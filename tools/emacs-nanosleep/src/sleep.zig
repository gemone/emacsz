// Native Zig replacement for gnulib's lib/nanosleep.c, the POSIX
// nanosleep() used by temacs (e.g. src/gnutls.c:652 pauses between TLS
// handshake retries). Per-platform NATIVE backends, NO libc on either
// side:
//   Linux   -> std.os.linux.nanosleep (raw syscall, EINTR-aware)
//   Windows -> kernel32 Sleep for the ms part + a QueryPerformanceCounter
//              busy-wait for the sub-ms remainder (Sleep is not
//              interruptible, so rmtp is zeroed -- same as gnulib).
// Signature/semantics match the C `int nanosleep (const struct timespec
// *rqtp, struct timespec *rmtp)`: returns 0 on success, -1 on
// interrupt/error. The kernel writes *rmtp on EINTR directly via the
// syscall pointer, so the remaining-time semantics are preserved without
// libc.

const std = @import("std");
const builtin = @import("builtin");

// Matches C `struct timespec` on Linux/Windows x86-64
// (time_t tv_sec; long tv_nsec;) -- 16 bytes. Identical layout to
// std.os.linux.timespec (sec/nsec, both isize), so the two may be
// reinterpreted via @ptrCast.
pub const timespec = extern struct {
    tv_sec: isize,
    tv_nsec: isize,
};

const BILLION: isize = 1_000_000_000;

// Suspend execution for at least *RQTP. On interrupt, the kernel writes
// the remaining time to *RMTP (if non-NULL) and the call returns -1.
// Returns 0 on success. Invalid nsec is rejected as -1 (mirrors gnulib
// + the kernel's own EINVAL check). libc-free: errno is not set -- the
// only temacs call site (src/gnutls.c:652) ignores the return value and
// passes RMTP=NULL.
//
// The symbol is `rpl_nanosleep` (not `nanosleep`) because gnulib's
// lib/time.h unconditionally `#define nanosleep rpl_nanosleep`, so every
// C call site (gnutls.c includes <time.h>) references the rpl_-prefixed
// name -- exactly the symbol the C lib/nanosleep.c emits.
export fn rpl_nanosleep(rqtp: *const timespec, rmtp: ?*timespec) c_int {
    // Reject invalid nsec up front, matching gnulib + the kernel.
    if (rqtp.tv_nsec < 0 or rqtp.tv_nsec >= BILLION) return -1;

    switch (builtin.os.tag) {
        .linux => return nanosleepLinux(rqtp, rmtp),
        .windows => return nanosleepWindows(rqtp, rmtp),
        else => @compileError(
            "emacs-nanosleep: nanosleep not implemented for this OS",
        ),
    }
}

fn nanosleepLinux(rqtp: *const timespec, rmtp: ?*timespec) c_int {
    const linux = std.os.linux;
    // std.os.linux.timespec (sec/nsec) shares the extern layout of our
    // C timespec (tv_sec/tv_nsec) -- both are {isize, isize} -- so the
    // raw syscall can consume the caller's pointer directly.
    const kreq: *const linux.timespec = @ptrCast(rqtp);
    const krem: ?*linux.timespec = if (rmtp) |r| @ptrCast(r) else null;
    const rc = linux.nanosleep(kreq, krem);
    if (rc == 0) return 0;
    // Raw syscall returns a positive errno on failure; map to the C
    // convention (-1). On EINTR the kernel has already written *krem,
    // so the caller's *rmtp carries the remaining time.
    return -1;
}

// Windows kernel32 externs (not pre-declared by std.os.windows in
// 0.16.0). Standard kernel32 ABI, no msvcrt/CRT.
extern "kernel32" fn Sleep(
    dwMilliseconds: std.os.windows.DWORD,
) callconv(.winapi) void;
extern "kernel32" fn QueryPerformanceCounter(
    lpPerformanceCount: *std.os.windows.LARGE_INTEGER,
) callconv(.winapi) std.os.windows.BOOL;
extern "kernel32" fn QueryPerformanceFrequency(
    lpFrequency: *std.os.windows.LARGE_INTEGER,
) callconv(.winapi) std.os.windows.BOOL;

fn nanosleepWindows(rqtp: *const timespec, rmtp: ?*timespec) c_int {
    const w = std.os.windows;

    if (rqtp.tv_sec < 0) {
        if (rmtp) |r| r.* = .{ .tv_sec = 0, .tv_nsec = 0 };
        return -1;
    }

    // Total delay in nanoseconds (i128 to avoid overflow at ~292 years).
    const total_ns: i128 =
        @as(i128, rqtp.tv_sec) * 1_000_000_000 + @as(i128, rqtp.tv_nsec);
    if (total_ns <= 0) {
        if (rmtp) |r| r.* = .{ .tv_sec = 0, .tv_nsec = 0 };
        return 0;
    }

    var freq: w.LARGE_INTEGER = 0;
    const have_qpc = QueryPerformanceFrequency(&freq).toBool() and (freq > 0);

    // Sub-second delay with a working high-res counter: the gnulib
    // pattern -- record an absolute QPC target, Sleep for the bulk
    // (minus a slop margin), then busy-wait the remainder against the
    // target. The absolute target makes Sleep's duration irrelevant to
    // accuracy (the spin absorbs the slack).
    if (rqtp.tv_sec == 0 and have_qpc) {
        var before: w.LARGE_INTEGER = 0;
        if (QueryPerformanceCounter(&before).toBool()) {
            // wait_ticks = total_ns * (freq / 1e9); compute in i128.
            const wait_ticks: i128 = @divTrunc(
                total_ns * @as(i128, freq),
                1_000_000_000,
            );
            const wait_until: i128 = @as(i128, before) + wait_ticks;
            // Sleep can take up to ~8 ms more or less than requested,
            // so leave a margin (gnulib subtracts 10 ms).
            const sleep_ms: i64 =
                @divTrunc(@as(i64, @intCast(rqtp.tv_nsec)), 1_000_000) - 10;
            if (sleep_ms > 0) {
                const ms: w.DWORD = @intCast(sleep_ms);
                Sleep(ms);
            }
            // Busy-wait the rest until the absolute QPC target.
            while (true) {
                var after: w.LARGE_INTEGER = 0;
                if (!QueryPerformanceCounter(&after).toBool()) break;
                if (@as(i128, after) >= wait_until) break;
            }
            if (rmtp) |r| r.* = .{ .tv_sec = 0, .tv_nsec = 0 };
            return 0;
        }
    }

    // Long delays (>= 1 s) or QPC fallback: ms-resolution Sleep covers
    // the full request. Clamp the i128 millisecond count to DWORD.
    const total_ms: i128 = @divTrunc(total_ns, 1_000_000);
    const ms: w.DWORD = if (total_ms > @as(i128, std.math.maxInt(w.DWORD)))
        std.math.maxInt(w.DWORD)
    else
        @intCast(total_ms);
    Sleep(ms);

    // Sleep is not interruptible: no remaining time.
    if (rmtp) |r| r.* = .{ .tv_sec = 0, .tv_nsec = 0 };
    return 0;
}
