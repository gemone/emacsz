//! config-probe: Zig-native header/function detection for the src/config.h
//! generator.  std.Build has no `cc.has_header`/`has_function` probe API
//! (unlike Meson), so these load-bearing, host-varying knobs are detected
//! with `zig cc` compile probes run from a cached Run step -- the same
//! pattern as the gen-config tool.
//!
//! LIBRARIES ARE NOT probed here: linking is declared natively via
//! `exe.linkSystemLibrary(name, .{})`, and Zig's compiler driver already
//! resolves system libraries (pkg-config → vcpkg → plain `-l` search
//! paths), so a library present without its .pc file (e.g. libgpm on a
//! /usr/lib64 host) links fine with no probe.  The committed
//! config_values.txt HAVE_* library knobs stay authoritative and agree
//! with what linkSystemLibrary resolves.
//!
//! Two probe kinds, mirroring configure's AC_CHECK_HEADERS /
//! AC_CHECK_FUNCS:
//!
//!   (1) headers     — `zig cc -c` compile of `#include <h>`
//!   (2) functions   — `zig cc -c` compile of a header + call
//!
//! Every probe emits a `NAME=value` override line on STDOUT in the same
//! format gen-config consumes (bare NAME = undef, NAME=1 = define): a
//! present probe writes `NAME=1`, an absent one writes the bare `NAME`.
//!
//! Usage: config-probe <zig-exe> [pkg-config-exe (ignored)]
//! cwd must be a writable directory: probe sources are staged under
//! `.zig-cache/config-probe/`.

const std = @import("std");

// ---- Headers probed via a compile of `#include <h>` -----------------------
const Header = struct { header: []const u8, knob: []const u8 };
const headers = [_]Header{
    .{ .header = "execinfo.h", .knob = "HAVE_EXECINFO_H" },
    .{ .header = "mntent.h", .knob = "HAVE_MNTENT_H" },
    .{ .header = "malloc.h", .knob = "HAVE_MALLOC_H" },
    .{ .header = "stdio_ext.h", .knob = "HAVE_STDIO_EXT_H" },
    .{ .header = "sys/sysinfo.h", .knob = "HAVE_SYS_SYSINFO_H" },
    .{ .header = "sys/soundcard.h", .knob = "HAVE_SYS_SOUNDCARD_H" },
    .{ .header = "machine/soundcard.h", .knob = "HAVE_MACHINE_SOUNDCARD_H" },
    .{ .header = "soundcard.h", .knob = "HAVE_SOUNDCARD_H" },
    .{ .header = "sys/inotify.h", .knob = "HAVE_INOTIFY" },
    .{ .header = "pty.h", .knob = "HAVE_PTY_H" },
    .{ .header = "net/if.h", .knob = "HAVE_NET_IF_H" },
    .{ .header = "ifaddrs.h", .knob = "HAVE_IFADDRS_H" },
    .{ .header = "sys/un.h", .knob = "HAVE_SYS_UN_H" },
    .{ .header = "sys/utsname.h", .knob = "HAVE_SYS_UTSNAME_H" },
    .{ .header = "sys/random.h", .knob = "HAVE_SYS_RANDOM_H" },
    .{ .header = "linux/fs.h", .knob = "HAVE_LINUX_FS_H" },
    .{ .header = "linux/filter.h", .knob = "HAVE_LINUX_FILTER_H" },
    .{ .header = "linux/seccomp.h", .knob = "HAVE_LINUX_SECCOMP_H" },
    .{ .header = "pthread.h", .knob = "HAVE_PTHREAD_H" },
};

// ---- (3) Functions probed via a compile of a header + call ---------------
// Each snippet is compiled with -D_GNU_SOURCE (some declarations need it,
// e.g. pipe2/accept4/getrandom) and -std=gnu2x, mirroring the build flags.
const Function = struct { knob: []const u8, src: []const u8 };
const functions = [_]Function{
    .{ .knob = "HAVE_GETRANDOM", .src = "#include <sys/random.h>\nvoid f(void){char b; (void)getrandom(&b, 1, 0);}" },
    .{ .knob = "HAVE_PIPE2", .src = "#include <unistd.h>\nvoid f(void){(void)pipe2(0, 0);}" },
    .{ .knob = "HAVE_ACCEPT4", .src = "#include <sys/socket.h>\nvoid f(void){(void)accept4(0, 0, 0, 0);}" },
    .{ .knob = "HAVE_GETADDRINFO_A", .src = "#include <netdb.h>\nvoid f(void){struct gaicb x[1]; struct sigevent s; (void)getaddrinfo_a(GAI_NOWAIT, x, 0, &s);}" },
    .{ .knob = "HAVE_SIGDESCR_NP", .src = "#include <string.h>\nvoid f(void){(void)sigdescr_np(0);}" },
    .{ .knob = "HAVE_MALLOC_TRIM", .src = "#include <malloc.h>\nvoid f(void){(void)malloc_trim(0);}" },
    .{ .knob = "HAVE_RENAMEAT2", .src = "#include <stdio.h>\nvoid f(void){(void)renameat2(0, \"\", 0, \"\", RENAME_NOREPLACE);}" },
    .{ .knob = "HAVE_TIMERFD", .src = "#include <sys/timerfd.h>\nvoid f(void){(void)timerfd_create(0, 0);}" },
    .{ .knob = "HAVE_TIMER_SETTIME", .src = "#include <time.h>\nvoid f(void){timer_t t; struct itimerspec s; (void)timer_settime(t, 0, &s, 0);}" },
    .{ .knob = "HAVE_GET_CURRENT_DIR_NAME", .src = "#include <unistd.h>\nvoid f(void){(void)get_current_dir_name();}" },
    .{ .knob = "HAVE_GETPT", .src = "#include <stdlib.h>\nvoid f(void){(void)getpt();}" },
    .{ .knob = "HAVE_MEMPCPY", .src = "#include <string.h>\nvoid f(void){char b[1]; (void)mempcpy(b, b, 1);}" },
    .{ .knob = "HAVE_MEMRCHR", .src = "#include <string.h>\nvoid f(void){char b[1]; (void)memrchr(b, 0, 1);}" },
    .{ .knob = "HAVE_LINUX_SYSINFO", .src = "#include <sys/sysinfo.h>\nvoid f(void){struct sysinfo s; (void)sysinfo(&s);}" },
    .{ .knob = "HAVE_GETPWENT", .src = "#include <pwd.h>\nvoid f(void){(void)getpwent();}" },
    .{ .knob = "HAVE_GETGRENT", .src = "#include <grp.h>\nvoid f(void){(void)getgrent();}" },
    .{ .knob = "HAVE_GETRUSAGE", .src = "#include <sys/resource.h>\nvoid f(void){struct rusage r; (void)getrusage(0, &r);}" },
    .{ .knob = "HAVE_GETIFADDRS", .src = "#include <ifaddrs.h>\nvoid f(void){struct ifaddrs *x; (void)getifaddrs(&x);}" },
    .{ .knob = "HAVE_MMAP", .src = "#include <sys/mman.h>\nvoid f(void){(void)mmap(0, 1, PROT_READ, MAP_PRIVATE, -1, 0);}" },
    .{ .knob = "HAVE_MEMMEM", .src = "#include <string.h>\nvoid f(void){char b[1]; (void)memmem(b, 1, b, 1);}" },
    .{ .knob = "HAVE_SIGSETJMP", .src = "#include <setjmp.h>\nvoid f(void){sigjmp_buf b; if (sigsetjmp(b, 0)) return;}" },
    .{ .knob = "HAVE__SETJMP", .src = "#include <setjmp.h>\nvoid f(void){jmp_buf b; if (_setjmp(b)) return;}" },
    .{ .knob = "HAVE_INOTIFY_INIT", .src = "#include <sys/inotify.h>\nvoid f(void){(void)inotify_init();}" },
    .{ .knob = "HAVE_INOTIFY_INIT1", .src = "#include <sys/inotify.h>\nvoid f(void){(void)inotify_init1(0);}" },
    .{ .knob = "HAVE_LANGINFO__NL_PAPER_WIDTH", .src = "#include <langinfo.h>\nvoid f(void){(void)_NL_PAPER_WIDTH;}" },
};

const PROBE_SUBDIR = ".zig-cache/config-probe/";

fn appendLine(gpa: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, present: bool) !void {
    if (present) {
        const line = try std.fmt.allocPrint(gpa, "{s}=1\n", .{name});
        defer gpa.free(line);
        try out.appendSlice(gpa, line);
    } else {
        try out.appendSlice(gpa, name);
        try out.append(gpa, '\n');
    }
}

fn runStatus(
    io: std.Io,
    gpa: std.mem.Allocator,
    env_map: *std.process.Environ.Map,
    argv: []const []const u8,
    quiet: bool,
) !u8 {
    const res = std.process.run(gpa, io, .{
        .argv = argv,
        .environ_map = env_map,
        .stdout_limit = .limited(1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch |err| return err;
    if (!quiet and res.term != .exited) {
        std.debug.print("config-probe: {s}: {any}\n", .{ argv[0], res.term });
        return 255;
    }
    if (res.term != .exited) return 255;
    return res.term.exited;
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    // Seed the Io environ snapshot with the parent environment (see
    // zeln-compile main.zig: an empty snapshot breaks argv[0] PATH lookup
    // on macOS/Homebrew).
    var io_threaded: std.Io.Threaded = .init(gpa, .{ .environ = minimal.environ });
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();
    var env_map = try std.process.Environ.createMap(minimal.environ, gpa);
    defer env_map.deinit();

    var arg_it = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer arg_it.deinit();
    _ = arg_it.next(); // argv[0]
    const zig_exe = arg_it.next() orelse "zig";
    _ = arg_it.next() orelse null; // argv[2]: historical pkg-config path (unused)

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);

    // ---- headers/functions via `zig cc` compile probes ----
    // Stage probe sources under .zig-cache/config-probe/ and compile each.
    try cwd.createDirPath(io, PROBE_SUBDIR);
    var zig_ok = true;
    const status = runStatus(io, gpa, &env_map, &.{ zig_exe, "version" }, true) catch |err| blk: {
        std.debug.print("config-probe: zig unavailable ({s}); skipping header/function probes\n", .{@errorName(err)});
        break :blk 255;
    };
    if (status != 0) {
        std.debug.print("config-probe: zig unusable; skipping header/function probes\n", .{});
        zig_ok = false;
    }
    if (zig_ok) {
        var probe_idx: usize = 0;
        var scratch: [128]u8 = undefined;
        for (headers) |h| {
            const src = try std.fmt.allocPrint(gpa, "#define _GNU_SOURCE\n#include <{s}>\nint probe(void){{return 0;}}\n", .{h.header});
            defer gpa.free(src);
            const present = try compileProbe(gpa, io, &env_map, &cwd, zig_exe, src, &scratch, &probe_idx);
            try appendLine(gpa, &out, h.knob, present);
        }
        for (functions) |f| {
            const src = try std.fmt.allocPrint(gpa, "#define _GNU_SOURCE\n{s}\n", .{f.src});
            defer gpa.free(src);
            const present = try compileProbe(gpa, io, &env_map, &cwd, zig_exe, src, &scratch, &probe_idx);
            try appendLine(gpa, &out, f.knob, present);
        }
    }

    const stdout_file = std.Io.File.stdout();
    try stdout_file.writeStreamingAll(io, out.items);
}

// Compile a C snippet with `zig cc`; returns true when the compile
// succeeds (header/declaration present).  `-c -o /dev/null` (NOT
// -fsyntax-only: zig cc does not support that flag) discards the object.
fn compileProbe(
    gpa: std.mem.Allocator,
    io: std.Io,
    env_map: *std.process.Environ.Map,
    cwd: *const std.Io.Dir,
    zig_exe: []const u8,
    src: []const u8,
    scratch: *[128]u8,
    probe_idx: *usize,
) !bool {
    const idx = probe_idx.*;
    probe_idx.* += 1;
    // Per-process staging token: the address of probe_idx differs across
    // processes (ASLR), so concurrent `zig build` invocations sharing the
    // cache cannot interleave writes to the same fixed probe file.
    const seed: usize = @intFromPtr(probe_idx) & 0xffff;
    const name = try std.fmt.bufPrint(scratch, "{s}p{x:0>4}_{d}.c", .{ PROBE_SUBDIR, seed, idx });
    try cwd.writeFile(io, .{ .sub_path = name, .data = src });
    const argv = [_][]const u8{
        zig_exe, "cc", "-std=gnu2x", "-c", "-o", "/dev/null", name,
    };
    const status = runStatus(io, gpa, env_map, &argv, true) catch return false;
    return status == 0;
}
