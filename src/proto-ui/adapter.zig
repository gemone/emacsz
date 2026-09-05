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
};

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
    .{ .id = "adapter_abi", .owner = .adapter, .status = .partial, .summary = "versioned host and adapter tables" },
    .{ .id = "emacs_module_seam", .owner = .adapter, .status = .partial, .summary = "opt-in public frame/window fact observation and EUP/SDL3 snapshot bridge; full display capture and live publishing pending" },
    .{ .id = "normal_rif_streaming", .owner = .adapter, .status = .blocked, .summary = "normal-RIF streaming pending thin-shim embedding" },
    .{ .id = "build_embedding", .owner = .build, .status = .designed, .summary = "zig-build generated manifest and adapter linkage" },
    .{ .id = "sdl3_frontend", .owner = .frontend, .status = .partial, .summary = "SDL3 validates continuous public Emacs facts as EUP snapshots; EPXL streaming, text, input, and Emacs frame pending" },
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
        return .{ .allocator = allocator, .host = host };
    }

    pub fn deinit(self: *Runtime) void {
        self.rows.deinit(self.allocator);
        self.damage.deinit(self.allocator);
        self.* = .{ .allocator = self.allocator, .host = self.host };
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
};

fn validateHost(host: *const HostV1) Error!void {
    if (host.abi_version != abi_version) return Error.AbiMismatch;
    if (host.size < @sizeOf(HostV1)) return Error.AbiMismatch;
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
