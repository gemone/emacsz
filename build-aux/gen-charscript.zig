//! Native Zig replacement for admin/unidata/blocks.awk: generate
//! lisp/international/charscript.el from admin/unidata/Blocks.txt +
//! emoji-data.txt. Byte-identical to the gawk output (the awk prints
//! entries in insertion order, which Zig replicates). Run with cwd =
//! repo root.

const std = @import("std");
const stamp = @import("stamp.zig");

const Entry = struct {
    start: []const u8,
    end: []const u8,
    alt: []const u8,
    name: []const u8,
};

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    const blocks = try cwd.readFileAlloc(io, "admin/unidata/Blocks.txt", gpa, .unlimited);
    defer gpa.free(blocks);
    const emoji = try cwd.readFileAlloc(io, "admin/unidata/emoji-data.txt", gpa, .unlimited);
    defer gpa.free(emoji);

    var starts: std.ArrayList([]const u8) = .empty;
    defer starts.deinit(gpa);
    var ends: std.ArrayList([]const u8) = .empty;
    defer ends.deinit(gpa);
    var alts: std.ArrayList([]const u8) = .empty;
    defer alts.deinit(gpa);
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(gpa);

    // Blocks.txt: ranges with names, hard-coded fixes and splits.
    var lines = std.mem.splitScalar(u8, blocks, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or !isHex(line[0])) continue;
        const range_end = std.mem.indexOfScalar(u8, line, ' ') orelse line.len;
        const range = line[0..range_end];
        const sep = std.mem.indexOf(u8, range, "..") orelse continue;
        var s = range[0..sep];
        // awk's substr length arithmetic: $1 is "0000..007F;" (the ';' is
        // part of the first field), so the end excludes the trailing ';'.
        const e = range[sep + 2 .. range.len - 1];
        // Name is everything after the "; " separator.  Trim CR too:
        // Windows checkouts (core.autocrlf) give Blocks.txt CRLF line
        // endings, and a trailing '\r' would defeat the endsWith
        // "forms"/"tiles" shortening below (e.g. "Mahjong Tiles\r" never
        // shortens to "Mahjong Tile").
        const semi = std.mem.indexOfScalar(u8, line, ';') orelse continue;
        const name = std.mem.trim(u8, line[semi + 1 ..], " \t\r");
        if (std.mem.eql(u8, s, "0080")) s = "00A0"; // fix_start

        try starts.append(gpa, try gpa.dupe(u8, s));
        try ends.append(gpa, try gpa.dupe(u8, e));
        try names.append(gpa, try gpa.dupe(u8, name));

        // Hard-coded split processed before name2alias and the merge.
        if (std.mem.eql(u8, s, "3300")) {
            ends.items[ends.items.len - 1] = "3357";
            names.items[names.items.len - 1] = "Katakana";
            try starts.append(gpa, try gpa.dupe(u8, "3358"));
            try ends.append(gpa, try gpa.dupe(u8, "33FF"));
            try names.append(gpa, try gpa.dupe(u8, "CJK Compatibility"));
        }

        const n = names.items.len;
        const added: usize = if (std.mem.eql(u8, s, "3300")) 2 else 1;
        for ((n - added)..n) |idx| {
            const alt = try name2alias(gpa, names.items[idx]);
            if (alt.len == 0) {
                // awk: i-- (discard this entry) then `next`.
                _ = starts.pop();
                _ = ends.pop();
                _ = names.pop();
                break;
            }
            try alts.append(gpa, alt);
            const cur = alts.items.len - 1;
            // Combine adjacent ranges with the same alt.
            if (cur > 0 and std.mem.eql(u8, alts.items[cur], alts.items[cur - 1]) and
                decodeHex(starts.items[cur]) == 1 + decodeHex(ends.items[cur - 1]))
            {
                ends.items[cur - 1] = ends.items[cur];
                const merged = try std.fmt.allocPrint(gpa, "{s}, {s}", .{ names.items[cur - 1], names.items[cur] });
                names.items[cur - 1] = merged;
                _ = starts.pop();
                _ = ends.pop();
                _ = alts.pop();
                _ = names.pop();
            }
            const check_idx = alts.items.len - 1;
            // Hard-coded splits after the merge.
            if (std.mem.eql(u8, starts.items[check_idx], "0370")) {
                ends.items[check_idx] = "03E1";
                try starts.append(gpa, try gpa.dupe(u8, "03E2"));
                try ends.append(gpa, try gpa.dupe(u8, "03EF"));
                try alts.append(gpa, "coptic");
                try names.append(gpa, "");
                try starts.append(gpa, try gpa.dupe(u8, "03F0"));
                try ends.append(gpa, try gpa.dupe(u8, "03FF"));
                try alts.append(gpa, "greek");
                try names.append(gpa, "");
            } else if (std.mem.eql(u8, starts.items[check_idx], "FB00")) {
                ends.items[check_idx] = "FB06";
                try starts.append(gpa, try gpa.dupe(u8, "FB13"));
                try ends.append(gpa, try gpa.dupe(u8, "FB17"));
                try alts.append(gpa, "armenian");
                try names.append(gpa, "");
                try starts.append(gpa, try gpa.dupe(u8, "FB1D"));
                try ends.append(gpa, try gpa.dupe(u8, "FB4F"));
                try alts.append(gpa, "hebrew");
                try names.append(gpa, "");
            } else if (std.mem.eql(u8, starts.items[check_idx], "FF00")) {
                ends.items[check_idx] = "FF60";
                try starts.append(gpa, try gpa.dupe(u8, "FF61"));
                try ends.append(gpa, try gpa.dupe(u8, "FF9F"));
                try alts.append(gpa, "kana");
                try names.append(gpa, "");
                try starts.append(gpa, try gpa.dupe(u8, "FFA0"));
                try ends.append(gpa, try gpa.dupe(u8, "FFDF"));
                try alts.append(gpa, "hangul");
                try names.append(gpa, "");
                try starts.append(gpa, try gpa.dupe(u8, "FFE0"));
                try ends.append(gpa, try gpa.dupe(u8, "FFEF"));
                try alts.append(gpa, "cjk-misc");
                try names.append(gpa, "");
            }
        }
    }

    // emoji-data.txt: Emoji_Presentation ranges.
    lines = std.mem.splitScalar(u8, emoji, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or !isHex(line[0])) continue;
        if (std.mem.indexOf(u8, line, "; Emoji_Presentation ") == null) continue;
        const range_end = std.mem.indexOfScalar(u8, line, ' ') orelse line.len;
        const range = line[0..range_end];
        if (std.mem.indexOf(u8, range, "..")) |sep| {
            try starts.append(gpa, try gpa.dupe(u8, range[0..sep]));
            try ends.append(gpa, try gpa.dupe(u8, range[sep + 2 ..]));
        } else {
            try starts.append(gpa, try gpa.dupe(u8, range));
            try ends.append(gpa, try gpa.dupe(u8, range));
        }
        try alts.append(gpa, "emoji");
        try names.append(gpa, "Autogenerated emoji");
    }

    // FE0F override appended last.
    try starts.append(gpa, try gpa.dupe(u8, "FE0F"));
    try ends.append(gpa, try gpa.dupe(u8, "FE0F"));
    try alts.append(gpa, "emoji");
    try names.append(gpa, "Autogenerated emoji (override)");

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.appendSlice(gpa, ";;; charscript.el --- character script table  -*- lexical-binding:t -*-\n");
    try out.appendSlice(gpa, ";;; Automatically generated from admin/unidata/{Blocks,emoji-data}.txt\n");
    try out.appendSlice(gpa, "(let (script-list)\n");
    try out.appendSlice(gpa, "  (dolist (elt '(\n");
    for (starts.items, 0..) |s, idx| {
        const line = try std.fmt.allocPrint(gpa, "    (#x{s} #x{s} {s})", .{ s, ends.items[idx], alts.items[idx] });
        defer gpa.free(line);
        try out.appendSlice(gpa, line);
        const nm = names.items[idx];
        const alt = alts.items[idx];
        if (nm.len > 0 and !eqLower(alt, nm) and
            std.mem.indexOfScalar(u8, alt, '-') == null)
        {
            try out.appendSlice(gpa, " ; ");
            try out.appendSlice(gpa, nm);
        }
        try out.appendSlice(gpa, "\n");
    }
    try out.appendSlice(gpa, "    ))\n");
    try out.appendSlice(gpa, "    (set-char-table-range char-script-table\n");
    try out.appendSlice(gpa, "\t\t\t  (cons (car elt) (nth 1 elt)) (nth 2 elt))\n");
    try out.appendSlice(gpa, "    (or (memq (nth 2 elt) script-list)\n");
    try out.appendSlice(gpa, "\t(setq script-list (cons (nth 2 elt) script-list))))\n");
    try out.appendSlice(gpa, "  (set-char-table-extra-slot char-script-table 0 (nreverse script-list)))\n");
    try out.appendSlice(gpa, "\n(map-char-table\n");
    try out.appendSlice(gpa, " (lambda (ch script)\n");
    try out.appendSlice(gpa, "   (and (eq script 'symbol)\n");
    try out.appendSlice(gpa, "\t(modify-category-entry ch ?5)))\n");
    try out.appendSlice(gpa, " char-script-table)\n");
    try out.appendSlice(gpa, "\n(provide 'charscript)");
    try out.append(gpa, '\n');

    _ = try stamp.writeFileIfChanged(io, gpa, cwd, "lisp/international/charscript.el", out.items);
}

fn isHex(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'A' and c <= 'F');
}

fn decodeHex(s: []const u8) u64 {
    var n: u64 = 0;
    for (s) |c| {
        n *= 16;
        if (c >= '0' and c <= '9') {
            n += c - '0';
        } else if (c >= 'A' and c <= 'F') {
            n += c - 'A' + 10;
        } else if (c >= 'a' and c <= 'f') {
            n += c - 'a' + 10;
        } else {
            std.debug.print("decodeHex bad char {c} in {s}\n", .{ c, s });
            std.process.exit(1);
        }
    }
    return n;
}

fn eqLower(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        const yl = if (y >= 'A' and y <= 'Z') y + 32 else y;
        if (x != yl) return false;
    }
    return true;
}

fn contains(hay: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, hay, needle) != null;
}

// /combining .* marks/: "combining", anything, " marks".
fn combiningMarks(name: []const u8) bool {
    const c = std.mem.indexOf(u8, name, "combining") orelse return false;
    return std.mem.indexOf(u8, name[c + 9 ..], " marks") != null;
}

/// awk name2alias: alias table, regex rules, then the sub() transforms.
fn name2alias(gpa: std.mem.Allocator, name_in: []const u8) ![]const u8 {
    const aliases = [_][2][]const u8{
        .{ "ipa extensions", "phonetic" },
        .{ "letterlike symbols", "symbol" },
        .{ "number forms", "symbol" },
        .{ "miscellaneous technical", "symbol" },
        .{ "control pictures", "symbol" },
        .{ "optical character recognition", "symbol" },
        .{ "enclosed alphanumerics", "symbol" },
        .{ "box drawing", "symbol" },
        .{ "block elements", "symbol" },
        .{ "miscellaneous symbols", "symbol" },
        .{ "miscellaneous symbols supplement", "symbol" },
        .{ "symbols for legacy computing", "symbol" },
        .{ "symbols for legacy computing supplement", "symbol" },
        .{ "cjk strokes", "cjk-misc" },
        .{ "cjk symbols and punctuation", "cjk-misc" },
        .{ "halfwidth and fullwidth forms", "cjk-misc" },
        .{ "yijing hexagram symbols", "cjk-misc" },
        .{ "common indic number forms", "north-indic-number" },
    };
    var buf: [256]u8 = undefined;
    var n: usize = 0;
    for (name_in) |c| {
        buf[n] = if (c >= 'A' and c <= 'Z') c + 32 else c;
        n += 1;
    }
    const name0: []const u8 = buf[0..n];
    const name: []const u8 = name0;

    for (aliases) |a| {
        if (std.mem.eql(u8, name, a[0])) return try gpa.dupe(u8, a[1]);
    }
    if (contains(name, "for symbols")) return try gpa.dupe(u8, "symbol");
    if (contains(name, "latin") or combiningMarks(name) or contains(name, "spacing modifier") or
        contains(name, "tone letters") or contains(name, "alphabetic presentation"))
        return try gpa.dupe(u8, "latin");
    if (contains(name, "cjk") or contains(name, "enclosed ideograph") or contains(name, "kangxi"))
        return try gpa.dupe(u8, "han");
    if (contains(name, "arabic")) return try gpa.dupe(u8, "arabic");
    if (std.mem.startsWith(u8, name, "greek")) return try gpa.dupe(u8, "greek");
    if (std.mem.startsWith(u8, name, "coptic")) return try gpa.dupe(u8, "coptic");
    if (contains(name, "cuneiform number")) return try gpa.dupe(u8, "cuneiform");
    if (contains(name, "cuneiform")) return try gpa.dupe(u8, "cuneiform");
    if (contains(name, "mathematical alphanumeric symbol")) return try gpa.dupe(u8, "mathematical");
    const symbol_tokens = [_][]const u8{
        "punctuation", "mathematical", "arrows", "currency", "superscript",
        "small form variants", "geometric", "dingbats", "enclosed",
        "alchemical", "pictograph", "emoticon", "transport",
    };
    for (symbol_tokens) |t| {
        if (contains(name, t)) return try gpa.dupe(u8, "symbol");
    }
    if (contains(name, "canadian aboriginal")) return try gpa.dupe(u8, "canadian-aboriginal");
    if (contains(name, "katakana") or contains(name, "hiragana")) return try gpa.dupe(u8, "kana");
    if (contains(name, "myanmar")) return try gpa.dupe(u8, "burmese");
    if (contains(name, "hangul")) return try gpa.dupe(u8, "hangul");
    if (contains(name, "khmer")) return try gpa.dupe(u8, "khmer");
    if (contains(name, "braille")) return try gpa.dupe(u8, "braille");
    if (std.mem.startsWith(u8, name, "yi ")) return try gpa.dupe(u8, "yi");
    if (contains(name, "surrogates") or contains(name, "private use") or contains(name, "variation selectors"))
        return try gpa.dupe(u8, "");
    if (std.mem.eql(u8, name, "specials") or std.mem.eql(u8, name, "tags"))
        return try gpa.dupe(u8, "");
    if (contains(name, "linear b")) return try gpa.dupe(u8, "linear-b");
    if (contains(name, "aramaic")) return try gpa.dupe(u8, "aramaic");
    if (contains(name, "rumi num")) return try gpa.dupe(u8, "arabic");
    if (contains(name, "duployan") or contains(name, "shorthand")) return try gpa.dupe(u8, "duployan-shorthand");
    if (contains(name, "sutton signwriting")) return try gpa.dupe(u8, "sutton-sign-writing");
    if (contains(name, "sinhala archaic number")) return try gpa.dupe(u8, "sinhala");
    if (contains(name, "tangut components")) return try gpa.dupe(u8, "tangut");

    var work: std.ArrayList(u8) = .empty;
    defer work.deinit(gpa);
    try work.appendSlice(gpa, name);
    if (std.mem.startsWith(u8, work.items, "small ")) {
        std.mem.copyForwards(u8, work.items[0 .. work.items.len - 6], work.items[6..]);
        work.items.len -= 6;
    }
    const strip_tokens = [_][]const u8{ " extended", " extensions", " extension", " supplement" };
    var best: ?usize = null;
    for (strip_tokens) |t| {
        if (std.mem.indexOf(u8, work.items, t)) |p| {
            if (best == null or p < best.?) best = p;
        }
    }
    if (best) |p| work.items.len = p;
    replaceFirst(&work, "numbers", "number");
    replaceFirst(&work, "numerals", "numeral");
    replaceFirst(&work, "symbols", "symbol");
    // sub(/forms$/, "form") and sub(/tiles$/, "tile"): shorten by one.
    if (std.mem.endsWith(u8, work.items, "forms")) work.items.len -= 1;
    if (std.mem.endsWith(u8, work.items, "tiles")) work.items.len -= 1;
    if (std.mem.startsWith(u8, work.items, "new ")) {
        std.mem.copyForwards(u8, work.items[0 .. work.items.len - 4], work.items[4..]);
        work.items.len -= 4;
    }
    const tail_tokens = [_][]const u8{ " characters", " hieroglyphs", " cursive", " hieroglyph format controls" };
    for (tail_tokens) |t| {
        if (std.mem.endsWith(u8, work.items, t)) {
            work.items.len -= t.len;
            break;
        }
    }
    var i: usize = 0;
    while (i < work.items.len) : (i += 1) {
        if (work.items[i] == ' ') work.items[i] = '-';
    }
    return try gpa.dupe(u8, work.items);
}

fn replaceFirst(work: *std.ArrayList(u8), from: []const u8, to: []const u8) void {
    if (std.mem.indexOf(u8, work.items, from)) |p| {
        @memcpy(work.items[p .. p + to.len], to);
        const tail = work.items[p + from.len ..];
        std.mem.copyForwards(u8, work.items[p + to.len ..], tail);
        work.items.len -= from.len - to.len;
    }
}
