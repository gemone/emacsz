// Native Zig implementation of gnulib's lib/sigdescr_np.c: a
// platform-specific description string for a signal number (used by
// src/sysdep.c's safe_strsignal for error output). The per-platform case
// sets mirror the C #ifdefs in the gnulib source exactly (aliased names
// like SIGIOT==SIGABRT or SIGIO==SIGPOLL are excluded there, so they are
// excluded here too). Pure static data; no libc call, no std import.

const builtin = @import("builtin");

// ISO C and POSIX signals plus the Linux-only extras (SIGPWR, SIGSTKFLT).
// SIGCLD==SIGCHLD, SIGIO==SIGPOLL and SIGIOT==SIGABRT are aliases on
// glibc, so their C cases are not compiled and the canonical names win.
fn linuxDesc(sig: c_int) ?[*:0]const u8 {
    return switch (sig) {
        6 => "Aborted",
        8 => "Arithmetic exception",
        4 => "Illegal instruction",
        2 => "Interrupt",
        11 => "Segmentation fault",
        15 => "Terminated",
        14 => "Alarm clock",
        7 => "Bus error",
        17 => "Child stopped or exited",
        18 => "Continued",
        1 => "Hangup",
        9 => "Killed",
        13 => "Broken pipe",
        3 => "Quit",
        19 => "Stopped (signal)",
        20 => "Stopped",
        21 => "Stopped (tty input)",
        22 => "Stopped (tty output)",
        10 => "User defined signal 1",
        12 => "User defined signal 2",
        29 => "I/O possible",
        27 => "Profiling timer expired",
        31 => "Bad system call",
        5 => "Trace/breakpoint trap",
        23 => "Urgent I/O condition",
        26 => "Virtual timer expired",
        24 => "CPU time limit exceeded",
        25 => "File size limit exceeded",
        30 => "Power failure",
        16 => "Stack fault",
        28 => "Window size changed",
        else => null,
    };
}

// Native Windows (mingw): ISO C signals plus SIGBREAK.
fn windowsDesc(sig: c_int) ?[*:0]const u8 {
    return switch (sig) {
        22 => "Aborted",
        8 => "Arithmetic exception",
        4 => "Illegal instruction",
        2 => "Interrupt",
        11 => "Segmentation fault",
        15 => "Terminated",
        21 => "Ctrl-Break",
        else => null,
    };
}

// Darwin: ISO C and POSIX signals plus SIGEMT, SIGINFO, SIGIO and
// SIGWINCH. SIGIOT==SIGABRT is an alias, so only ABRT appears.
fn darwinDesc(sig: c_int) ?[*:0]const u8 {
    return switch (sig) {
        6 => "Aborted",
        8 => "Arithmetic exception",
        4 => "Illegal instruction",
        2 => "Interrupt",
        11 => "Segmentation fault",
        15 => "Terminated",
        14 => "Alarm clock",
        10 => "Bus error",
        20 => "Child stopped or exited",
        19 => "Continued",
        1 => "Hangup",
        9 => "Killed",
        13 => "Broken pipe",
        3 => "Quit",
        17 => "Stopped (signal)",
        18 => "Stopped",
        21 => "Stopped (tty input)",
        22 => "Stopped (tty output)",
        30 => "User defined signal 1",
        31 => "User defined signal 2",
        27 => "Profiling timer expired",
        12 => "Bad system call",
        5 => "Trace/breakpoint trap",
        16 => "Urgent I/O condition",
        26 => "Virtual timer expired",
        24 => "CPU time limit exceeded",
        25 => "File size limit exceeded",
        7 => "Instruction emulation needed",
        29 => "Information request",
        23 => "I/O possible",
        28 => "Window size changed",
        else => null,
    };
}

// Return a description of signal SIG, or NULL if unknown.
pub export fn sigdescr_np(sig: c_int) ?[*:0]const u8 {
    return switch (builtin.os.tag) {
        .linux => linuxDesc(sig),
        .windows => windowsDesc(sig),
        .macos, .ios, .tvos, .watchos, .visionos => darwinDesc(sig),
        else => @compileError("gnulib-sigdescr-np: no signal description table for this OS"),
    };
}
