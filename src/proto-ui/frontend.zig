//! Frontend-owned scene state decoded from EUP.
//!
//! This module is deliberately independent of SDL and GNU Emacs.  SDL reads
//! the scene after the protocol/transport layers validate it; it never invents
//! core display state.

const std = @import("std");
const protocol = @import("protocol.zig");

pub const Error = protocol.Error || error{OutOfMemory};

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

const window_record_size: usize = 40;
const row_record_size: usize = 56;
const cursor_record_size: usize = 56;
const damage_record_size: usize = 16;
const present_record_size: usize = 16;

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

pub const ApplyStats = struct {
    control_messages: u64 = 0,
    frame_updates: u64 = 0,
};

pub const Scene = struct {
    allocator: std.mem.Allocator,
    session_id: ?u64 = null,
    next_sequence: ?u64 = null,
    frame: ?FrameIdentity = null,
    frame_header: ?protocol.FrameUpdateHeader = null,
    windows: std.ArrayList(Window) = .empty,
    rows: std.ArrayList(Row) = .empty,
    cursor: ?Cursor = null,
    damage: std.ArrayList(Rect) = .empty,
    present: ?PresentHint = null,
    stats: ApplyStats = .{},

    pub fn init(allocator: std.mem.Allocator) Scene {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Scene) void {
        self.windows.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.damage.deinit(self.allocator);
        self.windows = .empty;
        self.rows = .empty;
        self.damage = .empty;
        self.session_id = null;
        self.next_sequence = null;
        self.frame = null;
        self.frame_header = null;
        self.cursor = null;
        self.present = null;
        self.stats = .{};
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
            else => self.stats.control_messages += 1,
        }
        self.next_sequence = next_sequence;
        if (previous_session == null) self.session_id = payload.envelope.session_id;
    }

    fn applyFrameCreate(self: *Scene, envelope: protocol.Envelope, bytes: []const u8) Error!void {
        if (bytes.len != 8) return Error.InvalidMessage;
        const frame_id = std.mem.readInt(u32, bytes[0..4], .little);
        const generation = std.mem.readInt(u32, bytes[4..8], .little);
        if (frame_id == 0 or generation == 0 or envelope.frame_id != frame_id) return Error.InvalidMessage;
        if (self.frame) |old| {
            if (old.frame_id != frame_id or old.generation >= generation) return Error.InvalidMessage;
        }
        self.frame = .{ .frame_id = frame_id, .generation = generation };
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

        var windows: std.ArrayList(Window) = .empty;
        defer windows.deinit(self.allocator);
        var rows: std.ArrayList(Row) = .empty;
        defer rows.deinit(self.allocator);
        var damage: std.ArrayList(Rect) = .empty;
        defer damage.deinit(self.allocator);
        var cursor: ?Cursor = null;
        var present: ?PresentHint = null;

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
                protocol.SectionKind.present_hint => {
                    if (section.records.len != present_record_size or present != null) return Error.InvalidTable;
                    present = try decodePresentHint(section.records);
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
        // The update is now known to be complete; commit it atomically.
        const old_windows = self.windows;
        const old_rows = self.rows;
        const old_damage = self.damage;
        self.windows = windows;
        self.rows = rows;
        self.damage = damage;
        windows = old_windows;
        rows = old_rows;
        damage = old_damage;
        self.frame_header = update.header;
        self.cursor = cursor;
        self.present = present;
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
    var payload: [8]u8 = undefined;
    std.mem.writeInt(u32, payload[0..4], payload_frame, .little);
    std.mem.writeInt(u32, payload[4..8], 1, .little);
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
