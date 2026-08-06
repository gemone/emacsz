// Native Zig replacement for gnulib's lib/sig2str.c: conversion between
// signal names and numbers (sig2str / str2sig), used by src/process.c
// (signal-names, process-send-signal). Pure table + string handling,
// no libc call.
//
// The signal tables and RTMIN/RTMAX bounds are generated per platform
// from the same <signal.h> definitions gnulib's C file is compiled
// against:
//   Linux glibc   NSIG 65, SIGRTMIN 34, SIGRTMAX 64
//   Linux musl    NSIG 65, SIGRTMIN 35, SIGRTMAX 64
//   Windows       NSIG 23, no RT signals
//   Darwin        NSIG 32, no RT signals
// The tables preserve gnulib's ordering exactly, since the first match
// wins for aliased numbers (e.g. ABRT before IOT, CHLD before CLD,
// POLL before IO on Linux).

const std = @import("std");
const builtin = @import("builtin");

const SignalName = struct { num: c_int, name: [:0]const u8 };

const linux_table = [_]SignalName{
    .{ .num = 1, .name = "HUP" },
    .{ .num = 2, .name = "INT" },
    .{ .num = 3, .name = "QUIT" },
    .{ .num = 4, .name = "ILL" },
    .{ .num = 5, .name = "TRAP" },
    .{ .num = 6, .name = "ABRT" },
    .{ .num = 8, .name = "FPE" },
    .{ .num = 9, .name = "KILL" },
    .{ .num = 11, .name = "SEGV" },
    .{ .num = 7, .name = "BUS" },
    .{ .num = 13, .name = "PIPE" },
    .{ .num = 14, .name = "ALRM" },
    .{ .num = 15, .name = "TERM" },
    .{ .num = 10, .name = "USR1" },
    .{ .num = 12, .name = "USR2" },
    .{ .num = 17, .name = "CHLD" },
    .{ .num = 23, .name = "URG" },
    .{ .num = 19, .name = "STOP" },
    .{ .num = 20, .name = "TSTP" },
    .{ .num = 18, .name = "CONT" },
    .{ .num = 21, .name = "TTIN" },
    .{ .num = 22, .name = "TTOU" },
    .{ .num = 31, .name = "SYS" },
    .{ .num = 29, .name = "POLL" },
    .{ .num = 26, .name = "VTALRM" },
    .{ .num = 27, .name = "PROF" },
    .{ .num = 24, .name = "XCPU" },
    .{ .num = 25, .name = "XFSZ" },
    .{ .num = 6, .name = "IOT" },
    .{ .num = 17, .name = "CLD" },
    .{ .num = 30, .name = "PWR" },
    .{ .num = 28, .name = "WINCH" },
    .{ .num = 29, .name = "IO" },
    .{ .num = 16, .name = "STKFLT" },
    .{ .num = 0, .name = "EXIT" },
};

const windows_table = [_]SignalName{
    .{ .num = 2, .name = "INT" },
    .{ .num = 4, .name = "ILL" },
    .{ .num = 22, .name = "ABRT" },
    .{ .num = 8, .name = "FPE" },
    .{ .num = 11, .name = "SEGV" },
    .{ .num = 15, .name = "TERM" },
    .{ .num = 21, .name = "BREAK" },
    .{ .num = 0, .name = "EXIT" },
};

const darwin_table = [_]SignalName{
    .{ .num = 1, .name = "HUP" },
    .{ .num = 2, .name = "INT" },
    .{ .num = 3, .name = "QUIT" },
    .{ .num = 4, .name = "ILL" },
    .{ .num = 5, .name = "TRAP" },
    .{ .num = 6, .name = "ABRT" },
    .{ .num = 8, .name = "FPE" },
    .{ .num = 9, .name = "KILL" },
    .{ .num = 11, .name = "SEGV" },
    .{ .num = 10, .name = "BUS" },
    .{ .num = 13, .name = "PIPE" },
    .{ .num = 14, .name = "ALRM" },
    .{ .num = 15, .name = "TERM" },
    .{ .num = 30, .name = "USR1" },
    .{ .num = 31, .name = "USR2" },
    .{ .num = 20, .name = "CHLD" },
    .{ .num = 16, .name = "URG" },
    .{ .num = 17, .name = "STOP" },
    .{ .num = 18, .name = "TSTP" },
    .{ .num = 19, .name = "CONT" },
    .{ .num = 21, .name = "TTIN" },
    .{ .num = 22, .name = "TTOU" },
    .{ .num = 12, .name = "SYS" },
    .{ .num = 26, .name = "VTALRM" },
    .{ .num = 27, .name = "PROF" },
    .{ .num = 24, .name = "XCPU" },
    .{ .num = 25, .name = "XFSZ" },
    .{ .num = 6, .name = "IOT" },
    .{ .num = 7, .name = "EMT" },
    .{ .num = 20, .name = "CLD" },
    .{ .num = 28, .name = "WINCH" },
    .{ .num = 29, .name = "INFO" },
    .{ .num = 23, .name = "IO" },
    .{ .num = 0, .name = "EXIT" },
};

const table: []const SignalName = switch (builtin.os.tag) {
    .linux => &linux_table,
    .windows => &windows_table,
    .macos, .ios, .tvos, .watchos, .visionos => &darwin_table,
    else => @compileError("gnulib-sig2str: no signal table for this OS"),
};

// SIGNUM_BOUND mirrors gnulib's sig2str.h: NSIG - 1 (or the platform
// _sys_nsig/_SIG_MAXSIG variants). Used by callers (src/process.c
// signal-names iterates 0..SIGNUM_BOUND).
pub const SIGNUM_BOUND: c_int = switch (builtin.os.tag) {
    .linux => 64,
    .windows => 22,
    .macos, .ios, .tvos, .watchos, .visionos => 31,
    else => @compileError("gnulib-sig2str: no SIGNUM_BOUND for this OS"),
};

const RtBounds = struct {
    min: c_int,
    max: c_int,
};

const rt_bounds: RtBounds = switch (builtin.os.tag) {
    .linux => switch (builtin.target.abi) {
        .musl => .{ .min = 35, .max = 64 },
        else => .{ .min = 34, .max = 64 },
    },
    .windows => .{ .min = 0, .max = -1 },
    .macos, .ios, .tvos, .watchos, .visionos => .{ .min = 0, .max = -1 },
    else => @compileError("gnulib-sig2str: no RT bounds for this OS"),
};

// Decimal parse with strtol's observable behavior for the limited
// inputs sig2str feeds it: all bytes must be digits, no sign (the
// first byte is guaranteed a digit) and overflow fails. Returns null
// when the string is not a pure decimal number.
fn parseDecimal(s: []const u8) ?i64 {
    if (s.len == 0) return null;
    var v: i64 = 0;
    for (s) |c| {
        if (c < '0' or c > '9') return null;
        const d: i64 = c - '0';
        if (v > (@divTrunc(std.math.maxInt(i64) - d, 10))) return null;
        v = v * 10 + d;
    }
    return v;
}

// strtol on a possibly-signed tail (e.g. "+2", "-3"); every byte must
// be consumed. Returns null on failure.
fn parseSignedTail(s: []const u8) ?i64 {
    // strtol("") performs no conversion, returns 0 with endp at the
    // NUL terminator, so a bare "RTMIN"/"RTMAX" tail is valid (0).
    if (s.len == 0) return 0;
    if (s[0] == '+') return parseDecimal(s[1..]);
    if (s[0] == '-') {
        const abs = parseDecimal(s[1..]) orelse return null;
        return -abs;
    }
    return parseDecimal(s);
}

fn copyName(dst: [*:0]u8, name: [:0]const u8) void {
    std.mem.copyForwards(u8, dst[0..name.len], name);
    dst[name.len] = 0;
}

fn str2signum(signame: []const u8) c_int {
    // Numeric form: a string starting with a digit, parsed as decimal,
    // must end right after the number and be <= SIGNUM_BOUND.
    if (signame.len > 0 and signame[0] >= '0' and signame[0] <= '9') {
        const n = parseDecimal(signame) orelse return -1;
        if (n <= SIGNUM_BOUND)
            return @intCast(n);
        return -1;
    }

    for (table) |e| {
        if (std.mem.eql(u8, e.name, signame))
            return e.num;
    }

    const rtmin = rt_bounds.min;
    const rtmax = rt_bounds.max;
    if (rtmin > 0 and std.mem.startsWith(u8, signame, "RTMIN")) {
        const n = parseSignedTail(signame[5..]) orelse return -1;
        if (0 <= n and n <= rtmax - rtmin)
            return rtmin + @as(c_int, @intCast(n));
    } else if (rtmax > 0 and std.mem.startsWith(u8, signame, "RTMAX")) {
        const n = parseSignedTail(signame[5..]) orelse return -1;
        if (rtmin - rtmax <= n and n <= 0)
            return rtmax + @as(c_int, @intCast(n));
    }

    return -1;
}

/// Convert the signal name SIGNAME to the signal number *SIGNUM.
/// Return 0 if successful, -1 otherwise.
pub export fn str2sig(signame: [*:0]const u8, signum: *c_int) c_int {
    const name = std.mem.span(signame);
    signum.* = str2signum(name);
    return if (signum.* < 0) -1 else 0;
}

/// Convert SIGNUM to a signal name in SIGNAME (buffer of at least
/// SIG2STR_MAX bytes). Return 0 if successful, -1 otherwise.
pub export fn sig2str(signum: c_int, signame: [*:0]u8) c_int {
    for (table) |e| {
        if (e.num == signum) {
            copyName(signame, e.name);
            return 0;
        }
    }

    const rtmin = rt_bounds.min;
    const rtmax = rt_bounds.max;
    if (!(rtmin <= signum and signum <= rtmax))
        return -1;

    var base: c_int = undefined;
    if (signum <= rtmin + @divTrunc(rtmax - rtmin, 2)) {
        copyName(signame, "RTMIN");
        base = rtmin;
    } else {
        copyName(signame, "RTMAX");
        base = rtmax;
    }

    const delta = signum - base;
    if (delta != 0) {
        // "%+d": sign always present, then decimal digits.
        var tmp: [12]u8 = undefined;
        var idx: usize = 0;
        tmp[idx] = if (delta > 0) '+' else '-';
        idx += 1;
        var val: c_int = if (delta < 0) -delta else delta;
        var digits: [11]u8 = undefined;
        var di: usize = 0;
        while (val > 0) {
            digits[di] = @intCast('0' + @mod(val, 10));
            di += 1;
            val = @divTrunc(val, 10);
        }
        while (di > 0) {
            di -= 1;
            tmp[idx] = digits[di];
            idx += 1;
        }
        std.mem.copyForwards(u8, signame[5 .. 5 + idx], tmp[0..idx]);
        signame[5 + idx] = 0;
    }
    return 0;
}
