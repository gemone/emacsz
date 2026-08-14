//! Native Zig replacement for the `chmod +x` install step: make the
//! installed emacs launcher executable (defense against filesystems or
//! checkouts that drop the committed +x bit). argv[1] is the target.

const std = @import("std");

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;

    var it = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer it.deinit();
    _ = it.next();
    const path = it.next() orelse return error.MissingPath;

    const z = try std.fmt.allocPrintSentinel(gpa, "{s}", .{path}, 0);
    defer gpa.free(z);
    // std.c.chmod is the POSIX chmod from the host libc, target-correct on
    // both Linux and macOS; std.os.linux.chmod would emit a Linux syscall
    // number on macOS, where the syscall ABI is different.
    if (std.c.chmod(z, 0o755) != 0) return error.ChmodFailed;
}
