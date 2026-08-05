// memeq - bytewise equality of two buffers of length n.
//
// Replaces gnulib's lib/memeq.c, whose body is `!memcmp(a, b, n)` (emitted
// out-of-line via an `extern inline` in lib/string.h). This Zig version
// performs the comparison directly with a byte loop and does NOT call
// libc - the first gnulib function provided by an independent Zig package
// instead of C, a step toward decoupling the build from libc. At the
// build's -O0 the C compiler does not inline the gnulib header version,
// so callers resolve to this exported symbol.
//
// Signature matches the C declaration `bool memeq(void const *, void const
// *, size_t)` (lib/string.h). Built as a standalone object with no std
// dependency and no safety checks (ReleaseFast), so it pulls in no Zig
// runtime or panic handler that a C executable would have to satisfy.
export fn memeq(s1: [*]const u8, s2: [*]const u8, n: usize) bool {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (s1[i] != s2[i]) return false;
    }
    return true;
}
