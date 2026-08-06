//! Native Zig replacement for the verify-config shell step in build.zig:
//! assert the generated src/config.h carries the load-bearing knobs.
//! argv[1] is the generated config.h path. No shell.

const std = @import("std");

const checks = [_]struct { pattern: []const u8, line_exact: bool }{
    .{ .pattern = "#ifndef EMACS_CONFIG_H", .line_exact = true },
    .{ .pattern = "#define EMACS_CONFIG_H", .line_exact = true },
    .{ .pattern = "#include <conf_post.h>", .line_exact = true },
    .{ .pattern = "#define SYSTEM_TYPE \"gnu/linux\"", .line_exact = true },
    .{ .pattern = "#define EMACS_CONFIGURATION \"x86_64-pc-linux-gnu\"", .line_exact = true },
    .{ .pattern = "#define HAVE_PDUMPER 1", .line_exact = true },
    .{ .pattern = "#define SYSTEM_MALLOC 1", .line_exact = true },
    .{ .pattern = "#define HAVE_ALSA 1", .line_exact = true },
    .{ .pattern = "#define HAVE_DBUS 1", .line_exact = true },
    .{ .pattern = "#define HAVE_GPM 1", .line_exact = true },
    .{ .pattern = "#define HAVE_INOTIFY 1", .line_exact = true },
    .{ .pattern = "#define HAVE_LIBXML2 1", .line_exact = true },
    .{ .pattern = "#define HAVE_SQLITE3 1", .line_exact = true },
    .{ .pattern = "#define HAVE_LCMS2 1", .line_exact = true },
    .{ .pattern = "#define HAVE_GNUTLS 1", .line_exact = true },
    .{ .pattern = "#define HAVE_TREE_SITTER 1", .line_exact = true },
    .{ .pattern = "#define HAVE_GETRANDOM 1", .line_exact = true },
    .{ .pattern = "GNU_LINUX", .line_exact = false },
    .{ .pattern = "#define DIRECTORY_SEP '/'", .line_exact = true },
    .{ .pattern = "#define SEPCHAR ':'", .line_exact = true },
    .{ .pattern = "/* #undef HAVE_MODULES */", .line_exact = true },
    .{ .pattern = "/* #undef HAVE_NS */", .line_exact = true },
    .{ .pattern = "/* #undef HAVE_ANDROID */", .line_exact = true },
};

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    var it = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer it.deinit();
    _ = it.next();
    const path = it.next() orelse return error.MissingConfigArg;

    const text = try cwd.readFileAlloc(io, path, gpa, .limited(16 * 1024 * 1024));
    defer gpa.free(text);

    for (checks) |c| {
        var found = false;
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            if (c.line_exact) {
                if (std.mem.eql(u8, line, c.pattern)) {
                    found = true;
                    break;
                }
            } else {
                if (std.mem.indexOf(u8, line, c.pattern) != null) {
                    found = true;
                    break;
                }
            }
        }
        if (!found) {
            std.debug.print("verify-config: missing {s}\n", .{c.pattern});
            std.process.exit(1);
        }
    }
    std.debug.print("config.h OK\n", .{});
}
