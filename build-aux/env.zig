//! Parent-environment inheritance for child temacs spawns.
//!
//! Zig's std.process.spawn passes an empty environment on POSIX when no
//! environ_map is given (the Io.Threaded default environ block is
//! empty), so tools that spawn temacs without a map silently drop
//! TMPDIR, PATH and every other variable -- which broke the macOS ert
//! tests that need a writable temporary-file-directory.  Copy the
//! process environment (provided to main via Init.Minimal) and pass the
//! map to every spawn so children keep the parent session.

const std = @import("std");

pub fn inherit(gpa: std.mem.Allocator, minimal: std.process.Init.Minimal) !std.process.Environ.Map {
    return std.process.Environ.createMap(minimal.environ, gpa);
}
