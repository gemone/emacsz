// Native Zig replacements for gnulib's lib/gettime.c (gettime +
// current_timespec), the realtime-clock read used throughout temacs.
// Per-platform NATIVE backends, NO libc on either side:
//   Linux   -> std.os.linux.clock_gettime (raw syscall)
//   Windows -> ntdll RtlGetSystemTimePrecise (no msvcrt/CRT)
// Returns C `struct timespec` (extern struct, layout-compatible).

const std = @import("std");
const builtin = @import("builtin");

// Matches C `struct timespec` on Linux/Windows x86-64
// (time_t tv_sec; long tv_nsec;) -- 16 bytes.
pub const timespec = extern struct {
    tv_sec: isize,
    tv_nsec: isize,
};

const WINDOWS_EPOCH_DELTA_100NS: i64 = 116444736000000000; // 1601-01-01 -> 1970-01-01 in 100ns ticks.

// Get the realtime clock into *TS.
export fn gettime(ts: *timespec) void {
    switch (builtin.os.tag) {
        .linux => {
            const linux = std.os.linux;
            const lts: *linux.timespec = @ptrCast(ts);
            // clock_gettime never fails for CLOCK_REALTIME on a working
            // Linux kernel, but zero out defensively if it does.
            if (linux.clock_gettime(.REALTIME, lts) != 0)
                ts.* = .{ .tv_sec = 0, .tv_nsec = 0 };
        },
        .windows => {
            const w = std.os.windows;
            // RtlGetSystemTimePrecise returns 100ns ticks since 1601-01-01
            // (FILETIME's units, without the struct split). Zig 0.16 std
            // declares this ntdll form; kernel32.GetSystemTimeAsFileTime is
            // NOT in std, so the ntdll form is what actually links.
            const ticks: i64 = w.ntdll.RtlGetSystemTimePrecise();
            const unix_100ns: i64 = ticks -% WINDOWS_EPOCH_DELTA_100NS;
            ts.tv_sec = @divTrunc(unix_100ns, 10000000);
            ts.tv_nsec = @rem(unix_100ns, 10000000) * 100;
        },
        else => @compileError("emacs-time: gettime not implemented for this OS"),
    }
}

// Return the current realtime as a struct timespec.
export fn current_timespec() timespec {
    var ts: timespec = undefined;
    gettime(&ts);
    return ts;
}

// Return the current monotonic time as a struct timespec, with an
// Emacs-instance-local epoch (e.g. system boot). The clock is unaffected
// by changes to the system time and cheap to read; its resolution suits
// human time scales (better than ~10 ms is fine). Falls back to realtime
// (current_timespec) if no monotonic source is available.
//
// Replaces src/timefns.c:monotonic_coarse_timespec. Per-platform NATIVE
// backends, NO libc:
//   Linux   -> std.os.linux.clock_gettime(.MONOTONIC_COARSE), falling
//              back to .MONOTONIC, then to current_timespec() (the
//              realtime read above). MONOTONIC_COARSE is a vsyscall-free
//              fast path with coarse (~ms) resolution.
//   Windows -> kernel32/ntdll QueryPerformanceCounter (the monotonic
//              high-resolution clock; epoch fixed at boot, unaffected by
//              system-time changes) converted to sec/nsec via
//              QueryPerformanceFrequency. QPC is Windows' only monotonic
//              source (no CLOCK_MONOTONIC). Falls back to realtime if QPC
//              is unavailable (it never fails on XP+).
export fn monotonic_coarse_timespec() timespec {
    var ts: timespec = undefined;
    switch (builtin.os.tag) {
        .linux => {
            const linux = std.os.linux;
            const lts: *linux.timespec = @ptrCast(&ts);
            // Prefer the coarse clock (fast, vsyscall-free, ms-scale
            // resolution suited to human time scales), then the finer
            // monotonic clock, then realtime as a last resort -- matching
            // the priority of the C original.
            if (linux.clock_gettime(.MONOTONIC_COARSE, lts) == 0)
                return ts;
            if (linux.clock_gettime(.MONOTONIC, lts) == 0)
                return ts;
            return current_timespec();
        },
        .windows => {
            const w = std.os.windows;
            var freq: w.LARGE_INTEGER = undefined;
            var counter: w.LARGE_INTEGER = undefined;
            // QPC is Windows' monotonic clock; ntdll's Rtl* forms are the
            // actual implementations (kernel32's are thin wrappers) and
            // are what Zig's own std uses. They never fail on XP+, but if
            // one did, fall back to realtime like the C version does.
            if (!w.ntdll.RtlQueryPerformanceFrequency(&freq).toBool() or
                !w.ntdll.RtlQueryPerformanceCounter(&counter).toBool())
            {
                return current_timespec();
            }
            // freq > 0 and counter >= 0 always (boot-origin monotonic).
            // tv_sec = counter / freq; tv_nsec = (counter % freq) * 1e9 /
            // freq. The remainder is < freq, so for any real QPC frequency
            // (<= ~1e8) the product stays far within i64 range.
            const freq_i: i64 = freq;
            const counter_i: i64 = counter;
            ts.tv_sec = @divTrunc(counter_i, freq_i);
            const rem: i64 = @rem(counter_i, freq_i);
            ts.tv_nsec = @divTrunc(rem * 1_000_000_000, freq_i);
            return ts;
        },
        else => @compileError(
            "emacs-time: monotonic_coarse_timespec not implemented for this OS",
        ),
    }
}
