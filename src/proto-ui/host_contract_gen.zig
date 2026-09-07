//! Emits the machine-checkable host registration decision contract.

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
    var contract: std.ArrayList(u8) = .empty;
    defer contract.deinit(gpa);
    try proto_ui.host_contract.writeContract(gpa, &contract);
    try cwd.writeFile(io, .{ .sub_path = output_path, .data = contract.items });
}
