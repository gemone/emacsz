const std = @import("std");
const config_overrides = @import("config-overrides.zig");

// Canonical GNU-style configuration string for the build target
// (EMACS_CONFIGURATION); autoconf derives the same value from the host
// triple (e.g. aarch64-apple-darwin25.3.0).  Zig reports the OS
// micro-version separately, so the versionless canonical form is used;
// nothing in lisp or C keys off the version suffix.
// The Windows triple MUST carry the real ABI suffix: Vsystem_configuration
// feeds hash_zeln_abi (compz.c), so a gnu-hardcoded triple makes the msvc
// and gnu backends share one .zeln cache dir and each load the OTHER
// backend's native objects (msvc .zeln import api-ms-win-crt-*; gnu ones
// do not) -> "Cannot open load file"/"End of file during parsing" on the
// 8 resource-loading tests under check-zeln.  Mirror the ABI tag exactly.
fn canonicalConfiguration(t: std.Target, allocator: std.mem.Allocator) []const u8 {
    return switch (t.os.tag) {
        .macos => std.fmt.allocPrint(allocator, "{s}-apple-darwin", .{@tagName(t.cpu.arch)}) catch @panic("OOM"),
        .windows => std.fmt.allocPrint(allocator, "{s}-pc-windows-{s}", .{
            @tagName(t.cpu.arch), @tagName(t.abi),
        }) catch @panic("OOM"),
        else => std.Target.linuxTriple(&t, allocator) catch @panic("OOM"),
    };
}

// Which per-target config tags must override EMACS_CONFIGURATION: the
// committed config_values.txt carries the Linux triple, which only
// matches the native "linux" config.  macOS/Windows/musl compute their
// (arch-aware) triple from the target instead.
fn needsConfigTriple(tag: []const u8) bool {
    return std.mem.eql(u8, tag, "macos") or
        std.mem.eql(u8, tag, "windows") or
        std.mem.eql(u8, tag, "musl");
}

// Parse a committed vendored-source list (one relative path per line,
// '#' comments allowed) into an allocated slice.  Keeps the hundreds of
// nettle/gnutls C files out of build.zig while the lists themselves stay
// content-tracked and reviewable under tools/gnutls-config/.  The parsed
// strings point into the @embedFile'd list, which is static data, so the
// returned slice stays valid for the whole build.
fn vendorSourceList(b: *std.Build, comptime path: []const u8) []const []const u8 {
    const contents = @embedFile(path);
    var count: usize = 0;
    var count_it = std.mem.splitScalar(u8, contents, '\n');
    while (count_it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len > 0 and t[0] != '#') count += 1;
    }
    const list = b.allocator.alloc([]const u8, count) catch @panic("OOM");
    var i: usize = 0;
    var fill_it = std.mem.splitScalar(u8, contents, '\n');
    while (fill_it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len > 0 and t[0] != '#') {
            list[i] = t;
            i += 1;
        }
    }
    return list;
}

// gnulib modules whose global symbols GnuTLS's bundled gl/ redefines
// (c-ctype, c-strcasecmp, memeq/streq, stat-time).  Emacs already provides
// those exact symbols from its own Zig gnulib packages, so the GnuTLS
// copies are compiled with hidden visibility to avoid duplicate exported
// symbols in the final temacs link.
fn gnutlsGlCollision(src: []const u8) bool {
    const names = [_][]const u8{
        "gl/c-ctype.c",
        "gl/c-strcasecmp.c",
        "gl/c-strncasecmp.c",
        "gl/memeq.c",
        "gl/streq.c",
        "gl/stat-time.c",
    };
    for (names) |n| {
        if (std.mem.eql(u8, src, n)) return true;
    }
    return false;
}

// Apply MSVC-CRT / Winsock deprecation suppressions to a module, so every
// translation unit in it compiles without the CRT turning legitimate POSIX/
// ANSI names (open/close/fopen/strcpy/getenv/strerror/unlink/wcrtomb) or the
// winsock inet_addr/inet_ntoa into hard deprecation errors.  Mirrors upstream
// Emacs's MSVC build (_CRT_SECURE_NO_WARNINGS / _CRT_NONSTDC_NO_WARNINGS) plus
// the winsock equivalent.  Called at the module level so it reaches all TUs
// regardless of per-file compile flags; no effect on the MinGW ABI.
fn applyMsvcCrtWarnings(mod: *std.Build.Module) void {
    mod.addCMacro("_CRT_SECURE_NO_WARNINGS", "1");
    mod.addCMacro("_CRT_NONSTDC_NO_WARNINGS", "1");
    mod.addCMacro("_WINSOCK_DEPRECATED_NO_WARNINGS", "1");
    // MSVC CRT <math.h> only exposes M_PI and friends when _USE_MATH_DEFINES
    // is defined before it is included; src/lcms.c uses M_PI directly.
    mod.addCMacro("_USE_MATH_DEFINES", "1");
    // DirectWrite mirrors its structs with a plain `int` WINBOOL (distinct
    // from winbase BOOL and not defined by the current SDK headers);
    // src/w32dwrite.c uses it in the manually-declared DWrite structs.
    mod.addCMacro("WINBOOL", "int");
    // The MSVC CRT has no ftello (it spells the 64-bit variant _ftelli64 and
    // its ftell returns long).  HAVE_FSEEKO is set (src/lread.c then says
    // `#define file_tell ftello`, file_offset=off_t); map ftello to the CRT
    // ftell, whose long return matches this config's 32-bit off_t exactly.
    mod.addCMacro("ftello", "ftell");
    // The committed gnulib lib/inttypes.h defines PRIdPTR/PRIuPTR/... as
    // `__PRIPTR_PREFIX "d"` / `... "u"` / etc., and it defines the companion
    // 64-bit prefixes `_PRI64_PREFIX`/`_PRIu64_PREFIX` to "I64" for _MSC_VER
    // on its own (lines 727/742).  But `__PRIPTR_PREFIX` itself it never
    // defines, and the MSVC ABI's headers do not either (lib/inttypes.h
    // shadows the CRT's <inttypes.h> which would), so the token stays literal
    // and any `"...%"PRIdPTR"\n"` string-join fails with "expected ')'".
    // ptrdiff_t is 64-bit under the LLP64 MSVC ABI, so pin it to "I64" to
    // match lib/inttypes.h's own MSVC convention for the 64-bit prefixes.
    mod.addCMacro("__PRIPTR_PREFIX", "\"I64\"");
    // bool consistency for the MSVC ABI.  On MinGW `bool` is `signed char`,
    // and Emacs's w32 code freely mixes `bool *` with `signed char *` and
    // declares cross-file bool params.  Under the MSVC ABI clang's native
    // `_Bool` is a DIFFERENT type (same 1-byte size, distinct type), so w32
    // sources get "conflicting types" / "incompatible pointer types".
    // Defining `bool` to `signed char` (as MinGW does) restores the type
    // Emacs's w32 code is written against.  The MSVC CRT <stdbool.h> would
    // `#define bool _Bool` and clash with this, so also pre-set its `_STDBOOL`
    // include guard (the CRT stdbool's entire body is inside #ifndef _STDBOOL)
    // so it becomes empty and never redefines bool.  No effect on MinGW.
    mod.addCMacro("bool", "signed char");
    mod.addCMacro("_STDBOOL", "1");
}

// MSVC-backend toolchain hint (goal 3.6).  When the selected target uses the
// Windows MSVC C ABI (-Dtarget=x86_64-windows-msvc), the build needs the
// Windows SDK + a Visual Studio C/C++ toolchain.  zig itself performs the
// authoritative detection (a bare "failed to find libc installation:
// WindowsSdkNotFound" surfaces at the first C compile).  We do NOT hard-code
// install paths or abort the build here -- VS/Build Tools may legitimately
// live anywhere (e.g. installed via choco to a custom path).  Instead we
// print a one-time reminder of the choco installation commands and let the
// build proceed so zig's own real detection is the gate.  Developers who
// already installed the toolchain are never blocked.
fn probeMsvcToolchain(b: *std.Build) void {
    const host_windows = b.graph.host.result.os.tag == .windows;
    if (!host_windows) return; // Only relevant on a Windows host.
    std.debug.print(
        \\
        \\build.zig: the MSVC backend (-Dtarget=x86_64-windows-msvc) needs the
        \\Windows SDK and a Visual Studio C/C++ toolchain.
        \\If they are not already installed, install them with (admin PowerShell):
        \\  choco install -y visualstudio2022buildtools --package-parameters "--add Microsoft.VisualStudio.Workload.VCTools"
        \\  choco install -y windows-sdk-10
        \\Then re-run `zig build`.  A missing toolchain is detected by zig itself
        \\("failed to find libc installation: WindowsSdkNotFound") -- this message
        \\is only a reminder.
        \\
    , .{});
}

const ConfigOut = struct {
    file: std.Build.LazyPath,
    step: *std.Build.Step,
};

// True when the HOST has the GTK3 development files: a gtk+-3.0.pc is
// discoverable in a standard pkg-config search dir (or $PKG_CONFIG_PATH).
// This drives the -Dpgtk AUTO default for the native glibc-Linux build:
// GUI on where the libraries exist, console TTY fallback where they do
// not (clean clones, minimal containers).  Filesystem probing only --
// the single-threaded build Io cannot run a subprocess at config time,
// same constraint as gccDiscoverGccjit below.
fn hostHasGtk3PcFile(b: *std.Build) bool {
    const io = b.graph.io;
    var dirs: std.ArrayList([]const u8) = .empty;
    defer dirs.deinit(b.allocator);
    if (b.graph.environ_map.get("PKG_CONFIG_PATH")) |v| {
        var it = std.mem.splitScalar(u8, v, ':');
        while (it.next()) |p| {
            if (p.len > 0) dirs.append(b.allocator, b.dupe(p)) catch @panic("OOM");
        }
    }
    const fixed = [_][]const u8{
        "/usr/lib64/pkgconfig",
        "/usr/lib/x86_64-linux-gnu/pkgconfig",
        "/usr/lib/aarch64-linux-gnu/pkgconfig",
        "/usr/lib/pkgconfig",
        "/usr/local/lib/pkgconfig",
        "/usr/local/lib64/pkgconfig",
        "/usr/share/pkgconfig",
    };
    for (fixed) |d| dirs.append(b.allocator, d) catch @panic("OOM");
    for (dirs.items) |d| {
        var dir = std.Io.Dir.openDirAbsolute(io, d, .{}) catch continue;
        defer dir.close(io);
        if (dir.access(io, "gtk+-3.0.pc", .{})) {
            return true;
        } else |_| {}
    }
    return false;
}

// A knob forced by a user feature switch (-Dwith-gnutls=false).  Empty
// `value` = undef the knob; some gnulib switch macros (USE_ACL, ...) are
// used as C expressions and must be `0`, not undef, when disabled.
const DisabledKnob = struct {
    name: []const u8,
    value: []const u8 = "",
};

// Build config.h as a FIRST-CLASS Zig build artifact via `b.addConfigHeader`
// (`.style = .autoconf_undef` over the committed src/config.h.in -- the exact
// template format the old gen-config tool consumed).  Values come from the
// committed src/config_values.txt (the Linux autoconf results) plus the
// per-target override tables in config-overrides.zig; every `#undef NAME` in
// the template must have a value (raw `.ident` for a present value, or
// `.undef`), so the rendering is functionally identical to the previous
// output (ConfigHeader prepends its standard generated-file banner line).
// `disabled` lists knobs forced by the feature switches (value "" =
// undef; a non-empty value defines the knob to it, for gnulib switch
// macros that must be 0 when off).  Applied after the per-target
// overrides.
fn makeConfigHeader(b: *std.Build, tag: ?[]const u8, triple: ?[]const u8, disabled: []const DisabledKnob) ConfigOut {
    return makeConfigHeaderExtra(b, tag, triple, disabled, &.{});
}

/// makeConfigHeader with additional forced DEFINES applied last (after the
/// per-target overrides), so a knob the overrides undef (e.g. HAVE_PNG on
/// every console target) can be re-enabled by a -Dwith-* switch.  Value
/// "1" (or any non-empty ident) becomes `#define NAME value`.
fn makeConfigHeaderExtra(b: *std.Build, tag: ?[]const u8, triple: ?[]const u8, disabled: []const DisabledKnob, extra_defines: []const DisabledKnob) ConfigOut {
    const io = b.graph.io;
    const alloc = b.allocator;

    const values_text = std.Io.Dir.cwd().readFileAlloc(
        io,
        "src/config_values.txt",
        alloc,
        .limited(4 * 1024 * 1024),
    ) catch @panic("build.zig: read src/config_values.txt");
    const template_text = std.Io.Dir.cwd().readFileAlloc(
        io,
        "src/config.h.in",
        alloc,
        .limited(4 * 1024 * 1024),
    ) catch @panic("build.zig: read src/config.h.in");

    // name -> raw value ("" = undef)
    var values = std.StringHashMap([]const u8).init(alloc);
    {
        var it = std.mem.splitScalar(u8, values_text, '\n');
        while (it.next()) |raw_line| {
            // config_values.txt may be checked out with CRLF line endings on
            // Windows; strip one trailing \r so no value silently carries a
            // hidden carriage return (which has broken the quoted-string
            // feature-token rewrite below).
            const line = if (raw_line.len > 0 and raw_line[raw_line.len - 1] == '\r') raw_line[0 .. raw_line.len - 1] else raw_line;
            if (line.len == 0) continue;
            if (std.mem.indexOfScalar(u8, line, '=')) |eq| {
                values.put(b.dupe(line[0..eq]), b.dupe(line[eq + 1 ..])) catch @panic("OOM");
            } else {
                values.put(b.dupe(line), "") catch @panic("OOM");
            }
        }
    }

    if (tag) |t| {
        const overrides: ?[]const config_overrides.Override = if (std.mem.eql(u8, t, "linux"))
            &config_overrides.linux_overrides
        else if (std.mem.eql(u8, t, "musl"))
            &config_overrides.musl_overrides
        else if (std.mem.eql(u8, t, "windows"))
            &config_overrides.windows_overrides
        else if (std.mem.eql(u8, t, "macos"))
            &config_overrides.macos_overrides
        else
            null;
        if (overrides) |list| {
            for (list) |o| values.put(b.dupe(o.name), b.dupe(o.value)) catch @panic("OOM");
        }
        if (needsConfigTriple(t)) {
            const quoted = std.fmt.allocPrint(alloc, "\"{s}\"", .{
                triple orelse @panic("build.zig: this config tag needs a triple"),
            }) catch @panic("OOM");
            values.put(b.dupe("EMACS_CONFIGURATION"), quoted) catch @panic("OOM");
        }
    }

    // User feature switches (-Dwith-gnutls=false ...): force the knob,
    // applied last so the option wins over snapshot + target data.  Empty
    // value = undef; a non-empty value defines it (USE_ACL=0 for gnulib).
    for (disabled) |d| {
        values.put(b.dupe(d.name), b.dupe(d.value)) catch @panic("OOM");
    }
    // Forced DEFINES from opt-in switches (-Dwith-png=true ...), applied
    // after `disabled` so an enable wins even where the per-target
    // overrides undef the knob.
    for (extra_defines) |d| {
        values.put(b.dupe(d.name), b.dupe(d.value)) catch @panic("OOM");
    }
    // Keep EMACS_CONFIG_FEATURES truthful: drop the feature tokens whose
    // knob a switch disabled (e.g. HAVE_GNUTLS -> "GNUTLS").
    if (disabled.len > 0) {
        const features = values.get("EMACS_CONFIG_FEATURES") orelse null;
        if (features) |f| {
            // The stored value carries C string quotes ("ACL DBUS ...").
            const inner = if (f.len >= 2 and f[0] == '"' and f[f.len - 1] == '"') f[1 .. f.len - 1] else f;
            const knob_to_token = [_]struct { knob: []const u8, token: []const u8 }{
                .{ .knob = "HAVE_GNUTLS", .token = "GNUTLS" },
                .{ .knob = "HAVE_GPM", .token = "GPM" },
                .{ .knob = "HAVE_DBUS", .token = "DBUS" },
                .{ .knob = "HAVE_ALSA", .token = "SOUND" },
                .{ .knob = "HAVE_SQLITE3", .token = "SQLITE3" },
                .{ .knob = "HAVE_LIBXML2", .token = "LIBXML2" },
                .{ .knob = "HAVE_LCMS2", .token = "LCMS2" },
                .{ .knob = "HAVE_ZLIB", .token = "ZLIB" },
                .{ .knob = "HAVE_TREE_SITTER", .token = "TREE_SITTER" },
                .{ .knob = "USE_ACL", .token = "ACL" },
            };
            var drop = std.StringHashMap(void).init(alloc);
            defer drop.deinit();
            for (disabled) |d| {
                for (knob_to_token) |m| {
                    if (std.mem.eql(u8, d.name, m.knob)) drop.put(m.token, {}) catch @panic("OOM");
                }
            }
            var kept: std.ArrayList([]const u8) = .empty;
            defer kept.deinit(alloc);
            var tok = std.mem.tokenizeAny(u8, inner, " \t");
            while (tok.next()) |t| {
                if (!drop.contains(t)) kept.append(alloc, t) catch @panic("OOM");
            }
            const quoted = std.fmt.allocPrint(alloc, "\"{s}\"", .{std.mem.join(alloc, " ", kept.items) catch @panic("OOM")}) catch @panic("OOM");
            values.put(b.dupe("EMACS_CONFIG_FEATURES"), quoted) catch @panic("OOM");
        }
    }

    // The set of `#undef NAME` lines the template declares (the only knobs
    // the renderer substitutes; every other line passes through verbatim).
    var undef_names = std.StringHashMap(void).init(alloc);
    {
        var it = std.mem.splitScalar(u8, template_text, '\n');
        while (it.next()) |line| {
            if (line.len == 0 or line[0] != '#') continue;
            var tok = std.mem.tokenizeAny(u8, line[1..], " \t\r");
            const kw = tok.next() orelse continue;
            if (!std.mem.eql(u8, kw, "undef")) continue;
            const name = tok.next() orelse continue;
            undef_names.put(name, {}) catch @panic("OOM");
        }
    }

    const header = b.addConfigHeader(.{
        .style = .{ .autoconf_undef = b.path("src/config.h.in") },
        .include_path = "config.h",
    }, .{});
    var it = undef_names.keyIterator();
    while (it.next()) |name| {
        const raw = values.get(name.*) orelse "";
        if (raw.len == 0) {
            header.values.put(alloc, b.dupe(name.*), .undef) catch @panic("OOM");
        } else {
            header.values.put(alloc, b.dupe(name.*), .{ .ident = raw }) catch @panic("OOM");
        }
    }
    return .{ .file = header.getOutputFile(), .step = &header.step };
}

pub fn build(b: *std.Build) void {
    // Target selection uses zig's standard -Dtarget (e.g.
    // x86_64-windows-gnu for the default Windows GNU/MinGW backend, or
    // x86_64-windows-msvc for the MSVC backend).  No extra ABI shorthand is
    // added: -Dtarget already encodes arch+OS+ABI in full, so a second
    // switch would be a redundant, overlapping entry point.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // `-Dshow-sources=true`: print the parsed base/lib source lists to stderr
    // (two counts followed by the lists) and exit without installing artifacts.
    // Used to verify the build-time parsers against the autotools source lists.
    const show_sources = b.option(bool, "show-sources", "Print parsed base/lib source lists and exit") orelse false;
    // Phase-2.1 subsystem switches (all OFF by default => the build is
    // byte-identical to main). When ON, build.zig injects the matching
    // -DHAVE_* and, for the native-comp Zig path, compiles src/compz.c.
    const enable_native_comp_zig = b.option(bool, "native-comp-zig", "Enable the Zig/LLVM native-comp path (.zeln)") orelse false;
    // gccjit native-comp (.eln) — the UPSTREAM path (HAVE_NATIVE_COMP, src/comp.c).
    // Independent of -Dnative-comp-zig; both default OFF, both can be ON (M2.5
    // coexistence).  When both are on, the `native-comp-z-prefer' Lisp var
    // decides which native artifact loads where a .elc has both a .eln and a
    // .zeln.  libgccjit is host-specific, so the switch is forced OFF for any
    // non-native / non-glibc-Linux target (see native_comp_target below).
    // It is strictly opt-in: merely having libgccjit installed must not turn
    // a `-Dnative-comp-zig=true` zeln-only build into a combined graph.
    const enable_native_comp = b.option(bool, "native-comp", "Enable the gccjit native-comp path (.eln, HAVE_NATIVE_COMP); default OFF") orelse false;
    const enable_modules = b.option(bool, "modules", "Enable upstream dynamic modules (HAVE_MODULES)") orelse false;
    const enable_modules_zig = b.option(bool, "modules-zig", "Enable the Zig dynamic-module subsystem (HAVE_MODULES_ZIG)") orelse false;
    // Proto-UI is adapter-only.  The option builds the EUP codec and
    // versioned ABI, tests them with a fake host, and audits changed paths;
    // it does not alter inherited Emacs C/Lisp source or enable runtime
    // integration.
    const enable_proto_ui = b.option(bool, "proto-ui", "Build adapter-only EUP codec/ABI and run conformance plus boundary tests") orelse false;

    // Target-derived flags.  `target` is resolved at line 64, so target.result
    // is in scope here; computing these early lets the make-docfile / doc-scan
    // / buildobj gates below read them (they run before the source-compile
    // block).  musl targets get a minimal config (config-overrides.zig undefs
    // the optional system-lib features), so skip the corresponding -l flags
    // there too; only libm and ncurses (terminal support) remain.
    const is_windows = target.result.os.tag == .windows;
    const is_musl = target.result.os.tag == .linux and target.result.abi == .musl;
    // MSVC backend pre-flight (goal 3.6): when the selected target uses the
    // Windows MSVC ABI, fail fast with install guidance if the Windows SDK /
    // VS C++ toolchain is missing on this Windows host (instead of zig's opaque
    // "WindowsSdkNotFound").  Only fires for the msvc ABI; gnu backend is
    // self-contained on Windows.
    if (target.result.abi == .msvc) probeMsvcToolchain(b);

    if (enable_proto_ui) {
        const proto_ui_module = b.createModule(.{
            .root_source_file = b.path("src/proto-ui/root.zig"),
            // Adapter conformance/testing is a host tool and must run even
            // when the surrounding Emacs graph is configured for a foreign
            // target.
            .target = b.graph.host,
            .optimize = optimize,
        });
        const proto_ui_tests = b.addTest(.{
            .root_module = proto_ui_module,
        });
        const run_proto_ui_tests = b.addRunArtifact(proto_ui_tests);
        const proto_ui_unit_step = b.step(
            "proto-ui-unit",
            "Run adapter and EUP protocol unit tests",
        );
        proto_ui_unit_step.dependOn(&run_proto_ui_tests.step);

        // W4c-b1-b0: the adapter owns the authoritative ownership manifest;
        // Zig build emits a versioned C header and a non-normative ABI
        // summary.  They never overwrite tracked inherited C files.
        const abi_gen_tool = b.addExecutable(.{
            .name = "proto-ui-abi-gen",
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .optimize = .Debug,
                .root_source_file = b.path("src/proto-ui/abi_gen.zig"),
            }),
        });
        const run_abi_gen = b.addRunArtifact(abi_gen_tool);
        const abi_header = run_abi_gen.addOutputFileArg("abi_v1.h");
        const abi_manifest = run_abi_gen.addOutputFileArg("manifest.json");
        const install_abi_header = b.addInstallFile(
            abi_header,
            "include/proto-ui/abi_v1.h",
        );
        const install_abi_manifest = b.addInstallFile(
            abi_manifest,
            "include/proto-ui/manifest.json",
        );

        const abi_gen_step = b.step(
            "proto-ui-abi",
            "Generate the versioned Proto-UI adapter ABI and non-normative summary",
        );
        abi_gen_step.dependOn(&run_abi_gen.step);
        abi_gen_step.dependOn(&install_abi_header.step);
        abi_gen_step.dependOn(&install_abi_manifest.step);

        const conformance_tool = b.addExecutable(.{
            .name = "proto-ui-conformance",
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .optimize = optimize,
                .root_source_file = b.path("src/proto-ui/conformance.zig"),
            }),
        });
        const run_conformance = b.addRunArtifact(conformance_tool);
        const conformance_step = b.step(
            "proto-ui-conformance",
            "Run fake-host adapter ABI conformance tests",
        );
        conformance_step.dependOn(&run_conformance.step);

        const boundary_audit_tool = b.addExecutable(.{
            .name = "proto-ui-boundary-audit",
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .optimize = .Debug,
                .root_source_file = b.path("src/proto-ui/boundary_audit.zig"),
            }),
        });
        const run_boundary_audit = b.addRunArtifact(boundary_audit_tool);
        run_boundary_audit.addArg("src/proto-ui/adapter.zig");
        run_boundary_audit.addArg("build.zig");
        if (b.args) |user_args| run_boundary_audit.addArgs(user_args);
        const boundary_audit_step = b.step(
            "proto-ui-boundary-audit",
            "Classifier smoke audit; append paths after -- for a changed-path audit",
        );
        boundary_audit_step.dependOn(&run_boundary_audit.step);

        const boundary_step = b.step(
            "proto-ui-boundary",
            "Generate adapter ABI, run fake-host conformance, and audit boundary paths",
        );
        boundary_step.dependOn(&run_abi_gen.step);
        boundary_step.dependOn(&install_abi_header.step);
        boundary_step.dependOn(&install_abi_manifest.step);
        boundary_step.dependOn(&run_conformance.step);
        boundary_step.dependOn(&run_boundary_audit.step);
    }
    // modules_runtime: the SHARED module runtime turns on once when EITHER
    // module switch is on AND the target can actually dlopen.  Gates the
    // shared runtime -- HAVE_MODULES macro, emacs-module.c compile,
    // make-docfile / doc-scan / buildobj.h entries and the modules-test step
    // -- so -Dmodules and -Dmodules-zig both light it up.  Dynamic modules
    // need dlopen, which requires dynamic linking -- impossible in a
    // fully-static musl build (plan 13.1.6 / B4); force it off there.  Stays
    // on for glibc-Linux (dlopen lives in libc since glibc 2.34, no -ldl),
    // macOS and Windows.  Off-by-default behaviour is untouched (both switches
    // off => false, byte-identical build).
    const modules_runtime = (enable_modules or enable_modules_zig) and !is_musl;
    // modules_zig_provider: when on, src/dynlib.c is dropped from the compile
    // and the tools/emacs-dynlib Zig package provides the dynlib_* ABI instead
    // (Track-B B-Z, HAVE_MODULES_ZIG).  POSIX-only this cycle (the package
    // wraps libc dlopen/dlsym/dlclose/dlerror/dladdr; the w32 LoadLibrary
    // branch of dynlib.c is not ported), so it is forced OFF on Windows and
    // static musl -- the switch silently does nothing there (V6).  When off
    // (default), dynlib.c compiles at all sites exactly as today -- zero
    // footprint.
    const modules_zig_provider = enable_modules_zig and !is_musl and !is_windows;

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
    // The endian.h content depends on the target (macOS/BSD use
    // <sys/endian.h>, Linux/musl <endian.h>); pass the tag so the
    // generated header matches the build target, not the host.
    generate_headers.addArg(switch (target.result.os.tag) {
        .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .openbsd, .netbsd, .dragonfly => "macos",
        .windows => "windows",
        else => "linux",
    });
    const generate_step = b.step("generate-headers", "Generate Gnulib .gl.h headers");
    generate_step.dependOn(&generate_headers.step);

    // Generate lisp/international/{charscript,emoji-zwj}.el from
    // admin/unidata via native Zig tools (build-aux/gen-charscript.zig +
    // gen-emoji-zwj.zig, byte-identical ports of the gawk scripts).
    // Outputs land in the SOURCE TREE (gitignored). Standalone only --
    // NOT wired into the default install/zig build.
    const gen_charscript_tool = b.addExecutable(.{
        .name = "gen-charscript",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/gen-charscript.zig"),
        }),
    });
    const run_gen_charscript = b.addRunArtifact(gen_charscript_tool);
    run_gen_charscript.setCwd(b.path("."));
    const gen_emoji_zwj_tool = b.addExecutable(.{
        .name = "gen-emoji-zwj",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/gen-emoji-zwj.zig"),
        }),
    });
    const run_gen_emoji_zwj = b.addRunArtifact(gen_emoji_zwj_tool);
    run_gen_emoji_zwj.setCwd(b.path("."));
    const gen_unidata_step = b.step(
        "generate-unidata",
        "Generate lisp/international/{charscript,emoji-zwj}.el from admin/unidata",
    );
    gen_unidata_step.dependOn(&run_gen_charscript.step);
    gen_unidata_step.dependOn(&run_gen_emoji_zwj.step);

    // Generate etc/charsets/*.map (131 maps) and lisp/international/
    // {cp51932,eucjp-ms}.el from admin/charsets via a native Zig tool
    // (build-aux/gen-charsets.zig), byte-identical to the former
    // make+gawk+gzip+sed+sort pipeline. Outputs land in the SOURCE TREE
    // (gitignored). Standalone only -- NOT wired into the default
    // install/zig build.
    const gen_charsets_tool = b.addExecutable(.{
        .name = "gen-charsets",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/gen-charsets.zig"),
        }),
    });
    const gen_charsets = b.addRunArtifact(gen_charsets_tool);
    gen_charsets.setCwd(b.path("."));
    const gen_charsets_step = b.step(
        "generate-charsets",
        "Generate etc/charsets/*.map and cp51932/eucjp-ms.el from admin/charsets",
    );
    gen_charsets_step.dependOn(&gen_charsets.step);

    // Generate src/config.h as a FIRST-CLASS Zig build artifact via
    // `b.addConfigHeader` (`.style = .autoconf_undef` over src/config.h.in,
    // the lean template: guard + _GNU_SOURCE + every `#undef NAME` from
    // config.in + conf_post).  Values come from the committed
    // src/config_values.txt (NAME=value / bare NAME for undef, the Linux
    // autoconf results) plus the per-target override tables in
    // config-overrides.zig.  This replaces both the former ./configure
    // shell step and the custom gen-config tool: config.h is a standard
    // Step.ConfigHeader artifact, fully owned by the zig build, with
    // per-target differences derived from the target (not the host), so
    // builds are reproducible.  Every C compile (make-docfile + temacs)
    // includes the generated <config.h> via addIncludePath below.
    // Optional system-feature switches (mirror upstream --with-<lib>=no):
    // -Dwith-gnutls=false undefs HAVE_GNUTLS in config.h AND skips linking
    // the library.  Default on; each is applied after the per-target
    // overrides so the user's choice always wins.
    // GUI/image defaults: plain `zig build` on a Windows target should
    // yield the full GUI emacs with the complete vendored image surface
    // (the behavior of the MSYS2 reference build).  is_windows is defined
    // above (line ~360); gui_on_by_default guards the image defaults too.
    const gui_on_by_default = is_windows;
    const with_gnutls = b.option(bool, "with-gnutls", "Link GnuTLS (HAVE_GNUTLS)") orelse true;
    const with_dbus = b.option(bool, "with-dbus", "Link D-Bus (HAVE_DBUS)") orelse true;
    const with_gpm = b.option(bool, "with-gpm", "Link GPM console mouse (HAVE_GPM)") orelse true;
    const with_alsa = b.option(bool, "with-alsa", "Link ALSA sound (HAVE_ALSA)") orelse true;
    const with_acl = b.option(bool, "with-acl", "Link POSIX ACL (USE_ACL)") orelse true;
    const with_sqlite3 = b.option(bool, "with-sqlite3", "Enable SQLite (HAVE_SQLITE3)") orelse true;
    const with_xml2 = b.option(bool, "with-xml2", "Enable libxml2 (HAVE_LIBXML2)") orelse true;
    const with_lcms2 = b.option(bool, "with-lcms2", "Enable Little CMS (HAVE_LCMS2)") orelse true;
    const with_zlib = b.option(bool, "with-zlib", "Enable zlib (HAVE_ZLIB)") orelse true;
    // Tree-sitter (HAVE_TREE_SITTER), mirroring upstream --with-tree-sitter /
    // --without-tree-sitter.  Default on: tree-sitter is vendored via
    // build.zig.zon -> tree_sitter URL dep and built from source, so there is
    // no system dependency.  When off, the vendored libtree-sitter is not
    // linked and HAVE_TREE_SITTER is undef'd; src/treesit.c always compiles (as
    // upstream does) so `treesit-available-p' reports unavailable rather than
    // the symbol table disappearing.
    const with_tree_sitter = b.option(bool, "with-tree-sitter", "Enable tree-sitter (HAVE_TREE_SITTER, vendored)") orelse true;
    // Image libraries (objective 3.5): libpng/libjpeg/libtiff/giflib/
    // libwebp/libXpm vendored via build.zig.zon URL deps and built from
    // source as static libs.  Default ON for the Windows GUI build (the
    // MSYS2 reference ships the full image surface); explicitly OFF
    // otherwise unless the user passes -Dwith-*=true.  On non-Windows
    // targets they default off (no GUI), and -Dgui=false plus
    // -Dwith-*=false reproduces the original console-only build.
    const with_png = b.option(bool, "with-png", "Enable libpng (HAVE_PNG, vendored)") orelse (is_windows and gui_on_by_default);
    const with_jpeg = b.option(bool, "with-jpeg", "Enable libjpeg (HAVE_JPEG, vendored)") orelse (is_windows and gui_on_by_default);
    const with_tiff = b.option(bool, "with-tiff", "Enable libtiff (HAVE_TIFF, vendored)") orelse (is_windows and gui_on_by_default);
    const with_gif = b.option(bool, "with-gif", "Enable giflib (HAVE_GIF, vendored)") orelse (is_windows and gui_on_by_default);
    const with_webp = b.option(bool, "with-webp", "Enable libwebp (HAVE_WEBP, vendored)") orelse (is_windows and gui_on_by_default);
    const with_xpm = b.option(bool, "with-xpm", "Enable libXpm via its FOR_MSW layer (HAVE_XPM, vendored, no X11)") orelse (is_windows and gui_on_by_default);
    // The w32 GUI backend (objective: full GUI compilation).  DEFAULT ON
    // for the Windows target: plain `zig build` on Windows now produces
    // the GUI emacs (matching the MSYS2 reference build), not the
    // console-only variant.  -Dgui=false restores the console build;
    // non-Windows targets have no w32 GUI and stay console by default.
    // Options: the imaging/display switches (native-comp, modules,
    // with-*) are still independently toggleable.
    const with_gui = b.option(bool, "gui", "Enable the w32 GUI backend (HAVE_NTGUI, w32 display modules)") orelse gui_on_by_default;
    // The PGTK GUI backend (native glibc-Linux only).  Mirrors configure.ac's
    // `--with-pgtk` branch: window_system=pgtk with GTK3 + cairo, i.e.
    // HAVE_PGTK/HAVE_WINDOW_SYSTEM/POLL_FOR_INPUT, TERM_HEADER=gtkutil.h,
    // USE_CAIRO (cairo is REQUIRED for pgtk), HAVE_GTK3/USE_GTK, plus the
    // freetype/harfbuzz font stack.  Compiles the PGTK_OBJ display modules
    // (pgtkfns pgtkterm pgtkselect pgtkmenu pgtkim xsettings), the
    // WINDOW_SYSTEM_OBJ (fontset fringe image), xgselect and the cairo
    // font drivers (ftfont ftcrfont hbfont), linking the system GTK3
    // stack via pkg-config (zig's linkSystemLibrary consults it).
    //
    // DEFAULT ON for the native glibc-Linux build when the system has the
    // GTK3 development files (detected by looking for gtk+-3.0.pc in the
    // standard pkg-config dirs, including $PKG_CONFIG_PATH); machines
    // without them fall back to the TTY build automatically, and
    // -Dpgtk=false forces the console build everywhere.
    const pgtk_auto = target.result.os.tag == .linux and !is_musl and
        b.graph.host.result.os.tag == .linux and hostHasGtk3PcFile(b);
    const with_pgtk = b.option(bool, "pgtk", "Enable the PGTK (GTK3+cairo) GUI backend on Linux (HAVE_PGTK, pgtk display modules); default auto-on when system GTK3 dev files are found") orelse pgtk_auto;
    const pgtk_target = with_pgtk and target.result.os.tag == .linux and !is_musl;

    // Knobs forced by the switches, collected into DisabledKnob entries.
    var disabled_knobs: std.ArrayList(DisabledKnob) = .empty;
    defer disabled_knobs.deinit(b.allocator);
    {
        const Feature = struct { on: bool, name: []const u8, value: []const u8 = "" };
        const feats = [_]Feature{
            .{ .on = with_gnutls, .name = "HAVE_GNUTLS" },
            .{ .on = with_dbus, .name = "HAVE_DBUS" },
            .{ .on = with_gpm, .name = "HAVE_GPM" },
            .{ .on = with_alsa, .name = "HAVE_ALSA" },
            // USE_ACL is a gnulib switch macro used as a C expression;
            // it must be 0 (not undef) when disabled.
            .{ .on = with_acl, .name = "USE_ACL", .value = "0" },
            .{ .on = with_sqlite3, .name = "HAVE_SQLITE3" },
            .{ .on = with_xml2, .name = "HAVE_LIBXML2" },
            .{ .on = with_lcms2, .name = "HAVE_LCMS2" },
            .{ .on = with_zlib, .name = "HAVE_ZLIB" },
            .{ .on = with_tree_sitter, .name = "HAVE_TREE_SITTER" },
            .{ .on = with_png, .name = "HAVE_PNG" },
            .{ .on = with_jpeg, .name = "HAVE_JPEG" },
            .{ .on = with_tiff, .name = "HAVE_TIFF" },
            .{ .on = with_gif, .name = "HAVE_GIF" },
            .{ .on = with_webp, .name = "HAVE_WEBP" },
            // PGTK/cairo has a built-in XPM3 parser; HAVE_XPM selects the
            // X/libXpm loader and must stay off there.
            .{ .on = with_xpm and !pgtk_target, .name = "HAVE_XPM" },
        };
        for (feats) |f| {
            if (!f.on) disabled_knobs.append(b.allocator, .{ .name = f.name, .value = f.value }) catch @panic("OOM");
        }
    }
    // Opt-in image defines: every console target's overrides undef HAVE_PNG/
    // HAVE_JPEG/HAVE_TIFF, so re-define them AFTER the overrides when the
    // vendored libraries are switched on.
    var image_defines: std.ArrayList(DisabledKnob) = .empty;
    defer image_defines.deinit(b.allocator);
    {
        if (with_png) image_defines.append(b.allocator, .{ .name = "HAVE_PNG", .value = "1" }) catch @panic("OOM");
        if (with_jpeg) image_defines.append(b.allocator, .{ .name = "HAVE_JPEG", .value = "1" }) catch @panic("OOM");
        if (with_tiff) image_defines.append(b.allocator, .{ .name = "HAVE_TIFF", .value = "1" }) catch @panic("OOM");
        if (with_gif) image_defines.append(b.allocator, .{ .name = "HAVE_GIF", .value = "1" }) catch @panic("OOM");
        if (with_webp) image_defines.append(b.allocator, .{ .name = "HAVE_WEBP", .value = "1" }) catch @panic("OOM");
        if (with_xpm and !pgtk_target) image_defines.append(b.allocator, .{ .name = "HAVE_XPM", .value = "1" }) catch @panic("OOM");
        // Proto-UI is an independent opt-in backend identity and lifecycle
        // ABI.  It does not turn on HAVE_WINDOW_SYSTEM or any native-toolkit
        // dependency.
        // The w32 GUI backend (mirrors configure.ac's HAVE_W32=yes branch:
        // AC_DEFINE HAVE_NTGUI, and window_system=w32 implies
        // HAVE_WINDOW_SYSTEM + POLL_FOR_INPUT + WINDOW_SYSTEM_OBJ).
        if (with_gui and is_windows) {
            image_defines.append(b.allocator, .{ .name = "HAVE_NTGUI", .value = "1" }) catch @panic("OOM");
            image_defines.append(b.allocator, .{ .name = "HAVE_WINDOW_SYSTEM", .value = "1" }) catch @panic("OOM");
            image_defines.append(b.allocator, .{ .name = "POLL_FOR_INPUT", .value = "1" }) catch @panic("OOM");
            // TERM_HEADER (config.h) selects the per-window-system terminal
            // header every HAVE_WINDOW_SYSTEM TU includes (configure sets
            // w32term.h for HAVE_W32): src/alloc.c et al do
            // `#include TERM_HEADER`.
            image_defines.append(b.allocator, .{ .name = "TERM_HEADER", .value = "\"w32term.h\"" }) catch @panic("OOM");
            // Upstream defines HAVE_STACK_OVERFLOW_HANDLING for mingw; its
            // keyboard.c consumer calls w32_reset_stack_overflow_guard,
            // defined in w32fns.c — so it may only be on with the GUI
            // modules (the console build leaves it undef'd).
            image_defines.append(b.allocator, .{ .name = "HAVE_STACK_OVERFLOW_HANDLING", .value = "1" }) catch @panic("OOM");
        }
        // The PGTK backend (mirrors configure.ac's window_system=pgtk
        // branch + the gtk3/cairo/harfbuzz/fontconfig module checks):
        // window_system=pgtk implies HAVE_WINDOW_SYSTEM + POLL_FOR_INPUT
        // + TERM_HEADER=pgtkterm.h; GTK3 found => HAVE_GTK3 + USE_GTK;
        // cairo is required for pgtk => USE_CAIRO; freetype/fontconfig
        // are required => HAVE_FREETYPE; harfbuzz present on the host =>
        // HAVE_HARFBUZZ; glib linked => HAVE_GLIB.  The deprecation
        // warnings are silenced exactly as configure does by default.
        if (pgtk_target) {
            const dk = [_]DisabledKnob{
                .{ .name = "HAVE_PGTK", .value = "1" },
                .{ .name = "HAVE_WINDOW_SYSTEM", .value = "1" },
                .{ .name = "POLL_FOR_INPUT", .value = "1" },
                // TERM_HEADER: configure sets term_header=gtkterm's
                // gtkutil.h for every GTK-linked build (HAVE_GTK3 =>
                // gtk_term_header=gtkutil.h; term_header=$gtk_term_header
                // in the pkg_check_gtk=yes branch) -- gtkutil.h pulls the
                // real terminal header itself (pgtkterm.h under HAVE_PGTK)
                // and declares update_frame_tool_bar et al.
                .{ .name = "TERM_HEADER", .value = "\"gtkutil.h\"" },
                .{ .name = "HAVE_GTK3", .value = "1" },
                .{ .name = "USE_GTK", .value = "1" },
                .{ .name = "USE_CAIRO", .value = "1" },
                .{ .name = "HAVE_FREETYPE", .value = "1" },
                .{ .name = "HAVE_HARFBUZZ", .value = "1" },
                .{ .name = "HAVE_GLIB", .value = "1" },
                .{ .name = "GDK_DISABLE_DEPRECATION_WARNINGS", .value = "1" },
                .{ .name = "GLIB_DISABLE_DEPRECATION_WARNINGS", .value = "1" },
                // Advertise the GUI toolkit in the runtime feature string
                // (system-configuration-features), like a pgtk configure.
                .{ .name = "EMACS_CONFIG_FEATURES", .value = "\"ACL CAIRO DBUS GMP GNUTLS GPM HARFBUZZ LCMS2 LIBXML2 NOTIFY INOTIFY PDUMPER PGTK SECCOMP SOUND SQLITE3 THREADS TREE_SITTER ZLIB\"" },
            };
            for (dk) |d| image_defines.append(b.allocator, d) catch @panic("OOM");
        }
    }
    const base_config = makeConfigHeader(b, "linux", null, disabled_knobs.items);
    const config_h_file = base_config.file;
    const gen_config_step = b.step(
        "generate-config",
        "Generate src/config.h via addConfigHeader (template + values + per-target overrides)",
    );
    gen_config_step.dependOn(base_config.step);

    // config-probe: a DIAGNOSTIC host prober (tools/config-probe).  A
    // cached Run step that reports the host's header/function reality as
    // NAME=value override lines (`zig build probe-config`).  It does NOT
    // feed config.h: config.h is a deterministic, first-class artifact of
    // the zig build, derived ONLY from the committed config_values.txt +
    // per-target overrides, so the build is reproducible across machines.
    const enable_config_probe = b.option(bool, "config-probe", "Build the diagnostic host prober step (zig build probe-config)") orelse true;

    if (enable_config_probe) {
        const config_probe_dep = b.dependency("config_probe", .{});
        const config_probe_tool = b.addExecutable(.{
            .name = "config-probe",
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .optimize = .Debug,
                .root_source_file = config_probe_dep.path("src/main.zig"),
            }),
        });
        const run_config_probe = b.addRunArtifact(config_probe_tool);
        run_config_probe.setCwd(b.path("."));
        run_config_probe.addArg(b.graph.zig_exe);
        run_config_probe.addArg("pkg-config");
        const config_probe_step = b.step(
            "probe-config",
            "Diagnostic: probe the host's headers/functions (zig cc) and print the would-be config.h overrides",
        );
        config_probe_step.dependOn(&run_config_probe.step);
    }

    // Cross targets get a target-tagged config: the committed values are
    // the native Linux configure results, so for musl and Windows the
    // per-target override tables undef the optional system-library
    // features those targets cannot link yet.  The HOST/base config above
    // stays untouched for make-docfile and the config verifiers; only the
    // temacs C compile switches to the target config.
    const target_config_tag: ?[]const u8 = switch (target.result.os.tag) {
        .windows => "windows",
        .macos => "macos",
        .linux => if (target.result.abi == .musl) "musl" else null,
        else => null,
    };
    const target_config_h_file: ConfigOut = if (target_config_tag) |tag|
        makeConfigHeaderExtra(b, tag, if (needsConfigTriple(tag)) canonicalConfiguration(target.result, b.allocator) else null, disabled_knobs.items, image_defines.items)
        // Native glibc-Linux carries no target tag (it uses the base
        // config); re-apply the linux overrides + the opt-in forced
        // defines (-Dpgtk, -Dwith-png, ...) whenever any exist, so a
        // GUI/image switch reaches config.h on the native build too.
    else if (image_defines.items.len > 0)
        makeConfigHeaderExtra(b, "linux", null, disabled_knobs.items, image_defines.items)
    else
        base_config;

    // make-docfile is a HOST tool: it must compile against a config that
    // matches the OS it runs on.  The committed values are Linux-derived
    // (HAVE_DECL_*_UNLOCKED=1 etc.); on Windows and macOS hosts those
    // would make lib/unlocked-io.h remap getc/fputs/putchar to *_unlocked
    // symbols the platform libc does not have, so the host config carries
    // the platform tag whenever the host is Windows or macOS.
    // (Cross-compiling from a Linux host keeps the Linux host config,
    // which is what make-docfile runs against there.)
    const host_config_tag: ?[]const u8 = switch (b.graph.host.result.os.tag) {
        .windows => "windows",
        .macos => "macos",
        else => null,
    };
    const mdf_config: ConfigOut = if (host_config_tag) |tag|
        makeConfigHeader(b, tag, if (needsConfigTriple(tag)) canonicalConfiguration(b.graph.host.result, b.allocator) else null, disabled_knobs.items)
    else
        base_config;

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
    const mdf_flags_core = [_][]const u8{
        "-std=gnu2x",
        "-fno-common",
        "-fno-strict-aliasing",
        "-D_GNU_SOURCE",
        "-DHAVE_CONFIG_H",
        "-I.",
        "-Isrc",
        "-Ilib",
    };
    // The host config carries the Windows tag on a Windows host
    // (WINDOWSNT -> conf_post.h pulls in ms-w32.h from nt/inc), which
    // requires the upstream Windows include dir.  On Unix hosts nt/inc
    // must NOT be on the path: its mingw shims (unistd.h, dirent.h, ...)
    // would shadow the system headers.
    const mdf_flags: []const []const u8 = if (host_config_tag != null and b.graph.host.result.os.tag == .windows)
        &(mdf_flags_core ++ [_][]const u8{"-Int/inc"})
    else
        &mdf_flags_core;
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
    mdf.root_module.addIncludePath(mdf_config.file.dirname());
    mdf.step.dependOn(mdf_config.step);

    // Run `make-docfile -d src -g <sources>` and capture stdout as globals.h.
    // make-docfile resolves absolute source paths despite `-d src`, and
    // addFileArg makes Zig hash each scanned file.  This matters because an
    // upstream edit can add DEFVAR/DEFUN surface without changing argv.
    const run_mdf = b.addRunArtifact(mdf);
    run_mdf.addArg("-d");
    run_mdf.addArg("src");
    run_mdf.addArg("-g");
    for (base_sources) |s| {
        run_mdf.addFileArg(b.path(s));
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
        for (linux_doc_sources) |name| run_mdf.addFileArg(b.path(b.fmt("src/{s}", .{name})));
        // -Dpgtk: the GUI modules' DEFVAR/DEFUN surface (pgtkterm.c's
        // Vpgtk_* vars, pgtkfns.c's Fpgtk_* / frame parameters, fontset.c's
        // Fquery_fontset, fringe.c's Voverflow_newline_into_fringe,
        // image.c's DEFVARs, ftfont/hbfont font-driver symbols, ...) must
        // be in globals.h or every HAVE_WINDOW_SYSTEM TU fails to compile
        // -- mirrors the -Dgui windows re-add below.
        if (pgtk_target) {
            const pgtk_doc_sources = [_][]const u8{
                "pgtkfns.c", "pgtkterm.c",  "pgtkmenu.c",      "pgtkselect.c",
                "pgtkim.c",  "xsettings.c", "xgselect.c",      "fontset.c",
                "fringe.c",  "image.c",     "ftfont.c",        "ftcrfont.c",
                "hbfont.c",  "gtkutil.c",   "emacsgtkfixed.c",
            };
            for (pgtk_doc_sources) |name| {
                run_mdf.addFileArg(b.path(b.fmt("src/{s}", .{name})));
            }
        }
    }
    // kqueue.c is compiled only on BSD/macOS, so its DEFSYM/defsubr
    // symbols (Qcreate/Qdelete/... and Fkqueue_*) never reach globals.h
    // from the Linux base sources.  Scan it for the macOS target so the
    // generated header carries the lispsym indices and EXFUN
    // declarations, exactly like the Linux/windows re-adds above;
    // otherwise the Q* macros are missing and the Fkqueue_* forward
    // references are undeclared.
    if (target.result.os.tag == .macos) {
        run_mdf.addFileArg(b.path("src/kqueue.c"));
    }
    // The w32 modules are compiled into the Windows build, so their
    // EXFUN/DEFVAR/DEFSYM declarations must reach globals.h too,
    // otherwise the C sources that use those symbols before defining
    // them fail with "use of undeclared identifier".  Mirrors the
    // Linux-only DEFSYM re-add above (make-docfile -g scans only the
    // files it is given).  w32dwrite.c carries no Lisp-visible symbols
    // today but is included for parity with the compile gate.
    if (target.result.os.tag == .windows) {
        const windows_doc_sources = [_][]const u8{
            "w32.c",     "w32console.c", "w32heap.c",
            "w32proc.c", "w32reg.c",     "w32dwrite.c",
            "w32font.c",
            // w32fns.c carries the Vw32_* key-modifier DEFVARs that
            // w32inevt.c (the console input layer) reads; scan it for
            // symbols even though the GUI module itself is not built.
            "w32fns.c",
            // w32term.c DEFVARs Vw32_recognize_altgr, also read by
            // w32inevt.c.
                "w32term.c",
        };
        for (windows_doc_sources) |name| run_mdf.addFileArg(b.path(b.fmt("src/{s}", .{name})));
        // -Dgui: the GUI modules' DEFVAR/DEFUN surface (fringe.c's
        // Voverflow_newline_into_fringe, fontset.c's Fquery_fontset,
        // w32fns.c's Qauto/QCrelief, menu.c/xfaces.c consumers, ...) must
        // be in globals.h or every HAVE_WINDOW_SYSTEM TU fails to compile.
        if (with_gui) {
            const gui_doc_sources = [_][]const u8{
                "w32menu.c", "w32select.c", "w32uniscribe.c",
                "w32xfns.c", "fontset.c",   "fringe.c",
                "image.c",
                // w32image.c carries Fw32image_create_thumbnail and
                // w32cygwinx.c Fw32_battery_status (both referenced by
                // their own DEFUN bodies via globals.h declarations).
                  "w32image.c",  "w32cygwinx.c",
            };
            for (gui_doc_sources) |name| {
                run_mdf.addFileArg(b.path(b.fmt("src/{s}", .{name})));
            }
        }
    }
    // emacs-module.c (when -Dmodules=true) carries the module runtime's
    // DEFSYM/DEFVAR/DEFUN declarations (Qmodule_function_p, Fmodule_load,
    // Qinvalid_arity, ...).  It is MODULES_OBJ -- a separate autoconf var
    // (src/Makefile.in:270-271), not in base_obj -- so parseBaseSources
    // never picks it up; make-docfile must scan it explicitly so globals.h
    // carries those declarations, otherwise src/emacs-module.c and the
    // lread.c #ifdef HAVE_MODULES blocks fail with "undeclared identifier".
    // Mirrors the platform re-adds above.  (For a musl+modules build
    // modules_runtime is false, so emacs-module.c is not compiled; the
    // resulting globals.h externs are then unused-but-harmless.)  Track-B
    // B-Z: widened from enable_modules to modules_runtime so the Zig module
    // subsystem (-Dmodules-zig) also pulls in the shared runtime here.
    if (modules_runtime) run_mdf.addFileArg(b.path("src/emacs-module.c"));
    // compz.c (when -Dnative-comp-zig=true) carries the ZELN DEFUNs
    // (Scomp_z_load_zeln, Scomp_z_write_spike_zunit, ...) and the DEFVAR_LISP
    // slots (Vzeln_abi_hash, Vnative_comp_zeln_load_path,
    // Vcomp_z_native_version_dir, Vzeln_to_el_h), which make-docfile must
    // materialize in globals.h or the compile fails with
    // "no member f_Vnative_comp_zeln_load_path" / etc.  Scanned ONLY when
    // the flag is on so the off-path globals.h stays byte-identical (zero
    // footprint, plan section 0 pillar 3).
    //
    // Passed via addFileArg (not addArg) so Zig tracks compz.c as a file
    // INPUT to this Run step: compz.c is under active development (M1+),
    // and a plain addArg basename would let the globals.h output go STALE
    // across compz.c edits (the Run cache keys only on the make-docfile
    // binary + argv, not on file contents it isn't told about).  The
    // absolute path make-docfile receives resolves fine after its `-d src`
    // chdir (verified), and the other base sources above are stable enough
    // to keep as plain addArg basenames.
    if (enable_native_comp_zig) run_mdf.addFileArg(b.path("src/compz.c"));
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
    // SOME_MACHINE_OBJECTS as in Makefile.in:477-488.  Keep `.o` argv names:
    // make-docfile writes them into DOC and rewrites them only when opening
    // the source.  addFileInput tracks that source without changing argv.
    const some_machine_objects = [_][]const u8{
        "dosfns.o",        "msdos.o",      "xterm.o",
        "xfns.o",          "xmenu.o",      "xselect.o",
        "xrdb.o",          "xsmfns.o",     "fringe.o",
        "image.o",         "fontset.o",    "dbusbind.o",
        "cygw32.o",        "nsterm.o",     "nsfns.o",
        "nsmenu.o",        "nsselect.o",   "nsimage.o",
        "nsfont.o",        "macfont.o",    "nsxwidget.o",
        "w32.o",           "w32console.o", "w32cygwinx.o",
        "w32fns.o",        "w32heap.o",    "w32inevt.o",
        "w32notify.o",     "w32menu.o",    "w32proc.o",
        "w32reg.o",        "w32select.o",  "w32term.o",
        "w32xfns.o",       "w16select.o",  "widget.o",
        "xfont.o",         "ftfont.o",     "xftfont.o",
        "gtkutil.o",       "xsettings.o",  "xgselect.o",
        "termcap.o",       "hbfont.o",     "haikuterm.o",
        "haikufns.o",      "haikumenu.o",  "haikufont.o",
        "androidterm.o",   "androidfns.o", "androidfont.o",
        "androidselect.c", "androidvfs.c", "sfntfont-android.c",
        "sfntfont.c",
    };
    for (some_machine_objects) |name| {
        run_doc.addArg(name);
        const stem = name[0 .. name.len - 1];
        const extension = if (std.mem.startsWith(u8, name, "ns") or
            std.mem.startsWith(u8, name, "macfont")) "m" else "c";
        run_doc.addFileInput(b.path(b.fmt("src/{s}{s}", .{ stem, extension })));
    }
    for (base_sources) |s| {
        var name: []const u8 = s;
        if (std.mem.startsWith(u8, name, "src/")) name = name["src/".len..];
        // Pass .o names like upstream's doc_obj: make-docfile scans the
        // .c but writes the ^_S record with the name as given, and
        // help-C-file-name matches that record against build-files
        // (buildobj.h), which holds .o names.
        const o_name = b.fmt("{s}.o", .{name[0 .. name.len - 2]});
        run_doc.addArg(o_name);
        run_doc.addFileInput(b.path(s));
    }
    if (target.result.os.tag == .linux) {
        const linux_doc_sources = [_][]const u8{ "dbusbind.c", "dynlib.c", "inotify.c" };
        for (linux_doc_sources) |name| {
            run_doc.addArg(b.fmt("{s}o", .{name[0 .. name.len - 1]}));
            run_doc.addFileInput(b.path(b.fmt("src/{s}", .{name})));
        }
    }
    // Scan emacs-module.c for its doc strings when modules are on, so its
    // DEFUN primitives (Fmodule_load etc.) carry doc strings in etc/DOC --
    // mirrors the globals.h re-add above.  Passed as the .o name upstream's
    // doc_obj uses (make-docfile rewrites to .c after the -d src chdir).
    // Track-B B-Z: widened to modules_runtime so the doc strings are scanned
    // under the Zig module subsystem too.
    if (modules_runtime) {
        run_doc.addArg("emacs-module.o");
        run_doc.addFileInput(b.path("src/emacs-module.c"));
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
        // emacs-module.o is MODULES_OBJ (not base_obj); upstream's $(obj)
        // folds it into buildobj when modules are on, so mirror that here.
        // Track-B B-Z: widened to modules_runtime so the entry is present
        // under the Zig module subsystem too.
        if (modules_runtime) appendBuildobjEntry(a, &buf, "src/emacs-module.c") catch @panic("build.zig: OOM building buildobj.h");
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
    // config.h generation above. The tool is pure/deterministic: it takes
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

    // Verify the generated config.h carries the load-bearing subset of
    // knobs the rest of the build relies on, via a native Zig tool
    // (build-aux/verify-config.zig). Standalone -- does NOT depend on exe.
    const verify_config_tool = b.addExecutable(.{
        .name = "verify-config",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/verify-config.zig"),
        }),
    });
    const verify_config_cmd = b.addRunArtifact(verify_config_tool);
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
    const diff_config_tool = b.addExecutable(.{
        .name = "config-diff",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = b.path("build-aux/config-diff.zig"),
        }),
    });
    const diff_config_cmd = b.addRunArtifact(diff_config_tool);
    diff_config_cmd.addFileArg(config_h_file);
    diff_config_cmd.addFileArg(b.path("src/config.h"));
    const diff_config_step = b.step(
        "config-diff",
        "Report the config.h knob gap vs the gitignored reference",
    );
    diff_config_step.dependOn(base_config.step);
    diff_config_step.dependOn(&diff_config_cmd.step);

    // collect-config: the SIMD complete-DEF collector (tools/config-collect).
    // Scans any autoconf-style config file for every `#define`/`#undef`
    // (incl. indented `# define`, `# undef` and the `/* #undef */` comment
    // form) and prints the sorted-unique knob set -- the completeness
    // instrument: config.in universe vs config.h.in template vs the
    // generated config.h.  Standalone; runs on the lean template by default.
    const config_collect_dep = b.dependency("config_collect", .{});
    const config_collect_tool = b.addExecutable(.{
        .name = "config-collect",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
            .root_source_file = config_collect_dep.path("src/main.zig"),
        }),
    });
    const collect_config_cmd = b.addRunArtifact(config_collect_tool);
    collect_config_cmd.addFileArg(b.path("src/config.h.in"));
    const collect_config_step = b.step(
        "collect-config",
        "SIMD-scan a config file for the complete DEF knob set (default: src/config.h.in)",
    );
    collect_config_step.dependOn(&collect_config_cmd.step);

    // Create temacs executable
    const exe = b.addExecutable(.{
        .name = "temacs",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    // MSVC ABI: the CRT/Windows SDK promote a huge number of POSIX/ANSI
    // function names and deprecated APIs to hard deprecation ERRORS
    // (open/close/fopen/strcpy/getenv/strerror/unlink/wcrtomb, and winsock
    // inet_addr/inet_ntoa).  Emacs's w32 code uses the POSIX/ANSI names on
    // purpose (upstream's MSVC build does exactly this), so suppress all of
    // them at the module level -- this reaches EVERY TU in the module
    // regardless of per-file compile flags (the per-file -D only filters
    // some paths).  No effect on the MinGW ABI (its CRT doesn't gate these
    // on the same macros).
    if (target.result.abi == .msvc) {
        applyMsvcCrtWarnings(exe.root_module);
    }
    // The 8MB default main-thread stack overflows during deep batch Lisp
    // work in Debug builds (-O0 eval frames are large): the darwin
    // loadup dump died at cus-start (handle_sigsegv longjmps back to the
    // command loop and loadup re-enters), and the native Windows runner
    // died with a silent abort while byte-compiling diary-icalendar.el
    // (its compile session source-loads icalendar-parser/ast/recur and
    // org-element-ast).  The runtime setrlimit in emacs.c cannot resize
    // an already-allocated main thread on macOS or Windows, so set the
    // main-thread stack size at link time.
    if (target.result.os.tag == .macos or target.result.os.tag == .windows)
        exe.stack_size = 64 * 1024 * 1024;
    // Non-PIE: zig-cc PIE + pdumper mis-relocates static pointers
    // (mem_root, dump_hooks, ...) -> NULL/garbage on dump load ->
    // crashes. A non-PIE binary has fixed static addresses, so no
    // runtime relocation is needed. (The target requires PIC code,
    // but PIC code in a non-PIE exe still gets fixed statics.)
    // Darwin always slides the main executable (DYLD_NO_PIE is gone on
    // modern macOS), so a non-PIE dump would have stale absolute
    // addresses; keep the PIE relocation model there instead.
    if (target.result.os.tag != .macos)
        exe.pie = false;

    // Embed the Windows application manifest (nt/emacs-{x64,x86}.manifest)
    // into temacs.exe.  The manifest advertises the Windows 10+
    // <supportedOS> GUIDs; without them GetVersion()/GetVersionEx()
    // (src/w32fns.c) report 6.2 (Windows 8) even on Windows 10/11, which
    // makes w32con_setup_virtual_terminal (src/w32console.c) fail the
    // `w32_major_version >= 10' gate and DISABLE_VIRTUAL_TERMINAL the
    // console.  VTP off then routes output through the legacy
    // WriteConsoleOutputCharacter path (w32con_write_glyphs else-branch),
    // which misrenders multibyte (CJK) text on Windows Terminal (the
    // VT-native host).  The autotools build embeds this manifest via
    // WINDRES (nt/Makefile.in + configure.ac EMACS_MANIFEST); the zig
    // build previously had no equivalent, so CJK output was garbled.
    if (target.result.os.tag == .windows) {
        // The compatibility GUIDs (the part that fixes version detection)
        // are arch-independent; aarch64-windows has no dedicated manifest,
        // so it reuses the x64 file.
        const manifest_path: []const u8 = switch (target.result.cpu.arch) {
            .x86 => "nt/emacs-x86.manifest",
            else => "nt/emacs-x64.manifest",
        };
        exe.win32_manifest = b.path(manifest_path);
    }

    // temacs includes <config.h>; the generated file (from src/config.h.in +
    // src/config_values.txt) is provided via the module include path, so the
    // compile must wait for the generator. Cross targets use the
    // target-tagged config above.
    exe.root_module.addIncludePath(target_config_h_file.file.dirname());
    exe.step.dependOn(target_config_h_file.step);

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
    // w32.c provides num_processors/list_system_processes itself on
    // Windows, so skip the package there (it stays in the cross-compile
    // gate); linking both would duplicate the symbols.
    if (target.result.os.tag != .windows)
        exe.root_module.linkLibrary(gnulib_nproc_lib);

    // gnulib-tempname: an independent Zig package (tools/gnulib-tempname)
    // providing gnulib's temporary-name generation (gen_tempname /
    // gen_tempname_len / mkostemp, lib/tempname.c + lib/mkostemp.c),
    // backing `make-temp-file', filelock and call-process temp files.
    // getrandom with the clock-mix fallback (arc4random_buf on Darwin),
    // raw openat/mkdir/newfstatat syscalls on Linux and libc
    // open/mkdir/lstat on Darwin, errno set on failure as the C code
    // does. Built ReleaseFast (leaf generation).
    const gnulib_tempname_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_tempname", .{}).path("src/tempname.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true, // Darwin backend uses libc open/mkdir/lstat
    });
    const gnulib_tempname_lib =
        b.addLibrary(.{ .name = "gnulib-tempname", .root_module = gnulib_tempname_mod });
    exe.root_module.linkLibrary(gnulib_tempname_lib);
    if (target.result.os.tag == .windows)
        gnulib_tempname_mod.linkSystemLibrary("bcrypt", .{}); // Windows RNG

    // msvc-posix: MSVC-backend-only provider of the POSIX-name file/dir
    // functions the UCRT does not export (_open/_close/_mkdir/_unlink/
    // _getcwd/_stati64 aliases), needed by the MSVC command-line tools
    // (emacsclient, etags), the Zig gnulib-tempname package, and temacs.
    // Built only when the target selects the MSVC ABI; a Zig package (not a
    // C shim) is used because Emacs's w32 headers macro-map these very
    // names, which would rewrite a C wrapper's body.
    //
    // Two consumer flavors, differing only in whether getcwd/stat/fstat/
    // lstat are exported: temacs's own src/w32.c defines all four, so
    // exporting them there would duplicate symbols; the lib-src tools do not
    // link w32.c and rely on this package for them.
    const msvc_posix_mod = blk: {
        const opts = b.addOptions();
        opts.addOption(bool, "include_file_status_fns", true);
        const m = b.createModule(.{
            .root_source_file = b.dependency("msvc_posix", .{}).path("src/posix.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true, // every wrapper is a thin CRT call
        });
        m.addOptions("build_options", opts);
        break :blk m;
    };
    const msvc_posix_lib =
        b.addLibrary(.{ .name = "msvc-posix", .root_module = msvc_posix_mod });

    // Temacs flavor: exclude the getcwd/stat/fstat/lstat exports that
    // src/w32.c already provides.  Linked only on the MSVC ABI.
    const msvc_posix_temacs_mod = blk: {
        const opts = b.addOptions();
        opts.addOption(bool, "include_file_status_fns", false);
        const m = b.createModule(.{
            .root_source_file = b.dependency("msvc_posix", .{}).path("src/posix.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        m.addOptions("build_options", opts);
        break :blk m;
    };
    const msvc_posix_temacs_lib =
        b.addLibrary(.{ .name = "msvc-posix-temacs", .root_module = msvc_posix_temacs_mod });
    if (target.result.os.tag == .windows and target.result.abi == .msvc)
        exe.root_module.linkLibrary(msvc_posix_temacs_lib);

    // gnulib-fsusage: an independent Zig package (tools/gnulib-fsusage)
    // providing gnulib's file-system space query (get_fs_usage,
    // lib/fsusage.c), backing `file-system-info'. Reads statfs(2) via a
    // raw syscall on Linux and maps the fields into the gnulib struct
    // fs_usage, with errno set on failure (fileio.c tests ENOSYS); the
    // Darwin backend uses libc statfs. Built ReleaseFast (leaf query).
    const gnulib_fsusage_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_fsusage", .{}).path("src/fsusage.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true, // Darwin backend uses libc statfs
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
        .link_libc = true, // Darwin backend uses libc getloadavg
    });
    const gnulib_getloadavg_lib =
        b.addLibrary(.{ .name = "gnulib-getloadavg", .root_module = gnulib_getloadavg_mod });
    // w32.c provides getloadavg itself on Windows.
    if (target.result.os.tag != .windows)
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
    // w32.c provides careadlinkat itself on Windows.
    if (target.result.os.tag != .windows)
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
        .link_libc = true, // Darwin backend uses libc sysctl
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
    // targets fall back to mode-bit preservation via libc (Windows
    // emulates fchmod through the CRT handle + SetFileInformationByHandle).
    // Built ReleaseFast (leaf copy operation).
    const gnulib_acl_mod = b.createModule(.{
        .root_source_file = b.dependency("gnulib_acl", .{}).path("src/acl.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true, // non-Linux chmod/fchmod fallback
    });
    const gnulib_acl_lib =
        b.addLibrary(.{ .name = "gnulib-acl", .root_module = gnulib_acl_mod });
    // w32.c provides the acl_* emulation itself on Windows.
    if (target.result.os.tag != .windows)
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
    // w32.c provides rpl_pipe2 itself on Windows; close_stream and
    // set_binary_mode come from lib/close-stream.c and lib/binary-io.c.
    if (target.result.os.tag != .windows)
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
        .link_libc = true, // Darwin backend uses libc clock_gettime
    });
    const emacs_time_lib =
        b.addLibrary(.{ .name = "emacs-time", .root_module = emacs_time_mod });
    exe.root_module.linkLibrary(emacs_time_lib);

    // zeln-jit: the in-process lightweight Tier-1 engine (tools/zeln-jit,
    // docs/zeln-jit.md).  Its x86-64 emitter is integrated with the
    // bytecode hotness hook; other targets retain AOT/interpreter
    // fallback.  Built ReleaseFast: compilation and generated dispatch are
    // runtime paths.  Pure Zig, no libc, no external toolchain -- the
    // whole point is NO gcc/libgccjit and NO subprocess.
    const zeln_jit_mod = b.createModule(.{
        .root_source_file = b.dependency("zeln_jit", .{}).path("src/jit.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    const zeln_jit_lib =
        b.addLibrary(.{ .name = "zeln-jit", .root_module = zeln_jit_mod });
    exe.root_module.linkLibrary(zeln_jit_lib);

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
        .link_libc = true, // Darwin backend uses libc nanosleep
    });
    const emacs_nanosleep_lib = b.addLibrary(.{
        .name = "emacs-nanosleep",
        .root_module = emacs_nanosleep_mod,
    });
    exe.root_module.linkLibrary(emacs_nanosleep_lib);

    // emacs-bignum: the native Zig reimplementation of the GMP integer
    // API subset Emacs's bignum support uses (src/bignum.c and the mpz_*
    // call sites in data.c/print.c/lread.c/emacs-module.c/timefns.c/
    // pdumper.c). Linked in place of -lgmp; tools/bignum/include/gmp.h
    // shadows the system header so no GMP headers are needed on any
    // target. Exports are C-ABI compatible with libgmp (64-bit limbs,
    // same mpz_t layout, memory callbacks via mp_set_memory_functions).
    const bignum_mod = b.createModule(.{
        .root_source_file = b.dependency("bignum", .{})
            .path("src/bignum.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true, // C ABI exports (size_t, callbacks)
    });
    const bignum_lib = b.addLibrary(.{
        .name = "emacs-bignum",
        .root_module = bignum_mod,
    });
    exe.root_module.linkLibrary(bignum_lib);
    exe.root_module.addIncludePath(
        b.dependency("bignum", .{}).path("include"),
    );

    // Cross-platform gate: compile every independent Zig package for the
    // current target without the C-based temacs exe. The gnulib and
    // os-layer packages are the parts claimed to build on every target;
    // where the full C port or the final link against target system
    // libraries is not yet available (native Windows today), CI verifies
    // this layer as the authoritative cross-compile gate.
    const zig_packages_step = b.step(
        "zig-packages",
        "Compile all independent Zig packages for the current target",
    );
    inline for (.{
        gnulib_str_lib,
        gnulib_ctype_lib,
        gnulib_stdbit_lib,
        gnulib_hash_lib,
        gnulib_sig2str_lib,
        gnulib_filemode_lib,
        gnulib_timespec_lib,
        gnulib_filevercmp_lib,
        gnulib_sigdescr_np_lib,
        gnulib_nproc_lib,
        gnulib_tempname_lib,
        gnulib_fsusage_lib,
        gnulib_getloadavg_lib,
        gnulib_careadlinkat_lib,
        gnulib_dtoastr_lib,
        gnulib_stat_time_lib,
        gnulib_boot_time_lib,
        gnulib_c_strcase_lib,
        gnulib_acl_lib,
        gnulib_time_rz_lib,
        gnulib_io_lib,
        emacs_time_lib,
        emacs_nanosleep_lib,
        bignum_lib,
    }) |lib| {
        zig_packages_step.dependOn(&lib.step);
    }

    // is_windows / is_musl / modules_runtime / modules_zig_provider are
    // computed early (right after the option declarations above) so the
    // make-docfile / doc-scan / buildobj gates can read them; the source-
    // compile and link blocks here reuse the same consts.

    // emacs-dynlib (Track-B B-Z, HAVE_MODULES_ZIG): the independent Zig
    // dynamic-module LOADER, the native-linking parallel to the upstream
    // HAVE_MODULES subsystem (which compiles src/dynlib.c).  When
    // modules_zig_provider is on, src/dynlib.c is NOT compiled (the three
    // dynlib.c addCSourceFile sites above are gated on its inverse) and this
    // package satisfies the identical dynlib_* ABI at link time -- the swap
    // is purely build/link-level, mirroring the gnulib-* replacements (the
    // package's `export fn` symbols replace what dynlib.c would emit).  α
    // slice: the package wraps libc dlopen/dlsym/dlclose/dlerror/dladdr
    // (RTLD_LAZY|RTLD_GLOBAL on open, matching dynlib.c:279), so the load
    // still routes through ld.so; the raw-syscall ELF loader (Option γ)
    // replaces ONLY the extern "c" fn dlopen bodies here later, without
    // touching C.  POSIX-only this cycle (modules_zig_provider is already
    // false on Windows/musl, so the package is never built there).  Gating
    // the whole block on modules_zig_provider guarantees the off-path
    // default never even resolves the dependency -- zero footprint.
    if (modules_zig_provider) {
        const emacs_dynlib_mod = b.createModule(.{
            .root_source_file = b.dependency("emacs_dynlib", .{}).path("src/dynlib.zig"),
            .target = target,
            // ReleaseFast (leaf libc-call wrappers) so it pulls in no Zig
            // runtime/panic handler the C executable would have to satisfy.
            .optimize = .ReleaseFast,
            .link_libc = true, // wraps libc dlopen/dlsym/dlclose/dlerror/dladdr
        });
        const emacs_dynlib_lib =
            b.addLibrary(.{ .name = "emacs-dynlib", .root_module = emacs_dynlib_mod });
        exe.root_module.linkLibrary(emacs_dynlib_lib);
        zig_packages_step.dependOn(&emacs_dynlib_lib.step);
    }

    // gccjit native-comp (-Dnative-comp, HAVE_NATIVE_COMP).  libgccjit is a
    // HOST library: it links against the host's libgccjit.so and cannot be
    // cross-built (the gccjit path emits a host ELF .eln).  Gate it to a
    // native glibc-Linux build, mirroring the zeln is_native_target gate at
    // build.zig:2158/2390; any -Dtarget=... cross, musl, windows or macOS
    // forces the switch OFF (and the off-by-default behavior is untouched).
    // Evaluated here (top-level) so both the source-compile block and the
    // link-library block below can read it.
    const native_comp_target = enable_native_comp and
        target.result.cpu.arch == b.graph.host.result.cpu.arch and
        target.result.os.tag == b.graph.host.result.os.tag and
        target.result.abi == b.graph.host.result.abi and
        target.result.os.tag == .linux and !is_musl;
    if (enable_native_comp and !native_comp_target)
        std.debug.print("build: -Dnative-comp requested but the target is not native glibc-Linux; forcing the gccjit path OFF (libgccjit is host-only)\n", .{});
    // Host (glibc) include dirs must not leak into the musl compile:
    // -I/usr/include would inject glibc's C23 redirects (__isoc23_*)
    // into a musl build. musl uses zig's bundled headers instead.
    // Host (glibc) include dirs must not leak into the musl compile:
    // -I/usr/include would inject glibc's C23 redirects (__isoc23_*)
    // into a musl build. musl uses zig's bundled headers instead.

    // Add base C sources with proper flags
    //
    // emacs-module.h is GENERATED (upstream: configure.ac:5163
    // AC_CONFIG_FILES from src/emacs-module.in.h + the module-env-*
    // snippets); it is gitignored, so a fresh checkout has no
    // src/emacs-module.h and the dynamic-module compiles would fail.  The
    // gen-emacs-module-h step writes it into the source tree (mirroring
    // upstream's configure) and must precede both the emacs-module.c
    // compile and the mod-test sample module compile.  Defined at build()
    // top level (platform-independent) so both the exe compile loop below
    // and the modules-test step can depend on it.
    const run_gen_emh: ?*std.Build.Step.Run = if (modules_runtime) blk: {
        const gen_emh_dep = b.dependency("gen_emacs_module_h", .{});
        const gen_emh_tool = b.addExecutable(.{
            .name = "gen-emacs-module-h",
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .optimize = .Debug,
                .root_source_file = gen_emh_dep.path("src/main.zig"),
            }),
        });
        const run_gen_emh_local = b.addRunArtifact(gen_emh_tool);
        run_gen_emh_local.setCwd(b.path("."));
        // Track the template + snippet inputs so the run cache invalidates
        // on their content; the major version rides in as a literal arg.
        // The tool's 4th arg is the snippet DIRECTORY; the 8 snippet files
        // follow as extra tracked args (ignored by the tool, but they keep
        // the run cache invalidating on snippet edits).
        run_gen_emh_local.addFileArg(b.path("src/emacs-module.in.h"));
        run_gen_emh_local.addArg("src/emacs-module.h");
        run_gen_emh_local.addArg("32");
        run_gen_emh_local.addArg("src");
        run_gen_emh_local.addFileArg(b.path("src/module-env-25.h"));
        run_gen_emh_local.addFileArg(b.path("src/module-env-26.h"));
        run_gen_emh_local.addFileArg(b.path("src/module-env-27.h"));
        run_gen_emh_local.addFileArg(b.path("src/module-env-28.h"));
        run_gen_emh_local.addFileArg(b.path("src/module-env-29.h"));
        run_gen_emh_local.addFileArg(b.path("src/module-env-30.h"));
        run_gen_emh_local.addFileArg(b.path("src/module-env-31.h"));
        run_gen_emh_local.addFileArg(b.path("src/module-env-32.h"));
        // Writes into the source tree (src/emacs-module.h, gitignored); the
        // run cache cannot track the output file, so always re-run (cheap).
        run_gen_emh_local.has_side_effects = true;
        exe.step.dependOn(&run_gen_emh_local.step);
        break :blk run_gen_emh_local;
    } else null;

    if (!is_windows) {
        // Unix-like systems (macOS, Linux) - with libxml2 include path
        const base_flags_core = [_][]const u8{
            // No -O flag (module Debug=-O0). -O2 has a separate bug (a
            // -O2 file corrupts lisp state during dump -> bad relocation
            // entries -> SIGSEGV on load) that is NOT fixed by non-PIE
            // or pdumper.c -O0; stay at -O0 until that is root-caused.
            "-std=gnu2x", // Allow C23 features like _Static_assert without message
            "-fno-common",
            "-fno-strict-aliasing",
            // The fixnum range macros compare int values against the
            // 61-bit bounds; on targets where those are provably true
            // clang flags them (same suppression the Windows build
            // uses).
            "-Wno-tautological-constant-out-of-range-compare",
            // macOS deprecates some APIs (e.g. the older
            // posix_spawn_file_actions_addchdir_np name); keep the
            // shared sources compiling until the call sites migrate.
            "-Wno-deprecated-declarations",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
            "-Isrc",
            "-Ilib",
            "-Ilib/malloc", // Gnulib generated headers
        };
        // musl reuses the C23/execinfo shims from lib/w32 (generic
        // headers; the directory name is historical) and must NOT see
        // glibc's /usr/include (its C23 redirects would leak
        // __isoc23_* symbols into the musl link). macOS also lacks the
        // C23 <stdbit.h> (and friends), so it gets the same shims while
        // keeping the Homebrew system-dir flags. Duplicated -I entries
        // are harmless; the fixed 4-slot array keeps the concat type.
        const unix_extra_inc = if (is_musl)
            [_][]const u8{ "-Ilib/w32", "-Ilib/w32", "-Ilib/w32", "-Ilib/w32" }
        else if (target.result.os.tag == .macos)
            [_][]const u8{ "-I/usr/include", "-I/usr/include/libxml2", "-Ilib/w32", "-Ilib/w32" }
        else
            [_][]const u8{ "-I/usr/include", "-I/usr/include/libxml2", "-I/usr/include", "-I/usr/include" };
        const base_flags_full = base_flags_core ++ unix_extra_inc;
        const base_flags: []const []const u8 = &base_flags_full;

        // src/timefns.c:monotonic_coarse_timespec is provided by the
        // emacs-time Zig package (per-platform native backend, no libc)
        // instead of C; the body is #ifndef'd out in src/timefns.c when
        // EMACS_USE_ZIG_MONOTONIC_COARSE is defined. Passed per-file (like
        // lib/mktime.c above) so only this translation unit is affected.
        const timefns_flags = base_flags_full ++
            [_][]const u8{"-DEMACS_USE_ZIG_MONOTONIC_COARSE"};

        for (base_sources) |src| {
            const flags: []const []const u8 =
                if (std.mem.eql(u8, src, "src/timefns.c")) &timefns_flags else base_flags;
            // On every ncurses/terminfo platform (macOS with the vendored
            // libncurses, and glibc Linux with the system libncurses),
            // tgetent/tgetstr/tputs/tgoto/UP/BC/PC come from the ncurses
            // terminfo database.  Emacs's own termcap.c only reads
            // /etc/termcap (absent on modern systems); if compiled it
            // provides a tgetent that SHADOWS ncurses's and fails to find
            // any terminal (e.g. interactive `emacs -nw` aborts with
            // "Cannot open terminfo database file"), and tparam.c's
            // BC/UP/tgoto would duplicate the ncurses globals.  So both are
            // skipped on ncurses builds (terminfo.c supplies tparam via
            // ncurses tparm; same reasoning as the w32 skip below - upstream
            // leaves TERMCAP_OBJ empty when a terminfo library is present).
            // musl keeps termcap.c (no ncurses; TERMCAP_OBJ=termcap.o);
            // w32 needs no terminfo.
            if (!is_windows and !is_musl and
                (std.mem.eql(u8, src, "src/termcap.c") or
                    std.mem.eql(u8, src, "src/tparam.c")))
                continue;
            // src/comp.c is in base_obj (Makefile.in:459), so the loop compiles
            // it with base_flags.  When -Dnative-comp is effective, comp.c needs
            // <libgccjit.h> (NOT on the default include path) and the
            // HAVE_NATIVE_COMP macro, so SKIP it here and re-add it below with
            // the gccjit private include dir on its flags (mirrors the
            // termcap/tparam skip above).  OFF-path: native_comp_target is false
            // => comp.c is compiled here as today (byte-identical).
            if (native_comp_target and std.mem.eql(u8, src, "src/comp.c"))
                continue;
            exe.root_module.addCSourceFile(.{
                .file = b.path(src),
                .flags = flags,
            });
        }

        // Phase-2.1 subsystem switches (all OFF by default => the build is
        // byte-identical to main). When ON they inject -DHAVE_* (activating
        // the matching #ifdef blocks); the native-comp Zig path also compiles
        // src/compz.c. OFF => all no-ops.
        if (enable_native_comp_zig) {
            exe.root_module.addCMacro("HAVE_NATIVE_COMP_ZIG", "1");
            if (target.result.cpu.arch == .x86_64)
                exe.root_module.addCMacro("ZELN_JIT_ARCH_X86_64", "1");
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/compz.c"),
                .flags = base_flags,
            });
        }
        // gccjit native-comp (-Dnative-comp, HAVE_NATIVE_COMP).  comp.c was
        // skipped in the base-source loop above (it needs <libgccjit.h>);
        // re-add it here with the host gcc private include dir prepended so
        // the gccjit header is reachable.  The include dir is host/gcc-version
        // specific, so derive it from the build's C driver via
        // `cc -print-file-name=include` (honoring LIBGCCJIT_CFLAGS as an
        // override for distros/packagers), and GATE the whole feature to
        // native glibc-Linux (native_comp_target).  The LIBGCCJIT_HAVE_*
        // feature macros (comp.c:186/233/305/...) are intentionally NOT
        // probed -- the guarded code is optional gccjit optimization and
        // comp.c links/runs without them.
        if (native_comp_target) {
            exe.root_module.addCMacro("HAVE_NATIVE_COMP", "1");
            // libgccjit lives in gcc's PRIVATE install tree (the header
            // libgccjit.h and libgccjit.so are under /usr/lib/gcc/<triplet>/
            // <version>/), which is NOT on zig's default search path.  Discover
            // that tree by globbing /usr/lib/gcc/*/*/ at build time -- robust
            // across host triplets and gcc versions, and needs no subprocess
            // (the single-threaded build Io cannot run `cc -print-file-name=`;
            // std.fs dir iteration works fine at config time).  Wire in:
            //   - the include dir -> a -I on comp.c's flags;
            //   - the lib dir (the version dir itself) -> addLibraryPath so
            //     linkSystemLibrary("gccjit") can resolve libgccjit.so.
            var gccjit_inc: []const u8 = "";
            var gccjit_lib_dir: []const u8 = "";
            gccDiscoverGccjit(b, io, &gccjit_inc, &gccjit_lib_dir);
            if (gccjit_lib_dir.len > 0)
                exe.root_module.addLibraryPath(.{ .cwd_relative = gccjit_lib_dir });
            if (gccjit_inc.len > 0) {
                const inc_arg = std.fmt.allocPrint(b.allocator, "-I{s}", .{gccjit_inc}) catch unreachable;
                // comp.c flags = base_flags ++ .{inc_arg} (build-time slice
                // on the build allocator; lives for the build graph lifetime).
                const comp_flags = b.allocator.alloc([]const u8, base_flags.len + 1) catch unreachable;
                for (base_flags, 0..) |f, i| comp_flags[i] = f;
                comp_flags[base_flags.len] = inc_arg;
                exe.root_module.addCSourceFile(.{
                    .file = b.path("src/comp.c"),
                    .flags = comp_flags,
                });
            } else {
                // No private include dir resolved: fall back to base_flags and
                // let the compiler's default search path try to find the header.
                exe.root_module.addCSourceFile(.{
                    .file = b.path("src/comp.c"),
                    .flags = base_flags,
                });
            }
            // comp.c (gccjit) calls md5_stream (src/comp.c:755) to hash the
            // ABI. lib/md5-stream.c is normally excluded from the libgnu set
            // (build.zig:3046) because off-path nothing references it; with
            // HAVE_NATIVE_COMP on, comp.c does, so compile it here.  Its md5_*
            // calls resolve to the gnulib-hash Zig package (lib/md5.c itself
            // stays excluded -- the package provides the algorithm).
            exe.root_module.addCSourceFile(.{
                .file = b.path("lib/md5-stream.c"),
                .flags = base_flags,
            });
        }
        // .zeln-only builds (HAVE_NATIVE_COMP_ZIG without gccjit): compz.c's
        // comp_z_hash_source_file also streams via md5_stream, so compile
        // lib/md5-stream.c here too (same gnulib-hash Zig package linkage).
        else if (enable_native_comp_zig and !native_comp_target) {
            exe.root_module.addCSourceFile(.{
                .file = b.path("lib/md5-stream.c"),
                .flags = base_flags,
            });
        }
        // Dynamic modules (Track B, plan section 13).  -DHAVE_MODULES
        // activates the upstream module runtime (lread.c module-file
        // detection via MODULES_SUFFIX, eval.c funcall_module dispatch,
        // alloc.c make_user_ptr, emacs.c syms_of_module init).  config.h
        // carries MODULES_SUFFIX (set in src/config_values.txt + the
        // per-target config-overrides.zig overrides), so the lread.c #ifdef
        // HAVE_MODULES blocks compile.  emacs-module.c is the runtime
        // implementation -- it is src/Makefile.in's MODULES_OBJ, a separate
        // @MODULES_OBJ@ var (comment at Makefile.in:270), so it is NOT in
        // parseBaseSources's base_obj and must be compiled here exactly like
        // compz.c above.  musl is forced off (modules_runtime) since static
        // musl cannot dlopen; on glibc 2.34+ no -ldl is needed (dlopen et al.
        // live in libc).  Track-B B-Z: widened from enable_modules to
        // modules_runtime so the Zig module subsystem (-Dmodules-zig) also
        // activates the shared runtime (HAVE_MODULES macro + emacs-module.c);
        // HAVE_MODULES_ZIG is then emitted only when the Zig dynlib provider
        // is actually selected (modules_zig_provider -- POSIX this cycle).
        if (modules_runtime) {
            exe.root_module.addCMacro("HAVE_MODULES", "1");
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/emacs-module.c"),
                .flags = base_flags,
            });
        }
        if (modules_zig_provider) exe.root_module.addCMacro("HAVE_MODULES_ZIG", "1");

        // TERMCAP_OBJ: upstream builds terminfo.o when TERMINFO, else
        // termcap.o (+ tparam.o on MS-DOS).  Every ncurses/terminfo
        // platform (macOS vendored libncurses, glibc Linux system
        // libncurses) uses terminfo.c (tparam via ncurses tparm) to
        // replace the termcap/tparam pair skipped above.  musl stays on
        // termcap.c (no ncurses); w32 has no terminfo.
        if (!is_windows and !is_musl) {
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/terminfo.c"),
                .flags = base_flags,
            });
        }

        // Darwin-only shims: the glibc-style __errno_location the Zig
        // gnulib packages extern, getrandom(2) for the secure-random
        // callers, and the darwin_getloadavg alias for the Zig
        // getloadavg package.  Mirrors the w32-stubs.c pattern.
        if (target.result.os.tag == .macos) {
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/darwin-shims.c"),
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
            // dynlib.c (dlopen wrapper) backs treesit language loading and
            // module support on POSIX systems; the POSIX branch is selected
            // by HAVE_UNISTD_H and uses dlopen/dlsym from libc.  Track-B B-Z
            // (-Dmodules-zig): when the Zig emacs-dynlib package supplies the
            // dynlib_* ABI, dynlib.c is dropped here to avoid duplicate symbol
            // definitions at link -- the package's `export fn` names satisfy
            // the identical dynlib.h contract.
            if (!modules_zig_provider) {
                exe.root_module.addCSourceFile(.{
                    .file = b.path("src/dynlib.c"),
                    .flags = base_flags,
                });
            }
        }

        // Linux-only sources. Mirrors the kqueue gate above but keyed on
        // .linux, inside the !is_windows branch.
        //   - src/dynlib.c:HAVE_MODULES is undef in config.h, but treesit.c
        //     calls dynlib_{error,open,sym,addr} unconditionally; the POSIX
        //     branch uses dlopen/dlsym (in libc on glibc).  Track-B B-Z
        //     (-Dmodules-zig): when the Zig emacs-dynlib package supplies the
        //     dynlib_* ABI, dynlib.c is dropped here to avoid duplicate symbol
        //     definitions at link.
        //   - src/inotify.c:HAVE_INOTIFY=1 in config.h; inotify_init1 in libc.
        //   - src/dbusbind.c:HAVE_DBUS=1 in config.h; needs the two dbus
        //     include dirs `pkg-config --cflags dbus-1` reports on this host.
        if (target.result.os.tag == .linux) {
            if (!modules_zig_provider) {
                exe.root_module.addCSourceFile(.{
                    .file = b.path("src/dynlib.c"),
                    .flags = base_flags,
                });
            }
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/inotify.c"),
                .flags = base_flags,
            });
            const dbus_flags = base_flags_full ++ [_][]const u8{
                "-I/usr/include/dbus-1.0",
                "-I/usr/lib64/dbus-1.0/include",
            };
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/dbusbind.c"),
                .flags = &dbus_flags,
            });

            // -Dpgtk: the PGTK GUI display modules (configure.ac's
            // PGTK_OBJ + WINDOW_SYSTEM_OBJ + XGSELOBJ + FONT_OBJ for the
            // cairo/harfbuzz font stack): pgtkterm/pgtkfns/pgtkmenu/
            // pgtkselect/pgtkim/xsettings, fontset/fringe/image, xgselect,
            // ftfont/ftcrfont/hbfont.  The GTK3/glib/pango/cairo/harfbuzz
            // include dirs + libs come from pkg-config via the
            // linkSystemLibrary calls near the other system libraries.
            if (pgtk_target) {
                const pgtk_sources = [_][]const u8{
                    "src/pgtkterm.c",
                    "src/pgtkfns.c",
                    "src/pgtkmenu.c",
                    "src/pgtkselect.c",
                    "src/pgtkim.c",
                    "src/xsettings.c",
                    "src/xgselect.c",
                    "src/fontset.c",
                    "src/fringe.c",
                    "src/image.c",
                    "src/ftfont.c",
                    "src/ftcrfont.c",
                    "src/hbfont.c",
                    // GTK_OBJ: USE_GTK makes HAVE_EXT_TOOL_BAR true
                    // (lisp.h), so xdisp.c/pgtkfns.c call
                    // update_frame_tool_bar which gtkutil.c provides
                    // (plus the xg_* widget helpers pgtkmenu.c uses);
                    // emacsgtkfixed.o is the fixed GTK3 subclass.
                    "src/gtkutil.c",
                    "src/emacsgtkfixed.c",
                };
                for (pgtk_sources) |gsrc| {
                    exe.root_module.addCSourceFile(.{
                        .file = b.path(gsrc),
                        .flags = base_flags,
                    });
                }
            }
        }

        // Add Gnulib sources
        const libgnu_flags_core = [_][]const u8{
            // No -O flag: see base_flags (separate -O2 lisp-corruption bug).
            "-std=gnu2x",
            "-fno-common",
            "-fno-strict-aliasing",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
            "-Isrc",
            "-Ilib",
            "-Ilib/malloc", // Gnulib generated headers
        };
        const libgnu_flags_full = libgnu_flags_core ++ unix_extra_inc;
        const libgnu_flags: []const []const u8 = &libgnu_flags_full;

        for (libgnu_sources) |src| {
            exe.root_module.addCSourceFile(.{
                .file = b.path(src),
                .flags = libgnu_flags,
            });
        }
        // musl lacks glibc's <execinfo.h>; the lib/w32 shim declares the
        // backtrace family and this no-op implementation satisfies the
        // fatal-backtrace call sites in src/sysdep.c.
        if (is_musl) {
            exe.root_module.addCSourceFile(.{
                .file = b.path("lib/w32/execinfo.c"),
                .flags = libgnu_flags,
            });
        }
    } else {
        // Windows - without libxml2 include path
        // Include order matters: lib/ holds the committed gnulib
        // replacement headers (generated against glibc), lib/w32 holds
        // shims for headers mingw lacks (alloca/stdbit/sys-random/
        // byteswap/execinfo) so their include_next resolves, and nt/inc
        // is upstream's native Windows header set (ms-w32.h pulls it in
        // via conf_post.h once config.h defines WINDOWSNT).  The search
        // order mirrors the autotools Windows build (-I../lib -I../nt/inc).
        const base_flags_core_w32 = [_][]const u8{
            "-std=gnu2x",
            "-fno-common",
            "-fno-strict-aliasing",
            // The fixnum range macros compare int/long values against the
            // 61-bit fixnum bounds; on the LLP64 ABI those comparisons are
            // provably true and clang flags them.  They are intentional
            // (EMACS_INT is 64-bit long long on Windows) and harmless.
            "-Wno-tautological-constant-out-of-range-compare",
            "-Wno-initializer-overrides",
            "-Wno-pointer-sign",
            "-Wno-implicit-const-int-float-conversion",
            "-Demacs",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
            "-Isrc",
            "-Ilib",
            "-Ilib/w32",
            "-Int/inc",
        };
        // The MSVC CRT turns a huge number of perfectly-fine POSIX/ANSI names
        // (open/fdopen/strcpy/getenv/...) into hard deprecation ERRORS.  Emacs
        // deliberately uses the POSIX names (the vendored build.zig ports keep
        // them), so suppress those CRT warnings for the MSVC ABI exactly as
        // upstream's MSVC build does (_CRT_SECURE_NO_WARNINGS /
        // _CRT_NONSTDC_NO_WARNINGS).  Zero effect on the MinGW ABI.
        const base_flags: []const []const u8 = if (target.result.abi == .msvc)
            &(base_flags_core_w32 ++ [_][]const u8{
                "-D_CRT_SECURE_NO_WARNINGS",
                "-D_CRT_NONSTDC_NO_WARNINGS",
                // MSVC promotes the Windows SDK's __declspec(deprecated)
                // (e.g. GetVersion/GetVersionExA) to hard errors; the w32
                // code legitimately uses them for OS detection.  Suppress
                // deprecation warnings for the MSVC ABI, like the macOS
                // branch already does (-Wno-deprecated-declarations), plus
                // the w32 bit-field pattern (bare `int : N` with constant
                // values that truncate) which clang-msvc flags.
                "-Wno-deprecated-declarations",
                "-Wno-bitfield-constant-conversion",
            })
        else
            &base_flags_core_w32;

        // src/timefns.c:monotonic_coarse_timespec is provided by the
        // emacs-time Zig package (Windows QueryPerformanceCounter backend,
        // no msvcrt) instead of C; the body is #ifndef'd out when
        // EMACS_USE_ZIG_MONOTONIC_COARSE is defined. See the Unix branch
        // above for the full rationale.
        // base_flags is a runtime slice (MSVC-ABI appends CRT-warning
        // defines), so append the per-file flag at runtime, not with `++`.
        const timefns_flags = blk: {
            const out = b.allocator.alloc([]const u8, base_flags.len + 1) catch @panic("OOM");
            @memcpy(out[0..base_flags.len], base_flags);
            out[base_flags.len] = "-DEMACS_USE_ZIG_MONOTONIC_COARSE";
            break :blk out;
        };

        for (base_sources) |src| {
            const flags: []const []const u8 =
                if (std.mem.eql(u8, src, "src/timefns.c")) timefns_flags else base_flags;
            // w32console.c provides the terminal-emulation layer itself:
            // the cm.c cursor-motion globals and the termcap.c sys_* IO
            // functions (upstream sets CM_OBJ= on MinGW and never builds
            // termcap.o there; see configure.ac / src/Makefile.in).
            if (std.mem.eql(u8, src, "src/cm.c") or
                std.mem.eql(u8, src, "src/termcap.c"))
                continue;
            exe.root_module.addCSourceFile(.{
                .file = b.path(src),
                .flags = flags,
            });
        }

        // Add Gnulib sources
        const libgnu_flags_core = [_][]const u8{
            "-std=gnu2x",
            "-fno-common",
            "-fno-strict-aliasing",
            "-Wno-tautological-constant-out-of-range-compare",
            "-Wno-initializer-overrides",
            "-Wno-pointer-sign",
            "-Wno-implicit-const-int-float-conversion",
            "-Demacs",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
            "-Isrc",
            "-Ilib",
            "-Ilib/w32",
            "-Int/inc",
        };
        // Same MSVC-ABI CRT/SDK-warning suppression as base_flags above.
        const libgnu_flags: []const []const u8 = if (target.result.abi == .msvc)
            &(libgnu_flags_core ++ [_][]const u8{
                "-D_CRT_SECURE_NO_WARNINGS",
                "-D_CRT_NONSTDC_NO_WARNINGS",
                "-Wno-deprecated-declarations",
                "-Wno-bitfield-constant-conversion",
            })
        else
            &libgnu_flags_core;

        for (libgnu_sources) |src| {
            // Modules omitted on Windows (nt/gnulib-cfg.mk): w32.c or the
            // Zig packages already provide these, and the gnulib versions
            // clash with nt/inc or duplicate symbols at link time.
            if (std.mem.eql(u8, src, "lib/fcntl.c") or
                std.mem.eql(u8, src, "lib/allocator.c") or
                std.mem.eql(u8, src, "lib/canonicalize-lgpl.c") or
                std.mem.eql(u8, src, "lib/copy-file-range.c") or
                std.mem.eql(u8, src, "lib/dirfd.c") or
                std.mem.eql(u8, src, "lib/free.c") or
                std.mem.eql(u8, src, "lib/issymlink.c") or
                std.mem.eql(u8, src, "lib/issymlinkat.c") or
                std.mem.eql(u8, src, "lib/malloc.c") or
                std.mem.eql(u8, src, "lib/realloc.c") or
                std.mem.eql(u8, src, "lib/fpending.c") or
                // strtol/strtoll/strtoimax/strnlen (lib/{strtol,strtoll,
                // strtoimax,strnlen}.c) are provided natively by libucrt.lib
                // on the MSVC ABI; the gnulib copies would duplicate those
                // UCRT symbols at link.  MinGW's msvcrt lacks strnlen (and
                // its strtol lives in the DLL, overridable), so keep them
                // for the GNU backend.
                (target.result.abi == .msvc and
                    (std.mem.eql(u8, src, "lib/strtol.c") or
                        std.mem.eql(u8, src, "lib/strtoll.c") or
                        std.mem.eql(u8, src, "lib/strtoimax.c") or
                        std.mem.eql(u8, src, "lib/strnlen.c"))))
                continue;
            exe.root_module.addCSourceFile(.{
                .file = b.path(src),
                .flags = libgnu_flags,
            });
        }

        // Windows-only shim implementations: execinfo (backtrace
        // stubs), stpcpy and __fpending that mingw lacks.
        for ([_][]const u8{
            "lib/w32/execinfo.c",
            "lib/w32/stpcpy.c",
            "lib/w32/fpending.c",
            "lib/w32/strsignal.c",
            "lib/w32/time_r.c",
        }) |w32src| {
            exe.root_module.addCSourceFile(.{
                .file = b.path(w32src),
                .flags = libgnu_flags,
            });
        }

        // Windows native modules.  The console build omits the GUI-only
        // modules (w32fns/w32term/...) and stubs the few GUI symbols they
        // would provide via w32-stubs.c; with -Dgui=true the REAL modules
        // are compiled instead (mirrors configure.ac's W32_OBJ list for
        // mingw: w32fns w32menu w32reg w32font w32term w32xfns w32select
        // w32uniscribe w32dwrite + w32 w32console w32heap w32inevt w32proc,
        // plus WINDOW_SYSTEM_OBJ = fontset fringe image) and the stubs are
        // dropped (they would duplicate the real symbols at link).
        // TREE_SITTER_STATIC: tree-sitter is linked statically (vendored
        // dep), so treesit.c must NOT take its WINDOWSNT LoadLibrary
        // path (no tree-sitter.dll to load).
        exe.root_module.addCMacro("TREE_SITTER_STATIC", "1");
        if (with_gui) {
            // The MSVC SDK's gdiplus.h is C++-only (mingw-w64's is C), so
            // src/w32image.c (the GDI+ native-image API, an optional
            // feature beyond the vendored png/jpeg/tiff decoders) cannot
            // compile there; link no-op syms/globals hooks instead.
            const msvc_abi = target.result.abi == .msvc;
            for ([_][]const u8{
                "src/w32.c",
                "src/w32console.c",
                "src/w32heap.c",
                "src/w32inevt.c",
                "src/w32proc.c",
                "src/w32reg.c",
                "src/w32dwrite.c",
                "src/w32fns.c",
                "src/w32menu.c",
                "src/w32font.c",
                "src/w32term.c",
                "src/w32xfns.c",
                "src/w32select.c",
                "src/w32uniscribe.c",
                // w32cygwinx.c: the X-focus shim emacs.c references under
                // `#if defined HAVE_NTGUI || defined CYGWIN`.
                "src/w32cygwinx.c",
                "src/fontset.c",
                "src/fringe.c",
                "src/dynlib.c",
                // mingw-generic helpers (getrandom/set_binary_mode/
                // close_stream) shared with the console build.
                "src/w32-compat.c",
                if (msvc_abi) "src/w32image-stubs.c" else "src/w32image.c",
            }) |w32src| {
                exe.root_module.addCSourceFile(.{
                    .file = b.path(w32src),
                    .flags = libgnu_flags,
                });
            }
            // image.c: the only consumer of the vendored image headers, so
            // its -I paths ride on the per-file flags (module-level
            // include paths would reorder clang's search order and break
            // gnulib resolution on MSVC -- see the image-libs block above).
            var image_c_flags: std.ArrayList([]const u8) = .empty;
            defer image_c_flags.deinit(b.allocator);
            image_c_flags.appendSlice(b.allocator, libgnu_flags) catch @panic("OOM");
            if (with_png) {
                const p = b.lazyDependency("png_src", .{}) orelse return;
                const ip = std.fmt.allocPrint(b.allocator, "-I{s}", .{p.path("").getPath(b)}) catch @panic("OOM");
                image_c_flags.append(b.allocator, ip) catch @panic("OOM");
                image_c_flags.append(b.allocator, "-Int/inc/png") catch @panic("OOM");
            }
            if (with_jpeg) {
                const j = b.lazyDependency("jpeg_src", .{}) orelse return;
                const ip = std.fmt.allocPrint(b.allocator, "-I{s}", .{j.path("").getPath(b)}) catch @panic("OOM");
                image_c_flags.append(b.allocator, ip) catch @panic("OOM");
            }
            if (with_tiff) {
                const t = b.lazyDependency("tiff_src", .{}) orelse return;
                const tp = std.fmt.allocPrint(b.allocator, "-I{s}", .{t.path("libtiff").getPath(b)}) catch @panic("OOM");
                image_c_flags.append(b.allocator, tp) catch @panic("OOM");
                image_c_flags.append(b.allocator, "-Int/inc/tiff") catch @panic("OOM");
            }
            if (with_gif) {
                const g = b.lazyDependency("gif_src", .{}) orelse return;
                const ip = std.fmt.allocPrint(b.allocator, "-I{s}", .{g.path("").getPath(b)}) catch @panic("OOM");
                image_c_flags.append(b.allocator, ip) catch @panic("OOM");
            }
            if (with_webp) {
                const w = b.lazyDependency("webp_src", .{}) orelse return;
                const ip = std.fmt.allocPrint(b.allocator, "-I{s}", .{w.path("").getPath(b)}) catch @panic("OOM");
                image_c_flags.append(b.allocator, ip) catch @panic("OOM");
                // webp headers live in src/: <webp/decode.h> etc.
                const ip2 = std.fmt.allocPrint(b.allocator, "-I{s}", .{w.path("src").getPath(b)}) catch @panic("OOM");
                image_c_flags.append(b.allocator, ip2) catch @panic("OOM");
            }
            if (with_xpm and !pgtk_target) {
                const x = b.lazyDependency("xpm_src", .{}) orelse return;
                // image.c defines FOR_MSW itself before #include
                // "X11/xpm.h" (and renames XImage/XColor/Display to
                // xpm_*), so only the include paths are needed here:
                // include/ for X11/xpm.h, src/ for simx.h (pulled by
                // xpm.h under FOR_MSW).  nt/inc/xpm carries a patched
                // simx.h whose FUNC macro always takes the ANSI branch
                // (the stock one keys off __STDC__, which is 0 in
                // clang's MSVC mode -> K&R zero-arg prototypes that
                // break the arity-checked calls); it must precede src/.
                const ip0 = "-Int/inc/xpm";
                image_c_flags.append(b.allocator, ip0) catch @panic("OOM");
                const ip = std.fmt.allocPrint(b.allocator, "-I{s}", .{x.path("include").getPath(b)}) catch @panic("OOM");
                image_c_flags.append(b.allocator, ip) catch @panic("OOM");
                const ip2 = std.fmt.allocPrint(b.allocator, "-I{s}", .{x.path("src").getPath(b)}) catch @panic("OOM");
                image_c_flags.append(b.allocator, ip2) catch @panic("OOM");
            }
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/image.c"),
                .flags = image_c_flags.items,
            });
            // The image libraries are STATICALLY linked (zig cc builds
            // from the zig-fetched sources), so image.c's WINDOWSNT
            // LoadLibrary gate (init_*_functions) must not run: a NULL
            // type init makes initialize_image_type accept immediately.
            if (with_png or with_jpeg or with_tiff or with_gif or with_webp or with_xpm)
                exe.root_module.addCMacro("EMACS_STATIC_IMAGE_LIBS", "1");
            // GUI system libraries (configure.ac W32_LIBS, mingw branch):
            // usp10 backs w32uniscribe's Script* calls; comdlg32/comctl32/
            // ole32/winspool back the common dialogs, tooltips and OLE
            // drag-drop in w32fns/w32menu/w32select.
            exe.root_module.linkSystemLibrary("usp10", .{});
            exe.root_module.linkSystemLibrary("comdlg32", .{});
            exe.root_module.linkSystemLibrary("comctl32", .{});
            exe.root_module.linkSystemLibrary("ole32", .{});
            exe.root_module.linkSystemLibrary("winspool", .{});
            // gdi32 backs every GetDC/CreateFont/... call in w32term/
            // w32fns/w32font; gdiplus backs w32image.c's GDI+ API set
            // (the fn_Gdip* function pointers resolve at load).
            exe.root_module.linkSystemLibrary("gdi32", .{});
            exe.root_module.linkSystemLibrary("gdiplus", .{});
        } else {
            for ([_][]const u8{
                "src/w32.c",
                "src/w32console.c",
                "src/w32heap.c",
                "src/w32inevt.c",
                "src/w32proc.c",
                "src/w32reg.c",
                "src/w32dwrite.c",
                "src/dynlib.c",
                "src/w32-stubs.c",
                "src/w32-compat.c",
            }) |w32src| {
                exe.root_module.addCSourceFile(.{
                    .file = b.path(w32src),
                    .flags = libgnu_flags,
                });
            }
        }

        // Phase-2.1 subsystem switches, Windows branch (mirrors the Unix
        // branch above): the native-comp Zig path compiles src/compz.c and
        // defines HAVE_NATIVE_COMP_ZIG so the zeln DEFUNs are registered.
        if (enable_native_comp_zig) {
            exe.root_module.addCMacro("HAVE_NATIVE_COMP_ZIG", "1");
            if (target.result.cpu.arch == .x86_64)
                exe.root_module.addCMacro("ZELN_JIT_ARCH_X86_64", "1");
            exe.root_module.addCSourceFile(.{
                .file = b.path("src/compz.c"),
                .flags = libgnu_flags,
            });
            // compz.c's comp_z_hash_source_file streams via md5_stream.
            exe.root_module.addCSourceFile(.{
                .file = b.path("lib/md5-stream.c"),
                .flags = libgnu_flags,
            });
        }
    }

    // Link system libraries (phase 2: based on src/Makefile)
    // libm: the POSIX math library.  The MSVC CRT provides the math
    // functions in the CRT itself (no separate libm), so skip it for the
    // MSVC ABI target.
    if (target.result.abi != .msvc)
        exe.root_module.linkSystemLibrary("m", .{});
    // gccjit native-comp (-Dnative-comp): libgccjit.so.  ldconfig resolves it
    // (verified present on the build host).  Gated to native_comp_target so
    // off-path / cross builds never look for it.
    if (native_comp_target) exe.root_module.linkSystemLibrary("gccjit", .{});

    // -------------------------------------------------------------------
    // Zig-managed third-party libraries.  Every vendored dependency is
    // cross-platform, so it is built from source into a static lib linked
    // on all targets (macOS, Linux, musl and Windows) and the matching
    // config.h feature flag is enabled everywhere (see config-overrides.zig);
    // only genuinely platform-specific libraries stay behind guards.

    // XML parsing: libxml2 built from source as a Zig-managed dependency
    // (build.zig.zon -> xml2_src URL dep), replacing the system-installed
    // library. The two configure-generated headers (the public
    // include/libxml/xmlversion.h and the private config.h) are produced
    // from the vendored templates by zig's addConfigHeader (autoconf
    // @VAR@ / #undef styles); optional features Emacs never calls (HTTP,
    // catalog, C14N, debug, ICU, iconv, zlib/lzma compression) are
    // compiled out. On Windows the pthread/unistd/dlfcn/mmap features are
    // dropped so libxml2 takes its win32 code paths.
    if (with_xml2) {
        const xml2_src = b.dependency("xml2_src", .{});
        const xml2_win = target.result.os.tag == .windows;
        const xml2_cfg = b.addConfigHeader(.{
            .style = .{ .autoconf_at = xml2_src.path("include/libxml/xmlversion.h.in") },
            .include_path = "libxml/xmlversion.h",
        }, .{
            .VERSION = "2.15.3",
            .LIBXML_VERSION_NUMBER = "21503",
            .LIBXML_VERSION_EXTRA = "",
            .MODULE_EXTENSION = ".so",
            .WITH_THREADS = 1,
            // Windows keeps per-thread allocation on: with C11 TLS (USE_TLS)
            // and per-thread allocation off, globals.c's DllMain cleanup
            // references the undeclared `globalkey' (upstream 2.15.x quirk).
            .WITH_THREAD_ALLOC = if (xml2_win) @as(i32, 1) else @as(i32, 0),
            .WITH_OUTPUT = 1,
            .WITH_PUSH = 1,
            .WITH_READER = 1,
            .WITH_PATTERN = 1,
            .WITH_WRITER = 1,
            .WITH_SAX1 = 1,
            .WITH_HTTP = 0,
            .WITH_VALID = 1,
            .WITH_HTML = 1,
            .WITH_C14N = 0,
            .WITH_CATALOG = 0,
            .WITH_XPATH = 1,
            .WITH_XPTR = 1,
            .WITH_XINCLUDE = 1,
            .WITH_ICONV = 0,
            .WITH_ICU = 0,
            .WITH_ISO8859X = 1,
            .WITH_DEBUG = 0,
            .WITH_REGEXPS = 1,
            .WITH_RELAXNG = 1,
            .WITH_SCHEMAS = 1,
            .WITH_SCHEMATRON = 1,
            .WITH_MODULES = 0,
            .WITH_ZLIB = 0,
        });
        const xml2_config_cfg = b.addConfigHeader(.{
            .style = .{ .autoconf_undef = xml2_src.path("config.h.in") },
            .include_path = "config.h",
        }, .{
            // getentropy is a glibc/POSIX-2024 API; musl and Windows fall back
            // to the time-based seed in dict.c's xmlInitRandom.
            .HAVE_DECL_GETENTROPY = if (xml2_win or is_musl) null else @as(?i32, 1),
            .HAVE_DECL_GLOB = null,
            .HAVE_DECL_MMAP = if (xml2_win) null else @as(?i32, 1),
            .HAVE_DLFCN_H = if (xml2_win) null else @as(?i32, 1),
            .HAVE_DLOPEN = null,
            .HAVE_FUNC_ATTRIBUTE_DESTRUCTOR = 1,
            .HAVE_INTTYPES_H = 1,
            .HAVE_LIBHISTORY = null,
            .HAVE_LIBREADLINE = null,
            .HAVE_PTHREAD_H = if (xml2_win) null else @as(?i32, 1),
            .HAVE_SHLLOAD = null,
            .HAVE_STDINT_H = 1,
            .HAVE_STDIO_H = 1,
            .HAVE_STDLIB_H = 1,
            .HAVE_STRINGS_H = 1,
            .HAVE_STRING_H = 1,
            .HAVE_SYS_STAT_H = 1,
            .HAVE_SYS_TYPES_H = 1,
            .HAVE_UNISTD_H = if (xml2_win) null else @as(?i32, 1),
            .HAVE_ZLIB_H = null,
            .LT_OBJDIR = "",
            .PACKAGE = "libxml2",
            .PACKAGE_BUGREPORT = "",
            .PACKAGE_NAME = "libxml2",
            .PACKAGE_STRING = "libxml2 2.15.3",
            .PACKAGE_TARNAME = "libxml2",
            .PACKAGE_URL = "",
            .PACKAGE_VERSION = "2.15.3",
            .STDC_HEADERS = 1,
            .VERSION = "2.15.3",
            .XML_SYSCONFDIR = "/etc",
            .XML_THREAD_LOCAL = ._Thread_local,
        });
        const xml2_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        xml2_mod.addConfigHeader(xml2_cfg);
        xml2_mod.addConfigHeader(xml2_config_cfg);
        xml2_mod.addIncludePath(xml2_src.path(""));
        xml2_mod.addIncludePath(xml2_src.path("include"));
        const xml2_files = [_][]const u8{
            "HTMLparser.c", "HTMLtree.c",   "SAX2.c",     "buf.c",             "chvalid.c",
            "dict.c",       "encoding.c",   "entities.c", "error.c",           "globals.c",
            "hash.c",       "list.c",       "parser.c",   "parserInternals.c", "pattern.c",
            "relaxng.c",    "schematron.c", "threads.c",  "tree.c",            "uri.c",
            "valid.c",      "xinclude.c",   "xlink.c",    "xmlIO.c",           "xmlmemory.c",
            "xmlreader.c",  "xmlregexp.c",  "xmlsave.c",  "xmlschemas.c",      "xmlschemastypes.c",
            "xmlstring.c",  "xmlwriter.c",  "xpath.c",    "xpointer.c",
        };
        xml2_mod.addCSourceFiles(.{
            .root = xml2_src.path("."),
            .files = &xml2_files,
            .flags = &.{ "-std=c11", "-D_FILE_OFFSET_BITS=64", "-D_LARGEFILE_SOURCE" },
        });
        const xml2_lib = b.addLibrary(.{ .name = "xml2", .root_module = xml2_mod });
        exe.root_module.linkLibrary(xml2_lib);
        exe.root_module.addConfigHeader(xml2_cfg);
        exe.root_module.addIncludePath(xml2_src.path("include"));
    }

    // Compression: zlib built from source as a Zig-managed dependency
    // (build.zig.zon -> zlib_src URL dep), replacing the system libz.
    // Compiled in its own module so the Emacs config.h flags never
    // leak into zlib, and exported as a static libz for the exe.
    if (with_zlib) {
        const zlib_src = b.dependency("zlib_src", .{});
        const zlib_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        zlib_mod.addIncludePath(zlib_src.path(""));
        const zlib_sources = [_][]const u8{
            "adler32.c", "compress.c", "crc32.c",   "deflate.c", "gzclose.c",
            "gzlib.c",   "gzread.c",   "gzwrite.c", "infback.c", "inffast.c",
            "inflate.c", "inftrees.c", "trees.c",   "uncompr.c", "zutil.c",
        };
        // zlib compiles standalone.  -DHAVE_UNISTD_H is correct where unistd.h
        // exists (MinGW/glibc); the MSVC CRT has no unistd.h, and giving zlib
        // that define makes zconf.h include it and fail.  For the MSVC ABI,
        // build zlib without it (zconf.h degrades to its own off_t handling).
        const zlib_flags: []const []const u8 = if (target.result.abi == .msvc)
            &[_][]const u8{"-O2"}
        else
            &[_][]const u8{ "-O2", "-DHAVE_UNISTD_H" };
        for (zlib_sources) |zsrc| {
            zlib_mod.addCSourceFile(.{ .file = zlib_src.path(zsrc), .flags = zlib_flags });
        }
        const zlib_lib = b.addLibrary(.{ .name = "z", .root_module = zlib_mod });
        exe.root_module.linkLibrary(zlib_lib);
        exe.root_module.addIncludePath(zlib_src.path(""));
    }

    // ------------------------------------------------------------------
    // Image libraries (objective 3.5): libpng / libjpeg / libtiff built
    // from the zig-fetched source deps as static libs and linked into
    // temacs, plus src/image.c compiled so the whole chain (fetch ->
    // zig cc -> static lib -> link -> image.c) is real.  Opt-in via
    // -Dwith-png/jpeg/tiff: the console/TTY build has HAVE_WINDOW_SYSTEM
    // undef'd, so image.c's Lisp surface is dormant; the wiring is proven
    // and inherited as-is by the future GUI build.
    // ------------------------------------------------------------------
    if (with_png) {
        const png_src = b.lazyDependency("png_src", .{}) orelse return;
        const png_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        // libpng needs pnglibconf.h; the tarball ships it only as
        // scripts/pnglibconf.h.prebuilt, so a committed copy (renamed) lives
        // at nt/inc/png/pnglibconf.h.  png.h includes zlib.h (PNG_USE_ZLIB
        // is on in the prebuilt conf), so the vendored zlib source root is
        // on the path and libpng links the same static zlib.
        png_mod.addIncludePath(b.path("nt/inc/png"));
        png_mod.addIncludePath(png_src.path(""));
        if (with_zlib) {
            const z = b.lazyDependency("zlib_src", .{}) orelse return;
            png_mod.addIncludePath(z.path(""));
            const png_link_zlib = b.addLibrary(.{ .name = "z_for_png", .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }) });
            png_link_zlib.root_module.addIncludePath(z.path(""));
            const zsrcs = [_][]const u8{
                "adler32.c", "compress.c", "crc32.c",   "deflate.c",
                "infback.c", "inffast.c",  "inflate.c", "inftrees.c",
                "trees.c",   "uncompr.c",  "zutil.c",
            };
            const zflags: []const []const u8 = if (target.result.abi == .msvc)
                &[_][]const u8{"-O2"}
            else
                &[_][]const u8{ "-O2", "-DHAVE_UNISTD_H" };
            for (zsrcs) |zs| {
                png_link_zlib.root_module.addCSourceFile(.{ .file = z.path(zs), .flags = zflags });
            }
            png_mod.linkLibrary(png_link_zlib);
        }
        const png_sources = [_][]const u8{
            "png.c",      "pngerror.c", "pngget.c",   "pngmem.c",
            "pngpread.c", "pngread.c",  "pngrio.c",   "pngrtran.c",
            "pngrutil.c", "pngset.c",   "pngtrans.c", "pngwio.c",
            "pngwrite.c", "pngwtran.c", "pngwutil.c",
        };
        // MinGW supplies unistd.h; the MSVC CRT does not, and defining
        // PNG_NO_STDIO off-config breaks.  Keep both ABIs on plain -O2 and
        // let pnglibconf.h.prebuilt carry the platform choices.
        const png_flags: []const []const u8 = &[_][]const u8{"-O2"};
        for (png_sources) |src| {
            png_mod.addCSourceFile(.{ .file = png_src.path(src), .flags = png_flags });
        }
        const png_lib = b.addLibrary(.{ .name = "png16", .root_module = png_mod });
        exe.root_module.linkLibrary(png_lib);
        // NOTE: no exe-level png include path (same rationale as jpeg
        // above); the GUI build adds it per-file when compiling image.c.
    }
    if (with_jpeg) {
        const jpeg_src = b.lazyDependency("jpeg_src", .{}) orelse return;
        const jpeg_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        jpeg_mod.addIncludePath(jpeg_src.path(""));
        // jpeg-9f source set (the progressive-Huffman phuff files were
        // merged away in jpeg-9; verify against the tarball listing).
        const jpeg_sources = [_][]const u8{
            "jaricom.c",  "jcapimin.c", "jcapistd.c", "jcarith.c",
            "jccoefct.c", "jccolor.c",  "jcdctmgr.c", "jchuff.c",
            "jcinit.c",   "jcmainct.c", "jcmarker.c", "jcmaster.c",
            "jcomapi.c",  "jcparam.c",  "jcprepct.c", "jcsample.c",
            "jctrans.c",  "jdapimin.c", "jdapistd.c", "jdarith.c",
            "jdatadst.c", "jdatasrc.c", "jdcoefct.c", "jdcolor.c",
            "jddctmgr.c", "jdhuff.c",   "jdinput.c",  "jdmainct.c",
            "jdmarker.c", "jdmaster.c", "jdmerge.c",  "jdpostct.c",
            "jdsample.c", "jdtrans.c",  "jerror.c",   "jfdctflt.c",
            "jfdctfst.c", "jfdctint.c", "jidctflt.c", "jidctfst.c",
            "jidctint.c", "jquant1.c",  "jquant2.c",  "jutils.c",
            "jmemmgr.c",  "jmemnobs.c",
        };
        // The IJG tarball has no jconfig.h (configure generates it); a
        // committed minimal Windows/LLVM-safe one lives in nt/inc so both
        // ABIs build identically.
        jpeg_mod.addIncludePath(b.path("nt/inc"));
        const jpeg_flags: []const []const u8 = &[_][]const u8{"-O2"};
        for (jpeg_sources) |src| {
            jpeg_mod.addCSourceFile(.{ .file = jpeg_src.path(src), .flags = jpeg_flags });
        }
        const jpeg_lib = b.addLibrary(.{ .name = "jpeg", .root_module = jpeg_mod });
        exe.root_module.linkLibrary(jpeg_lib);
        // NOTE: no exe-level include path for jpeg: src/image.c (the only
        // consumer of jpeglib.h) is not part of the console build, and
        // putting the tarball root on the exe module's include path changes
        // clang's -I precedence (module paths precede per-file -I) in ways
        // that broke gnulib header resolution on the MSVC ABI. The GUI
        // build that compiles image.c should add it per-file instead.
    }
    if (with_tiff) {
        const tiff_src = b.lazyDependency("tiff_src", .{}) orelse return;
        const tiff_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        // libtiff needs tif_config.h + tiffconf.h (autotools outputs); a
        // committed minimal pair for a static LLVM build lives under
        // nt/inc/tiff/.
        tiff_mod.addIncludePath(b.path("nt/inc/tiff"));
        tiff_mod.addIncludePath(tiff_src.path("libtiff"));
        const tiff_sources = [_][]const u8{
            "tif_aux.c",      "tif_close.c",    "tif_codec.c",   "tif_color.c",
            "tif_compress.c", "tif_dir.c",      "tif_dirinfo.c", "tif_dirread.c",
            "tif_dirwrite.c", "tif_dumpmode.c", "tif_error.c",   "tif_extension.c",
            "tif_fax3.c",     "tif_fax3sm.c",   "tif_flush.c",   "tif_getimage.c",
            "tif_hash_set.c", "tif_luv.c",      "tif_lzw.c",     "tif_next.c",
            "tif_open.c",     "tif_packbits.c", "tif_predict.c", "tif_print.c",
            "tif_read.c",     "tif_strip.c",    "tif_swab.c",    "tif_thunder.c",
            "tif_tile.c",     "tif_unix.c",     "tif_version.c", "tif_warning.c",
            "tif_write.c",
            // tif_hash_set.c: the custom hash-set (TIFFHashSet*).
            // tif_unix.c: the POSIX fd-based platform IO layer --
            // TIFFOpen/_TIFFmalloc/_TIFFcalloc & friends (image.c calls
            // them directly under EMACS_STATIC_IMAGE_LIBS).
        };
        // On the MSVC ABI tif_unix.c's POSIX read/write calls must map to
        // the CRT's _read/_write (mingw's unistd.h does this itself).
        const tiff_flags: []const []const u8 = if (target.result.abi == .msvc)
            &[_][]const u8{ "-O2", "-Dread=_read", "-Dwrite=_write", "-Dclose=_close" }
        else
            &[_][]const u8{"-O2"};
        for (tiff_sources) |src| {
            const joined = std.fmt.allocPrint(b.allocator, "libtiff/{s}", .{src}) catch @panic("OOM");
            tiff_mod.addCSourceFile(.{ .file = tiff_src.path(joined), .flags = tiff_flags });
        }
        const tiff_lib = b.addLibrary(.{ .name = "tiff", .root_module = tiff_mod });
        exe.root_module.linkLibrary(tiff_lib);
        // NOTE: no exe-level tiff include path (same rationale as jpeg).
    }
    if (with_gif) {
        const gif_src = b.lazyDependency("gif_src", .{}) orelse return;
        const gif_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        gif_mod.addIncludePath(gif_src.path(""));
        // Library files only; the CLI tools (gif2rgb, gifbuild, ...) are
        // excluded -- they have their own mains.  gif_font.c (GifDrawText
        // & friends) is a utility-layer file that uses strtok_r (absent
        // from the MSVC CRT) and that no Emacs code references; excluded
        // so both ABIs build identically.
        const gif_sources = [_][]const u8{
            "dgif_lib.c", "egif_lib.c", "gif_err.c",
            "gif_hash.c", "gifalloc.c", "openbsd-reallocarray.c",
        };
        const gif_flags: []const []const u8 = if (target.result.abi == .msvc)
            &[_][]const u8{ "-O2", "-D_CRT_SECURE_NO_WARNINGS", "-Dfdopen=_fdopen" }
        else
            &[_][]const u8{"-O2"};
        for (gif_sources) |src| {
            gif_mod.addCSourceFile(.{ .file = gif_src.path(src), .flags = gif_flags });
        }
        const gif_lib = b.addLibrary(.{ .name = "gif", .root_module = gif_mod });
        exe.root_module.linkLibrary(gif_lib);
        // NOTE: no exe-level include path (same rationale as the others).
    }
    if (with_webp) {
        const webp_src = b.lazyDependency("webp_src", .{}) orelse return;
        const webp_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        // libwebp built WITH a minimal committed config.h (nt/inc/webp):
        // HAVE_CONFIG_H makes cpu.h's WEBP_USE_* gating depend on the
        // explicit WEBP_HAVE_* macros (absent -> all off).  That keeps
        // every source file compiling (the *_sse*.c bodies are #if'd
        // out) while cpu.h auto-defines no HAVE_* on its own -- on an
        // MSVC-ABI target the stock cpu.h DEFINES WEBP_USE_SSE41 via
        // WEBP_MSC_SSE41, which then makes dsp.c reference
        // VP8LDspInitSSE41 etc. with no definition available.
        webp_mod.addIncludePath(b.path("nt/inc/webp"));
        webp_mod.addCMacro("HAVE_CONFIG_H", "1");
        webp_mod.addIncludePath(webp_src.path(""));
        // libwebp without -DHAVE_CONFIG_H takes its defaults (plain-C dsp
        // fallback; no threading).  Everything under src/{dec,demux,dsp,
        // enc,mux,utils} is compiled -- emacs uses the anim decoder
        // (demux+mux) as well as plain decode/encode.  Walked with a
        // build-time glob (the same pattern as parseLibgnuSources) because
        // the dsp directory alone carries ~80 per-arch files.
        {
            const src_dir = webp_src.path("src").getPath(b);
            var dir = std.Io.Dir.cwd().openDir(io, src_dir, .{ .iterate = true }) catch @panic("build.zig: cannot open webp src");
            defer dir.close(io);
            var walker = dir.walk(b.allocator) catch @panic("OOM");
            defer walker.deinit();
            const webp_flags: []const []const u8 = &[_][]const u8{"-O2"};
            while (walker.next(io) catch null) |entry| {
                if (entry.kind != .file) continue;
                if (!std.mem.endsWith(u8, entry.basename, ".c")) continue;
                // only the library subdirs (dec/demux/dsp/enc/mux/utils),
                // not examples/: match "<dir><sep>..." at path start.  The
                // walker emits OS-native separators on Windows.
                const dirs = [_][]const u8{ "dec", "demux", "dsp", "enc", "mux", "utils" };
                var in_lib_dir = false;
                for (dirs) |d| {
                    if (entry.path.len > d.len + 1 and
                        std.mem.eql(u8, entry.path[0..d.len], d) and
                        (entry.path[d.len] == '/' or entry.path[d.len] == '\\'))
                    {
                        in_lib_dir = true;
                        break;
                    }
                }
                if (!in_lib_dir) continue;
                // The walker's path is relative to the src dir; LazyPath
                // joins use forward slashes.
                const joined = std.fmt.allocPrint(b.allocator, "src/{s}", .{entry.path}) catch @panic("OOM");
                for (joined) |*ch| {
                    if (ch.* == '\\') ch.* = '/';
                }
                webp_mod.addCSourceFile(.{
                    .file = webp_src.path(joined),
                    .flags = webp_flags,
                });
            }
        }
        const webp_lib = b.addLibrary(.{ .name = "webp", .root_module = webp_mod });
        exe.root_module.linkLibrary(webp_lib);
        // NOTE: no exe-level include path (same rationale as the others).
    }
    // The vendored libXpm uses its Windows FOR_MSW simulation layer.  PGTK
    // instead enables image.c's built-in XPM3 parser, which avoids mixing
    // Xlib typedefs with GDK typedefs.
    const vendored_xpm = with_xpm and !pgtk_target;
    if (vendored_xpm) {
        const xpm_src = b.lazyDependency("xpm_src", .{}) orelse return;
        const xpm_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        // The upstream FOR_MSW simulation layer: simx.h/simx.c define the
        // X11 surface over plain C + MSW types, so no X11 headers/libs are
        // needed.  Under FOR_MSW the whole Pixmap-based API is excluded
        // ("FOR_MSW, all ..Pixmap.. are excluded, only the ..XImage.. are
        // used" -- xpm.h), so the *FrP.c/*ToP.c files (Pixmap-input/output
        // entry points) are not compiled; image.c on WINDOWSNT uses the
        // XImage variants exclusively.
        xpm_mod.addCMacro("FOR_MSW", "1");
        xpm_mod.addIncludePath(b.path("nt/inc/xpm"));
        xpm_mod.addIncludePath(xpm_src.path("src"));
        // XpmI.h does #include "xpm.h" (quoted, FOR_MSW style), which
        // lives at include/X11/xpm.h.
        xpm_mod.addIncludePath(xpm_src.path("include/X11"));
        const xpm_sources = [_][]const u8{
            "Attrib.c",   "CrBufFrI.c", "CrDatFrI.c",
            "create.c",   "CrIFrBuf.c", "CrIFrDat.c",
            "data.c",     "hashtab.c",  "Image.c",
            "Info.c",     "misc.c",     "parse.c",
            "RdFToBuf.c", "RdFToDat.c", "RdFToI.c",
            "rgb.c",      "scan.c",     "simx.c",
            "WrFFrBuf.c", "WrFFrDat.c", "WrFFrI.c",
        };
        // K&R-era old-style function definitions (simx.c hexCharToInt)
        // need gnu89; the rest of the lib is plain C89-compatible.
        const xpm_flags: []const []const u8 = &[_][]const u8{ "-O2", "-std=gnu89" };
        for (xpm_sources) |src| {
            const joined = std.fmt.allocPrint(b.allocator, "src/{s}", .{src}) catch @panic("OOM");
            xpm_mod.addCSourceFile(.{ .file = xpm_src.path(joined), .flags = xpm_flags });
        }
        const xpm_lib = b.addLibrary(.{ .name = "Xpm", .root_module = xpm_mod });
        exe.root_module.linkLibrary(xpm_lib);
        // NOTE: no exe-level include path (same rationale as the others).
    }
    // src/image.c itself is NOT compiled on this console/TTY build: it is a
    // window-system module (struct image lives in struct frame; the lookup
    // cache walks Display_Info via FRAME_DISPLAY_INFO), so it needs the
    // GUI display backend (HAVE_NTGUI + w32term.h on Windows) to compile.
    // The libraries above are still BUILT and LINKED here, so the
    // fetch->zig cc->static lib->link chain is proven end-to-end and the
    // future GUI build inherits ready wiring + the HAVE_PNG/JPEG/TIFF
    // config knobs this switch enables.

    // Color management: Little CMS built from source as a Zig-managed
    // dependency (build.zig.zon -> lcms2_src), replacing the system
    // liblcms2.  Own module so Emacs config flags do not leak in.
    if (with_lcms2) {
        const lcms2_src = b.dependency("lcms2_src", .{});
        const lcms2_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        lcms2_mod.addIncludePath(lcms2_src.path("src"));
        lcms2_mod.addIncludePath(lcms2_src.path("include"));
        const lcms2_sources = [_][]const u8{
            "src/cmsalpha.c", "src/cmscam02.c", "src/cmscgats.c",  "src/cmscnvrt.c",
            "src/cmserr.c",   "src/cmsgamma.c", "src/cmsgmt.c",    "src/cmshalf.c",
            "src/cmsintrp.c", "src/cmsio0.c",   "src/cmsio1.c",    "src/cmslut.c",
            "src/cmsmd5.c",   "src/cmsmtrx.c",  "src/cmsnamed.c",  "src/cmsopt.c",
            "src/cmspack.c",  "src/cmspcs.c",   "src/cmsplugin.c", "src/cmsps2.c",
            "src/cmssamp.c",  "src/cmssm.c",    "src/cmstypes.c",  "src/cmsvirt.c",
            "src/cmswtpnt.c", "src/cmsxform.c",
        };
        const lcms2_flags = [_][]const u8{"-O2"};
        for (lcms2_sources) |lcsrc| {
            lcms2_mod.addCSourceFile(.{
                .file = lcms2_src.path(lcsrc),
                .flags = &lcms2_flags,
            });
        }
        const lcms2_lib = b.addLibrary(.{ .name = "lcms2", .root_module = lcms2_mod });
        exe.root_module.linkLibrary(lcms2_lib);
        exe.root_module.addIncludePath(lcms2_src.path("src"));
        exe.root_module.addIncludePath(lcms2_src.path("include"));
    }

    // SQLite database: the amalgamation built from source as a
    // Zig-managed dependency (build.zig.zon -> sqlite_src), replacing
    // the system libsqlite3.  Own module so Emacs config flags do not
    // leak in; exported as a static libsqlite3 for the exe.  Loadable
    // extensions are compiled in so `sqlite-load-extension' works on
    // every target (the vendored build, unlike the platform sqlite3).
    if (with_sqlite3) {
        const sqlite_src = b.dependency("sqlite_src", .{});
        const sqlite_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        sqlite_mod.addIncludePath(sqlite_src.path(""));
        sqlite_mod.addCSourceFile(.{
            .file = sqlite_src.path("sqlite3.c"),
            .flags = &.{ "-O2", "-DHAVE_USLEEP", "-DSQLITE_ENABLE_LOAD_EXTENSION" },
        });
        const sqlite_lib = b.addLibrary(.{ .name = "sqlite3", .root_module = sqlite_mod });
        exe.root_module.linkLibrary(sqlite_lib);
        exe.root_module.addIncludePath(sqlite_src.path(""));
    }

    // Tree-sitter (HAVE_TREE_SITTER): ts_* symbols from src/treesit.c.
    // Built from source as a Zig-managed dependency (build.zig.zon ->
    // tree_sitter URL dep, pinned to tag v0.27.0) using tree-sitter's
    // own Zig 0.16 build.zig, replacing the
    // system-installed library on every platform.  Gated on -Dwith-tree-sitter
    // (default on) so `zig build -Dwith-tree-sitter=false` mirrors upstream
    // --without-tree-sitter: the vendored lib is not linked and HAVE_TREE_SITTER
    // is undef'd, while src/treesit.c still compiles (its ts_* bodies are
    // #if HAVE_TREE_SITTER-gated out) to keep treesit-available-p present.
    if (with_tree_sitter) {
        const tree_sitter = b.dependency("tree_sitter", .{
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.linkLibrary(tree_sitter.artifact("tree-sitter"));
        exe.root_module.addIncludePath(tree_sitter.path("lib/include"));
    }

    // GnuTLS (HAVE_GNUTLS): gnutls_* symbols from src/gnutls.c.  Built
    // from source as a Zig-managed dependency (build.zig.zon -> gnutls_src
    // + nettle_src URL deps), replacing the Homebrew/system-installed
    // library.  The configure-generated headers (config.h, gnutls.h, the
    // gnulib + unistring replacements) and the exact source lists are
    // committed in tools/gnutls-config (macOS aarch64 reference build; see
    // tools/gnutls-config/README.md).  macOS only for now - the other
    // targets keep the system library until their configs are vendored.
    // The vendored GnuTLS/nettle build needs the macOS SDK (Security/
    // CoreFoundation frameworks, sys/ttydev.h, ...), so it is only
    // compiled when the host is macOS.  Cross-compiling the macOS target
    // from another host falls through to the system-library link below
    // (which fails at link time on a non-macOS host, as before the
    // vendoring).  Gated on -Dwith-gnutls so the switch actually skips
    // the whole vendored GnuTLS/nettle/unistring stack on macOS.
    if (target.result.os.tag == .macos and b.graph.host.result.os.tag == .macos and with_gnutls) vendored_gnutls: {
        const nettle_src = b.lazyDependency("nettle_src", .{}) orelse break :vendored_gnutls;
        const nettle_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        // Nettle builds with its own config.h (committed as
        // tools/gnutls-config/nettle/config.h) plus the bundled mini-gmp,
        // so no external GMP is needed; the whole nettle+hogweed+mini-gmp
        // source set lands in one static libnettle.
        nettle_mod.addIncludePath(nettle_src.path("."));
        nettle_mod.addIncludePath(b.path("tools/gnutls-config/nettle"));
        const nettle_flags = [_][]const u8{ "-O2", "-DHAVE_CONFIG_H" };
        // mini-gmp.o's mpz_* globals would collide with Emacs's own bignum
        // (src/bignum.c, GMP-compatible); compile it hidden so GnuTLS's
        // references bind to the local copy while Emacs's stay untouched.
        const nettle_hidden_flags = [_][]const u8{ "-O2", "-DHAVE_CONFIG_H", "-fvisibility=hidden" };
        for (vendorSourceList(b, "tools/gnutls-config/nettle-sources.txt")) |src| {
            const flags = if (std.mem.eql(u8, src, "mini-gmp.c")) &nettle_hidden_flags else &nettle_flags;
            nettle_mod.addCSourceFile(.{ .file = nettle_src.path(src), .flags = flags });
        }
        const nettle_lib = b.addLibrary(.{ .name = "nettle", .root_module = nettle_mod });

        const gnutls_src = b.lazyDependency("gnutls_src", .{}) orelse break :vendored_gnutls;
        // Vendored libunistring (NFC/NFKC normalization + Unicode category
        // tables used by str-unicode.c/str-iconv.c); a separate module
        // mirroring GnuTLS's own lib/unistring subbuild, whose sources must
        // not see the main library's gnulib include dirs.
        const gnutls_unistring_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        gnutls_unistring_mod.addIncludePath(b.path("tools/gnutls-config/unistring"));
        gnutls_unistring_mod.addIncludePath(gnutls_src.path("lib/unistring"));
        gnutls_unistring_mod.addIncludePath(b.path("tools/gnutls-config"));
        for (vendorSourceList(b, "tools/gnutls-config/gnutls-unistring-sources.txt")) |src| {
            gnutls_unistring_mod.addCSourceFile(.{ .file = gnutls_src.path(src), .flags = &nettle_flags });
        }
        const gnutls_unistring_lib = b.addLibrary(.{ .name = "unistring", .root_module = gnutls_unistring_mod });

        const gnutls_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        // Include order mirrors lib/Makefile.am (DEFAULT_INCLUDES first,
        // then AM_CPPFLAGS): lib, config.h dir, top, gnulib source +
        // generated, public headers, x509, unistring, minitasn1, nettle.
        gnutls_mod.addIncludePath(gnutls_src.path("lib"));
        gnutls_mod.addIncludePath(b.path("tools/gnutls-config"));
        gnutls_mod.addIncludePath(gnutls_src.path("."));
        gnutls_mod.addIncludePath(gnutls_src.path("gl"));
        gnutls_mod.addIncludePath(b.path("tools/gnutls-config/gl"));
        gnutls_mod.addIncludePath(gnutls_src.path("lib/includes"));
        gnutls_mod.addIncludePath(gnutls_src.path("lib/x509"));
        gnutls_mod.addIncludePath(b.path("tools/gnutls-config/unistring"));
        gnutls_mod.addIncludePath(gnutls_src.path("lib/unistring"));
        gnutls_mod.addIncludePath(gnutls_src.path("lib/minitasn1"));
        gnutls_mod.addIncludePath(gnutls_src.path("lib/nettle"));
        gnutls_mod.addIncludePath(gnutls_src.path("lib/nettle/int"));
        // <nettle/...> public headers (committed copies of the 47 headers
        // GnuTLS's compiled sources include, mirroring the install prefix
        // the reference build pointed NETTLE_CFLAGS at).
        gnutls_mod.addIncludePath(b.path("tools/gnutls-config/nettle"));
        const gnutls_flags = [_][]const u8{
            "-O2",
            "-DHAVE_CONFIG_H",
            "-DGNUTLS_BUILDING_LIB=1",
            "-DLOCALEDIR=\"\"",
            "-DSYSTEM_PRIORITY_FILE=\"\"",
        };
        const gnutls_hidden_flags = [_][]const u8{
            "-O2",
            "-DHAVE_CONFIG_H",
            "-DGNUTLS_BUILDING_LIB=1",
            "-fvisibility=hidden",
            "-DLOCALEDIR=\"\"",
            "-DSYSTEM_PRIORITY_FILE=\"\"",
        };
        for (vendorSourceList(b, "tools/gnutls-config/gnutls-sources.txt")) |src| {
            const flags = if (gnutlsGlCollision(src)) &gnutls_hidden_flags else &gnutls_flags;
            gnutls_mod.addCSourceFile(.{ .file = gnutls_src.path(src), .flags = flags });
        }
        gnutls_mod.linkLibrary(nettle_lib);
        gnutls_mod.linkLibrary(gnutls_unistring_lib);
        // GnuTLS's macOS system-certificate loading (system/certs.c) uses
        // Security + CoreFoundation; same frameworks as upstream's MACOSX
        // branch of lib/Makefile.am.
        gnutls_mod.linkFramework("Security", .{});
        gnutls_mod.linkFramework("CoreFoundation", .{});
        const gnutls_lib = b.addLibrary(.{ .name = "gnutls", .root_module = gnutls_mod });
        exe.root_module.linkLibrary(gnutls_lib);
        // src/gnutls.c includes <gnutls/gnutls.h> (generated, committed)
        // and <gnutls/x509.h> + <gnutls/crypto.h> (from the tarball).
        exe.root_module.addIncludePath(b.path("tools/gnutls-config"));
        exe.root_module.addIncludePath(gnutls_src.path("lib/includes"));
    }

    // ncurses (HAVE_NCURSES): terminfo/termcap backing terminal UI.
    // Built from source as a Zig-managed dependency (build.zig.zon ->
    // ncurses_src URL dep), replacing the system-installed library on
    // macOS.  The configure-generated headers (curses.h, term.h,
    // ncurses_cfg.h, ...) and the generated capability tables (codes.c,
    // comp_captab.c, names.c, lib_gen.c, ...) are committed in
    // tools/ncurses-config (macOS aarch64 reference build; see
    // tools/ncurses-config/README.md).  Terminfo dirs point at the
    // system /usr/share/terminfo, matching the reference configure.
    if (target.result.os.tag == .macos and b.graph.host.result.os.tag == .macos) vendored_ncurses: {
        const ncurses_src = b.lazyDependency("ncurses_src", .{}) orelse break :vendored_ncurses;
        const ncurses_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        // Include order mirrors the reference make (ncurses source dir,
        // generated include dir, source include dir).
        ncurses_mod.addIncludePath(ncurses_src.path("ncurses"));
        ncurses_mod.addIncludePath(b.path("tools/ncurses-config/include"));
        ncurses_mod.addIncludePath(b.path("tools/ncurses-config/ncurses"));
        ncurses_mod.addIncludePath(ncurses_src.path("include"));
        const ncurses_flags = [_][]const u8{
            "-O2",
            "-DHAVE_CONFIG_H",
            "-DBUILDING_NCURSES",
            "-DNCURSES_STATIC",
            "-D_DARWIN_C_SOURCE",
        };
        for (vendorSourceList(b, "tools/ncurses-config/ncurses-sources.txt")) |src| {
            ncurses_mod.addCSourceFile(.{ .file = ncurses_src.path(src), .flags = &ncurses_flags });
        }
        for (vendorSourceList(b, "tools/ncurses-config/ncurses-generated-sources.txt")) |src| {
            const gen_path = std.fmt.allocPrint(
                b.allocator,
                "tools/ncurses-config/ncurses/{s}",
                .{src},
            ) catch @panic("OOM");
            ncurses_mod.addCSourceFile(.{ .file = b.path(gen_path), .flags = &ncurses_flags });
        }
        const ncurses_lib = b.addLibrary(.{ .name = "ncurses", .root_module = ncurses_mod });
        exe.root_module.linkLibrary(ncurses_lib);
    }

    // System libraries that are not (yet) vendored, or are inherently
    // platform-specific.  ncurses and gnutls come from the vendored
    // dependencies above on macOS and from the system libraries on the
    // other Unix-likes until their configs are vendored (the w32 console
    // needs no terminfo).  ACL/ALSA/GPM/D-Bus back Linux-only subsystems
    // (POSIX ACLs, ALSA sound, console mouse, D-Bus).
    // All declared natively via linkSystemLibrary: zig's compiler driver
    // resolves system libraries itself (pkg-config → vcpkg → plain `-l`
    // search paths), so e.g. libgpm present without a .pc file still links.
    // macOS builds link the vendored gnutls/ncurses above when the host
    // is macOS; every other Unix-like (Linux, BSD, or a non-macOS host
    // cross-compiling the macOS target) keeps the system libraries until
    // their configs are vendored.
    if (target.result.os.tag == .macos and b.graph.host.result.os.tag == .macos) {
        // gnutls + ncurses are already linked from the vendored libs above.
    } else if (!is_windows and !is_musl) {
        // Core libraries
        if (with_gnutls) exe.root_module.linkSystemLibrary("gnutls", .{});

        // Terminal support
        exe.root_module.linkSystemLibrary("ncurses", .{});
    }

    // ACL/ALSA/GPM/D-Bus are glibc-target Linux subsystems; the musl
    // config undefs HAVE_ACL/HAVE_ALSA/HAVE_GPM/HAVE_DBUS, so musl links
    // only the vendored static libs above (no system libraries).
    if (target.result.abi != .musl and target.result.os.tag == .linux) {
        // ACL support (Linux only). Link libacl: config.h defines HAVE_ACL_*
        // and the library is installed. Do NOT link libselinux: config.h has
        // HAVE_LIBSELINUX undefined and the library is absent on the host, so
        // linking it only breaks the build.
        if (with_acl) exe.root_module.linkSystemLibrary("acl", .{});
        // ALSA audio (HAVE_ALSA): snd_* symbols from src/sound.c.
        if (with_alsa) exe.root_module.linkSystemLibrary("asound", .{});
        // Linux console mouse (HAVE_GPM): Gpm_*/gpm_* symbols from src/term.c.
        if (with_gpm) exe.root_module.linkSystemLibrary("gpm", .{});
        // D-Bus (HAVE_DBUS): dbus_* symbols from src/dbusbind.c.
        if (with_dbus) exe.root_module.linkSystemLibrary("dbus-1", .{});
        // PGTK GUI stack (-Dpgtk, configure.ac's GTK_LIBS + CAIRO_LIBS +
        // FREETYPE_LIBS + HARFBUZZ_LIBS): zig's linkSystemLibrary resolves
        // each through pkg-config, which also contributes the include
        // dirs the pgtk*/ftcrfont/hbfont TUs need (gtk-3.0, glib, pango,
        // cairo, harfbuzz, freetype2, fontconfig).
        if (pgtk_target) {
            exe.root_module.linkSystemLibrary("gtk+-3.0", .{});
            exe.root_module.linkSystemLibrary("glib-2.0", .{});
            exe.root_module.linkSystemLibrary("gobject-2.0", .{});
            exe.root_module.linkSystemLibrary("gio-2.0", .{});
            exe.root_module.linkSystemLibrary("pango", .{});
            exe.root_module.linkSystemLibrary("pangocairo", .{});
            exe.root_module.linkSystemLibrary("gdk_pixbuf-2.0", .{});
            exe.root_module.linkSystemLibrary("cairo", .{});
            exe.root_module.linkSystemLibrary("cairo-gobject", .{});
            exe.root_module.linkSystemLibrary("harfbuzz", .{});
            exe.root_module.linkSystemLibrary("freetype2", .{});
            exe.root_module.linkSystemLibrary("fontconfig", .{});
        }
    }

    if (is_musl) {
        // No system libraries: the remaining feature libs (gnutls, ALSA,
        // GPM, D-Bus) are undef'd in the musl config, and src/termcap.c
        // (compiled via TERMCAP_OBJ) supplies the terminal capabilities
        // itself, so the static binary links with only zig's bundled
        // musl + libm plus the vendored static libs above.
    } else if (is_windows) {
        // Windows: getrandom (lib/getrandom.c) uses BCryptGenRandom;
        // sockets and the console UI need ws2_32/kernel32/user32/gdi32;
        // winmm (sound.c mci/waveOut/PlaySound) and mpr (WNet* network
        // shares in w32.c) mirror upstream's W32_LIBS.
        exe.root_module.linkSystemLibrary("bcrypt", .{});
        exe.root_module.linkSystemLibrary("ws2_32", .{});
        exe.root_module.linkSystemLibrary("kernel32", .{});
        exe.root_module.linkSystemLibrary("user32", .{});
        exe.root_module.linkSystemLibrary("gdi32", .{});
        exe.root_module.linkSystemLibrary("winmm", .{});
        exe.root_module.linkSystemLibrary("mpr", .{});
        // shell32 is NOT explicit in upstream W32_LIBS but is pulled in
        // transitively there (comctl32/comdlg32/ole32 import it).  The
        // console-only build links none of those, so without an explicit
        // -lshell32 the DLL is absent from the import table and the w32
        // dynamic loads via GetModuleHandle("shell32.dll") fail: the
        // init_environment AppData HOME fallback (SHGetFolderPathA) is
        // skipped and ShellExecuteEx (browse-url) is unavailable.
        exe.root_module.linkSystemLibrary("shell32", .{});
        // advapi32: the Crypt* / Reg* / GetUserNameA / token-privilege calls
        // in src/w32.c+w32proc.c.  MinGW's emacsclient-like linker pulls
        // these in transitively; the MSVC lld link resolves each dllimport
        // explicitly and needs the .lib named, so state it for the MSVC ABI.
        if (target.result.abi == .msvc)
            exe.root_module.linkSystemLibrary("advapi32", .{});
    }

    // lib-src tools (emacsclient, etags) — the user-facing programs the
    // native build installs (zig-out/bin).  Mirror the make-docfile pattern:
    // each is a standalone executable compiled with the libgnu-style flags
    // plus exactly the gnulib provider sources it references (upstream
    // links them via ../lib/libgnu.a; the zig build compiles the handful
    // of providers directly).  These run on the TARGET (not the build
    // host), so they use the target config + target.
    {
        const libsrc_flags_core = [_][]const u8{
            "-std=gnu2x",
            "-fno-common",
            "-fno-strict-aliasing",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
            "-Isrc",
            "-Ilib",
            "-Ilib/malloc",
        };
        // macOS tool flags: like the core set but WITHOUT -Ilib (lib/ is
        // a module include path there, ordered after lib/macos-tool so
        // the getopt.h substitute wins -- see the flags comment below).
        const _macsrc_flags_core = [_][]const u8{
            "-std=gnu2x",
            "-fno-common",
            "-fno-strict-aliasing",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-I.",
            "-Isrc",
            "-Ilib/malloc",
        };
        const libsrc_flags: []const []const u8 = if (is_windows)
            &(libsrc_flags_core ++ [_][]const u8{ "-Int/inc", "-Ilib/w32" })
        else if (target.result.os.tag == .macos)
            // Darwin does not declare environ in <unistd.h>; force the
            // crt_externs accessor header before every tool source, and
            // rename the gnulib getopt surface out of the system's way
            // (__GETOPT_PREFIX=rpl_, the gnulib-standard mechanism) with
            // lib/getopt{,1}.c linked below.  -Ilib is deliberately
            // DROPPED here and supplied (after lib/macos-tool) as a
            // module include path in the tools loop, so #include
            // <getopt.h> resolves to lib/macos-tool/getopt.h -- the
            // full gnulib substitute, with no include_next graft onto
            // the SDK's <getopt.h> (the graft broke against Xcode 26.5's
            // annotated declarations and left getopt1.c parsing with
            // the renames undefined on CI's SDK).
            &(_macsrc_flags_core ++ [_][]const u8{ "-include", "lib/macos-environ.h", "-D__GETOPT_PREFIX=rpl_" })
        else
            &libsrc_flags_core;

        const Tool = struct {
            name: []const u8,
            src: []const u8,
            providers: []const []const u8,
        };
        // Provider sets are per-platform: the POSIX ACL stack is compiled
        // only where the target is the native glibc toolchain (macOS and
        // foreign cross targets use a stub; macOS's config would otherwise
        // pull <acl/libacl.h>), and the Windows tools need the mingw shims
        // (stpcpy, nl_langinfo) plus the Zig gnulib-tempname mkostemp.
        const tools_native_linux_glibc =
            target.result.cpu.arch == b.graph.host.result.cpu.arch and
            target.result.os.tag == b.graph.host.result.os.tag and
            target.result.abi == b.graph.host.result.abi and
            target.result.os.tag == .linux and !is_musl;
        const emacsclient_providers: []const []const u8 = if (is_windows)
            &.{
                "lib/c-ctype.c",    "lib/realloc.c",
                "lib/strnul.c",     "lib/memeq.c",
                "lib/getline.c",    "lib/getdelim.c",
                "lib/w32/stpcpy.c",
            }
        else if (target.result.os.tag == .macos)
            // macOS lacks SOCK_CLOEXEC, so emacsclient.c's cloexec_socket()
            // takes its fcntl(F_SETFD, FD_CLOEXEC) fallback; gnulib's
            // lib/fcntl.h renames fcntl -> rpl_fcntl, so lib/fcntl.c must be
            // linked (Linux/glibc has SOCK_CLOEXEC and never calls fcntl).
            // getopt{,1}.c supply the rpl_ getopt implementation the
            // -D__GETOPT_PREFIX rename above points the call sites at.
            &.{ "lib/c-ctype.c", "lib/realloc.c", "lib/macos-file-has-acl-stub.c", "lib/fcntl.c", "lib/strnul.c", "lib/memeq.c", "lib/getopt.c", "lib/getopt1.c" }
        else if (is_musl or !tools_native_linux_glibc)
            // Static musl has no libacl and USE_ACL is disabled.  Foreign
            // cross targets cannot assume a target libacl in the Zig sysroot.
            // Reuse the no-ACL stub: emacsclient only uses file_has_acl
            // defensively before connecting to a local socket, and returning
            // 0 matches an ACL-unavailable platform.
            &.{ "lib/c-ctype.c", "lib/realloc.c", "lib/macos-file-has-acl-stub.c", "lib/strnul.c", "lib/memeq.c" }
        else
            &.{ "lib/c-ctype.c", "lib/realloc.c", "lib/file-has-acl.c", "lib/strnul.c", "lib/acl-errno-valid.c", "lib/memeq.c" };
        const etags_providers: []const []const u8 = if (is_windows)
            &.{
                "lib/c-ctype.c", "lib/binary-io.c",
                "lib/streq.c",   "lib/realloc.c",
                "lib/regex.c", // includes regcomp/regexec/regex_internal
                "lib/c-strcasecmp.c",
                "lib/c-strncasecmp.c",
                "lib/memeq.c",
                "lib/malloc/dynarray_resize.c",
                "lib/w32/stpcpy.c",
                "lib/w32/nl_langinfo.c",
            }
        else if (target.result.os.tag == .macos)
            // The macOS flags rename the gnulib getopt surface to rpl_ (see
            // libsrc_flags above), so the implementation is linked in too.
            &.{
                "lib/c-ctype.c", "lib/binary-io.c",
                "lib/streq.c",   "lib/realloc.c",
                "lib/regex.c", // includes regcomp/regexec/regex_internal
                "lib/c-strcasecmp.c",
                "lib/c-strncasecmp.c",
                "lib/memeq.c",
                "lib/malloc/dynarray_resize.c",
                "lib/getopt.c",
                "lib/getopt1.c",
            }
        else
            &.{
                "lib/c-ctype.c", "lib/binary-io.c",
                "lib/streq.c",   "lib/realloc.c",
                "lib/regex.c", // includes regcomp/regexec/regex_internal
                "lib/c-strcasecmp.c",
                "lib/c-strncasecmp.c",
                "lib/memeq.c",
                "lib/malloc/dynarray_resize.c",
            };
        const tools = [_]Tool{
            .{
                .name = "emacsclient",
                .src = "lib-src/emacsclient.c",
                .providers = emacsclient_providers,
            },
            .{
                .name = "etags",
                .src = "lib-src/etags.c",
                .providers = etags_providers,
            },
        };

        for (tools) |t| {
            const tool_exe = b.addExecutable(.{
                .name = t.name,
                .root_module = b.createModule(.{
                    .target = target,
                    .optimize = optimize,
                    .link_libc = true,
                }),
            });
            if (target.result.abi == .msvc) applyMsvcCrtWarnings(tool_exe.root_module);
            tool_exe.root_module.addCSourceFile(.{
                .file = b.path(t.src),
                .flags = libsrc_flags,
            });
            for (t.providers) |p| {
                tool_exe.root_module.addCSourceFile(.{
                    .file = b.path(p),
                    .flags = libsrc_flags,
                });
            }
            // emacsclient's file_has_acl needs libacl only on the native
            // glibc-Linux toolchain; upstream links FILE_HAS_ACL_LIB there
            // too.  Gated on -Dwith-acl (the ACL providers are dropped on
            // !with_acl; keep in sync with emacsclient_providers above).
            if (tools_native_linux_glibc and with_acl)
                tool_exe.root_module.linkSystemLibrary("acl", .{});
            if (is_windows and std.mem.eql(u8, t.name, "emacsclient")) {
                // w32_window_app (emacsclient.c:412) calls InitCommonControls.
                tool_exe.root_module.linkSystemLibrary("comctl32", .{});
                tool_exe.root_module.linkSystemLibrary("ws2_32", .{});
                // The MSVC link (lld) resolves each DLL import explicitly:
                // emacsclient calls MessageBox (user32) and the Reg* API
                // (advapi32); MinGW's emacsclient links these transitively
                // via its libs, the MSVC ABI does not, so state them.
                if (target.result.abi == .msvc) {
                    tool_exe.root_module.linkSystemLibrary("user32", .{});
                    tool_exe.root_module.linkSystemLibrary("advapi32", .{});
                }
            }
            // etags's mkostemp on Windows comes from the Zig gnulib-tempname
            // package (same provider the temacs build links); the mingw CRT
            // has no mkostemp.
            if (is_windows and std.mem.eql(u8, t.name, "etags"))
                tool_exe.root_module.linkLibrary(gnulib_tempname_lib);
            // MSVC ABI: the UCRT does not export the POSIX file/dir names the
            // tools (and the gnulib-tempname package above) call; provide them
            // via the Zig msvc-posix package.  MinGW/msvcrt exports both
            // spellings, so this is MSVC-only.
            if (is_windows and target.result.abi == .msvc and
                (std.mem.eql(u8, t.name, "emacsclient") or std.mem.eql(u8, t.name, "etags")))
                tool_exe.root_module.linkLibrary(msvc_posix_lib);
            tool_exe.root_module.addIncludePath(target_config_h_file.file.dirname());
            tool_exe.step.dependOn(target_config_h_file.step);
            // macOS tools: resolve #include <getopt.h> against the
            // substitute in lib/macos-tool FIRST, then lib/ itself for
            // the rest of the gnulib headers (module include paths keep
            // their add order and follow the per-file -I flags).
            if (target.result.os.tag == .macos) {
                tool_exe.root_module.addIncludePath(b.path("lib/macos-tool"));
                tool_exe.root_module.addIncludePath(b.path("lib"));
            }
            // MSVC-ABI tools (emacsclient, etags): the MSVC CRT has no
            // <getopt.h>/getopt_long at all (MinGW's CRT does).  Provide the
            // same full gnulib getopt substitute the macOS tools use:
            // lib/macos-tool/getopt.h on the include path, and link the gnulib
            // getopt.c+getopt1.c implementation (verified to compile for the
            // MSVC ABI).  lib/getopt.h requires <config.h> first, which the
            // flags' -DHAVE_CONFIG_H + target-config include path satisfy.
            if (target.result.abi == .msvc and (std.mem.eql(u8, t.name, "emacsclient") or std.mem.eql(u8, t.name, "etags"))) {
                tool_exe.root_module.addIncludePath(b.path("lib/macos-tool"));
                tool_exe.root_module.addCSourceFile(.{
                    .file = b.path("lib/getopt.c"),
                    .flags = libsrc_flags,
                });
                tool_exe.root_module.addCSourceFile(.{
                    .file = b.path("lib/getopt1.c"),
                    .flags = libsrc_flags,
                });
            }
            const install_tool = b.addInstallArtifact(tool_exe, .{});
            b.getInstallStep().dependOn(&install_tool.step);
        }
    }

    // Install the executable.  The step is kept as an explicit handle so
    // the dump tool can depend on "temacs is in place" without pulling in
    // the whole install step (which would otherwise create an install ->
    // dump -> install dependency cycle once the default build produces the
    // dumped image below).
    const install_temacs = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_temacs.step);

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
    // The wrapper is a static script; the default `zig build` produces the
    // dumped image (bootstrap-emacs.pdmp) and the runtime loaddefs via the
    // dump-compiled chain wired into the install step below, so a plain
    // `zig build` leaves a fully usable editor.
    //
    // Exec-bit defense: 0.16.0's InstallFile step has no .mode option (it
    // delegates to Io.Dir.updateFile with default options, which copies the
    // source mode). The source file is committed +x, but to be robust against
    // filesystems/checkouts that drop the bit, run chmod +x after install so
    // acceptance `test -x zig-out/bin/emacs` holds unconditionally.
    // `emacs` launcher install: on Windows a native emacs.exe (there is no
    // #!/bin/sh, so a .sh wrapper is not a runnable exe -- the smoke step
    // died with InvalidExe); on Unix the emacs-launcher.sh, which also
    // disables ASLR via setarch for reliable pdumper relocation.
    // emacs_wrapper_step is whichever step produces the runnable `emacs`, so
    // the smoke step below can depend on it uniformly.
    const emacs_wrapper_step: *std.Build.Step = if (is_windows) blk: {
        const emacs_launcher = b.addExecutable(.{
            .name = "emacs",
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .optimize = .Debug,
                .root_source_file = b.path("build-aux/emacs-launcher.zig"),
            }),
        });
        // The launcher is the top-level process on a native Windows build,
        // so give it the same manifest as temacs (consistency + matches
        // upstream emacs.exe).  Only set it when the HOST is Windows: the
        // launcher is built for b.graph.host (so it can run during the
        // build), and Zig rejects win32_manifest unless the target object
        // format is COFF -- so cross-compiling from Linux (host=ELF) must
        // skip it.  temacs above uses the cross *target*, so it always gets
        // the manifest regardless of host.
        if (b.graph.host.result.os.tag == .windows) {
            emacs_launcher.win32_manifest = b.path(switch (b.graph.host.result.cpu.arch) {
                .x86 => "nt/emacs-x86.manifest",
                else => "nt/emacs-x64.manifest",
            });
        }
        const install_emacs_launcher = b.addInstallArtifact(emacs_launcher, .{});
        b.getInstallStep().dependOn(&install_emacs_launcher.step);
        break :blk &install_emacs_launcher.step;
    } else blk: {
        const install_emacs_wrapper = b.addInstallFileWithDir(
            b.path("build-aux/emacs-launcher.sh"),
            .bin,
            "emacs",
        );
        b.getInstallStep().dependOn(&install_emacs_wrapper.step);
        const chmod_tool = b.addExecutable(.{
            .name = "chmod-x",
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .optimize = .Debug,
                // Uses std.c.chmod (POSIX chmod from the host libc) so the
                // syscall is target-correct on Linux and macOS.
                .link_libc = true,
                .root_source_file = b.path("build-aux/chmod-x.zig"),
            }),
        });
        const chmod_emacs_wrapper = b.addRunArtifact(chmod_tool);
        chmod_emacs_wrapper.addArg(b.pathJoin(&.{ b.install_path, "bin", "emacs" }));
        chmod_emacs_wrapper.step.dependOn(&install_emacs_wrapper.step);
        b.getInstallStep().dependOn(&chmod_emacs_wrapper.step);
        break :blk &chmod_emacs_wrapper.step;
    };

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
    // ABI-suffix the dump stamp (first extra argv arg; see stampName in the
    // tool): gnu/msvc share .zig-cache, so an unsuffixed dump.stamp made the
    // second backend's dump skip and reuse the first backend's temacs+pdmp
    // (an msvc prefix then shipped gnu binaries).
    run_dump.addArg(@tagName(target.result.abi));
    // The dump tool and every downstream checker spawn
    // ./zig-out/bin/temacs, so the executable install must happen before
    // them.  (Only the named "dump" step carried this dependency before,
    // which worked locally where a stale temacs existed but failed on
    // a clean checkout with FileNotFound.)
    run_dump.step.dependOn(&install_temacs.step);
    // Track the temacs binary itself as a cache input: the dumped pdmp
    // embeds temacs's subrs, which change with the feature switches
    // (-Dnative-comp-zig/-Dmodules/...).  Without this, flipping a switch
    // between two `zig build` invocations that share a cache (e.g. the CI
    // test job running `zig build` then `-Dnative-comp-zig=true populate`)
    // reuses the stale dump -> the populate's emacs lacks comp-z-write-
    // file-zunit ("not bound").  getEmittedBin's content differs per flag,
    // so the dump correctly reruns when temacs changes.
    run_dump.addFileArg(exe.getEmittedBin());
    // The dumped image loads the charset maps and the unicode script
    // tables from the source tree; both are gitignored generated data,
    // so a clean checkout must generate them before the dump runs.
    // (Only the named "dump" step carried these dependencies before,
    // which worked locally where stale outputs existed but failed on a
    // clean checkout with "Loading charset map".)
    run_dump.step.dependOn(gen_charsets_step);
    run_dump.step.dependOn(gen_unidata_step);
    // The dump must run with etc/DOC present: loadup calls
    // (Snarf-documentation "DOC"), and in pbootstrap mode it swallows
    // the error if DOC is missing, leaving every C primitive without a
    // doc string in the dumped image (doc-tests-documentation/c-primitive).
    run_dump.step.dependOn(gen_doc_step);
    const dump_step = b.step("dump", "Bootstrap (from-source) dump of bootstrap-emacs.pdmp");
    dump_step.dependOn(b.getInstallStep());
    dump_step.dependOn(&run_dump.step);

    // generate-charprop: produce lisp/international/{charprop,uni-*}.el
    // from admin/unidata via the dumped emacs (mirrors admin/unidata/
    // Makefile). Some lisp files (char-fold.el, shadowfile.el, and the
    // autoload scrape) need the Unicode property tables, so charprop
    // must exist before generate-loaddefs and compile-lisp; it runs
    // from the source (pbootstrap) dump, which avoids a cycle. Outputs
    // are gitignored; on a clean checkout nothing masks a missing
    // generation.
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
    // Writes gitignored lisp/international/{charprop,uni-*}.el into the
    // source tree; treat as side-effectful so a cached run can never skip
    // regeneration after the files vanish (mirrors gen_loaddefs).
    gen_charprop.has_side_effects = true;
    gen_charprop.step.dependOn(&run_dump.step);
    const gen_charprop_step = b.step(
        "generate-charprop",
        "Generate lisp/international/{charprop,uni-*}.el from admin/unidata",
    );
    gen_charprop_step.dependOn(&gen_charprop.step);

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
    // The tool writes the loaddefs/cus-load/finder-inf files directly
    // into the (gitignored) source tree, so Zig cannot see when an
    // external clean removes them.  Treat the run as side-effectful so a
    // cached run can never skip regeneration after the files vanish.
    gen_loaddefs.has_side_effects = true;
    gen_loaddefs.step.dependOn(&run_dump.step);
    const gen_loaddefs_step = b.step(
        "generate-loaddefs",
        "Generate lisp/loaddefs.el + *-loaddefs.el autoload files",
    );
    gen_loaddefs_step.dependOn(&gen_loaddefs.step);
    gen_loaddefs.step.dependOn(&gen_charprop.step);

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

    // generate-cedet-grammars: produce the cedet parser files
    // (semantic/*-wy.el, semantic/wisent/*-wy.el, semantic/bovine/*-by.el,
    // srecode/srt-wy.el) from admin/grammars via the bovine/wisent batch
    // generators (mirrors admin/grammars/Makefile.in). Upstream does not
    // track these; without them the cedet suites fail to load
    // ("Cannot open load file srecode/srt-wy").  Declared BEFORE
    // run_compile_lisp: on a cold checkout compile-lisp needs the grammar
    // files (cedet sources require the generated -wy.el at compile time),
    // so run_compile_lisp depends on gen_cedet below.
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
    // Writes gitignored cedet grammar files (semantic/*-wy.el etc.) into
    // the source tree; treat as side-effectful so a cached run can never
    // skip regeneration after the files vanish (mirrors gen_loaddefs).
    gen_cedet.has_side_effects = true;
    // The grammar batch generators run against the SOURCE bootstrap dump
    // (bootstrap-emacs.pdmp from `dump`; they load the grammar tools from
    // lisp/cedet source).  Depend on run_dump, NOT run_smoke: smoke needs
    // dump-compiled -> compile-lisp, and compile-lisp needs these grammar
    // files on a cold checkout, so wiring through smoke would be a cycle.
    gen_cedet.step.dependOn(&run_dump.step);
    const gen_cedet_step = b.step(
        "generate-cedet-grammars",
        "Generate cedet parser files from admin/grammars",
    );
    gen_cedet_step.dependOn(&gen_cedet.step);

    const run_compile_lisp = b.addRunArtifact(compile_lisp_tool);
    run_compile_lisp.setCwd(b.path("."));
    run_compile_lisp.step.dependOn(&run_dump.step);
    run_compile_lisp.step.dependOn(&gen_loaddefs.step);
    // Some lisp files (char-fold.el, shadowfile.el) load charprop at
    // compile time, so generate it from the source dump first (a clean
    // checkout has no stale charprop.el to mask the missing dependency).
    run_compile_lisp.step.dependOn(&gen_charprop.step);
    // Cold-checkout fix: cedet sources (lisp/cedet/{srecode,semantic}/**)
    // `require' the generated wisent/bovine grammars (srt-wy.el, c-by.el,
    // ...) AT COMPILE TIME, and those files are NOT tracked (generated
    // from admin/grammars/*.{by,wy}).  A cold clone (no warm zigbuild
    // cache) therefore failed to byte-compile ~20 cedet files ("Cannot
    // open load file srecode/srt-wy") unless generate-cedet-grammars had
    // run first.  gen_cedet depends on run_dump only (grammars run
    // against the source bootstrap dump), so this edge is cycle-free.
    // POSIX-only edge: the batch grammar generators (bovine/wisent)
    // do not run on the w32 console build (they exit non-zero there),
    // so on Windows the grammars are never generated and compile-lisp
    // falls back to its per-file skip (cedet .elc simply absent), the
    // pre-existing behavior before this wiring.
    if (!is_windows)
        run_compile_lisp.step.dependOn(&gen_cedet.step);
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
    // ABI-suffix the dump stamp (first extra argv arg; see run_dump above):
    // each backend must dump its own temacs+pdmp pair.
    run_dump_compiled.addArg(@tagName(target.result.abi));
    run_dump_compiled.step.dependOn(&run_compile_lisp.step);
    // Same temacs-content tracking as run_dump (flag flip -> rerun).
    run_dump_compiled.addFileArg(exe.getEmittedBin());
    const dump_compiled_step = b.step("dump-compiled", "Re-dump bootstrap-emacs.pdmp with compiled lisp");
    dump_compiled_step.dependOn(&run_dump_compiled.step);
    // The default `zig build` must produce a usable emacs, not just
    // temacs + the wrapper: wire the dumped image (bootstrap-emacs.pdmp)
    // and the runtime loaddefs files into the install step.  The dump
    // chain depends on install_temacs (not the whole install step), so
    // there is no cycle.  Native only: the dump *executes* temacs over
    // loadup, which is impossible for a cross target (the foreign temacs
    // cannot run on the build host), so a cross `zig build -Dtarget=...`
    // stays a compile-only check (install_temacs only), matching the
    // per-platform matrix in .github/workflows/ci.yml.
    const is_native_target = target.result.cpu.arch == b.graph.host.result.cpu.arch and
        target.result.os.tag == b.graph.host.result.os.tag and
        target.result.abi == b.graph.host.result.abi;
    // The dump *executes* the freshly built temacs over loadup, so it needs a
    // target the build host can run.  Exact triple equality is too strict on
    // Windows: the host ABI is often reported as gnu while -Dtarget selects
    // windows-msvc (or vice versa), yet BOTH ABIs' exes run on a Windows host
    // -- so gate on os+arch only when the host is Windows (a Linux/macOS host
    // cross-building windows still must not dump).  This is what lets
    // `zig build -Dtarget=x86_64-windows-msvc` dump and `install -p` ship a
    // runnable pdmp for the MSVC backend on a VS-equipped Windows machine,
    // exactly as it already does for GNU.
    const host_can_run_target = is_native_target or
        (b.graph.host.result.os.tag == .windows and
            target.result.os.tag == .windows and
            target.result.cpu.arch == b.graph.host.result.cpu.arch);
    if (host_can_run_target) b.getInstallStep().dependOn(dump_compiled_step);

    // `zig build install -p <dir>` must yield a self-consistent, runnable
    // emacs of the REQUESTED backend.  bootstrap-dump.zig runs
    // ./zig-out/bin/temacs.exe over loadup and writes the pdmp next to it,
    // so the dump drives whatever binary sits in zig-out/bin; with -Dtarget
    // flipping between gnu/msvc and a -p prefix, that file could hold the
    // OTHER backend's binary.  build.zig already passes this target's
    // emitted temacs as the tracked file arg; the tool STAGES it into
    // zig-out/bin before running loadup (see bootstrap-dump.zig), so every
    // dump comes from the REQUESTED backend's binary.  The prefix install
    // then ships that same emitted temacs + the dump's pdmp as a pair.
    if (host_can_run_target) {
        const temacs_base: []const u8 = if (target.result.os.tag == .windows)
            "temacs.exe"
        else
            "temacs";
        const install_temacs_pair = b.addInstallFileWithDir(
            exe.getEmittedBin(),
            .bin,
            temacs_base,
        );
        install_temacs_pair.step.dependOn(&install_temacs.step);
        b.getInstallStep().dependOn(&install_temacs_pair.step);
        const install_pdmp_pair = b.addInstallFileWithDir(
            b.path("zig-out/bin/bootstrap-emacs.pdmp"),
            .bin,
            "bootstrap-emacs.pdmp",
        );
        install_pdmp_pair.step.dependOn(&run_dump_compiled.step);
        b.getInstallStep().dependOn(&install_pdmp_pair.step);
    }

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
    // Same direct-to-source-tree writes as gen_loaddefs; rerun even when
    // the step was cached, otherwise check/check-all reuses the cached
    // run after an external clean and suites fail to load *-loaddefs.el.
    run_loaddefs_final.has_side_effects = true;
    run_loaddefs_final.step.dependOn(&run_dump_compiled.step);
    // dump-compiled produces "the pdmp that interactive use actually loads"
    // (its own docstring); smoke verifies that dumped emacs starts. Both must
    // leave the runtime loaddefs files present: the dump SCRUBBED them (loadup
    // must use ldefs-boot.el), and cl-lib.el loads cl-loaddefs.el at runtime
    // to autoload cl-extra's cl-some/cl-mapcan/cl-coerce (cl-lib deliberately
    // does NOT require cl-extra). Without this, an interactive `emacs -nw`
    // has void cl-* functions and fails to load any use-package-based
    // ~/.emacs.d. check already pulls run_loaddefs_final (via run-check); wire
    // it into the two "produce a usable emacs" flows too so they leave a tree
    // that autoloads correctly.
    dump_compiled_step.dependOn(&run_loaddefs_final.step);

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
    run_smoke.step.dependOn(&run_loaddefs_final.step);
    // Depend on the emacs-wrapper install step (chmod +x on Unix; the
    // native emacs.exe build on Windows) so the runnable `emacs` exists
    // before smoke invokes ./zig-out/bin/emacs(.exe).
    run_smoke.step.dependOn(emacs_wrapper_step);
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
    // cedet suites require the generated wisent grammars
    // (srecode/srt-wy.el, ...); on Windows the batch grammar generators
    // exit non-zero, so gate the dependency like compile-lisp does.
    if (!is_windows) run_check_all.step.dependOn(&gen_cedet.step);
    const check_all_step = b.step("check-all", "Run ALL ert suites (no skip; per-suite isolation + timeout) and classify failures");
    check_all_step.dependOn(&run_check_all.step);

    // modules-test: build the sample dynamic module
    // (test/src/emacs-module-resources/mod-test.c) as mod-test.so and install
    // it to zig-out/test/src/emacs-module-resources/, the path
    // emacs-module-tests.el resolves mod-test-file to (relative to
    // invocation-directory = zig-out/bin).  mod-test.c uses the mpz_* bignum
    // API (extract/make_big_integer, the nanoseconds test), so the .so links
    // emacs-bignum (its own copy, separate from temacs's -- the module is a
    // standalone shared object) and includes the tools/bignum gmp.h shim.
    // Upstream MODULE_CFLAGS is just -fPIC.  Gated on modules_enabled (Track
    // B B2, plan section 13); off by default so the default build is
    // unchanged.  The dumped emacs validates the module via a separate
    // invocation (see the modules-test invocation in the plan):
    //   ./zig-out/bin/emacs --batch -L test -L test/src -l ert \
    //     -l test/src/emacs-module-tests.el -f ert-run-tests-batch-and-exit
    // Track-B B-Z: widened from modules_enabled to modules_runtime so the
    // sample module builds under -Dmodules-zig too (the dumped emacs then
    // loads it through the Zig-provided dynlib_* surface).
    if (modules_runtime) {
        const mod_test_mod = b.createModule(.{
            .target = target,
            // ReleaseFast (not the build's Debug default): mod-test.c calls
            // memset (NULL, 'a', 0) on a zero-length allocation (line 748),
            // which is a libc no-op but traps under Zig's Debug nonnull
            // safety check.  ReleaseFast disables that check (matching how
            // gcc/clang build this module upstream) while keeping the C
            // semantics identical.  Same optimize the gnulib Zig packages use.
            .optimize = .ReleaseFast,
            .link_libc = true,
        });
        const mod_test_flags = [_][]const u8{
            "-std=gnu2x",
            "-fno-common",
            "-fPIC",
            "-fno-strict-aliasing",
            "-D_GNU_SOURCE",
            "-DHAVE_CONFIG_H",
            "-Isrc",
        };
        mod_test_mod.addCSourceFile(.{
            .file = b.path("test/src/emacs-module-resources/mod-test.c"),
            .flags = &mod_test_flags,
        });
        // mod-test.c includes "config.h" + <emacs-module.h> (src/) +
        // <gmp.h> (tools/bignum/include).  The target config provides config.h.
        mod_test_mod.addIncludePath(target_config_h_file.file.dirname());
        mod_test_mod.addIncludePath(
            b.dependency("bignum", .{}).path("include"),
        );
        mod_test_mod.linkLibrary(bignum_lib);
        const mod_test_lib = b.addLibrary(.{
            .name = "mod-test",
            .root_module = mod_test_mod,
            .linkage = .dynamic,
        });
        // Ensure config.h is generated before mod-test.c compiles (the
        // addIncludePath LazyPath carries the file dependency; this adds the
        // ordering edge to the generator step, mirroring exe at line 616).
        mod_test_lib.step.dependOn(target_config_h_file.step);
        // emacs-module.h (generated into the source tree) is found via the
        // mod-test.c compile's -Isrc; the gen-emacs-module-h run step must
        // have produced it first.
        if (run_gen_emh) |r| mod_test_lib.step.dependOn(&r.step);
        // Install as mod-test.<suffix> (NOT libmod-test.<suffix>): the suite
        // resolves the load path with the bare module base name, no lib
        // prefix.  .prefix is the zig-out root, so the full dest_rel_path
        // lands the module exactly where emacs-module-tests.el's mod-test-file
        // points.  The suffix must match the platform's MODULES_SUFFIX (the
        // PRIMARY module suffix): ".dylib" on darwin, ".dll" on Windows,
        // ".so" on ELF hosts -- emacs-module-tests' darwin-secondary-suffix
        // test asserts the primary file exists and manufactures the secondary
        // (.so) via add-name-to-file, and describe-function-1 compares against
        // module-file-suffix.  Installing the wrong name fails those on macOS.
        const mod_suffix: []const u8 = switch (target.result.os.tag) {
            .macos => ".dylib",
            .windows => ".dll",
            else => ".so",
        };
        const mod_install_path = std.fmt.allocPrint(
            b.allocator,
            "test/src/emacs-module-resources/mod-test{s}",
            .{mod_suffix},
        ) catch @panic("OOM");
        const install_mod_test = b.addInstallFileWithDir(
            mod_test_lib.getEmittedBin(),
            .prefix,
            mod_install_path,
        );
        install_mod_test.step.dependOn(&mod_test_lib.step);
        b.getInstallStep().dependOn(&install_mod_test.step);
        const modules_test_step = b.step(
            "modules-test",
            "Build the sample dynamic module (mod-test.so) for emacs-module-tests",
        );
        modules_test_step.dependOn(&install_mod_test.step);

        // ---- modules-test-run: full module validation (plan B2).  Runs the
        // UPSTREAM emacs-module-tests suite against the dumped emacs with the
        // sample module installed; mod-test-file resolves relative to
        // invocation-directory (zig-out/bin) to the installed mod-test.so.
        // The same ert batch entry as upstream `make check` uses for the
        // module API (env functions, user-ptr, finalizers, signal / non-local
        // exit, threadsafety).  Requires the mod-test build above.
        const run_module_tests = b.addSystemCommand(&[_][]const u8{
            "./zig-out/bin/emacs", "--batch",
            "-L",                  "test/src",
            "-l",                  "test/src/emacs-module-tests.el",
            "-f",                  "ert-run-tests-batch-and-exit",
        });
        run_module_tests.setCwd(b.path("."));
        run_module_tests.step.dependOn(&run_dump_compiled.step);
        run_module_tests.step.dependOn(&run_loaddefs_final.step);
        run_module_tests.step.dependOn(&install_mod_test.step);
        const modules_test_run_step = b.step(
            "modules-test-run",
            "Run the upstream emacs-module-tests suite (full module validation)",
        );
        modules_test_run_step.dependOn(&run_module_tests.step);
    }

    // Phase-2.1 native-comp Zig path (M0 spike, plan §6).  Opt-in: only
    // when -Dnative-comp-zig=true AND a native (non-cross) build.  Produces
    // zig-out/bin/test-spike.zeln via zunit -> .ll -> `zig cc -shared`,
    // and proves the full C<->Zig contract (plan §8).  OFF by default =>
    // zero footprint (compz.c is not even compiled; see line 1198).  The
    // .zeln is a native shared object (ELF .so on glibc, Mach-O .dylib on
    // macOS, PE .dll on Windows) produced by `zig cc -shared`, so the
    // whole pipeline runs on every native OS; static-musl stays excluded
    // (it cannot dlopen).  host_can_run_target (os+arch, not exact-triple)
    // gates this for the same reason as the dump: a Windows host runs BOTH
    // ABI backends' exes and .zeln shared objects, so the msvc target gets
    // the full .zeln feature steps as well.
    if (enable_native_comp_zig and host_can_run_target and !is_musl) {
        // The zeln-compile tool: a host Zig executable that parses a
        // zunit, emits the Tier-0 .ll, and drives `zig cc -shared`.
        // Mirrors compile_lisp_tool (an addExecutable over a tools/
        // package root, targeting the build host).  Built whenever the
        // flag is on so `zig build -Dnative-comp-zig=true` produces it.
        const zeln_compile_dep = b.dependency("zeln_compile", .{});
        const zeln_compile_tool = b.addExecutable(.{
            .name = "zeln-compile",
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .optimize = .Debug,
                .root_source_file = zeln_compile_dep.path("src/main.zig"),
            }),
        });
        // Installed filename + ZELN_COMPILE path.  Windows needs the .exe
        // suffix: the emitted executable is zeln-compile.exe there, and
        // file-executable-p / the shell won't accept it without it.
        const zeln_compile_bin = if (b.graph.host.result.os.tag == .windows)
            "zeln-compile.exe"
        else
            "zeln-compile";
        // Install the tool to zig-out/bin so the runtime FDO harness can
        // spawn it (ZELN_COMPILE env, zeln-fdo.el); the same binary the
        // spike / zeln-diff / populate steps invoke directly.
        const install_zeln_compile = b.addInstallFileWithDir(
            zeln_compile_tool.getEmittedBin(),
            .prefix,
            b.fmt("bin/{s}", .{zeln_compile_bin}),
        );
        install_zeln_compile.step.dependOn(&zeln_compile_tool.step);
        b.getInstallStep().dependOn(&install_zeln_compile.step);

        // Step 1: run the dumped emacs to serialize the spike zunit +
        // manifest (comp-z-write-spike-zunit is defined in src/compz.c).
        // The dumped emacs (bootstrap-emacs.pdmp from dump-compiled) and
        // the runtime loaddefs must both be in place; chmod_emacs_wrapper
        // ensures ./zig-out/bin/emacs is executable.  Output lands in
        // zig-out/bin (a real directory; zig-out/etc is a symlink to the
        // source tree and must not be polluted by spike artifacts).
        const spike_ser = b.addSystemCommand(&[_][]const u8{
            "./zig-out/bin/emacs",                                   "--batch", "--eval",
            "(comp-z-write-spike-zunit \"zig-out/bin/zeln-spike\")",
        });
        spike_ser.setCwd(b.path("."));
        spike_ser.step.dependOn(&run_dump_compiled.step);
        spike_ser.step.dependOn(&run_loaddefs_final.step);
        spike_ser.step.dependOn(emacs_wrapper_step);

        // Step 2: run zeln-compile over the zunit -> .ll -> .zeln.
        const spike_compile = b.addRunArtifact(zeln_compile_tool);
        // The zeln-compile child spawns `zig cc`; pass the build's own zig
        // executable explicitly (absolute path) so the child never depends
        // on PATH lookup (which CI runners can lose in the child chain).
        spike_compile.setEnvironmentVariable("ZELN_ZIG_CC", b.graph.zig_exe);
        spike_compile.setCwd(b.path("."));
        spike_compile.addArg("zig-out/bin/zeln-spike.zunit");
        spike_compile.addArg("zig-out/bin/zeln-spike.manifest");
        spike_compile.addArg("zig-out/bin/test-spike.zeln");
        spike_compile.step.dependOn(&spike_ser.step);

        // test-spike.zeln now lives under zig-out/bin (a real dir); no
        // separate install step is needed.  The step is the single handle
        // the M0 proof / CI gate (plan §8) drives.
        const zeln_spike_step = b.step(
            "zeln-compile-spike",
            "M0 spike: build test-spike.zeln (zunit -> .ll -> .zeln)",
        );
        zeln_spike_step.dependOn(&spike_compile.step);

        // ---- M1 differential-test step (plan M1) ----------------------------
        // The M1 correctness gate.  byte-compile each corpus fn, serialize it
        // via comp-z-write-zunit, compile each .zunit to .zeln, then funcall
        // the reference closure (exec_byte_code) vs the .zeln native fn on a
        // shared input set and assert behavioral identity.  Behavioral IDENTITY
        // is the only gate; speed is not measured (Tier-0; M3 is the perf gate).
        // OFF unless -Dnative-comp-zig=true (this whole block is under that
        // guard) so the default build has zero footprint.
        //
        // The corpus + inputs live in build-aux/zeln-diff.el (single source of
        // truth); build.zig only needs the fn names here to mint one
        // zeln-compile run step per fn (zeln-compile consumes one zunit).
        const diff_names = [_][]const u8{
            "inc",      "arith",    "abs",       "cadr",       "conslist", "loop",
            "rec",      "fmt",      "list3",     "strpred",    "rest",     "list6",
            "list7",    "const2",
            // ---- M2 corpus (one+ per new opcode group) ----
              "dynvar",    "saveex",     "saverest", "savebuf",
            "unwind",   "condcase", "catchself", "catchcross", "vecstr",   "asetop",
            "concatn",  "listops",  "consmut",   "nconcop",    "bufrange", "bufmove",
            "matchops", "strcase",  "arith2",    "symfns",     "fnsym",    "markerop",
            "bufpred",
        };

        // (a) Serialize: emacs --batch -l zeln-diff.el --eval run-serialize.
        // Produces zig-out/bin/zeln-diff/<name>.{zunit,manifest} per fn.
        const diff_ser = b.addSystemCommand(&[_][]const u8{
            "./zig-out/bin/emacs", "--batch",
            "-l",                  "build-aux/zeln-diff.el",
            "--eval",              "(zeln-diff-run-serialize)",
        });
        diff_ser.setCwd(b.path("."));
        diff_ser.step.dependOn(&run_dump_compiled.step);
        diff_ser.step.dependOn(&run_loaddefs_final.step);
        diff_ser.step.dependOn(emacs_wrapper_step);

        // (c) Harness: emacs --batch -l zeln-diff.el --eval run-harness.  Loads
        // each .zeln, funcalls baseline vs native on the shared inputs, prints
        // "M1 differential: N/N functions identical", and exits non-zero on the
        // first mismatch.  Declared before the compile loop so each per-fn
        // compile step can be wired as its dependency (it must run AFTER every
        // .zeln is produced).
        const diff_harness = b.addSystemCommand(&[_][]const u8{
            "./zig-out/bin/emacs", "--batch",
            "-l",                  "build-aux/zeln-diff.el",
            "--eval",              "(zeln-diff-run-harness)",
        });
        diff_harness.setCwd(b.path("."));
        diff_harness.step.dependOn(&run_dump_compiled.step);
        diff_harness.step.dependOn(emacs_wrapper_step);
        diff_harness.step.dependOn(&diff_ser.step);

        // (b) Compile each .zunit -> .ll -> .zeln (one zeln-compile run per fn).
        // Each depends on serialize; the harness depends on each.  Independent
        // of one another (zeln-compile is a leaf invocation).
        const diff_dir = "zig-out/bin/zeln-diff";
        for (diff_names) |name| {
            const zunit_arg = std.fmt.allocPrint(b.allocator, "{s}/{s}.zunit", .{ diff_dir, name }) catch unreachable;
            const manifest_arg = std.fmt.allocPrint(b.allocator, "{s}/{s}.manifest", .{ diff_dir, name }) catch unreachable;
            const zeln_arg = std.fmt.allocPrint(b.allocator, "{s}/{s}.zeln", .{ diff_dir, name }) catch unreachable;
            const dc = b.addRunArtifact(zeln_compile_tool);
            dc.setEnvironmentVariable("ZELN_ZIG_CC", b.graph.zig_exe);
            dc.setCwd(b.path("."));
            dc.addArg(zunit_arg);
            dc.addArg(manifest_arg);
            dc.addArg(zeln_arg);
            dc.step.dependOn(&diff_ser.step);
            diff_harness.step.dependOn(&dc.step);
        }

        // The single handle the M1 gate drives.
        const zeln_diff_step = b.step(
            "zeln-diff",
            "M1 differential test: interpreter vs .zeln on the corpus (N/N identical)",
        );
        // MSVC host: SKIP.  The zeln-diff harness loads .zeln files and
        // funcalls their native entry points.  On MSVC, the host's longjmp
        // invokes RtlUnwind which cannot walk LLVM-generated .zeln frames
        // (fundamental ABI limitation; exit 40).  Populate coverage gate
        // still proves compilation.
        // MSVC: skip — .zeln execution hits MSVC UCRT _setjmp ABI mismatch.
        if (target.result.abi != .msvc) zeln_diff_step.dependOn(&diff_harness.step);

        // ---- M2b cache-population step (deliverable 1) --------------------
        // populate-zeln-cache: walk lisp/**/*.elc, serialize each to a
        // zabi=3 zunit (comp-z-write-file-zunit), then run zeln-compile per
        // zunit into .zeln-cache/<ver>/<rel>.zeln.  Per-file fault tolerance:
        // a zeln-compile non-zero exit (emitter UnsupportedOpcode on
        // Bswitch/obsolete, or a serializer signal) is caught per-.elc and
        // recorded in zig-out/zeln-cache/SKIP-LIST; the step exits 0 and
        // prints the coverage ratio.  Those .elc fall back to the
        // interpreter via the transparent-load fallthrough.
        const populate_tool = b.addExecutable(.{
            .name = "populate-zeln-cache",
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .optimize = .Debug,
                .root_source_file = b.path("build-aux/populate-zeln-cache.zig"),
            }),
        });
        const run_populate = b.addRunArtifact(populate_tool);
        // The populate driver spawns zeln-compile itself, which spawns
        // `zig cc`; the explicit zig path propagates through env.inherit.
        run_populate.setEnvironmentVariable("ZELN_ZIG_CC", b.graph.zig_exe);
        // Target triple for the .zeln objects: zeln-compile passes it to
        // `zig cc -target` so the native units match THIS build's ABI (a
        // -Dtarget=x86_64-windows-msvc build must not emit host-gnu
        // objects), and uses it to reject handler-carrying units on msvc
        // (longjmp-into-JIT-frame aborts there; those files fall back to
        // the interpreter).  MUST be zig's own triple spelling
        // (target.zigTriple, e.g. aarch64-macos / x86_64-windows-msvc) --
        // canonicalConfiguration's autoconf form (aarch64-apple-darwin) is
        // not a valid -target value and failed every compile on macOS.
        //
        // Windows: ALWAYS use the GNU (MinGW) triple for .zeln, even when
        // the host is MSVC.  Both use the Microsoft x64 calling convention,
        // so freloc function pointers are interchangeable.  The MSVC CRT's
        // longjmp on x64 always invokes RtlUnwind (mandatory per the x64
        // ABI), which walks every stack frame; MSVC-target .zeln DLLs
        // produced by zig cc lack the SEH unwind metadata the unwinder
        // needs, crashing with exit 40.  MinGW-target .zeln DLLs carry
        // proper .pdata/.xdata that RtlUnwind understands.  Additionally,
        // loading a MinGW DLL avoids the MSVC UCRT _setjmp intrinsic
        // abort entirely (the gate rejects handler-carrying units, so the
        // .zeln never calls setjmp directly).
        const zeln_target_triple = if (target.result.os.tag == .windows)
            "x86_64-windows-gnu"
        else
            target.result.zigTriple(b.allocator) catch @panic("OOM");
        run_populate.setEnvironmentVariable(
            "ZELN_TARGET",
            zeln_target_triple,
        );
        // The .zeln IR must call the SAME setjmp/longjmp pair as the host
        // emacs (sys_setjmp/sys_longjmp in lisp.h).  Since .zeln is always
        // compiled for the GNU target on Windows (see above), use the
        // MinGW CRT's plain setjmp/longjmp pair.  The pushhandler gate
        // rejects handler-carrying units on MSVC, so the symbol is never
        // actually called for msvc-host .zeln; it only matters for GNU
        // hosts where both sides use the MinGW CRT.
        run_populate.setEnvironmentVariable("ZELN_SETJMP_SYM", "setjmp");
        // Deterministic interpreter for the build-time serialize/BC walk
        // (the JIT gate is a runtime feature; the batch pipeline pins it).
        run_populate.setEnvironmentVariable("ZELN_JIT", "0");
        // The pushhandler gate in zeln-compile needs to know the HOST ABI
        // (not the .zeln target): MSVC hosts must reject handler-carrying
        // units because their setjmp/longjmp CRT formats are incompatible
        // with MinGW .zeln code.
        if (target.result.abi == .msvc) {
            run_populate.setEnvironmentVariable("ZELN_HOST_MSVC", "1");
        }
        run_populate.setCwd(b.path("."));
        // Pass the built zeln-compile exe as a file arg (tracked dep) so the
        // driver can spawn one zeln-compile per zunit.
        run_populate.addFileArg(zeln_compile_tool.getEmittedBin());
        // Track temacs (its subrs decide whether comp-z-write-file-zunit is
        // bound in the dumped image) so a flag flip invalidates the cache.
        run_populate.addFileArg(exe.getEmittedBin());
        run_populate.step.dependOn(&zeln_compile_tool.step);
        run_populate.step.dependOn(&run_compile_lisp.step);
        run_populate.step.dependOn(&run_dump_compiled.step);
        run_populate.step.dependOn(&run_loaddefs_final.step);
        run_populate.step.dependOn(emacs_wrapper_step);
        const populate_step = b.step(
            "populate-zeln-cache",
            "M2b: populate .zeln-cache from lisp/**/*.elc (per-file tolerant)",
        );
        populate_step.dependOn(&run_populate.step);

        // ---- M2b 582-via-.zeln gate (deliverable 3) -----------------------
        // check-zeln: a second run of run-check with ZELN_LOAD_PATH set to
        // the populated cache, so the dumped emacs transparently swaps
        // .elc -> .zeln where compiled (and falls through to the interpreter
        // where skipped).  The SAME test list / ert selector as the off-path
        // `check' run (run-check.zig), so the two ert summaries are directly
        // comparable -- the behavioral-identity proof.  check-zeln depends
        // on populate-zeln-cache (build-graph ordering prevents the mtime
        // race between populating and consuming the cache).
        const run_check_zeln = b.addRunArtifact(run_check_tool);
        run_check_zeln.setCwd(b.path("."));
        // Relative path (resolved by the dumped emacs's expand-file-name
        // against ITS default-directory, which run-check sets to the repo
        // root via cwd).  An ABSOLUTE path here was tried and REGRESSED
        // check-zeln on the GNU backend (8 resource-load failures, the
        // same signature CI shows): keep the original relative form.
        // MSVC host: do NOT set ZELN_LOAD_PATH.  The MSVC CRT's longjmp
        // on x64 ALWAYS invokes RtlUnwind (mandatory per the x64 ABI);
        // RtlUnwind cannot correctly walk LLVM-compiled .zeln frames
        // (personality routine incompatibility, exit 40) regardless of
        // whether the .zeln is compiled for GNU or MSVC target.  The
        // populate-zeln-cache coverage gate (48.5% > 45%) still proves
        // the .zeln compilation pipeline works.
        // MSVC host: skip ZELN_LOAD_PATH.  Even with uwtable +
        // __C_specific_handler personality (which fixes RtlUnwind frame
        // walking), the .zeln's _setjmp call from LLVM code still hits
        // the MSVC UCRT intrinsic mismatch (exit 40).  This requires a
        // C-level wrapper for pushhandler to fix (architectural change).
        if (target.result.abi != .msvc) {
            run_check_zeln.setEnvironmentVariable("ZELN_LOAD_PATH", "zig-out/zeln-cache");
        }
        run_check_zeln.step.dependOn(&run_populate.step);
        run_check_zeln.step.dependOn(&run_dump_compiled.step);
        run_check_zeln.step.dependOn(&run_loaddefs_final.step);
        run_check_zeln.step.dependOn(emacs_wrapper_step);
        const check_zeln_step = b.step(
            "check-zeln",
            "M2b: run 582 built-in tests with transparent .zeln loading",
        );
        check_zeln_step.dependOn(&run_check_zeln.step);

        // ---- full-suite AOT + in-process JIT gate -------------------------
        // Same .zeln-backed 582-test run as check-zeln, but the runtime
        // JIT gate is armed in the Emacs children.  This deliberately goes
        // through a separate ZELN_TEST_JIT control so it cannot leak into
        // loaddefs/dump children.
        const run_check_zeln_jit = b.addRunArtifact(run_check_tool);
        run_check_zeln_jit.setCwd(b.path("."));
        run_check_zeln_jit.setEnvironmentVariable("ZELN_LOAD_PATH", "zig-out/zeln-cache");
        run_check_zeln_jit.setEnvironmentVariable("ZELN_TEST_JIT", "1");
        run_check_zeln_jit.step.dependOn(&run_populate.step);
        run_check_zeln_jit.step.dependOn(&run_dump_compiled.step);
        run_check_zeln_jit.step.dependOn(&run_loaddefs_final.step);
        run_check_zeln_jit.step.dependOn(emacs_wrapper_step);
        const check_zeln_jit_step = b.step(
            "check-zeln-jit",
            "Run 582 built-in tests with .zeln loading and the runtime JIT gate on",
        );
        check_zeln_jit_step.dependOn(&run_check_zeln_jit.step);

        // ---- zeln-fdo: the Z5 auto profile-guided recompilation loop.
        // build-aux/zeln-fdo.el drives the full closed loop on a SIMULATED
        // .zeln: build a 2-fn fixture, serialize + compile it, load with
        // zeln-auto-fdo-path/profile/interval set (tiny interval + low
        // threshold), hammer the hot fn, force GC (the loader flushes a
        // profile and hot-swaps a --profile recompile), hammer again +
        // GC (round 2 --profile --final: counters dropped), then assert the
        // profile file exists, the final .zeln is hot-first, and the hot
        // fn still returns the correct value after both swaps.  Exits
        // non-zero on any failure.  ZELN_COMPILE points at the installed
        // zeln-compile (the harness spawns it itself).
        const run_fdo = b.addSystemCommand(&[_][]const u8{
            "./zig-out/bin/emacs", "--batch",
            "-l",                  "build-aux/zeln-fdo.el",
            "--eval",              "(zeln-fdo-run)",
        });
        run_fdo.setCwd(b.path("."));
        run_fdo.setEnvironmentVariable("ZELN_COMPILE", b.fmt("zig-out/bin/{s}", .{zeln_compile_bin}));
        run_fdo.step.dependOn(&install_zeln_compile.step);
        run_fdo.step.dependOn(&run_dump_compiled.step);
        run_fdo.step.dependOn(&run_loaddefs_final.step);
        run_fdo.step.dependOn(emacs_wrapper_step);
        const zeln_fdo_step = b.step(
            "zeln-fdo",
            "Z5: auto profile-guided recompilation loop (collect -> recompile -> hot-swap)",
        );
        zeln_fdo_step.dependOn(&run_fdo.step);

        // ---- zeln-pgo: the Z7 multi-fixture PGO gate.  Same closed loop
        // as zeln-fdo (build -> instrument -> load -> hammer -> GC ->
        // profile recompile -> hot-swap -> --final), but over a CORPUS of
        // workload-shaped fixtures (dispatch loop / recursion / bignum
        // overflow / list ops / dense arith / branchy) instead of a single
        // hot/cold pair.  Runs identically on glibc-Linux, macOS and
        // Windows (the .zeln is a native .so/.dylib/.dll), so it can gate
        // the per-platform CI matrix.  Hammer count is parameterized via
        // ZELN_PGO_HAMMER (default 150000/round) for quick CI runs.
        const run_pgo = b.addSystemCommand(&[_][]const u8{
            "./zig-out/bin/emacs", "--batch",
            "-l",                  "build-aux/zeln-pgo.el",
            "--eval",              "(zeln-pgo-run)",
        });
        run_pgo.setCwd(b.path("."));
        run_pgo.setEnvironmentVariable("ZELN_COMPILE", b.fmt("zig-out/bin/{s}", .{zeln_compile_bin}));
        run_pgo.step.dependOn(&install_zeln_compile.step);
        run_pgo.step.dependOn(&run_dump_compiled.step);
        run_pgo.step.dependOn(&run_loaddefs_final.step);
        run_pgo.step.dependOn(emacs_wrapper_step);
        const zeln_pgo_step = b.step(
            "zeln-pgo",
            "Z7: multi-fixture PGO closed-loop test (6 workload shapes)",
        );
        // MSVC host: SKIP (same .zeln execution limitation as zeln-diff).
        // MSVC: skip — same .zeln execution limitation.
        if (target.result.abi != .msvc) zeln_pgo_step.dependOn(&run_pgo.step);

        // ---- zeln-jit-unit: run the emitter/compiler tests from the root
        // graph.  The smoke gate depends on these so an executable gate
        // cannot pass while the platform fallback or instruction encoding
        // invariants have regressed underneath it.
        const zeln_jit_unit_mod = b.createModule(.{
            .root_source_file = b.dependency("zeln_jit", .{}).path("src/jit.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        });
        const zeln_jit_unit_tests = b.addTest(.{
            .root_module = zeln_jit_unit_mod,
        });
        const run_zeln_jit_unit = b.addRunArtifact(zeln_jit_unit_tests);
        const zeln_jit_unit_step = b.step(
            "zeln-jit-unit",
            "Run zeln-jit emitter/compiler unit tests",
        );
        zeln_jit_unit_step.dependOn(&run_zeln_jit_unit.step);

        // ---- zeln-jit-smoke: a tiny executable gate for the in-process
        // JIT.  It checks both correctness and seam behavior: fixed-arity
        // machine-code dispatch, rebuilt-closure constants rebinding,
        // and a Lisp error crossing a generated frame.  On non-x86_64 the
        // Lisp gate reports SKIP and exits successfully; CI runs the full
        // JIT suite only on x86_64 targets where it can prove dispatch.
        const run_jit_smoke = b.addSystemCommand(&[_][]const u8{
            "./zig-out/bin/emacs", "--batch",
            "-l",                  "build-aux/zeln-jit-smoke.el",
            "--eval",              "(zeln-jit-smoke-run)",
        });
        run_jit_smoke.setCwd(b.path("."));
        run_jit_smoke.setEnvironmentVariable("ZELN_JIT", "1");
        run_jit_smoke.setEnvironmentVariable(
            "ZELN_COMPILE",
            b.fmt("zig-out/bin/{s}", .{zeln_compile_bin}),
        );
        run_jit_smoke.step.dependOn(&run_dump_compiled.step);
        run_jit_smoke.step.dependOn(&run_loaddefs_final.step);
        run_jit_smoke.step.dependOn(emacs_wrapper_step);
        run_jit_smoke.step.dependOn(&install_zeln_compile.step);
        run_jit_smoke.step.dependOn(&run_zeln_jit_unit.step);
        const zeln_jit_smoke_step = b.step(
            "zeln-jit-smoke",
            "Run the executable in-process JIT smoke/error-path gate",
        );
        zeln_jit_smoke_step.dependOn(&run_jit_smoke.step);

        // ---- zeln-interop-smoke: end-to-end transparent replacement gate.
        // It compiles one fixture with both backends, then runs clean child
        // Emacs processes for both `native-comp-z-prefer' values and checks
        // which native unit's file actually won.  Enabled only in combined
        // builds; zeln-only has no .eln candidate to replace.
        if (enable_native_comp) {
            const run_interop_smoke = b.addSystemCommand(&[_][]const u8{
                "./zig-out/bin/emacs", "--batch",
                "-l",                  "build-aux/zeln-interop-smoke.el",
                "--eval",              "(zeln-interop-smoke-run)",
            });
            run_interop_smoke.setCwd(b.path("."));
            run_interop_smoke.setEnvironmentVariable(
                "ZELN_COMPILE",
                b.fmt("zig-out/bin/{s}", .{zeln_compile_bin}),
            );
            run_interop_smoke.setEnvironmentVariable("ZELN_EMACS", "zig-out/bin/emacs");
            run_interop_smoke.step.dependOn(&run_dump_compiled.step);
            run_interop_smoke.step.dependOn(&run_loaddefs_final.step);
            run_interop_smoke.step.dependOn(emacs_wrapper_step);
            run_interop_smoke.step.dependOn(&install_zeln_compile.step);
            const zeln_interop_smoke_step = b.step(
                "zeln-interop-smoke",
                "Verify transparent .eln/.zeln selection by native-comp-z-prefer",
            );
            zeln_interop_smoke_step.dependOn(&run_interop_smoke.step);
        }

        // ---- zeln-jit-bench: interpreter / AOT / in-process JIT timing.
        // The benchmark force-compiles an identity-distinct clone of each
        // workload, verifies zeln-jit-compiled-p and every JIT result, then
        // times the interpreter and JIT clones in one process without letting
        // the interpreter A/B closure cross the hotness gate.  It also runs
        // the existing .zeln AOT compile/correctness path, so native/jit is
        // measured over the same program shapes.
        const run_jit_bench = b.addSystemCommand(&[_][]const u8{
            "./zig-out/bin/emacs", "--batch",
            "-l",                  "build-aux/zeln-bench.el",
            "--eval",              "(zeln-bench-run nil t)",
        });
        run_jit_bench.setCwd(b.path("."));
        run_jit_bench.setEnvironmentVariable("ZELN_COMPILE", b.fmt("zig-out/bin/{s}", .{zeln_compile_bin}));
        run_jit_bench.setEnvironmentVariable("ZELN_JIT", "1");
        run_jit_bench.setEnvironmentVariable(
            "ZIG_GLOBAL_CACHE_DIR",
            b.fmt("{s}/zeln-jit-bench-global", .{b.graph.global_cache_root.path orelse ".zig-cache"}),
        );
        run_jit_bench.setEnvironmentVariable(
            "ZIG_LOCAL_CACHE_DIR",
            b.fmt("{s}/zeln-jit-bench-cache", .{b.cache_root.path orelse ".zig-cache"}),
        );
        run_jit_bench.step.dependOn(&install_zeln_compile.step);
        run_jit_bench.step.dependOn(&run_dump_compiled.step);
        run_jit_bench.step.dependOn(&run_loaddefs_final.step);
        run_jit_bench.step.dependOn(emacs_wrapper_step);
        const zeln_jit_bench_step = b.step(
            "zeln-jit-bench",
            "Perf comparison: interpreter vs .zeln AOT vs in-process JIT (verified JIT dispatch)",
        );
        zeln_jit_bench_step.dependOn(&run_jit_bench.step);

        // ---- bench-check: real-suite perf comparison (interpreter vs
        // .zeln) over the SAME 582 built-in tests.  bench-tests runs the
        // run-check harness in both modes (ZELN_LOAD_PATH unset vs the
        // populated cache) best-of-3 and reports the wall-clock ratio — the
        // complete performance comparison on the real test/ suites, with the
        // original interpreter as baseline.  Depends on populate (mtime
        // ordering) + the dump chain, mirroring check-zeln.
        const bench_tool = b.addExecutable(.{
            .name = "bench-tests",
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .optimize = .Debug,
                .root_source_file = b.path("build-aux/bench-tests.zig"),
            }),
        });
        const run_bench = b.addRunArtifact(bench_tool);
        run_bench.setCwd(b.path("."));
        run_bench.addFileArg(run_check_tool.getEmittedBin());
        run_bench.addArg("zig-out/zeln-cache");
        run_bench.step.dependOn(&run_populate.step);
        run_bench.step.dependOn(&run_dump_compiled.step);
        run_bench.step.dependOn(&run_loaddefs_final.step);
        run_bench.step.dependOn(emacs_wrapper_step);
        const bench_step = b.step(
            "bench-check",
            "Real-suite perf: interpreter vs .zeln on the 582 built-in tests (best-of-3)",
        );
        bench_step.dependOn(&run_bench.step);
    }
    // The help step below prints only a static banner.  Avoid the `echo`
    // system command that the Unix shell implies: on a bare Windows host
    // (no MSYS2, per the migration goal) `echo` is a cmd.exe builtin with no
    // echo.exe binary, so spawning it via addSystemCommand fails with
    // FileNotFound.  Instead a small custom step prints the banner directly
    // through std.debug.print, which is cross-platform and needs only the
    // Zig runtime.  The banner text uses the same wording as the prior echo.
    const helptext = std.fmt.allocPrint(b.allocator,
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
        \\Windows backends (via -Dtarget, Windows host only):
        \\  -Dtarget=x86_64-windows-gnu   - GNU/MinGW backend (default; zig's bundled headers+libs)
        \\  -Dtarget=x86_64-windows-msvc  - MSVC backend (requires Visual Studio / Windows SDK)
        \\
        \\Native-comp Zig path (opt-in: -Dnative-comp-zig=true; native
        \\  Linux/macOS/Windows targets; JIT execution is x86-64 only):
        \\  zig build zeln-compile-spike - M0 spike: build test-spike.zeln
        \\  zig build zeln-diff         - M1/M2 differential test (N/N identical)
        \\  zig build populate-zeln-cache - M2b: populate .zeln-cache from lisp/
        \\  zig build check-zeln        - M2b: 582 built-in tests via .zeln
        \\  zig build check-zeln-jit    - 582 built-in tests with AOT + runtime JIT
        \\  zig build zeln-jit-unit     - zeln-jit emitter/compiler unit tests
        \\  zig build zeln-jit-smoke    - executable in-process JIT/error-path gate
        \\  zig build zeln-jit-bench    - interpreter/AOT/JIT performance comparison
        \\  zig build zeln-fdo          - Z5: auto profile-guided recompile loop
        \\  zig build zeln-pgo          - Z7: multi-fixture PGO test (6 workload shapes)
        \\
        \\Proto-UI path (opt-in: -Dproto-ui=true):
        \\  zig build -Dproto-ui=true proto-ui-unit - adapter and EUP protocol tests
        \\
        \\Native-comp gccjit path (opt-in: -Dnative-comp=true, native glibc-Linux;
        \\  requires libgccjit). Coexists with -Dnative-comp-zig: when both are on,
        \\  `native-comp-z-prefer' (nil=prefer .eln, t=prefer .zeln) picks the
        \\  artifact loaded where a .elc has both a .eln and a .zeln.
        \\  zig build zeln-interop-smoke - end-to-end .eln/.zeln selection gate
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
        \\
    , .{}) catch @panic("OOM");
    const help_step = b.step("help", "Show build information");
    const HelpStep = struct {
        step: std.Build.Step,
        text: []const u8,
        fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
            _ = options;
            const self: *@This() = @fieldParentPtr("step", step);
            std.debug.print("{s}", .{self.text});
            return;
        }
    };
    const hs = b.allocator.create(HelpStep) catch @panic("OOM");
    hs.* = .{
        .step = std.Build.Step.init(.{
            .id = .custom,
            .name = "help-print",
            .owner = b,
            .makeFn = HelpStep.make,
        }),
        .text = helptext,
    };
    help_step.dependOn(&hs.step);
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
        "acl",             "alloca",      "binary-io",       "boot-time",
        "byteswap",        "c-ctype",     "c-str",           "canonicalize",
        "careadlinkat",    "chmodat",     "cloexec",         "close-stream",
        "copy-file-range", "dirent",      "dirfd",           "dtoastr",
        "dtotimespec",     "dup2",        "fallocat",        "fchmodat",
        "fcntl",           "fd-open",     "filemode",        "filename",
        "filevercmp",      "flexmember",  "fpending",        "fingerprint",
        "futimens",        "free",        "fsusage",         "gen_tempname",
        "get-permissions", "getdelim",    "getrandom",       "getline",
        "getprogname",     "hard-locale", "isset",           "issymlink",
        "lstat",           "malloc",      "md5",             "memchr",
        "memcmp",          "memeq",       "memmem",          "memset_explicit",
        "memmove",         "memcpy",      "memrchr",         "mkdir",
        "mkancesdirs",     "mkostemp",    "mktime",          "nanosleep",
        "nproc",           "nstrftime",   "openat-die",      "openat",
        "pathmax",         "pending",     "pipe2",           "pthread",
        "qcopy-acl",       "quotearl",    "read",            "realloc",
        "same",            "save-cwd",    "set-permissions", "sha",
        "sig2str",         "sigdescr_np", "streq",           "stat",
        "stdbit",          "stdc",        "strchr",          "strcmp",
        "strchrnul",       "strcpy",      "strerror",        "strlen",
        "string",          "strncase",    "strndup",         "strnlen",
        "strncmp",         "strnul",      "strto",           "tempname",
        "time",            "timespec",    "u64",             "unsetenv",
        "utimens",         "waitpid",     "wctype",          "xmalloc",
    };
    // Exclusion: substring port of the former `grep -v` list.
    const exclude = [_][]const u8{
        "regex",               "strtoimax",       "strtoumax",
        "printf",              "strftime",        "at-func",
        "dynarray-skeleton",   "ialloca",         "malloc/dynarray",
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
        "futimens",            "utimens",
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
        "stdc_trailing_zeros", "stdc_count_ones", "stdc_bit_width",
        // lib/sha1.c, lib/sha256.c and lib/sha512.c are provided by an
        // independent Zig package (tools/gnulib-hash, dependency
        // `gnulib_hash`) -- native Zig SHA1, SHA-2 (sha224/sha256/
        // sha384/sha512) operating on the gnulib ctx structs. Excluded
        // here so the C sources are not compiled; the package's exported
        // sha1_*/sha256_*/sha512_* symbols are linked into temacs below.
        "sha1",                "sha256",          "sha512",
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
                   "dtotimespec",     "timespec-add",
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
                  "c-strcasecmp",    "c-strncasecmp",
        // lib/qcopy-acl.c, lib/file-has-acl.c, lib/acl-errno-valid.c,
        // lib/acl-internal.c, lib/acl_entries.c, lib/set-permissions.c
        // and lib/get-permissions.c are provided by an independent Zig
        // package (tools/gnulib-acl, dependency `gnulib_acl`) -- native
        // Zig ACL copy (qcopy_acl) with the libattr attr_copy_* xattr
        // semantics and the fdfile_has_aclinfo EOPNOTSUPP diagnostic.
        // Excluded here so the C sources are not compiled; the package's
        // exported qcopy_acl symbol is linked into temacs below
        // (preserve-permissions in Fcopy_file).
        "qcopy-acl",           "file-has-acl",    "acl-errno-valid",
        "acl-internal",        "acl_entries",     "set-permissions",
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
        "timegm",              "mktime",
        // lib/close-stream.c, lib/binary-io.c, lib/pipe2.c are provided
        // by an independent Zig package (tools/gnulib-io, dependency
        // `gnulib_io`) -- native Zig close_stream / set_binary_mode /
        // rpl_pipe2 with libc FILE* delegation and raw Linux pipe/fcntl
        // syscalls. Excluded here so the C sources are not compiled;
        // the package's exported symbols are linked into temacs below
        // (exit-time flush, emacs_pipe, `set-binary-mode').
                 "close-stream",
        "binary-io",           "pipe2",
        // lib/fpending.c, lib/save-cwd.c, lib/md5-stream.c,
        // lib/strnul.c and lib/u64.c are dead in this build: nothing
        // references their symbols any more (their former callers are
        // Zig packages: close_stream now uses glibc's __fpending, and
        // save-cwd/md5-stream/strnul/u64 had no callers at all once
        // at-func, fdopendir, native-comp and the hash/string packages
        // were replaced). Excluded so the C sources are not compiled.
                  "fpending",
        "save-cwd",            "md5-stream",      "strnul",
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

/// Discover gcc's private libgccjit install tree by globbing the standard
/// `/usr/lib/gcc/<triplet>/<version>/` layout at build-config time.  Sets
/// `*out_inc` to the directory holding libgccjit.h (the `<version>/include`
/// subdir) and `*out_lib_dir` to the `<version>` dir itself (where
/// libgccjit.so lives).  Both are left empty if no tree is found (the caller
/// then falls back to the compiler's default search path).  This is the
/// fallback for the compiler's default search path.
/// gcc-host equivalent of `cc -print-file-name=include`/`=libgccjit.so`, done
/// without a subprocess (the single-threaded build Io cannot run one) by
/// iterating the directory tree directly.
fn gccDiscoverGccjit(
    b: *std.Build,
    io: std.Io,
    out_inc: *[]const u8,
    out_lib_dir: *[]const u8,
) void {
    const a = b.allocator;
    var gcc_dir = std.Io.Dir.openDirAbsolute(io, "/usr/lib/gcc", .{ .iterate = true }) catch return;
    defer gcc_dir.close(io);
    var triplet_it = gcc_dir.iterate();
    while (triplet_it.next(io) catch null) |triplet_entry| {
        if (triplet_entry.kind != .directory) continue;
        var triplet_dir = gcc_dir.openDir(io, triplet_entry.name, .{ .iterate = true }) catch continue;
        defer triplet_dir.close(io);
        var version_it = triplet_dir.iterate();
        while (version_it.next(io) catch null) |version_entry| {
            if (version_entry.kind != .directory) continue;
            // Look for <version>/include/libgccjit.h.
            const inc_rel = std.fmt.allocPrint(a, "{s}/include/libgccjit.h", .{version_entry.name}) catch continue;
            if (triplet_dir.access(io, inc_rel, .{})) {
                // Found it.  Record the absolute include + lib dirs.
                out_inc.* = std.fmt.allocPrint(a, "/usr/lib/gcc/{s}/{s}/include", .{ triplet_entry.name, version_entry.name }) catch unreachable;
                out_lib_dir.* = std.fmt.allocPrint(a, "/usr/lib/gcc/{s}/{s}", .{ triplet_entry.name, version_entry.name }) catch unreachable;
                return;
            } else |_| {}
        }
    }
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
