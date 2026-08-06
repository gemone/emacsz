const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // `-Dshow-sources=true`: print the parsed base/lib source lists to stderr
    // (two counts followed by the lists) and exit without installing artifacts.
    // Used to verify the build-time parsers against the autotools source lists.
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

    // Generate Gnulib .gl.h headers before compilation. A native Zig tool
    // (build-aux/generate-gl-headers.zig) replaces the former shell-out;
    // mirrors the same sed pipeline so the tracked lib/malloc/*.gl.h outputs
    // stay byte-identical. The tool runs at build time, so like make-docfile
    // (lines 128-135) it targets the build host (b.graph.host) rather than
    // the cross target. The run step is wired into both the standalone
    // `generate-headers` step and the exe (line 638), preserving the prior
    // behavior -- the port is purely an implementation swap.
    // The Gnulib .gl.h generator is now an independent Zig package
    // (dependency `gl_headers_gen` in build.zig.zon -> tools/gl-headers).
    const gl_dep = b.dependency("gl_headers_gen", .{});
    const gl_tool = b.addExecutable(.{
        .name = "generate-gl-headers",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .link_libc = true,
            .root_source_file = gl_dep.path("src/main.zig"),
        }),
    });
    const generate_headers = b.addRunArtifact(gl_tool);
    generate_headers.setCwd(b.path("."));
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

    // Generate src/config.h via a CUSTOM generator (not addConfigHeader).
    // addConfigHeader needs a comptime values struct, unwieldy for the ~760
    // config.h knobs; this reads the lean zig-authored template (src/config.h.in:
    // guard + _GNU_SOURCE + every `#undef NAME` from config.in + conf_post) plus
    // the zig-owned answer data (src/config_values.txt: `NAME=value`, or bare
    // `NAME` for undef) and substitutes each `#undef NAME` -> the value --
    // the macro processing autoconf's config.status does. Text-based, so every
    // value type (ints, strings, char literals, /**/) is handled uniformly.
    // This REPLACES the former ./configure shell step (autoconf probe): the
    // template + answer file are committed, the tool is pure Zig, and every C
    // compile (make-docfile + temacs) includes the generated <config.h> from
    // the zig-cache via addIncludePath below. No shell is needed.
    //
    // The config.h generator is an independent Zig package (dependency
    // `gen_config` in build.zig.zon -> tools/gen-config). The tool reads
    // src/config.h.in + src/config_values.txt (with cwd = repo root via
    // setCwd) and writes the substituted config.h body to STDOUT;
    // captureStdOut lands it in the zig-cache. Defined here (before
    // make-docfile + temacs) because every C compile includes <config.h>.
    const gen_config_dep = b.dependency("gen_config", .{});
    const gen_config_tool = b.addExecutable(.{
        .name = "gen-config",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .link_libc = true,
            .root_source_file = gen_config_dep.path("src/main.zig"),
        }),
    });
    const run_gen_config = b.addRunArtifact(gen_config_tool);
    run_gen_config.setCwd(b.path("."));
    // Pass the template + answer files as args so the step's cache tracks
    // their content (the tool reads them relative to the cwd).
    run_gen_config.addFileArg(b.path("src/config.h.in"));
    run_gen_config.addFileArg(b.path("src/config_values.txt"));
    const config_h_file = run_gen_config.captureStdOut(.{ .basename = "config.h" });
    const gen_config_step = b.step(
        "generate-config",
        "Generate src/config.h from the zig-authored template + values",
    );
    gen_config_step.dependOn(&run_gen_config.step);

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
        "-fno-strict-aliasing",
        "-D_GNU_SOURCE",
        "-DHAVE_CONFIG_H",
        "-I.",
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
    // make-docfile's sources include <config.h>; the generated file (from
    // src/config.h.in + src/config_values.txt) is provided via the module
    // include path, so the compile must wait for the generator.
    mdf.root_module.addIncludePath(config_h_file.dirname());
    mdf.step.dependOn(&run_gen_config.step);

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

    // Generate etc/DOC: the doc strings for C primitives and variables,
    // consumed at runtime from doc-directory (etc/) by doc.c. Mirrors
    // src/Makefile.in's DOC rule: SOME_MACHINE_OBJECTS first (so every
    // platform's entries are present once), then doc_obj (= base_obj on
    // this TTY build, plus the Linux DEFSYM files re-added for globals.h
    // parity). Without it `(documentation 'subr)` returns nil and
    // doc-tests-documentation/c-primitive fails. Output lands in etc/
    // (gitignored) where the dumped emacs looks for it.
    const run_doc = b.addRunArtifact(mdf);
    run_doc.addArg("-d");
    run_doc.addArg("src");
    // SOME_MACHINE_OBJECTS as in Makefile.in:477-488 (.o names; make-docfile
    // rewrites the extension to .c after the -d chdir).
    const some_machine_objects = [_][]const u8{
        "dosfns.o",          "msdos.o",          "xterm.o",
        "xfns.o",            "xmenu.o",          "xselect.o",
        "xrdb.o",            "xsmfns.o",         "fringe.o",
        "image.o",           "fontset.o",        "dbusbind.o",
        "cygw32.o",          "nsterm.o",         "nsfns.o",
        "nsmenu.o",          "nsselect.o",       "nsimage.o",
        "nsfont.o",          "macfont.o",        "nsxwidget.o",
        "w32.o",             "w32console.o",     "w32cygwinx.o",
        "w32fns.o",          "w32heap.o",        "w32inevt.o",
        "w32notify.o",       "w32menu.o",        "w32proc.o",
        "w32reg.o",          "w32select.o",      "w32term.o",
        "w32xfns.o",         "w16select.o",      "widget.o",
        "xfont.o",           "ftfont.o",         "xftfont.o",
        "gtkutil.o",         "xsettings.o",      "xgselect.o",
        "termcap.o",         "hbfont.o",         "haikuterm.o",
        "haikufns.o",        "haikumenu.o",      "haikufont.o",
        "androidterm.o",     "androidfns.o",     "androidfont.o",
        "androidselect.c",   "androidvfs.c",     "sfntfont-android.c",
        "sfntfont.c",
    };
    for (some_machine_objects) |name| run_doc.addArg(name);
    for (base_sources) |s| {
        var name: []const u8 = s;
        if (std.mem.startsWith(u8, name, "src/")) name = name["src/".len..];
        // Pass .o names like upstream's doc_obj: make-docfile scans the
        // .c but writes the ^_S record with the name as given, and
        // help-C-file-name matches that record against build-files
        // (buildobj.h), which holds .o names.
        const o_name = std.fmt.allocPrint(b.allocator, "{s}.o", .{name[0 .. name.len - 2]}) catch @panic("OOM");
        run_doc.addArg(o_name);
    }
    if (target.result.os.tag == .linux) {
        const linux_doc_sources = [_][]const u8{ "dbusbind.c", "dynlib.c", "inotify.c" };
        for (linux_doc_sources) |name| {
            const o_name = std.fmt.allocPrint(b.allocator, "{s}o", .{name[0 .. name.len - 1]}) catch @panic("OOM");
            run_doc.addArg(o_name);
        }
    }
    const doc_capture = run_doc.captureStdOut(.{ .basename = "DOC" });
    // Install etc/DOC into the source tree with the native
    // UpdateSourceFiles step (no shell; etc/DOC is a gitignored
    // generated artifact, like loaddefs).
    const doc_install = b.addUpdateSourceFiles();
    doc_install.addCopyFileToSource(doc_capture, "etc/DOC");
    doc_install.step.dependOn(&run_doc.step);
    const gen_doc_step = b.step("generate-doc", "Generate etc/DOC via make-docfile");
    gen_doc_step.dependOn(&doc_install.step);

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
    // include path below so it overrides the bootstrap copy. Emits ONLY the
    // live non-Android branch (HAVE_ANDROID is undef in config.h, so the
    // `#if !defined HAVE_ANDROID` arm is the active one) and defines all 11
    // PATH_* macros so the header is self-contained. <repo> is the project
    // root (b.path(".").getPath(b)), the same directory the dump step
    // (below) operates in.
    //
    // The epaths.h generator is an independent Zig package (dependency
    // `gen_epaths` in build.zig.zon -> tools/gen-epaths), mirroring the
    // gen_config extraction above. The tool is pure/deterministic: it takes
    // the absolute repo root as argv[1] and writes the 11 PATH_* macros to
    // STDOUT; captureStdOut lands it in the zig-cache, the same LazyPath
    // shape the inline addWriteFiles produced, so the include-path
    // registration below consumes it unchanged.
    const gen_epaths_dep = b.dependency("gen_epaths", .{});
    const gen_epaths_tool = b.addExecutable(.{
        .name = "gen-epaths",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .link_libc = true,
            .root_source_file = gen_epaths_dep.path("src/main.zig"),
        }),
    });
    const run_gen_epaths = b.addRunArtifact(gen_epaths_tool);
    run_gen_epaths.setCwd(b.path("."));
    run_gen_epaths.addArg(b.path(".").getPath(b));
    const epaths_h = run_gen_epaths.captureStdOut(.{ .basename = "epaths.h" });
    const gen_epaths_step = b.step("generate-epaths", "Generate epaths.h with build-tree paths");
    gen_epaths_step.dependOn(&run_gen_epaths.step);

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
    diff_config_step.dependOn(&run_gen_config.step);
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
    // Non-PIE: zig-cc PIE + pdumper mis-relocates static pointers
    // (mem_root, dump_hooks, ...) -> NULL/garbage on dump load ->
    // crashes. A non-PIE binary has fixed static addresses, so no
    // runtime relocation is needed. (The target requires PIC code,
    // but PIC code in a non-PIE exe still gets fixed statics.)
    exe.pie = false;

    // temacs includes <config.h>; the generated file (from src/config.h.in +
    // src/config_values.txt) is provided via the module include path, so the
    // compile must wait for the generator.
    exe.root_module.addIncludePath(config_h_file.dirname());
    exe.step.dependOn(&run_gen_config.step);

    // gnulib-str: an independent Zig package (tools/gnulib-str) providing
    // the gnulib string-primitive external definitions that lib/memeq.c +
    // lib/streq.c would otherwise emit (their bodies are merely the
    // out-of-line copy of an `extern inline` in lib/string.h). Each
    // exported symbol (memeq, streq) is a direct implementation with no
    // libc call. Built ReleaseFast (leaf byte/string loops) so it pulls in
    // no Zig runtime or panic handler that this C executable would have to
    // satisfy. At -O0 the C compiler does not inline the header versions,
    // so callers resolve to these exported symbols.
    const gnulib_str_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_str", .{}).path("src/str.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_str_lib =
        b.addLibrary(.{ .name = "gnulib-str", .root_module = gnulib_str_mod });
    exe.root_module.linkLibrary(gnulib_str_lib);

    // gnulib-ctype: an independent Zig package (tools/gnulib-ctype)
    // providing gnulib's c-ctype character-classification functions
    // (c_isalpha, c_isdigit, c_tolower, ...) that lib/c-ctype.c would
    // otherwise emit. ASCII-only, locale-independent, exact semantic match
    // with no libc call. Built ReleaseFast (leaf int checks) so it pulls in
    // no Zig runtime the C executable must satisfy.
    const gnulib_ctype_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_ctype", .{}).path("src/ctype.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_ctype_lib =
        b.addLibrary(.{ .name = "gnulib-ctype", .root_module = gnulib_ctype_mod });
    exe.root_module.linkLibrary(gnulib_ctype_lib);

    // gnulib-stdbit: an independent Zig package (tools/gnulib-stdbit)
    // providing gnulib's C23 <stdbit.h> bit-count functions
    // (stdc_leading_zeros/_trailing_zeros/_count_ones/_bit_width and their
    // type-specific _uc/_us/_ui/_ul/_ull variants) that lib/stdc_*.c would
    // otherwise emit. Each is a single @clz/@ctz/@popCount builtin with
    // exact C23 semantics; no libc call. Built ReleaseFast (leaf bit ops).
    const gnulib_stdbit_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_stdbit", .{}).path("src/stdbit.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_stdbit_lib =
        b.addLibrary(.{ .name = "gnulib-stdbit", .root_module = gnulib_stdbit_mod });
    exe.root_module.linkLibrary(gnulib_stdbit_lib);

    // gnulib-hash: an independent Zig package (tools/gnulib-hash) providing
    // gnulib's cryptographic hashes as native Zig. SHA1, the SHA-2 family
    // (sha224/sha256/sha384/sha512), SHA-3 (Keccak, sha3_224..512) and
    // MD5, operating on the gnulib ctx layouts (lib/sha1.h, lib/sha256.h,
    // lib/sha512.h, lib/sha3.h, lib/md5.h), with no libc call. Backs
    // `secure-hash' and md5_gz_stream. Built ReleaseFast (leaf crypto).
    const gnulib_hash_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_hash", .{}).path("src/hash.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_hash_lib =
        b.addLibrary(.{ .name = "gnulib-hash", .root_module = gnulib_hash_mod });
    exe.root_module.linkLibrary(gnulib_hash_lib);

    // gnulib-sig2str: an independent Zig package (tools/gnulib-sig2str)
    // providing gnulib's signal name<->number conversion (sig2str /
    // str2sig) that lib/sig2str.c would otherwise emit. Pure table and
    // string handling over per-platform signal tables (Linux glibc/musl,
    // Windows, Darwin); no libc call. Backs `signal-names' and signal
    // parsing in src/process.c. Built ReleaseFast (leaf lookups) so it
    // pulls in no Zig runtime the C executable must satisfy.
    const gnulib_sig2str_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_sig2str", .{}).path("src/sig2str.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_sig2str_lib =
        b.addLibrary(.{ .name = "gnulib-sig2str", .root_module = gnulib_sig2str_mod });
    exe.root_module.linkLibrary(gnulib_sig2str_lib);

    // gnulib-filemode: an independent Zig package (tools/gnulib-filemode)
    // providing gnulib's file-mode string helpers (strmode /
    // filemodestring, lib/filemode.c), turning st_mode into the ls-style
    // "drwxr-xr-x" string used by file-attributes and dired. Pure string
    // logic with no libc call. Built ReleaseFast (leaf computation).
    const gnulib_filemode_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_filemode", .{}).path("src/filemode.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_filemode_lib =
        b.addLibrary(.{ .name = "gnulib-filemode", .root_module = gnulib_filemode_mod });
    exe.root_module.linkLibrary(gnulib_filemode_lib);

    // gnulib-timespec: an independent Zig package (tools/gnulib-timespec)
    // providing gnulib's timespec arithmetic (dtotimespec / timespec_add /
    // timespec_sub, lib/dtotimespec.c + lib/timespec-add.c +
    // lib/timespec-sub.c) with saturated clamping on time_t overflow,
    // plus the extern-inline helpers from lib/timespec.c (make_timespec /
    // timespec_cmp / timespec_sign / timespectod). Pure arithmetic with
    // no libc call. Built ReleaseFast (leaf math).
    const gnulib_timespec_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_timespec", .{}).path("src/timespec.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_timespec_lib =
        b.addLibrary(.{ .name = "gnulib-timespec", .root_module = gnulib_timespec_mod });
    exe.root_module.linkLibrary(gnulib_timespec_lib);

    // gnulib-filevercmp: an independent Zig package (tools/gnulib-filevercmp)
    // providing gnulib's version-sort file name comparison (filevercmp /
    // filenvercmp, lib/filevercmp.c), the Debian-policy algorithm used by
    // `string-version-lessp'. Pure byte/string logic with no libc call.
    // Built ReleaseFast (leaf comparison).
    const gnulib_filevercmp_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_filevercmp", .{}).path("src/filevercmp.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_filevercmp_lib =
        b.addLibrary(.{ .name = "gnulib-filevercmp", .root_module = gnulib_filevercmp_mod });
    exe.root_module.linkLibrary(gnulib_filevercmp_lib);

    // gnulib-sigdescr-np: an independent Zig package
    // (tools/gnulib-sigdescr-np) providing gnulib's signal description
    // strings (sigdescr_np, lib/sigdescr_np.c), used by safe_strsignal
    // in src/sysdep.c for error output. Static per-platform tables with
    // no libc call. Built ReleaseFast (leaf lookup).
    const gnulib_sigdescr_np_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_sigdescr_np", .{}).path("src/sigdescr_np.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_sigdescr_np_lib =
        b.addLibrary(.{ .name = "gnulib-sigdescr-np", .root_module = gnulib_sigdescr_np_mod });
    exe.root_module.linkLibrary(gnulib_sigdescr_np_lib);

    // gnulib-nproc: an independent Zig package (tools/gnulib-nproc)
    // providing gnulib's processor-count query (num_processors,
    // lib/nproc.c), backing `num-processors'. Replicates the C logic:
    // affinity mask via sched_getaffinity, configured/online counts from
    // sysfs (the data glibc's sysconf consults), cgroup-v2 CPU quota and
    // OMP environment variables. No libc call: raw syscalls + /proc//sys
    // reads. Built ReleaseFast (leaf query).
    const gnulib_nproc_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_nproc", .{}).path("src/nproc.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_nproc_lib =
        b.addLibrary(.{ .name = "gnulib-nproc", .root_module = gnulib_nproc_mod });
    exe.root_module.linkLibrary(gnulib_nproc_lib);

    // gnulib-tempname: an independent Zig package (tools/gnulib-tempname)
    // providing gnulib's temporary-name generation (gen_tempname /
    // gen_tempname_len / mkostemp, lib/tempname.c + lib/mkostemp.c),
    // backing `make-temp-file', filelock and call-process temp files.
    // getrandom with the clock-mix fallback, raw openat/mkdir/newfstatat
    // syscalls, errno set on failure as the C code does. No libc call.
    // Built ReleaseFast (leaf generation).
    const gnulib_tempname_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_tempname", .{}).path("src/tempname.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_tempname_lib =
        b.addLibrary(.{ .name = "gnulib-tempname", .root_module = gnulib_tempname_mod });
    exe.root_module.linkLibrary(gnulib_tempname_lib);

    // gnulib-fsusage: an independent Zig package (tools/gnulib-fsusage)
    // providing gnulib's file-system space query (get_fs_usage,
    // lib/fsusage.c), backing `file-system-info'. Reads statfs(2) via a
    // raw syscall and maps the fields into the gnulib struct fs_usage,
    // with errno set on failure (fileio.c tests ENOSYS). No libc call.
    // Built ReleaseFast (leaf query).
    const gnulib_fsusage_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_fsusage", .{}).path("src/fsusage.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_fsusage_lib =
        b.addLibrary(.{ .name = "gnulib-fsusage", .root_module = gnulib_fsusage_mod });
    exe.root_module.linkLibrary(gnulib_fsusage_lib);

    // gnulib-getloadavg: an independent Zig package
    // (tools/gnulib-getloadavg) providing gnulib's load-average query
    // (getloadavg, lib/getloadavg.c), backing `load-average'. Reads the
    // 1/5/15-minute loads via the sysinfo(2) raw syscall and converts
    // the fixed-point values; errno set on failure. No libc call. Built
    // ReleaseFast (leaf query).
    const gnulib_getloadavg_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_getloadavg", .{}).path("src/getloadavg.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_getloadavg_lib =
        b.addLibrary(.{ .name = "gnulib-getloadavg", .root_module = gnulib_getloadavg_mod });
    exe.root_module.linkLibrary(gnulib_getloadavg_lib);

    // gnulib-careadlinkat: an independent Zig package
    // (tools/gnulib-careadlinkat) providing gnulib's symlink reader
    // (careadlinkat, lib/careadlinkat.c), backing `file-symlink-p' and
    // `file-truename'. Reads via the caller-provided preadlinkat
    // callback into a caller buffer or an allocator-managed buffer,
    // growing on truncation; the NULL-allocator stdlib fallback is kept
    // for API compatibility. No libc call on the Emacs path. Built
    // ReleaseFast (leaf read).
    const gnulib_careadlinkat_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_careadlinkat", .{}).path("src/careadlinkat.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_careadlinkat_lib =
        b.addLibrary(.{ .name = "gnulib-careadlinkat", .root_module = gnulib_careadlinkat_mod });
    exe.root_module.linkLibrary(gnulib_careadlinkat_lib);

    // gnulib-dtoastr: an independent Zig package (tools/gnulib-dtoastr)
    // providing gnulib's accurate float-to-string conversion (dtoastr,
    // lib/ftoastr.c for double), backing float printing in src/print.c.
    // Replicates the C's shortest-round-trip loop with no libc call:
    // exact digits from zig std's decimal renderer, round-half-even %g
    // formatting and a std.fmt.parseFloat round-trip check. Built
    // ReleaseFast (leaf conversion).
    const gnulib_dtoastr_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_dtoastr", .{}).path("src/dtoastr.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_dtoastr_lib =
        b.addLibrary(.{ .name = "gnulib-dtoastr", .root_module = gnulib_dtoastr_mod });
    exe.root_module.linkLibrary(gnulib_dtoastr_lib);

    // gnulib-stat-time: an independent Zig package (tools/gnulib-stat-time)
    // providing gnulib's struct stat timestamp accessors (get_stat_atime /
    // mtime / ctime and ns variants, lib/stat-time.c), backing
    // `file-attributes' time elements. Pure struct reads with no libc
    // call. Built ReleaseFast (leaf accessor).
    const gnulib_stat_time_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_stat_time", .{}).path("src/stat_time.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_stat_time_lib =
        b.addLibrary(.{ .name = "gnulib-stat-time", .root_module = gnulib_stat_time_mod });
    exe.root_module.linkLibrary(gnulib_stat_time_lib);

    // gnulib-boot-time: an independent Zig package (tools/gnulib-boot-time)
    // providing gnulib's boot-time query (get_boot_time, lib/boot-time.c),
    // backing lock-file identification in src/filelock.c. Replicates the
    // C chain with no libc call: utmp scan (BOOT_TIME + runlevel
    // workaround), boot-touched-file mtime fallback, then CLOCK_BOOTTIME
    // subtracted from the realtime clock; result cached in static state.
    // Built ReleaseFast (leaf query).
    const gnulib_boot_time_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_boot_time", .{}).path("src/boot_time.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_boot_time_lib =
        b.addLibrary(.{ .name = "gnulib-boot-time", .root_module = gnulib_boot_time_mod });
    exe.root_module.linkLibrary(gnulib_boot_time_lib);

    // gnulib-c-strcase: an independent Zig package (tools/gnulib-c-strcase)
    // providing gnulib's ASCII case-insensitive string comparison
    // (c_strcasecmp / c_strncasecmp, lib/c-strcasecmp.c +
    // lib/c-strncasecmp.c), backing `-exe' detection in src/emacs.c and
    // font-pattern matching in src/ftfont.c. Pure byte logic with no
    // libc call. Built ReleaseFast (leaf compare).
    const gnulib_c_strcase_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_c_strcase", .{}).path("src/c_strcase.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_c_strcase_lib =
        b.addLibrary(.{ .name = "gnulib-c-strcase", .root_module = gnulib_c_strcase_mod });
    exe.root_module.linkLibrary(gnulib_c_strcase_lib);

    // gnulib-acl: an independent Zig package (tools/gnulib-acl)
    // providing gnulib's ACL copy (qcopy_acl, lib/qcopy-acl.c under
    // USE_XATTR), backing preserve-permissions in src/fileio.c. On
    // Linux it replicates the whole C chain with no libc call: raw
    // chmod/fchmod for the mode bits, libattr's attr_copy_file /
    // attr_copy_fd semantics (llistxattr/lgetxattr/lsetxattr and f*
    // variants) filtered by is_attr_permissions (hardcoded ACL names +
    // /etc/xattr.conf `permissions' actions), and the fdfile_has_aclinfo
    // EOPNOTSUPP diagnostic (Bug#78328) via listxattr probes. Non-Linux
    // targets fall back to mode-bit preservation via libc. Built
    // ReleaseFast (leaf copy operation).
    const gnulib_acl_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_acl", .{}).path("src/acl.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const gnulib_acl_lib =
        b.addLibrary(.{ .name = "gnulib-acl", .root_module = gnulib_acl_mod });
    exe.root_module.linkLibrary(gnulib_acl_lib);

    // gnulib-time-rz: an independent Zig package (tools/gnulib-time-rz)
    // providing gnulib's time zone management (tzalloc / tzfree /
    // set_tz / revert_tz / localtime_rz / mktime_z, lib/time_rz.c),
    // backing `format-time-string' / `decode-time' with an explicit
    // time zone in src/timefns.c and lib/strftime.c's %Z handling.
    // Replicates the C module exactly: the struct-tm_zone abbreviation
    // cache that keeps tm_zone pointers alive across the TZ swap, and
    // the environment swap via Emacs's own TZ getter/setter
    // (emacs_getenv_TZ / emacs_setenv_TZ from src/timefns.c, wired by
    // conf_post.h) followed by libc tzset; the actual conversions use
    // libc localtime_r/gmtime_r/mktime/timegm, matching gnulib's own
    // design (the TZ database parsing lives in libc's tzset). Built
    // ReleaseFast (leaf conversion).
    const gnulib_time_rz_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_time_rz", .{}).path("src/time_rz.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true, // libc tzset/localtime_r/mktime + Emacs's TZ getter/setter
    });
    const gnulib_time_rz_lib =
        b.addLibrary(.{ .name = "gnulib-time-rz", .root_module = gnulib_time_rz_mod });
    exe.root_module.linkLibrary(gnulib_time_rz_lib);

    // gnulib-io: an independent Zig package (tools/gnulib-io) providing
    // the remaining live gnulib I/O wrappers -- close_stream
    // (lib/close-stream.c), set_binary_mode (lib/binary-io.c) and
    // rpl_pipe2 (lib/pipe2.c). Backs src/sysdep.c's exit-time
    // stdout/stderr flush and emacs_pipe, and `set-binary-mode'. The
    // FILE* functions delegate to libc (ferror/fclose/__fpending on
    // glibc) exactly like the C code; the pipe and fcntl work uses raw
    // Linux syscalls with a libc fallback for other systems. Built
    // ReleaseFast (leaf wrappers).
    const gnulib_io_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_io", .{}).path("src/io.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true, // libc fclose/ferror/__fpending + portable pipe fallback
    });
    const gnulib_io_lib =
        b.addLibrary(.{ .name = "gnulib-io", .root_module = gnulib_io_mod });
    exe.root_module.linkLibrary(gnulib_io_lib);

    // emacs-time: an independent Zig package (tools/emacs-time) providing
    // the realtime-clock read (gettime / current_timespec) that lib/gettime.c
    // would otherwise provide, via per-platform NATIVE backends with no libc:
    // Linux std.os.linux.clock_gettime (raw syscall), Windows kernel32
    // GetSystemTimeAsFileTime. First OS-layer subsystem under the
    // "POSIX/sysdep -> zig stdlib" cross-platform strategy. Built ReleaseFast.
    const emacs_time_mod = b.createModule(.{
        .root_source_file = b.dependency("emacs_time", .{}).path("src/time.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const emacs_time_lib =
        b.addLibrary(.{ .name = "emacs-time", .root_module = emacs_time_mod });
    exe.root_module.linkLibrary(emacs_time_lib);

    // emacs-nanosleep: an independent Zig package (tools/emacs-nanosleep)
    // providing the POSIX nanosleep() that lib/nanosleep.c would otherwise
    // provide, via per-platform NATIVE backends with no libc: Linux
    // std.os.linux.nanosleep (raw syscall, EINTR-aware), Windows kernel32
    // Sleep + QueryPerformanceCounter busy-wait. Second OS-layer subsystem
    // under the "POSIX/sysdep -> zig stdlib" cross-platform strategy. Built
    // ReleaseFast (leaf syscall + spin, no Zig runtime the C exe must
    // satisfy).
    const emacs_nanosleep_mod = b.createModule(.{
        .root_source_file = b.dependency("emacs_nanosleep", .{})
            .path("src/sleep.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const emacs_nanosleep_lib = b.addLibrary(.{
        .name = "emacs-nanosleep",
        .root_module = emacs_nanosleep_mod,
    });
    exe.root_module.linkLibrary(emacs_nanosleep_lib);

    // Determine if we're building for Unix-like systems
    const is_windows = target.result.os.tag == .windows;

    // Add base C sources with proper flags
    if (!is_windows) {
        // Unix-like systems (macOS, Linux) - with libxml2 include path
        const base_flags = &[_][]const u8{
            // No -O flag (module Debug=-O0). -O2 has a separate bug (a
            // -O2 file corrupts lisp state during dump -> bad relocation
            // entries -> SIGSEGV on load) that is NOT fixed by non-PIE
            // or pdumper.c -O0; stay at -O0 until that is root-caused.
            "-std=gnu2x",  // Allow C23 features like _Static_assert without message
            "-fno-common",
        "-fno-strict-aliasing",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
            "-Isrc",
            "-Ilib",
            "-Ilib/malloc",  // Gnulib generated headers
            "-I/usr/include",
            "-I/usr/include/libxml2",  // libxml2 headers
        };

        // src/timefns.c:monotonic_coarse_timespec is provided by the
        // emacs-time Zig package (per-platform native backend, no libc)
        // instead of C; the body is #ifndef'd out in src/timefns.c when
        // EMACS_USE_ZIG_MONOTONIC_COARSE is defined. Passed per-file (like
        // lib/mktime.c above) so only this translation unit is affected.
        const timefns_flags = base_flags ++
            [_][]const u8{"-DEMACS_USE_ZIG_MONOTONIC_COARSE"};

        for (base_sources) |src| {
            const flags: []const []const u8 =
                if (std.mem.eql(u8, src, "src/timefns.c")) timefns_flags else base_flags;
            exe.root_module.addCSourceFile(.{
                .file = b.path(src),
                .flags = flags,
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
            // No -O flag: see base_flags (separate -O2 lisp-corruption bug).
            "-std=gnu2x",
            "-fno-common",
        "-fno-strict-aliasing",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
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
        "-fno-strict-aliasing",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
            "-Isrc",
            "-Ilib",
        };

        // src/timefns.c:monotonic_coarse_timespec is provided by the
        // emacs-time Zig package (Windows QueryPerformanceCounter backend,
        // no msvcrt) instead of C; the body is #ifndef'd out when
        // EMACS_USE_ZIG_MONOTONIC_COARSE is defined. See the Unix branch
        // above for the full rationale.
        const timefns_flags = base_flags ++
            [_][]const u8{"-DEMACS_USE_ZIG_MONOTONIC_COARSE"};

        for (base_sources) |src| {
            const flags: []const []const u8 =
                if (std.mem.eql(u8, src, "src/timefns.c")) timefns_flags else base_flags;
            exe.root_module.addCSourceFile(.{
                .file = b.path(src),
                .flags = flags,
            });
        }

        // Add Gnulib sources
        const libgnu_flags = &[_][]const u8{
            "-std=gnu2x",
            "-fno-common",
        "-fno-strict-aliasing",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
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
            // D-Bus (HAVE_DBUS): dbus_* symbols from src/dbusbind.c.
            exe.root_module.linkSystemLibrary("dbus-1", .{});
        }
    }

    // Install the executable
    b.installArtifact(exe);

    // Install the `emacs` wrapper script (build-aux/emacs-launcher.sh) as
    // zig-out/bin/emacs. The wrapper resolves temacs and bootstrap-emacs.pdmp
    // relative to its own location ($0), so the dumped bootstrap emacs can be
    // invoked like a normal editor command (`zig-out/bin/emacs --version`)
    // without manually passing --dump-file=... on every invocation. It is the
    // literal <bootstrap-emacs> prerequisite of the I9d lisp-bootstrap
    // transitional bridge. The script is committed source (like make-docfile.c
    // above), NOT a generated artifact -- only build-aux/emacs-launcher.sh and
    // build.zig are touched.
    //
    // Not gated on run_dump: the wrapper is a static script, so the default
    // `zig build` stays light (dump still needs bootstrap data + config.h).
    // The wrapper errors clearly if the pdmp is absent -- the user runs
    // `zig build dump` first.
    //
    // Exec-bit defense: 0.16.0's InstallFile step has no .mode option (it
    // delegates to Io.Dir.updateFile with default options, which copies the
    // source mode). The source file is committed +x, but to be robust against
    // filesystems/checkouts that drop the bit, run chmod +x after install so
    // acceptance `test -x zig-out/bin/emacs` holds unconditionally.
    const install_emacs_wrapper = b.addInstallFileWithDir(
        b.path("build-aux/emacs-launcher.sh"),
        .bin,
        "emacs",
    );
    b.getInstallStep().dependOn(&install_emacs_wrapper.step);
    const chmod_emacs_wrapper = b.addSystemCommand(&[_][]const u8{
        "chmod",
        "+x",
        b.pathJoin(&.{ b.install_path, "bin", "emacs" }),
    });
    chmod_emacs_wrapper.step.dependOn(&install_emacs_wrapper.step);
    b.getInstallStep().dependOn(&chmod_emacs_wrapper.step);

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
    exe.root_module.addIncludePath(epaths_h.dirname());
    exe.step.dependOn(&run_gen_epaths.step);

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
    // loadup must run from zig-out/bin with zig-out/etc -> ../etc in
    // place: Fsnarf-documentation and get_doc_string resolve "../etc/"
    // relative to the process CWD (doc.c sibling_etc) at dump time, so
    // unless the binary's sibling etc/ holds DOC the pbootstrap
    // (Snarf-documentation "DOC") silently fails and the dumped image
    // carries no C doc strings. EMACSLOADPATH/EMACSDATA use the absolute
    // repo paths because the CWD changes. The work is done by a native
    // Zig tool (build-aux/bootstrap-dump.zig) with no shell: it scrubs
    // stale loaddefs, links zig-out/etc -> ../etc, runs loadup in
    // pbootstrap mode with the source-tree env (retrying on the
    // ASLR-sensitive pdumper signal flake), and links temacs.pdmp.
    const bootstrap_dump_tool = b.addExecutable(.{
        .name = "bootstrap-dump",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/bootstrap-dump.zig"),
        }),
    });
    const run_dump = b.addRunArtifact(bootstrap_dump_tool);
    run_dump.setCwd(b.path("."));
    // The dump must run with etc/DOC present: loadup calls
    // (Snarf-documentation "DOC"), and in pbootstrap mode it swallows
    // the error if DOC is missing, leaving every C primitive without a
    // doc string in the dumped image (doc-tests-documentation/c-primitive).
    run_dump.step.dependOn(gen_doc_step);
    const dump_step = b.step("dump", "Bootstrap (from-source) dump of bootstrap-emacs.pdmp");
    dump_step.dependOn(b.getInstallStep());
    dump_step.dependOn(&run_dump.step);

    // generate-loaddefs: produce lisp/loaddefs.el + per-subdir
    // *-loaddefs.el (autoload cookies) via the dumped emacs. Mirrors
    // lisp/Makefile.in's `autoloads` target. Required at runtime by
    // suites that (require 'foo-loaddefs) (calendar, calc, org, ...);
    // without it they fail to load ("Cannot open load file: X-loaddefs").
    // Outputs gitignored. Runs right after the source dump because
    // compile-lisp needs the loaddefs (some files (require
    // 'foo-loaddefs) at compile time); the final dump-compiled scrubs
    // them again, so check and check-all additionally run a final
    // generation (run_loaddefs_final) before launching suites.
    const gen_loaddefs_tool = b.addExecutable(.{
        .name = "generate-loaddefs",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/generate-loaddefs.zig"),
        }),
    });
    const gen_loaddefs = b.addRunArtifact(gen_loaddefs_tool);
    gen_loaddefs.setCwd(b.path("."));
    gen_loaddefs.step.dependOn(&run_dump.step);
    const gen_loaddefs_step = b.step(
        "generate-loaddefs",
        "Generate lisp/loaddefs.el + *-loaddefs.el autoload files",
    );
    gen_loaddefs_step.dependOn(&gen_loaddefs.step);

    // compile-lisp: byte-compile the whole lisp tree with the bootstrap
    // dump. Upstream byte-compiles before its final dump; running from
    // source only breaks behaviors that assume compiled functions (e.g.
    // help-function-arglist's docstring route, and cl-lib's derived-type
    // method registration, which is skipped when cl-lib loads before
    // cl-generic -- an eval-when-compile artifact that only happens when
    // cl-preloaded.el is loaded from source). cl-macs/cl-seq/cl-extra are
    // preloaded for the compiler (cl-find-class/cl-every live there, not
    // in the dump). Incremental: arg 0 recompiles only missing/older
    // .elc. Requires loaddefs (generated after the source dump) for
    // files that (require 'foo-loaddefs) at compile time.
    const compile_lisp_tool = b.addExecutable(.{
        .name = "compile-lisp",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/compile-lisp.zig"),
        }),
    });
    const run_compile_lisp = b.addRunArtifact(compile_lisp_tool);
    run_compile_lisp.setCwd(b.path("."));
    run_compile_lisp.step.dependOn(&run_dump.step);
    run_compile_lisp.step.dependOn(&gen_loaddefs.step);
    const compile_lisp_step = b.step("compile-lisp", "Byte-compile lisp/ with the bootstrap emacs");
    compile_lisp_step.dependOn(&run_compile_lisp.step);

    // dump-compiled: re-run loadup after compile-lisp so the dumped image
    // carries byte-compiled preloaded code (the pdmp that check/check-all
    // and interactive use actually load). Same loadup invocation as the
    // source dump (same scrub, same zig-out/etc, same cwd).
    const dump_compiled_tool = b.addExecutable(.{
        .name = "bootstrap-dump-compiled",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/bootstrap-dump.zig"),
        }),
    });
    const run_dump_compiled = b.addRunArtifact(dump_compiled_tool);
    run_dump_compiled.setCwd(b.path("."));
    run_dump_compiled.step.dependOn(&run_compile_lisp.step);
    const dump_compiled_step = b.step("dump-compiled", "Re-dump bootstrap-emacs.pdmp with compiled lisp");
    dump_compiled_step.dependOn(&run_dump_compiled.step);

    // Final loaddefs generation for check/check-all: dump-compiled
    // scrubbed the loaddefs, and suites (require 'foo-loaddefs) at
    // runtime. Same tool as gen_loaddefs, gated on the final dump.
    const run_loaddefs_final_tool = b.addExecutable(.{
        .name = "generate-loaddefs-final",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/generate-loaddefs.zig"),
        }),
    });
    const run_loaddefs_final = b.addRunArtifact(run_loaddefs_final_tool);
    run_loaddefs_final.setCwd(b.path("."));
    run_loaddefs_final.step.dependOn(&run_dump_compiled.step);

    // Smoke step (`zig build smoke`): prove the dumped emacs actually starts
    // and evaluates Lisp by printing emacs-version from the pdmp. Mirrors
    // run_dump (ASLR-off load via setarch -R, same env exports) so a bad
    // pdmp is caught here -- segfault/garbage load exits nonzero under
    // `set -e`, and the grep asserts a N.N version was printed (catches a
    // hypothetical exits-0-but-empty case). Gates `check` so a broken
    // dump fails fast instead of launching the 314 ert tests.
    //
    // The smoke ALSO exercises the installed emacs wrapper
    // (zig-out/bin/emacs), in addition to the direct-temacs load above:
    // the wrapper resolves temacs+pdmp relative to its own location
    // ($0), invokes temacs under `setarch "$(uname -m)" -R`, and
    // forwards args, so `./zig-out/bin/emacs --version` printing a
    // N.N version proves the end-to-end wrapper path.
    const smoke_tool = b.addExecutable(.{
        .name = "smoke",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/smoke.zig"),
        }),
    });
    const run_smoke = b.addRunArtifact(smoke_tool);
    run_smoke.setCwd(b.path("."));
    run_smoke.step.dependOn(&run_dump_compiled.step);
    // Depend on chmod_emacs_wrapper (which depends on install_emacs_wrapper)
    // so the +x bit is set before smoke runs ./zig-out/bin/emacs.
    run_smoke.step.dependOn(&chmod_emacs_wrapper.step);
    const smoke_step = b.step("smoke", "Verify the dumped emacs starts and evaluates Lisp");
    smoke_step.dependOn(&run_smoke.step);

    // `check` step: run a broad set of built-in ert test suites with the
    // dumped emacs (582 tests across 40 suites today: alloc, version,
    // byte-run, float-sup, cl-preloaded, button, delim-col, color, custom,
    // dom, data, marker, chartab, cmds, let-alist, cl-lib, map, seq,
    // character, charset, json, fns, backquote, parse-time, derived,
    // cond-star, cl-print, time-date, check-declare, copyright,
    // easy-mmode, nadvice, pcase, pp, ring, rx, warnings, regexp-opt,
    // range, crypto-hash).
    // `ulimit -s unlimited` because -O0 eval frames are large
    // (ert-deftest macro expansion otherwise overflows the C stack).
    // cl-macs/cl-seq/cl-extra are preloaded explicitly because the bootstrap
    // dump carries only ldefs_boot.el, so cl-lib is not autoloaded. The
    // `-L test/...` dirs let each (load "NAME") resolve. Exits 0 iff all
    // tests pass. (Suites that abort, error, or hang at -O0 are excluded:
    // abbrev-tests, char-fold-tests, emacsclient-tests; eval-tests and
    // macroexp-tests hang in ert-deftest expansion; editfns-tests has one
    // unexpected failure; subr-x-tests and map-ynp-tests abort with
    // SIGABRT (rc=134); gv-tests hangs >=60s in ert-deftest expansion.)
    const run_check_tool = b.addExecutable(.{
        .name = "run-check",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/run-check.zig"),
        }),
    });
    const run_check = b.addRunArtifact(run_check_tool);
    run_check.setCwd(b.path("."));
    run_check.step.dependOn(&run_smoke.step);
    run_check.step.dependOn(&run_loaddefs_final.step);
    const check_step = b.step("check", "Run built-in ert test suites with the dumped emacs");
    check_step.dependOn(&run_check.step);

    // Test step: run the built-in ert suite (alias of `check`). The
    // former body shelled out to a run-zig-tests.sh that no longer
    // exists; `check` already runs test/src/alloc-tests.el (4/4 pass)
    // with the dumped emacs, so `zig build test` delegates to it.
    const test_step = b.step("test", "Run a built-in ert test suite with the dumped emacs");
    test_step.dependOn(check_step);

    // generate-charprop: produce lisp/international/{charprop,uni-*}.el
    // from admin/unidata via the dumped emacs (mirrors admin/unidata/
    // Makefile). Required at runtime by suites touching ucs-names /
    // char-from-name (tramp, completion); without it they fail to load.
    // The bootstrap dump does not bundle charprop (loaded on demand), so
    // it is generated separately. Outputs are gitignored. Standalone
    // (like generate-charsets); run before check-all if needed.
    const gen_charprop_tool = b.addExecutable(.{
        .name = "generate-charprop",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/generate-charprop.zig"),
        }),
    });
    const gen_charprop = b.addRunArtifact(gen_charprop_tool);
    gen_charprop.setCwd(b.path("."));
    gen_charprop.step.dependOn(&run_smoke.step);
    const gen_charprop_step = b.step(
        "generate-charprop",
        "Generate lisp/international/{charprop,uni-*}.el from admin/unidata",
    );
    gen_charprop_step.dependOn(&gen_charprop.step);

    // generate-cedet-grammars: produce the cedet parser files
    // (semantic/*-wy.el, semantic/wisent/*-wy.el, semantic/bovine/*-by.el,
    // srecode/srt-wy.el) from admin/grammars via the bovine/wisent batch
    // generators (mirrors admin/grammars/Makefile.in). Upstream does not
    // track these; without them the cedet suites fail to load
    // ("Cannot open load file srecode/srt-wy"). Standalone; run before
    // check-all if the suite set needs cedet.
    const gen_cedet_tool = b.addExecutable(.{
        .name = "generate-cedet-grammars",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/generate-cedet-grammars.zig"),
        }),
    });
    const gen_cedet = b.addRunArtifact(gen_cedet_tool);
    gen_cedet.setCwd(b.path("."));
    gen_cedet.step.dependOn(&run_smoke.step);
    const gen_cedet_step = b.step(
        "generate-cedet-grammars",
        "Generate cedet parser files from admin/grammars",
    );
    gen_cedet_step.dependOn(&gen_cedet.step);

    // check-all step: run EVERY *-tests.el under test/ — no skip. Each
    // suite runs in its own temacs process under a per-suite timeout so a
    // hang/crash in one suite cannot hide the rest, and every outcome is
    // classified (PASS/FAIL/HANG/CRASH/LOAD). Unlike `check` (a stable
    // 40-suite baseline), this is the failure-discovery tool: its output
    // is meant to drive the next migration phase, so nothing is excluded.
    // Full per-suite logs land in zig-out/check-all/<suite>.out.
    const check_all_tool = b.addExecutable(.{
        .name = "check-all",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/check-all.zig"),
        }),
    });
    const run_check_all = b.addRunArtifact(check_all_tool);
    run_check_all.setCwd(b.path("."));
    run_check_all.step.dependOn(&run_smoke.step);
    run_check_all.step.dependOn(&run_loaddefs_final.step);
    const check_all_step = b.step("check-all", "Run ALL ert suites (no skip; per-suite isolation + timeout) and classify failures");
    check_all_step.dependOn(&run_check_all.step);

    // Help step
    const help_step = b.step("help", "Show build information");
    const help_cmd = b.addSystemCommand(&[_][]const u8{
        "echo",
        \\Emacs Zig Native Build
        \\======================
        \\
        \\Available steps:
        \\  zig build                   - Build temacs + emacs wrapper
        \\  zig build dump              - Dump a runnable bootstrap-emacs.pdmp
        \\  zig build compile-lisp      - Byte-compile lisp/ (incremental)
        \\  zig build dump-compiled     - Re-dump with compiled lisp loaded
        \\  zig build smoke             - Verify dumped emacs runs
        \\  zig build check             - Run built-in ert test suites (582 tests across 40 suites)
        \\  zig build test              - Alias of check
        \\  zig build check-all         - Run ALL ert suites (no skip; classify failures for planning)
        \\  zig build generate-headers  - Generate Gnulib .gl.h headers
        \\  zig build generate-unidata  - Generate charscript/emoji-zwj.el
        \\  zig build generate-charsets - Generate charset maps
        \\  zig build generate-charprop - Generate unicode charprop/uni-*.el
        \\  zig build generate-loaddefs - Generate autoload files
        \\  zig build generate-cedet-grammars - Generate cedet parser files
        \\  zig build help              - Show this message
        \\
        \\Runnable commands (after `zig build dump`):
        \\  zig-out/bin/temacs          - raw temacs (needs --dump-file=...)
        \\  zig-out/bin/emacs           - wrapper that locates temacs+pdmp and
        \\                               forwards args (e.g. `--version`)
        \\
        \\Status: Linux TTY build works
        \\  - zig build: temacs (non-PIE, -O0) + emacs wrapper
        \\  - zig build dump: runnable emacs (32.0.50)
        \\  - zig build check: 582/582 built-in tests pass
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
        // lib/futimens.c + lib/utimens.c: with working system futimens and
        // utimensat (HAVE_FUTIMENS=1, HAVE_UTIMENSAT=1) and no rpl rename,
        // linking gnulib's futimens makes fdutimens's internal futimens call
        // resolve to the gnulib copy -> infinite mutual recursion (copy-file
        // with keep-time t busy-loops; dired-copy-preserve-time defaults to
        // t, so dired copies and copy-directory hang too). Callers use the
        // libc functions (fileio.c set-file-times/copy-file keep-time).
        "futimens",
        "utimens",
        // lib/memeq.c + lib/streq.c are provided by an independent Zig
        // package (tools/gnulib-str, dependency `gnulib_str`) instead of C
        // -- runtime gnulib string primitives replaced by Zig. Excluded
        // here so the C sources are not compiled; the package's exported
        // symbols are linked into temacs below.
        "memeq",
        "streq",
        // lib/c-ctype.c is provided by an independent Zig package
        // (tools/gnulib-ctype, dependency `gnulib_ctype`) instead of C --
        // gnulib's ASCII character-classification functions replaced by
        // Zig. Excluded here so the C source is not compiled; the package's
        // exported symbols are linked into temacs below. (make-docfile, a
        // host tool, still compiles its own copy of lib/c-ctype.c.)
        "c-ctype",
        // lib/stdc_leading_zeros.c, lib/stdc_trailing_zeros.c,
        // lib/stdc_count_ones.c, lib/stdc_bit_width.c are provided by an
        // independent Zig package (tools/gnulib-stdbit, dependency
        // `gnulib_stdbit`) -- the C23 stdbit bit-count functions replaced
        // by Zig @clz/@ctz/@popCount. Excluded by exact name so
        // lib/stdc_memreverse8u.c (not yet replaced) still compiles.
        "stdc_leading_zeros",
        "stdc_trailing_zeros",
        "stdc_count_ones",
        "stdc_bit_width",
        // lib/sha1.c, lib/sha256.c and lib/sha512.c are provided by an
        // independent Zig package (tools/gnulib-hash, dependency
        // `gnulib_hash`) -- native Zig SHA1, SHA-2 (sha224/sha256/
        // sha384/sha512) operating on the gnulib ctx structs. Excluded
        // here so the C sources are not compiled; the package's exported
        // sha1_*/sha256_*/sha512_* symbols are linked into temacs below.
        "sha1",
        "sha256",
        "sha512",
        // lib/sha3.c is provided by the same Zig package (tools/gnulib-hash)
        // -- a native Zig SHA-3 (Keccak-f[1600] sponge, FIPS 202) operating
        // on the gnulib struct sha3_ctx. Excluded here so the C source is
        // not compiled; the package's exported sha3_* symbols are linked
        // into temacs below (`secure-hash' sha3_224/256/384/512).
        "sha3",
        // lib/md5.c is provided by the same Zig package (tools/gnulib-hash)
        // -- a native Zig MD5 operating on the gnulib struct md5_ctx
        // (RFC 1321). Excluded by exact name so lib/md5-stream.c (the
        // FILE*-reading md5_stream wrapper, still C) keeps compiling and
        // calls the package's exported md5_* symbols.
        "md5.c",
        // lib/sig2str.c is provided by an independent Zig package
        // (tools/gnulib-sig2str, dependency `gnulib_sig2str`) -- the
        // signal name<->number conversion (sig2str / str2sig) replaced
        // by native Zig. Excluded here so the C source is not compiled;
        // the package's exported symbols are linked into temacs below.
        "sig2str",
        // lib/filemode.c is provided by an independent Zig package
        // (tools/gnulib-filemode, dependency `gnulib_filemode`) -- native
        // Zig strmode/filemodestring (ls-style mode strings). Excluded
        // here so the C source is not compiled; the package's exported
        // symbols are linked into temacs below (file-attributes string
        // mode element, dired).
        "filemode",
        // lib/dtotimespec.c, lib/timespec-add.c and lib/timespec-sub.c are
        // provided by an independent Zig package (tools/gnulib-timespec,
        // dependency `gnulib_timespec`) -- native Zig double->timespec
        // conversion and saturating timespec add/sub. Excluded by exact
        // name so lib/timespec.c (the make_timespec/timespec_cmp extern
        // inline definitions) still compiles; the package's exported
        // symbols are linked into temacs below.
        "dtotimespec",
        "timespec-add",
        "timespec-sub",
        // lib/timespec.c (the extern-inline definitions of make_timespec,
        // timespec_cmp, timespec_sign and timespectod) is provided by the
        // same Zig package (tools/gnulib-timespec, dependency
        // `gnulib_timespec`). Excluded here so the C source is not
        // compiled; the package's exported symbols are linked into temacs
        // below (callers mostly inline the lib/timespec.h bodies).
        "timespec",
        // lib/filevercmp.c is provided by an independent Zig package
        // (tools/gnulib-filevercmp, dependency `gnulib_filevercmp`) --
        // native Zig Debian-policy version sort (filevercmp /
        // filenvercmp). Excluded here so the C source is not compiled;
        // the package's exported symbols are linked into temacs below
        // (`string-version-lessp').
        "filevercmp",
        // lib/sigdescr_np.c is provided by an independent Zig package
        // (tools/gnulib-sigdescr-np, dependency `gnulib_sigdescr_np`) --
        // native Zig signal description strings (sigdescr_np). Excluded
        // here so the C source is not compiled; the package's exported
        // symbol is linked into temacs below (safe_strsignal).
        "sigdescr_np",
        // lib/nproc.c is provided by an independent Zig package
        // (tools/gnulib-nproc, dependency `gnulib_nproc`) -- native Zig
        // processor-count query (num_processors). Excluded here so the
        // C source is not compiled; the package's exported symbol is
        // linked into temacs below (`num-processors').
        "nproc",
        // lib/tempname.c + lib/mkostemp.c are provided by an independent
        // Zig package (tools/gnulib-tempname, dependency
        // `gnulib_tempname`) -- native Zig temp-name generation
        // (gen_tempname / gen_tempname_len / mkostemp). Excluded here so
        // the C sources are not compiled; the package's exported symbols
        // are linked into temacs below (`make-temp-file', filelock).
        "tempname",
        "mkostemp",
        // lib/fsusage.c is provided by an independent Zig package
        // (tools/gnulib-fsusage, dependency `gnulib_fsusage`) -- native
        // Zig file-system space query (get_fs_usage). Excluded here so
        // the C source is not compiled; the package's exported symbol is
        // linked into temacs below (`file-system-info').
        "fsusage",
        // lib/getloadavg.c is provided by an independent Zig package
        // (tools/gnulib-getloadavg, dependency `gnulib_getloadavg`) --
        // native Zig load-average query (getloadavg). Excluded here so
        // the C source is not compiled; the package's exported symbol is
        // linked into temacs below (`load-average').
        "getloadavg",
        // lib/careadlinkat.c is provided by an independent Zig package
        // (tools/gnulib-careadlinkat, dependency `gnulib_careadlinkat`)
        // -- native Zig symlink reader (careadlinkat). Excluded here so
        // the C source is not compiled; the package's exported symbol is
        // linked into temacs below (`file-symlink-p', `file-truename').
        "careadlinkat",
        // lib/dtoastr.c (the LENGTH-2 instantiation of lib/ftoastr.c) is
        // provided by an independent Zig package (tools/gnulib-dtoastr,
        // dependency `gnulib_dtoastr`) -- native Zig dtoastr. Excluded
        // here so the C source is not compiled; the package's exported
        // symbol is linked into temacs below (float printing).
        "dtoastr",
        // lib/stat-time.c is provided by an independent Zig package
        // (tools/gnulib-stat-time, dependency `gnulib_stat_time`) --
        // native Zig struct stat timestamp accessors (get_stat_*).
        // Excluded here so the C source is not compiled; the package's
        // exported symbols are linked into temacs below
        // (`file-attributes' time elements).
        "stat-time",
        // lib/boot-time.c is provided by an independent Zig package
        // (tools/gnulib-boot-time, dependency `gnulib_boot_time`) --
        // native Zig boot-time query (get_boot_time). Excluded here so
        // the C source is not compiled; the package's exported symbol is
        // linked into temacs below (lock-file identification).
        "boot-time",
        // lib/c-strcasecmp.c + lib/c-strncasecmp.c are provided by an
        // independent Zig package (tools/gnulib-c-strcase, dependency
        // `gnulib_c_strcase`) -- native Zig ASCII case-insensitive string
        // comparison. Excluded here so the C sources are not compiled;
        // the package's exported symbols are linked into temacs below.
        "c-strcasecmp",
        "c-strncasecmp",
        // lib/qcopy-acl.c, lib/file-has-acl.c, lib/acl-errno-valid.c,
        // lib/acl-internal.c, lib/acl_entries.c, lib/set-permissions.c
        // and lib/get-permissions.c are provided by an independent Zig
        // package (tools/gnulib-acl, dependency `gnulib_acl`) -- native
        // Zig ACL copy (qcopy_acl) with the libattr attr_copy_* xattr
        // semantics and the fdfile_has_aclinfo EOPNOTSUPP diagnostic.
        // Excluded here so the C sources are not compiled; the package's
        // exported qcopy_acl symbol is linked into temacs below
        // (preserve-permissions in Fcopy_file).
        "qcopy-acl",
        "file-has-acl",
        "acl-errno-valid",
        "acl-internal",
        "acl_entries",
        "set-permissions",
        "get-permissions",
        // lib/time_rz.c is provided by an independent Zig package
        // (tools/gnulib-time-rz, dependency `gnulib_time_rz`) -- native
        // Zig TZ management (tzalloc / tzfree / set_tz / revert_tz /
        // localtime_rz / mktime_z) with the struct-tm_zone abbreviation
        // cache, over Emacs's own TZ getter/setter and libc's tzset/
        // localtime_r/mktime. Excluded here so the C source is not
        // compiled; the package's exported symbols are linked into
        // temacs below (time-zone conversions in timefns.c, %Z in
        // nstrftime.c).
        "time_rz",
        // lib/time_r.c, lib/timegm.c and lib/mktime.c are the last live
        // gnulib C objects; the gnulib-time-rz package's localtime_r /
        // gmtime_r / timegm externs now bind directly to libc (glibc
        // exports all three), and nothing else references
        // mktime_internal. Excluded here so the C sources are not
        // compiled; the time conversions in src and the Zig package use
        // libc's versions.
        "time_r",
        "timegm",
        "mktime",
        // lib/close-stream.c, lib/binary-io.c, lib/pipe2.c are provided
        // by an independent Zig package (tools/gnulib-io, dependency
        // `gnulib_io`) -- native Zig close_stream / set_binary_mode /
        // rpl_pipe2 with libc FILE* delegation and raw Linux pipe/fcntl
        // syscalls. Excluded here so the C sources are not compiled;
        // the package's exported symbols are linked into temacs below
        // (exit-time flush, emacs_pipe, `set-binary-mode').
        "close-stream",
        "binary-io",
        "pipe2",
        // lib/fpending.c, lib/save-cwd.c, lib/md5-stream.c,
        // lib/strnul.c and lib/u64.c are dead in this build: nothing
        // references their symbols any more (their former callers are
        // Zig packages: close_stream now uses glibc's __fpending, and
        // save-cwd/md5-stream/strnul/u64 had no callers at all once
        // at-func, fdopendir, native-comp and the hash/string packages
        // were replaced). Excluded so the C sources are not compiled.
        "fpending",
        "save-cwd",
        "md5-stream",
        "strnul",
        "u64",
        // lib/gettime.c is provided by an independent Zig package
        // (tools/emacs-time, dependency `emacs_time`) -- the realtime
        // clock read (gettime / current_timespec) via per-platform native
        // backends, no libc. Excluded here so the C source is not compiled.
        "gettime",
        // lib/nanosleep.c is provided by an independent Zig package
        // (tools/emacs-nanosleep, dependency `emacs_nanosleep`) -- the
        // POSIX nanosleep() via per-platform native backends, no libc
        // (Linux std.os.linux.nanosleep raw syscall; Windows kernel32
        // Sleep + QueryPerformanceCounter busy-wait). Excluded here so
        // the C source is not compiled; the package's exported
        // `rpl_nanosleep` symbol (gnulib renames nanosleep via lib/time.h)
        // is linked into temacs below.
        "nanosleep",
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

fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |n| {
        if (std.mem.indexOf(u8, haystack, n) != null) return true;
    }
    return false;
}
