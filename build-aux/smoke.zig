//! Native Zig replacement for the smoke-step shell script in build.zig:
//! prove the dumped emacs starts and evaluates Lisp (emacs-version), and
//! that the installed emacs wrapper works end-to-end (`--version`).
//! No shell; the pdumper relocation flake is retried on signal death.
//! Run with cwd = repo root.

const std = @import("std");
const aslr = @import("aslr.zig");
const env = @import("env.zig");
const temacs_path = @import("temacs-path.zig");

pub fn main(minimal: std.process.Init.Minimal) !void {
    aslr.disableAslr();
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();

    const root = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(root);
    const lisp_path = try std.fs.path.join(gpa, &.{ root, "lisp" });
    defer gpa.free(lisp_path);
    const etc_path = try std.fs.path.join(gpa, &.{ root, "etc" });
    defer gpa.free(etc_path);

    var env_map = try env.inherit(gpa, minimal);
    defer env_map.deinit();
    try env_map.put("EMACSLOADPATH", lisp_path);
    try env_map.put("EMACSDATA", etc_path);
    try env_map.put("LC_ALL", "C");

    const temacs_argv = [_][]const u8{
        "./zig-out/bin/" ++ temacs_path.name,
        "--batch",
        "--dump-file=./zig-out/bin/bootstrap-emacs.pdmp",
        "--eval", "(princ emacs-version)",
    };

    // Direct dumped-emacs load: retry on signal death (ASLR-sensitive
    // pdumper relocation, like the dump and check steps).
    var attempt: usize = 0;
    var version: []u8 = &.{};
    while (true) : (attempt += 1) {
        const res = std.process.run(gpa, io, .{
            .argv = &temacs_argv,
            .environ_map = &env_map,
            .stdout_limit = .limited(1024),
        }) catch |err| {
            std.debug.print("smoke: temacs run failed: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        defer gpa.free(res.stdout);
        defer gpa.free(res.stderr);
        switch (res.term) {
            .exited => |code| {
                if (code == 0) {
                    version = try gpa.dupe(u8, res.stdout);
                    break;
                }
                std.debug.print("smoke: temacs exited {d}\n", .{code});
                std.process.exit(1);
            },
            .signal => |sig| {
                std.debug.print("smoke: temacs died with signal {d}; retrying ({d}/3)\n", .{ @intFromEnum(sig), attempt + 1 });
                if (attempt >= 2) std.process.exit(1);
            },
            else => std.process.exit(1),
        }
    }
    const trimmed = std.mem.trim(u8, version, " \t\r\n");
    var vi: usize = 0;
    while (vi < trimmed.len and std.ascii.isDigit(trimmed[vi])) vi += 1;
    if (vi == 0 or vi >= trimmed.len or trimmed[vi] != '.') {
        std.debug.print("smoke: bad emacs-version output: {s}\n", .{trimmed});
        std.process.exit(1);
    }
    if (vi + 1 >= trimmed.len or !std.ascii.isDigit(trimmed[vi + 1])) {
        std.debug.print("smoke: bad emacs-version output: {s}\n", .{trimmed});
        std.process.exit(1);
    }
    std.debug.print("{s}\n", .{trimmed});
    std.debug.print("smoke: dumped emacs version {s}\n", .{trimmed});

    // Exercise the installed emacs wrapper end-to-end.
    const wrapper_argv = [_][]const u8{"./zig-out/bin/emacs", "--version"};
    const wres = std.process.run(gpa, io, .{
        .argv = &wrapper_argv,
        .environ_map = &env_map,
        .stdout_limit = .limited(4096),
        .stderr_limit = .limited(4096),
    }) catch |err| {
        std.debug.print("smoke: emacs wrapper run failed: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer gpa.free(wres.stdout);
    defer gpa.free(wres.stderr);
    const wtrim = std.mem.trim(u8, wres.stdout, " \t\r\n");
    if (!std.mem.startsWith(u8, wtrim, "GNU Emacs ")) {
        std.debug.print("smoke: bad wrapper output: {s}\n", .{wtrim});
        std.process.exit(1);
    }
    var wlines = std.mem.splitScalar(u8, wtrim, '\n');
    if (wlines.next()) |first| std.debug.print("smoke: emacs wrapper version {s}\n", .{first});
}
