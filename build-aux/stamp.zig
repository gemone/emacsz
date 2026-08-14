//! Make-style freshness stamps for the build tools that `zig build`
//! re-executes on every invocation.
//!
//! Zig 0.16's Step.Run treats a Run step with no declared outputs as
//! side-effectful (std/Build/Step/Run.zig hasSideEffects: `.infer_from_args
//! => !hasAnyOutputArgs()`, `.inherit => true`), so the dump / loaddefs /
//! compile-lisp chain re-runs end to end even on a fully warm cache: the
//! tools write gitignored files into the SOURCE TREE, which the build
//! graph cannot track as outputs.  Moving the work under Run steps with
//! declared outputs would let a cached run skip regeneration after an
//! external clean (exactly why those steps carry `has_side_effects`), so
//! instead each tool gets a make-style freshness check INSIDE itself:
//!
//!   1. fingerprint every input: (path, size, mtime-ns, kind), gathered
//!      deterministically (sorted), via the 0.16 `std.Io` API;
//!   2. compare against a stamp under zig-out/.stamps/<name> that also
//!      records the output files the last run produced;
//!   3. fresh  ==  fingerprint matches AND every recorded output still
//!      exists  ->  skip the dump/scrape/compile entirely;
//!   4. after a real run, re-fingerprint the (post-run) inputs and
//!      re-record the outputs, so a run that wrote nothing converges
//!      immediately.
//!
//! mtime+size (make's own model) is the right granularity here: git
//! checkouts, editors and the generators all bump mtimes, and the
//! fingerprints are recomputed per run (~1600 stats, single-digit ms)
//! rather than hashed content.

const std = @import("std");

/// Incremental fingerprint over build inputs.
pub const Finger = struct {
    h: std.hash.XxHash64,

    pub fn init(salt: []const u8) Finger {
        var f: Finger = .{ .h = std.hash.XxHash64.init(0x5eed_5eed) };
        f.bytes("stamp-v1");
        f.bytes(salt);
        return f;
    }

    /// Delimit raw bytes so concatenated inputs cannot alias.
    pub fn bytes(self: *Finger, s: []const u8) void {
        var n: usize = s.len;
        self.h.update(std.mem.asBytes(&n));
        self.h.update(s);
    }

    /// Fold one file in by (path, size, mtime-ns, kind).  A missing file
    /// folds as a distinct marker so deleting an input invalidates the
    /// stamp.  Absolute paths ignore `dir` (std.Io.Dir.statFile rule).
    pub fn file(self: *Finger, io: std.Io, dir: std.Io.Dir, path: []const u8) void {
        const st = dir.statFile(io, path, .{}) catch {
            self.bytes("\x00missing");
            self.bytes(path);
            return;
        };
        self.bytes(path);
        self.h.update(std.mem.asBytes(&st.size));
        const ns: i128 = st.mtime.nanoseconds;
        self.h.update(std.mem.asBytes(&ns));
        const kind: u8 = @intFromEnum(st.kind);
        self.h.update(std.mem.asBytes(&kind));
    }

    /// Deterministic recursive fingerprint of everything under `path`
    /// (files AND directories, by relative path, size, mtime-ns, kind).
    /// Entries are collected and sorted before folding, so the hash does
    /// not depend on readdir order.  `exclude`, when given, drops entries
    /// whose relative path matches (use it for the tool's own outputs,
    /// which must not fingerprint their "before" state).
    pub fn tree(
        self: *Finger,
        io: std.Io,
        gpa: std.mem.Allocator,
        dir: std.Io.Dir,
        path: []const u8,
        exclude: ?*const fn (rel: []const u8) bool,
    ) !void {
        var entries: std.ArrayList(Entry) = .empty;
        defer {
            for (entries.items) |e| gpa.free(e.path);
            entries.deinit(gpa);
        }
        try collect(io, gpa, dir, path, exclude, &entries);
        std.mem.sort(Entry, entries.items, {}, Entry.lessThan);
        for (entries.items) |e| {
            self.bytes(e.path);
            // Directory mtimes are deliberately NOT folded: creating or
            // deleting any file inside a directory (the loaddefs regen,
            // the dump scrub, byte compilation) touches the directory
            // mtime even when the surviving tree is byte-identical, so
            // folding it would make the stamps churn forever.  The
            // directory's PRESENCE (path + kind) still fingerprints.
            const fold_size: u64 = if (e.kind == .directory) 0 else e.size;
            const fold_mtime: i128 = if (e.kind == .directory) 0 else e.mtime_ns;
            self.h.update(std.mem.asBytes(&fold_size));
            self.h.update(std.mem.asBytes(&fold_mtime));
            const kind: u8 = @intFromEnum(e.kind);
            self.h.update(std.mem.asBytes(&kind));
        }
    }

    /// Fold a file in by CONTENT, not stat: for inputs that generators
    /// rewrite on every build through paths the tools cannot make
    /// mtime-stable (e.g. etc/DOC via UpdateSourceFiles).  Content-hash
    /// keeps the stamp fresh across no-op rewrites.
    pub fn fileContent(self: *Finger, io: std.Io, dir: std.Io.Dir, gpa: std.mem.Allocator, path: []const u8) void {
        const data = dir.readFileAlloc(io, path, gpa, .limited(64 * 1024 * 1024)) catch {
            self.bytes("\x00missing");
            self.bytes(path);
            return;
        };
        defer gpa.free(data);
        self.bytes(path);
        var n: usize = data.len;
        self.h.update(std.mem.asBytes(&n));
        self.h.update(data);
    }

    pub fn final(self: *Finger) u64 {
        return self.h.final();
    }

    const Entry = struct {
        path: []const u8,
        size: u64,
        mtime_ns: i128,
        kind: std.Io.File.Kind,

        fn lessThan(_: void, a: Entry, b: Entry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    };

    fn collect(
        io: std.Io,
        gpa: std.mem.Allocator,
        dir: std.Io.Dir,
        path: []const u8,
        exclude: ?*const fn (rel: []const u8) bool,
        out: *std.ArrayList(Entry),
    ) !void {
        if (exclude) |f| if (f(path)) return;
        const st = dir.statFile(io, path, .{}) catch return;
        try out.append(gpa, .{
            .path = try gpa.dupe(u8, path),
            .size = st.size,
            .mtime_ns = st.mtime.nanoseconds,
            .kind = st.kind,
        });
        if (st.kind != .directory) return;
        var d = dir.openDir(io, path, .{ .iterate = true }) catch return;
        defer d.close(io);
        var w = try d.walk(gpa);
        defer w.deinit();
        while (w.next(io) catch null) |entry| {
            if (exclude) |f| if (f(entry.path)) continue;
            const st2 = d.statFile(io, entry.path, .{}) catch continue;
            try out.append(gpa, .{
                .path = try joinRel(gpa, path, entry.path),
                .size = st2.size,
                .mtime_ns = st2.mtime.nanoseconds,
                .kind = st2.kind,
            });
        }
    }

    fn joinRel(gpa: std.mem.Allocator, root: []const u8, rel: []const u8) ![]const u8 {
        if (root.len == 0 or std.mem.eql(u8, root, ".")) return gpa.dupe(u8, rel);
        return std.fs.path.join(gpa, &.{ root, rel });
    }
};

fn stampPath(gpa: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fs.path.join(gpa, &.{ "zig-out", ".stamps", name });
}

/// Why-not-fresh diagnostics: one line per invalidated stamp, printed
/// to stderr (a converged no-op build prints nothing).
fn trace(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
}

/// True when the stamp named `name` records `hash` and every output it
/// listed still exists.  All paths are relative to the repo root (cwd).
pub fn isFresh(io: std.Io, gpa: std.mem.Allocator, cwd: std.Io.Dir, name: []const u8, hash: u64) bool {
    const path = stampPath(gpa, name) catch return false;
    defer gpa.free(path);
    const text = cwd.readFileAlloc(io, path, gpa, .limited(1024 * 1024)) catch {
        trace("stamp {s}: no stamp file ({s})\n", .{ name, path });
        return false;
    };
    defer gpa.free(text);
    var lines = std.mem.splitScalar(u8, text, '\n');
    const first = lines.next() orelse return false;
    const recorded = std.fmt.parseInt(u64, std.mem.trim(u8, first, " \r"), 16) catch return false;
    if (recorded != hash) {
        trace("stamp {s}: hash mismatch recorded={x} computed={x}\n", .{ name, recorded, hash });
        return false;
    }
    while (lines.next()) |line| {
        const out = std.mem.trim(u8, line, " \r");
        if (out.len == 0) continue;
        _ = cwd.statFile(io, out, .{}) catch {
            trace("stamp {s}: recorded output missing: {s}\n", .{ name, out });
            return false;
        };
    }
    return true;
}

/// Record `hash` and the produced `outputs` under zig-out/.stamps/.
/// Called after a successful real run.
pub fn mark(io: std.Io, gpa: std.mem.Allocator, cwd: std.Io.Dir, name: []const u8, hash: u64, outputs: []const []const u8) void {
    const dir_path = std.fs.path.join(gpa, &.{ "zig-out", ".stamps" }) catch return;
    defer gpa.free(dir_path);
    cwd.createDirPath(io, dir_path) catch {};
    const path = stampPath(gpa, name) catch return;
    defer gpa.free(path);
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    buf.print(gpa, "{x}\n", .{hash}) catch return;
    for (outputs) |o| buf.print(gpa, "{s}\n", .{o}) catch return;
    cwd.writeFile(io, .{ .sub_path = path, .data = buf.items }) catch {};
}

/// Write `data` only when it differs from the file's current content,
/// preserving the mtime of identical outputs.  The tree-writing
/// generators must use this: their Run steps re-execute on every build,
/// and an unconditional rewrite churns mtimes that downstream freshness
/// stamps (and make-style .el/.elc comparisons) depend on.  Returns
/// true when the file was actually written.
pub fn writeFileIfChanged(io: std.Io, gpa: std.mem.Allocator, cwd: std.Io.Dir, sub_path: []const u8, data: []const u8) !bool {
    if (cwd.readFileAlloc(io, sub_path, gpa, .limited(data.len + 1))) |existing| {
        defer gpa.free(existing);
        if (std.mem.eql(u8, existing, data)) return false;
    } else |_| {}
    try cwd.writeFile(io, .{ .sub_path = sub_path, .data = data });
    return true;
}
