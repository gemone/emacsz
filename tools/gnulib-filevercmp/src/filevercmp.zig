// Native Zig implementation of gnulib's lib/filevercmp.c (filevercmp /
// filenvercmp), the Debian-policy version sort for file names used by
// `string-version-lessp' (src/fns.c). Pure byte/string logic with ASCII
// classification (the c-ctype calls in the C source are ASCII-only); no
// libc call, no std import.

pub const Idx = isize;

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn isAlnum(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}

// Return the length of the prefix of S that corresponds to the suffix
// defined by (\.[A-Za-z~][A-Za-z0-9~]*)*$ in the C locale, using the
// longest such suffix while never using all of S when S is nonempty.
// If *LEN is -1, S is NUL-terminated and *LEN is set to its length;
// otherwise *LEN is a nonnegative length that is not changed.
fn filePrefixlen(s: [*]const u8, len: *isize) Idx {
    const n: usize = if (len.* < 0) ~@as(usize, 0) else @intCast(len.*);
    var prefixlen: Idx = 0;
    var i: usize = 0;
    while (true) {
        if (len.* < 0) {
            if (s[i] == 0) {
                len.* = @intCast(i);
                return prefixlen;
            }
        } else if (i == n) {
            len.* = @intCast(i);
            return prefixlen;
        }
        i += 1;
        prefixlen = @intCast(i);
        while (i + 1 < n and s[i] == '.' and (isAlpha(s[i + 1]) or s[i + 1] == '~')) {
            i += 2;
            while (i < n and (isAlnum(s[i]) or s[i] == '~')) i += 1;
        }
    }
}

// Version-sort comparison value for S's byte at position POS; POS == LEN
// sorts before all non-'~' bytes.
fn order(s: [*]const u8, pos: usize, len: usize) c_int {
    if (pos == len) return -1;
    const c = s[pos];
    if (isDigit(c)) return 0;
    if (isAlpha(c)) return c;
    if (c == '~') return -2;
    // C: c + UCHAR_MAX + 1
    return @as(c_int, c) + 256;
}

// Debian verrevcmp: compare two version strings (arrays of length
// S1_LEN / S2_LEN), alternating lexical and numeric runs.
fn verrevcmp(s1: [*]const u8, s1_len: usize, s2: [*]const u8, s2_len: usize) c_int {
    var s1_pos: usize = 0;
    var s2_pos: usize = 0;
    while (s1_pos < s1_len or s2_pos < s2_len) {
        var first_diff: c_int = 0;
        while ((s1_pos < s1_len and !isDigit(s1[s1_pos])) or
            (s2_pos < s2_len and !isDigit(s2[s2_pos])))
        {
            const s1_c = order(s1, s1_pos, s1_len);
            const s2_c = order(s2, s2_pos, s2_len);
            if (s1_c != s2_c) return s1_c - s2_c;
            s1_pos += 1;
            s2_pos += 1;
        }
        while (s1_pos < s1_len and s1[s1_pos] == '0') s1_pos += 1;
        while (s2_pos < s2_len and s2[s2_pos] == '0') s2_pos += 1;
        while (s1_pos < s1_len and s2_pos < s2_len and
            isDigit(s1[s1_pos]) and isDigit(s2[s2_pos]))
        {
            if (first_diff == 0)
                first_diff = @as(c_int, s1[s1_pos]) - @as(c_int, s2[s2_pos]);
            s1_pos += 1;
            s2_pos += 1;
        }
        if (s1_pos < s1_len and isDigit(s1[s1_pos])) return 1;
        if (s2_pos < s2_len and isDigit(s2[s2_pos])) return -1;
        if (first_diff != 0) return first_diff;
    }
    return 0;
}

// Compare A (of length ALEN, or NUL-terminated if ALEN < 0) and B (of
// length BLEN, likewise) as version-sorted file names.
pub export fn filenvercmp(a: [*]const u8, alen_in: isize, b: [*]const u8, blen_in: isize) c_int {
    var alen = alen_in;
    var blen = blen_in;

    // Special case for empty versions: the empty string sorts first.
    const aempty = if (alen < 0) a[0] == 0 else alen == 0;
    const bempty = if (blen < 0) b[0] == 0 else blen == 0;
    if (aempty) return if (bempty) 0 else -1;
    if (bempty) return 1;

    // Special cases for leading ".": "." sorts first, then "..", then
    // other names with a leading ".", then other names.
    if (a[0] == '.') {
        if (b[0] != '.') return -1;

        const adot = if (alen < 0) a[1] == 0 else alen == 1;
        const bdot = if (blen < 0) b[1] == 0 else blen == 1;
        if (adot) return if (bdot) 0 else -1;
        if (bdot) return 1;

        const adotdot = a[1] == '.' and (if (alen < 0) a[2] == 0 else alen == 2);
        const bdotdot = b[1] == '.' and (if (blen < 0) b[2] == 0 else blen == 2);
        if (adotdot) return if (bdotdot) 0 else -1;
        if (bdotdot) return 1;
    } else if (b[0] == '.') {
        return 1;
    }

    // Cut the version suffixes (filePrefixlen updates alen/blen to the
    // full lengths and returns the prefix lengths).
    const aprefixlen = filePrefixlen(a, &alen);
    const bprefixlen = filePrefixlen(b, &blen);

    // If both suffixes are empty, a second pass would return the same.
    const one_pass_only = aprefixlen == alen and bprefixlen == blen;
    const result = verrevcmp(a, @intCast(aprefixlen), b, @intCast(bprefixlen));
    if (result != 0 or one_pass_only) return result;
    return verrevcmp(a, @intCast(alen), b, @intCast(blen));
}

// Compare NUL-terminated strings S1 and S2 as version-sorted file names.
pub export fn filevercmp(s1: [*:0]const u8, s2: [*:0]const u8) c_int {
    return filenvercmp(s1, -1, s2, -1);
}
