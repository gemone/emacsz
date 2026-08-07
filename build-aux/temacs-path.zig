//! Shared helper for the build-time tools that spawn temacs: the
//! executable is temacs.exe on Windows hosts and temacs elsewhere.
//! Each tool runs on the build host (make-docfile/check/smoke/... are
//! host tools), so the name must match the host platform.

const std = @import("std");
const builtin = @import("builtin");

pub const name: []const u8 = if (builtin.os.tag == .windows) "temacs.exe" else "temacs";

pub fn joinBin(gpa: std.mem.Allocator, root: []const u8) ![]const u8 {
    return std.fs.path.join(gpa, &.{ root, "zig-out", "bin", name });
}
