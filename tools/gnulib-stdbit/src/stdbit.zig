// Zig replacements for gnulib's C23 <stdbit.h> bit-count functions
// (lib/stdc_leading_zeros.c, lib/stdc_trailing_zeros.c,
// lib/stdc_count_ones.c, lib/stdc_bit_width.c), whose bodies merely emit
// the out-of-line externals for the `extern inline` type-specific variants
// (_uc/_us/_ui/_ul/_ull) in lib/stdbit.h. Each maps to a Zig builtin
// (@clz / @ctz / @popCount) with EXACT C23 semantics, including the n=0
// edge case: leading/trailing zeros of 0 return the type's bit width;
// bit_width of 0 returns 0. Zig guarantees @clz(0)=@ctz(0)=bit width, so
// the match is exact. No libc call. Each variant returns unsigned int.
//
// Signatures match lib/stdbit.h. Used by temacs core integer ops
// (data.c: logcount/ash via count_ones/leading/trailing_zeros; bit_width).

export fn stdc_leading_zeros_uc(n: u8) c_uint {
    return @intCast(@clz(n));
}
export fn stdc_leading_zeros_us(n: c_ushort) c_uint {
    return @intCast(@clz(n));
}
export fn stdc_leading_zeros_ui(n: c_uint) c_uint {
    return @intCast(@clz(n));
}
export fn stdc_leading_zeros_ul(n: c_ulong) c_uint {
    return @intCast(@clz(n));
}
export fn stdc_leading_zeros_ull(n: c_ulonglong) c_uint {
    return @intCast(@clz(n));
}

export fn stdc_trailing_zeros_uc(n: u8) c_uint {
    return @intCast(@ctz(n));
}
export fn stdc_trailing_zeros_us(n: c_ushort) c_uint {
    return @intCast(@ctz(n));
}
export fn stdc_trailing_zeros_ui(n: c_uint) c_uint {
    return @intCast(@ctz(n));
}
export fn stdc_trailing_zeros_ul(n: c_ulong) c_uint {
    return @intCast(@ctz(n));
}
export fn stdc_trailing_zeros_ull(n: c_ulonglong) c_uint {
    return @intCast(@ctz(n));
}

export fn stdc_count_ones_uc(n: u8) c_uint {
    return @intCast(@popCount(n));
}
export fn stdc_count_ones_us(n: c_ushort) c_uint {
    return @intCast(@popCount(n));
}
export fn stdc_count_ones_ui(n: c_uint) c_uint {
    return @intCast(@popCount(n));
}
export fn stdc_count_ones_ul(n: c_ulong) c_uint {
    return @intCast(@popCount(n));
}
export fn stdc_count_ones_ull(n: c_ulonglong) c_uint {
    return @intCast(@popCount(n));
}

export fn stdc_bit_width_uc(n: u8) c_uint {
    return @intCast(@bitSizeOf(u8) - @clz(n));
}
export fn stdc_bit_width_us(n: c_ushort) c_uint {
    return @intCast(@bitSizeOf(c_ushort) - @clz(n));
}
export fn stdc_bit_width_ui(n: c_uint) c_uint {
    return @intCast(@bitSizeOf(c_uint) - @clz(n));
}
export fn stdc_bit_width_ul(n: c_ulong) c_uint {
    return @intCast(@bitSizeOf(c_ulong) - @clz(n));
}
export fn stdc_bit_width_ull(n: c_ulonglong) c_uint {
    return @intCast(@bitSizeOf(c_ulonglong) - @clz(n));
}
