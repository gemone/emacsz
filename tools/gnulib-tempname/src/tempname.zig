// Native Zig implementation of gnulib's temp-name generation
// (lib/tempname.c + lib/mkostemp.c): gen_tempname / gen_tempname_len /
// mkostemp, backing `make-temp-file', filelock and call-process
// temporary files. Randomness comes from getrandom(GRND_NONBLOCK) with
// the same low-quality clock-mix fallback; name probes use raw syscalls
// (openat O_CREAT|O_EXCL, mkdir, newfstatat); errno is set on failure
// exactly as the C code does (callers such as filelock read it).

const std = @import("std");
const linux = std.os.linux;
const builtin = @import("builtin");

comptime {
    if (builtin.os.tag != .linux and builtin.os.tag != .android)
        @compileError("gnulib-tempname: raw-syscall tempname is Linux-only for now");
}

// glibc/musl errno location; temacs links libc, so the symbol resolves
// at final link even though this module itself does not link libc.
extern fn __errno_location() *c_int;

const GT_FILE: c_int = 0;
const GT_DIR: c_int = 1;
const GT_NOCREATE: c_int = 2;

// max(TMP_MAX, 62^3); both are 238328.
const ATTEMPTS: u32 = 238328;

const BASE_62_DIGITS: u32 = 10; // 62^10 < 2^64
const BASE_62_POWER: u64 = 839299365868340224; // 62^10

const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

const EINVAL: c_int = 22;
const EEXIST: c_int = 17;
const ENOENT: c_int = 2;
const EOVERFLOW: c_int = 75;
const GRND_NONBLOCK: u32 = 1;

const O_ACCMODE: u32 = 3;
const O_RDWR: u32 = 2;
const O_CREAT: u32 = 0x40;
const O_EXCL: u32 = 0x80;

fn setErrno(e: c_int) void {
    __errno_location().* = e;
}

inline fn mixRandomValues(r: u64, s: u64) u64 {
    return (2862933555777941757 *% r +% 3037000493) ^ s;
}

// Set *R to a random value; return true when it came from getrandom
// (high quality), false for the clock-based ersatz fallback.
fn randomBits(r: *u64, s: u64) bool {
    var buf: [8]u8 = undefined;
    if (linux.getrandom(&buf, 8, GRND_NONBLOCK) == 8) {
        r.* = std.mem.readInt(u64, &buf, .little);
        return true;
    }

    var v = s;
    var tv: linux.timespec = undefined;
    _ = linux.clock_gettime(linux.CLOCK.REALTIME, &tv);
    v = mixRandomValues(v, @intCast(tv.sec));
    v = mixRandomValues(v, @intCast(tv.nsec));
    r.* = v;
    return false;
}

const TryResult = struct { rc: c_int, err: c_int };

fn tryFile(tmpl: [*:0]const u8, flags: c_int) TryResult {
    const f: u32 = (@as(u32, @bitCast(flags)) & ~O_ACCMODE) | O_RDWR | O_CREAT | O_EXCL;
    const raw = linux.openat(linux.AT.FDCWD, tmpl, @bitCast(f), 0o600);
    const r = @as(isize, @bitCast(raw));
    if (r >= 0) return .{ .rc = @intCast(r), .err = 0 };
    return .{ .rc = -1, .err = @intCast(-r) };
}

fn tryDir(tmpl: [*:0]const u8, _: c_int) TryResult {
    const raw = linux.mkdir(tmpl, 0o700);
    if (raw == 0) return .{ .rc = 0, .err = 0 };
    return .{ .rc = -1, .err = @intCast(-@as(isize, @bitCast(raw))) };
}

fn tryNocreate(tmpl: [*:0]const u8, _: c_int) TryResult {
    // lstat via newfstatat + AT_SYMLINK_NOFOLLOW; only the result matters.
    var st: [512]u8 = undefined;
    const raw = linux.syscall4(
        .fstatat64,
        @bitCast(@as(isize, linux.AT.FDCWD)),
        @intFromPtr(tmpl),
        @intFromPtr(&st),
        @as(usize, 0x100), // AT_SYMLINK_NOFOLLOW
    );
    const r = @as(isize, @bitCast(raw));
    if (r == 0 or r == -EOVERFLOW) return .{ .rc = -1, .err = EEXIST };
    if (r == -ENOENT) return .{ .rc = 0, .err = 0 };
    return .{ .rc = -1, .err = @intCast(-r) };
}

fn tryTempnameLen(
    tmpl: [*:0]u8,
    suffixlen: c_int,
    flags: c_int,
    kind: c_int,
    x_suffix_len: usize,
) c_int {
    const saved_errno = __errno_location().*;

    const len = std.mem.len(tmpl);
    if (suffixlen < 0) {
        setErrno(EINVAL);
        return -1;
    }
    const sl: usize = @intCast(suffixlen);
    if (len < x_suffix_len + sl) {
        setErrno(EINVAL);
        return -1;
    }
    const x_start = len - x_suffix_len - sl;
    var all_x = true;
    for (0..x_suffix_len) |i| {
        if (tmpl[x_start + i] != 'X') {
            all_x = false;
            break;
        }
    }
    if (!all_x) {
        setErrno(EINVAL);
        return -1;
    }

    const tryfuncs = [_]*const fn ([*:0]const u8, c_int) TryResult{ tryFile, tryDir, tryNocreate };
    const tryfunc = tryfuncs[@intCast(kind)];

    // Random state persists across attempts: 10 base-62 digits are
    // extracted per random value, so with a 6-X suffix four digits carry
    // over to the next attempt (matching the C loop exactly).
    var v: u64 = 0;
    var vdigbuf: u64 = 0;
    var vdigits: u32 = 0;
    const biased_min = ~@as(u64, 0) - (~@as(u64, 0) % BASE_62_POWER);

    var count: u32 = 0;
    while (count < ATTEMPTS) : (count += 1) {
        var i: usize = 0;
        while (i < x_suffix_len) : (i += 1) {
            if (vdigits == 0) {
                // Re-roll only when the bits are high quality (getrandom)
                // and biased; the ersatz fallback is used as-is.
                while (true) {
                    const hq = randomBits(&v, v);
                    if (!hq or v < biased_min) break;
                }
                vdigbuf = v;
                vdigits = BASE_62_DIGITS;
            }
            tmpl[x_start + i] = letters[@as(usize, vdigbuf % 62)];
            vdigbuf = @divTrunc(vdigbuf, 62);
            vdigits -= 1;
        }
        const res = tryfunc(tmpl, flags);
        if (res.rc >= 0) {
            setErrno(saved_errno);
            return res.rc;
        }
        if (res.err != EEXIST) {
            // The C code relies on the failed syscall having set errno.
            setErrno(res.err);
            return -1;
        }
    }

    setErrno(EEXIST);
    return -1;
}

// Generate a temporary file name based on TMPL (ending in at least
// X_SUFFIX_LEN Xs, possibly followed by a suffix); overwrite TMPL and
// return a descriptor for GT_FILE, 0 for GT_NOCREATE/GT_DIR on success.
pub export fn gen_tempname_len(
    tmpl: [*:0]u8,
    suffixlen: c_int,
    flags: c_int,
    kind: c_int,
    x_suffix_len: usize,
) c_int {
    return tryTempnameLen(tmpl, suffixlen, flags, kind, x_suffix_len);
}

pub export fn gen_tempname(tmpl: [*:0]u8, suffixlen: c_int, flags: c_int, kind: c_int) c_int {
    return gen_tempname_len(tmpl, suffixlen, flags, kind, 6);
}

// Generate a unique temp file from XTEMPLATE (last six chars "XXXXXX")
// and return an open fd.
pub export fn mkostemp(xtemplate: [*:0]u8, flags: c_int) c_int {
    return gen_tempname(xtemplate, 0, flags, GT_FILE);
}
