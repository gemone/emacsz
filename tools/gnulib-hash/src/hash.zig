// Native Zig implementations of SHA1 and MD5, replacing gnulib's
// lib/sha1.c and lib/md5.c. They operate on the gnulib ctx layouts
// (lib/sha1.h, lib/md5.h) so temacs's existing call sites -- sha1_*
// in src/fns.c, md5_buffer/md5_process_* in src/fns.c, src/comp.c and
// src/decompress.c -- work unchanged. Standard SHA1 (FIPS 180-1) and
// MD5 (RFC 1321); no libc call, no std import.
//
// The ctx layout matches lib/sha1.h exactly (extern struct):
//   uint32_t A,B,C,D,E; uint32_t total[2]; uint32_t buflen; uint32_t buffer[32];

const Sha1Ctx = extern struct {
    A: u32,
    B: u32,
    C: u32,
    D: u32,
    E: u32,
    total: [2]u32,
    buflen: u32,
    buffer: [32]u32,
};

// Read/write 32-bit big-endian words (SHA1 is big-endian on the wire).
fn rd32be(p: [*]const u8, i: usize) u32 {
    return (@as(u32, p[i]) << 24) | (@as(u32, p[i + 1]) << 16) |
        (@as(u32, p[i + 2]) << 8) | @as(u32, p[i + 3]);
}

fn wr32be(p: [*]u8, i: usize, v: u32) void {
    p[i] = @truncate(v >> 24);
    p[i + 1] = @truncate(v >> 16);
    p[i + 2] = @truncate(v >> 8);
    p[i + 3] = @truncate(v);
}

inline fn rol5(x: u32) u32 {
    return (x << 5) | (x >> 27);
}
inline fn rol30(x: u32) u32 {
    return (x << 30) | (x >> 2);
}
inline fn rol1(x: u32) u32 {
    return (x << 1) | (x >> 31);
}

export fn sha1_init_ctx(ctx: *Sha1Ctx) void {
    ctx.A = 0x67452301;
    ctx.B = 0xEFCDAB89;
    ctx.C = 0x98BADCFE;
    ctx.D = 0x10325476;
    ctx.E = 0xC3D2E1F0;
    ctx.total[0] = 0;
    ctx.total[1] = 0;
    ctx.buflen = 0;
}

// Process LEN bytes of BUFFER (LEN a multiple of 64), updating CTX.
export fn sha1_process_block(buffer: *const anyopaque, len: usize, ctx: *Sha1Ctx) void {
    const bp: [*]const u8 = @ptrCast(buffer);

    // Increment the 64-bit byte count by len (with carry).
    const lolen: u32 = @truncate(len);
    const old0 = ctx.total[0];
    ctx.total[0] +%= lolen;
    ctx.total[1] +%= @as(u32, @truncate(len >> 32)) +% @as(u32, @intFromBool(ctx.total[0] < old0));

    var off: usize = 0;
    while (off + 64 <= len) : (off += 64) {
        // Per FIPS 180-4 6.1.3, the working variables are loaded from the
        // current hash state and added back PER BLOCK (not carried across
        // blocks), so multi-block process_block calls stay correct.
        var a = ctx.A;
        var b = ctx.B;
        var c = ctx.C;
        var d = ctx.D;
        var e = ctx.E;
        var w: [80]u32 = undefined;
        var t: usize = 0;
        while (t < 16) : (t += 1) w[t] = rd32be(bp, off + t * 4);
        while (t < 80) : (t += 1)
            w[t] = rol1(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16]);

        t = 0;
        while (t < 80) : (t += 1) {
            const f: u32 = if (t < 20) (d ^ (b & (c ^ d)))
                else if (t < 40) (b ^ c ^ d)
                else if (t < 60) ((b & c) | (d & (b | c)))
                else (b ^ c ^ d);
            const k: u32 = if (t < 20) 0x5A827999
                else if (t < 40) 0x6ED9EBA1
                else if (t < 60) 0x8F1BBCDC
                else 0xCA62C1D6;
            const tmp = rol5(a) +% f +% e +% k +% w[t];
            e = d;
            d = c;
            c = rol30(b);
            b = a;
            a = tmp;
        }
        // SHA1 adds the working variables back into the hash state per block.
        ctx.A +%= a;
        ctx.B +%= b;
        ctx.C +%= c;
        ctx.D +%= d;
        ctx.E +%= e;
    }
}

// Update CTX for LEN bytes at BUFFER (LEN need not be a multiple of 64).
export fn sha1_process_bytes(buffer: *const anyopaque, len: usize, ctx: *Sha1Ctx) void {
    const src: [*]const u8 = @ptrCast(buffer);
    const bp: [*]u8 = @ptrCast(&ctx.buffer);
    var s: usize = 0;
    var remaining = len;

    // Fill the internal buffer to a block boundary first if partial.
    if (ctx.buflen != 0) {
        const add: usize = @min(@as(usize, 64 - ctx.buflen), remaining);
        var i: usize = 0;
        while (i < add) : (i += 1) bp[ctx.buflen + i] = src[s + i];
        ctx.buflen +%= @intCast(add);
        s += add;
        remaining -= add;
        if (ctx.buflen == 64) {
            sha1_process_block(&ctx.buffer, 64, ctx);
            ctx.buflen = 0;
        }
    }

    // Process whole blocks straight from the input.
    while (remaining >= 64) {
        sha1_process_block(&src[s], 64, ctx);
        s += 64;
        remaining -= 64;
    }

    // Buffer the trailing partial block.
    if (remaining > 0) {
        var i: usize = 0;
        while (i < remaining) : (i += 1) bp[i] = src[s + i];
        ctx.buflen = @intCast(remaining);
    }
}

// Write the 20-byte digest (A..E, big-endian) to the first 20 bytes of RESBUF.
export fn sha1_read_ctx(ctx: *const Sha1Ctx, resbuf: *anyopaque) *anyopaque {
    const r: [*]u8 = @ptrCast(resbuf);
    wr32be(r, 0, ctx.A);
    wr32be(r, 4, ctx.B);
    wr32be(r, 8, ctx.C);
    wr32be(r, 12, ctx.D);
    wr32be(r, 16, ctx.E);
    return resbuf;
}

// Pad, process the final block(s), and write the digest to RESBUF.
export fn sha1_finish_ctx(ctx: *Sha1Ctx, resbuf: *anyopaque) *anyopaque {
    const bp: [*]u8 = @ptrCast(&ctx.buffer);
    const bytes = ctx.buflen;
    // One block holds the padding if < 56 bytes buffered, else two.
    const size: usize = if (bytes < 56) 16 else 32; // in 32-bit words

    // Count the remaining buffered bytes.
    const old0 = ctx.total[0];
    ctx.total[0] +%= bytes;
    if (ctx.total[0] < old0) ctx.total[1] +%= 1;

    // Append the 64-bit message length in bits (big-endian).
    const bitcount: u64 = ((@as(u64, ctx.total[1]) << 32) | @as(u64, ctx.total[0])) << 3;
    const loff = (size - 2) * 4;
    var i: usize = 0;
    while (i < 8) : (i += 1) bp[loff + i] = @truncate(bitcount >> @intCast((7 - i) * 8));

    // 0x80 then zero-fill up to the length field.
    bp[bytes] = 0x80;
    i = bytes + 1;
    while (i < loff) : (i += 1) bp[i] = 0;

    sha1_process_block(&ctx.buffer, size * 4, ctx);
    return sha1_read_ctx(ctx, resbuf);
}

// One-shot: digest LEN bytes at BUFFER into the first 20 bytes of RESBLOCK.
export fn sha1_buffer(buffer: *const anyopaque, len: usize, resblock: *anyopaque) *anyopaque {
    var ctx: Sha1Ctx = undefined;
    sha1_init_ctx(&ctx);
    sha1_process_bytes(buffer, len, &ctx);
    return sha1_finish_ctx(&ctx, resblock);
}

// ---------------------------------------------------------------------------
// MD5 (RFC 1321).  The ctx layout matches lib/md5.h exactly (extern struct):
//   uint32_t A,B,C,D; uint32_t total[2]; uint32_t buflen; uint32_t buffer[32];
// lib/md5-stream.c stays in C (it only does FILE* reading) and calls the
// md5_* symbols below.

const Md5Ctx = extern struct {
    A: u32,
    B: u32,
    C: u32,
    D: u32,
    total: [2]u32,
    buflen: u32,
    buffer: [32]u32,
};

fn rd32le(p: [*]const u8, i: usize) u32 {
    return @as(u32, p[i]) | (@as(u32, p[i + 1]) << 8) |
        (@as(u32, p[i + 2]) << 16) | (@as(u32, p[i + 3]) << 24);
}

fn wr32le(p: [*]u8, i: usize, v: u32) void {
    p[i] = @truncate(v);
    p[i + 1] = @truncate(v >> 8);
    p[i + 2] = @truncate(v >> 16);
    p[i + 3] = @truncate(v >> 24);
}

inline fn rotl32(x: u32, s: u5) u32 {
    const r: u5 = @intCast(32 - @as(u31, s));
    return (x << s) | (x >> r);
}

// Message-word index, rotation, and constant (T[i] = floor(2^32*|sin i|))
// for each of the 64 steps (RFC 1321 section 3.4).
const md5_k = [64]u4{
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
    1,  6, 11,  0,  5, 10, 15,  4,  9, 14,  3,  8, 13,  2,  7, 12,
    5,  8, 11, 14,  1,  4,  7, 10, 13,  0,  3,  6,  9, 12, 15,  2,
    0,  7, 14,  5, 12,  3, 10,  1,  8, 15,  6, 13,  4, 11,  2,  9,
};
const md5_s = [64]u5{
    7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
    5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
    4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
    6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,
};
const md5_t = [64]u32{
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
};

// RFC 1321 3.4 round functions.
inline fn md5F(b: u32, c: u32, d: u32) u32 {
    return d ^ (b & (c ^ d));
}
inline fn md5G(b: u32, c: u32, d: u32) u32 {
    return md5F(d, b, c);
}
inline fn md5H(b: u32, c: u32, d: u32) u32 {
    return b ^ c ^ d;
}
inline fn md5I(b: u32, c: u32, d: u32) u32 {
    return c ^ (b | ~d);
}

export fn md5_init_ctx(ctx: *Md5Ctx) void {
    ctx.A = 0x67452301;
    ctx.B = 0xefcdab89;
    ctx.C = 0x98badcfe;
    ctx.D = 0x10325476;
    ctx.total[0] = 0;
    ctx.total[1] = 0;
    ctx.buflen = 0;
}

// Process LEN bytes of BUFFER (LEN a multiple of 64), updating CTX.
export fn md5_process_block(buffer: *const anyopaque, len: usize, ctx: *Md5Ctx) void {
    const bp: [*]const u8 = @ptrCast(buffer);

    // Increment the 64-bit byte count by len (with carry), exactly as the
    // C source does: total[1] += (len >> 32) + (low word overflowed).
    const old0 = ctx.total[0];
    const lolen: u32 = @truncate(len);
    ctx.total[0] +%= lolen;
    ctx.total[1] +%= @as(u32, @truncate(len >> 32)) +% @as(u32, @intFromBool(ctx.total[0] < old0));

    var off: usize = 0;
    while (off + 64 <= len) : (off += 64) {
        var x: [16]u32 = undefined;
        for (0..16) |i| x[i] = rd32le(bp, off + i * 4);

        var a = ctx.A;
        var b = ctx.B;
        var c = ctx.C;
        var d = ctx.D;

        var step: usize = 0;
        while (step < 64) : (step += 1) {
            const f: u32 = if (step < 16) md5F(b, c, d)
                else if (step < 32) md5G(b, c, d)
                else if (step < 48) md5H(b, c, d)
                else md5I(b, c, d);
            const tmp = a +% f +% x[md5_k[step]] +% md5_t[step];
            a = d;
            d = c;
            c = b;
            b = b +% rotl32(tmp, md5_s[step]);
        }

        ctx.A +%= a;
        ctx.B +%= b;
        ctx.C +%= c;
        ctx.D +%= d;
    }
}

// Update CTX for LEN bytes at BUFFER (LEN need not be a multiple of 64).
// Mirrors the C source's 128-byte internal buffer and its flush rules.
export fn md5_process_bytes(buffer: *const anyopaque, len: usize, ctx: *Md5Ctx) void {
    const src: [*]const u8 = @ptrCast(buffer);
    const bp: [*]u8 = @ptrCast(&ctx.buffer);
    var s: usize = 0;
    var remaining = len;

    // Top up the internal buffer to a 128-byte ceiling first.
    if (ctx.buflen != 0) {
        const left_over: usize = ctx.buflen;
        const add: usize = @min(@as(usize, 128 - left_over), remaining);
        var i: usize = 0;
        while (i < add) : (i += 1) bp[left_over + i] = src[s + i];
        ctx.buflen +%= @intCast(add);
        s += add;
        remaining -= add;
        if (ctx.buflen > 64) {
            md5_process_block(&ctx.buffer, ctx.buflen & ~@as(u32, 63), ctx);
            ctx.buflen &= 63;
            const tail_start = (left_over + add) & ~@as(usize, 63);
            var j: usize = 0;
            while (j < ctx.buflen) : (j += 1) bp[j] = bp[tail_start + j];
        }
    }

    // Process whole blocks straight from the input.
    if (remaining >= 64) {
        md5_process_block(&src[s], remaining & ~@as(usize, 63), ctx);
        s += remaining & ~@as(usize, 63);
        remaining &= 63;
    }

    // Buffer the trailing partial block.
    if (remaining > 0) {
        const left_over: usize = ctx.buflen;
        var i: usize = 0;
        while (i < remaining) : (i += 1) bp[left_over + i] = src[s + i];
        const new_left = left_over + remaining;
        if (new_left >= 64) {
            md5_process_block(&ctx.buffer, 64, ctx);
            const tail = new_left - 64;
            var j: usize = 0;
            while (j < tail) : (j += 1) bp[j] = bp[64 + j];
            ctx.buflen = @intCast(tail);
        } else {
            ctx.buflen = @intCast(new_left);
        }
    }
}

// Write the 16-byte digest (A..D, little-endian) to the first 16 bytes of RESBUF.
export fn md5_read_ctx(ctx: *const Md5Ctx, resbuf: *anyopaque) *anyopaque {
    const r: [*]u8 = @ptrCast(resbuf);
    wr32le(r, 0, ctx.A);
    wr32le(r, 4, ctx.B);
    wr32le(r, 8, ctx.C);
    wr32le(r, 12, ctx.D);
    return resbuf;
}

// Pad, process the final block(s), and write the digest to RESBUF.
export fn md5_finish_ctx(ctx: *Md5Ctx, resbuf: *anyopaque) *anyopaque {
    const bp: [*]u8 = @ptrCast(&ctx.buffer);
    const bytes = ctx.buflen;
    // One block holds the padding if < 56 bytes buffered, else two.
    const size: usize = if (bytes < 56) 16 else 32; // in 32-bit words

    // Count the remaining buffered bytes.
    const old0 = ctx.total[0];
    ctx.total[0] +%= bytes;
    if (ctx.total[0] < old0) ctx.total[1] +%= 1;

    // Append the 64-bit message length in bits, little-endian.
    const bitcount: u64 = ((@as(u64, ctx.total[1]) << 32) | @as(u64, ctx.total[0])) << 3;
    const loff = (size - 2) * 4;
    var i: usize = 0;
    while (i < 8) : (i += 1) bp[loff + i] = @truncate(bitcount >> @intCast(i * 8));

    // 0x80 then zero-fill up to the length field.
    bp[bytes] = 0x80;
    i = bytes + 1;
    while (i < loff) : (i += 1) bp[i] = 0;

    md5_process_block(&ctx.buffer, size * 4, ctx);
    return md5_read_ctx(ctx, resbuf);
}

// One-shot: digest LEN bytes at BUFFER into the first 16 bytes of RESBLOCK.
export fn md5_buffer(buffer: *const anyopaque, len: usize, resblock: *anyopaque) *anyopaque {
    var ctx: Md5Ctx = undefined;
    md5_init_ctx(&ctx);
    md5_process_bytes(buffer, len, &ctx);
    return md5_finish_ctx(&ctx, resblock);
}
