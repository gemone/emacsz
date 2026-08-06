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
// This is the foundation slice: mpz lifecycle, conversions, comparison,
// add/sub/mul and two-power shifts, plus size queries. The remaining
// surface (division, pow/gcd, import/export, limbs API, strings) lands
// in follow-up slices.

const std = @import("std");

pub const mp_limb_t = u64;
pub const mp_size_t = isize;
pub const mp_bitcnt_t = u64;
pub const GMP_NUMB_BITS: usize = 64;

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
    const an = limbCount(a);
    const bn = limbCount(b);
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

pub export fn mpz_set_ui(z: *mpz_t, u: u64) void {
    ensureCapacity(z, 1);
    if (u == 0) {
        z._mp_size = 0;
        return;
    }
    z._mp_d.?[0] = u;
    z._mp_size = 1;
}

pub export fn mpz_set_si(z: *mpz_t, i: i64) void {
    if (i < 0) {
        mpz_set_ui(z, @as(u64, @bitCast(-i)));
        z._mp_size = -z._mp_size;
    } else {
        mpz_set_ui(z, @intCast(i));
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
pub export fn mpz_sizeinbase(z: *const mpz_t, base: c_int) c_ulong {
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

pub export fn mpz_cmp_ui(a: *const mpz_t, u: u64) c_int {
    var b: mpz_t = undefined;
    mpz_init(&b);
    defer mpz_clear(&b);
    mpz_set_ui(&b, u);
    return mpz_cmp(a, &b);
}

pub export fn mpz_cmp_si(a: *const mpz_t, i: i64) c_int {
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

pub export fn mpz_add_ui(z: *mpz_t, a: *const mpz_t, u: u64) void {
    var b: mpz_t = undefined;
    mpz_init(&b);
    defer mpz_clear(&b);
    mpz_set_ui(&b, u);
    mpz_add(z, a, &b);
}

pub export fn mpz_sub_ui(z: *mpz_t, a: *const mpz_t, u: u64) void {
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

pub export fn mpz_mul_ui(z: *mpz_t, a: *const mpz_t, u: u64) void {
    const an = limbCount(a);
    if (an == 0 or u == 0) {
        ensureCapacity(z, 1);
        z._mp_size = 0;
        return;
    }
    const res = allocLimbs(an + 1) orelse oom();
    var carry: u64 = 0;
    var i: usize = 0;
    while (i < an) : (i += 1) {
        const r = mulAddLimbs(a._mp_d.?[i], u, 0, carry);
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
    try std.testing.expectEqual(@as(c_ulong, 1), mpz_sizeinbase(&z, 10));
    mpz_set_ui(&z, 255);
    try std.testing.expectEqual(@as(c_ulong, 8), mpz_sizeinbase(&z, 2));
    try std.testing.expectEqual(@as(c_ulong, 2), mpz_sizeinbase(&z, 16));
    try std.testing.expectEqual(@as(c_ulong, 3), mpz_sizeinbase(&z, 10));
    mpz_set_ui(&z, 1);
    mpz_mul_2exp(&z, &z, 100); // 2^100
    try std.testing.expectEqual(@as(c_ulong, 101), mpz_sizeinbase(&z, 2));
    try std.testing.expectEqual(@as(c_ulong, 31), mpz_sizeinbase(&z, 10));
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
