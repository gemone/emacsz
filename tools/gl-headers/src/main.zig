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
const std = @import("std");

const banner = "/* DO NOT EDIT! GENERATED AUTOMATICALLY! */";

const Rewrite = struct { from: []const u8, to: []const u8 };

const Job = struct {
    src: []const u8,
    dst: []const u8,
    rewrites: []const Rewrite,
    drop_libc_hidden_proto: bool,
};

pub fn main() !void {
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();
    const a = std.heap.smp_allocator;
    const cwd = std.Io.Dir.cwd();

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
