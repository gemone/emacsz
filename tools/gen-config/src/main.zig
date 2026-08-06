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
    .{ .name = "HAVE_BCRYPT_H", .value = "1" },
    .{ .name = "HAVE_LIB_BCRYPT", .value = "1" },
    .{ .name = "UINTPTR_WIDTH", .value = "64" },
    .{ .name = "UCHAR_WIDTH", .value = "8" },
    .{ .name = "USE_UNLOCKED_IO" },
    .{ .name = "HAVE_DECL_GETC_UNLOCKED" },
    .{ .name = "HAVE_DECL_GETDELIM" },
    .{ .name = "HAVE_DECL_GETLINE" },
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
