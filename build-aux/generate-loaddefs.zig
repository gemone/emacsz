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
const env = @import("env.zig");
const stamp = @import("stamp.zig");
const temacs_path = @import("temacs-path.zig");

pub fn main(minimal: std.process.Init.Minimal) !void {
    aslr.disableAslr();
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();
    var env_map = try env.inherit(gpa, minimal);
    defer env_map.deinit();

    const root = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(root);
    const lisp_path = try std.fs.path.join(gpa, &.{ root, "lisp" });
    defer gpa.free(lisp_path);
    const temacs = try temacs_path.joinBin(gpa, root);
    defer gpa.free(temacs);
    const dump = try std.fs.path.join(gpa, &.{ root, "zig-out", "bin", "bootstrap-emacs.pdmp" });
    defer gpa.free(dump);

    // Freshness stamp: the scrape reads every .el/.elc under lisp/ (the
    // generator loads files through `load', which prefers .elc) with the
    // dumped emacs, so its inputs are the lisp tree (minus this tool's
    // own outputs), the temacs binary and the pdmp it runs.  When the
    // stamp matches and every recorded output still exists, skip the
    // three emacs invocations entirely (the Run step re-executes on
    // every `zig build`; see stamp.zig).
    if (try upToDate(io, gpa, cwd, temacs, dump)) {
        std.debug.print("generate-loaddefs: up to date (stamp); skipping scrape\n", .{});
        return;
    }

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
    // Lisp strings treat '\' as an escape ("D:\a\..." reads as
    // "D:<bell>..."), so use forward slashes in the eval forms.
    const lisp_path_flat = try std.mem.replaceOwned(u8, gpa, lisp_path, "\\", "/");
    defer gpa.free(lisp_path_flat);
    const charprop_flat = try std.mem.replaceOwned(u8, gpa, charprop, "\\", "/");
    defer gpa.free(charprop_flat);
    // The autoload scrape loads files (e.g. tramp-adb) that require the
    // Unicode property data; the source dump does not bundle charprop,
    // so load it explicitly (a clean checkout has no stale tables).
    const charprop_eval = try std.fmt.allocPrint(gpa, "(load \"{s}\")", .{charprop_flat});
    defer gpa.free(charprop_eval);
    try runEmacs(io, gpa, &env_map, temacs, dump, lisp_path, &.{
        "--eval", charprop_eval,
        "--eval", "(setq make-backup-files nil create-lockfiles nil write-region-inhibit-fsync t)",
        "-l", "emacs-lisp/loaddefs-gen.el",
        "-f", "loaddefs-generate--emacs-batch",
    }, subdirs);

    const cus_eval = try std.fmt.allocPrint(gpa, "(setq generated-custom-dependencies-file \"{s}/cus-load.el\")", .{lisp_path_flat});
    defer gpa.free(cus_eval);
    try runEmacs(io, gpa, &env_map, temacs, dump, lisp_path, &.{
        "--eval", "(setq make-backup-files nil create-lockfiles nil write-region-inhibit-fsync t)",
        "-l", "cus-dep",
        "--eval", cus_eval,
        "-f", "custom-make-dependencies",
    }, subdirs);

    const finder_eval = try std.fmt.allocPrint(gpa, "(setq generated-finder-keywords-file \"{s}/finder-inf.el\")", .{lisp_path_flat});
    defer gpa.free(finder_eval);
    try runEmacs(io, gpa, &env_map, temacs, dump, lisp_path, &.{
        "--eval", "(setq make-backup-files nil create-lockfiles nil write-region-inhibit-fsync t)",
        "-l", "finder",
        "--eval", finder_eval,
        // drive finder-compile-keywords over the trailing DIRS and let batch
        // mode exit normally (no explicit `kill-emacs').
        "--eval", "(apply #'finder-compile-keywords command-line-args-left)",
    }, finder_dirs);

    // Record the post-run fingerprint + the outputs that must survive
    // for the next run to skip (any missing output forces a regen).
    var f = freshFinger(io, gpa, cwd, temacs, dump);
    const outputs = try collectOutputs(io, gpa, cwd);
    defer {
        for (outputs) |o| gpa.free(o);
        gpa.free(outputs);
    }
    stamp.mark(io, gpa, cwd, stampName, f.final(), outputs);
}

const stampName = "loaddefs.stamp";

/// Fingerprint of everything the three emacs invocations read: the lisp
/// tree minus this tool's own outputs (isLoaddefsOutput) and minus every
/// .elc (isElc), plus the binary and dump that run the scrape (and this
/// tool's source, so editing it invalidates).
///
/// Excluding ALL .elc breaks a stamp-death cycle with compile-lisp: the
/// scrape reads autoload/custom/finder cookies from the .el SOURCES, so a
/// recompile's new .elc (mtime/size churn) is not a scrape input.  Before
/// this, compile-lisp re-emitting .elc invalidated loaddefs.stamp, which
/// rewrote the *-loaddefs.el (mtime churn), which reinvalidated
/// compile-lisp.stamp (it fingerprints the loaddefs .el as inputs), which
/// recompiled again -- loaddefs-final and compile-lisp ping-ponged on
/// every `zig build`, so the CI .zeln step regenerated the whole tree
/// 6-10x (finder/custom/loaddefs runs plus compile-lisp) instead of once.
fn freshFinger(io: std.Io, gpa: std.mem.Allocator, cwd: std.Io.Dir, temacs: []const u8, dump: []const u8) stamp.Finger {
    var f = stamp.Finger.init("loaddefs");
    f.file(io, cwd, temacs);
    f.file(io, cwd, dump);
    f.file(io, cwd, "build-aux/generate-loaddefs.zig");
    f.tree(io, gpa, cwd, "lisp", fingerprintExclude) catch {};
    return f;
}

/// Tree entries excluded from the freshness fingerprint: every .elc
/// (compile-lisp's outputs; not scrape inputs) and this tool's own
/// loaddefs outputs.
fn fingerprintExclude(rel: []const u8) bool {
    if (std.mem.endsWith(u8, rel, ".elc")) return true;
    return isLoaddefsOutput(rel);
}

fn upToDate(io: std.Io, gpa: std.mem.Allocator, cwd: std.Io.Dir, temacs: []const u8, dump: []const u8) !bool {
    var f = freshFinger(io, gpa, cwd, temacs, dump);
    return stamp.isFresh(io, gpa, cwd, stampName, f.final());
}

/// True for the files this tool writes: lisp/loaddefs.el(.elc),
/// per-subdir *-loaddefs.el(.elc), cus-load.el, finder-inf.el.  Doubles
/// as the tree-fingerprint exclusion (outputs must not fingerprint
/// their pre-generation state) and the post-run output collector.
fn isLoaddefsOutput(rel: []const u8) bool {
    const base = std.fs.path.basename(rel);
    if (std.mem.endsWith(u8, base, "~")) return true; // emacs backup files
    // An .elc is excluded when its .el is: byte-recompile-directory
    // compiles the whole regenerated loaddefs family every build, so
    // cus-load.elc / finder-inf.elc churn the tree as much as the .el
    // forms do.
    if (std.mem.endsWith(u8, base, ".elc"))
        return isLoaddefsOutput(base[0 .. base.len - 1]);
    return std.mem.eql(u8, base, "loaddefs.el") or
        std.mem.eql(u8, base, "cus-load.el") or
        std.mem.eql(u8, base, "finder-inf.el") or
        std.mem.endsWith(u8, base, "-loaddefs.el");
}

/// Walk lisp/ and collect every output path this tool produced, in
/// sorted order (deterministic stamp output list).
fn collectOutputs(io: std.Io, gpa: std.mem.Allocator, cwd: std.Io.Dir) ![]const []const u8 {
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
        if (!isLoaddefsOutput(entry.path)) continue;
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
/// flakiness, like the check step) AND on a hard timeout enforced by a
/// watchdog thread.
///
/// std.process.run is NOT used: its .timeout only bounds reads of the
/// child's stdout/stderr pipes, so a child that prints its final line and
/// then hangs without closing the pipes (exactly what the windows-latest
/// finder scrape does -- it prints 'Scanning files for finder...done' and
/// blocks in the finder-inf.el write phase) never trips it.  Instead this
/// spawns the child, a thread performs the blocking wait on on an Io of
/// its own, and the main thread sleeps in 500ms steps and calls
/// child.kill(io) once the deadline (default 120s, LOADDEFS_EMACS_TIMEOUT
/// overrides) passes.  On the deadline the child is killed and retried
/// with a fresh process (the scrape is deterministic), capped at 3
/// attempts.
const WaiterState = struct {
    gpa: std.mem.Allocator,
    child: std.process.Child,
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    term: std.process.Child.Term = .{ .exited = 255 },
};

fn waitThread(w: *WaiterState) void {
    var wio_threaded: std.Io.Threaded = .init(w.gpa, .{});
    const wio = wio_threaded.io();
    w.term = w.child.wait(wio) catch .{ .exited = 255 };
    w.done.store(true, .release);
}

fn runEmacs(
    io: std.Io,
    gpa: std.mem.Allocator,
    env_map: *const std.process.Environ.Map,
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
    var dit = std.mem.tokenizeScalar(u8, dirs, ' ');
    while (dit.next()) |d| try argv.append(gpa, d);

    const EMACS_TIMEOUT_SECS: i64 = blk: {
        if (env_map.get("LOADDEFS_EMACS_TIMEOUT")) |v|
            break :blk std.fmt.parseInt(i64, v, 10) catch 120;
        break :blk 120;
    };

    const clock = std.Io.Clock.awake;
    var attempt: usize = 0;
    while (true) : (attempt += 1) {
        var child = std.process.spawn(io, .{
            .argv = argv.items,
            .cwd = .{ .path = lisp_path },
            .environ_map = env_map,
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        }) catch |err| {
            std.debug.print("generate-loaddefs: spawn failed: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };

        var state: WaiterState = .{ .gpa = gpa, .child = child };
        const t = std.Thread.spawn(.{ .allocator = gpa }, waitThread, .{&state}) catch |err| {
            child.kill(io);
            std.debug.print("generate-loaddefs: watchdog thread spawn failed: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };

        var killed = false;
        const deadline = std.Io.Timestamp.now(io, clock).addDuration(
            std.Io.Duration.fromSeconds(EMACS_TIMEOUT_SECS),
        );
        while (!state.done.load(.acquire)) {
            if (std.Io.Timestamp.now(io, clock).durationTo(deadline).nanoseconds <= 0 and !killed) {
                killed = true;
                std.debug.print("generate-loaddefs: emacs scrape timed out after {d}s (attempt {d}/3); killing\n", .{ EMACS_TIMEOUT_SECS, attempt + 1 });
                child.kill(io);
            }
            io.sleep(std.Io.Duration.fromMilliseconds(500), std.Io.Clock.awake) catch {};
        }
        t.join();
        const term = state.term;
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
        if (killed and attempt >= 2) {
            std.debug.print("generate-loaddefs: scrape timed out 3x -- failing\n", .{});
            std.process.exit(1);
        }
    }
}
