const std = @import("std");

// Import generated source lists
const base_sources = @import("build-config/base_sources.zig").base_sources;
const libgnu_sources = @import("build-config/libgnu_sources.zig").libgnu_sources;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
    exe.linkSystemLibrary("m");

    if (!is_windows) {
        // Core libraries
        exe.linkSystemLibrary("gmp");
        exe.linkSystemLibrary("gnutls");

        // Terminal support
        exe.linkSystemLibrary("ncurses");

        // XML parsing
        exe.linkSystemLibrary("xml2");

        // Compression
        exe.linkSystemLibrary("z");

        // Color management
        exe.linkSystemLibrary("lcms2");

        // SQLite database
        exe.linkSystemLibrary("sqlite3");

        // ACL support (Linux only, for file access control lists)
        if (target.result.os.tag == .linux) {
            exe.linkSystemLibrary("acl");
            exe.linkSystemLibrary("selinux");
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
