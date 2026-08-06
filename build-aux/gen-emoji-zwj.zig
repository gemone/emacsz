//! Native Zig replacement for admin/unidata/emoji-zwj.awk: generate
//! lisp/international/emoji-zwj.el from admin/unidata/
//! emoji-zwj-sequences.txt (+ emoji-sequences.txt flag/keycap data by
//! hand, replicated literally). Byte-identical to the gawk output,
//! including gawk's sorted `for (elt in ch)` iteration. Run with cwd =
//! repo root.

const std = @import("std");

const trigger_codepoints = [_][]const u8{
    "261D", "26F9", "270C", "270D", "2764", "1F3CB", "1F3CC",
    "1F3F3", "1F3F4", "1F441", "1F574", "1F575", "1F590", "20E3",
};

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    const zwj_src = try cwd.readFileAlloc(io, "admin/unidata/emoji-zwj-sequences.txt", gpa, .unlimited);
    defer gpa.free(zwj_src);
    const seq_src = try cwd.readFileAlloc(io, "admin/unidata/emoji-sequences.txt", gpa, .unlimited);
    defer gpa.free(seq_src);

    // ch: set of first-codepoints; vec: newline-joined quoted sequences
    // per first codepoint (awk's `for (elt in ch)` iterates sorted).
    var ch = std.StringArrayHashMapUnmanaged(void){};
    defer ch.deinit(gpa);
    var vec = std.StringArrayHashMapUnmanaged(std.ArrayList(u8)){};
    defer {
        var it = vec.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(gpa);
        vec.deinit(gpa);
    }

    for ([_][]const u8{ zwj_src, seq_src }) |src| {
        var lines = std.mem.splitScalar(u8, src, '\n');
        while (lines.next()) |line| {
            // /^[0-9A-F].*; RGI_Emoji_(ZWJ|Modifier)_Sequence/
            const semi = std.mem.indexOf(u8, line, "; RGI_Emoji_") orelse continue;
            const tag = line[semi + 2 ..];
            if (!(std.mem.startsWith(u8, tag, "RGI_Emoji_ZWJ_Sequence") or
                std.mem.startsWith(u8, tag, "RGI_Emoji_Modifier_Sequence")))
                continue;
            if (line.len == 0 or !isHex(line[0])) continue;
            // sub(/ *;.*/, "", $0): strip the " ;..." tail, split on spaces.
            var tail = line;
            if (std.mem.indexOfScalar(u8, tail, ';')) |sc| tail = tail[0..sc];
            const stripped = std.mem.trim(u8, tail, " \t");
            var elts = std.mem.tokenizeAny(u8, stripped, " \t");
            const first = elts.next() orelse continue;
            const gop = try ch.getOrPut(gpa, first);
            if (!gop.found_existing) {
                try vec.put(gpa, first, .empty);
            }
            const v = vec.getPtr(first).?;
            if (gop.found_existing) try v.append(gpa, '\n');
            try v.append(gpa, '"');
            // awk's loop runs j = 1..num, so the first codepoint is part
            // of the sequence too.
            try v.appendSlice(gpa, "\\N{U+");
            try v.appendSlice(gpa, first);
            try v.appendSlice(gpa, "}");
            while (elts.next()) |e| {
                try v.appendSlice(gpa, "\\N{U+");
                try v.appendSlice(gpa, e);
                try v.appendSlice(gpa, "}");
            }
            try v.append(gpa, '"');
        }
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    try out.appendSlice(gpa, ";;; emoji-zwj.el --- emoji zwj character composition table  -*- lexical-binding:t -*-\n");
    try out.appendSlice(gpa, ";;; Automatically generated from admin/unidata/emoji-{zwj-,}sequences.txt\n");
    try out.appendSlice(gpa, "(eval-when-compile (require 'regexp-opt))\n");
    try out.appendSlice(gpa, "(setq auto-composition-emoji-eligible-codepoints\n'(\n");
    for (trigger_codepoints) |cp| {
        const line = try std.fmt.allocPrint(gpa, "?\\N{{U+{s}}}\n", .{cp});
        defer gpa.free(line);
        try out.appendSlice(gpa, line);
    }
    try out.appendSlice(gpa, "))\n");

    // The awk code appends FE0F trigger lines to an undefined `codepoint`
    // array entry (never printed); replicate that by doing nothing here.
    try out.appendSlice(gpa, "(dolist (elt (eval-when-compile `(\n");
    var keys: std.ArrayList([]const u8) = .empty;
    defer {
        keys.deinit(gpa);
    }
    var kit = ch.iterator();
    while (kit.next()) |entry| try keys.append(gpa, entry.key_ptr.*);
    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    for (keys.items) |key| {
        const v = vec.getPtr(key).?;
        const entry_head = try std.fmt.allocPrint(gpa, "(#x{s} .\n,(regexp-opt\n'(\n", .{key});
        defer gpa.free(entry_head);
        try out.appendSlice(gpa, entry_head);
        try out.appendSlice(gpa, v.items);
        const entry_tail = try std.fmt.allocPrint(gpa, "\n\"\\N{{U+{s}}}\\N{{U+FE0E}}\"\n\"\\N{{U+{s}}}\\N{{U+FE0F}}\"\n)))\n", .{ key, key });
        defer gpa.free(entry_tail);
        try out.appendSlice(gpa, entry_tail);
    }
    try out.appendSlice(gpa, ")))\n");
    try out.appendSlice(gpa, "  (set-char-table-range composition-function-table\n");
    try out.appendSlice(gpa, "                        (car elt)\n");
    try out.appendSlice(gpa, "                        (nconc (char-table-range composition-function-table (car elt))\n");
    try out.appendSlice(gpa, "                               (list (vector (cdr elt)\n");
    try out.appendSlice(gpa, "                                             0\n");
    try out.appendSlice(gpa, "                                             #'compose-gstring-for-graphic)))))\n");
    try out.appendSlice(gpa, ";; The following two blocks are derived by hand from emoji-sequences.txt\n");
    try out.appendSlice(gpa, ";; FIXME: add support for Emoji_Keycap_Sequence once we learn how to respect FE0F/VS-16\n");
    try out.appendSlice(gpa, ";; for ASCII characters.\n");
    try out.appendSlice(gpa, ";; Flags\n");
    try out.appendSlice(gpa, "(set-char-table-range composition-function-table\n");
    try out.appendSlice(gpa, "                      '(#x1F1E6 . #x1F1FF)\n");
    try out.appendSlice(gpa, "                      (nconc (char-table-range composition-function-table '(#x1F1E6 . #x1F1FF))\n");
    try out.appendSlice(gpa, "                             (list (vector \"[\\U0001F1E6-\\U0001F1FF][\\U0001F1E6-\\U0001F1FF]\"\n");
    try out.appendSlice(gpa, "                                           0\n");
    try out.appendSlice(gpa, "                                           #'compose-gstring-for-graphic))))\n");
    try out.appendSlice(gpa, ";; UK Flags\n");
    try out.appendSlice(gpa, "(set-char-table-range composition-function-table\n");
    try out.appendSlice(gpa, "                      #x1F3F4\n");
    try out.appendSlice(gpa, "                      (nconc (char-table-range composition-function-table #x1F3F4)\n");
    try out.appendSlice(gpa, "                             (list (vector \"\\U0001F3F4\\U000E0067\\U000E0062\\\\(?:\\U000E0065\\U000E006E\\U000E0067\\\\|\\U000E0073\\U000E0063\\U000E0074\\\\|\\U000E0077\\U000E006C\\U000E0073\\\\)\\U000E007F\"\n");
    try out.appendSlice(gpa, "                                           0\n");
    try out.appendSlice(gpa, "                                           #'compose-gstring-for-graphic))))\n");
    try out.appendSlice(gpa, "\n(provide 'emoji-zwj)");

    try cwd.writeFile(io, .{ .sub_path = "lisp/international/emoji-zwj.el", .data = out.items });
}

fn isHex(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'A' and c <= 'F');
}
