//! Native Zig replacement for build-aux/check-all.sh: run every
//! *-tests.el under test/ in its own temacs process with a per-suite
//! timeout, classifying each outcome (PASS/FAIL/HANG/CRASH/LOAD) so one
//! bad suite can never hide another. No shell; the pdumper relocation
//! flake is retried on signal death, and the stack limit is raised
//! first (the shell's `ulimit -s unlimited`). Run with cwd = repo root.

const std = @import("std");
const aslr = @import("aslr.zig");
const builtin = @import("builtin");
const temacs_path = @import("temacs-path.zig");

const preload = "(progn (load \"cl-macs\") (load \"cl-seq\") (load \"cl-extra\") (require (quote ert)))";

pub fn main(minimal: std.process.Init.Minimal) !void {
    aslr.disableAslr();
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    if (comptime builtin.os.tag != .windows) {
        std.posix.setrlimit(.STACK, .{
            .cur = std.posix.RLIM.INFINITY,
            .max = std.posix.RLIM.INFINITY,
        }) catch {};
    }

    var env_map = try std.process.Environ.createMap(minimal.environ, gpa);
    defer env_map.deinit();
    // Mirror the upstream test environment: TERM=dumb for the batch
    // runs.  A missing TERM makes terminal-dependent suites misbehave
    // (tab-bar-tests skips its tty test only when TERM is "dumb" on
    // darwin), while an unknown term type fails terminfo lookups under
    // HOME=/nonexistent.
    try env_map.put("TERM", "dumb");
    try env_map.put("LANG", "C");
    try env_map.put("HOME", "/nonexistent");

    const root = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(root);
    const test_path = try std.fs.path.join(gpa, &.{ root, "test" });
    defer gpa.free(test_path);
    try env_map.put("EMACS_TEST_DIRECTORY", test_path);

    var timeout: i64 = 90;
    if (env_map.get("CHECK_ALL_TIMEOUT")) |s| {
        timeout = std.fmt.parseInt(i64, s, 10) catch 90;
    }
    var retries: usize = 3;
    if (env_map.get("CHECK_ALL_RETRIES")) |s| {
        retries = std.fmt.parseInt(usize, s, 10) catch 3;
    }
    const filter = env_map.get("CHECK_ALL_FILTER");

    var suites: std.ArrayList([]const u8) = .empty;
    defer {
        for (suites.items) |s| gpa.free(s);
        suites.deinit(gpa);
    }
    {
        var test_dir = try cwd.openDir(io, "test", .{ .iterate = true });
        defer test_dir.close(io);
        var w = try test_dir.walk(gpa);
        defer w.deinit();
        while (try w.next(io)) |entry| {
            const base = entry.basename;
            if (entry.kind == .directory) {
                // Prune manual / data / infra / *resources dirs (not part
                // of `make check`); skip descending into them.
                if (std.mem.eql(u8, base, "manual") or
                    std.mem.eql(u8, base, "data") or
                    std.mem.eql(u8, base, "infra") or
                    std.mem.endsWith(u8, base, "resources"))
                {
                    w.leave(io);
                }
                continue;
            }
            if (entry.kind != .file) continue;
            if (std.mem.eql(u8, base, "emacs-module-tests.el")) continue; // modules disabled
            if (!std.mem.endsWith(u8, base, "-tests.el")) continue;
            if (filter) |f| {
                // Approximate the shell's grep -E filter: match if any
                // '|'-separated alternative is a substring of the path.
                var matched = false;
                var alts = std.mem.splitScalar(u8, f, '|');
                while (alts.next()) |alt| {
                    if (alt.len > 0 and std.mem.indexOf(u8, entry.path, alt) != null) {
                        matched = true;
                        break;
                    }
                }
                if (!matched) continue;
            }
            try suites.append(gpa, try gpa.dupe(u8, entry.path));
        }
    }
    std.mem.sort([]const u8, suites.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);

    std.debug.print("check-all: {d} suites, timeout={d}s\n", .{ suites.items.len, timeout });

    const out_dir = try std.fs.path.join(gpa, &.{ root, "zig-out", "check-all" });
    defer gpa.free(out_dir);
    {
    // std.os.linux.mkdir is Linux-only; on macOS it silently does
    // nothing, so the per-suite logs were never written.  Use the
    // cross-platform Io API instead.
    cwd.createDir(io, out_dir, @enumFromInt(0o755)) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    }

    var pass: usize = 0;
    var fail: usize = 0;
    var hang: usize = 0;
    var crash: usize = 0;
    var loaderr: usize = 0;
    var n: usize = 0;

    for (suites.items) |suite| {
        n += 1;
        // rel = path under test/ without the .el; suitedir = absolute dir;
        // loadtarget = absolute path without the .el.
        const rel = suite[0 .. suite.len - 3]; // strip ".el"
        const loadtarget = try std.fs.path.join(gpa, &.{ root, "test", rel });
        defer gpa.free(loadtarget);
        const dirname = std.fs.path.dirname(rel) orelse ".";
        const suitedir = try std.fs.path.join(gpa, &.{ root, "test", dirname });
        defer gpa.free(suitedir);

        const form = try std.fmt.allocPrint(gpa, "(progn {s} (load \"{s}\") (let ((ert-batch-print-lines 0)) (ert-run-tests-batch-and-exit (quote (not (or (tag :expensive-test) (tag :unstable) (tag :nativecomp)))))))", .{ preload, loadtarget });
        defer gpa.free(form);
        const dump_path = try std.fs.path.join(gpa, &.{ root, "zig-out", "bin", "bootstrap-emacs.pdmp" });
        defer gpa.free(dump_path);
        const dump_arg = try std.fmt.allocPrint(gpa, "--dump-file={s}", .{dump_path});
        defer gpa.free(dump_arg);
        const temacs = try temacs_path.joinBin(gpa, root);
        defer gpa.free(temacs);
        const l1 = try std.fs.path.join(gpa, &.{ root, "test" });
        defer gpa.free(l1);

        const argv = [_][]const u8{ temacs, "--batch", "-L", l1, "-L", suitedir, dump_arg, "--eval", form };

        var out: []u8 = &.{};
        var out_owned = false;
        var term: std.process.Child.Term = .{ .exited = 255 };
        var attempt: usize = 0;
        while (true) : (attempt += 1) {
            const res = std.process.run(gpa, io, .{
                .argv = &argv,
                .cwd = .{ .path = suitedir },
                .environ_map = &env_map,
                .timeout = .{ .duration = .{ .raw = std.Io.Duration.fromSeconds(timeout), .clock = .awake } },
                .stdout_limit = .unlimited,
                .stderr_limit = .unlimited,
            }) catch |err| switch (err) {
                error.Timeout => {
                    term = .{ .exited = 124 };
                    out = &.{};
                    out_owned = false;
                    break;
                },
                else => {
                    std.debug.print("check-all: {s} spawn failed: {s}\n", .{ rel, @errorName(err) });
                    term = .{ .exited = 255 };
                    out_owned = false;
                    break;
                },
            };
            out = try std.mem.concat(gpa, u8, &.{ res.stdout, res.stderr });
            gpa.free(res.stdout);
            gpa.free(res.stderr);
            out_owned = true;
            term = res.term;
            // Retry only on signal death (pdumper relocation flake); a
            // genuine result exits 0/1/255 and a timeout is 124.
            switch (term) {
                .signal => |sig| {
                    if (attempt + 1 >= retries) break;
                    std.debug.print("check-all: {s} died with signal {d} on attempt {d}/{d}; retrying\n", .{ rel, @intFromEnum(sig), attempt + 1, retries });
                    continue;
                },
                else => break,
            }
        }

        const rc: u16 = switch (term) {
            .exited => |code| code,
            .signal => |sig| 128 + @as(u16, @intCast(@intFromEnum(sig))),
            else => 255,
        };
        var status: []const u8 = undefined;
        var detail: []const u8 = "";
        switch (rc) {
            0 => {
                status = "PASS";
                pass += 1;
            },
            1 => {
                status = "FAIL";
                fail += 1;
                detail = extractUnexpected(out) orelse "";
            },
            124, 137 => {
                status = "HANG";
                hang += 1;
                detail = "timeout";
            },
            else => {
                if (rc >= 128 and rc <= 192) {
                    status = "CRASH";
                    crash += 1;
                    detail = "signal";
                } else {
                    status = "LOAD";
                    loaderr += 1;
                    detail = firstErrorLine(out) orelse "";
                }
            },
        }

        std.debug.print("{s}\trc={d}\t{s}\t{s}\n", .{ status, rc, rel, detail });
        const log_rel = try std.mem.replaceOwned(u8, gpa, rel, "/", "_");
        defer gpa.free(log_rel);
        const log_name = try std.fmt.allocPrint(gpa, "{s}.out", .{log_rel});
        defer gpa.free(log_name);
        const log_full = try std.fs.path.join(gpa, &.{ "zig-out", "check-all", log_name });
        defer gpa.free(log_full);
        cwd.writeFile(io, .{ .sub_path = log_full, .data = out }) catch {};
        if (out_owned) gpa.free(out);
    }

    std.debug.print("\n=== check-all SUMMARY ===\n", .{});
    std.debug.print("total={d}  pass={d}  fail={d}  hang={d}  crash={d}  load={d}\n", .{ n, pass, fail, hang, crash, loaderr });
}

// "N unexpected result(s)" from the ert batch output (FAIL detail).
fn extractUnexpected(out: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, out, '\n');
    var found: ?[]const u8 = null;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.indexOf(u8, trimmed, "unexpected") != null and
            std.mem.indexOfAny(u8, trimmed, "0123456789") != null)
        {
            found = trimmed;
        }
    }
    return found;
}

// First error-ish line from the suite output (LOAD detail).
fn firstErrorLine(out: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, out, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.indexOfAny(u8, trimmed, "errorvoidcannotwrongno catch") != null)
            return trimmed[0..@min(trimmed.len, 80)];
    }
    return null;
}
