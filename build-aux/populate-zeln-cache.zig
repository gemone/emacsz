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
    const skips_lisp = cwd.readFileAlloc(io, skips_lisp_path, gpa, .limited(16 * 1024 * 1024)) catch "";
    defer gpa.free(skips_lisp);

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

        const cc_argv = [_][]const u8{ zeln_compile, zunit, manifest, zeln };
        const res = std.process.run(gpa, io, .{
            .argv = &cc_argv,
            .environ_map = &env_map,
            .stdout_limit = .limited(64 * 1024),
            .stderr_limit = .limited(64 * 1024),
        }) catch |err| {
            // Spawn failure (not an emitter reject): record + continue.
            const msg = try std.fmt.allocPrint(gpa, "{s}\tspawn-failed: {s}\n", .{ elc, @errorName(err) });
            defer gpa.free(msg);
            try skip_list.appendSlice(gpa, msg);
            n_skip_emitter += 1;
            continue;
        };
        const ok = (res.term == .exited and res.term.exited == 0);
        if (ok) {
            n_compiled += 1;
        } else {
            n_skip_emitter += 1;
            // Classify the reason from the emitter's stderr.
            const reason = classifyEmitterReason(res.stderr);
            const msg = try std.fmt.allocPrint(gpa, "{s}\t{s}\n", .{ elc, reason });
            defer gpa.free(msg);
            try skip_list.appendSlice(gpa, msg);
        }
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
