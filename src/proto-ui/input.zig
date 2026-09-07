//! Bounded SDL-to-EUP input translation for the facts profile.

const std = @import("std");
const frontend = @import("frontend.zig");

pub const SDL_EVENT_KEY_DOWN: c_uint = 0x300;
pub const SDL_EVENT_KEY_UP: c_uint = 0x301;
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

pub const max_logical_key_bytes: usize = 64;

pub const KeyState = enum(u8) {
    down = 1,
    up = 2,
    repeat = 3,
};

pub const key_modifier_shift: u32 = 1 << 0;
pub const key_modifier_control: u32 = 1 << 1;
pub const key_modifier_meta: u32 = 1 << 2;
pub const key_modifier_alt: u32 = 1 << 3;
pub const key_modifier_super: u32 = 1 << 4;
pub const key_modifier_hyper: u32 = 1 << 5;
pub const key_modifier_function: u32 = 1 << 6;
pub const key_modifier_caps_lock: u32 = 1 << 7;
pub const key_modifier_num_lock: u32 = 1 << 8;
pub const key_modifier_scroll_lock: u32 = 1 << 9;
pub const key_modifier_mask: u32 = (1 << 10) - 1;

/// Fixed storage keeps reverse-input queue ownership explicit and bounded.
pub const FullKeyEvent = struct {
    state: KeyState,
    modifiers: u32,
    physical_key: u32,
    repeat_count: u32 = 0,
    device_id: u32 = 0,
    layout_id: u32 = 0,
    logical_key_buffer: [max_logical_key_bytes]u8 = undefined,
    logical_key_length: usize = 0,
    text_buffer: [max_text_bytes]u8 = undefined,
    text_length: usize = 0,

    pub fn logicalKey(self: *const FullKeyEvent) []const u8 {
        return self.logical_key_buffer[0..self.logical_key_length];
    }

    pub fn text(self: *const FullKeyEvent) []const u8 {
        return self.text_buffer[0..self.text_length];
    }
};

pub const key_v2_schema: u16 = 2;
pub const key_v2_fixed_tail: usize = 27;

fn validKeyV2String(bytes: []const u8, max_bytes: usize) bool {
    if (bytes.len > max_bytes) return false;
    for (bytes) |byte| {
        if (byte == 0) return false;
    }
    return std.unicode.utf8ValidateSlice(bytes);
}

pub fn validFullKeyEvent(event: FullKeyEvent) bool {
    if (event.device_id != 0 or event.layout_id != 0) return false;
    if (event.modifiers & ~key_modifier_mask != 0) return false;
    if (event.physical_key == 0) return false;
    if (!validKeyV2String(event.logicalKey(), max_logical_key_bytes) or
        !validKeyV2String(event.text(), max_text_bytes)) return false;
    return switch (event.state) {
        .down, .up => event.repeat_count == 0,
        .repeat => event.repeat_count >= 1,
    };
}

pub fn encodeFullKeyEvent(a: std.mem.Allocator, event: FullKeyEvent, out: *std.ArrayList(u8)) !void {
    if (!validFullKeyEvent(event)) return error.InvalidFullKeyEvent;
    const logical = event.logicalKey();
    const text = event.text();
    const total = key_v2_fixed_tail + logical.len + text.len;
    try out.ensureUnusedCapacity(a, total);
    out.appendAssumeCapacity(0);
    out.appendAssumeCapacity(0);
    out.appendAssumeCapacity(key_v2_schema);
    out.appendAssumeCapacity(0);
    out.appendAssumeCapacity(@intFromEnum(event.state));
    inline for (.{ event.modifiers, event.physical_key, event.repeat_count, event.device_id, event.layout_id }) |value| {
        out.items.len += 4;
        std.mem.writeInt(u32, out.items[out.items.len - 4 ..][0..4], value, .little);
    }
    out.appendAssumeCapacity(@intCast(logical.len));
    out.appendAssumeCapacity(@intCast(text.len));
    out.appendSliceAssumeCapacity(logical);
    out.appendSliceAssumeCapacity(text);
}

pub fn decodeFullKeyEvent(bytes: []const u8) !FullKeyEvent {
    if (bytes.len < key_v2_fixed_tail or
        std.mem.readInt(u16, bytes[0..2], .little) != 0 or
        std.mem.readInt(u16, bytes[2..4], .little) != key_v2_schema)
        return error.InvalidFullKeyEvent;
    const state: KeyState = switch (bytes[4]) {
        1 => .down,
        2 => .up,
        3 => .repeat,
        else => return error.InvalidFullKeyEvent,
    };
    var event: FullKeyEvent = .{ .state = state, .modifiers = 0, .physical_key = 0 };
    var offset: usize = 5;
    inline for (.{ "modifiers", "physical_key", "repeat_count", "device_id", "layout_id" }) |field| {
        if (bytes.len < offset + 4) return error.InvalidFullKeyEvent;
        @field(event, field) = std.mem.readInt(u32, bytes[offset..][0..4], .little);
        offset += 4;
    }
    const logical_length: usize = bytes[offset];
    const text_length: usize = bytes[offset + 1];
    offset += 2;
    if (bytes.len != offset + logical_length + text_length or
        logical_length > max_logical_key_bytes or text_length > max_text_bytes)
        return error.InvalidFullKeyEvent;
    event.logical_key_length = logical_length;
    event.text_length = text_length;
    @memcpy(event.logical_key_buffer[0..logical_length], bytes[offset..][0..logical_length]);
    @memcpy(event.text_buffer[0..text_length], bytes[offset + logical_length ..][0..text_length]);
    if (!validFullKeyEvent(event)) return error.InvalidFullKeyEvent;
    return event;
}

pub const sdl_kmod_lshift: u16 = 0x0001;
pub const sdl_kmod_rshift: u16 = 0x0002;
pub const sdl_kmod_lctrl: u16 = 0x0040;
pub const sdl_kmod_rctrl: u16 = 0x0080;
pub const sdl_kmod_lalt: u16 = 0x0100;
pub const sdl_kmod_ralt: u16 = 0x0200;
pub const sdl_kmod_lgui: u16 = 0x0400;
pub const sdl_kmod_rgui: u16 = 0x0800;
pub const sdl_kmod_mode: u16 = 0x1000;
pub const sdl_kmod_caps: u16 = 0x2000;
pub const sdl_kmod_num: u16 = 0x4000;
pub const sdl_kmod_scroll: u16 = 0x8000;

pub fn sdlModifiersToEup(modifiers: u16) u32 {
    var result: u32 = 0;
    if (modifiers & (sdl_kmod_lshift | sdl_kmod_rshift) != 0) result |= key_modifier_shift;
    if (modifiers & (sdl_kmod_lctrl | sdl_kmod_rctrl) != 0) result |= key_modifier_control;
    if (modifiers & sdl_kmod_mode != 0) result |= key_modifier_meta;
    if (modifiers & (sdl_kmod_lalt | sdl_kmod_ralt) != 0) result |= key_modifier_alt;
    if (modifiers & (sdl_kmod_lgui | sdl_kmod_rgui) != 0) result |= key_modifier_super;
    if (modifiers & sdl_kmod_caps != 0) result |= key_modifier_caps_lock;
    if (modifiers & sdl_kmod_num != 0) result |= key_modifier_num_lock;
    if (modifiers & sdl_kmod_scroll != 0) result |= key_modifier_scroll_lock;
    return result;
}

pub fn sdlState(down: bool, repeat: bool) KeyState {
    return if (repeat) .repeat else if (down) .down else .up;
}

pub fn sdlLogicalKey(name: ?[*:0]const u8) struct { buffer: [max_logical_key_bytes]u8, length: usize } {
    var result: [max_logical_key_bytes]u8 = undefined;
    const source: []const u8 = if (name) |value| std.mem.span(value) else "";
    const length = @min(source.len, max_logical_key_bytes);
    @memcpy(result[0..length], source[0..length]);
    return .{ .buffer = result, .length = length };
}

pub fn translateFullKey(
    scancode: i32,
    logical_name: ?[*:0]const u8,
    down: bool,
    repeat: bool,
    modifiers: u16,
    device_id: u32,
) ?FullKeyEvent {
    if (scancode <= 0 or scancode > std.math.maxInt(u32)) return null;
    const logical = sdlLogicalKey(logical_name);
    return .{
        .state = sdlState(down, repeat),
        .modifiers = sdlModifiersToEup(modifiers),
        .physical_key = @intCast(scancode),
        .repeat_count = if (repeat) 1 else 0,
        .device_id = device_id,
        .logical_key_buffer = logical.buffer,
        .logical_key_length = logical.length,
    };
}

pub fn duplicatesTextInput(event: FullKeyEvent) bool {
    return event.state == .down and event.modifiers == 0 and
        event.logicalKey().len == 1 and
        event.logicalKey()[0] >= 0x20 and event.logicalKey()[0] <= 0x7e;
}

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
    key_v2: FullKeyEvent,
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

    pub fn pushKeyV2(self: *Queue, event: FullKeyEvent) !void {
        if (!validFullKeyEvent(event)) return error.InvalidFullKeyEvent;
        if (self.length == queue_capacity) return error.InputQueueFull;
        self.items[self.length] = .{ .key_v2 = event };
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
    key_v2_negotiated: bool = false,

    pub const Sent = struct {
        sequence: u64,
        event: TranslatedEvent,
    };

    pub fn pushKey(self: *DeliveryJournal, event: frontend.KeyEvent) !void {
        if (self.pointer_active) return error.PointerSessionActive;
        try self.queue.pushKey(event);
    }

    pub fn pushKeyV2(self: *DeliveryJournal, event: FullKeyEvent) !void {
        if (!self.key_v2_negotiated) return error.FullKeyCapabilityNotNegotiated;
        if (self.pointer_active) return error.PointerSessionActive;
        try self.queue.pushKeyV2(event);
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
    return validTextInput(text);
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

pub const clipboard_artifact_prefix = "base64:";
pub const max_clipboard_artifact_bytes =
    clipboard_artifact_prefix.len + std.base64.standard.Encoder.calcSize(max_clipboard_bytes);

pub const ClipboardCodecError = error{
    InvalidClipboardArtifact,
    OutOfMemory,
};

/// A conservative, text-only clipboard artifact. Base64 preserves exact
/// UTF-8 bytes without turning this bridge into a MIME/rich-text transport.
pub fn encodeClipboardArtifact(a: std.mem.Allocator, text: []const u8, out: *std.ArrayList(u8)) !void {
    if (!validClipboardText(text)) return error.InvalidClipboardArtifact;
    const encoded_size = std.base64.standard.Encoder.calcSize(text.len);
    try out.ensureUnusedCapacity(a, clipboard_artifact_prefix.len + encoded_size);
    out.appendSliceAssumeCapacity(clipboard_artifact_prefix);
    const encoded_start = out.items.len;
    out.appendNTimesAssumeCapacity(0, encoded_size);
    const encoded = out.items[encoded_start..][0..encoded_size];
    _ = std.base64.standard.Encoder.encode(encoded, text);
}

pub fn decodeClipboardArtifact(a: std.mem.Allocator, artifact: []const u8) ![]u8 {
    if (!std.mem.startsWith(u8, artifact, clipboard_artifact_prefix))
        return error.InvalidClipboardArtifact;
    const encoded = artifact[clipboard_artifact_prefix.len..];
    const decoded_size = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch
        return error.InvalidClipboardArtifact;
    if (decoded_size == 0 or decoded_size > max_clipboard_bytes)
        return error.InvalidClipboardArtifact;
    const decoded = try a.alloc(u8, decoded_size);
    errdefer a.free(decoded);
    std.base64.standard.Decoder.decode(decoded, encoded) catch
        return error.InvalidClipboardArtifact;
    if (!validClipboardText(decoded)) return error.InvalidClipboardArtifact;
    return decoded;
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
    try std.testing.expect(validClipboardText("你好"));
    try std.testing.expect(validClipboardText("e\u{0301}"));
    try std.testing.expect(!validClipboardText(""));
    try std.testing.expect(!validClipboardText("\x00"));
    try std.testing.expect(!validClipboardText("a" ** 121));
    try std.testing.expect(!validClipboardText("bad\npayload"));
    try std.testing.expect(!validClipboardText("\tbad"));
    try std.testing.expect(!validClipboardText("\xff\xfe"));
}

test "clipboard artifacts round trip exact Unicode and reject hostile bytes" {
    const a = std.testing.allocator;
    var artifact: std.ArrayList(u8) = .empty;
    defer artifact.deinit(a);
    try encodeClipboardArtifact(a, "Emacs 你好", &artifact);
    const decoded = try decodeClipboardArtifact(a, artifact.items);
    defer a.free(decoded);
    try std.testing.expectEqualStrings("Emacs 你好", decoded);

    try std.testing.expectError(error.InvalidClipboardArtifact, decodeClipboardArtifact(a, "Emacs 你好"));
    try std.testing.expectError(error.InvalidClipboardArtifact, decodeClipboardArtifact(a, "base64:!"));
    try std.testing.expectError(error.InvalidClipboardArtifact, decodeClipboardArtifact(a, "base64:"));
    artifact.clearRetainingCapacity();
    try std.testing.expectError(error.InvalidClipboardArtifact, encodeClipboardArtifact(a, "bad\npayload", &artifact));
}

test "clipboard Unicode delivery is capability gated without queue side effects" {
    var journal: DeliveryJournal = .{};
    try journal.pushTextAllowed("ASCII", .ascii);
    try std.testing.expectError(error.TextCapabilityNotNegotiated, journal.pushTextAllowed("你好", .ascii));
    try std.testing.expectEqual(@as(usize, 1), journal.queue.length);
    try std.testing.expectEqualStrings("ASCII", journal.queue.items[0].text.bytes());
    try journal.pushTextAllowed("你好", .unicode);
    try std.testing.expectEqual(@as(usize, 2), journal.queue.length);
    try std.testing.expectEqualStrings("你好", journal.queue.items[1].text.bytes());
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

test "full key v2 round trips strict variable-length payloads" {
    const a = std.testing.allocator;
    var event: FullKeyEvent = .{
        .state = .repeat,
        .modifiers = key_modifier_control | key_modifier_hyper | key_modifier_num_lock,
        .physical_key = 8,
        .repeat_count = 3,
        .device_id = 0,
        .layout_id = 0,
    };
    const logical = "é【key】";
    const text = "こんにちは";
    @memcpy(event.logical_key_buffer[0..logical.len], logical);
    event.logical_key_length = logical.len;
    @memcpy(event.text_buffer[0..text.len], text);
    event.text_length = text.len;

    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    try encodeFullKeyEvent(a, event, &bytes);
    const decoded = try decodeFullKeyEvent(bytes.items);
    try std.testing.expectEqual(event.state, decoded.state);
    try std.testing.expectEqual(event.modifiers, decoded.modifiers);
    try std.testing.expectEqual(event.physical_key, decoded.physical_key);
    try std.testing.expectEqual(event.repeat_count, decoded.repeat_count);
    try std.testing.expectEqualStrings(event.logicalKey(), decoded.logicalKey());
    try std.testing.expectEqualStrings(event.text(), decoded.text());
    try std.testing.expectError(error.InvalidFullKeyEvent, decodeFullKeyEvent(bytes.items[0 .. bytes.items.len - 1]));
    try bytes.append(a, 0);
    try std.testing.expectError(error.InvalidFullKeyEvent, decodeFullKeyEvent(bytes.items));

    var invalid = event;
    invalid.state = .down;
    invalid.repeat_count = 3;
    try std.testing.expect(!validFullKeyEvent(invalid));
    invalid.state = .repeat;
    invalid.modifiers = key_modifier_mask + 1;
    try std.testing.expect(!validFullKeyEvent(invalid));
    invalid.modifiers = 0;
    invalid.physical_key = 0;
    try std.testing.expect(!validFullKeyEvent(invalid));

    var nul = event;
    nul.state = .down;
    nul.repeat_count = 0;
    nul.text_buffer[0] = 0;
    nul.text_length = 1;
    try std.testing.expect(!validFullKeyEvent(nul));
}

test "old key receiver and encoder reject the v2 discriminator" {
    const wire = [_]u8{
        0, 0, 2, 0, @intFromEnum(KeyState.down),
        0, 0, 0, 0, 4,
        0, 0, 0, 0, 0,
        0, 0, 0, 0, 0,
        0, 0, 0, 0, 0,
        0, 0,
    };
    try std.testing.expectError(error.InvalidTable, frontend.decodeKeyEvent(&wire));
}

test "SDL full-key translation folds modifiers and preserves states" {
    const down = translateFullKey(8, "e", true, false, sdl_kmod_rctrl | sdl_kmod_lshift | sdl_kmod_caps, 7).?;
    try std.testing.expectEqual(KeyState.down, down.state);
    try std.testing.expectEqual(key_modifier_control | key_modifier_shift | key_modifier_caps_lock, down.modifiers);
    try std.testing.expectEqual(@as(u32, 8), down.physical_key);
    try std.testing.expectEqual(@as(u32, 7), down.device_id);
    try std.testing.expectEqualStrings("e", down.logicalKey());

    const up = translateFullKey(8, "e", false, false, sdl_kmod_lctrl, 0).?;
    try std.testing.expectEqual(KeyState.up, up.state);
    try std.testing.expectEqual(@as(u32, 0), up.repeat_count);

    const repeat = translateFullKey(11, "b", true, true, sdl_kmod_mode | sdl_kmod_ralt | sdl_kmod_num, 0).?;
    try std.testing.expectEqual(KeyState.repeat, repeat.state);
    try std.testing.expectEqual(key_modifier_meta | key_modifier_alt | key_modifier_num_lock, repeat.modifiers);
    try std.testing.expectEqual(@as(u32, 1), repeat.repeat_count);
    try std.testing.expect(translateFullKey(0, "bad", true, false, 0, 0) == null);
    try std.testing.expect(duplicatesTextInput(translateFullKey(8, "x", true, false, 0, 0).?));
}

test "full key v2 delivery is capability gated and ordered" {
    var journal: DeliveryJournal = .{};
    const event = translateFullKey(8, "e", true, false, sdl_kmod_lctrl, 0).?;
    try std.testing.expectError(error.FullKeyCapabilityNotNegotiated, journal.pushKeyV2(event));
    journal.key_v2_negotiated = true;
    try journal.pushKeyV2(event);
    try journal.pushKey(.{ .action = .cursor_right });
    const first = (try journal.take()).?;
    try std.testing.expectEqual(@as(u64, 1), first.sequence);
    try std.testing.expectEqual(KeyState.down, first.event.key_v2.state);
    try std.testing.expectEqualStrings("e", first.event.key_v2.logicalKey());
    try std.testing.expectError(error.InputInFlight, journal.take());
    try std.testing.expect(journal.acknowledge(1));
    const second = (try journal.take()).?;
    try std.testing.expectEqual(@as(u64, 2), second.sequence);
    try std.testing.expectEqual(frontend.KeyAction.cursor_right, second.event.key.action);
}
