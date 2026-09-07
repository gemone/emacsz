//! Fake-host conformance harness for the versioned Proto-UI adapter ABI.
//!
//! This binary has no GNU Emacs dependency.  It exercises the adapter state
//! machine and failure paths with a fake host that supplies only opaque IDs,
//! generations, and public geometry.

const std = @import("std");
const adapter = @import("adapter.zig");

const FakeHost = struct {
    generation: u64,

    fn init(generation: u64) FakeHost {
        return .{ .generation = generation };
    }

    fn table(self: *FakeHost) adapter.HostV1 {
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

    fn readGeometry(context: *anyopaque, object_id: u64, geometry: *adapter.Geometry) callconv(.c) u8 {
        _ = context;
        _ = object_id;
        geometry.* = .{ .x = 0, .y = 0, .width = 320, .height = 200 };
        return 1;
    }
};

const FrameStateHost = struct {
    generation: u64,
    visibility_byte: u8 = @intFromEnum(adapter.FrameVisibility.visible),
    focused_byte: u8 = 0,
    success: u8 = 1,
    callback_count: u64 = 0,
    reserved_byte: u8 = 0,

    fn table(self: *FrameStateHost) adapter.HostV1 {
        return .{
            .context = self,
            .read_generation = readGeneration,
            .read_geometry = readGeometry,
            .read_frame_state = readFrameState,
        };
    }

    fn readGeneration(context: *anyopaque, object_id: u64) callconv(.c) u64 {
        _ = object_id;
        const self: *FrameStateHost = @ptrCast(@alignCast(context));
        return self.generation;
    }

    fn readGeometry(context: *anyopaque, object_id: u64, geometry: *adapter.Geometry) callconv(.c) u8 {
        _ = context;
        _ = object_id;
        geometry.* = .{ .x = 0, .y = 0, .width = 320, .height = 200 };
        return 1;
    }

    fn readFrameState(context: *anyopaque, frame_id: u64, frame_state: *adapter.FrameState) callconv(.c) u8 {
        const self: *FrameStateHost = @ptrCast(@alignCast(context));
        self.callback_count += 1;
        if (self.success != 1) return self.success;
        frame_state.* = .{
            .generation = self.generation,
            .visibility = self.visibility_byte,
            .focused = self.focused_byte,
            .reserved = [_]u8{self.reserved_byte} ** 6,
        };
        _ = frame_id;
        return 1;
    }
};

fn readInvalidFocusedFrameState(
    context: *anyopaque,
    frame_id: u64,
    frame_state: *adapter.FrameState,
) callconv(.c) u8 {
    _ = context;
    _ = frame_id;
    frame_state.* = .{ .generation = 113, .visibility = 1, .focused = 2 };
    return 1;
}

fn captureComplete(runtime: *adapter.Runtime) !void {
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
    try runtime.captureDamage(.{ .x = 0, .y = 0, .width = 40, .height = 10 });
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var host = FakeHost.init(101);
    var table = host.table();
    var runtime = try adapter.Runtime.init(allocator, &table);
    defer runtime.deinit();

    try captureComplete(&runtime);
    const generation = try runtime.commit();
    if (generation != 101 or runtime.committed_updates != 1)
        return error.ConformanceCommitFailed;

    // Cursor records are optional, but the runtime must remember the latest.
    try captureComplete(&runtime);
    try runtime.captureCursor(.{
        .window_id = 20,
        .x = 2,
        .y = 0,
        .width = 2,
        .height = 10,
        .kind = 2,
        .visible = true,
        .active = true,
    });
    if (runtime.cursor == null or runtime.cursor.?.x != 2)
        return error.ConformanceCursorFailed;
    runtime.cancel();

    // ABI validation is fail closed.
    var bad_abi = host.table();
    bad_abi.abi_version = adapter.abi_version + 1;
    if (adapter.Runtime.init(allocator, &bad_abi)) |_| {
        return error.ConformanceAbiAccepted;
    } else |err| {
        if (err != adapter.Error.AbiMismatch) return err;
    }

    // A missing required callback is an ABI mismatch, not a crash.
    var missing_callback = host.table();
    missing_callback.read_generation = null;
    if (adapter.Runtime.init(allocator, &missing_callback)) |_| {
        return error.ConformanceNullCallbackAccepted;
    } else |err| {
        if (err != adapter.Error.AbiMismatch) return err;
    }

    // The generation observed at begin must remain stable through commit.
    var changed = FakeHost.init(101);
    var changed_table = changed.table();
    var changed_runtime = try adapter.Runtime.init(allocator, &changed_table);
    defer changed_runtime.deinit();
    try changed_runtime.begin(10);
    changed.generation = 102;
    if (changed_runtime.commit()) |_| {
        return error.ConformanceGenerationAccepted;
    } else |err| {
        if (err != adapter.Error.GenerationMismatch) return err;
        changed_runtime.cancel();
    }

    // A missing row, window, or damage record is partial and never commits.
    var partial = FakeHost.init(103);
    var partial_table = partial.table();
    var partial_runtime = try adapter.Runtime.init(allocator, &partial_table);
    defer partial_runtime.deinit();
    try partial_runtime.begin(10);
    if (partial_runtime.commit()) |_| {
        return error.ConformancePartialAccepted;
    } else |err| {
        if (err != adapter.Error.CapturePartial) return err;
    }
    partial_runtime.cancel();

    // Optional v1 frame state is available only when the supplied table size
    // actually covers the appended callback.
    const LegacyHostV1 = extern struct {
        abi_version: u32,
        size: usize,
        context: *anyopaque,
        read_generation: *const fn (*anyopaque, u64) callconv(.c) u64,
        read_geometry: *const fn (*anyopaque, u64, *adapter.Geometry) callconv(.c) u8,
    };

    var legacy_fake = FakeHost.init(107);
    var legacy_host = LegacyHostV1{
        .abi_version = adapter.abi_version,
        .size = @sizeOf(LegacyHostV1),
        .context = &legacy_fake,
        .read_generation = FakeHost.readGeneration,
        .read_geometry = FakeHost.readGeometry,
    };
    var legacy_runtime = try adapter.Runtime.init(allocator, @ptrCast(&legacy_host));
    defer legacy_runtime.deinit();
    try std.testing.expectError(adapter.Error.FrameStateUnsupported, legacy_runtime.observeFrameState(10));
    try captureComplete(&legacy_runtime);
    try std.testing.expectEqual(@as(u64, 107), try legacy_runtime.commit());

    inline for ([_]adapter.FrameVisibility{ .hidden, .visible, .iconified }) |visibility| {
        var state_host = FrameStateHost{
            .generation = 108,
            .visibility_byte = @intFromEnum(visibility),
            .focused_byte = @intFromBool(visibility == .visible),
        };
        var state_table = state_host.table();
        var state_runtime = try adapter.Runtime.init(allocator, &state_table);
        defer state_runtime.deinit();
        const observation = try state_runtime.observeFrameState(10);
        if (observation.visibility != visibility or observation.focused != (visibility == .visible))
            return error.ConformanceFrameStateFailed;
    }

    {
        var missing_state_host = FrameStateHost{ .generation = 109 };
        var missing_state_table = missing_state_host.table();
        missing_state_table.read_frame_state = null;
        var missing_state_runtime = try adapter.Runtime.init(allocator, &missing_state_table);
        defer missing_state_runtime.deinit();
        try std.testing.expectError(adapter.Error.FrameStateUnsupported, missing_state_runtime.observeFrameState(10));
    }

    {
        var failed_state_host = FrameStateHost{ .generation = 110, .success = 0 };
        var failed_state_table = failed_state_host.table();
        var failed_state_runtime = try adapter.Runtime.init(allocator, &failed_state_table);
        defer failed_state_runtime.deinit();
        try std.testing.expectError(adapter.Error.FrameStateFailed, failed_state_runtime.observeFrameState(10));
    }

    {
        var invalid_success_host = FrameStateHost{ .generation = 111, .success = 2 };
        var invalid_success_table = invalid_success_host.table();
        var invalid_success_runtime = try adapter.Runtime.init(allocator, &invalid_success_table);
        defer invalid_success_runtime.deinit();
        try std.testing.expectError(adapter.Error.FrameStateFailed, invalid_success_runtime.observeFrameState(10));
    }

    {
        var zero_generation_host = FrameStateHost{ .generation = 0 };
        var zero_generation_table = zero_generation_host.table();
        var zero_generation_runtime = try adapter.Runtime.init(allocator, &zero_generation_table);
        defer zero_generation_runtime.deinit();
        try std.testing.expectError(adapter.Error.GenerationMismatch, zero_generation_runtime.observeFrameState(10));
    }

    {
        var invalid_visibility_host = FrameStateHost{ .generation = 112, .visibility_byte = 3 };
        var invalid_visibility_table = invalid_visibility_host.table();
        var invalid_visibility_runtime = try adapter.Runtime.init(allocator, &invalid_visibility_table);
        defer invalid_visibility_runtime.deinit();
        try std.testing.expectError(adapter.Error.FrameStateInvalid, invalid_visibility_runtime.observeFrameState(10));
    }

    {
        var invalid_focus_host = FrameStateHost{ .generation = 113, .visibility_byte = 1, .focused_byte = 2 };
        var invalid_focus_table = invalid_focus_host.table();
        var invalid_focus_runtime = try adapter.Runtime.init(allocator, &invalid_focus_table);
        defer invalid_focus_runtime.deinit();
        invalid_focus_table.read_frame_state = readInvalidFocusedFrameState;
        try std.testing.expectError(adapter.Error.FrameStateInvalid, invalid_focus_runtime.observeFrameState(10));
    }

    {
        var reserved_host = FrameStateHost{ .generation = 114, .reserved_byte = 1 };
        var reserved_table = reserved_host.table();
        var reserved_runtime = try adapter.Runtime.init(allocator, &reserved_table);
        defer reserved_runtime.deinit();
        try std.testing.expectError(adapter.Error.FrameStateInvalid, reserved_runtime.observeFrameState(10));
    }

    std.debug.print("adapter ABI v{d}: fake-host conformance OK\n", .{adapter.abi_version});
}
