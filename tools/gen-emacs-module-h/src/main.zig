//! gen-emacs-module-h: generate src/emacs-module.h from the committed
//! src/emacs-module.in.h template, mirroring upstream's autoconf rule
//! (configure.ac:5163 AC_CONFIG_FILES([src/emacs-module.h:src/emacs-module.in.h])
//! + AC_SUBST_FILE for the module-env snippets + the emacs_major_version
//! substitution).  Without this step a fresh checkout has no
//! src/emacs-module.h (it is gitignored + generated), and the dynamic-module
//! build (HAVE_MODULES / HAVE_MODULES_ZIG) fails to find the header.
//!
//! Substitutions applied to the template:
//!   @emacs_major_version@    -> <major-version>   (e.g. "32" from 32.0.50)
//!   @module_env_snippet_25@  ..  @module_env_snippet_32@
//!                            -> contents of <snippet-dir>/module-env-N.h
//!
//! Usage: gen-emacs-module-h <template> <output> <major-version> <snippet-dir>
//! (cwd = repo root; the output is written into the source tree, mirroring
//! where upstream's configure writes it, and is covered by .gitignore.)

const std = @import("std");

pub fn main(minimal: std.process.Init.Minimal) !void {
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();
    const a = std.heap.smp_allocator;
    const cwd = std.Io.Dir.cwd();

    var it = try std.process.Args.Iterator.initAllocator(minimal.args, a);
    defer it.deinit();
    _ = it.next(); // program name
    const template_path = it.next() orelse return error.MissingTemplateArg;
    const output_path = it.next() orelse return error.MissingOutputArg;
    const major_version = it.next() orelse return error.MissingVersionArg;
    const snippet_dir = it.next() orelse return error.MissingSnippetDirArg;

    // `text` is owned by us and manually freed after each substitution
    // (replaceOwned allocates a fresh buffer; no deferred free so the
    // reassignment never double-frees).
    var text = try cwd.readFileAlloc(io, template_path, a, .limited(1 << 20));

    // @emacs_major_version@ -> the major version (e.g. "32" from 32.0.50).
    {
        const replaced = try std.mem.replaceOwned(u8, a, text, "@emacs_major_version@", major_version);
        a.free(text);
        text = replaced;
    }

    // @module_env_snippet_25@ .. @module_env_snippet_32@ -> file contents.
    var n: u8 = 25;
    while (n <= 32) : (n += 1) {
        const name = try std.fmt.allocPrint(a, "module-env-{d}.h", .{n});
        defer a.free(name);
        const path = try std.fs.path.join(a, &.{ snippet_dir, name });
        defer a.free(path);
        const content = try cwd.readFileAlloc(io, path, a, .limited(1 << 20));
        defer a.free(content);
        const placeholder = try std.fmt.allocPrint(a, "@module_env_snippet_{d}@", .{n});
        defer a.free(placeholder);
        const replaced = try std.mem.replaceOwned(u8, a, text, placeholder, content);
        a.free(text);
        text = replaced;
    }

    try cwd.writeFile(io, .{ .sub_path = output_path, .data = text });
    a.free(text);
    std.debug.print("gen-emacs-module-h: wrote {s} (major {s}, snippets 25-32)\n", .{ output_path, major_version });
}
