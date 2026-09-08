const std = @import("std");

pub const major_version: u16 = 1;
pub const minor_version: u16 = 0;
pub const header_size: u16 = 62;
pub const max_rows: usize = 256;
pub const max_damage: usize = 256;
pub const max_opacity: u16 = 10000;
pub const max_frame_scale: f32 = 64.0;
pub const max_frame_dpi: f32 = 4096.0;

pub const FrameMonitorFlags = struct {
    pub const primary: u8 = 1 << 0;
};

pub const FrameMaximizeFlags = struct {
    pub const horizontal: u8 = 1 << 0;
    pub const vertical: u8 = 1 << 1;
    pub const both: u8 = horizontal | vertical;
};

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
    InvalidMenuHover,
    InvalidToolbarClick,
    InvalidDialogResult,
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
    pub const session_suspend: u16 = 0x0007;
    pub const session_resume: u16 = 0x0008;
    pub const session_resumed: u16 = 0x0009;
    pub const session_close: u16 = 0x000a;
    pub const ping: u16 = 0x000b;
    pub const pong: u16 = 0x000c;
    pub const session_error: u16 = 0x000d;
    pub const version_mismatch: u16 = 0x000e;
    pub const frame_create: u16 = 0x0200;
    pub const window_tree_snapshot: u16 = 0x0300;
    pub const window_create: u16 = 0x0301;
    pub const window_delete: u16 = 0x0303;
    pub const window_geometry: u16 = 0x0304;
    pub const window_zones: u16 = 0x0305;
    pub const window_face: u16 = 0x0306;
    pub const window_position: u16 = 0x0307;
    pub const mouse_highlight: u16 = 0x030a;
    pub const window_scroll_state: u16 = 0x0308;
    pub const window_patch: u16 = 0x0302;
    pub const frame_destroy: u16 = 0x0206;
    pub const frame_update: u16 = 0x0203;
    pub const frame_patch: u16 = 0x0201;
    pub const frame_snapshot: u16 = 0x0202;
    pub const frame_presented: u16 = 0x0204;
    pub const frame_dropped: u16 = 0x0205;
    pub const frame_visibility: u16 = 0x0208;
    pub const frame_title: u16 = 0x0209;
    pub const frame_icon: u16 = 0x020a;
    pub const frame_alpha: u16 = 0x020d;
    pub const frame_focus: u16 = 0x0210;
    pub const frame_decorations: u16 = 0x0214;
    pub const frame_size_hints: u16 = 0x0211;
    pub const frame_z_order: u16 = 0x0212;
    pub const frame_parent: u16 = 0x0213;
    pub const frame_scale: u16 = 0x020f;
    pub const frame_fullscreen: u16 = 0x020b;
    pub const frame_geometry: u16 = 0x0207;
    pub const frame_monitor: u16 = 0x020e;
    pub const frame_maximize: u16 = 0x020c;
    pub const resource_request: u16 = 0x0510;
    pub const resource_evict: u16 = 0x0511;
    pub const resource_snapshot: u16 = 0x0512;
    pub const face_define: u16 = 0x0500;
    pub const face_patch: u16 = 0x0501;
    pub const face_delete: u16 = 0x0502;
    pub const glyph_run: u16 = 0x0405;
    pub const glyph_run_delete: u16 = 0x0406;
    pub const cursor_update: u16 = 0x0407;
    pub const begin_update: u16 = 0x0400;
    pub const end_update: u16 = 0x0401;
    pub const row_snapshot: u16 = 0x0402;
    pub const row_update: u16 = 0x0403;
    pub const row_delete: u16 = 0x0404;
    pub const fringe_update: u16 = 0x0408;
    pub const clear_area: u16 = 0x040b;
    pub const divider_update: u16 = 0x0409;
    pub const border_update: u16 = 0x040a;
    pub const scroll_run: u16 = 0x040c;
    pub const damage_rects: u16 = 0x040d;
    pub const flush: u16 = 0x040e;
    pub const render_hint: u16 = 0x040f;
    pub const font_define: u16 = 0x0503;
    pub const font_patch: u16 = 0x0504;
    pub const font_metrics: u16 = 0x0505;
    pub const font_delete: u16 = 0x0506;
    pub const fringe_bitmap_define: u16 = 0x050a;
    pub const fringe_bitmap_delete: u16 = 0x050b;
    pub const image_define: u16 = 0x0507;
    pub const image_data: u16 = 0x0508;
    pub const image_delete: u16 = 0x0509;
    pub const atlas_define: u16 = 0x0513;
    pub const atlas_page_update: u16 = 0x0514;
    pub const atlas_glyph_add: u16 = 0x0515;
    pub const atlas_invalidate: u16 = 0x0516;
    pub const string_define: u16 = 0x050e;
    pub const string_delete: u16 = 0x050f;
    pub const tooltip_show: u16 = 0x0930;
    pub const tooltip_move: u16 = 0x0931;
    pub const tooltip_hide: u16 = 0x0932;
    pub const menu_model: u16 = 0x0900;
    pub const menu_patch: u16 = 0x0901;
    pub const menu_open: u16 = 0x0902;
    pub const menu_close: u16 = 0x0903;
    pub const menu_result: u16 = 0x0904;
    pub const menu_cancel: u16 = 0x0905;
    pub const menu_hover: u16 = 0x0906;
    pub const toolbar_model: u16 = 0x0910;
    pub const toolbar_patch: u16 = 0x0911;
    pub const dialog_open: u16 = 0x0920;
    pub const dialog_update: u16 = 0x0921;
    pub const dialog_close: u16 = 0x0922;
    pub const dialog_result: u16 = 0x0923;
    pub const toolbar_click: u16 = 0x0912;
    pub const key_event: u16 = 0x0600;
    pub const text_input: u16 = 0x0601;
    pub const pointer_event: u16 = 0x0602;
    pub const wheel_event: u16 = 0x0603;
    pub const focus_event: u16 = 0x0606;
    pub const window_request: u16 = 0x0607;
    pub const scroll_request: u16 = 0x0309;
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

pub const AtlasDefine = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    atlas_id: u32,
    generation: u32,
    width: u32,
    height: u32,
    page_count: u16,
};

pub const atlas_define_size: usize = 32;
pub const max_atlas_dimension: u32 = 4096;
pub const max_atlas_pages: u16 = 16;

pub const AtlasPageUpdate = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    atlas_id: u32,
    generation: u32,
    page_index: u16,
    page_count: u16,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    bytes: []const u8,
};

pub const atlas_page_update_header_size: usize = 28;
pub const max_atlas_page_bytes: usize = 1024 * 1024;

pub const AtlasGlyphAdd = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    atlas_id: u32,
    generation: u32,
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
    reserved_tail: [4]u8 = @splat(0),
};

pub const atlas_glyph_add_size: usize = 48;
pub const max_atlas_glyphs: usize = 256;

pub const AtlasInvalidateFlags = struct {
    pub const all: u8 = 1 << 0;
    pub const page: u8 = 1 << 1;
    pub const glyph: u8 = 1 << 2;
    pub const known: u8 = all | page | glyph;
};

pub const AtlasInvalidate = struct {
    schema: u16 = 1,
    flags: u8,
    reserved: u8 = 0,
    atlas_id: u32,
    generation: u32,
    target: u32 = 0,
};

pub const atlas_invalidate_size: usize = 16;

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

pub const FacePatchFlags = struct {
    pub const foreground: u8 = 1 << 0;
    pub const background: u8 = 1 << 1;
    pub const known: u8 = foreground | background;
};

/// Bounded FACE_PATCH v1: updates only foreground/background colors and
/// requires a stale-generation-safe replacement generation.
pub const FacePatch = struct {
    schema: u16 = 1,
    flags: u8,
    reserved: u8 = 0,
    face_id: u32,
    expected_generation: u32,
    new_generation: u32,
    foreground: [4]u8 = .{ 0, 0, 0, 0 },
    background: [4]u8 = .{ 0, 0, 0, 0 },
    reserved_tail: [4]u8 = .{ 0, 0, 0, 0 },
};

pub const face_patch_size: usize = 28;

fn validateFacePatch(patch: FacePatch) Error!void {
    if (patch.schema != 1 or patch.reserved != 0 or
        !std.mem.allEqual(u8, &patch.reserved_tail, 0) or
        patch.flags & ~@as(u8, FacePatchFlags.known) != 0 or
        patch.face_id == 0 or patch.expected_generation == 0 or
        patch.new_generation <= patch.expected_generation)
        return Error.InvalidMessage;
    if (patch.flags & FacePatchFlags.foreground != 0 and
        (patch.foreground[3] == 0 or !anyColorBytes(patch.foreground)))
        return Error.InvalidMessage;
    if (patch.flags & FacePatchFlags.background != 0 and
        (patch.background[3] == 0 or !anyColorBytes(patch.background)))
        return Error.InvalidMessage;
    if (patch.flags & FacePatchFlags.foreground == 0 and anyColorBytes(patch.foreground))
        return Error.InvalidMessage;
    if (patch.flags & FacePatchFlags.background == 0 and anyColorBytes(patch.background))
        return Error.InvalidMessage;
}

fn anyColorBytes(color: [4]u8) bool {
    return color[0] != 0 or color[1] != 0 or color[2] != 0;
}

fn optionalReferenceValid(id: u32, generation: u32, present: bool) bool {
    return if (present) (id != 0 and generation != 0) else (id == 0 and generation == 0);
}

fn validateFaceStyle(style: FaceStyle, color_present: bool) Error!void {
    if ((style == .color) != color_present) return Error.InvalidStyle;
}

pub fn validateFaceDefine(payload: FaceDefine) Error!void {
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

pub const max_fringe_bitmap_dimension: usize = 32;
pub const fringe_bitmap_data_size: usize =
    ((max_fringe_bitmap_dimension + 7) / 8) * max_fringe_bitmap_dimension;

pub const FringeBitmapDefine = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    bitmap_id: u32,
    generation: u32,
    width: u16,
    height: u16,
    bits: [fringe_bitmap_data_size]u8 = @splat(0),
};

pub const fringe_bitmap_define_size: usize = 144;

pub const FringeBitmapDelete = struct {
    bitmap_id: u32,
    generation: u32,
};

pub const fringe_bitmap_delete_size: usize = 8;

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
        .fringe_bitmap => {
            const payload = try decodeFringeBitmapDefine(entry.payload);
            if (payload.bitmap_id != entry.resource_id or payload.generation != entry.generation)
                return Error.InvalidResource;
        },
        .icon => return Error.Unsupported,
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

fn validateFontMetricsPatch(patch: FontMetricsPatch) Error!void {
    if (patch.schema != 1 or patch.flags != 0 or patch.reserved != 0 or
        !std.mem.allEqual(u8, &patch.reserved_tail, 0) or patch.font_id == 0 or
        patch.expected_generation == 0 or patch.new_generation <= patch.expected_generation)
        return Error.InvalidMessage;
    if (!fontMetricInRange(patch.ascent) or !fontMetricInRange(patch.descent) or
        !fontMetricInRange(patch.line_height) or !fontMetricInRange(patch.average_advance) or
        !fontMetricInRange(patch.max_advance) or patch.average_advance > patch.max_advance or
        patch.line_height < @as(u32, @intCast(patch.ascent + patch.descent)))
        return Error.InvalidMessage;
}

fn fontMetricInRange(value: i64) bool {
    return value >= 0 and value <= max_font_metric;
}

pub fn validateFontDefine(payload: FontDefine) Error!void {
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

fn validateAtlasDefine(payload: AtlasDefine) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        payload.atlas_id == 0 or payload.generation == 0 or
        payload.width == 0 or payload.width > max_atlas_dimension or
        payload.height == 0 or payload.height > max_atlas_dimension or
        payload.page_count == 0 or payload.page_count > max_atlas_pages)
        return Error.InvalidMessage;
}

pub fn encodeAtlasDefine(a: std.mem.Allocator, payload: AtlasDefine, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateAtlasDefine(payload);
    var b: [atlas_define_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    std.mem.writeInt(u32, b[4..8], payload.atlas_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.generation, .little);
    std.mem.writeInt(u32, b[12..16], payload.width, .little);
    std.mem.writeInt(u32, b[16..20], payload.height, .little);
    std.mem.writeInt(u16, b[20..22], payload.page_count, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeAtlasDefine(data: []const u8) Error!AtlasDefine {
    if (data.len != atlas_define_size) return Error.InvalidTable;
    const payload = AtlasDefine{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .atlas_id = std.mem.readInt(u32, data[4..8], .little),
        .generation = std.mem.readInt(u32, data[8..12], .little),
        .width = std.mem.readInt(u32, data[12..16], .little),
        .height = std.mem.readInt(u32, data[16..20], .little),
        .page_count = std.mem.readInt(u16, data[20..22], .little),
    };
    try validateAtlasDefine(payload);
    return payload;
}

pub fn validateAtlasPageUpdate(payload: AtlasPageUpdate) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        payload.atlas_id == 0 or payload.generation == 0 or
        payload.page_count == 0 or payload.page_count > max_atlas_pages or
        payload.page_index >= payload.page_count or
        payload.width == 0 or payload.height == 0) return Error.InvalidMessage;
    const required = @as(u64, payload.width) * @as(u64, payload.height) * 4;
    if (required > max_atlas_page_bytes or payload.bytes.len != required)
        return Error.InvalidMessage;
}

pub fn encodeAtlasPageUpdate(a: std.mem.Allocator, payload: AtlasPageUpdate, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateAtlasPageUpdate(payload);
    var b: [atlas_page_update_header_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    std.mem.writeInt(u32, b[4..8], payload.atlas_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.generation, .little);
    std.mem.writeInt(u16, b[12..14], payload.page_index, .little);
    std.mem.writeInt(u16, b[14..16], payload.page_count, .little);
    std.mem.writeInt(u16, b[16..18], payload.x, .little);
    std.mem.writeInt(u16, b[18..20], payload.y, .little);
    std.mem.writeInt(u16, b[20..22], payload.width, .little);
    std.mem.writeInt(u16, b[22..24], payload.height, .little);
    std.mem.writeInt(u32, b[24..28], @intCast(payload.bytes.len), .little);
    try out.appendSlice(a, &b);
    try out.appendSlice(a, payload.bytes);
}

pub fn decodeAtlasPageUpdate(a: std.mem.Allocator, data: []const u8) (Error || std.mem.Allocator.Error)!AtlasPageUpdate {
    if (data.len < atlas_page_update_header_size) return Error.InvalidTable;
    const byte_length = std.mem.readInt(u32, data[24..28], .little);
    if (byte_length == 0 or byte_length > max_atlas_page_bytes or
        data.len != atlas_page_update_header_size + byte_length) return Error.InvalidTable;
    var payload = AtlasPageUpdate{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .atlas_id = std.mem.readInt(u32, data[4..8], .little),
        .generation = std.mem.readInt(u32, data[8..12], .little),
        .page_index = std.mem.readInt(u16, data[12..14], .little),
        .page_count = std.mem.readInt(u16, data[14..16], .little),
        .x = std.mem.readInt(u16, data[16..18], .little),
        .y = std.mem.readInt(u16, data[18..20], .little),
        .width = std.mem.readInt(u16, data[20..22], .little),
        .height = std.mem.readInt(u16, data[22..24], .little),
        .bytes = data[atlas_page_update_header_size..],
    };
    try validateAtlasPageUpdate(payload);
    const owned = try a.dupe(u8, payload.bytes);
    errdefer a.free(owned);
    payload.bytes = owned;
    return payload;
}

pub fn freeAtlasPageUpdate(a: std.mem.Allocator, payload: *AtlasPageUpdate) void {
    if (payload.bytes.len != 0) a.free(payload.bytes);
    payload.bytes = &.{};
}

pub fn validateAtlasGlyphAdd(payload: AtlasGlyphAdd) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0) or
        payload.atlas_id == 0 or payload.generation == 0 or
        payload.glyph_id == 0 or payload.font_id == 0 or
        payload.size_px == 0 or payload.width == 0 or payload.height == 0 or
        payload.baseline > payload.height) return Error.InvalidMessage;
}

pub fn encodeAtlasGlyphAdd(a: std.mem.Allocator, payload: AtlasGlyphAdd, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateAtlasGlyphAdd(payload);
    var b: [atlas_glyph_add_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    std.mem.writeInt(u32, b[4..8], payload.atlas_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.generation, .little);
    std.mem.writeInt(u32, b[12..16], payload.glyph_id, .little);
    std.mem.writeInt(u32, b[16..20], payload.font_id, .little);
    std.mem.writeInt(u16, b[20..22], payload.size_px, .little);
    std.mem.writeInt(u64, b[24..32], payload.variation_hash, .little);
    std.mem.writeInt(u16, b[32..34], payload.x, .little);
    std.mem.writeInt(u16, b[34..36], payload.y, .little);
    std.mem.writeInt(u16, b[36..38], payload.width, .little);
    std.mem.writeInt(u16, b[38..40], payload.height, .little);
    std.mem.writeInt(u16, b[40..42], payload.baseline, .little);
    std.mem.writeInt(u16, b[42..44], payload.advance_x, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeAtlasGlyphAdd(data: []const u8) Error!AtlasGlyphAdd {
    if (data.len != atlas_glyph_add_size) return Error.InvalidTable;
    const payload = AtlasGlyphAdd{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .atlas_id = std.mem.readInt(u32, data[4..8], .little),
        .generation = std.mem.readInt(u32, data[8..12], .little),
        .glyph_id = std.mem.readInt(u32, data[12..16], .little),
        .font_id = std.mem.readInt(u32, data[16..20], .little),
        .size_px = std.mem.readInt(u16, data[20..22], .little),
        .variation_hash = std.mem.readInt(u64, data[24..32], .little),
        .x = std.mem.readInt(u16, data[32..34], .little),
        .y = std.mem.readInt(u16, data[34..36], .little),
        .width = std.mem.readInt(u16, data[36..38], .little),
        .height = std.mem.readInt(u16, data[38..40], .little),
        .baseline = std.mem.readInt(u16, data[40..42], .little),
        .advance_x = std.mem.readInt(u16, data[42..44], .little),
        .reserved_tail = data[44..48][0..4].*,
    };
    try validateAtlasGlyphAdd(payload);
    return payload;
}

pub fn validateAtlasInvalidate(payload: AtlasInvalidate) Error!void {
    if (payload.schema != 1 or payload.reserved != 0 or
        payload.flags == 0 or payload.flags & ~AtlasInvalidateFlags.known != 0 or
        @popCount(payload.flags) != 1 or
        payload.atlas_id == 0 or payload.generation == 0)
        return Error.InvalidMessage;
    if (payload.flags == AtlasInvalidateFlags.all) {
        if (payload.target != 0) return Error.InvalidMessage;
    } else {
        if (payload.flags & AtlasInvalidateFlags.all != 0 or
            (payload.flags == AtlasInvalidateFlags.glyph and payload.target == 0))
            return Error.InvalidMessage;
    }
}

pub fn encodeAtlasInvalidate(a: std.mem.Allocator, payload: AtlasInvalidate, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateAtlasInvalidate(payload);
    var b: [atlas_invalidate_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    b[2] = payload.flags;
    b[3] = payload.reserved;
    std.mem.writeInt(u32, b[4..8], payload.atlas_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.generation, .little);
    std.mem.writeInt(u32, b[12..16], payload.target, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeAtlasInvalidate(data: []const u8) Error!AtlasInvalidate {
    if (data.len != atlas_invalidate_size) return Error.InvalidTable;
    const payload = AtlasInvalidate{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .atlas_id = std.mem.readInt(u32, data[4..8], .little),
        .generation = std.mem.readInt(u32, data[8..12], .little),
        .target = std.mem.readInt(u32, data[12..16], .little),
    };
    try validateAtlasInvalidate(payload);
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

fn validateFringeBitmapDefine(payload: FringeBitmapDefine) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        payload.bitmap_id == 0 or payload.generation == 0 or
        payload.width == 0 or payload.height == 0 or
        payload.width > max_fringe_bitmap_dimension or
        payload.height > max_fringe_bitmap_dimension)
        return Error.InvalidMessage;

    const stride: usize = (max_fringe_bitmap_dimension + 7) / 8;
    const used_bytes: usize = (payload.width + 7) / 8;
    var y: usize = 0;
    while (y < payload.height) : (y += 1) {
        const row = payload.bits[y * stride ..][0..stride];
        for (row[used_bytes..]) |byte| {
            if (byte != 0) return Error.InvalidMessage;
        }
        const used_bits: u8 = @intCast(payload.width - (used_bytes -| 1) * 8);
        if (used_bits < 8 and blk: {
            break :blk (row[used_bytes - 1] & (@as(u8, 0xff) >> @intCast(used_bits))) != 0;
        })
            return Error.InvalidMessage;
    }
    for (payload.bits[payload.height * stride ..]) |byte| {
        if (byte != 0) return Error.InvalidMessage;
    }
}

pub fn encodeFringeBitmapDefine(a: std.mem.Allocator, payload: FringeBitmapDefine, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateFringeBitmapDefine(payload);
    var b: [fringe_bitmap_define_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    b[2] = payload.flags;
    b[3] = payload.reserved;
    std.mem.writeInt(u32, b[4..8], payload.bitmap_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.generation, .little);
    std.mem.writeInt(u16, b[12..14], payload.width, .little);
    std.mem.writeInt(u16, b[14..16], payload.height, .little);
    @memcpy(b[16..fringe_bitmap_define_size], &payload.bits);
    try out.appendSlice(a, &b);
}

pub fn decodeFringeBitmapDefine(data: []const u8) Error!FringeBitmapDefine {
    if (data.len != fringe_bitmap_define_size) return Error.InvalidTable;
    const payload: FringeBitmapDefine = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .bitmap_id = std.mem.readInt(u32, data[4..8], .little),
        .generation = std.mem.readInt(u32, data[8..12], .little),
        .width = std.mem.readInt(u16, data[12..14], .little),
        .height = std.mem.readInt(u16, data[14..16], .little),
        .bits = data[16..fringe_bitmap_define_size][0..fringe_bitmap_data_size].*,
    };
    try validateFringeBitmapDefine(payload);
    return payload;
}

pub fn encodeFringeBitmapDelete(a: std.mem.Allocator, payload: FringeBitmapDelete, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    if (payload.bitmap_id == 0 or payload.generation == 0) return Error.InvalidMessage;
    var b: [fringe_bitmap_delete_size]u8 = undefined;
    std.mem.writeInt(u32, b[0..4], payload.bitmap_id, .little);
    std.mem.writeInt(u32, b[4..8], payload.generation, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeFringeBitmapDelete(data: []const u8) Error!FringeBitmapDelete {
    if (data.len != fringe_bitmap_delete_size) return Error.InvalidTable;
    const payload: FringeBitmapDelete = .{
        .bitmap_id = std.mem.readInt(u32, data[0..4], .little),
        .generation = std.mem.readInt(u32, data[4..8], .little),
    };
    if (payload.bitmap_id == 0 or payload.generation == 0) return Error.InvalidMessage;
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

pub fn encodeFacePatch(a: std.mem.Allocator, patch: FacePatch, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateFacePatch(patch);
    var bytes: [face_patch_size]u8 = [_]u8{0} ** face_patch_size;
    std.mem.writeInt(u16, bytes[0..2], patch.schema, .little);
    bytes[2] = patch.flags;
    bytes[3] = patch.reserved;
    std.mem.writeInt(u32, bytes[4..8], patch.face_id, .little);
    std.mem.writeInt(u32, bytes[8..12], patch.expected_generation, .little);
    std.mem.writeInt(u32, bytes[12..16], patch.new_generation, .little);
    @memcpy(bytes[16..20], &patch.foreground);
    @memcpy(bytes[20..24], &patch.background);
    try out.appendSlice(a, &bytes);
}

pub fn decodeFacePatch(data: []const u8) Error!FacePatch {
    if (data.len != face_patch_size) return Error.InvalidTable;
    const patch = FacePatch{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .face_id = std.mem.readInt(u32, data[4..8], .little),
        .expected_generation = std.mem.readInt(u32, data[8..12], .little),
        .new_generation = std.mem.readInt(u32, data[12..16], .little),
        .foreground = data[16..20][0..4].*,
        .background = data[20..24][0..4].*,
        .reserved_tail = data[24..28][0..4].*,
    };
    try validateFacePatch(patch);
    return patch;
}

pub const FontMetricsPatch = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    font_id: u32,
    expected_generation: u32,
    new_generation: u32,
    ascent: i32,
    descent: i32,
    line_height: u32,
    average_advance: u32,
    max_advance: u32,
    reserved_tail: [4]u8 = .{ 0, 0, 0, 0 },
};

pub const font_metrics_patch_size: usize = 36;

pub const FontPatch = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    font_id: u32,
    expected_generation: u32,
    new_generation: u32,
    weight: u16,
    width_percent: u16,
    pixel_size: u32,
    point_size_tenths: u32,
    x_dpi: u32,
    y_dpi: u32,
    slant: FontSlant,
    spacing: FontSpacing,
    scalable: bool,
    fixed_pitch: bool,
    reserved_tail: [4]u8 = @splat(0),
};

pub const font_patch_size: usize = 44;

fn validateFontPatch(patch: FontPatch) Error!void {
    if (patch.schema != 1 or patch.flags != 0 or patch.reserved != 0 or
        !std.mem.allEqual(u8, &patch.reserved_tail, 0) or
        patch.font_id == 0 or patch.expected_generation == 0 or
        patch.new_generation <= patch.expected_generation or
        patch.weight < 1 or patch.weight > 1000 or
        patch.width_percent < 50 or patch.width_percent > 200 or
        patch.pixel_size > max_font_metric or
        patch.point_size_tenths > max_font_metric or
        patch.x_dpi > 4096 or patch.y_dpi > 4096 or
        (patch.x_dpi == 0) != (patch.y_dpi == 0) or
        (patch.fixed_pitch and patch.spacing == .proportional) or
        (patch.spacing == .mono and !patch.fixed_pitch))
        return Error.InvalidMessage;
}

pub fn encodeFontPatch(a: std.mem.Allocator, patch: FontPatch, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateFontPatch(patch);
    var b: [font_patch_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], patch.schema, .little);
    b[2] = patch.flags;
    b[3] = patch.reserved;
    std.mem.writeInt(u32, b[4..8], patch.font_id, .little);
    std.mem.writeInt(u32, b[8..12], patch.expected_generation, .little);
    std.mem.writeInt(u32, b[12..16], patch.new_generation, .little);
    std.mem.writeInt(u16, b[16..18], patch.weight, .little);
    std.mem.writeInt(u16, b[18..20], patch.width_percent, .little);
    std.mem.writeInt(u32, b[20..24], patch.pixel_size, .little);
    std.mem.writeInt(u32, b[24..28], patch.point_size_tenths, .little);
    std.mem.writeInt(u32, b[28..32], patch.x_dpi, .little);
    std.mem.writeInt(u32, b[32..36], patch.y_dpi, .little);
    b[36] = @intFromEnum(patch.slant);
    b[37] = @intFromEnum(patch.spacing);
    b[38] = @intFromBool(patch.scalable);
    b[39] = @intFromBool(patch.fixed_pitch);
    try out.appendSlice(a, &b);
}

pub fn decodeFontPatch(data: []const u8) Error!FontPatch {
    if (data.len != font_patch_size) return Error.InvalidTable;
    const patch: FontPatch = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .font_id = std.mem.readInt(u32, data[4..8], .little),
        .expected_generation = std.mem.readInt(u32, data[8..12], .little),
        .new_generation = std.mem.readInt(u32, data[12..16], .little),
        .weight = std.mem.readInt(u16, data[16..18], .little),
        .width_percent = std.mem.readInt(u16, data[18..20], .little),
        .pixel_size = std.mem.readInt(u32, data[20..24], .little),
        .point_size_tenths = std.mem.readInt(u32, data[24..28], .little),
        .x_dpi = std.mem.readInt(u32, data[28..32], .little),
        .y_dpi = std.mem.readInt(u32, data[32..36], .little),
        .slant = switch (data[36]) {
            0 => .unspecified,
            1 => .roman,
            2 => .italic,
            3 => .oblique,
            else => return Error.InvalidStyle,
        },
        .spacing = switch (data[37]) {
            0 => .unspecified,
            1 => .mono,
            2 => .proportional,
            else => return Error.InvalidStyle,
        },
        .scalable = data[38] == 1,
        .fixed_pitch = data[39] == 1,
        .reserved_tail = data[40..44][0..4].*,
    };
    if (data[38] > 1 or data[39] > 1) return Error.InvalidBoolean;
    try validateFontPatch(patch);
    return patch;
}

pub fn encodeFontMetricsPatch(a: std.mem.Allocator, patch: FontMetricsPatch, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateFontMetricsPatch(patch);
    var b: [font_metrics_patch_size]u8 = [_]u8{0} ** font_metrics_patch_size;
    std.mem.writeInt(u16, b[0..2], patch.schema, .little);
    std.mem.writeInt(u32, b[4..8], patch.font_id, .little);
    std.mem.writeInt(u32, b[8..12], patch.expected_generation, .little);
    std.mem.writeInt(u32, b[12..16], patch.new_generation, .little);
    std.mem.writeInt(i32, b[16..20], patch.ascent, .little);
    std.mem.writeInt(i32, b[20..24], patch.descent, .little);
    std.mem.writeInt(u32, b[24..28], patch.line_height, .little);
    std.mem.writeInt(u32, b[28..32], patch.average_advance, .little);
    std.mem.writeInt(u32, b[32..36], patch.max_advance, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeFontMetricsPatch(data: []const u8) Error!FontMetricsPatch {
    if (data.len != font_metrics_patch_size) return Error.InvalidTable;
    const patch: FontMetricsPatch = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .font_id = std.mem.readInt(u32, data[4..8], .little),
        .expected_generation = std.mem.readInt(u32, data[8..12], .little),
        .new_generation = std.mem.readInt(u32, data[12..16], .little),
        .ascent = @bitCast(std.mem.readInt(u32, data[16..20], .little)),
        .descent = @bitCast(std.mem.readInt(u32, data[20..24], .little)),
        .line_height = std.mem.readInt(u32, data[24..28], .little),
        .average_advance = std.mem.readInt(u32, data[28..32], .little),
        .max_advance = std.mem.readInt(u32, data[32..36], .little),
        .reserved_tail = data[32..36][0..4].*,
    };
    try validateFontMetricsPatch(patch);
    return patch;
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

pub const FramePatchFlags = struct {
    pub const visibility: u16 = 1 << 0;
    pub const focus: u16 = 1 << 1;
    pub const alpha: u16 = 1 << 2;
    pub const decorations: u16 = 1 << 3;
    pub const scale: u16 = 1 << 4;
    pub const known: u16 = visibility | focus | alpha | decorations | scale;
};

pub const FramePatch = struct {
    schema: u16 = 1,
    presence: u16,
    frame_generation: u32,
    visibility: FrameVisibilityState = .visible,
    focused: bool = false,
    decorated: bool = true,
    reserved_after_decorated: u8 = 0,
    active_opacity: u16 = 10000,
    inactive_opacity: u16 = 10000,
    background_opacity: u16 = 10000,
    scale: f32 = 1,
    dpi_x: f32 = 96,
    dpi_y: f32 = 96,
    reserved_tail: [8]u8 = @splat(0),
};

pub const frame_patch_size: usize = 40;

fn validateFramePatch(payload: FramePatch) Error!void {
    if (payload.schema != 1 or payload.presence == 0 or
        payload.presence & ~FramePatchFlags.known != 0 or
        payload.frame_generation == 0 or payload.reserved_after_decorated != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0))
        return Error.InvalidMessage;
    switch (payload.visibility) {
        .hidden, .visible, .iconified => {},
    }
    if (payload.active_opacity > max_opacity or
        payload.inactive_opacity > max_opacity or
        payload.background_opacity > max_opacity)
        return Error.InvalidMessage;
    if (!std.math.isFinite(payload.scale) or payload.scale <= 0 or
        payload.scale > max_frame_scale or
        !std.math.isFinite(payload.dpi_x) or payload.dpi_x <= 0 or
        payload.dpi_x > max_frame_dpi or
        !std.math.isFinite(payload.dpi_y) or payload.dpi_y <= 0 or
        payload.dpi_y > max_frame_dpi)
        return Error.InvalidMessage;
    if (payload.presence & FramePatchFlags.visibility != 0 and
        payload.visibility != .visible and payload.focused)
        return Error.InvalidMessage;
}

pub fn encodeFramePatch(a: std.mem.Allocator, payload: FramePatch, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateFramePatch(payload);
    var b: [frame_patch_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    std.mem.writeInt(u16, b[2..4], payload.presence, .little);
    std.mem.writeInt(u32, b[4..8], payload.frame_generation, .little);
    b[8] = @intFromEnum(payload.visibility);
    b[9] = @intFromBool(payload.focused);
    b[10] = @intFromBool(payload.decorated);
    std.mem.writeInt(u16, b[12..14], payload.active_opacity, .little);
    std.mem.writeInt(u16, b[14..16], payload.inactive_opacity, .little);
    std.mem.writeInt(u16, b[16..18], payload.background_opacity, .little);
    std.mem.writeInt(u32, b[20..24], @bitCast(payload.scale), .little);
    std.mem.writeInt(u32, b[24..28], @bitCast(payload.dpi_x), .little);
    std.mem.writeInt(u32, b[28..32], @bitCast(payload.dpi_y), .little);
    try out.appendSlice(a, &b);
}

pub fn decodeFramePatch(data: []const u8) Error!FramePatch {
    if (data.len != frame_patch_size) return Error.InvalidTable;
    const payload: FramePatch = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .presence = std.mem.readInt(u16, data[2..4], .little),
        .frame_generation = std.mem.readInt(u32, data[4..8], .little),
        .visibility = switch (data[8]) {
            0 => .hidden,
            1 => .visible,
            2 => .iconified,
            else => return Error.InvalidTable,
        },
        .focused = switch (data[9]) {
            0 => false,
            1 => true,
            else => return Error.InvalidBoolean,
        },
        .decorated = switch (data[10]) {
            0 => false,
            1 => true,
            else => return Error.InvalidBoolean,
        },
        .reserved_after_decorated = data[11],
        .active_opacity = std.mem.readInt(u16, data[12..14], .little),
        .inactive_opacity = std.mem.readInt(u16, data[14..16], .little),
        .background_opacity = std.mem.readInt(u16, data[16..18], .little),
        .scale = @bitCast(std.mem.readInt(u32, data[20..24], .little)),
        .dpi_x = @bitCast(std.mem.readInt(u32, data[24..28], .little)),
        .dpi_y = @bitCast(std.mem.readInt(u32, data[28..32], .little)),
        .reserved_tail = data[32..40][0..8].*,
    };
    try validateFramePatch(payload);
    return payload;
}

pub const FrameSnapshotFlags = struct {
    pub const visibility: u32 = 1 << 0;
    pub const focus: u32 = 1 << 1;
    pub const alpha: u32 = 1 << 2;
    pub const decorations: u32 = 1 << 3;
    pub const scale: u32 = 1 << 4;
    pub const geometry: u32 = 1 << 5;
    pub const fullscreen: u32 = 1 << 6;
    pub const maximize: u32 = 1 << 7;
    pub const all: u32 = visibility | focus | alpha | decorations |
        scale | geometry | fullscreen | maximize;
};

pub const FrameSnapshot = struct {
    schema: u16 = 1,
    reserved: u16 = 0,
    presence: u32 = FrameSnapshotFlags.all,
    frame_generation: u32,
    visibility: FrameVisibilityState = .visible,
    focused: bool = false,
    fullscreen: FrameFullscreenMode = .none,
    maximize_flags: u8 = FrameMaximizeFlags.both,
    decorated: bool = true,
    reserved_after_decorated: u8 = 0,
    active_opacity: u16 = 10000,
    inactive_opacity: u16 = 10000,
    background_opacity: u16 = 10000,
    scale: f32 = 1,
    dpi_x: f32 = 96,
    dpi_y: f32 = 96,
    outer: GeometryRect,
    content: GeometryRect,
    text: GeometryRect,
    window: GeometryRect,
    body: GeometryRect,
    reserved_tail: [12]u8 = @splat(0),
};

pub const frame_snapshot_size: usize = 128;

fn decodeFrameSnapshotVisibility(value: u8) Error!FrameVisibilityState {
    return switch (value) {
        0 => .hidden,
        1 => .visible,
        2 => .iconified,
        else => Error.InvalidTable,
    };
}

fn decodeFrameSnapshotFullscreen(value: u8) Error!FrameFullscreenMode {
    return switch (value) {
        0 => .none,
        1 => .fullboth,
        2 => .fullwidth,
        3 => .fullheight,
        4 => .maximized,
        else => Error.InvalidMessage,
    };
}

fn decodeFrameSnapshotBoolean(value: u8) Error!bool {
    return switch (value) {
        0 => false,
        1 => true,
        else => Error.InvalidBoolean,
    };
}

fn validateFrameSnapshot(payload: FrameSnapshot) Error!void {
    if (payload.schema != 1 or payload.reserved != 0 or
        payload.presence != FrameSnapshotFlags.all or
        payload.frame_generation == 0 or
        payload.reserved_after_decorated != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0))
        return Error.InvalidMessage;
    if (payload.focused and payload.visibility != .visible)
        return Error.InvalidMessage;
    if (payload.active_opacity > max_opacity or
        payload.inactive_opacity > max_opacity or
        payload.background_opacity > max_opacity)
        return Error.InvalidMessage;
    if (!std.math.isFinite(payload.scale) or payload.scale <= 0 or
        payload.scale > max_frame_scale or
        !std.math.isFinite(payload.dpi_x) or payload.dpi_x <= 0 or
        payload.dpi_x > max_frame_dpi or
        !std.math.isFinite(payload.dpi_y) or payload.dpi_y <= 0 or
        payload.dpi_y > max_frame_dpi)
        return Error.InvalidMessage;
    if (payload.maximize_flags & ~FrameMaximizeFlags.both != 0 or
        payload.maximize_flags == 0)
        return Error.InvalidMessage;
    inline for (.{ payload.outer, payload.content, payload.text, payload.window, payload.body }) |rect| {
        if (!validGeometryRect(rect)) return Error.InvalidMessage;
    }
    if (!containsGeometryRect(payload.outer, payload.content) or
        !containsGeometryRect(payload.content, payload.text) or
        !containsGeometryRect(payload.content, payload.window) or
        !containsGeometryRect(payload.window, payload.body))
        return Error.InvalidMessage;
}

pub fn encodeFrameSnapshot(a: std.mem.Allocator, payload: FrameSnapshot, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateFrameSnapshot(payload);
    var b: [frame_snapshot_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    std.mem.writeInt(u16, b[2..4], payload.reserved, .little);
    std.mem.writeInt(u32, b[4..8], payload.presence, .little);
    std.mem.writeInt(u32, b[8..12], payload.frame_generation, .little);
    b[12] = @intFromEnum(payload.visibility);
    b[13] = @intFromBool(payload.focused);
    b[14] = @intFromEnum(payload.fullscreen);
    b[15] = payload.maximize_flags;
    b[16] = @intFromBool(payload.decorated);
    b[17] = payload.reserved_after_decorated;
    std.mem.writeInt(u16, b[18..20], payload.active_opacity, .little);
    std.mem.writeInt(u16, b[20..22], payload.inactive_opacity, .little);
    std.mem.writeInt(u16, b[22..24], payload.background_opacity, .little);
    std.mem.writeInt(u32, b[24..28], @bitCast(payload.scale), .little);
    std.mem.writeInt(u32, b[28..32], @bitCast(payload.dpi_x), .little);
    std.mem.writeInt(u32, b[32..36], @bitCast(payload.dpi_y), .little);
    inline for (.{ payload.outer, payload.content, payload.text, payload.window, payload.body }, 0..) |rect, index| {
        const offset = 36 + index * 16;
        inline for (.{ rect.x, rect.y, rect.width, rect.height }, 0..) |value, part| {
            std.mem.writeInt(u32, b[offset + part * 4 ..][0..4], @bitCast(value), .little);
        }
    }
    try out.appendSlice(a, &b);
}

pub fn decodeFrameSnapshot(data: []const u8) Error!FrameSnapshot {
    if (data.len != frame_snapshot_size) return Error.InvalidTable;
    const payload: FrameSnapshot = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .reserved = std.mem.readInt(u16, data[2..4], .little),
        .presence = std.mem.readInt(u32, data[4..8], .little),
        .frame_generation = std.mem.readInt(u32, data[8..12], .little),
        .visibility = try decodeFrameSnapshotVisibility(data[12]),
        .focused = try decodeFrameSnapshotBoolean(data[13]),
        .fullscreen = try decodeFrameSnapshotFullscreen(data[14]),
        .maximize_flags = data[15],
        .decorated = try decodeFrameSnapshotBoolean(data[16]),
        .reserved_after_decorated = data[17],
        .active_opacity = std.mem.readInt(u16, data[18..20], .little),
        .inactive_opacity = std.mem.readInt(u16, data[20..22], .little),
        .background_opacity = std.mem.readInt(u16, data[22..24], .little),
        .scale = @bitCast(std.mem.readInt(u32, data[24..28], .little)),
        .dpi_x = @bitCast(std.mem.readInt(u32, data[28..32], .little)),
        .dpi_y = @bitCast(std.mem.readInt(u32, data[32..36], .little)),
        .outer = .{
            .x = @bitCast(std.mem.readInt(u32, data[36..40], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[40..44], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[44..48], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[48..52], .little)),
        },
        .content = .{
            .x = @bitCast(std.mem.readInt(u32, data[52..56], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[56..60], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[60..64], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[64..68], .little)),
        },
        .text = .{
            .x = @bitCast(std.mem.readInt(u32, data[68..72], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[72..76], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[76..80], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[80..84], .little)),
        },
        .window = .{
            .x = @bitCast(std.mem.readInt(u32, data[84..88], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[88..92], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[92..96], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[96..100], .little)),
        },
        .body = .{
            .x = @bitCast(std.mem.readInt(u32, data[100..104], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[104..108], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[108..112], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[112..116], .little)),
        },
        .reserved_tail = data[116..128][0..12].*,
    };
    try validateFrameSnapshot(payload);
    return payload;
}

pub const FrameTitlePayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    string_resource_id: u32,
    string_generation: u32,
    frame_generation: u32,
};

pub const FrameAlphaPayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    active_opacity: u16,
    inactive_opacity: u16,
    background_opacity: u16,
    reserved_middle: u16 = 0,
    frame_generation: u32,
    reserved_tail: u32 = 0,
};

pub const FrameDecorationsPayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    decorated: bool,
    reserved_after_decorated: [3]u8 = .{ 0, 0, 0 },
    frame_generation: u32,
};

pub const FrameScalePayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    scale: f32,
    dpi_x: f32,
    dpi_y: f32,
    frame_generation: u32,
    reserved_tail: u32 = 0,
};

pub const FrameFullscreenMode = enum(u8) {
    none = 0,
    fullboth = 1,
    fullwidth = 2,
    fullheight = 3,
    maximized = 4,
};

pub const FrameFullscreenPayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    mode: FrameFullscreenMode,
    reserved_after_mode: [3]u8 = .{ 0, 0, 0 },
    frame_generation: u32,
};

pub const FrameMonitorPayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    monitor_id: u32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    frame_generation: u32,
    reserved_tail: u32 = 0,
};

pub const FrameMaximizePayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    reserved_after_flags: [4]u8 = .{ 0, 0, 0, 0 },
    frame_generation: u32,
};

pub const GeometryRect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const FrameGeometryPayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    frame_generation: u32,
    outer: GeometryRect,
    content: GeometryRect,
    text: GeometryRect,
    window: GeometryRect,
    body: GeometryRect,
    reserved_tail: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
};

pub const FrameIconFlags = struct {
    pub const present: u8 = 1 << 0;
};

pub const FrameIconPayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    image_id: u32 = 0,
    image_generation: u32 = 0,
    hotspot_x: i32 = 0,
    hotspot_y: i32 = 0,
    frame_generation: u32,
    reserved_tail: u32 = 0,
};

pub const FrameSizeHintFlags = struct {
    pub const min_size: u8 = 1 << 0;
    pub const max_size: u8 = 1 << 1;
    pub const size_increment: u8 = 1 << 2;
    pub const aspect_ratio: u8 = 1 << 3;
    pub const known: u8 = min_size | max_size | size_increment | aspect_ratio;
};

pub const FrameSizeHintsPayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    frame_generation: u32,
    min_width: u32 = 0,
    min_height: u32 = 0,
    max_width: u32 = 0,
    max_height: u32 = 0,
    width_increment: u32 = 0,
    height_increment: u32 = 0,
    aspect_min_numerator: u32 = 0,
    aspect_min_denominator: u32 = 0,
    aspect_max_numerator: u32 = 0,
    aspect_max_denominator: u32 = 0,
};

pub const FrameZOrderOperation = enum(u8) {
    raise = 1,
    lower = 2,
    top = 3,
    bottom = 4,
    above = 5,
    below = 6,
};

pub const FrameZOrderPayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    operation: FrameZOrderOperation,
    reserved_after_operation: [3]u8 = .{ 0, 0, 0 },
    frame_generation: u32,
    relative_frame_id: u32 = 0,
    relative_frame_generation: u32 = 0,
    reserved_tail: u32 = 0,
};

pub const FrameParentFlags = struct {
    pub const present: u8 = 1 << 0;
    pub const modal: u8 = 1 << 1;
    pub const known: u8 = present | modal;
};

pub const FrameParentPayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    parent_frame_id: u32 = 0,
    parent_frame_generation: u32 = 0,
    child_frame_generation: u32,
    reserved_tail: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
};

pub const FrameFlushFlags = struct {
    pub const present_required: u8 = 1 << 0;
    pub const visible_only: u8 = 1 << 1;
    pub const known: u8 = present_required | visible_only;
};

pub const FrameFlushDamageKind = enum(u8) {
    none = 0,
    partial = 1,
    full = 2,
    state_only = 3,
    resource_only = 4,
};

pub const FrameFlushPayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    frame_generation: u32,
    redisplay_generation: u64,
    frame_sequence: u64,
    deadline_ns: u64 = 0,
    damage_kind: FrameFlushDamageKind,
    reserved_tail: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
};

pub const RenderHintMode = enum(u8) {
    auto = 0,
    vsync = 1,
    adaptive_vsync = 2,
    mailbox = 3,
    immediate = 4,
};

pub const RenderHintWorkload = enum(u8) {
    unspecified = 0,
    typing = 1,
    scroll = 2,
    animation = 3,
    resize = 4,
    idle = 5,
};

pub const RenderHintFlags = struct {
    pub const damage_only_allowed: u8 = 1 << 0;
    pub const deadline_present: u8 = 1 << 1;
    pub const refresh_interval_present: u8 = 1 << 2;
    pub const known: u8 = damage_only_allowed | deadline_present | refresh_interval_present;
};

pub const RenderHintPayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    preferred_mode: RenderHintMode,
    workload: RenderHintWorkload,
    reserved_after_workload: [2]u8 = .{ 0, 0 },
    frame_generation: u32,
    refresh_interval_ns: u64 = 0,
    deadline_ns: u64 = 0,
    reserved_tail: [4]u8 = .{ 0, 0, 0, 0 },
};

pub const PresentDamageKind = enum(u8) {
    none = 0,
    initial = 1,
    cursor = 2,
    text = 3,
    region = 4,
    viewport = 5,
    unchanged = 6,
};

pub const FrameDropReason = enum(u8) {
    invalid_window_size = 1,
    render_device_lost = 2,
    draw_failed = 3,
    superseded = 4,
    resource_missing = 5,
    limit_exceeded = 6,
};

pub const FramePresentedPayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    frame_generation: u32,
    redisplay_generation: u64,
    frame_sequence: u64,
    presented_at_ns: u64,
    frame_path_ns: u64,
    draw_command_count: u64,
    damage_kind: PresentDamageKind,
    reserved_tail: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
};

pub const FrameDroppedPayload = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    frame_generation: u32,
    redisplay_generation: u64,
    frame_sequence: u64,
    last_presented_sequence: u64,
    observed_at_ns: u64,
    reason: FrameDropReason,
    reserved_tail: [7]u8 = .{ 0, 0, 0, 0, 0, 0, 0 },
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

pub const ScrollRequestKind = enum(u8) {
    absolute = 1,
    relative = 2,
};

pub const ScrollAxis = enum(u8) {
    vertical = 1,
    horizontal = 2,
};

pub const ScrollRequest = struct {
    schema: u16 = 1,
    kind: ScrollRequestKind,
    axis: ScrollAxis,
    reserved: u8 = 0,
    window_id: u64,
    position: i64,
    delta: i32,
    frame_generation: u32,
    reserved_tail: [4]u8 = @splat(0),
};

pub const scroll_request_size: usize = 40;
pub const scroll_request_schema: u16 = 1;

pub fn validateScrollRequest(payload: ScrollRequest) Error!void {
    if (payload.schema != 1 or payload.reserved != 0 or payload.window_id == 0 or
        payload.frame_generation == 0 or !std.mem.allEqual(u8, &payload.reserved_tail, 0))
        return Error.InvalidMessage;
    switch (payload.kind) {
        .absolute => {
            if (payload.position < 0 or payload.delta != 0) return Error.InvalidMessage;
        },
        .relative => {
            if (payload.delta == 0 or payload.position != 0) return Error.InvalidMessage;
        },
    }
}

pub fn encodeScrollRequest(a: std.mem.Allocator, payload: ScrollRequest, out: *std.ArrayList(u8)) !void {
    try validateScrollRequest(payload);
    var bytes: [scroll_request_size]u8 = @splat(0);
    std.mem.writeInt(u16, bytes[0..2], payload.schema, .little);
    bytes[2] = @intFromEnum(payload.kind);
    bytes[3] = @intFromEnum(payload.axis);
    std.mem.writeInt(u64, bytes[8..16], payload.window_id, .little);
    std.mem.writeInt(i64, bytes[16..24], payload.position, .little);
    std.mem.writeInt(i32, bytes[24..28], payload.delta, .little);
    std.mem.writeInt(u32, bytes[28..32], payload.frame_generation, .little);
    try out.appendSlice(a, &bytes);
}

pub fn decodeScrollRequest(data: []const u8) Error!ScrollRequest {
    if (data.len != scroll_request_size) return Error.InvalidTable;
    if (std.mem.readInt(u16, data[0..2], .little) != scroll_request_schema)
        return Error.InvalidTable;
    if (data[4] != 0 or !std.mem.allEqual(u8, data[32..40], 0)) return Error.InvalidReserved;
    const payload: ScrollRequest = .{
        .kind = switch (data[2]) {
            1 => .absolute,
            2 => .relative,
            else => return Error.InvalidTable,
        },
        .axis = switch (data[3]) {
            1 => .vertical,
            2 => .horizontal,
            else => return Error.InvalidTable,
        },
        .window_id = std.mem.readInt(u64, data[8..16], .little),
        .position = std.mem.readInt(i64, data[16..24], .little),
        .delta = std.mem.readInt(i32, data[24..28], .little),
        .frame_generation = std.mem.readInt(u32, data[28..32], .little),
    };
    try validateScrollRequest(payload);
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

pub const MenuNodeKind = enum(u8) {
    separator = 1,
    command = 2,
    checkbox = 3,
    radio = 4,
    submenu = 5,
};

pub const MenuNodeFlags = struct {
    pub const enabled: u8 = 1 << 0;
    pub const visible: u8 = 1 << 1;
    pub const selected: u8 = 1 << 2;
    pub const known: u8 = enabled | visible | selected;
};

pub const MenuModelHeader = struct {
    frame_id: u32,
    frame_generation: u32,
    menu_id: u32,
    menu_generation: u32,
};

pub const MenuNode = struct {
    item_id: u32,
    parent_item_id: u32,
    kind: MenuNodeKind,
    flags: u8,
    depth: u8,
    label: [64]u8 = @splat(0),
    label_len: u8 = 0,
    help: [64]u8 = @splat(0),
    help_len: u8 = 0,
    key: [32]u8 = @splat(0),
    key_len: u8 = 0,
};

pub const MenuModelSnapshot = struct {
    header: MenuModelHeader,
    nodes: []const MenuNode,
};

pub const menu_model_header_size: usize = 32;
pub const menu_node_size: usize = 176;
pub const menu_model_schema: u16 = 1;
pub const max_menu_nodes: usize = 32;
pub const max_menu_depth: u8 = 4;

fn validateMenuText(bytes: []const u8) Error!void {
    if (bytes.len == 0) return Error.InvalidMessage;
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return Error.InvalidMessage;
    for (bytes) |byte| {
        if (byte < 0x20 or byte == 0x7f) return Error.InvalidMessage;
    }
    if (!std.unicode.utf8ValidateSlice(bytes)) return Error.InvalidUtf8;
}

fn validateMenuNode(node: MenuNode) Error!void {
    if (node.item_id == 0) return Error.InvalidMessage;
    if (node.flags & ~MenuNodeFlags.known != 0) return Error.InvalidReserved;
    if (node.depth > max_menu_depth) return Error.InvalidMessage;
    if (node.parent_item_id == 0 and node.depth != 0) return Error.InvalidMessage;
    if (node.label_len > node.label.len or
        node.help_len > node.help.len or
        node.key_len > node.key.len) return Error.InvalidMessage;
    if (!std.mem.allEqual(u8, node.label[node.label_len..], 0) or
        !std.mem.allEqual(u8, node.help[node.help_len..], 0) or
        !std.mem.allEqual(u8, node.key[node.key_len..], 0))
        return Error.InvalidReserved;
    if (node.label_len != 0) try validateMenuText(node.label[0..node.label_len]);
    if (node.help_len != 0) try validateMenuText(node.help[0..node.help_len]);
    if (node.key_len != 0) try validateMenuText(node.key[0..node.key_len]);
    const visible = node.flags & MenuNodeFlags.visible != 0;
    const enabled = node.flags & MenuNodeFlags.enabled != 0;
    const selected = node.flags & MenuNodeFlags.selected != 0;
    if (!visible and (enabled or selected)) return Error.InvalidMessage;
    if (selected and !(node.kind == .checkbox or node.kind == .radio))
        return Error.InvalidMessage;
    switch (node.kind) {
        .separator => {
            if (node.label_len != 0 or node.help_len != 0 or node.key_len != 0 or
                enabled or selected)
                return Error.InvalidMessage;
        },
        .submenu => {
            if (node.label_len == 0 or selected) return Error.InvalidMessage;
        },
        else => {
            if (node.label_len == 0) return Error.InvalidMessage;
        },
    }
}

pub fn validateMenuModelSnapshot(snapshot: MenuModelSnapshot) Error!void {
    const header = snapshot.header;
    if (header.frame_id == 0 or header.frame_generation == 0 or
        header.menu_id == 0 or header.menu_generation == 0)
        return Error.InvalidMessage;
    if (snapshot.nodes.len == 0 or snapshot.nodes.len > max_menu_nodes)
        return Error.InvalidMessage;

    for (snapshot.nodes, 0..) |node, index| {
        try validateMenuNode(node);
        for (snapshot.nodes[0..index]) |prior| {
            if (prior.item_id == node.item_id) return Error.InvalidTable;
        }
    }

    var top_level: usize = 0;
    for (snapshot.nodes) |node| {
        if (node.parent_item_id == 0) {
            top_level += 1;
            continue;
        }
        var parent: ?MenuNode = null;
        for (snapshot.nodes) |candidate| {
            if (candidate.item_id == node.parent_item_id) {
                parent = candidate;
                break;
            }
        }
        const parent_node = parent orelse return Error.InvalidMessage;
        if (parent_node.kind != .submenu or parent_node.depth + 1 != node.depth or
            (parent_node.flags & (MenuNodeFlags.visible | MenuNodeFlags.enabled)) !=
                (MenuNodeFlags.visible | MenuNodeFlags.enabled))
            return Error.InvalidMessage;
        var current = parent_node;
        var hops: usize = 0;
        while (current.parent_item_id != 0) {
            hops += 1;
            if (hops > max_menu_depth) return Error.InvalidMessage;
            parent = null;
            for (snapshot.nodes) |candidate| {
                if (candidate.item_id == current.parent_item_id) {
                    parent = candidate;
                    break;
                }
            }
            current = parent orelse return Error.InvalidMessage;
        }
    }
    if (top_level == 0) return Error.InvalidMessage;
}

pub fn encodeMenuModelSnapshot(
    a: std.mem.Allocator,
    snapshot: MenuModelSnapshot,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateMenuModelSnapshot(snapshot);
    var header: [menu_model_header_size]u8 = @splat(0);
    std.mem.writeInt(u16, header[0..2], menu_model_schema, .little);
    std.mem.writeInt(u32, header[4..8], snapshot.header.frame_id, .little);
    std.mem.writeInt(u32, header[8..12], snapshot.header.frame_generation, .little);
    std.mem.writeInt(u32, header[12..16], snapshot.header.menu_id, .little);
    std.mem.writeInt(u32, header[16..20], snapshot.header.menu_generation, .little);
    std.mem.writeInt(u32, header[20..24], @intCast(snapshot.nodes.len), .little);
    try out.appendSlice(a, &header);
    for (snapshot.nodes) |node| {
        var bytes: [menu_node_size]u8 = @splat(0);
        std.mem.writeInt(u32, bytes[0..4], node.item_id, .little);
        std.mem.writeInt(u32, bytes[4..8], node.parent_item_id, .little);
        bytes[8] = @intFromEnum(node.kind);
        bytes[9] = node.flags;
        bytes[10] = node.depth;
        bytes[11] = node.label_len;
        bytes[12] = node.help_len;
        bytes[13] = node.key_len;
        @memcpy(bytes[16..80], &node.label);
        @memcpy(bytes[80..144], &node.help);
        @memcpy(bytes[144..176], &node.key);
        try out.appendSlice(a, &bytes);
    }
}

pub fn decodeMenuModelSnapshot(
    a: std.mem.Allocator,
    data: []const u8,
) (Error || std.mem.Allocator.Error)!MenuModelSnapshot {
    if (data.len < menu_model_header_size) return Error.InvalidTable;
    var reader = Reader{ .data = data };
    if (try reader.readU16() != menu_model_schema) return Error.InvalidVersion;
    const flags = try reader.readByte();
    const reserved = try reader.readByte();
    const frame_id = try reader.readU32();
    const frame_generation = try reader.readU32();
    const menu_id = try reader.readU32();
    const menu_generation = try reader.readU32();
    const node_count = try reader.readU32();
    try reader.expectZeros(8);
    if (flags != 0 or reserved != 0) return Error.InvalidReserved;
    if (node_count == 0 or node_count > max_menu_nodes) return Error.InvalidTable;
    if (data.len != menu_model_header_size + @as(usize, node_count) * menu_node_size)
        return Error.InvalidTable;

    const nodes = try a.alloc(MenuNode, node_count);
    errdefer a.free(nodes);
    for (nodes) |*node| {
        node.* = .{
            .item_id = try reader.readU32(),
            .parent_item_id = try reader.readU32(),
            .kind = switch (try reader.readByte()) {
                1 => .separator,
                2 => .command,
                3 => .checkbox,
                4 => .radio,
                5 => .submenu,
                else => return Error.InvalidMessage,
            },
            .flags = try reader.readByte(),
            .depth = try reader.readByte(),
            .label_len = try reader.readByte(),
            .help_len = try reader.readByte(),
            .key_len = try reader.readByte(),
        };
        try reader.expectZeros(2);
        node.label = (try reader.bytes(64))[0..64].*;
        node.help = (try reader.bytes(64))[0..64].*;
        node.key = (try reader.bytes(32))[0..32].*;
    }
    const snapshot: MenuModelSnapshot = .{
        .header = .{
            .frame_id = frame_id,
            .frame_generation = frame_generation,
            .menu_id = menu_id,
            .menu_generation = menu_generation,
        },
        .nodes = nodes,
    };
    try validateMenuModelSnapshot(snapshot);
    return snapshot;
}

pub fn freeMenuModelSnapshot(a: std.mem.Allocator, snapshot: *MenuModelSnapshot) void {
    a.free(snapshot.nodes);
    snapshot.nodes = &.{};
}

pub const MenuPatchOperationKind = enum(u8) {
    upsert = 1,
    delete = 2,
};

pub const MenuPatchHeader = struct {
    frame_id: u32,
    frame_generation: u32,
    menu_id: u32,
    expected_generation: u32,
    new_generation: u32,
};

pub const MenuPatchOperation = struct {
    operation: MenuPatchOperationKind,
    node: MenuNode,
    reserved_tail: [4]u8 = @splat(0),
};

pub const menu_patch_header_size: usize = 32;
pub const menu_patch_operation_size: usize = 184;
pub const menu_patch_schema: u16 = 1;
pub const max_menu_patch_operations: usize = 32;

fn validateMenuPatchHeader(header: MenuPatchHeader, operation_count: u32) Error!void {
    if (header.frame_id == 0 or header.frame_generation == 0 or
        header.menu_id == 0 or header.expected_generation == 0 or
        header.new_generation <= header.expected_generation or
        operation_count == 0 or operation_count > max_menu_patch_operations)
        return Error.InvalidMessage;
}

fn validateMenuPatchOperation(operation: MenuPatchOperation) Error!void {
    if (!std.mem.allEqual(u8, &operation.reserved_tail, 0)) return Error.InvalidReserved;
    if (operation.node.item_id == 0) return Error.InvalidMessage;
    if (operation.operation == .delete) {
        if (operation.node.parent_item_id != 0 or
            operation.node.kind != .command or operation.node.flags != 0 or
            operation.node.depth != 0 or operation.node.label_len != 0 or
            operation.node.help_len != 0 or operation.node.key_len != 0)
            return Error.InvalidMessage;
        if (!std.mem.allEqual(u8, &operation.node.label, 0) or
            !std.mem.allEqual(u8, &operation.node.help, 0) or
            !std.mem.allEqual(u8, &operation.node.key, 0))
            return Error.InvalidReserved;
        return;
    }
    try validateMenuNode(operation.node);
}

pub fn encodeMenuPatch(
    a: std.mem.Allocator,
    header: MenuPatchHeader,
    operations: []const MenuPatchOperation,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateMenuPatchHeader(header, @intCast(operations.len));
    var header_bytes: [menu_patch_header_size]u8 = @splat(0);
    std.mem.writeInt(u16, header_bytes[0..2], menu_patch_schema, .little);
    std.mem.writeInt(u32, header_bytes[4..8], header.frame_id, .little);
    std.mem.writeInt(u32, header_bytes[8..12], header.frame_generation, .little);
    std.mem.writeInt(u32, header_bytes[12..16], header.menu_id, .little);
    std.mem.writeInt(u32, header_bytes[16..20], header.expected_generation, .little);
    std.mem.writeInt(u32, header_bytes[20..24], header.new_generation, .little);
    std.mem.writeInt(u32, header_bytes[24..28], @intCast(operations.len), .little);
    try out.appendSlice(a, &header_bytes);
    for (operations) |operation| {
        try validateMenuPatchOperation(operation);
        var bytes: [menu_patch_operation_size]u8 = @splat(0);
        bytes[0] = @intFromEnum(operation.operation);
        std.mem.writeInt(u32, bytes[4..8], operation.node.item_id, .little);
        std.mem.writeInt(u32, bytes[8..12], operation.node.parent_item_id, .little);
        bytes[12] = @intFromEnum(operation.node.kind);
        bytes[13] = operation.node.flags;
        bytes[14] = operation.node.depth;
        bytes[15] = operation.node.label_len;
        bytes[16] = operation.node.help_len;
        bytes[17] = operation.node.key_len;
        @memcpy(bytes[20..84], &operation.node.label);
        @memcpy(bytes[84..148], &operation.node.help);
        @memcpy(bytes[148..180], &operation.node.key);
        try out.appendSlice(a, &bytes);
    }
}

pub fn decodeMenuPatch(
    a: std.mem.Allocator,
    data: []const u8,
) (Error || std.mem.Allocator.Error)!struct { header: MenuPatchHeader, operations: []MenuPatchOperation } {
    if (data.len < menu_patch_header_size) return Error.InvalidTable;
    var reader = Reader{ .data = data };
    if (try reader.readU16() != menu_patch_schema) return Error.InvalidVersion;
    const flags = try reader.readByte();
    const reserved = try reader.readByte();
    const header: MenuPatchHeader = .{
        .frame_id = try reader.readU32(),
        .frame_generation = try reader.readU32(),
        .menu_id = try reader.readU32(),
        .expected_generation = try reader.readU32(),
        .new_generation = try reader.readU32(),
    };
    const operation_count = try reader.readU32();
    try reader.expectZeros(4);
    if (flags != 0 or reserved != 0) return Error.InvalidReserved;
    try validateMenuPatchHeader(header, operation_count);
    if (data.len != menu_patch_header_size + @as(usize, operation_count) * menu_patch_operation_size)
        return Error.InvalidTable;

    const operations = try a.alloc(MenuPatchOperation, operation_count);
    errdefer a.free(operations);
    for (operations) |*operation| {
        const operation_kind: MenuPatchOperationKind = switch (try reader.readByte()) {
            1 => .upsert,
            2 => .delete,
            else => return Error.InvalidMessage,
        };
        try reader.expectZeros(3);
        operation.* = .{
            .operation = operation_kind,
            .node = .{
                .item_id = try reader.readU32(),
                .parent_item_id = try reader.readU32(),
                .kind = switch (try reader.readByte()) {
                    1 => .separator,
                    2 => .command,
                    3 => .checkbox,
                    4 => .radio,
                    5 => .submenu,
                    else => return Error.InvalidMessage,
                },
                .flags = try reader.readByte(),
                .depth = try reader.readByte(),
                .label_len = try reader.readByte(),
                .help_len = try reader.readByte(),
                .key_len = try reader.readByte(),
            },
        };
        try reader.expectZeros(2);
        operation.node.label = (try reader.bytes(64))[0..64].*;
        operation.node.help = (try reader.bytes(64))[0..64].*;
        operation.node.key = (try reader.bytes(32))[0..32].*;
        operation.reserved_tail = (try reader.bytes(4))[0..4].*;
        try validateMenuPatchOperation(operation.*);
    }
    return .{ .header = header, .operations = operations };
}

pub fn freeMenuPatchOperations(a: std.mem.Allocator, operations: []MenuPatchOperation) void {
    a.free(operations);
}

pub const MenuCloseReason = enum(u8) {
    selection = 1,
    dismissal = 2,
    replacement = 3,
};

pub const MenuOpen = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    menu_id: u32,
    menu_generation: u32,
    item_id: u32,
    window_id: u64,
    frame_generation: u32,
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    reserved_tail: [4]u8 = @splat(0),
};

pub const menu_open_size: usize = 48;

pub const MenuClose = struct {
    schema: u16 = 1,
    reason: MenuCloseReason,
    reserved: u8 = 0,
    menu_id: u32,
    menu_generation: u32,
    item_id: u32,
    frame_generation: u32,
};

pub const menu_close_size: usize = 24;

fn validateMenuOpen(payload: MenuOpen) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0) or
        payload.menu_id == 0 or payload.menu_generation == 0 or
        payload.item_id == 0 or payload.window_id == 0 or
        payload.frame_generation == 0 or payload.x < 0 or payload.y < 0 or
        payload.width == 0 or payload.height == 0 or
        payload.width > max_window_size or payload.height > max_window_size)
        return Error.InvalidMessage;
}

pub fn encodeMenuOpen(a: std.mem.Allocator, payload: MenuOpen, out: *std.ArrayList(u8)) !void {
    try validateMenuOpen(payload);
    var b: [menu_open_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    b[2] = payload.flags;
    b[3] = payload.reserved;
    std.mem.writeInt(u32, b[4..8], payload.menu_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.menu_generation, .little);
    std.mem.writeInt(u32, b[12..16], payload.item_id, .little);
    std.mem.writeInt(u64, b[16..24], payload.window_id, .little);
    std.mem.writeInt(u32, b[24..28], payload.frame_generation, .little);
    std.mem.writeInt(i32, b[28..32], payload.x, .little);
    std.mem.writeInt(i32, b[32..36], payload.y, .little);
    std.mem.writeInt(u32, b[36..40], payload.width, .little);
    std.mem.writeInt(u32, b[40..44], payload.height, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeMenuOpen(data: []const u8) Error!MenuOpen {
    if (data.len != menu_open_size) return Error.InvalidTable;
    const payload: MenuOpen = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .menu_id = std.mem.readInt(u32, data[4..8], .little),
        .menu_generation = std.mem.readInt(u32, data[8..12], .little),
        .item_id = std.mem.readInt(u32, data[12..16], .little),
        .window_id = std.mem.readInt(u64, data[16..24], .little),
        .frame_generation = std.mem.readInt(u32, data[24..28], .little),
        .x = @bitCast(std.mem.readInt(u32, data[28..32], .little)),
        .y = @bitCast(std.mem.readInt(u32, data[32..36], .little)),
        .width = std.mem.readInt(u32, data[36..40], .little),
        .height = std.mem.readInt(u32, data[40..44], .little),
        .reserved_tail = data[44..48][0..4].*,
    };
    try validateMenuOpen(payload);
    return payload;
}

pub fn encodeMenuClose(a: std.mem.Allocator, payload: MenuClose, out: *std.ArrayList(u8)) !void {
    if (payload.schema != 1 or payload.reserved != 0 or
        payload.menu_id == 0 or payload.menu_generation == 0 or
        payload.item_id == 0 or payload.frame_generation == 0)
        return Error.InvalidMessage;
    var b: [menu_close_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    b[2] = @intFromEnum(payload.reason);
    b[3] = payload.reserved;
    std.mem.writeInt(u32, b[4..8], payload.menu_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.menu_generation, .little);
    std.mem.writeInt(u32, b[12..16], payload.item_id, .little);
    std.mem.writeInt(u32, b[16..20], payload.frame_generation, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeMenuClose(data: []const u8) Error!MenuClose {
    if (data.len != menu_close_size) return Error.InvalidTable;
    const payload: MenuClose = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .reason = switch (data[2]) {
            1 => .selection,
            2 => .dismissal,
            3 => .replacement,
            else => return Error.InvalidMessage,
        },
        .reserved = data[3],
        .menu_id = std.mem.readInt(u32, data[4..8], .little),
        .menu_generation = std.mem.readInt(u32, data[8..12], .little),
        .item_id = std.mem.readInt(u32, data[12..16], .little),
        .frame_generation = std.mem.readInt(u32, data[16..20], .little),
    };
    if (payload.schema != 1 or payload.reserved != 0 or
        payload.menu_id == 0 or payload.menu_generation == 0 or
        payload.item_id == 0 or payload.frame_generation == 0)
        return Error.InvalidMessage;
    return payload;
}

pub const MenuCancelReason = enum(u8) {
    user = 1,
    escape = 2,
    focus_lost = 3,
};

pub const MenuResult = struct {
    schema: u16 = 1,
    flags: u8 = 0,
    reserved: u8 = 0,
    menu_id: u32,
    menu_generation: u32,
    item_id: u32,
    window_id: u64,
    frame_generation: u32,
    reserved_tail: [4]u8 = @splat(0),
};

pub const menu_result_size: usize = 32;

pub const MenuCancel = struct {
    schema: u16 = 1,
    reason: MenuCancelReason,
    reserved: u8 = 0,
    menu_id: u32,
    menu_generation: u32,
    window_id: u64,
    frame_generation: u32,
    reserved_tail: [4]u8 = @splat(0),
};

pub const menu_cancel_size: usize = 28;

pub fn validateMenuResult(payload: MenuResult) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0) or
        payload.menu_id == 0 or payload.menu_generation == 0 or
        payload.item_id == 0 or payload.window_id == 0 or
        payload.frame_generation == 0)
        return Error.InvalidMessage;
}

pub fn encodeMenuResult(a: std.mem.Allocator, payload: MenuResult, out: *std.ArrayList(u8)) !void {
    try validateMenuResult(payload);
    var b: [menu_result_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    b[2] = payload.flags;
    b[3] = payload.reserved;
    std.mem.writeInt(u32, b[4..8], payload.menu_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.menu_generation, .little);
    std.mem.writeInt(u32, b[12..16], payload.item_id, .little);
    std.mem.writeInt(u64, b[16..24], payload.window_id, .little);
    std.mem.writeInt(u32, b[24..28], payload.frame_generation, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeMenuResult(data: []const u8) Error!MenuResult {
    if (data.len != menu_result_size) return Error.InvalidTable;
    const payload: MenuResult = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .menu_id = std.mem.readInt(u32, data[4..8], .little),
        .menu_generation = std.mem.readInt(u32, data[8..12], .little),
        .item_id = std.mem.readInt(u32, data[12..16], .little),
        .window_id = std.mem.readInt(u64, data[16..24], .little),
        .frame_generation = std.mem.readInt(u32, data[24..28], .little),
        .reserved_tail = data[28..menu_result_size][0..4].*,
    };
    try validateMenuResult(payload);
    return payload;
}

pub fn validateMenuCancel(payload: MenuCancel) Error!void {
    if (payload.schema != 1 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0) or
        payload.menu_id == 0 or payload.menu_generation == 0 or
        payload.window_id == 0 or payload.frame_generation == 0)
        return Error.InvalidMessage;
    switch (payload.reason) {
        .user, .escape, .focus_lost => {},
    }
}

pub fn encodeMenuCancel(a: std.mem.Allocator, payload: MenuCancel, out: *std.ArrayList(u8)) !void {
    try validateMenuCancel(payload);
    var b: [menu_cancel_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    b[2] = @intFromEnum(payload.reason);
    b[3] = payload.reserved;
    std.mem.writeInt(u32, b[4..8], payload.menu_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.menu_generation, .little);
    std.mem.writeInt(u64, b[12..20], payload.window_id, .little);
    std.mem.writeInt(u32, b[20..24], payload.frame_generation, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeMenuCancel(data: []const u8) Error!MenuCancel {
    if (data.len != menu_cancel_size) return Error.InvalidTable;
    const payload: MenuCancel = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .reason = switch (data[2]) {
            1 => .user,
            2 => .escape,
            3 => .focus_lost,
            else => return Error.InvalidMessage,
        },
        .reserved = data[3],
        .menu_id = std.mem.readInt(u32, data[4..8], .little),
        .menu_generation = std.mem.readInt(u32, data[8..12], .little),
        .window_id = std.mem.readInt(u64, data[12..20], .little),
        .frame_generation = std.mem.readInt(u32, data[20..24], .little),
        .reserved_tail = data[24..menu_cancel_size][0..4].*,
    };
    try validateMenuCancel(payload);
    return payload;
}

pub const MenuHoverPhase = enum(u8) {
    enter = 1,
    move = 2,
    leave = 3,
};

pub const MenuHover = struct {
    schema: u16 = 1,
    phase: MenuHoverPhase,
    reserved: u8 = 0,
    menu_id: u32,
    menu_generation: u32,
    item_id: u32 = 0,
    window_id: u64,
    frame_generation: u32,
    x: i32 = 0,
    y: i32 = 0,
    reserved_tail: [4]u8 = @splat(0),
};

pub const menu_hover_size: usize = 40;

pub fn validateMenuHover(payload: MenuHover) Error!void {
    if (payload.schema != 1 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0) or
        payload.menu_id == 0 or payload.menu_generation == 0 or
        payload.window_id == 0 or payload.frame_generation == 0)
        return Error.InvalidMessage;
    switch (payload.phase) {
        .enter, .move => {
            if (payload.item_id == 0 or payload.x < 0 or payload.y < 0)
                return Error.InvalidMenuHover;
        },
        .leave => {
            if (payload.item_id != 0 or payload.x != 0 or payload.y != 0)
                return Error.InvalidMenuHover;
        },
    }
}

pub fn encodeMenuHover(a: std.mem.Allocator, payload: MenuHover, out: *std.ArrayList(u8)) !void {
    try validateMenuHover(payload);
    var b: [menu_hover_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    b[2] = @intFromEnum(payload.phase);
    b[3] = payload.reserved;
    std.mem.writeInt(u32, b[4..8], payload.menu_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.menu_generation, .little);
    std.mem.writeInt(u32, b[12..16], payload.item_id, .little);
    std.mem.writeInt(u64, b[16..24], payload.window_id, .little);
    std.mem.writeInt(u32, b[24..28], payload.frame_generation, .little);
    std.mem.writeInt(i32, b[28..32], payload.x, .little);
    std.mem.writeInt(i32, b[32..36], payload.y, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeMenuHover(data: []const u8) Error!MenuHover {
    if (data.len != menu_hover_size) return Error.InvalidTable;
    const payload: MenuHover = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .phase = switch (data[2]) {
            1 => .enter,
            2 => .move,
            3 => .leave,
            else => return Error.InvalidMessage,
        },
        .reserved = data[3],
        .menu_id = std.mem.readInt(u32, data[4..8], .little),
        .menu_generation = std.mem.readInt(u32, data[8..12], .little),
        .item_id = std.mem.readInt(u32, data[12..16], .little),
        .window_id = std.mem.readInt(u64, data[16..24], .little),
        .frame_generation = std.mem.readInt(u32, data[24..28], .little),
        .x = @bitCast(std.mem.readInt(u32, data[28..32], .little)),
        .y = @bitCast(std.mem.readInt(u32, data[32..36], .little)),
        .reserved_tail = data[36..menu_hover_size][0..4].*,
    };
    try validateMenuHover(payload);
    return payload;
}

test "menu patch codecs enforce ordered generation and operations" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    const header: MenuPatchHeader = .{
        .frame_id = 7,
        .frame_generation = 1,
        .menu_id = 3,
        .expected_generation = 4,
        .new_generation = 5,
    };
    var operations = [_]MenuPatchOperation{
        .{ .operation = .upsert, .node = .{
            .item_id = 21,
            .parent_item_id = 20,
            .kind = .command,
            .flags = MenuNodeFlags.enabled | MenuNodeFlags.visible,
            .depth = 1,
            .label_len = 8,
        } },
        .{ .operation = .delete, .node = .{
            .item_id = 22,
            .parent_item_id = 0,
            .kind = .command,
            .flags = 0,
            .depth = 0,
        } },
    };
    @memcpy(operations[0].node.label[0..8], "NewFrame");
    try encodeMenuPatch(a, header, &operations, &bytes);
    try std.testing.expectEqual(menu_patch_header_size + 2 * menu_patch_operation_size, bytes.items.len);
    const decoded = try decodeMenuPatch(a, bytes.items);
    defer freeMenuPatchOperations(a, decoded.operations);
    try std.testing.expectEqual(header, decoded.header);
    try std.testing.expectEqual(operations.len, decoded.operations.len);
    try std.testing.expectEqual(MenuPatchOperationKind.upsert, decoded.operations[0].operation);
    try std.testing.expectEqualStrings("NewFrame", decoded.operations[0].node.label[0..8]);
    try std.testing.expectEqual(MenuPatchOperationKind.delete, decoded.operations[1].operation);

    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeMenuPatch(a, bytes.items));
    bytes.items[3] = 0;
    try std.testing.expectError(Error.InvalidTable, decodeMenuPatch(a, bytes.items[0 .. bytes.items.len - 1]));
    try std.testing.expectError(Error.InvalidMessage, encodeMenuPatch(a, .{
        .frame_id = 7,
        .frame_generation = 1,
        .menu_id = 3,
        .expected_generation = 5,
        .new_generation = 5,
    }, &operations, &bytes));

    // Reject malformed node payloads at the raw trust boundary, not only
    // through the validating encoder.
    bytes.items[menu_patch_header_size + 13] = 0x80;
    try std.testing.expectError(Error.InvalidReserved, decodeMenuPatch(a, bytes.items));
    bytes.items[menu_patch_header_size + 13] = MenuNodeFlags.enabled | MenuNodeFlags.visible;
    bytes.items[menu_patch_header_size + 20] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuPatch(a, bytes.items));
    bytes.items[menu_patch_header_size + 20] = 'N';
    bytes.items[menu_patch_header_size + menu_patch_operation_size] = 9;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuPatch(a, bytes.items));
    bytes.items[menu_patch_header_size + menu_patch_operation_size] = @intFromEnum(MenuPatchOperationKind.delete);
    std.mem.writeInt(u32, bytes.items[menu_patch_header_size + menu_patch_operation_size + 8 ..][0..4], 20, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeMenuPatch(a, bytes.items));
    std.mem.writeInt(u32, bytes.items[menu_patch_header_size + menu_patch_operation_size + 8 ..][0..4], 0, .little);
    bytes.items[menu_patch_header_size + menu_patch_operation_size + 20] = 'x';
    try std.testing.expectError(Error.InvalidReserved, decodeMenuPatch(a, bytes.items));
}

pub fn toolbarModelFixture(items: []ToolbarItem) ToolbarModel {
    items[0] = .{ .item_id = 40, .kind = .button, .label_len = 4 };
    items[1] = .{ .item_id = 41, .kind = .toggle, .flags = ToolbarItemFlags.enabled | ToolbarItemFlags.visible | ToolbarItemFlags.selected, .label_len = 9 };
    items[2] = .{ .item_id = 42, .kind = .separator, .flags = ToolbarItemFlags.visible };
    items[3] = .{ .item_id = 43, .kind = .space, .flags = ToolbarItemFlags.visible };
    @memcpy(items[0].label[0..4], "Save");
    @memcpy(items[1].label[0..9], "Overwrite");
    return .{
        .header = .{ .frame_id = 7, .frame_generation = 1, .toolbar_id = 9, .toolbar_generation = 2 },
        .items = items[0..4],
    };
}

test "toolbar model codec enforces bounded UTF-8 items" {
    const a = std.testing.allocator;
    var fixture_items: [4]ToolbarItem = undefined;
    const model = toolbarModelFixture(&fixture_items);
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeToolbarModel(a, model, &bytes);
    try std.testing.expectEqual(toolbar_model_header_size + 4 * toolbar_item_size, bytes.items.len);
    var decoded = try decodeToolbarModel(a, bytes.items);
    defer freeToolbarModel(a, &decoded);
    try std.testing.expectEqual(model.header, decoded.header);
    try std.testing.expectEqual(model.items.len, decoded.items.len);
    try std.testing.expectEqualStrings("Save", decoded.items[0].label[0..4]);
    try std.testing.expectEqualStrings("Overwrite", decoded.items[1].label[0..9]);

    bytes.items[toolbar_model_header_size + toolbar_item_size + 12] = 9;
    try std.testing.expectError(Error.InvalidMessage, decodeToolbarModel(a, bytes.items));
    bytes.items[toolbar_model_header_size + toolbar_item_size + 12] = @intFromEnum(ToolbarItemKind.toggle);
    std.mem.writeInt(u32, bytes.items[toolbar_model_header_size + toolbar_item_size ..][0..4], 40, .little);
    try std.testing.expectError(Error.InvalidTable, decodeToolbarModel(a, bytes.items));
    std.mem.writeInt(u32, bytes.items[toolbar_model_header_size + toolbar_item_size ..][0..4], 41, .little);
    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeToolbarModel(a, bytes.items));
    bytes.items[3] = 0;
    try std.testing.expectError(Error.InvalidTable, decodeToolbarModel(a, bytes.items[0 .. bytes.items.len - 1]));
}

test "toolbar click codec validates phase identity and pointer facts" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    const click: ToolbarClick = .{
        .phase = .release,
        .toolbar_id = 9,
        .toolbar_generation = 2,
        .item_id = 40,
        .window_id = 10,
        .frame_generation = 1,
        .click_count = 2,
        .button = 1,
        .modifiers = 1,
        .x = 12,
        .y = 24,
    };
    try encodeToolbarClick(a, click, &bytes);
    try std.testing.expectEqual(toolbar_click_size, bytes.items.len);
    try std.testing.expectEqual(click, try decodeToolbarClick(bytes.items));

    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidToolbarClick, decodeToolbarClick(bytes.items));
    bytes.items[3] = 0;
    bytes.items[2] = 3;
    try std.testing.expectError(Error.InvalidMessage, decodeToolbarClick(bytes.items));
    bytes.items[2] = @intFromEnum(ToolbarClickPhase.release);
    try std.testing.expectError(Error.InvalidTable, decodeToolbarClick(bytes.items[0 .. bytes.items.len - 1]));
}

test "toolbar patch codecs enforce ordered generation and operations" {
    const a = std.testing.allocator;
    var fixture_items: [4]ToolbarItem = undefined;
    const base_model = toolbarModelFixture(&fixture_items);
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    const header: ToolbarPatchHeader = .{
        .frame_id = base_model.header.frame_id,
        .frame_generation = base_model.header.frame_generation,
        .toolbar_id = base_model.header.toolbar_id,
        .expected_generation = base_model.header.toolbar_generation,
        .new_generation = base_model.header.toolbar_generation + 1,
    };
    var item = ToolbarItem{ .item_id = 44, .kind = .button, .flags = ToolbarItemFlags.enabled | ToolbarItemFlags.visible, .label_len = 4 };
    @memcpy(item.label[0..4], "Undo");
    const operations = [_]ToolbarPatchOperation{
        .{ .operation = .upsert, .item = item },
        .{ .operation = .delete, .item = .{ .item_id = 43, .kind = .button, .flags = 0 } },
    };
    try encodeToolbarPatch(a, header, &operations, &bytes);
    try std.testing.expectEqual(toolbar_patch_header_size + 2 * toolbar_patch_operation_size, bytes.items.len);
    const decoded = try decodeToolbarPatch(a, bytes.items);
    defer freeToolbarPatchOperations(a, decoded.operations);
    try std.testing.expectEqual(header, decoded.header);
    try std.testing.expectEqual(operations.len, decoded.operations.len);
    try std.testing.expectEqualStrings("Undo", decoded.operations[0].item.label[0..4]);

    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeToolbarPatch(a, bytes.items));
    bytes.items[3] = 0;
    bytes.items[toolbar_patch_header_size + toolbar_patch_operation_size + 16] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeToolbarPatch(a, bytes.items));
    bytes.items[toolbar_patch_header_size + toolbar_patch_operation_size + 16] = @intFromEnum(ToolbarPatchOperationKind.delete);
    bytes.items[toolbar_patch_header_size + toolbar_patch_operation_size + 24] = 'x';
    try std.testing.expectError(Error.InvalidReserved, decodeToolbarPatch(a, bytes.items));
    try std.testing.expectError(Error.InvalidTable, decodeToolbarPatch(a, bytes.items[0 .. bytes.items.len - 1]));

    const stale_header: ToolbarPatchHeader = .{
        .frame_id = header.frame_id,
        .frame_generation = header.frame_generation,
        .toolbar_id = header.toolbar_id,
        .expected_generation = header.new_generation,
        .new_generation = header.new_generation,
    };
    try std.testing.expectError(Error.InvalidMessage, encodeToolbarPatch(a, stale_header, &operations, &bytes));
}

test "menu hover codecs enforce phase-specific bounded identity" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    const hover: MenuHover = .{
        .phase = .move,
        .menu_id = 3,
        .menu_generation = 4,
        .item_id = 21,
        .window_id = 10,
        .frame_generation = 1,
        .x = 8,
        .y = 16,
    };
    try encodeMenuHover(a, hover, &bytes);
    try std.testing.expectEqual(menu_hover_size, bytes.items.len);
    try std.testing.expectEqual(hover, try decodeMenuHover(bytes.items));
    bytes.items[2] = @intFromEnum(MenuHoverPhase.enter);
    try std.testing.expectEqual(MenuHoverPhase.enter, (try decodeMenuHover(bytes.items)).phase);
    bytes.items[2] = @intFromEnum(MenuHoverPhase.move);

    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuHover(bytes.items));
    bytes.items[3] = 0;
    bytes.items[39] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuHover(bytes.items));
    bytes.items[39] = 0;
    bytes.items[2] = 3;
    try std.testing.expectError(Error.InvalidMenuHover, decodeMenuHover(bytes.items));

    bytes.items[2] = @intFromEnum(MenuHoverPhase.move);
    std.mem.writeInt(u32, bytes.items[12..16], 0, .little);
    try std.testing.expectError(Error.InvalidMenuHover, decodeMenuHover(bytes.items));
    std.mem.writeInt(u32, bytes.items[12..16], hover.item_id, .little);
    std.mem.writeInt(i32, bytes.items[28..32], -1, .little);
    try std.testing.expectError(Error.InvalidMenuHover, decodeMenuHover(bytes.items));
    std.mem.writeInt(i32, bytes.items[28..32], hover.x, .little);
    std.mem.writeInt(i32, bytes.items[32..36], -1, .little);
    try std.testing.expectError(Error.InvalidMenuHover, decodeMenuHover(bytes.items));
    std.mem.writeInt(i32, bytes.items[32..36], hover.y, .little);
    bytes.items[0] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuHover(bytes.items));
    bytes.items[0] = 1;
    std.mem.writeInt(u32, bytes.items[4..8], 0, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeMenuHover(bytes.items));
    std.mem.writeInt(u32, bytes.items[4..8], hover.menu_id, .little);
    std.mem.writeInt(u32, bytes.items[8..12], 0, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeMenuHover(bytes.items));
    std.mem.writeInt(u32, bytes.items[8..12], hover.menu_generation, .little);
    std.mem.writeInt(u64, bytes.items[16..24], 0, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeMenuHover(bytes.items));
    std.mem.writeInt(u64, bytes.items[16..24], hover.window_id, .little);
    std.mem.writeInt(u32, bytes.items[24..28], 0, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeMenuHover(bytes.items));
    std.mem.writeInt(u32, bytes.items[24..28], hover.frame_generation, .little);
    try std.testing.expectError(Error.InvalidTable, decodeMenuHover(bytes.items[0 .. bytes.items.len - 1]));

    const leave: MenuHover = .{
        .phase = .leave,
        .menu_id = 3,
        .menu_generation = 4,
        .window_id = 10,
        .frame_generation = 1,
    };
    bytes.clearRetainingCapacity();
    try encodeMenuHover(a, leave, &bytes);
    try std.testing.expectEqual(leave, try decodeMenuHover(bytes.items));
    bytes.items[12] = 1;
    try std.testing.expectError(Error.InvalidMenuHover, decodeMenuHover(bytes.items));
    bytes.items[12] = 0;
    std.mem.writeInt(i32, bytes.items[28..32], -1, .little);
    try std.testing.expectError(Error.InvalidMenuHover, decodeMenuHover(bytes.items));
    std.mem.writeInt(i32, bytes.items[28..32], 0, .little);
    bytes.items[32] = 1;
    try std.testing.expectError(Error.InvalidMenuHover, decodeMenuHover(bytes.items));
}

pub const ToolbarItemKind = enum(u8) {
    separator = 1,
    button = 2,
    toggle = 3,
    space = 4,
};

pub const ToolbarItemFlags = struct {
    pub const enabled: u8 = 1 << 0;
    pub const visible: u8 = 1 << 1;
    pub const selected: u8 = 1 << 2;
    pub const pressed: u8 = 1 << 3;
    pub const known: u8 = enabled | visible | selected | pressed;
};

pub const ToolbarModelHeader = struct {
    frame_id: u32,
    frame_generation: u32,
    toolbar_id: u32,
    toolbar_generation: u32,
};

pub const ToolbarItem = struct {
    item_id: u32,
    icon_image_id: u32 = 0,
    icon_image_generation: u32 = 0,
    kind: ToolbarItemKind,
    flags: u8 = ToolbarItemFlags.enabled | ToolbarItemFlags.visible,
    label: [64]u8 = @splat(0),
    label_len: u8 = 0,
    help: [64]u8 = @splat(0),
    help_len: u8 = 0,
    key: [16]u8 = @splat(0),
    key_len: u8 = 0,
};

pub const ToolbarModel = struct {
    header: ToolbarModelHeader,
    items: []const ToolbarItem,
};

pub const toolbar_model_header_size: usize = 40;
pub const toolbar_item_size: usize = 164;
pub const toolbar_model_schema: u16 = 1;
pub const max_toolbar_items: usize = 16;

pub const ToolbarClickPhase = enum(u8) {
    press = 1,
    release = 2,
};

pub const ToolbarClick = struct {
    schema: u16 = 1,
    phase: ToolbarClickPhase,
    reserved: u8 = 0,
    toolbar_id: u32,
    toolbar_generation: u32,
    item_id: u32,
    window_id: u64,
    frame_generation: u32,
    click_count: u8,
    button: u8,
    modifiers: u16,
    x: i32,
    y: i32,
    reserved_tail: [8]u8 = @splat(0),
};

pub const toolbar_click_size: usize = 48;

fn validateToolbarText(bytes: []const u8) Error!void {
    if (bytes.len == 0) return Error.InvalidMessage;
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return Error.InvalidMessage;
    for (bytes) |byte| {
        if (byte < 0x20 or byte == 0x7f) return Error.InvalidMessage;
    }
    if (!std.unicode.utf8ValidateSlice(bytes)) return Error.InvalidUtf8;
}

fn validateToolbarItem(item: ToolbarItem) Error!void {
    if (item.item_id == 0) return Error.InvalidMessage;
    if (item.flags & ~ToolbarItemFlags.known != 0) return Error.InvalidReserved;
    if (item.label_len > item.label.len or item.help_len > item.help.len or
        item.key_len > item.key.len) return Error.InvalidMessage;
    if (!std.mem.allEqual(u8, item.label[item.label_len..], 0) or
        !std.mem.allEqual(u8, item.help[item.help_len..], 0) or
        !std.mem.allEqual(u8, item.key[item.key_len..], 0))
        return Error.InvalidReserved;
    if (item.label_len != 0) try validateToolbarText(item.label[0..item.label_len]);
    if (item.help_len != 0) try validateToolbarText(item.help[0..item.help_len]);
    if (item.key_len != 0) try validateToolbarText(item.key[0..item.key_len]);
    if ((item.icon_image_id == 0) != (item.icon_image_generation == 0))
        return Error.InvalidMessage;
    const visible = item.flags & ToolbarItemFlags.visible != 0;
    const enabled = item.flags & ToolbarItemFlags.enabled != 0;
    const selected = item.flags & ToolbarItemFlags.selected != 0;
    const pressed = item.flags & ToolbarItemFlags.pressed != 0;
    if (!visible and (enabled or selected or pressed)) return Error.InvalidMessage;
    if (pressed and !enabled) return Error.InvalidMessage;
    switch (item.kind) {
        .separator, .space => {
            if (item.label_len != 0 or item.help_len != 0 or item.key_len != 0 or
                item.icon_image_id != 0 or item.icon_image_generation != 0 or
                enabled or selected or pressed)
                return Error.InvalidMessage;
        },
        .button => {
            if (item.label_len == 0 and item.icon_image_id == 0) return Error.InvalidMessage;
            if (selected) return Error.InvalidMessage;
        },
        .toggle => {
            if (item.label_len == 0 and item.icon_image_id == 0) return Error.InvalidMessage;
        },
    }
}

pub fn validateToolbarModel(model: ToolbarModel) Error!void {
    const header = model.header;
    if (header.frame_id == 0 or header.frame_generation == 0 or
        header.toolbar_id == 0 or header.toolbar_generation == 0)
        return Error.InvalidMessage;
    if (model.items.len == 0 or model.items.len > max_toolbar_items)
        return Error.InvalidMessage;
    for (model.items, 0..) |item, index| {
        try validateToolbarItem(item);
        for (model.items[0..index]) |prior| {
            if (prior.item_id == item.item_id) return Error.InvalidTable;
        }
    }
}

pub fn encodeToolbarModel(a: std.mem.Allocator, model: ToolbarModel, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateToolbarModel(model);
    var header: [toolbar_model_header_size]u8 = @splat(0);
    std.mem.writeInt(u16, header[0..2], toolbar_model_schema, .little);
    std.mem.writeInt(u32, header[4..8], model.header.frame_id, .little);
    std.mem.writeInt(u32, header[8..12], model.header.frame_generation, .little);
    std.mem.writeInt(u32, header[12..16], model.header.toolbar_id, .little);
    std.mem.writeInt(u32, header[16..20], model.header.toolbar_generation, .little);
    std.mem.writeInt(u32, header[20..24], @intCast(model.items.len), .little);
    try out.appendSlice(a, &header);
    for (model.items) |item| {
        var bytes: [toolbar_item_size]u8 = @splat(0);
        std.mem.writeInt(u32, bytes[0..4], item.item_id, .little);
        std.mem.writeInt(u32, bytes[4..8], item.icon_image_id, .little);
        std.mem.writeInt(u32, bytes[8..12], item.icon_image_generation, .little);
        bytes[12] = @intFromEnum(item.kind);
        bytes[13] = item.flags;
        bytes[14] = item.label_len;
        bytes[15] = item.help_len;
        bytes[16] = item.key_len;
        @memcpy(bytes[20..84], &item.label);
        @memcpy(bytes[84..148], &item.help);
        @memcpy(bytes[148..164], &item.key);
        try out.appendSlice(a, &bytes);
    }
}

pub fn decodeToolbarModel(a: std.mem.Allocator, data: []const u8) (Error || std.mem.Allocator.Error)!ToolbarModel {
    if (data.len < toolbar_model_header_size) return Error.InvalidTable;
    var reader = Reader{ .data = data };
    if (try reader.readU16() != toolbar_model_schema) return Error.InvalidVersion;
    const flags = try reader.readByte();
    const reserved = try reader.readByte();
    const header: ToolbarModelHeader = .{
        .frame_id = try reader.readU32(),
        .frame_generation = try reader.readU32(),
        .toolbar_id = try reader.readU32(),
        .toolbar_generation = try reader.readU32(),
    };
    const item_count = try reader.readU32();
    try reader.expectZeros(16);
    if (flags != 0 or reserved != 0) return Error.InvalidReserved;
    if (item_count == 0 or item_count > max_toolbar_items) return Error.InvalidTable;
    if (data.len != toolbar_model_header_size + @as(usize, item_count) * toolbar_item_size)
        return Error.InvalidTable;
    const items = try a.alloc(ToolbarItem, item_count);
    errdefer a.free(items);
    for (items) |*item| {
        item.* = .{
            .item_id = try reader.readU32(),
            .icon_image_id = try reader.readU32(),
            .icon_image_generation = try reader.readU32(),
            .kind = switch (try reader.readByte()) {
                1 => .separator,
                2 => .button,
                3 => .toggle,
                4 => .space,
                else => return Error.InvalidMessage,
            },
            .flags = try reader.readByte(),
            .label_len = try reader.readByte(),
            .help_len = try reader.readByte(),
            .key_len = try reader.readByte(),
        };
        try reader.expectZeros(3);
        item.label = (try reader.bytes(64))[0..64].*;
        item.help = (try reader.bytes(64))[0..64].*;
        item.key = (try reader.bytes(16))[0..16].*;
    }
    const model: ToolbarModel = .{ .header = header, .items = items };
    try validateToolbarModel(model);
    return model;
}

pub fn freeToolbarModel(a: std.mem.Allocator, model: *ToolbarModel) void {
    a.free(model.items);
    model.items = &.{};
}

pub const ToolbarPatchOperationKind = enum(u8) {
    upsert = 1,
    delete = 2,
};

pub const ToolbarPatchHeader = struct {
    frame_id: u32,
    frame_generation: u32,
    toolbar_id: u32,
    expected_generation: u32,
    new_generation: u32,
};

pub const ToolbarPatchOperation = struct {
    operation: ToolbarPatchOperationKind,
    item: ToolbarItem,
};

pub const toolbar_patch_header_size: usize = 44;
pub const toolbar_patch_operation_size: usize = 168;
pub const toolbar_patch_schema: u16 = 1;
pub const max_toolbar_patch_operations: usize = 16;

fn validateToolbarPatchHeader(header: ToolbarPatchHeader, operation_count: u32) Error!void {
    if (header.frame_id == 0 or header.frame_generation == 0 or
        header.toolbar_id == 0 or header.expected_generation == 0 or
        header.new_generation <= header.expected_generation or
        operation_count == 0 or operation_count > max_toolbar_patch_operations)
        return Error.InvalidMessage;
}

fn validateToolbarPatchOperation(operation: ToolbarPatchOperation) Error!void {
    if (operation.item.item_id == 0) return Error.InvalidMessage;
    if (operation.operation == .delete) {
        if (operation.item.kind != .button or operation.item.flags != 0 or
            operation.item.label_len != 0 or operation.item.help_len != 0 or
            operation.item.key_len != 0 or operation.item.icon_image_id != 0 or
            operation.item.icon_image_generation != 0)
            return Error.InvalidMessage;
        if (!std.mem.allEqual(u8, &operation.item.label, 0) or
            !std.mem.allEqual(u8, &operation.item.help, 0) or
            !std.mem.allEqual(u8, &operation.item.key, 0))
            return Error.InvalidReserved;
        return;
    }
    try validateToolbarItem(operation.item);
}

pub fn encodeToolbarPatch(
    a: std.mem.Allocator,
    header: ToolbarPatchHeader,
    operations: []const ToolbarPatchOperation,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateToolbarPatchHeader(header, @intCast(operations.len));
    var header_bytes: [toolbar_patch_header_size]u8 = @splat(0);
    std.mem.writeInt(u16, header_bytes[0..2], toolbar_patch_schema, .little);
    std.mem.writeInt(u32, header_bytes[4..8], header.frame_id, .little);
    std.mem.writeInt(u32, header_bytes[8..12], header.frame_generation, .little);
    std.mem.writeInt(u32, header_bytes[12..16], header.toolbar_id, .little);
    std.mem.writeInt(u32, header_bytes[16..20], header.expected_generation, .little);
    std.mem.writeInt(u32, header_bytes[20..24], header.new_generation, .little);
    std.mem.writeInt(u32, header_bytes[24..28], @intCast(operations.len), .little);
    try out.appendSlice(a, &header_bytes);
    for (operations) |operation| {
        try validateToolbarPatchOperation(operation);
        var bytes: [toolbar_patch_operation_size]u8 = @splat(0);
        bytes[0] = @intFromEnum(operation.operation);
        std.mem.writeInt(u32, bytes[4..8], operation.item.item_id, .little);
        std.mem.writeInt(u32, bytes[8..12], operation.item.icon_image_id, .little);
        std.mem.writeInt(u32, bytes[12..16], operation.item.icon_image_generation, .little);
        bytes[16] = @intFromEnum(operation.item.kind);
        bytes[17] = operation.item.flags;
        bytes[18] = operation.item.label_len;
        bytes[19] = operation.item.help_len;
        bytes[20] = operation.item.key_len;
        @memcpy(bytes[24..88], &operation.item.label);
        @memcpy(bytes[88..152], &operation.item.help);
        @memcpy(bytes[152..168], &operation.item.key);
        try out.appendSlice(a, &bytes);
    }
}

pub fn decodeToolbarPatch(
    a: std.mem.Allocator,
    data: []const u8,
) (Error || std.mem.Allocator.Error)!struct { header: ToolbarPatchHeader, operations: []ToolbarPatchOperation } {
    if (data.len < toolbar_patch_header_size) return Error.InvalidTable;
    var reader = Reader{ .data = data };
    if (try reader.readU16() != toolbar_patch_schema) return Error.InvalidVersion;
    const flags = try reader.readByte();
    const reserved = try reader.readByte();
    const header: ToolbarPatchHeader = .{
        .frame_id = try reader.readU32(),
        .frame_generation = try reader.readU32(),
        .toolbar_id = try reader.readU32(),
        .expected_generation = try reader.readU32(),
        .new_generation = try reader.readU32(),
    };
    const operation_count = try reader.readU32();
    try reader.expectZeros(16);
    if (flags != 0 or reserved != 0) return Error.InvalidReserved;
    try validateToolbarPatchHeader(header, operation_count);
    if (data.len != toolbar_patch_header_size + @as(usize, operation_count) * toolbar_patch_operation_size)
        return Error.InvalidTable;
    const operations = try a.alloc(ToolbarPatchOperation, operation_count);
    errdefer a.free(operations);
    for (operations) |*operation| {
        const operation_kind: ToolbarPatchOperationKind = switch (try reader.readByte()) {
            1 => .upsert,
            2 => .delete,
            else => return Error.InvalidMessage,
        };
        try reader.expectZeros(3);
        var item: ToolbarItem = .{
            .item_id = try reader.readU32(),
            .icon_image_id = try reader.readU32(),
            .icon_image_generation = try reader.readU32(),
            .kind = switch (try reader.readByte()) {
                1 => .separator,
                2 => .button,
                3 => .toggle,
                4 => .space,
                else => return Error.InvalidMessage,
            },
            .flags = try reader.readByte(),
            .label_len = try reader.readByte(),
            .help_len = try reader.readByte(),
            .key_len = try reader.readByte(),
        };
        try reader.expectZeros(3);
        item.label = (try reader.bytes(64))[0..64].*;
        item.help = (try reader.bytes(64))[0..64].*;
        item.key = (try reader.bytes(16))[0..16].*;
        operation.* = .{ .operation = operation_kind, .item = item };
        try validateToolbarPatchOperation(operation.*);
    }
    return .{ .header = header, .operations = operations };
}

pub fn freeToolbarPatchOperations(a: std.mem.Allocator, operations: []ToolbarPatchOperation) void {
    a.free(operations);
}

pub fn validateToolbarClick(payload: ToolbarClick) Error!void {
    if (payload.schema != 1 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0) or
        payload.toolbar_id == 0 or payload.toolbar_generation == 0 or
        payload.item_id == 0 or payload.window_id == 0 or
        payload.frame_generation == 0)
        return Error.InvalidToolbarClick;
    switch (payload.phase) {
        .press, .release => {},
    }
    if (payload.click_count == 0 or payload.click_count > 8 or
        payload.button == 0 or payload.button > 5 or payload.x < 0 or payload.y < 0)
        return Error.InvalidMessage;
}

pub fn encodeToolbarClick(a: std.mem.Allocator, payload: ToolbarClick, out: *std.ArrayList(u8)) !void {
    try validateToolbarClick(payload);
    var b: [toolbar_click_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    b[2] = @intFromEnum(payload.phase);
    b[3] = payload.reserved;
    std.mem.writeInt(u32, b[4..8], payload.toolbar_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.toolbar_generation, .little);
    std.mem.writeInt(u32, b[12..16], payload.item_id, .little);
    std.mem.writeInt(u64, b[16..24], payload.window_id, .little);
    std.mem.writeInt(u32, b[24..28], payload.frame_generation, .little);
    b[28] = payload.click_count;
    b[29] = payload.button;
    std.mem.writeInt(u16, b[30..32], payload.modifiers, .little);
    std.mem.writeInt(i32, b[32..36], payload.x, .little);
    std.mem.writeInt(i32, b[36..40], payload.y, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeToolbarClick(data: []const u8) Error!ToolbarClick {
    if (data.len != toolbar_click_size) return Error.InvalidTable;
    const payload: ToolbarClick = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .phase = switch (data[2]) {
            1 => .press,
            2 => .release,
            else => return Error.InvalidMessage,
        },
        .reserved = data[3],
        .toolbar_id = std.mem.readInt(u32, data[4..8], .little),
        .toolbar_generation = std.mem.readInt(u32, data[8..12], .little),
        .item_id = std.mem.readInt(u32, data[12..16], .little),
        .window_id = std.mem.readInt(u64, data[16..24], .little),
        .frame_generation = std.mem.readInt(u32, data[24..28], .little),
        .click_count = data[28],
        .button = data[29],
        .modifiers = std.mem.readInt(u16, data[30..32], .little),
        .x = @bitCast(std.mem.readInt(u32, data[32..36], .little)),
        .y = @bitCast(std.mem.readInt(u32, data[36..40], .little)),
        .reserved_tail = data[40..48][0..8].*,
    };
    try validateToolbarClick(payload);
    return payload;
}

pub const DialogKind = enum(u8) {
    message = 1,
    prompt = 2,
    confirm = 3,
};

pub const DialogFlags = struct {
    pub const modal: u8 = 1 << 0;
    pub const known: u8 = modal;
};

pub const DialogButtons = struct {
    pub const ok: u16 = 1 << 0;
    pub const cancel: u16 = 1 << 1;
    pub const yes: u16 = 1 << 2;
    pub const no: u16 = 1 << 3;
    pub const retry: u16 = 1 << 4;
    pub const close: u16 = 1 << 5;
    pub const known: u16 = ok | cancel | yes | no | retry | close;
};

pub const max_dialog_title: usize = 64;
pub const max_dialog_text: usize = 192;

pub const DialogState = struct {
    schema: u16 = 1,
    flags: u8 = DialogFlags.modal,
    kind: DialogKind,
    reserved: u8 = 0,
    dialog_id: u32,
    dialog_generation: u32,
    window_id: u64,
    frame_generation: u32,
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    title_len: u8,
    text_len: u16,
    buttons: u16,
    reserved_tail: u16 = 0,
    title: [max_dialog_title]u8 = @splat(0),
    text: [max_dialog_text]u8 = @splat(0),
};

pub const dialog_state_size: usize = 304;

pub const DialogCloseReason = enum(u8) {
    action = 1,
    escape = 2,
    replaced = 3,
    shutdown = 4,
};

pub const DialogClose = struct {
    schema: u16 = 1,
    reason: DialogCloseReason,
    reserved: u8 = 0,
    dialog_id: u32,
    dialog_generation: u32,
    window_id: u64,
    frame_generation: u32,
    reserved_tail: [4]u8 = @splat(0),
};

pub const dialog_close_size: usize = 28;

pub const DialogResultButton = enum(u8) {
    ok = 1,
    cancel = 2,
    yes = 3,
    no = 4,
    retry = 5,
    close = 6,
    custom = 7,
};

pub const DialogResult = struct {
    schema: u16 = 1,
    button: DialogResultButton,
    flags: u8 = 0,
    dialog_id: u32,
    dialog_generation: u32,
    window_id: u64,
    frame_generation: u32,
    text_len: u16 = 0,
    reserved_tail: [6]u8 = @splat(0),
    text: [128]u8 = @splat(0),
};

pub const dialog_result_size: usize = 160;

fn validateDialogGeometry(state: DialogState) Error!void {
    if (state.x < 0 or state.y < 0 or state.width == 0 or state.height == 0 or
        state.width > max_window_size or state.height > max_window_size)
        return Error.InvalidMessage;
}

fn validateDialogState(state: DialogState) Error!void {
    if (state.schema != 1 or state.flags & ~DialogFlags.known != 0 or
        state.reserved != 0 or state.reserved_tail != 0 or
        state.dialog_id == 0 or state.dialog_generation == 0 or
        state.window_id == 0 or state.frame_generation == 0)
        return Error.InvalidMessage;
    try validateDialogGeometry(state);
    if (state.title_len == 0 or state.title_len > max_dialog_title or
        state.text_len == 0 or state.text_len > max_dialog_text or
        !std.mem.allEqual(u8, state.title[state.title_len..], 0) or
        !std.mem.allEqual(u8, state.text[state.text_len..], 0))
        return Error.InvalidMessage;
    try validateToolbarText(state.title[0..state.title_len]);
    try validateToolbarText(state.text[0..state.text_len]);
    if (state.buttons == 0 or state.buttons & ~DialogButtons.known != 0)
        return Error.InvalidMessage;
    switch (state.kind) {
        .message => {
            if (state.buttons & (DialogButtons.yes | DialogButtons.no) != 0)
                return Error.InvalidMessage;
        },
        .prompt => {
            if (state.buttons & DialogButtons.yes != 0) return Error.InvalidMessage;
        },
        .confirm => {
            if (state.buttons & DialogButtons.ok != 0) return Error.InvalidMessage;
        },
    }
}

pub fn encodeDialogState(a: std.mem.Allocator, state: DialogState, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateDialogState(state);
    var b: [dialog_state_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], state.schema, .little);
    b[2] = state.flags;
    b[3] = @intFromEnum(state.kind);
    std.mem.writeInt(u32, b[4..8], state.dialog_id, .little);
    std.mem.writeInt(u32, b[8..12], state.dialog_generation, .little);
    std.mem.writeInt(u64, b[12..20], state.window_id, .little);
    std.mem.writeInt(u32, b[20..24], state.frame_generation, .little);
    std.mem.writeInt(i32, b[24..28], state.x, .little);
    std.mem.writeInt(i32, b[28..32], state.y, .little);
    std.mem.writeInt(u32, b[32..36], state.width, .little);
    std.mem.writeInt(u32, b[36..40], state.height, .little);
    b[40] = state.title_len;
    std.mem.writeInt(u16, b[42..44], state.text_len, .little);
    std.mem.writeInt(u16, b[44..46], state.buttons, .little);
    @memcpy(b[48..112], &state.title);
    @memcpy(b[112..304], &state.text);
    try out.appendSlice(a, &b);
}

pub fn decodeDialogState(data: []const u8) Error!DialogState {
    if (data.len != dialog_state_size) return Error.InvalidTable;
    if (data[41] != 0) return Error.InvalidReserved;
    const state: DialogState = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .kind = switch (data[3]) {
            1 => .message,
            2 => .prompt,
            3 => .confirm,
            else => return Error.InvalidMessage,
        },
        .dialog_id = std.mem.readInt(u32, data[4..8], .little),
        .dialog_generation = std.mem.readInt(u32, data[8..12], .little),
        .window_id = std.mem.readInt(u64, data[12..20], .little),
        .frame_generation = std.mem.readInt(u32, data[20..24], .little),
        .x = @bitCast(std.mem.readInt(u32, data[24..28], .little)),
        .y = @bitCast(std.mem.readInt(u32, data[28..32], .little)),
        .width = std.mem.readInt(u32, data[32..36], .little),
        .height = std.mem.readInt(u32, data[36..40], .little),
        .title_len = data[40],
        .text_len = std.mem.readInt(u16, data[42..44], .little),
        .buttons = std.mem.readInt(u16, data[44..46], .little),
        .reserved_tail = std.mem.readInt(u16, data[46..48], .little),
        .title = data[48..112][0..max_dialog_title].*,
        .text = data[112..304][0..max_dialog_text].*,
    };
    try validateDialogState(state);
    return state;
}

pub fn encodeDialogClose(a: std.mem.Allocator, payload: DialogClose, out: *std.ArrayList(u8)) !void {
    if (payload.schema != 1 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0) or
        payload.dialog_id == 0 or payload.dialog_generation == 0 or
        payload.window_id == 0 or payload.frame_generation == 0)
        return Error.InvalidMessage;
    switch (payload.reason) {
        .action, .escape, .replaced, .shutdown => {},
    }
    var b: [dialog_close_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    b[2] = @intFromEnum(payload.reason);
    b[3] = payload.reserved;
    std.mem.writeInt(u32, b[4..8], payload.dialog_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.dialog_generation, .little);
    std.mem.writeInt(u64, b[12..20], payload.window_id, .little);
    std.mem.writeInt(u32, b[20..24], payload.frame_generation, .little);
    try out.appendSlice(a, &b);
}

pub fn decodeDialogClose(data: []const u8) Error!DialogClose {
    if (data.len != dialog_close_size) return Error.InvalidTable;
    const payload: DialogClose = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .reason = switch (data[2]) {
            1 => .action,
            2 => .escape,
            3 => .replaced,
            4 => .shutdown,
            else => return Error.InvalidMessage,
        },
        .reserved = data[3],
        .dialog_id = std.mem.readInt(u32, data[4..8], .little),
        .dialog_generation = std.mem.readInt(u32, data[8..12], .little),
        .window_id = std.mem.readInt(u64, data[12..20], .little),
        .frame_generation = std.mem.readInt(u32, data[20..24], .little),
        .reserved_tail = data[24..dialog_close_size][0..4].*,
    };
    if (payload.schema != 1 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0) or
        payload.dialog_id == 0 or payload.dialog_generation == 0 or
        payload.window_id == 0 or payload.frame_generation == 0)
        return Error.InvalidMessage;
    return payload;
}

fn validateDialogResultText(text: []const u8) Error!void {
    if (std.mem.indexOfScalar(u8, text, 0) != null) return Error.InvalidMessage;
    for (text) |byte| {
        if (byte < 0x20 or byte == 0x7f) return Error.InvalidMessage;
    }
    if (!std.unicode.utf8ValidateSlice(text)) return Error.InvalidUtf8;
}

pub fn validateDialogResult(payload: DialogResult) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0) or
        payload.dialog_id == 0 or payload.dialog_generation == 0 or
        payload.window_id == 0 or payload.frame_generation == 0)
        return Error.InvalidDialogResult;
    if (payload.text_len > payload.text.len or
        !std.mem.allEqual(u8, payload.text[payload.text_len..], 0))
        return Error.InvalidDialogResult;
    if (payload.text_len != 0) try validateDialogResultText(payload.text[0..payload.text_len]);
    switch (payload.button) {
        .ok, .cancel, .yes, .no, .retry, .close, .custom => {},
    }
}

pub fn encodeDialogResult(a: std.mem.Allocator, payload: DialogResult, out: *std.ArrayList(u8)) !void {
    try validateDialogResult(payload);
    var b: [dialog_result_size]u8 = @splat(0);
    std.mem.writeInt(u16, b[0..2], payload.schema, .little);
    b[2] = @intFromEnum(payload.button);
    b[3] = payload.flags;
    std.mem.writeInt(u32, b[4..8], payload.dialog_id, .little);
    std.mem.writeInt(u32, b[8..12], payload.dialog_generation, .little);
    std.mem.writeInt(u64, b[12..20], payload.window_id, .little);
    std.mem.writeInt(u32, b[20..24], payload.frame_generation, .little);
    std.mem.writeInt(u16, b[24..26], payload.text_len, .little);
    @memcpy(b[32..160], payload.text[0..128]);
    try out.appendSlice(a, &b);
}

pub fn decodeDialogResult(data: []const u8) Error!DialogResult {
    if (data.len != dialog_result_size) return Error.InvalidTable;
    const payload: DialogResult = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .button = switch (data[2]) {
            1 => .ok,
            2 => .cancel,
            3 => .yes,
            4 => .no,
            5 => .retry,
            6 => .close,
            7 => .custom,
            else => return Error.InvalidMessage,
        },
        .flags = data[3],
        .dialog_id = std.mem.readInt(u32, data[4..8], .little),
        .dialog_generation = std.mem.readInt(u32, data[8..12], .little),
        .window_id = std.mem.readInt(u64, data[12..20], .little),
        .frame_generation = std.mem.readInt(u32, data[20..24], .little),
        .text_len = std.mem.readInt(u16, data[24..26], .little),
        .reserved_tail = data[26..32][0..6].*,
        .text = data[32..160][0..128].*,
    };
    try validateDialogResult(payload);
    return payload;
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

fn validateFrameAlpha(payload: FrameAlphaPayload) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or
        payload.reserved != 0 or payload.reserved_middle != 0 or
        payload.reserved_tail != 0)
        return Error.InvalidMessage;
    if (payload.active_opacity > max_opacity or
        payload.inactive_opacity > max_opacity or
        payload.background_opacity > max_opacity)
        return Error.InvalidMessage;
    if (payload.frame_generation == 0) return Error.InvalidMessage;
}

pub fn encodeFrameAlpha(
    a: std.mem.Allocator,
    payload: FrameAlphaPayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameAlpha(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    std.mem.writeInt(u16, &bytes, payload.active_opacity, .little);
    try out.appendSlice(a, &bytes);
    std.mem.writeInt(u16, &bytes, payload.inactive_opacity, .little);
    try out.appendSlice(a, &bytes);
    std.mem.writeInt(u16, &bytes, payload.background_opacity, .little);
    try out.appendSlice(a, &bytes);
    std.mem.writeInt(u16, &bytes, payload.reserved_middle, .little);
    try out.appendSlice(a, &bytes);
    var word: [4]u8 = undefined;
    std.mem.writeInt(u32, &word, payload.frame_generation, .little);
    try out.appendSlice(a, &word);
    std.mem.writeInt(u32, &word, payload.reserved_tail, .little);
    try out.appendSlice(a, &word);
}

pub fn decodeFrameAlpha(data: []const u8) Error!FrameAlphaPayload {
    if (data.len != 20) return Error.InvalidTable;
    const payload = FrameAlphaPayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .active_opacity = std.mem.readInt(u16, data[4..6], .little),
        .inactive_opacity = std.mem.readInt(u16, data[6..8], .little),
        .background_opacity = std.mem.readInt(u16, data[8..10], .little),
        .reserved_middle = std.mem.readInt(u16, data[10..12], .little),
        .frame_generation = std.mem.readInt(u32, data[12..16], .little),
        .reserved_tail = std.mem.readInt(u32, data[16..20], .little),
    };
    try validateFrameAlpha(payload);
    return payload;
}

pub fn validateFrameAlphaEnvelope(payload: FrameAlphaPayload, envelope: Envelope) Error!void {
    try validateFrameAlpha(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

fn validateFrameDecorations(payload: FrameDecorationsPayload) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_after_decorated, 0))
        return Error.InvalidMessage;
    if (payload.frame_generation == 0) return Error.InvalidMessage;
}

pub fn encodeFrameDecorations(
    a: std.mem.Allocator,
    payload: FrameDecorationsPayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameDecorations(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    try out.append(a, @intFromBool(payload.decorated));
    try out.appendSlice(a, &payload.reserved_after_decorated);
    var word: [4]u8 = undefined;
    std.mem.writeInt(u32, &word, payload.frame_generation, .little);
    try out.appendSlice(a, &word);
}

pub fn decodeFrameDecorations(data: []const u8) Error!FrameDecorationsPayload {
    if (data.len != 12) return Error.InvalidTable;
    const payload = FrameDecorationsPayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .decorated = switch (data[4]) {
            0 => false,
            1 => true,
            else => return Error.InvalidBoolean,
        },
        .reserved_after_decorated = data[5..8][0..3].*,
        .frame_generation = std.mem.readInt(u32, data[8..12], .little),
    };
    try validateFrameDecorations(payload);
    return payload;
}

pub fn validateFrameDecorationsEnvelope(payload: FrameDecorationsPayload, envelope: Envelope) Error!void {
    try validateFrameDecorations(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

fn validateFrameScale(payload: FrameScalePayload) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        payload.reserved_tail != 0) return Error.InvalidMessage;
    if (!std.math.isFinite(payload.scale) or payload.scale <= 0 or
        payload.scale > max_frame_scale) return Error.InvalidMessage;
    if (!std.math.isFinite(payload.dpi_x) or payload.dpi_x <= 0 or
        payload.dpi_x > max_frame_dpi) return Error.InvalidMessage;
    if (!std.math.isFinite(payload.dpi_y) or payload.dpi_y <= 0 or
        payload.dpi_y > max_frame_dpi) return Error.InvalidMessage;
    if (payload.frame_generation == 0) return Error.InvalidMessage;
}

pub fn encodeFrameScale(
    a: std.mem.Allocator,
    payload: FrameScalePayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameScale(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    var word: [4]u8 = undefined;
    inline for (.{ payload.scale, payload.dpi_x, payload.dpi_y }) |value| {
        std.mem.writeInt(u32, &word, @bitCast(value), .little);
        try out.appendSlice(a, &word);
    }
    std.mem.writeInt(u32, &word, payload.frame_generation, .little);
    try out.appendSlice(a, &word);
    std.mem.writeInt(u32, &word, payload.reserved_tail, .little);
    try out.appendSlice(a, &word);
}

pub fn decodeFrameScale(data: []const u8) Error!FrameScalePayload {
    if (data.len != 24) return Error.InvalidTable;
    const payload = FrameScalePayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .scale = @bitCast(std.mem.readInt(u32, data[4..8], .little)),
        .dpi_x = @bitCast(std.mem.readInt(u32, data[8..12], .little)),
        .dpi_y = @bitCast(std.mem.readInt(u32, data[12..16], .little)),
        .frame_generation = std.mem.readInt(u32, data[16..20], .little),
        .reserved_tail = std.mem.readInt(u32, data[20..24], .little),
    };
    try validateFrameScale(payload);
    return payload;
}

pub fn validateFrameScaleEnvelope(payload: FrameScalePayload, envelope: Envelope) Error!void {
    try validateFrameScale(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

fn validateFrameFullscreen(payload: FrameFullscreenPayload) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_after_mode, 0))
        return Error.InvalidMessage;
    if (payload.frame_generation == 0) return Error.InvalidMessage;
}

pub fn encodeFrameFullscreen(
    a: std.mem.Allocator,
    payload: FrameFullscreenPayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameFullscreen(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    try out.append(a, @intFromEnum(payload.mode));
    try out.appendSlice(a, &payload.reserved_after_mode);
    var word: [4]u8 = undefined;
    std.mem.writeInt(u32, &word, payload.frame_generation, .little);
    try out.appendSlice(a, &word);
}

pub fn decodeFrameFullscreen(data: []const u8) Error!FrameFullscreenPayload {
    if (data.len != 12) return Error.InvalidTable;
    const payload = FrameFullscreenPayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .mode = switch (data[4]) {
            0 => .none,
            1 => .fullboth,
            2 => .fullwidth,
            3 => .fullheight,
            4 => .maximized,
            else => return Error.InvalidMessage,
        },
        .reserved_after_mode = data[5..8][0..3].*,
        .frame_generation = std.mem.readInt(u32, data[8..12], .little),
    };
    try validateFrameFullscreen(payload);
    return payload;
}

pub fn validateFrameFullscreenEnvelope(payload: FrameFullscreenPayload, envelope: Envelope) Error!void {
    try validateFrameFullscreen(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

fn validateFrameMonitor(payload: FrameMonitorPayload) Error!void {
    if (payload.schema != 1 or payload.reserved != 0 or
        payload.flags & ~FrameMonitorFlags.primary != 0 or
        payload.reserved_tail != 0) return Error.InvalidMessage;
    if (payload.monitor_id == 0 or payload.frame_generation == 0) return Error.InvalidMessage;
    if (payload.width <= 0 or payload.height <= 0) return Error.InvalidMessage;
    const right = @as(i64, payload.x) + @as(i64, payload.width);
    const bottom = @as(i64, payload.y) + @as(i64, payload.height);
    if (right > std.math.maxInt(i32) or bottom > std.math.maxInt(i32))
        return Error.InvalidMessage;
}

pub fn encodeFrameMonitor(
    a: std.mem.Allocator,
    payload: FrameMonitorPayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameMonitor(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    var word: [4]u8 = undefined;
    std.mem.writeInt(u32, &word, payload.monitor_id, .little);
    try out.appendSlice(a, &word);
    inline for (.{ payload.x, payload.y, payload.width, payload.height }) |value| {
        std.mem.writeInt(u32, &word, @bitCast(value), .little);
        try out.appendSlice(a, &word);
    }
    std.mem.writeInt(u32, &word, payload.frame_generation, .little);
    try out.appendSlice(a, &word);
    std.mem.writeInt(u32, &word, payload.reserved_tail, .little);
    try out.appendSlice(a, &word);
}

pub fn decodeFrameMonitor(data: []const u8) Error!FrameMonitorPayload {
    if (data.len != 32) return Error.InvalidTable;
    const payload = FrameMonitorPayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .monitor_id = std.mem.readInt(u32, data[4..8], .little),
        .x = @bitCast(std.mem.readInt(u32, data[8..12], .little)),
        .y = @bitCast(std.mem.readInt(u32, data[12..16], .little)),
        .width = @bitCast(std.mem.readInt(u32, data[16..20], .little)),
        .height = @bitCast(std.mem.readInt(u32, data[20..24], .little)),
        .frame_generation = std.mem.readInt(u32, data[24..28], .little),
        .reserved_tail = std.mem.readInt(u32, data[28..32], .little),
    };
    try validateFrameMonitor(payload);
    return payload;
}

pub fn validateFrameMonitorEnvelope(payload: FrameMonitorPayload, envelope: Envelope) Error!void {
    try validateFrameMonitor(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

fn validateFrameMaximize(payload: FrameMaximizePayload) Error!void {
    if (payload.schema != 1 or payload.reserved != 0 or
        payload.flags & ~FrameMaximizeFlags.both != 0 or
        !std.mem.allEqual(u8, &payload.reserved_after_flags, 0))
        return Error.InvalidMessage;
    if (payload.flags == 0 or payload.frame_generation == 0) return Error.InvalidMessage;
}

pub fn encodeFrameMaximize(
    a: std.mem.Allocator,
    payload: FrameMaximizePayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameMaximize(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    try out.appendSlice(a, &payload.reserved_after_flags);
    var word: [4]u8 = undefined;
    std.mem.writeInt(u32, &word, payload.frame_generation, .little);
    try out.appendSlice(a, &word);
}

pub fn decodeFrameMaximize(data: []const u8) Error!FrameMaximizePayload {
    if (data.len != 12) return Error.InvalidTable;
    const payload = FrameMaximizePayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .reserved_after_flags = data[4..8][0..4].*,
        .frame_generation = std.mem.readInt(u32, data[8..12], .little),
    };
    try validateFrameMaximize(payload);
    return payload;
}

pub fn validateFrameMaximizeEnvelope(payload: FrameMaximizePayload, envelope: Envelope) Error!void {
    try validateFrameMaximize(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

fn validateFrameFeedbackIdentity(
    frame_generation: u32,
    redisplay_generation: u64,
    frame_sequence: u64,
    timestamp_ns: u64,
) Error!void {
    if (frame_generation == 0 or redisplay_generation == 0 or
        frame_sequence == 0 or timestamp_ns == 0) return Error.InvalidMessage;
}

fn validateFramePresented(payload: FramePresentedPayload) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0)) return Error.InvalidMessage;
    try validateFrameFeedbackIdentity(
        payload.frame_generation,
        payload.redisplay_generation,
        payload.frame_sequence,
        payload.presented_at_ns,
    );
}

pub fn encodeFramePresented(
    a: std.mem.Allocator,
    payload: FramePresentedPayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFramePresented(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    var word: [4]u8 = undefined;
    std.mem.writeInt(u32, &word, payload.frame_generation, .little);
    try out.appendSlice(a, &word);
    var long: [8]u8 = undefined;
    inline for (.{ payload.redisplay_generation, payload.frame_sequence, payload.presented_at_ns, payload.frame_path_ns, payload.draw_command_count }) |value| {
        std.mem.writeInt(u64, &long, value, .little);
        try out.appendSlice(a, &long);
    }
    try out.append(a, @intFromEnum(payload.damage_kind));
    try out.appendSlice(a, &payload.reserved_tail);
}

pub fn decodeFramePresented(data: []const u8) Error!FramePresentedPayload {
    if (data.len != 56) return Error.InvalidTable;
    const payload = FramePresentedPayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .frame_generation = std.mem.readInt(u32, data[4..8], .little),
        .redisplay_generation = std.mem.readInt(u64, data[8..16], .little),
        .frame_sequence = std.mem.readInt(u64, data[16..24], .little),
        .presented_at_ns = std.mem.readInt(u64, data[24..32], .little),
        .frame_path_ns = std.mem.readInt(u64, data[32..40], .little),
        .draw_command_count = std.mem.readInt(u64, data[40..48], .little),
        .damage_kind = switch (data[48]) {
            0 => .none,
            1 => .initial,
            2 => .cursor,
            3 => .text,
            4 => .region,
            5 => .viewport,
            6 => .unchanged,
            else => return Error.InvalidMessage,
        },
        .reserved_tail = data[49..56][0..7].*,
    };
    try validateFramePresented(payload);
    return payload;
}

fn validateFrameDropped(payload: FrameDroppedPayload) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0)) return Error.InvalidMessage;
    try validateFrameFeedbackIdentity(
        payload.frame_generation,
        payload.redisplay_generation,
        payload.frame_sequence,
        payload.observed_at_ns,
    );
}

pub fn encodeFrameDropped(
    a: std.mem.Allocator,
    payload: FrameDroppedPayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameDropped(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    var word: [4]u8 = undefined;
    std.mem.writeInt(u32, &word, payload.frame_generation, .little);
    try out.appendSlice(a, &word);
    var long: [8]u8 = undefined;
    inline for (.{ payload.redisplay_generation, payload.frame_sequence, payload.last_presented_sequence, payload.observed_at_ns }) |value| {
        std.mem.writeInt(u64, &long, value, .little);
        try out.appendSlice(a, &long);
    }
    try out.append(a, @intFromEnum(payload.reason));
    try out.appendSlice(a, &payload.reserved_tail);
}

pub fn decodeFrameDropped(data: []const u8) Error!FrameDroppedPayload {
    if (data.len != 48) return Error.InvalidTable;
    const payload = FrameDroppedPayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .frame_generation = std.mem.readInt(u32, data[4..8], .little),
        .redisplay_generation = std.mem.readInt(u64, data[8..16], .little),
        .frame_sequence = std.mem.readInt(u64, data[16..24], .little),
        .last_presented_sequence = std.mem.readInt(u64, data[24..32], .little),
        .observed_at_ns = std.mem.readInt(u64, data[32..40], .little),
        .reason = switch (data[40]) {
            1 => .invalid_window_size,
            2 => .render_device_lost,
            3 => .draw_failed,
            4 => .superseded,
            5 => .resource_missing,
            6 => .limit_exceeded,
            else => return Error.InvalidMessage,
        },
        .reserved_tail = data[41..48][0..7].*,
    };
    try validateFrameDropped(payload);
    return payload;
}

pub fn containsGeometryRect(outer: GeometryRect, inner: GeometryRect) bool {
    const outer_right = @as(i64, outer.x) + outer.width;
    const outer_bottom = @as(i64, outer.y) + outer.height;
    const inner_right = @as(i64, inner.x) + inner.width;
    const inner_bottom = @as(i64, inner.y) + inner.height;
    return inner.x >= outer.x and inner.y >= outer.y and
        inner_right <= outer_right and inner_bottom <= outer_bottom;
}

pub fn validGeometryRect(rect: GeometryRect) bool {
    return rect.width > 0 and rect.height > 0 and
        @as(i64, rect.x) + rect.width <= std.math.maxInt(i32) and
        @as(i64, rect.y) + rect.height <= std.math.maxInt(i32);
}

fn validateFrameGeometry(payload: FrameGeometryPayload) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0))
        return Error.InvalidMessage;
    if (payload.frame_generation == 0) return Error.InvalidMessage;
    const rects = [_]GeometryRect{ payload.outer, payload.content, payload.text, payload.window, payload.body };
    for (rects) |rect| {
        if (!validGeometryRect(rect)) return Error.InvalidMessage;
    }
    if (!containsGeometryRect(payload.outer, payload.content) or
        !containsGeometryRect(payload.content, payload.text) or
        !containsGeometryRect(payload.content, payload.window) or
        !containsGeometryRect(payload.window, payload.body))
        return Error.InvalidMessage;
}

fn encodeGeometryRect(a: std.mem.Allocator, rect: GeometryRect, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    var word: [4]u8 = undefined;
    inline for (.{ rect.x, rect.y, rect.width, rect.height }) |value| {
        std.mem.writeInt(u32, &word, @bitCast(value), .little);
        try out.appendSlice(a, &word);
    }
}

pub fn encodeFrameGeometry(
    a: std.mem.Allocator,
    payload: FrameGeometryPayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameGeometry(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    var word: [4]u8 = undefined;
    std.mem.writeInt(u32, &word, payload.frame_generation, .little);
    try out.appendSlice(a, &word);
    inline for (.{ payload.outer, payload.content, payload.text, payload.window, payload.body }) |rect| {
        try encodeGeometryRect(a, rect, out);
    }
    try out.appendSlice(a, &payload.reserved_tail);
}

pub fn decodeFrameGeometry(data: []const u8) Error!FrameGeometryPayload {
    if (data.len != 96) return Error.InvalidTable;
    const payload = FrameGeometryPayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .frame_generation = std.mem.readInt(u32, data[4..8], .little),
        .outer = .{
            .x = @bitCast(std.mem.readInt(u32, data[8..12], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[12..16], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[16..20], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[20..24], .little)),
        },
        .content = .{
            .x = @bitCast(std.mem.readInt(u32, data[24..28], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[28..32], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[32..36], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[36..40], .little)),
        },
        .text = .{
            .x = @bitCast(std.mem.readInt(u32, data[40..44], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[44..48], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[48..52], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[52..56], .little)),
        },
        .window = .{
            .x = @bitCast(std.mem.readInt(u32, data[56..60], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[60..64], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[64..68], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[68..72], .little)),
        },
        .body = .{
            .x = @bitCast(std.mem.readInt(u32, data[72..76], .little)),
            .y = @bitCast(std.mem.readInt(u32, data[76..80], .little)),
            .width = @bitCast(std.mem.readInt(u32, data[80..84], .little)),
            .height = @bitCast(std.mem.readInt(u32, data[84..88], .little)),
        },
    };
    if (std.mem.readInt(u32, data[88..92], .little) != 0 or
        std.mem.readInt(u32, data[92..96], .little) != 0) return Error.InvalidTable;
    try validateFrameGeometry(payload);
    return payload;
}

pub fn validateFrameGeometryEnvelope(payload: FrameGeometryPayload, envelope: Envelope) Error!void {
    try validateFrameGeometry(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

fn validateFrameIcon(payload: FrameIconPayload) Error!void {
    if (payload.schema != 1 or payload.reserved != 0 or
        payload.flags & ~FrameIconFlags.present != 0 or
        payload.reserved_tail != 0) return Error.InvalidMessage;
    if (payload.frame_generation == 0) return Error.InvalidMessage;
    if (payload.flags & FrameIconFlags.present != 0) {
        if (payload.image_id == 0 or payload.image_generation == 0 or
            payload.hotspot_x < 0 or payload.hotspot_y < 0)
            return Error.InvalidMessage;
    } else {
        if (payload.image_id != 0 or payload.image_generation != 0 or
            payload.hotspot_x != 0 or payload.hotspot_y != 0)
            return Error.InvalidMessage;
    }
}

pub fn encodeFrameIcon(
    a: std.mem.Allocator,
    payload: FrameIconPayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameIcon(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    var word: [4]u8 = undefined;
    inline for (.{ payload.image_id, payload.image_generation, @as(u32, @bitCast(payload.hotspot_x)), @as(u32, @bitCast(payload.hotspot_y)), payload.frame_generation, payload.reserved_tail }) |value| {
        std.mem.writeInt(u32, &word, value, .little);
        try out.appendSlice(a, &word);
    }
}

pub fn decodeFrameIcon(data: []const u8) Error!FrameIconPayload {
    if (data.len != 28) return Error.InvalidTable;
    const payload = FrameIconPayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .image_id = std.mem.readInt(u32, data[4..8], .little),
        .image_generation = std.mem.readInt(u32, data[8..12], .little),
        .hotspot_x = @bitCast(std.mem.readInt(u32, data[12..16], .little)),
        .hotspot_y = @bitCast(std.mem.readInt(u32, data[16..20], .little)),
        .frame_generation = std.mem.readInt(u32, data[20..24], .little),
        .reserved_tail = std.mem.readInt(u32, data[24..28], .little),
    };
    try validateFrameIcon(payload);
    return payload;
}

pub fn validateFrameIconEnvelope(payload: FrameIconPayload, envelope: Envelope) Error!void {
    try validateFrameIcon(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

fn validateFrameSizeHints(payload: FrameSizeHintsPayload) Error!void {
    if (payload.schema != 1 or payload.reserved != 0 or
        payload.flags & ~FrameSizeHintFlags.known != 0)
        return Error.InvalidMessage;
    if (payload.frame_generation == 0) return Error.InvalidMessage;

    const has_min = payload.flags & FrameSizeHintFlags.min_size != 0;
    const has_max = payload.flags & FrameSizeHintFlags.max_size != 0;
    const has_increment = payload.flags & FrameSizeHintFlags.size_increment != 0;
    const has_aspect = payload.flags & FrameSizeHintFlags.aspect_ratio != 0;
    const fits_platform_dimension = struct {
        fn check(value: u32) bool {
            return value <= std.math.maxInt(i32);
        }
    }.check;
    if (!fits_platform_dimension(payload.min_width) or
        !fits_platform_dimension(payload.min_height) or
        !fits_platform_dimension(payload.max_width) or
        !fits_platform_dimension(payload.max_height) or
        !fits_platform_dimension(payload.width_increment) or
        !fits_platform_dimension(payload.height_increment))
        return Error.InvalidMessage;
    if ((has_min and (payload.min_width == 0 or payload.min_height == 0)) or
        (!has_min and (payload.min_width != 0 or payload.min_height != 0)))
        return Error.InvalidMessage;
    if ((has_max and (payload.max_width == 0 or payload.max_height == 0)) or
        (!has_max and (payload.max_width != 0 or payload.max_height != 0)))
        return Error.InvalidMessage;
    if (has_min and has_max and (payload.max_width < payload.min_width or
        payload.max_height < payload.min_height)) return Error.InvalidMessage;

    const increment_present = payload.width_increment != 0 or payload.height_increment != 0;
    if (has_increment != increment_present or
        (has_increment and (payload.width_increment == 0 or payload.height_increment == 0)))
        return Error.InvalidMessage;

    if (has_aspect) {
        if (payload.aspect_min_numerator == 0 or payload.aspect_min_denominator == 0 or
            payload.aspect_max_numerator == 0 or payload.aspect_max_denominator == 0 or
            @as(u128, payload.aspect_min_numerator) * payload.aspect_max_denominator >
                @as(u128, payload.aspect_max_numerator) * payload.aspect_min_denominator)
            return Error.InvalidMessage;
    } else if (payload.aspect_min_numerator != 0 or payload.aspect_min_denominator != 0 or
        payload.aspect_max_numerator != 0 or payload.aspect_max_denominator != 0)
        return Error.InvalidMessage;
}

pub fn encodeFrameSizeHints(
    a: std.mem.Allocator,
    payload: FrameSizeHintsPayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameSizeHints(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    var word: [4]u8 = undefined;
    inline for (.{ payload.frame_generation, payload.min_width, payload.min_height, payload.max_width, payload.max_height, payload.width_increment, payload.height_increment, payload.aspect_min_numerator, payload.aspect_min_denominator, payload.aspect_max_numerator, payload.aspect_max_denominator }) |value| {
        std.mem.writeInt(u32, &word, value, .little);
        try out.appendSlice(a, &word);
    }
}

pub fn decodeFrameSizeHints(data: []const u8) Error!FrameSizeHintsPayload {
    if (data.len != 48) return Error.InvalidTable;
    var offset: usize = 4;
    var values: [11]u32 = undefined;
    inline for (&values) |*value| {
        value.* = std.mem.readInt(u32, data[offset..][0..4], .little);
        offset += 4;
    }
    const payload = FrameSizeHintsPayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .frame_generation = values[0],
        .min_width = values[1],
        .min_height = values[2],
        .max_width = values[3],
        .max_height = values[4],
        .width_increment = values[5],
        .height_increment = values[6],
        .aspect_min_numerator = values[7],
        .aspect_min_denominator = values[8],
        .aspect_max_numerator = values[9],
        .aspect_max_denominator = values[10],
    };
    try validateFrameSizeHints(payload);
    return payload;
}

pub fn validateFrameSizeHintsEnvelope(payload: FrameSizeHintsPayload, envelope: Envelope) Error!void {
    try validateFrameSizeHints(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

fn validateFrameZOrder(payload: FrameZOrderPayload) Error!void {
    if (payload.schema != 1 or payload.flags != 0 or payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_after_operation, 0) or
        payload.reserved_tail != 0) return Error.InvalidMessage;
    if (payload.frame_generation == 0) return Error.InvalidMessage;
    const needs_relative = payload.operation == .above or payload.operation == .below;
    const has_relative = payload.relative_frame_id != 0 and payload.relative_frame_generation != 0;
    if (needs_relative != has_relative) return Error.InvalidMessage;
}

pub fn encodeFrameZOrder(
    a: std.mem.Allocator,
    payload: FrameZOrderPayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameZOrder(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    try out.append(a, @intFromEnum(payload.operation));
    try out.appendSlice(a, &payload.reserved_after_operation);
    var word: [4]u8 = undefined;
    std.mem.writeInt(u32, &word, payload.frame_generation, .little);
    try out.appendSlice(a, &word);
    std.mem.writeInt(u32, &word, payload.relative_frame_id, .little);
    try out.appendSlice(a, &word);
    std.mem.writeInt(u32, &word, payload.relative_frame_generation, .little);
    try out.appendSlice(a, &word);
    std.mem.writeInt(u32, &word, payload.reserved_tail, .little);
    try out.appendSlice(a, &word);
}

pub fn decodeFrameZOrder(data: []const u8) Error!FrameZOrderPayload {
    if (data.len != 24) return Error.InvalidTable;
    const payload = FrameZOrderPayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .operation = switch (data[4]) {
            1 => .raise,
            2 => .lower,
            3 => .top,
            4 => .bottom,
            5 => .above,
            6 => .below,
            else => return Error.InvalidMessage,
        },
        .reserved_after_operation = data[5..8][0..3].*,
        .frame_generation = std.mem.readInt(u32, data[8..12], .little),
        .relative_frame_id = std.mem.readInt(u32, data[12..16], .little),
        .relative_frame_generation = std.mem.readInt(u32, data[16..20], .little),
        .reserved_tail = std.mem.readInt(u32, data[20..24], .little),
    };
    try validateFrameZOrder(payload);
    return payload;
}

pub fn validateFrameZOrderEnvelope(payload: FrameZOrderPayload, envelope: Envelope) Error!void {
    try validateFrameZOrder(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

fn validateFrameParent(payload: FrameParentPayload) Error!void {
    if (payload.schema != 1 or payload.reserved != 0 or
        payload.flags & ~FrameParentFlags.known != 0 or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0)) return Error.InvalidMessage;
    if (payload.child_frame_generation == 0) return Error.InvalidMessage;

    const has_parent = payload.flags & FrameParentFlags.present != 0;
    const modal = payload.flags & FrameParentFlags.modal != 0;
    const parent_values_present = payload.parent_frame_id != 0 and
        payload.parent_frame_generation != 0;
    const parent_values_absent = payload.parent_frame_id == 0 and
        payload.parent_frame_generation == 0;
    if (has_parent and !parent_values_present) return Error.InvalidMessage;
    if (!has_parent and !parent_values_absent) return Error.InvalidMessage;
    if (modal and !has_parent) return Error.InvalidMessage;
}

pub fn encodeFrameParent(
    a: std.mem.Allocator,
    payload: FrameParentPayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameParent(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    var word: [4]u8 = undefined;
    inline for (.{ payload.parent_frame_id, payload.parent_frame_generation, payload.child_frame_generation }) |value| {
        std.mem.writeInt(u32, &word, value, .little);
        try out.appendSlice(a, &word);
    }
    try out.appendSlice(a, &payload.reserved_tail);
}

pub fn decodeFrameParent(data: []const u8) Error!FrameParentPayload {
    if (data.len != 24) return Error.InvalidTable;
    const payload = FrameParentPayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .parent_frame_id = std.mem.readInt(u32, data[4..8], .little),
        .parent_frame_generation = std.mem.readInt(u32, data[8..12], .little),
        .child_frame_generation = std.mem.readInt(u32, data[12..16], .little),
        .reserved_tail = data[16..24][0..8].*,
    };
    try validateFrameParent(payload);
    return payload;
}

pub fn validateFrameParentEnvelope(payload: FrameParentPayload, envelope: Envelope) Error!void {
    try validateFrameParent(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

fn validateFrameFlush(payload: FrameFlushPayload) Error!void {
    if (payload.schema != 1 or payload.flags & ~@as(u8, FrameFlushFlags.known) != 0 or
        payload.reserved != 0 or !std.mem.allEqual(u8, &payload.reserved_tail, 0))
        return Error.InvalidMessage;
    if (payload.frame_generation == 0 or payload.redisplay_generation == 0 or
        payload.frame_sequence == 0)
        return Error.InvalidMessage;
}

pub fn encodeFrameFlush(
    a: std.mem.Allocator,
    payload: FrameFlushPayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateFrameFlush(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    var word: [4]u8 = undefined;
    std.mem.writeInt(u32, &word, payload.frame_generation, .little);
    try out.appendSlice(a, &word);
    var long: [8]u8 = undefined;
    inline for (.{ payload.redisplay_generation, payload.frame_sequence, payload.deadline_ns }) |value| {
        std.mem.writeInt(u64, &long, value, .little);
        try out.appendSlice(a, &long);
    }
    try out.append(a, @intFromEnum(payload.damage_kind));
    try out.appendSlice(a, &payload.reserved_tail);
}

pub fn decodeFrameFlush(data: []const u8) Error!FrameFlushPayload {
    if (data.len != 40) return Error.InvalidTable;
    const payload = FrameFlushPayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .frame_generation = std.mem.readInt(u32, data[4..8], .little),
        .redisplay_generation = std.mem.readInt(u64, data[8..16], .little),
        .frame_sequence = std.mem.readInt(u64, data[16..24], .little),
        .deadline_ns = std.mem.readInt(u64, data[24..32], .little),
        .damage_kind = switch (data[32]) {
            0 => .none,
            1 => .partial,
            2 => .full,
            3 => .state_only,
            4 => .resource_only,
            else => return Error.InvalidMessage,
        },
        .reserved_tail = data[33..40][0..7].*,
    };
    try validateFrameFlush(payload);
    return payload;
}

pub fn validateFrameFlushEnvelope(payload: FrameFlushPayload, envelope: Envelope) Error!void {
    try validateFrameFlush(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

pub fn validateRenderHint(payload: RenderHintPayload) Error!void {
    if (payload.schema != 1 or payload.flags & ~@as(u8, RenderHintFlags.known) != 0 or
        payload.reserved != 0 or
        !std.mem.allEqual(u8, &payload.reserved_after_workload, 0) or
        !std.mem.allEqual(u8, &payload.reserved_tail, 0))
        return Error.InvalidMessage;
    if (payload.frame_generation == 0) return Error.InvalidMessage;
    if ((payload.flags & RenderHintFlags.deadline_present != 0) != (payload.deadline_ns != 0) or
        (payload.flags & RenderHintFlags.refresh_interval_present != 0) !=
            (payload.refresh_interval_ns != 0))
        return Error.InvalidMessage;
}

pub fn encodeRenderHint(
    a: std.mem.Allocator,
    payload: RenderHintPayload,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateRenderHint(payload);
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, payload.schema, .little);
    try out.appendSlice(a, &bytes);
    try out.append(a, payload.flags);
    try out.append(a, payload.reserved);
    try out.append(a, @intFromEnum(payload.preferred_mode));
    try out.append(a, @intFromEnum(payload.workload));
    try out.appendSlice(a, &payload.reserved_after_workload);
    var word: [4]u8 = undefined;
    std.mem.writeInt(u32, &word, payload.frame_generation, .little);
    try out.appendSlice(a, &word);
    var long: [8]u8 = undefined;
    inline for (.{ payload.refresh_interval_ns, payload.deadline_ns }) |value| {
        std.mem.writeInt(u64, &long, value, .little);
        try out.appendSlice(a, &long);
    }
    try out.appendSlice(a, &payload.reserved_tail);
}

pub fn decodeRenderHint(data: []const u8) Error!RenderHintPayload {
    if (data.len != 32) return Error.InvalidTable;
    const payload = RenderHintPayload{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .flags = data[2],
        .reserved = data[3],
        .preferred_mode = switch (data[4]) {
            0 => .auto,
            1 => .vsync,
            2 => .adaptive_vsync,
            3 => .mailbox,
            4 => .immediate,
            else => return Error.InvalidMessage,
        },
        .workload = switch (data[5]) {
            0 => .unspecified,
            1 => .typing,
            2 => .scroll,
            3 => .animation,
            4 => .resize,
            5 => .idle,
            else => return Error.InvalidMessage,
        },
        .reserved_after_workload = data[6..8][0..2].*,
        .frame_generation = std.mem.readInt(u32, data[8..12], .little),
        .refresh_interval_ns = std.mem.readInt(u64, data[12..20], .little),
        .deadline_ns = std.mem.readInt(u64, data[20..28], .little),
        .reserved_tail = data[28..32][0..4].*,
    };
    try validateRenderHint(payload);
    return payload;
}

pub fn validateRenderHintEnvelope(payload: RenderHintPayload, envelope: Envelope) Error!void {
    try validateRenderHint(payload);
    if (envelope.frame_id == 0) return Error.InvalidMessage;
}

pub const WindowCreate = struct {
    frame_id: u32,
    frame_generation: u32,
    node: WindowTreeNode,
};

pub const window_create_size: usize = 12 + window_tree_node_size;

fn validateWindowCreate(create: WindowCreate) Error!void {
    if (create.frame_id == 0 or create.frame_generation == 0) return Error.InvalidMessage;
    if (create.node.window_id == 0 or create.node.width <= 0 or create.node.height <= 0 or
        create.node.x < 0 or create.node.y < 0 or !create.node.visible())
        return Error.InvalidMessage;
    if (create.node.depth > max_window_tree_depth or
        create.node.flags & ~@as(u32, 3) != 0)
        return Error.InvalidMessage;
}

pub fn encodeWindowCreate(
    a: std.mem.Allocator,
    create: WindowCreate,
    out: *std.ArrayList(u8),
) (Error || std.mem.Allocator.Error)!void {
    try validateWindowCreate(create);
    var header: [12]u8 = [_]u8{0} ** 12;
    std.mem.writeInt(u16, header[0..2], window_tree_schema, .little);
    std.mem.writeInt(u32, header[4..8], create.frame_id, .little);
    std.mem.writeInt(u32, header[8..12], create.frame_generation, .little);
    try out.appendSlice(a, &header);
    var node_bytes: [window_tree_node_size]u8 = [_]u8{0} ** window_tree_node_size;
    std.mem.writeInt(u64, node_bytes[0..8], create.node.window_id, .little);
    std.mem.writeInt(u64, node_bytes[8..16], create.node.parent_window_id, .little);
    std.mem.writeInt(u32, node_bytes[16..20], @bitCast(create.node.x), .little);
    std.mem.writeInt(u32, node_bytes[20..24], @bitCast(create.node.y), .little);
    std.mem.writeInt(u32, node_bytes[24..28], @bitCast(create.node.width), .little);
    std.mem.writeInt(u32, node_bytes[28..32], @bitCast(create.node.height), .little);
    std.mem.writeInt(u32, node_bytes[32..36], create.node.flags, .little);
    std.mem.writeInt(u32, node_bytes[36..40], create.node.default_face_id, .little);
    node_bytes[40] = create.node.depth;
    try out.appendSlice(a, &node_bytes);
}

pub fn decodeWindowCreate(data: []const u8) Error!WindowCreate {
    if (data.len != window_create_size) return Error.InvalidTable;
    var reader = Reader{ .data = data };
    if (try reader.readU16() != window_tree_schema) return Error.InvalidTable;
    try reader.expectZeros(2);
    const frame_id = try reader.readU32();
    const frame_generation = try reader.readU32();
    const node = WindowTreeNode{
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
    const create: WindowCreate = .{ .frame_id = frame_id, .frame_generation = frame_generation, .node = node };
    try validateWindowCreate(create);
    return create;
}

pub const WindowDelete = struct {
    frame_id: u32,
    frame_generation: u32,
    window_id: u64,
};

pub const window_delete_size: usize = 20;

fn validateWindowDelete(delete: WindowDelete) Error!void {
    if (delete.frame_id == 0 or delete.frame_generation == 0 or delete.window_id == 0)
        return Error.InvalidMessage;
}

pub fn encodeWindowDelete(a: std.mem.Allocator, delete: WindowDelete, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateWindowDelete(delete);
    var bytes: [window_delete_size]u8 = [_]u8{0} ** window_delete_size;
    std.mem.writeInt(u16, bytes[0..2], window_tree_schema, .little);
    std.mem.writeInt(u32, bytes[4..8], delete.frame_id, .little);
    std.mem.writeInt(u32, bytes[8..12], delete.frame_generation, .little);
    std.mem.writeInt(u64, bytes[12..20], delete.window_id, .little);
    try out.appendSlice(a, &bytes);
}

pub fn decodeWindowDelete(data: []const u8) Error!WindowDelete {
    if (data.len != window_delete_size) return Error.InvalidTable;
    var reader = Reader{ .data = data };
    if (try reader.readU16() != window_tree_schema) return Error.InvalidTable;
    try reader.expectZeros(2);
    const delete: WindowDelete = .{
        .frame_id = try reader.readU32(),
        .frame_generation = try reader.readU32(),
        .window_id = try reader.readU64(),
    };
    try validateWindowDelete(delete);
    return delete;
}

pub const WindowPatchFlags = struct {
    pub const x: u32 = 1 << 0;
    pub const y: u32 = 1 << 1;
    pub const width: u32 = 1 << 2;
    pub const height: u32 = 1 << 3;
    pub const parent: u32 = 1 << 4;
    pub const visible: u32 = 1 << 5;
    pub const default_face: u32 = 1 << 6;
    pub const depth: u32 = 1 << 7;
    pub const known: u32 = x | y | width | height | parent | visible | default_face | depth;
};

pub const WindowPatch = struct {
    schema: u16 = 1,
    flags: u32,
    reserved: u32 = 0,
    frame_id: u32,
    frame_generation: u32,
    window_id: u64,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    parent_window_id: u64 = 0,
    default_face_id: u32 = 0,
    visible: bool = false,
    depth: u8 = 0,
};

pub const window_patch_size: usize = 56;

fn validateWindowPatch(payload: WindowPatch) Error!void {
    if (payload.schema != 1 or payload.reserved != 0 or
        payload.flags & ~WindowPatchFlags.known != 0 or payload.flags == 0)
        return Error.InvalidMessage;
    if (payload.frame_id == 0 or payload.frame_generation == 0 or payload.window_id == 0)
        return Error.InvalidMessage;
    if (payload.flags & WindowPatchFlags.x != 0 and payload.x < 0) return Error.InvalidMessage;
    if (payload.flags & WindowPatchFlags.y != 0 and payload.y < 0) return Error.InvalidMessage;
    if (payload.flags & WindowPatchFlags.width != 0 and payload.width <= 0) return Error.InvalidMessage;
    if (payload.flags & WindowPatchFlags.height != 0 and payload.height <= 0) return Error.InvalidMessage;
    if (payload.flags & WindowPatchFlags.parent != 0 and payload.parent_window_id == 0)
        return Error.InvalidMessage;
    if (payload.flags & WindowPatchFlags.default_face != 0 and payload.default_face_id == 0)
        return Error.InvalidMessage;
    if (payload.flags & WindowPatchFlags.depth != 0 and payload.depth > max_window_tree_depth)
        return Error.InvalidMessage;
    const geometry_present = payload.flags &
        (WindowPatchFlags.x | WindowPatchFlags.y |
            WindowPatchFlags.width | WindowPatchFlags.height) != 0;
    if (!geometry_present and (payload.x != 0 or payload.y != 0 or
        payload.width != 0 or payload.height != 0))
        return Error.InvalidMessage;
    if (payload.flags & WindowPatchFlags.parent == 0 and payload.parent_window_id != 0)
        return Error.InvalidMessage;
    if (payload.flags & WindowPatchFlags.default_face == 0 and payload.default_face_id != 0)
        return Error.InvalidMessage;
    if (payload.flags & WindowPatchFlags.visible == 0 and payload.visible)
        return Error.InvalidMessage;
    if (payload.flags & WindowPatchFlags.depth == 0 and payload.depth != 0)
        return Error.InvalidMessage;
}

pub fn encodeWindowPatch(a: std.mem.Allocator, payload: WindowPatch, out: *std.ArrayList(u8)) (Error || std.mem.Allocator.Error)!void {
    try validateWindowPatch(payload);
    var bytes: [window_patch_size]u8 = [_]u8{0} ** window_patch_size;
    std.mem.writeInt(u16, bytes[0..2], payload.schema, .little);
    std.mem.writeInt(u32, bytes[2..6], payload.flags, .little);
    std.mem.writeInt(u32, bytes[6..10], payload.reserved, .little);
    std.mem.writeInt(u32, bytes[10..14], payload.frame_id, .little);
    std.mem.writeInt(u32, bytes[14..18], payload.frame_generation, .little);
    std.mem.writeInt(u64, bytes[18..26], payload.window_id, .little);
    std.mem.writeInt(u32, bytes[26..30], @bitCast(payload.x), .little);
    std.mem.writeInt(u32, bytes[30..34], @bitCast(payload.y), .little);
    std.mem.writeInt(u32, bytes[34..38], @bitCast(payload.width), .little);
    std.mem.writeInt(u32, bytes[38..42], @bitCast(payload.height), .little);
    std.mem.writeInt(u64, bytes[42..50], payload.parent_window_id, .little);
    std.mem.writeInt(u32, bytes[50..54], payload.default_face_id, .little);
    bytes[54] = @intFromBool(payload.visible);
    bytes[55] = payload.depth;
    try out.appendSlice(a, &bytes);
}

pub fn decodeWindowPatch(data: []const u8) Error!WindowPatch {
    if (data.len != window_patch_size) return Error.InvalidTable;
    var reader = Reader{ .data = data };
    if (try reader.readU16() != window_tree_schema) return Error.InvalidTable;
    const flags = try reader.readU32();
    const reserved = try reader.readU32();
    const frame_id = try reader.readU32();
    const frame_generation = try reader.readU32();
    const window_id = try reader.readU64();
    const payload = WindowPatch{
        .flags = flags,
        .reserved = reserved,
        .frame_id = frame_id,
        .frame_generation = frame_generation,
        .window_id = window_id,
        .x = try reader.readI32(),
        .y = try reader.readI32(),
        .width = try reader.readI32(),
        .height = try reader.readI32(),
        .parent_window_id = try reader.readU64(),
        .default_face_id = try reader.readU32(),
        .visible = switch (try reader.readByte()) {
            0 => false,
            1 => true,
            else => return Error.InvalidMessage,
        },
        .depth = try reader.readByte(),
    };
    try validateWindowPatch(payload);
    return payload;
}

test "window lifecycle codecs have exact little-endian wire layout" {
    const a = std.testing.allocator;
    var wire: std.ArrayList(u8) = .empty;
    defer wire.deinit(a);
    const node: WindowTreeNode = .{
        .window_id = 0x0102030405060708,
        .parent_window_id = 9,
        .x = 2,
        .y = 3,
        .width = 40,
        .height = 20,
        .flags = window_tree_flag_visible,
        .default_face_id = 4,
        .depth = 1,
    };
    try encodeWindowCreate(a, .{ .frame_id = 7, .frame_generation = 2, .node = node }, &wire);
    try std.testing.expectEqual(window_create_size, wire.items.len);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, wire.items[0..2], .little));
    try std.testing.expectEqual(@as(u32, 7), std.mem.readInt(u32, wire.items[4..8], .little));
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, wire.items[8..12], .little));
    const created = try decodeWindowCreate(wire.items);
    try std.testing.expectEqual(node.window_id, created.node.window_id);
    try std.testing.expectEqual(@as(u64, 9), created.node.parent_window_id);
    try std.testing.expectEqual(@as(i32, 2), created.node.x);

    wire.items[2] = 1;
    try std.testing.expectError(Error.InvalidEnvelope, decodeWindowCreate(wire.items));
    wire.items[2] = 0;
    wire.items[12 + window_tree_node_size - 1] = 1;
    try std.testing.expectError(Error.InvalidEnvelope, decodeWindowCreate(wire.items));
    wire.items[12 + window_tree_node_size - 1] = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeWindowCreate(a, .{ .frame_id = 0, .frame_generation = 2, .node = node }, &wire));
    try std.testing.expectError(Error.InvalidMessage, encodeWindowCreate(a, .{ .frame_id = 7, .frame_generation = 0, .node = node }, &wire));
    try std.testing.expectError(Error.InvalidMessage, encodeWindowCreate(a, .{
        .frame_id = 7,
        .frame_generation = 2,
        .node = .{ .window_id = 0, .parent_window_id = 0, .x = 0, .y = 0, .width = 1, .height = 1, .flags = window_tree_flag_visible, .default_face_id = 0, .depth = 0 },
    }, &wire));

    wire.clearRetainingCapacity();
    try encodeWindowDelete(a, .{ .frame_id = 7, .frame_generation = 2, .window_id = node.window_id }, &wire);
    try std.testing.expectEqual(window_delete_size, wire.items.len);
    try std.testing.expectEqual(@as(u64, node.window_id), std.mem.readInt(u64, wire.items[12..20], .little));
    const deleted = try decodeWindowDelete(wire.items);
    try std.testing.expectEqual(node.window_id, deleted.window_id);
    wire.items[3] = 1;
    try std.testing.expectError(Error.InvalidEnvelope, decodeWindowDelete(wire.items));
    wire.items[3] = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeWindowDelete(a, .{ .frame_id = 7, .frame_generation = 0, .window_id = node.window_id }, &wire));
    try std.testing.expectError(Error.InvalidMessage, encodeWindowDelete(a, .{ .frame_id = 7, .frame_generation = 2, .window_id = 0 }, &wire));
}

test "window patch has exact canonical little-endian wire layout" {
    const a = std.testing.allocator;
    var wire: std.ArrayList(u8) = .empty;
    defer wire.deinit(a);
    const f = WindowPatchFlags;
    const payload: WindowPatch = .{
        .flags = f.known,
        .frame_id = 7,
        .frame_generation = 2,
        .window_id = 0x0102030405060708,
        .x = 1,
        .y = 2,
        .width = 30,
        .height = 20,
        .parent_window_id = 901,
        .default_face_id = 4,
        .visible = true,
        .depth = 2,
    };
    try encodeWindowPatch(a, payload, &wire);
    try std.testing.expectEqual(window_patch_size, wire.items.len);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, wire.items[0..2], .little));
    try std.testing.expectEqual(f.known, std.mem.readInt(u32, wire.items[2..6], .little));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, wire.items[6..10], .little));
    try std.testing.expectEqual(payload.frame_id, std.mem.readInt(u32, wire.items[10..14], .little));
    try std.testing.expectEqual(payload.frame_generation, std.mem.readInt(u32, wire.items[14..18], .little));
    try std.testing.expectEqual(payload.window_id, std.mem.readInt(u64, wire.items[18..26], .little));
    try std.testing.expectEqual(payload.x, std.mem.readInt(i32, wire.items[26..30], .little));
    try std.testing.expectEqual(payload.y, std.mem.readInt(i32, wire.items[30..34], .little));
    try std.testing.expectEqual(payload.width, std.mem.readInt(i32, wire.items[34..38], .little));
    try std.testing.expectEqual(payload.height, std.mem.readInt(i32, wire.items[38..42], .little));
    try std.testing.expectEqual(payload.parent_window_id, std.mem.readInt(u64, wire.items[42..50], .little));
    try std.testing.expectEqual(payload.default_face_id, std.mem.readInt(u32, wire.items[50..54], .little));
    try std.testing.expectEqual(@as(u8, 1), wire.items[54]);
    try std.testing.expectEqual(payload.depth, wire.items[55]);
    try std.testing.expectEqual(payload, try decodeWindowPatch(wire.items));

    wire.items[3] = 1; // unknown presence bit
    try std.testing.expectError(Error.InvalidMessage, decodeWindowPatch(wire.items));
    wire.items[3] = 0;
    wire.items[6] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeWindowPatch(wire.items));
    wire.items[6] = 0;
    wire.items[54] = 2;
    try std.testing.expectError(Error.InvalidMessage, decodeWindowPatch(wire.items));

    wire.clearRetainingCapacity();
    var sparse = payload;
    sparse.flags = f.visible;
    sparse.x = 0;
    sparse.y = 0;
    sparse.width = 0;
    sparse.height = 0;
    sparse.parent_window_id = 0;
    sparse.default_face_id = 0;
    sparse.visible = false;
    sparse.depth = 0;
    try encodeWindowPatch(a, sparse, &wire);
    try std.testing.expectEqual(@as(u8, 0), wire.items[54]);
    try std.testing.expectEqual(sparse, try decodeWindowPatch(wire.items));
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

test "frame patch payload enforces bounded atomic presence" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    const patch: FramePatch = .{
        .presence = FramePatchFlags.visibility | FramePatchFlags.focus |
            FramePatchFlags.alpha | FramePatchFlags.decorations |
            FramePatchFlags.scale,
        .frame_generation = 2,
        .visibility = .visible,
        .focused = true,
        .decorated = false,
        .active_opacity = 9000,
        .inactive_opacity = 7000,
        .background_opacity = 9500,
        .scale = 1.25,
        .dpi_x = 96,
        .dpi_y = 120,
    };
    try encodeFramePatch(a, patch, &bytes);
    try std.testing.expectEqual(frame_patch_size, bytes.items.len);
    try std.testing.expectEqual(patch, try decodeFramePatch(bytes.items));

    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFramePatch(bytes.items));
    bytes.items[3] = 0;
    bytes.items[11] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFramePatch(bytes.items));
    bytes.items[11] = 0;
    std.mem.writeInt(u16, bytes.items[2..4], FramePatchFlags.visibility, .little);
    bytes.items[8] = @intFromEnum(FrameVisibilityState.hidden);
    bytes.items[9] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFramePatch(bytes.items));
    bytes.items[9] = 0;
    bytes.items[8] = 3;
    try std.testing.expectError(Error.InvalidTable, decodeFramePatch(bytes.items));
    bytes.items[8] = @intFromEnum(FrameVisibilityState.visible);
    bytes.items[9] = 1;
    bytes.items[10] = 2;
    try std.testing.expectError(Error.InvalidBoolean, decodeFramePatch(bytes.items));
    bytes.items[10] = 0;
    bytes.items[39] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFramePatch(bytes.items));
    std.mem.writeInt(u16, bytes.items[2..4], FramePatchFlags.known, .little);
    bytes.items[39] = 0;
    try std.testing.expectEqual(patch, try decodeFramePatch(bytes.items));
    std.mem.writeInt(u16, bytes.items[2..4], 0, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFramePatch(bytes.items));
    try std.testing.expectError(Error.InvalidTable, decodeFramePatch(bytes.items[0 .. bytes.items.len - 1]));
}

fn validFrameSnapshot() FrameSnapshot {
    return .{
        .frame_generation = 2,
        .visibility = .visible,
        .focused = true,
        .fullscreen = .none,
        .maximize_flags = FrameMaximizeFlags.both,
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
}

test "frame snapshot enforces complete bounded core presentation state" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    const snapshot = validFrameSnapshot();
    try encodeFrameSnapshot(a, snapshot, &bytes);
    try std.testing.expectEqual(frame_snapshot_size, bytes.items.len);
    try std.testing.expectEqual(snapshot, try decodeFrameSnapshot(bytes.items));

    var invalid = snapshot;
    invalid.frame_generation = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSnapshot(a, invalid, &bytes));
    invalid = snapshot;
    invalid.active_opacity = max_opacity + 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSnapshot(a, invalid, &bytes));
    invalid = snapshot;
    invalid.inactive_opacity = max_opacity + 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSnapshot(a, invalid, &bytes));
    invalid = snapshot;
    invalid.background_opacity = max_opacity + 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSnapshot(a, invalid, &bytes));
    invalid = snapshot;
    invalid.scale = max_frame_scale + 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSnapshot(a, invalid, &bytes));
    invalid = snapshot;
    invalid.dpi_x = max_frame_dpi + 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSnapshot(a, invalid, &bytes));
    invalid = snapshot;
    invalid.dpi_y = max_frame_dpi + 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSnapshot(a, invalid, &bytes));
    invalid = snapshot;
    invalid.body = .{ .x = 200, .y = 8, .width = 8, .height = 8 };
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSnapshot(a, invalid, &bytes));

    bytes.items[6] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameSnapshot(bytes.items));
    bytes.items[6] = 0;
    bytes.items[12] = 3;
    try std.testing.expectError(Error.InvalidTable, decodeFrameSnapshot(bytes.items));
    bytes.items[12] = @intFromEnum(FrameVisibilityState.visible);
    bytes.items[13] = 2;
    try std.testing.expectError(Error.InvalidBoolean, decodeFrameSnapshot(bytes.items));
    bytes.items[13] = 1;
    bytes.items[14] = 5;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameSnapshot(bytes.items));
    bytes.items[14] = 0;
    bytes.items[15] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameSnapshot(bytes.items));
    bytes.items[15] = FrameMaximizeFlags.horizontal;
    try std.testing.expectEqual(FrameMaximizeFlags.horizontal, (try decodeFrameSnapshot(bytes.items)).maximize_flags);
    bytes.items[15] = FrameMaximizeFlags.vertical;
    try std.testing.expectEqual(FrameMaximizeFlags.vertical, (try decodeFrameSnapshot(bytes.items)).maximize_flags);
    bytes.items[15] = FrameMaximizeFlags.both;
    bytes.items[15] = ~FrameMaximizeFlags.both;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameSnapshot(bytes.items));
    bytes.items[15] = FrameMaximizeFlags.both;
    bytes.items[16] = 2;
    try std.testing.expectError(Error.InvalidBoolean, decodeFrameSnapshot(bytes.items));
    bytes.items[16] = 0;
    bytes.items[17] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameSnapshot(bytes.items));
    bytes.items[17] = 0;
    bytes.items[127] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameSnapshot(bytes.items));
    bytes.items[127] = 0;
    std.mem.writeInt(u32, bytes.items[4..8], FrameSnapshotFlags.all & ~FrameSnapshotFlags.geometry, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFrameSnapshot(bytes.items));
    std.mem.writeInt(u32, bytes.items[4..8], FrameSnapshotFlags.all, .little);
    bytes.items[13] = 1;
    bytes.items[12] = @intFromEnum(FrameVisibilityState.hidden);
    try std.testing.expectError(Error.InvalidMessage, decodeFrameSnapshot(bytes.items));
    try std.testing.expectError(Error.InvalidTable, decodeFrameSnapshot(bytes.items[0 .. bytes.items.len - 1]));
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

test "frame alpha payload enforces strict wire form" {
    const a = std.testing.allocator;
    const payload = FrameAlphaPayload{
        .active_opacity = 8000,
        .inactive_opacity = 6000,
        .background_opacity = 9000,
        .frame_generation = 2,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameAlpha(a, payload, &bytes);
    try std.testing.expectEqual(@as(usize, 20), bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFrameAlpha(bytes.items));

    bytes.items[0] = 2;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameAlpha(bytes.items));
    bytes.items[0] = 1;
    bytes.items[2] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameAlpha(bytes.items));
    bytes.items[2] = 0;
    bytes.items[8] = 0x11;
    bytes.items[9] = 0x27;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameAlpha(bytes.items));
    bytes.items[8] = 0x28;
    bytes.items[9] = 0x23;
    std.mem.writeInt(u16, bytes.items[10..12], 1, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFrameAlpha(bytes.items));
    std.mem.writeInt(u16, bytes.items[10..12], 0, .little);
    std.mem.writeInt(u32, bytes.items[16..20], 1, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFrameAlpha(bytes.items));
    std.mem.writeInt(u32, bytes.items[16..20], 0, .little);
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFrameAlpha(bytes.items));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameAlpha(a, .{
        .active_opacity = 0,
        .inactive_opacity = 0,
        .background_opacity = 0,
        .frame_generation = 0,
    }, &bytes));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameAlpha(a, .{
        .active_opacity = max_opacity + 1,
        .inactive_opacity = max_opacity,
        .background_opacity = max_opacity,
        .frame_generation = 1,
    }, &bytes));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameAlpha(a, .{
        .active_opacity = max_opacity,
        .inactive_opacity = max_opacity + 1,
        .background_opacity = max_opacity,
        .frame_generation = 1,
    }, &bytes));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameAlpha(a, .{
        .active_opacity = max_opacity,
        .inactive_opacity = max_opacity,
        .background_opacity = max_opacity + 1,
        .frame_generation = 1,
    }, &bytes));
}

test "frame decorations payload enforces strict wire form" {
    const a = std.testing.allocator;
    const payload = FrameDecorationsPayload{ .decorated = false, .frame_generation = 2 };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameDecorations(a, payload, &bytes);
    try std.testing.expectEqual(@as(usize, 12), bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFrameDecorations(bytes.items));

    bytes.items[0] = 2;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameDecorations(bytes.items));
    bytes.items[0] = 1;
    bytes.items[2] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameDecorations(bytes.items));
    bytes.items[2] = 0;
    bytes.items[4] = 2;
    try std.testing.expectError(Error.InvalidBoolean, decodeFrameDecorations(bytes.items));
    bytes.items[4] = 0;
    bytes.items[5] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameDecorations(bytes.items));
    bytes.items[5] = 0;
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFrameDecorations(bytes.items));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameDecorations(a, .{
        .decorated = true,
        .frame_generation = 0,
    }, &bytes));
}

test "frame scale payload enforces strict wire form" {
    const a = std.testing.allocator;
    const payload = FrameScalePayload{
        .scale = 1.5,
        .dpi_x = 96,
        .dpi_y = 192,
        .frame_generation = 2,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameScale(a, payload, &bytes);
    try std.testing.expectEqual(@as(usize, 24), bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFrameScale(bytes.items));

    bytes.items[0] = 2;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameScale(bytes.items));
    bytes.items[0] = 1;
    bytes.items[2] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameScale(bytes.items));
    bytes.items[2] = 0;
    std.mem.writeInt(u32, bytes.items[4..8], 0, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFrameScale(bytes.items));
    std.mem.writeInt(u32, bytes.items[4..8], 0x7fc0_0000, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFrameScale(bytes.items));
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFrameScale(bytes.items));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameScale(a, .{
        .scale = 1,
        .dpi_x = 96,
        .dpi_y = 96,
        .frame_generation = 0,
    }, &bytes));
}

test "frame fullscreen payload enforces strict wire form" {
    const a = std.testing.allocator;
    const payload = FrameFullscreenPayload{ .mode = .fullboth, .frame_generation = 2 };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameFullscreen(a, payload, &bytes);
    try std.testing.expectEqual(@as(usize, 12), bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFrameFullscreen(bytes.items));

    bytes.items[0] = 2;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameFullscreen(bytes.items));
    bytes.items[0] = 1;
    bytes.items[2] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameFullscreen(bytes.items));
    bytes.items[2] = 0;
    bytes.items[4] = 5;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameFullscreen(bytes.items));
    for ([_]FrameFullscreenMode{ .none, .fullboth, .fullwidth, .fullheight, .maximized }) |mode| {
        bytes.items[4] = @intFromEnum(mode);
        try std.testing.expectEqual(mode, (try decodeFrameFullscreen(bytes.items)).mode);
    }
    bytes.items[4] = 1;
    bytes.items[5] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameFullscreen(bytes.items));
    bytes.items[5] = 0;
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFrameFullscreen(bytes.items));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameFullscreen(a, .{
        .mode = .none,
        .frame_generation = 0,
    }, &bytes));
}

test "frame monitor payload enforces strict wire form" {
    const a = std.testing.allocator;
    const payload = FrameMonitorPayload{
        .flags = FrameMonitorFlags.primary,
        .monitor_id = 30,
        .x = -10,
        .y = 0,
        .width = 1920,
        .height = 1080,
        .frame_generation = 2,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameMonitor(a, payload, &bytes);
    try std.testing.expectEqual(@as(usize, 32), bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFrameMonitor(bytes.items));

    bytes.items[0] = 2;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameMonitor(bytes.items));
    bytes.items[0] = 1;
    bytes.items[2] = FrameMonitorFlags.primary | 2;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameMonitor(bytes.items));
    bytes.items[2] = FrameMonitorFlags.primary;
    std.mem.writeInt(u32, bytes.items[16..20], 0, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFrameMonitor(bytes.items));
    std.mem.writeInt(u32, bytes.items[16..20], 1920, .little);
    std.mem.writeInt(u32, bytes.items[28..32], 1, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFrameMonitor(bytes.items));
    std.mem.writeInt(u32, bytes.items[28..32], 0, .little);
    std.mem.writeInt(u32, bytes.items[8..12], @bitCast(@as(i32, std.math.minInt(i32))), .little);
    std.mem.writeInt(u32, bytes.items[16..20], @bitCast(@as(i32, std.math.maxInt(i32))), .little);
    try std.testing.expectEqual(@as(i32, std.math.minInt(i32)), (try decodeFrameMonitor(bytes.items)).x);
    try std.testing.expectEqual(@as(i32, std.math.maxInt(i32)), (try decodeFrameMonitor(bytes.items)).width);
    std.mem.writeInt(u32, bytes.items[8..12], @bitCast(@as(i32, std.math.maxInt(i32))), .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFrameMonitor(bytes.items));
    std.mem.writeInt(u32, bytes.items[8..12], @bitCast(@as(i32, 0)), .little);
    std.mem.writeInt(u32, bytes.items[8..12], @bitCast(@as(i32, 0)), .little);
    std.mem.writeInt(u32, bytes.items[16..20], 1920, .little);
    try std.testing.expectError(Error.InvalidMessage, encodeFrameMonitor(a, .{
        .monitor_id = 1,
        .x = 0,
        .y = 0,
        .width = 1,
        .height = 1,
        .frame_generation = 0,
    }, &bytes));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameMonitor(a, .{
        .monitor_id = 1,
        .x = 0,
        .y = 0,
        .width = 0,
        .height = 1,
        .frame_generation = 1,
    }, &bytes));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameMonitor(a, .{
        .monitor_id = 1,
        .x = 0,
        .y = 0,
        .width = 1,
        .height = -1,
        .frame_generation = 1,
    }, &bytes));
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFrameMonitor(bytes.items));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameMonitor(a, .{
        .monitor_id = 0,
        .x = 0,
        .y = 0,
        .width = 1,
        .height = 1,
        .frame_generation = 1,
    }, &bytes));
}

test "frame maximize payload enforces strict wire form" {
    const a = std.testing.allocator;
    const payload = FrameMaximizePayload{
        .flags = FrameMaximizeFlags.both,
        .frame_generation = 2,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameMaximize(a, payload, &bytes);
    try std.testing.expectEqual(@as(usize, 12), bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFrameMaximize(bytes.items));

    bytes.items[0] = 2;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameMaximize(bytes.items));
    bytes.items[0] = 1;
    bytes.items[2] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameMaximize(bytes.items));
    bytes.items[2] = 7;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameMaximize(bytes.items));
    bytes.items[2] = FrameMaximizeFlags.both;
    for ([_]usize{ 3, 4, 5, 6, 7 }) |reserved_index| {
        bytes.items[reserved_index] = 1;
        try std.testing.expectError(Error.InvalidMessage, decodeFrameMaximize(bytes.items));
        bytes.items[reserved_index] = 0;
    }
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFrameMaximize(bytes.items));
    try std.testing.expectError(Error.InvalidMessage, encodeFrameMaximize(a, .{
        .flags = FrameMaximizeFlags.horizontal,
        .frame_generation = 0,
    }, &bytes));
}

test "frame geometry payload enforces nested rectangles" {
    const a = std.testing.allocator;
    const payload = FrameGeometryPayload{
        .frame_generation = 2,
        .outer = .{ .x = 0, .y = 0, .width = 260, .height = 116 },
        .content = .{ .x = 10, .y = 10, .width = 240, .height = 96 },
        .text = .{ .x = 12, .y = 12, .width = 236, .height = 92 },
        .window = .{ .x = 12, .y = 12, .width = 236, .height = 92 },
        .body = .{ .x = 13, .y = 13, .width = 234, .height = 90 },
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameGeometry(a, payload, &bytes);
    try std.testing.expectEqual(@as(usize, 96), bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFrameGeometry(bytes.items));
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, bytes.items[0..2], .little));
    try std.testing.expectEqual(payload.frame_generation, std.mem.readInt(u32, bytes.items[4..8], .little));
    try std.testing.expectEqual(payload.content.x, @as(i32, @bitCast(std.mem.readInt(u32, bytes.items[24..28], .little))));
    try std.testing.expectEqual(payload.window.height, @as(i32, @bitCast(std.mem.readInt(u32, bytes.items[68..72], .little))));
    try std.testing.expect(std.mem.allEqual(u8, bytes.items[88..96], 0));

    bytes.items[0] = 2;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameGeometry(bytes.items));
    bytes.items[0] = 1;
    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameGeometry(bytes.items));
    bytes.items[3] = 0;
    bytes.items[90] = 1;
    try std.testing.expectError(Error.InvalidTable, decodeFrameGeometry(bytes.items));
    bytes.items[90] = 0;
    var invalid = payload;
    invalid.text.width = 300;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameGeometry(a, invalid, &bytes));
    invalid = payload;
    invalid.frame_generation = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameGeometry(a, invalid, &bytes));
    invalid = payload;
    invalid.body.width = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameGeometry(a, invalid, &bytes));
    invalid = payload;
    invalid.body.width = std.math.maxInt(i32);
    try std.testing.expectError(Error.InvalidMessage, encodeFrameGeometry(a, invalid, &bytes));
}

test "frame icon payload enforces strict present/absent form" {
    const a = std.testing.allocator;
    const present = FrameIconPayload{
        .flags = FrameIconFlags.present,
        .image_id = 20,
        .image_generation = 4,
        .hotspot_x = 1,
        .hotspot_y = 2,
        .frame_generation = 3,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameIcon(a, present, &bytes);
    try std.testing.expectEqual(@as(usize, 28), bytes.items.len);
    try std.testing.expectEqual(present, try decodeFrameIcon(bytes.items));

    bytes.items[0] = 2;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameIcon(bytes.items));
    bytes.items[0] = 1;
    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameIcon(bytes.items));
    bytes.items[3] = 0;
    bytes.items[20] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameIcon(bytes.items));
    bytes.items[20] = 3;
    bytes.items[4] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameIcon(bytes.items));
    bytes.items[4] = 20;
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFrameIcon(bytes.items));
    bytes.shrinkRetainingCapacity(bytes.items.len - 1);

    const absent = FrameIconPayload{ .frame_generation = 3 };
    bytes.clearRetainingCapacity();
    try encodeFrameIcon(a, absent, &bytes);
    try std.testing.expectEqual(absent, try decodeFrameIcon(bytes.items));
    bytes.items[4] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameIcon(bytes.items));
}

test "frame flush payload has a strict fixed wire form" {
    const a = std.testing.allocator;
    const payload = FrameFlushPayload{
        .flags = FrameFlushFlags.present_required | FrameFlushFlags.visible_only,
        .frame_generation = 2,
        .redisplay_generation = 0x0102030405060708,
        .frame_sequence = 0x0102030405060709,
        .deadline_ns = 0x010203040506070a,
        .damage_kind = .partial,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameFlush(a, payload, &bytes);
    try std.testing.expectEqual(@as(usize, 40), bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFrameFlush(bytes.items));
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, bytes.items[0..2], .little));
    try std.testing.expectEqual(payload.frame_generation, std.mem.readInt(u32, bytes.items[4..8], .little));
    try std.testing.expectEqual(payload.redisplay_generation, std.mem.readInt(u64, bytes.items[8..16], .little));
    try std.testing.expectEqual(payload.frame_sequence, std.mem.readInt(u64, bytes.items[16..24], .little));
    try std.testing.expectEqual(@as(u8, @intFromEnum(FrameFlushDamageKind.partial)), bytes.items[32]);

    bytes.items[2] = 0x80;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameFlush(bytes.items));
    bytes.items[2] = payload.flags;
    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameFlush(bytes.items));
    bytes.items[3] = 0;
    bytes.items[32] = 9;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameFlush(bytes.items));
    bytes.items[32] = @intFromEnum(FrameFlushDamageKind.partial);
    bytes.items[33] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameFlush(bytes.items));
    bytes.items[33] = 0;
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFrameFlush(bytes.items));
    inline for (.{ "frame_generation", "redisplay_generation", "frame_sequence" }) |field| {
        var invalid = payload;
        @field(invalid, field) = 0;
        try std.testing.expectError(Error.InvalidMessage, encodeFrameFlush(a, invalid, &bytes));
    }
}

test "render hint payload pairs flags with optional values" {
    const a = std.testing.allocator;
    const payload = RenderHintPayload{
        .flags = RenderHintFlags.damage_only_allowed |
            RenderHintFlags.deadline_present | RenderHintFlags.refresh_interval_present,
        .preferred_mode = .adaptive_vsync,
        .workload = .scroll,
        .frame_generation = 2,
        .refresh_interval_ns = 16_666_667,
        .deadline_ns = 1_000_000,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeRenderHint(a, payload, &bytes);
    try std.testing.expectEqual(@as(usize, 32), bytes.items.len);
    try std.testing.expectEqual(payload, try decodeRenderHint(bytes.items));
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, bytes.items[0..2], .little));
    try std.testing.expectEqual(@as(u8, @intFromEnum(RenderHintMode.adaptive_vsync)), bytes.items[4]);
    try std.testing.expectEqual(@as(u8, @intFromEnum(RenderHintWorkload.scroll)), bytes.items[5]);
    try std.testing.expectEqual(payload.frame_generation, std.mem.readInt(u32, bytes.items[8..12], .little));
    try std.testing.expectEqual(payload.refresh_interval_ns, std.mem.readInt(u64, bytes.items[12..20], .little));
    try std.testing.expectEqual(payload.deadline_ns, std.mem.readInt(u64, bytes.items[20..28], .little));

    bytes.items[2] = 0x80;
    try std.testing.expectError(Error.InvalidMessage, decodeRenderHint(bytes.items));
    bytes.items[2] = payload.flags;
    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeRenderHint(bytes.items));
    bytes.items[3] = 0;
    bytes.items[4] = 9;
    try std.testing.expectError(Error.InvalidMessage, decodeRenderHint(bytes.items));
    bytes.items[4] = @intFromEnum(RenderHintMode.adaptive_vsync);
    bytes.items[5] = 9;
    try std.testing.expectError(Error.InvalidMessage, decodeRenderHint(bytes.items));
    bytes.items[5] = @intFromEnum(RenderHintWorkload.scroll);
    bytes.items[6] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeRenderHint(bytes.items));
    bytes.items[6] = 0;
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeRenderHint(bytes.items));

    var unpaired = payload;
    unpaired.flags = RenderHintFlags.deadline_present;
    try std.testing.expectError(Error.InvalidMessage, encodeRenderHint(a, unpaired, &bytes));
    unpaired = payload;
    unpaired.flags = RenderHintFlags.refresh_interval_present;
    try std.testing.expectError(Error.InvalidMessage, encodeRenderHint(a, unpaired, &bytes));
    unpaired = payload;
    unpaired.deadline_ns = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeRenderHint(a, unpaired, &bytes));
}

test "frame presented payload enforces strict wire form" {
    const a = std.testing.allocator;
    const payload = FramePresentedPayload{
        .frame_generation = 2,
        .redisplay_generation = 0x0102030405060708,
        .frame_sequence = 0x0102030405060709,
        .presented_at_ns = 0x010203040506070a,
        .frame_path_ns = 0x010203040506070b,
        .draw_command_count = 0x010203040506070c,
        .damage_kind = .region,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFramePresented(a, payload, &bytes);
    try std.testing.expectEqual(@as(usize, 56), bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFramePresented(bytes.items));
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, bytes.items[0..2], .little));
    try std.testing.expectEqual(payload.frame_generation, std.mem.readInt(u32, bytes.items[4..8], .little));
    try std.testing.expectEqual(payload.redisplay_generation, std.mem.readInt(u64, bytes.items[8..16], .little));
    try std.testing.expectEqual(payload.presented_at_ns, std.mem.readInt(u64, bytes.items[24..32], .little));

    bytes.items[0] = 2;
    try std.testing.expectError(Error.InvalidMessage, decodeFramePresented(bytes.items));
    bytes.items[0] = 1;
    bytes.items[2] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFramePresented(bytes.items));
    bytes.items[2] = 0;
    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFramePresented(bytes.items));
    bytes.items[3] = 0;
    bytes.items[48] = 9;
    try std.testing.expectError(Error.InvalidMessage, decodeFramePresented(bytes.items));
    bytes.items[48] = @intFromEnum(PresentDamageKind.region);
    bytes.items[49] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFramePresented(bytes.items));
    bytes.items[49] = 0;
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFramePresented(bytes.items));
    inline for (.{ "frame_generation", "redisplay_generation", "frame_sequence", "presented_at_ns" }) |field| {
        var invalid = payload;
        @field(invalid, field) = 0;
        try std.testing.expectError(Error.InvalidMessage, encodeFramePresented(a, invalid, &bytes));
    }
    try std.testing.expectError(Error.InvalidMessage, encodeFramePresented(a, .{
        .frame_generation = 0,
        .redisplay_generation = 1,
        .frame_sequence = 1,
        .presented_at_ns = 1,
        .frame_path_ns = 1,
        .draw_command_count = 1,
        .damage_kind = .initial,
    }, &bytes));
}

test "frame dropped payload enforces strict wire form" {
    const a = std.testing.allocator;
    const payload = FrameDroppedPayload{
        .frame_generation = 2,
        .redisplay_generation = 0x0102030405060708,
        .frame_sequence = 0x0102030405060709,
        .last_presented_sequence = 0x010203040506070a,
        .observed_at_ns = 0x010203040506070b,
        .reason = .superseded,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameDropped(a, payload, &bytes);
    try std.testing.expectEqual(@as(usize, 48), bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFrameDropped(bytes.items));
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, bytes.items[0..2], .little));
    try std.testing.expectEqual(payload.frame_generation, std.mem.readInt(u32, bytes.items[4..8], .little));
    try std.testing.expectEqual(payload.redisplay_generation, std.mem.readInt(u64, bytes.items[8..16], .little));
    try std.testing.expectEqual(payload.observed_at_ns, std.mem.readInt(u64, bytes.items[32..40], .little));

    bytes.items[0] = 2;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameDropped(bytes.items));
    bytes.items[0] = 1;
    bytes.items[2] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameDropped(bytes.items));
    bytes.items[2] = 0;
    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameDropped(bytes.items));
    bytes.items[2] = 0;
    bytes.items[40] = 9;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameDropped(bytes.items));
    bytes.items[40] = @intFromEnum(FrameDropReason.superseded);
    bytes.items[41] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameDropped(bytes.items));
    bytes.items[41] = 0;
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFrameDropped(bytes.items));
    inline for (.{ "frame_generation", "redisplay_generation", "frame_sequence", "observed_at_ns" }) |field| {
        var invalid = payload;
        @field(invalid, field) = 0;
        try std.testing.expectError(Error.InvalidMessage, encodeFrameDropped(a, invalid, &bytes));
    }
    try std.testing.expectError(Error.InvalidMessage, encodeFrameDropped(a, .{
        .frame_generation = 0,
        .redisplay_generation = 1,
        .frame_sequence = 1,
        .observed_at_ns = 1,
        .last_presented_sequence = 1,
        .reason = .invalid_window_size,
    }, &bytes));
}

test "frame size hints enforce flags values and aspect ordering" {
    const a = std.testing.allocator;
    const payload = FrameSizeHintsPayload{
        .flags = FrameSizeHintFlags.min_size | FrameSizeHintFlags.max_size |
            FrameSizeHintFlags.size_increment | FrameSizeHintFlags.aspect_ratio,
        .frame_generation = 3,
        .min_width = 200,
        .min_height = 100,
        .max_width = 800,
        .max_height = 600,
        .width_increment = 10,
        .height_increment = 20,
        .aspect_min_numerator = 1,
        .aspect_min_denominator = 2,
        .aspect_max_numerator = 2,
        .aspect_max_denominator = 1,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameSizeHints(a, payload, &bytes);
    try std.testing.expectEqual(@as(usize, 48), bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFrameSizeHints(bytes.items));
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, bytes.items[0..2], .little));
    try std.testing.expectEqual(payload.frame_generation, std.mem.readInt(u32, bytes.items[4..8], .little));
    try std.testing.expectEqual(payload.min_width, std.mem.readInt(u32, bytes.items[8..12], .little));
    try std.testing.expectEqual(payload.max_height, std.mem.readInt(u32, bytes.items[20..24], .little));
    try std.testing.expectEqual(payload.width_increment, std.mem.readInt(u32, bytes.items[24..28], .little));
    try std.testing.expectEqual(payload.height_increment, std.mem.readInt(u32, bytes.items[28..32], .little));
    try std.testing.expectEqual(payload.aspect_min_numerator, std.mem.readInt(u32, bytes.items[32..36], .little));
    try std.testing.expectEqual(payload.aspect_max_denominator, std.mem.readInt(u32, bytes.items[44..48], .little));

    var invalid = payload;
    invalid.flags = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSizeHints(a, invalid, &bytes));
    invalid = payload;
    invalid.reserved = 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSizeHints(a, invalid, &bytes));
    invalid = payload;
    invalid.frame_generation = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSizeHints(a, invalid, &bytes));
    invalid = payload;
    invalid.min_width = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSizeHints(a, invalid, &bytes));
    invalid = payload;
    invalid.min_height = std.math.maxInt(i32) + 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSizeHints(a, invalid, &bytes));
    invalid = payload;
    invalid.max_width = 100;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSizeHints(a, invalid, &bytes));
    invalid = payload;
    invalid.max_height = 90;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSizeHints(a, invalid, &bytes));
    invalid = payload;
    invalid.width_increment = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSizeHints(a, invalid, &bytes));
    invalid = payload;
    invalid.height_increment = std.math.maxInt(i32) + 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSizeHints(a, invalid, &bytes));
    invalid = payload;
    invalid.aspect_min_numerator = 3;
    invalid.aspect_min_denominator = 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSizeHints(a, invalid, &bytes));
    invalid = payload;
    invalid.aspect_min_numerator = std.math.maxInt(u32);
    invalid.aspect_min_denominator = 1;
    invalid.aspect_max_numerator = 1;
    invalid.aspect_max_denominator = std.math.maxInt(u32);
    try std.testing.expectError(Error.InvalidMessage, encodeFrameSizeHints(a, invalid, &bytes));
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFrameSizeHints(bytes.items));
}

test "frame z-order payload enforces operation and relative identity" {
    const a = std.testing.allocator;
    const relative = FrameZOrderPayload{
        .operation = .above,
        .frame_generation = 2,
        .relative_frame_id = 8,
        .relative_frame_generation = 1,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameZOrder(a, relative, &bytes);
    try std.testing.expectEqual(@as(usize, 24), bytes.items.len);
    try std.testing.expectEqual(relative, try decodeFrameZOrder(bytes.items));

    const top = FrameZOrderPayload{ .operation = .top, .frame_generation = 2 };
    bytes.clearRetainingCapacity();
    try encodeFrameZOrder(a, top, &bytes);
    try std.testing.expectEqual(top, try decodeFrameZOrder(bytes.items));

    bytes.items[4] = 9;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameZOrder(bytes.items));
    bytes.items[4] = @intFromEnum(FrameZOrderOperation.top);
    bytes.items[4] = @intFromEnum(FrameZOrderOperation.above);
    bytes.items[12] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameZOrder(bytes.items));
    bytes.items[4] = @intFromEnum(FrameZOrderOperation.above);
    bytes.items[12] = 8;
    bytes.items[16] = 2;
    bytes.items[12] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameZOrder(bytes.items));
    bytes.items[12] = 8;
    bytes.items[4] = @intFromEnum(FrameZOrderOperation.top);
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFrameZOrder(bytes.items));

    var invalid = relative;
    invalid.relative_frame_id = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameZOrder(a, invalid, &bytes));
    invalid = relative;
    invalid.frame_generation = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameZOrder(a, invalid, &bytes));
}

test "frame parent payload enforces nullable and modal relations" {
    const a = std.testing.allocator;
    const child = FrameParentPayload{ .child_frame_generation = 3 };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFrameParent(a, child, &bytes);
    try std.testing.expectEqual(@as(usize, 24), bytes.items.len);
    try std.testing.expectEqual(child, try decodeFrameParent(bytes.items));

    const linked = FrameParentPayload{
        .flags = FrameParentFlags.present | FrameParentFlags.modal,
        .parent_frame_id = 7,
        .parent_frame_generation = 1,
        .child_frame_generation = 3,
    };
    var no_parent_generation = linked;
    no_parent_generation.flags = FrameParentFlags.present;
    no_parent_generation.parent_frame_generation = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameParent(a, no_parent_generation, &bytes));

    bytes.clearRetainingCapacity();
    try encodeFrameParent(a, linked, &bytes);
    try std.testing.expectEqual(linked, try decodeFrameParent(bytes.items));

    bytes.items[0] = 2;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameParent(bytes.items));
    bytes.items[0] = 1;
    bytes.items[2] = FrameParentFlags.modal;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameParent(bytes.items));
    bytes.items[2] = FrameParentFlags.present | FrameParentFlags.modal;
    bytes.items[2] = 4;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameParent(bytes.items));
    bytes.items[2] = FrameParentFlags.present | FrameParentFlags.modal;
    bytes.items[12] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameParent(bytes.items));
    bytes.items[12] = 3;
    bytes.items[4] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameParent(bytes.items));
    bytes.items[4] = 7;
    bytes.items[8] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameParent(bytes.items));
    bytes.items[8] = 1;
    bytes.items[20] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFrameParent(bytes.items));
    bytes.items[20] = 0;
    try bytes.append(a, 0);
    try std.testing.expectError(Error.InvalidTable, decodeFrameParent(bytes.items));

    var invalid = child;
    invalid.child_frame_generation = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeFrameParent(a, invalid, &bytes));
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

test "font patch codec enforces scalar identity and generation rules" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    const patch: FontPatch = .{
        .font_id = 31,
        .expected_generation = 5,
        .new_generation = 6,
        .weight = 700,
        .width_percent = 100,
        .pixel_size = 18,
        .point_size_tenths = 135,
        .x_dpi = 96,
        .y_dpi = 96,
        .slant = .roman,
        .spacing = .mono,
        .scalable = true,
        .fixed_pitch = true,
    };
    try encodeFontPatch(a, patch, &bytes);
    try std.testing.expectEqual(font_patch_size, bytes.items.len);
    try std.testing.expectEqual(patch, try decodeFontPatch(bytes.items));

    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFontPatch(bytes.items));
    bytes.items[3] = 0;
    bytes.items[40] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFontPatch(bytes.items));
    bytes.items[40] = 0;
    bytes.items[38] = 2;
    try std.testing.expectError(Error.InvalidBoolean, decodeFontPatch(bytes.items));
    bytes.items[38] = 1;

    std.mem.writeInt(u32, bytes.items[12..16], 5, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFontPatch(bytes.items));
    std.mem.writeInt(u32, bytes.items[12..16], patch.new_generation, .little);
    std.mem.writeInt(u32, bytes.items[28..32], 96, .little);
    std.mem.writeInt(u32, bytes.items[32..36], 0, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFontPatch(bytes.items));
    try std.testing.expectError(Error.InvalidTable, decodeFontPatch(bytes.items[0 .. bytes.items.len - 1]));
}

test "fringe bitmap codec enforces bounded packed rows" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    var payload: FringeBitmapDefine = .{
        .bitmap_id = 9,
        .generation = 2,
        .width = 12,
        .height = 3,
    };
    payload.bits[0] = 0x80;
    payload.bits[1] = 0x80;
    payload.bits[(max_fringe_bitmap_dimension + 7) / 8 + 1] = 0x40;
    try encodeFringeBitmapDefine(a, payload, &bytes);
    try std.testing.expectEqual(fringe_bitmap_define_size, bytes.items.len);
    try std.testing.expectEqual(payload, try decodeFringeBitmapDefine(bytes.items));

    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFringeBitmapDefine(bytes.items));
    bytes.items[3] = 0;
    bytes.items[2] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeFringeBitmapDefine(bytes.items));
    bytes.items[2] = 0;

    payload.width = 8;
    payload.bits[1] = 0x80;
    try std.testing.expectError(Error.InvalidMessage, encodeFringeBitmapDefine(a, payload, &bytes));
    payload.bits[1] = 0;
    payload.height = 3;
    payload.bits[4 * (max_fringe_bitmap_dimension + 7) / 8] = 1;
    try std.testing.expectError(Error.InvalidMessage, encodeFringeBitmapDefine(a, payload, &bytes));
    payload.bits[4 * (max_fringe_bitmap_dimension + 7) / 8] = 0;
    payload.width = 12;

    std.mem.writeInt(u16, bytes.items[12..14], 33, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeFringeBitmapDefine(bytes.items));
    std.mem.writeInt(u16, bytes.items[12..14], payload.width, .little);
    try std.testing.expectError(Error.InvalidTable, decodeFringeBitmapDefine(bytes.items[0 .. bytes.items.len - 1]));

    var delete_bytes: std.ArrayList(u8) = .empty;
    defer delete_bytes.deinit(a);
    try encodeFringeBitmapDelete(a, .{ .bitmap_id = 9, .generation = 2 }, &delete_bytes);
    try std.testing.expectEqual(fringe_bitmap_delete_size, delete_bytes.items.len);
    try std.testing.expectEqual(FringeBitmapDelete{ .bitmap_id = 9, .generation = 2 }, try decodeFringeBitmapDelete(delete_bytes.items));
    delete_bytes.items[0] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeFringeBitmapDelete(delete_bytes.items));
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

test "menu model round trips bounded UTF-8 tree" {
    const a = std.testing.allocator;
    var nodes = [_]MenuNode{
        .{
            .item_id = 20,
            .parent_item_id = 0,
            .kind = .submenu,
            .flags = MenuNodeFlags.enabled | MenuNodeFlags.visible,
            .depth = 0,
            .label_len = 4,
            .help_len = 4,
            .key_len = 1,
        },
        .{
            .item_id = 21,
            .parent_item_id = 20,
            .kind = .command,
            .flags = MenuNodeFlags.enabled | MenuNodeFlags.visible,
            .depth = 1,
            .label_len = 8,
        },
    };
    @memcpy(nodes[0].label[0..4], "File");
    @memcpy(nodes[0].help[0..4], "File");
    @memcpy(nodes[0].key[0..1], "F");
    @memcpy(nodes[1].label[0..8], "NewFrame");
    const snapshot: MenuModelSnapshot = .{
        .header = .{ .frame_id = 7, .frame_generation = 2, .menu_id = 3, .menu_generation = 4 },
        .nodes = &nodes,
    };
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeMenuModelSnapshot(a, snapshot, &bytes);
    try std.testing.expectEqual(menu_model_header_size + 2 * menu_node_size, bytes.items.len);
    var decoded = try decodeMenuModelSnapshot(a, bytes.items);
    defer freeMenuModelSnapshot(a, &decoded);
    try std.testing.expectEqual(@as(usize, 2), decoded.nodes.len);
    try std.testing.expectEqualStrings("File", decoded.nodes[0].label[0..4]);
    try std.testing.expectEqualStrings("NewFrame", decoded.nodes[1].label[0..8]);
}

test "menu model rejects invalid hierarchy and metadata" {
    var valid = [_]MenuNode{
        .{
            .item_id = 20,
            .parent_item_id = 0,
            .kind = .submenu,
            .flags = MenuNodeFlags.enabled | MenuNodeFlags.visible,
            .depth = 0,
            .label_len = 4,
        },
        .{
            .item_id = 21,
            .parent_item_id = 20,
            .kind = .command,
            .flags = MenuNodeFlags.enabled | MenuNodeFlags.visible,
            .depth = 1,
            .label_len = 8,
        },
    };
    @memcpy(valid[0].label[0..4], "File");
    @memcpy(valid[1].label[0..8], "NewFrame");
    const header: MenuModelHeader = .{ .frame_id = 7, .frame_generation = 1, .menu_id = 3, .menu_generation = 1 };
    try validateMenuModelSnapshot(.{ .header = header, .nodes = &valid });

    var duplicate = valid;
    duplicate[1].item_id = 20;
    try std.testing.expectError(Error.InvalidTable, validateMenuModelSnapshot(.{ .header = header, .nodes = &duplicate }));

    var command_parent = valid;
    command_parent[0].kind = .command;
    try std.testing.expectError(Error.InvalidMessage, validateMenuModelSnapshot(.{ .header = header, .nodes = &command_parent }));

    var bad_label = valid;
    bad_label[1].label[0] = 0xff;
    try std.testing.expectError(Error.InvalidUtf8, validateMenuModelSnapshot(.{ .header = header, .nodes = &bad_label }));

    var hidden_parent = valid;
    hidden_parent[0].flags = MenuNodeFlags.enabled;
    try std.testing.expectError(Error.InvalidMessage, validateMenuModelSnapshot(.{ .header = header, .nodes = &hidden_parent }));

    var disabled_parent = valid;
    disabled_parent[0].flags = MenuNodeFlags.visible;
    try std.testing.expectError(Error.InvalidMessage, validateMenuModelSnapshot(.{ .header = header, .nodes = &disabled_parent }));

    var non_root_depth = valid;
    non_root_depth[1].parent_item_id = 0;
    try std.testing.expectError(Error.InvalidMessage, validateMenuModelSnapshot(.{ .header = header, .nodes = &non_root_depth }));

    var oversize_label = valid;
    oversize_label[1].label_len = oversize_label[1].label.len + 1;
    try std.testing.expectError(Error.InvalidMessage, validateMenuModelSnapshot(.{ .header = header, .nodes = &oversize_label }));

    var oversize_key = valid;
    oversize_key[1].key_len = oversize_key[1].key.len + 1;
    try std.testing.expectError(Error.InvalidMessage, validateMenuModelSnapshot(.{ .header = header, .nodes = &oversize_key }));

    const wire_allocator = std.testing.allocator;
    var round_trip: std.ArrayList(u8) = .empty;
    defer round_trip.deinit(wire_allocator);
    try encodeMenuModelSnapshot(wire_allocator, .{ .header = header, .nodes = &valid }, &round_trip);
    var oversize_wire = try wire_allocator.dupe(u8, round_trip.items);
    defer wire_allocator.free(oversize_wire);
    const second_label_len = menu_model_header_size + menu_node_size + 10;
    oversize_wire[second_label_len] = 65;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuModelSnapshot(wire_allocator, oversize_wire));

    @memcpy(oversize_wire, round_trip.items);
    const second_key_len = menu_model_header_size + menu_node_size + 12;
    oversize_wire[second_key_len] = 33;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuModelSnapshot(wire_allocator, oversize_wire));
}

test "menu open and close codecs enforce identity bounds and reasons" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    const open: MenuOpen = .{
        .menu_id = 3,
        .menu_generation = 4,
        .item_id = 20,
        .window_id = 10,
        .frame_generation = 1,
        .x = 8,
        .y = 16,
        .width = 48,
        .height = 64,
    };
    try encodeMenuOpen(a, open, &bytes);
    try std.testing.expectEqual(menu_open_size, bytes.items.len);
    try std.testing.expectEqual(open, try decodeMenuOpen(bytes.items));

    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuOpen(bytes.items));
    bytes.items[3] = 0;
    bytes.items[47] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuOpen(bytes.items));
    bytes.items[47] = 0;
    std.mem.writeInt(i32, bytes.items[28..32], -1, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeMenuOpen(bytes.items));
    std.mem.writeInt(i32, bytes.items[28..32], open.x, .little);
    std.mem.writeInt(u32, bytes.items[36..40], max_window_size + 1, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeMenuOpen(bytes.items));
    try std.testing.expectError(Error.InvalidTable, decodeMenuOpen(bytes.items[0 .. bytes.items.len - 1]));

    bytes.clearRetainingCapacity();
    const close: MenuClose = .{
        .reason = .selection,
        .menu_id = 3,
        .menu_generation = 4,
        .item_id = 21,
        .frame_generation = 1,
    };
    try encodeMenuClose(a, close, &bytes);
    try std.testing.expectEqual(menu_close_size, bytes.items.len);
    try std.testing.expectEqual(close, try decodeMenuClose(bytes.items));
    bytes.items[2] = 4;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuClose(bytes.items));
    bytes.items[2] = @intFromEnum(MenuCloseReason.selection);
    bytes.items[3] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuClose(bytes.items));
    bytes.items[3] = 0;
    try std.testing.expectError(Error.InvalidTable, decodeMenuClose(bytes.items[0 .. bytes.items.len - 1]));
}

test "menu result and cancel codecs validate bounded live identities" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    const result: MenuResult = .{
        .menu_id = 3,
        .menu_generation = 4,
        .item_id = 21,
        .window_id = 10,
        .frame_generation = 1,
    };
    try encodeMenuResult(a, result, &bytes);
    try std.testing.expectEqual(menu_result_size, bytes.items.len);
    try std.testing.expectEqual(result, try decodeMenuResult(bytes.items));
    bytes.items[2] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuResult(bytes.items));
    bytes.items[2] = 0;
    bytes.items[31] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuResult(bytes.items));
    bytes.items[31] = 0;
    bytes.items[12] = 0;
    bytes.items[13] = 0;
    bytes.items[14] = 0;
    bytes.items[15] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuResult(bytes.items));
    try std.testing.expectError(Error.InvalidTable, decodeMenuResult(bytes.items[0 .. bytes.items.len - 1]));

    bytes.clearRetainingCapacity();
    const cancel: MenuCancel = .{
        .reason = .escape,
        .menu_id = 3,
        .menu_generation = 4,
        .window_id = 10,
        .frame_generation = 1,
    };
    try encodeMenuCancel(a, cancel, &bytes);
    try std.testing.expectEqual(menu_cancel_size, bytes.items.len);
    try std.testing.expectEqual(cancel, try decodeMenuCancel(bytes.items));
    bytes.items[2] = 9;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuCancel(bytes.items));
    bytes.items[2] = @intFromEnum(MenuCancelReason.escape);
    bytes.items[27] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeMenuCancel(bytes.items));
    bytes.items[27] = 0;
    std.mem.writeInt(u32, bytes.items[20..24], 0, .little);
    try std.testing.expectError(Error.InvalidMessage, decodeMenuCancel(bytes.items));
    try std.testing.expectError(Error.InvalidTable, decodeMenuCancel(bytes.items[0 .. bytes.items.len - 1]));
}

test "dialog codecs enforce bounded model and result identities" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    var title: [max_dialog_title]u8 = @splat(0);
    var text: [max_dialog_text]u8 = @splat(0);
    @memcpy(title[0..6], "Delete");
    @memcpy(text[0..11], "Delete file");
    const state: DialogState = .{
        .kind = .confirm,
        .dialog_id = 80,
        .dialog_generation = 2,
        .window_id = 10,
        .frame_generation = 3,
        .x = 8,
        .y = 12,
        .width = 96,
        .height = 48,
        .title_len = 6,
        .text_len = 11,
        .buttons = DialogButtons.yes | DialogButtons.no,
        .title = title,
        .text = text,
    };
    try encodeDialogState(a, state, &bytes);
    try std.testing.expectEqual(dialog_state_size, bytes.items.len);
    try std.testing.expectEqual(state, try decodeDialogState(bytes.items));
    bytes.items[41] = 1;
    try std.testing.expectError(Error.InvalidReserved, decodeDialogState(bytes.items));
    bytes.items[41] = 0;
    bytes.items[46] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeDialogState(bytes.items));
    bytes.items[46] = 0;
    var invalid = state;
    invalid.buttons = DialogButtons.ok;
    try std.testing.expectError(Error.InvalidMessage, encodeDialogState(a, invalid, &bytes));
    invalid = state;
    invalid.width = 0;
    try std.testing.expectError(Error.InvalidMessage, encodeDialogState(a, invalid, &bytes));
    try std.testing.expectError(Error.InvalidTable, decodeDialogState(bytes.items[0 .. bytes.items.len - 1]));

    bytes.clearRetainingCapacity();
    const close: DialogClose = .{
        .reason = .escape,
        .dialog_id = 80,
        .dialog_generation = 2,
        .window_id = 10,
        .frame_generation = 3,
    };
    try encodeDialogClose(a, close, &bytes);
    try std.testing.expectEqual(dialog_close_size, bytes.items.len);
    try std.testing.expectEqual(close, try decodeDialogClose(bytes.items));
    bytes.items[24] = 1;
    try std.testing.expectError(Error.InvalidMessage, decodeDialogClose(bytes.items));
    bytes.items[24] = 0;

    bytes.clearRetainingCapacity();
    var result_text: [128]u8 = @splat(0);
    @memcpy(result_text[0..4], "user");
    const result: DialogResult = .{
        .button = .custom,
        .dialog_id = 80,
        .dialog_generation = 2,
        .window_id = 10,
        .frame_generation = 3,
        .text_len = 4,
        .text = result_text,
    };
    try encodeDialogResult(a, result, &bytes);
    try std.testing.expectEqual(dialog_result_size, bytes.items.len);
    try std.testing.expectEqual(result, try decodeDialogResult(bytes.items));
    bytes.items[2] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeDialogResult(bytes.items));
    bytes.items[2] = @intFromEnum(DialogResultButton.custom);
    bytes.items[26] = 1;
    try std.testing.expectError(Error.InvalidDialogResult, decodeDialogResult(bytes.items));
    bytes.items[26] = 0;
    bytes.items[32] = 0;
    try std.testing.expectError(Error.InvalidMessage, decodeDialogResult(bytes.items));
    bytes.items[32] = 'u';
    try std.testing.expectError(Error.InvalidTable, decodeDialogResult(bytes.items[0 .. bytes.items.len - 1]));
}
