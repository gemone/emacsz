//! Source-authoritative provenance for the candidate R8 adapter linkage.
//!
//! This module names the adapter-owned shared-library artifact and pins the
//! exact PureRuntimeHostV1 ABI/table inventory after R7 approval.  The selected
//! adapter remains unlinked; it does not register a terminal or enable runtime.

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
    if (linkage_schema_version != 1) return "unsupported linkage schema";
    if (host_contract.validateState()) |problem| return problem;
    if (host_contract.decision.status != .approved) return "linkage requires approved R7";
    if (host_adapter.current.status != .selected) return "candidate adapter is not selected";
    if (!host_adapter.current.selected) return "candidate selection flag is absent";
    if (host_adapter.current.linked_into_emacs) return "candidate adapter is linked";
    if (inherited_source_paths_modified.len != 0) return "candidate linkage claims inherited-source edits";
    if (runtime_host.abi_version != 1) return "unsupported runtime host ABI";
    if (table_size == 0 or group_count != 5 or operation_count != 27)
        return "runtime host table inventory changed";
    if (!std.mem.eql(u8, status, "prepared_not_linked"))
        return "candidate linkage is not prepared-not-linked";
    if (registered or runtime_available or linked_into_emacs)
        return "candidate linkage claims activation";
    return null;
}

pub fn writeManifest(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (validateState() != null) return Error.InvalidAdapterLinkage;
    const hash = abiTableHash();
    try out.appendSlice(gpa, "{\"manifest_version\":1,");
    try out.print(gpa, "\"linkage_schema_version\":{d},", .{linkage_schema_version});
    try out.appendSlice(gpa, "\"kind\":\"proto-ui-r8-adapter-linkage\",");
    try out.appendSlice(gpa, "\"authoritative_source\":");
    try runtime.appendJsonStringPublic(gpa, out, authoritative_source);
    try out.appendSlice(gpa, ",\"candidate_id\":");
    try runtime.appendJsonStringPublic(gpa, out, host_adapter.candidate_input.candidate.id);
    try out.appendSlice(gpa, ",\"status\":");
    try runtime.appendJsonStringPublic(gpa, out, status);
    try out.print(gpa, ",\"selected\":{},\"registered\":{},\"runtime_available\":{},\"reason_code\":", .{
        selected,
        registered,
        runtime_available,
    });
    try runtime.appendJsonStringPublic(gpa, out, prepared_not_linked_reason_code);
    try out.appendSlice(gpa, ",\"artifact\":{\"build_artifact_id\":");
    try runtime.appendJsonStringPublic(gpa, out, artifact_id);
    try out.print(gpa, ",\"kind\":\"shared_library\",\"linked_into_emacs\":{}}}", .{linked_into_emacs});
    try out.appendSlice(gpa, ",\"build_injection\":{\"point\":");
    try runtime.appendJsonStringPublic(gpa, out, injection_point);
    try out.appendSlice(gpa, ",\"default\":false,\"state\":\"planned\"}");
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
