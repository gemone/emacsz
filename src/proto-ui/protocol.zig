const std = @import("std");

pub const major_version: u16 = 1;
pub const minor_version: u16 = 0;
pub const header_size: u16 = 62;

pub const Error = error{
    InvalidEnvelope,
    InvalidVersion,
    InvalidMessage,
    InvalidResource,
    InvalidTable,
    InvalidSequence,
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
    pub const frame_update: u16 = 0x0203;
    pub const frame_presented: u16 = 0x0204;
    pub const resource_request: u16 = 0x0510;
    pub const key_event: u16 = 0x0600;
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

pub const Capability = struct {
    /// `name` and `value` borrow bytes from the encoded input.  The caller
    /// must keep that input alive for the lifetime of the decoded table.
    name: []const u8,
    value: []const u8,
};

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
