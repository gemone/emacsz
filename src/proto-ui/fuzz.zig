//! Deterministic, bounded, in-process protocol fuzz hardening.
//!
//! This adapter-owned harness mutates only valid codec seeds.  Every iteration
//! uses fresh storage, every decode/application error is counted instead of
//! escaped, and no target retains state across iterations.  It uses neither
//! libFuzzer nor a network connection.

const std = @import("std");
const protocol = @import("protocol.zig");
const frontend = @import("frontend.zig");
const facts = @import("facts.zig");

pub const default_iterations: u32 = 4096;
pub const max_iterations: u32 = 100_000;
pub const max_input_bytes: usize = 8 * 1024;

pub const Target = enum {
    raw_eup_envelope,
    frame_update_payload,
    capability_table,
    frame_visibility_focus,
    resource_request_evict,
    input_codecs,
    glyph_run_debug_v1,
    frontend_scene_apply,

    pub const count = @typeInfo(Target).@"enum".fields.len;

    pub fn name(self: Target) []const u8 {
        return @tagName(self);
    }
};

pub const target_names: [Target.count][]const u8 = blk: {
    var names: [Target.count][]const u8 = undefined;
    for (0..Target.count) |index| {
        names[index] = @as(Target, @enumFromInt(index)).name();
    }
    break :blk names;
};

pub const Mutation = enum {
    byte_flip,
    truncate,
    field_type_flip,
    duplicate,
    zero_generation,
    stale_generation,
    oversized_length,
    invalid_reserved,
};

pub const Counts = struct {
    accepted: u64 = 0,
    rejected: u64 = 0,

    pub fn total(self: Counts) u64 {
        return self.accepted + self.rejected;
    }
};

const Shape = struct {
    length_offset: ?usize = null,
    identity_offset: ?usize = null,
    type_offset: ?usize = null,
    reserved_offset: ?usize = null,
};

fn shapeFor(target: Target, variant: usize) Shape {
    return switch (target) {
        .raw_eup_envelope, .frontend_scene_apply => .{
            .length_offset = 14,
            .identity_offset = 42,
            .type_offset = 10,
            .reserved_offset = 46,
        },
        .frame_update_payload => .{
            .length_offset = 88,
            .identity_offset = 4,
            .type_offset = 72,
            .reserved_offset = 74,
        },
        .capability_table => .{ .length_offset = 0, .type_offset = 4 },
        .frame_visibility_focus => .{
            .identity_offset = 4,
            .type_offset = 8,
            .reserved_offset = 9,
        },
        .resource_request_evict => if (variant & 1 == 0)
            .{ .length_offset = 0, .identity_offset = 8, .type_offset = 4 }
        else
            .{ .identity_offset = 8, .type_offset = 12, .reserved_offset = 1 },
        .input_codecs => .{ .length_offset = 0, .type_offset = 0, .reserved_offset = 12 },
        .glyph_run_debug_v1 => .{
            .length_offset = 14,
            .identity_offset = 42,
            .type_offset = 10,
            .reserved_offset = 46,
        },
    };
}

pub fn mutationAt(random: std.Random, index: usize) Mutation {
    const values = [_]Mutation{
        .byte_flip,        .truncate,         .field_type_flip,
        .duplicate,        .zero_generation,  .oversized_length,
        .stale_generation, .invalid_reserved,
    };
    const selected = random.intRangeAtMost(usize, 0, values.len - 1);
    return values[(index +% selected) % values.len];
}

fn putU32(bytes: []u8, offset: usize, value: u32) void {
    if (offset + 4 <= bytes.len) {
        std.mem.writeInt(u32, bytes[offset..][0..4], value, .little);
    }
}

/// The caller owns the returned allocation.  A truncated result remains the
/// same base allocation and is safe for the allocator's sized free.
fn mutate(
    allocator: std.mem.Allocator,
    seed: []const u8,
    target: Target,
    variant: usize,
    mutation: Mutation,
    random: std.Random,
) ![]u8 {
    if (seed.len > max_input_bytes) return error.InputTooLarge;
    const bytes = try allocator.dupe(u8, seed);
    errdefer allocator.free(bytes);
    const shape = shapeFor(target, variant);

    switch (mutation) {
        .byte_flip => {
            const offset = random.intRangeLessThan(usize, 0, bytes.len);
            const bit = random.intRangeAtMost(u3, 0, 7);
            bytes[offset] ^= @as(u8, 1) << bit;
        },
        .truncate => {
            const length = random.intRangeLessThan(usize, 0, bytes.len);
            const shrunk = try allocator.realloc(bytes, length);
            // `errdefer` owns the original allocation only while realloc
            // fails.  After success ownership transfers to `shrunk`.
            return shrunk;
        },
        .field_type_flip => {
            const offset = shape.type_offset orelse
                random.intRangeLessThan(usize, 0, bytes.len);
            if (offset < bytes.len) bytes[offset] ^= 0xff;
        },
        .duplicate => {
            const duplicated = try duplicateRecord(allocator, target, variant, bytes);
            if (duplicated) |result| {
                return result;
            } else if (bytes.len == 0 or bytes.len * 2 > max_input_bytes) {
                const offset = random.intRangeLessThan(usize, 0, bytes.len);
                bytes[offset] ^= 1;
                return bytes;
            }
            const doubled = try allocator.alloc(u8, bytes.len * 2);
            defer allocator.free(bytes);
            @memcpy(doubled[0..bytes.len], bytes);
            @memcpy(doubled[bytes.len..], bytes);
            return doubled;
        },
        .zero_generation => {
            const offset = shape.identity_offset orelse
                random.intRangeLessThan(usize, 0, bytes.len);
            putU32(bytes, offset, 0);
        },
        .stale_generation => {
            const offset = shape.identity_offset orelse
                random.intRangeLessThan(usize, 0, bytes.len);
            if (offset + 4 <= bytes.len) {
                const generation = std.mem.readInt(u32, bytes[offset..][0..4], .little);
                putU32(bytes, offset, if (generation > 1) generation - 1 else 0);
            }
        },
        .oversized_length => {
            const offset = shape.length_offset orelse
                random.intRangeLessThan(usize, 0, bytes.len);
            putU32(bytes, offset, std.math.maxInt(u32));
        },
        .invalid_reserved => {
            const offset = shape.reserved_offset orelse
                random.intRangeLessThan(usize, 0, bytes.len);
            if (offset < bytes.len) bytes[offset] = 0xa5;
        },
    }
    return bytes;
}

/// Builds an exact duplicate section/record when the target's grammar has a
/// count header.  A null result falls back to whole-input duplication for
/// message formats that detect trailing bytes.
fn duplicateRecord(
    allocator: std.mem.Allocator,
    target: Target,
    variant: usize,
    bytes: []u8,
) !?[]u8 {
    switch (target) {
        .frame_update_payload => {
            if (bytes.len < 96 or std.mem.readInt(u32, bytes[88..92], .little) != 1)
                return null;
            const section_length = std.mem.readInt(u32, bytes[92..96], .little);
            const section_bytes = 8 + @as(usize, section_length);
            if (section_length > bytes.len - 96 or bytes.len + section_bytes > max_input_bytes)
                return null;
            const doubled = try allocator.alloc(u8, bytes.len + section_bytes);
            defer allocator.free(bytes);
            @memcpy(doubled[0..bytes.len], bytes);
            @memcpy(doubled[bytes.len..], bytes[96..][0..section_bytes]);
            std.mem.writeInt(u32, doubled[88..92], 2, .little);
            return doubled;
        },
        .capability_table => {
            if (bytes.len < 6) return null;
            const doubled = try allocator.alloc(u8, bytes.len + bytes.len - 4);
            defer allocator.free(bytes);
            @memcpy(doubled[0..bytes.len], bytes);
            @memcpy(doubled[bytes.len..], bytes[4..]);
            std.mem.writeInt(u32, doubled[0..4], 2, .little);
            return doubled;
        },
        .resource_request_evict => {
            if (variant & 1 != 0 or bytes.len != 28) return null;
            const doubled = try allocator.alloc(u8, 40);
            defer allocator.free(bytes);
            @memcpy(doubled[0..bytes.len], bytes);
            @memcpy(doubled[28..40], bytes[16..28]);
            std.mem.writeInt(u32, doubled[0..4], 3, .little);
            return doubled;
        },
        else => return null,
    }
}

fn envelope(
    allocator: std.mem.Allocator,
    payload: []const u8,
    message_type: u16,
    frame_id: u32,
    sequence: u64,
    out: *std.ArrayList(u8),
) !void {
    try protocol.encodeEnvelope(allocator, .{
        .flags = 0,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = if (sequence == 0) 0 else sequence - 1,
        .session_id = 0x1001,
        .frame_id = frame_id,
        .timestamp_ns = 123,
    }, payload, out);
}

fn finishList(allocator: std.mem.Allocator, list: *std.ArrayList(u8)) ![]u8 {
    defer list.deinit(allocator);
    return list.toOwnedSlice(allocator);
}

fn seedRawEnvelope(allocator: std.mem.Allocator, variant: usize) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try envelope(allocator, &.{ 1, 2, 3, 4 }, protocol.Message.hello, 0, 100, &list);
    if (variant != 0) list.items[variant % list.items.len] ^= 1;
    return finishList(allocator, &list);
}

fn frameUpdatePayload(allocator: std.mem.Allocator, sequence: u64) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    // A valid resource record gives the duplicate-section mutator real
    // grammar to target instead of merely manufacturing trailing bytes.
    var resource = [_]u8{0} ** 16;
    resource[0] = @intFromEnum(protocol.ResourceKind.font);
    std.mem.writeInt(u32, resource[4..8], 7, .little);
    std.mem.writeInt(u32, resource[8..12], 1, .little);
    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.resources, .records = &resource },
    };
    try protocol.encodeFrameUpdate(allocator, .{
        .header = .{
            .frame_id = 7,
            .frame_generation = 7,
            .sequence = sequence,
            .redisplay_generation = 11,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = 20,
            .logical_height = 10,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = 40,
            .physical_height = 20,
            .scale = 2,
            .dpi_x = 96,
            .dpi_y = 96,
            .damage_mode = 2,
            .update_cause = 0,
            .coalesced_count = 0,
            .timestamp_ns = 123,
        },
        .sections = &sections,
    }, &list);
    return finishList(allocator, &list);
}

fn seedFrameUpdate(allocator: std.mem.Allocator, variant: usize) ![]u8 {
    const payload = try frameUpdatePayload(allocator, 100 + variant);
    defer allocator.free(payload);
    return allocator.dupe(u8, payload);
}

fn seedCapabilities(allocator: std.mem.Allocator, variant: usize) ![]u8 {
    const capabilities = [_]protocol.Capability{
        .{ .name = "protocol.v1", .value = if (variant == 0) "1" else "stable" },
    };
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try protocol.encodeCapabilities(allocator, &capabilities, &list);
    return finishList(allocator, &list);
}

fn seedVisibilityFocus(allocator: std.mem.Allocator, variant: usize) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    if (variant & 1 == 0) {
        try protocol.encodeFrameVisibility(allocator, .{
            .frame_id = 7,
            .frame_generation = 5,
            .state = @enumFromInt(variant % 3),
        }, &list);
    } else {
        try protocol.encodeFrameFocus(allocator, .{
            .frame_id = 7,
            .frame_generation = 5,
            .focused = variant % 4 == 3,
        }, &list);
    }
    return finishList(allocator, &list);
}

fn seedResources(allocator: std.mem.Allocator, variant: usize) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    if (variant & 1 == 0) {
        const requests = [_]protocol.ResourceRequest{
            .{ .kind = .font, .id = 3, .generation = 4 },
            .{ .kind = .image, .id = 5, .generation = 6 },
        };
        try protocol.encodeResourceRequests(allocator, &requests, &list);
    } else {
        try protocol.encodeResourceEvict(allocator, .{
            .kind = .face,
            .id = 8,
            .generation = 9,
            .reason = .lru,
        }, &list);
    }
    return finishList(allocator, &list);
}

fn seedInputs(allocator: std.mem.Allocator, variant: usize) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    switch (variant % 4) {
        0 => try frontend.encodeTextInput(allocator, .{ .text = "a" }, &list),
        1 => try frontend.encodeKeyEvent(allocator, .{ .action = .cursor_left }, &list),
        2 => try frontend.encodePointerInput(allocator, .{
            .phase = .release,
            .button = 1,
            .x = 3,
            .y = 4,
            .clicks = 1,
        }, &list),
        else => try frontend.encodeWheelInput(allocator, .{ .y = 1 }, &list),
    }
    return finishList(allocator, &list);
}

fn seedGlyphRun(allocator: std.mem.Allocator, variant: usize) ![]u8 {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(allocator);
    try frontend.encodeGlyphRun(allocator, .{
        .run_id = 9,
        .generation = if (variant % 4 == 3) 2 else 1,
        .window_id = 1001,
        .row_index = 0,
        .x = 1,
        .y = 2,
        .width = 20,
        .height = 8,
        .text = "Emacs",
    }, &payload);
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try envelope(allocator, payload.items, protocol.Message.glyph_run, 1, 3, &list);
    if (variant % 4 == 1) list.items[list.items.len - 1] = 0;
    if (variant % 4 == 2) try list.append(allocator, 'x');
    return finishList(allocator, &list);
}

fn seedScene(allocator: std.mem.Allocator, variant: usize) ![]u8 {
    var payload: [8]u8 = undefined;
    std.mem.writeInt(u32, payload[0..4], 7, .little);
    std.mem.writeInt(u32, payload[4..8], 1, .little);
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try envelope(allocator, &payload, protocol.Message.frame_create, 7, 100 + variant, &list);
    return finishList(allocator, &list);
}

fn makeSeed(allocator: std.mem.Allocator, target: Target, iteration: usize) ![]u8 {
    return switch (target) {
        .raw_eup_envelope => seedRawEnvelope(allocator, iteration),
        .frame_update_payload => seedFrameUpdate(allocator, iteration),
        .capability_table => seedCapabilities(allocator, iteration),
        .frame_visibility_focus => seedVisibilityFocus(allocator, iteration),
        .resource_request_evict => seedResources(allocator, iteration),
        .input_codecs => seedInputs(allocator, iteration),
        .glyph_run_debug_v1 => seedGlyphRun(allocator, iteration),
        .frontend_scene_apply => seedScene(allocator, iteration),
    };
}

fn applyError(err: anyerror) !bool {
    if (err == error.OutOfMemory) return err;
    return false;
}

fn applyTarget(
    allocator: std.mem.Allocator,
    target: Target,
    variant: usize,
    input_bytes: []const u8,
) !bool {
    switch (target) {
        .raw_eup_envelope => {
            _ = protocol.decodeEnvelope(input_bytes) catch |err| {
                return if (err == error.OutOfMemory) err else false;
            };
            return true;
        },
        .frontend_scene_apply => {
            var scene = frontend.Scene.init(allocator);
            defer scene.deinit();
            scene.apply(input_bytes) catch |err| return applyError(err);
            return true;
        },
        .frame_update_payload => {
            const update = protocol.decodeFrameUpdate(allocator, input_bytes) catch |err| {
                return if (err == error.OutOfMemory) err else false;
            };
            var owned = update;
            defer protocol.freeFrameUpdate(allocator, &owned);
            return true;
        },
        .capability_table => {
            const capabilities = protocol.decodeCapabilities(allocator, input_bytes) catch |err| {
                return if (err == error.OutOfMemory) err else false;
            };
            defer allocator.free(capabilities);
            return true;
        },
        .frame_visibility_focus => {
            if (variant & 1 == 0) {
                _ = protocol.decodeFrameVisibility(input_bytes) catch |err| {
                    return if (err == error.OutOfMemory) err else false;
                };
            } else {
                _ = protocol.decodeFrameFocus(input_bytes) catch |err| {
                    return if (err == error.OutOfMemory) err else false;
                };
            }
            return true;
        },
        .resource_request_evict => {
            // The two valid shapes have distinct base lengths (28 vs 16).
            // Mutants stay inside their decoder family, including oversized
            // request counts and duplicate/truncated payloads.
            // The two valid shapes have distinct base lengths (28 vs 16).
            // Mutants stay inside their decoder family, including oversized
            // request counts and duplicate/truncated payloads.
            if (variant & 1 == 0) {
                const requests = protocol.decodeResourceRequests(allocator, input_bytes) catch |err| {
                    return if (err == error.OutOfMemory) err else false;
                };
                defer allocator.free(requests);
            } else {
                _ = protocol.decodeResourceEvict(input_bytes) catch |err| {
                    return if (err == error.OutOfMemory) err else false;
                };
            }
            return true;
        },
        .glyph_run_debug_v1 => {
            var scene = try facts.buildScene(allocator, .{
                .frame_width = 80,
                .frame_height = 60,
                .window_width = 80,
                .window_height = 60,
            }, 0);
            defer scene.deinit();
            scene.apply(input_bytes) catch |err| {
                return applyError(err);
            };
            return true;
        },
        .input_codecs => switch (variant % 4) {
            0 => {
                const decoded = frontend.decodeTextInput(input_bytes) catch |err| return applyError(err);
                _ = decoded;
                return true;
            },
            1 => {
                const decoded = frontend.decodeKeyEvent(input_bytes) catch |err| return applyError(err);
                _ = decoded;
                return true;
            },
            2 => {
                const decoded = frontend.decodePointerInput(input_bytes) catch |err| return applyError(err);
                _ = decoded;
                return true;
            },
            else => {
                const decoded = frontend.decodeWheelInput(input_bytes) catch |err| return applyError(err);
                _ = decoded;
                return true;
            },
        },
    }
}

pub fn runIteration(
    allocator: std.mem.Allocator,
    target: Target,
    iteration: usize,
    random: std.Random,
) !Counts {
    const seed = try makeSeed(allocator, target, iteration);
    defer allocator.free(seed);
    const mutated = try mutate(
        allocator,
        seed,
        target,
        iteration,
        mutationAt(random, iteration),
        random,
    );
    defer allocator.free(mutated);
    if (try applyTarget(allocator, target, iteration, mutated)) {
        return .{ .accepted = 1, .rejected = 0 };
    }
    return .{ .accepted = 0, .rejected = 1 };
}

pub fn runTarget(
    allocator: std.mem.Allocator,
    target: Target,
    iterations: u32,
    seed: u64,
) !Counts {
    var prng = std.Random.DefaultPrng.init(seed ^ hashTarget(target));
    var counts: Counts = .{};
    for (0..iterations) |iteration| {
        const iteration_counts = try runIteration(allocator, target, iteration, prng.random());
        counts.accepted += iteration_counts.accepted;
        counts.rejected += iteration_counts.rejected;
    }
    return counts;
}

pub fn runAll(
    allocator: std.mem.Allocator,
    iterations: u32,
    seed: u64,
) !Counts {
    var total: Counts = .{};
    for (0..Target.count) |index| {
        const counts = try runTarget(allocator, @enumFromInt(index), iterations, seed);
        total.accepted += counts.accepted;
        total.rejected += counts.rejected;
    }
    return total;
}

fn hashTarget(target: Target) u64 {
    return std.hash.Wyhash.hash(0, target.name());
}

pub const Options = struct {
    iterations: u32 = default_iterations,
    seed: u64 = 0x70726f746f2d7569,
};

fn parseU64(text: []const u8) !u64 {
    return std.fmt.parseInt(u64, text, 10) catch error.InvalidFuzzOption;
}

pub fn parseOptions(
    arguments: []const []const u8,
    defaults: Options,
) !Options {
    var options = defaults;
    var index: usize = 0;
    while (index < arguments.len) : (index += 1) {
        const argument = arguments[index];
        var value: []const u8 = "";
        if (std.mem.startsWith(u8, argument, "--iterations=")) {
            value = argument["--iterations=".len..];
        } else if (std.mem.eql(u8, argument, "--iterations")) {
            index += 1;
            if (index >= arguments.len) return error.MissingFuzzOptionValue;
            value = arguments[index];
        } else if (std.mem.startsWith(u8, argument, "--seed=")) {
            value = argument["--seed=".len..];
        } else if (std.mem.eql(u8, argument, "--seed")) {
            index += 1;
            if (index >= arguments.len) return error.MissingFuzzOptionValue;
            value = arguments[index];
        } else {
            return error.UnknownFuzzOption;
        }
        const parsed = try parseU64(value);
        if (std.mem.startsWith(u8, argument, "--iterations")) {
            if (parsed == 0 or parsed > max_iterations) return error.IterationsOutOfRange;
            options.iterations = @intCast(parsed);
        } else {
            if (parsed == 0) return error.SeedOutOfRange;
            options.seed = parsed;
        }
    }
    return options;
}

fn printSummary(options: Options, counts: Counts) !void {
    std.debug.print(
        "{{\"summary\":\"proto-ui-fuzz\",\"seed\":{d},\"iterations\":{d},\"accepted\":{d},\"rejected\":{d},\"targets\":[",
        .{
            options.seed,
            options.iterations,
            counts.accepted,
            counts.rejected,
        },
    );
    for (target_names, 0..) |target, index| {
        std.debug.print("{s}\"{s}\"", .{ if (index == 0) "" else ",", target });
    }
    std.debug.print("],\"result\":\"pass\"}}\n", .{});
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var iterator = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer iterator.deinit();
    _ = iterator.next();

    var arguments: std.ArrayList([]const u8) = .empty;
    defer arguments.deinit(gpa);
    while (iterator.next()) |argument| try arguments.append(gpa, argument);
    const options = try parseOptions(arguments.items, .{});
    const counts = try runAll(gpa, options.iterations, options.seed);
    if (counts.total() != @as(u64, options.iterations) * Target.count) return error.FuzzCountMismatch;
    try printSummary(options, counts);
}

test "prng and mutation selection are deterministic" {
    var left = std.Random.DefaultPrng.init(1234);
    var right = std.Random.DefaultPrng.init(1234);
    for (0..32) |index| {
        try std.testing.expectEqual(
            mutationAt(left.random(), index),
            mutationAt(right.random(), index),
        );
    }

    var first = std.Random.DefaultPrng.init(99);
    var second = std.Random.DefaultPrng.init(99);
    for (0..8) |_| {
        try std.testing.expectEqual(first.random().int(u64), second.random().int(u64));
    }
}

test "every fuzz target counts mutated valid seeds" {
    const allocator = std.testing.allocator;
    inline for (0..Target.count) |target_index| {
        const target: Target = @enumFromInt(target_index);
        const seed = try makeSeed(allocator, target, 0);
        defer allocator.free(seed);
        try std.testing.expect(try applyTarget(allocator, target, 0, seed));

        const counts = try runTarget(allocator, target, 16, 4200 + target_index);
        try std.testing.expectEqual(@as(u64, 16), counts.total());
        // Unmutated seeds prove an accepted baseline; mutation families target
        // grammar violations, so a nonzero rejection count proves coverage.
        try std.testing.expect(counts.rejected > 0);
    }
}

test "fuzz target runs are deterministic and leave no allocations" {
    const allocator = std.testing.allocator;
    const left = try runTarget(allocator, .frame_update_payload, 8, 314159);
    const right = try runTarget(allocator, .frame_update_payload, 8, 314159);
    try std.testing.expectEqual(left, right);

    for (0..Target.count) |target_index| {
        _ = try runTarget(allocator, @enumFromInt(target_index), 3, 271828);
    }
}

test "mutation families are bounded and free cleanly" {
    const allocator = std.testing.allocator;
    var source = std.Random.DefaultPrng.init(7);
    const random = source.random();
    for (0..Target.count) |target_index| {
        const target: Target = @enumFromInt(target_index);
        const seed = try makeSeed(allocator, target, 0);
        defer allocator.free(seed);
        inline for (@typeInfo(Mutation).@"enum".fields) |field| {
            const mutation: Mutation = @enumFromInt(field.value);
            const mutated = try mutate(allocator, seed, target, 0, mutation, random);
            defer allocator.free(mutated);
            try std.testing.expect(mutated.len <= max_input_bytes);
        }
    }
}

test "CLI options are bounded and parsed" {
    const combined = try parseOptions(&.{ "--iterations=12", "--seed=77" }, .{});
    try std.testing.expectEqual(@as(u32, 12), combined.iterations);
    try std.testing.expectEqual(@as(u64, 77), combined.seed);

    const separate = try parseOptions(&.{ "--iterations", "13", "--seed", "78" }, .{});
    try std.testing.expectEqual(@as(u32, 13), separate.iterations);
    try std.testing.expectEqual(@as(u64, 78), separate.seed);

    try std.testing.expectError(error.IterationsOutOfRange, parseOptions(&.{"--iterations=0"}, .{}));
    try std.testing.expectError(error.IterationsOutOfRange, parseOptions(&.{ "--iterations", "100001" }, .{}));
    try std.testing.expectError(error.SeedOutOfRange, parseOptions(&.{"--seed=0"}, .{}));
    try std.testing.expectError(error.UnknownFuzzOption, parseOptions(&.{"--network"}, .{}));
}
