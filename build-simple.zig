const std = @import("std");

pub fn build(b: *std.Build) void {
    fn runTestStep(b: *std.Build, test_file: []const u8, test_name: []const u8) !std.Build.Step.Run {
        const log_file = b.fmt("{s}.log", test_name);
        const log_path = b.path(b.fmt("test/{s}", log_file));

        const run_test = b.addSystemCommand(&[_][]const u8{
            "sh", "-c",
            b.fmt(
                \\cd test && HOME=/nonexistent EMACS_TEST_DIRECTORY=$(pwd) {0} --batch \\
                -L . -L ../lisp -l ert -l {1} -f ert-run-tests-batch-and-exit 2>&1 | tee {2} | tail -5
            , test_file, test_name, log_path
            ),
        });

        run_test.setCwd(b.path("."));
        run_test.has_side_effects = true;

        return run_test;
    }
}
