//! Native Zig replacement for the compile-lisp shell script in
//! build.zig: byte-compile the whole lisp tree with the bootstrap dump
//! (mirrors lisp/Makefile.in's compile-main). No shell; the pdumper
//! relocation flake is retried on signal death. Run with cwd = repo root.

const std = @import("std");
const aslr = @import("aslr.zig");
const env = @import("env.zig");
const stamp = @import("stamp.zig");

pub fn main(minimal: std.process.Init.Minimal) !void {
    aslr.disableAslr();
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

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

    // Freshness stamp: byte-recompile-directory compiles every .el whose
    // .elc is missing or older, so the inputs are the .el tree (plus the
    // dumped emacs that runs the compiler) and the outputs are the .elc
    // files.  When the stamp matches and every recorded .elc survives,
    // skip the emacs invocation entirely (byte-recompile itself would be
    // a no-op anyway; this just saves the startup + tree walk).
    {
        var f = freshFinger(io, gpa, cwd, temacs, dump);
        if (stamp.isFresh(io, gpa, cwd, stampName, f.final())) {
            std.debug.print("compile-lisp: .elc tree up to date (stamp); skipping\n", .{});
            return;
        }
    }

    var env_map = try env.inherit(gpa, minimal);
    defer env_map.deinit();
    try env_map.put("EMACSLOADPATH", lisp_path);
    try env_map.put("EMACSDATA", etc_path);
    try env_map.put("LC_ALL", "C");
    // Build tooling wants deterministic interpreter behavior: the JIT
    // gate stays OFF for the byte-compile pass (mirrors the run-check
    // contract; the zeln-jit engine is for interactive runtimes).
    try env_map.put("ZELN_JIT", "0");

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
                if (code == 0) break;
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

    // Record the post-run fingerprint + the .elc outputs (any missing
    // .elc forces a re-run; the emacs side would recompile just it).
    var f = freshFinger(io, gpa, cwd, temacs, dump);
    const outputs = try collectElc(io, gpa, cwd);
    defer {
        for (outputs) |o| gpa.free(o);
        gpa.free(outputs);
    }
    stamp.mark(io, gpa, cwd, stampName, f.final(), outputs);
}

const stampName = "compile-lisp.stamp";

fn freshFinger(io: std.Io, gpa: std.mem.Allocator, cwd: std.Io.Dir, temacs: []const u8, dump: []const u8) stamp.Finger {
    var f = stamp.Finger.init("compile-lisp");
    // Content, not mtime: bootstrap staging and install steps may rewrite
    // identical binaries/images on every invocation.
    f.fileContent(io, cwd, gpa, temacs);
    f.fileContent(io, cwd, gpa, dump);
    f.file(io, cwd, "build-aux/compile-lisp.zig");
    // .elc are this tool's OUTPUTS (excluded); loaddefs outputs are
    // compile-time inputs and stay fingerprinted.
    f.tree(io, gpa, cwd, "lisp", isElc) catch {};
    return f;
}

fn isElc(rel: []const u8) bool {
    if (std.mem.endsWith(u8, rel, "~")) return true; // emacs backup files
    return std.mem.endsWith(u8, rel, ".elc") or std.mem.endsWith(u8, rel, ".elc.gz");
}

/// Every .elc under lisp/, sorted (the deterministic output list).
fn collectElc(io: std.Io, gpa: std.mem.Allocator, cwd: std.Io.Dir) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (out.items) |o| gpa.free(o);
        out.deinit(gpa);
    }
    var lisp = try cwd.openDir(io, "lisp", .{ .iterate = true });
    defer lisp.close(io);
    var w = try lisp.walk(gpa);
    defer w.deinit();
    while (w.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!isElc(entry.path)) continue;
        const full = try std.fs.path.join(gpa, &.{ "lisp", entry.path });
        try out.append(gpa, full);
    }
    std.mem.sort([]const u8, out.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return out.toOwnedSlice(gpa);
}
