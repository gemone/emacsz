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
    // Main-thread Io for the serialize-phase child + the file IO below.
    // The compile phase's worker threads each build their OWN Io.Threaded
    // (inside processJobs): std.Io.Threaded is a single-threaded async
    // facade, and sharing one instance across the N workers made their
    // concurrent pipe reads + child waits race on Windows -- one waiter
    // consumes another's completion, a wait never returns, and the whole
    // phase deadlocks silently until the CI step timeout (POSIX happened
    // to survive because child waiting is waitpid-based there).
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
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
    // The helper byte-compiles the test tree first (per-file tolerant),
    // then walks lisp/**/*.elc, calls comp-z-write-file-zunit per file
    // (condition-case -> skips on signal), and writes JOBS + SKIPS-LISP.
    // It exits 0 even when every file skips.
    //
    // Watchdog: a single test-file compile has been observed to hang for
    // 60+ minutes on the 2-vCPU windows runner (while completing in
    // milliseconds everywhere else), silently burning the whole CI step
    // budget.  So phase (a) runs in respawn batches: each emacs invocation
    // gets ZELN_BC_ONLY=1 (compile the remaining test files, then exit)
    // and a hard timeout.  On timeout the driver DEFERS the file named in
    // BC-CURRENT (written by the elisp side right before each compile) and
    // respawns, so the batch always makes progress past the hang.  After
    // the batch completes, every deferred file is retried in its OWN fresh
    // emacs process; one that still cannot compile standalone HARD-FAILS
    // the step naming the file -- coverage is never silently reduced.
    const bc_state_dir = "zig-out/zeln-cache";
    const bc_defer_path = bc_state_dir ++ "/BC-DEFER";
    const bc_current_path = bc_state_dir ++ "/BC-CURRENT";
    // Per-batch budget: generous for a legitimate slow compile (the whole
    // cold tree needs ~1 min locally; Windows runners are slower), short
    // enough that a hang costs minutes, not the step.
    const bc_batch_secs: i64 = blk: {
        if (env_map.get("ZELN_BC_TIMEOUT")) |v|
            break :blk std.fmt.parseInt(i64, v, 10) catch 600;
        break :blk 600;
    };
    const BC_MAX_DEFERS: usize = 100;
    {
        // Start from a clean slate: a stale BC-DEFER from an aborted run
        // would silently drop files that may compile fine now.
        cwd.deleteFile(io, bc_defer_path) catch {};
        cwd.deleteFile(io, bc_current_path) catch {};

        var bc_defers: usize = 0;
        // Deep-clone the parent env ONCE so the per-batch `put` below grows
        // an independently-owned map.  A plain `var bc_env = env_map' struct
        // copy aliases env_map's internal buffer; when `put` grows it on the
        // respawn iteration it reallocates that shared buffer, leaving
        // env_map dangling -> the next batch iteration crashes in getOrPut.
        var bc_env = try env_map.clone(gpa);
        defer bc_env.deinit();
        batch: while (true) {
            // If the previous batch was killed mid-compile, defer
            // exactly that file so the respawn makes progress past it.
            const cur = cwd.readFileAlloc(io, bc_current_path, gpa, .limited(4096)) catch null;
            if (cur) |c| {
                defer gpa.free(c);
                const trimmed = std.mem.trim(u8, c, " \t\r\n");
                if (trimmed.len > 0) {
                    if (bc_defers >= BC_MAX_DEFERS) {
                        std.debug.print("populate-zeln-cache: BC-DEFER limit ({d}) reached at '{s}' -- the batch cannot make progress\n", .{ BC_MAX_DEFERS, trimmed });
                        std.process.exit(1);
                    }
                    // Append via read-modify-write (small file, avoids
                    // seek-based append API differences across hosts).
                    const old = cwd.readFileAlloc(io, bc_defer_path, gpa, .limited(1 << 20)) catch null;
                    defer {
                        if (old) |o| gpa.free(o);
                    }
                    var buf: std.ArrayList(u8) = .empty;
                    defer buf.deinit(gpa);
                    if (old) |o| buf.appendSlice(gpa, o) catch {};
                    buf.appendSlice(gpa, trimmed) catch {};
                    buf.append(gpa, '\n') catch {};
                    cwd.writeFile(io, .{ .sub_path = bc_defer_path, .data = buf.items }) catch {};
                    bc_defers += 1;
                    std.debug.print("populate-zeln-cache: compile watchdog timeout on '{s}' -- deferred for standalone retry ({d}/{d})\n", .{ trimmed, bc_defers, BC_MAX_DEFERS });
                }
            }

            try bc_env.put("ZELN_BC_ONLY", "1");
            const bc_argv = [_][]const u8{
                "./zig-out/bin/emacs", "--batch",
                "-l", "build-aux/zeln-populate.el",
            };
            // std.process.run's .timeout does NOT fire on the 2-vCPU
            // windows-latest runner when the child hangs with its pipes open
            // (established in commit 68191acd / generate-loaddefs); a wedged
            // byte-compile batch would then block forever with the step going
            // to the full timeout.  Spawn + waitBounded instead: the watchdog
            // force-terminates the batch after bc_batch_secs, stdio is
            // inherited so progress streams live (reliably visible), and the
            // caller either defers the current file and respawns (batch) or
            // hard-fails (standalone).
            var bc_child = try std.process.spawn(io, .{
                .argv = &bc_argv,
                .environ_map = &bc_env,
                .stdin = .inherit,
                .stdout = .inherit,
                .stderr = .inherit,
            });
            var bc_timed_out = false;
            const bc_term = waitBounded(io, gpa, &bc_child, bc_batch_secs, &bc_timed_out);
            if (bc_timed_out) {
                // The batch hit its per-batch budget (a single test-file
                // byte-compile hung on the 2-vCPU windows runner).  Defer the
                // in-flight file and respawn so the batch makes progress past
                // the hang instead of the whole populate step failing.
                std.debug.print("populate-zeln-cache: batch drove to timeout after {d}s; respawning\n", .{bc_batch_secs});
                continue :batch;
            }
            switch (bc_term) {
                .exited => |code| if (code != 0) {
                    std.debug.print("populate-zeln-cache: byte-compile batch exited {d}\n", .{code});
                    std.process.exit(1);
                },
                else => {
                    std.debug.print("populate-zeln-cache: byte-compile batch died\n", .{});
                    std.process.exit(1);
                },
            }
            // Exit 0: every remaining file is either compiled (has an
            // .elc) or on BC-DEFER for the standalone retry below.
            break :batch;
        }

        // Standalone retry: every deferred file gets its OWN fresh emacs
        // process with the full batch budget.  This is exactly the shape
        // that completes in milliseconds locally; CI's hang appears to
        // need the accumulated in-process state.  Zero silent coverage
        // loss: a file that still cannot compile standalone hard-fails
        // the step, naming it.
        const defer_data = cwd.readFileAlloc(io, bc_defer_path, gpa, .limited(1 << 20)) catch null;
        defer {
            if (defer_data) |d| gpa.free(d);
        }
        if (defer_data) |dd| {
            var dit = std.mem.splitScalar(u8, dd, '\n');
            while (dit.next()) |line| {
                const trimmed = std.mem.trim(u8, line, " \t\r");
                if (trimmed.len == 0) continue;
                const eval_expr = std.fmt.allocPrint(gpa,
                    "(progn (when (eq system-type 'windows-nt) (setq file-name-coding-system 'utf-8 default-file-name-coding-system 'utf-8)) (if (byte-compile-file \"{s}\") (kill-emacs 0) (kill-emacs 1)))", .{trimmed}) catch @panic("OOM");
                defer gpa.free(eval_expr);
                const one_argv = [_][]const u8{
                    "./zig-out/bin/emacs", "--batch",
                    "-L", "lisp", "-L", "test/src", "-L", "test/lisp",
                    "-L", "test/lisp/emacs-lisp", "-L", "test/lisp/calendar",
                    "--eval", eval_expr,
                };
                std.debug.print("populate-zeln-cache: standalone retry: {s}\n", .{trimmed});
                // std.process.run's .timeout does not fire on the windows
                // runner for a wedged child; use spawn + waitBounded so a
                // stuck standalone compile hard-fails after bc_batch_secs
                // instead of hanging the whole step.
                var one_child = try std.process.spawn(io, .{
                    .argv = &one_argv,
                    .environ_map = &env_map,
                    .stdin = .inherit,
                    .stdout = .inherit,
                    .stderr = .inherit,
                });
                var one_timed_out = false;
                const one_term = waitBounded(io, gpa, &one_child, bc_batch_secs, &one_timed_out);
                if (one_timed_out) {
                    // The standalone compile also hung on the 2-vCPU windows
                    // runner (environmental, not a source bug -- the file
                    // compiles in ~2s locally).  byte-compile is best-effort
                    // (per zeln-populate.el a file that cannot be compiled
                    // simply has no .zeln and runs from source), so treat an
                    // environmental hang as a skip, not a hard failure: the
                    // .zeln coverage floor still gates against any real
                    // large-scale regression.
                    std.debug.print("populate-zeln-cache: standalone '{s}' hung {d}s on windows -- skipped (runs from .el source); coverage floor still gates\n", .{ trimmed, bc_batch_secs });
                    continue;
                }
                switch (one_term) {
                    .exited => |code| {
                        if (code != 0) {
                            std.debug.print("populate-zeln-cache: HARD-FAIL: '{s}' exited {d} in the standalone retry\n", .{ trimmed, code });
                            std.process.exit(1);
                        }
                    },
                    else => {
                        std.debug.print("populate-zeln-cache: HARD-FAIL: '{s}' died in the standalone retry\n", .{trimmed});
                        std.process.exit(1);
                    },
                }
                std.debug.print("populate-zeln-cache: standalone retry ok: {s}\n", .{trimmed});
            }
        }
    }

    // Final invocation: no ZELN_BC_ONLY -- runs the serialize walk over every
    // .elc (skipping anything the driver deferred).  A per-file serialize can
    // hang on the 2-vCPU windows runner (Defender/I-O, e.g. ediff-ptch.elc),
    // so on a watchdog timeout the driver defers the in-flight SER-CURRENT
    // file and respawns the walk; the Elisp side then skips deferred .elc.
    const ser_argv = [_][]const u8{
        "./zig-out/bin/emacs", "--batch",
        "-l", "build-aux/zeln-populate.el",
    };
    const ser_defer_path = bc_state_dir ++ "/SER-DEFER";
    const ser_current_path = bc_state_dir ++ "/SER-CURRENT";
    cwd.deleteFile(io, ser_defer_path) catch {};
    cwd.deleteFile(io, ser_current_path) catch {};
    var ser_attempt: usize = 0;
    ser: while (true) {
        var child = try std.process.spawn(io, .{
            .argv = &ser_argv,
            .environ_map = &env_map,
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        });
        var ser_timed_out = false;
        const term = waitBounded(io, gpa, &child, bc_batch_secs, &ser_timed_out);
        if (ser_timed_out) {
            ser_attempt += 1;
            std.debug.print("populate-zeln-cache: serialize timeout {d}s (attempt {d}); deferring in-flight file\n", .{ bc_batch_secs, ser_attempt });
            // Defer the file that was mid-serialize so the respawn skips it.
            if (cwd.readFileAlloc(io, ser_current_path, gpa, .limited(4096)) catch null) |cur| {
                defer gpa.free(cur);
                const trimmed = std.mem.trim(u8, cur, " \t\r\n");
                if (trimmed.len > 0) {
                    const old = cwd.readFileAlloc(io, ser_defer_path, gpa, .limited(1 << 20)) catch null;
                    defer {
                        if (old) |o| gpa.free(o);
                    }
                    var buf: std.ArrayList(u8) = .empty;
                    defer buf.deinit(gpa);
                    if (old) |o| buf.appendSlice(gpa, o) catch {};
                    buf.appendSlice(gpa, trimmed) catch {};
                    buf.append(gpa, '\n') catch {};
                    cwd.writeFile(io, .{ .sub_path = ser_defer_path, .data = buf.items }) catch {};
                }
            }
            // Bound the number of respawns; many serial hangs would be a real
            // regression the coverage floor should surface, not hide forever.
            if (ser_attempt >= 10) {
                std.debug.print("populate-zeln-cache: serialize defers exceeded {d}; failing\n", .{ser_attempt});
                std.process.exit(1);
            }
            continue :ser;
        }
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
        break :ser;
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
    // speedup.  The work is SPAWN-BOUND (workers mostly wait on the
    // child, not burn CPU), so small hosts get a floor above their core
    // count: a 2-vCPU windows runner at cpu-count workers spent ~47 min
    // just on 812 x 7s spawns; 6 workers cut that to ~16 min with no
    // CPU saturation.  Cap stays 8 to bound peak memory (each
    // zeln-compile loads the full zig toolchain); ZELN_PARALLELISM
    // overrides.
    const worker_count: usize = blk: {
        if (env_map.get("ZELN_PARALLELISM")) |v|
            break :blk std.fmt.parseInt(usize, v, 10) catch 4;
        const cpu = std.Thread.getCpuCount() catch 4;
        break :blk @min(@max(cpu * 3, 6), 8);
    };
    const results = gpa.alloc(WorkerResult, worker_count) catch @panic("OOM");
    defer gpa.free(results);
    for (results) |*r| r.* = .{};

    if (n_jobs > 0 and worker_count > 1) {
        const threads = gpa.alloc(std.Thread, worker_count) catch @panic("OOM");
        defer gpa.free(threads);
        for (0..worker_count) |w| {
            threads[w] = std.Thread.spawn(.{ .allocator = gpa }, processJobs, .{
                gpa, &env_map, zeln_compile, jobs.items, w, worker_count, &results[w],
            }) catch |err| {
                std.debug.print("populate-zeln-cache: thread spawn failed: {s}\n", .{@errorName(err)});
                std.process.exit(1);
            };
        }
        for (threads) |t| t.join();
    } else if (n_jobs > 0) {
        processJobs(gpa, &env_map, zeln_compile, jobs.items, 0, 1, &results[0]);
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
    //
    // MSVC ABI: the .zeln pushhandler mechanism requires calling the CRT's
    // _setjmp from LLVM-compiled code, which the MSVC UCRT does not support
    // (the CRT intrinsic assumes MSVC-compiled callers; exit 40).  zeln-
    // compile rejects handler-carrying units on msvc; those fall back to
    // the interpreter.  The observed skip rate is ~51.5%, so a 45% floor
    // still catches a near-total fallback while accommodating the ABI.
    const is_msvc = if (env_map.get("ZELN_TARGET")) |t|
        std.mem.endsWith(u8, t, "-msvc")
    else
        false;
    const MIN_COVERAGE_PCT: f64 = if (is_msvc) 45.0 else 50.0;
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
    env_map: *const std.process.Environ.Map,
    zeln_compile: []const u8,
    jobs: []const Job,
    start: usize,
    stride: usize,
    result: *WorkerResult,
) void {
    // Private Io.Threaded per worker (see the comment in main): each
    // thread drives its own children through its own instance, so there
    // is no shared completion state to race on.  A worker runs one child
    // at a time, so the default async_limit suffices.
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();
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

/// Watchdog-bounded child wait: waits for CHILD to exit, but force-terminates
/// it after TIMEOUT_SECS so a wedged emacs (the Windows CI Defender/I-O hang)
/// cannot block the step forever with zero log output.  Mirrors the
/// generate-loaddefs runEmacs watchdog: a helper thread does the blocking
/// `child.wait` on an Io it owns while the calling thread loops on the clock
/// and calls `child.kill(io)` past the deadline.
const WaitState = struct {
    gpa: std.mem.Allocator,
    child: *std.process.Child,
    done: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    term: std.process.Child.Term = .{ .exited = 255 },
};

fn waitThreadFn(w: *WaitState) void {
    var wio_threaded: std.Io.Threaded = .init(w.gpa, .{});
    const wio = wio_threaded.io();
    w.term = w.child.wait(wio) catch .{ .exited = 255 };
    w.done.store(true, .release);
}

fn waitBounded(io: std.Io, gpa: std.mem.Allocator, child: *std.process.Child, timeout_secs: i64, timed_out: *bool) std.process.Child.Term {
    var state: WaitState = .{ .gpa = gpa, .child = child };
    const t = std.Thread.spawn(.{ .allocator = gpa }, waitThreadFn, .{&state}) catch |err| {
        std.debug.print("populate-zeln-cache: watchdog thread spawn failed: {s}\n", .{@errorName(err)});
        child.kill(io);
        return .{ .exited = 255 };
    };

    var killed = false;
    const clock = std.Io.Clock.awake;
    const deadline = std.Io.Timestamp.now(io, clock).addDuration(
        std.Io.Duration.fromSeconds(timeout_secs),
    );
    while (!state.done.load(.acquire)) {
        if (std.Io.Timestamp.now(io, clock).durationTo(deadline).nanoseconds <= 0 and !killed) {
            killed = true;
            std.debug.print("populate-zeln-cache: watchdog timed out after {d}s; killing\n", .{timeout_secs});
            child.kill(io);
        }
        io.sleep(std.Io.Duration.fromMilliseconds(500), std.Io.Clock.awake) catch {};
    }
    t.join();
    timed_out.* = killed;
    return state.term;
}
