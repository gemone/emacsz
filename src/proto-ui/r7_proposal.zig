//! Source-authoritative R7 registration proposal for the pure SDL3 runtime.
//!
//! This artifact is the reviewed R7 proposal input.  The recorded decision is
//! policy-only; it does not register a terminal, enable output_proto, alter an
//! inherited backend, or claim parity.

const std = @import("std");
const host_contract = @import("host_contract.zig");
const runtime = @import("runtime.zig");

pub const manifest_version: u32 = 1;
pub const proposal_schema_version: u32 = 1;
pub const authoritative_source = "src/proto-ui/r7_proposal.zig";
pub const proposal_id = "R7:pure-sdl3-output-proto-terminal";
pub const reason_code = runtime.reason_code;

pub const ProposalStatus = enum {
    draft,
    ready_for_review,
    approved,
    withdrawn,
};

pub const Target = struct {
    ui_backend: []const u8 = "sdl3",
    terminal_type: []const u8 = "output_proto",
    pure_sdl3_ui: bool = true,
    pgtk_reference_only: bool = true,
    pgtk_runtime_fallback_allowed: bool = false,
    tty_runtime_fallback_allowed: bool = false,
    frontend_may_evaluate_elisp: bool = false,
    frontend_may_own_emacs_layout: bool = false,
};

pub const Prerequisite = struct {
    name: []const u8,
    status: []const u8,
    evidence: []const u8,
};

pub const EvidenceGate = struct {
    name: []const u8,
    command: []const u8,
    status: []const u8,
    expected: []const u8,
};

pub const Error = error{
    InvalidR7Proposal,
};

pub const proposal = Proposal{};
pub const target = Target{};
pub const prerequisites = [_]Prerequisite{
    .{
        .name = "terminal.lifecycle_state_machine",
        .status = "implemented",
        .evidence = "proto-ui-unit terminal lifecycle tests",
    },
    .{
        .name = "runtime.fail_closed_manifest",
        .status = "implemented",
        .evidence = "proto-ui-runtime-manifest",
    },
    .{
        .name = "adapter.generated_c_shim",
        .status = "implemented",
        .evidence = "proto-ui-shim-conformance",
    },
    .{
        .name = "adapter.host_shim_library",
        .status = "implemented",
        .evidence = "proto-ui-shim-library-conformance",
    },
    .{
        .name = "frame.service_mapping",
        .status = "implemented",
        .evidence = "proto-ui-unit frame service mapping tests",
    },
    .{
        .name = "capture.atomic_batches",
        .status = "implemented",
        .evidence = "proto-ui-unit capture service tests",
    },
    .{
        .name = "redisplay.resource_capture",
        .status = "implemented",
        .evidence = "runtime bridge face/font/image observation tests and sdl3-runtime-bridge-smoke",
    },
    .{
        .name = "redisplay.shaped_run_capture",
        .status = "implemented",
        .evidence = "PureRuntimeHostV1 shaped-run observation and schema-3 EUP emission tests",
    },
    .{
        .name = "host.registration_decision",
        .status = "implemented",
        .evidence = "proto-ui-host-contract approved with complete policy-only metadata",
    },
};

pub const evidence_gates = [_]EvidenceGate{
    .{
        .name = "proto-ui-unit",
        .command = "zig build -Dproto-ui=true proto-ui-unit",
        .status = "passing",
        .expected = "exit 0",
    },
    .{
        .name = "proto-ui-boundary",
        .command = "zig build -Dproto-ui=true proto-ui-boundary",
        .status = "passing",
        .expected = "exit 0 while runtime is unavailable",
    },
    .{
        .name = "proto-ui-host-contract",
        .command = "zig build -Dproto-ui=true proto-ui-host-contract",
        .status = "passing",
        .expected = "exit 0 and approved policy-only registration decision",
    },
    .{
        .name = "runtime-fail-closed",
        .command = "zig build -Dproto-ui=true -Dproto-ui-runtime=true proto-ui-boundary",
        .status = "passing-by-failing",
        .expected = "exit 1 with runtime_host_linkage_or_registration_missing",
    },
    .{
        .name = "pure-proto-frame",
        .command = "zig build -Dpgtk=false -Dproto-ui=true -Dproto-ui-runtime=true -Dsdl3-frontend=true sdl3-pure-frame",
        .status = "pending",
        .expected = "real window-system=proto frame rendered by SDL3",
    },
    .{
        .name = "pgtk-differential-parity",
        .command = "zig build -Dproto-ui=true -Dsdl3-frontend=true sdl3-pgtk-parity",
        .status = "pending",
        .expected = "PGTK reference and Proto semantic matrix agree",
    },
};

pub const Proposal = struct {
    status: ProposalStatus = .approved,
    registered: bool = false,
    runtime_available: bool = false,
    decision_status: []const u8 = "approved",
    reason_code: []const u8 = runtime.reason_code,
};

fn expectedPrerequisite(name: []const u8) ?Prerequisite {
    for (prerequisites) |item| {
        if (std.mem.eql(u8, item.name, name)) return item;
    }
    return null;
}

fn validateProposalState(candidate: Proposal) ?[]const u8 {
    if (candidate.status != .approved) return "proposal is not approved";
    if (candidate.registered) return "proposal unexpectedly claims registration";
    if (candidate.runtime_available) return "proposal unexpectedly claims runtime";
    if (!std.mem.eql(u8, candidate.decision_status, "approved"))
        return "proposal decision is not approved";
    if (!std.mem.eql(u8, candidate.reason_code, runtime.reason_code))
        return "proposal reason code changed";
    return null;
}

pub fn validateState() ?[]const u8 {
    if (validateProposalState(proposal)) |problem| return problem;
    if (host_contract.decision.status != .approved)
        return "source host-contract decision is not approved";
    if (runtime.runtime_state.runtime_available or !runtime.runtime_state.fail_closed)
        return "source runtime is not fail-closed";
    if (!target.pure_sdl3_ui or !target.pgtk_reference_only)
        return "pure SDL3 target policy is incomplete";
    if (target.pgtk_runtime_fallback_allowed or target.tty_runtime_fallback_allowed)
        return "runtime fallback is not forbidden";
    if (target.frontend_may_evaluate_elisp or target.frontend_may_own_emacs_layout)
        return "frontend ownership policy is invalid";

    const required = [_][]const u8{
        "terminal.lifecycle_state_machine",
        "runtime.fail_closed_manifest",
        "adapter.generated_c_shim",
        "adapter.host_shim_library",
        "frame.service_mapping",
        "capture.atomic_batches",
        "redisplay.resource_capture",
        "redisplay.shaped_run_capture",
        "host.registration_decision",
    };
    if (prerequisites.len != required.len) return "unexpected prerequisite count";
    for (required) |name| {
        const item = expectedPrerequisite(name) orelse return "missing prerequisite";
        if (item.status.len == 0 or item.evidence.len == 0)
            return "incomplete prerequisite";
    }

    const required_gates = [_][]const u8{
        "proto-ui-unit",
        "proto-ui-boundary",
        "proto-ui-host-contract",
        "runtime-fail-closed",
        "pure-proto-frame",
        "pgtk-differential-parity",
    };
    if (evidence_gates.len != required_gates.len)
        return "unexpected evidence-gate count";
    for (evidence_gates, 0..) |gate, index| {
        if (!std.mem.eql(u8, gate.name, required_gates[index]))
            return "unexpected evidence gate";
        if (gate.command.len == 0 or gate.expected.len == 0)
            return "incomplete evidence gate";
    }
    return null;
}

pub fn writeProposal(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (validateState() != null) return Error.InvalidR7Proposal;
    try out.appendSlice(gpa, "{\"manifest_version\":");
    try out.print(gpa, "{d}", .{manifest_version});
    try out.appendSlice(gpa, ",\"kind\":\"proto-ui-r7-registration-proposal\",");
    try out.appendSlice(gpa, "\"authoritative_source\":\"");
    try out.appendSlice(gpa, authoritative_source);
    try out.appendSlice(gpa, "\",\"proposal_schema_version\":");
    try out.print(gpa, "{d}", .{proposal_schema_version});
    try out.appendSlice(gpa, ",\"proposal_id\":");
    try runtime.appendJsonStringPublic(gpa, out, proposal_id);
    try out.appendSlice(gpa, ",\"proposal_status\":\"");
    try out.appendSlice(gpa, @tagName(proposal.status));
    try out.appendSlice(gpa, "\",\"registered\":");
    try out.print(gpa, "{}", .{proposal.registered});
    try out.appendSlice(gpa, ",\"runtime_available\":");
    try out.print(gpa, "{}", .{proposal.runtime_available});
    try out.appendSlice(gpa, ",\"decision_status\":");
    try runtime.appendJsonStringPublic(gpa, out, proposal.decision_status);
    try out.appendSlice(gpa, ",\"reason_code\":");
    try runtime.appendJsonStringPublic(gpa, out, proposal.reason_code);
    try out.appendSlice(gpa, ",\"target\":{\"ui_backend\":");
    try runtime.appendJsonStringPublic(gpa, out, target.ui_backend);
    try out.appendSlice(gpa, ",\"terminal_type\":");
    try runtime.appendJsonStringPublic(gpa, out, target.terminal_type);
    try out.appendSlice(gpa, ",\"pure_sdl3_ui\":");
    try out.print(gpa, "{}", .{target.pure_sdl3_ui});
    try out.appendSlice(gpa, ",\"pgtk_reference_only\":");
    try out.print(gpa, "{}", .{target.pgtk_reference_only});
    try out.appendSlice(gpa, ",\"pgtk_runtime_fallback_allowed\":");
    try out.print(gpa, "{}", .{target.pgtk_runtime_fallback_allowed});
    try out.appendSlice(gpa, ",\"tty_runtime_fallback_allowed\":");
    try out.print(gpa, "{}", .{target.tty_runtime_fallback_allowed});
    try out.appendSlice(gpa, ",\"frontend_may_evaluate_elisp\":");
    try out.print(gpa, "{}", .{target.frontend_may_evaluate_elisp});
    try out.appendSlice(gpa, ",\"frontend_may_own_emacs_layout\":");
    try out.print(gpa, "{}", .{target.frontend_may_own_emacs_layout});
    try out.appendSlice(gpa, "},\"required_callback_groups\":[");
    for (runtime.callback_groups, 0..) |group, index| {
        if (index != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"name\":\"");
        try out.appendSlice(gpa, @tagName(group));
        try out.appendSlice(gpa, "\",\"required\":true,\"operations\":");
        try runtime.appendJsonStringArrayPublic(gpa, out, group.operations());
        try out.appendSlice(gpa, ",\"ownership\":");
        try runtime.appendJsonStringPublic(gpa, out, group.ownership());
        try out.append(gpa, '}');
    }
    try out.appendSlice(gpa, "],\"prerequisites\":[");
    for (prerequisites, 0..) |item, index| {
        if (index != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"name\":");
        try runtime.appendJsonStringPublic(gpa, out, item.name);
        try out.appendSlice(gpa, ",\"status\":");
        try runtime.appendJsonStringPublic(gpa, out, item.status);
        try out.appendSlice(gpa, ",\"evidence\":");
        try runtime.appendJsonStringPublic(gpa, out, item.evidence);
        try out.append(gpa, '}');
    }
    try out.appendSlice(gpa, "],\"evidence_gates\":[");
    for (evidence_gates, 0..) |gate, index| {
        if (index != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"name\":");
        try runtime.appendJsonStringPublic(gpa, out, gate.name);
        try out.appendSlice(gpa, ",\"command\":");
        try runtime.appendJsonStringPublic(gpa, out, gate.command);
        try out.appendSlice(gpa, ",\"status\":");
        try runtime.appendJsonStringPublic(gpa, out, gate.status);
        try out.appendSlice(gpa, ",\"expected\":");
        try runtime.appendJsonStringPublic(gpa, out, gate.expected);
        try out.append(gpa, '}');
    }
    try out.appendSlice(gpa, "]}\n");
}

test "R7 proposal records the approved decision but remains fail closed" {
    try std.testing.expectEqual(ProposalStatus.approved, proposal.status);
    try std.testing.expect(!proposal.registered);
    try std.testing.expect(!proposal.runtime_available);
    try std.testing.expectEqualStrings(runtime.reason_code, proposal.reason_code);
    try std.testing.expectEqual(@as(?[]const u8, null), validateState());
}

test "registered or runtime-capable R7 proposals fail validation" {
    var registered = proposal;
    registered.registered = true;
    try std.testing.expectEqualStrings(
        "proposal unexpectedly claims registration",
        validateProposalState(registered).?,
    );

    var runtime_enabled = proposal;
    runtime_enabled.runtime_available = true;
    try std.testing.expectEqualStrings(
        "proposal unexpectedly claims runtime",
        validateProposalState(runtime_enabled).?,
    );
}

test "R7 proposal JSON is deterministic and policy complete" {
    const gpa = std.testing.allocator;
    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(gpa);
    try writeProposal(gpa, &first);
    try writeProposal(gpa, &second);
    try std.testing.expectEqualSlices(u8, first.items, second.items);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"proposal_status\":\"approved\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"registered\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"runtime_available\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"pgtk_runtime_fallback_allowed\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"frontend_may_evaluate_elisp\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"host.registration_decision\"") != null);
}
