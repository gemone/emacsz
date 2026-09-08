//! Selection-gated runtime activation and machine-readable activation plan.
//!
//! The controller can exercise the approved path with a conformance host, but
//! the repository's current selection is unselected while R7 remains pending.
//! No code in this module registers an Emacs terminal or enables runtime.

const std = @import("std");
const host_adapter = @import("host_adapter.zig");
const runtime_host = @import("runtime_host.zig");
const runtime = @import("runtime.zig");
const terminal = @import("terminal.zig");
const terminal_service = @import("terminal_service.zig");

pub const manifest_version: u32 = 1;
pub const activation_schema_version: u32 = 1;
pub const authoritative_source = "src/proto-ui/runtime_activation.zig";

pub const Error = terminal_service.Error || error{
    HostSelectionRequired,
    InvalidSelectionDecision,
    InvalidActivationState,
};

pub const State = enum {
    idle,
    activating,
    terminal_active,
    draining,
    rollback_pending,
    drained,
};

pub const activation_sequence = [_][]const u8{
    "r7.approved_with_metadata",
    "host_adapter.selected",
    "terminal.created",
    "terminal.activated",
    "frame.registered",
    "redisplay.capture_ready",
    "frontend.transport_ready",
};

pub const rollback_sequence = [_][]const u8{
    "frontend.transport_stopped",
    "redisplay.capture_cancelled",
    "frame.unregistered",
    "terminal.drained",
    "terminal.deleted",
    "host_adapter.unselected",
};

pub const Controller = struct {
    selection: host_adapter.Decision,
    service: terminal_service.TerminalService,
    state: State = .idle,

    pub fn init(
        table: runtime_host.PureRuntimeHostV1,
        terminals: *terminal.TerminalRegistry,
        selection: host_adapter.Decision,
    ) Error!Controller {
        try validateDecisionShape(selection);
        const service = try terminal_service.TerminalService.init(table, terminals);
        return .{ .selection = selection, .service = service };
    }

    fn validateDecisionShape(selection: host_adapter.Decision) Error!void {
        const consistent = switch (selection.status) {
            .unselected => !selection.selected and !selection.activation_allowed and
                !selection.registered and !selection.runtime_available,
            .selected => selection.selected and selection.activation_allowed and
                !selection.registered and !selection.runtime_available,
            .rejected => !selection.selected and !selection.activation_allowed and
                !selection.registered and !selection.runtime_available,
        };
        if (!consistent) return error.InvalidSelectionDecision;
    }

    fn requireSelected(self: *const Controller) Error!void {
        if (self.selection.status != .selected or !self.selection.activation_allowed)
            return error.HostSelectionRequired;
    }

    pub fn activateTerminal(self: *Controller) Error!terminal.Terminal {
        if (self.state != .idle) return error.InvalidActivationState;
        try self.requireSelected();
        self.state = .activating;
        _ = self.service.create(terminal.initial_generation) catch |err| {
            self.state = .idle;
            return err;
        };
        const activated = self.service.activate() catch |err| {
            self.service.cancelActivation() catch |rollback_err| {
                if (rollback_err == error.HostCallbackFailed) {
                    // A host-delete failure remains rollback-pending in the
                    // terminal service for bounded retry; do not mask it.
                    self.state = .rollback_pending;
                    return err;
                }
                self.state = .idle;
                return rollback_err;
            };
            self.state = .idle;
            return err;
        };
        self.state = .terminal_active;
        return activated;
    }

    pub fn drain(self: *Controller) Error!terminal.Terminal {
        if (self.state != .terminal_active and self.state != .draining)
            return error.InvalidActivationState;
        self.state = .draining;
        const drained = self.service.drain() catch |err| return err;
        self.state = .drained;
        return drained;
    }

    pub fn completeRollback(self: *Controller) Error!void {
        if (self.state != .rollback_pending) return error.InvalidActivationState;
        try self.service.completeRollback();
        self.state = .idle;
    }

    pub fn activeTerminal(self: *const Controller) Error!terminal.Terminal {
        if (self.state != .terminal_active) return error.InvalidActivationState;
        return self.service.activeTerminal();
    }
};

pub const current_selection = host_adapter.current;

pub fn validateState() ?[]const u8 {
    if (host_adapter.validateState()) |problem| return problem;
    if (current_selection.activation_allowed)
        return "current activation unexpectedly allowed";
    if (current_selection.registered or current_selection.runtime_available)
        return "current activation unexpectedly registered or available";
    if (activation_sequence.len == 0 or rollback_sequence.len == 0)
        return "activation sequence is empty";
    return null;
}

pub fn writeManifest(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (validateState() != null) return error.InvalidRuntimeActivation;
    try out.appendSlice(gpa, "{\"manifest_version\":1,");
    try out.appendSlice(gpa, "\"kind\":\"proto-ui-runtime-activation\",");
    try out.appendSlice(gpa, "\"authoritative_source\":");
    try runtime.appendJsonStringPublic(gpa, out, authoritative_source);
    try out.appendSlice(gpa, ",\"activation_schema_version\":");
    try out.print(gpa, "{d}", .{activation_schema_version});
    try out.appendSlice(gpa, ",\"selection_status\":\"");
    try out.appendSlice(gpa, @tagName(current_selection.status));
    try out.appendSlice(gpa, "\",\"activation\":{\"allowed\":false,\"state\":\"blocked_by_r7\"");
    try out.appendSlice(gpa, ",\"registered\":false,\"runtime_available\":false,\"reason_code\":");
    try runtime.appendJsonStringPublic(gpa, out, current_selection.reason_code);
    try out.appendSlice(gpa, "},\"activation_sequence\":[");
    for (activation_sequence, 0..) |step, index| {
        if (index != 0) try out.append(gpa, ',');
        try runtime.appendJsonStringPublic(gpa, out, step);
    }
    try out.appendSlice(gpa, "],\"rollback_sequence\":[");
    for (rollback_sequence, 0..) |step, index| {
        if (index != 0) try out.append(gpa, ',');
        try runtime.appendJsonStringPublic(gpa, out, step);
    }
    try out.appendSlice(gpa, "]}\n");
}

test "activation controller requires a selected host adapter decision" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var terminals: terminal.TerminalRegistry = .{};
    var blocked = try Controller.init(
        table,
        &terminals,
        host_adapter.current,
    );
    try std.testing.expectError(error.HostSelectionRequired, blocked.activateTerminal());
    try std.testing.expectEqual(State.idle, blocked.state);
    try std.testing.expectEqual(runtime_host.TerminalState.absent, host.terminal);
}

test "activation controller activates and drains an approved fake host" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var terminals: terminal.TerminalRegistry = .{};
    const approved = host_adapter.evaluate(.{
        .r7_status = .approved,
        .r7_metadata_complete = true,
    });
    var controller = try Controller.init(table, &terminals, approved);

    const active = try controller.activateTerminal();
    try std.testing.expectEqual(State.terminal_active, controller.state);
    try std.testing.expectEqual(active, try controller.activeTerminal());

    const drained = try controller.drain();
    try std.testing.expectEqual(State.drained, controller.state);
    try std.testing.expectEqual(terminal.TerminalState.deleted, drained.state);
    try std.testing.expectEqual(runtime_host.TerminalState.deleted, host.terminal);
}

test "activation controller rolls back a failed terminal activation" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var terminals: terminal.TerminalRegistry = .{};
    host.terminal_group.activate_terminal = failedActivation;
    const approved = host_adapter.evaluate(.{
        .r7_status = .approved,
        .r7_metadata_complete = true,
    });
    var controller = try Controller.init(table, &terminals, approved);

    try std.testing.expectError(error.HostCallbackFailed, controller.activateTerminal());
    try std.testing.expectEqual(State.idle, controller.state);
    try std.testing.expectEqual(terminal.TerminalState.deleted, terminals.lookup(1).?.state);
    try std.testing.expectEqual(runtime_host.TerminalState.deleted, host.terminal);
}

test "activation controller retains failed rollback for bounded retry" {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var terminals: terminal.TerminalRegistry = .{};
    host.terminal_group.activate_terminal = failedActivation;
    host.terminal_group.delete_terminal = failedDeletion;
    const approved = host_adapter.evaluate(.{
        .r7_status = .approved,
        .r7_metadata_complete = true,
    });
    var controller = try Controller.init(table, &terminals, approved);

    try std.testing.expectError(error.HostCallbackFailed, controller.activateTerminal());
    try std.testing.expectEqual(State.rollback_pending, controller.state);

    host.terminal_group.delete_terminal = successfulDeletion;
    try controller.completeRollback();
    try std.testing.expectEqual(State.idle, controller.state);
    try std.testing.expectEqual(terminal.TerminalState.deleted, terminals.lookup(1).?.state);
}

fn failedActivation(
    context: *anyopaque,
    identity: *const runtime_host.Identity,
) callconv(.c) runtime_host.Status {
    _ = context;
    _ = identity;
    return .failed;
}

fn failedDeletion(
    context: *anyopaque,
    identity: *const runtime_host.Identity,
) callconv(.c) runtime_host.Status {
    _ = context;
    _ = identity;
    return .failed;
}

fn successfulDeletion(
    context: *anyopaque,
    identity: *const runtime_host.Identity,
) callconv(.c) runtime_host.Status {
    _ = context;
    _ = identity;
    return .ok;
}

test "current runtime activation remains blocked by pending R7" {
    try std.testing.expectEqual(@as(?[]const u8, null), validateState());
    try std.testing.expectEqual(host_adapter.SelectionStatus.unselected, current_selection.status);
    try std.testing.expect(!current_selection.activation_allowed);
}

test "runtime activation manifest is deterministic and bounded" {
    const gpa = std.testing.allocator;
    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(gpa);
    try writeManifest(gpa, &first);
    try writeManifest(gpa, &second);
    try std.testing.expectEqualSlices(u8, first.items, second.items);
    try std.testing.expect(first.items.len < 16 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"allowed\":false") != null);
}
