// Native Zig implementation of gnulib's lib/fsusage.c (get_fs_usage),
// backing `file-system-info' in src/fileio.c. Reads the mount's
// statfs(2) via a raw syscall and maps the kernel fields into the
// gnulib struct fs_usage, matching what glibc's statvfs-based path
// returns on modern Linux (the pre-2.6.36 statvfs hang workaround is
// irrelevant here). errno is set on failure exactly as the C code
// leaves it (fileio.c tests for ENOSYS). No libc call.

const std = @import("std");
const linux = std.os.linux;
const builtin = @import("builtin");

comptime {
    if (builtin.os.tag != .linux and builtin.os.tag != .android)
        @compileError("gnulib-fsusage: raw-statfs implementation is Linux-only for now");
}

extern fn __errno_location() *c_int;

// gnulib struct fs_usage (lib/fsusage.h): 64-bit uintmax_t fields.
pub const FsUsage = extern struct {
    fsu_blocksize: u64,
    fsu_blocks: u64,
    fsu_bfree: u64,
    fsu_bavail: u64,
    fsu_bavail_top_bit_set: bool,
    fsu_files: u64,
    fsu_ffree: u64,
};

// Linux x86_64 struct statfs (all long/unsigned long = 64-bit fields).
const StatFs = extern struct {
    f_type: i64,
    f_bsize: i64,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_fsid: [2]i32,
    f_namelen: i64,
    f_frsize: i64,
    f_flags: i64,
    f_spare: [4]i64,
};

// Fill in the fields of FSP with space usage for the file system on
// which FILE resides.  DISK is ignored (the statfs method needs no
// device).  Return 0 on success, -1 on failure (with errno set).
pub export fn get_fs_usage(
    file: [*:0]const u8,
    disk: ?[*:0]const u8,
    fsp: *FsUsage,
) c_int {
    _ = disk;

    var fsd: StatFs = undefined;
    const raw = linux.syscall2(.statfs, @intFromPtr(file), @intFromPtr(&fsd));
    if (@as(isize, @bitCast(raw)) < 0) {
        __errno_location().* = @intCast(-@as(isize, @bitCast(raw)));
        return -1;
    }

    // f_frsize isn't guaranteed to be supported; fall back to f_bsize.
    // For 64-bit fields the gnulib PROPAGATE_ALL_ONES/TOP_BIT macros are
    // identities, so the raw values are copied through.
    fsp.fsu_blocksize = if (fsd.f_frsize != 0)
        @bitCast(fsd.f_frsize)
    else
        @bitCast(fsd.f_bsize);
    fsp.fsu_blocks = fsd.f_blocks;
    fsp.fsu_bfree = fsd.f_bfree;
    fsp.fsu_bavail = fsd.f_bavail;
    fsp.fsu_bavail_top_bit_set = (fsd.f_bavail >> 63) != 0;
    fsp.fsu_files = fsd.f_files;
    fsp.fsu_ffree = fsd.f_ffree;
    return 0;
}
