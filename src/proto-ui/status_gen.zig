//! Emits the machine-checkable Proto-UI capability status manifest. The
//! authoritative entries live beside the negotiation policy, not in this tool.

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
    var manifest: std.ArrayList(u8) = .empty;
    defer manifest.deinit(gpa);
    try proto_ui.capability.writeStatusManifest(gpa, &manifest);
    try cwd.writeFile(io, .{ .sub_path = output_path, .data = manifest.items });
}
