//! Adapter-owned terminal identity and cleanup state machine.

const std = @import("std");

pub const Error = error{
    InvalidGeneration,
    InvalidId,
    InvalidTransition,
    StaleGeneration,
    TerminalAlreadyExists,
    TerminalNotLive,
    TerminalTableFull,
};

pub const max_terminals: usize = 8;
pub const initial_generation: u32 = 1;

pub const TerminalState = enum(u8) {
    registering = 1,
    active = 2,
    draining = 3,
    failed = 4,
    deleted = 5,
};

pub const Terminal = struct {
    id: u32,
    generation: u32,
    state: TerminalState,
};

pub const Counters = struct {
    created: u64 = 0,
    activated: u64 = 0,
    drained: u64 = 0,
    detached: u64 = 0,
    failed: u64 = 0,
    cleanup_completed: u64 = 0,
};

pub const TerminalRegistry = struct {
    terminals: [max_terminals]Terminal = undefined,
    len: usize = 0,
    counters: Counters = .{},

    pub fn reset(self: *TerminalRegistry) void {
        self.* = .{};
    }

    pub fn lookup(self: TerminalRegistry, id: u32) ?Terminal {
        const index = self.findIndex(id) orelse return null;
        return self.terminals[index];
    }

    pub fn activeTerminal(self: TerminalRegistry) ?Terminal {
        for (self.terminals[0..self.len]) |terminal| {
            if (terminal.state == .active) return terminal;
        }
        return null;
    }

    /// Registration starts at generation 1. Every successful lifecycle
    /// transition advances that terminal's generation, and terminal records are
    /// retained so neither failed nor deleted IDs can ever be reused.
    pub fn create(self: *TerminalRegistry, id: u32, generation: u32) Error!void {
        if (id == 0) return Error.InvalidId;
        if (generation == 0) return Error.InvalidGeneration;
        if (generation != initial_generation) return Error.StaleGeneration;
        if (self.liveIndex() != null) return Error.TerminalAlreadyExists;
        if (self.findIndex(id) != null) return Error.TerminalAlreadyExists;
        if (self.len == max_terminals) return Error.TerminalTableFull;
        self.terminals[self.len] = .{ .id = id, .generation = generation, .state = .registering };
        self.len += 1;
        self.counters.created += 1;
    }

    pub fn activate(self: *TerminalRegistry, id: u32, expected_generation: u32) Error!u32 {
        return self.transition(id, expected_generation, .registering, .active, .activated);
    }

    pub fn beginDrain(self: *TerminalRegistry, id: u32, expected_generation: u32) Error!u32 {
        return self.transition(id, expected_generation, .active, .draining, .drained);
    }

    pub fn detach(self: *TerminalRegistry, id: u32, expected_generation: u32) Error!u32 {
        return self.transition(id, expected_generation, .draining, .deleted, .detached);
    }

    pub fn fail(self: *TerminalRegistry, id: u32, expected_generation: u32) Error!u32 {
        if (expected_generation == 0) return Error.InvalidGeneration;
        const index = self.mutableIndex(id) orelse return Error.TerminalNotLive;
        if (self.terminals[index].generation != expected_generation) return Error.StaleGeneration;
        if (self.terminals[index].state == .failed or self.terminals[index].state == .deleted) {
            return Error.InvalidTransition;
        }
        self.terminals[index].state = .failed;
        const generation = advance(&self.terminals[index]);
        self.counters.failed += 1;
        return generation;
    }

    pub fn completeCleanup(self: *TerminalRegistry, id: u32, expected_generation: u32) Error!u32 {
        return self.transition(id, expected_generation, .failed, .deleted, .cleanup_completed);
    }

    fn transition(
        self: *TerminalRegistry,
        id: u32,
        expected_generation: u32,
        required_state: TerminalState,
        next_state: TerminalState,
        counter: CounterKind,
    ) Error!u32 {
        if (expected_generation == 0) return Error.InvalidGeneration;
        const index = self.mutableIndex(id) orelse return Error.TerminalNotLive;
        if (self.terminals[index].generation != expected_generation) return Error.StaleGeneration;
        if (self.terminals[index].state != required_state) return Error.InvalidTransition;
        self.terminals[index].state = next_state;
        const generation = advance(&self.terminals[index]);
        switch (counter) {
            .activated => self.counters.activated += 1,
            .drained => self.counters.drained += 1,
            .detached => self.counters.detached += 1,
            .cleanup_completed => self.counters.cleanup_completed += 1,
        }
        return generation;
    }

    fn advance(terminal: *Terminal) Error!u32 {
        if (terminal.generation == std.math.maxInt(u32)) {
            // Keep the terminal quarantined; generation overflow can never be
            // represented and therefore cannot safely leave the state.
            terminal.state = .failed;
            return Error.InvalidGeneration;
        }
        terminal.generation += 1;
        return terminal.generation;
    }

    fn findIndex(self: TerminalRegistry, id: u32) ?usize {
        for (self.terminals[0..self.len], 0..) |terminal, index| {
            if (terminal.id == id) return index;
        }
        return null;
    }

    fn mutableIndex(self: TerminalRegistry, id: u32) ?usize {
        return self.findIndex(id);
    }

    fn liveIndex(self: TerminalRegistry) ?usize {
        for (self.terminals[0..self.len], 0..) |terminal, index| {
            if (terminal.state == .registering or terminal.state == .active or terminal.state == .draining) {
                return index;
            }
        }
        return null;
    }
};

const CounterKind = enum {
    activated,
    drained,
    detached,
    cleanup_completed,
};

test "terminal completes the normal lifecycle with increasing generations" {
    var registry: TerminalRegistry = .{};
    try registry.create(7, initial_generation);
    try std.testing.expectEqual(TerminalState.registering, registry.lookup(7).?.state);
    try std.testing.expectEqual(@as(u32, 2), try registry.activate(7, 1));
    try std.testing.expectEqual(TerminalState.active, registry.lookup(7).?.state);
    try std.testing.expectError(Error.InvalidTransition, registry.activate(7, 2));
    try std.testing.expectError(Error.StaleGeneration, registry.beginDrain(7, 1));
    try std.testing.expectEqual(TerminalState.active, registry.lookup(7).?.state);

    try std.testing.expectEqual(@as(u32, 3), try registry.beginDrain(7, 2));
    try std.testing.expectEqual(TerminalState.draining, registry.lookup(7).?.state);
    try std.testing.expectEqual(@as(u32, 4), try registry.detach(7, 3));
    try std.testing.expectEqual(TerminalState.deleted, registry.lookup(7).?.state);
    try std.testing.expectEqual(Counters{ .created = 1, .activated = 1, .drained = 1, .detached = 1 }, registry.counters);
}

test "terminal failure and cleanup quarantine without ID reuse" {
    var registry: TerminalRegistry = .{};
    try registry.create(3, initial_generation);
    try std.testing.expectEqual(@as(u32, 2), try registry.fail(3, 1));
    try std.testing.expectEqual(TerminalState.failed, registry.lookup(3).?.state);
    try std.testing.expectEqual(@as(u32, 3), try registry.completeCleanup(3, 2));
    try std.testing.expectEqual(TerminalState.deleted, registry.lookup(3).?.state);
    try std.testing.expectEqual(Counters{ .created = 1, .failed = 1, .cleanup_completed = 1 }, registry.counters);

    try std.testing.expectError(Error.TerminalAlreadyExists, registry.create(3, initial_generation));
    try std.testing.expectEqual(TerminalState.deleted, registry.lookup(3).?.state);
}

test "terminal rejects invalid and out-of-order transitions" {
    var registry: TerminalRegistry = .{};
    try std.testing.expectError(Error.InvalidId, registry.create(0, initial_generation));
    try std.testing.expectError(Error.InvalidGeneration, registry.create(1, 0));
    try std.testing.expectError(Error.StaleGeneration, registry.create(1, 2));
    try std.testing.expectError(Error.TerminalNotLive, registry.activate(1, 1));

    try registry.create(1, initial_generation);
    try std.testing.expectError(Error.InvalidTransition, registry.beginDrain(1, 1));
    try std.testing.expectError(Error.InvalidTransition, registry.detach(1, 1));
    try std.testing.expectError(Error.InvalidTransition, registry.completeCleanup(1, 1));

    try std.testing.expectEqual(@as(u32, 2), try registry.activate(1, 1));
    try std.testing.expectError(Error.StaleGeneration, registry.activate(1, 1));
    try std.testing.expectError(Error.InvalidTransition, registry.activate(1, 2));
    try std.testing.expectError(Error.InvalidGeneration, registry.fail(1, 0));
}

test "terminal permits only one live terminal and never reuses IDs" {
    var registry: TerminalRegistry = .{};
    try registry.create(1, initial_generation);
    try std.testing.expect(registry.activeTerminal() == null);
    try std.testing.expectError(Error.TerminalAlreadyExists, registry.create(2, initial_generation));
    try std.testing.expectError(Error.TerminalAlreadyExists, registry.create(1, initial_generation));

    _ = try registry.activate(1, 1);
    try std.testing.expectEqual(registry.lookup(1), registry.activeTerminal());
    try std.testing.expectError(Error.TerminalAlreadyExists, registry.create(2, initial_generation));
    try std.testing.expectError(Error.TerminalAlreadyExists, registry.create(1, initial_generation));

    const draining = try registry.beginDrain(1, 2);
    _ = try registry.detach(1, draining);
    try std.testing.expect(registry.activeTerminal() == null);
    try std.testing.expectError(Error.TerminalAlreadyExists, registry.create(1, initial_generation));
    try registry.create(2, initial_generation);
    try std.testing.expectEqual(TerminalState.registering, registry.lookup(2).?.state);
    try std.testing.expectEqual(TerminalState.deleted, registry.lookup(1).?.state);
}

test "terminal table is bounded and preserves all retained records" {
    var registry: TerminalRegistry = .{};
    for (1..max_terminals + 1) |id| {
        try registry.create(@intCast(id), initial_generation);
        _ = try registry.fail(@intCast(id), 1);
        _ = try registry.completeCleanup(@intCast(id), 2);
    }
    try std.testing.expectEqual(max_terminals, registry.len);
    try std.testing.expectError(Error.TerminalTableFull, registry.create(@intCast(max_terminals + 1), initial_generation));
    try std.testing.expectEqual(@as(u64, max_terminals), registry.counters.created);
    try std.testing.expectEqual(@as(u64, max_terminals), registry.counters.failed);
    try std.testing.expectEqual(@as(u64, max_terminals), registry.counters.cleanup_completed);

    registry.reset();
    try std.testing.expectEqual(@as(usize, 0), registry.len);
    try std.testing.expectEqual(Counters{}, registry.counters);
    try registry.create(1, initial_generation);
}

test "terminal generation overflow quarantines instead of wrapping" {
    var registry: TerminalRegistry = .{};
    registry.terminals[0] = .{ .id = 1, .generation = std.math.maxInt(u32), .state = .active };
    registry.len = 1;
    try std.testing.expectError(Error.InvalidGeneration, registry.beginDrain(1, std.math.maxInt(u32)));
    try std.testing.expectEqual(TerminalState.failed, registry.lookup(1).?.state);
}
