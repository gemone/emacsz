//! Candidate R8 runtime-host adapter artifact.
//!
//! The library can operate an adapter session against an explicitly supplied,
//! validated `PureRuntimeHostV1` table.  It has no load-time initializer and
//! no way to register an Emacs terminal; inherited Emacs never calls it.  The
//! legacy no-argument create export remains fail closed so linkage alone can
//! never enable `output_proto` runtime.

const std = @import("std");
const runtime_host = @import("runtime_host.zig");
const terminal = @import("terminal.zig");
const terminal_service = @import("terminal_service.zig");
const frontend = @import("frontend.zig");
const protocol = @import("protocol.zig");

pub const result_ok: c_int = 0;
pub const result_invalid: c_int = 1;
pub const result_host_failed: c_int = 2;
pub const result_invalid_handle: c_int = 3;
pub const result_invalid_state: c_int = 4;
pub const result_allocation_failed: c_int = 5;

const AdapterSession = struct {
    table: runtime_host.PureRuntimeHostV1,
    terminals: terminal.TerminalRegistry = .{},
    service: terminal_service.TerminalService = undefined,
};

fn resultCode(err: anyerror) c_int {
    return switch (err) {
        error.InvalidRuntimeHost, error.InvalidHostIdentity => result_invalid,
        error.HostCallbackFailed => result_host_failed,
        error.InvalidServiceState, error.InvalidHostTerminal => result_invalid_state,
        error.OutOfMemory => result_allocation_failed,
        else => result_host_failed,
    };
}

fn session(handle: ?*anyopaque) ?*AdapterSession {
    return @ptrCast(@alignCast(handle));
}

export fn proto_ui_runtime_host_adapter_abi_version() u32 {
    return runtime_host.abi_version;
}

export fn proto_ui_runtime_host_adapter_table_size() usize {
    return @sizeOf(runtime_host.PureRuntimeHostV1);
}

export fn proto_ui_runtime_host_adapter_validate(
    table: ?*const runtime_host.PureRuntimeHostV1,
) c_int {
    runtime_host.validateTable(table) catch return result_invalid;
    return result_ok;
}

export fn proto_ui_runtime_host_adapter_create() c_int {
    // Registration is the R8 activation boundary.  No explicit registration
    // path exists, so the legacy no-table creation remains unavailable.
    return result_invalid_state;
}

export fn proto_ui_runtime_host_adapter_session_create(
    table: ?*const runtime_host.PureRuntimeHostV1,
    out: ?*?*anyopaque,
) c_int {
    if (out == null) return result_invalid;
    out.?.* = null;
    runtime_host.validateTable(table) catch return result_invalid;
    const storage = std.heap.c_allocator.create(AdapterSession) catch
        return result_allocation_failed;
    storage.* = .{ .table = table.?.* };
    storage.service = terminal_service.TerminalService.init(
        storage.table,
        &storage.terminals,
    ) catch |err| {
        std.heap.c_allocator.destroy(storage);
        return resultCode(err);
    };
    out.?.* = storage;
    return result_ok;
}

export fn proto_ui_runtime_host_adapter_session_activate(
    handle: ?*anyopaque,
    out_terminal: ?*runtime_host.Identity,
) c_int {
    const adapter = session(handle) orelse return result_invalid_handle;
    if (out_terminal) |out| out.* = .{};
    const created = adapter.service.create(terminal.initial_generation) catch |err|
        return resultCode(err);
    const active = adapter.service.activate() catch |err| {
        adapter.service.cancelActivation() catch {};
        return resultCode(err);
    };
    if (out_terminal) |out| out.* = .{
        .id = active.id,
        .generation = active.generation,
    };
    _ = created;
    return result_ok;
}

export fn proto_ui_runtime_host_adapter_session_drain(
    handle: ?*anyopaque,
) c_int {
    const adapter = session(handle) orelse return result_invalid_handle;
    _ = adapter.service.drain() catch |err| return resultCode(err);
    return result_ok;
}

export fn proto_ui_runtime_host_adapter_session_destroy(handle: ?*anyopaque) c_int {
    const adapter = session(handle) orelse return result_invalid_handle;
    switch (adapter.service.state) {
        .idle => {},
        .registering => adapter.service.cancelActivation() catch |err|
            return resultCode(err),
        .active, .draining => {
            _ = adapter.service.drain() catch |err| return resultCode(err);
        },
        .rollback_pending => adapter.service.completeRollback() catch |err|
            return resultCode(err),
    }
    std.heap.c_allocator.destroy(adapter);
    return result_ok;
}

test "legacy no-table creation remains blocked" {
    var host: runtime_host.FakeHost = undefined;
    const valid_table = runtime_host.fakeTable(&host);
    const create: *const fn () callconv(.c) c_int = proto_ui_runtime_host_adapter_create;
    try std.testing.expectEqual(@as(c_int, 0), proto_ui_runtime_host_adapter_validate(&valid_table));
    try std.testing.expectEqual(@as(c_int, 1), proto_ui_runtime_host_adapter_validate(null));
    try std.testing.expectEqual(result_invalid_state, create());
}

test "candidate session drives host terminal lifecycle without registration" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(result_ok, proto_ui_runtime_host_adapter_session_create(&table, &handle));
    try std.testing.expect(handle != null);

    var host_terminal: runtime_host.Identity = .{};
    try std.testing.expectEqual(result_ok, proto_ui_runtime_host_adapter_session_activate(handle, &host_terminal));
    try std.testing.expect(host_terminal.valid());
    try std.testing.expectEqual(runtime_host.TerminalState.active, host.terminal);

    try std.testing.expectEqual(result_ok, proto_ui_runtime_host_adapter_session_drain(handle));
    try std.testing.expectEqual(runtime_host.TerminalState.deleted, host.terminal);
    try std.testing.expectEqual(result_ok, proto_ui_runtime_host_adapter_session_destroy(handle));
}

test "candidate session rejects null and invalid handles" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(result_invalid, proto_ui_runtime_host_adapter_session_create(null, &handle));
    try std.testing.expectEqual(result_invalid, proto_ui_runtime_host_adapter_session_create(&table, null));
    try std.testing.expectEqual(result_invalid_handle, proto_ui_runtime_host_adapter_session_activate(null, null));
    try std.testing.expectEqual(result_invalid_handle, proto_ui_runtime_host_adapter_session_drain(null));
    try std.testing.expectEqual(result_invalid_handle, proto_ui_runtime_host_adapter_session_destroy(null));
}

test "candidate destroy drains an active terminal" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var handle: ?*anyopaque = null;
    try std.testing.expectEqual(result_ok, proto_ui_runtime_host_adapter_session_create(&table, &handle));
    try std.testing.expectEqual(result_ok, proto_ui_runtime_host_adapter_session_activate(handle, null));
    try std.testing.expectEqual(result_ok, proto_ui_runtime_host_adapter_session_destroy(handle));
    try std.testing.expectEqual(runtime_host.TerminalState.deleted, host.terminal);
}

pub const TpeWireRow = extern struct {
    window_id: u64,
    index: u32,
    flags: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    ascent: i32,
    descent: i32,
    baseline: i32,
    visible_height: i32,
};

pub const TpeWireRun = extern struct {
    run_id: u32,
    generation: u32,
    window_id: u64,
    row_index: u32,
    face_id: u32,
    face_generation: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    text_length: u32,
    text: [256]u8,
};

pub const TpeWireCursor = extern struct {
    window_id: u64,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    kind: u8,
    visible: bool,
    active: bool,
};

pub const TpeWireFace = extern struct {
    face_id: u32,
    generation: u32,
    background: [4]u8,
};

pub const TpeWireHighlight = extern struct {
    flags: u8,
    window_id: u64,
    frame_generation: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    face_id: u32,
    face_generation: u32,
};

pub const TpeWireSnapshot = extern struct {
    frame_id: u32,
    frame_generation: u32,
    session_id: u64,
    redisplay_generation: u64,
    width: i32,
    height: i32,
    rows: ?[*]const TpeWireRow,
    row_count: usize,
    runs: ?[*]const TpeWireRun,
    run_count: usize,
    cursor: TpeWireCursor,
    faces: ?[*]const TpeWireFace,
    face_count: usize,
    highlights: ?[*]const TpeWireHighlight,
    highlight_count: usize,
};

fn tpeAppendEnvelope(
    out: *std.ArrayList(u8),
    message_type: u16,
    flags: u16,
    sequence: u64,
    session_id: u64,
    frame_id: u32,
    timestamp_ns: u64,
    payload: []const u8,
) !void {
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(std.heap.c_allocator);
    try protocol.encodeEnvelope(std.heap.c_allocator, .{
        .flags = flags,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = session_id,
        .frame_id = frame_id,
        .timestamp_ns = timestamp_ns,
    }, payload, &message);
    var prefix: [4]u8 = undefined;
    std.mem.writeInt(u32, &prefix, @intCast(message.items.len), .little);
    try out.appendSlice(std.heap.c_allocator, &prefix);
    try out.appendSlice(std.heap.c_allocator, message.items);
}

export fn proto_ui_tpe_encode_snapshot(
    input: ?*const TpeWireSnapshot,
    out_bytes: *?[*]u8,
    out_len: *usize,
) c_int {
    out_bytes.* = null;
    out_len.* = 0;
    const snapshot = input orelse return 1;
    if (snapshot.frame_id == 0 or snapshot.frame_generation == 0 or
        snapshot.session_id == 0 or snapshot.redisplay_generation == 0 or
        snapshot.width <= 0 or snapshot.height <= 0 or
        snapshot.row_count == 0 or snapshot.rows == null)
        return 1;

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(std.heap.c_allocator);
    const TpeSnapshotSequenceState = struct {
        var session_id: u64 = 0;
        var frame_generation: u32 = 0;
        var next: u64 = 1;
        var last_face_generation: u32 = 0;
        var last_highlight_count: usize = 0;
    };
    const first_snapshot = snapshot.session_id != TpeSnapshotSequenceState.session_id or
        snapshot.frame_generation != TpeSnapshotSequenceState.frame_generation;
    if (first_snapshot) {
        TpeSnapshotSequenceState.session_id = snapshot.session_id;
        TpeSnapshotSequenceState.frame_generation = snapshot.frame_generation;
        TpeSnapshotSequenceState.next = 1;
        TpeSnapshotSequenceState.last_face_generation = 0;
        TpeSnapshotSequenceState.last_highlight_count = 0;
    }
    var sequence: u64 = TpeSnapshotSequenceState.next;

    var stale_face_payload: [8]u8 = undefined;
    if (TpeSnapshotSequenceState.last_highlight_count > 0 and !first_snapshot) {
        for (0..TpeSnapshotSequenceState.last_highlight_count) |index| {
            const face_id = if (index == 0) 9 else 40 + @as(u32, @intCast(index - 1));
            std.mem.writeInt(u32, stale_face_payload[0..4], face_id, .little);
            std.mem.writeInt(u32, stale_face_payload[4..8], TpeSnapshotSequenceState.last_face_generation, .little);
            tpeAppendEnvelope(&output, protocol.Message.face_delete, 0, sequence, snapshot.session_id, snapshot.frame_id, sequence, &stale_face_payload) catch return 2;
            sequence += 1;
        }
    }

    var create_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, create_payload[0..4], snapshot.frame_id, .little);
    std.mem.writeInt(u32, create_payload[4..8], snapshot.frame_generation, .little);
    if (first_snapshot) {
        tpeAppendEnvelope(&output, protocol.Message.frame_create, 0, sequence, snapshot.session_id, snapshot.frame_id, sequence, &create_payload) catch return 2;
        sequence += 1;
    }

    var geometry_payload: std.ArrayList(u8) = .empty;
    defer geometry_payload.deinit(std.heap.c_allocator);
    const rect = protocol.GeometryRect{ .x = 0, .y = 0, .width = snapshot.width, .height = snapshot.height };
    protocol.encodeFrameGeometry(std.heap.c_allocator, .{
        .frame_generation = snapshot.frame_generation,
        .outer = rect,
        .content = rect,
        .text = rect,
        .window = rect,
        .body = rect,
    }, &geometry_payload) catch return 2;
    if (first_snapshot) {
        tpeAppendEnvelope(&output, protocol.Message.frame_geometry, 0, sequence, snapshot.session_id, snapshot.frame_id, sequence, geometry_payload.items) catch return 2;
        sequence += 1;
    }

    var window_bytes: std.ArrayList(u8) = .empty;
    defer window_bytes.deinit(std.heap.c_allocator);
    var row_bytes: std.ArrayList(u8) = .empty;
    defer row_bytes.deinit(std.heap.c_allocator);
    const window_id = snapshot.rows.?[0].window_id;
    frontend.encodeWindow(std.heap.c_allocator, .{
        .id = window_id,
        .frame_id = snapshot.frame_id,
        .x = 0,
        .y = 0,
        .width = snapshot.width,
        .height = snapshot.height,
    }, &window_bytes) catch return 2;
    for (snapshot.rows.?[0..snapshot.row_count]) |row| {
        frontend.encodeRow(std.heap.c_allocator, .{
            .window_id = row.window_id,
            .index = row.index,
            .flags = row.flags,
            .x = row.x,
            .y = row.y,
            .width = row.width,
            .height = row.height,
            .ascent = row.ascent,
            .descent = row.descent,
            .baseline = row.baseline,
            .visible_height = row.visible_height,
        }, &row_bytes) catch return 2;
    }

    var cursor_bytes: std.ArrayList(u8) = .empty;
    defer cursor_bytes.deinit(std.heap.c_allocator);
    frontend.encodeCursor(std.heap.c_allocator, .{
        .window_id = snapshot.cursor.window_id,
        .x = snapshot.cursor.x,
        .y = snapshot.cursor.y,
        .width = snapshot.cursor.width,
        .height = snapshot.cursor.height,
        .kind = snapshot.cursor.kind,
        .visible = snapshot.cursor.visible,
        .active = snapshot.cursor.active,
    }, &cursor_bytes) catch return 2;

    if (snapshot.face_count > 0 and snapshot.faces != null) {
        for (snapshot.faces.?[0..snapshot.face_count]) |face| {
            var face_payload: std.ArrayList(u8) = .empty;
            defer face_payload.deinit(std.heap.c_allocator);
            protocol.encodeFaceDefine(std.heap.c_allocator, .{
                .face_id = face.face_id,
                .generation = face.generation,
                .presence = .{ .background = true },
                .background = face.background,
            }, &face_payload) catch return 2;
            tpeAppendEnvelope(&output, protocol.Message.face_define, 0, sequence, snapshot.session_id, snapshot.frame_id, sequence, face_payload.items) catch return 2;
            sequence += 1;
        }
    }

    var damage_bytes: std.ArrayList(u8) = .empty;
    defer damage_bytes.deinit(std.heap.c_allocator);
    frontend.encodeRect(std.heap.c_allocator, .{
        .x = 0,
        .y = 0,
        .width = snapshot.width,
        .height = snapshot.height,
    }, &damage_bytes) catch return 2;

    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = window_bytes.items },
        .{ .kind = protocol.SectionKind.rows, .records = row_bytes.items },
        .{ .kind = protocol.SectionKind.cursors, .records = cursor_bytes.items },
        .{ .kind = protocol.SectionKind.damage, .records = damage_bytes.items },
    };
    var update_payload: std.ArrayList(u8) = .empty;
    defer update_payload.deinit(std.heap.c_allocator);
    const frame_sequence: u64 = sequence;
    protocol.encodeFrameUpdate(std.heap.c_allocator, .{
        .header = .{
            .frame_id = snapshot.frame_id,
            .frame_generation = snapshot.frame_generation,
            .sequence = sequence,
            .redisplay_generation = snapshot.redisplay_generation,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = snapshot.width,
            .logical_height = snapshot.height,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = snapshot.width,
            .physical_height = snapshot.height,
            .scale = 1.0,
            .dpi_x = 96.0,
            .dpi_y = 96.0,
            .damage_mode = 2,
            .update_cause = 1,
            .coalesced_count = 0,
            .timestamp_ns = sequence,
        },
        .sections = &sections,
    }, &update_payload) catch return 2;
    tpeAppendEnvelope(&output, protocol.Message.frame_update, protocol.Flags.delta, sequence, snapshot.session_id, snapshot.frame_id, sequence, update_payload.items) catch return 2;
    sequence += 1;

    for (snapshot.runs.?[0..snapshot.run_count]) |run| {
        var run_payload: std.ArrayList(u8) = .empty;
        defer run_payload.deinit(std.heap.c_allocator);
        frontend.encodeGlyphRun(std.heap.c_allocator, .{
            .run_id = run.run_id,
            .generation = run.generation,
            .window_id = run.window_id,
            .row_index = run.row_index,
            .face_id = run.face_id,
            .face_generation = run.face_generation,
            .x = run.x,
            .y = run.y,
            .width = run.width,
            .height = run.height,
            .text = run.text[0..run.text_length],
        }, &run_payload) catch return 2;
        tpeAppendEnvelope(&output, protocol.Message.glyph_run, protocol.Flags.debug, sequence, snapshot.session_id, snapshot.frame_id, sequence, run_payload.items) catch return 2;
        sequence += 1;
    }

    if (snapshot.highlight_count > 0 and snapshot.highlights != null) {
        for (snapshot.highlights.?[0..snapshot.highlight_count]) |highlight| {
            var highlight_bytes: std.ArrayList(u8) = .empty;
            defer highlight_bytes.deinit(std.heap.c_allocator);
            frontend.encodeMouseHighlightState(std.heap.c_allocator, .{
                .flags = frontend.MouseHighlightFlags.visible,
                .window_id = highlight.window_id,
                .frame_generation = highlight.frame_generation,
                .rect = .{
                    .x = highlight.x,
                    .y = highlight.y,
                    .width = highlight.width,
                    .height = highlight.height,
                },
                .face_id = highlight.face_id,
                .face_generation = highlight.face_generation,
            }, &highlight_bytes) catch return 2;
            tpeAppendEnvelope(&output, protocol.Message.mouse_highlight, 0, sequence, snapshot.session_id, snapshot.frame_id, sequence, highlight_bytes.items) catch return 2;
            sequence += 1;
        }
    }

    if (snapshot.highlight_count == 0 and
        TpeSnapshotSequenceState.last_highlight_count > 0 and !first_snapshot)
    {
        for (0..TpeSnapshotSequenceState.last_highlight_count) |index| {
            const face_id = if (index == 0) 9 else 40 + @as(u32, @intCast(index - 1));
            var highlight_bytes: std.ArrayList(u8) = .empty;
            defer highlight_bytes.deinit(std.heap.c_allocator);
            frontend.encodeMouseHighlightState(std.heap.c_allocator, .{
                .flags = frontend.MouseHighlightFlags.hidden,
                .window_id = snapshot.rows.?[0].window_id,
                .frame_generation = snapshot.frame_generation,
                .rect = .{ .x = 0, .y = 0, .width = 1, .height = 1 },
                .face_id = face_id,
                .face_generation = TpeSnapshotSequenceState.last_face_generation,
            }, &highlight_bytes) catch return 2;
            tpeAppendEnvelope(&output, protocol.Message.mouse_highlight, 0, sequence, snapshot.session_id, snapshot.frame_id, sequence, highlight_bytes.items) catch return 2;
            sequence += 1;
        }
    }

    var flush_payload: std.ArrayList(u8) = .empty;
    defer flush_payload.deinit(std.heap.c_allocator);
    protocol.encodeFrameFlush(std.heap.c_allocator, .{
        .frame_generation = snapshot.frame_generation,
        .redisplay_generation = snapshot.redisplay_generation,
        .frame_sequence = frame_sequence,
        .damage_kind = .full,
    }, &flush_payload) catch return 2;
    tpeAppendEnvelope(&output, protocol.Message.flush, 0, sequence, snapshot.session_id, snapshot.frame_id, sequence, flush_payload.items) catch return 2;

    const bytes = std.heap.c_allocator.dupe(u8, output.items) catch return 3;
    TpeSnapshotSequenceState.next = sequence + 1;
    TpeSnapshotSequenceState.last_face_generation = @intCast(snapshot.redisplay_generation);
    TpeSnapshotSequenceState.last_highlight_count = snapshot.highlight_count;
    out_bytes.* = bytes.ptr;
    out_len.* = bytes.len;
    return 0;
}

export fn proto_ui_tpe_free_snapshot(bytes: ?[*]u8, len: usize) void {
    if (bytes) |pointer| std.heap.c_allocator.free(pointer[0..len]);
}

test "tpe snapshot encoder emits bounded EUP messages" {
    var text = "Emacs".*;
    var rows = [_]TpeWireRow{.{ .window_id = 10, .index = 0, .flags = 0, .x = 0, .y = 0, .width = 80, .height = 16, .ascent = 12, .descent = 4, .baseline = 12, .visible_height = 16 }};
    var runs = [_]TpeWireRun{.{
        .run_id = 1,
        .generation = 1,
        .window_id = 10,
        .row_index = 0,
        .face_id = 0,
        .face_generation = 0,
        .x = 0,
        .y = 0,
        .width = 40,
        .height = 16,
        .text_length = 5,
        .text = undefined,
    }};
    @memcpy(runs[0].text[0..5], &text);
    var faces: [0]TpeWireFace = .{};
    var highlights: [0]TpeWireHighlight = .{};
    const snapshot = TpeWireSnapshot{
        .frame_id = 2,
        .frame_generation = 1,
        .session_id = 9,
        .redisplay_generation = 1,
        .width = 80,
        .height = 24,
        .rows = &rows,
        .row_count = rows.len,
        .runs = &runs,
        .run_count = runs.len,
        .cursor = .{ .window_id = 10, .x = 40, .y = 0, .width = 8, .height = 16, .kind = 1, .visible = true, .active = true },
        .faces = &faces,
        .face_count = faces.len,
        .highlights = &highlights,
        .highlight_count = highlights.len,
    };
    var bytes: ?[*]u8 = null;
    var len: usize = 0;
    try std.testing.expectEqual(@as(c_int, 0), proto_ui_tpe_encode_snapshot(&snapshot, &bytes, &len));
    defer proto_ui_tpe_free_snapshot(bytes, len);
    try std.testing.expect(bytes != null and len > 100);

    var offset: usize = 0;
    var count: usize = 0;
    while (offset < len) {
        const message_len = std.mem.readInt(u32, bytes.?[offset..][0..4], .little);
        const payload = try protocol.decodeEnvelope(bytes.?[offset + 4 ..][0..message_len]);
        try std.testing.expect(payload.envelope.frame_id == 2);
        offset += 4 + message_len;
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 4 + runs.len), count);
}
