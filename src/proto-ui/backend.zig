//! Emacs-facing lifecycle and redisplay-capture ABI for the opt-in proto-ui
//! backend.
//!
//! This module owns protocol-level identity for headless terminal sessions and
//! frames.  The C integration layer owns the corresponding Emacs objects and
//! calls this ABI so EUP IDs, lifecycle messages, and frame-update metadata
//! cannot diverge.  The export functions are called only from the Emacs main
//! thread.

const std = @import("std");
const protocol = @import("protocol.zig");
const transport = @import("transport.zig");

/// Bump only when the C-facing registration ABI changes.  EUP wire-version
/// changes are tracked separately by `protocol.major_version`.
pub const abi_version: u32 = 1;

pub const LifecycleError = error{
    InvalidTerminal,
    InvalidFrame,
    RowLimit,
    DamageLimit,
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
    capture_failed: bool = false,
    cursor: ?CursorState = null,
    update_rows: [max_update_rows]RowState = undefined,
    update_row_count: usize = 0,
    update_damage: [max_update_damage]DamageState = undefined,
    update_damage_count: usize = 0,
};

pub const Window = struct {
    id: u64,
    frame_id: u64,
    live: bool = true,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
};

pub const max_update_rows: usize = 256;
pub const row_record_size: usize = 56;
pub const max_update_damage: usize = 256;
pub const damage_record_size: usize = 16;

pub const RowState = struct {
    window_id: u64,
    row_index: u32,
    flags: u32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    ascent: i32 = 0,
    descent: i32 = 0,
    baseline: i32 = 0,
    visible_height: i32 = 0,
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

pub const DamageState = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    id: u64,
    next_terminal_id: u64 = 1,
    next_frame_id: u64 = 1,
    next_window_id: u64 = 1,
    terminals: std.AutoHashMapUnmanaged(u64, Terminal) = .{},
    frames: std.AutoHashMapUnmanaged(u64, Frame) = .{},
    windows: std.AutoHashMapUnmanaged(u64, Window) = .{},
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
        self.windows.deinit(self.allocator);
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

        // A terminal can only be destroyed after its C frames are detached.
        // Remove terminal-local metadata now so repeated capture cannot grow
        // maps for dead objects.
        var frame_it = self.frames.iterator();
        while (frame_it.next()) |entry| {
            if (entry.value_ptr.terminal_id == terminal_id) {
                _ = self.frames.remove(entry.key_ptr.*);
                var window_it = self.windows.iterator();
                while (window_it.next()) |window_entry| {
                    if (window_entry.value_ptr.frame_id == entry.key_ptr.*)
                        _ = self.windows.remove(window_entry.key_ptr.*);
                }
            }
        }
        _ = self.terminals.remove(terminal_id);
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
        try self.windows.ensureUnusedCapacity(self.allocator, 1);
        self.windows.putAssumeCapacity(id, .{
            .id = id,
            .frame_id = frame_id,
        });
        self.next_window_id += 1;
        return id;
    }

    pub fn setWindowGeometry(
        self: *Session,
        window_id: u64,
        frame_id: u64,
        x: i32,
        y: i32,
        width: i32,
        height: i32,
    ) !void {
        const window = self.windows.getPtr(window_id) orelse
            return LifecycleError.InvalidFrame;
        if (window.frame_id != frame_id or !window.live)
            return LifecycleError.InvalidFrame;
        window.x = x;
        window.y = y;
        window.width = width;
        window.height = height;
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
        // The EUP view is dead and the C frame is going away.  Remove stable
        // state so redisplay-frequency lifecycle churn cannot grow maps.
        _ = self.frames.remove(frame_id);
        var window_it = self.windows.iterator();
        while (window_it.next()) |entry| {
            if (entry.value_ptr.frame_id == frame_id)
                _ = self.windows.remove(entry.key_ptr.*);
        }
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
        frame.capture_failed = false;
        frame.cursor = null;
        frame.update_row_count = 0;
        frame.update_damage_count = 0;
    }

    pub fn recordRow(
        self: *Session,
        frame_id: u64,
        window_id: u64,
        row_index: u32,
        flags: u32,
        x: i32,
        y: i32,
        width: i32,
        height: i32,
        ascent: i32,
        descent: i32,
        baseline: i32,
        visible_height: i32,
    ) !void {
        const frame = self.frames.getPtr(frame_id) orelse
            return LifecycleError.InvalidFrame;
        if (!frame.update_active) return LifecycleError.InvalidFrame;
        if (window_id == 0) return LifecycleError.InvalidFrame;
        if (frame.update_row_count >= frame.update_rows.len) {
            frame.capture_failed = true;
            return LifecycleError.RowLimit;
        }
        frame.update_rows[frame.update_row_count] = .{
            .window_id = window_id,
            .row_index = row_index,
            .flags = flags,
            .x = x,
            .y = y,
            .width = width,
            .height = height,
            .ascent = ascent,
            .descent = descent,
            .baseline = baseline,
            .visible_height = visible_height,
        };
        frame.update_row_count += 1;
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

    pub fn recordDamage(
        self: *Session,
        frame_id: u64,
        x: i32,
        y: i32,
        width: i32,
        height: i32,
    ) !void {
        const frame = self.frames.getPtr(frame_id) orelse
            return LifecycleError.InvalidFrame;
        if (!frame.update_active) return LifecycleError.InvalidFrame;
        if (width < 0 or height < 0) {
            frame.capture_failed = true;
            return LifecycleError.InvalidFrame;
        }
        if (width > 0 and x > std.math.maxInt(i32) - width) {
            frame.capture_failed = true;
            return LifecycleError.InvalidFrame;
        }
        if (height > 0 and y > std.math.maxInt(i32) - height) {
            frame.capture_failed = true;
            return LifecycleError.InvalidFrame;
        }
        if (frame.update_damage_count >= frame.update_damage.len) {
            frame.capture_failed = true;
            return LifecycleError.DamageLimit;
        }

        frame.update_damage[frame.update_damage_count] = .{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
        frame.update_damage_count += 1;
    }

    pub fn cancelFrame(self: *Session, frame_id: u64) void {
        if (self.frames.getPtr(frame_id)) |frame| {
            frame.update_active = false;
            frame.cursor = null;
            frame.update_row_count = 0;
            frame.update_damage_count = 0;
        }
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
        if (frame.update_damage_count >= frame.update_damage.len)
            return LifecycleError.DamageLimit;
        if (frame.capture_failed) return LifecycleError.RowLimit;
        if (logical_width < 0 or logical_height < 0)
            return LifecycleError.InvalidFrame;
        if (self.sink.next_sequence == std.math.maxInt(u64))
            return LifecycleError.SessionLimit;

        const sequence = self.sink.next_sequence;
        const frame_id32: u32 = @intCast(frame.id);

        // W4b/W4c-a emits captured damage (or the full-frame fallback) plus
        // row/window metadata.  Concrete glyph/face/font/image tables remain
        // W5+.
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

        // With no captured rectangles the conservative fallback stays
        // full-frame.  Real redisplay hooks emit the actual damaged set.
        var damage_records: [max_update_damage + 1][damage_record_size]u8 = undefined;
        const damage_count = if (frame.update_damage_count == 0)
            1
        else
            frame.update_damage_count;
        if (frame.update_damage_count == 0) {
            std.mem.writeInt(i32, damage_records[0][0..4], 0, .little);
            std.mem.writeInt(i32, damage_records[0][4..8], 0, .little);
            std.mem.writeInt(i32, damage_records[0][8..12], logical_width, .little);
            std.mem.writeInt(i32, damage_records[0][12..16], logical_height, .little);
        } else {
            for (frame.update_damage[0..frame.update_damage_count], 0..) |damage, index| {
                std.mem.writeInt(i32, damage_records[index][0..4], damage.x, .little);
                std.mem.writeInt(i32, damage_records[index][4..8], damage.y, .little);
                std.mem.writeInt(i32, damage_records[index][8..12], damage.width, .little);
                std.mem.writeInt(i32, damage_records[index][12..16], damage.height, .little);
            }
        }

        var present: [16]u8 = undefined;
        std.mem.writeInt(u32, present[0..4], 0, .little); // vsync
        std.mem.writeInt(u32, present[4..8], 1, .little); // damage allowed
        std.mem.writeInt(u64, present[8..16], 0, .little); // no deadline

        var sections: [5]protocol.Section = undefined;
        var section_count: usize = 0;
        var window_payload: std.ArrayList(u8) = .empty;
        defer window_payload.deinit(self.allocator);
        var window_count: u32 = 0;
        var window_it = self.windows.valueIterator();
        while (window_it.next()) |window| {
            if (window.frame_id != frame.id or !window.live) continue;
            if (window_payload.items.len > std.math.maxInt(u32) - 40)
                return LifecycleError.SessionLimit;
            try window_payload.ensureUnusedCapacity(self.allocator, 40);
            var entry: [40]u8 = undefined;
            std.mem.writeInt(u64, entry[0..8], window.id, .little);
            std.mem.writeInt(u32, entry[8..12], frame_id32, .little);
            std.mem.writeInt(i32, entry[12..16], window.x, .little);
            std.mem.writeInt(i32, entry[16..20], window.y, .little);
            std.mem.writeInt(i32, entry[20..24], window.width, .little);
            std.mem.writeInt(i32, entry[24..28], window.height, .little);
            @memset(entry[28..40], 0);
            window_payload.appendSliceAssumeCapacity(&entry);
            window_count += 1;
        }
        if (window_count > 0) {
            sections[section_count] = .{
                .kind = protocol.SectionKind.windows,
                .records = window_payload.items,
            };
            section_count += 1;
        }
        if (frame.update_row_count > 0) {
            const count = frame.update_row_count;
            if (count * row_record_size > std.math.maxInt(u32))
                return LifecycleError.SessionLimit;
            var rows_payload: [max_update_rows * row_record_size]u8 = undefined;
            for (frame.update_rows[0..count], 0..) |row, index| {
                const base = index * row_record_size;
                std.mem.writeInt(u64, rows_payload[base..][0..8], row.window_id, .little);
                std.mem.writeInt(u32, rows_payload[base + 8 ..][0..4], row.row_index, .little);
                std.mem.writeInt(u32, rows_payload[base + 12 ..][0..4], row.flags, .little);
                std.mem.writeInt(i32, rows_payload[base + 16 ..][0..4], row.x, .little);
                std.mem.writeInt(i32, rows_payload[base + 20 ..][0..4], row.y, .little);
                std.mem.writeInt(i32, rows_payload[base + 24 ..][0..4], row.width, .little);
                std.mem.writeInt(i32, rows_payload[base + 28 ..][0..4], row.height, .little);
                std.mem.writeInt(i32, rows_payload[base + 32 ..][0..4], row.ascent, .little);
                std.mem.writeInt(i32, rows_payload[base + 36 ..][0..4], row.descent, .little);
                std.mem.writeInt(i32, rows_payload[base + 40 ..][0..4], row.baseline, .little);
                std.mem.writeInt(i32, rows_payload[base + 44 ..][0..4], row.visible_height, .little);
                @memset(rows_payload[base + 48 .. base + 56], 0);
            }
            sections[section_count] = .{
                .kind = protocol.SectionKind.rows,
                .records = rows_payload[0 .. count * row_record_size],
            };
            section_count += 1;
        }
        if (has_cursor) {
            sections[section_count] = .{
                .kind = protocol.SectionKind.cursors,
                .records = &cursor_record,
            };
            section_count += 1;
        }
        sections[section_count] = .{
            .kind = protocol.SectionKind.damage,
            .records = @as([]const u8, @ptrCast(&damage_records))[0 .. damage_count * damage_record_size],
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
                .damage_mode = if (frame.update_damage_count == 0) 2 else 1,
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
        // W4a/W4b/W4c-a emits one FRAME_UPDATE per successful flush.
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

export fn proto_ui_frame_update_cancel(session_id: u64, frame_id: u64) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    session.cancelFrame(frame_id);
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

export fn proto_ui_window_geometry(
    session_id: u64,
    window_id: u64,
    frame_id: u64,
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    session.setWindowGeometry(window_id, frame_id, @intCast(x), @intCast(y), @intCast(width), @intCast(height)) catch return -1;
    return 0;
}

export fn proto_ui_frame_row(
    session_id: u64,
    frame_id: u64,
    window_id: u64,
    row_index: u32,
    flags: u32,
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
    ascent: c_int,
    descent: c_int,
    baseline: c_int,
    visible_height: c_int,
) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    session.recordRow(
        frame_id,
        window_id,
        row_index,
        flags,
        @intCast(x),
        @intCast(y),
        @intCast(width),
        @intCast(height),
        @intCast(ascent),
        @intCast(descent),
        @intCast(baseline),
        @intCast(visible_height),
    ) catch return -1;
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

export fn proto_ui_frame_damage(
    session_id: u64,
    frame_id: u64,
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
) c_int {
    const session = lifecycle_session orelse return -1;
    if (session.id != session_id) return -1;
    session.recordDamage(
        frame_id,
        @intCast(x),
        @intCast(y),
        @intCast(width),
        @intCast(height),
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

test "frame update preserves full-damage fallback and cursor" {
    const a = std.testing.allocator;
    const session = try Session.create(a, 88);
    defer session.destroy();
    const terminal_id = try session.createTerminal();
    const frame_id = try session.createFrame(terminal_id);
    const window_id = try session.createWindow(frame_id);
    try session.setWindowGeometry(window_id, frame_id, 10, 20, 300, 180);

    try session.beginFrame(frame_id);
    try session.recordRow(frame_id, window_id, 0, 0, 10, 20, 300, 20, 14, 4, 14, 20);
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
    try std.testing.expectEqual(@as(usize, 5), update.sections.len);
    try std.testing.expectEqual(@as(u8, 2), update.header.damage_mode);
    try std.testing.expectEqual(protocol.SectionKind.windows, update.sections[0].kind);
    try std.testing.expectEqual(@as(usize, 40), update.sections[0].records.len);
    try std.testing.expectEqual(window_id, std.mem.readInt(u64, update.sections[0].records[0..8], .little));
    try std.testing.expectEqual(@as(i32, 300), std.mem.readInt(i32, update.sections[0].records[20..24], .little));
    try std.testing.expectEqual(protocol.SectionKind.rows, update.sections[1].kind);
    try std.testing.expectEqual(@as(usize, 56), update.sections[1].records.len);
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, update.sections[1].records[8..12], .little));
    try std.testing.expectEqual(protocol.SectionKind.cursors, update.sections[2].kind);
    try std.testing.expectEqual(@as(usize, 56), update.sections[2].records.len);
    try std.testing.expectEqual(window_id, std.mem.readInt(u64, update.sections[2].records[0..8], .little));
    try std.testing.expectEqual(protocol.SectionKind.damage, update.sections[3].kind);
    try std.testing.expectEqual(@as(usize, 16), update.sections[3].records.len);
    try std.testing.expectEqual(@as(i32, 320), std.mem.readInt(i32, update.sections[3].records[8..12], .little));
    try std.testing.expectEqual(protocol.SectionKind.present_hint, update.sections[4].kind);
}

test "window geometry rejects mismatched frame ownership" {
    const a = std.testing.allocator;
    const session = try Session.create(a, 5);
    defer session.destroy();
    const terminal_id = try session.createTerminal();
    const frame_id = try session.createFrame(terminal_id);
    const window_id = try session.createWindow(frame_id);
    try session.setWindowGeometry(window_id, frame_id, 1, 2, 30, 40);
    try std.testing.expectError(
        LifecycleError.InvalidFrame,
        session.setWindowGeometry(window_id, frame_id + 1, 3, 4, 50, 60),
    );
    const window = session.windows.get(window_id).?;
    try std.testing.expectEqual(@as(i32, 30), window.width);
    try std.testing.expectEqual(@as(i32, 40), window.height);
}

test "row capture enforces fixed update capacity" {
    const a = std.testing.allocator;
    const session = try Session.create(a, 6);
    defer session.destroy();
    const terminal_id = try session.createTerminal();
    const frame_id = try session.createFrame(terminal_id);
    const window_id = try session.createWindow(frame_id);
    try session.beginFrame(frame_id);

    for (0..max_update_rows) |row_index| {
        try session.recordRow(frame_id, window_id, @intCast(row_index), 0, 0, @intCast(row_index), 10, 8, 6, 2, 6, 8);
    }
    try std.testing.expectError(
        LifecycleError.RowLimit,
        session.recordRow(frame_id, window_id, max_update_rows, 0, 0, @intCast(max_update_rows), 10, 8, 6, 2, 6, 8),
    );
    try std.testing.expectError(LifecycleError.RowLimit, session.flushFrame(frame_id, 100, 100));
    try std.testing.expect(session.frames.get(frame_id).?.capture_failed);
    try std.testing.expectEqual(@as(usize, max_update_rows), session.frames.get(frame_id).?.update_row_count);
}

test "real damage capture replaces full-frame fallback" {
    const a = std.testing.allocator;
    const session = try Session.create(a, 9);
    defer session.destroy();
    const terminal_id = try session.createTerminal();
    const frame_id = try session.createFrame(terminal_id);
    const window_id = try session.createWindow(frame_id);
    _ = window_id;

    try session.beginFrame(frame_id);
    try session.recordDamage(frame_id, 2, 3, 40, 10);
    try session.recordDamage(frame_id, 5, 30, 60, 12);
    try session.flushFrame(frame_id, 320, 200);

    const encoded = session.sink.messages.items[session.sink.messages.items.len - 1];
    const payload = try protocol.decodeEnvelope(encoded);
    const update = try protocol.decodeFrameUpdate(a, payload.bytes);
    defer a.free(update.sections);
    try std.testing.expectEqual(@as(u8, 1), update.header.damage_mode);
    var damage = update.sections[0];
    for (update.sections) |section| {
        if (section.kind == protocol.SectionKind.damage) damage = section;
    }
    try std.testing.expectEqual(protocol.SectionKind.damage, damage.kind);
    try std.testing.expectEqual(@as(usize, 2 * damage_record_size), damage.records.len);
    try std.testing.expectEqual(@as(i32, 2), std.mem.readInt(i32, damage.records[0..4], .little));
    try std.testing.expectEqual(@as(i32, 40), std.mem.readInt(i32, damage.records[8..12], .little));
    try std.testing.expectEqual(@as(i32, 5), std.mem.readInt(i32, damage.records[16..20], .little));
    try std.testing.expectEqual(@as(i32, 60), std.mem.readInt(i32, damage.records[24..28], .little));
}

test "damage capture enforces capacity and invalid rectangles" {
    const a = std.testing.allocator;
    const session = try Session.create(a, 10);
    defer session.destroy();
    const terminal_id = try session.createTerminal();
    const frame_id = try session.createFrame(terminal_id);
    try session.beginFrame(frame_id);
    try std.testing.expectError(
        LifecycleError.InvalidFrame,
        session.recordDamage(frame_id, 0, 0, -1, 1),
    );

    for (0..max_update_damage) |index| {
        try session.recordDamage(frame_id, 0, @intCast(index), 8, 4);
    }
    try std.testing.expectError(
        LifecycleError.DamageLimit,
        session.recordDamage(frame_id, 0, max_update_damage, 8, 4),
    );
    try std.testing.expectError(LifecycleError.DamageLimit, session.flushFrame(frame_id, 100, 100));
    try std.testing.expect(session.frames.get(frame_id).?.capture_failed);
}
