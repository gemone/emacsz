// Native Zig replacements for gnulib's lib/gettime.c (gettime +
// current_timespec), the realtime-clock read used throughout temacs.
// Per-platform NATIVE backends, NO libc on either side:
//   Linux   -> std.os.linux.clock_gettime (raw syscall)
//   Windows -> kernel32 GetSystemTimeAsFileTime (no msvcrt/CRT)
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
            var ft: w.FILETIME = undefined;
            w.kernel32.GetSystemTimeAsFileTime(&ft);
            const ticks: u64 = (@as(u64, ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
            const unix_100ns: i64 = @as(i64, @bitCast(ticks)) -% WINDOWS_EPOCH_DELTA_100NS;
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
