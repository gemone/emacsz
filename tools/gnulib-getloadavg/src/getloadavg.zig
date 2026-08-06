// Native Zig implementation of gnulib's lib/getloadavg.c on Linux:
// getloadavg reads the 1/5/15-minute load averages via the sysinfo(2)
// raw syscall and converts the fixed-point loads (1/65536 scale) to
// doubles. Backs `load-average' in src/fns.c. No libc call; errno is
// set on failure as the C code leaves it.

const std = @import("std");
const linux = std.os.linux;
const builtin = @import("builtin");

comptime {
    if (builtin.os.tag != .linux)
        @compileError("gnulib-getloadavg: sysinfo-based implementation is Linux-only for now");
}

extern fn __errno_location() *c_int;

// glibc x86_64 struct sysinfo (112 bytes; loads at offset 8).
const Sysinfo = extern struct {
    uptime: i64,
    loads: [3]u64,
    totalram: u64,
    freeram: u64,
    sharedram: u64,
    bufferram: u64,
    totalswap: u64,
    freeswap: u64,
    procs: u16,
    pad: u16,
    totalhigh: u64,
    freehigh: u64,
    mem_unit: u32,
    _pad: u32,
};

comptime {
    if (@offsetOf(Sysinfo, "loads") != 8)
        @compileError("struct sysinfo layout mismatch: loads expected at offset 8");
    if (@sizeOf(Sysinfo) != 112)
        @compileError("struct sysinfo layout mismatch: expected 112 bytes");
}

// Put the 1-, 5- and 15-minute load averages into LOADAVG[0..2].
// Return the number written (3), or -1 with errno set on failure.
pub export fn getloadavg(loadavg: [*]f64, nelem: c_int) c_int {
    _ = nelem;

    var info: Sysinfo = undefined;
    const raw = linux.syscall1(.sysinfo, @intFromPtr(&info));
    if (@as(isize, @bitCast(raw)) < 0) {
        __errno_location().* = @intCast(-@as(isize, @bitCast(raw)));
        return -1;
    }

    // The gnulib C writes all three entries unconditionally on Linux.
    // Fixed-point loads are scaled by 2^SI_LOAD_SHIFT (65536).
    loadavg[0] = @as(f64, @floatFromInt(info.loads[0])) / 65536.0;
    loadavg[1] = @as(f64, @floatFromInt(info.loads[1])) / 65536.0;
    loadavg[2] = @as(f64, @floatFromInt(info.loads[2])) / 65536.0;
    return 3;
}
