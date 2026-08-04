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

    // Generate lisp/international/{charscript,emoji-zwj}.el from admin/unidata
    // via gawk. Mirrors `make -C admin/unidata charscript.el emoji-zwj.el`.
    // Outputs land in the SOURCE TREE (where make places them, where the
    // future I9c dump step reads them via EMACSLOADPATH=$PWD/lisp); both are
    // gitignored (.gitignore:268), so source-tree writes do not dirty the
    // index. Use gawk explicitly (the AWK the Makefile sets), not awk, to
    // avoid mawk portability issues. Standalone only -- NOT wired into the
    // default install/zig build (deferred to the I9c dump increment).
    const gen_unidata = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        \\set -e
        \\gawk -f admin/unidata/blocks.awk \
        \\  admin/unidata/Blocks.txt admin/unidata/emoji-data.txt \
        \\  > lisp/international/charscript.el
        \\gawk -f admin/unidata/emoji-zwj.awk \
        \\  admin/unidata/emoji-zwj-sequences.txt admin/unidata/emoji-sequences.txt \
        \\  > lisp/international/emoji-zwj.el
    });
    const gen_unidata_step = b.step(
        "generate-unidata",
        "Generate lisp/international/{charscript,emoji-zwj}.el from admin/unidata",
    );
    gen_unidata_step.dependOn(&gen_unidata.step);

    // Generate etc/charsets/*.map (131 maps) and lisp/international/
    // {cp51932,eucjp-ms}.el from admin/charsets via the bootstrap Makefile.
    // Mirrors `make -C admin/charsets charsetdir=$PWD/etc/charsets
    // top_srcdir=$PWD` (plan lines 26,72). Outputs land in the SOURCE TREE
    // (where the I9c dump step reads them via EMACSLOADPATH=$PWD/lisp and
    // EMACSDATA=$PWD/etc); all are gitignored (.gitignore:266,268), so
    // source-tree writes do not dirty the index. admin/charsets/Makefile is
    // a CONFIGURE PRODUCT (only Makefile.in is tracked), so the step
    // degrades gracefully when configure has not run -- identical in spirit
    // to the dump step requiring the bootstrap config.h. `$PWD` is the repo
    // root because setCwd(b.path(".")) (same as the dump step below);
    // `make -C` then cd's into admin/charsets so ${srcdir}=. resolves
    // mapfiles/awk scripts, while charsetdir/top_srcdir are overridden on
    // the cmdline. Standalone only -- NOT wired into the default
    // install/zig build (mirrors generate-unidata above).
    const gen_charsets = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        \\set -e
        \\if [ ! -f admin/charsets/Makefile ]; then
        \\  echo "Warning: admin/charsets/Makefile not present (run configure);" \
        \\    "skipping charset map generation"
        \\  exit 0
        \\fi
        \\make -C admin/charsets \
        \\  charsetdir="$PWD/etc/charsets" top_srcdir="$PWD"
    });
    gen_charsets.setCwd(b.path("."));
    const gen_charsets_step = b.step(
        "generate-charsets",
        "Generate etc/charsets/*.map and cp51932/eucjp-ms.el from admin/charsets",
    );
    gen_charsets_step.dependOn(&gen_charsets.step);

    // Build make-docfile as a HOST tool (it runs at build time, so it must
    // target the build host rather than the cross target). Reuses the same
    // config.h-aware flags as the libgnu compile; all gnulib headers that
    // make-docfile.c includes are already present under lib/.
    //
    // NO extra -D shims are needed: lib/string.h already defines streq and
    // memeq as inline functions (under `#if 1 && !0`) and lib/fcntl.h defines
    // O_BINARY=0 under `#ifndef O_BINARY`. Command-line `-Dstreq`/`-Dmemeq`
    // macros actively break the build because they rewrite the inline function
    // identifier in lib/string.h and produce `expected identifier or '('`.
    const mdf_flags = &[_][]const u8{
        "-std=gnu2x",
        "-fno-common",
        "-D_GNU_SOURCE",
        "-DHAVE_CONFIG_H",
        "-I.",
        "-Ibuild-config",
        "-Isrc",
        "-Ilib",
    };
    const mdf = b.addExecutable(.{
        .name = "make-docfile",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .link_libc = true,
        }),
    });
    // Source set. make-docfile.c + c-ctype.c + binary-io.c mirror the autotools
    // build; streq.c / memeq.c / realloc.c provide the out-of-line definitions
    // of the gnulib inline functions that make-docfile.c references (lib/string.h
    // declares streq & memeq as plain C99 `inline`, and lib/stdlib.h #defines
    // realloc -> rpl_realloc). Autotools pulls these from ../lib/libgnu.a; here
    // we compile the three specific providers directly. Each is self-contained
    // (streq.c/memeq.c just re-include <string.h> with the extern-inline macro;
    // realloc.c sets _GL_USE_STDLIB_ALLOC=1 so its realloc() call hits libc).
    const mdf_sources = [_][]const u8{
        "lib-src/make-docfile.c",
        "lib/c-ctype.c",
        "lib/binary-io.c",
        "lib/streq.c",
        "lib/memeq.c",
        "lib/realloc.c",
    };
    for (mdf_sources) |src| {
        mdf.root_module.addCSourceFile(.{
            .file = b.path(src),
            .flags = mdf_flags,
        });
    }

    // Run `make-docfile -d src -g <names>` and capture stdout as globals.h.
    // make-docfile only rewrites a trailing ".o" to ".c"/".m" (scan_c_file at
    // ~line 809), so a bare basename is NOT accepted — pass the full
    // "foo.c" name. Just strip the leading "src/" prefix so the name resolves
    // after the -d src chdir. On a Linux TTY build there is no NS_OBJC_OBJ, so
    // base_obj == doc_obj.
    const run_mdf = b.addRunArtifact(mdf);
    run_mdf.addArg("-d");
    run_mdf.addArg("src");
    run_mdf.addArg("-g");
    for (base_sources) |s| {
        // Strip leading "src/"; keep the ".c" extension.
        var name: []const u8 = s;
        if (std.mem.startsWith(u8, name, "src/")) name = name["src/".len..];
        run_mdf.addArg(name);
    }
    // Autotools folds $(DBUS_OBJ)/$(DYNLIB_OBJ)/$(NOTIFY_OBJ) into base_obj
    // (and thus doc_obj) on Linux; parseBaseSources drops $(...) vars, so the
    // Linux-only DEFSYM providers must be re-added here, otherwise globals.h
    // is missing QCbyte/QCstring/... (dbusbind.c, 33 DEFSYMs) and
    // Qaccess/Qcreate/... (inotify.c, 21 DEFSYMs) and the compile fails with
    // "use of undeclared identifier". dynlib.c has zero DEFSYMs but is added
    // for parity with the compile gate.
    if (target.result.os.tag == .linux) {
        const linux_doc_sources = [_][]const u8{ "dbusbind.c", "dynlib.c", "inotify.c" };
        for (linux_doc_sources) |name| run_mdf.addArg(name);
    }
    const globals_h = run_mdf.captureStdOut(.{ .basename = "globals.h" });

    const gen_globals_step = b.step("generate-globals", "Generate src/globals.h via make-docfile");
    gen_globals_step.dependOn(&run_mdf.step);

    // Generate buildobj.h: a flat comma-list of object file names consumed by
    // src/doc.c:547's `static char const *const buildobj[] = { #include "buildobj.h" };`.
    // Mirrors Makefile.in:673-679's sed (strip dir, .c -> .o, wrap as "<name>.o",),
    // built purely from the in-memory base/lib source slices. The header lands
    // in the zig cache (NOT src/), keeping the source tree clean.
    const buildobj_body = blk: {
        const a = b.allocator;
        var buf: std.ArrayList(u8) = .empty;
        for (base_sources) |src| appendBuildobjEntry(a, &buf, src) catch @panic("build.zig: OOM building buildobj.h");
        for (libgnu_sources) |src| appendBuildobjEntry(a, &buf, src) catch @panic("build.zig: OOM building buildobj.h");
        break :blk buf.toOwnedSlice(a) catch @panic("build.zig: OOM building buildobj.h");
    };
    const buildobj_wf = b.addWriteFiles();
    _ = buildobj_wf.add("buildobj.h", buildobj_body);
    const gen_buildobj_step = b.step("generate-buildobj", "Generate buildobj.h");
    gen_buildobj_step.dependOn(&buildobj_wf.step);

    // Generate epaths.h: build-tree paths so the dumped emacs finds lisp/etc
    // under the source tree by default, instead of the nonexistent
    // /usr/local/share install dirs the bootstrap src/epaths.h carries. The
    // header lands in the zig cache (NOT src/) and is registered on the
    // include path below so it overrides the bootstrap copy. Mirrors
    // buildobj.h generation above. Emits ONLY the live non-Android branch
    // (HAVE_ANDROID is undef in config.h, so the `#if !defined HAVE_ANDROID`
    // arm is the active one) and defines all 11 PATH_* macros so the header
    // is self-contained. <repo> is the project root (b.path(".")), the same
    // directory the dump step (below) operates in.
    const epaths_body = blk: {
        const a = b.allocator;
        const repo = b.path(".").getPath(b);
        const path_load = std.fmt.allocPrint(a, "{s}/lisp", .{repo}) catch
            @panic("build.zig: OOM building epaths.h");
        const path_exec = std.fmt.allocPrint(a, "{s}/lib-src", .{repo}) catch
            @panic("build.zig: OOM building epaths.h");
        const path_etc = std.fmt.allocPrint(a, "{s}/etc", .{repo}) catch
            @panic("build.zig: OOM building epaths.h");
        const path_info = std.fmt.allocPrint(a, "{s}/info", .{repo}) catch
            @panic("build.zig: OOM building epaths.h");
        var buf: std.ArrayList(u8) = .empty;
        appendEpathsStr(a, &buf, "PATH_LOADSEARCH", path_load) catch
            @panic("build.zig: OOM building epaths.h");
        appendEpathsStr(a, &buf, "PATH_REL_LOADSEARCH", "32.0.50/lisp") catch
            @panic("build.zig: OOM building epaths.h");
        // PATH_SITELOADSEARCH is intentionally empty: a non-empty value is
        // prepended to load-path, which would make (car load-path) the
        // site-lisp dir instead of PATH_LOADSEARCH (<repo>/lisp). The build
        // tree has no site-lisp, so empty keeps load-path rooted at
        // <repo>/lisp.
        appendEpathsStr(a, &buf, "PATH_SITELOADSEARCH", "") catch
            @panic("build.zig: OOM building epaths.h");
        appendEpathsStr(a, &buf, "PATH_DUMPLOADSEARCH", path_load) catch
            @panic("build.zig: OOM building epaths.h");
        appendEpathsStr(a, &buf, "PATH_EXEC", path_exec) catch
            @panic("build.zig: OOM building epaths.h");
        appendEpathsStr(a, &buf, "PATH_DATA", path_etc) catch
            @panic("build.zig: OOM building epaths.h");
        appendEpathsStr(a, &buf, "PATH_BITMAPS", "") catch
            @panic("build.zig: OOM building epaths.h");
        appendEpathsStr(a, &buf, "PATH_DOC", path_etc) catch
            @panic("build.zig: OOM building epaths.h");
        appendEpathsStr(a, &buf, "PATH_INFO", path_info) catch
            @panic("build.zig: OOM building epaths.h");
        appendEpathsRaw(a, &buf, "PATH_GAME", "((char const *) 0)") catch
            @panic("build.zig: OOM building epaths.h");
        appendEpathsStr(a, &buf, "PATH_X_DEFAULTS", "") catch
            @panic("build.zig: OOM building epaths.h");
        break :blk buf.toOwnedSlice(a) catch @panic("build.zig: OOM building epaths.h");
    };
    const epaths_wf = b.addWriteFiles();
    _ = epaths_wf.add("epaths.h", epaths_body);
    const gen_epaths_step = b.step("generate-epaths", "Generate epaths.h with build-tree paths");
    gen_epaths_step.dependOn(&epaths_wf.step);

    // Generate src/config.h via a CUSTOM generator (not addConfigHeader).
    // addConfigHeader needs a comptime values struct, unwieldy for the ~760
    // config.h knobs; this reads the lean zig-authored template (src/config.h.in:
    // guard + _GNU_SOURCE + every `#undef NAME` from config.in + conf_post) plus
    // the zig-owned answer data (src/config_values.txt: `NAME=value`, or bare
    // `NAME` for undef) and substitutes each `#undef NAME` -> the value --
    // the macro processing autoconf's config.status does. Text-based, so every
    // value type (ints, strings, char literals, /**/) is handled uniformly.
    // Output lands in .zig-cache (gitignored). Standalone -- does NOT depend on exe.
    const config_h_in_text = std.Io.Dir.cwd().readFileAlloc(
        io, "src/config.h.in", b.allocator, .limited(4 * 1024 * 1024),
    ) catch @panic("build.zig: failed to read src/config.h.in");
    const config_values_text = std.Io.Dir.cwd().readFileAlloc(
        io, "src/config_values.txt", b.allocator, .limited(4 * 1024 * 1024),
    ) catch @panic("build.zig: failed to read src/config_values.txt");
    var config_values = std.StringHashMap([]const u8).init(b.allocator);
    defer config_values.deinit();
    {
        var vit = std.mem.splitScalar(u8, config_values_text, '\n');
        while (vit.next()) |vline| {
            if (vline.len == 0) continue;
            if (std.mem.indexOfScalar(u8, vline, '=')) |eq| {
                config_values.put(vline[0..eq], vline[eq + 1 ..]) catch
                    @panic("build.zig: OOM building config values map");
            } else {
                config_values.put(vline, "") catch
                    @panic("build.zig: OOM building config values map");
            }
        }
    }
    const config_h_body = blk: {
        const a = b.allocator;
        var buf: std.ArrayList(u8) = .empty;
        var tit = std.mem.splitScalar(u8, config_h_in_text, '\n');
        var first = true;
        while (tit.next()) |tline| {
            if (!first) buf.append(a, '\n') catch
                @panic("build.zig: OOM building config.h");
            first = false;
            if (std.mem.startsWith(u8, tline, "#undef ")) {
                const name = std.mem.trim(u8, tline["#undef ".len..], " \t\r");
                const v = config_values.get(name);
                const has_val = v != null and v.?.len > 0;
                const rendered = if (has_val)
                    std.fmt.allocPrint(a, "#define {s} {s}", .{ name, v.? }) catch
                        @panic("build.zig: OOM building config.h")
                else
                    std.fmt.allocPrint(a, "/* #undef {s} */", .{name}) catch
                        @panic("build.zig: OOM building config.h");
                buf.appendSlice(a, rendered) catch
                    @panic("build.zig: OOM building config.h");
            } else {
                buf.appendSlice(a, tline) catch
                    @panic("build.zig: OOM building config.h");
            }
        }
        break :blk buf.toOwnedSlice(a) catch @panic("build.zig: OOM building config.h");
    };
    const config_h_wf = b.addWriteFiles();
    const config_h_file = config_h_wf.add("config.h", config_h_body);
    const gen_config_step = b.step(
        "generate-config",
        "Generate src/config.h from the zig-authored template + values",
    );
    gen_config_step.dependOn(&config_h_wf.step);

    // Verify the generated config.h carries the load-bearing subset of knobs
    // the rest of the build will eventually rely on. The generated file path
    // is passed in as $1 via the standard addFileArg idiom; any failed grep
    // exits non-zero and fails the step. Standalone -- does NOT depend on exe.
    const verify_config_cmd = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        \\set -e
        \\f="$1"
        \\grep -qE '^#ifndef EMACS_CONFIG_H$' "$f"
        \\grep -qE '^#define EMACS_CONFIG_H$' "$f"
        \\grep -qE '^#include <conf_post\.h>$' "$f"
        \\grep -qE '^#define SYSTEM_TYPE "gnu/linux"$' "$f"
        \\grep -qE '^#define EMACS_CONFIGURATION "x86_64-pc-linux-gnu"$' "$f"
        \\grep -qE '^#define HAVE_PDUMPER 1$' "$f"
        \\grep -qE '^#define SYSTEM_MALLOC 1$' "$f"
        \\grep -qE '^#define HAVE_ALSA 1$' "$f"
        \\grep -qE '^#define HAVE_DBUS 1$' "$f"
        \\grep -qE '^#define HAVE_GPM 1$' "$f"
        \\grep -qE '^#define HAVE_INOTIFY 1$' "$f"
        \\grep -qE '^#define HAVE_LIBXML2 1$' "$f"
        \\grep -qE '^#define HAVE_SQLITE3 1$' "$f"
        \\grep -qE '^#define HAVE_LCMS2 1$' "$f"
        \\grep -qE '^#define HAVE_GNUTLS 1$' "$f"
        \\grep -qE '^#define HAVE_TREE_SITTER 1$' "$f"
        \\grep -qE '^#define HAVE_GETRANDOM 1$' "$f"
        \\grep -qE '^#define GNU_LINUX\b' "$f"
        \\grep -qE "^#define DIRECTORY_SEP '/'$" "$f"
        \\grep -qE "^#define SEPCHAR ':'$" "$f"
        \\grep -qE '^/\* #undef HAVE_MODULES \*/$' "$f"
        \\grep -qE '^/\* #undef HAVE_NS \*/$' "$f"
        \\grep -qE '^/\* #undef HAVE_ANDROID \*/$' "$f"
        \\echo "config.h OK"
    });
    verify_config_cmd.addArg("config-h");
    verify_config_cmd.addFileArg(config_h_file);
    const verify_config_step = b.step(
        "verify-config",
        "Verify the generated src/config.h carries the load-bearing knob subset",
    );
    verify_config_step.dependOn(&verify_config_cmd.step);

    // Diagnostic: quantify the gap between the generated config.h and the
    // gitignored reference src/config.h (the local autogen+configure output).
    // Soft (always exits 0) -- the gap is expected until I4b finishes. This
    // step is what makes subsequent I4b chunks verifiable: run it after each
    // chunk and watch `missing:` shrink toward 0. Standalone -- depends only
    // on config_h, not on exe.
    const diff_config_cmd = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        \\set -u
        \\gen="$1"; ref="$2"
        \\if [ ! -f "$ref" ]; then
        \\  echo "reference src/config.h not present; skipping diff"
        \\  exit 0
        \\fi
        \\extract() {
        \\  grep -hoE '^#define [A-Z_][A-Z_0-9]*' "$1" | awk '{print $2}'
        \\  grep -hoE '^/\* #undef [A-Z_][A-Z_0-9]* \*/' "$1" | awk '{print $3}'
        \\}
        \\extract "$gen" | sort -u | grep -vxE 'EMACS_CONFIG_H|_GL_CONFIG_H_INCLUDED' > "$gen.knobs"
        \\extract "$ref" | sort -u | grep -vxE 'EMACS_CONFIG_H|_GL_CONFIG_H_INCLUDED' > "$ref.knobs"
        \\g=$(wc -l < "$gen.knobs"); r=$(wc -l < "$ref.knobs")
        \\miss=$(comm -23 "$ref.knobs" "$gen.knobs" | wc -l)
        \\extra=$(comm -13 "$ref.knobs" "$gen.knobs" | wc -l)
        \\echo "generated: $g knobs"
        \\echo "reference: $r knobs"
        \\echo "missing: $miss"
        \\echo "extra: $extra"
        \\echo "--- first missing ---"
        \\comm -23 "$ref.knobs" "$gen.knobs" | head -10
        \\rm -f "$gen.knobs" "$ref.knobs"
        \\exit 0
    });
    diff_config_cmd.addArg("config-diff");
    diff_config_cmd.addFileArg(config_h_file);
    diff_config_cmd.addFileArg(b.path("src/config.h"));
    const diff_config_step = b.step(
        "config-diff",
        "Report the config.h knob gap vs the gitignored reference",
    );
    diff_config_step.dependOn(&config_h_wf.step);
    diff_config_step.dependOn(&diff_config_cmd.step);

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

        // Linux-only sources. Mirrors the kqueue gate above but keyed on
        // .linux, inside the !is_windows branch.
        //   - src/dynlib.c:HAVE_MODULES is undef in config.h, but treesit.c
        //     calls dynlib_{error,open,sym,addr} unconditionally; the POSIX
        //     branch uses dlopen/dlsym (in libc on glibc).
        //   - src/inotify.c:HAVE_INOTIFY=1 in config.h; inotify_init1 in libc.
        //   - src/dbusbind.c:HAVE_DBUS=1 in config.h; needs the two dbus
        //     include dirs `pkg-config --cflags dbus-1` reports on this host.
        if (target.result.os.tag == .linux) {
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/dynlib.c"),
                .flags = base_flags,
            });
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/inotify.c"),
                .flags = base_flags,
            });
            const dbus_flags = base_flags ++ [_][]const u8{
                "-I/usr/include/dbus-1.0",
                "-I/usr/lib64/dbus-1.0/include",
            };
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/dbusbind.c"),
                .flags = dbus_flags,
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

        // lib/mktime.c is compiled in the 92-file libgnu set, but its body is
        // #if'd out unless -DNEED_MKTIME_INTERNAL=1 is set per-file (Autotools
        // passes this on the mktime.o compile line, NOT via config.h). lib/
        // mktime-internal.h:72 renames __mktime_internal -> mktime_internal
        // when !_LIBC, so timegm.o references mktime_internal; without the
        // flag the symbol is left undefined. DO NOT add -DNEED_MKTIME_WORKING
        // (it would rename mktime -> rpl_mktime and break other callers).
        const libgnu_mktime_flags = libgnu_flags ++ [_][]const u8{ "-DNEED_MKTIME_INTERNAL=1" };

        for (libgnu_sources) |src| {
            const flags: []const []const u8 =
                if (std.mem.eql(u8, src, "lib/mktime.c")) libgnu_mktime_flags else libgnu_flags;
            exe.root_module.addCSourceFile(.{
                .file = b.path(src),
                .flags = flags,
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

            // Tree-sitter (HAVE_TREE_SITTER): ts_* symbols from src/treesit.c.
            exe.root_module.linkSystemLibrary("tree-sitter", .{});
            // ALSA audio (HAVE_ALSA): snd_* symbols from src/sound.c.
            exe.root_module.linkSystemLibrary("asound", .{});
            // Linux console mouse (HAVE_GPM): Gpm_*/gpm_* symbols from src/term.c.
            exe.root_module.linkSystemLibrary("gpm", .{});
            // Extended-attribute ACL copy: attr_copy_* from lib/qcopy-acl.c (libattr.so.1).
            exe.root_module.linkSystemLibrary("attr", .{});
            // D-Bus (HAVE_DBUS): dbus_* symbols from src/dbusbind.c.
            exe.root_module.linkSystemLibrary("dbus-1", .{});
        }
    }

    // Install the executable
    b.installArtifact(exe);

    // Make the executable compilation depend on header generation
    exe.step.dependOn(&generate_headers.step);

    // temacs needs globals.h on its include path; the header lives under
    // zig-cache, NOT in src/ (the source tree stays clean).
    exe.root_module.addIncludePath(globals_h.dirname());
    exe.step.dependOn(&run_mdf.step);

    // temacs also needs buildobj.h (included by src/doc.c:547) on its include
    // path; the header lives under zig-cache alongside globals.h.
    exe.root_module.addIncludePath(buildobj_wf.getDirectory());
    exe.step.dependOn(&buildobj_wf.step);

    // temacs also needs the zig-generated epaths.h on its include path. The
    // header lives under zig-cache alongside globals.h/buildobj.h and carries
    // build-tree paths (lisp/etc/lib-src under <repo>) so the dumped emacs
    // locates its data without EMACSLOADPATH/EMACSDATA and without a
    // /usr/local/share install. addIncludePath is what lets the generated
    // copy take effect once the bootstrap src/epaths.h is moved aside.
    exe.root_module.addIncludePath(epaths_wf.getDirectory());
    exe.step.dependOn(&epaths_wf.step);

    // Dump step (`zig build dump`): produce a runnable bootstrap-emacs.pdmp by
    // running the built temacs over loadup in bootstrap mode. The dumped emacs
    // can then evaluate Lisp, e.g.:
    //   ./zig-out/bin/temacs --dump-file=zig-out/bin/bootstrap-emacs.pdmp \
    //     --batch --eval '(princ emacs-version)'   -> "32.0.50"
    // It is a SEPARATE step (not part of the default `zig build`) because it
    // needs the bootstrap data files (etc/charsets/*.map,
    // lisp/international/{charscript,emoji-zwj}.el) and src/config.h present --
    // transitional dependencies, like config.h. Run `zig build generate-unidata`
    // and `zig build generate-charsets` first.
    //
    // --temacs=pbootstrap (NOT pdump) is mandatory for the first, from-source
    // dump: it sets will_bootstrap (emacs.c:1377), bypassing fns.c:3833's guard
    // that forbids autoloads while preparing to dump, so files.el's
    // (eval-when-compile (require 'pcase)) can load pcase. EMACSLOADPATH and
    // EMACSDATA point loadup and the charset loader at the source tree, since
    // the epaths.h install paths don't exist yet (I7). loadup writes the dump
    // next to the running temacs (zig-out/bin/), where the install put it.
    const run_dump = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        \\EMACSLOADPATH="$PWD/lisp" EMACSDATA="$PWD/etc" LC_ALL=C \
        \\  ./zig-out/bin/temacs -batch -l loadup --temacs=pbootstrap
    });
    run_dump.setCwd(b.path("."));
    const dump_step = b.step("dump", "Dump a runnable bootstrap-emacs.pdmp via temacs loadup");
    dump_step.dependOn(b.getInstallStep());
    dump_step.dependOn(&run_dump.step);

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
        "fcntl",      "fd-open",      "filemode",       "filename",
        "filevercmp", "flexmember",   "fpending",       "fingerprint",
        "futimens",
        "free",       "fsusage",      "gen_tempname",   "get-permissions",
        "getdelim",   "getrandom",    "getline",        "getprogname",
        "hard-locale", "isset",       "issymlink",      "lstat",
        "malloc",     "md5",          "memchr",         "memcmp",
        "memeq",      "memmem",       "memset_explicit", "memmove",
        "memcpy",
        "memrchr",    "mkdir",        "mkancesdirs",    "mkostemp",
        "mktime",     "nanosleep",    "nproc",          "nstrftime",
        "openat-die", "openat",       "pathmax",        "pending",
        "pipe2",      "pthread",      "qcopy-acl",      "quotearl",
        "read",       "realloc",      "same",           "save-cwd",
        "set-permissions", "sha",     "sig2str",        "sigdescr_np",
        "streq",      "stat",         "stdbit",         "stdc",
        "strchr",     "strcmp",       "strchrnul",      "strcpy",
        "strerror",   "strlen",       "string",         "strncase",
        "strndup",    "strnlen",      "strncmp",        "strnul",
        "strto",
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
        // lib/getrandom.c: with HAVE_GETRANDOM and the rpl substitution
        // disabled (lib/sys/random.h guards `#define getrandom rpl_getrandom`
        // under `#if 0`), compiling this file produces a self-recursive
        // getrandom -- its internal call resolves to its own definition,
        // overflowing the stack at startup. Callers (fns.c, sysdep.c) use the
        // libc getrandom directly, so the gnulib rpl provider is unneeded.
        "getrandom",
        // lib/fchmodat.c: same self-recursion as getrandom. lib/sys/stat.h
        // guards `#define fchmodat rpl_fchmodat` under `#if 0` (rpl off), so
        // compiling this file defines a plain `fchmodat` whose internal
        // orig_fchmodat call resolves to itself -> stack overflow. It crashes
        // byte-compilation (the byte-compiler fchmodat's its temp files).
        // Callers use the libc fchmodat (HAVE_FCHMODAT=1).
        "fchmodat",
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

/// Append one `"<basename>.o",\n` line to `buf`, mirroring Makefile.in:673-679:
/// strip the directory prefix (everything up to and including the last `/`),
/// rewrite the trailing `.c` suffix to `.o`, and wrap with a leading `"` and a
/// trailing `",`. Our parsed source lists are `.c`-suffixed, so the sed's
/// `.obj` -> `.o` rule does not apply here.
fn appendBuildobjEntry(a: std.mem.Allocator, buf: *std.ArrayList(u8), src: []const u8) !void {
    const base: []const u8 = if (std.mem.lastIndexOfScalar(u8, src, '/')) |idx|
        src[idx + 1 ..]
    else
        src;
    const stem: []const u8 = if (std.mem.endsWith(u8, base, ".c"))
        base[0 .. base.len - ".c".len]
    else
        base;
    try buf.appendSlice(a, "\"");
    try buf.appendSlice(a, stem);
    try buf.appendSlice(a, ".o\",\n");
}

/// Append a `#define NAME "VALUE"\n` line to `buf`, for the string-valued
/// epaths.h macros (PATH_LOADSEARCH, PATH_DATA, ...). Mirrors the quoting of
/// the bootstrap src/epaths.h.
fn appendEpathsStr(a: std.mem.Allocator, buf: *std.ArrayList(u8), name: []const u8, value: []const u8) !void {
    try buf.appendSlice(a, "#define ");
    try buf.appendSlice(a, name);
    try buf.appendSlice(a, " \"");
    try buf.appendSlice(a, value);
    try buf.appendSlice(a, "\"\n");
}

/// Append a `#define NAME VALUE\n` line (unquoted), for macros whose value is
/// not a string literal: PATH_GAME = ((char const *) 0).
fn appendEpathsRaw(a: std.mem.Allocator, buf: *std.ArrayList(u8), name: []const u8, value: []const u8) !void {
    try buf.appendSlice(a, "#define ");
    try buf.appendSlice(a, name);
    try buf.appendSlice(a, " ");
    try buf.appendSlice(a, value);
    try buf.appendSlice(a, "\n");
}

fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |n| {
        if (std.mem.indexOf(u8, haystack, n) != null) return true;
    }
    return false;
}
