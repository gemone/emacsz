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
// Run with cwd = repo root. The generated config.h body is written to STDOUT;
// the consumer captures it via captureStdOut and lands it in the zig-cache.
const std = @import("std");

pub fn main() !void {
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();
    const a = std.heap.smp_allocator;
    const cwd = std.Io.Dir.cwd();

    const config_h_in_text = try cwd.readFileAlloc(
        io,
        "src/config.h.in",
        a,
        .limited(4 * 1024 * 1024),
    );
    const config_values_text = try cwd.readFileAlloc(
        io,
        "src/config_values.txt",
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
