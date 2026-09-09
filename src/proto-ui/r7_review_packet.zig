//! Source-authoritative review packet for the pending R7 host decision.
//!
//! The packet packages policy, evidence, and reviewer checks.  It does not
//! approve R7, select a host adapter, register a terminal, enable
//! `output_proto`, or claim PGTK parity.

const std = @import("std");
const host_contract = @import("host_contract.zig");
const host_adapter = @import("host_adapter.zig");
const r7_proposal = @import("r7_proposal.zig");
const runtime_activation = @import("runtime_activation.zig");
const r8_readiness = @import("r8_readiness.zig");
const runtime = @import("runtime.zig");

pub const manifest_version: u32 = 1;
pub const packet_schema_version: u32 = 1;
pub const authoritative_source = "src/proto-ui/r7_review_packet.zig";
pub const packet_id = r7_proposal.proposal_id ++ ":review";
pub const reason_code = runtime.reason_code;
pub const activation_rule =
    "A reviewer approves every checklist item, records complete metadata, and " ++
    "updates the source contract in a separate reviewed commit.  The packet " ++
    "itself never activates the runtime.";

pub const PacketStatus = enum {
    draft,
    ready_for_review,
    withdrawn,
};

pub const CheckStatus = enum {
    pending,
    approved,
    rejected,
};

pub const ReviewItem = struct {
    id: []const u8,
    question: []const u8,
    status: CheckStatus = .pending,
};

pub const InputKind = enum {
    proposal,
    contract,
    adapter_selection,
    activation,
    readiness,
};

pub const ReviewInput = struct {
    kind: InputKind,
    name: []const u8,
    artifact: []const u8,
};

pub const ReferenceDocument = struct {
    name: []const u8,
    artifact: []const u8,
};

pub const Packet = struct {
    status: PacketStatus = .ready_for_review,
    approved: bool = false,
    registered: bool = false,
    runtime_available: bool = false,
    activation_allowed: bool = false,
    fail_closed: bool = true,
    decision_status: []const u8 = "pending",
    reason_code: []const u8 = reason_code,
};

pub const packet = Packet{};
pub const approval = host_contract.DecisionMetadata{};

pub const review_items = [_]ReviewItem{
    .{
        .id = "policy.pure_sdl3_boundary",
        .question = "Is the target a pure SDL3 output_proto frontend with PGTK as reference only and no PGTK/TTY runtime fallback?",
    },
    .{
        .id = "integration.no_inherited_edits",
        .question = "Does the proposed linkage avoid edits, replacement, patching, or symbol interposition in tracked inherited Emacs C/Lisp source?",
    },
    .{
        .id = "abi.callback_table",
        .question = "Does the complete versioned terminal/frame/redisplay/input/lifecycle callback table preserve the documented ownership and generation rules?",
    },
    .{
        .id = "evidence.gates",
        .question = "Are the implemented-prerequisite, fail-closed, future pure-frame, and PGTK-differential evidence gates unambiguous and reproducible?",
    },
    .{
        .id = "rollback.disable",
        .question = "Does reverse rollback restore terminal, frame, transport, and frontend state while default builds stay isolated?",
    },
    .{
        .id = "approval.metadata",
        .question = "Are reviewer, decision ID, review time, and approval scope supplied only when the source decision changes from pending?",
    },
};

pub const review_inputs = [_]ReviewInput{
    .{
        .kind = .proposal,
        .name = "registration proposal",
        .artifact = "zig-out/proto-ui/r7_proposal.json",
    },
    .{
        .kind = .contract,
        .name = "registration contract",
        .artifact = "zig-out/proto-ui/host_registration_contract.json",
    },
    .{
        .kind = .adapter_selection,
        .name = "host adapter selection",
        .artifact = "zig-out/proto-ui/host_adapter_selection.json",
    },
    .{
        .kind = .activation,
        .name = "runtime activation contract",
        .artifact = "zig-out/proto-ui/runtime_activation.json",
    },
    .{
        .kind = .readiness,
        .name = "R8 entry readiness",
        .artifact = "zig-out/proto-ui/r8_readiness.json",
    },
};

pub const reference_documents = [_]ReferenceDocument{
    .{ .name = "runtime design", .artifact = "docs/proto-ui/output-proto-runtime.md" },
};

pub const Error = error{
    InvalidR7ReviewPacket,
} || runtime.Error;

fn expectedItemFrom(items: []const ReviewItem, id: []const u8) ?ReviewItem {
    for (items) |item| {
        if (std.mem.eql(u8, item.id, id)) return item;
    }
    return null;
}

fn approvalPresent(metadata: host_contract.DecisionMetadata) bool {
    return metadata.reviewer != null or metadata.decision_id != null or
        metadata.reviewed_at != null or metadata.approval_scope != null;
}

fn validatePacket(
    candidate: Packet,
    candidate_items: []const ReviewItem,
    candidate_approval: host_contract.DecisionMetadata,
) ?[]const u8 {
    if (packet_schema_version != 1) return "unsupported packet schema";
    if (candidate.status != .ready_for_review) return "packet is not ready for review";
    if (candidate.approved or candidate.registered or candidate.runtime_available or
        candidate.activation_allowed or !candidate.fail_closed)
        return "packet unexpectedly claims an activation outcome";
    if (!std.mem.eql(u8, candidate.decision_status, "pending"))
        return "packet decision is not pending";
    if (!std.mem.eql(u8, candidate.reason_code, runtime.reason_code))
        return "packet reason code changed";
    if (activation_rule.len == 0) return "missing activation rule";

    const required = [_][]const u8{
        "policy.pure_sdl3_boundary",
        "integration.no_inherited_edits",
        "abi.callback_table",
        "evidence.gates",
        "rollback.disable",
        "approval.metadata",
    };
    if (candidate_items.len != required.len) return "unexpected review-item count";
    for (required) |id| {
        const item = expectedItemFrom(candidate_items, id) orelse return "missing review item";
        if (item.status != .pending) return "review item is pre-approved";
        if (item.question.len == 0) return "review item lacks a question";
    }
    const required_inputs = [_]struct { kind: InputKind, name: []const u8, artifact: []const u8 }{
        .{ .kind = .proposal, .name = "registration proposal", .artifact = "zig-out/proto-ui/r7_proposal.json" },
        .{ .kind = .contract, .name = "registration contract", .artifact = "zig-out/proto-ui/host_registration_contract.json" },
        .{ .kind = .adapter_selection, .name = "host adapter selection", .artifact = "zig-out/proto-ui/host_adapter_selection.json" },
        .{ .kind = .activation, .name = "runtime activation contract", .artifact = "zig-out/proto-ui/runtime_activation.json" },
        .{ .kind = .readiness, .name = "R8 entry readiness", .artifact = "zig-out/proto-ui/r8_readiness.json" },
    };
    if (review_inputs.len != required_inputs.len) return "unexpected review-input count";
    for (review_inputs, required_inputs) |input, expected| {
        if (input.kind != expected.kind or !std.mem.eql(u8, input.name, expected.name) or
            !std.mem.eql(u8, input.artifact, expected.artifact))
            return "review-input manifest changed";
        if (input.name.len == 0 or input.artifact.len == 0)
            return "incomplete review input";
    }
    if (reference_documents.len != 1) return "unexpected reference-document count";
    for (reference_documents) |document| {
        if (document.name.len == 0 or document.artifact.len == 0)
            return "incomplete reference document";
    }
    if (approvalPresent(candidate_approval)) return "pending packet has approval metadata";

    if (r7_proposal.validateState()) |problem| return problem;
    if (host_contract.validateState()) |problem| return problem;
    if (runtime.runtime_state.runtime_available or !runtime.runtime_state.fail_closed)
        return "source runtime is not fail-closed";
    return null;
}

pub fn validateState() ?[]const u8 {
    return validatePacket(packet, &review_items, approval);
}

fn writeVerifiedInput(
    gpa: std.mem.Allocator,
    input: ReviewInput,
    out: *std.ArrayList(u8),
) !void {
    switch (input.kind) {
        .proposal => try r7_proposal.writeProposal(gpa, out),
        .contract => try host_contract.writeContract(gpa, out),
        .adapter_selection => try host_adapter.writeManifest(gpa, out),
        .activation => try runtime_activation.writeManifest(gpa, out),
        .readiness => try r8_readiness.writeManifest(gpa, out),
    }
}

fn appendInputDigest(
    gpa: std.mem.Allocator,
    input: ReviewInput,
    out: *std.ArrayList(u8),
) !void {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(gpa);
    try writeVerifiedInput(gpa, input, &bytes);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(bytes.items);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    try out.ensureUnusedCapacity(gpa, digest.len * 2);
    for (digest) |byte| {
        try out.print(gpa, "{x:0>2}", .{byte});
    }
}

/// Emits canonical compact JSON: deterministic across hosts and runs.
pub fn writePacket(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (validateState() != null) return Error.InvalidR7ReviewPacket;
    try out.appendSlice(gpa, "{\"manifest_version\":");
    try out.print(gpa, "{d}", .{manifest_version});
    try out.appendSlice(gpa, ",\"kind\":\"proto-ui-r7-review-packet\",\"authoritative_source\":");
    try runtime.appendJsonStringPublic(gpa, out, authoritative_source);
    try out.appendSlice(gpa, ",\"packet_schema_version\":");
    try out.print(gpa, "{d}", .{packet_schema_version});
    try out.appendSlice(gpa, ",\"packet_id\":");
    try runtime.appendJsonStringPublic(gpa, out, packet_id);
    try out.appendSlice(gpa, ",\"packet_status\":");
    try runtime.appendJsonStringPublic(gpa, out, @tagName(packet.status));
    try out.appendSlice(gpa, ",\"proposal_id\":");
    try runtime.appendJsonStringPublic(gpa, out, r7_proposal.proposal_id);
    try out.appendSlice(gpa, ",\"proposal_status\":");
    try runtime.appendJsonStringPublic(gpa, out, @tagName(r7_proposal.proposal.status));
    try out.appendSlice(gpa, ",\"target\":{\"ui_backend\":");
    try runtime.appendJsonStringPublic(gpa, out, r7_proposal.target.ui_backend);
    try out.appendSlice(gpa, ",\"terminal_type\":");
    try runtime.appendJsonStringPublic(gpa, out, r7_proposal.target.terminal_type);
    try out.appendSlice(gpa, ",\"pure_sdl3_ui\":");
    try out.print(gpa, "{}", .{r7_proposal.target.pure_sdl3_ui});
    try out.appendSlice(gpa, ",\"pgtk_reference_only\":");
    try out.print(gpa, "{}", .{r7_proposal.target.pgtk_reference_only});
    try out.appendSlice(gpa, ",\"pgtk_runtime_fallback_allowed\":");
    try out.print(gpa, "{}", .{r7_proposal.target.pgtk_runtime_fallback_allowed});
    try out.appendSlice(gpa, ",\"tty_runtime_fallback_allowed\":");
    try out.print(gpa, "{}", .{r7_proposal.target.tty_runtime_fallback_allowed});
    try out.appendSlice(gpa, "},\"approved\":");
    try out.print(gpa, "{}", .{packet.approved});
    try out.appendSlice(gpa, ",\"registered\":");
    try out.print(gpa, "{}", .{packet.registered});
    try out.appendSlice(gpa, ",\"runtime_available\":");
    try out.print(gpa, "{}", .{packet.runtime_available});
    try out.appendSlice(gpa, ",\"activation_allowed\":");
    try out.print(gpa, "{}", .{packet.activation_allowed});
    try out.appendSlice(gpa, ",\"fail_closed\":");
    try out.print(gpa, "{}", .{packet.fail_closed});
    try out.appendSlice(gpa, ",\"decision\":{\"status\":");
    try runtime.appendJsonStringPublic(gpa, out, packet.decision_status);
    try out.appendSlice(gpa, ",\"reason_code\":");
    try runtime.appendJsonStringPublic(gpa, out, packet.reason_code);
    try out.appendSlice(gpa, ",\"metadata\":");
    try host_contract.appendMetadata(gpa, out, approval);
    try out.appendSlice(gpa, "},\"review_items\":[");
    for (review_items, 0..) |item, index| {
        if (index != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"id\":");
        try runtime.appendJsonStringPublic(gpa, out, item.id);
        try out.appendSlice(gpa, ",\"question\":");
        try runtime.appendJsonStringPublic(gpa, out, item.question);
        try out.appendSlice(gpa, ",\"status\":");
        try runtime.appendJsonStringPublic(gpa, out, @tagName(item.status));
        try out.append(gpa, '}');
    }
    try out.appendSlice(gpa, "],\"review_inputs\":[");
    for (review_inputs, 0..) |input, index| {
        if (index != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"kind\":");
        try runtime.appendJsonStringPublic(gpa, out, @tagName(input.kind));
        try out.appendSlice(gpa, ",\"name\":");
        try runtime.appendJsonStringPublic(gpa, out, input.name);
        try out.appendSlice(gpa, ",\"artifact\":");
        try runtime.appendJsonStringPublic(gpa, out, input.artifact);
        try out.appendSlice(gpa, ",\"sha256\":\"");
        try appendInputDigest(gpa, input, out);
        try out.appendSlice(gpa, "\"}");
    }
    try out.appendSlice(gpa, "],\"reference_documents\":[");
    for (reference_documents, 0..) |document, index| {
        if (index != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"name\":");
        try runtime.appendJsonStringPublic(gpa, out, document.name);
        try out.appendSlice(gpa, ",\"artifact\":");
        try runtime.appendJsonStringPublic(gpa, out, document.artifact);
        try out.append(gpa, '}');
    }
    try out.appendSlice(gpa, "],\"required_evidence_gates\":[");
    for (r7_proposal.evidence_gates, 0..) |gate, index| {
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
    try out.appendSlice(gpa, "],\"activation_rule\":");
    try runtime.appendJsonStringPublic(gpa, out, activation_rule);
    try out.appendSlice(gpa, "}\n");
}

test "review packet remains pending and fail closed" {
    try std.testing.expectEqual(PacketStatus.ready_for_review, packet.status);
    try std.testing.expect(!packet.approved);
    try std.testing.expect(!packet.registered);
    try std.testing.expect(!packet.runtime_available);
    try std.testing.expect(!packet.activation_allowed);
    try std.testing.expect(packet.fail_closed);
    try std.testing.expectEqualStrings(runtime.reason_code, packet.reason_code);
    try std.testing.expectEqual(@as(?[]const u8, null), validateState());
}

test "pre-approving packet state fails validation" {
    var candidate = packet;
    candidate.approved = true;
    try std.testing.expectEqualStrings(
        "packet unexpectedly claims an activation outcome",
        validatePacket(candidate, &review_items, approval).?,
    );

    var approved_items = review_items;
    for (&approved_items) |*item| item.status = .approved;
    try std.testing.expectEqualStrings(
        "review item is pre-approved",
        validatePacket(packet, &approved_items, approval).?,
    );
}

test "review packet JSON is deterministic, bounded, and policy complete" {
    const gpa = std.testing.allocator;
    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(gpa);
    try writePacket(gpa, &first);
    try writePacket(gpa, &second);
    try std.testing.expectEqualSlices(u8, first.items, second.items);
    try std.testing.expect(first.items.len < 16 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"packet_status\":\"ready_for_review\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"approved\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"runtime_available\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"activation_allowed\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"policy.pure_sdl3_boundary\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"pgtk_runtime_fallback_allowed\":false") != null);
}
