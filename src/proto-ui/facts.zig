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
};

pub const CursorFacts = struct {
    line: i32,
    column: i32,
};

pub const max_observed_windows: usize = 16;

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
        if (self.start_line < 1 or self.line_count < 0) return false;
        const sum = @addWithOverflow(self.start_line, self.line_count);
        if (sum[1] != 0) return false;
        return sum[0] <= max_text_lines + 1;
    }
};

pub const max_text_lines: usize = 32;
pub const max_text_columns: usize = 120;
pub const max_text_bytes: usize = max_text_columns;
pub const max_lines_per_window: usize = 8;
pub const max_total_text_lines: usize = 128;

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

pub const Snapshot = struct {
    facts: FrameFacts,
    windows: []WindowFact = &.{},
    contents: []WindowContent = &.{},
    text: TextLines = .{},
    cursor: CursorFacts = .{ .line = 0, .column = 0 },
    viewport: ViewportFacts = .{ .start_line = 1, .line_count = 0 },
    title: ?[]const u8 = null,

    pub fn eql(left: Snapshot, right: Snapshot) bool {
        return factsEql(left.facts, right.facts) and left.text.eql(right.text) and
            windowsEql(left.windows, right.windows) and
            windowContentsEql(left.contents, right.contents) and
            std.meta.eql(left.cursor, right.cursor) and
            std.meta.eql(left.viewport, right.viewport) and
            ((left.title == null and right.title == null) or
                (left.title != null and right.title != null and
                    std.mem.eql(u8, left.title.?, right.title.?)));
    }

    pub fn deinit(self: *Snapshot, gpa: std.mem.Allocator) void {
        if (self.windows.len != 0) gpa.free(self.windows);
        self.windows = &.{};
        for (self.contents) |*content| content.deinit(gpa);
        if (self.contents.len != 0) gpa.free(self.contents);
        self.contents = &.{};
        self.text.deinit(gpa);
        if (self.title) |title| gpa.free(title);
        self.title = null;
    }
};
pub const Error = std.json.ParseError(std.json.Scanner) || error{
    InvalidFrameFacts,
    InvalidWindowFacts,
    InvalidWindowContent,
    InvalidViewportFacts,
    InvalidModeLineFacts,
    InvalidAuxLineFacts,
    InvalidTitleFacts,
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
    title: ?[]const u8 = null,
};

const WindowStateWire = struct {
    id: u32,
    lines: []const []const u8 = &.{},
    window_start_line: i32 = 1,
    window_visible_lines: i32 = 0,
    cursor: ?CursorFacts = null,
    cursor_active: bool = false,
    mode_line: ?[]const u8 = null,
    mode_line_height: i32 = 0,
    header_line: ?[]const u8 = null,
    header_line_height: i32 = 0,
    tab_line: ?[]const u8 = null,
    tab_line_height: i32 = 0,
};

fn cursorFitsVertical(cursor: CursorFacts, window_height: i32) bool {
    const row_height: i64 = @max(1, @divTrunc(window_height, 15));
    const cursor_height: i64 = @max(2, @min(18, row_height));
    return @as(i64, cursor.line - 1) * row_height + cursor_height <= window_height;
}

fn parseWindowText(gpa: std.mem.Allocator, lines: []const []const u8) !TextLines {
    if (lines.len > max_lines_per_window) return error.InvalidWindowContent;
    var total: usize = 0;
    for (lines) |line| {
        if (!frontend.validBoundedUtf8Line(line, max_text_columns)) return error.InvalidWindowContent;
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

fn parseWindowContents(gpa: std.mem.Allocator, states: []const WindowStateWire, windows: []const WindowFact) ![]WindowContent {
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
            if (!cursorFitsVertical(cursor, fact.height))
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
        contents[index] = .{
            .id = state.id,
            .text = try parseWindowText(gpa, state.lines),
            .viewport = viewport,
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
            !frontend.validBoundedUtf8Line(line, max_text_columns)) return error.InvalidTextFacts;
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
        if (!frontend.validBoundedUtf8Line(line, max_text_columns)) return error.InvalidTextFacts;
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
    const contents = try parseWindowContents(gpa, wire.window_states, windows);
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
    return .{
        .facts = .{
            .frame_width = wire.frame_width,
            .frame_height = wire.frame_height,
            .window_width = wire.window_width,
            .window_height = wire.window_height,
        },
        .windows = windows,
        .contents = contents,
        .text = .{ .lines = slices, .owner = owner },
        .cursor = wire.cursor,
        .viewport = viewport,
        .title = if (wire.title) |title| try gpa.dupe(u8, title) else null,
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
        \\     "tab_line":"LT","tab_line_height":1},
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
    const row_count: i32 = 15;
    const row_height = @max(1, @divTrunc(facts.window_height, row_count));
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
        .kind = 1,
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

    const update_sequence = sequence;
    const snapshot_wire: SnapshotWire = .{
        .frame_width = facts.frame_width,
        .frame_height = facts.frame_height,
        .window_width = facts.window_width,
        .window_height = facts.window_height,
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
        const row_count: i32 = 15;
        const row_height = @max(1, @divTrunc(window.height, row_count));
        var row_index: i32 = 0;
        while (row_index < row_count) : (row_index += 1) {
            try frontend.encodeRow(gpa, .{
                .window_id = window.id,
                .index = @intCast(row_index),
                .flags = 0,
                .x = 0,
                .y = row_index * row_height,
                .width = window.width,
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
                .width = window.width,
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
                    .width = window.width,
                    .height = height,
                    .flags = aux[0],
                    .line = line,
                }, &aux_line_bytes);
            }
        }
    }
    const selected_row_count: i32 = 15;
    const wire_viewport: ViewportFacts = .{
        .start_line = viewport.start_line,
        .line_count = @min(viewport.line_count, selected_row_count),
    };
    if (cursor.line < 1 or cursor.line > selected_row_count or
        @as(i64, cursor.column) * 8 + 2 > facts.window_width)
        return error.InvalidCursorFacts;

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
        const row_height = @max(1, @divTrunc(window.height, selected_row_count));
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
        if (bounded_cursor.line < 1 or bounded_cursor.line > selected_row_count or
            bounded_cursor.column < 0 or
            @as(i64, bounded_cursor.column) * 8 + 2 > window.width)
            return error.InvalidCursorFacts;
        if (!cursorFitsVertical(bounded_cursor, window.height))
            return error.InvalidCursorFacts;
        if (wire_cursor_active) active_cursor_count += 1;
        try frontend.encodeCursor(gpa, .{
            .window_id = window.id,
            .x = bounded_cursor.column * 8,
            .y = (bounded_cursor.line - 1) * row_height,
            .width = 2,
            .height = @max(2, @min(18, row_height)),
            .kind = 1,
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
            if (line.len > max_text_columns) return error.InvalidTextFacts;
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
}

test "parses and validates bounded frame facts" {
    const a = std.testing.allocator;
    const facts = try parse(a, "{\"frame_width\":100,\"frame_height\":80,\"window_width\":90,\"window_height\":70}");
    try std.testing.expectEqual(@as(i32, 100), facts.frame_width);
    try std.testing.expectError(error.InvalidFrameFacts, parse(a, "{\"frame_width\":0,\"frame_height\":80,\"window_width\":0,\"window_height\":0}"));
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
    try std.testing.expectError(error.InvalidCursorFacts, appendWireSnapshot(a, narrow, text.lines, .{ .line = 1, .column = 1 }, .{ .start_line = 1, .line_count = 2 }, &scene, &messages));
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
