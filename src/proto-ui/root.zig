pub const protocol = @import("protocol.zig");
pub const capability = @import("capability.zig");
pub const lifecycle = @import("lifecycle.zig");
pub const frontend = @import("frontend.zig");
pub const facts = @import("facts.zig");
pub const renderer = @import("renderer.zig");
pub const input = @import("input.zig");
pub const adapter = @import("adapter.zig");
pub const transport = @import("transport.zig");
pub const live = @import("live.zig");
pub const terminal = @import("terminal.zig");
pub const frame_service = @import("frame_service.zig");
pub const runtime = @import("runtime.zig");
pub const capture_service = @import("capture_service.zig");
pub const host_contract = @import("host_contract.zig");

test {
    _ = protocol;
    _ = capability;
    _ = lifecycle;
    _ = frontend;
    _ = facts;
    _ = renderer;
    _ = input;
    _ = adapter;
    _ = transport;
    _ = live;
    _ = terminal;
    _ = frame_service;
    _ = runtime;
    _ = capture_service;
    _ = host_contract;
}
