//! Loads the exported candidate adapter ABI and keeps creation fail closed.

const std = @import("std");
const proto_ui = @import("proto_ui");

extern fn proto_ui_runtime_host_adapter_abi_version() u32;
extern fn proto_ui_runtime_host_adapter_table_size() usize;
extern fn proto_ui_runtime_host_adapter_validate(table: ?*const anyopaque) c_int;
extern fn proto_ui_runtime_host_adapter_create() c_int;

pub fn main(minimal: std.process.Init.Minimal) !void {
    _ = minimal;
    const expected_table_size = proto_ui.r8_adapter_linkage.table_size;

    if (proto_ui_runtime_host_adapter_abi_version() != 1 or
        proto_ui_runtime_host_adapter_table_size() != expected_table_size or
        proto_ui_runtime_host_adapter_validate(null) != 1 or
        proto_ui_runtime_host_adapter_create() != 2)
    {
        std.debug.print("runtime-host-adapter probe: unexpected exported ABI\n", .{});
        return error.InvalidRuntimeHostAdapter;
    }
    std.debug.print(
        "{{\"probe\":\"runtime-host-adapter\",\"abi_version\":1,\"table_size\":{d},\"null_table_rejected\":true,\"creation_blocked\":true,\"result\":\"pass\"}}\n",
        .{expected_table_size},
    );
}
