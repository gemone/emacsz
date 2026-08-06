// Native Zig implementation of gnulib's lib/ftoastr.c instantiated as
// dtoastr (LENGTH 2): convert a double to the fewest decimal digits that
// round-trip, formatted like printf %g. Replicates the C algorithm --
// try %g at precision DBL_DIG (15) and increase until strtod parses the
// string back to the same double -- but with no libc call: exact digits
// come from std.fmt.float.render, rounding is round-half-even like glibc
// printf, and the round-trip check uses std.fmt.parseFloat. Backs float
// printing in src/print.c.

const std = @import("std");

const DBL_DIG: usize = 15;
const FLOAT_PREC_BOUND: usize = 53; // DBL_MANT_DIG
const DBL_MIN: f64 = 2.2250738585072014e-308;

const FTOASTR_LEFT_JUSTIFY: c_int = 1;
const FTOASTR_ALWAYS_SIGNED: c_int = 2;
const FTOASTR_SPACE_POSITIVE: c_int = 4;
const FTOASTR_ZERO_PAD: c_int = 8;
const FTOASTR_UPPER_E: c_int = 16;

const Digits = struct {
    len: usize,
    exp: i32, // exponent of the first significant digit
};

// Extract significant digits (no leading zeros, no dot) from the full
// decimal expansion SRC (unsigned) into DST; value = 0.<digits> * 10^(exp+1).
fn extractDigits(src: []const u8, dst: []u8) Digits {
    const dot = std.mem.indexOfScalar(u8, src, '.') orelse src.len;
    var first: usize = 0;
    while (first < src.len and (src[first] == '0' or src[first] == '.')) first += 1;
    if (first == src.len)
        return .{ .len = 0, .exp = 0 };

    const exp: i32 = if (first < dot)
        @intCast(dot - first - 1)
    else
        -@as(i32, @intCast(first - dot));

    var n: usize = 0;
    var i = first;
    while (i < src.len) : (i += 1) {
        if (src[i] != '.') {
            dst[n] = src[i];
            n += 1;
        }
    }
    return .{ .len = n, .exp = exp };
}

// Round DIGITS (len LEN) to PREC significant digits, round-half-even
// like glibc printf; returns the new length after stripping trailing
// zeros and updates *EXP on a carry.
fn roundHalfEven(digits: []u8, len: usize, exp: *i32, prec: usize) usize {
    if (len <= prec) {
        var n = len;
        while (n > 1 and digits[n - 1] == '0') n -= 1;
        return n;
    }

    var round_up = false;
    const disc = digits[prec];
    if (disc > '5') {
        round_up = true;
    } else if (disc == '5') {
        var any = false;
        for (digits[prec + 1 .. len]) |c| {
            if (c != '0') {
                any = true;
                break;
            }
        }
        if (any) {
            round_up = true;
        } else if ((digits[prec - 1] - '0') % 2 == 1) {
            round_up = true;
        }
    }

    if (round_up) {
        var i: isize = @intCast(prec - 1);
        while (i >= 0) : (i -= 1) {
            const idx: usize = @intCast(i);
            if (digits[idx] == '9') {
                digits[idx] = '0';
            } else {
                digits[idx] += 1;
                break;
            }
        }
        if (i < 0) {
            // 999..9 carried to 1000..0: exponent rises, digits = 1 + zeros.
            digits[0] = '1';
            for (1..prec) |j| digits[j] = '0';
            exp.* += 1;
        }
    }

    var n = prec;
    while (n > 1 and digits[n - 1] == '0') n -= 1;
    return n;
}

// Format DIGITS (value = 0.<digits> * 10^(exp+1), trailing zeros already
// stripped) as %g at precision PREC into OUT. Returns the slice.
fn formatG(out: []u8, sign: bool, digits: []const u8, exp: i32, prec: usize) []const u8 {
    var idx: usize = 0;
    if (sign) {
        out[idx] = '-';
        idx += 1;
    }

    if (exp < -4 or exp >= @as(i32, @intCast(prec))) {
        // e-notation: d[.ddd]e<sign><at least two digits>
        out[idx] = digits[0];
        idx += 1;
        if (digits.len > 1) {
            out[idx] = '.';
            idx += 1;
            @memcpy(out[idx..][0 .. digits.len - 1], digits[1..]);
            idx += digits.len - 1;
        }
        out[idx] = 'e';
        idx += 1;
        if (exp < 0) {
            out[idx] = '-';
            idx += 1;
        } else {
            out[idx] = '+';
            idx += 1;
        }
        const ae: u32 = @intCast(@abs(exp));
        if (ae < 10) {
            out[idx] = '0';
            idx += 1;
        }
        var tmp: [8]u8 = undefined;
        var ti: usize = 0;
        var v = ae;
        while (true) {
            tmp[ti] = '0' + @as(u8, @intCast(v % 10));
            ti += 1;
            v /= 10;
            if (v == 0) break;
        }
        while (ti > 0) {
            ti -= 1;
            out[idx] = tmp[ti];
            idx += 1;
        }
    } else if (exp >= 0) {
        // f-notation with an integer part.
        const int_len: usize = @intCast(exp + 1);
        var i: usize = 0;
        while (i < int_len) : (i += 1) {
            out[idx] = if (i < digits.len) digits[i] else '0';
            idx += 1;
        }
        if (digits.len > int_len) {
            out[idx] = '.';
            idx += 1;
            @memcpy(out[idx..][0 .. digits.len - int_len], digits[int_len..]);
            idx += digits.len - int_len;
        }
    } else {
        // f-notation "0.000ddd".
        out[idx] = '0';
        idx += 1;
        out[idx] = '.';
        idx += 1;
        var z: i32 = -exp - 1;
        while (z > 0) : (z -= 1) {
            out[idx] = '0';
            idx += 1;
        }
        @memcpy(out[idx..][0..digits.len], digits);
        idx += digits.len;
    }
    return out[0..idx];
}

// Apply printf flags and field width to BASE (which carries its own '-'
// sign for negatives) into OUT; %g uppercase via UPPER_E.
fn applyFormat(base: []const u8, flags: c_int, width: c_int, out: []u8) []const u8 {
    const upper = (flags & FTOASTR_UPPER_E) != 0;
    const sign_off: usize = if (base.len > 0 and base[0] == '-') 1 else 0;
    const body = base[sign_off..];

    var prefix: u8 = 0;
    if (sign_off == 0) {
        if ((flags & FTOASTR_ALWAYS_SIGNED) != 0)
            prefix = '+'
        else if ((flags & FTOASTR_SPACE_POSITIVE) != 0)
            prefix = ' ';
    }

    const content_len = body.len + @intFromBool(prefix != 0);
    const total: usize = @intCast(@max(@as(c_int, @intCast(content_len)), width));
    const zero_pad = (flags & FTOASTR_ZERO_PAD) != 0 and (flags & FTOASTR_LEFT_JUSTIFY) == 0;
    const left = (flags & FTOASTR_LEFT_JUSTIFY) != 0;

    var idx: usize = 0;
    if (sign_off != 0) {
        out[idx] = '-';
        idx += 1;
    } else if (prefix != 0) {
        out[idx] = prefix;
        idx += 1;
    }
    const pad = total - content_len;
    if (!left and !zero_pad) {
        @memset(out[idx..][0..pad], ' ');
        idx += pad;
    } else if (!left and zero_pad) {
        @memset(out[idx..][0..pad], '0');
        idx += pad;
    }
    @memcpy(out[idx..][0..body.len], body);
    idx += body.len;
    if (left) {
        @memset(out[idx..][0..pad], ' ');
        idx += pad;
    }

    if (upper) {
        for (out[0..idx]) |*c| {
            if (c.* == 'e') c.* = 'E';
        }
    }
    return out[0..idx];
}

// Format X as %g with precision PREC into OUT; returns the string or
// null for non-finite input (handled by the caller).
fn gFormat(out: []u8, x: f64, prec: usize) ?[]const u8 {
    if (std.math.isNan(x)) {
        var idx: usize = 0;
        if (std.math.signbit(x)) {
            out[0] = '-';
            idx = 1;
        }
        @memcpy(out[idx..][0..3], "nan");
        return out[0 .. idx + 3];
    }
    if (std.math.isInf(x)) {
        const sign = std.math.signbit(x);
        out[0] = '-';
        @memcpy(out[@intFromBool(sign)..][0..3], "inf");
        return out[0 .. 3 + @as(usize, @intFromBool(sign))];
    }

    var render_buf: [400]u8 = undefined;
    const s = std.fmt.float.render(&render_buf, @abs(x), .{ .mode = .decimal }) catch return null;

    var digits_buf: [400]u8 = undefined;
    var d = extractDigits(s, &digits_buf);
    if (d.len == 0) {
        // Zero: "0" or "-0" (printf %g keeps the sign of negative zero).
        var idx: usize = 0;
        if (std.math.signbit(x)) {
            out[0] = '-';
            idx = 1;
        }
        out[idx] = '0';
        return out[0 .. idx + 1];
    }

    d.len = roundHalfEven(digits_buf[0..d.len], d.len, &d.exp, prec);
    return formatG(out, std.math.signbit(x), digits_buf[0..d.len], d.exp, prec);
}

// Convert X to the fewest digits that round-trip, formatted like
// printf("%*.*g") with the given FLAGS and WIDTH; write to BUF (at most
// BUFSIZE bytes, NUL-terminated) and return the full length.
pub export fn dtoastr(buf: [*]u8, bufsize: usize, flags: c_int, width: c_int, x: f64) c_int {
    var raw_buf: [256]u8 = undefined;
    var padded_buf: [512]u8 = undefined;

    var prec: usize = if (@abs(x) < DBL_MIN) 1 else DBL_DIG;
    while (true) : (prec += 1) {
        const raw = gFormat(&raw_buf, x, prec) orelse return -1;
        const s = applyFormat(raw, flags, width, &padded_buf);
        const n: c_int = @intCast(s.len);

        const roundtrip = if (n < @as(c_int, @intCast(bufsize)))
            (std.fmt.parseFloat(f64, s) catch return -1) == x
        else
            false;
        if (roundtrip or FLOAT_PREC_BOUND <= prec) {
            if (bufsize > 0) {
                const copy: usize = @min(s.len, bufsize - 1);
                @memcpy(buf[0..copy], s[0..copy]);
                buf[copy] = 0;
            }
            return n;
        }
    }
}
