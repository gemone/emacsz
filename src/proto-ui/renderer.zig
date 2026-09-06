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
pub const DamageKind = enum {
    none,
    cursor,
    text,
    region,
    viewport,
    initial,
};

pub const DamageDecision = struct {
    kind: DamageKind,
    old_cursor: ?CursorObservation = null,
    new_cursor: ?CursorObservation = null,
    clip: ?LogicalRect = null,
};

pub const DamageClip = union(enum) {
    full,
    rect: LogicalRect,
};

pub const CursorSize = struct { width: i32, height: i32 };

/// Returns the smallest rectangle the debug renderer can draw for a cursor.
pub fn renderedCursorSize(width: i32, height: i32) CursorSize {
    return .{ .width = @max(2, width), .height = @max(2, height) };
}

/// Returns the conservative logical union of the old and new cursor rectangles
/// for a cursor-only change. Different windows or a missing endpoint require
/// full-frame fallback.
pub fn cursorDamageClip(
    old: ?CursorObservation,
    new: ?CursorObservation,
    frame_width: i32,
    frame_height: i32,
) ?LogicalRect {
    const old_cursor = old orelse return null;
    const new_cursor = new orelse return null;
    if (old_cursor.window_id != new_cursor.window_id) return null;
    const old_size = renderedCursorSize(old_cursor.width, old_cursor.height);
    const new_size = renderedCursorSize(new_cursor.width, new_cursor.height);
    const old_left: i64 = @as(i64, old_cursor.owner_x) + old_cursor.x;
    const old_top: i64 = @as(i64, old_cursor.owner_y) + old_cursor.y;
    const old_right: i64 = old_left + old_size.width;
    const old_bottom: i64 = old_top + old_size.height;
    const new_left: i64 = @as(i64, new_cursor.owner_x) + new_cursor.x;
    const new_top: i64 = @as(i64, new_cursor.owner_y) + new_cursor.y;
    const new_right: i64 = new_left + new_size.width;
    const new_bottom: i64 = new_top + new_size.height;

    const left_i64: i64 = @max(0, @min(old_left, new_left) - 1);
    const top_i64: i64 = @max(0, @min(old_top, new_top) - 1);
    const right_i64: i64 = @min(@as(i64, frame_width), @max(old_right, new_right) + 1);
    const bottom_i64: i64 = @min(@as(i64, frame_height), @max(old_bottom, new_bottom) + 1);
    if (left_i64 >= right_i64 or top_i64 >= bottom_i64) return null;
    if (left_i64 > std.math.maxInt(i32) or right_i64 > std.math.maxInt(i32) or
        top_i64 > std.math.maxInt(i32) or bottom_i64 > std.math.maxInt(i32)) return null;
    return .{
        .x = @floatFromInt(left_i64),
        .y = @floatFromInt(top_i64),
        .width = @floatFromInt(right_i64 - left_i64),
        .height = @floatFromInt(bottom_i64 - top_i64),
    };
}

pub const max_clipped_text_lines: usize = 32;

pub const TextLineRect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const TextLineObservation = struct {
    row_index: u32 = 0,
    hash: u64 = 0,
    rect: TextLineRect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
};

fn clipFromLogicalBounds(
    left: i64,
    top: i64,
    right: i64,
    bottom: i64,
    frame_width: i32,
    frame_height: i32,
) ?LogicalRect {
    const left_i64: i64 = @max(0, left);
    const top_i64: i64 = @max(0, top);
    const right_i64: i64 = @min(@as(i64, frame_width), right);
    const bottom_i64: i64 = @min(@as(i64, frame_height), bottom);
    if (left_i64 >= right_i64 or top_i64 >= bottom_i64) return null;
    if (left_i64 > std.math.maxInt(i32) or right_i64 > std.math.maxInt(i32) or
        top_i64 > std.math.maxInt(i32) or bottom_i64 > std.math.maxInt(i32)) return null;
    return .{
        .x = @floatFromInt(left_i64),
        .y = @floatFromInt(top_i64),
        .width = @floatFromInt(right_i64 - left_i64),
        .height = @floatFromInt(bottom_i64 - top_i64),
    };
}

fn addTextLineRect(clip: *?LogicalRect, rect: TextLineRect) void {
    if (rect.width <= 0 or rect.height <= 0) return;
    const right: i64 = @as(i64, rect.x) + rect.width;
    const bottom: i64 = @as(i64, rect.y) + rect.height;
    if (clip.*) |current| {
        const rect_x: f32 = @floatFromInt(rect.x);
        const rect_y: f32 = @floatFromInt(rect.y);
        const right_f: f32 = @floatFromInt(right);
        const bottom_f: f32 = @floatFromInt(bottom);
        clip.* = .{
            .x = @min(current.x, rect_x),
            .y = @min(current.y, rect_y),
            .width = @max(current.x + current.width, right_f) - @min(current.x, rect_x),
            .height = @max(current.y + current.height, bottom_f) - @min(current.y, rect_y),
        };
    } else {
        clip.* = .{
            .x = @floatFromInt(rect.x),
            .y = @floatFromInt(rect.y),
            .width = @floatFromInt(right),
            .height = @floatFromInt(bottom),
        };
    }
}

fn textLineByRow(
    observation: SceneDamageObservation,
    row_index: u32,
) ?TextLineObservation {
    for (observation.text_lines[0..observation.bounded_text_line_count]) |line| {
        if (line.row_index == row_index) return line;
    }
    return null;
}

/// Returns a conservative union of changed text-line rectangles and both cursor
/// endpoints. Incomplete observations, exact-representation failures, or no
/// bounded result return null so the caller takes a full-frame fallback.
pub fn textDamageClip(
    old: SceneDamageObservation,
    new: SceneDamageObservation,
    frame_width: i32,
    frame_height: i32,
) ?LogicalRect {
    if (!old.text_lines_complete or !new.text_lines_complete or
        old.bounded_text_line_count != old.text_line_count or
        new.bounded_text_line_count != new.text_line_count or
        frame_width <= 0 or frame_height <= 0) return null;

    var union_rect: ?LogicalRect = null;
    var changed = false;
    for (old.text_lines[0..old.bounded_text_line_count]) |line| {
        const replacement = textLineByRow(new, line.row_index);
        if (replacement == null or replacement.?.hash != line.hash) {
            changed = true;
            addTextLineRect(&union_rect, line.rect);
        }
    }
    for (new.text_lines[0..new.bounded_text_line_count]) |line| {
        const previous = textLineByRow(old, line.row_index);
        if (previous == null or previous.?.hash != line.hash) {
            changed = true;
            addTextLineRect(&union_rect, line.rect);
        }
    }
    if (!changed) return null;
    if (old.cursor != null or new.cursor != null) {
        if (!std.meta.eql(old.cursor, new.cursor)) {
            // The cursor helper owns its rendered-size expansion and one-pixel
            // margin. Compose after the line union so both rectangles are kept.
            const cursor_union = cursorDamageClip(old.cursor, new.cursor, frame_width, frame_height) orelse return null;
            addTextLineRect(&union_rect, .{
                .x = @intFromFloat(cursor_union.x),
                .y = @intFromFloat(cursor_union.y),
                .width = @intFromFloat(cursor_union.width),
                .height = @intFromFloat(cursor_union.height),
            });
        }
    }
    const clip = union_rect orelse return null;
    return clipFromLogicalBounds(
        @intFromFloat(clip.x - 1),
        @intFromFloat(clip.y - 1),
        @intFromFloat(clip.x + clip.width + 1),
        @intFromFloat(clip.y + clip.height + 1),
        frame_width,
        frame_height,
    );
}

pub const SceneDamageObservation = struct {
    frame_width: i32 = 0,
    frame_height: i32 = 0,
    viewport_start_line: i32,
    viewport_line_count: i32,
    cursor: ?CursorObservation,
    text_hash: [32]u8,
    text_line_count: usize,
    structure_hash: [32]u8,
    structure_object_count: usize,
    text_lines: [max_clipped_text_lines]TextLineObservation = [_]TextLineObservation{.{}} ** max_clipped_text_lines,
    bounded_text_line_count: usize = 0,
    text_lines_complete: bool = true,
};

pub const CursorObservation = struct {
    window_id: u64,
    owner_x: i32,
    owner_y: i32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    kind: u8,
    visible: bool,
    active: bool,
};

/// Conservative W10c damage classification. The first observation and any
/// viewport change fall back to full-frame work; only unchanged states are
/// omitted and cursor-only changes are tagged for a future clipped path.
pub const FrameGate = struct {
    dirty: bool = true,
    width: i32 = 0,
    height: i32 = 0,
    previous: ?SceneDamageObservation = null,

    pub fn shouldPresent(self: *FrameGate, width: i32, height: i32) bool {
        const needed = self.dirty or width != self.width or height != self.height;
        self.dirty = false;
        self.width = width;
        self.height = height;
        return needed;
    }

    pub fn observeScene(self: *FrameGate, observation: SceneDamageObservation) DamageDecision {
        const previous = self.previous;
        self.previous = observation;
        if (previous) |old| {
            const viewport_changed = old.viewport_start_line != observation.viewport_start_line or
                old.viewport_line_count != observation.viewport_line_count;
            const structure_changed = !std.mem.eql(u8, &old.structure_hash, &observation.structure_hash) or
                old.structure_object_count != observation.structure_object_count;
            const aggregate_changed = !std.mem.eql(u8, &old.text_hash, &observation.text_hash) or
                old.text_line_count != observation.text_line_count;
            if (viewport_changed or structure_changed)
                return .{
                    .kind = .viewport,
                    .old_cursor = old.cursor,
                    .new_cursor = observation.cursor,
                };
            if (!std.meta.eql(old.cursor, observation.cursor)) {
                const text_clip = textDamageClip(old, observation, observation.frame_width, observation.frame_height);
                if (aggregate_changed and text_clip == null)
                    return .{
                        .kind = .viewport,
                        .old_cursor = old.cursor,
                        .new_cursor = observation.cursor,
                    };
                if (aggregate_changed)
                    return .{
                        .kind = .region,
                        .old_cursor = old.cursor,
                        .new_cursor = observation.cursor,
                        .clip = text_clip,
                    };
                const clip = cursorDamageClip(
                    old.cursor,
                    observation.cursor,
                    observation.frame_width,
                    observation.frame_height,
                );
                return .{
                    .kind = .cursor,
                    .old_cursor = old.cursor,
                    .new_cursor = observation.cursor,
                    .clip = clip,
                };
            }
            const text_clip = textDamageClip(old, observation, observation.frame_width, observation.frame_height);
            if (aggregate_changed and text_clip == null)
                return .{
                    .kind = .viewport,
                    .old_cursor = old.cursor,
                    .new_cursor = observation.cursor,
                };
            if (aggregate_changed)
                return .{
                    .kind = .text,
                    .old_cursor = old.cursor,
                    .new_cursor = observation.cursor,
                    .clip = text_clip,
                };
            return .{
                .kind = .none,
                .old_cursor = old.cursor,
                .new_cursor = observation.cursor,
            };
        }
        return .{
            .kind = .initial,
            .new_cursor = observation.cursor,
        };
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
    initial_damage_frames: u64 = 0,
    cursor_damage_frames: u64 = 0,
    text_damage_frames: u64 = 0,
    region_damage_frames: u64 = 0,
    viewport_damage_frames: u64 = 0,
    unchanged_frames: u64 = 0,
    cursor_clipped_frames: u64 = 0,
    cursor_full_fallback_frames: u64 = 0,
    text_clipped_frames: u64 = 0,
    text_full_fallback_frames: u64 = 0,
    region_clipped_frames: u64 = 0,
    region_full_fallback_frames: u64 = 0,
    clipped_draw_commands_total: u64 = 0,

    pub fn recordClip(self: *FrameCounters, kind: DamageKind, clipped: bool, submitted_commands: u64) void {
        switch (kind) {
            .cursor => self.recordCursorClip(clipped, submitted_commands),
            .text => {
                if (clipped) {
                    self.text_clipped_frames += 1;
                    self.clipped_draw_commands_total += submitted_commands;
                } else self.text_full_fallback_frames += 1;
            },
            .region => {
                if (clipped) {
                    self.region_clipped_frames += 1;
                    self.clipped_draw_commands_total += submitted_commands;
                } else self.region_full_fallback_frames += 1;
            },
            else => {},
        }
    }

    pub fn recordCursorClip(self: *FrameCounters, clipped: bool, submitted_commands: u64) void {
        if (clipped) {
            self.cursor_clipped_frames += 1;
            self.clipped_draw_commands_total += submitted_commands;
        } else {
            self.cursor_full_fallback_frames += 1;
        }
    }

    pub fn recordDamage(self: *FrameCounters, kind: DamageKind) void {
        switch (kind) {
            .initial => self.initial_damage_frames += 1,
            .cursor => self.cursor_damage_frames += 1,
            .text => self.text_damage_frames += 1,
            .region => self.region_damage_frames += 1,
            .viewport => self.viewport_damage_frames += 1,
            .none => self.unchanged_frames += 1,
        }
    }

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

test "cursor-only damage produces a bounded clip rectangle" {
    const old: CursorObservation = .{ .window_id = 1, .owner_x = 0, .owner_y = 0, .x = 8, .y = 0, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true };
    const new: CursorObservation = .{ .window_id = 1, .owner_x = 0, .owner_y = 0, .x = 16, .y = 8, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true };
    const clip = (cursorDamageClip(old, new, 120, 80) orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(@as(f32, 7), clip.x);
    try std.testing.expectEqual(@as(f32, 0), clip.y);
    try std.testing.expectEqual(@as(f32, 12), clip.width);
    try std.testing.expectEqual(@as(f32, 17), clip.height);
    try std.testing.expect(cursorDamageClip(null, new, 120, 80) == null);
    try std.testing.expect(cursorDamageClip(old, .{ .window_id = 2, .owner_x = 0, .owner_y = 0, .x = 16, .y = 8, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true }, 120, 80) == null);
    try std.testing.expect(cursorDamageClip(old, new, 1, 1) == null);

    const degenerate: CursorObservation = .{ .window_id = 1, .owner_x = 10, .owner_y = 10, .x = 20, .y = 20, .width = 0, .height = 1, .kind = 1, .visible = true, .active = true };
    const degenerate_clip = (cursorDamageClip(degenerate, degenerate, 120, 80) orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(@as(f32, 29), degenerate_clip.x);
    try std.testing.expectEqual(@as(f32, 29), degenerate_clip.y);
    try std.testing.expectEqual(@as(f32, 4), degenerate_clip.width);
    try std.testing.expectEqual(@as(f32, 4), degenerate_clip.height);
}

test "frame gate classifies text-only changes as viewport damage" {
    var gate: FrameGate = .{};
    const cursor: CursorObservation = .{ .window_id = 1, .owner_x = 0, .owner_y = 0, .x = 8, .y = 0, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true };
    const first: SceneDamageObservation = .{
        .viewport_start_line = 1,
        .viewport_line_count = 2,
        .cursor = cursor,
        .text_hash = [_]u8{1} ** 32,
        .text_line_count = 2,
        .structure_hash = [_]u8{3} ** 32,
        .structure_object_count = 2,
    };
    const second: SceneDamageObservation = .{
        .viewport_start_line = 1,
        .viewport_line_count = 2,
        .cursor = cursor,
        .text_hash = [_]u8{2} ** 32,
        .text_line_count = 2,
        .structure_hash = [_]u8{3} ** 32,
        .structure_object_count = 2,
    };
    _ = gate.observeScene(first);
    try std.testing.expectEqual(DamageKind.viewport, gate.observeScene(second).kind);
}

test "text damage clips changed bounded line observations" {
    const cursor: CursorObservation = .{ .window_id = 1, .owner_x = 0, .owner_y = 0, .x = 8, .y = 0, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true };
    var old: SceneDamageObservation = .{
        .frame_width = 120,
        .frame_height = 80,
        .viewport_start_line = 1,
        .viewport_line_count = 2,
        .cursor = cursor,
        .text_hash = [_]u8{1} ** 32,
        .text_line_count = 2,
        .structure_hash = [_]u8{3} ** 32,
        .structure_object_count = 2,
    };
    var new = old;
    old.text_lines[0] = .{ .row_index = 0, .hash = 1, .rect = .{ .x = 0, .y = 0, .width = 100, .height = 20 } };
    old.text_lines[1] = .{ .row_index = 1, .hash = 2, .rect = .{ .x = 0, .y = 20, .width = 100, .height = 20 } };
    old.bounded_text_line_count = 2;
    new = old;
    new.text_hash = [_]u8{2} ** 32;
    new.text_lines[0].hash = 3;

    const clip = (textDamageClip(old, new, 120, 80) orelse return error.TestUnexpectedResult);
    try std.testing.expectEqual(@as(f32, 0), clip.x);
    try std.testing.expectEqual(@as(f32, 0), clip.y);
    try std.testing.expectEqual(@as(f32, 101), clip.width);
    try std.testing.expectEqual(@as(f32, 21), clip.height);
}

test "frame gate classifies changed text and cursor as bounded region damage" {
    var gate: FrameGate = .{};
    _ = gate.shouldPresent(120, 80);
    const old_cursor: CursorObservation = .{ .window_id = 1, .owner_x = 0, .owner_y = 0, .x = 8, .y = 0, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true };
    const new_cursor: CursorObservation = .{ .window_id = 1, .owner_x = 0, .owner_y = 0, .x = 16, .y = 0, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true };
    var old: SceneDamageObservation = .{
        .frame_width = 120,
        .frame_height = 80,
        .viewport_start_line = 1,
        .viewport_line_count = 2,
        .cursor = old_cursor,
        .text_hash = [_]u8{1} ** 32,
        .text_line_count = 1,
        .structure_hash = [_]u8{3} ** 32,
        .structure_object_count = 2,
    };
    old.text_lines[0] = .{
        .row_index = 0,
        .hash = 1,
        .rect = .{ .x = 0, .y = 0, .width = 80, .height = 20 },
    };
    old.bounded_text_line_count = 1;
    var new = old;
    new.cursor = new_cursor;
    new.text_hash = [_]u8{2} ** 32;
    new.text_lines[0] = .{
        .row_index = 0,
        .hash = 2,
        .rect = .{ .x = 0, .y = 0, .width = 80, .height = 20 },
    };
    _ = gate.observeScene(old);
    const decision = gate.observeScene(new);
    try std.testing.expectEqual(DamageKind.region, decision.kind);
    try std.testing.expect(decision.clip != null);
}

test "frame gate classifies structure-only changes as viewport damage" {
    var gate: FrameGate = .{};
    const cursor: CursorObservation = .{ .window_id = 1, .owner_x = 0, .owner_y = 0, .x = 8, .y = 0, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true };
    const first: SceneDamageObservation = .{
        .viewport_start_line = 1,
        .viewport_line_count = 2,
        .cursor = cursor,
        .text_hash = [_]u8{1} ** 32,
        .text_line_count = 2,
        .structure_hash = [_]u8{3} ** 32,
        .structure_object_count = 2,
    };
    const second: SceneDamageObservation = .{
        .viewport_start_line = 1,
        .viewport_line_count = 2,
        .cursor = cursor,
        .text_hash = first.text_hash,
        .text_line_count = 2,
        .structure_hash = [_]u8{4} ** 32,
        .structure_object_count = 2,
    };
    _ = gate.observeScene(first);
    try std.testing.expectEqual(DamageKind.viewport, gate.observeScene(second).kind);
}

test "frame gate classifies initial cursor and viewport damage" {
    var gate: FrameGate = .{};
    var counters: FrameCounters = .{};

    const base: SceneDamageObservation = .{
        .viewport_start_line = 1,
        .viewport_line_count = 15,
        .cursor = .{ .window_id = 1, .owner_x = 0, .owner_y = 0, .x = 8, .y = 0, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true },
        .text_hash = [_]u8{0} ** 32,
        .text_line_count = 15,
        .structure_hash = [_]u8{0} ** 32,
        .structure_object_count = 15,
    };
    const first = gate.observeScene(base);
    try std.testing.expectEqual(DamageKind.initial, first.kind);
    counters.recordDamage(first.kind);

    const unchanged = gate.observeScene(base);
    try std.testing.expectEqual(DamageKind.none, unchanged.kind);
    counters.recordDamage(unchanged.kind);

    const moved = gate.observeScene(.{
        .viewport_start_line = 1,
        .viewport_line_count = 15,
        .cursor = .{ .window_id = 1, .owner_x = 0, .owner_y = 0, .x = 16, .y = 8, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true },
        .text_hash = [_]u8{0} ** 32,
        .text_line_count = 15,
        .structure_hash = [_]u8{0} ** 32,
        .structure_object_count = 15,
    });
    try std.testing.expectEqual(DamageKind.cursor, moved.kind);
    counters.recordDamage(moved.kind);

    const scrolled = gate.observeScene(.{
        .viewport_start_line = 2,
        .viewport_line_count = 15,
        .cursor = .{ .window_id = 1, .owner_x = 0, .owner_y = 0, .x = 16, .y = 8, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true },
        .text_hash = [_]u8{1} ** 32,
        .text_line_count = 15,
        .structure_hash = [_]u8{0} ** 32,
        .structure_object_count = 15,
    });
    try std.testing.expectEqual(DamageKind.viewport, scrolled.kind);
    counters.recordDamage(scrolled.kind);

    try std.testing.expectEqual(@as(u64, 1), counters.initial_damage_frames);
    try std.testing.expectEqual(@as(u64, 1), counters.cursor_damage_frames);
    try std.testing.expectEqual(@as(u64, 1), counters.viewport_damage_frames);
    try std.testing.expectEqual(@as(u64, 1), counters.unchanged_frames);
}

test "frame counters record cursor clipped and fallback frames" {
    var counters: FrameCounters = .{};
    counters.recordCursorClip(true, 93);
    counters.recordCursorClip(false, 0);
    try std.testing.expectEqual(@as(u64, 1), counters.cursor_clipped_frames);
    try std.testing.expectEqual(@as(u64, 1), counters.cursor_full_fallback_frames);
    try std.testing.expectEqual(@as(u64, 93), counters.clipped_draw_commands_total);
}
