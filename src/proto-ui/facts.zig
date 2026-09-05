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

pub const Error = std.json.ParseError(std.json.Scanner) || error{InvalidFrameFacts};

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
