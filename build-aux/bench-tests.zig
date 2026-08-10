//! bench-tests: real-suite performance comparison for the .zeln path.
//! Runs the SAME built-in ert suite (the 43 test/src + test/lisp files the
//! check harness loads — the real test/ tree, NOT synthetic micro-benchmarks)
//! twice against the dumped emacs:
//!   (1) interpreter baseline: run-check with ZELN_LOAD_PATH unset (the
//!       original exec_byte_code path, exactly what `zig build check' runs);
//!   (2) .zeln path: run-check with ZELN_LOAD_PATH=<cache> (the transparent
//!       .elc -> .zeln swap, exactly what `zig build check-zeln' runs).
//! Extracts the ert-reported elapsed seconds from each run's summary line
//! ("Ran N tests, ... (DATE, T sec)") and prints the wall-clock comparison
//! + the zeln/interp ratio (LOWER = zeln faster).  Exits non-zero if either
//! run reports unexpected results (a perf comparison over a failing suite is
//! meaningless) or the times cannot be parsed.
//!
//! Usage: bench-tests <run-check-exe> <zeln-cache-dir>
//! (cwd = repo root; the dumped emacs is at ./zig-out/bin/emacs.)

const std = @import("std");
const env = @import("env.zig");

const Summary = struct { tests: usize, unexpected: usize, secs: f64 };

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();

    var arg_it = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer arg_it.deinit();
    _ = arg_it.next(); // argv[0]
    const run_check_exe = arg_it.next() orelse {
        std.debug.print("bench-tests: missing <run-check-exe> arg\n", .{});
        std.process.exit(2);
    };
    const zeln_cache = arg_it.next() orelse {
        std.debug.print("bench-tests: missing <zeln-cache-dir> arg\n", .{});
        std.process.exit(2);
    };
    const n_runs = 3; // best-of-N per mode (machine noise on shared hosts)

    var env_map = try env.inherit(gpa, minimal);
    defer env_map.deinit();

    const argv = [_][]const u8{run_check_exe};

    // ---- Mode 1: interpreter baseline (ZELN_LOAD_PATH unset). ----
    _ = env_map.swapRemove("ZELN_LOAD_PATH");
    const interp = try bestOf(gpa, io, &env_map, &argv, n_runs);
    // ---- Mode 2: .zeln path (ZELN_LOAD_PATH=<cache>). ----
    try env_map.put("ZELN_LOAD_PATH", zeln_cache);
    const zeln = try bestOf(gpa, io, &env_map, &argv, n_runs);

    if (interp.unexpected > 0 or zeln.unexpected > 0) {
        std.debug.print("bench-tests: cannot compare over failing runs (interp {d} unexpected, zeln {d} unexpected)\n", .{ interp.unexpected, zeln.unexpected });
        std.process.exit(1);
    }
    const ratio = if (interp.secs > 0) zeln.secs / interp.secs else 0.0;
    std.debug.print("bench-tests: ert suite {d} tests, best-of-{d} — interpreter {d:.3}s, .zeln {d:.3}s, zeln/interp = {d:.3} (lower = zeln faster; <1 = zeln beats interpreter)\n", .{ interp.tests, n_runs, interp.secs, zeln.secs, ratio });
}

fn bestOf(
    gpa: std.mem.Allocator,
    io: std.Io,
    env_map: *std.process.Environ.Map,
    argv: []const []const u8,
    n: usize,
) !Summary {
    var best: ?Summary = null;
    for (0..n) |_| {
        const s = try runOne(gpa, io, env_map, argv);
        if (best == null or s.secs < best.?.secs) best = s;
    }
    return best.?;
}

fn runOne(
    gpa: std.mem.Allocator,
    io: std.Io,
    env_map: *std.process.Environ.Map,
    argv: []const []const u8,
) !Summary {
    const res = try std.process.run(gpa, io, .{
        .argv = argv,
        .environ_map = env_map,
    });
    // The ert summary ("Ran N tests ...") goes to stderr in batch mode
    // (message -> *Messages* -> stderr); try both streams.
    return parseSummary(res.stdout) orelse parseSummary(res.stderr) orelse {
        std.debug.print("bench-tests: could not parse ert summary\n--- stdout ---\n{s}\n--- stderr ---\n{s}\n", .{ res.stdout, res.stderr });
        std.process.exit(1);
    };
}

fn parseSummary(stdout: []const u8) ?Summary {
    var best: ?Summary = null;
    var it = std.mem.splitScalar(u8, stdout, '\n');
    while (it.next()) |line| {
        const idx = std.mem.indexOf(u8, line, "Ran ") orelse continue;
        const after = line[idx + 4 ..];
        // "Ran N tests, ...": N is the digits before " tests".
        const tpos = std.mem.indexOf(u8, after, " tests") orelse continue;
        const tests = std.fmt.parseInt(usize, std.mem.trim(u8, after[0..tpos], " "), 10) catch continue;
        if (std.mem.indexOf(u8, line, "unexpected") == null) continue;
        const upos = std.mem.lastIndexOf(u8, line, "unexpected") orelse continue;
        const up_start = std.mem.lastIndexOfScalar(u8, line[0..upos], ',') orelse continue;
        const unexpected = std.fmt.parseInt(usize, std.mem.trim(u8, line[up_start + 1 .. upos], " "), 10) catch continue;
        const paren = std.mem.lastIndexOfScalar(u8, line, '(') orelse continue;
        const secs = parseSecs(line[paren + 1 ..]) orelse continue;
        best = .{ .tests = tests, .unexpected = unexpected, .secs = secs };
    }
    return best;
}

fn parseSecs(tail: []const u8) ?f64 {
    // tail looks like "2026-08-10 22:11:53+0800, 20.845857 sec)"
    const last_comma = std.mem.lastIndexOfScalar(u8, tail, ',') orelse return null;
    const rest = std.mem.trim(u8, tail[last_comma + 1 ..], " ");
    const sec = std.mem.indexOf(u8, rest, " sec") orelse return null;
    return std.fmt.parseFloat(f64, std.mem.trim(u8, rest[0..sec], " ")) catch null;
}
