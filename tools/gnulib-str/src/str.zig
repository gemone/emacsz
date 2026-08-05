// Zig replacements for gnulib string-primitive functions whose C sources
// (lib/memeq.c, lib/streq.c) merely emit the out-of-line external for an
// `extern inline` in lib/string.h. Provided here as independent Zig with
// no libc call -- a step toward decoupling the build from libc. At the
// build's -O0 the C compiler does not inline the header versions, so
// callers resolve to these exported symbols. Signatures match the C
// declarations in lib/string.h.

// memeq: bytewise equality of two buffers of length n. (C body: !memcmp.)
export fn memeq(s1: [*]const u8, s2: [*]const u8, n: usize) bool {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (s1[i] != s2[i]) return false;
    }
    return true;
}

// streq: equality of two null-terminated strings. (C body: !strcmp.)
export fn streq(s1: [*:0]const u8, s2: [*:0]const u8) bool {
    var i: usize = 0;
    while (true) : (i += 1) {
        const a = s1[i];
        const b = s2[i];
        if (a != b) return false;
        if (a == 0) return true;
    }
}
