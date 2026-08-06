// Native Zig implementation of gnulib's lib/fsusage.c (get_fs_usage),
// backing `file-system-info' in src/fileio.c. Reads the mount's
// statfs(2) and maps the kernel fields into the gnulib struct fs_usage.
//   Linux  -> raw statfs syscall (no libc call).
//   Darwin -> libc statfs (macOS's stable ABI).
//   Windows -> GetDiskFreeSpaceExA (kernel32; fileio.c never queries
//             fs usage under DOS_NT, so this keeps the API available).
// errno is set on failure exactly as the C code leaves it.

const std = @import("std");
const linux = std.os.linux;
const builtin = @import("builtin");

fn isDarwin(tag: std.Target.Os.Tag) bool {
    return switch (tag) {
        .macos, .ios, .tvos, .watchos, .visionos, .driverkit, .maccatalyst => true,
        else => false,
    };
}

fn isWindows(tag: std.Target.Os.Tag) bool {
    return tag == .windows;
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
    if (comptime isDarwin(builtin.os.tag))
        return getFsUsageDarwin(file, fsp);
    if (comptime isWindows(builtin.os.tag))
        return getFsUsageWindows(file, fsp);
    if (builtin.os.tag != .linux)
        @compileError("gnulib-fsusage: no implementation for this OS");
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

// Darwin x86_64 struct statfs (the fields get_fs_usage reads; the
// trailing name arrays are omitted since the layout is not needed).
const StatFsDarwin = extern struct {
    f_bsize: u32,
    f_iosize: i32,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_fsid: [2]i32,
    f_owner: u32,
    f_type: u32,
    f_flags: u32,
    f_fssubtype: u32,
    f_fsize: u32,
    f_reserved: [2]u32,
};

extern "c" fn statfs(path: [*:0]const u8, buf: *anyopaque) c_int;

fn getFsUsageDarwin(file: [*:0]const u8, fsp: *FsUsage) c_int {
    // statfs fills the entire macOS struct (the trailing mount-name
    // arrays add ~2 KiB), so back the leading-field layout with a
    // padded buffer instead of an undersized stack struct.
    var raw: [4096]u8 align(16) = undefined;
    if (statfs(file, &raw) != 0)
        return -1;
    const fsd: *const StatFsDarwin = @ptrCast(&raw);
    fsp.fsu_blocksize = fsd.f_bsize;
    fsp.fsu_blocks = fsd.f_blocks;
    fsp.fsu_bfree = fsd.f_bfree;
    fsp.fsu_bavail = fsd.f_bavail;
    fsp.fsu_bavail_top_bit_set = (fsd.f_bavail >> 63) != 0;
    fsp.fsu_files = fsd.f_files;
    fsp.fsu_ffree = fsd.f_ffree;
    return 0;
}

// Windows: GetDiskFreeSpaceExA reports bytes; map them into 1024-byte
// blocks.  File counts are unknown (the all-ones sentinel that
// PROPAGATE_ALL_ONES would produce).
extern "c" fn GetDiskFreeSpaceExA(
    dir: [*:0]const u8,
    free: ?*u64,
    total: ?*u64,
    avail: ?*u64,
) c_int;

fn getFsUsageWindows(file: [*:0]const u8, fsp: *FsUsage) c_int {
    var total: u64 = 0;
    var free: u64 = 0;
    var avail: u64 = 0;
    if (GetDiskFreeSpaceExA(file, &free, &total, &avail) == 0)
        return -1;
    const blocksize: u64 = 1024;
    fsp.fsu_blocksize = blocksize;
    fsp.fsu_blocks = @divTrunc(total, blocksize);
    fsp.fsu_bfree = @divTrunc(free, blocksize);
    fsp.fsu_bavail = @divTrunc(avail, blocksize);
    fsp.fsu_bavail_top_bit_set = false;
    fsp.fsu_files = std.math.maxInt(u64);
    fsp.fsu_ffree = std.math.maxInt(u64);
    return 0;
}
