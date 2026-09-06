//! Renderer selection policy shared by the SDL3 frontend and tests.

const std = @import("std");

pub const Request = union(enum) {
    auto,
    software,
    gpu,
    named: []const u8,
};

pub const Tier = enum {
    software,
    basic,
    advanced,
};

pub const PresentMode = enum {
    off,
    on,
    adaptive,
};

/// Decides whether the framebuffer needs work. Resize always invalidates the
/// previous frame; an explicit dirty flag covers scene changes and expose
/// events. This is frontend pacing policy, not protocol state.
pub const FrameGate = struct {
    dirty: bool = true,
    width: i32 = 0,
    height: i32 = 0,

    pub fn shouldPresent(self: *FrameGate, width: i32, height: i32) bool {
        const needed = self.dirty or width != self.width or height != self.height;
        self.dirty = false;
        self.width = width;
        self.height = height;
        return needed;
    }
};

/// The first W10b counter set. It measures change-aware full-frame
/// presentation on the frontend, including raster/GPU submit inside
/// `SDL_RenderPresent`. Separate GPU timestamps and atlas counters remain
/// future W10 work.
pub const FrameCounters = struct {
    presented_frames: u64 = 0,
    skipped_frames: u64 = 0,
    draw_commands_total: u64 = 0,
    clear_commands_total: u64 = 0,
    fill_commands_total: u64 = 0,
    text_commands_total: u64 = 0,
    frame_path_total_ns: u64 = 0,
    frame_path_last_ns: u64 = 0,
    present_last_ns: u64 = 0,

    pub fn recordSkipped(self: *FrameCounters) void {
        self.skipped_frames += 1;
    }

    pub fn recordPresent(self: *FrameCounters, frame_ns: u64, present_ns: u64) void {
        self.presented_frames += 1;
        self.frame_path_total_ns += frame_ns;
        self.frame_path_last_ns = frame_ns;
        self.present_last_ns = present_ns;
    }

    pub fn recordDrawList(self: *FrameCounters, stats: DrawStats) void {
        self.draw_commands_total += stats.commands;
        self.clear_commands_total += stats.clears;
        self.fill_commands_total += stats.fills;
        self.text_commands_total += stats.texts;
    }
};

/// Identity of a rasterized glyph in the future texture atlas. Font/glyph IDs
/// are assigned by the adapter once glyph-run resources are implemented.
pub const GlyphKey = struct {
    font_id: u32,
    glyph_id: u32,
    size_px: u16,
    variation_hash: u64,

    pub fn eql(self: GlyphKey, other: GlyphKey) bool {
        return self.font_id == other.font_id and self.glyph_id == other.glyph_id and
            self.size_px == other.size_px and self.variation_hash == other.variation_hash;
    }
};

pub const GlyphRect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    pub fn valid(self: GlyphRect) bool {
        return self.width > 0 and self.height > 0;
    }
};

pub const GlyphAtlasEntry = struct {
    key: GlyphKey,
    rect: GlyphRect,
    last_use_generation: u64 = 0,
};

pub const AtlasCounters = struct {
    lookups: u64 = 0,
    hits: u64 = 0,
    misses: u64 = 0,
    inserts: u64 = 0,
    updates: u64 = 0,
    evictions: u64 = 0,
};

pub const GlyphAtlasError = error{
    InvalidGlyphRect,
    AtlasCapacityRequired,
};

/// A bounded, adapter-owned glyph-atlas placement policy. This slice owns only
/// keys, rectangles, LRU generations, and counters; backend texture allocation
/// and upload are future W10 work.
pub const GlyphAtlas = struct {
    allocator: std.mem.Allocator,
    entries: []GlyphAtlasEntry,
    length: usize = 0,
    capacity: usize,
    generation: u64 = 0,
    counters: AtlasCounters = .{},

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !GlyphAtlas {
        if (capacity == 0) return GlyphAtlasError.AtlasCapacityRequired;
        const entries = try allocator.alloc(GlyphAtlasEntry, capacity);
        for (entries) |*entry| entry.* = .{
            .key = .{ .font_id = 0, .glyph_id = 0, .size_px = 0, .variation_hash = 0 },
            .rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
            .last_use_generation = 0,
        };
        return .{ .allocator = allocator, .entries = entries, .capacity = capacity };
    }

    pub fn deinit(self: *GlyphAtlas) void {
        self.allocator.free(self.entries);
    }

    pub fn beginFrame(self: *GlyphAtlas) void {
        self.generation += 1;
    }

    pub fn lookup(self: *GlyphAtlas, key: GlyphKey) ?GlyphRect {
        self.counters.lookups += 1;
        for (self.entries[0..self.length]) |*entry| {
            if (entry.key.eql(key)) {
                self.generation += 1;
                entry.last_use_generation = self.generation;
                self.counters.hits += 1;
                return entry.rect;
            }
        }
        self.counters.misses += 1;
        return null;
    }

    pub fn insert(self: *GlyphAtlas, key: GlyphKey, rect: GlyphRect) !void {
        if (!rect.valid()) return GlyphAtlasError.InvalidGlyphRect;
        for (self.entries[0..self.length]) |*entry| {
            if (entry.key.eql(key)) {
                self.generation += 1;
                entry.rect = rect;
                entry.last_use_generation = self.generation;
                self.counters.updates += 1;
                return;
            }
        }

        self.generation += 1;
        if (self.length < self.capacity) {
            self.entries[self.length] = .{
                .key = key,
                .rect = rect,
                .last_use_generation = self.generation,
            };
            self.length += 1;
            self.counters.inserts += 1;
            return;
        }

        var oldest_index: usize = 0;
        for (self.entries[1..], 1..) |entry, index| {
            if (entry.last_use_generation < self.entries[oldest_index].last_use_generation)
                oldest_index = index;
        }
        self.entries[oldest_index] = .{
            .key = key,
            .rect = rect,
            .last_use_generation = self.generation,
        };
        self.counters.evictions += 1;
        self.counters.inserts += 1;
    }
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

pub const LogicalRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

pub const DrawCommand = union(enum) {
    clear: Color,
    fill: struct { rect: LogicalRect, color: Color },
    text: struct { x: f32, y: f32, bytes: []const u8 },
};

pub const DrawStats = struct {
    commands: u64 = 0,
    clears: u64 = 0,
    fills: u64 = 0,
    texts: u64 = 0,
};

/// Backend-neutral immediate commands for the current smoke renderer. The
/// command list owns command storage, while text slices are borrowed and must
/// remain valid until execution completes. This avoids per-frame text copies;
/// the future glyph atlas replaces this debug text path.
pub const DrawList = struct {
    allocator: std.mem.Allocator,
    commands: std.ArrayList(DrawCommand) = .empty,
    logical_width: f32 = 0,
    logical_height: f32 = 0,
    stats: DrawStats = .{},

    pub fn deinit(self: *DrawList) void {
        self.commands.deinit(self.allocator);
    }

    pub fn reset(self: *DrawList) void {
        self.commands.clearRetainingCapacity();
        self.stats = .{};
    }

    pub fn setLogicalSize(self: *DrawList, width: f32, height: f32) void {
        self.logical_width = width;
        self.logical_height = height;
    }

    pub fn clear(self: *DrawList, color: Color) !void {
        try self.commands.append(self.allocator, .{ .clear = color });
        self.stats.commands += 1;
        self.stats.clears += 1;
    }

    pub fn fillRect(self: *DrawList, rect: LogicalRect, color: Color) !void {
        try self.commands.append(self.allocator, .{ .fill = .{ .rect = rect, .color = color } });
        self.stats.commands += 1;
        self.stats.fills += 1;
    }

    pub fn drawText(self: *DrawList, x: f32, y: f32, bytes: []const u8) !void {
        if (bytes.len == 0 or bytes.len > 120) return error.InvalidDrawText;
        for (bytes) |byte| {
            if (byte < 0x20 or byte > 0x7e) return error.InvalidDrawText;
        }
        try self.commands.append(self.allocator, .{ .text = .{ .x = x, .y = y, .bytes = bytes } });
        self.stats.commands += 1;
        self.stats.texts += 1;
    }
};

pub fn parseRequest(value: []const u8) ?Request {
    if (std.mem.eql(u8, value, "auto")) return .auto;
    if (std.mem.eql(u8, value, "software")) return .software;
    if (std.mem.eql(u8, value, "gpu")) return .gpu;
    if (value.len == 0) return null;
    return .{ .named = value };
}

pub fn parsePresentMode(value: []const u8) ?PresentMode {
    if (std.mem.eql(u8, value, "off")) return .off;
    if (std.mem.eql(u8, value, "on")) return .on;
    if (std.mem.eql(u8, value, "adaptive")) return .adaptive;
    return null;
}

pub fn requestName(request: Request) []const u8 {
    return switch (request) {
        .auto => "auto",
        .software => "software",
        .gpu => "gpu",
        .named => |name| name,
    };
}

pub fn candidates(request: Request) []const ?[]const u8 {
    return switch (request) {
        .auto => &.{null},
        .software => &.{"software"},
        // An explicit GPU request falls back to software so headless and
        // GPU-less machines retain a usable frontend. A named driver is an
        // operator override and deliberately fails if unavailable.
        .gpu => &.{ "gpu", "software" },
        .named => |name| &.{name},
    };
}

pub fn classify(name: []const u8) Tier {
    if (std.ascii.eqlIgnoreCase(name, "software")) return .software;
    if (std.ascii.eqlIgnoreCase(name, "gpu")) return .advanced;
    const gpu_names = [_][]const u8{
        "opengl",   "opengles2",  "opengles",   "metal", "vulkan",
        "direct3d", "direct3d11", "direct3d12",
    };
    for (gpu_names) |gpu_name| {
        if (std.ascii.eqlIgnoreCase(name, gpu_name)) return .basic;
    }
    return .basic;
}

pub fn vsyncNumber(mode: PresentMode) i32 {
    return switch (mode) {
        .off => 0,
        .adaptive => -1,
        .on => 1,
    };
}

test "parses renderer and present requests" {
    try std.testing.expectEqual(Request.auto, parseRequest("auto").?);
    try std.testing.expectEqual(Request.software, parseRequest("software").?);
    try std.testing.expectEqual(Request.gpu, parseRequest("gpu").?);
    try std.testing.expectEqualStrings("vulkan", parseRequest("vulkan").?.named);
    try std.testing.expectEqual(@as(?Request, null), parseRequest(""));
    try std.testing.expectEqualStrings("bogus-policy", parseRequest("bogus-policy").?.named);

    try std.testing.expectEqual(PresentMode.off, parsePresentMode("off").?);
    try std.testing.expectEqual(PresentMode.on, parsePresentMode("on").?);
    try std.testing.expectEqual(PresentMode.adaptive, parsePresentMode("adaptive").?);
    try std.testing.expectEqual(@as(?PresentMode, null), parsePresentMode("sometimes"));
}

test "gpu selection has explicit software fallback" {
    const auto_candidates = candidates(.auto);
    try std.testing.expectEqual(@as(usize, 1), auto_candidates.len);
    try std.testing.expectEqual(@as(?[]const u8, null), auto_candidates[0]);

    const gpu_candidates = candidates(.gpu);
    try std.testing.expectEqualStrings("gpu", gpu_candidates[0].?);
    try std.testing.expectEqualStrings("software", gpu_candidates[1].?);

    const named_candidates = candidates(.{ .named = "vulkan" });
    try std.testing.expectEqualStrings("vulkan", named_candidates[0].?);
}

test "classifies SDL renderer names into capability tiers" {
    try std.testing.expectEqual(Tier.software, classify("software"));
    try std.testing.expectEqual(Tier.advanced, classify("GPU"));
    try std.testing.expectEqual(Tier.basic, classify("opengl"));
    try std.testing.expectEqual(Tier.basic, classify("Direct3D12"));
    try std.testing.expectEqual(Tier.basic, classify("future-driver"));
}

test "frame gate presents dirty and resized frames only" {
    var gate: FrameGate = .{};
    try std.testing.expect(gate.shouldPresent(800, 600));
    try std.testing.expect(!gate.shouldPresent(800, 600));
    try std.testing.expect(!gate.shouldPresent(800, 600));

    gate.dirty = true;
    try std.testing.expect(gate.shouldPresent(800, 600));
    try std.testing.expect(!gate.shouldPresent(800, 600));
    try std.testing.expect(gate.shouldPresent(960, 600));
    try std.testing.expect(!gate.shouldPresent(960, 600));
}

test "frame counters separate presents from skipped polls" {
    var counters: FrameCounters = .{};
    counters.recordPresent(1_250, 2_500);
    counters.recordSkipped();
    counters.recordSkipped();
    counters.recordPresent(750, 4_000);

    try std.testing.expectEqual(@as(u64, 2), counters.presented_frames);
    try std.testing.expectEqual(@as(u64, 2), counters.skipped_frames);
    try std.testing.expectEqual(@as(u64, 2_000), counters.frame_path_total_ns);
    try std.testing.expectEqual(@as(u64, 750), counters.frame_path_last_ns);
    try std.testing.expectEqual(@as(u64, 4_000), counters.present_last_ns);

    counters.recordDrawList(.{ .commands = 3, .clears = 1, .fills = 1, .texts = 1 });
    try std.testing.expectEqual(@as(u64, 3), counters.draw_commands_total);
    try std.testing.expectEqual(@as(u64, 1), counters.clear_commands_total);
    try std.testing.expectEqual(@as(u64, 1), counters.fill_commands_total);
    try std.testing.expectEqual(@as(u64, 1), counters.text_commands_total);
}

test "glyph atlas inserts looks up and evicts least recent use" {
    var atlas = try GlyphAtlas.init(std.testing.allocator, 2);
    defer atlas.deinit();
    const first: GlyphKey = .{ .font_id = 1, .glyph_id = 10, .size_px = 14, .variation_hash = 1 };
    const second: GlyphKey = .{ .font_id = 1, .glyph_id = 11, .size_px = 14, .variation_hash = 1 };
    const third: GlyphKey = .{ .font_id = 1, .glyph_id = 12, .size_px = 14, .variation_hash = 1 };

    atlas.beginFrame();
    try std.testing.expect(atlas.lookup(first) == null);
    try atlas.insert(first, .{ .x = 0, .y = 0, .width = 8, .height = 12 });
    atlas.beginFrame();
    try std.testing.expectEqual(GlyphRect{ .x = 0, .y = 0, .width = 8, .height = 12 }, atlas.lookup(first).?);

    atlas.beginFrame();
    try atlas.insert(second, .{ .x = 8, .y = 0, .width = 8, .height = 12 });
    try atlas.insert(third, .{ .x = 16, .y = 0, .width = 8, .height = 12 });

    try std.testing.expectEqual(@as(u64, 1), atlas.counters.evictions);
    try std.testing.expect(atlas.lookup(first) == null);
    try std.testing.expect(atlas.lookup(second) != null);
    try std.testing.expect(atlas.lookup(third) != null);
    try std.testing.expectEqual(@as(u64, 5), atlas.counters.lookups);
    try std.testing.expectEqual(@as(u64, 3), atlas.counters.hits);
    try std.testing.expectEqual(@as(u64, 2), atlas.counters.misses);
}

test "glyph atlas rejects zero capacity and invalid rectangles" {
    try std.testing.expectError(GlyphAtlasError.AtlasCapacityRequired, GlyphAtlas.init(std.testing.allocator, 0));
    var atlas = try GlyphAtlas.init(std.testing.allocator, 1);
    defer atlas.deinit();
    const key: GlyphKey = .{ .font_id = 1, .glyph_id = 1, .size_px = 10, .variation_hash = 0 };
    try std.testing.expectError(GlyphAtlasError.InvalidGlyphRect, atlas.insert(key, .{ .x = 0, .y = 0, .width = 0, .height = 8 }));
}

test "glyph atlas updates existing key without eviction" {
    var atlas = try GlyphAtlas.init(std.testing.allocator, 2);
    defer atlas.deinit();
    const key: GlyphKey = .{ .font_id = 3, .glyph_id = 30, .size_px = 16, .variation_hash = 9 };
    try atlas.insert(key, .{ .x = 1, .y = 2, .width = 8, .height = 12 });
    try atlas.insert(key, .{ .x = 3, .y = 4, .width = 9, .height = 13 });

    try std.testing.expectEqual(@as(usize, 1), atlas.length);
    try std.testing.expectEqual(GlyphRect{ .x = 3, .y = 4, .width = 9, .height = 13 }, atlas.lookup(key).?);
    try std.testing.expectEqual(@as(u64, 1), atlas.counters.inserts);
    try std.testing.expectEqual(@as(u64, 1), atlas.counters.updates);
    try std.testing.expectEqual(@as(u64, 0), atlas.counters.evictions);
}

test "draw list records and resets backend-neutral commands" {
    var list: DrawList = .{ .allocator = std.testing.allocator };
    defer list.deinit();
    list.setLogicalSize(100, 80);
    try list.clear(.{ .r = 0x18, .g = 0x20, .b = 0x2a });
    try list.fillRect(.{ .x = 1, .y = 2, .width = 3, .height = 4 }, .{ .r = 1, .g = 2, .b = 3 });
    try list.drawText(4, 5, "Emacs");

    try std.testing.expectEqual(@as(usize, 3), list.commands.items.len);
    try std.testing.expectEqual(@as(u64, 3), list.stats.commands);
    try std.testing.expectEqual(@as(u64, 1), list.stats.clears);
    try std.testing.expectEqual(@as(u64, 1), list.stats.fills);
    try std.testing.expectEqual(@as(u64, 1), list.stats.texts);
    try std.testing.expectEqualStrings("Emacs", list.commands.items[2].text.bytes);

    list.reset();
    try std.testing.expectEqual(@as(usize, 0), list.commands.items.len);
    try std.testing.expectEqual(@as(u64, 0), list.stats.commands);
    try std.testing.expectEqual(@as(f32, 100), list.logical_width);
}

test "draw list rejects absent oversized and non-ASCII text" {
    var list: DrawList = .{ .allocator = std.testing.allocator };
    defer list.deinit();
    try std.testing.expectError(error.InvalidDrawText, list.drawText(0, 0, ""));
    try std.testing.expectError(error.InvalidDrawText, list.drawText(0, 0, "CJK 字"));
    const oversized = "a" ** 121;
    try std.testing.expectError(error.InvalidDrawText, list.drawText(0, 0, oversized[0..]));
}
