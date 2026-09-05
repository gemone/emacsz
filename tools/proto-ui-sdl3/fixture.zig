//! Converts observed public Emacs frame facts into an ERP1 EUP replay.

const std = @import("std");
const proto_ui = @import("proto_ui");
const protocol = proto_ui.protocol;
const frontend = proto_ui.frontend;
const transport = proto_ui.transport;

const FrameFacts = struct {
    frame_width: i32,
    frame_height: i32,
    window_width: i32,
    window_height: i32,
};

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var args = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer args.deinit();
    _ = args.next();
    const facts_path = args.next() orelse return error.MissingFactsPath;
    const path = args.next() orelse return error.MissingReplayPath;
    if (args.next() != null) return error.UnexpectedArgument;

    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();

    const facts_bytes = try std.Io.Dir.cwd().readFileAlloc(
        io,
        facts_path,
        gpa,
        .limited(64 * 1024),
    );
    defer gpa.free(facts_bytes);
    const parsed = try std.json.parseFromSlice(FrameFacts, gpa, facts_bytes, .{});
    defer parsed.deinit();
    const facts = parsed.value;
    if (facts.frame_width <= 0 or facts.frame_height <= 0 or
        facts.window_width <= 0 or facts.window_height <= 0 or
        facts.window_width > facts.frame_width or
        facts.window_height > facts.frame_height)
        return error.InvalidFrameFacts;

    var sink = transport.MemorySink.init(gpa);
    defer sink.deinit();

    var create_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, create_payload[0..4], 1, .little);
    std.mem.writeInt(u32, create_payload[4..8], 1, .little);
    _ = try sink.send(.{
        .flags = 0,
        .message_type = protocol.Message.frame_create,
        .sequence = 0,
        .ack_sequence = 0,
        .session_id = 0x1001,
        .frame_id = 1,
        .timestamp_ns = 1,
    }, &create_payload);

    var window_bytes: std.ArrayList(u8) = .empty;
    defer window_bytes.deinit(gpa);
    const window_width = @min(facts.window_width, facts.frame_width);
    const window_height = @min(facts.window_height, facts.frame_height);
    try frontend.encodeWindow(gpa, .{ .id = 1001, .frame_id = 1, .x = 0, .y = 0, .width = window_width, .height = window_height }, &window_bytes);

    var row_bytes: std.ArrayList(u8) = .empty;
    defer row_bytes.deinit(gpa);
    const row_count: i32 = 15;
    const row_height = @max(1, @divTrunc(window_height, row_count));
    for (0..15) |index| {
        try frontend.encodeRow(gpa, .{
            .window_id = 1001,
            .index = @intCast(index),
            .flags = 0,
            .x = 0,
            .y = @intCast(index * row_height),
            .width = window_width,
            .height = row_height,
            .ascent = 16,
            .descent = 5,
            .baseline = 16,
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
        .height = 18,
        .kind = 1,
        .visible = true,
        .active = true,
    }, &cursor_bytes);

    var damage_bytes: std.ArrayList(u8) = .empty;
    defer damage_bytes.deinit(gpa);
    try frontend.encodeRect(gpa, .{ .x = 0, .y = 0, .width = facts.frame_width, .height = facts.frame_height }, &damage_bytes);

    var present_bytes: std.ArrayList(u8) = .empty;
    defer present_bytes.deinit(gpa);
    try frontend.encodePresentHint(gpa, .{ .mode = 0, .flags = 0, .deadline_ns = 0 }, &present_bytes);

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
            .sequence = 2,
            .redisplay_generation = 1,
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
            .timestamp_ns = 2,
        },
        .sections = &sections,
    }, &update_payload);

    _ = try sink.send(.{
        .flags = protocol.Flags.delta | protocol.Flags.coalescable,
        .message_type = protocol.Message.frame_update,
        .sequence = 0,
        .ack_sequence = 0,
        .session_id = 0x1001,
        .frame_id = 1,
        .timestamp_ns = 2,
    }, update_payload.items);

    try transport.writeReplay(gpa, io, path, sink.messages.items);
    std.debug.print("sdl3 fixture: encoded Emacs facts {d}x{d} into {d} EUP messages at {s}\n", .{
        facts.frame_width,
        facts.frame_height,
        sink.messages.items.len,
        path,
    });
}
