//! Adapter-side Terminal Provider Extension v1 registration policy.
//!
//! This module validates the provider descriptor against the existing
//! PureRuntimeHostV1 ABI and exercises the registration state machine with a
//! fake core.  It does not add TP1 core dispatch, an Emacs call path, a startup
//! constructor, terminal registration, or output_proto runtime.

const std = @import("std");
const host_adapter = @import("host_adapter.zig");
const host_contract = @import("host_contract.zig");
const runtime = @import("runtime.zig");
const runtime_host = @import("runtime_host.zig");

pub const manifest_version: u32 = 1;
pub const policy_schema_version: u32 = 1;
pub const authoritative_source = "src/proto-ui/tpe_registration.zig";
pub const provider_name = "proto";
pub const identity_symbol = "proto";
pub const policy_status = "implemented_fake_core_only";
pub const fail_closed_reason = "tp2_policy_only_core_dispatch_and_runtime_absent";
pub const abi_version = runtime_host.abi_version;
pub const table_size = @sizeOf(runtime_host.PureRuntimeHostV1);
pub const group_count = runtime.callback_groups.len;
pub const operation_count = runtime_host.operation_names.len;

pub const Error = error{
    InvalidDescriptor,
    InvalidRuntimeHost,
    DuplicateRegistration,
    InvalidTransition,
    RegistrationQuarantined,
    OperationFailed,
};

pub const Flags = packed struct(u32) {
    graphic: bool = false,
    input: bool = false,
    selection: bool = false,
    tooltip: bool = false,
    menu: bool = false,
    image: bool = false,
    reserved: u26 = 0,
};

pub const required_flags = Flags{
    .graphic = true,
    .input = true,
    .selection = true,
    .tooltip = true,
    .menu = true,
    .image = true,
};

pub const flag_names = [_][]const u8{
    "graphic",
    "input",
    "selection",
    "tooltip",
    "menu",
    "image",
};

pub const State = enum {
    disabled,
    provider_table_validated,
    provider_registered,
    terminal_provider_selected,
    terminal_created,
    terminal_activated,
    transport_ready,
    frame_capability_ready,
    quarantined,
    rolled_back,
};

pub const forward_order = [_]State{
    .disabled,
    .provider_table_validated,
    .provider_registered,
    .terminal_provider_selected,
    .terminal_created,
    .terminal_activated,
    .transport_ready,
    .frame_capability_ready,
};

pub const Descriptor = struct {
    name: []const u8,
    identity_symbol: []const u8,
    flags: Flags,
    inherited_source_paths_modified: []const []const u8,
    registration_requested: bool,
};

pub const canonical_descriptor = Descriptor{
    .name = provider_name,
    .identity_symbol = identity_symbol,
    .flags = required_flags,
    .inherited_source_paths_modified = &.{},
    .registration_requested = true,
};

fn flagsEqual(left: Flags, right: Flags) bool {
    return @as(u32, @bitCast(left)) == @as(u32, @bitCast(right));
}

pub fn validateDescriptor(descriptor: Descriptor) Error!void {
    if (!std.mem.eql(u8, descriptor.name, provider_name)) return error.InvalidDescriptor;
    if (!std.mem.eql(u8, descriptor.identity_symbol, identity_symbol))
        return error.InvalidDescriptor;
    if (!flagsEqual(descriptor.flags, required_flags)) return error.InvalidDescriptor;
    if (descriptor.inherited_source_paths_modified.len != 0)
        return error.InvalidDescriptor;
    if (!descriptor.registration_requested) return error.InvalidDescriptor;
}

pub const Identity = struct {
    id: u64,
    generation: u64,
};

pub const Registration = struct {
    descriptor: Descriptor,
    table: *const runtime_host.PureRuntimeHostV1,
    state: State = .disabled,
    fail_at: ?State = null,
    generation: u64 = 0,
    terminal: ?Identity = null,
    retained_generations: [8]u64 = undefined,
    retained_count: usize = 0,
    rollback_log: [rollback_order.len][]const u8 = undefined,
    rollback_count: usize = 0,
    registrations: usize = 0,

    pub fn init(
        descriptor: Descriptor,
        table: *const runtime_host.PureRuntimeHostV1,
    ) Registration {
        return .{ .descriptor = descriptor, .table = table };
    }

    fn validateRegistration(self: *const Registration) Error!void {
        try validateDescriptor(self.descriptor);
        runtime_host.validateTable(self.table) catch return error.InvalidRuntimeHost;
        if (self.table.abi_version != abi_version or self.table.size != table_size)
            return error.InvalidRuntimeHost;
    }

    pub fn setFailureAt(self: *Registration, state: State) Error!void {
        switch (state) {
            .disabled, .provider_table_validated, .quarantined, .rolled_back => return error.InvalidTransition,
            else => {},
        }
        if (self.state != .disabled) return error.InvalidTransition;
        self.fail_at = state;
    }

    pub fn advance(self: *Registration) Error!State {
        if (self.state == .quarantined) return error.RegistrationQuarantined;
        if (self.state == .rolled_back) return error.DuplicateRegistration;
        const current_index = stateIndex(self.state) orelse return error.InvalidTransition;
        if (current_index + 1 >= forward_order.len) return error.DuplicateRegistration;
        const target = forward_order[current_index + 1];
        try self.validateRegistration();
        if (self.state == .disabled and self.registrations != 0) return error.DuplicateRegistration;
        if (self.fail_at != null and self.fail_at.? == target) {
            if (target != .provider_table_validated) self.retainGeneration();
            self.quarantine(target);
            return error.OperationFailed;
        }
        self.state = target;
        if (target == .provider_table_validated) {
            self.registrations += 1;
            self.generation = self.registrations;
        }
        if (target == .terminal_created) {
            self.terminal = .{ .id = 7, .generation = self.generation };
        }
        return target;
    }

    pub fn register(self: *Registration) Error!State {
        if (self.state == .quarantined) return error.RegistrationQuarantined;
        if (self.state != .disabled) return error.DuplicateRegistration;
        var state: State = .disabled;
        while (state != .frame_capability_ready) {
            state = try self.advance();
        }
        return state;
    }

    pub fn rollback(self: *Registration) bool {
        if (self.state == .disabled or self.state == .quarantined or self.state == .rolled_back)
            return false;
        for (rollbackStepsFor(self.state)) |step| {
            self.rollback_log[self.rollback_count] = step;
            self.rollback_count += 1;
        }
        self.terminal = null;
        if (self.registrations != 0 and self.retained_count < self.retained_generations.len) {
            var already_retained = false;
            for (self.retained_generations[0..self.retained_count]) |retained| {
                if (retained == self.generation) already_retained = true;
            }
            if (!already_retained) {
                self.retained_generations[self.retained_count] = self.generation;
                self.retained_count += 1;
            }
        }
        self.state = .rolled_back;
        return true;
    }

    pub fn rollbackStepsFor(state: State) []const []const u8 {
        return switch (state) {
            .frame_capability_ready => rollback_order[0..],
            .transport_ready => rollback_order[3..],
            .terminal_activated => rollback_order[2..],
            .terminal_created => rollback_order[4..],
            .terminal_provider_selected => rollback_order[5..],
            .provider_registered => rollback_order[6..],
            .provider_table_validated => rollback_order[7..],
            else => rollback_order[7..8],
        };
    }

    fn retainGeneration(self: *Registration) void {
        if (self.retained_count >= self.retained_generations.len) return;
        const generation = if (self.registrations == 0) 1 else self.registrations;
        self.retained_generations[self.retained_count] = generation;
        self.retained_count += 1;
    }

    fn quarantine(self: *Registration, failed_target: State) void {
        if (self.state != .disabled and self.state != failed_target) {
            _ = self.rollback();
        } else {
            for (rollback_order) |step| {
                if (self.rollback_count >= self.rollback_log.len) break;
                self.rollback_log[self.rollback_count] = step;
                self.rollback_count += 1;
            }
            self.terminal = null;
        }
        self.state = .quarantined;
        self.fail_at = null;
    }
};

fn stateIndex(state: State) ?usize {
    for (forward_order, 0..) |candidate, index| {
        if (candidate == state) return index;
    }
    return null;
}

pub fn validatePolicy() ?[]const u8 {
    if (policy_schema_version != 1) return "unsupported TPE policy schema";
    if (!std.mem.eql(u8, policy_status, "implemented_fake_core_only"))
        return "TPE policy status changed";
    if (!std.mem.eql(u8, fail_closed_reason, "tp2_policy_only_core_dispatch_and_runtime_absent"))
        return "TPE fail-closed reason changed";
    if (validateDescriptor(canonical_descriptor)) |_| {} else |_| {
        return "canonical TPE provider descriptor changed";
    }
    if (host_contract.validateState() != null or host_contract.decision.status != .approved)
        return "TPE policy requires approved R7 metadata";
    if (host_adapter.current.status != .selected) return "candidate adapter is not selected";
    if (abi_version != 1 or table_size != 64 or group_count != 5 or operation_count != 27)
        return "PureRuntimeHostV1 inventory changed";
    return null;
}

pub fn writeManifest(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (validatePolicy() != null) return Error.InvalidDescriptor;
    try out.appendSlice(gpa, "{\"manifest_version\":");
    try out.print(gpa, "{d}", .{manifest_version});
    try out.appendSlice(gpa, ",\"kind\":\"proto-ui-tpe-registration-policy\",");
    try out.appendSlice(gpa, "\"authoritative_source\":");
    try runtime.appendJsonStringPublic(gpa, out, authoritative_source);
    try out.print(gpa, ",\"policy_schema_version\":{d}", .{policy_schema_version});
    try out.appendSlice(gpa, ",\"policy_status\":");
    try runtime.appendJsonStringPublic(gpa, out, policy_status);
    try out.appendSlice(gpa, ",\"provider\":{\"name\":");
    try runtime.appendJsonStringPublic(gpa, out, provider_name);
    try out.appendSlice(gpa, ",\"identity_symbol\":");
    try runtime.appendJsonStringPublic(gpa, out, identity_symbol);
    try out.appendSlice(gpa, ",\"flags\":");
    try runtime.appendJsonStringArrayPublic(gpa, out, &flag_names);
    try out.appendSlice(gpa, ",\"immutable\":true}");
    try out.appendSlice(gpa, ",\"registration\":{\"explicit\":true,\"default_enabled\":false,\"state\":\"policy_disabled\",\"attempted\":false,\"registered\":false,\"quarantined\":false,\"generation_retention\":true}");
    try out.appendSlice(gpa, ",\"tp1_core_dispatch_absent\":true,\"emacs_call_path\":false,\"startup_constructor\":false,\"terminal_registration\":false,\"output_proto_runtime\":false,\"runtime_available\":false,\"pgtk_runtime_fallback_allowed\":false,\"tty_runtime_fallback_allowed\":false,\"reason_code\":");
    try runtime.appendJsonStringPublic(gpa, out, fail_closed_reason);
    try out.appendSlice(gpa, ",\"abi\":{\"version\":");
    try out.print(gpa, "{d}", .{abi_version});
    try out.appendSlice(gpa, ",\"table_size\":");
    try out.print(gpa, "{d}", .{table_size});
    try out.appendSlice(gpa, ",\"group_count\":");
    try out.print(gpa, "{d}", .{group_count});
    try out.appendSlice(gpa, ",\"operation_count\":");
    try out.print(gpa, "{d}", .{operation_count});
    try out.appendSlice(gpa, "}");
    try out.appendSlice(gpa, ",\"inherited_source_paths_modified\":");
    try runtime.appendJsonStringArrayPublic(gpa, out, canonical_descriptor.inherited_source_paths_modified);
    try out.appendSlice(gpa, ",\"rollback_order\":[");
    for (rollback_order, 0..) |step, index| {
        if (index != 0) try out.append(gpa, ',');
        try runtime.appendJsonStringPublic(gpa, out, step);
    }
    try out.appendSlice(gpa, "]}\n");
}

pub const rollback_order = [_][]const u8{
    "frontend.transport_stopped",
    "redisplay.capture_cancelled",
    "frames.unregistered",
    "terminal.drained",
    "terminal.deleted",
    "provider_state.freed",
    "gc_roots.released",
    "provider.unregistered",
};

test "descriptor policy accepts only canonical immutable provider" {
    try validateDescriptor(canonical_descriptor);

    const bad_name = Descriptor{
        .name = "bad",
        .identity_symbol = identity_symbol,
        .flags = required_flags,
        .inherited_source_paths_modified = &.{},
        .registration_requested = true,
    };
    try std.testing.expectError(error.InvalidDescriptor, validateDescriptor(bad_name));

    const bad_identity = Descriptor{
        .name = provider_name,
        .identity_symbol = "bad",
        .flags = required_flags,
        .inherited_source_paths_modified = &.{},
        .registration_requested = true,
    };
    try std.testing.expectError(error.InvalidDescriptor, validateDescriptor(bad_identity));

    const unrequested = Descriptor{
        .name = provider_name,
        .identity_symbol = identity_symbol,
        .flags = required_flags,
        .inherited_source_paths_modified = &.{},
        .registration_requested = false,
    };
    try std.testing.expectError(error.InvalidDescriptor, validateDescriptor(unrequested));

    var flags = required_flags;
    flags.graphic = false;
    var reserved_flags = required_flags;
    reserved_flags.reserved = 1;
    const bad_flags = Descriptor{
        .name = provider_name,
        .identity_symbol = identity_symbol,
        .flags = flags,
        .inherited_source_paths_modified = &.{},
        .registration_requested = true,
    };
    try std.testing.expectError(error.InvalidDescriptor, validateDescriptor(bad_flags));

    const bad_reserved = Descriptor{
        .name = provider_name,
        .identity_symbol = identity_symbol,
        .flags = reserved_flags,
        .inherited_source_paths_modified = &.{},
        .registration_requested = true,
    };
    try std.testing.expectError(error.InvalidDescriptor, validateDescriptor(bad_reserved));

    const inherited_edit = Descriptor{
        .name = provider_name,
        .identity_symbol = identity_symbol,
        .flags = required_flags,
        .inherited_source_paths_modified = &.{"src/term.c"},
        .registration_requested = true,
    };
    try std.testing.expectError(error.InvalidDescriptor, validateDescriptor(inherited_edit));
}

test "state policy rejects invalid control transitions without mutation" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var registration = Registration.init(canonical_descriptor, &table);
    try std.testing.expectError(error.InvalidTransition, registration.setFailureAt(.disabled));
    try std.testing.expectError(error.InvalidTransition, registration.setFailureAt(.provider_table_validated));
    try std.testing.expectError(error.InvalidTransition, registration.setFailureAt(.quarantined));
    try std.testing.expectError(error.InvalidTransition, registration.setFailureAt(.rolled_back));
    try std.testing.expectEqual(State.disabled, registration.state);
    try std.testing.expect(registration.fail_at == null);
    try std.testing.expect(!registration.rollback());
    try std.testing.expectEqual(@as(usize, 0), registration.rollback_count);
}

test "fake-core registration follows the exact explicit state machine" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var registration = Registration.init(canonical_descriptor, &table);
    try std.testing.expectEqual(State.disabled, registration.state);

    var expected: usize = 1;
    for (forward_order[1..]) |_| {
        const state = try registration.advance();
        try std.testing.expectEqual(forward_order[expected], state);
        expected += 1;
    }
    try std.testing.expectEqual(State.frame_capability_ready, registration.state);
    try std.testing.expectEqual(@as(u64, 1), registration.generation);
    try std.testing.expectEqual(@as(usize, 1), registration.registrations);
    try std.testing.expectEqual(@as(u64, 7), registration.terminal.?.id);
    try std.testing.expectError(error.DuplicateRegistration, registration.advance());
    try std.testing.expectError(error.DuplicateRegistration, registration.register());

    try std.testing.expect(registration.rollback());
    try std.testing.expectEqual(State.rolled_back, registration.state);
    try std.testing.expectEqual(rollback_order.len, registration.rollback_count);
    try std.testing.expectEqualStrings(rollback_order[0], registration.rollback_log[0]);
    try std.testing.expectEqualStrings(rollback_order[rollback_order.len - 1], registration.rollback_log[rollback_order.len - 1]);
    try std.testing.expect(!registration.rollback());
    try std.testing.expectEqual(rollback_order.len, registration.rollback_count);
    try std.testing.expectEqual(@as(usize, 1), registration.retained_count);
    try std.testing.expectEqual(@as(u64, 1), registration.retained_generations[0]);
}

test "fake-core rejects malformed host ABI tables" {
    const cases = [_]struct { mutate: *const fn (*runtime_host.PureRuntimeHostV1) void }{
        .{ .mutate = struct {
            fn mutate(table: *runtime_host.PureRuntimeHostV1) void {
                table.abi_version = 2;
            }
        }.mutate },
        .{ .mutate = struct {
            fn mutate(table: *runtime_host.PureRuntimeHostV1) void {
                table.size = 63;
            }
        }.mutate },
        .{ .mutate = struct {
            fn mutate(table: *runtime_host.PureRuntimeHostV1) void {
                table.terminal = null;
            }
        }.mutate },
    };

    for (cases) |case| {
        var host: runtime_host.FakeHost = undefined;
        var table = runtime_host.fakeTable(&host);
        case.mutate(&table);
        var registration = Registration.init(canonical_descriptor, &table);
        try std.testing.expectError(error.InvalidRuntimeHost, registration.advance());
    }
}

test "failure quarantines generation and preserves reverse rollback ordering" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var registration = Registration.init(canonical_descriptor, &table);
    try registration.setFailureAt(.terminal_activated);

    while (registration.state != .terminal_created) {
        _ = try registration.advance();
    }
    try std.testing.expectError(error.OperationFailed, registration.advance());
    try std.testing.expectEqual(State.quarantined, registration.state);
    try std.testing.expect(registration.terminal == null);
    try std.testing.expectEqual(@as(usize, 1), registration.retained_count);
    try std.testing.expectEqualStrings("terminal.deleted", registration.rollback_log[0]);
    try std.testing.expectEqualStrings("provider.unregistered", registration.rollback_log[registration.rollback_count - 1]);
    try std.testing.expectError(error.RegistrationQuarantined, registration.advance());
    try std.testing.expectError(error.RegistrationQuarantined, registration.register());
}

test "TPE policy manifest is deterministic and explicitly fail closed" {
    try std.testing.expectEqual(@as(?[]const u8, null), validatePolicy());
    const gpa = std.testing.allocator;
    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(gpa);
    try writeManifest(gpa, &first);
    try writeManifest(gpa, &second);
    try std.testing.expectEqualSlices(u8, first.items, second.items);
    try std.testing.expect(first.items.len < 16 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"tp1_core_dispatch_absent\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"runtime_available\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"terminal_registration\":false") != null);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, first.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(policy_status, parsed.value.object.get("policy_status").?.string);
}
