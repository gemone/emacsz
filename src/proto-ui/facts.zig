//! Adapter-owned conversion for public Emacs frame facts.
//!
//! Facts are observed through public Lisp APIs, validated, then translated to a
//! complete EUP snapshot so SDL can consume them through the same Scene rules
//! as any other FRAME_UPDATE.

const std = @import("std");
const frontend = @import("frontend.zig");
const protocol = @import("protocol.zig");

pub const FrameFacts = struct {
    frame_width: i32,
    frame_height: i32,
    window_width: i32,
    window_height: i32,
};

pub const CursorFacts = struct {
    line: i32,
    column: i32,
};

pub const max_text_lines: usize = 32;
pub const max_text_columns: usize = 120;

pub const TextLines = struct {
    lines: [][]const u8 = &.{},
    owner: []u8 = &.{},

    pub fn deinit(self: *TextLines, gpa: std.mem.Allocator) void {
        if (self.lines.len != 0) gpa.free(self.lines);
        if (self.owner.len != 0) gpa.free(self.owner);
        self.* = .{};
    }

    pub fn eql(self: TextLines, other: TextLines) bool {
        if (self.lines.len != other.lines.len) return false;
        for (self.lines, other.lines) |left, right| {
            if (!std.mem.eql(u8, left, right)) return false;
        }
        return true;
    }
};

pub const Snapshot = struct {
    facts: FrameFacts,
    text: TextLines = .{},
    cursor: CursorFacts = .{ .line = 0, .column = 0 },

    pub fn eql(left: Snapshot, right: Snapshot) bool {
        return factsEql(left.facts, right.facts) and left.text.eql(right.text) and
            std.meta.eql(left.cursor, right.cursor);
    }

    pub fn deinit(self: *Snapshot, gpa: std.mem.Allocator) void {
        self.text.deinit(gpa);
    }
};
pub const Error = std.json.ParseError(std.json.Scanner) || error{InvalidFrameFacts};

const SnapshotWire = struct {
    frame_width: i32,
    frame_height: i32,
    window_width: i32,
    window_height: i32,
    text: []const []const u8 = &.{},
    cursor: CursorFacts = .{ .line = 1, .column = 0 },
};

pub fn factsEql(left: FrameFacts, right: FrameFacts) bool {
    return std.meta.eql(left, right);
}

pub fn parse(gpa: std.mem.Allocator, bytes: []const u8) Error!FrameFacts {
    const parsed = try std.json.parseFromSlice(FrameFacts, gpa, bytes, .{});
    defer parsed.deinit();
    const facts = parsed.value;
    if (facts.frame_width <= 0 or facts.frame_height <= 0 or
        facts.window_width <= 0 or facts.window_height <= 0 or
        facts.window_width > facts.frame_width or
        facts.window_height > facts.frame_height) return error.InvalidFrameFacts;
    return facts;
}

pub fn parseText(gpa: std.mem.Allocator, bytes: []const u8) !TextLines {
    var count: usize = 0;
    var total: usize = 0;
    var lines: [max_text_lines][]const u8 = undefined;
    const body = if (std.mem.endsWith(u8, bytes, "\n")) bytes[0 .. bytes.len - 1] else bytes;
    var iterator = std.mem.splitScalar(u8, body, '\n');
    while (iterator.next()) |line| {
        if (count == max_text_lines or line.len > max_text_columns) return error.InvalidTextFacts;
        for (line) |byte| {
            if (byte < 0x20 or byte > 0x7e) return error.InvalidTextFacts;
        }
        lines[count] = line;
        total += line.len;
        count += 1;
    }

    const slices = try gpa.alloc([]const u8, count);
    errdefer gpa.free(slices);
    const owner = try gpa.alloc(u8, total);
    errdefer gpa.free(owner);
    var offset: usize = 0;
    for (lines[0..count], 0..) |line, index| {
        @memcpy(owner[offset..][0..line.len], line);
        slices[index] = owner[offset..][0..line.len];
        offset += line.len;
    }
    return .{ .lines = slices, .owner = owner };
}

pub fn parseCursor(gpa: std.mem.Allocator, bytes: []const u8) !CursorFacts {
    const parsed = try std.json.parseFromSlice(CursorFacts, gpa, bytes, .{});
    defer parsed.deinit();
    const cursor = parsed.value;
    if (cursor.line < 1 or cursor.column < 0 or
        cursor.line >= @as(i32, @intCast(max_text_lines)) or
        cursor.column > @as(i32, @intCast(max_text_columns))) return error.InvalidCursorFacts;
    return cursor;
}

pub fn parseSnapshot(gpa: std.mem.Allocator, bytes: []const u8) !Snapshot {
    const parsed = try std.json.parseFromSlice(SnapshotWire, gpa, bytes, .{});
    defer parsed.deinit();
    const wire = parsed.value;
    if (wire.frame_width <= 0 or wire.frame_height <= 0 or
        wire.window_width <= 0 or wire.window_height <= 0 or
        wire.window_width > wire.frame_width or
        wire.window_height > wire.frame_height) return error.InvalidFrameFacts;
    if (wire.text.len > max_text_lines) return error.InvalidTextFacts;
    for (wire.text) |line| {
        if (line.len > max_text_columns) return error.InvalidTextFacts;
        for (line) |byte| {
            if (byte < 0x20 or byte > 0x7e) return error.InvalidTextFacts;
        }
    }
    if (wire.cursor.line < 1 or wire.cursor.line > max_text_lines or
        wire.cursor.column < 0 or wire.cursor.column > max_text_columns)
        return error.InvalidCursorFacts;

    const slices = try gpa.alloc([]const u8, wire.text.len);
    errdefer gpa.free(slices);
    var total: usize = 0;
    for (wire.text) |line| total += line.len;
    const owner = try gpa.alloc(u8, total);
    errdefer gpa.free(owner);
    var offset: usize = 0;
    for (wire.text, 0..) |line, index| {
        @memcpy(owner[offset..][0..line.len], line);
        slices[index] = owner[offset..][0..line.len];
        offset += line.len;
    }
    return .{
        .facts = .{
            .frame_width = wire.frame_width,
            .frame_height = wire.frame_height,
            .window_width = wire.window_width,
            .window_height = wire.window_height,
        },
        .text = .{ .lines = slices, .owner = owner },
        .cursor = wire.cursor,
    };
}

test "unchanged facts compare equal for publisher coalescing" {
    const first = FrameFacts{ .frame_width = 80, .frame_height = 25, .window_width = 80, .window_height = 23 };
    var second = first;
    try std.testing.expect(factsEql(first, second));
    second.window_height += 1;
    try std.testing.expect(!factsEql(first, second));
}

pub fn buildScene(gpa: std.mem.Allocator, facts: FrameFacts, snapshot_index: u64) !frontend.Scene {
    if (facts.frame_width <= 0 or facts.frame_height <= 0 or
        facts.window_width <= 0 or facts.window_height <= 0 or
        facts.window_width > facts.frame_width or
        facts.window_height > facts.frame_height) return error.InvalidFrameFacts;

    var scene = frontend.Scene.init(gpa);
    errdefer scene.deinit();
    const sequence: u64 = std.math.mul(u64, snapshot_index, 2) catch return error.OutOfMemory;
    const create_sequence = sequence + 1;
    const update_sequence = sequence + 2;

    var create_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, create_payload[0..4], 1, .little);
    std.mem.writeInt(u32, create_payload[4..8], 1, .little);
    var create_message: std.ArrayList(u8) = .empty;
    defer create_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_create,
        .sequence = create_sequence,
        .ack_sequence = 0,
        .session_id = 0x1001,
        .frame_id = 1,
        .timestamp_ns = create_sequence,
    }, &create_payload, &create_message);
    try scene.apply(create_message.items);

    var window_bytes: std.ArrayList(u8) = .empty;
    defer window_bytes.deinit(gpa);
    try frontend.encodeWindow(gpa, .{
        .id = 1001,
        .frame_id = 1,
        .x = 0,
        .y = 0,
        .width = facts.window_width,
        .height = facts.window_height,
    }, &window_bytes);

    var row_bytes: std.ArrayList(u8) = .empty;
    defer row_bytes.deinit(gpa);
    const row_count: i32 = 15;
    const row_height = @max(1, @divTrunc(facts.window_height, row_count));
    var row_index: i32 = 0;
    while (row_index < row_count) : (row_index += 1) {
        try frontend.encodeRow(gpa, .{
            .window_id = 1001,
            .index = @intCast(row_index),
            .flags = 0,
            .x = 0,
            .y = row_index * row_height,
            .width = facts.window_width,
            .height = row_height,
            .ascent = @min(16, row_height),
            .descent = row_height - @min(16, row_height),
            .baseline = @min(16, row_height),
            .visible_height = row_height,
        }, &row_bytes);
    }

    var cursor_bytes: std.ArrayList(u8) = .empty;
    defer cursor_bytes.deinit(gpa);
    try frontend.encodeCursor(gpa, .{
        .window_id = 1001,
        .x = 8,
        .y = row_height,
        .width = 2,
        .height = @max(2, @min(18, row_height)),
        .kind = 1,
        .visible = true,
        .active = true,
    }, &cursor_bytes);

    var damage_bytes: std.ArrayList(u8) = .empty;
    defer damage_bytes.deinit(gpa);
    try frontend.encodeRect(gpa, .{
        .x = 0,
        .y = 0,
        .width = facts.frame_width,
        .height = facts.frame_height,
    }, &damage_bytes);

    var present_bytes: std.ArrayList(u8) = .empty;
    defer present_bytes.deinit(gpa);
    try frontend.encodePresentHint(gpa, .{
        .mode = 0,
        .flags = 0,
        .deadline_ns = 0,
    }, &present_bytes);

    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = window_bytes.items },
        .{ .kind = protocol.SectionKind.rows, .records = row_bytes.items },
        .{ .kind = protocol.SectionKind.cursors, .records = cursor_bytes.items },
        .{ .kind = protocol.SectionKind.damage, .records = damage_bytes.items },
        .{ .kind = protocol.SectionKind.present_hint, .records = present_bytes.items },
    };
    var update_payload: std.ArrayList(u8) = .empty;
    defer update_payload.deinit(gpa);
    try protocol.encodeFrameUpdate(gpa, .{
        .header = .{
            .frame_id = 1,
            .frame_generation = 1,
            .sequence = update_sequence,
            .redisplay_generation = snapshot_index + 1,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = facts.frame_width,
            .logical_height = facts.frame_height,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = facts.frame_width,
            .physical_height = facts.frame_height,
            .scale = 1,
            .dpi_x = 96,
            .dpi_y = 96,
            .damage_mode = 2,
            .update_cause = 1,
            .coalesced_count = 0,
            .timestamp_ns = update_sequence,
        },
        .sections = &sections,
    }, &update_payload);
    var update_message: std.ArrayList(u8) = .empty;
    defer update_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.delta | protocol.Flags.coalescable,
        .message_type = protocol.Message.frame_update,
        .sequence = update_sequence,
        .ack_sequence = 0,
        .session_id = 0x1001,
        .frame_id = 1,
        .timestamp_ns = update_sequence,
    }, update_payload.items, &update_message);
    try scene.apply(update_message.items);
    if (scene.stats.frame_updates != 1) return error.InvalidFrameFacts;
    return scene;
}

/// Encodes and validates a transport snapshot in `scene`, returning owned EUP
/// messages. The first snapshot includes `FRAME_CREATE`; later ones are
/// update-only and inherit the scene's contiguous sequence.
pub fn appendWireSnapshot(
    gpa: std.mem.Allocator,
    facts: FrameFacts,
    text: []const []const u8,
    cursor: CursorFacts,
    scene: *frontend.Scene,
    messages: *std.ArrayList([]const u8),
) !void {
    if (facts.frame_width <= 0 or facts.frame_height <= 0 or
        facts.window_width <= 0 or facts.window_height <= 0 or
        facts.window_width > facts.frame_width or
        facts.window_height > facts.frame_height) return error.InvalidFrameFacts;

    const initial = scene.frame == null;
    var sequence = scene.next_sequence orelse 1;

    if (initial) {
        var create_payload: [8]u8 = undefined;
        std.mem.writeInt(u32, create_payload[0..4], 1, .little);
        std.mem.writeInt(u32, create_payload[4..8], 1, .little);
        var create_message: std.ArrayList(u8) = .empty;
        defer create_message.deinit(gpa);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.frame_create,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = 0x1001,
            .frame_id = 1,
            .timestamp_ns = sequence,
        }, &create_payload, &create_message);
        const retained_create = try gpa.dupe(u8, create_message.items);
        messages.append(gpa, retained_create) catch |err| {
            gpa.free(retained_create);
            return err;
        };
        try scene.apply(retained_create);
        sequence += 1;
    }

    const update_sequence = sequence;
    var window_bytes: std.ArrayList(u8) = .empty;
    defer window_bytes.deinit(gpa);
    try frontend.encodeWindow(gpa, .{
        .id = 1001,
        .frame_id = 1,
        .x = 0,
        .y = 0,
        .width = facts.window_width,
        .height = facts.window_height,
    }, &window_bytes);

    var row_bytes: std.ArrayList(u8) = .empty;
    defer row_bytes.deinit(gpa);
    const row_count: i32 = 15;
    const row_height = @max(1, @divTrunc(facts.window_height, row_count));
    if (cursor.line < 1 or cursor.line > row_count or
        cursor.column * 8 + 2 > facts.window_width)
        return error.InvalidCursorFacts;
    var row_index: i32 = 0;
    while (row_index < row_count) : (row_index += 1) {
        try frontend.encodeRow(gpa, .{
            .window_id = 1001,
            .index = @intCast(row_index),
            .flags = 0,
            .x = 0,
            .y = row_index * row_height,
            .width = facts.window_width,
            .height = row_height,
            .ascent = @min(16, row_height),
            .descent = row_height - @min(16, row_height),
            .baseline = @min(16, row_height),
            .visible_height = row_height,
        }, &row_bytes);
    }

    var cursor_bytes: std.ArrayList(u8) = .empty;
    defer cursor_bytes.deinit(gpa);
    try frontend.encodeCursor(gpa, .{
        .window_id = 1001,
        .x = cursor.column * 8,
        .y = (cursor.line - 1) * row_height,
        .width = 2,
        .height = @max(2, @min(18, row_height)),
        .kind = 1,
        .visible = true,
        .active = true,
    }, &cursor_bytes);

    var damage_bytes: std.ArrayList(u8) = .empty;
    defer damage_bytes.deinit(gpa);
    try frontend.encodeRect(gpa, .{
        .x = 0,
        .y = 0,
        .width = facts.frame_width,
        .height = facts.frame_height,
    }, &damage_bytes);

    var present_bytes: std.ArrayList(u8) = .empty;
    defer present_bytes.deinit(gpa);
    try frontend.encodePresentHint(gpa, .{
        .mode = 0,
        .flags = 0,
        .deadline_ns = 0,
    }, &present_bytes);

    var text_bytes: std.ArrayList(u8) = .empty;
    defer text_bytes.deinit(gpa);
    if (text.len > max_text_lines) return error.InvalidTextFacts;
    for (text, 0..) |line, index| {
        if (line.len > max_text_columns) return error.InvalidTextFacts;
        try frontend.encodeTextLine(gpa, .{ .row_index = @intCast(index), .line = line }, &text_bytes);
    }

    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = window_bytes.items },
        .{ .kind = protocol.SectionKind.rows, .records = row_bytes.items },
        .{ .kind = protocol.SectionKind.cursors, .records = cursor_bytes.items },
        .{ .kind = protocol.SectionKind.extension_min, .records = text_bytes.items },
        .{ .kind = protocol.SectionKind.damage, .records = damage_bytes.items },
        .{ .kind = protocol.SectionKind.present_hint, .records = present_bytes.items },
    };
    var update_payload: std.ArrayList(u8) = .empty;
    defer update_payload.deinit(gpa);
    try protocol.encodeFrameUpdate(gpa, .{
        .header = .{
            .frame_id = 1,
            .frame_generation = 1,
            .sequence = update_sequence,
            .redisplay_generation = scene.stats.frame_updates + 1,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = facts.frame_width,
            .logical_height = facts.frame_height,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = facts.frame_width,
            .physical_height = facts.frame_height,
            .scale = 1,
            .dpi_x = 96,
            .dpi_y = 96,
            .damage_mode = 2,
            .update_cause = 1,
            .coalesced_count = 0,
            .timestamp_ns = update_sequence,
        },
        .sections = &sections,
    }, &update_payload);

    var update_message: std.ArrayList(u8) = .empty;
    defer update_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.delta | protocol.Flags.coalescable,
        .message_type = protocol.Message.frame_update,
        .sequence = update_sequence,
        .ack_sequence = 0,
        .session_id = scene.session_id orelse 0x1001,
        .frame_id = 1,
        .timestamp_ns = update_sequence,
    }, update_payload.items, &update_message);
    const retained_update = try gpa.dupe(u8, update_message.items);
    messages.append(gpa, retained_update) catch |err| {
        gpa.free(retained_update);
        return err;
    };
    try scene.apply(retained_update);
}

test "parses and validates bounded frame facts" {
    const a = std.testing.allocator;
    const facts = try parse(a, "{\"frame_width\":100,\"frame_height\":80,\"window_width\":90,\"window_height\":70}");
    try std.testing.expectEqual(@as(i32, 100), facts.frame_width);
    try std.testing.expectError(error.InvalidFrameFacts, parse(a, "{\"frame_width\":0,\"frame_height\":80,\"window_width\":0,\"window_height\":0}"));
}

test "builds a validated EUP snapshot scene" {
    const a = std.testing.allocator;
    const facts = try parse(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75}");
    var scene = try buildScene(a, facts, 3);
    defer scene.deinit();
    try std.testing.expectEqual(@as(u64, 1), scene.stats.frame_updates);
    try std.testing.expectEqual(@as(usize, 1), scene.windows.items.len);
    try std.testing.expectEqual(@as(usize, 15), scene.rows.items.len);
    try std.testing.expectEqual(@as(i32, 110), scene.windows.items[0].width);
}

test "wire snapshots advance contiguous scene sequences" {
    const a = std.testing.allocator;
    const parsed = try parse(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75}");
    const invalid = FrameFacts{ .frame_width = 0, .frame_height = 90, .window_width = 0, .window_height = 0 };
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var empty_scene = frontend.Scene.init(a);
    defer empty_scene.deinit();
    try std.testing.expectError(error.InvalidFrameFacts, appendWireSnapshot(a, invalid, &.{}, .{ .line = 1, .column = 0 }, &empty_scene, &messages));

    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshot(a, parsed, &.{}, .{ .line = 1, .column = 0 }, &scene, &messages);
    try std.testing.expectEqual(@as(usize, 2), messages.items.len);
    try std.testing.expectEqual(@as(u64, 1), scene.stats.frame_updates);
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);

    try appendWireSnapshot(a, parsed, &.{}, .{ .line = 1, .column = 0 }, &scene, &messages);
    try std.testing.expectEqual(@as(usize, 3), messages.items.len);
    try std.testing.expectEqual(@as(u64, 2), scene.stats.frame_updates);
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);
}

test "wire snapshot carries validated public text lines" {
    const a = std.testing.allocator;
    const parsed = try parse(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75}");
    var text = try parseText(a, "Emacs Proto-UI\nvisible ASCII\n");
    defer text.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), text.lines.len);
    try std.testing.expectEqualStrings("visible ASCII", text.lines[1]);

    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshot(a, parsed, text.lines, .{ .line = 1, .column = 1 }, &scene, &messages);
    try std.testing.expectEqual(@as(usize, 2), scene.text.items.len);
    try std.testing.expectEqualStrings("Emacs Proto-UI", scene.text.items[0].bytes);
    try std.testing.expectEqualStrings("visible ASCII", scene.text.items[1].bytes);
    try std.testing.expectEqual(@as(i32, 8), scene.cursor.?.x);
    try std.testing.expectEqual(@as(i32, 0), scene.cursor.?.y);
    try std.testing.expectError(error.InvalidTextFacts, parseText(a, "bad\n\x00"));

    const narrow = FrameFacts{ .frame_width = 9, .frame_height = 90, .window_width = 9, .window_height = 75 };
    try std.testing.expectError(error.InvalidCursorFacts, appendWireSnapshot(a, narrow, text.lines, .{ .line = 1, .column = 1 }, &scene, &messages));
}

test "parses and validates bounded cursor facts" {
    const a = std.testing.allocator;
    const cursor = try parseCursor(a, "{\"line\":2,\"column\":17}");
    try std.testing.expectEqual(@as(i32, 2), cursor.line);
    try std.testing.expectEqual(@as(i32, 17), cursor.column);
    try std.testing.expectError(error.InvalidCursorFacts, parseCursor(a, "{\"line\":-1,\"column\":0}"));
    try std.testing.expectError(error.InvalidCursorFacts, parseCursor(a, "{\"line\":0,\"column\":0}"));
    try std.testing.expectError(error.InvalidCursorFacts, parseCursor(a, "{\"line\":32,\"column\":0}"));
}
