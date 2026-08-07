// Generate src/config.h from the zig-authored template + values. Native Zig
// replacement for the former inline build.zig logic -- mirrors the
// substitution byte-for-byte so the generated config.h stays identical.
//
// Reads `src/config.h.in` (guard + _GNU_SOURCE + every `#undef NAME` from
// config.in + conf_post) and `src/config_values.txt` (`NAME=value`, or bare
// `NAME` for undef), builds a name -> value map, and substitutes each
// `#undef NAME` line with its value (or `/* #undef NAME */`) -- the macro
// processing autoconf's config.status does. Text-based, so every value type
// (ints, strings, char literals, /**/) is handled uniformly.
//
// Run with cwd = repo root; the template and answer files are passed as
// argv[1] and argv[2] (relative to cwd) so the build tracks their content.
// An optional argv[3] target tag ("linux", "musl", "windows") applies
// per-target overrides on top of the committed Linux values, so cross
// builds get a config matching what they can actually link. The
// generated config.h body is written to STDOUT; the consumer captures it
// via captureStdOut and lands it in the zig-cache.
const std = @import("std");

// Optional system-library features disabled for targets where the
// library is unavailable or not part of the milestone build. The
// bignum rewrite already removed the gmp dependency on every target.
const Override = struct { name: []const u8, value: []const u8 = "" };

const musl_overrides: []const Override = &.{
    .{ .name = "HAVE_GNUTLS" },
    .{ .name = "HAVE_LIBXML2" },
    .{ .name = "HAVE_LCMS2" },
    .{ .name = "HAVE_SQLITE3" },
    .{ .name = "HAVE_TREE_SITTER" },
    .{ .name = "HAVE_ALSA" },
    .{ .name = "HAVE_GPM" },
    .{ .name = "HAVE_DBUS" },
    .{ .name = "HAVE_ZLIB" },
    // glibc-only features absent from musl; TERMINFO is dropped so
    // src/termcap.c (compiled via TERMCAP_OBJ) supplies the terminal
    // capabilities instead of ncurses; ACLs stay with the Zig package.
    .{ .name = "TERMINFO" },
    .{ .name = "TERMINFO_DEFINES_BC" },
    .{ .name = "USE_ACL" },
    .{ .name = "HAVE_ACL_GET_FILE" },
    .{ .name = "HAVE_EXECINFO_H" },
    .{ .name = "HAVE_GETADDRINFO_A" },
    .{ .name = "HAVE_MALLOC_TRIM" },
    .{ .name = "HAVE_RENAMEAT2" },
    .{ .name = "HAVE_LANGINFO__NL_PAPER_WIDTH" },
    .{ .name = "HAVE_SIGDESCR_NP" },
};

// macOS lacks the *_unlocked stdio family (Apple's libc never exported
// them), so the make-docfile HOST config must not carry the
// HAVE_DECL_*_UNLOCKED values that the committed Linux config derived
// from glibc.  Only the host tool needs this tag; the macOS temacs
// target keeps the Linux-derived values (same as today).
const macos_overrides: []const Override = &.{
    .{ .name = "HAVE_DECL_GETC_UNLOCKED" },
    .{ .name = "HAVE_DECL_CLEARERR_UNLOCKED" },
    .{ .name = "HAVE_DECL_FEOF_UNLOCKED" },
    .{ .name = "HAVE_DECL_FERROR_UNLOCKED" },
    .{ .name = "HAVE_DECL_FFLUSH_UNLOCKED" },
    .{ .name = "HAVE_DECL_FGETS_UNLOCKED" },
    .{ .name = "HAVE_DECL_FILENO_UNLOCKED" },
    .{ .name = "HAVE_DECL_FPUTC_UNLOCKED" },
    .{ .name = "HAVE_DECL_FPUTS_UNLOCKED" },
    .{ .name = "HAVE_DECL_FREAD_UNLOCKED" },
    .{ .name = "HAVE_DECL_FWRITE_UNLOCKED" },
    .{ .name = "HAVE_DECL_GETCHAR_UNLOCKED" },
    .{ .name = "HAVE_DECL_PUTCHAR_UNLOCKED" },
    .{ .name = "HAVE_DECL_PUTC_UNLOCKED" },
    // Darwin struct stat uses st_atimespec/st_mtimespec/st_ctimespec
    // instead of glibc's st_atim/st_mtim/st_ctim, so flip the knob the
    // committed stat-time.h switches on.
    .{ .name = "HAVE_STRUCT_STAT_ST_ATIM_TV_NSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_ATIMESPEC_TV_NSEC", .value = "1" },
    // DARWIN_OS selects the Mach-O subr section (__DATA,subrs) and the
    // darwin-specific code paths; the committed Linux values enable
    // Linux-only subsystems (GPM console mouse, tree-sitter, the
    // copy_file_range wrapper) and glibc's <malloc.h>.
    .{ .name = "DARWIN_OS", .value = "1" },
    .{ .name = "HAVE_GPM" },
    .{ .name = "HAVE_TREE_SITTER" },
    .{ .name = "HAVE_COPY_FILE_RANGE" },
    .{ .name = "HAVE_MALLOC_H" },
    .{ .name = "HAVE_TIMERFD" },
    .{ .name = "HAVE_STDIO_EXT_H" },
    .{ .name = "HAVE_SYS_SYSINFO_H" },
    .{ .name = "HAVE_LINUX_SECCOMP_H" },
    .{ .name = "HAVE_LINUX_FS_H" },
    .{ .name = "HAVE_MEMPCPY" },
    .{ .name = "HAVE_MEMRCHR" },
    .{ .name = "HAVE_LANGINFO__NL_PAPER_WIDTH" },
    .{ .name = "HAVE_ENVIRON_DECL" },
};

// Windows additionally drops the POSIX-only subsystems that need mingw
// ports of the same libraries, and switches the config to the native
// Windows system (WINDOWSNT pulls in src/ms-w32.h via conf_post.h). The
// HAVE_* values below mirror what a --with-w32 configure run yields:
// w32.c provides fstatat/lstat/getuid/etc., lib/getrandom.c provides
// getrandom over BCryptGenRandom, and the mingw toolchain supplies
// UINTPTR_WIDTH/UCHAR_WIDTH from the C23 <stdint.h>/<limits.h> only on
// glibc, so they are pinned here. The HAVE_DECL_* undefs let
// src/conf_post.h declare getdelim/getline and keep lib/getdelim.c on
// the plain getc path (mingw has no getc_unlocked).
const windows_overrides: []const Override = &.{
    .{ .name = "HAVE_GNUTLS" },
    .{ .name = "HAVE_LIBXML2" },
    .{ .name = "HAVE_LCMS2" },
    .{ .name = "HAVE_SQLITE3" },
    .{ .name = "HAVE_TREE_SITTER" },
    .{ .name = "HAVE_ALSA" },
    .{ .name = "HAVE_GPM" },
    .{ .name = "HAVE_DBUS" },
    .{ .name = "HAVE_ZLIB" },
    .{ .name = "WINDOWSNT", .value = "1" },
    .{ .name = "DOS_NT", .value = "1" },
    .{ .name = "HAVE_BCRYPT_H", .value = "1" },
    .{ .name = "HAVE_LIB_BCRYPT", .value = "1" },
    .{ .name = "USE_UNLOCKED_IO" },
    .{ .name = "HAVE_STACK_OVERFLOW_HANDLING" },
    .{ .name = "HAVE_TIMERFD" },
    .{ .name = "HAVE__SETJMP" },
    .{ .name = "HAVE_SIGSETJMP" },
    .{ .name = "HAVE_MMAP" },
    .{ .name = "HAVE_MEMMEM" },
    .{ .name = "HAVE_ACCEPT4" },
    .{ .name = "HAVE_ALIGNED_ALLOC" },
    .{ .name = "HAVE_MALLOC_TRIM" },
    .{ .name = "HAVE_GET_CURRENT_DIR_NAME" },
    .{ .name = "HAVE_GETADDRINFO_A" },
    .{ .name = "HAVE_GETIFADDRS" },
    .{ .name = "HAVE_GETRUSAGE" },
    .{ .name = "HAVE_NET_IF_H" },
    .{ .name = "HAVE_IFADDRS_H" },
    .{ .name = "HAVE_SYS_PERSONALITY_H" },
    .{ .name = "HAVE_PERSONALITY_ADDR_NO_RANDOMIZE" },
    .{ .name = "HAVE_SYNC" },
    .{ .name = "HAVE_STRSIGNAL" },
    .{ .name = "HAVE_LINUX_SYSINFO" },
    .{ .name = "HAVE_SYS_UTSNAME_H" },
    .{ .name = "HAVE_LINUX_FS_H" },
    .{ .name = "HAVE_SYS_UN_H" },
    .{ .name = "HAVE_STRUCT_UNIPAIR_UNICODE" },
    .{ .name = "HAVE_POSIX_SPAWN" },
    .{ .name = "HAVE_POSIX_SPAWN_FILE_ACTIONS_ADDCHDIR_NP" },
    .{ .name = "HAVE_DECL_POSIX_SPAWN_SETSID" },
    .{ .name = "HAVE_TM_GMTOFF" },
    .{ .name = "HAVE_GRANTPT" },
    .{ .name = "HAVE_POSIX_OPENPT" },
    .{ .name = "HAVE_PTYS" },
    .{ .name = "GNU_LINUX" },
    .{ .name = "UNIX98_PTYS" },
    .{ .name = "HAVE_PTY_H" },
    .{ .name = "HAVE_STDIO_EXT_H" },
    .{ .name = "HAVE_DECL___FPENDING" },
    .{ .name = "USABLE_SIGIO" },
    .{ .name = "SIGNALS_VIA_CHARACTERS" },
    .{ .name = "HAVE_GETPWENT" },
    .{ .name = "HAVE_ENDPWENT" },
    .{ .name = "HAVE_GETGRENT" },
    .{ .name = "HAVE_ENDGRENT" },
    .{ .name = "HAVE_PROCFS" },
    .{ .name = "HAVE_INOTIFY" },
    .{ .name = "HAVE_PTHREAD" },
    .{ .name = "HAVE_PTHREAD_H" },
    .{ .name = "HAVE_PTHREAD_SETNAME_NP" },
    .{ .name = "HAVE_PTHREAD_SETNAME_NP_1ARG" },
    .{ .name = "HAVE_PTHREAD_SETNAME_NP_3ARG" },
    .{ .name = "HAVE_PTHREAD_SET_NAME_NP" },
    .{ .name = "HAVE_PTHREAD_SIGMASK" },
    .{ .name = "HAVE_STRUCT_DIRENT_D_TYPE" },
    .{ .name = "HAVE_LINUX_SECCOMP_H" },
    .{ .name = "HAVE_LINUX_FILTER_H" },
    .{ .name = "HAVE_DECL_SECCOMP_SET_MODE_FILTER" },
    .{ .name = "HAVE_DECL_SECCOMP_FILTER_FLAG_TSYNC" },
    .{ .name = "HAVE_STRUCT_TM_TM_ZONE" },
    .{ .name = "HAVE_STRUCT_TM_TM_GMTOFF" },
    .{ .name = "HAVE_STRUCT_STAT_ST_ATIM_TV_NSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_ATIMESPEC_TV_NSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_ATIMENSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_ATIM_ST__TIM_TV_NSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_BIRTHTIMESPEC_TV_NSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_BIRTHTIM_TV_NSEC" },
    .{ .name = "HAVE_STRUCT_STAT_ST_BIRTHTIMENSEC" },
    .{ .name = "TYPEOF_STRUCT_STAT_ST_ATIM_IS_STRUCT_TIMESPEC" },
    .{ .name = "HAVE_DECL_GETC_UNLOCKED" },
    .{ .name = "HAVE_DECL_GETDELIM" },
    .{ .name = "HAVE_DECL_GETLINE" },
    .{ .name = "HAVE_DECL_CLEARERR_UNLOCKED" },
    .{ .name = "HAVE_DECL_FEOF_UNLOCKED" },
    .{ .name = "HAVE_DECL_FERROR_UNLOCKED" },
    .{ .name = "HAVE_DECL_FFLUSH_UNLOCKED" },
    .{ .name = "HAVE_DECL_FGETS_UNLOCKED" },
    .{ .name = "HAVE_DECL_FILENO_UNLOCKED" },
    .{ .name = "HAVE_DECL_FPUTC_UNLOCKED" },
    .{ .name = "HAVE_DECL_FPUTS_UNLOCKED" },
    .{ .name = "HAVE_DECL_FREAD_UNLOCKED" },
    .{ .name = "HAVE_DECL_FWRITE_UNLOCKED" },
    .{ .name = "HAVE_DECL_GETCHAR_UNLOCKED" },
    .{ .name = "HAVE_DECL_PUTCHAR_UNLOCKED" },
    .{ .name = "HAVE_DECL_PUTC_UNLOCKED" },
    .{ .name = "HAVE_STDBIT_H" },
    .{ .name = "HAVE_SYS_RANDOM_H" },
    .{ .name = "HAVE_EXECINFO_H" },
};

pub fn main(minimal: std.process.Init.Minimal) !void {
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();
    const a = std.heap.smp_allocator;
    const cwd = std.Io.Dir.cwd();

    var it = try std.process.Args.Iterator.initAllocator(minimal.args, a);
    defer it.deinit();
    _ = it.next(); // program name
    const template_path = it.next() orelse return error.MissingTemplateArg;
    const values_path = it.next() orelse return error.MissingValuesArg;
    const target_tag = it.next();

    const config_h_in_text = try cwd.readFileAlloc(
        io,
        template_path,
        a,
        .limited(4 * 1024 * 1024),
    );
    const config_values_text = try cwd.readFileAlloc(
        io,
        values_path,
        a,
        .limited(4 * 1024 * 1024),
    );

    var config_values = std.StringHashMap([]const u8).init(a);
    defer config_values.deinit();
    {
        var vit = std.mem.splitScalar(u8, config_values_text, '\n');
        while (vit.next()) |vline| {
            if (vline.len == 0) continue;
            if (std.mem.indexOfScalar(u8, vline, '=')) |eq| {
                try config_values.put(vline[0..eq], vline[eq + 1 ..]);
            } else {
                try config_values.put(vline, "");
            }
        }
    }

    if (target_tag) |tag| {
        const overrides = if (std.mem.eql(u8, tag, "musl"))
            musl_overrides
        else if (std.mem.eql(u8, tag, "windows"))
            windows_overrides
        else if (std.mem.eql(u8, tag, "macos"))
            macos_overrides
        else
            null;
        if (overrides) |list| {
            for (list) |ov| {
                try config_values.put(ov.name, ov.value);
            }
        }
    }

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(a);
    {
        var tit = std.mem.splitScalar(u8, config_h_in_text, '\n');
        var first = true;
        while (tit.next()) |tline| {
            if (!first) try buf.append(a, '\n');
            first = false;
            if (std.mem.startsWith(u8, tline, "#undef ")) {
                const name = std.mem.trim(u8, tline["#undef ".len..], " \t\r");
                const v = config_values.get(name);
                const has_val = v != null and v.?.len > 0;
                const rendered = if (has_val)
                    try std.fmt.allocPrint(a, "#define {s} {s}", .{ name, v.? })
                else
                    try std.fmt.allocPrint(a, "/* #undef {s} */", .{name});
                defer a.free(rendered);
                try buf.appendSlice(a, rendered);
            } else {
                try buf.appendSlice(a, tline);
            }
        }
    }

    const stdout_file = std.Io.File.stdout();
    try stdout_file.writeStreamingAll(io, buf.items);
}
