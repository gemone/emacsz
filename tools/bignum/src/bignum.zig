// Native Zig implementation of the GMP integer API subset used by
// Emacs's bignum support (src/bignum.c and the mpz_* call sites in
// data.c/print.c/lread.c/emacs-module.c/timefns.c/pdumper.c). The
// exports are C-ABI compatible with libgmp so temacs can link this
// package instead of -lgmp, on every target. Representation matches
// GMP exactly: sign-magnitude, little-endian 64-bit limbs, with the
// mpz_t struct layout (alloc/size/limb pointer). Memory goes through
// mp_set_memory_functions callbacks (Emacs installs xmalloc-based
// callbacks), defaulting to zig's allocator when not overridden.
//
// Implemented so far: mpz lifecycle, conversions, comparison, add/sub/mul,
// two-power shifts, size queries, the full division family (truncated,
// floored, ceiling, single-limb and exact), pow/gcd/addmul/submul,
// bitwise ops, the limbs API and byte import/export. The remaining
// surface (strings, doubles and fit predicates) lands in this slice;
// the package now covers the full GMP surface Emacs calls.

const std = @import("std");

pub const mp_limb_t = u64;
pub const mp_size_t = isize;
pub const mp_bitcnt_t = u64;
pub const GMP_NUMB_BITS: usize = 64;

// GMP exposes the limb width as an extern const int; Emacs reads it in
// src/bignum.c to double-check the layout assumptions.
pub export const mp_bits_per_limb: c_int = 64;

// GMP's mpz_t is `typedef __mpz_struct mpz_t[1]`; C passes a pointer,
// so every export takes `*mpz_t`.
pub const mpz_t = extern struct {
    _mp_alloc: c_int,
    _mp_size: c_int,
    _mp_d: ?[*]mp_limb_t,
};

const AllocFn = *const fn (usize) callconv(.c) ?*anyopaque;
const ReallocFn = *const fn (?*anyopaque, usize, usize) callconv(.c) ?*anyopaque;
const FreeFn = *const fn (?*anyopaque, usize) callconv(.c) void;

var g_alloc: AllocFn = zigAlloc;
var g_realloc: ReallocFn = zigRealloc;
var g_free: FreeFn = zigFree;

fn zigAlloc(n: usize) callconv(.c) ?*anyopaque {
    const mem = std.heap.smp_allocator.alloc(u8, n) catch return null;
    return mem.ptr;
}

fn zigRealloc(p: ?*anyopaque, old_size: usize, new_size: usize) callconv(.c) ?*anyopaque {
    const a = std.heap.smp_allocator;
    if (p) |ptr| {
        const bytes: [*]u8 = @ptrCast(ptr);
        const mem = a.realloc(bytes[0..old_size], new_size) catch return null;
        return mem.ptr;
    }
    return zigAlloc(new_size);
}

fn zigFree(p: ?*anyopaque, size: usize) callconv(.c) void {
    if (p) |ptr| {
        const bytes: [*]u8 = @ptrCast(ptr);
        std.heap.smp_allocator.free(bytes[0..size]);
    }
}

// Install GMP-compatible memory callbacks (NULL resets to the zig
// defaults). Emacs calls this with its xmalloc-family functions.
pub export fn mp_set_memory_functions(
    alloc: ?AllocFn,
    realloc: ?ReallocFn,
    free: ?FreeFn,
) void {
    if (alloc) |f| g_alloc = f;
    if (realloc) |f| g_realloc = f;
    if (free) |f| g_free = f;
}

pub export fn mp_get_memory_functions(
    alloc: ?*?AllocFn,
    realloc: ?*?ReallocFn,
    free: ?*?FreeFn,
) void {
    if (alloc) |p| p.* = g_alloc;
    if (realloc) |p| p.* = g_realloc;
    if (free) |p| p.* = g_free;
}

fn oom() noreturn {
    @panic("bignum: out of memory");
}

fn allocLimbs(n: usize) ?[*]mp_limb_t {
    if (n == 0) return null;
    const p = g_alloc(n * @sizeOf(mp_limb_t)) orelse return null;
    return @ptrCast(@alignCast(p));
}

fn freeLimbs(d: [*]mp_limb_t, alloc: usize) void {
    if (alloc != 0) g_free(d, alloc * @sizeOf(mp_limb_t));
}

fn limbCount(z: *const mpz_t) usize {
    return if (z._mp_size < 0) @intCast(-z._mp_size) else @intCast(z._mp_size);
}

fn signOf(z: *const mpz_t) c_int {
    if (z._mp_size == 0) return 0;
    return if (z._mp_size > 0) 1 else -1;
}

// Trim leading zero limbs; a zero value gets size 0.
fn normalize(z: *mpz_t) void {
    const d = z._mp_d orelse {
        z._mp_size = 0;
        return;
    };
    var n = limbCount(z);
    while (n > 0 and d[n - 1] == 0) n -= 1;
    if (n == 0) {
        z._mp_size = 0;
        return;
    }
    const neg = z._mp_size < 0;
    z._mp_size = if (neg) -@as(c_int, @intCast(n)) else @as(c_int, @intCast(n));
}

// Replace z's storage with the freshly computed buffer D of ALLOC limbs
// (USED used limbs, sign SIGN). D is always a fresh allocation, so this
// is safe when z aliases an input already consumed by the caller.
fn commit(z: *mpz_t, d: [*]mp_limb_t, alloc: usize, used: usize, sign: c_int) void {
    if (z._mp_d) |old| freeLimbs(old, @intCast(z._mp_alloc));
    z._mp_d = d;
    z._mp_alloc = @intCast(alloc);
    z._mp_size = if (used == 0 or sign == 0) 0 else if (sign < 0) -@as(c_int, @intCast(used)) else @as(c_int, @intCast(used));
}

fn addLimbs(a: u64, b: u64, carry_in: u1) struct { u64, u1 } {
    const r1 = @addWithOverflow(a, b);
    const r2 = @addWithOverflow(@as(u64, @bitCast(r1[0])), carry_in);
    return .{ @as(u64, @bitCast(r2[0])), r1[1] | r2[1] };
}

fn subLimbs(a: u64, b: u64, borrow_in: u1) struct { u64, u1 } {
    const r1 = @subWithOverflow(a, b);
    const r2 = @subWithOverflow(@as(u64, @bitCast(r1[0])), borrow_in);
    return .{ @as(u64, @bitCast(r2[0])), r1[1] | r2[1] };
}

// D[0..n) = |a| + |b|; the result has at most N+1 limbs.
fn magAdd(z: *mpz_t, a: *const mpz_t, b: *const mpz_t) void {
    const an = limbCount(a);
    const bn = limbCount(b);
    const n = @max(an, bn);
    const res = allocLimbs(n + 1) orelse oom();
    var carry: u1 = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const av: u64 = if (i < an) a._mp_d.?[i] else 0;
        const bv: u64 = if (i < bn) b._mp_d.?[i] else 0;
        const r = addLimbs(av, bv, carry);
        res[i] = @as(u64, @bitCast(r[0]));
        carry = r[1];
    }
    if (carry == 1) {
        res[n] = 1;
        commit(z, res, n + 1, n + 1, 1);
    } else {
        commit(z, res, n + 1, n, 1);
    }
}

// |a| >= |b| must hold; D[0..an) = |a| - |b|.
fn magSub(z: *mpz_t, a: *const mpz_t, b: *const mpz_t) void {
    const an = limbCount(a);
    const bn = limbCount(b);
    const res = allocLimbs(an) orelse oom();
    var borrow: u1 = 0;
    var i: usize = 0;
    while (i < an) : (i += 1) {
        const av: u64 = a._mp_d.?[i];
        const bv: u64 = if (i < bn) b._mp_d.?[i] else 0;
        const r = subLimbs(av, bv, borrow);
        res[i] = @as(u64, @bitCast(r[0]));
        borrow = r[1];
    }
    std.debug.assert(borrow == 0); // caller guarantees |a| >= |b|
    var used = an;
    while (used > 0 and res[used - 1] == 0) used -= 1;
    commit(z, res, an, used, 1);
}

// Compare |a| and |b|: negative when |a| < |b|, etc.
fn magCmp(a: *const mpz_t, b: *const mpz_t) c_int {
    // Skip leading zero limbs so an unnormalized operand (e.g. one built
    // via mpz_limbs_finish with a zero top limb) compares by value.
    var an = limbCount(a);
    var bn = limbCount(b);
    while (an > 0 and a._mp_d.?[an - 1] == 0) an -= 1;
    while (bn > 0 and b._mp_d.?[bn - 1] == 0) bn -= 1;
    if (an != bn) return if (an < bn) -1 else 1;
    var i = an;
    while (i > 0) {
        i -= 1;
        if (a._mp_d.?[i] != b._mp_d.?[i])
            return if (a._mp_d.?[i] < b._mp_d.?[i]) -1 else 1;
    }
    return 0;
}

pub export fn mpz_init(z: *mpz_t) void {
    z.* = .{ ._mp_alloc = 0, ._mp_size = 0, ._mp_d = null };
}

// Preallocate enough limbs for NBITS bits (the value stays zero).
pub export fn mpz_init2(z: *mpz_t, nbits: mp_bitcnt_t) void {
    const need: usize = @intCast((nbits + GMP_NUMB_BITS - 1) / GMP_NUMB_BITS);
    z.* = .{ ._mp_alloc = 0, ._mp_size = 0, ._mp_d = null };
    if (need != 0) {
        const d = allocLimbs(need) orelse oom();
        @memset(d[0..need], 0);
        z._mp_d = d;
        z._mp_alloc = @intCast(need);
    }
}

pub export fn mpz_clear(z: *mpz_t) void {
    if (z._mp_d) |d| {
        freeLimbs(d, @intCast(z._mp_alloc));
        z._mp_d = null;
    }
    z._mp_alloc = 0;
    z._mp_size = 0;
}

// Ensure Z has room for NEED limbs, growing and copying as needed.
fn ensureCapacity(z: *mpz_t, need: usize) void {
    const cur: usize = @intCast(z._mp_alloc);
    if (cur >= need) return;
    var new_alloc = if (cur == 0) 4 else cur;
    while (new_alloc < need) new_alloc *= 2;
    const np = g_realloc(z._mp_d, cur * @sizeOf(mp_limb_t), new_alloc * @sizeOf(mp_limb_t)) orelse oom();
    const nd: [*]mp_limb_t = @ptrCast(@alignCast(np));
    @memset(nd[cur..new_alloc], 0);
    z._mp_d = nd;
    z._mp_alloc = @intCast(new_alloc);
}

// 64-bit setter for internal use.  The exported mpz_set_ui is GMP's
// `unsigned long` (only 32-bit on LLP64/Windows), so it cannot carry a full
// 64-bit limb; bignum.zig's own >32-bit constants -- e.g. the 53-bit double
// mantissa assembled in mpf_set_d -- go through this helper instead.
fn mpz_set_u64(z: *mpz_t, u: u64) void {
    ensureCapacity(z, 1);
    if (u == 0) {
        z._mp_size = 0;
        return;
    }
    z._mp_d.?[0] = u;
    z._mp_size = 1;
}

pub export fn mpz_set_ui(z: *mpz_t, u: c_ulong) void {
    mpz_set_u64(z, @intCast(u));
}

pub export fn mpz_set_si(z: *mpz_t, i: c_long) void {
    // GMP ABI: the operand is `signed long` (32-bit on LLP64/Windows).
    // Widen to i64 before the magnitude work.
    const ii: i64 = @intCast(i);
    if (ii < 0) {
        mpz_set_ui(z, @intCast(@as(u64, @bitCast(0 -% ii))));
        z._mp_size = -z._mp_size;
    } else {
        mpz_set_ui(z, @intCast(ii));
    }
}

// Low limb regardless of sign (GMP semantics).
pub export fn mpz_get_ui(z: *const mpz_t) u64 {
    if (z._mp_size == 0) return 0;
    return z._mp_d.?[0];
}

pub export fn mpz_get_si(z: *const mpz_t) i64 {
    const l = mpz_get_ui(z);
    if (z._mp_size == 0) return 0;
    // GMP returns the two's-complement value of the low limb, saturating
    // at LONG_MAX/LONG_MIN when the magnitude does not fit.
    if (z._mp_size > 0)
        return if (l <= std.math.maxInt(i64)) @intCast(l) else std.math.maxInt(i64);
    return if (l <= std.math.maxInt(i64)) -@as(i64, @intCast(l)) else std.math.minInt(i64);
}

pub export fn mpz_set(z: *mpz_t, src: *const mpz_t) void {
    if (z == src) return;
    const n = limbCount(src);
    ensureCapacity(z, if (n == 0) 1 else n);
    if (n != 0) @memcpy(z._mp_d.?[0..n], src._mp_d.?[0..n]);
    z._mp_size = src._mp_size;
}

pub export fn mpz_swap(a: *mpz_t, b: *mpz_t) void {
    const tmp = a.*;
    a.* = b.*;
    b.* = tmp;
}

pub export fn mpz_neg(z: *mpz_t, src: *const mpz_t) void {
    mpz_set(z, src);
    z._mp_size = -z._mp_size;
}

pub export fn mpz_abs(z: *mpz_t, src: *const mpz_t) void {
    mpz_set(z, src);
    if (z._mp_size < 0) z._mp_size = -z._mp_size;
}

pub export fn mpz_sgn(z: *const mpz_t) c_int {
    return signOf(z);
}

pub export fn mpz_size(z: *const mpz_t) mp_size_t {
    return @intCast(limbCount(z));
}

fn bitLength(z: *const mpz_t) u64 {
    const n = limbCount(z);
    if (n == 0) return 0;
    const top = z._mp_d.?[n - 1];
    return @as(u64, n - 1) * GMP_NUMB_BITS + (GMP_NUMB_BITS - @clz(top));
}

// Number of digits in the given base (2..62). Never underestimates
// (Emacs sizes print buffers from this plus slack).
pub export fn mpz_sizeinbase(z: *const mpz_t, base: c_int) usize {
    const bits = bitLength(z);
    if (bits == 0) return 1;
    const b: u64 = @intCast(base);
    if (b & (b - 1) == 0) {
        const lg: u64 = @ctz(b);
        return @intCast(@divTrunc(bits + lg - 1, lg));
    }
    // Upper bound on ceil(bits / log2(base)) via a fixed-point reciprocal
    // (rounded up), so the result never underestimates the digit count.
    const scale: f128 = 0x1p60;
    const recip: u128 = @intFromFloat(@ceil(scale / @log2(@as(f128, @floatFromInt(b)))));
    return @intCast((@as(u128, bits) * recip >> 60) + 1);
}

pub export fn mpz_cmp(a: *const mpz_t, b: *const mpz_t) c_int {
    const sa = signOf(a);
    const sb = signOf(b);
    if (sa != sb) return if (sa < sb) -1 else 1;
    if (sa == 0) return 0;
    const c = magCmp(a, b);
    return if (sa > 0) c else -c;
}

pub export fn mpz_cmpabs(a: *const mpz_t, b: *const mpz_t) c_int {
    return magCmp(a, b);
}

pub export fn mpz_cmp_ui(a: *const mpz_t, u: c_ulong) c_int {
    var b: mpz_t = undefined;
    mpz_init(&b);
    defer mpz_clear(&b);
    mpz_set_ui(&b, u);
    return mpz_cmp(a, &b);
}

pub export fn mpz_cmp_si(a: *const mpz_t, i: c_long) c_int {
    var b: mpz_t = undefined;
    mpz_init(&b);
    defer mpz_clear(&b);
    mpz_set_si(&b, i);
    return mpz_cmp(a, &b);
}

pub export fn mpz_add(z: *mpz_t, a: *const mpz_t, b: *const mpz_t) void {
    const sa = signOf(a);
    const sb = signOf(b);
    if (sa == 0) {
        mpz_set(z, b);
        return;
    }
    if (sb == 0) {
        mpz_set(z, a);
        return;
    }
    if (sa == sb) {
        magAdd(z, a, b);
        if (z._mp_size != 0 and sa < 0) z._mp_size = -z._mp_size;
        return;
    }
    switch (magCmp(a, b)) {
        -1 => {
            magSub(z, b, a);
            if (z._mp_size != 0 and sb < 0) z._mp_size = -z._mp_size;
        },
        1 => {
            magSub(z, a, b);
            if (z._mp_size != 0 and sa < 0) z._mp_size = -z._mp_size;
        },
        else => {
            ensureCapacity(z, 1);
            z._mp_size = 0;
        },
    }
}

pub export fn mpz_sub(z: *mpz_t, a: *const mpz_t, b: *const mpz_t) void {
    const sa = signOf(a);
    const sb = signOf(b);
    if (sa == 0) {
        mpz_neg(z, b);
        return;
    }
    if (sb == 0) {
        mpz_set(z, a);
        return;
    }
    if (sa != sb) {
        magAdd(z, a, b);
        if (z._mp_size != 0 and sa < 0) z._mp_size = -z._mp_size;
        return;
    }
    switch (magCmp(a, b)) {
        -1 => {
            magSub(z, b, a);
            if (z._mp_size != 0 and sa > 0) z._mp_size = -z._mp_size;
        },
        1 => {
            magSub(z, a, b);
            if (z._mp_size != 0 and sa < 0) z._mp_size = -z._mp_size;
        },
        else => {
            ensureCapacity(z, 1);
            z._mp_size = 0;
        },
    }
}

pub export fn mpz_add_ui(z: *mpz_t, a: *const mpz_t, u: c_ulong) void {
    var b: mpz_t = undefined;
    mpz_init(&b);
    defer mpz_clear(&b);
    mpz_set_ui(&b, u);
    mpz_add(z, a, &b);
}

pub export fn mpz_sub_ui(z: *mpz_t, a: *const mpz_t, u: c_ulong) void {
    var b: mpz_t = undefined;
    mpz_init(&b);
    defer mpz_clear(&b);
    mpz_set_ui(&b, u);
    mpz_sub(z, a, &b);
}

// D[i + j] += A[i] * B[j] + carry (schoolbook inner step).
fn mulAddLimbs(a: u64, b: u64, addend: u64, carry_in: u64) struct { u64, u64 } {
    const wide = @as(u128, a) * b + @as(u128, addend) + @as(u128, carry_in);
    return .{ @truncate(wide), @truncate(wide >> 64) };
}

pub export fn mpz_mul(z: *mpz_t, a: *const mpz_t, b: *const mpz_t) void {
    const an = limbCount(a);
    const bn = limbCount(b);
    if (an == 0 or bn == 0) {
        ensureCapacity(z, 1);
        z._mp_size = 0;
        return;
    }
    const res = allocLimbs(an + bn) orelse oom();
    @memset(res[0 .. an + bn], 0);
    var i: usize = 0;
    while (i < an) : (i += 1) {
        const ai = a._mp_d.?[i];
        var carry: u64 = 0;
        var j: usize = 0;
        while (j < bn) : (j += 1) {
            const r = mulAddLimbs(ai, b._mp_d.?[j], res[i + j], carry);
            res[i + j] = r[0];
            carry = r[1];
        }
        res[i + bn] = carry;
    }
    var used = an + bn;
    while (used > 0 and res[used - 1] == 0) used -= 1;
    const sign: c_int = if ((signOf(a) < 0) != (signOf(b) < 0)) -1 else 1;
    commit(z, res, an + bn, used, sign);
}

pub export fn mpz_mul_ui(z: *mpz_t, a: *const mpz_t, u: c_ulong) void {
    const uu: u64 = @intCast(u);
    const an = limbCount(a);
    if (an == 0 or uu == 0) {
        ensureCapacity(z, 1);
        z._mp_size = 0;
        return;
    }
    const res = allocLimbs(an + 1) orelse oom();
    var carry: u64 = 0;
    var i: usize = 0;
    while (i < an) : (i += 1) {
        const r = mulAddLimbs(a._mp_d.?[i], uu, 0, carry);
        res[i] = r[0];
        carry = r[1];
    }
    res[an] = carry;
    var used = an + 1;
    while (used > 0 and res[used - 1] == 0) used -= 1;
    const sign: c_int = if (signOf(a) < 0) -1 else 1;
    commit(z, res, an + 1, used, sign);
}

pub export fn mpz_mul_2exp(z: *mpz_t, a: *const mpz_t, k: mp_bitcnt_t) void {
    const an = limbCount(a);
    if (an == 0 or k == 0) {
        mpz_set(z, a);
        return;
    }
    const limb_shift: usize = @intCast(k / GMP_NUMB_BITS);
    const bit_shift: u6 = @intCast(k % GMP_NUMB_BITS);
    const extra: usize = if (bit_shift == 0) 0 else 1;
    const res = allocLimbs(an + limb_shift + extra) orelse oom();
    @memset(res[0 .. an + limb_shift + extra], 0);
    if (bit_shift == 0) {
        @memcpy(res[limb_shift .. limb_shift + an], a._mp_d.?[0..an]);
    } else {
        var carry: u64 = 0;
        var i: usize = 0;
        while (i < an) : (i += 1) {
            const v = a._mp_d.?[i];
            res[limb_shift + i] = (v << bit_shift) | carry;
            carry = v >> @intCast(GMP_NUMB_BITS - bit_shift);
        }
        if (carry != 0) res[limb_shift + an] = carry;
    }
    var used = an + limb_shift + extra;
    while (used > 0 and res[used - 1] == 0) used -= 1;
    const sign: c_int = if (signOf(a) < 0) -1 else 1;
    commit(z, res, an + limb_shift + extra, used, sign);
}

// Floor division by a power of two: rounds toward -inf for negatives.
pub export fn mpz_fdiv_q_2exp(z: *mpz_t, a: *const mpz_t, k: mp_bitcnt_t) void {
    const neg = signOf(a) < 0;
    var mag: mpz_t = undefined;
    mpz_init(&mag);
    defer mpz_clear(&mag);
    mpz_abs(&mag, a);

    const limb_shift: usize = @intCast(k / GMP_NUMB_BITS);
    const bit_shift: u6 = @intCast(k % GMP_NUMB_BITS);
    const an = limbCount(&mag);

    var dropped: bool = false;
    if (an != 0 and limb_shift < an) {
        if (bit_shift != 0 and (mag._mp_d.?[limb_shift] & ((@as(u64, 1) << bit_shift) - 1)) != 0)
            dropped = true;
        var i: usize = 0;
        while (i < limb_shift) : (i += 1) {
            if (mag._mp_d.?[i] != 0) {
                dropped = true;
                break;
            }
        }
    } else {
        dropped = an != 0; // entire magnitude shifted out; zero drops nothing
    }

    const out_limbs = if (limb_shift >= an) 0 else an - limb_shift;
    const need_increment = neg and dropped;
    const cap = (if (out_limbs == 0) 1 else out_limbs) + @as(usize, @intFromBool(need_increment));
    const res = allocLimbs(cap) orelse oom();
    var used: usize = 0;
    if (out_limbs != 0) {
        if (bit_shift == 0) {
            @memcpy(res[0..out_limbs], mag._mp_d.?[limb_shift .. limb_shift + out_limbs]);
        } else {
            var i: usize = 0;
            while (i < out_limbs) : (i += 1) {
                const hi = mag._mp_d.?[limb_shift + i];
                const lo: u64 = if (limb_shift + i + 1 < an) mag._mp_d.?[limb_shift + i + 1] else 0;
                res[i] = (hi >> bit_shift) | (lo << @intCast(GMP_NUMB_BITS - bit_shift));
            }
        }
        used = out_limbs;
        while (used > 0 and res[used - 1] == 0) used -= 1;
    }
    if (need_increment) {
        // Floor division of a negative rounds toward -inf: add one to the
        // truncated magnitude (capacity has headroom for the carry).
        var carry: u1 = 1;
        var i: usize = 0;
        while (carry == 1) : (i += 1) {
            const r = addLimbs(if (i < used) res[i] else 0, 0, carry);
            res[i] = @as(u64, @bitCast(r[0]));
            carry = r[1];
        }
        used = cap;
        while (used > 0 and res[used - 1] == 0) used -= 1;
        commit(z, res, cap, used, -1);
        return;
    }
    commit(z, res, cap, used, if (neg and used != 0) -1 else 1);
}

// ---------- division ----------

// Fill QBUF (limbCount(n) limbs; pass null to skip) with trunc(|n| / d) and
// return |n| mod d. d must be nonzero.
fn singleLimbDivMod(n: *const mpz_t, d: u64, qbuf: ?[*]mp_limb_t) u64 {
    const an = limbCount(n);
    var rem: u64 = 0;
    var i = an;
    while (i > 0) {
        i -= 1;
        const wide = (@as(u128, rem) << 64) | n._mp_d.?[i];
        if (qbuf) |q| q[i] = @truncate(wide / d);
        rem = @truncate(wide % d);
    }
    return rem;
}

// Magnitude division: Q = |n| / |d|, R = |n| mod |d|, both committed with
// positive signs. |d| must be nonzero; q and r must be distinct variables
// but either may alias n or d (the inputs are copied into work buffers
// before any output commit). Handles |n| < |d| (q = 0, r = |n|).
fn magDivmod(q: *mpz_t, r: *mpz_t, n: *const mpz_t, d: *const mpz_t) void {
    const an = limbCount(n);
    const bn = limbCount(d);
    std.debug.assert(bn > 0);
    std.debug.assert(q != r);

    if (an < bn) {
        const rlimbs = allocLimbs(if (an == 0) 1 else an) orelse oom();
        if (an != 0) @memcpy(rlimbs[0..an], n._mp_d.?[0..an]);
        ensureCapacity(q, 1);
        q._mp_size = 0;
        commit(r, rlimbs, if (an == 0) 1 else an, an, 1);
        return;
    }

    // Normalize so the divisor's top limb has its high bit set; the
    // dividend is shifted the same amount into an+1 limbs.
    const s: u6 = @intCast(@clz(d._mp_d.?[bn - 1]));
    const u = allocLimbs(an + 1) orelse oom();
    const v = allocLimbs(bn) orelse oom();
    if (s == 0) {
        @memcpy(u[0..an], n._mp_d.?[0..an]);
        u[an] = 0;
        @memcpy(v[0..bn], d._mp_d.?[0..bn]);
    } else {
        const sh: u6 = @intCast(64 - @as(u7, s));
        var carry: u64 = 0;
        var i: usize = 0;
        while (i < an) : (i += 1) {
            const x = n._mp_d.?[i];
            u[i] = (x << s) | carry;
            carry = x >> sh;
        }
        u[an] = carry;
        carry = 0;
        i = 0;
        while (i < bn) : (i += 1) {
            const x = d._mp_d.?[i];
            v[i] = (x << s) | carry;
            carry = x >> sh;
        }
    }

    if (bn == 1) {
        // Single-limb divisor: straight long division over the shifted
        // limbs, starting at the extra top limb u[an] (the shift carry).
        const qbuf = allocLimbs(an) orelse oom();
        var rem: u64 = 0;
        var i = an;
        while (true) {
            const wide = (@as(u128, rem) << 64) | u[i];
            if (i < an) qbuf[i] = @truncate(wide / v[0]);
            rem = @truncate(wide % v[0]);
            if (i == 0) break;
            i -= 1;
        }
        const true_rem = rem >> s;
        var qused = an;
        while (qused > 0 and qbuf[qused - 1] == 0) qused -= 1;
        commit(q, qbuf, an, qused, 1);
        const rbuf = allocLimbs(1) orelse oom();
        if (true_rem != 0) rbuf[0] = true_rem;
        commit(r, rbuf, 1, if (true_rem != 0) 1 else 0, 1);
        freeLimbs(u, an + 1);
        freeLimbs(v, bn);
        return;
    }

    // Knuth algorithm D over 64-bit limbs (TAOCP 4.3.1).
    const vtop = v[bn - 1];
    const vsub = v[bn - 2];
    const m = an - bn;
    const qbuf = allocLimbs(m + 1) orelse oom();

    var j: usize = m + 1;
    while (j > 0) {
        j -= 1;
        const ujn = u[j + bn];
        var qhat: u64 = undefined;
        if (ujn == vtop) {
            // qhat = b - 1, rhat = u[j+n-1] + vtop >= vtop, so the test
            // b*rhat + u[j+n-2] > qhat*v[n-2] can never pass.
            qhat = std.math.maxInt(u64);
        } else {
            const num = (@as(u128, ujn) << 64) | u[j + bn - 1];
            qhat = @truncate(num / vtop);
            var rhat: u64 = @truncate(num % vtop);
            while (true) {
                const big = @as(u128, qhat) * vsub;
                const right = (@as(u128, rhat) << 64) | u[j + bn - 2];
                if (big <= right) break;
                qhat -%= 1;
                rhat +%= vtop;
                if (rhat < vtop) break; // wrapped past 2^64: test must fail
            }
        }
        // Multiply and subtract: u[j..j+bn] -= qhat * v.
        var carry: u64 = 0;
        var borrow: u1 = 0;
        var i: usize = 0;
        while (i < bn) : (i += 1) {
            const p = @as(u128, qhat) * v[i] + carry;
            carry = @truncate(p >> 64);
            const low: u64 = @truncate(p);
            const t: u128 = @as(u128, u[j + i]) -% (@as(u128, low) + borrow);
            u[j + i] = @truncate(t);
            borrow = @intFromBool(t >> 64 != 0);
        }
        const t2: u128 = @as(u128, u[j + bn]) -% (@as(u128, carry) + borrow);
        u[j + bn] = @truncate(t2);
        if (t2 >> 64 != 0) {
            // qhat was one too large: decrement and add the divisor back.
            qhat -%= 1;
            var carry2: u1 = 0;
            i = 0;
            while (i < bn) : (i += 1) {
                const sum = @as(u128, u[j + i]) + v[i] + carry2;
                u[j + i] = @truncate(sum);
                carry2 = @intFromBool(sum >> 64 != 0);
            }
            const sum2 = @as(u128, u[j + bn]) + carry2;
            u[j + bn] = @truncate(sum2);
        }
        qbuf[j] = qhat;
    }

    // Unnormalize the remainder (u[0..bn) holds |n| mod |d| shifted left).
    const rbuf = allocLimbs(bn) orelse oom();
    var rused: usize = bn;
    if (s == 0) {
        @memcpy(rbuf[0..bn], u[0..bn]);
    } else {
        const sh: u6 = @intCast(64 - @as(u7, s));
        var i: usize = 0;
        while (i < bn) : (i += 1) {
            const hi = u[i];
            const lo: u64 = if (i + 1 < bn) u[i + 1] else 0;
            rbuf[i] = (hi >> s) | (lo << sh);
        }
    }
    while (rused > 0 and rbuf[rused - 1] == 0) rused -= 1;
    var qused = m + 1;
    while (qused > 0 and qbuf[qused - 1] == 0) qused -= 1;
    commit(q, qbuf, m + 1, qused, 1);
    commit(r, rbuf, bn, rused, 1);
    freeLimbs(u, an + 1);
    freeLimbs(v, bn);
}

pub export fn mpz_tdiv_qr(q: *mpz_t, r: *mpz_t, n: *const mpz_t, d: *const mpz_t) void {
    const sn = signOf(n);
    const sd = signOf(d);
    if (sd == 0) @panic("mpz division by zero");
    if (sn == 0) {
        ensureCapacity(q, 1);
        q._mp_size = 0;
        ensureCapacity(r, 1);
        r._mp_size = 0;
        return;
    }
    magDivmod(q, r, n, d);
    if ((sn < 0) != (sd < 0)) q._mp_size = -q._mp_size;
    if (sn < 0) r._mp_size = -r._mp_size;
}

pub export fn mpz_tdiv_q(q: *mpz_t, n: *const mpz_t, d: *const mpz_t) void {
    var r: mpz_t = undefined;
    mpz_init(&r);
    defer mpz_clear(&r);
    mpz_tdiv_qr(q, &r, n, d);
}

pub export fn mpz_tdiv_r(r: *mpz_t, n: *const mpz_t, d: *const mpz_t) void {
    var q: mpz_t = undefined;
    mpz_init(&q);
    defer mpz_clear(&q);
    mpz_tdiv_qr(&q, r, n, d);
}

// GMP returns the nonnegative remainder |n| mod d here (truncated
// division by a positive single-limb divisor).
pub export fn mpz_tdiv_ui(n: *const mpz_t, d: c_ulong) u64 {
    const dd: u64 = @intCast(d);
    if (dd == 0) @panic("mpz division by zero");
    return singleLimbDivMod(n, dd, null);
}

pub export fn mpz_fdiv_q(q: *mpz_t, n: *const mpz_t, d: *const mpz_t) void {
    const sn = signOf(n);
    const sd = signOf(d);
    if (sd == 0) @panic("mpz division by zero");
    if (sn == 0) {
        ensureCapacity(q, 1);
        q._mp_size = 0;
        return;
    }
    var r: mpz_t = undefined;
    mpz_init(&r);
    defer mpz_clear(&r);
    mpz_tdiv_qr(q, &r, n, d);
    if (signOf(&r) != 0 and (sn < 0) != (sd < 0))
        mpz_sub_ui(q, q, 1);
}

pub export fn mpz_fdiv_r(r: *mpz_t, n: *const mpz_t, d: *const mpz_t) void {
    if (r == d) {
        var dc: mpz_t = undefined;
        mpz_init(&dc);
        defer mpz_clear(&dc);
        mpz_set(&dc, d);
        mpz_fdiv_r(r, n, &dc);
        return;
    }
    const sn = signOf(n);
    const sd = signOf(d);
    if (sd == 0) @panic("mpz division by zero");
    if (sn == 0) {
        ensureCapacity(r, 1);
        r._mp_size = 0;
        return;
    }
    var q: mpz_t = undefined;
    mpz_init(&q);
    defer mpz_clear(&q);
    mpz_tdiv_qr(&q, r, n, d);
    if (signOf(r) != 0 and (sn < 0) != (sd < 0))
        mpz_add(r, r, d);
}

pub export fn mpz_fdiv_qr(q: *mpz_t, r: *mpz_t, n: *const mpz_t, d: *const mpz_t) void {
    if (q == d or r == d) {
        var dc: mpz_t = undefined;
        mpz_init(&dc);
        defer mpz_clear(&dc);
        mpz_set(&dc, d);
        mpz_fdiv_qr(q, r, n, &dc);
        return;
    }
    const sn = signOf(n);
    const sd = signOf(d);
    if (sd == 0) @panic("mpz division by zero");
    if (sn == 0) {
        ensureCapacity(q, 1);
        q._mp_size = 0;
        ensureCapacity(r, 1);
        r._mp_size = 0;
        return;
    }
    mpz_tdiv_qr(q, r, n, d);
    if (signOf(r) != 0 and (sn < 0) != (sd < 0)) {
        mpz_sub_ui(q, q, 1);
        mpz_add(r, r, d);
    }
}

pub export fn mpz_cdiv_q(q: *mpz_t, n: *const mpz_t, d: *const mpz_t) void {
    const sn = signOf(n);
    const sd = signOf(d);
    if (sd == 0) @panic("mpz division by zero");
    if (sn == 0) {
        ensureCapacity(q, 1);
        q._mp_size = 0;
        return;
    }
    var r: mpz_t = undefined;
    mpz_init(&r);
    defer mpz_clear(&r);
    mpz_tdiv_qr(q, &r, n, d);
    if (signOf(&r) != 0 and sn == sd)
        mpz_add_ui(q, q, 1);
}

// Floor division by a positive single-limb divisor; returns the
// nonnegative remainder (as GMP does).
pub export fn mpz_fdiv_q_ui(q: *mpz_t, n: *const mpz_t, d: c_ulong) u64 {
    const dd: u64 = @intCast(d);
    if (dd == 0) @panic("mpz division by zero");
    const an = limbCount(n);
    if (an == 0) {
        ensureCapacity(q, 1);
        q._mp_size = 0;
        return 0;
    }
    const qbuf = allocLimbs(an + 1) orelse oom();
    const rem = singleLimbDivMod(n, dd, qbuf);
    var used = an;
    while (used > 0 and qbuf[used - 1] == 0) used -= 1;
    const neg = signOf(n) < 0;
    if (neg and rem != 0) {
        commit(q, qbuf, an + 1, used, -1);
        mpz_sub_ui(q, q, 1); // floor rounds the negative quotient down
        return dd - rem;
    }
    commit(q, qbuf, an + 1, used, if (neg) -1 else 1);
    return rem;
}

pub export fn mpz_divexact(q: *mpz_t, n: *const mpz_t, d: *const mpz_t) void {
    const sd = signOf(d);
    if (sd == 0) @panic("mpz division by zero");
    if (signOf(n) == 0) {
        ensureCapacity(q, 1);
        q._mp_size = 0;
        return;
    }
    var r: mpz_t = undefined;
    mpz_init(&r);
    defer mpz_clear(&r);
    mpz_tdiv_qr(q, &r, n, d);
    if (signOf(&r) != 0) @panic("mpz_divexact: non-exact division");
}

// ---------- powers and gcd ----------

pub export fn mpz_init_set_ui(z: *mpz_t, u: c_ulong) void {
    mpz_init(z);
    mpz_set_ui(z, u);
}

pub export fn mpz_init_set_si(z: *mpz_t, i: c_long) void {
    mpz_init(z);
    mpz_set_si(z, i);
}

// ROP += |A| * |B| with full sign arithmetic. Any operand may alias ROP.
pub export fn mpz_addmul(rop: *mpz_t, a: *const mpz_t, b: *const mpz_t) void {
    var t: mpz_t = undefined;
    mpz_init(&t);
    defer mpz_clear(&t);
    mpz_mul(&t, a, b);
    mpz_add(rop, rop, &t);
}

pub export fn mpz_addmul_ui(rop: *mpz_t, a: *const mpz_t, u: c_ulong) void {
    var t: mpz_t = undefined;
    mpz_init(&t);
    defer mpz_clear(&t);
    mpz_mul_ui(&t, a, u);
    mpz_add(rop, rop, &t);
}

pub export fn mpz_submul(rop: *mpz_t, a: *const mpz_t, b: *const mpz_t) void {
    var t: mpz_t = undefined;
    mpz_init(&t);
    defer mpz_clear(&t);
    mpz_mul(&t, a, b);
    mpz_sub(rop, rop, &t);
}

// ROP = BASE^EXP by square-and-multiply; 0^0 = 1 (GMP convention) and
// ROP may alias BASE (data.c exponentiates mpz[0] in place).
pub export fn mpz_pow_ui(rop: *mpz_t, base: *const mpz_t, exp: c_ulong) void {
    if (exp == 0) {
        mpz_set_ui(rop, 1);
        return;
    }
    var b: mpz_t = undefined;
    mpz_init(&b);
    defer mpz_clear(&b);
    mpz_set(&b, base);
    if (signOf(&b) == 0) {
        mpz_set_ui(rop, 0);
        return;
    }
    var result: mpz_t = undefined;
    var factor: mpz_t = undefined;
    mpz_init(&result);
    mpz_init(&factor);
    defer mpz_clear(&result);
    defer mpz_clear(&factor);
    mpz_set_ui(&result, 1);
    mpz_set(&factor, &b);
    var e = exp;
    while (e != 0) {
        if (e & 1 == 1) mpz_mul(&result, &result, &factor);
        e >>= 1;
        if (e != 0) mpz_mul(&factor, &factor, &factor);
    }
    mpz_set(rop, &result);
}

pub export fn mpz_ui_pow_ui(rop: *mpz_t, base: c_ulong, exp: c_ulong) void {
    var b: mpz_t = undefined;
    mpz_init(&b);
    defer mpz_clear(&b);
    mpz_set_ui(&b, base);
    mpz_pow_ui(rop, &b, exp);
}

// ROP = gcd(|A|, |B|), always nonnegative; gcd(0, 0) = 0. ROP may alias
// A or B (timefns.c reduces tick/hz pairs in place).
pub export fn mpz_gcd(rop: *mpz_t, a: *const mpz_t, b: *const mpz_t) void {
    var x: mpz_t = undefined;
    var y: mpz_t = undefined;
    var r: mpz_t = undefined;
    mpz_init(&x);
    mpz_init(&y);
    mpz_init(&r);
    defer mpz_clear(&x);
    defer mpz_clear(&y);
    defer mpz_clear(&r);
    mpz_abs(&x, a);
    mpz_abs(&y, b);
    while (signOf(&y) != 0) {
        mpz_tdiv_r(&r, &x, &y);
        mpz_set(&x, &y);
        mpz_set(&y, &r);
    }
    mpz_set(rop, &x);
}

// ---------- bitwise ops ----------

// D = |a| op |b| (magnitudes only), committed with a positive sign.
fn magBitwise(rop: *mpz_t, a: *const mpz_t, b: *const mpz_t, kind: enum { band, bor, bxor }) void {
    const an = limbCount(a);
    const bn = limbCount(b);
    const n = switch (kind) {
        .band => @min(an, bn),
        else => @max(an, bn),
    };
    if (n == 0) {
        ensureCapacity(rop, 1);
        rop._mp_size = 0;
        return;
    }
    const res = allocLimbs(n) orelse oom();
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const av: u64 = if (i < an) a._mp_d.?[i] else 0;
        const bv: u64 = if (i < bn) b._mp_d.?[i] else 0;
        res[i] = switch (kind) {
            .band => av & bv,
            .bor => av | bv,
            .bxor => av ^ bv,
        };
    }
    var used = n;
    while (used > 0 and res[used - 1] == 0) used -= 1;
    commit(rop, res, n, used, 1);
}

// The and/ior/xor family follows GMP's infinite two's-complement model:
// a negative operand -X acts as ~(X - 1). The four sign combinations
// reduce to magnitude ops plus at most one subtract and one increment.
pub export fn mpz_and(rop: *mpz_t, a: *const mpz_t, b: *const mpz_t) void {
    const na = signOf(a) < 0;
    const nb = signOf(b) < 0;
    var x: mpz_t = undefined;
    var y: mpz_t = undefined;
    mpz_init(&x);
    mpz_init(&y);
    defer mpz_clear(&x);
    defer mpz_clear(&y);
    mpz_abs(&x, a);
    mpz_abs(&y, b);
    if (na) mpz_sub_ui(&x, &x, 1);
    if (nb) mpz_sub_ui(&y, &y, 1);
    if (!na and !nb) {
        magBitwise(rop, &x, &y, .band);
    } else if (na and nb) {
        // ~X & ~Y = ~(X | Y) = -(X | Y) - 1
        magBitwise(rop, &x, &y, .bor);
        mpz_add_ui(rop, rop, 1);
        mpz_neg(rop, rop);
    } else {
        // ~X & Y = Y - (X & Y) (and symmetrically)
        magBitwise(rop, &x, &y, .band);
        if (na) mpz_sub(rop, &y, rop) else mpz_sub(rop, &x, rop);
    }
}

pub export fn mpz_ior(rop: *mpz_t, a: *const mpz_t, b: *const mpz_t) void {
    const na = signOf(a) < 0;
    const nb = signOf(b) < 0;
    var x: mpz_t = undefined;
    var y: mpz_t = undefined;
    mpz_init(&x);
    mpz_init(&y);
    defer mpz_clear(&x);
    defer mpz_clear(&y);
    mpz_abs(&x, a);
    mpz_abs(&y, b);
    if (na) mpz_sub_ui(&x, &x, 1);
    if (nb) mpz_sub_ui(&y, &y, 1);
    if (!na and !nb) {
        magBitwise(rop, &x, &y, .bor);
    } else if (na and nb) {
        // ~X | ~Y = ~(X & Y) = -(X & Y) - 1
        magBitwise(rop, &x, &y, .band);
        mpz_add_ui(rop, rop, 1);
        mpz_neg(rop, rop);
    } else {
        // ~X | Y = ~(X & ~Y) = -(X - (X & Y)) - 1
        magBitwise(rop, &x, &y, .band);
        if (na) mpz_sub(rop, &x, rop) else mpz_sub(rop, &y, rop);
        mpz_add_ui(rop, rop, 1);
        mpz_neg(rop, rop);
    }
}

pub export fn mpz_xor(rop: *mpz_t, a: *const mpz_t, b: *const mpz_t) void {
    const na = signOf(a) < 0;
    const nb = signOf(b) < 0;
    var x: mpz_t = undefined;
    var y: mpz_t = undefined;
    mpz_init(&x);
    mpz_init(&y);
    defer mpz_clear(&x);
    defer mpz_clear(&y);
    mpz_abs(&x, a);
    mpz_abs(&y, b);
    if (na) mpz_sub_ui(&x, &x, 1);
    if (nb) mpz_sub_ui(&y, &y, 1);
    if (na == nb) {
        // X ^ Y, or ~X ^ ~Y = X ^ Y
        magBitwise(rop, &x, &y, .bxor);
    } else {
        // ~X ^ Y = ~(X ^ Y) = -(X ^ Y) - 1
        magBitwise(rop, &x, &y, .bxor);
        mpz_add_ui(rop, rop, 1);
        mpz_neg(rop, rop);
    }
}

// ROP = ~A = -A - 1.
pub export fn mpz_com(rop: *mpz_t, a: *const mpz_t) void {
    var t: mpz_t = undefined;
    mpz_init(&t);
    defer mpz_clear(&t);
    mpz_neg(&t, a);
    mpz_sub_ui(&t, &t, 1);
    mpz_set(rop, &t);
}

pub export fn mpz_odd_p(a: *const mpz_t) c_int {
    if (signOf(a) == 0) return 0;
    return if (a._mp_d.?[0] & 1 == 1) 1 else 0;
}

// GMP defines popcount on the two's-complement representation, which is
// infinite for negatives; it returns ULONG_MAX in that case.
pub export fn mpz_popcount(a: *const mpz_t) c_ulong {
    if (signOf(a) < 0) return std.math.maxInt(c_ulong);
    const an = limbCount(a);
    var count: c_ulong = 0;
    var i: usize = 0;
    while (i < an) : (i += 1) count += @popCount(a._mp_d.?[i]);
    return count;
}

// Scan LIMBS for the first set bit at or after START, treating the limbs
// as complemented when NEG (the two's complement of a negative value).
fn scanLimbBits(neg: bool, limbs: [*]const mp_limb_t, an: usize, start: mp_bitcnt_t) c_ulong {
    const start_limb: usize = @intCast(start / GMP_NUMB_BITS);
    const start_bit: u6 = @intCast(start % GMP_NUMB_BITS);
    var i = start_limb;
    while (i <= an) : (i += 1) {
        var limb: u64 = 0;
        if (i < an) {
            limb = if (neg) ~limbs[i] else limbs[i];
        } else {
            if (!neg) break;
            limb = std.math.maxInt(u64);
        }
        const skip: u6 = if (i == start_limb) start_bit else 0;
        const shifted = limb >> skip;
        if (shifted != 0) {
            const idx: u6 = @intCast(@ctz(shifted));
            return @intCast(i * GMP_NUMB_BITS + @as(usize, skip) + idx);
        }
        if (i == an) break; // negative: the infinite 1s start here
    }
    return std.math.maxInt(c_ulong);
}

// Index of the first set bit at or after START in the two's-complement
// representation, or ULONG_MAX when none exists.
pub export fn mpz_scan1(a: *const mpz_t, start: mp_bitcnt_t) c_ulong {
    const an = limbCount(a);
    if (signOf(a) >= 0) return scanLimbBits(false, a._mp_d.?, an, start);
    var t: mpz_t = undefined;
    mpz_init(&t);
    defer mpz_clear(&t);
    mpz_abs(&t, a);
    mpz_sub_ui(&t, &t, 1); // two's complement of -x is ~(x - 1)
    return scanLimbBits(true, t._mp_d.?, limbCount(&t), start);
}

// ---------- limbs API ----------

// Limb N of the magnitude (GMP ignores the sign); 0 when out of range.
pub export fn mpz_getlimbn(a: *const mpz_t, n: mp_size_t) mp_limb_t {
    if (n < 0) return 0;
    const idx: usize = @intCast(n);
    if (idx >= limbCount(a)) return 0;
    return a._mp_d.?[idx];
}

pub export fn mpz_limbs_read(a: *const mpz_t) ?[*]mp_limb_t {
    return a._mp_d;
}

// Grow ROP to hold at least N limbs and return a pointer to the array.
pub export fn mpz_limbs_write(rop: *mpz_t, n: mp_size_t) ?[*]mp_limb_t {
    if (n < 0) @panic("mpz_limbs_write: negative count");
    const need: usize = @intCast(n);
    ensureCapacity(rop, need);
    return rop._mp_d;
}

// Commit a limb array written through mpz_limbs_write: SIZE is the signed
// limb count (GMP trusts the caller, so no trimming happens here).
pub export fn mpz_limbs_finish(rop: *mpz_t, size: mp_size_t) void {
    // GMP's mpz_limbs_finish trusts the caller's size; Emacs's random
    // bignum path can pass a count whose top limb is zero. Normalize so
    // every subsequent operation sees a canonical representation.
    const neg = size < 0;
    var n: usize = if (neg) @intCast(-size) else @intCast(size);
    if (rop._mp_d) |d| {
        while (n > 0 and d[n - 1] == 0) n -= 1;
    }
    if (n == 0) {
        rop._mp_size = 0;
        return;
    }
    rop._mp_size = if (neg) -@as(c_int, @intCast(n)) else @as(c_int, @intCast(n));
}

// Point X at the read-only limb array XP without allocating; the returned
// value is X itself. A later mpz_clear is safe (_mp_alloc is 0).
pub export fn mpz_roinit_n(x: *mpz_t, xp: [*]const mp_limb_t, xs: mp_size_t) *const mpz_t {
    x._mp_alloc = 0;
    x._mp_size = @intCast(xs);
    x._mp_d = @constCast(xp);
    return x;
}

// ---------- byte import/export ----------

const nativeLittle = @import("builtin").cpu.arch.endian() == .little;

fn endianLittle(endian: c_int) bool {
    return if (endian == 0) nativeLittle else endian < 0;
}

// Import COUNT words of SIZE bytes each, covering the |value|; ORDER is
// 1 for most-significant-word-first, -1 for least-first, 0 acts as 1
// (GMP's convention); ENDIAN is 1 big / -1 little / 0 native. Nails=0.
pub export fn mpz_import(rop: *mpz_t, count: usize, order: c_int, size: usize, endian: c_int, nails: usize, op: ?*const anyopaque) void {
    if (nails != 0) @panic("mpz_import: nails not supported");
    if (size > 8) @panic("mpz_import: word size over 8 bytes");
    if (size == 0 or count == 0 or op == null) {
        mpz_set_ui(rop, 0);
        return;
    }
    const bytes: [*]const u8 = @ptrCast(op.?);
    const little = endianLittle(endian);
    const lsw_first = order < 0;
    const total = count * size;
    const nlimbs = (total + 7) / 8;
    const res = allocLimbs(nlimbs) orelse oom();
    @memset(res[0..nlimbs], 0);
    var li: usize = 0;
    var cur: u64 = 0;
    var curbytes: u7 = 0;
    var wi: usize = 0;
    while (wi < count) : (wi += 1) {
        const mem_idx = if (lsw_first) wi else count - 1 - wi;
        const wptr = bytes + mem_idx * size;
        var bi: usize = 0;
        while (bi < size) : (bi += 1) {
            const byte = wptr[if (little) bi else size - 1 - bi];
            cur |= @as(u64, byte) << @intCast(8 * curbytes);
            curbytes += 1;
            if (curbytes == 8) {
                res[li] = cur;
                li += 1;
                cur = 0;
                curbytes = 0;
            }
        }
    }
    if (curbytes != 0) {
        res[li] = cur;
        li += 1;
    }
    var used = nlimbs;
    while (used > 0 and res[used - 1] == 0) used -= 1;
    commit(rop, res, nlimbs, used, 1);
}

// Export the |value| as whole words into ROP; *COUNTP receives the word
// count (zero for zero), and ROP is returned. The caller must size ROP
// for mpz_sizeinbase-based estimates.
pub export fn mpz_export(rop: ?*anyopaque, countp: ?*usize, order: c_int, size: usize, endian: c_int, nails: usize, op: *const mpz_t) ?*anyopaque {
    if (nails != 0) @panic("mpz_export: nails not supported");
    if (size == 0 or size > 8) @panic("mpz_export: unsupported word size");
    const bits = bitLength(op);
    const sigbytes = (bits + 7) / 8;
    const count = (sigbytes + size - 1) / size;
    if (countp) |cp| cp.* = count;
    if (rop == null or count == 0) return rop;
    const bytes: [*]u8 = @ptrCast(rop.?);
    @memset(bytes[0 .. count * size], 0);
    const little = endianLittle(endian);
    const lsw_first = order < 0;
    var wi: usize = 0;
    while (wi < count) : (wi += 1) {
        const mem_idx = if (lsw_first) wi else count - 1 - wi;
        const wptr = bytes + mem_idx * size;
        var bi: usize = 0;
        while (bi < size) : (bi += 1) {
            const bpos = wi * size + bi;
            const byte: u8 = if (bpos < sigbytes)
                @as(u8, @truncate(op._mp_d.?[bpos / 8] >> @intCast(8 * (bpos % 8))))
            else
                0;
            wptr[if (little) bi else size - 1 - bi] = byte;
        }
    }
    return rop;
}

// ---------- string conversion ----------

// Digit value of byte C in the given BASE (2..62), matching GMP:
// '0'-'9' are 0-9, and for bases <= 36 both letter cases are 10-35,
// while for bases 37..62 'A'-'Z' are 10-35 and 'a'-'z' are 36-61.
fn digitToVal(c: u8, base: usize) ?u8 {
    const v: u8 = switch (c) {
        '0'...'9' => c - '0',
        'a'...'z' => if (base <= 36) c - 'a' + 10 else c - 'a' + 36,
        'A'...'Z' => c - 'A' + 10,
        else => return null,
    };
    return if (v < base) v else null;
}

// Character for digit value V in the given BASE; UPPER selects
// upper-case letters for bases 2..36 (GMP's negative-base behavior).
fn digitToChar(v: u8, base: usize, upper: bool) u8 {
    if (v < 10) return '0' + v;
    if (base <= 36) return @as(u8, if (upper) 'A' else 'a') + (v - 10);
    // Bases 37..62 always use 'A'-'Z' for 10..35 then 'a'-'z'.
    return @as(u8, if (v <= 35) 'A' else 'a') + (if (v <= 35) v - 10 else v - 36);
}

// Parse STR as a base-BASE integer into ROP, matching GMP's mpz_set_str:
// leading/trailing whitespace is skipped, whitespace between digits is
// ignored, a single leading '-' is allowed (no '+'), base 0 detects the
// 0x/0X, 0b/0B and leading-0 (octal) prefixes, any other non-digit makes
// the whole parse fail (returning -1 and leaving ROP untouched), and a
// bare "0x"/"0b" prefix parses as zero. BASE may be 0 or 2..62.
pub export fn mpz_set_str(rop: *mpz_t, str: [*:0]const u8, base_in: c_int) c_int {
    if (base_in < 0 or base_in > 62 or base_in == 1) return -1;
    var base: usize = @intCast(base_in);
    var p = str;
    while (std.ascii.isWhitespace(p[0])) p += 1;
    var neg = false;
    if (p[0] == '-') {
        neg = true;
        p += 1;
    }
    var prefix = false;
    if (base == 0) {
        if (p[0] == '0' and (p[1] == 'x' or p[1] == 'X')) {
            base = 16;
            prefix = true;
            p += 2;
        } else if (p[0] == '0' and (p[1] == 'b' or p[1] == 'B')) {
            base = 2;
            prefix = true;
            p += 2;
        } else if (p[0] == '0') {
            base = 8;
        } else {
            base = 10;
        }
    }
    var have_digit = false;
    var acc: mpz_t = undefined;
    mpz_init(&acc);
    defer mpz_clear(&acc);
    while (true) {
        const c = p[0];
        if (c == 0) break;
        if (std.ascii.isWhitespace(c)) {
            p += 1;
            continue;
        }
        const v = digitToVal(c, base) orelse return -1;
        have_digit = true;
        mpz_mul_ui(&acc, &acc, @intCast(base));
        mpz_add_ui(&acc, &acc, @intCast(v));
        p += 1;
    }
    if (!have_digit and !prefix) return -1;
    if (neg) mpz_neg(&acc, &acc);
    mpz_swap(rop, &acc);
    return 0;
}

// Convert OP to a base-BASE string into STR (allocated via the memory
// callbacks when STR is null), matching GMP: negative BASE means
// upper-case digits, the buffer needs mpz_sizeinbase + 2 bytes, and the
// returned pointer is STR (or the freshly allocated buffer).
pub export fn mpz_get_str(str: ?[*]u8, base_in: c_int, op: *const mpz_t) ?[*]u8 {
    const upper = base_in < 0;
    const base: usize = if (base_in < 0) @intCast(-base_in) else @intCast(base_in);
    if (base < 2 or base > 62) return null;
    const cap: usize = @intCast(mpz_sizeinbase(op, @intCast(base)) + 2);
    var owned = false;
    var buf: [*]u8 = undefined;
    if (str) |s| {
        buf = s;
    } else {
        buf = @ptrCast(g_alloc(cap) orelse oom());
        owned = true;
    }
    var end = buf + cap - 1;
    end[0] = 0;
    var p = end;
    var t: mpz_t = undefined;
    mpz_init(&t);
    defer mpz_clear(&t);
    mpz_abs(&t, op);
    while (limbCount(&t) != 0) {
        const v: u8 = @intCast(mpz_fdiv_q_ui(&t, &t, @intCast(base)));
        p -= 1;
        p[0] = digitToChar(v, base, upper);
    }
    if (p == end) {
        p -= 1;
        p[0] = '0';
    }
    if (op._mp_size < 0) {
        p -= 1;
        p[0] = '-';
    }
    if (p != buf) {
        const len = end - p;
        std.mem.copyForwards(u8, buf[0..len], p[0..len]);
        buf[len] = 0;
    }
    return if (owned) buf else str;
}

// ---------- double conversion ----------

// Convert OP to a double, truncating toward zero (GMP semantics);
// magnitudes too large for a double become (+/-)infinity.
pub export fn mpz_get_d(op: *const mpz_t) f64 {
    const n = limbCount(op);
    if (n == 0) return 0;
    const d = op._mp_d.?;
    const hi = d[n - 1];
    const topbits: u64 = 64 - @as(u64, @clz(hi));
    var mant: u64 = undefined;
    var exp: i64 = undefined;
    if (topbits >= 53) {
        const sh: u6 = @intCast(topbits - 53);
        mant = hi >> sh;
        exp = @as(i64, @intCast(64 * (n - 1) + (topbits - 53)));
    } else if (n >= 2) {
        const lo = d[n - 2];
        const combined: u128 = (@as(u128, hi) << 64) | lo;
        const sh: u7 = @intCast(64 + topbits - 53);
        mant = @as(u64, @truncate(combined >> sh));
        exp = @as(i64, @intCast(64 * (n - 2) + (64 + topbits - 53)));
    } else {
        const sh: u6 = @intCast(53 - topbits);
        mant = hi << sh;
        exp = -@as(i64, @intCast(53 - topbits));
    }
    var result = @as(f64, @floatFromInt(mant)) * @exp2(@as(f64, @floatFromInt(exp)));
    if (op._mp_size < 0) result = -result;
    return result;
}

// Convert D to an mpz, truncating toward zero (GMP semantics). GMP
// aborts on NaN/Inf; we map those to zero instead, and Emacs never
// passes them here.
pub export fn mpz_set_d(rop: *mpz_t, d: f64) void {
    if (std.math.isNan(d) or std.math.isInf(d) or d == 0) {
        mpz_set_ui(rop, 0);
        return;
    }
    const neg = d < 0;
    const mag = if (neg) -d else d;
    const bits: u64 = @bitCast(mag);
    const e: i64 = @as(i64, @intCast((bits >> 52) & 0x7FF)) - 1023;
    if (e < 0) {
        mpz_set_ui(rop, 0); // |d| < 1 (including subnormals) truncates to 0.
        return;
    }
    const frac: u64 = (bits & 0xFFFFFFFFFFFFF) | 0x10000000000000;
    var t: mpz_t = undefined;
    mpz_init(&t);
    defer mpz_clear(&t);
    if (e >= 52) {
        mpz_set_u64(&t, frac);
        if (e > 52) mpz_mul_2exp(&t, &t, @intCast(e - 52));
    } else {
        const sh: u6 = @intCast(52 - e);
        mpz_set_u64(&t, frac >> sh);
    }
    if (neg) mpz_neg(&t, &t);
    mpz_swap(rop, &t);
}

// Compare OP with D exactly (no truncation of D), like GMP's
// mpz_cmp_d. NaN never reaches this from Emacs (guarded at the call
// sites); we return 0 for it, where GMP would abort.
pub export fn mpz_cmp_d(op: *const mpz_t, d: f64) c_int {
    if (std.math.isNan(d)) return 0;
    if (std.math.isInf(d)) return if (d > 0) -1 else 1;
    const sgn = signOf(op);
    if (sgn == 0) return if (d > 0) -1 else if (d < 0) 1 else 0;
    var t: mpz_t = undefined;
    mpz_init(&t);
    defer mpz_clear(&t);
    if (sgn < 0) {
        if (d >= 0) return -1;
        mpz_set_d(&t, -d);
        const c = mpz_cmpabs(op, &t);
        if (c != 0) return -c;
        return if (d == @trunc(d)) 0 else 1;
    } else {
        if (d <= 0) return 1;
        mpz_set_d(&t, d);
        const c = mpz_cmpabs(op, &t);
        if (c != 0) return c;
        return if (d == @trunc(d)) 0 else -1;
    }
}

// ---------- fit predicates ----------

fn fitsSigned(z: *const mpz_t, lo: i64, hi: i64) bool {
    const sgn = signOf(z);
    if (sgn == 0) return true;
    if (sgn < 0) return mpz_cmp_si(z, @intCast(lo)) >= 0;
    return mpz_cmp_si(z, @intCast(hi)) <= 0;
}

fn fitsUnsigned(z: *const mpz_t, hi: u64) bool {
    if (signOf(z) < 0) return false;
    return mpz_cmp_ui(z, @intCast(hi)) <= 0;
}

pub export fn mpz_fits_sint_p(z: *const mpz_t) c_int {
    return @intFromBool(fitsSigned(z, std.math.minInt(c_int), std.math.maxInt(c_int)));
}

pub export fn mpz_fits_slong_p(z: *const mpz_t) c_int {
    return @intFromBool(fitsSigned(z, std.math.minInt(c_long), std.math.maxInt(c_long)));
}

pub export fn mpz_fits_ulong_p(z: *const mpz_t) c_int {
    return @intFromBool(fitsUnsigned(z, std.math.maxInt(c_ulong)));
}

// Test helper: build a magnitude from LIMBS pseudo-random limbs.
fn rndMagTest(z: *mpz_t, limbs: usize, seed: *u64) void {
    mpz_set_ui(z, 0);
    var i: usize = 0;
    while (i < limbs) : (i += 1) {
        seed.* = seed.* *% 6364136223846793005 +% 1442695040888963407;
        const limb = seed.* ^ (seed.* >> 33);
        mpz_mul_2exp(z, z, 64);
        mpz_add_ui(z, z, limb);
    }
}

test "mpz set get swap neg abs sgn" {
    var z: mpz_t = undefined;
    mpz_init(&z);
    defer mpz_clear(&z);
    try std.testing.expectEqual(@as(c_int, 0), mpz_sgn(&z));
    mpz_set_ui(&z, 0xDEADBEEFCAFEBABE);
    try std.testing.expectEqual(@as(u64, 0xDEADBEEFCAFEBABE), mpz_get_ui(&z));
    try std.testing.expectEqual(@as(c_int, 1), mpz_sgn(&z));
    mpz_neg(&z, &z);
    try std.testing.expectEqual(@as(c_int, -1), mpz_sgn(&z));
    try std.testing.expectEqual(@as(u64, 0xDEADBEEFCAFEBABE), mpz_get_ui(&z));
    mpz_abs(&z, &z);
    try std.testing.expectEqual(@as(c_int, 1), mpz_sgn(&z));
    var other: mpz_t = undefined;
    mpz_init(&other);
    defer mpz_clear(&other);
    mpz_set_si(&other, -42);
    try std.testing.expectEqual(@as(i64, -42), mpz_get_si(&other));
    mpz_swap(&z, &other);
    try std.testing.expectEqual(@as(u64, 0xDEADBEEFCAFEBABE), mpz_get_ui(&other));
    try std.testing.expectEqual(@as(i64, -42), mpz_get_si(&z));
}

test "mpz cmp family" {
    var a: mpz_t = undefined;
    var b: mpz_t = undefined;
    mpz_init(&a);
    mpz_init(&b);
    defer mpz_clear(&a);
    defer mpz_clear(&b);
    mpz_set_ui(&a, 100);
    mpz_set_ui(&b, 100);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&a, &b));
    mpz_set_ui(&b, 101);
    try std.testing.expectEqual(@as(c_int, -1), mpz_cmp(&a, &b));
    mpz_set_ui(&b, 99);
    try std.testing.expectEqual(@as(c_int, 1), mpz_cmp(&a, &b));
    try std.testing.expectEqual(@as(c_int, 1), mpz_cmp_ui(&a, 99));
    try std.testing.expectEqual(@as(c_int, -1), mpz_cmp_si(&a, 101));
    mpz_neg(&b, &a);
    try std.testing.expectEqual(@as(c_int, -1), mpz_cmp(&b, &a));
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmpabs(&a, &b));
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmpabs(&b, &a));
}

test "mpz add sub carry across limbs" {
    var a: mpz_t = undefined;
    var b: mpz_t = undefined;
    var r: mpz_t = undefined;
    mpz_init(&a);
    mpz_init(&b);
    mpz_init(&r);
    defer mpz_clear(&a);
    defer mpz_clear(&b);
    defer mpz_clear(&r);
    const hi = 0xFFFFFFFFFFFFFFFF;
    const lo = 0xFFFFFFFFFFFFFFFF;
    mpz_set_ui(&a, hi);
    mpz_mul_2exp(&a, &a, 64);
    mpz_add_ui(&a, &a, lo); // a = 2^128 - 1
    mpz_set_ui(&b, 1);
    mpz_add(&r, &a, &b); // r = 2^128
    try std.testing.expectEqual(@as(isize, 3), mpz_size(&r));
    mpz_sub(&r, &r, &b); // r = 2^128 - 1
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&r, &a));
    mpz_set_ui(&b, hi);
    mpz_sub_ui(&b, &b, 5);
    mpz_set_ui(&a, 1);
    mpz_sub(&r, &b, &a); // (2^64-5) - 1
    try std.testing.expectEqual(@as(u64, hi - 6), mpz_get_ui(&r));
    // 2^128 - 1 - (2^64) = 2^64 - 1, borrowing across limbs
    mpz_set_ui(&b, 1);
    mpz_mul_2exp(&b, &b, 64);
    mpz_sub(&r, &a, &b);
    try std.testing.expectEqual(@as(u64, lo), mpz_get_ui(&r));
    try std.testing.expectEqual(@as(isize, 1), mpz_size(&r));
}

test "mpz mul schoolbook" {
    var a: mpz_t = undefined;
    var b: mpz_t = undefined;
    var r: mpz_t = undefined;
    mpz_init(&a);
    mpz_init(&b);
    mpz_init(&r);
    defer mpz_clear(&a);
    defer mpz_clear(&b);
    defer mpz_clear(&r);
    mpz_set_ui(&a, 123456789);
    mpz_set_ui(&b, 987654321);
    mpz_mul(&r, &a, &b);
    try std.testing.expectEqual(@as(u64, 121932631112635269), mpz_get_ui(&r));
    // (2^64 - 1)^2 exercises 128-bit multiplication
    mpz_set_ui(&a, 0xFFFFFFFFFFFFFFFF);
    mpz_set_ui(&b, 0xFFFFFFFFFFFFFFFF);
    mpz_mul(&r, &a, &b);
    // = 2^128 - 2^65 + 1
    var expect: mpz_t = undefined;
    mpz_init(&expect);
    defer mpz_clear(&expect);
    mpz_set_ui(&expect, 1);
    mpz_mul_2exp(&expect, &expect, 128);
    mpz_sub_ui(&expect, &expect, 1);
    mpz_mul_2exp(&expect, &expect, 0);
    mpz_sub_ui(&expect, &expect, 0xFFFFFFFFFFFFFFFF);
    mpz_sub_ui(&expect, &expect, 0xFFFFFFFFFFFFFFFF);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&r, &expect));
}

test "mpz mul_ui and sign" {
    var a: mpz_t = undefined;
    var r: mpz_t = undefined;
    mpz_init(&a);
    mpz_init(&r);
    defer mpz_clear(&a);
    defer mpz_clear(&r);
    mpz_set_ui(&a, 0xFFFFFFFFFFFFFFFF);
    mpz_mul_ui(&r, &a, 3); // 3 * (2^64 - 1) = 2^66 - 3
    try std.testing.expectEqual(@as(u64, 0xFFFFFFFFFFFFFFFD), mpz_get_ui(&r));
    try std.testing.expectEqual(@as(isize, 2), mpz_size(&r));
    mpz_neg(&a, &a);
    mpz_mul_ui(&r, &a, 3);
    try std.testing.expectEqual(@as(c_int, -1), mpz_sgn(&r));
}

test "mpz sizeinbase" {
    var z: mpz_t = undefined;
    mpz_init(&z);
    defer mpz_clear(&z);
    mpz_set_ui(&z, 0);
    try std.testing.expectEqual(@as(usize, 1), mpz_sizeinbase(&z, 10));
    mpz_set_ui(&z, 255);
    try std.testing.expectEqual(@as(usize, 8), mpz_sizeinbase(&z, 2));
    try std.testing.expectEqual(@as(usize, 2), mpz_sizeinbase(&z, 16));
    try std.testing.expectEqual(@as(usize, 3), mpz_sizeinbase(&z, 10));
    mpz_set_ui(&z, 1);
    mpz_mul_2exp(&z, &z, 100); // 2^100
    try std.testing.expectEqual(@as(usize, 101), mpz_sizeinbase(&z, 2));
    try std.testing.expectEqual(@as(usize, 31), mpz_sizeinbase(&z, 10));
}

test "mpz fdiv_q_2exp floor semantics" {
    var a: mpz_t = undefined;
    var r: mpz_t = undefined;
    mpz_init(&a);
    mpz_init(&r);
    defer mpz_clear(&a);
    defer mpz_clear(&r);
    mpz_set_ui(&a, 7);
    mpz_fdiv_q_2exp(&r, &a, 2); // 7 >> 2 = 1
    try std.testing.expectEqual(@as(u64, 1), mpz_get_ui(&r));
    mpz_neg(&a, &a); // -7
    mpz_fdiv_q_2exp(&r, &a, 2); // floor(-7/4) = -2
    try std.testing.expectEqual(@as(i64, -2), mpz_get_si(&r));
    mpz_fdiv_q_2exp(&r, &a, 1); // floor(-7/2) = -4
    try std.testing.expectEqual(@as(i64, -4), mpz_get_si(&r));
    mpz_fdiv_q_2exp(&r, &a, 10); // floor(-7/1024) = -1
    try std.testing.expectEqual(@as(i64, -1), mpz_get_si(&r));
    // exact division: -8 / 2 = -4
    mpz_set_si(&a, -8);
    mpz_fdiv_q_2exp(&r, &a, 1);
    try std.testing.expectEqual(@as(i64, -4), mpz_get_si(&r));
}

test "mpz sub with an unnormalized leading-zero-limb operand" {
    // Emacs's get_random_bignum finishes a 2-limb buffer whose top limb
    // can be zero; the value must still compare and subtract by value.
    var z: mpz_t = undefined;
    var n: mpz_t = undefined;
    var half: mpz_t = undefined;
    mpz_init(&z);
    mpz_init(&n);
    mpz_init(&half);
    defer mpz_clear(&z);
    defer mpz_clear(&n);
    defer mpz_clear(&half);

    const limbs = mpz_limbs_write(&n, 2).?;
    limbs[0] = 8554759657629807981;
    limbs[1] = 0; // phantom leading zero limb, as the random path can leave
    mpz_limbs_finish(&n, 2);
    try std.testing.expectEqual(@as(isize, 1), mpz_size(&n));

    mpz_set_ui(&half, 9223372036854775808); // 2^63
    mpz_sub(&z, &n, &half);
    try std.testing.expectEqual(@as(i64, -668612379224967827), mpz_get_si(&z));
    mpz_sub(&z, &half, &n);
    try std.testing.expectEqual(@as(i64, 668612379224967827), mpz_get_si(&z));
}

test "mpz tdiv fdiv cdiv signed small cases" {
    const Cases = struct { n: i64, d: i64, tq: i64, tr: i64, fq: i64, fr: i64, cq: i64 };
    const cases = [_]Cases{
        .{ .n = 7, .d = 3, .tq = 2, .tr = 1, .fq = 2, .fr = 1, .cq = 3 },
        .{ .n = -7, .d = 3, .tq = -2, .tr = -1, .fq = -3, .fr = 2, .cq = -2 },
        .{ .n = 7, .d = -3, .tq = -2, .tr = 1, .fq = -3, .fr = -2, .cq = -2 },
        .{ .n = -7, .d = -3, .tq = 2, .tr = -1, .fq = 2, .fr = -1, .cq = 3 },
    };
    var n: mpz_t = undefined;
    var d: mpz_t = undefined;
    var q: mpz_t = undefined;
    var r: mpz_t = undefined;
    mpz_init(&n);
    mpz_init(&d);
    mpz_init(&q);
    mpz_init(&r);
    defer mpz_clear(&n);
    defer mpz_clear(&d);
    defer mpz_clear(&q);
    defer mpz_clear(&r);
    for (cases) |c| {
        mpz_set_si(&n, c.n);
        mpz_set_si(&d, c.d);
        mpz_tdiv_qr(&q, &r, &n, &d);
        try std.testing.expectEqual(@as(i64, c.tq), mpz_get_si(&q));
        try std.testing.expectEqual(@as(i64, c.tr), mpz_get_si(&r));
        mpz_tdiv_q(&q, &n, &d);
        try std.testing.expectEqual(@as(i64, c.tq), mpz_get_si(&q));
        mpz_tdiv_r(&r, &n, &d);
        try std.testing.expectEqual(@as(i64, c.tr), mpz_get_si(&r));
        mpz_fdiv_qr(&q, &r, &n, &d);
        try std.testing.expectEqual(@as(i64, c.fq), mpz_get_si(&q));
        try std.testing.expectEqual(@as(i64, c.fr), mpz_get_si(&r));
        mpz_fdiv_q(&q, &n, &d);
        try std.testing.expectEqual(@as(i64, c.fq), mpz_get_si(&q));
        mpz_fdiv_r(&r, &n, &d);
        try std.testing.expectEqual(@as(i64, c.fr), mpz_get_si(&r));
        mpz_cdiv_q(&q, &n, &d);
        try std.testing.expectEqual(@as(i64, c.cq), mpz_get_si(&q));
    }
}

test "mpz tdiv_ui and fdiv_q_ui" {
    var n: mpz_t = undefined;
    var q: mpz_t = undefined;
    mpz_init(&n);
    mpz_init(&q);
    defer mpz_clear(&n);
    defer mpz_clear(&q);

    mpz_set_si(&n, -7);
    try std.testing.expectEqual(@as(u64, 1), mpz_tdiv_ui(&n, 3));
    try std.testing.expectEqual(@as(u64, 2), mpz_fdiv_q_ui(&q, &n, 3));
    try std.testing.expectEqual(@as(i64, -3), mpz_get_si(&q));

    mpz_set_si(&n, 7);
    try std.testing.expectEqual(@as(u64, 1), mpz_tdiv_ui(&n, 3));
    try std.testing.expectEqual(@as(u64, 1), mpz_fdiv_q_ui(&q, &n, 3));
    try std.testing.expectEqual(@as(i64, 2), mpz_get_si(&q));

    // Exact division: no floor adjustment for negatives.
    mpz_set_si(&n, -6);
    try std.testing.expectEqual(@as(u64, 0), mpz_tdiv_ui(&n, 3));
    try std.testing.expectEqual(@as(u64, 0), mpz_fdiv_q_ui(&q, &n, 3));
    try std.testing.expectEqual(@as(i64, -2), mpz_get_si(&q));

    // Multi-limb floor adjustment: -(2^64 - 2) / 3 = -6148914691236517205,
    // remainder 1 (values verified against libgmp).
    mpz_set_ui(&n, 0xFFFFFFFFFFFFFFFE);
    try std.testing.expectEqual(@as(u64, 2), mpz_tdiv_ui(&n, 3));
    try std.testing.expectEqual(@as(u64, 2), mpz_fdiv_q_ui(&q, &n, 3));
    try std.testing.expectEqual(@as(u64, 6148914691236517204), mpz_get_ui(&q));
    mpz_neg(&n, &n);
    try std.testing.expectEqual(@as(u64, 2), mpz_tdiv_ui(&n, 3));
    try std.testing.expectEqual(@as(u64, 1), mpz_fdiv_q_ui(&q, &n, 3));
    try std.testing.expectEqual(@as(i64, -6148914691236517205), mpz_get_si(&q));
}

test "mpz multi-limb division exact and known quotients" {
    var n: mpz_t = undefined;
    var d: mpz_t = undefined;
    var q: mpz_t = undefined;
    var r: mpz_t = undefined;
    var chk: mpz_t = undefined;
    mpz_init(&n);
    mpz_init(&d);
    mpz_init(&q);
    mpz_init(&r);
    mpz_init(&chk);
    defer mpz_clear(&n);
    defer mpz_clear(&d);
    defer mpz_clear(&q);
    defer mpz_clear(&r);
    defer mpz_clear(&chk);

    // (2^128 - 1) * (2^64 + 1) divided by (2^64 + 1) is exact, quotient 2^128-1.
    mpz_set_ui(&n, 1);
    mpz_mul_2exp(&n, &n, 128);
    mpz_sub_ui(&n, &n, 1);
    mpz_set_ui(&d, 1);
    mpz_mul_2exp(&d, &d, 64);
    mpz_add_ui(&d, &d, 1);
    mpz_mul(&n, &n, &d);
    mpz_tdiv_qr(&q, &r, &n, &d);
    try std.testing.expectEqual(@as(c_int, 0), mpz_sgn(&r));
    mpz_set_ui(&chk, 1);
    mpz_mul_2exp(&chk, &chk, 128);
    mpz_sub_ui(&chk, &chk, 1);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&q, &chk));

    // 2^192 - 1 over 2^96 - 1: quotient 2^96 + 1, remainder 0.
    mpz_set_ui(&n, 1);
    mpz_mul_2exp(&n, &n, 192);
    mpz_sub_ui(&n, &n, 1);
    mpz_set_ui(&d, 1);
    mpz_mul_2exp(&d, &d, 96);
    mpz_sub_ui(&d, &d, 1);
    mpz_tdiv_qr(&q, &r, &n, &d);
    try std.testing.expectEqual(@as(c_int, 0), mpz_sgn(&r));
    mpz_set_ui(&chk, 1);
    mpz_mul_2exp(&chk, &chk, 96);
    mpz_add_ui(&chk, &chk, 1);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&q, &chk));

    // (2^64 - 1)^2 over 2^64 - 2: quotient 2^64, remainder 1
    // (exercises the qhat-overestimation correction).
    mpz_set_ui(&n, 0xFFFFFFFFFFFFFFFF);
    mpz_mul(&n, &n, &n);
    mpz_set_ui(&d, 0xFFFFFFFFFFFFFFFE);
    mpz_tdiv_qr(&q, &r, &n, &d);
    mpz_set_ui(&chk, 1);
    mpz_mul_2exp(&chk, &chk, 64);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&q, &chk));
    try std.testing.expectEqual(@as(u64, 1), mpz_get_ui(&r));
}

test "mpz division invariants on pseudo-random values" {
    var n: mpz_t = undefined;
    var d: mpz_t = undefined;
    var q: mpz_t = undefined;
    var r: mpz_t = undefined;
    var chk: mpz_t = undefined;
    var mag: mpz_t = undefined;
    mpz_init(&n);
    mpz_init(&d);
    mpz_init(&q);
    mpz_init(&r);
    mpz_init(&chk);
    mpz_init(&mag);
    defer mpz_clear(&n);
    defer mpz_clear(&d);
    defer mpz_clear(&q);
    defer mpz_clear(&r);
    defer mpz_clear(&chk);
    defer mpz_clear(&mag);

    var seed: u64 = 0x123456789ABCDEF0;
    var iter: usize = 0;
    while (iter < 100) : (iter += 1) {
        rndMagTest(&n, 2 + seed % 10, &seed);
        rndMagTest(&d, 1 + seed % 5, &seed);
        if (mpz_sgn(&d) == 0) mpz_set_ui(&d, 7);
        const nneg = (seed & 1) == 1;
        const dneg = ((seed >> 1) & 1) == 1;
        if (nneg) mpz_neg(&n, &n);
        if (dneg) mpz_neg(&d, &d);

        mpz_tdiv_qr(&q, &r, &n, &d);
        mpz_mul(&chk, &q, &d);
        mpz_add(&chk, &chk, &r);
        try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&chk, &n));
        if (mpz_sgn(&r) != 0) {
            try std.testing.expectEqual(@as(c_int, if (nneg) -1 else 1), mpz_sgn(&r));
            if (mpz_sgn(&q) != 0)
                try std.testing.expectEqual(@as(c_int, if (nneg != dneg) -1 else 1), mpz_sgn(&q));
        }
        mpz_abs(&mag, &r);
        mpz_abs(&chk, &d);
        try std.testing.expectEqual(@as(c_int, -1), mpz_cmp(&mag, &chk));

        mpz_fdiv_qr(&q, &r, &n, &d);
        mpz_mul(&chk, &q, &d);
        mpz_add(&chk, &chk, &r);
        try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&chk, &n));
        if (mpz_sgn(&r) != 0)
            try std.testing.expectEqual(@as(c_int, if (dneg) -1 else 1), mpz_sgn(&r));
        mpz_abs(&mag, &r);
        mpz_abs(&chk, &d);
        try std.testing.expectEqual(@as(c_int, -1), mpz_cmp(&mag, &chk));
    }
}

test "mpz division aliasing and divexact" {
    var n: mpz_t = undefined;
    var d: mpz_t = undefined;
    var r: mpz_t = undefined;
    var q: mpz_t = undefined;
    var a: mpz_t = undefined;
    var b: mpz_t = undefined;
    mpz_init(&n);
    mpz_init(&d);
    mpz_init(&r);
    mpz_init(&q);
    mpz_init(&a);
    mpz_init(&b);
    defer mpz_clear(&n);
    defer mpz_clear(&d);
    defer mpz_clear(&r);
    defer mpz_clear(&q);
    defer mpz_clear(&a);
    defer mpz_clear(&b);

    // q aliases n (timefns.c does mpz_fdiv_qr (mpz[0], mpz[1], mpz[0], d)).
    mpz_set_ui(&n, 1);
    mpz_mul_2exp(&n, &n, 192);
    mpz_sub_ui(&n, &n, 1); // 2^192 - 1
    mpz_set_ui(&d, 1);
    mpz_mul_2exp(&d, &d, 96);
    mpz_add_ui(&d, &d, 1); // 2^96 + 1
    mpz_tdiv_qr(&n, &r, &n, &d);
    mpz_set_ui(&q, 1);
    mpz_mul_2exp(&q, &q, 96);
    mpz_sub_ui(&q, &q, 1); // 2^96 - 1
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&n, &q));
    try std.testing.expectEqual(@as(c_int, 0), mpz_sgn(&r));

    // r aliases n (data.c pattern: tdiv_r into the dividend cell).
    mpz_set_ui(&n, 1);
    mpz_mul_2exp(&n, &n, 192);
    mpz_sub_ui(&n, &n, 1);
    mpz_tdiv_r(&n, &n, &d);
    try std.testing.expectEqual(@as(c_int, 0), mpz_sgn(&n));

    // divexact, both signs.
    mpz_set_ui(&a, 12345678901234567890);
    mpz_set_ui(&b, 987654321);
    mpz_mul(&n, &a, &b);
    mpz_divexact(&q, &n, &b);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&q, &a));
    mpz_neg(&n, &n);
    mpz_divexact(&q, &n, &b);
    mpz_neg(&a, &a);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&q, &a));
    mpz_neg(&b, &b);
    mpz_divexact(&q, &n, &b);
    mpz_neg(&a, &a); // a was -A; the quotient of two negatives is +A
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&q, &a));
}

test "mpz pow_ui and ui_pow_ui" {
    var b: mpz_t = undefined;
    var r: mpz_t = undefined;
    var chk: mpz_t = undefined;
    mpz_init(&b);
    mpz_init(&r);
    mpz_init(&chk);
    defer mpz_clear(&b);
    defer mpz_clear(&r);
    defer mpz_clear(&chk);

    mpz_set_ui(&b, 2);
    mpz_pow_ui(&r, &b, 10);
    try std.testing.expectEqual(@as(u64, 1024), mpz_get_ui(&r));
    mpz_set_si(&b, -3);
    mpz_pow_ui(&r, &b, 3);
    try std.testing.expectEqual(@as(i64, -27), mpz_get_si(&r));
    mpz_pow_ui(&r, &b, 0);
    try std.testing.expectEqual(@as(u64, 1), mpz_get_ui(&r));
    mpz_set_ui(&b, 0);
    mpz_pow_ui(&r, &b, 0);
    try std.testing.expectEqual(@as(u64, 1), mpz_get_ui(&r));
    mpz_pow_ui(&r, &b, 5);
    try std.testing.expectEqual(@as(u64, 0), mpz_get_ui(&r));

    // ROP aliasing BASE (data.c pattern).
    mpz_set_ui(&b, 3);
    mpz_pow_ui(&b, &b, 200);
    mpz_set_ui(&chk, 3);
    var i: usize = 1;
    while (i < 200) : (i += 1) mpz_mul_ui(&chk, &chk, 3);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&b, &chk));

    mpz_ui_pow_ui(&r, 10, 20);
    mpz_ui_pow_ui(&chk, 10, 10);
    mpz_mul(&chk, &chk, &chk); // 10^20
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&r, &chk));
}

test "mpz gcd" {
    var a: mpz_t = undefined;
    var b: mpz_t = undefined;
    var r: mpz_t = undefined;
    var chk: mpz_t = undefined;
    mpz_init(&a);
    mpz_init(&b);
    mpz_init(&r);
    mpz_init(&chk);
    defer mpz_clear(&a);
    defer mpz_clear(&b);
    defer mpz_clear(&r);
    defer mpz_clear(&chk);

    mpz_set_ui(&a, 123456789);
    mpz_set_ui(&b, 987654321);
    mpz_gcd(&r, &a, &b);
    try std.testing.expectEqual(@as(u64, 9), mpz_get_ui(&r));
    mpz_neg(&a, &a);
    mpz_gcd(&r, &a, &b);
    try std.testing.expectEqual(@as(u64, 9), mpz_get_ui(&r));
    mpz_set_ui(&a, 0);
    mpz_gcd(&r, &a, &b);
    try std.testing.expectEqual(@as(u64, 987654321), mpz_get_ui(&r));
    mpz_set_ui(&b, 0);
    mpz_gcd(&r, &a, &b);
    try std.testing.expectEqual(@as(u64, 0), mpz_get_ui(&r));

    // gcd(2^100, 2^50) = 2^50; gcd of two powers of two is the smaller.
    mpz_set_ui(&a, 1);
    mpz_mul_2exp(&a, &a, 100);
    mpz_set_ui(&b, 1);
    mpz_mul_2exp(&b, &b, 50);
    mpz_gcd(&r, &a, &b);
    mpz_set_ui(&chk, 1);
    mpz_mul_2exp(&chk, &chk, 50);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&r, &chk));

    // ROP aliases A (timefns.c gcd in place).
    mpz_set_ui(&a, 123456789);
    mpz_set_ui(&b, 987654321);
    mpz_gcd(&a, &a, &b);
    try std.testing.expectEqual(@as(u64, 9), mpz_get_ui(&a));
}

test "mpz addmul submul" {
    var a: mpz_t = undefined;
    var b: mpz_t = undefined;
    var r: mpz_t = undefined;
    var chk: mpz_t = undefined;
    mpz_init(&a);
    mpz_init(&b);
    mpz_init(&r);
    mpz_init(&chk);
    defer mpz_clear(&a);
    defer mpz_clear(&b);
    defer mpz_clear(&r);
    defer mpz_clear(&chk);

    mpz_set_si(&a, -100);
    mpz_set_si(&b, 7);
    mpz_set_ui(&r, 3);
    mpz_addmul(&r, &a, &b);
    try std.testing.expectEqual(@as(i64, -697), mpz_get_si(&r));
    mpz_submul(&r, &a, &b);
    try std.testing.expectEqual(@as(i64, 3), mpz_get_si(&r));

    mpz_set_ui(&a, 5);
    mpz_set_ui(&r, 1);
    mpz_addmul_ui(&r, &a, 7);
    try std.testing.expectEqual(@as(u64, 36), mpz_get_ui(&r));

    // Multi-limb with ROP aliasing A: r = 2^128; r += r * 3 = 4 * 2^128.
    mpz_set_ui(&r, 1);
    mpz_mul_2exp(&r, &r, 128);
    mpz_addmul_ui(&r, &r, 3);
    mpz_set_ui(&chk, 4);
    mpz_mul_2exp(&chk, &chk, 128);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&r, &chk));
}

test "mpz bitwise and ior xor com" {
    var a: mpz_t = undefined;
    var b: mpz_t = undefined;
    var r: mpz_t = undefined;
    var chk: mpz_t = undefined;
    mpz_init(&a);
    mpz_init(&b);
    mpz_init(&r);
    mpz_init(&chk);
    defer mpz_clear(&a);
    defer mpz_clear(&b);
    defer mpz_clear(&r);
    defer mpz_clear(&chk);

    mpz_set_si(&a, -1);
    mpz_set_si(&b, 12);
    mpz_and(&r, &a, &b);
    try std.testing.expectEqual(@as(i64, 12), mpz_get_si(&r));
    mpz_set_si(&a, -5);
    mpz_and(&r, &a, &b);
    try std.testing.expectEqual(@as(i64, 8), mpz_get_si(&r));
    mpz_set_si(&b, -12);
    mpz_and(&r, &a, &b);
    try std.testing.expectEqual(@as(i64, -16), mpz_get_si(&r));
    mpz_set_si(&b, 12);
    mpz_ior(&r, &a, &b);
    try std.testing.expectEqual(@as(i64, -1), mpz_get_si(&r));
    mpz_set_si(&b, -12);
    mpz_ior(&r, &a, &b);
    try std.testing.expectEqual(@as(i64, -1), mpz_get_si(&r));
    mpz_set_si(&b, 12);
    mpz_xor(&r, &a, &b);
    try std.testing.expectEqual(@as(i64, -9), mpz_get_si(&r));
    mpz_set_si(&b, -12);
    mpz_xor(&r, &a, &b);
    try std.testing.expectEqual(@as(i64, 15), mpz_get_si(&r));
    mpz_set_si(&a, -5);
    mpz_com(&r, &a);
    try std.testing.expectEqual(@as(i64, 4), mpz_get_si(&r));
    mpz_set_si(&a, 5);
    mpz_com(&r, &a);
    try std.testing.expectEqual(@as(i64, -6), mpz_get_si(&r));

    // Multi-limb: (2^128 - 1) & (2^64 + 1) = 2^64 + 1; mixed-sign case.
    mpz_set_ui(&a, 1);
    mpz_mul_2exp(&a, &a, 128);
    mpz_sub_ui(&a, &a, 1);
    mpz_set_ui(&b, 1);
    mpz_mul_2exp(&b, &b, 64);
    mpz_add_ui(&b, &b, 1);
    mpz_and(&r, &a, &b);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&r, &b));
    mpz_neg(&a, &a); // a = -(2^128 - 1)
    mpz_and(&r, &a, &b); // ~(2^128 - 2) & (2^64 + 1) = 1 (only bit 0)
    try std.testing.expectEqual(@as(u64, 1), mpz_get_ui(&r));
    mpz_ior(&r, &a, &a);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&r, &a));
    mpz_xor(&r, &a, &a);
    try std.testing.expectEqual(@as(c_int, 0), mpz_sgn(&r));
}

test "mpz popcount scan1 odd" {
    var a: mpz_t = undefined;
    mpz_init(&a);
    defer mpz_clear(&a);

    mpz_set_si(&a, -1);
    try std.testing.expectEqual(@as(c_ulong, std.math.maxInt(c_ulong)), mpz_popcount(&a));
    try std.testing.expectEqual(@as(c_ulong, 0), mpz_scan1(&a, 0));
    try std.testing.expectEqual(@as(c_int, 1), mpz_odd_p(&a));
    mpz_set_si(&a, -2);
    try std.testing.expectEqual(@as(c_ulong, 1), mpz_scan1(&a, 0));
    try std.testing.expectEqual(@as(c_int, 0), mpz_odd_p(&a));
    mpz_set_si(&a, -5);
    try std.testing.expectEqual(@as(c_ulong, 0), mpz_scan1(&a, 0));
    mpz_set_si(&a, -8);
    try std.testing.expectEqual(@as(c_ulong, 3), mpz_scan1(&a, 0));
    mpz_set_si(&a, 7);
    try std.testing.expectEqual(@as(c_ulong, 3), mpz_popcount(&a));
    try std.testing.expectEqual(@as(c_ulong, 0), mpz_scan1(&a, 0));
    try std.testing.expectEqual(@as(c_int, 1), mpz_odd_p(&a));
    mpz_set_si(&a, 0);
    try std.testing.expectEqual(@as(c_ulong, 0), mpz_popcount(&a));
    try std.testing.expectEqual(@as(c_ulong, std.math.maxInt(c_ulong)), mpz_scan1(&a, 0));
    try std.testing.expectEqual(@as(c_int, 0), mpz_odd_p(&a));
    mpz_set_si(&a, 100);
    try std.testing.expectEqual(@as(c_ulong, 3), mpz_popcount(&a));
    try std.testing.expectEqual(@as(c_ulong, 2), mpz_scan1(&a, 0));
    try std.testing.expectEqual(@as(c_ulong, 5), mpz_scan1(&a, 3));
}

test "mpz limbs api getlimbn roinit" {
    var z: mpz_t = undefined;
    mpz_init(&z);
    defer mpz_clear(&z);

    // Build 3 + 2^64 via mpz_limbs_write / mpz_limbs_finish.
    const limbs = mpz_limbs_write(&z, 2).?;
    limbs[0] = 3;
    limbs[1] = 1;
    mpz_limbs_finish(&z, 2);
    try std.testing.expectEqual(@as(u64, 3), mpz_getlimbn(&z, 0));
    try std.testing.expectEqual(@as(u64, 1), mpz_getlimbn(&z, 1));
    try std.testing.expectEqual(@as(u64, 0), mpz_getlimbn(&z, 2));
    var chk: mpz_t = undefined;
    mpz_init(&chk);
    defer mpz_clear(&chk);
    mpz_set_ui(&chk, 1);
    mpz_mul_2exp(&chk, &chk, 64);
    mpz_add_ui(&chk, &chk, 3);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&z, &chk));

    // Negative sign through limbs_finish.
    mpz_limbs_finish(&z, -2);
    try std.testing.expectEqual(@as(c_int, -1), mpz_sgn(&z));
    try std.testing.expectEqual(@as(u64, 3), mpz_getlimbn(&z, 0));
    mpz_limbs_finish(&z, 2);

    // mpz_roinit_n points at caller storage.
    const static_limbs = [_]u64{ 0xDEADBEEF, 0x0123456789ABCDEF };
    var ro: mpz_t = undefined;
    _ = mpz_roinit_n(&ro, &static_limbs, 2);
    try std.testing.expectEqual(@as(u64, 0xDEADBEEF), mpz_getlimbn(&ro, 0));
    try std.testing.expectEqual(@as(u64, 0x0123456789ABCDEF), mpz_getlimbn(&ro, 1));
    try std.testing.expectEqual(@as(isize, 2), mpz_size(&ro));
    mpz_clear(&ro); // alloc == 0: must not free the static array
    try std.testing.expectEqual(@as(u64, 0xDEADBEEF), static_limbs[0]);
}

test "mpz import export round trips" {
    var z: mpz_t = undefined;
    var r: mpz_t = undefined;
    mpz_init(&z);
    mpz_init(&r);
    defer mpz_clear(&z);
    defer mpz_clear(&r);

    // 2^64 + 1 exported as native u64 words, least-significant first.
    mpz_set_ui(&z, 1);
    mpz_mul_2exp(&z, &z, 64);
    mpz_add_ui(&z, &z, 1);
    var buf: [16]u8 = undefined;
    var n: usize = 0;
    _ = mpz_export(&buf, &n, -1, 8, 0, 0, &z);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(@as(u8, 1), buf[0]);
    try std.testing.expectEqual(@as(u8, 0), buf[7]);
    try std.testing.expectEqual(@as(u8, 1), buf[8]);
    mpz_import(&r, n, -1, 8, 0, 0, &buf);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&r, &z));

    // 32-bit words, most-significant first, big-endian bytes.
    mpz_set_ui(&z, 0x0102030405060708);
    _ = mpz_export(&buf, &n, 1, 4, 1, 0, &z);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(@as(u8, 0x01), buf[0]);
    try std.testing.expectEqual(@as(u8, 0x02), buf[1]);
    try std.testing.expectEqual(@as(u8, 0x08), buf[7]);
    mpz_import(&r, n, 1, 4, 1, 0, &buf);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&r, &z));

    // Direct import of two 32-bit little-endian words: 1 + 2 * 2^32.
    const bytes = [_]u8{ 1, 0, 0, 0, 2, 0, 0, 0 };
    mpz_import(&r, 2, -1, 4, -1, 0, &bytes);
    var chk2: mpz_t = undefined;
    mpz_init(&chk2);
    defer mpz_clear(&chk2);
    mpz_set_ui(&chk2, 1);
    mpz_mul_2exp(&chk2, &chk2, 32);
    mpz_mul_ui(&chk2, &chk2, 2);
    mpz_add_ui(&chk2, &chk2, 1);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&r, &chk2));

    // Zero exports zero words and leaves the count at 0.
    mpz_set_ui(&z, 0);
    n = 99;
    var scratch: [8]u8 = .{ 0xAA } ** 8;
    _ = mpz_export(&scratch, &n, -1, 8, 0, 0, &z);
    try std.testing.expectEqual(@as(usize, 0), n);
    try std.testing.expectEqual(@as(u8, 0xAA), scratch[0]);
}

test "mpz set_str get_str" {
    var z: mpz_t = undefined;
    var chk: mpz_t = undefined;
    mpz_init(&z);
    mpz_init(&chk);
    defer mpz_clear(&z);
    defer mpz_clear(&chk);

    // Round trip a signed value through every base 2..36 and base 62.
    mpz_set_si(&z, -1234567);
    var base: c_int = 2;
    while (base <= 36) : (base += 1) {
        var buf: [64:0]u8 = undefined;
        const s = mpz_get_str(&buf, base, &z);
        try std.testing.expect(s == &buf);
        try std.testing.expectEqual(@as(c_int, 0), mpz_set_str(&chk, @as([*:0]const u8, @ptrCast(s.?)), base));
        try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&z, &chk));
    }
    var buf62: [16:0]u8 = undefined;
    _ = mpz_get_str(&buf62, 62, &z);
    try std.testing.expectEqualStrings("-5BAN", std.mem.span(@as([*:0]const u8, @ptrCast(&buf62))));
    try std.testing.expectEqual(@as(c_int, 0), mpz_set_str(&chk, @as([*:0]const u8, @ptrCast(&buf62)), 62));
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&z, &chk));

    // Negative base prints upper-case digits; zero prints "0".
    _ = mpz_set_str(&z, "-255", 10);
    var buf: [16:0]u8 = undefined;
    _ = mpz_get_str(&buf, -16, &z);
    try std.testing.expectEqualStrings("-FF", std.mem.span(@as([*:0]const u8, @ptrCast(&buf))));
    mpz_set_ui(&z, 0);
    _ = mpz_get_str(&buf, 10, &z);
    try std.testing.expectEqualStrings("0", std.mem.span(@as([*:0]const u8, @ptrCast(&buf))));

    // NULL buffer allocates via the memory callbacks and parses back.
    _ = mpz_set_str(&z, "12345678901234567890", 10);
    const s2 = mpz_get_str(null, 10, &z).?;
    try std.testing.expectEqualStrings("12345678901234567890", std.mem.span(@as([*:0]const u8, @ptrCast(s2))));
    g_free(s2, @as(usize, @intCast(mpz_sizeinbase(&z, 10) + 2)));

    // Base 0 auto-detects 0x/0X, 0b/0B and leading-zero octal.
    _ = mpz_set_str(&chk, "16", 10);
    try std.testing.expectEqual(@as(c_int, 0), mpz_set_str(&z, "0x10", 0));
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&z, &chk));
    _ = mpz_set_str(&chk, "5", 10);
    try std.testing.expectEqual(@as(c_int, 0), mpz_set_str(&z, "0b101", 0));
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&z, &chk));
    _ = mpz_set_str(&chk, "8", 10);
    try std.testing.expectEqual(@as(c_int, 0), mpz_set_str(&z, "010", 0));
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&z, &chk));
    _ = mpz_set_str(&chk, "-16", 10);
    try std.testing.expectEqual(@as(c_int, 0), mpz_set_str(&z, "-0x10", 0));
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&z, &chk));

    // Whitespace is skipped (leading, trailing and between digits);
    // a bare 0x/0b prefix is zero; '+' and stray non-digits fail.
    _ = mpz_set_str(&chk, "-123", 10);
    try std.testing.expectEqual(@as(c_int, 0), mpz_set_str(&z, "  -123  ", 10));
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&z, &chk));
    _ = mpz_set_str(&chk, "1234", 10);
    try std.testing.expectEqual(@as(c_int, 0), mpz_set_str(&z, "12 34", 10));
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&z, &chk));
    mpz_set_ui(&chk, 0);
    try std.testing.expectEqual(@as(c_int, 0), mpz_set_str(&z, "0x", 0));
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&z, &chk));
    try std.testing.expectEqual(@as(c_int, 0), mpz_set_str(&z, "0b", 0));
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp(&z, &chk));

    // Failures leave ROP unchanged.
    mpz_set_ui(&z, 42);
    try std.testing.expectEqual(@as(c_int, -1), mpz_set_str(&z, "123abc", 10));
    try std.testing.expectEqual(@as(c_int, -1), mpz_set_str(&z, "+42", 10));
    try std.testing.expectEqual(@as(c_int, -1), mpz_set_str(&z, "09", 0));
    try std.testing.expectEqual(@as(c_int, -1), mpz_set_str(&z, "123.5", 10));
    try std.testing.expectEqual(@as(c_int, -1), mpz_set_str(&z, "", 10));
    try std.testing.expectEqual(@as(c_int, -1), mpz_set_str(&z, "-", 10));
    try std.testing.expectEqual(@as(c_int, -1), mpz_set_str(&z, "1", 1));
    try std.testing.expectEqual(@as(c_int, -1), mpz_set_str(&z, "1", 63));
    try std.testing.expectEqual(@as(c_int, -1), mpz_set_str(&z, "ff", -16));
    try std.testing.expectEqual(@as(c_int, 42), mpz_get_si(&z));
}

test "mpz get_d set_d cmp_d" {
    var z: mpz_t = undefined;
    mpz_init(&z);
    defer mpz_clear(&z);

    // get_d truncates toward zero and honors the sign.
    _ = mpz_set_str(&z, "9007199254740993", 10); // 2^53 + 1
    try std.testing.expectEqual(@as(f64, 9007199254740992.0), mpz_get_d(&z));
    _ = mpz_set_str(&z, "-9007199254740993", 10);
    try std.testing.expectEqual(@as(f64, -9007199254740992.0), mpz_get_d(&z));
    _ = mpz_set_str(&z, "9007199254740991", 10); // 2^53 - 1 is exact
    try std.testing.expectEqual(@as(f64, 9007199254740991.0), mpz_get_d(&z));
    _ = mpz_set_str(&z, "1267650600228229401496703205376", 10); // 2^100
    try std.testing.expectEqual(@exp2(@as(f64, 100.0)), mpz_get_d(&z));
    mpz_set_ui(&z, 1);
    try std.testing.expectEqual(@as(f64, 1.0), mpz_get_d(&z));
    mpz_set_si(&z, -7);
    try std.testing.expectEqual(@as(f64, -7.0), mpz_get_d(&z));
    mpz_set_ui(&z, 0);
    try std.testing.expectEqual(@as(f64, 0.0), mpz_get_d(&z));
    mpz_set_ui(&z, 1);
    var i: usize = 0;
    while (i < 400) : (i += 1) mpz_mul_ui(&z, &z, 10);
    try std.testing.expect(std.math.isInf(mpz_get_d(&z)));
    mpz_neg(&z, &z);
    try std.testing.expect(std.math.isInf(mpz_get_d(&z)));
    try std.testing.expect(mpz_get_d(&z) < 0);

    // set_d truncates toward zero; NaN/Inf map to zero.
    mpz_set_d(&z, 1.9);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp_si(&z, 1));
    mpz_set_d(&z, -1.9);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp_si(&z, -1));
    mpz_set_d(&z, 0.5);
    try std.testing.expectEqual(@as(c_int, 0), mpz_sgn(&z));
    mpz_set_d(&z, 123.0);
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp_si(&z, 123));
    mpz_set_d(&z, 4503599627370496.0); // 2^52
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp_si(&z, 4503599627370496));
    mpz_set_d(&z, 1e300);
    try std.testing.expectEqual(@as(f64, 1e300), mpz_get_d(&z));
    mpz_set_d(&z, -1e300);
    try std.testing.expectEqual(@as(f64, -1e300), mpz_get_d(&z));
    mpz_set_d(&z, std.math.nan(f64));
    try std.testing.expectEqual(@as(c_int, 0), mpz_sgn(&z));
    mpz_set_d(&z, std.math.inf(f64));
    try std.testing.expectEqual(@as(c_int, 0), mpz_sgn(&z));

    // cmp_d compares exactly, not against the truncated double.
    mpz_set_ui(&z, 2);
    try std.testing.expectEqual(@as(c_int, -1), mpz_cmp_d(&z, 2.9));
    mpz_set_ui(&z, 3);
    try std.testing.expectEqual(@as(c_int, 1), mpz_cmp_d(&z, 2.9));
    mpz_set_si(&z, -2);
    try std.testing.expectEqual(@as(c_int, 1), mpz_cmp_d(&z, -2.9));
    mpz_set_si(&z, -3);
    try std.testing.expectEqual(@as(c_int, -1), mpz_cmp_d(&z, -2.9));
    mpz_set_ui(&z, 0);
    try std.testing.expectEqual(@as(c_int, -1), mpz_cmp_d(&z, 2.5));
    try std.testing.expectEqual(@as(c_int, 1), mpz_cmp_d(&z, -1.0));
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp_d(&z, -0.0));
    try std.testing.expectEqual(@as(c_int, 0), mpz_cmp_d(&z, 0.0));
    try std.testing.expectEqual(@as(c_int, -1), mpz_cmp_d(&z, std.math.inf(f64)));
    try std.testing.expectEqual(@as(c_int, 1), mpz_cmp_d(&z, -std.math.inf(f64)));
    _ = mpz_set_str(&z, "9007199254740993", 10);
    try std.testing.expectEqual(@as(c_int, 1), mpz_cmp_d(&z, 9007199254740992.0));
    try std.testing.expectEqual(@as(c_int, -1), mpz_cmp_d(&z, 9007199254740994.0));
    mpz_set_si(&z, -5);
    try std.testing.expectEqual(@as(c_int, -1), mpz_cmp_d(&z, std.math.inf(f64)));
    try std.testing.expectEqual(@as(c_int, 1), mpz_cmp_d(&z, -std.math.inf(f64)));
}

test "mpz fits predicates" {
    var z: mpz_t = undefined;
    mpz_init(&z);
    defer mpz_clear(&z);

    mpz_set_ui(&z, 0);
    try std.testing.expectEqual(@as(c_int, 1), mpz_fits_sint_p(&z));
    try std.testing.expectEqual(@as(c_int, 1), mpz_fits_slong_p(&z));
    try std.testing.expectEqual(@as(c_int, 1), mpz_fits_ulong_p(&z));

    mpz_set_si(&z, std.math.maxInt(c_int));
    try std.testing.expectEqual(@as(c_int, 1), mpz_fits_sint_p(&z));
    mpz_set_si(&z, std.math.maxInt(c_int));
    mpz_add_ui(&z, &z, 1);
    try std.testing.expectEqual(@as(c_int, 0), mpz_fits_sint_p(&z));
    try std.testing.expectEqual(@as(c_int, 1), mpz_fits_slong_p(&z));
    mpz_set_si(&z, std.math.minInt(c_int));
    try std.testing.expectEqual(@as(c_int, 1), mpz_fits_sint_p(&z));
    mpz_set_si(&z, std.math.minInt(c_int));
    mpz_sub_ui(&z, &z, 1);
    try std.testing.expectEqual(@as(c_int, 0), mpz_fits_sint_p(&z));

    mpz_set_si(&z, std.math.maxInt(c_long));
    try std.testing.expectEqual(@as(c_int, 1), mpz_fits_slong_p(&z));
    try std.testing.expectEqual(@as(c_int, 1), mpz_fits_ulong_p(&z));
    mpz_set_si(&z, std.math.minInt(c_long));
    try std.testing.expectEqual(@as(c_int, 1), mpz_fits_slong_p(&z));
    try std.testing.expectEqual(@as(c_int, 0), mpz_fits_ulong_p(&z));
    mpz_set_si(&z, -1);
    try std.testing.expectEqual(@as(c_int, 1), mpz_fits_slong_p(&z));
    try std.testing.expectEqual(@as(c_int, 0), mpz_fits_ulong_p(&z));

    mpz_set_ui(&z, std.math.maxInt(c_ulong));
    try std.testing.expectEqual(@as(c_int, 1), mpz_fits_ulong_p(&z));
    mpz_add_ui(&z, &z, 1);
    try std.testing.expectEqual(@as(c_int, 0), mpz_fits_ulong_p(&z));
    try std.testing.expectEqual(@as(c_int, 0), mpz_fits_slong_p(&z));
}
