//! Source-authoritative Proto-UI runtime contract and fail-closed state.
//!
//! R2 intentionally has no host registration seam and no terminal
//! registration implementation.  The manifest states that fact so build
//! tooling can audit it without inventing inherited-core integration.

const std = @import("std");
const terminal = @import("terminal.zig");

pub const manifest_version: u32 = 1;
pub const authoritative_source = "src/proto-ui/runtime.zig";
pub const reason_code = "host_registration_contract_missing";
pub const fail_closed_reason =
    "No reviewed Emacs host adapter can supply the versioned terminal, frame, " ++
    "redisplay, input, and lifecycle callback groups required to register " ++
    "an output_proto terminal.";

pub const Error = error{
    InvalidRuntimeManifest,
    RuntimeUnexpectedlyAvailable,
};

pub const CallbackGroup = enum {
    terminal,
    frame,
    redisplay,
    input,
    lifecycle,

    pub fn operations(self: CallbackGroup) []const []const u8 {
        return switch (self) {
            .terminal => &.{ "create_terminal", "activate_terminal", "delete_terminal" },
            .frame => &.{ "register_frame", "unregister_frame", "read_frame_state", "read_geometry" },
            .redisplay => &.{
                "begin_capture",
                "observe_window",
                "observe_row",
                "observe_run",
                "observe_cursor",
                "observe_damage",
                "commit_capture",
                "cancel_capture",
            },
            .input => &.{ "deliver_event", "deliver_result", "deliver_completion_status" },
            .lifecycle => &.{ "heartbeat", "flush", "diagnostic", "cancel_all_pending_work" },
        };
    }

    pub fn ownership(self: CallbackGroup) []const u8 {
        return switch (self) {
            .terminal => "Emacs owns terminal truth; adapter owns protocol identity",
            .frame => "Emacs owns frame truth; adapter maps identity/generation",
            .redisplay => "Emacs owns display truth; adapter owns EUP translation",
            .input => "Emacs owns command interpretation",
            .lifecycle => "Adapter owns protocol/session state",
        };
    }
};

pub const callback_groups = [_]CallbackGroup{ .terminal, .frame, .redisplay, .input, .lifecycle };

pub const RuntimeState = struct {
    runtime_available: bool = false,
    fail_closed: bool = true,
    reason_code: []const u8 = reason_code,
    reason_message: []const u8 = fail_closed_reason,
};

pub const runtime_state = RuntimeState{};

pub const Groundwork = struct {
    name: []const u8,
    status: []const u8,
    evidence: []const u8,
    owner: []const u8,
    boundary: []const u8,
};

pub const implemented_groundwork = [_]Groundwork{.{
    .name = "terminal.lifecycle_state_machine",
    .status = "implemented",
    .evidence = "proto-ui-unit terminal lifecycle tests",
    .owner = "proto-ui-adapter",
    .boundary = "identity/generation/cleanup state only; no Emacs terminal registration",
}};

pub const OwnershipSummary = struct {
    emacs: []const []const u8,
    adapter: []const []const u8,
    frontend: []const []const u8,
};

pub const ownership_summary = OwnershipSummary{
    .emacs = &.{ "terminal truth", "frame truth", "display truth", "command interpretation" },
    .adapter = &.{ "protocol identity", "EUP translation", "protocol/session state" },
    .frontend = &.{ "scene ownership", "input capture", "renderer", "presentation" },
};

pub const EvidenceGate = struct {
    required: bool = true,
    command: []const u8 = "zig build -Dproto-ui=true -Dproto-ui-runtime=true proto-ui-boundary",
    expected_result: []const u8 = "nonzero exit",
    reason_code: []const u8 = reason_code,
};

pub const evidence_gate = EvidenceGate{};

pub fn validateState() ?[]const u8 {
    if (runtime_state.runtime_available) return "runtime unexpectedly available";
    if (!runtime_state.fail_closed) return "runtime is not fail-closed";
    if (!std.mem.eql(u8, runtime_state.reason_code, reason_code)) return "reason code changed";
    if (runtime_state.reason_message.len == 0) return "missing reason message";
    for (callback_groups) |group| {
        if (group.operations().len == 0) return "callback group has no operations";
        for (group.operations()) |operation| {
            if (operation.len == 0) return "empty callback operation";
        }
    }
    for (implemented_groundwork) |item| {
        if (!std.mem.eql(u8, item.name, "terminal.lifecycle_state_machine")) return "unexpected groundwork";
        if (!std.mem.eql(u8, item.owner, "proto-ui-adapter")) return "groundwork owner is not adapter";
    }
    return null;
}

fn appendJsonString(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.append(gpa, '"');
    for (value) |byte| {
        if (byte == '"' or byte == '\\' or byte < 0x20) return Error.InvalidRuntimeManifest;
        try out.append(gpa, byte);
    }
    try out.append(gpa, '"');
}

fn appendJsonStringArray(gpa: std.mem.Allocator, out: *std.ArrayList(u8), values: []const []const u8) !void {
    try out.append(gpa, '[');
    for (values, 0..) |value, index| {
        if (index != 0) try out.append(gpa, ',');
        try appendJsonString(gpa, out, value);
    }
    try out.append(gpa, ']');
}

/// Emits canonical compact JSON: deterministic across hosts and runs.
pub fn writeManifest(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (validateState() != null) return Error.InvalidRuntimeManifest;
    try out.appendSlice(gpa, "{\"manifest_version\":1,");
    try out.appendSlice(gpa, "\"kind\":\"proto-ui-runtime-manifest\",");
    try out.appendSlice(gpa, "\"authoritative_source\":\"");
    try out.appendSlice(gpa, authoritative_source);
    try out.appendSlice(gpa, "\",\"runtime_available\":false,\"fail_closed\":true,");
    try out.appendSlice(gpa, "\"reason\":{\"code\":\"");
    try out.appendSlice(gpa, reason_code);
    try out.appendSlice(gpa, "\",\"message\":");
    try appendJsonString(gpa, out, fail_closed_reason);
    try out.appendSlice(gpa, "},\"required_callback_groups\":[");
    for (callback_groups, 0..) |group, group_index| {
        if (group_index != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"name\":\"");
        try out.appendSlice(gpa, @tagName(group));
        try out.appendSlice(gpa, "\",\"required\":true,\"operations\":");
        try appendJsonStringArray(gpa, out, group.operations());
        try out.appendSlice(gpa, ",\"ownership\":");
        try appendJsonString(gpa, out, group.ownership());
        try out.append(gpa, '}');
    }
    try out.appendSlice(gpa, "],\"implemented_groundwork\":[");
    for (implemented_groundwork, 0..) |item, index| {
        if (index != 0) try out.append(gpa, ',');
        try out.appendSlice(gpa, "{\"name\":");
        try appendJsonString(gpa, out, item.name);
        try out.appendSlice(gpa, ",\"status\":");
        try appendJsonString(gpa, out, item.status);
        try out.appendSlice(gpa, ",\"evidence\":");
        try appendJsonString(gpa, out, item.evidence);
        try out.appendSlice(gpa, ",\"owner\":");
        try appendJsonString(gpa, out, item.owner);
        try out.appendSlice(gpa, ",\"boundary\":");
        try appendJsonString(gpa, out, item.boundary);
        try out.append(gpa, '}');
    }
    try out.appendSlice(gpa, "],\"ownership_summary\":{\"emacs\":");
    try appendJsonStringArray(gpa, out, ownership_summary.emacs);
    try out.appendSlice(gpa, ",\"adapter\":");
    try appendJsonStringArray(gpa, out, ownership_summary.adapter);
    try out.appendSlice(gpa, ",\"frontend\":");
    try appendJsonStringArray(gpa, out, ownership_summary.frontend);
    try out.appendSlice(gpa, "},\"evidence_gate\":{\"required\":true,\"command\":");
    try appendJsonString(gpa, out, evidence_gate.command);
    try out.appendSlice(gpa, ",\"expected_result\":");
    try appendJsonString(gpa, out, evidence_gate.expected_result);
    try out.appendSlice(gpa, ",\"reason_code\":");
    try appendJsonString(gpa, out, evidence_gate.reason_code);
    try out.appendSlice(gpa, "}}\n");
}

test "runtime state is unavailable and fail-closed" {
    try std.testing.expectEqual(RuntimeState{}, runtime_state);
    try std.testing.expectEqual(@as(?[]const u8, null), validateState());
    try std.testing.expectEqualStrings(reason_code, runtime_state.reason_code);
}

test "required callback contract is complete and stable" {
    try std.testing.expectEqual(@as(usize, 5), callback_groups.len);
    try std.testing.expectEqual(CallbackGroup.terminal, callback_groups[0]);
    try std.testing.expectEqual(CallbackGroup.lifecycle, callback_groups[4]);
    try std.testing.expectEqual(@as(usize, 3), CallbackGroup.terminal.operations().len);
    try std.testing.expectEqual(@as(usize, 4), CallbackGroup.frame.operations().len);
    try std.testing.expectEqual(@as(usize, 8), CallbackGroup.redisplay.operations().len);
    try std.testing.expectEqual(@as(usize, 3), CallbackGroup.input.operations().len);
    try std.testing.expectEqual(@as(usize, 4), CallbackGroup.lifecycle.operations().len);
    try std.testing.expectEqualStrings("create_terminal", CallbackGroup.terminal.operations()[0]);
    try std.testing.expectEqualStrings("cancel_capture", CallbackGroup.redisplay.operations()[7]);
    try std.testing.expect(terminal.max_terminals > 0);
}

test "runtime manifest is valid, deterministic, and never enables runtime" {
    const gpa = std.testing.allocator;
    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(gpa);
    try writeManifest(gpa, &first);
    try writeManifest(gpa, &second);
    try std.testing.expectEqualSlices(u8, first.items, second.items);
    try std.testing.expect(first.items.len < 8 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"runtime_available\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"fail_closed\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"host_registration_contract_missing\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"terminal.lifecycle_state_machine\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "runtime_available\":true") == null);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, first.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(std.json.Value{ .bool = false }, parsed.value.object.get("runtime_available").?);
    try std.testing.expectEqual(@as(u64, 5), parsed.value.object.get("required_callback_groups").?.array.items.len);
}

test "reason message and evidence gate remain stable" {
    try std.testing.expect(std.mem.indexOf(u8, fail_closed_reason, "No reviewed Emacs host adapter") != null);
    try std.testing.expect(std.mem.indexOf(u8, evidence_gate.command, "-Dproto-ui-runtime=true") != null);
    try std.testing.expectEqualStrings("nonzero exit", evidence_gate.expected_result);
}
