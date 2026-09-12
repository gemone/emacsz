const std = @import("std");

extern "c" fn proto_ui_tpe_core_test_run() c_int;

test "generic terminal provider registry validates and dispatches lifecycle" {
    try std.testing.expectEqual(@as(c_int, 0), proto_ui_tpe_core_test_run());
}
