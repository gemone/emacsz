//! Native Zig replacement for the config-diff shell step in build.zig:
//! quantify the knob gap between the generated config.h (argv[1]) and
//! the autoconf reference (argv[2], optional). No shell.

const std = @import("std");

fn extractKnobs(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, path: []const u8) ![][]const u8 {
    const text = try cwd.readFileAlloc(io, path, gpa, .limited(16 * 1024 * 1024));
    defer gpa.free(text);
    var knobs: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var name: ?[]const u8 = null;
        if (std.mem.startsWith(u8, line, "#define ") and line.len > 8 and isKnobStart(line[8])) {
            const rest = line[8..];
            const end = knobEnd(rest) orelse rest.len;
            name = rest[0..end];
        } else if (std.mem.startsWith(u8, line, "/* #undef ") and line.len > 11 and line[line.len - 2] == '*' and line[line.len - 1] == '/') {
            const inner = line["/* #undef ".len .. line.len - 2];
            name = std.mem.trim(u8, inner, " \t");
        }
        if (name) |n| {
            if (std.mem.eql(u8, n, "EMACS_CONFIG_H") or std.mem.eql(u8, n, "_GL_CONFIG_H_INCLUDED")) continue;
            try knobs.append(gpa, try gpa.dupe(u8, n));
        }
    }
    return knobs.toOwnedSlice(gpa);
}

fn isKnobStart(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or c == '_';
}

fn knobEnd(s: []const u8) ?usize {
    for (s, 0..) |c, i| {
        if (!((c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_')) return i;
    }
    return s.len;
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    var it = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer it.deinit();
    _ = it.next();
    const gen_path = it.next() orelse return error.MissingArgs;
    const ref_path = it.next() orelse {
        std.debug.print("reference config.h not present; skipping diff\n", .{});
        return;
    };
    if (!fileExists(io, cwd, ref_path)) {
        std.debug.print("reference config.h not present; skipping diff\n", .{});
        return;
    }

    const gen = try extractKnobs(gpa, io, cwd, gen_path);
    defer {
        for (gen) |k| gpa.free(k);
        gpa.free(gen);
    }
    const ref = try extractKnobs(gpa, io, cwd, ref_path);
    defer {
        for (ref) |k| gpa.free(k);
        gpa.free(ref);
    }
    std.mem.sort([]const u8, gen, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    std.mem.sort([]const u8, ref, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);

    var miss: usize = 0;
    var extra: usize = 0;
    var first_missing: ?[]const u8 = null;
    var gi: usize = 0;
    var ri: usize = 0;
    while (gi < gen.len and ri < ref.len) {
        if (std.mem.eql(u8, gen[gi], ref[ri])) {
            gi += 1;
            ri += 1;
        } else if (std.mem.lessThan(u8, gen[gi], ref[ri])) {
            extra += 1;
            gi += 1;
        } else {
            miss += 1;
            if (first_missing == null) first_missing = ref[ri];
            ri += 1;
        }
    }
    miss += ref.len - ri;
    extra += gen.len - gi;

    std.debug.print("generated: {d} knobs\n", .{gen.len});
    std.debug.print("reference: {d} knobs\n", .{ref.len});
    std.debug.print("missing: {d}\n", .{miss});
    std.debug.print("extra: {d}\n", .{extra});
    std.debug.print("--- first missing ---\n", .{});
    if (first_missing) |fm| std.debug.print("{s}\n", .{fm});
}

fn fileExists(io: std.Io, cwd: std.Io.Dir, path: []const u8) bool {
    var f = cwd.openFile(io, path, .{}) catch return false;
    f.close(io);
    return true;
}
