// zeln-compile: the native-compilation tool for the HAVE_NATIVE_COMP_ZIG
// path (produces `.zeln` from a zunit). It is a separate process per the
// C<->Zig boundary (plan section 4.1): temacs serializes a zunit; this
// tool parses it, emits LLVM IR (`.ll`), drives `zig cc -shared` to
// produce the `.zeln`, and writes it to `.zeln-cache/`.
//
// This is the M0/scaffold skeleton: it only proves the package resolves
// and compiles under Zig 0.16. M0 replaces this with the real zunit
// parser + `.ll` emitter + `zig cc` driver; the scaffold only needs the
// skeleton to build.
const std = @import("std");

pub fn main(minimal: std.process.Init.Minimal) !void {
    _ = minimal;
}
