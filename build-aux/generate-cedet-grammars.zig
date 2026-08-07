//! Native Zig replacement for build-aux/generate-cedet-grammars.sh:
//! generate the cedet parser files from admin/grammars/*.{by,wy} via the
//! dumped emacs. No shell; the pdumper relocation flake is retried on
//! signal death. Run with cwd = repo root; incremental (existing output
//! files are left untouched).

const std = @import("std");
const aslr = @import("aslr.zig");
const env = @import("env.zig");

const Grammar = struct {
    tool: []const u8,
    func: []const u8,
    out: []const u8,
    src: []const u8,
};

const grammars = [_]Grammar{
    .{ .tool = "semantic/bovine/grammar", .func = "bovine-batch-make-parser", .out = "lisp/cedet/semantic/bovine/c-by.el", .src = "c.by" },
    .{ .tool = "semantic/bovine/grammar", .func = "bovine-batch-make-parser", .out = "lisp/cedet/semantic/bovine/make-by.el", .src = "make.by" },
    .{ .tool = "semantic/bovine/grammar", .func = "bovine-batch-make-parser", .out = "lisp/cedet/semantic/bovine/scm-by.el", .src = "scheme.by" },
    .{ .tool = "semantic/wisent/grammar", .func = "wisent-batch-make-parser", .out = "lisp/cedet/semantic/grammar-wy.el", .src = "grammar.wy" },
    .{ .tool = "semantic/wisent/grammar", .func = "wisent-batch-make-parser", .out = "lisp/cedet/semantic/wisent/javat-wy.el", .src = "java-tags.wy" },
    .{ .tool = "semantic/wisent/grammar", .func = "wisent-batch-make-parser", .out = "lisp/cedet/semantic/wisent/js-wy.el", .src = "js.wy" },
    .{ .tool = "semantic/wisent/grammar", .func = "wisent-batch-make-parser", .out = "lisp/cedet/semantic/wisent/python-wy.el", .src = "python.wy" },
    .{ .tool = "semantic/wisent/grammar", .func = "wisent-batch-make-parser", .out = "lisp/cedet/srecode/srt-wy.el", .src = "srecode-template.wy" },
};

pub fn main(minimal: std.process.Init.Minimal) !void {
    aslr.disableAslr();
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();
    var env_map = try env.inherit(gpa, minimal);
    defer env_map.deinit();

    const root = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(root);
    const temacs_path = @import("temacs-path.zig");
    const temacs = try temacs_path.joinBin(gpa, root);
    defer gpa.free(temacs);
    const dump = try std.fs.path.join(gpa, &.{ root, "zig-out", "bin", "bootstrap-emacs.pdmp" });
    defer gpa.free(dump);
    const lisp_dir = try std.fs.path.join(gpa, &.{ root, "lisp" });
    defer gpa.free(lisp_dir);
    const cedet_dir = try std.fs.path.join(gpa, &.{ root, "lisp", "cedet" });
    defer gpa.free(cedet_dir);
    const gr = try std.fs.path.join(gpa, &.{ root, "admin", "grammars" });
    defer gpa.free(gr);

    const dump_arg = try std.fmt.allocPrint(gpa, "--dump-file={s}", .{dump});
    defer gpa.free(dump_arg);

    var generated: usize = 0;
    for (grammars) |g| {
        const out_abs = try std.fs.path.join(gpa, &.{ root, g.out });
        defer gpa.free(out_abs);
        if (fileExists(io, cwd, out_abs)) continue;

        const tool_abs = try std.fs.path.join(gpa, &.{ cedet_dir, g.tool });
        defer gpa.free(tool_abs);
        const src_abs = try std.fs.path.join(gpa, &.{ gr, g.src });
        defer gpa.free(src_abs);
        const argv = [_][]const u8{
            temacs, "--batch",
            "-L", lisp_dir,
            "-L", cedet_dir,
            dump_arg,
            "-l", "cl-extra",
            "-l", tool_abs,
            "-f", g.func,
            "-o", out_abs,
            src_abs,
        };
        var attempt: usize = 0;
        while (true) : (attempt += 1) {
            var child = try std.process.spawn(io, .{
                .argv = &argv,
                .environ_map = &env_map,
                .stdin = .ignore,
                .stdout = .ignore,
                .stderr = .ignore,
            });
            const term = try child.wait(io);
            switch (term) {
                .exited => |code| {
                    if (code != 0) {
                        std.debug.print("generate-cedet-grammars: {s} {s} -> {s} exited {d}\n", .{ g.tool, g.src, g.out, code });
                        std.process.exit(1);
                    }
                    break;
                },
                .signal => |sig| {
                    std.debug.print("generate-cedet-grammars: temacs died with signal {d}; retrying ({d}/3)\n", .{ @intFromEnum(sig), attempt + 1 });
                    if (attempt >= 2) std.process.exit(1);
                },
                else => std.process.exit(1),
            }
        }
        if (!fileExists(io, cwd, out_abs)) {
            std.debug.print("generate-cedet-grammars: {s} produced no {s}\n", .{ g.tool, g.out });
            std.process.exit(1);
        }
        generated += 1;
    }
    std.debug.print("generate-cedet-grammars: generated {d} parser files\n", .{generated});
}

fn fileExists(io: std.Io, cwd: std.Io.Dir, path: []const u8) bool {
    var f = cwd.openFile(io, path, .{}) catch return false;
    f.close(io);
    return true;
}
