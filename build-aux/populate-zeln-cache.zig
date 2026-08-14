//! populate-zeln-cache: the M2b cache-population driver (plan M2b
//! deliverable 1).  Two phases:
//!
//!   (a) spawn the dumped emacs ONCE to run build-aux/zeln-populate.el,
//!       which walks lisp/**/*.elc and serializes each to a zabi=3 zunit
//!       (comp-z-write-file-zunit), writing JOBS + SKIPS-LISP under
//!       zig-out/zeln-cache.  Per-file serialize signals are caught inside
//!       the Elisp helper (condition-case) and recorded as skips.
//!   (b) spawn ONE zeln-compile per job (leaf, parallelizable) producing
//!       zig-out/zeln-cache/<ver>/<rel>.zeln.  A zeln-compile non-zero
//!       exit (emitter error.UnsupportedOpcode on Bswitch/obsolete, or a
//!       serializer/round-trip signal) is CAUGHT PER-FILE: that .elc is
//!       recorded in the skip list and the step CONTINUES.  It does NOT
//!       fail.
//!
//! Then aggregates, writes zig-out/zeln-cache/SKIP-LIST, prints the
//! coverage ratio, and exits 0 unconditionally.  Skips are not failures:
//! a skipped .elc falls back to the interpreter via the transparent-load
//! fallthrough (maybe_swap_for_zeln), so native-where-compiled +
//! interpreter-where-skipped is observationally identical to
//! all-interpreter (the 582-via-.zeln gate proves it).
//!
//! Usage: populate-zeln-cache <zeln-compile-exe>
//! (the dumped emacs is at ./zig-out/bin/emacs; cwd = repo root.)

const std = @import("std");
const env = @import("env.zig");

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    // Default async_limit is cpu_count-1 (Io.Threaded.init).  On a
    // 2-vCPU Windows runner that is 1, which serializes every concurrent
    // child-process operation back to one -- so the N worker threads'
    // std.process.run calls above would run one-at-a-time and the compile
    // phase never finished within the CI step timeout.  Raise the limit so
    // the parallel spawns actually run concurrently.
    var io_threaded: std.Io.Threaded = .init(gpa, .{
        .async_limit = .unlimited,
        .concurrent_limit = .unlimited,
    });
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    var env_map = try env.inherit(gpa, minimal);
    defer env_map.deinit();

    var arg_it = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer arg_it.deinit();
    _ = arg_it.next(); // argv[0]
    const zeln_compile = arg_it.next() orelse {
        std.debug.print("populate-zeln-cache: missing <zeln-compile-exe> arg\n", .{});
        std.process.exit(2);
    };

    const staging = "zig-out/zeln-cache/staging";

    // ---- (a) serialize phase: emacs --batch -l build-aux/zeln-populate.el.
    // The helper walks lisp/**/*.elc, calls comp-z-write-file-zunit per
    // file (condition-case -> skips on signal), and writes JOBS +
    // SKIPS-LISP.  It exits 0 even when every file skips.
    const ser_argv = [_][]const u8{
        "./zig-out/bin/emacs", "--batch",
        "-l", "build-aux/zeln-populate.el",
    };
    {
        var child = try std.process.spawn(io, .{
            .argv = &ser_argv,
            .environ_map = &env_map,
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        });
        const term = try child.wait(io);
        switch (term) {
            .exited => |code| if (code != 0) {
                std.debug.print("populate-zeln-cache: serialize phase exited {d}\n", .{code});
                std.process.exit(1);
            },
            else => {
                std.debug.print("populate-zeln-cache: serialize phase died\n", .{});
                std.process.exit(1);
            },
        }
    }

    // ---- Read JOBS + SKIPS-LISP. ----
    const jobs_path = "zig-out/zeln-cache/JOBS";
    const skips_lisp_path = "zig-out/zeln-cache/SKIPS-LISP";
    const jobs_data = cwd.readFileAlloc(io, jobs_path, gpa, .limited(16 * 1024 * 1024)) catch |err| {
        std.debug.print("populate-zeln-cache: cannot read JOBS ({s})\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer gpa.free(jobs_data);
    // SKIPS-LISP may legitimately be absent (empty serialize-phase skip
    // list); never free the "" fallback -- it is a string literal, not a
    // heap allocation (freeing it would be UB).
    const skips_lisp_opt = cwd.readFileAlloc(io, skips_lisp_path, gpa, .limited(16 * 1024 * 1024)) catch null;
    defer if (skips_lisp_opt) |sl| gpa.free(sl);
    const skips_lisp = skips_lisp_opt orelse "";

    // ---- (b) compile phase: one zeln-compile per job, per-file tolerant. ----
    var n_compiled: usize = 0;
    var n_skip_emitter: usize = 0;
    var skip_list: std.ArrayList(u8) = .empty;
    defer skip_list.deinit(gpa);

    // Start SKIP-LIST with the serialize-phase skips.
    {
        var sit = std.mem.splitScalar(u8, skips_lisp, '\n');
        while (sit.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            try skip_list.appendSlice(gpa, trimmed);
            try skip_list.append(gpa, '\n');
        }
    }

    // Parse JOBS once.  The field slices point into jobs_data, which stays
    // alive (and read-only) for the whole compile phase, so the worker
    // threads can share it safely.
    var jobs: std.ArrayList(Job) = .empty;
    defer jobs.deinit(gpa);
    {
        var job_it = std.mem.splitScalar(u8, jobs_data, '\n');
        while (job_it.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            // Line format: "zunit\tmanifest\tzeln\telc".
            var fields = std.mem.splitScalar(u8, trimmed, '\t');
            const zunit = fields.next() orelse continue;
            const manifest = fields.next() orelse continue;
            const zeln = fields.next() orelse continue;
            const elc = fields.next() orelse "?";
            try jobs.append(gpa, .{ .zunit = zunit, .manifest = manifest, .zeln = zeln, .elc = elc });
        }
    }
    const n_jobs = jobs.items.len;

    // Compile phase, parallelized.  Each zeln-compile is an independent
    // leaf process (one zunit -> one .zeln, no shared state), so fan out
    // across worker threads.  The big win is Windows -- zig cc startup is
    // ~7s there vs ~0.2s on Linux, and 1000+ serial spawns used to blow
    // the 120-minute CI step timeout -- but Linux/macOS get the same
    // speedup.  Cap workers at 8 to bound peak memory (each zeln-compile
    // loads the full zig toolchain); ZELN_PARALLELISM overrides.
    const worker_count: usize = blk: {
        if (env_map.get("ZELN_PARALLELISM")) |v|
            break :blk std.fmt.parseInt(usize, v, 10) catch 4;
        break :blk @min(std.Thread.getCpuCount() catch 4, 8);
    };
    const results = gpa.alloc(WorkerResult, worker_count) catch @panic("OOM");
    defer gpa.free(results);
    for (results) |*r| r.* = .{};

    if (n_jobs > 0 and worker_count > 1) {
        const threads = gpa.alloc(std.Thread, worker_count) catch @panic("OOM");
        defer gpa.free(threads);
        for (0..worker_count) |w| {
            threads[w] = std.Thread.spawn(.{ .allocator = gpa }, processJobs, .{
                gpa, io, &env_map, zeln_compile, jobs.items, w, worker_count, &results[w],
            }) catch |err| {
                std.debug.print("populate-zeln-cache: thread spawn failed: {s}\n", .{@errorName(err)});
                std.process.exit(1);
            };
        }
        for (threads) |t| t.join();
    } else if (n_jobs > 0) {
        processJobs(gpa, io, &env_map, zeln_compile, jobs.items, 0, 1, &results[0]);
    }

    // Merge per-worker tallies in order.
    for (results) |*r| {
        n_compiled += r.n_compiled;
        n_skip_emitter += r.n_skip_emitter;
        try skip_list.appendSlice(gpa, r.skip_list.items);
        r.skip_list.deinit(gpa);
    }

    // ---- Write SKIP-LIST. ----
    const skip_list_path = "zig-out/zeln-cache/SKIP-LIST";
    try cwd.writeFile(io, .{ .sub_path = skip_list_path, .data = skip_list.items });

    // ---- Coverage ratio. ----
    // Denominator = compiled + emitter-skipped (the set that HAD defuns and
    // reached the emitter); serialize-phase skips (no-source / no-defuns /
    // serialize-error) are reported separately as they never contended for
    // native compilation.
    const attempted: usize = n_compiled + n_skip_emitter;
    const coverage: f64 = if (attempted == 0)
        0.0
    else
        @as(f64, @floatFromInt(n_compiled)) * 100.0 / @as(f64, @floatFromInt(attempted));

    std.debug.print(
        "zeln cache: {d} compiled, {d} skipped ({d:.1}% coverage); {d} serialize-skips\n",
        .{ n_compiled, n_skip_emitter, coverage, countLines(skips_lisp) },
    );

    // ---- Coverage floor. ----
    // Skips are individually legitimate (interpreter fallback), but a
    // CATASTROPHIC fallback (e.g. every zeln-compile failing to spawn the
    // linker, as seen on CI: "zig cc spawn failed: FileNotFound" -> 0 compiled
    // / 100% skipped) must NOT pass silently: the check-zeln suite would then
    // run entirely on the interpreter and report a vacuous 582/582.  Require
    // a minimum share of the contended set to actually compile; a sub-floor
    // run exits non-zero so the gate fails loudly.
    const MIN_COVERAGE_PCT: f64 = 50.0;
    if (attempted > 0 and coverage < MIN_COVERAGE_PCT) {
        std.debug.print(
            "zeln cache: coverage {d:.1}% below floor {d:.0}% ({d} compiled of {d} contended) — " ++
                "failing (a near-total silent fallback would vacate the .zeln gate)\n",
            .{ coverage, MIN_COVERAGE_PCT, n_compiled, attempted },
        );
        std.process.exit(1);
    }

    // Best-effort: drop the staging dir now that .zeln are in place.
    cwd.deleteTree(io, staging) catch {};

    // Exit 0 unconditionally: skips are not failures (interpreter fallback).
    std.process.exit(0);
}

// Map the emitter's stderr to a short reason token.  The dominant case is
// Bswitch (the only genuinely-missing non-obsolete opcode); obsolete
// opcodes and serializer round-trip failures are surfaced verbatim.
fn classifyEmitterReason(stderr: []const u8) []const u8 {
    if (std.mem.indexOf(u8, stderr, "UnsupportedOpcode") != null) return "unsupported-opcode";
    if (std.mem.indexOf(u8, stderr, "zig cc failed") != null) return "link-failed";
    if (std.mem.indexOf(u8, stderr, "emit failed") != null) return "emit-failed";
    if (std.mem.indexOf(u8, stderr, "parse failed") != null) return "parse-failed";
    return "emitter-error";
}

fn countLines(s: []const u8) usize {
    if (s.len == 0) return 0;
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, s, '\n');
    while (it.next()) |line| {
        if (std.mem.trim(u8, line, " \t\r").len > 0) n += 1;
    }
    return n;
}

// ---- Parallel compile phase ---------------------------------------------

/// One JOBS line: "zunit\tmanifest\tzeln\telc".  The slices point into the
/// JOBS buffer, which outlives the whole compile phase (read-only shared).
const Job = struct {
    zunit: []const u8,
    manifest: []const u8,
    zeln: []const u8,
    elc: []const u8,
};

/// Per-worker tallies; merged in order after the threads join.
const WorkerResult = struct {
    n_compiled: usize = 0,
    n_skip_emitter: usize = 0,
    skip_list: std.ArrayList(u8) = .empty,
};

/// Worker body: process JOBS[start], JOBS[start+stride], ... (strided so
/// every worker walks the whole array without locking).  Each job spawns
/// one zeln-compile leaf process and records its outcome locally; errors
/// are swallowed per-file (that IS the tolerance contract), allocation
/// failure just drops the skip-list line.
fn processJobs(
    gpa: std.mem.Allocator,
    io: std.Io,
    env_map: *const std.process.Environ.Map,
    zeln_compile: []const u8,
    jobs: []const Job,
    start: usize,
    stride: usize,
    result: *WorkerResult,
) void {
    var i = start;
    while (i < jobs.len) : (i += stride) {
        const job = jobs[i];
        const cc_argv = [_][]const u8{ zeln_compile, job.zunit, job.manifest, job.zeln };
        const res = std.process.run(gpa, io, .{
            .argv = &cc_argv,
            .environ_map = env_map,
            .stdout_limit = .limited(64 * 1024),
            .stderr_limit = .limited(64 * 1024),
        }) catch |err| {
            // Spawn failure (not an emitter reject): record + continue.
            const msg = std.fmt.allocPrint(gpa, "{s}\tspawn-failed: {s}\n", .{ job.elc, @errorName(err) }) catch return;
            defer gpa.free(msg);
            result.skip_list.appendSlice(gpa, msg) catch {};
            result.n_skip_emitter += 1;
            continue;
        };
        defer gpa.free(res.stdout);
        defer gpa.free(res.stderr);
        if (res.term == .exited and res.term.exited == 0) {
            result.n_compiled += 1;
        } else {
            result.n_skip_emitter += 1;
            // Classify the reason from the emitter's stderr.
            const reason = classifyEmitterReason(res.stderr);
            const msg = std.fmt.allocPrint(gpa, "{s}\t{s}\n", .{ job.elc, reason }) catch return;
            defer gpa.free(msg);
            result.skip_list.appendSlice(gpa, msg) catch {};
        }
    }
}
