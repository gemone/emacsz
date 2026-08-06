// Native Zig implementations of SHA1, SHA2 (SHA-224/256/384/512) and MD5,
// replacing gnulib's lib/sha1.c, lib/sha256.c, lib/sha512.c and
// lib/md5.c. They operate on the gnulib ctx layouts (lib/sha1.h,
// lib/sha256.h, lib/sha512.h, lib/md5.h) so temacs's existing call sites
// -- sha1_*/sha256_*/sha512_*/md5_buffer in src/fns.c (secure-hash),
// md5_buffer/md5_process_* in src/comp.c and src/decompress.c -- work
// unchanged. Standard SHA1 (FIPS 180-1), SHA2 (FIPS 180-2/4) and MD5
// (RFC 1321); no libc call, no std import.
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

fn rd64le(p: [*]const u8, i: usize) u64 {
    return @as(u64, p[i]) | (@as(u64, p[i + 1]) << 8) |
        (@as(u64, p[i + 2]) << 16) | (@as(u64, p[i + 3]) << 24) |
        (@as(u64, p[i + 4]) << 32) | (@as(u64, p[i + 5]) << 40) |
        (@as(u64, p[i + 6]) << 48) | (@as(u64, p[i + 7]) << 56);
}

fn wr64le(p: [*]u8, i: usize, v: u64) void {
    p[i] = @truncate(v);
    p[i + 1] = @truncate(v >> 8);
    p[i + 2] = @truncate(v >> 16);
    p[i + 3] = @truncate(v >> 24);
    p[i + 4] = @truncate(v >> 32);
    p[i + 5] = @truncate(v >> 40);
    p[i + 6] = @truncate(v >> 48);
    p[i + 7] = @truncate(v >> 56);
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

// ---------------------------------------------------------------------------
// SHA-256 / SHA-224 (FIPS 180-2/4).  The ctx layout matches lib/sha256.h
// exactly (extern struct; buflen is C size_t):
//   uint32_t state[8]; uint32_t total[2]; size_t buflen; uint32_t buffer[32];

const Sha256Ctx = extern struct {
    state: [8]u32,
    total: [2]u32,
    buflen: usize,
    buffer: [32]u32,
};

fn rd64be(p: [*]const u8, i: usize) u64 {
    return (@as(u64, p[i]) << 56) | (@as(u64, p[i + 1]) << 48) |
        (@as(u64, p[i + 2]) << 40) | (@as(u64, p[i + 3]) << 32) |
        (@as(u64, p[i + 4]) << 24) | (@as(u64, p[i + 5]) << 16) |
        (@as(u64, p[i + 6]) << 8) | @as(u64, p[i + 7]);
}

fn wr64be(p: [*]u8, i: usize, v: u64) void {
    p[i] = @truncate(v >> 56);
    p[i + 1] = @truncate(v >> 48);
    p[i + 2] = @truncate(v >> 40);
    p[i + 3] = @truncate(v >> 32);
    p[i + 4] = @truncate(v >> 24);
    p[i + 5] = @truncate(v >> 16);
    p[i + 6] = @truncate(v >> 8);
    p[i + 7] = @truncate(v);
}

inline fn ror32(x: u32, n: u5) u32 {
    const r: u5 = @intCast(32 - @as(u31, n));
    return (x >> n) | (x << r);
}

inline fn ror64(x: u64, n: u6) u64 {
    const r: u6 = @intCast(64 - @as(u63, n));
    return (x >> n) | (x << r);
}

// SHA-256 round constants (FIPS 180-4 section 4.2.2).
const sha256_k = [64]u32{
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

fn sha256Init(ctx: *Sha256Ctx, h224: bool) void {
    ctx.state = if (h224) .{
        0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939,
        0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4,
    } else .{
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    };
    ctx.total[0] = 0;
    ctx.total[1] = 0;
    ctx.buflen = 0;
}

export fn sha256_init_ctx(ctx: *Sha256Ctx) void {
    sha256Init(ctx, false);
}

export fn sha224_init_ctx(ctx: *Sha256Ctx) void {
    sha256Init(ctx, true);
}

// Process LEN bytes of BUFFER (LEN a multiple of 64), updating CTX.
export fn sha256_process_block(buffer: *const anyopaque, len: usize, ctx: *Sha256Ctx) void {
    const bp: [*]const u8 = @ptrCast(buffer);

    // Increment the 64-bit byte count by len (with carry), as the C source.
    const old0 = ctx.total[0];
    const lolen: u32 = @truncate(len);
    ctx.total[0] +%= lolen;
    ctx.total[1] +%= @as(u32, @truncate(len >> 32)) +% @as(u32, @intFromBool(ctx.total[0] < old0));

    var off: usize = 0;
    while (off + 64 <= len) : (off += 64) {
        var w: [64]u32 = undefined;
        for (0..16) |i| w[i] = rd32be(bp, off + i * 4);
        var t: usize = 16;
        while (t < 64) : (t += 1) {
            const s0 = ror32(w[t - 15], 7) ^ ror32(w[t - 15], 18) ^ (w[t - 15] >> 3);
            const s1 = ror32(w[t - 2], 17) ^ ror32(w[t - 2], 19) ^ (w[t - 2] >> 10);
            w[t] = w[t - 16] +% s0 +% w[t - 7] +% s1;
        }

        var a = ctx.state[0];
        var b = ctx.state[1];
        var c = ctx.state[2];
        var d = ctx.state[3];
        var e = ctx.state[4];
        var f = ctx.state[5];
        var g = ctx.state[6];
        var h = ctx.state[7];

        t = 0;
        while (t < 64) : (t += 1) {
            const big_s1 = ror32(e, 6) ^ ror32(e, 11) ^ ror32(e, 25);
            const ch = (e & f) ^ (~e & g);
            const t1 = h +% big_s1 +% ch +% sha256_k[t] +% w[t];
            const big_s0 = ror32(a, 2) ^ ror32(a, 13) ^ ror32(a, 22);
            const maj = (a & b) ^ (a & c) ^ (b & c);
            const t2 = big_s0 +% maj;
            h = g;
            g = f;
            f = e;
            e = d +% t1;
            d = c;
            c = b;
            b = a;
            a = t1 +% t2;
        }

        ctx.state[0] +%= a;
        ctx.state[1] +%= b;
        ctx.state[2] +%= c;
        ctx.state[3] +%= d;
        ctx.state[4] +%= e;
        ctx.state[5] +%= f;
        ctx.state[6] +%= g;
        ctx.state[7] +%= h;
    }
}

// Update CTX for LEN bytes at BUFFER (LEN need not be a multiple of 64).
// Same 128-byte internal-buffer scheme as md5_process_bytes.
export fn sha256_process_bytes(buffer: *const anyopaque, len: usize, ctx: *Sha256Ctx) void {
    const src: [*]const u8 = @ptrCast(buffer);
    const bp: [*]u8 = @ptrCast(&ctx.buffer);
    var s: usize = 0;
    var remaining = len;

    if (ctx.buflen != 0) {
        const left_over: usize = ctx.buflen;
        const add: usize = @min(@as(usize, 128 - left_over), remaining);
        var i: usize = 0;
        while (i < add) : (i += 1) bp[left_over + i] = src[s + i];
        ctx.buflen +%= add;
        s += add;
        remaining -= add;
        if (ctx.buflen > 64) {
            sha256_process_block(&ctx.buffer, ctx.buflen & ~@as(usize, 63), ctx);
            ctx.buflen &= 63;
            const tail_start = (left_over + add) & ~@as(usize, 63);
            var j: usize = 0;
            while (j < ctx.buflen) : (j += 1) bp[j] = bp[tail_start + j];
        }
    }

    if (remaining >= 64) {
        sha256_process_block(&src[s], remaining & ~@as(usize, 63), ctx);
        s += remaining & ~@as(usize, 63);
        remaining &= 63;
    }

    if (remaining > 0) {
        const left_over: usize = ctx.buflen;
        var i: usize = 0;
        while (i < remaining) : (i += 1) bp[left_over + i] = src[s + i];
        const new_left = left_over + remaining;
        if (new_left >= 64) {
            sha256_process_block(&ctx.buffer, 64, ctx);
            const tail = new_left - 64;
            var j: usize = 0;
            while (j < tail) : (j += 1) bp[j] = bp[64 + j];
            ctx.buflen = tail;
        } else {
            ctx.buflen = new_left;
        }
    }
}

fn sha256WriteDigest(ctx: *const Sha256Ctx, resbuf: *anyopaque, words: usize) *anyopaque {
    const r: [*]u8 = @ptrCast(resbuf);
    for (0..words) |i| wr32be(r, i * 4, ctx.state[i]);
    return resbuf;
}

export fn sha256_read_ctx(ctx: *const Sha256Ctx, resbuf: *anyopaque) *anyopaque {
    return sha256WriteDigest(ctx, resbuf, 8);
}

export fn sha224_read_ctx(ctx: *const Sha256Ctx, resbuf: *anyopaque) *anyopaque {
    return sha256WriteDigest(ctx, resbuf, 7);
}

fn sha256Conclude(ctx: *Sha256Ctx) void {
    const bp: [*]u8 = @ptrCast(&ctx.buffer);
    const bytes = ctx.buflen;
    // One block holds the padding if < 56 bytes buffered, else two.
    const size: usize = if (bytes < 56) 16 else 32; // in 32-bit words

    const old0 = ctx.total[0];
    ctx.total[0] +%= @intCast(bytes);
    if (ctx.total[0] < old0) ctx.total[1] +%= 1;

    // Append the 64-bit message length in bits, big-endian.
    const bitcount: u64 = ((@as(u64, ctx.total[1]) << 32) | @as(u64, ctx.total[0])) << 3;
    const loff = (size - 2) * 4;
    var i: usize = 0;
    while (i < 8) : (i += 1) bp[loff + i] = @truncate(bitcount >> @intCast((7 - i) * 8));

    bp[bytes] = 0x80;
    i = bytes + 1;
    while (i < loff) : (i += 1) bp[i] = 0;

    sha256_process_block(&ctx.buffer, size * 4, ctx);
}

export fn sha256_finish_ctx(ctx: *Sha256Ctx, resbuf: *anyopaque) *anyopaque {
    sha256Conclude(ctx);
    return sha256_read_ctx(ctx, resbuf);
}

export fn sha224_finish_ctx(ctx: *Sha256Ctx, resbuf: *anyopaque) *anyopaque {
    sha256Conclude(ctx);
    return sha224_read_ctx(ctx, resbuf);
}

fn sha256BufferOneShot(h224: bool, buffer: *const anyopaque, len: usize, resblock: *anyopaque) *anyopaque {
    var ctx: Sha256Ctx = undefined;
    sha256Init(&ctx, h224);
    sha256_process_bytes(buffer, len, &ctx);
    sha256Conclude(&ctx);
    return sha256WriteDigest(&ctx, resblock, if (h224) 7 else 8);
}

export fn sha256_buffer(buffer: *const anyopaque, len: usize, resblock: *anyopaque) *anyopaque {
    return sha256BufferOneShot(false, buffer, len, resblock);
}

export fn sha224_buffer(buffer: *const anyopaque, len: usize, resblock: *anyopaque) *anyopaque {
    return sha256BufferOneShot(true, buffer, len, resblock);
}

// ---------------------------------------------------------------------------
// SHA-512 / SHA-384 (FIPS 180-2/4).  The ctx layout matches lib/sha512.h
// exactly (extern struct; buflen is C size_t):
//   uint64_t state[8]; uint64_t total[2]; size_t buflen; uint64_t buffer[32];

const Sha512Ctx = extern struct {
    state: [8]u64,
    total: [2]u64,
    buflen: usize,
    buffer: [32]u64,
};

// SHA-512 round constants (FIPS 180-4 section 4.2.3).
const sha512_k = [80]u64{
    0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
    0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
    0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
    0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694,
    0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
    0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
    0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4,
    0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70,
    0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
    0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
    0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30,
    0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
    0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
    0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
    0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
    0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b,
    0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178,
    0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b,
    0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c,
    0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
};

fn sha512Init(ctx: *Sha512Ctx, h384: bool) void {
    ctx.state = if (h384) .{
        0xcbbb9d5dc1059ed8, 0x629a292a367cd507, 0x9159015a3070dd17, 0x152fecd8f70e5939,
        0x67332667ffc00b31, 0x8eb44a8768581511, 0xdb0c2e0d64f98fa7, 0x47b5481dbefa4fa4,
    } else .{
        0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
        0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
    };
    ctx.total[0] = 0;
    ctx.total[1] = 0;
    ctx.buflen = 0;
}

export fn sha512_init_ctx(ctx: *Sha512Ctx) void {
    sha512Init(ctx, false);
}

export fn sha384_init_ctx(ctx: *Sha512Ctx) void {
    sha512Init(ctx, true);
}

// Process LEN bytes of BUFFER (LEN a multiple of 128), updating CTX.
export fn sha512_process_block(buffer: *const anyopaque, len: usize, ctx: *Sha512Ctx) void {
    const bp: [*]const u8 = @ptrCast(buffer);

    // Increment the 128-bit byte count by len (with carry), as the C source.
    const old0 = ctx.total[0];
    const lolen: u64 = @intCast(len);
    ctx.total[0] +%= lolen;
    ctx.total[1] +%= @as(u64, @intFromBool(ctx.total[0] < old0));

    var off: usize = 0;
    while (off + 128 <= len) : (off += 128) {
        var w: [80]u64 = undefined;
        for (0..16) |i| w[i] = rd64be(bp, off + i * 8);
        var t: usize = 16;
        while (t < 80) : (t += 1) {
            const s0 = ror64(w[t - 15], 1) ^ ror64(w[t - 15], 8) ^ (w[t - 15] >> 7);
            const s1 = ror64(w[t - 2], 19) ^ ror64(w[t - 2], 61) ^ (w[t - 2] >> 6);
            w[t] = w[t - 16] +% s0 +% w[t - 7] +% s1;
        }

        var a = ctx.state[0];
        var b = ctx.state[1];
        var c = ctx.state[2];
        var d = ctx.state[3];
        var e = ctx.state[4];
        var f = ctx.state[5];
        var g = ctx.state[6];
        var h = ctx.state[7];

        t = 0;
        while (t < 80) : (t += 1) {
            const big_s1 = ror64(e, 14) ^ ror64(e, 18) ^ ror64(e, 41);
            const ch = (e & f) ^ (~e & g);
            const t1 = h +% big_s1 +% ch +% sha512_k[t] +% w[t];
            const big_s0 = ror64(a, 28) ^ ror64(a, 34) ^ ror64(a, 39);
            const maj = (a & b) ^ (a & c) ^ (b & c);
            const t2 = big_s0 +% maj;
            h = g;
            g = f;
            f = e;
            e = d +% t1;
            d = c;
            c = b;
            b = a;
            a = t1 +% t2;
        }

        ctx.state[0] +%= a;
        ctx.state[1] +%= b;
        ctx.state[2] +%= c;
        ctx.state[3] +%= d;
        ctx.state[4] +%= e;
        ctx.state[5] +%= f;
        ctx.state[6] +%= g;
        ctx.state[7] +%= h;
    }
}

// Update CTX for LEN bytes at BUFFER (LEN need not be a multiple of 128).
// Same scheme as the others, with a 256-byte internal buffer / 128-byte
// blocks per lib/sha512.c.
export fn sha512_process_bytes(buffer: *const anyopaque, len: usize, ctx: *Sha512Ctx) void {
    const src: [*]const u8 = @ptrCast(buffer);
    const bp: [*]u8 = @ptrCast(&ctx.buffer);
    var s: usize = 0;
    var remaining = len;

    if (ctx.buflen != 0) {
        const left_over: usize = ctx.buflen;
        const add: usize = @min(@as(usize, 256 - left_over), remaining);
        var i: usize = 0;
        while (i < add) : (i += 1) bp[left_over + i] = src[s + i];
        ctx.buflen +%= add;
        s += add;
        remaining -= add;
        if (ctx.buflen > 128) {
            sha512_process_block(&ctx.buffer, ctx.buflen & ~@as(usize, 127), ctx);
            ctx.buflen &= 127;
            const tail_start = (left_over + add) & ~@as(usize, 127);
            var j: usize = 0;
            while (j < ctx.buflen) : (j += 1) bp[j] = bp[tail_start + j];
        }
    }

    if (remaining >= 128) {
        sha512_process_block(&src[s], remaining & ~@as(usize, 127), ctx);
        s += remaining & ~@as(usize, 127);
        remaining &= 127;
    }

    if (remaining > 0) {
        const left_over: usize = ctx.buflen;
        var i: usize = 0;
        while (i < remaining) : (i += 1) bp[left_over + i] = src[s + i];
        const new_left = left_over + remaining;
        if (new_left >= 128) {
            sha512_process_block(&ctx.buffer, 128, ctx);
            const tail = new_left - 128;
            var j: usize = 0;
            while (j < tail) : (j += 1) bp[j] = bp[128 + j];
            ctx.buflen = tail;
        } else {
            ctx.buflen = new_left;
        }
    }
}

fn sha512WriteDigest(ctx: *const Sha512Ctx, resbuf: *anyopaque, words: usize) *anyopaque {
    const r: [*]u8 = @ptrCast(resbuf);
    for (0..words) |i| wr64be(r, i * 8, ctx.state[i]);
    return resbuf;
}

export fn sha512_read_ctx(ctx: *const Sha512Ctx, resbuf: *anyopaque) *anyopaque {
    return sha512WriteDigest(ctx, resbuf, 8);
}

export fn sha384_read_ctx(ctx: *const Sha512Ctx, resbuf: *anyopaque) *anyopaque {
    return sha512WriteDigest(ctx, resbuf, 6);
}

fn sha512Conclude(ctx: *Sha512Ctx) void {
    const bp: [*]u8 = @ptrCast(&ctx.buffer);
    const bytes = ctx.buflen;
    // One block holds the padding if < 112 bytes buffered, else two.
    const size: usize = if (bytes < 112) 16 else 32; // in 64-bit words

    const old0 = ctx.total[0];
    ctx.total[0] +%= @intCast(bytes);
    if (ctx.total[0] < old0) ctx.total[1] +%= 1;

    // Append the 128-bit message length in bits, big-endian (the low
    // 64 bits always fit in the two u64 counters for any len: usize).
    const bitcount: u128 = ((@as(u128, ctx.total[1]) << 64) | @as(u128, ctx.total[0])) << 3;
    const loff = (size - 2) * 8;
    var i: usize = 0;
    while (i < 16) : (i += 1) bp[loff + i] = @truncate(bitcount >> @intCast((15 - i) * 8));

    bp[bytes] = 0x80;
    i = bytes + 1;
    while (i < loff) : (i += 1) bp[i] = 0;

    sha512_process_block(&ctx.buffer, size * 8, ctx);
}

export fn sha512_finish_ctx(ctx: *Sha512Ctx, resbuf: *anyopaque) *anyopaque {
    sha512Conclude(ctx);
    return sha512_read_ctx(ctx, resbuf);
}

export fn sha384_finish_ctx(ctx: *Sha512Ctx, resbuf: *anyopaque) *anyopaque {
    sha512Conclude(ctx);
    return sha384_read_ctx(ctx, resbuf);
}

fn sha512BufferOneShot(h384: bool, buffer: *const anyopaque, len: usize, resblock: *anyopaque) *anyopaque {
    var ctx: Sha512Ctx = undefined;
    sha512Init(&ctx, h384);
    sha512_process_bytes(buffer, len, &ctx);
    sha512Conclude(&ctx);
    return sha512WriteDigest(&ctx, resblock, if (h384) 6 else 8);
}

export fn sha512_buffer(buffer: *const anyopaque, len: usize, resblock: *anyopaque) *anyopaque {
    return sha512BufferOneShot(false, buffer, len, resblock);
}

export fn sha384_buffer(buffer: *const anyopaque, len: usize, resblock: *anyopaque) *anyopaque {
    return sha512BufferOneShot(true, buffer, len, resblock);
}

// ---------------------------------------------------------------------------
// SHA-3 (FIPS 202), replacing gnulib's lib/sha3.c. The ctx layout matches
// lib/sha3.h exactly (extern struct; buflen/digestlen/blocklen are size_t):
//   uint64_t state[25]; uint8_t buffer[144]; size_t buflen, digestlen,
//   blocklen. Keccak-f[1600] sponge with the 0x06 domain suffix.

pub const Sha3Ctx = extern struct {
    state: [25]u64,
    buffer: [144]u8,
    buflen: usize,
    digestlen: usize,
    blocklen: usize,
};

const keccak_rc = [24]u64{
    0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
    0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
    0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
};

// Rotation offsets for lanes in x + 5y order (FIPS 202 section 3.2.3).
const keccak_rho = [25]u6{
    0, 1, 62, 28, 27,
    36, 44, 6, 55, 20,
    3, 10, 43, 25, 39,
    41, 45, 15, 21, 8,
    18, 2, 61, 56, 14,
};

// Destination lane for each source lane under the pi permutation.
const keccak_pi = [25]u8{
    0, 10, 20, 5, 15,
    16, 1, 11, 21, 6,
    7, 17, 2, 12, 22,
    23, 8, 18, 3, 13,
    14, 24, 9, 19, 4,
};

fn keccakF(a: *[25]u64) void {
    var round: usize = 0;
    while (round < 24) : (round += 1) {
        // Theta.
        var c: [5]u64 = undefined;
        for (0..5) |x| c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20];
        var d: [5]u64 = undefined;
        for (0..5) |x| d[x] = c[(x + 4) % 5] ^ rotl64(c[(x + 1) % 5], 1);
        for (0..25) |i| a[i] ^= d[i % 5];

        // Rho and Pi.
        var b: [25]u64 = undefined;
        for (0..25) |i| b[keccak_pi[i]] = rotl64(a[i], keccak_rho[i]);

        // Chi.
        for (0..5) |y| {
            const base = 5 * y;
            var t: [5]u64 = undefined;
            for (0..5) |x| t[x] = b[base + x];
            for (0..5) |x| a[base + x] = t[x] ^ ((~t[(x + 1) % 5]) & t[(x + 2) % 5]);
        }

        // Iota.
        a[0] ^= keccak_rc[round];
    }
}

inline fn rotl64(x: u64, n: u6) u64 {
    const r: u6 = @intCast(64 - @as(u63, n));
    return (x << n) | (x >> r);
}

fn sha3Init(ctx: *Sha3Ctx, digestlen: usize, blocklen: usize) bool {
    ctx.state = .{0} ** 25;
    ctx.buflen = 0;
    ctx.digestlen = digestlen;
    ctx.blocklen = blocklen;
    return true;
}

pub export fn sha3_224_init_ctx(ctx: *Sha3Ctx) bool {
    return sha3Init(ctx, 28, 144);
}

pub export fn sha3_256_init_ctx(ctx: *Sha3Ctx) bool {
    return sha3Init(ctx, 32, 136);
}

pub export fn sha3_384_init_ctx(ctx: *Sha3Ctx) bool {
    return sha3Init(ctx, 48, 104);
}

pub export fn sha3_512_init_ctx(ctx: *Sha3Ctx) bool {
    return sha3Init(ctx, 64, 72);
}

pub export fn sha3_free_ctx(ctx: *Sha3Ctx) void {
    _ = ctx;
    // Nothing to free (the gnulib C implementation is a no-op too).
}

// Process LEN bytes of BUFFER (LEN a multiple of BLOCKLEN), updating CTX.
pub export fn sha3_process_block(buffer: *const anyopaque, len: usize, ctx: *Sha3Ctx) bool {
    const bp: [*]const u8 = @ptrCast(buffer);
    const rate_words = ctx.blocklen / 8;
    var off: usize = 0;
    while (off < len) : (off += ctx.blocklen) {
        for (0..rate_words) |i| {
            ctx.state[i] ^= rd64le(bp, off + i * 8);
        }
        keccakF(&ctx.state);
    }
    return true;
}

// Update CTX for LEN bytes at BUFFER (LEN need not be a multiple of
// BLOCKLEN); buffer the partial block for the next call.
pub export fn sha3_process_bytes(buffer: *const anyopaque, len: usize, ctx: *Sha3Ctx) bool {
    const src: [*]const u8 = @ptrCast(buffer);
    var s: usize = 0;
    var remaining = len;

    if (0 < ctx.buflen) {
        const left = ctx.blocklen - ctx.buflen;
        if (remaining < left) {
            @memcpy(ctx.buffer[ctx.buflen..][0..remaining], src[0..remaining]);
            ctx.buflen += remaining;
            return true;
        }
        @memcpy(ctx.buffer[ctx.buflen..][0..left], src[0..left]);
        s += left;
        remaining -= left;
        _ = sha3_process_block(&ctx.buffer, ctx.blocklen, ctx);
    }

    const full = remaining - remaining % ctx.blocklen;
    _ = sha3_process_block(&src[s], full, ctx);
    s += full;
    remaining -= full;

    @memcpy(ctx.buffer[0..remaining], src[s..][0..remaining]);
    ctx.buflen = remaining;
    return true;
}

// Write the digest (DIGESTLEN bytes, little-endian state words) to RESBUF.
pub export fn sha3_read_ctx(ctx: *const Sha3Ctx, resbuf: *anyopaque) *anyopaque {
    const r: [*]u8 = @ptrCast(resbuf);
    const words = ctx.digestlen / 8;
    var i: usize = 0;
    while (i < words) : (i += 1) wr64le(r, i * 8, ctx.state[i]);
    var bytes = ctx.digestlen % 8;
    var off = words * 8;
    var word = ctx.state[words];
    while (bytes > 0) : (bytes -= 1) {
        r[off] = @truncate(word);
        off += 1;
        word >>= 8;
    }
    return resbuf;
}

// Pad (0x06 domain suffix + 0x80 terminator), absorb the final block(s)
// and write the digest to RESBUF.
pub export fn sha3_finish_ctx(ctx: *Sha3Ctx, resbuf: *anyopaque) *anyopaque {
    ctx.buffer[ctx.buflen] = 0x06;
    ctx.buflen += 1;
    @memset(ctx.buffer[ctx.buflen..][0 .. ctx.blocklen - ctx.buflen], 0);
    ctx.buffer[ctx.blocklen - 1] |= 0x80;
    _ = sha3_process_block(&ctx.buffer, ctx.blocklen, ctx);
    return sha3_read_ctx(ctx, resbuf);
}

fn sha3BufferOneShot(digestlen: usize, blocklen: usize, buffer: *const anyopaque, len: usize, resblock: *anyopaque) *anyopaque {
    var ctx: Sha3Ctx = undefined;
    _ = sha3Init(&ctx, digestlen, blocklen);
    _ = sha3_process_bytes(buffer, len, &ctx);
    return sha3_finish_ctx(&ctx, resblock);
}

pub export fn sha3_224_buffer(buffer: *const anyopaque, len: usize, resblock: *anyopaque) *anyopaque {
    return sha3BufferOneShot(28, 144, buffer, len, resblock);
}

pub export fn sha3_256_buffer(buffer: *const anyopaque, len: usize, resblock: *anyopaque) *anyopaque {
    return sha3BufferOneShot(32, 136, buffer, len, resblock);
}

pub export fn sha3_384_buffer(buffer: *const anyopaque, len: usize, resblock: *anyopaque) *anyopaque {
    return sha3BufferOneShot(48, 104, buffer, len, resblock);
}

pub export fn sha3_512_buffer(buffer: *const anyopaque, len: usize, resblock: *anyopaque) *anyopaque {
    return sha3BufferOneShot(64, 72, buffer, len, resblock);
}
