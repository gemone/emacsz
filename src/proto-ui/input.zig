//! Bounded SDL-to-EUP input translation for the facts profile.

const std = @import("std");
const frontend = @import("frontend.zig");

pub const SDL_EVENT_KEY_DOWN: c_uint = 0x300;
pub const SDL_EVENT_TEXT_INPUT: c_uint = 0x303;

pub const SDL_SCANCODE_COPY: i32 = 6;
pub const SDL_SCANCODE_BACKSPACE: i32 = 42;
pub const SDL_SCANCODE_RIGHT: i32 = 79;
pub const SDL_SCANCODE_LEFT: i32 = 80;
pub const SDL_SCANCODE_DOWN: i32 = 81;
pub const SDL_SCANCODE_UP: i32 = 82;
pub const SDL_SCANCODE_C: i32 = 6;
pub const SDL_SCANCODE_V: i32 = 25;

pub const max_text_bytes: usize = 120;
pub const queue_capacity: usize = 32;
pub const sdl_ctrl_modifiers: u16 = 0x00c0;
pub const max_clipboard_bytes: usize = 120;

/// Enforces the facts-profile reverse-input sequencing contract: exactly one
/// input may be in flight, ACKs must match that sequence, and sequence zero is
/// reserved. The EPXL framing layer remains responsible for wire encoding.
pub const SenderState = struct {
    next_sequence: u64 = 1,
    in_flight: ?u64 = null,
    last_acknowledged: u64 = 0,

    pub fn takeSequence(self: *SenderState) !u64 {
        if (self.in_flight != null) return error.InputInFlight;
        const sequence = self.next_sequence;
        self.next_sequence += 1;
        self.in_flight = sequence;
        return sequence;
    }

    pub fn acknowledge(self: *SenderState, sequence: u64) bool {
        if (sequence == 0 or self.in_flight != sequence) return false;
        self.last_acknowledged = sequence;
        self.in_flight = null;
        return true;
    }
};

/// Validates a bounded apply-ACK payload containing exactly one decimal
/// sequence. Trailing filesystem newline whitespace is accepted.
pub fn validApplyAck(payload: []const u8, expected_sequence: u64) bool {
    const trimmed = std.mem.trim(u8, payload, " \t\r\n");
    const sequence = std.fmt.parseInt(u64, trimmed, 10) catch return false;
    return sequence == expected_sequence;
}

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
    pointer: frontend.PointerInput,
    wheel: frontend.WheelInput,
};

pub const TextSupport = enum { ascii, unicode };

pub fn isAsciiText(text: []const u8) bool {
    for (text) |byte| {
        if (byte < 0x20 or byte > 0x7e) return false;
    }
    return true;
}

pub fn validTextInput(text: []const u8) bool {
    return text.len > 0 and text.len <= max_text_bytes and
        frontend.validBoundedUtf8Text(text, max_text_bytes);
}

pub const Queue = struct {
    items: [queue_capacity]TranslatedEvent = undefined,
    length: usize = 0,

    pub fn pushKey(self: *Queue, event: frontend.KeyEvent) !void {
        if (self.length == queue_capacity) return error.InputQueueFull;
        self.items[self.length] = .{ .key = event };
        self.length += 1;
    }

    pub fn pushPointer(self: *Queue, event: frontend.PointerInput) !void {
        if (!event.valid()) return error.InvalidPointerIntent;
        if (self.length == queue_capacity) return error.InputQueueFull;
        self.items[self.length] = .{ .pointer = event };
        self.length += 1;
    }

    pub fn pushWheel(self: *Queue, event: frontend.WheelInput) !void {
        if (!event.valid()) return error.InvalidWheelIntent;
        if (self.length == queue_capacity) return error.InputQueueFull;
        self.items[self.length] = .{ .wheel = event };
        self.length += 1;
    }

    pub fn pushText(self: *Queue, text: []const u8) !void {
        if (!validTextInput(text)) return error.InvalidInputText;
        if (self.length == queue_capacity) return error.InputQueueFull;
        var translated: TextEvent = .{ .length = text.len };
        @memcpy(translated.buffer[0..text.len], text);
        self.items[self.length] = .{ .text = translated };
        self.length += 1;
    }

    pub fn pop(self: *Queue) ?TranslatedEvent {
        if (self.length == 0) return null;
        const item = self.items[0];
        std.mem.copyForwards(TranslatedEvent, self.items[0 .. self.length - 1], self.items[1..self.length]);
        self.length -= 1;
        return item;
    }

    pub fn clear(self: *Queue) void {
        self.length = 0;
    }
};

/// Bounded frontend-owned delivery state. The queue preserves intent order;
/// `pending` retains the one EPXL intent whose transport ACK has not arrived,
/// including across a reconnect. Retry attempts use the original wire sequence.
pub const DeliveryJournal = struct {
    queue: Queue = .{},
    sender: SenderState = .{},
    pending: ?TranslatedEvent = null,
    attempts: u32 = 0,
    max_attempts: u32 = 3,
    retry_armed: bool = false,
    pointer_active: bool = false,

    pub const Sent = struct {
        sequence: u64,
        event: TranslatedEvent,
    };

    pub fn pushKey(self: *DeliveryJournal, event: frontend.KeyEvent) !void {
        if (self.pointer_active) return error.PointerSessionActive;
        try self.queue.pushKey(event);
    }

    pub fn pushPointer(self: *DeliveryJournal, event: frontend.PointerInput) !void {
        if (!event.valid()) return error.InvalidPointerIntent;
        if (self.queue.length == queue_capacity) return error.InputQueueFull;
        var next_active = self.pointer_active;
        switch (event.phase) {
            .press => {
                if (self.pointer_active) return error.PointerSessionActive;
                next_active = true;
            },
            .motion => {
                const dragging = event.button == 1;
                if (dragging != self.pointer_active) return error.PointerSessionActive;
            },
            .release => {
                if (!self.pointer_active) return error.PointerSessionActive;
                next_active = false;
            },
        }
        // The capacity precheck makes the session transition and enqueue atomic
        // for this fixed-capacity queue; queue.pushPointer cannot then fail.
        try self.queue.pushPointer(event);
        self.pointer_active = next_active;
    }

    pub fn pushWheel(self: *DeliveryJournal, event: frontend.WheelInput) !void {
        if (self.pointer_active) return error.PointerSessionActive;
        try self.queue.pushWheel(event);
    }

    pub fn pushText(self: *DeliveryJournal, text: []const u8) !void {
        if (self.pointer_active) return error.PointerSessionActive;
        try self.queue.pushText(text);
    }

    pub fn pushTextAllowed(
        self: *DeliveryJournal,
        text: []const u8,
        support: TextSupport,
    ) !void {
        if (!validTextInput(text)) return error.InvalidInputText;
        if (!isAsciiText(text) and support != .unicode)
            return error.TextCapabilityNotNegotiated;
        try self.pushText(text);
    }

    pub fn take(self: *DeliveryJournal) !?Sent {
        if (self.pending == null) {
            self.pending = self.queue.pop() orelse return null;
            self.attempts = 0;
        }
        if (self.attempts >= self.max_attempts) return error.DeliveryRetriesExhausted;
        const sequence = if (self.sender.in_flight) |sequence| blk: {
            if (!self.retry_armed) return error.InputInFlight;
            break :blk sequence;
        } else try self.sender.takeSequence();
        self.retry_armed = false;
        self.attempts += 1;
        return .{ .sequence = sequence, .event = self.pending.? };
    }

    pub fn beginRetry(self: *DeliveryJournal) void {
        if (self.pending != null and self.sender.in_flight != null) self.retry_armed = true;
    }

    pub fn acknowledge(self: *DeliveryJournal, sequence: u64) bool {
        if (!self.sender.acknowledge(sequence)) return false;
        self.pending = null;
        self.attempts = 0;
        self.retry_armed = false;
        return true;
    }
};

pub fn isCopyShortcut(
    scancode: i32,
    down: bool,
    repeat: bool,
    modifiers: u16,
) bool {
    return down and !repeat and scancode == SDL_SCANCODE_COPY and
        modifiers & sdl_ctrl_modifiers != 0 and modifiers & ~sdl_ctrl_modifiers == 0;
}

pub fn validClipboardText(text: []const u8) bool {
    for (text) |byte| {
        if (!std.ascii.isPrint(byte)) return false;
    }
    return text.len > 0 and text.len <= max_clipboard_bytes;
}

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

pub fn translateText(source: ?[*:0]const u8, support: TextSupport) ?TextEvent {
    const source_text = source orelse return null;
    const text = std.mem.span(source_text);
    if (!validTextInput(text)) return null;
    if (!isAsciiText(text) and support != .unicode) return null;
    var translated: TextEvent = .{ .length = text.len };
    @memcpy(translated.buffer[0..text.len], text);
    return translated;
}

pub fn isPasteShortcut(
    scancode: i32,
    down: bool,
    repeat: bool,
    modifiers: u16,
) bool {
    return down and !repeat and scancode == SDL_SCANCODE_V and
        modifiers & sdl_ctrl_modifiers != 0 and modifiers & ~sdl_ctrl_modifiers == 0;
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

test "copy shortcut requires pressed non-repeat Ctrl+C" {
    try std.testing.expect(isCopyShortcut(6, true, false, 0x40));
    try std.testing.expect(isCopyShortcut(6, true, false, 0x80));
    try std.testing.expect(!isCopyShortcut(6, false, false, 0x40));
    try std.testing.expect(!isCopyShortcut(6, true, true, 0x40));
    try std.testing.expect(!isCopyShortcut(6, true, false, 0));
    try std.testing.expect(!isCopyShortcut(6, true, false, 0xc1));
}

test "validates bounded clipboard copy payload" {
    try std.testing.expect(validClipboardText("Emacs Proto-UI"));
    try std.testing.expect(!validClipboardText(""));
    try std.testing.expect(!validClipboardText("a" ** 121));
    try std.testing.expect(!validClipboardText("bad\npayload"));
}

test "text support validates ASCII, Unicode, and hostile bytes" {
    try std.testing.expect(isAsciiText("Emacs"));
    try std.testing.expect(!isAsciiText("你好"));
    try std.testing.expect(validTextInput("你好"));
    try std.testing.expect(validTextInput("e\u{0301}"));
    try std.testing.expect(!validTextInput(""));
    try std.testing.expect(!validTextInput("a\x00b"));
    try std.testing.expect(!validTextInput("a" ** 121));
    try std.testing.expect(!validTextInput("\xff\xfe"));

    try std.testing.expect(translateText("X", .ascii) != null);
    try std.testing.expect(translateText("你好", .unicode) != null);
    try std.testing.expect(translateText("你好", .ascii) == null);
    try std.testing.expect(translateText(null, .unicode) == null);
    try std.testing.expect(translateText("", .unicode) == null);
    try std.testing.expect(translateText("\xff\xfe", .unicode) == null);
}

test "delivery gate rejects Unicode without side effects under ASCII mode" {
    var journal: DeliveryJournal = .{};
    try journal.pushTextAllowed("ASCII", .ascii);
    try std.testing.expectEqual(@as(usize, 1), journal.queue.length);
    try std.testing.expectError(
        error.TextCapabilityNotNegotiated,
        journal.pushTextAllowed("你好", .ascii),
    );
    try std.testing.expectEqual(@as(usize, 1), journal.queue.length);
    try std.testing.expectEqualStrings("ASCII", journal.queue.items[0].text.bytes());

    try journal.pushTextAllowed("你好", .unicode);
    try std.testing.expectEqual(@as(usize, 2), journal.queue.length);
    try std.testing.expectEqualStrings("你好", journal.queue.items[1].text.bytes());
}

test "sender permits one monotonic in-flight input and exact ACK" {
    var sender: SenderState = .{};
    const first = try sender.takeSequence();
    try std.testing.expectEqual(@as(u64, 1), first);
    try std.testing.expectError(error.InputInFlight, sender.takeSequence());
    try std.testing.expect(!sender.acknowledge(0));
    try std.testing.expect(!sender.acknowledge(2));
    try std.testing.expect(sender.acknowledge(first));
    try std.testing.expectEqual(@as(u64, 1), sender.last_acknowledged);

    const second = try sender.takeSequence();
    try std.testing.expectEqual(@as(u64, 2), second);
    try std.testing.expect(sender.acknowledge(second));
    try std.testing.expectEqual(@as(u64, 2), sender.last_acknowledged);
}

test "pointer queue rejects bounded-profile violations before journaling" {
    var queue: Queue = .{};
    try std.testing.expectError(error.InvalidPointerIntent, queue.pushPointer(.{ .phase = .motion, .x = -1, .y = 0 }));
    try std.testing.expectError(error.InvalidPointerIntent, queue.pushPointer(.{ .phase = .motion, .x = frontend.max_pointer_coordinate + 1, .y = 0 }));
    try std.testing.expectError(error.InvalidPointerIntent, queue.pushPointer(.{ .phase = .motion, .x = 0, .y = 0, .modifiers = 1 }));
    try std.testing.expectError(error.InvalidPointerIntent, queue.pushPointer(.{ .phase = .motion, .x = 0, .y = 0, .button = 2 }));
    try std.testing.expectError(error.InvalidPointerIntent, queue.pushPointer(.{ .phase = .press, .x = 0, .y = 0, .button = 1, .clicks = 2 }));
    try std.testing.expectEqual(@as(usize, 0), queue.length);
}

test "pointer journal enforces ordered drag sessions" {
    var journal: DeliveryJournal = .{};
    try std.testing.expectError(error.PointerSessionActive, journal.pushPointer(.{ .phase = .release, .button = 1, .x = 1, .y = 1, .clicks = 1 }));
    try std.testing.expectError(error.PointerSessionActive, journal.pushPointer(.{ .phase = .motion, .button = 1, .x = 1, .y = 1 }));

    try journal.pushPointer(.{ .phase = .press, .button = 1, .x = 10, .y = 2, .clicks = 1 });
    try std.testing.expect(journal.pointer_active);
    try journal.pushPointer(.{ .phase = .motion, .button = 1, .x = 20, .y = 3 });
    try std.testing.expectError(error.PointerSessionActive, journal.pushKey(.{ .action = .backspace }));
    try journal.pushPointer(.{ .phase = .release, .button = 1, .x = 30, .y = 4, .clicks = 1 });
    try std.testing.expect(!journal.pointer_active);
    try journal.pushKey(.{ .action = .backspace });
}

test "pointer session state rolls back when the bounded queue is full" {
    var journal: DeliveryJournal = .{};
    while (journal.queue.length < queue_capacity) try journal.queue.pushText("x");
    try std.testing.expectError(error.InputQueueFull, journal.pushPointer(.{ .phase = .press, .button = 1, .x = 1, .y = 1, .clicks = 1 }));
    try std.testing.expect(!journal.pointer_active);
    journal.queue.clear();

    try journal.pushPointer(.{ .phase = .press, .button = 1, .x = 1, .y = 1, .clicks = 1 });
    while (journal.queue.length < queue_capacity) try journal.pushPointer(.{ .phase = .motion, .button = 1, .x = 2, .y = 2 });
    try std.testing.expectError(error.InputQueueFull, journal.pushPointer(.{ .phase = .motion, .button = 1, .x = 3, .y = 3 }));
    try std.testing.expect(journal.pointer_active);
    try std.testing.expectError(error.InputQueueFull, journal.pushPointer(.{ .phase = .release, .button = 1, .x = 4, .y = 4, .clicks = 1 }));
    try std.testing.expect(journal.pointer_active);
}

test "wheel journal accepts bounded ticks and rejects active pointer sessions" {
    var journal: DeliveryJournal = .{};
    try journal.pushWheel(.{ .y = 1 });
    const sent = (try journal.take()).?;
    try std.testing.expectEqual(frontend.WheelInput{ .y = 1 }, sent.event.wheel);
    try std.testing.expect(journal.acknowledge(sent.sequence));

    try journal.pushPointer(.{ .phase = .press, .button = 1, .x = 1, .y = 1, .clicks = 1 });
    try std.testing.expectError(error.PointerSessionActive, journal.pushWheel(.{ .y = -1 }));
    journal.queue.clear();
    journal.pointer_active = false;
    try journal.pushWheel(.{ .y = -1 });
}

test "pointer journal rejects duplicate press and idle drag motion" {
    var journal: DeliveryJournal = .{};
    try journal.pushPointer(.{ .phase = .press, .button = 1, .x = 1, .y = 1, .clicks = 1 });
    try std.testing.expectError(error.PointerSessionActive, journal.pushPointer(.{ .phase = .press, .button = 1, .x = 2, .y = 2, .clicks = 1 }));
    try std.testing.expectError(error.PointerSessionActive, journal.pushPointer(.{ .phase = .motion, .x = 3, .y = 3 }));
    journal.queue.clear();
}

test "queue and journal accept bounded pointer intents" {
    var queue: Queue = .{};
    try queue.pushPointer(.{ .phase = .motion, .x = 12, .y = 4 });
    try queue.pushPointer(.{ .phase = .press, .button = 1, .x = 120, .y = 2, .clicks = 1 });
    try std.testing.expectEqual(frontend.PointerPhase.motion, queue.items[0].pointer.phase);

    var journal: DeliveryJournal = .{};
    try journal.pushPointer(.{ .phase = .press, .button = 1, .x = 120, .y = 2, .clicks = 1 });
    try journal.pushPointer(.{ .phase = .release, .button = 1, .x = 120, .y = 2, .clicks = 1 });
    const press_sent = (try journal.take()).?;
    try std.testing.expectEqual(frontend.PointerPhase.press, press_sent.event.pointer.phase);
    try std.testing.expect(journal.acknowledge(press_sent.sequence));
    const sent = (try journal.take()).?;
    try std.testing.expectEqual(frontend.PointerPhase.release, sent.event.pointer.phase);
    try std.testing.expect(journal.acknowledge(sent.sequence));
}

test "delivery journal retries the same intent and sequence after reconnect" {
    var journal: DeliveryJournal = .{};
    try journal.pushText("X");

    const first = (try journal.take()).?;
    try std.testing.expectEqual(@as(u64, 1), first.sequence);
    try std.testing.expectEqualStrings("X", first.event.text.bytes());
    try std.testing.expectError(error.InputInFlight, journal.take());

    journal.beginRetry();
    const retry = (try journal.take()).?;
    try std.testing.expectEqual(first.sequence, retry.sequence);
    try std.testing.expectEqualStrings("X", retry.event.text.bytes());

    try std.testing.expect(!journal.acknowledge(first.sequence - 1));
    try std.testing.expect(journal.acknowledge(first.sequence));
    try std.testing.expectEqual(@as(?TranslatedEvent, null), journal.pending);
    try std.testing.expectEqual(@as(?DeliveryJournal.Sent, null), try journal.take());

    try journal.pushKey(.{ .action = .cursor_left });
    const second = (try journal.take()).?;
    try std.testing.expectEqual(@as(u64, 2), second.sequence);
}

test "delivery journal bounds retries while preserving the pending intent" {
    var journal: DeliveryJournal = .{ .max_attempts = 2 };
    try journal.pushText("Y");

    try std.testing.expect((try journal.take()) != null);
    journal.beginRetry();
    try std.testing.expect((try journal.take()) != null);
    journal.beginRetry();
    try std.testing.expectError(error.DeliveryRetriesExhausted, journal.take());
    try std.testing.expect(journal.pending != null);
    try std.testing.expect(journal.acknowledge(1));
    try std.testing.expectEqual(@as(?TranslatedEvent, null), journal.pending);
}

test "paste shortcut requires V with only either Ctrl modifier" {
    try std.testing.expect(isPasteShortcut(SDL_SCANCODE_V, true, false, 0x40));
    try std.testing.expect(isPasteShortcut(SDL_SCANCODE_V, true, false, 0x80));
    try std.testing.expect(!isPasteShortcut(SDL_SCANCODE_V, false, false, 0x40));
    try std.testing.expect(!isPasteShortcut(SDL_SCANCODE_V, true, true, 0x40));
    try std.testing.expect(!isPasteShortcut(SDL_SCANCODE_V, true, false, 0));
    try std.testing.expect(!isPasteShortcut(SDL_SCANCODE_C, true, false, 0x40));
    try std.testing.expect(!isPasteShortcut(SDL_SCANCODE_V, true, false, 0xc1));
}

test "apply ACK accepts only the exact bounded sequence payload" {
    try std.testing.expect(validApplyAck("7", 7));
    try std.testing.expect(validApplyAck("7\n", 7));
    try std.testing.expect(validApplyAck(" 7\r\n", 7));
    try std.testing.expect(!validApplyAck("8\n", 7));
    try std.testing.expect(!validApplyAck("", 7));
    try std.testing.expect(!validApplyAck("7x", 7));
    try std.testing.expect(!validApplyAck("7\n7", 7));
}

test "queue copies and bounds UTF-8 text" {
    var queue: Queue = .{};
    try queue.pushText("Emacs");
    try queue.pushText("你好");
    try queue.pushKey(.{ .action = .cursor_left });
    try std.testing.expectEqual(@as(usize, 3), queue.length);
    try std.testing.expectEqualStrings("Emacs", queue.items[0].text.bytes());
    try std.testing.expectEqualStrings("你好", queue.items[1].text.bytes());
    try std.testing.expectEqual(frontend.KeyAction.cursor_left, queue.items[2].key.action);

    try std.testing.expectError(error.InvalidInputText, queue.pushText(""));
    try std.testing.expectError(error.InvalidInputText, queue.pushText("\xff\xfe"));
    const oversized = "a" ** 121;
    try std.testing.expectError(error.InvalidInputText, queue.pushText(oversized[0..]));

    var many: Queue = .{};
    for (0..queue_capacity) |_| try many.pushText("x");
    try std.testing.expectError(error.InputQueueFull, many.pushText("x"));

    const first = many.pop().?;
    try std.testing.expectEqualStrings("x", first.text.bytes());
    try std.testing.expectEqual(queue_capacity - 1, many.length);
    try std.testing.expect(many.pop() != null);
    many.clear();
    try std.testing.expectEqual(@as(?TranslatedEvent, null), many.pop());
}
