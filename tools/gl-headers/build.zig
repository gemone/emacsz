const std = @import("std");

// This package provides the generate-gl-headers build tool as source.
// The consumer (the root build.zig) builds the tool executable from
// src/main.zig via `dep.path("src/main.zig")`, so this build.zig has
// no steps to declare.
pub fn build(b: *std.Build) void {
    _ = b;
}
