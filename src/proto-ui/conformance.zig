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

    std.debug.print("adapter ABI v{d}: fake-host conformance OK\n", .{adapter.abi_version});
}
