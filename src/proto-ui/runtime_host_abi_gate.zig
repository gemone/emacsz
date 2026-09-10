//! Audits the generated C projection manifest for PureRuntimeHostV1.

const std = @import("std");
const abi = @import("runtime_host_abi.zig");

pub fn main(minimal: std.process.Init.Minimal) !void {
    var io_threaded: std.Io.Threaded = .init(std.heap.smp_allocator, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();
    const gpa = std.heap.smp_allocator;

    var args = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer args.deinit();
    _ = args.next();

    const manifest_path = args.next() orelse return error.MissingManifestArg;
    const actual = try cwd.readFileAlloc(io, manifest_path, gpa, .limited(64 * 1024));
    defer gpa.free(actual);
    if (!std.mem.eql(u8, actual, abi.manifest)) return error.InvalidRuntimeHostAbiManifest;
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-runtime-host-abi\",\"abi_version\":1,\"registered\":false,\"runtime_available\":false,\"decision\":\"approved\",\"reason\":\"runtime_host_linkage_or_registration_missing\"}}\n",
        .{},
    );
}
