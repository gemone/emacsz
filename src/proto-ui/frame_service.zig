//! Adapter-owned mapping from host frame handles to EUP frame identities.
//!
//! Emacs remains authoritative for frame truth.  This service observes only
//! the reviewed HostV1 callbacks and mirrors the observation into the existing
//! protocol frame registry.  It does not register a terminal, create an
//! output_proto runtime, encode EUP, or touch a transport.

const std = @import("std");
const adapter = @import("adapter.zig");
const lifecycle = @import("lifecycle.zig");
const terminal = @import("terminal.zig");

pub const Error = adapter.Error || lifecycle.Error || terminal.Error || error{
    FrameServiceTableFull,
    UnknownFrameMapping,
};

pub const max_frame_mappings: usize = 8;

pub const Mapping = struct {
    host_handle: u64,
    eup_frame_id: u32,
    host_generation: u64,
    protocol_frame_generation: u32,
    visibility: adapter.FrameVisibility,
    focused: bool,
    active: bool,
};

pub const Counters = struct {
    registered: u64 = 0,
    refreshed: u64 = 0,
    deleted: u64 = 0,
    drained: u64 = 0,
    failures: u64 = 0,
};

pub const FrameService = struct {
    runtime: *adapter.Runtime,
    frames: *lifecycle.FrameRegistry,
    terminals: *terminal.TerminalRegistry,
    terminal_id: u32,
    mappings: [max_frame_mappings]Mapping = undefined,
    len: usize = 0,
    counters: Counters = .{},

    pub fn init(
        runtime: *adapter.Runtime,
        frames: *lifecycle.FrameRegistry,
        terminals: *terminal.TerminalRegistry,
        terminal_id: u32,
    ) Error!FrameService {
        if (terminal_id == 0) return error.InvalidArgument;
        const active = terminals.activeTerminal() orelse return error.TerminalNotLive;
        if (active.id != terminal_id) return error.TerminalNotLive;
        return .{
            .runtime = runtime,
            .frames = frames,
            .terminals = terminals,
            .terminal_id = terminal_id,
        };
    }

    pub fn register(
        self: *FrameService,
        host_handle: u64,
        eup_frame_id: u32,
    ) Error!Mapping {
        if (host_handle == 0 or eup_frame_id == 0) return self.fail(error.InvalidArgument);
        if (self.len == max_frame_mappings) return self.fail(error.FrameServiceTableFull);
        self.requireActiveTerminal() catch |err| return self.fail(err);
        self.findAny(host_handle, eup_frame_id) catch |err| return self.fail(err);

        const observation = self.observe(host_handle) catch |err| return self.fail(err);
        self.frames.createObserved(
            eup_frame_id,
            @intCast(observation.generation),
            protocolVisibility(observation.visibility),
            observation.focused,
        ) catch |err| return self.fail(err);
        const mapping = Mapping{
            .host_handle = host_handle,
            .eup_frame_id = eup_frame_id,
            .host_generation = observation.generation,
            .protocol_frame_generation = @intCast(observation.generation),
            .visibility = observation.visibility,
            .focused = observation.focused,
            .active = true,
        };
        self.mappings[self.len] = mapping;
        self.len += 1;
        self.counters.registered += 1;
        return mapping;
    }

    pub fn refresh(self: *FrameService, host_handle: u64) Error!Mapping {
        const index = self.findActiveHandle(host_handle) orelse
            return self.fail(error.UnknownFrameMapping);
        const observation = self.observe(host_handle) catch |err| return self.fail(err);
        const mapping = self.mappings[index];

        self.frames.advanceObserved(
            mapping.eup_frame_id,
            @intCast(observation.generation),
            protocolVisibility(observation.visibility),
            observation.focused,
        ) catch |err| return self.fail(err);
        self.mappings[index] = .{
            .host_handle = mapping.host_handle,
            .eup_frame_id = mapping.eup_frame_id,
            .host_generation = observation.generation,
            .protocol_frame_generation = @intCast(observation.generation),
            .visibility = observation.visibility,
            .focused = observation.focused,
            .active = true,
        };
        self.counters.refreshed += 1;
        return self.mappings[index];
    }

    pub fn unregister(self: *FrameService, host_handle: u64) Error!void {
        const index = self.findActiveHandle(host_handle) orelse
            return self.fail(error.UnknownFrameMapping);
        const mapping = self.mappings[index];
        const observation = self.observe(host_handle) catch |err| return self.fail(err);
        if (observation.generation != mapping.host_generation)
            return self.fail(error.StaleGeneration);

        self.frames.destroy(mapping.eup_frame_id, mapping.protocol_frame_generation) catch |err|
            return self.fail(err);
        self.mappings[index].active = false;
        self.counters.deleted += 1;
    }

    pub fn drain(self: *FrameService) Error!usize {
        const state = self.terminals.lookup(self.terminal_id) orelse
            return self.fail(error.TerminalNotLive);
        if (state.state != .active and state.state != .draining)
            return self.fail(error.TerminalNotLive);

        var pending: [max_frame_mappings]usize = undefined;
        var pending_count: usize = 0;
        for (self.mappings[0..self.len], 0..) |mapping, index| {
            if (!mapping.active) continue;
            const observation = self.observe(mapping.host_handle) catch |err|
                return self.fail(err);
            if (observation.generation != mapping.host_generation)
                return self.fail(error.StaleGeneration);
            pending[pending_count] = index;
            pending_count += 1;
        }

        for (pending[0..pending_count]) |index| {
            const mapping = self.mappings[index];
            self.frames.destroy(
                mapping.eup_frame_id,
                mapping.protocol_frame_generation,
            ) catch |err| return self.fail(err);
            self.mappings[index].active = false;
            self.counters.drained += 1;
        }
        return pending_count;
    }

    pub fn lookupHost(self: FrameService, host_handle: u64) ?Mapping {
        const index = self.findActiveHandle(host_handle) orelse return null;
        return self.mappings[index];
    }

    pub fn lookupFrame(self: FrameService, eup_frame_id: u32) ?Mapping {
        for (self.mappings[0..self.len]) |mapping| {
            if (mapping.active and mapping.eup_frame_id == eup_frame_id) return mapping;
        }
        return null;
    }

    pub fn snapshot(self: FrameService, out: *[max_frame_mappings]Mapping) usize {
        var count: usize = 0;
        for (self.mappings[0..self.len]) |mapping| {
            if (mapping.active) {
                out[count] = mapping;
                count += 1;
            }
        }
        return count;
    }

    fn requireActiveTerminal(self: *FrameService) Error!void {
        const active = self.terminals.activeTerminal() orelse return error.TerminalNotLive;
        if (active.id != self.terminal_id) return error.TerminalNotLive;
    }

    fn observe(self: *FrameService, host_handle: u64) Error!adapter.FrameObservation {
        if (host_handle == 0) return error.InvalidArgument;
        const read_generation = self.runtime.host.read_generation orelse
            return error.AbiMismatch;
        const context = self.runtime.host.context orelse return error.AbiMismatch;
        const expected_generation = read_generation(context, host_handle);
        if (expected_generation == 0) return error.GenerationMismatch;
        if (expected_generation > std.math.maxInt(u32))
            return error.InvalidGeneration;

        const observation = try self.runtime.observeFrameState(host_handle);
        if (observation.generation != expected_generation)
            return error.GenerationMismatch;
        if (observation.generation > std.math.maxInt(u32))
            return error.InvalidGeneration;
        return observation;
    }

    fn findAny(self: FrameService, host_handle: u64, eup_frame_id: u32) Error!void {
        for (self.mappings[0..self.len]) |mapping| {
            if (mapping.host_handle == host_handle or
                mapping.eup_frame_id == eup_frame_id)
                return error.FrameAlreadyExists;
        }
    }

    fn findActiveHandle(self: FrameService, host_handle: u64) ?usize {
        for (self.mappings[0..self.len], 0..) |mapping, index| {
            if (mapping.active and mapping.host_handle == host_handle) return index;
        }
        return null;
    }

    fn fail(self: *FrameService, err: Error) Error {
        self.counters.failures += 1;
        return err;
    }
};

fn protocolVisibility(visibility: adapter.FrameVisibility) lifecycle.FrameVisibility {
    return @enumFromInt(@intFromEnum(visibility));
}

test "frame service registers visible, hidden, and iconified observations" {
    var fixture = try TestFixture.init(.{ .generation = 10 });
    defer fixture.deinit();
    var service = try fixture.service();

    try fixture.setVisible(11, .visible, true);
    const visible = try service.register(11, 101);
    try fixture.setVisible(12, .hidden, false);
    const hidden = try service.register(12, 102);
    try fixture.setVisible(13, .iconified, false);
    const iconified = try service.register(13, 103);

    try std.testing.expect(visible.focused);
    try std.testing.expectEqual(adapter.FrameVisibility.visible, visible.visibility);
    try std.testing.expectEqual(adapter.FrameVisibility.hidden, hidden.visibility);
    try std.testing.expectEqual(adapter.FrameVisibility.iconified, iconified.visibility);
    try std.testing.expectEqual(@as(u32, 10), visible.protocol_frame_generation);
    try std.testing.expectEqual(@as(u32, 10), fixture.frames.lookup(101).?.generation);
    try std.testing.expect(!fixture.frames.lookup(102).?.focused);
}

test "frame service refresh atomically applies a newer observation" {
    var fixture = try TestFixture.init(.{ .generation = 20 });
    defer fixture.deinit();
    var service = try fixture.service();
    try fixture.setVisible(21, .visible, true);
    _ = try service.register(21, 201);

    try fixture.setVisible(21, .hidden, false);
    fixture.setGeneration(31);
    const refreshed = try service.refresh(21);
    try std.testing.expectEqual(@as(u64, 31), refreshed.host_generation);
    try std.testing.expectEqual(@as(u32, 31), refreshed.protocol_frame_generation);
    try std.testing.expectEqual(adapter.FrameVisibility.hidden, refreshed.visibility);
    try std.testing.expect(!refreshed.focused);
    try std.testing.expectEqual(@as(u32, 31), fixture.frames.lookup(201).?.generation);
}

test "frame service rejects malformed and stale observations without mutation" {
    var fixture = try TestFixture.init(.{ .generation = 40 });
    defer fixture.deinit();
    var service = try fixture.service();
    try fixture.setVisible(31, .visible, true);
    _ = try service.register(31, 301);
    const before = service.mappings[0];

    fixture.host.state_success = 0;
    try std.testing.expectError(adapter.Error.FrameStateFailed, service.refresh(31));
    try expectUnchanged(service.mappings[0], before);
    fixture.host.state_success = 1;

    fixture.host.generation = 0;
    fixture.host.setState(31, 0, .visible, true);
    try std.testing.expectError(adapter.Error.GenerationMismatch, service.refresh(31));
    try expectUnchanged(service.mappings[0], before);
    fixture.host.generation = std.math.maxInt(u32) + 1;
    fixture.host.setState(31, std.math.maxInt(u32) + 1, .visible, true);
    try std.testing.expectError(terminal.Error.InvalidGeneration, service.refresh(31));
    try expectUnchanged(service.mappings[0], before);

    fixture.host.generation = 39;
    fixture.host.setState(31, 39, .visible, true);
    try std.testing.expectError(
        lifecycle.Error.StaleGeneration,
        service.refresh(31),
    );
    try expectUnchanged(service.mappings[0], before);

    fixture.host.generation = 41;
    fixture.host.setState(31, 41, .iconified, true);
    try std.testing.expectError(adapter.Error.FrameStateInvalid, service.refresh(31));
    try expectUnchanged(service.mappings[0], before);

    fixture.host.reserved_byte = 1;
    try std.testing.expectError(adapter.Error.FrameStateInvalid, service.refresh(31));
    try expectUnchanged(service.mappings[0], before);
    fixture.host.reserved_byte = 0;

    try std.testing.expectError(Error.UnknownFrameMapping, service.refresh(99));
    try std.testing.expectEqual(@as(u64, 7), service.counters.failures);
    try std.testing.expectEqual(@as(u32, 40), fixture.frames.lookup(301).?.generation);
}

test "frame service enforces identity, terminal, and table contracts" {
    var fixture = try TestFixture.init(.{ .generation = 1 });
    defer fixture.deinit();

    try std.testing.expectError(
        terminal.Error.TerminalNotLive,
        FrameService.init(fixture.runtime, fixture.frames, fixture.terminals, 77),
    );
    var service = try fixture.service();
    try fixture.setVisible(41, .visible, true);
    _ = try service.register(41, 401);

    try std.testing.expectError(lifecycle.Error.FrameAlreadyExists, service.register(42, 401));
    try std.testing.expectError(lifecycle.Error.FrameAlreadyExists, service.register(41, 402));
    try std.testing.expectError(error.InvalidArgument, service.register(0, 403));
    try std.testing.expectError(error.InvalidArgument, service.register(43, 0));
    try std.testing.expectEqual(@as(u64, 4), service.counters.failures);

    fixture.setGeneration(2);
    try fixture.setVisible(42, .visible, false);
    _ = try service.register(42, 402);
    fixture.setGeneration(3);
    try fixture.setVisible(43, .visible, true);
    _ = try service.register(43, 403);
    fixture.setGeneration(4);
    try fixture.setVisible(44, .visible, false);
    _ = try service.register(44, 404);
    fixture.setGeneration(5);
    try fixture.setVisible(45, .visible, false);
    _ = try service.register(45, 405);
    fixture.setGeneration(6);
    try fixture.setVisible(46, .visible, false);
    _ = try service.register(46, 406);
    fixture.setGeneration(7);
    try fixture.setVisible(47, .visible, false);
    _ = try service.register(47, 407);
    fixture.host.generation = 8;
    try fixture.setVisible(48, .visible, false);
    _ = try service.register(48, 408);
    fixture.setGeneration(9);
    try fixture.setVisible(49, .visible, false);
    try std.testing.expectError(
        Error.FrameServiceTableFull,
        service.register(49, 409),
    );
    try std.testing.expectEqual(max_frame_mappings, service.len);
    try std.testing.expectEqual(@as(u64, 5), service.counters.failures);
}

test "frame service rejects registration when terminal is not active" {
    var fixture = try TestFixture.init(.{ .generation = 42 });
    defer fixture.deinit();
    var service = try fixture.service();
    try fixture.setVisible(421, .visible, true);
    _ = try service.register(421, 421);

    const terminal_generation = try fixture.terminals.beginDrain(9, 2);
    try std.testing.expectEqual(@as(u32, 3), terminal_generation);
    try fixture.setVisible(422, .visible, false);
    try std.testing.expectError(
        terminal.Error.TerminalNotLive,
        service.register(422, 422),
    );
    try std.testing.expectEqual(@as(usize, 1), service.len);
    try std.testing.expectEqual(@as(u64, 1), service.counters.failures);
}

test "frame service rejects unsupported and mismatched observations without mutation" {
    var fixture = try TestFixture.init(.{ .generation = 43 });
    defer fixture.deinit();
    var service = try fixture.service();
    try fixture.setVisible(431, .visible, true);
    _ = try service.register(431, 431);
    const before = service.mappings[0];

    fixture.runtime.frame_state_available = false;
    try std.testing.expectError(
        adapter.Error.FrameStateUnsupported,
        service.refresh(431),
    );
    try expectUnchanged(service.mappings[0], before);
    fixture.runtime.frame_state_available = true;

    fixture.host.state_generation_delta = 1;
    try std.testing.expectError(
        adapter.Error.GenerationMismatch,
        service.refresh(431),
    );
    try expectUnchanged(service.mappings[0], before);
    try std.testing.expectEqual(@as(u64, 2), service.counters.failures);
}

test "registration rejects focused hidden and malformed host observations" {
    var fixture = try TestFixture.init(.{ .generation = 44 });
    defer fixture.deinit();
    var service = try fixture.service();

    try fixture.setVisible(441, .hidden, true);
    try std.testing.expectError(
        adapter.Error.FrameStateInvalid,
        service.register(441, 441),
    );
    try std.testing.expectEqual(@as(usize, 0), service.len);

    try fixture.setVisible(442, .visible, false);
    fixture.host.reserved_byte = 1;
    try std.testing.expectError(
        adapter.Error.FrameStateInvalid,
        service.register(442, 442),
    );
    try std.testing.expectEqual(@as(usize, 0), service.len);
    try std.testing.expectEqual(@as(u64, 2), service.counters.failures);
}

test "frame service deletes once and never reuses an EUP ID" {
    var fixture = try TestFixture.init(.{ .generation = 50 });
    defer fixture.deinit();
    var service = try fixture.service();
    try fixture.setVisible(51, .visible, true);
    _ = try service.register(51, 501);

    try service.unregister(51);
    try std.testing.expectError(
        lifecycle.Error.FrameAlreadyExists,
        service.register(51, 502),
    );
    try std.testing.expectEqual(lifecycle.FrameStatus.destroyed, fixture.frames.lookup(501).?.status);
    try std.testing.expectError(Error.UnknownFrameMapping, service.unregister(51));
    try fixture.setVisible(52, .visible, false);
    try std.testing.expectError(lifecycle.Error.FrameAlreadyExists, service.register(52, 501));
    try std.testing.expectEqual(@as(u64, 1), service.counters.deleted);
    try std.testing.expectEqual(@as(u64, 3), service.counters.failures);
}

test "frame service drain validates and removes every active mapping" {
    var fixture = try TestFixture.init(.{ .generation = 60 });
    defer fixture.deinit();
    var service = try fixture.service();
    const handles = [_]u64{ 61, 62, 63 };
    for (handles, 0..) |handle, index| {
        try fixture.setVisible(handle, .visible, index == 0);
        _ = try service.register(handle, @intCast(601 + index));
    }

    try std.testing.expectEqual(@as(usize, 3), try service.drain());
    for (handles, 0..) |_, index| {
        const frame_id: u32 = @intCast(601 + index);
        try std.testing.expectEqual(
            lifecycle.FrameStatus.destroyed,
            fixture.frames.lookup(frame_id).?.status,
        );
    }
    var snapshot: [max_frame_mappings]Mapping = undefined;
    try std.testing.expectEqual(@as(usize, 0), service.snapshot(&snapshot));
    try std.testing.expectEqual(@as(u64, 3), service.counters.drained);

    fixture.setGeneration(61);
    try std.testing.expectEqual(@as(usize, 0), try service.drain());
}

test "drain rejects a changed host observation before destroying any frame" {
    var fixture = try TestFixture.init(.{ .generation = 70 });
    defer fixture.deinit();
    var service = try fixture.service();
    try fixture.setVisible(71, .visible, true);
    _ = try service.register(71, 701);
    try fixture.setVisible(72, .visible, false);
    _ = try service.register(72, 702);

    fixture.setGeneration(71);
    try std.testing.expectError(lifecycle.Error.StaleGeneration, service.drain());
    try std.testing.expectEqual(
        lifecycle.FrameStatus.active,
        fixture.frames.lookup(701).?.status,
    );
    try std.testing.expectEqual(
        lifecycle.FrameStatus.active,
        fixture.frames.lookup(702).?.status,
    );
    try std.testing.expectEqual(@as(u64, 1), service.counters.failures);
}

test "frame observation does not interfere with active capture state" {
    var fixture = try TestFixture.init(.{ .generation = 80 });
    defer fixture.deinit();
    var service = try fixture.service();
    try fixture.setVisible(81, .visible, true);
    _ = try service.register(81, 801);
    try fixture.runtime.begin(81);

    _ = try service.refresh(81);
    try std.testing.expectEqual(adapter.Phase.capturing, fixture.runtime.phase);
    try std.testing.expectEqual(@as(u64, 80), fixture.runtime.generation);
    fixture.runtime.cancel();
}

const TestFixture = struct {
    host: *ServiceHost,
    table: *adapter.HostV1,
    runtime: *adapter.Runtime,
    frames: *lifecycle.FrameRegistry,
    terminals: *terminal.TerminalRegistry,

    const InitOptions = struct { generation: u64 };

    fn init(options: InitOptions) !TestFixture {
        const allocator = std.testing.allocator;
        const host = try allocator.create(ServiceHost);
        host.* = ServiceHost.init(options.generation);
        const table = try allocator.create(adapter.HostV1);
        table.* = host.table();
        const runtime = try allocator.create(adapter.Runtime);
        runtime.* = try adapter.Runtime.init(allocator, table);
        const frames = try allocator.create(lifecycle.FrameRegistry);
        frames.* = .{};
        const terminals = try allocator.create(terminal.TerminalRegistry);
        terminals.* = .{};
        _ = try terminals.create(9, terminal.initial_generation);
        _ = try terminals.activate(9, terminal.initial_generation);
        return .{
            .host = host,
            .table = table,
            .runtime = runtime,
            .frames = frames,
            .terminals = terminals,
        };
    }

    fn deinit(self: *TestFixture) void {
        const allocator = std.testing.allocator;
        self.runtime.deinit();
        allocator.destroy(self.runtime);
        allocator.destroy(self.table);
        allocator.destroy(self.frames);
        allocator.destroy(self.terminals);
        allocator.destroy(self.host);
    }

    fn setGeneration(self: *TestFixture, generation: u64) void {
        self.host.generation = generation;
        for (self.host.states[0..self.host.state_count]) |*state| {
            state.generation = generation;
        }
    }

    fn service(self: *TestFixture) Error!FrameService {
        return FrameService.init(self.runtime, self.frames, self.terminals, 9);
    }

    fn setVisible(
        self: *TestFixture,
        frame_handle: u64,
        visibility: adapter.FrameVisibility,
        focused: bool,
    ) !void {
        self.host.setState(frame_handle, self.host.generation, visibility, focused);
        self.host.state_success = 1;
        self.host.reserved_byte = 0;
    }
};

const ServiceHost = struct {
    generation: u64,
    state_generation_delta: u64 = 0,
    state_success: u8 = 1,
    reserved_byte: u8 = 0,
    states: [16]HostState = undefined,
    state_count: usize = 0,

    const HostState = struct {
        handle: u64,
        generation: u64,
        visibility: adapter.FrameVisibility,
        focused: bool,
    };

    fn init(generation: u64) ServiceHost {
        return .{ .generation = generation };
    }

    fn table(self: *ServiceHost) adapter.HostV1 {
        return .{
            .context = self,
            .read_generation = readGeneration,
            .read_geometry = readGeometry,
            .read_frame_state = readFrameState,
        };
    }

    fn readGeneration(context: *anyopaque, frame_id: u64) callconv(.c) u64 {
        const self: *ServiceHost = @ptrCast(@alignCast(context));
        const state = self.find(frame_id) orelse return 0;
        return state.generation;
    }

    fn readGeometry(context: *anyopaque, frame_id: u64, geometry: *adapter.Geometry) callconv(.c) u8 {
        _ = context;
        _ = frame_id;
        geometry.* = .{ .x = 0, .y = 0, .width = 320, .height = 200 };
        return 1;
    }

    fn readFrameState(context: *anyopaque, frame_id: u64, state: *adapter.FrameState) callconv(.c) u8 {
        const self: *ServiceHost = @ptrCast(@alignCast(context));
        if (self.state_success != 1) return 0;
        const found = self.find(frame_id) orelse return 0;
        state.* = .{
            .generation = found.generation + self.state_generation_delta,
            .visibility = @intFromEnum(found.visibility),
            .focused = @intFromBool(found.focused),
            .reserved = .{ self.reserved_byte, 0, 0, 0, 0, 0 },
        };
        return 1;
    }

    fn find(self: *ServiceHost, frame_id: u64) ?*HostState {
        for (self.states[0..self.state_count]) |*state| {
            if (state.handle == frame_id) return state;
        }
        return null;
    }

    fn setState(
        self: *ServiceHost,
        frame_handle: u64,
        generation: u64,
        visibility: adapter.FrameVisibility,
        focused: bool,
    ) void {
        if (self.find(frame_handle)) |state| {
            state.* = .{
                .handle = frame_handle,
                .generation = generation,
                .visibility = visibility,
                .focused = focused,
            };
            return;
        }
        self.states[self.state_count] = .{
            .handle = frame_handle,
            .generation = generation,
            .visibility = visibility,
            .focused = focused,
        };
        self.state_count += 1;
    }
};

fn expectUnchanged(actual: Mapping, expected: Mapping) !void {
    try std.testing.expectEqual(expected.host_handle, actual.host_handle);
    try std.testing.expectEqual(expected.eup_frame_id, actual.eup_frame_id);
    try std.testing.expectEqual(expected.host_generation, actual.host_generation);
    try std.testing.expectEqual(expected.protocol_frame_generation, actual.protocol_frame_generation);
    try std.testing.expectEqual(expected.visibility, actual.visibility);
    try std.testing.expectEqual(expected.focused, actual.focused);
    try std.testing.expectEqual(expected.active, actual.active);
}
