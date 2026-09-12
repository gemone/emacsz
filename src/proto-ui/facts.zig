//! Adapter-owned conversion for public Emacs frame facts.
//!
//! Facts are observed through public Lisp APIs, validated, then translated to a
//! complete EUP snapshot so SDL can consume them through the same Scene rules
//! as any other FRAME_UPDATE.

const std = @import("std");
const frontend = @import("frontend.zig");
const protocol = @import("protocol.zig");

pub const FrameFacts = struct {
    frame_width: i32,
    frame_height: i32,
    window_width: i32,
    window_height: i32,
    /// Real display line height in logical units; 0 keeps the bounded guess.
    line_height: i32 = 0,
    /// Real display character width in logical units; 0 keeps the guess.
    char_width: i32 = 0,
    /// Real default-face font pixel size reported by the producer; 0 keeps the
    /// line-height-derived size.
    font_pixel_size: i32 = 0,
    focused: bool = false,
    /// Bounded cursor shape for the published cursors.
    ///
    /// The adapter publishes one kind for the frame's cursors: the selected
    /// window's Emacs cursor type decides it, and an unrecognised or absent
    /// value keeps the solid box.
    cursor_kind: u8 = 1,
    /// Live default-face colors reported by the producer as `#rrggbb`.
    ///
    /// Absent means the producer did not report that half, so the frontend
    /// keeps its draw default instead of guessing a color.
    default_foreground: ?[4]u8 = null,
    default_background: ?[4]u8 = null,
    /// Live mode-line face colors reported by the producer as `#rrggbb`.
    mode_line_foreground: ?[4]u8 = null,
    mode_line_background: ?[4]u8 = null,
    mode_line_inactive_foreground: ?[4]u8 = null,
    mode_line_inactive_background: ?[4]u8 = null,
    /// Live header-line and tab-line face colors from the producer.
    header_line_foreground: ?[4]u8 = null,
    header_line_background: ?[4]u8 = null,
    tab_line_foreground: ?[4]u8 = null,
    tab_line_background: ?[4]u8 = null,
    /// Live tool-bar face colors from the producer.
    tool_bar_foreground: ?[4]u8 = null,
    tool_bar_background: ?[4]u8 = null,
    /// Bounded box styles for the frame's real mode-line and tool-bar faces.
    mode_line_box: protocol.BoxStyle = .none,
    tool_bar_box: protocol.BoxStyle = .none,
    /// Real `:box` `:line-width` in pixels for those faces (0 = unspecified).
    mode_line_box_width: i32 = 0,
    tool_bar_box_width: i32 = 0,
    cursor_background: ?[4]u8 = null,
    fringe_background: ?[4]u8 = null,
    /// Bounded active-region highlight rectangles (one per displayed row).
    regions: []RegionRect = &.{},
    region_background: ?[4]u8 = null,
    /// Bounded mouse-face highlight rectangles under the mirror's pointer
    /// (one per displayed row the highlighted span touches).
    mouse_rects: []RegionRect = &.{},
    mouse_background: ?[4]u8 = null,
    /// Bounded font-lock runs (up to eight visible rows) with their foregrounds.
    line_runs: []LineRun = &.{},
};

pub const LineRunWire = struct {
    window_id: u64 = 0,
    mode_line: bool = false,
    header_line: bool = false,
    tab_line: bool = false,
    row: i32 = 0,
    column: i32 = 0,
    text: []const u8 = "",
    foreground: ?[]const u8 = null,
    background: ?[]const u8 = null,
    underline: bool = false,
    strike_through: bool = false,
    overline: bool = false,
    underline_color: ?[]const u8 = null,
    strike_color: ?[]const u8 = null,
    overline_color: ?[]const u8 = null,
    inverse_video: bool = false,
    bold: bool = false,
    italic: bool = false,
    box: bool = false,
    box_color: ?[]const u8 = null,
    partial: bool = false,
    variable_pitch: bool = false,
    font_file: ?[]const u8 = null,
    /// Producer-reported text-origin pixel geometry; both are absent (-1)
    /// when the producer has no face-aware pixel measurement.
    pixel_x: i32 = -1,
    pixel_width: i32 = -1,
};

pub const max_line_runs: usize = 32;
pub const max_line_run_rows: usize = 8;
pub const line_run_face_base_id: u32 = 100;
pub const line_run_glyph_base_id: u32 = 300;

pub const RegionRect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
};

pub const CursorFacts = struct {
    line: i32,
    column: i32,
};

pub const max_observed_windows: usize = 16;

/// Face id the live facts bridge uses for the frame's default face.
pub const default_face_id: u32 = 1;
/// Reserved face id for the frame's real mode-line face colors.
pub const mode_line_face_id: u32 = 2;
/// Reserved face ids for the frame's cursor and fringe colors.
pub const mode_line_inactive_face_id: u32 = 5;
/// Reserved face id for the frame's active-region highlight color.  A
/// multi-line region emits one rectangle per displayed row, using this id for
/// the first rectangle and the bounded block above it for the rest.
pub const region_face_id: u32 = 6;
pub const region_rect_face_base_id: u32 = 20;
pub const max_region_rects: usize = 8;

/// Face id for the index-th rectangle of the active-region highlight.
pub fn regionRectFaceId(index: usize) u32 {
    return if (index == 0) region_face_id else region_rect_face_base_id + @as(u32, @intCast(index - 1));
}
/// Reserved face id for the mouse-face highlight under the mirror's pointer.
pub const mouse_face_id: u32 = 9;
/// A mouse-face span that covers several displayed rows emits one rectangle
/// per row, using `mouse_face_id` for the first and this bounded block above it
/// for the rest (kept clear of the region's 20..27 block).
pub const mouse_rect_face_base_id: u32 = 40;
pub const max_mouse_rects: usize = 8;

/// Face id for the index-th rectangle of the mouse-face highlight.
pub fn mouseRectFaceId(index: usize) u32 {
    return if (index == 0) mouse_face_id else mouse_rect_face_base_id + @as(u32, @intCast(index - 1));
}
pub const cursor_face_id: u32 = 3;
pub const fringe_face_id: u32 = 4;
/// Reserved face ids for the frame's real header-line and tab-line colors.
pub const header_line_face_id: u32 = 7;
pub const tab_line_face_id: u32 = 8;
/// Reserved face id for the frame's real tool-bar face colors.
pub const tool_bar_face_id: u32 = 10;
/// Reserved string resource id carrying the frame's default font file path.
pub const default_font_string_id: u32 = 1;
/// Reserved string resource id carrying the frame's default font pixel size.
pub const default_font_size_string_id: u32 = 2;
/// Reserved string resource id carrying the frame's echo-area text.
pub const echo_string_id: u32 = 3;
/// Reserved string resource id carrying one negotiated variable-pitch font.
pub const variable_font_string_id: u32 = 4;

pub const WindowFact = struct {
    id: u32,
    index: usize,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    selected: bool,
};

fn windowsEql(left: []const WindowFact, right: []const WindowFact) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (!std.meta.eql(a, b)) return false;
    }
    return true;
}

pub const ViewportFacts = struct {
    start_line: i32,
    line_count: i32,

    pub fn valid(self: ViewportFacts) bool {
        // The mirrored line count is bounded by the text table; the start line
        // is the window's real absolute line, so it is bounded only by the
        // publisher's own buffer-line clamp.  Coupling the two would reject a
        // scrolled window that still mirrors a full screen.
        if (self.start_line < 1 or self.start_line > max_viewport_start_line) return false;
        return self.line_count >= 0 and self.line_count <= max_text_lines;
    }
};

pub const max_text_lines: usize = 32;
/// Upper bound for a published absolute window start line.
pub const max_viewport_start_line: i32 = 1 << 24;
pub const max_text_columns: usize = 120;
pub const max_text_bytes: usize = max_text_columns;
pub const max_lines_per_window: usize = 32;
pub const max_total_text_lines: usize = 128;
pub const max_buffer_lines: i32 = 1 << 20;
pub const max_menu_bar_items: usize = 8;
pub const max_menu_bar_label: usize = 64;
pub const max_toolbar_label: usize = 64;
pub const max_toolbar_key: usize = 16;
pub const max_menu_children: usize = 24;
pub const menu_child_id_base: u32 = 1000;
pub const menu_nested_child_id_base: u32 = 1100;
pub const max_menu_path_len: usize = 3;
pub const max_menu_row_depth: usize = max_menu_path_len + 1;

pub const MenuRowKind = enum { command, checkbox, radio };

fn parseMenuRowKind(value: []const u8) ?MenuRowKind {
    if (std.mem.eql(u8, value, "command")) return .command;
    if (std.mem.eql(u8, value, "toggle") or std.mem.eql(u8, value, "checkbox")) return .checkbox;
    if (std.mem.eql(u8, value, "radio")) return .radio;
    return null;
}

pub fn menuChildIdBase(row_depth: usize) ?u32 {
    if (row_depth == 0 or row_depth > max_menu_path_len + 1) return null;
    return menu_child_id_base + @as(u32, @intCast(100 * (row_depth - 1)));
}

/// One bounded font-lock run of the first visible line with its owned text.
pub const LineRun = struct {
    window_id: u64 = 0,
    mode_line: bool = false,
    header_line: bool = false,
    tab_line: bool = false,
    row: i32 = 0,
    column: i32,
    text: []const u8,
    foreground: [4]u8,
    /// A face background distinct from the frame default, when present.
    background: ?[4]u8 = null,
    underline: bool = false,
    strike_through: bool = false,
    overline: bool = false,
    underline_color: ?[4]u8 = null,
    strike_color: ?[4]u8 = null,
    overline_color: ?[4]u8 = null,
    inverse_video: bool = false,
    bold: bool = false,
    italic: bool = false,
    /// A face box decoration on this run, with its own color when it names one.
    box: bool = false,
    box_color: ?[4]u8 = null,
    /// This run colours only part of its row, so the row keeps its plain text.
    partial: bool = false,
    /// The resolved face names a font distinct from the frame default.
    variable_pitch: bool = false,
    /// Alternate font family: 0 default, 1 the negotiated variable-pitch font,
    /// 2/3 the additional bounded alternate font files.
    font_family: u8 = 0,
    /// Producer-reported text-origin pixel geometry; -1/-1 keeps the
    /// character-cell fallback.
    pixel_x: i32 = -1,
    pixel_width: i32 = -1,
};

/// Most alternate font files published beside the default and family 1.
pub const max_alt_font_families: usize = 2;

pub const TextLines = struct {
    lines: [][]const u8 = &.{},
    owner: []u8 = &.{},

    pub fn deinit(self: *TextLines, gpa: std.mem.Allocator) void {
        if (self.lines.len != 0) gpa.free(self.lines);
        if (self.owner.len != 0) gpa.free(self.owner);
        self.* = .{};
    }

    pub fn eql(self: TextLines, other: TextLines) bool {
        if (self.lines.len != other.lines.len) return false;
        for (self.lines, other.lines) |left, right| {
            if (!std.mem.eql(u8, left, right)) return false;
        }
        return true;
    }
};

pub const WindowContent = struct {
    id: u32,
    text: TextLines,
    viewport: ViewportFacts,
    scroll_width: i32 = 0,
    buffer_lines: i32 = 0,
    scroll_top: i32 = 0,
    scroll_height: i32 = 0,
    hscroll: i32 = 0,
    hviewport: i32 = 0,
    hcontent: i32 = 0,
    fringe_left: i32 = 0,
    fringe_right: i32 = 0,
    mode_line: ?[]const u8 = null,
    mode_line_height: i32 = 0,
    header_line: ?[]const u8 = null,
    header_line_height: i32 = 0,
    tab_line: ?[]const u8 = null,
    tab_line_height: i32 = 0,
    cursor: ?CursorFacts = null,
    cursor_active: bool = false,

    pub fn eql(left: WindowContent, right: WindowContent) bool {
        return left.id == right.id and left.text.eql(right.text) and
            std.meta.eql(left.viewport, right.viewport) and
            left.scroll_width == right.scroll_width and
            left.buffer_lines == right.buffer_lines and
            left.scroll_top == right.scroll_top and
            left.scroll_height == right.scroll_height and
            left.hscroll == right.hscroll and
            left.hviewport == right.hviewport and
            left.hcontent == right.hcontent and
            left.fringe_left == right.fringe_left and
            left.fringe_right == right.fringe_right and
            std.meta.eql(left.cursor, right.cursor) and
            left.cursor_active == right.cursor_active and
            ((left.mode_line == null and right.mode_line == null) or
                (left.mode_line != null and right.mode_line != null and
                    std.mem.eql(u8, left.mode_line.?, right.mode_line.?))) and
            left.mode_line_height == right.mode_line_height and
            ((left.header_line == null and right.header_line == null) or
                (left.header_line != null and right.header_line != null and
                    std.mem.eql(u8, left.header_line.?, right.header_line.?))) and
            left.header_line_height == right.header_line_height and
            ((left.tab_line == null and right.tab_line == null) or
                (left.tab_line != null and right.tab_line != null and
                    std.mem.eql(u8, left.tab_line.?, right.tab_line.?))) and
            left.tab_line_height == right.tab_line_height;
    }

    pub fn deinit(self: *WindowContent, gpa: std.mem.Allocator) void {
        self.text.deinit(gpa);
        if (self.mode_line) |line| gpa.free(line);
        if (self.header_line) |line| gpa.free(line);
        if (self.tab_line) |line| gpa.free(line);
    }
};

fn windowContentsEql(left: []const WindowContent, right: []const WindowContent) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (!a.eql(b)) return false;
    }
    return true;
}

fn lineRunsEql(left: []const LineRun, right: []const LineRun) bool {
    if (left.len != right.len) return false;
    for (left, right) |a_run, b_run| {
        if (a_run.window_id != b_run.window_id or a_run.mode_line != b_run.mode_line or
            a_run.header_line != b_run.header_line or a_run.tab_line != b_run.tab_line or
            a_run.row != b_run.row or a_run.column != b_run.column or
            !std.meta.eql(a_run.foreground, b_run.foreground) or
            !std.meta.eql(a_run.background, b_run.background) or
            a_run.underline != b_run.underline or
            a_run.strike_through != b_run.strike_through or
            a_run.overline != b_run.overline or
            !std.meta.eql(a_run.underline_color, b_run.underline_color) or
            !std.meta.eql(a_run.strike_color, b_run.strike_color) or
            !std.meta.eql(a_run.overline_color, b_run.overline_color) or
            a_run.inverse_video != b_run.inverse_video or
            a_run.bold != b_run.bold or a_run.italic != b_run.italic or
            a_run.box != b_run.box or
            !std.meta.eql(a_run.box_color, b_run.box_color) or
            a_run.partial != b_run.partial or
            a_run.variable_pitch != b_run.variable_pitch or
            a_run.font_family != b_run.font_family or
            !std.mem.eql(u8, a_run.text, b_run.text)) return false;
    }
    return true;
}

fn menuBarEql(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (!std.mem.eql(u8, a, b)) return false;
    }
    return true;
}

fn altFontFilesEql(left: [max_alt_font_families]?[]const u8, right: [max_alt_font_families]?[]const u8) bool {
    for (left, right) |a, b| {
        if ((a == null) != (b == null)) return false;
        if (a != null and !std.mem.eql(u8, a.?, b.?)) return false;
    }
    return true;
}

fn toolbarFactsEql(left: []const ToolbarFact, right: []const ToolbarFact) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (a.kind != b.kind or a.flags != b.flags or
            !std.mem.eql(u8, a.label, b.label) or
            !std.mem.eql(u8, a.help, b.help) or
            !std.mem.eql(u8, a.key, b.key)) return false;
    }
    return true;
}

const OpenMenuPathWire = struct {
    id: u32 = 0,
    label: []const u8 = "",
};

const OpenMenuWire = struct {
    item_id: u32 = 0,
    window_id: u64 = 0,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    items: []const []const u8 = &.{},
    enabled: []const bool = &.{},
    keys: []const []const u8 = &.{},
    helps: []const []const u8 = &.{},
    submenu: []const bool = &.{},
    selected: []const bool = &.{},
    kind: []const []const u8 = &.{},
    icon_ids: []const u32 = &.{},
    icon_generations: []const u32 = &.{},
    icon_payloads: []const []const u8 = &.{},
    parent_id: u32 = 0,
    parent_label: ?[]const u8 = null,
    path: []const OpenMenuPathWire = &.{},
};

/// Bounded open-menu state published by the producer: the pressed menu-bar item
/// and the real child rows of its keymap, with the popup rectangle the frontend
/// draws and navigates.
pub const MenuPath = struct {
    id: u32,
    label: []const u8,
};

pub const OpenMenu = struct {
    item_id: u32,
    window_id: u64,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    items: [][]const u8 = &.{},
    /// Real `:enable` state per row (parallel to `items`).
    enabled: []bool = &.{},
    /// Real key hint each row shows (parallel to `items`; empty when none).
    keys: [][]const u8 = &.{},
    keys_owner: []u8 = &.{},
    /// Real `:help` text per row (parallel to `items`; empty when none).
    helps: [][]const u8 = &.{},
    helps_owner: []u8 = &.{},
    owner: []u8 = &.{},
    /// True when a row opens a bounded submenu.
    submenus: []bool = &.{},
    /// Real stateful-row selection state (parallel to `items`).
    selected: []bool = &.{},
    /// Bounded row kind after radio/toggle properties.
    kinds: []MenuRowKind = &.{},
    /// Generation-qualified menu icon references (parallel to `items`).
    icon_ids: []u32 = &.{},
    icon_generations: []u32 = &.{},
    /// Real bounded XBM bytes for a file-backed or inline `:data` icon.
    icon_payloads: [][]const u8 = &.{},
    icon_payloads_owner: []u8 = &.{},
    /// Root identity/label path for a nested popup; zero means a top-level popup.
    parent_id: u32 = 0,
    parent_label: []const u8 = &.{},
    parent_label_owner: []u8 = &.{},
    path: []MenuPath = &.{},
    path_owner: []u8 = &.{},

    pub fn eql(left: OpenMenu, right: OpenMenu) bool {
        return left.item_id == right.item_id and left.window_id == right.window_id and
            left.x == right.x and left.y == right.y and
            left.width == right.width and left.height == right.height and
            menuBarEql(left.items, right.items) and
            std.meta.eql(left.enabled, right.enabled) and
            menuBarEql(left.keys, right.keys) and
            menuBarEql(left.helps, right.helps) and
            std.meta.eql(left.submenus, right.submenus) and
            std.meta.eql(left.selected, right.selected) and
            std.mem.eql(MenuRowKind, left.kinds, right.kinds) and
            std.meta.eql(left.icon_ids, right.icon_ids) and
            std.meta.eql(left.icon_generations, right.icon_generations) and
            menuBarEql(left.icon_payloads, right.icon_payloads) and
            left.parent_id == right.parent_id and
            std.mem.eql(u8, left.parent_label, right.parent_label) and
            left.path.len == right.path.len and blk: {
            for (left.path, right.path) |a, b| {
                if (a.id != b.id or !std.mem.eql(u8, a.label, b.label)) break :blk false;
            }
            break :blk true;
        };
    }

    pub fn deinit(self: *OpenMenu, gpa: std.mem.Allocator) void {
        if (self.items.len != 0) gpa.free(self.items);
        if (self.enabled.len != 0) gpa.free(self.enabled);
        if (self.keys.len != 0) gpa.free(self.keys);
        if (self.keys_owner.len != 0) gpa.free(self.keys_owner);
        if (self.helps.len != 0) gpa.free(self.helps);
        if (self.helps_owner.len != 0) gpa.free(self.helps_owner);
        if (self.owner.len != 0) gpa.free(self.owner);
        if (self.submenus.len != 0) gpa.free(self.submenus);
        if (self.selected.len != 0) gpa.free(self.selected);
        if (self.kinds.len != 0) gpa.free(self.kinds);
        if (self.icon_ids.len != 0) gpa.free(self.icon_ids);
        if (self.icon_generations.len != 0) gpa.free(self.icon_generations);
        if (self.icon_payloads.len != 0) gpa.free(self.icon_payloads);
        if (self.icon_payloads_owner.len != 0) gpa.free(self.icon_payloads_owner);
        self.icon_payloads = &.{};
        self.icon_payloads_owner = &.{};
        if (self.parent_label_owner.len != 0) gpa.free(self.parent_label_owner);
        if (self.path.len != 0) gpa.free(self.path);
        if (self.path_owner.len != 0) gpa.free(self.path_owner);
        self.items = &.{};
        self.enabled = &.{};
        self.keys = &.{};
        self.keys_owner = &.{};
        self.owner = &.{};
        self.submenus = &.{};
        self.selected = &.{};
        self.kinds = &.{};
        self.parent_label = &.{};
        self.parent_label_owner = &.{};
        self.path = &.{};
        self.path_owner = &.{};
    }
};

/// One bounded tool-bar item published by the producer.
pub const ToolbarFact = struct {
    kind: protocol.ToolbarItemKind,
    flags: u8,
    label: []const u8,
    help: []const u8,
    key: []const u8,
};

pub const Snapshot = struct {
    facts: FrameFacts,
    windows: []WindowFact = &.{},
    contents: []WindowContent = &.{},
    text: TextLines = .{},
    cursor: CursorFacts = .{ .line = 0, .column = 0 },
    viewport: ViewportFacts = .{ .start_line = 1, .line_count = 0 },
    /// Bounded real default font file path reported by the producer.
    font_file: ?[]const u8 = null,
    /// One real font file used by runs that differ from the default face.
    variable_font_file: ?[]const u8 = null,
    /// Additional bounded alternate font files (families 2 and 3).
    alt_font_files: [max_alt_font_families]?[]const u8 = .{ null, null },
    /// Bounded echo-area text for the frame's bottom strip.
    echo: ?[]const u8 = null,
    /// Owned storage for the published line-run texts.
    line_runs_owner: []u8 = &.{},
    /// Bounded font-lock runs (up to eight visible rows; views into `line_runs_owner`).
    line_runs: []LineRun = &.{},
    /// Bounded real menu-bar labels with their owned storage.
    menu_bar: [][]const u8 = &.{},
    menu_bar_owner: []u8 = &.{},
    /// Bounded real tool-bar items with their owned label/help/key storage.
    tool_bar: []ToolbarFact = &.{},
    tool_bar_owner: []u8 = &.{},
    open_menu: ?OpenMenu = null,
    title: ?[]const u8 = null,
    focused: bool = false,

    pub fn eql(left: Snapshot, right: Snapshot) bool {
        return factsEql(left.facts, right.facts) and left.text.eql(right.text) and
            windowsEql(left.windows, right.windows) and
            windowContentsEql(left.contents, right.contents) and
            std.meta.eql(left.cursor, right.cursor) and
            std.meta.eql(left.viewport, right.viewport) and
            lineRunsEql(left.line_runs, right.line_runs) and
            ((left.font_file == null and right.font_file == null) or
                (left.font_file != null and right.font_file != null and
                    std.mem.eql(u8, left.font_file.?, right.font_file.?))) and
            ((left.variable_font_file == null and right.variable_font_file == null) or
                (left.variable_font_file != null and right.variable_font_file != null and
                    std.mem.eql(u8, left.variable_font_file.?, right.variable_font_file.?))) and
            altFontFilesEql(left.alt_font_files, right.alt_font_files) and
            ((left.echo == null and right.echo == null) or
                (left.echo != null and right.echo != null and
                    std.mem.eql(u8, left.echo.?, right.echo.?))) and
            menuBarEql(left.menu_bar, right.menu_bar) and
            toolbarFactsEql(left.tool_bar, right.tool_bar) and
            ((left.open_menu == null and right.open_menu == null) or
                (left.open_menu != null and right.open_menu != null and
                    left.open_menu.?.eql(right.open_menu.?))) and
            ((left.title == null and right.title == null) or
                (left.title != null and right.title != null and
                    std.mem.eql(u8, left.title.?, right.title.?))) and
            left.focused == right.focused;
    }

    pub fn deinit(self: *Snapshot, gpa: std.mem.Allocator) void {
        if (self.windows.len != 0) gpa.free(self.windows);
        self.windows = &.{};
        for (self.contents) |*content| content.deinit(gpa);
        if (self.contents.len != 0) gpa.free(self.contents);
        self.contents = &.{};
        self.text.deinit(gpa);
        if (self.line_runs.len != 0) gpa.free(self.line_runs);
        if (self.line_runs_owner.len != 0) gpa.free(self.line_runs_owner);
        self.line_runs = &.{};
        self.line_runs_owner = &.{};
        if (self.facts.regions.len != 0) gpa.free(self.facts.regions);
        self.facts.regions = &.{};
        if (self.facts.mouse_rects.len != 0) gpa.free(self.facts.mouse_rects);
        self.facts.mouse_rects = &.{};
        if (self.font_file) |file| gpa.free(file);
        self.font_file = null;
        if (self.variable_font_file) |file| gpa.free(file);
        self.variable_font_file = null;
        for (&self.alt_font_files) |*file| {
            if (file.*) |owned| gpa.free(owned);
            file.* = null;
        }
        if (self.echo) |text| gpa.free(text);
        self.echo = null;
        if (self.menu_bar.len != 0) gpa.free(self.menu_bar);
        if (self.menu_bar_owner.len != 0) gpa.free(self.menu_bar_owner);
        self.menu_bar = &.{};
        self.menu_bar_owner = &.{};
        if (self.tool_bar.len != 0) gpa.free(self.tool_bar);
        if (self.tool_bar_owner.len != 0) gpa.free(self.tool_bar_owner);
        self.tool_bar = &.{};
        self.tool_bar_owner = &.{};
        if (self.open_menu) |*open_menu| open_menu.deinit(gpa);
        self.open_menu = null;
        if (self.title) |title| gpa.free(title);
        self.title = null;
    }
};
pub const Error = std.json.ParseError(std.json.Scanner) || error{
    InvalidFrameFacts,
    InvalidWindowFacts,
    InvalidWindowContent,
    InvalidViewportFacts,
    InvalidScrollFacts,
    InvalidMenuBarFacts,
    InvalidFontFacts,
    InvalidRegionFacts,
    InvalidEchoFacts,
    InvalidModeLineFacts,
    InvalidAuxLineFacts,
    InvalidTitleFacts,
    InvalidToolbarFacts,
};

const ToolbarItemWire = struct {
    kind: []const u8 = "button",
    label: ?[]const u8 = null,
    help: ?[]const u8 = null,
    key: ?[]const u8 = null,
    enabled: bool = true,
    visible: bool = true,
    selected: bool = false,
};

const SnapshotWire = struct {
    frame_width: i32,
    frame_height: i32,
    window_width: i32,
    window_height: i32,
    windows: []const WindowFact = &.{},
    identity: []const u8 = "",
    window_states: []const WindowStateWire = &.{},
    text: []const []const u8 = &.{},
    cursor: CursorFacts = .{ .line = 1, .column = 0 },
    window_start_line: i32 = 1,
    window_visible_lines: i32 = 0,
    line_height: i32 = 0,
    char_width: i32 = 0,
    menu_bar: []const []const u8 = &.{},
    menu_open: ?OpenMenuWire = null,
    tool_bar: []const ToolbarItemWire = &.{},
    title: ?[]const u8 = null,
    focused: bool = false,
    /// Live default-face colors as `#rrggbb`, when the producer reports them.
    foreground: ?[]const u8 = null,
    background: ?[]const u8 = null,
    mode_line_foreground: ?[]const u8 = null,
    mode_line_background: ?[]const u8 = null,
    mode_line_inactive_foreground: ?[]const u8 = null,
    mode_line_inactive_background: ?[]const u8 = null,
    header_line_foreground: ?[]const u8 = null,
    header_line_background: ?[]const u8 = null,
    tab_line_foreground: ?[]const u8 = null,
    tab_line_background: ?[]const u8 = null,
    tool_bar_foreground: ?[]const u8 = null,
    tool_bar_background: ?[]const u8 = null,
    mode_line_box: ?[]const u8 = null,
    tool_bar_box: ?[]const u8 = null,
    mode_line_box_width: i32 = 0,
    tool_bar_box_width: i32 = 0,
    cursor_background: ?[]const u8 = null,
    fringe_background: ?[]const u8 = null,
    regions: []const RegionRect = &.{},
    region_background: ?[]const u8 = null,
    mouse_rects: []const RegionRect = &.{},
    mouse_background: ?[]const u8 = null,
    echo: ?[]const u8 = null,
    line_runs: []const LineRunWire = &.{},
    font_file: ?[]const u8 = null,
    variable_font_file: ?[]const u8 = null,
    font_pixel_size: i32 = 0,
    cursor_kind: u8 = 1,
};

const WindowStateWire = struct {
    id: u32,
    lines: []const []const u8 = &.{},
    window_start_line: i32 = 1,
    window_visible_lines: i32 = 0,
    cursor: ?CursorFacts = null,
    cursor_active: bool = false,
    scroll_width: i32 = 0,
    buffer_lines: i32 = 0,
    scroll_top: i32 = 0,
    scroll_height: i32 = 0,
    hscroll: i32 = 0,
    hviewport: i32 = 0,
    hcontent: i32 = 0,
    fringe_left: i32 = 0,
    fringe_right: i32 = 0,
    mode_line: ?[]const u8 = null,
    mode_line_height: i32 = 0,
    header_line: ?[]const u8 = null,
    header_line_height: i32 = 0,
    tab_line: ?[]const u8 = null,
    tab_line_height: i32 = 0,
};

fn cursorFitsVertical(cursor: CursorFacts, window_height: i32, line_height: i32) bool {
    const row_height: i64 = visibleRowHeight(window_height, line_height);
    const cursor_height: i64 = @max(2, @min(18, row_height));
    return @as(i64, cursor.line - 1) * row_height + cursor_height <= window_height;
}

/// The frame's real character cell width, used to place a cursor column.
fn cursorCellWidth(char_width: i32) i32 {
    return if (char_width > 0 and char_width <= 256) char_width else 8;
}

fn visibleRowCount(window_height: i32, line_height: i32) i32 {
    if (line_height > 1)
        return @max(1, @min(15, @divTrunc(window_height, line_height)));
    return @min(15, window_height);
}

fn visibleRowHeight(window_height: i32, line_height: i32) i32 {
    if (line_height > 1) return @min(line_height, window_height);
    return @max(1, @divTrunc(window_height, visibleRowCount(window_height, 0)));
}

fn parseWindowText(gpa: std.mem.Allocator, lines: []const []const u8) !TextLines {
    if (lines.len > max_lines_per_window) return error.InvalidWindowContent;
    var total: usize = 0;
    for (lines) |line| {
        if (!frontend.validBoundedUtf8Line(line, frontend.max_row_columns)) return error.InvalidWindowContent;
        total += line.len;
    }
    const slices = try gpa.alloc([]const u8, lines.len);
    errdefer gpa.free(slices);
    const owner = try gpa.alloc(u8, total);
    errdefer gpa.free(owner);
    var offset: usize = 0;
    for (lines, 0..) |line, index| {
        @memcpy(owner[offset..][0..line.len], line);
        slices[index] = owner[offset..][0..line.len];
        offset += line.len;
    }
    return .{ .lines = slices, .owner = owner };
}

fn parseWindowContents(gpa: std.mem.Allocator, states: []const WindowStateWire, windows: []const WindowFact, line_height: i32) ![]WindowContent {
    if (states.len == 0) return &.{};
    if (states.len != windows.len) return error.InvalidWindowContent;
    const contents = try gpa.alloc(WindowContent, states.len);
    var initialized: usize = 0;
    errdefer {
        for (contents[0..initialized]) |*content| content.deinit(gpa);
        gpa.free(contents);
    }
    var active_count: usize = 0;
    for (states, 0..) |state, index| {
        const fact = windows[index];
        if (state.id != fact.id or state.id == 0) return error.InvalidWindowContent;
        const viewport = ViewportFacts{ .start_line = state.window_start_line, .line_count = state.window_visible_lines };
        if (!viewport.valid() or viewport.line_count != state.lines.len) return error.InvalidWindowContent;
        if (state.cursor == null and state.cursor_active) return error.InvalidCursorFacts;
        if (state.cursor) |cursor| {
            if (cursor.line < 1 or cursor.column < 0 or
                cursor.line > state.lines.len or cursor.column > max_text_columns)
                return error.InvalidCursorFacts;
            if (@as(i64, cursor.column) * 8 + 2 > fact.width)
                return error.InvalidCursorFacts;
            if (!cursorFitsVertical(cursor, fact.height, line_height))
                return error.InvalidCursorFacts;
            if (!fact.selected and state.cursor_active) return error.InvalidCursorFacts;
            if (state.cursor_active) active_count += 1;
        }
        if (state.mode_line != null or state.mode_line_height != 0) {
            if (state.mode_line == null or state.mode_line_height <= 0 or
                state.mode_line_height > fact.height or
                !frontend.validBoundedUtf8Text(state.mode_line.?, max_text_columns))
                return error.InvalidModeLineFacts;
        }
        if (state.header_line != null or state.header_line_height != 0) {
            if (state.header_line == null or state.header_line_height <= 0 or
                state.header_line_height > fact.height or
                !frontend.validBoundedUtf8Text(state.header_line.?, max_text_columns))
                return error.InvalidAuxLineFacts;
        }
        if (state.header_line != null and state.tab_line != null) {
            const combined = @addWithOverflow(state.header_line_height, state.tab_line_height);
            if (combined[1] != 0 or combined[0] > fact.height)
                return error.InvalidAuxLineFacts;
        }
        if (state.tab_line != null or state.tab_line_height != 0) {
            if (state.tab_line == null or state.tab_line_height <= 0 or
                state.tab_line_height > fact.height or
                !frontend.validBoundedUtf8Text(state.tab_line.?, max_text_columns))
                return error.InvalidAuxLineFacts;
        }
        if (state.scroll_width < 0 or state.scroll_width > 256 or
            state.buffer_lines < 0 or state.buffer_lines > max_buffer_lines or
            state.scroll_top < 0 or state.scroll_top > max_buffer_lines or
            (state.scroll_width > 0 and state.buffer_lines == 0))
            return error.InvalidScrollFacts;
        if (state.fringe_left < 0 or state.fringe_left > 64 or
            state.fringe_right < 0 or state.fringe_right > 64)
            return error.InvalidScrollFacts;
        if (state.scroll_height < 0 or state.scroll_height > 256 or
            state.hscroll < 0 or state.hviewport < 0 or state.hcontent < 0 or
            state.hscroll > max_buffer_lines or state.hcontent > max_buffer_lines or
            state.hviewport > max_buffer_lines or
            (state.scroll_height > 0 and
                (state.hviewport <= 0 or state.hcontent < state.hviewport)))
            return error.InvalidScrollFacts;
        contents[index] = .{
            .id = state.id,
            .text = try parseWindowText(gpa, state.lines),
            .viewport = viewport,
            .scroll_width = state.scroll_width,
            .buffer_lines = state.buffer_lines,
            .scroll_top = state.scroll_top,
            .scroll_height = state.scroll_height,
            .hscroll = state.hscroll,
            .hviewport = state.hviewport,
            .hcontent = state.hcontent,
            .fringe_left = state.fringe_left,
            .fringe_right = state.fringe_right,
            .cursor = state.cursor,
            .cursor_active = state.cursor_active,
            .mode_line = if (state.mode_line) |line| try gpa.dupe(u8, line) else null,
            .mode_line_height = state.mode_line_height,
            .header_line = if (state.header_line) |line| try gpa.dupe(u8, line) else null,
            .header_line_height = state.header_line_height,
            .tab_line = if (state.tab_line) |line| try gpa.dupe(u8, line) else null,
            .tab_line_height = state.tab_line_height,
        };
        initialized = index + 1;
    }
    if (active_count > 1) return error.InvalidCursorFacts;
    for (contents, 0..) |left, index| {
        for (windows) |fact| {
            if (left.id == fact.id) break;
        } else return error.InvalidWindowContent;
        for (contents[index + 1 ..]) |right| {
            if (left.id == right.id) return error.InvalidWindowContent;
        }
    }
    return contents;
}

fn validateWindowFact(wire: WindowFact, snapshot: SnapshotWire) Error!void {
    if (wire.x < 0 or wire.y < 0 or wire.width <= 0 or wire.height <= 0 or
        wire.x > snapshot.frame_width or wire.y > snapshot.frame_height or
        wire.width > snapshot.frame_width or wire.height > snapshot.frame_height or
        @as(i64, wire.x) + wire.width > snapshot.frame_width or
        @as(i64, wire.y) + wire.height > snapshot.frame_height)
        return error.InvalidWindowFacts;
}

fn validateWindowSet(windows: []const WindowFact, snapshot: SnapshotWire) Error!void {
    if (windows.len > max_observed_windows) return error.InvalidWindowFacts;
    var selected_count: usize = 0;
    var selected: ?WindowFact = null;
    var id_count: usize = 0;
    for (windows, 0..) |item, index| {
        if (item.index != index) return error.InvalidWindowFacts;
        if (item.id != 0) id_count += 1;
        try validateWindowFact(item, snapshot);
        if (item.selected) {
            selected = item;
            selected_count += 1;
        }
    }
    if (selected_count != 1) return error.InvalidWindowFacts;
    if (id_count != windows.len) return error.InvalidWindowFacts;

    for (windows, 0..) |item, index| {
        for (windows[index + 1 ..]) |other| {
            if (item.id == other.id) return error.InvalidWindowFacts;
            const left = @max(item.x, other.x);
            const right = @min(@as(i64, item.x) + item.width, @as(i64, other.x) + other.width);
            const top = @max(item.y, other.y);
            const bottom = @min(@as(i64, item.y) + item.height, @as(i64, other.y) + other.height);
            if (left < right and top < bottom) return error.InvalidWindowFacts;
        }
    }

    if (selected.?.width != snapshot.window_width or
        selected.?.height != snapshot.window_height)
        return error.InvalidWindowFacts;
}

fn parseWindows(gpa: std.mem.Allocator, wire: []const WindowFact, snapshot: SnapshotWire) ![]WindowFact {
    if (wire.len == 0) {
        const windows = try gpa.alloc(WindowFact, 1);
        windows[0] = .{
            .id = 1001,
            .index = 0,
            .x = 0,
            .y = 0,
            .width = snapshot.window_width,
            .height = snapshot.window_height,
            .selected = true,
        };
        try validateWindowFact(windows[0], snapshot);
        return windows;
    }
    try validateWindowSet(wire, snapshot);

    const windows = try gpa.alloc(WindowFact, wire.len);
    @memcpy(windows, wire);
    return windows;
}

pub fn factsEql(left: FrameFacts, right: FrameFacts) bool {
    return std.meta.eql(left, right);
}

/// Keep the published cursor kind inside the bounded set the frontend renders.
/// Anything else falls back to the solid box rather than inventing a shape.
pub fn boundedCursorKind(kind: u8) u8 {
    return switch (kind) {
        frontend.cursor_kind_box,
        frontend.cursor_kind_bar,
        frontend.cursor_kind_hbar,
        frontend.cursor_kind_hollow,
        frontend.cursor_kind_underline,
        => kind,
        else => frontend.cursor_kind_box,
    };
}

/// Parse one `#rrggbb` face color.  Returns null for anything else, so a
/// producer that reports an unusable value keeps the frontend default instead
/// of propagating a guess.
pub fn parseFaceColor(text: []const u8) ?[4]u8 {
    if (text.len != 7 or text[0] != '#') return null;
    var color: [4]u8 = .{ 0, 0, 0, 255 };
    var index: usize = 0;
    while (index < 3) : (index += 1) {
        const high = hexDigit(text[1 + index * 2]) orelse return null;
        const low = hexDigit(text[2 + index * 2]) orelse return null;
        color[index] = high * 16 + low;
    }
    return color;
}

/// Parse one bounded box-style name.  Anything else is rejected, so an
/// unusable producer value cannot silently become a guessed border.
fn parseBoxStyle(text: []const u8) ?protocol.BoxStyle {
    if (std.mem.eql(u8, text, "simple")) return .simple;
    if (std.mem.eql(u8, text, "released")) return .released;
    if (std.mem.eql(u8, text, "pressed")) return .pressed;
    return null;
}

fn isPrintableAscii(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (byte < 0x20 or byte > 0x7e) return false;
    }
    return true;
}

/// A bounded, readable font file path from the wire.
fn validFontFilePath(file: []const u8) bool {
    if (file.len == 0 or file.len > 120 or !frontend.validBoundedUtf8Text(file, 120))
        return false;
    for (file) |byte| {
        if (byte < 0x20 or byte == 0x7f) return false;
    }
    return true;
}

fn fontFileMatches(file: []const u8, candidate: ?[]const u8) bool {
    const other = candidate orelse return false;
    return std.mem.eql(u8, file, other);
}

fn fontFileInList(file: []const u8, list: *const [max_alt_font_families]?[]const u8, count: usize) bool {
    for (list[0..count]) |entry| {
        if (entry) |candidate| {
            if (std.mem.eql(u8, file, candidate)) return true;
        }
    }
    return false;
}

/// Resolve a run's alternate font family from its file path: 0 default,
/// 1 the negotiated variable-pitch font, 2/3 the extra alternates.
fn runFontFamily(
    file: ?[]const u8,
    default_file: ?[]const u8,
    alt_files: []const ?[]const u8,
) u8 {
    const name = file orelse return 0;
    if (fontFileMatches(name, default_file)) return 0;
    for (alt_files, 0..) |entry, index| {
        const candidate = entry orelse continue;
        if (std.mem.eql(u8, name, candidate)) return @intCast(2 + index);
    }
    return 1;
}

fn hexDigit(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

pub fn parse(gpa: std.mem.Allocator, bytes: []const u8) Error!FrameFacts {
    const parsed = try std.json.parseFromSlice(FrameFacts, gpa, bytes, .{});
    defer parsed.deinit();
    const facts = parsed.value;
    if (facts.frame_width <= 0 or facts.frame_height <= 0 or
        facts.window_width <= 0 or facts.window_height <= 0 or
        facts.window_width > facts.frame_width or
        facts.window_height > facts.frame_height) return error.InvalidFrameFacts;
    return facts;
}

pub fn parseText(gpa: std.mem.Allocator, bytes: []const u8) !TextLines {
    var count: usize = 0;
    var total: usize = 0;
    var lines: [max_text_lines][]const u8 = undefined;
    const body = if (std.mem.endsWith(u8, bytes, "\n")) bytes[0 .. bytes.len - 1] else bytes;
    var iterator = std.mem.splitScalar(u8, body, '\n');
    while (iterator.next()) |line| {
        if (count == max_text_lines or
            !frontend.validBoundedUtf8Line(line, frontend.max_row_columns)) return error.InvalidTextFacts;
        lines[count] = line;
        total += line.len;
        count += 1;
    }

    const slices = try gpa.alloc([]const u8, count);
    errdefer gpa.free(slices);
    const owner = try gpa.alloc(u8, total);
    errdefer gpa.free(owner);
    var offset: usize = 0;
    for (lines[0..count], 0..) |line, index| {
        @memcpy(owner[offset..][0..line.len], line);
        slices[index] = owner[offset..][0..line.len];
        offset += line.len;
    }
    return .{ .lines = slices, .owner = owner };
}

pub fn parseCursor(gpa: std.mem.Allocator, bytes: []const u8) !CursorFacts {
    const parsed = try std.json.parseFromSlice(CursorFacts, gpa, bytes, .{});
    defer parsed.deinit();
    const cursor = parsed.value;
    if (cursor.line < 1 or cursor.column < 0 or
        cursor.line >= @as(i32, @intCast(max_text_lines)) or
        cursor.column > @as(i32, @intCast(max_text_columns))) return error.InvalidCursorFacts;
    return cursor;
}

/// Return the run-measured text offset of a cursor, or null when no body run
/// on that displayed row carries P163's bounded pixel pair.
fn runAwareCursorOffset(facts: FrameFacts, window_id: u64, row: i32, column: i32) ?i32 {
    for (facts.line_runs) |run| {
        if ((run.window_id != 0 and run.window_id != window_id) or
            run.mode_line or run.header_line or run.tab_line or
            run.row != row or run.pixel_x < 0 or run.pixel_width <= 0)
            continue;
        const run_start = run.column;
        const run_end = run_start + @as(i32, @intCast(run.text.len));
        if (column < run_start or column > run_end) continue;
        const local = @min(@max(0, column - run_start), @as(i32, @intCast(run.text.len)));
        return run.pixel_x + @divTrunc(
            local * run.pixel_width,
            @as(i32, @intCast(run.text.len)),
        );
    }
    return null;
}

pub fn parseSnapshot(gpa: std.mem.Allocator, bytes: []const u8) !Snapshot {
    const parsed = try std.json.parseFromSlice(SnapshotWire, gpa, bytes, .{});
    defer parsed.deinit();
    const wire = parsed.value;
    if (wire.frame_width <= 0 or wire.frame_height <= 0 or
        wire.window_width <= 0 or wire.window_height <= 0 or
        wire.window_width > wire.frame_width or
        wire.window_height > wire.frame_height) return error.InvalidFrameFacts;
    if (wire.text.len > max_text_lines) return error.InvalidTextFacts;
    for (wire.text) |line| {
        if (!frontend.validBoundedUtf8Line(line, frontend.max_row_columns)) return error.InvalidTextFacts;
    }
    if (wire.cursor.line < 1 or wire.cursor.line > max_text_lines or
        wire.cursor.column < 0 or wire.cursor.column > max_text_columns)
        return error.InvalidCursorFacts;
    const viewport = ViewportFacts{ .start_line = wire.window_start_line, .line_count = wire.window_visible_lines };
    if (!viewport.valid()) return error.InvalidViewportFacts;
    if (viewport.line_count != wire.text.len) return error.InvalidViewportFacts;
    if (wire.title) |title| {
        if (title.len == 0 or title.len > max_text_columns or
            !frontend.validBoundedUtf8Text(title, max_text_columns))
            return error.InvalidTitleFacts;
    }
    if ((wire.windows.len != 0 or wire.window_states.len != 0) and
        !std.mem.eql(u8, wire.identity, "process_lifetime"))
        return error.InvalidWindowFacts;
    if (wire.windows.len == 0 and wire.window_states.len != 0)
        return error.InvalidWindowFacts;
    const windows = try parseWindows(gpa, wire.windows, wire);
    errdefer gpa.free(windows);
    if (wire.line_height < 0 or wire.line_height > 512) return error.InvalidFrameFacts;
    if (wire.char_width < 0 or wire.char_width > 256) return error.InvalidFrameFacts;
    if (wire.regions.len > max_region_rects) return error.InvalidRegionFacts;
    const regions = try gpa.alloc(RegionRect, wire.regions.len);
    errdefer gpa.free(regions);
    for (wire.regions, 0..) |region, region_index| {
        if (region.x < 0 or region.y < 0 or region.width <= 0 or region.height <= 0 or
            region.width > 4096 or region.height > 4096)
            return error.InvalidRegionFacts;
        regions[region_index] = region;
    }
    if (wire.echo) |echo| {
        if (echo.len == 0 or echo.len > max_text_columns or
            !frontend.validBoundedUtf8Text(echo, max_text_columns))
            return error.InvalidEchoFacts;
    }
    if (wire.mouse_rects.len > max_mouse_rects) return error.InvalidRegionFacts;
    const mouse_rects = try gpa.alloc(RegionRect, wire.mouse_rects.len);
    errdefer gpa.free(mouse_rects);
    for (wire.mouse_rects, 0..) |rect, rect_index| {
        if (rect.x < 0 or rect.y < 0 or rect.width <= 0 or rect.height <= 0 or
            rect.width > 4096 or rect.height > 4096)
            return error.InvalidRegionFacts;
        mouse_rects[rect_index] = rect;
    }
    const contents = try parseWindowContents(gpa, wire.window_states, windows, wire.line_height);
    errdefer {
        for (contents) |*content| content.deinit(gpa);
        gpa.free(contents);
    }

    const slices = try gpa.alloc([]const u8, wire.text.len);
    errdefer gpa.free(slices);
    var total: usize = 0;
    for (wire.text) |line| total += line.len;
    const owner = try gpa.alloc(u8, total);
    errdefer gpa.free(owner);
    var offset: usize = 0;
    for (wire.text, 0..) |line, index| {
        @memcpy(owner[offset..][0..line.len], line);
        slices[index] = owner[offset..][0..line.len];
        offset += line.len;
    }
    if (wire.font_file) |font_file| {
        if (!validFontFilePath(font_file)) return error.InvalidFontFacts;
    }
    if (wire.font_pixel_size < 0 or wire.font_pixel_size > 512)
        return error.InvalidFontFacts;
    if (wire.mode_line_box) |text| {
        if (parseBoxStyle(text) == null) return error.InvalidModeLineFacts;
    }
    if (wire.tool_bar_box) |text| {
        if (parseBoxStyle(text) == null) return error.InvalidToolbarFacts;
    }
    if (wire.mode_line_box_width < 0 or wire.mode_line_box_width > 8)
        return error.InvalidModeLineFacts;
    if (wire.tool_bar_box_width < 0 or wire.tool_bar_box_width > 8)
        return error.InvalidToolbarFacts;
    if (wire.variable_font_file) |font_file| {
        if (!validFontFilePath(font_file)) return error.InvalidFontFacts;
    }
    if (wire.line_runs.len > max_line_runs) return error.InvalidRunFacts;
    var line_runs: []LineRun = &.{};
    var line_runs_owner: []u8 = &.{};
    var alt_font_files: [max_alt_font_families]?[]const u8 = .{ null, null };
    var alt_font_count: usize = 0;
    if (wire.line_runs.len != 0) {
        var run_total: usize = 0;
        for (wire.line_runs) |wire_run| {
            const color = if (wire_run.foreground) |text| parseFaceColor(text) else null;
            const background = if (wire_run.background) |text| parseFaceColor(text) else null;
            const underline_color = if (wire_run.underline_color) |text| parseFaceColor(text) else null;
            const strike_color = if (wire_run.strike_color) |text| parseFaceColor(text) else null;
            const overline_color = if (wire_run.overline_color) |text| parseFaceColor(text) else null;
            const box_color = if (wire_run.box_color) |text| parseFaceColor(text) else null;
            if (wire_run.row < 0 or wire_run.row >= max_line_run_rows or
                wire_run.column < 0 or wire_run.text.len == 0 or
                wire_run.text.len > frontend.max_row_columns or color == null or
                @as(u8, @intFromBool(wire_run.mode_line)) +
                    @as(u8, @intFromBool(wire_run.header_line)) +
                    @as(u8, @intFromBool(wire_run.tab_line)) > 1 or
                (wire_run.background != null and background == null) or
                (wire_run.underline_color != null and underline_color == null) or
                (wire_run.strike_color != null and strike_color == null) or
                (wire_run.overline_color != null and overline_color == null) or
                (wire_run.box_color != null and box_color == null) or
                !isPrintableAscii(wire_run.text))
                return error.InvalidRunFacts;
            const pixel_metrics = wire_run.pixel_x >= 0 and wire_run.pixel_width >= 0;
            if ((wire_run.pixel_x < 0) != (wire_run.pixel_width < 0) or
                (pixel_metrics and (wire_run.pixel_x > 4096 or
                    wire_run.pixel_width == 0 or wire_run.pixel_width > 4096)))
                return error.InvalidRunFacts;
            if (wire_run.font_file) |font_file| {
                if (!validFontFilePath(font_file)) return error.InvalidRunFacts;
                // A run font that is neither the default nor family 1 opens an
                // additional alternate family, bounded to two.  Extra
                // families beyond the bound keep family 1 rather than failing
                // the whole snapshot.
                if (!fontFileMatches(font_file, wire.font_file) and
                    !fontFileMatches(font_file, wire.variable_font_file) and
                    !fontFileInList(font_file, &alt_font_files, alt_font_count) and
                    alt_font_count < max_alt_font_families)
                {
                    alt_font_files[alt_font_count] = font_file;
                    alt_font_count += 1;
                }
            }
            run_total += wire_run.text.len;
        }
        const run_owner = try gpa.alloc(u8, run_total);
        errdefer gpa.free(run_owner);
        const runs = try gpa.alloc(LineRun, wire.line_runs.len);
        errdefer gpa.free(runs);
        var run_offset: usize = 0;
        for (wire.line_runs, 0..) |wire_run, index| {
            @memcpy(run_owner[run_offset..][0..wire_run.text.len], wire_run.text);
            runs[index] = .{
                .window_id = wire_run.window_id,
                .mode_line = wire_run.mode_line,
                .header_line = wire_run.header_line,
                .tab_line = wire_run.tab_line,
                .row = wire_run.row,
                .column = wire_run.column,
                .text = run_owner[run_offset..][0..wire_run.text.len],
                .foreground = parseFaceColor(wire_run.foreground.?).?,
                .background = if (wire_run.background) |text| parseFaceColor(text) else null,
                .underline = wire_run.underline,
                .strike_through = wire_run.strike_through,
                .overline = wire_run.overline,
                .underline_color = if (wire_run.underline_color) |text| parseFaceColor(text) else null,
                .strike_color = if (wire_run.strike_color) |text| parseFaceColor(text) else null,
                .overline_color = if (wire_run.overline_color) |text| parseFaceColor(text) else null,
                .inverse_video = wire_run.inverse_video,
                .bold = wire_run.bold,
                .italic = wire_run.italic,
                .box = wire_run.box,
                .box_color = if (wire_run.box_color) |text| parseFaceColor(text) else null,
                .partial = wire_run.partial,
                .variable_pitch = wire_run.variable_pitch,
                .font_family = runFontFamily(
                    wire_run.font_file,
                    wire.font_file,
                    alt_font_files[0..alt_font_count],
                ),
                .pixel_x = wire_run.pixel_x,
                .pixel_width = wire_run.pixel_width,
            };
            run_offset += wire_run.text.len;
        }
        line_runs = runs;
        line_runs_owner = run_owner;
    }

    if (wire.menu_bar.len > max_menu_bar_items) return error.InvalidMenuBarFacts;
    const menu_bar = try gpa.alloc([]const u8, wire.menu_bar.len);
    errdefer gpa.free(menu_bar);
    var menu_total: usize = 0;
    for (wire.menu_bar) |label| {
        if (label.len == 0 or label.len > max_menu_bar_label or
            !frontend.validBoundedUtf8Text(label, max_menu_bar_label))
            return error.InvalidMenuBarFacts;
        menu_total += label.len;
    }
    const menu_owner = try gpa.alloc(u8, menu_total);
    errdefer gpa.free(menu_owner);
    var menu_offset: usize = 0;
    for (wire.menu_bar, 0..) |label, index| {
        @memcpy(menu_owner[menu_offset..][0..label.len], label);
        menu_bar[index] = menu_owner[menu_offset..][0..label.len];
        menu_offset += label.len;
    }
    var open_menu: ?OpenMenu = null;
    if (wire.menu_open) |wire_menu| {
        var candidate = wire_menu;
        var legacy_path: [1]OpenMenuPathWire = undefined;
        if (candidate.parent_id != 0 and candidate.path.len == 0) {
            legacy_path[0] = .{
                .id = candidate.item_id,
                .label = candidate.parent_label orelse "",
            };
            candidate.path = &legacy_path;
        }
        if (candidate.item_id == 0 or
            candidate.window_id == 0 or candidate.x < 0 or candidate.y < 0 or
            candidate.width <= 0 or candidate.height <= 0 or
            candidate.items.len == 0 or candidate.items.len > max_menu_children)
            return error.InvalidMenuBarFacts;
        if (candidate.enabled.len != 0 and candidate.enabled.len != candidate.items.len)
            return error.InvalidMenuBarFacts;
        if (candidate.keys.len != 0 and candidate.keys.len != candidate.items.len)
            return error.InvalidMenuBarFacts;
        if (candidate.helps.len != 0 and candidate.helps.len != candidate.items.len)
            return error.InvalidMenuBarFacts;
        if (candidate.submenu.len != 0 and candidate.submenu.len != candidate.items.len)
            return error.InvalidMenuBarFacts;
        if (candidate.selected.len != 0 and candidate.selected.len != candidate.items.len)
            return error.InvalidMenuBarFacts;
        if (candidate.kind.len != 0 and candidate.kind.len != candidate.items.len)
            return error.InvalidMenuBarFacts;
        for (candidate.kind) |kind| {
            if (parseMenuRowKind(kind) == null) return error.InvalidMenuBarFacts;
        }
        if (candidate.icon_ids.len != 0 and candidate.icon_ids.len != candidate.items.len)
            return error.InvalidMenuBarFacts;
        if (candidate.icon_generations.len != 0 and candidate.icon_generations.len != candidate.items.len)
            return error.InvalidMenuBarFacts;
        if (candidate.icon_payloads.len != 0 and candidate.icon_payloads.len != candidate.items.len)
            return error.InvalidMenuBarFacts;
        if (candidate.parent_id == 0 and candidate.item_id > menu_bar.len)
            return error.InvalidMenuBarFacts;
        if (candidate.parent_id != 0) {
            if (candidate.path.len == 0 or candidate.path.len > max_menu_path_len)
                return error.InvalidMenuBarFacts;
            const item_base = menuChildIdBase(candidate.path.len) orelse
                return error.InvalidMenuBarFacts;
            if (candidate.item_id < item_base or candidate.item_id >= item_base + max_menu_children or
                candidate.parent_id == 0 or candidate.parent_id > menu_bar.len)
                return error.InvalidMenuBarFacts;
            for (candidate.path, 0..) |entry, index| {
                const base = menuChildIdBase(index + 1) orelse return error.InvalidMenuBarFacts;
                if (entry.id < base or entry.id >= base + max_menu_children or
                    entry.label.len == 0 or entry.label.len > max_menu_bar_label or
                    !frontend.validBoundedUtf8Text(entry.label, max_menu_bar_label))
                    return error.InvalidMenuBarFacts;
                if (index == candidate.path.len - 1 and entry.id != candidate.item_id)
                    return error.InvalidMenuBarFacts;
                if (index > 0 and entry.id == candidate.path[index - 1].id)
                    return error.InvalidMenuBarFacts;
            }
            const immediate_label = candidate.path[candidate.path.len - 1].label;
            if (candidate.parent_label) |label| {
                if (!std.mem.eql(u8, label, immediate_label))
                    return error.InvalidMenuBarFacts;
            }
        }
        var child_slices = try gpa.alloc([]const u8, candidate.items.len);
        errdefer gpa.free(child_slices);
        const child_enabled = try gpa.alloc(bool, candidate.items.len);
        errdefer gpa.free(child_enabled);
        @memset(child_enabled, true);
        if (candidate.enabled.len == candidate.items.len) {
            @memcpy(child_enabled, candidate.enabled);
        }
        const child_submenus = try gpa.alloc(bool, candidate.items.len);
        errdefer gpa.free(child_submenus);
        @memset(child_submenus, false);
        if (candidate.submenu.len == candidate.items.len) {
            @memcpy(child_submenus, candidate.submenu);
        }
        const child_selected = try gpa.alloc(bool, candidate.items.len);
        errdefer gpa.free(child_selected);
        @memset(child_selected, false);
        if (candidate.selected.len == candidate.items.len) {
            @memcpy(child_selected, candidate.selected);
        }
        const child_helps = try gpa.alloc([]const u8, candidate.items.len);
        errdefer gpa.free(child_helps);
        @memset(child_helps, &.{});
        const child_kinds = try gpa.alloc(MenuRowKind, candidate.items.len);
        errdefer gpa.free(child_kinds);
        for (child_kinds) |*kind| kind.* = .command;
        const child_icon_ids = try gpa.alloc(u32, candidate.items.len);
        errdefer gpa.free(child_icon_ids);
        @memset(child_icon_ids, 0);
        const child_icon_generations = try gpa.alloc(u32, candidate.items.len);
        errdefer gpa.free(child_icon_generations);
        @memset(child_icon_generations, 0);
        if (candidate.icon_ids.len == candidate.items.len) {
            @memcpy(child_icon_ids, candidate.icon_ids);
        }
        if (candidate.icon_generations.len == candidate.items.len) {
            @memcpy(child_icon_generations, candidate.icon_generations);
        }
        const child_icon_payloads = try gpa.alloc([]const u8, candidate.items.len);
        errdefer gpa.free(child_icon_payloads);
        @memset(child_icon_payloads, &.{});
        if (candidate.kind.len == candidate.items.len) {
            for (candidate.kind, 0..) |kind, index|
                child_kinds[index] = parseMenuRowKind(kind).?;
        }
        const parent_label = candidate.parent_label orelse
            (if (candidate.path.len != 0) candidate.path[candidate.path.len - 1].label else &.{});
        var path = try gpa.alloc(MenuPath, candidate.path.len);
        errdefer gpa.free(path);
        var path_total: usize = 0;
        for (candidate.path) |entry| path_total += entry.label.len;
        var path_owner: []u8 = &.{};
        if (path_total != 0) {
            path_owner = try gpa.alloc(u8, path_total);
        }
        errdefer if (path_owner.len != 0) gpa.free(path_owner);
        var path_offset: usize = 0;
        for (candidate.path, 0..) |entry, index| {
            if (entry.label.len != 0) {
                @memcpy(path_owner[path_offset..][0..entry.label.len], entry.label);
                path_offset += entry.label.len;
            }
            path[index] = .{ .id = entry.id, .label = path_owner[path_offset - entry.label.len ..][0..entry.label.len] };
        }
        var parent_label_owner: []u8 = &.{};
        if (parent_label.len != 0) parent_label_owner = try gpa.dupe(u8, parent_label);
        errdefer if (parent_label_owner.len != 0) gpa.free(parent_label_owner);
        var child_keys = try gpa.alloc([]const u8, candidate.items.len);
        errdefer gpa.free(child_keys);
        @memset(child_keys, &.{});
        var keys_total: usize = 0;
        for (candidate.keys) |key| {
            if (key.len > 32 or !frontend.validBoundedUtf8Line(key, 32))
                return error.InvalidMenuBarFacts;
            keys_total += key.len;
        }
        const keys_owner = try gpa.alloc(u8, keys_total);
        errdefer gpa.free(keys_owner);
        var keys_offset: usize = 0;
        for (candidate.keys, 0..) |key, index| {
            @memcpy(keys_owner[keys_offset..][0..key.len], key);
            child_keys[index] = keys_owner[keys_offset..][0..key.len];
            keys_offset += key.len;
        }
        var helps_total: usize = 0;
        for (candidate.helps) |help| {
            if (help.len != 0 and (help.len > max_menu_bar_label or
                !frontend.validBoundedUtf8Text(help, max_menu_bar_label)))
                return error.InvalidMenuBarFacts;
            helps_total += help.len;
        }
        const helps_owner = try gpa.alloc(u8, helps_total);
        errdefer gpa.free(helps_owner);
        var helps_offset: usize = 0;
        for (candidate.helps, 0..) |help, index| {
            @memcpy(helps_owner[helps_offset..][0..help.len], help);
            child_helps[index] = helps_owner[helps_offset..][0..help.len];
            helps_offset += help.len;
        }
        var decoded_payload_lengths: [max_menu_children]?usize = .{null} ** max_menu_children;
        var icon_payload_total: usize = 0;
        if (candidate.icon_payloads.len == candidate.items.len) {
            for (candidate.icon_payloads, 0..) |encoded, index| {
                if (encoded.len == 0) continue;
                const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch
                    return error.InvalidMenuBarFacts;
                if (decoded_len > max_menu_icon_payload)
                    continue;
                decoded_payload_lengths[index] = decoded_len;
                icon_payload_total += decoded_len;
            }
        }
        const icon_payloads_owner = try gpa.alloc(u8, icon_payload_total);
        errdefer gpa.free(icon_payloads_owner);
        var icon_payload_offset: usize = 0;
        if (candidate.icon_payloads.len == candidate.items.len) {
            for (candidate.icon_payloads, 0..) |encoded, index| {
                const decoded_len = decoded_payload_lengths[index] orelse continue;
                std.base64.standard.Decoder.decode(
                    icon_payloads_owner[icon_payload_offset..][0..decoded_len],
                    encoded,
                ) catch return error.InvalidMenuBarFacts;
                child_icon_payloads[index] = icon_payloads_owner[icon_payload_offset..][0..decoded_len];
                icon_payload_offset += decoded_len;
            }
        }
        var child_total: usize = 0;
        for (candidate.items) |label| {
            if (std.mem.eql(u8, label, "--")) continue;
            if (label.len == 0 or label.len > max_menu_bar_label or
                !frontend.validBoundedUtf8Text(label, max_menu_bar_label))
                return error.InvalidMenuBarFacts;
            child_total += label.len;
        }
        var child_owner = try gpa.alloc(u8, child_total);
        errdefer gpa.free(child_owner);
        var child_offset: usize = 0;
        for (candidate.items, 0..) |label, index| {
            const separate = std.mem.eql(u8, label, "--");
            if (!separate) {
                @memcpy(child_owner[child_offset..][0..label.len], label);
                child_slices[index] = child_owner[child_offset..][0..label.len];
                child_offset += label.len;
            } else {
                child_slices[index] = child_owner[child_offset..][0..0];
            }
        }
        open_menu = .{
            .item_id = candidate.item_id,
            .window_id = candidate.window_id,
            .x = candidate.x,
            .y = candidate.y,
            .width = candidate.width,
            .height = candidate.height,
            .items = child_slices,
            .enabled = child_enabled,
            .keys = child_keys,
            .keys_owner = keys_owner,
            .helps = child_helps,
            .helps_owner = helps_owner,
            .owner = child_owner,
            .submenus = child_submenus,
            .selected = child_selected,
            .kinds = child_kinds,
            .icon_ids = child_icon_ids,
            .icon_generations = child_icon_generations,
            .icon_payloads = child_icon_payloads,
            .icon_payloads_owner = icon_payloads_owner,
            .parent_id = candidate.parent_id,
            .parent_label = parent_label_owner,
            .parent_label_owner = parent_label_owner,
            .path = path,
            .path_owner = path_owner,
        };
    }

    if (wire.tool_bar.len > protocol.max_toolbar_items) return error.InvalidToolbarFacts;
    const tool_bar = try gpa.alloc(ToolbarFact, wire.tool_bar.len);
    errdefer gpa.free(tool_bar);
    var tool_total: usize = 0;
    for (wire.tool_bar) |item| {
        const kind = parseToolbarKind(item.kind) orelse return error.InvalidToolbarFacts;
        const label = item.label orelse "";
        const help = item.help orelse "";
        const key = item.key orelse "";
        const separator = kind == .separator or kind == .space;
        if (separator) {
            if (label.len != 0 or help.len != 0 or key.len != 0)
                return error.InvalidToolbarFacts;
        } else if (label.len == 0 or label.len > max_toolbar_label or
            !frontend.validBoundedUtf8Text(label, max_toolbar_label))
        {
            return error.InvalidToolbarFacts;
        }
        if (help.len != 0 and (help.len > max_toolbar_label or
            !frontend.validBoundedUtf8Text(help, max_toolbar_label)))
            return error.InvalidToolbarFacts;
        if (key.len != 0 and (key.len > max_toolbar_key or
            !frontend.validBoundedUtf8Text(key, max_toolbar_key)))
            return error.InvalidToolbarFacts;
        tool_total += label.len + help.len + key.len;
    }
    const tool_owner = try gpa.alloc(u8, tool_total);
    errdefer gpa.free(tool_owner);
    var tool_offset: usize = 0;
    for (wire.tool_bar, 0..) |item, index| {
        const kind = parseToolbarKind(item.kind).?;
        const label = item.label orelse "";
        const help = item.help orelse "";
        const key = item.key orelse "";
        var flags: u8 = 0;
        if (item.enabled) flags |= protocol.ToolbarItemFlags.enabled;
        if (item.visible) flags |= protocol.ToolbarItemFlags.visible;
        if (item.selected) flags |= protocol.ToolbarItemFlags.selected;
        @memcpy(tool_owner[tool_offset..][0..label.len], label);
        const owned_label = tool_owner[tool_offset..][0..label.len];
        tool_offset += label.len;
        @memcpy(tool_owner[tool_offset..][0..help.len], help);
        const owned_help = tool_owner[tool_offset..][0..help.len];
        tool_offset += help.len;
        @memcpy(tool_owner[tool_offset..][0..key.len], key);
        const owned_key = tool_owner[tool_offset..][0..key.len];
        tool_offset += key.len;
        tool_bar[index] = .{
            .kind = kind,
            .flags = flags,
            .label = owned_label,
            .help = owned_help,
            .key = owned_key,
        };
    }
    return .{
        .facts = .{
            .frame_width = wire.frame_width,
            .frame_height = wire.frame_height,
            .window_width = wire.window_width,
            .window_height = wire.window_height,
            .line_height = wire.line_height,
            .char_width = wire.char_width,
            .font_pixel_size = wire.font_pixel_size,
            .focused = wire.focused,
            .cursor_kind = boundedCursorKind(wire.cursor_kind),
            .default_foreground = if (wire.foreground) |text| parseFaceColor(text) else null,
            .default_background = if (wire.background) |text| parseFaceColor(text) else null,
            .mode_line_foreground = if (wire.mode_line_foreground) |text| parseFaceColor(text) else null,
            .mode_line_background = if (wire.mode_line_background) |text| parseFaceColor(text) else null,
            .mode_line_inactive_foreground = if (wire.mode_line_inactive_foreground) |text| parseFaceColor(text) else null,
            .mode_line_inactive_background = if (wire.mode_line_inactive_background) |text| parseFaceColor(text) else null,
            .header_line_foreground = if (wire.header_line_foreground) |text| parseFaceColor(text) else null,
            .header_line_background = if (wire.header_line_background) |text| parseFaceColor(text) else null,
            .tab_line_foreground = if (wire.tab_line_foreground) |text| parseFaceColor(text) else null,
            .tab_line_background = if (wire.tab_line_background) |text| parseFaceColor(text) else null,
            .tool_bar_foreground = if (wire.tool_bar_foreground) |text| parseFaceColor(text) else null,
            .tool_bar_background = if (wire.tool_bar_background) |text| parseFaceColor(text) else null,
            .mode_line_box = if (wire.mode_line_box) |text| parseBoxStyle(text).? else .none,
            .tool_bar_box = if (wire.tool_bar_box) |text| parseBoxStyle(text).? else .none,
            .mode_line_box_width = wire.mode_line_box_width,
            .tool_bar_box_width = wire.tool_bar_box_width,
            .cursor_background = if (wire.cursor_background) |text| parseFaceColor(text) else null,
            .fringe_background = if (wire.fringe_background) |text| parseFaceColor(text) else null,
            .regions = regions,
            .region_background = if (wire.region_background) |text| parseFaceColor(text) else null,
            .mouse_rects = mouse_rects,
            .mouse_background = if (wire.mouse_background) |text| parseFaceColor(text) else null,
            .line_runs = line_runs,
        },
        .windows = windows,
        .contents = contents,
        .text = .{ .lines = slices, .owner = owner },
        .cursor = wire.cursor,
        .viewport = viewport,
        .font_file = if (wire.font_file) |font_file| try gpa.dupe(u8, font_file) else null,
        .variable_font_file = if (wire.variable_font_file) |font_file| try gpa.dupe(u8, font_file) else null,
        .alt_font_files = .{
            if (alt_font_files[0]) |font_file| try gpa.dupe(u8, font_file) else null,
            if (alt_font_files[1]) |font_file| try gpa.dupe(u8, font_file) else null,
        },
        .echo = if (wire.echo) |text| try gpa.dupe(u8, text) else null,
        .line_runs = line_runs,
        .line_runs_owner = line_runs_owner,
        .menu_bar = menu_bar,
        .menu_bar_owner = menu_owner,
        .tool_bar = tool_bar,
        .tool_bar_owner = tool_owner,
        .open_menu = open_menu,
        .title = if (wire.title) |title| try gpa.dupe(u8, title) else null,
        .focused = wire.focused,
    };
}

test "unchanged facts compare equal for publisher coalescing" {
    const first = FrameFacts{ .frame_width = 80, .frame_height = 25, .window_width = 80, .window_height = 23 };
    var second = first;
    try std.testing.expect(factsEql(first, second));
    second.window_height += 1;
    try std.testing.expect(!factsEql(first, second));
}

test "parses bounded real windows into wire snapshot" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":40,"window_width":60,"window_height":30,
        \\  "windows":[
        \\    {"id":101,"index":0,"x":0,"y":0,"width":60,"height":30,"selected":false},
        \\    {"id":102,"index":1,"x":60,"y":0,"width":60,"height":30,"selected":true}
        \\  ],
        \\  "text":["Emacs","Proto-UI"],
        \\  "identity":"process_lifetime",
        \\  "cursor":{"line":1,"column":1},
        \\  "window_start_line":1,"window_visible_lines":2
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), snapshot.windows.len);
    try std.testing.expectEqual(@as(usize, 1), snapshot.windows[1].index);
    try std.testing.expectEqual(@as(i32, 60), snapshot.windows[1].x);

    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    try appendWireSnapshotWindows(
        a,
        snapshot.facts,
        snapshot.windows,
        snapshot.contents,
        snapshot.text.lines,
        snapshot.cursor,
        snapshot.viewport,
        &scene,
        &messages,
    );
    try std.testing.expectEqual(@as(usize, 2), scene.windows.items.len);
    try std.testing.expectEqual(@as(u64, 102), scene.windows.items[1].id);
    try std.testing.expectEqual(@as(u64, 101), scene.windows.items[0].id);
    try std.testing.expectEqual(@as(u64, 102), scene.text.items[0].window_id);
    try std.testing.expectEqual(@as(i32, 8), scene.cursor.?.x);
    try std.testing.expectEqual(@as(i32, 0), scene.cursor.?.y);

    // Apply a one-window snapshot against the two-window Scene. FRAME_UPDATE
    // is authoritative, so the stale ID must not survive the replacement.

    try appendWireSnapshot(
        a,
        snapshot.facts,
        snapshot.text.lines,
        snapshot.cursor,
        snapshot.viewport,
        &scene,
        &messages,
    );
    try std.testing.expectEqual(@as(usize, 1), scene.windows.items.len);
    try std.testing.expectEqual(@as(u64, 1001), scene.windows.items[0].id);

    const overlap =
        \\{"frame_width":120,"frame_height":40,"window_width":60,"window_height":30,
        \\ "windows":[{"id":101,"index":0,"x":0,"y":0,"width":70,"height":30,"selected":true},
        \\ {"id":102,"index":1,"x":60,"y":0,"width":60,"height":30,"selected":false}],
        \\ "text":["Emacs"],
        \\ "window_start_line":1,"window_visible_lines":1}
    ;
    try std.testing.expectError(error.InvalidWindowFacts, parseSnapshot(a, overlap));
}

test "projects bounded states for every window" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":40,"window_width":60,"window_height":20,
        \\  "identity":"process_lifetime",
        \\  "windows":[
        \\    {"id":101,"index":0,"x":0,"y":0,"width":60,"height":20,"selected":false},
        \\    {"id":102,"index":1,"x":60,"y":0,"width":60,"height":20,"selected":true}
        \\  ],
        \\  "window_states":[
        \\    {"id":101,"lines":["left"],"window_start_line":1,"window_visible_lines":1,
        \\     "cursor":{"line":1,"column":1},"cursor_active":false,
        \\     "mode_line":"Left","mode_line_height":2,
        \\     "header_line":"LH","header_line_height":2,
        \\     "tab_line":"LT","tab_line_height":1,
        \\     "scroll_width":12,"buffer_lines":20,"scroll_top":5,
        \\     "scroll_height":8,"hscroll":5,"hviewport":40,"hcontent":100},
        \\    {"id":102,"lines":["right"],"window_start_line":1,"window_visible_lines":1,
        \\     "cursor":{"line":1,"column":2},"cursor_active":true,
        \\     "mode_line":"Right","mode_line_height":2,
        \\     "header_line":"RH","header_line_height":2,
        \\     "tab_line":"RT","tab_line_height":1}
        \\  ],
        \\  "text":["right"],
        \\  "window_start_line":1,"window_visible_lines":1
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), snapshot.contents.len);

    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    try appendWireSnapshotWindows(
        a,
        snapshot.facts,
        snapshot.windows,
        snapshot.contents,
        snapshot.text.lines,
        snapshot.cursor,
        snapshot.viewport,
        &scene,
        &messages,
    );
    try std.testing.expectEqual(@as(usize, 2), scene.windows.items.len);
    try std.testing.expectEqual(@as(usize, 30), scene.rows.items.len);
    try std.testing.expectEqual(@as(usize, 2), scene.text.items.len);
    try std.testing.expectEqual(@as(u64, 101), scene.text.items[0].window_id);
    try std.testing.expectEqual(@as(u64, 102), scene.text.items[1].window_id);
    try std.testing.expectEqual(@as(usize, 2), scene.cursor_count);
    try std.testing.expectEqual(@as(u64, 101), scene.cursors[0].window_id);
    try std.testing.expect(!scene.cursors[0].active);
    try std.testing.expectEqual(@as(u64, 102), scene.cursor.?.window_id);
    try std.testing.expect(scene.cursor.?.active);
    try std.testing.expectEqual(@as(usize, 2), scene.mode_line_count);
    try std.testing.expectEqualStrings("Left", scene.mode_lines[0].bytes[0..scene.mode_lines[0].len]);
    try std.testing.expectEqualStrings("Right", scene.mode_lines[1].bytes[0..scene.mode_lines[1].len]);
    try std.testing.expectEqual(@as(usize, 4), scene.aux_line_count);
    try std.testing.expectEqualStrings("LH", scene.aux_lines[0].bytes[0..scene.aux_lines[0].len]);
    try std.testing.expectEqual(frontend.aux_line_header, scene.aux_lines[0].flags);
    try std.testing.expectEqualStrings("LT", scene.aux_lines[1].bytes[0..scene.aux_lines[1].len]);
    try std.testing.expectEqual(frontend.aux_line_tab, scene.aux_lines[1].flags);
    try std.testing.expectEqual(@as(usize, 2), scene.scroll_states.items.len);
    try std.testing.expectEqual(@as(u64, 101), scene.scroll_states.items[0].window_id);
    try std.testing.expectEqual(@as(u32, 12), scene.scroll_states.items[0].track_width);
    try std.testing.expectEqual(@as(u32, 20), scene.scroll_states.items[0].content_size);
    try std.testing.expectEqual(@as(u32, 1), scene.scroll_states.items[0].viewport_size);
    try std.testing.expectEqual(@as(u32, 5), scene.scroll_states.items[0].position);
    try std.testing.expectEqual(
        frontend.WindowScrollFlags.horizontal_visible,
        scene.scroll_states.items[1].flags,
    );
    try std.testing.expectEqual(@as(u64, 101), scene.scroll_states.items[1].window_id);
    try std.testing.expectEqual(@as(u32, 8), scene.scroll_states.items[1].track_width);
    try std.testing.expectEqual(@as(u32, 100), scene.scroll_states.items[1].content_size);
    try std.testing.expectEqual(@as(u32, 40), scene.scroll_states.items[1].viewport_size);
    try std.testing.expectEqual(@as(u32, 5), scene.scroll_states.items[1].position);

    const short_split =
        \\{
        \\  "frame_width":120,"frame_height":40,"window_width":60,"window_height":3,
        \\  "identity":"process_lifetime",
        \\  "windows":[
        \\    {"id":101,"index":0,"x":0,"y":0,"width":60,"height":3,"selected":false},
        \\    {"id":102,"index":1,"x":60,"y":0,"width":60,"height":3,"selected":true}
        \\  ],
        \\  "window_states":[
        \\    {"id":101,"lines":["left","extra-1","extra-2","extra-3"],"window_start_line":1,"window_visible_lines":4,
        \\     "cursor":{"line":1,"column":1},"cursor_active":false},
        \\    {"id":102,"lines":["right","extra-1","extra-2","extra-3"],"window_start_line":1,"window_visible_lines":4,
        \\     "cursor":{"line":1,"column":1},"cursor_active":true}
        \\  ],
        \\  "text":["right"],
        \\  "window_start_line":1,"window_visible_lines":1
        \\}
    ;
    var short_snapshot = try parseSnapshot(a, short_split);
    defer short_snapshot.deinit(a);
    var short_scene = frontend.Scene.init(a);
    defer short_scene.deinit();
    var short_messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (short_messages.items) |message| a.free(message);
        short_messages.deinit(a);
    }
    try appendWireSnapshotWindows(
        a,
        short_snapshot.facts,
        short_snapshot.windows,
        short_snapshot.contents,
        short_snapshot.text.lines,
        short_snapshot.cursor,
        short_snapshot.viewport,
        &short_scene,
        &short_messages,
    );
    try std.testing.expectEqual(@as(usize, 6), short_scene.rows.items.len);
    try std.testing.expectEqual(@as(i32, 1), short_scene.rows.items[0].height);
    try std.testing.expectEqual(@as(i32, 1), short_scene.rows.items[5].height);
    try std.testing.expectEqual(@as(usize, 6), short_scene.text.items.len);

    const combined_overflow =
        \\{"frame_width":120,"frame_height":40,"window_width":120,"window_height":20,
        \\ "identity":"process_lifetime",
        \\ "windows":[{"id":101,"index":0,"x":0,"y":0,"width":120,"height":20,"selected":true}],
        \\ "window_states":[
        \\  {"id":101,"lines":["left"],"window_start_line":1,"window_visible_lines":1,
        \\   "header_line":"H","header_line_height":12,
        \\   "tab_line":"T","tab_line_height":12}],
        \\ "text":["left"],"window_start_line":1,"window_visible_lines":1}
    ;
    try std.testing.expectError(error.InvalidAuxLineFacts, parseSnapshot(a, combined_overflow));

    const duplicate =
        \\{"frame_width":120,"frame_height":40,"window_width":60,"window_height":20,
        \\ "identity":"process_lifetime",
        \\ "windows":[{"id":101,"index":0,"x":0,"y":0,"width":60,"height":20,"selected":false},
        \\ {"id":102,"index":1,"x":60,"y":0,"width":60,"height":20,"selected":true}],
        \\ "window_states":[{"id":101,"lines":[],"window_start_line":1,"window_visible_lines":0}],
        \\ "text":[],"window_start_line":1,"window_visible_lines":0}
    ;
    try std.testing.expectError(error.InvalidWindowContent, parseSnapshot(a, duplicate));

    const active_non_selected =
        \\{"frame_width":120,"frame_height":40,"window_width":60,"window_height":20,
        \\ "identity":"process_lifetime",
        \\ "windows":[{"id":101,"index":0,"x":0,"y":0,"width":60,"height":20,"selected":false},
        \\ {"id":102,"index":1,"x":60,"y":0,"width":60,"height":20,"selected":true}],
        \\ "window_states":[
        \\  {"id":101,"lines":["left"],"window_start_line":1,"window_visible_lines":1,
        \\   "cursor":{"line":1,"column":1},"cursor_active":true},
        \\  {"id":102,"lines":["right"],"window_start_line":1,"window_visible_lines":1}],
        \\ "text":["right"],"window_start_line":1,"window_visible_lines":1}
    ;
    try std.testing.expectError(error.InvalidCursorFacts, parseSnapshot(a, active_non_selected));

    const dangling_active =
        \\{"frame_width":120,"frame_height":40,"window_width":120,"window_height":20,
        \\ "identity":"process_lifetime",
        \\ "windows":[{"id":101,"index":0,"x":0,"y":0,"width":120,"height":20,"selected":true}],
        \\ "window_states":[
        \\  {"id":101,"lines":["left"],"window_start_line":1,"window_visible_lines":1,
        \\   "cursor_active":true}],
        \\ "text":["left"],"window_start_line":1,"window_visible_lines":1}
    ;
    try std.testing.expectError(error.InvalidCursorFacts, parseSnapshot(a, dangling_active));

    const oversized_cursor =
        \\{"frame_width":120,"frame_height":40,"window_width":9,"window_height":20,
        \\ "identity":"process_lifetime",
        \\ "windows":[{"id":101,"index":0,"x":0,"y":0,"width":9,"height":20,"selected":true}],
        \\ "window_states":[
        \\  {"id":101,"lines":["left"],"window_start_line":1,"window_visible_lines":1,
        \\   "cursor":{"line":1,"column":1},"cursor_active":true}],
        \\ "text":["left"],"window_start_line":1,"window_visible_lines":1}
    ;
    try std.testing.expectError(error.InvalidCursorFacts, parseSnapshot(a, oversized_cursor));

    const short_window_cursor =
        \\{"frame_width":120,"frame_height":40,"window_width":120,"window_height":3,
        \\ "identity":"process_lifetime",
        \\ "windows":[{"id":101,"index":0,"x":0,"y":0,"width":120,"height":3,"selected":true}],
        \\ "window_states":[
        \\  {"id":101,"lines":["a","b","c"],"window_start_line":1,"window_visible_lines":3,
        \\   "cursor":{"line":3,"column":0},"cursor_active":true}],
        \\ "text":["a","b","c"],"window_start_line":1,"window_visible_lines":3}
    ;
    try std.testing.expectError(error.InvalidCursorFacts, parseSnapshot(a, short_window_cursor));
}

test "mode-line projection is all-or-nothing with selected mode line" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":40,"window_width":60,"window_height":20,
        \\  "identity":"process_lifetime",
        \\  "windows":[
        \\    {"id":101,"index":0,"x":0,"y":0,"width":60,"height":20,"selected":false},
        \\    {"id":102,"index":1,"x":60,"y":0,"width":60,"height":20,"selected":true}
        \\  ],
        \\  "window_states":[
        \\    {"id":101,"lines":["left"],"window_start_line":1,"window_visible_lines":1,
        \\     "mode_line":"Left","mode_line_height":2},
        \\    {"id":102,"lines":["right"],"window_start_line":1,"window_visible_lines":1}
        \\  ],
        \\  "text":["right"],
        \\  "window_start_line":1,"window_visible_lines":1
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    try appendWireSnapshotWindows(
        a,
        snapshot.facts,
        snapshot.windows,
        snapshot.contents,
        snapshot.text.lines,
        snapshot.cursor,
        snapshot.viewport,
        &scene,
        &messages,
    );
    try std.testing.expectEqual(@as(usize, 0), scene.mode_line_count);
}

test "aux-line projection rejects direct combined overflow safely" {
    const a = std.testing.allocator;
    const facts = FrameFacts{ .frame_width = 100, .frame_height = 20, .window_width = 100, .window_height = 20 };
    const windows = [_]WindowFact{.{ .id = 101, .index = 0, .x = 0, .y = 0, .width = 100, .height = 20, .selected = true }};
    var header_owner: [1]u8 = undefined;
    header_owner[0] = 'H';
    var tab_owner: [1]u8 = undefined;
    tab_owner[0] = 'T';
    const max_height = std.math.maxInt(i32);
    const contents = [_]WindowContent{.{
        .id = 101,
        .text = .{},
        .viewport = .{ .start_line = 1, .line_count = 0 },
        .header_line = header_owner[0..1],
        .header_line_height = max_height,
        .tab_line = tab_owner[0..1],
        .tab_line_height = max_height,
    }};
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    try std.testing.expectError(error.InvalidAuxLineFacts, appendWireSnapshotWindows(
        a,
        facts,
        &windows,
        &contents,
        &.{},
        .{ .line = 1, .column = 0 },
        .{ .start_line = 1, .line_count = 0 },
        &scene,
        &messages,
    ));
}

test "unsafe omitted aux line preserves the remaining snapshot" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":40,"window_width":60,"window_height":20,
        \\  "identity":"process_lifetime",
        \\  "windows":[
        \\    {"id":101,"index":0,"x":0,"y":0,"width":60,"height":20,"selected":false},
        \\    {"id":102,"index":1,"x":60,"y":0,"width":60,"height":20,"selected":true}
        \\  ],
        \\  "window_states":[
        \\    {"id":101,"lines":["left"],"window_start_line":1,"window_visible_lines":1},
        \\    {"id":102,"lines":["right"],"window_start_line":1,"window_visible_lines":1,
        \\     "header_line":null,"header_line_height":0,
        \\     "tab_line":"Right tab","tab_line_height":2}
        \\  ],
        \\  "text":["right"],
        \\  "window_start_line":1,"window_visible_lines":1
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    try appendWireSnapshotWindows(
        a,
        snapshot.facts,
        snapshot.windows,
        snapshot.contents,
        snapshot.text.lines,
        snapshot.cursor,
        snapshot.viewport,
        &scene,
        &messages,
    );
    try std.testing.expectEqual(@as(usize, 1), scene.aux_line_count);
    try std.testing.expectEqual(frontend.aux_line_tab, scene.aux_lines[0].flags);
    try std.testing.expectEqualStrings("Right tab", scene.aux_lines[0].bytes[0..scene.aux_lines[0].len]);
}

test "real window snapshot rejects malformed identities" {
    const a = std.testing.allocator;
    const duplicate =
        \\{"frame_width":120,"frame_height":40,"window_width":60,"window_height":30,
        \\ "identity":"process_lifetime",
        \\ "windows":[{"id":101,"index":0,"x":0,"y":0,"width":60,"height":30,"selected":true},
        \\ {"id":101,"index":1,"x":60,"y":0,"width":60,"height":30,"selected":false}],
        \\ "text":["Emacs"],
        \\ "window_start_line":1,"window_visible_lines":1}
    ;
    try std.testing.expectError(error.InvalidWindowFacts, parseSnapshot(a, duplicate));

    const zero =
        \\{"frame_width":120,"frame_height":40,"window_width":120,"window_height":30,
        \\ "identity":"process_lifetime",
        \\ "windows":[{"id":0,"index":0,"x":0,"y":0,"width":120,"height":30,"selected":true}],
        \\ "text":["Emacs"],
        \\ "window_start_line":1,"window_visible_lines":1}
    ;
    try std.testing.expectError(error.InvalidWindowFacts, parseSnapshot(a, zero));

    const wrong_marker =
        \\{"frame_width":120,"frame_height":40,"window_width":60,"window_height":30,
        \\ "identity":"per_call_only",
        \\ "windows":[{"id":101,"index":0,"x":0,"y":0,"width":60,"height":30,"selected":true},
        \\ {"id":102,"index":1,"x":60,"y":0,"width":60,"height":30,"selected":false}],
        \\ "text":["Emacs"],
        \\ "window_start_line":1,"window_visible_lines":1}
    ;
    try std.testing.expectError(error.InvalidWindowFacts, parseSnapshot(a, wrong_marker));

    const states_without_windows =
        \\{"frame_width":120,"frame_height":40,"window_width":120,"window_height":30,
        \\ "identity":"process_lifetime",
        \\ "window_states":[{"id":101,"lines":["bad"],"window_start_line":1,"window_visible_lines":1}],
        \\ "text":[],"window_start_line":1,"window_visible_lines":0}
    ;
    try std.testing.expectError(error.InvalidWindowFacts, parseSnapshot(a, states_without_windows));
}

pub fn buildScene(gpa: std.mem.Allocator, facts: FrameFacts, snapshot_index: u64) !frontend.Scene {
    if (facts.frame_width <= 0 or facts.frame_height <= 0 or
        facts.window_width <= 0 or facts.window_height <= 0 or
        facts.window_width > facts.frame_width or
        facts.window_height > facts.frame_height) return error.InvalidFrameFacts;

    var scene = frontend.Scene.init(gpa);
    errdefer scene.deinit();
    const sequence: u64 = std.math.mul(u64, snapshot_index, 2) catch return error.OutOfMemory;
    const create_sequence = sequence + 1;
    const update_sequence = sequence + 2;

    var create_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, create_payload[0..4], 1, .little);
    std.mem.writeInt(u32, create_payload[4..8], 1, .little);
    var create_message: std.ArrayList(u8) = .empty;
    defer create_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_create,
        .sequence = create_sequence,
        .ack_sequence = 0,
        .session_id = 0x1001,
        .frame_id = 1,
        .timestamp_ns = create_sequence,
    }, &create_payload, &create_message);
    try scene.apply(create_message.items);

    var window_bytes: std.ArrayList(u8) = .empty;
    defer window_bytes.deinit(gpa);
    try frontend.encodeWindow(gpa, .{
        .id = 1001,
        .frame_id = 1,
        .x = 0,
        .y = 0,
        .width = facts.window_width,
        .height = facts.window_height,
    }, &window_bytes);

    var row_bytes: std.ArrayList(u8) = .empty;
    defer row_bytes.deinit(gpa);
    const row_count: i32 = visibleRowCount(facts.window_height, facts.line_height);
    const row_height = visibleRowHeight(facts.window_height, facts.line_height);
    var row_index: i32 = 0;
    while (row_index < row_count) : (row_index += 1) {
        try frontend.encodeRow(gpa, .{
            .window_id = 1001,
            .index = @intCast(row_index),
            .flags = 0,
            .x = 0,
            .y = row_index * row_height,
            .width = facts.window_width,
            .height = row_height,
            .ascent = @min(16, row_height),
            .descent = row_height - @min(16, row_height),
            .baseline = @min(16, row_height),
            .visible_height = row_height,
        }, &row_bytes);
    }

    var cursor_bytes: std.ArrayList(u8) = .empty;
    defer cursor_bytes.deinit(gpa);
    try frontend.encodeCursor(gpa, .{
        .window_id = 1001,
        .x = 8,
        .y = row_height,
        .width = 2,
        .height = @max(2, @min(18, row_height)),
        .kind = facts.cursor_kind,
        .visible = true,
        .active = true,
    }, &cursor_bytes);

    var damage_bytes: std.ArrayList(u8) = .empty;
    defer damage_bytes.deinit(gpa);
    try frontend.encodeRect(gpa, .{
        .x = 0,
        .y = 0,
        .width = facts.frame_width,
        .height = facts.frame_height,
    }, &damage_bytes);

    var present_bytes: std.ArrayList(u8) = .empty;
    defer present_bytes.deinit(gpa);
    try frontend.encodePresentHint(gpa, .{
        .mode = 0,
        .flags = 0,
        .deadline_ns = 0,
    }, &present_bytes);

    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = window_bytes.items },
        .{ .kind = protocol.SectionKind.rows, .records = row_bytes.items },
        .{ .kind = protocol.SectionKind.cursors, .records = cursor_bytes.items },
        .{ .kind = protocol.SectionKind.damage, .records = damage_bytes.items },
        .{ .kind = protocol.SectionKind.present_hint, .records = present_bytes.items },
    };
    var update_payload: std.ArrayList(u8) = .empty;
    defer update_payload.deinit(gpa);
    try protocol.encodeFrameUpdate(gpa, .{
        .header = .{
            .frame_id = 1,
            .frame_generation = 1,
            .sequence = update_sequence,
            .redisplay_generation = snapshot_index + 1,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = facts.frame_width,
            .logical_height = facts.frame_height,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = facts.frame_width,
            .physical_height = facts.frame_height,
            .scale = 1,
            .dpi_x = 96,
            .dpi_y = 96,
            .damage_mode = 2,
            .update_cause = 1,
            .coalesced_count = 0,
            .timestamp_ns = update_sequence,
        },
        .sections = &sections,
    }, &update_payload);
    var update_message: std.ArrayList(u8) = .empty;
    defer update_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.delta | protocol.Flags.coalescable,
        .message_type = protocol.Message.frame_update,
        .sequence = update_sequence,
        .ack_sequence = 0,
        .session_id = 0x1001,
        .frame_id = 1,
        .timestamp_ns = update_sequence,
    }, update_payload.items, &update_message);
    try scene.apply(update_message.items);
    if (scene.stats.frame_updates != 1) return error.InvalidFrameFacts;
    return scene;
}

/// Encodes and validates a transport snapshot in `scene`, returning owned EUP
/// messages. The first snapshot includes `FRAME_CREATE`; later ones are
/// update-only and inherit the scene's contiguous sequence.
pub fn appendWireSnapshot(
    gpa: std.mem.Allocator,
    facts: FrameFacts,
    text: []const []const u8,
    cursor: CursorFacts,
    viewport: ViewportFacts,
    scene: *frontend.Scene,
    messages: *std.ArrayList([]const u8),
) !void {
    return appendWireSnapshotWindows(gpa, facts, &.{}, &.{}, text, cursor, viewport, scene, messages);
}

pub fn appendTitleMessages(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    title: []const u8,
    messages: *std.ArrayList([]const u8),
) !void {
    if (title.len == 0 or title.len > max_text_columns or
        !frontend.validBoundedUtf8Text(title, max_text_columns)) return error.InvalidTitleFacts;
    const sequence = scene.next_sequence orelse return error.InvalidTitleFacts;
    if (sequence > std.math.maxInt(u32) - 1) return error.InvalidTitleFacts;
    const generation: u32 = @intCast(sequence);
    const frame_generation = scene.frame orelse return error.InvalidTitleFacts;

    var string_payload: std.ArrayList(u8) = .empty;
    defer string_payload.deinit(gpa);
    try protocol.encodeStringDefine(gpa, .{
        .resource_id = 9001,
        .generation = generation,
        .bytes = title,
    }, &string_payload);
    var string_message: std.ArrayList(u8) = .empty;
    defer string_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.string_define,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = scene.session_id orelse 0x1001,
        .frame_id = 1,
        .timestamp_ns = sequence,
    }, string_payload.items, &string_message);
    try messages.append(gpa, try gpa.dupe(u8, string_message.items));
    try scene.apply(string_message.items);

    var title_payload: std.ArrayList(u8) = .empty;
    defer title_payload.deinit(gpa);
    try protocol.encodeFrameTitle(gpa, .{
        .string_resource_id = 9001,
        .string_generation = generation,
        .frame_generation = frame_generation.generation,
    }, &title_payload);
    var title_message: std.ArrayList(u8) = .empty;
    defer title_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_title,
        .sequence = sequence + 1,
        .ack_sequence = 0,
        .session_id = scene.session_id orelse 0x1001,
        .frame_id = 1,
        .timestamp_ns = sequence + 1,
    }, title_payload.items, &title_message);
    try messages.append(gpa, try gpa.dupe(u8, title_message.items));
    try scene.apply(title_message.items);
}

pub fn appendWireSnapshotWindows(
    gpa: std.mem.Allocator,
    facts: FrameFacts,
    windows: []const WindowFact,
    contents: []const WindowContent,
    text: []const []const u8,
    cursor: CursorFacts,
    viewport: ViewportFacts,
    scene: *frontend.Scene,
    messages: *std.ArrayList([]const u8),
) !void {
    if (facts.frame_width <= 0 or facts.frame_height <= 0 or
        facts.window_width <= 0 or facts.window_height <= 0 or
        facts.window_width > facts.frame_width or
        facts.window_height > facts.frame_height) return error.InvalidFrameFacts;

    const initial = scene.frame == null;
    var sequence = scene.next_sequence orelse 1;

    if (initial) {
        var create_payload: [8]u8 = undefined;
        std.mem.writeInt(u32, create_payload[0..4], 1, .little);
        std.mem.writeInt(u32, create_payload[4..8], 1, .little);
        var create_message: std.ArrayList(u8) = .empty;
        defer create_message.deinit(gpa);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.frame_create,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = 0x1001,
            .frame_id = 1,
            .timestamp_ns = sequence,
        }, &create_payload, &create_message);
        const retained_create = try gpa.dupe(u8, create_message.items);
        messages.append(gpa, retained_create) catch |err| {
            gpa.free(retained_create);
            return err;
        };
        try scene.apply(retained_create);
        sequence += 1;
    }

    const observed_focus = if (scene.frames.lookup(1)) |frame| frame.focused else false;
    if (facts.focused != observed_focus) {
        var focus_payload: std.ArrayList(u8) = .empty;
        defer focus_payload.deinit(gpa);
        try protocol.encodeFrameFocus(gpa, .{
            .frame_id = 1,
            .frame_generation = 1,
            .focused = facts.focused,
        }, &focus_payload);
        var focus_message: std.ArrayList(u8) = .empty;
        defer focus_message.deinit(gpa);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.frame_focus,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = 0x1001,
            .frame_id = 1,
            .timestamp_ns = sequence,
        }, focus_payload.items, &focus_message);
        const retained_focus = try gpa.dupe(u8, focus_message.items);
        messages.append(gpa, retained_focus) catch |err| {
            gpa.free(retained_focus);
            return err;
        };
        try scene.apply(retained_focus);
        sequence += 1;
    }

    const update_sequence = sequence;
    const snapshot_wire: SnapshotWire = .{
        .frame_width = facts.frame_width,
        .frame_height = facts.frame_height,
        .window_width = facts.window_width,
        .window_height = facts.window_height,
        .focused = facts.focused,
    };
    var selected: WindowFact = .{
        .id = 1001,
        .index = 0,
        .x = 0,
        .y = 0,
        .width = facts.window_width,
        .height = facts.window_height,
        .selected = true,
    };
    if (windows.len != 0) try validateWindowSet(windows, snapshot_wire);
    for (windows) |item| {
        if (item.selected) selected = item;
    }
    var effective_windows = windows;
    if (effective_windows.len == 0) effective_windows = &[_]WindowFact{selected};

    var window_bytes: std.ArrayList(u8) = .empty;
    defer window_bytes.deinit(gpa);
    if (effective_windows.len == 0) {
        try frontend.encodeWindow(gpa, .{
            .id = 1001,
            .frame_id = 1,
            .x = 0,
            .y = 0,
            .width = facts.window_width,
            .height = facts.window_height,
        }, &window_bytes);
    } else {
        for (effective_windows) |item| {
            const id: u32 = item.id;
            try frontend.encodeWindow(gpa, .{
                .id = id,
                .frame_id = 1,
                .x = item.x,
                .y = item.y,
                .width = item.width,
                .height = item.height,
            }, &window_bytes);
        }
    }

    var row_bytes: std.ArrayList(u8) = .empty;
    defer row_bytes.deinit(gpa);
    var mode_line_bytes: std.ArrayList(u8) = .empty;
    defer mode_line_bytes.deinit(gpa);
    var aux_line_bytes: std.ArrayList(u8) = .empty;
    defer aux_line_bytes.deinit(gpa);
    if (!viewport.valid()) return error.InvalidViewportFacts;
    const fallback_content: WindowContent = .{
        .id = selected.id,
        .text = .{ .lines = @constCast(text), .owner = &.{} },
        .viewport = viewport,
    };
    var publish_mode_lines = false;
    for (contents) |content| {
        if (content.id == selected.id and content.mode_line != null and
            content.mode_line_height > 0)
            publish_mode_lines = true;
    }
    for (effective_windows) |window| {
        var content = fallback_content;
        var found = false;
        if (contents.len != 0) {
            for (contents) |candidate| {
                if (candidate.id == window.id) {
                    content = candidate;
                    found = true;
                    break;
                }
            } else continue;
        }
        // Small real windows cannot contain fifteen positive-height rows.
        // Use one pixel per row below 15 rows, then the normal 15-row
        // floor-division layout.
        const row_count: i32 = visibleRowCount(window.height, facts.line_height);
        const row_height = visibleRowHeight(window.height, facts.line_height);
        // A display-backed window reserves its fringe columns and its scroll
        // bar, so rows (and the text drawn from them) start after the left
        // fringe and stop before the scroll bar instead of running under them.
        const row_x: i32 = content.fringe_left;
        const row_width: i32 = @max(8, window.width - content.fringe_left -
            content.fringe_right - content.scroll_width);
        var row_index: i32 = 0;
        while (row_index < row_count) : (row_index += 1) {
            try frontend.encodeRow(gpa, .{
                .window_id = window.id,
                .index = @intCast(row_index),
                .flags = 0,
                .x = row_x,
                .y = row_index * row_height,
                .width = row_width,
                .height = row_height,
                .ascent = @min(16, row_height),
                .descent = row_height - @min(16, row_height),
                .baseline = @min(16, row_height),
                .visible_height = row_height,
            }, &row_bytes);
        }
        const published_mode_line = if (publish_mode_lines) content.mode_line else null;
        if (published_mode_line) |line| {
            if (content.mode_line_height <= 0 or content.mode_line_height > window.height)
                return error.InvalidModeLineFacts;
            if (line.len > max_text_columns) return error.InvalidModeLineFacts;
            try frontend.encodeModeLineV1(gpa, .{
                .window_id = window.id,
                .x = 0,
                .y = window.height - content.mode_line_height,
                .width = @max(8, window.width - content.scroll_width),
                .height = content.mode_line_height,
                .flags = if (window.selected) frontend.mode_line_active else 0,
                .line = line,
            }, &mode_line_bytes);
        }
        if (content.header_line != null and content.tab_line != null) {
            const combined = @addWithOverflow(content.header_line_height, content.tab_line_height);
            if (combined[1] != 0 or combined[0] > window.height)
                return error.InvalidAuxLineFacts;
        }
        inline for (.{ .{ frontend.aux_line_header, content.header_line, content.header_line_height }, .{ frontend.aux_line_tab, content.tab_line, content.tab_line_height } }) |aux| {
            if (aux[1]) |line| {
                const height = aux[2];
                const y = if (aux[0] == frontend.aux_line_tab and content.header_line != null)
                    content.header_line_height
                else
                    0;
                if (height <= 0 or height > window.height) return error.InvalidAuxLineFacts;
                try frontend.encodeWindowAuxLineV1(gpa, .{
                    .window_id = window.id,
                    .x = 0,
                    .y = y,
                    .width = @max(8, window.width - content.scroll_width),
                    .height = height,
                    .flags = aux[0],
                    .line = line,
                }, &aux_line_bytes);
            }
        }
    }
    const selected_row_count: i32 = visibleRowCount(facts.window_height, facts.line_height);
    const wire_viewport: ViewportFacts = .{
        .start_line = viewport.start_line,
        .line_count = @min(viewport.line_count, selected_row_count),
    };
    if (cursor.line < 1 or cursor.column < 0) return error.InvalidCursorFacts;

    var cursor_bytes: std.ArrayList(u8) = .empty;
    defer cursor_bytes.deinit(gpa);
    var active_cursor_count: usize = 0;
    for (effective_windows) |window| {
        var content = fallback_content;
        var found = false;
        if (contents.len != 0) {
            for (contents) |candidate| {
                if (candidate.id == window.id) {
                    content = candidate;
                    found = true;
                    break;
                }
            } else continue;
        }
        const row_height = visibleRowHeight(window.height, facts.line_height);
        var wire_cursor: ?CursorFacts = null;
        var wire_cursor_active = false;
        if (found) {
            wire_cursor = content.cursor;
            wire_cursor_active = content.cursor_active;
        }
        if (wire_cursor == null and window.selected) {
            wire_cursor = cursor;
            wire_cursor_active = true;
        }
        const bounded_cursor = wire_cursor orelse continue;
        if (!window.selected and wire_cursor_active) return error.InvalidCursorFacts;
        // The cursor is geometry, not a contract: clamp it into the window
        // instead of failing the whole snapshot when a producer reports a
        // position the window cannot hold (a short window or a far-right
        // column), which would otherwise blank the mirror.
        const window_rows = @max(1, visibleRowCount(window.height, facts.line_height));
        const cursor_line = std.math.clamp(bounded_cursor.line, 1, window_rows);
        const cursor_max_column = @max(0, @divTrunc(
            window.width - content.fringe_left - cursor_width(facts.char_width),
            cursorCellWidth(facts.char_width),
        ));
        const cursor_column = std.math.clamp(bounded_cursor.column, 0, cursor_max_column);
        if (wire_cursor_active) active_cursor_count += 1;
        try frontend.encodeCursor(gpa, .{
            .window_id = window.id,
            // Prefer a producer run's P163 pixel geometry; that keeps the
            // caret aligned inside variable-pitch text.  Cell geometry remains
            // the fallback for rows without a matching run.
            .x = content.fringe_left +
                (runAwareCursorOffset(facts, window.id, cursor_line - 1, cursor_column) orelse
                    cursor_column * cursorCellWidth(facts.char_width)),
            .y = (cursor_line - 1) * row_height,
            .width = cursor_width(facts.char_width),
            .height = @max(2, @min(18, row_height)),
            .kind = facts.cursor_kind,
            .visible = true,
            .active = wire_cursor_active,
        }, &cursor_bytes);
    }
    if (active_cursor_count != 1) return error.InvalidCursorFacts;

    var damage_bytes: std.ArrayList(u8) = .empty;
    defer damage_bytes.deinit(gpa);
    try frontend.encodeRect(gpa, .{
        .x = 0,
        .y = 0,
        .width = facts.frame_width,
        .height = facts.frame_height,
    }, &damage_bytes);

    var present_bytes: std.ArrayList(u8) = .empty;
    defer present_bytes.deinit(gpa);
    try frontend.encodePresentHint(gpa, .{
        .mode = 0,
        .flags = 0,
        .deadline_ns = 0,
    }, &present_bytes);

    var wire_viewport_bytes: [8]u8 = undefined;
    std.mem.writeInt(i32, wire_viewport_bytes[0..4], wire_viewport.start_line, .little);
    std.mem.writeInt(i32, wire_viewport_bytes[4..8], wire_viewport.line_count, .little);

    var text_bytes: std.ArrayList(u8) = .empty;
    defer text_bytes.deinit(gpa);
    var total_text_lines: usize = 0;
    for (effective_windows) |window| {
        var content = fallback_content;
        var found = false;
        for (contents) |candidate| {
            if (candidate.id == window.id) {
                content = candidate;
                found = true;
                break;
            }
        }
        if (!found and (contents.len != 0 or window.id != selected.id)) continue;
        if (content.text.lines.len > max_lines_per_window) return error.InvalidWindowContent;
        total_text_lines += content.text.lines.len;
        if (total_text_lines > max_total_text_lines) return error.InvalidWindowContent;
        for (content.text.lines, 0..) |line, index| {
            if (index >= visibleRowCount(window.height, facts.line_height)) break;
            if (line.len > frontend.max_row_columns) return error.InvalidTextFacts;
            // A blank display row carries no text line; the row stays blank
            // while every later row keeps its index, so preserving an empty
            // line cannot shift the rows after it.
            if (line.len == 0) continue;
            try frontend.encodeTextLineV2(gpa, .{
                .window_id = window.id,
                .row_index = @intCast(index),
                .line = line,
            }, &text_bytes);
        }
    }

    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = window_bytes.items },
        .{ .kind = protocol.SectionKind.rows, .records = row_bytes.items },
        .{ .kind = protocol.SectionKind.cursors, .records = cursor_bytes.items },
        .{ .kind = protocol.SectionKind.extension_min + 1, .records = &wire_viewport_bytes },
        .{ .kind = protocol.SectionKind.extension_min + 2, .records = text_bytes.items },
        .{ .kind = protocol.SectionKind.extension_min + 3, .records = mode_line_bytes.items },
        .{ .kind = protocol.SectionKind.extension_min + 4, .records = aux_line_bytes.items },
        .{ .kind = protocol.SectionKind.damage, .records = damage_bytes.items },
        .{ .kind = protocol.SectionKind.present_hint, .records = present_bytes.items },
    };
    var update_payload: std.ArrayList(u8) = .empty;
    defer update_payload.deinit(gpa);
    try protocol.encodeFrameUpdate(gpa, .{
        .header = .{
            .frame_id = 1,
            .frame_generation = 1,
            .sequence = update_sequence,
            .redisplay_generation = scene.stats.frame_updates + 1,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = facts.frame_width,
            .logical_height = facts.frame_height,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = facts.frame_width,
            .physical_height = facts.frame_height,
            .scale = 1,
            .dpi_x = 96,
            .dpi_y = 96,
            .damage_mode = 2,
            .update_cause = 1,
            .coalesced_count = 0,
            .timestamp_ns = update_sequence,
        },
        .sections = &sections,
    }, &update_payload);

    var update_message: std.ArrayList(u8) = .empty;
    defer update_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.delta | protocol.Flags.coalescable,
        .message_type = protocol.Message.frame_update,
        .sequence = update_sequence,
        .ack_sequence = 0,
        .session_id = scene.session_id orelse 0x1001,
        .frame_id = 1,
        .timestamp_ns = update_sequence,
    }, update_payload.items, &update_message);
    const retained_update = try gpa.dupe(u8, update_message.items);
    messages.append(gpa, retained_update) catch |err| {
        gpa.free(retained_update);
        return err;
    };
    try scene.apply(retained_update);

    // A live default face keeps the SDL window on Emacs's own colors.  The face
    // generation only advances when the reported colors actually change, and a
    // window binding is only resent when it would change, so an unchanged
    // snapshot adds no traffic.
    if (facts.default_foreground != null or facts.default_background != null) {
        const foreground = facts.default_foreground orelse [4]u8{ 0, 0, 0, 0 };
        const background = facts.default_background orelse [4]u8{ 0, 0, 0, 0 };
        const current = scene.faces.lookup(default_face_id);
        const changed = if (current) |existing|
            existing.payload.presence.foreground != (facts.default_foreground != null) or
                existing.payload.presence.background != (facts.default_background != null) or
                !std.meta.eql(existing.payload.foreground, foreground) or
                !std.meta.eql(existing.payload.background, background)
        else
            true;
        var face_generation: u32 = if (current) |existing| existing.generation else 0;
        var face_sequence = update_sequence + 1;
        if (changed) {
            face_generation += 1;
            var face_payload: std.ArrayList(u8) = .empty;
            defer face_payload.deinit(gpa);
            try protocol.encodeFaceDefine(gpa, .{
                .face_id = default_face_id,
                .generation = face_generation,
                .presence = .{
                    .foreground = facts.default_foreground != null,
                    .background = facts.default_background != null,
                },
                .foreground = foreground,
                .background = background,
            }, &face_payload);
            var face_message: std.ArrayList(u8) = .empty;
            defer face_message.deinit(gpa);
            try protocol.encodeEnvelope(gpa, .{
                .flags = 0,
                .message_type = protocol.Message.face_define,
                .sequence = face_sequence,
                .ack_sequence = 0,
                .session_id = scene.session_id orelse 0x1001,
                .frame_id = 1,
                .timestamp_ns = face_sequence,
            }, face_payload.items, &face_message);
            const retained_face = try gpa.dupe(u8, face_message.items);
            messages.append(gpa, retained_face) catch |err| {
                gpa.free(retained_face);
                return err;
            };
            try scene.apply(retained_face);
            face_sequence += 1;
        }
        for (effective_windows) |window| {
            var bound = false;
            for (scene.window_faces.items) |state| {
                if (state.window_id != window.id) continue;
                bound = state.face_id == default_face_id and
                    state.face_generation == face_generation;
                break;
            }
            if (bound) continue;
            var state_payload: std.ArrayList(u8) = .empty;
            defer state_payload.deinit(gpa);
            try frontend.encodeWindowFaceState(gpa, .{
                .window_id = window.id,
                .frame_generation = 1,
                .face_id = default_face_id,
                .face_generation = face_generation,
            }, &state_payload);
            var state_message: std.ArrayList(u8) = .empty;
            defer state_message.deinit(gpa);
            try protocol.encodeEnvelope(gpa, .{
                .flags = 0,
                .message_type = protocol.Message.window_face,
                .sequence = face_sequence,
                .ack_sequence = 0,
                .session_id = scene.session_id orelse 0x1001,
                .frame_id = 1,
                .timestamp_ns = face_sequence,
            }, state_payload.items, &state_message);
            const retained_state = try gpa.dupe(u8, state_message.items);
            messages.append(gpa, retained_state) catch |err| {
                gpa.free(retained_state);
                return err;
            };
            try scene.apply(retained_state);
            face_sequence += 1;
        }
    }

    // The frame's other real faces are published under reserved ids so the
    // mode-line bar, the cursor, and the fringe bars can use Emacs's own
    // colors.  Like the default face the generation only advances on a change.
    try appendReservedFace(gpa, scene, messages, mode_line_face_id, facts.mode_line_foreground, facts.mode_line_background, .{ .box = facts.mode_line_box, .box_width = facts.mode_line_box_width });
    try appendReservedFace(gpa, scene, messages, cursor_face_id, null, facts.cursor_background, .{});
    try appendReservedFace(gpa, scene, messages, mode_line_inactive_face_id, facts.mode_line_inactive_foreground, facts.mode_line_inactive_background, .{});
    try appendReservedFace(gpa, scene, messages, header_line_face_id, facts.header_line_foreground, facts.header_line_background, .{});
    try appendReservedFace(gpa, scene, messages, tab_line_face_id, facts.tab_line_foreground, facts.tab_line_background, .{});
    try appendReservedFace(gpa, scene, messages, tool_bar_face_id, facts.tool_bar_foreground, facts.tool_bar_background, .{ .box = facts.tool_bar_box, .box_width = facts.tool_bar_box_width });
    for (0..facts.regions.len) |region_index| {
        try appendReservedFace(gpa, scene, messages, regionRectFaceId(region_index), null, facts.region_background, .{});
    }
    for (0..facts.mouse_rects.len) |mouse_index| {
        try appendReservedFace(gpa, scene, messages, mouseRectFaceId(mouse_index), null, facts.mouse_background, .{});
    }
    try appendReservedFace(gpa, scene, messages, fringe_face_id, null, facts.fringe_background, .{});

    // A window that reports a nonzero scroll-bar width gets a bounded live
    // scroll state so the frontend can draw the real proportional thumb.  An
    // authoritative FRAME_UPDATE replaces these states, so they are re-sent
    // with the frame; the profile pins the width only because a batch Emacs
    // frame has no scroll bars of its own.  A reported scroll-bar height
    // likewise publishes the independent horizontal state of that window.
    if (contents.len != 0) {
        var scroll_sequence = scene.next_sequence orelse update_sequence + 1;
        for (effective_windows) |window| {
            var content = fallback_content;
            var found = false;
            for (contents) |candidate| {
                if (candidate.id == window.id) {
                    content = candidate;
                    found = true;
                    break;
                }
            }
            if (!found) continue;
            if (content.scroll_width > 0 and content.buffer_lines > 0) {
                const line_count: i32 = @intCast(content.text.lines.len);
                const viewport_size: u32 = @intCast(@max(1, @min(line_count, content.buffer_lines)));
                const content_size: u32 = @intCast(@max(content.buffer_lines, @as(i32, @intCast(viewport_size))));
                const position = clampedScrollPosition(content.scroll_top, content_size, viewport_size);
                try appendScrollState(gpa, scene, messages, window.id, .vertical, .{
                    .content_size = content_size,
                    .viewport_size = viewport_size,
                    .position = position,
                    .track_width = @intCast(content.scroll_width),
                }, scroll_sequence);
                scroll_sequence += 1;
            }
            if (content.scroll_height > 0 and content.hviewport > 0) {
                const viewport_size: u32 = @intCast(content.hviewport);
                const content_size: u32 = @intCast(@max(content.hcontent, content.hviewport));
                const position = clampedScrollPosition(content.hscroll, content_size, viewport_size);
                try appendScrollState(gpa, scene, messages, window.id, .horizontal, .{
                    .content_size = content_size,
                    .viewport_size = viewport_size,
                    .position = position,
                    .track_width = @intCast(content.scroll_height),
                }, scroll_sequence);
                scroll_sequence += 1;
            }
        }
    }

    // A display-backed window reports real fringe widths, which the frontend
    // draws as edge bars from the same records the synthetic path uses.  Like
    // the scroll states these are cleared by an authoritative FRAME_UPDATE, so
    // they travel with the frame.
    if (contents.len != 0) {
        const fringe_color = facts.fringe_background orelse
            facts.default_background orelse [4]u8{ 0x20, 0x24, 0x2c, 255 };
        for (effective_windows, 0..) |window, window_index| {
            var content = fallback_content;
            var found = false;
            for (contents) |candidate| {
                if (candidate.id == window.id) {
                    content = candidate;
                    found = true;
                    break;
                }
            }
            if (!found) continue;
            const base_id: u32 = 200 + @as(u32, @intCast(window_index)) * 2;
            if (content.fringe_left > 0) {
                try appendFringe(gpa, scene, messages, .left, base_id, window.id, window.width, window.height, content.fringe_left, fringe_color);
            }
            if (content.fringe_right > 0) {
                try appendFringe(gpa, scene, messages, .right, base_id + 1, window.id, window.width, window.height, content.fringe_right, fringe_color);
            }
        }
    }

    // The first visible lines' real font-lock runs travel as bounded
    // face-colored glyph runs, so the mirror can show syntax colors instead of
    // one flat line color.  Each row's runs cover the whole line, which is what
    // lets the frontend replace that row's plain text without hiding anything.
    if (facts.line_runs.len != 0 and effective_windows.len != 0) {
        // A run names the window it belongs to (0 = the first window).  The
        // scene's row table is flat in window order, so the glyph run's row
        // index is the window's base row plus the window-local row.
        const cell_width: i32 = if (facts.char_width > 0) facts.char_width else 8;
        for (facts.line_runs, 0..) |run, index| {
            var window_index: usize = 0;
            var window_found = false;
            for (effective_windows, 0..) |candidate, candidate_index| {
                if (run.window_id == 0 or candidate.id == run.window_id) {
                    window_index = candidate_index;
                    window_found = true;
                    break;
                }
            }
            if (!window_found) continue;
            const window = effective_windows[window_index];
            var fringe_left: i32 = 0;
            var mode_line_height: i32 = 0;
            var header_line_height: i32 = 0;
            var tab_line_height: i32 = 0;
            for (contents) |candidate| {
                if (candidate.id == window.id) {
                    fringe_left = candidate.fringe_left;
                    mode_line_height = candidate.mode_line_height;
                    header_line_height = candidate.header_line_height;
                    tab_line_height = candidate.tab_line_height;
                    break;
                }
            }
            const row_height = visibleRowHeight(window.height, facts.line_height);
            var base_row: i32 = 0;
            for (effective_windows[0..window_index]) |previous|
                base_row += visibleRowCount(previous.height, facts.line_height);
            const chrome = runChrome(run);
            const face_id = line_run_face_base_id + @as(u32, @intCast(index));
            try appendReservedFace(gpa, scene, messages, face_id, run.foreground, run.background, .{
                .underline = if (!run.underline) .unspecified else if (run.underline_color != null) .color else .single,
                .strike_through = if (!run.strike_through) .unspecified else if (run.strike_color != null) .color else .single,
                .overline = if (!run.overline) .unspecified else if (run.overline_color != null) .color else .single,
                .underline_color = run.underline_color,
                .strike_color = run.strike_color,
                .overline_color = run.overline_color,
                .inverse_video = run.inverse_video,
                // A run's box is drawn as the bounded simple box style; the
                // released/button styles only matter for the chrome faces.
                .box = if (run.box) .simple else .none,
                .box_color = run.box_color,
            });
            const face = scene.faces.lookup(face_id) orelse continue;
            // A chrome run keeps that aux row's geometry and is anchored to the
            // window's first row for validation only; a body run covers its own
            // row's plain text.
            const anchored_row: i32 = if (chrome == .body) base_row + run.row else base_row;
            const chrome_height: i32 = switch (chrome) {
                .mode_line => mode_line_height,
                .header_line => header_line_height,
                .tab_line => tab_line_height,
                .body => 0,
            };
            const run_height: i32 = if (chrome != .body and chrome_height > 0) chrome_height else row_height;
            const run_y: i32 = switch (chrome) {
                .mode_line => window.height - run_height,
                .header_line => 0,
                .tab_line => if (header_line_height > 0) header_line_height else 0,
                .body => run.row * row_height,
            };
            // Runs carry window-relative coordinates, so a line wider than its
            // window (a long line in a narrow frame) must clamp to the window:
            // an unclamped run would fail the scene's bounds check and reject
            // the whole snapshot.
            const run_x: i32 = (if (chrome != .body) 4 else fringe_left) +
                (if (run.pixel_x >= 0) run.pixel_x else run.column * cell_width);
            if (run_x < 0 or run_x >= window.width) continue;
            const run_width: i32 = @min(
                if (run.pixel_width >= 0)
                    run.pixel_width
                else
                    @as(i32, @intCast(run.text.len)) * cell_width,
                window.width - run_x,
            );
            if (run_width <= 0) continue;
            try appendLineRunGlyph(
                gpa,
                scene,
                messages,
                line_run_glyph_base_id + @as(u32, @intCast(index)),
                window.id,
                anchored_row,
                run_y,
                run_x,
                run_width,
                run_height,
                run.text,
                face_id,
                face.generation,
                run.bold,
                run.italic,
                run.variable_pitch,
                run.font_family,
                run.partial and chrome == .body,
                chrome,
            );
        }
    }

    // The active region travels as the bounded highlight records after the
    // frame (one per displayed row), because an authoritative update clears
    // the highlight table.
    for (facts.regions, 0..) |region, region_index| {
        const face_id = regionRectFaceId(region_index);
        if (scene.faces.lookup(face_id)) |face| {
            if (effective_windows.len != 0)
                try appendHighlight(gpa, scene, messages, region, face_id, effective_windows[0].id, effective_windows[0].width, effective_windows[0].height, face.generation);
        }
    }

    // The mouse-face highlight under the pointer travels the same bounded
    // record, keyed by its own reserved face so it can coexist with the region.
    for (facts.mouse_rects, 0..) |mouse, mouse_index| {
        const face_id = mouseRectFaceId(mouse_index);
        if (scene.faces.lookup(face_id)) |face| {
            if (effective_windows.len != 0)
                try appendHighlight(gpa, scene, messages, mouse, face_id, effective_windows[0].id, effective_windows[0].width, effective_windows[0].height, face.generation);
        }
    }
}

/// Append and apply one bounded fringe update for WINDOW.
fn appendFringe(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    messages: *std.ArrayList([]const u8),
    side: frontend.FringeSide,
    fringe_id: u32,
    window_id: u64,
    window_width: i32,
    window_height: i32,
    width: i32,
    color: [4]u8,
) !void {
    if (width <= 0 or width > window_width) return;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try frontend.encodeFringeUpdate(gpa, .{
        .side = side,
        .fringe_id = fringe_id,
        .fringe_generation = 1,
        .window_id = window_id,
        .y = 0,
        .height = window_height,
        .width = width,
        .color = color,
        .frame_generation = 1,
    }, &payload);
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(gpa);
    const sequence = scene.next_sequence orelse return error.InvalidFrameFacts;
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.fringe_update,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = scene.session_id orelse 0x1001,
        .frame_id = 1,
        .timestamp_ns = sequence,
    }, payload.items, &message);
    const retained = try gpa.dupe(u8, message.items);
    messages.append(gpa, retained) catch |err| {
        gpa.free(retained);
        return err;
    };
    try scene.apply(retained);
}

const ScrollOrientation = enum { vertical, horizontal };

/// Adapter-owned menu id for the live menu-bar model.
const menu_bar_menu_id: u32 = 0x9e01;
const max_menu_icon_payload: usize = 4096;
const max_menu_icon_dimension: u32 = 32;

const MenuXbm = struct {
    width: u32,
    height: u32,
    bits: [128]u8,
};

const MenuIconPixels = struct {
    width: u32,
    height: u32,
    bytes: []u8,
};

fn menuXbmDefine(bytes: []const u8, suffix: []const u8) ?u32 {
    const needle_end = std.mem.indexOf(u8, bytes, suffix) orelse return null;
    var cursor = needle_end + suffix.len;
    while (cursor < bytes.len and (bytes[cursor] == ' ' or bytes[cursor] == '\t')) cursor += 1;
    const start = cursor;
    while (cursor < bytes.len and bytes[cursor] >= '0' and bytes[cursor] <= '9') cursor += 1;
    if (cursor == start) return null;
    return std.fmt.parseInt(u32, bytes[start..cursor], 10) catch null;
}

fn parseMenuXbm(bytes: []const u8) ?MenuXbm {
    if (bytes.len == 0 or bytes.len > max_menu_icon_payload) return null;
    for (bytes) |char| {
        if ((char < 0x20 and char != '\t' and char != '\n' and char != '\r') or
            char > 0x7e) return null;
    }
    const width = menuXbmDefine(bytes, "_width") orelse return null;
    const height = menuXbmDefine(bytes, "_height") orelse return null;
    if (width == 0 or width > max_menu_icon_dimension or
        height == 0 or height > max_menu_icon_dimension) return null;
    const open = std.mem.indexOfScalar(u8, bytes, '{') orelse return null;
    const close = std.mem.indexOfScalarPos(u8, bytes, open, '}') orelse return null;
    const row_bytes = (width + 7) / 8;
    const expected = row_bytes * height;
    var values: [128]u8 = @splat(0);
    if (expected > values.len) return null;
    var index: usize = 0;
    var cursor = open + 1;
    while (cursor < close) {
        while (cursor < close and (bytes[cursor] == ' ' or bytes[cursor] == '\t' or
            bytes[cursor] == '\n' or bytes[cursor] == '\r' or bytes[cursor] == ',')) cursor += 1;
        if (cursor == close) break;
        if (index == values.len or cursor + 1 >= close or bytes[cursor] != '0') return null;
        cursor += 1;
        if (bytes[cursor] != 'x' and bytes[cursor] != 'X') return null;
        cursor += 1;
        if (cursor + 1 >= close) return null;
        const high = std.fmt.charToDigit(bytes[cursor], 16) catch return null;
        const low = std.fmt.charToDigit(bytes[cursor + 1], 16) catch return null;
        values[index] = @as(u8, high) * 16 + low;
        index += 1;
        cursor += 2;
    }
    if (index != expected) return null;
    return .{ .width = width, .height = height, .bits = values };
}

fn decodeMenuIconPixels(gpa: std.mem.Allocator, payload: []const u8) ?MenuIconPixels {
    const xbm = parseMenuXbm(payload) orelse return null;
    const pixels = gpa.alloc(u8, @as(usize, xbm.width) * xbm.height * 4) catch return null;
    const row_bytes: usize = (xbm.width + 7) / 8;
    @memset(pixels, 0);
    for (0..xbm.height) |row| {
        for (0..xbm.width) |column| {
            if (xbm.bits[row * row_bytes + column / 8] &
                (@as(u8, 1) << @intCast(column % 8)) == 0) continue;
            const offset = (row * @as(usize, xbm.width) + column) * 4;
            pixels[offset + 3] = 255;
        }
    }
    return .{ .width = xbm.width, .height = xbm.height, .bytes = pixels };
}

fn appendSceneMessage(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    message_type: u16,
    payload: []const u8,
    messages: *std.ArrayList([]const u8),
) !void {
    const sequence = scene.next_sequence orelse return error.InvalidMenuBarFacts;
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = scene.session_id orelse 0x1001,
        .frame_id = 1,
        .timestamp_ns = sequence,
    }, payload, &message);
    const retained = try gpa.dupe(u8, message.items);
    errdefer gpa.free(retained);
    try scene.apply(retained);
    try messages.append(gpa, retained);
}

fn appendMenuIconMessages(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    menu: OpenMenu,
    messages: *std.ArrayList([]const u8),
) !void {
    if (menu.icon_payloads.len != menu.items.len) return;
    for (menu.icon_payloads, 0..) |payload, index| {
        const image_id = menu.icon_ids[index];
        const generation = menu.icon_generations[index];
        if (image_id == 0 or generation == 0 or payload.len == 0) continue;
        const pixels = decodeMenuIconPixels(gpa, payload) orelse {
            continue;
        };
        defer gpa.free(pixels.bytes);
        const existing = scene.images.lookup(image_id);
        if (existing) |image| {
            if (image.complete and image.generation == generation and
                image.metadata.width == pixels.width and
                image.metadata.height == pixels.height and
                std.mem.eql(u8, image.bytes, pixels.bytes))
                continue;
        }
        var define_payload: std.ArrayList(u8) = .empty;
        defer define_payload.deinit(gpa);
        try protocol.encodeImageDefine(gpa, .{
            .image_id = image_id,
            .generation = generation,
            .width = pixels.width,
            .height = pixels.height,
            .total_byte_count = @intCast(pixels.bytes.len),
            .cache_policy = .pinned,
        }, &define_payload);
        try appendSceneMessage(gpa, scene, protocol.Message.image_define, define_payload.items, messages);
        var data_payload: std.ArrayList(u8) = .empty;
        defer data_payload.deinit(gpa);
        try protocol.encodeImageData(gpa, .{
            .image_id = image_id,
            .generation = generation,
            .fragment_index = 0,
            .fragment_count = 1,
            .bytes = pixels.bytes,
        }, &data_payload);
        try appendSceneMessage(gpa, scene, protocol.Message.image_data, data_payload.items, messages);
    }
}

/// Publish the bounded live menu-bar model when the real labels change.  The
/// model survives a `FRAME_UPDATE`, so an unchanged menu bar adds no traffic
/// and the generation only advances when the labels actually differ.
pub fn appendMenuMessages(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    menu_bar: []const []const u8,
    open_menu: ?OpenMenu,
    messages: *std.ArrayList([]const u8),
) !void {
    if (menu_bar.len == 0 or menu_bar.len > max_menu_bar_items)
        return error.InvalidMenuBarFacts;
    const child_count: usize = if (open_menu) |menu| menu.items.len else 0;
    const path_count: usize = if (open_menu) |menu| menu.path.len else 0;
    const parent_count: usize = if (open_menu) |menu|
        (if (menu.parent_id != 0) path_count else 0)
    else
        0;
    if (menu_bar.len + parent_count + child_count > protocol.max_menu_nodes)
        return error.InvalidMenuBarFacts;
    if (open_menu) |menu|
        try appendMenuIconMessages(gpa, scene, menu, messages);

    var nodes: [protocol.max_menu_nodes]protocol.MenuNode = undefined;
    for (menu_bar, 0..) |label, index| {
        if (label.len == 0 or label.len > max_menu_bar_label)
            return error.InvalidMenuBarFacts;
        nodes[index] = .{
            .item_id = @intCast(index + 1),
            .parent_item_id = 0,
            .kind = .submenu,
            .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
            .depth = 0,
            .label_len = @intCast(label.len),
        };
        @memcpy(nodes[index].label[0..label.len], label);
    }
    if (open_menu) |menu| {
        for (menu.path, 0..) |entry, index| {
            const node = &nodes[menu_bar.len + index];
            node.* = .{
                .item_id = entry.id,
                .parent_item_id = if (index == 0) menu.parent_id else menu.path[index - 1].id,
                .kind = .submenu,
                .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
                .depth = @intCast(index + 1),
                .label_len = @intCast(entry.label.len),
            };
            @memcpy(node.label[0..entry.label.len], entry.label);
        }
        const row_base: u32 = if (menu.path.len != 0)
            menuChildIdBase(menu.path.len + 1).?
        else
            menu_child_id_base;
        const row_offset = menu_bar.len + parent_count;
        for (menu.items, 0..) |label, index| {
            // An empty label is the bounded separator row.
            const separator = label.len == 0;
            const row_submenu = !separator and menu.submenus.len == menu.items.len and
                menu.submenus[index];
            const row_kind: MenuRowKind = if (separator) .command else if (menu.kinds.len == menu.items.len) menu.kinds[index] else .command;
            const row_selected = !separator and (row_kind == .checkbox or row_kind == .radio) and
                menu.selected.len == menu.items.len and menu.selected[index];
            const row_enabled = !separator and
                (menu.enabled.len != menu.items.len or menu.enabled[index]);
            var row_flags = if (row_enabled)
                protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible
            else
                protocol.MenuNodeFlags.visible;
            if (row_selected) row_flags |= protocol.MenuNodeFlags.selected;
            const row_key = if (menu.keys.len == menu.items.len) menu.keys[index] else "";
            nodes[row_offset + index] = .{
                .item_id = row_base + @as(u32, @intCast(index)),
                .parent_item_id = menu.item_id,
                .kind = if (separator)
                    .separator
                else if (row_submenu)
                    .submenu
                else switch (row_kind) {
                    .command => .command,
                    .checkbox => .checkbox,
                    .radio => .radio,
                },
                .flags = row_flags,
                .depth = @intCast(if (menu.parent_id != 0) menu.path.len + 1 else 1),
                .label_len = @intCast(label.len),
            };
            @memcpy(nodes[row_offset + index].label[0..label.len], label);
            if (row_key.len != 0 and row_key.len <= nodes[row_offset + index].key.len) {
                @memcpy(nodes[row_offset + index].key[0..row_key.len], row_key);
                nodes[row_offset + index].key_len = @intCast(row_key.len);
            }
            const row_help = if (menu.helps.len == menu.items.len) menu.helps[index] else "";
            if (row_help.len != 0 and row_help.len <= nodes[row_offset + index].help.len) {
                @memcpy(nodes[row_offset + index].help[0..row_help.len], row_help);
                nodes[row_offset + index].help_len = @intCast(row_help.len);
            }
            if (!separator and menu.icon_ids.len == menu.items.len and
                menu.icon_generations.len == menu.items.len)
            {
                nodes[row_offset + index].icon_image_id = menu.icon_ids[index];
                nodes[row_offset + index].icon_image_generation = menu.icon_generations[index];
            }
        }
    }
    const total = menu_bar.len + parent_count + child_count;

    // The model survives a FRAME_UPDATE, so it is only re-sent when a node
    // actually differs and the generation only advances on a real change.
    var model_changed = true;
    if (scene.menu_model) |current| {
        if (current.nodes.len == total) {
            model_changed = false;
            for (current.nodes, nodes[0..total]) |existing, wanted| {
                if (existing.item_id != wanted.item_id or
                    existing.parent_item_id != wanted.parent_item_id or
                    existing.kind != wanted.kind or existing.flags != wanted.flags or
                    existing.depth != wanted.depth or
                    existing.label_len != wanted.label_len or
                    existing.icon_image_id != wanted.icon_image_id or
                    existing.icon_image_generation != wanted.icon_image_generation or
                    existing.help_len != wanted.help_len or
                    !std.mem.eql(
                        u8,
                        existing.label[0..existing.label_len],
                        wanted.label[0..wanted.label_len],
                    ) or
                    !std.mem.eql(
                        u8,
                        existing.help[0..existing.help_len],
                        wanted.help[0..wanted.help_len],
                    ))
                {
                    model_changed = true;
                    break;
                }
            }
        }
    }
    var generation: u32 = 1;
    if (scene.menu_model) |current| generation = current.header.menu_generation;
    if (model_changed) {
        if (scene.menu_model != null) generation += 1;
        const sequence = scene.next_sequence orelse return error.InvalidMenuBarFacts;
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        try protocol.encodeMenuModelSnapshot(gpa, .{
            .header = .{
                .frame_id = 1,
                .frame_generation = 1,
                .menu_id = menu_bar_menu_id,
                .menu_generation = generation,
            },
            .nodes = nodes[0..total],
        }, &payload);
        var message: std.ArrayList(u8) = .empty;
        defer message.deinit(gpa);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.menu_model,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = scene.session_id orelse 0x1001,
            .frame_id = 1,
            .timestamp_ns = sequence,
        }, payload.items, &message);
        const retained = try gpa.dupe(u8, message.items);
        messages.append(gpa, retained) catch |err| {
            gpa.free(retained);
            return err;
        };
        try scene.apply(retained);
    }

    if (open_menu) |menu| {
        try appendMenuIconMessages(gpa, scene, menu, messages);
        const owner = findSceneWindow(scene, menu.window_id) orelse return;
        if (menu.x >= owner.width or menu.y >= owner.height) return;
        const width: u32 = @intCast(@min(menu.width, owner.width - menu.x));
        const height: u32 = @intCast(@min(menu.height, owner.height - menu.y));
        if (width == 0 or height == 0) return;
        if (scene.menu_open) |existing| {
            if (existing.item_id == menu.item_id and
                existing.menu_generation == generation and
                existing.x == menu.x and existing.y == menu.y and
                existing.width == width and existing.height == height)
                return;
        }
        const sequence = scene.next_sequence orelse return error.InvalidMenuBarFacts;
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(gpa);
        try protocol.encodeMenuOpen(gpa, .{
            .menu_id = menu_bar_menu_id,
            .menu_generation = generation,
            .item_id = menu.item_id,
            .window_id = menu.window_id,
            .frame_generation = 1,
            .x = menu.x,
            .y = menu.y,
            .width = width,
            .height = height,
        }, &payload);
        var message: std.ArrayList(u8) = .empty;
        defer message.deinit(gpa);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.menu_open,
            .sequence = sequence,
            .ack_sequence = 0,
            .session_id = scene.session_id orelse 0x1001,
            .frame_id = 1,
            .timestamp_ns = sequence,
        }, payload.items, &message);
        const retained = try gpa.dupe(u8, message.items);
        messages.append(gpa, retained) catch |err| {
            gpa.free(retained);
            return err;
        };
        try scene.apply(retained);
        return;
    }

    // The producer closed the menu: dismiss the live popup while the model
    // keeps its rows, because a closed popup never renders them.
    const open = scene.menu_open orelse return;
    if (open.menu_id != menu_bar_menu_id) return;
    const sequence = scene.next_sequence orelse return error.InvalidMenuBarFacts;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try protocol.encodeMenuClose(gpa, .{
        .reason = .dismissal,
        .menu_id = open.menu_id,
        .menu_generation = open.menu_generation,
        .item_id = open.item_id,
        .frame_generation = 1,
    }, &payload);
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.menu_close,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = scene.session_id orelse 0x1001,
        .frame_id = 1,
        .timestamp_ns = sequence,
    }, payload.items, &message);
    const retained = try gpa.dupe(u8, message.items);
    messages.append(gpa, retained) catch |err| {
        gpa.free(retained);
        return err;
    };
    try scene.apply(retained);
}

fn parseToolbarKind(text: []const u8) ?protocol.ToolbarItemKind {
    if (std.mem.eql(u8, text, "separator")) return .separator;
    if (std.mem.eql(u8, text, "space")) return .space;
    if (std.mem.eql(u8, text, "button")) return .button;
    if (std.mem.eql(u8, text, "toggle")) return .toggle;
    return null;
}

/// Adapter-owned tool-bar id for the live tool-bar model.
const toolbar_model_id: u32 = 0x9e02;

/// Publish the bounded live tool-bar model when the real items change.  The
/// model survives a `FRAME_UPDATE`, so an unchanged tool bar adds no traffic
/// and the generation only advances when the items actually differ.
pub fn appendToolbarMessages(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    tool_bar: []const ToolbarFact,
    messages: *std.ArrayList([]const u8),
) !void {
    if (tool_bar.len == 0) return;
    if (tool_bar.len > protocol.max_toolbar_items) return error.InvalidToolbarFacts;

    var items: [protocol.max_toolbar_items]protocol.ToolbarItem = undefined;
    for (tool_bar, 0..) |fact, index| {
        var item = protocol.ToolbarItem{
            .item_id = @intCast(index + 1),
            .kind = fact.kind,
            .flags = fact.flags,
        };
        item.label_len = @intCast(fact.label.len);
        @memcpy(item.label[0..fact.label.len], fact.label);
        item.help_len = @intCast(fact.help.len);
        @memcpy(item.help[0..fact.help.len], fact.help);
        item.key_len = @intCast(fact.key.len);
        @memcpy(item.key[0..fact.key.len], fact.key);
        items[index] = item;
    }

    var model_changed = scene.toolbar == null;
    if (scene.toolbar) |current| {
        if (current.header.toolbar_id != toolbar_model_id or
            current.items.len != tool_bar.len)
        {
            model_changed = true;
        } else {
            for (current.items, 0..) |existing, index| {
                const wanted = items[index];
                if (existing.kind != wanted.kind or existing.flags != wanted.flags or
                    existing.label_len != wanted.label_len or
                    existing.help_len != wanted.help_len or
                    existing.key_len != wanted.key_len or
                    !std.mem.eql(
                        u8,
                        existing.label[0..existing.label_len],
                        wanted.label[0..wanted.label_len],
                    ) or
                    !std.mem.eql(
                        u8,
                        existing.help[0..existing.help_len],
                        wanted.help[0..wanted.help_len],
                    ) or
                    !std.mem.eql(
                        u8,
                        existing.key[0..existing.key_len],
                        wanted.key[0..wanted.key_len],
                    ))
                {
                    model_changed = true;
                    break;
                }
            }
        }
    }
    if (!model_changed) return;

    var generation: u32 = 1;
    if (scene.toolbar) |current| generation = current.header.toolbar_generation + 1;
    const sequence = scene.next_sequence orelse return error.InvalidToolbarFacts;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try protocol.encodeToolbarModel(gpa, .{
        .header = .{
            .frame_id = 1,
            .frame_generation = 1,
            .toolbar_id = toolbar_model_id,
            .toolbar_generation = generation,
        },
        .items = items[0..tool_bar.len],
    }, &payload);
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.toolbar_model,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = scene.session_id orelse 0x1001,
        .frame_id = 1,
        .timestamp_ns = sequence,
    }, payload.items, &message);
    const retained = try gpa.dupe(u8, message.items);
    messages.append(gpa, retained) catch |err| {
        gpa.free(retained);
        return err;
    };
    try scene.apply(retained);
}

fn findSceneWindow(scene: *const frontend.Scene, window_id: u64) ?frontend.Window {
    for (scene.windows.items) |window| {
        if (window.id == window_id) return window;
    }
    return null;
}

/// Bounded face line decorations the run faces can carry.
const FaceDecorations = struct {
    underline: protocol.FaceStyle = .unspecified,
    strike_through: protocol.FaceStyle = .unspecified,
    overline: protocol.FaceStyle = .unspecified,
    underline_color: ?[4]u8 = null,
    strike_color: ?[4]u8 = null,
    overline_color: ?[4]u8 = null,
    inverse_video: bool = false,
    box: protocol.BoxStyle = .none,
    box_color: ?[4]u8 = null,
    /// Real `:box` `:line-width` in pixels; 0 keeps the bounded guess.
    box_width: i32 = 0,
};

/// Publish one reserved face's colors, generation-qualified like the default
/// face and only when it is not already live with those exact colors.
fn appendReservedFace(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    messages: *std.ArrayList([]const u8),
    face_id: u32,
    foreground: ?[4]u8,
    background: ?[4]u8,
    decorations: FaceDecorations,
) !void {
    if (foreground == null and background == null) return;
    const fg = foreground orelse [4]u8{ 0, 0, 0, 0 };
    const bg = background orelse [4]u8{ 0, 0, 0, 0 };
    const underline_color = decorations.underline_color orelse [4]u8{ 0, 0, 0, 0 };
    const strike_color = decorations.strike_color orelse [4]u8{ 0, 0, 0, 0 };
    const overline_color = decorations.overline_color orelse [4]u8{ 0, 0, 0, 0 };
    // The wire requires a box color whenever a box is present, so a box that
    // names no color falls back to the face foreground (how Emacs draws it).
    const box_present = decorations.box != .none;
    const box_color = if (box_present) decorations.box_color orelse fg else [4]u8{ 0, 0, 0, 0 };
    const box_line_width: i32 = if (box_present)
        @min(@max(decorations.box_width, 0), 8)
    else
        0;
    const current = scene.faces.lookup(face_id);
    const changed = if (current) |existing|
        existing.payload.presence.foreground != (foreground != null) or
            existing.payload.presence.background != (background != null) or
            existing.payload.presence.underline_color != (decorations.underline_color != null) or
            existing.payload.presence.strike_color != (decorations.strike_color != null) or
            existing.payload.presence.overline_color != (decorations.overline_color != null) or
            existing.payload.presence.box_color != box_present or
            !std.meta.eql(existing.payload.foreground, fg) or
            !std.meta.eql(existing.payload.background, bg) or
            !std.meta.eql(existing.payload.underline_color, underline_color) or
            !std.meta.eql(existing.payload.strike_color, strike_color) or
            !std.meta.eql(existing.payload.overline_color, overline_color) or
            !std.meta.eql(existing.payload.box_color, box_color) or
            existing.payload.box_line_width != box_line_width or
            existing.payload.underline != decorations.underline or
            existing.payload.strike_through != decorations.strike_through or
            existing.payload.overline != decorations.overline or
            existing.payload.inverse_video != decorations.inverse_video or
            existing.payload.box != decorations.box
    else
        true;
    if (!changed) return;
    const generation: u32 = if (current) |existing| existing.generation + 1 else 1;
    const sequence = scene.next_sequence orelse return error.InvalidFrameFacts;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try protocol.encodeFaceDefine(gpa, .{
        .face_id = face_id,
        .generation = generation,
        .presence = .{
            .foreground = foreground != null,
            .background = background != null,
            .underline_color = decorations.underline_color != null,
            .strike_color = decorations.strike_color != null,
            .overline_color = decorations.overline_color != null,
            .box_color = box_present,
        },
        .foreground = fg,
        .background = bg,
        .underline_color = underline_color,
        .strike_color = strike_color,
        .overline_color = overline_color,
        .box_color = box_color,
        .underline = decorations.underline,
        .strike_through = decorations.strike_through,
        .overline = decorations.overline,
        .box = decorations.box,
        .box_line_width = box_line_width,
        .inverse_video = decorations.inverse_video,
    }, &payload);
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.face_define,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = scene.session_id orelse 0x1001,
        .frame_id = 1,
        .timestamp_ns = sequence,
    }, payload.items, &message);
    const retained = try gpa.dupe(u8, message.items);
    messages.append(gpa, retained) catch |err| {
        gpa.free(retained);
        return err;
    };
    try scene.apply(retained);
}

/// Which chrome row a line run replaces; a body run owns its visible row.
const RunChrome = enum { body, mode_line, header_line, tab_line };

fn runChrome(run: LineRun) RunChrome {
    if (run.mode_line) return .mode_line;
    if (run.header_line) return .header_line;
    if (run.tab_line) return .tab_line;
    return .body;
}

/// Append one bounded face-colored ASCII glyph run for a line run.
fn appendLineRunGlyph(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    messages: *std.ArrayList([]const u8),
    run_id: u32,
    window_id: u64,
    row_index: i32,
    y: i32,
    x: i32,
    wire_width: i32,
    row_height: i32,
    text: []const u8,
    face_id: u32,
    face_generation: u32,
    bold: bool,
    italic: bool,
    variable_pitch: bool,
    font_family: u8,
    partial: bool,
    chrome: RunChrome,
) !void {
    if (x < 0 or row_index < 0 or wire_width <= 0 or row_height <= 0 or text.len == 0) return;
    const sequence = scene.next_sequence orelse return error.InvalidRunFacts;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try frontend.encodeGlyphRun(gpa, .{
        // Schema 2 is the bounded face-bound debug glyph run.
        .schema = 2,
        .flags = frontend.glyph_debug_fallback |
            (if (bold) frontend.glyph_bold else 0) |
            (if (italic) frontend.glyph_italic else 0) |
            (if (variable_pitch) frontend.glyph_variable_font else 0) |
            (if (font_family > 1)
                @as(u16, @intCast(font_family - 1)) << frontend.glyph_font_family_shift
            else
                0) |
            (if (partial) frontend.glyph_partial_body else 0) |
            switch (chrome) {
                .body => 0,
                .mode_line => frontend.glyph_mode_line,
                .header_line => frontend.glyph_header_line,
                .tab_line => frontend.glyph_tab_line,
            },
        .run_id = run_id,
        .generation = 1,
        .window_id = window_id,
        .row_index = @intCast(row_index),
        .face_id = face_id,
        .face_generation = face_generation,
        .x = x,
        .y = y,
        .width = wire_width,
        .height = row_height,
        .text = text,
    }, &payload);
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.debug,
        .message_type = protocol.Message.glyph_run,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = scene.session_id orelse 0x1001,
        .frame_id = 1,
        .timestamp_ns = sequence,
    }, payload.items, &message);
    const retained = try gpa.dupe(u8, message.items);
    messages.append(gpa, retained) catch |err| {
        gpa.free(retained);
        return err;
    };
    try scene.apply(retained);
}

/// Publish the active region as a bounded visible highlight record.
///
/// The record is the frontend's bounded highlight (rect plus a live face), so
/// the region uses the same validation, ownership, and draw path as the
/// synthetic mouse highlight; the rect is clamped inside the owning window.
fn appendHighlight(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    messages: *std.ArrayList([]const u8),
    region: RegionRect,
    face_id: u32,
    window_id: u64,
    window_width: i32,
    window_height: i32,
    face_generation: u32,
) !void {
    if (region.x >= window_width or region.y >= window_height) return;
    const width: i32 = @min(region.width, window_width - region.x);
    const height: i32 = @min(region.height, window_height - region.y);
    if (width <= 0 or height <= 0) return;
    const sequence = scene.next_sequence orelse return error.InvalidRegionFacts;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try frontend.encodeMouseHighlightState(gpa, .{
        .flags = frontend.MouseHighlightFlags.visible,
        .window_id = window_id,
        .frame_generation = 1,
        .rect = .{ .x = region.x, .y = region.y, .width = width, .height = height },
        .face_id = face_id,
        .face_generation = face_generation,
    }, &payload);
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.mouse_highlight,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = scene.session_id orelse 0x1001,
        .frame_id = 1,
        .timestamp_ns = sequence,
    }, payload.items, &message);
    const retained = try gpa.dupe(u8, message.items);
    messages.append(gpa, retained) catch |err| {
        gpa.free(retained);
        return err;
    };
    try scene.apply(retained);
}

/// Publish one bounded producer string as a generation-qualified resource,
/// regenerating only when its bytes change.
fn appendBoundedString(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    resource_id: u32,
    bytes: []const u8,
    messages: *std.ArrayList([]const u8),
) !void {
    if (bytes.len == 0 or bytes.len > protocol.max_string_bytes) return error.InvalidFontFacts;
    const current = scene.strings.lookup(resource_id);
    if (current) |resource| {
        if (std.mem.eql(u8, resource.bytes, bytes)) return;
    }
    const generation: u32 = if (current) |resource| resource.generation + 1 else 1;
    const sequence = scene.next_sequence orelse return error.InvalidFontFacts;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try protocol.encodeStringDefine(gpa, .{
        .resource_id = resource_id,
        .generation = generation,
        .bytes = bytes,
    }, &payload);
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.string_define,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = scene.session_id orelse 0x1001,
        .frame_id = 1,
        .timestamp_ns = sequence,
    }, payload.items, &message);
    const retained = try gpa.dupe(u8, message.items);
    messages.append(gpa, retained) catch |err| {
        gpa.free(retained);
        return err;
    };
    try scene.apply(retained);
}

/// Publish the frame's real default font file and pixel size as bounded string
/// resources.
///
/// The frontend resolves the file to a real SDL_ttf font and falls back to its
/// own bundled font when the resource is absent or cannot be opened, and sizes
/// that font from the published pixel size rather than the row line height.
pub fn appendFontMessages(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    font_file: ?[]const u8,
    font_pixel_size: i32,
    variable_font_file: ?[]const u8,
    alt_font_files: [max_alt_font_families]?[]const u8,
    messages: *std.ArrayList([]const u8),
) !void {
    if (font_file) |file|
        try appendBoundedString(gpa, scene, default_font_string_id, file, messages);
    if (font_pixel_size > 0 and font_pixel_size <= 512) {
        var text_buffer: [8]u8 = undefined;
        const text = try std.fmt.bufPrint(&text_buffer, "{d}", .{font_pixel_size});
        try appendBoundedString(gpa, scene, default_font_size_string_id, text, messages);
    }
    if (variable_font_file) |file|
        try appendBoundedString(gpa, scene, variable_font_string_id, file, messages);
    for (alt_font_files, 0..) |entry, index| {
        if (entry) |file|
            try appendBoundedString(gpa, scene, variable_font_string_id + 1 + @as(u32, @intCast(index)), file, messages);
    }
}

/// Publish the frame's echo-area text as a bounded string resource.
pub fn appendEchoMessages(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    echo: ?[]const u8,
    messages: *std.ArrayList([]const u8),
) !void {
    const text = echo orelse return;
    try appendBoundedString(gpa, scene, echo_string_id, text, messages);
}

/// Real character cell width for cursor geometry, bounded and never thinner
/// than the two-unit diagnostic bar.
fn cursor_width(char_width: i32) i32 {
    if (char_width > 1) return @min(char_width, 64);
    return 2;
}

fn clampedScrollPosition(position: i32, content_size: u32, viewport_size: u32) u32 {
    const scrollable = content_size - viewport_size;
    return @intCast(@min(@max(position, 0), @as(i32, @intCast(scrollable))));
}

/// Append and apply one bounded scroll state for WINDOW/ORIENTATION.
fn appendScrollState(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    messages: *std.ArrayList([]const u8),
    window_id: u32,
    orientation: ScrollOrientation,
    state: struct {
        content_size: u32,
        viewport_size: u32,
        position: u32,
        track_width: u32,
    },
    sequence: u64,
) !void {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try frontend.encodeWindowScrollState(gpa, .{
        .flags = switch (orientation) {
            .vertical => frontend.WindowScrollFlags.vertical_visible,
            .horizontal => frontend.WindowScrollFlags.horizontal_visible,
        },
        .window_id = window_id,
        .frame_generation = 1,
        .content_size = state.content_size,
        .viewport_size = state.viewport_size,
        .position = state.position,
        .track_width = state.track_width,
    }, &payload);
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.scrollbar_state,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = scene.session_id orelse 0x1001,
        .frame_id = 1,
        .timestamp_ns = sequence,
    }, payload.items, &message);
    const retained = try gpa.dupe(u8, message.items);
    messages.append(gpa, retained) catch |err| {
        gpa.free(retained);
        return err;
    };
    try scene.apply(retained);
}

test "parses and validates bounded frame facts" {
    const a = std.testing.allocator;
    const facts = try parse(a, "{\"frame_width\":100,\"frame_height\":80,\"window_width\":90,\"window_height\":70}");
    try std.testing.expectEqual(@as(i32, 100), facts.frame_width);
    try std.testing.expectError(error.InvalidFrameFacts, parse(a, "{\"frame_width\":0,\"frame_height\":80,\"window_width\":0,\"window_height\":0}"));
}

test "parses bounded multi-row font-lock runs" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "mode_line_box":"released",
        \\  "line_runs":[
        \\    {"row":0,"column":0,"text":"(message ","foreground":"#000000","underline":true,"overline":true,"underline_color":"#00a0a0"},
        \\    {"row":1,"column":0,"text":"Emacs","foreground":"#8b2252","background":"#204060","inverse_video":true},
        \\    {"row":1,"column":5,"text":"boxed","foreground":"#000000","box":true,"box_color":"#112233"}
        \\  ]
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqual(@as(usize, 3), snapshot.facts.line_runs.len);
    try std.testing.expectEqual(protocol.BoxStyle.released, snapshot.facts.mode_line_box);
    try std.testing.expect(snapshot.facts.line_runs[2].box);
    try std.testing.expectEqual([4]u8{ 0x11, 0x22, 0x33, 255 }, snapshot.facts.line_runs[2].box_color.?);
    try std.testing.expectEqual(@as(i32, 0), snapshot.facts.line_runs[0].row);
    try std.testing.expect(snapshot.facts.line_runs[0].underline);
    try std.testing.expect(snapshot.facts.line_runs[0].overline);
    try std.testing.expect(!snapshot.facts.line_runs[0].strike_through);
    try std.testing.expectEqual([4]u8{ 0x00, 0xa0, 0xa0, 255 }, snapshot.facts.line_runs[0].underline_color.?);
    try std.testing.expectEqual(@as(i32, 1), snapshot.facts.line_runs[1].row);
    try std.testing.expectEqualStrings("Emacs", snapshot.facts.line_runs[1].text);
    try std.testing.expect(!snapshot.facts.line_runs[1].variable_pitch);
    try std.testing.expectEqual([4]u8{ 0x20, 0x40, 0x60, 255 }, snapshot.facts.line_runs[1].background.?);
    try std.testing.expect(snapshot.facts.line_runs[0].background == null);
    try std.testing.expect(!snapshot.facts.line_runs[0].inverse_video);
    try std.testing.expect(snapshot.facts.line_runs[1].inverse_video);
    try std.testing.expectError(error.InvalidRunFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"line_runs\":[{\"row\":8,\"column\":0,\"text\":\"x\",\"foreground\":\"#000000\"}]}"));
    try std.testing.expectError(error.InvalidRunFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"line_runs\":[{\"row\":0,\"column\":0,\"text\":\"x\",\"foreground\":\"#000000\",\"background\":\"bogus\"}]}"));
    try std.testing.expectError(error.InvalidRunFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"line_runs\":[{\"row\":0,\"column\":0,\"text\":\"x\",\"foreground\":\"#000000\",\"underline_color\":\"bogus\"}]}"));
    try std.testing.expectError(error.InvalidRunFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"line_runs\":[{\"row\":0,\"column\":0,\"text\":\"x\",\"foreground\":\"#000000\",\"box_color\":\"bogus\"}]}"));
    // The bounded run wire is printable ASCII, so a non-ASCII run is rejected
    // and the producer must fall back to the row's plain text instead.
    try std.testing.expectError(error.InvalidRunFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"line_runs\":[{\"row\":0,\"column\":0,\"text\":\"你\",\"foreground\":\"#000000\"}]}"));
    try std.testing.expectError(error.InvalidModeLineFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"mode_line_box\":\"bogus\"}"));
}

test "line runs name their window and use the flat row index" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":40,"window_width":60,"window_height":30,
        \\  "line_height":10,
        \\  "windows":[
        \\    {"id":101,"index":0,"x":0,"y":0,"width":60,"height":30,"selected":false},
        \\    {"id":102,"index":1,"x":60,"y":0,"width":60,"height":30,"selected":true}
        \\  ],
        \\  "identity":"process_lifetime",
        \\  "cursor":{"line":1,"column":1},
        \\  "window_start_line":1,"window_visible_lines":2,
        \\  "text":["ab","cd"],
        \\  "line_runs":[{"window_id":102,"row":0,"column":0,"text":"ab","foreground":"#000000"}]
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshotWindows(a, snapshot.facts, snapshot.windows, snapshot.contents, snapshot.text.lines, snapshot.cursor, snapshot.viewport, &scene, &messages);
    try std.testing.expectEqual(@as(usize, 1), scene.glyph_runs.items.len);
    const run = scene.glyph_runs.items[0];
    try std.testing.expectEqual(@as(u64, 102), run.window_id);
    // Window 101 has three 10-pixel rows, so window 102's first row is index 3.
    try std.testing.expectEqual(@as(u32, 3), run.row_index);
}

test "chrome runs carry the header and tab flags exclusively" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "line_runs":[
        \\    {"row":0,"column":0,"text":"H","foreground":"#000000","header_line":true},
        \\    {"row":0,"column":0,"text":"T","foreground":"#000000","tab_line":true}
        \\  ]
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expect(snapshot.facts.line_runs[0].header_line);
    try std.testing.expect(!snapshot.facts.line_runs[0].mode_line);
    try std.testing.expect(!snapshot.facts.line_runs[0].tab_line);
    try std.testing.expect(snapshot.facts.line_runs[1].tab_line);
    // A chrome run replaces its aux row instead of a body row, so the adapter
    // anchors it to the window's first row but keeps the chrome flag.
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshot(a, snapshot.facts, snapshot.text.lines, snapshot.cursor, snapshot.viewport, &scene, &messages);
    try std.testing.expectEqual(@as(usize, 2), scene.glyph_runs.items.len);
    try std.testing.expect(scene.glyph_runs.items[0].header_line);
    try std.testing.expect(!scene.glyph_runs.items[0].covers_row);
    try std.testing.expect(scene.glyph_runs.items[1].tab_line);
    try std.testing.expectError(error.InvalidRunFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"line_runs\":[{\"row\":0,\"column\":0,\"text\":\"x\",\"foreground\":\"#000000\",\"mode_line\":true,\"header_line\":true}]}"));
}

test "parses bounded tool-bar items and rejects malformed separators" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "tool_bar_foreground":"#000000","tool_bar_background":"#bdbdbd",
        \\  "tool_bar":[
        \\    {"kind":"separator","enabled":false},
        \\    {"kind":"button","label":"Save","key":"save-buffer","help":"Save"},
        \\    {"kind":"toggle","label":"Wrap","key":"wrap","selected":true}
        \\  ]
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqual(@as(usize, 3), snapshot.tool_bar.len);
    try std.testing.expectEqual(protocol.ToolbarItemKind.separator, snapshot.tool_bar[0].kind);
    try std.testing.expectEqual(@as(u8, 0), snapshot.tool_bar[0].flags & protocol.ToolbarItemFlags.enabled);
    try std.testing.expectEqualStrings("Save", snapshot.tool_bar[1].label);
    try std.testing.expectEqualStrings("save-buffer", snapshot.tool_bar[1].key);
    try std.testing.expectEqual(protocol.ToolbarItemKind.toggle, snapshot.tool_bar[2].kind);
    try std.testing.expect(snapshot.tool_bar[2].flags & protocol.ToolbarItemFlags.selected != 0);
    try std.testing.expectEqual([4]u8{ 0xbd, 0xbd, 0xbd, 255 }, snapshot.facts.tool_bar_background.?);
    try std.testing.expectEqual([4]u8{ 0x00, 0x00, 0x00, 255 }, snapshot.facts.tool_bar_foreground.?);
    // A separator may not carry a label.
    try std.testing.expectError(error.InvalidToolbarFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"tool_bar\":[{\"kind\":\"separator\",\"label\":\"x\"}]}"));
}

test "line-run glyph geometry scales with the frame character cell" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "char_width":10,"line_height":15,
        \\  "line_runs":[{"row":0,"column":2,"text":"ab","foreground":"#000000"}]
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshot(a, snapshot.facts, snapshot.text.lines, snapshot.cursor, snapshot.viewport, &scene, &messages);
    try std.testing.expectEqual(@as(usize, 1), scene.glyph_runs.items.len);
    const run = scene.glyph_runs.items[0];
    // columns * the real cell (2 * 10), and the text advances by the same cell.
    try std.testing.expectEqual(@as(i32, 20), run.x);
    try std.testing.expectEqual(@as(i32, 20), run.width);
}

test "line-run producer metrics replace cell geometry" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "char_width":10,"line_height":15,
        \\  "line_runs":[{"row":0,"column":2,"text":"ab","foreground":"#000000",
        \\                "variable_pitch":true,"pixel_x":17,"pixel_width":23}]
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqual(@as(i32, 17), snapshot.facts.line_runs[0].pixel_x);
    try std.testing.expectEqual(@as(i32, 23), snapshot.facts.line_runs[0].pixel_width);
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshot(a, snapshot.facts, snapshot.text.lines, snapshot.cursor, snapshot.viewport, &scene, &messages);
    try std.testing.expectEqual(@as(usize, 1), scene.glyph_runs.items.len);
    try std.testing.expectEqual(@as(i32, 17), scene.glyph_runs.items[0].x);
    try std.testing.expectEqual(@as(i32, 23), scene.glyph_runs.items[0].width);
    const prefix =
        "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75," ++
        "\"char_width\":10,\"line_runs\":[{\"row\":0,\"column\":2,\"text\":\"ab\"," ++
        "\"foreground\":\"#000000\",\"pixel_x\":";
    const invalids = [_][2][]const u8{
        .{ "-1", "20" },
        .{ "17", "-1" },
        .{ "-2", "20" },
        .{ "17", "0" },
        .{ "17", "4097" },
    };
    for (invalids) |invalid| {
        const bytes = try std.mem.concat(a, u8, &.{ prefix, invalid[0], ",\"pixel_width\":", invalid[1], "}]}" });
        defer a.free(bytes);
        try std.testing.expectError(error.InvalidRunFacts, parseSnapshot(a, bytes));
    }
}

test "cursor geometry uses producer run metrics" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "char_width":10,"line_height":15,
        \\  "cursor":{"line":1,"column":3},
        \\  "line_runs":[{"row":0,"column":2,"text":"ab","foreground":"#000000",
        \\                "variable_pitch":true,"pixel_x":17,"pixel_width":23}]
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshot(a, snapshot.facts, snapshot.text.lines, snapshot.cursor, snapshot.viewport, &scene, &messages);
    const cursor = scene.cursor orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(i32, 28), cursor.x);
}

test "run fonts bound distinct alternate families" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "font_file":"/fonts/default.ttf",
        \\  "variable_font_file":"/fonts/serif.ttf",
        \\  "line_runs":[
        \\    {"row":0,"column":0,"text":"plain","foreground":"#000000"},
        \\    {"row":0,"column":2,"text":"serif","foreground":"#000000","font_file":"/fonts/serif.ttf","variable_pitch":true},
        \\    {"row":0,"column":4,"text":"sans","foreground":"#000000","font_file":"/fonts/sans.ttf","variable_pitch":true},
        \\    {"row":0,"column":6,"text":"again","foreground":"#000000","font_file":"/fonts/sans.ttf","variable_pitch":true},
        \\    {"row":0,"column":8,"text":"mono2","foreground":"#000000","font_file":"/fonts/othermono.ttf","variable_pitch":true},
        \\    {"row":0,"column":10,"text":"def","foreground":"#000000","font_file":"/fonts/default.ttf"}
        \\  ]
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    const families = [_]u8{ 0, 1, 2, 2, 3, 0 };
    for (snapshot.facts.line_runs, families) |run, family| {
        try std.testing.expectEqual(family, run.font_family);
    }
    try std.testing.expectEqualStrings("/fonts/sans.ttf", snapshot.alt_font_files[0].?);
    try std.testing.expectEqualStrings("/fonts/othermono.ttf", snapshot.alt_font_files[1].?);

    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshot(a, snapshot.facts, snapshot.text.lines, snapshot.cursor, snapshot.viewport, &scene, &messages);
    try std.testing.expectEqual(@as(usize, 6), scene.glyph_runs.items.len);
    for (scene.glyph_runs.items, families) |run, family| {
        try std.testing.expectEqual(family, run.font_family);
    }

    var scene2 = frontend.Scene.init(a);
    defer scene2.deinit();
    scene2.next_sequence = 1;
    var font_messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (font_messages.items) |message| a.free(message);
        font_messages.deinit(a);
    }
    try appendFontMessages(a, &scene2, snapshot.font_file, 13, snapshot.variable_font_file, snapshot.alt_font_files, &font_messages);
    try std.testing.expectEqual(@as(usize, 5), font_messages.items.len);
    try std.testing.expectEqualStrings("/fonts/serif.ttf", scene2.strings.lookup(variable_font_string_id).?.bytes);
    try std.testing.expectEqualStrings("/fonts/sans.ttf", scene2.strings.lookup(variable_font_string_id + 1).?.bytes);
    try std.testing.expectEqualStrings("/fonts/othermono.ttf", scene2.strings.lookup(variable_font_string_id + 2).?.bytes);
}

test "long line runs clamp to the window instead of failing the snapshot" {
    const a = std.testing.allocator;
    const long: [120]u8 = @splat('x');
    const json = try std.fmt.allocPrint(a, "{{\"frame_width\":600,\"frame_height\":400,\"window_width\":600,\"window_height\":300," ++
        "\"line_runs\":[{{\"row\":0,\"column\":0,\"text\":\"{s}\",\"foreground\":\"#000000\"}}]}}", .{&long});
    defer a.free(json);
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    // The scene validates a run against the owning window, and the adapter
    // emits window-relative coordinates: a run whose full-width extent exceeds
    // the window (a long line in a narrow frame) must clamp rather than reject
    // the whole snapshot.
    try appendWireSnapshot(a, snapshot.facts, snapshot.text.lines, snapshot.cursor, snapshot.viewport, &scene, &messages);
    try std.testing.expectEqual(@as(usize, 1), scene.glyph_runs.items.len);
    try std.testing.expect(scene.glyph_runs.items[0].width <= 600);
}

test "publishes the real font file and pixel size as string resources" {
    const a = std.testing.allocator;
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    scene.next_sequence = 1;
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    try appendFontMessages(a, &scene, "/usr/share/fonts/LiberationMono-Regular.ttf", 13, "/usr/share/fonts/DejaVuSerif.ttf", .{ null, null }, &messages);
    try std.testing.expectEqual(@as(usize, 3), messages.items.len);
    const file = scene.strings.lookup(default_font_string_id) orelse return error.MissingFontFile;
    try std.testing.expectEqualStrings("/usr/share/fonts/LiberationMono-Regular.ttf", file.bytes);
    const size = scene.strings.lookup(default_font_size_string_id) orelse return error.MissingFontSize;
    try std.testing.expectEqualStrings("13", size.bytes);
    try std.testing.expectEqual(@as(i32, 13), std.fmt.parseInt(i32, size.bytes, 10) catch 0);
    const variable = scene.strings.lookup(variable_font_string_id) orelse return error.MissingVariableFont;
    try std.testing.expectEqualStrings("/usr/share/fonts/DejaVuSerif.ttf", variable.bytes);
}

test "parses and publishes the frame echo text" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "echo":"ProtoEcho"
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqualStrings("ProtoEcho", snapshot.echo.?);
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    scene.next_sequence = 1;
    try appendEchoMessages(a, &scene, snapshot.echo, &messages);
    const resource = scene.strings.lookup(echo_string_id) orelse return error.MissingEchoResource;
    try std.testing.expectEqualStrings("ProtoEcho", resource.bytes);
    try std.testing.expectError(error.InvalidEchoFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"echo\":\"\"}"));
}

test "parses the mouse-face highlight facts" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "mouse_rects":[{"x":2,"y":0,"width":8,"height":15},{"x":0,"y":15,"width":40,"height":15}],
        \\  "mouse_background":"#33aa77"
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), snapshot.facts.mouse_rects.len);
    try std.testing.expectEqual(@as(i32, 2), snapshot.facts.mouse_rects[0].x);
    try std.testing.expectEqual(@as(i32, 8), snapshot.facts.mouse_rects[0].width);
    try std.testing.expectEqual([4]u8{ 0x33, 0xaa, 0x77, 255 }, snapshot.facts.mouse_background.?);
    try std.testing.expectEqual(mouse_face_id, mouseRectFaceId(0));
    try std.testing.expectEqual(mouse_rect_face_base_id, mouseRectFaceId(1));
    try std.testing.expectError(error.InvalidRegionFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"mouse_rects\":[{\"x\":-1,\"y\":0,\"width\":8,\"height\":15}]}"));
}

test "open-menu rows carry the real enable state" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "menu_bar":["Edit","File"],
        \\  "menu_open":{"item_id":1,"window_id":1,"x":0,"y":1,"width":20,"height":4,
        \\    "items":["Undo","--","Cut","Select All"],
        \\    "enabled":[true,false,false,true],
        \\    "keys":["C-x u","","C-w","C-x h"],
        \\    "helps":["Undo last change","","Cut","Select all"]}
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqual(@as(usize, 4), snapshot.open_menu.?.enabled.len);
    try std.testing.expect(snapshot.open_menu.?.enabled[0]);
    try std.testing.expect(!snapshot.open_menu.?.enabled[2]);
    try std.testing.expectEqual(@as(usize, 4), snapshot.open_menu.?.keys.len);
    try std.testing.expectEqualStrings("C-x u", snapshot.open_menu.?.keys[0]);
    try std.testing.expectEqualStrings("", snapshot.open_menu.?.keys[1]);
    try std.testing.expectEqualStrings("Undo last change", snapshot.open_menu.?.helps[0]);
    try std.testing.expectEqualStrings("", snapshot.open_menu.?.helps[1]);
    // A short or missing enable vector defaults the missing rows to enabled.
    var without_enable = try parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"menu_bar\":[\"Edit\"],\"menu_open\":{\"item_id\":1,\"window_id\":1,\"x\":0,\"y\":1,\"width\":20,\"height\":2,\"items\":[\"Undo\"]}}");
    defer without_enable.deinit(a);
    try std.testing.expect(without_enable.open_menu.?.enabled[0]);
    // A missing key vector leaves every row without a hint.
    try std.testing.expectEqualStrings("", without_enable.open_menu.?.keys[0]);
    try std.testing.expectEqualStrings("", without_enable.open_menu.?.helps[0]);
    // A mismatched length is rejected rather than guessed.
    try std.testing.expectError(error.InvalidMenuBarFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"menu_bar\":[\"Edit\"],\"menu_open\":{\"item_id\":1,\"window_id\":1,\"x\":0,\"y\":1,\"width\":20,\"height\":2,\"items\":[\"Undo\"],\"enabled\":[true,false]}}"));
    try std.testing.expectError(error.InvalidMenuBarFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"menu_bar\":[\"Edit\"],\"menu_open\":{\"item_id\":1,\"window_id\":1,\"x\":0,\"y\":1,\"width\":20,\"height\":2,\"items\":[\"Undo\"],\"keys\":[\"C-x u\",\"C-w\"]}}"));
    try std.testing.expectError(error.InvalidMenuBarFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"menu_bar\":[\"Edit\"],\"menu_open\":{\"item_id\":1,\"window_id\":1,\"x\":0,\"y\":1,\"width\":20,\"height\":2,\"items\":[\"Undo\"],\"helps\":[\"Undo\",\"Redo\"]}}"));
}

test "open-menu rows project real checkbox and radio state" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "menu_bar":["Options"],
        \\  "menu_open":{"item_id":1,"window_id":101,"x":0,"y":1,"width":20,"height":4,
        \\    "items":["Toggle","--","Radio","Command"],
        \\    "helps":["Toggle wrap","","Radio mode","Command help"],
        \\    "kind":["checkbox","command","radio","command"],
        \\    "selected":[true,false,false,false]}
        \\}
        \\
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    const menu = snapshot.open_menu.?;
    try std.testing.expectEqual(MenuRowKind.checkbox, menu.kinds[0]);
    try std.testing.expectEqual(MenuRowKind.radio, menu.kinds[2]);
    try std.testing.expectEqual(MenuRowKind.command, menu.kinds[3]);
    try std.testing.expect(menu.selected[0]);
    try std.testing.expect(!menu.selected[2]);
    try std.testing.expect(!menu.selected[3]);

    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = try buildScene(a, snapshot.facts, 1);
    defer scene.deinit();
    scene.next_sequence = 2;
    try appendMenuMessages(a, &scene, snapshot.menu_bar, snapshot.open_menu, &messages);
    const nodes = scene.menu_model.?.nodes;
    try std.testing.expectEqual(protocol.MenuNodeKind.checkbox, nodes[1].kind);
    try std.testing.expect(nodes[1].flags & protocol.MenuNodeFlags.selected != 0);
    try std.testing.expectEqual(protocol.MenuNodeKind.separator, nodes[2].kind);
    try std.testing.expectEqual(protocol.MenuNodeFlags.visible, nodes[2].flags);
    try std.testing.expectEqual(protocol.MenuNodeKind.radio, nodes[3].kind);
    try std.testing.expect(nodes[3].flags & protocol.MenuNodeFlags.selected == 0);
    try std.testing.expectEqual(protocol.MenuNodeKind.command, nodes[4].kind);
    try std.testing.expect(nodes[4].flags & protocol.MenuNodeFlags.selected == 0);
    try std.testing.expectEqualStrings("Toggle wrap", nodes[1].help[0..11]);
    try std.testing.expectEqual(@as(u8, 0), nodes[2].help_len);
    try std.testing.expectEqualStrings("Radio mode", nodes[3].help[0..10]);
    try std.testing.expectEqualStrings("Command help", nodes[4].help[0..12]);

    const base = "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"menu_bar\":[\"Options\"],\"menu_open\":{\"item_id\":1,\"window_id\":101,\"x\":0,\"y\":1,\"width\":20,\"height\":3,\"items\":[\"Toggle\"]";
    try std.testing.expectError(error.InvalidMenuBarFacts, parseSnapshot(a, base ++ ",\"kind\":[\"radio\",\"toggle\"]}}"));
    try std.testing.expectError(error.InvalidMenuBarFacts, parseSnapshot(a, base ++ ",\"kind\":[\"secret\"]}}"));
    try std.testing.expectError(error.InvalidMenuBarFacts, parseSnapshot(a, base ++ ",\"selected\":[true,false]}}"));
}

test "open-menu icons decode bounded XBM payloads into RGBA images" {
    const a = std.testing.allocator;
    const payload = "I2RlZmluZSBpY29uX3dpZHRoIDIKI2RlZmluZSBpY29uX2hlaWdodCAxCnN0YXRpYyBjaGFyIGljb25fYml0c1tdID0gezB4MDF9Ow==";
    const json = try std.fmt.allocPrint(a, "{{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"menu_bar\":[\"Options\"],\"menu_open\":{{\"item_id\":1,\"window_id\":1001,\"x\":0,\"y\":1,\"width\":20,\"height\":1,\"items\":[\"Icon\"],\"icon_ids\":[31],\"icon_generations\":[1],\"icon_payloads\":[\"{s}\"]}}}}", .{payload});
    defer a.free(json);
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), snapshot.open_menu.?.icon_payloads.len);
    try std.testing.expect(std.mem.startsWith(u8, snapshot.open_menu.?.icon_payloads[0], "#define icon_width 2\n"));

    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = try buildScene(a, snapshot.facts, 1);
    defer scene.deinit();
    scene.next_sequence = 2;
    try appendMenuMessages(a, &scene, snapshot.menu_bar, snapshot.open_menu, &messages);
    try std.testing.expectEqual(@as(usize, 4), messages.items.len);
    try std.testing.expectEqual(protocol.Message.image_define, (try protocol.decodeEnvelope(messages.items[0])).envelope.message_type);
    try std.testing.expectEqual(protocol.Message.image_data, (try protocol.decodeEnvelope(messages.items[1])).envelope.message_type);
    const image = scene.images.lookup(31) orelse return error.TestExpectedImage;
    try std.testing.expect(image.complete);
    try std.testing.expectEqual(@as(u32, 2), image.metadata.width);
    try std.testing.expectEqual(@as(u32, 1), image.metadata.height);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 255, 0, 0, 0, 0 }, image.bytes);
    try std.testing.expectEqual(@as(u32, 31), scene.menu_model.?.nodes[1].icon_image_id);

    const mismatch = "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"menu_bar\":[\"Options\"],\"menu_open\":{\"item_id\":1,\"window_id\":101,\"x\":0,\"y\":1,\"width\":20,\"height\":1,\"items\":[\"Icon\"],\"icon_payloads\":[\"not-base64\"]}}";
    try std.testing.expectError(error.InvalidMenuBarFacts, parseSnapshot(a, mismatch));
    const wrong_length = "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"menu_bar\":[\"Options\"],\"menu_open\":{\"item_id\":1,\"window_id\":101,\"x\":0,\"y\":1,\"width\":20,\"height\":2,\"items\":[\"Icon\",\"Other\"],\"icon_payloads\":[\"\"]}}";
    try std.testing.expectError(error.InvalidMenuBarFacts, parseSnapshot(a, wrong_length));

    const malformed_payload = "I2RlZmluZSBpY29uX3dpZHRoIDAKI2RlZmluZSBpY29uX2hlaWdodCAxCnN0YXRpYyBjaGFyIGljb25fYml0c1tdID0gezB4MDB9Ow==";
    const malformed = try std.fmt.allocPrint(a, "{{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"menu_bar\":[\"Options\"],\"menu_open\":{{\"item_id\":1,\"window_id\":1001,\"x\":0,\"y\":1,\"width\":20,\"height\":1,\"items\":[\"Icon\"],\"icon_ids\":[31],\"icon_generations\":[1],\"icon_payloads\":[\"{s}\"]}}}}", .{malformed_payload});
    defer a.free(malformed);
    var malformed_snapshot = try parseSnapshot(a, malformed);
    defer malformed_snapshot.deinit(a);
    var fallback_messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (fallback_messages.items) |message| a.free(message);
        fallback_messages.deinit(a);
    }
    var fallback_scene = try buildScene(a, malformed_snapshot.facts, 1);
    defer fallback_scene.deinit();
    fallback_scene.next_sequence = 2;
    try appendMenuMessages(a, &fallback_scene, malformed_snapshot.menu_bar, malformed_snapshot.open_menu, &fallback_messages);
    try std.testing.expectEqual(@as(usize, 2), fallback_messages.items.len);
    try std.testing.expectEqual(protocol.Message.menu_model, (try protocol.decodeEnvelope(fallback_messages.items[0])).envelope.message_type);
    try std.testing.expectEqual(protocol.Message.menu_open, (try protocol.decodeEnvelope(fallback_messages.items[1])).envelope.message_type);
    try std.testing.expectEqual(@as(u32, 31), fallback_scene.menu_model.?.nodes[1].icon_image_id);
    try std.testing.expectEqual(@as(u32, 1), fallback_scene.menu_model.?.nodes[1].icon_image_generation);
    try std.testing.expect(fallback_scene.images.lookup(31) == null);
}

test "open-menu oversized icon payload falls back without snapshot rejection" {
    const a = std.testing.allocator;
    const oversized_payload: [max_menu_icon_payload + 1]u8 = @splat('x');
    const encoded_len = std.base64.standard.Encoder.calcSize(oversized_payload.len);
    const encoded_payload = try a.alloc(u8, encoded_len);
    defer a.free(encoded_payload);
    _ = std.base64.standard.Encoder.encode(encoded_payload, &oversized_payload);

    const json = try std.fmt.allocPrint(
        a,
        "{{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"menu_bar\":[\"Options\"],\"menu_open\":{{\"item_id\":1,\"window_id\":1001,\"x\":0,\"y\":1,\"width\":20,\"height\":1,\"items\":[\"Icon\"],\"icon_ids\":[31],\"icon_generations\":[1],\"icon_payloads\":[\"{s}\"]}}}}",
        .{encoded_payload},
    );
    defer a.free(json);
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), snapshot.open_menu.?.icon_payloads[0].len);

    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = try buildScene(a, snapshot.facts, 1);
    defer scene.deinit();
    scene.next_sequence = 2;
    try appendMenuMessages(a, &scene, snapshot.menu_bar, snapshot.open_menu, &messages);
    try std.testing.expectEqual(@as(usize, 2), messages.items.len);
    try std.testing.expectEqual(protocol.Message.menu_model, (try protocol.decodeEnvelope(messages.items[0])).envelope.message_type);
    try std.testing.expectEqual(protocol.Message.menu_open, (try protocol.decodeEnvelope(messages.items[1])).envelope.message_type);
    try std.testing.expectEqual(@as(u32, 31), scene.menu_model.?.nodes[1].icon_image_id);
    try std.testing.expectEqual(@as(u32, 1), scene.menu_model.?.nodes[1].icon_image_generation);
    try std.testing.expect(scene.images.lookup(31) == null);
}

test "nested menu facts carry parent and submenu rows" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "menu_bar":["Edit","File"],
        \\  "menu_open":{"item_id":1001,"window_id":1,"x":10,"y":2,"width":20,"height":1,
        \\    "items":["Inside"],"enabled":[true],"keys":["C-x u"],"submenu":[false],
        \\    "parent_id":1,"parent_label":"Parent"}
        \\}
        \\
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqual(@as(u32, 1001), snapshot.open_menu.?.item_id);
    try std.testing.expectEqual(@as(u32, 1), snapshot.open_menu.?.parent_id);
    try std.testing.expectEqualStrings("Parent", snapshot.open_menu.?.parent_label);
    try std.testing.expect(!snapshot.open_menu.?.submenus[0]);
    try std.testing.expectError(error.InvalidMenuBarFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"menu_bar\":[\"Edit\"],\"menu_open\":{\"item_id\":1,\"window_id\":1,\"x\":0,\"y\":1,\"width\":20,\"height\":1,\"items\":[\"One\"],\"parent_id\":1,\"parent_label\":\"Parent\"}}"));
    try std.testing.expectError(error.InvalidMenuBarFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"menu_bar\":[\"Edit\"],\"menu_open\":{\"item_id\":1001,\"window_id\":1,\"x\":0,\"y\":1,\"width\":20,\"height\":1,\"items\":[\"One\"],\"parent_id\":2,\"parent_label\":\"Parent\"}}"));
}

test "menu path projects a bounded ancestor chain" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "menu_bar":["Edit"],
        \\  "menu_open":{"item_id":1100,"window_id":1,"x":48,"y":6,"width":20,"height":1,
        \\    "items":["Deepest"],"submenu":[false],
        \\    "parent_id":1,
        \\    "path":[{"id":1000,"label":"Sub"},{"id":1100,"label":"Nested"}]}
        \\}
        \\
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    const menu = snapshot.open_menu.?;
    try std.testing.expectEqual(@as(usize, 2), menu.path.len);
    try std.testing.expectEqual(@as(u32, 1000), menu.path[0].id);
    try std.testing.expectEqualStrings("Nested", menu.path[1].label);

    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = try buildScene(a, snapshot.facts, 1);
    defer scene.deinit();
    scene.next_sequence = 2;
    try appendMenuMessages(a, &scene, snapshot.menu_bar, snapshot.open_menu, &messages);
    const model = scene.menu_model.?;
    try std.testing.expectEqual(@as(usize, 4), model.nodes.len);
    try std.testing.expectEqual(@as(u8, 1), model.nodes[1].depth);
    try std.testing.expectEqual(@as(u32, 1000), model.nodes[1].item_id);
    try std.testing.expectEqual(@as(u32, 1), model.nodes[1].parent_item_id);
    try std.testing.expectEqual(@as(u8, 2), model.nodes[2].depth);
    try std.testing.expectEqual(@as(u32, 1100), model.nodes[2].item_id);
    try std.testing.expectEqual(@as(u32, 1000), model.nodes[2].parent_item_id);
    try std.testing.expectEqual(@as(u8, 3), model.nodes[3].depth);
    try std.testing.expectEqual(@as(u32, 1200), model.nodes[3].item_id);
    try std.testing.expectEqual(@as(u32, 1100), model.nodes[3].parent_item_id);

    const overflow = "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"menu_bar\":[\"Edit\"],\"menu_open\":{\"item_id\":1300,\"window_id\":1,\"x\":0,\"y\":1,\"width\":20,\"height\":1,\"items\":[\"One\"],\"parent_id\":1,\"path\":[{\"id\":1000,\"label\":\"A\"},{\"id\":1100,\"label\":\"B\"},{\"id\":1200,\"label\":\"C\"},{\"id\":1300,\"label\":\"D\"}]}}";
    try std.testing.expectError(error.InvalidMenuBarFacts, parseSnapshot(a, overflow));
}

test "bounded box line widths parse and reject out-of-range values" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "mode_line_box":"released","mode_line_box_width":2,
        \\  "tool_bar_box":"pressed","tool_bar_box_width":1
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqual(protocol.BoxStyle.released, snapshot.facts.mode_line_box);
    try std.testing.expectEqual(@as(i32, 2), snapshot.facts.mode_line_box_width);
    try std.testing.expectEqual(protocol.BoxStyle.pressed, snapshot.facts.tool_bar_box);
    try std.testing.expectEqual(@as(i32, 1), snapshot.facts.tool_bar_box_width);
    try std.testing.expectError(error.InvalidModeLineFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"mode_line_box\":\"released\",\"mode_line_box_width\":9}"));
    try std.testing.expectError(error.InvalidToolbarFacts, parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"tool_bar_box\":\"simple\",\"tool_bar_box_width\":-1}"));
}

test "parses real header-line and tab-line face colors" {
    const a = std.testing.allocator;
    const json =
        \\{
        \\  "frame_width":120,"frame_height":90,"window_width":110,"window_height":75,
        \\  "header_line_foreground":"#333333","header_line_background":"#e5e5e5",
        \\  "tab_line_foreground":"#000000","tab_line_background":"#d9d9d9"
        \\}
    ;
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqual([4]u8{ 0x33, 0x33, 0x33, 255 }, snapshot.facts.header_line_foreground.?);
    try std.testing.expectEqual([4]u8{ 0xe5, 0xe5, 0xe5, 255 }, snapshot.facts.header_line_background.?);
    try std.testing.expectEqual([4]u8{ 0x00, 0x00, 0x00, 255 }, snapshot.facts.tab_line_foreground.?);
    try std.testing.expectEqual([4]u8{ 0xd9, 0xd9, 0xd9, 255 }, snapshot.facts.tab_line_background.?);
}

test "builds a validated EUP snapshot scene" {
    const a = std.testing.allocator;
    const facts = try parse(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75}");
    var scene = try buildScene(a, facts, 3);
    defer scene.deinit();
    try std.testing.expectEqual(@as(u64, 1), scene.stats.frame_updates);
    try std.testing.expectEqual(@as(usize, 1), scene.windows.items.len);
    try std.testing.expectEqual(@as(usize, 15), scene.rows.items.len);
    try std.testing.expectEqual(@as(i32, 110), scene.windows.items[0].width);
}

test "wire snapshots advance contiguous scene sequences" {
    const a = std.testing.allocator;
    const parsed = try parse(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75}");
    const invalid = FrameFacts{ .frame_width = 0, .frame_height = 90, .window_width = 0, .window_height = 0 };
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var empty_scene = frontend.Scene.init(a);
    defer empty_scene.deinit();
    try std.testing.expectError(error.InvalidFrameFacts, appendWireSnapshot(a, invalid, &.{}, .{ .line = 1, .column = 0 }, .{ .start_line = 1, .line_count = 0 }, &empty_scene, &messages));

    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshot(a, parsed, &.{}, .{ .line = 1, .column = 0 }, .{ .start_line = 1, .line_count = 0 }, &scene, &messages);
    try std.testing.expectEqual(@as(usize, 2), messages.items.len);
    try std.testing.expectEqual(@as(u64, 1), scene.stats.frame_updates);
    try std.testing.expectEqual(@as(u64, 3), scene.next_sequence.?);

    try appendWireSnapshot(a, parsed, &.{}, .{ .line = 1, .column = 0 }, .{ .start_line = 1, .line_count = 0 }, &scene, &messages);
    try std.testing.expectEqual(@as(usize, 3), messages.items.len);
    try std.testing.expectEqual(@as(u64, 2), scene.stats.frame_updates);
    try std.testing.expectEqual(@as(u64, 4), scene.next_sequence.?);
}

test "focused public fact wires FRAME_FOCUS" {
    const a = std.testing.allocator;
    var focused = try parseSnapshot(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"focused\":true}");
    defer focused.deinit(a);
    try std.testing.expect(focused.focused);
    try std.testing.expect(focused.facts.focused);
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshot(a, focused.facts, &.{}, .{ .line = 1, .column = 0 }, .{ .start_line = 1, .line_count = 0 }, &scene, &messages);
    try std.testing.expectEqual(@as(usize, 3), messages.items.len);
    try std.testing.expect(scene.frames.lookup(1).?.focused);
}

test "title facts parse and wire through string plus frame title" {
    const a = std.testing.allocator;
    const json = "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"title\":\"Emacs Proto-UI\"}";
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqualStrings("Emacs Proto-UI", snapshot.title.?);

    const invalid = "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"title\":\"\"}";
    try std.testing.expectError(error.InvalidTitleFacts, parseSnapshot(a, invalid));

    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshot(a, snapshot.facts, snapshot.text.lines, snapshot.cursor, snapshot.viewport, &scene, &messages);
    try appendTitleMessages(a, &scene, snapshot.title.?, &messages);
    try std.testing.expectEqual(@as(usize, 4), messages.items.len);
    try std.testing.expectEqual(@as(u64, 5), scene.next_sequence.?);
    try std.testing.expectEqualStrings("Emacs Proto-UI", scene.title.?);
}

test "viewport facts parse and wire into scene metadata" {
    const a = std.testing.allocator;
    const json = "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75,\"text\":[\"one\",\"two\"],\"cursor\":{\"line\":1,\"column\":0},\"window_start_line\":3,\"window_visible_lines\":2}";
    var snapshot = try parseSnapshot(a, json);
    defer snapshot.deinit(a);
    try std.testing.expectEqual(ViewportFacts{ .start_line = 3, .line_count = 2 }, snapshot.viewport);
    var invalid_viewport: ViewportFacts = .{ .start_line = 0, .line_count = 2 };
    try std.testing.expect(!invalid_viewport.valid());

    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    const facts = try parse(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75}");
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshot(a, facts, snapshot.text.lines, snapshot.cursor, snapshot.viewport, &scene, &messages);
    try std.testing.expectEqual(frontend.Viewport{ .start_line = 3, .line_count = 2 }, scene.viewport.?);
    try std.testing.expectError(error.InvalidViewportFacts, appendWireSnapshot(a, facts, snapshot.text.lines, snapshot.cursor, .{ .start_line = 0, .line_count = 2 }, &scene, &messages));
}

test "wire snapshot carries validated public text lines" {
    const a = std.testing.allocator;
    const parsed = try parse(a, "{\"frame_width\":120,\"frame_height\":90,\"window_width\":110,\"window_height\":75}");
    var text = try parseText(a, "Emacs Proto-UI\nvisible ASCII\n");
    defer text.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), text.lines.len);
    try std.testing.expectEqualStrings("visible ASCII", text.lines[1]);

    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshot(a, parsed, text.lines, .{ .line = 1, .column = 1 }, .{ .start_line = 1, .line_count = 2 }, &scene, &messages);
    try std.testing.expectEqual(@as(usize, 2), scene.text.items.len);
    try std.testing.expectEqualStrings("Emacs Proto-UI", scene.text.items[0].bytes);
    try std.testing.expectEqualStrings("visible ASCII", scene.text.items[1].bytes);
    try std.testing.expectEqual(@as(i32, 8), scene.cursor.?.x);
    try std.testing.expectEqual(@as(i32, 0), scene.cursor.?.y);
    try std.testing.expectError(error.InvalidTextFacts, parseText(a, "bad\n\x00"));
    try std.testing.expectError(error.InvalidTextFacts, parseText(a, "bad\n\xff\xfe"));
    var unicode = try parseText(a, "你好é\u{0301}\n");
    defer unicode.deinit(a);
    var unicode_scene = frontend.Scene.init(a);
    defer unicode_scene.deinit();
    try appendWireSnapshot(a, parsed, unicode.lines, .{ .line = 1, .column = 2 }, .{ .start_line = 1, .line_count = 1 }, &unicode_scene, &messages);
    try std.testing.expectEqualStrings("你好é\u{0301}", unicode_scene.text.items[0].bytes);

    const narrow = FrameFacts{ .frame_width = 9, .frame_height = 90, .window_width = 9, .window_height = 75 };
    // A cursor the window cannot hold clamps to the window instead of failing
    // the whole snapshot.
    try appendWireSnapshot(a, narrow, text.lines, .{ .line = 1, .column = 1 }, .{ .start_line = 1, .line_count = 2 }, &scene, &messages);
    try std.testing.expectEqual(@as(i32, 0), scene.cursor.?.x);
}

test "a real cursor column reaches the cursor rect" {
    const a = std.testing.allocator;
    const facts = FrameFacts{
        .frame_width = 400,
        .frame_height = 200,
        .window_width = 400,
        .window_height = 150,
        .char_width = 10,
    };
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| a.free(message);
        messages.deinit(a);
    }
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try appendWireSnapshot(a, facts, &.{"Emacs"}, .{ .line = 1, .column = 20 }, .{ .start_line = 1, .line_count = 1 }, &scene, &messages);
    // The adapter places the cursor at its real column on the frame's real
    // character cell (10 here), not a hardcoded eight-unit cell.
    try std.testing.expectEqual(@as(i32, 200), scene.cursor.?.x);
}

test "parses and validates bounded cursor facts" {
    const a = std.testing.allocator;
    const cursor = try parseCursor(a, "{\"line\":2,\"column\":17}");
    try std.testing.expectEqual(@as(i32, 2), cursor.line);
    try std.testing.expectEqual(@as(i32, 17), cursor.column);
    try std.testing.expectError(error.InvalidCursorFacts, parseCursor(a, "{\"line\":-1,\"column\":0}"));
    try std.testing.expectError(error.InvalidCursorFacts, parseCursor(a, "{\"line\":0,\"column\":0}"));
    try std.testing.expectError(error.InvalidCursorFacts, parseCursor(a, "{\"line\":32,\"column\":0}"));
}
