//! Source-authoritative provenance for the candidate R8 adapter linkage.
//!
//! The default state names the adapter-owned host-audit artifact and pins the
//! exact PureRuntimeHostV1 ABI/table inventory.  The opt-in native Linux glibc
//! state may be linked-not-registered: the candidate is present in the temacs
//! link graph, but nothing calls it, registers a terminal, or enables runtime.

const std = @import("std");
const host_adapter = @import("host_adapter.zig");
const host_contract = @import("host_contract.zig");
const runtime = @import("runtime.zig");
const runtime_host = @import("runtime_host.zig");

pub const manifest_version: u32 = 1;
pub const linkage_schema_version: u32 = 1;
pub const authoritative_source = "src/proto-ui/r8_adapter_linkage.zig";
pub const artifact_id = "proto-ui-runtime-host-adapter";
pub const injection_point = "build.zig:proto-ui-runtime-host-adapter";
pub const target_artifact_id = "proto-ui-runtime-host-adapter-target";
pub const target_injection_point = "build.zig:temacs";
pub const linked_symbol = "proto_ui_runtime_host_adapter_abi_version";
pub const linked_target = "native-linux-gnu";
pub const prepared_not_linked_reason_code = runtime.reason_code;
pub const status = "prepared_not_linked";
pub const inherited_source_paths_modified = host_adapter.candidate_input.candidate.inherited_source_paths_modified;
pub const selected = true;
pub const registered = false;
pub const runtime_available = false;
pub const linked_into_emacs = false;

pub const Error = error{
    InvalidAdapterLinkage,
};

pub const operation_count = runtime_host.operation_names.len;
pub const group_count = runtime.callback_groups.len;
pub const table_size = @sizeOf(runtime_host.PureRuntimeHostV1);

/// Canonical hash of the versioned ABI shape and callback operation inventory.
/// This deliberately does not hash generated machine code or a host binary.
pub fn abiTableDigest() [std.crypto.hash.sha2.Sha256.digest_length]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("proto-ui-r8-adapter-linkage/v1");
    var u32_bytes: [4]u8 = undefined;
    var u64_bytes: [8]u8 = undefined;
    std.mem.writeInt(u32, &u32_bytes, runtime_host.abi_version, .little);
    hasher.update(&u32_bytes);
    std.mem.writeInt(u64, &u64_bytes, table_size, .little);
    hasher.update(&u64_bytes);
    std.mem.writeInt(u32, &u32_bytes, group_count, .little);
    hasher.update(&u32_bytes);
    std.mem.writeInt(u32, &u32_bytes, operation_count, .little);
    hasher.update(&u32_bytes);
    inline for (runtime.callback_groups) |group| {
        const name = @tagName(group);
        std.mem.writeInt(u32, &u32_bytes, @intCast(name.len), .little);
        hasher.update(name);
        hasher.update(&u32_bytes);
    }
    for (runtime_host.operation_names) |operation| {
        std.mem.writeInt(u32, &u32_bytes, @intCast(operation.len), .little);
        hasher.update(operation);
        hasher.update(&u32_bytes);
    }
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

pub fn abiTableHash() [64]u8 {
    return std.fmt.bytesToHex(abiTableDigest(), .lower);
}

pub fn validateState() ?[]const u8 {
    return validateLinkedState(false);
}

pub const LinkedState = struct {
    status: []const u8,
    reason_code: []const u8,
    artifact_kind: []const u8,
    injection_state: []const u8,
    selected: bool,
    registered: bool,
    runtime_available: bool,
    linked_into_emacs: bool,
};

pub fn linkedState(runtime_linking: bool) LinkedState {
    return if (!runtime_linking) .{
        .status = status,
        .reason_code = prepared_not_linked_reason_code,
        .artifact_kind = "shared_library",
        .injection_state = "planned",
        .selected = selected,
        .registered = registered,
        .runtime_available = runtime_available,
        .linked_into_emacs = linked_into_emacs,
    } else .{
        .status = "linked_not_registered",
        .reason_code = "r8_registration_missing",
        .artifact_kind = "static_library",
        .injection_state = "linked_not_registered",
        .selected = true,
        .registered = false,
        .runtime_available = false,
        .linked_into_emacs = true,
    };
}

pub fn validateLinkedState(runtime_linking: bool) ?[]const u8 {
    if (linkage_schema_version != 1) return "unsupported linkage schema";
    if (host_contract.validateState()) |problem| return problem;
    if (host_contract.decision.status != .approved) return "linkage requires approved R7";
    if (host_adapter.current.status != .selected) return "candidate adapter is not selected";
    if (!host_adapter.current.selected) return "candidate selection flag is absent";
    if (inherited_source_paths_modified.len != 0) return "candidate linkage claims inherited-source edits";
    if (runtime_host.abi_version != 1) return "unsupported runtime host ABI";
    if (table_size == 0 or group_count != 5 or operation_count != 27)
        return "runtime host table inventory changed";

    const state = linkedState(runtime_linking);
    if (!std.mem.eql(u8, state.status, if (runtime_linking) "linked_not_registered" else "prepared_not_linked"))
        return "candidate linkage state is inconsistent";
    if (!state.selected or state.registered or state.runtime_available)
        return "candidate linkage claims registration or runtime";
    if (state.linked_into_emacs != runtime_linking)
        return "candidate linkage state disagrees with the requested link graph";
    if (!std.mem.eql(u8, state.artifact_kind, if (runtime_linking) "static_library" else "shared_library"))
        return "candidate artifact kind disagrees with linkage state";
    if (!std.mem.eql(u8, state.injection_state, if (runtime_linking) "linked_not_registered" else "planned"))
        return "candidate injection state disagrees with linkage state";
    if (!std.mem.eql(u8, state.reason_code, if (runtime_linking) "r8_registration_missing" else runtime.reason_code))
        return "candidate linkage reason is inconsistent";
    return null;
}

pub fn writeManifest(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    return writeLinkedManifest(gpa, out, false);
}

pub fn writeLinkedManifest(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    runtime_linking: bool,
) !void {
    const state = linkedState(runtime_linking);
    if (validateLinkedState(runtime_linking) != null) return Error.InvalidAdapterLinkage;
    const hash = abiTableHash();
    try out.appendSlice(gpa, "{\"manifest_version\":1,");
    try out.print(gpa, "\"linkage_schema_version\":{d},", .{linkage_schema_version});
    try out.appendSlice(gpa, "\"kind\":\"proto-ui-r8-adapter-linkage\",");
    try out.appendSlice(gpa, "\"authoritative_source\":");
    try runtime.appendJsonStringPublic(gpa, out, authoritative_source);
    try out.appendSlice(gpa, ",\"candidate_id\":");
    try runtime.appendJsonStringPublic(gpa, out, host_adapter.candidate_input.candidate.id);
    try out.appendSlice(gpa, ",\"status\":");
    try runtime.appendJsonStringPublic(gpa, out, state.status);
    try out.print(gpa, ",\"runtime_linking\":{},\"selected\":{},\"registered\":{},\"runtime_available\":{},\"reason_code\":", .{
        runtime_linking,
        state.selected,
        state.registered,
        state.runtime_available,
    });
    try runtime.appendJsonStringPublic(gpa, out, state.reason_code);
    const build_artifact_id = if (runtime_linking) target_artifact_id else artifact_id;
    const build_injection_point = if (runtime_linking) target_injection_point else injection_point;
    try out.appendSlice(gpa, ",\"artifact\":{\"build_artifact_id\":");
    try runtime.appendJsonStringPublic(gpa, out, build_artifact_id);
    try out.appendSlice(gpa, ",\"kind\":");
    try runtime.appendJsonStringPublic(gpa, out, state.artifact_kind);
    try out.print(gpa, ",\"linked_into_emacs\":{}}}", .{state.linked_into_emacs});
    try out.appendSlice(gpa, ",\"linked_target\":");
    try runtime.appendJsonStringPublic(gpa, out, if (runtime_linking) linked_target else "");
    try out.appendSlice(gpa, ",\"build_injection\":{\"point\":");
    try runtime.appendJsonStringPublic(gpa, out, build_injection_point);
    try out.print(gpa, ",\"default\":false,\"state\":", .{});
    try runtime.appendJsonStringPublic(gpa, out, state.injection_state);
    try out.appendSlice(gpa, "}");
    try out.appendSlice(gpa, ",\"abi\":{\"version\":");
    try out.print(gpa, "{d}", .{runtime_host.abi_version});
    try out.appendSlice(gpa, ",\"table_size\":");
    try out.print(gpa, "{d}", .{table_size});
    try out.appendSlice(gpa, ",\"group_count\":");
    try out.print(gpa, "{d}", .{group_count});
    try out.appendSlice(gpa, ",\"operation_count\":");
    try out.print(gpa, "{d}", .{operation_count});
    try out.appendSlice(gpa, ",\"inventory_sha256\":");
    try runtime.appendJsonStringPublic(gpa, out, &hash);
    try out.appendSlice(gpa, "},\"inherited_source_paths_modified\":");
    try runtime.appendJsonStringArrayPublic(gpa, out, inherited_source_paths_modified);
    try out.appendSlice(gpa, "}");
    try out.append(gpa, '\n');
}

test "selected adapter linkage remains prepared and fail closed" {
    try std.testing.expectEqual(host_contract.DecisionStatus.approved, host_contract.decision.status);
    try std.testing.expectEqual(host_adapter.SelectionStatus.selected, host_adapter.current.status);
    try std.testing.expectEqual(@as(?[]const u8, null), validateState());
    try std.testing.expectEqualStrings("prepared_not_linked", status);
    try std.testing.expectEqual(@as(usize, 27), operation_count);
    try std.testing.expectEqual(@as(usize, 5), group_count);
    try std.testing.expectEqual(@as(usize, 64), table_size);
}

test "opt-in adapter linkage is linked but still not registered" {
    try std.testing.expectEqual(@as(?[]const u8, null), validateLinkedState(true));
    const state = linkedState(true);
    try std.testing.expectEqualStrings("linked_not_registered", state.status);
    try std.testing.expectEqualStrings("r8_registration_missing", state.reason_code);
    try std.testing.expect(state.linked_into_emacs);
    try std.testing.expect(!state.registered);
    try std.testing.expect(!state.runtime_available);
    const gpa = std.testing.allocator;
    var manifest: std.ArrayList(u8) = .empty;
    defer manifest.deinit(gpa);
    try writeLinkedManifest(gpa, &manifest, true);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, manifest.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings(target_artifact_id, parsed.value.object.get("artifact").?.object.get("build_artifact_id").?.string);
    try std.testing.expectEqualStrings(target_injection_point, parsed.value.object.get("build_injection").?.object.get("point").?.string);
}

test "adapter linkage ABI hash is stable and bounded" {
    const first = abiTableHash();
    const second = abiTableHash();
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(@as(usize, 64), first.len);
    for (first) |char| {
        try std.testing.expect((char >= '0' and char <= '9') or (char >= 'a' and char <= 'f'));
    }
}

test "adapter linkage manifest is deterministic and fail closed" {
    const gpa = std.testing.allocator;
    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(gpa);
    try writeManifest(gpa, &first);
    try writeManifest(gpa, &second);
    try std.testing.expectEqualSlices(u8, first.items, second.items);
    try std.testing.expect(first.items.len < 16 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"status\":\"prepared_not_linked\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"linked_into_emacs\":false") != null);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, first.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("prepared_not_linked", parsed.value.object.get("status").?.string);
}
