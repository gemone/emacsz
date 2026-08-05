// Zig replacements for gnulib's c-ctype character-classification
// functions. lib/c-ctype.c is merely the out-of-line externals for the
// `extern inline` definitions in lib/c-ctype.h, so excluding it from the
// build and providing these exported symbols here replaces it. Each is
// ASCII-only and locale-independent (C_CTYPE_ASCII in c-ctype.h), matching
// gnulib's exact semantics: `is*` take int and return bool (false for any
// non-ASCII/EOF input, including c < 0); `to*` take int and return int
// unchanged outside A-Z/a-z. No libc call, no std import.
//
// Signatures match the C declarations in lib/c-ctype.h.

export fn c_isalnum(c: c_int) bool {
    return (c >= '0' and c <= '9') or (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}

export fn c_isalpha(c: c_int) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}

export fn c_isascii(c: c_int) bool {
    return c >= 0 and c <= 0x7f;
}

export fn c_isblank(c: c_int) bool {
    return c == ' ' or c == '\t';
}

export fn c_iscntrl(c: c_int) bool {
    return (c >= 0 and c <= 0x1f) or c == 0x7f;
}

export fn c_isdigit(c: c_int) bool {
    return c >= '0' and c <= '9';
}

export fn c_isgraph(c: c_int) bool {
    return c >= 0x21 and c <= 0x7e;
}

export fn c_islower(c: c_int) bool {
    return c >= 'a' and c <= 'z';
}

export fn c_isprint(c: c_int) bool {
    return c >= 0x20 and c <= 0x7e;
}

export fn c_ispunct(c: c_int) bool {
    return c_isgraph(c) and !c_isalnum(c);
}

export fn c_isspace(c: c_int) bool {
    return c == ' ' or (c >= '\t' and c <= '\r');
}

export fn c_isupper(c: c_int) bool {
    return c >= 'A' and c <= 'Z';
}

export fn c_isxdigit(c: c_int) bool {
    return (c >= '0' and c <= '9') or (c >= 'A' and c <= 'F') or (c >= 'a' and c <= 'f');
}

export fn c_tolower(c: c_int) c_int {
    if (c >= 'A' and c <= 'Z') return c + ('a' - 'A');
    return c;
}

export fn c_toupper(c: c_int) c_int {
    if (c >= 'a' and c <= 'z') return c - ('a' - 'A');
    return c;
}
