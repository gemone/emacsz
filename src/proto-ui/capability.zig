//! Adapter-owned capability negotiation policy and implementation manifest.
//!
//! EUP defines arbitrary name/value capabilities.  This module binds the local
//! EPXL profile to a small, versioned subset, intersects the backend/frontend
//! sets, and records implementation status for generated tooling.  Unknown
//! optional names are ignored, as required by EUP; known names with malformed
//! values fail the session deterministically.

const std = @import("std");
const protocol = @import("protocol.zig");

pub const manifest_version: u32 = 1;
pub const session_id: u64 = 0x1001;
pub const hash_len: usize = 32;

pub const Error = protocol.Error || error{
    MissingRequiredCapability,
    InvalidCapabilityValue,
    InvalidNegotiationMessage,
    CapabilityHashMismatch,
};

pub const Status = enum {
    implemented,
    degraded,
    pending,

    pub fn name(self: Status) []const u8 {
        return switch (self) {
            .implemented => "implemented",
            .degraded => "degraded",
            .pending => "pending",
        };
    }
};

pub const Feature = enum {
    protocol_v1,
    capability_negotiation,
    transport_epxl_local,
    session_resync,
    frame_facts_profile,
    text_ascii_bounded,
    input_text_ascii,
    input_key_bounded,
    input_pointer_bounded,
    input_wheel_line,
    clipboard_ascii_bounded,
    damage_retained_clip,
    renderer_sdl3,
    frame_output_proto,
    frame_lifecycle,
    resource_generation_contract,
    redisplay_glyph_rows,
    resource_v1,

    pub fn name(self: Feature) []const u8 {
        return switch (self) {
            .protocol_v1 => "protocol.v1",
            .capability_negotiation => "capability.negotiation",
            .transport_epxl_local => "transport.epxl_local",
            .session_resync => "session.resync",
            .frame_facts_profile => "frame.facts_profile",
            .text_ascii_bounded => "text.ascii_bounded",
            .input_text_ascii => "input.text_ascii",
            .input_key_bounded => "input.key_bounded",
            .input_pointer_bounded => "input.pointer_bounded",
            .input_wheel_line => "input.wheel_line",
            .clipboard_ascii_bounded => "clipboard.ascii_bounded",
            .damage_retained_clip => "damage.retained_clip",
            .renderer_sdl3 => "renderer.sdl3",
            .frame_output_proto => "frame.output_proto",
            .frame_lifecycle => "frame.lifecycle",
            .resource_generation_contract => "resource.generation_contract",
            .redisplay_glyph_rows => "redisplay.glyph_rows",
            .resource_v1 => "resource.v1",
        };
    }

    pub fn required(self: Feature) bool {
        return switch (self) {
            .protocol_v1, .transport_epxl_local, .session_resync, .frame_facts_profile, .text_ascii_bounded, .renderer_sdl3 => true,
            else => false,
        };
    }

    pub fn negotiable(self: Feature) bool {
        return switch (self) {
            .frame_output_proto, .frame_lifecycle, .resource_generation_contract, .redisplay_glyph_rows, .resource_v1 => false,
            else => true,
        };
    }
};

pub const FeatureDescriptor = struct {
    feature: Feature,
    status: Status,
    evidence: []const u8,
};

pub const feature_descriptors = [_]FeatureDescriptor{
    .{ .feature = .protocol_v1, .status = .implemented, .evidence = "proto-ui-conformance" },
    .{ .feature = .capability_negotiation, .status = .implemented, .evidence = "proto-ui-unit and sdl3-epxl-facts-smoke" },
    .{ .feature = .transport_epxl_local, .status = .implemented, .evidence = "sdl3-live-smoke" },
    .{ .feature = .session_resync, .status = .implemented, .evidence = "sdl3-epxl-resync-smoke" },
    .{ .feature = .frame_facts_profile, .status = .degraded, .evidence = "sdl3-epxl-facts-smoke" },
    .{ .feature = .text_ascii_bounded, .status = .degraded, .evidence = "sdl3-epxl-input-smoke" },
    .{ .feature = .input_text_ascii, .status = .degraded, .evidence = "sdl3-epxl-input-smoke" },
    .{ .feature = .input_key_bounded, .status = .degraded, .evidence = "sdl3-epxl-edit-smoke" },
    .{ .feature = .input_pointer_bounded, .status = .degraded, .evidence = "sdl3-pointer-smoke" },
    .{ .feature = .input_wheel_line, .status = .degraded, .evidence = "sdl3-wheel-smoke" },
    .{ .feature = .clipboard_ascii_bounded, .status = .degraded, .evidence = "sdl3-clipboard-smoke" },
    .{ .feature = .damage_retained_clip, .status = .degraded, .evidence = "sdl3-pointer-smoke and sdl3-epxl-interactive-smoke" },
    .{ .feature = .renderer_sdl3, .status = .degraded, .evidence = "sdl3-renderer-smoke" },
    .{ .feature = .frame_output_proto, .status = .pending, .evidence = "W12/W16 real proto frame acceptance pending" },
    .{ .feature = .frame_lifecycle, .status = .degraded, .evidence = "proto-ui-unit frame lifecycle contract" },
    .{ .feature = .resource_generation_contract, .status = .degraded, .evidence = "proto-ui-unit resource generation contract" },
    .{ .feature = .redisplay_glyph_rows, .status = .pending, .evidence = "W12 redisplay capture pending" },
    .{ .feature = .resource_v1, .status = .pending, .evidence = "W12 resource model pending" },
};

pub const feature_count = @typeInfo(Feature).@"enum".fields.len;

pub const Set = struct {
    bits: [feature_count]bool = [_]bool{false} ** feature_count,

    pub fn contains(self: Set, feature: Feature) bool {
        return self.bits[@intFromEnum(feature)];
    }

    pub fn insert(self: *Set, feature: Feature) void {
        self.bits[@intFromEnum(feature)] = true;
    }

    pub fn intersection(self: Set, other: Set) Set {
        var result: Set = .{};
        for (0..feature_count) |index| {
            result.bits[index] = self.bits[index] and other.bits[index];
        }
        return result;
    }
};

pub fn backendSupported() Set {
    var set: Set = .{};
    for (feature_descriptors) |item| {
        if (item.feature.negotiable() and item.status != .pending)
            set.insert(item.feature);
    }
    return set;
}

pub const frontendSupported = backendSupported;

fn descriptor(feature: Feature) FeatureDescriptor {
    for (feature_descriptors) |candidate| {
        if (candidate.feature == feature) return candidate;
    }
    unreachable;
}

fn setFromCapabilities(capabilities: []const protocol.Capability, allocator: std.mem.Allocator) !Set {
    // `decodeCapabilities` requires an allocator even though this profile does
    // not retain decoded names/values.
    _ = allocator;
    var result: Set = .{};
    for (capabilities) |capability| {
        for (feature_descriptors) |item| {
            const feature = item.feature;
            if (!feature.negotiable()) continue;
            if (!std.mem.eql(u8, capability.name, feature.name())) continue;
            if (!std.mem.eql(u8, capability.value, "1")) return Error.InvalidCapabilityValue;
            result.insert(feature);
        }
    }
    return result;
}

pub fn decodeSet(allocator: std.mem.Allocator, payload: []const u8) !Set {
    const decoded = try protocol.decodeCapabilities(allocator, payload);
    defer allocator.free(decoded);
    return setFromCapabilities(decoded, allocator);
}

pub const Negotiated = struct {
    effective: Set,
    hash: [hash_len]u8,
};

pub fn negotiate(backend: Set, frontend: Set) Error!Negotiated {
    const effective = backend.intersection(frontend);
    for (feature_descriptors) |item| {
        if (item.feature.required() and !effective.contains(item.feature))
            return Error.MissingRequiredCapability;
    }
    var negotiated: Negotiated = .{ .effective = effective, .hash = undefined };
    hashEffective(effective, &negotiated.hash);
    return negotiated;
}

pub fn hashEffective(set: Set, out: *[hash_len]u8) void {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (feature_descriptors) |item| {
        const feature = item.feature;
        if (!feature.negotiable()) continue;
        const present: u8 = if (set.contains(feature)) 1 else 0;
        hasher.update(feature.name());
        hasher.update(&.{0});
        hasher.update(&.{present});
    }
    hasher.final(out);
}

pub fn encodePayload(
    gpa: std.mem.Allocator,
    set: Set,
    out: *std.ArrayList(u8),
) !void {
    var capabilities: [feature_count]protocol.Capability = undefined;
    var count: usize = 0;
    for (feature_descriptors) |item| {
        const feature = item.feature;
        if (!feature.negotiable() or !set.contains(feature)) continue;
        capabilities[count] = .{ .name = feature.name(), .value = "1" };
        count += 1;
    }
    try protocol.encodeCapabilities(gpa, capabilities[0..count], out);
}

pub fn encodeMessage(
    gpa: std.mem.Allocator,
    set: Set,
    message_type: u16,
    sequence: u64,
    ack_sequence: u64,
    out: *std.ArrayList(u8),
) !void {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try encodePayload(gpa, set, &payload);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.idempotent,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = ack_sequence,
        .session_id = session_id,
        .timestamp_ns = sequence,
    }, payload.items, out);
}

pub fn encodeReadyAck(
    gpa: std.mem.Allocator,
    hash: *const [hash_len]u8,
    sequence: u64,
    ack_sequence: u64,
    out: *std.ArrayList(u8),
) !void {
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.idempotent,
        .message_type = protocol.Message.ready_ack,
        .sequence = sequence,
        .ack_sequence = ack_sequence,
        .session_id = session_id,
        .timestamp_ns = sequence,
    }, hash, out);
}

pub fn validateStatusManifest() ?[]const u8 {
    var seen = [_]bool{false} ** feature_count;
    for (feature_descriptors) |item| {
        const index = @intFromEnum(item.feature);
        if (seen[index]) return "duplicate feature status";
        seen[index] = true;
        if (item.evidence.len == 0) return "missing status evidence";
        if (item.status == .implemented and !item.feature.negotiable())
            return "implemented feature must be negotiable";
        if (item.status == .pending and item.feature.required())
            return "required feature cannot remain pending";
    }
    for (seen) |seen_item| {
        if (!seen_item) return "feature missing status";
    }
    return null;
}

pub fn writeStatusManifest(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (validateStatusManifest() != null) return Error.InvalidCapabilityValue;
    try out.appendSlice(gpa,
        \\{
        \\  "manifest_version": 1,
        \\  "authoritative_source": "src/proto-ui/capability.zig",
        \\  "scope": "proto-ui-epxl-profile",
        \\  "features": [
    );
    for (feature_descriptors, 0..) |item, index| {
        try out.appendSlice(gpa, "\n    {\"name\":\"");
        try out.appendSlice(gpa, item.feature.name());
        try out.appendSlice(gpa, "\",\"status\":\"");
        try out.appendSlice(gpa, item.status.name());
        try out.appendSlice(gpa, "\",\"required\":");
        try out.appendSlice(gpa, if (item.feature.required()) "true" else "false");
        try out.appendSlice(gpa, ",\"negotiable\":");
        try out.appendSlice(gpa, if (item.feature.negotiable()) "true" else "false");
        try out.appendSlice(gpa, ",\"evidence\":\"");
        // Descriptors use repository-local ASCII evidence names and never
        // contain quotes/backslashes, so this remains valid JSON.
        for (item.evidence) |byte| {
            if (byte == '"' or byte == '\\' or byte < 0x20) return Error.InvalidCapabilityValue;
            try out.append(gpa, byte);
        }
        try out.appendSlice(gpa, "\"}");
        if (index + 1 != feature_descriptors.len) try out.appendSlice(gpa, ",");
    }
    try out.appendSlice(gpa, "\n  ]\n}\n");
}

test "status manifest is complete and generated JSON is bounded" {
    try std.testing.expect(validateStatusManifest() == null);
    const gpa = std.testing.allocator;
    var json: std.ArrayList(u8) = .empty;
    defer json.deinit(gpa);
    try writeStatusManifest(gpa, &json);
    try std.testing.expect(json.items.len > 100);
    try std.testing.expect(json.items.len < 16 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"name\":\"resource.v1\"") != null);
}

test "capability payload round trip and unknown optional names are ignored" {
    const gpa = std.testing.allocator;
    var set = backendSupported();
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try encodePayload(gpa, set, &payload);
    const decoded = try decodeSet(gpa, payload.items);
    try std.testing.expectEqual(set.contains(.session_resync), decoded.contains(.session_resync));
    try std.testing.expect(decoded.contains(.protocol_v1));
    try std.testing.expect(!decoded.contains(.frame_output_proto));

    const unknown = protocol.Capability{ .name = "vendor.unknown", .value = "1" };
    const decoded_capabilities = try protocol.decodeCapabilities(gpa, payload.items);
    defer gpa.free(decoded_capabilities);
    var capabilities = try gpa.alloc(protocol.Capability, decoded_capabilities.len + 1);
    defer gpa.free(capabilities);
    @memcpy(capabilities[0..decoded_capabilities.len], decoded_capabilities);
    capabilities[capabilities.len - 1] = unknown;
    var combined: std.ArrayList(u8) = .empty;
    defer combined.deinit(gpa);
    try protocol.encodeCapabilities(gpa, capabilities, &combined);
    const decoded_unknown = try decodeSet(gpa, combined.items);
    try std.testing.expectEqual(set.contains(.text_ascii_bounded), decoded_unknown.contains(.text_ascii_bounded));
}

test "known malformed capability values are rejected" {
    const gpa = std.testing.allocator;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    const capabilities = [_]protocol.Capability{.{ .name = "protocol.v1", .value = "yes" }};
    try protocol.encodeCapabilities(gpa, &capabilities, &payload);
    try std.testing.expectError(Error.InvalidCapabilityValue, decodeSet(gpa, payload.items));
}

test "negotiation reports a stable effective-set hash" {
    const all = backendSupported();
    var without_renderer = all;
    without_renderer.bits[@intFromEnum(Feature.clipboard_ascii_bounded)] = false;
    const left = try negotiate(all, without_renderer);
    const right = try negotiate(without_renderer, all);
    try std.testing.expectEqualSlices(u8, &left.hash, &right.hash);
    try std.testing.expect(left.effective.contains(.protocol_v1));
    try std.testing.expect(!left.effective.contains(.clipboard_ascii_bounded));
}

test "negotiation intersects and enforces required features" {
    const all = backendSupported();
    const negotiated = try negotiate(all, all);
    var expected_hash: [hash_len]u8 = undefined;
    hashEffective(all, &expected_hash);
    try std.testing.expectEqualSlices(u8, &expected_hash, &negotiated.hash);

    var missing_text = all;
    missing_text.bits[@intFromEnum(Feature.text_ascii_bounded)] = false;
    try std.testing.expectError(Error.MissingRequiredCapability, negotiate(all, missing_text));

    var left_only = all;
    left_only.bits[@intFromEnum(Feature.clipboard_ascii_bounded)] = false;
    const effective = try negotiate(left_only, all);
    try std.testing.expect(!effective.effective.contains(.clipboard_ascii_bounded));
}
