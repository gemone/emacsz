//! Adapter-owned frame and resource generation state machines.
//!
//! These policies are transport- and renderer-independent.  They make frame
//! identity and resource versioning explicit before the bounded facts profile
//! can be expanded toward redisplay-owned faces, fonts, images, and glyphs.

const std = @import("std");
const protocol = @import("protocol.zig");

pub const Error = protocol.Error || error{
    FrameAlreadyExists,
    FrameNotActive,
    FrameNotVisible,
    ResourceTableFull,
    ResourceNotLive,
    ResourcePayloadTooLarge,
    ResourcePayloadBudgetExceeded,
    StaleGeneration,
};

pub const max_frames: usize = 8;
pub const max_resources: usize = 64;
pub const max_resource_payload_entries: usize = 32;
pub const max_resource_payload_bytes: usize = 4096;
pub const resource_payload_byte_budget: usize = 16384;

pub const FrameStatus = enum(u8) {
    active = 1,
    destroyed = 2,
};

pub const FrameVisibility = protocol.FrameVisibilityState;

pub const Frame = struct {
    id: u32,
    generation: u32,
    status: FrameStatus,
    visibility: FrameVisibility = .visible,
    focused: bool = false,
};

pub const FrameRegistry = struct {
    frames: [max_frames]Frame = undefined,
    len: usize = 0,

    pub fn reset(self: *FrameRegistry) void {
        self.* = .{};
    }

    fn find(self: FrameRegistry, id: u32) ?*const Frame {
        for (self.frames[0..self.len]) |*frame| {
            if (frame.id == id) return frame;
        }
        return null;
    }

    pub fn lookup(self: FrameRegistry, id: u32) ?Frame {
        const frame = self.find(id) orelse return null;
        return frame.*;
    }

    /// A frame ID is never recycled. A destroy keeps the highest generation so
    /// a later stale create cannot resurrect it.
    pub fn create(self: *FrameRegistry, id: u32, generation: u32) Error!void {
        if (id == 0 or generation == 0) return Error.InvalidMessage;
        if (self.find(id) != null) return Error.FrameAlreadyExists;
        for (self.frames[0..self.len]) |frame| {
            if (frame.status == .active) return Error.FrameAlreadyExists;
        }
        if (self.len == max_frames) return Error.ResourceTableFull;
        self.frames[self.len] = .{ .id = id, .generation = generation, .status = .active };
        self.len += 1;
    }

    pub fn setVisibility(self: *FrameRegistry, id: u32, generation: u32, visibility: FrameVisibility) Error!void {
        const frame = self.find(id) orelse return Error.FrameNotActive;
        if (frame.status != .active or frame.generation != generation) return Error.FrameNotActive;
        self.frames[self.frameIndex(id)].visibility = visibility;
        if (visibility != .visible) self.frames[self.frameIndex(id)].focused = false;
    }

    pub fn setFocus(self: *FrameRegistry, id: u32, generation: u32, focused: bool) Error!void {
        const frame = self.find(id) orelse return Error.FrameNotActive;
        if (frame.status != .active or frame.generation != generation) return Error.FrameNotActive;
        if (focused and frame.visibility != .visible) return Error.FrameNotVisible;
        self.frames[self.frameIndex(id)].focused = focused;
    }

    pub fn update(self: *FrameRegistry, id: u32, generation: u32) Error!void {
        const frame = self.find(id) orelse return Error.FrameNotActive;
        if (frame.status != .active or frame.generation != generation) return Error.FrameNotActive;
    }

    pub fn destroy(self: *FrameRegistry, id: u32, generation: u32) Error!void {
        const frame = self.find(id) orelse return Error.FrameNotActive;
        if (frame.status != .active or frame.generation != generation) return Error.FrameNotActive;
        const index = self.frameIndex(id);
        self.frames[index].status = .destroyed;
        self.frames[index].visibility = .hidden;
        self.frames[index].focused = false;
    }

    fn frameIndex(self: *FrameRegistry, id: u32) usize {
        for (self.frames[0..self.len], 0..) |frame, index| {
            if (frame.id == id) return index;
        }
        unreachable;
    }
};

pub const ResourceKind = protocol.ResourceKind;

pub const ResourceStatus = enum(u8) {
    live = 1,
    deleted = 2,
};

pub const Resource = struct {
    kind: ResourceKind,
    id: u32,
    generation: u32,
    status: ResourceStatus,
};

pub const ResourceRegistry = struct {
    resources: [max_resources]Resource = undefined,
    len: usize = 0,

    pub fn reset(self: *ResourceRegistry) void {
        self.* = .{};
    }

    fn find(self: ResourceRegistry, kind: ResourceKind, id: u32) ?usize {
        for (self.resources[0..self.len], 0..) |resource, index| {
            if (resource.kind == kind and resource.id == id) return index;
        }
        return null;
    }

    pub fn lookup(self: ResourceRegistry, kind: ResourceKind, id: u32) ?Resource {
        const index = self.find(kind, id) orelse return null;
        return self.resources[index];
    }

    /// Validate every declaration before mutating so a malformed composite
    /// frame cannot leave a partially applied resource table.
    pub fn validateDeclarations(self: ResourceRegistry, declarations: []const Resource) Error!void {
        var new_count: usize = 0;
        for (declarations, 0..) |declaration, declaration_index| {
            if (declaration.generation == 0 or declaration.id == 0) return Error.InvalidMessage;
            if (declaration.status != .live) return Error.InvalidMessage;
            for (declarations[0..declaration_index]) |prior| {
                if (prior.kind == declaration.kind and prior.id == declaration.id)
                    return Error.InvalidTable;
            }
            if (self.find(declaration.kind, declaration.id)) |index| {
                const old = self.resources[index];
                if (declaration.generation <= old.generation) return Error.StaleGeneration;
            } else {
                new_count += 1;
            }
        }
        if (self.len + new_count > max_resources) return Error.ResourceTableFull;
    }

    pub fn declareAll(self: *ResourceRegistry, declarations: []const Resource) Error!void {
        try self.validateDeclarations(declarations);
        for (declarations) |declaration| {
            if (self.find(declaration.kind, declaration.id)) |index| {
                self.resources[index] = .{
                    .kind = declaration.kind,
                    .id = declaration.id,
                    .generation = declaration.generation,
                    .status = .live,
                };
                continue;
            }
            if (self.len == max_resources) return Error.ResourceTableFull;
            self.resources[self.len] = .{
                .kind = declaration.kind,
                .id = declaration.id,
                .generation = declaration.generation,
                .status = .live,
            };
            self.len += 1;
        }
    }

    pub fn delete(self: *ResourceRegistry, kind: ResourceKind, id: u32, generation: u32) Error!void {
        const index = self.find(kind, id) orelse return Error.ResourceNotLive;
        const resource = self.resources[index];
        if (resource.status != .live or resource.generation != generation)
            return Error.StaleGeneration;
        self.resources[index].status = .deleted;
    }
};

pub const ResourcePayloadKey = struct {
    kind: ResourceKind,
    id: u32,
};

pub const ResourcePayloadEntry = struct {
    key: ResourcePayloadKey,
    generation: u32,
    bytes: []u8,
    last_use: u64,
};

pub const ResourcePayloadCounters = struct {
    hits: u64 = 0,
    misses: u64 = 0,
    inserts: u64 = 0,
    updates: u64 = 0,
    evictions: u64 = 0,
};

pub const ResourcePayloadStore = struct {
    allocator: std.mem.Allocator,
    entries: [max_resource_payload_entries]ResourcePayloadEntry = undefined,
    entry_count: usize = 0,
    current_bytes: usize = 0,
    clock: u64 = 0,
    counters: ResourcePayloadCounters = .{},

    pub fn init(allocator: std.mem.Allocator) ResourcePayloadStore {
        return .{ .allocator = allocator };
    }

    const Key = ResourcePayloadKey;

    fn find(self: ResourcePayloadStore, key: Key) ?usize {
        for (self.entries[0..self.entry_count], 0..) |entry, index| {
            if (entry.key.kind == key.kind and entry.key.id == key.id) return index;
        }
        return null;
    }

    fn oldestIndexExcept(self: ResourcePayloadStore, except: ?Key) ?usize {
        var oldest: ?usize = null;
        for (self.entries[0..self.entry_count], 0..) |entry, index| {
            if (except != null and entry.key.kind == except.?.kind and entry.key.id == except.?.id)
                continue;
            if (oldest == null or entry.last_use < self.entries[oldest.?].last_use)
                oldest = index;
        }
        return oldest;
    }

    pub fn lookup(self: *ResourcePayloadStore, kind: ResourceKind, id: u32, generation: u32) ?[]const u8 {
        const index = self.find(.{ .kind = kind, .id = id }) orelse {
            self.counters.misses += 1;
            return null;
        };
        if (self.entries[index].generation != generation) {
            self.counters.misses += 1;
            return null;
        }
        self.clock += 1;
        self.entries[index].last_use = self.clock;
        self.counters.hits += 1;
        return self.entries[index].bytes;
    }

    pub fn put(
        self: *ResourcePayloadStore,
        kind: ResourceKind,
        id: u32,
        generation: u32,
        payload: []const u8,
    ) (Error || std.mem.Allocator.Error)!void {
        if (id == 0 or generation == 0) return Error.InvalidMessage;
        if (payload.len == 0) return Error.InvalidMessage;
        if (payload.len > max_resource_payload_bytes) return Error.ResourcePayloadTooLarge;
        const key = Key{ .kind = kind, .id = id };
        const existing_index = self.find(key);
        if (existing_index) |index| {
            if (generation <= self.entries[index].generation) return Error.StaleGeneration;
        }

        // Materialize the payload before eviction or replacement so OOM cannot
        // leave an evicted cache or a partially updated entry.
        const owned = try self.allocator.dupe(u8, payload);
        errdefer self.allocator.free(owned);

        if (existing_index) |index| {
            const old_bytes = self.entries[index].bytes;
            while (self.current_bytes - old_bytes.len + payload.len > resource_payload_byte_budget) {
                const oldest = self.oldestIndexExcept(key) orelse
                    return Error.ResourcePayloadBudgetExceeded;
                self.current_bytes -= self.entries[oldest].bytes.len;
                self.allocator.free(self.entries[oldest].bytes);
                if (oldest + 1 != self.entry_count)
                    self.entries[oldest] = self.entries[self.entry_count - 1];
                self.entry_count -= 1;
                self.counters.evictions += 1;
            }

            const entry_index = self.find(key) orelse unreachable;
            const entry = &self.entries[entry_index];
            const replaced_bytes = entry.bytes;
            self.clock += 1;
            entry.bytes = owned;
            entry.generation = generation;
            entry.last_use = self.clock;
            self.allocator.free(replaced_bytes);
            self.current_bytes = self.current_bytes - replaced_bytes.len + payload.len;
            self.counters.updates += 1;
            return;
        }

        // A valid new payload always fits after evicting sufficiently many LRU
        // entries because each payload is bounded by the total byte budget.
        while (self.entry_count + 1 > max_resource_payload_entries or
            self.current_bytes + payload.len > resource_payload_byte_budget)
        {
            const oldest = self.oldestIndexExcept(null) orelse
                return Error.ResourcePayloadBudgetExceeded;
            self.current_bytes -= self.entries[oldest].bytes.len;
            self.allocator.free(self.entries[oldest].bytes);
            if (oldest + 1 != self.entry_count)
                self.entries[oldest] = self.entries[self.entry_count - 1];
            self.entry_count -= 1;
            self.counters.evictions += 1;
        }

        self.clock += 1;
        self.entries[self.entry_count] = .{
            .key = key,
            .generation = generation,
            .bytes = owned,
            .last_use = self.clock,
        };
        self.entry_count += 1;
        self.current_bytes += payload.len;
        self.counters.inserts += 1;
    }

    pub fn remove(self: *ResourcePayloadStore, kind: ResourceKind, id: u32, generation: u32) Error!void {
        const index = self.find(.{ .kind = kind, .id = id }) orelse return Error.ResourceNotLive;
        if (self.entries[index].generation != generation) return Error.StaleGeneration;
        const bytes = self.entries[index].bytes;
        self.current_bytes -= bytes.len;
        self.allocator.free(bytes);
        if (index + 1 != self.entry_count)
            self.entries[index] = self.entries[self.entry_count - 1];
        self.entry_count -= 1;
    }

    pub fn clear(self: *ResourcePayloadStore) void {
        for (self.entries[0..self.entry_count]) |entry| self.allocator.free(entry.bytes);
        self.entry_count = 0;
        self.current_bytes = 0;
    }

    pub fn deinit(self: *ResourcePayloadStore) void {
        const allocator = self.allocator;
        self.clear();
        self.* = .{ .allocator = allocator };
    }
};

test "frame registry enforces create update destroy lifecycle" {
    var registry: FrameRegistry = .{};
    try registry.create(1, 1);
    try registry.update(1, 1);
    try std.testing.expectError(Error.FrameAlreadyExists, registry.create(1, 2));
    try std.testing.expectError(Error.FrameNotActive, registry.update(1, 2));
    try registry.destroy(1, 1);
    try std.testing.expectError(Error.FrameNotActive, registry.update(1, 1));
    try std.testing.expectError(Error.FrameNotActive, registry.destroy(1, 1));
    try std.testing.expectError(Error.FrameAlreadyExists, registry.create(1, 2));
}

test "resource registry validates composite declarations atomically" {
    var registry: ResourceRegistry = .{};
    const first = [_]Resource{
        .{ .kind = .font, .id = 1, .generation = 2, .status = .live },
        .{ .kind = .string, .id = 3, .generation = 1, .status = .live },
    };
    try registry.declareAll(&first);
    try std.testing.expectEqual(ResourceStatus.live, registry.lookup(.font, 1).?.status);

    // The second declaration is stale; neither declaration may be applied.
    const invalid = [_]Resource{
        .{ .kind = .font, .id = 1, .generation = 3, .status = .live },
        .{ .kind = .string, .id = 3, .generation = 1, .status = .live },
    };
    try std.testing.expectError(Error.StaleGeneration, registry.declareAll(&invalid));
    try std.testing.expectEqual(@as(u32, 2), registry.lookup(.font, 1).?.generation);

    const newer = [_]Resource{
        .{ .kind = .font, .id = 1, .generation = 3, .status = .live },
    };
    try registry.declareAll(&newer);
    try registry.delete(.font, 1, 3);
    try std.testing.expectEqual(ResourceStatus.deleted, registry.lookup(.font, 1).?.status);
    try std.testing.expectError(Error.StaleGeneration, registry.delete(.font, 1, 3));
}

test "resource payload store performs bounded LRU replacement" {
    const a = std.testing.allocator;
    var store = ResourcePayloadStore.init(a);
    defer store.deinit();

    try store.put(.font, 1, 2, "font-2");
    try store.put(.image, 2, 1, "image-1");
    try std.testing.expectEqual(@as(u64, 2), store.counters.inserts);
    const font = store.lookup(.font, 1, 2) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("font-2", font);

    // A lookup refreshes font; image is therefore the first eviction when
    // capacity pressure is introduced.
    for (0..max_resource_payload_entries - 2) |index| {
        try store.put(.string, @intCast(index + 1), 1, "x");
    }
    try store.put(.face, 3, 1, "face");
    try std.testing.expect(store.lookup(.image, 2, 1) == null);
    try std.testing.expect(store.lookup(.font, 1, 2) != null);
    try std.testing.expectEqual(@as(u64, 1), store.counters.evictions);
}

test "replacement evicts only the minimum LRU entries" {
    const a = std.testing.allocator;
    var store = ResourcePayloadStore.init(a);
    defer store.deinit();

    const other_payload = [_]u8{'x'} ** 4000;
    try store.put(.font, 1, 1, "A");
    try store.put(.image, 2, 1, &other_payload);
    try store.put(.face, 3, 1, &other_payload);
    try store.put(.icon, 4, 1, &other_payload);
    try store.put(.string, 5, 1, &other_payload);
    try std.testing.expectEqual(@as(usize, 16001), store.current_bytes);
    try std.testing.expectEqual(@as(u64, 0), store.counters.evictions);

    const replacement = [_]u8{'A'} ** 4096;
    try store.put(.font, 1, 2, &replacement);

    try std.testing.expectEqual(@as(u64, 1), store.counters.updates);
    try std.testing.expectEqual(@as(u64, 1), store.counters.evictions);
    try std.testing.expectEqual(@as(usize, 4), store.entry_count);
    try std.testing.expectEqual(@as(usize, 16096), store.current_bytes);

    try std.testing.expectEqual(@as(usize, 4096), store.lookup(.font, 1, 2).?.len);
    try std.testing.expectEqualStrings(&other_payload, store.lookup(.face, 3, 1).?);
    try std.testing.expectEqualStrings(&other_payload, store.lookup(.icon, 4, 1).?);
    try std.testing.expectEqualStrings(&other_payload, store.lookup(.string, 5, 1).?);
    try std.testing.expect(store.lookup(.image, 2, 1) == null);
}

test "resource payload store validates generations size budget and OOM" {
    const a = std.testing.allocator;
    var store = ResourcePayloadStore.init(a);
    defer store.deinit();
    try store.put(.font, 1, 1, "old");

    const counters_before_empty = store.counters;
    const entry_count_before_empty = store.entry_count;
    const bytes_before_empty = store.current_bytes;
    try std.testing.expectError(Error.InvalidMessage, store.put(.font, 1, 2, ""));
    try std.testing.expectEqual(counters_before_empty, store.counters);
    try std.testing.expectEqual(entry_count_before_empty, store.entry_count);
    try std.testing.expectEqual(bytes_before_empty, store.current_bytes);
    try std.testing.expectEqualStrings("old", store.lookup(.font, 1, 1).?);

    try std.testing.expectError(Error.StaleGeneration, store.put(.font, 1, 1, "equal"));
    try std.testing.expectError(Error.InvalidMessage, store.put(.font, 1, 0, "stale"));
    try std.testing.expectError(Error.ResourcePayloadTooLarge, store.put(.font, 1, 2, &[_]u8{0} ** (max_resource_payload_bytes + 1)));
    try std.testing.expectEqualStrings("old", store.lookup(.font, 1, 1).?);
    try std.testing.expectEqual(@as(u64, 1), store.counters.inserts);
    try std.testing.expectEqual(@as(usize, 3), store.current_bytes);

    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    store.allocator = failing.allocator();
    try std.testing.expectError(error.OutOfMemory, store.put(.font, 1, 2, "new"));
    store.allocator = a;
    try std.testing.expectEqualStrings("old", store.lookup(.font, 1, 1).?);

    try store.put(.font, 1, 2, "new");
    try store.remove(.font, 1, 2);
    try std.testing.expectError(Error.ResourceNotLive, store.remove(.font, 1, 2));
    try std.testing.expectEqual(@as(usize, 0), store.current_bytes);
    try std.testing.expectEqual(@as(usize, 0), store.entry_count);
}

test "bounded frame and resource tables reject overflow" {
    var frames: FrameRegistry = .{};
    for (1..max_frames + 1) |id| {
        const frame_id: u32 = @intCast(id);
        try frames.create(frame_id, 1);
        try frames.update(frame_id, 1);
        try frames.destroy(frame_id, 1);
    }
    try std.testing.expectError(Error.ResourceTableFull, frames.create(@intCast(max_frames + 1), 1));

    var resources: ResourceRegistry = .{};
    for (1..max_resources + 1) |id| {
        try resources.declareAll(&[_]Resource{.{ .kind = .string, .id = @intCast(id), .generation = 1, .status = .live }});
    }
    try std.testing.expectError(Error.ResourceTableFull, resources.declareAll(&[_]Resource{.{ .kind = .string, .id = max_resources + 1, .generation = 1, .status = .live }}));

    var almost_full: ResourceRegistry = .{};
    for (1..max_resources) |id| {
        try almost_full.declareAll(&[_]Resource{.{ .kind = .string, .id = @intCast(id), .generation = 1, .status = .live }});
    }
    const two_new = [_]Resource{
        .{ .kind = .string, .id = max_resources, .generation = 1, .status = .live },
        .{ .kind = .string, .id = max_resources + 1, .generation = 1, .status = .live },
    };
    try std.testing.expectError(Error.ResourceTableFull, almost_full.declareAll(&two_new));
    try std.testing.expectEqual(@as(usize, max_resources - 1), almost_full.len);
}

test "frame visibility and focus follow live visibility semantics" {
    var registry: FrameRegistry = .{};
    try registry.create(7, 1);
    try std.testing.expectEqual(FrameVisibility.visible, registry.lookup(7).?.visibility);
    try std.testing.expectEqual(false, registry.lookup(7).?.focused);

    try registry.setFocus(7, 1, true);
    try std.testing.expectEqual(true, registry.lookup(7).?.focused);
    try registry.setVisibility(7, 1, .hidden);
    try std.testing.expectEqual(FrameVisibility.hidden, registry.lookup(7).?.visibility);
    try std.testing.expectEqual(false, registry.lookup(7).?.focused);
    try std.testing.expectError(Error.FrameNotVisible, registry.setFocus(7, 1, true));

    try registry.setVisibility(7, 1, .visible);
    try registry.setFocus(7, 1, true);
    try std.testing.expectError(Error.FrameNotActive, registry.setVisibility(7, 2, .visible));
    try std.testing.expectEqual(@as(u32, 1), registry.lookup(7).?.generation);
    try registry.destroy(7, 1);
    try std.testing.expectEqual(FrameVisibility.hidden, registry.lookup(7).?.visibility);
    try std.testing.expectEqual(false, registry.lookup(7).?.focused);
}
