//! Standard EUP v1 session-setup payloads and bounded setup state machine.
//!
//! This module is protocol preparation for the pure SDL3 runtime.  It does not
//! replace the authenticated EPXL transport handshake yet and does not enable
//! output_proto.

const std = @import("std");
const protocol = @import("protocol.zig");

pub const protocol_major: u16 = 1;
pub const protocol_minor: u16 = 0;

pub const Role = enum(u8) {
    frontend = 1,
    backend = 2,
};

pub const Profile = enum(u8) {
    local_unix = 1,
};

pub const hello_size: usize = 38;
pub const hello_ack_size: usize = 46;
pub const session_ready_size: usize = 48;
pub const ready_ack_size: usize = 48;
pub const feature_hash_len: usize = 32;

pub const Error = protocol.Error || error{
    InvalidSessionPayload,
    InvalidSessionStage,
    InvalidSessionRole,
    InvalidSessionProfile,
    ProtocolVersionMismatch,
    CapabilityHashMismatch,
    NextSequenceMismatch,
};

pub const Hello = struct {
    protocol_major: u16 = protocol_major,
    protocol_minor: u16 = protocol_minor,
    profile: Profile = .local_unix,
    feature_hash: [feature_hash_len]u8,

    pub fn role(self: Hello) Role {
        _ = self;
        return .frontend;
    }
};

pub const HelloAck = struct {
    protocol_major: u16 = protocol_major,
    protocol_minor: u16 = protocol_minor,
    profile: Profile = .local_unix,
    session_id: u64,
    feature_hash: [feature_hash_len]u8,

    pub fn role(self: HelloAck) Role {
        _ = self;
        return .backend;
    }
};

pub const SessionReady = struct {
    protocol_major: u16 = protocol_major,
    protocol_minor: u16 = protocol_minor,
    profile: Profile = .local_unix,
    feature_hash: [feature_hash_len]u8,
    next_sequence: u64,
};

pub const ReadyAck = struct {
    protocol_major: u16 = protocol_major,
    protocol_minor: u16 = protocol_minor,
    profile: Profile = .local_unix,
    feature_hash: [feature_hash_len]u8,
    next_sequence: u64,
};

pub const Stage = enum {
    idle,
    hello_sent,
    hello_acked,
    ready_sent,
    established,
};

pub const Setup = struct {
    stage: Stage = .idle,
    role: Role = .frontend,
    profile: Profile = .local_unix,
    feature_hash: [feature_hash_len]u8,
    session_id: u64 = 0,
    next_sequence: u64 = 0,
    selected_minor: u16 = 0,

    pub fn start(feature_hash: [feature_hash_len]u8, next_sequence: u64) Setup {
        return .{
            .role = .frontend,
            .feature_hash = feature_hash,
            .next_sequence = next_sequence,
        };
    }

    pub fn makeHello(self: *const Setup) Hello {
        return .{ .protocol_minor = self.selected_minor, .feature_hash = self.feature_hash };
    }

    pub fn helloSent(self: *Setup, hello: *const Hello) Error!void {
        if (self.stage != .idle) return error.InvalidSessionStage;
        if (self.role != .frontend) return error.InvalidSessionRole;
        if (hello.protocol_major != protocol_major or hello.protocol_minor > protocol_minor)
            return error.ProtocolVersionMismatch;
        if (hello.profile != self.profile) return error.InvalidSessionProfile;
        if (!hashEql(hello.feature_hash, self.feature_hash))
            return error.CapabilityHashMismatch;
        self.stage = .hello_sent;
    }

    pub fn helloAcked(self: *Setup, ack: *const HelloAck) Error!void {
        if (self.stage != .hello_sent) return error.InvalidSessionStage;
        if (ack.role() != .backend) return error.InvalidSessionRole;
        if (ack.protocol_major != protocol_major or ack.protocol_minor > protocol_minor)
            return error.ProtocolVersionMismatch;
        if (ack.profile != self.profile) return error.InvalidSessionProfile;
        if (ack.session_id == 0) return error.InvalidSessionPayload;
        if (!hashEql(ack.feature_hash, self.feature_hash))
            return error.CapabilityHashMismatch;
        self.stage = .hello_acked;
        self.session_id = ack.session_id;
        self.selected_minor = ack.protocol_minor;
    }

    pub fn makeSessionReady(self: *const Setup) SessionReady {
        return .{
            .protocol_minor = self.selected_minor,
            .feature_hash = self.feature_hash,
            .next_sequence = self.next_sequence,
        };
    }

    pub fn readySent(self: *Setup, ready: *const SessionReady) Error!void {
        if (self.stage != .hello_acked) return error.InvalidSessionStage;
        if (ready.profile != self.profile) return error.InvalidSessionProfile;
        if (ready.protocol_major != protocol_major or ready.protocol_minor != self.selected_minor)
            return error.ProtocolVersionMismatch;
        if (!hashEql(ready.feature_hash, self.feature_hash))
            return error.CapabilityHashMismatch;
        if (ready.next_sequence != self.next_sequence) return error.NextSequenceMismatch;
        self.stage = .ready_sent;
    }

    pub fn established(self: *Setup, ack: *const ReadyAck) Error!void {
        if (self.stage != .ready_sent) return error.InvalidSessionStage;
        if (ack.profile != self.profile) return error.InvalidSessionProfile;
        if (ack.protocol_major != protocol_major or ack.protocol_minor != self.selected_minor)
            return error.ProtocolVersionMismatch;
        if (!hashEql(ack.feature_hash, self.feature_hash))
            return error.CapabilityHashMismatch;
        if (ack.next_sequence != self.next_sequence) return error.NextSequenceMismatch;
        self.stage = .established;
    }
};

fn hashEql(a: [feature_hash_len]u8, b: [feature_hash_len]u8) bool {
    var difference: u8 = 0;
    for (a, b) |left, right| difference |= left ^ right;
    return difference == 0;
}

fn appendHeader(gpa: std.mem.Allocator, out: *std.ArrayList(u8), major: u16, minor: u16, role: u8, profile: u8) !void {
    try out.appendSlice(gpa, &[2]u8{ @intCast(major & 0xff), @intCast(major >> 8) });
    try out.appendSlice(gpa, &[2]u8{ @intCast(minor & 0xff), @intCast(minor >> 8) });
    try out.append(gpa, role);
    try out.append(gpa, profile);
}

pub fn encodeHello(gpa: std.mem.Allocator, hello: *const Hello, out: *std.ArrayList(u8)) !void {
    if (hello.role() != .frontend or hello.protocol_major != protocol_major or
        hello.protocol_minor > protocol_minor or hello.profile != .local_unix)
        return error.InvalidSessionPayload;
    try out.ensureUnusedCapacity(gpa, hello_size);
    appendHeader(gpa, out, hello.protocol_major, hello.protocol_minor, @intFromEnum(hello.role()), @intFromEnum(hello.profile)) catch @panic("fixed append");
    out.appendSliceAssumeCapacity(&hello.feature_hash);
}

pub fn decodeHello(data: []const u8) Error!Hello {
    if (data.len != hello_size) return error.InvalidSessionPayload;
    const major = std.mem.readInt(u16, data[0..2], .little);
    const minor = std.mem.readInt(u16, data[2..4], .little);
    const role: Role = switch (data[4]) {
        1 => .frontend,
        2 => .backend,
        else => return error.InvalidSessionRole,
    };
    const profile: Profile = switch (data[5]) {
        1 => .local_unix,
        else => return error.InvalidSessionProfile,
    };
    if (role != .frontend or profile != .local_unix or major != protocol_major or minor > protocol_minor)
        return error.InvalidSessionPayload;
    var hash: [feature_hash_len]u8 = undefined;
    @memcpy(&hash, data[6..38]);
    return .{ .protocol_major = major, .protocol_minor = minor, .profile = profile, .feature_hash = hash };
}

pub fn encodeHelloAck(gpa: std.mem.Allocator, ack: *const HelloAck, out: *std.ArrayList(u8)) !void {
    if (ack.role() != .backend or ack.protocol_major != protocol_major or
        ack.protocol_minor > protocol_minor or ack.profile != .local_unix or ack.session_id == 0)
        return error.InvalidSessionPayload;
    try out.ensureUnusedCapacity(gpa, hello_ack_size);
    appendHeader(gpa, out, ack.protocol_major, ack.protocol_minor, @intFromEnum(ack.role()), @intFromEnum(ack.profile)) catch @panic("fixed append");
    var session: [8]u8 = undefined;
    std.mem.writeInt(u64, &session, ack.session_id, .little);
    out.appendSliceAssumeCapacity(&session);
    out.appendSliceAssumeCapacity(&ack.feature_hash);
}

pub fn decodeHelloAck(data: []const u8) Error!HelloAck {
    if (data.len != hello_ack_size) return error.InvalidSessionPayload;
    const major = std.mem.readInt(u16, data[0..2], .little);
    const minor = std.mem.readInt(u16, data[2..4], .little);
    const role: Role = switch (data[4]) {
        1 => .frontend,
        2 => .backend,
        else => return error.InvalidSessionRole,
    };
    const profile: Profile = switch (data[5]) {
        1 => .local_unix,
        else => return error.InvalidSessionProfile,
    };
    const session_id = std.mem.readInt(u64, data[6..14], .little);
    var hash: [feature_hash_len]u8 = undefined;
    @memcpy(&hash, data[14..46]);
    if (role != .backend or profile != .local_unix or major != protocol_major or minor > protocol_minor or session_id == 0)
        return error.InvalidSessionPayload;
    return .{ .protocol_major = major, .protocol_minor = minor, .profile = profile, .session_id = session_id, .feature_hash = hash };
}

pub fn encodeSessionReady(gpa: std.mem.Allocator, ready: *const SessionReady, out: *std.ArrayList(u8)) !void {
    if (ready.protocol_major != protocol_major or ready.protocol_minor > protocol_minor or
        ready.profile != .local_unix or ready.next_sequence == 0)
        return error.InvalidSessionPayload;
    try out.ensureUnusedCapacity(gpa, session_ready_size);
    try out.appendSlice(gpa, &[2]u8{ @intCast(ready.protocol_major & 0xff), @intCast(ready.protocol_major >> 8) });
    try out.appendSlice(gpa, &[2]u8{ @intCast(ready.protocol_minor & 0xff), @intCast(ready.protocol_minor >> 8) });
    try out.appendSlice(gpa, &[4]u8{ @intFromEnum(ready.profile), 0, 0, 0 });
    try out.appendSlice(gpa, &ready.feature_hash);
    var sequence: [8]u8 = undefined;
    std.mem.writeInt(u64, &sequence, ready.next_sequence, .little);
    out.appendSliceAssumeCapacity(&sequence);
}
pub fn decodeSessionReady(data: []const u8) Error!SessionReady {
    if (data.len != session_ready_size) return error.InvalidSessionPayload;
    const major = std.mem.readInt(u16, data[0..2], .little);
    const minor = std.mem.readInt(u16, data[2..4], .little);
    const profile: Profile = switch (data[4]) {
        1 => .local_unix,
        else => return error.InvalidSessionProfile,
    };
    if (data[5] != 0 or data[6] != 0 or data[7] != 0) return error.InvalidSessionPayload;
    var hash: [feature_hash_len]u8 = undefined;
    @memcpy(&hash, data[8..40]);
    const next_sequence = std.mem.readInt(u64, data[40..48], .little);
    if (profile != .local_unix or major != protocol_major or minor > protocol_minor or next_sequence == 0)
        return error.InvalidSessionPayload;
    return .{ .protocol_major = major, .protocol_minor = minor, .profile = profile, .feature_hash = hash, .next_sequence = next_sequence };
}

pub fn encodeReadyAck(gpa: std.mem.Allocator, ack: *const ReadyAck, out: *std.ArrayList(u8)) !void {
    if (ack.protocol_major != protocol_major or ack.protocol_minor > protocol_minor or
        ack.profile != .local_unix or ack.next_sequence == 0)
        return error.InvalidSessionPayload;
    try out.ensureUnusedCapacity(gpa, ready_ack_size);
    try out.appendSlice(gpa, &[2]u8{ @intCast(ack.protocol_major & 0xff), @intCast(ack.protocol_major >> 8) });
    try out.appendSlice(gpa, &[2]u8{ @intCast(ack.protocol_minor & 0xff), @intCast(ack.protocol_minor >> 8) });
    try out.appendSlice(gpa, &[4]u8{ @intFromEnum(ack.profile), 0, 0, 0 });
    try out.appendSlice(gpa, &ack.feature_hash);
    var sequence: [8]u8 = undefined;
    std.mem.writeInt(u64, &sequence, ack.next_sequence, .little);
    out.appendSliceAssumeCapacity(&sequence);
}

pub fn decodeReadyAck(data: []const u8) Error!ReadyAck {
    if (data.len != ready_ack_size) return error.InvalidSessionPayload;
    const major = std.mem.readInt(u16, data[0..2], .little);
    const minor = std.mem.readInt(u16, data[2..4], .little);
    const profile: Profile = switch (data[4]) {
        1 => .local_unix,
        else => return error.InvalidSessionProfile,
    };
    if (data[5] != 0 or data[6] != 0 or data[7] != 0) return error.InvalidSessionPayload;
    var hash: [feature_hash_len]u8 = undefined;
    @memcpy(&hash, data[8..40]);
    const next_sequence = std.mem.readInt(u64, data[40..48], .little);
    if (profile != .local_unix or major != protocol_major or minor > protocol_minor or next_sequence == 0)
        return error.InvalidSessionPayload;
    return .{ .protocol_major = major, .protocol_minor = minor, .profile = profile, .feature_hash = hash, .next_sequence = next_sequence };
}

test "session setup payloads round trip with fixed sizes" {
    const hash = [_]u8{7} ** feature_hash_len;
    const hello: Hello = .{ .feature_hash = hash };
    var hello_bytes: std.ArrayList(u8) = .empty;
    defer hello_bytes.deinit(std.testing.allocator);
    try encodeHello(std.testing.allocator, &hello, &hello_bytes);
    try std.testing.expectEqual(hello_size, hello_bytes.items.len);
    try std.testing.expectEqualDeep(hello, try decodeHello(hello_bytes.items));

    const ack: HelloAck = .{ .session_id = 42, .feature_hash = hash };
    var ack_bytes: std.ArrayList(u8) = .empty;
    defer ack_bytes.deinit(std.testing.allocator);
    try encodeHelloAck(std.testing.allocator, &ack, &ack_bytes);
    try std.testing.expectEqual(hello_ack_size, ack_bytes.items.len);
    try std.testing.expectEqualDeep(ack, try decodeHelloAck(ack_bytes.items));

    const ready: SessionReady = .{ .feature_hash = hash, .next_sequence = 8 };
    var ready_bytes: std.ArrayList(u8) = .empty;
    defer ready_bytes.deinit(std.testing.allocator);
    try encodeSessionReady(std.testing.allocator, &ready, &ready_bytes);
    try std.testing.expectEqual(session_ready_size, ready_bytes.items.len);
    try std.testing.expectEqualDeep(ready, try decodeSessionReady(ready_bytes.items));

    const ready_ack: ReadyAck = .{ .feature_hash = hash, .next_sequence = 8 };
    var ready_ack_bytes: std.ArrayList(u8) = .empty;
    defer ready_ack_bytes.deinit(std.testing.allocator);
    try encodeReadyAck(std.testing.allocator, &ready_ack, &ready_ack_bytes);
    try std.testing.expectEqual(ready_ack_size, ready_ack_bytes.items.len);
    try std.testing.expectEqualDeep(ready_ack, try decodeReadyAck(ready_ack_bytes.items));
}

test "setup state machine reaches established and rejects mismatches" {
    const hash = [_]u8{9} ** feature_hash_len;
    var setup = Setup.start(hash, 5);
    const hello = setup.makeHello();
    try setup.helloSent(&hello);

    const ack: HelloAck = .{ .session_id = 77, .protocol_minor = 0, .feature_hash = hash };
    try setup.helloAcked(&ack);

    const ready = setup.makeSessionReady();
    try setup.readySent(&ready);

    const ready_ack: ReadyAck = .{ .feature_hash = hash, .next_sequence = 5 };
    try setup.established(&ready_ack);
    try std.testing.expectEqual(Stage.established, setup.stage);

    var mismatch = Setup.start(hash, 5);
    mismatch.stage = .ready_sent;
    mismatch.session_id = 77;
    mismatch.selected_minor = 0;
    const bad_ack: ReadyAck = .{ .feature_hash = hash, .next_sequence = 6 };
    try std.testing.expectError(error.NextSequenceMismatch, mismatch.established(&bad_ack));
}
