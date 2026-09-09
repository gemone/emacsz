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
        DuplicateFace,
        DuplicateFont,
        DuplicateImage,
        DuplicateCursor,
        TooManyWindows,
        TooManyRows,
        TooManyRuns,
        TooManyShapedRuns,
        DuplicateShapedRun,
        TooManyFaces,
        TooManyFonts,
        TooManyImages,
        TooManyImageBytes,
        TooManyCursors,
        TooManyDamage,
        DuplicateInput,
        TooManyInputs,
        UnknownInput,
    };

pub const max_windows: usize = 16;
pub const max_rows: usize = 256;
pub const max_runs: usize = 64;
pub const max_shaped_runs: usize = 16;
pub const max_faces: usize = 8;
pub const max_fonts: usize = 8;
pub const max_images: usize = 4;
pub const max_image_capture_bytes: usize = 4096;
pub const max_image_capture_fragments: u16 = 4;
pub const max_image_capture_fragment_bytes: usize = 1024;
pub const max_cursors: usize = 16;
pub const max_damage: usize = 32;
pub const max_tracked_inputs: usize = 16;

pub const input_kind_key: u16 = 1;
pub const input_kind_text: u16 = 2;
pub const input_kind_pointer_button: u16 = 3;
pub const input_kind_pointer_motion: u16 = 4;
pub const input_kind_wheel: u16 = 5;

fn invalidIdentityTerminalCreate(
    context: *anyopaque,
    request: *const runtime_host.TerminalCreateRequest,
    result: *runtime_host.Identity,
) callconv(.c) runtime_host.Status {
    _ = context;
    _ = request;
    result.* = .{};
    return .ok;
}

fn failingShapedRun(
    context: *anyopaque,
    session: *const runtime_host.Identity,
    record: *const runtime_host.ShapedRunRecord,
) callconv(.c) runtime_host.Status {
    _ = context;
    _ = session;
    _ = record;
    return .failed;
}

fn invalidIdentityCaptureBegin(
    context: *anyopaque,
    request: *const runtime_host.CaptureRequest,
    result: *runtime_host.Identity,
) callconv(.c) runtime_host.Status {
    _ = context;
    _ = request;
    result.* = .{};
    return .ok;
}

pub const InputState = struct {
    accepted: bool = false,
    result_reported: bool = false,
    completed: bool = false,
    cancelled: bool = false,
};

pub const LifecycleCounters = struct {
    heartbeats: usize = 0,
    flushes: usize = 0,
    diagnostics: usize = 0,
    cancellations: usize = 0,
};

pub const State = enum {
    idle,
    terminal_active,
    frame_registered,
    capturing,
    captured,
    destroyed,
};

pub const FrameRuntimeState = struct {
    host_generation: u64,
    visibility: runtime_host.adapter.FrameVisibility,
    focused: bool,
};

pub const FrameStateChange = struct {
    visibility_changed: bool,
    focus_changed: bool,
    state: FrameRuntimeState,
};

pub const Counts = struct {
    windows: usize = 0,
    rows: usize = 0,
    runs: usize = 0,
    shaped_runs: usize = 0,
    faces: usize = 0,
    fonts: usize = 0,
    images: usize = 0,
    cursors: usize = 0,
    damage: usize = 0,
};

pub const RenderHintRequest = struct {
    mode: protocol.RenderHintMode = .auto,
    workload: protocol.RenderHintWorkload = .unspecified,
    damage_only_allowed: bool = false,
    refresh_interval_ns: u64 = 0,
    deadline_ns: u64 = 0,
};

pub const ImageCapture = struct {
    metadata: protocol.ImageDefine,
    fragment_count: u16 = 0,
    bytes: [max_image_capture_bytes]u8 = undefined,
    fragment_lengths: [max_image_capture_fragments]usize = [_]usize{0} ** max_image_capture_fragments,
    bytes_received: usize = 0,
    fragments_received: u16 = 0,
    complete: bool = false,
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
    shaped_runs: [max_shaped_runs]runtime_host.ShapedRunRecord = undefined,
    faces: [max_faces]protocol.FaceDefine = undefined,
    fonts: [max_fonts]protocol.FontDefine = undefined,
    images: [max_images]ImageCapture = undefined,
    cursors: [max_cursors]runtime_host.CursorRecord = undefined,
    damage: [max_damage]runtime_host.DamageRecord = undefined,
    counts: Counts = .{},
    input_ids: [max_tracked_inputs]u64 = undefined,
    input_states: [max_tracked_inputs]InputState = undefined,
    input_count: usize = 0,
    lifecycle: LifecycleCounters = .{},
    last_encoded_frame_sequence: u64 = 0,
    last_accepted_frame_sequence: u64 = 0,
    last_emitted_flush_frame_sequence: u64 = 0,
    render_hint: ?protocol.RenderHintPayload = null,
    frame_state: ?FrameRuntimeState = null,
    frame_geometry: ?runtime_host.adapter.Geometry = null,

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
        var created: runtime_host.Identity = .{};
        try runtime_host.ensureOk(callback(context, &request, &created));
        try runtime_host.validateIdentity(&created);
        self.terminal = created;
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
        var registered: runtime_host.Identity = .{};
        try runtime_host.ensureOk(callback(context, &host_frame, &registered));
        if (!registered.valid() or registered.id > std.math.maxInt(u32))
            return error.InvalidFrameIdentity;
        self.frame = registered;
        self.host_frame = host_frame;
        self.state = .frame_registered;
    }

    pub fn beginCapture(self: *Bridge, redisplay_generation: u64) Error!void {
        switch (self.state) {
            .frame_registered, .captured => {},
            else => return error.InvalidState,
        }
        if (redisplay_generation == 0 or redisplay_generation > std.math.maxInt(u32) or
            (self.state == .captured and redisplay_generation <= self.redisplay_generation))
            return error.InvalidFrameIdentity;
        const request: runtime_host.CaptureRequest = .{
            .frame = self.frame,
            .redisplay_generation = redisplay_generation,
        };
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.begin_capture orelse return error.InvalidRuntimeHost;
        var capture: runtime_host.Identity = .{};
        try runtime_host.ensureOk(callback(context, &request, &capture));
        try runtime_host.validateIdentity(&capture);
        self.capture = capture;
        self.redisplay_generation = redisplay_generation;
        self.counts = .{};
        self.last_encoded_frame_sequence = 0;
        self.last_accepted_frame_sequence = 0;
        self.last_emitted_flush_frame_sequence = 0;
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
        if (self.frame_geometry) |bounds| {
            if (record.x < bounds.x or record.y < bounds.y or
                @as(i64, record.x) + record.width > @as(i64, bounds.x) + bounds.width or
                @as(i64, record.y) + record.height > @as(i64, bounds.y) + bounds.height)
                return error.InvalidFrameIdentity;
        }
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
        for (self.shaped_runs[0..self.counts.shaped_runs]) |existing| {
            if (existing.run_id == record.run_id) return error.DuplicateRun;
        }
        if (record.face_id != 0) {
            const face = self.findFace(record.face_id) orelse return error.InvalidState;
            if (face.generation != record.face_generation) return error.InvalidState;
        }
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.observe_run orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &self.capture, &record));
        self.runs[self.counts.runs] = record;
        self.counts.runs += 1;
    }

    pub fn observeShapedRun(self: *Bridge, record: runtime_host.ShapedRunRecord) Error!void {
        try self.requireState(.capturing);
        try runtime_host.validateShapedRunRecord(&record);
        try self.requireObservedWindow(record.window_id);
        if (self.counts.shaped_runs == max_shaped_runs) return error.TooManyShapedRuns;
        for (self.runs[0..self.counts.runs]) |existing| {
            if (existing.run_id == record.run_id) return error.DuplicateShapedRun;
        }
        for (self.shaped_runs[0..self.counts.shaped_runs]) |existing| {
            if (existing.run_id == record.run_id) return error.DuplicateShapedRun;
        }
        const face = self.findFace(record.face_id) orelse return error.InvalidState;
        if (face.generation != record.face_generation or
            !face.presence.font or face.font_id != record.font_id)
            return error.InvalidState;
        const font = self.findFont(record.font_id) orelse return error.InvalidState;
        if (font.generation != face.font_generation) return error.InvalidState;
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.observe_shaped_run orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &self.capture, &record));
        self.shaped_runs[self.counts.shaped_runs] = record;
        self.counts.shaped_runs += 1;
    }

    pub fn observeFace(self: *Bridge, record: runtime_host.FaceRecord) Error!void {
        try self.requireState(.capturing);
        try runtime_host.validateFaceRecord(&record);
        const face = try protocol.decodeFaceDefine(&record.bytes);
        if (self.counts.faces == max_faces) return error.TooManyFaces;
        for (self.faces[0..self.counts.faces]) |existing| {
            if (existing.face_id == face.face_id) return error.DuplicateFace;
        }
        if (face.presence.font) {
            const font = self.findFont(face.font_id) orelse return error.InvalidState;
            if (font.generation != face.font_generation) return error.InvalidState;
        }
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.observe_face orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &self.capture, &record));
        self.faces[self.counts.faces] = face;
        self.counts.faces += 1;
    }

    pub fn observeFont(self: *Bridge, record: runtime_host.FontRecord) Error!void {
        try self.requireState(.capturing);
        try runtime_host.validateFontRecord(&record);
        const font = try protocol.decodeFontDefine(&record.bytes);
        if (self.counts.fonts == max_fonts) return error.TooManyFonts;
        for (self.fonts[0..self.counts.fonts]) |existing| {
            if (existing.font_id == font.font_id) return error.DuplicateFont;
        }
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.observe_font orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &self.capture, &record));
        self.fonts[self.counts.fonts] = font;
        self.counts.fonts += 1;
    }

    pub fn observeImageDefine(self: *Bridge, record: runtime_host.ImageDefineRecord) Error!void {
        try self.requireState(.capturing);
        try runtime_host.validateImageDefineRecord(&record);
        const metadata = try protocol.decodeImageDefine(&record.bytes);
        if (metadata.total_byte_count > max_image_capture_bytes)
            return error.TooManyImageBytes;
        if (self.counts.images == max_images) return error.TooManyImages;
        for (self.images[0..self.counts.images]) |existing| {
            if (existing.metadata.image_id == metadata.image_id)
                return error.DuplicateImage;
        }
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.observe_image_define orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &self.capture, &record));
        self.images[self.counts.images] = .{ .metadata = metadata };
        self.counts.images += 1;
    }

    pub fn observeImageFragment(self: *Bridge, record: runtime_host.ImageFragmentRecord) Error!void {
        try self.requireState(.capturing);
        try runtime_host.validateImageFragmentRecord(&record);
        var index: ?usize = null;
        for (self.images[0..self.counts.images], 0..) |*image, candidate| {
            if (image.metadata.image_id == record.image_id) index = candidate;
        }
        const image_index = index orelse return error.InvalidState;
        const image = &self.images[image_index];
        if (image.complete or image.metadata.generation != record.generation or
            (image.fragment_count != 0 and record.fragment_count != image.fragment_count) or
            record.fragment_index != image.fragments_received or
            image.bytes_received + record.byte_length > image.metadata.total_byte_count)
            return error.InvalidState;
        const group = try self.redisplayGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.observe_image_fragment orelse return error.InvalidRuntimeHost;
        const expected_count = if (image.fragment_count == 0) record.fragment_count else image.fragment_count;
        try runtime_host.ensureOk(callback(context, &self.capture, &record));
        image.fragment_count = expected_count;
        @memcpy(
            image.bytes[image.bytes_received..][0..record.byte_length],
            record.bytes[0..record.byte_length],
        );
        image.bytes_received += record.byte_length;
        image.fragment_lengths[record.fragment_index] = record.byte_length;
        image.fragments_received += 1;
        image.complete = image.bytes_received == image.metadata.total_byte_count and
            image.fragments_received == image.fragment_count;
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
        const bounds = self.frame_geometry orelse return error.InvalidState;
        if (@as(i64, record.x) + record.width > @as(i64, bounds.x) + bounds.width or
            @as(i64, record.y) + record.height > @as(i64, bounds.y) + bounds.height)
            return error.InvalidState;
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
        var active_cursors: usize = 0;
        for (self.cursors[0..self.counts.cursors]) |cursor| {
            if (cursor.active) active_cursors += 1;
        }
        if (self.counts.cursors != 0 and active_cursors != 1)
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

    pub fn refreshFrameGeometry(self: *Bridge) Error!runtime_host.adapter.Geometry {
        switch (self.state) {
            .frame_registered, .capturing, .captured => {},
            else => return error.InvalidState,
        }
        const group = try self.frameGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.read_geometry orelse return error.InvalidRuntimeHost;
        var geometry: runtime_host.adapter.Geometry = .{};
        try runtime_host.ensureOk(callback(context, &self.frame, &geometry));
        try runtime_host.validateGeometry(&geometry);
        if (geometry.width <= 0 or geometry.height <= 0)
            return error.InvalidFrameIdentity;
        self.frame_geometry = geometry;
        return geometry;
    }

    pub fn geometrySnapshot(self: *const Bridge) ?runtime_host.adapter.Geometry {
        return self.frame_geometry;
    }

    pub fn refreshFrameState(self: *Bridge) Error!FrameStateChange {
        switch (self.state) {
            .frame_registered, .capturing, .captured => {},
            else => return error.InvalidState,
        }
        const group = try self.frameGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.read_frame_state orelse return error.InvalidRuntimeHost;
        var observed: runtime_host.adapter.FrameState = .{};
        try runtime_host.ensureOk(callback(context, &self.frame, &observed));
        try runtime_host.validateFrameState(&observed);
        if (observed.generation != self.frame.generation)
            return error.InvalidFrameIdentity;
        const visibility: runtime_host.adapter.FrameVisibility = @enumFromInt(observed.visibility);
        const focused = observed.focused != 0;
        if (visibility != .visible and focused)
            return error.InvalidFrameIdentity;

        const previous = self.frame_state;
        const next: FrameRuntimeState = .{
            .host_generation = observed.generation,
            .visibility = visibility,
            .focused = focused,
        };
        self.frame_state = next;
        return .{
            .visibility_changed = previous == null or
                previous.?.visibility != next.visibility,
            .focus_changed = previous == null or
                previous.?.focused != next.focused,
            .state = next,
        };
    }

    pub fn encodeFrameVisibility(
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
        const cached = self.frame_state orelse return error.InvalidState;
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        try protocol.encodeFrameVisibility(gpa, .{
            .frame_id = @intCast(self.frame.id),
            .frame_generation = self.eup_frame_generation,
            .state = @enumFromInt(@intFromEnum(cached.visibility)),
        }, &payload);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.frame_visibility,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = @intCast(self.frame.id),
            .timestamp_ns = timestamp_ns,
        }, payload.items, out);
    }

    pub fn encodeFrameFocus(
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
        const cached = self.frame_state orelse return error.InvalidState;
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        try protocol.encodeFrameFocus(gpa, .{
            .frame_id = @intCast(self.frame.id),
            .frame_generation = self.eup_frame_generation,
            .focused = cached.focused,
        }, &payload);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.frame_focus,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = @intCast(self.frame.id),
            .timestamp_ns = timestamp_ns,
        }, payload.items, out);
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
        self: *Bridge,
        gpa: std.mem.Allocator,
        sequence: u64,
        session_id: u64,
        timestamp_ns: u64,
        out: *std.ArrayList(u8),
    ) Error!void {
        try self.requireState(.captured);
        if (sequence == 0 or sequence <= self.last_encoded_frame_sequence)
            return error.InvalidState;
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

        const bounds = self.frame_geometry orelse return error.InvalidState;
        const header_x: i32 = bounds.x;
        const header_y: i32 = bounds.y;
        const header_width: i32 = bounds.width;
        const header_height: i32 = bounds.height;
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
                .logical_x = header_x,
                .logical_y = header_y,
                .logical_width = header_width,
                .logical_height = header_height,
                .physical_x = header_x,
                .physical_y = header_y,
                .physical_width = header_width,
                .physical_height = header_height,
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
        self.last_encoded_frame_sequence = sequence;
    }

    /// Marks the just-encoded frame as accepted by the Scene/consumer.  A
    /// rejected encode remains a sender-side fact and cannot be flushed.
    pub fn acceptFrameUpdate(self: *Bridge, sequence: u64) Error!void {
        try self.requireState(.captured);
        if (sequence == 0 or sequence != self.last_encoded_frame_sequence)
            return error.InvalidState;
        self.last_accepted_frame_sequence = sequence;
    }

    pub fn encodeDamageRects(
        self: *const Bridge,
        gpa: std.mem.Allocator,
        sequence: u64,
        session_id: u64,
        timestamp_ns: u64,
        out: *std.ArrayList(u8),
    ) Error!void {
        try self.requireState(.captured);
        if (self.last_accepted_frame_sequence == 0 or sequence == 0)
            return error.InvalidState;
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        var rects: std.ArrayList(frontend.Rect) = .empty;
        defer rects.deinit(gpa);
        for (self.damage[0..self.counts.damage]) |record| {
            try rects.append(gpa, .{
                .x = record.x,
                .y = record.y,
                .width = record.width,
                .height = record.height,
            });
        }
        try frontend.encodeDamageRects(gpa, self.eup_frame_generation, rects.items, &payload);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.damage_rects,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = @intCast(self.frame.id),
            .timestamp_ns = timestamp_ns,
        }, payload.items, out);
    }

    pub fn setRenderHint(self: *Bridge, request: RenderHintRequest) Error!void {
        switch (self.state) {
            .frame_registered, .capturing, .captured => {},
            else => return error.InvalidState,
        }
        const payload: protocol.RenderHintPayload = .{
            .flags = (if (request.damage_only_allowed) protocol.RenderHintFlags.damage_only_allowed else 0) |
                (if (request.deadline_ns != 0) protocol.RenderHintFlags.deadline_present else 0) |
                (if (request.refresh_interval_ns != 0) protocol.RenderHintFlags.refresh_interval_present else 0),
            .preferred_mode = request.mode,
            .workload = request.workload,
            .frame_generation = self.eup_frame_generation,
            .refresh_interval_ns = request.refresh_interval_ns,
            .deadline_ns = request.deadline_ns,
        };
        try protocol.validateRenderHint(payload);
        self.render_hint = payload;
    }

    pub fn encodeFlush(
        self: *Bridge,
        gpa: std.mem.Allocator,
        sequence: u64,
        session_id: u64,
        timestamp_ns: u64,
        out: *std.ArrayList(u8),
    ) Error!void {
        try self.requireState(.captured);
        if (self.last_accepted_frame_sequence == 0 or
            self.last_emitted_flush_frame_sequence == self.last_accepted_frame_sequence)
            return error.InvalidState;
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        try protocol.encodeFrameFlush(gpa, .{
            .flags = protocol.FrameFlushFlags.present_required,
            .frame_generation = self.eup_frame_generation,
            .redisplay_generation = self.redisplay_generation,
            .frame_sequence = self.last_accepted_frame_sequence,
            .deadline_ns = 0,
            .damage_kind = .full,
        }, &payload);
        try self.flush();
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.flush,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = @intCast(self.frame.id),
            .timestamp_ns = timestamp_ns,
        }, payload.items, out);
        self.last_emitted_flush_frame_sequence = self.last_accepted_frame_sequence;
    }

    pub fn encodeRenderHint(
        self: *const Bridge,
        gpa: std.mem.Allocator,
        sequence: u64,
        session_id: u64,
        timestamp_ns: u64,
        out: *std.ArrayList(u8),
    ) Error!void {
        try self.requireState(.captured);
        const payload_state = self.render_hint orelse return error.InvalidState;
        if (payload_state.frame_generation != self.eup_frame_generation)
            return error.InvalidFrameIdentity;
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        try protocol.encodeRenderHint(gpa, payload_state, &payload);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.render_hint,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = @intCast(self.frame.id),
            .timestamp_ns = timestamp_ns,
        }, payload.items, out);
    }

    pub fn encodeRun(
        self: *const Bridge,
        gpa: std.mem.Allocator,
        run_index: usize,
        sequence: u64,
        session_id: u64,
        timestamp_ns: u64,
        out: *std.ArrayList(u8),
    ) Error!void {
        try self.requireState(.captured);
        if (run_index >= self.counts.runs) return error.InvalidState;
        const record = self.runs[run_index];
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        const face_bound = record.face_id != 0;
        try frontend.encodeGlyphRun(gpa, .{
            .schema = if (face_bound) 2 else 1,
            .run_id = @intCast(record.run_id),
            .generation = @intCast(self.redisplay_generation),
            .window_id = record.window_id,
            .row_index = record.row_index,
            .face_id = record.face_id,
            .face_generation = record.face_generation,
            .x = record.x,
            .y = record.y,
            .width = record.width,
            .height = record.height,
            .text = record.text[0..record.text_length],
        }, &payload);
        try protocol.encodeEnvelope(gpa, .{
            .flags = protocol.Flags.debug,
            .message_type = protocol.Message.glyph_run,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = @intCast(self.frame.id),
            .timestamp_ns = timestamp_ns,
        }, payload.items, out);
    }

    pub fn encodeShapedRun(
        self: *const Bridge,
        gpa: std.mem.Allocator,
        run_index: usize,
        sequence: u64,
        session_id: u64,
        timestamp_ns: u64,
        out: *std.ArrayList(u8),
    ) Error!void {
        try self.requireState(.captured);
        if (run_index >= self.counts.shaped_runs) return error.InvalidState;
        const record = self.shaped_runs[run_index];
        var glyphs: [runtime_host.max_shaped_run_glyphs]frontend.ShapedGlyph = undefined;
        for (record.glyphs[0..record.glyph_count], 0..) |source, index| {
            glyphs[index] = .{
                .glyph_id = source.glyph_id,
                .cluster = source.cluster,
                .x_offset = source.x_offset,
                .y_offset = source.y_offset,
                .advance_x = source.advance_x,
                .advance_y = source.advance_y,
            };
        }
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        try frontend.encodeGlyphRun(gpa, .{
            .schema = 3,
            .flags = frontend.glyph_shaped_atlas,
            .run_id = @intCast(record.run_id),
            .generation = @intCast(self.redisplay_generation),
            .window_id = record.window_id,
            .row_index = record.row_index,
            .face_id = record.face_id,
            .face_generation = record.face_generation,
            .font_id = record.font_id,
            .x = record.x,
            .y = record.y,
            .width = record.width,
            .height = record.height,
            .text = "",
            .glyphs = glyphs,
            .glyph_count = record.glyph_count,
        }, &payload);
        try protocol.encodeEnvelope(gpa, .{
            .flags = protocol.Flags.debug,
            .message_type = protocol.Message.glyph_run,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = @intCast(self.frame.id),
            .timestamp_ns = timestamp_ns,
        }, payload.items, out);
    }

    pub fn encodeFaceDefine(
        self: *const Bridge,
        gpa: std.mem.Allocator,
        face_index: usize,
        sequence: u64,
        session_id: u64,
        timestamp_ns: u64,
        out: *std.ArrayList(u8),
    ) Error!void {
        try self.requireState(.captured);
        if (face_index >= self.counts.faces) return error.InvalidState;
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        try protocol.encodeFaceDefine(gpa, self.faces[face_index], &payload);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.face_define,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = @intCast(self.frame.id),
            .timestamp_ns = timestamp_ns,
        }, payload.items, out);
    }

    pub fn encodeFontDefine(
        self: *const Bridge,
        gpa: std.mem.Allocator,
        font_index: usize,
        sequence: u64,
        session_id: u64,
        timestamp_ns: u64,
        out: *std.ArrayList(u8),
    ) Error!void {
        try self.requireState(.captured);
        if (font_index >= self.counts.fonts) return error.InvalidState;
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        try protocol.encodeFontDefine(gpa, self.fonts[font_index], &payload);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.font_define,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = @intCast(self.frame.id),
            .timestamp_ns = timestamp_ns,
        }, payload.items, out);
    }

    pub fn encodeImageDefine(
        self: *const Bridge,
        gpa: std.mem.Allocator,
        image_index: usize,
        sequence: u64,
        session_id: u64,
        timestamp_ns: u64,
        out: *std.ArrayList(u8),
    ) Error!void {
        try self.requireState(.captured);
        if (image_index >= self.counts.images) return error.InvalidState;
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        try protocol.encodeImageDefine(gpa, self.images[image_index].metadata, &payload);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.image_define,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = @intCast(self.frame.id),
            .timestamp_ns = timestamp_ns,
        }, payload.items, out);
    }

    pub fn encodeImageFragment(
        self: *const Bridge,
        gpa: std.mem.Allocator,
        image_index: usize,
        fragment_index: u16,
        sequence: u64,
        session_id: u64,
        timestamp_ns: u64,
        out: *std.ArrayList(u8),
    ) Error!void {
        try self.requireState(.captured);
        if (image_index >= self.counts.images) return error.InvalidState;
        const image = self.images[image_index];
        if (fragment_index >= image.fragment_count) return error.InvalidState;
        const length = image.fragment_lengths[fragment_index];
        if (length == 0) return error.InvalidState;
        var offset: usize = 0;
        for (image.fragment_lengths[0..fragment_index]) |prior| offset += prior;
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        try protocol.encodeImageData(gpa, .{
            .image_id = image.metadata.image_id,
            .generation = image.metadata.generation,
            .fragment_index = fragment_index,
            .fragment_count = image.fragments_received,
            .bytes = image.bytes[offset..][0..length],
        }, &payload);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.image_data,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = session_id,
            .frame_id = @intCast(self.frame.id),
            .timestamp_ns = timestamp_ns,
        }, payload.items, out);
    }

    fn findFace(self: *const Bridge, face_id: u32) ?protocol.FaceDefine {
        for (self.faces[0..self.counts.faces]) |face| {
            if (face.face_id == face_id) return face;
        }
        return null;
    }

    fn findFont(self: *const Bridge, font_id: u32) ?protocol.FontDefine {
        for (self.fonts[0..self.counts.fonts]) |font| {
            if (font.font_id == font_id) return font;
        }
        return null;
    }

    fn findInput(self: *const Bridge, event_id: u64) ?usize {
        for (self.input_ids[0..self.input_count], 0..) |candidate, index| {
            if (candidate == event_id) return index;
        }
        return null;
    }

    fn checkInputCapacity(self: *const Bridge, event_id: u64) Error!void {
        if (event_id == 0) return error.InvalidState;
        if (self.findInput(event_id) != null) return error.DuplicateInput;
        if (self.input_count == max_tracked_inputs) return error.TooManyInputs;
    }

    fn inputTracker(self: *Bridge, event_id: u64) Error!*InputState {
        const index = self.findInput(event_id) orelse return error.UnknownInput;
        return &self.input_states[index];
    }

    pub fn deliverInput(
        self: *Bridge,
        event: runtime_host.InputEvent,
    ) Error!runtime_host.InputAck {
        switch (self.state) {
            .frame_registered, .capturing, .captured => {},
            else => return error.InvalidState,
        }
        try self.checkInputCapacity(event.event_id);
        var delivered = event;
        delivered.frame_id = self.frame.id;
        try runtime_host.validateInputEvent(&delivered);

        const group = self.table.input orelse return error.InvalidRuntimeHost;
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.deliver_event orelse return error.InvalidRuntimeHost;
        var ack: runtime_host.InputAck = .{};
        try runtime_host.ensureOk(callback(context, &delivered, &ack));
        if (ack.event_id != delivered.event_id) return error.InvalidState;

        if (ack.accepted and ack.status == .ok) {
            self.input_ids[self.input_count] = delivered.event_id;
            self.input_states[self.input_count] = .{ .accepted = true };
            self.input_count += 1;
        }
        return ack;
    }

    pub fn deliverResult(
        self: *Bridge,
        result: runtime_host.InputResult,
    ) Error!void {
        switch (self.state) {
            .frame_registered, .capturing, .captured => {},
            else => return error.InvalidState,
        }
        try runtime_host.validateInputResult(&result);
        const tracker = try self.inputTracker(result.event_id);
        if (!tracker.accepted or tracker.cancelled or tracker.result_reported) return error.InvalidState;

        const group = self.table.input orelse return error.InvalidRuntimeHost;
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.deliver_result orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &result));
        tracker.result_reported = true;
    }

    pub fn deliverCompletion(
        self: *Bridge,
        completion: runtime_host.CompletionStatus,
    ) Error!void {
        switch (self.state) {
            .frame_registered, .capturing, .captured => {},
            else => return error.InvalidState,
        }
        try runtime_host.validateCompletion(&completion);
        const tracker = try self.inputTracker(completion.transaction_id);
        if (!tracker.accepted or tracker.cancelled or
            !tracker.result_reported or tracker.completed)
            return error.InvalidState;

        const group = self.table.input orelse return error.InvalidRuntimeHost;
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.deliver_completion_status orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &completion));
        tracker.completed = true;
    }

    pub fn inputSnapshot(self: *const Bridge, event_id: u64) ?InputState {
        const index = self.findInput(event_id) orelse return null;
        return self.input_states[index];
    }

    fn requireActiveSession(self: *const Bridge) Error!void {
        switch (self.state) {
            .terminal_active, .frame_registered, .capturing, .captured => {},
            else => return error.InvalidState,
        }
    }

    fn lifecycleGroup(self: *const Bridge) Error!*const runtime_host.LifecycleGroupV1 {
        return self.table.lifecycle orelse error.InvalidRuntimeHost;
    }

    pub fn heartbeat(self: *Bridge) Error!runtime_host.HeartbeatResult {
        try self.requireActiveSession();
        const group = try self.lifecycleGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.heartbeat orelse return error.InvalidRuntimeHost;
        var result: runtime_host.HeartbeatResult = .{};
        try runtime_host.ensureOk(callback(context, &result));
        if (!result.healthy) return error.HostCallbackFailed;
        self.lifecycle.heartbeats += 1;
        return result;
    }

    pub fn flush(self: *Bridge) Error!void {
        try self.requireActiveSession();
        const group = try self.lifecycleGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.flush orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context));
        self.lifecycle.flushes += 1;
    }

    pub fn diagnostic(
        self: *Bridge,
        record: runtime_host.DiagnosticRecord,
    ) Error!void {
        try self.requireActiveSession();
        try runtime_host.validateDiagnostic(&record);
        const group = try self.lifecycleGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.diagnostic orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context, &record));
        self.lifecycle.diagnostics += 1;
    }

    pub fn pendingInputCount(self: *const Bridge) usize {
        var pending: usize = 0;
        for (self.input_states[0..self.input_count]) |state| {
            if (state.accepted and !state.cancelled and !state.completed) pending += 1;
        }
        return pending;
    }

    pub fn cancelAllPendingWork(self: *Bridge) Error!void {
        try self.requireActiveSession();
        const group = try self.lifecycleGroup();
        const context = group.context orelse return error.InvalidRuntimeHost;
        const callback = group.cancel_all_pending_work orelse return error.InvalidRuntimeHost;
        try runtime_host.ensureOk(callback(context));
        for (self.input_states[0..self.input_count]) |*state| {
            if (state.accepted and !state.cancelled and !state.completed)
                state.cancelled = true;
        }
        self.lifecycle.cancellations += 1;
    }

    pub fn lifecycleSnapshot(self: *const Bridge) LifecycleCounters {
        return self.lifecycle;
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
    const geometry = try bridge.refreshFrameGeometry();
    try std.testing.expectEqual(@as(i32, 800), geometry.width);
    try std.testing.expectEqual(@as(i32, 600), geometry.height);
    const initial_state = try bridge.refreshFrameState();
    try std.testing.expect(initial_state.visibility_changed);
    try std.testing.expect(initial_state.focus_changed);
    const unchanged_state = try bridge.refreshFrameState();
    try std.testing.expect(!unchanged_state.visibility_changed);
    try std.testing.expect(!unchanged_state.focus_changed);
    try bridge.beginCapture(8);

    const face_bytes = try protocol.encodeFaceDefineBytes(.{
        .face_id = 7,
        .generation = 2,
        .presence = .{ .foreground = true, .background = true },
        .foreground = .{ 0xff, 0xd5, 0x4d, 255 },
        .background = .{ 0x20, 0x28, 0x38, 255 },
    });
    try bridge.observeFace(.{ .bytes = face_bytes });

    try bridge.observeWindow(.{ .id = 10, .generation = 8, .width = 80, .height = 60 });
    try bridge.observeRow(.{ .window_id = 10, .row_index = 0, .width = 80, .height = 10, .ascent = 7, .descent = 3, .baseline = 7, .visible_height = 10 });
    var run_text = [_]u8{0} ** 120;
    @memcpy(run_text[0..5], "Emacs");
    try bridge.observeRun(.{ .run_id = 1, .window_id = 10, .row_index = 0, .face_id = 7, .face_generation = 2, .x = 2, .y = 0, .width = 40, .height = 10, .text_length = 5, .text = run_text });
    try bridge.observeCursor(.{ .window_id = 10, .x = 0, .y = 0, .width = 2, .height = 8, .visible = true, .active = true });
    try bridge.observeDamage(.{ .width = 800, .height = 600 });
    try std.testing.expectEqual(Counts{ .windows = 1, .rows = 1, .runs = 1, .faces = 1, .cursors = 1, .damage = 1 }, bridge.snapshotCounts());
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
    try bridge.acceptFrameUpdate(2);

    var captured_face: std.ArrayList(u8) = .empty;
    defer captured_face.deinit(gpa);
    try bridge.encodeFaceDefine(gpa, 0, 3, 9, 3, &captured_face);
    try scene.apply(captured_face.items);
    try std.testing.expect(scene.faces.lookup(7) != null);

    var captured_run: std.ArrayList(u8) = .empty;
    defer captured_run.deinit(gpa);
    try bridge.encodeRun(gpa, 0, 4, 9, 4, &captured_run);
    try scene.apply(captured_run.items);
    try std.testing.expectEqual(@as(usize, 1), scene.glyph_runs.items.len);

    try std.testing.expectEqual(@as(usize, 1), scene.windows.items.len);
    try std.testing.expectEqual(@as(usize, 1), scene.rows.items.len);
    try std.testing.expect(scene.cursor != null);

    try bridge.setRenderHint(.{
        .mode = .adaptive_vsync,
        .workload = .typing,
        .damage_only_allowed = true,
        .refresh_interval_ns = 16_666_667,
        .deadline_ns = 2,
    });
    var visibility: std.ArrayList(u8) = .empty;
    defer visibility.deinit(gpa);
    try bridge.encodeFlush(gpa, 5, 9, 3, &visibility);
    try scene.apply(visibility.items);
    try std.testing.expect(scene.flush != null);
    try std.testing.expectEqual(@as(u64, 2), scene.flush.?.frame_sequence);
    try std.testing.expectEqual(protocol.FrameFlushDamageKind.full, scene.flush.?.damage_kind);

    var duplicate_flush: std.ArrayList(u8) = .empty;
    defer duplicate_flush.deinit(gpa);
    try std.testing.expectError(error.InvalidState, bridge.encodeFlush(gpa, 3, 9, 3, &duplicate_flush));

    var hint: std.ArrayList(u8) = .empty;
    defer hint.deinit(gpa);
    try bridge.encodeRenderHint(gpa, 6, 9, 4, &hint);
    try scene.apply(hint.items);
    try std.testing.expectEqual(protocol.RenderHintMode.adaptive_vsync, scene.render_hint.?.preferred_mode);

    var visibility_next: std.ArrayList(u8) = .empty;
    defer visibility_next.deinit(gpa);
    try bridge.encodeFrameVisibility(gpa, 7, 9, 5, &visibility_next);
    try scene.apply(visibility_next.items);

    var focus: std.ArrayList(u8) = .empty;
    defer focus.deinit(gpa);
    try bridge.encodeFrameFocus(gpa, 8, 9, 6, &focus);
    try scene.apply(focus.items);
    try std.testing.expectEqual(
        protocol.FrameVisibilityState.visible,
        scene.frames.lookup(100).?.visibility,
    );
    try std.testing.expect(scene.frames.lookup(100).?.focused);

    try bridge.destroy();
    var destroy: std.ArrayList(u8) = .empty;
    defer destroy.deinit(gpa);
    try bridge.encodeFrameDestroy(gpa, 9, 9, 8, &destroy);
    try scene.apply(destroy.items);
    try std.testing.expectEqual(State.destroyed, bridge.state);
    try std.testing.expectEqual(@as(usize, 0), scene.windows.items.len);
}

test "hidden focused host state is rejected without cache mutation" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);
    try bridge.createTerminal(.{ .requested_generation = 1 });
    try bridge.registerFrame(.{ .id = 22, .generation = 1 });

    host.frame_visibility = .hidden;
    host.frame_focused = true;
    try std.testing.expectError(error.InvalidFrameIdentity, bridge.refreshFrameState());
    try std.testing.expect(bridge.frame_state == null);
}

test "runtime bridge rejects invalid duplicate face captures" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);
    try bridge.createTerminal(.{ .requested_generation = 1 });
    try bridge.activateTerminal();
    try bridge.registerFrame(.{ .id = 22, .generation = 1 });
    _ = try bridge.refreshFrameGeometry();
    try bridge.beginCapture(1);

    try std.testing.expectError(error.InvalidRuntimeHost, bridge.observeFace(.{}));

    const bytes = try protocol.encodeFaceDefineBytes(.{ .face_id = 7, .generation = 1 });
    try bridge.observeFace(.{ .bytes = bytes });
    try std.testing.expectError(error.DuplicateFace, bridge.observeFace(.{ .bytes = bytes }));
}

test "runtime bridge validates captured font-backed faces" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);
    try bridge.createTerminal(.{ .requested_generation = 1 });
    try bridge.activateTerminal();
    try bridge.registerFrame(.{ .id = 22, .generation = 1 });
    _ = try bridge.refreshFrameGeometry();
    try bridge.beginCapture(1);

    var family: [64]u8 = @splat(0);
    @memcpy(family[0..7], "Adaptor");
    var foundry: [32]u8 = @splat(0);
    @memcpy(foundry[0..4], "Test");
    var style: [32]u8 = @splat(0);
    @memcpy(style[0..4], "Mono");
    const font_bytes = try protocol.encodeFontDefineBytes(.{
        .font_id = 8,
        .generation = 1,
        .family = family,
        .family_len = "Adaptor".len,
        .foundry = foundry,
        .foundry_len = "Test".len,
        .style = style,
        .style_len = "Mono".len,
        .pixel_size = 16,
        .x_dpi = 96,
        .y_dpi = 96,
        .ascent = 10,
        .descent = 3,
        .line_height = 13,
        .average_advance = 8,
        .space_advance = 8,
        .max_advance = 8,
        .min_advance = 8,
        .fixed_pitch = true,
        .spacing = .mono,
    });
    try bridge.observeFont(.{ .bytes = font_bytes });
    try std.testing.expectError(error.DuplicateFont, bridge.observeFont(.{ .bytes = font_bytes }));

    const stale_face = try protocol.encodeFaceDefineBytes(.{
        .face_id = 7,
        .generation = 1,
        .presence = .{ .font = true },
        .font_id = 8,
        .font_generation = 2,
    });
    try std.testing.expectError(error.InvalidState, bridge.observeFace(.{ .bytes = stale_face }));

    const face = try protocol.encodeFaceDefineBytes(.{
        .face_id = 7,
        .generation = 1,
        .presence = .{ .font = true },
        .font_id = 8,
        .font_generation = 1,
    });
    try bridge.observeFace(.{ .bytes = face });
    try std.testing.expectEqual(@as(usize, 1), bridge.counts.fonts);
    try std.testing.expectEqual(@as(usize, 1), bridge.counts.faces);
}

test "runtime bridge captures and validates bounded image fragments" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);
    try bridge.createTerminal(.{ .requested_generation = 1 });
    try bridge.activateTerminal();
    try bridge.registerFrame(.{ .id = 22, .generation = 1 });
    _ = try bridge.refreshFrameGeometry();
    try bridge.beginCapture(1);

    const metadata_bytes = try protocol.encodeImageDefineBytes(.{
        .image_id = 31,
        .generation = 1,
        .width = 4,
        .height = 4,
        .total_byte_count = 64,
        .cache_policy = .pinned,
    });
    try bridge.observeImageDefine(.{ .bytes = metadata_bytes });
    try std.testing.expectError(error.DuplicateImage, bridge.observeImageDefine(.{ .bytes = metadata_bytes }));

    var fragment: runtime_host.ImageFragmentRecord = .{
        .image_id = 31,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 1,
        .byte_length = 64,
    };
    for (fragment.bytes[0..64], 0..) |*byte, index| byte.* = @truncate(index * 7 + 9);
    try bridge.observeImageFragment(fragment);
    try std.testing.expect(bridge.images[0].complete);

    const observations_before = host.observations;
    const counts_before = bridge.snapshotCounts();
    try std.testing.expectError(error.InvalidState, bridge.observeImageFragment(fragment));
    try std.testing.expectEqual(observations_before, host.observations);
    try std.testing.expectEqual(counts_before, bridge.snapshotCounts());

    const oversized = try protocol.encodeImageDefineBytes(.{
        .image_id = 32,
        .generation = 1,
        .width = 33,
        .height = 33,
        .total_byte_count = 4356,
    });
    try std.testing.expectError(error.TooManyImageBytes, bridge.observeImageDefine(.{ .bytes = oversized }));
}

test "runtime bridge rejects stale run face before host observation" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);
    try bridge.createTerminal(.{ .requested_generation = 1 });
    try bridge.activateTerminal();
    try bridge.registerFrame(.{ .id = 22, .generation = 1 });
    _ = try bridge.refreshFrameGeometry();
    try bridge.beginCapture(1);
    try bridge.observeWindow(.{ .id = 10, .generation = 1, .width = 20, .height = 10 });
    try bridge.observeRow(.{ .window_id = 10, .row_index = 0, .width = 20, .height = 4, .ascent = 3, .descent = 1, .baseline = 3, .visible_height = 4 });

    const bytes = try protocol.encodeFaceDefineBytes(.{ .face_id = 7, .generation = 1 });
    try bridge.observeFace(.{ .bytes = bytes });
    const observations_before = host.observations;
    const counts_before = bridge.snapshotCounts();

    var run_text = [_]u8{0} ** 120;
    @memcpy(run_text[0..5], "Emacs");
    try std.testing.expectError(error.InvalidState, bridge.observeRun(.{
        .run_id = 1,
        .window_id = 10,
        .row_index = 0,
        .face_id = 7,
        .face_generation = 2,
        .width = 10,
        .height = 4,
        .text_length = 5,
        .text = run_text,
    }));
    try std.testing.expectEqual(observations_before, host.observations);
    try std.testing.expectEqual(counts_before, bridge.snapshotCounts());
}

test "bridge rejects ok callbacks that return invalid identities" {
    var invalid_create_host: runtime_host.FakeHost = undefined;
    const invalid_create_table = runtime_host.fakeTable(&invalid_create_host);
    invalid_create_host.terminal_group.create_terminal = invalidIdentityTerminalCreate;
    var bridge = try Bridge.init(invalid_create_table);

    try std.testing.expectError(error.InvalidRuntimeHost, bridge.createTerminal(.{ .requested_generation = 1 }));
    try std.testing.expectEqual(State.idle, bridge.state);
    try std.testing.expect(!bridge.terminal.valid());

    var capture_host: runtime_host.FakeHost = undefined;
    const capture_table = runtime_host.fakeTable(&capture_host);
    var active_bridge = try Bridge.init(capture_table);
    try active_bridge.createTerminal(.{ .requested_generation = 1 });
    try active_bridge.activateTerminal();
    try active_bridge.registerFrame(.{ .id = 22, .generation = 8 });
    capture_host.redisplay_group.begin_capture = invalidIdentityCaptureBegin;
    try std.testing.expectError(error.InvalidRuntimeHost, active_bridge.beginCapture(8));
    try std.testing.expectEqual(State.frame_registered, active_bridge.state);
    try std.testing.expectEqual(@as(u64, 0), active_bridge.redisplay_generation);
    try std.testing.expect(!active_bridge.capture.valid());
}

test "bridge rejects cursor sets without exactly one active cursor" {
    inline for (.{ 1, 2 }) |cursor_count| {
        var host: runtime_host.FakeHost = undefined;
        const table = runtime_host.fakeTable(&host);
        var bridge = try Bridge.init(table);
        try bridge.createTerminal(.{ .requested_generation = 1 });
        try bridge.activateTerminal();
        try bridge.registerFrame(.{ .id = 22, .generation = 8 });
        _ = try bridge.refreshFrameGeometry();
        try bridge.beginCapture(8);
        inline for (.{ 10, 11 }) |window_id| {
            try bridge.observeWindow(.{ .id = window_id, .generation = 8, .width = 80, .height = 60 });
            try bridge.observeRow(.{ .window_id = window_id, .row_index = 0, .width = 80, .height = 10, .ascent = 7, .descent = 3, .baseline = 7, .visible_height = 10 });
        }
        try bridge.observeDamage(.{ .width = 800, .height = 600 });
        inline for (0..cursor_count) |index| {
            try bridge.observeCursor(.{
                .window_id = 10 + index,
                .x = @intCast(index * 2),
                .y = 0,
                .width = 2,
                .height = 10,
                .visible = true,
                .active = cursor_count == 2,
            });
        }
        try std.testing.expectEqual(cursor_count, bridge.snapshotCounts().cursors);
        try std.testing.expectError(error.InvalidState, bridge.commitCapture());
        try bridge.destroy();
    }
}

test "bridge advances bounded redisplay capture generations" {
    const gpa = std.testing.allocator;
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);

    try bridge.createTerminal(.{ .requested_generation = 1 });
    try bridge.activateTerminal();
    try bridge.registerFrame(.{ .id = 22, .generation = 8 });
    _ = try bridge.refreshFrameGeometry();
    try bridge.beginCapture(8);
    try bridge.observeWindow(.{ .id = 10, .generation = 8, .width = 80, .height = 60 });
    try bridge.observeRow(.{ .window_id = 10, .row_index = 0, .width = 80, .height = 10, .ascent = 7, .descent = 3, .baseline = 7, .visible_height = 10 });
    try bridge.observeDamage(.{ .width = 800, .height = 600 });
    try bridge.commitCapture();

    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    try bridge.encodeFrameUpdate(gpa, 1, 9, 2, &first);
    try std.testing.expectError(error.InvalidState, bridge.encodeFlush(gpa, 2, 9, 2, &first));
    try bridge.acceptFrameUpdate(1);
    try bridge.encodeFlush(gpa, 2, 9, 2, &first);
    try std.testing.expectEqual(@as(u64, 1), bridge.last_emitted_flush_frame_sequence);

    try bridge.setRenderHint(.{
        .mode = .adaptive_vsync,
        .workload = .typing,
        .damage_only_allowed = true,
        .refresh_interval_ns = 16_666_667,
        .deadline_ns = 2,
    });

    try std.testing.expectError(error.InvalidFrameIdentity, bridge.beginCapture(8));
    host.force_failure = true;
    try std.testing.expectError(error.HostCallbackFailed, bridge.beginCapture(9));
    try std.testing.expectEqual(State.captured, bridge.state);
    try std.testing.expectEqual(@as(u64, 8), bridge.redisplay_generation);
    try std.testing.expectEqual(@as(u64, 1), bridge.last_encoded_frame_sequence);
    try std.testing.expectEqual(@as(u64, 1), bridge.last_accepted_frame_sequence);
    try std.testing.expectEqual(@as(u64, 1), bridge.last_emitted_flush_frame_sequence);
    try std.testing.expect(bridge.render_hint != null);
    host.force_failure = false;
    try bridge.beginCapture(9);
    try std.testing.expectEqual(State.capturing, bridge.state);
    try std.testing.expectEqual(Counts{}, bridge.snapshotCounts());
    try std.testing.expectEqual(@as(u64, 0), bridge.last_encoded_frame_sequence);
    try std.testing.expectEqual(@as(u64, 0), bridge.last_accepted_frame_sequence);
    try std.testing.expectEqual(@as(u64, 0), bridge.last_emitted_flush_frame_sequence);
    try std.testing.expect(bridge.render_hint != null);
    try std.testing.expectEqual(@as(u64, 9), bridge.redisplay_generation);

    try bridge.observeWindow(.{ .id = 10, .generation = 8, .width = 80, .height = 60 });
    try bridge.observeRow(.{ .window_id = 10, .row_index = 0, .width = 80, .height = 10, .ascent = 7, .descent = 3, .baseline = 7, .visible_height = 10 });
    try bridge.observeDamage(.{ .width = 800, .height = 600 });
    try bridge.commitCapture();

    var next: std.ArrayList(u8) = .empty;
    defer next.deinit(gpa);
    try bridge.encodeFrameUpdate(gpa, 3, 9, 3, &next);
    const payload = try protocol.decodeEnvelope(next.items);
    var update = try protocol.decodeFrameUpdate(gpa, payload.bytes);
    defer protocol.freeFrameUpdate(gpa, &update);
    try std.testing.expectEqual(@as(u64, 9), update.header.redisplay_generation);
    try std.testing.expectEqual(@as(u64, 3), update.header.sequence);
    try bridge.acceptFrameUpdate(3);

    var flushed: std.ArrayList(u8) = .empty;
    defer flushed.deinit(gpa);
    try bridge.encodeFlush(gpa, 4, 9, 3, &flushed);
    const flush_payload = try protocol.decodeEnvelope(flushed.items);
    const flush = try protocol.decodeFrameFlush(flush_payload.bytes);
    try std.testing.expectEqual(@as(u64, 9), flush.redisplay_generation);
    try std.testing.expectEqual(@as(u64, 3), flush.frame_sequence);
}

test "bridge delivers key and text intents with ordered lifecycle" {
    const gpa = std.testing.allocator;
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);

    try bridge.createTerminal(.{ .requested_generation = 1 });
    try bridge.registerFrame(.{ .id = 22, .generation = 1 });

    const key = runtime_host.InputEvent{
        .event_id = 11,
        .kind = input_kind_key,
        .code = 4,
        .modifiers = 2,
    };
    const key_ack = try bridge.deliverInput(key);
    try std.testing.expect(key_ack.accepted);
    try bridge.deliverResult(.{ .event_id = key.event_id, .command_status = @intFromEnum(runtime_host.CommandStatus.ok) });
    try bridge.deliverCompletion(.{ .transaction_id = key.event_id, .status = .ok, .completed = true });

    var text = runtime_host.InputEvent{
        .event_id = 12,
        .kind = input_kind_text,
        .payload_length = 5,
    };
    @memcpy(text.payload[0..5], "Emacs");
    const text_ack = try bridge.deliverInput(text);
    try std.testing.expect(text_ack.accepted);
    try bridge.deliverResult(.{ .event_id = text.event_id, .command_status = @intFromEnum(runtime_host.CommandStatus.ok) });
    try bridge.deliverCompletion(.{ .transaction_id = text.event_id, .status = .ok, .completed = true });

    try std.testing.expectEqual(
        InputState{ .accepted = true, .result_reported = true, .completed = true },
        bridge.inputSnapshot(11).?,
    );
    try std.testing.expectEqual(
        InputState{ .accepted = true, .result_reported = true, .completed = true },
        bridge.inputSnapshot(12).?,
    );
    _ = gpa;
}

test "bridge rejects duplicate input and completion before result" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);
    try bridge.createTerminal(.{ .requested_generation = 1 });
    try bridge.registerFrame(.{ .id = 22, .generation = 1 });

    const event: runtime_host.InputEvent = .{ .event_id = 20, .kind = input_kind_key };
    _ = try bridge.deliverInput(event);
    try std.testing.expectError(error.DuplicateInput, bridge.deliverInput(event));
    try std.testing.expectError(error.InvalidState, bridge.deliverCompletion(.{ .transaction_id = event.event_id, .completed = true }));
}

test "bridge lifecycle operations and cancellation track bounded input state" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);
    try bridge.createTerminal(.{ .requested_generation = 1 });
    try bridge.registerFrame(.{ .id = 22, .generation = 1 });

    const heartbeat = try bridge.heartbeat();
    try std.testing.expect(heartbeat.healthy);
    try bridge.flush();
    var diagnostic: runtime_host.DiagnosticRecord = .{ .code = 7 };
    diagnostic.message_length = 5;
    @memcpy(diagnostic.message[0..5], "ready");
    try bridge.diagnostic(diagnostic);

    const event: runtime_host.InputEvent = .{
        .event_id = 30,
        .kind = input_kind_key,
        .code = 4,
    };
    _ = try bridge.deliverInput(event);
    try std.testing.expectEqual(@as(usize, 1), bridge.pendingInputCount());
    try bridge.cancelAllPendingWork();
    try std.testing.expectEqual(@as(usize, 0), bridge.pendingInputCount());
    try std.testing.expectError(error.InvalidState, bridge.deliverResult(.{
        .event_id = event.event_id,
        .command_status = @intFromEnum(runtime_host.CommandStatus.ok),
    }));
    try std.testing.expectError(error.InvalidState, bridge.deliverCompletion(.{
        .transaction_id = event.event_id,
        .completed = true,
    }));

    const counts = bridge.lifecycleSnapshot();
    try std.testing.expectEqual(@as(usize, 1), counts.heartbeats);
    try std.testing.expectEqual(@as(usize, 1), counts.flushes);
    try std.testing.expectEqual(@as(usize, 1), counts.diagnostics);
    try std.testing.expectEqual(@as(usize, 1), counts.cancellations);
}

test "bridge rejects observations outside capturing state without mutation" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);

    try std.testing.expectError(error.InvalidState, bridge.observeWindow(.{ .id = 1, .generation = 1 }));
    try std.testing.expectEqual(State.idle, bridge.state);
    try std.testing.expectEqual(Counts{}, bridge.snapshotCounts());
}

test "runtime bridge validates shaped run capture against face and font" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);
    try bridge.createTerminal(.{ .requested_generation = 1 });
    try bridge.activateTerminal();
    try bridge.registerFrame(.{ .id = 22, .generation = 1 });
    _ = try bridge.refreshFrameGeometry();
    try bridge.beginCapture(1);
    try bridge.observeWindow(.{ .id = 10, .generation = 1, .width = 40, .height = 10 });
    try bridge.observeRow(.{ .window_id = 10, .row_index = 0, .width = 40, .height = 10, .ascent = 8, .descent = 2, .baseline = 8, .visible_height = 10 });

    var family: [64]u8 = @splat(0);
    @memcpy(family[0..7], "Adaptor");
    var foundry: [32]u8 = @splat(0);
    @memcpy(foundry[0..4], "Test");
    var style: [32]u8 = @splat(0);
    @memcpy(style[0..4], "Mono");
    const font_bytes = try protocol.encodeFontDefineBytes(.{
        .font_id = 8,
        .generation = 1,
        .family = family,
        .family_len = "Adaptor".len,
        .foundry = foundry,
        .foundry_len = "Test".len,
        .style = style,
        .style_len = "Mono".len,
        .fixed_pitch = true,
        .spacing = .mono,
    });
    try bridge.observeFont(.{ .bytes = font_bytes });

    const face_bytes = try protocol.encodeFaceDefineBytes(.{
        .face_id = 7,
        .generation = 1,
        .presence = .{ .font = true },
        .font_id = 8,
        .font_generation = 1,
    });
    try bridge.observeFace(.{ .bytes = face_bytes });

    var shaped: runtime_host.ShapedRunRecord = .{
        .run_id = 21,
        .window_id = 10,
        .row_index = 0,
        .face_id = 7,
        .face_generation = 1,
        .font_id = 8,
        .glyph_count = 1,
        .width = 6,
        .height = 8,
    };
    shaped.glyphs[0] = .{ .glyph_id = 101, .cluster = 0, .advance_x = 6 };
    try bridge.observeShapedRun(shaped);
    try std.testing.expectEqual(@as(usize, 1), bridge.counts.shaped_runs);
    try std.testing.expectError(error.DuplicateShapedRun, bridge.observeShapedRun(shaped));
}

test "shaped run capture enforces collisions atomicity and reset" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try Bridge.init(table);
    try bridge.createTerminal(.{ .requested_generation = 1 });
    try bridge.activateTerminal();
    try bridge.registerFrame(.{ .id = 22, .generation = 1 });
    _ = try bridge.refreshFrameGeometry();
    try bridge.beginCapture(1);
    try bridge.observeWindow(.{ .id = 10, .generation = 1, .width = 40, .height = 10 });
    try bridge.observeRow(.{ .window_id = 10, .row_index = 0, .width = 40, .height = 10, .ascent = 8, .descent = 2, .baseline = 8, .visible_height = 10 });

    var family: [64]u8 = @splat(0);
    @memcpy(family[0..7], "Adaptor");
    var foundry: [32]u8 = @splat(0);
    @memcpy(foundry[0..4], "Test");
    var style: [32]u8 = @splat(0);
    @memcpy(style[0..4], "Mono");
    const font_bytes = try protocol.encodeFontDefineBytes(.{
        .font_id = 8,
        .generation = 1,
        .family = family,
        .family_len = "Adaptor".len,
        .foundry = foundry,
        .foundry_len = "Test".len,
        .style = style,
        .style_len = "Mono".len,
        .fixed_pitch = true,
        .spacing = .mono,
    });
    try bridge.observeFont(.{ .bytes = font_bytes });
    const face_bytes = try protocol.encodeFaceDefineBytes(.{
        .face_id = 7,
        .generation = 1,
        .presence = .{ .font = true },
        .font_id = 8,
        .font_generation = 1,
    });
    try bridge.observeFace(.{ .bytes = face_bytes });

    var regular: runtime_host.RunRecord = .{ .run_id = 1, .window_id = 10, .row_index = 0, .width = 6, .height = 8, .text_length = 1 };
    regular.text[0] = 'A';
    try bridge.observeRun(regular);
    var shaped: runtime_host.ShapedRunRecord = .{ .run_id = 1, .window_id = 10, .row_index = 0, .face_id = 7, .face_generation = 1, .font_id = 8, .glyph_count = 1, .width = 6, .height = 8 };
    shaped.glyphs[0] = .{ .glyph_id = 101, .cluster = 0, .advance_x = 6 };
    try std.testing.expectError(error.DuplicateShapedRun, bridge.observeShapedRun(shaped));

    shaped.run_id = 2;
    try bridge.observeShapedRun(shaped);
    regular.run_id = 2;
    try std.testing.expectError(error.DuplicateRun, bridge.observeRun(regular));

    const counts_before = bridge.snapshotCounts();
    host.redisplay_group.observe_shaped_run = failingShapedRun;
    shaped.run_id = 3;
    try std.testing.expectError(error.HostCallbackFailed, bridge.observeShapedRun(shaped));
    try std.testing.expectEqual(counts_before, bridge.snapshotCounts());
    host.redisplay_group.observe_shaped_run = runtime_host.FakeHost.observeShapedRun;
    try bridge.observeShapedRun(shaped);
    try bridge.commitCapture();

    var encoded: std.ArrayList(u8) = .empty;
    defer encoded.deinit(std.testing.allocator);
    try bridge.encodeShapedRun(std.testing.allocator, 1, 9, 9, 9, &encoded);
    const decoded_envelope = try protocol.decodeEnvelope(encoded.items);
    const decoded_wire = try frontend.decodeGlyphRun(decoded_envelope.bytes);
    try std.testing.expectEqual(@as(u16, 3), decoded_wire.schema);
    try std.testing.expectEqual(@as(u32, 8), decoded_wire.font_id);
    try std.testing.expectEqual(@as(usize, 1), decoded_wire.glyph_count);
    try std.testing.expectEqual(@as(u32, 101), decoded_wire.glyphs[0].glyph_id);

    try bridge.beginCapture(2);
    try std.testing.expectEqual(@as(usize, 0), bridge.counts.shaped_runs);
}
