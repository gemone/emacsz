//! Source-authoritative Proto-UI host registration decision contract.
//!
//! This is policy only.  Approval selects policy and a candidate; it never
//! registers a terminal, enables `output_proto`, or changes inherited Emacs
//! C/Lisp.

const std = @import("std");
const runtime = @import("runtime.zig");

pub const manifest_version: u32 = 1;
pub const contract_schema_version: u32 = 1;
pub const authoritative_source = "src/proto-ui/host_contract.zig";
pub const pending_reason_code = "host_registration_contract_missing";
pub const approved_reason_code = runtime.reason_code;
pub const approved_reviewer = "Proto-UI Dedicated Review Agent";
pub const approved_decision_id = "R7:pure-sdl3-output-proto-terminal:2026-09-10";
pub const approved_reviewed_at = "2026-09-10T09:49:41Z";
pub const approved_scope = "policy_and_candidate_selection_only";

pub const DecisionStatus = enum {
    pending,
    approved,
    rejected,
};

pub const DecisionMetadata = struct {
    reviewer: ?[]const u8 = null,
    decision_id: ?[]const u8 = null,
    reviewed_at: ?[]const u8 = null,
    approval_scope: ?[]const u8 = null,
};

pub const Decision = struct {
    status: DecisionStatus = .approved,
    reason_code: []const u8 = approved_reason_code,
    metadata: DecisionMetadata = .{
        .reviewer = approved_reviewer,
        .decision_id = approved_decision_id,
        .reviewed_at = approved_reviewed_at,
        .approval_scope = approved_scope,
    },
};

pub const decision = Decision{};

pub const acceptable_integration_mechanism =
    "A separately reviewed generic Terminal Provider Extension and an " ++
    "adapter-owned Emacs host adapter supply the complete versioned callback " ++
    "groups through the seam selected and linked by zig build.";

pub const forbidden_mechanisms = [_][]const u8{
    "Direct edits to inherited GNU Emacs C or Lisp source for Proto-UI",
    "Implicit enablement in the default Emacs build or existing PGTK/TTY backends",
    "Frontend evaluation of Emacs Lisp",
    "Frontend ownership of Emacs buffer, window, frame, face, or layout truth",
    "Unversioned global state or undocumented host function-pointer casts",
};

pub const FrontendContract = struct {
    may_render_protocol_scenes: bool = true,
    may_capture_platform_input: bool = true,
    may_evaluate_elisp: bool = false,
    may_own_emacs_layout: bool = false,
};

pub const frontend_contract = FrontendContract{};

pub const EvidenceGate = struct {
    name: []const u8,
    command: []const u8,
    expected_result: []const u8,
    reason_code: ?[]const u8 = null,
};

pub const required_evidence_gates = [_]EvidenceGate{
    .{
        .name = "proto-ui-host-contract",
        .command = "zig build -Dproto-ui=true proto-ui-host-contract",
        .expected_result = "exit 0 for the source-authoritative approved policy-only decision",
    },
    .{
        .name = "proto-ui-unit",
        .command = "zig build -Dproto-ui=true proto-ui-unit",
        .expected_result = "exit 0",
    },
    .{
        .name = "proto-ui-boundary",
        .command = "zig build -Dproto-ui=true proto-ui-boundary",
        .expected_result = "exit 0 while runtime is unavailable",
    },
    .{
        .name = "runtime-fail-closed",
        .command = "zig build -Dproto-ui=true -Dproto-ui-runtime=true proto-ui-boundary",
        .expected_result = "nonzero exit while adapter linkage or terminal registration is absent",
        .reason_code = runtime.reason_code,
    },
};

pub const rollback_disable_guarantees = [_][]const u8{
    "Proto-UI runtime options default to false.",
    "A disabled build has no Proto-UI runtime initialization or inherited-backend coupling.",
    "Removing the optional host adapter selection restores the prior fail-closed build.",
    "Runtime shutdown drains pending adapter work and unregisters protocol identities before returning.",
};

pub const default_build_isolation_guarantee =
    "The default build compiles no Proto-UI runtime adapter, registers no " ++
    "terminal, changes no existing backend behavior, and preserves the " ++
    "byte-identical inherited core path outside explicit Proto-UI tooling.";

pub const Error = error{
    InvalidHostContract,
    UnsupportedSchemaVersion,
    InvalidDecisionStatus,
};

pub fn validateDecision() ?[]const u8 {
    switch (decision.status) {
        .pending => {
            if (!std.mem.eql(u8, decision.reason_code, pending_reason_code))
                return "pending reason changed";
            if (metadataPresent()) return "pending decision has review metadata";
            if (metadataComplete()) return "pending decision has review metadata";
        },
        .approved => {
            if (!metadataComplete()) return "approved decision lacks complete review metadata";
            if (!std.mem.eql(u8, decision.metadata.reviewer.?, approved_reviewer) or
                !std.mem.eql(u8, decision.metadata.decision_id.?, approved_decision_id) or
                !std.mem.eql(u8, decision.metadata.reviewed_at.?, approved_reviewed_at) or
                !std.mem.eql(u8, decision.metadata.approval_scope.?, approved_scope))
                return "approved decision metadata changed";
            if (!std.mem.eql(u8, decision.reason_code, approved_reason_code))
                return "approved reason changed";
        },
        .rejected => {
            if (!metadataComplete()) return "rejected decision lacks complete review metadata";
            if (decision.reason_code.len == 0) return "rejected decision lacks reason";
        },
    }
    return null;
}

pub fn validateState() ?[]const u8 {
    if (contract_schema_version != 1) return "unsupported contract schema";
    if (acceptable_integration_mechanism.len == 0) return "missing integration mechanism";
    if (forbidden_mechanisms.len == 0) return "missing forbidden mechanisms";
    for (forbidden_mechanisms) |mechanism| {
        if (mechanism.len == 0) return "empty forbidden mechanism";
    }
    if (frontend_contract.may_evaluate_elisp) return "frontend may evaluate Elisp";
    if (frontend_contract.may_own_emacs_layout) return "frontend may own Emacs layout";
    for (required_evidence_gates) |gate| {
        if (gate.name.len == 0 or gate.command.len == 0 or gate.expected_result.len == 0)
            return "incomplete evidence gate";
    }
    if (rollback_disable_guarantees.len < 4) return "incomplete rollback guarantees";
    for (rollback_disable_guarantees) |guarantee| {
        if (guarantee.len == 0) return "empty rollback guarantee";
    }
    if (default_build_isolation_guarantee.len == 0) return "missing isolation guarantee";
    for (runtime.callback_groups) |group| {
        if (group.operations().len == 0) return "empty callback group";
    }
    return validateDecision();
}

pub fn validateArtifact(value: std.json.Value) ?[]const u8 {
    if (value != .object) return "contract is not an object";
    const object = value.object;
    if (object.count() != 12) return "contract field set changed";
    if (integer(object, "manifest_version") != manifest_version) return "manifest version changed";
    if (integer(object, "contract_schema_version") != contract_schema_version) return "schema version changed";
    if (!equalsString(object, "kind", "proto-ui-host-registration-contract")) return "kind changed";
    if (!equalsString(object, "authoritative_source", authoritative_source)) return "authoritative source changed";

    const decision_value = object.get("decision") orelse return "missing decision";
    if (decision_value != .object) return "decision is not an object";
    const decision_object = decision_value.object;
    if (decision_object.count() != 3) return "decision field set changed";
    const status_value = decision_object.get("status") orelse return "missing decision status";
    if (status_value != .string) return "decision status is not a string";
    const status = std.meta.stringToEnum(DecisionStatus, status_value.string) orelse
        return "invalid decision status";
    if (status == .pending) {
        if (!equalsString(decision_object, "reason_code", pending_reason_code))
            return "pending reason changed";
        if (!metadataNull(decision_object)) return "pending metadata is not placeholder";
    } else if (status == .approved) {
        if (!equalsString(decision_object, "reason_code", approved_reason_code))
            return "approved reason changed";
        if (!metadataCompleteValue(decision_object)) return "decision lacks review metadata";
        const metadata = decision_object.get("metadata").?.object;
        if (!equalsString(metadata, "reviewer", approved_reviewer) or
            !equalsString(metadata, "decision_id", approved_decision_id) or
            !equalsString(metadata, "reviewed_at", approved_reviewed_at) or
            !equalsString(metadata, "approval_scope", approved_scope))
            return "approved decision metadata changed";
    } else {
        if (!metadataCompleteValue(decision_object)) return "decision lacks review metadata";
    }

    if (!equalsString(object, "acceptable_integration_mechanism", acceptable_integration_mechanism))
        return "integration mechanism changed";
    if (!equalsStringArray(object, "forbidden_mechanisms", &forbidden_mechanisms))
        return "forbidden mechanisms changed";
    if (!equalsString(object, "default_build_isolation_guarantee", default_build_isolation_guarantee))
        return "isolation guarantee changed";
    if (!equalsStringArray(object, "rollback_disable_guarantees", &rollback_disable_guarantees))
        return "rollback guarantees changed";

    const frontend_value = object.get("frontend_contract") orelse return "missing frontend contract";
    if (frontend_value != .object) return "frontend contract is not an object";
    if (frontend_value.object.count() != 4) return "frontend field set changed";
    if (!boolean(frontend_value.object, "may_render_protocol_scenes")) return "frontend cannot render scenes";
    if (!boolean(frontend_value.object, "may_capture_platform_input")) return "frontend cannot capture input";
    if (boolean(frontend_value.object, "may_evaluate_elisp")) return "frontend may evaluate Elisp";
    if (boolean(frontend_value.object, "may_own_emacs_layout")) return "frontend may own Emacs layout";

    const groups_value = object.get("required_callback_groups") orelse return "missing callback groups";
    if (groups_value != .array) return "callback groups are not an array";
    if (groups_value.array.items.len != runtime.callback_groups.len) return "callback group count changed";
    for (runtime.callback_groups, groups_value.array.items) |expected_group, actual_value| {
        if (actual_value != .object) return "callback group is not an object";
        const group = actual_value.object;
        if (group.count() != 4) return "callback field set changed";
        if (!equalsString(group, "name", @tagName(expected_group))) return "callback group name changed";
        if (!boolean(group, "required")) return "callback group is optional";
        if (!equalsStringArray(group, "operations", expected_group.operations()))
            return "callback operations changed";
        if (!equalsString(group, "ownership", expected_group.ownership()))
            return "callback ownership changed";
    }

    const evidence_value = object.get("required_evidence_gates") orelse return "missing evidence gates";
    if (evidence_value != .array) return "evidence gates are not an array";
    if (evidence_value.array.items.len != required_evidence_gates.len) return "evidence gate count changed";
    for (required_evidence_gates, evidence_value.array.items) |expected_gate, actual_value| {
        if (actual_value != .object) return "evidence gate is not an object";
        const gate = actual_value.object;
        if (gate.count() != 4) return "evidence field set changed";
        if (!equalsString(gate, "name", expected_gate.name)) return "evidence gate name changed";
        if (!equalsString(gate, "command", expected_gate.command)) return "evidence gate command changed";
        if (!equalsString(gate, "expected_result", expected_gate.expected_result))
            return "evidence expectation changed";
        const expected_reason = expected_gate.reason_code orelse "";
        if (!equalsString(gate, "reason_code", expected_reason)) return "evidence reason changed";
    }
    return null;
}

fn metadataPresent() bool {
    return decision.metadata.reviewer != null or
        decision.metadata.decision_id != null or
        decision.metadata.reviewed_at != null or
        decision.metadata.approval_scope != null;
}

pub fn metadataComplete() bool {
    return nonempty(decision.metadata.reviewer) and
        nonempty(decision.metadata.decision_id) and
        nonempty(decision.metadata.reviewed_at) and
        nonempty(decision.metadata.approval_scope);
}

fn nonempty(value: ?[]const u8) bool {
    return value != null and value.?.len > 0;
}

fn metadataNull(object: std.json.ObjectMap) bool {
    const metadata_value = object.get("metadata") orelse return false;
    if (metadata_value != .object) return false;
    for ([_][]const u8{ "reviewer", "decision_id", "reviewed_at", "approval_scope" }) |key| {
        const field = metadata_value.object.get(key) orelse return false;
        if (field != .null) return false;
    }
    return metadata_value.object.count() == 4;
}

fn metadataCompleteValue(object: std.json.ObjectMap) bool {
    const metadata_value = object.get("metadata") orelse return false;
    if (metadata_value != .object) return false;
    for ([_][]const u8{ "reviewer", "decision_id", "reviewed_at", "approval_scope" }) |key| {
        const field = metadata_value.object.get(key) orelse return false;
        if (field != .string or field.string.len == 0) return false;
    }
    return metadata_value.object.count() == 4;
}

fn integer(object: std.json.ObjectMap, key: []const u8) i64 {
    const value = object.get(key) orelse return -1;
    if (value != .integer) return -1;
    return value.integer;
}

fn boolean(object: std.json.ObjectMap, key: []const u8) bool {
    const value = object.get(key) orelse return false;
    if (value != .bool) return false;
    return value.bool;
}

fn equalsString(object: std.json.ObjectMap, key: []const u8, expected: []const u8) bool {
    const value = object.get(key) orelse return false;
    return value == .string and std.mem.eql(u8, value.string, expected);
}

fn equalsStringArray(object: std.json.ObjectMap, key: []const u8, expected: []const []const u8) bool {
    const value = object.get(key) orelse return false;
    if (value != .array or value.array.items.len != expected.len) return false;
    for (expected, value.array.items) |expected_item, actual_value| {
        if (actual_value != .string or !std.mem.eql(u8, actual_value.string, expected_item))
            return false;
    }
    return true;
}

pub fn appendMetadata(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    metadata: DecisionMetadata,
) !void {
    try out.appendSlice(gpa, "{\"reviewer\":");
    try appendOptionalString(gpa, out, metadata.reviewer);
    try out.appendSlice(gpa, ",\"decision_id\":");
    try appendOptionalString(gpa, out, metadata.decision_id);
    try out.appendSlice(gpa, ",\"reviewed_at\":");
    try appendOptionalString(gpa, out, metadata.reviewed_at);
    try out.appendSlice(gpa, ",\"approval_scope\":");
    try appendOptionalString(gpa, out, metadata.approval_scope);
    try out.appendSlice(gpa, "}");
}

fn appendOptionalString(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    value: ?[]const u8,
) !void {
    if (value) |text| {
        try runtime.appendJsonStringPublic(gpa, out, text);
    } else {
        try out.appendSlice(gpa, "null");
    }
}

/// Emits canonical compact JSON: deterministic across hosts and runs.
pub fn writeContract(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (validateState() != null) return Error.InvalidHostContract;
    try out.appendSlice(gpa, "{\"manifest_version\":");
    try out.print(gpa, "{d}", .{manifest_version});
    try out.append(gpa, ',');
    try out.appendSlice(gpa, "\"kind\":\"proto-ui-host-registration-contract\",");
    try out.appendSlice(gpa, "\"authoritative_source\":\"");
    try out.appendSlice(gpa, authoritative_source);
    try out.appendSlice(gpa, "\",\"contract_schema_version\":");
    try out.print(gpa, "{d}", .{contract_schema_version});
    try out.appendSlice(gpa, ",\"decision\":{\"status\":\"");
    try out.appendSlice(gpa, @tagName(decision.status));
    try out.appendSlice(gpa, "\",\"reason_code\":");
    try runtime.appendJsonStringPublic(gpa, out, decision.reason_code);
    try out.appendSlice(gpa, ",\"metadata\":");
    try appendMetadata(gpa, out, decision.metadata);
    try out.appendSlice(gpa, "},\"acceptable_integration_mechanism\":");
    try runtime.appendJsonStringPublic(gpa, out, acceptable_integration_mechanism);
    try out.appendSlice(gpa, ",\"forbidden_mechanisms\":");
    try runtime.appendJsonStringArrayPublic(gpa, out, &forbidden_mechanisms);
    try out.appendSlice(gpa, ",\"required_callback_groups\":[");
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
    try out.appendSlice(gpa, "],\"required_evidence_gates\":[");
    for (required_evidence_gates, 0..) |gate, index| {
        if (index != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"name\":");
        try runtime.appendJsonStringPublic(gpa, out, gate.name);
        try out.appendSlice(gpa, ",\"command\":");
        try runtime.appendJsonStringPublic(gpa, out, gate.command);
        try out.appendSlice(gpa, ",\"expected_result\":");
        try runtime.appendJsonStringPublic(gpa, out, gate.expected_result);
        try out.appendSlice(gpa, ",\"reason_code\":");
        try runtime.appendJsonStringPublic(gpa, out, gate.reason_code orelse "");
        try out.append(gpa, '}');
    }
    try out.appendSlice(gpa, "],\"rollback_disable_guarantees\":");
    try runtime.appendJsonStringArrayPublic(gpa, out, &rollback_disable_guarantees);
    try out.appendSlice(gpa, ",\"default_build_isolation_guarantee\":");
    try runtime.appendJsonStringPublic(gpa, out, default_build_isolation_guarantee);
    try out.appendSlice(gpa, ",\"frontend_contract\":{\"may_render_protocol_scenes\":");
    try out.print(gpa, "{}", .{frontend_contract.may_render_protocol_scenes});
    try out.appendSlice(gpa, ",");
    try out.appendSlice(gpa, "\"may_capture_platform_input\":");
    try out.print(gpa, "{}", .{frontend_contract.may_capture_platform_input});
    try out.appendSlice(gpa, ",\"may_evaluate_elisp\":");
    try out.print(gpa, "{}", .{frontend_contract.may_evaluate_elisp});
    try out.appendSlice(gpa, ",\"may_own_emacs_layout\":");
    try out.print(gpa, "{}", .{frontend_contract.may_own_emacs_layout});
    try out.appendSlice(gpa, "}}\n");
}

test "source decision is approved policy only and runtime remains fail-closed" {
    try std.testing.expectEqual(DecisionStatus.approved, decision.status);
    try std.testing.expectEqualStrings(approved_reason_code, runtime.reason_code);
    try std.testing.expectEqual(@as(?[]const u8, null), validateState());
    try std.testing.expect(frontend_contract.may_render_protocol_scenes);
    try std.testing.expect(!frontend_contract.may_evaluate_elisp);
    try std.testing.expect(!frontend_contract.may_own_emacs_layout);
}

test "contract JSON is deterministic and policy-complete" {
    const gpa = std.testing.allocator;
    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(gpa);
    try writeContract(gpa, &first);
    try writeContract(gpa, &second);
    try std.testing.expectEqualSlices(u8, first.items, second.items);
    try std.testing.expect(first.items.len < 16 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"status\":\"approved\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"reviewer\":\"Proto-UI Dedicated Review Agent\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"may_evaluate_elisp\":false") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, first.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?[]const u8, null), validateArtifact(parsed.value));
}

test "approved decisions require complete review metadata" {
    const gpa = std.testing.allocator;
    var contract: std.ArrayList(u8) = .empty;
    defer contract.deinit(gpa);
    try writeContract(gpa, &contract);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, contract.items, .{});
    defer parsed.deinit();
    const decision_object = parsed.value.object.getPtr("decision").?.object;
    const metadata_object = decision_object.getPtr("metadata").?.object;
    metadata_object.getPtr("reviewer").?.* = .null;
    metadata_object.getPtr("decision_id").?.* = .null;
    metadata_object.getPtr("reviewed_at").?.* = .null;
    metadata_object.getPtr("approval_scope").?.* = .null;
    const invalid = validateArtifact(parsed.value);
    try std.testing.expect(invalid != null);
    try std.testing.expectEqualStrings("decision lacks review metadata", invalid.?);

    const metadata = decision_object.getPtr("metadata").?.object;
    metadata.getPtr("reviewer").?.* = .{ .string = approved_reviewer };
    metadata.getPtr("decision_id").?.* = .{ .string = approved_decision_id };
    metadata.getPtr("reviewed_at").?.* = .{ .string = approved_reviewed_at };
    metadata.getPtr("approval_scope").?.* = .{ .string = approved_scope };
    try std.testing.expectEqual(@as(?[]const u8, null), validateArtifact(parsed.value));
}
