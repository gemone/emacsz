//! Emits the C projection and conformance source for PureRuntimeHostV1.

const std = @import("std");
const abi = @import("runtime_host_abi.zig");

pub fn main(minimal: std.process.Init.Minimal) !void {
    var io_threaded: std.Io.Threaded = .init(std.heap.smp_allocator, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    var args = try std.process.Args.Iterator.initAllocator(minimal.args, std.heap.smp_allocator);
    defer args.deinit();
    _ = args.next();

    const header_path = args.next() orelse return error.MissingHeaderArg;
    const conformance_path = args.next() orelse return error.MissingConformanceArg;
    const manifest_path = args.next() orelse return error.MissingManifestArg;

    try cwd.writeFile(io, .{ .sub_path = header_path, .data = abi.header });
    try cwd.writeFile(io, .{ .sub_path = conformance_path, .data = abi.conformance });
    try cwd.writeFile(io, .{ .sub_path = manifest_path, .data = abi.manifest });
}
