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

pub const I32Rect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

/// Unions protocol damage rectangles and clamps them to the logical frame.
/// An empty or wholly invalid array yields no clip; callers must fall back.
pub fn explicitDamageClip(
    logical_width: i32,
    logical_height: i32,
    rects: []const I32Rect,
) ?LogicalRect {
    if (logical_width <= 0 or logical_height <= 0) return null;
    var union_rect: ?LogicalRect = null;
    for (rects) |rect| {
        if (rect.width <= 0 or rect.height <= 0) continue;
        const left_i64: i64 = @max(0, rect.x);
        const top_i64: i64 = @max(0, rect.y);
        const right_i64: i64 = @min(@as(i64, logical_width), @as(i64, rect.x) + rect.width);
        const bottom_i64: i64 = @min(@as(i64, logical_height), @as(i64, rect.y) + rect.height);
        if (left_i64 >= right_i64 or top_i64 >= bottom_i64) continue;

        const left: f32 = @floatFromInt(left_i64);
        const top: f32 = @floatFromInt(top_i64);
        const right: f32 = @floatFromInt(right_i64);
        const bottom: f32 = @floatFromInt(bottom_i64);
        if (union_rect) |current| {
            union_rect = .{
                .x = @min(current.x, left),
                .y = @min(current.y, top),
                .width = @max(current.x + current.width, right) - @min(current.x, left),
                .height = @max(current.y + current.height, bottom) - @min(current.y, top),
            };
        } else union_rect = .{ .x = left, .y = top, .width = right - left, .height = bottom - top };
    }
    return union_rect;
}

pub const ScrollCopyPlan = struct {
    source_y: i32,
    destination_y: i32,
    width: i32,
    height: i32,
    overlap: bool,
    estimated_upload_bytes: u64,
};

pub fn planScrollCopy(
    window_width: i32,
    window_height: i32,
    source_y: i32,
    destination_y: i32,
    width: i32,
    height: i32,
) ?ScrollCopyPlan {
    if (window_width <= 0 or window_height <= 0 or
        width <= 0 or height <= 0 or width != window_width or
        source_y < 0 or destination_y < 0 or
        @as(i64, source_y) + height > window_height or
        @as(i64, destination_y) + height > window_height)
        return null;
    const overlap = source_y != destination_y and
        source_y < destination_y + height and
        destination_y < source_y + height;
    const pixels: u64 = @as(u64, @intCast(width)) * @as(u64, @intCast(height));
    return .{
        .source_y = source_y,
        .destination_y = destination_y,
        .width = width,
        .height = height,
        .overlap = overlap,
        .estimated_upload_bytes = pixels * 4,
    };
}

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
pub const CursorEndpoints = struct { old: CursorObservation, new: CursorObservation };
pub const max_observed_cursors: usize = 16;

pub const TextLineRect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const TextLineObservation = struct {
    window_id: u64 = 0,
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
    window_id: u64,
    row_index: u32,
) ?TextLineObservation {
    for (observation.text_lines[0..observation.bounded_text_line_count]) |line| {
        if (line.window_id == window_id and line.row_index == row_index) return line;
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
        const replacement = textLineByRow(new, line.window_id, line.row_index);
        if (replacement == null or replacement.?.hash != line.hash) {
            changed = true;
            addTextLineRect(&union_rect, line.rect);
        }
    }
    for (new.text_lines[0..new.bounded_text_line_count]) |line| {
        const previous = textLineByRow(old, line.window_id, line.row_index);
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
    cursor_hash: u64 = 0,
    cursor_count: usize = 0,
    text_hash: [32]u8,
    mode_line_hash: u64 = 0,
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
                old.text_line_count != observation.text_line_count or
                old.mode_line_hash != observation.mode_line_hash;
            if (viewport_changed or structure_changed)
                return .{
                    .kind = .viewport,
                    .old_cursor = old.cursor,
                    .new_cursor = observation.cursor,
                };
            if (old.mode_line_hash != observation.mode_line_hash)
                return .{
                    .kind = .viewport,
                    .old_cursor = old.cursor,
                    .new_cursor = observation.cursor,
                };
            const cursor_changed = old.cursor_count != observation.cursor_count or
                old.cursor_hash != observation.cursor_hash or
                !std.meta.eql(old.cursor, observation.cursor);
            if (cursor_changed) {
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
                if (old.cursor_count != observation.cursor_count or
                    old.cursor_hash != observation.cursor_hash or
                    observation.cursor_count > 1 or aggregate_changed)
                    return .{
                        .kind = .viewport,
                        .old_cursor = old.cursor,
                        .new_cursor = observation.cursor,
                    };
                const endpoints: CursorEndpoints = .{ .old = old.cursor.?, .new = observation.cursor.? };
                const clip = cursorDamageClip(
                    endpoints.old,
                    endpoints.new,
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
            const mode_line_changed = old.mode_line_hash != observation.mode_line_hash;
            if (mode_line_changed)
                return .{
                    .kind = .viewport,
                    .old_cursor = old.cursor,
                    .new_cursor = observation.cursor,
                };
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
    unicode_text_commands_total: u64 = 0,
    atlas_glyphs_total: u64 = 0,
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
    scroll_copies: u64 = 0,
    scroll_copy_commands: u64 = 0,
    scroll_copy_planned_bytes: u64 = 0,
    explicit_damage_frames: u64 = 0,
    explicit_clipped_frames: u64 = 0,
    explicit_full_fallback_frames: u64 = 0,
    explicit_submitted_commands: u64 = 0,
    explicit_skipped_commands: u64 = 0,
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

    pub fn recordScrollCopy(self: *FrameCounters, planned_bytes: u64, submitted_commands: u64) void {
        self.scroll_copies += 1;
        self.scroll_copy_planned_bytes += planned_bytes;
        self.scroll_copy_commands += submitted_commands;
    }

    pub fn recordExplicitDamage(
        self: *FrameCounters,
        clipped: bool,
        submitted_commands: u64,
        skipped_commands: u64,
    ) void {
        self.explicit_damage_frames += 1;
        self.explicit_submitted_commands += submitted_commands;
        self.explicit_skipped_commands += skipped_commands;
        if (clipped) {
            self.explicit_clipped_frames += 1;
            self.clipped_draw_commands_total += submitted_commands;
        } else self.explicit_full_fallback_frames += 1;
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
        self.unicode_text_commands_total += stats.unicode_texts;
        self.atlas_glyphs_total += stats.atlas_glyphs;
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
    text: struct { x: f32, y: f32, color: ?Color = null, bytes: []const u8 },
    unicode_text: struct { x: f32, y: f32, color: Color, bytes: []const u8 },
    image: struct { rect: LogicalRect, pixels: []const u8, width: u32, height: u32 },
    image_region: struct {
        destination: LogicalRect,
        source: LogicalRect,
        pixels: []const u8,
        source_width: u32,
        source_height: u32,
        cache_key: u64,
        cache_revision: u32,
        atlas_id: u32,
        page_index: u16,
        generation: u32,
    },
};

pub const DrawStats = struct {
    commands: u64 = 0,
    examined_commands: u64 = 0,
    skipped_commands: u64 = 0,
    clears: u64 = 0,
    fills: u64 = 0,
    texts: u64 = 0,
    unicode_texts: u64 = 0,
    images: u64 = 0,
    atlas_glyphs: u64 = 0,
};

pub const LatencySummary = struct {
    p50_ns: u64,
    p95_ns: u64,
    p99_ns: u64,
    mean_ns: f64,
    fps: f64,
};

/// Percentiles use nearest-rank on a copied, sorted sample. The input is left
/// unchanged and timing-only data never mutates renderer state.
pub fn summarizeLatencies(samples: []const u64) !LatencySummary {
    if (samples.len == 0) return error.EmptyLatencySample;
    for (samples) |sample| {
        if (sample == 0) return error.InvalidLatencySample;
    }
    const sorted = try std.heap.smp_allocator.dupe(u64, samples);
    defer std.heap.smp_allocator.free(sorted);
    std.mem.sort(u64, sorted, {}, std.sort.asc(u64));
    const percentile = struct {
        fn value(data: []const u64, percent: u64) u64 {
            // Nearest rank: ceil(N * percent / 100), converted to a zero-based
            // index. The @min guard makes p95/p99 exact for N = 1.
            const index = @min(
                data.len - 1,
                (data.len * percent + 99) / 100 - 1,
            );
            return data[index];
        }
    }.value;
    var total: u128 = 0;
    for (sorted) |sample| total += sample;
    const mean: f64 = @floatFromInt(total);
    const count: f64 = @floatFromInt(sorted.len);
    const mean_ns = mean / count;
    return .{
        .p50_ns = percentile(sorted, 50),
        .p95_ns = percentile(sorted, 95),
        .p99_ns = percentile(sorted, 99),
        .mean_ns = mean_ns,
        .fps = if (mean_ns > 0) 1_000_000_000.0 / mean_ns else 0,
    };
}

pub const FaceLineStyle = enum(u8) {
    unspecified = 0,
    off = 1,
    single = 2,
    color = 3,
};

pub const FaceBoxStyle = enum(u8) {
    none = 0,
    simple = 1,
    released = 2,
    pressed = 3,
};

pub const FaceDecorationStyles = struct {
    underline: FaceLineStyle = .unspecified,
    overline: FaceLineStyle = .unspecified,
    strike_through: FaceLineStyle = .unspecified,
    box: FaceBoxStyle = .none,
    underline_color: ?Color = null,
    overline_color: ?Color = null,
    strike_color: ?Color = null,
    box_color: ?Color = null,
    foreground: ?Color = null,
};

pub const FaceDecorationBar = struct {
    rect: LogicalRect,
    color: Color,
};

pub const FaceDecorationBars = struct {
    bars: [7]FaceDecorationBar = undefined,
    len: usize = 0,

    pub fn slice(self: *const FaceDecorationBars) []const FaceDecorationBar {
        return self.bars[0..self.len];
    }
};

fn faceLineColor(style: FaceLineStyle, style_color: ?Color, foreground: ?Color) ?Color {
    return switch (style) {
        .off => null,
        .color => style_color orelse foreground,
        .unspecified => null,
        .single => foreground,
    };
}

fn pushFaceBar(bars: *FaceDecorationBars, rect: LogicalRect, color: ?Color) void {
    if (color == null or rect.width <= 0 or rect.height <= 0) return;
    if (bars.len == bars.bars.len) return;
    bars.bars[bars.len] = .{ .rect = rect, .color = color.? };
    bars.len += 1;
}

/// Computes bounded face decoration bars for one diagnostic ASCII glyph run.
/// These are approximation bars for the current debug renderer, not shaped-text
/// metrics or full Emacs face rendering.
pub fn faceDecorationBars(
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    styles: FaceDecorationStyles,
) FaceDecorationBars {
    var bars: FaceDecorationBars = .{};
    if (width <= 0 or height <= 0) return bars;
    const thickness: f32 = @max(1, height * 0.08);

    if (styles.underline != .off) {
        const color = faceLineColor(styles.underline, styles.underline_color, styles.foreground);
        pushFaceBar(&bars, .{ .x = x, .y = y + height - thickness, .width = width, .height = thickness }, color);
    }
    if (styles.overline != .off) {
        const color = faceLineColor(styles.overline, styles.overline_color, styles.foreground);
        pushFaceBar(&bars, .{ .x = x, .y = y, .width = width, .height = thickness }, color);
    }
    if (styles.strike_through != .off) {
        const color = faceLineColor(styles.strike_through, styles.strike_color, styles.foreground);
        pushFaceBar(&bars, .{ .x = x, .y = y + (height - thickness) / 2, .width = width, .height = thickness }, color);
    }
    if (styles.box != .none) {
        const color = styles.box_color orelse styles.foreground;
        pushFaceBar(&bars, .{ .x = x, .y = y, .width = width, .height = thickness }, color);
        pushFaceBar(&bars, .{ .x = x, .y = y + height - thickness, .width = width, .height = thickness }, color);
        pushFaceBar(&bars, .{ .x = x, .y = y + thickness, .width = thickness, .height = @max(0, height - 2 * thickness) }, color);
        pushFaceBar(&bars, .{ .x = x + width - thickness, .y = y + thickness, .width = thickness, .height = @max(0, height - 2 * thickness) }, color);
    }
    return bars;
}

fn logicalRectsIntersect(left: LogicalRect, right: LogicalRect) bool {
    return left.x < right.x + right.width and
        right.x < left.x + left.width and
        left.y < right.y + right.height and
        right.y < left.y + left.height;
}

/// Conservative CPU-side culling for explicit damage.  Debug text has no
/// measured bounds in this diagnostic path, so its estimated box uses the
/// SDL debug-text cell width plus a vertical margin.
pub fn drawCommandIntersectsClip(command: DrawCommand, clip: LogicalRect) bool {
    if (clip.width <= 0 or clip.height <= 0) return false;
    return switch (command) {
        .clear => true,
        .fill => |draw| logicalRectsIntersect(draw.rect, clip),
        .image => |draw| logicalRectsIntersect(draw.rect, clip),
        .image_region => |draw| logicalRectsIntersect(draw.destination, clip),
        .text => |draw| logicalRectsIntersect(
            .{ .x = draw.x, .y = draw.y, .width = @floatFromInt(8 * draw.bytes.len), .height = 16 },
            clip,
        ),
        // Font-backed UTF-8 has no backend-independent measured bounds yet.
        // Keep it conservative; a false-positive draw is cheaper than dropping
        // visible text during damage culling.
        .unicode_text => true,
    };
}

/// Backend-neutral immediate commands for the current smoke renderer. The
/// command list owns command storage, while text slices are borrowed and must
/// remain valid until execution completes. This avoids per-frame text copies;
/// the future glyph atlas replaces this debug text path.
pub const DrawList = struct {
    allocator: std.mem.Allocator,
    commands: std.ArrayList(DrawCommand) = .empty,
    candidate_metadata: [160]u8 = undefined,
    candidate_metadata_len: usize = 0,
    logical_width: f32 = 0,
    logical_height: f32 = 0,
    stats: DrawStats = .{},

    pub fn deinit(self: *DrawList) void {
        self.commands.deinit(self.allocator);
    }

    pub fn reset(self: *DrawList) void {
        self.commands.clearRetainingCapacity();
        self.candidate_metadata_len = 0;
        self.stats = .{};
    }

    /// Stores generated candidate metadata so the borrowed text command
    /// remains valid through execution.  The bounded buffer avoids a stack
    /// lifetime bug without adding per-command text copies.
    pub fn setCandidateMetadata(self: *DrawList, bytes: []const u8) ![]const u8 {
        if (bytes.len > self.candidate_metadata.len) return error.InvalidDrawText;
        @memcpy(self.candidate_metadata[0..bytes.len], bytes);
        self.candidate_metadata_len = bytes.len;
        return self.candidate_metadata[0..bytes.len];
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

    pub fn drawImage(
        self: *DrawList,
        rect: LogicalRect,
        pixels: []const u8,
        width: u32,
        height: u32,
    ) !void {
        if (rect.width <= 0 or rect.height <= 0 or width == 0 or height == 0)
            return error.InvalidDrawImage;
        if (pixels.len != @as(usize, width) * @as(usize, height) * 4)
            return error.InvalidDrawImage;
        try self.commands.append(self.allocator, .{ .image = .{
            .rect = rect,
            .pixels = pixels,
            .width = width,
            .height = height,
        } });
        self.stats.commands += 1;
        self.stats.images += 1;
    }

    pub fn drawAtlasGlyph(
        self: *DrawList,
        destination: LogicalRect,
        source: LogicalRect,
        pixels: []const u8,
        source_width: u32,
        source_height: u32,
        cache_key: u64,
        cache_revision: u32,
        atlas_id: u32,
        page_index: u16,
        generation: u32,
    ) !void {
        if (destination.width <= 0 or destination.height <= 0 or
            source.width <= 0 or source.height <= 0 or source_width == 0 or source_height == 0)
            return error.InvalidDrawAtlasGlyph;
        if (source.x < 0 or source.y < 0 or
            source.x + source.width > @as(f32, @floatFromInt(source_width)) or
            source.y + source.height > @as(f32, @floatFromInt(source_height)))
            return error.InvalidDrawAtlasGlyph;
        if (pixels.len != @as(usize, source_width) * @as(usize, source_height) * 4)
            return error.InvalidDrawAtlasGlyph;
        try self.commands.append(self.allocator, .{ .image_region = .{
            .destination = destination,
            .source = source,
            .pixels = pixels,
            .source_width = source_width,
            .source_height = source_height,
            .cache_key = cache_key,
            .cache_revision = cache_revision,
            .atlas_id = atlas_id,
            .page_index = page_index,
            .generation = generation,
        } });
        self.stats.commands += 1;
        self.stats.images += 1;
        self.stats.atlas_glyphs += 1;
    }

    pub fn drawText(self: *DrawList, x: f32, y: f32, bytes: []const u8, color: ?Color) !void {
        if (bytes.len == 0 or bytes.len > 120) return error.InvalidDrawText;
        for (bytes) |byte| {
            if (byte < 0x20 or byte > 0x7e) return error.InvalidDrawText;
        }
        try self.commands.append(self.allocator, .{ .text = .{ .x = x, .y = y, .color = color, .bytes = bytes } });
        self.stats.commands += 1;
        self.stats.texts += 1;
    }

    /// Queue bounded UTF-8 text for a backend with real font support.
    /// This stays separate from `drawText` so the existing diagnostic ASCII
    /// renderer cannot silently pretend to support Unicode.
    pub fn drawUnicodeText(self: *DrawList, x: f32, y: f32, bytes: []const u8, color: Color) !void {
        if (bytes.len == 0 or bytes.len > 120) return error.InvalidUnicodeText;
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUnicodeText;
        try self.commands.append(self.allocator, .{ .unicode_text = .{
            .x = x,
            .y = y,
            .color = color,
            .bytes = bytes,
        } });
        self.stats.commands += 1;
        self.stats.unicode_texts += 1;
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

test "explicit damage culls conservative command bounds" {
    const clip: LogicalRect = .{ .x = 16, .y = 8, .width = 96, .height = 48 };
    const clear: DrawCommand = .{ .clear = .{ .r = 0, .g = 0, .b = 0 } };
    const inside: DrawCommand = .{ .fill = .{
        .rect = .{ .x = 32, .y = 16, .width = 16, .height = 16 },
        .color = .{ .r = 1, .g = 2, .b = 3 },
    } };
    const outside_fill: DrawCommand = .{ .fill = .{
        .rect = .{ .x = 160, .y = 72, .width = 16, .height = 16 },
        .color = .{ .r = 1, .g = 2, .b = 3 },
    } };
    const touching: DrawCommand = .{ .fill = .{
        .rect = .{ .x = 104, .y = 32, .width = 16, .height = 16 },
        .color = .{ .r = 1, .g = 2, .b = 3 },
    } };
    const outside_text: DrawCommand = .{ .text = .{
        .x = 8,
        .y = 72,
        .bytes = "outside",
    } };

    try std.testing.expect(drawCommandIntersectsClip(clear, clip));
    try std.testing.expect(drawCommandIntersectsClip(inside, clip));
    try std.testing.expect(drawCommandIntersectsClip(touching, clip));
    try std.testing.expect(!drawCommandIntersectsClip(outside_fill, clip));
    try std.testing.expect(!drawCommandIntersectsClip(outside_text, clip));
}

test "face decoration bars honor styles and colors" {
    const bars = faceDecorationBars(10, 20, 80, 16, .{
        .underline = .single,
        .strike_through = .color,
        .strike_color = .{ .r = 1, .g = 2, .b = 3 },
        .foreground = .{ .r = 250, .g = 250, .b = 250 },
    });
    try std.testing.expectEqual(@as(usize, 2), bars.len);
    try std.testing.expectEqual(@as(f32, 1.28), bars.slice()[0].rect.height);
    try std.testing.expectEqual(Color{ .r = 1, .g = 2, .b = 3 }, bars.slice()[1].color);

    const boxed = faceDecorationBars(0, 0, 40, 20, .{
        .underline = .single,
        .overline = .single,
        .strike_through = .single,
        .box = .simple,
        .foreground = .{ .r = 9, .g = 9, .b = 9 },
    });
    try std.testing.expectEqual(@as(usize, 7), boxed.len);
}

test "explicit damage counters separate submitted and culled commands" {
    var counters: FrameCounters = .{};
    counters.recordExplicitDamage(true, 7, 2);

    try std.testing.expectEqual(@as(u64, 1), counters.explicit_damage_frames);
    try std.testing.expectEqual(@as(u64, 1), counters.explicit_clipped_frames);
    try std.testing.expectEqual(@as(u64, 0), counters.explicit_full_fallback_frames);
    try std.testing.expectEqual(@as(u64, 7), counters.explicit_submitted_commands);
    try std.testing.expectEqual(@as(u64, 2), counters.explicit_skipped_commands);
}

test "scroll copy planner rejects non-full-width runs and estimates bytes" {
    const plan = planScrollCopy(80, 60, 0, 10, 80, 40);
    try std.testing.expect(plan != null);
    try std.testing.expect(plan.?.overlap);
    try std.testing.expectEqual(@as(u64, 80 * 40 * 4), plan.?.estimated_upload_bytes);
    try std.testing.expectEqual(ScrollCopyPlan{
        .source_y = 0,
        .destination_y = 10,
        .width = 80,
        .height = 40,
        .overlap = true,
        .estimated_upload_bytes = 12_800,
    }, plan.?);
    try std.testing.expect(planScrollCopy(80, 60, 0, 10, 40, 40) == null);
    try std.testing.expect(planScrollCopy(80, 60, 0, 10, 80, 61) == null);
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
    try list.drawText(4, 5, "Emacs", null);

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
    try std.testing.expectError(error.InvalidDrawText, list.drawText(0, 0, "", null));
    try std.testing.expectError(error.InvalidDrawText, list.drawText(0, 0, "CJK 字", null));
    const oversized = "a" ** 121;
    try std.testing.expectError(error.InvalidDrawText, list.drawText(0, 0, oversized[0..], null));
}

test "unicode draw queue accepts bounded UTF-8 separately from ASCII debug text" {
    var list: DrawList = .{ .allocator = std.testing.allocator };
    defer list.deinit();
    try list.drawUnicodeText(4, 6, "你好 Emacs", .{ .r = 0xf0, .g = 0xf6, .b = 0xff, .a = 255 });
    try std.testing.expectEqual(@as(u64, 1), list.stats.unicode_texts);
    try std.testing.expectEqualStrings("你好 Emacs", list.commands.items[0].unicode_text.bytes);
    try std.testing.expectError(error.InvalidUnicodeText, list.drawUnicodeText(0, 0, "", .{ .r = 0, .g = 0, .b = 0, .a = 255 }));
    try std.testing.expectError(error.InvalidUnicodeText, list.drawUnicodeText(0, 0, &.{0xff}, .{ .r = 0, .g = 0, .b = 0, .a = 255 }));
}

test "unicode draws are never culled by an assumed glyph box" {
    const command: DrawCommand = .{ .unicode_text = .{
        .x = 100,
        .y = 100,
        .color = .{ .r = 0, .g = 0, .b = 0 },
        .bytes = "字",
    } };
    try std.testing.expect(drawCommandIntersectsClip(command, .{ .x = 0, .y = 0, .width = 10, .height = 10 }));
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

test "multi-cursor damage falls back when a non-selected cursor changes" {
    var gate: FrameGate = .{};
    const selected: CursorObservation = .{
        .window_id = 1,
        .owner_x = 0,
        .owner_y = 0,
        .x = 0,
        .y = 0,
        .width = 2,
        .height = 8,
        .kind = 1,
        .visible = true,
        .active = true,
    };
    const non_selected: CursorObservation = .{
        .window_id = 2,
        .owner_x = 40,
        .owner_y = 0,
        .x = 0,
        .y = 0,
        .width = 2,
        .height = 8,
        .kind = 1,
        .visible = true,
        .active = false,
    };
    const first: SceneDamageObservation = .{
        .frame_width = 120,
        .frame_height = 20,
        .viewport_start_line = 1,
        .viewport_line_count = 2,
        .cursor = selected,
        .cursor_hash = 11,
        .cursor_count = 2,
        .text_hash = [_]u8{0} ** 32,
        .text_line_count = 2,
        .structure_hash = [_]u8{0} ** 32,
        .structure_object_count = 2,
    };
    _ = gate.observeScene(first);
    var moved = non_selected;
    moved.x = 8;
    const second: SceneDamageObservation = .{
        .frame_width = 120,
        .frame_height = 20,
        .viewport_start_line = 1,
        .viewport_line_count = 2,
        .cursor = selected,
        .cursor_hash = 12,
        .cursor_count = 2,
        .text_hash = first.text_hash,
        .text_line_count = first.text_line_count,
        .structure_hash = first.structure_hash,
        .structure_object_count = first.structure_object_count,
    };
    const moved_only = gate.observeScene(second);
    try std.testing.expectEqual(DamageKind.viewport, moved_only.kind);

    _ = gate.observeScene(second);
    var moved_selected = selected;
    moved_selected.x = 4;
    const third: SceneDamageObservation = .{
        .frame_width = 120,
        .frame_height = 20,
        .viewport_start_line = 1,
        .viewport_line_count = 2,
        .cursor = moved_selected,
        .cursor_hash = 13,
        .cursor_count = 2,
        .text_hash = second.text_hash,
        .text_line_count = second.text_line_count,
        .structure_hash = second.structure_hash,
        .structure_object_count = second.structure_object_count,
    };
    try std.testing.expectEqual(DamageKind.viewport, gate.observeScene(third).kind);
}

test "mode-line flag changes invalidate damage" {
    var gate: FrameGate = .{};
    const base: SceneDamageObservation = .{
        .viewport_start_line = 1,
        .viewport_line_count = 1,
        .cursor = null,
        .text_hash = [_]u8{7} ** 32,
        .text_line_count = 0,
        .structure_hash = [_]u8{7} ** 32,
        .structure_object_count = 0,
    };
    var first = base;
    first.mode_line_hash = 1;
    var second = base;
    second.mode_line_hash = 2;
    _ = gate.observeScene(first);
    try std.testing.expectEqual(DamageKind.viewport, gate.observeScene(second).kind);

    var unchanged_gate: FrameGate = .{};
    var same = base;
    same.mode_line_hash = 3;
    _ = unchanged_gate.observeScene(same);
    try std.testing.expectEqual(DamageKind.none, unchanged_gate.observeScene(same).kind);
}

test "combined text and mode-line damage uses full-frame fallback" {
    var gate: FrameGate = .{};
    const first: SceneDamageObservation = .{
        .frame_width = 120,
        .frame_height = 80,
        .viewport_start_line = 1,
        .viewport_line_count = 1,
        .cursor = .{ .window_id = 1, .owner_x = 0, .owner_y = 0, .x = 0, .y = 0, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true },
        .text_hash = [_]u8{1} ** 32,
        .mode_line_hash = 1,
        .text_line_count = 1,
        .structure_hash = [_]u8{1} ** 32,
        .structure_object_count = 1,
        .text_lines = blk: {
            var lines = [_]TextLineObservation{.{}} ** max_clipped_text_lines;
            lines[0] = .{ .window_id = 1, .row_index = 0, .hash = 1, .rect = .{ .x = 0, .y = 0, .width = 20, .height = 8 } };
            break :blk lines;
        },
        .bounded_text_line_count = 1,
    };
    var second = first;
    second.text_hash = [_]u8{2} ** 32;
    second.mode_line_hash = 2;
    second.cursor = .{ .window_id = 1, .owner_x = 0, .owner_y = 0, .x = 16, .y = 8, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true };
    second.text_lines[0].hash = 2;
    _ = gate.observeScene(first);
    try std.testing.expectEqual(DamageKind.viewport, gate.observeScene(second).kind);
}

test "frame counters record cursor clipped and fallback frames" {
    var counters: FrameCounters = .{};
    counters.recordCursorClip(true, 93);
    counters.recordCursorClip(false, 0);
    try std.testing.expectEqual(@as(u64, 1), counters.cursor_clipped_frames);
    try std.testing.expectEqual(@as(u64, 1), counters.cursor_full_fallback_frames);
    try std.testing.expectEqual(@as(u64, 93), counters.clipped_draw_commands_total);
}

test "draw list records atlas glyph source and destination regions" {
    var list: DrawList = .{ .allocator = std.testing.allocator };
    defer list.deinit();
    const pixels = [_]u8{ 1, 2, 3, 255 };
    try list.drawAtlasGlyph(
        .{ .x = 1, .y = 2, .width = 1, .height = 1 },
        .{ .x = 0, .y = 0, .width = 1, .height = 1 },
        &pixels,
        1,
        1,
        77,
        3,
        9,
        1,
        4,
    );
    try std.testing.expectEqual(@as(usize, 1), list.commands.items.len);
    const command = list.commands.items[0].image_region;
    try std.testing.expectEqual(@as(f32, 1), command.destination.x);
    try std.testing.expectEqual(@as(f32, 0), command.source.x);
    try std.testing.expectEqual(@as(u64, 1), list.stats.atlas_glyphs);
}

test "text damage matches window and row, not row alone" {
    const make = struct {
        fn observation(first_hash: u64, second_hash: u64) SceneDamageObservation {
            var result: SceneDamageObservation = .{
                .viewport_start_line = 1,
                .viewport_line_count = 0,
                .cursor = null,
                .text_hash = .{0} ** 32,
                .text_line_count = 2,
                .structure_hash = .{0} ** 32,
                .structure_object_count = 2,
            };
            result.text_lines[0] = .{
                .window_id = 101,
                .row_index = 0,
                .hash = first_hash,
                .rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 },
            };
            result.text_lines[1] = .{
                .window_id = 102,
                .row_index = 0,
                .hash = second_hash,
                .rect = .{ .x = 50, .y = 0, .width = 10, .height = 10 },
            };
            result.bounded_text_line_count = 2;
            return result;
        }
    };
    const old = make.observation(1, 2);
    const unchanged = make.observation(1, 2);
    const changed = make.observation(1, 3);
    try std.testing.expect(textDamageClip(old, unchanged, 120, 80) == null);
    try std.testing.expect(textDamageClip(old, changed, 120, 80) != null);
}

test "latency summary uses nearest-rank percentiles" {
    const summary = try summarizeLatencies(&[_]u64{ 50, 20, 40, 10, 30, 60, 70, 80, 90, 100 });
    try std.testing.expectEqual(@as(u64, 50), summary.p50_ns);
    try std.testing.expectEqual(@as(u64, 100), summary.p95_ns);
    try std.testing.expectEqual(@as(u64, 100), summary.p99_ns);
    try std.testing.expectEqual(@as(f64, 55), summary.mean_ns);
    try std.testing.expect(summary.fps > 0);
    const single = try summarizeLatencies(&[_]u64{7});
    try std.testing.expectEqual(@as(u64, 7), single.p50_ns);
    try std.testing.expectEqual(@as(u64, 7), single.p95_ns);
    try std.testing.expectEqual(@as(u64, 7), single.p99_ns);
    try std.testing.expectError(error.EmptyLatencySample, summarizeLatencies(&[_]u64{}));
    try std.testing.expectError(error.InvalidLatencySample, summarizeLatencies(&[_]u64{ 1, 0 }));
}
