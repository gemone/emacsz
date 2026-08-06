// Native Zig implementations of gnulib's timespec arithmetic
// (lib/dtotimespec.c, lib/timespec-add.c, lib/timespec-sub.c):
// dtotimespec converts a double to a struct timespec (rounding toward
// +infinity, clamping on overflow), timespec_add / timespec_sub add and
// subtract timestamps with saturated clamping when time_t overflows.
// Pure arithmetic; no libc call, no std import.
//
// struct timespec on this target (glibc x86_64): time_t = i64 and
// tv_nsec is a long = i64.

pub const Timespec = extern struct {
    tv_sec: i64,
    tv_nsec: i64,
};

const TIMESPEC_HZ: i64 = 1000000000;
const TIME_MIN: i64 = -0x8000000000000000;
const TIME_MAX: i64 = 0x7fffffffffffffff;

// Convert the double value SEC to a struct timespec.  Round toward
// positive infinity; on overflow return an extremal value.
pub export fn dtotimespec(sec: f64) Timespec {
    if (!(TIME_MIN < sec))
        return .{ .tv_sec = TIME_MIN, .tv_nsec = 0 };
    if (!(sec < 1.0 + @as(f64, @floatFromInt(TIME_MAX))))
        return .{ .tv_sec = TIME_MAX, .tv_nsec = TIMESPEC_HZ - 1 };

    var s: i64 = @intFromFloat(sec); // C: time_t s = sec; (trunc toward zero)
    const frac = TIMESPEC_HZ * (sec - @as(f64, @floatFromInt(s)));
    var ns: i64 = @intFromFloat(frac); // C: long ns = frac;
    if (@as(f64, @floatFromInt(ns)) < frac) ns += 1; // C: ns += ns < frac;
    s += @divTrunc(ns, TIMESPEC_HZ); // C: s += ns / TIMESPEC_HZ;
    ns = @rem(ns, TIMESPEC_HZ); // C: ns %= TIMESPEC_HZ (truncated)
    if (ns < 0) {
        s -= 1;
        ns += TIMESPEC_HZ;
    }
    return .{ .tv_sec = s, .tv_nsec = ns };
}

// Saturating sum of two timestamps; on time_t overflow clamp to the
// extremal value whose sign matches the wrapped result (mirrors
// gnulib's ckd_add-based timespec_add).
pub export fn timespec_add(a: Timespec, b: Timespec) Timespec {
    const nssum = a.tv_nsec + b.tv_nsec;
    const carry: i64 = if (TIMESPEC_HZ <= nssum) 1 else 0;

    const first = @addWithOverflow(a.tv_sec, b.tv_sec);
    var rs: i64 = first[0];
    const second = @addWithOverflow(rs, carry);
    rs = second[0];

    if ((first[1] != 0) == (second[1] != 0))
        return .{ .tv_sec = rs, .tv_nsec = nssum - TIMESPEC_HZ * carry };

    // (TIME_MIN + TIME_MAX) / 2 == 0 for i64; clamp toward the sign of
    // the wrapped result.
    if (0 < rs)
        return .{ .tv_sec = TIME_MIN, .tv_nsec = 0 };
    return .{ .tv_sec = TIME_MAX, .tv_nsec = TIMESPEC_HZ - 1 };
}

// Saturating difference of two timestamps; same clamping rule.
pub export fn timespec_sub(a: Timespec, b: Timespec) Timespec {
    const nsdiff = a.tv_nsec - b.tv_nsec;
    const borrow: i64 = if (nsdiff < 0) 1 else 0;

    const first = @subWithOverflow(a.tv_sec, b.tv_sec);
    var rs: i64 = first[0];
    const second = @subWithOverflow(rs, borrow);
    rs = second[0];

    if ((first[1] != 0) == (second[1] != 0))
        return .{ .tv_sec = rs, .tv_nsec = nsdiff + TIMESPEC_HZ * borrow };

    if (0 < rs)
        return .{ .tv_sec = TIME_MIN, .tv_nsec = 0 };
    return .{ .tv_sec = TIME_MAX, .tv_nsec = TIMESPEC_HZ - 1 };
}
