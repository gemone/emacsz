// Native Zig implementation of gnulib's lib/boot-time.c (get_boot_time)
// on Linux, backing lock-file identification in src/filelock.c.
// Replicates the C chain with no libc call: scan /var/run/utmp for a
// BOOT_TIME entry (with the runlevel workaround), fall back to the
// mtime of boot-touched files (>= 1122334455), then to
// CLOCK_BOOTTIME-uptime subtracted from the realtime clock; the result
// is cached in static state like the C code.

const std = @import("std");
const linux = std.os.linux;
const builtin = @import("builtin");

comptime {
    if (builtin.os.tag != .linux and builtin.os.tag != .android)
        @compileError("gnulib-boot-time: Linux implementation only for now");
}

const BOOT_TIME: i16 = 2;
const UTMP_FILE = "/var/run/utmp";

pub const Timespec = extern struct {
    tv_sec: i64,
    tv_nsec: i64,
};

// glibc x86_64 struct utmp: 384-byte records, BOOT_TIME entries carry
// their timestamp in ut_tv (sec/usec).
const Utmp = extern struct {
    ut_type: i16,
    ut_pid: i32,
    ut_line: [32]u8,
    ut_id: [4]u8,
    ut_user: [32]u8,
    ut_host: [256]u8,
    ut_exit: [4]u8,
    ut_session: i32,
    ut_tv_sec: i32,
    ut_tv_usec: i32,
    ut_addr_v6: [4]i32,
    unused: [20]u8,
};

comptime {
    if (@sizeOf(Utmp) != 384 or @offsetOf(Utmp, "ut_user") != 44 or
        @offsetOf(Utmp, "ut_line") != 8 or @offsetOf(Utmp, "ut_tv_sec") != 340)
        @compileError("struct utmp layout mismatch");
}

fn cStrEq(field: []const u8, s: [:0]const u8) bool {
    if (field.len < s.len) return false;
    return std.mem.eql(u8, field[0..s.len], s);
}

fn readFileNul(path: [*:0]const u8, buf: []u8) ?[]const u8 {
    const fd_rc = linux.openat(linux.AT.FDCWD, path, .{}, 0);
    if (@as(isize, @bitCast(fd_rc)) < 0) return null;
    const fd: i32 = @intCast(fd_rc);
    defer _ = linux.close(fd);
    var total: usize = 0;
    while (total < buf.len) {
        const rc = linux.read(fd, buf[total..].ptr, buf.len - total);
        const n = @as(isize, @bitCast(rc));
        if (n < 0) return null;
        if (n == 0) break;
        total += @intCast(n);
    }
    return buf[0..total];
}

// stat(2) mtime of PATH (follows symlinks, like the C stat call).
fn statMtime(path: [*:0]const u8) ?Timespec {
    var st: [512]u8 = undefined;
    const raw = linux.syscall4(
        .fstatat64,
        @bitCast(@as(isize, linux.AT.FDCWD)),
        @intFromPtr(path),
        @intFromPtr(&st),
        0,
    );
    if (@as(isize, @bitCast(raw)) < 0) return null;
    // st_mtim at offset 88 in glibc x86_64 struct stat.
    return .{
        .tv_sec = std.mem.readInt(i64, st[88..96], .little),
        .tv_nsec = std.mem.readInt(i64, st[96..104], .little),
    };
}

// get_linux_uptime: CLOCK_BOOTTIME via raw syscall, else /proc/uptime.
fn linuxUptime() ?Timespec {
    var ts: linux.timespec = undefined;
    if (linux.clock_gettime(linux.CLOCK.BOOTTIME, &ts) == 0)
        return .{ .tv_sec = @intCast(ts.sec), .tv_nsec = @intCast(ts.nsec) };

    var buf: [64]u8 = undefined;
    const data = readFileNul("/proc/uptime", &buf) orelse return null;
    var i: usize = 0;
    var sec: i64 = 0;
    while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1)
        sec = sec * 10 + (data[i] - '0');
    if (i == 0) return null;
    var ns: i64 = 0;
    if (i < data.len and data[i] == '.') {
        i += 1;
        var digits: usize = 0;
        while (digits < 9 and i < data.len and data[i] >= '0' and data[i] <= '9') : ({
            i += 1;
            digits += 1;
        }) ns = ns * 10 + (data[i] - '0');
        while (digits < 9) : (digits += 1) ns *= 10;
    }
    return .{ .tv_sec = sec, .tv_nsec = ns };
}

// Scan /var/run/utmp for the BOOT_TIME entry (with the Raspbian
// runlevel workaround); null if none.
fn utmpBootTime() ?Timespec {
    var buf: [1 << 20]u8 = undefined;
    const data = readFileNul(UTMP_FILE, &buf) orelse return null;

    var found: Timespec = .{ .tv_sec = 0, .tv_nsec = 0 };
    var runlevel: Timespec = .{ .tv_sec = 0, .tv_nsec = 0 };

    var off: usize = 0;
    while (off + @sizeOf(Utmp) <= data.len) : (off += @sizeOf(Utmp)) {
        const u: *const Utmp = @ptrCast(@alignCast(data.ptr + off));
        const ts = Timespec{
            .tv_sec = u.ut_tv_sec,
            .tv_nsec = @as(i64, u.ut_tv_usec) * 1000,
        };
        if (u.ut_type == BOOT_TIME)
            found = ts;
        if (cStrEq(&u.ut_user, "runlevel\x00") and cStrEq(&u.ut_line, "~\x00"))
            runlevel = ts;
    }

    // Raspbian (no RTC) writes a 1970-ish BOOT_TIME then a runlevel entry.
    if (found.tv_sec <= 60 and runlevel.tv_sec != 0)
        found = runlevel;

    return if (found.tv_sec != 0) found else null;
}

// Boot-touched files whose mtime approximates the boot time.
const boot_touched_files = [_][*:0]const u8{
    "/var/lib/systemd/random-seed",
    "/var/lib/urandom/random-seed",
    "/var/lib/random-seed",
    "/var/run/utmp",
};

fn linuxBootTimeFallback() ?Timespec {
    for (boot_touched_files) |path| {
        if (statMtime(path)) |t| {
            // Reject bogus pre-2005 timestamps seen on some distros.
            if (t.tv_sec >= 1122334455)
                return t;
        }
    }
    return null;
}

fn linuxBootTimeFinalFallback() ?Timespec {
    const uptime = linuxUptime() orelse return null;
    var now: linux.timespec = undefined;
    if (linux.clock_gettime(linux.CLOCK.REALTIME, &now) != 0) return null;

    var result = Timespec{
        .tv_sec = @intCast(now.sec),
        .tv_nsec = @intCast(now.nsec),
    };
    if (result.tv_nsec < uptime.tv_nsec) {
        result.tv_nsec += 1000000000;
        result.tv_sec -= 1;
    }
    result.tv_sec -= uptime.tv_sec;
    result.tv_nsec -= uptime.tv_nsec;
    return result;
}

var cached_result: c_int = -1;
var cached_boot_time: Timespec = undefined;

// Return the last boot time in *P_BOOT_TIME: 0 on success, -1 if the
// information is unavailable.  The result is cached.
pub export fn get_boot_time(p_boot_time: *Timespec) c_int {
    if (cached_result < 0) {
        var boot: Timespec = undefined;
        var result: c_int = -1;

        if (utmpBootTime()) |t| {
            boot = t;
            result = 0;
        } else if (linuxBootTimeFallback()) |t| {
            boot = t;
            result = 0;
        } else if (linuxBootTimeFinalFallback()) |t| {
            boot = t;
            result = 0;
        }

        cached_boot_time = boot;
        cached_result = result;
    }

    if (cached_result == 0) {
        p_boot_time.* = cached_boot_time;
        return 0;
    }
    return -1;
}
