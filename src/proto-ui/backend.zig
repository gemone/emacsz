//! W3 Emacs-facing lifecycle ABI for the opt-in proto-ui backend.
//!
//! This module owns protocol-level identity for headless terminal sessions and
//! frames.  It intentionally does not create Emacs terminal objects or frames;
//! A future C integration layer will own the corresponding Emacs objects and
//! call this ABI so EUP IDs and lifecycle messages cannot diverge.  The export
//! functions are called only from the Emacs main thread during W3.

const std = @import("std");
const protocol = @import("protocol.zig");
const transport = @import("transport.zig");

/// Bump only when the C-facing registration ABI changes.  EUP wire-version
/// changes are tracked separately by `protocol.major_version`.
pub const abi_version: u32 = 1;

pub const LifecycleError = error{
    InvalidTerminal,
    InvalidFrame,
    SessionLimit,
    OutOfMemory,
};

pub const Terminal = struct {
    id: u64,
    live: bool = true,
};

pub const Frame = struct {
    id: u64,
    generation: u32 = 1,
    terminal_id: u64,
    live: bool = true,
    redisplay_generation: u64 = 0,
    update_active: bool = false,
    cursor: ?CursorState = null,
};

pub const CursorState = struct {
    window_id: u64,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    kind: u8,
    visible: bool,
    active: bool,
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    id: u64,
    next_terminal_id: u64 = 1,
    next_frame_id: u64 = 1,
    next_window_id: u64 = 1,
    terminals: std.AutoHashMapUnmanaged(u64, Terminal) = .{},
    frames: std.AutoHashMapUnmanaged(u64, Frame) = .{},
    sink: transport.MemorySink,
    frame_create_count: u64 = 0,
    frame_destroy_count: u64 = 0,
    frame_update_count: u64 = 0,

    pub fn create(allocator: std.mem.Allocator, id: u64) !*Session {
        const session = try allocator.create(Session);
        errdefer allocator.destroy(session);
        session.* = .{
            .allocator = allocator,
            .id = id,
            .sink = transport.MemorySink.init(allocator),
        };
        return session;
    }

    pub fn destroy(self: *Session) void {
        self.terminals.deinit(self.allocator);
        self.frames.deinit(self.allocator);
        self.sink.deinit();
        self.allocator.destroy(self);
    }

    pub fn createTerminal(self: *Session) !u64 {
        if (self.next_terminal_id == 0 or
            self.next_terminal_id > std.math.maxInt(u32)) return LifecycleError.SessionLimit;
        const id = self.next_terminal_id;
        try self.terminals.ensureUnusedCapacity(self.allocator, 1);
        self.terminals.putAssumeCapacity(id, .{ .id = id });
        self.next_terminal_id += 1;
        return id;
    }

    pub fn destroyTerminal(self: *Session, terminal_id: u64) !void {
        const terminal = self.terminals.getPtr(terminal_id) orelse
            return LifecycleError.InvalidTerminal;
        if (!terminal.live) return LifecycleError.InvalidTerminal;
        terminal.live = false;
    }

    pub fn createFrame(self: *Session, terminal_id: u64) !u64 {
        const terminal = self.terminals.get(terminal_id) orelse
            return LifecycleError.InvalidTerminal;
        if (!terminal.live) return LifecycleError.InvalidTerminal;
        if (self.next_frame_id == 0 or
            self.next_frame_id > std.math.maxInt(u32)) return LifecycleError.SessionLimit;
        const id = self.next_frame_id;

        // Reserve state and claim the ID first.  If protocol emission fails,
        // roll both back so a failed create never leaves live state or an ID
        // gap behind.
        try self.frames.ensureUnusedCapacity(self.allocator, 1);
        self.frames.putAssumeCapacity(id, .{
            .id = id,
            .generation = 1,
            .terminal_id = terminal_id,
        });
        self.next_frame_id += 1;
        errdefer {
            _ = self.frames.remove(id);
            self.next_frame_id = id;
        }

        try self.emitFrameLifecycle(protocol.Message.frame_create, id, 1);
        self.frame_create_count += 1;
        return id;
    }

    pub fn createWindow(self: *Session, frame_id: u64) !u64 {
        const frame = self.frames.get(frame_id) orelse
            return LifecycleError.InvalidFrame;
        if (!frame.live) return LifecycleError.InvalidFrame;
        if (self.next_window_id == 0 or
            self.next_window_id > std.math.maxInt(u32)) return LifecycleError.SessionLimit;
        const id = self.next_window_id;
        self.next_window_id += 1;
        return id;
    }

    pub fn destroyFrame(self: *Session, frame_id: u64) !void {
        const frame = self.frames.getPtr(frame_id) orelse
            return LifecycleError.InvalidFrame;
        if (!frame.live) return LifecycleError.InvalidFrame;

        // Mutate the non-failing authoritative state first.  If protocol
        // emission fails, restore it; callers treat destroy as failed.
        frame.live = false;
        errdefer frame.live = true;
        try self.emitFrameLifecycle(
            protocol.Message.frame_destroy,
            frame.id,
            frame.generation,
        );
        self.frame_destroy_count += 1;
    }

    pub fn beginFrame(self: *Session, frame_id: u64) !void {
        const frame = self.frames.getPtr(frame_id) orelse
            return LifecycleError.InvalidFrame;
        if (!frame.live) return LifecycleError.InvalidFrame;
        if (frame.update_active) return LifecycleError.InvalidFrame;
        if (frame.redisplay_generation == std.math.maxInt(u64))
            return LifecycleError.SessionLimit;
        frame.redisplay_generation += 1;
        frame.update_active = true;
        frame.cursor = null;
    }

    pub fn recordCursor(
        self: *Session,
        frame_id: u64,
        window_id: u64,
        x: i32,
        y: i32,
        width: i32,
        height: i32,
        kind: u8,
        visible: bool,
        active: bool,
    ) !void {
        const frame = self.frames.getPtr(frame_id) orelse
            return LifecycleError.InvalidFrame;
        if (!frame.update_active) return LifecycleError.InvalidFrame;
        if (window_id == 0) return LifecycleError.InvalidFrame;
        frame.cursor = .{
            .window_id = window_id,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .kind = kind,
            .visible = visible,
            .active = active,
        };
    }

    pub fn flushFrame(
        self: *Session,
        frame_id: u64,
        logical_width: i32,
        logical_height: i32,
    ) !void {
        const frame = self.frames.getPtr(frame_id) orelse
            return LifecycleError.InvalidFrame;
        if (!frame.live or !frame.update_active)
            return LifecycleError.InvalidFrame;
        if (logical_width < 0 or logical_height < 0)
            return LifecycleError.InvalidFrame;
        if (self.sink.next_sequence == std.math.maxInt(u64))
            return LifecycleError.SessionLimit;

        const sequence = self.sink.next_sequence;
        const frame_id32: u32 = @intCast(frame.id);

        // W4a emits a conservative full-frame damage rectangle.  Concrete
        // row/glyph tables arrive in the next redisplay slice.
        var cursor_record: [56]u8 = undefined;
        var has_cursor = false;
        if (frame.cursor) |cursor| {
            std.mem.writeInt(u64, cursor_record[0..8], cursor.window_id, .little);
            std.mem.writeInt(i32, cursor_record[8..12], cursor.x, .little);
            std.mem.writeInt(i32, cursor_record[12..16], cursor.y, .little);
            std.mem.writeInt(i32, cursor_record[16..20], cursor.width, .little);
            std.mem.writeInt(i32, cursor_record[20..24], cursor.height, .little);
            cursor_record[24] = cursor.kind;
            cursor_record[25] = @intFromBool(cursor.visible);
            cursor_record[26] = @intFromBool(cursor.active);
            @memset(cursor_record[27..56], 0);
            has_cursor = true;
        }

        var damage: [16]u8 = undefined;
        std.mem.writeInt(i32, damage[0..4], 0, .little);
        std.mem.writeInt(i32, damage[4..8], 0, .little);
        std.mem.writeInt(i32, damage[8..12], logical_width, .little);
        std.mem.writeInt(i32, damage[12..16], logical_height, .little);

        var present: [16]u8 = undefined;
        std.mem.writeInt(u32, present[0..4], 0, .little); // vsync
        std.mem.writeInt(u32, present[4..8], 1, .little); // damage allowed
        std.mem.writeInt(u64, present[8..16], 0, .little); // no deadline

        var sections: [3]protocol.Section = undefined;
        var section_count: usize = 0;
        if (has_cursor) {
            sections[section_count] = .{
                .kind = protocol.SectionKind.cursors,
                .records = &cursor_record,
            };
            section_count += 1;
        }
        sections[section_count] = .{
            .kind = protocol.SectionKind.damage,
            .records = &damage,
        };
        section_count += 1;
        sections[section_count] = .{
            .kind = protocol.SectionKind.present_hint,
            .records = &present,
        };
        section_count += 1;

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);
        try protocol.encodeFrameUpdate(self.allocator, .{
            .header = .{
                .frame_id = frame_id32,
                .frame_generation = frame.generation,
                .sequence = sequence,
                .redisplay_generation = frame.redisplay_generation,
                .logical_x = 0,
                .logical_y = 0,
                .logical_width = logical_width,
                .logical_height = logical_height,
                .physical_x = 0,
                .physical_y = 0,
                .physical_width = logical_width,
                .physical_height = logical_height,
                .scale = 1.0,
                .dpi_x = 96.0,
                .dpi_y = 96.0,
                .damage_mode = 2, // full
                .update_cause = 1, // redisplay
                .coalesced_count = 0,
                .timestamp_ns = 0,
            },
            .sections = sections[0..section_count],
        }, &payload);

        _ = try self.sink.send(.{
            .flags = protocol.Flags.delta | protocol.Flags.idempotent,
            .message_type = protocol.Message.frame_update,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = self.id,
            .frame_id = frame_id32,
            .timestamp_ns = 0,
        }, payload.items);

        // The EUP update is committed only after transport ownership
        // succeeds.  A later W4 slice can retry/coalesce failed updates.
        frame.update_active = false;
        self.frame_update_count += 1;
    }

    pub fn frameMessageCount(self: *Session, frame_id: u64) usize {
        // W4a emits one FRAME_UPDATE per successful flush.
        _ = frame_id;
        return self.frame_update_count;
    }

    pub fn frameIsLive(self: *Session, frame_id: u64) bool {
        const frame = self.frames.get(frame_id) orelse return false;
        return frame.live;
    }

    pub fn messageCount(self: *Session) usize {
        return self.sink.messages.items.len;
    }

    fn emitFrameLifecycle(
        self: *Session,
        message_type: u16,
        frame_id: u64,
        frame_generation: u32,
    ) !void {
        if (frame_id == 0 or frame_id > std.math.maxInt(u32))
            return LifecycleError.SessionLimit;

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.allocator);
        var word: [8]u8 = undefined;
        std.mem.writeInt(u32, word[0..4], @intCast(frame_id), .little);
        std.mem.writeInt(u32, word[4..8], frame_generation, .little);
        try payload.appendSlice(self.allocator, &word);

        // MemorySink owns envelope framing and session sequence assignment.
        _ = try self.sink.send(.{
            .flags = protocol.Flags.idempotent,
            .message_type = message_type,
            .sequence = 0,
            .ack_sequence = 0,
            .session_id = self.id,
            .frame_id = @intCast(frame_id),
            .timestamp_ns = 0,
        }, payload.items);
    }
};

// The lifecycle exports are called only from the Emacs main thread.  This
// state machine intentionally has no cross-thread lock; the state marker only
// detects concurrent creation of the process-wide singleton.
var lifecycle_session: ?*Session = null;
var lifecycle_state: std.atomic.Value(u8) = .init(0);

/// Create the process-wide lifecycle session used by Emacs.  Repeated calls
/// return the same session so C terminal objects and EUP IDs stay stable.
export fn proto_ui_lifecycle_session_create(session_id: *u64) c_int {
    if (lifecycle_session) |session| {
        session_id.* = session.id;
        return 0;
    }
    if (lifecycle_state.cmpxchgStrong(0, 1, .acquire, .monotonic) != null)
        return -1;
    const session = Session.create(std.heap.page_allocator, 1) catch {
        lifecycle_state.store(0, .release);
        return -1;
    };
    lifecycle_session = session;
    lifecycle_state.store(2, .release);
    session_id.* = session.id;
    return 0;
}

export fn proto_ui_terminal_create(session_id: u64, terminal_id: *u64) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    const id = session.createTerminal() catch return -1;
    terminal_id.* = id;
    return 0;
}

export fn proto_ui_terminal_destroy(session_id: u64, terminal_id: u64) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    session.destroyTerminal(terminal_id) catch return -1;
    return 0;
}

export fn proto_ui_frame_create(
    session_id: u64,
    terminal_id: u64,
    frame_id: *u64,
) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    const id = session.createFrame(terminal_id) catch return -1;
    frame_id.* = id;
    return 0;
}

export fn proto_ui_frame_destroy(session_id: u64, frame_id: u64) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    session.destroyFrame(frame_id) catch return -1;
    return 0;
}

export fn proto_ui_frame_live(session_id: u64, frame_id: u64) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    return if (session.frameIsLive(frame_id)) 1 else 0;
}

export fn proto_ui_frame_update_begin(session_id: u64, frame_id: u64) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    session.beginFrame(frame_id) catch return -1;
    return 0;
}

export fn proto_ui_window_create(
    session_id: u64,
    frame_id: u64,
    window_id: *u64,
) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    const id = session.createWindow(frame_id) catch return -1;
    window_id.* = id;
    return 0;
}

export fn proto_ui_frame_cursor(
    session_id: u64,
    frame_id: u64,
    window_id: u64,
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
    kind: u8,
    visible: bool,
    active: bool,
) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    session.recordCursor(
        frame_id,
        window_id,
        @intCast(x),
        @intCast(y),
        @intCast(width),
        @intCast(height),
        kind,
        visible,
        active,
    ) catch return -1;
    return 0;
}

export fn proto_ui_frame_flush(
    session_id: u64,
    frame_id: u64,
    logical_width: c_int,
    logical_height: c_int,
) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    session.flushFrame(
        frame_id,
        @intCast(logical_width),
        @intCast(logical_height),
    ) catch return -1;
    return 0;
}

export fn proto_ui_frame_update_count(session_id: u64) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    return if (session.frame_update_count > std.math.maxInt(c_int))
        std.math.maxInt(c_int)
    else
        @intCast(session.frame_update_count);
}

export fn proto_ui_registration_compatible(
    requested_abi: c_uint,
    eup_major: c_uint,
    eup_minor: c_uint,
) bool {
    return requested_abi == abiVersion() and eup_major == protocol.major_version and eup_minor <= protocol.minor_version;
}

fn abiVersion() c_uint {
    return abi_version;
}

test "registration ABI remains versioned" {
    try std.testing.expectEqual(@as(u32, 1), abiVersion());
    try std.testing.expect(proto_ui_registration_compatible(1, 1, 0));
    try std.testing.expect(!proto_ui_registration_compatible(1, 1, 1));
    try std.testing.expect(!proto_ui_registration_compatible(2, 1, 0));
    try std.testing.expect(!proto_ui_registration_compatible(1, 2, 0));
    try std.testing.expect(!proto_ui_registration_compatible(1, 1, 2));
}

test "lifecycle IDs, generations, and emitted messages remain stable" {
    const a = std.testing.allocator;
    const session = try Session.create(a, 77);
    defer session.destroy();

    const terminal_id = try session.createTerminal();
    const frame_id = try session.createFrame(terminal_id);
    try std.testing.expectEqual(@as(u64, 1), terminal_id);
    try std.testing.expectEqual(@as(u64, 1), frame_id);
    try std.testing.expect(session.frameIsLive(frame_id));
    try std.testing.expectEqual(@as(usize, 1), session.messageCount());

    try session.destroyFrame(frame_id);
    try std.testing.expect(!session.frameIsLive(frame_id));
    try std.testing.expectEqual(@as(usize, 2), session.messageCount());
    try std.testing.expectError(LifecycleError.InvalidTerminal, session.createFrame(terminal_id + 1));
    try std.testing.expectError(LifecycleError.InvalidFrame, session.destroyFrame(frame_id));

    // Backend terminal destruction is independent of frame state and must
    // reject repeated destruction at the lifecycle boundary.
    try session.destroyTerminal(terminal_id);
    try std.testing.expectError(LifecycleError.InvalidTerminal, session.destroyTerminal(terminal_id));

    const expected = [_]u16{ protocol.Message.frame_create, protocol.Message.frame_destroy };
    for (expected, 0..) |message_type, index| {
        const decoded = try protocol.decodeEnvelope(session.sink.messages.items[index]);
        try std.testing.expectEqual(@as(u64, 77), decoded.envelope.session_id);
        try std.testing.expectEqual(@as(u32, 1), decoded.envelope.frame_id);
        try std.testing.expectEqual(@as(u64, index + 1), decoded.envelope.sequence);
        try std.testing.expectEqual(message_type, decoded.envelope.message_type);
        try std.testing.expectEqual(@as(usize, 8), decoded.bytes.len);
        try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, decoded.bytes[0..4], .little));
        try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, decoded.bytes[4..8], .little));
    }
}

test "lifecycle state rolls back when emission fails" {
    const a = std.testing.allocator;
    const session = try Session.create(a, 77);
    defer session.destroy();

    const terminal_id = try session.createTerminal();
    session.sink.next_sequence = std.math.maxInt(u64);
    try std.testing.expectError(
        protocol.Error.Unsupported,
        session.createFrame(terminal_id),
    );
    try std.testing.expectEqual(@as(u64, 1), session.next_frame_id);
    try std.testing.expectEqual(@as(usize, 0), session.frames.count());
    try std.testing.expectEqual(@as(usize, 0), session.messageCount());

    session.sink.next_sequence = 1;
    const frame_id = try session.createFrame(terminal_id);
    session.sink.next_sequence = std.math.maxInt(u64);
    try std.testing.expectError(
        protocol.Error.Unsupported,
        session.destroyFrame(frame_id),
    );
    try std.testing.expect(session.frameIsLive(frame_id));
    try std.testing.expectEqual(@as(u64, 0), session.frame_destroy_count);
    try std.testing.expectEqual(@as(usize, 1), session.messageCount());
}

test "frame update captures full damage and cursor" {
    const a = std.testing.allocator;
    const session = try Session.create(a, 88);
    defer session.destroy();
    const terminal_id = try session.createTerminal();
    const frame_id = try session.createFrame(terminal_id);
    const window_id = try session.createWindow(frame_id);

    try session.beginFrame(frame_id);
    try session.recordCursor(frame_id, window_id, 4, 8, 2, 16, 0, true, true);
    try session.flushFrame(frame_id, 320, 200);

    try std.testing.expectEqual(@as(usize, 1), session.frame_update_count);
    const encoded = session.sink.messages.items[session.sink.messages.items.len - 1];
    const payload = try protocol.decodeEnvelope(encoded);
    try std.testing.expectEqual(protocol.Message.frame_update, payload.envelope.message_type);
    const update = try protocol.decodeFrameUpdate(a, payload.bytes);
    defer a.free(update.sections);
    try std.testing.expectEqual(frame_id, update.header.frame_id);
    try std.testing.expectEqual(@as(u64, 1), update.header.redisplay_generation);
    try std.testing.expectEqual(@as(i32, 320), update.header.logical_width);
    try std.testing.expectEqual(@as(usize, 3), update.sections.len);
    try std.testing.expectEqual(protocol.SectionKind.cursors, update.sections[0].kind);
    try std.testing.expectEqual(protocol.SectionKind.damage, update.sections[1].kind);
    try std.testing.expectEqual(@as(usize, 16), update.sections[1].records.len);
    try std.testing.expectEqual(@as(i32, 320), std.mem.readInt(i32, update.sections[1].records[8..12], .little));
    try std.testing.expectEqual(@as(usize, 56), update.sections[0].records.len);
    try std.testing.expectEqual(window_id, std.mem.readInt(u64, update.sections[0].records[0..8], .little));
    try std.testing.expectEqual(protocol.SectionKind.present_hint, update.sections[2].kind);
}
