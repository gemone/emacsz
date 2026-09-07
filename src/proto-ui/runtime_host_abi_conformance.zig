//! Zig harness for the generated C ABI conformance translation unit.

const std = @import("std");

extern fn proto_ui_pure_runtime_host_abi_conformance() c_int;

test "generated PureRuntimeHostV1 C ABI conformance" {
    try std.testing.expectEqual(@as(c_int, 0), proto_ui_pure_runtime_host_abi_conformance());
}
