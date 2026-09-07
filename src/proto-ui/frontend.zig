//! Frontend-owned scene state decoded from EUP.
//!
//! This module is deliberately independent of SDL and GNU Emacs.  SDL reads
//! the scene after the protocol/transport layers validate it; it never invents
//! core display state.

const std = @import("std");
const protocol = @import("protocol.zig");
const lifecycle = @import("lifecycle.zig");

pub const Error = protocol.Error || lifecycle.Error || error{OutOfMemory};

pub const Window = struct {
    id: u64,
    frame_id: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,

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
    row_index: u32,
    bytes: [:0]const u8,
};

pub const max_glyph_text_bytes: usize = 120;
pub const max_glyph_runs: usize = 64;
pub const glyph_record_size: usize = 60;
pub const glyph_delete_record_size: usize = 24;
pub const glyph_debug_fallback: u16 = 1 << 0;

pub const GlyphRun = struct {
    run_id: u32,
    generation: u32,
    window_id: u64,
    row_index: u32,
    face_id: u32,
    face_generation: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    text: [:0]u8,
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
    if ((run.schema != 1 and run.schema != 2) or run.flags != glyph_debug_fallback or
        run.direction != 1 or run.font_id != 0 or run.run_id == 0 or
        run.generation == 0 or run.window_id == 0 or
        !validGlyphRunText(run.text)) return Error.InvalidMessage;
    if ((face_bound and (run.face_id == 0 or run.face_generation == 0)) or
        (!face_bound and (run.face_id != 0 or run.face_generation != 0)))
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
    try out.appendSlice(a, run.text);
}

pub fn decodeGlyphRun(bytes: []const u8) Error!GlyphRunWire {
    if (bytes.len < glyph_record_size + 1 or bytes.len > glyph_record_size + max_glyph_text_bytes)
        return Error.InvalidTable;
    const header = bytes[0..glyph_record_size];
    const text = bytes[glyph_record_size..];
    const schema = std.mem.readInt(u16, header[0..2], .little);
    const flags = std.mem.readInt(u16, header[2..4], .little);
    const direction = std.mem.readInt(u16, header[4..6], .little);
    const face_generation = std.mem.readInt(u32, header[52..56], .little);
    if ((schema != 1 and schema != 2) or flags != glyph_debug_fallback or direction != 1 or
        std.mem.readInt(u16, header[6..8], .little) != 0) return Error.InvalidVersion;
    if ((schema == 1 and (face_generation != 0)) or
        (schema == 2 and face_generation == 0)) return Error.InvalidVersion;
    const run: GlyphRunWire = .{
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
    };
    if (!std.mem.allEqual(u8, header[56..60], 0)) return Error.InvalidReserved;
    if ((schema == 1 and run.face_id != 0) or
        (schema == 2 and run.face_id == 0)) return Error.InvalidMessage;
    if (!run.valid() or !validGlyphRunText(text)) return Error.InvalidMessage;
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

/// Bounded facts/scene text is UTF-8 and excludes C0 controls (including NUL).
/// Printable ASCII remains a strict subset; combining marks and CJK are valid.
pub fn validBoundedUtf8Text(text: []const u8, max_bytes: usize) bool {
    if (!validBoundedUtf8Line(text, max_bytes)) return false;
    return text.len != 0;
}

pub fn validBoundedUtf8Line(text: []const u8, max_bytes: usize) bool {
    if (text.len > max_bytes) return false;
    for (text) |byte| {
        if (byte < 0x20) return false;
    }
    return std.unicode.utf8ValidateSlice(text);
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

fn putU16(out: *std.ArrayList(u8), a: std.mem.Allocator, value: u16) !void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, value, .little);
    try out.appendSlice(a, &bytes);
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
    image_placements: [max_image_placements]ImagePlacement = undefined,
    image_placement_count: usize = 0,
    cursor: ?Cursor = null,
    damage: std.ArrayList(Rect) = .empty,
    text: std.ArrayList(TextLine) = .empty,
    title: ?[:0]u8 = null,
    present: ?PresentHint = null,
    viewport: ?Viewport = null,
    window_tree: ?protocol.WindowTreeSnapshot = null,
    stats: ApplyStats = .{},

    pub fn init(allocator: std.mem.Allocator) Scene {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Scene) void {
        self.windows.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.clearGlyphRuns();
        self.damage.deinit(self.allocator);
        self.strings.deinit(self.allocator);
        self.faces = .{};
        self.fonts = .{};
        self.images.clear(self.allocator);
        for (self.text.items) |line| self.allocator.free(line.bytes);
        self.text.deinit(self.allocator);
        self.clearTitle();
        self.windows = .empty;
        self.rows = .empty;
        self.glyph_runs = .empty;
        self.damage = .empty;
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
        self.present = null;
        self.viewport = null;
        if (self.window_tree) |*tree| protocol.freeWindowTreeSnapshot(self.allocator, tree);
        self.window_tree = null;
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
            if (payload.envelope.sequence != expected) return Error.InvalidSequence;
        }
        const next_sequence = std.math.add(u64, payload.envelope.sequence, 1) catch return Error.InvalidSequence;

        switch (payload.envelope.message_type) {
            protocol.Message.frame_create => try self.applyFrameCreate(payload.envelope, payload.bytes),
            protocol.Message.frame_update => try self.applyFrameUpdate(payload),
            protocol.Message.window_tree_snapshot => try self.applyWindowTreeSnapshot(payload),
            protocol.Message.glyph_run => try self.applyGlyphRun(payload),
            protocol.Message.glyph_run_delete => try self.applyGlyphRunDelete(payload),
            protocol.Message.frame_visibility => try self.applyFrameVisibility(payload),
            protocol.Message.frame_title => try self.applyFrameTitle(payload),
            protocol.Message.frame_focus => try self.applyFrameFocus(payload),
            protocol.Message.frame_destroy => try self.applyFrameDestroy(payload.envelope, payload.bytes),
            protocol.Message.face_define => try self.applyFaceDefine(payload),
            protocol.Message.face_delete => try self.applyFaceDelete(payload),
            protocol.Message.font_define => try self.applyFontDefine(payload),
            protocol.Message.font_delete => try self.applyFontDelete(payload),
            protocol.Message.string_define => try self.applyStringDefine(payload),
            protocol.Message.string_delete => try self.applyStringDelete(payload),
            protocol.Message.image_define => try self.applyImageDefine(payload),
            protocol.Message.image_data => try self.applyImageData(payload),
            protocol.Message.image_delete => try self.applyImageDelete(payload),
            protocol.Message.resource_snapshot => try self.applyResourceSnapshot(payload),
            else => self.stats.control_messages += 1,
        }
        self.next_sequence = next_sequence;
        if (previous_session == null) self.session_id = payload.envelope.session_id;
    }

    fn clearVisualState(self: *Scene) void {
        self.clearTitle();
        self.clearGlyphRuns();
        self.windows.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.damage.deinit(self.allocator);
        for (self.text.items) |line| self.allocator.free(line.bytes);
        self.text.deinit(self.allocator);
        self.windows = .empty;
        self.rows = .empty;
        self.glyph_runs = .empty;
        self.damage = .empty;
        self.text = .empty;
        self.frame_header = null;
        self.cursor = null;
        self.present = null;
        self.viewport = null;
        if (self.window_tree) |*tree| protocol.freeWindowTreeSnapshot(self.allocator, tree);
        self.window_tree = null;
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

        if (wire.face_id != 0) {
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
        const next: GlyphRun = .{
            .run_id = wire.run_id,
            .generation = wire.generation,
            .window_id = wire.window_id,
            .row_index = wire.row_index,
            .face_id = wire.face_id,
            .face_generation = wire.face_generation,
            .x = wire.x,
            .y = wire.y,
            .width = wire.width,
            .height = wire.height,
            .text = owned,
        };
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

    fn applyFaceDefine(self: *Scene, payload: protocol.Payload) Error!void {
        const face = try protocol.decodeFaceDefine(payload.bytes);
        const old = self.faces.lookup(face.face_id);
        const old_generation: ?u32 = if (old) |resource| resource.generation else null;
        try self.faces.define(&self.resources, face);
        if (old_generation) |generation| self.removeGlyphRunsForFace(face.face_id, generation);
        self.stats.control_messages += 1;
    }

    fn applyFaceDelete(self: *Scene, payload: protocol.Payload) Error!void {
        const face = try protocol.decodeFaceDelete(payload.bytes);
        try self.faces.delete(&self.resources, face);
        self.removeGlyphRunsForFace(face.face_id, face.generation);
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
        try self.fonts.define(&self.resources, font);
        self.stats.control_messages += 1;
    }

    fn applyFontDelete(self: *Scene, payload: protocol.Payload) Error!void {
        const font = try protocol.decodeFontDelete(payload.bytes);
        try self.fonts.delete(&self.resources, font);
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
                    .fringe_bitmap, .icon => return Error.Unsupported,
                },
            }
        }

        var old_strings = self.strings;
        var old_images = self.images;
        self.strings = strings;
        self.faces = faces;
        self.fonts = fonts;
        self.images = images;
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
        var image_placements: [max_image_placements]ImagePlacement = undefined;
        var image_placement_count: usize = 0;
        var cursor: ?Cursor = null;
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
                    if (section.records.len != cursor_record_size or cursor != null) return Error.InvalidTable;
                    const wire = try decodeCursor(section.records);
                    const owner = findWindow(windows.items, wire.window_id) orelse return Error.InvalidMessage;
                    if (!inside(wire.x, wire.width, owner.width) or
                        !inside(wire.y, wire.height, owner.height))
                        return Error.InvalidMessage;
                    cursor = wire;
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
                    var offset: usize = 0;
                    while (offset < section.records.len) {
                        if (section.records.len - offset < 8) return Error.InvalidTable;
                        const length = std.mem.readInt(u32, section.records[offset + 4 ..][0..4], .little);
                        const record_length = 8 + length;
                        if (record_length > section.records.len - offset) return Error.InvalidTable;
                        const wire = try decodeTextLine(section.records[offset..][0..record_length]);
                        for (text.items) |old| {
                            if (old.row_index == wire.row_index) return Error.InvalidTable;
                        }
                        if (wire.row_index >= rows.items.len) return Error.InvalidMessage;
                        const owned = try self.allocator.dupeZ(u8, wire.line);
                        errdefer self.allocator.free(owned);
                        try text.append(self.allocator, .{ .row_index = wire.row_index, .bytes = owned });
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
        const old_text = self.text;
        self.windows = windows;
        self.rows = rows;
        self.glyph_runs = .empty;
        self.damage = damage;
        self.text = text;
        self.image_placements = image_placements;
        self.image_placement_count = image_placement_count;
        windows = old_windows;
        rows = old_rows;
        // FRAME_UPDATE is authoritative visual state.  Free the old owned
        // glyph storage only after the complete update has validated.
        for (old_glyph_runs.items) |run| self.allocator.free(run.text);
        old_glyph_runs.deinit(self.allocator);
        damage = old_damage;
        text = old_text;
        self.frame_header = update.header;
        self.cursor = cursor;
        self.present = present;
        self.viewport = viewport;
        self.stats.frame_updates += 1;
    }
};

fn inside(offset: i32, extent: i32, limit: i32) bool {
    return offset >= 0 and extent >= 0 and offset <= limit and extent <= limit - offset;
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
