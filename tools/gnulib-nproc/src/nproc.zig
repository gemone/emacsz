// Native Zig implementation of gnulib's lib/nproc.c (num_processors),
// backing `num-processors' in src/process.c. Replicates the C logic:
// the affinity mask for NPROC_CURRENT, the configured/online CPU counts
// (read from sysfs, matching what glibc's sysconf consults), the
// cgroup-v2 CPU quota for the current process, and the OpenMP
// environment variables for NPROC_CURRENT_OVERRIDABLE. No libc call:
// file reads and the scheduler/affinity syscalls go through
// std.os.linux raw syscalls.

const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;

const NPROC_ALL: c_int = 0;
const NPROC_CURRENT: c_int = 1;
const NPROC_CURRENT_OVERRIDABLE: c_int = 2;

const NPROC_MINIMUM: c_ulong = 1;
const ULONG_MAX: c_ulong = ~@as(c_ulong, 0);

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\x0b' or c == '\x0c' or c == '\r';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isWindows(tag: std.Target.Os.Tag) bool {
    return tag == .windows;
}

// Read PATH into BUF via raw syscalls; return the bytes read (empty on
// read failure).
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

fn fileExists(path: [*:0]const u8) bool {
    const rc = linux.openat(linux.AT.FDCWD, path, .{}, 0);
    if (@as(isize, @bitCast(rc)) < 0) return false;
    _ = linux.close(@intCast(rc));
    return true;
}

// Count the CPUs described by a sysfs mask file such as "0-15" or
// "0-3,5-7". Returns 1 when the file is unreadable, mirroring the
// glibc sysconf behavior the C source compensates for (the caller then
// applies the same 1-or-2 affinity quirk).
fn countCpuList(data: []const u8) c_ulong {
    var total: c_ulong = 0;
    var it = std.mem.splitScalar(u8, data, ',');
    while (it.next()) |tok_raw| {
        const tok = std.mem.trim(u8, tok_raw, " \t\r\n");
        if (tok.len == 0) continue;
        if (std.mem.indexOfScalar(u8, tok, '-')) |dash| {
            const a = parseDec(tok[0..dash]) orelse return 0;
            const b = parseDec(tok[dash + 1 ..]) orelse return 0;
            if (b < a) return 0;
            // The C code accumulates in 'unsigned long', which wraps on
            // 32-bit targets; truncate to the same width.
            total +%= @as(c_ulong, @truncate(b - a + 1));
        } else {
            _ = parseDec(tok) orelse return 0;
            total += 1;
        }
    }
    return total;
}

fn parseDec(s: []const u8) ?u64 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    for (s) |c| {
        if (!isDigit(c)) return null;
        const d: u64 = c - '0';
        if (v > (@divTrunc(std.math.maxInt(u64) - d, 10))) return null;
        v = v * 10 + d;
    }
    return v;
}

fn countSysfsCpus(path: [*:0]const u8) c_ulong {
    var buf: [512]u8 = undefined;
    const data = readFileNul(path, &buf) orelse return 1;
    return countCpuList(data);
}

// Number of CPUs available to the current process via the affinity
// mask (sched_getaffinity), 0 when unknown.
fn numProcessorsViaAffinityMask() c_ulong {
    var set: linux.cpu_set_t = undefined;
    const rc = linux.sched_getaffinity(0, @sizeOf(linux.cpu_set_t), &set);
    if (@as(isize, @bitCast(rc)) < 0) return 0;
    const count: c_ulong = linux.CPU_COUNT(set);
    return if (count > 0) count else 0;
}

// Windows: the Win32 APIs gnulib's nproc.c uses. kernel32 is linked
// automatically for Windows targets, so this module stays libc-free
// (the winapi convention keeps Zig from requiring a libc module).
extern "winapi" fn GetSystemInfo(si: *SystemInfo) void;
extern "winapi" fn GetProcessAffinityMask(
    proc: ?*anyopaque,
    process_mask: *usize,
    system_mask: *usize,
) c_int;
extern "winapi" fn GetEnvironmentVariableA(name: [*:0]const u8, buffer: [*]u8, size: u32) u32;

const SystemInfo = extern struct {
    u: extern union {
        dwOemId: u32,
        proc_arch: extern struct { wProcessorArchitecture: u16, wReserved: u16 },
    },
    dwPageSize: u32,
    lpMinimumApplicationAddress: usize,
    lpMaximumApplicationAddress: usize,
    dwActiveProcessorMask: usize,
    dwNumberOfProcessors: u32,
    dwProcessorType: u32,
    dwAllocationGranularity: u32,
    wProcessorLevel: u16,
    wProcessorRevision: u16,
};

comptime {
    // SYSTEM_INFO on x86_64: 4 + 4 + 8 + 8 + 8 + 4 + 4 + 4 + 2 + 2 = 48.
    if (@sizeOf(SystemInfo) != 48)
        @compileError("struct SYSTEM_INFO layout mismatch: expected 48 bytes");
    if (@offsetOf(SystemInfo, "dwNumberOfProcessors") != 32)
        @compileError("struct SYSTEM_INFO layout mismatch: dwNumberOfProcessors expected at 32");
}

// gnulib num_processors_via_affinity_mask on native Windows: the bit
// count of the process affinity mask.
fn numProcessorsViaAffinityMaskWindows() c_ulong {
    // GetCurrentProcess returns the pseudo-handle (HANDLE)-1.
    const current: ?*anyopaque = @ptrFromInt(~@as(usize, 0));
    var process_mask: usize = 0;
    var system_mask: usize = 0;
    if (GetProcessAffinityMask(current, &process_mask, &system_mask) != 0) {
        var mask = process_mask;
        var count: c_ulong = 0;
        while (mask != 0) : (mask >>= 1) {
            if ((mask & 1) != 0) count += 1;
        }
        if (count > 0) return count;
    }
    return 0;
}

// gnulib num_processors_available on native Windows: the affinity count
// for NPROC_CURRENT, GetSystemInfo's count otherwise.
fn numProcessorsAvailableWindows(query: c_int) c_ulong {
    if (query == NPROC_CURRENT) {
        const n = numProcessorsViaAffinityMaskWindows();
        if (n > 0) return n;
    }
    var si: SystemInfo = undefined;
    GetSystemInfo(&si);
    if (si.dwNumberOfProcessors > 0)
        return si.dwNumberOfProcessors;
    return NPROC_MINIMUM;
}

fn numProcessorsAvailable(query: c_int) c_ulong {
    if (comptime isWindows(builtin.os.tag))
        return numProcessorsAvailableWindows(query);
    if (query == NPROC_CURRENT) {
        const n = numProcessorsViaAffinityMask();
        if (n > 0) return n;
        const onln = countSysfsCpus("/sys/devices/system/cpu/online");
        if (onln > 0) return onln;
    } else {
        var n = countSysfsCpus("/sys/devices/system/cpu/possible");
        // glibc's sysconf can return 1 or 2 when sysfs is unavailable;
        // the affinity count is then the better answer.
        if (n == 1 or n == 2) {
            const cur = numProcessorsViaAffinityMask();
            if (cur > n) n = cur;
        }
        if (n > 0) return n;
    }
    return NPROC_MINIMUM;
}

// cgroup-v2 mount point, initially at the usual location, falling back
// to a /proc/mounts scan. Returns a slice into MOUNT_BUF.
fn cgroup2Mount(mount_buf: []u8) ?[]const u8 {
    if (fileExists("/sys/fs/cgroup/cgroup.controllers"))
        return "/sys/fs/cgroup";

    var mbuf: [65536]u8 = undefined;
    const data = readFileNul("/proc/mounts", &mbuf) orelse return null;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        // Fields: device mountpoint fstype options freq passno.
        const dev_end = std.mem.indexOfAny(u8, line, " \t") orelse continue;
        var rest = std.mem.trimStart(u8, line[dev_end..], " \t");
        const mp_end = std.mem.indexOfAny(u8, rest, " \t") orelse continue;
        const mp = rest[0..mp_end];
        rest = std.mem.trimStart(u8, rest[mp_end..], " \t");
        const fs_end = std.mem.indexOfAny(u8, rest, " \t") orelse continue;
        if (std.mem.eql(u8, rest[0..fs_end], "cgroup2")) {
            if (mp.len > mount_buf.len) return null;
            @memcpy(mount_buf[0..mp.len], mp);
            return mount_buf[0..mp.len];
        }
    }
    return null;
}

// Minimum configured cgroup-v2 CPU quota for this process as a CPU
// count (>= 1), or ULONG_MAX when no quota applies.
fn getCgroup2CpuQuota() c_ulong {
    var cpu_quota: c_ulong = ULONG_MAX;

    var cbuf: [2048]u8 = undefined;
    const cgdata = readFileNul("/proc/self/cgroup", &cbuf) orelse return cpu_quota;
    var cgroup: []const u8 = "";
    var found = false;
    var lines = std.mem.splitScalar(u8, cgdata, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "0::/")) {
            cgroup = line[3..];
            found = true;
            break;
        }
    }
    if (!found) return cpu_quota;

    var mount_buf: [512]u8 = undefined;
    const mount = cgroup2Mount(&mount_buf) orelse return cpu_quota;

    var path_buf: [1024]u8 = undefined;
    while (cgroup.len > 0) {
        const path = std.fmt.bufPrintZ(&path_buf, "{s}{s}/cpu.max", .{ mount, cgroup }) catch break;
        var qbuf: [512]u8 = undefined;
        if (readFileNul(path, &qbuf)) |content| {
            if (!std.mem.startsWith(u8, content, "max")) {
                var toks = std.mem.tokenizeAny(u8, content, " \t\r\n");
                const qtok = toks.next();
                const ptok = toks.next();
                if (qtok != null and ptok != null) {
                    const quota = parseLong(qtok.?) orelse null;
                    const period = parseLong(ptok.?) orelse null;
                    if (quota != null and period != null and period.? != 0) {
                        const ncpus: f64 = @as(f64, @floatFromInt(quota.?)) /
                            @as(f64, @floatFromInt(period.?));
                        if (cpu_quota == ULONG_MAX or ncpus < @as(f64, @floatFromInt(cpu_quota))) {
                            const rounded: i64 = @intFromFloat(ncpus + 0.5);
                            cpu_quota = @max(1, @as(c_ulong, @intCast(rounded)));
                            if (cpu_quota == 1) cgroup = "";
                        }
                    }
                }
            }
        }

        // Walk up the nested hierarchy ("/2" -> "/" -> "").
        if (std.mem.lastIndexOfScalar(u8, cgroup, '/')) |last| {
            if (last == 0 and cgroup.len > 1)
                cgroup = "/"
            else
                cgroup = cgroup[0..last];
        } else break;
    }
    return cpu_quota;
}

fn parseLong(s: []const u8) ?i64 {
    var t = s;
    var neg = false;
    if (t.len > 0 and (t[0] == '-' or t[0] == '+')) {
        neg = t[0] == '-';
        t = t[1..];
    }
    if (t.len == 0) return null;
    var v: i64 = 0;
    for (t) |c| {
        if (!isDigit(c)) return null;
        const d: i64 = c - '0';
        if (v > (@divTrunc(std.math.maxInt(i64) - d, 10))) return null;
        v = v * 10 + d;
    }
    return if (neg) -v else v;
}

// cgroup-v2 CPU quota if the current scheduler honors it, else ULONG_MAX.
fn cpuQuota() c_ulong {
    var quota: c_ulong = ULONG_MAX;
    if (builtin.os.tag == .linux) {
        const rc = linux.sched_getscheduler(0);
        const sched = @as(isize, @bitCast(rc));
        // -1 (error), SCHED_FIFO(1), SCHED_RR(2) and SCHED_DEADLINE(6)
        // processes are exempt from the quota.
        if (sched < 0 or sched == 1 or sched == 2 or sched == 6)
            quota = ULONG_MAX
        else
            quota = getCgroup2CpuQuota();
    }
    return quota;
}

fn getenvProc(name: []const u8, buf: []u8) ?[]const u8 {
    const data = readFileNul("/proc/self/environ", buf) orelse return null;
    var it = std.mem.splitScalar(u8, data, 0);
    while (it.next()) |entry| {
        if (std.mem.startsWith(u8, entry, name) and entry.len > name.len and entry[name.len] == '=')
            return entry[name.len + 1 ..];
    }
    return null;
}

// OMP environment lookup: /proc/self/environ on Linux, the Win32
// environment block on Windows (keeping the module libc-free).
fn getenvProcAny(name: []const u8, buf: []u8) ?[]const u8 {
    if (comptime isWindows(builtin.os.tag)) {
        var nbuf: [64]u8 = undefined;
        const z = std.fmt.bufPrintZ(&nbuf, "{s}", .{name}) catch return null;
        const len = GetEnvironmentVariableA(z.ptr, buf.ptr, @intCast(buf.len));
        if (len == 0 or len >= buf.len) return null;
        return buf[0..len];
    }
    return getenvProc(name, buf);
}

// Parse an OpenMP environment value: leading/trailing whitespace
// allowed, positive decimal, or the first value of a nesting level.
fn parseOmpThreads(threads: ?[]const u8) c_ulong {
    const t = threads orelse return 0;
    var i: usize = 0;
    while (i < t.len and isSpace(t[i])) i += 1;
    if (i < t.len and isDigit(t[i])) {
        var val: c_ulong = 0;
        var overflow = false;
        while (i < t.len and isDigit(t[i])) : (i += 1) {
            const d: c_ulong = t[i] - '0';
            if (val > @divTrunc(ULONG_MAX - d, 10)) {
                overflow = true;
                while (i < t.len and isDigit(t[i])) i += 1;
                break;
            }
            val = val * 10 + d;
        }
        if (overflow) val = ULONG_MAX; // strtoul ERANGE saturation
        while (i < t.len and isSpace(t[i])) i += 1;
        if (i == t.len) return val;
        if (t[i] == ',') return val;
    }
    return 0;
}

// Return the number of processors for QUERY (NPROC_ALL, NPROC_CURRENT or
// NPROC_CURRENT_OVERRIDABLE); guaranteed >= 1.
pub export fn num_processors(query_in: c_int) c_ulong {
    var query = query_in;
    var nproc_limit: c_ulong = ULONG_MAX;

    // Honor the OpenMP environment variables.
    if (query == NPROC_CURRENT_OVERRIDABLE) {
        var ebuf: [32768]u8 = undefined;
        const omp_threads = parseOmpThreads(getenvProcAny("OMP_NUM_THREADS", &ebuf));
        const omp_limit_raw = parseOmpThreads(getenvProcAny("OMP_THREAD_LIMIT", &ebuf));
        const omp_env_limit: c_ulong = if (omp_limit_raw == 0) ULONG_MAX else omp_limit_raw;

        if (omp_threads != 0)
            return @min(omp_threads, omp_env_limit);

        nproc_limit = omp_env_limit;
        query = NPROC_CURRENT;
    }

    // Honor any CPU quotas.
    if (query == NPROC_CURRENT and nproc_limit > NPROC_MINIMUM) {
        const quota = cpuQuota();
        nproc_limit = @min(quota, nproc_limit);
    }

    if (nproc_limit > NPROC_MINIMUM) {
        const nprocs = numProcessorsAvailable(query);
        nproc_limit = @min(nprocs, nproc_limit);
    }

    return nproc_limit;
}
