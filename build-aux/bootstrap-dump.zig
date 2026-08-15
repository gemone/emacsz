//! Native Zig replacement for the bootstrap-dump shell script in
//! build.zig: scrub stale loaddefs (loadup must NOT see them -- it uses
//! ldefs-boot.el), prepare zig-out/etc for the dumped emacs, run loadup
//! in pbootstrap mode with EMACSLOADPATH/EMACSDATA pointing at the
//! source tree, and link temacs.pdmp. No shell; the pdumper relocation
//! flake is retried on signal death (the ASLR-off setarch trick is not
//! available without a shell). Run with cwd = repo root.

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

    const root = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(root);
    const bin_dir = try std.fs.path.join(gpa, &.{ root, "zig-out", "bin" });
    defer gpa.free(bin_dir);
    const lisp_path = try std.fs.path.join(gpa, &.{ root, "lisp" });
    defer gpa.free(lisp_path);
    const etc_path = try std.fs.path.join(gpa, &.{ root, "etc" });
    defer gpa.free(etc_path);
    const temacs = try temacs_path.joinBin(gpa, root);
    defer gpa.free(temacs);

    // zig-out/etc -> ../etc so the dumped emacs resolves ../etc/ relative
    // to the process CWD at dump time (Fsnarf-documentation / DOC).
    // Kept BEFORE the freshness check: it must exist even on the skip
    // path (the dumped emacs consults ../etc at runtime too).
    linkEtc(io, cwd);

    // Freshness stamp: loadup embeds the temacs binary's subrs plus the
    // preloaded lisp state (loadup.el + the lisp tree, .el sources and
    // .elc whichever is newer) and snarfs etc/DOC, with the charset maps
    // under etc/charsets loaded during preload.  When none of that moved
    // and both dump outputs survive, skip the whole scrub+loadup.  Both
    // Run sites of this tool (source dump and post-compile re-dump)
    // compute the fingerprint at THEIR position in the graph, so a
    // recompile between them naturally invalidates the second dump.
    // The loaddefs outputs are excluded: loadup must not see them (the
    // scrub below deletes them) and they are regenerated downstream.
    {
        var f = try freshFinger(io, gpa, cwd, temacs);
        if (stamp.isFresh(io, gpa, cwd, stampName, f.final())) {
            std.debug.print("bootstrap-dump: dump up to date (stamp); skipping loadup\n", .{});
            return;
        }
    }

    // Scrub stale loaddefs: a leftover lisp/loaddefs.el makes loadup
    // abort (e.g. void frameset-filter-alist at tab-bar), so remove the
    // top-level files plus every per-subdir *-loaddefs.el(.elc) at depth
    // >= 2 (they are regenerated after the dump).
    for ([_][]const u8{ "lisp/loaddefs.el", "lisp/loaddefs.elc" }) |p| {
        cwd.deleteFile(io, p) catch {};
    }
    {
        var lisp = try cwd.openDir(io, "lisp", .{ .iterate = true });
        defer lisp.close(io);
        var w = try lisp.walk(gpa);
        defer w.deinit();
        while (try w.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (std.mem.indexOfScalar(u8, entry.path, '/') == null) continue; // depth >= 2
            const base = std.fs.path.basename(entry.path);
            if (std.mem.endsWith(u8, base, "-loaddefs.el") or
                std.mem.endsWith(u8, base, "-loaddefs.elc"))
            {
                lisp.deleteFile(io, entry.path) catch {};
            }
        }
    }

    // Loadup must run from zig-out/bin with the source-tree env.
    var env_map = try env.inherit(gpa, minimal);
    defer env_map.deinit();
    try env_map.put("EMACSLOADPATH", lisp_path);
    try env_map.put("EMACSDATA", etc_path);
    try env_map.put("LC_ALL", "C");

    const argv = [_][]const u8{ "./" ++ temacs_path.name, "-batch", "-l", "loadup", "--temacs=pbootstrap" };
    var attempt: usize = 0;
    while (true) : (attempt += 1) {
        std.debug.print("bootstrap-dump: attempt {d}\n", .{attempt + 1});
        const res = std.process.run(gpa, io, .{
            .argv = &argv,
            .cwd = .{ .path = bin_dir },
            .environ_map = &env_map,
            .stdout_limit = .unlimited,
            .stderr_limit = .unlimited,
        }) catch |err| {
            std.debug.print("bootstrap-dump: spawn failed: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        switch (res.term) {
            .exited => |code| {
                if (code == 0) break;
                printTail(res.stdout);
                printTail(res.stderr);
                std.debug.print("bootstrap-dump: temacs exited {d}\n", .{code});
                std.process.exit(1);
            },
            .signal => |sig| {
                printTail(res.stdout);
                printTail(res.stderr);
                std.debug.print("bootstrap-dump: temacs died with signal {d}; retrying ({d}/3)\n", .{ @intFromEnum(sig), attempt + 1 });
                if (attempt >= 2) std.process.exit(1);
            },
            else => std.process.exit(1),
        }
    }

    // Make the binary self-contained: load_pdump auto-loads "<argv0>.pdmp"
    // from the executable's directory, so subprocess re-invocations start
    // the dumped emacs instead of re-running loadup from source.
    //
    // The companion must be named <temacs-name>.pdmp: on Windows that is
    // temacs.exe.pdmp (argv[0] is temacs.exe), which is also exactly what
    // the dump.stamp records below -- before this fix the link/copy used
    // the hard-coded "temacs.pdmp" (a Unix-only name), so the recorded
    // output never existed, dump.stamp reported 'recorded output missing'
    // forever, and every CI run re-dumped, which re-ran the loaddefs final
    // pass (its stamp fingerprints the dump), which re-ran the finder scan
    // that hangs on windows-latest.
    const pdmp_name = try std.mem.concat(gpa, u8, &.{ temacs_path.name, ".pdmp" });
    defer gpa.free(pdmp_name);
    const pdmp_link = try std.fs.path.join(gpa, &.{ bin_dir, pdmp_name });
    defer gpa.free(pdmp_link);
    std.Io.Dir.deleteFileAbsolute(io, pdmp_link) catch {};
    cwd.symLink(io, "bootstrap-emacs.pdmp", pdmp_link, .{}) catch |err| switch (err) {
        // Non-privileged Windows hosts can't symlink (PRIVILEGE_NOT_HELD);
        // copy the pdmp so load_pdump still resolves "<argv0>.pdmp" for
        // subprocess re-invocations of the dumped emacs.
        error.PermissionDenied => {
            const pdmp_src_abs = try std.fs.path.join(gpa, &.{ bin_dir, "bootstrap-emacs.pdmp" });
            defer gpa.free(pdmp_src_abs);
            try std.Io.Dir.copyFileAbsolute(pdmp_src_abs, pdmp_link, io, .{ .replace = true });
        },
        else => return err,
    };

    // Record the post-run fingerprint + outputs (the pdmp itself and the
    // <temacs>.pdmp companion).  Computed AFTER loadup so a re-dump that
    // nothing upstream moved converges on the next run.
    var f = try freshFinger(io, gpa, cwd, temacs);
    stamp.mark(io, gpa, cwd, stampName, f.final(), &.{
        "zig-out/bin/bootstrap-emacs.pdmp",
        "zig-out/bin/" ++ temacs_path.name ++ ".pdmp",
    });
}

const stampName = "dump.stamp";

/// Fingerprint of every loadup input: the temacs binary (subrs land in
/// the dump), src/loadup.el (the preload script), the lisp tree minus
/// the loaddefs outputs (loadup reads .el/.elc with ldefs-boot instead),
/// etc/DOC (snarfed at dump time), the charset maps (loaded during
/// preload) and this tool's source.
fn freshFinger(io: std.Io, gpa: std.mem.Allocator, cwd: std.Io.Dir, temacs: []const u8) !stamp.Finger {
    var f = stamp.Finger.init("dump");
    f.file(io, cwd, temacs);
    f.file(io, cwd, "build-aux/bootstrap-dump.zig");
    // etc/DOC is rewritten by the UpdateSourceFiles step on every build
    // (the make-docfile Run re-executes and its capture carries a fresh
    // mtime), so fingerprint its CONTENT: an unchanged DOC must not
    // invalidate the dump stamp.
    f.fileContent(io, cwd, gpa, "etc/DOC");
    f.tree(io, gpa, cwd, "etc/charsets", null) catch {};
    f.tree(io, gpa, cwd, "lisp", isLoaddefsOutput) catch {};
    return f;
}

/// The files the scrub deletes before loadup: lisp/loaddefs.el(.elc) and
/// every per-subdir *-loaddefs.el(.elc).  Excluded from the fingerprint
/// because loadup never reads them.  cus-load.el and finder-inf.el are
/// excluded too: they are autoload-metadata written by the loaddefs
/// pass AFTER the dump (never preload inputs), and fingerprinting them
/// would make the dump and loaddefs stamps invalidate each other
/// forever.
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

/// Ensure zig-out/etc -> ../etc (idempotent; called on both the fresh
/// and the skip path).
fn linkEtc(io: std.Io, cwd: std.Io.Dir) void {
    cwd.deleteFile(io, "zig-out/etc") catch {};
    cwd.symLink(io, "../etc", "zig-out/etc", .{ .is_directory = true }) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // parallel build already linked it
        // Non-privileged Windows hosts can't create symlinks
        // (PRIVILEGE_NOT_HELD; needs Developer Mode or admin). EMACSDATA
        // already points the bootstrap emacs at the source-tree etc,
        // so the relative ../etc resolution is not required there.
        error.PermissionDenied => {},
        else => return,
    };
}

fn printTail(out: []const u8) void {
    std.debug.print("{s}\n", .{out});
}
