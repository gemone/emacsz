const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // `-Dshow-sources=true`: print the parsed base/lib source lists to stderr
    // (two counts followed by the lists) and exit without installing artifacts.
    // Used to verify the build-time parsers against the legacy build-config/*.zig.
    const show_sources = b.option(bool, "show-sources", "Print parsed base/lib source lists and exit") orelse false;

    // Build-time file interface (single-threaded, synchronous). Used to parse
    // src/Makefile.in and glob lib/*.c so that `zig build` no longer requires a
    // pre-generated build-config/ directory (kills the comptime @import
    // circularity and the manual source-list extraction step).
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();

    const base_sources = parseBaseSources(b, io) catch @panic(
        "build.zig: failed to parse src/Makefile.in base_obj",
    );
    const libgnu_sources = parseLibgnuSources(b, io) catch @panic(
        "build.zig: failed to glob lib/*.c",
    );

    if (show_sources) {
        std.debug.print("BASE_COUNT: {d}\n", .{base_sources.len});
        std.debug.print("BASE:\n", .{});
        for (base_sources) |s| std.debug.print("{s}\n", .{s});
        std.debug.print("LIB_COUNT: {d}\n", .{libgnu_sources.len});
        std.debug.print("LIB:\n", .{});
        for (libgnu_sources) |s| std.debug.print("{s}\n", .{s});
        return;
    }

    // Generate Gnulib .gl.h headers before compilation
    const generate_headers = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        \\if [ -f build-aux/generate-gl-headers.sh ]; then
        \\  ./build-aux/generate-gl-headers.sh
        \\else
        \\  echo "Warning: generate-gl-headers.sh not found, skipping..."
        \\fi
    });
    const generate_step = b.step("generate-headers", "Generate Gnulib .gl.h headers");
    generate_step.dependOn(&generate_headers.step);

    // Create temacs executable
    const exe = b.addExecutable(.{
        .name = "temacs",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // Determine if we're building for Unix-like systems
    const is_windows = target.result.os.tag == .windows;

    // Add base C sources with proper flags
    // Note: build-config must come before src to override epaths.h
    if (!is_windows) {
        // Unix-like systems (macOS, Linux) - with libxml2 include path
        const base_flags = &[_][]const u8{
            "-std=gnu2x",  // Allow C23 features like _Static_assert without message
            "-fno-common",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
            "-Ibuild-config",  // Before src to override epaths.h
            "-Isrc",
            "-Ilib",
            "-Ilib/malloc",  // Gnulib generated headers
            "-I/usr/include",
            "-I/usr/include/libxml2",  // libxml2 headers
        };

        for (base_sources) |src| {
            exe.root_module.addCSourceFile(.{
                .file = b.path(src),
                .flags = base_flags,
            });
        }

        // Add platform-specific sources
        // kqueue.c is BSD/macOS-specific (HAVE_KQUEUE)
        const is_macos = target.result.os.tag == .macos;
        const is_bsd = target.result.os.tag == .freebsd or
                       target.result.os.tag == .openbsd or
                       target.result.os.tag == .netbsd or
                       target.result.os.tag == .dragonfly;

        if (is_macos or is_bsd) {
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/kqueue.c"),
                .flags = base_flags,
            });
        }

        // Add Gnulib sources
        const libgnu_flags = &[_][]const u8{
            "-std=gnu2x",
            "-fno-common",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
            "-Ibuild-config",
            "-Isrc",
            "-Ilib",
            "-Ilib/malloc",  // Gnulib generated headers
            "-I/usr/include",
            "-I/usr/include/libxml2",
        };

        for (libgnu_sources) |src| {
            exe.root_module.addCSourceFile(.{
                .file = b.path(src),
                .flags = libgnu_flags,
            });
        }
    } else {
        // Windows - without libxml2 include path
        const base_flags = &[_][]const u8{
            "-std=gnu2x",
            "-fno-common",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
            "-Ibuild-config",
            "-Isrc",
            "-Ilib",
        };

        for (base_sources) |src| {
            exe.root_module.addCSourceFile(.{
                .file = b.path(src),
                .flags = base_flags,
            });
        }

        // Add Gnulib sources
        const libgnu_flags = &[_][]const u8{
            "-std=gnu2x",
            "-fno-common",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
            "-Ibuild-config",
            "-Isrc",
            "-Ilib",
        };

        for (libgnu_sources) |src| {
            exe.root_module.addCSourceFile(.{
                .file = b.path(src),
                .flags = libgnu_flags,
            });
        }
    }

    // Link system libraries (phase 2: based on src/Makefile)
    exe.root_module.linkSystemLibrary("m", .{});

    if (!is_windows) {
        // Core libraries
        exe.root_module.linkSystemLibrary("gmp", .{});
        exe.root_module.linkSystemLibrary("gnutls", .{});

        // Terminal support
        exe.root_module.linkSystemLibrary("ncurses", .{});

        // XML parsing
        exe.root_module.linkSystemLibrary("xml2", .{});

        // Compression
        exe.root_module.linkSystemLibrary("z", .{});

        // Color management
        exe.root_module.linkSystemLibrary("lcms2", .{});

        // SQLite database
        exe.root_module.linkSystemLibrary("sqlite3", .{});

        // ACL support (Linux only). Link libacl: config.h defines HAVE_ACL_*
        // and the library is installed. Do NOT link libselinux: config.h has
        // HAVE_LIBSELINUX undefined and the library is absent on the host, so
        // linking it only breaks the build.
        if (target.result.os.tag == .linux) {
            exe.root_module.linkSystemLibrary("acl", .{});
        }
    }

    // Install the executable
    b.installArtifact(exe);

    // Make the executable compilation depend on header generation
    exe.step.dependOn(&generate_headers.step);

    // Test step
    const test_step = b.step("test", "Run all tests");
    const run_tests = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        \\if [ -f run-zig-tests.sh ]; then
        \\  sh run-zig-tests.sh
        \\else
        \\  echo "No test script found, skipping"
        \\fi
    });
    test_step.dependOn(&run_tests.step);

    // Help step
    const help_step = b.step("help", "Show build information");
    const help_cmd = b.addSystemCommand(&[_][]const u8{
        "echo",
        \\Emacs Zig Native Build System - Phase 2
        \\=======================================
        \\
        \\Available steps:
        \\  zig build      - Build temacs
        \\  zig build test  - Run all tests
        \\  zig build help  - Show this message
        \\
        \\Status: Phase 2 In Progress
        \\  - Metadata extraction: ✓ Complete
        \\  - Source file organization: ✓ Complete
        \\  - Compilation: ✓ Complete
    });
    help_step.dependOn(&help_cmd.step);
}

/// Parse the `base_obj =` block from src/Makefile.in (lines ~450-469) into the
/// list of C sources for the TUI-only build. Mirrors the former shell-based
/// extractor: skip $(... ) variables (except $(CM_OBJ) -> cm.c), map
/// foo.o -> src/foo.c, then append the TUI extras (termcap.c, tparam.c) that
/// autotools pulls in via TERMCAP_OBJ. Result is sorted + de-duped.
fn parseBaseSources(b: *std.Build, io: std.Io) ![]const []const u8 {
    const a = b.allocator;
    const content = try std.Io.Dir.cwd().readFileAlloc(
        io,
        "src/Makefile.in",
        a,
        .limited(8 * 1024 * 1024),
    );

    var list: std.ArrayList([]const u8) = .empty;
    var seen = std.StringHashMap(void).init(a);
    defer seen.deinit();

    const marker = "base_obj = ";
    const start_idx = std.mem.indexOf(u8, content, marker) orelse return error.BaseObjNotFound;
    const pos = start_idx + marker.len;

    // The block spans continuation lines (each ending in '\') until a line that
    // does NOT end in '\'. The next Makefile assignment (doc_obj) is NOT part of
    // the block, so this naturally stops at the right place.
    var block_end: usize = content.len;
    var line_start: usize = pos;
    while (true) {
        const nl_idx = std.mem.indexOfScalarPos(u8, content, line_start, '\n') orelse {
            block_end = content.len;
            break;
        };
        const trimmed = std.mem.trimEnd(u8, content[line_start..nl_idx], " \t\r");
        if (std.mem.endsWith(u8, trimmed, "\\")) {
            line_start = nl_idx + 1;
        } else {
            block_end = nl_idx;
            break;
        }
    }

    const block = content[pos..block_end];
    var it = std.mem.tokenizeAny(u8, block, " \t\r\n\\");
    while (it.next()) |tok| {
        const path: []const u8 = if (std.mem.eql(u8, tok, "$(CM_OBJ)"))
            "src/cm.c"
        else if (std.mem.startsWith(u8, tok, "$("))
            continue
        else if (std.mem.endsWith(u8, tok, ".o"))
            try std.fmt.allocPrint(a, "src/{s}.c", .{tok[0 .. tok.len - 2]})
        else
            continue;

        const gop = try seen.getOrPut(path);
        if (!gop.found_existing) try list.append(a, path);
    }

    // TUI extras: termcap.c + tparam.c come from TERMCAP_OBJ in autotools and
    // are not present in base_obj. kqueue.c is intentionally NOT added here
    // (BSD/macOS-only, gated on the target above).
    const extras = [_][]const u8{ "src/termcap.c", "src/tparam.c" };
    for (extras) |extra| {
        const gop = try seen.getOrPut(extra);
        if (!gop.found_existing) try list.append(a, extra);
    }

    std.mem.sort([]const u8, list.items, {}, struct {
        fn lt(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lt);
    return list.toOwnedSlice(a);
}

/// Glob lib/**/*.c at build time and apply the same allowlist/exclusion filter
/// as the former shell-based extractor (substrings, ported verbatim), then
/// explicitly append lib/nstrftime.c (excluded by the "strftime" rule but
/// required by src/timefns.c). Result is sorted + de-duped.
fn parseLibgnuSources(b: *std.Build, io: std.Io) ![]const []const u8 {
    const a = b.allocator;
    var list: std.ArrayList([]const u8) = .empty;
    var seen = std.StringHashMap(void).init(a);
    defer seen.deinit();

    // Allowlist: substring port of the former `grep -E` allowlist.
    const allowlist = [_][]const u8{
        "acl",        "alloca",       "binary-io",      "boot-time",
        "byteswap",   "c-ctype",      "c-str",          "canonicalize",
        "careadlinkat", "chmodat",    "cloexec",        "close-stream",
        "copy-file-range", "dirent",  "dirfd",          "dtoastr",
        "dtotimespec", "dup2",        "fallocat",       "fchmodat",
        "fd-open",    "filemode",     "filename",       "filevercmp",
        "flexmember", "fpending",     "fingerprint",    "futimens",
        "free",       "fsusage",      "gen_tempname",   "get-permissions",
        "getdelim",   "getrandom",    "getline",        "getprogname",
        "hard-locale", "isset",       "issymlink",      "lstat",
        "malloc",     "md5",          "memchr",         "memcmp",
        "memmem",     "memset_explicit", "memmove",     "memcpy",
        "memrchr",    "mkdir",        "mkancesdirs",    "mkostemp",
        "mktime",     "nanosleep",    "nproc",          "nstrftime",
        "openat-die", "openat",       "pathmax",        "pending",
        "pipe2",      "pthread",      "qcopy-acl",      "quotearl",
        "read",       "realloc",      "same",           "save-cwd",
        "set-permissions", "sha",     "sig2str",        "sigdescr_np",
        "streq",      "stat",         "stdbit",         "stdc",
        "strchr",     "strcmp",       "strchrnul",      "strcpy",
        "strerror",   "strlen",       "string",         "strncase",
        "strndup",    "strnlen",      "strncmp",        "strto",
        "tempname",   "time",         "timespec",       "u64",
        "unsetenv",   "utimens",      "waitpid",        "wctype",
        "xmalloc",
    };
    // Exclusion: substring port of the former `grep -v` list.
    const exclude = [_][]const u8{
        "regex",          "strtoimax",     "strtoumax",
        "printf",         "strftime",      "at-func",
        "dynarray-skeleton", "ialloca",    "malloc/dynarray",
        "pthread_sigmask",
    };

    var libdir = try std.Io.Dir.cwd().openDir(io, "lib", .{ .iterate = true });
    defer libdir.close(io);
    var w = try libdir.walk(a);
    defer w.deinit();
    while (try w.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".c")) continue;

        const path = try std.fmt.allocPrint(a, "lib/{s}", .{entry.path});
        if (!containsAny(path, &allowlist)) continue;
        if (containsAny(path, &exclude)) continue;

        const gop = try seen.getOrPut(path);
        if (!gop.found_existing) try list.append(a, path);
    }

    // nstrftime.c is matched by the "strftime" exclusion above but is required
    // by src/timefns.c; it is appended explicitly.
    const nstrftime = "lib/nstrftime.c";
    const gop = try seen.getOrPut(nstrftime);
    if (!gop.found_existing) try list.append(a, nstrftime);

    std.mem.sort([]const u8, list.items, {}, struct {
        fn lt(_: void, lhs: []const u8, rhs: []const u8) bool {
            return std.mem.lessThan(u8, lhs, rhs);
        }
    }.lt);
    return list.toOwnedSlice(a);
}

fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |n| {
        if (std.mem.indexOf(u8, haystack, n) != null) return true;
    }
    return false;
}
