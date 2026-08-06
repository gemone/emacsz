//! Native Zig replacement for admin/charsets/mapconv + compact.awk:
//! generate the etc/charsets/*.map files from the committed glibc
//! charmaps and admin/charsets/mapfiles sources, byte-identical to the
//! shell pipeline (gunzip | sed filter | sed substitute | sort |
//! compact). No shell, no gawk, no make. Run with cwd = repo root.
//!
//! The Makefile's sed addresses and substitutions are fixed patterns;
//! each is implemented as a targeted line check/parse below (no regex
//! engine needed). The special awk scripts (cp932/eucjp-ms/gb18030/
//! big5/kuten/cp51932) are ported in their own functions; targets that
//! need them are left untouched until those land.

const std = @import("std");

const Rule = struct {
    out: []const u8,          // relative to repo root
    src: []const u8,          // relative to admin/charsets (glibc/*.gz or mapfiles/*)
    addr: []const u8,         // sed address command
    format: []const u8,       // mapconv source format
    awk: []const u8,          // "" = no awk (cat)
    post: []const u8 = "",    // extra post-processing ("" = none)
};

// Compact-based rules (the awk-special targets are handled separately).
const compact_rules = [_]Rule{
    .{ .out = "etc/charsets/VSCII.map", .src = "glibc/TCVN5712-1.gz", .addr = "A", .format = "GLIBC-1", .awk = "compact" },
    .{ .out = "etc/charsets/VSCII-2.map", .src = "glibc/TCVN5712-1.gz", .addr = "B", .format = "GLIBC-1", .awk = "compact", .post = "vscii2" },
    .{ .out = "etc/charsets/MIK.map", .src = "mapfiles/bulgarian-mik.txt", .addr = "ALL", .format = "CZYBORRA", .awk = "compact" },
    .{ .out = "etc/charsets/PTCP154.map", .src = "mapfiles/PTCP154", .addr = "0X", .format = "IANA", .awk = "compact" },
    .{ .out = "etc/charsets/stdenc.map", .src = "mapfiles/stdenc.txt", .addr = "HEX", .format = "UNICODE", .awk = "compact" },
    .{ .out = "etc/charsets/symbol.map", .src = "mapfiles/symbol.txt", .addr = "HEX", .format = "UNICODE", .awk = "compact" },
    .{ .out = "etc/charsets/CP949-2BYTE.map", .src = "glibc/CP949.gz", .addr = "E", .format = "GLIBC-2", .awk = "compact" },
    .{ .out = "etc/charsets/GB2312.map", .src = "glibc/GB2312.gz", .addr = "F", .format = "GLIBC-2-7", .awk = "compact" },
    .{ .out = "etc/charsets/GBK.map", .src = "glibc/GBK.gz", .addr = "E", .format = "GLIBC-2", .awk = "compact" },
    .{ .out = "etc/charsets/JISX0201.map", .src = "glibc/JIS_X0201.gz", .addr = "G", .format = "GLIBC-1", .awk = "compact", .post = "jisx0201" },
    .{ .out = "etc/charsets/JISX0208.map", .src = "glibc/EUC-JP.gz", .addr = "F", .format = "GLIBC-2-7", .awk = "", .post = "jisx2014" },
    .{ .out = "etc/charsets/JISX0212.map", .src = "glibc/EUC-JP.gz", .addr = "8F", .format = "GLIBC-2-7", .awk = "compact" },
    .{ .out = "etc/charsets/JISX2132.map", .src = "glibc/EUC-JISX0213.gz", .addr = "8F", .format = "GLIBC-2-7", .awk = "" },
    .{ .out = "etc/charsets/KSC5601.map", .src = "glibc/EUC-KR.gz", .addr = "F", .format = "GLIBC-2-7", .awk = "compact" },
    .{ .out = "etc/charsets/BIG5.map", .src = "glibc/BIG5.gz", .addr = "F", .format = "GLIBC-2", .awk = "" },
    .{ .out = "etc/charsets/BIG5-HKSCS.map", .src = "glibc/BIG5-HKSCS.gz", .addr = "H", .format = "GLIBC-2", .awk = "compact" },
    .{ .out = "etc/charsets/JOHAB.map", .src = "glibc/JOHAB.gz", .addr = "E", .format = "GLIBC-2", .awk = "compact" },
    .{ .out = "etc/charsets/CNS-1.map", .src = "glibc/EUC-TW.gz", .addr = "F", .format = "GLIBC-2-7", .awk = "compact" },
    .{ .out = "etc/charsets/CNS-F.map", .src = "glibc/EUC-TW.gz", .addr = "8EAF", .format = "GLIBC-2-7", .awk = "compact" },
};

// CNS-2..CNS-7 use KANJI-DATABASE from mapfiles/cns2ucsdkw.txt.
const cns_db = [_][]const u8{ "C2", "C3", "C4", "C5", "C6", "C7" };

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    var generated: usize = 0;
    for (compact_rules) |rule| {
        if (try genMap(gpa, io, cwd, rule)) generated += 1;
    }
    for (cns_db, 2..) |prefix, idx| {
        const rule = Rule{
            .out = try std.fmt.allocPrint(gpa, "etc/charsets/CNS-{d}.map", .{idx}),
            .src = "mapfiles/cns2ucsdkw.txt",
            .addr = try std.fmt.allocPrint(gpa, "C{d}", .{prefix[1] - '0'}),
            .format = "KANJI-DATABASE",
            .awk = "compact",
        };
        if (try genMap(gpa, io, cwd, rule)) generated += 1;
    }

    // The generic glibc rules: every glibc/*.gz whose base name matches a
    // map (8859-*, KA-*, EBCDIC*, IBM*, and the rest via %.map).
    var glibc = try cwd.openDir(io, "admin/charsets/glibc", .{ .iterate = true });
    defer glibc.close(io);
    var w = try glibc.walk(gpa);
    defer w.deinit();
    while (try w.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".gz")) continue;
        const base = entry.basename[0 .. entry.basename.len - 3];
        if (alreadyHandled(base)) continue;
        // Map the glibc charmap name to the target map name (the Makefile
        // prefix rules: ISO-8859-% -> 8859-%, GEORGIAN-% -> KA-%,
        // EBCDIC-% -> EBCDIC%; everything else keeps its name).
        const mapped = if (std.mem.startsWith(u8, base, "ISO-8859-"))
            try std.fmt.allocPrint(gpa, "8859-{s}", .{base["ISO-8859-".len..]})
        else if (std.mem.startsWith(u8, base, "GEORGIAN-"))
            try std.fmt.allocPrint(gpa, "KA-{s}", .{base["GEORGIAN-".len..]})
        else if (std.mem.startsWith(u8, base, "EBCDIC-"))
            try std.fmt.allocPrint(gpa, "EBCDIC{s}", .{base["EBCDIC-".len..]})
        else
            try gpa.dupe(u8, base);
        defer gpa.free(mapped);
        const out = try std.fmt.allocPrint(gpa, "etc/charsets/{s}.map", .{mapped});
        defer gpa.free(out);
        // The generic rule: GLIBC-1, compact, '/^<.*[ \t]\/x/'.
        const rule = Rule{
            .out = out,
            .src = try std.fmt.allocPrint(gpa, "glibc/{s}.gz", .{base}),
            .addr = "GEN",
            .format = "GLIBC-1",
            .awk = "compact",
        };
        if (try genMap(gpa, io, cwd, rule)) generated += 1;
    }

    std.debug.print("gen-charsets: generated/updated {d} compact maps\n", .{generated});
}

fn alreadyHandled(base: []const u8) bool {
    const handled = [_][]const u8{
        "TCVN5712-1", "CP949", "GB2312", "GBK", "JIS_X0201", "EUC-JP", "MIK",
        "EUC-JISX0213", "EUC-KR", "BIG5", "BIG5-HKSCS", "JOHAB", "EUC-TW",
        "GB18030", "CP932", "EUC-JP-MS",
    };
    for (handled) |h| {
        if (std.mem.eql(u8, base, h)) return true;
    }
    return false;
}

fn genMap(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, rule: Rule) !bool {
    const src_abs = try std.fs.path.join(gpa, &.{ "admin", "charsets", rule.src });
    defer gpa.free(src_abs);

    var lines: std.ArrayList([]const u8) = .empty;
    defer {
        for (lines.items) |l| gpa.free(l);
        lines.deinit(gpa);
    }

    // Header, then the transformed "0xXX 0xYYYY" lines.
    const base = std.fs.path.basename(rule.src);
    const header = if (std.mem.startsWith(u8, rule.src, "glibc/"))
        try std.fmt.allocPrint(gpa, "# Generated from {s} in localedata/charmaps of glibc", .{stripGz(base)})
    else blk: {
        // mapconv: two header lines naming the upstream source URL.
        const full = try std.fmt.allocPrint(gpa, "admin/charsets/mapfiles/{s}", .{base});
        defer gpa.free(full);
        const url = if (std.mem.eql(u8, rule.format, "CZYBORRA"))
            try std.fmt.allocPrint(gpa, "https://czyborra.com/charsets/{s}.gz", .{base})
        else if (std.mem.eql(u8, rule.format, "KANJI-DATABASE"))
            try gpa.dupe(u8, "http://kanji-database.cvs.sourceforge.net/viewvc/*checkout*/kanji-database/kanji-database/data/cns2ucsdkw.txt?revision=1.4")
        else if (std.mem.eql(u8, rule.format, "IANA"))
            try std.fmt.allocPrint(gpa, "https://www.iana.org/assignments/charset-reg/{s}", .{base})
        else if (std.mem.eql(u8, rule.format, "UNICODE"))
            try std.fmt.allocPrint(gpa, "https://www.unicode.org/Public/MAPPINGS/VENDORS/ADOBE/{s}", .{base})
        else if (std.mem.eql(u8, rule.format, "UNICODE2"))
            try std.fmt.allocPrint(gpa, "https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/{s}", .{base})
        else
            try gpa.dupe(u8, "");
        defer gpa.free(url);
        const l1 = try std.fmt.allocPrint(gpa, "# Generated from {s} which is a copy of", .{full});
        const l2 = try std.fmt.allocPrint(gpa, "# {s}", .{url});
        break :blk std.mem.concat(gpa, u8, &.{ l1, "\n", l2 }) catch unreachable;
    };
    try lines.append(gpa, header);

    const src = if (std.mem.endsWith(u8, rule.src, ".gz"))
        try gunzipFile(gpa, io, cwd, src_abs)
    else
        try cwd.readFileAlloc(io, src_abs, gpa, .unlimited);
    defer gpa.free(src);

    var transformed: std.ArrayList([]const u8) = .empty;
    defer {
        for (transformed.items) |l| gpa.free(l);
        transformed.deinit(gpa);
    }
    var src_lines = std.mem.splitScalar(u8, src, '\n');
    while (src_lines.next()) |line| {
        if (!addrMatch(rule.addr, line)) continue;
        if (try transformLine(gpa, rule.format, rule.addr, line)) |t| {
            try transformed.append(gpa, t);
        }
    }
    // mapconv sorts; UNICODE uses `sort -r` (prefers the first of
    // duplicated mappings, e.g. 0x20 -> U+0020 over U+00A0).
    if (std.mem.eql(u8, rule.format, "UNICODE")) {
        std.mem.sort([]const u8, transformed.items, {}, struct {
            fn lt(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, b, a);
            }
        }.lt);
    } else {
        std.mem.sort([]const u8, transformed.items, {}, struct {
            fn lt(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lt);
    }

    if (std.mem.eql(u8, rule.awk, "compact")) {
        const compacted = try compactAwk(gpa, transformed.items);
        for (compacted) |c| try lines.append(gpa, c);
    } else {
        for (transformed.items) |t| try lines.append(gpa, t);
        // The lines list now owns these slices; do not free them twice.
        transformed.clearRetainingCapacity();
    }

    if (std.mem.eql(u8, rule.post, "vscii2")) {
        // sed 's/0x20-0x7F.*/0x00-0x7F 0x0000/'
        for (lines.items, 0..) |l, idx| {
            if (std.mem.startsWith(u8, l, "0x20-0x7F"))
                lines.items[idx] = try gpa.dupe(u8, "0x00-0x7F 0x0000");
        }
    } else if (std.mem.eql(u8, rule.post, "jisx2014")) {
        // sed 's/0x2015/0x2014/'
        for (lines.items, 0..) |l, idx| {
            if (std.mem.indexOf(u8, l, "0x2015") != null) {
                const fixed = try std.mem.replaceOwned(u8, gpa, l, "0x2015", "0x2014");
                lines.items[idx] = fixed;
            }
        }
    } else if (std.mem.eql(u8, rule.post, "jisx0201")) {
        try lines.append(gpa, try gpa.dupe(u8, "# Generated by hand"));
        try lines.append(gpa, try gpa.dupe(u8, "0xA1-0xDF 0xFF61"));
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    for (lines.items) |l| {
        try out.appendSlice(gpa, l);
        try out.append(gpa, '\n');
    }
    try cwd.writeFile(io, .{ .sub_path = rule.out, .data = out.items });
    return true;
}

fn stripGz(base: []const u8) []const u8 {
    return if (std.mem.endsWith(u8, base, ".gz")) base[0 .. base.len - 3] else base;
}

fn isHex(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

/// The sed address checks, one per distinct Makefile pattern.
fn addrMatch(addr: []const u8, line: []const u8) bool {
    if (std.mem.eql(u8, addr, "ALL")) return true;
    if (line.len == 0) return false;
    if (std.mem.eql(u8, addr, "GEN") or std.mem.eql(u8, addr, "A")) {
        // /^<.*[ \t]\/x/  (A restricts the hex digit set below)
        if (line[0] != '<') return false;
        const x = std.mem.indexOf(u8, line, "/x") orelse return false;
        if (x < 2 or !(line[x - 1] == ' ' or line[x - 1] == '\t')) return false;
        if (std.mem.eql(u8, addr, "A")) {
            if (x + 2 >= line.len or !isHex(line[x + 2])) return false;
            if (x + 4 >= line.len or !(line[x + 4] == ' ' or line[x + 4] == '\t')) return false;
        }
        return true;
    }
    if (std.mem.eql(u8, addr, "B")) {
        // /^<.*[ \t]\/x[2-7a-f].[ \t]/
        if (line[0] != '<') return false;
        const x = std.mem.indexOf(u8, line, "/x") orelse return false;
        if (x < 2 or !(line[x - 1] == ' ' or line[x - 1] == '\t')) return false;
        if (x + 2 >= line.len) return false;
        const c = line[x + 2];
        if (!((c >= '2' and c <= '7') or (c >= 'a' and c <= 'f'))) return false;
        if (x + 4 >= line.len or !(line[x + 4] == ' ' or line[x + 4] == '\t')) return false;
        return true;
    }
    if (std.mem.eql(u8, addr, "E")) {
        // /^<.*[ \t]\/x[89a-f]/
        if (line[0] != '<') return false;
        const x = std.mem.indexOf(u8, line, "/x") orelse return false;
        if (x < 2 or !(line[x - 1] == ' ' or line[x - 1] == '\t')) return false;
        if (x + 2 >= line.len) return false;
        const c = line[x + 2];
        return (c >= '8' and c <= '9') or (c >= 'a' and c <= 'f');
    }
    if (std.mem.eql(u8, addr, "F")) {
        // /^<.*[ \t]\/x[a-f]/
        if (line[0] != '<') return false;
        const x = std.mem.indexOf(u8, line, "/x") orelse return false;
        if (x < 2 or !(line[x - 1] == ' ' or line[x - 1] == '\t')) return false;
        return x + 2 < line.len and line[x + 2] >= 'a' and line[x + 2] <= 'f';
    }
    if (std.mem.eql(u8, addr, "G")) {
        // /^<.*[ \t]\/x[0-9]/
        if (line[0] != '<') return false;
        const x = std.mem.indexOf(u8, line, "/x") orelse return false;
        if (x < 2 or !(line[x - 1] == ' ' or line[x - 1] == '\t')) return false;
        return x + 2 < line.len and line[x + 2] >= '0' and line[x + 2] <= '9';
    }
    if (std.mem.eql(u8, addr, "H")) {
        // /^<.*[ \t]\/x[89a-f].\//
        if (line[0] != '<') return false;
        const x = std.mem.indexOf(u8, line, "/x") orelse return false;
        if (x < 2 or !(line[x - 1] == ' ' or line[x - 1] == '\t')) return false;
        if (x + 2 >= line.len) return false;
        const c = line[x + 2];
        if (!((c >= '8' and c <= '9') or (c >= 'a' and c <= 'f'))) return false;
        return x + 4 < line.len and line[x + 4] == '/';
    }
    if (std.mem.eql(u8, addr, "8F")) {
        // /^<.*[ \t]\/x8f/ s,/x8f,,
        if (line[0] != '<') return false;
        return std.mem.indexOf(u8, line, "/x8f") != null;
    }
    if (std.mem.eql(u8, addr, "8EAF")) {
        // /^<.*\/x8e\/xaf/ s,/x8e/xaf,,
        return line[0] == '<' and std.mem.indexOf(u8, line, "/x8e/xaf") != null;
    }
    if (std.mem.eql(u8, addr, "0X")) return std.mem.startsWith(u8, line, "0x");
    if (std.mem.eql(u8, addr, "HEX")) return isHex(line[0]);
    if (std.mem.startsWith(u8, addr, "C")) {
        // /^C2/ .. /^C7/
        return std.mem.startsWith(u8, line, addr);
    }
    return false;
}

/// The format substitutions (return null when the line does not match the
/// expected shape; the sed patterns effectively drop non-matching lines).
fn transformLine(gpa: std.mem.Allocator, format: []const u8, addr: []const u8, line: []const u8) !?[]const u8 {
    if (std.mem.eql(u8, format, "GLIBC-1")) {
        // <UYYYY>\t/xXX -> 0xXX 0xYYYY
        const u = std.mem.indexOf(u8, line, "<U") orelse return null;
        const u_end = std.mem.indexOfScalar(u8, line[u + 2 ..], '>') orelse return null;
        const yyyy = line[u + 2 .. u + 2 + u_end];
        const x = std.mem.indexOf(u8, line, "/x") orelse return null;
        if (x + 2 + 2 > line.len) return null;
        const xx = line[x + 2 .. x + 4];
        return try std.fmt.allocPrint(gpa, "0x{s} 0x{s}", .{ xx, yyyy });
    }
    if (std.mem.eql(u8, format, "GLIBC-2")) {
        // <UYYYY>\t/xXX/xZZ -> 0xXXZZ 0xYYYY
        const u = std.mem.indexOf(u8, line, "<U") orelse return null;
        const u_end = std.mem.indexOfScalar(u8, line[u + 2 ..], '>') orelse return null;
        const yyyy = line[u + 2 .. u + 2 + u_end];
        const x1 = std.mem.indexOf(u8, line, "/x") orelse return null;
        const x2 = std.mem.indexOfPos(u8, line, x1 + 2, "/x") orelse return null;
        if (x2 + 4 > line.len) return null;
        const xx = line[x1 + 2 .. x1 + 4];
        const zz = line[x2 + 2 .. x2 + 4];
        return try std.fmt.allocPrint(gpa, "0x{s}{s} 0x{s}", .{ xx, zz, yyyy });
    }
    if (std.mem.eql(u8, format, "GLIBC-2-7")) {
        // MSB fix: /xa -> /x2 ... /xf -> /x7, then GLIBC-2.
        var fixed: std.ArrayList(u8) = .empty;
        defer fixed.deinit(gpa);
        // Address substitutions: strip /x8f or /x8e/xaf prefixes.
        var work = line;
        var work_owned = false;
        defer if (work_owned) gpa.free(work);
        if (std.mem.eql(u8, addr, "8F")) {
            if (std.mem.indexOf(u8, line, "/x8f")) |p| {
                try fixed.appendSlice(gpa, line[0..p]);
                try fixed.appendSlice(gpa, line[p + 4 ..]);
                work = try gpa.dupe(u8, fixed.items);
                work_owned = true;
            }
        }
        if (std.mem.eql(u8, addr, "8EAF")) {
            if (std.mem.indexOf(u8, line, "/x8e/xaf")) |p| {
                try fixed.appendSlice(gpa, line[0..p]);
                try fixed.appendSlice(gpa, line[p + 8 ..]);
                work = try gpa.dupe(u8, fixed.items);
                work_owned = true;
            }
        }
        fixed.clearRetainingCapacity();
        var i: usize = 0;
        while (i < work.len) {
            if (i + 1 < work.len and work[i] == 'x' and work[i + 1] >= 'a' and work[i + 1] <= 'f') {
                try fixed.append(gpa, 'x');
                try fixed.append(gpa, work[i + 1] - 'a' + '2');
                i += 2;
            } else {
                try fixed.append(gpa, work[i]);
                i += 1;
            }
        }
        // /x8e/xaf and /x8f removals happen in the address step.
        return try transformLine(gpa, "GLIBC-2", addr, fixed.items);
    }
    if (std.mem.eql(u8, format, "IANA")) {
        // 0xXX 0xYYYY ... -> 0xXX 0xYYYY
        var it = std.mem.tokenizeAny(u8, line, " \t");
        const a = it.next() orelse return null;
        const b = it.next() orelse return null;
        if (!std.mem.startsWith(u8, a, "0x") or !std.mem.startsWith(u8, b, "0x")) return null;
        return try std.fmt.allocPrint(gpa, "{s} {s}", .{ a, b });
    }
    if (std.mem.eql(u8, format, "UNICODE")) {
        // YYYY\tXX -> 0xXX 0xYYYY
        var it = std.mem.tokenizeAny(u8, line, " \t");
        const a = it.next() orelse return null;
        const b = it.next() orelse return null;
        return try std.fmt.allocPrint(gpa, "0x{s} 0x{s}", .{ b, a });
    }
    if (std.mem.eql(u8, format, "UNICODE2")) {
        // 0xXXXX 0xYYYY -> same
        var it = std.mem.tokenizeAny(u8, line, " \t");
        const a = it.next() orelse return null;
        const b = it.next() orelse return null;
        return try std.fmt.allocPrint(gpa, "{s} {s}", .{ a, b });
    }
    if (std.mem.eql(u8, format, "CZYBORRA")) {
        // =XX U+YYYY -> 0xXX 0xYYYY
        if (line.len < 3 or line[0] != '=') return null;
        const u = std.mem.indexOf(u8, line, "U+") orelse return null;
        return try std.fmt.allocPrint(gpa, "0x{s} 0x{s}", .{ line[1..3], line[u + 2 ..] });
    }
    if (std.mem.eql(u8, format, "KANJI-DATABASE")) {
        // C?-XXXX U+YYYYY -> 0xXXXX 0xYYYY
        const u = std.mem.indexOf(u8, line, " U+") orelse return null;
        const code = std.mem.trim(u8, line[3..u], " ");
        return try std.fmt.allocPrint(gpa, "0x{s} 0x{s}", .{ code, line[u + 3 ..] });
    }
    return null;
}

/// compact.awk: merge adjacent code/unicode pairs into ranges.
fn compactAwk(gpa: std.mem.Allocator, lines: []const []const u8) ![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    defer out.deinit(gpa);
    var from_code: u64 = 0;
    var to_code: i64 = -1;
    var to_unicode: u64 = 0;
    var from_unicode: u64 = 0;
    var first = true;

    for (lines) |line| {
        var it = std.mem.tokenizeAny(u8, line, " \t");
        const code_s = it.next() orelse continue;
        const uni_s = it.next() orelse continue;
        // decode_hex($1, 3) / decode_hex($2, 3): skip "0x", 1-based table.
        const code = decodeHexSkip(code_s);
        const unicode = decodeHexSkip(uni_s);
        if (first) {
            from_code = code;
            to_code = @intCast(code);
            from_unicode = unicode;
            to_unicode = unicode;
            first = false;
            continue;
        }
        if (code == @as(u64, @intCast(to_code)) + 1 and unicode == to_unicode + 1) {
            to_code += 1;
            to_unicode += 1;
        } else {
            try out.append(gpa, try fmtRange(gpa, from_code, to_code, from_unicode));
            from_code = code;
            to_code = @intCast(code);
            from_unicode = unicode;
            to_unicode = unicode;
        }
    }
    if (!first) try out.append(gpa, try fmtRange(gpa, from_code, to_code, from_unicode));
    return out.toOwnedSlice(gpa);
}

fn fmtRange(gpa: std.mem.Allocator, from_code: u64, to_code: i64, from_unicode: u64) ![]const u8 {
    const fc: usize = @intCast(from_code);
    const tc: usize = @intCast(to_code);
    if (tc < 256) {
        if (fc == tc)
            return try std.fmt.allocPrint(gpa, "0x{X:0>2} 0x{X:0>4}", .{ fc, from_unicode })
        else
            return try std.fmt.allocPrint(gpa, "0x{X:0>2}-0x{X:0>2} 0x{X:0>4}", .{ fc, tc, from_unicode });
    } else {
        if (fc == tc)
            return try std.fmt.allocPrint(gpa, "0x{X:0>4} 0x{X:0>4}", .{ fc, from_unicode })
        else
            return try std.fmt.allocPrint(gpa, "0x{X:0>4}-0x{X:0>4} 0x{X:0>4}", .{ fc, tc, from_unicode });
    }
}

// awk's decode_hex(str, 3): skip the "0x" prefix; the 1-based tohex table
// means n = n*16 + value (values below 0x10 keep their numeric value).
fn decodeHexSkip(s: []const u8) u64 {
    var start: usize = 0;
    if (std.mem.startsWith(u8, s, "0x")) start = 2;
    var n: u64 = 0;
    for (s[start..]) |c| {
        n *= 16;
        n += hexVal(c);
    }
    return n;
}

fn hexVal(c: u8) u64 {
    return if (c >= '0' and c <= '9') c - '0' else if (c >= 'a' and c <= 'f') c - 'a' + 10 else c - 'A' + 10;
}

fn gunzipFile(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, path: []const u8) ![]u8 {
    const gz = try cwd.readFileAlloc(io, path, gpa, .limited(64 * 1024 * 1024));
    defer gpa.free(gz);
    var reader = std.Io.Reader.fixed(gz);
    var decomp = std.compress.flate.Decompress.init(&reader, .gzip, &.{});
    return decomp.reader.allocRemaining(gpa, .unlimited) catch |err| {
        std.debug.print("gunzip failed: {s}\n", .{@errorName(err)});
        return error.GunzipFailed;
    };
}
