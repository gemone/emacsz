//! Audits current runtime activation as blocked without linkage or registration.

const std = @import("std");
const proto_ui = @import("proto_ui");

fn emitBlocked() void {
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-runtime-activation\",\"selection\":\"selected\",\"activation\":\"blocked_by_linkage_or_registration\",\"allowed\":false,\"registered\":false,\"runtime_available\":false,\"reason\":\"{s}\",\"result\":\"pass\"}}\n",
        .{proto_ui.host_adapter.linkage_missing_reason_code},
    );
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    var args = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer args.deinit();
    _ = args.next();

    const manifest_path = args.next() orelse return error.MissingManifestArg;
    const actual = try cwd.readFileAlloc(io, manifest_path, gpa, .limited(64 * 1024));
    defer gpa.free(actual);

    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(gpa);
    try proto_ui.runtime_activation.writeManifest(gpa, &expected);
    if (!std.mem.eql(u8, actual, expected.items)) {
        emitBlocked();
        std.debug.print("runtime-activation gate: artifact mismatch\n", .{});
        return error.InvalidRuntimeActivationArtifact;
    }
    if (proto_ui.runtime_activation.validateState()) |problem| {
        emitBlocked();
        std.debug.print("runtime-activation gate: {s}\n", .{problem});
        return error.InvalidRuntimeActivationState;
    }
    emitBlocked();
}
