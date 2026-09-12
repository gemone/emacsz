//! Exercises the exported candidate adapter session ABI and keeps registration fail closed.

const std = @import("std");
const proto_ui = @import("proto_ui");

const Identity = extern struct {
    id: u64 = 0,
    generation: u64 = 0,
};

extern fn proto_ui_runtime_host_adapter_abi_version() u32;
extern fn proto_ui_runtime_host_adapter_table_size() usize;
extern fn proto_ui_runtime_host_adapter_validate(table: ?*const anyopaque) c_int;
extern fn proto_ui_runtime_host_adapter_create() c_int;
extern fn proto_ui_runtime_host_adapter_session_create(table: ?*const anyopaque, out: *?*anyopaque) c_int;
extern fn proto_ui_runtime_host_adapter_session_activate(handle: ?*anyopaque, out_terminal: ?*Identity) c_int;
extern fn proto_ui_runtime_host_adapter_session_drain(handle: ?*anyopaque) c_int;
extern fn proto_ui_runtime_host_adapter_session_destroy(handle: ?*anyopaque) c_int;

pub fn main(minimal: std.process.Init.Minimal) !void {
    _ = minimal;
    var host: proto_ui.runtime_host.FakeHost = undefined;
    const table = proto_ui.runtime_host.fakeTable(&host);
    const expected_table_size = proto_ui.r8_adapter_linkage.table_size;
    var handle: ?*anyopaque = null;
    var terminal: Identity = .{};
    var recreated: Identity = .{};

    if (proto_ui_runtime_host_adapter_abi_version() != 1 or
        proto_ui_runtime_host_adapter_table_size() != expected_table_size or
        proto_ui_runtime_host_adapter_validate(null) != 1 or
        proto_ui_runtime_host_adapter_create() != 4 or
        proto_ui_runtime_host_adapter_session_create(null, &handle) != 1 or
        proto_ui_runtime_host_adapter_session_create(&table, &handle) != 0 or
        handle == null or
        proto_ui_runtime_host_adapter_session_activate(handle, &terminal) != 0 or
        terminal.id == 0 or terminal.generation == 0 or
        host.terminal != .active or
        proto_ui_runtime_host_adapter_session_drain(handle) != 0 or
        host.terminal != .deleted or
        proto_ui_runtime_host_adapter_session_activate(handle, &recreated) != 0 or
        recreated.id <= terminal.id or
        recreated.generation == 0 or
        host.terminal != .active or
        proto_ui_runtime_host_adapter_session_drain(handle) != 0 or
        proto_ui_runtime_host_adapter_session_destroy(handle) != 0)
    {
        std.debug.print("runtime-host-adapter probe: unexpected exported ABI\n", .{});
        return error.InvalidRuntimeHostAdapter;
    }

    std.debug.print(
        "{{\"probe\":\"runtime-host-adapter\",\"abi_version\":1,\"table_size\":{d},\"null_table_rejected\":true,\"no_table_creation_blocked\":true,\"session_created\":true,\"terminal_activated\":true,\"terminal_drained\":true,\"terminal_recreated\":true,\"terminal_id_not_reused\":true,\"emacs_registered\":false,\"runtime_available\":false,\"result\":\"pass\"}}\n",
        .{expected_table_size},
    );
}
