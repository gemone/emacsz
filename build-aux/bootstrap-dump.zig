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

    // zig-out/etc -> ../etc so the dumped emacs resolves ../etc/ relative
    // to the process CWD at dump time (Fsnarf-documentation / DOC).
    cwd.deleteFile(io, "zig-out/etc") catch {};
    cwd.symLink(io, "../etc", "zig-out/etc", .{ .is_directory = true }) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // parallel build already linked it
        // Non-privileged Windows hosts can't create symlinks
        // (PRIVILEGE_NOT_HELD; needs Developer Mode or admin). EMACSDATA
        // below already points the bootstrap emacs at the source-tree etc,
        // so the relative ../etc resolution is not required there.
        error.PermissionDenied => {},
        else => return err,
    };

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
    const pdmp_link = try std.fs.path.join(gpa, &.{ bin_dir, "temacs.pdmp" });
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
}

fn printTail(out: []const u8) void {
    std.debug.print("{s}\n", .{out});
}
