//! Tracked Zig host harness for the generated Proto-UI thin C shim.
//!
//! The build graph compiles generated C directly into this host test.  The
//! harness checks ABI layout and fail-closed delegation only; it owns no Emacs
//! state and exercises no transport or protocol encoding.

const std = @import("std");
const adapter = @import("adapter.zig");
const abi_gen = @import("abi_gen.zig");

const c = @cImport({
    @cInclude("abi_v1.h");
});

const Host = struct {
    generation: u64 = 0,
    frame_generation: u64 = 0x0102030405060708,
    frame_visibility: u8 = 2,
    frame_focused: u8 = 0,
    geometry_result: u8 = 1,
    frame_result: u8 = 1,
    generation_calls: u32 = 0,
    geometry_calls: u32 = 0,
    frame_calls: u32 = 0,

    fn table(self: *Host) c.ProtoUiHostV1 {
        return .{
            .abi_version = c.PROTO_UI_ABI_VERSION,
            .size = @sizeOf(c.ProtoUiHostV1),
            .context = self,
            .read_generation = readGeneration,
            .read_geometry = readGeometry,
            .read_frame_state = readFrameState,
        };
    }

    fn readGeneration(context: ?*anyopaque, object_id: c_ulonglong) callconv(.c) c_ulonglong {
        _ = object_id;
        const self: *Host = @ptrCast(@alignCast(context.?));
        self.generation_calls += 1;
        return self.generation;
    }

    fn readGeometry(context: ?*anyopaque, object_id: c_ulonglong, geometry: [*c]c.ProtoUiGeometry) callconv(.c) u8 {
        _ = object_id;
        const self: *Host = @ptrCast(@alignCast(context.?));
        self.geometry_calls += 1;
        geometry.* = .{ .x = 1, .y = 2, .width = 320, .height = 200 };
        return self.geometry_result;
    }

    fn readFrameState(context: ?*anyopaque, frame_id: c_ulonglong, state: [*c]c.ProtoUiFrameState) callconv(.c) u8 {
        _ = frame_id;
        const self: *Host = @ptrCast(@alignCast(context.?));
        self.frame_calls += 1;
        state.* = .{
            .generation = self.frame_generation,
            .visibility = self.frame_visibility,
            .focused = self.frame_focused,
            .reserved = [_]u8{0} ** 6,
        };
        return self.frame_result;
    }
};

fn expectStatus(actual: u8, expected: u8) !void {
    if (actual != expected) return error.ShimConformanceStatusMismatch;
}

test "generated ABI and C/Zig layouts are stable" {
    try std.testing.expectEqual(@as(u8, 1), c.proto_ui_shim_abi_version());
    try std.testing.expectEqual(@sizeOf(adapter.Geometry), @sizeOf(c.ProtoUiGeometry));
    try std.testing.expectEqual(@offsetOf(adapter.Geometry, "x"), @offsetOf(c.ProtoUiGeometry, "x"));
    try std.testing.expectEqual(@offsetOf(adapter.Geometry, "y"), @offsetOf(c.ProtoUiGeometry, "y"));
    try std.testing.expectEqual(@offsetOf(adapter.Geometry, "width"), @offsetOf(c.ProtoUiGeometry, "width"));
    try std.testing.expectEqual(@offsetOf(adapter.Geometry, "height"), @offsetOf(c.ProtoUiGeometry, "height"));

    try std.testing.expectEqual(@sizeOf(adapter.FrameState), @sizeOf(c.ProtoUiFrameState));
    try std.testing.expectEqual(@offsetOf(adapter.FrameState, "generation"), @offsetOf(c.ProtoUiFrameState, "generation"));
    try std.testing.expectEqual(@offsetOf(adapter.FrameState, "visibility"), @offsetOf(c.ProtoUiFrameState, "visibility"));
    try std.testing.expectEqual(@offsetOf(adapter.FrameState, "focused"), @offsetOf(c.ProtoUiFrameState, "focused"));
    try std.testing.expectEqual(@offsetOf(adapter.FrameState, "reserved"), @offsetOf(c.ProtoUiFrameState, "reserved"));

    try std.testing.expectEqual(@sizeOf(adapter.HostV1), @sizeOf(c.ProtoUiHostV1));
    inline for (.{ "abi_version", "size", "context", "read_generation", "read_geometry", "read_frame_state" }) |field| {
        try std.testing.expectEqual(@offsetOf(adapter.HostV1, field), @offsetOf(c.ProtoUiHostV1, field));
    }
    try std.testing.expectEqual(adapter.host_v1_legacy_size, @sizeOf(LegacyHostV1));
}

test "generated shim delegates success paths and copies outputs" {
    var host = Host{ .generation = 42 };
    const table = host.table();
    var generation: c_ulonglong = 999;
    try expectStatus(c.proto_ui_shim_read_generation(&table, 10, &generation), c.PROTO_UI_STATUS_SUCCESS);
    try std.testing.expectEqual(@as(c_ulonglong, 42), generation);
    try std.testing.expectEqual(@as(u32, 1), host.generation_calls);

    var geometry: c.ProtoUiGeometry = undefined;
    try expectStatus(c.proto_ui_shim_read_geometry(&table, 20, &geometry), c.PROTO_UI_STATUS_SUCCESS);
    try std.testing.expectEqual(@as(c_int, 1), geometry.x);
    try std.testing.expectEqual(@as(c_int, 2), geometry.y);
    try std.testing.expectEqual(@as(c_int, 320), geometry.width);
    try std.testing.expectEqual(@as(c_int, 200), geometry.height);

    var state: c.ProtoUiFrameState = .{
        .generation = 0xdeadbeefdeadbeef,
        .visibility = 0xaa,
        .focused = 0x55,
        .reserved = [_]u8{0x77} ** 6,
    };
    try expectStatus(c.proto_ui_shim_read_frame_state(&table, 30, &state), c.PROTO_UI_STATUS_SUCCESS);
    try std.testing.expectEqual(host.frame_generation, state.generation);
    try std.testing.expectEqual(host.frame_visibility, state.visibility);
    try std.testing.expectEqual(host.frame_focused, state.focused);
    try std.testing.expectEqualSlices(u8, &[_]u8{0} ** 6, &state.reserved);
    try std.testing.expectEqual(@as(u32, 1), host.frame_calls);
}

test "generated manifest parses as exactly one strict JSON object" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, abi_gen.manifest, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(std.json.Value{ .object = parsed.value.object }, parsed.value);
    try std.testing.expectEqual(@as(i64, 1), parsed.value.object.get("abi_version").?.integer);
    const tables = parsed.value.object.get("tables").?.object;
    const host = tables.get("host_v1").?.object;
    try std.testing.expectEqual(@as(u64, 3), host.get("callbacks").?.array.items.len);
    try std.testing.expectEqual(@as(u64, 1), host.get("optional_callbacks").?.array.items.len);

    for ([_][]const u8{ abi_gen.manifest ++ " {}", abi_gen.manifest ++ "x" }) |invalid| {
        try std.testing.expectError(error.SyntaxError, std.json.parseFromSliceLeaky(
            std.json.Value,
            arena.allocator(),
            invalid,
            .{},
        ));
    }
}

test "generated shim rejects null arguments without callbacks" {
    var host = Host{ .generation = 44 };
    const table = host.table();
    var generation: c_ulonglong = 0;
    var geometry: c.ProtoUiGeometry = undefined;
    var state: c.ProtoUiFrameState = undefined;

    try expectStatus(c.proto_ui_shim_host_validate(null), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try expectStatus(c.proto_ui_shim_read_generation(null, 1, &generation), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try expectStatus(c.proto_ui_shim_read_generation(&table, 1, null), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try expectStatus(c.proto_ui_shim_read_geometry(null, 1, &geometry), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try expectStatus(c.proto_ui_shim_read_geometry(&table, 1, null), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try expectStatus(c.proto_ui_shim_read_frame_state(null, 1, &state), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try expectStatus(c.proto_ui_shim_read_frame_state(&table, 1, null), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try std.testing.expectEqual(@as(u32, 0), host.generation_calls);
    try std.testing.expectEqual(@as(u32, 0), host.geometry_calls);
    try std.testing.expectEqual(@as(u32, 0), host.frame_calls);
}

test "generated shim rejects wrong ABI and malformed table sizes" {
    var host = Host{ .generation = 45 };
    var table = host.table();

    table.abi_version = c.PROTO_UI_ABI_VERSION + 1;
    try expectStatus(c.proto_ui_shim_host_validate(&table), c.PROTO_UI_STATUS_ABI_MISMATCH);

    table = host.table();
    table.size = 1;
    try expectStatus(c.proto_ui_shim_read_geometry(&table, 1, undefined), c.PROTO_UI_STATUS_ABI_MISMATCH);

    table = host.table();
    table.size = @sizeOf(c.ProtoUiHostV1) - 1;
    try expectStatus(c.proto_ui_shim_host_validate(&table), c.PROTO_UI_STATUS_ABI_MISMATCH);
}

test "generated shim reports missing callbacks and failures" {
    var host = Host{ .generation = 46 };
    var table = host.table();
    var generation: c_ulonglong = 0;
    var geometry: c.ProtoUiGeometry = undefined;
    var state: c.ProtoUiFrameState = undefined;

    table.read_generation = null;
    try expectStatus(c.proto_ui_shim_read_generation(&table, 1, &generation), c.PROTO_UI_STATUS_CALLBACK_MISSING);
    table = host.table();
    table.read_geometry = null;
    try expectStatus(c.proto_ui_shim_read_geometry(&table, 1, &geometry), c.PROTO_UI_STATUS_CALLBACK_MISSING);
    table = host.table();
    table.context = null;
    try expectStatus(c.proto_ui_shim_read_frame_state(&table, 1, &state), c.PROTO_UI_STATUS_CALLBACK_MISSING);

    table = host.table();
    generation = 998;
    host.generation = 0;
    try expectStatus(c.proto_ui_shim_read_generation(&table, 1, &generation), c.PROTO_UI_STATUS_CALLBACK_FAILED);
    try std.testing.expectEqual(@as(c_ulonglong, 998), generation);
    host.generation = 46;

    host.geometry_result = 0;
    try expectStatus(c.proto_ui_shim_read_geometry(&table, 1, &geometry), c.PROTO_UI_STATUS_CALLBACK_FAILED);
    host.geometry_result = 1;

    host.frame_result = 2;
    try expectStatus(c.proto_ui_shim_read_frame_state(&table, 1, &state), c.PROTO_UI_STATUS_CALLBACK_FAILED);
    host.frame_result = 1;
}

const LegacyHostV1 = extern struct {
    abi_version: c_uint,
    size: usize,
    context: ?*anyopaque,
    read_generation: *const fn (?*anyopaque, c_ulonglong) callconv(.c) c_ulonglong,
    read_geometry: *const fn (?*anyopaque, c_ulonglong, [*c]c.ProtoUiGeometry) callconv(.c) u8,
};

test "legacy table succeeds reads but reports frame state unsupported" {
    var host = Host{ .generation = 47 };
    const legacy = LegacyHostV1{
        .abi_version = c.PROTO_UI_ABI_VERSION,
        .size = @sizeOf(LegacyHostV1),
        .context = &host,
        .read_generation = Host.readGeneration,
        .read_geometry = Host.readGeometry,
    };
    const table: *const c.ProtoUiHostV1 = @ptrCast(&legacy);
    var generation: c_ulonglong = 0;
    var geometry: c.ProtoUiGeometry = undefined;
    var state: c.ProtoUiFrameState = undefined;

    try expectStatus(c.PROTO_UI_STATUS_SUCCESS, c.proto_ui_shim_host_validate(table));
    try expectStatus(c.PROTO_UI_STATUS_SUCCESS, c.proto_ui_shim_read_generation(table, 1, &generation));
    try expectStatus(c.PROTO_UI_STATUS_SUCCESS, c.proto_ui_shim_read_geometry(table, 1, &geometry));
    try expectStatus(c.PROTO_UI_STATUS_FRAME_STATE_UNSUPPORTED, c.proto_ui_shim_read_frame_state(table, 1, &state));
    try std.testing.expectEqual(@as(u32, 1), host.generation_calls);
    try std.testing.expectEqual(@as(u32, 1), host.geometry_calls);
    try std.testing.expectEqual(@as(u32, 0), host.frame_calls);
}
