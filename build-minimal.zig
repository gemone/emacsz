const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Run test");
    const cmd = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        "cd test && HOME=/nonexistent EMACS_TEST_DIRECTORY=$(pwd) ../zig-out/bin/temacs --batch -L . -L ../lisp -l ert -l lisp/abbrev-tests.el -f ert-run-tests-batch-and-exit 2>&1",
    });
    cmd.setCwd(b.path("."));
    test_step.dependOn(&cmd);
}
