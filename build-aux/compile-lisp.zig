//! Native Zig replacement for the compile-lisp shell script in
//! build.zig: byte-compile the whole lisp tree with the bootstrap dump
//! (mirrors lisp/Makefile.in's compile-main). No shell; the pdumper
//! relocation flake is retried on signal death. Run with cwd = repo root.

const std = @import("std");
const aslr = @import("aslr.zig");
const env = @import("env.zig");

pub fn main(minimal: std.process.Init.Minimal) !void {
    aslr.disableAslr();
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();

    const root = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(root);
    const lisp_path = try std.fs.path.join(gpa, &.{ root, "lisp" });
    defer gpa.free(lisp_path);
    const temacs_path = @import("temacs-path.zig");
    const temacs = try temacs_path.joinBin(gpa, root);
    defer gpa.free(temacs);
    const dump = try std.fs.path.join(gpa, &.{ root, "zig-out", "bin", "bootstrap-emacs.pdmp" });
    defer gpa.free(dump);
    const etc_path = try std.fs.path.join(gpa, &.{ root, "etc" });
    defer gpa.free(etc_path);

    var env_map = try env.inherit(gpa, minimal);
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
    // Lisp strings treat '\' as an escape ("D:\a\..." reads as
    // "D:<bell>..."), so use forward slashes in the eval forms.
    const charprop_flat = try std.mem.replaceOwned(u8, gpa, charprop, "\\", "/");
    defer gpa.free(charprop_flat);
    const lisp_path_flat = try std.mem.replaceOwned(u8, gpa, lisp_path, "\\", "/");
    defer gpa.free(lisp_path_flat);
    const diary_target = try std.fmt.allocPrint(gpa, "{s}/calendar/diary-icalendar.el", .{lisp_path_flat});
    defer gpa.free(diary_target);
    // TEMPORARY diagnostic (remove after the windows diary-icalendar
    // abort is identified): when ZIG_COMPILE_LISP_PROBE is set, run a
    // stepwise load/compile of diary-icalendar.el instead of the full
    // tree so the last P-marker before a crash pinpoints the abort.
    const probe_enabled = if (env_map.get("ZIG_COMPILE_LISP_PROBE")) |v|
        std.mem.eql(u8, v, "1")
    else
        false;
    const eval = if (probe_enabled)
        try std.fmt.allocPrint(gpa,
            \\(progn (load "cl-macs") (load "cl-seq") (load "cl-extra") (load "{s}")
            \\ (message "P0 env HOME=%S SHELL=%S TEMP=%S" (getenv "HOME") (getenv "SHELL") (getenv "TEMP"))
            \\ (message "P0b user-real-login-name=%S" (user-real-login-name))
            \\ (message "P1 load icalendar") (load "calendar/icalendar")
            \\ (message "P2 load icalendar-parser") (load "calendar/icalendar-parser")
            \\ (message "P3 load icalendar-utils") (load "calendar/icalendar-utils")
            \\ (message "P4 load icalendar-recur") (load "calendar/icalendar-recur")
            \\ (message "P5 load icalendar-ast") (load "calendar/icalendar-ast")
            \\ (message "P6 load org-element-ast") (load "org/org-element-ast")
            \\ (message "P7 load diary-icalendar") (load "calendar/diary-icalendar")
            \\ (message "P8 byte-compile diary-icalendar") (byte-compile-file "{s}")
            \\ (message "P9 done"))
        , .{ charprop_flat, diary_target })
    else
        try std.fmt.allocPrint(gpa, "(progn (load \"cl-macs\") (load \"cl-seq\") (load \"cl-extra\") (load \"{s}\") (byte-recompile-directory \"{s}\" 0))", .{ charprop_flat, lisp_path_flat });
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
