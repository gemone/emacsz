//! Native Zig replacement for build-aux/generate-charprop.sh: generate
//! lisp/international/{charprop,uni-*}.el from admin/unidata via the
//! dumped emacs, including the unidata.txt sed transform. No shell; the
//! pdumper relocation flake is retried on signal death. Run with cwd =
//! repo root. Incremental: an existing output file is left untouched.

const std = @import("std");
const aslr = @import("aslr.zig");
const temacs_path = @import("temacs-path.zig");

const unifiles = [_][]const u8{
    "uni-name",                "uni-category",          "uni-combining",
    "uni-bidi",                "uni-decomposition",     "uni-decimal",
    "uni-digit",               "uni-numeric",           "uni-mirrored",
    "uni-old-name",            "uni-comment",           "uni-uppercase",
    "uni-lowercase",           "uni-titlecase",         "uni-special-uppercase",
    "uni-special-lowercase",   "uni-special-titlecase", "uni-brackets",
};

pub fn main() !void {
    aslr.disableAslr();
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    const root = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(root);
    const temacs = try temacs_path.joinBin(gpa, root);
    defer gpa.free(temacs);
    const dump = try std.fs.path.join(gpa, &.{ root, "zig-out", "bin", "bootstrap-emacs.pdmp" });
    defer gpa.free(dump);
    const unidata = try std.fs.path.join(gpa, &.{ root, "admin", "unidata" });
    defer gpa.free(unidata);
    const out_dir = try std.fs.path.join(gpa, &.{ root, "lisp", "international" });
    defer gpa.free(out_dir);

    // unidata.txt: the sed transform
    //   s/\([^;]*\);\(.*\)/(#x\1 "\2")/  then  s/;/" "/g
    const src = try cwd.readFileAlloc(io, "admin/unidata/UnicodeData.txt", gpa, .unlimited);
    defer gpa.free(src);
    var out_txt: std.ArrayList(u8) = .empty;
    defer out_txt.deinit(gpa);
    var line_start: usize = 0;
    while (line_start <= src.len) {
        const nl = std.mem.indexOfScalarPos(u8, src, line_start, '\n') orelse src.len;
        const line = src[line_start..nl];
        if (line.len == 0) {
            // An empty line in the middle of the file stays empty; the
            // phantom segment after a final newline is not a line.
            if (nl < src.len) try out_txt.append(gpa, '\n');
            if (nl == src.len) break;
            line_start = nl + 1;
            continue;
        }
        const semi = std.mem.indexOfScalar(u8, line, ';') orelse {
            // No ';': pass the line through unchanged (sed does not match).
            try out_txt.appendSlice(gpa, line);
            try out_txt.append(gpa, '\n');
            continue;
        };
        try out_txt.appendSlice(gpa, "(#x");
        try out_txt.appendSlice(gpa, line[0..semi]);
        try out_txt.appendSlice(gpa, " \"");
        var fields = std.mem.splitScalar(u8, line[semi + 1 ..], ';');
        var first = true;
        while (fields.next()) |f| {
            if (!first) try out_txt.appendSlice(gpa, "\" \"");
            first = false;
            try out_txt.appendSlice(gpa, f);
        }
        try out_txt.appendSlice(gpa, "\")\n");
        if (nl == src.len) break;
        line_start = nl + 1;
    }
    try cwd.writeFile(io, .{ .sub_path = "admin/unidata/unidata.txt", .data = out_txt.items });

    const dump_arg = try std.fmt.allocPrint(gpa, "--dump-file={s}", .{dump});
    defer gpa.free(dump_arg);

    var generated: usize = 0;
    for (unifiles) |u| {
        const target = try std.fs.path.join(gpa, &.{ out_dir, u });
        defer gpa.free(target);
        const out_el = try std.fmt.allocPrint(gpa, "{s}.el", .{target});
        defer gpa.free(out_el);
        if (fileExists(io, cwd, out_el)) continue;
    const eval = try std.fmt.allocPrint(gpa, "(unidata-gen-file \"{s}.el\" \"{s}\" \"unidata.txt\")", .{ target, unidata });
    defer gpa.free(eval);
        try runEmacs(gpa, io, temacs, dump_arg, unidata, "unidata-gen", eval);
        generated += 1;
    }

    // Non-unifile tables: uni-scripts, uni-confusable, idna-mapping,
    // emoji-labels and the charprop bundle.
    const specials = [_]struct { name: []const u8 }{
        .{ .name = "uni-scripts.el" },
        .{ .name = "uni-confusable.el" },
        .{ .name = "idna-mapping.el" },
    };
    for (specials) |sp| {
        const target = try std.fs.path.join(gpa, &.{ out_dir, sp.name });
        defer gpa.free(target);
        if (fileExists(io, cwd, target)) continue;
        const eval = if (std.mem.eql(u8, sp.name, "uni-scripts.el"))
            try std.fmt.allocPrint(gpa, "(unidata-gen-scripts \"{s}/uni-scripts.el\")", .{out_dir})
        else if (std.mem.eql(u8, sp.name, "uni-confusable.el"))
            try std.fmt.allocPrint(gpa, "(unidata-gen-confusable \"{s}/uni-confusable.el\")", .{out_dir})
        else
            try std.fmt.allocPrint(gpa, "(unidata-gen-idna-mapping \"{s}/idna-mapping.el\")", .{out_dir});
        defer gpa.free(eval);
        try runEmacs(gpa, io, temacs, dump_arg, unidata, "unidata-gen", eval);
        generated += 1;
    }
    {
        const target = try std.fs.path.join(gpa, &.{ out_dir, "emoji-labels.el" });
        defer gpa.free(target);
        if (!fileExists(io, cwd, target)) {
            const eval = try std.fmt.allocPrint(gpa, "(emoji--generate-file \"{s}/emoji-labels.el\")", .{out_dir});
            defer gpa.free(eval);
            try runEmacs(gpa, io, temacs, dump_arg, out_dir, "emoji", eval);
            generated += 1;
        }
    }
    {
        const target = try std.fs.path.join(gpa, &.{ out_dir, "charprop.el" });
        defer gpa.free(target);
        if (!fileExists(io, cwd, target)) {
            const eval = try std.fmt.allocPrint(gpa, "(unidata-gen-charprop \"{s}/charprop.el\")", .{out_dir});
            defer gpa.free(eval);
            try runEmacs(gpa, io, temacs, dump_arg, unidata, "unidata-gen", eval);
            generated += 1;
        }
    }

    std.debug.print("generate-charprop: generated/updated {d} files in {s}\n", .{ generated, out_dir });
}

fn fileExists(io: std.Io, cwd: std.Io.Dir, path: []const u8) bool {
    var f = cwd.openFile(io, path, .{}) catch return false;
    f.close(io);
    return true;
}

fn runEmacs(
    gpa: std.mem.Allocator,
    io: std.Io,
    temacs: []const u8,
    dump_arg: []const u8,
    load_dir: []const u8,
    load_lib: []const u8,
    eval: []const u8,
) !void {
    const argv = [_][]const u8{ temacs, "--batch", "-L", load_dir, "-l", load_lib, dump_arg, "--eval", eval };
    var attempt: usize = 0;
    while (true) : (attempt += 1) {
        const res = try std.process.run(gpa, io, .{
            .argv = &argv,
            .stdout_limit = .unlimited,
            .stderr_limit = .unlimited,
        });
        switch (res.term) {
            .exited => |code| {
                if (code == 0) return;
                printTail(res.stdout);
                printTail(res.stderr);
                std.debug.print("generate-charprop: temacs exited {d}\n", .{code});
                std.process.exit(1);
            },
            .signal => |sig| {
                printTail(res.stdout);
                printTail(res.stderr);
                std.debug.print("generate-charprop: temacs died with signal {d}; retrying ({d}/3)\n", .{ @intFromEnum(sig), attempt + 1 });
                if (attempt >= 2) std.process.exit(1);
            },
            else => std.process.exit(1),
        }
    }
}

fn printTail(out: []const u8) void {
    const tail = if (out.len > 65536) out[out.len - 65536 ..] else out;
    std.debug.print("{s}\n", .{tail});
}
