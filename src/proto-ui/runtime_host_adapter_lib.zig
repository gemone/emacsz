//! Candidate R8 runtime-host adapter artifact.
//!
//! This candidate library validates a caller-supplied PureRuntimeHostV1 table
//! and deliberately refuses adapter creation.  It has no load-time initializer;
//! when explicitly linked into temacs, inherited Emacs never calls it.  It also
//! cannot register a terminal or enable Proto-UI runtime.

const runtime_host = @import("runtime_host.zig");

export fn proto_ui_runtime_host_adapter_abi_version() u32 {
    return runtime_host.abi_version;
}

export fn proto_ui_runtime_host_adapter_table_size() usize {
    return @sizeOf(runtime_host.PureRuntimeHostV1);
}

export fn proto_ui_runtime_host_adapter_validate(
    table: ?*const runtime_host.PureRuntimeHostV1,
) c_int {
    runtime_host.validateTable(table) catch return 1;
    return 0;
}

export fn proto_ui_runtime_host_adapter_create() c_int {
    // Adapter creation is the R8 activation boundary.  Remain fail closed until
    // a reviewed registration path explicitly calls this candidate; linkage
    // alone must never activate it.
    return 2;
}

test "candidate adapter rejects absent table and refuses creation" {
    var host: runtime_host.FakeHost = undefined;
    const valid_table = runtime_host.fakeTable(&host);
    const create: *const fn () callconv(.c) c_int = proto_ui_runtime_host_adapter_create;
    try std.testing.expectEqual(@as(c_int, 0), proto_ui_runtime_host_adapter_validate(&valid_table));
    try std.testing.expectEqual(@as(c_int, 1), proto_ui_runtime_host_adapter_validate(null));
    try std.testing.expectEqual(@as(c_int, 2), create());
}

const std = @import("std");
