//! Adapter-owned bridge from the pure runtime host ABI to bounded EUP frames.
//!
//! This module prepares the future pure SDL3 path: it drives the reviewed
//! PureRuntimeHostV1 contract and emits deterministic frame lifecycle/update
//! messages.  It does not register an Emacs terminal, attach a host adapter,
//! initialize PGTK, enable output_proto, or touch inherited GNU Emacs code.

const std = @import("std");
const frontend = @import("frontend.zig");
const protocol = @import("protocol.zig");
const runtime_host = @import("runtime_host.zig");

pub const Error = runtime_host.Error || frontend.Error || protocol.Error ||
    error{
        InvalidState,
        InvalidFrameIdentity,
        OutputTooLarge,
        UnknownWindow,
        DuplicateWindow,
        DuplicateRow,
        DuplicateRun,
        DuplicateCursor,
        TooManyWindows,
        TooManyRows,
        TooManyRuns,
        TooManyCursors,
        TooManyDamage,
    };

pub const max_windows: usize = 4;
pub const max_rows: usize = 32;
pub const max_runs: usize = 64;
pub const max_cursors: usize = 4;
pub const max_damage: usize = 32;

pub const State = enum {
    idle,
    terminal_active,
    frame_registered,
    capturing,
    captured,
    destroyed,
};

pub const Counts = struct {
    windows: usize = 0,
    rows: usize = 0,
    runs: usize = 0,
    cursors: usize = 0,
    damage: usize = 0,
};

pub const Bridge = struct {
    table: runtime_host.PureRuntimeHostV1,
    state: State = .idle,
    terminal: runtime_host.Identity = .{},
    host_frame: runtime_host.Identity = .{},
    frame: runtime_host.Identity = .{},
    eup_frame_generation: u32 = 1,
    capture: runtime_host.Identity = .{},
    redisplay_generation: u64 = 0,
    windows: [max_windows]runtime_host.WindowRecord = undefined,
    rows: [max_rows]runtime_host.RowRecord = undefined,
    runs: [max_runs]runtime_host.RunRecord = undefined,
    cursors: [max_cursors]runtime_host.CursorRecord = undefined,
    damage: [max_damage]runtime_host.DamageRecord = undefined,
    counts: Counts = .{},

    pub fn init(table: runtime_host.PureRuntimeHostV1) Error!Bridge {
        try runtime_host.validateTable(&table);
        return .{ .table = table };
    }

    fn requireState(self: *const Bridge, state: State) Error!void {
        if (self.state != state) return error.InvalidState;
    }

    fn status(result: runtime_host.Status) Error!void {
        if (result != .ok) return error.HostCallbackFailed;
    }

    fn terminalGroup(self: *const Bridge) Error!*const runtime_host.TerminalGroupV1 {
        return self.table.terminal orelse error.InvalidRuntimeHost;
    }

    fn frameGroup(self: *const Bridge) Error!*const runtime_host.FrameGroupV1 {
        return self.table.frame orelse error.InvalidRuntimeHost;
    }

    fn redisplayGroup(self: *const Bridge) Error!*const runtime_host.RedisplayGroupV1 {
        return self.table.redisplay orelse error.InvalidRuntimeHost;
    }

    pub fn createTerminal(
        self: *Bridge,
        request: runtime_host.TerminalCreateRequest,
    ) Error!void {
        try self.requireState(.idle);
        const group = try self.terminalGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.create_terminal orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &request, &self.terminal));
        self.state = .terminal_active;
    }

    pub fn activateTerminal(self: *Bridge) Error!void {
        try self.requireState(.terminal_active);
        const group = try self.terminalGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.activate_terminal orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &self.terminal));
    }

    pub fn registerFrame(self: *Bridge, host_frame: runtime_host.Identity) Error!void {
        try self.requireState(.terminal_active);
        try runtime_host.validateIdentity(&host_frame);
        const group = try self.frameGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.register_frame orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &host_frame, &self.frame));
        if (!self.frame.valid() or self.frame.id > std.math.maxInt(u32))
            return error.InvalidFrameIdentity;
        self.host_frame = host_frame;
        self.state = .frame_registered;
    }

    pub fn beginCapture(self: *Bridge, redisplay_generation: u64) Error!void {
        try self.requireState(.frame_registered);
        if (redisplay_generation == 0 or redisplay_generation != self.frame.generation)
            return error.InvalidFrameIdentity;
        const request: runtime_host.CaptureRequest = .{
            .frame = self.frame,
            .redisplay_generation = redisplay_generation,
        };
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.begin_capture orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &request, &self.capture));
        self.redisplay_generation = redisplay_generation;
        self.state = .capturing;
    }

    fn knownWindow(self: *const Bridge, window_id: u64) bool {
        for (self.windows[0..self.counts.windows]) |window| {
            if (window.id == window_id) return true;
        }
        return false;
    }

    pub fn observeWindow(self: *Bridge, record: runtime_host.WindowRecord) Error!void {
        try self.requireState(.capturing);
        try runtime_host.validateWindowRecord(&record);
        if (record.generation != self.frame.generation) return error.InvalidFrameIdentity;
        if (self.counts.windows == max_windows) return error.TooManyWindows;
        for (self.windows[0..self.counts.windows]) |existing| {
            if (existing.id == record.id) return error.DuplicateWindow;
        }
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.observe_window orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &self.capture, &record));
        self.windows[self.counts.windows] = record;
        self.counts.windows += 1;
    }

    fn requireObservedWindow(self: *const Bridge, window_id: u64) Error!void {
        for (self.windows[0..self.counts.windows]) |window| {
            if (window.id == window_id) return;
        }
        return error.UnknownWindow;
    }

    pub fn observeRow(self: *Bridge, record: runtime_host.RowRecord) Error!void {
        try self.requireState(.capturing);
        try runtime_host.validateRowRecord(&record);
        try self.requireObservedWindow(record.window_id);
        if (self.counts.rows == max_rows) return error.TooManyRows;
        for (self.rows[0..self.counts.rows]) |existing| {
            if (existing.window_id == record.window_id and existing.row_index == record.row_index)
                return error.DuplicateRow;
        }
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.observe_row orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &self.capture, &record));
        self.rows[self.counts.rows] = record;
        self.counts.rows += 1;
    }

    pub fn observeRun(self: *Bridge, record: runtime_host.RunRecord) Error!void {
        try self.requireState(.capturing);
        try runtime_host.validateRunRecord(&record);
        try self.requireObservedWindow(record.window_id);
        if (self.counts.runs == max_runs) return error.TooManyRuns;
        for (self.runs[0..self.counts.runs]) |existing| {
            if (existing.run_id == record.run_id) return error.DuplicateRun;
        }
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.observe_run orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &self.capture, &record));
        self.runs[self.counts.runs] = record;
        self.counts.runs += 1;
    }

    pub fn observeCursor(self: *Bridge, record: runtime_host.CursorRecord) Error!void {
        try self.requireState(.capturing);
        try runtime_host.validateCursorRecord(&record);
        try self.requireObservedWindow(record.window_id);
        if (self.counts.cursors == max_cursors) return error.TooManyCursors;
        for (self.cursors[0..self.counts.cursors]) |existing| {
            if (existing.window_id == record.window_id) return error.DuplicateCursor;
        }
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.observe_cursor orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &self.capture, &record));
        self.cursors[self.counts.cursors] = record;
        self.counts.cursors += 1;
    }

    pub fn observeDamage(self: *Bridge, record: runtime_host.DamageRecord) Error!void {
        try self.requireState(.capturing);
        try runtime_host.validateDamageRecord(&record);
        if (self.counts.damage == max_damage) return error.TooManyDamage;
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.observe_damage orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &self.capture, &record));
        self.damage[self.counts.damage] = record;
        self.counts.damage += 1;
    }

    pub fn commitCapture(self: *Bridge) Error!void {
        try self.requireState(.capturing);
        if (self.counts.windows == 0 or self.counts.rows == 0)
            return error.InvalidState;
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.commit_capture orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &self.capture));
        self.state = .captured;
    }

    pub fn snapshotCounts(self: *const Bridge) Counts {
        return self.counts;
    }

    pub fn encodeFrameCreate(
        self: *const Bridge,
        gpa: std.mem.Allocator,
        sequence: u64,
        session_id: u64,
        timestamp_ns: u64,
        out: *std.ArrayList(u8),
    ) Error!void {
        switch (self.state) {
            .frame_registered, .capturing, .captured => {},
            else => return error.InvalidState,
        }
        const frame_id: u32 = @intCast(self.frame.id);
        var payload: [8]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], frame_id, .little);
        std.mem.writeInt(u32, payload[4..8], self.eup_frame_generation, .little);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.frame_create,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = frame_id,
            .timestamp_ns = timestamp_ns,
        }, &payload, out);
    }

    pub fn encodeFrameUpdate(
        self: *const Bridge,
        gpa: std.mem.Allocator,
        sequence: u64,
        session_id: u64,
        timestamp_ns: u64,
        out: *std.ArrayList(u8),
    ) Error!void {
        try self.requireState(.captured);
        const frame_id: u32 = @intCast(self.frame.id);
        const frame_generation: u32 = self.eup_frame_generation;

        var window_bytes: std.ArrayList(u8) = .empty;
        defer window_bytes.deinit(gpa);
        var row_bytes: std.ArrayList(u8) = .empty;
        defer row_bytes.deinit(gpa);
        var cursor_bytes: std.ArrayList(u8) = .empty;
        defer cursor_bytes.deinit(gpa);
        var damage_bytes: std.ArrayList(u8) = .empty;
        defer damage_bytes.deinit(gpa);

        for (self.windows[0..self.counts.windows]) |record| {
            try frontend.encodeWindow(gpa, .{
                .id = record.id,
                .frame_id = frame_id,
                .x = record.x,
                .y = record.y,
                .width = record.width,
                .height = record.height,
            }, &window_bytes);
        }
        for (self.rows[0..self.counts.rows]) |record| {
            try frontend.encodeRow(gpa, .{
                .window_id = record.window_id,
                .index = record.row_index,
                .x = record.x,
                .y = record.y,
                .width = record.width,
                .height = record.height,
                .ascent = record.ascent,
                .descent = record.descent,
                .baseline = record.baseline,
                .visible_height = record.visible_height,
                .flags = record.flags,
            }, &row_bytes);
        }
        for (self.cursors[0..self.counts.cursors]) |record| {
            try frontend.encodeCursor(gpa, .{
                .window_id = record.window_id,
                .x = record.x,
                .y = record.y,
                .width = record.width,
                .height = record.height,
                .kind = record.kind,
                .visible = record.visible,
                .active = record.active,
            }, &cursor_bytes);
        }
        for (self.damage[0..self.counts.damage]) |record| {
            try frontend.encodeRect(gpa, .{
                .x = record.x,
                .y = record.y,
                .width = record.width,
                .height = record.height,
            }, &damage_bytes);
        }

        const sections = [_]protocol.Section{
            .{ .kind = protocol.SectionKind.windows, .records = window_bytes.items },
            .{ .kind = protocol.SectionKind.rows, .records = row_bytes.items },
            .{ .kind = protocol.SectionKind.cursors, .records = cursor_bytes.items },
            .{ .kind = protocol.SectionKind.damage, .records = damage_bytes.items },
        };
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        try protocol.encodeFrameUpdate(gpa, .{
            .header = .{
                .frame_id = frame_id,
                .frame_generation = frame_generation,
                .sequence = sequence,
                .redisplay_generation = self.redisplay_generation,
                .logical_x = 0,
                .logical_y = 0,
                .logical_width = @intCast(self.windows[0].width),
                .logical_height = @intCast(self.windows[0].height),
                .physical_x = 0,
                .physical_y = 0,
                .physical_width = @intCast(self.windows[0].width),
                .physical_height = @intCast(self.windows[0].height),
                .scale = 1.0,
                .dpi_x = 96.0,
                .dpi_y = 96.0,
                .damage_mode = 2,
                .update_cause = 1,
                .coalesced_count = 0,
                .timestamp_ns = timestamp_ns,
            },
            .sections = &sections,
        }, &payload);
        try protocol.encodeEnvelope(gpa, .{
            .flags = protocol.Flags.delta,
            .message_type = protocol.Message.frame_update,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = frame_id,
            .timestamp_ns = timestamp_ns,
        }, payload.items, out);
    }

    pub fn destroy(self: *Bridge) Error!void {
        if (self.state == .destroyed or self.state == .idle) return error.InvalidState;
        if (self.state == .capturing) {
            const redisplay = try self.redisplayGroup();
            const redisplay_context = redisplay.context orelse return error.InvalidRuntimeHost;
            const cancel = redisplay.cancel_capture orelse return error.InvalidRuntimeHost;
            try runtime_host.ensureOk(cancel(redisplay_context, &self.capture));
        }
        if (self.state != .terminal_active) {
            const frame = try self.frameGroup();
            const frame_context = frame.context orelse return error.InvalidRuntimeHost;
            const unregister = frame.unregister_frame orelse return error.InvalidRuntimeHost;
            try runtime_host.ensureOk(unregister(frame_context, &self.frame));
        }
        const terminal = try self.terminalGroup();
        const terminal_context = terminal.context orelse return error.InvalidRuntimeHost;
        const delete_terminal = terminal.delete_terminal orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(delete_terminal(terminal_context, &self.terminal));
        self.state = .destroyed;
    }

    pub fn encodeFrameDestroy(
        self: *const Bridge,
        gpa: std.mem.Allocator,
        sequence: u64,
        session_id: u64,
        timestamp_ns: u64,
        out: *std.ArrayList(u8),
    ) Error!void {
        try self.requireState(.destroyed);
        const frame_id: u32 = @intCast(self.frame.id);
        var payload: [8]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], frame_id, .little);
        std.mem.writeInt(u32, payload[4..8], self.eup_frame_generation, .little);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.frame_destroy,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = frame_id,
            .timestamp_ns = timestamp_ns,
        }, &payload, out);
    }
};

test "pure runtime bridge produces a valid bounded EUP frame lifecycle" {
    const gpa = std.testing.allocator;
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);

    try bridge.createTerminal(.{ .requested_generation = 1 });
    try bridge.activateTerminal();
    try bridge.registerFrame(.{ .id = 22, .generation = 8 });
    try bridge.beginCapture(8);

    try bridge.observeWindow(.{ .id = 10, .generation = 8, .width = 80, .height = 60 });
    try bridge.observeRow(.{ .window_id = 10, .row_index = 0, .width = 80, .height = 10, .ascent = 7, .descent = 3, .baseline = 7, .visible_height = 10 });
    try bridge.observeRun(.{ .run_id = 1, .window_id = 10, .row_index = 0, .byte_length = 5 });
    try bridge.observeCursor(.{ .window_id = 10, .x = 0, .y = 0, .width = 2, .height = 8, .visible = true, .active = true });
    try bridge.observeDamage(.{ .width = 80, .height = 60 });
    try std.testing.expectEqual(Counts{ .windows = 1, .rows = 1, .runs = 1, .cursors = 1, .damage = 1 }, bridge.snapshotCounts());
    try bridge.commitCapture();

    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();

    var create: std.ArrayList(u8) = .empty;
    defer create.deinit(gpa);
    try bridge.encodeFrameCreate(gpa, 1, 9, 1, &create);
    try scene.apply(create.items);

    var update: std.ArrayList(u8) = .empty;
    defer update.deinit(gpa);
    try bridge.encodeFrameUpdate(gpa, 2, 9, 2, &update);
    try scene.apply(update.items);

    try std.testing.expectEqual(@as(usize, 1), scene.windows.items.len);
    try std.testing.expectEqual(@as(usize, 1), scene.rows.items.len);
    try std.testing.expect(scene.cursor != null);

    try bridge.destroy();
    var destroy: std.ArrayList(u8) = .empty;
    defer destroy.deinit(gpa);
    try bridge.encodeFrameDestroy(gpa, 3, 9, 3, &destroy);
    try scene.apply(destroy.items);
    try std.testing.expectEqual(State.destroyed, bridge.state);
    try std.testing.expectEqual(@as(usize, 0), scene.windows.items.len);
}

test "bridge rejects observations outside capturing state without mutation" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);

    try std.testing.expectError(error.InvalidState, bridge.observeWindow(.{ .id = 1, .generation = 1 }));
    try std.testing.expectEqual(State.idle, bridge.state);
    try std.testing.expectEqual(Counts{}, bridge.snapshotCounts());
}
