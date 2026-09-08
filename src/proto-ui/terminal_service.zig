//! Adapter-owned orchestration of the PureRuntimeHostV1 terminal group.
//!
//! This service exercises and bounds terminal create/activate/drain/delete
//! sequencing against a reviewed host table.  It does not select an Emacs host,
//! approve R7, initialize PGTK, or make `output_proto` runtime available.

const std = @import("std");
const runtime_host = @import("runtime_host.zig");
const terminal = @import("terminal.zig");

pub const Error = runtime_host.Error || terminal.Error || error{
    InvalidServiceState,
    InvalidHostIdentity,
    TerminalIdSpaceExhausted,
};

pub const State = enum {
    idle,
    registering,
    active,
    draining,
    rollback_pending,
};

pub const Counters = struct {
    created: u64 = 0,
    activated: u64 = 0,
    drained: u64 = 0,
    drained_retries: u64 = 0,
    rolled_back: u64 = 0,
};

pub const TerminalService = struct {
    table: runtime_host.PureRuntimeHostV1,
    terminals: *terminal.TerminalRegistry,
    host_identity: ?runtime_host.Identity = null,
    registry_terminal_id: ?u32 = null,
    next_registry_terminal_id: u32 = 1,
    state: State = .idle,
    counters: Counters = .{},

    pub fn init(
        table: runtime_host.PureRuntimeHostV1,
        terminals: *terminal.TerminalRegistry,
    ) Error!TerminalService {
        try runtime_host.validateTable(&table);
        return .{ .table = table, .terminals = terminals };
    }

    fn terminalGroup(self: *const TerminalService) Error!*const runtime_host.TerminalGroupV1 {
        return self.table.terminal orelse error.InvalidServiceState;
    }

    fn callIdentity(
        self: *const TerminalService,
        comptime field: []const u8,
        identity: runtime_host.Identity,
    ) Error!void {
        const group = try self.terminalGroup();
        const callback = @field(group, field) orelse return error.InvalidServiceState;
        const context = group.context orelse return error.InvalidServiceState;
        try runtime_host.ensureOk(callback(context, &identity));
    }

    fn nextRegistryTerminalId(self: *TerminalService) Error!u32 {
        while (true) {
            if (self.next_registry_terminal_id == 0) return error.TerminalIdSpaceExhausted;
            const candidate = self.next_registry_terminal_id;
            self.next_registry_terminal_id = if (candidate == std.math.maxInt(u32))
                0
            else
                candidate + 1;
            if (self.terminals.lookup(candidate) == null) return candidate;
        }
    }

    fn rollbackHostTerminal(self: *TerminalService) Error!void {
        const host = self.host_identity orelse return error.InvalidHostIdentity;
        self.callIdentity("delete_terminal", host) catch |err| {
            self.state = .rollback_pending;
            return err;
        };
        self.host_identity = null;
        self.counters.rolled_back += 1;
    }

    pub fn create(self: *TerminalService, requested_generation: u32) Error!terminal.Terminal {
        switch (self.state) {
            .idle => {},
            .rollback_pending => return error.InvalidServiceState,
            else => return error.InvalidServiceState,
        }
        const request: runtime_host.TerminalCreateRequest = .{
            .requested_generation = requested_generation,
        };
        runtime_host.validateTerminalCreate(&request) catch
            return error.InvalidHostIdentity;
        const group = try self.terminalGroup();
        const callback = group.create_terminal orelse return error.InvalidServiceState;
        const context = group.context orelse return error.InvalidServiceState;
        var host: runtime_host.Identity = .{};
        try runtime_host.ensureOk(callback(context, &request, &host));
        try runtime_host.validateIdentity(&host);
        self.host_identity = host;

        const registry_id = try self.nextRegistryTerminalId();
        self.terminals.create(registry_id, terminal.initial_generation) catch |err| {
            self.rollbackHostTerminal() catch {};
            return err;
        };
        self.registry_terminal_id = registry_id;
        self.state = .registering;
        self.counters.created += 1;
        return self.terminals.lookup(registry_id).?;
    }

    pub fn activate(self: *TerminalService) Error!terminal.Terminal {
        if (self.state != .registering) return error.InvalidServiceState;
        const registry_id = self.registry_terminal_id orelse return error.InvalidServiceState;
        const host = self.host_identity orelse return error.InvalidHostIdentity;
        const current = self.terminals.lookup(registry_id) orelse return error.InvalidServiceState;
        try self.callIdentity("activate_terminal", host);
        _ = try self.terminals.activate(registry_id, current.generation);
        self.state = .active;
        self.counters.activated += 1;
        return self.terminals.lookup(registry_id).?;
    }

    pub fn drain(self: *TerminalService) Error!terminal.Terminal {
        const registry_id = self.registry_terminal_id orelse return error.InvalidServiceState;
        const record = self.terminals.lookup(registry_id) orelse return error.InvalidServiceState;
        const generation = switch (self.state) {
            .active => blk: {
                const generation = try self.terminals.beginDrain(registry_id, record.generation);
                self.state = .draining;
                break :blk generation;
            },
            .draining => blk: {
                self.counters.drained_retries += 1;
                break :blk record.generation;
            },
            else => return error.InvalidServiceState,
        };
        const host = self.host_identity orelse return error.InvalidHostIdentity;
        self.callIdentity("delete_terminal", host) catch |err| {
            self.state = .draining;
            return err;
        };
        _ = try self.terminals.detach(registry_id, generation);
        self.host_identity = null;
        self.registry_terminal_id = null;
        self.state = .idle;
        self.counters.drained += 1;
        return self.terminals.lookup(registry_id).?;
    }

    pub fn completeRollback(self: *TerminalService) Error!void {
        if (self.state != .rollback_pending) return error.InvalidServiceState;
        try self.rollbackHostTerminal();
        self.state = .idle;
    }

    pub fn activeTerminal(self: *const TerminalService) Error!terminal.Terminal {
        if (self.state != .active) return error.InvalidServiceState;
        const registry_id = self.registry_terminal_id orelse return error.InvalidServiceState;
        return self.terminals.lookup(registry_id) orelse error.InvalidServiceState;
    }
};

test "terminal service completes bounded host lifecycle and retains retired IDs" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var terminals: terminal.TerminalRegistry = .{};
    var service = try TerminalService.init(table, &terminals);

    const created = try service.create(terminal.initial_generation);
    try std.testing.expectEqual(terminal.TerminalState.registering, created.state);
    try std.testing.expectEqual(@as(u32, 1), created.id);
    try std.testing.expectEqual(runtime_host.TerminalState.active, host.terminal);

    const active = try service.activate();
    try std.testing.expectEqual(terminal.TerminalState.active, active.state);
    try std.testing.expectEqual(@as(u32, 2), active.generation);
    try std.testing.expectEqual(active, try service.activeTerminal());

    const drained = try service.drain();
    try std.testing.expectEqual(terminal.TerminalState.deleted, drained.state);
    try std.testing.expectEqual(@as(u32, 4), drained.generation);
    try std.testing.expectEqual(runtime_host.TerminalState.deleted, host.terminal);
    try std.testing.expectEqual(State.idle, service.state);
    try std.testing.expectEqual(
        Counters{ .created = 1, .activated = 1, .drained = 1 },
        service.counters,
    );

    try std.testing.expectEqual(@as(u32, 2), service.next_registry_terminal_id);
}

test "terminal service retains draining state when host deletion fails" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var terminals: terminal.TerminalRegistry = .{};
    var service = try TerminalService.init(table, &terminals);

    _ = try service.create(terminal.initial_generation);
    _ = try service.activate();
    host.force_failure = true;
    try std.testing.expectError(error.HostCallbackFailed, service.drain());
    try std.testing.expectEqual(State.draining, service.state);
    try std.testing.expectEqual(terminal.TerminalState.draining, terminals.lookup(1).?.state);

    host.force_failure = false;
    const drained = try service.drain();
    try std.testing.expectEqual(terminal.TerminalState.deleted, drained.state);
    try std.testing.expectEqual(@as(u64, 1), service.counters.drained_retries);
}

test "terminal service rolls back an unregistrable host terminal" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var terminals: terminal.TerminalRegistry = .{};
    for (1..terminal.max_terminals + 1) |id| {
        terminals.terminals[id - 1] = .{
            .id = @intCast(id),
            .generation = 2,
            .state = .deleted,
        };
    }
    terminals.len = terminal.max_terminals;
    var service = try TerminalService.init(table, &terminals);

    try std.testing.expectError(terminal.Error.TerminalTableFull, service.create(1));
    try std.testing.expectEqual(State.idle, service.state);
    try std.testing.expectEqual(runtime_host.TerminalState.deleted, host.terminal);
    try std.testing.expectEqual(@as(u64, 1), service.counters.rolled_back);
}

fn successfulTerminalCreate(
    context: *anyopaque,
    request: *const runtime_host.TerminalCreateRequest,
    result: *runtime_host.Identity,
) callconv(.c) runtime_host.Status {
    _ = context;
    result.* = .{ .id = 1, .generation = request.requested_generation };
    return .ok;
}

fn failedTerminalDelete(
    context: *anyopaque,
    identity: *const runtime_host.Identity,
) callconv(.c) runtime_host.Status {
    _ = context;
    _ = identity;
    return .failed;
}

fn successfulTerminalDelete(
    context: *anyopaque,
    identity: *const runtime_host.Identity,
) callconv(.c) runtime_host.Status {
    _ = context;
    _ = identity;
    return .ok;
}

test "terminal service can complete rollback pending cleanup" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var terminals: terminal.TerminalRegistry = .{};
    for (1..terminal.max_terminals + 1) |id| {
        terminals.terminals[id - 1] = .{
            .id = @intCast(id),
            .generation = 2,
            .state = .deleted,
        };
    }
    terminals.len = terminal.max_terminals;
    host.terminal_group.create_terminal = successfulTerminalCreate;
    host.terminal_group.delete_terminal = failedTerminalDelete;
    var service = try TerminalService.init(table, &terminals);

    try std.testing.expectError(terminal.Error.TerminalTableFull, service.create(1));
    try std.testing.expectEqual(State.rollback_pending, service.state);
    try std.testing.expect(service.host_identity != null);
    try std.testing.expectError(error.HostCallbackFailed, service.completeRollback());
    try std.testing.expectEqual(State.rollback_pending, service.state);

    host.terminal_group.delete_terminal = successfulTerminalDelete;
    try service.completeRollback();
    try std.testing.expectEqual(State.idle, service.state);
    try std.testing.expectEqual(@as(u64, 1), service.counters.rolled_back);
}
