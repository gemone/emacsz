// Native Zig implementation of gnulib's lib/filemode.c: strmode and
// filemodestring turn a file mode into an ls-style string like
// "-rwxr-xr-x". No libc call, no std import.
//
// Only st_mode is consulted. The extra S_TYPEISSEM/S_TYPEISMQ/
// S_TYPEISSHM/S_TYPEISTMO type letters (F/Q/S/T) are 0 on Linux
// (S_INSEM and friends are undefined), so filemodestring reduces to
// strmode (statp->st_mode) on this target.
//
// Stat is glibc x86_64's struct stat layout; the comptime check below
// pins st_mode's offset so a wrong layout fails at compile time.

const Stat = extern struct {
    st_dev: u64,
    st_ino: u64,
    st_nlink: u64,
    st_mode: u32,
    st_uid: u32,
    st_gid: u32,
    pad0: u32,
    st_rdev: u64,
    st_size: i64,
    st_blksize: i64,
    st_blocks: i64,
    st_atim: [2]i64,
    st_mtim: [2]i64,
    st_ctim: [2]i64,
    reserved: [3]i64,
};

comptime {
    if (@offsetOf(Stat, "st_mode") != 24)
        @compileError("struct stat layout mismatch: st_mode expected at offset 24");
}

// File-type bits (POSIX/glibc S_IFMT 0170000 with S_IFxxx values).
const S_IFREG: u32 = 0x8000;
const S_IFDIR: u32 = 0x4000;
const S_IFBLK: u32 = 0x6000;
const S_IFCHR: u32 = 0x2000;
const S_IFLNK: u32 = 0xA000;
const S_IFIFO: u32 = 0x1000;
const S_IFSOCK: u32 = 0xC000;

// Special and permission bits.
const S_ISUID: u32 = 0x800;
const S_ISGID: u32 = 0x400;
const S_ISVTX: u32 = 0x200;
const S_IRUSR: u32 = 0x100;
const S_IWUSR: u32 = 0x80;
const S_IXUSR: u32 = 0x40;
const S_IRGRP: u32 = 0x20;
const S_IWGRP: u32 = 0x10;
const S_IXGRP: u32 = 0x8;
const S_IROTH: u32 = 0x4;
const S_IWOTH: u32 = 0x2;
const S_IXOTH: u32 = 0x1;

// File-type character for MODE (lib/filemode.c ftypelet). The
// nonstandard S_ISCTG/DOOR/MPB/MPC/MPX/NWK/PORT/WHT letters are
// unreachable on Linux (the S_IS* macros are 0), so only the POSIX
// types can appear here.
fn ftypelet(bits: u32) u8 {
    return switch (bits & 0xF000) {
        S_IFREG => '-',
        S_IFDIR => 'd',
        S_IFBLK => 'b',
        S_IFCHR => 'c',
        S_IFLNK => 'l',
        S_IFIFO => 'p',
        S_IFSOCK => 's',
        else => '?',
    };
}

// Owner/group/other execute slot: 's'/'t' when the special bit is set
// (with execute), 'S'/'T' when set without execute, else 'x'/'-'.
fn specialChar(mode: u32, special: u32, exec: u32, on: u8, on_noexec: u8) u8 {
    if ((mode & special) != 0)
        return if ((mode & exec) != 0) on else on_noexec;
    return if ((mode & exec) != 0) 'x' else '-';
}

// Write the 12-byte ls-style mode string for MODE into STR.
export fn strmode(mode: u32, str: [*]u8) void {
    str[0] = ftypelet(mode);
    str[1] = if ((mode & S_IRUSR) != 0) 'r' else '-';
    str[2] = if ((mode & S_IWUSR) != 0) 'w' else '-';
    str[3] = specialChar(mode, S_ISUID, S_IXUSR, 's', 'S');
    str[4] = if ((mode & S_IRGRP) != 0) 'r' else '-';
    str[5] = if ((mode & S_IWGRP) != 0) 'w' else '-';
    str[6] = specialChar(mode, S_ISGID, S_IXGRP, 's', 'S');
    str[7] = if ((mode & S_IROTH) != 0) 'r' else '-';
    str[8] = if ((mode & S_IWOTH) != 0) 'w' else '-';
    str[9] = specialChar(mode, S_ISVTX, S_IXOTH, 't', 'T');
    str[10] = ' ';
    str[11] = 0;
}

// Fill STR with the mode string of STATP (12 bytes, NUL-terminated).
export fn filemodestring(statp: *const Stat, str: [*]u8) void {
    strmode(statp.st_mode, str);
}
