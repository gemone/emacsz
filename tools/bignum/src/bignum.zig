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
// and bitwise ops. The remaining surface (import/export, limbs API,
// strings and doubles) lands in follow-up slices.

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
pub export fn mpz_tdiv_ui(n: *const mpz_t, d: u64) u64 {
    if (d == 0) @panic("mpz division by zero");
    return singleLimbDivMod(n, d, null);
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
pub export fn mpz_fdiv_q_ui(q: *mpz_t, n: *const mpz_t, d: u64) u64 {
    if (d == 0) @panic("mpz division by zero");
    const an = limbCount(n);
    if (an == 0) {
        ensureCapacity(q, 1);
        q._mp_size = 0;
        return 0;
    }
    const qbuf = allocLimbs(an + 1) orelse oom();
    const rem = singleLimbDivMod(n, d, qbuf);
    var used = an;
    while (used > 0 and qbuf[used - 1] == 0) used -= 1;
    const neg = signOf(n) < 0;
    if (neg and rem != 0) {
        commit(q, qbuf, an + 1, used, -1);
        mpz_sub_ui(q, q, 1); // floor rounds the negative quotient down
        return d - rem;
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

pub export fn mpz_init_set_ui(z: *mpz_t, u: u64) void {
    mpz_init(z);
    mpz_set_ui(z, u);
}

// ROP += |A| * |B| with full sign arithmetic. Any operand may alias ROP.
pub export fn mpz_addmul(rop: *mpz_t, a: *const mpz_t, b: *const mpz_t) void {
    var t: mpz_t = undefined;
    mpz_init(&t);
    defer mpz_clear(&t);
    mpz_mul(&t, a, b);
    mpz_add(rop, rop, &t);
}

pub export fn mpz_addmul_ui(rop: *mpz_t, a: *const mpz_t, u: u64) void {
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
