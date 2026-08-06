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

    // Special awk-based targets.
    try genCp932(gpa, io, cwd);
    try genCp51932(gpa, io, cwd);
    try genEucjpMs(gpa, io, cwd);
    try genGb180302(gpa, io, cwd);
    try genGb180304(gpa, io, cwd);
    try genJisc6226(gpa, io, cwd);
    try genJisx2131(gpa, io, cwd);

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

    // These read maps produced above (BIG5.map from the compact rules,
    // IBM866.map from the glibc walk), so they must run after the
    // generators. The original order worked only where stale outputs
    // already existed in etc/charsets/.
    try genBig5(gpa, io, cwd);
    try genAlternativnyj(gpa, io, cwd);

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
    // awk's tohex table is empty for invalid characters -> 0.
    return if (c >= '0' and c <= '9') c - '0' else if (c >= 'a' and c <= 'f') c - 'a' + 10 else if (c >= 'A' and c <= 'F') c - 'A' + 10 else 0;
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

fn writeOut(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir, path: []const u8, lines: []const []const u8) !void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    for (lines) |l| {
        try out.appendSlice(gpa, l);
        try out.append(gpa, '\n');
    }
    try cwd.writeFile(io, .{ .sub_path = path, .data = out.items });
}

// ---------------------------------------------------------------------
// cp932.awk -> CP932-2BYTE.map (from mapfiles/CP932.TXT)
// ---------------------------------------------------------------------
fn genCp932(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir) !void {
    const src = try cwd.readFileAlloc(io, "admin/charsets/mapfiles/CP932.TXT", gpa, .unlimited);
    defer gpa.free(src);

    const Keyed = struct { key: u64, line: []const u8 };
    var keyed: std.ArrayList(Keyed) = .empty;
    defer {
        for (keyed.items) |k| gpa.free(k.line);
        keyed.deinit(gpa);
    }
    var src_lines = std.mem.splitScalar(u8, src, '\n');
    while (src_lines.next()) |line| {
        // mapconv UNICODE2 filter /^0x[89A-F][0-9A-F][0-9A-F]/ + transform.
        if (line.len < 4 or !std.mem.startsWith(u8, line, "0x")) continue;
        const c3 = line[2];
        if (!((c3 >= '8' and c3 <= '9') or (c3 >= 'A' and c3 <= 'F'))) continue;
        if (line.len < 7 or !isHex(line[3]) or !isHex(line[4]) or !isHex(line[5])) continue;
        var it = std.mem.tokenizeAny(u8, line, " \t");
        const code_s = it.next() orelse continue;
        const uni_s = it.next() orelse continue;
        const sjis = decodeHexSkip(code_s);
        var out_line: []const u8 = undefined;
        if (code_s[2] == '8' or code_s[2] == '9' or code_s[2] == 'E') {
            const ku = sjisToJisKu(sjis);
            const tag: []const u8 = if (ku.ku == 13) "1" else if (ku.ku >= 89 and ku.ku <= 92) "3" else "0";
            out_line = try std.fmt.allocPrint(gpa, "{s} {s} # {s} {X:0>2}{X:0>2}", .{ code_s, uni_s, tag, ku.j1, ku.j2 });
            try keyed.append(gpa, .{ .key = if (std.mem.eql(u8, tag, "1")) 1 else if (std.mem.eql(u8, tag, "3")) 3 else 0, .line = out_line });
        } else if (code_s[2] == 'F') {
            out_line = try std.fmt.allocPrint(gpa, "{s} {s} # 2", .{ code_s, uni_s });
            try keyed.append(gpa, .{ .key = 2, .line = out_line });
        } else {
            out_line = try std.fmt.allocPrint(gpa, "{s} {s}", .{ code_s, uni_s });
            try keyed.append(gpa, .{ .key = 0, .line = out_line });
        }
    }

    // User-defined area (END of cp932.awk).
    var code: u64 = 57344;
    var i: u32 = 240;
    while (i < 250) : (i += 1) {
        var j: u32 = 64;
        while (j <= 126) : (j += 1) {
            const l = try std.fmt.allocPrint(gpa, "0x{X:0>2}{X:0>2} 0x{X:0>4} # 4", .{ i, j, code });
            code += 1;
            try keyed.append(gpa, .{ .key = 4, .line = l });
        }
        j = 128;
        while (j <= 158) : (j += 1) {
            const l = try std.fmt.allocPrint(gpa, "0x{X:0>2}{X:0>2} 0x{X:0>4} # 4", .{ i, j, code });
            code += 1;
            try keyed.append(gpa, .{ .key = 4, .line = l });
        }
        while (j <= 252) : (j += 1) {
            const l = try std.fmt.allocPrint(gpa, "0x{X:0>2}{X:0>2} 0x{X:0>4} # 4", .{ i, j, code });
            code += 1;
            try keyed.append(gpa, .{ .key = 4, .line = l });
        }
    }

    // mapconv UNICODE2 pipes through `sort -n -k 4,4` (stable; ties keep
    // input order).
    std.mem.sort(Keyed, keyed.items, {}, struct {
        fn lt(_: void, a: Keyed, b: Keyed) bool {
            return a.key < b.key;
        }
    }.lt);

    var out: std.ArrayList([]const u8) = .empty;
    defer out.deinit(gpa);
    try out.append(gpa, "# Generated from admin/charsets/mapfiles/CP932.TXT which is a copy of");
    try out.append(gpa, "# https://www.unicode.org/Public/MAPPINGS/VENDORS/MICSFT/WINDOWS/CP932.TXT");
    for (keyed.items) |k| try out.append(gpa, k.line);
    try writeOut(gpa, io, cwd, "etc/charsets/CP932-2BYTE.map", out.items);
}

const JisKu = struct { ku: u64, j1: u64, j2: u64 };

fn sjisToJisKu(code: u64) JisKu {
    const s1 = code / 256;
    const s2 = code % 256;
    var j1: u64 = undefined;
    var j2: u64 = undefined;
    if (s2 >= 159) {
        j1 = if (s1 >= 224) s1 * 2 - 352 else s1 * 2 - 224;
        j2 = s2 - 126;
    } else {
        j1 = if (s1 >= 224) s1 * 2 - 353 else s1 * 2 - 225;
        j2 = if (s2 >= 127) s2 - 32 else s2 - 31;
    }
    return .{ .ku = j1 - 32, .j1 = j1, .j2 = j2 };
}

// ---------------------------------------------------------------------
// cp51932.awk -> lisp/international/cp51932.el (from CP932-2BYTE.map)
// ---------------------------------------------------------------------
fn genCp51932(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir) !void {
    const src = try cwd.readFileAlloc(io, "etc/charsets/CP932-2BYTE.map", gpa, .unlimited);
    defer gpa.free(src);
    var raw: std.ArrayList(u8) = .empty;
    defer raw.deinit(gpa);
    try raw.appendSlice(gpa, ";;; cp51932.el -- translation table for CP51932  -*- lexical-binding:t -*-\n");
    try raw.appendSlice(gpa, ";;; Automatically generated from CP932-2BYTE.map\n");
    try raw.appendSlice(gpa, "(let ((map\n");
    try raw.appendSlice(gpa, "       '(;JISEXT<->UNICODE"); // printf: no newline
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| {
        // /# [13]/
        const m = std.mem.indexOf(u8, line, " # ") orelse continue;
        const key = line[m + 3 ..];
        if (!(std.mem.startsWith(u8, key, "1") or std.mem.startsWith(u8, key, "3"))) continue;
        var it = std.mem.tokenizeAny(u8, line, " \t");
        _ = it.next(); // 0xXXXX
        const uni = it.next() orelse continue;
        _ = it.next(); // #
        _ = it.next();
        const jis_code = it.next() orelse continue; // $5: the JIS ku-ten
        try raw.appendSlice(gpa, "\n\t (#x");
        try raw.appendSlice(gpa, jis_code);
        try raw.appendSlice(gpa, " . #x");
        try raw.appendSlice(gpa, uni[2..]);
        try raw.appendSlice(gpa, ")");
    }
    try raw.appendSlice(gpa, ")))\n");
    try raw.appendSlice(gpa, "  (setq map (mapcar (lambda (x)\n");
    try raw.appendSlice(gpa, "\t\t      (cons (decode-char 'japanese-jisx0208 (car x))\n");
    try raw.appendSlice(gpa, "\t\t\t    (cdr x)))\n");
    try raw.appendSlice(gpa, "\t\t    map))\n");
    try raw.appendSlice(gpa, "  (define-translation-table 'cp51932-decode map)\n");
    try raw.appendSlice(gpa, "  (mapc (lambda (x)\n");
    try raw.appendSlice(gpa, "\t  (let ((tmp (car x)))\n");
    try raw.appendSlice(gpa, "\t    (setcar x (cdr x)) (setcdr x tmp)))\n");
    try raw.appendSlice(gpa, "\tmap)\n");
    try raw.appendSlice(gpa, "  (define-translation-table 'cp51932-encode map))\n");
    try raw.appendSlice(gpa, "\n");
    try raw.appendSlice(gpa, "(provide 'cp51932)\n");
    try cwd.writeFile(io, .{ .sub_path = "lisp/international/cp51932.el", .data = raw.items });
}

// ---------------------------------------------------------------------
// eucjp-ms.awk -> lisp/international/eucjp-ms.el (from glibc/EUC-JP-MS.gz)
// ---------------------------------------------------------------------
fn genEucjpMs(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir) !void {
    const src = try gunzipFile(gpa, io, cwd, "admin/charsets/glibc/EUC-JP-MS.gz");
    defer gpa.free(src);
    var raw: std.ArrayList(u8) = .empty;
    defer raw.deinit(gpa);
    try raw.appendSlice(gpa, ";;; eucjp-ms.el --- translation table for eucJP-ms  -*- lexical-binding:t -*-\n");
    try raw.appendSlice(gpa, ";;; Automatically generated from /usr/share/i18n/charmaps/EUC-JP-MS.gz\n");
    try raw.appendSlice(gpa, "(let ((map\n");
    try raw.appendSlice(gpa, "       '(;JISEXT<->UNICODE\n"); // print: with newline (blank line before first entry)

    var state: u32 = 0;
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "% JIS X 0208")) {
            state = 1;
            continue;
        }
        if (std.mem.startsWith(u8, line, "% JIS X 0212")) {
            state = 3;
            continue;
        }
        if (std.mem.startsWith(u8, line, "END CHARMAP")) {
            state = 0;
            continue;
        }
        var unicode: ?[]const u8 = null;
        if (std.mem.startsWith(u8, line, "<U") and line.len > 6 and isHex(line[2]) and isHex(line[3]) and isHex(line[4]) and isHex(line[5]) and line[6] == '>') {
            unicode = line[2..6];
        } else if (std.mem.startsWith(u8, line, "%IRREVERSIBLE%<U") and line.len > 20) {
            unicode = line[16..20];
        }
        if (unicode == null or state == 0) continue;
        var it = std.mem.tokenizeAny(u8, line, " \t");
        _ = it.next();
        const code = it.next() orelse continue;
        if (state == 1 and (std.mem.eql(u8, code, "/xad/xa1") or std.mem.eql(u8, code, "/xf5/xa1"))) {
            state = 2;
        } else if (state == 3 and std.mem.eql(u8, code, "/x8f/xf3/xf3")) {
            state = 4;
        }
        if (state == 2) {
            var jis: std.ArrayList(u8) = .empty;
            defer jis.deinit(gpa);
            var i: usize = 0;
            while (i < code.len) {
                if (std.mem.startsWith(u8, code[i..], "/x")) {
                    i += 2;
                } else {
                    try jis.append(gpa, code[i]);
                    i += 1;
                }
            }
            try raw.appendSlice(gpa, "\n\t (#x");
            try raw.appendSlice(gpa, jis.items);
            try raw.appendSlice(gpa, " . #x");
            try raw.appendSlice(gpa, unicode.?);
            try raw.appendSlice(gpa, ")");
            if (std.mem.eql(u8, code, "/xad/xfc")) state = 1;
        } else if (state == 4) {
            const body = code[4..]; // skip "/x8f" (4 chars)
            var jis: std.ArrayList(u8) = .empty;
            defer jis.deinit(gpa);
            var i: usize = 0;
            while (i < body.len) {
                if (std.mem.startsWith(u8, body[i..], "/x")) {
                    i += 2;
                } else {
                    try jis.append(gpa, body[i]);
                    i += 1;
                }
            }
            try raw.appendSlice(gpa, "\n\t (#x");
            try raw.appendSlice(gpa, jis.items);
            try raw.appendSlice(gpa, " #x");
            try raw.appendSlice(gpa, unicode.?);
            try raw.appendSlice(gpa, ")");
        }
    }
    try raw.appendSlice(gpa, ")))\n");
    try raw.appendSlice(gpa, "  (setq map\n");
    try raw.appendSlice(gpa, "    (mapcar\n");
    try raw.appendSlice(gpa, "\t(lambda (x)\n");
    try raw.appendSlice(gpa, "\t    (let ((code (logand (car x) #x7F7F)))\n");
    try raw.appendSlice(gpa, "\t      (if (integerp (cdr x))\n");
    try raw.appendSlice(gpa, "\t\t  (cons (decode-char 'japanese-jisx0208 code) (cdr x))\n");
    try raw.appendSlice(gpa, "\t\t(cons (decode-char 'japanese-jisx0212 code)\n");
    try raw.appendSlice(gpa, "\t\t      (cadr x)))))\n");
    try raw.appendSlice(gpa, "\tmap))\n");
    try raw.appendSlice(gpa, "  (define-translation-table 'eucjp-ms-decode map)\n");
    try raw.appendSlice(gpa, "  (mapc (lambda (x)\n");
    try raw.appendSlice(gpa, "\t    (let ((tmp (car x)))\n");
    try raw.appendSlice(gpa, "\t      (setcar x (cdr x)) (setcdr x tmp)))\n");
    try raw.appendSlice(gpa, "\tmap)\n");
    try raw.appendSlice(gpa, "  (define-translation-table 'eucjp-ms-encode map))\n");
    try raw.appendSlice(gpa, "\n");
    try raw.appendSlice(gpa, "(provide 'eucjp-ms)\n");
    try cwd.writeFile(io, .{ .sub_path = "lisp/international/eucjp-ms.el", .data = raw.items });
}

// ---------------------------------------------------------------------
// gb180302.awk -> GB180302.map (from glibc/GB18030.gz)
// ---------------------------------------------------------------------
fn genGb180302(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir) !void {
    const src = try gunzipFile(gpa, io, cwd, "admin/charsets/glibc/GB18030.gz");
    defer gpa.free(src);
    const Pair = struct { gb: i64, unicode: u64 };
    var pairs: std.ArrayList(Pair) = .empty;
    defer pairs.deinit(gpa);
    var src_lines = std.mem.splitScalar(u8, src, '\n');
    while (src_lines.next()) |line| {
        // addr /^<.*[ \t]\/x..\/x..[ \t]/ + GLIBC-2 transform.
        if (line.len == 0 or line[0] != '<') continue;
        const u = std.mem.indexOf(u8, line, "<U") orelse continue;
        const u_end = std.mem.indexOfScalar(u8, line[u + 2 ..], '>') orelse continue;
        const yyyy = line[u + 2 .. u + 2 + u_end];
        const x1 = std.mem.indexOf(u8, line, "/x") orelse continue;
        const x2 = std.mem.indexOfPos(u8, line, x1 + 2, "/x") orelse continue;
        // The address requires a space/tab after the second /x; a third
        // /x (4-byte GB18030 code) or end-of-line does not match.
        if (x2 + 4 >= line.len) continue;
        if (!(line[x2 + 4] == ' ' or line[x2 + 4] == '\t')) continue;
        const code = try std.fmt.allocPrint(gpa, "{s}{s}", .{ line[x1 + 2 .. x1 + 4], line[x2 + 2 .. x2 + 4] });
        defer gpa.free(code);
        try pairs.append(gpa, .{ .gb = gbToIndex(decodeHexSkip(code)), .unicode = decodeHexSkip(yyyy) });
    }
    // sort ascending by (gb, unicode) — mapconv sorts the transformed lines.
    std.mem.sort(Pair, pairs.items, {}, struct {
        fn lt(_: void, a: Pair, b: Pair) bool {
            if (a.gb != b.gb) return a.gb < b.gb;
            return a.unicode < b.unicode;
        }
    }.lt);

    var out: std.ArrayList([]const u8) = .empty;
    defer out.deinit(gpa);
    try out.append(gpa, "# Generated from GB18030 in localedata/charmaps of glibc");
    var from_gb: i64 = 0;
    var to_gb: i64 = -1;
    var from_unicode: u64 = 0;
    var to_unicode: u64 = 0;
    var first = true;
    for (pairs.items) |p| {
        if (first) {
            from_gb = p.gb;
            to_gb = p.gb;
            from_unicode = p.unicode;
            to_unicode = p.unicode;
            first = false;
            continue;
        }
        if (p.gb == to_gb + 1 and p.unicode == to_unicode + 1) {
            to_gb += 1;
            to_unicode += 1;
        } else if (p.gb > to_gb) {
            try out.append(gpa, try fmtGbRange(gpa, from_gb, to_gb, from_unicode));
            from_gb = p.gb;
            to_gb = p.gb;
            from_unicode = p.unicode;
            to_unicode = p.unicode;
        }
    }
    if (!first) try out.append(gpa, try fmtGbRange(gpa, from_gb, to_gb, from_unicode));
    try writeOut(gpa, io, cwd, "etc/charsets/GB180302.map", out.items);
}

fn gbToIndex(gb: u64) i64 {
    const b0: i64 = @intCast(gb / 256);
    const b1: i64 = @intCast(gb % 256);
    return (b0 - 129) * 191 + b1 - 64;
}

fn indexToGb(idx: i64) u64 {
    const b0: u64 = @intCast(@divTrunc(idx, 191) + 129);
    const b1: u64 = @intCast(@rem(idx, 191) + 64);
    return b0 * 256 + b1;
}

fn fmtGbRange(gpa: std.mem.Allocator, from_gb: i64, to_gb: i64, from_unicode: u64) ![]const u8 {
    const fg = indexToGb(from_gb);
    const tg = indexToGb(to_gb);
    if (from_unicode <= 65535) {
        if (from_gb == to_gb)
            return try std.fmt.allocPrint(gpa, "0x{X:0>4} 0x{X:0>4}", .{ fg, from_unicode });
        return try std.fmt.allocPrint(gpa, "0x{X:0>4}-0x{X:0>4} 0x{X:0>4}", .{ fg, tg, from_unicode });
    } else {
        if (from_gb == to_gb)
            return try std.fmt.allocPrint(gpa, "0x{X:0>4} 0x{X:0>8}", .{ fg, from_unicode });
        return try std.fmt.allocPrint(gpa, "0x{X:0>4}-0x{X:0>4} 0x{X:0>8}", .{ fg, tg, from_unicode });
    }
}

// ---------------------------------------------------------------------
// gb180304.awk -> GB180304.map (from GB180302.map)
// ---------------------------------------------------------------------
fn genGb180304(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir) !void {
    const src = try cwd.readFileAlloc(io, "etc/charsets/GB180302.map", gpa, .unlimited);
    defer gpa.free(src);
    var table: [65537]bool = [_]bool{false} ** 65537;
    table[65536] = true;
    var header: ?[]const u8 = null;
    var src_lines = std.mem.splitScalar(u8, src, '\n');
    while (src_lines.next()) |line| {
        if (line.len == 0) continue;
        if (line[0] == '#') {
            if (header == null) header = line;
            continue;
        }
        var it = std.mem.tokenizeAny(u8, line, " \t");
        const a = it.next() orelse continue;
        const b = it.next() orelse continue;
        // awk reads substr($2, 3, 4): the first four hex digits after 0x.
        const b4 = if (std.mem.startsWith(u8, b, "0x") and b.len >= 6) b[2..6] else b;
        if (std.mem.indexOf(u8, a, "-")) |dash| {
            const gb_from = gbToIndex(decodeHexSkip(a[0..dash]));
            const gb_to = gbToIndex(decodeHexSkip(a[dash + 1 ..]));
            const unicode = decodeHexSkip(b4);
            var gi = gb_from;
            while (gi <= gb_to) : (gi += 1) {
                table[unicode + @as(u64, @intCast(gi - gb_from))] = true;
            }
        } else {
            const gb = gbToIndex(decodeHexSkip(a));
            const unicode = decodeHexSkip(b4);
            _ = gb;
            table[unicode] = true;
        }
    }

    var out: std.ArrayList([]const u8) = .empty;
    defer out.deinit(gpa);
    if (header) |h| try out.append(gpa, try gpa.dupe(u8, h));
    var from_gb: i64 = -1;
    var to_gb: i64 = 0;
    var from_i: u64 = 0;
    var i: usize = 128;
    while (i <= 65536) : (i += 1) {
        if (!table[i]) {
            if (i < 55296 or i >= 57344) {
                if (from_gb < 0) {
                    from_gb = to_gb;
                    from_i = i;
                }
                to_gb += 1;
            }
        } else if (from_gb >= 0) {
            const s1 = try indexToGbStr(gpa, @intCast(from_gb));
            const s2 = try indexToGbStr(gpa, @intCast(to_gb - 1));
            const l = if (from_gb + 1 == to_gb)
                try std.fmt.allocPrint(gpa, "0x{s}\t\t0x{X:0>4}", .{ s1, from_i })
            else
                try std.fmt.allocPrint(gpa, "0x{s}-0x{s}\t0x{X:0>4}", .{ s1, s2, from_i });
            try out.append(gpa, l);
            from_gb = -1;
        }
    }
    try writeOut(gpa, io, cwd, "etc/charsets/GB180304.map", out.items);
}

// The 4-byte GB18030 encoding: b3 = idx%10+48, b2 = (idx/10)%126+129,
// b1 = (idx/1260)%10+48, b0 = idx/12600+129.
fn indexToGbStr(gpa: std.mem.Allocator, idx: u64) ![]const u8 {
    const b3 = idx % 10 + 48;
    var rem = idx / 10;
    const b2 = rem % 126 + 129;
    rem /= 126;
    const b1 = rem % 10 + 48;
    const b0 = rem / 10 + 129;
    return try std.fmt.allocPrint(gpa, "{X:0>2}{X:0>2}{X:0>2}{X:0>2}", .{ b0, b1, b2, b3 });
}

// ---------------------------------------------------------------------
// big5.awk -> BIG5-1.map / BIG5-2.map (from BIG5.map)
// ---------------------------------------------------------------------
fn genBig5(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir) !void {
    const src = try cwd.readFileAlloc(io, "etc/charsets/BIG5.map", gpa, .unlimited);
    defer gpa.free(src);

    // BIG5-1: sed range /0xa140/,/0xc8fe/; BIG5-2: /0xc940/,$.
    const ranges = [_]struct { name: []const u8, start: []const u8, end: ?[]const u8 }{
        .{ .name = "BIG5-1", .start = "0xa140", .end = "0xc8fe" },
        .{ .name = "BIG5-2", .start = "0xc940", .end = null },
    };
    // Re-read with proper range filtering.
    for (ranges) |r| {
        var out: std.ArrayList([]const u8) = .empty;
        defer out.deinit(gpa);
        try out.append(gpa, try std.fmt.allocPrint(gpa, "# Generated from {s}", .{"BIG5.map"}));
        var in_range = false;
        var lines2 = std.mem.splitScalar(u8, src, '\n');
        while (lines2.next()) |line| {
            if (line.len < 6 or !std.mem.startsWith(u8, line, "0x")) continue;
            const code = line[0..6];
            if (std.mem.eql(u8, code, r.start)) in_range = true;
            if (!in_range) continue;
            var it = std.mem.tokenizeAny(u8, line, " \t");
            const a = it.next() orelse continue;
            const b = it.next() orelse continue;
            const big5 = decodeHexSkip(a);
            const out_code = decodeBig5(big5);
            const l = try std.fmt.allocPrint(gpa, "0x{X:0>4} {s}", .{ out_code, b });
            try out.append(gpa, l);
            if (r.end != null and std.mem.eql(u8, code, r.end.?)) break;
        }
        try writeOut(gpa, io, cwd, try std.fmt.allocPrint(gpa, "etc/charsets/{s}.map", .{r.name}), out.items);
    }
}

fn decodeBig5(big5: u64) u64 {
    const b0: i64 = @intCast(big5 / 256);
    const b1: i64 = @intCast(big5 % 256);
    var idx: i64 = if (b1 < 127) (b0 - 161) * 157 + (b1 - 64) else (b0 - 161) * 157 + (b1 - 98);
    if (b0 >= 201) idx -= 6280;
    const nb0 = @as(u64, @intCast(@divTrunc(idx, 94))) + 33;
    const nb1 = @as(u64, @intCast(@rem(idx, 94))) + 33;
    return nb0 * 256 + nb1;
}

// ---------------------------------------------------------------------
// kuten.awk + YASUOKA -> JISC6226.map (from mapfiles/Uni2JIS)
// ---------------------------------------------------------------------
fn genJisc6226(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir) !void {
    const src = try cwd.readFileAlloc(io, "admin/charsets/mapfiles/Uni2JIS", gpa, .unlimited);
    defer gpa.free(src);
    var out: std.ArrayList([]const u8) = .empty;
    defer out.deinit(gpa);
    try out.append(gpa, "# Generated from admin/charsets/mapfiles/Uni2JIS which is a copy of");
    try out.append(gpa, "# http://kanji.zinbun.kyoto-u.ac.jp/~yasuoka/ftp/CJKtable/Uni2JIS.Z");
    const Kuten = struct { kuten: []const u8, unicode: []const u8 };
    var pairs: std.ArrayList(Kuten) = .empty;
    defer {
        for (pairs.items) |p| gpa.free(p.kuten);
        pairs.deinit(gpa);
    }
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        const dash = std.mem.indexOf(u8, line, "0-") orelse continue;
        // YASUOKA: "YYYY 0-XXXX" -> "0xXXXX 0xYYYY"; kuten.awk converts.
        const yyyy = std.mem.trim(u8, line[0..dash], " \t");
        const kuten = std.mem.trim(u8, line[dash + 2 ..], " \t");
        if (kuten.len < 4) continue;
        try pairs.append(gpa, .{ .kuten = try gpa.dupe(u8, kuten), .unicode = try gpa.dupe(u8, yyyy) });
    }
    // mapconv sorts the transformed lines before kuten.awk.
    std.mem.sort(Kuten, pairs.items, {}, struct {
        fn lt(_: void, a: Kuten, b: Kuten) bool {
            return std.mem.lessThan(u8, a.kuten, b.kuten);
        }
    }.lt);
    for (pairs.items) |p| {
        const kuten = p.kuten;
        const yyyy = p.unicode;
        const ku = parseDec(kuten[0..2]) + 32;
        const ten = parseDec(kuten[2..4]) + 32;
        const l = try std.fmt.allocPrint(gpa, "0x{X:0>2}{X:0>2} 0x{s}", .{ ku, ten, yyyy });
        try out.append(gpa, l);
    }
    // sed '/0x2140/s/005C/FF3C/'
    for (out.items, 0..) |l, idx| {
        if (std.mem.startsWith(u8, l, "0x2140") and std.mem.indexOf(u8, l, "005C") != null) {
            out.items[idx] = try gpa.dupe(u8, std.mem.replaceOwned(u8, gpa, l, "005C", "FF3C") catch unreachable);
        }
    }
    try out.append(gpa, "0x3442 0x3D4E");
    try out.append(gpa, "0x374E 0x25874");
    try out.append(gpa, "0x3764 0x28EF6");
    try out.append(gpa, "0x513D 0x2F80F");
    try out.append(gpa, "0x7045 0x9724");
    try writeOut(gpa, io, cwd, "etc/charsets/JISC6226.map", out.items);
}

fn parseDec(s: []const u8) u64 {
    var n: u64 = 0;
    for (s) |c| {
        n = n * 10 + (c - '0');
    }
    return n;
}

// ---------------------------------------------------------------------
// JISX2131.map: GLIBC-2-7 + the sed script filter from JISX213A.map
// ---------------------------------------------------------------------
fn genJisx2131(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir) !void {
    // Build the filter: for each non-# line of JISX213A.map, drop lines
    // whose Unicode (leading zeros stripped) matches.
    const jisxa = try cwd.readFileAlloc(io, "admin/charsets/mapfiles/JISX213A.map", gpa, .unlimited);
    defer gpa.free(jisxa);
    var drop: std.ArrayList(u64) = .empty;
    defer drop.deinit(gpa);
    var ja = std.mem.splitScalar(u8, jisxa, '\n');
    while (ja.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        var it = std.mem.tokenizeAny(u8, line, " \t");
        _ = it.next();
        const u = it.next() orelse continue;
        if (std.mem.startsWith(u8, u, "0x")) {
            try drop.append(gpa, decodeHexSkip(u));
        }
    }

    const src = try gunzipFile(gpa, io, cwd, "admin/charsets/glibc/EUC-JISX0213.gz");
    defer gpa.free(src);
    var out: std.ArrayList([]const u8) = .empty;
    defer out.deinit(gpa);
    try out.append(gpa, "# Generated from EUC-JISX0213 in localedata/charmaps of glibc");
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| {
        if (!addrMatch("F", line)) continue;
        const t = try transformLine(gpa, "GLIBC-2-7", "F", line) orelse continue;
        // sed script filter: /0x0*<unicode>$/d
        var it = std.mem.tokenizeAny(u8, t, " \t");
        _ = it.next();
        const u = it.next() orelse continue;
        const uv = decodeHexSkip(u);
        var dropped = false;
        for (drop.items) |d| {
            if (uv == d) {
                dropped = true;
                break;
            }
        }
        if (dropped) {
            gpa.free(t);
            continue;
        }
        // post seds: 0x2015 -> 0x2014, 0x2299 -> 0x29BF.
        var final = t;
        if (std.mem.indexOf(u8, t, "0x2015") != null) {
            final = try std.mem.replaceOwned(u8, gpa, t, "0x2015", "0x2014");
            gpa.free(t);
        }
        if (std.mem.indexOf(u8, final, "0x2299") != null) {
            const f2 = try std.mem.replaceOwned(u8, gpa, final, "0x2299", "0x29BF");
            gpa.free(final);
            final = f2;
        }
        try out.append(gpa, final);
    }
    try writeOut(gpa, io, cwd, "etc/charsets/JISX2131.map", out.items);
}

// ---------------------------------------------------------------------
// ALTERNATIVNYJ.map: header + per-byte Unicode fixes on IBM866.map
// ---------------------------------------------------------------------
fn genAlternativnyj(gpa: std.mem.Allocator, io: std.Io, cwd: std.Io.Dir) !void {
    const src = try cwd.readFileAlloc(io, "etc/charsets/IBM866.map", gpa, .unlimited);
    defer gpa.free(src);
    const fixes = [_]struct { byte: []const u8, uni: []const u8 }{
        .{ .byte = "0xF2", .uni = "0x2019" },
        .{ .byte = "0xF3", .uni = "0x2018" },
        .{ .byte = "0xF4", .uni = "0x0301" },
        .{ .byte = "0xF5", .uni = "0x0300" },
        .{ .byte = "0xF6", .uni = "0x203A" },
        .{ .byte = "0xF7", .uni = "0x2039" },
        .{ .byte = "0xF8", .uni = "0x2191" },
        .{ .byte = "0xF9", .uni = "0x2193" },
        .{ .byte = "0xFA", .uni = "0x00B1" },
        .{ .byte = "0xFB", .uni = "0x00F7" },
    };
    var out: std.ArrayList([]const u8) = .empty;
    defer out.deinit(gpa);
    try out.append(gpa, "# Modified from IBM866.map according to the chart at");
    try out.append(gpa, "# https://web.archive.org/web/20100131045151/http://www.cyrillic.com/ref/cyrillic/koi-8alt.html");
    try out.append(gpa, "# with guesses for the Unicodes of the glyphs.");
    var first = true;
    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |line| {
        if (first) {
            first = false; // sed '1 d'
            continue;
        }
        if (line.len < 6) continue;
        var fixed = line;
        for (fixes) |f| {
            if (std.mem.indexOf(u8, fixed, f.byte) != null and std.mem.indexOfScalar(u8, fixed, ' ') != null) {
                const space = std.mem.indexOfScalar(u8, fixed, ' ').?;
                const replaced = try std.fmt.allocPrint(gpa, "{s} {s}", .{ fixed[0..space], f.uni });
                fixed = replaced;
            }
        }
        try out.append(gpa, fixed);
    }
    try writeOut(gpa, io, cwd, "etc/charsets/ALTERNATIVNYJ.map", out.items);
}
