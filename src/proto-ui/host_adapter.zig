//! Versioned host-adapter selection policy for the pure SDL3 runtime.
//!
//! The source currently records the pure-SDL3 candidate as *unselected*: R7 is
//! pending and no Emacs host adapter is linked or activated.  This module does
//! not create a terminal or modify inherited GNU Emacs C/Lisp source.

const std = @import("std");
const host_contract = @import("host_contract.zig");
const runtime = @import("runtime.zig");
const runtime_host = @import("runtime_host.zig");

pub const manifest_version: u32 = 1;
pub const selection_schema_version: u32 = 1;
pub const authoritative_source = "src/proto-ui/host_adapter.zig";
pub const pending_reason_code = runtime.reason_code;
pub const rejected_reason_code = "r7_registration_rejected";
pub const metadata_reason_code = "r7_review_metadata_incomplete";
pub const invalid_reason_code = "host_adapter_contract_invalid";

pub const SelectionStatus = enum {
    unselected,
    selected,
    rejected,
};

pub const Candidate = struct {
    id: []const u8 = "pure-sdl3-runtime-host-v1",
    abi_version: u32 = runtime_host.abi_version,
    terminal_type: []const u8 = "output_proto",
    ui_backend: []const u8 = "sdl3",
    inherited_source_paths_modified: []const []const u8 = &.{},
    pgtk_runtime_fallback_allowed: bool = false,
    tty_runtime_fallback_allowed: bool = false,
    frontend_may_evaluate_elisp: bool = false,
    frontend_may_own_emacs_layout: bool = false,
};

pub const Input = struct {
    r7_status: host_contract.DecisionStatus,
    r7_metadata_complete: bool,
    candidate: Candidate = .{},
    selected: bool = false,
    registered: bool = false,
    runtime_available: bool = false,
};

pub const Decision = struct {
    status: SelectionStatus,
    selected: bool = false,
    activation_allowed: bool = false,
    registered: bool = false,
    runtime_available: bool = false,
    reason_code: []const u8,
};

pub const candidate_input = Input{
    .r7_status = host_contract.decision.status,
    .r7_metadata_complete = host_contract.metadataComplete(),
};

pub const current = evaluate(candidate_input);

pub fn validateCandidate(candidate: Candidate) ?[]const u8 {
    if (candidate.id.len == 0) return "candidate id is empty";
    if (candidate.abi_version != runtime_host.abi_version)
        return "candidate ABI version mismatch";
    if (!std.mem.eql(u8, candidate.terminal_type, "output_proto"))
        return "candidate terminal type mismatch";
    if (!std.mem.eql(u8, candidate.ui_backend, "sdl3"))
        return "candidate UI backend mismatch";
    if (candidate.inherited_source_paths_modified.len != 0)
        return "candidate claims inherited-source modification";
    if (candidate.pgtk_runtime_fallback_allowed)
        return "candidate permits PGTK runtime fallback";
    if (candidate.tty_runtime_fallback_allowed)
        return "candidate permits TTY runtime fallback";
    if (candidate.frontend_may_evaluate_elisp)
        return "candidate permits frontend Elisp evaluation";
    if (candidate.frontend_may_own_emacs_layout)
        return "candidate permits frontend layout ownership";
    for (runtime.callback_groups) |group| {
        if (group.operations().len == 0) return "candidate callback group is empty";
    }
    return null;
}

pub fn evaluate(input: Input) Decision {
    if (validateCandidate(input.candidate) != null or
        input.selected or input.registered or input.runtime_available)
        return .{
            .status = .rejected,
            .reason_code = invalid_reason_code,
        };
    return switch (input.r7_status) {
        .pending => .{
            .status = .unselected,
            .reason_code = pending_reason_code,
        },
        .rejected => .{
            .status = .rejected,
            .reason_code = rejected_reason_code,
        },
        .approved => if (!input.r7_metadata_complete) .{
            .status = .rejected,
            .reason_code = metadata_reason_code,
        } else .{
            .status = .selected,
            .selected = true,
            .activation_allowed = true,
            .reason_code = "r7_approved",
        },
    };
}

pub fn validateState() ?[]const u8 {
    if (host_contract.validateState()) |problem| return problem;
    if (validateCandidate(candidate_input.candidate)) |problem| return problem;
    if (current.status != .unselected) return "current selection is not unselected";
    if (current.selected or current.activation_allowed or
        current.registered or current.runtime_available)
        return "pending R7 unexpectedly enables selection";
    if (!std.mem.eql(u8, current.reason_code, pending_reason_code))
        return "current selection reason changed";
    return null;
}

pub fn writeManifest(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (validateState() != null) return error.InvalidHostAdapterSelection;
    try out.appendSlice(gpa, "{\"manifest_version\":1,");
    try out.appendSlice(gpa, "\"kind\":\"proto-ui-host-adapter-selection\",");
    try out.appendSlice(gpa, "\"authoritative_source\":");
    try runtime.appendJsonStringPublic(gpa, out, authoritative_source);
    try out.appendSlice(gpa, ",\"selection_schema_version\":");
    try out.print(gpa, "{d}", .{selection_schema_version});
    try out.appendSlice(gpa, ",\"candidate\":{\"id\":");
    try runtime.appendJsonStringPublic(gpa, out, candidate_input.candidate.id);
    try out.appendSlice(gpa, ",\"abi_version\":");
    try out.print(gpa, "{d}", .{candidate_input.candidate.abi_version});
    try out.appendSlice(gpa, ",\"terminal_type\":");
    try runtime.appendJsonStringPublic(gpa, out, candidate_input.candidate.terminal_type);
    try out.appendSlice(gpa, ",\"ui_backend\":");
    try runtime.appendJsonStringPublic(gpa, out, candidate_input.candidate.ui_backend);
    try out.appendSlice(gpa, "},\"r7_decision_status\":");
    try runtime.appendJsonStringPublic(gpa, out, @tagName(host_contract.decision.status));
    try out.appendSlice(gpa, ",\"selection\":{\"status\":\"unselected\",\"selected\":false");
    try out.appendSlice(gpa, ",\"activation_allowed\":false,\"registered\":false");
    try out.appendSlice(gpa, ",\"runtime_available\":false,\"reason_code\":");
    try runtime.appendJsonStringPublic(gpa, out, current.reason_code);
    try out.appendSlice(gpa, "},\"required_callback_groups\":[");
    for (runtime.callback_groups, 0..) |group, index| {
        if (index != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"name\":\"");
        try out.appendSlice(gpa, @tagName(group));
        try out.appendSlice(gpa, "\",\"operations\":");
        try runtime.appendJsonStringArrayPublic(gpa, out, group.operations());
        try out.appendSlice(gpa, ",\"ownership\":");
        try runtime.appendJsonStringPublic(gpa, out, group.ownership());
        try out.append(gpa, '}');
    }
    try out.appendSlice(gpa, "],\"policy\":{\"inherited_source_paths_modified\":");
    try runtime.appendJsonStringArrayPublic(gpa, out, candidate_input.candidate.inherited_source_paths_modified);
    try out.appendSlice(gpa, ",\"pgtk_runtime_fallback_allowed\":false");
    try out.appendSlice(gpa, ",\"tty_runtime_fallback_allowed\":false");
    try out.appendSlice(gpa, ",\"frontend_may_evaluate_elisp\":false");
    try out.appendSlice(gpa, ",\"frontend_may_own_emacs_layout\":false}}\n");
}

test "current pure SDL3 candidate remains unselected before R7 approval" {
    try std.testing.expectEqual(host_contract.DecisionStatus.pending, host_contract.decision.status);
    try std.testing.expectEqual(SelectionStatus.unselected, current.status);
    try std.testing.expect(!current.selected);
    try std.testing.expect(!current.activation_allowed);
    try std.testing.expect(!current.registered);
    try std.testing.expect(!current.runtime_available);
    try std.testing.expectEqual(@as(?[]const u8, null), validateState());
}

test "candidate selection policy requires approval and complete metadata" {
    const pending = evaluate(.{ .r7_status = .pending, .r7_metadata_complete = false });
    try std.testing.expectEqual(SelectionStatus.unselected, pending.status);
    try std.testing.expectEqualStrings(pending_reason_code, pending.reason_code);

    const incomplete = evaluate(.{ .r7_status = .approved, .r7_metadata_complete = false });
    try std.testing.expectEqual(SelectionStatus.rejected, incomplete.status);
    try std.testing.expectEqualStrings(metadata_reason_code, incomplete.reason_code);

    const approved = evaluate(.{ .r7_status = .approved, .r7_metadata_complete = true });
    try std.testing.expectEqual(SelectionStatus.selected, approved.status);
    try std.testing.expect(approved.selected);
    try std.testing.expect(approved.activation_allowed);
    try std.testing.expect(!approved.registered);
    try std.testing.expect(!approved.runtime_available);

    const fallback = evaluate(.{
        .r7_status = .approved,
        .r7_metadata_complete = true,
        .candidate = .{ .pgtk_runtime_fallback_allowed = true },
    });
    try std.testing.expectEqual(SelectionStatus.rejected, fallback.status);
    try std.testing.expectEqualStrings(invalid_reason_code, fallback.reason_code);
}

test "host adapter selection manifest is deterministic and bounded" {
    const gpa = std.testing.allocator;
    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(gpa);
    try writeManifest(gpa, &first);
    try writeManifest(gpa, &second);
    try std.testing.expectEqualSlices(u8, first.items, second.items);
    try std.testing.expect(first.items.len < 16 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"status\":\"unselected\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"runtime_available\":false") != null);
}
