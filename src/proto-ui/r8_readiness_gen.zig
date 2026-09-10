//! Emits the machine-checkable R8 entry-readiness contract.

const std = @import("std");
const proto_ui = @import("proto_ui");

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    var args = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer args.deinit();
    _ = args.next();

    const output_path = args.next() orelse return error.MissingOutputArg;
    var runtime_linking = false;
    while (args.next()) |argument| {
        if (std.mem.eql(u8, argument, "--runtime-linking=true")) {
            runtime_linking = true;
        } else if (std.mem.eql(u8, argument, "--runtime-linking=false")) {
            runtime_linking = false;
        } else return error.UnknownGenArgument;
    }
    var manifest: std.ArrayList(u8) = .empty;
    defer manifest.deinit(gpa);
    try proto_ui.r8_readiness.writeLinkedManifest(gpa, &manifest, runtime_linking);
    try cwd.writeFile(io, .{ .sub_path = output_path, .data = manifest.items });
}
