//! Native Zig replacement for the compile-lisp shell script in
//! build.zig: byte-compile the whole lisp tree with the bootstrap dump
//! (mirrors lisp/Makefile.in's compile-main). No shell; the pdumper
//! relocation flake is retried on signal death. Run with cwd = repo root.

const std = @import("std");
const aslr = @import("aslr.zig");

pub fn main() !void {
    aslr.disableAslr();
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();

    const root = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(root);
    const lisp_path = try std.fs.path.join(gpa, &.{ root, "lisp" });
    defer gpa.free(lisp_path);
    const temacs = try std.fs.path.join(gpa, &.{ root, "zig-out", "bin", "temacs" });
    defer gpa.free(temacs);
    const dump = try std.fs.path.join(gpa, &.{ root, "zig-out", "bin", "bootstrap-emacs.pdmp" });
    defer gpa.free(dump);
    const etc_path = try std.fs.path.join(gpa, &.{ root, "etc" });
    defer gpa.free(etc_path);

    var env_map = std.process.Environ.Map.init(gpa);
    defer env_map.deinit();
    try env_map.put("EMACSLOADPATH", lisp_path);
    try env_map.put("EMACSDATA", etc_path);
    try env_map.put("LC_ALL", "C");

    const charprop = try std.fs.path.join(gpa, &.{ lisp_path, "international", "charprop" });
    defer gpa.free(charprop);
    // char-fold.el builds its tables from the Unicode property data at
    // compile time, so charprop must be loaded in the compile session
    // (the source dump does not bundle it; loadup only tolerates its
    // absence). A clean checkout has no stale .elc to hide the need.
    const eval = try std.fmt.allocPrint(gpa, "(progn (load \"cl-macs\") (load \"cl-seq\") (load \"cl-extra\") (load \"{s}\") (byte-recompile-directory \"{s}\" 0))", .{ charprop, lisp_path });
    defer gpa.free(eval);
    const dump_arg = try std.fmt.allocPrint(gpa, "--dump-file={s}", .{dump});
    defer gpa.free(dump_arg);

    const argv = [_][]const u8{ temacs, "--batch", "-L", lisp_path, dump_arg, "--eval", eval };
    var attempt: usize = 0;
    while (true) : (attempt += 1) {
        var child = try std.process.spawn(io, .{
            .argv = &argv,
            .cwd = .{ .path = root },
            .environ_map = &env_map,
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        });
        const term = try child.wait(io);
        switch (term) {
            .exited => |code| {
                if (code == 0) return;
                std.debug.print("compile-lisp: temacs exited {d}\n", .{code});
                std.process.exit(1);
            },
            .signal => |sig| {
                std.debug.print("compile-lisp: temacs died with signal {d}; retrying ({d}/3)\n", .{ @intFromEnum(sig), attempt + 1 });
                if (attempt >= 2) std.process.exit(1);
            },
            else => std.process.exit(1),
        }
    }
}
