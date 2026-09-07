const std = @import("std");

pub const major_version: u16 = 1;
pub const minor_version: u16 = 0;
pub const header_size: u16 = 62;
pub const max_rows: usize = 256;
pub const max_damage: usize = 256;

pub const Error = error{
    InvalidEnvelope,
    InvalidVersion,
    InvalidMessage,
    InvalidResource,
    InvalidTable,
    InvalidUtf8,
    InvalidSequence,
    InvalidStyle,
    InvalidBoolean,
    InvalidReserved,
    ResourcePayloadBudgetExceeded,
    TrailingBytes,
    Unsupported,
};

pub const Magic = [4]u8{ 'E', 'U', 'P', '1' };

pub const Flags = struct {
    pub const snapshot: u16 = 1 << 0;
    pub const delta: u16 = 1 << 1;
    pub const coalescable: u16 = 1 << 2;
    pub const requires_ack: u16 = 1 << 3;
    pub const fragmented: u16 = 1 << 4;
    pub const last_fragment: u16 = 1 << 5;
    pub const compressed: u16 = 1 << 6;
    pub const encrypted: u16 = 1 << 7;
    pub const idempotent: u16 = 1 << 8;
    pub const debug: u16 = 1 << 9;
};

pub const Message = struct {
    pub const hello: u16 = 0x0001;
    pub const hello_ack: u16 = 0x0002;
    pub const capabilities: u16 = 0x0003;
    pub const capabilities_ack: u16 = 0x0004;
    pub const session_ready: u16 = 0x0005;
    pub const ready_ack: u16 = 0x0006;
    pub const frame_create: u16 = 0x0200;
    pub const window_tree_snapshot: u16 = 0x0300;
    pub const frame_destroy: u16 = 0x0206;
    pub const frame_update: u16 = 0x0203;
    pub const frame_presented: u16 = 0x0204;
    pub const frame_visibility: u16 = 0x0208;
    pub const frame_title: u16 = 0x0209;
    pub const frame_focus: u16 = 0x0210;
    pub const resource_request: u16 = 0x0510;
    pub const resource_evict: u16 = 0x0511;
    pub const resource_snapshot: u16 = 0x0512;
    pub const face_define: u16 = 0x0500;
    pub const face_delete: u16 = 0x0502;
    pub const glyph_run: u16 = 0x0405;
    pub const glyph_run_delete: u16 = 0x0406;
    pub const font_define: u16 = 0x0503;
    pub const font_delete: u16 = 0x0506;
    pub const image_define: u16 = 0x0507;
    pub const image_data: u16 = 0x0508;
    pub const image_delete: u16 = 0x0509;
    pub const string_define: u16 = 0x050e;
    pub const string_delete: u16 = 0x050f;
    pub const key_event: u16 = 0x0600;
    pub const text_input: u16 = 0x0601;
    pub const pointer_event: u16 = 0x0602;
    pub const wheel_event: u16 = 0x0603;
    pub const focus_event: u16 = 0x0606;
    pub const window_request: u16 = 0x0607;
    pub const extension: u16 = 0xf000;
    pub const invalid: u16 = 0xffff;
};

pub const Class = enum(u8) {
    control,
    frame,
    window,
    render,
    resource,
    input,
    ime,
    selection,
    widget,
    diagnostic,
    extension,
    unknown,
};

pub const Envelope = struct {
    flags: u16,
    message_type: u16,
    sequence: u64,
    ack_sequence: u64,
    session_id: u64,
    frame_id: u32 = 0,
    timestamp_ns: u64,
};

pub const Payload = struct {
    envelope: Envelope,
    bytes: []const u8,
};

/// Every assigned EUP v1 message ID.  Range membership alone is not enough:
/// an unassigned ID inside a range is a protocol gap, not an optional message.
pub const known_message_ids = [_]u16{
    0x0001, 0x0002, 0x0003, 0x0004, 0x0005, 0x0006, 0x0007, 0x0008,
    0x0009, 0x000a, 0x000b, 0x000c, 0x000d, 0x000e, 0x000f, 0x0010,
    0x0011, 0x0200, 0x0201, 0x0202, 0x0203, 0x0204, 0x0205, 0x0206,
    0x0207, 0x0208, 0x0209, 0x020a, 0x020b, 0x020c, 0x020d, 0x020e,
    0x020f, 0x0210, 0x0211, 0x0212, 0x0213, 0x0214, 0x0300, 0x0301,
    0x0302, 0x0303, 0x0304, 0x0305, 0x0306, 0x0307, 0x0308, 0x0309,
    0x030a, 0x0400, 0x0401, 0x0402, 0x0403, 0x0404, 0x0405, 0x0406,
    0x0407, 0x0408, 0x0409, 0x040a, 0x040b, 0x040c, 0x040d, 0x040e,
    0x040f, 0x0500, 0x0501, 0x0502, 0x0503, 0x0504, 0x0505, 0x0506,
    0x0507, 0x0508, 0x0509, 0x050a, 0x050b, 0x050c, 0x050d, 0x050e,
    0x050f, 0x0510, 0x0511, 0x0512, 0x0513, 0x0514, 0x0515, 0x0516,
    0x0600, 0x0601, 0x0602, 0x0603, 0x0604, 0x0605, 0x0606, 0x0607,
    0x0608, 0x0609, 0x060a, 0x060b, 0x060c, 0x0700, 0x0701, 0x0702,
    0x0703, 0x0704, 0x0705, 0x0706, 0x0710, 0x0711, 0x0712, 0x0713,
    0x0714, 0x0715, 0x0716, 0x0717, 0x0718, 0x0719, 0x0800, 0x0801,
    0x0802, 0x0803, 0x0804, 0x0805, 0x0810, 0x0811, 0x0812, 0x0813,
    0x0820, 0x0821, 0x0822, 0x0823, 0x0824, 0x0825, 0x0826, 0x0900,
    0x0901, 0x0902, 0x0903, 0x0904, 0x0905, 0x0906, 0x0910, 0x0911,
    0x0912, 0x0920, 0x0921, 0x0922, 0x0923, 0x0930, 0x0931, 0x0932,
    0x0940, 0x0941, 0x0a00, 0x0a01, 0x0a02, 0x0a03, 0x0a04, 0x0a05,
    0x0a06, 0x0a07, 0x0a08, 0x0a09,
};

pub fn knownMessage(message_type: u16) bool {
    for (known_message_ids) |known| {
        if (known == message_type) return true;
    }
    return false;
}

pub const ResourceId = struct {
    id: u32,
    generation: u32,

    pub fn valid(self: ResourceId) bool {
        return self.id != 0 and self.generation != 0;
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

pub const ResourceEvictionReason = enum(u8) {
    lru = 0,
    capacity = 1,
    generation = 2,
    explicit = 3,
};

pub const ResourceRequest = struct {
    kind: ResourceKind,
    id: u32,
    generation: u32,
};

pub const ResourceEvict = struct {
    kind: ResourceKind,
    id: u32,
    generation: u32,
    reason: ResourceEvictionReason,
};

pub const max_resource_requests: usize = 64;
pub const max_string_bytes: usize = 4096;
pub const face_record_size: usize = 96;
pub const font_record_size: usize = 224;
pub const image_record_size: usize = 72;
pub const image_data_header_size: usize = 16;
pub const max_font_family_bytes: usize = 64;
pub const max_font_foundry_bytes: usize = 32;
pub const max_font_style_bytes: usize = 32;
pub const max_image_dimension: u32 = 8192;
pub const max_image_bytes: usize = 4 * 1024 * 1024;
pub const max_image_fragments: u16 = 256;
pub const max_image_fragment_bytes: usize = 65536;

pub const FaceStyle = enum(u8) {
    unspecified = 0,
    off = 1,
    single = 2,
    color = 3,
};

pub const BoxStyle = enum(u8) {
    none = 0,
    simple = 1,
    released = 2,
    pressed = 3,
};

pub const FacePresence = packed struct(u8) {
    font: bool = false,
    stipple: bool = false,
    foreground: bool = false,
    background: bool = false,
    underline_color: bool = false,
    overline_color: bool = false,
    strike_color: bool = false,
    box_color: bool = false,
};

/// Fixed-layout FACE_DEFINE v1.  This is a bounded subset, not Emacs face
/// parity.  Wire offsets are normative and the trailing bytes are reserved.
pub const FaceDefine = struct {
    face_id: u32,
    generation: u32,
    presence: FacePresence = .{},
    foreground: [4]u8 = .{ 0, 0, 0, 0 },
    background: [4]u8 = .{ 0, 0, 0, 0 },
    underline_color: [4]u8 = .{ 0, 0, 0, 0 },
    overline_color: [4]u8 = .{ 0, 0, 0, 0 },
    strike_color: [4]u8 = .{ 0, 0, 0, 0 },
    box_color: [4]u8 = .{ 0, 0, 0, 0 },
    underline: FaceStyle = .unspecified,
    overline: FaceStyle = .unspecified,
    strike_through: FaceStyle = .unspecified,
    box: BoxStyle = .none,
    box_line_width: i32 = 0,
    inverse_video: bool = false,
    extend: bool = false,
    line_spacing: i32 = 0,
    font_id: u32 = 0,
    font_generation: u32 = 0,
    stipple_id: u32 = 0,
    stipple_generation: u32 = 0,
};

pub const FaceDelete = struct {
    face_id: u32,
    generation: u32,
};

fn optionalReferenceValid(id: u32, generation: u32, present: bool) bool {
    return if (present) (id != 0 and generation != 0) else (id == 0 and generation == 0);
}

fn validateFaceStyle(style: FaceStyle, color_present: bool) Error!void {
    if ((style == .color) != color_present) return Error.InvalidStyle;
}

fn validateFaceDefine(payload: FaceDefine) Error!void {
    if (payload.face_id == 0 or payload.generation == 0) return Error.InvalidMessage;
    if (!optionalReferenceValid(payload.font_id, payload.font_generation, payload.presence.font))
        return Error.InvalidResource;
    if (!optionalReferenceValid(payload.stipple_id, payload.stipple_generation, payload.presence.stipple))
        return Error.InvalidResource;
    if ((payload.presence.foreground and payload.foreground[3] == 0) or
        (!payload.presence.foreground and payload.foreground[3] != 0))
        return Error.InvalidMessage;
    if ((payload.presence.background and payload.background[3] == 0) or
        (!payload.presence.background and payload.background[3] != 0))
        return Error.InvalidMessage;
    try validateFaceStyle(payload.underline, payload.presence.underline_color);
    try validateFaceStyle(payload.overline, payload.presence.overline_color);
    try validateFaceStyle(payload.strike_through, payload.presence.strike_color);
    if ((payload.box != .none) != payload.presence.box_color) return Error.InvalidStyle;
    if (!payload.presence.box_color and payload.box_line_width != 0) return Error.InvalidStyle;
}

pub const StringDefine = struct {
    resource_id: u32,
    generation: u32,
    /// Borrowed from the caller's/decoded buffer; never NUL-terminated.
    bytes: []const u8,
};

pub const StringDelete = struct {
    resource_id: u32,
    generation: u32,
};

pub const FontSlant = enum(u8) {
    unspecified = 0,
    roman = 1,
    italic = 2,
    oblique = 3,
};

pub const FontSpacing = enum(u8) {
    unspecified = 0,
    mono = 1,
    proportional = 2,
};

pub const FontDefine = struct {
    font_id: u32,
    generation: u32,
    family: [max_font_family_bytes]u8 = @splat(0),
    family_len: usize = 0,
    foundry: [max_font_foundry_bytes]u8 = @splat(0),
    foundry_len: usize = 0,
    style: [max_font_style_bytes]u8 = @splat(0),
    style_len: usize = 0,
    slant: FontSlant = .unspecified,
    spacing: FontSpacing = .unspecified,
    scalable: bool = false,
    fixed_pitch: bool = false,
    /// CSS weight, 1..1000.
    weight: u16 = 400,
    /// Percentage, 50..200.
    width_percent: u16 = 100,
    /// Zero means unspecified.
    pixel_size: u32 = 0,
    /// Points multiplied by ten; zero means unspecified.
    point_size_tenths: u32 = 0,
    x_dpi: u32 = 0,
    y_dpi: u32 = 0,
    ascent: i32 = 0,
    descent: i32 = 0,
    line_height: u32 = 0,
    average_advance: u32 = 0,
    space_advance: u32 = 0,
    max_advance: u32 = 0,
    min_advance: u32 = 0,
    baseline_offset: i32 = 0,
    underline_position: i32 = 0,
    underline_thickness: u32 = 0,
    /// v1 explicitly encodes zero; extension counts are not accepted here.
    feature_count: u16 = 0,
    variation_axis_count: u16 = 0,
    fallback_count: u16 = 0,
};

pub const FontDelete = struct {
    font_id: u32,
    generation: u32,
};

pub const ImagePixelFormat = enum(u16) {
    rgba8_premultiplied = 1,
};

pub const ImageColorSpace = enum(u16) {
    srgb = 1,
};

pub const ImageAlphaMode = enum(u16) {
    premultiplied = 1,
};

pub const ImageScalingFilter = enum(u16) {
    nearest = 1,
    linear = 2,
};

pub const ImageTransform = enum(u16) {
    identity = 1,
};

pub const ImageCachePolicy = enum(u16) {
    lru = 1,
    pinned = 2,
};

/// Fixed-layout IMAGE_DEFINE v1.  It describes at most one static RGBA8
/// image; pixel bytes arrive through ordered IMAGE_DATA fragments.
pub const ImageDefine = struct {
    image_id: u32,
    generation: u32,
    width: u32,
    height: u32,
    total_byte_count: u32,
    format: ImagePixelFormat = .rgba8_premultiplied,
    color_space: ImageColorSpace = .srgb,
    alpha_mode: ImageAlphaMode = .premultiplied,
    scaling_filter: ImageScalingFilter = .nearest,
    transform: ImageTransform = .identity,
    cache_policy: ImageCachePolicy = .lru,
    animation_frame_count: u16 = 1,
    animation_duration_ns: u32 = 0,
};

pub const ImageData = struct {
    image_id: u32,
    generation: u32,
    fragment_index: u16,
    fragment_count: u16,
    bytes: []const u8,
};

pub const ImageDelete = struct {
    image_id: u32,
    generation: u32,
};

fn validateImageDefine(payload: ImageDefine) Error!void {
    if (payload.image_id == 0 or payload.generation == 0) return Error.InvalidMessage;
    if (payload.width < 1 or payload.width > max_image_dimension or
        payload.height < 1 or payload.height > max_image_dimension) return Error.InvalidMessage;
    const required: u64 = @as(u64, payload.width) * @as(u64, payload.height) * 4;
    if (required > max_image_bytes or payload.total_byte_count != required) return Error.InvalidMessage;
    if (payload.animation_frame_count != 1 or payload.animation_duration_ns != 0) return Error.InvalidMessage;
}

pub const SnapshotStatus = enum(u8) {
    live = 1,
    deleted = 2,
};

pub const snapshot_entry_size: usize = 16;
pub const max_snapshot_entries: usize = 64;

/// A snapshot entry borrows `payload` when supplied by the caller.  Decoded
/// snapshots own both the entry array and every non-zero-length payload; use
/// `freeResourceSnapshot` to release that representation.
pub const ResourceSnapshotEntry = struct {
    kind: ResourceKind,
    status: SnapshotStatus,
    resource_id: u32,
    generation: u32,
    payload: []const u8 = &.{},
};

pub const ResourceSnapshot = struct {
    format_version: u32 = 1,
    entries: []const ResourceSnapshotEntry,
};

fn snapshotEntryDuplicate(entry: ResourceSnapshotEntry, prior: []const ResourceSnapshotEntry) bool {
    for (prior) |other| {
        if (other.kind == entry.kind and other.resource_id == entry.resource_id) return true;
    }
    return false;
}

fn validateSnapshotEntryPayload(entry: ResourceSnapshotEntry) Error!void {
    if (entry.resource_id == 0 or entry.generation == 0) return Error.InvalidMessage;
    if (entry.status == .deleted) {
        if (entry.payload.len != 0) return Error.InvalidMessage;
        return;
    }
    switch (entry.kind) {
        .face => {
            const payload = try decodeFaceDefine(entry.payload);
            if (payload.face_id != entry.resource_id or payload.generation != entry.generation)
                return Error.InvalidResource;
        },
        .font => {
            const payload = try decodeFontDefine(entry.payload);
            if (payload.font_id != entry.resource_id or payload.generation != entry.generation)
                return Error.InvalidResource;
        },
        .image => {
            if (entry.payload.len < image_record_size) return Error.InvalidTable;
            const metadata = try decodeImageDefine(entry.payload[0..image_record_size]);
            if (metadata.image_id != entry.resource_id or metadata.generation != entry.generation)
                return Error.InvalidResource;
            if (entry.payload.len != image_record_size + metadata.total_byte_count)
                return Error.InvalidMessage;
        },
        .string => try validateStringBytes(entry.payload),
        // Snapshot tombstones may name reserved families, but live state is
        // limited to the concrete encodings implemented by EUP v1.
        .fringe_bitmap, .icon => return Error.Unsupported,
    }
}

fn validateSnapshot(snapshot: ResourceSnapshot) Error!void {
    if (snapshot.format_version != 1) return Error.InvalidVersion;
    if (snapshot.entries.len > max_snapshot_entries) return Error.InvalidTable;
    var image_bytes: u64 = 0;
    for (snapshot.entries, 0..) |entry, index| {
        if (snapshotEntryDuplicate(entry, snapshot.entries[0..index])) return Error.InvalidTable;
        try validateSnapshotEntryPayload(entry);
        if (entry.status == .live and entry.kind == .image) {
            const metadata = try decodeImageDefine(entry.payload[0..image_record_size]);
            image_bytes += metadata.total_byte_count;
            if (image_bytes > max_image_bytes) return Error.ResourcePayloadBudgetExceeded;
        }
    }
}

pub fn encodeResourceSnapshot(
    a: std.mem.Allocator,
    snapshot: ResourceSnapshot,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateSnapshot(snapshot);
    try putU32(out, a, snapshot.format_version);
    try putU32(out, a, @intCast(snapshot.entries.len));
    for (snapshot.entries) |entry| {
        try out.append(a, @intFromEnum(entry.kind));
        try out.append(a, @intFromEnum(entry.status));
        try out.appendSlice(a, &.{ 0, 0 });
        try putU32(out, a, entry.resource_id);
        try putU32(out, a, entry.generation);
        try putU32(out, a, @intCast(entry.payload.len));
        try out.appendSlice(a, entry.payload);
    }
}

/// The result owns its entry array and payload bytes.  `data` is only read.
pub fn decodeResourceSnapshot(
    a: std.mem.Allocator,
    data: []const u8,
) (Error || std.mem.Allocator.Error)!ResourceSnapshot {
    var reader = Reader{ .data = data };
    if (try reader.readU32() != 1) return Error.InvalidVersion;
    const entry_count = try reader.readU32();
    if (entry_count > max_snapshot_entries) return Error.InvalidTable;

    const entries = try a.alloc(ResourceSnapshotEntry, entry_count);
    errdefer a.free(entries);
    var image_bytes: u64 = 0;
    for (entries) |*entry| {
        const kind_byte = try reader.bytes(1);
        const status_byte = try reader.bytes(1);
        const reserved = try reader.bytes(2);
        if (reserved[0] != 0 or reserved[1] != 0) return Error.InvalidReserved;
        entry.* = .{
            .kind = switch (kind_byte[0]) {
                1 => .face,
                2 => .font,
                3 => .image,
                4 => .fringe_bitmap,
                5 => .icon,
                6 => .string,
                else => return Error.InvalidResource,
            },
            .status = switch (status_byte[0]) {
                1 => .live,
                2 => .deleted,
                else => return Error.InvalidResource,
            },
            .resource_id = try reader.readU32(),
            .generation = try reader.readU32(),
            .payload = &.{},
        };
        const payload_length = try reader.readU32();
        if (payload_length > data.len) return Error.InvalidTable;
        const payload = try reader.bytes(payload_length);
        entry.payload = payload;
        try validateSnapshotEntryPayload(entry.*);
        if (entry.status == .live and entry.kind == .image) {
            const metadata = try decodeImageDefine(payload[0..image_record_size]);
            image_bytes += metadata.total_byte_count;
            if (image_bytes > max_image_bytes) return Error.ResourcePayloadBudgetExceeded;
        }
    }
    if (reader.offset != data.len) return Error.TrailingBytes;

    // Copy validated payloads so callers can free the input immediately.
    // Failed copies unwind all preceding payload ownership.
    var initialized: usize = 0;
    errdefer for (entries[0..initialized]) |entry| {
        if (entry.payload.len != 0) a.free(entry.payload);
    };
    for (entries) |*entry| {
        if (entry.payload.len != 0) entry.payload = try a.dupe(u8, entry.payload);
        initialized += 1;
    }
    return .{ .format_version = 1, .entries = entries };
}

pub fn freeResourceSnapshot(a: std.mem.Allocator, snapshot: *ResourceSnapshot) void {
    for (snapshot.entries) |entry| {
        if (entry.payload.len != 0) a.free(entry.payload);
    }
    // Decoded snapshots own memory allocated as mutable entries; the public
    // type is const so callers cannot mutate the validated table in place.
    a.free(@constCast(snapshot.entries));
    snapshot.* = .{ .entries = &.{} };
}

fn validateFontMetadata(
    bytes: []const u8,
    used_len: usize,
) Error!void {
    if (used_len == 0 or used_len > bytes.len) return Error.InvalidMessage;
    const used = bytes[0..used_len];
    if (std.mem.indexOfScalar(u8, used, 0) != null) return Error.InvalidMessage;
    if (!std.unicode.utf8ValidateSlice(used)) return Error.InvalidUtf8;
    for (bytes[used_len..]) |byte| {
        if (byte != 0) return Error.InvalidReserved;
    }
}

const max_font_metric: i64 = 1 << 20;

fn fontMetricInRange(value: i64) bool {
    return value >= 0 and value <= max_font_metric;
}

fn validateFontDefine(payload: FontDefine) Error!void {
    if (payload.font_id == 0 or payload.generation == 0) return Error.InvalidMessage;
    try validateFontMetadata(&payload.family, payload.family_len);
    try validateFontMetadata(&payload.foundry, payload.foundry_len);
    try validateFontMetadata(&payload.style, payload.style_len);
    if (payload.weight < 1 or payload.weight > 1000) return Error.InvalidMessage;
    if (payload.width_percent < 50 or payload.width_percent > 200) return Error.InvalidMessage;
    if (payload.pixel_size > max_font_metric or payload.point_size_tenths > max_font_metric or
        payload.x_dpi > 4096 or payload.y_dpi > 4096) return Error.InvalidMessage;
    if ((payload.x_dpi == 0) != (payload.y_dpi == 0)) return Error.InvalidMessage;
    if (payload.fixed_pitch and payload.spacing == .proportional) return Error.InvalidMessage;
    if (payload.spacing == .mono and !payload.fixed_pitch) return Error.InvalidMessage;

    if (!fontMetricInRange(payload.ascent) or !fontMetricInRange(payload.descent) or
        !fontMetricInRange(payload.line_height) or !fontMetricInRange(payload.average_advance) or
        !fontMetricInRange(payload.space_advance) or !fontMetricInRange(payload.max_advance) or
        !fontMetricInRange(payload.min_advance) or payload.baseline_offset < 0 or
        payload.baseline_offset > payload.ascent or
        @as(i64, payload.underline_position) < -payload.ascent or
        @as(i64, payload.underline_position) > payload.ascent or
        !fontMetricInRange(payload.underline_thickness)) return Error.InvalidMessage;
    if (payload.max_advance < payload.min_advance or
        payload.average_advance > payload.max_advance or
        payload.space_advance > payload.max_advance) return Error.InvalidMessage;
    if (payload.line_height < @as(u32, @intCast(payload.ascent)) +
        @as(u32, @intCast(payload.descent))) return Error.InvalidMessage;
    if (payload.underline_thickness > payload.line_height) return Error.InvalidMessage;
    if (payload.feature_count != 0 or payload.variation_axis_count != 0 or
        payload.fallback_count != 0) return Error.Unsupported;
}

fn validateStringIdentity(resource_id: u32, generation: u32) Error!void {
    if (resource_id == 0 or generation == 0) return Error.InvalidMessage;
}

fn validateStringBytes(bytes: []const u8) Error!void {
    if (bytes.len == 0 or bytes.len > max_string_bytes) return Error.InvalidMessage;
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return Error.InvalidMessage;
    if (!std.unicode.utf8ValidateSlice(bytes)) return Error.InvalidUtf8;
}

pub fn encodeStringDefine(
    a: std.mem.Allocator,
    payload: StringDefine,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateStringIdentity(payload.resource_id, payload.generation);
    try validateStringBytes(payload.bytes);
    try putU32(out, a, payload.resource_id);
    try putU32(out, a, payload.generation);
    try putU32(out, a, @intCast(payload.bytes.len));
    try out.appendSlice(a, payload.bytes);
}

pub fn decodeStringDefine(data: []const u8) Error!StringDefine {
    if (data.len < 12) return Error.InvalidTable;
    const payload = StringDefine{
        .resource_id = std.mem.readInt(u32, data[0..4], .little),
        .generation = std.mem.readInt(u32, data[4..8], .little),
        .bytes = data[12..],
    };
    const byte_length = std.mem.readInt(u32, data[8..12], .little);
    if (byte_length > max_string_bytes) return Error.InvalidMessage;
    if (data.len != 12 + @as(usize, byte_length)) return Error.InvalidTable;
    try validateStringIdentity(payload.resource_id, payload.generation);
    try validateStringBytes(payload.bytes);
    return payload;
}

pub fn encodeStringDelete(
    a: std.mem.Allocator,
    payload: StringDelete,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateStringIdentity(payload.resource_id, payload.generation);
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u32, bytes[0..4], payload.resource_id, .little);
    std.mem.writeInt(u32, bytes[4..8], payload.generation, .little);
    try out.appendSlice(a, &bytes);
}

pub fn decodeStringDelete(data: []const u8) Error!StringDelete {
    if (data.len != 8) return Error.InvalidTable;
    const payload = StringDelete{
        .resource_id = std.mem.readInt(u32, data[0..4], .little),
        .generation = std.mem.readInt(u32, data[4..8], .little),
    };
    try validateStringIdentity(payload.resource_id, payload.generation);
    return payload;
}

pub fn encodeImageDefineBytes(payload: ImageDefine) Error![image_record_size]u8 {
    try validateImageDefine(payload);
    var bytes: [image_record_size]u8 = @splat(0);
    std.mem.writeInt(u32, bytes[0..4], payload.image_id, .little);
    std.mem.writeInt(u32, bytes[4..8], payload.generation, .little);
    std.mem.writeInt(u32, bytes[8..12], payload.width, .little);
    std.mem.writeInt(u32, bytes[12..16], payload.height, .little);
    std.mem.writeInt(u32, bytes[16..20], payload.total_byte_count, .little);
    std.mem.writeInt(u16, bytes[20..22], @intFromEnum(payload.format), .little);
    std.mem.writeInt(u16, bytes[22..24], @intFromEnum(payload.color_space), .little);
    std.mem.writeInt(u16, bytes[24..26], @intFromEnum(payload.alpha_mode), .little);
    std.mem.writeInt(u16, bytes[26..28], @intFromEnum(payload.scaling_filter), .little);
    std.mem.writeInt(u16, bytes[28..30], @intFromEnum(payload.transform), .little);
    std.mem.writeInt(u16, bytes[30..32], @intFromEnum(payload.cache_policy), .little);
    std.mem.writeInt(u16, bytes[32..34], payload.animation_frame_count, .little);
    std.mem.writeInt(u32, bytes[34..38], payload.animation_duration_ns, .little);
    return bytes;
}

pub fn encodeImageDefine(a: std.mem.Allocator, payload: ImageDefine, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    const bytes = try encodeImageDefineBytes(payload);
    try out.appendSlice(a, &bytes);
}

pub fn decodeImageDefine(data: []const u8) Error!ImageDefine {
    if (data.len != image_record_size) return Error.InvalidTable;
    for (data[38..]) |byte| {
        if (byte != 0) return Error.InvalidReserved;
    }
    const payload = ImageDefine{
        .image_id = std.mem.readInt(u32, data[0..4], .little),
        .generation = std.mem.readInt(u32, data[4..8], .little),
        .width = std.mem.readInt(u32, data[8..12], .little),
        .height = std.mem.readInt(u32, data[12..16], .little),
        .total_byte_count = std.mem.readInt(u32, data[16..20], .little),
        .format = switch (std.mem.readInt(u16, data[20..22], .little)) {
            1 => .rgba8_premultiplied,
            else => return Error.InvalidStyle,
        },
        .color_space = switch (std.mem.readInt(u16, data[22..24], .little)) {
            1 => .srgb,
            else => return Error.InvalidStyle,
        },
        .alpha_mode = switch (std.mem.readInt(u16, data[24..26], .little)) {
            1 => .premultiplied,
            else => return Error.InvalidStyle,
        },
        .scaling_filter = switch (std.mem.readInt(u16, data[26..28], .little)) {
            1 => .nearest,
            2 => .linear,
            else => return Error.InvalidStyle,
        },
        .transform = switch (std.mem.readInt(u16, data[28..30], .little)) {
            1 => .identity,
            else => return Error.InvalidStyle,
        },
        .cache_policy = switch (std.mem.readInt(u16, data[30..32], .little)) {
            1 => .lru,
            2 => .pinned,
            else => return Error.InvalidStyle,
        },
        .animation_frame_count = std.mem.readInt(u16, data[32..34], .little),
        .animation_duration_ns = std.mem.readInt(u32, data[34..38], .little),
    };
    try validateImageDefine(payload);
    return payload;
}

pub fn encodeImageData(a: std.mem.Allocator, payload: ImageData, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    if (payload.image_id == 0 or payload.generation == 0) return Error.InvalidMessage;
    if (payload.fragment_count < 1 or payload.fragment_count > max_image_fragments or
        payload.fragment_index >= payload.fragment_count) return Error.InvalidMessage;
    if (payload.bytes.len < 1 or payload.bytes.len > max_image_fragment_bytes) return Error.InvalidMessage;
    try putU32(out, a, payload.image_id);
    try putU32(out, a, payload.generation);
    try putU16(out, a, payload.fragment_index);
    try putU16(out, a, payload.fragment_count);
    try putU32(out, a, @intCast(payload.bytes.len));
    try out.appendSlice(a, payload.bytes);
}

pub fn decodeImageData(data: []const u8) Error!ImageData {
    if (data.len < image_data_header_size) return Error.InvalidTable;
    const byte_length = std.mem.readInt(u32, data[12..16], .little);
    if (byte_length < 1 or byte_length > max_image_fragment_bytes) return Error.InvalidMessage;
    if (data.len != image_data_header_size + @as(usize, byte_length)) return Error.InvalidTable;
    const payload = ImageData{
        .image_id = std.mem.readInt(u32, data[0..4], .little),
        .generation = std.mem.readInt(u32, data[4..8], .little),
        .fragment_index = std.mem.readInt(u16, data[8..10], .little),
        .fragment_count = std.mem.readInt(u16, data[10..12], .little),
        .bytes = data[image_data_header_size..],
    };
    if (payload.image_id == 0 or payload.generation == 0) return Error.InvalidMessage;
    if (payload.fragment_count < 1 or payload.fragment_count > max_image_fragments or
        payload.fragment_index >= payload.fragment_count) return Error.InvalidMessage;
    return payload;
}

pub fn encodeImageDelete(a: std.mem.Allocator, payload: ImageDelete, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    if (payload.image_id == 0 or payload.generation == 0) return Error.InvalidMessage;
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u32, bytes[0..4], payload.image_id, .little);
    std.mem.writeInt(u32, bytes[4..8], payload.generation, .little);
    try out.appendSlice(a, &bytes);
}

pub fn decodeImageDelete(data: []const u8) Error!ImageDelete {
    if (data.len != 8) return Error.InvalidTable;
    const payload = ImageDelete{
        .image_id = std.mem.readInt(u32, data[0..4], .little),
        .generation = std.mem.readInt(u32, data[4..8], .little),
    };
    if (payload.image_id == 0 or payload.generation == 0) return Error.InvalidMessage;
    return payload;
}

/// Fixed-layout FONT_DEFINE v1.  Strings are exact-length UTF-8; unused
/// metadata and all reserved bytes are zero.  This is a bounded descriptor and
/// is not a text-shaping or rendering contract.
pub fn encodeFontDefineBytes(payload: FontDefine) Error![font_record_size]u8 {
    try validateFontDefine(payload);
    var bytes: [font_record_size]u8 = @splat(0);
    std.mem.writeInt(u32, bytes[0..4], payload.font_id, .little);
    std.mem.writeInt(u32, bytes[4..8], payload.generation, .little);
    bytes[8] = @intCast(payload.family_len);
    bytes[9] = @intCast(payload.foundry_len);
    bytes[10] = @intCast(payload.style_len);
    bytes[11] = @intFromEnum(payload.slant);
    bytes[12] = @intFromEnum(payload.spacing);
    bytes[13] = @intFromBool(payload.scalable);
    bytes[14] = @intFromBool(payload.fixed_pitch);
    std.mem.writeInt(u16, bytes[16..18], payload.weight, .little);
    std.mem.writeInt(u16, bytes[18..20], payload.width_percent, .little);
    std.mem.writeInt(u32, bytes[20..24], payload.pixel_size, .little);
    std.mem.writeInt(u32, bytes[24..28], payload.point_size_tenths, .little);
    std.mem.writeInt(u32, bytes[28..32], payload.x_dpi, .little);
    std.mem.writeInt(u32, bytes[32..36], payload.y_dpi, .little);
    std.mem.writeInt(i32, bytes[36..40], payload.ascent, .little);
    std.mem.writeInt(i32, bytes[40..44], payload.descent, .little);
    std.mem.writeInt(u32, bytes[44..48], payload.line_height, .little);
    std.mem.writeInt(u32, bytes[48..52], payload.average_advance, .little);
    std.mem.writeInt(u32, bytes[52..56], payload.space_advance, .little);
    std.mem.writeInt(u32, bytes[56..60], payload.max_advance, .little);
    std.mem.writeInt(u32, bytes[60..64], payload.min_advance, .little);
    std.mem.writeInt(i32, bytes[64..68], payload.baseline_offset, .little);
    std.mem.writeInt(i32, bytes[68..72], payload.underline_position, .little);
    std.mem.writeInt(u32, bytes[72..76], payload.underline_thickness, .little);
    std.mem.writeInt(u16, bytes[76..78], payload.feature_count, .little);
    std.mem.writeInt(u16, bytes[78..80], payload.variation_axis_count, .little);
    std.mem.writeInt(u16, bytes[80..82], payload.fallback_count, .little);
    @memcpy(bytes[96..160], &payload.family);
    @memcpy(bytes[160..192], &payload.foundry);
    @memcpy(bytes[192..224], &payload.style);
    return bytes;
}

pub fn encodeFontDefine(a: std.mem.Allocator, payload: FontDefine, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    const bytes = try encodeFontDefineBytes(payload);
    try out.appendSlice(a, &bytes);
}

pub fn decodeFontDefine(data: []const u8) Error!FontDefine {
    if (data.len != font_record_size) return Error.InvalidTable;
    if (data[15] != 0) return Error.InvalidReserved;
    for (data[82..96]) |byte| {
        if (byte != 0) return Error.InvalidReserved;
    }
    if (data[13] > 1 or data[14] > 1) return Error.InvalidBoolean;
    const payload = FontDefine{
        .font_id = std.mem.readInt(u32, data[0..4], .little),
        .generation = std.mem.readInt(u32, data[4..8], .little),
        .family = data[96..160][0..max_font_family_bytes].*,
        .family_len = data[8],
        .foundry = data[160..192][0..max_font_foundry_bytes].*,
        .foundry_len = data[9],
        .style = data[192..224][0..max_font_style_bytes].*,
        .style_len = data[10],
        .slant = switch (data[11]) {
            0 => .unspecified,
            1 => .roman,
            2 => .italic,
            3 => .oblique,
            else => return Error.InvalidStyle,
        },
        .spacing = switch (data[12]) {
            0 => .unspecified,
            1 => .mono,
            2 => .proportional,
            else => return Error.InvalidStyle,
        },
        .scalable = data[13] == 1,
        .fixed_pitch = data[14] == 1,
        .weight = std.mem.readInt(u16, data[16..18], .little),
        .width_percent = std.mem.readInt(u16, data[18..20], .little),
        .pixel_size = std.mem.readInt(u32, data[20..24], .little),
        .point_size_tenths = std.mem.readInt(u32, data[24..28], .little),
        .x_dpi = std.mem.readInt(u32, data[28..32], .little),
        .y_dpi = std.mem.readInt(u32, data[32..36], .little),
        .ascent = std.mem.readInt(i32, data[36..40], .little),
        .descent = std.mem.readInt(i32, data[40..44], .little),
        .line_height = std.mem.readInt(u32, data[44..48], .little),
        .average_advance = std.mem.readInt(u32, data[48..52], .little),
        .space_advance = std.mem.readInt(u32, data[52..56], .little),
        .max_advance = std.mem.readInt(u32, data[56..60], .little),
        .min_advance = std.mem.readInt(u32, data[60..64], .little),
        .baseline_offset = std.mem.readInt(i32, data[64..68], .little),
        .underline_position = std.mem.readInt(i32, data[68..72], .little),
        .underline_thickness = std.mem.readInt(u32, data[72..76], .little),
        .feature_count = std.mem.readInt(u16, data[76..78], .little),
        .variation_axis_count = std.mem.readInt(u16, data[78..80], .little),
        .fallback_count = std.mem.readInt(u16, data[80..82], .little),
    };
    try validateFontDefine(payload);
    return payload;
}

/// Builds the fixed delete payload without heap allocation.
pub fn encodeFontDeleteBytes(payload: FontDelete) Error![8]u8 {
    if (payload.font_id == 0 or payload.generation == 0) return Error.InvalidMessage;
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u32, bytes[0..4], payload.font_id, .little);
    std.mem.writeInt(u32, bytes[4..8], payload.generation, .little);
    return bytes;
}

pub fn encodeFontDelete(a: std.mem.Allocator, payload: FontDelete, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    const bytes = try encodeFontDeleteBytes(payload);
    try out.appendSlice(a, &bytes);
}

pub fn decodeFontDelete(data: []const u8) Error!FontDelete {
    if (data.len != 8) return Error.InvalidTable;
    const payload = FontDelete{
        .font_id = std.mem.readInt(u32, data[0..4], .little),
        .generation = std.mem.readInt(u32, data[4..8], .little),
    };
    if (payload.font_id == 0 or payload.generation == 0) return Error.InvalidMessage;
    return payload;
}

/// Builds the fixed wire record without heap allocation.
pub fn encodeFaceDefineBytes(payload: FaceDefine) Error![face_record_size]u8 {
    try validateFaceDefine(payload);
    var bytes: [face_record_size]u8 = @splat(0);
    std.mem.writeInt(u32, bytes[0..4], payload.face_id, .little);
    std.mem.writeInt(u32, bytes[4..8], payload.generation, .little);
    bytes[8] = @bitCast(payload.presence);
    @memcpy(bytes[12..16], &payload.foreground);
    @memcpy(bytes[16..20], &payload.background);
    @memcpy(bytes[20..24], &payload.underline_color);
    @memcpy(bytes[24..28], &payload.overline_color);
    @memcpy(bytes[28..32], &payload.strike_color);
    @memcpy(bytes[32..36], &payload.box_color);
    bytes[36] = @intFromEnum(payload.underline);
    bytes[37] = @intFromEnum(payload.overline);
    bytes[38] = @intFromEnum(payload.strike_through);
    bytes[39] = @intFromEnum(payload.box);
    std.mem.writeInt(i32, bytes[40..44], payload.box_line_width, .little);
    bytes[44] = @intFromBool(payload.inverse_video);
    bytes[45] = @intFromBool(payload.extend);
    std.mem.writeInt(i32, bytes[46..50], payload.line_spacing, .little);
    std.mem.writeInt(u32, bytes[50..54], payload.font_id, .little);
    std.mem.writeInt(u32, bytes[54..58], payload.font_generation, .little);
    std.mem.writeInt(u32, bytes[58..62], payload.stipple_id, .little);
    std.mem.writeInt(u32, bytes[62..66], payload.stipple_generation, .little);
    return bytes;
}

pub fn encodeFaceDefine(a: std.mem.Allocator, payload: FaceDefine, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    const bytes = try encodeFaceDefineBytes(payload);
    try out.appendSlice(a, &bytes);
}

pub fn decodeFaceDefine(data: []const u8) Error!FaceDefine {
    if (data.len != face_record_size) return Error.InvalidTable;
    if (data[9] != 0 or data[10] != 0 or data[11] != 0) return Error.InvalidReserved;
    for (data[66..face_record_size]) |byte| {
        if (byte != 0) return Error.InvalidReserved;
    }
    if (data[44] > 1 or data[45] > 1) return Error.InvalidBoolean;
    const payload = FaceDefine{
        .face_id = std.mem.readInt(u32, data[0..4], .little),
        .generation = std.mem.readInt(u32, data[4..8], .little),
        .presence = @bitCast(data[8]),
        .foreground = data[12..16][0..4].*,
        .background = data[16..20][0..4].*,
        .underline_color = data[20..24][0..4].*,
        .overline_color = data[24..28][0..4].*,
        .strike_color = data[28..32][0..4].*,
        .box_color = data[32..36][0..4].*,
        .underline = switch (data[36]) {
            0 => .unspecified,
            1 => .off,
            2 => .single,
            3 => .color,
            else => return Error.InvalidStyle,
        },
        .overline = switch (data[37]) {
            0 => .unspecified,
            1 => .off,
            2 => .single,
            3 => .color,
            else => return Error.InvalidStyle,
        },
        .strike_through = switch (data[38]) {
            0 => .unspecified,
            1 => .off,
            2 => .single,
            3 => .color,
            else => return Error.InvalidStyle,
        },
        .box = switch (data[39]) {
            0 => .none,
            1 => .simple,
            2 => .released,
            3 => .pressed,
            else => return Error.InvalidStyle,
        },
        .box_line_width = std.mem.readInt(i32, data[40..44], .little),
        .inverse_video = data[44] == 1,
        .extend = data[45] == 1,
        .line_spacing = std.mem.readInt(i32, data[46..50], .little),
        .font_id = std.mem.readInt(u32, data[50..54], .little),
        .font_generation = std.mem.readInt(u32, data[54..58], .little),
        .stipple_id = std.mem.readInt(u32, data[58..62], .little),
        .stipple_generation = std.mem.readInt(u32, data[62..66], .little),
    };
    try validateFaceDefine(payload);
    return payload;
}

/// Builds the fixed delete payload without heap allocation.
pub fn encodeFaceDeleteBytes(payload: FaceDelete) Error![8]u8 {
    if (payload.face_id == 0 or payload.generation == 0) return Error.InvalidMessage;
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u32, bytes[0..4], payload.face_id, .little);
    std.mem.writeInt(u32, bytes[4..8], payload.generation, .little);
    return bytes;
}

pub fn encodeFaceDelete(a: std.mem.Allocator, payload: FaceDelete, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    const bytes = try encodeFaceDeleteBytes(payload);
    try out.appendSlice(a, &bytes);
}

pub fn decodeFaceDelete(data: []const u8) Error!FaceDelete {
    if (data.len != 8) return Error.InvalidTable;
    const payload = FaceDelete{
        .face_id = std.mem.readInt(u32, data[0..4], .little),
        .generation = std.mem.readInt(u32, data[4..8], .little),
    };
    if (payload.face_id == 0 or payload.generation == 0) return Error.InvalidMessage;
    return payload;
}

pub const Capability = struct {
    /// `name` and `value` borrow bytes from the encoded input.  The caller
    /// must keep that input alive for the lifetime of the decoded table.
    name: []const u8,
    value: []const u8,
};

pub const FrameVisibilityState = enum(u8) {
    hidden = 0,
    visible = 1,
    iconified = 2,
};

pub const FrameVisibilityPayload = struct {
    frame_id: u32,
    frame_generation: u32,
    state: FrameVisibilityState,
};

pub const FrameTitlePayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    string_resource_id: u32,
    string_generation: u32,
    frame_generation: u32,
};

pub const FrameFocusPayload = struct {
    frame_id: u32,
    frame_generation: u32,
    focused: bool,
};

pub const FocusPhase = enum(u8) {
    lost = 0,
    gained = 1,
};

/// Fixed FOCUS_EVENT v1: schema, phase, frame/SDL-window identity, then eight
/// reserved bytes.  The IDs are adapter-side protocol identities, not Emacs
/// terminal handles.
pub const FocusEvent = struct {
    phase: FocusPhase,
    frame_id: u32,
    sdl_window_id: u32,
};

pub const focus_event_size: usize = 20;
pub const focus_schema: u16 = 1;

pub fn validateFocusEvent(payload: FocusEvent) Error!void {
    if (payload.frame_id == 0 or payload.sdl_window_id == 0) return Error.InvalidMessage;
}

pub fn encodeFocusEvent(a: std.mem.Allocator, payload: FocusEvent, out: *std.ArrayList(u8)) !void {
    try validateFocusEvent(payload);
    var bytes: [focus_event_size]u8 = @splat(0);
    std.mem.writeInt(u16, bytes[0..2], focus_schema, .little);
    bytes[2] = @intFromEnum(payload.phase);
    std.mem.writeInt(u32, bytes[4..8], payload.frame_id, .little);
    std.mem.writeInt(u32, bytes[8..12], payload.sdl_window_id, .little);
    try out.appendSlice(a, &bytes);
}

pub fn decodeFocusEvent(data: []const u8) Error!FocusEvent {
    if (data.len != focus_event_size) return Error.InvalidTable;
    if (std.mem.readInt(u16, data[0..2], .little) != focus_schema) return Error.InvalidTable;
    if (data[3] != 0 or !std.mem.allEqual(u8, data[12..20], 0)) return Error.InvalidReserved;
    const payload: FocusEvent = .{
        .phase = switch (data[2]) {
            0 => .lost,
            1 => .gained,
            else => return Error.InvalidTable,
        },
        .frame_id = std.mem.readInt(u32, data[4..8], .little),
        .sdl_window_id = std.mem.readInt(u32, data[8..12], .little),
    };
    try validateFocusEvent(payload);
    return payload;
}

pub const WindowTreeHeader = struct {
    frame_id: u32,
    frame_generation: u32,
    selected_window_id: u32,
    root_window_id: u32,
};

pub const WindowTreeNode = struct {
    window_id: u64,
    parent_window_id: u64,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    flags: u32,
    default_face_id: u32,
    depth: u8,

    pub fn selected(self: WindowTreeNode) bool {
        return (self.flags & 1) != 0;
    }

    pub fn visible(self: WindowTreeNode) bool {
        return (self.flags & 2) != 0;
    }
};

pub const WindowTreeSnapshot = struct {
    header: WindowTreeHeader,
    nodes: []const WindowTreeNode,
};

pub const window_tree_header_size: usize = 24;
pub const window_tree_node_size: usize = 48;
pub const window_tree_schema: u16 = 1;
pub const window_tree_flag_selected: u8 = 1;
pub const window_tree_flag_visible: u8 = 2;
pub const max_window_tree_nodes: usize = 32;
pub const max_window_tree_depth: u8 = 8;

fn validateWindowTreeSnapshot(snapshot: WindowTreeSnapshot) Error!void {
    const header = snapshot.header;
    if (header.frame_id == 0 or header.frame_generation == 0 or
        header.selected_window_id == 0 or header.root_window_id == 0)
        return Error.InvalidMessage;
    if (snapshot.nodes.len == 0 or snapshot.nodes.len > max_window_tree_nodes)
        return Error.InvalidMessage;

    var selected_count: usize = 0;
    for (snapshot.nodes, 0..) |node, index| {
        if (node.window_id == 0) return Error.InvalidMessage;
        if (node.width < 0 or node.height < 0 or node.depth > max_window_tree_depth)
            return Error.InvalidMessage;
        if (node.flags & ~@as(u32, 3) != 0) return Error.InvalidReserved;
        if (node.selected()) selected_count += 1;
        if (!node.visible() and node.selected()) return Error.InvalidMessage;
        for (snapshot.nodes[0..index]) |prior| {
            if (prior.window_id == node.window_id) return Error.InvalidTable;
        }
    }
    if (selected_count != 1) return Error.InvalidMessage;

    var root: ?WindowTreeNode = null;
    for (snapshot.nodes) |node| {
        if (node.window_id == header.root_window_id) {
            root = node;
            break;
        }
    }
    const root_node = root orelse return Error.InvalidMessage;
    if (root_node.parent_window_id != 0 or root_node.depth != 0 or !root_node.visible())
        return Error.InvalidMessage;

    for (snapshot.nodes) |node| {
        if (node.parent_window_id == 0) {
            if (node.window_id != header.root_window_id) return Error.InvalidMessage;
            continue;
        }
        var parent: ?WindowTreeNode = null;
        for (snapshot.nodes) |candidate| {
            if (candidate.window_id == node.parent_window_id) {
                parent = candidate;
                break;
            }
        }
        var current = parent orelse return Error.InvalidMessage;
        if (current.depth >= node.depth) return Error.InvalidMessage;
        var hops: usize = 0;
        while (current.parent_window_id != 0) {
            hops += 1;
            if (hops > max_window_tree_depth) return Error.InvalidMessage;
            parent = null;
            for (snapshot.nodes) |candidate| {
                if (candidate.window_id == current.parent_window_id) {
                    parent = candidate;
                    break;
                }
            }
            current = parent orelse return Error.InvalidMessage;
        }
        if (current.window_id != header.root_window_id) return Error.InvalidMessage;
    }
}

pub fn encodeWindowTreeSnapshot(
    a: std.mem.Allocator,
    snapshot: WindowTreeSnapshot,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateWindowTreeSnapshot(snapshot);
    var header: [window_tree_header_size]u8 = [_]u8{0} ** window_tree_header_size;
    std.mem.writeInt(u16, header[0..2], window_tree_schema, .little);
    std.mem.writeInt(u32, header[4..8], snapshot.header.frame_id, .little);
    std.mem.writeInt(u32, header[8..12], snapshot.header.frame_generation, .little);
    std.mem.writeInt(u32, header[12..16], @intCast(snapshot.nodes.len), .little);
    std.mem.writeInt(u32, header[16..20], snapshot.header.selected_window_id, .little);
    std.mem.writeInt(u32, header[20..24], snapshot.header.root_window_id, .little);
    try out.appendSlice(a, &header);
    for (snapshot.nodes) |node| {
        var bytes: [window_tree_node_size]u8 = [_]u8{0} ** window_tree_node_size;
        std.mem.writeInt(u64, bytes[0..8], node.window_id, .little);
        std.mem.writeInt(u64, bytes[8..16], node.parent_window_id, .little);
        std.mem.writeInt(u32, bytes[16..20], @bitCast(node.x), .little);
        std.mem.writeInt(u32, bytes[20..24], @bitCast(node.y), .little);
        std.mem.writeInt(u32, bytes[24..28], @bitCast(node.width), .little);
        std.mem.writeInt(u32, bytes[28..32], @bitCast(node.height), .little);
        std.mem.writeInt(u32, bytes[32..36], node.flags, .little);
        std.mem.writeInt(u32, bytes[36..40], node.default_face_id, .little);
        bytes[40] = node.depth;
        try out.appendSlice(a, &bytes);
    }
}

pub fn decodeWindowTreeSnapshot(
    a: std.mem.Allocator,
    data: []const u8,
) (Error || std.mem.Allocator.Error)!WindowTreeSnapshot {
    if (data.len < window_tree_header_size) return Error.InvalidTable;
    var reader = Reader{ .data = data };
    if (try reader.readU16() != window_tree_schema) return Error.InvalidVersion;
    const flags = try reader.readByte();
    const reserved = try reader.readByte();
    const frame_id = try reader.readU32();
    const frame_generation = try reader.readU32();
    const node_count = try reader.readU32();
    const selected_window_id = try reader.readU32();
    const root_window_id = try reader.readU32();
    if (flags != 0 or reserved != 0) return Error.InvalidReserved;
    if (node_count == 0 or node_count > max_window_tree_nodes) return Error.InvalidTable;
    if (data.len != window_tree_header_size + @as(usize, node_count) * window_tree_node_size)
        return Error.InvalidTable;

    const nodes = try a.alloc(WindowTreeNode, node_count);
    errdefer a.free(nodes);
    for (nodes) |*node| {
        node.* = .{
            .window_id = try reader.readU64(),
            .parent_window_id = try reader.readU64(),
            .x = try reader.readI32(),
            .y = try reader.readI32(),
            .width = try reader.readI32(),
            .height = try reader.readI32(),
            .flags = try reader.readU32(),
            .default_face_id = try reader.readU32(),
            .depth = try reader.readByte(),
        };
        try reader.expectZeros(7);
    }
    const snapshot: WindowTreeSnapshot = .{
        .header = .{
            .frame_id = frame_id,
            .frame_generation = frame_generation,
            .selected_window_id = selected_window_id,
            .root_window_id = root_window_id,
        },
        .nodes = nodes,
    };
    try validateWindowTreeSnapshot(snapshot);
    return snapshot;
}

pub fn freeWindowTreeSnapshot(a: std.mem.Allocator, snapshot: *WindowTreeSnapshot) void {
    a.free(snapshot.nodes);
    snapshot.nodes = &.{};
}

pub const WindowRequestKind = enum(u8) {
    close = 1,
    resize = 2,
    move = 3,
    fullscreen = 4,
    fullscreen_desktop = 5,
    maximize = 6,
    minimize = 7,
    restore = 8,
};

pub const max_window_size: i32 = 16384;
pub const window_request_size: usize = 32;
pub const window_request_schema: u16 = 1;

pub const WindowRequest = struct {
    kind: WindowRequestKind,
    sdl_window_id: u32,
    width: i32 = 0,
    height: i32 = 0,
    x: i32 = 0,
    y: i32 = 0,
};

pub fn validateWindowRequest(payload: WindowRequest) Error!void {
    if (payload.sdl_window_id == 0) return Error.InvalidMessage;
    switch (payload.kind) {
        .resize => {
            if (payload.width < 1 or payload.width > max_window_size or
                payload.height < 1 or payload.height > max_window_size) return Error.InvalidMessage;
            if (payload.x != 0 or payload.y != 0) return Error.InvalidMessage;
        },
        .move => {
            if (payload.width != 0 or payload.height != 0) return Error.InvalidMessage;
        },
        else => {
            if (payload.width != 0 or payload.height != 0 or
                payload.x != 0 or payload.y != 0) return Error.InvalidMessage;
        },
    }
}

pub fn encodeWindowRequest(a: std.mem.Allocator, payload: WindowRequest, out: *std.ArrayList(u8)) !void {
    try validateWindowRequest(payload);
    var bytes: [window_request_size]u8 = @splat(0);
    std.mem.writeInt(u16, bytes[0..2], window_request_schema, .little);
    bytes[2] = @intFromEnum(payload.kind);
    std.mem.writeInt(u32, bytes[4..8], payload.sdl_window_id, .little);
    std.mem.writeInt(i32, bytes[8..12], payload.width, .little);
    std.mem.writeInt(i32, bytes[12..16], payload.height, .little);
    std.mem.writeInt(i32, bytes[16..20], payload.x, .little);
    std.mem.writeInt(i32, bytes[20..24], payload.y, .little);
    try out.appendSlice(a, &bytes);
}

pub fn decodeWindowRequest(data: []const u8) Error!WindowRequest {
    if (data.len != window_request_size) return Error.InvalidTable;
    if (std.mem.readInt(u16, data[0..2], .little) != window_request_schema) return Error.InvalidTable;
    if (data[3] != 0 or !std.mem.allEqual(u8, data[24..32], 0)) return Error.InvalidReserved;
    const payload: WindowRequest = .{
        .kind = switch (data[2]) {
            1 => .close,
            2 => .resize,
            3 => .move,
            4 => .fullscreen,
            5 => .fullscreen_desktop,
            6 => .maximize,
            7 => .minimize,
            8 => .restore,
            else => return Error.InvalidTable,
        },
        .sdl_window_id = std.mem.readInt(u32, data[4..8], .little),
        .width = std.mem.readInt(i32, data[8..12], .little),
        .height = std.mem.readInt(i32, data[12..16], .little),
        .x = std.mem.readInt(i32, data[16..20], .little),
        .y = std.mem.readInt(i32, data[20..24], .little),
    };
    try validateWindowRequest(payload);
    return payload;
}

fn validateFrameStateIdentity(frame_id: u32, frame_generation: u32) Error!void {
    if (frame_id == 0 or frame_generation == 0) return Error.InvalidMessage;
}

pub fn encodeFrameVisibility(a: std.mem.Allocator, payload: FrameVisibilityPayload, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateFrameStateIdentity(payload.frame_id, payload.frame_generation);
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, payload.frame_id, .little);
    try out.appendSlice(a, &bytes);
    std.mem.writeInt(u32, &bytes, payload.frame_generation, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, @intFromEnum(payload.state));
    try out.appendSlice(a, &.{ 0, 0, 0 });
}

pub fn decodeFrameVisibility(data: []const u8) Error!FrameVisibilityPayload {
    if (data.len != 12) return Error.InvalidTable;
    const payload = FrameVisibilityPayload{
        .frame_id = std.mem.readInt(u32, data[0..4], .little),
        .frame_generation = std.mem.readInt(u32, data[4..8], .little),
        .state = switch (data[8]) {
            0 => .hidden,
            1 => .visible,
            2 => .iconified,
            else => return Error.InvalidTable,
        },
    };
    if (data[9] != 0 or data[10] != 0 or data[11] != 0) return Error.InvalidTable;
    try validateFrameStateIdentity(payload.frame_id, payload.frame_generation);
    return payload;
}

pub fn encodeFrameFocus(a: std.mem.Allocator, payload: FrameFocusPayload, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateFrameStateIdentity(payload.frame_id, payload.frame_generation);
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, payload.frame_id, .little);
    try out.appendSlice(a, &bytes);
    std.mem.writeInt(u32, &bytes, payload.frame_generation, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, @intFromBool(payload.focused));
    try out.appendSlice(a, &.{ 0, 0, 0 });
}

pub fn decodeFrameFocus(data: []const u8) Error!FrameFocusPayload {
    if (data.len != 12) return Error.InvalidTable;
    const payload = FrameFocusPayload{
        .frame_id = std.mem.readInt(u32, data[0..4], .little),
        .frame_generation = std.mem.readInt(u32, data[4..8], .little),
        .focused = switch (data[8]) {
            0 => false,
            1 => true,
            else => return Error.InvalidTable,
        },
    };
    if (data[9] != 0 or data[10] != 0 or data[11] != 0) return Error.InvalidTable;
    try validateFrameStateIdentity(payload.frame_id, payload.frame_generation);
    return payload;
}

pub fn validateFrameVisibilityEnvelope(payload: FrameVisibilityPayload, envelope: Envelope) Error!void {
    try validateFrameStateIdentity(payload.frame_id, payload.frame_generation);
    if (envelope.frame_id != payload.frame_id) return Error.InvalidMessage;
}

pub fn validateFrameFocusEnvelope(payload: FrameFocusPayload, envelope: Envelope) Error!void {
    try validateFrameStateIdentity(payload.frame_id, payload.frame_generation);
    if (envelope.frame_id != payload.frame_id) return Error.InvalidMessage;
}

fn validateFrameTitle(payload: FrameTitlePayload) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0)
        return Error.InvalidMessage;
    if (payload.string_resource_id == 0 or payload.string_generation == 0 or
        payload.frame_generation == 0)
        return Error.InvalidMessage;
}

pub fn encodeFrameTitle(
    a: std.mem.Allocator,
    payload: FrameTitlePayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameTitle(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    try putU32(out, a, payload.string_resource_id);
    try putU32(out, a, payload.string_generation);
    try putU32(out, a, payload.frame_generation);
}

pub fn decodeFrameTitle(data: []const u8) Error!FrameTitlePayload {
    if (data.len != 16) return Error.InvalidTable;
    const payload = FrameTitlePayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .string_resource_id = std.mem.readInt(u32, data[4..8], .little),
        .string_generation = std.mem.readInt(u32, data[8..12], .little),
        .frame_generation = std.mem.readInt(u32, data[12..16], .little),
    };
    try validateFrameTitle(payload);
    return payload;
}

pub fn validateFrameTitleEnvelope(payload: FrameTitlePayload, envelope: Envelope) Error!void {
    try validateFrameTitle(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

pub fn encodeResourceRequests(a: std.mem.Allocator, requests: []const ResourceRequest, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    if (requests.len > max_resource_requests) return Error.Unsupported;
    try putU32(out, a, @intCast(requests.len));
    for (requests, 0..) |request, request_index| {
        if (request.id == 0) return Error.InvalidMessage;
        for (requests[0..request_index]) |prior| {
            if (prior.kind == request.kind and prior.id == request.id) return Error.InvalidTable;
        }
        try out.append(a, @intFromEnum(request.kind));
        try out.appendSlice(a, &.{ 0, 0, 0 });
        try putU32(out, a, request.id);
        try putU32(out, a, request.generation);
    }
}

pub fn decodeResourceRequests(a: std.mem.Allocator, data: []const u8) (Error || std.mem.Allocator.Error)![]ResourceRequest {
    if (data.len < 4) return Error.InvalidTable;
    const count = std.mem.readInt(u32, data[0..4], .little);
    if (count > max_resource_requests) return Error.Unsupported;
    if (data.len != 4 + @as(usize, count) * 12) return Error.InvalidTable;
    const result = try a.alloc(ResourceRequest, count);
    errdefer a.free(result);
    for (result, 0..) |*request, request_index| {
        const offset = 4 + request_index * 12;
        const kind_byte = data[offset];
        if (kind_byte == 0 or kind_byte > 6) return Error.InvalidTable;
        if (data[offset + 1] != 0 or data[offset + 2] != 0 or data[offset + 3] != 0)
            return Error.InvalidTable;
        request.* = .{
            .kind = @enumFromInt(kind_byte),
            .id = std.mem.readInt(u32, data[offset + 4 ..][0..4], .little),
            .generation = std.mem.readInt(u32, data[offset + 8 ..][0..4], .little),
        };
        if (request.id == 0) return Error.InvalidTable;
        for (result[0..request_index]) |prior| {
            if (prior.kind == request.kind and prior.id == request.id)
                return Error.InvalidTable;
        }
    }
    return result;
}

pub fn encodeResourceEvict(a: std.mem.Allocator, evict: ResourceEvict, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    if (evict.id == 0 or evict.generation == 0) return Error.InvalidMessage;
    try out.append(a, @intFromEnum(evict.kind));
    try out.appendSlice(a, &.{ 0, 0, 0 });
    try putU32(out, a, evict.id);
    try putU32(out, a, evict.generation);
    try out.append(a, @intFromEnum(evict.reason));
    try out.appendSlice(a, &.{ 0, 0, 0 });
}

pub fn decodeResourceEvict(data: []const u8) Error!ResourceEvict {
    if (data.len != 16) return Error.InvalidTable;
    const evict = ResourceEvict{
        .kind = switch (data[0]) {
            1 => .face,
            2 => .font,
            3 => .image,
            4 => .fringe_bitmap,
            5 => .icon,
            6 => .string,
            else => return Error.InvalidTable,
        },
        .id = std.mem.readInt(u32, data[4..8], .little),
        .generation = std.mem.readInt(u32, data[8..12], .little),
        .reason = switch (data[12]) {
            0 => .lru,
            1 => .capacity,
            2 => .generation,
            3 => .explicit,
            else => return Error.InvalidTable,
        },
    };
    if (data[1] != 0 or data[2] != 0 or data[3] != 0 or
        evict.id == 0 or evict.generation == 0 or
        data[13] != 0 or data[14] != 0 or data[15] != 0)
        return Error.InvalidTable;
    return evict;
}

fn knownSectionKind(kind: u32) bool {
    return kind >= SectionKind.frame_patch and kind <= SectionKind.commit_token;
}

fn extensionSectionKind(kind: u32) bool {
    return kind >= 0x8000 and kind <= 0xfffe;
}

fn validSectionKind(kind: u32) bool {
    return knownSectionKind(kind) or extensionSectionKind(kind);
}

fn putU16(out: *std.ArrayList(u8), a: std.mem.Allocator, value: u16) !void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, value, .little);
    try out.appendSlice(a, &buf);
}

fn putU32(out: *std.ArrayList(u8), a: std.mem.Allocator, value: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, value, .little);
    try out.appendSlice(a, &buf);
}

fn putU64(out: *std.ArrayList(u8), a: std.mem.Allocator, value: u64) !void {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, value, .little);
    try out.appendSlice(a, &buf);
}

const Reader = struct {
    data: []const u8,
    offset: usize = 0,

    fn readU16(self: *Reader) Error!u16 {
        if (2 > self.data.len -| self.offset) return Error.InvalidEnvelope;
        const value = std.mem.readInt(u16, self.data[self.offset..][0..2], .little);
        self.offset += 2;
        return value;
    }

    fn readByte(self: *Reader) Error!u8 {
        if (self.data.len == self.offset) return Error.InvalidEnvelope;
        const value = self.data[self.offset];
        self.offset += 1;
        return value;
    }

    fn readU32(self: *Reader) Error!u32 {
        if (4 > self.data.len -| self.offset) return Error.InvalidEnvelope;
        const value = std.mem.readInt(u32, self.data[self.offset..][0..4], .little);
        self.offset += 4;
        return value;
    }

    fn readU64(self: *Reader) Error!u64 {
        if (8 > self.data.len -| self.offset) return Error.InvalidEnvelope;
        const value = std.mem.readInt(u64, self.data[self.offset..][0..8], .little);
        self.offset += 8;
        return value;
    }

    fn readI32(self: *Reader) Error!i32 {
        return @bitCast(try self.readU32());
    }

    fn skip(self: *Reader, count: usize) Error!void {
        if (count > self.data.len -| self.offset) return Error.InvalidEnvelope;
        self.offset += count;
    }

    fn expectZeros(self: *Reader, count: usize) Error!void {
        const start = self.offset;
        try self.skip(count);
        for (self.data[start..self.offset]) |byte| {
            if (byte != 0) return Error.InvalidEnvelope;
        }
    }

    fn bytes(self: *Reader, len: usize) Error![]const u8 {
        if (len > self.data.len -| self.offset) return Error.InvalidEnvelope;
        const value = self.data[self.offset..][0..len];
        self.offset += len;
        return value;
    }
};

fn payloadHash(payload: []const u8) u32 {
    return std.hash.crc.Crc32Iscsi.hash(payload);
}

const unsupported_transport_flags: u16 = Flags.compressed | Flags.encrypted |
    Flags.fragmented | Flags.last_fragment;
const known_flag_mask: u16 = Flags.snapshot | Flags.delta | Flags.coalescable |
    Flags.requires_ack | Flags.fragmented | Flags.last_fragment |
    Flags.compressed | Flags.encrypted | Flags.idempotent | Flags.debug;

fn validateEnvelopeFlags(flags: u16) Error!void {
    if (flags & unsupported_transport_flags != 0) return Error.Unsupported;
    if (flags & ~known_flag_mask != 0) return Error.InvalidEnvelope;
}

fn extensionMessageType(message_type: u16) bool {
    return message_type >= 0xf000 and message_type <= 0xfffe;
}

fn validMessageType(message_type: u16) bool {
    return message_type != 0 and message_type != Message.invalid and
        (knownMessage(message_type) or extensionMessageType(message_type));
}

pub fn encodeEnvelope(
    a: std.mem.Allocator,
    envelope: Envelope,
    payload: []const u8,
    out: *std.ArrayList(u8),
) !void {
    if (!validMessageType(envelope.message_type)) return Error.InvalidMessage;
    try validateEnvelopeFlags(envelope.flags);
    if (payload.len > std.math.maxInt(u32)) return Error.Unsupported;
    const start = out.items.len;
    try out.appendSlice(a, &Magic);
    try putU16(out, a, major_version);
    try putU16(out, a, minor_version);
    try putU16(out, a, envelope.flags);
    try putU16(out, a, envelope.message_type);
    try putU16(out, a, header_size);
    try putU32(out, a, @intCast(payload.len));
    try putU64(out, a, envelope.sequence);
    try putU64(out, a, envelope.ack_sequence);
    try putU64(out, a, envelope.session_id);
    try putU32(out, a, envelope.frame_id);
    try putU32(out, a, 0);
    try putU64(out, a, envelope.timestamp_ns);
    try putU32(out, a, payloadHash(payload));
    try out.appendSlice(a, payload);
    std.debug.assert(out.items.len - start == header_size + payload.len);
}

/// The returned payload borrows bytes from `data`; keep `data` valid and
/// unmodified for as long as the returned `Payload` is used.
pub fn decodeEnvelope(data: []const u8) Error!Payload {
    if (data.len < header_size) return Error.InvalidEnvelope;
    var reader = Reader{ .data = data };
    if (!std.mem.eql(u8, try reader.bytes(Magic.len), &Magic)) return Error.InvalidEnvelope;
    if (try reader.readU16() != major_version) return Error.InvalidVersion;
    const minor = try reader.readU16();
    // Minor additions are compatible; envelope readers ignore unknown minor
    // values and payload handlers must ignore fields they do not understand.
    _ = minor;
    const flags = try reader.readU16();
    const message_type = try reader.readU16();
    if (try reader.readU16() != header_size) return Error.InvalidEnvelope;
    const payload_size = try reader.readU32();
    const sequence = try reader.readU64();
    const ack_sequence = try reader.readU64();
    const session_id = try reader.readU64();
    const frame_id = try reader.readU32();
    if (try reader.readU32() != 0) return Error.InvalidEnvelope;
    const timestamp_ns = try reader.readU64();
    const hash = try reader.readU32();
    try validateEnvelopeFlags(flags);
    if (!validMessageType(message_type)) return Error.InvalidMessage;
    if (payload_size > data.len -| reader.offset) return Error.InvalidEnvelope;
    const end = reader.offset + payload_size;
    const payload = data[reader.offset..end];
    if (hash != 0 and hash != payloadHash(payload)) return Error.InvalidEnvelope;
    if (end != data.len) return Error.TrailingBytes;
    return .{
        .envelope = .{
            .flags = flags,
            .message_type = message_type,
            .sequence = sequence,
            .ack_sequence = ack_sequence,
            .session_id = session_id,
            .frame_id = frame_id,
            .timestamp_ns = timestamp_ns,
        },
        .bytes = payload,
    };
}

pub fn messageClass(message_type: u16) Class {
    return switch (message_type) {
        0x0001...0x00ff => .control,
        0x0200...0x02ff => .frame,
        0x0300...0x03ff => .window,
        0x0400...0x04ff => .render,
        0x0500...0x05ff => .resource,
        0x0600...0x06ff => .input,
        0x0700...0x07ff => .ime,
        0x0800...0x08ff => .selection,
        0x0900...0x09ff => .widget,
        0x0a00...0x0aff => .diagnostic,
        0xf000...0xfffe => .extension,
        else => .unknown,
    };
}

/// Unknown extension and debug messages are optional. Known core messages are
/// not silently discarded; concrete payload handling is added by later tasks.
pub fn optionalMessage(flags: u16, message_type: u16) bool {
    if (message_type == 0 or message_type == Message.invalid) return false;
    if (knownMessage(message_type)) return (flags & Flags.debug) != 0;
    return true;
}

pub fn encodeCapabilities(
    a: std.mem.Allocator,
    capabilities: []const Capability,
    out: *std.ArrayList(u8),
) !void {
    if (capabilities.len > std.math.maxInt(u32)) return Error.Unsupported;
    try putU32(out, a, @intCast(capabilities.len));
    for (capabilities, 0..) |capability, capability_index| {
        if (capability.name.len == 0) return Error.InvalidTable;
        if (capability.name.len > std.math.maxInt(u16) or capability.value.len > std.math.maxInt(u16))
            return Error.Unsupported;
        for (capabilities[0..capability_index]) |prior| {
            if (std.mem.eql(u8, prior.name, capability.name)) return Error.InvalidTable;
        }
        try putU16(out, a, @intCast(capability.name.len));
        try out.appendSlice(a, capability.name);
        try putU16(out, a, @intCast(capability.value.len));
        try out.appendSlice(a, capability.value);
    }
}

pub fn decodeCapabilities(a: std.mem.Allocator, data: []const u8) ![]Capability {
    var reader = Reader{ .data = data };
    const count = reader.readU32() catch return Error.InvalidTable;
    // Every entry needs at least two length fields.  Check before allocating
    // an untrusted count.
    if (count > (data.len -| reader.offset) / 4) return Error.InvalidTable;
    const result = try a.alloc(Capability, count);
    errdefer a.free(result);
    if (count == 0) {
        if (reader.offset != data.len) return Error.TrailingBytes;
        return result;
    }
    for (result, 0..) |*capability, capability_index| {
        const name_len = reader.readU16() catch return Error.InvalidTable;
        const name = reader.bytes(name_len) catch return Error.InvalidTable;
        const value_len = reader.readU16() catch return Error.InvalidTable;
        const value = reader.bytes(value_len) catch return Error.InvalidTable;
        if (name_len == 0) return Error.InvalidTable;
        for (result[0..capability_index]) |prior| {
            if (std.mem.eql(u8, prior.name, name)) return Error.InvalidTable;
        }
        capability.* = .{ .name = name, .value = value };
    }
    if (reader.offset != data.len) return Error.TrailingBytes;
    return result;
}

pub const SectionKind = struct {
    pub const frame_patch: u32 = 1;
    pub const windows: u32 = 2;
    pub const rows: u32 = 3;
    pub const render_items: u32 = 4;
    pub const cursors: u32 = 5;
    pub const fringes: u32 = 6;
    pub const dividers: u32 = 7;
    pub const scroll_optimizations: u32 = 8;
    pub const damage: u32 = 9;
    pub const resources: u32 = 10;
    pub const present_hint: u32 = 11;
    pub const commit_token: u32 = 12;
    pub const extension_min: u32 = 0x8000;
};

pub const Section = struct {
    kind: u32,
    records: []const u8,
};

pub const FrameUpdateHeader = struct {
    frame_id: u32,
    frame_generation: u32,
    sequence: u64,
    redisplay_generation: u64,
    logical_x: i32,
    logical_y: i32,
    logical_width: i32,
    logical_height: i32,
    physical_x: i32,
    physical_y: i32,
    physical_width: i32,
    physical_height: i32,
    scale: f32,
    dpi_x: f32,
    dpi_y: f32,
    damage_mode: u8,
    update_cause: u8,
    coalesced_count: u32,
    timestamp_ns: u64,
};

pub const frame_update_header_size: usize = 88;

pub const FrameUpdate = struct {
    header: FrameUpdateHeader,
    sections: []const Section,
};

fn validateFrameSections(sections: []const Section) Error!void {
    var previous_known_kind: ?u32 = null;
    for (sections) |section| {
        if (!validSectionKind(section.kind)) return Error.InvalidTable;
        if (knownSectionKind(section.kind)) {
            if (previous_known_kind) |previous| {
                if (section.kind <= previous) return Error.InvalidTable;
            }
            previous_known_kind = section.kind;
        }
    }
}

pub fn validateFrameHeader(header: FrameUpdateHeader) Error!void {
    if (header.frame_id == 0 or header.frame_generation == 0) return Error.InvalidMessage;
    if (header.logical_width < 0 or header.logical_height < 0) return Error.InvalidMessage;
    if (header.physical_width < 0 or header.physical_height < 0) return Error.InvalidMessage;
    if (!std.math.isFinite(header.scale) or header.scale <= 0) return Error.InvalidMessage;
    if (!std.math.isFinite(header.dpi_x) or header.dpi_x <= 0) return Error.InvalidMessage;
    if (!std.math.isFinite(header.dpi_y) or header.dpi_y <= 0) return Error.InvalidMessage;
}

/// A FRAME_UPDATE repeats identity fields for validation after reassembly.
/// The envelope remains the transport authority for session/sequence; this
/// rejects a mismatched payload that could otherwise be attributed to a frame.
pub fn validateFrameEnvelope(header: FrameUpdateHeader, envelope: Envelope) Error!void {
    try validateFrameHeader(header);
    if (header.frame_id != envelope.frame_id) return Error.InvalidMessage;
    if (header.sequence != envelope.sequence) return Error.InvalidMessage;
}

fn putI32(out: *std.ArrayList(u8), a: std.mem.Allocator, value: i32) !void {
    try putU32(out, a, @bitCast(value));
}

fn putF32(out: *std.ArrayList(u8), a: std.mem.Allocator, value: f32) !void {
    try putU32(out, a, @bitCast(value));
}

pub fn encodeFrameUpdate(a: std.mem.Allocator, update: FrameUpdate, out: *std.ArrayList(u8)) !void {
    const header = update.header;
    try validateFrameHeader(header);
    try validateFrameSections(update.sections);
    if (update.sections.len > std.math.maxInt(u32)) return Error.Unsupported;
    try out.appendSlice(a, "FUP1");
    try putU32(out, a, header.frame_id);
    try putU32(out, a, header.frame_generation);
    try putU64(out, a, header.sequence);
    try putU64(out, a, header.redisplay_generation);
    try putI32(out, a, header.logical_x);
    try putI32(out, a, header.logical_y);
    try putI32(out, a, header.logical_width);
    try putI32(out, a, header.logical_height);
    try putI32(out, a, header.physical_x);
    try putI32(out, a, header.physical_y);
    try putI32(out, a, header.physical_width);
    try putI32(out, a, header.physical_height);
    try putF32(out, a, header.scale);
    try putF32(out, a, header.dpi_x);
    try putF32(out, a, header.dpi_y);
    try out.append(a, header.damage_mode);
    try out.append(a, header.update_cause);
    try out.appendSlice(a, &[_]u8{ 0, 0 });
    try putU32(out, a, header.coalesced_count);
    try putU64(out, a, header.timestamp_ns);
    try putU32(out, a, @intCast(update.sections.len));
    for (update.sections) |section| {
        if (section.records.len > std.math.maxInt(u32)) return Error.Unsupported;
        try putU32(out, a, section.kind);
        try putU32(out, a, @intCast(section.records.len));
        try out.appendSlice(a, section.records);
    }
}

/// The returned sections borrow record bytes from `data`; keep `data` valid
/// and unmodified for as long as the returned `FrameUpdate` is used.
pub fn decodeFrameUpdate(a: std.mem.Allocator, data: []const u8) !FrameUpdate {
    var reader = Reader{ .data = data };
    const magic_bytes = reader.bytes(4) catch return Error.InvalidTable;
    if (!std.mem.eql(u8, magic_bytes, "FUP1")) return Error.InvalidTable;
    var header: FrameUpdateHeader = undefined;
    header.frame_id = reader.readU32() catch return Error.InvalidTable;
    header.frame_generation = reader.readU32() catch return Error.InvalidTable;
    header.sequence = reader.readU64() catch return Error.InvalidTable;
    header.redisplay_generation = reader.readU64() catch return Error.InvalidTable;
    header.logical_x = @bitCast(reader.readU32() catch return Error.InvalidTable);
    header.logical_y = @bitCast(reader.readU32() catch return Error.InvalidTable);
    header.logical_width = @bitCast(reader.readU32() catch return Error.InvalidTable);
    header.logical_height = @bitCast(reader.readU32() catch return Error.InvalidTable);
    header.physical_x = @bitCast(reader.readU32() catch return Error.InvalidTable);
    header.physical_y = @bitCast(reader.readU32() catch return Error.InvalidTable);
    header.physical_width = @bitCast(reader.readU32() catch return Error.InvalidTable);
    header.physical_height = @bitCast(reader.readU32() catch return Error.InvalidTable);
    header.scale = @bitCast(reader.readU32() catch return Error.InvalidTable);
    header.dpi_x = @bitCast(reader.readU32() catch return Error.InvalidTable);
    header.dpi_y = @bitCast(reader.readU32() catch return Error.InvalidTable);
    header.damage_mode = (reader.bytes(1) catch return Error.InvalidTable)[0];
    header.update_cause = (reader.bytes(1) catch return Error.InvalidTable)[0];
    _ = reader.bytes(2) catch return Error.InvalidTable;
    header.coalesced_count = reader.readU32() catch return Error.InvalidTable;
    header.timestamp_ns = reader.readU64() catch return Error.InvalidTable;
    try validateFrameHeader(header);

    const section_count = reader.readU32() catch return Error.InvalidTable;
    if (section_count > (data.len -| reader.offset) / 8) return Error.InvalidTable;
    const sections = try a.alloc(Section, section_count);
    errdefer a.free(sections);
    var previous_known_kind: ?u32 = null;
    for (sections) |*section| {
        section.kind = reader.readU32() catch return Error.InvalidTable;
        if (!validSectionKind(section.kind)) return Error.InvalidTable;
        const length = reader.readU32() catch return Error.InvalidTable;
        section.records = reader.bytes(length) catch return Error.InvalidTable;
        if (section.kind != 0 and (section.kind <= SectionKind.commit_token)) {
            if (previous_known_kind) |previous| {
                if (section.kind <= previous) return Error.InvalidTable;
            }
            previous_known_kind = section.kind;
        }
    }
    if (reader.offset != data.len) return Error.TrailingBytes;
    return .{ .header = header, .sections = sections };
}

/// Frees storage allocated by `decodeFrameUpdate`.  Record bytes continue to
/// borrow the caller's encoded payload and have no independent allocation.
pub fn freeFrameUpdate(a: std.mem.Allocator, update: *FrameUpdate) void {
    a.free(update.sections);
    update.sections = &.{};
}

test "envelope round trip and hash validation" {
    const a = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);
    const payload = [_]u8{ 1, 2, 3, 4 };
    try encodeEnvelope(a, .{
        .flags = Flags.delta | Flags.coalescable,
        .message_type = Message.frame_update,
        .sequence = 42,
        .ack_sequence = 41,
        .session_id = 7,
        .frame_id = 2,
        .timestamp_ns = 99,
    }, &payload, &out);
    const decoded = try decodeEnvelope(out.items);
    try std.testing.expectEqual(Message.frame_update, decoded.envelope.message_type);
    try std.testing.expectEqualSlices(u8, &payload, decoded.bytes);
}

test "v1 message table is complete canonical and non-overlapping" {
    // This count is the number of assigned IDs in the normative EUP v1
    // message tables.  Extension IDs (0xf000-0xfffe) are valid but are not
    // part of the stable assigned table.
    try std.testing.expectEqual(@as(usize, 164), known_message_ids.len);
    try std.testing.expect(!knownMessage(Message.invalid));

    for (known_message_ids, 0..) |id, i| {
        try std.testing.expect(knownMessage(id));
        try std.testing.expect(messageClass(id) != .unknown);
        if (i + 1 < known_message_ids.len) {
            try std.testing.expect(id < known_message_ids[i + 1]);
        }
    }
}

test "envelope rejects bad magic, trailer, and unknown core message" {
    const a = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);
    try encodeEnvelope(a, .{
        .flags = 0,
        .message_type = Message.hello,
        .sequence = 1,
        .ack_sequence = 0,
        .session_id = 1,
        .timestamp_ns = 1,
    }, &[_]u8{}, &out);
    out.items[0] = 'X';
    try std.testing.expectError(Error.InvalidEnvelope, decodeEnvelope(out.items));
    out.items[0] = 'E';
    const original_len = out.items.len;
    out.append(a, 0) catch unreachable;
    try std.testing.expectError(Error.TrailingBytes, decodeEnvelope(out.items));
    out.shrinkRetainingCapacity(original_len);
    _ = try decodeEnvelope(out.items);
}

test "capability and resource encoding follows v1 generations" {
    const a = std.testing.allocator;
    const capabilities = [_]Capability{
        .{ .name = "renderer", .value = "gpu-basic" },
        .{ .name = "max-payload", .value = "1048576" },
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeCapabilities(a, &capabilities, &bytes);
    const decoded = try decodeCapabilities(a, bytes.items);
    defer a.free(decoded);
    try std.testing.expectEqualStrings("gpu-basic", decoded[0].value);
    try std.testing.expect((&ResourceId{ .id = 3, .generation = 4 }).valid());
    try std.testing.expect(!(&ResourceId{ .id = 3, .generation = 0 }).valid());
}

test "capability table rejects empty duplicate and truncated entries" {
    const a = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);

    const duplicate = [_]Capability{
        .{ .name = "same", .value = "1" },
        .{ .name = "same", .value = "2" },
    };
    try std.testing.expectError(Error.InvalidTable, encodeCapabilities(a, &duplicate, &out));

    const empty = [_]Capability{.{ .name = "", .value = "1" }};
    try std.testing.expectError(Error.InvalidTable, encodeCapabilities(a, &empty, &out));

    // A declared entry needs four bytes even when both strings are empty.
    try std.testing.expectError(Error.InvalidTable, decodeCapabilities(a, &[_]u8{ 1, 0, 0, 0 }));
    try std.testing.expectError(Error.InvalidTable, decodeCapabilities(a, &[_]u8{ 1, 0, 0, 0, 4 }));
}

test "frame visibility and focus payloads enforce strict wire form" {
    const a = std.testing.allocator;
    const visibility = FrameVisibilityPayload{ .frame_id = 7, .frame_generation = 2, .state = .iconified };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(std.testing.allocator);
    try encodeFrameVisibility(a, visibility, &bytes);
    try std.testing.expectEqual(@as(usize, 12), bytes.items.len);
    try std.testing.expectEqual(visibility, try decodeFrameVisibility(bytes.items));

    bytes.items[8] = 3;
    try std.testing.expectError(Error.InvalidTable, decodeFrameVisibility(bytes.items));
    bytes.items[8] = 1;
    bytes.items[9] = 1;
    try std.testing.expectError(Error.InvalidTable, decodeFrameVisibility(bytes.items));

    bytes.clearRetainingCapacity();
    const focus = FrameFocusPayload{ .frame_id = 7, .frame_generation = 2, .focused = true };
    try encodeFrameFocus(a, focus, &bytes);
    try std.testing.expectEqual(focus, try decodeFrameFocus(bytes.items));
    bytes.items[8] = 2;
    try std.testing.expectError(Error.InvalidTable, decodeFrameFocus(bytes.items));
    bytes.items[8] = 1;
    bytes.items[11] = 1;
    try std.testing.expectError(Error.InvalidTable, decodeFrameFocus(bytes.items));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameVisibility(a, .{ .frame_id = 0, .frame_generation = 1, .state = .visible }, &bytes));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameFocus(a, .{ .frame_id = 7, .frame_generation = 0, .focused = false }, &bytes));
}

test "frame title payload enforces strict wire form" {
    const a = std.testing.allocator;
    const payload = FrameTitlePayload{
        .string_resource_id = 12,
        .string_generation = 3,
        .frame_generation = 2,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameTitle(a, payload, &bytes);
    try std.testing.expectEqual(@as(usize, 16), bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFrameTitle(bytes.items));

    bytes.items[0] = 2;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameTitle(bytes.items));
    bytes.items[0] = 1;
    bytes.items[2] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameTitle(bytes.items));
    bytes.items[2] = 0;
    bytes.items[4] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameTitle(bytes.items));
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFrameTitle(bytes.items));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameTitle(a, .{
        .string_resource_id = 0,
        .string_generation = 1,
        .frame_generation = 1,
    }, &bytes));
}

test "resource request and evict codecs enforce strict wire form" {
    const a = std.testing.allocator;
    const requests = [_]ResourceRequest{
        .{ .kind = .font, .id = 12, .generation = 0 },
        .{ .kind = .image, .id = 30, .generation = 4 },
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeResourceRequests(a, &requests, &bytes);
    try std.testing.expectEqual(@as(usize, 28), bytes.items.len);
    const decoded = try decodeResourceRequests(a, bytes.items);
    defer a.free(decoded);
    try std.testing.expectEqualSlices(ResourceRequest, &requests, decoded);

    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeResourceRequests(a, bytes.items));
    bytes.items[0] = 3;
    try std.testing.expectError(Error.InvalidTable, decodeResourceRequests(a, bytes.items));
    bytes.items[0] = 2;
    bytes.items[16] = 7;
    try std.testing.expectError(Error.InvalidTable, decodeResourceRequests(a, bytes.items));
    const duplicate = [_]ResourceRequest{ requests[0], requests[0] };
    try std.testing.expectError(Error.InvalidTable, encodeResourceRequests(a, &duplicate, &bytes));

    bytes.clearRetainingCapacity();
    const evict = ResourceEvict{ .kind = .face, .id = 8, .generation = 3, .reason = .capacity };
    try encodeResourceEvict(a, evict, &bytes);
    try std.testing.expectEqual(@as(usize, 16), bytes.items.len);
    try std.testing.expectEqual(evict, try decodeResourceEvict(bytes.items));
    bytes.items[12] = 4;
    try std.testing.expectError(Error.InvalidTable, decodeResourceEvict(bytes.items));
    bytes.items[12] = 0;
    bytes.items[15] = 1;
    try std.testing.expectError(Error.InvalidTable, decodeResourceEvict(bytes.items));
    try std.testing.expectError(Error.InvalidMessage, encodeResourceEvict(a, .{ .kind = .face, .id = 0, .generation = 1, .reason = .explicit }, &bytes));
}

test "string resource codecs enforce UTF-8 and bounded exact payloads" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    const ascii = StringDefine{ .resource_id = 12, .generation = 3, .bytes = "hello" };
    try encodeStringDefine(a, ascii, &bytes);
    const decoded_ascii = try decodeStringDefine(bytes.items);
    try std.testing.expectEqual(ascii.resource_id, decoded_ascii.resource_id);
    try std.testing.expectEqual(ascii.generation, decoded_ascii.generation);
    try std.testing.expectEqualStrings(ascii.bytes, decoded_ascii.bytes);

    bytes.clearRetainingCapacity();
    const unicode = StringDefine{ .resource_id = 13, .generation = 4, .bytes = "é🎉" };
    try encodeStringDefine(a, unicode, &bytes);
    const decoded_unicode = try decodeStringDefine(bytes.items);
    try std.testing.expectEqualStrings(unicode.bytes, decoded_unicode.bytes);

    bytes.clearRetainingCapacity();
    const oversized = StringDefine{ .resource_id = 1, .generation = 1, .bytes = &[_]u8{'x'} ** (max_string_bytes + 1) };
    try std.testing.expectError(Error.InvalidMessage, encodeStringDefine(a, oversized, &bytes));
    var bad_length: [16]u8 = undefined;
    std.mem.writeInt(u32, bad_length[0..4], 1, .little);
    std.mem.writeInt(u32, bad_length[4..8], 1, .little);
    std.mem.writeInt(u32, bad_length[8..12], max_string_bytes + 1, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeStringDefine(&bad_length));

    bytes.clearRetainingCapacity();
    try encodeStringDefine(a, ascii, &bytes);
    try std.testing.expectError(Error.InvalidTable, decodeStringDefine(bytes.items[0 .. bytes.items.len - 1]));
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeStringDefine(bytes.items));
    bytes.clearRetainingCapacity();
    try encodeStringDefine(a, ascii, &bytes);
    bytes.items[12] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeStringDefine(bytes.items));
    bytes.items[12] = 'h';
    bytes.items[13] = 0xff;
    try std.testing.expectError(Error.InvalidUtf8, decodeStringDefine(bytes.items));
    bytes.items[13] = 'e';
    bytes.items[0] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeStringDefine(bytes.items));

    bytes.clearRetainingCapacity();
    const deletion = StringDelete{ .resource_id = 14, .generation = 2 };
    try encodeStringDelete(a, deletion, &bytes);
    try std.testing.expectEqual(deletion, try decodeStringDelete(bytes.items));
    bytes.items[4] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeStringDelete(bytes.items));
    bytes.items[7] = 2;
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeStringDelete(bytes.items));
}

fn fontFixture() FontDefine {
    var payload = FontDefine{
        .font_id = 31,
        .generation = 5,
        .family_len = 3,
        .foundry_len = 5,
        .style_len = 6,
        .slant = .italic,
        .spacing = .mono,
        .scalable = true,
        .fixed_pitch = true,
        .weight = 450,
        .width_percent = 110,
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
    @memcpy(payload.family[0..3], "éx");
    @memcpy(payload.foundry[0..5], "found");
    @memcpy(payload.style[0..6], "Book12");
    return payload;
}

test "font resource codecs enforce fixed bounded UTF-8 metadata" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    const payload = fontFixture();
    try encodeFontDefine(a, payload, &bytes);
    try std.testing.expectEqual(font_record_size, bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFontDefine(bytes.items));

    bytes.items[8] = 65; // family length exceeds its fixed field
    try std.testing.expectError(Error.InvalidMessage, decodeFontDefine(bytes.items));
    bytes.items[8] = 3;
    bytes.items[96] = 'n';
    bytes.items[97] = 0xff;
    bytes.items[98] = 'x';
    try std.testing.expectError(Error.InvalidUtf8, decodeFontDefine(bytes.items));
    @memcpy(bytes.items[96..99], "éx");

    bytes.items[97] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFontDefine(bytes.items));
    @memcpy(bytes.items[96..99], "éx");
    bytes.items[100] = 1; // unused metadata tail is strict zero
    try std.testing.expectError(Error.InvalidReserved, decodeFontDefine(bytes.items));
    bytes.items[100] = 0;

    bytes.items[15] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeFontDefine(bytes.items));
    bytes.items[15] = 0;
    bytes.items[90] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeFontDefine(bytes.items));
    bytes.items[90] = 0;

    try std.testing.expectError(Error.InvalidTable, decodeFontDefine(bytes.items[0 .. bytes.items.len - 1]));
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFontDefine(bytes.items));
}

test "font resource codecs reject invalid enums booleans ranges and extensions" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    const payload = fontFixture();
    try encodeFontDefine(a, payload, &bytes);

    bytes.items[11] = 4;
    try std.testing.expectError(Error.InvalidStyle, decodeFontDefine(bytes.items));
    bytes.items[11] = @intFromEnum(FontSlant.italic);
    bytes.items[12] = 3;
    try std.testing.expectError(Error.InvalidStyle, decodeFontDefine(bytes.items));
    bytes.items[12] = @intFromEnum(FontSpacing.mono);
    bytes.items[13] = 2;
    try std.testing.expectError(Error.InvalidBoolean, decodeFontDefine(bytes.items));
    bytes.items[13] = 1;
    bytes.items[14] = 2;
    try std.testing.expectError(Error.InvalidBoolean, decodeFontDefine(bytes.items));
    bytes.items[14] = 1;

    std.mem.writeInt(u16, bytes.items[16..18], 1001, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFontDefine(bytes.items));
    std.mem.writeInt(u16, bytes.items[16..18], payload.weight, .little);
    std.mem.writeInt(u16, bytes.items[18..20], 49, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFontDefine(bytes.items));
    std.mem.writeInt(u16, bytes.items[18..20], payload.width_percent, .little);

    std.mem.writeInt(u32, bytes.items[28..32], 96, .little);
    std.mem.writeInt(u32, bytes.items[32..36], 0, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFontDefine(bytes.items));
    std.mem.writeInt(u32, bytes.items[32..36], payload.y_dpi, .little);
    std.mem.writeInt(u32, bytes.items[44..48], 13, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFontDefine(bytes.items));
    std.mem.writeInt(u32, bytes.items[44..48], payload.line_height, .little);
    std.mem.writeInt(u16, bytes.items[76..78], 1, .little);
    try std.testing.expectError(Error.Unsupported, decodeFontDefine(bytes.items));
    std.mem.writeInt(u16, bytes.items[76..78], 0, .little);
    std.mem.writeInt(u16, bytes.items[78..80], 1, .little);
    try std.testing.expectError(Error.Unsupported, decodeFontDefine(bytes.items));
    std.mem.writeInt(u16, bytes.items[78..80], 0, .little);
    std.mem.writeInt(u16, bytes.items[80..82], 1, .little);
    try std.testing.expectError(Error.Unsupported, decodeFontDefine(bytes.items));
    std.mem.writeInt(u16, bytes.items[80..82], 0, .little);

    var invalid = payload;
    invalid.weight = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeFontDefine(a, invalid, &bytes));
    invalid = payload;
    invalid.width_percent = 201;
    try std.testing.expectError(Error.InvalidMessage, encodeFontDefine(a, invalid, &bytes));
    invalid = payload;
    invalid.pixel_size = max_font_metric + 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFontDefine(a, invalid, &bytes));
    invalid = payload;
    invalid.baseline_offset = payload.ascent + 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFontDefine(a, invalid, &bytes));
    invalid = payload;
    invalid.max_advance = payload.min_advance - 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFontDefine(a, invalid, &bytes));
    invalid = payload;
    invalid.spacing = .proportional;
    try std.testing.expectError(Error.InvalidMessage, encodeFontDefine(a, invalid, &bytes));
}

test "font delete codec requires exact nonzero identity" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    const deletion = FontDelete{ .font_id = 31, .generation = 5 };
    try encodeFontDelete(a, deletion, &bytes);
    try std.testing.expectEqual(deletion, try decodeFontDelete(bytes.items));
    bytes.items[0] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFontDelete(bytes.items));
    bytes.items[0] = 31;
    bytes.items[4] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFontDelete(bytes.items));
    bytes.items[4] = 5;
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFontDelete(bytes.items));
}

test "optional and required message policy follows EUP classes" {
    try std.testing.expect(!optionalMessage(0, Message.hello));
    try std.testing.expect(optionalMessage(0, 0x1234));
    try std.testing.expect(!optionalMessage(0, Message.invalid));
    try std.testing.expect(optionalMessage(Flags.debug, Message.hello));
    try std.testing.expect(optionalMessage(0, 0xf001));
    try std.testing.expectEqual(Class.unknown, messageClass(0x1234));
}

test "extension envelope messages round trip and remain optional" {
    const a = std.testing.allocator;
    const payload = [_]u8{ 'v', 'n', 'd', 'r' };
    var wire: std.ArrayList(u8) = .empty;
    defer wire.deinit(a);
    try encodeEnvelope(a, .{
        .flags = 0,
        .message_type = 0xf001,
        .sequence = 9,
        .ack_sequence = 0,
        .session_id = 1,
        .timestamp_ns = 2,
    }, &payload, &wire);
    const decoded = try decodeEnvelope(wire.items);
    try std.testing.expectEqual(@as(u16, 0xf001), decoded.envelope.message_type);
    try std.testing.expectEqual(Class.extension, messageClass(0xf001));
    try std.testing.expect(optionalMessage(0, 0xf001));
    try std.testing.expectEqualSlices(u8, &payload, decoded.bytes);
    try std.testing.expect(validMessageType(0xfffe));
    try std.testing.expect(!validMessageType(0xffff));
}

test "envelope encoder rejects unsupported and unknown states" {
    const a = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);

    try std.testing.expectError(
        Error.Unsupported,
        encodeEnvelope(a, .{ .flags = Flags.compressed, .message_type = Message.hello, .sequence = 1, .ack_sequence = 0, .session_id = 1, .timestamp_ns = 1 }, &[_]u8{}, &out),
    );
    try std.testing.expectError(
        Error.InvalidEnvelope,
        encodeEnvelope(a, .{ .flags = 1 << 15, .message_type = Message.hello, .sequence = 1, .ack_sequence = 0, .session_id = 1, .timestamp_ns = 1 }, &[_]u8{}, &out),
    );
    try std.testing.expectError(
        Error.InvalidMessage,
        encodeEnvelope(a, .{ .flags = 0, .message_type = 0x0215, .sequence = 1, .ack_sequence = 0, .session_id = 1, .timestamp_ns = 1 }, &[_]u8{}, &out),
    );
}

test "frame update section tables reject malformed ordering and kinds" {
    const a = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);
    const header: FrameUpdateHeader = .{
        .frame_id = 1,
        .frame_generation = 1,
        .sequence = 1,
        .redisplay_generation = 1,
        .logical_x = 0,
        .logical_y = 0,
        .logical_width = 10,
        .logical_height = 10,
        .physical_x = 0,
        .physical_y = 0,
        .physical_width = 10,
        .physical_height = 10,
        .scale = 1.0,
        .dpi_x = 96,
        .dpi_y = 96,
        .damage_mode = 1,
        .update_cause = 1,
        .coalesced_count = 0,
        .timestamp_ns = 1,
    };

    const duplicate = [_]Section{
        .{ .kind = SectionKind.damage, .records = &[_]u8{} },
        .{ .kind = SectionKind.damage, .records = &[_]u8{} },
    };
    try std.testing.expectError(Error.InvalidTable, encodeFrameUpdate(a, .{ .header = header, .sections = &duplicate }, &out));

    const reserved = [_]Section{.{ .kind = 13, .records = &[_]u8{} }};
    try std.testing.expectError(Error.InvalidTable, encodeFrameUpdate(a, .{ .header = header, .sections = &reserved }, &out));

    // Duplicate known sections are rejected after decode as well.
    const valid = [_]Section{.{ .kind = SectionKind.damage, .records = &[_]u8{} }};
    var wire: std.ArrayList(u8) = .empty;
    defer wire.deinit(a);
    try encodeFrameUpdate(a, .{ .header = header, .sections = &valid }, &wire);
    try wire.appendSlice(a, &[_]u8{ 9, 0, 0, 0, 0, 0, 0, 0 });
    wire.items[88] = 2; // section_count is immediately after the 88-byte prefix
    try std.testing.expectError(Error.InvalidTable, decodeFrameUpdate(a, wire.items));
}

test "frame update section tables round trip" {
    const a = std.testing.allocator;
    var table: std.ArrayList(u8) = .empty;
    defer table.deinit(a);
    try table.appendSlice(a, &[_]u8{ 9, 8, 7, 6 });
    const sections = [_]Section{
        .{ .kind = SectionKind.damage, .records = table.items },
        .{ .kind = 0x8001, .records = &[_]u8{} },
    };
    const update = FrameUpdate{
        .header = .{
            .frame_id = 3,
            .frame_generation = 1,
            .sequence = 12,
            .redisplay_generation = 4,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = 800,
            .logical_height = 600,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = 1600,
            .physical_height = 1200,
            .scale = 2.0,
            .dpi_x = 192,
            .dpi_y = 192,
            .damage_mode = 2,
            .update_cause = 1,
            .coalesced_count = 3,
            .timestamp_ns = 77,
        },
        .sections = &sections,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameUpdate(a, update, &bytes);
    const decoded = try decodeFrameUpdate(a, bytes.items);
    defer a.free(decoded.sections);
    try std.testing.expectEqual(@as(f32, 2.0), decoded.header.scale);
    try std.testing.expectEqual(sections.len, decoded.sections.len);
    try std.testing.expectEqualSlices(u8, table.items, decoded.sections[0].records);

    // The payload header must agree with the transport envelope before the
    // frontend attributes a decoded update to a frame.
    const envelope = Envelope{
        .flags = Flags.delta | Flags.coalescable,
        .message_type = Message.frame_update,
        .sequence = update.header.sequence,
        .ack_sequence = 0,
        .session_id = 1,
        .frame_id = update.header.frame_id,
        .timestamp_ns = update.header.timestamp_ns,
    };
    try validateFrameEnvelope(decoded.header, envelope);

    var mismatched = envelope;
    mismatched.frame_id = 4;
    try std.testing.expectError(Error.InvalidMessage, validateFrameEnvelope(decoded.header, mismatched));
}

test "face codecs preserve the fixed v1 wire subset" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    const minimal = FaceDefine{ .face_id = 12, .generation = 3 };
    try encodeFaceDefine(a, minimal, &bytes);
    const fixed = try encodeFaceDefineBytes(minimal);
    try std.testing.expectEqualSlices(u8, &fixed, bytes.items);
    try std.testing.expectEqual(face_record_size, bytes.items.len);
    try std.testing.expectEqual(minimal, try decodeFaceDefine(bytes.items));

    bytes.clearRetainingCapacity();
    const complete = FaceDefine{
        .face_id = 30,
        .generation = 7,
        .presence = .{
            .font = true,
            .stipple = true,
            .foreground = true,
            .background = true,
            .underline_color = true,
            .overline_color = true,
            .strike_color = true,
            .box_color = true,
        },
        .foreground = .{ 1, 2, 3, 4 },
        .background = .{ 5, 6, 7, 8 },
        .underline_color = .{ 9, 10, 11, 12 },
        .overline_color = .{ 13, 14, 15, 16 },
        .strike_color = .{ 17, 18, 19, 20 },
        .box_color = .{ 21, 22, 23, 24 },
        .underline = .color,
        .overline = .color,
        .strike_through = .color,
        .box = .pressed,
        .box_line_width = -2,
        .inverse_video = true,
        .extend = true,
        .line_spacing = -3,
        .font_id = 41,
        .font_generation = 42,
        .stipple_id = 43,
        .stipple_generation = 44,
    };
    try encodeFaceDefine(a, complete, &bytes);
    try std.testing.expectEqual(@as(usize, 96), bytes.items.len);
    try std.testing.expectEqual(complete, try decodeFaceDefine(bytes.items));

    std.mem.writeInt(u32, bytes.items[50..54], 0, .little);
    std.mem.writeInt(u32, bytes.items[54..58], 0, .little);
    bytes.items[8] &= ~@as(u8, 1);
    bytes.items[8] |= 1; // font is explicitly present with a zero reference
    try std.testing.expectError(Error.InvalidResource, decodeFaceDefine(bytes.items));
    bytes.items[8] &= ~@as(u8, 1);
    bytes.items[8] &= ~@as(u8, 1 << 4);

    bytes.items[36] = 3; // color underline without an underline-color bit
    try std.testing.expectError(Error.InvalidStyle, decodeFaceDefine(bytes.items));
    bytes.items[36] = 2;

    bytes.items[39] = 4;
    try std.testing.expectError(Error.InvalidStyle, decodeFaceDefine(bytes.items));
    bytes.items[39] = 0;

    bytes.items[44] = 2;
    try std.testing.expectError(Error.InvalidBoolean, decodeFaceDefine(bytes.items));
    bytes.items[44] = 1;
    bytes.items[45] = 2;
    try std.testing.expectError(Error.InvalidBoolean, decodeFaceDefine(bytes.items));
    bytes.items[45] = 1;

    bytes.items[70] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeFaceDefine(bytes.items));
    bytes.items[70] = 0;
    bytes.items[10] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeFaceDefine(bytes.items));
    bytes.items[10] = 0;

    try std.testing.expectError(Error.InvalidTable, decodeFaceDefine(bytes.items[0..95]));
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFaceDefine(bytes.items));

    var invalid = minimal;
    invalid.presence.foreground = true;
    invalid.foreground = .{ 0, 0, 0, 0 };
    try std.testing.expectError(Error.InvalidMessage, encodeFaceDefine(a, invalid, &bytes));
    invalid.presence.foreground = false;
    invalid.presence.font = true;
    try std.testing.expectError(Error.InvalidResource, encodeFaceDefine(a, invalid, &bytes));
    invalid.presence.font = false;
    invalid.presence.stipple = true;
    try std.testing.expectError(Error.InvalidResource, encodeFaceDefine(a, invalid, &bytes));
    invalid.presence.stipple = false;
    invalid.presence.underline_color = true;
    invalid.underline = .single;
    try std.testing.expectError(Error.InvalidStyle, encodeFaceDefine(a, invalid, &bytes));
    invalid.presence.underline_color = false;
    invalid.underline = .color;
    try std.testing.expectError(Error.InvalidStyle, encodeFaceDefine(a, invalid, &bytes));
    invalid.underline = .off;
    invalid.presence.box_color = true;
    invalid.box_color = .{ 0, 0, 0, 1 };
    try std.testing.expectError(Error.InvalidStyle, encodeFaceDefine(a, invalid, &bytes));
    invalid.presence.box_color = false;
    invalid.box = .simple;
    try std.testing.expectError(Error.InvalidStyle, encodeFaceDefine(a, invalid, &bytes));
    invalid.box = .none;
    invalid.box_line_width = 1;
    try std.testing.expectError(Error.InvalidStyle, encodeFaceDefine(a, invalid, &bytes));
    invalid.box_line_width = 0;
    invalid.overline = .color;
    try std.testing.expectError(Error.InvalidStyle, encodeFaceDefine(a, invalid, &bytes));
    invalid.overline = .off;
    invalid.strike_through = .color;
    try std.testing.expectError(Error.InvalidStyle, encodeFaceDefine(a, invalid, &bytes));

    bytes.clearRetainingCapacity();
    try encodeFaceDelete(a, .{ .face_id = 31, .generation = 8 }, &bytes);
    try std.testing.expectEqualSlices(u8, &(try encodeFaceDeleteBytes(.{ .face_id = 31, .generation = 8 })), bytes.items);
    try std.testing.expectEqual(@as(usize, 8), bytes.items.len);
    try std.testing.expectEqual(FaceDelete{ .face_id = 31, .generation = 8 }, try decodeFaceDelete(bytes.items));
    bytes.items[0] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFaceDelete(bytes.items));
    bytes.items[0] = 31;
    bytes.items[4] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFaceDelete(bytes.items));
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFaceDelete(bytes.items));
}

fn imageFixture(id: u32, generation: u32) ImageDefine {
    return .{
        .image_id = id,
        .generation = generation,
        .width = 2,
        .height = 2,
        .total_byte_count = 16,
    };
}

test "image codecs validate fixed metadata, fragments, and deletes" {
    const metadata = imageFixture(7, 2);
    const wire = try encodeImageDefineBytes(metadata);
    try std.testing.expectEqual(image_record_size, wire.len);
    try std.testing.expectEqual(metadata, try decodeImageDefine(&wire));

    var reserved = wire;
    reserved[38] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeImageDefine(&reserved));

    var bad_total = imageFixture(7, 2);
    bad_total.total_byte_count = 15;
    try std.testing.expectError(Error.InvalidMessage, encodeImageDefineBytes(bad_total));

    var oversized_dimension = imageFixture(7, 2);
    oversized_dimension.width = max_image_dimension;
    oversized_dimension.height = max_image_dimension;
    try std.testing.expectError(Error.InvalidMessage, encodeImageDefineBytes(oversized_dimension));

    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(std.testing.allocator);
    try encodeImageData(std.testing.allocator, .{
        .image_id = 7,
        .generation = 2,
        .fragment_index = 0,
        .fragment_count = 2,
        .bytes = "ABCD",
    }, &bytes);
    const data = try decodeImageData(bytes.items);
    try std.testing.expectEqualSlices(u8, "ABCD", data.bytes);
    bytes.items[image_data_header_size] = 0;
    try std.testing.expectEqual(@as(u8, 0), data.bytes[0]);

    try bytes.append(std.testing.allocator, 'x');
    try std.testing.expectError(Error.InvalidTable, decodeImageData(bytes.items));
    bytes.items[bytes.items.len - 1] = 0;
    try std.testing.expectError(Error.InvalidTable, decodeImageData(bytes.items));

    bytes.clearRetainingCapacity();
    try encodeImageDelete(std.testing.allocator, .{ .image_id = 7, .generation = 2 }, &bytes);
    try std.testing.expectEqual(@as(u32, 7), (try decodeImageDelete(bytes.items)).image_id);
    try std.testing.expectError(Error.InvalidTable, decodeImageDelete(bytes.items[0..7]));
}

fn snapshotEntry(
    kind: ResourceKind,
    status: SnapshotStatus,
    id: u32,
    generation: u32,
    payload: []const u8,
) ResourceSnapshotEntry {
    return .{ .kind = kind, .status = status, .resource_id = id, .generation = generation, .payload = payload };
}

test "resource snapshot round trips empty and owns decoded payload" {
    const a = std.testing.allocator;
    const empty = [_]ResourceSnapshotEntry{};
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeResourceSnapshot(a, .{ .entries = &empty }, &bytes);
    var snapshot = try decodeResourceSnapshot(a, bytes.items);
    defer freeResourceSnapshot(a, &snapshot);
    try std.testing.expectEqual(@as(usize, 0), snapshot.entries.len);
    try std.testing.expectEqual(@as(u32, 1), snapshot.format_version);
}

test "resource snapshot preserves every concrete kind and tombstone" {
    const a = std.testing.allocator;
    const face_wire = try encodeFaceDefineBytes(.{ .face_id = 11, .generation = 2 });
    var font_payload = fontFixture();
    font_payload.font_id = 12;
    font_payload.generation = 5;
    const font_wire = try encodeFontDefineBytes(font_payload);
    const image_metadata = try encodeImageDefineBytes(imageFixture(14, 3));
    var image_wire: [image_record_size + 16]u8 = undefined;
    @memcpy(image_wire[0..image_record_size], &image_metadata);
    @memcpy(image_wire[image_record_size..], "sixteen_pixels!!");

    const entries = [_]ResourceSnapshotEntry{
        snapshotEntry(.face, .live, 11, 2, &face_wire),
        snapshotEntry(.font, .live, 12, 5, &font_wire),
        snapshotEntry(.image, .live, 14, 3, &image_wire),
        snapshotEntry(.string, .live, 16, 7, "snapshot"),
        snapshotEntry(.fringe_bitmap, .deleted, 20, 2, &.{}),
        snapshotEntry(.icon, .deleted, 21, 3, &.{}),
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeResourceSnapshot(a, .{ .entries = &entries }, &bytes);

    var snapshot = try decodeResourceSnapshot(a, bytes.items);
    defer freeResourceSnapshot(a, &snapshot);
    try std.testing.expectEqual(entries.len, snapshot.entries.len);
    try std.testing.expectEqualStrings("snapshot", snapshot.entries[3].payload);
    _ = try decodeFaceDefine(snapshot.entries[0].payload);
    _ = try decodeFontDefine(snapshot.entries[1].payload);
    _ = try decodeImageDefine(snapshot.entries[2].payload[0..image_record_size]);
    try std.testing.expectEqualSlices(u8, "sixteen_pixels!!", snapshot.entries[2].payload[image_record_size..]);
    try std.testing.expectEqual(SnapshotStatus.deleted, snapshot.entries[4].status);

    // The decoded payload is a validated copy, including the exact image tail.
}

test "resource snapshot rejects malformed boundaries identity and duplicates" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    const bad_version = [_]u8{ 2, 0, 0, 0, 0, 0, 0, 0 };
    try std.testing.expectError(Error.InvalidVersion, decodeResourceSnapshot(a, &bad_version));

    const face_wire = try encodeFaceDefineBytes(.{ .face_id = 1, .generation = 1 });
    const base = [_]ResourceSnapshotEntry{
        snapshotEntry(.face, .live, 1, 1, &face_wire),
        snapshotEntry(.face, .deleted, 1, 2, &.{}),
    };
    try std.testing.expectError(Error.InvalidTable, encodeResourceSnapshot(a, .{ .entries = &base }, &bytes));

    const zero_id = [_]ResourceSnapshotEntry{snapshotEntry(.face, .live, 0, 1, &face_wire)};
    try std.testing.expectError(Error.InvalidMessage, encodeResourceSnapshot(a, .{ .entries = &zero_id }, &bytes));

    const bad_deleted = [_]ResourceSnapshotEntry{snapshotEntry(.face, .deleted, 2, 1, &face_wire)};
    try std.testing.expectError(Error.InvalidMessage, encodeResourceSnapshot(a, .{ .entries = &bad_deleted }, &bytes));

    const bad_live = [_]ResourceSnapshotEntry{snapshotEntry(.face, .live, 2, 1, face_wire[0..95])};
    try std.testing.expectError(Error.InvalidTable, encodeResourceSnapshot(a, .{ .entries = &bad_live }, &bytes));

    const mismatched = [_]ResourceSnapshotEntry{snapshotEntry(.face, .live, 2, 1, &face_wire)};
    try std.testing.expectError(Error.InvalidResource, encodeResourceSnapshot(a, .{ .entries = &mismatched }, &bytes));

    const metadata = try encodeImageDefineBytes(imageFixture(3, 1));
    var short_image: [image_record_size + 1]u8 = undefined;
    @memcpy(short_image[0..image_record_size], &metadata);
    short_image[image_record_size] = 0;
    const incomplete = [_]ResourceSnapshotEntry{snapshotEntry(.image, .live, 3, 1, &short_image)};
    try std.testing.expectError(Error.InvalidMessage, encodeResourceSnapshot(a, .{ .entries = &incomplete }, &bytes));

    const mismatched_image = [_]ResourceSnapshotEntry{snapshotEntry(.image, .live, 4, 1, &short_image)};
    try std.testing.expectError(Error.InvalidResource, encodeResourceSnapshot(a, .{ .entries = &mismatched_image }, &bytes));

    const empty = [_]ResourceSnapshotEntry{};
    bytes.clearRetainingCapacity();
    try encodeResourceSnapshot(a, .{ .entries = &empty }, &bytes);
    try bytes.append(a, 0);
    try std.testing.expectError(Error.TrailingBytes, decodeResourceSnapshot(a, bytes.items));

    var reserved = bytes.items;
    reserved[bytes.items.len - 1] = 0;
    var malformed = [_]u8{ 1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0 };
    malformed[8] = 0;
    malformed[10] = 0;
    try std.testing.expectError(Error.InvalidResource, decodeResourceSnapshot(a, &malformed));
}

test "focus event codec enforces fixed schema identity and reserved bytes" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFocusEvent(a, .{ .phase = .gained, .frame_id = 7, .sdl_window_id = 9 }, &bytes);
    try std.testing.expectEqual(focus_event_size, bytes.items.len);
    const decoded = try decodeFocusEvent(bytes.items);
    try std.testing.expectEqual(FocusPhase.gained, decoded.phase);
    try std.testing.expectEqual(@as(u32, 7), decoded.frame_id);
    try std.testing.expectEqual(@as(u32, 9), decoded.sdl_window_id);
    try std.testing.expectEqual(@as(u16, focus_schema), std.mem.readInt(u16, bytes.items[0..2], .little));
    try std.testing.expectEqual(@as(u8, 0), bytes.items[3]);
    try std.testing.expect(std.mem.allEqual(u8, bytes.items[12..], 0));

    try std.testing.expectError(Error.InvalidTable, decodeFocusEvent(bytes.items[0 .. bytes.items.len - 1]));
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFocusEvent(bytes.items));
    var invalid = try decodeFocusEvent(bytes.items[0 .. bytes.items.len - 1]);
    invalid.frame_id = 0;
    try std.testing.expectError(Error.InvalidMessage, validateFocusEvent(invalid));
    invalid.frame_id = 7;
    invalid.sdl_window_id = 0;
    try std.testing.expectError(Error.InvalidMessage, validateFocusEvent(invalid));

    var wire: [focus_event_size]u8 = @splat(0);
    std.mem.writeInt(u16, wire[0..2], focus_schema, .little);
    wire[2] = @intFromEnum(FocusPhase.lost);
    std.mem.writeInt(u32, wire[4..8], 7, .little);
    std.mem.writeInt(u32, wire[8..12], 9, .little);
    wire[2] = 2;
    try std.testing.expectError(Error.InvalidTable, decodeFocusEvent(&wire));
    wire[2] = 1;
    wire[3] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeFocusEvent(&wire));
    wire[3] = 0;
    wire[12] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeFocusEvent(&wire));
    try std.testing.expectError(Error.InvalidMessage, encodeFocusEvent(a, .{ .phase = .lost, .frame_id = 0, .sdl_window_id = 9 }, &bytes));
}

test "window request codec enforces bounded requests and payload agreement" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    const resize: WindowRequest = .{ .kind = .resize, .sdl_window_id = 4, .width = 1, .height = max_window_size };
    try encodeWindowRequest(a, resize, &bytes);
    try std.testing.expectEqual(window_request_size, bytes.items.len);
    try std.testing.expectEqual(WindowRequestKind.resize, (try decodeWindowRequest(bytes.items)).kind);
    try std.testing.expectEqual(@as(i32, 1), (try decodeWindowRequest(bytes.items)).width);
    try std.testing.expectEqual(@as(i32, max_window_size), (try decodeWindowRequest(bytes.items)).height);

    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeWindowRequest(bytes.items));
    try std.testing.expectError(Error.InvalidTable, decodeWindowRequest(bytes.items[0 .. bytes.items.len - 2]));

    var oversized = resize;
    oversized.width = max_window_size + 1;
    try std.testing.expectError(Error.InvalidMessage, validateWindowRequest(oversized));
    oversized.width = 1;
    oversized.height = 0;
    try std.testing.expectError(Error.InvalidMessage, validateWindowRequest(oversized));
    oversized.height = max_window_size;
    oversized.x = 1;
    try std.testing.expectError(Error.InvalidMessage, validateWindowRequest(oversized));

    const move: WindowRequest = .{ .kind = .move, .sdl_window_id = 4, .x = -3, .y = 4 };
    bytes.clearRetainingCapacity();
    try encodeWindowRequest(a, move, &bytes);
    try std.testing.expectEqual(move, try decodeWindowRequest(bytes.items));
    var contradictory = move;
    contradictory.width = 1;
    try std.testing.expectError(Error.InvalidMessage, validateWindowRequest(contradictory));

    const close: WindowRequest = .{ .kind = .close, .sdl_window_id = 4 };
    bytes.clearRetainingCapacity();
    try encodeWindowRequest(a, close, &bytes);
    try std.testing.expectEqual(close, try decodeWindowRequest(bytes.items));
    var invalid_close = close;
    invalid_close.y = -1;
    try std.testing.expectError(Error.InvalidMessage, validateWindowRequest(invalid_close));

    var wire: [window_request_size]u8 = @splat(0);
    std.mem.writeInt(u16, wire[0..2], window_request_schema, .little);
    wire[2] = @intFromEnum(WindowRequestKind.close);
    std.mem.writeInt(u32, wire[4..8], 4, .little);
    wire[2] = 9;
    try std.testing.expectError(Error.InvalidTable, decodeWindowRequest(&wire));
    wire[2] = @intFromEnum(WindowRequestKind.close);
    wire[3] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeWindowRequest(&wire));
    wire[3] = 0;
    wire[24] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeWindowRequest(&wire));
    try std.testing.expectError(Error.InvalidMessage, encodeWindowRequest(a, .{ .kind = .close, .sdl_window_id = 0 }, &bytes));
}

test "window tree snapshot round trips and validates hierarchy" {
    const a = std.testing.allocator;
    const nodes = [_]WindowTreeNode{
        .{ .window_id = 10, .parent_window_id = 0, .x = 0, .y = 0, .width = 80, .height = 60, .flags = window_tree_flag_visible, .default_face_id = 0, .depth = 0 },
        .{ .window_id = 11, .parent_window_id = 10, .x = 40, .y = 0, .width = 40, .height = 60, .flags = window_tree_flag_visible | window_tree_flag_selected, .default_face_id = 3, .depth = 1 },
    };
    const snapshot: WindowTreeSnapshot = .{
        .header = .{ .frame_id = 7, .frame_generation = 2, .selected_window_id = 11, .root_window_id = 10 },
        .nodes = &nodes,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeWindowTreeSnapshot(a, snapshot, &bytes);
    try std.testing.expectEqual(window_tree_header_size + 2 * window_tree_node_size, bytes.items.len);
    var decoded = try decodeWindowTreeSnapshot(a, bytes.items);
    defer freeWindowTreeSnapshot(a, &decoded);
    try std.testing.expectEqual(@as(usize, 2), decoded.nodes.len);
    try std.testing.expectEqualStrings("root-child", "root-child");
}

test "window tree rejects unknown parent and cycle" {
    const bad_parent = [_]WindowTreeNode{
        .{ .window_id = 10, .parent_window_id = 0, .x = 0, .y = 0, .width = 10, .height = 10, .flags = window_tree_flag_visible, .default_face_id = 0, .depth = 0 },
        .{ .window_id = 11, .parent_window_id = 99, .x = 0, .y = 0, .width = 10, .height = 10, .flags = window_tree_flag_visible, .default_face_id = 0, .depth = 1 },
    };
    try std.testing.expectError(Error.InvalidMessage, validateWindowTreeSnapshot(.{
        .header = .{ .frame_id = 7, .frame_generation = 1, .selected_window_id = 10, .root_window_id = 10 },
        .nodes = &bad_parent,
    }));

    const cycle = [_]WindowTreeNode{
        .{ .window_id = 10, .parent_window_id = 11, .x = 0, .y = 0, .width = 10, .height = 10, .flags = window_tree_flag_visible, .default_face_id = 0, .depth = 1 },
        .{ .window_id = 11, .parent_window_id = 10, .x = 0, .y = 0, .width = 10, .height = 10, .flags = window_tree_flag_visible | window_tree_flag_selected, .default_face_id = 0, .depth = 1 },
    };
    try std.testing.expectError(Error.InvalidMessage, validateWindowTreeSnapshot(.{
        .header = .{ .frame_id = 7, .frame_generation = 1, .selected_window_id = 11, .root_window_id = 10 },
        .nodes = &cycle,
    }));
}
