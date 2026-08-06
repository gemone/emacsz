//! Native Zig replacement for build-aux/generate-loaddefs.sh: generate
//! lisp/loaddefs.el + per-subdir *-loaddefs.el (autoload cookies),
//! cus-load.el and finder-inf.el via the dumped emacs, with no shell.
//! Mirrors lisp/Makefile.in's autoloads / custom-deps / finder-data
//! targets: the same SUBDIRS_ALMOST / SUBDIRS_FINDER directory lists
//! (every lisp/ directory except the exact obsolete/ and term/; the
//! finder pass also drops leim*), loaddefs.el deleted first for a FULL
//! regeneration, and the same emacs invocations. Run with cwd = repo
//! root. The pdumper relocation flake is retried on signal death, like
//! the check step does (setarch -R is not available without a shell).

const std = @import("std");
const aslr = @import("aslr.zig");

pub fn main() !void {
    aslr.disableAslr();
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    const root = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(root);
    const lisp_path = try std.fs.path.join(gpa, &.{ root, "lisp" });
    defer gpa.free(lisp_path);
    const temacs = try std.fs.path.join(gpa, &.{ root, "zig-out", "bin", "temacs" });
    defer gpa.free(temacs);
    const dump = try std.fs.path.join(gpa, &.{ root, "zig-out", "bin", "bootstrap-emacs.pdmp" });
    defer gpa.free(dump);

    const subdirs = try collectDirs(io, gpa, cwd, false);
    defer gpa.free(subdirs);
    const finder_dirs = try collectDirs(io, gpa, cwd, true);
    defer gpa.free(finder_dirs);

    // Force a FULL regeneration: with an existing loaddefs.el the
    // generator runs in "updating" mode and silently skips every source
    // file older than it (mirroring lisp/Makefile.in's autoloads-force).
    const loaddefs = try std.fs.path.join(gpa, &.{ lisp_path, "loaddefs.el" });
    defer gpa.free(loaddefs);
    std.Io.Dir.deleteFileAbsolute(io, loaddefs) catch {};

    const charprop = try std.fs.path.join(gpa, &.{ lisp_path, "international", "charprop" });
    defer gpa.free(charprop);
    // The autoload scrape loads files (e.g. tramp-adb) that require the
    // Unicode property data; the source dump does not bundle charprop,
    // so load it explicitly (a clean checkout has no stale tables).
    const charprop_eval = try std.fmt.allocPrint(gpa, "(load \"{s}\")", .{charprop});
    defer gpa.free(charprop_eval);
    try runEmacs(io, gpa, temacs, dump, lisp_path, &.{
        "--eval", charprop_eval,
        "-l", "emacs-lisp/loaddefs-gen.el",
        "-f", "loaddefs-generate--emacs-batch",
    }, subdirs);

    const cus_eval = try std.fmt.allocPrint(gpa, "(setq generated-custom-dependencies-file \"{s}/cus-load.el\")", .{lisp_path});
    defer gpa.free(cus_eval);
    try runEmacs(io, gpa, temacs, dump, lisp_path, &.{
        "-l", "cus-dep",
        "--eval", cus_eval,
        "-f", "custom-make-dependencies",
    }, subdirs);

    const finder_eval = try std.fmt.allocPrint(gpa, "(setq generated-finder-keywords-file \"{s}/finder-inf.el\")", .{lisp_path});
    defer gpa.free(finder_eval);
    try runEmacs(io, gpa, temacs, dump, lisp_path, &.{
        "-l", "finder",
        "--eval", finder_eval,
        "-f", "finder-compile-keywords-make-dist",
    }, finder_dirs);
}

/// The SUBDIRS_ALMOST / SUBDIRS_FINDER list: every directory under lisp/
/// ("./"-prefixed, sorted), excluding the exact obsolete/ and term/
/// dirs; for finder also drop leim* (the shell's `-path './leim*'`).
fn collectDirs(io: std.Io, gpa: std.mem.Allocator, cwd: std.Io.Dir, for_finder: bool) ![]u8 {
    var lisp = try cwd.openDir(io, "lisp", .{ .iterate = true });
    defer lisp.close(io);

    var dirs: std.ArrayList([]const u8) = .empty;
    defer {
        for (dirs.items) |d| gpa.free(d);
        dirs.deinit(gpa);
    }
    try dirs.append(gpa, try gpa.dupe(u8, "."));

    var w = try lisp.walk(gpa);
    defer w.deinit();
    while (try w.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        const rel = entry.path;
        if (std.mem.eql(u8, rel, "obsolete") or std.mem.eql(u8, rel, "term"))
            continue;
        if (for_finder and std.mem.startsWith(u8, rel, "leim"))
            continue;
        const dotted = try std.fmt.allocPrint(gpa, "./{s}", .{rel});
        try dirs.append(gpa, dotted);
    }

    std.mem.sort([]const u8, dirs.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return std.mem.join(gpa, " ", dirs.items);
}

/// Run one dumped-emacs batch invocation with the given fixed args and
/// the trailing SUBDIRS list; retry on signal death (pdumper relocation
/// flakiness, like the check step).
fn runEmacs(
    io: std.Io,
    gpa: std.mem.Allocator,
    temacs: []const u8,
    dump: []const u8,
    lisp_path: []const u8,
    fixed: []const []const u8,
    dirs: []const u8,
) !void {
    const dump_arg = try std.fmt.allocPrint(gpa, "--dump-file={s}", .{dump});
    defer gpa.free(dump_arg);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.append(gpa, temacs);
    try argv.append(gpa, "--batch");
    try argv.append(gpa, "-L");
    try argv.append(gpa, ".");
    try argv.append(gpa, dump_arg);
    try argv.appendSlice(gpa, fixed);
    var it = std.mem.tokenizeScalar(u8, dirs, ' ');
    while (it.next()) |d| try argv.append(gpa, d);

    var attempt: usize = 0;
    while (true) : (attempt += 1) {
        var child = try std.process.spawn(io, .{
            .argv = argv.items,
            .cwd = .{ .path = lisp_path },
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        });
        const term = try child.wait(io);
        switch (term) {
            .exited => |code| {
                if (code == 0) return;
                std.debug.print("generate-loaddefs: temacs exited {d}\n", .{code});
                std.process.exit(1);
            },
            .signal => |sig| {
                std.debug.print("generate-loaddefs: temacs died with signal {d}; retrying ({d}/3)\n", .{ @intFromEnum(sig), attempt + 1 });
                if (attempt >= 2) std.process.exit(1);
            },
            else => std.process.exit(1),
        }
    }
}
