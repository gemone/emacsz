const std = @import("std");
const protocol = @import("protocol.zig");

pub const MemorySink = struct {
    arena: std.heap.ArenaAllocator,
    messages: std.ArrayList([]const u8) = .empty,
    next_sequence: u64 = 1,

    /// Messages are owned by the internal arena and remain valid only until
    /// `deinit`.  Callers may retain the returned slice only within that
    /// lifetime.
    pub fn init(child: std.mem.Allocator) MemorySink {
        return .{ .arena = std.heap.ArenaAllocator.init(child) };
    }

    pub fn deinit(self: *MemorySink) void {
        self.arena.deinit();
    }

    pub fn send(
        self: *MemorySink,
        envelope_in: protocol.Envelope,
        payload: []const u8,
    ) ![]const u8 {
        const a = self.arena.allocator();
        var message: std.ArrayList(u8) = .empty;
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
        try self.messages.append(a, message.items);
        // Advance only after encoding and sink ownership have succeeded.
        self.next_sequence = next_sequence;
        return message.items;
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
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024 * 1024));
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
