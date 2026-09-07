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
pub const runtime = @import("runtime.zig");

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
    _ = runtime;
}
