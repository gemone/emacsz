//! Audits the PureRuntimeHostV1 ABI manifest and keeps runtime fail closed.

const std = @import("std");
const proto_ui = @import("proto_ui");

fn emitPrepared() void {
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-runtime-host\",\"abi_version\":1,\"registered\":false,\"runtime_available\":false,\"decision\":\"pending\",\"reason\":\"host_registration_contract_missing\"}}\n",
        .{},
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
    try proto_ui.runtime_host.writeManifest(gpa, &expected);
    if (!std.mem.eql(u8, actual, expected.items)) {
        emitPrepared();
        std.debug.print("runtime-host gate: manifest mismatch\n", .{});
        return error.InvalidRuntimeHostManifest;
    }
    emitPrepared();
}
