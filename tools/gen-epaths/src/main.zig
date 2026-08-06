// Generate epaths.h: build-tree paths so the dumped emacs finds lisp/etc
// under the source tree by default, instead of the nonexistent
// /usr/local/share install dirs the bootstrap src/epaths.h carries. Native
// Zig replacement for the former inline build.zig logic -- mirrors the
// output byte-for-byte so the generated epaths.h stays identical.
//
// Emits ONLY the live non-Android branch (HAVE_ANDROID is undef in config.h,
// so the `#if !defined HAVE_ANDROID` arm is the active one) and defines all
// 11 PATH_* macros so the header is self-contained.
//
// The tool is pure and deterministic: it takes the absolute repo root as
// argv[1] (passed by the consumer via `b.path(".").getPath(b)`) and does NOT
// compute cwd itself. The generated epaths.h body is written to STDOUT; the
// consumer captures it via captureStdOut and lands it in the zig-cache.
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const a = std.heap.smp_allocator;

    // argv[0] = program name, argv[1] = absolute repo root.
    var args_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, a);
    defer args_it.deinit();
    _ = args_it.skip();
    const repo_z = args_it.next() orelse {
        std.debug.print("usage: gen-epaths <repo-root>\n", .{});
        return error.MissingRepoArg;
    };
    const repo: []const u8 = repo_z;

    const path_load = try std.fmt.allocPrint(a, "{s}/lisp", .{repo});
    const path_exec = try std.fmt.allocPrint(a, "{s}/lib-src", .{repo});
    const path_etc = try std.fmt.allocPrint(a, "{s}/etc", .{repo});
    const path_info = try std.fmt.allocPrint(a, "{s}/info", .{repo});

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(a);

    try appendStr(a, &buf, "PATH_LOADSEARCH", path_load);
    try appendStr(a, &buf, "PATH_REL_LOADSEARCH", "32.0.50/lisp");
    // PATH_SITELOADSEARCH is intentionally empty: a non-empty value is
    // prepended to load-path, which would make (car load-path) the
    // site-lisp dir instead of PATH_LOADSEARCH (<repo>/lisp). The build
    // tree has no site-lisp, so empty keeps load-path rooted at
    // <repo>/lisp.
    try appendStr(a, &buf, "PATH_SITELOADSEARCH", "");
    try appendStr(a, &buf, "PATH_DUMPLOADSEARCH", path_load);
    try appendStr(a, &buf, "PATH_EXEC", path_exec);
    try appendStr(a, &buf, "PATH_DATA", path_etc);
    try appendStr(a, &buf, "PATH_BITMAPS", "");
    try appendStr(a, &buf, "PATH_DOC", path_etc);
    try appendStr(a, &buf, "PATH_INFO", path_info);
    try appendRaw(a, &buf, "PATH_GAME", "((char const *) 0)");
    try appendStr(a, &buf, "PATH_X_DEFAULTS", "");

    const stdout_file = std.Io.File.stdout();
    try stdout_file.writeStreamingAll(io, buf.items);
}

/// Append a `#define NAME "VALUE"\n` line to `buf`, for the string-valued
/// epaths.h macros (PATH_LOADSEARCH, PATH_DATA, ...). Mirrors the quoting of
/// the bootstrap src/epaths.h.
fn appendStr(a: std.mem.Allocator, buf: *std.ArrayList(u8), name: []const u8, value: []const u8) !void {
    try buf.appendSlice(a, "#define ");
    try buf.appendSlice(a, name);
    try buf.appendSlice(a, " \"");
    try buf.appendSlice(a, value);
    try buf.appendSlice(a, "\"\n");
}

/// Append a `#define NAME VALUE\n` line (unquoted), for macros whose value is
/// not a string literal: PATH_GAME = ((char const *) 0).
fn appendRaw(a: std.mem.Allocator, buf: *std.ArrayList(u8), name: []const u8, value: []const u8) !void {
    try buf.appendSlice(a, "#define ");
    try buf.appendSlice(a, name);
    try buf.appendSlice(a, " ");
    try buf.appendSlice(a, value);
    try buf.appendSlice(a, "\n");
}
