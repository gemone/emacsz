// Native Zig implementation of gnulib's lib/c-strcasecmp.c and
// lib/c-strncasecmp.c: ASCII case-insensitive string comparison using
// c_tolower (the c-ctype function already provided by the
// tools/gnulib-ctype package). Backs `-exe' detection in src/emacs.c
// and font-pattern matching in src/ftfont.c. Pure byte logic; no libc
// call, no std import.

fn toLower(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

// Compare S1 and S2 case-insensitively; return negative, zero or
// positive like strcmp.
pub export fn c_strcasecmp(s1: [*:0]const u8, s2: [*:0]const u8) c_int {
    if (s1 == s2) return 0;
    var p1: usize = 0;
    var p2: usize = 0;
    while (true) {
        const c1 = toLower(s1[p1]);
        const c2 = toLower(s2[p2]);
        p1 += 1;
        p2 += 1;
        if (c1 == 0 or c1 != c2)
            return @as(c_int, c1) - @as(c_int, c2);
    }
}

// Compare at most N bytes of S1 and S2 case-insensitively.
pub export fn c_strncasecmp(s1: [*:0]const u8, s2: [*:0]const u8, n: usize) c_int {
    if (s1 == s2 or n == 0) return 0;
    var p1: usize = 0;
    var p2: usize = 0;
    var remaining = n;
    while (true) {
        const c1 = toLower(s1[p1]);
        const c2 = toLower(s2[p2]);
        p1 += 1;
        p2 += 1;
        remaining -= 1;
        if (remaining == 0 or c1 == 0 or c1 != c2)
            return @as(c_int, c1) - @as(c_int, c2);
    }
}
