const std = @import("std");

pub fn build(b: *std.Build) void {
    b.default_step = b.step("build", "Build temacs");
    const build_step = b.addExecutable(.{
        .name = "temacs",
        .root_module = b.createModule(.{
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
        }),
    });
    b.installArtifact(build_step);

    const test_step = b.step("test", "Run all tests");
    const run_tests = b.addSystemCommand(&[_][]const u8{
        "sh",
        "run-zig-tests.sh",
    });
    test_step.dependOn(&run_tests.step);

    const help_step = b.step("help", "Show build information");
    const help_cmd = b.addSystemCommand(&[_][]const u8{
        "echo",
        "Emacs Zig Native Build System",
        "============================",
        "",
        "Available steps:",
        "  zig build      - Build temacs",
        "  zig build test  - Run all tests",
        "  zig build help  - Show this message",
        "",
        "Note: run-zig-tests.sh supports TEST_SELECTOR env var",
    });
    help_step.dependOn(&help_cmd.step);
}
