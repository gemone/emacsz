//! Adapter-owned host/adapter ABI, boundary manifest, and fake-host runtime.
//!
//! This module is deliberately independent of GNU Emacs internals.  The host
//! supplies opaque object handles and public display facts; the adapter owns
//! capture state, EUP translation, damage policy, and publication.

const std = @import("std");

pub const abi_version: u32 = 1;
pub const eup_major: u32 = 1;
pub const eup_minor: u32 = 0;

pub const max_rows: usize = 256;
pub const max_damage: usize = 256;

pub const Error = error{
    AbiMismatch,
    FrameStateUnsupported,
    FrameStateFailed,
    FrameStateInvalid,
    InvalidArgument,
    GenerationMismatch,
    CaptureActive,
    CapturePartial,
    LimitExceeded,
    OutOfMemory,
};

pub const Geometry = extern struct {
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,

    pub fn valid(self: Geometry) bool {
        return self.width >= 0 and self.height >= 0;
    }
};

pub const FrameVisibility = enum(u8) {
    hidden = 0,
    visible = 1,
    iconified = 2,
};

pub const FrameState = extern struct {
    generation: u64 = 0,
    visibility: u8 = @intFromEnum(FrameVisibility.hidden),
    focused: u8 = 0,
    reserved: [6]u8 = [_]u8{0} ** 6,
};

pub const FrameObservation = struct {
    frame_id: u64,
    generation: u64,
    visibility: FrameVisibility,
    focused: bool,
};

pub const Row = struct {
    window_id: u64,
    index: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    ascent: i32,
    descent: i32,
    baseline: i32,
    visible_height: i32,
};

pub const Cursor = struct {
    window_id: u64,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    kind: u8,
    visible: bool,
    active: bool,
};

pub const Damage = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const ReadGenerationFn = *const fn (context: *anyopaque, object_id: u64) callconv(.c) u64;
pub const ReadGeometryFn = *const fn (context: *anyopaque, object_id: u64, geometry: *Geometry) callconv(.c) u8;
pub const ReadFrameStateFn = *const fn (context: *anyopaque, frame_id: u64, frame_state: *FrameState) callconv(.c) u8;

/// Versioned host-owned callbacks.  A host exposes only opaque handles and
/// public display facts.  No GNU Emacs internal object crosses this boundary.
/// The caller must keep `context` and every callback pointer stable for the
/// lifetime of the Runtime.
/// The entire host table and referenced context must remain valid and stable
/// for the lifetime of the Runtime.
pub const HostV1 = extern struct {
    abi_version: u32 = abi_version,
    size: usize = @sizeOf(HostV1),
    context: ?*anyopaque = null,
    read_generation: ?ReadGenerationFn = null,
    read_geometry: ?ReadGeometryFn = null,
    read_frame_state: ?ReadFrameStateFn = null,
};

/// Size of a v1 table that ends after the two required callbacks.  New hosts
/// may append the optional frame-state callback while retaining ABI major 1.
pub const host_v1_legacy_size: usize = @offsetOf(HostV1, "read_frame_state");

pub const Phase = enum {
    idle,
    capturing,
};

pub const Owner = enum {
    adapter,
    build,
    frontend,
    protocol,
};

pub const IntegrationStatus = enum {
    implemented,
    partial,
    designed,
    planned,
    blocked,
};

pub const IntegrationPoint = struct {
    id: []const u8,
    owner: Owner,
    status: IntegrationStatus,
    summary: []const u8,
};

pub const integration_points = [_]IntegrationPoint{
    .{ .id = "eup_codec", .owner = .protocol, .status = .implemented, .summary = "adapter-only EUP envelope, capability, and FRAME_UPDATE codec" },
    .{ .id = "transport", .owner = .adapter, .status = .implemented, .summary = "adapter-only bounded memory sink and ERP1 replay-file codec" },
    .{ .id = "live_transport", .owner = .adapter, .status = .partial, .summary = "EPXL v1 local Unix handshake, frames, ACK backpressure; reconnect/coalescing pending" },
    .{ .id = "live_backpressure", .owner = .adapter, .status = .partial, .summary = "one-message EPXL ACK window; reconnect/coalescing pending" },
    .{ .id = "capability_negotiation", .owner = .adapter, .status = .implemented, .summary = "bounded EPXL name/value negotiation with required-feature intersection, hash verification, and generated status manifest; full EUP feature coverage pending" },
    .{ .id = "host_frame_state_seam", .owner = .adapter, .status = .partial, .summary = "optional ABI v1 read_frame_state callback with backward-compatible host tables and fail-closed frame state validation; output_proto runtime integration pending" },
    .{ .id = "frame_service_mapping", .owner = .adapter, .status = .partial, .summary = "bounded host-handle to EUP-frame identity/state mapping with fail-closed observation, generation refresh, delete-once, and terminal drain; Emacs host registration and output_proto ownership pending" },
    .{ .id = "frame_resource_contract", .owner = .adapter, .status = .partial, .summary = "bounded frame create/update/destroy state machine, real-frame lifecycle smoke, visibility/focus contract, resource-generation declaration contract, and bounded resource payload cache/eviction implemented; output_proto frame ownership, redisplay integration, resource payloads, deletion transport, snapshots, and full resource parity pending" },
    .{ .id = "adapter_abi", .owner = .adapter, .status = .partial, .summary = "versioned host and adapter tables" },
    .{ .id = "emacs_module_seam", .owner = .adapter, .status = .partial, .summary = "opt-in public frame/window fact observation, bounded viewport metadata, and EUP/SDL3 snapshot bridge; full display capture and live publishing pending" },
    .{ .id = "normal_rif_streaming", .owner = .adapter, .status = .blocked, .summary = "normal-RIF streaming pending thin-shim embedding" },
    .{ .id = "build_embedding", .owner = .build, .status = .designed, .summary = "zig-build generated manifest and adapter linkage" },
    .{ .id = "sdl3_frontend", .owner = .frontend, .status = .partial, .summary = "SDL3 validates continuous public Emacs facts as EUP snapshots; EPXL streaming, facts text/cursor/viewport metadata, bounded ASCII text, pressed unmodified backspace and cursor actions, and a bounded real-frame lifecycle smoke are implemented, while full scroll state, pixel vscroll, overlays, variable-pitch lines, glyph runs, shaped text, keyboard/keymap/IME input, output_proto frame ownership, and redisplay-owned lifecycle pending" },
    .{ .id = "renderer_selection", .owner = .frontend, .status = .partial, .summary = "adapter-owned auto/software/GPU/named selection policy, actual-tier classification, GPU-to-software fallback, and present-mode request; GPU draw graph and counters pending" },
    .{ .id = "frame_pacing", .owner = .frontend, .status = .partial, .summary = "dirty/resize-aware full-frame gate with present/skip, frame-path, and initial/cursor/text/region/viewport/unchanged damage counters; cursor-only and bounded ASCII text/cursor changes use retained-frame clips; viewport, oversized/incomplete observations, and fallbacks remain full-frame, while general EUP rectangle damage/GPU timestamps pending" },
    .{ .id = "draw_list", .owner = .frontend, .status = .partial, .summary = "reusable backend-neutral clear/fill/debug-text command list executed by SDL software and GPU-backed renderers; glyph atlas, images, scissor/blend, rectangle damage, and native GPU counters pending" },
    .{ .id = "input_translation", .owner = .frontend, .status = .partial, .summary = "bounded SDL key/text translation queue for printable ASCII plus backspace/cursor/copy and best-effort pointer motion plus ordered left press/drag/release sessions and bounded vertical wheel ticks through the persistent EPXL delivery journal; modifiers, Unicode, focus, full keymaps, selection drag, horizontal/pixel scrolling, and related capabilities pending" },
    .{ .id = "emacs_interactive_bridge", .owner = .frontend, .status = .partial, .summary = "real SDL facts window with authenticated EPXL input as the default path and an explicit bounded local-action fallback; redisplay-owned glyphs and full interactive input pending" },
    .{ .id = "clipboard_text", .owner = .frontend, .status = .partial, .summary = "Ctrl+V SDL clipboard capture bounded to printable ASCII input; Unicode, rich text, MIME offers, and selection ownership pending" },
    .{ .id = "clipboard_copy", .owner = .frontend, .status = .partial, .summary = "Ctrl+C copy intent over authenticated EPXL with a bounded validated clipboard-result artifact; local fallback remains; Unicode, rich text, MIME offers, and selection ownership pending" },
    .{ .id = "glyph_atlas_policy", .owner = .frontend, .status = .partial, .summary = "bounded glyph-key atlas placement policy with LRU replacement and counters; rasterization, textures, uploads, and glyph runs pending" },
    .{ .id = "epxl_input_sequence", .owner = .frontend, .status = .partial, .summary = "bounded delivery journal with monotonic sequences, exact ACK matching, fault-injected reconnect recovery, and real SDL interactive input; publisher-crash recovery and full keymaps pending" },
};

pub const ManifestIssue = struct {
    id: ?[]const u8 = null,
    reason: []const u8,
};

pub const BoundaryClass = enum {
    adapter,
    build,
    protocol,
    frontend,
    documentation,
    tests,
    inherited_c,
    other,
};

pub fn validateManifest() ?ManifestIssue {
    if (integration_points.len == 0)
        return .{ .reason = "manifest is empty" };

    for (integration_points, 0..) |point, i| {
        if (point.id.len == 0) return .{ .reason = "integration point has empty id" };
        if (point.summary.len == 0)
            return .{ .id = point.id, .reason = "integration point has empty summary" };

        var j = i + 1;
        while (j < integration_points.len) : (j += 1) {
            if (std.mem.eql(u8, point.id, integration_points[j].id))
                return .{ .id = point.id, .reason = "duplicate integration point id" };
        }
    }

    for (integration_points) |point| {
        if (point.owner != .adapter and point.owner != .protocol and
            point.owner != .frontend and point.owner != .build)
            return .{ .id = point.id, .reason = "integration point owner is not adapter-first" };
    }

    return null;
}

pub fn classifyPath(path: []const u8) BoundaryClass {
    if (std.mem.indexOf(u8, path, "..") != null and
        (std.mem.endsWith(u8, path, ".c") or
            std.mem.endsWith(u8, path, ".h") or
            std.mem.endsWith(u8, path, ".m") or
            std.mem.endsWith(u8, path, ".mm")))
        return .inherited_c;

    if (hasPathPrefix(path, "src/proto-ui/")) return .adapter;
    if (hasPathPrefix(path, "docs/proto-ui/")) return .documentation;
    if (hasPathPrefix(path, "tools/proto-ui/")) return .adapter;
    if (hasPathPrefix(path, "tools/proto-ui-sdl3/")) return .frontend;
    if (hasPathPrefix(path, "tools/proto-ui-emacs-module/")) return .adapter;
    if (hasPathPrefix(path, "zig-cache/proto-ui/")) return .adapter;
    if (hasPathPrefix(path, "zig-out/include/proto-ui/")) return .adapter;
    if (std.mem.eql(u8, path, "build.zig")) return .build;
    if (hasPathPrefix(path, "test/proto-ui/")) return .tests;

    const is_c_or_header = std.mem.endsWith(u8, path, ".c") or
        std.mem.endsWith(u8, path, ".h") or
        std.mem.endsWith(u8, path, ".m") or
        std.mem.endsWith(u8, path, ".mm");
    if (is_c_or_header) return .inherited_c;

    return .other;
}

pub fn isNewInheritedCoreEdit(path: []const u8) bool {
    return classifyPath(path) == .inherited_c;
}

fn hasPathPrefix(path: []const u8, prefix: []const u8) bool {
    if (path.len < prefix.len) return false;
    for (prefix, 0..) |expected, i| {
        const actual: u8 = if (path[i] == '\\') '/' else path[i];
        const wanted: u8 = if (expected == '\\') '/' else expected;
        if (actual != wanted) return false;
    }
    return true;
}

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    host: *const HostV1,
    host_size: usize,
    frame_state_available: bool = false,
    phase: Phase = .idle,
    frame_id: u64 = 0,
    generation: u64 = 0,
    window_id: u64 = 0,
    geometry: Geometry = .{},
    has_window: bool = false,
    has_row: bool = false,
    has_cursor: bool = false,
    has_damage: bool = false,
    rows: std.ArrayList(Row) = .empty,
    damage: std.ArrayList(Damage) = .empty,
    cursor: ?Cursor = null,
    committed_updates: u64 = 0,
    cancelled_updates: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, host: *const HostV1) Error!Runtime {
        try validateHost(host);
        const frame_state_available = host.size >= @sizeOf(HostV1) and
            host.read_frame_state != null;
        return .{
            .allocator = allocator,
            .host = host,
            .host_size = host.size,
            .frame_state_available = frame_state_available,
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.rows.deinit(self.allocator);
        self.damage.deinit(self.allocator);
        self.* = .{
            .allocator = self.allocator,
            .host = self.host,
            .host_size = self.host_size,
            .frame_state_available = self.frame_state_available,
        };
    }

    pub fn begin(self: *Runtime, frame_id: u64) Error!void {
        if (frame_id == 0) return Error.InvalidArgument;
        if (self.phase == .capturing) return Error.CaptureActive;

        const read_generation = self.host.read_generation orelse
            return Error.AbiMismatch;
        const context = self.host.context orelse return Error.AbiMismatch;
        self.generation = read_generation(context, frame_id);
        if (self.generation == 0) return Error.GenerationMismatch;

        self.phase = .capturing;
        self.frame_id = frame_id;
        self.window_id = 0;
        self.geometry = .{};
        self.has_window = false;
        self.has_row = false;
        self.has_cursor = false;
        self.has_damage = false;
        self.rows.clearRetainingCapacity();
        self.damage.clearRetainingCapacity();
        self.cursor = null;
    }

    pub fn captureWindow(self: *Runtime, window_id: u64) Error!void {
        if (self.phase != .capturing or window_id == 0) return Error.InvalidArgument;
        if (self.has_window or self.rows.items.len != 0 or
            self.has_cursor or self.damage.items.len != 0)
            return Error.InvalidArgument;

        var geometry = Geometry{};
        if (self.host.read_geometry) |read_geometry| {
            const context = self.host.context orelse return Error.AbiMismatch;
            if (read_geometry(context, window_id, &geometry) == 0)
                return Error.InvalidArgument;
        }
        if (!geometry.valid()) return Error.InvalidArgument;

        self.window_id = window_id;
        self.geometry = geometry;
        self.has_window = true;
    }

    pub fn captureRow(self: *Runtime, row: Row) Error!void {
        if (self.phase != .capturing) return Error.InvalidArgument;
        if (!self.has_window) return Error.InvalidArgument;
        if (row.window_id != self.window_id) return Error.InvalidArgument;
        if (row.width < 0 or row.height < 0) return Error.InvalidArgument;
        if (self.rows.items.len == max_rows) return Error.LimitExceeded;

        try self.rows.append(self.allocator, row);
        self.has_row = true;
    }

    pub fn captureCursor(self: *Runtime, cursor: Cursor) Error!void {
        if (self.phase != .capturing or !self.has_window or
            cursor.window_id != self.window_id)
            return Error.InvalidArgument;
        self.cursor = cursor;
        self.has_cursor = true;
    }

    pub fn captureDamage(self: *Runtime, damage: Damage) Error!void {
        if (self.phase != .capturing) return Error.InvalidArgument;
        if (!self.has_window) return Error.InvalidArgument;
        if (damage.width < 0 or damage.height < 0) return Error.InvalidArgument;
        if (self.damage.items.len == max_damage) return Error.LimitExceeded;

        try self.damage.append(self.allocator, damage);
        self.has_damage = true;
    }

    pub fn cancel(self: *Runtime) void {
        if (self.phase == .capturing) self.cancelled_updates += 1;
        self.phase = .idle;
        self.frame_id = 0;
        self.generation = 0;
        self.window_id = 0;
        self.has_window = false;
        self.has_row = false;
        self.has_cursor = false;
        self.has_damage = false;
        self.rows.clearRetainingCapacity();
        self.damage.clearRetainingCapacity();
        self.cursor = null;
    }

    pub fn commit(self: *Runtime) Error!u64 {
        if (self.phase != .capturing) return Error.InvalidArgument;

        const read_generation = self.host.read_generation orelse
            return Error.AbiMismatch;
        const context = self.host.context orelse return Error.AbiMismatch;
        const host_generation = read_generation(context, self.frame_id);
        if (host_generation != self.generation) return Error.GenerationMismatch;
        if (!self.has_window or !self.has_row or self.rows.items.len == 0 or !self.has_damage)
            return Error.CapturePartial;

        self.phase = .idle;
        self.committed_updates += 1;
        const generation = self.generation;
        self.generation = 0;
        self.window_id = 0;
        self.has_window = false;
        self.has_row = false;
        self.has_cursor = false;
        self.has_damage = false;
        self.rows.clearRetainingCapacity();
        self.damage.clearRetainingCapacity();
        self.cursor = null;
        return generation;
    }

    pub fn observeFrameState(self: *Runtime, frame_id: u64) Error!FrameObservation {
        if (frame_id == 0) return Error.InvalidArgument;
        if (!self.frame_state_available)
            return Error.FrameStateUnsupported;

        const read_frame_state = self.host.read_frame_state.?;
        const context = self.host.context orelse return Error.AbiMismatch;
        var state = FrameState{};
        const succeeded = read_frame_state(context, frame_id, &state);
        if (succeeded != 1) return Error.FrameStateFailed;
        if (state.generation == 0) return Error.GenerationMismatch;

        const visibility = switch (state.visibility) {
            0 => FrameVisibility.hidden,
            1 => FrameVisibility.visible,
            2 => FrameVisibility.iconified,
            else => return Error.FrameStateInvalid,
        };
        if (state.focused > 1) return Error.FrameStateInvalid;
        if (state.focused == 1 and visibility != .visible)
            return Error.FrameStateInvalid;
        for (state.reserved) |byte| {
            if (byte != 0) return Error.FrameStateInvalid;
        }

        return .{
            .frame_id = frame_id,
            .generation = state.generation,
            .visibility = visibility,
            .focused = state.focused == 1,
        };
    }
};

fn validateHost(host: *const HostV1) Error!void {
    if (host.abi_version != abi_version) return Error.AbiMismatch;
    if (host.size < host_v1_legacy_size) return Error.AbiMismatch;
    if (host.context == null) return Error.AbiMismatch;
    if (host.read_generation == null) return Error.AbiMismatch;
    if (host.read_geometry == null) return Error.AbiMismatch;
}

test "manifest is complete and adapter-first" {
    try std.testing.expect(validateManifest() == null);
    try std.testing.expect(integration_points.len >= 6);
}

test "path classifier separates adapter and inherited C" {
    try std.testing.expectEqual(BoundaryClass.adapter, classifyPath("src/proto-ui/adapter.zig"));
    try std.testing.expectEqual(BoundaryClass.build, classifyPath("build.zig"));
    try std.testing.expectEqual(BoundaryClass.documentation, classifyPath("docs/proto-ui/adapter-boundary.md"));
    try std.testing.expectEqual(BoundaryClass.frontend, classifyPath("tools/proto-ui-sdl3/main.zig"));
    try std.testing.expectEqual(BoundaryClass.inherited_c, classifyPath("src/xdisp.c"));
    try std.testing.expect(isNewInheritedCoreEdit("src/xdisp.c"));
    try std.testing.expect(!isNewInheritedCoreEdit("src/proto-ui/runtime.zig"));
    try std.testing.expect(isNewInheritedCoreEdit("oldXMenu/Activate.c"));
    try std.testing.expect(isNewInheritedCoreEdit("exec/exec.c"));
    try std.testing.expect(isNewInheritedCoreEdit("admin/alloc-colors.c"));
    try std.testing.expect(isNewInheritedCoreEdit("nextstep/Emacs.app/Abcd.m"));
    try std.testing.expect(isNewInheritedCoreEdit("src\\xdisp.c"));
    try std.testing.expect(isNewInheritedCoreEdit("src/proto-ui/../../src/xdisp.c"));
    try std.testing.expect(!isNewInheritedCoreEdit("zig-cache/proto-ui/generated.c"));
}

test "host ABI requires context and public geometry callback" {
    const allocator = std.testing.allocator;
    var host = FakeHost.init(51);
    var table = host.table();
    table.context = null;
    try std.testing.expectError(Error.AbiMismatch, Runtime.init(allocator, &table));
    table.context = &host;
    table.read_geometry = null;
    try std.testing.expectError(Error.AbiMismatch, Runtime.init(allocator, &table));

    table.read_geometry = FakeHost.readGeometry;
    var runtime = try Runtime.init(allocator, &table);
    defer runtime.deinit();
}

test "extern geometry matches the generated C ABI layout" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Geometry));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Geometry, "x"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(Geometry, "y"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(Geometry, "width"));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(Geometry, "height"));
}

test "frame state matches the generated C ABI layout" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(FrameState));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(FrameState, "generation"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(FrameState, "visibility"));
    try std.testing.expectEqual(@as(usize, 9), @offsetOf(FrameState, "focused"));
    try std.testing.expectEqual(@as(usize, 10), @offsetOf(FrameState, "reserved"));
}

const FrameStateFakeHost = struct {
    generation: u64,
    visibility: FrameVisibility,
    focused: bool,
    success: u8 = 1,
    callback_count: u64 = 0,
    reserved_byte: u8 = 0,

    fn table(self: *FrameStateFakeHost) HostV1 {
        return .{
            .abi_version = abi_version,
            .size = @sizeOf(HostV1),
            .context = self,
            .read_generation = readGeneration,
            .read_geometry = readGeometry,
            .read_frame_state = readFrameState,
        };
    }

    fn readGeneration(context: *anyopaque, object_id: u64) callconv(.c) u64 {
        _ = object_id;
        const self: *FrameStateFakeHost = @ptrCast(@alignCast(context));
        return self.generation;
    }

    fn readGeometry(context: *anyopaque, object_id: u64, geometry: *Geometry) callconv(.c) u8 {
        _ = context;
        _ = object_id;
        geometry.* = .{ .width = 80, .height = 60 };
        return 1;
    }

    fn readFrameState(context: *anyopaque, frame_id: u64, frame_state: *FrameState) callconv(.c) u8 {
        _ = frame_id;
        const self: *FrameStateFakeHost = @ptrCast(@alignCast(context));
        self.callback_count += 1;
        frame_state.* = .{
            .generation = self.generation,
            .visibility = @intFromEnum(self.visibility),
            .focused = @intFromBool(self.focused),
            .reserved = [_]u8{self.reserved_byte} ** 6,
        };
        return self.success;
    }
};

test "runtime observes optional host frame state" {
    const allocator = std.testing.allocator;
    inline for ([_]FrameVisibility{ .hidden, .visible, .iconified }) |visibility| {
        var host = FrameStateFakeHost{
            .generation = 42,
            .visibility = visibility,
            .focused = visibility == .visible,
        };
        var table = host.table();
        var runtime = try Runtime.init(allocator, &table);
        defer runtime.deinit();

        const observation = try runtime.observeFrameState(10);
        try std.testing.expectEqual(@as(u64, 10), observation.frame_id);
        try std.testing.expectEqual(@as(u64, 42), observation.generation);
        try std.testing.expectEqual(visibility, observation.visibility);
        try std.testing.expectEqual(visibility == .visible, observation.focused);
        try std.testing.expectEqual(@as(u64, 1), host.callback_count);
    }
}

test "runtime fails closed for invalid host frame state" {
    const allocator = std.testing.allocator;

    var state_host = FrameStateFakeHost{
        .generation = 42,
        .visibility = .visible,
        .focused = true,
    };
    var state_table = state_host.table();
    var state_runtime = try Runtime.init(allocator, &state_table);
    defer state_runtime.deinit();
    try std.testing.expectError(Error.InvalidArgument, state_runtime.observeFrameState(0));

    for ([_]u8{ 0, 2 }) |success| {
        state_host.success = success;
        try std.testing.expectError(Error.FrameStateFailed, state_runtime.observeFrameState(10));
    }
    state_host.success = 1;

    state_host.generation = 0;
    try std.testing.expectError(Error.GenerationMismatch, state_runtime.observeFrameState(10));
    state_host.generation = 42;

    for ([_]FrameVisibility{ .hidden, .iconified }) |visibility| {
        state_host.visibility = visibility;
        state_host.focused = true;
        try std.testing.expectError(Error.FrameStateInvalid, state_runtime.observeFrameState(10));
    }

    state_host.visibility = .visible;
    state_host.focused = true;
    state_host.reserved_byte = 1;
    try std.testing.expectError(Error.FrameStateInvalid, state_runtime.observeFrameState(10));
}

test "legacy host tables retain capture and do not expose frame state" {
    const LegacyHostV1 = extern struct {
        abi_version: u32,
        size: usize,
        context: *anyopaque,
        read_generation: *const fn (*anyopaque, u64) callconv(.c) u64,
        read_geometry: *const fn (*anyopaque, u64, *Geometry) callconv(.c) u8,
    };

    const allocator = std.testing.allocator;
    var host = FakeHost.init(77);
    var legacy = LegacyHostV1{
        .abi_version = abi_version,
        .size = @sizeOf(LegacyHostV1),
        .context = &host,
        .read_generation = FakeHost.readGeneration,
        .read_geometry = FakeHost.readGeometry,
    };
    const legacy_table: *const HostV1 = @ptrCast(&legacy);
    try std.testing.expectEqual(host_v1_legacy_size, legacy.size);
    var runtime = try Runtime.init(allocator, legacy_table);
    defer runtime.deinit();

    try std.testing.expectError(Error.FrameStateUnsupported, runtime.observeFrameState(10));
    try runtime.begin(10);
    try runtime.captureWindow(20);
    try runtime.captureRow(.{ .window_id = 20, .index = 0, .x = 0, .y = 0, .width = 40, .height = 10, .ascent = 8, .descent = 2, .baseline = 8, .visible_height = 10 });
    try runtime.captureDamage(.{ .x = 0, .y = 0, .width = 40, .height = 10 });
    try std.testing.expectEqual(@as(u64, 77), try runtime.commit());
}

test "runtime accepts complete fake host capture" {
    const allocator = std.testing.allocator;
    var host = FakeHost.init(101);
    var table = host.table();
    var runtime = try Runtime.init(allocator, &table);
    defer runtime.deinit();

    try runtime.begin(10);
    try runtime.captureWindow(20);
    try runtime.captureRow(.{
        .window_id = 20,
        .index = 0,
        .x = 0,
        .y = 0,
        .width = 40,
        .height = 10,
        .ascent = 8,
        .descent = 2,
        .baseline = 8,
        .visible_height = 10,
    });
    try runtime.captureCursor(.{ .window_id = 20, .x = 1, .y = 0, .width = 2, .height = 10, .kind = 1, .visible = true, .active = true });
    try runtime.captureDamage(.{ .x = 0, .y = 0, .width = 40, .height = 10 });
    try std.testing.expectEqual(@as(u64, 101), try runtime.commit());
    try std.testing.expectEqual(@as(u64, 1), runtime.committed_updates);
}

test "runtime rejects ABI and host generation mismatches" {
    const allocator = std.testing.allocator;
    var host = FakeHost.init(0);
    var table = host.table();
    table.abi_version = abi_version + 1;
    try std.testing.expectError(Error.AbiMismatch, Runtime.init(allocator, &table));

    table = host.table();
    table.read_generation = null;
    try std.testing.expectError(Error.AbiMismatch, Runtime.init(allocator, &table));
    table.read_generation = FakeHost.readGeneration;

    host.generation = 0;
    var runtime = try Runtime.init(allocator, &table);
    defer runtime.deinit();
    try std.testing.expectError(Error.GenerationMismatch, runtime.begin(10));
}

test "runtime requires a complete capture before commit" {
    const allocator = std.testing.allocator;
    var host = FakeHost.init(7);
    var table = host.table();
    var runtime = try Runtime.init(allocator, &table);
    defer runtime.deinit();

    try runtime.begin(10);
    try std.testing.expectError(Error.CapturePartial, runtime.commit());
    runtime.cancel();
    try std.testing.expectEqual(@as(u64, 0), runtime.committed_updates);
    try std.testing.expectEqual(@as(u64, 1), runtime.cancelled_updates);
}

pub const FakeHost = struct {
    generation: u64,

    pub fn init(generation: u64) FakeHost {
        return .{ .generation = generation };
    }

    pub fn table(self: *FakeHost) HostV1 {
        return .{
            .context = self,
            .read_generation = readGeneration,
            .read_geometry = readGeometry,
        };
    }

    fn readGeneration(context: *anyopaque, object_id: u64) callconv(.c) u64 {
        _ = object_id;
        const self: *FakeHost = @ptrCast(@alignCast(context));
        return self.generation;
    }

    fn readGeometry(context: *anyopaque, object_id: u64, geometry: *Geometry) callconv(.c) u8 {
        _ = context;
        _ = object_id;
        geometry.* = .{ .x = 0, .y = 0, .width = 320, .height = 200 };
        return 1;
    }
};
