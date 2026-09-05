//! Adapter-first changed-path audit.
//!
//! With no arguments, performs a self-check of known classifications.  Each
//! command-line argument is treated as a changed repository path; any new
//! inherited C/H/ObjC edit fails the audit.

const std = @import("std");
const adapter = @import("adapter.zig");

pub fn main(minimal: std.process.Init.Minimal) !void {
    var args = try std.process.Args.Iterator.initAllocator(minimal.args, std.heap.smp_allocator);
    defer args.deinit();
    _ = args.next(); // program name

    var rejected: usize = 0;
    while (args.next()) |path| {
        const class = adapter.classifyPath(path);
        std.debug.print("{s}: {s}\n", .{ @tagName(class), path });
        if (adapter.isNewInheritedCoreEdit(path)) rejected += 1;
    }

    if (adapter.validateManifest() != null) {
        std.debug.print("boundary: manifest invalid\n", .{});
        std.process.exit(1);
    }
    if (rejected != 0) {
        std.debug.print("boundary: rejected {d} inherited-C edit(s)\n", .{rejected});
        std.process.exit(1);
    }
    std.debug.print("boundary: OK\n", .{});
}

test "boundary audit self-check rejects inherited C paths" {
    try std.testing.expect(adapter.isNewInheritedCoreEdit("oldXMenu/Activate.c"));
    try std.testing.expect(adapter.isNewInheritedCoreEdit("exec/exec.c"));
    try std.testing.expect(adapter.isNewInheritedCoreEdit("admin/alloc-colors.c"));
}
