//! Native Zig replacement for the check-step shell script in build.zig:
//! run the built-in ert suites with the dumped emacs. No shell. Raises
//! the stack limit first (the shell's `ulimit -s unlimited`: -O0 eval
//! frames are large), then runs temacs with the suite list; a genuine
//! ert failure exits < 128 and is not retried, while signal death (the
//! pdumper relocation flake) is retried like the shell did. Run with
//! cwd = repo root.

const std = @import("std");
const aslr = @import("aslr.zig");
const builtin = @import("builtin");
const env = @import("env.zig");
const temacs_path = @import("temacs-path.zig");

const test_files = [_][]const u8{
    "cl-macs",         "cl-seq",        "cl-extra",       "alloc-tests",
    "version-tests",   "byte-run-tests", "float-sup-tests", "cl-preloaded-tests",
    "button-tests",    "delim-col-tests", "color-tests",   "custom-tests",
    "dom-tests",       "data-tests",    "marker-tests",   "chartab-tests",
    "cmds-tests",      "let-alist-tests", "cl-lib-tests",  "map-tests",
    "seq-tests",       "character-tests", "charset-tests", "json-tests",
    "fns-tests",       "backquote-tests", "parse-time-tests", "derived-tests",
    "cond-star-tests", "cl-print-tests", "time-date-tests", "check-declare-tests",
    "copyright-tests", "easy-mmode-tests", "nadvice-tests", "pcase-tests",
    "pp-tests",        "ring-tests",   "rx-tests",        "warnings-tests",
    "regexp-opt-tests", "range-tests", "crypto-hash-tests",
};

pub fn main(minimal: std.process.Init.Minimal) !void {
    aslr.disableAslr();
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    // Copy the parent environment: POSIX spawns otherwise pass an empty
    // environment, dropping TMPDIR/PATH from the test session.
    var env_map = try env.inherit(gpa, minimal);
    defer env_map.deinit();
    // Match the dump/compile/smoke tools and force the C locale for a
    // deterministic run, so test inputs (e.g. the UTF-8 string literals in
    // character-tests.el) decode identically on every host.  Without this a
    // non-C host locale makes string-width disagree with the expected
    // values (character-test-string-width failed under a zh-CN host).
    try env_map.put("LC_ALL", "C");

    // -O0 eval frames are large; raise the stack limit so the ert-deftest
    // macro expansion does not overflow the C stack (ulimit -s unlimited).
    if (comptime builtin.os.tag != .windows) {
        std.posix.setrlimit(.STACK, .{
            .cur = std.posix.RLIM.INFINITY,
            .max = std.posix.RLIM.INFINITY,
        }) catch {};
    }

    var eval: std.ArrayList(u8) = .empty;
    defer eval.deinit(gpa);
    try eval.appendSlice(gpa, "(progn ");
    // M2b check-zeln gate: if ZELN_LOAD_PATH is set, point the .zeln cache
    // at it so the dumped emacs transparently swaps .elc -> .zeln where
    // compiled (and falls through to the interpreter where skipped).  The
    // SAME test list / ert selector as the off-path `check' run, so the
    // two summaries are directly comparable (behavioral-identity proof).
    // Gate-#2 genuine-run instrumentation: the run FAILS when
    // `zeln-load-count' is still 0 after the suite, so a cache with zero
    // usable .zeln (e.g. every link failed) can no longer pass this gate
    // via silent interpreter fallback.
    var zeln_gate = false;
    if (env_map.get("ZELN_LOAD_PATH")) |zp| {
        if (zp.len > 0) {
            zeln_gate = true;
            try eval.appendSlice(gpa, "(setq native-comp-zeln-load-path (list (expand-file-name \"");
            try eval.appendSlice(gpa, zp);
            try eval.appendSlice(gpa, "\"))) ");
        }
    }
    try eval.appendSlice(gpa, "(load \"cl-macs\") (load \"cl-seq\") (load \"cl-extra\") (require (quote ert)) ");
    for (test_files) |f| {
        if (std.mem.eql(u8, f, "cl-macs") or std.mem.eql(u8, f, "cl-seq") or std.mem.eql(u8, f, "cl-extra"))
            continue;
        try eval.appendSlice(gpa, "(load \"");
        try eval.appendSlice(gpa, f);
        try eval.appendSlice(gpa, "\") ");
    }
    // ert-run-tests-batch-and-exit calls kill-emacs itself, so when the
    // zeln gate is on we use ert-run-tests-batch and compute the exit code
    // manually: 0 = suite passed AND at least one .zeln was genuinely
    // loaded; 1 = unexpected results OR a silent interpreter fallback
    // (zeln-load-count still 0, e.g. every cache link failed).
    if (zeln_gate) {
        try eval.appendSlice(gpa, " (let ((stats (ert-run-tests-batch (quote (not (or (tag :expensive-test) (tag :unstable) (tag :nativecomp)))))))");
        try eval.appendSlice(gpa, " (princ (format \"\\nzeln-load-count: %d\\n\" zeln-load-count))");
        try eval.appendSlice(gpa, " (if (zerop (ert-stats-completed-unexpected stats)) (if (zerop zeln-load-count) (progn (princ \"check-zeln: FAIL - no .zeln loaded (silent interpreter fallback); populate-zeln-cache produced no usable artifacts\\n\") (kill-emacs 1)) (kill-emacs 0)) (kill-emacs 1))))");
    } else {
        try eval.appendSlice(gpa, " (ert-run-tests-batch-and-exit (quote (not (or (tag :expensive-test) (tag :unstable) (tag :nativecomp))))))");
    }

    const argv = [_][]const u8{
        "./zig-out/bin/" ++ temacs_path.name,
        "--batch",
        "-L", "test/src",
        "-L", "test/lisp",
        "-L", "test/lisp/emacs-lisp",
        "-L", "test/lisp/calendar",
        "--dump-file=./zig-out/bin/bootstrap-emacs.pdmp",
        "--eval", eval.items,
    };

    var attempt: usize = 0;
    while (true) : (attempt += 1) {
        var child = try std.process.spawn(io, .{
            .argv = &argv,
            .environ_map = &env_map,
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        });
        const term = try child.wait(io);
        switch (term) {
            .exited => |code| {
                // A genuine test failure (exit < 128) is final; signal
                // death is the pdumper relocation flake and is retried.
                if (code == 0 or code < 128) std.process.exit(code);
                std.debug.print("check: temacs died with signal ({d}) on attempt {d}/3; retrying (pdumper relocation flakiness)\n", .{ code, attempt + 1 });
            },
            .signal => |sig| {
                std.debug.print("check: temacs died with signal {d} on attempt {d}/3; retrying (pdumper relocation flakiness)\n", .{ @intFromEnum(sig), attempt + 1 });
            },
            else => std.process.exit(1),
        }
        if (attempt >= 2) std.process.exit(1);
    }
}
