const std = @import("std");
const protocol = @import("protocol.zig");

pub const max_retained_messages: usize = 256;

pub const MemorySink = struct {
    allocator: std.mem.Allocator,
    messages: std.ArrayList([]const u8) = .empty,
    next_sequence: u64 = 1,

    /// Messages are owned by the bounded sink.  A returned slice remains valid
    /// only until that message is evicted (after 256 newer messages) or
    /// `deinit` is called.
    pub fn init(child: std.mem.Allocator) MemorySink {
        return .{ .allocator = child };
    }

    pub fn deinit(self: *MemorySink) void {
        for (self.messages.items) |message| self.allocator.free(message);
        self.messages.deinit(self.allocator);
    }

    pub fn send(
        self: *MemorySink,
        envelope_in: protocol.Envelope,
        payload: []const u8,
    ) ![]const u8 {
        const a = self.allocator;
        var message: std.ArrayList(u8) = .empty;
        defer message.deinit(a);
        var envelope = envelope_in;
        var next_sequence = self.next_sequence;
        if (envelope.sequence == 0) {
            if (self.next_sequence == std.math.maxInt(u64)) return protocol.Error.Unsupported;
            envelope.sequence = self.next_sequence;
            next_sequence = self.next_sequence + 1;
        } else if (envelope.sequence >= self.next_sequence) {
            if (envelope.sequence == std.math.maxInt(u64)) return protocol.Error.Unsupported;
            next_sequence = envelope.sequence + 1;
        } else {
            return protocol.Error.InvalidSequence;
        }
        try protocol.encodeEnvelope(a, envelope, payload, &message);
        const retained = try a.dupe(u8, message.items);
        errdefer a.free(retained);
        try self.messages.append(a, retained);
        while (self.messages.items.len > max_retained_messages) {
            const oldest = self.messages.orderedRemove(0);
            a.free(oldest);
        }
        // Advance only after encoding and sink ownership have succeeded.
        self.next_sequence = next_sequence;
        return retained;
    }
};

pub const replay_magic = [4]u8{ 'E', 'R', 'P', '1' };

pub fn writeReplay(
    gpa: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    messages: []const []const u8,
) !void {
    if (messages.len > std.math.maxInt(u32)) return protocol.Error.Unsupported;
    var file: std.ArrayList(u8) = .empty;
    defer file.deinit(gpa);
    try file.appendSlice(gpa, &replay_magic);
    var count: [4]u8 = undefined;
    std.mem.writeInt(u32, &count, @intCast(messages.len), .little);
    try file.appendSlice(gpa, &count);
    for (messages) |message| {
        if (message.len > std.math.maxInt(u32)) return protocol.Error.Unsupported;
        var length: [4]u8 = undefined;
        std.mem.writeInt(u32, &length, @intCast(message.len), .little);
        try file.appendSlice(gpa, &length);
        try file.appendSlice(gpa, message);
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = file.items });
}

pub fn readReplay(gpa: std.mem.Allocator, io: std.Io, path: []const u8) ![][]const u8 {
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileTooBig, error.StreamTooLong => return protocol.Error.Unsupported,
        else => return err,
    };
    defer gpa.free(data);
    if (data.len < 8 or !std.mem.eql(u8, data[0..4], &replay_magic))
        return protocol.Error.InvalidEnvelope;
    var offset: usize = 4;
    const count = std.mem.readInt(u32, data[offset..][0..4], .little);
    offset += 4;
    if (count > (data.len -| offset) / 4) return protocol.Error.InvalidEnvelope;
    const messages = try gpa.alloc([]const u8, count);
    var owned_count: usize = 0;
    errdefer {
        for (messages[0..owned_count]) |message| gpa.free(message);
        gpa.free(messages);
    }
    for (messages) |*message| {
        if (4 > data.len -| offset) return protocol.Error.TrailingBytes;
        const length = std.mem.readInt(u32, data[offset..][0..4], .little);
        offset += 4;
        if (length > data.len -| offset) return protocol.Error.TrailingBytes;
        const copy = try gpa.dupe(u8, data[offset..][0..length]);
        offset += length;
        message.* = copy;
        owned_count += 1;
    }
    return messages;
}

pub fn freeReplay(gpa: std.mem.Allocator, messages: [][]const u8) void {
    for (messages) |message| gpa.free(message);
    gpa.free(messages);
}

test "memory sink assigns ordered sequences" {
    const protocol_mod = protocol;
    var sink = MemorySink.init(std.testing.allocator);
    defer sink.deinit();
    const first = try sink.send(.{
        .flags = 0,
        .message_type = protocol_mod.Message.hello,
        .sequence = 0,
        .ack_sequence = 0,
        .session_id = 8,
        .timestamp_ns = 1,
    }, &[_]u8{});
    const second = try sink.send(.{
        .flags = 0,
        .message_type = protocol_mod.Message.hello_ack,
        .sequence = 0,
        .ack_sequence = 1,
        .session_id = 8,
        .timestamp_ns = 2,
    }, &[_]u8{});
    try std.testing.expectEqual(@as(u64, 1), (try protocol_mod.decodeEnvelope(first)).envelope.sequence);
    try std.testing.expectEqual(@as(u64, 2), (try protocol_mod.decodeEnvelope(second)).envelope.sequence);
}

test "memory sink rejects stale and duplicate producer sequences" {
    const protocol_mod = protocol;
    var sink = MemorySink.init(std.testing.allocator);
    defer sink.deinit();
    const first = try sink.send(.{
        .flags = 0,
        .message_type = protocol_mod.Message.hello,
        .sequence = 0,
        .ack_sequence = 0,
        .session_id = 1,
        .timestamp_ns = 1,
    }, &[_]u8{});
    try std.testing.expectEqual(@as(u64, 1), (try protocol_mod.decodeEnvelope(first)).envelope.sequence);
    try std.testing.expectError(
        protocol.Error.InvalidSequence,
        sink.send(.{
            .flags = 0,
            .message_type = protocol_mod.Message.hello_ack,
            .sequence = 1,
            .ack_sequence = 0,
            .session_id = 1,
            .timestamp_ns = 2,
        }, &[_]u8{}),
    );
}

test "replay file round trip" {
    const a = std.testing.allocator;
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try std.fmt.allocPrint(a, ".zig-cache/tmp/{s}/roundtrip", .{tmp.sub_path});
    defer a.free(path);
    const messages = [_][]const u8{ "first", "", "third-message" };
    try writeReplay(a, io, path, &messages);

    const loaded = try readReplay(a, io, path);
    defer freeReplay(a, loaded);
    try std.testing.expectEqual(messages.len, loaded.len);
    try std.testing.expectEqualStrings(messages[0], loaded[0]);
    try std.testing.expectEqualStrings(messages[1], loaded[1]);
    try std.testing.expectEqualStrings(messages[2], loaded[2]);
}

test "replay file rejects bad count short length and oversized input" {
    const a = std.testing.allocator;
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const prefix = try std.fmt.allocPrint(a, ".zig-cache/tmp/{s}/", .{tmp.sub_path});
    defer a.free(prefix);

    const bad_count = [_]u8{ 'E', 'R', 'P', '1', 0xff, 0xff, 0xff, 0xff };
    const bad_count_path = try std.fmt.allocPrint(a, "{s}bad-count", .{prefix});
    defer a.free(bad_count_path);
    try tmp.dir.writeFile(io, .{ .sub_path = "bad-count", .data = &bad_count });
    try std.testing.expectError(protocol.Error.InvalidEnvelope, readReplay(a, io, bad_count_path));

    const short_length = [_]u8{ 'E', 'R', 'P', '1', 1, 0, 0, 0, 8, 0, 0, 0, 1, 2 };
    const short_path = try std.fmt.allocPrint(a, "{s}short-length", .{prefix});
    defer a.free(short_path);
    try tmp.dir.writeFile(io, .{ .sub_path = "short-length", .data = &short_length });
    try std.testing.expectError(protocol.Error.TrailingBytes, readReplay(a, io, short_path));

    const truncated = [_]u8{ 'E', 'R', 'P', '1', 1, 0, 0, 0 };
    const truncated_path = try std.fmt.allocPrint(a, "{s}truncated", .{prefix});
    defer a.free(truncated_path);
    try tmp.dir.writeFile(io, .{ .sub_path = "truncated", .data = &truncated });
    try std.testing.expectError(protocol.Error.InvalidEnvelope, readReplay(a, io, truncated_path));

    const oversized_size = 64 * 1024 * 1024 + 1;
    const oversized = try a.alloc(u8, oversized_size);
    defer a.free(oversized);
    @memset(oversized, 'R');
    const oversized_path = try std.fmt.allocPrint(a, "{s}oversized", .{prefix});
    defer a.free(oversized_path);
    try tmp.dir.writeFile(io, .{ .sub_path = "oversized", .data = oversized });
    try std.testing.expectError(protocol.Error.Unsupported, readReplay(a, io, oversized_path));
}

test "memory sink evicts oldest messages beyond bound" {
    const a = std.testing.allocator;
    var sink = MemorySink.init(a);
    defer sink.deinit();
    for (0..max_retained_messages + 1) |i| {
        var sequence: [8]u8 = undefined;
        std.mem.writeInt(u64, &sequence, i, .little);
        _ = try sink.send(.{
            .flags = 0,
            .message_type = protocol.Message.hello,
            .sequence = 0,
            .ack_sequence = 0,
            .session_id = 1,
            .timestamp_ns = 0,
        }, &sequence);
    }
    try std.testing.expectEqual(max_retained_messages, sink.messages.items.len);
    try std.testing.expectEqual(@as(u64, 2), (try protocol.decodeEnvelope(sink.messages.items[0])).envelope.sequence);
    try std.testing.expectEqual(@as(u64, max_retained_messages + 1), (try protocol.decodeEnvelope(sink.messages.items[max_retained_messages - 1])).envelope.sequence);
}
