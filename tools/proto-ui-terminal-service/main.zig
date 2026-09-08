//! Machine-readable fake-host evidence for the adapter terminal service.

const std = @import("std");
const proto_ui = @import("proto_ui");

const runtime_host = proto_ui.runtime_host;
const terminal = proto_ui.terminal;
const TerminalService = proto_ui.terminal_service.TerminalService;

fn expectHostCallbackFailed(result: proto_ui.terminal_service.Error!terminal.Terminal) !void {
    if (result) |_| return error.DrainUnexpectedlySucceeded else |err| {
        if (err != error.HostCallbackFailed) return err;
    }
}

fn runLifecycleEvidence() !void {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var terminals: terminal.TerminalRegistry = .{};
    var service = try TerminalService.init(table, &terminals);

    const created = try service.create(terminal.initial_generation);
    if (created.state != .registering or created.id != 1 or created.generation != 1)
        return error.TerminalCreateStateInvalid;
    if (host.terminal != .active) return error.HostCreateStateInvalid;

    const active = try service.activate();
    if (active.state != .active or active.generation != 2)
        return error.TerminalActivateStateInvalid;
    if ((try service.activeTerminal()).id != active.id)
        return error.TerminalActiveLookupInvalid;

    host.force_failure = true;
    try expectHostCallbackFailed(service.drain());
    if (service.state != .draining or terminals.lookup(1).?.state != .draining)
        return error.TerminalDrainRetryStateInvalid;

    host.force_failure = false;
    const drained = try service.drain();
    if (drained.state != .deleted or drained.generation != 4)
        return error.TerminalDrainStateInvalid;
    if (host.terminal != .deleted or service.state != .idle)
        return error.TerminalDeleteStateInvalid;
    if (service.counters.drained_retries != 1)
        return error.TerminalDrainRetryCounterInvalid;
}

fn runRollbackEvidence() !void {
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
    if (service.create(terminal.initial_generation)) |_| {
        return error.RollbackUnexpectedlySucceeded;
    } else |err| {
        if (err != terminal.Error.TerminalTableFull) return err;
    }
    if (service.state != .idle or host.terminal != .deleted)
        return error.TerminalRollbackStateInvalid;
    if (service.counters.rolled_back != 1)
        return error.TerminalRollbackCounterInvalid;
}

pub fn main() !void {
    try runLifecycleEvidence();
    try runRollbackEvidence();
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-terminal-service\",\"created\":1,\"activated\":1,\"drained\":1,\"drain_retries\":1,\"rolled_back\":1,\"emacs_registered\":false,\"runtime_available\":false,\"result\":\"pass\"}}\n",
        .{},
    );
}
