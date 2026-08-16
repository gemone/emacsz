const std = @import("std");

// This package provides the MSVC POSIX-name provider as source (see
// src/posix.zig).  The root build.zig builds it into a static library that
// it links into the MSVC command-line tools via
// `b.dependency("msvc_posix", .{}).path("src/posix.zig")`, so this build.zig
// has no steps of its own to declare.
pub fn build(b: *std.Build) void {
    _ = b;
}
