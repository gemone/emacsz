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
    StaleGeneration,
};

pub const max_frames: usize = 8;
pub const max_resources: usize = 64;

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

pub const ResourceKind = enum(u8) {
    face = 1,
    font = 2,
    image = 3,
    fringe_bitmap = 4,
    icon = 5,
    string = 6,
};

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
