//! Adapter-owned full-runtime host ABI for the future pure SDL3 backend.
//!
//! This file defines the versioned contract that an R7-approved Emacs host
//! adapter would implement.  It is deliberately only an ABI contract and fake
//! conformance fixture: it does not register a terminal, enable output_proto,
//! initialize PGTK, or modify inherited GNU Emacs code.

const std = @import("std");
pub const adapter = @import("adapter.zig");
pub const protocol = @import("protocol.zig");

pub const abi_version: u32 = 1;
pub const authoritative_source = "src/proto-ui/runtime_host.zig";
pub const reason_code = "host_registration_contract_missing";

pub const Status = enum(u8) {
    ok = 0,
    invalid = 1,
    unsupported = 2,
    not_found = 3,
    busy = 4,
    generation_mismatch = 5,
    failed = 6,

    pub fn valid(self: Status) bool {
        return switch (self) {
            .ok, .invalid, .unsupported, .not_found, .busy, .generation_mismatch, .failed => true,
        };
    }
};

pub const Error = error{
    InvalidRuntimeHost,
    HostCallbackFailed,
};

pub const Identity = extern struct {
    id: u64 = 0,
    generation: u64 = 0,

    pub fn valid(self: Identity) bool {
        return self.id != 0 and self.generation != 0;
    }
};

pub const TerminalCreateRequest = extern struct {
    requested_generation: u64 = 1,
    kind: u8 = @intFromEnum(TerminalKind.output_proto),
    reserved: [7]u8 = [_]u8{0} ** 7,
};

pub const TerminalKind = enum(u8) { output_proto = 1 };

pub const CaptureRequest = extern struct {
    frame: Identity = .{},
    redisplay_generation: u64 = 0,
    flags: u32 = 0,
    reserved: u32 = 0,
};

pub const WindowRecord = extern struct {
    id: u64 = 0,
    generation: u64 = 0,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    flags: u32 = 0,
    reserved: u32 = 0,

    pub fn id_valid(self: WindowRecord) bool {
        return self.id != 0 and self.generation != 0;
    }
};

pub const RowRecord = extern struct {
    window_id: u64 = 0,
    row_index: u32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    ascent: i32 = 0,
    descent: i32 = 0,
    baseline: i32 = 0,
    visible_height: i32 = 0,
    flags: u32 = 0,
    reserved: u32 = 0,
};

pub const RunRecord = extern struct {
    run_id: u64 = 0,
    window_id: u64 = 0,
    row_index: u32 = 0,
    face_id: u32 = 0,
    face_generation: u32 = 0,
    font_id: u32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    direction: u8 = 1,
    kind: u8 = @intFromEnum(RunKind.text),
    text_length: u16 = 0,
    reserved: u32 = 0,
    text: [120]u8 = [_]u8{0} ** 120,
};

pub const RunKind = enum(u8) { text = 1, glyphless = 2, composition = 3, image = 4, stretch = 5, rectangle = 6 };

pub const ShapedGlyphRecord = extern struct {
    glyph_id: u32 = 0,
    cluster: u32 = 0,
    x_offset: i16 = 0,
    y_offset: i16 = 0,
    advance_x: u16 = 0,
    advance_y: u16 = 0,
};

pub const max_shaped_run_glyphs: usize = 7;

pub const ShapedRunRecord = extern struct {
    run_id: u64 = 0,
    window_id: u64 = 0,
    row_index: u32 = 0,
    face_id: u32 = 0,
    face_generation: u32 = 0,
    font_id: u32 = 0,
    glyph_count: u32 = 0,
    direction: u16 = 1,
    flags: u16 = 0,
    reserved: u32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    glyphs: [max_shaped_run_glyphs]ShapedGlyphRecord = undefined,
};

pub const CursorRecord = extern struct {
    window_id: u64 = 0,
    row_index: u32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    kind: u8 = 0,
    visible: bool = false,
    active: bool = false,
    reserved: [5]u8 = [_]u8{0} ** 5,
};

pub const DamageRecord = extern struct {
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    reason: u8 = 0,
    reserved: [3]u8 = [_]u8{0} ** 3,
};

/// Fixed EUP FACE_DEFINE wire form carried verbatim from the host capture.
pub const FaceRecord = extern struct {
    bytes: [96]u8 = [_]u8{0} ** 96,
};

/// Fixed EUP FONT_DEFINE wire form carried verbatim from the host capture.
pub const FontRecord = extern struct {
    bytes: [224]u8 = [_]u8{0} ** 224,
};

/// Exact EUP IMAGE_DEFINE wire form carried from the host capture.
pub const ImageDefineRecord = extern struct {
    bytes: [72]u8 = [_]u8{0} ** 72,
};

/// Bounded IMAGE_DATA fragment.  The redisplay seam accepts at most 1024
/// bytes per fragment and four fragments per image; wire bytes remain exact.
pub const ImageFragmentRecord = extern struct {
    image_id: u32 = 0,
    generation: u32 = 0,
    fragment_index: u16 = 0,
    fragment_count: u16 = 0,
    byte_length: u32 = 0,
    reserved: u32 = 0,
    bytes: [1024]u8 = [_]u8{0} ** 1024,
};

pub const InputEvent = extern struct {
    pub const payload_bytes: usize = 64;

    event_id: u64 = 0,
    frame_id: u64 = 0,
    kind: u16 = 0,
    modifiers: u16 = 0,
    code: u32 = 0,
    repeat: u32 = 0,
    payload_length: u16 = 0,
    reserved: u16 = 0,
    payload: [64]u8 = [_]u8{0} ** 64,
};

pub const InputAck = extern struct {
    event_id: u64 = 0,
    accepted: bool = false,
    status: Status = .ok,
    reserved: [6]u8 = [_]u8{0} ** 6,
};

pub const InputResult = extern struct {
    event_id: u64 = 0,
    command_status: u8 = @intFromEnum(CommandStatus.ok),
    changed_display: bool = false,
    reserved: [6]u8 = [_]u8{0} ** 6,
};

pub const CommandStatus = enum(u8) { ok = 0, unhandled = 1, error_result = 2 };

pub const InputKind = enum(u16) {
    key = 1,
    text = 2,
    pointer_button = 3,
    pointer_motion = 4,
    wheel = 5,
};

pub const CompletionStatus = extern struct {
    transaction_id: u64 = 0,
    status: Status = .ok,
    completed: bool = false,
    reserved: [6]u8 = [_]u8{0} ** 6,
};

pub const HeartbeatResult = extern struct {
    sequence: u64 = 0,
    pending_work: u32 = 0,
    healthy: bool = true,
    reserved: [3]u8 = [_]u8{0} ** 3,
};

pub const DiagnosticRecord = extern struct {
    code: u32 = 0,
    severity: u8 = 0,
    reserved: [3]u8 = [_]u8{0} ** 3,
    message_length: u16 = 0,
    reserved2: [6]u8 = [_]u8{0} ** 6,
    message: [120]u8 = [_]u8{0} ** 120,
};

pub const TerminalCreateFn = *const fn (*anyopaque, *const TerminalCreateRequest, *Identity) callconv(.c) Status;
pub const IdentityOperationFn = *const fn (*anyopaque, *const Identity) callconv(.c) Status;
pub const FrameRegisterFn = *const fn (*anyopaque, *const Identity, *Identity) callconv(.c) Status;
pub const FrameStateFn = *const fn (*anyopaque, *const Identity, *adapter.FrameState) callconv(.c) Status;
pub const FrameGeometryFn = *const fn (*anyopaque, *const Identity, *adapter.Geometry) callconv(.c) Status;
pub const CaptureBeginFn = *const fn (*anyopaque, *const CaptureRequest, *Identity) callconv(.c) Status;
pub const CaptureIdentityFn = *const fn (*anyopaque, *const Identity, *const WindowRecord) callconv(.c) Status;
pub const CaptureRowFn = *const fn (*anyopaque, *const Identity, *const RowRecord) callconv(.c) Status;
pub const CaptureRunFn = *const fn (*anyopaque, *const Identity, *const RunRecord) callconv(.c) Status;
pub const CaptureCursorFn = *const fn (*anyopaque, *const Identity, *const CursorRecord) callconv(.c) Status;
pub const CaptureDamageFn = *const fn (*anyopaque, *const Identity, *const DamageRecord) callconv(.c) Status;
pub const CaptureFaceFn = *const fn (*anyopaque, *const Identity, *const FaceRecord) callconv(.c) Status;
pub const CaptureFontFn = *const fn (*anyopaque, *const Identity, *const FontRecord) callconv(.c) Status;
pub const CaptureShapedRunFn = *const fn (*anyopaque, *const Identity, *const ShapedRunRecord) callconv(.c) Status;
pub const CaptureImageDefineFn = *const fn (*anyopaque, *const Identity, *const ImageDefineRecord) callconv(.c) Status;
pub const CaptureImageFragmentFn = *const fn (*anyopaque, *const Identity, *const ImageFragmentRecord) callconv(.c) Status;
pub const CaptureOperationFn = *const fn (*anyopaque, *const Identity) callconv(.c) Status;
pub const InputDeliverFn = *const fn (*anyopaque, *const InputEvent, *InputAck) callconv(.c) Status;
pub const InputResultFn = *const fn (*anyopaque, *const InputResult) callconv(.c) Status;
pub const CompletionFn = *const fn (*anyopaque, *const CompletionStatus) callconv(.c) Status;
pub const HeartbeatFn = *const fn (*anyopaque, *HeartbeatResult) callconv(.c) Status;
pub const OperationFn = *const fn (*anyopaque) callconv(.c) Status;
pub const DiagnosticFn = *const fn (*anyopaque, *const DiagnosticRecord) callconv(.c) Status;

pub const TerminalGroupV1 = extern struct {
    abi_version: u32 = abi_version,
    size: usize = @sizeOf(TerminalGroupV1),
    context: ?*anyopaque = null,
    create_terminal: ?TerminalCreateFn = null,
    activate_terminal: ?IdentityOperationFn = null,
    delete_terminal: ?IdentityOperationFn = null,
};

pub const FrameGroupV1 = extern struct {
    abi_version: u32 = abi_version,
    size: usize = @sizeOf(FrameGroupV1),
    context: ?*anyopaque = null,
    register_frame: ?FrameRegisterFn = null,
    unregister_frame: ?IdentityOperationFn = null,
    read_frame_state: ?FrameStateFn = null,
    read_geometry: ?FrameGeometryFn = null,
};

pub const RedisplayGroupV1 = extern struct {
    abi_version: u32 = abi_version,
    size: usize = @sizeOf(RedisplayGroupV1),
    context: ?*anyopaque = null,
    begin_capture: ?CaptureBeginFn = null,
    observe_window: ?CaptureIdentityFn = null,
    observe_row: ?CaptureRowFn = null,
    observe_run: ?CaptureRunFn = null,
    observe_cursor: ?CaptureCursorFn = null,
    observe_damage: ?CaptureDamageFn = null,
    observe_face: ?CaptureFaceFn = null,
    observe_font: ?CaptureFontFn = null,
    observe_shaped_run: ?CaptureShapedRunFn = null,
    observe_image_define: ?CaptureImageDefineFn = null,
    observe_image_fragment: ?CaptureImageFragmentFn = null,
    commit_capture: ?CaptureOperationFn = null,
    cancel_capture: ?CaptureOperationFn = null,
};

pub const InputGroupV1 = extern struct {
    abi_version: u32 = abi_version,
    size: usize = @sizeOf(InputGroupV1),
    context: ?*anyopaque = null,
    deliver_event: ?InputDeliverFn = null,
    deliver_result: ?InputResultFn = null,
    deliver_completion_status: ?CompletionFn = null,
};

pub const LifecycleGroupV1 = extern struct {
    abi_version: u32 = abi_version,
    size: usize = @sizeOf(LifecycleGroupV1),
    context: ?*anyopaque = null,
    heartbeat: ?HeartbeatFn = null,
    flush: ?OperationFn = null,
    diagnostic: ?DiagnosticFn = null,
    cancel_all_pending_work: ?OperationFn = null,
};

pub const PureRuntimeHostV1 = extern struct {
    abi_version: u32 = abi_version,
    size: usize = @sizeOf(PureRuntimeHostV1),
    context: ?*anyopaque = null,
    terminal: ?*const TerminalGroupV1 = null,
    frame: ?*const FrameGroupV1 = null,
    redisplay: ?*const RedisplayGroupV1 = null,
    input: ?*const InputGroupV1 = null,
    lifecycle: ?*const LifecycleGroupV1 = null,
};

pub const operation_names = [_][]const u8{
    "terminal.create_terminal",
    "terminal.activate_terminal",
    "terminal.delete_terminal",
    "frame.register_frame",
    "frame.unregister_frame",
    "frame.read_frame_state",
    "frame.read_geometry",
    "redisplay.begin_capture",
    "redisplay.observe_window",
    "redisplay.observe_row",
    "redisplay.observe_run",
    "redisplay.observe_cursor",
    "redisplay.observe_damage",
    "redisplay.observe_face",
    "redisplay.observe_font",
    "redisplay.observe_shaped_run",
    "redisplay.observe_image_define",
    "redisplay.observe_image_fragment",
    "redisplay.commit_capture",
    "redisplay.cancel_capture",
    "input.deliver_event",
    "input.deliver_result",
    "input.deliver_completion_status",
    "lifecycle.heartbeat",
    "lifecycle.flush",
    "lifecycle.diagnostic",
    "lifecycle.cancel_all_pending_work",
};

fn validateGroup(comptime Group: type, group: ?*const Group) Error!void {
    const group_value = group orelse return error.InvalidRuntimeHost;
    if (group_value.abi_version != abi_version) return error.InvalidRuntimeHost;
    if (group_value.size != @sizeOf(Group)) return error.InvalidRuntimeHost;
    if (group_value.context == null) return error.InvalidRuntimeHost;
    inline for (@typeInfo(Group).@"struct".fields) |field| {
        if (comptime std.mem.startsWith(u8, field.name, "context") == false and field.type != u32 and field.type != usize) {
            if (@field(group_value, field.name) == null) return error.InvalidRuntimeHost;
        }
    }
}

pub fn validateTable(table: ?*const PureRuntimeHostV1) Error!void {
    const value = table orelse return error.InvalidRuntimeHost;
    if (value.abi_version != abi_version) return error.InvalidRuntimeHost;
    if (value.size != @sizeOf(PureRuntimeHostV1)) return error.InvalidRuntimeHost;
    if (value.context == null) return error.InvalidRuntimeHost;
    try validateGroup(TerminalGroupV1, value.terminal);
    try validateGroup(FrameGroupV1, value.frame);
    try validateGroup(RedisplayGroupV1, value.redisplay);
    try validateGroup(InputGroupV1, value.input);
    try validateGroup(LifecycleGroupV1, value.lifecycle);
}

pub fn validateTerminalCreate(request: *const TerminalCreateRequest) Error!void {
    if (request.requested_generation == 0) return error.InvalidRuntimeHost;
    if (request.kind != @intFromEnum(TerminalKind.output_proto)) return error.InvalidRuntimeHost;
    if (!std.mem.allEqual(u8, &request.reserved, 0)) return error.InvalidRuntimeHost;
}

pub fn validateIdentity(identity: *const Identity) Error!void {
    if (!identity.valid()) return error.InvalidRuntimeHost;
}

pub fn validateFrameState(state: *const adapter.FrameState) Error!void {
    if (state.generation == 0) return error.InvalidRuntimeHost;
    if (state.visibility > @intFromEnum(adapter.FrameVisibility.iconified)) return error.InvalidRuntimeHost;
    if (state.focused > 1) return error.InvalidRuntimeHost;
    if (!std.mem.allEqual(u8, &state.reserved, 0)) return error.InvalidRuntimeHost;
}

pub fn validateGeometry(geometry: *const adapter.Geometry) Error!void {
    if (!geometry.valid()) return error.InvalidRuntimeHost;
}

pub fn validateCaptureRequest(request: *const CaptureRequest) Error!void {
    try validateIdentity(&request.frame);
    if (request.redisplay_generation == 0 or request.redisplay_generation > std.math.maxInt(u32) or request.reserved != 0) return error.InvalidRuntimeHost;
}

pub fn validateWindowRecord(record: *const WindowRecord) Error!void {
    if (!record.id_valid() or record.width < 0 or record.height < 0 or record.reserved != 0)
        return error.InvalidRuntimeHost;
}

pub fn validateRowRecord(record: *const RowRecord) Error!void {
    if (record.window_id == 0 or record.width < 0 or record.height < 0 or
        record.ascent < 0 or record.descent < 0 or record.baseline < 0 or
        record.visible_height < 0 or record.reserved != 0)
        return error.InvalidRuntimeHost;
}

pub fn validateRunRecord(record: *const RunRecord) Error!void {
    if (record.run_id == 0 or record.run_id > std.math.maxInt(u32) or record.window_id == 0 or record.text_length == 0 or
        record.text_length > record.text.len or record.x < 0 or record.y < 0 or
        record.width < 0 or record.height < 0 or record.direction != 1 or
        record.reserved != 0) return error.InvalidRuntimeHost;
    if ((record.face_id == 0) != (record.face_generation == 0))
        return error.InvalidRuntimeHost;
    for (record.text[0..record.text_length]) |byte| {
        if (byte < 0x20 or byte == 0x7f or byte > 0x7e) return error.InvalidRuntimeHost;
    }
    for (record.text[record.text_length..]) |byte| {
        if (byte != 0) return error.InvalidRuntimeHost;
    }
    switch (record.kind) {
        @intFromEnum(RunKind.text),
        @intFromEnum(RunKind.glyphless),
        @intFromEnum(RunKind.composition),
        @intFromEnum(RunKind.image),
        @intFromEnum(RunKind.stretch),
        @intFromEnum(RunKind.rectangle),
        => {},
        else => return error.InvalidRuntimeHost,
    }
}

pub fn validateShapedRunRecord(record: *const ShapedRunRecord) Error!void {
    if (record.run_id == 0 or record.run_id > std.math.maxInt(u32) or record.window_id == 0 or
        record.face_id == 0 or record.face_generation == 0 or
        record.font_id == 0 or record.glyph_count == 0 or
        record.glyph_count > record.glyphs.len or
        record.direction != 1 or record.flags != 0 or record.reserved != 0 or
        record.x < 0 or record.y < 0 or record.width < 0 or record.height < 0)
        return error.InvalidRuntimeHost;
    for (record.glyphs[0..record.glyph_count]) |glyph| {
        if (glyph.glyph_id == 0) return error.InvalidRuntimeHost;
    }
}

pub fn validateCursorRecord(record: *const CursorRecord) Error!void {
    if (record.window_id == 0 or record.width < 0 or record.height < 0 or
        !std.mem.allEqual(u8, &record.reserved, 0)) return error.InvalidRuntimeHost;
}

pub fn validateDamageRecord(record: *const DamageRecord) Error!void {
    if (record.width < 0 or record.height < 0 or
        !std.mem.allEqual(u8, &record.reserved, 0)) return error.InvalidRuntimeHost;
}

pub fn validateFaceRecord(record: *const FaceRecord) Error!void {
    _ = protocol.decodeFaceDefine(&record.bytes) catch return error.InvalidRuntimeHost;
}

pub fn validateFontRecord(record: *const FontRecord) Error!void {
    _ = protocol.decodeFontDefine(&record.bytes) catch return error.InvalidRuntimeHost;
}

pub fn validateImageDefineRecord(record: *const ImageDefineRecord) Error!void {
    _ = protocol.decodeImageDefine(&record.bytes) catch return error.InvalidRuntimeHost;
}

pub fn validateImageFragmentRecord(record: *const ImageFragmentRecord) Error!void {
    if (record.image_id == 0 or record.generation == 0 or
        record.fragment_count == 0 or record.fragment_count > 4 or
        record.fragment_index >= record.fragment_count or
        record.byte_length == 0 or record.byte_length > record.bytes.len or
        record.reserved != 0) return error.InvalidRuntimeHost;
}

pub fn validateInputEvent(event: *const InputEvent) Error!void {
    if (event.event_id == 0 or event.payload_length > event.payload.len or event.reserved != 0)
        return error.InvalidRuntimeHost;
    switch (event.kind) {
        @intFromEnum(InputKind.key),
        @intFromEnum(InputKind.text),
        @intFromEnum(InputKind.pointer_button),
        @intFromEnum(InputKind.pointer_motion),
        @intFromEnum(InputKind.wheel),
        => {},
        else => return error.InvalidRuntimeHost,
    }
    if (event.kind == @intFromEnum(InputKind.text)) {
        const payload = event.payload[0..event.payload_length];
        if (!std.unicode.utf8ValidateSlice(payload)) return error.InvalidRuntimeHost;
        if (std.mem.indexOfScalar(u8, payload, 0) != null) return error.InvalidRuntimeHost;
    }
}

pub fn validateInputResult(result: *const InputResult) Error!void {
    if (result.event_id == 0 or result.command_status > @intFromEnum(CommandStatus.error_result) or
        !std.mem.allEqual(u8, &result.reserved, 0)) return error.InvalidRuntimeHost;
}

pub fn validateCompletion(result: *const CompletionStatus) Error!void {
    if (result.transaction_id == 0 or !result.status.valid() or
        !std.mem.allEqual(u8, &result.reserved, 0)) return error.InvalidRuntimeHost;
}

pub fn validateDiagnostic(record: *const DiagnosticRecord) Error!void {
    if (record.message_length > record.message.len or
        !std.mem.allEqual(u8, &record.reserved, 0) or
        !std.mem.allEqual(u8, &record.reserved2, 0)) return error.InvalidRuntimeHost;
}

fn invalidIfError(result: Error!void) Status {
    return if (result) Status.ok else |_| Status.invalid;
}

pub const Manifest = struct {
    registered: bool = false,
    runtime_available: bool = false,
    decision_status: []const u8 = "pending",
};

pub const manifest = Manifest{};

pub fn writeManifest(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (manifest.registered or manifest.runtime_available) return error.InvalidRuntimeHost;
    try out.appendSlice(gpa, "{\"manifest_version\":1,\"kind\":\"proto-ui-pure-runtime-host-abi\",");
    try out.appendSlice(gpa, "\"authoritative_source\":");
    try appendJsonString(gpa, out, authoritative_source);
    try out.appendSlice(gpa, ",\"abi_version\":");
    try out.print(gpa, "{d}", .{abi_version});
    try out.appendSlice(gpa, ",\"registered\":false,\"runtime_available\":false,\"decision_status\":\"pending\",\"reason_code\":");
    try appendJsonString(gpa, out, reason_code);
    try out.appendSlice(gpa, ",\"required_callback_groups\":[");
    const groups = [_][]const u8{ "terminal", "frame", "redisplay", "input", "lifecycle" };
    for (groups, 0..) |group, index| {
        if (index != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"name\":");
        try appendJsonString(gpa, out, group);
        try out.appendSlice(gpa, ",\"required\":true}");
    }
    try out.appendSlice(gpa, "],\"operations\":[");
    for (operation_names, 0..) |operation, index| {
        if (index != 0) try out.append(gpa, ',');
        try appendJsonString(gpa, out, operation);
    }
    try out.appendSlice(gpa, "]}\n");
}

pub const TerminalState = enum { absent, active, draining, deleted };

/// Converts a C-ABI status into a Zig error for adapter-owned callers.
pub fn ensureOk(status: Status) Error!void {
    if (status != .ok) return error.HostCallbackFailed;
}

fn appendJsonString(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.append(gpa, '"');
    for (value) |char| {
        switch (char) {
            '"' => try out.appendSlice(gpa, "\\\""),
            '\\' => try out.appendSlice(gpa, "\\\\"),
            '\n' => try out.appendSlice(gpa, "\\n"),
            '\r' => try out.appendSlice(gpa, "\\r"),
            '\t' => try out.appendSlice(gpa, "\\t"),
            else => {
                if (char < 0x20) {
                    try out.print(gpa, "\\u{x:0>4}", .{char});
                } else {
                    try out.append(gpa, char);
                }
            },
        }
    }
    try out.append(gpa, '"');
}

pub const FakeHost = struct {
    terminal: TerminalState = .absent,
    terminal_id: u64 = 0,
    terminal_generation: u64 = 0,
    frame_registered: bool = false,
    frame: Identity = .{},
    frame_visibility: adapter.FrameVisibility = .visible,
    frame_focused: bool = true,
    capture_active: bool = false,
    capture: Identity = .{},
    observations: usize = 0,
    delivered: usize = 0,
    results: usize = 0,
    completions: usize = 0,
    heartbeats: usize = 0,
    flushed: usize = 0,
    diagnostics: usize = 0,
    cancelled: usize = 0,
    force_failure: bool = false,
    terminal_group: TerminalGroupV1 = .{},
    frame_group: FrameGroupV1 = .{},
    redisplay_group: RedisplayGroupV1 = .{},
    input_group: InputGroupV1 = .{},
    lifecycle_group: LifecycleGroupV1 = .{},

    pub fn init() FakeHost {
        return .{};
    }

    pub fn table(self: *FakeHost) PureRuntimeHostV1 {
        return .{
            .abi_version = abi_version,
            .size = @sizeOf(PureRuntimeHostV1),
            .context = self,
            .terminal = &self.terminal_group,
            .frame = &self.frame_group,
            .redisplay = &self.redisplay_group,
            .input = &self.input_group,
            .lifecycle = &self.lifecycle_group,
        };
    }

    fn check(self: *FakeHost) Status {
        return if (self.force_failure) .failed else .ok;
    }

    fn createTerminal(context: *anyopaque, request: *const TerminalCreateRequest, result: *Identity) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateTerminalCreate(request)) != .ok)
            return .invalid;
        if (self.terminal != .absent) return .busy;
        if (self.check() != .ok) return .failed;
        self.terminal = .active;
        self.terminal_id = 1;
        self.terminal_generation = request.requested_generation;
        result.* = .{ .id = self.terminal_id, .generation = self.terminal_generation };
        return .ok;
    }

    fn activateTerminal(context: *anyopaque, identity: *const Identity) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (self.terminal != .active and self.terminal != .draining) return .invalid;
        if (!identity.valid() or identity.id != self.terminal_id or identity.generation != self.terminal_generation)
            return .generation_mismatch;
        if (self.check() != .ok) return .failed;
        self.terminal = .active;
        return .ok;
    }

    fn deleteTerminal(context: *anyopaque, identity: *const Identity) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (!identity.valid() or identity.id != self.terminal_id or identity.generation != self.terminal_generation)
            return .generation_mismatch;
        if (self.terminal != .active and self.terminal != .draining) return .invalid;
        if (self.check() != .ok) return .failed;
        self.terminal = .deleted;
        return .ok;
    }

    fn registerFrame(context: *anyopaque, host_frame: *const Identity, protocol_frame: *Identity) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateIdentity(host_frame)) != .ok or self.frame_registered) return .invalid;
        if (self.check() != .ok) return .failed;
        self.frame_registered = true;
        self.frame = host_frame.*;
        protocol_frame.* = .{ .id = 100, .generation = host_frame.generation };
        return .ok;
    }

    fn unregisterFrame(context: *anyopaque, identity: *const Identity) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (!self.frame_registered or !identity.valid() or identity.id != 100 or identity.generation != self.frame.generation)
            return .generation_mismatch;
        if (self.check() != .ok) return .failed;
        self.frame_registered = false;
        self.frame = .{};
        return .ok;
    }

    fn readFrameState(context: *anyopaque, identity: *const Identity, result: *adapter.FrameState) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (!self.frame_registered or identity.id != 100 or identity.generation != self.frame.generation)
            return .not_found;
        result.* = .{
            .generation = identity.generation,
            .visibility = @intFromEnum(self.frame_visibility),
            .focused = @intFromBool(self.frame_focused),
        };
        return .ok;
    }

    fn readGeometry(context: *anyopaque, identity: *const Identity, result: *adapter.Geometry) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (!self.frame_registered or identity.id != 100) return .not_found;
        result.* = .{ .x = 0, .y = 0, .width = 800, .height = 600 };
        return .ok;
    }

    fn beginCapture(context: *anyopaque, request: *const CaptureRequest, result: *Identity) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateCaptureRequest(request)) != .ok or self.capture_active)
            return .invalid;
        if (self.check() != .ok) return .failed;
        self.capture_active = true;
        self.capture = .{ .id = 7, .generation = request.redisplay_generation };
        result.* = self.capture;
        return .ok;
    }

    fn observeWindow(context: *anyopaque, session: *const Identity, record: *const WindowRecord) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateWindowRecord(record)) != .ok or
            !self.capture_active or session.id != self.capture.id)
            return .invalid;
        self.observations += 1;
        return .ok;
    }

    fn observeRow(context: *anyopaque, session: *const Identity, record: *const RowRecord) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateRowRecord(record)) != .ok or
            !self.capture_active or session.id != self.capture.id)
            return .invalid;
        self.observations += 1;
        return .ok;
    }

    fn observeRun(context: *anyopaque, session: *const Identity, record: *const RunRecord) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateRunRecord(record)) != .ok or
            !self.capture_active or session.id != self.capture.id)
            return .invalid;
        self.observations += 1;
        return .ok;
    }

    pub fn observeShapedRun(context: *anyopaque, session: *const Identity, record: *const ShapedRunRecord) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateShapedRunRecord(record)) != .ok or
            !self.capture_active or session.id != self.capture.id)
            return .invalid;
        self.observations += 1;
        return .ok;
    }

    fn observeCursor(context: *anyopaque, session: *const Identity, record: *const CursorRecord) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateCursorRecord(record)) != .ok or
            !self.capture_active or session.id != self.capture.id)
            return .invalid;
        self.observations += 1;
        return .ok;
    }

    fn observeDamage(context: *anyopaque, session: *const Identity, record: *const DamageRecord) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateDamageRecord(record)) != .ok or
            !self.capture_active or session.id != self.capture.id)
            return .invalid;
        self.observations += 1;
        return .ok;
    }

    fn observeFace(context: *anyopaque, session: *const Identity, record: *const FaceRecord) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateFaceRecord(record)) != .ok or
            !self.capture_active or session.id != self.capture.id)
            return .invalid;
        self.observations += 1;
        return .ok;
    }

    fn observeFont(context: *anyopaque, session: *const Identity, record: *const FontRecord) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateFontRecord(record)) != .ok or
            !self.capture_active or session.id != self.capture.id)
            return .invalid;
        self.observations += 1;
        return .ok;
    }

    fn observeImageDefine(context: *anyopaque, session: *const Identity, record: *const ImageDefineRecord) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateImageDefineRecord(record)) != .ok or
            !self.capture_active or session.id != self.capture.id)
            return .invalid;
        self.observations += 1;
        return .ok;
    }

    fn observeImageFragment(context: *anyopaque, session: *const Identity, record: *const ImageFragmentRecord) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateImageFragmentRecord(record)) != .ok or
            !self.capture_active or session.id != self.capture.id)
            return .invalid;
        self.observations += 1;
        return .ok;
    }

    fn commitCapture(context: *anyopaque, session: *const Identity) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (!self.capture_active or session.id != self.capture.id) return .invalid;
        if (self.check() != .ok) return .failed;
        self.capture_active = false;
        return .ok;
    }

    fn cancelCapture(context: *anyopaque, session: *const Identity) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (!self.capture_active or session.id != self.capture.id) return .invalid;
        self.capture_active = false;
        self.cancelled += 1;
        return .ok;
    }

    fn deliverEvent(context: *anyopaque, event: *const InputEvent, ack: *InputAck) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateInputEvent(event)) != .ok) return .invalid;
        if (self.check() != .ok) return .failed;
        self.delivered += 1;
        ack.* = .{ .event_id = event.event_id, .accepted = true, .status = .ok };
        return .ok;
    }

    fn deliverResult(context: *anyopaque, result: *const InputResult) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateInputResult(result)) != .ok) return .invalid;
        self.results += 1;
        return .ok;
    }

    fn deliverCompletion(context: *anyopaque, result: *const CompletionStatus) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateCompletion(result)) != .ok) return .invalid;
        self.completions += 1;
        return .ok;
    }

    fn heartbeat(context: *anyopaque, result: *HeartbeatResult) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (self.check() != .ok) return .failed;
        self.heartbeats += 1;
        result.* = .{ .sequence = self.heartbeats, .pending_work = 0, .healthy = true };
        return .ok;
    }

    fn flush(context: *anyopaque) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        self.flushed += 1;
        return self.check();
    }

    fn diagnostic(context: *anyopaque, record: *const DiagnosticRecord) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        if (invalidIfError(validateDiagnostic(record)) != .ok) return .invalid;
        self.diagnostics += 1;
        return .ok;
    }

    fn cancelAll(context: *anyopaque) callconv(.c) Status {
        const self: *FakeHost = @ptrCast(@alignCast(context));
        self.cancelled += 1;
        return self.check();
    }
};

pub fn fakeTable(host: *FakeHost) PureRuntimeHostV1 {
    host.* = .{
        .terminal_group = .{ .context = host, .create_terminal = FakeHost.createTerminal, .activate_terminal = FakeHost.activateTerminal, .delete_terminal = FakeHost.deleteTerminal },
        .frame_group = .{ .context = host, .register_frame = FakeHost.registerFrame, .unregister_frame = FakeHost.unregisterFrame, .read_frame_state = FakeHost.readFrameState, .read_geometry = FakeHost.readGeometry },
        .redisplay_group = .{ .context = host, .begin_capture = FakeHost.beginCapture, .observe_window = FakeHost.observeWindow, .observe_row = FakeHost.observeRow, .observe_run = FakeHost.observeRun, .observe_shaped_run = FakeHost.observeShapedRun, .observe_cursor = FakeHost.observeCursor, .observe_damage = FakeHost.observeDamage, .observe_face = FakeHost.observeFace, .observe_font = FakeHost.observeFont, .observe_image_define = FakeHost.observeImageDefine, .observe_image_fragment = FakeHost.observeImageFragment, .commit_capture = FakeHost.commitCapture, .cancel_capture = FakeHost.cancelCapture },
        .input_group = .{ .context = host, .deliver_event = FakeHost.deliverEvent, .deliver_result = FakeHost.deliverResult, .deliver_completion_status = FakeHost.deliverCompletion },
        .lifecycle_group = .{ .context = host, .heartbeat = FakeHost.heartbeat, .flush = FakeHost.flush, .diagnostic = FakeHost.diagnostic, .cancel_all_pending_work = FakeHost.cancelAll },
    };
    return host.table();
}

test "valid pure runtime host table passes validation" {
    var host: FakeHost = undefined;
    const table = fakeTable(&host);
    try validateTable(&table);
}

test "invalid ABI size context or null callback fails without invocation" {
    var host: FakeHost = undefined;
    var table = fakeTable(&host);
    table.abi_version = 2;
    try std.testing.expectError(error.InvalidRuntimeHost, validateTable(&table));

    table = fakeTable(&host);
    table.size = 1;
    try std.testing.expectError(error.InvalidRuntimeHost, validateTable(&table));

    _ = fakeTable(&host);
    host.terminal_group.create_terminal = null;
    table = host.table();
    try std.testing.expectError(error.InvalidRuntimeHost, validateTable(&table));
}

test "fake host terminal frame capture input and lifecycle conformance" {
    var host: FakeHost = undefined;
    const table = fakeTable(&host);
    try validateTable(&table);

    var terminal: Identity = .{};
    try std.testing.expectEqual(Status.ok, table.terminal.?.create_terminal.?(table.terminal.?.context.?, &.{ .requested_generation = 1 }, &terminal));
    try std.testing.expectEqual(Status.ok, table.terminal.?.activate_terminal.?(table.terminal.?.context.?, &terminal));
    var frame_host: Identity = .{ .id = 22, .generation = 8 };
    var frame: Identity = .{};
    try std.testing.expectEqual(Status.ok, table.frame.?.register_frame.?(table.frame.?.context.?, &frame_host, &frame));
    var state: adapter.FrameState = .{};
    try std.testing.expectEqual(Status.ok, table.frame.?.read_frame_state.?(table.frame.?.context.?, &frame, &state));

    var session: Identity = .{};
    try std.testing.expectEqual(Status.ok, table.redisplay.?.begin_capture.?(table.redisplay.?.context.?, &.{ .frame = frame, .redisplay_generation = 8 }, &session));
    try std.testing.expectEqual(Status.ok, table.redisplay.?.observe_window.?(table.redisplay.?.context.?, &session, &.{ .id = 10, .generation = 8 }));
    try std.testing.expectEqual(Status.ok, table.redisplay.?.commit_capture.?(table.redisplay.?.context.?, &session));

    var ack: InputAck = .{};
    try std.testing.expectEqual(Status.ok, table.input.?.deliver_event.?(table.input.?.context.?, &.{ .event_id = 5, .kind = @intFromEnum(InputKind.key) }, &ack));
    try std.testing.expect(ack.accepted);
    var heartbeat: HeartbeatResult = .{};
    try std.testing.expectEqual(Status.ok, table.lifecycle.?.heartbeat.?(table.lifecycle.?.context.?, &heartbeat));

    try std.testing.expectEqual(Status.ok, table.frame.?.unregister_frame.?(table.frame.?.context.?, &frame));
    try std.testing.expectEqual(Status.ok, table.terminal.?.delete_terminal.?(table.terminal.?.context.?, &terminal));
}

test "capture cancel rejects later commit and failure does not create terminal" {
    var host: FakeHost = undefined;
    const table = fakeTable(&host);
    var terminal: Identity = .{};
    host.force_failure = true;
    try std.testing.expectEqual(Status.failed, table.terminal.?.create_terminal.?(table.terminal.?.context.?, &.{ .requested_generation = 1 }, &terminal));
    host.force_failure = false;
    try std.testing.expectEqual(Status.ok, table.terminal.?.create_terminal.?(table.terminal.?.context.?, &.{ .requested_generation = 1 }, &terminal));

    var session: Identity = .{};
    try std.testing.expectEqual(Status.ok, table.redisplay.?.begin_capture.?(table.redisplay.?.context.?, &.{ .frame = .{ .id = 1, .generation = 1 }, .redisplay_generation = 1 }, &session));
    try std.testing.expectEqual(Status.ok, table.redisplay.?.cancel_capture.?(table.redisplay.?.context.?, &session));
    try std.testing.expectEqual(Status.invalid, table.redisplay.?.commit_capture.?(table.redisplay.?.context.?, &session));
}

test "manifest records the ABI as available policy but not runtime" {
    const gpa = std.testing.allocator;
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    try writeManifest(gpa, &output);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"registered\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"runtime_available\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"reason_code\":\"host_registration_contract_missing\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"terminal\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"lifecycle\"") != null);
}
