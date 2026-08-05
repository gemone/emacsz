// Native Zig implementation of SHA1, replacing gnulib's lib/sha1.c.
// Operates on the gnulib struct sha1_ctx layout (lib/sha1.h) so temacs's
// existing call sites (sha1_init_ctx / sha1_process_bytes /
// sha1_finish_ctx in src/fns.c, used by `secure-hash') work unchanged.
// Standard SHA1 (FIPS 180-1); no libc call, no std import.
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
