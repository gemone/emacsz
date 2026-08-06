//! Native Zig replacement for the check-step shell script in build.zig:
//! run the built-in ert suites with the dumped emacs. No shell. Raises
//! the stack limit first (the shell's `ulimit -s unlimited`: -O0 eval
//! frames are large), then runs temacs with the suite list; a genuine
//! ert failure exits < 128 and is not retried, while signal death (the
//! pdumper relocation flake) is retried like the shell did. Run with
//! cwd = repo root.

const std = @import("std");

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

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();

    // -O0 eval frames are large; raise the stack limit so the ert-deftest
    // macro expansion does not overflow the C stack (ulimit -s unlimited).
    std.posix.setrlimit(.STACK, .{
        .cur = std.posix.RLIM.INFINITY,
        .max = std.posix.RLIM.INFINITY,
    }) catch {};

    var eval: std.ArrayList(u8) = .empty;
    defer eval.deinit(gpa);
    try eval.appendSlice(gpa, "(progn (load \"cl-macs\") (load \"cl-seq\") (load \"cl-extra\") (require (quote ert)) ");
    for (test_files) |f| {
        if (std.mem.eql(u8, f, "cl-macs") or std.mem.eql(u8, f, "cl-seq") or std.mem.eql(u8, f, "cl-extra"))
            continue;
        try eval.appendSlice(gpa, "(load \"");
        try eval.appendSlice(gpa, f);
        try eval.appendSlice(gpa, "\") ");
    }
    try eval.appendSlice(gpa, "(let ((ert-batch-print-lines 0)) (ert-run-tests-batch-and-exit (quote (not (or (tag :expensive-test) (tag :unstable) (tag :nativecomp)))))))");

    const argv = [_][]const u8{
        "./zig-out/bin/temacs",
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
