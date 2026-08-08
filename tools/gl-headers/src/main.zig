// Generate Gnulib .gl.h internal header files. Native Zig replacement for
// the former shell-script generator -- mirrors the sed pipeline
// byte-for-byte so the committed .gl.h files stay identical.
//
// Per file, the applied transform matches the original sed:
//   - Prepend `/* DO NOT EDIT! GENERATED AUTOMATICALLY! */` as line 1
//     (sed `1h;1s,.*,BANNER,;1G`), keeping the original line 1 as line 2.
//   - Drop every line containing `libc_hidden_proto` (dynarray.h,
//     scratch_buffer.h only -- private glibc declarations).
//   - Apply a set of global string rewrites (dynarray-skeleton.c,
//     scratch_buffer.h) renaming glibc-internal spellings to their Gnulib
//     equivalents.
//
// Run with cwd = repo root. The 3 .gl.h outputs land in lib/malloc/
// alongside the tracked sources and are themselves tracked, so
// byte-identical regeneration does not dirty the working tree.
//
// Additionally generates lib/endian.h from lib/endian.in.h with the
// per-target @VAR@ substitution configure performs, so a fresh checkout
// builds without autotools artifacts.  The target tag is passed as
// argv[1] ("macos", "linux", "windows"); without it the build host is
// used.
const std = @import("std");
const builtin = @import("builtin");

const banner = "/* DO NOT EDIT! GENERATED AUTOMATICALLY! */";

const Rewrite = struct { from: []const u8, to: []const u8 };

const Job = struct {
    src: []const u8,
    dst: []const u8,
    rewrites: []const Rewrite,
    drop_libc_hidden_proto: bool,
};

pub fn main(minimal: std.process.Init.Minimal) !void {
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();
    const a = std.heap.smp_allocator;
    const cwd = std.Io.Dir.cwd();

    var arg_it = try std.process.Args.Iterator.initAllocator(minimal.args, a);
    defer arg_it.deinit();
    _ = arg_it.next(); // argv[0]
    const target_tag = arg_it.next() orelse hostTag();

    const jobs = [_]Job{
        .{
            .src = "lib/malloc/dynarray.h",
            .dst = "lib/malloc/dynarray.gl.h",
            .rewrites = &.{},
            .drop_libc_hidden_proto = true,
        },
        .{
            .src = "lib/malloc/dynarray-skeleton.c",
            .dst = "lib/malloc/dynarray-skeleton.gl.h",
            .rewrites = &.{
                .{ .from = "<malloc/dynarray.h>", .to = "<malloc/dynarray.gl.h>" },
                .{ .from = "__attribute_maybe_unused__", .to = "_GL_ATTRIBUTE_MAYBE_UNUSED" },
                .{ .from = "__attribute_nonnull__", .to = "_GL_ATTRIBUTE_NONNULL" },
                .{ .from = "__attribute_warn_unused_result__", .to = "_GL_ATTRIBUTE_NODISCARD" },
                .{ .from = "__glibc_likely", .to = "_GL_LIKELY" },
                .{ .from = "__glibc_unlikely", .to = "_GL_UNLIKELY" },
            },
            .drop_libc_hidden_proto = false,
        },
        .{
            .src = "lib/malloc/scratch_buffer.h",
            .dst = "lib/malloc/scratch_buffer.gl.h",
            .rewrites = &.{
                .{ .from = "__always_inline", .to = "inline _GL_ATTRIBUTE_ALWAYS_INLINE" },
                .{ .from = "__glibc_likely", .to = "_GL_LIKELY" },
                .{ .from = "__glibc_unlikely", .to = "_GL_UNLIKELY" },
            },
            .drop_libc_hidden_proto = true,
        },
    };

    for (jobs) |job| try runOne(io, a, cwd, job);
    try generateEndianH(io, a, cwd, target_tag);
}

/// "macos" for Darwin/BSD, "linux" for glibc/musl, "windows" otherwise.
fn hostTag() []const u8 {
    return switch (builtin.os.tag) {
        .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .openbsd, .netbsd, .dragonfly => "macos",
        .windows => "windows",
        else => "linux",
    };
}

/// Substitute configure's @VAR@ placeholders in lib/endian.in.h and
/// write lib/endian.h, prepending the generated banner.  macOS and the
/// BSDs provide <sys/endian.h> (not <endian.h>); Linux/musl provide
/// <endian.h>; Windows has neither, so the template's byte-order
/// fallback definitions are used.
fn generateEndianH(io: std.Io, a: std.mem.Allocator, cwd: std.Io.Dir, target_tag: []const u8) !void {
    const input = try cwd.readFileAlloc(io, "lib/endian.in.h", a, .limited(8 * 1024 * 1024));
    defer a.free(input);

    const is_linux = std.mem.eql(u8, target_tag, "linux");
    const is_windows = std.mem.eql(u8, target_tag, "windows");
    const have_endian: []const u8 = if (is_linux) "1" else "0";
    const have_sys_endian: []const u8 = if (is_linux or is_windows) "0" else "1";

    const tokens = [_][2][]const u8{
        .{ "@GUARD_PREFIX@", "GL" },
        .{ "@PRAGMA_SYSTEM_HEADER@", "#pragma GCC system_header" },
        .{ "@PRAGMA_COLUMNS@", "" },
        .{ "@HAVE_ENDIAN_H@", have_endian },
        .{ "@INCLUDE_NEXT@", "include_next" },
        .{ "@NEXT_ENDIAN_H@", "<endian.h>" },
        .{ "@HAVE_SYS_ENDIAN_H@", have_sys_endian },
        .{ "@ENDIAN_H_JUST_MISSING_STDINT@", "0" },
    };

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);
    try out.appendSlice(a, banner);
    try out.append(a, '\n');

    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |line0| {
        var line: []u8 = try a.dupe(u8, line0);
        defer a.free(line);
        for (tokens) |tok| {
            if (std.mem.indexOf(u8, line, tok[0]) == null) continue;
            const next = try replaceAll(a, line, tok[0], tok[1]);
            a.free(line);
            line = next;
        }
        try out.appendSlice(a, line);
        try out.append(a, '\n');
    }

    try cwd.writeFile(io, .{ .sub_path = "lib/endian.h", .data = out.items });
}

fn runOne(io: std.Io, a: std.mem.Allocator, cwd: std.Io.Dir, job: Job) !void {
    const input = try cwd.readFileAlloc(io, job.src, a, .limited(8 * 1024 * 1024));
    defer a.free(input);

    // splitScalar on a '\n'-terminated file yields a trailing empty token;
    // drop it so output line count matches sed's (one '\n' per line).
    const ends_with_nl = input.len > 0 and input[input.len - 1] == '\n';
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(a);
    {
        var it = std.mem.splitScalar(u8, input, '\n');
        while (it.next()) |l| try lines.append(a, l);
    }
    if (ends_with_nl and lines.items.len > 0) lines.items.len -= 1;

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);

    for (lines.items, 0..) |line, i| {
        if (i == 0) {
            try out.appendSlice(a, banner);
            try out.append(a, '\n');
        }
        if (job.drop_libc_hidden_proto and std.mem.indexOf(u8, line, "libc_hidden_proto") != null) continue;
        const rewritten = try applyRewrites(a, line, job.rewrites);
        defer a.free(rewritten);
        try out.appendSlice(a, rewritten);
        try out.append(a, '\n');
    }

    // sed preserves the absence of a trailing newline on the final line;
    // since we always emit '\n' after each processed line, strip the last
    // one when the input did not end with '\n'. All current inputs end
    // with '\n', so this is a no-op in practice but keeps the tool honest.
    if (!ends_with_nl and out.items.len > 0 and out.items[out.items.len - 1] == '\n') {
        out.items.len -= 1;
    }

    try cwd.writeFile(io, .{ .sub_path = job.dst, .data = out.items });
}

fn applyRewrites(a: std.mem.Allocator, line: []const u8, rewrites: []const Rewrite) ![]u8 {
    var current: []u8 = try a.dupe(u8, line);
    for (rewrites) |rw| {
        if (std.mem.indexOf(u8, current, rw.from) == null) continue;
        const next = try replaceAll(a, current, rw.from, rw.to);
        a.free(current);
        current = next;
    }
    return current;
}

fn replaceAll(a: std.mem.Allocator, haystack: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    const new_size = std.mem.replacementSize(u8, haystack, needle, replacement);
    const buf = try a.alloc(u8, new_size);
    _ = std.mem.replace(u8, haystack, needle, replacement, buf);
    return buf;
}
