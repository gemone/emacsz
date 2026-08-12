//! config-collect: complete DEF (#define / #undef) collection from an
//! autoconf-style config file, driven by a SIMD line scan.
//!
//! Reads a config source (argv[1]): the full autoconf `src/config.in`
//! (the autoheader universe), the lean `src/config.h.in` template, or a
//! generated `config.h`.  Every line whose first non-blank token is
//! `#define` / `#undef` yields its knob name; the complete set is emitted
//! sorted + de-duplicated, one name per line, on STDOUT.
//!
//! This is the "complete DEF collection" counterpart to the probing
//! half of autoconf: config-probe detects the host, gen-config emits
//! config.h, and config-collect measures *which* knobs the template /
//! answer file / output actually contains — so a knob added to the
//! autoheader universe but forgotten in config_values.txt (or vice
//! versa) shows up as a missing/extra name instead of drifting silently.
//!
//! The scan is SIMD: line starts are located with 64-byte `@Vector`
//! equality against '\n' (a movemask + ctz walk), and the `#define` /
//! `#undef` prefix of every line is matched with an 8-byte vector
//! compare — the scalar fallback covers only the under-64-byte tail.
//!
//! Usage: config-collect <config-file>
//! cwd: any; the file is read via its path (argv[1]).

const std = @import("std");

const VEC: comptime_int = 64;
// autotools/gnulib DEF forms, all normalized to "the knob name":
//   `#define NAME ...`, `#undef NAME`            (config.in, template)
//   `      #define NAME ...`                     (indented gnulib scaffold)
//   `# define NAME ...`                          (space after '#')
//   `/* #undef NAME */`                          (config.status output)
// The 8-byte prefixes below are vector-compared on the trimmed line; the
// name is the identifier token that follows the keyword.

const Kind = enum { define, undef };

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t';
}

fn isIdentChar(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or
        (c >= '0' and c <= '9') or c == '_';
}

// SIMD scan: return the index of the next '\n' at-or-after `from`, or
// data.len when there is none.  64-byte chunks are compared as vectors;
// only the trailing remainder falls back to a scalar loop.
fn nextNewline(data: []const u8, from: usize) usize {
    var i = from;
    while (i + VEC <= data.len) : (i += VEC) {
        const v: @Vector(VEC, u8) = data[i..][0..VEC].*;
        const mask: u64 = @bitCast(v == @as(@Vector(VEC, u8), @splat('\n')));
        if (mask != 0) return i + @ctz(mask);
    }
    while (i < data.len) : (i += 1) {
        if (data[i] == '\n') return i;
    }
    return data.len;
}

// Locate the DEF keyword on `line` (after leading whitespace and the '#',
// allowing a space between '#' and the keyword).  Returns the byte offset
// just past the keyword + trailing spaces (where the name starts), or
// null when the line is not a DEF.
fn defNameStart(line: []const u8) ?usize {
    var i: usize = 0;
    while (i < line.len and isSpace(line[i])) i += 1;
    if (i >= line.len) return null;
    if (line[i] == '/') {
        // comment form: `/* #undef NAME */`
        if (std.mem.startsWith(u8, line[i..], "/* #undef "))
            return i + "/* #undef ".len;
        return null;
    }
    if (line[i] != '#') return null;
    i += 1;
    while (i < line.len and isSpace(line[i])) i += 1;
    if (std.mem.startsWith(u8, line[i..], "define ")) {
        i += "define ".len;
    } else if (std.mem.startsWith(u8, line[i..], "undef ")) {
        i += "undef ".len;
    } else {
        return null;
    }
    while (i < line.len and isSpace(line[i])) i += 1;
    return i;
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    var arg_it = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer arg_it.deinit();
    _ = arg_it.next(); // argv[0]
    const path = arg_it.next() orelse return error.MissingConfigPathArg;

    const data = try cwd.readFileAlloc(io, path, gpa, .limited(32 * 1024 * 1024));
    defer gpa.free(data);

    var knobs: std.ArrayList([]const u8) = .empty;
    defer knobs.deinit(gpa);

    // SIMD line walk: for each line, match the DEF keyword and, when it
    // hits, extract the knob name (identifier token).  Names are slices
    // into `data` (alive for the whole run) — no copies.
    var line_start: usize = 0;
    while (line_start <= data.len) {
        const nl = nextNewline(data, line_start);
        const line = data[line_start..nl];
        if (defNameStart(line)) |name_start| {
            var end = name_start;
            while (end < line.len and isIdentChar(line[end])) end += 1;
            if (end > name_start) try knobs.append(gpa, line[name_start..end]);
        }
        if (nl >= data.len) break;
        line_start = nl + 1;
    }

    std.mem.sort([]const u8, knobs.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);

    // De-duplicate (sorted adjacent runs).
    var unique: std.ArrayList([]const u8) = .empty;
    defer unique.deinit(gpa);
    for (knobs.items) |name| {
        if (unique.items.len == 0 or !std.mem.eql(u8, unique.items[unique.items.len - 1], name)) {
            try unique.append(gpa, name);
        }
    }

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    for (unique.items) |name| {
        try buf.appendSlice(gpa, name);
        try buf.append(gpa, '\n');
    }

    const stdout_file = std.Io.File.stdout();
    try stdout_file.writeStreamingAll(io, buf.items);
}
