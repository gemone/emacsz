//! Native `emacs` launcher for hosts that cannot run the .sh wrapper --
//! Windows without msys2, where a `#!/bin/sh` script is not a valid
//! executable (the build's smoke step failed with InvalidExe).  It mirrors
//! build-aux/emacs-launcher.sh: resolve this executable's own directory,
//! then run the sibling temacs with the dumped bootstrap-emacs.pdmp,
//! forwarding argv and stdio verbatim, so the installed `emacs` works from
//! any CWD with no shell.
//!
//! build.zig builds this and installs it as `emacs(.exe)` on Windows; Unix
//! keeps the .sh, which additionally disables ASLR via `setarch -R` for
//! reliable pdumper relocation (aslr.zig's personality(2) trick is
//! Linux-only and applies only to the process that calls it, so the shell
//! wrapper remains preferable there).

const std = @import("std");
const env = @import("env.zig");
const temacs_path = @import("temacs-path.zig");

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();

    // Resolve this executable's directory; temacs and the pdmp are siblings.
    const self = try std.process.executablePathAlloc(io, gpa);
    defer gpa.free(self);
    const dir = std.fs.path.dirname(self) orelse {
        std.debug.print("emacs: cannot resolve launcher directory from {s}\n", .{self});
        std.process.exit(1);
    };
    const temacs = try std.fs.path.join(gpa, &.{ dir, temacs_path.name });
    defer gpa.free(temacs);
    const pdmp = try std.fs.path.join(gpa, &.{ dir, "bootstrap-emacs.pdmp" });
    defer gpa.free(pdmp);
    const dump_arg = try std.fmt.allocPrint(gpa, "--dump-file={s}", .{pdmp});
    defer gpa.free(dump_arg);

    // argv = [temacs, --dump-file=<pdmp>, <caller args...>]; drop argv[0]
    // (this launcher's own path) so the forwarded command line is exactly
    // what the caller asked emacs to do.
    var arg_it = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer arg_it.deinit();
    _ = arg_it.next();

    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(gpa);
    try argv.append(gpa, temacs);
    try argv.append(gpa, dump_arg);
    while (arg_it.next()) |a| try argv.append(gpa, a);

    // epaths.h build-tree paths locate lisp/etc under the source tree, so
    // the launcher works from any CWD without setting EMACSLOADPATH/
    // EMACSDATA; only honor explicit EMACS_LISP_DIR/EMACS_DATA_DIR overrides
    // (relocatability/testing), matching emacs-launcher.sh.
    var env_map = try env.inherit(gpa, minimal);
    defer env_map.deinit();
    if (env_map.get("EMACS_LISP_DIR")) |v| try env_map.put("EMACSLOADPATH", v);
    if (env_map.get("EMACS_DATA_DIR")) |v| try env_map.put("EMACSDATA", v);

    var child = try std.process.spawn(io, .{
        .argv = argv.items,
        .environ_map = &env_map,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| std.process.exit(code),
        else => std.process.exit(1),
    }
}
