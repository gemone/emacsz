//! Tracked dynamic-loader conformance harness for the generated Proto-UI shim.
//!
//! The build graph supplies the exact shared-library artifact as argv[1].  The
//! harness dlopen/dlsym/dlcloses that artifact, validates the five ABI entry
//! points through loaded function pointers, and proves non-ABI implementation
//! names are not exported.  It owns no Emacs state, terminal registration, EUP
//! encoding, or transport.

const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("abi_v1.h");
});

const AbiVersionFn = *const fn () callconv(.c) u8;
const HostValidateFn = *const fn (?*const c.ProtoUiHostV1) callconv(.c) u8;
const ReadGenerationFn = *const fn (?*const c.ProtoUiHostV1, c_ulonglong, ?*c_ulonglong) callconv(.c) u8;
const ReadGeometryFn = *const fn (?*const c.ProtoUiHostV1, c_ulonglong, ?*c.ProtoUiGeometry) callconv(.c) u8;
const ReadFrameStateFn = *const fn (?*const c.ProtoUiHostV1, c_ulonglong, ?*c.ProtoUiFrameState) callconv(.c) u8;

const Host = struct {
    generation: c_ulonglong,
    frame_generation: c_ulonglong = 0x0102030405060708,
    geometry_result: u8 = 1,
    frame_result: u8 = 1,
    generation_calls: u32 = 0,
    geometry_calls: u32 = 0,
    frame_calls: u32 = 0,

    fn fullTable(self: *Host) c.ProtoUiHostV1 {
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
        geometry.* = .{ .x = 12, .y = 34, .width = 640, .height = 400 };
        return self.geometry_result;
    }

    fn readFrameState(context: ?*anyopaque, frame_id: c_ulonglong, state: [*c]c.ProtoUiFrameState) callconv(.c) u8 {
        _ = frame_id;
        const self: *Host = @ptrCast(@alignCast(context.?));
        self.frame_calls += 1;
        state.* = .{
            .generation = self.frame_generation,
            .visibility = c.PROTO_UI_FRAME_STATE_VISIBLE,
            .focused = 1,
            .reserved = [_]u8{0} ** 6,
        };
        return self.frame_result;
    }
};

const LegacyHostV1 = extern struct {
    abi_version: c_uint,
    size: usize,
    context: ?*anyopaque,
    read_generation: *const fn (?*anyopaque, c_ulonglong) callconv(.c) c_ulonglong,
    read_geometry: *const fn (?*anyopaque, c_ulonglong, [*c]c.ProtoUiGeometry) callconv(.c) u8,
};

const Functions = struct {
    abi_version: AbiVersionFn,
    host_validate: HostValidateFn,
    read_generation: ReadGenerationFn,
    read_geometry: ReadGeometryFn,
    read_frame_state: ReadFrameStateFn,
};

fn requireLookup(library: *std.DynLib, comptime T: type, name: [:0]const u8) !T {
    return library.lookup(T, name) orelse {
        std.debug.print("shim-library-conformance: missing required symbol {s}\n", .{name});
        return error.MissingRequiredSymbol;
    };
}

fn requireMissing(library: *std.DynLib, name: [:0]const u8) !void {
    const value = library.lookup(*const anyopaque, name);
    if (value != null) {
        std.debug.print("shim-library-conformance: forbidden symbol exported: {s}\n", .{name});
        return error.ForbiddenSymbolExported;
    }
}

fn expectStatus(actual: u8, expected: u8) !void {
    if (actual != expected) return error.ShimLibraryConformanceStatusMismatch;
}

fn validateLoadedAbi(library: *std.DynLib) !Functions {
    const functions = Functions{
        .abi_version = try requireLookup(library, AbiVersionFn, "proto_ui_shim_abi_version"),
        .host_validate = try requireLookup(library, HostValidateFn, "proto_ui_shim_host_validate"),
        .read_generation = try requireLookup(library, ReadGenerationFn, "proto_ui_shim_read_generation"),
        .read_geometry = try requireLookup(library, ReadGeometryFn, "proto_ui_shim_read_geometry"),
        .read_frame_state = try requireLookup(library, ReadFrameStateFn, "proto_ui_shim_read_frame_state"),
    };

    try std.testing.expectEqual(@as(u8, c.PROTO_UI_ABI_VERSION), functions.abi_version());
    return functions;
}

fn validateSymbolIsolation(library: *std.DynLib) !void {
    const forbidden = [_][:0]const u8{
        "proto_ui_host_validate_v1",
        "main",
        "proto_ui_terminal_register",
        "proto_ui_terminal_create",
        "proto_ui_frame_register",
        "proto_ui_frame_create",
        "proto_ui_eup_encode",
        "proto_ui_encode_eup",
        "output_proto_register",
        "proto_ui_transport_start",
    };
    for (forbidden) |name| try requireMissing(library, name);
}

fn validateSuccessDelegation(functions: *const Functions) !void {
    var host = Host{ .generation = 7351 };
    const table = host.fullTable();
    var generation: c_ulonglong = 999;
    var geometry = c.ProtoUiGeometry{ .x = -1, .y = -2, .width = -3, .height = -4 };
    var state = c.ProtoUiFrameState{
        .generation = 0xdeadbeefdeadbeef,
        .visibility = c.PROTO_UI_FRAME_STATE_HIDDEN,
        .focused = 0,
        .reserved = [_]u8{0xaa} ** 6,
    };

    try expectStatus(functions.host_validate(&table), c.PROTO_UI_STATUS_SUCCESS);
    try expectStatus(functions.read_generation(&table, 101, &generation), c.PROTO_UI_STATUS_SUCCESS);
    try std.testing.expectEqual(@as(c_ulonglong, 7351), generation);
    try expectStatus(functions.read_geometry(&table, 202, &geometry), c.PROTO_UI_STATUS_SUCCESS);
    try std.testing.expectEqual(@as(c_int, 12), geometry.x);
    try std.testing.expectEqual(@as(c_int, 34), geometry.y);
    try std.testing.expectEqual(@as(c_int, 640), geometry.width);
    try std.testing.expectEqual(@as(c_int, 400), geometry.height);
    try expectStatus(functions.read_frame_state(&table, 303, &state), c.PROTO_UI_STATUS_SUCCESS);
    try std.testing.expectEqual(@as(c_ulonglong, 0x0102030405060708), state.generation);
    try std.testing.expectEqual(@as(u8, c.PROTO_UI_FRAME_STATE_VISIBLE), state.visibility);
    try std.testing.expectEqual(@as(u8, 1), state.focused);

    try std.testing.expectEqual(@as(u32, 1), host.generation_calls);
    try std.testing.expectEqual(@as(u32, 1), host.geometry_calls);
    try std.testing.expectEqual(@as(u32, 1), host.frame_calls);
}

fn validateFailClosedPaths(functions: *const Functions) !void {
    var host = Host{ .generation = 8192 };
    var table = host.fullTable();
    var generation: c_ulonglong = 123;
    var geometry = c.ProtoUiGeometry{ .x = 0, .y = 0, .width = 0, .height = 0 };
    var state = c.ProtoUiFrameState{
        .generation = 77,
        .visibility = c.PROTO_UI_FRAME_STATE_HIDDEN,
        .focused = 0,
        .reserved = [_]u8{0} ** 6,
    };

    try expectStatus(functions.host_validate(null), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try expectStatus(functions.read_generation(null, 1, &generation), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try expectStatus(functions.read_geometry(null, 1, &geometry), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try expectStatus(functions.read_frame_state(null, 1, &state), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try expectStatus(functions.read_generation(&table, 1, null), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try expectStatus(functions.read_geometry(&table, 1, null), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try expectStatus(functions.read_frame_state(&table, 1, null), c.PROTO_UI_STATUS_INVALID_ARGUMENT);
    try std.testing.expectEqual(@as(u32, 0), host.generation_calls);
    try std.testing.expectEqual(@as(u32, 0), host.geometry_calls);
    try std.testing.expectEqual(@as(u32, 0), host.frame_calls);

    table.abi_version += 1;
    try expectStatus(functions.host_validate(&table), c.PROTO_UI_STATUS_ABI_MISMATCH);
    table = host.fullTable();
    table.size = 1;
    try expectStatus(functions.read_geometry(&table, 1, undefined), c.PROTO_UI_STATUS_ABI_MISMATCH);
    table = host.fullTable();
    table.size = @sizeOf(c.ProtoUiHostV1) - 1;
    try expectStatus(functions.host_validate(&table), c.PROTO_UI_STATUS_ABI_MISMATCH);

    table = host.fullTable();
    table.read_generation = null;
    try expectStatus(functions.read_generation(&table, 1, &generation), c.PROTO_UI_STATUS_CALLBACK_MISSING);
    table = host.fullTable();
    table.read_geometry = null;
    try expectStatus(functions.read_geometry(&table, 1, &geometry), c.PROTO_UI_STATUS_CALLBACK_MISSING);
    table = host.fullTable();
    table.context = null;
    try expectStatus(functions.read_frame_state(&table, 1, &state), c.PROTO_UI_STATUS_CALLBACK_MISSING);

    table = host.fullTable();
    host.generation = 0;
    try expectStatus(functions.read_generation(&table, 1, &generation), c.PROTO_UI_STATUS_CALLBACK_FAILED);
    try std.testing.expectEqual(@as(c_ulonglong, 123), generation);
    host.generation = 8192;
    host.geometry_result = 0;
    geometry.x = -9;
    try expectStatus(functions.read_geometry(&table, 1, &geometry), c.PROTO_UI_STATUS_CALLBACK_FAILED);
    try std.testing.expectEqual(@as(c_int, -9), geometry.x);
    host.geometry_result = 1;
    host.frame_result = 2;
    state.generation = 88;
    try expectStatus(functions.read_frame_state(&table, 1, &state), c.PROTO_UI_STATUS_CALLBACK_FAILED);
    try std.testing.expectEqual(@as(c_ulonglong, 88), state.generation);
    host.frame_result = 1;

    const legacy = LegacyHostV1{
        .abi_version = c.PROTO_UI_ABI_VERSION,
        .size = @sizeOf(LegacyHostV1),
        .context = &host,
        .read_generation = Host.readGeneration,
        .read_geometry = Host.readGeometry,
    };
    const legacy_table: *const c.ProtoUiHostV1 = @ptrCast(&legacy);
    try expectStatus(functions.host_validate(legacy_table), c.PROTO_UI_STATUS_SUCCESS);
    try expectStatus(functions.read_generation(legacy_table, 1, &generation), c.PROTO_UI_STATUS_SUCCESS);
    try expectStatus(functions.read_geometry(legacy_table, 1, &geometry), c.PROTO_UI_STATUS_SUCCESS);
    try expectStatus(functions.read_frame_state(legacy_table, 1, &state), c.PROTO_UI_STATUS_FRAME_STATE_UNSUPPORTED);
    try std.testing.expectEqual(@as(u32, 1), host.frame_calls);
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    if (builtin.os.tag == .windows) {
        std.debug.print("shim-library-conformance: SKIPPED (Windows loader path not required yet)\n", .{});
        return;
    }

    var args = try std.process.Args.Iterator.initAllocator(minimal.args, std.heap.smp_allocator);
    defer args.deinit();
    _ = args.next();
    const library_path = args.next() orelse return error.MissingLibraryPathArg;
    if (args.next() != null) return error.UnexpectedExtraArguments;

    var library = try std.DynLib.open(library_path);
    defer library.close();

    const functions = try validateLoadedAbi(&library);
    try validateSymbolIsolation(&library);
    try validateSuccessDelegation(&functions);
    try validateFailClosedPaths(&functions);
    std.debug.print("shim-library-conformance: OK ({s})\n", .{library_path});
}
