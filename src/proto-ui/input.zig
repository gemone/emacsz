//! Bounded SDL-to-EUP input translation for the facts profile.

const std = @import("std");
const frontend = @import("frontend.zig");

pub const SDL_EVENT_KEY_DOWN: c_uint = 0x300;
pub const SDL_EVENT_TEXT_INPUT: c_uint = 0x303;

pub const SDL_SCANCODE_BACKSPACE: i32 = 42;
pub const SDL_SCANCODE_RIGHT: i32 = 79;
pub const SDL_SCANCODE_LEFT: i32 = 80;
pub const SDL_SCANCODE_DOWN: i32 = 81;
pub const SDL_SCANCODE_UP: i32 = 82;

pub const max_text_bytes: usize = 120;
pub const queue_capacity: usize = 32;

pub const TextEvent = struct {
    buffer: [max_text_bytes]u8 = undefined,
    length: usize = 0,

    pub fn bytes(self: *const TextEvent) []const u8 {
        return self.buffer[0..self.length];
    }
};

pub const TranslatedEvent = union(enum) {
    key: frontend.KeyEvent,
    text: TextEvent,
};

pub const Queue = struct {
    items: [queue_capacity]TranslatedEvent = undefined,
    length: usize = 0,

    pub fn pushKey(self: *Queue, event: frontend.KeyEvent) !void {
        if (self.length == queue_capacity) return error.InputQueueFull;
        self.items[self.length] = .{ .key = event };
        self.length += 1;
    }

    pub fn pushText(self: *Queue, text: []const u8) !void {
        if (text.len == 0 or text.len > max_text_bytes) return error.InvalidInputText;
        for (text) |byte| {
            if (byte < 0x20 or byte > 0x7e) return error.InvalidInputText;
        }
        if (self.length == queue_capacity) return error.InputQueueFull;
        var translated: TextEvent = .{ .length = text.len };
        @memcpy(translated.buffer[0..text.len], text);
        self.items[self.length] = .{ .text = translated };
        self.length += 1;
    }

    pub fn clear(self: *Queue) void {
        self.length = 0;
    }
};

pub fn translateKey(
    scancode: i32,
    down: bool,
    repeat: bool,
    modifiers: u16,
) ?frontend.KeyEvent {
    if (!down or repeat or modifiers != 0) return null;
    const action: frontend.KeyAction = switch (scancode) {
        SDL_SCANCODE_BACKSPACE => .backspace,
        SDL_SCANCODE_LEFT => .cursor_left,
        SDL_SCANCODE_RIGHT => .cursor_right,
        SDL_SCANCODE_UP => .cursor_up,
        SDL_SCANCODE_DOWN => .cursor_down,
        else => return null,
    };
    return .{ .action = action, .state = 1, .modifiers = 0 };
}

pub fn translateText(source: ?[*:0]const u8) ?TextEvent {
    const source_text = source orelse return null;
    const text = std.mem.span(source_text);
    if (text.len == 0 or text.len > max_text_bytes) return null;
    for (text) |byte| {
        if (byte < 0x20 or byte > 0x7e) return null;
    }
    var translated: TextEvent = .{ .length = text.len };
    @memcpy(translated.buffer[0..text.len], text);
    return translated;
}

test "translates only pressed unmodified bounded editing keys" {
    try std.testing.expectEqual(frontend.KeyAction.backspace, translateKey(SDL_SCANCODE_BACKSPACE, true, false, 0).?.action);
    try std.testing.expectEqual(frontend.KeyAction.cursor_left, translateKey(SDL_SCANCODE_LEFT, true, false, 0).?.action);
    try std.testing.expectEqual(frontend.KeyAction.cursor_right, translateKey(SDL_SCANCODE_RIGHT, true, false, 0).?.action);
    try std.testing.expectEqual(frontend.KeyAction.cursor_up, translateKey(SDL_SCANCODE_UP, true, false, 0).?.action);
    try std.testing.expectEqual(frontend.KeyAction.cursor_down, translateKey(SDL_SCANCODE_DOWN, true, false, 0).?.action);
    try std.testing.expectEqual(@as(?frontend.KeyEvent, null), translateKey(SDL_SCANCODE_BACKSPACE, false, false, 0));
    try std.testing.expectEqual(@as(?frontend.KeyEvent, null), translateKey(SDL_SCANCODE_BACKSPACE, true, true, 0));
    try std.testing.expectEqual(@as(?frontend.KeyEvent, null), translateKey(SDL_SCANCODE_BACKSPACE, true, false, 1));
    try std.testing.expectEqual(@as(?frontend.KeyEvent, null), translateKey(999, true, false, 0));
}

test "queue copies and bounds printable text" {
    var queue: Queue = .{};
    try queue.pushText("Emacs");
    try queue.pushKey(.{ .action = .cursor_left });
    try std.testing.expectEqual(@as(usize, 2), queue.length);
    try std.testing.expectEqualStrings("Emacs", queue.items[0].text.bytes());
    try std.testing.expectEqual(frontend.KeyAction.cursor_left, queue.items[1].key.action);

    try std.testing.expectError(error.InvalidInputText, queue.pushText(""));
    try std.testing.expectError(error.InvalidInputText, queue.pushText("CJK 字"));
    const oversized = "a" ** 121;
    try std.testing.expectError(error.InvalidInputText, queue.pushText(oversized[0..]));

    var many: Queue = .{};
    for (0..queue_capacity) |_| try many.pushText("x");
    try std.testing.expectError(error.InputQueueFull, many.pushText("x"));
}
