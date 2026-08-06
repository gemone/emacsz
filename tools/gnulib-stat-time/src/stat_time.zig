// Native Zig implementation of gnulib's lib/stat-time.c external
// definitions (the accessors are inline in lib/stat-time.h): extract
// the access/status-change/modification (and birth) timestamps from a
// struct stat. On glibc x86_64 st_atim/st_mtim/st_ctim are struct
// timespec members and there is no birth-time field, so get_stat_* read
// the timespecs directly and get_stat_birthtime returns (-1, -1);
// stat_time_normalize is a passthrough (the macOS/Solaris negative-ns
// workaround does not apply). Backs `file-attributes' time elements in
// src/dired.c and src/fileio.c. No libc call.

const std = @import("std");
const builtin = @import("builtin");

fn isDarwin(tag: std.Target.Os.Tag) bool {
    return switch (tag) {
        .macos, .ios, .tvos, .watchos, .visionos, .driverkit, .maccatalyst => true,
        else => false,
    };
}

// glibc x86_64 struct stat (144 bytes; timespec members at 72/88/104).
pub const Stat = extern struct {
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
    if (@offsetOf(Stat, "st_atim") != 72 or @offsetOf(Stat, "st_mtim") != 88 or
        @offsetOf(Stat, "st_ctim") != 104)
        @compileError("struct stat layout mismatch: timespec members at wrong offsets");
}

const Timespec = extern struct {
    tv_sec: i64,
    tv_nsec: i64,
};

pub export fn get_stat_atime_ns(st: *const Stat) c_long {
    if (comptime isDarwin(builtin.os.tag))
        return @intCast(darwinStat(st).st_atimespec.tv_nsec);
    return @intCast(st.st_atim[1]);
}

pub export fn get_stat_ctime_ns(st: *const Stat) c_long {
    if (comptime isDarwin(builtin.os.tag))
        return @intCast(darwinStat(st).st_ctimespec.tv_nsec);
    return @intCast(st.st_ctim[1]);
}

pub export fn get_stat_mtime_ns(st: *const Stat) c_long {
    if (comptime isDarwin(builtin.os.tag))
        return @intCast(darwinStat(st).st_mtimespec.tv_nsec);
    return @intCast(st.st_mtim[1]);
}

pub export fn get_stat_atime(st: *const Stat) Timespec {
    if (comptime isDarwin(builtin.os.tag)) {
        const d = darwinStat(st);
        return .{ .tv_sec = d.st_atimespec.tv_sec, .tv_nsec = @intCast(d.st_atimespec.tv_nsec) };
    }
    return .{ .tv_sec = st.st_atim[0], .tv_nsec = @intCast(st.st_atim[1]) };
}

pub export fn get_stat_ctime(st: *const Stat) Timespec {
    if (comptime isDarwin(builtin.os.tag)) {
        const d = darwinStat(st);
        return .{ .tv_sec = d.st_ctimespec.tv_sec, .tv_nsec = @intCast(d.st_ctimespec.tv_nsec) };
    }
    return .{ .tv_sec = st.st_ctim[0], .tv_nsec = @intCast(st.st_ctim[1]) };
}

pub export fn get_stat_mtime(st: *const Stat) Timespec {
    if (comptime isDarwin(builtin.os.tag)) {
        const d = darwinStat(st);
        return .{ .tv_sec = d.st_mtimespec.tv_sec, .tv_nsec = @intCast(d.st_mtimespec.tv_nsec) };
    }
    return .{ .tv_sec = st.st_mtim[0], .tv_nsec = @intCast(st.st_mtim[1]) };
}

pub export fn stat_time_normalize(result: c_int, st: ?*Stat) c_int {
    _ = st;
    return result; // macOS/Solaris negative-tv_nsec workaround does not apply
}

// Darwin x86_64 struct stat (timespec members named st_*timespec, with
// st_birthtimespec present).
const StatDarwin = extern struct {
    st_dev: i32,
    st_mode: u16,
    st_nlink: u16,
    st_ino: u64,
    st_uid: u32,
    st_gid: u32,
    st_rdev: i32,
    st_atimespec: Timespec,
    st_mtimespec: Timespec,
    st_ctimespec: Timespec,
    st_birthtimespec: Timespec,
    st_size: i64,
    st_blocks: i64,
    st_blksize: i32,
    st_flags: u32,
    st_gen: u32,
    st_lspare: i32,
    st_qspare: [2]i64,
};

fn darwinStat(st: *const Stat) *const StatDarwin {
    return @ptrCast(st);
}

// Birth time only exists on macOS; the Linux accessors return constant
// "not supported" values. Split into helpers because Zig analyzes both
// comptime-if branches and a parameter used in one cannot be discarded
// in the other.
pub export fn get_stat_birthtime_ns(st: *const Stat) c_long {
    if (comptime isDarwin(builtin.os.tag))
        return darwinBirthNs(st);
    return linuxBirthNs(st);
}

pub export fn get_stat_birthtime(st: *const Stat) Timespec {
    if (comptime isDarwin(builtin.os.tag))
        return darwinBirthTime(st);
    return linuxBirthTime(st);
}

fn darwinBirthNs(st: *const Stat) c_long {
    return @intCast(darwinStat(st).st_birthtimespec.tv_nsec);
}

fn linuxBirthNs(st: *const Stat) c_long {
    _ = st;
    return 0; // no birth-time field on Linux
}

fn darwinBirthTime(st: *const Stat) Timespec {
    const d = darwinStat(st);
    return .{ .tv_sec = d.st_birthtimespec.tv_sec, .tv_nsec = @intCast(d.st_birthtimespec.tv_nsec) };
}

fn linuxBirthTime(st: *const Stat) Timespec {
    _ = st;
    // Birth time is not supported on Linux; both fields -1.
    return .{ .tv_sec = -1, .tv_nsec = -1 };
}
