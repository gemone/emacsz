//! Frontend-owned scene state decoded from EUP.
//!
//! This module is deliberately independent of SDL and GNU Emacs.  SDL reads
//! the scene after the protocol/transport layers validate it; it never invents
//! core display state.

const std = @import("std");
const protocol = @import("protocol.zig");
const session = @import("session.zig");
const lifecycle = @import("lifecycle.zig");

pub const Error = protocol.Error || session.Error || lifecycle.Error || error{
    OutOfMemory,
    SessionSuspended,
    DuplicateResource,
};

pub const max_atlas_resources: usize = 4;

pub const Window = struct {
    id: u64,
    frame_id: u32,
    parent_id: u64 = 0,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    visible: bool = true,
    default_face_id: u32 = 0,
    depth: u8 = 0,

    fn valid(self: Window) bool {
        return self.id != 0 and self.frame_id != 0 and self.width >= 0 and self.height >= 0;
    }
};

pub const Row = struct {
    window_id: u64,
    index: u32,
    flags: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    ascent: i32,
    descent: i32,
    baseline: i32,
    visible_height: i32,

    fn valid(self: Row) bool {
        return self.window_id != 0 and self.width >= 0 and self.height >= 0 and
            self.visible_height >= 0 and self.ascent >= 0 and self.descent >= 0;
    }
};

pub const Cursor = struct {
    window_id: u64,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    kind: u8,
    visible: bool,
    active: bool,

    fn valid(self: Cursor) bool {
        return self.window_id != 0 and self.width >= 0 and self.height >= 0;
    }

    fn bounded(self: Cursor) bool {
        return self.valid() and self.width > 0 and self.height > 0;
    }

    fn withOwner(self: Cursor, owner: Window) Error!Cursor {
        if (!self.bounded()) return Error.InvalidMessage;
        if (!inside(self.x, self.width, owner.width) or
            !inside(self.y, self.height, owner.height)) return Error.InvalidMessage;
        return self;
    }
};

pub const Rect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,

    fn valid(self: Rect) bool {
        return self.width >= 0 and self.height >= 0;
    }
};

pub const PresentHint = struct {
    mode: u32,
    flags: u32,
    deadline_ns: u64,
};

pub const ImagePlacement = struct {
    placement_id: u32,
    window_id: u64,
    image_id: u32,
    image_generation: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    z_order: i16,
};

pub const ImagePlacementWire = struct {
    placement_id: u32,
    window_id: u64,
    image_id: u32,
    image_generation: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    z_order: i16 = 0,
};

pub fn encodeImagePlacement(
    a: std.mem.Allocator,
    placement: ImagePlacementWire,
    out: *std.ArrayList(u8),
) !void {
    if (placement.placement_id == 0 or placement.window_id == 0 or
        placement.image_id == 0 or placement.image_generation == 0 or
        placement.width <= 0 or placement.height <= 0 or
        placement.x < 0 or placement.y < 0) return Error.InvalidMessage;
    var bytes: [image_placement_record_size]u8 = [_]u8{0} ** image_placement_record_size;
    std.mem.writeInt(u16, bytes[0..2], image_placement_schema, .little);
    bytes[2] = image_placement_kind;
    std.mem.writeInt(u32, bytes[4..8], placement.placement_id, .little);
    std.mem.writeInt(u64, bytes[8..16], placement.window_id, .little);
    std.mem.writeInt(u32, bytes[16..20], placement.image_id, .little);
    std.mem.writeInt(u32, bytes[20..24], placement.image_generation, .little);
    std.mem.writeInt(u32, bytes[24..28], @bitCast(placement.x), .little);
    std.mem.writeInt(u32, bytes[28..32], @bitCast(placement.y), .little);
    std.mem.writeInt(u32, bytes[32..36], @bitCast(placement.width), .little);
    std.mem.writeInt(u32, bytes[36..40], @bitCast(placement.height), .little);
    std.mem.writeInt(u16, bytes[40..42], @bitCast(placement.z_order), .little);
    try out.appendSlice(a, &bytes);
}

pub fn decodeImagePlacement(data: []const u8) Error!ImagePlacement {
    if (data.len != image_placement_record_size) return Error.InvalidTable;
    const schema = std.mem.readInt(u16, data[0..2], .little);
    const kind = data[2];
    const flags = data[3];
    const placement: ImagePlacement = .{
        .placement_id = std.mem.readInt(u32, data[4..8], .little),
        .window_id = std.mem.readInt(u64, data[8..16], .little),
        .image_id = std.mem.readInt(u32, data[16..20], .little),
        .image_generation = std.mem.readInt(u32, data[20..24], .little),
        .x = @bitCast(std.mem.readInt(u32, data[24..28], .little)),
        .y = @bitCast(std.mem.readInt(u32, data[28..32], .little)),
        .width = @bitCast(std.mem.readInt(u32, data[32..36], .little)),
        .height = @bitCast(std.mem.readInt(u32, data[36..40], .little)),
        .z_order = @bitCast(std.mem.readInt(u16, data[40..42], .little)),
    };
    if (schema != image_placement_schema or kind != image_placement_kind or flags != 0)
        return Error.InvalidVersion;
    if (!std.mem.allEqual(u8, data[42..64], 0)) return Error.InvalidReserved;
    if (placement.placement_id == 0 or placement.window_id == 0 or
        placement.image_id == 0 or placement.image_generation == 0 or
        placement.x < 0 or placement.y < 0 or
        placement.width <= 0 or placement.height <= 0) return Error.InvalidMessage;
    return placement;
}

pub const TextLine = struct {
    window_id: u64 = 1,
    row_index: u32,
    bytes: [:0]const u8,
};

pub const max_glyph_text_bytes: usize = 120;
pub const max_glyph_runs: usize = 64;
pub const glyph_record_size: usize = 60;
pub const glyph_delete_record_size: usize = 24;
pub const glyph_debug_fallback: u16 = 1 << 0;
pub const glyph_shaped_atlas: u16 = 1 << 1;
pub const shaped_glyph_record_size: usize = 16;
pub const max_shaped_glyphs: usize = 7;

pub const ShapedGlyph = struct {
    glyph_id: u32,
    cluster: u32,
    x_offset: i16,
    y_offset: i16,
    advance_x: u16,
    advance_y: u16,
};

pub const GlyphRun = struct {
    run_id: u32,
    generation: u32,
    window_id: u64,
    row_index: u32,
    face_id: u32,
    face_generation: u32,
    font_id: u32 = 0,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    text: [:0]u8,
    shaped: bool = false,
    shaped_glyphs: [max_shaped_glyphs]ShapedGlyph = undefined,
    shaped_count: usize = 0,
};

pub const GlyphRunWire = struct {
    schema: u16 = 1,
    flags: u16 = glyph_debug_fallback,
    direction: u16 = 1,
    run_id: u32,
    generation: u32,
    window_id: u64,
    row_index: u32,
    face_id: u32 = 0,
    face_generation: u32 = 0,
    font_id: u32 = 0,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    text: []const u8,
    glyphs: [max_shaped_glyphs]ShapedGlyph = undefined,
    glyph_count: usize = 0,

    fn valid(self: GlyphRunWire) bool {
        return self.run_id != 0 and self.generation != 0 and self.window_id != 0 and
            self.x >= 0 and self.y >= 0 and self.width >= 0 and self.height >= 0;
    }
};

pub const GlyphRunDeleteWire = struct {
    run_id: u32,
    generation: u32,
    window_id: u64,
    row_index: u32,
};

pub fn encodeGlyphRun(a: std.mem.Allocator, run: GlyphRunWire, out: *std.ArrayList(u8)) !void {
    const face_bound = run.schema == 2;
    const shaped_atlas = run.schema == 3;
    if ((run.schema != 1 and run.schema != 2 and run.schema != 3) or
        run.direction != 1 or run.run_id == 0 or
        run.generation == 0 or run.window_id == 0) return Error.InvalidMessage;
    if (!shaped_atlas and (run.flags != glyph_debug_fallback or run.font_id != 0 or
        !validGlyphRunText(run.text))) return Error.InvalidMessage;
    if (shaped_atlas and (run.flags != glyph_shaped_atlas or run.font_id == 0 or
        run.glyph_count == 0 or run.glyph_count > max_shaped_glyphs or
        run.text.len != 0)) return Error.InvalidMessage;
    if ((face_bound and (run.face_id == 0 or run.face_generation == 0)) or
        (!face_bound and !shaped_atlas and (run.face_id != 0 or run.face_generation != 0)) or
        (shaped_atlas and (run.face_id == 0 or run.face_generation == 0 or run.font_id == 0)))
        return Error.InvalidMessage;
    if (run.x < 0 or run.y < 0 or run.width < 0 or run.height < 0)
        return Error.InvalidMessage;
    try out.appendSlice(a, &[8]u8{
        @intCast(run.schema),       0,
        @intCast(run.flags & 0xff), @intCast(run.flags >> 8),
        1,                          0,
        0,                          0,
    });
    try putU32(out, a, run.run_id);
    try putU32(out, a, run.generation);
    try putU64(out, a, run.window_id);
    try putU32(out, a, run.row_index);
    try putU32(out, a, run.face_id);
    try putU32(out, a, run.font_id);
    try putI32(out, a, run.x);
    try putI32(out, a, run.y);
    try putI32(out, a, run.width);
    try putI32(out, a, run.height);
    var reserved: [8]u8 = [_]u8{0} ** 8;
    std.mem.writeInt(u32, reserved[0..4], run.face_generation, .little);
    try out.appendSlice(a, &reserved);
    if (shaped_atlas) {
        for (run.glyphs[0..run.glyph_count]) |glyph| {
            try putU32(out, a, glyph.glyph_id);
            try putU32(out, a, glyph.cluster);
            try putI16(out, a, glyph.x_offset);
            try putI16(out, a, glyph.y_offset);
            try putU16(out, a, glyph.advance_x);
            try putU16(out, a, glyph.advance_y);
        }
    } else {
        try out.appendSlice(a, run.text);
    }
}

pub fn decodeGlyphRun(bytes: []const u8) Error!GlyphRunWire {
    if (bytes.len < glyph_record_size or bytes.len > glyph_record_size + max_glyph_text_bytes)
        return Error.InvalidTable;
    const header = bytes[0..glyph_record_size];
    const body = bytes[glyph_record_size..];
    const schema = std.mem.readInt(u16, header[0..2], .little);
    const flags = std.mem.readInt(u16, header[2..4], .little);
    const direction = std.mem.readInt(u16, header[4..6], .little);
    const face_generation = std.mem.readInt(u32, header[52..56], .little);
    if ((schema != 1 and schema != 2 and schema != 3) or direction != 1 or
        std.mem.readInt(u16, header[6..8], .little) != 0) return Error.InvalidVersion;
    if ((schema == 1 and (face_generation != 0 or flags != glyph_debug_fallback)) or
        (schema == 2 and (face_generation == 0 or flags != glyph_debug_fallback)) or
        (schema == 3 and (face_generation == 0 or flags != glyph_shaped_atlas)))
        return Error.InvalidVersion;
    const text: []const u8 = if (schema == 3) &.{} else body;
    var glyphs: [max_shaped_glyphs]ShapedGlyph = undefined;
    var glyph_count: usize = 0;
    if (schema == 3) {
        glyph_count = body.len / shaped_glyph_record_size;
        var offset: usize = 0;
        while (offset < glyph_count) : (offset += 1) {
            const base = body[offset * shaped_glyph_record_size ..][0..shaped_glyph_record_size];
            glyphs[offset] = .{
                .glyph_id = std.mem.readInt(u32, base[0..4], .little),
                .cluster = std.mem.readInt(u32, base[4..8], .little),
                .x_offset = @bitCast(std.mem.readInt(u16, base[8..10], .little)),
                .y_offset = @bitCast(std.mem.readInt(u16, base[10..12], .little)),
                .advance_x = std.mem.readInt(u16, base[12..14], .little),
                .advance_y = std.mem.readInt(u16, base[14..16], .little),
            };
        }
    }
    const run: GlyphRunWire = .{
        .schema = schema,
        .run_id = std.mem.readInt(u32, header[8..12], .little),
        .generation = std.mem.readInt(u32, header[12..16], .little),
        .window_id = std.mem.readInt(u64, header[16..24], .little),
        .row_index = std.mem.readInt(u32, header[24..28], .little),
        .face_id = std.mem.readInt(u32, header[28..32], .little),
        .face_generation = face_generation,
        .font_id = std.mem.readInt(u32, header[32..36], .little),
        .x = @bitCast(std.mem.readInt(u32, header[36..40], .little)),
        .y = @bitCast(std.mem.readInt(u32, header[40..44], .little)),
        .width = @bitCast(std.mem.readInt(u32, header[44..48], .little)),
        .height = @bitCast(std.mem.readInt(u32, header[48..52], .little)),
        .text = text,
        .glyphs = glyphs,
        .glyph_count = glyph_count,
    };
    if (!std.mem.allEqual(u8, header[56..60], 0)) return Error.InvalidReserved;
    if ((schema == 1 and run.face_id != 0) or
        (schema == 2 and run.face_id == 0)) return Error.InvalidMessage;
    if ((schema != 3 and run.font_id != 0) or
        (schema == 3 and (run.face_id == 0 or run.font_id == 0))) return Error.InvalidMessage;
    if (!run.valid()) return Error.InvalidMessage;
    if (schema != 3) {
        if (body.len < 1 or !validGlyphRunText(text)) return Error.InvalidMessage;
    } else {
        if (body.len < shaped_glyph_record_size or body.len % shaped_glyph_record_size != 0 or
            body.len / shaped_glyph_record_size > max_shaped_glyphs)
            return Error.InvalidMessage;
    }
    return run;
}

pub fn encodeGlyphRunDelete(
    a: std.mem.Allocator,
    delete: GlyphRunDeleteWire,
    out: *std.ArrayList(u8),
) !void {
    if (delete.run_id == 0 or delete.generation == 0 or delete.window_id == 0)
        return Error.InvalidMessage;
    try putU32(out, a, delete.run_id);
    try putU32(out, a, delete.generation);
    try putU64(out, a, delete.window_id);
    try putU32(out, a, delete.row_index);
    try putU32(out, a, 0);
}

pub fn decodeGlyphRunDelete(bytes: []const u8) Error!GlyphRunDeleteWire {
    if (bytes.len != glyph_delete_record_size) return Error.InvalidTable;
    const delete: GlyphRunDeleteWire = .{
        .run_id = std.mem.readInt(u32, bytes[0..4], .little),
        .generation = std.mem.readInt(u32, bytes[4..8], .little),
        .window_id = std.mem.readInt(u64, bytes[8..16], .little),
        .row_index = std.mem.readInt(u32, bytes[16..20], .little),
    };
    if (!std.mem.allEqual(u8, bytes[20..24], 0)) return Error.InvalidReserved;
    if (delete.run_id == 0 or delete.generation == 0 or delete.window_id == 0)
        return Error.InvalidMessage;
    return delete;
}

fn validGlyphRunText(text: []const u8) bool {
    if (text.len == 0 or text.len > max_glyph_text_bytes) return false;
    for (text) |byte| {
        if (byte < 0x20 or byte == 0x7f or byte > 0x7e) return false;
    }
    return true;
}

pub const TextLineWire = struct {
    row_index: u32,
    line: []const u8,
};

pub const TextLineV2Wire = struct {
    window_id: u64,
    row_index: u32,
    line: []const u8,
};

pub const ModeLine = struct {
    window_id: u64,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    flags: u16,
    bytes: [121]u8 = undefined,
    len: u16 = 0,
};

pub const ModeLineWire = struct {
    window_id: u64,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    flags: u16 = 0,
    line: []const u8,
};

pub const mode_line_header_size: usize = 30;
pub const mode_line_active: u16 = 1;
pub const aux_line_header: u16 = 1 << 1;
pub const aux_line_tab: u16 = 1 << 2;
pub const aux_line_kind_mask: u16 = aux_line_header | aux_line_tab;
pub const aux_line_header_size: usize = 30;
pub const max_aux_lines: usize = 32;

pub fn encodeWindowAuxLineV1(a: std.mem.Allocator, line: ModeLineWire, out: *std.ArrayList(u8)) !void {
    if (line.window_id == 0 or line.width <= 0 or line.height <= 0 or
        line.flags & ~aux_line_kind_mask != 0 or
        line.flags & aux_line_kind_mask == 0 or
        line.flags & aux_line_kind_mask == aux_line_kind_mask)
        return Error.InvalidTable;
    if (!validBoundedUtf8Text(line.line, max_text_columns)) return Error.InvalidTable;
    var header: [aux_line_header_size]u8 = undefined;
    std.mem.writeInt(u64, header[0..8], line.window_id, .little);
    inline for (.{ line.x, line.y, line.width, line.height }, 0..) |value, index| {
        std.mem.writeInt(i32, header[8 + index * 4 ..][0..4], value, .little);
    }
    std.mem.writeInt(u16, header[24..26], line.flags, .little);
    std.mem.writeInt(u32, header[26..30], @intCast(line.line.len), .little);
    try out.appendSlice(a, &header);
    try out.appendSlice(a, line.line);
}

pub fn decodeWindowAuxLineV1(bytes: []const u8) Error!ModeLineWire {
    if (bytes.len < aux_line_header_size) return Error.InvalidTable;
    const length = std.mem.readInt(u32, bytes[26..30], .little);
    if (bytes.len != aux_line_header_size + length) return Error.InvalidTable;
    const payload = bytes[aux_line_header_size..];
    if (!validBoundedUtf8Text(payload, max_text_columns)) return Error.InvalidTable;
    const flags = std.mem.readInt(u16, bytes[24..26], .little);
    if (flags & ~aux_line_kind_mask != 0 or
        flags & aux_line_kind_mask == 0 or
        flags & aux_line_kind_mask == aux_line_kind_mask)
        return Error.InvalidTable;
    return .{
        .window_id = std.mem.readInt(u64, bytes[0..8], .little),
        .x = @bitCast(std.mem.readInt(u32, bytes[8..12], .little)),
        .y = @bitCast(std.mem.readInt(u32, bytes[12..16], .little)),
        .width = @bitCast(std.mem.readInt(u32, bytes[16..20], .little)),
        .height = @bitCast(std.mem.readInt(u32, bytes[20..24], .little)),
        .flags = flags,
        .line = payload,
    };
}

/// Bounded facts/scene text is UTF-8 and excludes C0/C1 controls and DEL.
/// Printable ASCII remains a strict subset; combining marks and CJK are valid.
pub fn validBoundedUtf8Text(text: []const u8, max_bytes: usize) bool {
    if (!validBoundedUtf8Line(text, max_bytes)) return false;
    return text.len != 0;
}

pub fn validBoundedUtf8Line(text: []const u8, max_bytes: usize) bool {
    if (text.len > max_bytes) return false;
    if (!std.unicode.utf8ValidateSlice(text)) return false;
    var view = std.unicode.Utf8View.initUnchecked(text);
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |codepoint| {
        if (codepoint < 0x20 or (codepoint >= 0x7f and codepoint <= 0x9f))
            return false;
    }
    return true;
}

pub const TextInput = struct {
    text: []const u8,
};

pub const KeyAction = enum(u16) {
    backspace = 1,
    copy = 6,
    cursor_left = 2,
    cursor_right = 3,
    cursor_up = 4,
    cursor_down = 5,
};

pub const KeyEvent = struct {
    action: KeyAction,
    state: u8 = 1,
    modifiers: u8 = 0,
};

pub const max_pointer_coordinate: i32 = 16383;

pub const PointerPhase = enum(u8) {
    motion = 1,
    press = 2,
    release = 3,
};

pub const PointerInput = struct {
    phase: PointerPhase,
    button: u8 = 0,
    x: i32,
    y: i32,
    clicks: u8 = 0,
    modifiers: u8 = 0,

    pub fn valid(self: PointerInput) bool {
        if (self.x < 0 or self.x > max_pointer_coordinate or
            self.y < 0 or self.y > max_pointer_coordinate or self.modifiers != 0) return false;
        return switch (self.phase) {
            // button 1 on motion means an active left-drag; button 0 is idle motion.
            .motion => (self.button == 0 or self.button == 1) and self.clicks == 0,
            .press, .release => self.button == 1 and self.clicks == 1,
        };
    }
};

pub const max_wheel_ticks: i8 = 8;

pub const WheelUnit = enum(u8) {
    line = 1,
};

pub const WheelSource = enum(u8) {
    wheel = 1,
};

pub const WheelInput = struct {
    x: i8 = 0,
    y: i8 = 0,
    unit: WheelUnit = .line,
    source: WheelSource = .wheel,
    modifiers: u8 = 0,

    pub fn valid(self: WheelInput) bool {
        if (self.modifiers != 0 or self.unit != .line or self.source != .wheel) return false;
        if (self.x != 0) return false;
        return self.y != 0 and @abs(self.y) <= max_wheel_ticks;
    }
};

pub const window_record_size: usize = 40;
pub const row_record_size: usize = 56;
pub const cursor_record_size: usize = 56;
pub const damage_record_size: usize = 16;
const present_record_size: usize = 16;
const max_text_columns: usize = 120;
const resource_record_size: usize = 16;
pub const ResourceDeclaration = lifecycle.Resource;
pub const max_resources = lifecycle.max_resources;
pub const max_string_resources: usize = 64;
pub const max_face_resources: usize = 64;
pub const max_font_resources: usize = 64;
pub const max_image_resources: usize = 8;
pub const max_image_placements: usize = 16;
pub const max_mode_lines: usize = 16;
pub const max_clear_areas: usize = 64;
pub const max_scroll_runs: usize = 32;
pub const max_dividers: usize = 32;
pub const max_fringes: usize = 32;
pub const max_fringe_bitmaps: usize = 64;

pub const FringeSide = enum(u8) {
    left = 1,
    right = 2,
};

pub const FringeUpdate = struct {
    schema: u16 = 1,
    side: FringeSide,
    reserved: u8 = 0,
    fringe_id: u32,
    fringe_generation: u32,
    window_id: u64,
    y: i32,
    height: i32,
    width: i32,
    color: [4]u8,
    frame_generation: u32,
};

pub const fringe_update_size: usize = 40;

pub fn fringeRect(fringe: FringeUpdate, owner_width: i32) Rect {
    const x = if (fringe.side == .left) 0 else owner_width - fringe.width;
    return .{ .x = x, .y = fringe.y, .width = fringe.width, .height = fringe.height };
}

pub fn encodeFringeUpdate(a: std.mem.Allocator, fringe: FringeUpdate, out: *std.ArrayList(u8)) !void {
    if (fringe.schema != 1 or fringe.reserved != 0 or
        fringe.fringe_id == 0 or fringe.fringe_generation == 0 or
        fringe.window_id == 0 or fringe.y < 0 or fringe.height <= 0 or
        fringe.width <= 0 or fringe.color[3] == 0 or fringe.frame_generation == 0)
        return Error.InvalidMessage;
    var b: [fringe_update_size]u8 = [_]u8{0} ** fringe_update_size;
    std.mem.writeInt(u16, b[0..2], fringe.schema, .little);
    b[2] = @intFromEnum(fringe.side);
    std.mem.writeInt(u32, b[4..8], fringe.fringe_id, .little);
    std.mem.writeInt(u32, b[8..12], fringe.fringe_generation, .little);
    std.mem.writeInt(u64, b[12..20], fringe.window_id, .little);
    std.mem.writeInt(i32, b[20..24], fringe.y, .little);
    std.mem.writeInt(i32, b[24..28], fringe.height, .little);
    std.mem.writeInt(i32, b[28..32], fringe.width, .little);
    @memcpy(b[32..36], &fringe.color);
    std.mem.writeInt(u32, b[36..40], fringe.frame_generation, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeFringeUpdate(data: []const u8) Error!FringeUpdate {
    if (data.len != fringe_update_size) return Error.InvalidTable;
    const fringe: FringeUpdate = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .side = switch (data[2]) {
            1 => .left,
            2 => .right,
            else => return Error.InvalidMessage,
        },
        .reserved = data[3],
        .fringe_id = std.mem.readInt(u32, data[4..8], .little),
        .fringe_generation = std.mem.readInt(u32, data[8..12], .little),
        .window_id = std.mem.readInt(u64, data[12..20], .little),
        .y = @bitCast(std.mem.readInt(u32, data[20..24], .little)),
        .height = @bitCast(std.mem.readInt(u32, data[24..28], .little)),
        .width = @bitCast(std.mem.readInt(u32, data[28..32], .little)),
        .color = data[32..36][0..4].*,
        .frame_generation = std.mem.readInt(u32, data[36..40], .little),
    };
    if (fringe.schema != 1 or fringe.reserved != 0 or
        fringe.fringe_id == 0 or fringe.fringe_generation == 0 or
        fringe.window_id == 0 or fringe.y < 0 or fringe.height <= 0 or
        fringe.width <= 0 or fringe.color[3] == 0 or fringe.frame_generation == 0)
        return Error.InvalidMessage;
    return fringe;
}
pub const WindowScrollFlags = struct {
    pub const vertical_visible: u8 = 1 << 0;
    pub const known: u8 = vertical_visible;
};

pub const WindowScrollState = struct {
    schema: u16 = 1,
    flags: u8,
    reserved: u8 = 0,
    window_id: u64,
    frame_generation: u32,
    content_size: u32,
    viewport_size: u32,
    position: u32,
    track_width: u32,
    reserved_tail: [16]u8 = @splat(0),
};

pub const window_scroll_state_size: usize = 48;
pub const max_scrollbar_states: usize = 32;
pub const max_window_faces: usize = 32;
pub const max_window_geometries: usize = 32;
pub const max_window_zones: usize = 32;
pub const max_window_positions: usize = 32;
pub const max_mouse_highlights: usize = 32;
pub const max_scene_cursors: usize = 16;

pub const WindowGeometryState = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    window_id: u64,
    frame_generation: u32,
    content: protocol.GeometryRect,
    body: protocol.GeometryRect,
    reserved_tail: [4]u8 = @splat(0),
};

pub const window_geometry_state_size: usize = 52;

fn encodeGeometryRectFixed(a: std.mem.Allocator, rect: protocol.GeometryRect, out: *std.ArrayList(u8)) !void {
    var word: [4]u8 = undefined;
    inline for (.{ rect.x, rect.y, rect.width, rect.height }) |value| {
        std.mem.writeInt(u32, &word, @bitCast(value), .little);
        try out.appendSlice(a, &word);
    }
}

pub const WindowZoneBits = struct {
    pub const mode_line: u32 = 1 << 0;
    pub const header_line: u32 = 1 << 1;
    pub const tab_line: u32 = 1 << 2;
    pub const left_margin: u32 = 1 << 3;
    pub const right_margin: u32 = 1 << 4;
    pub const left_fringe: u32 = 1 << 5;
    pub const right_fringe: u32 = 1 << 6;
    pub const horizontal_scrollbar: u32 = 1 << 7;
    pub const vertical_scrollbar: u32 = 1 << 8;
    pub const known: u32 = mode_line | header_line | tab_line |
        left_margin | right_margin | left_fringe | right_fringe |
        horizontal_scrollbar | vertical_scrollbar;
};

pub const window_zone_count: usize = 9;

pub const WindowZonesState = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    window_id: u64,
    frame_generation: u32,
    presence: u32,
    zones: [window_zone_count]protocol.GeometryRect = [_]protocol.GeometryRect{.{ .x = 0, .y = 0, .width = 0, .height = 0 }} ** window_zone_count,
};

pub const window_zones_state_size: usize = 20 + window_zone_count * 16;

fn geometryRectsOverlap(a: protocol.GeometryRect, b: protocol.GeometryRect) bool {
    const a_right = @as(i64, a.x) + a.width;
    const a_bottom = @as(i64, a.y) + a.height;
    const b_right = @as(i64, b.x) + b.width;
    const b_bottom = @as(i64, b.y) + b.height;
    return a.x < b_right and b.x < a_right and
        a.y < b_bottom and b.y < a_bottom;
}

pub fn zoneRect(state: WindowZonesState, bit: u32) ?protocol.GeometryRect {
    if (state.presence & bit == 0) return null;
    return state.zones[@ctz(bit)];
}

fn validateWindowZonesState(state: WindowZonesState) Error!void {
    if (state.schema != 1 or state.flags != 0 or state.reserved != 0 or
        state.window_id == 0 or state.frame_generation == 0 or
        state.presence == 0 or state.presence & ~WindowZoneBits.known != 0)
        return Error.InvalidMessage;

    var index: usize = 0;
    while (index < window_zone_count) : (index += 1) {
        const bit = @as(u32, 1) << @intCast(index);
        const rect = state.zones[index];
        if (state.presence & bit != 0) {
            if (rect.x < 0 or rect.y < 0 or !protocol.validGeometryRect(rect))
                return Error.InvalidMessage;
        } else if (rect.x != 0 or rect.y != 0 or rect.width != 0 or rect.height != 0) {
            return Error.InvalidMessage;
        }
    }

    var outer: usize = 0;
    while (outer < window_zone_count) : (outer += 1) {
        if (state.presence & (@as(u32, 1) << @intCast(outer)) == 0) continue;
        var inner: usize = outer + 1;
        while (inner < window_zone_count) : (inner += 1) {
            if (state.presence & (@as(u32, 1) << @intCast(inner)) == 0) continue;
            if (geometryRectsOverlap(state.zones[outer], state.zones[inner]))
                return Error.InvalidMessage;
        }
    }
}

pub fn encodeWindowZonesState(
    a: std.mem.Allocator,
    state: WindowZonesState,
    out: *std.ArrayList(u8),
) !void {
    try validateWindowZonesState(state);
    var b: [window_zones_state_size]u8 = [_]u8{0} ** window_zones_state_size;
    std.mem.writeInt(u16, b[0..2], state.schema, .little);
    std.mem.writeInt(u64, b[4..12], state.window_id, .little);
    std.mem.writeInt(u32, b[12..16], state.frame_generation, .little);
    std.mem.writeInt(u32, b[16..20], state.presence, .little);
    try out.appendSlice(a, b[0..20]);
    for (state.zones) |rect| try encodeGeometryRectFixed(a, rect, out);
}

pub fn decodeWindowZonesState(data: []const u8) Error!WindowZonesState {
    if (data.len != window_zones_state_size) return Error.InvalidTable;
    var state: WindowZonesState = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .window_id = std.mem.readInt(u64, data[4..12], .little),
        .frame_generation = std.mem.readInt(u32, data[12..16], .little),
        .presence = std.mem.readInt(u32, data[16..20], .little),
    };
    var offset: usize = 20;
    for (&state.zones) |*rect| {
        rect.* = .{
            .x = @bitCast(std.mem.readInt(u32, data[offset..][0..4], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[offset + 4 ..][0..4], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[offset + 8 ..][0..4], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[offset + 12 ..][0..4], .little)),
        };
        offset += 16;
    }
    try validateWindowZonesState(state);
    return state;
}

pub const WindowFaceState = struct {
    schema: u16 = 1,
    reserved: u8 = 0,
    flags: u8 = 0,
    window_id: u64,
    frame_generation: u32,
    face_id: u32,
    face_generation: u32,
};

pub fn encodeWindowGeometryState(
    a: std.mem.Allocator,
    state: WindowGeometryState,
    out: *std.ArrayList(u8),
) !void {
    try validateWindowGeometryState(state);
    var b: [window_geometry_state_size]u8 = [_]u8{0} ** window_geometry_state_size;
    std.mem.writeInt(u16, b[0..2], state.schema, .little);
    std.mem.writeInt(u64, b[4..12], state.window_id, .little);
    std.mem.writeInt(u32, b[12..16], state.frame_generation, .little);
    try out.appendSlice(a, b[0..16]);
    try encodeGeometryRectFixed(a, state.content, out);
    try encodeGeometryRectFixed(a, state.body, out);
    try out.appendSlice(a, &state.reserved_tail);
}

pub fn decodeWindowGeometryState(data: []const u8) Error!WindowGeometryState {
    if (data.len != window_geometry_state_size) return Error.InvalidTable;
    const state: WindowGeometryState = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .window_id = std.mem.readInt(u64, data[4..12], .little),
        .frame_generation = std.mem.readInt(u32, data[12..16], .little),
        .content = .{
            .x = @bitCast(std.mem.readInt(u32, data[16..20], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[20..24], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[24..28], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[28..32], .little)),
        },
        .body = .{
            .x = @bitCast(std.mem.readInt(u32, data[32..36], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[36..40], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[40..44], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[44..48], .little)),
        },
        .reserved_tail = data[48..52][0..4].*,
    };
    try validateWindowGeometryState(state);
    return state;
}

fn validateWindowGeometryState(state: WindowGeometryState) Error!void {
    if (state.schema != 1 or state.flags != 0 or state.reserved != 0 or
        state.window_id == 0 or state.frame_generation == 0 or
        !std.mem.allEqual(u8, &state.reserved_tail, 0) or
        state.content.x < 0 or state.content.y < 0 or
        state.body.x < 0 or state.body.y < 0 or
        !protocol.validGeometryRect(state.content) or
        !protocol.validGeometryRect(state.body) or
        !protocol.containsGeometryRect(state.content, state.body))
        return Error.InvalidMessage;
}

pub const window_face_state_size: usize = 24;

pub const WindowPositionFlags = struct {
    pub const point_visible: u8 = 1 << 0;
    pub const known: u8 = point_visible;
};

pub const WindowPositionState = struct {
    schema: u16 = 1,
    flags: u8,
    reserved: u8 = 0,
    window_id: u64,
    frame_generation: u32,
    buffer_id: u32,
    buffer_generation: u32,
    window_start: u32,
    point: u32,
    reserved_tail: [8]u8 = @splat(0),
};

pub const window_position_state_size: usize = 40;

pub fn encodeWindowPositionState(
    a: std.mem.Allocator,
    state: WindowPositionState,
    out: *std.ArrayList(u8),
) !void {
    try validateWindowPositionState(state);
    var b: [window_position_state_size]u8 = [_]u8{0} ** window_position_state_size;
    std.mem.writeInt(u16, b[0..2], state.schema, .little);
    b[2] = state.flags;
    b[3] = state.reserved;
    std.mem.writeInt(u64, b[4..12], state.window_id, .little);
    std.mem.writeInt(u32, b[12..16], state.frame_generation, .little);
    std.mem.writeInt(u32, b[16..20], state.buffer_id, .little);
    std.mem.writeInt(u32, b[20..24], state.buffer_generation, .little);
    std.mem.writeInt(u32, b[24..28], state.window_start, .little);
    std.mem.writeInt(u32, b[28..32], state.point, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeWindowPositionState(data: []const u8) Error!WindowPositionState {
    if (data.len != window_position_state_size) return Error.InvalidTable;
    const state: WindowPositionState = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .window_id = std.mem.readInt(u64, data[4..12], .little),
        .frame_generation = std.mem.readInt(u32, data[12..16], .little),
        .buffer_id = std.mem.readInt(u32, data[16..20], .little),
        .buffer_generation = std.mem.readInt(u32, data[20..24], .little),
        .window_start = std.mem.readInt(u32, data[24..28], .little),
        .point = std.mem.readInt(u32, data[28..32], .little),
        .reserved_tail = data[32..40][0..8].*,
    };
    try validateWindowPositionState(state);
    return state;
}

pub const MouseHighlightFlags = struct {
    pub const visible: u8 = 1 << 0;
    pub const known: u8 = visible;
};

pub const MouseHighlightState = struct {
    schema: u16 = 1,
    flags: u8,
    reserved: u8 = 0,
    window_id: u64,
    frame_generation: u32,
    rect: Rect,
    face_id: u32,
    face_generation: u32,
    reserved_tail: [8]u8 = @splat(0),
};

pub const mouse_highlight_state_size: usize = 48;

pub fn encodeMouseHighlightState(a: std.mem.Allocator, state: MouseHighlightState, out: *std.ArrayList(u8)) !void {
    try validateMouseHighlightState(state);
    var b: [mouse_highlight_state_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], state.schema, .little);
    b[2] = state.flags;
    b[3] = state.reserved;
    std.mem.writeInt(u64, b[4..12], state.window_id, .little);
    std.mem.writeInt(u32, b[12..16], state.frame_generation, .little);
    inline for (.{ state.rect.x, state.rect.y, state.rect.width, state.rect.height }, 0..) |value, index| {
        std.mem.writeInt(i32, b[16 + index * 4 ..][0..4], value, .little);
    }
    std.mem.writeInt(u32, b[32..36], state.face_id, .little);
    std.mem.writeInt(u32, b[36..40], state.face_generation, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeMouseHighlightState(data: []const u8) Error!MouseHighlightState {
    if (data.len != mouse_highlight_state_size) return Error.InvalidTable;
    const state: MouseHighlightState = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .window_id = std.mem.readInt(u64, data[4..12], .little),
        .frame_generation = std.mem.readInt(u32, data[12..16], .little),
        .rect = .{
            .x = @bitCast(std.mem.readInt(u32, data[16..20], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[20..24], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[24..28], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[28..32], .little)),
        },
        .face_id = std.mem.readInt(u32, data[32..36], .little),
        .face_generation = std.mem.readInt(u32, data[36..40], .little),
        .reserved_tail = data[40..48][0..8].*,
    };
    try validateMouseHighlightState(state);
    return state;
}

fn validateMouseHighlightState(state: MouseHighlightState) Error!void {
    if (state.schema != 1 or state.flags & ~MouseHighlightFlags.known != 0 or
        state.reserved != 0 or !std.mem.allEqual(u8, &state.reserved_tail, 0) or
        state.window_id == 0 or state.frame_generation == 0 or
        state.face_id == 0 or state.face_generation == 0 or
        state.rect.width <= 0 or state.rect.height <= 0 or
        state.rect.x < 0 or state.rect.y < 0)
        return Error.InvalidMessage;
}

fn validateWindowPositionState(state: WindowPositionState) Error!void {
    if (state.schema != 1 or state.flags & ~WindowPositionFlags.known != 0 or
        state.reserved != 0 or !std.mem.allEqual(u8, &state.reserved_tail, 0) or
        state.window_id == 0 or state.frame_generation == 0 or
        state.buffer_id == 0 or state.buffer_generation == 0 or
        state.window_start == 0 or state.point == 0)
        return Error.InvalidMessage;
}

pub fn encodeWindowFaceState(a: std.mem.Allocator, state: WindowFaceState, out: *std.ArrayList(u8)) !void {
    try validateWindowFaceState(state);
    var b: [window_face_state_size]u8 = [_]u8{0} ** window_face_state_size;
    std.mem.writeInt(u16, b[0..2], state.schema, .little);
    std.mem.writeInt(u64, b[4..12], state.window_id, .little);
    std.mem.writeInt(u32, b[12..16], state.frame_generation, .little);
    std.mem.writeInt(u32, b[16..20], state.face_id, .little);
    std.mem.writeInt(u32, b[20..24], state.face_generation, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeWindowFaceState(data: []const u8) Error!WindowFaceState {
    if (data.len != window_face_state_size) return Error.InvalidTable;
    const state: WindowFaceState = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .reserved = data[2],
        .flags = data[3],
        .window_id = std.mem.readInt(u64, data[4..12], .little),
        .frame_generation = std.mem.readInt(u32, data[12..16], .little),
        .face_id = std.mem.readInt(u32, data[16..20], .little),
        .face_generation = std.mem.readInt(u32, data[20..24], .little),
    };
    try validateWindowFaceState(state);
    return state;
}

fn validateWindowFaceState(state: WindowFaceState) Error!void {
    if (state.schema != 1 or state.flags != 0 or state.reserved != 0 or
        state.window_id == 0 or state.frame_generation == 0 or
        state.face_id == 0 or state.face_generation == 0)
        return Error.InvalidMessage;
}

pub fn encodeWindowScrollState(a: std.mem.Allocator, state: WindowScrollState, out: *std.ArrayList(u8)) !void {
    try validateWindowScrollState(state);
    var b: [window_scroll_state_size]u8 = [_]u8{0} ** window_scroll_state_size;
    std.mem.writeInt(u16, b[0..2], state.schema, .little);
    b[2] = state.flags;
    std.mem.writeInt(u64, b[4..12], state.window_id, .little);
    std.mem.writeInt(u32, b[12..16], state.frame_generation, .little);
    std.mem.writeInt(u32, b[16..20], state.content_size, .little);
    std.mem.writeInt(u32, b[20..24], state.viewport_size, .little);
    std.mem.writeInt(u32, b[24..28], state.position, .little);
    std.mem.writeInt(u32, b[28..32], state.track_width, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeWindowScrollState(data: []const u8) Error!WindowScrollState {
    if (data.len != window_scroll_state_size) return Error.InvalidTable;
    const state: WindowScrollState = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .window_id = std.mem.readInt(u64, data[4..12], .little),
        .frame_generation = std.mem.readInt(u32, data[12..16], .little),
        .content_size = std.mem.readInt(u32, data[16..20], .little),
        .viewport_size = std.mem.readInt(u32, data[20..24], .little),
        .position = std.mem.readInt(u32, data[24..28], .little),
        .track_width = std.mem.readInt(u32, data[28..32], .little),
        .reserved_tail = data[32..48][0..16].*,
    };
    try validateWindowScrollState(state);
    return state;
}

fn validateWindowScrollState(state: WindowScrollState) Error!void {
    if (state.schema != 1 or state.flags & ~@as(u8, WindowScrollFlags.known) != 0 or
        state.reserved != 0 or state.window_id == 0 or
        state.frame_generation == 0 or state.viewport_size == 0 or
        state.content_size < state.viewport_size or state.position > state.content_size - state.viewport_size or
        state.track_width == 0 or state.track_width > 256 or
        !std.mem.allEqual(u8, &state.reserved_tail, 0))
        return Error.InvalidMessage;
}

pub const max_tooltip_text: usize = 120;

pub const TooltipShow = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    tooltip_id: u32,
    generation: u32,
    window_id: u64,
    frame_generation: u32,
    x: i32,
    y: i32,
    max_width: u32,
    max_height: u32,
    text_length: u16 = 0,
    reserved_tail: [2]u8 = @splat(0),
    text: [max_tooltip_text]u8 = @splat(0),
};

pub const tooltip_show_size: usize = 164;

pub const TooltipMove = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    tooltip_id: u32,
    generation: u32,
    window_id: u64,
    frame_generation: u32,
    x: i32,
    y: i32,
    reserved_tail: [8]u8 = @splat(0),
};

pub const tooltip_move_size: usize = 40;

pub const TooltipHide = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    tooltip_id: u32,
    generation: u32,
    reserved_tail: [4]u8 = @splat(0),
};

pub const tooltip_hide_size: usize = 16;

fn validateTooltipIdentity(payload: anytype) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        payload.tooltip_id == 0 or payload.generation == 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0))
        return Error.InvalidMessage;
    if (comptime @hasField(@TypeOf(payload), "window_id")) {
        if (payload.window_id == 0) return Error.InvalidMessage;
    }
    if (comptime @hasField(@TypeOf(payload), "frame_generation")) {
        if (payload.frame_generation == 0) return Error.InvalidMessage;
    }
    if (comptime @hasField(@TypeOf(payload), "max_width")) {
        if (payload.max_width == 0 or payload.max_height == 0 or
            payload.max_width > 16384 or payload.max_height > 16384 or
            payload.text_length == 0 or payload.text_length > max_tooltip_text or
            !validBoundedUtf8Text(payload.text[0..payload.text_length], max_tooltip_text) or
            !std.mem.allEqual(u8, payload.text[payload.text_length..], 0))
            return Error.InvalidMessage;
    }
}

pub fn encodeTooltipShow(a: std.mem.Allocator, payload: TooltipShow, out: *std.ArrayList(u8)) !void {
    if (payload.max_width == 0 or payload.max_height == 0 or
        payload.max_width > 16384 or payload.max_height > 16384 or
        payload.text_length == 0 or payload.text_length > max_tooltip_text or
        !validBoundedUtf8Text(payload.text[0..payload.text_length], max_tooltip_text) or
        !std.mem.allEqual(u8, payload.text[payload.text_length..], 0))
        return Error.InvalidMessage;
    try validateTooltipIdentity(payload);
    var b: [tooltip_show_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    b[2] = payload.flags;
    b[3] = payload.reserved;
    std.mem.writeInt(u32, b[4..8], payload.tooltip_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.generation, .little);
    std.mem.writeInt(u64, b[12..20], payload.window_id, .little);
    std.mem.writeInt(u32, b[20..24], payload.frame_generation, .little);
    std.mem.writeInt(i32, b[24..28], payload.x, .little);
    std.mem.writeInt(i32, b[28..32], payload.y, .little);
    std.mem.writeInt(u32, b[32..36], payload.max_width, .little);
    std.mem.writeInt(u32, b[36..40], payload.max_height, .little);
    std.mem.writeInt(u16, b[40..42], payload.text_length, .little);
    @memcpy(b[44..164], payload.text[0..max_tooltip_text]);
    try out.appendSlice(a, &b);
}

fn decodeTooltipShow(data: []const u8) Error!TooltipShow {
    if (data.len != tooltip_show_size) return Error.InvalidTable;
    const payload: TooltipShow = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .tooltip_id = std.mem.readInt(u32, data[4..8], .little),
        .generation = std.mem.readInt(u32, data[8..12], .little),
        .window_id = std.mem.readInt(u64, data[12..20], .little),
        .frame_generation = std.mem.readInt(u32, data[20..24], .little),
        .x = @bitCast(std.mem.readInt(u32, data[24..28], .little)),
        .y = @bitCast(std.mem.readInt(u32, data[28..32], .little)),
        .max_width = std.mem.readInt(u32, data[32..36], .little),
        .max_height = std.mem.readInt(u32, data[36..40], .little),
        .text_length = std.mem.readInt(u16, data[40..42], .little),
        .reserved_tail = data[42..44][0..2].*,
        .text = data[44..164][0..max_tooltip_text].*,
    };
    if (payload.max_width == 0 or payload.max_height == 0 or
        payload.max_width > 16384 or payload.max_height > 16384 or
        payload.text_length == 0 or payload.text_length > max_tooltip_text or
        !validBoundedUtf8Text(payload.text[0..payload.text_length], max_tooltip_text) or
        !std.mem.allEqual(u8, payload.text[payload.text_length..], 0))
        return Error.InvalidMessage;
    try validateTooltipIdentity(payload);
    return payload;
}

pub fn encodeTooltipMove(a: std.mem.Allocator, payload: TooltipMove, out: *std.ArrayList(u8)) !void {
    try validateTooltipIdentity(payload);
    var b: [tooltip_move_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    b[2] = payload.flags;
    b[3] = payload.reserved;
    std.mem.writeInt(u32, b[4..8], payload.tooltip_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.generation, .little);
    std.mem.writeInt(u64, b[12..20], payload.window_id, .little);
    std.mem.writeInt(u32, b[20..24], payload.frame_generation, .little);
    std.mem.writeInt(i32, b[24..28], payload.x, .little);
    std.mem.writeInt(i32, b[28..32], payload.y, .little);
    try out.appendSlice(a, &b);
}

fn decodeTooltipMove(data: []const u8) Error!TooltipMove {
    if (data.len != tooltip_move_size) return Error.InvalidTable;
    const payload: TooltipMove = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .tooltip_id = std.mem.readInt(u32, data[4..8], .little),
        .generation = std.mem.readInt(u32, data[8..12], .little),
        .window_id = std.mem.readInt(u64, data[12..20], .little),
        .frame_generation = std.mem.readInt(u32, data[20..24], .little),
        .x = @bitCast(std.mem.readInt(u32, data[24..28], .little)),
        .y = @bitCast(std.mem.readInt(u32, data[28..32], .little)),
        .reserved_tail = data[32..40][0..8].*,
    };
    try validateTooltipIdentity(payload);
    return payload;
}

pub fn encodeTooltipHide(a: std.mem.Allocator, payload: TooltipHide, out: *std.ArrayList(u8)) !void {
    try validateTooltipIdentity(payload);
    var b: [tooltip_hide_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    b[2] = payload.flags;
    b[3] = payload.reserved;
    std.mem.writeInt(u32, b[4..8], payload.tooltip_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.generation, .little);
    try out.appendSlice(a, &b);
}

fn decodeTooltipHide(data: []const u8) Error!TooltipHide {
    if (data.len != tooltip_hide_size) return Error.InvalidTable;
    const payload: TooltipHide = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .tooltip_id = std.mem.readInt(u32, data[4..8], .little),
        .generation = std.mem.readInt(u32, data[8..12], .little),
        .reserved_tail = data[12..16][0..4].*,
    };
    try validateTooltipIdentity(payload);
    return payload;
}

pub const BorderSides = struct {
    pub const top: u8 = 1 << 0;
    pub const right: u8 = 1 << 1;
    pub const bottom: u8 = 1 << 2;
    pub const left: u8 = 1 << 3;
    pub const known: u8 = top | right | bottom | left;
};

pub const max_border_thickness: i32 = 64;

pub const DividerOrientation = enum(u8) {
    vertical = 1,
    horizontal = 2,
};

pub const DividerUpdate = struct {
    schema: u16 = 1,
    orientation: DividerOrientation,
    reserved: u8 = 0,
    divider_id: u32,
    divider_generation: u32,
    window_id: u64,
    position: i32,
    offset: i32,
    span: i32,
    thickness: i32,
    frame_generation: u32,
};

pub const divider_update_size: usize = 40;

pub fn dividerRect(area: DividerUpdate) Rect {
    return if (area.orientation == .vertical)
        .{ .x = area.position, .y = area.offset, .width = area.thickness, .height = area.span }
    else
        .{ .x = area.offset, .y = area.position, .width = area.span, .height = area.thickness };
}

pub fn encodeDividerUpdate(
    a: std.mem.Allocator,
    divider: DividerUpdate,
    out: *std.ArrayList(u8),
) !void {
    if (divider.schema != 1 or divider.reserved != 0 or
        divider.divider_id == 0 or divider.divider_generation == 0 or
        divider.window_id == 0 or divider.thickness <= 0 or divider.span <= 0 or
        divider.position < 0 or divider.offset < 0 or divider.frame_generation == 0)
        return Error.InvalidMessage;
    var b: [divider_update_size]u8 = [_]u8{0} ** divider_update_size;
    std.mem.writeInt(u16, b[0..2], divider.schema, .little);
    b[2] = @intFromEnum(divider.orientation);
    std.mem.writeInt(u32, b[4..8], divider.divider_id, .little);
    std.mem.writeInt(u32, b[8..12], divider.divider_generation, .little);
    std.mem.writeInt(u64, b[12..20], divider.window_id, .little);
    std.mem.writeInt(i32, b[20..24], divider.position, .little);
    std.mem.writeInt(i32, b[24..28], divider.offset, .little);
    std.mem.writeInt(i32, b[28..32], divider.span, .little);
    std.mem.writeInt(i32, b[32..36], divider.thickness, .little);
    std.mem.writeInt(u32, b[36..40], divider.frame_generation, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeDividerUpdate(data: []const u8) Error!DividerUpdate {
    if (data.len != divider_update_size) return Error.InvalidTable;
    const divider: DividerUpdate = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .orientation = switch (data[2]) {
            1 => .vertical,
            2 => .horizontal,
            else => return Error.InvalidMessage,
        },
        .reserved = data[3],
        .divider_id = std.mem.readInt(u32, data[4..8], .little),
        .divider_generation = std.mem.readInt(u32, data[8..12], .little),
        .window_id = std.mem.readInt(u64, data[12..20], .little),
        .position = @bitCast(std.mem.readInt(u32, data[20..24], .little)),
        .offset = @bitCast(std.mem.readInt(u32, data[24..28], .little)),
        .span = @bitCast(std.mem.readInt(u32, data[28..32], .little)),
        .thickness = @bitCast(std.mem.readInt(u32, data[32..36], .little)),
        .frame_generation = std.mem.readInt(u32, data[36..40], .little),
    };
    if (divider.schema != 1 or divider.reserved != 0 or
        divider.divider_id == 0 or divider.divider_generation == 0 or
        divider.window_id == 0 or divider.thickness <= 0 or divider.span <= 0 or
        divider.position < 0 or divider.offset < 0 or divider.frame_generation == 0)
        return Error.InvalidMessage;
    return divider;
}

pub const BorderUpdate = struct {
    schema: u16 = 1,
    sides: u8,
    reserved: u8 = 0,
    thickness: u32,
    color: [4]u8,
    frame_generation: u32,
};

pub const border_update_size: usize = 16;

pub fn encodeBorderUpdate(
    a: std.mem.Allocator,
    border: BorderUpdate,
    out: *std.ArrayList(u8),
) !void {
    if (border.schema != 1 or border.reserved != 0 or
        border.sides == 0 or border.sides & ~@as(u8, BorderSides.known) != 0 or
        border.thickness == 0 or border.thickness > max_border_thickness or
        border.color[3] == 0 or border.frame_generation == 0)
        return Error.InvalidMessage;
    var bytes: [border_update_size]u8 = [_]u8{0} ** border_update_size;
    std.mem.writeInt(u16, bytes[0..2], border.schema, .little);
    bytes[2] = border.sides;
    bytes[3] = border.reserved;
    std.mem.writeInt(u32, bytes[4..8], border.thickness, .little);
    @memcpy(bytes[8..12], &border.color);
    std.mem.writeInt(u32, bytes[12..16], border.frame_generation, .little);
    try out.appendSlice(a, &bytes);
}

pub fn decodeBorderUpdate(data: []const u8) Error!BorderUpdate {
    if (data.len != border_update_size) return Error.InvalidTable;
    const border: BorderUpdate = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .sides = data[2],
        .reserved = data[3],
        .thickness = std.mem.readInt(u32, data[4..8], .little),
        .color = data[8..12][0..4].*,
        .frame_generation = std.mem.readInt(u32, data[12..16], .little),
    };
    if (border.schema != 1 or border.reserved != 0 or
        border.sides == 0 or border.sides & ~@as(u8, BorderSides.known) != 0 or
        border.thickness == 0 or border.thickness > max_border_thickness or
        border.color[3] == 0 or border.frame_generation == 0)
        return Error.InvalidMessage;
    return border;
}

pub const image_placement_record_size: usize = 64;
pub const image_placement_schema: u16 = 1;
pub const image_placement_kind: u8 = 3;

pub const FaceResource = struct {
    face_id: u32,
    generation: u32,
    payload: protocol.FaceDefine,
};

pub const FaceResourceCounters = struct {
    defines: u64 = 0,
    replacements: u64 = 0,
    deletes: u64 = 0,
    rejections: u64 = 0,
};

/// Faces are protocol-global bounded resources.  Unlike strings, they remain
/// available after a frame destroy so a new frame can reference the same face
/// generation; explicit deletion, session resync, or scene deinit removes them.
pub const FaceResources = struct {
    faces: [max_face_resources]FaceResource = undefined,
    len: usize = 0,
    counters: FaceResourceCounters = .{},

    fn find(self: FaceResources, face_id: u32) ?usize {
        for (self.faces[0..self.len], 0..) |resource, index| {
            if (resource.face_id == face_id) return index;
        }
        return null;
    }

    pub fn lookup(self: FaceResources, face_id: u32) ?FaceResource {
        const index = self.find(face_id) orelse return null;
        return self.faces[index];
    }

    fn define(
        self: *FaceResources,
        resources: *lifecycle.ResourceRegistry,
        payload: protocol.FaceDefine,
    ) Error!void {
        const existing_index = self.find(payload.face_id);
        if (existing_index) |index| {
            if (payload.generation <= self.faces[index].generation) {
                self.counters.rejections += 1;
                return Error.StaleGeneration;
            }
        } else if (self.len == max_face_resources or resources.len == lifecycle.max_resources) {
            self.counters.rejections += 1;
            return Error.ResourceTableFull;
        }

        // The wire record and scene value are allocation-free.  Registry
        // validation is the only fallible step; table replacement cannot fail.
        try resources.declareAll(&[_]lifecycle.Resource{.{
            .kind = .face,
            .id = payload.face_id,
            .generation = payload.generation,
            .status = .live,
        }});

        if (existing_index) |index| {
            self.faces[index] = .{ .face_id = payload.face_id, .generation = payload.generation, .payload = payload };
            self.counters.replacements += 1;
        } else {
            self.faces[self.len] = .{ .face_id = payload.face_id, .generation = payload.generation, .payload = payload };
            self.len += 1;
            self.counters.defines += 1;
        }
    }

    fn delete(
        self: *FaceResources,
        resources: *lifecycle.ResourceRegistry,
        payload: protocol.FaceDelete,
    ) Error!void {
        const index = self.find(payload.face_id) orelse {
            self.counters.rejections += 1;
            return Error.ResourceNotLive;
        };
        if (self.faces[index].generation != payload.generation) {
            self.counters.rejections += 1;
            return Error.StaleGeneration;
        }
        try resources.delete(.face, payload.face_id, payload.generation);
        if (index + 1 < self.len) {
            std.mem.copyForwards(FaceResource, self.faces[index .. self.len - 1], self.faces[index + 1 .. self.len]);
        }
        self.len -= 1;
        self.counters.deletes += 1;
    }
};

pub const FringeBitmapResource = struct {
    bitmap_id: u32,
    generation: u32,
    payload: protocol.FringeBitmapDefine,
};

pub const FringeBitmapResourceCounters = struct {
    defines: u64 = 0,
    replacements: u64 = 0,
    deletes: u64 = 0,
    rejections: u64 = 0,
};

pub const FringeBitmapResources = struct {
    bitmaps: [max_fringe_bitmaps]FringeBitmapResource = undefined,
    len: usize = 0,
    counters: FringeBitmapResourceCounters = .{},

    fn find(self: FringeBitmapResources, bitmap_id: u32) ?usize {
        for (self.bitmaps[0..self.len], 0..) |resource, index| {
            if (resource.bitmap_id == bitmap_id) return index;
        }
        return null;
    }

    pub fn lookup(self: FringeBitmapResources, bitmap_id: u32) ?FringeBitmapResource {
        const index = self.find(bitmap_id) orelse return null;
        return self.bitmaps[index];
    }

    fn define(
        self: *FringeBitmapResources,
        resources: *lifecycle.ResourceRegistry,
        payload: protocol.FringeBitmapDefine,
    ) Error!void {
        const existing_index = self.find(payload.bitmap_id);
        if (existing_index) |index| {
            if (payload.generation <= self.bitmaps[index].generation) {
                self.counters.rejections += 1;
                return Error.StaleGeneration;
            }
        } else if (self.len == max_fringe_bitmaps or resources.len == lifecycle.max_resources) {
            self.counters.rejections += 1;
            return Error.ResourceTableFull;
        }

        try resources.declareAll(&[_]lifecycle.Resource{.{
            .kind = .fringe_bitmap,
            .id = payload.bitmap_id,
            .generation = payload.generation,
            .status = .live,
        }});

        if (existing_index) |index| {
            self.bitmaps[index] = .{
                .bitmap_id = payload.bitmap_id,
                .generation = payload.generation,
                .payload = payload,
            };
            self.counters.replacements += 1;
        } else {
            self.bitmaps[self.len] = .{
                .bitmap_id = payload.bitmap_id,
                .generation = payload.generation,
                .payload = payload,
            };
            self.len += 1;
            self.counters.defines += 1;
        }
    }

    fn delete(
        self: *FringeBitmapResources,
        resources: *lifecycle.ResourceRegistry,
        payload: protocol.FringeBitmapDelete,
    ) Error!void {
        const index = self.find(payload.bitmap_id) orelse {
            self.counters.rejections += 1;
            return Error.ResourceNotLive;
        };
        if (self.bitmaps[index].generation != payload.generation) {
            self.counters.rejections += 1;
            return Error.StaleGeneration;
        }
        try resources.delete(.fringe_bitmap, payload.bitmap_id, payload.generation);
        if (index + 1 < self.len) {
            std.mem.copyForwards(FringeBitmapResource, self.bitmaps[index .. self.len - 1], self.bitmaps[index + 1 .. self.len]);
        }
        self.len -= 1;
        self.counters.deletes += 1;
    }
};

pub fn fringeBitmapBit(payload: protocol.FringeBitmapDefine, x: usize, y: usize) bool {
    if (x >= payload.width or y >= payload.height) return false;
    const stride = (protocol.max_fringe_bitmap_dimension + 7) / 8;
    const byte = payload.bits[y * stride + x / 8];
    return byte & (@as(u8, 1) << @intCast(7 - x % 8)) != 0;
}

pub const StringResource = struct {
    resource_id: u32,
    generation: u32,
    bytes: []u8,
};

pub const StringResourceCounters = struct {
    defines: u64 = 0,
    replacements: u64 = 0,
    deletes: u64 = 0,
    rejections: u64 = 0,
};

pub const StringResources = struct {
    strings: [max_string_resources]StringResource = undefined,
    len: usize = 0,
    counters: StringResourceCounters = .{},

    fn find(self: StringResources, resource_id: u32) ?usize {
        for (self.strings[0..self.len], 0..) |resource, index| {
            if (resource.resource_id == resource_id) return index;
        }
        return null;
    }

    pub fn lookup(self: StringResources, resource_id: u32) ?StringResource {
        const index = self.find(resource_id) orelse return null;
        return self.strings[index];
    }

    fn define(
        self: *StringResources,
        allocator: std.mem.Allocator,
        resources: *lifecycle.ResourceRegistry,
        payload: protocol.StringDefine,
    ) Error!void {
        const existing_index = self.find(payload.resource_id);
        if (existing_index) |index| {
            if (payload.generation <= self.strings[index].generation) {
                self.counters.rejections += 1;
                return Error.StaleGeneration;
            }
        }

        // Allocate the only new owner before either registry or scene table
        // mutation.  Every later failure leaves the previous payload active.
        const owned = try allocator.dupe(u8, payload.bytes);
        errdefer allocator.free(owned);

        try resources.declareAll(&[_]lifecycle.Resource{.{
            .kind = .string,
            .id = payload.resource_id,
            .generation = payload.generation,
            .status = .live,
        }});

        if (existing_index) |index| {
            const old = self.strings[index];
            allocator.free(old.bytes);
            self.strings[index] = .{
                .resource_id = payload.resource_id,
                .generation = payload.generation,
                .bytes = owned,
            };
            self.counters.replacements += 1;
        } else {
            self.strings[self.len] = .{
                .resource_id = payload.resource_id,
                .generation = payload.generation,
                .bytes = owned,
            };
            self.len += 1;
            self.counters.defines += 1;
        }
    }

    fn delete(
        self: *StringResources,
        allocator: std.mem.Allocator,
        resources: *lifecycle.ResourceRegistry,
        payload: protocol.StringDelete,
    ) Error!void {
        const index = self.find(payload.resource_id) orelse {
            self.counters.rejections += 1;
            return Error.ResourceNotLive;
        };
        if (self.strings[index].generation != payload.generation) {
            self.counters.rejections += 1;
            return Error.StaleGeneration;
        }
        try resources.delete(.string, payload.resource_id, payload.generation);
        allocator.free(self.strings[index].bytes);
        if (index + 1 < self.len) {
            std.mem.copyForwards(StringResource, self.strings[index .. self.len - 1], self.strings[index + 1 .. self.len]);
        }
        self.len -= 1;
        self.counters.deletes += 1;
    }

    fn clear(self: *StringResources, allocator: std.mem.Allocator) void {
        for (self.strings[0..self.len]) |resource| allocator.free(resource.bytes);
        self.* = .{};
    }

    fn deinit(self: *StringResources, allocator: std.mem.Allocator) void {
        self.clear(allocator);
    }
};

pub const FontResource = struct {
    font_id: u32,
    generation: u32,
    payload: protocol.FontDefine,
};

pub const FontResourceCounters = struct {
    defines: u64 = 0,
    replacements: u64 = 0,
    deletes: u64 = 0,
    rejections: u64 = 0,
};

/// Fonts are protocol-global bounded resources.  They survive frame destroy
/// so a replacement frame can reference the same descriptor; explicit
/// deletion, authenticated resync, or scene teardown removes them.
pub const FontResources = struct {
    fonts: [max_font_resources]FontResource = undefined,
    len: usize = 0,
    counters: FontResourceCounters = .{},

    fn find(self: FontResources, font_id: u32) ?usize {
        for (self.fonts[0..self.len], 0..) |resource, index| {
            if (resource.font_id == font_id) return index;
        }
        return null;
    }

    pub fn lookup(self: FontResources, font_id: u32) ?FontResource {
        const index = self.find(font_id) orelse return null;
        return self.fonts[index];
    }

    fn define(
        self: *FontResources,
        resources: *lifecycle.ResourceRegistry,
        payload: protocol.FontDefine,
    ) Error!void {
        const existing_index = self.find(payload.font_id);
        if (existing_index) |index| {
            if (payload.generation <= self.fonts[index].generation) {
                self.counters.rejections += 1;
                return Error.StaleGeneration;
            }
        } else if (self.len == max_font_resources or resources.len == lifecycle.max_resources) {
            self.counters.rejections += 1;
            return Error.ResourceTableFull;
        }

        // The wire record is copied by value.  Registry validation is the only
        // fallible step; the scene table replacement cannot fail or leak.
        try resources.declareAll(&[_]lifecycle.Resource{.{
            .kind = .font,
            .id = payload.font_id,
            .generation = payload.generation,
            .status = .live,
        }});

        if (existing_index) |index| {
            self.fonts[index] = .{
                .font_id = payload.font_id,
                .generation = payload.generation,
                .payload = payload,
            };
            self.counters.replacements += 1;
        } else {
            self.fonts[self.len] = .{
                .font_id = payload.font_id,
                .generation = payload.generation,
                .payload = payload,
            };
            self.len += 1;
            self.counters.defines += 1;
        }
    }

    fn delete(
        self: *FontResources,
        resources: *lifecycle.ResourceRegistry,
        payload: protocol.FontDelete,
    ) Error!void {
        const index = self.find(payload.font_id) orelse {
            self.counters.rejections += 1;
            return Error.ResourceNotLive;
        };
        if (self.fonts[index].generation != payload.generation) {
            self.counters.rejections += 1;
            return Error.StaleGeneration;
        }
        try resources.delete(.font, payload.font_id, payload.generation);
        if (index + 1 < self.len) {
            std.mem.copyForwards(FontResource, self.fonts[index .. self.len - 1], self.fonts[index + 1 .. self.len]);
        }
        self.len -= 1;
        self.counters.deletes += 1;
    }
};

pub const ImageResource = struct {
    image_id: u32,
    generation: u32,
    metadata: protocol.ImageDefine,
    bytes: []u8 = &.{},
    bytes_received: usize = 0,
    fragments_received: u16 = 0,
    complete: bool = false,
};

pub const ImageResourceCounters = struct {
    defines: u64 = 0,
    replacements: u64 = 0,
    complete: u64 = 0,
    deletes: u64 = 0,
    rejections: u64 = 0,
};

/// Images are protocol-global bounded resources.  They survive frame destroy
/// so a replacement frame can reference the same pixel generation; explicit
/// deletion, authenticated resync, or scene teardown removes them.
pub const ImageResources = struct {
    images: [max_image_resources]ImageResource = undefined,
    len: usize = 0,
    declared_bytes: usize = 0,
    counters: ImageResourceCounters = .{},

    fn find(self: ImageResources, image_id: u32) ?usize {
        for (self.images[0..self.len], 0..) |resource, index| {
            if (resource.image_id == image_id) return index;
        }
        return null;
    }

    pub fn lookup(self: ImageResources, image_id: u32) ?ImageResource {
        const index = self.find(image_id) orelse return null;
        return self.images[index];
    }

    fn define(
        self: *ImageResources,
        allocator: std.mem.Allocator,
        resources: *lifecycle.ResourceRegistry,
        metadata: protocol.ImageDefine,
    ) Error!void {
        const existing_index = self.find(metadata.image_id);
        if (existing_index) |index| {
            if (metadata.generation <= self.images[index].generation) {
                self.counters.rejections += 1;
                return Error.StaleGeneration;
            }
        }

        const existing_declared = if (existing_index) |index| self.images[index].metadata.total_byte_count else 0;
        const next_declared = self.declared_bytes - existing_declared + metadata.total_byte_count;
        if (next_declared > protocol.max_image_bytes) {
            self.counters.rejections += 1;
            return Error.ResourcePayloadBudgetExceeded;
        }
        if (existing_index == null and
            (self.len == max_image_resources or resources.len == lifecycle.max_resources))
        {
            self.counters.rejections += 1;
            return Error.ResourceTableFull;
        }

        try resources.declareAll(&[_]lifecycle.Resource{.{
            .kind = .image,
            .id = metadata.image_id,
            .generation = metadata.generation,
            .status = .live,
        }});

        if (existing_index) |index| {
            allocator.free(self.images[index].bytes);
            self.images[index] = .{
                .image_id = metadata.image_id,
                .generation = metadata.generation,
                .metadata = metadata,
            };
            self.counters.replacements += 1;
        } else {
            self.images[self.len] = .{
                .image_id = metadata.image_id,
                .generation = metadata.generation,
                .metadata = metadata,
            };
            self.len += 1;
            self.counters.defines += 1;
        }
        self.declared_bytes = next_declared;
    }

    fn data(
        self: *ImageResources,
        allocator: std.mem.Allocator,
        payload: protocol.ImageData,
    ) Error!void {
        const index = self.find(payload.image_id) orelse {
            self.counters.rejections += 1;
            return Error.ResourceNotLive;
        };
        const image = &self.images[index];
        if (image.generation != payload.generation) {
            self.counters.rejections += 1;
            return Error.StaleGeneration;
        }
        if (payload.fragment_index != image.fragments_received) {
            self.counters.rejections += 1;
            return Error.InvalidSequence;
        }
        const fragment_len = payload.bytes.len;
        if (@as(u64, image.fragments_received) + 1 > payload.fragment_count) {
            self.counters.rejections += 1;
            return Error.InvalidSequence;
        }
        const next_received: u64 = @as(u64, image.bytes_received) + fragment_len;
        if (fragment_len > image.metadata.total_byte_count or
            next_received > image.metadata.total_byte_count)
        {
            self.counters.rejections += 1;
            return Error.ResourcePayloadTooLarge;
        }
        const is_final = @as(u64, image.fragments_received) + 1 == payload.fragment_count;
        if (is_final and next_received != image.metadata.total_byte_count) {
            self.counters.rejections += 1;
            return Error.InvalidMessage;
        }
        if (image.bytes.len == 0 and image.fragments_received == 0 and !image.complete) {
            image.bytes = allocator.alloc(u8, image.metadata.total_byte_count) catch {
                self.counters.rejections += 1;
                return Error.OutOfMemory;
            };
        }

        const copy_start = image.bytes_received;
        @memcpy(image.bytes[copy_start..][0..fragment_len], payload.bytes);
        image.bytes_received = copy_start + fragment_len;
        image.fragments_received += 1;

        if (is_final) {
            image.complete = true;
            self.counters.complete += 1;
        }
    }

    fn delete(
        self: *ImageResources,
        allocator: std.mem.Allocator,
        resources: *lifecycle.ResourceRegistry,
        payload: protocol.ImageDelete,
    ) Error!void {
        const index = self.find(payload.image_id) orelse {
            self.counters.rejections += 1;
            return Error.ResourceNotLive;
        };
        if (self.images[index].generation != payload.generation) {
            self.counters.rejections += 1;
            return Error.StaleGeneration;
        }
        try resources.delete(.image, payload.image_id, payload.generation);
        self.declared_bytes -= self.images[index].metadata.total_byte_count;
        allocator.free(self.images[index].bytes);
        if (index + 1 < self.len) {
            std.mem.copyForwards(ImageResource, self.images[index .. self.len - 1], self.images[index + 1 .. self.len]);
        }
        self.len -= 1;
        self.counters.deletes += 1;
    }

    fn clear(self: *ImageResources, allocator: std.mem.Allocator) void {
        for (self.images[0..self.len]) |resource| allocator.free(resource.bytes);
        self.* = .{};
    }
};

pub const AtlasGlyphPixels = struct {
    bytes: []const u8,
    cache_key: u64,
    cache_revision: u32,
    atlas_id: u32,
    page_index: u16,
    generation: u32,
    page_width: u16,
    page_height: u16,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    advance_x: u16,
};

pub const AtlasPage = struct {
    page_index: u16 = 0,
    revision: u32 = 0,
    x: u16 = 0,
    y: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,
    bytes: []u8 = &.{},
};

pub const AtlasGlyph = struct {
    glyph_id: u32,
    font_id: u32,
    size_px: u16,
    variation_hash: u64,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    baseline: u16,
    advance_x: u16,
};

pub const AtlasState = struct {
    atlas_id: u32,
    generation: u32,
    width: u32,
    height: u32,
    page_count: u16,
    page_revision: u32 = 0,
    pages: []AtlasPage = &.{},
    glyphs: std.ArrayList(AtlasGlyph) = .empty,

    fn deinit(self: *AtlasState, allocator: std.mem.Allocator) void {
        for (self.pages) |page| allocator.free(page.bytes);
        if (self.pages.len != 0) allocator.free(self.pages);
        self.glyphs.deinit(allocator);
        self.* = .{
            .atlas_id = self.atlas_id,
            .generation = self.generation,
            .width = self.width,
            .height = self.height,
            .page_count = self.page_count,
        };
    }
};

pub const AtlasResources = struct {
    allocator: std.mem.Allocator,
    atlases: std.ArrayList(AtlasState) = .empty,

    pub fn init(allocator: std.mem.Allocator) AtlasResources {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *AtlasResources) void {
        for (self.atlases.items) |*atlas| atlas.deinit(self.allocator);
        self.atlases.deinit(self.allocator);
        self.* = AtlasResources.init(self.allocator);
    }

    fn find(self: *AtlasResources, atlas_id: u32) ?*AtlasState {
        for (self.atlases.items) |*atlas| {
            if (atlas.atlas_id == atlas_id) return atlas;
        }
        return null;
    }

    pub fn first(self: *const AtlasResources) ?*const AtlasState {
        return if (self.atlases.items.len != 0) &self.atlases.items[0] else null;
    }

    pub fn lookup(self: *const AtlasResources, atlas_id: u32) ?*const AtlasState {
        for (self.atlases.items) |*atlas| {
            if (atlas.atlas_id == atlas_id) return atlas;
        }
        return null;
    }

    pub fn findGlyphPixels(
        self: *const AtlasResources,
        font_hint: u32,
        glyph_id: u32,
    ) ?AtlasGlyphPixels {
        for (self.atlases.items) |*atlas| {
            for (atlas.glyphs.items) |glyph| {
                if (glyph.glyph_id != glyph_id) continue;
                if (font_hint != 0 and glyph.font_id != font_hint) continue;
                for (atlas.pages) |*page| {
                    if (page.bytes.len == 0) continue;
                    if (glyph.x < page.x or glyph.y < page.y or
                        glyph.x + glyph.width > page.x + page.width or
                        glyph.y + glyph.height > page.y + page.height) continue;
                    var key_hasher = std.hash.Wyhash.init(0);
                    key_hasher.update(std.mem.asBytes(&atlas.atlas_id));
                    key_hasher.update(std.mem.asBytes(&page.page_index));
                    key_hasher.update(std.mem.asBytes(&atlas.generation));
                    key_hasher.update(std.mem.asBytes(&page.revision));
                    const cache_key = key_hasher.final();
                    return .{
                        .bytes = page.bytes,
                        .cache_key = cache_key,
                        .cache_revision = page.revision,
                        .atlas_id = atlas.atlas_id,
                        .page_index = page.page_index,
                        .generation = atlas.generation,
                        .page_width = page.width,
                        .page_height = page.height,
                        .x = glyph.x - page.x,
                        .y = glyph.y - page.y,
                        .width = glyph.width,
                        .height = glyph.height,
                        .advance_x = glyph.advance_x,
                    };
                }
            }
        }
        return null;
    }

    pub fn applyDefine(self: *AtlasResources, payload: protocol.AtlasDefine) Error!void {
        if (self.atlases.items.len == max_atlas_resources) return Error.ResourceTableFull;
        for (self.atlases.items) |atlas| {
            if (atlas.atlas_id == payload.atlas_id) return Error.DuplicateResource;
        }
        const pages = try self.allocator.alloc(AtlasPage, payload.page_count);
        errdefer self.allocator.free(pages);
        for (pages, 0..) |*page, index| page.* = .{ .page_index = @intCast(index) };

        try self.atlases.append(self.allocator, .{
            .atlas_id = payload.atlas_id,
            .generation = payload.generation,
            .width = payload.width,
            .height = payload.height,
            .page_count = payload.page_count,
            .pages = pages,
        });
    }

    pub fn applyPageUpdate(self: *AtlasResources, payload: protocol.AtlasPageUpdate) Error!void {
        const atlas = self.find(payload.atlas_id) orelse return Error.ResourceNotLive;
        if (atlas.generation != payload.generation or
            atlas.page_count != payload.page_count or
            @as(u32, payload.x) + payload.width > atlas.width or
            @as(u32, payload.y) + payload.height > atlas.height) return Error.InvalidMessage;
        const bytes = try self.allocator.dupe(u8, payload.bytes);
        errdefer self.allocator.free(bytes);
        const page = &atlas.pages[payload.page_index];
        if (page.bytes.len != 0) self.allocator.free(page.bytes);
        atlas.page_revision +%= 1;
        page.* = .{
            .page_index = payload.page_index,
            .revision = atlas.page_revision,
            .x = payload.x,
            .y = payload.y,
            .width = payload.width,
            .height = payload.height,
            .bytes = bytes,
        };
    }

    pub fn applyGlyphAdd(self: *AtlasResources, payload: protocol.AtlasGlyphAdd) Error!void {
        const atlas = self.find(payload.atlas_id) orelse return Error.ResourceNotLive;
        if (atlas.generation != payload.generation or
            @as(u32, payload.x) + payload.width > atlas.width or
            @as(u32, payload.y) + payload.height > atlas.height) return Error.InvalidMessage;
        for (atlas.glyphs.items) |glyph| {
            if (glyph.glyph_id == payload.glyph_id and glyph.font_id == payload.font_id)
                return Error.DuplicateResource;
        }
        if (atlas.glyphs.items.len == protocol.max_atlas_glyphs) return Error.ResourceTableFull;
        try atlas.glyphs.append(self.allocator, .{
            .glyph_id = payload.glyph_id,
            .font_id = payload.font_id,
            .size_px = payload.size_px,
            .variation_hash = payload.variation_hash,
            .x = payload.x,
            .y = payload.y,
            .width = payload.width,
            .height = payload.height,
            .baseline = payload.baseline,
            .advance_x = payload.advance_x,
        });
    }

    pub fn applyInvalidate(self: *AtlasResources, payload: protocol.AtlasInvalidate) Error!void {
        const atlas = self.find(payload.atlas_id) orelse return Error.ResourceNotLive;
        if (atlas.generation != payload.generation) return Error.StaleGeneration;
        if (payload.flags & protocol.AtlasInvalidateFlags.all != 0) {
            for (atlas.pages) |*page| {
                if (page.bytes.len != 0) self.allocator.free(page.bytes);
                atlas.page_revision +%= 1;
                page.* = .{ .page_index = page.page_index, .revision = atlas.page_revision };
            }
            atlas.glyphs.clearRetainingCapacity();
            return;
        }
        if (payload.flags & protocol.AtlasInvalidateFlags.page != 0) {
            if (payload.target >= atlas.page_count) return Error.InvalidMessage;
            const page = &atlas.pages[payload.target];
            if (page.bytes.len != 0) self.allocator.free(page.bytes);
            atlas.page_revision +%= 1;
            page.* = .{ .page_index = page.page_index, .revision = atlas.page_revision };
            return;
        }
        var index: usize = 0;
        while (index < atlas.glyphs.items.len) {
            if (atlas.glyphs.items[index].glyph_id == payload.target) {
                _ = atlas.glyphs.orderedRemove(index);
            } else index += 1;
        }
    }

    fn clear(self: *AtlasResources) void {
        for (self.atlases.items) |*atlas| atlas.deinit(self.allocator);
        self.atlases.clearRetainingCapacity();
    }
};

fn putU16(out: *std.ArrayList(u8), a: std.mem.Allocator, value: u16) !void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, value, .little);
    try out.appendSlice(a, &bytes);
}

fn putI16(out: *std.ArrayList(u8), a: std.mem.Allocator, value: i16) !void {
    try putU16(out, a, @bitCast(value));
}

fn putU32(out: *std.ArrayList(u8), a: std.mem.Allocator, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    try out.appendSlice(a, &bytes);
}

fn putI32(out: *std.ArrayList(u8), a: std.mem.Allocator, value: i32) !void {
    try putU32(out, a, @bitCast(value));
}

fn putU64(out: *std.ArrayList(u8), a: std.mem.Allocator, value: u64) !void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    try out.appendSlice(a, &bytes);
}

const Reader = struct {
    bytes: []const u8,
    offset: usize = 0,

    fn readU16(self: *Reader) Error!u16 {
        if (self.bytes.len - self.offset < 2) return Error.InvalidTable;
        const value = std.mem.readInt(u16, self.bytes[self.offset..][0..2], .little);
        self.offset += 2;
        return value;
    }

    fn readU32(self: *Reader) Error!u32 {
        if (self.bytes.len - self.offset < 4) return Error.InvalidTable;
        const value = std.mem.readInt(u32, self.bytes[self.offset..][0..4], .little);
        self.offset += 4;
        return value;
    }

    fn readI32(self: *Reader) Error!i32 {
        return @bitCast(try self.readU32());
    }

    fn readU64(self: *Reader) Error!u64 {
        if (self.bytes.len - self.offset < 8) return Error.InvalidTable;
        const value = std.mem.readInt(u64, self.bytes[self.offset..][0..8], .little);
        self.offset += 8;
        return value;
    }

    fn readByte(self: *Reader) Error!u8 {
        if (self.bytes.len == self.offset) return Error.InvalidTable;
        const value = self.bytes[self.offset];
        self.offset += 1;
        return value;
    }

    fn skip(self: *Reader, count: usize) Error!void {
        if (self.bytes.len - self.offset < count) return Error.InvalidTable;
        self.offset += count;
    }

    fn expectZeros(self: *Reader, count: usize) Error!void {
        const start = self.offset;
        try self.skip(count);
        for (self.bytes[start..self.offset]) |byte| {
            if (byte != 0) return Error.InvalidTable;
        }
    }
};

pub fn encodeWindow(a: std.mem.Allocator, window: Window, out: *std.ArrayList(u8)) !void {
    if (!window.valid()) return Error.InvalidMessage;
    try putU64(out, a, window.id);
    try putU32(out, a, window.frame_id);
    try putI32(out, a, window.x);
    try putI32(out, a, window.y);
    try putI32(out, a, window.width);
    try putI32(out, a, window.height);
    try out.appendNTimes(a, 0, 12);
}

pub fn decodeWindow(bytes: []const u8) Error!Window {
    if (bytes.len != window_record_size) return Error.InvalidTable;
    var reader: Reader = .{ .bytes = bytes };
    const window: Window = .{
        .id = try reader.readU64(),
        .frame_id = try reader.readU32(),
        .x = try reader.readI32(),
        .y = try reader.readI32(),
        .width = try reader.readI32(),
        .height = try reader.readI32(),
    };
    try reader.expectZeros(12);
    if (!window.valid()) return Error.InvalidMessage;
    return window;
}

pub fn encodeRow(a: std.mem.Allocator, row: Row, out: *std.ArrayList(u8)) !void {
    if (!row.valid()) return Error.InvalidMessage;
    try putU64(out, a, row.window_id);
    try putU32(out, a, row.index);
    try putU32(out, a, row.flags);
    try putI32(out, a, row.x);
    try putI32(out, a, row.y);
    try putI32(out, a, row.width);
    try putI32(out, a, row.height);
    try putI32(out, a, row.ascent);
    try putI32(out, a, row.descent);
    try putI32(out, a, row.baseline);
    try putI32(out, a, row.visible_height);
    try out.appendNTimes(a, 0, 8);
}

pub fn decodeRow(bytes: []const u8) Error!Row {
    if (bytes.len != row_record_size) return Error.InvalidTable;
    var reader: Reader = .{ .bytes = bytes };
    const row: Row = .{
        .window_id = try reader.readU64(),
        .index = try reader.readU32(),
        .flags = try reader.readU32(),
        .x = try reader.readI32(),
        .y = try reader.readI32(),
        .width = try reader.readI32(),
        .height = try reader.readI32(),
        .ascent = try reader.readI32(),
        .descent = try reader.readI32(),
        .baseline = try reader.readI32(),
        .visible_height = try reader.readI32(),
    };
    try reader.expectZeros(8);
    if (!row.valid()) return Error.InvalidMessage;
    return row;
}

pub const update_boundary_size: usize = 12;
pub const update_boundary_schema: u16 = 1;

pub const UpdateBoundary = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    frame_generation: u32,
    update_id: u32,
};

pub fn encodeUpdateBoundary(
    a: std.mem.Allocator,
    kind: u16,
    boundary: UpdateBoundary,
    out: *std.ArrayList(u8),
) !void {
    if (kind != protocol.Message.begin_update and kind != protocol.Message.end_update)
        return Error.InvalidMessage;
    if (boundary.schema != 1 or boundary.flags != 0 or boundary.reserved != 0 or
        boundary.frame_generation == 0 or boundary.update_id == 0)
        return Error.InvalidMessage;
    var b: [update_boundary_size]u8 = [_]u8{0} ** update_boundary_size;
    std.mem.writeInt(u16, b[0..2], boundary.schema, .little);
    b[2] = boundary.flags;
    b[3] = boundary.reserved;
    std.mem.writeInt(u32, b[4..8], boundary.frame_generation, .little);
    std.mem.writeInt(u32, b[8..12], boundary.update_id, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeUpdateBoundary(data: []const u8) Error!UpdateBoundary {
    if (data.len != update_boundary_size) return Error.InvalidTable;
    const boundary: UpdateBoundary = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .frame_generation = std.mem.readInt(u32, data[4..8], .little),
        .update_id = std.mem.readInt(u32, data[8..12], .little),
    };
    if (boundary.schema != 1 or boundary.flags != 0 or boundary.reserved != 0 or
        boundary.frame_generation == 0 or boundary.update_id == 0)
        return Error.InvalidMessage;
    return boundary;
}

pub const row_snapshot_header_size: usize = 8;
pub const row_snapshot_size: usize = row_snapshot_header_size + row_record_size;
pub const row_delete_size: usize = 24;
pub const row_snapshot_schema: u16 = 1;

fn encodeRowHeader(a: std.mem.Allocator, frame_generation: u32, row: Row, out: *std.ArrayList(u8)) !void {
    if (frame_generation == 0 or !row.valid()) return Error.InvalidMessage;
    var header: [row_snapshot_header_size]u8 = [_]u8{0} ** row_snapshot_header_size;
    std.mem.writeInt(u16, header[0..2], row_snapshot_schema, .little);
    std.mem.writeInt(u32, header[4..8], frame_generation, .little);
    try out.appendSlice(a, &header);
    try encodeRow(a, row, out);
}

pub fn encodeRowSnapshot(a: std.mem.Allocator, frame_generation: u32, row: Row, out: *std.ArrayList(u8)) !void {
    try encodeRowHeader(a, frame_generation, row, out);
}

pub fn encodeRowUpdate(a: std.mem.Allocator, frame_generation: u32, row: Row, out: *std.ArrayList(u8)) !void {
    try encodeRowHeader(a, frame_generation, row, out);
}

pub fn decodeRowSnapshot(data: []const u8) Error!struct { frame_generation: u32, row: Row } {
    if (data.len != row_snapshot_size) return Error.InvalidTable;
    var reader: Reader = .{ .bytes = data };
    if (try reader.readU16() != row_snapshot_schema) return Error.InvalidTable;
    try reader.expectZeros(2);
    const frame_generation = try reader.readU32();
    const row = try decodeRow(data[row_snapshot_header_size..]);
    if (frame_generation == 0 or row.window_id == 0) return Error.InvalidMessage;
    return .{ .frame_generation = frame_generation, .row = row };
}

pub const RowDelete = struct {
    frame_generation: u32,
    window_id: u64,
    row_index: u32,
};

pub fn encodeRowDelete(a: std.mem.Allocator, delete: RowDelete, out: *std.ArrayList(u8)) !void {
    if (delete.frame_generation == 0 or delete.window_id == 0 or delete.row_index > protocol.max_rows)
        return Error.InvalidMessage;
    var bytes: [row_delete_size]u8 = [_]u8{0} ** row_delete_size;
    std.mem.writeInt(u16, bytes[0..2], row_snapshot_schema, .little);
    std.mem.writeInt(u32, bytes[4..8], delete.frame_generation, .little);
    std.mem.writeInt(u64, bytes[8..16], delete.window_id, .little);
    std.mem.writeInt(u32, bytes[16..20], delete.row_index, .little);
    try out.appendSlice(a, &bytes);
}

pub fn decodeRowDelete(data: []const u8) Error!RowDelete {
    if (data.len != row_delete_size) return Error.InvalidTable;
    var reader: Reader = .{ .bytes = data };
    if (try reader.readU16() != row_snapshot_schema) return Error.InvalidTable;
    try reader.expectZeros(2);
    const delete: RowDelete = .{
        .frame_generation = try reader.readU32(),
        .window_id = try reader.readU64(),
        .row_index = try reader.readU32(),
    };
    if (delete.frame_generation == 0 or delete.window_id == 0) return Error.InvalidMessage;
    return delete;
}

pub fn encodeCursor(a: std.mem.Allocator, cursor: Cursor, out: *std.ArrayList(u8)) !void {
    if (!cursor.valid()) return Error.InvalidMessage;
    try putU64(out, a, cursor.window_id);
    try putI32(out, a, cursor.x);
    try putI32(out, a, cursor.y);
    try putI32(out, a, cursor.width);
    try putI32(out, a, cursor.height);
    try out.append(a, cursor.kind);
    try out.append(a, @intFromBool(cursor.visible));
    try out.append(a, @intFromBool(cursor.active));
    try out.appendNTimes(a, 0, 29);
}

pub fn decodeCursor(bytes: []const u8) Error!Cursor {
    if (bytes.len != cursor_record_size) return Error.InvalidTable;
    var reader: Reader = .{ .bytes = bytes };
    const cursor: Cursor = .{
        .window_id = try reader.readU64(),
        .x = try reader.readI32(),
        .y = try reader.readI32(),
        .width = try reader.readI32(),
        .height = try reader.readI32(),
        .kind = try reader.readByte(),
        .visible = (try reader.readByte()) != 0,
        .active = (try reader.readByte()) != 0,
    };
    try reader.expectZeros(29);
    if (!cursor.valid()) return Error.InvalidMessage;
    return cursor;
}

pub const cursor_update_header_size: usize = 8;
pub const cursor_update_size: usize = cursor_update_header_size + cursor_record_size;
pub const cursor_update_schema: u16 = 1;

pub fn encodeCursorUpdate(
    a: std.mem.Allocator,
    frame_generation: u32,
    cursor: Cursor,
    out: *std.ArrayList(u8),
) !void {
    if (frame_generation == 0 or !cursor.bounded()) return Error.InvalidMessage;
    var header: [cursor_update_header_size]u8 = [_]u8{0} ** cursor_update_header_size;
    std.mem.writeInt(u16, header[0..2], cursor_update_schema, .little);
    std.mem.writeInt(u32, header[4..8], frame_generation, .little);
    try out.appendSlice(a, &header);
    try encodeCursor(a, cursor, out);
}

pub fn decodeCursorUpdate(data: []const u8) Error!struct { frame_generation: u32, cursor: Cursor } {
    if (data.len != cursor_update_size) return Error.InvalidTable;
    var reader: Reader = .{ .bytes = data };
    if (try reader.readU16() != cursor_update_schema) return Error.InvalidTable;
    try reader.expectZeros(2);
    const frame_generation = try reader.readU32();
    const cursor = try decodeCursor(data[cursor_update_header_size..]);
    if (frame_generation == 0 or !cursor.bounded()) return Error.InvalidMessage;
    return .{ .frame_generation = frame_generation, .cursor = cursor };
}

pub fn encodeRect(a: std.mem.Allocator, rect: Rect, out: *std.ArrayList(u8)) !void {
    if (!rect.valid()) return Error.InvalidMessage;
    try putI32(out, a, rect.x);
    try putI32(out, a, rect.y);
    try putI32(out, a, rect.width);
    try putI32(out, a, rect.height);
}

pub fn decodeRect(bytes: []const u8) Error!Rect {
    if (bytes.len != damage_record_size) return Error.InvalidTable;
    var reader: Reader = .{ .bytes = bytes };
    const rect: Rect = .{
        .x = try reader.readI32(),
        .y = try reader.readI32(),
        .width = try reader.readI32(),
        .height = try reader.readI32(),
    };
    if (!rect.valid()) return Error.InvalidMessage;
    return rect;
}

pub const damage_rects_header_size: usize = 12;
pub const damage_rects_schema: u16 = 1;

pub fn encodeDamageRects(
    a: std.mem.Allocator,
    frame_generation: u32,
    rects: []const Rect,
    out: *std.ArrayList(u8),
) !void {
    if (frame_generation == 0 or rects.len == 0 or rects.len > protocol.max_damage)
        return Error.InvalidMessage;
    var header: [damage_rects_header_size]u8 = [_]u8{0} ** damage_rects_header_size;
    std.mem.writeInt(u16, header[0..2], damage_rects_schema, .little);
    std.mem.writeInt(u32, header[4..8], frame_generation, .little);
    std.mem.writeInt(u32, header[8..12], @intCast(rects.len), .little);
    try out.appendSlice(a, &header);
    for (rects) |rect| try encodeRect(a, rect, out);
}

pub const DamageRects = struct {
    frame_generation: u32,
    rects: []const Rect,
};

pub fn decodeDamageRects(a: std.mem.Allocator, data: []const u8) Error!DamageRects {
    if (data.len < damage_rects_header_size) return Error.InvalidTable;
    var reader: Reader = .{ .bytes = data };
    if (try reader.readU16() != damage_rects_schema) return Error.InvalidTable;
    try reader.expectZeros(2);
    const frame_generation = try reader.readU32();
    const count = try reader.readU32();
    if (frame_generation == 0 or count == 0 or count > protocol.max_damage)
        return Error.InvalidMessage;
    if (data.len != damage_rects_header_size + @as(usize, count) * damage_record_size)
        return Error.InvalidTable;

    const rects = try a.alloc(Rect, count);
    errdefer a.free(rects);
    for (rects) |*rect| {
        rect.* = try decodeRect(data[reader.offset..][0..damage_record_size]);
        try reader.skip(damage_record_size);
    }
    return .{ .frame_generation = frame_generation, .rects = rects };
}

pub fn freeDamageRects(a: std.mem.Allocator, damage: DamageRects) void {
    a.free(damage.rects);
}

pub const ClearArea = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    window_id: u64,
    rect: Rect,
    face_id: u32,
    face_generation: u32,
    frame_generation: u32,
};

pub const clear_area_size: usize = 40;

pub fn encodeClearArea(
    a: std.mem.Allocator,
    area: ClearArea,
    out: *std.ArrayList(u8),
) !void {
    if (area.schema != 1 or area.flags != 0 or area.reserved != 0 or
        area.window_id == 0 or !area.rect.valid() or
        area.rect.width <= 0 or area.rect.height <= 0 or
        area.face_id == 0 or area.face_generation == 0 or
        area.frame_generation == 0) return Error.InvalidMessage;
    var bytes: [clear_area_size]u8 = [_]u8{0} ** clear_area_size;
    std.mem.writeInt(u16, bytes[0..2], area.schema, .little);
    std.mem.writeInt(u64, bytes[4..12], area.window_id, .little);
    std.mem.writeInt(i32, bytes[12..16], area.rect.x, .little);
    std.mem.writeInt(i32, bytes[16..20], area.rect.y, .little);
    std.mem.writeInt(i32, bytes[20..24], area.rect.width, .little);
    std.mem.writeInt(i32, bytes[24..28], area.rect.height, .little);
    std.mem.writeInt(u32, bytes[28..32], area.face_id, .little);
    std.mem.writeInt(u32, bytes[32..36], area.face_generation, .little);
    std.mem.writeInt(u32, bytes[36..40], area.frame_generation, .little);
    try out.appendSlice(a, &bytes);
}

pub fn decodeClearArea(data: []const u8) Error!ClearArea {
    if (data.len != clear_area_size) return Error.InvalidTable;
    const area: ClearArea = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .window_id = std.mem.readInt(u64, data[4..12], .little),
        .rect = .{
            .x = @bitCast(std.mem.readInt(u32, data[12..16], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[16..20], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[20..24], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[24..28], .little)),
        },
        .face_id = std.mem.readInt(u32, data[28..32], .little),
        .face_generation = std.mem.readInt(u32, data[32..36], .little),
        .frame_generation = std.mem.readInt(u32, data[36..40], .little),
    };
    if (area.schema != 1 or area.flags != 0 or area.reserved != 0 or
        area.window_id == 0 or !area.rect.valid() or
        area.rect.width <= 0 or area.rect.height <= 0 or
        area.face_id == 0 or area.face_generation == 0 or
        area.frame_generation == 0) return Error.InvalidMessage;
    return area;
}

pub const ScrollRun = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    window_id: u64,
    source_y: i32,
    destination_y: i32,
    width: i32,
    height: i32,
    frame_generation: u32,
};

pub const scroll_run_size: usize = 32;

pub fn encodeScrollRun(
    a: std.mem.Allocator,
    run: ScrollRun,
    out: *std.ArrayList(u8),
) !void {
    if (run.schema != 1 or run.flags != 0 or run.reserved != 0 or
        run.window_id == 0 or
        run.width <= 0 or run.height <= 0 or
        run.source_y < 0 or run.destination_y < 0 or
        run.frame_generation == 0) return Error.InvalidMessage;
    var bytes: [scroll_run_size]u8 = [_]u8{0} ** scroll_run_size;
    std.mem.writeInt(u16, bytes[0..2], run.schema, .little);
    std.mem.writeInt(u64, bytes[4..12], run.window_id, .little);
    std.mem.writeInt(i32, bytes[12..16], run.source_y, .little);
    std.mem.writeInt(i32, bytes[16..20], run.destination_y, .little);
    std.mem.writeInt(i32, bytes[20..24], run.width, .little);
    std.mem.writeInt(i32, bytes[24..28], run.height, .little);
    std.mem.writeInt(u32, bytes[28..32], run.frame_generation, .little);
    try out.appendSlice(a, &bytes);
}

pub fn decodeScrollRun(data: []const u8) Error!ScrollRun {
    if (data.len != scroll_run_size) return Error.InvalidTable;
    const run: ScrollRun = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .window_id = std.mem.readInt(u64, data[4..12], .little),
        .source_y = @bitCast(std.mem.readInt(u32, data[12..16], .little)),
        .destination_y = @bitCast(std.mem.readInt(u32, data[16..20], .little)),
        .width = @bitCast(std.mem.readInt(u32, data[20..24], .little)),
        .height = @bitCast(std.mem.readInt(u32, data[24..28], .little)),
        .frame_generation = std.mem.readInt(u32, data[28..32], .little),
    };
    if (run.schema != 1 or run.flags != 0 or run.reserved != 0 or
        run.window_id == 0 or
        run.width <= 0 or run.height <= 0 or
        run.source_y < 0 or run.destination_y < 0 or
        run.frame_generation == 0) return Error.InvalidMessage;
    return run;
}

pub fn encodePresentHint(a: std.mem.Allocator, hint: PresentHint, out: *std.ArrayList(u8)) !void {
    try putU32(out, a, hint.mode);
    try putU32(out, a, hint.flags);
    try putU64(out, a, hint.deadline_ns);
}

pub fn encodeTextLine(a: std.mem.Allocator, line: TextLineWire, out: *std.ArrayList(u8)) !void {
    if (!validBoundedUtf8Text(line.line, max_text_columns)) return Error.InvalidTable;
    try putU32(out, a, line.row_index);
    try putU32(out, a, @intCast(line.line.len));
    try out.appendSlice(a, line.line);
}

pub fn decodeTextLine(bytes: []const u8) Error!TextLineWire {
    if (bytes.len < 8) return Error.InvalidTable;
    const length = std.mem.readInt(u32, bytes[4..8], .little);
    if (bytes.len != 8 + length) return Error.InvalidTable;
    const payload = bytes[8..];
    if (!validBoundedUtf8Text(payload, max_text_columns)) return Error.InvalidTable;
    return .{ .row_index = std.mem.readInt(u32, bytes[0..4], .little), .line = payload };
}

pub fn encodeTextLineV2(a: std.mem.Allocator, line: TextLineV2Wire, out: *std.ArrayList(u8)) !void {
    if (line.window_id == 0) return Error.InvalidTable;
    if (!validBoundedUtf8Text(line.line, max_text_columns)) return Error.InvalidTable;
    try putU64(out, a, line.window_id);
    try putU32(out, a, line.row_index);
    try putU32(out, a, @intCast(line.line.len));
    try out.appendSlice(a, line.line);
}

pub fn decodeTextLineV2(bytes: []const u8) Error!TextLineV2Wire {
    if (bytes.len < 16) return Error.InvalidTable;
    const length = std.mem.readInt(u32, bytes[12..16], .little);
    if (bytes.len != 16 + length) return Error.InvalidTable;
    const payload = bytes[16..];
    if (!validBoundedUtf8Text(payload, max_text_columns)) return Error.InvalidTable;
    return .{
        .window_id = std.mem.readInt(u64, bytes[0..8], .little),
        .row_index = std.mem.readInt(u32, bytes[8..12], .little),
        .line = payload,
    };
}

pub fn encodeModeLineV1(a: std.mem.Allocator, mode_line: ModeLineWire, out: *std.ArrayList(u8)) !void {
    if (mode_line.window_id == 0 or mode_line.width <= 0 or mode_line.height <= 0 or
        mode_line.flags & ~mode_line_active != 0)
        return Error.InvalidTable;
    if (!validBoundedUtf8Text(mode_line.line, max_text_columns)) return Error.InvalidTable;
    var header: [mode_line_header_size]u8 = undefined;
    std.mem.writeInt(u64, header[0..8], mode_line.window_id, .little);
    inline for (.{ mode_line.x, mode_line.y, mode_line.width, mode_line.height }, 0..) |value, index| {
        std.mem.writeInt(i32, header[8 + index * 4 ..][0..4], value, .little);
    }
    std.mem.writeInt(u16, header[24..26], mode_line.flags, .little);
    std.mem.writeInt(u32, header[26..30], @intCast(mode_line.line.len), .little);
    try out.appendSlice(a, &header);
    try out.appendSlice(a, mode_line.line);
}

pub fn decodeModeLineV1(bytes: []const u8) Error!ModeLineWire {
    if (bytes.len < mode_line_header_size) return Error.InvalidTable;
    const length = std.mem.readInt(u32, bytes[26..30], .little);
    if (bytes.len != mode_line_header_size + length) return Error.InvalidTable;
    const payload = bytes[mode_line_header_size..];
    if (!validBoundedUtf8Text(payload, max_text_columns)) return Error.InvalidTable;
    const flags = std.mem.readInt(u16, bytes[24..26], .little);
    if (flags & ~mode_line_active != 0) return Error.InvalidTable;
    return .{
        .window_id = std.mem.readInt(u64, bytes[0..8], .little),
        .x = @bitCast(std.mem.readInt(u32, bytes[8..12], .little)),
        .y = @bitCast(std.mem.readInt(u32, bytes[12..16], .little)),
        .width = @bitCast(std.mem.readInt(u32, bytes[16..20], .little)),
        .height = @bitCast(std.mem.readInt(u32, bytes[20..24], .little)),
        .flags = flags,
        .line = payload,
    };
}

pub const max_ime_contexts: usize = 4;
pub const ime_context_flags: u32 = 0;

pub const ImeAttach = struct {
    context_id: u64,
    window_id: u64,
    flags: u32 = 0,
};

pub const ImeDetach = struct {
    context_id: u64,
    window_id: u64,
};

pub const ImeFocus = struct {
    context_id: u64,
    window_id: u64,
    focused: bool,
};

pub const ImeCursorRect = struct {
    context_id: u64,
    window_id: u64,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const ImeReset = struct {
    context_id: u64,
    window_id: u64,
    reason: u8 = 0,
};

pub const ImeAllowedInputFlags = struct {
    pub const text: u32 = 1 << 0;
    pub const multiline: u32 = 1 << 1;
    pub const surrounding_text: u32 = 1 << 2;
    pub const delete_surrounding: u32 = 1 << 3;
    pub const known: u32 = text | multiline | surrounding_text | delete_surrounding;
};

pub const ImeAllowedInput = struct {
    context_id: u64,
    window_id: u64,
    flags: u32 = 0,
};

pub const ImeSurroundingText = struct {
    context_id: u64,
    window_id: u64,
    cursor_offset: u32,
    selected_length: u32,
    bytes: []const u8,
};

pub const ImeIdentity = struct { context_id: u64, window_id: u64 };

fn decodeImeIdentity(bytes: []const u8) Error!ImeIdentity {
    if (bytes.len < 16) return Error.InvalidTable;
    const identity: ImeIdentity = .{
        .context_id = std.mem.readInt(u64, bytes[0..8], .little),
        .window_id = std.mem.readInt(u64, bytes[8..16], .little),
    };
    if (identity.context_id == 0 or identity.window_id == 0) return Error.InvalidTable;
    return identity;
}

fn encodeImeIdentity(a: std.mem.Allocator, context_id: u64, window_id: u64, out: *std.ArrayList(u8)) !void {
    if (context_id == 0 or window_id == 0) return Error.InvalidTable;
    try putU64(out, a, context_id);
    try putU64(out, a, window_id);
}

pub fn encodeImeAttach(a: std.mem.Allocator, request: ImeAttach, out: *std.ArrayList(u8)) !void {
    if (request.flags != ime_context_flags) return Error.InvalidTable;
    try encodeImeIdentity(a, request.context_id, request.window_id, out);
    try putU32(out, a, request.flags);
}

pub fn decodeImeAttach(bytes: []const u8) Error!ImeAttach {
    const identity = try decodeImeIdentity(bytes);
    if (bytes.len != 20) return Error.InvalidTable;
    const flags = std.mem.readInt(u32, bytes[16..20], .little);
    if (flags != ime_context_flags) return Error.InvalidTable;
    return .{ .context_id = identity.context_id, .window_id = identity.window_id, .flags = flags };
}

pub fn encodeImeDetach(a: std.mem.Allocator, request: ImeDetach, out: *std.ArrayList(u8)) !void {
    try encodeImeIdentity(a, request.context_id, request.window_id, out);
}

pub fn decodeImeDetach(bytes: []const u8) Error!ImeDetach {
    const identity = try decodeImeIdentity(bytes);
    if (bytes.len != 16) return Error.InvalidTable;
    return .{ .context_id = identity.context_id, .window_id = identity.window_id };
}

pub fn encodeImeFocus(a: std.mem.Allocator, request: ImeFocus, out: *std.ArrayList(u8)) !void {
    try encodeImeIdentity(a, request.context_id, request.window_id, out);
    try out.append(a, @intFromBool(request.focused));
    try out.appendNTimes(a, 0, 3);
}

pub fn decodeImeFocus(bytes: []const u8) Error!ImeFocus {
    const identity = try decodeImeIdentity(bytes);
    if (bytes.len != 20 or bytes[16] > 1 or bytes[17] != 0 or bytes[18] != 0 or bytes[19] != 0)
        return Error.InvalidTable;
    return .{ .context_id = identity.context_id, .window_id = identity.window_id, .focused = bytes[16] == 1 };
}

pub fn encodeImeCursorRect(a: std.mem.Allocator, rect: ImeCursorRect, out: *std.ArrayList(u8)) !void {
    if (rect.width <= 0 or rect.height <= 0) return Error.InvalidTable;
    try encodeImeIdentity(a, rect.context_id, rect.window_id, out);
    inline for (.{ rect.x, rect.y, rect.width, rect.height }) |value| {
        try putI32(out, a, value);
    }
}

pub fn decodeImeCursorRect(bytes: []const u8) Error!ImeCursorRect {
    const identity = try decodeImeIdentity(bytes);
    if (bytes.len != 32) return Error.InvalidTable;
    const width: i32 = @bitCast(std.mem.readInt(u32, bytes[24..28], .little));
    const height: i32 = @bitCast(std.mem.readInt(u32, bytes[28..32], .little));
    if (width <= 0 or height <= 0) return Error.InvalidTable;
    return .{
        .context_id = identity.context_id,
        .window_id = identity.window_id,
        .x = @bitCast(std.mem.readInt(u32, bytes[16..20], .little)),
        .y = @bitCast(std.mem.readInt(u32, bytes[20..24], .little)),
        .width = width,
        .height = height,
    };
}

pub fn encodeImeReset(a: std.mem.Allocator, request: ImeReset, out: *std.ArrayList(u8)) !void {
    if (request.reason != 0) return Error.InvalidTable;
    try encodeImeIdentity(a, request.context_id, request.window_id, out);
    try out.append(a, request.reason);
    try out.appendNTimes(a, 0, 3);
}

pub fn decodeImeReset(bytes: []const u8) Error!ImeReset {
    const identity = try decodeImeIdentity(bytes);
    if (bytes.len != 20 or bytes[16] != 0 or bytes[17] != 0 or bytes[18] != 0 or bytes[19] != 0)
        return Error.InvalidTable;
    return .{ .context_id = identity.context_id, .window_id = identity.window_id, .reason = bytes[16] };
}

pub fn encodeImeAllowedInput(a: std.mem.Allocator, request: ImeAllowedInput, out: *std.ArrayList(u8)) !void {
    if (request.flags & ~ImeAllowedInputFlags.known != 0) return Error.InvalidTable;
    try encodeImeIdentity(a, request.context_id, request.window_id, out);
    try putU32(out, a, request.flags);
}

pub fn decodeImeAllowedInput(bytes: []const u8) Error!ImeAllowedInput {
    const identity = try decodeImeIdentity(bytes);
    if (bytes.len != 20) return Error.InvalidTable;
    const flags = std.mem.readInt(u32, bytes[16..20], .little);
    if (flags & ~ImeAllowedInputFlags.known != 0) return Error.InvalidTable;
    return .{ .context_id = identity.context_id, .window_id = identity.window_id, .flags = flags };
}

pub fn encodeImeSurroundingText(a: std.mem.Allocator, request: ImeSurroundingText, out: *std.ArrayList(u8)) !void {
    if (!validBoundedUtf8Line(request.bytes, max_text_columns)) return Error.InvalidTable;
    if (request.selected_length > request.cursor_offset or
        request.cursor_offset > request.bytes.len)
        return Error.InvalidTable;
    try encodeImeIdentity(a, request.context_id, request.window_id, out);
    try putU32(out, a, request.cursor_offset);
    try putU32(out, a, request.selected_length);
    try putU32(out, a, @intCast(request.bytes.len));
    try out.appendSlice(a, request.bytes);
}

pub fn decodeImeSurroundingText(bytes: []const u8) Error!ImeSurroundingText {
    const identity = try decodeImeIdentity(bytes);
    if (bytes.len < 28) return Error.InvalidTable;
    const length = std.mem.readInt(u32, bytes[24..28], .little);
    if (bytes.len != 28 + length) return Error.InvalidTable;
    const payload = bytes[28..];
    if (!validBoundedUtf8Line(payload, max_text_columns)) return Error.InvalidTable;
    const cursor_offset = std.mem.readInt(u32, bytes[16..20], .little);
    const selected_length = std.mem.readInt(u32, bytes[20..24], .little);
    if (selected_length > cursor_offset or cursor_offset > payload.len)
        return Error.InvalidTable;
    return .{
        .context_id = identity.context_id,
        .window_id = identity.window_id,
        .cursor_offset = cursor_offset,
        .selected_length = selected_length,
        .bytes = payload,
    };
}

pub const ImePlatform = enum(u8) {
    none = 0,
    basic = 1,
};

pub const ImeAttached = struct {
    context_id: u64,
    platform: ImePlatform = .none,
    flags: u32 = 0,
};

pub const ImeDetached = struct {
    context_id: u64,
    reason: u8 = 0,
};

pub const ImePreeditUpdate = struct {
    context_id: u64,
    cursor_offset: u32,
    selected_length: u32,
    bytes: []const u8,
};

pub const ImeCommit = struct {
    context_id: u64,
    bytes: []const u8,
};

pub const ImeRequestSurrounding = struct {
    context_id: u64,
    request_id: u64,
};

pub const ImeDeleteSurrounding = struct {
    context_id: u64,
    offset: i32,
    length: u32,
};

pub const max_ime_candidates: u32 = 64;
pub const max_ime_candidate_pages: u32 = 16;

pub const ImeCandidateUpdate = struct {
    context_id: u64,
    selected_index: u32,
    candidate_count: u32,
    page_index: u32,
    page_count: u32,
    cursor_x: i32,
    cursor_y: i32,
    cursor_width: i32,
    cursor_height: i32,
    selected_label: []const u8,

    pub fn valid(self: ImeCandidateUpdate) bool {
        if (self.candidate_count > max_ime_candidates or
            self.page_count == 0 or self.page_count > max_ime_candidate_pages or
            self.page_index >= self.page_count) return false;
        if (self.candidate_count == 0) {
            if (self.selected_index != 0 or self.selected_label.len != 0) return false;
        } else {
            if (self.selected_index >= self.candidate_count or
                self.selected_label.len == 0 or
                self.selected_label.len > max_text_columns) return false;
        }
        return self.cursor_width > 0 and self.cursor_height > 0;
    }
};

fn encodeImeContextId(a: std.mem.Allocator, context_id: u64, out: *std.ArrayList(u8)) !void {
    if (context_id == 0) return Error.InvalidTable;
    try putU64(out, a, context_id);
}

fn decodeImeContextId(bytes: []const u8) Error!u64 {
    if (bytes.len < 8) return Error.InvalidTable;
    const context_id = std.mem.readInt(u64, bytes[0..8], .little);
    if (context_id == 0) return Error.InvalidTable;
    return context_id;
}

pub fn encodeImeAttached(a: std.mem.Allocator, payload: ImeAttached, out: *std.ArrayList(u8)) !void {
    if (payload.flags != 0 or payload.platform == .none) return Error.InvalidTable;
    try encodeImeContextId(a, payload.context_id, out);
    try out.append(a, @intFromEnum(payload.platform));
    try out.appendNTimes(a, 0, 3);
    try putU32(out, a, payload.flags);
}

pub fn decodeImeAttached(bytes: []const u8) Error!ImeAttached {
    const context_id = try decodeImeContextId(bytes);
    if (bytes.len != 16) return Error.InvalidTable;
    const platform: ImePlatform = switch (bytes[8]) {
        0 => .none,
        1 => .basic,
        else => return Error.InvalidTable,
    };
    if (platform == .none or bytes[9] != 0 or bytes[10] != 0 or bytes[11] != 0)
        return Error.InvalidTable;
    const flags = std.mem.readInt(u32, bytes[12..16], .little);
    if (flags != 0) return Error.InvalidTable;
    return .{ .context_id = context_id, .platform = platform, .flags = flags };
}

pub fn encodeImeDetached(a: std.mem.Allocator, payload: ImeDetached, out: *std.ArrayList(u8)) !void {
    if (payload.reason != 0) return Error.InvalidTable;
    try encodeImeContextId(a, payload.context_id, out);
    try out.append(a, payload.reason);
    try out.appendNTimes(a, 0, 3);
}

pub fn decodeImeDetached(bytes: []const u8) Error!ImeDetached {
    const context_id = try decodeImeContextId(bytes);
    if (bytes.len != 12 or bytes[8] != 0 or bytes[9] != 0 or bytes[10] != 0 or bytes[11] != 0)
        return Error.InvalidTable;
    return .{ .context_id = context_id, .reason = bytes[8] };
}

pub fn encodeImePreeditStart(a: std.mem.Allocator, context_id: u64, out: *std.ArrayList(u8)) !void {
    try encodeImeContextId(a, context_id, out);
}

pub fn decodeImePreeditStart(bytes: []const u8) Error!u64 {
    const context_id = try decodeImeContextId(bytes);
    if (bytes.len != 8) return Error.InvalidTable;
    return context_id;
}

pub fn encodeImePreeditUpdate(a: std.mem.Allocator, payload: ImePreeditUpdate, out: *std.ArrayList(u8)) !void {
    if (!validBoundedUtf8Line(payload.bytes, max_text_columns)) return Error.InvalidTable;
    if (payload.selected_length > payload.cursor_offset or payload.cursor_offset > payload.bytes.len)
        return Error.InvalidTable;
    try encodeImeContextId(a, payload.context_id, out);
    try putU32(out, a, payload.cursor_offset);
    try putU32(out, a, payload.selected_length);
    try putU32(out, a, @intCast(payload.bytes.len));
    try out.appendSlice(a, payload.bytes);
}

pub fn decodeImePreeditUpdate(bytes: []const u8) Error!ImePreeditUpdate {
    const context_id = try decodeImeContextId(bytes);
    if (bytes.len < 20) return Error.InvalidTable;
    const cursor_offset = std.mem.readInt(u32, bytes[8..12], .little);
    const selected_length = std.mem.readInt(u32, bytes[12..16], .little);
    const length = std.mem.readInt(u32, bytes[16..20], .little);
    if (bytes.len != 20 + length) return Error.InvalidTable;
    const text = bytes[20..];
    if (!validBoundedUtf8Line(text, max_text_columns)) return Error.InvalidTable;
    if (selected_length > cursor_offset or cursor_offset > text.len) return Error.InvalidTable;
    return .{ .context_id = context_id, .cursor_offset = cursor_offset, .selected_length = selected_length, .bytes = text };
}

pub fn encodeImePreeditEnd(a: std.mem.Allocator, context_id: u64, out: *std.ArrayList(u8)) !void {
    try encodeImeContextId(a, context_id, out);
}

pub fn decodeImePreeditEnd(bytes: []const u8) Error!u64 {
    const context_id = try decodeImeContextId(bytes);
    if (bytes.len != 8) return Error.InvalidTable;
    return context_id;
}

pub fn encodeImeCommit(a: std.mem.Allocator, payload: ImeCommit, out: *std.ArrayList(u8)) !void {
    if (!validBoundedUtf8Text(payload.bytes, max_text_columns)) return Error.InvalidTable;
    try encodeImeContextId(a, payload.context_id, out);
    try putU32(out, a, @intCast(payload.bytes.len));
    try out.appendSlice(a, payload.bytes);
}

pub fn decodeImeCommit(bytes: []const u8) Error!ImeCommit {
    const context_id = try decodeImeContextId(bytes);
    if (bytes.len < 12) return Error.InvalidTable;
    const length = std.mem.readInt(u32, bytes[8..12], .little);
    if (bytes.len != 12 + length) return Error.InvalidTable;
    const text = bytes[12..];
    if (!validBoundedUtf8Text(text, max_text_columns)) return Error.InvalidTable;
    return .{ .context_id = context_id, .bytes = text };
}

pub fn encodeImeRequestSurrounding(a: std.mem.Allocator, payload: ImeRequestSurrounding, out: *std.ArrayList(u8)) !void {
    if (payload.request_id == 0) return Error.InvalidTable;
    try encodeImeContextId(a, payload.context_id, out);
    try putU64(out, a, payload.request_id);
}

pub fn decodeImeRequestSurrounding(bytes: []const u8) Error!ImeRequestSurrounding {
    const context_id = try decodeImeContextId(bytes);
    if (bytes.len != 16) return Error.InvalidTable;
    const request_id = std.mem.readInt(u64, bytes[8..16], .little);
    if (request_id == 0) return Error.InvalidTable;
    return .{ .context_id = context_id, .request_id = request_id };
}

pub fn encodeImeDeleteSurrounding(a: std.mem.Allocator, payload: ImeDeleteSurrounding, out: *std.ArrayList(u8)) !void {
    if (payload.length == 0 or payload.length > max_text_columns or
        payload.offset < -@as(i32, @intCast(max_text_columns)) or
        payload.offset > max_text_columns) return Error.InvalidTable;
    if (payload.offset < 0 and payload.length > @as(u32, @intCast(-payload.offset))) return Error.InvalidTable;
    try encodeImeContextId(a, payload.context_id, out);
    try putI32(out, a, payload.offset);
    try putU32(out, a, payload.length);
}

pub fn decodeImeDeleteSurrounding(bytes: []const u8) Error!ImeDeleteSurrounding {
    const context_id = try decodeImeContextId(bytes);
    if (bytes.len != 16) return Error.InvalidTable;
    const offset: i32 = @bitCast(std.mem.readInt(u32, bytes[8..12], .little));
    const length = std.mem.readInt(u32, bytes[12..16], .little);
    if (length == 0 or length > max_text_columns or
        offset < -@as(i32, @intCast(max_text_columns)) or offset > max_text_columns)
        return Error.InvalidTable;
    if (offset < 0 and length > @as(u32, @intCast(-offset))) return Error.InvalidTable;
    return .{ .context_id = context_id, .offset = offset, .length = length };
}

pub fn encodeImeCandidateUpdate(a: std.mem.Allocator, payload: ImeCandidateUpdate, out: *std.ArrayList(u8)) !void {
    if (!payload.valid()) return Error.InvalidTable;
    if (!validBoundedUtf8Line(payload.selected_label, max_text_columns)) return Error.InvalidTable;
    try encodeImeContextId(a, payload.context_id, out);
    inline for (.{ payload.selected_index, payload.candidate_count, payload.page_index, payload.page_count }) |value| {
        try putU32(out, a, value);
    }
    inline for (.{ payload.cursor_x, payload.cursor_y, payload.cursor_width, payload.cursor_height }) |value| {
        try putI32(out, a, value);
    }
    try putU32(out, a, @intCast(payload.selected_label.len));
    try out.appendSlice(a, payload.selected_label);
}

pub fn decodeImeCandidateUpdate(bytes: []const u8) Error!ImeCandidateUpdate {
    const context_id = try decodeImeContextId(bytes);
    if (bytes.len < 44) return Error.InvalidTable;
    var values: [4]u32 = undefined;
    inline for (0..4) |index| {
        values[index] = std.mem.readInt(u32, bytes[8 + index * 4 ..][0..4], .little);
    }
    var rects: [4]i32 = undefined;
    inline for (0..4) |index| {
        rects[index] = @bitCast(std.mem.readInt(u32, bytes[24 + index * 4 ..][0..4], .little));
    }
    const length = std.mem.readInt(u32, bytes[40..44], .little);
    if (bytes.len != 44 + length) return Error.InvalidTable;
    const label = bytes[44..];
    if (!validBoundedUtf8Line(label, max_text_columns)) return Error.InvalidTable;
    const payload: ImeCandidateUpdate = .{
        .context_id = context_id,
        .selected_index = values[0],
        .candidate_count = values[1],
        .page_index = values[2],
        .page_count = values[3],
        .cursor_x = rects[0],
        .cursor_y = rects[1],
        .cursor_width = rects[2],
        .cursor_height = rects[3],
        .selected_label = label,
    };
    if (!payload.valid()) return Error.InvalidTable;
    return payload;
}

pub fn encodeImeCancel(a: std.mem.Allocator, context_id: u64, out: *std.ArrayList(u8)) !void {
    try encodeImeContextId(a, context_id, out);
}

pub fn decodeImeCancel(bytes: []const u8) Error!u64 {
    const context_id = try decodeImeContextId(bytes);
    if (bytes.len != 8) return Error.InvalidTable;
    return context_id;
}

pub fn encodeTextInput(a: std.mem.Allocator, input: TextInput, out: *std.ArrayList(u8)) !void {
    if (!validBoundedUtf8Text(input.text, max_text_columns)) return Error.InvalidTable;
    try putU32(out, a, @intCast(input.text.len));
    try out.appendSlice(a, input.text);
}

pub fn decodeTextInput(bytes: []const u8) Error!TextInput {
    if (bytes.len < 4) return Error.InvalidTable;
    const length = std.mem.readInt(u32, bytes[0..4], .little);
    if (length == 0 or length > max_text_columns or
        bytes.len < 4 or bytes.len - 4 != length) return Error.InvalidTable;
    const text = bytes[4..];
    if (!validBoundedUtf8Text(text, max_text_columns)) return Error.InvalidTable;
    return .{ .text = text };
}

pub fn encodeKeyEvent(a: std.mem.Allocator, event: KeyEvent, out: *std.ArrayList(u8)) !void {
    if (event.state != 1 or event.modifiers != 0) return Error.Unsupported;
    try putU16(out, a, @intFromEnum(event.action));
    try out.append(a, event.state);
    try out.append(a, event.modifiers);
}

pub fn decodeKeyEvent(bytes: []const u8) Error!KeyEvent {
    if (bytes.len != 4) return Error.InvalidTable;
    const action_value = std.mem.readInt(u16, bytes[0..2], .little);
    const action: KeyAction = switch (action_value) {
        1 => .backspace,
        6 => .copy,
        2 => .cursor_left,
        3 => .cursor_right,
        4 => .cursor_up,
        5 => .cursor_down,
        else => return Error.InvalidTable,
    };
    if (bytes[2] != 1 or bytes[3] != 0) return Error.Unsupported;
    return .{ .action = action, .state = bytes[2], .modifiers = bytes[3] };
}

pub fn encodePointerInput(a: std.mem.Allocator, input: PointerInput, out: *std.ArrayList(u8)) !void {
    if (!input.valid()) return Error.Unsupported;
    try out.append(a, @intFromEnum(input.phase));
    try out.append(a, input.button);
    try putI32(out, a, input.x);
    try putI32(out, a, input.y);
    try out.append(a, input.clicks);
    try out.append(a, input.modifiers);
    try putU16(out, a, 0);
}

pub fn encodeWheelInput(a: std.mem.Allocator, input: WheelInput, out: *std.ArrayList(u8)) !void {
    if (!input.valid()) return Error.Unsupported;
    try out.append(a, @intFromEnum(input.unit));
    try out.append(a, @intFromEnum(input.source));
    try out.append(a, input.modifiers);
    try out.append(a, @bitCast(input.x));
    try out.append(a, @bitCast(input.y));
    try out.appendSlice(a, &[_]u8{0} ** 9);
}

pub fn decodeWheelInput(bytes: []const u8) Error!WheelInput {
    if (bytes.len != 14) return Error.InvalidTable;
    const input: WheelInput = .{
        .unit = if (bytes[0] == 1) .line else return Error.InvalidTable,
        .source = if (bytes[1] == 1) .wheel else return Error.InvalidTable,
        .modifiers = bytes[2],
        .x = @bitCast(bytes[3]),
        .y = @bitCast(bytes[4]),
    };
    if (!input.valid() or bytes[5] != 0 or bytes[6] != 0 or bytes[7] != 0 or bytes[8] != 0 or bytes[9] != 0 or bytes[10] != 0 or bytes[11] != 0 or bytes[12] != 0 or bytes[13] != 0) return Error.Unsupported;
    return input;
}

pub fn decodePointerInput(bytes: []const u8) Error!PointerInput {
    if (bytes.len != 14) return Error.InvalidTable;
    const phase_value = bytes[0];
    const phase: PointerPhase = switch (phase_value) {
        1 => .motion,
        2 => .press,
        3 => .release,
        else => return Error.InvalidTable,
    };
    const input: PointerInput = .{
        .phase = phase,
        .button = bytes[1],
        .x = @bitCast(std.mem.readInt(i32, bytes[2..6], .little)),
        .y = @bitCast(std.mem.readInt(i32, bytes[6..10], .little)),
        .clicks = bytes[10],
        .modifiers = bytes[11],
    };
    if (!input.valid() or std.mem.readInt(u16, bytes[12..14], .little) != 0) return Error.Unsupported;
    return input;
}

pub fn decodePresentHint(bytes: []const u8) Error!PresentHint {
    if (bytes.len != present_record_size) return Error.InvalidTable;
    var reader: Reader = .{ .bytes = bytes };
    return .{
        .mode = try reader.readU32(),
        .flags = try reader.readU32(),
        .deadline_ns = try reader.readU64(),
    };
}

pub const FrameIdentity = struct {
    frame_id: u32,
    generation: u32,
};

pub const Viewport = struct {
    start_line: i32,
    line_count: i32,

    fn valid(self: Viewport) bool {
        return self.start_line >= 1 and self.line_count >= 0 and
            self.line_count <= protocol.max_rows;
    }
};

pub const ApplyStats = struct {
    control_messages: u64 = 0,
    frame_updates: u64 = 0,
};

fn encodeResourceDeclaration(a: std.mem.Allocator, declaration: ResourceDeclaration, out: *std.ArrayList(u8)) !void {
    if (declaration.id == 0 or declaration.generation == 0) return Error.InvalidMessage;
    try out.append(a, @intFromEnum(declaration.kind));
    try out.appendSlice(a, &.{ 0, 0, 0 });
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, declaration.id, .little);
    try out.appendSlice(a, &bytes);
    std.mem.writeInt(u32, &bytes, declaration.generation, .little);
    try out.appendSlice(a, &bytes);
    try out.appendSlice(a, &.{ 0, 0, 0, 0 });
}

fn decodeResourceDeclaration(bytes: []const u8) Error!ResourceDeclaration {
    if (bytes.len != resource_record_size) return Error.InvalidTable;
    if (bytes[0] == 0 or bytes[0] > 6) return Error.InvalidTable;
    const kind: lifecycle.ResourceKind = @enumFromInt(bytes[0]);
    if (bytes[1] != 0 or bytes[2] != 0 or bytes[3] != 0) return Error.InvalidTable;
    const id = std.mem.readInt(u32, bytes[4..8], .little);
    const generation = std.mem.readInt(u32, bytes[8..12], .little);
    if (bytes[12] != 0 or bytes[13] != 0 or bytes[14] != 0 or bytes[15] != 0) return Error.InvalidTable;
    if (id == 0 or generation == 0) return Error.InvalidTable;
    return .{ .kind = kind, .id = id, .generation = generation, .status = .live };
}

pub const ImeContext = struct {
    context_id: u64,
    window_id: u64,
    frame_id: u32,
    focused: bool = false,
    cursor_x: i32 = 0,
    cursor_y: i32 = 0,
    cursor_width: i32 = 0,
    cursor_height: i32 = 0,
    allowed_input: u32 = 0,
    surrounding_bytes: [121]u8 = undefined,
    surrounding_len: u16 = 0,
    surrounding_cursor_offset: u32 = 0,
    surrounding_selected_length: u32 = 0,
    has_surrounding: bool = false,

    pub fn clearSurrounding(self: *ImeContext) void {
        self.surrounding_len = 0;
        self.surrounding_cursor_offset = 0;
        self.surrounding_selected_length = 0;
        self.has_surrounding = false;
    }
};

pub const Scene = struct {
    allocator: std.mem.Allocator,
    session_id: ?u64 = null,
    next_sequence: ?u64 = null,
    frame: ?FrameIdentity = null,
    frames: lifecycle.FrameRegistry = .{},
    resources: lifecycle.ResourceRegistry = .{},
    frame_header: ?protocol.FrameUpdateHeader = null,
    windows: std.ArrayList(Window) = .empty,
    rows: std.ArrayList(Row) = .empty,
    glyph_runs: std.ArrayList(GlyphRun) = .empty,
    strings: StringResources = .{},
    faces: FaceResources = .{},
    fonts: FontResources = .{},
    images: ImageResources = .{},
    fringe_bitmaps: FringeBitmapResources = .{},
    image_placements: [max_image_placements]ImagePlacement = undefined,
    image_placement_count: usize = 0,
    cursor: ?Cursor = null,
    cursors: [max_scene_cursors]Cursor = undefined,
    cursor_count: usize = 0,
    damage: std.ArrayList(Rect) = .empty,
    clear_areas: std.ArrayList(ClearArea) = .empty,
    scroll_runs: std.ArrayList(ScrollRun) = .empty,
    dividers: std.ArrayList(DividerUpdate) = .empty,
    fringes: std.ArrayList(FringeUpdate) = .empty,
    scroll_states: std.ArrayList(WindowScrollState) = .empty,
    window_faces: std.ArrayList(WindowFaceState) = .empty,
    window_geometries: std.ArrayList(WindowGeometryState) = .empty,
    window_zones: std.ArrayList(WindowZonesState) = .empty,
    window_positions: std.ArrayList(WindowPositionState) = .empty,
    mouse_highlights: [max_mouse_highlights]MouseHighlightState = undefined,
    mouse_highlight_count: usize = 0,
    tooltip: ?TooltipShow = null,
    atlases: AtlasResources = undefined,
    border: ?BorderUpdate = null,
    text: std.ArrayList(TextLine) = .empty,
    mode_lines: [max_mode_lines]ModeLine = undefined,
    mode_line_count: usize = 0,
    ime_contexts: [max_ime_contexts]ImeContext = undefined,
    ime_context_count: usize = 0,
    aux_lines: [max_aux_lines]ModeLine = undefined,
    aux_line_count: usize = 0,
    title: ?[:0]u8 = null,
    alpha: ?protocol.FrameAlphaPayload = null,
    decorations: ?protocol.FrameDecorationsPayload = null,
    scale: ?protocol.FrameScalePayload = null,
    fullscreen: ?protocol.FrameFullscreenPayload = null,
    monitor: ?protocol.FrameMonitorPayload = null,
    maximize: ?protocol.FrameMaximizePayload = null,
    geometry: ?protocol.FrameGeometryPayload = null,
    icon: ?protocol.FrameIconPayload = null,
    size_hints: ?protocol.FrameSizeHintsPayload = null,
    z_order: ?protocol.FrameZOrderPayload = null,
    parent: ?protocol.FrameParentPayload = null,
    present: ?PresentHint = null,
    flush: ?protocol.FrameFlushPayload = null,
    render_hint: ?protocol.RenderHintPayload = null,
    active_update_id: ?u32 = null,
    viewport: ?Viewport = null,
    window_tree: ?protocol.WindowTreeSnapshot = null,
    menu_model: ?protocol.MenuModelSnapshot = null,
    menu_open: ?protocol.MenuOpen = null,
    dialog: ?protocol.DialogState = null,
    toolbar: ?protocol.ToolbarModel = null,
    control: session.Control = .{},
    stats: ApplyStats = .{},

    pub fn init(allocator: std.mem.Allocator) Scene {
        return .{ .allocator = allocator, .atlases = AtlasResources.init(allocator) };
    }

    pub fn deinit(self: *Scene) void {
        self.atlases.deinit();
        self.windows.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.clearGlyphRuns();
        self.damage.deinit(self.allocator);
        self.clear_areas.deinit(self.allocator);
        self.scroll_runs.deinit(self.allocator);
        self.dividers.deinit(self.allocator);
        self.fringes.deinit(self.allocator);
        self.scroll_states.deinit(self.allocator);
        self.window_faces.deinit(self.allocator);
        self.window_geometries.deinit(self.allocator);
        self.window_zones.deinit(self.allocator);
        self.window_positions.deinit(self.allocator);
        self.strings.deinit(self.allocator);
        self.faces = .{};
        self.fonts = .{};
        self.images.clear(self.allocator);
        self.fringe_bitmaps = .{};
        for (self.text.items) |line| self.allocator.free(line.bytes);
        self.text.deinit(self.allocator);
        self.clearTitle();
        self.alpha = null;
        self.decorations = null;
        self.scale = null;
        self.fullscreen = null;
        self.monitor = null;
        self.maximize = null;
        self.geometry = null;
        self.icon = null;
        self.size_hints = null;
        self.z_order = null;
        self.parent = null;
        self.windows = .empty;
        self.rows = .empty;
        self.glyph_runs = .empty;
        self.damage = .empty;
        self.clear_areas = .empty;
        self.scroll_runs = .empty;
        self.dividers = .empty;
        self.fringes = .empty;
        self.scroll_states = .empty;
        self.window_faces = .empty;
        self.window_geometries = .empty;
        self.window_zones = .empty;
        self.window_positions = .empty;
        self.strings = .{};
        self.faces = .{};
        self.fonts = .{};
        self.text = .empty;
        self.session_id = null;
        self.next_sequence = null;
        self.frame = null;
        self.frames.reset();
        self.resources.reset();
        self.frame_header = null;
        self.cursor = null;
        self.cursor_count = 0;
        self.ime_context_count = 0;
        self.present = null;
        self.flush = null;
        self.render_hint = null;
        self.active_update_id = null;
        self.viewport = null;
        self.tooltip = null;
        self.menu_open = null;
        if (self.window_tree) |*tree| protocol.freeWindowTreeSnapshot(self.allocator, tree);
        self.window_tree = null;
        if (self.menu_model) |*model| protocol.freeMenuModelSnapshot(self.allocator, model);
        self.menu_model = null;
        if (self.toolbar) |*model| protocol.freeToolbarModel(self.allocator, model);
        self.toolbar = null;
        self.dialog = null;
        self.control = .{};
        self.image_placement_count = 0;
        self.stats = .{};
    }

    /// Discards display state before an authenticated RESYNC_BEGIN.  Allocator
    /// identity is preserved so the same scene can continue after recovery.
    pub fn resetForResync(self: *Scene) void {
        self.deinit();
    }

    pub fn apply(self: *Scene, message: []const u8) Error!void {
        const payload = try protocol.decodeEnvelope(message);
        const previous_session = self.session_id;
        if (self.session_id) |expected| {
            if (payload.envelope.session_id != expected) return Error.InvalidMessage;
        }
        if (self.next_sequence) |expected| {
            if (payload.envelope.sequence != expected) {
                return Error.InvalidSequence;
            }
        }
        const next_sequence = std.math.add(u64, payload.envelope.sequence, 1) catch return Error.InvalidSequence;

        switch (payload.envelope.message_type) {
            protocol.Message.session_suspend,
            protocol.Message.session_resume,
            protocol.Message.session_resumed,
            protocol.Message.session_close,
            protocol.Message.ping,
            protocol.Message.pong,
            protocol.Message.session_error,
            protocol.Message.version_mismatch,
            => {
                var authoritative_sequence = next_sequence;
                if (payload.envelope.message_type == protocol.Message.session_resumed) {
                    const resumed = try session.decodeResumed(payload.bytes);
                    if (resumed.next_sequence <= payload.envelope.sequence)
                        return Error.InvalidSequence;
                    authoritative_sequence = resumed.next_sequence;
                }
                try self.control.apply(payload.envelope.message_type, payload.bytes);
                self.stats.control_messages += 1;
                self.next_sequence = authoritative_sequence;
                if (previous_session == null) self.session_id = payload.envelope.session_id;
                return;
            },
            else => {},
        }

        if (self.control.stage == .fatal or self.control.stage == .closed)
            return Error.InvalidSessionStage;
        if ((self.control.stage == .suspended or self.control.stage == .resume_pending) and
            (payload.envelope.message_type >= protocol.Message.frame_create and
                payload.envelope.message_type < protocol.Message.window_tree_snapshot or
                payload.envelope.message_type == protocol.Message.window_create or
                payload.envelope.message_type == protocol.Message.window_delete))
            return Error.SessionSuspended;

        switch (payload.envelope.message_type) {
            protocol.Message.frame_create => try self.applyFrameCreate(payload.envelope, payload.bytes),
            protocol.Message.frame_patch => try self.applyFramePatch(payload),
            protocol.Message.frame_snapshot => try self.applyFrameSnapshot(payload),
            protocol.Message.frame_update => try self.applyFrameUpdate(payload),
            protocol.Message.begin_update => try self.applyBeginUpdate(payload),
            protocol.Message.end_update => try self.applyEndUpdate(payload),
            protocol.Message.row_snapshot => try self.applyRowSnapshot(payload),
            protocol.Message.row_update => try self.applyRowUpdate(payload),
            protocol.Message.row_delete => try self.applyRowDelete(payload),
            protocol.Message.window_tree_snapshot => try self.applyWindowTreeSnapshot(payload),
            protocol.Message.menu_model => try self.applyMenuModel(payload),
            protocol.Message.menu_patch => try self.applyMenuPatch(payload),
            protocol.Message.toolbar_model => try self.applyToolbarModel(payload),
            protocol.Message.dialog_open => try self.applyDialogOpen(payload),
            protocol.Message.dialog_update => try self.applyDialogUpdate(payload),
            protocol.Message.dialog_close => try self.applyDialogClose(payload),
            protocol.Message.toolbar_patch => try self.applyToolbarPatch(payload),
            protocol.Message.menu_open => try self.applyMenuOpen(payload),
            protocol.Message.menu_close => try self.applyMenuClose(payload),
            protocol.Message.glyph_run => try self.applyGlyphRun(payload),
            protocol.Message.glyph_run_delete => try self.applyGlyphRunDelete(payload),
            protocol.Message.frame_visibility => try self.applyFrameVisibility(payload),
            protocol.Message.frame_title => try self.applyFrameTitle(payload),
            protocol.Message.frame_alpha => try self.applyFrameAlpha(payload),
            protocol.Message.frame_focus => try self.applyFrameFocus(payload),
            protocol.Message.frame_destroy => try self.applyFrameDestroy(payload.envelope, payload.bytes),
            protocol.Message.frame_decorations => try self.applyFrameDecorations(payload),
            protocol.Message.frame_scale => try self.applyFrameScale(payload),
            protocol.Message.frame_fullscreen => try self.applyFrameFullscreen(payload),
            protocol.Message.frame_monitor => try self.applyFrameMonitor(payload),
            protocol.Message.frame_maximize => try self.applyFrameMaximize(payload),
            protocol.Message.frame_geometry => try self.applyFrameGeometry(payload),
            protocol.Message.frame_icon => try self.applyFrameIcon(payload),
            protocol.Message.frame_size_hints => try self.applyFrameSizeHints(payload),
            protocol.Message.frame_z_order => try self.applyFrameZOrder(payload),
            protocol.Message.frame_parent => try self.applyFrameParent(payload),
            protocol.Message.border_update => try self.applyBorderUpdate(payload),
            protocol.Message.window_create => try self.applyWindowCreate(payload),
            protocol.Message.window_delete => try self.applyWindowDelete(payload),
            protocol.Message.window_patch => try self.applyWindowPatch(payload),
            protocol.Message.window_geometry => try self.applyWindowGeometry(payload),
            protocol.Message.window_zones => try self.applyWindowZones(payload),
            protocol.Message.window_position => try self.applyWindowPosition(payload),
            protocol.Message.mouse_highlight => try self.applyMouseHighlight(payload),
            protocol.Message.tooltip_show => try self.applyTooltipShow(payload),
            protocol.Message.tooltip_move => try self.applyTooltipMove(payload),
            protocol.Message.tooltip_hide => try self.applyTooltipHide(payload),
            protocol.Message.cursor_update => try self.applyCursorUpdate(payload),
            protocol.Message.clear_area => try self.applyClearArea(payload),
            protocol.Message.scroll_run => try self.applyScrollRun(payload),
            protocol.Message.divider_update => try self.applyDividerUpdate(payload),
            protocol.Message.fringe_update => try self.applyFringeUpdate(payload),
            protocol.Message.fringe_bitmap_define => try self.applyFringeBitmapDefine(payload),
            protocol.Message.fringe_bitmap_delete => try self.applyFringeBitmapDelete(payload),
            protocol.Message.window_scroll_state => try self.applyWindowScrollState(payload),
            protocol.Message.scrollbar_state => try self.applyWindowScrollState(payload),
            protocol.Message.window_face => try self.applyWindowFace(payload),
            protocol.Message.damage_rects => try self.applyDamageRects(payload),
            protocol.Message.flush => try self.applyFlush(payload),
            protocol.Message.render_hint => try self.applyRenderHint(payload),
            protocol.Message.face_define => try self.applyFaceDefine(payload),
            protocol.Message.face_patch => try self.applyFacePatch(payload),
            protocol.Message.face_delete => try self.applyFaceDelete(payload),
            protocol.Message.font_define => try self.applyFontDefine(payload),
            protocol.Message.font_patch => try self.applyFontPatch(payload),
            protocol.Message.font_metrics => try self.applyFontMetrics(payload),
            protocol.Message.font_delete => try self.applyFontDelete(payload),
            protocol.Message.string_define => try self.applyStringDefine(payload),
            protocol.Message.string_delete => try self.applyStringDelete(payload),
            protocol.Message.image_define => try self.applyImageDefine(payload),
            protocol.Message.image_data => try self.applyImageData(payload),
            protocol.Message.image_delete => try self.applyImageDelete(payload),
            protocol.Message.resource_snapshot => try self.applyResourceSnapshot(payload),
            protocol.Message.atlas_define => try self.atlases.applyDefine(try protocol.decodeAtlasDefine(payload.bytes)),
            protocol.Message.atlas_page_update => {
                var page = try protocol.decodeAtlasPageUpdate(self.allocator, payload.bytes);
                defer protocol.freeAtlasPageUpdate(self.allocator, &page);
                try self.atlases.applyPageUpdate(page);
            },
            protocol.Message.atlas_glyph_add => try self.atlases.applyGlyphAdd(try protocol.decodeAtlasGlyphAdd(payload.bytes)),
            protocol.Message.atlas_invalidate => try self.atlases.applyInvalidate(try protocol.decodeAtlasInvalidate(payload.bytes)),
            protocol.Message.ime_attach => try self.applyImeAttach(payload),
            protocol.Message.ime_detach => try self.applyImeDetach(payload),
            protocol.Message.ime_focus => try self.applyImeFocus(payload),
            protocol.Message.ime_cursor_rect => try self.applyImeCursorRect(payload),
            protocol.Message.ime_allowed_input => try self.applyImeAllowedInput(payload),
            protocol.Message.ime_surrounding_text => try self.applyImeSurroundingText(payload),
            protocol.Message.ime_reset => try self.applyImeReset(payload),
            else => self.stats.control_messages += 1,
        }
        self.next_sequence = next_sequence;
        if (previous_session == null) self.session_id = payload.envelope.session_id;
    }

    fn clearVisualState(self: *Scene) void {
        self.clearTitle();
        self.alpha = null;
        self.decorations = null;
        self.scale = null;
        self.fullscreen = null;
        self.monitor = null;
        self.maximize = null;
        self.geometry = null;
        self.icon = null;
        self.size_hints = null;
        self.z_order = null;
        self.parent = null;
        self.border = null;
        self.clearGlyphRuns();
        self.windows.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.damage.deinit(self.allocator);
        self.clear_areas.deinit(self.allocator);
        self.scroll_runs.deinit(self.allocator);
        self.dividers.deinit(self.allocator);
        self.fringes.deinit(self.allocator);
        self.scroll_states.deinit(self.allocator);
        self.window_faces.deinit(self.allocator);
        self.window_geometries.deinit(self.allocator);
        self.window_zones.deinit(self.allocator);
        self.window_positions.deinit(self.allocator);
        for (self.text.items) |line| self.allocator.free(line.bytes);
        self.text.deinit(self.allocator);
        self.windows = .empty;
        self.rows = .empty;
        self.glyph_runs = .empty;
        self.damage = .empty;
        self.clear_areas = .empty;
        self.scroll_runs = .empty;
        self.dividers = .empty;
        self.fringes = .empty;
        self.scroll_states = .empty;
        self.window_faces = .empty;
        self.window_geometries = .empty;
        self.window_zones = .empty;
        self.window_positions = .empty;
        self.text = .empty;
        self.mode_line_count = 0;
        self.aux_line_count = 0;
        self.ime_context_count = 0;
        self.frame_header = null;
        self.cursor = null;
        self.present = null;
        self.flush = null;
        self.render_hint = null;
        self.viewport = null;
        self.tooltip = null;
        self.menu_open = null;
        if (self.window_tree) |*tree| protocol.freeWindowTreeSnapshot(self.allocator, tree);
        self.window_tree = null;
        if (self.menu_model) |*model| protocol.freeMenuModelSnapshot(self.allocator, model);
        self.menu_model = null;
        if (self.toolbar) |*model| protocol.freeToolbarModel(self.allocator, model);
        self.toolbar = null;
        self.dialog = null;
    }

    fn clearGlyphRuns(self: *Scene) void {
        for (self.glyph_runs.items) |run| self.allocator.free(run.text);
        self.glyph_runs.deinit(self.allocator);
        self.glyph_runs = .empty;
    }

    fn clearTitle(self: *Scene) void {
        if (self.title) |title| self.allocator.free(title);
        self.title = null;
    }

    fn applyGlyphRun(self: *Scene, payload: protocol.Payload) Error!void {
        const wire = try decodeGlyphRun(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (payload.envelope.frame_id != frame.frame_id) return Error.InvalidMessage;
        if (self.frame_header == null) return Error.FrameNotActive;

        var window: ?Window = null;
        for (self.windows.items) |candidate| {
            if (candidate.id == wire.window_id) {
                window = candidate;
                break;
            }
        }
        const owner = window orelse return Error.InvalidMessage;
        if (wire.row_index >= self.rows.items.len) return Error.InvalidMessage;
        if (self.rows.items[wire.row_index].window_id != owner.id) return Error.InvalidMessage;
        const header = self.frame_header.?;
        if (!inside(wire.x, wire.width, header.logical_width) or
            !inside(wire.y, wire.height, header.logical_height)) return Error.InvalidMessage;

        if (wire.schema == 3) {
            if (wire.face_id == 0) return Error.InvalidMessage;
            const face = self.faces.lookup(wire.face_id) orelse return Error.ResourceNotLive;
            if (face.generation != wire.face_generation) return Error.StaleGeneration;
            if (!face.payload.presence.font or face.payload.font_id != wire.font_id)
                return Error.InvalidMessage;
            const font = self.fonts.lookup(wire.font_id) orelse return Error.ResourceNotLive;
            if (font.generation != face.payload.font_generation) return Error.StaleGeneration;
            for (wire.glyphs[0..wire.glyph_count]) |glyph| {
                if (self.atlases.findGlyphPixels(wire.font_id, glyph.glyph_id) == null)
                    return Error.ResourceNotLive;
            }
        } else if (wire.face_id != 0) {
            const face = self.faces.lookup(wire.face_id) orelse return Error.ResourceNotLive;
            if (face.generation != wire.face_generation) return Error.StaleGeneration;
        }

        var existing_index: ?usize = null;
        for (self.glyph_runs.items, 0..) |active, index| {
            if (active.run_id == wire.run_id) {
                existing_index = index;
                break;
            }
        }
        if (existing_index) |index| {
            if (wire.generation <= self.glyph_runs.items[index].generation)
                return Error.StaleGeneration;
        } else if (self.glyph_runs.items.len == max_glyph_runs) {
            return Error.ResourceTableFull;
        }

        const owned = try self.allocator.dupeZ(u8, wire.text);
        errdefer self.allocator.free(owned);
        var next: GlyphRun = .{
            .run_id = wire.run_id,
            .generation = wire.generation,
            .window_id = wire.window_id,
            .row_index = wire.row_index,
            .face_id = wire.face_id,
            .face_generation = wire.face_generation,
            .font_id = wire.font_id,
            .x = wire.x,
            .y = wire.y,
            .width = wire.width,
            .height = wire.height,
            .text = owned,
            .shaped = wire.schema == 3,
            .shaped_count = wire.glyph_count,
        };
        if (wire.schema == 3) @memcpy(next.shaped_glyphs[0..wire.glyph_count], wire.glyphs[0..wire.glyph_count]);
        if (existing_index) |index| {
            const old = self.glyph_runs.items[index].text;
            self.glyph_runs.items[index] = next;
            self.allocator.free(old);
        } else {
            try self.glyph_runs.append(self.allocator, next);
        }
        self.stats.control_messages += 1;
    }

    fn applyGlyphRunDelete(self: *Scene, payload: protocol.Payload) Error!void {
        const wire = try decodeGlyphRunDelete(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (payload.envelope.frame_id != frame.frame_id) return Error.InvalidMessage;
        if (self.frame_header == null) return Error.FrameNotActive;

        var window: ?Window = null;
        for (self.windows.items) |candidate| {
            if (candidate.id == wire.window_id) {
                window = candidate;
                break;
            }
        }
        const owner = window orelse return Error.InvalidMessage;
        if (wire.row_index >= self.rows.items.len) return Error.InvalidMessage;
        if (self.rows.items[wire.row_index].window_id != owner.id) return Error.InvalidMessage;

        for (self.glyph_runs.items, 0..) |active, index| {
            if (active.run_id != wire.run_id or active.window_id != wire.window_id or
                active.row_index != wire.row_index) continue;
            if (active.generation != wire.generation) return Error.StaleGeneration;
            const owned = active.text;
            _ = self.glyph_runs.orderedRemove(index);
            self.allocator.free(owned);
            self.stats.control_messages += 1;
            return;
        }
        return Error.InvalidMessage;
    }

    fn applyFrameDestroy(self: *Scene, envelope: protocol.Envelope, bytes: []const u8) Error!void {
        if (bytes.len != 8) return Error.InvalidMessage;
        const frame_id = std.mem.readInt(u32, bytes[0..4], .little);
        const generation = std.mem.readInt(u32, bytes[4..8], .little);
        if (frame_id == 0 or generation == 0 or envelope.frame_id != frame_id) return Error.InvalidMessage;
        try self.frames.destroy(frame_id, generation);
        self.strings.clear(self.allocator);
        if (self.frame) |frame| {
            if (frame.frame_id == frame_id and frame.generation == generation) self.frame = null;
        }
        self.clearVisualState();
        self.stats.control_messages += 1;
    }

    fn applyFramePatch(self: *Scene, payload: protocol.Payload) Error!void {
        // Decode and derive every selected field before the first mutation so
        // an invalid patch cannot leave mixed frame/visual state behind.
        const patch = try protocol.decodeFramePatch(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (payload.envelope.frame_id != frame.frame_id or
            frame.generation != patch.frame_generation)
            return Error.InvalidMessage;
        const current = self.frames.lookup(frame.frame_id) orelse
            return Error.FrameNotActive;
        if (current.status != .active or current.generation != frame.generation)
            return Error.FrameNotActive;

        const next_visibility = if (patch.presence & protocol.FramePatchFlags.visibility != 0)
            patch.visibility
        else
            current.visibility;
        const requested_focused = if (patch.presence & protocol.FramePatchFlags.focus != 0)
            patch.focused
        else
            current.focused;
        if (patch.presence & protocol.FramePatchFlags.focus != 0 and
            patch.focused and next_visibility != .visible) return Error.InvalidMessage;
        const next_focused = if (next_visibility != .visible)
            false
        else
            requested_focused;
        if (next_focused and next_visibility != .visible) return Error.InvalidMessage;

        if (patch.presence & protocol.FramePatchFlags.visibility != 0)
            try self.frames.setVisibility(frame.frame_id, frame.generation, patch.visibility);
        if (patch.presence & protocol.FramePatchFlags.focus != 0)
            try self.frames.setFocus(frame.frame_id, frame.generation, patch.focused);
        if (patch.presence & protocol.FramePatchFlags.alpha != 0) {
            self.alpha = .{
                .active_opacity = patch.active_opacity,
                .inactive_opacity = patch.inactive_opacity,
                .background_opacity = patch.background_opacity,
                .frame_generation = frame.generation,
            };
        }
        if (patch.presence & protocol.FramePatchFlags.decorations != 0) {
            self.decorations = .{
                .decorated = patch.decorated,
                .frame_generation = frame.generation,
            };
        }
        if (patch.presence & protocol.FramePatchFlags.scale != 0) {
            self.scale = .{
                .scale = patch.scale,
                .dpi_x = patch.dpi_x,
                .dpi_y = patch.dpi_y,
                .frame_generation = frame.generation,
            };
        }
        self.stats.control_messages += 1;
    }

    fn applyFrameSnapshot(self: *Scene, payload: protocol.Payload) Error!void {
        const snapshot = try protocol.decodeFrameSnapshot(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (payload.envelope.frame_id != frame.frame_id or
            frame.generation != snapshot.frame_generation)
            return Error.InvalidMessage;
        const current = self.frames.lookup(frame.frame_id) orelse
            return Error.FrameNotActive;
        if (current.status != .active or current.generation != frame.generation)
            return Error.FrameNotActive;
        if (snapshot.focused and snapshot.visibility != .visible)
            return Error.InvalidMessage;

        try self.frames.setVisibility(frame.frame_id, frame.generation, snapshot.visibility);
        try self.frames.setFocus(frame.frame_id, frame.generation, snapshot.focused);
        self.alpha = .{
            .active_opacity = snapshot.active_opacity,
            .inactive_opacity = snapshot.inactive_opacity,
            .background_opacity = snapshot.background_opacity,
            .frame_generation = frame.generation,
        };
        self.decorations = .{
            .decorated = snapshot.decorated,
            .frame_generation = frame.generation,
        };
        self.scale = .{
            .scale = snapshot.scale,
            .dpi_x = snapshot.dpi_x,
            .dpi_y = snapshot.dpi_y,
            .frame_generation = frame.generation,
        };
        self.geometry = .{
            .frame_generation = frame.generation,
            .outer = snapshot.outer,
            .content = snapshot.content,
            .text = snapshot.text,
            .window = snapshot.window,
            .body = snapshot.body,
        };
        self.fullscreen = .{
            .mode = snapshot.fullscreen,
            .frame_generation = frame.generation,
        };
        self.maximize = .{
            .flags = snapshot.maximize_flags,
            .frame_generation = frame.generation,
        };
        self.stats.control_messages += 1;
    }

    fn applyFrameVisibility(self: *Scene, payload: protocol.Payload) Error!void {
        const state = try protocol.decodeFrameVisibility(payload.bytes);
        try protocol.validateFrameVisibilityEnvelope(state, payload.envelope);
        try self.frames.setVisibility(state.frame_id, state.frame_generation, state.state);
        self.stats.control_messages += 1;
    }

    fn applyFrameFocus(self: *Scene, payload: protocol.Payload) Error!void {
        const focus = try protocol.decodeFrameFocus(payload.bytes);
        try protocol.validateFrameFocusEnvelope(focus, payload.envelope);
        try self.frames.setFocus(focus.frame_id, focus.frame_generation, focus.focused);
        self.stats.control_messages += 1;
    }

    fn applyFrameTitle(self: *Scene, payload: protocol.Payload) Error!void {
        const title = try protocol.decodeFrameTitle(payload.bytes);
        try protocol.validateFrameTitleEnvelope(title, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != title.frame_generation)
            return Error.InvalidMessage;

        const resource = self.strings.lookup(title.string_resource_id) orelse
            return Error.ResourceNotLive;
        if (resource.generation != title.string_generation)
            return Error.ResourceNotLive;

        const owned = try self.allocator.dupeZ(u8, resource.bytes);
        errdefer self.allocator.free(owned);
        self.clearTitle();
        self.title = owned;
        self.stats.control_messages += 1;
    }

    fn applyFrameAlpha(self: *Scene, payload: protocol.Payload) Error!void {
        const alpha = try protocol.decodeFrameAlpha(payload.bytes);
        try protocol.validateFrameAlphaEnvelope(alpha, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != alpha.frame_generation)
            return Error.InvalidMessage;
        self.alpha = alpha;
        self.stats.control_messages += 1;
    }

    fn applyFrameDecorations(self: *Scene, payload: protocol.Payload) Error!void {
        const decorations = try protocol.decodeFrameDecorations(payload.bytes);
        try protocol.validateFrameDecorationsEnvelope(decorations, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != decorations.frame_generation)
            return Error.InvalidMessage;
        self.decorations = decorations;
        self.stats.control_messages += 1;
    }

    fn applyFrameScale(self: *Scene, payload: protocol.Payload) Error!void {
        const scale = try protocol.decodeFrameScale(payload.bytes);
        try protocol.validateFrameScaleEnvelope(scale, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != scale.frame_generation)
            return Error.InvalidMessage;
        self.scale = scale;
        self.stats.control_messages += 1;
    }

    fn applyFrameFullscreen(self: *Scene, payload: protocol.Payload) Error!void {
        const fullscreen = try protocol.decodeFrameFullscreen(payload.bytes);
        try protocol.validateFrameFullscreenEnvelope(fullscreen, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != fullscreen.frame_generation)
            return Error.InvalidMessage;
        self.fullscreen = fullscreen;
        self.stats.control_messages += 1;
    }

    fn applyFrameMonitor(self: *Scene, payload: protocol.Payload) Error!void {
        const monitor = try protocol.decodeFrameMonitor(payload.bytes);
        try protocol.validateFrameMonitorEnvelope(monitor, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != monitor.frame_generation)
            return Error.InvalidMessage;
        self.monitor = monitor;
        self.stats.control_messages += 1;
    }

    fn applyFrameMaximize(self: *Scene, payload: protocol.Payload) Error!void {
        const maximize = try protocol.decodeFrameMaximize(payload.bytes);
        try protocol.validateFrameMaximizeEnvelope(maximize, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != maximize.frame_generation)
            return Error.InvalidMessage;
        self.maximize = maximize;
        self.stats.control_messages += 1;
    }

    fn applyFrameGeometry(self: *Scene, payload: protocol.Payload) Error!void {
        const geometry = try protocol.decodeFrameGeometry(payload.bytes);
        try protocol.validateFrameGeometryEnvelope(geometry, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != geometry.frame_generation)
            return Error.InvalidMessage;
        self.geometry = geometry;
        self.stats.control_messages += 1;
    }

    fn applyFrameIcon(self: *Scene, payload: protocol.Payload) Error!void {
        const icon = try protocol.decodeFrameIcon(payload.bytes);
        try protocol.validateFrameIconEnvelope(icon, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != icon.frame_generation)
            return Error.InvalidMessage;

        if (icon.flags & protocol.FrameIconFlags.present != 0) {
            const image = self.images.lookup(icon.image_id) orelse
                return Error.ResourceNotLive;
            if (image.generation != icon.image_generation or !image.complete)
                return Error.ResourceNotLive;
            if (icon.hotspot_x >= image.metadata.width or
                icon.hotspot_y >= image.metadata.height)
                return Error.InvalidMessage;
        }
        self.icon = if (icon.flags & protocol.FrameIconFlags.present != 0) icon else null;
        self.stats.control_messages += 1;
    }

    fn applyFrameSizeHints(self: *Scene, payload: protocol.Payload) Error!void {
        const hints = try protocol.decodeFrameSizeHints(payload.bytes);
        try protocol.validateFrameSizeHintsEnvelope(hints, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != hints.frame_generation)
            return Error.InvalidMessage;
        self.size_hints = hints;
        self.stats.control_messages += 1;
    }

    fn applyFrameZOrder(self: *Scene, payload: protocol.Payload) Error!void {
        const z_order = try protocol.decodeFrameZOrder(payload.bytes);
        try protocol.validateFrameZOrderEnvelope(z_order, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != z_order.frame_generation)
            return Error.InvalidMessage;

        const needs_relative = z_order.operation == .above or z_order.operation == .below;
        if (needs_relative) {
            const relative = self.frames.lookup(z_order.relative_frame_id) orelse
                return Error.FrameNotActive;
            if (relative.status != .active or
                relative.generation != z_order.relative_frame_generation or
                relative.id == frame.frame_id)
                return Error.InvalidMessage;
        }
        self.z_order = z_order;
        self.stats.control_messages += 1;
    }

    fn applyFrameParent(self: *Scene, payload: protocol.Payload) Error!void {
        const parent = try protocol.decodeFrameParent(payload.bytes);
        try protocol.validateFrameParentEnvelope(parent, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != parent.child_frame_generation)
            return Error.InvalidMessage;

        const has_parent = parent.flags & protocol.FrameParentFlags.present != 0;
        if (has_parent) {
            if (parent.parent_frame_id == frame.frame_id) return Error.InvalidMessage;
            const parent_frame = self.frames.lookup(parent.parent_frame_id) orelse
                return Error.FrameNotActive;
            if (parent_frame.status != .active or
                parent_frame.generation != parent.parent_frame_generation)
                return Error.InvalidMessage;
        }
        self.parent = parent;
        self.stats.control_messages += 1;
    }

    fn applyWindowCreate(self: *Scene, payload: protocol.Payload) Error!void {
        const create = try protocol.decodeWindowCreate(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != create.frame_id or
            frame.generation != create.frame_generation or
            payload.envelope.frame_id != create.frame_id)
            return Error.InvalidMessage;
        if (self.windows.items.len >= protocol.max_window_tree_nodes)
            return Error.ResourceTableFull;
        for (self.windows.items) |existing| {
            if (existing.id == create.node.window_id) return Error.InvalidTable;
        }
        if (create.node.parent_window_id != 0 and
            findWindow(self.windows.items, create.node.parent_window_id) == null)
            return Error.InvalidMessage;
        try self.windows.append(self.allocator, .{
            .id = create.node.window_id,
            .frame_id = create.frame_id,
            .parent_id = create.node.parent_window_id,
            .x = create.node.x,
            .y = create.node.y,
            .width = create.node.width,
            .height = create.node.height,
            .visible = create.node.visible(),
            .default_face_id = create.node.default_face_id,
            .depth = create.node.depth,
        });
        self.stats.control_messages += 1;
    }

    fn applyWindowDelete(self: *Scene, payload: protocol.Payload) Error!void {
        const delete = try protocol.decodeWindowDelete(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != delete.frame_id or
            frame.generation != delete.frame_generation or
            payload.envelope.frame_id != delete.frame_id)
            return Error.InvalidMessage;
        var index: ?usize = null;
        for (self.windows.items, 0..) |window, window_index| {
            if (window.id == delete.window_id) {
                index = window_index;
                break;
            }
        }
        const window_index = index orelse return Error.InvalidMessage;
        const window_id = self.windows.items[window_index].id;
        for (self.windows.items) |window| {
            if (window.parent_id == window_id) return Error.ResourceNotLive;
        }
        for (self.rows.items) |row| {
            if (row.window_id == window_id) return Error.ResourceNotLive;
        }
        for (self.glyph_runs.items) |run| {
            if (run.window_id == window_id) return Error.ResourceNotLive;
        }
        for (self.image_placements[0..self.image_placement_count]) |placement| {
            if (placement.window_id == window_id) return Error.ResourceNotLive;
        }
        for (self.cursors[0..self.cursor_count]) |cursor| {
            if (cursor.window_id == window_id) return Error.ResourceNotLive;
        }
        _ = self.windows.orderedRemove(window_index);

        self.removeWindowFacesForWindow(window_id);
        self.removeWindowGeometriesForWindow(window_id);
        self.removeWindowZonesForWindow(window_id);
        self.removeWindowPositionsForWindow(window_id);
        self.removeScrollStatesForWindow(window_id);
        self.removeMouseHighlightsForWindow(window_id);
        if (self.tooltip) |tip| {
            if (tip.window_id == window_id) self.tooltip = null;
        }
        if (self.menu_open) |open| {
            if (open.window_id == window_id) self.menu_open = null;
        }
        if (self.dialog) |dialog| {
            if (dialog.window_id == window_id) self.dialog = null;
        }
        var ime_index: usize = 0;
        while (ime_index < self.ime_context_count) {
            if (self.ime_contexts[ime_index].window_id == window_id) {
                self.ime_contexts[ime_index] = self.ime_contexts[self.ime_context_count - 1];
                self.ime_context_count -= 1;
            } else ime_index += 1;
        }
        self.stats.control_messages += 1;
    }

    fn applyWindowPatch(self: *Scene, payload: protocol.Payload) Error!void {
        const patch = try protocol.decodeWindowPatch(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != patch.frame_id or
            frame.generation != patch.frame_generation or
            payload.envelope.frame_id != patch.frame_id)
            return Error.InvalidMessage;
        var index: ?usize = null;
        for (self.windows.items, 0..) |window, window_index| {
            if (window.id == patch.window_id) {
                index = window_index;
                break;
            }
        }
        const window_index = index orelse return Error.InvalidMessage;
        if (self.windows.items[window_index].frame_id != patch.frame_id)
            return Error.InvalidMessage;
        var updated = self.windows.items[window_index];
        const f = protocol.WindowPatchFlags;
        if (patch.flags & f.x != 0) updated.x = patch.x;
        if (patch.flags & f.y != 0) updated.y = patch.y;
        if (patch.flags & f.width != 0) updated.width = patch.width;
        if (patch.flags & f.height != 0) updated.height = patch.height;
        if (patch.flags & f.visible != 0) updated.visible = patch.visible;
        if (patch.flags & f.default_face != 0) updated.default_face_id = patch.default_face_id;
        if (patch.flags & f.parent != 0) {
            if (patch.parent_window_id == updated.id) return Error.InvalidMessage;
            const parent_window = findWindow(self.windows.items, patch.parent_window_id) orelse
                return Error.InvalidMessage;
            var candidate = parent_window.parent_id;
            while (candidate != 0) {
                if (candidate == updated.id) return Error.InvalidMessage;
                const owner = findWindow(self.windows.items, candidate) orelse
                    return Error.InvalidMessage;
                candidate = owner.parent_id;
            }
            updated.parent_id = patch.parent_window_id;
            updated.depth = parent_window.depth + 1;
        }
        if (patch.flags & f.depth != 0) updated.depth = patch.depth;
        if (updated.parent_id != 0) {
            const parent_window = findWindow(self.windows.items, updated.parent_id) orelse
                return Error.InvalidMessage;
            if (updated.depth != parent_window.depth + 1 or
                updated.depth > protocol.max_window_tree_depth)
                return Error.InvalidMessage;
        } else if (updated.depth != 0) return Error.InvalidMessage;
        if (updated.width <= 0 or updated.height <= 0 or updated.x < 0 or updated.y < 0)
            return Error.InvalidMessage;
        for (self.windows.items, 0..) |window, check_index| {
            const candidate = if (window.id == updated.id and check_index == window_index)
                updated
            else
                window;
            if (candidate.frame_id != patch.frame_id) return Error.InvalidMessage;
            for (self.windows.items[0..check_index]) |prior| {
                if (prior.id == candidate.id) return Error.InvalidMessage;
            }
            if (candidate.parent_id == candidate.id) return Error.InvalidMessage;
            if (candidate.parent_id == 0) {
                if (candidate.depth != 0) return Error.InvalidMessage;
                continue;
            }
            const parent_window = findWindow(self.windows.items, candidate.parent_id) orelse
                return Error.InvalidMessage;
            if (candidate.depth != parent_window.depth + 1 or
                candidate.depth > protocol.max_window_tree_depth)
                return Error.InvalidMessage;
            var hops: usize = 0;
            var ancestor_id = parent_window.parent_id;
            while (ancestor_id != 0) {
                hops += 1;
                if (hops > protocol.max_window_tree_depth or ancestor_id == candidate.id)
                    return Error.InvalidMessage;
                const ancestor = findWindow(self.windows.items, ancestor_id) orelse
                    return Error.InvalidMessage;
                ancestor_id = ancestor.parent_id;
            }
        }
        for (self.cursors[0..self.cursor_count]) |*cursor| {
            if (cursor.window_id == updated.id) cursor.* = try cursor.withOwner(updated);
        }
        self.cursor = if (self.cursor_count == 0) null else blk: {
            for (self.cursors[0..self.cursor_count]) |candidate| {
                if (candidate.active) break :blk candidate;
            }
            break :blk self.cursors[0];
        };
        for (self.ime_contexts[0..self.ime_context_count]) |*context| {
            if (context.window_id == updated.id) {
                if (!inside(context.cursor_x, context.cursor_width, updated.width) or
                    !inside(context.cursor_y, context.cursor_height, updated.height))
                {
                    context.cursor_x = 0;
                    context.cursor_y = 0;
                    context.cursor_width = 0;
                    context.cursor_height = 0;
                }
            }
        }
        self.windows.items[window_index] = updated;
        for (self.window_geometries.items) |*geometry| {
            if (geometry.window_id == updated.id and !windowGeometryFits(updated, geometry.*)) {
                self.removeWindowGeometriesForWindow(updated.id);
                break;
            }
        }
        for (self.window_zones.items) |*zones| {
            if (zones.window_id == updated.id and !windowZonesFit(updated, zones.*)) {
                self.removeWindowZonesForWindow(updated.id);
                break;
            }
        }
        self.stats.control_messages += 1;
    }

    fn applyCursorUpdate(self: *Scene, payload: protocol.Payload) Error!void {
        const update = try decodeCursorUpdate(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (self.frame_header == null) return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != update.frame_generation)
            return Error.InvalidMessage;
        const owner = findWindow(self.windows.items, update.cursor.window_id) orelse
            return Error.InvalidMessage;
        _ = try update.cursor.withOwner(owner);
        var existing_active_count: usize = 0;
        var replaced_index: ?usize = null;
        for (self.cursors[0..self.cursor_count], 0..) |cursor, index| {
            if (cursor.active) existing_active_count += 1;
            if (cursor.window_id == update.cursor.window_id) replaced_index = index;
        }
        const replacement = replaced_index != null;
        const projected_active_count = if (replacement) blk: {
            const old = self.cursors[replaced_index.?];
            break :blk existing_active_count - @intFromBool(old.active) + @intFromBool(update.cursor.active);
        } else existing_active_count + @intFromBool(update.cursor.active);
        if (projected_active_count != 1) return Error.InvalidMessage;
        if (!replacement and self.cursor_count == max_scene_cursors) return Error.Unsupported;
        var replaced = false;
        for (self.cursors[0..self.cursor_count]) |*cursor| {
            if (cursor.window_id == update.cursor.window_id) {
                cursor.* = update.cursor;
                replaced = true;
                break;
            }
        }
        if (!replaced) {
            if (self.cursor_count == max_scene_cursors) return Error.Unsupported;
            self.cursors[self.cursor_count] = update.cursor;
            self.cursor_count += 1;
        }
        self.cursor = update.cursor;
        self.stats.control_messages += 1;
    }

    fn applyDamageRects(self: *Scene, payload: protocol.Payload) Error!void {
        const decoded = try decodeDamageRects(self.allocator, payload.bytes);
        defer freeDamageRects(self.allocator, decoded);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != decoded.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        for (decoded.rects) |rect| {
            if (!rectInFrame(rect, header)) return Error.InvalidMessage;
        }

        var replacement: std.ArrayList(Rect) = .empty;
        errdefer replacement.deinit(self.allocator);
        try replacement.appendSlice(self.allocator, decoded.rects);
        var old = self.damage;
        self.damage = replacement;
        old.deinit(self.allocator);
        self.stats.control_messages += 1;
    }

    fn applyFlush(self: *Scene, payload: protocol.Payload) Error!void {
        const flush = try protocol.decodeFrameFlush(payload.bytes);
        try protocol.validateFrameFlushEnvelope(flush, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != flush.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation or
            header.redisplay_generation != flush.redisplay_generation or
            header.sequence != flush.frame_sequence)
            return Error.InvalidMessage;
        self.flush = flush;
        self.stats.control_messages += 1;
    }

    fn applyRenderHint(self: *Scene, payload: protocol.Payload) Error!void {
        const hint = try protocol.decodeRenderHint(payload.bytes);
        try protocol.validateRenderHintEnvelope(hint, payload.envelope);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != hint.frame_generation)
            return Error.InvalidMessage;
        self.render_hint = hint;
        self.stats.control_messages += 1;
    }

    pub fn placeImage(self: *Scene, placement: ImagePlacement) Error!void {
        _ = self.frame_header orelse return Error.FrameNotActive;
        const owner = findWindow(self.windows.items, placement.window_id) orelse
            return Error.InvalidMessage;
        if (!inside(placement.x, placement.width, owner.width) or
            !inside(placement.y, placement.height, owner.height))
            return Error.InvalidMessage;
        const image = self.images.lookup(placement.image_id) orelse
            return Error.ResourceNotLive;
        if (image.generation != placement.image_generation or !image.complete or
            image.bytes.len != image.metadata.total_byte_count)
            return Error.ResourceNotLive;
        for (self.image_placements[0..self.image_placement_count]) |old| {
            if (old.placement_id == placement.placement_id)
                return Error.InvalidTable;
        }
        if (self.image_placement_count == max_image_placements)
            return Error.Unsupported;
        self.image_placements[self.image_placement_count] = placement;
        self.image_placement_count += 1;
    }

    fn removeGlyphRunsForFace(
        self: *Scene,
        face_id: u32,
        face_generation: u32,
    ) void {
        var index: usize = 0;
        while (index < self.glyph_runs.items.len) {
            const run = self.glyph_runs.items[index];
            if (run.face_id == face_id and run.face_generation == face_generation) {
                const owned = run.text;
                _ = self.glyph_runs.orderedRemove(index);
                self.allocator.free(owned);
            } else index += 1;
        }
    }

    fn removeWindowFacesForFace(
        self: *Scene,
        face_id: u32,
        face_generation: u32,
    ) void {
        var index: usize = 0;
        while (index < self.window_faces.items.len) {
            const state = self.window_faces.items[index];
            if (state.face_id == face_id and state.face_generation == face_generation) {
                _ = self.window_faces.orderedRemove(index);
            } else index += 1;
        }
    }

    fn removeWindowFacesForWindow(self: *Scene, window_id: u64) void {
        var index: usize = 0;
        while (index < self.window_faces.items.len) {
            if (self.window_faces.items[index].window_id == window_id) {
                _ = self.window_faces.orderedRemove(index);
            } else index += 1;
        }
    }

    fn removeWindowGeometriesForWindow(self: *Scene, window_id: u64) void {
        var index: usize = 0;
        while (index < self.window_geometries.items.len) {
            if (self.window_geometries.items[index].window_id == window_id) {
                _ = self.window_geometries.orderedRemove(index);
            } else index += 1;
        }
    }

    fn removeWindowZonesForWindow(self: *Scene, window_id: u64) void {
        var index: usize = 0;
        while (index < self.window_zones.items.len) {
            if (self.window_zones.items[index].window_id == window_id) {
                _ = self.window_zones.orderedRemove(index);
            } else index += 1;
        }
    }

    fn removeWindowPositionsForWindow(self: *Scene, window_id: u64) void {
        var index: usize = 0;
        while (index < self.window_positions.items.len) {
            if (self.window_positions.items[index].window_id == window_id) {
                _ = self.window_positions.orderedRemove(index);
            } else index += 1;
        }
    }

    fn removeScrollStatesForWindow(self: *Scene, window_id: u64) void {
        var index: usize = 0;
        while (index < self.scroll_states.items.len) {
            if (self.scroll_states.items[index].window_id == window_id) {
                _ = self.scroll_states.orderedRemove(index);
            } else index += 1;
        }
    }

    fn removeMouseHighlightsForWindow(self: *Scene, window_id: u64) void {
        var index: usize = 0;
        while (index < self.mouse_highlight_count) {
            if (self.mouse_highlights[index].window_id == window_id) {
                if (index + 1 < self.mouse_highlight_count) {
                    std.mem.copyForwards(MouseHighlightState, self.mouse_highlights[index .. self.mouse_highlight_count - 1], self.mouse_highlights[index + 1 .. self.mouse_highlight_count]);
                }
                self.mouse_highlight_count -= 1;
            } else index += 1;
        }
    }

    fn removeMouseHighlightsForFace(self: *Scene, face_id: u32, face_generation: u32) void {
        var index: usize = 0;
        while (index < self.mouse_highlight_count) {
            if (self.mouse_highlights[index].face_id == face_id and
                self.mouse_highlights[index].face_generation == face_generation)
            {
                if (index + 1 < self.mouse_highlight_count) {
                    std.mem.copyForwards(MouseHighlightState, self.mouse_highlights[index .. self.mouse_highlight_count - 1], self.mouse_highlights[index + 1 .. self.mouse_highlight_count]);
                }
                self.mouse_highlight_count -= 1;
            } else index += 1;
        }
    }

    fn removeGlyphRunsForFont(self: *Scene, font_id: u32) void {
        var index: usize = 0;
        while (index < self.glyph_runs.items.len) {
            if (self.glyph_runs.items[index].font_id == font_id) {
                const owned = self.glyph_runs.items[index].text;
                _ = self.glyph_runs.orderedRemove(index);
                self.allocator.free(owned);
            } else index += 1;
        }
    }

    fn removeFringesForBitmap(self: *Scene, bitmap_id: u32) void {
        var index: usize = 0;
        while (index < self.fringes.items.len) {
            if (self.fringes.items[index].fringe_id == bitmap_id) {
                _ = self.fringes.orderedRemove(index);
            } else index += 1;
        }
    }

    fn applyWindowTreeSnapshot(self: *Scene, payload: protocol.Payload) Error!void {
        const frame = self.frame orelse return Error.FrameNotActive;
        var tree = try protocol.decodeWindowTreeSnapshot(self.allocator, payload.bytes);
        errdefer protocol.freeWindowTreeSnapshot(self.allocator, &tree);
        if (payload.envelope.frame_id != frame.frame_id or
            tree.header.frame_id != frame.frame_id or
            tree.header.frame_generation != frame.generation)
        {
            protocol.freeWindowTreeSnapshot(self.allocator, &tree);
            return Error.InvalidMessage;
        }
        if (self.window_tree) |*old| protocol.freeWindowTreeSnapshot(self.allocator, old);
        self.window_tree = tree;
        self.stats.control_messages += 1;
    }

    fn applyMenuModel(self: *Scene, payload: protocol.Payload) Error!void {
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        var model = try protocol.decodeMenuModelSnapshot(self.allocator, payload.bytes);
        errdefer protocol.freeMenuModelSnapshot(self.allocator, &model);
        if (payload.envelope.frame_id != frame.frame_id or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation or
            model.header.frame_id != frame.frame_id or
            model.header.frame_generation != frame.generation)
        {
            protocol.freeMenuModelSnapshot(self.allocator, &model);
            return Error.InvalidMessage;
        }
        if (self.menu_model) |old| {
            if (old.header.menu_id == model.header.menu_id and
                model.header.menu_generation <= old.header.menu_generation)
            {
                protocol.freeMenuModelSnapshot(self.allocator, &model);
                return Error.StaleGeneration;
            }
        }
        if (self.menu_model) |*old| protocol.freeMenuModelSnapshot(self.allocator, old);
        self.menu_model = model;
        self.menu_open = null;
        self.stats.control_messages += 1;
    }

    fn findMenuNode(model: protocol.MenuModelSnapshot, item_id: u32) ?protocol.MenuNode {
        for (model.nodes) |node| {
            if (node.item_id == item_id) return node;
        }
        return null;
    }

    fn applyMenuOpen(self: *Scene, payload: protocol.Payload) Error!void {
        const open = try protocol.decodeMenuOpen(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        const model = self.menu_model orelse return Error.ResourceNotLive;
        if (payload.envelope.frame_id != frame.frame_id or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation or
            model.header.menu_id != open.menu_id or
            model.header.menu_generation != open.menu_generation or
            open.frame_generation != frame.generation)
            return Error.InvalidMessage;
        const owner = findWindow(self.windows.items, open.window_id) orelse
            return Error.InvalidMessage;
        const item = findMenuNode(model, open.item_id) orelse
            return Error.ResourceNotLive;
        if (item.kind != .submenu or
            (item.flags & (protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible)) !=
                (protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible) or
            open.x < 0 or open.y < 0 or
            @as(i64, open.x) + open.width > owner.width or
            @as(i64, open.y) + open.height > owner.height)
            return Error.InvalidMessage;
        self.menu_open = open;
        self.stats.control_messages += 1;
    }

    fn applyMenuClose(self: *Scene, payload: protocol.Payload) Error!void {
        const close = try protocol.decodeMenuClose(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        const model = self.menu_model orelse return Error.ResourceNotLive;
        const open = self.menu_open orelse return Error.ResourceNotLive;
        if (payload.envelope.frame_id != frame.frame_id or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation or
            model.header.menu_id != close.menu_id or
            model.header.menu_generation != close.menu_generation or
            open.menu_id != close.menu_id or
            open.menu_generation != close.menu_generation or
            close.frame_generation != frame.generation)
            return Error.InvalidMessage;
        _ = findMenuNode(model, close.item_id) orelse
            return Error.ResourceNotLive;
        self.menu_open = null;
        self.stats.control_messages += 1;
    }

    fn applyMenuPatch(self: *Scene, payload: protocol.Payload) Error!void {
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        const decoded = try protocol.decodeMenuPatch(self.allocator, payload.bytes);
        defer protocol.freeMenuPatchOperations(self.allocator, decoded.operations);
        const current_model = self.menu_model orelse return Error.ResourceNotLive;
        if (payload.envelope.frame_id != frame.frame_id or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation or
            current_model.header.frame_id != decoded.header.frame_id or
            current_model.header.frame_generation != decoded.header.frame_generation or
            current_model.header.menu_id != decoded.header.menu_id or
            current_model.header.menu_generation != decoded.header.expected_generation)
            return Error.InvalidMessage;

        var nodes: [protocol.max_menu_nodes]protocol.MenuNode = undefined;
        var count: usize = current_model.nodes.len;
        @memcpy(nodes[0..count], current_model.nodes);

        for (decoded.operations) |operation| {
            const item_id = operation.node.item_id;
            var existing_index: ?usize = null;
            for (nodes[0..count], 0..) |node, index| {
                if (node.item_id == item_id) {
                    existing_index = index;
                    break;
                }
            }

            switch (operation.operation) {
                .upsert => {
                    if (operation.node.parent_item_id != 0) {
                        var parent_found = false;
                        for (nodes[0..count]) |parent| {
                            if (parent.item_id == operation.node.parent_item_id) {
                                parent_found = true;
                                break;
                            }
                        }
                        if (!parent_found) return Error.ResourceNotLive;
                    }
                    if (existing_index) |index| {
                        nodes[index] = operation.node;
                    } else {
                        if (count == protocol.max_menu_nodes) return Error.ResourceTableFull;
                        nodes[count] = operation.node;
                        count += 1;
                    }
                },
                .delete => {
                    const index = existing_index orelse return Error.ResourceNotLive;
                    for (nodes[0..count]) |node| {
                        if (node.parent_item_id == item_id) return Error.ResourceNotLive;
                    }
                    if (self.menu_open) |open| {
                        if (open.item_id == item_id) return Error.ResourceNotLive;
                    }
                    if (index + 1 < count) {
                        std.mem.copyForwards(protocol.MenuNode, nodes[index .. count - 1], nodes[index + 1 .. count]);
                    }
                    count -= 1;
                },
            }
        }

        const next_model: protocol.MenuModelSnapshot = .{
            .header = .{
                .frame_id = current_model.header.frame_id,
                .frame_generation = current_model.header.frame_generation,
                .menu_id = current_model.header.menu_id,
                .menu_generation = decoded.header.new_generation,
            },
            .nodes = nodes[0..count],
        };
        try protocol.validateMenuModelSnapshot(next_model);
        const owned_nodes = try self.allocator.alloc(protocol.MenuNode, count);
        @memcpy(owned_nodes, nodes[0..count]);
        if (self.menu_model) |*old| protocol.freeMenuModelSnapshot(self.allocator, old);
        self.menu_model = .{ .header = next_model.header, .nodes = owned_nodes };
        self.menu_open = null;
        self.stats.control_messages += 1;
    }

    fn applyToolbarModel(self: *Scene, payload: protocol.Payload) Error!void {
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        var model = try protocol.decodeToolbarModel(self.allocator, payload.bytes);
        errdefer protocol.freeToolbarModel(self.allocator, &model);
        if (payload.envelope.frame_id != frame.frame_id or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation or
            model.header.frame_id != frame.frame_id or
            model.header.frame_generation != frame.generation)
        {
            return Error.InvalidMessage;
        }
        if (self.toolbar) |old| {
            if (old.header.toolbar_id == model.header.toolbar_id and
                model.header.toolbar_generation <= old.header.toolbar_generation)
            {
                return Error.StaleGeneration;
            }
        }
        if (self.toolbar) |*old| protocol.freeToolbarModel(self.allocator, old);
        self.toolbar = model;
        self.stats.control_messages += 1;
    }

    fn applyToolbarPatch(self: *Scene, payload: protocol.Payload) Error!void {
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        const decoded = try protocol.decodeToolbarPatch(self.allocator, payload.bytes);
        defer protocol.freeToolbarPatchOperations(self.allocator, decoded.operations);
        const current_model = self.toolbar orelse return Error.ResourceNotLive;
        if (payload.envelope.frame_id != frame.frame_id or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation or
            current_model.header.frame_id != decoded.header.frame_id or
            current_model.header.frame_generation != decoded.header.frame_generation or
            current_model.header.toolbar_id != decoded.header.toolbar_id or
            current_model.header.toolbar_generation != decoded.header.expected_generation)
        {
            return Error.InvalidMessage;
        }

        var items: [protocol.max_toolbar_items]protocol.ToolbarItem = undefined;
        var count: usize = current_model.items.len;
        @memcpy(items[0..count], current_model.items);

        for (decoded.operations) |operation| {
            const item_id = operation.item.item_id;
            var existing_index: ?usize = null;
            for (items[0..count], 0..) |item, index| {
                if (item.item_id == item_id) {
                    existing_index = index;
                    break;
                }
            }

            switch (operation.operation) {
                .upsert => {
                    if (existing_index) |index| {
                        items[index] = operation.item;
                    } else {
                        if (count == protocol.max_toolbar_items) return Error.ResourceTableFull;
                        items[count] = operation.item;
                        count += 1;
                    }
                },
                .delete => {
                    const index = existing_index orelse return Error.ResourceNotLive;
                    if (index + 1 < count) {
                        std.mem.copyForwards(protocol.ToolbarItem, items[index .. count - 1], items[index + 1 .. count]);
                    }
                    count -= 1;
                },
            }
        }

        const next_model: protocol.ToolbarModel = .{
            .header = .{
                .frame_id = current_model.header.frame_id,
                .frame_generation = current_model.header.frame_generation,
                .toolbar_id = current_model.header.toolbar_id,
                .toolbar_generation = decoded.header.new_generation,
            },
            .items = items[0..count],
        };
        try protocol.validateToolbarModel(next_model);
        const owned_items = try self.allocator.alloc(protocol.ToolbarItem, count);
        @memcpy(owned_items, next_model.items);
        if (self.toolbar) |*old| protocol.freeToolbarModel(self.allocator, old);
        self.toolbar = .{ .header = next_model.header, .items = owned_items };
        self.stats.control_messages += 1;
    }

    fn validateDialogOwner(self: *Scene, envelope_frame_id: u32, window_id: u64, frame_generation: u32) Error!Window {
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != envelope_frame_id or
            frame.generation != frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        return findWindow(self.windows.items, window_id) orelse Error.InvalidMessage;
    }

    fn applyDialogOpen(self: *Scene, payload: protocol.Payload) Error!void {
        const dialog = try protocol.decodeDialogState(payload.bytes);
        const owner = try self.validateDialogOwner(payload.envelope.frame_id, dialog.window_id, dialog.frame_generation);
        if (dialog.x < 0 or dialog.y < 0 or
            @as(i64, dialog.x) + dialog.width > owner.width or
            @as(i64, dialog.y) + dialog.height > owner.height)
            return Error.InvalidMessage;
        if (self.dialog) |old| {
            if (old.dialog_id == dialog.dialog_id and
                dialog.dialog_generation <= old.dialog_generation)
                return Error.StaleGeneration;
        }
        self.dialog = dialog;
        self.stats.control_messages += 1;
    }

    fn applyDialogUpdate(self: *Scene, payload: protocol.Payload) Error!void {
        const dialog = try protocol.decodeDialogState(payload.bytes);
        const owner = try self.validateDialogOwner(payload.envelope.frame_id, dialog.window_id, dialog.frame_generation);
        const old = self.dialog orelse return Error.ResourceNotLive;
        if (old.dialog_id != dialog.dialog_id)
            return Error.InvalidMessage;
        if (dialog.window_id != old.window_id)
            return Error.InvalidMessage;
        if (dialog.dialog_generation <= old.dialog_generation)
            return Error.StaleGeneration;
        if (dialog.x < 0 or dialog.y < 0 or
            @as(i64, dialog.x) + dialog.width > owner.width or
            @as(i64, dialog.y) + dialog.height > owner.height)
            return Error.InvalidMessage;
        self.dialog = dialog;
        self.stats.control_messages += 1;
    }

    fn applyDialogClose(self: *Scene, payload: protocol.Payload) Error!void {
        const close = try protocol.decodeDialogClose(payload.bytes);
        _ = try self.validateDialogOwner(payload.envelope.frame_id, close.window_id, close.frame_generation);
        const dialog = self.dialog orelse return Error.ResourceNotLive;
        if (dialog.dialog_id != close.dialog_id or
            dialog.dialog_generation != close.dialog_generation or
            dialog.window_id != close.window_id)
            return Error.InvalidMessage;
        self.dialog = null;
        self.stats.control_messages += 1;
    }

    fn applyFaceDefine(self: *Scene, payload: protocol.Payload) Error!void {
        const face = try protocol.decodeFaceDefine(payload.bytes);
        const old = self.faces.lookup(face.face_id);
        const old_generation: ?u32 = if (old) |resource| resource.generation else null;
        try self.faces.define(&self.resources, face);
        if (old_generation) |generation| self.removeGlyphRunsForFace(face.face_id, generation);
        if (old_generation) |generation| self.removeWindowFacesForFace(face.face_id, generation);
        if (old_generation) |generation| self.removeMouseHighlightsForFace(face.face_id, generation);
        self.stats.control_messages += 1;
    }

    fn applyFaceDelete(self: *Scene, payload: protocol.Payload) Error!void {
        const face = try protocol.decodeFaceDelete(payload.bytes);
        try self.faces.delete(&self.resources, face);
        self.removeGlyphRunsForFace(face.face_id, face.generation);
        self.removeWindowFacesForFace(face.face_id, face.generation);
        self.removeMouseHighlightsForFace(face.face_id, face.generation);
        self.stats.control_messages += 1;
    }

    fn applyFacePatch(self: *Scene, payload: protocol.Payload) Error!void {
        const patch = try protocol.decodeFacePatch(payload.bytes);
        const current = self.faces.lookup(patch.face_id) orelse
            return Error.ResourceNotLive;
        if (current.generation != patch.expected_generation)
            return Error.StaleGeneration;
        if (patch.new_generation <= current.generation)
            return Error.StaleGeneration;

        var patched = current.payload;
        patched.generation = patch.new_generation;
        if (patch.flags & protocol.FacePatchFlags.foreground != 0) {
            patched.presence.foreground = true;
            patched.foreground = patch.foreground;
        }
        if (patch.flags & protocol.FacePatchFlags.background != 0) {
            patched.presence.background = true;
            patched.background = patch.background;
        }
        try protocol.validateFaceDefine(patched);
        try self.faces.define(&self.resources, patched);
        self.removeGlyphRunsForFace(patch.face_id, current.generation);
        self.removeWindowFacesForFace(patch.face_id, current.generation);
        self.removeMouseHighlightsForFace(patch.face_id, current.generation);
        self.stats.control_messages += 1;
    }

    fn applyStringDefine(self: *Scene, payload: protocol.Payload) Error!void {
        const string = try protocol.decodeStringDefine(payload.bytes);
        try self.strings.define(self.allocator, &self.resources, string);
        self.stats.control_messages += 1;
    }

    fn applyStringDelete(self: *Scene, payload: protocol.Payload) Error!void {
        const string = try protocol.decodeStringDelete(payload.bytes);
        try self.strings.delete(self.allocator, &self.resources, string);
        self.stats.control_messages += 1;
    }

    fn applyFontDefine(self: *Scene, payload: protocol.Payload) Error!void {
        const font = try protocol.decodeFontDefine(payload.bytes);
        const current = self.fonts.lookup(font.font_id);
        const old_generation: ?u32 = if (current) |resource| resource.generation else null;
        try self.fonts.define(&self.resources, font);
        if (old_generation != null) self.removeGlyphRunsForFont(font.font_id);
        self.stats.control_messages += 1;
    }

    fn applyFontPatch(self: *Scene, payload: protocol.Payload) Error!void {
        const patch = try protocol.decodeFontPatch(payload.bytes);
        const current = self.fonts.lookup(patch.font_id) orelse return Error.ResourceNotLive;
        if (current.generation != patch.expected_generation) return Error.StaleGeneration;
        var patched = current.payload;
        patched.generation = patch.new_generation;
        patched.weight = patch.weight;
        patched.width_percent = patch.width_percent;
        patched.pixel_size = patch.pixel_size;
        patched.point_size_tenths = patch.point_size_tenths;
        patched.x_dpi = patch.x_dpi;
        patched.y_dpi = patch.y_dpi;
        patched.slant = patch.slant;
        patched.spacing = patch.spacing;
        patched.scalable = patch.scalable;
        patched.fixed_pitch = patch.fixed_pitch;
        try protocol.validateFontDefine(patched);
        try self.fonts.define(&self.resources, patched);
        self.removeGlyphRunsForFont(patch.font_id);
        self.stats.control_messages += 1;
    }

    fn applyFontMetrics(self: *Scene, payload: protocol.Payload) Error!void {
        const patch = try protocol.decodeFontMetricsPatch(payload.bytes);
        const current = self.fonts.lookup(patch.font_id) orelse return Error.ResourceNotLive;
        if (current.generation != patch.expected_generation) return Error.StaleGeneration;
        var patched = current.payload;
        patched.generation = patch.new_generation;
        patched.ascent = patch.ascent;
        patched.descent = patch.descent;
        patched.line_height = patch.line_height;
        patched.average_advance = patch.average_advance;
        patched.max_advance = patch.max_advance;
        try protocol.validateFontDefine(patched);
        try self.fonts.define(&self.resources, patched);
        self.removeGlyphRunsForFont(patch.font_id);
        self.stats.control_messages += 1;
    }

    fn applyFontDelete(self: *Scene, payload: protocol.Payload) Error!void {
        const font = try protocol.decodeFontDelete(payload.bytes);
        try self.fonts.delete(&self.resources, font);
        self.stats.control_messages += 1;
    }

    fn applyFringeBitmapDefine(self: *Scene, payload: protocol.Payload) Error!void {
        const bitmap = try protocol.decodeFringeBitmapDefine(payload.bytes);
        const current = self.fringe_bitmaps.lookup(bitmap.bitmap_id);
        const old_generation: ?u32 = if (current) |resource| resource.generation else null;
        try self.fringe_bitmaps.define(&self.resources, bitmap);
        if (old_generation != null) self.removeFringesForBitmap(bitmap.bitmap_id);
        self.stats.control_messages += 1;
    }

    fn applyFringeBitmapDelete(self: *Scene, payload: protocol.Payload) Error!void {
        const bitmap = try protocol.decodeFringeBitmapDelete(payload.bytes);
        try self.fringe_bitmaps.delete(&self.resources, bitmap);
        self.removeFringesForBitmap(bitmap.bitmap_id);
        self.stats.control_messages += 1;
    }

    fn applyImageDefine(self: *Scene, payload: protocol.Payload) Error!void {
        const image = try protocol.decodeImageDefine(payload.bytes);
        try self.images.define(self.allocator, &self.resources, image);
        self.stats.control_messages += 1;
    }

    fn applyImageData(self: *Scene, payload: protocol.Payload) Error!void {
        const image = try protocol.decodeImageData(payload.bytes);
        try self.images.data(self.allocator, image);
        self.stats.control_messages += 1;
    }

    fn applyImageDelete(self: *Scene, payload: protocol.Payload) Error!void {
        const image = try protocol.decodeImageDelete(payload.bytes);
        try self.images.delete(self.allocator, &self.resources, image);
        self.stats.control_messages += 1;
    }

    fn findImeContext(self: *Scene, context_id: u64) ?*ImeContext {
        for (self.ime_contexts[0..self.ime_context_count]) |*context| {
            if (context.context_id == context_id) return context;
        }
        return null;
    }

    fn applyImeAttach(self: *Scene, payload: protocol.Payload) Error!void {
        const request = try decodeImeAttach(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id) return Error.InvalidMessage;
        _ = findWindow(self.windows.items, request.window_id) orelse
            return Error.InvalidMessage;
        if (self.findImeContext(request.context_id) != null) return Error.DuplicateResource;
        for (self.ime_contexts[0..self.ime_context_count]) |context| {
            if (context.window_id == request.window_id) return Error.InvalidMessage;
        }
        if (self.ime_context_count == max_ime_contexts) return Error.Unsupported;
        self.ime_contexts[self.ime_context_count] = .{
            .context_id = request.context_id,
            .window_id = request.window_id,
            .frame_id = frame.frame_id,
        };
        self.ime_context_count += 1;
        self.stats.control_messages += 1;
    }

    fn applyImeDetach(self: *Scene, payload: protocol.Payload) Error!void {
        const request = try decodeImeDetach(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id) return Error.InvalidMessage;
        for (self.ime_contexts[0..self.ime_context_count], 0..) |context, index| {
            if (context.context_id == request.context_id) {
                if (context.window_id != request.window_id) return Error.InvalidMessage;
                self.ime_contexts[index] = self.ime_contexts[self.ime_context_count - 1];
                self.ime_context_count -= 1;
                self.stats.control_messages += 1;
                return;
            }
        }
        return Error.InvalidMessage;
    }

    fn applyImeFocus(self: *Scene, payload: protocol.Payload) Error!void {
        const request = try decodeImeFocus(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id) return Error.InvalidMessage;
        const context = self.findImeContext(request.context_id) orelse return Error.InvalidMessage;
        if (context.window_id != request.window_id) return Error.InvalidMessage;
        context.focused = request.focused;
        self.stats.control_messages += 1;
    }

    fn applyImeCursorRect(self: *Scene, payload: protocol.Payload) Error!void {
        const rect = try decodeImeCursorRect(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id) return Error.InvalidMessage;
        const context = self.findImeContext(rect.context_id) orelse return Error.InvalidMessage;
        const owner = findWindow(self.windows.items, rect.window_id) orelse return Error.InvalidMessage;
        if (context.window_id != rect.window_id) return Error.InvalidMessage;
        if (!inside(rect.x, rect.width, owner.width) or
            !inside(rect.y, rect.height, owner.height))
            return Error.InvalidMessage;
        context.cursor_x = rect.x;
        context.cursor_y = rect.y;
        context.cursor_width = rect.width;
        context.cursor_height = rect.height;
        self.stats.control_messages += 1;
    }

    fn applyImeAllowedInput(self: *Scene, payload: protocol.Payload) Error!void {
        const request = try decodeImeAllowedInput(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id) return Error.InvalidMessage;
        const context = self.findImeContext(request.context_id) orelse return Error.InvalidMessage;
        if (context.window_id != request.window_id) return Error.InvalidMessage;
        context.allowed_input = request.flags;
        if (request.flags & ImeAllowedInputFlags.surrounding_text == 0)
            context.clearSurrounding();
        self.stats.control_messages += 1;
    }

    fn applyImeSurroundingText(self: *Scene, payload: protocol.Payload) Error!void {
        const request = try decodeImeSurroundingText(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id) return Error.InvalidMessage;
        const context = self.findImeContext(request.context_id) orelse return Error.InvalidMessage;
        if (context.window_id != request.window_id) return Error.InvalidMessage;
        if (context.allowed_input & ImeAllowedInputFlags.surrounding_text == 0)
            return Error.InvalidMessage;
        var storage: [121]u8 = undefined;
        @memcpy(storage[0..request.bytes.len], request.bytes);
        context.surrounding_bytes = storage;
        context.surrounding_len = @intCast(request.bytes.len);
        context.surrounding_cursor_offset = request.cursor_offset;
        context.surrounding_selected_length = request.selected_length;
        context.has_surrounding = true;
        self.stats.control_messages += 1;
    }

    fn applyImeReset(self: *Scene, payload: protocol.Payload) Error!void {
        const request = try decodeImeReset(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id) return Error.InvalidMessage;
        const context = self.findImeContext(request.context_id) orelse return Error.InvalidMessage;
        if (context.window_id != request.window_id) return Error.InvalidMessage;
        context.allowed_input = 0;
        context.clearSurrounding();
        context.focused = false;
        context.cursor_x = 0;
        context.cursor_y = 0;
        context.cursor_width = 0;
        context.cursor_height = 0;
        self.stats.control_messages += 1;
    }

    fn reconcileImeContexts(self: *Scene, windows: []const Window) void {
        var index: usize = 0;
        while (index < self.ime_context_count) {
            const context = &self.ime_contexts[index];
            const owner = findWindow(windows, context.window_id) orelse {
                self.ime_contexts[index] = self.ime_contexts[self.ime_context_count - 1];
                self.ime_context_count -= 1;
                continue;
            };
            if ((context.cursor_width != 0 or context.cursor_height != 0) and
                (!inside(context.cursor_x, context.cursor_width, owner.width) or
                    !inside(context.cursor_y, context.cursor_height, owner.height)))
            {
                context.cursor_x = 0;
                context.cursor_y = 0;
                context.cursor_width = 0;
                context.cursor_height = 0;
            }
            index += 1;
        }
    }

    fn applyFrameCreate(self: *Scene, envelope: protocol.Envelope, bytes: []const u8) Error!void {
        if (bytes.len != 8) return Error.InvalidMessage;
        const frame_id = std.mem.readInt(u32, bytes[0..4], .little);
        const generation = std.mem.readInt(u32, bytes[4..8], .little);
        if (frame_id == 0 or generation == 0 or envelope.frame_id != frame_id) return Error.InvalidMessage;
        if (generation != 1) return Error.InvalidMessage;
        try self.frames.create(frame_id, generation);
        self.frame = .{ .frame_id = frame_id, .generation = generation };
        self.stats.control_messages += 1;
    }

    fn appendSnapshotTombstone(
        resources: *lifecycle.ResourceRegistry,
        entry: protocol.ResourceSnapshotEntry,
    ) Error!void {
        if (resources.len == lifecycle.max_resources) return Error.ResourceTableFull;
        resources.resources[resources.len] = .{
            .kind = entry.kind,
            .id = entry.resource_id,
            .generation = entry.generation,
            .status = .deleted,
        };
        resources.len += 1;
    }

    fn restoreImageEntry(
        images: *ImageResources,
        resources: *lifecycle.ResourceRegistry,
        allocator: std.mem.Allocator,
        entry: protocol.ResourceSnapshotEntry,
    ) Error!void {
        const metadata = try protocol.decodeImageDefine(entry.payload[0..protocol.image_record_size]);
        try images.define(allocator, resources, metadata);
        const fragment_count = (entry.payload.len - protocol.image_record_size +
            protocol.max_image_fragment_bytes - 1) / protocol.max_image_fragment_bytes;
        var offset: usize = protocol.image_record_size;
        var fragment_index: u16 = 0;
        while (offset < entry.payload.len) : (fragment_index += 1) {
            const end = @min(entry.payload.len, offset + protocol.max_image_fragment_bytes);
            try images.data(allocator, .{
                .image_id = metadata.image_id,
                .generation = metadata.generation,
                .fragment_index = fragment_index,
                .fragment_count = @intCast(fragment_count),
                .bytes = entry.payload[offset..end],
            });
            offset = end;
        }
    }

    /// A snapshot is authoritative: validate and build every replacement table
    /// before releasing the old state.  No snapshot error reaches this swap.
    fn applyResourceSnapshot(self: *Scene, payload: protocol.Payload) Error!void {
        var snapshot = try protocol.decodeResourceSnapshot(self.allocator, payload.bytes);
        defer protocol.freeResourceSnapshot(self.allocator, &snapshot);

        var strings = StringResources{};
        var faces = FaceResources{};
        var fonts = FontResources{};
        var images = ImageResources{};
        var fringe_bitmaps = FringeBitmapResources{};
        var resources = lifecycle.ResourceRegistry{};
        errdefer {
            strings.deinit(self.allocator);
            images.clear(self.allocator);
        }

        for (snapshot.entries) |entry| {
            switch (entry.status) {
                .deleted => try appendSnapshotTombstone(&resources, entry),
                .live => switch (entry.kind) {
                    .face => try faces.define(&resources, try protocol.decodeFaceDefine(entry.payload)),
                    .font => try fonts.define(&resources, try protocol.decodeFontDefine(entry.payload)),
                    .string => try strings.define(self.allocator, &resources, .{
                        .resource_id = entry.resource_id,
                        .generation = entry.generation,
                        .bytes = entry.payload,
                    }),
                    .image => try restoreImageEntry(&images, &resources, self.allocator, entry),
                    .fringe_bitmap => try fringe_bitmaps.define(&resources, try protocol.decodeFringeBitmapDefine(entry.payload)),
                    .icon => return Error.Unsupported,
                },
            }
        }

        var old_strings = self.strings;
        var old_images = self.images;
        self.strings = strings;
        self.faces = faces;
        self.fonts = fonts;
        self.images = images;
        self.fringe_bitmaps = fringe_bitmaps;
        self.resources = resources;
        old_strings.deinit(self.allocator);
        old_images.clear(self.allocator);
        self.stats.control_messages += 1;
    }

    fn applyFrameUpdate(self: *Scene, payload: protocol.Payload) Error!void {
        var update = try protocol.decodeFrameUpdate(self.allocator, payload.bytes);
        defer protocol.freeFrameUpdate(self.allocator, &update);
        try protocol.validateFrameEnvelope(update.header, payload.envelope);
        if (self.frame) |frame| {
            if (frame.frame_id != update.header.frame_id or frame.generation != update.header.frame_generation)
                return Error.InvalidMessage;
        } else return Error.InvalidMessage;
        try self.frames.update(update.header.frame_id, update.header.frame_generation);

        var windows: std.ArrayList(Window) = .empty;
        defer windows.deinit(self.allocator);
        var rows: std.ArrayList(Row) = .empty;
        defer rows.deinit(self.allocator);
        var damage: std.ArrayList(Rect) = .empty;
        defer damage.deinit(self.allocator);
        var text: std.ArrayList(TextLine) = .empty;
        defer text.deinit(self.allocator);
        var mode_lines: [max_mode_lines]ModeLine = undefined;
        var mode_line_count: usize = 0;
        var aux_lines: [max_aux_lines]ModeLine = undefined;
        var aux_line_count: usize = 0;
        errdefer for (text.items) |line| self.allocator.free(line.bytes);
        var text_section_seen = false;
        var image_placements: [max_image_placements]ImagePlacement = undefined;
        var image_placement_count: usize = 0;
        var cursors: [max_scene_cursors]Cursor = undefined;
        var cursor_count: usize = 0;
        var present: ?PresentHint = null;
        var viewport: ?Viewport = null;
        var resource_declarations: [max_resources]ResourceDeclaration = undefined;
        var resource_count: usize = 0;

        for (update.sections) |section| {
            switch (section.kind) {
                protocol.SectionKind.windows => {
                    if (section.records.len % window_record_size != 0) return Error.InvalidTable;
                    if (section.records.len / window_record_size > protocol.max_rows) return Error.Unsupported;
                    var offset: usize = 0;
                    while (offset < section.records.len) : (offset += window_record_size) {
                        const wire = try decodeWindow(section.records[offset..][0..window_record_size]);
                        if (wire.frame_id != update.header.frame_id) return Error.InvalidMessage;
                        for (windows.items) |old| {
                            if (old.id == wire.id) return Error.InvalidTable;
                        }
                        try windows.append(self.allocator, wire);
                    }
                    for (windows.items) |window| {
                        if (!inside(window.x, window.width, update.header.logical_width) or
                            !inside(window.y, window.height, update.header.logical_height))
                            return Error.InvalidMessage;
                    }
                },
                protocol.SectionKind.rows => {
                    if (section.records.len % row_record_size != 0) return Error.InvalidTable;
                    if (section.records.len / row_record_size > protocol.max_rows) return Error.Unsupported;
                    var offset: usize = 0;
                    while (offset < section.records.len) : (offset += row_record_size) {
                        const row = try decodeRow(section.records[offset..][0..row_record_size]);
                        if (row.flags != 0) return Error.InvalidMessage;
                        const owner = findWindow(windows.items, row.window_id) orelse return Error.InvalidMessage;
                        for (rows.items) |old| {
                            if (old.window_id == row.window_id and old.index == row.index) return Error.InvalidTable;
                            if (old.window_id == row.window_id and old.index >= row.index) return Error.InvalidTable;
                        }
                        if (!inside(row.x, row.width, owner.width) or
                            !inside(row.y, row.height, owner.height))
                            return Error.InvalidMessage;
                        try rows.append(self.allocator, row);
                    }
                },
                protocol.SectionKind.cursors => {
                    if (section.records.len % cursor_record_size != 0) return Error.InvalidTable;
                    cursor_count = section.records.len / cursor_record_size;
                    if (cursor_count > max_scene_cursors) return Error.Unsupported;
                    var active_count: usize = 0;
                    var cursor_index: usize = 0;
                    var offset: usize = 0;
                    while (offset < section.records.len) : ({
                        offset += cursor_record_size;
                        cursor_index += 1;
                    }) {
                        const wire = try decodeCursor(section.records[offset..][0..cursor_record_size]);
                        for (cursors[0..cursor_index]) |old| {
                            if (old.window_id == wire.window_id) return Error.InvalidTable;
                        }
                        const owner = findWindow(windows.items, wire.window_id) orelse return Error.InvalidMessage;
                        if (!inside(wire.x, wire.width, owner.width) or
                            !inside(wire.y, wire.height, owner.height))
                            return Error.InvalidMessage;
                        if (wire.active) active_count += 1;
                        cursors[cursor_index] = wire;
                    }
                    if (cursor_count != 0 and active_count != 1) return Error.InvalidMessage;
                },
                protocol.SectionKind.damage => {
                    if (section.records.len % damage_record_size != 0) return Error.InvalidTable;
                    if (section.records.len / damage_record_size > protocol.max_damage) return Error.Unsupported;
                    var offset: usize = 0;
                    while (offset < section.records.len) : (offset += damage_record_size) {
                        const rect = try decodeRect(section.records[offset..][0..damage_record_size]);
                        if (!rectInFrame(rect, update.header)) return Error.InvalidMessage;
                        try damage.append(self.allocator, rect);
                    }
                },
                protocol.SectionKind.render_items => {
                    if (section.records.len % image_placement_record_size != 0)
                        return Error.InvalidTable;
                    const count = section.records.len / image_placement_record_size;
                    if (count > max_image_placements) return Error.Unsupported;
                    var offset: usize = 0;
                    while (offset < section.records.len) : (offset += image_placement_record_size) {
                        const placement = try decodeImagePlacement(section.records[offset..][0..image_placement_record_size]);
                        if (placement.width == 0 or placement.height == 0) return Error.InvalidMessage;
                        const owner = findWindow(windows.items, placement.window_id) orelse
                            return Error.InvalidMessage;
                        if (!inside(placement.x, placement.width, owner.width) or
                            !inside(placement.y, placement.height, owner.height))
                            return Error.InvalidMessage;
                        const image = self.images.lookup(placement.image_id) orelse
                            return Error.ResourceNotLive;
                        if (image.generation != placement.image_generation or
                            !image.complete or image.bytes.len != image.metadata.total_byte_count)
                            return Error.ResourceNotLive;
                        for (image_placements[0..image_placement_count]) |old| {
                            if (old.placement_id == placement.placement_id)
                                return Error.InvalidTable;
                        }
                        image_placements[image_placement_count] = placement;
                        image_placement_count += 1;
                    }
                },
                protocol.SectionKind.resources => {
                    if (section.records.len % resource_record_size != 0) return Error.InvalidTable;
                    if (section.records.len / resource_record_size > max_resources) return Error.Unsupported;
                    var offset: usize = 0;
                    while (offset < section.records.len) : (offset += resource_record_size) {
                        const declaration = try decodeResourceDeclaration(section.records[offset..][0..resource_record_size]);
                        for (resource_declarations[0..resource_count]) |old| {
                            if (old.kind == declaration.kind and old.id == declaration.id) return Error.InvalidTable;
                        }
                        if (resource_count == max_resources) return Error.Unsupported;
                        resource_declarations[resource_count] = declaration;
                        resource_count += 1;
                    }
                },
                protocol.SectionKind.present_hint => {
                    if (section.records.len != present_record_size or present != null) return Error.InvalidTable;
                    present = try decodePresentHint(section.records);
                },
                protocol.SectionKind.extension_min + 1 => {
                    if (section.records.len != 8 or viewport != null) return Error.InvalidTable;
                    const wire: Viewport = .{
                        .start_line = std.mem.readInt(i32, section.records[0..4], .little),
                        .line_count = std.mem.readInt(i32, section.records[4..8], .little),
                    };
                    if (!wire.valid()) return Error.InvalidTable;
                    viewport = wire;
                },
                protocol.SectionKind.extension_min => {
                    if (text_section_seen) return Error.InvalidTable;
                    text_section_seen = true;
                    var offset: usize = 0;
                    while (offset < section.records.len) {
                        if (section.records.len - offset < 8) return Error.InvalidTable;
                        const length = std.mem.readInt(u32, section.records[offset + 4 ..][0..4], .little);
                        const record_length = 8 + length;
                        if (record_length > section.records.len - offset) return Error.InvalidTable;
                        const wire = try decodeTextLine(section.records[offset..][0..record_length]);
                        for (text.items) |old| {
                            if (windows.items.len == 1 and old.window_id == windows.items[0].id and
                                old.row_index == wire.row_index) return Error.InvalidTable;
                        }
                        if (windows.items.len != 1 or wire.row_index >= rows.items.len) return Error.InvalidMessage;
                        const owned = try self.allocator.dupeZ(u8, wire.line);
                        errdefer self.allocator.free(owned);
                        try text.append(self.allocator, .{ .window_id = windows.items[0].id, .row_index = wire.row_index, .bytes = owned });
                        offset += record_length;
                    }
                },
                protocol.SectionKind.extension_min + 2 => {
                    if (text_section_seen) return Error.InvalidTable;
                    text_section_seen = true;
                    var offset: usize = 0;
                    while (offset < section.records.len) {
                        if (section.records.len - offset < 16) return Error.InvalidTable;
                        const length = std.mem.readInt(u32, section.records[offset + 12 ..][0..4], .little);
                        const record_length = 16 + length;
                        if (record_length > section.records.len - offset) return Error.InvalidTable;
                        const wire = try decodeTextLineV2(section.records[offset..][0..record_length]);
                        const owner = findWindow(windows.items, wire.window_id) orelse return Error.InvalidMessage;
                        for (text.items) |old| {
                            if (old.window_id == wire.window_id and old.row_index == wire.row_index)
                                return Error.InvalidTable;
                        }
                        var row: ?Row = null;
                        for (rows.items) |candidate| {
                            if (candidate.window_id == wire.window_id and candidate.index == wire.row_index) {
                                row = candidate;
                                break;
                            }
                        }
                        if (row == null) return Error.InvalidMessage;
                        if (row.?.window_id != owner.id) return Error.InvalidMessage;
                        const owned = try self.allocator.dupeZ(u8, wire.line);
                        errdefer self.allocator.free(owned);
                        try text.append(self.allocator, .{ .window_id = wire.window_id, .row_index = wire.row_index, .bytes = owned });
                        offset += record_length;
                    }
                },
                protocol.SectionKind.extension_min + 3 => {
                    if (mode_line_count != 0) return Error.InvalidTable;
                    var active_mode_lines: usize = 0;
                    var offset: usize = 0;
                    while (offset < section.records.len) {
                        if (section.records.len - offset < mode_line_header_size) return Error.InvalidTable;
                        const length = std.mem.readInt(u32, section.records[offset + 26 ..][0..4], .little);
                        const record_length = mode_line_header_size + length;
                        if (record_length > section.records.len - offset) return Error.InvalidTable;
                        const wire = try decodeModeLineV1(section.records[offset..][0..record_length]);
                        const owner = findWindow(windows.items, wire.window_id) orelse return Error.InvalidMessage;
                        for (mode_lines[0..mode_line_count]) |old| {
                            if (old.window_id == wire.window_id) return Error.InvalidTable;
                        }
                        if (wire.x < 0 or wire.y < 0 or wire.width <= 0 or wire.height <= 0 or
                            !inside(wire.x, wire.width, owner.width) or
                            !inside(wire.y, wire.height, owner.height))
                            return Error.InvalidMessage;
                        if (wire.flags & mode_line_active != 0) active_mode_lines += 1;
                        if (mode_line_count == max_mode_lines) return Error.Unsupported;
                        var storage: [121]u8 = undefined;
                        @memcpy(storage[0..wire.line.len], wire.line);
                        mode_lines[mode_line_count] = .{
                            .window_id = wire.window_id,
                            .x = wire.x,
                            .y = wire.y,
                            .width = wire.width,
                            .height = wire.height,
                            .flags = wire.flags,
                            .bytes = storage,
                            .len = @intCast(wire.line.len),
                        };
                        mode_line_count += 1;
                        offset += record_length;
                    }
                    if (mode_line_count != 0 and active_mode_lines != 1) return Error.InvalidMessage;
                },
                protocol.SectionKind.extension_min + 4 => {
                    if (aux_line_count != 0) return Error.InvalidTable;
                    var offset: usize = 0;
                    while (offset < section.records.len) {
                        if (section.records.len - offset < aux_line_header_size) return Error.InvalidTable;
                        const length = std.mem.readInt(u32, section.records[offset + 26 ..][0..4], .little);
                        const record_length = aux_line_header_size + length;
                        if (record_length > section.records.len - offset) return Error.InvalidTable;
                        const wire = try decodeWindowAuxLineV1(section.records[offset..][0..record_length]);
                        const owner = findWindow(windows.items, wire.window_id) orelse return Error.InvalidMessage;
                        for (aux_lines[0..aux_line_count]) |old| {
                            if (old.window_id == wire.window_id and old.flags == wire.flags)
                                return Error.InvalidTable;
                        }
                        if (wire.x < 0 or wire.y < 0 or wire.width <= 0 or wire.height <= 0 or
                            !inside(wire.x, wire.width, owner.width) or
                            !inside(wire.y, wire.height, owner.height))
                            return Error.InvalidMessage;
                        if (aux_line_count == max_aux_lines) return Error.Unsupported;
                        var storage: [121]u8 = undefined;
                        @memcpy(storage[0..wire.line.len], wire.line);
                        aux_lines[aux_line_count] = .{
                            .window_id = wire.window_id,
                            .x = wire.x,
                            .y = wire.y,
                            .width = wire.width,
                            .height = wire.height,
                            .flags = wire.flags,
                            .bytes = storage,
                            .len = @intCast(wire.line.len),
                        };
                        aux_line_count += 1;
                        offset += record_length;
                    }
                },
                else => {},
            }
        }

        if (windows.items.len == 0) return Error.InvalidMessage;
        if (update.header.damage_mode == 1 and damage.items.len == 0) return Error.InvalidMessage;
        if (update.header.damage_mode == 2) {
            if (damage.items.len != 1) return Error.InvalidMessage;
            const full = damage.items[0];
            if (full.x != 0 or full.y != 0 or
                full.width != update.header.logical_width or
                full.height != update.header.logical_height)
                return Error.InvalidMessage;
        }
        if (update.header.damage_mode != 1 and update.header.damage_mode != 2)
            return Error.InvalidMessage;
        // The update is now known to be complete; resource generation is
        // validated and committed atomically with the visual state below.
        try self.resources.declareAll(resource_declarations[0..resource_count]);
        // The update is now known to be complete; commit it atomically.
        const old_windows = self.windows;
        const old_rows = self.rows;
        var old_glyph_runs = self.glyph_runs;
        const old_damage = self.damage;
        for (self.text.items) |line| self.allocator.free(line.bytes);
        self.text.deinit(self.allocator);
        self.windows = windows;
        self.rows = rows;
        self.glyph_runs = .empty;
        self.damage = damage;
        self.text = text;
        self.mode_lines = mode_lines;
        self.mode_line_count = mode_line_count;
        self.aux_lines = aux_lines;
        self.aux_line_count = aux_line_count;
        self.reconcileImeContexts(windows.items);
        self.clear_areas.clearRetainingCapacity();
        self.scroll_runs.clearRetainingCapacity();
        self.dividers.clearRetainingCapacity();
        self.fringes.clearRetainingCapacity();
        self.scroll_states.clearRetainingCapacity();
        self.window_faces.clearRetainingCapacity();
        self.window_geometries.clearRetainingCapacity();
        self.window_zones.clearRetainingCapacity();
        self.window_positions.clearRetainingCapacity();
        self.mouse_highlight_count = 0;
        self.image_placements = image_placements;
        self.image_placement_count = image_placement_count;
        windows = old_windows;
        rows = old_rows;
        // FRAME_UPDATE is authoritative visual state.  Free the old owned
        // glyph storage only after the complete update has validated.
        for (old_glyph_runs.items) |run| self.allocator.free(run.text);
        old_glyph_runs.deinit(self.allocator);
        damage = old_damage;
        text = .empty;
        mode_line_count = 0;
        aux_line_count = 0;
        self.frame_header = update.header;
        self.cursors = cursors;
        self.cursor_count = cursor_count;
        self.cursor = if (cursor_count == 0) null else blk: {
            for (cursors[0..cursor_count]) |wire| {
                if (wire.active) break :blk wire;
            }
            break :blk cursors[0];
        };
        self.present = present;
        self.flush = null;
        self.viewport = viewport;
        self.active_update_id = null;
        self.menu_open = null;
        self.stats.frame_updates += 1;
    }

    fn applyBorderUpdate(self: *Scene, payload: protocol.Payload) Error!void {
        const border = try decodeBorderUpdate(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != border.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation or
            @as(i64, border.thickness) * 2 > @min(header.logical_width, header.logical_height))
            return Error.InvalidMessage;
        self.border = border;
        self.stats.control_messages += 1;
    }
    fn validateRowForOwner(row: Row, owner: Window) Error!void {
        if (row.window_id != owner.id or row.flags != 0 or
            !inside(row.x, row.width, owner.width) or
            !inside(row.y, row.height, owner.height) or
            row.ascent < 0 or row.descent < 0 or
            row.baseline < 0 or row.visible_height < 0)
            return Error.InvalidMessage;
    }

    fn upsertRow(self: *Scene, row: Row, require_existing: bool) Error!void {
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != header.frame_id or header.frame_generation != frame.generation) return Error.InvalidMessage;
        const owner = findWindow(self.windows.items, row.window_id) orelse return Error.InvalidMessage;
        try validateRowForOwner(row, owner);
        var index: ?usize = null;
        for (self.rows.items, 0..) |old, i| {
            if (old.window_id == row.window_id and old.index == row.index) index = i;
        }
        if (require_existing and index == null) return Error.InvalidMessage;
        if (index) |i| self.rows.items[i] = row else try self.rows.append(self.allocator, row);
        self.stats.control_messages += 1;
    }

    fn applyRowSnapshot(self: *Scene, payload: protocol.Payload) Error!void {
        const decoded = try decodeRowSnapshot(payload.bytes);
        try upsertRow(self, decoded.row, false);
    }

    fn applyRowUpdate(self: *Scene, payload: protocol.Payload) Error!void {
        const decoded = try decodeRowSnapshot(payload.bytes);
        try upsertRow(self, decoded.row, true);
    }

    fn applyRowDelete(self: *Scene, payload: protocol.Payload) Error!void {
        const delete = try decodeRowDelete(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or frame.generation != delete.frame_generation)
            return Error.InvalidMessage;
        const owner = findWindow(self.windows.items, delete.window_id) orelse return Error.InvalidMessage;
        var index: ?usize = null;
        for (self.rows.items, 0..) |row, i| {
            if (row.window_id == delete.window_id and row.index == delete.row_index) index = i;
        }
        const row_index = index orelse return Error.InvalidMessage;
        for (self.glyph_runs.items) |run| {
            if (run.window_id == delete.window_id and run.row_index == delete.row_index)
                return Error.ResourceNotLive;
        }
        var text_i: usize = 0;
        while (text_i < self.text.items.len) {
            if (self.text.items[text_i].window_id == delete.window_id and
                self.text.items[text_i].row_index == delete.row_index)
            {
                const owned = self.text.items[text_i].bytes;
                _ = self.text.orderedRemove(text_i);
                self.allocator.free(owned);
            } else text_i += 1;
        }
        _ = owner;
        _ = self.rows.orderedRemove(row_index);
        self.stats.control_messages += 1;
    }

    fn applyBeginUpdate(self: *Scene, payload: protocol.Payload) Error!void {
        const boundary = try decodeUpdateBoundary(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != boundary.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        if (self.active_update_id != null) return Error.InvalidMessage;
        self.active_update_id = boundary.update_id;
        self.stats.control_messages += 1;
    }

    fn applyEndUpdate(self: *Scene, payload: protocol.Payload) Error!void {
        const boundary = try decodeUpdateBoundary(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != boundary.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        const active = self.active_update_id orelse return Error.InvalidMessage;
        if (active != boundary.update_id) return Error.InvalidMessage;
        self.active_update_id = null;
        self.stats.control_messages += 1;
    }

    fn applyClearArea(self: *Scene, payload: protocol.Payload) Error!void {
        const area = try decodeClearArea(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != area.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        const owner = findWindow(self.windows.items, area.window_id) orelse
            return Error.InvalidMessage;
        if (!inside(area.rect.x, area.rect.width, owner.width) or
            !inside(area.rect.y, area.rect.height, owner.height))
            return Error.InvalidMessage;
        const face = self.faces.lookup(area.face_id) orelse
            return Error.ResourceNotLive;
        if (face.generation != area.face_generation or
            !face.payload.presence.background)
            return Error.ResourceNotLive;
        if (self.clear_areas.items.len == max_clear_areas)
            return Error.Unsupported;
        try self.clear_areas.append(self.allocator, area);
        self.stats.control_messages += 1;
    }

    fn applyScrollRun(self: *Scene, payload: protocol.Payload) Error!void {
        const run = try decodeScrollRun(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != run.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        const owner = findWindow(self.windows.items, run.window_id) orelse
            return Error.InvalidMessage;
        if (run.width != owner.width or
            !inside(0, run.height, owner.height) or
            @as(i64, run.source_y) + run.height > owner.height or
            @as(i64, run.destination_y) + run.height > owner.height)
            return Error.InvalidMessage;
        if (self.scroll_runs.items.len == max_scroll_runs)
            return Error.Unsupported;
        try self.scroll_runs.append(self.allocator, run);
        self.stats.control_messages += 1;
    }

    fn applyWindowFace(self: *Scene, payload: protocol.Payload) Error!void {
        const state = try decodeWindowFaceState(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != state.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        _ = findWindow(self.windows.items, state.window_id) orelse
            return Error.InvalidMessage;
        const face = self.faces.lookup(state.face_id) orelse
            return Error.ResourceNotLive;
        if (face.generation != state.face_generation)
            return Error.StaleGeneration;
        for (self.window_faces.items, 0..) |*old, index| {
            if (old.window_id == state.window_id) {
                self.window_faces.items[index] = state;
                self.stats.control_messages += 1;
                return;
            }
        }
        if (self.window_faces.items.len == max_window_faces) return Error.Unsupported;
        try self.window_faces.append(self.allocator, state);
        self.stats.control_messages += 1;
    }

    fn applyWindowGeometry(self: *Scene, payload: protocol.Payload) Error!void {
        const state = try decodeWindowGeometryState(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != state.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        const owner = findWindow(self.windows.items, state.window_id) orelse
            return Error.InvalidMessage;
        if (!windowGeometryFits(owner, state)) return Error.InvalidMessage;
        for (self.window_zones.items) |zones| {
            if (zones.window_id != owner.id) continue;
            var index: usize = 0;
            while (index < window_zone_count) : (index += 1) {
                const bit = @as(u32, 1) << @intCast(index);
                if (zoneRect(zones, bit)) |rect| {
                    if (geometryRectsOverlap(state.body, rect)) return Error.InvalidMessage;
                }
            }
        }
        for (self.window_geometries.items, 0..) |*old, index| {
            if (old.window_id == state.window_id) {
                self.window_geometries.items[index] = state;
                self.stats.control_messages += 1;
                return;
            }
        }
        if (self.window_geometries.items.len == max_window_geometries) return Error.Unsupported;
        try self.window_geometries.append(self.allocator, state);
        self.stats.control_messages += 1;
    }

    fn applyWindowZones(self: *Scene, payload: protocol.Payload) Error!void {
        const state = try decodeWindowZonesState(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != state.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        const owner = findWindow(self.windows.items, state.window_id) orelse
            return Error.InvalidMessage;
        if (!windowZonesFit(owner, state)) return Error.InvalidMessage;
        for (self.window_geometries.items) |geometry| {
            if (geometry.window_id != owner.id) continue;
            var index: usize = 0;
            while (index < window_zone_count) : (index += 1) {
                const bit = @as(u32, 1) << @intCast(index);
                if (zoneRect(state, bit)) |rect| {
                    if (geometryRectsOverlap(geometry.body, rect)) return Error.InvalidMessage;
                }
            }
        }
        for (self.window_zones.items, 0..) |*old, index| {
            if (old.window_id == state.window_id) {
                self.window_zones.items[index] = state;
                self.stats.control_messages += 1;
                return;
            }
        }
        if (self.window_zones.items.len == max_window_zones) return Error.Unsupported;
        try self.window_zones.append(self.allocator, state);
        self.stats.control_messages += 1;
    }

    fn applyWindowPosition(self: *Scene, payload: protocol.Payload) Error!void {
        const state = try decodeWindowPositionState(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != state.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        _ = findWindow(self.windows.items, state.window_id) orelse
            return Error.InvalidMessage;
        for (self.window_positions.items, 0..) |*old, index| {
            if (old.window_id == state.window_id) {
                self.window_positions.items[index] = state;
                self.stats.control_messages += 1;
                return;
            }
        }
        if (self.window_positions.items.len == max_window_positions) return Error.Unsupported;
        try self.window_positions.append(self.allocator, state);
        self.stats.control_messages += 1;
    }

    fn validateActiveTooltipOwner(self: *Scene, envelope_frame_id: u32, window_id: u64, frame_generation: u32) Error!Window {
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != envelope_frame_id or
            frame.generation != frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        return findWindow(self.windows.items, window_id) orelse Error.InvalidMessage;
    }

    fn applyTooltipShow(self: *Scene, payload: protocol.Payload) Error!void {
        const tip = try decodeTooltipShow(payload.bytes);
        const owner = try self.validateActiveTooltipOwner(payload.envelope.frame_id, tip.window_id, tip.frame_generation);
        if (tip.x < 0 or tip.y < 0 or
            @as(i64, tip.x) + tip.max_width > owner.width or
            @as(i64, tip.y) + tip.max_height > owner.height)
            return Error.InvalidMessage;
        if (self.tooltip) |old| {
            if (old.tooltip_id == tip.tooltip_id and tip.generation <= old.generation)
                return Error.StaleGeneration;
        }
        self.tooltip = tip;
        self.stats.control_messages += 1;
    }

    fn applyTooltipMove(self: *Scene, payload: protocol.Payload) Error!void {
        const move = try decodeTooltipMove(payload.bytes);
        const owner = try self.validateActiveTooltipOwner(payload.envelope.frame_id, move.window_id, move.frame_generation);
        const tip = self.tooltip orelse return Error.ResourceNotLive;
        if (tip.tooltip_id != move.tooltip_id or tip.generation != move.generation or
            tip.window_id != move.window_id)
            return Error.InvalidMessage;
        if (move.x < 0 or move.y < 0 or
            @as(i64, move.x) + tip.max_width > owner.width or
            @as(i64, move.y) + tip.max_height > owner.height)
            return Error.InvalidMessage;
        self.tooltip.?.x = move.x;
        self.tooltip.?.y = move.y;
        self.stats.control_messages += 1;
    }

    fn applyTooltipHide(self: *Scene, payload: protocol.Payload) Error!void {
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        const hide = try decodeTooltipHide(payload.bytes);
        const tip = self.tooltip orelse return Error.ResourceNotLive;
        if (tip.tooltip_id != hide.tooltip_id or tip.generation != hide.generation)
            return Error.StaleGeneration;
        self.tooltip = null;
        self.stats.control_messages += 1;
    }

    fn applyMouseHighlight(self: *Scene, payload: protocol.Payload) Error!void {
        const state = try decodeMouseHighlightState(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != state.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        const owner = findWindow(self.windows.items, state.window_id) orelse
            return Error.InvalidMessage;
        if (!inside(state.rect.x, state.rect.width, owner.width) or
            !inside(state.rect.y, state.rect.height, owner.height))
            return Error.InvalidMessage;
        const face = self.faces.lookup(state.face_id) orelse return Error.ResourceNotLive;
        if (face.generation != state.face_generation) return Error.StaleGeneration;
        for (self.mouse_highlights[0..self.mouse_highlight_count], 0..) |*old, index| {
            if (old.window_id == state.window_id) {
                self.mouse_highlights[index] = state;
                self.stats.control_messages += 1;
                return;
            }
        }
        if (self.mouse_highlight_count == max_mouse_highlights) return Error.Unsupported;
        self.mouse_highlights[self.mouse_highlight_count] = state;
        self.mouse_highlight_count += 1;
        self.stats.control_messages += 1;
    }

    fn applyWindowScrollState(self: *Scene, payload: protocol.Payload) Error!void {
        const state = try decodeWindowScrollState(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != state.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        _ = findWindow(self.windows.items, state.window_id) orelse
            return Error.InvalidMessage;
        for (self.scroll_states.items, 0..) |*old, index| {
            if (old.window_id == state.window_id) {
                self.scroll_states.items[index] = state;
                self.stats.control_messages += 1;
                return;
            }
        }
        if (self.scroll_states.items.len == max_scrollbar_states) return Error.Unsupported;
        try self.scroll_states.append(self.allocator, state);
        self.stats.control_messages += 1;
    }

    fn applyFringeUpdate(self: *Scene, payload: protocol.Payload) Error!void {
        const fringe = try decodeFringeUpdate(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != fringe.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        const owner = findWindow(self.windows.items, fringe.window_id) orelse
            return Error.InvalidMessage;
        if (fringe.width > owner.width or
            !inside(0, fringe.height, owner.height) or
            @as(i64, fringe.y) + fringe.height > owner.height)
            return Error.InvalidMessage;
        for (self.fringes.items) |*old| {
            if (old.fringe_id == fringe.fringe_id) {
                if (fringe.fringe_generation <= old.fringe_generation)
                    return Error.StaleGeneration;
                old.* = fringe;
                self.stats.control_messages += 1;
                return;
            }
        }
        if (self.fringes.items.len == max_fringes) return Error.Unsupported;
        try self.fringes.append(self.allocator, fringe);
        self.stats.control_messages += 1;
    }

    fn applyDividerUpdate(self: *Scene, payload: protocol.Payload) Error!void {
        const divider = try decodeDividerUpdate(payload.bytes);
        const frame = self.frame orelse return Error.FrameNotActive;
        const header = self.frame_header orelse return Error.FrameNotActive;
        if (frame.frame_id != payload.envelope.frame_id or
            frame.generation != divider.frame_generation or
            header.frame_id != frame.frame_id or
            header.frame_generation != frame.generation)
            return Error.InvalidMessage;
        const owner = findWindow(self.windows.items, divider.window_id) orelse
            return Error.InvalidMessage;
        const rect = dividerRect(divider);
        if (!inside(rect.x, rect.width, owner.width) or
            !inside(rect.y, rect.height, owner.height))
            return Error.InvalidMessage;
        for (self.dividers.items) |*old| {
            if (old.divider_id == divider.divider_id) {
                if (divider.divider_generation <= old.divider_generation)
                    return Error.StaleGeneration;
                old.* = divider;
                self.stats.control_messages += 1;
                return;
            }
        }
        if (self.dividers.items.len == max_dividers) return Error.Unsupported;
        try self.dividers.append(self.allocator, divider);
        self.stats.control_messages += 1;
    }
};

fn inside(offset: i32, extent: i32, limit: i32) bool {
    return offset >= 0 and extent >= 0 and offset <= limit and extent <= limit - offset;
}

fn windowGeometryFits(owner: Window, state: WindowGeometryState) bool {
    return inside(@intCast(state.content.x), @intCast(state.content.width), owner.width) and
        inside(@intCast(state.content.y), @intCast(state.content.height), owner.height) and
        inside(@intCast(state.body.x), @intCast(state.body.width), @intCast(state.content.width)) and
        inside(@intCast(state.body.y), @intCast(state.body.height), @intCast(state.content.height));
}

fn windowZonesFit(owner: Window, state: WindowZonesState) bool {
    var index: usize = 0;
    while (index < window_zone_count) : (index += 1) {
        const bit = @as(u32, 1) << @intCast(index);
        const rect = zoneRect(state, bit) orelse continue;
        if (!inside(rect.x, rect.width, owner.width) or
            !inside(rect.y, rect.height, owner.height)) return false;
    }
    return true;
}

fn findWindow(windows: []const Window, id: u64) ?Window {
    for (windows) |window| {
        if (window.id == id) return window;
    }
    return null;
}

fn rectInFrame(rect: Rect, header: protocol.FrameUpdateHeader) bool {
    return inside(rect.x, rect.width, header.logical_width) and
        inside(rect.y, rect.height, header.logical_height);
}

test "window row cursor and damage records round trip" {
    const a = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);

    try encodeWindow(a, .{ .id = 1, .frame_id = 7, .x = 1, .y = 2, .width = 30, .height = 20 }, &out);
    const window = try decodeWindow(out.items);
    try std.testing.expectEqual(@as(u64, 1), window.id);
    out.clearRetainingCapacity();

    try encodeRow(a, .{ .window_id = 1, .index = 2, .flags = 0, .x = 0, .y = 4, .width = 30, .height = 8, .ascent = 6, .descent = 2, .baseline = 6, .visible_height = 8 }, &out);
    const row = try decodeRow(out.items);
    try std.testing.expectEqual(@as(u32, 2), row.index);
    out.clearRetainingCapacity();

    try encodeCursor(a, .{ .window_id = 1, .x = 3, .y = 4, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true }, &out);
    const cursor = try decodeCursor(out.items);
    try std.testing.expect(cursor.visible);
    out.clearRetainingCapacity();

    try encodeRect(a, .{ .x = 0, .y = 0, .width = 30, .height = 20 }, &out);
    const rect = try decodeRect(out.items);
    try std.testing.expectEqual(@as(i32, 30), rect.width);
}

test "cursor update has exact little-endian wire layout" {
    const a = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);
    const cursor: Cursor = .{ .window_id = 100, .x = 3, .y = 4, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true };
    try encodeCursorUpdate(a, 7, cursor, &out);
    try std.testing.expectEqual(cursor_update_size, out.items.len);
    try std.testing.expectEqualSlices(u8, &.{ 1, 0 }, out.items[0..2]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0 }, out.items[2..4]);
    try std.testing.expectEqual(@as(u32, 7), std.mem.readInt(u32, out.items[4..8], .little));
    var expected_record: [cursor_record_size]u8 = @splat(0xaa);
    {
        var record: std.ArrayList(u8) = .empty;
        defer record.deinit(a);
        try encodeCursor(a, cursor, &record);
        @memcpy(&expected_record, record.items);
    }
    try std.testing.expectEqualSlices(u8, out.items[8..], &expected_record);
    const decoded = try decodeCursorUpdate(out.items);
    try std.testing.expectEqual(@as(u32, 7), decoded.frame_generation);
    try std.testing.expectEqual(cursor, decoded.cursor);

    for (out.items[0..4]) |*byte| {
        const original = byte.*;
        byte.* = 0xff;
        try std.testing.expectError(Error.InvalidTable, decodeCursorUpdate(out.items));
        byte.* = original;
    }
    out.items[4] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeCursorUpdate(out.items));
    out.items[4] = 7;
    try std.testing.expectError(Error.InvalidTable, decodeCursorUpdate(out.items[0 .. out.items.len - 1]));
}

test "scene validates cursor update against active frame and owner" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const valid: Cursor = .{ .window_id = 100, .x = 76, .y = 52, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeCursorUpdate(a, 1, valid, &payload);
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(a);
    try protocol.encodeEnvelope(a, .{ .flags = 0, .message_type = protocol.Message.cursor_update, .sequence = 3, .ack_sequence = 0, .session_id = 9, .frame_id = 7, .timestamp_ns = 3 }, payload.items, &message);
    try scene.apply(message.items);
    try std.testing.expectEqual(valid, scene.cursor.?);

    payload.clearRetainingCapacity();
    try encodeCursorUpdate(a, 2, valid, &payload);
    const stale = try windowLifecycleMessage(a, protocol.Message.cursor_update, 4, 7, payload.items);
    defer a.free(stale);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(stale));
    try std.testing.expectEqual(valid, scene.cursor.?);

    const missing: Cursor = .{ .window_id = 999, .x = 0, .y = 0, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true };
    payload.clearRetainingCapacity();
    try encodeCursorUpdate(a, 1, missing, &payload);
    const missing_owner = try windowLifecycleMessage(a, protocol.Message.cursor_update, 4, 7, payload.items);
    defer a.free(missing_owner);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(missing_owner));

    const outside: Cursor = .{ .window_id = 100, .x = 80, .y = 0, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true };
    payload.clearRetainingCapacity();
    try encodeCursorUpdate(a, 1, outside, &payload);
    const outside_owner = try windowLifecycleMessage(a, protocol.Message.cursor_update, 4, 7, payload.items);
    defer a.free(outside_owner);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(outside_owner));
    try std.testing.expectEqual(valid, scene.cursor.?);

    var wrong_envelope: std.ArrayList(u8) = .empty;
    defer wrong_envelope.deinit(a);
    try protocol.encodeEnvelope(a, .{ .flags = 0, .message_type = protocol.Message.cursor_update, .sequence = 4, .ack_sequence = 0, .session_id = 9, .frame_id = 8, .timestamp_ns = 4 }, payload.items, &wrong_envelope);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_envelope.items));
    try std.testing.expectEqual(valid, scene.cursor.?);
}

fn cursorFrameUpdateMessage(
    a: std.mem.Allocator,
    sequence: u64,
    cursor_count: usize,
    active_count: usize,
) ![]u8 {
    std.debug.assert(cursor_count != 0);
    const header: protocol.FrameUpdateHeader = .{
        .frame_id = 7,
        .frame_generation = 1,
        .sequence = sequence,
        .redisplay_generation = 1,
        .logical_x = 0,
        .logical_y = 0,
        .logical_width = 80,
        .logical_height = 60,
        .physical_x = 0,
        .physical_y = 0,
        .physical_width = 80,
        .physical_height = 60,
        .scale = 1,
        .dpi_x = 96,
        .dpi_y = 96,
        .damage_mode = 2,
        .update_cause = 1,
        .coalesced_count = 0,
        .timestamp_ns = 2,
    };
    var windows: std.ArrayList(u8) = .empty;
    defer windows.deinit(a);
    var rows: std.ArrayList(u8) = .empty;
    defer rows.deinit(a);
    var cursors: std.ArrayList(u8) = .empty;
    defer cursors.deinit(a);
    var damage: std.ArrayList(u8) = .empty;
    defer damage.deinit(a);
    for (0..cursor_count) |index| {
        const id: u64 = 100 + index;
        try encodeWindow(a, .{
            .id = id,
            .frame_id = 7,
            .x = @intCast(index * 2),
            .y = 0,
            .width = 2,
            .height = 60,
        }, &windows);
        try encodeRow(a, .{
            .window_id = id,
            .index = 0,
            .flags = 0,
            .x = 0,
            .y = 0,
            .width = 2,
            .height = 10,
            .ascent = 7,
            .descent = 3,
            .baseline = 7,
            .visible_height = 10,
        }, &rows);
        try encodeCursor(a, .{
            .window_id = id,
            .x = 0,
            .y = 0,
            .width = 2,
            .height = 10,
            .kind = 1,
            .visible = true,
            .active = index < active_count,
        }, &cursors);
    }
    try encodeRect(a, .{ .x = 0, .y = 0, .width = 80, .height = 60 }, &damage);
    var sections: std.ArrayList(protocol.Section) = .empty;
    defer sections.deinit(a);
    try sections.append(a, .{ .kind = protocol.SectionKind.windows, .records = windows.items });
    try sections.append(a, .{ .kind = protocol.SectionKind.rows, .records = rows.items });
    try sections.append(a, .{ .kind = protocol.SectionKind.cursors, .records = cursors.items });
    try sections.append(a, .{ .kind = protocol.SectionKind.damage, .records = damage.items });
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeFrameUpdate(a, .{ .header = header, .sections = sections.items }, &payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = protocol.Flags.delta,
        .message_type = protocol.Message.frame_update,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = 2,
    }, payload.items, &message);
    return message.toOwnedSlice(a);
}

fn modeLineFrameUpdateMessage(
    a: std.mem.Allocator,
    sequence: u64,
    owner_count: usize,
    wires: []const ModeLineWire,
) ![]u8 {
    std.debug.assert(owner_count != 0);
    const header: protocol.FrameUpdateHeader = .{
        .frame_id = 7,
        .frame_generation = 1,
        .sequence = sequence,
        .redisplay_generation = 1,
        .logical_x = 0,
        .logical_y = 0,
        .logical_width = 80,
        .logical_height = 60,
        .physical_x = 0,
        .physical_y = 0,
        .physical_width = 80,
        .physical_height = 60,
        .scale = 1,
        .dpi_x = 96,
        .dpi_y = 96,
        .damage_mode = 2,
        .update_cause = 1,
        .coalesced_count = 0,
        .timestamp_ns = 2,
    };
    var windows: std.ArrayList(u8) = .empty;
    defer windows.deinit(a);
    var rows: std.ArrayList(u8) = .empty;
    defer rows.deinit(a);
    var mode_lines: std.ArrayList(u8) = .empty;
    defer mode_lines.deinit(a);
    var damage: std.ArrayList(u8) = .empty;
    defer damage.deinit(a);
    for (0..owner_count) |index| {
        const id: u64 = 100 + index;
        try encodeWindow(a, .{ .id = id, .frame_id = 7, .x = 0, .y = 0, .width = 80, .height = 60 }, &windows);
        try encodeRow(a, .{ .window_id = id, .index = 0, .flags = 0, .x = 0, .y = 0, .width = 80, .height = 10, .ascent = 7, .descent = 3, .baseline = 7, .visible_height = 10 }, &rows);
    }
    for (wires) |wire| try encodeModeLineV1(a, wire, &mode_lines);
    try encodeRect(a, .{ .x = 0, .y = 0, .width = 80, .height = 60 }, &damage);
    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = windows.items },
        .{ .kind = protocol.SectionKind.rows, .records = rows.items },
        .{ .kind = protocol.SectionKind.extension_min + 3, .records = mode_lines.items },
        .{ .kind = protocol.SectionKind.damage, .records = damage.items },
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeFrameUpdate(a, .{ .header = header, .sections = &sections }, &payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{ .flags = protocol.Flags.delta, .message_type = protocol.Message.frame_update, .sequence = sequence, .ack_sequence = 0, .session_id = 9, .frame_id = 7, .timestamp_ns = 2 }, payload.items, &message);
    return message.toOwnedSlice(a);
}

test "frame update accepts exactly one active per-window cursor" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);
    const update = try cursorFrameUpdateMessage(a, 2, 2, 1);
    defer a.free(update);
    try scene.apply(update);
    try std.testing.expectEqual(@as(usize, 2), scene.cursor_count);
    try std.testing.expect(scene.cursors[0].active);
    try std.testing.expect(!scene.cursors[1].active);
    try std.testing.expectEqual(scene.cursors[0], scene.cursor.?);
}

test "frame update rejects invalid cursor cardinalities" {
    const a = std.testing.allocator;
    inline for (.{ 0, 2 }) |active_count| {
        var scene = Scene.init(a);
        defer scene.deinit();
        const create = try createMessage(a, 1, 7, 7);
        defer a.free(create);
        try scene.apply(create);
        const update = try cursorFrameUpdateMessage(a, 2, 2, active_count);
        defer a.free(update);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(update));
    }

    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);
    const oversized = try cursorFrameUpdateMessage(a, 2, max_scene_cursors + 1, 1);
    defer a.free(oversized);
    try std.testing.expectError(Error.Unsupported, scene.apply(oversized));
}

fn auxLineFrameUpdateMessage(
    a: std.mem.Allocator,
    sequence: u64,
    owner_count: usize,
    wires: []const ModeLineWire,
) ![]u8 {
    std.debug.assert(owner_count != 0);
    const header: protocol.FrameUpdateHeader = .{
        .frame_id = 7,
        .frame_generation = 1,
        .sequence = sequence,
        .redisplay_generation = 1,
        .logical_x = 0,
        .logical_y = 0,
        .logical_width = 80,
        .logical_height = 60,
        .physical_x = 0,
        .physical_y = 0,
        .physical_width = 80,
        .physical_height = 60,
        .scale = 1,
        .dpi_x = 96,
        .dpi_y = 96,
        .damage_mode = 2,
        .update_cause = 1,
        .coalesced_count = 0,
        .timestamp_ns = 2,
    };
    var windows: std.ArrayList(u8) = .empty;
    defer windows.deinit(a);
    var rows: std.ArrayList(u8) = .empty;
    defer rows.deinit(a);
    var aux: std.ArrayList(u8) = .empty;
    defer aux.deinit(a);
    var damage: std.ArrayList(u8) = .empty;
    defer damage.deinit(a);
    for (0..owner_count) |index| {
        const id: u64 = 100 + index;
        try encodeWindow(a, .{ .id = id, .frame_id = 7, .x = 0, .y = 0, .width = 80, .height = 60 }, &windows);
        try encodeRow(a, .{ .window_id = id, .index = 0, .flags = 0, .x = 0, .y = 0, .width = 80, .height = 10, .ascent = 7, .descent = 3, .baseline = 7, .visible_height = 10 }, &rows);
    }
    for (wires) |wire| try encodeWindowAuxLineV1(a, wire, &aux);
    try encodeRect(a, .{ .x = 0, .y = 0, .width = 80, .height = 60 }, &damage);
    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = windows.items },
        .{ .kind = protocol.SectionKind.rows, .records = rows.items },
        .{ .kind = protocol.SectionKind.extension_min + 4, .records = aux.items },
        .{ .kind = protocol.SectionKind.damage, .records = damage.items },
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeFrameUpdate(a, .{ .header = header, .sections = &sections }, &payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{ .flags = protocol.Flags.delta, .message_type = protocol.Message.frame_update, .sequence = sequence, .ack_sequence = 0, .session_id = 9, .frame_id = 7, .timestamp_ns = 2 }, payload.items, &message);
    return message.toOwnedSlice(a);
}

test "mode line frame updates validate bounds, cardinality, and replacement" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const baseline = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(baseline);
    try scene.apply(create);
    try scene.apply(baseline);

    const valid = [_]ModeLineWire{.{ .window_id = 100, .x = 0, .y = 52, .width = 80, .height = 8, .flags = mode_line_active, .line = "Mode" }};
    const with_mode = try modeLineFrameUpdateMessage(a, 3, 1, &valid);
    defer a.free(with_mode);
    try scene.apply(with_mode);
    try std.testing.expectEqual(@as(usize, 1), scene.mode_line_count);
    try std.testing.expectEqualStrings("Mode", scene.mode_lines[0].bytes[0..scene.mode_lines[0].len]);

    const without_mode = try updateMessage(a, 4, 7, 7, 80, 0);
    defer a.free(without_mode);
    try scene.apply(without_mode);
    try std.testing.expectEqual(@as(usize, 0), scene.mode_line_count);

    const invalid_sets = [_][]const ModeLineWire{
        &.{.{ .window_id = 100, .x = 0, .y = 52, .width = 80, .height = 8, .line = "inactive" }},
        &.{
            .{ .window_id = 100, .x = 0, .y = 52, .width = 40, .height = 8, .flags = mode_line_active, .line = "one" },
            .{ .window_id = 101, .x = 0, .y = 52, .width = 40, .height = 8, .flags = mode_line_active, .line = "two" },
        },
        &.{.{ .window_id = 100, .x = 78, .y = 52, .width = 10, .height = 8, .flags = mode_line_active, .line = "wide" }},
    };
    for (invalid_sets) |wires| {
        var bad = Scene.init(a);
        defer bad.deinit();
        try bad.apply(create);
        try bad.apply(baseline);
        const message = try modeLineFrameUpdateMessage(a, 3, @max(1, wires.len), wires);
        defer a.free(message);
        try std.testing.expectError(Error.InvalidMessage, bad.apply(message));
    }

    const duplicate = [_]ModeLineWire{
        .{ .window_id = 100, .x = 0, .y = 52, .width = 40, .height = 8, .flags = mode_line_active, .line = "one" },
        .{ .window_id = 100, .x = 40, .y = 52, .width = 40, .height = 8, .line = "duplicate" },
    };
    var duplicated = Scene.init(a);
    defer duplicated.deinit();
    try duplicated.apply(create);
    try duplicated.apply(baseline);
    const duplicate_update = try modeLineFrameUpdateMessage(a, 3, 2, &duplicate);
    defer a.free(duplicate_update);
    try std.testing.expectError(Error.InvalidTable, duplicated.apply(duplicate_update));

    var many: [max_mode_lines + 1]ModeLineWire = undefined;
    for (&many, 0..) |*wire, index| {
        wire.* = .{ .window_id = 100 + index, .x = 0, .y = 52, .width = 80, .height = 8, .flags = if (index == 0) mode_line_active else 0, .line = "mode" };
    }
    var oversized = Scene.init(a);
    defer oversized.deinit();
    try oversized.apply(create);
    try oversized.apply(baseline);
    const many_update = try modeLineFrameUpdateMessage(a, 3, many.len, &many);
    defer a.free(many_update);
    try std.testing.expectError(Error.Unsupported, oversized.apply(many_update));
}

test "window aux lines validate kinds, owners, and authoritative replacement" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const baseline = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(baseline);
    try scene.apply(create);
    try scene.apply(baseline);

    const valid = [_]ModeLineWire{
        .{ .window_id = 100, .x = 0, .y = 0, .width = 80, .height = 4, .flags = aux_line_header, .line = "Header" },
        .{ .window_id = 100, .x = 0, .y = 4, .width = 80, .height = 4, .flags = aux_line_tab, .line = "Tab" },
        .{ .window_id = 101, .x = 0, .y = 0, .width = 80, .height = 4, .flags = aux_line_header, .line = "Other" },
    };
    const update = try auxLineFrameUpdateMessage(a, 3, 2, &valid);
    defer a.free(update);
    try scene.apply(update);
    try std.testing.expectEqual(@as(usize, 3), scene.aux_line_count);
    try std.testing.expectEqualStrings("Header", scene.aux_lines[0].bytes[0..scene.aux_lines[0].len]);

    const omitted = try updateMessage(a, 4, 7, 7, 80, 0);
    defer a.free(omitted);
    try scene.apply(omitted);
    try std.testing.expectEqual(@as(usize, 0), scene.aux_line_count);

    const invalid_sets = [_][]const ModeLineWire{
        &.{.{ .window_id = 100, .x = 78, .y = 0, .width = 10, .height = 4, .flags = aux_line_header, .line = "wide" }},
    };
    for (invalid_sets) |wires| {
        var bad = Scene.init(a);
        defer bad.deinit();
        try bad.apply(create);
        try bad.apply(baseline);
        const message = try auxLineFrameUpdateMessage(a, 3, @max(1, wires.len), wires);
        defer a.free(message);
        try std.testing.expectError(Error.InvalidMessage, bad.apply(message));
    }

    const duplicate = [_]ModeLineWire{
        .{ .window_id = 100, .x = 0, .y = 0, .width = 80, .height = 4, .flags = aux_line_header, .line = "one" },
        .{ .window_id = 100, .x = 0, .y = 4, .width = 80, .height = 4, .flags = aux_line_header, .line = "duplicate" },
    };
    var duplicated = Scene.init(a);
    defer duplicated.deinit();
    try duplicated.apply(create);
    try duplicated.apply(baseline);
    const duplicate_update = try auxLineFrameUpdateMessage(a, 3, 1, &duplicate);
    defer a.free(duplicate_update);
    try std.testing.expectError(Error.InvalidTable, duplicated.apply(duplicate_update));

    var many: [max_aux_lines + 1]ModeLineWire = undefined;
    for (&many, 0..) |*wire, index| {
        wire.* = .{ .window_id = 100 + @as(u64, @intCast(index)), .x = 0, .y = 0, .width = 80, .height = 4, .flags = aux_line_header, .line = "line" };
    }
    var oversized = Scene.init(a);
    defer oversized.deinit();
    try oversized.apply(create);
    try oversized.apply(baseline);
    const many_update = try auxLineFrameUpdateMessage(a, 3, max_aux_lines + 1, &many);
    defer a.free(many_update);
    try std.testing.expectError(Error.Unsupported, oversized.apply(many_update));
}

test "mode line payload accepts 120 bytes and rejects 121" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    var line: [120]u8 = @splat('a');
    const valid: ModeLineWire = .{ .window_id = 100, .x = 0, .y = 0, .width = 80, .height = 2, .line = &line };
    try encodeModeLineV1(a, valid, &bytes);
    const decoded = try decodeModeLineV1(bytes.items);
    try std.testing.expectEqual(@as(usize, 120), decoded.line.len);
    bytes.clearRetainingCapacity();
    var long: [121]u8 = @splat('b');
    const invalid: ModeLineWire = .{ .window_id = 100, .x = 0, .y = 0, .width = 80, .height = 2, .line = &long };
    try std.testing.expectError(Error.InvalidTable, encodeModeLineV1(a, invalid, &bytes));
}

test "aux line codec validates kind bits and bounds" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    const valid: ModeLineWire = .{ .window_id = 101, .x = 0, .y = 0, .width = 80, .height = 4, .flags = aux_line_tab, .line = "Tab" };
    try encodeWindowAuxLineV1(a, valid, &bytes);
    const decoded = try decodeWindowAuxLineV1(bytes.items);
    try std.testing.expectEqual(valid.window_id, decoded.window_id);
    try std.testing.expectEqual(valid.flags, decoded.flags);
    try std.testing.expectEqualStrings(valid.line, decoded.line);
    try std.testing.expectError(Error.InvalidTable, decodeWindowAuxLineV1(bytes.items[0 .. bytes.items.len - 1]));
    bytes.items[25] ^= @as(u8, 1);
    try std.testing.expectError(Error.InvalidTable, decodeWindowAuxLineV1(bytes.items));
    bytes.clearRetainingCapacity();
    const invalid_flags: ModeLineWire = .{ .window_id = 101, .x = 0, .y = 0, .width = 80, .height = 4, .flags = mode_line_active | aux_line_header, .line = "bad" };
    try std.testing.expectError(Error.InvalidTable, encodeWindowAuxLineV1(a, invalid_flags, &bytes));
}

test "window aux line codec rejects malformed and unsafe payloads" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    const valid: ModeLineWire = .{ .window_id = 100, .x = 0, .y = 0, .width = 80, .height = 4, .flags = aux_line_header, .line = "A" };
    try encodeWindowAuxLineV1(a, valid, &bytes);
    try std.testing.expectEqualStrings("A", (try decodeWindowAuxLineV1(bytes.items)).line);
    bytes.items[24] = 0;
    try std.testing.expectError(Error.InvalidTable, decodeWindowAuxLineV1(bytes.items));
    bytes.items[24] = 4;
    try std.testing.expectEqual(aux_line_tab, (try decodeWindowAuxLineV1(bytes.items)).flags);
    bytes.items[24] = 3;
    try std.testing.expectError(Error.InvalidTable, decodeWindowAuxLineV1(bytes.items));
    bytes.items[24] = 2;

    const empty: ModeLineWire = .{ .window_id = 100, .x = 0, .y = 0, .width = 80, .height = 4, .flags = aux_line_header, .line = "" };
    try std.testing.expectError(Error.InvalidTable, encodeWindowAuxLineV1(a, empty, &bytes));
    var long: [121]u8 = @splat('x');
    const oversized: ModeLineWire = .{ .window_id = 100, .x = 0, .y = 0, .width = 80, .height = 4, .flags = aux_line_header, .line = &long };
    try std.testing.expectError(Error.InvalidTable, encodeWindowAuxLineV1(a, oversized, &bytes));
    const malformed_utf8: ModeLineWire = .{ .window_id = 100, .x = 0, .y = 0, .width = 80, .height = 4, .flags = aux_line_header, .line = &.{0xff} };
    try std.testing.expectError(Error.InvalidTable, encodeWindowAuxLineV1(a, malformed_utf8, &bytes));
    const del: ModeLineWire = .{ .window_id = 100, .x = 0, .y = 0, .width = 80, .height = 4, .flags = aux_line_header, .line = "A\u{7f}" };
    try std.testing.expectError(Error.InvalidTable, encodeWindowAuxLineV1(a, del, &bytes));
    const c1_start: ModeLineWire = .{ .window_id = 100, .x = 0, .y = 0, .width = 80, .height = 4, .flags = aux_line_header, .line = "A\u{80}" };
    try std.testing.expectError(Error.InvalidTable, encodeWindowAuxLineV1(a, c1_start, &bytes));
    const c1_end: ModeLineWire = .{ .window_id = 100, .x = 0, .y = 0, .width = 80, .height = 4, .flags = aux_line_header, .line = "A\u{9f}" };
    try std.testing.expectError(Error.InvalidTable, encodeWindowAuxLineV1(a, c1_end, &bytes));
}

test "ime context lifecycle validates owner and exact state" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);
    try std.testing.expectEqual(@as(usize, 0), scene.ime_context_count);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeImeAttach(a, .{ .context_id = 11, .window_id = 100 }, &payload);
    const attach = try windowLifecycleMessage(a, protocol.Message.ime_attach, 3, 7, payload.items);
    defer a.free(attach);
    try scene.apply(attach);
    try std.testing.expectEqual(@as(usize, 1), scene.ime_context_count);
    try std.testing.expectEqual(@as(u64, 11), scene.ime_contexts[0].context_id);

    payload.clearRetainingCapacity();
    try encodeImeFocus(a, .{ .context_id = 11, .window_id = 100, .focused = true }, &payload);
    const focus = try windowLifecycleMessage(a, protocol.Message.ime_focus, 4, 7, payload.items);
    defer a.free(focus);
    try scene.apply(focus);
    try std.testing.expect(scene.ime_contexts[0].focused);

    payload.clearRetainingCapacity();
    try encodeImeCursorRect(a, .{ .context_id = 11, .window_id = 100, .x = 8, .y = 8, .width = 4, .height = 8 }, &payload);
    const cursor = try windowLifecycleMessage(a, protocol.Message.ime_cursor_rect, 5, 7, payload.items);
    defer a.free(cursor);
    try scene.apply(cursor);
    try std.testing.expectEqual(@as(i32, 8), scene.ime_contexts[0].cursor_x);

    payload.clearRetainingCapacity();
    try encodeImeReset(a, .{ .context_id = 11, .window_id = 100 }, &payload);
    const reset = try windowLifecycleMessage(a, protocol.Message.ime_reset, 6, 7, payload.items);
    defer a.free(reset);
    try scene.apply(reset);

    payload.clearRetainingCapacity();
    try encodeImeDetach(a, .{ .context_id = 11, .window_id = 100 }, &payload);
    const detach = try windowLifecycleMessage(a, protocol.Message.ime_detach, 7, 7, payload.items);
    defer a.free(detach);
    try scene.apply(detach);
    try std.testing.expectEqual(@as(usize, 0), scene.ime_context_count);
}

test "ime context codecs reject malformed values" {
    const a = std.testing.allocator;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);

    try std.testing.expectError(Error.InvalidTable, encodeImeAttach(a, .{ .context_id = 0, .window_id = 100 }, &payload));
    payload.clearRetainingCapacity();
    try std.testing.expectError(Error.InvalidTable, encodeImeAttach(a, .{ .context_id = 11, .window_id = 100, .flags = 1 }, &payload));
    try std.testing.expectError(Error.InvalidTable, decodeImeAttach(payload.items));

    payload.clearRetainingCapacity();
    try encodeImeFocus(a, .{ .context_id = 11, .window_id = 100, .focused = true }, &payload);
    payload.items[16] = 2;
    try std.testing.expectError(Error.InvalidTable, decodeImeFocus(payload.items));

    payload.clearRetainingCapacity();
    try std.testing.expectError(Error.InvalidTable, encodeImeCursorRect(a, .{ .context_id = 11, .window_id = 100, .x = 0, .y = 0, .width = 0, .height = 8 }, &payload));

    payload.clearRetainingCapacity();
    try std.testing.expectError(Error.InvalidTable, encodeImeReset(a, .{ .context_id = 11, .window_id = 100, .reason = 1 }, &payload));
}

test "ime reset clears state and deleted window removes context" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);
    const second = try windowCreateMessage(a, 3, 7, .{ .window_id = 101, .parent_window_id = 0, .x = 0, .y = 0, .width = 40, .height = 40, .flags = 2, .default_face_id = 0, .depth = 0 });
    defer a.free(second);
    try scene.apply(second);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeImeAttach(a, .{ .context_id = 11, .window_id = 100 }, &payload);
    const attach = try windowLifecycleMessage(a, protocol.Message.ime_attach, 4, 7, payload.items);
    defer a.free(attach);
    try scene.apply(attach);

    payload.clearRetainingCapacity();
    try encodeImeAttach(a, .{ .context_id = 12, .window_id = 101 }, &payload);
    const attach_second = try windowLifecycleMessage(a, protocol.Message.ime_attach, 5, 7, payload.items);
    defer a.free(attach_second);
    try scene.apply(attach_second);

    payload.clearRetainingCapacity();
    try encodeImeFocus(a, .{ .context_id = 11, .window_id = 100, .focused = true }, &payload);
    const focus = try windowLifecycleMessage(a, protocol.Message.ime_focus, 6, 7, payload.items);
    defer a.free(focus);
    try scene.apply(focus);
    payload.clearRetainingCapacity();
    try encodeImeCursorRect(a, .{ .context_id = 11, .window_id = 100, .x = 2, .y = 2, .width = 4, .height = 8 }, &payload);
    const cursor = try windowLifecycleMessage(a, protocol.Message.ime_cursor_rect, 7, 7, payload.items);
    defer a.free(cursor);
    try scene.apply(cursor);

    payload.clearRetainingCapacity();
    try encodeImeReset(a, .{ .context_id = 11, .window_id = 100 }, &payload);
    const reset = try windowLifecycleMessage(a, protocol.Message.ime_reset, 8, 7, payload.items);
    defer a.free(reset);
    try scene.apply(reset);
    try std.testing.expect(!scene.ime_contexts[0].focused);
    try std.testing.expectEqual(@as(i32, 0), scene.ime_contexts[0].cursor_width);

    const delete = try windowDeleteMessage(a, 9, 7, 101);
    defer a.free(delete);
    try scene.apply(delete);
    try std.testing.expectEqual(@as(usize, 1), scene.ime_context_count);
    try std.testing.expectEqual(@as(u64, 11), scene.ime_contexts[0].context_id);
    payload.clearRetainingCapacity();
    try encodeImeFocus(a, .{ .context_id = 12, .window_id = 101, .focused = true }, &payload);
    const stale_focus = try windowLifecycleMessage(a, protocol.Message.ime_focus, 10, 7, payload.items);
    defer a.free(stale_focus);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(stale_focus));
}

test "ime wire payloads have exact layouts and bounded lifecycle" {
    const a = std.testing.allocator;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);

    try encodeImeAttach(a, .{ .context_id = 11, .window_id = 100 }, &payload);
    try std.testing.expectEqual(@as(usize, 20), payload.items.len);
    try std.testing.expectEqual(@as(u64, 11), std.mem.readInt(u64, payload.items[0..8], .little));
    try std.testing.expectEqual(@as(u64, 100), std.mem.readInt(u64, payload.items[8..16], .little));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, payload.items[16..20], .little));

    payload.clearRetainingCapacity();
    try encodeImeDetach(a, .{ .context_id = 11, .window_id = 100 }, &payload);
    try std.testing.expectEqual(@as(usize, 16), payload.items.len);

    payload.clearRetainingCapacity();
    try encodeImeFocus(a, .{ .context_id = 11, .window_id = 100, .focused = true }, &payload);
    try std.testing.expectEqual(@as(usize, 20), payload.items.len);
    try std.testing.expectEqual(@as(u8, 1), payload.items[16]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0 }, payload.items[17..20]);

    payload.clearRetainingCapacity();
    try encodeImeCursorRect(a, .{ .context_id = 11, .window_id = 100, .x = 2, .y = 3, .width = 4, .height = 5 }, &payload);
    try std.testing.expectEqual(@as(usize, 32), payload.items.len);
    try std.testing.expectEqual(@as(i32, 2), @as(i32, @bitCast(std.mem.readInt(u32, payload.items[16..20], .little))));
    try std.testing.expectEqual(@as(i32, 3), @as(i32, @bitCast(std.mem.readInt(u32, payload.items[20..24], .little))));
    try std.testing.expectEqual(@as(i32, 4), @as(i32, @bitCast(std.mem.readInt(u32, payload.items[24..28], .little))));
    try std.testing.expectEqual(@as(i32, 5), @as(i32, @bitCast(std.mem.readInt(u32, payload.items[28..32], .little))));

    payload.clearRetainingCapacity();
    try encodeImeReset(a, .{ .context_id = 11, .window_id = 100 }, &payload);
    try std.testing.expectEqual(@as(usize, 20), payload.items.len);
    try std.testing.expectEqual(@as(u8, 0), payload.items[16]);

    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var context_payload: std.ArrayList(u8) = .empty;
    defer context_payload.deinit(a);
    try encodeImeAttach(a, .{ .context_id = 11, .window_id = 100 }, &context_payload);
    const attach = try windowLifecycleMessage(a, protocol.Message.ime_attach, 3, 7, context_payload.items);
    defer a.free(attach);
    try scene.apply(attach);
    const duplicate_attach = try windowLifecycleMessage(a, protocol.Message.ime_attach, 4, 7, payload.items);
    defer a.free(duplicate_attach);
    try std.testing.expectError(Error.DuplicateResource, scene.apply(duplicate_attach));

    payload.clearRetainingCapacity();
    try encodeImeAttach(a, .{ .context_id = 12, .window_id = 100 }, &payload);
    const same_window = try windowLifecycleMessage(a, protocol.Message.ime_attach, 4, 7, payload.items);
    defer a.free(same_window);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(same_window));

    payload.clearRetainingCapacity();
    try encodeImeFocus(a, .{ .context_id = 11, .window_id = 101, .focused = true }, &payload);
    const wrong_owner = try windowLifecycleMessage(a, protocol.Message.ime_focus, 4, 7, payload.items);
    defer a.free(wrong_owner);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_owner));

    // Four contexts are accepted; a fifth context/window is rejected.
    var extra_payload: std.ArrayList(u8) = .empty;
    defer extra_payload.deinit(a);
    const created_windows = [_]u64{ 101, 102, 103, 104 };
    for (created_windows, 0..) |window_id, index| {
        const create_sequence = scene.next_sequence.?;
        const create_window = try windowCreateMessage(a, create_sequence, 7, .{
            .window_id = window_id,
            .parent_window_id = 0,
            .x = 0,
            .y = 0,
            .width = 40,
            .height = 40,
            .flags = 2,
            .default_face_id = 0,
            .depth = 0,
        });
        defer a.free(create_window);
        try scene.apply(create_window);
        extra_payload.clearRetainingCapacity();
        try encodeImeAttach(a, .{ .context_id = 20 + @as(u64, @intCast(index)), .window_id = window_id }, &extra_payload);
        const attach_sequence = scene.next_sequence.?;
        const attach_extra = try windowLifecycleMessage(a, protocol.Message.ime_attach, attach_sequence, 7, extra_payload.items);
        defer a.free(attach_extra);
        if (index < 3) {
            try scene.apply(attach_extra);
        } else {
            try std.testing.expectEqual(@as(usize, 4), scene.ime_context_count);
            try std.testing.expectError(Error.Unsupported, scene.apply(attach_extra));
        }
    }
    scene.resetForResync();
    try std.testing.expectEqual(@as(usize, 0), scene.ime_context_count);
}

test "ime contexts reconcile authoritative window replacement" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);
    const second = try windowCreateMessage(a, 3, 7, .{ .window_id = 101, .parent_window_id = 0, .x = 0, .y = 0, .width = 40, .height = 40, .flags = 2, .default_face_id = 0, .depth = 0 });
    defer a.free(second);
    try scene.apply(second);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeImeAttach(a, .{ .context_id = 11, .window_id = 100 }, &payload);
    const attach = try windowLifecycleMessage(a, protocol.Message.ime_attach, 4, 7, payload.items);
    defer a.free(attach);
    try scene.apply(attach);
    payload.clearRetainingCapacity();
    try encodeImeAttach(a, .{ .context_id = 12, .window_id = 101 }, &payload);
    const attach_second = try windowLifecycleMessage(a, protocol.Message.ime_attach, 5, 7, payload.items);
    defer a.free(attach_second);
    try scene.apply(attach_second);
    payload.clearRetainingCapacity();
    try encodeImeCursorRect(a, .{ .context_id = 11, .window_id = 100, .x = 70, .y = 2, .width = 4, .height = 8 }, &payload);
    const cursor = try windowLifecycleMessage(a, protocol.Message.ime_cursor_rect, 6, 7, payload.items);
    defer a.free(cursor);
    try scene.apply(cursor);
    try std.testing.expectEqual(@as(i32, 4), scene.ime_contexts[0].cursor_width);

    const narrow_header: protocol.FrameUpdateHeader = .{
        .frame_id = 7,
        .frame_generation = 1,
        .sequence = 7,
        .redisplay_generation = 2,
        .logical_x = 0,
        .logical_y = 0,
        .logical_width = 20,
        .logical_height = 60,
        .physical_x = 0,
        .physical_y = 0,
        .physical_width = 20,
        .physical_height = 60,
        .scale = 1,
        .dpi_x = 96,
        .dpi_y = 96,
        .damage_mode = 2,
        .update_cause = 1,
        .coalesced_count = 0,
        .timestamp_ns = 7,
    };
    var narrow_windows: std.ArrayList(u8) = .empty;
    defer narrow_windows.deinit(a);
    var narrow_rows: std.ArrayList(u8) = .empty;
    defer narrow_rows.deinit(a);
    var narrow_damage: std.ArrayList(u8) = .empty;
    defer narrow_damage.deinit(a);
    try encodeWindow(a, .{ .id = 100, .frame_id = 7, .x = 0, .y = 0, .width = 20, .height = 60 }, &narrow_windows);
    try encodeRow(a, .{ .window_id = 100, .index = 0, .flags = 0, .x = 0, .y = 0, .width = 20, .height = 10, .ascent = 7, .descent = 3, .baseline = 7, .visible_height = 10 }, &narrow_rows);
    try encodeRect(a, .{ .x = 0, .y = 0, .width = 20, .height = 60 }, &narrow_damage);
    const narrow_sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = narrow_windows.items },
        .{ .kind = protocol.SectionKind.rows, .records = narrow_rows.items },
        .{ .kind = protocol.SectionKind.damage, .records = narrow_damage.items },
    };
    var narrow_payload: std.ArrayList(u8) = .empty;
    defer narrow_payload.deinit(a);
    try protocol.encodeFrameUpdate(a, .{ .header = narrow_header, .sections = &narrow_sections }, &narrow_payload);
    const replacement = try windowLifecycleMessage(a, protocol.Message.frame_update, 7, 7, narrow_payload.items);
    defer a.free(replacement);
    try scene.apply(replacement);
    try std.testing.expectEqual(@as(usize, 1), scene.ime_context_count);
    try std.testing.expectEqual(@as(u64, 11), scene.ime_contexts[0].context_id);
    try std.testing.expectEqual(@as(i32, 0), scene.ime_contexts[0].cursor_width);
}

test "ime cursor clears when a window patch makes it stale" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeImeAttach(a, .{ .context_id = 11, .window_id = 100 }, &payload);
    const attach = try windowLifecycleMessage(a, protocol.Message.ime_attach, 3, 7, payload.items);
    defer a.free(attach);
    try scene.apply(attach);
    payload.clearRetainingCapacity();
    try encodeImeCursorRect(a, .{ .context_id = 11, .window_id = 100, .x = 74, .y = 2, .width = 4, .height = 8 }, &payload);
    const cursor = try windowLifecycleMessage(a, protocol.Message.ime_cursor_rect, 4, 7, payload.items);
    defer a.free(cursor);
    try scene.apply(cursor);

    var patch_payload: std.ArrayList(u8) = .empty;
    defer patch_payload.deinit(a);
    try protocol.encodeWindowPatch(a, .{ .flags = protocol.WindowPatchFlags.width, .frame_id = 7, .frame_generation = 1, .window_id = 100, .width = 40 }, &patch_payload);
    const patch = try windowLifecycleMessage(a, protocol.Message.window_patch, 5, 7, patch_payload.items);
    defer a.free(patch);
    try scene.apply(patch);
    try std.testing.expectEqual(@as(i32, 0), scene.ime_contexts[0].cursor_width);
}

test "ime allowed input and surrounding text validate wire and state" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeImeAttach(a, .{ .context_id = 11, .window_id = 100 }, &payload);
    const attach = try windowLifecycleMessage(a, protocol.Message.ime_attach, 3, 7, payload.items);
    defer a.free(attach);
    try scene.apply(attach);

    const flags = ImeAllowedInputFlags.text | ImeAllowedInputFlags.surrounding_text | ImeAllowedInputFlags.delete_surrounding;
    payload.clearRetainingCapacity();
    try encodeImeAllowedInput(a, .{ .context_id = 11, .window_id = 100, .flags = flags }, &payload);
    try std.testing.expectEqual(@as(usize, 20), payload.items.len);
    const allowed = try windowLifecycleMessage(a, protocol.Message.ime_allowed_input, 4, 7, payload.items);
    defer a.free(allowed);
    try scene.apply(allowed);
    try std.testing.expectEqual(flags, scene.ime_contexts[0].allowed_input);

    payload.clearRetainingCapacity();
    try encodeImeSurroundingText(a, .{ .context_id = 11, .window_id = 100, .cursor_offset = 6, .selected_length = 4, .bytes = "abroad" }, &payload);
    try std.testing.expectEqual(@as(usize, 34), payload.items.len);
    const decoded = try decodeImeSurroundingText(payload.items);
    try std.testing.expectEqual(@as(u32, 6), decoded.cursor_offset);
    try std.testing.expectEqual(@as(u32, 4), decoded.selected_length);
    try std.testing.expectEqualStrings("abroad", decoded.bytes);
    const surrounding = try windowLifecycleMessage(a, protocol.Message.ime_surrounding_text, 5, 7, payload.items);
    defer a.free(surrounding);
    try scene.apply(surrounding);
    try std.testing.expect(scene.ime_contexts[0].has_surrounding);
    try std.testing.expectEqualStrings("abroad", scene.ime_contexts[0].surrounding_bytes[0..scene.ime_contexts[0].surrounding_len]);

    // Empty surrounding text is valid; it clears the selected range.
    payload.clearRetainingCapacity();
    try encodeImeSurroundingText(a, .{ .context_id = 11, .window_id = 100, .cursor_offset = 0, .selected_length = 0, .bytes = "" }, &payload);
    const empty_surrounding = try windowLifecycleMessage(a, protocol.Message.ime_surrounding_text, 6, 7, payload.items);
    defer a.free(empty_surrounding);
    try scene.apply(empty_surrounding);
    try std.testing.expect(scene.ime_contexts[0].has_surrounding);
    try std.testing.expectEqual(@as(u32, 0), scene.ime_contexts[0].surrounding_selected_length);

    // Disabling surrounding support invalidates retained surrounding state.
    payload.clearRetainingCapacity();
    try encodeImeAllowedInput(a, .{ .context_id = 11, .window_id = 100, .flags = ImeAllowedInputFlags.text }, &payload);
    const disable_surrounding = try windowLifecycleMessage(a, protocol.Message.ime_allowed_input, 7, 7, payload.items);
    defer a.free(disable_surrounding);
    try scene.apply(disable_surrounding);
    try std.testing.expect(!scene.ime_contexts[0].has_surrounding);
    payload.clearRetainingCapacity();
    try encodeImeSurroundingText(a, .{ .context_id = 11, .window_id = 100, .cursor_offset = 1, .selected_length = 0, .bytes = "A" }, &payload);
    const rejected_surrounding = try windowLifecycleMessage(a, protocol.Message.ime_surrounding_text, 8, 7, payload.items);
    defer a.free(rejected_surrounding);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(rejected_surrounding));
    try std.testing.expect(!scene.ime_contexts[0].has_surrounding);

    // Bad selection bounds and unsupported policy bits are rejected.
    payload.clearRetainingCapacity();
    try std.testing.expectError(Error.InvalidTable, encodeImeSurroundingText(a, .{ .context_id = 11, .window_id = 100, .cursor_offset = 1, .selected_length = 2, .bytes = "A" }, &payload));
    payload.clearRetainingCapacity();
    try std.testing.expectError(Error.InvalidTable, encodeImeAllowedInput(a, .{ .context_id = 11, .window_id = 100, .flags = 0x8000 }, &payload));

    // ALLOWED_INPUT decodes only exact 20-byte payloads.
    payload.clearRetainingCapacity();
    try encodeImeAllowedInput(a, .{ .context_id = 11, .window_id = 100, .flags = flags }, &payload);
    try std.testing.expectError(Error.InvalidTable, decodeImeAllowedInput(payload.items[0..18]));
    var allowed_trailing: [21]u8 = undefined;
    @memcpy(allowed_trailing[0..payload.items.len], payload.items);
    allowed_trailing[20] = 0;
    try std.testing.expectError(Error.InvalidTable, decodeImeAllowedInput(allowed_trailing[0..]));

    payload.items[16..20].* = @bitCast(@as(u32, 0x8000));
    try std.testing.expectError(Error.InvalidTable, decodeImeAllowedInput(payload.items));
    payload.items[16..20].* = @bitCast(@as(u32, flags));

    // SURROUNDING_TEXT accepts the 120-byte maximum, then rejects 121 bytes.
    payload.clearRetainingCapacity();
    var max_text: [120]u8 = @splat('a');
    try encodeImeSurroundingText(a, .{ .context_id = 11, .window_id = 100, .cursor_offset = 120, .selected_length = 0, .bytes = max_text[0..] }, &payload);
    try std.testing.expectEqual(@as(u32, 120), (try decodeImeSurroundingText(payload.items)).cursor_offset);
    payload.clearRetainingCapacity();
    var long_text: [121]u8 = @splat('a');
    try std.testing.expectError(Error.InvalidTable, encodeImeSurroundingText(a, .{ .context_id = 11, .window_id = 100, .cursor_offset = 121, .selected_length = 0, .bytes = long_text[0..] }, &payload));

    // Decode rejects short/trailing variable forms and unsafe/malformed bytes.
    payload.clearRetainingCapacity();
    try encodeImeSurroundingText(a, .{ .context_id = 11, .window_id = 100, .cursor_offset = 1, .selected_length = 0, .bytes = "A" }, &payload);
    try std.testing.expectError(Error.InvalidTable, decodeImeSurroundingText(payload.items[0..26]));
    var surrounding_trailing: [29]u8 = undefined;
    @memcpy(surrounding_trailing[0..payload.items.len], payload.items);
    surrounding_trailing[28] = 0;
    try std.testing.expectError(Error.InvalidTable, decodeImeSurroundingText(surrounding_trailing[0..]));

    payload.items[28] = 0x7f;
    try std.testing.expectError(Error.InvalidTable, decodeImeSurroundingText(payload.items));
    payload.items[28] = 0xff;
    try std.testing.expectError(Error.InvalidTable, decodeImeSurroundingText(payload.items));
    payload.items[28] = 0xc2;
    payload.append(a, 0x81) catch unreachable;
    std.mem.writeInt(u32, payload.items[24..28], 2, .little);
    try std.testing.expectError(Error.InvalidTable, decodeImeSurroundingText(payload.items));

    // Decode validates cursor/selection as end-biased bounds.
    payload.clearRetainingCapacity();
    try encodeImeSurroundingText(a, .{ .context_id = 11, .window_id = 100, .cursor_offset = 1, .selected_length = 0, .bytes = "A" }, &payload);
    std.mem.writeInt(u32, payload.items[20..24], 2, .little);
    try std.testing.expectError(Error.InvalidTable, decodeImeSurroundingText(payload.items));
    std.mem.writeInt(u32, payload.items[20..24], 0, .little);
    std.mem.writeInt(u32, payload.items[16..20], 2, .little);
    try std.testing.expectError(Error.InvalidTable, decodeImeSurroundingText(payload.items));

    // RESET clears policy and all retained surrounding fields.
    payload.clearRetainingCapacity();
    try encodeImeAllowedInput(a, .{ .context_id = 11, .window_id = 100, .flags = flags }, &payload);
    const reenable = try windowLifecycleMessage(a, protocol.Message.ime_allowed_input, 8, 7, payload.items);
    defer a.free(reenable);
    try scene.apply(reenable);
    payload.clearRetainingCapacity();
    try encodeImeSurroundingText(a, .{ .context_id = 11, .window_id = 100, .cursor_offset = 1, .selected_length = 0, .bytes = "A" }, &payload);
    const repopulate = try windowLifecycleMessage(a, protocol.Message.ime_surrounding_text, 9, 7, payload.items);
    defer a.free(repopulate);
    try scene.apply(repopulate);
    payload.clearRetainingCapacity();
    try encodeImeReset(a, .{ .context_id = 11, .window_id = 100 }, &payload);
    const reset = try windowLifecycleMessage(a, protocol.Message.ime_reset, 10, 7, payload.items);
    defer a.free(reset);
    try scene.apply(reset);
    try std.testing.expectEqual(@as(u32, 0), scene.ime_contexts[0].allowed_input);
    try std.testing.expect(!scene.ime_contexts[0].has_surrounding);
    try std.testing.expectEqual(@as(u16, 0), scene.ime_contexts[0].surrounding_len);
    try std.testing.expectEqual(@as(u32, 0), scene.ime_contexts[0].surrounding_cursor_offset);
    try std.testing.expectEqual(@as(u32, 0), scene.ime_contexts[0].surrounding_selected_length);
    try std.testing.expectEqual(@as(usize, 1), scene.ime_context_count);
}

test "ime reverse codecs round trip and reject invalid bounded state" {
    const a = std.testing.allocator;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);

    try encodeImeAttached(a, .{ .context_id = 11, .platform = .basic }, &payload);
    try std.testing.expectEqual(@as(usize, 16), payload.items.len);
    const attached = try decodeImeAttached(payload.items);
    try std.testing.expectEqual(ImePlatform.basic, attached.platform);
    for (9..12) |offset| {
        payload.items[offset] = 1;
        try std.testing.expectError(Error.InvalidTable, decodeImeAttached(payload.items));
        payload.items[offset] = 0;
    }
    payload.items[8] = 0;
    try std.testing.expectError(Error.InvalidTable, decodeImeAttached(payload.items));

    payload.clearRetainingCapacity();
    try encodeImeDetached(a, .{ .context_id = 11 }, &payload);
    try std.testing.expectEqual(@as(usize, 12), payload.items.len);
    payload.items[8] = 1;
    try std.testing.expectError(Error.InvalidTable, decodeImeDetached(payload.items));

    payload.clearRetainingCapacity();
    try encodeImePreeditUpdate(a, .{ .context_id = 11, .cursor_offset = 3, .selected_length = 1, .bytes = "abcd" }, &payload);
    try std.testing.expectEqual(@as(usize, 24), payload.items.len);
    const preedit = try decodeImePreeditUpdate(payload.items);
    try std.testing.expectEqual(@as(u32, 1), preedit.selected_length);
    try std.testing.expectEqualStrings("abcd", preedit.bytes);
    payload.items[19] = 0xff;
    try std.testing.expectError(Error.InvalidTable, decodeImePreeditUpdate(payload.items));

    payload.clearRetainingCapacity();
    try encodeImeCommit(a, .{ .context_id = 11, .bytes = "汉" }, &payload);
    try std.testing.expectEqual(@as(usize, 15), payload.items.len);
    const commit = try decodeImeCommit(payload.items);
    try std.testing.expectEqualStrings("汉", commit.bytes);
    payload.items[12] = 0;
    try std.testing.expectError(Error.InvalidTable, decodeImeCommit(payload.items));

    payload.clearRetainingCapacity();
    try encodeImeRequestSurrounding(a, .{ .context_id = 11, .request_id = 77 }, &payload);
    try std.testing.expectEqual(@as(usize, 16), payload.items.len);
    try std.testing.expectEqual(@as(u64, 77), (try decodeImeRequestSurrounding(payload.items)).request_id);
    payload.items[8] = 0;
    try std.testing.expectError(Error.InvalidTable, decodeImeRequestSurrounding(payload.items));

    payload.clearRetainingCapacity();
    try encodeImeDeleteSurrounding(a, .{ .context_id = 11, .offset = -2, .length = 2 }, &payload);
    try std.testing.expectEqual(@as(usize, 16), payload.items.len);
    try std.testing.expectEqual(@as(i32, -2), (try decodeImeDeleteSurrounding(payload.items)).offset);
    payload.items[12] = 3;
    try std.testing.expectError(Error.InvalidTable, decodeImeDeleteSurrounding(payload.items));

    payload.clearRetainingCapacity();
    try encodeImeCandidateUpdate(a, .{ .context_id = 11, .selected_index = 1, .candidate_count = 3, .page_index = 0, .page_count = 2, .cursor_x = 8, .cursor_y = 8, .cursor_width = 40, .cursor_height = 16, .selected_label = "乙" }, &payload);
    var candidate = try decodeImeCandidateUpdate(payload.items);
    try std.testing.expectEqual(@as(u32, 1), candidate.selected_index);
    try std.testing.expectEqualStrings("乙", candidate.selected_label);
    candidate.candidate_count = 0;
    try std.testing.expectError(Error.InvalidTable, encodeImeCandidateUpdate(a, candidate, &payload));

    payload.clearRetainingCapacity();
    try encodeImeCancel(a, 11, &payload);
    try std.testing.expectEqual(@as(u64, 11), try decodeImeCancel(payload.items));
    payload.items[0] = 0;
    try std.testing.expectError(Error.InvalidTable, decodeImeCancel(payload.items));

    payload.clearRetainingCapacity();
    try encodeImePreeditStart(a, 11, &payload);
    try std.testing.expectEqual(@as(u64, 11), try decodeImePreeditStart(payload.items));
    payload.clearRetainingCapacity();
    try encodeImePreeditEnd(a, 11, &payload);
    try std.testing.expectEqual(@as(u64, 11), try decodeImePreeditEnd(payload.items));
    payload.append(a, 0) catch unreachable;
    try std.testing.expectError(Error.InvalidTable, decodeImePreeditEnd(payload.items));
    payload.clearRetainingCapacity();
    try encodeImeCancel(a, 11, &payload);
    payload.append(a, 0) catch unreachable;
    try std.testing.expectError(Error.InvalidTable, decodeImeCancel(payload.items));
    payload.clearRetainingCapacity();
    try encodeImePreeditStart(a, 11, &payload);
    payload.append(a, 0) catch unreachable;
    try std.testing.expectError(Error.InvalidTable, decodeImePreeditStart(payload.items));
}

test "damage rects have a bounded variable wire form" {
    const a = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);
    const rects = [_]Rect{
        .{ .x = 2, .y = 3, .width = 20, .height = 10 },
        .{ .x = 30, .y = 8, .width = 12, .height = 4 },
    };
    try encodeDamageRects(a, 7, &rects, &out);
    try std.testing.expectEqual(damage_rects_header_size + 2 * damage_record_size, out.items.len);
    try std.testing.expectEqual(damage_rects_schema, std.mem.readInt(u16, out.items[0..2], .little));
    try std.testing.expectEqual(@as(u32, 7), std.mem.readInt(u32, out.items[4..8], .little));
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, out.items[8..12], .little));

    const decoded = try decodeDamageRects(a, out.items);
    defer freeDamageRects(a, decoded);
    try std.testing.expectEqual(@as(u32, 7), decoded.frame_generation);
    try std.testing.expectEqualSlices(Rect, &rects, decoded.rects);

    out.items[2] = 1;
    try std.testing.expectError(Error.InvalidTable, decodeDamageRects(a, out.items));
    out.items[2] = 0;
    out.items[3] = 1;
    try std.testing.expectError(Error.InvalidTable, decodeDamageRects(a, out.items));
    out.items[3] = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeDamageRects(a, 0, &rects, &out));
    try std.testing.expectError(Error.InvalidMessage, encodeDamageRects(a, 7, &.{}, &out));
    try std.testing.expectError(Error.InvalidTable, decodeDamageRects(a, out.items[0 .. out.items.len - 1]));
}

test "cursor update preserves exactly one active cursor" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);
    const frame_update = try cursorFrameUpdateMessage(a, 2, 1, 1);
    defer a.free(frame_update);
    try scene.apply(frame_update);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    const inactive: Cursor = .{ .window_id = 100, .x = 0, .y = 0, .width = 2, .height = 10, .kind = 1, .visible = true, .active = false };
    try encodeCursorUpdate(a, 1, inactive, &payload);
    const deactivate_only = try windowLifecycleMessage(a, protocol.Message.cursor_update, 3, 7, payload.items);
    defer a.free(deactivate_only);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(deactivate_only));
    try std.testing.expectEqual(@as(usize, 1), scene.cursor_count);
    try std.testing.expect(scene.cursor.?.active);

    payload.clearRetainingCapacity();
    try encodeCursorUpdate(a, 1, inactive, &payload);
    const inactive_missing = try windowLifecycleMessage(a, protocol.Message.cursor_update, 3, 7, payload.items);
    defer a.free(inactive_missing);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(inactive_missing));

    const second_active: Cursor = .{ .window_id = 101, .x = 0, .y = 0, .width = 2, .height = 10, .kind = 1, .visible = true, .active = true };
    payload.clearRetainingCapacity();
    try encodeCursorUpdate(a, 1, second_active, &payload);
    const append_active = try windowLifecycleMessage(a, protocol.Message.cursor_update, 3, 7, payload.items);
    defer a.free(append_active);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(append_active));
    try std.testing.expectEqual(@as(usize, 1), scene.cursor_count);
}

test "scene atomically replaces damage with bounded active-frame rects" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);
    try std.testing.expectEqual(@as(usize, 1), scene.damage.items.len);

    const rects = [_]Rect{
        .{ .x = 4, .y = 4, .width = 30, .height = 20 },
        .{ .x = 40, .y = 30, .width = 20, .height = 10 },
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeDamageRects(a, 1, &rects, &payload);
    const message = try windowLifecycleMessage(a, protocol.Message.damage_rects, 3, 7, payload.items);
    defer a.free(message);
    try scene.apply(message);
    try std.testing.expectEqualSlices(Rect, &rects, scene.damage.items);

    const outside = [_]Rect{.{ .x = 70, .y = 50, .width = 20, .height = 20 }};
    payload.clearRetainingCapacity();
    try encodeDamageRects(a, 1, &outside, &payload);
    const outside_message = try windowLifecycleMessage(a, protocol.Message.damage_rects, 4, 7, payload.items);
    defer a.free(outside_message);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(outside_message));
    try std.testing.expectEqualSlices(Rect, &rects, scene.damage.items);

    const wrong_envelope = try windowLifecycleMessage(a, protocol.Message.damage_rects, 4, 8, payload.items);
    defer a.free(wrong_envelope);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_envelope));
    try std.testing.expectEqualSlices(Rect, &rects, scene.damage.items);
}

test "border update enforces strict form and active frame" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const border: BorderUpdate = .{
        .sides = BorderSides.top | BorderSides.left,
        .thickness = 4,
        .color = .{ 12, 34, 56, 255 },
        .frame_generation = 1,
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeBorderUpdate(a, border, &payload);
    try std.testing.expectEqual(border_update_size, payload.items.len);
    try std.testing.expectEqual(border, try decodeBorderUpdate(payload.items));

    const message = try windowLifecycleMessage(a, protocol.Message.border_update, 3, 7, payload.items);
    defer a.free(message);
    try scene.apply(message);
    try std.testing.expectEqual(border, scene.border.?);

    payload.items[2] = 0x10;
    try std.testing.expectError(Error.InvalidMessage, decodeBorderUpdate(payload.items));
    payload.items[2] = BorderSides.top | BorderSides.left;
    payload.items[4] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeBorderUpdate(payload.items));
    payload.items[4] = 4;
    try std.testing.expectError(Error.InvalidTable, decodeBorderUpdate(payload.items[0 .. payload.items.len - 1]));

    std.mem.writeInt(u32, payload.items[12..16], 2, .little);

    const stale = try windowLifecycleMessage(a, protocol.Message.border_update, 4, 7, payload.items);
    defer a.free(stale);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(stale));
    try std.testing.expectEqual(border, scene.border.?);
}

test "face patch updates colors and advances generation" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const face: protocol.FaceDefine = .{
        .face_id = 8,
        .generation = 2,
        .presence = .{ .foreground = true },
        .foreground = .{ 1, 2, 3, 255 },
    };
    var face_payload: std.ArrayList(u8) = .empty;
    defer face_payload.deinit(a);
    try protocol.encodeFaceDefine(a, face, &face_payload);
    const define = try windowLifecycleMessage(a, protocol.Message.face_define, 3, 7, face_payload.items);
    defer a.free(define);
    try scene.apply(define);

    const patch: protocol.FacePatch = .{
        .flags = protocol.FacePatchFlags.foreground | protocol.FacePatchFlags.background,
        .face_id = 8,
        .expected_generation = 2,
        .new_generation = 3,
        .foreground = .{ 9, 10, 11, 255 },
        .background = .{ 20, 30, 40, 255 },
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeFacePatch(a, patch, &payload);
    try std.testing.expectEqual(protocol.face_patch_size, payload.items.len);
    try std.testing.expectEqual(patch, try protocol.decodeFacePatch(payload.items));
    const message = try windowLifecycleMessage(a, protocol.Message.face_patch, 4, 7, payload.items);
    defer a.free(message);
    try scene.apply(message);

    const patched = scene.faces.lookup(8).?;
    try std.testing.expectEqual(@as(u32, 3), patched.generation);
    try std.testing.expect(patched.payload.presence.background);
    try std.testing.expectEqual([4]u8{ 9, 10, 11, 255 }, patched.payload.foreground);
    try std.testing.expectEqual([4]u8{ 20, 30, 40, 255 }, patched.payload.background);

    const stale = try windowLifecycleMessage(a, protocol.Message.face_patch, 5, 7, payload.items);
    defer a.free(stale);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(stale));
}

test "clear area has exact wire form and validates active face" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const face: protocol.FaceDefine = .{
        .face_id = 9,
        .generation = 3,
        .presence = .{ .background = true },
        .background = .{ 12, 34, 56, 255 },
    };
    var face_payload: std.ArrayList(u8) = .empty;
    defer face_payload.deinit(a);
    try protocol.encodeFaceDefine(a, face, &face_payload);
    const face_message = try windowLifecycleMessage(a, protocol.Message.face_define, 3, 7, face_payload.items);
    defer a.free(face_message);
    try scene.apply(face_message);

    const area: ClearArea = .{
        .window_id = 100,
        .rect = .{ .x = 8, .y = 8, .width = 24, .height = 16 },
        .face_id = 9,
        .face_generation = 3,
        .frame_generation = 1,
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeClearArea(a, area, &payload);
    try std.testing.expectEqual(clear_area_size, payload.items.len);
    try std.testing.expectEqual(area, try decodeClearArea(payload.items));

    const message = try windowLifecycleMessage(a, protocol.Message.clear_area, 4, 7, payload.items);
    defer a.free(message);
    try scene.apply(message);
    try std.testing.expectEqual(area, scene.clear_areas.items[0]);

    const outside: ClearArea = .{
        .window_id = 100,
        .rect = .{ .x = 72, .y = 8, .width = 16, .height = 16 },
        .face_id = 9,
        .face_generation = 3,
        .frame_generation = 1,
    };
    payload.clearRetainingCapacity();
    try encodeClearArea(a, outside, &payload);
    const outside_message = try windowLifecycleMessage(a, protocol.Message.clear_area, 5, 7, payload.items);
    defer a.free(outside_message);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(outside_message));
    try std.testing.expectEqual(@as(usize, 1), scene.clear_areas.items.len);

    const stale_face: ClearArea = .{
        .window_id = 100,
        .rect = area.rect,
        .face_id = 9,
        .face_generation = 2,
        .frame_generation = 1,
    };
    payload.clearRetainingCapacity();
    try encodeClearArea(a, stale_face, &payload);
    const stale_message = try windowLifecycleMessage(a, protocol.Message.clear_area, 5, 7, payload.items);
    defer a.free(stale_message);
    try std.testing.expectError(Error.ResourceNotLive, scene.apply(stale_message));
    try std.testing.expectEqual(@as(usize, 1), scene.clear_areas.items.len);
}

test "scroll run has exact wire form and validates vertical copy bounds" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const run: ScrollRun = .{
        .window_id = 100,
        .source_y = 0,
        .destination_y = 10,
        .width = 80,
        .height = 40,
        .frame_generation = 1,
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeScrollRun(a, run, &payload);
    try std.testing.expectEqual(scroll_run_size, payload.items.len);
    try std.testing.expectEqual(run, try decodeScrollRun(payload.items));

    const message = try windowLifecycleMessage(a, protocol.Message.scroll_run, 3, 7, payload.items);
    defer a.free(message);
    try scene.apply(message);
    try std.testing.expectEqual(run, scene.scroll_runs.items[0]);

    var too_tall = run;
    too_tall.height = 61;
    payload.clearRetainingCapacity();
    try encodeScrollRun(a, too_tall, &payload);
    const invalid = try windowLifecycleMessage(a, protocol.Message.scroll_run, 4, 7, payload.items);
    defer a.free(invalid);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(invalid));
    try std.testing.expectEqual(@as(usize, 1), scene.scroll_runs.items.len);
}

test "window scroll state validates geometry and upserts per window" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const state: WindowScrollState = .{
        .flags = WindowScrollFlags.vertical_visible,
        .window_id = 100,
        .frame_generation = 1,
        .content_size = 2000,
        .viewport_size = 400,
        .position = 400,
        .track_width = 12,
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeWindowScrollState(a, state, &payload);
    try std.testing.expectEqual(window_scroll_state_size, payload.items.len);
    try std.testing.expectEqual(state, try decodeWindowScrollState(payload.items));
    const message = try windowLifecycleMessage(a, protocol.Message.window_scroll_state, 3, 7, payload.items);
    defer a.free(message);
    try scene.apply(message);
    try std.testing.expectEqual(state, scene.scroll_states.items[0]);

    var updated = state;
    updated.position = 800;
    payload.clearRetainingCapacity();
    try encodeWindowScrollState(a, updated, &payload);
    const updated_message = try windowLifecycleMessage(a, protocol.Message.scrollbar_state, 4, 7, payload.items);
    defer a.free(updated_message);
    try scene.apply(updated_message);
    try std.testing.expectEqual(@as(u32, 800), scene.scroll_states.items[0].position);

    const second_window = try windowCreateMessage(a, 5, 7, .{
        .window_id = 101,
        .parent_window_id = 0,
        .x = 0,
        .y = 0,
        .width = 40,
        .height = 40,
        .flags = 2,
        .default_face_id = 0,
        .depth = 0,
    });
    defer a.free(second_window);
    try scene.apply(second_window);
    const deleted_state: WindowScrollState = .{
        .flags = WindowScrollFlags.vertical_visible,
        .window_id = 101,
        .frame_generation = 1,
        .content_size = 400,
        .viewport_size = 100,
        .position = 0,
        .track_width = 8,
    };
    payload.clearRetainingCapacity();
    try encodeWindowScrollState(a, deleted_state, &payload);
    const deleted_state_message = try windowLifecycleMessage(a, protocol.Message.scrollbar_state, 6, 7, payload.items);
    defer a.free(deleted_state_message);
    try scene.apply(deleted_state_message);
    try std.testing.expectEqual(@as(usize, 2), scene.scroll_states.items.len);

    const delete = try windowDeleteMessage(a, 7, 7, 101);
    defer a.free(delete);
    try scene.apply(delete);
    try std.testing.expectEqual(@as(usize, 1), scene.scroll_states.items.len);
    try std.testing.expectEqual(@as(u64, 100), scene.scroll_states.items[0].window_id);

    var invalid = state;
    invalid.position = 1601;
    payload.clearRetainingCapacity();
    try std.testing.expectError(Error.InvalidMessage, encodeWindowScrollState(a, invalid, &payload));
    try std.testing.expectEqual(@as(u32, 800), scene.scroll_states.items[0].position);
    scene.resetForResync();
    try std.testing.expect(scene.scroll_states.items.len == 0);
}

test "tooltip lifecycle validates frame owner and bounded text" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var show: TooltipShow = .{
        .tooltip_id = 8,
        .generation = 1,
        .window_id = 100,
        .frame_generation = 1,
        .x = 8,
        .y = 8,
        .max_width = 32,
        .max_height = 16,
    };
    const text = "Emacs";
    show.text_length = text.len;
    @memcpy(show.text[0..text.len], text);
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    var invalid = show;
    invalid.window_id = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeTooltipShow(a, invalid, &payload));
    invalid = show;
    invalid.frame_generation = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeTooltipShow(a, invalid, &payload));
    invalid = show;
    invalid.x = -1;
    payload.clearRetainingCapacity();
    try encodeTooltipShow(a, invalid, &payload);
    {
        const outside_owner = try windowLifecycleMessage(a, protocol.Message.tooltip_show, 3, 7, payload.items);
        defer a.free(outside_owner);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(outside_owner));
    }
    try std.testing.expect(scene.tooltip == null);
    payload.clearRetainingCapacity();
    try encodeTooltipShow(a, show, &payload);
    try std.testing.expectEqual(tooltip_show_size, payload.items.len);
    try std.testing.expectEqual(show, try decodeTooltipShow(payload.items));
    {
        const message = try windowLifecycleMessage(a, protocol.Message.tooltip_show, 3, 7, payload.items);
        defer a.free(message);
        try scene.apply(message);
    }
    try std.testing.expectEqual(show, scene.tooltip.?);

    payload.clearRetainingCapacity();
    try encodeTooltipShow(a, show, &payload);
    {
        const stale = try windowLifecycleMessage(a, protocol.Message.tooltip_show, 4, 7, payload.items);
        defer a.free(stale);
        try std.testing.expectError(Error.StaleGeneration, scene.apply(stale));
    }

    payload.clearRetainingCapacity();
    try encodeTooltipHide(a, .{ .tooltip_id = 8, .generation = 1 }, &payload);
    {
        const cross_frame = try windowLifecycleMessage(a, protocol.Message.tooltip_hide, 4, 8, payload.items);
        defer a.free(cross_frame);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(cross_frame));
    }

    const move: TooltipMove = .{
        .tooltip_id = 8,
        .generation = 1,
        .window_id = 100,
        .frame_generation = 1,
        .x = 24,
        .y = 20,
    };
    payload.clearRetainingCapacity();
    try encodeTooltipMove(a, move, &payload);
    try std.testing.expectEqual(tooltip_move_size, payload.items.len);
    try std.testing.expectEqual(move, try decodeTooltipMove(payload.items));
    {
        const accepted = try windowLifecycleMessage(a, protocol.Message.tooltip_move, 4, 7, payload.items);
        defer a.free(accepted);
        try scene.apply(accepted);
    }
    try std.testing.expectEqual(@as(i32, 24), scene.tooltip.?.x);
    try std.testing.expectEqual(@as(i32, 20), scene.tooltip.?.y);

    const hide: TooltipHide = .{ .tooltip_id = 8, .generation = 1 };
    payload.clearRetainingCapacity();
    try encodeTooltipHide(a, hide, &payload);
    try std.testing.expectEqual(tooltip_hide_size, payload.items.len);
    try std.testing.expectEqual(hide, try decodeTooltipHide(payload.items));
    {
        const accepted = try windowLifecycleMessage(a, protocol.Message.tooltip_hide, 5, 7, payload.items);
        defer a.free(accepted);
        try scene.apply(accepted);
    }
    try std.testing.expect(scene.tooltip == null);

    payload.clearRetainingCapacity();
    try encodeTooltipHide(a, hide, &payload);
    {
        const repeat = try windowLifecycleMessage(a, protocol.Message.tooltip_hide, 6, 7, payload.items);
        defer a.free(repeat);
        try std.testing.expectError(Error.ResourceNotLive, scene.apply(repeat));
    }

    show.text_length = text.len;
    @memcpy(show.text[0..text.len], text);
    payload.clearRetainingCapacity();
    try encodeTooltipShow(a, show, &payload);
    {
        const shown = try windowLifecycleMessage(a, protocol.Message.tooltip_show, 6, 7, payload.items);
        defer a.free(shown);
        try scene.apply(shown);
    }
    scene.rows.deinit(a);
    scene.rows = .empty;
    {
        const deleted = try windowDeleteMessage(a, 7, 7, 100);
        defer a.free(deleted);
        try scene.apply(deleted);
    }
    try std.testing.expect(scene.tooltip == null);

    {
        const recreated = try windowCreateMessage(a, 8, 7, .{
            .window_id = 100,
            .parent_window_id = 0,
            .x = 0,
            .y = 0,
            .width = 80,
            .height = 60,
            .flags = 2,
            .default_face_id = 0,
            .depth = 0,
        });
        defer a.free(recreated);
        try scene.apply(recreated);
    }
    {
        const shown = try windowLifecycleMessage(a, protocol.Message.tooltip_show, 9, 7, payload.items);
        defer a.free(shown);
        try scene.apply(shown);
    }
    try std.testing.expect(scene.tooltip != null);
    scene.clearVisualState();
    try std.testing.expect(scene.tooltip == null);
    scene.resetForResync();
    try std.testing.expect(scene.tooltip == null);
}

test "menu model validates active frame and generation lifecycle" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var nodes = [_]protocol.MenuNode{ .{
        .item_id = 20,
        .parent_item_id = 0,
        .kind = .submenu,
        .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
        .depth = 0,
        .label_len = 4,
    }, .{
        .item_id = 21,
        .parent_item_id = 20,
        .kind = .command,
        .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
        .depth = 1,
        .label_len = 8,
    } };
    @memcpy(nodes[0].label[0..4], "File");
    @memcpy(nodes[1].label[0..8], "NewFrame");
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeMenuModelSnapshot(a, .{
        .header = .{ .frame_id = 7, .frame_generation = 1, .menu_id = 3, .menu_generation = 1 },
        .nodes = &nodes,
    }, &payload);
    {
        const message = try windowLifecycleMessage(a, protocol.Message.menu_model, 3, 7, payload.items);
        defer a.free(message);
        try scene.apply(message);
    }
    try std.testing.expectEqualStrings("File", scene.menu_model.?.nodes[0].label[0..4]);

    {
        const stale = try windowLifecycleMessage(a, protocol.Message.menu_model, 4, 7, payload.items);
        defer a.free(stale);
        try std.testing.expectError(Error.StaleGeneration, scene.apply(stale));
    }
    try std.testing.expectEqual(@as(u32, 1), scene.menu_model.?.header.menu_generation);

    payload.clearRetainingCapacity();
    try protocol.encodeMenuModelSnapshot(a, .{
        .header = .{ .frame_id = 7, .frame_generation = 1, .menu_id = 3, .menu_generation = 2 },
        .nodes = &nodes,
    }, &payload);
    {
        const replacement = try windowLifecycleMessage(a, protocol.Message.menu_model, 4, 7, payload.items);
        defer a.free(replacement);
        try scene.apply(replacement);
    }
    try std.testing.expectEqual(@as(u32, 2), scene.menu_model.?.header.menu_generation);

    payload.clearRetainingCapacity();
    try protocol.encodeMenuOpen(a, .{
        .menu_id = 3,
        .menu_generation = 1,
        .item_id = 20,
        .window_id = 100,
        .frame_generation = 1,
        .x = 16,
        .y = 16,
        .width = 48,
        .height = 32,
    }, &payload);
    {
        const stale_open = try windowLifecycleMessage(a, protocol.Message.menu_open, 5, 7, payload.items);
        defer a.free(stale_open);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(stale_open));
    }

    payload.clearRetainingCapacity();
    try protocol.encodeMenuOpen(a, .{
        .menu_id = 3,
        .menu_generation = 2,
        .item_id = 20,
        .window_id = 100,
        .frame_generation = 1,
        .x = 16,
        .y = 16,
        .width = 48,
        .height = 32,
    }, &payload);
    {
        const open = try windowLifecycleMessage(a, protocol.Message.menu_open, 5, 7, payload.items);
        defer a.free(open);
        try scene.apply(open);
    }
    try std.testing.expectEqual(@as(u32, 20), scene.menu_open.?.item_id);

    payload.items[8] = 3;
    {
        const wrong_menu = try windowLifecycleMessage(a, protocol.Message.menu_open, 6, 7, payload.items);
        defer a.free(wrong_menu);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_menu));
    }
    payload.items[8] = 2;

    payload.clearRetainingCapacity();
    try protocol.encodeMenuOpen(a, .{
        .menu_id = 3,
        .menu_generation = 2,
        .item_id = 20,
        .window_id = 100,
        .frame_generation = 1,
        .x = 8,
        .y = 8,
        .width = 48,
        .height = 32,
    }, &payload);
    {
        const replacement_open = try windowLifecycleMessage(a, protocol.Message.menu_open, 6, 7, payload.items);
        defer a.free(replacement_open);
        try scene.apply(replacement_open);
    }
    try std.testing.expectEqual(@as(i32, 8), scene.menu_open.?.x);

    payload.clearRetainingCapacity();
    try protocol.encodeMenuClose(a, .{
        .reason = .dismissal,
        .menu_id = 3,
        .menu_generation = 2,
        .item_id = 21,
        .frame_generation = 1,
    }, &payload);
    {
        const close = try windowLifecycleMessage(a, protocol.Message.menu_close, 7, 7, payload.items);
        defer a.free(close);
        try scene.apply(close);
    }
    try std.testing.expect(scene.menu_open == null);

    {
        const repeat_close = try windowLifecycleMessage(a, protocol.Message.menu_close, 8, 7, payload.items);
        defer a.free(repeat_close);
        try std.testing.expectError(Error.ResourceNotLive, scene.apply(repeat_close));
    }

    payload.clearRetainingCapacity();
    try protocol.encodeMenuOpen(a, .{
        .menu_id = 3,
        .menu_generation = 2,
        .item_id = 20,
        .window_id = 100,
        .frame_generation = 1,
        .x = 16,
        .y = 16,
        .width = 48,
        .height = 32,
    }, &payload);
    {
        const open = try windowLifecycleMessage(a, protocol.Message.menu_open, 8, 7, payload.items);
        defer a.free(open);
        try scene.apply(open);
    }
    scene.rows.deinit(a);
    scene.rows = .empty;
    {
        const deleted = try windowDeleteMessage(a, 9, 7, 100);
        defer a.free(deleted);
        try scene.apply(deleted);
    }
    try std.testing.expect(scene.menu_open == null);
    try std.testing.expect(scene.menu_model != null);

    payload.clearRetainingCapacity();
    try protocol.encodeMenuModelSnapshot(a, .{
        .header = .{ .frame_id = 7, .frame_generation = 1, .menu_id = 3, .menu_generation = 2 },
        .nodes = &nodes,
    }, &payload);
    scene.resetForResync();
    try std.testing.expect(scene.menu_open == null);
    try std.testing.expect(scene.menu_model == null);

    const recreated_create = try createMessage(a, 1, 7, 7);
    defer a.free(recreated_create);
    const recreated_update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(recreated_update);
    try scene.apply(recreated_create);
    try scene.apply(recreated_update);
    {
        const model = try windowLifecycleMessage(a, protocol.Message.menu_model, 3, 7, payload.items);
        defer a.free(model);
        try scene.apply(model);
    }
    payload.clearRetainingCapacity();
    try protocol.encodeMenuOpen(a, .{
        .menu_id = 3,
        .menu_generation = 2,
        .item_id = 20,
        .window_id = 100,
        .frame_generation = 1,
        .x = 16,
        .y = 16,
        .width = 48,
        .height = 32,
    }, &payload);
    {
        const open = try windowLifecycleMessage(a, protocol.Message.menu_open, 4, 7, payload.items);
        defer a.free(open);
        try scene.apply(open);
    }
    {
        var destroy_payload: [8]u8 = undefined;
        std.mem.writeInt(u32, destroy_payload[0..4], 7, .little);
        std.mem.writeInt(u32, destroy_payload[4..8], 1, .little);
        var destroy_message: std.ArrayList(u8) = .empty;
        defer destroy_message.deinit(a);
        try protocol.encodeEnvelope(a, .{
            .flags = 0,
            .message_type = protocol.Message.frame_destroy,
            .sequence = 5,
            .ack_sequence = 0,
            .session_id = 9,
            .frame_id = 7,
            .timestamp_ns = 5,
        }, &destroy_payload, &destroy_message);
        try scene.apply(destroy_message.items);
    }
    try std.testing.expect(scene.menu_open == null);
    try std.testing.expect(scene.menu_model == null);
    try std.testing.expect(scene.frame == null);
}

test "menu patch applies ordered upserts and deletes atomically" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var nodes = [_]protocol.MenuNode{.{
        .item_id = 20,
        .parent_item_id = 0,
        .kind = .submenu,
        .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
        .depth = 0,
        .label_len = 4,
    }};
    @memcpy(nodes[0].label[0..4], "File");
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeMenuModelSnapshot(a, .{
        .header = .{ .frame_id = 7, .frame_generation = 1, .menu_id = 3, .menu_generation = 1 },
        .nodes = &nodes,
    }, &payload);
    {
        const model = try windowLifecycleMessage(a, protocol.Message.menu_model, 3, 7, payload.items);
        defer a.free(model);
        try scene.apply(model);
    }

    var operations = [_]protocol.MenuPatchOperation{
        .{ .operation = .upsert, .node = .{
            .item_id = 21,
            .parent_item_id = 20,
            .kind = .command,
            .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
            .depth = 1,
            .label_len = 8,
        } },
        .{ .operation = .upsert, .node = .{
            .item_id = 20,
            .parent_item_id = 0,
            .kind = .submenu,
            .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
            .depth = 0,
            .label_len = 7,
        } },
    };
    @memcpy(operations[0].node.label[0..8], "NewFrame");
    @memcpy(operations[1].node.label[0..7], "FileNew");
    payload.clearRetainingCapacity();
    try protocol.encodeMenuPatch(a, .{
        .frame_id = 7,
        .frame_generation = 1,
        .menu_id = 3,
        .expected_generation = 1,
        .new_generation = 2,
    }, &operations, &payload);
    {
        const patch = try windowLifecycleMessage(a, protocol.Message.menu_patch, 4, 7, payload.items);
        defer a.free(patch);
        try scene.apply(patch);
    }
    try std.testing.expectEqualStrings("FileNew", scene.menu_model.?.nodes[0].label[0..7]);
    try std.testing.expectEqualStrings("NewFrame", scene.menu_model.?.nodes[1].label[0..8]);
    try std.testing.expectEqual(@as(u32, 2), scene.menu_model.?.header.menu_generation);

    var delete_operations = [_]protocol.MenuPatchOperation{.{ .operation = .delete, .node = .{
        .item_id = 21,
        .parent_item_id = 0,
        .kind = .command,
        .flags = 0,
        .depth = 0,
    } }};
    payload.clearRetainingCapacity();
    try protocol.encodeMenuPatch(a, .{
        .frame_id = 7,
        .frame_generation = 1,
        .menu_id = 3,
        .expected_generation = 1,
        .new_generation = 3,
    }, &delete_operations, &payload);
    {
        const stale = try windowLifecycleMessage(a, protocol.Message.menu_patch, 5, 7, payload.items);
        defer a.free(stale);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(stale));
    }
    try std.testing.expectEqual(@as(u32, 2), scene.menu_model.?.header.menu_generation);

    payload.clearRetainingCapacity();
    try protocol.encodeMenuPatch(a, .{
        .frame_id = 7,
        .frame_generation = 1,
        .menu_id = 3,
        .expected_generation = 2,
        .new_generation = 3,
    }, &delete_operations, &payload);
    {
        const deletion = try windowLifecycleMessage(a, protocol.Message.menu_patch, 5, 7, payload.items);
        defer a.free(deletion);
        try scene.apply(deletion);
    }
    try std.testing.expectEqual(@as(usize, 1), scene.menu_model.?.nodes.len);
    try std.testing.expectEqual(@as(u32, 3), scene.menu_model.?.header.menu_generation);
}

test "menu patch enforces context, ordered hierarchy, and popup cleanup" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var root = protocol.MenuNode{
        .item_id = 20,
        .parent_item_id = 0,
        .kind = .submenu,
        .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
        .depth = 0,
        .label_len = 4,
    };
    @memcpy(root.label[0..4], "File");
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeMenuModelSnapshot(a, .{
        .header = .{ .frame_id = 7, .frame_generation = 1, .menu_id = 3, .menu_generation = 1 },
        .nodes = &.{root},
    }, &payload);
    const model = try windowLifecycleMessage(a, protocol.Message.menu_model, 3, 7, payload.items);
    defer a.free(model);
    try scene.apply(model);

    const delete_child = protocol.MenuNode{
        .item_id = 21,
        .parent_item_id = 0,
        .kind = .command,
        .flags = 0,
        .depth = 0,
    };
    const delete_root = protocol.MenuNode{
        .item_id = 20,
        .parent_item_id = 0,
        .kind = .command,
        .flags = 0,
        .depth = 0,
    };

    var child = protocol.MenuNode{
        .item_id = 21,
        .parent_item_id = 20,
        .kind = .command,
        .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
        .depth = 1,
        .label_len = 8,
    };
    @memcpy(child.label[0..8], "NewFrame");
    payload.clearRetainingCapacity();
    try protocol.encodeMenuPatch(a, .{
        .frame_id = 7,
        .frame_generation = 1,
        .menu_id = 3,
        .expected_generation = 1,
        .new_generation = 2,
    }, &.{.{ .operation = .upsert, .node = child }}, &payload);
    const add_child = try windowLifecycleMessage(a, protocol.Message.menu_patch, 4, 7, payload.items);
    defer a.free(add_child);
    try scene.apply(add_child);

    payload.clearRetainingCapacity();
    try protocol.encodeMenuOpen(a, .{
        .menu_id = 3,
        .menu_generation = 2,
        .item_id = 20,
        .window_id = 100,
        .frame_generation = 1,
        .x = 8,
        .y = 8,
        .width = 16,
        .height = 12,
    }, &payload);
    const open = try windowLifecycleMessage(a, protocol.Message.menu_open, 5, 7, payload.items);
    defer a.free(open);
    try scene.apply(open);
    try std.testing.expect(scene.menu_open != null);

    payload.clearRetainingCapacity();
    try protocol.encodeMenuPatch(a, .{
        .frame_id = 7,
        .frame_generation = 1,
        .menu_id = 3,
        .expected_generation = 2,
        .new_generation = 3,
    }, &.{.{ .operation = .upsert, .node = child }}, &payload);
    const close_popup = try windowLifecycleMessage(a, protocol.Message.menu_patch, 6, 7, payload.items);
    defer a.free(close_popup);
    try scene.apply(close_popup);
    try std.testing.expect(scene.menu_open == null);

    // The envelope may not name a different frame from the patched model.
    const wrong_frame = try windowLifecycleMessage(a, protocol.Message.menu_patch, 7, 8, payload.items);
    defer a.free(wrong_frame);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_frame));

    // The payload may not name a different live menu, and a parent delete
    // earlier in the same patch leaves its current child without a parent.
    payload.clearRetainingCapacity();
    child.depth = 0;
    try protocol.encodeMenuPatch(a, .{
        .frame_id = 7,
        .frame_generation = 1,
        .menu_id = 4,
        .expected_generation = 3,
        .new_generation = 4,
    }, &.{.{ .operation = .delete, .node = delete_child }}, &payload);
    const wrong_menu = try windowLifecycleMessage(a, protocol.Message.menu_patch, 7, 7, payload.items);
    defer a.free(wrong_menu);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_menu));

    payload.clearRetainingCapacity();
    try protocol.encodeMenuPatch(a, .{
        .frame_id = 7,
        .frame_generation = 1,
        .menu_id = 3,
        .expected_generation = 3,
        .new_generation = 4,
    }, &.{
        .{ .operation = .delete, .node = delete_root },
        .{ .operation = .delete, .node = delete_child },
    }, &payload);
    const parent_first = try windowLifecycleMessage(a, protocol.Message.menu_patch, 7, 7, payload.items);
    defer a.free(parent_first);
    try std.testing.expectError(Error.ResourceNotLive, scene.apply(parent_first));
    try std.testing.expectEqual(@as(u32, 3), scene.menu_model.?.header.menu_generation);

    child.depth = 1;
    var replacement = protocol.MenuNode{
        .item_id = 22,
        .parent_item_id = 0,
        .kind = .submenu,
        .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
        .depth = 0,
        .label_len = 5,
    };
    @memcpy(replacement.label[0..5], "Extra");
    payload.clearRetainingCapacity();
    try protocol.encodeMenuPatch(a, .{
        .frame_id = 7,
        .frame_generation = 1,
        .menu_id = 3,
        .expected_generation = 3,
        .new_generation = 4,
    }, &.{
        .{ .operation = .delete, .node = delete_child },
        .{ .operation = .delete, .node = delete_root },
        .{ .operation = .upsert, .node = replacement },
    }, &payload);
    const ordered = try windowLifecycleMessage(a, protocol.Message.menu_patch, 7, 7, payload.items);
    defer a.free(ordered);
    try scene.apply(ordered);
    try std.testing.expectEqual(@as(u32, 4), scene.menu_model.?.header.menu_generation);
    try std.testing.expectEqual(@as(usize, 1), scene.menu_model.?.nodes.len);
    try std.testing.expectEqual(@as(u32, 22), scene.menu_model.?.nodes[0].item_id);

    scene.resetForResync();
    try std.testing.expect(scene.menu_model == null);
    try std.testing.expect(scene.menu_open == null);
}

test "scene applies bounded toolbar model for active frame" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var fixture_items: [4]protocol.ToolbarItem = undefined;
    var model = protocol.toolbarModelFixture(&fixture_items);
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeToolbarModel(a, model, &payload);
    {
        const message = try windowLifecycleMessage(a, protocol.Message.toolbar_model, 3, 7, payload.items);
        defer a.free(message);
        try scene.apply(message);
    }
    try std.testing.expectEqual(model.header, scene.toolbar.?.header);
    try std.testing.expectEqual(model.items.len, scene.toolbar.?.items.len);

    {
        var wrong_model = model;
        wrong_model.header.frame_generation = 2;
        payload.clearRetainingCapacity();
        try protocol.encodeToolbarModel(a, wrong_model, &payload);
        const wrong = try windowLifecycleMessage(a, protocol.Message.toolbar_model, 4, 7, payload.items);
        defer a.free(wrong);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong));
    }

    model.header.toolbar_generation = 3;
    payload.clearRetainingCapacity();
    try protocol.encodeToolbarModel(a, model, &payload);
    {
        const replacement = try windowLifecycleMessage(a, protocol.Message.toolbar_model, 4, 7, payload.items);
        defer a.free(replacement);
        try scene.apply(replacement);
    }
    try std.testing.expectEqual(@as(u32, 3), scene.toolbar.?.header.toolbar_generation);

    scene.resetForResync();
    try std.testing.expect(scene.toolbar == null);
}

test "scene applies toolbar patch atomically and clears on resync" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var fixture_items: [4]protocol.ToolbarItem = undefined;
    const model = protocol.toolbarModelFixture(&fixture_items);
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeToolbarModel(a, model, &payload);
    {
        const message = try windowLifecycleMessage(a, protocol.Message.toolbar_model, 3, 7, payload.items);
        defer a.free(message);
        try scene.apply(message);
    }

    var undo = protocol.ToolbarItem{ .item_id = 44, .kind = .button, .flags = protocol.ToolbarItemFlags.enabled | protocol.ToolbarItemFlags.visible, .label_len = 4 };
    @memcpy(undo.label[0..4], "Undo");
    var operations = [_]protocol.ToolbarPatchOperation{
        .{ .operation = .upsert, .item = undo },
        .{ .operation = .delete, .item = .{ .item_id = 43, .kind = .button, .flags = 0 } },
    };
    payload.clearRetainingCapacity();
    try protocol.encodeToolbarPatch(a, .{
        .frame_id = 7,
        .frame_generation = 1,
        .toolbar_id = 9,
        .expected_generation = 2,
        .new_generation = 3,
    }, &operations, &payload);
    {
        const patch = try windowLifecycleMessage(a, protocol.Message.toolbar_patch, 4, 7, payload.items);
        defer a.free(patch);
        try scene.apply(patch);
    }
    try std.testing.expectEqual(@as(u32, 3), scene.toolbar.?.header.toolbar_generation);
    try std.testing.expectEqual(@as(usize, 4), scene.toolbar.?.items.len);
    try std.testing.expectEqualStrings("Undo", scene.toolbar.?.items[3].label[0..4]);

    var redo = undo;
    redo.item_id = 40;
    redo.label = @splat(0);
    redo.label_len = 4;
    @memcpy(redo.label[0..4], "Redo");
    var ordered_operations = [_]protocol.ToolbarPatchOperation{
        .{ .operation = .delete, .item = .{ .item_id = 40, .kind = .button, .flags = 0 } },
        .{ .operation = .upsert, .item = redo },
    };
    payload.clearRetainingCapacity();
    try protocol.encodeToolbarPatch(a, .{
        .frame_id = 7,
        .frame_generation = 1,
        .toolbar_id = 9,
        .expected_generation = 3,
        .new_generation = 4,
    }, &ordered_operations, &payload);
    {
        const ordered = try windowLifecycleMessage(a, protocol.Message.toolbar_patch, 5, 7, payload.items);
        defer a.free(ordered);
        try scene.apply(ordered);
    }
    try std.testing.expectEqual(@as(u32, 4), scene.toolbar.?.header.toolbar_generation);
    try std.testing.expectEqual(@as(usize, 4), scene.toolbar.?.items.len);
    try std.testing.expectEqual(@as(u32, 40), scene.toolbar.?.items[3].item_id);
    try std.testing.expectEqualStrings("Redo", scene.toolbar.?.items[3].label[0..4]);

    payload.clearRetainingCapacity();
    try protocol.encodeToolbarPatch(a, .{
        .frame_id = 7,
        .frame_generation = 1,
        .toolbar_id = 9,
        .expected_generation = 3,
        .new_generation = 5,
    }, &operations, &payload);
    {
        const stale = try windowLifecycleMessage(a, protocol.Message.toolbar_patch, 6, 7, payload.items);
        defer a.free(stale);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(stale));
    }
    try std.testing.expectEqual(@as(u32, 4), scene.toolbar.?.header.toolbar_generation);

    scene.resetForResync();
    try std.testing.expect(scene.toolbar == null);
}

test "mouse highlight validates state and follows window and face lifecycle" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var face_payload: std.ArrayList(u8) = .empty;
    defer face_payload.deinit(a);
    try protocol.encodeFaceDefine(a, .{
        .face_id = 8,
        .generation = 1,
        .presence = .{ .background = true },
        .background = .{ 0x60, 0x80, 0xa0, 255 },
    }, &face_payload);
    const face_defined = try faceMessage(a, protocol.Message.face_define, 3, face_payload.items);
    defer a.free(face_defined);
    try scene.apply(face_defined);

    var state: MouseHighlightState = .{
        .flags = MouseHighlightFlags.visible,
        .window_id = 100,
        .frame_generation = 1,
        .rect = .{ .x = 8, .y = 8, .width = 16, .height = 8 },
        .face_id = 8,
        .face_generation = 1,
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeMouseHighlightState(a, state, &payload);
    try std.testing.expectEqual(mouse_highlight_state_size, payload.items.len);
    try std.testing.expectEqual(state, try decodeMouseHighlightState(payload.items));
    payload.items[40] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeMouseHighlightState(payload.items));
    payload.items[40] = 0;
    {
        const message = try windowLifecycleMessage(a, protocol.Message.mouse_highlight, 4, 7, payload.items);
        defer a.free(message);
        try scene.apply(message);
    }
    try std.testing.expectEqual(state, scene.mouse_highlights[0]);
    try std.testing.expectEqual(@as(usize, 1), scene.mouse_highlight_count);

    const second = try windowCreateMessage(a, 5, 7, .{
        .window_id = 101,
        .parent_window_id = 100,
        .x = 0,
        .y = 8,
        .width = 40,
        .height = 20,
        .flags = protocol.window_tree_flag_visible,
        .default_face_id = 0,
        .depth = 1,
    });
    defer a.free(second);
    try scene.apply(second);
    var second_state = state;
    second_state.window_id = 101;
    second_state.rect = .{ .x = 0, .y = 0, .width = 8, .height = 4 };
    payload.clearRetainingCapacity();
    try encodeMouseHighlightState(a, second_state, &payload);
    {
        const message = try windowLifecycleMessage(a, protocol.Message.mouse_highlight, 6, 7, payload.items);
        defer a.free(message);
        try scene.apply(message);
    }
    try std.testing.expectEqual(@as(usize, 2), scene.mouse_highlight_count);

    var invalid = state;
    invalid.frame_generation = 2;
    payload.clearRetainingCapacity();
    try encodeMouseHighlightState(a, invalid, &payload);
    {
        const message = try windowLifecycleMessage(a, protocol.Message.mouse_highlight, 7, 7, payload.items);
        defer a.free(message);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(message));
    }

    invalid = state;
    invalid.window_id = 999;
    payload.clearRetainingCapacity();
    try encodeMouseHighlightState(a, invalid, &payload);
    {
        const message = try windowLifecycleMessage(a, protocol.Message.mouse_highlight, 7, 7, payload.items);
        defer a.free(message);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(message));
    }

    invalid = state;
    invalid.rect = .{ .x = 79, .y = 0, .width = 2, .height = 8 };
    payload.clearRetainingCapacity();
    try encodeMouseHighlightState(a, invalid, &payload);
    {
        const message = try windowLifecycleMessage(a, protocol.Message.mouse_highlight, 7, 7, payload.items);
        defer a.free(message);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(message));
    }

    invalid = state;
    invalid.face_generation = 2;
    payload.clearRetainingCapacity();
    try encodeMouseHighlightState(a, invalid, &payload);
    {
        const message = try windowLifecycleMessage(a, protocol.Message.mouse_highlight, 7, 7, payload.items);
        defer a.free(message);
        try std.testing.expectError(Error.StaleGeneration, scene.apply(message));
    }
    try std.testing.expectEqual(@as(usize, 2), scene.mouse_highlight_count);

    payload.clearRetainingCapacity();
    try protocol.encodeFacePatch(a, .{
        .flags = protocol.FacePatchFlags.background,
        .face_id = 8,
        .expected_generation = 1,
        .new_generation = 2,
        .foreground = .{ 0, 0, 0, 0 },
        .background = .{ 0xa0, 0x80, 0x60, 255 },
    }, &payload);
    const face_patched = try faceMessage(a, protocol.Message.face_patch, 7, payload.items);
    defer a.free(face_patched);
    try scene.apply(face_patched);
    try std.testing.expectEqual(@as(usize, 0), scene.mouse_highlight_count);

    state.face_generation = 2;
    second_state.face_generation = 2;
    payload.clearRetainingCapacity();
    try encodeMouseHighlightState(a, state, &payload);
    {
        const message = try windowLifecycleMessage(a, protocol.Message.mouse_highlight, 8, 7, payload.items);
        defer a.free(message);
        try scene.apply(message);
    }
    payload.clearRetainingCapacity();
    try encodeMouseHighlightState(a, second_state, &payload);
    {
        const message = try windowLifecycleMessage(a, protocol.Message.mouse_highlight, 9, 7, payload.items);
        defer a.free(message);
        try scene.apply(message);
    }

    const child_delete = try windowDeleteMessage(a, 10, 7, 101);
    defer a.free(child_delete);
    try scene.apply(child_delete);
    try std.testing.expectEqual(@as(usize, 1), scene.mouse_highlight_count);
    try std.testing.expectEqual(state, scene.mouse_highlights[0]);

    const authoritative_update = try updateMessage(a, 11, 7, 7, 80, 0);
    defer a.free(authoritative_update);
    try scene.apply(authoritative_update);
    try std.testing.expectEqual(@as(usize, 0), scene.mouse_highlight_count);
}

test "window face state validates live resources and follows face lifecycle" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const face: protocol.FaceDefine = .{
        .face_id = 8,
        .generation = 1,
        .presence = .{ .background = true },
        .background = .{ 12, 34, 56, 255 },
    };
    var face_payload: std.ArrayList(u8) = .empty;
    defer face_payload.deinit(a);
    try protocol.encodeFaceDefine(a, face, &face_payload);
    const define = try faceMessage(a, protocol.Message.face_define, 3, face_payload.items);
    defer a.free(define);
    try scene.apply(define);

    const state: WindowFaceState = .{
        .window_id = 100,
        .frame_generation = 1,
        .face_id = 8,
        .face_generation = 1,
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeWindowFaceState(a, state, &payload);
    try std.testing.expectEqual(window_face_state_size, payload.items.len);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, payload.items[0..2], .little));
    try std.testing.expectEqual(@as(u8, 0), payload.items[2]);
    try std.testing.expectEqual(@as(u8, 0), payload.items[3]);
    try std.testing.expectEqual(state, try decodeWindowFaceState(payload.items));

    const message = try windowLifecycleMessage(a, protocol.Message.window_face, 4, 7, payload.items);
    defer a.free(message);
    try scene.apply(message);
    try std.testing.expectEqual(state, scene.window_faces.items[0]);

    const wrong_size = try windowLifecycleMessage(a, protocol.Message.window_face, 5, 7, payload.items[0 .. payload.items.len - 1]);
    defer a.free(wrong_size);
    try std.testing.expectError(Error.InvalidTable, scene.apply(wrong_size));

    payload.items[2] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeWindowFaceState(payload.items));
    payload.items[2] = 0;
    payload.items[3] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeWindowFaceState(payload.items));
    payload.items[3] = 0;

    const face_two: protocol.FaceDefine = .{ .face_id = 9, .generation = 1 };
    face_payload.clearRetainingCapacity();
    try protocol.encodeFaceDefine(a, face_two, &face_payload);
    const define_two = try faceMessage(a, protocol.Message.face_define, 5, face_payload.items);
    defer a.free(define_two);
    try scene.apply(define_two);

    var replacement = state;
    replacement.face_id = 9;
    payload.clearRetainingCapacity();
    try encodeWindowFaceState(a, replacement, &payload);
    const replacement_message = try windowLifecycleMessage(a, protocol.Message.window_face, 6, 7, payload.items);
    defer a.free(replacement_message);
    try scene.apply(replacement_message);
    try std.testing.expectEqual(@as(usize, 1), scene.window_faces.items.len);
    try std.testing.expectEqual(replacement, scene.window_faces.items[0]);

    var stale_frame = replacement;
    stale_frame.frame_generation = 2;
    payload.clearRetainingCapacity();
    try encodeWindowFaceState(a, stale_frame, &payload);
    const stale_frame_message = try windowLifecycleMessage(a, protocol.Message.window_face, 7, 7, payload.items);
    defer a.free(stale_frame_message);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(stale_frame_message));

    var missing_owner = replacement;
    missing_owner.window_id = 999;
    payload.clearRetainingCapacity();
    try encodeWindowFaceState(a, missing_owner, &payload);
    const missing_message = try windowLifecycleMessage(a, protocol.Message.window_face, 7, 7, payload.items);
    defer a.free(missing_message);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(missing_message));

    var stale_face = replacement;
    stale_face.face_generation = 2;
    payload.clearRetainingCapacity();
    try encodeWindowFaceState(a, stale_face, &payload);
    const stale_face_message = try windowLifecycleMessage(a, protocol.Message.window_face, 7, 7, payload.items);
    defer a.free(stale_face_message);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(stale_face_message));
    try std.testing.expectEqual(replacement, scene.window_faces.items[0]);

    payload.clearRetainingCapacity();
    try protocol.encodeFacePatch(a, .{
        .flags = protocol.FacePatchFlags.background,
        .face_id = 9,
        .expected_generation = 1,
        .new_generation = 2,
        .foreground = .{ 0, 0, 0, 0 },
        .background = .{ 1, 2, 3, 255 },
    }, &payload);
    const face_patch = try faceMessage(a, protocol.Message.face_patch, 7, payload.items);
    defer a.free(face_patch);
    try scene.apply(face_patch);
    try std.testing.expectEqual(@as(usize, 0), scene.window_faces.items.len);

    payload.clearRetainingCapacity();
    try encodeWindowFaceState(a, .{
        .window_id = 100,
        .frame_generation = 1,
        .face_id = 9,
        .face_generation = 2,
    }, &payload);
    const replacement_state = try windowLifecycleMessage(a, protocol.Message.window_face, 8, 7, payload.items);
    defer a.free(replacement_state);
    try scene.apply(replacement_state);
    try std.testing.expectEqual(@as(usize, 1), scene.window_faces.items.len);

    payload.clearRetainingCapacity();
    try protocol.encodeFaceDelete(a, .{ .face_id = 9, .generation = 2 }, &payload);
    const deletion = try faceMessage(a, protocol.Message.face_delete, 9, payload.items);
    defer a.free(deletion);
    try scene.apply(deletion);
    try std.testing.expectEqual(@as(usize, 0), scene.window_faces.items.len);

    payload.clearRetainingCapacity();
    const empty_window_create = try windowCreateMessage(a, 10, 7, .{
        .window_id = 900,
        .parent_window_id = 0,
        .x = 0,
        .y = 0,
        .width = 20,
        .height = 20,
        .flags = 2,
        .default_face_id = 0,
        .depth = 0,
    });
    defer a.free(empty_window_create);
    try scene.apply(empty_window_create);

    try encodeWindowFaceState(a, .{
        .window_id = 900,
        .frame_generation = 1,
        .face_id = 8,
        .face_generation = 1,
    }, &payload);
    const reattach = try windowLifecycleMessage(a, protocol.Message.window_face, 11, 7, payload.items);
    defer a.free(reattach);
    try scene.apply(reattach);
    try std.testing.expectEqual(@as(usize, 1), scene.window_faces.items.len);

    const window_delete = try windowDeleteMessage(a, 12, 7, 900);
    defer a.free(window_delete);
    try scene.apply(window_delete);
    try std.testing.expectEqual(@as(usize, 0), scene.window_faces.items.len);
}

test "window face state rejects overflow atomically" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const face: protocol.FaceDefine = .{ .face_id = 8, .generation = 1 };
    var face_payload: std.ArrayList(u8) = .empty;
    defer face_payload.deinit(a);
    try protocol.encodeFaceDefine(a, face, &face_payload);
    const define = try faceMessage(a, protocol.Message.face_define, 3, face_payload.items);
    defer a.free(define);
    try scene.apply(define);

    for (0..max_window_faces) |index| {
        try scene.window_faces.append(a, .{
            .window_id = 1000 + @as(u64, @intCast(index)),
            .frame_generation = 1,
            .face_id = 8,
            .face_generation = 1,
        });
    }

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeWindowFaceState(a, .{
        .window_id = 100,
        .frame_generation = 1,
        .face_id = 8,
        .face_generation = 1,
    }, &payload);
    const message = try windowLifecycleMessage(a, protocol.Message.window_face, 4, 7, payload.items);
    defer a.free(message);
    try std.testing.expectError(Error.Unsupported, scene.apply(message));
    try std.testing.expectEqual(max_window_faces, scene.window_faces.items.len);
    for (scene.window_faces.items) |state| {
        try std.testing.expect(state.window_id != 100);
    }
}

test "window geometry validates owner content and follows window patch" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const state: WindowGeometryState = .{
        .window_id = 100,
        .frame_generation = 1,
        .content = .{ .x = 2, .y = 2, .width = 60, .height = 40 },
        .body = .{ .x = 4, .y = 4, .width = 40, .height = 20 },
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeWindowGeometryState(a, state, &payload);
    try std.testing.expectEqual(window_geometry_state_size, payload.items.len);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, payload.items[0..2], .little));
    try std.testing.expectEqual(state, try decodeWindowGeometryState(payload.items));

    const message = try windowLifecycleMessage(a, protocol.Message.window_geometry, 3, 7, payload.items);
    defer a.free(message);
    try scene.apply(message);
    try std.testing.expectEqual(state, scene.window_geometries.items[0]);

    var replacement = state;
    replacement.content = .{ .x = 4, .y = 4, .width = 50, .height = 30 };
    replacement.body = .{ .x = 4, .y = 4, .width = 30, .height = 10 };
    payload.clearRetainingCapacity();
    try encodeWindowGeometryState(a, replacement, &payload);
    const replacement_message = try windowLifecycleMessage(a, protocol.Message.window_geometry, 4, 7, payload.items);
    defer a.free(replacement_message);
    try scene.apply(replacement_message);
    try std.testing.expectEqual(@as(usize, 1), scene.window_geometries.items.len);
    try std.testing.expectEqual(replacement, scene.window_geometries.items[0]);

    var body_outside = replacement;
    body_outside.body.width = 60;
    payload.clearRetainingCapacity();
    try std.testing.expectError(Error.InvalidMessage, encodeWindowGeometryState(a, body_outside, &payload));

    var outside_owner = replacement;
    outside_owner.content.width = 100;
    payload.clearRetainingCapacity();
    try encodeWindowGeometryState(a, outside_owner, &payload);
    const outside_message = try windowLifecycleMessage(a, protocol.Message.window_geometry, 5, 7, payload.items);
    defer a.free(outside_message);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(outside_message));

    payload.clearRetainingCapacity();
    try protocol.encodeWindowPatch(a, .{
        .flags = protocol.WindowPatchFlags.width,
        .frame_id = 7,
        .frame_generation = 1,
        .window_id = 100,
        .width = 20,
    }, &payload);
    const shrink = try windowLifecycleMessage(a, protocol.Message.window_patch, 5, 7, payload.items);
    defer a.free(shrink);
    try scene.apply(shrink);
    try std.testing.expectEqual(@as(usize, 0), scene.window_geometries.items.len);
}

test "window zones validate disjoint owner regions and lifecycle" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var state: WindowZonesState = .{
        .window_id = 100,
        .frame_generation = 1,
        .presence = WindowZoneBits.left_fringe | WindowZoneBits.vertical_scrollbar,
    };
    state.zones[@ctz(WindowZoneBits.left_fringe)] = .{ .x = 0, .y = 0, .width = 4, .height = 60 };
    state.zones[@ctz(WindowZoneBits.vertical_scrollbar)] = .{ .x = 70, .y = 0, .width = 10, .height = 60 };

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeWindowZonesState(a, state, &payload);
    try std.testing.expectEqual(window_zones_state_size, payload.items.len);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, payload.items[0..2], .little));
    try std.testing.expectEqual(state, try decodeWindowZonesState(payload.items));

    const message = try windowLifecycleMessage(a, protocol.Message.window_zones, 3, 7, payload.items);
    defer a.free(message);
    try scene.apply(message);
    try std.testing.expectEqual(state, scene.window_zones.items[0]);

    var replacement = state;
    replacement.presence = WindowZoneBits.left_fringe;
    replacement.zones[@ctz(WindowZoneBits.vertical_scrollbar)] = .{ .x = 0, .y = 0, .width = 0, .height = 0 };
    payload.clearRetainingCapacity();
    try encodeWindowZonesState(a, replacement, &payload);
    const replacement_message = try windowLifecycleMessage(a, protocol.Message.window_zones, 4, 7, payload.items);
    defer a.free(replacement_message);
    try scene.apply(replacement_message);
    try std.testing.expectEqual(@as(usize, 1), scene.window_zones.items.len);
    try std.testing.expectEqual(replacement, scene.window_zones.items[0]);

    var overlapping = replacement;
    overlapping.presence = WindowZoneBits.left_fringe | WindowZoneBits.right_fringe;
    overlapping.zones[@ctz(WindowZoneBits.right_fringe)] = .{ .x = 0, .y = 0, .width = 4, .height = 60 };
    payload.clearRetainingCapacity();
    try std.testing.expectError(Error.InvalidMessage, encodeWindowZonesState(a, overlapping, &payload));

    var outside_owner = replacement;
    outside_owner.zones[@ctz(WindowZoneBits.left_fringe)] = .{ .x = 0, .y = 0, .width = 100, .height = 60 };
    payload.clearRetainingCapacity();
    try encodeWindowZonesState(a, outside_owner, &payload);
    const outside_message = try windowLifecycleMessage(a, protocol.Message.window_zones, 5, 7, payload.items);
    defer a.free(outside_message);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(outside_message));

    payload.clearRetainingCapacity();
    try encodeWindowZonesState(a, state, &payload);
    const reapply = try windowLifecycleMessage(a, protocol.Message.window_zones, 5, 7, payload.items);
    defer a.free(reapply);
    try scene.apply(reapply);

    payload.clearRetainingCapacity();
    try protocol.encodeWindowPatch(a, .{
        .flags = protocol.WindowPatchFlags.width,
        .frame_id = 7,
        .frame_generation = 1,
        .window_id = 100,
        .width = 20,
    }, &payload);
    const shrink = try windowLifecycleMessage(a, protocol.Message.window_patch, 6, 7, payload.items);
    defer a.free(shrink);
    try scene.apply(shrink);
    try std.testing.expectEqual(@as(usize, 0), scene.window_zones.items.len);
}

test "window position validates diagnostic state and upserts per window" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const state: WindowPositionState = .{
        .flags = WindowPositionFlags.point_visible,
        .window_id = 100,
        .frame_generation = 1,
        .buffer_id = 31,
        .buffer_generation = 7,
        .window_start = 101,
        .point = 122,
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeWindowPositionState(a, state, &payload);
    try std.testing.expectEqual(window_position_state_size, payload.items.len);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, payload.items[0..2], .little));
    try std.testing.expectEqual(state, try decodeWindowPositionState(payload.items));

    const message = try windowLifecycleMessage(a, protocol.Message.window_position, 3, 7, payload.items);
    defer a.free(message);
    try scene.apply(message);
    try std.testing.expectEqual(state, scene.window_positions.items[0]);

    var replacement = state;
    replacement.point = 133;
    replacement.flags = 0;
    payload.clearRetainingCapacity();
    try encodeWindowPositionState(a, replacement, &payload);
    const replacement_message = try windowLifecycleMessage(a, protocol.Message.window_position, 4, 7, payload.items);
    defer a.free(replacement_message);
    try scene.apply(replacement_message);
    try std.testing.expectEqual(@as(usize, 1), scene.window_positions.items.len);
    try std.testing.expectEqual(replacement, scene.window_positions.items[0]);

    var invalid = replacement;
    invalid.flags = 0x80;
    payload.clearRetainingCapacity();
    try std.testing.expectError(Error.InvalidMessage, encodeWindowPositionState(a, invalid, &payload));

    payload.clearRetainingCapacity();
    try encodeWindowPositionState(a, replacement, &payload);
    payload.items[payload.items.len - 1] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeWindowPositionState(payload.items));

    var missing_owner = replacement;
    missing_owner.window_id = 999;
    payload.clearRetainingCapacity();
    try encodeWindowPositionState(a, missing_owner, &payload);
    const missing_message = try windowLifecycleMessage(a, protocol.Message.window_position, 5, 7, payload.items);
    defer a.free(missing_message);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(missing_message));

    const authoritative_update = try updateMessage(a, 5, 7, 7, 80, 0);
    defer a.free(authoritative_update);
    try scene.apply(authoritative_update);
    try std.testing.expectEqual(@as(usize, 0), scene.window_positions.items.len);
}

test "divider update validates generation and owner bounds" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const divider: DividerUpdate = .{
        .orientation = .vertical,
        .divider_id = 5,
        .divider_generation = 1,
        .window_id = 100,
        .position = 40,
        .offset = 4,
        .span = 52,
        .thickness = 3,
        .frame_generation = 1,
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeDividerUpdate(a, divider, &payload);
    try std.testing.expectEqual(divider_update_size, payload.items.len);
    try std.testing.expectEqual(divider, try decodeDividerUpdate(payload.items));
    const message = try windowLifecycleMessage(a, protocol.Message.divider_update, 3, 7, payload.items);
    defer a.free(message);
    try scene.apply(message);
    try std.testing.expectEqual(divider, scene.dividers.items[0]);

    const stale = divider;
    payload.clearRetainingCapacity();
    try encodeDividerUpdate(a, stale, &payload);
    const stale_message = try windowLifecycleMessage(a, protocol.Message.divider_update, 4, 7, payload.items);
    defer a.free(stale_message);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(stale_message));

    var newer = divider;
    newer.divider_generation = 2;
    newer.position = 44;
    payload.clearRetainingCapacity();
    try encodeDividerUpdate(a, newer, &payload);
    const newer_message = try windowLifecycleMessage(a, protocol.Message.divider_update, 4, 7, payload.items);
    defer a.free(newer_message);
    try scene.apply(newer_message);
    try std.testing.expectEqual(newer, scene.dividers.items[0]);
}

test "fringe update validates generation and active frame" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const fringe: FringeUpdate = .{
        .side = .left,
        .fringe_id = 7,
        .fringe_generation = 1,
        .window_id = 100,
        .y = 4,
        .height = 40,
        .width = 6,
        .color = .{ 1, 2, 3, 255 },
        .frame_generation = 1,
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeFringeUpdate(a, fringe, &payload);
    try std.testing.expectEqual(fringe_update_size, payload.items.len);
    try std.testing.expectEqual(fringe, try decodeFringeUpdate(payload.items));
    const message = try windowLifecycleMessage(a, protocol.Message.fringe_update, 3, 7, payload.items);
    defer a.free(message);
    try scene.apply(message);
    try std.testing.expectEqual(fringe, scene.fringes.items[0]);

    const stale = fringe;
    payload.clearRetainingCapacity();
    try encodeFringeUpdate(a, stale, &payload);
    const stale_message = try windowLifecycleMessage(a, protocol.Message.fringe_update, 4, 7, payload.items);
    defer a.free(stale_message);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(stale_message));

    var newer = fringe;
    newer.fringe_generation = 2;
    newer.width = 8;
    payload.clearRetainingCapacity();
    try encodeFringeUpdate(a, newer, &payload);
    const newer_message = try windowLifecycleMessage(a, protocol.Message.fringe_update, 4, 7, payload.items);
    defer a.free(newer_message);
    try scene.apply(newer_message);
    try std.testing.expectEqual(newer, scene.fringes.items[0]);
}

test "fringe bitmap resources validate lifecycle and placement references" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var bitmap: protocol.FringeBitmapDefine = .{
        .bitmap_id = 9,
        .generation = 1,
        .width = 2,
        .height = 2,
    };
    bitmap.bits[0] = 0x80;
    bitmap.bits[(protocol.max_fringe_bitmap_dimension + 7) / 8] = 0x40;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeFringeBitmapDefine(a, bitmap, &payload);
    const defined = try faceMessage(a, protocol.Message.fringe_bitmap_define, 3, payload.items);
    defer a.free(defined);
    try scene.apply(defined);
    try std.testing.expectEqual(bitmap, scene.fringe_bitmaps.lookup(9).?.payload);
    try std.testing.expect(fringeBitmapBit(bitmap, 0, 0));
    try std.testing.expect(fringeBitmapBit(bitmap, 1, 1));
    try std.testing.expect(!fringeBitmapBit(bitmap, 1, 0));

    const fringe: FringeUpdate = .{
        .side = .left,
        .fringe_id = 9,
        .fringe_generation = 1,
        .window_id = 100,
        .y = 4,
        .height = 4,
        .width = 4,
        .color = .{ 1, 2, 3, 255 },
        .frame_generation = 1,
    };
    payload.clearRetainingCapacity();
    try encodeFringeUpdate(a, fringe, &payload);
    const placement = try windowLifecycleMessage(a, protocol.Message.fringe_update, 4, 7, payload.items);
    defer a.free(placement);
    try scene.apply(placement);
    try std.testing.expectEqual(@as(usize, 1), scene.fringes.items.len);

    bitmap.generation = 2;
    payload.clearRetainingCapacity();
    try protocol.encodeFringeBitmapDefine(a, bitmap, &payload);
    const replacement = try faceMessage(a, protocol.Message.fringe_bitmap_define, 5, payload.items);
    defer a.free(replacement);
    try scene.apply(replacement);
    try std.testing.expectEqual(@as(u32, 2), scene.fringe_bitmaps.lookup(9).?.generation);
    try std.testing.expectEqual(@as(usize, 0), scene.fringes.items.len);

    payload.clearRetainingCapacity();
    try protocol.encodeFringeBitmapDelete(a, .{ .bitmap_id = 9, .generation = 2 }, &payload);
    const deletion = try faceMessage(a, protocol.Message.fringe_bitmap_delete, 6, payload.items);
    defer a.free(deletion);
    try scene.apply(deletion);
    try std.testing.expect(scene.fringe_bitmaps.lookup(9) == null);
    try std.testing.expectEqual(lifecycle.ResourceStatus.deleted, scene.resources.lookup(.fringe_bitmap, 9).?.status);
    try std.testing.expectEqual(@as(usize, 0), scene.fringes.items.len);

    bitmap.generation = 2;
    var snapshot_payload: std.ArrayList(u8) = .empty;
    defer snapshot_payload.deinit(a);
    try protocol.encodeFringeBitmapDefine(a, bitmap, &snapshot_payload);
    const snapshot_entries = [_]protocol.ResourceSnapshotEntry{
        .{ .kind = .fringe_bitmap, .status = .live, .resource_id = 9, .generation = 2, .payload = snapshot_payload.items },
    };
    const snapshot = try snapshotMessage(a, 7, &snapshot_entries);
    defer a.free(snapshot);
    try scene.apply(snapshot);
    try std.testing.expectEqual(@as(u32, 2), scene.fringe_bitmaps.lookup(9).?.generation);
    try std.testing.expectEqual(@as(usize, 0), scene.fringes.items.len);
}

test "row snapshot update and delete maintain bounded row state" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const row: Row = .{ .window_id = 100, .index = 2, .flags = 0, .x = 0, .y = 40, .width = 80, .height = 10, .ascent = 7, .descent = 2, .baseline = 7, .visible_height = 10 };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeRowSnapshot(a, 1, row, &payload);
    try std.testing.expectEqual(row_snapshot_size, payload.items.len);
    const snapshot = try windowLifecycleMessage(a, protocol.Message.row_snapshot, 3, 7, payload.items);
    defer a.free(snapshot);
    try scene.apply(snapshot);
    try std.testing.expectEqual(@as(usize, 2), scene.rows.items.len);

    var replacement = row;
    replacement.height = 12;
    replacement.visible_height = 12;
    payload.clearRetainingCapacity();
    try encodeRowUpdate(a, 1, replacement, &payload);
    const update_message = try windowLifecycleMessage(a, protocol.Message.row_update, 4, 7, payload.items);
    defer a.free(update_message);
    try scene.apply(update_message);
    try std.testing.expectEqual(@as(i32, 12), scene.rows.items[1].height);

    const other_window = try windowCreateMessage(a, 5, 7, .{
        .window_id = 101,
        .parent_window_id = 0,
        .x = 0,
        .y = 0,
        .width = 80,
        .height = 60,
        .flags = 2,
        .default_face_id = 0,
        .depth = 0,
    });
    defer a.free(other_window);
    try scene.apply(other_window);
    const other_row: Row = .{ .window_id = 101, .index = 2, .flags = 0, .x = 0, .y = 40, .width = 80, .height = 10, .ascent = 7, .descent = 2, .baseline = 7, .visible_height = 10 };
    payload.clearRetainingCapacity();
    try encodeRowSnapshot(a, 1, other_row, &payload);
    const other_snapshot = try windowLifecycleMessage(a, protocol.Message.row_snapshot, 6, 7, payload.items);
    defer a.free(other_snapshot);
    try scene.apply(other_snapshot);
    try scene.text.append(a, .{ .window_id = 100, .row_index = 2, .bytes = try a.dupeZ(u8, "one hundred") });
    try scene.text.append(a, .{ .window_id = 101, .row_index = 2, .bytes = try a.dupeZ(u8, "one oh one") });

    const delete: RowDelete = .{ .frame_generation = 1, .window_id = 100, .row_index = 2 };
    payload.clearRetainingCapacity();
    try encodeRowDelete(a, delete, &payload);
    try std.testing.expectEqual(row_delete_size, payload.items.len);
    const deletion = try windowLifecycleMessage(a, protocol.Message.row_delete, 7, 7, payload.items);
    defer a.free(deletion);
    try scene.apply(deletion);
    try std.testing.expectEqual(@as(usize, 2), scene.rows.items.len);
    try std.testing.expectEqual(@as(usize, 1), scene.text.items.len);
    try std.testing.expectEqual(@as(u64, 101), scene.text.items[0].window_id);
    try std.testing.expectEqualStrings("one oh one", scene.text.items[0].bytes);
}

test "update boundaries reject nesting and stale close" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeUpdateBoundary(a, protocol.Message.begin_update, .{ .frame_generation = 1, .update_id = 77 }, &payload);
    try std.testing.expectEqual(update_boundary_size, payload.items.len);
    const begin = try windowLifecycleMessage(a, protocol.Message.begin_update, 3, 7, payload.items);
    defer a.free(begin);
    try scene.apply(begin);
    try std.testing.expectEqual(@as(u32, 77), scene.active_update_id.?);

    const nested = try windowLifecycleMessage(a, protocol.Message.begin_update, 4, 7, payload.items);
    defer a.free(nested);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(nested));

    payload.clearRetainingCapacity();
    try encodeUpdateBoundary(a, protocol.Message.end_update, .{ .frame_generation = 1, .update_id = 78 }, &payload);
    const wrong_close = try windowLifecycleMessage(a, protocol.Message.end_update, 4, 7, payload.items);
    defer a.free(wrong_close);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_close));

    payload.clearRetainingCapacity();
    try encodeUpdateBoundary(a, protocol.Message.end_update, .{ .frame_generation = 1, .update_id = 77 }, &payload);
    const close = try windowLifecycleMessage(a, protocol.Message.end_update, 4, 7, payload.items);
    defer a.free(close);
    try scene.apply(close);
    try std.testing.expect(scene.active_update_id == null);
}

test "scene stores flush and render hints only for the active frame" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const flush: protocol.FrameFlushPayload = .{
        .flags = protocol.FrameFlushFlags.present_required,
        .frame_generation = 1,
        .redisplay_generation = 1,
        .frame_sequence = 2,
        .deadline_ns = 8,
        .damage_kind = .partial,
    };
    var flush_payload: std.ArrayList(u8) = .empty;
    defer flush_payload.deinit(a);
    try protocol.encodeFrameFlush(a, flush, &flush_payload);
    const flush_message = try windowLifecycleMessage(a, protocol.Message.flush, 3, 7, flush_payload.items);
    defer a.free(flush_message);
    try scene.apply(flush_message);
    try std.testing.expectEqual(flush, scene.flush.?);

    const hint: protocol.RenderHintPayload = .{
        .flags = protocol.RenderHintFlags.damage_only_allowed |
            protocol.RenderHintFlags.deadline_present,
        .preferred_mode = .mailbox,
        .workload = .typing,
        .frame_generation = 1,
        .deadline_ns = 9,
    };
    var hint_payload: std.ArrayList(u8) = .empty;
    defer hint_payload.deinit(a);
    try protocol.encodeRenderHint(a, hint, &hint_payload);
    const hint_message = try windowLifecycleMessage(a, protocol.Message.render_hint, 4, 7, hint_payload.items);
    defer a.free(hint_message);
    try scene.apply(hint_message);
    try std.testing.expectEqual(hint, scene.render_hint.?);

    var stale_payload: std.ArrayList(u8) = .empty;
    defer stale_payload.deinit(a);
    try protocol.encodeFrameFlush(a, .{
        .flags = protocol.FrameFlushFlags.present_required,
        .frame_generation = 2,
        .redisplay_generation = 1,
        .frame_sequence = 2,
        .deadline_ns = 8,
        .damage_kind = .partial,
    }, &stale_payload);
    const stale = try windowLifecycleMessage(a, protocol.Message.flush, 5, 7, stale_payload.items);
    defer a.free(stale);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(stale));
    const wrong_envelope = try windowLifecycleMessage(a, protocol.Message.render_hint, 5, 8, hint_payload.items);
    defer a.free(wrong_envelope);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_envelope));
    try std.testing.expectEqual(flush, scene.flush.?);
    try std.testing.expectEqual(hint, scene.render_hint.?);

    const next_update = try updateMessage(a, 5, 7, 7, 80, 0);
    defer a.free(next_update);
    try scene.apply(next_update);
    try std.testing.expect(scene.flush == null);
    try std.testing.expectEqual(hint, scene.render_hint.?);
}

test "window patch rejects a shrink that would orphan the cursor" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var cursor_payload: std.ArrayList(u8) = .empty;
    defer cursor_payload.deinit(a);
    try encodeCursorUpdate(a, 1, .{ .window_id = 100, .x = 76, .y = 52, .width = 2, .height = 8, .kind = 1, .visible = true, .active = true }, &cursor_payload);
    const cursor_message = try windowLifecycleMessage(a, protocol.Message.cursor_update, 3, 7, cursor_payload.items);
    defer a.free(cursor_message);
    try scene.apply(cursor_message);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeWindowPatch(a, .{
        .flags = protocol.WindowPatchFlags.width | protocol.WindowPatchFlags.height,
        .frame_id = 7,
        .frame_generation = 1,
        .window_id = 100,
        .width = 40,
        .height = 20,
    }, &payload);
    const patch = try windowLifecycleMessage(a, protocol.Message.window_patch, 4, 7, payload.items);
    defer a.free(patch);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(patch));
    try std.testing.expectEqual(@as(i32, 80), scene.windows.items[0].width);
    try std.testing.expectEqual(@as(i32, 60), scene.windows.items[0].height);
    try std.testing.expectEqual(@as(i32, 76), scene.cursor.?.x);
}

test "scene applies lifecycle and atomically validates update" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    var create: [8]u8 = undefined;
    std.mem.writeInt(u32, create[0..4], 7, .little);
    std.mem.writeInt(u32, create[4..8], 1, .little);
    var sink_bytes: std.ArrayList(u8) = .empty;
    defer sink_bytes.deinit(a);
    try protocol.encodeEnvelope(a, .{ .flags = 0, .message_type = protocol.Message.frame_create, .sequence = 1, .ack_sequence = 0, .session_id = 9, .frame_id = 7, .timestamp_ns = 1 }, &create, &sink_bytes);
    try scene.apply(sink_bytes.items);

    const header: protocol.FrameUpdateHeader = .{
        .frame_id = 7,
        .frame_generation = 1,
        .sequence = 2,
        .redisplay_generation = 1,
        .logical_x = 0,
        .logical_y = 0,
        .logical_width = 80,
        .logical_height = 60,
        .physical_x = 0,
        .physical_y = 0,
        .physical_width = 160,
        .physical_height = 120,
        .scale = 2,
        .dpi_x = 192,
        .dpi_y = 192,
        .damage_mode = 2,
        .update_cause = 1,
        .coalesced_count = 0,
        .timestamp_ns = 2,
    };
    var window_bytes: std.ArrayList(u8) = .empty;
    defer window_bytes.deinit(a);
    try encodeWindow(a, .{ .id = 7, .frame_id = 7, .x = 0, .y = 0, .width = 80, .height = 60 }, &window_bytes);
    var row_bytes: std.ArrayList(u8) = .empty;
    defer row_bytes.deinit(a);
    try encodeRow(a, .{ .window_id = 7, .index = 0, .flags = 0, .x = 0, .y = 0, .width = 80, .height = 10, .ascent = 7, .descent = 3, .baseline = 7, .visible_height = 10 }, &row_bytes);
    var damage_bytes: std.ArrayList(u8) = .empty;
    defer damage_bytes.deinit(a);
    try encodeRect(a, .{ .x = 0, .y = 0, .width = 80, .height = 60 }, &damage_bytes);
    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = window_bytes.items },
        .{ .kind = protocol.SectionKind.rows, .records = row_bytes.items },
        .{ .kind = protocol.SectionKind.damage, .records = damage_bytes.items },
    };
    var update_bytes: std.ArrayList(u8) = .empty;
    defer update_bytes.deinit(a);
    try protocol.encodeFrameUpdate(a, .{ .header = header, .sections = &sections }, &update_bytes);
    try protocol.encodeEnvelope(a, .{ .flags = protocol.Flags.delta, .message_type = protocol.Message.frame_update, .sequence = 2, .ack_sequence = 0, .session_id = 9, .frame_id = 7, .timestamp_ns = 2 }, update_bytes.items, &sink_bytes);
    try scene.apply(sink_bytes.items[sink_bytes.items.len - (protocol.header_size + update_bytes.items.len) ..]);

    try std.testing.expectEqual(@as(u64, 1), scene.stats.frame_updates);
    try std.testing.expectEqual(@as(usize, 1), scene.windows.items.len);
    try std.testing.expectEqual(@as(usize, 1), scene.rows.items.len);
}

fn createMessage(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    payload_frame: u32,
) ![]u8 {
    return createMessageGeneration(a, sequence, envelope_frame, payload_frame, 1);
}

fn createMessageGeneration(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    payload_frame: u32,
    generation: u32,
) ![]u8 {
    var payload: [8]u8 = undefined;
    std.mem.writeInt(u32, payload[0..4], payload_frame, .little);
    std.mem.writeInt(u32, payload[4..8], generation, .little);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_create,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = 1,
    }, &payload, &message);
    return message.toOwnedSlice(a);
}

fn updateMessage(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    window_frame: u32,
    row_width: i32,
    row_flags: u32,
) ![]u8 {
    const header: protocol.FrameUpdateHeader = .{
        .frame_id = envelope_frame,
        .frame_generation = 1,
        .sequence = sequence,
        .redisplay_generation = 1,
        .logical_x = 0,
        .logical_y = 0,
        .logical_width = 80,
        .logical_height = 60,
        .physical_x = 0,
        .physical_y = 0,
        .physical_width = 80,
        .physical_height = 60,
        .scale = 1,
        .dpi_x = 96,
        .dpi_y = 96,
        .damage_mode = 2,
        .update_cause = 1,
        .coalesced_count = 0,
        .timestamp_ns = 2,
    };
    var windows: std.ArrayList(u8) = .empty;
    defer windows.deinit(a);
    try encodeWindow(a, .{ .id = 100, .frame_id = window_frame, .x = 0, .y = 0, .width = 80, .height = 60 }, &windows);
    var rows: std.ArrayList(u8) = .empty;
    defer rows.deinit(a);
    try encodeRow(a, .{ .window_id = 100, .index = 0, .flags = row_flags, .x = 0, .y = 0, .width = row_width, .height = 10, .ascent = 7, .descent = 3, .baseline = 7, .visible_height = 10 }, &rows);
    var damage: std.ArrayList(u8) = .empty;
    defer damage.deinit(a);
    try encodeRect(a, .{ .x = 0, .y = 0, .width = 80, .height = 60 }, &damage);
    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = windows.items },
        .{ .kind = protocol.SectionKind.rows, .records = rows.items },
        .{ .kind = protocol.SectionKind.damage, .records = damage.items },
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeFrameUpdate(a, .{ .header = header, .sections = &sections }, &payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = protocol.Flags.delta,
        .message_type = protocol.Message.frame_update,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = 2,
    }, payload.items, &message);
    return message.toOwnedSlice(a);
}

fn frameStateMessage(
    a: std.mem.Allocator,
    sequence: u64,
    message_type: u16,
    envelope_frame: u32,
    payload_frame: u32,
    generation: u32,
    state_byte: u8,
) ![]u8 {
    var payload: [12]u8 = undefined;
    std.mem.writeInt(u32, payload[0..4], payload_frame, .little);
    std.mem.writeInt(u32, payload[4..8], generation, .little);
    payload[8] = state_byte;
    @memset(payload[9..12], 0);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = sequence,
    }, &payload, &message);
    return message.toOwnedSlice(a);
}

fn frameTitleMessage(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    payload: protocol.FrameTitlePayload,
) ![]u8 {
    var title_payload: std.ArrayList(u8) = .empty;
    defer title_payload.deinit(a);
    try protocol.encodeFrameTitle(a, payload, &title_payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_title,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = sequence,
    }, title_payload.items, &message);
    return message.toOwnedSlice(a);
}

fn frameAlphaMessage(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    payload: protocol.FrameAlphaPayload,
) ![]u8 {
    var alpha_payload: std.ArrayList(u8) = .empty;
    defer alpha_payload.deinit(a);
    try protocol.encodeFrameAlpha(a, payload, &alpha_payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_alpha,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = sequence,
    }, alpha_payload.items, &message);
    return message.toOwnedSlice(a);
}

fn frameDecorationsMessage(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    payload: protocol.FrameDecorationsPayload,
) ![]u8 {
    var decorations_payload: std.ArrayList(u8) = .empty;
    defer decorations_payload.deinit(a);
    try protocol.encodeFrameDecorations(a, payload, &decorations_payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_decorations,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = sequence,
    }, decorations_payload.items, &message);
    return message.toOwnedSlice(a);
}

fn frameScaleMessage(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    payload: protocol.FrameScalePayload,
) ![]u8 {
    var scale_payload: std.ArrayList(u8) = .empty;
    defer scale_payload.deinit(a);
    try protocol.encodeFrameScale(a, payload, &scale_payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_scale,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = sequence,
    }, scale_payload.items, &message);
    return message.toOwnedSlice(a);
}

fn frameFullscreenMessage(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    payload: protocol.FrameFullscreenPayload,
) ![]u8 {
    var fullscreen_payload: std.ArrayList(u8) = .empty;
    defer fullscreen_payload.deinit(a);
    try protocol.encodeFrameFullscreen(a, payload, &fullscreen_payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_fullscreen,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = sequence,
    }, fullscreen_payload.items, &message);
    return message.toOwnedSlice(a);
}

fn frameMonitorMessage(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    payload: protocol.FrameMonitorPayload,
) ![]u8 {
    var monitor_payload: std.ArrayList(u8) = .empty;
    defer monitor_payload.deinit(a);
    try protocol.encodeFrameMonitor(a, payload, &monitor_payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_monitor,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = sequence,
    }, monitor_payload.items, &message);
    return message.toOwnedSlice(a);
}

fn frameMaximizeMessage(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    payload: protocol.FrameMaximizePayload,
) ![]u8 {
    var maximize_payload: std.ArrayList(u8) = .empty;
    defer maximize_payload.deinit(a);
    try protocol.encodeFrameMaximize(a, payload, &maximize_payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_maximize,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = sequence,
    }, maximize_payload.items, &message);
    return message.toOwnedSlice(a);
}

fn frameSizeHintsMessage(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    payload: protocol.FrameSizeHintsPayload,
) ![]u8 {
    var hints_payload: std.ArrayList(u8) = .empty;
    defer hints_payload.deinit(a);
    try protocol.encodeFrameSizeHints(a, payload, &hints_payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_size_hints,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = sequence,
    }, hints_payload.items, &message);
    return message.toOwnedSlice(a);
}

fn frameZOrderMessage(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    payload: protocol.FrameZOrderPayload,
) ![]u8 {
    var z_order_payload: std.ArrayList(u8) = .empty;
    defer z_order_payload.deinit(a);
    try protocol.encodeFrameZOrder(a, payload, &z_order_payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_z_order,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = sequence,
    }, z_order_payload.items, &message);
    return message.toOwnedSlice(a);
}

fn frameParentMessage(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    payload: protocol.FrameParentPayload,
) ![]u8 {
    var parent_payload: std.ArrayList(u8) = .empty;
    defer parent_payload.deinit(a);
    try protocol.encodeFrameParent(a, payload, &parent_payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_parent,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = sequence,
    }, parent_payload.items, &message);
    return message.toOwnedSlice(a);
}

fn frameGeometryMessage(
    a: std.mem.Allocator,
    sequence: u64,
    envelope_frame: u32,
    payload: protocol.FrameGeometryPayload,
) ![]u8 {
    var geometry_payload: std.ArrayList(u8) = .empty;
    defer geometry_payload.deinit(a);
    try protocol.encodeFrameGeometry(a, payload, &geometry_payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_geometry,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = envelope_frame,
        .timestamp_ns = sequence,
    }, geometry_payload.items, &message);
    return message.toOwnedSlice(a);
}

fn sessionControlMessage(
    a: std.mem.Allocator,
    sequence: u64,
    message_type: u16,
    payload: []const u8,
) ![]u8 {
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .timestamp_ns = sequence,
    }, payload, &message);
    return message.toOwnedSlice(a);
}

test "scene rejects frame ownership geometry and reserved bytes" {
    const a = std.testing.allocator;
    {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(a);
        try encodeWindow(a, .{ .id = 1, .frame_id = 7, .x = 0, .y = 0, .width = 1, .height = 1 }, &out);
        out.items[out.items.len - 1] = 1;
        try std.testing.expectError(Error.InvalidTable, decodeWindow(out.items));
    }
    {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(a);
        try encodeRow(a, .{ .window_id = 1, .index = 0, .flags = 0, .x = 0, .y = 0, .width = 1, .height = 1, .ascent = 1, .descent = 0, .baseline = 1, .visible_height = 1 }, &out);
        out.items[out.items.len - 1] = 1;
        try std.testing.expectError(Error.InvalidTable, decodeRow(out.items));
    }
    {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(a);
        try encodeCursor(a, .{ .window_id = 1, .x = 0, .y = 0, .width = 1, .height = 1, .kind = 0, .visible = true, .active = true }, &out);
        out.items[out.items.len - 1] = 1;
        try std.testing.expectError(Error.InvalidTable, decodeCursor(out.items));
    }

    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 2, 1);
    defer a.free(create);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(create));

    const owned_create = try createMessage(a, 1, 7, 7);
    defer a.free(owned_create);
    try scene.apply(owned_create);
    const mismatch = try updateMessage(a, 2, 7, 8, 10, 0);
    defer a.free(mismatch);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(mismatch));
    const outside = try updateMessage(a, 2, 7, 7, 90, 0);
    defer a.free(outside);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(outside));
    const flagged = try updateMessage(a, 2, 7, 7, 10, 1);
    defer a.free(flagged);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(flagged));
    try std.testing.expectEqual(@as(u64, 0), scene.stats.frame_updates);
    try std.testing.expectEqual(@as(u64, 2), scene.next_sequence.?);
}

test "scene owns geometry and enforces sequence and frame identity" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    const geometry = protocol.FrameGeometryPayload{
        .frame_generation = 1,
        .outer = .{ .x = 0, .y = 0, .width = 248, .height = 104 },
        .content = .{ .x = 4, .y = 4, .width = 240, .height = 96 },
        .text = .{ .x = 4, .y = 4, .width = 240, .height = 96 },
        .window = .{ .x = 4, .y = 4, .width = 240, .height = 96 },
        .body = .{ .x = 4, .y = 4, .width = 240, .height = 96 },
    };
    const wrong_envelope = try frameGeometryMessage(a, 2, 8, geometry);
    defer a.free(wrong_envelope);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_envelope));

    const wrong_generation = try frameGeometryMessage(a, 2, 7, b: {
        var payload = geometry;
        payload.frame_generation = 2;
        break :b payload;
    });
    defer a.free(wrong_generation);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_generation));
    try std.testing.expectEqual(@as(u64, 2), scene.next_sequence.?);

    const future = try frameGeometryMessage(a, 4, 7, geometry);
    defer a.free(future);
    try std.testing.expectError(Error.InvalidSequence, scene.apply(future));

    const geometry_message = try frameGeometryMessage(a, 2, 7, geometry);
    defer a.free(geometry_message);
    try scene.apply(geometry_message);
    try std.testing.expectEqual(geometry, scene.geometry.?);
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);

    var destroy: [8]u8 = undefined;
    std.mem.writeInt(u32, destroy[0..4], 7, .little);
    std.mem.writeInt(u32, destroy[4..8], 1, .little);
    var destroy_message: std.ArrayList(u8) = .empty;
    defer destroy_message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_destroy,
        .sequence = 3,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = 3,
    }, &destroy, &destroy_message);
    try scene.apply(destroy_message.items);
    try std.testing.expect(scene.geometry == null);
}

test "scene replacement is allocation atomic" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);
    const first = try updateMessage(a, 2, 7, 7, 10, 0);
    defer a.free(first);
    try scene.apply(first);

    const second = try updateMessage(a, 3, 7, 7, 11, 0);
    defer a.free(second);
    var successful = false;
    for (0..64) |fail_index| {
        var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = fail_index });
        scene.allocator = failing.allocator();
        if (scene.apply(second)) {
            successful = true;
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expectEqual(@as(u64, 1), scene.stats.frame_updates);
            try std.testing.expectEqual(@as(i32, 10), scene.rows.items[0].width);
        }
        scene.allocator = a;
    }
    scene.allocator = a;
    try std.testing.expect(successful);
    try std.testing.expectEqual(@as(i32, 11), scene.rows.items[0].width);
}

test "resync reset allows a coherent scene replay" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);
    const first = try updateMessage(a, 2, 7, 7, 10, 0);
    defer a.free(first);
    try scene.apply(first);
    try std.testing.expectEqual(@as(u64, 1), scene.stats.frame_updates);

    scene.resetForResync();
    try std.testing.expectEqual(@as(u64, 0), scene.stats.frame_updates);
    try scene.apply(create);
    try scene.apply(first);
    try std.testing.expectEqual(@as(u64, 1), scene.stats.frame_updates);
}

test "text codecs accept bounded UTF-8 and reject malformed input" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try std.testing.expectError(Error.InvalidTable, decodeTextInput(bytes.items));
    try std.testing.expectError(Error.InvalidTable, encodeTextInput(a, .{ .text = "" }, &bytes));
    try encodeTextInput(a, .{ .text = "X" }, &bytes);
    const decoded = try decodeTextInput(bytes.items);
    try std.testing.expectEqualStrings("X", decoded.text);
    bytes.clearRetainingCapacity();
    try encodeTextInput(a, .{ .text = "你好é\u{0301}" }, &bytes);
    const unicode = try decodeTextInput(bytes.items);
    try std.testing.expectEqualStrings("你好é\u{0301}", unicode.text);
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeTextInput(bytes.items));

    var invalid: std.ArrayList(u8) = .empty;
    defer invalid.deinit(a);
    try invalid.appendSlice(a, &.{ 1, 0, 0, 0, 0 });
    try std.testing.expectError(Error.InvalidTable, decodeTextInput(invalid.items));

    const oversized = "a" ** 121;
    try std.testing.expectError(Error.InvalidTable, encodeTextInput(a, .{ .text = oversized[0..] }, &bytes));
}

fn glyphRunMessage(
    a: std.mem.Allocator,
    sequence: u64,
    generation: u32,
    text: []const u8,
) ![]u8 {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeGlyphRun(a, .{
        .run_id = 9,
        .generation = generation,
        .window_id = 100,
        .row_index = 0,
        .x = 1,
        .y = 2,
        .width = 20,
        .height = 8,
        .text = text,
    }, &payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = protocol.Flags.debug,
        .message_type = protocol.Message.glyph_run,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = sequence,
    }, payload.items, &message);
    return message.toOwnedSlice(a);
}

fn windowTreeMessage(a: std.mem.Allocator, sequence: u64, payload: []const u8) ![]u8 {
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.window_tree_snapshot,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = sequence,
    }, payload, &message);
    return message.toOwnedSlice(a);
}

fn faceBoundGlyphRunMessage(
    a: std.mem.Allocator,
    sequence: u64,
    generation: u32,
    face_id: u32,
    face_generation: u32,
    text: []const u8,
) ![]u8 {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeGlyphRun(a, .{
        .schema = 2,
        .run_id = 9,
        .generation = generation,
        .window_id = 100,
        .row_index = 0,
        .face_id = face_id,
        .face_generation = face_generation,
        .x = 1,
        .y = 2,
        .width = 20,
        .height = 8,
        .text = text,
    }, &payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = protocol.Flags.debug,
        .message_type = protocol.Message.glyph_run,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = sequence,
    }, payload.items, &message);
    return message.toOwnedSlice(a);
}

fn glyphRunDeleteMessage(
    a: std.mem.Allocator,
    sequence: u64,
    delete: GlyphRunDeleteWire,
) ![]u8 {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try encodeGlyphRunDelete(a, delete, &payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = protocol.Flags.debug,
        .message_type = protocol.Message.glyph_run_delete,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = sequence,
    }, payload.items, &message);
    return message.toOwnedSlice(a);
}

test "glyph run debug fallback codec is exact and bounded" {
    const a = std.testing.allocator;
    var wire: std.ArrayList(u8) = .empty;
    defer wire.deinit(a);
    try encodeGlyphRun(a, .{
        .run_id = 9,
        .generation = 2,
        .window_id = 100,
        .row_index = 0,
        .x = 1,
        .y = 2,
        .width = 20,
        .height = 8,
        .text = "Emacs text",
    }, &wire);
    try std.testing.expectEqual(glyph_record_size + 10, wire.items.len);
    const decoded = try decodeGlyphRun(wire.items);
    try std.testing.expectEqual(@as(u16, 1), decoded.schema);
    try std.testing.expectEqual(@as(u16, 1), decoded.direction);
    try std.testing.expectEqual(glyph_debug_fallback, decoded.flags);
    try std.testing.expectEqualStrings("Emacs text", decoded.text);
    try wire.append(a, 0);
    try std.testing.expectError(Error.InvalidMessage, decodeGlyphRun(wire.items));
}

test "glyph run delete codec is exact identity-shaped" {
    const a = std.testing.allocator;
    var wire: std.ArrayList(u8) = .empty;
    defer wire.deinit(a);
    try encodeGlyphRunDelete(a, .{ .run_id = 9, .generation = 3, .window_id = 100, .row_index = 4 }, &wire);
    try std.testing.expectEqual(glyph_delete_record_size, wire.items.len);
    const decoded = try decodeGlyphRunDelete(wire.items);
    try std.testing.expectEqual(@as(u32, 9), decoded.run_id);
    try std.testing.expectEqual(@as(u32, 3), decoded.generation);
    try std.testing.expectEqual(@as(u64, 100), decoded.window_id);
    try std.testing.expectEqual(@as(u32, 4), decoded.row_index);

    try wire.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeGlyphRunDelete(wire.items));
    wire.items[wire.items.len - 1] = 1;
    wire.items[20] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeGlyphRunDelete(wire.items[0..24]));
    wire.items[20] = 0;

    try std.testing.expectError(Error.InvalidMessage, encodeGlyphRunDelete(a, .{ .run_id = 0, .generation = 3, .window_id = 100, .row_index = 0 }, &wire));
    try std.testing.expectError(Error.InvalidMessage, encodeGlyphRunDelete(a, .{ .run_id = 9, .generation = 0, .window_id = 100, .row_index = 0 }, &wire));
    try std.testing.expectError(Error.InvalidMessage, encodeGlyphRunDelete(a, .{ .run_id = 9, .generation = 3, .window_id = 0, .row_index = 0 }, &wire));
}

const default_glyph_delete: GlyphRunDeleteWire = .{
    .run_id = 9,
    .generation = 2,
    .window_id = 100,
    .row_index = 0,
};

fn windowLifecycleMessage(a: std.mem.Allocator, message_type: u16, sequence: u64, frame_id: u32, payload: []const u8) ![]u8 {
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{ .flags = 0, .message_type = message_type, .sequence = sequence, .ack_sequence = 0, .session_id = 9, .frame_id = frame_id, .timestamp_ns = sequence }, payload, &message);
    return message.toOwnedSlice(a);
}

fn windowCreateMessage(a: std.mem.Allocator, sequence: u64, frame_id: u32, node: protocol.WindowTreeNode) ![]u8 {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeWindowCreate(a, .{ .frame_id = frame_id, .frame_generation = 1, .node = node }, &payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{ .flags = 0, .message_type = protocol.Message.window_create, .sequence = sequence, .ack_sequence = 0, .session_id = 9, .frame_id = frame_id, .timestamp_ns = sequence }, payload.items, &message);
    return message.toOwnedSlice(a);
}

fn windowDeleteMessage(a: std.mem.Allocator, sequence: u64, frame_id: u32, window_id: u64) ![]u8 {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeWindowDelete(a, .{ .frame_id = frame_id, .frame_generation = 1, .window_id = window_id }, &payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{ .flags = 0, .message_type = protocol.Message.window_delete, .sequence = sequence, .ack_sequence = 0, .session_id = 9, .frame_id = frame_id, .timestamp_ns = sequence }, payload.items, &message);
    return message.toOwnedSlice(a);
}

test "scene applies and deletes standalone window lifecycle messages" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create_frame = try createMessage(a, 1, 7, 7);
    defer a.free(create_frame);
    try scene.apply(create_frame);

    const create = try windowCreateMessage(a, 2, 7, .{ .window_id = 900, .parent_window_id = 0, .x = 0, .y = 0, .width = 40, .height = 20, .flags = 2, .default_face_id = 0, .depth = 0 });
    defer a.free(create);
    try scene.apply(create);
    try std.testing.expectEqual(@as(usize, 1), scene.windows.items.len);
    try std.testing.expectEqual(@as(u64, 900), scene.windows.items[0].id);

    const duplicate = try windowCreateMessage(a, 3, 7, .{ .window_id = 900, .parent_window_id = 0, .x = 0, .y = 0, .width = 30, .height = 20, .flags = 2, .default_face_id = 0, .depth = 0 });
    defer a.free(duplicate);
    try std.testing.expectError(Error.InvalidTable, scene.apply(duplicate));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);

    const child = try windowCreateMessage(a, 3, 7, .{ .window_id = 901, .parent_window_id = 900, .x = 0, .y = 0, .width = 30, .height = 20, .flags = 2, .default_face_id = 0, .depth = 1 });
    defer a.free(child);
    try scene.apply(child);
    try std.testing.expectEqual(@as(u64, 0), scene.windows.items[0].parent_id);
    try std.testing.expectEqual(@as(u64, 901), scene.windows.items[1].id);
    try std.testing.expectEqual(@as(u64, 900), scene.windows.items[1].parent_id);

    const parent_delete = try windowDeleteMessage(a, 4, 7, 900);
    defer a.free(parent_delete);
    try std.testing.expectError(Error.ResourceNotLive, scene.apply(parent_delete));

    const child_delete = try windowDeleteMessage(a, 4, 7, 901);
    defer a.free(child_delete);
    try scene.apply(child_delete);
    const delete = try windowDeleteMessage(a, 5, 7, 900);
    defer a.free(delete);
    try scene.apply(delete);
    try std.testing.expectEqual(@as(usize, 0), scene.windows.items.len);
    const missing_delete = try windowDeleteMessage(a, 6, 7, 900);
    defer a.free(missing_delete);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(missing_delete));
}

test "window lifecycle is rejected while session is suspended" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create_frame = try createMessage(a, 1, 7, 7);
    defer a.free(create_frame);
    try scene.apply(create_frame);

    var suspend_payload: std.ArrayList(u8) = .empty;
    defer suspend_payload.deinit(a);
    try session.encodeSuspend(a, .{ .reason = .transport_pressure }, &suspend_payload);
    var suspend_message: std.ArrayList(u8) = .empty;
    defer suspend_message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.session_suspend,
        .sequence = 2,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 0,
        .timestamp_ns = 2,
    }, suspend_payload.items, &suspend_message);
    try scene.apply(suspend_message.items);

    const create = try windowCreateMessage(a, 3, 7, .{ .window_id = 900, .parent_window_id = 0, .x = 0, .y = 0, .width = 40, .height = 20, .flags = 2, .default_face_id = 0, .depth = 0 });
    defer a.free(create);
    try std.testing.expectError(Error.SessionSuspended, scene.apply(create));
}

test "scene patches window geometry parent and visibility" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create_frame = try createMessage(a, 1, 7, 7);
    defer a.free(create_frame);
    try scene.apply(create_frame);

    const root = try windowCreateMessage(a, 2, 7, .{ .window_id = 900, .parent_window_id = 0, .x = 0, .y = 0, .width = 40, .height = 20, .flags = 2, .default_face_id = 0, .depth = 0 });
    defer a.free(root);
    try scene.apply(root);
    const child = try windowCreateMessage(a, 3, 7, .{ .window_id = 901, .parent_window_id = 900, .x = 0, .y = 0, .width = 30, .height = 20, .flags = 2, .default_face_id = 0, .depth = 1 });
    defer a.free(child);
    try scene.apply(child);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeWindowPatch(a, .{
        .flags = protocol.WindowPatchFlags.x | protocol.WindowPatchFlags.y |
            protocol.WindowPatchFlags.width | protocol.WindowPatchFlags.height |
            protocol.WindowPatchFlags.visible | protocol.WindowPatchFlags.default_face,
        .frame_id = 7,
        .frame_generation = 1,
        .window_id = 901,
        .x = 2,
        .y = 3,
        .width = 20,
        .height = 10,
        .visible = false,
        .default_face_id = 8,
    }, &payload);
    const patch = try windowLifecycleMessage(a, protocol.Message.window_patch, 4, 7, payload.items);
    defer a.free(patch);
    try scene.apply(patch);
    try std.testing.expectEqual(@as(i32, 2), scene.windows.items[1].x);
    try std.testing.expectEqual(false, scene.windows.items[1].visible);
    try std.testing.expectEqual(@as(u32, 8), scene.windows.items[1].default_face_id);

    payload.clearRetainingCapacity();
    const cycle = try protocol.encodeWindowPatch(a, .{
        .flags = protocol.WindowPatchFlags.parent,
        .frame_id = 7,
        .frame_generation = 1,
        .window_id = 900,
        .parent_window_id = 901,
    }, &payload);
    _ = cycle;
    const invalid_patch = try windowLifecycleMessage(a, protocol.Message.window_patch, 5, 7, payload.items);
    defer a.free(invalid_patch);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(invalid_patch));
}

test "scene applies and validates window tree snapshot" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    const nodes = [_]protocol.WindowTreeNode{
        .{ .window_id = 10, .parent_window_id = 0, .x = 0, .y = 0, .width = 80, .height = 60, .flags = protocol.window_tree_flag_visible, .default_face_id = 0, .depth = 0 },
        .{ .window_id = 11, .parent_window_id = 10, .x = 40, .y = 0, .width = 40, .height = 60, .flags = protocol.window_tree_flag_visible | protocol.window_tree_flag_selected, .default_face_id = 3, .depth = 1 },
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeWindowTreeSnapshot(a, .{
        .header = .{ .frame_id = 7, .frame_generation = 1, .selected_window_id = 11, .root_window_id = 10 },
        .nodes = &nodes,
    }, &payload);
    const snapshot = try windowTreeMessage(a, 2, payload.items);
    defer a.free(snapshot);
    try scene.apply(snapshot);
    try std.testing.expect(scene.window_tree != null);
    try std.testing.expectEqual(@as(u32, 11), scene.window_tree.?.header.selected_window_id);
}

test "face bound glyph run validates resource and face generation" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var face_payload: std.ArrayList(u8) = .empty;
    defer face_payload.deinit(a);
    try protocol.encodeFaceDefine(a, .{ .face_id = 11, .generation = 2 }, &face_payload);
    const face_defined = try faceMessage(a, protocol.Message.face_define, 3, face_payload.items);
    defer a.free(face_defined);
    try scene.apply(face_defined);

    var bound_payload: std.ArrayList(u8) = .empty;
    defer bound_payload.deinit(a);
    try encodeGlyphRun(a, .{
        .schema = 2,
        .run_id = 9,
        .generation = 2,
        .window_id = 100,
        .row_index = 0,
        .face_id = 11,
        .face_generation = 2,
        .x = 1,
        .y = 2,
        .width = 20,
        .height = 8,
        .text = "Emacs",
    }, &bound_payload);
    const bound = try faceBoundGlyphRunMessage(a, 4, 2, 11, 2, "Emacs");
    defer a.free(bound);
    try scene.apply(bound);
    try std.testing.expectEqual(@as(usize, 1), scene.glyph_runs.items.len);
    try std.testing.expectEqual(@as(u32, 11), scene.glyph_runs.items[0].face_id);

    var stale_payload: std.ArrayList(u8) = .empty;
    defer stale_payload.deinit(a);
    try encodeGlyphRun(a, .{
        .schema = 2,
        .run_id = 9,
        .generation = 3,
        .window_id = 100,
        .row_index = 0,
        .face_id = 11,
        .face_generation = 1,
        .x = 1,
        .y = 2,
        .width = 20,
        .height = 8,
        .text = "stale",
    }, &stale_payload);
    const stale = try faceBoundGlyphRunMessage(a, 5, 3, 11, 1, "stale");
    defer a.free(stale);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(stale));
}

test "scene validates glyph context and replaces by strictly newer generation" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const first = try glyphRunMessage(a, 3, 2, "Emacs");
    defer a.free(first);
    try scene.apply(first);
    try std.testing.expectEqual(@as(usize, 1), scene.glyph_runs.items.len);
    try std.testing.expectEqualStrings("Emacs", scene.glyph_runs.items[0].text);

    const equal = try glyphRunMessage(a, 4, 2, "stale");
    defer a.free(equal);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(equal));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);
    try std.testing.expectEqualStrings("Emacs", scene.glyph_runs.items[0].text);

    const replacement = try glyphRunMessage(a, 4, 3, "replacement");
    defer a.free(replacement);
    try scene.apply(replacement);
    try std.testing.expectEqualStrings("replacement", scene.glyph_runs.items[0].text);

    const next_update = try updateMessage(a, 5, 7, 7, 80, 0);
    defer a.free(next_update);
    try scene.apply(next_update);
    try std.testing.expectEqual(@as(usize, 0), scene.glyph_runs.items.len);
}

test "glyph run delete requires exact identity and advances only on success" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    const run = try glyphRunMessage(a, 3, 2, "Emacs");
    defer a.free(run);
    try scene.apply(run);
    const control_after_run = scene.stats.control_messages;

    const stale = try glyphRunDeleteMessage(a, 4, .{ .generation = 1, .run_id = 9, .window_id = 100, .row_index = 0 });
    defer a.free(stale);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(stale));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const wrong_run = try glyphRunDeleteMessage(a, 4, .{ .run_id = 10, .generation = 2, .window_id = 100, .row_index = 0 });
    defer a.free(wrong_run);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_run));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const wrong_row = try glyphRunDeleteMessage(a, 4, .{ .run_id = 9, .generation = 2, .window_id = 100, .row_index = 1 });
    defer a.free(wrong_row);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_row));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const exact = try glyphRunDeleteMessage(a, 4, default_glyph_delete);
    defer a.free(exact);
    try scene.apply(exact);
    try std.testing.expectEqual(@as(u64, 5), scene.next_sequence.?);
    try std.testing.expectEqual(control_after_run + 1, scene.stats.control_messages);
    try std.testing.expectEqual(@as(usize, 0), scene.glyph_runs.items.len);

    const missing = try glyphRunDeleteMessage(a, 5, default_glyph_delete);
    defer a.free(missing);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(missing));
    try std.testing.expectEqual(@as(u64, 5), scene.next_sequence.?);
}

test "key event codec validates bounded editing actions" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeKeyEvent(a, .{ .action = .backspace }, &bytes);
    const decoded = try decodeKeyEvent(bytes.items);
    try std.testing.expectEqual(KeyAction.backspace, decoded.action);
    try std.testing.expectEqual(@as(u8, 1), bytes.items[0]);
    try std.testing.expectEqual(@as(u8, 1), decoded.state);
    try std.testing.expectEqual(@as(u8, 0), decoded.modifiers);

    try std.testing.expectError(Error.InvalidTable, decodeKeyEvent(bytes.items[0..3]));
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeKeyEvent(bytes.items));
    try std.testing.expectError(Error.Unsupported, encodeKeyEvent(a, .{ .action = .backspace, .state = 0 }, &bytes));
    try std.testing.expectError(Error.Unsupported, encodeKeyEvent(a, .{ .action = .backspace, .modifiers = 1 }, &bytes));

    bytes.clearRetainingCapacity();
    try encodeKeyEvent(a, .{ .action = .copy }, &bytes);
    try std.testing.expectEqual(KeyAction.copy, (try decodeKeyEvent(bytes.items)).action);
    try std.testing.expectEqual(@as(u8, 6), bytes.items[0]);
    bytes.items[2] = 0;
    try std.testing.expectError(Error.Unsupported, decodeKeyEvent(bytes.items));
    bytes.items[2] = 1;
    bytes.items[3] = 1;
    try std.testing.expectError(Error.Unsupported, decodeKeyEvent(bytes.items));

    var invalid: std.ArrayList(u8) = .empty;
    defer invalid.deinit(a);
    try invalid.appendSlice(a, &.{ 99, 0, 1, 0 });
    try std.testing.expectError(Error.InvalidTable, decodeKeyEvent(invalid.items));
    invalid.items[0] = 1;
    invalid.items[2] = 0;
    try std.testing.expectError(Error.Unsupported, decodeKeyEvent(invalid.items));
    invalid.items[2] = 1;
    invalid.items[3] = 1;
    try std.testing.expectError(Error.Unsupported, decodeKeyEvent(invalid.items));
}

test "pointer codec validates bounded facts-profile events" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    try encodePointerInput(a, .{ .phase = .motion, .x = 12, .y = 4 }, &bytes);
    var decoded = try decodePointerInput(bytes.items);
    try std.testing.expectEqual(PointerPhase.motion, decoded.phase);
    try std.testing.expectEqual(@as(i32, 12), decoded.x);
    try std.testing.expectEqual(@as(i32, 4), decoded.y);

    bytes.clearRetainingCapacity();
    try encodePointerInput(a, .{ .phase = .press, .button = 1, .x = 120, .y = 2, .clicks = 1 }, &bytes);
    decoded = try decodePointerInput(bytes.items);
    try std.testing.expectEqual(PointerPhase.press, decoded.phase);
    try std.testing.expectEqual(@as(u8, 1), decoded.button);

    bytes.items[0] = 4;
    try std.testing.expectError(Error.InvalidTable, decodePointerInput(bytes.items));
    try std.testing.expectError(Error.Unsupported, encodePointerInput(a, .{ .phase = .press, .x = -1, .y = 0, .button = 1, .clicks = 1 }, &bytes));
    try std.testing.expectError(Error.Unsupported, encodePointerInput(a, .{ .phase = .motion, .x = 0, .y = 0, .button = 2 }, &bytes));
}

test "wheel codec accepts only bounded line wheel ticks" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    try encodeWheelInput(a, .{ .y = -1 }, &bytes);
    const decoded = try decodeWheelInput(bytes.items);
    try std.testing.expectEqual(@as(i8, -1), decoded.y);
    try std.testing.expectEqual(WheelUnit.line, decoded.unit);
    try std.testing.expectEqual(WheelSource.wheel, decoded.source);

    bytes.clearRetainingCapacity();
    try encodeWheelInput(a, .{ .y = 1 }, &bytes);
    try std.testing.expectEqual(@as(i8, 1), (try decodeWheelInput(bytes.items)).y);
    try std.testing.expectError(Error.Unsupported, encodeWheelInput(a, .{ .y = 0 }, &bytes));
    try std.testing.expectError(Error.Unsupported, encodeWheelInput(a, .{ .y = max_wheel_ticks + 1 }, &bytes));
    try std.testing.expectError(Error.Unsupported, encodeWheelInput(a, .{ .x = 1, .y = 1 }, &bytes));
    bytes.items[5] = 1;
    try std.testing.expectError(Error.Unsupported, decodeWheelInput(bytes.items));
}

test "key event codec round trips bounded cursor actions" {
    const a = std.testing.allocator;
    inline for ([_]KeyAction{ .cursor_left, .cursor_right, .cursor_up, .cursor_down }) |action| {
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(a);
        try encodeKeyEvent(a, .{ .action = action }, &bytes);
        const decoded = try decodeKeyEvent(bytes.items);
        try std.testing.expectEqual(action, decoded.action);
    }
}

test "scene applies frame destroy and clears owned visual state" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);
    const update = try updateMessage(a, 2, 7, 7, 10, 0);
    defer a.free(update);
    try scene.apply(update);

    var destroy: [8]u8 = undefined;
    std.mem.writeInt(u32, destroy[0..4], 7, .little);
    std.mem.writeInt(u32, destroy[4..8], 1, .little);
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(a);
    try protocol.encodeEnvelope(a, .{ .flags = 0, .message_type = protocol.Message.frame_destroy, .sequence = 3, .ack_sequence = 0, .session_id = 9, .frame_id = 7, .timestamp_ns = 3 }, &destroy, &message);
    try scene.apply(message.items);

    try std.testing.expectEqual(lifecycle.FrameStatus.destroyed, scene.frames.frames[0].status);
    try std.testing.expect(scene.frame == null);
    try std.testing.expectEqual(@as(usize, 0), scene.windows.items.len);
    try std.testing.expect(scene.frame_header == null);
}

test "scene rejects second active frame and noninitial generation" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const bad_create = try createMessageGeneration(a, 1, 7, 7, 2);
    defer a.free(bad_create);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(bad_create));

    const good_create = try createMessage(a, 1, 7, 7);
    defer a.free(good_create);
    try scene.apply(good_create);

    const second = try createMessage(a, 2, 8, 8);
    defer a.free(second);
    try std.testing.expectError(Error.FrameAlreadyExists, scene.apply(second));
    try std.testing.expectEqual(@as(u32, 7), scene.frame.?.frame_id);
    try std.testing.expectEqual(@as(u64, 2), scene.next_sequence.?);
}

test "scene applies visibility and focus against the active frame" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);
    const update = try updateMessage(a, 2, 7, 7, 10, 0);
    defer a.free(update);
    try scene.apply(update);
    try std.testing.expectEqual(lifecycle.FrameVisibility.visible, scene.frames.frames[0].visibility);

    const hidden = try frameStateMessage(a, 3, protocol.Message.frame_visibility, 7, 7, 1, 0);
    defer a.free(hidden);
    try scene.apply(hidden);
    try std.testing.expectEqual(lifecycle.FrameVisibility.hidden, scene.frames.frames[0].visibility);
    try std.testing.expectEqual(false, scene.frames.frames[0].focused);

    const hidden_focus = try frameStateMessage(a, 4, protocol.Message.frame_focus, 7, 7, 1, 1);
    defer a.free(hidden_focus);
    try std.testing.expectError(Error.FrameNotVisible, scene.apply(hidden_focus));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const visible = try frameStateMessage(a, 4, protocol.Message.frame_visibility, 7, 7, 1, 1);
    defer a.free(visible);
    try scene.apply(visible);
    const focus = try frameStateMessage(a, 5, protocol.Message.frame_focus, 7, 7, 1, 1);
    defer a.free(focus);
    try scene.apply(focus);
    try std.testing.expectEqual(true, scene.frames.frames[0].focused);
    try std.testing.expectEqual(@as(u64, 4), scene.stats.control_messages);

    const stale = try frameStateMessage(a, 6, protocol.Message.frame_visibility, 7, 7, 2, 0);
    defer a.free(stale);
    try std.testing.expectError(Error.FrameNotActive, scene.apply(stale));

    const mismatched = try frameStateMessage(a, 6, protocol.Message.frame_visibility, 8, 7, 1, 0);
    defer a.free(mismatched);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(mismatched));

    var destroy_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, destroy_payload[0..4], 7, .little);
    std.mem.writeInt(u32, destroy_payload[4..8], 1, .little);
    var destroy: std.ArrayList(u8) = .empty;
    defer destroy.deinit(a);
    try protocol.encodeEnvelope(a, .{ .flags = 0, .message_type = protocol.Message.frame_destroy, .sequence = 6, .ack_sequence = 0, .session_id = 9, .frame_id = 7, .timestamp_ns = 6 }, &destroy_payload, &destroy);
    try scene.apply(destroy.items);
    try std.testing.expectEqual(lifecycle.FrameVisibility.hidden, scene.frames.frames[0].visibility);
    try std.testing.expectEqual(false, scene.frames.frames[0].focused);
    try std.testing.expectEqual(lifecycle.FrameStatus.destroyed, scene.frames.frames[0].status);
}

test "scene applies frame patch atomically to bounded frame state" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeFramePatch(a, .{
        .presence = protocol.FramePatchFlags.visibility |
            protocol.FramePatchFlags.focus | protocol.FramePatchFlags.alpha |
            protocol.FramePatchFlags.decorations | protocol.FramePatchFlags.scale,
        .frame_generation = 1,
        .visibility = .visible,
        .focused = true,
        .decorated = false,
        .active_opacity = 9000,
        .inactive_opacity = 7000,
        .background_opacity = 9500,
    }, &payload);
    {
        const patch = try windowLifecycleMessage(a, protocol.Message.frame_patch, 3, 7, payload.items);
        defer a.free(patch);
        try scene.apply(patch);
    }
    try std.testing.expectEqual(lifecycle.FrameVisibility.visible, scene.frames.frames[0].visibility);
    try std.testing.expectEqual(true, scene.frames.frames[0].focused);
    try std.testing.expectEqual(@as(u16, 9000), scene.alpha.?.active_opacity);
    try std.testing.expectEqual(false, scene.decorations.?.decorated);
    try std.testing.expectEqual(@as(f32, 1), scene.scale.?.scale);

    payload.clearRetainingCapacity();
    try protocol.encodeFramePatch(a, .{
        .presence = protocol.FramePatchFlags.alpha,
        .frame_generation = 2,
        .active_opacity = 1000,
        .inactive_opacity = 1000,
        .background_opacity = 1000,
    }, &payload);
    {
        const stale = try windowLifecycleMessage(a, protocol.Message.frame_patch, 4, 7, payload.items);
        defer a.free(stale);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(stale));
    }
    try std.testing.expectEqual(@as(u16, 9000), scene.alpha.?.active_opacity);

    payload.clearRetainingCapacity();
    try protocol.encodeFramePatch(a, .{
        .presence = protocol.FramePatchFlags.alpha,
        .frame_generation = 1,
        .active_opacity = 5000,
        .inactive_opacity = 4000,
        .background_opacity = 6000,
    }, &payload);
    {
        const alpha_only = try windowLifecycleMessage(a, protocol.Message.frame_patch, 4, 7, payload.items);
        defer a.free(alpha_only);
        try scene.apply(alpha_only);
    }
    try std.testing.expectEqual(@as(u16, 5000), scene.alpha.?.active_opacity);
    try std.testing.expectEqual(false, scene.decorations.?.decorated);

    const iconified = try frameStateMessage(a, 5, protocol.Message.frame_visibility, 7, 7, 1, 2);
    defer a.free(iconified);
    try scene.apply(iconified);

    payload.clearRetainingCapacity();
    try protocol.encodeFramePatch(a, .{
        .presence = protocol.FramePatchFlags.alpha | protocol.FramePatchFlags.focus,
        .frame_generation = 1,
        .focused = true,
        .active_opacity = 1000,
        .inactive_opacity = 1000,
        .background_opacity = 1000,
    }, &payload);
    {
        const rejected = try windowLifecycleMessage(a, protocol.Message.frame_patch, 6, 7, payload.items);
        defer a.free(rejected);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(rejected));
    }
    try std.testing.expectEqual(@as(u16, 5000), scene.alpha.?.active_opacity);
    try std.testing.expectEqual(lifecycle.FrameVisibility.iconified, scene.frames.frames[0].visibility);
    try std.testing.expectEqual(false, scene.frames.frames[0].focused);

    try std.testing.expectError(Error.InvalidMessage, protocol.encodeFramePatch(a, .{
        .presence = protocol.FramePatchFlags.visibility | protocol.FramePatchFlags.focus,
        .frame_generation = 1,
        .visibility = .hidden,
        .focused = true,
    }, &payload));
    try std.testing.expectEqual(false, scene.frames.frames[0].focused);

    payload.clearRetainingCapacity();
    try protocol.encodeFramePatch(a, .{
        .presence = protocol.FramePatchFlags.visibility,
        .frame_generation = 1,
        .visibility = .hidden,
    }, &payload);
    {
        const hidden = try windowLifecycleMessage(a, protocol.Message.frame_patch, 6, 7, payload.items);
        defer a.free(hidden);
        try scene.apply(hidden);
    }
    try std.testing.expectEqual(lifecycle.FrameVisibility.hidden, scene.frames.frames[0].visibility);
    try std.testing.expectEqual(false, scene.frames.frames[0].focused);
}

test "scene applies complete bounded frame snapshot atomically" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    {
        const hidden = try frameStateMessage(a, 3, protocol.Message.frame_visibility, 7, 7, 1, 0);
        defer a.free(hidden);
        try scene.apply(hidden);
    }
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeFramePatch(a, .{
        .presence = protocol.FramePatchFlags.alpha |
            protocol.FramePatchFlags.decorations | protocol.FramePatchFlags.scale,
        .frame_generation = 1,
        .active_opacity = 1000,
        .inactive_opacity = 2000,
        .background_opacity = 3000,
        .decorated = true,
        .scale = 2,
        .dpi_x = 144,
        .dpi_y = 120,
    }, &payload);
    {
        const old_patch = try windowLifecycleMessage(a, protocol.Message.frame_patch, 4, 7, payload.items);
        defer a.free(old_patch);
        try scene.apply(old_patch);
    }
    payload.clearRetainingCapacity();
    try protocol.encodeFrameFullscreen(a, .{
        .mode = .fullboth,
        .frame_generation = 1,
    }, &payload);
    {
        const fullscreen = try windowLifecycleMessage(a, protocol.Message.frame_fullscreen, 5, 7, payload.items);
        defer a.free(fullscreen);
        try scene.apply(fullscreen);
    }
    payload.clearRetainingCapacity();
    try protocol.encodeFrameMaximize(a, .{
        .flags = protocol.FrameMaximizeFlags.horizontal,
        .frame_generation = 1,
    }, &payload);
    {
        const maximize = try windowLifecycleMessage(a, protocol.Message.frame_maximize, 6, 7, payload.items);
        defer a.free(maximize);
        try scene.apply(maximize);
    }

    const snapshot: protocol.FrameSnapshot = .{
        .frame_generation = 1,
        .visibility = .visible,
        .focused = true,
        .fullscreen = .none,
        .maximize_flags = protocol.FrameMaximizeFlags.both,
        .decorated = false,
        .active_opacity = 9000,
        .inactive_opacity = 7000,
        .background_opacity = 9500,
        .outer = .{ .x = 0, .y = 0, .width = 100, .height = 100 },
        .content = .{ .x = 4, .y = 4, .width = 92, .height = 92 },
        .text = .{ .x = 4, .y = 4, .width = 92, .height = 92 },
        .window = .{ .x = 4, .y = 4, .width = 92, .height = 92 },
        .body = .{ .x = 8, .y = 8, .width = 80, .height = 80 },
    };
    payload.clearRetainingCapacity();
    try protocol.encodeFrameSnapshot(a, snapshot, &payload);
    {
        const message = try windowLifecycleMessage(a, protocol.Message.frame_snapshot, 7, 7, payload.items);
        defer a.free(message);
        try scene.apply(message);
    }

    try std.testing.expectEqual(lifecycle.FrameVisibility.visible, scene.frames.frames[0].visibility);
    try std.testing.expectEqual(true, scene.frames.frames[0].focused);
    try std.testing.expectEqual(@as(u16, 9000), scene.alpha.?.active_opacity);
    try std.testing.expectEqual(@as(u16, 7000), scene.alpha.?.inactive_opacity);
    try std.testing.expectEqual(@as(u16, 9500), scene.alpha.?.background_opacity);
    try std.testing.expectEqual(false, scene.decorations.?.decorated);
    try std.testing.expectEqual(@as(f32, 1), scene.scale.?.scale);
    try std.testing.expectEqual(@as(f32, 96), scene.scale.?.dpi_x);
    try std.testing.expectEqual(@as(f32, 96), scene.scale.?.dpi_y);
    try std.testing.expectEqual(snapshot.outer, scene.geometry.?.outer);
    try std.testing.expectEqual(snapshot.content, scene.geometry.?.content);
    try std.testing.expectEqual(snapshot.text, scene.geometry.?.text);
    try std.testing.expectEqual(snapshot.window, scene.geometry.?.window);
    try std.testing.expectEqual(snapshot.body, scene.geometry.?.body);
    try std.testing.expectEqual(protocol.FrameFullscreenMode.none, scene.fullscreen.?.mode);
    try std.testing.expectEqual(protocol.FrameMaximizeFlags.both, scene.maximize.?.flags);

    var stale = snapshot;
    stale.frame_generation = 2;
    payload.clearRetainingCapacity();
    try protocol.encodeFrameSnapshot(a, stale, &payload);
    {
        const stale_message = try windowLifecycleMessage(a, protocol.Message.frame_snapshot, 8, 7, payload.items);
        defer a.free(stale_message);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(stale_message));
    }
    try std.testing.expectEqual(lifecycle.FrameVisibility.visible, scene.frames.frames[0].visibility);
    try std.testing.expectEqual(true, scene.frames.frames[0].focused);
    try std.testing.expectEqual(@as(u16, 9000), scene.alpha.?.active_opacity);
    try std.testing.expectEqual(@as(u16, 7000), scene.alpha.?.inactive_opacity);
    try std.testing.expectEqual(@as(u16, 9500), scene.alpha.?.background_opacity);
    try std.testing.expectEqual(false, scene.decorations.?.decorated);
    try std.testing.expectEqual(@as(f32, 1), scene.scale.?.scale);
    try std.testing.expectEqual(@as(f32, 96), scene.scale.?.dpi_x);
    try std.testing.expectEqual(@as(f32, 96), scene.scale.?.dpi_y);
    try std.testing.expectEqual(snapshot.body, scene.geometry.?.body);
    try std.testing.expectEqual(protocol.FrameFullscreenMode.none, scene.fullscreen.?.mode);
    try std.testing.expectEqual(protocol.FrameMaximizeFlags.both, scene.maximize.?.flags);

    scene.resetForResync();
    try std.testing.expectEqual(null, scene.alpha);
    try std.testing.expectEqual(null, scene.decorations);
    try std.testing.expectEqual(null, scene.scale);
    try std.testing.expectEqual(null, scene.geometry);
    try std.testing.expectEqual(null, scene.fullscreen);
    try std.testing.expectEqual(null, scene.maximize);
}
test "scene applies title only for live active-generation strings" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    var string_payload: std.ArrayList(u8) = .empty;
    defer string_payload.deinit(a);
    try protocol.encodeStringDefine(a, .{
        .resource_id = 12,
        .generation = 1,
        .bytes = "Emacs Proto-UI",
    }, &string_payload);
    const string = try stringMessage(a, protocol.Message.string_define, 2, string_payload.items);
    defer a.free(string);
    try scene.apply(string);

    const missing = try frameTitleMessage(a, 3, 7, .{
        .string_resource_id = 40,
        .string_generation = 1,
        .frame_generation = 1,
    });
    defer a.free(missing);
    try std.testing.expectError(Error.ResourceNotLive, scene.apply(missing));

    const title = try frameTitleMessage(a, 3, 7, .{
        .string_resource_id = 12,
        .string_generation = 1,
        .frame_generation = 1,
    });
    defer a.free(title);
    try scene.apply(title);
    try std.testing.expectEqualStrings("Emacs Proto-UI", scene.title.?);
    try std.testing.expectEqual(@as(u64, 3), scene.stats.control_messages);

    const stale = try frameTitleMessage(a, 4, 7, .{
        .string_resource_id = 12,
        .string_generation = 2,
        .frame_generation = 1,
    });
    defer a.free(stale);
    try std.testing.expectError(Error.ResourceNotLive, scene.apply(stale));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const wrong_generation = try frameTitleMessage(a, 4, 7, .{
        .string_resource_id = 12,
        .string_generation = 1,
        .frame_generation = 2,
    });
    defer a.free(wrong_generation);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_generation));

    const wrong_frame = try frameTitleMessage(a, 4, 8, .{
        .string_resource_id = 12,
        .string_generation = 1,
        .frame_generation = 1,
    });
    defer a.free(wrong_frame);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_frame));

    scene.resetForResync();
    try std.testing.expect(scene.title == null);
}

test "scene applies alpha only to the active frame generation" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    const alpha = try frameAlphaMessage(a, 2, 7, .{
        .active_opacity = 8000,
        .inactive_opacity = 6000,
        .background_opacity = 9000,
        .frame_generation = 1,
    });
    defer a.free(alpha);
    try scene.apply(alpha);
    try std.testing.expectEqual(@as(u16, 8000), scene.alpha.?.active_opacity);
    try std.testing.expectEqual(@as(u16, 6000), scene.alpha.?.inactive_opacity);
    try std.testing.expectEqual(@as(u16, 9000), scene.alpha.?.background_opacity);

    const opaque_replacement = try frameAlphaMessage(a, 3, 7, .{
        .active_opacity = 10000,
        .inactive_opacity = 10000,
        .background_opacity = 10000,
        .frame_generation = 1,
    });
    defer a.free(opaque_replacement);
    try scene.apply(opaque_replacement);
    try std.testing.expectEqual(@as(u16, 10000), scene.alpha.?.active_opacity);

    const stale = try frameAlphaMessage(a, 4, 7, .{
        .active_opacity = 0,
        .inactive_opacity = 0,
        .background_opacity = 0,
        .frame_generation = 2,
    });
    defer a.free(stale);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(stale));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const wrong_frame = try frameAlphaMessage(a, 4, 8, .{
        .active_opacity = 0,
        .inactive_opacity = 0,
        .background_opacity = 0,
        .frame_generation = 1,
    });
    defer a.free(wrong_frame);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_frame));

    scene.resetForResync();
    try std.testing.expect(scene.alpha == null);
}

test "scene applies decorations only to the active frame generation" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    const undecorated = try frameDecorationsMessage(a, 2, 7, .{
        .decorated = false,
        .frame_generation = 1,
    });
    defer a.free(undecorated);
    try scene.apply(undecorated);
    try std.testing.expectEqual(false, scene.decorations.?.decorated);

    const decorated = try frameDecorationsMessage(a, 3, 7, .{
        .decorated = true,
        .frame_generation = 1,
    });
    defer a.free(decorated);
    try scene.apply(decorated);
    try std.testing.expectEqual(true, scene.decorations.?.decorated);

    const stale = try frameDecorationsMessage(a, 4, 7, .{
        .decorated = true,
        .frame_generation = 2,
    });
    defer a.free(stale);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(stale));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const wrong_frame = try frameDecorationsMessage(a, 4, 8, .{
        .decorated = true,
        .frame_generation = 1,
    });
    defer a.free(wrong_frame);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_frame));

    scene.resetForResync();
    try std.testing.expect(scene.decorations == null);
}

test "scene applies scale only to the active frame generation" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    const scale = try frameScaleMessage(a, 2, 7, .{
        .scale = 1.5,
        .dpi_x = 96,
        .dpi_y = 192,
        .frame_generation = 1,
    });
    defer a.free(scale);
    try scene.apply(scale);
    try std.testing.expectEqual(@as(f32, 1.5), scene.scale.?.scale);
    try std.testing.expectEqual(@as(f32, 96), scene.scale.?.dpi_x);
    try std.testing.expectEqual(@as(f32, 192), scene.scale.?.dpi_y);

    const replacement = try frameScaleMessage(a, 3, 7, .{
        .scale = 2,
        .dpi_x = 192,
        .dpi_y = 192,
        .frame_generation = 1,
    });
    defer a.free(replacement);
    try scene.apply(replacement);
    try std.testing.expectEqual(@as(f32, 2), scene.scale.?.scale);

    const stale = try frameScaleMessage(a, 4, 7, .{
        .scale = 1,
        .dpi_x = 96,
        .dpi_y = 96,
        .frame_generation = 2,
    });
    defer a.free(stale);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(stale));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const wrong_frame = try frameScaleMessage(a, 4, 8, .{
        .scale = 1,
        .dpi_x = 96,
        .dpi_y = 96,
        .frame_generation = 1,
    });
    defer a.free(wrong_frame);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_frame));

    scene.resetForResync();
    try std.testing.expect(scene.scale == null);
}

test "scene applies fullscreen only to the active frame generation" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    const fullboth = try frameFullscreenMessage(a, 2, 7, .{
        .mode = .fullboth,
        .frame_generation = 1,
    });
    defer a.free(fullboth);
    try scene.apply(fullboth);
    try std.testing.expectEqual(protocol.FrameFullscreenMode.fullboth, scene.fullscreen.?.mode);

    const fullwidth = try frameFullscreenMessage(a, 3, 7, .{
        .mode = .fullwidth,
        .frame_generation = 1,
    });
    defer a.free(fullwidth);
    try scene.apply(fullwidth);
    try std.testing.expectEqual(protocol.FrameFullscreenMode.fullwidth, scene.fullscreen.?.mode);

    const stale = try frameFullscreenMessage(a, 4, 7, .{
        .mode = .none,
        .frame_generation = 2,
    });
    defer a.free(stale);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(stale));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const wrong_frame = try frameFullscreenMessage(a, 4, 8, .{
        .mode = .none,
        .frame_generation = 1,
    });
    defer a.free(wrong_frame);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_frame));

    var destroy_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, destroy_payload[0..4], 7, .little);
    std.mem.writeInt(u32, destroy_payload[4..8], 1, .little);
    var destroy: std.ArrayList(u8) = .empty;
    defer destroy.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_destroy,
        .sequence = 4,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = 4,
    }, &destroy_payload, &destroy);
    try scene.apply(destroy.items);
    try std.testing.expect(scene.fullscreen == null);

    scene.resetForResync();
    try std.testing.expect(scene.fullscreen == null);
}

test "scene applies monitor only to the active frame generation" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    const monitor = try frameMonitorMessage(a, 2, 7, .{
        .flags = protocol.FrameMonitorFlags.primary,
        .monitor_id = 30,
        .x = 0,
        .y = 0,
        .width = 1920,
        .height = 1080,
        .frame_generation = 1,
    });
    defer a.free(monitor);
    try scene.apply(monitor);
    try std.testing.expectEqual(@as(u32, 30), scene.monitor.?.monitor_id);
    try std.testing.expectEqual(@as(i32, 1920), scene.monitor.?.width);

    const replacement = try frameMonitorMessage(a, 3, 7, .{
        .monitor_id = 31,
        .x = 1920,
        .y = 0,
        .width = 1280,
        .height = 720,
        .frame_generation = 1,
    });
    defer a.free(replacement);
    try scene.apply(replacement);
    try std.testing.expectEqual(@as(u32, 31), scene.monitor.?.monitor_id);

    const stale = try frameMonitorMessage(a, 4, 7, .{
        .monitor_id = 31,
        .x = 0,
        .y = 0,
        .width = 1,
        .height = 1,
        .frame_generation = 2,
    });
    defer a.free(stale);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(stale));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const wrong_frame = try frameMonitorMessage(a, 4, 8, .{
        .monitor_id = 31,
        .x = 0,
        .y = 0,
        .width = 1,
        .height = 1,
        .frame_generation = 1,
    });
    defer a.free(wrong_frame);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_frame));

    var destroy_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, destroy_payload[0..4], 7, .little);
    std.mem.writeInt(u32, destroy_payload[4..8], 1, .little);
    var destroy: std.ArrayList(u8) = .empty;
    defer destroy.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_destroy,
        .sequence = 4,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = 4,
    }, &destroy_payload, &destroy);
    try scene.apply(destroy.items);
    try std.testing.expect(scene.monitor == null);

    scene.resetForResync();
    try std.testing.expect(scene.monitor == null);
}

test "scene applies maximize only to the active frame generation" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    const horizontal = try frameMaximizeMessage(a, 2, 7, .{
        .flags = protocol.FrameMaximizeFlags.horizontal,
        .frame_generation = 1,
    });
    defer a.free(horizontal);
    try scene.apply(horizontal);
    try std.testing.expectEqual(@as(u8, protocol.FrameMaximizeFlags.horizontal), scene.maximize.?.flags);

    const vertical = try frameMaximizeMessage(a, 3, 7, .{
        .flags = protocol.FrameMaximizeFlags.vertical,
        .frame_generation = 1,
    });
    defer a.free(vertical);
    try scene.apply(vertical);
    try std.testing.expectEqual(@as(u8, protocol.FrameMaximizeFlags.vertical), scene.maximize.?.flags);

    const stale = try frameMaximizeMessage(a, 4, 7, .{
        .flags = protocol.FrameMaximizeFlags.both,
        .frame_generation = 2,
    });
    defer a.free(stale);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(stale));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const wrong_frame = try frameMaximizeMessage(a, 4, 8, .{
        .flags = protocol.FrameMaximizeFlags.both,
        .frame_generation = 1,
    });
    defer a.free(wrong_frame);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_frame));

    const current = try frameMaximizeMessage(a, 4, 7, .{
        .flags = protocol.FrameMaximizeFlags.both,
        .frame_generation = 1,
    });
    defer a.free(current);
    try scene.apply(current);

    var destroy_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, destroy_payload[0..4], 7, .little);
    std.mem.writeInt(u32, destroy_payload[4..8], 1, .little);
    var destroy: std.ArrayList(u8) = .empty;
    defer destroy.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_destroy,
        .sequence = 5,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = 5,
    }, &destroy_payload, &destroy);
    try scene.apply(destroy.items);
    try std.testing.expect(scene.maximize == null);

    scene.resetForResync();
    try std.testing.expect(scene.maximize == null);
}

test "scene applies size hints only to the active frame generation" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    const hints = try frameSizeHintsMessage(a, 2, 7, .{
        .flags = protocol.FrameSizeHintFlags.min_size |
            protocol.FrameSizeHintFlags.max_size |
            protocol.FrameSizeHintFlags.size_increment |
            protocol.FrameSizeHintFlags.aspect_ratio,
        .frame_generation = 1,
        .min_width = 120,
        .min_height = 48,
        .max_width = 960,
        .max_height = 480,
        .width_increment = 8,
        .height_increment = 8,
        .aspect_min_numerator = 1,
        .aspect_min_denominator = 4,
        .aspect_max_numerator = 4,
        .aspect_max_denominator = 1,
    });
    defer a.free(hints);
    try scene.apply(hints);
    try std.testing.expectEqual(@as(u32, 120), scene.size_hints.?.min_width);
    try std.testing.expectEqual(@as(u32, 960), scene.size_hints.?.max_width);
    try std.testing.expectEqual(@as(u32, 8), scene.size_hints.?.width_increment);

    const replacement = try frameSizeHintsMessage(a, 3, 7, .{
        .flags = protocol.FrameSizeHintFlags.min_size,
        .frame_generation = 1,
        .min_width = 80,
        .min_height = 40,
    });
    defer a.free(replacement);
    try scene.apply(replacement);
    try std.testing.expectEqual(@as(u32, 80), scene.size_hints.?.min_width);
    try std.testing.expectEqual(@as(u32, 0), scene.size_hints.?.max_width);

    const stale = try frameSizeHintsMessage(a, 4, 7, .{
        .flags = protocol.FrameSizeHintFlags.min_size,
        .frame_generation = 2,
        .min_width = 100,
        .min_height = 40,
    });
    defer a.free(stale);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(stale));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);
    try std.testing.expectEqual(@as(u32, 80), scene.size_hints.?.min_width);

    const wrong_frame = try frameSizeHintsMessage(a, 4, 8, .{
        .flags = protocol.FrameSizeHintFlags.min_size,
        .frame_generation = 1,
        .min_width = 100,
        .min_height = 40,
    });
    defer a.free(wrong_frame);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_frame));

    const current = try frameSizeHintsMessage(a, 4, 7, .{
        .flags = protocol.FrameSizeHintFlags.min_size,
        .frame_generation = 1,
        .min_width = 100,
        .min_height = 40,
    });
    defer a.free(current);
    try scene.apply(current);
    try std.testing.expectEqual(@as(u32, 100), scene.size_hints.?.min_width);

    var destroy_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, destroy_payload[0..4], 7, .little);
    std.mem.writeInt(u32, destroy_payload[4..8], 1, .little);
    var destroy: std.ArrayList(u8) = .empty;
    defer destroy.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_destroy,
        .sequence = 5,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = 5,
    }, &destroy_payload, &destroy);
    try scene.apply(destroy.items);
    try std.testing.expect(scene.size_hints == null);

    scene.resetForResync();
    try std.testing.expect(scene.size_hints == null);
}

test "scene applies z-order only for valid identities and targets" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    const raise = try frameZOrderMessage(a, 2, 7, .{
        .operation = .raise,
        .frame_generation = 1,
    });
    defer a.free(raise);
    try scene.apply(raise);
    try std.testing.expectEqual(protocol.FrameZOrderOperation.raise, scene.z_order.?.operation);

    const above = try frameZOrderMessage(a, 3, 7, .{
        .operation = .above,
        .frame_generation = 1,
        .relative_frame_id = 7,
        .relative_frame_generation = 1,
    });
    defer a.free(above);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(above));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);
    try std.testing.expectEqual(
        protocol.FrameZOrderOperation.raise,
        scene.z_order.?.operation,
    );

    try scene.frames.createObserved(8, 1, .visible, true);

    const stale_target = try frameZOrderMessage(a, 3, 7, .{
        .operation = .above,
        .frame_generation = 1,
        .relative_frame_id = 8,
        .relative_frame_generation = 2,
    });
    defer a.free(stale_target);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(stale_target));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);

    const current = try frameZOrderMessage(a, 3, 7, .{
        .operation = .above,
        .frame_generation = 1,
        .relative_frame_id = 8,
        .relative_frame_generation = 1,
    });
    defer a.free(current);
    try scene.apply(current);
    try std.testing.expectEqual(protocol.FrameZOrderOperation.above, scene.z_order.?.operation);
    try std.testing.expectEqual(@as(u32, 8), scene.z_order.?.relative_frame_id);

    var destroy_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, destroy_payload[0..4], 7, .little);
    std.mem.writeInt(u32, destroy_payload[4..8], 1, .little);
    var destroy: std.ArrayList(u8) = .empty;
    defer destroy.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_destroy,
        .sequence = 4,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = 4,
    }, &destroy_payload, &destroy);
    try scene.apply(destroy.items);
    try std.testing.expect(scene.z_order == null);

    scene.resetForResync();
    try std.testing.expect(scene.z_order == null);
}

test "scene applies parent state only for valid identities and targets" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    const unparent = try frameParentMessage(a, 2, 7, .{
        .child_frame_generation = 1,
    });
    defer a.free(unparent);
    try scene.apply(unparent);
    try std.testing.expectEqual(@as(u32, 1), scene.parent.?.child_frame_generation);

    const self_parent = try frameParentMessage(a, 3, 7, .{
        .flags = protocol.FrameParentFlags.present,
        .parent_frame_id = 7,
        .parent_frame_generation = 1,
        .child_frame_generation = 1,
    });
    defer a.free(self_parent);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(self_parent));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);
    try std.testing.expect(scene.parent != null);
    try std.testing.expectEqual(
        @as(u32, 0),
        scene.parent.?.parent_frame_id,
    );

    const stale_parent = try frameParentMessage(a, 3, 7, .{
        .flags = protocol.FrameParentFlags.present,
        .parent_frame_id = 8,
        .parent_frame_generation = 2,
        .child_frame_generation = 1,
    });
    defer a.free(stale_parent);
    try std.testing.expectError(Error.FrameNotActive, scene.apply(stale_parent));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);

    try scene.frames.createObserved(8, 1, .visible, true);
    const wrong_generation = try frameParentMessage(a, 3, 7, .{
        .flags = protocol.FrameParentFlags.present,
        .parent_frame_id = 8,
        .parent_frame_generation = 2,
        .child_frame_generation = 1,
    });
    defer a.free(wrong_generation);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_generation));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);

    const linked = try frameParentMessage(a, 3, 7, .{
        .flags = protocol.FrameParentFlags.present | protocol.FrameParentFlags.modal,
        .parent_frame_id = 8,
        .parent_frame_generation = 1,
        .child_frame_generation = 1,
    });
    defer a.free(linked);
    try scene.apply(linked);
    try std.testing.expectEqual(@as(u32, 8), scene.parent.?.parent_frame_id);
    try std.testing.expectEqual(
        protocol.FrameParentFlags.present | protocol.FrameParentFlags.modal,
        scene.parent.?.flags,
    );

    const wrong_child = try frameParentMessage(a, 4, 7, .{
        .flags = protocol.FrameParentFlags.present,
        .parent_frame_id = 8,
        .parent_frame_generation = 1,
        .child_frame_generation = 2,
    });
    defer a.free(wrong_child);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_child));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);
    try std.testing.expectEqual(@as(u32, 8), scene.parent.?.parent_frame_id);

    const wrong_envelope = try frameParentMessage(a, 4, 8, .{
        .flags = protocol.FrameParentFlags.present,
        .parent_frame_id = 7,
        .parent_frame_generation = 1,
        .child_frame_generation = 1,
    });
    defer a.free(wrong_envelope);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_envelope));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const duplicate = try frameParentMessage(a, 3, 7, .{
        .child_frame_generation = 1,
    });
    defer a.free(duplicate);
    try std.testing.expectError(Error.InvalidSequence, scene.apply(duplicate));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    var destroy_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, destroy_payload[0..4], 7, .little);
    std.mem.writeInt(u32, destroy_payload[4..8], 1, .little);
    var destroy: std.ArrayList(u8) = .empty;
    defer destroy.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_destroy,
        .sequence = 4,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = 4,
    }, &destroy_payload, &destroy);
    try scene.apply(destroy.items);
    try std.testing.expect(scene.parent == null);

    scene.resetForResync();
    try std.testing.expect(scene.parent == null);
}

test "scene applies standard session control and pauses frame traffic" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    const control_suspend = try sessionControlMessage(
        a,
        2,
        protocol.Message.session_suspend,
        &.{ 3, 0, 0, 0 },
    );
    defer a.free(control_suspend);
    try scene.apply(control_suspend);
    try std.testing.expectEqual(session.ControlStage.suspended, scene.control.stage);

    const blocked_update = try updateMessage(a, 3, 7, 7, 10, 0);
    defer a.free(blocked_update);
    try std.testing.expectError(Error.SessionSuspended, scene.apply(blocked_update));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);

    const control_resume = try sessionControlMessage(
        a,
        3,
        protocol.Message.session_resume,
        &.{ 11, 0, 0, 0 },
    );
    defer a.free(control_resume);
    try scene.apply(control_resume);
    try std.testing.expectEqual(session.ControlStage.resume_pending, scene.control.stage);

    const blocked_pending_update = try updateMessage(a, 4, 7, 7, 10, 0);
    defer a.free(blocked_pending_update);
    try std.testing.expectError(Error.SessionSuspended, scene.apply(blocked_pending_update));
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const stale_resumed = try sessionControlMessage(
        a,
        4,
        protocol.Message.session_resumed,
        &.{ 4, 0, 0, 0, 0, 0, 0, 0 },
    );
    defer a.free(stale_resumed);
    try std.testing.expectError(Error.InvalidSequence, scene.apply(stale_resumed));
    try std.testing.expectEqual(session.ControlStage.resume_pending, scene.control.stage);
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);

    const resumed = try sessionControlMessage(
        a,
        4,
        protocol.Message.session_resumed,
        &.{ 12, 0, 0, 0, 0, 0, 0, 0 },
    );
    defer a.free(resumed);
    try scene.apply(resumed);
    try std.testing.expectEqual(session.ControlStage.active, scene.control.stage);
    try std.testing.expectEqual(@as(u64, 12), scene.next_sequence.?);

    const update = try updateMessage(a, 12, 7, 7, 10, 0);
    defer a.free(update);
    try scene.apply(update);
    try std.testing.expectEqual(@as(u64, 1), scene.stats.frame_updates);

    const close = try sessionControlMessage(
        a,
        13,
        protocol.Message.session_close,
        &.{ 1, 0, 0, 0 },
    );
    defer a.free(close);
    try scene.apply(close);
    try std.testing.expectEqual(session.ControlStage.closed, scene.control.stage);
}

test "scene terminal control states reject traffic without advancing sequence" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    var mismatch: [8]u8 = undefined;
    std.mem.writeInt(u16, mismatch[0..2], 1, .little);
    std.mem.writeInt(u16, mismatch[2..4], 0, .little);
    std.mem.writeInt(u16, mismatch[4..6], 2, .little);
    std.mem.writeInt(u16, mismatch[6..8], 0, .little);
    const fatal = try sessionControlMessage(
        a,
        2,
        protocol.Message.version_mismatch,
        &mismatch,
    );
    defer a.free(fatal);
    try scene.apply(fatal);
    try std.testing.expectEqual(session.ControlStage.fatal, scene.control.stage);

    const blocked_update = try updateMessage(a, 3, 7, 7, 10, 0);
    defer a.free(blocked_update);
    try std.testing.expectError(Error.InvalidSessionStage, scene.apply(blocked_update));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);

    const ping = try sessionControlMessage(
        a,
        3,
        protocol.Message.ping,
        &.{ 22, 0, 0, 0, 0, 0, 0, 0 },
    );
    defer a.free(ping);
    try std.testing.expectError(Error.InvalidSessionStage, scene.apply(ping));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);

    const closed = try createMessage(a, 3, 8, 8);
    defer a.free(closed);
    try std.testing.expectError(Error.InvalidSessionStage, scene.apply(closed));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);
}

test "scene ordered close rejects frame traffic" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    const update = try updateMessage(a, 2, 7, 7, 10, 0);
    defer a.free(update);
    try scene.apply(update);

    const close = try sessionControlMessage(
        a,
        3,
        protocol.Message.session_close,
        &.{ 1, 0, 0, 0 },
    );
    defer a.free(close);
    try scene.apply(close);
    try std.testing.expectEqual(session.ControlStage.closed, scene.control.stage);
}

test "scene atomically validates resource generation declarations" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);
    const update = try updateMessage(a, 2, 7, 7, 10, 0);
    defer a.free(update);
    try scene.apply(update);

    var resource_bytes: std.ArrayList(u8) = .empty;
    defer resource_bytes.deinit(a);
    try encodeResourceDeclaration(a, .{ .kind = .font, .id = 12, .generation = 2, .status = .live }, &resource_bytes);
    try resource_bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeResourceDeclaration(resource_bytes.items));

    resource_bytes.clearRetainingCapacity();
    try encodeResourceDeclaration(a, .{ .kind = .font, .id = 12, .generation = 2, .status = .live }, &resource_bytes);
    try encodeResourceDeclaration(a, .{ .kind = .string, .id = 30, .generation = 1, .status = .live }, &resource_bytes);
    const third = try updateWithResources(a, 3, resource_bytes.items);
    defer a.free(third);
    try scene.apply(third);
    try std.testing.expectEqual(@as(u32, 2), scene.resources.lookup(.font, 12).?.generation);
    try std.testing.expectEqual(lifecycle.ResourceStatus.live, scene.resources.lookup(.string, 30).?.status);

    const stale = try updateWithResources(a, 4, resource_bytes.items);
    defer a.free(stale);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(stale));
    try std.testing.expectEqual(@as(u32, 2), scene.resources.lookup(.font, 12).?.generation);
    try std.testing.expectEqual(@as(u64, 2), scene.stats.frame_updates);
}

fn stringMessage(
    a: std.mem.Allocator,
    message_type: u16,
    sequence: u64,
    payload: []const u8,
) ![]u8 {
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .timestamp_ns = sequence,
    }, payload, &message);
    return message.toOwnedSlice(a);
}

test "scene owns replaces looks up and deletes bounded string resources" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    var ascii_payload: std.ArrayList(u8) = .empty;
    defer ascii_payload.deinit(a);
    try protocol.encodeStringDefine(a, .{ .resource_id = 12, .generation = 1, .bytes = "hello" }, &ascii_payload);
    const ascii = try stringMessage(a, protocol.Message.string_define, 2, ascii_payload.items);
    defer a.free(ascii);
    try scene.apply(ascii);
    try std.testing.expectEqualStrings("hello", scene.strings.lookup(12).?.bytes);
    try std.testing.expectEqual(lifecycle.ResourceStatus.live, scene.resources.lookup(.string, 12).?.status);

    ascii_payload.clearRetainingCapacity();
    try protocol.encodeStringDefine(a, .{ .resource_id = 12, .generation = 2, .bytes = "é🎉" }, &ascii_payload);
    const unicode = try stringMessage(a, protocol.Message.string_define, 3, ascii_payload.items);
    defer a.free(unicode);
    try scene.apply(unicode);
    try std.testing.expectEqual(@as(u32, 2), scene.strings.lookup(12).?.generation);
    try std.testing.expectEqualStrings("é🎉", scene.strings.lookup(12).?.bytes);
    try std.testing.expectEqual(@as(u64, 1), scene.strings.counters.defines);
    try std.testing.expectEqual(@as(u64, 1), scene.strings.counters.replacements);

    ascii_payload.clearRetainingCapacity();
    try protocol.encodeStringDelete(a, .{ .resource_id = 12, .generation = 2 }, &ascii_payload);
    const deletion = try stringMessage(a, protocol.Message.string_delete, 4, ascii_payload.items);
    defer a.free(deletion);
    try scene.apply(deletion);
    try std.testing.expect(scene.strings.lookup(12) == null);
    try std.testing.expectEqual(lifecycle.ResourceStatus.deleted, scene.resources.lookup(.string, 12).?.status);

    const duplicate = try stringMessage(a, protocol.Message.string_delete, 5, ascii_payload.items);
    defer a.free(duplicate);
    try std.testing.expectError(Error.ResourceNotLive, scene.apply(duplicate));
    try std.testing.expectEqual(@as(u64, 5), scene.next_sequence.?);
    try std.testing.expectEqual(@as(u64, 1), scene.strings.counters.rejections);
}

test "scene rejects stale equal and malformed string resources without sequence drift" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeStringDefine(a, .{ .resource_id = 20, .generation = 5, .bytes = "live" }, &payload);
    const first = try stringMessage(a, protocol.Message.string_define, 2, payload.items);
    defer a.free(first);
    try scene.apply(first);

    payload.clearRetainingCapacity();
    try protocol.encodeStringDefine(a, .{ .resource_id = 20, .generation = 5, .bytes = "equal" }, &payload);
    const equal = try stringMessage(a, protocol.Message.string_define, 3, payload.items);
    defer a.free(equal);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(equal));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);
    try std.testing.expectEqualStrings("live", scene.strings.lookup(20).?.bytes);

    payload.clearRetainingCapacity();
    try protocol.encodeStringDelete(a, .{ .resource_id = 20, .generation = 4 }, &payload);
    const wrong_generation = try stringMessage(a, protocol.Message.string_delete, 3, payload.items);
    defer a.free(wrong_generation);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(wrong_generation));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);
    try std.testing.expectEqualStrings("live", scene.strings.lookup(20).?.bytes);

    var malformed: [14]u8 = undefined;
    std.mem.writeInt(u32, malformed[0..4], 21, .little);
    std.mem.writeInt(u32, malformed[4..8], 1, .little);
    std.mem.writeInt(u32, malformed[8..12], 2, .little);
    @memcpy(malformed[12..14], "\xff\xfe");
    const invalid_utf8 = try stringMessage(a, protocol.Message.string_define, 3, &malformed);
    defer a.free(invalid_utf8);
    try std.testing.expectError(Error.InvalidUtf8, scene.apply(invalid_utf8));

    malformed[12] = 'a';
    malformed[13] = 0;
    const nul = try stringMessage(a, protocol.Message.string_define, 3, &malformed);
    defer a.free(nul);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(nul));

    const truncated = try stringMessage(a, protocol.Message.string_define, 3, malformed[0..11]);
    defer a.free(truncated);
    try std.testing.expectError(Error.InvalidTable, scene.apply(truncated));

    var trailing_payload: [15]u8 = undefined;
    @memcpy(trailing_payload[0..malformed.len], &malformed);
    trailing_payload[malformed.len] = 'x';
    const trailing = try stringMessage(a, protocol.Message.string_define, 3, &trailing_payload);
    defer a.free(trailing);
    try std.testing.expectError(Error.InvalidTable, scene.apply(trailing));

    var oversized: [12]u8 = undefined;
    std.mem.writeInt(u32, oversized[0..4], 22, .little);
    std.mem.writeInt(u32, oversized[4..8], 1, .little);
    std.mem.writeInt(u32, oversized[8..12], protocol.max_string_bytes + 1, .little);
    const over = try stringMessage(a, protocol.Message.string_define, 3, &oversized);
    defer a.free(over);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(over));

    payload.clearRetainingCapacity();
    try protocol.encodeStringDefine(a, .{ .resource_id = 22, .generation = 1, .bytes = "ok" }, &payload);
    const valid = try stringMessage(a, protocol.Message.string_define, 3, payload.items);
    defer a.free(valid);
    try scene.apply(valid);
    try std.testing.expectEqualStrings("ok", scene.strings.lookup(22).?.bytes);
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);
}

test "string resync cleanup and capacity remain bounded" {
    const a = std.testing.allocator;
    {
        var scene = Scene.init(a);
        defer scene.deinit();
        const create = try createMessage(a, 1, 7, 7);
        defer a.free(create);
        try scene.apply(create);
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(a);
        try protocol.encodeStringDefine(a, .{ .resource_id = 30, .generation = 1, .bytes = "before" }, &payload);
        const before = try stringMessage(a, protocol.Message.string_define, 2, payload.items);
        defer a.free(before);
        try scene.apply(before);
        scene.resetForResync();
        try std.testing.expect(scene.strings.lookup(30) == null);
        try std.testing.expectEqual(@as(usize, 0), scene.resources.len);
        try std.testing.expect(scene.session_id == null);
        try scene.apply(create);
        try std.testing.expectEqual(@as(u64, 2), scene.next_sequence.?);
    }

    {
        var scene = Scene.init(a);
        defer scene.deinit();
        const create = try createMessage(a, 1, 7, 7);
        defer a.free(create);
        try scene.apply(create);
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(a);
        for (1..max_string_resources + 1) |id| {
            const resource_id: u32 = @intCast(id);
            payload.clearRetainingCapacity();
            try protocol.encodeStringDefine(a, .{
                .resource_id = resource_id,
                .generation = 1,
                .bytes = "value",
            }, &payload);
            const message = try stringMessage(
                a,
                protocol.Message.string_define,
                @intCast(id + 1),
                payload.items,
            );
            defer a.free(message);
            try scene.apply(message);
        }
        try std.testing.expectEqual(max_string_resources, scene.strings.len);

        payload.clearRetainingCapacity();
        try protocol.encodeStringDefine(a, .{ .resource_id = max_string_resources + 1, .generation = 1, .bytes = "over" }, &payload);
        const overflow = try stringMessage(a, protocol.Message.string_define, max_string_resources + 2, payload.items);
        defer a.free(overflow);
        try std.testing.expectError(Error.ResourceTableFull, scene.apply(overflow));
        try std.testing.expectEqual(max_string_resources, scene.strings.len);
        try std.testing.expectEqual(@as(u64, max_string_resources + 2), scene.next_sequence.?);

        payload.clearRetainingCapacity();
        try protocol.encodeStringDefine(a, .{ .resource_id = max_string_resources, .generation = 2, .bytes = "replacement" }, &payload);
        const replacement = try stringMessage(a, protocol.Message.string_define, max_string_resources + 2, payload.items);
        defer a.free(replacement);
        try scene.apply(replacement);
        try std.testing.expectEqual(max_string_resources, scene.strings.len);
        try std.testing.expectEqualStrings("replacement", scene.strings.lookup(max_string_resources).?.bytes);
    }
}

fn updateWithResources(a: std.mem.Allocator, sequence: u64, resource_records: []const u8) ![]u8 {
    const header: protocol.FrameUpdateHeader = .{
        .frame_id = 7,
        .frame_generation = 1,
        .sequence = sequence,
        .redisplay_generation = sequence,
        .logical_x = 0,
        .logical_y = 0,
        .logical_width = 80,
        .logical_height = 60,
        .physical_x = 0,
        .physical_y = 0,
        .physical_width = 80,
        .physical_height = 60,
        .scale = 1,
        .dpi_x = 96,
        .dpi_y = 96,
        .damage_mode = 2,
        .update_cause = 1,
        .coalesced_count = 0,
        .timestamp_ns = sequence,
    };
    var windows: std.ArrayList(u8) = .empty;
    defer windows.deinit(a);
    try encodeWindow(a, .{ .id = 100, .frame_id = 7, .x = 0, .y = 0, .width = 80, .height = 60 }, &windows);
    var rows: std.ArrayList(u8) = .empty;
    defer rows.deinit(a);
    try encodeRow(a, .{ .window_id = 100, .index = 0, .flags = 0, .x = 0, .y = 0, .width = 10, .height = 10, .ascent = 7, .descent = 3, .baseline = 7, .visible_height = 10 }, &rows);
    var damage: std.ArrayList(u8) = .empty;
    defer damage.deinit(a);
    try encodeRect(a, .{ .x = 0, .y = 0, .width = 80, .height = 60 }, &damage);
    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = windows.items },
        .{ .kind = protocol.SectionKind.rows, .records = rows.items },
        .{ .kind = protocol.SectionKind.damage, .records = damage.items },
        .{ .kind = protocol.SectionKind.resources, .records = resource_records },
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeFrameUpdate(a, .{ .header = header, .sections = &sections }, &payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{ .flags = protocol.Flags.delta, .message_type = protocol.Message.frame_update, .sequence = sequence, .ack_sequence = 0, .session_id = 9, .frame_id = 7, .timestamp_ns = sequence }, payload.items, &message);
    return message.toOwnedSlice(a);
}

fn faceMessage(
    a: std.mem.Allocator,
    message_type: u16,
    sequence: u64,
    payload: []const u8,
) ![]u8 {
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .timestamp_ns = sequence,
    }, payload, &message);
    return message.toOwnedSlice(a);
}

test "scene owns replaces looks up and deletes bounded face resources" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    var face = protocol.FaceDefine{ .face_id = 12, .generation = 1 };
    face.presence.font = true;
    face.presence.stipple = true;
    face.font_id = 50;
    face.font_generation = 51;
    face.stipple_id = 52;
    face.stipple_generation = 53;
    try protocol.encodeFaceDefine(a, face, &payload);
    const defined = try faceMessage(a, protocol.Message.face_define, 2, payload.items);
    defer a.free(defined);
    try scene.apply(defined);
    try std.testing.expectEqual(face, scene.faces.lookup(12).?.payload);
    try std.testing.expectEqual(lifecycle.ResourceStatus.live, scene.resources.lookup(.face, 12).?.status);

    face.generation = 1;
    payload.clearRetainingCapacity();
    try protocol.encodeFaceDefine(a, face, &payload);
    const equal = try faceMessage(a, protocol.Message.face_define, 3, payload.items);
    defer a.free(equal);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(equal));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);

    payload.clearRetainingCapacity();
    try protocol.encodeFaceDelete(a, .{ .face_id = 12, .generation = 9 }, &payload);
    const wrong_delete = try faceMessage(a, protocol.Message.face_delete, 3, payload.items);
    defer a.free(wrong_delete);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(wrong_delete));

    var malformed: [97]u8 = undefined;
    @memset(&malformed, 0);
    std.mem.writeInt(u32, malformed[0..4], 13, .little);
    std.mem.writeInt(u32, malformed[4..8], 1, .little);
    const wrong_size = try faceMessage(a, protocol.Message.face_define, 3, &malformed);
    defer a.free(wrong_size);
    try std.testing.expectError(Error.InvalidTable, scene.apply(wrong_size));

    face.generation = 2;
    payload.clearRetainingCapacity();
    try protocol.encodeFaceDefine(a, face, &payload);
    const replacement = try faceMessage(a, protocol.Message.face_define, 3, payload.items);
    defer a.free(replacement);
    try scene.apply(replacement);
    try std.testing.expectEqual(@as(u32, 2), scene.faces.lookup(12).?.generation);
    try std.testing.expectEqual(@as(u64, 1), scene.faces.counters.replacements);

    payload.clearRetainingCapacity();
    try protocol.encodeFaceDelete(a, .{ .face_id = 12, .generation = 2 }, &payload);
    const deletion = try faceMessage(a, protocol.Message.face_delete, 4, payload.items);
    defer a.free(deletion);
    try scene.apply(deletion);
    try std.testing.expect(scene.faces.lookup(12) == null);
    try std.testing.expectEqual(lifecycle.ResourceStatus.deleted, scene.resources.lookup(.face, 12).?.status);

    const duplicate = try faceMessage(a, protocol.Message.face_delete, 5, payload.items);
    defer a.free(duplicate);
    try std.testing.expectError(Error.ResourceNotLive, scene.apply(duplicate));
    try std.testing.expectEqual(@as(u64, 5), scene.next_sequence.?);
    try std.testing.expectEqual(@as(u64, 3), scene.faces.counters.rejections);
}

test "face table remains bounded and permits in-place generation replacement" {
    var resources = lifecycle.ResourceRegistry{};
    var faces = FaceResources{};
    for (0..max_face_resources) |index| {
        const id: u32 = @intCast(100 + index);
        try faces.define(&resources, .{ .face_id = id, .generation = 1 });
    }
    try std.testing.expectEqual(max_face_resources, faces.len);
    try std.testing.expectEqual(max_face_resources, resources.len);
    try std.testing.expectError(
        Error.ResourceTableFull,
        faces.define(&resources, .{ .face_id = 999, .generation = 1 }),
    );

    try faces.define(&resources, .{ .face_id = 100, .generation = 65 });
    try std.testing.expectEqual(max_face_resources, faces.len);
    try std.testing.expectEqual(@as(u32, 65), faces.lookup(100).?.generation);
    try std.testing.expectEqual(@as(u64, 1), faces.counters.replacements);
}

test "face resources survive frame destroy and clear on resync and deinit" {
    const a = std.testing.allocator;
    {
        var scene = Scene.init(a);
        const create = try createMessage(a, 1, 7, 7);
        defer a.free(create);
        try scene.apply(create);
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(a);
        try protocol.encodeFaceDefine(a, .{ .face_id = 20, .generation = 1 }, &payload);
        const defined = try faceMessage(a, protocol.Message.face_define, 2, payload.items);
        defer a.free(defined);
        try scene.apply(defined);

        var destroy_payload: [8]u8 = undefined;
        std.mem.writeInt(u32, destroy_payload[0..4], 7, .little);
        std.mem.writeInt(u32, destroy_payload[4..8], 1, .little);
        var destroy: std.ArrayList(u8) = .empty;
        defer destroy.deinit(a);
        try protocol.encodeEnvelope(a, .{
            .flags = 0,
            .message_type = protocol.Message.frame_destroy,
            .sequence = 3,
            .ack_sequence = 0,
            .session_id = 9,
            .frame_id = 7,
            .timestamp_ns = 3,
        }, &destroy_payload, &destroy);
        const destroyed = try a.dupe(u8, destroy.items);
        defer a.free(destroyed);
        try scene.apply(destroyed);
        try std.testing.expect(scene.faces.lookup(20) != null);
        scene.deinit();
    }

    {
        var scene = Scene.init(a);
        const create = try createMessage(a, 1, 7, 7);
        defer a.free(create);
        try scene.apply(create);
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(a);
        try protocol.encodeFaceDefine(a, .{ .face_id = 21, .generation = 1 }, &payload);
        const defined = try faceMessage(a, protocol.Message.face_define, 2, payload.items);
        defer a.free(defined);
        try scene.apply(defined);
        scene.resetForResync();
        try std.testing.expectEqual(@as(usize, 0), scene.faces.len);
        try std.testing.expect(scene.resources.lookup(.face, 21) == null);
        scene.deinit();
    }
}

fn frontendFontFixture(id: u32, generation: u32) protocol.FontDefine {
    var payload = protocol.FontDefine{
        .font_id = id,
        .generation = generation,
        .family_len = 5,
        .foundry_len = 5,
        .style_len = 6,
        .slant = .roman,
        .spacing = .mono,
        .scalable = true,
        .fixed_pitch = true,
        .weight = 400,
        .width_percent = 100,
        .pixel_size = 16,
        .point_size_tenths = 120,
        .x_dpi = 96,
        .y_dpi = 96,
        .ascent = 10,
        .descent = 4,
        .line_height = 14,
        .average_advance = 8,
        .space_advance = 8,
        .max_advance = 10,
        .min_advance = 6,
        .baseline_offset = 10,
        .underline_position = -2,
        .underline_thickness = 1,
    };
    @memcpy(payload.family[0..5], "Test1");
    @memcpy(payload.foundry[0..5], "found");
    @memcpy(payload.style[0..6], "Book12");
    return payload;
}

test "scene owns replaces looks up and deletes bounded font resources" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    const font = frontendFontFixture(12, 1);
    try protocol.encodeFontDefine(a, font, &payload);
    const defined = try faceMessage(a, protocol.Message.font_define, 2, payload.items);
    defer a.free(defined);
    try scene.apply(defined);
    try std.testing.expectEqual(font, scene.fonts.lookup(12).?.payload);
    try std.testing.expectEqual(lifecycle.ResourceStatus.live, scene.resources.lookup(.font, 12).?.status);

    // Equal generation is rejected before any table/registry mutation and
    // leaves envelope sequencing continuous.
    payload.clearRetainingCapacity();
    try protocol.encodeFontDefine(a, font, &payload);
    const equal = try faceMessage(a, protocol.Message.font_define, 3, payload.items);
    defer a.free(equal);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(equal));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);
    try std.testing.expectEqual(font, scene.fonts.lookup(12).?.payload);

    payload.clearRetainingCapacity();
    try protocol.encodeFontDelete(a, .{ .font_id = 12, .generation = 9 }, &payload);
    const wrong_delete = try faceMessage(a, protocol.Message.font_delete, 3, payload.items);
    defer a.free(wrong_delete);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(wrong_delete));

    var malformed: [protocol.font_record_size + 1]u8 = @splat(0);
    std.mem.writeInt(u32, malformed[0..4], 13, .little);
    std.mem.writeInt(u32, malformed[4..8], 1, .little);
    const wrong_size = try faceMessage(a, protocol.Message.font_define, 3, &malformed);
    defer a.free(wrong_size);
    try std.testing.expectError(Error.InvalidTable, scene.apply(wrong_size));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);

    const replacement = frontendFontFixture(12, 2);
    payload.clearRetainingCapacity();
    try protocol.encodeFontDefine(a, replacement, &payload);
    const replacement_message = try faceMessage(a, protocol.Message.font_define, 3, payload.items);
    defer a.free(replacement_message);
    try scene.apply(replacement_message);
    try std.testing.expectEqual(@as(u32, 2), scene.fonts.lookup(12).?.generation);
    try std.testing.expectEqual(@as(u64, 1), scene.fonts.counters.replacements);

    payload.clearRetainingCapacity();
    try protocol.encodeFontDelete(a, .{ .font_id = 12, .generation = 2 }, &payload);
    const deletion = try faceMessage(a, protocol.Message.font_delete, 4, payload.items);
    defer a.free(deletion);
    try scene.apply(deletion);
    try std.testing.expect(scene.fonts.lookup(12) == null);
    try std.testing.expectEqual(lifecycle.ResourceStatus.deleted, scene.resources.lookup(.font, 12).?.status);

    const duplicate = try faceMessage(a, protocol.Message.font_delete, 5, payload.items);
    defer a.free(duplicate);
    try std.testing.expectError(Error.ResourceNotLive, scene.apply(duplicate));
    try std.testing.expectEqual(@as(u64, 5), scene.next_sequence.?);
    try std.testing.expectEqual(@as(u64, 3), scene.fonts.counters.rejections);
}

test "scene applies font patch and preserves retained font metadata" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    const font = frontendFontFixture(12, 1);
    try protocol.encodeFontDefine(a, font, &payload);
    const defined = try faceMessage(a, protocol.Message.font_define, 2, payload.items);
    defer a.free(defined);
    try scene.apply(defined);

    payload.clearRetainingCapacity();
    try protocol.encodeFontPatch(a, .{
        .font_id = 12,
        .expected_generation = 1,
        .new_generation = 2,
        .weight = 700,
        .width_percent = 110,
        .pixel_size = 18,
        .point_size_tenths = 135,
        .x_dpi = 96,
        .y_dpi = 96,
        .slant = .italic,
        .spacing = .mono,
        .scalable = true,
        .fixed_pitch = true,
    }, &payload);
    const patched = try faceMessage(a, protocol.Message.font_patch, 3, payload.items);
    defer a.free(patched);
    try scene.apply(patched);

    const updated = scene.fonts.lookup(12).?;
    try std.testing.expectEqual(@as(u32, 2), updated.generation);
    try std.testing.expectEqual(@as(u16, 700), updated.payload.weight);
    try std.testing.expectEqual(@as(u16, 110), updated.payload.width_percent);
    try std.testing.expectEqual(@as(u32, 18), updated.payload.pixel_size);
    try std.testing.expectEqual(protocol.FontSlant.italic, updated.payload.slant);
    try std.testing.expectEqualStrings("Test1", updated.payload.family[0..updated.payload.family_len]);
    try std.testing.expectEqual(@as(i32, 10), updated.payload.ascent);
    try std.testing.expectEqual(@as(u32, 14), updated.payload.line_height);

    payload.clearRetainingCapacity();
    try protocol.encodeFontPatch(a, .{
        .font_id = 12,
        .expected_generation = 1,
        .new_generation = 3,
        .weight = 700,
        .width_percent = 110,
        .pixel_size = 18,
        .point_size_tenths = 135,
        .x_dpi = 96,
        .y_dpi = 96,
        .slant = .italic,
        .spacing = .mono,
        .scalable = true,
        .fixed_pitch = true,
    }, &payload);
    const stale = try faceMessage(a, protocol.Message.font_patch, 4, payload.items);
    defer a.free(stale);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(stale));
    try std.testing.expectEqual(@as(u32, 2), scene.fonts.lookup(12).?.generation);
}

test "font table remains bounded and permits in-place generation replacement" {
    var resources = lifecycle.ResourceRegistry{};
    var fonts = FontResources{};
    for (0..max_font_resources) |index| {
        const id: u32 = @intCast(200 + index);
        try fonts.define(&resources, .{ .font_id = id, .generation = 1 });
    }
    try std.testing.expectEqual(max_font_resources, fonts.len);
    try std.testing.expectEqual(max_font_resources, resources.len);
    try std.testing.expectError(
        Error.ResourceTableFull,
        fonts.define(&resources, .{ .font_id = 999, .generation = 1 }),
    );

    try fonts.define(&resources, .{ .font_id = 200, .generation = 65 });
    try std.testing.expectEqual(max_font_resources, fonts.len);
    try std.testing.expectEqual(@as(u32, 65), fonts.lookup(200).?.generation);
    try std.testing.expectEqual(@as(u64, 1), fonts.counters.replacements);
}

test "font resources survive frame destroy and clear on resync and deinit" {
    const a = std.testing.allocator;
    {
        var scene = Scene.init(a);
        const create = try createMessage(a, 1, 7, 7);
        defer a.free(create);
        try scene.apply(create);
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(a);
        try protocol.encodeFontDefine(a, frontendFontFixture(20, 1), &payload);
        const defined = try faceMessage(a, protocol.Message.font_define, 2, payload.items);
        defer a.free(defined);
        try scene.apply(defined);

        var destroy_payload: [8]u8 = undefined;
        std.mem.writeInt(u32, destroy_payload[0..4], 7, .little);
        std.mem.writeInt(u32, destroy_payload[4..8], 1, .little);
        var destroyed_message: std.ArrayList(u8) = .empty;
        defer destroyed_message.deinit(a);
        try protocol.encodeEnvelope(a, .{
            .flags = 0,
            .message_type = protocol.Message.frame_destroy,
            .sequence = 3,
            .ack_sequence = 0,
            .session_id = 9,
            .frame_id = 7,
            .timestamp_ns = 3,
        }, &destroy_payload, &destroyed_message);
        const destroyed = try a.dupe(u8, destroyed_message.items);
        defer a.free(destroyed);
        try scene.apply(destroyed);
        try std.testing.expect(scene.fonts.lookup(20) != null);
        scene.deinit();
        try std.testing.expectEqual(@as(usize, 0), scene.fonts.len);
        try std.testing.expect(scene.resources.lookup(.font, 20) == null);
    }

    {
        var scene = Scene.init(a);
        const create = try createMessage(a, 1, 7, 7);
        defer a.free(create);
        try scene.apply(create);
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(a);
        try protocol.encodeFontDefine(a, frontendFontFixture(21, 1), &payload);
        const defined = try faceMessage(a, protocol.Message.font_define, 2, payload.items);
        defer a.free(defined);
        try scene.apply(defined);
        scene.resetForResync();
        try std.testing.expectEqual(@as(usize, 0), scene.fonts.len);
        try std.testing.expect(scene.resources.lookup(.font, 21) == null);
        scene.deinit();
    }
}

fn frontendImageFixture(id: u32, generation: u32) protocol.ImageDefine {
    return .{
        .image_id = id,
        .generation = generation,
        .width = 2,
        .height = 2,
        .total_byte_count = 16,
    };
}

fn imageMessage(
    a: std.mem.Allocator,
    message_type: u16,
    sequence: u64,
    payload: []const u8,
) ![]u8 {
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .timestamp_ns = sequence,
    }, payload, &message);
    return message.toOwnedSlice(a);
}

test "image resources assemble ordered fragments and enforce generation lifecycle" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);

    try protocol.encodeImageDefine(a, frontendImageFixture(10, 1), &payload);
    const define = try imageMessage(a, protocol.Message.image_define, 2, payload.items);
    defer a.free(define);
    try scene.apply(define);
    try std.testing.expect(!scene.images.lookup(10).?.complete);

    const equal = try imageMessage(a, protocol.Message.image_define, 3, payload.items);
    defer a.free(equal);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(equal));
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);

    payload.clearRetainingCapacity();
    try protocol.encodeImageData(a, .{
        .image_id = 10,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 2,
        .bytes = "ABCD",
    }, &payload);
    const ascii_fragment = try imageMessage(a, protocol.Message.image_data, 3, payload.items);
    defer a.free(ascii_fragment);
    try scene.apply(ascii_fragment);

    const binary = [_]u8{ 0, 255, 1, 254, 2, 253, 3, 252, 4, 251, 5, 250 };
    payload.clearRetainingCapacity();
    try protocol.encodeImageData(a, .{
        .image_id = 10,
        .generation = 1,
        .fragment_index = 1,
        .fragment_count = 2,
        .bytes = &binary,
    }, &payload);
    const binary_fragment = try imageMessage(a, protocol.Message.image_data, 4, payload.items);
    defer a.free(binary_fragment);
    try scene.apply(binary_fragment);
    try std.testing.expect(scene.images.lookup(10).?.complete);
    try std.testing.expectEqual(@as(usize, 16), scene.images.lookup(10).?.bytes.len);

    payload.clearRetainingCapacity();
    try protocol.encodeImageData(a, .{
        .image_id = 10,
        .generation = 2,
        .fragment_index = 0,
        .fragment_count = 1,
        .bytes = "wrong-generation",
    }, &payload);
    const wrong_generation = try imageMessage(a, protocol.Message.image_data, 5, payload.items);
    defer a.free(wrong_generation);
    try std.testing.expectError(Error.StaleGeneration, scene.apply(wrong_generation));
    try std.testing.expectEqual(@as(u64, 5), scene.next_sequence.?);

    payload.clearRetainingCapacity();
    try protocol.encodeImageDefine(a, frontendImageFixture(10, 2), &payload);
    const replacement = try imageMessage(a, protocol.Message.image_define, 5, payload.items);
    defer a.free(replacement);
    try scene.apply(replacement);
    try std.testing.expectEqual(@as(usize, 0), scene.images.lookup(10).?.bytes.len);
    try std.testing.expect(!scene.images.lookup(10).?.complete);

    payload.clearRetainingCapacity();
    try protocol.encodeImageData(a, .{
        .image_id = 10,
        .generation = 2,
        .fragment_index = 0,
        .fragment_count = 1,
        .bytes = "ABCDEFGHIJKLMNOP",
    }, &payload);
    const complete_replacement = try imageMessage(a, protocol.Message.image_data, 6, payload.items);
    defer a.free(complete_replacement);
    try scene.apply(complete_replacement);

    payload.clearRetainingCapacity();
    try protocol.encodeImageDelete(a, .{ .image_id = 10, .generation = 2 }, &payload);
    const deleted = try imageMessage(a, protocol.Message.image_delete, 7, payload.items);
    defer a.free(deleted);
    try scene.apply(deleted);
    const duplicate = try imageMessage(a, protocol.Message.image_delete, 8, payload.items);
    defer a.free(duplicate);
    try std.testing.expectError(Error.ResourceNotLive, scene.apply(duplicate));
    try std.testing.expectEqual(@as(u64, 8), scene.next_sequence.?);
    scene.deinit();
}

test "image deletion covers complete and incomplete payloads and cleanup remains safe" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);

    try protocol.encodeImageDefine(a, .{
        .image_id = 11,
        .generation = 1,
        .width = 1,
        .height = 1,
        .total_byte_count = 4,
    }, &payload);
    const define = try imageMessage(a, protocol.Message.image_define, 2, payload.items);
    defer a.free(define);
    try scene.apply(define);
    payload.clearRetainingCapacity();
    try protocol.encodeImageData(a, .{
        .image_id = 11,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 1,
        .bytes = "done",
    }, &payload);
    const data = try imageMessage(a, protocol.Message.image_data, 3, payload.items);
    defer a.free(data);
    try scene.apply(data);
    payload.clearRetainingCapacity();
    try protocol.encodeImageDelete(a, .{ .image_id = 11, .generation = 1 }, &payload);
    const complete_delete = try imageMessage(a, protocol.Message.image_delete, 4, payload.items);
    defer a.free(complete_delete);
    try scene.apply(complete_delete);

    payload.clearRetainingCapacity();
    try protocol.encodeImageDefine(a, .{
        .image_id = 12,
        .generation = 1,
        .width = 1,
        .height = 2,
        .total_byte_count = 8,
    }, &payload);
    const second_define = try imageMessage(a, protocol.Message.image_define, 5, payload.items);
    defer a.free(second_define);
    try scene.apply(second_define);
    payload.clearRetainingCapacity();
    try protocol.encodeImageData(a, .{
        .image_id = 12,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 2,
        .bytes = "half",
    }, &payload);
    const partial = try imageMessage(a, protocol.Message.image_data, 6, payload.items);
    defer a.free(partial);
    try scene.apply(partial);
    payload.clearRetainingCapacity();
    try protocol.encodeImageDelete(a, .{ .image_id = 12, .generation = 1 }, &payload);
    const incomplete_delete = try imageMessage(a, protocol.Message.image_delete, 7, payload.items);
    defer a.free(incomplete_delete);
    try scene.apply(incomplete_delete);

    try std.testing.expectEqual(@as(usize, 0), scene.images.len);
    try std.testing.expectEqual(@as(usize, 0), scene.images.declared_bytes);
    scene.resetForResync();
    scene.deinit();
}

test "image fragment order totals malformed records and limits fail closed" {
    const a = std.testing.allocator;
    var resources = lifecycle.ResourceRegistry{};
    var images = ImageResources{};

    try images.define(a, &resources, .{
        .image_id = 20,
        .generation = 1,
        .width = 1,
        .height = 2,
        .total_byte_count = 8,
    });
    try images.data(a, .{
        .image_id = 20,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 2,
        .bytes = "half",
    });
    try std.testing.expectError(Error.InvalidSequence, images.data(a, .{
        .image_id = 20,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 2,
        .bytes = "dup!",
    }));
    try std.testing.expectError(Error.InvalidSequence, images.data(a, .{
        .image_id = 20,
        .generation = 1,
        .fragment_index = 1,
        .fragment_count = 1,
        .bytes = "half",
    }));
    try images.data(a, .{
        .image_id = 20,
        .generation = 1,
        .fragment_index = 1,
        .fragment_count = 2,
        .bytes = "tail",
    });
    try std.testing.expect(images.lookup(20).?.complete);

    try images.define(a, &resources, .{
        .image_id = 21,
        .generation = 1,
        .width = 1,
        .height = 2,
        .total_byte_count = 8,
    });
    try std.testing.expectError(Error.InvalidSequence, images.data(a, .{
        .image_id = 21,
        .generation = 1,
        .fragment_index = 1,
        .fragment_count = 2,
        .bytes = "gap!",
    }));
    try images.define(a, &resources, .{
        .image_id = 21,
        .generation = 2,
        .width = 1,
        .height = 2,
        .total_byte_count = 8,
    });
    try std.testing.expectEqual(@as(u16, 0), images.lookup(21).?.fragments_received);
    try std.testing.expectError(Error.InvalidMessage, images.data(a, .{
        .image_id = 21,
        .generation = 2,
        .fragment_index = 0,
        .fragment_count = 1,
        .bytes = "wrong",
    }));
    try images.delete(a, &resources, .{ .image_id = 21, .generation = 2 });
    try images.delete(a, &resources, .{ .image_id = 20, .generation = 1 });

    try images.define(a, &resources, .{
        .image_id = 22,
        .generation = 1,
        .width = 1024,
        .height = 1024,
        .total_byte_count = protocol.max_image_bytes,
    });
    try std.testing.expectError(Error.ResourcePayloadBudgetExceeded, images.define(a, &resources, .{
        .image_id = 23,
        .generation = 1,
        .width = 1,
        .height = 1,
        .total_byte_count = 4,
    }));
    try images.delete(a, &resources, .{ .image_id = 22, .generation = 1 });

    for (0..max_image_resources) |index| {
        try images.define(a, &resources, .{
            .image_id = @intCast(100 + index),
            .generation = 1,
            .width = 1,
            .height = 1,
            .total_byte_count = 4,
        });
    }
    try std.testing.expectError(Error.ResourceTableFull, images.define(a, &resources, .{
        .image_id = 999,
        .generation = 1,
        .width = 1,
        .height = 1,
        .total_byte_count = 4,
    }));
    try images.define(a, &resources, .{
        .image_id = 100,
        .generation = 2,
        .width = 1,
        .height = 1,
        .total_byte_count = 4,
    });
    images.clear(a);

    var scene = Scene.init(a);
    var malformed: [protocol.image_record_size]u8 = @splat(0);
    const malformed_message = try imageMessage(a, protocol.Message.image_define, 2, &malformed);
    defer a.free(malformed_message);
    try std.testing.expectError(Error.InvalidStyle, scene.apply(malformed_message));

    var oversized: [protocol.image_data_header_size + 8]u8 = @splat(0);
    std.mem.writeInt(u32, oversized[12..16], protocol.max_image_fragment_bytes + 1, .little);
    const oversized_message = try imageMessage(a, protocol.Message.image_data, 2, &oversized);
    defer a.free(oversized_message);
    try std.testing.expectError(Error.InvalidMessage, scene.apply(oversized_message));

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    payload.clearRetainingCapacity();
    try protocol.encodeImageData(a, .{
        .image_id = 30,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 1,
        .bytes = "abcd",
    }, &payload);
    const truncated_payload = payload.items[0 .. payload.items.len - 1];
    const truncated = try imageMessage(a, protocol.Message.image_data, 2, truncated_payload);
    defer a.free(truncated);
    try std.testing.expectError(Error.InvalidTable, scene.apply(truncated));
    scene.deinit();
}

test "frame icon validates live resources and clears across scene cleanup" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeImageDefine(a, frontendImageFixture(31, 1), &payload);
    const defined = try imageMessage(a, protocol.Message.image_define, 2, payload.items);
    defer a.free(defined);
    try scene.apply(defined);
    payload.clearRetainingCapacity();
    try protocol.encodeImageData(a, .{
        .image_id = 31,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 1,
        .bytes = "ABCDEFGHIJKLMNOP",
    }, &payload);
    const data = try imageMessage(a, protocol.Message.image_data, 3, payload.items);
    defer a.free(data);
    try scene.apply(data);

    const iconMessage = struct {
        fn call(
            allocator: std.mem.Allocator,
            message_type: u16,
            sequence: u64,
            frame_id: u32,
            icon: protocol.FrameIconPayload,
        ) ![]u8 {
            var bytes: std.ArrayList(u8) = .empty;
            errdefer bytes.deinit(allocator);
            try protocol.encodeFrameIcon(allocator, icon, &bytes);
            defer bytes.deinit(allocator);
            var message: std.ArrayList(u8) = .empty;
            errdefer message.deinit(allocator);
            try protocol.encodeEnvelope(allocator, .{
                .flags = 0,
                .message_type = message_type,
                .sequence = sequence,
                .ack_sequence = 0,
                .session_id = 9,
                .frame_id = frame_id,
                .timestamp_ns = sequence,
            }, bytes.items, &message);
            return message.toOwnedSlice(allocator);
        }
    }.call;

    const present = try iconMessage(a, protocol.Message.frame_icon, 4, 7, .{
        .flags = protocol.FrameIconFlags.present,
        .image_id = 31,
        .image_generation = 1,
        .hotspot_x = 1,
        .hotspot_y = 1,
        .frame_generation = 1,
    });
    defer a.free(present);
    try scene.apply(present);
    try std.testing.expectEqual(protocol.FrameIconFlags.present, scene.icon.?.flags);
    try std.testing.expectEqual(@as(u32, 31), scene.icon.?.image_id);

    const stale = try iconMessage(a, protocol.Message.frame_icon, 5, 7, .{
        .flags = protocol.FrameIconFlags.present,
        .image_id = 31,
        .image_generation = 2,
        .hotspot_x = 1,
        .hotspot_y = 1,
        .frame_generation = 1,
    });
    defer a.free(stale);
    try std.testing.expectError(Error.ResourceNotLive, scene.apply(stale));
    try std.testing.expectEqual(@as(u64, 5), scene.next_sequence.?);
    try std.testing.expectEqual(@as(u32, 1), scene.icon.?.image_generation);

    const absent = try iconMessage(a, protocol.Message.frame_icon, 5, 7, .{ .frame_generation = 1 });
    defer a.free(absent);
    try scene.apply(absent);
    try std.testing.expect(scene.icon == null);

    const restore = try iconMessage(a, protocol.Message.frame_icon, 6, 7, .{
        .flags = protocol.FrameIconFlags.present,
        .image_id = 31,
        .image_generation = 1,
        .hotspot_x = 1,
        .hotspot_y = 1,
        .frame_generation = 1,
    });
    defer a.free(restore);
    try scene.apply(restore);
    scene.resetForResync();
    try std.testing.expect(scene.icon == null);
    try std.testing.expect(scene.images.lookup(31) == null);

    const recreate = try createMessage(a, 2, 8, 8);
    defer a.free(recreate);
    try scene.apply(recreate);
    payload.clearRetainingCapacity();
    try protocol.encodeImageDefine(a, frontendImageFixture(32, 1), &payload);
    const redefined = try imageMessage(a, protocol.Message.image_define, 3, payload.items);
    defer a.free(redefined);
    try scene.apply(redefined);
    payload.clearRetainingCapacity();
    try protocol.encodeImageData(a, .{
        .image_id = 32,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 1,
        .bytes = "ABCDEFGHIJKLMNOP",
    }, &payload);
    const redata = try imageMessage(a, protocol.Message.image_data, 4, payload.items);
    defer a.free(redata);
    try scene.apply(redata);

    const restored = try iconMessage(a, protocol.Message.frame_icon, 5, 8, .{
        .flags = protocol.FrameIconFlags.present,
        .image_id = 32,
        .image_generation = 1,
        .hotspot_x = 1,
        .hotspot_y = 1,
        .frame_generation = 1,
    });
    defer a.free(restored);
    try scene.apply(restored);
    try std.testing.expectEqual(@as(u32, 32), scene.icon.?.image_id);

    var destroy_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, destroy_payload[0..4], 8, .little);
    std.mem.writeInt(u32, destroy_payload[4..8], 1, .little);
    var destroyed: std.ArrayList(u8) = .empty;
    defer destroyed.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_destroy,
        .sequence = 6,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 8,
        .timestamp_ns = 6,
    }, &destroy_payload, &destroyed);
    try scene.apply(destroyed.items);
    try std.testing.expect(scene.icon == null);
}

fn snapshotFontFixture(id: u32, generation: u32) protocol.FontDefine {
    var payload = protocol.FontDefine{
        .font_id = id,
        .generation = generation,
        .family_len = 1,
        .foundry_len = 5,
        .style_len = 5,
        .slant = .roman,
        .spacing = .mono,
        .scalable = true,
        .fixed_pitch = true,
        .pixel_size = 16,
        .point_size_tenths = 120,
        .x_dpi = 96,
        .y_dpi = 96,
        .ascent = 10,
        .descent = 4,
        .line_height = 14,
        .average_advance = 8,
        .space_advance = 8,
        .max_advance = 10,
        .min_advance = 6,
        .baseline_offset = 10,
        .underline_position = -2,
        .underline_thickness = 1,
    };
    payload.family[0] = 'F';
    @memcpy(payload.foundry[0..5], "found");
    @memcpy(payload.style[0..5], "Book1");
    return payload;
}

fn snapshotMessage(
    a: std.mem.Allocator,
    sequence: u64,
    entries: []const protocol.ResourceSnapshotEntry,
) ![]u8 {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeResourceSnapshot(a, .{ .entries = entries }, &payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = protocol.Flags.snapshot,
        .message_type = protocol.Message.resource_snapshot,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 9,
        .timestamp_ns = sequence,
    }, payload.items, &message);
    return message.toOwnedSlice(a);
}

test "snapshot atomically restores concrete resources and tombstones" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    // Seed incomplete and superseded state to prove authoritative replacement.
    try scene.strings.define(a, &scene.resources, .{
        .resource_id = 100,
        .generation = 1,
        .bytes = "old",
    });
    try scene.images.define(a, &scene.resources, frontendImageFixture(20, 1));
    try scene.images.data(a, .{
        .image_id = 20,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 2,
        .bytes = "half",
    });

    const face_wire = try protocol.encodeFaceDefineBytes(.{ .face_id = 11, .generation = 2 });
    const font_wire = try protocol.encodeFontDefineBytes(snapshotFontFixture(12, 3));
    const image_metadata = try protocol.encodeImageDefineBytes(frontendImageFixture(14, 3));
    var image_wire: [protocol.image_record_size + 16]u8 = undefined;
    @memcpy(image_wire[0..protocol.image_record_size], &image_metadata);
    @memcpy(image_wire[protocol.image_record_size..], "sixteen_pixels!!");
    const entries = [_]protocol.ResourceSnapshotEntry{
        .{ .kind = .face, .status = .live, .resource_id = 11, .generation = 2, .payload = &face_wire },
        .{ .kind = .font, .status = .live, .resource_id = 12, .generation = 3, .payload = &font_wire },
        .{ .kind = .image, .status = .live, .resource_id = 14, .generation = 3, .payload = &image_wire },
        .{ .kind = .string, .status = .live, .resource_id = 16, .generation = 4, .payload = "snapshot" },
        .{ .kind = .image, .status = .deleted, .resource_id = 20, .generation = 2, .payload = &.{} },
    };
    const message = try snapshotMessage(a, 2, &entries);
    defer a.free(message);
    try scene.apply(message);

    try std.testing.expectEqual(@as(u32, 2), scene.faces.lookup(11).?.generation);
    try std.testing.expectEqual(@as(u32, 3), scene.fonts.lookup(12).?.generation);
    try std.testing.expectEqualStrings("snapshot", scene.strings.lookup(16).?.bytes);
    const image = scene.images.lookup(14).?;
    try std.testing.expect(image.complete);
    try std.testing.expectEqualStrings("sixteen_pixels!!", image.bytes);
    try std.testing.expectEqual(lifecycle.ResourceStatus.deleted, scene.resources.lookup(.image, 20).?.status);
    try std.testing.expectEqual(@as(u64, 2), scene.stats.control_messages);
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);
}

test "empty snapshot replaces all resources and clears incomplete images" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);

    try scene.strings.define(a, &scene.resources, .{ .resource_id = 1, .generation = 1, .bytes = "old" });
    try scene.faces.define(&scene.resources, .{ .face_id = 2, .generation = 1 });
    try scene.fonts.define(&scene.resources, snapshotFontFixture(3, 1));
    try scene.images.define(a, &scene.resources, frontendImageFixture(4, 1));

    const empty = [_]protocol.ResourceSnapshotEntry{};
    const message = try snapshotMessage(a, 2, &empty);
    defer a.free(message);
    try scene.apply(message);

    try std.testing.expectEqual(@as(usize, 0), scene.strings.len);
    try std.testing.expectEqual(@as(usize, 0), scene.faces.len);
    try std.testing.expectEqual(@as(usize, 0), scene.fonts.len);
    try std.testing.expectEqual(@as(usize, 0), scene.images.len);
    try std.testing.expectEqual(@as(usize, 0), scene.resources.len);
}

test "rejected snapshot is atomic and preserves sequence continuity" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);
    try scene.strings.define(a, &scene.resources, .{ .resource_id = 8, .generation = 1, .bytes = "kept" });

    const face_wire = try protocol.encodeFaceDefineBytes(.{ .face_id = 9, .generation = 1 });
    const duplicate = [_]protocol.ResourceSnapshotEntry{
        .{ .kind = .face, .status = .live, .resource_id = 9, .generation = 1, .payload = &face_wire },
        .{ .kind = .face, .status = .deleted, .resource_id = 9, .generation = 2, .payload = &.{} },
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try std.testing.expectError(Error.InvalidTable, protocol.encodeResourceSnapshot(a, .{ .entries = &duplicate }, &payload));

    const valid = [_]protocol.ResourceSnapshotEntry{
        .{ .kind = .string, .status = .live, .resource_id = 10, .generation = 1, .payload = "new" },
    };
    const message = try snapshotMessage(a, 2, &valid);
    defer a.free(message);
    try std.testing.expectError(Error.InvalidEnvelope, scene.apply(message[0 .. message.len - 1]));
    try std.testing.expectEqual(@as(u64, 2), scene.next_sequence.?);
    try std.testing.expectEqualStrings("kept", scene.strings.lookup(8).?.bytes);
    try std.testing.expectEqual(@as(usize, 0), scene.faces.len);

    const accepted = try snapshotMessage(a, 2, &valid);
    defer a.free(accepted);
    try scene.apply(accepted);
    try std.testing.expectEqualStrings("new", scene.strings.lookup(10).?.bytes);
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);
}

test "snapshot resources clear on resync and scene deinit" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    try scene.apply(create);
    const string = [_]protocol.ResourceSnapshotEntry{
        .{ .kind = .string, .status = .live, .resource_id = 10, .generation = 1, .payload = "owned" },
    };
    const message = try snapshotMessage(a, 2, &string);
    defer a.free(message);
    try scene.apply(message);
    try std.testing.expectEqual(@as(usize, 1), scene.strings.len);
    scene.resetForResync();
    try std.testing.expectEqual(@as(usize, 0), scene.strings.len);
    try std.testing.expectEqual(@as(usize, 0), scene.resources.len);
    scene.deinit();
}

test "atlas resources validate define page glyph and invalidation" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();

    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeAtlasDefine(a, .{
        .atlas_id = 7,
        .generation = 1,
        .width = 64,
        .height = 64,
        .page_count = 1,
    }, &payload);
    const define = try faceMessage(a, protocol.Message.atlas_define, 1, payload.items);
    defer a.free(define);
    try scene.apply(define);
    try std.testing.expect(scene.atlases.lookup(7) != null);

    payload.clearRetainingCapacity();
    try protocol.encodeAtlasPageUpdate(a, .{
        .atlas_id = 7,
        .generation = 1,
        .page_index = 0,
        .page_count = 1,
        .x = 8,
        .y = 8,
        .width = 1,
        .height = 1,
        .bytes = &.{ 1, 2, 3, 4 },
    }, &payload);
    const page = try faceMessage(a, protocol.Message.atlas_page_update, 2, payload.items);
    defer a.free(page);
    try scene.apply(page);

    payload.clearRetainingCapacity();
    try protocol.encodeAtlasGlyphAdd(a, .{
        .atlas_id = 7,
        .generation = 1,
        .glyph_id = 9,
        .font_id = 8,
        .size_px = 16,
        .variation_hash = 42,
        .x = 8,
        .y = 8,
        .width = 1,
        .height = 1,
        .baseline = 1,
        .advance_x = 1,
    }, &payload);
    const glyph = try faceMessage(a, protocol.Message.atlas_glyph_add, 3, payload.items);
    defer a.free(glyph);
    try scene.apply(glyph);
    try std.testing.expectEqual(@as(usize, 1), scene.atlases.lookup(7).?.glyphs.items.len);

    payload.clearRetainingCapacity();
    try protocol.encodeAtlasInvalidate(a, .{
        .flags = protocol.AtlasInvalidateFlags.glyph,
        .atlas_id = 7,
        .generation = 1,
        .target = 9,
    }, &payload);
    const invalidate = try faceMessage(a, protocol.Message.atlas_invalidate, 4, payload.items);
    defer a.free(invalidate);
    try scene.apply(invalidate);
    try std.testing.expectEqual(@as(usize, 0), scene.atlases.lookup(7).?.glyphs.items.len);

    payload.clearRetainingCapacity();
    try protocol.encodeAtlasInvalidate(a, .{
        .flags = protocol.AtlasInvalidateFlags.page,
        .atlas_id = 7,
        .generation = 1,
        .target = 0,
    }, &payload);
    const page_invalidate = try faceMessage(a, protocol.Message.atlas_invalidate, 5, payload.items);
    defer a.free(page_invalidate);
    try scene.apply(page_invalidate);
    try std.testing.expectEqual(@as(usize, 0), scene.atlases.lookup(7).?.pages[0].bytes.len);
    try std.testing.expectEqual(@as(u32, 2), scene.atlases.lookup(7).?.pages[0].revision);

    payload.clearRetainingCapacity();
    try std.testing.expectError(Error.InvalidMessage, protocol.encodeAtlasInvalidate(a, .{
        .flags = protocol.AtlasInvalidateFlags.page |
            protocol.AtlasInvalidateFlags.glyph,
        .atlas_id = 7,
        .generation = 1,
        .target = 1,
    }, &payload));
    try std.testing.expectEqual(@as(u32, 2), scene.atlases.lookup(7).?.pages[0].revision);

    // A page replacement changes both bytes and cache identity even when the
    // atlas generation stays unchanged.
    payload.clearRetainingCapacity();
    try protocol.encodeAtlasPageUpdate(a, .{
        .atlas_id = 7,
        .generation = 1,
        .page_index = 0,
        .page_count = 1,
        .x = 8,
        .y = 8,
        .width = 1,
        .height = 1,
        .bytes = &.{ 9, 8, 7, 6 },
    }, &payload);
    const replacement_page = try faceMessage(a, protocol.Message.atlas_page_update, 6, payload.items);
    defer a.free(replacement_page);
    try scene.apply(replacement_page);
    const page_state = scene.atlases.lookup(7).?;
    try std.testing.expect(page_state.pages[0].revision > 0);
    try std.testing.expectEqual(@as(u32, 9), page_state.pages[0].bytes[0]);
}

test "shaped atlas glyph run validates face font and atlas entries" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var family: [64]u8 = @splat(0);
    @memcpy(family[0..7], "Adaptor");
    var foundry: [32]u8 = @splat(0);
    @memcpy(foundry[0..4], "Test");
    var style: [32]u8 = @splat(0);
    @memcpy(style[0..4], "Mono");
    var font_payload: std.ArrayList(u8) = .empty;
    defer font_payload.deinit(a);
    try protocol.encodeFontDefine(a, .{
        .font_id = 8,
        .generation = 1,
        .family = family,
        .family_len = "Adaptor".len,
        .foundry = foundry,
        .foundry_len = "Test".len,
        .style = style,
        .style_len = "Mono".len,
        .pixel_size = 16,
        .x_dpi = 96,
        .y_dpi = 96,
        .ascent = 10,
        .descent = 3,
        .line_height = 13,
        .average_advance = 6,
        .space_advance = 6,
        .max_advance = 6,
        .min_advance = 6,
        .fixed_pitch = true,
        .spacing = .mono,
    }, &font_payload);
    const font_define = try faceMessage(a, protocol.Message.font_define, 3, font_payload.items);
    defer a.free(font_define);
    try scene.apply(font_define);

    var face_payload: std.ArrayList(u8) = .empty;
    defer face_payload.deinit(a);
    try protocol.encodeFaceDefine(a, .{
        .face_id = 11,
        .generation = 2,
        .presence = .{ .font = true },
        .font_id = 8,
        .font_generation = 1,
    }, &face_payload);
    const face_define = try faceMessage(a, protocol.Message.face_define, 4, face_payload.items);
    defer a.free(face_define);
    try scene.apply(face_define);

    var atlas_payload: std.ArrayList(u8) = .empty;
    defer atlas_payload.deinit(a);
    try protocol.encodeAtlasDefine(a, .{
        .atlas_id = 7,
        .generation = 1,
        .width = 32,
        .height = 8,
        .page_count = 1,
    }, &atlas_payload);
    const atlas_define = try faceMessage(a, protocol.Message.atlas_define, 5, atlas_payload.items);
    defer a.free(atlas_define);
    try scene.apply(atlas_define);

    atlas_payload.clearRetainingCapacity();
    try protocol.encodeAtlasPageUpdate(a, .{
        .atlas_id = 7,
        .generation = 1,
        .page_index = 0,
        .page_count = 1,
        .x = 0,
        .y = 0,
        .width = 32,
        .height = 8,
        .bytes = &([_]u8{255} ** 1024),
    }, &atlas_payload);
    const atlas_page = try faceMessage(a, protocol.Message.atlas_page_update, 6, atlas_payload.items);
    defer a.free(atlas_page);
    try scene.apply(atlas_page);

    atlas_payload.clearRetainingCapacity();
    try protocol.encodeAtlasGlyphAdd(a, .{
        .atlas_id = 7,
        .generation = 1,
        .glyph_id = 101,
        .font_id = 8,
        .size_px = 16,
        .variation_hash = 7,
        .x = 0,
        .y = 0,
        .width = 6,
        .height = 8,
        .baseline = 8,
        .advance_x = 6,
    }, &atlas_payload);
    const atlas_glyph = try faceMessage(a, protocol.Message.atlas_glyph_add, 7, atlas_payload.items);
    defer a.free(atlas_glyph);
    try scene.apply(atlas_glyph);

    var glyphs: [max_shaped_glyphs]ShapedGlyph = undefined;
    glyphs[0] = .{ .glyph_id = 101, .cluster = 0, .x_offset = 0, .y_offset = 0, .advance_x = 6, .advance_y = 0 };
    var shaped_payload: std.ArrayList(u8) = .empty;
    defer shaped_payload.deinit(a);
    try encodeGlyphRun(a, .{
        .schema = 3,
        .flags = glyph_shaped_atlas,
        .run_id = 21,
        .generation = 2,
        .window_id = 100,
        .row_index = 0,
        .face_id = 11,
        .face_generation = 2,
        .font_id = 8,
        .x = 1,
        .y = 1,
        .width = 12,
        .height = 8,
        .text = "",
        .glyphs = glyphs,
        .glyph_count = 1,
    }, &shaped_payload);
    var faceless_payload: std.ArrayList(u8) = .empty;
    defer faceless_payload.deinit(a);
    try std.testing.expectError(Error.InvalidMessage, encodeGlyphRun(a, .{
        .schema = 3,
        .flags = glyph_shaped_atlas,
        .run_id = 22,
        .generation = 2,
        .window_id = 100,
        .row_index = 0,
        .face_id = 0,
        .face_generation = 0,
        .font_id = 8,
        .x = 1,
        .y = 1,
        .width = 12,
        .height = 8,
        .text = "",
        .glyphs = glyphs,
        .glyph_count = 1,
    }, &faceless_payload));

    glyphs[0] = .{ .glyph_id = 999, .cluster = 0, .x_offset = 0, .y_offset = 0, .advance_x = 6, .advance_y = 0 };
    var missing_atlas_payload: std.ArrayList(u8) = .empty;
    defer missing_atlas_payload.deinit(a);
    try encodeGlyphRun(a, .{
        .schema = 3,
        .flags = glyph_shaped_atlas,
        .run_id = 22,
        .generation = 2,
        .window_id = 100,
        .row_index = 0,
        .face_id = 11,
        .face_generation = 2,
        .font_id = 8,
        .x = 1,
        .y = 1,
        .width = 12,
        .height = 8,
        .text = "",
        .glyphs = glyphs,
        .glyph_count = 1,
    }, &missing_atlas_payload);

    glyphs[0] = .{ .glyph_id = 101, .cluster = 0, .x_offset = 0, .y_offset = 0, .advance_x = 6, .advance_y = 0 };
    var missing_atlas_envelope: std.ArrayList(u8) = .empty;
    defer missing_atlas_envelope.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = protocol.Flags.debug,
        .message_type = protocol.Message.glyph_run,
        .sequence = 8,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = 8,
    }, missing_atlas_payload.items, &missing_atlas_envelope);
    const missing_atlas = try missing_atlas_envelope.toOwnedSlice(a);
    defer a.free(missing_atlas);
    try std.testing.expectError(Error.ResourceNotLive, scene.apply(missing_atlas));
    glyphs[0] = .{ .glyph_id = 101, .cluster = 0, .x_offset = 0, .y_offset = 0, .advance_x = 6, .advance_y = 0 };

    var shaped_envelope: std.ArrayList(u8) = .empty;
    defer shaped_envelope.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = protocol.Flags.debug,
        .message_type = protocol.Message.glyph_run,
        .sequence = 8,
        .ack_sequence = 0,
        .session_id = 9,
        .frame_id = 7,
        .timestamp_ns = 8,
    }, shaped_payload.items, &shaped_envelope);
    const shaped = try shaped_envelope.toOwnedSlice(a);
    defer a.free(shaped);
    try scene.apply(shaped);
    try std.testing.expectEqual(@as(usize, 1), scene.glyph_runs.items.len);
    try std.testing.expect(scene.glyph_runs.items[0].shaped);
    try std.testing.expectEqual(@as(usize, 1), scene.glyph_runs.items[0].shaped_count);
    try std.testing.expectEqual(@as(u32, 101), scene.glyph_runs.items[0].shaped_glyphs[0].glyph_id);

    var font_patch_payload: std.ArrayList(u8) = .empty;
    defer font_patch_payload.deinit(a);
    try protocol.encodeFontPatch(a, .{
        .font_id = 8,
        .expected_generation = 1,
        .new_generation = 2,
        .weight = 700,
        .width_percent = 100,
        .pixel_size = 16,
        .point_size_tenths = 0,
        .x_dpi = 96,
        .y_dpi = 96,
        .slant = .roman,
        .spacing = .mono,
        .scalable = false,
        .fixed_pitch = true,
    }, &font_patch_payload);
    const font_patch = try faceMessage(a, protocol.Message.font_patch, 9, font_patch_payload.items);
    defer a.free(font_patch);
    try scene.apply(font_patch);
    try std.testing.expectEqual(@as(usize, 0), scene.glyph_runs.items.len);
}

test "dialog lifecycle validates owner, generation, and cleanup" {
    const a = std.testing.allocator;
    var scene = Scene.init(a);
    defer scene.deinit();
    const create = try createMessage(a, 1, 7, 7);
    defer a.free(create);
    const update = try updateMessage(a, 2, 7, 7, 80, 0);
    defer a.free(update);
    try scene.apply(create);
    try scene.apply(update);

    var title: [protocol.max_dialog_title]u8 = @splat(0);
    var text: [protocol.max_dialog_text]u8 = @splat(0);
    @memcpy(title[0..6], "Delete");
    @memcpy(text[0..11], "Delete file");
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    var state: protocol.DialogState = .{
        .kind = .confirm,
        .dialog_id = 80,
        .dialog_generation = 1,
        .window_id = 100,
        .frame_generation = 1,
        .x = 8,
        .y = 8,
        .width = 32,
        .height = 16,
        .title_len = 6,
        .text_len = 11,
        .buttons = protocol.DialogButtons.yes | protocol.DialogButtons.no,
        .title = title,
        .text = text,
    };
    try protocol.encodeDialogState(a, state, &payload);
    {
        const cross_frame = try windowLifecycleMessage(a, protocol.Message.dialog_open, 3, 8, payload.items);
        defer a.free(cross_frame);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(cross_frame));
    }
    var outside = state;
    outside.width = 81;
    payload.clearRetainingCapacity();
    try protocol.encodeDialogState(a, outside, &payload);
    {
        const invalid = try windowLifecycleMessage(a, protocol.Message.dialog_open, 3, 7, payload.items);
        defer a.free(invalid);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(invalid));
    }

    payload.clearRetainingCapacity();
    try protocol.encodeDialogState(a, state, &payload);
    {
        const open = try windowLifecycleMessage(a, protocol.Message.dialog_open, 3, 7, payload.items);
        defer a.free(open);
        try scene.apply(open);
    }
    {
        const stale = try windowLifecycleMessage(a, protocol.Message.dialog_open, 4, 7, payload.items);
        defer a.free(stale);
        try std.testing.expectError(Error.StaleGeneration, scene.apply(stale));
    }

    state.dialog_generation = 2;
    state.text_len = 6;
    @memset(&state.text, 0);
    @memcpy(state.text[0..6], "Append");
    payload.clearRetainingCapacity();
    try protocol.encodeDialogState(a, state, &payload);
    {
        const replacement = try windowLifecycleMessage(a, protocol.Message.dialog_update, 4, 7, payload.items);
        defer a.free(replacement);
        try scene.apply(replacement);
    }
    try std.testing.expectEqual(@as(u32, 2), scene.dialog.?.dialog_generation);
    try std.testing.expectEqualStrings("Append", scene.dialog.?.text[0..6]);

    const second_window = try windowCreateMessage(a, 5, 7, .{
        .window_id = 101,
        .parent_window_id = 0,
        .x = 0,
        .y = 0,
        .width = 80,
        .height = 60,
        .flags = 2,
        .default_face_id = 0,
        .depth = 0,
    });
    defer a.free(second_window);
    try scene.apply(second_window);
    var moved = state;
    moved.window_id = 101;
    moved.dialog_generation = 3;
    payload.clearRetainingCapacity();
    try protocol.encodeDialogState(a, moved, &payload);
    {
        const wrong_owner = try windowLifecycleMessage(a, protocol.Message.dialog_update, 6, 7, payload.items);
        defer a.free(wrong_owner);
        try std.testing.expectError(Error.InvalidMessage, scene.apply(wrong_owner));
    }
    try std.testing.expectEqual(@as(u32, 2), scene.dialog.?.dialog_generation);
    try std.testing.expectEqual(@as(u64, 100), scene.dialog.?.window_id);
    payload.clearRetainingCapacity();
    try protocol.encodeDialogClose(a, .{
        .reason = .escape,
        .dialog_id = 80,
        .dialog_generation = 2,
        .window_id = 100,
        .frame_generation = 1,
    }, &payload);
    {
        const close = try windowLifecycleMessage(a, protocol.Message.dialog_close, 6, 7, payload.items);
        defer a.free(close);
        try scene.apply(close);
    }
    try std.testing.expect(scene.dialog == null);

    state.dialog_generation = 3;
    payload.clearRetainingCapacity();
    try protocol.encodeDialogState(a, state, &payload);
    {
        const reopened = try windowLifecycleMessage(a, protocol.Message.dialog_open, 7, 7, payload.items);
        defer a.free(reopened);
        try scene.apply(reopened);
    }
    scene.rows.deinit(a);
    scene.rows = .empty;
    const deleted = try windowDeleteMessage(a, 8, 7, 100);
    defer a.free(deleted);
    try scene.apply(deleted);
    try std.testing.expect(scene.dialog == null);
    scene.resetForResync();
    try std.testing.expect(scene.dialog == null);
}

test "bounded text v2 preserves window ownership" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    const line: TextLineV2Wire = .{
        .window_id = 102,
        .row_index = 3,
        .line = "visible ASCII",
    };
    try encodeTextLineV2(a, line, &bytes);
    const decoded = try decodeTextLineV2(bytes.items);
    try std.testing.expectEqual(line.window_id, decoded.window_id);
    try std.testing.expectEqual(line.row_index, decoded.row_index);
    try std.testing.expectEqualStrings(line.line, decoded.line);
    try std.testing.expectError(Error.InvalidTable, decodeTextLineV2(bytes.items[0 .. bytes.items.len - 1]));
    bytes.items[16] = 0;
    try std.testing.expectError(Error.InvalidTable, decodeTextLineV2(bytes.items));
}

test "mode line v1 preserves bounded owner geometry" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    const wire: ModeLineWire = .{
        .window_id = 102,
        .x = 2,
        .y = 20,
        .width = 60,
        .height = 2,
        .flags = mode_line_active,
        .line = "UTF-8 ASCII",
    };
    try encodeModeLineV1(a, wire, &bytes);
    const decoded = try decodeModeLineV1(bytes.items);
    try std.testing.expectEqual(wire.window_id, decoded.window_id);
    try std.testing.expectEqual(wire.x, decoded.x);
    try std.testing.expectEqual(wire.y, decoded.y);
    try std.testing.expectEqual(wire.width, decoded.width);
    try std.testing.expectEqual(wire.height, decoded.height);
    try std.testing.expectEqual(wire.flags, decoded.flags);
    try std.testing.expectEqualStrings(wire.line, decoded.line);
    try std.testing.expectError(Error.InvalidTable, decodeModeLineV1(bytes.items[0 .. bytes.items.len - 1]));
    try std.testing.expectError(Error.InvalidTable, decodeModeLineV1(bytes.items[0 .. mode_line_header_size - 1]));
    bytes.items[25] = 0xff;
    try std.testing.expectError(Error.InvalidTable, decodeModeLineV1(bytes.items));
}

fn textV2Update(
    a: std.mem.Allocator,
    records: []const []const u8,
    include_legacy: bool,
    legacy_record: []const u8,
) ![]u8 {
    const header: protocol.FrameUpdateHeader = .{
        .frame_id = 7,
        .frame_generation = 1,
        .sequence = 2,
        .redisplay_generation = 1,
        .logical_x = 0,
        .logical_y = 0,
        .logical_width = 80,
        .logical_height = 60,
        .physical_x = 0,
        .physical_y = 0,
        .physical_width = 80,
        .physical_height = 60,
        .scale = 1,
        .dpi_x = 96,
        .dpi_y = 96,
        .damage_mode = 2,
        .update_cause = 1,
        .coalesced_count = 0,
        .timestamp_ns = 2,
    };
    var window_bytes: std.ArrayList(u8) = .empty;
    defer window_bytes.deinit(a);
    try encodeWindow(a, .{ .id = 100, .frame_id = 7, .x = 0, .y = 0, .width = 80, .height = 60 }, &window_bytes);
    var row_bytes: std.ArrayList(u8) = .empty;
    defer row_bytes.deinit(a);
    try encodeRow(a, .{ .window_id = 100, .index = 0, .flags = 0, .x = 0, .y = 0, .width = 80, .height = 10, .ascent = 7, .descent = 3, .baseline = 7, .visible_height = 10 }, &row_bytes);
    var damage_bytes: std.ArrayList(u8) = .empty;
    defer damage_bytes.deinit(a);
    try encodeRect(a, .{ .x = 0, .y = 0, .width = 80, .height = 60 }, &damage_bytes);
    var text_bytes: std.ArrayList(u8) = .empty;
    defer text_bytes.deinit(a);
    for (records) |record| try text_bytes.appendSlice(a, record);
    var sections: std.ArrayList(protocol.Section) = .empty;
    defer sections.deinit(a);
    try sections.append(a, .{ .kind = protocol.SectionKind.windows, .records = window_bytes.items });
    try sections.append(a, .{ .kind = protocol.SectionKind.rows, .records = row_bytes.items });
    try sections.append(a, .{ .kind = protocol.SectionKind.damage, .records = damage_bytes.items });
    if (include_legacy) try sections.append(a, .{ .kind = protocol.SectionKind.extension_min, .records = legacy_record });
    try sections.append(a, .{ .kind = protocol.SectionKind.extension_min + 2, .records = text_bytes.items });
    _ = &sections;
    var update: std.ArrayList(u8) = .empty;
    defer update.deinit(a);
    try protocol.encodeFrameUpdate(a, .{ .header = header, .sections = sections.items }, &update);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(a);
    try protocol.encodeEnvelope(a, .{ .flags = protocol.Flags.delta, .message_type = protocol.Message.frame_update, .sequence = 2, .ack_sequence = 0, .session_id = 9, .frame_id = 7, .timestamp_ns = 2 }, update.items, &message);
    return message.toOwnedSlice(a);
}

test "text v2 scene ownership is deterministic" {
    const a = std.testing.allocator;
    var valid_records: [1][]const u8 = undefined;
    var valid_record: std.ArrayList(u8) = .empty;
    defer valid_record.deinit(a);
    try encodeTextLineV2(a, .{ .window_id = 100, .row_index = 0, .line = "one" }, &valid_record);
    valid_records[0] = valid_record.items;

    var duplicate_record: std.ArrayList(u8) = .empty;
    defer duplicate_record.deinit(a);
    try encodeTextLineV2(a, .{ .window_id = 100, .row_index = 0, .line = "two" }, &duplicate_record);
    var duplicate_records: [2][]const u8 = undefined;
    duplicate_records[0] = valid_record.items;
    duplicate_records[1] = duplicate_record.items;

    var unknown_record: std.ArrayList(u8) = .empty;
    defer unknown_record.deinit(a);
    try encodeTextLineV2(a, .{ .window_id = 999, .row_index = 0, .line = "bad" }, &unknown_record);
    var unknown_records: [1][]const u8 = undefined;
    unknown_records[0] = unknown_record.items;

    var missing_record: std.ArrayList(u8) = .empty;
    defer missing_record.deinit(a);
    try encodeTextLineV2(a, .{ .window_id = 100, .row_index = 1, .line = "bad" }, &missing_record);
    var missing_records: [1][]const u8 = undefined;
    missing_records[0] = missing_record.items;

    const cases = [_][]const []const u8{ &valid_records, &duplicate_records, &unknown_records, &missing_records };
    for (cases, 0..) |records, case_index| {
        var scene = Scene.init(a);
        defer scene.deinit();
        const create = try createMessage(a, 1, 7, 7);
        defer a.free(create);
        try scene.apply(create);
        const message = try textV2Update(a, records, false, "");
        defer a.free(message);
        if (case_index == 0) {
            try scene.apply(message);
            try std.testing.expectEqual(@as(u64, 100), scene.text.items[0].window_id);
        } else if (case_index == 1) {
            try std.testing.expectError(Error.InvalidTable, scene.apply(message));
        } else {
            try std.testing.expectError(Error.InvalidMessage, scene.apply(message));
        }
    }

    var legacy_record: std.ArrayList(u8) = .empty;
    defer legacy_record.deinit(a);
    try encodeTextLine(a, .{ .row_index = 0, .line = "legacy" }, &legacy_record);
    var mixed_records: [2][]const u8 = undefined;
    mixed_records[0] = legacy_record.items;
    mixed_records[1] = valid_record.items;
    {
        var scene = Scene.init(a);
        defer scene.deinit();
        const create = try createMessage(a, 1, 7, 7);
        defer a.free(create);
        try scene.apply(create);
        const message = try textV2Update(a, &mixed_records, true, legacy_record.items);
        defer a.free(message);
        try std.testing.expectError(Error.InvalidTable, scene.apply(message));
    }
}
