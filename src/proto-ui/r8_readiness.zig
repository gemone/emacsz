//! Source-authoritative R8 entry-readiness policy.
//!
//! R8 means a real terminal and frame, not another fake-host or public-fact
//! fixture.  R7 is approved and the adapter is selected.  Opt-in target-specific
//! linkage can advance the linkage requirement, but registration remains a
//! separate mandatory condition, so R8 entry always stays blocked in this slice.

const std = @import("std");
const host_contract = @import("host_contract.zig");
const host_adapter = @import("host_adapter.zig");
const adapter_linkage = @import("r8_adapter_linkage.zig");
const runtime = @import("runtime.zig");

pub const manifest_version: u32 = 1;
pub const readiness_schema_version: u32 = 1;
pub const authoritative_source = "src/proto-ui/r8_readiness.zig";
pub const blocked_reason_code = "r8_host_adapter_linkage_or_registration_missing";

pub const Status = enum {
    pending,
    implemented,
};

pub const Requirement = struct {
    name: []const u8,
    status: Status,
    required: bool = true,
    evidence: []const u8,
};

pub const requirements = [_]Requirement{
    .{
        .name = "r7.reviewed_decision",
        .status = .implemented,
        .evidence = "proto-ui-host-contract records the complete policy-only R7 approval metadata",
    },
    .{
        .name = "adapter.linked_without_inherited_source_edits",
        .status = .pending,
        .evidence = "Candidate artifact, ABI/table inventory hash, and planned injection point are pinned by r8_adapter_linkage.json; an R7-approved Emacs link remains required",
    },
    .{
        .name = "core.terminal_provider_extension",
        .status = .pending,
        .evidence = "TP2 adapter policy conformance is complete, but TP1 remains unauthorized; no generic core dispatch, provider registration, or output_proto terminal exists",
    },
    .{
        .name = "static_isolation",
        .status = .implemented,
        .evidence = "proto-ui-isolation-audit and default-build Proto-UI exclusion",
    },
    .{
        .name = "callback_conformance",
        .status = .implemented,
        .evidence = "PureRuntimeHostV1 fake-host ABI conformance and adapter prerequisite records",
    },
    .{
        .name = "process_crash_containment",
        .status = .implemented,
        .evidence = "proto-ui-crash-isolation",
    },
    .{
        .name = "fail_closed_runtime_manifest",
        .status = .implemented,
        .evidence = "proto-ui-runtime manifest and required nonzero runtime boundary without a linked registered adapter",
    },
    .{
        .name = "rollback_and_disable",
        .status = .implemented,
        .evidence = "runtime activation sequence, reverse rollback order, and default-off feature flags",
    },
};

pub const rollback_order = [_][]const u8{
    "frontend.transport_stopped",
    "redisplay.capture_cancelled",
    "frame.unregistered",
    "terminal.drained",
    "terminal.deleted",
    "host_adapter.unselected",
};

pub const Error = error{
    InvalidR8Readiness,
};

pub fn requirementsFor(runtime_linking: bool) [requirements.len]Requirement {
    var result = requirements;
    result[1] = if (!runtime_linking) .{
        .name = "adapter.linked_without_inherited_source_edits",
        .status = .pending,
        .evidence = "Candidate artifact, ABI/table inventory hash, and planned injection point are pinned by r8_adapter_linkage.json; an R7-approved Emacs link remains required",
    } else .{
        .name = "adapter.linked_without_inherited_source_edits",
        .status = .implemented,
        .evidence = "The selected adapter-owned static candidate is forced into the native Linux glibc temacs link graph and verified in the linked ELF",
    };
    return result;
}

pub fn entryReadyFor(runtime_linking: bool) bool {
    for (requirementsFor(runtime_linking)) |requirement| {
        if (requirement.required and requirement.status != .implemented) return false;
    }
    return host_contract.decision.status == .approved and
        host_contract.metadataComplete() and
        host_adapter.current.status == .selected and
        host_adapter.current.activation_allowed;
}

pub fn entryReady() bool {
    return entryReadyFor(false);
}

pub fn validateState() ?[]const u8 {
    return validateLinkedState(false);
}

pub fn validateLinkedState(runtime_linking: bool) ?[]const u8 {
    if (readiness_schema_version != 1) return "unsupported readiness schema";
    if (host_adapter.candidate_input.candidate.inherited_source_paths_modified.len != 0)
        return "invalid inherited-source audit";
    if (host_adapter.validateState()) |problem| return problem;
    if (entryReadyFor(runtime_linking)) return "R8 entry unexpectedly ready";
    if (entry_status != .blocked) return "entry status is not blocked";
    if (!std.mem.eql(u8, reason_code, blocked_reason_code)) return "entry reason changed";
    if (activation_allowed or runtime_available or default_enabled) return "blocked entry allows runtime";
    if (tracked_inherited_source_edits.len != 0) return "readiness claims inherited-source edits";

    const expected_names = [_][]const u8{
        "r7.reviewed_decision",
        "adapter.linked_without_inherited_source_edits",
        "core.terminal_provider_extension",
        "static_isolation",
        "callback_conformance",
        "process_crash_containment",
        "fail_closed_runtime_manifest",
        "rollback_and_disable",
    };
    if (requirements.len != expected_names.len) return "readiness requirement count changed";
    const linked_requirements = requirementsFor(runtime_linking);
    for (linked_requirements, 0..) |requirement, index| {
        if (!std.mem.eql(u8, requirement.name, expected_names[index])) return "readiness requirement changed";
        if (!requirement.required) return "readiness requirement became optional";
        if (requirement.evidence.len == 0) return "readiness evidence is empty";
    }
    const expected_rollback = [_][]const u8{
        "frontend.transport_stopped",
        "redisplay.capture_cancelled",
        "frame.unregistered",
        "terminal.drained",
        "terminal.deleted",
        "host_adapter.unselected",
    };
    if (rollback_order.len != expected_rollback.len) return "rollback order changed";
    for (rollback_order, 0..) |step, index| {
        if (!std.mem.eql(u8, step, expected_rollback[index])) return "rollback step changed";
    }
    return null;
}

pub const EntryStatus = enum {
    blocked,
    ready,
};

pub const entry_status: EntryStatus = .blocked;
pub const reason_code = blocked_reason_code;
pub const activation_allowed = false;
pub const runtime_available = false;
pub const default_enabled = false;
pub const tracked_inherited_source_edits: []const []const u8 = &.{};

/// Emits canonical compact JSON: deterministic across hosts and runs.
pub fn writeManifest(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    return writeLinkedManifest(gpa, out, false);
}

pub fn writeLinkedManifest(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    runtime_linking: bool,
) !void {
    if (validateLinkedState(runtime_linking) != null) return Error.InvalidR8Readiness;
    const linked_requirements = requirementsFor(runtime_linking);
    const linked_adapter_state = adapter_linkage.linkedState(runtime_linking);
    try out.appendSlice(gpa, "{\"manifest_version\":");
    try out.print(gpa, "{d}", .{manifest_version});
    try out.appendSlice(gpa, ",\"kind\":\"proto-ui-r8-entry-readiness\",");
    try out.appendSlice(gpa, "\"authoritative_source\":");
    try runtime.appendJsonStringPublic(gpa, out, authoritative_source);
    try out.appendSlice(gpa, ",\"readiness_schema_version\":");
    try out.print(gpa, "{d}", .{readiness_schema_version});
    try out.appendSlice(gpa, ",\"entry_status\":\"");
    try out.appendSlice(gpa, @tagName(entry_status));
    try out.appendSlice(gpa, "\",\"reason_code\":");
    try runtime.appendJsonStringPublic(gpa, out, reason_code);
    try out.appendSlice(gpa, ",\"r7_decision\":\"");
    try out.appendSlice(gpa, @tagName(host_contract.decision.status));
    try out.print(gpa, "\",\"runtime_linking\":{}", .{runtime_linking});
    try out.appendSlice(gpa, ",\"default_enabled\":");
    try out.print(gpa, "{}", .{default_enabled});
    try out.appendSlice(gpa, ",\"activation_allowed\":");
    try out.print(gpa, "{}", .{activation_allowed});
    try out.appendSlice(gpa, ",\"runtime_available\":");
    try out.print(gpa, "{}", .{runtime_available});
    try out.appendSlice(gpa, ",\"tracked_inherited_source_edits\":");
    try runtime.appendJsonStringArrayPublic(gpa, out, tracked_inherited_source_edits);
    try out.appendSlice(gpa, ",\"adapter_linkage\":{\"status\":");
    try runtime.appendJsonStringPublic(gpa, out, linked_adapter_state.status);
    try out.appendSlice(gpa, ",\"linked_target\":");
    try runtime.appendJsonStringPublic(gpa, out, if (runtime_linking) adapter_linkage.linked_target else "");
    try out.appendSlice(gpa, ",\"artifact_id\":");
    try runtime.appendJsonStringPublic(
        gpa,
        out,
        if (runtime_linking) adapter_linkage.target_artifact_id else adapter_linkage.artifact_id,
    );
    try out.appendSlice(gpa, ",\"abi_table_sha256\":");
    const abi_hash = adapter_linkage.abiTableHash();
    try runtime.appendJsonStringPublic(gpa, out, &abi_hash);
    try out.appendSlice(gpa, "},\"requirements\":[");
    for (linked_requirements, 0..) |requirement, index| {
        if (index != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"name\":");
        try runtime.appendJsonStringPublic(gpa, out, requirement.name);
        try out.appendSlice(gpa, ",\"status\":\"");
        try out.appendSlice(gpa, @tagName(requirement.status));
        try out.appendSlice(gpa, "\",\"required\":");
        try out.print(gpa, "{}", .{requirement.required});
        try out.appendSlice(gpa, ",\"evidence\":");
        try runtime.appendJsonStringPublic(gpa, out, requirement.evidence);
        try out.append(gpa, '}');
    }
    try out.appendSlice(gpa, "],\"rollback_order\":[");
    for (rollback_order, 0..) |step, index| {
        if (index != 0) try out.append(gpa, ',');
        try runtime.appendJsonStringPublic(gpa, out, step);
    }
    try out.appendSlice(gpa, "]}\n");
}

test "R8 entry remains blocked without linkage or registration" {
    try std.testing.expectEqual(host_contract.DecisionStatus.approved, host_contract.decision.status);
    try std.testing.expectEqual(host_adapter.SelectionStatus.selected, host_adapter.current.status);
    try std.testing.expectEqual(@as(?[]const u8, null), validateState());
    try std.testing.expect(!entryReady());
    try std.testing.expectEqual(EntryStatus.blocked, entry_status);
    try std.testing.expect(!activation_allowed);
    try std.testing.expect(!runtime_available);
    try std.testing.expect(!default_enabled);
    try std.testing.expectEqual(@as(usize, 0), tracked_inherited_source_edits.len);
}

test "R8 entry remains blocked after opt-in adapter linkage" {
    try std.testing.expectEqual(@as(?[]const u8, null), validateLinkedState(true));
    const linked_requirements = requirementsFor(true);
    try std.testing.expectEqual(Status.implemented, linked_requirements[1].status);
    try std.testing.expectEqual(Status.pending, linked_requirements[2].status);
    try std.testing.expect(!entryReadyFor(true));
    try std.testing.expectEqual(EntryStatus.blocked, entry_status);
    try std.testing.expect(!activation_allowed);
    try std.testing.expect(!runtime_available);
}

test "R8 readiness JSON is deterministic and bounded" {
    const gpa = std.testing.allocator;
    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(gpa);
    try writeLinkedManifest(gpa, &first, true);
    try writeLinkedManifest(gpa, &second, true);
    try std.testing.expectEqualSlices(u8, first.items, second.items);
    try std.testing.expect(first.items.len < 16 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"entry_status\":\"blocked\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"r7_decision\":\"approved\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"activation_allowed\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"status\":\"linked_not_registered\"") != null);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, first.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("blocked", parsed.value.object.get("entry_status").?.string);
}
