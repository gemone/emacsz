//! Standard EUP v1 session setup/control payloads and bounded state machines.
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
pub const suspend_size: usize = 4;
pub const resume_size: usize = 4;
pub const resumed_size: usize = 8;
pub const close_size: usize = 4;
pub const ping_size: usize = 8;
pub const pong_size: usize = 8;
pub const version_mismatch_size: usize = 8;
pub const session_error_header_size: usize = 12;
pub const max_session_error_detail: usize = 256;

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

    pub fn start(feature_hash: [feature_hash_len]u8, next_sequence: u64) Error!Setup {
        if (next_sequence == 0) return error.InvalidSessionPayload;
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

fn appendHeader(out: *std.ArrayList(u8), major: u16, minor: u16, role: u8, profile: u8) void {
    out.appendSliceAssumeCapacity(&.{
        @truncate(major), @truncate(major >> 8),
        @truncate(minor), @truncate(minor >> 8),
        role,             profile,
    });
}

pub fn encodeHello(gpa: std.mem.Allocator, hello: *const Hello, out: *std.ArrayList(u8)) !void {
    if (hello.role() != .frontend or hello.protocol_major != protocol_major or
        hello.protocol_minor > protocol_minor or hello.profile != .local_unix)
        return error.InvalidSessionPayload;
    try out.ensureUnusedCapacity(gpa, hello_size);
    appendHeader(out, hello.protocol_major, hello.protocol_minor, @intFromEnum(hello.role()), @intFromEnum(hello.profile));
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
    appendHeader(out, ack.protocol_major, ack.protocol_minor, @intFromEnum(ack.role()), @intFromEnum(ack.profile));
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

pub const SuspendReason = enum(u8) {
    user = 1,
    background = 2,
    resource_pressure = 3,
    transport_pressure = 4,
    host = 5,
};

pub const CloseReason = enum(u8) {
    normal = 1,
    shutdown = 2,
    protocol = 3,
    resource = 4,
    transport = 5,
};

pub const ErrorSeverity = enum(u8) {
    info = 1,
    warning = 2,
    recoverable = 3,
    fatal = 4,
};

pub const SessionSuspend = struct {
    reason: SuspendReason,
};

pub const SessionResume = struct {
    generation: u32,
};

pub const SessionResumed = struct {
    next_sequence: u64,
};

pub const SessionClose = struct {
    reason: CloseReason,
};

pub const Ping = struct {
    timestamp_ns: u64,
};

pub const Pong = struct {
    original_timestamp_ns: u64,
};

pub const SessionError = struct {
    code: u16,
    severity: ErrorSeverity,
    recoverable: bool,
    message_resource_id: u32,
    detail: []const u8,
};

pub const VersionMismatch = struct {
    required_major: u16,
    required_minor: u16,
    observed_major: u16,
    observed_minor: u16,
};

pub const ControlStage = enum {
    active,
    suspended,
    resume_pending,
    resync_requested,
    resync_active,
    closed,
    fatal,
};

pub const ResyncReason = enum(u8) {
    sequence_gap = 1,
    resource_missing = 2,
    state_digest_mismatch = 3,
    publisher_restart = 4,
};

pub const ResyncRequestFlag = struct {
    pub const full_snapshot: u8 = 1;
    pub const resources: u8 = 2;
    pub const valid_mask: u8 = full_snapshot | resources;
};

pub const ResyncResource = struct {
    pub const faces: u64 = 1;
    pub const fonts: u64 = 2;
    pub const strings: u64 = 4;
    pub const images: u64 = 8;
    pub const fringe_bitmaps: u64 = 16;
    pub const valid_mask: u64 = faces | fonts | strings | images | fringe_bitmaps;
};

pub const ResyncRequest = struct {
    schema: u16 = 1,
    reason: ResyncReason,
    flags: u8 = 0,
    first_missing_sequence: u64 = 0,
    last_missing_sequence: u64 = 0,
    requested_resources: u64 = 0,
};

pub const resync_request_size: usize = 40;

pub const ResyncScope = enum(u8) {
    display_only = 1,
    resources_only = 2,
    full = 3,
};

pub const ResyncBegin = struct {
    schema: u16 = 1,
    scope: ResyncScope,
    resync_id: u64,
    first_sequence: u64,
};

pub const resync_begin_size: usize = 32;

pub const ResyncComplete = struct {
    schema: u16 = 1,
    resync_id: u64,
    coherent_next_sequence: u64,
};

pub const resync_complete_size: usize = 32;

pub const Control = struct {
    stage: ControlStage = .active,
    suspend_reason: ?SuspendReason = null,
    requested_resume_generation: u32 = 0,
    resume_next_sequence: u64 = 0,
    outstanding_ping_ns: u64 = 0,
    close_reason: ?CloseReason = null,
    last_error_code: u16 = 0,
    last_error_severity: ErrorSeverity = .info,
    recoverable_error_count: u64 = 0,
    resync_request: ?ResyncRequest = null,
    resync_scope: ?ResyncScope = null,
    resync_id: u64 = 0,
    resync_first_sequence: u64 = 0,

    pub fn apply(self: *Control, message_type: u16, payload: []const u8) Error!void {
        if (self.stage == .fatal or self.stage == .closed) return error.InvalidSessionStage;
        if (self.stage == .resync_requested and message_type != protocol.Message.resync_begin)
            return error.InvalidSessionStage;
        if (self.stage == .resync_active and message_type != protocol.Message.resync_complete)
            return error.InvalidSessionStage;
        switch (message_type) {
            protocol.Message.session_suspend => {
                if (self.stage != .active) return error.InvalidSessionStage;
                const value = try decodeSuspend(payload);
                self.stage = .suspended;
                self.suspend_reason = value.reason;
            },
            protocol.Message.session_resume => {
                if (self.stage != .suspended) return error.InvalidSessionStage;
                const value = try decodeResume(payload);
                self.requested_resume_generation = value.generation;
                self.stage = .resume_pending;
            },
            protocol.Message.session_resumed => {
                if (self.stage != .resume_pending) return error.InvalidSessionStage;
                const value = try decodeResumed(payload);
                self.resume_next_sequence = value.next_sequence;
                self.stage = .active;
                self.suspend_reason = null;
                self.requested_resume_generation = 0;
            },
            protocol.Message.session_close => {
                const value = try decodeClose(payload);
                self.close_reason = value.reason;
                self.stage = .closed;
            },
            protocol.Message.ping => {
                const value = try decodePing(payload);
                if (self.outstanding_ping_ns != 0) return error.InvalidSessionStage;
                self.outstanding_ping_ns = value.timestamp_ns;
            },
            protocol.Message.pong => {
                const value = try decodePong(payload);
                if (self.outstanding_ping_ns == 0 or value.original_timestamp_ns != self.outstanding_ping_ns)
                    return error.InvalidSessionPayload;
                self.outstanding_ping_ns = 0;
            },
            protocol.Message.session_error => {
                const value = try decodeSessionError(payload);
                self.last_error_code = value.code;
                self.last_error_severity = value.severity;
                if (value.severity == .fatal or !value.recoverable) {
                    self.stage = .fatal;
                } else {
                    self.recoverable_error_count += 1;
                }
            },
            protocol.Message.resync_request => {
                if (self.stage != .active) return error.InvalidSessionStage;
                const value = try decodeResyncRequest(payload);
                self.resync_request = value;
                self.resync_scope = null;
                self.resync_id = 0;
                self.stage = .resync_requested;
            },
            protocol.Message.resync_begin => {
                if (self.stage != .resync_requested) return error.InvalidSessionStage;
                const request = self.resync_request orelse return error.InvalidSessionStage;
                const value = try decodeResyncBegin(payload);
                const expected_scope: ResyncScope = if (request.flags & ResyncRequestFlag.full_snapshot != 0)
                    .full
                else if (request.flags & ResyncRequestFlag.resources != 0 and
                    request.requested_resources != 0)
                    .resources_only
                else
                    .display_only;
                if (value.scope != expected_scope) return error.InvalidSessionPayload;
                if (request.first_missing_sequence != 0 and
                    value.first_sequence != request.first_missing_sequence)
                    return error.InvalidSessionPayload;
                self.resync_scope = value.scope;
                self.resync_id = value.resync_id;
                self.resync_first_sequence = value.first_sequence;
                self.stage = .resync_active;
            },
            protocol.Message.resync_complete => {
                if (self.stage != .resync_active) return error.InvalidSessionStage;
                const request = self.resync_request orelse return error.InvalidSessionStage;
                const value = try decodeResyncComplete(payload);
                if (value.resync_id != self.resync_id) return error.InvalidSessionPayload;
                if (request.first_missing_sequence != 0) {
                    const expected_next = std.math.add(u64, request.last_missing_sequence, 1) catch
                        return error.InvalidSessionPayload;
                    if (value.coherent_next_sequence != expected_next)
                        return error.InvalidSessionPayload;
                } else if (value.coherent_next_sequence <= self.resync_first_sequence) {
                    return error.InvalidSessionPayload;
                }
                self.stage = .active;
                self.resync_request = null;
                self.resync_scope = null;
                self.resync_id = 0;
                self.resync_first_sequence = 0;
            },
            protocol.Message.version_mismatch => {
                _ = try decodeVersionMismatch(payload);
                self.stage = .fatal;
            },
            else => return error.InvalidSessionPayload,
        }
    }
};

pub fn encodeSuspend(gpa: std.mem.Allocator, value: SessionSuspend, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(gpa, &.{ @intFromEnum(value.reason), 0, 0, 0 });
}

pub fn decodeSuspend(data: []const u8) Error!SessionSuspend {
    if (data.len != suspend_size or data[1] != 0 or data[2] != 0 or data[3] != 0)
        return error.InvalidSessionPayload;
    const value: SessionSuspend = .{ .reason = switch (data[0]) {
        1 => .user,
        2 => .background,
        3 => .resource_pressure,
        4 => .transport_pressure,
        5 => .host,
        else => return error.InvalidSessionPayload,
    } };
    return value;
}

pub fn encodeResume(gpa: std.mem.Allocator, value: SessionResume, out: *std.ArrayList(u8)) !void {
    if (value.generation == 0) return error.InvalidSessionPayload;
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value.generation, .little);
    try out.appendSlice(gpa, &bytes);
}

pub fn decodeResume(data: []const u8) Error!SessionResume {
    if (data.len != resume_size) return error.InvalidSessionPayload;
    const value: SessionResume = .{ .generation = std.mem.readInt(u32, data[0..4], .little) };
    if (value.generation == 0) return error.InvalidSessionPayload;
    return value;
}

pub fn encodeResumed(gpa: std.mem.Allocator, value: SessionResumed, out: *std.ArrayList(u8)) !void {
    if (value.next_sequence == 0) return error.InvalidSessionPayload;
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value.next_sequence, .little);
    try out.appendSlice(gpa, &bytes);
}

pub fn decodeResumed(data: []const u8) Error!SessionResumed {
    if (data.len != resumed_size) return error.InvalidSessionPayload;
    const value: SessionResumed = .{ .next_sequence = std.mem.readInt(u64, data[0..8], .little) };
    if (value.next_sequence == 0) return error.InvalidSessionPayload;
    return value;
}

pub fn encodeClose(gpa: std.mem.Allocator, value: SessionClose, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(gpa, &.{ @intFromEnum(value.reason), 0, 0, 0 });
}

pub fn decodeClose(data: []const u8) Error!SessionClose {
    if (data.len != close_size or data[1] != 0 or data[2] != 0 or data[3] != 0)
        return error.InvalidSessionPayload;
    return .{ .reason = switch (data[0]) {
        1 => .normal,
        2 => .shutdown,
        3 => .protocol,
        4 => .resource,
        5 => .transport,
        else => return error.InvalidSessionPayload,
    } };
}

pub fn encodePing(gpa: std.mem.Allocator, value: Ping, out: *std.ArrayList(u8)) !void {
    if (value.timestamp_ns == 0) return error.InvalidSessionPayload;
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value.timestamp_ns, .little);
    try out.appendSlice(gpa, &bytes);
}

pub fn decodePing(data: []const u8) Error!Ping {
    if (data.len != ping_size) return error.InvalidSessionPayload;
    const value: Ping = .{ .timestamp_ns = std.mem.readInt(u64, data[0..8], .little) };
    if (value.timestamp_ns == 0) return error.InvalidSessionPayload;
    return value;
}

pub fn encodePong(gpa: std.mem.Allocator, value: Pong, out: *std.ArrayList(u8)) !void {
    if (value.original_timestamp_ns == 0) return error.InvalidSessionPayload;
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value.original_timestamp_ns, .little);
    try out.appendSlice(gpa, &bytes);
}

pub fn decodePong(data: []const u8) Error!Pong {
    if (data.len != pong_size) return error.InvalidSessionPayload;
    const value: Pong = .{ .original_timestamp_ns = std.mem.readInt(u64, data[0..8], .little) };
    if (value.original_timestamp_ns == 0) return error.InvalidSessionPayload;
    return value;
}

fn validateSessionError(value: SessionError) Error!void {
    if (value.code == 0 or value.message_resource_id == 0 or
        value.detail.len > max_session_error_detail) return error.InvalidSessionPayload;
    if (value.detail.len != 0 and !std.unicode.utf8ValidateSlice(value.detail))
        return error.InvalidSessionPayload;
}

pub fn encodeSessionError(gpa: std.mem.Allocator, value: SessionError, out: *std.ArrayList(u8)) !void {
    try validateSessionError(value);
    try out.ensureUnusedCapacity(gpa, session_error_header_size + value.detail.len);
    var code: [2]u8 = undefined;
    std.mem.writeInt(u16, &code, value.code, .little);
    try out.appendSlice(gpa, &.{ code[0], code[1], @intFromEnum(value.severity), @intFromBool(value.recoverable) });
    var word: [4]u8 = undefined;
    std.mem.writeInt(u32, &word, value.message_resource_id, .little);
    try out.appendSlice(gpa, &word);
    var half: [2]u8 = undefined;
    std.mem.writeInt(u16, &half, @intCast(value.detail.len), .little);
    try out.appendSlice(gpa, &half);
    try out.appendSlice(gpa, &.{ 0, 0 });
    try out.appendSlice(gpa, value.detail);
}

pub fn decodeSessionError(data: []const u8) Error!SessionError {
    if (data.len < session_error_header_size) return error.InvalidSessionPayload;
    const detail_length = std.mem.readInt(u16, data[8..10], .little);
    if (data[10] != 0 or data[11] != 0 or data.len != session_error_header_size + @as(usize, detail_length))
        return error.InvalidSessionPayload;
    const value: SessionError = .{
        .code = std.mem.readInt(u16, data[0..2], .little),
        .severity = switch (data[2]) {
            1 => .info,
            2 => .warning,
            3 => .recoverable,
            4 => .fatal,
            else => return error.InvalidSessionPayload,
        },
        .recoverable = switch (data[3]) {
            0 => false,
            1 => true,
            else => return error.InvalidSessionPayload,
        },
        .message_resource_id = std.mem.readInt(u32, data[4..8], .little),
        .detail = data[session_error_header_size..],
    };
    try validateSessionError(value);
    return value;
}

pub fn encodeVersionMismatch(gpa: std.mem.Allocator, value: VersionMismatch, out: *std.ArrayList(u8)) !void {
    var bytes: [version_mismatch_size]u8 = undefined;
    std.mem.writeInt(u16, bytes[0..2], value.required_major, .little);
    std.mem.writeInt(u16, bytes[2..4], value.required_minor, .little);
    std.mem.writeInt(u16, bytes[4..6], value.observed_major, .little);
    std.mem.writeInt(u16, bytes[6..8], value.observed_minor, .little);
    try out.appendSlice(gpa, &bytes);
}

pub fn decodeVersionMismatch(data: []const u8) Error!VersionMismatch {
    if (data.len != version_mismatch_size) return error.InvalidSessionPayload;
    return .{
        .required_major = std.mem.readInt(u16, data[0..2], .little),
        .required_minor = std.mem.readInt(u16, data[2..4], .little),
        .observed_major = std.mem.readInt(u16, data[4..6], .little),
        .observed_minor = std.mem.readInt(u16, data[6..8], .little),
    };
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
    var setup = try Setup.start(hash, 5);
    const hello = setup.makeHello();
    try setup.helloSent(&hello);

    const ack: HelloAck = .{ .session_id = 77, .protocol_minor = 0, .feature_hash = hash };
    try setup.helloAcked(&ack);

    const ready = setup.makeSessionReady();
    try setup.readySent(&ready);

    const ready_ack: ReadyAck = .{ .feature_hash = hash, .next_sequence = 5 };
    try setup.established(&ready_ack);
    try std.testing.expectEqual(Stage.established, setup.stage);

    var mismatch = try Setup.start(hash, 5);
    mismatch.stage = .ready_sent;
    mismatch.session_id = 77;
    mismatch.selected_minor = 0;
    const bad_ack: ReadyAck = .{ .feature_hash = hash, .next_sequence = 6 };
    try std.testing.expectError(error.NextSequenceMismatch, mismatch.established(&bad_ack));
    try std.testing.expectError(error.InvalidSessionPayload, Setup.start(hash, 0));
}

test "session control payloads round trip with strict fixed forms" {
    const a = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);

    try encodeSuspend(a, .{ .reason = .transport_pressure }, &bytes);
    try std.testing.expectEqual(suspend_size, bytes.items.len);
    try std.testing.expectEqual(SuspendReason.transport_pressure, (try decodeSuspend(bytes.items)).reason);
    bytes.clearRetainingCapacity();

    try encodeResume(a, .{ .generation = 44 }, &bytes);
    try std.testing.expectEqual(resume_size, bytes.items.len);
    try std.testing.expectEqual(@as(u32, 44), (try decodeResume(bytes.items)).generation);
    bytes.clearRetainingCapacity();

    try encodeResumed(a, .{ .next_sequence = 99 }, &bytes);
    try std.testing.expectEqual(resumed_size, bytes.items.len);
    try std.testing.expectEqual(@as(u64, 99), (try decodeResumed(bytes.items)).next_sequence);
    bytes.clearRetainingCapacity();

    try encodeClose(a, .{ .reason = .resource }, &bytes);
    try std.testing.expectEqual(close_size, bytes.items.len);
    try std.testing.expectEqual(CloseReason.resource, (try decodeClose(bytes.items)).reason);
    bytes.clearRetainingCapacity();

    try encodePing(a, .{ .timestamp_ns = 77 }, &bytes);
    try std.testing.expectEqual(ping_size, bytes.items.len);
    try std.testing.expectEqual(@as(u64, 77), (try decodePing(bytes.items)).timestamp_ns);
    bytes.clearRetainingCapacity();

    try encodePong(a, .{ .original_timestamp_ns = 77 }, &bytes);
    try std.testing.expectEqual(pong_size, bytes.items.len);
    try std.testing.expectEqual(@as(u64, 77), (try decodePong(bytes.items)).original_timestamp_ns);
    bytes.clearRetainingCapacity();

    try encodeSessionError(a, .{
        .code = 501,
        .severity = .recoverable,
        .recoverable = true,
        .message_resource_id = 12,
        .detail = "retry",
    }, &bytes);
    try std.testing.expectEqual(session_error_header_size + 5, bytes.items.len);
    const error_value = try decodeSessionError(bytes.items);
    try std.testing.expectEqual(@as(u16, 501), error_value.code);
    try std.testing.expectEqualStrings("retry", error_value.detail);
    bytes.clearRetainingCapacity();

    try encodeVersionMismatch(a, .{
        .required_major = 1,
        .required_minor = 2,
        .observed_major = 2,
        .observed_minor = 0,
    }, &bytes);
    try std.testing.expectEqual(version_mismatch_size, bytes.items.len);
    const version_value = try decodeVersionMismatch(bytes.items);
    try std.testing.expectEqual(@as(u16, 2), version_value.observed_major);
}

test "session control state machine enforces ordered lifecycle" {
    var control: Control = .{};
    try control.apply(protocol.Message.session_suspend, &.{ 4, 0, 0, 0 });
    try std.testing.expectEqual(ControlStage.suspended, control.stage);
    try std.testing.expectError(error.InvalidSessionStage, control.apply(protocol.Message.session_suspend, &.{ 1, 0, 0, 0 }));

    try control.apply(protocol.Message.session_resume, &.{ 8, 0, 0, 0 });
    try std.testing.expectEqual(ControlStage.resume_pending, control.stage);
    try control.apply(protocol.Message.session_resumed, &.{ 9, 0, 0, 0, 0, 0, 0, 0 });
    try std.testing.expectEqual(ControlStage.active, control.stage);

    try control.apply(protocol.Message.ping, &.{ 21, 0, 0, 0, 0, 0, 0, 0 });
    try std.testing.expectError(error.InvalidSessionStage, control.apply(protocol.Message.ping, &.{ 22, 0, 0, 0, 0, 0, 0, 0 }));
    try control.apply(protocol.Message.pong, &.{ 21, 0, 0, 0, 0, 0, 0, 0 });
    try std.testing.expectEqual(@as(u64, 0), control.outstanding_ping_ns);

    try control.apply(protocol.Message.session_error, &.{
        101, 0, 3, 1, 12, 0, 0, 0, 5, 0, 0, 0, 'r', 'e', 't', 'r', 'y',
    });
    try std.testing.expectEqual(ControlStage.active, control.stage);
    try std.testing.expectEqual(@as(u16, 101), control.last_error_code);
    try std.testing.expectEqual(ErrorSeverity.recoverable, control.last_error_severity);
    try std.testing.expectEqual(@as(u64, 1), control.recoverable_error_count);

    try control.apply(protocol.Message.session_close, &.{ 1, 0, 0, 0 });
    try std.testing.expectEqual(ControlStage.closed, control.stage);
    try std.testing.expectError(error.InvalidSessionStage, control.apply(protocol.Message.ping, &.{ 22, 0, 0, 0, 0, 0, 0, 0 }));
}

test "session control validates reserved bytes and bounded UTF-8 detail" {
    try std.testing.expectError(error.InvalidSessionPayload, decodeSuspend(&.{ 1, 1, 0, 0 }));
    try std.testing.expectError(error.InvalidSessionPayload, decodeClose(&.{ 1, 0, 0, 1 }));

    const long_detail = [_]u8{'x'} ** (max_session_error_detail + 1);
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidSessionPayload, encodeSessionError(std.testing.allocator, .{
        .code = 1,
        .severity = .recoverable,
        .recoverable = true,
        .message_resource_id = 1,
        .detail = &long_detail,
    }, &bytes));

    const header = [_]u8{ 1, 0, 1, 1 } ++ std.mem.toBytes(@as(u32, 1)) ++ std.mem.toBytes(@as(u16, max_session_error_detail + 1)) ++ [2]u8{ 0, 0 };
    try std.testing.expectError(error.InvalidSessionPayload, decodeSessionError(&header ++ long_detail));
}

pub fn encodeResyncRequest(gpa: std.mem.Allocator, value: ResyncRequest, out: *std.ArrayList(u8)) !void {
    try validateResyncRequest(value);
    var bytes: [resync_request_size]u8 = @splat(0);
    std.mem.writeInt(u16, bytes[0..2], value.schema, .little);
    bytes[2] = @intFromEnum(value.reason);
    bytes[3] = value.flags;
    std.mem.writeInt(u64, bytes[8..16], value.first_missing_sequence, .little);
    std.mem.writeInt(u64, bytes[16..24], value.last_missing_sequence, .little);
    std.mem.writeInt(u64, bytes[24..32], value.requested_resources, .little);
    try out.appendSlice(gpa, &bytes);
}

pub fn decodeResyncRequest(data: []const u8) Error!ResyncRequest {
    if (data.len != resync_request_size) return error.InvalidSessionPayload;
    if (!std.mem.allEqual(u8, data[4..8], 0) or !std.mem.allEqual(u8, data[32..40], 0))
        return error.InvalidSessionPayload;
    const value: ResyncRequest = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .reason = switch (data[2]) {
            1 => .sequence_gap,
            2 => .resource_missing,
            3 => .state_digest_mismatch,
            4 => .publisher_restart,
            else => return error.InvalidSessionPayload,
        },
        .flags = data[3],
        .first_missing_sequence = std.mem.readInt(u64, data[8..16], .little),
        .last_missing_sequence = std.mem.readInt(u64, data[16..24], .little),
        .requested_resources = std.mem.readInt(u64, data[24..32], .little),
    };
    try validateResyncRequest(value);
    return value;
}

fn validateResyncRequest(value: ResyncRequest) Error!void {
    if (value.schema != 1 or value.flags & ~ResyncRequestFlag.valid_mask != 0 or
        value.requested_resources & ~ResyncResource.valid_mask != 0) return error.InvalidSessionPayload;
    if (value.requested_resources != 0 and value.flags & ResyncRequestFlag.resources == 0)
        return error.InvalidSessionPayload;
    if (value.reason == .resource_missing and
        (value.flags & ResyncRequestFlag.resources == 0 or value.requested_resources == 0))
        return error.InvalidSessionPayload;
    if (value.reason == .publisher_restart and value.flags & ResyncRequestFlag.full_snapshot == 0)
        return error.InvalidSessionPayload;
    const has_range = value.first_missing_sequence != 0 or value.last_missing_sequence != 0;
    if (has_range and (value.first_missing_sequence == 0 or
        value.first_missing_sequence > value.last_missing_sequence or
        value.last_missing_sequence == std.math.maxInt(u64)))
        return error.InvalidSessionPayload;
    if (value.reason == .sequence_gap and !has_range) return error.InvalidSessionPayload;
}

pub fn encodeResyncBegin(gpa: std.mem.Allocator, value: ResyncBegin, out: *std.ArrayList(u8)) !void {
    try validateResyncBegin(value);
    var bytes: [resync_begin_size]u8 = @splat(0);
    std.mem.writeInt(u16, bytes[0..2], value.schema, .little);
    bytes[2] = @intFromEnum(value.scope);
    std.mem.writeInt(u64, bytes[8..16], value.resync_id, .little);
    std.mem.writeInt(u64, bytes[16..24], value.first_sequence, .little);
    try out.appendSlice(gpa, &bytes);
}

pub fn decodeResyncBegin(data: []const u8) Error!ResyncBegin {
    if (data.len != resync_begin_size) return error.InvalidSessionPayload;
    if (!std.mem.allEqual(u8, data[3..8], 0) or !std.mem.allEqual(u8, data[24..32], 0))
        return error.InvalidSessionPayload;
    const value: ResyncBegin = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .scope = switch (data[2]) {
            1 => .display_only,
            2 => .resources_only,
            3 => .full,
            else => return error.InvalidSessionPayload,
        },
        .resync_id = std.mem.readInt(u64, data[8..16], .little),
        .first_sequence = std.mem.readInt(u64, data[16..24], .little),
    };
    try validateResyncBegin(value);
    return value;
}

fn validateResyncBegin(value: ResyncBegin) Error!void {
    if (value.schema != 1 or value.resync_id == 0 or value.first_sequence == 0)
        return error.InvalidSessionPayload;
}

pub fn encodeResyncComplete(gpa: std.mem.Allocator, value: ResyncComplete, out: *std.ArrayList(u8)) !void {
    try validateResyncComplete(value);
    var bytes: [resync_complete_size]u8 = @splat(0);
    std.mem.writeInt(u16, bytes[0..2], value.schema, .little);
    std.mem.writeInt(u64, bytes[8..16], value.resync_id, .little);
    std.mem.writeInt(u64, bytes[16..24], value.coherent_next_sequence, .little);
    try out.appendSlice(gpa, &bytes);
}

pub fn decodeResyncComplete(data: []const u8) Error!ResyncComplete {
    if (data.len != resync_complete_size) return error.InvalidSessionPayload;
    if (!std.mem.allEqual(u8, data[2..8], 0) or !std.mem.allEqual(u8, data[24..32], 0))
        return error.InvalidSessionPayload;
    const value: ResyncComplete = .{
        .schema = std.mem.readInt(u16, data[0..2], .little),
        .resync_id = std.mem.readInt(u64, data[8..16], .little),
        .coherent_next_sequence = std.mem.readInt(u64, data[16..24], .little),
    };
    try validateResyncComplete(value);
    return value;
}

fn validateResyncComplete(value: ResyncComplete) Error!void {
    if (value.schema != 1 or value.resync_id == 0 or value.coherent_next_sequence == 0)
        return error.InvalidSessionPayload;
}

test "resync request and begin codecs round trip and reject malformed state" {
    const request: ResyncRequest = .{
        .reason = .sequence_gap,
        .first_missing_sequence = 8,
        .last_missing_sequence = 10,
    };
    var bytes: [resync_request_size]u8 = encodeResyncRequestBytes(request);
    try std.testing.expectEqualDeep(request, try decodeResyncRequest(&bytes));
    bytes[24] = 1;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncRequest(&bytes));

    var begin_bytes: [resync_begin_size]u8 = @splat(0);
    std.mem.writeInt(u16, begin_bytes[0..2], 1, .little);
    begin_bytes[2] = @intFromEnum(ResyncScope.full);
    std.mem.writeInt(u64, begin_bytes[8..16], 9, .little);
    std.mem.writeInt(u64, begin_bytes[16..24], 11, .little);
    const begin = try decodeResyncBegin(&begin_bytes);
    try std.testing.expectEqual(ResyncScope.full, begin.scope);
    begin_bytes[3] = 1;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncBegin(&begin_bytes));
}

fn encodeResyncRequestBytes(value: ResyncRequest) [resync_request_size]u8 {
    var bytes: [resync_request_size]u8 = @splat(0);
    std.mem.writeInt(u16, bytes[0..2], value.schema, .little);
    bytes[2] = @intFromEnum(value.reason);
    bytes[3] = value.flags;
    std.mem.writeInt(u64, bytes[8..16], value.first_missing_sequence, .little);
    std.mem.writeInt(u64, bytes[16..24], value.last_missing_sequence, .little);
    std.mem.writeInt(u64, bytes[24..32], value.requested_resources, .little);
    return bytes;
}

test "resync control state machine enforces scope id and coherent sequence" {
    var control: Control = .{};
    const request: ResyncRequest = .{ .reason = .sequence_gap, .first_missing_sequence = 8, .last_missing_sequence = 8 };
    try control.apply(protocol.Message.resync_request, &encodeResyncRequestBytes(request));
    try std.testing.expectEqual(ControlStage.resync_requested, control.stage);

    var begin: [resync_begin_size]u8 = @splat(0);
    std.mem.writeInt(u16, begin[0..2], 1, .little);
    begin[2] = @intFromEnum(ResyncScope.display_only);
    std.mem.writeInt(u64, begin[8..16], 77, .little);
    std.mem.writeInt(u64, begin[16..24], 8, .little);
    try control.apply(protocol.Message.resync_begin, &begin);
    try std.testing.expectEqual(ControlStage.resync_active, control.stage);

    var complete: [resync_complete_size]u8 = @splat(0);
    std.mem.writeInt(u16, complete[0..2], 1, .little);
    std.mem.writeInt(u64, complete[8..16], 77, .little);
    std.mem.writeInt(u64, complete[16..24], 9, .little);
    try control.apply(protocol.Message.resync_complete, &complete);
    try std.testing.expectEqual(ControlStage.active, control.stage);
    try std.testing.expectEqual(@as(?ResyncRequest, null), control.resync_request);
}

test "resync codecs reject reserved schemas enums ranges and sequence boundaries" {
    const request: ResyncRequest = .{ .reason = .sequence_gap, .first_missing_sequence = 3, .last_missing_sequence = 3 };
    var bytes: [resync_request_size]u8 = encodeResyncRequestBytes(request);

    bytes[0] = 2;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncRequest(&bytes));
    bytes[0] = 1;
    bytes[2] = 5;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncRequest(&bytes));
    bytes[2] = 1;
    bytes[3] = 8;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncRequest(&bytes));
    bytes[3] = 2;
    bytes[24] = 0x80;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncRequest(&bytes));
    bytes[24] = 0;
    bytes[4] = 4;
    bytes[12] = 3;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncRequest(&bytes));
    bytes[4] = 3;
    std.mem.writeInt(u64, bytes[16..24], std.math.maxInt(u64), .little);
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncRequest(&bytes));
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncRequest(bytes[0 .. bytes.len - 1]));
    var trailing_bytes: [resync_request_size + 1]u8 = undefined;
    @memcpy(trailing_bytes[0..resync_request_size], &bytes);
    trailing_bytes[resync_request_size] = 0;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncRequest(&trailing_bytes));

    const begin_valid: ResyncBegin = .{ .scope = .resources_only, .resync_id = 7, .first_sequence = 4 };
    var begin: [resync_begin_size]u8 = @splat(0);
    std.mem.writeInt(u16, begin[0..2], begin_valid.schema, .little);
    begin[2] = @intFromEnum(begin_valid.scope);
    std.mem.writeInt(u64, begin[8..16], begin_valid.resync_id, .little);
    std.mem.writeInt(u64, begin[16..24], begin_valid.first_sequence, .little);
    try std.testing.expectEqualDeep(begin_valid, try decodeResyncBegin(&begin));
    begin[0] = 3;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncBegin(&begin));
    begin[0] = 1;
    begin[2] = 7;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncBegin(&begin));
    begin[2] = 2;
    std.mem.writeInt(u64, begin[8..16], 0, .little);
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncBegin(&begin));
    std.mem.writeInt(u64, begin[8..16], 7, .little);
    std.mem.writeInt(u64, begin[16..24], 0, .little);
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncBegin(&begin));
    begin[16] = 0;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncBegin(&begin));
    begin[16] = 4;
    begin[3] = 1;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncBegin(&begin));
    begin[3] = 0;
    begin[25] = 1;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncBegin(&begin));
    begin[25] = 0;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncBegin(begin[0 .. begin.len - 1]));

    const complete_valid: ResyncComplete = .{ .resync_id = 7, .coherent_next_sequence = 4 };
    var complete: [resync_complete_size]u8 = @splat(0);
    std.mem.writeInt(u16, complete[0..2], complete_valid.schema, .little);
    std.mem.writeInt(u64, complete[8..16], complete_valid.resync_id, .little);
    std.mem.writeInt(u64, complete[16..24], complete_valid.coherent_next_sequence, .little);
    try std.testing.expectEqualDeep(complete_valid, try decodeResyncComplete(&complete));
    complete[0] = 4;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncComplete(&complete));
    complete[0] = 1;
    complete[2] = 1;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncComplete(&complete));
    complete[2] = 0;
    std.mem.writeInt(u64, complete[8..16], 0, .little);
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncComplete(&complete));
    std.mem.writeInt(u64, complete[8..16], 7, .little);
    std.mem.writeInt(u64, complete[16..24], 0, .little);
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncComplete(&complete));
    complete[16] = 5;
    try std.testing.expectEqual(@as(u64, 5), (try decodeResyncComplete(&complete)).coherent_next_sequence);
    complete[16] = 4;
    complete[3] = 1;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncComplete(&complete));
    complete[3] = 0;
    complete[25] = 1;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncComplete(&complete));
    complete[25] = 0;
    try std.testing.expectError(error.InvalidSessionPayload, decodeResyncComplete(complete[0 .. complete.len - 1]));
}

test "resync control scope mapping transitions and invalid states are atomic" {
    const cases = [_]struct { request: ResyncRequest, scope: ResyncScope }{
        .{ .request = .{ .reason = .sequence_gap, .first_missing_sequence = 4, .last_missing_sequence = 4 }, .scope = .display_only },
        .{ .request = .{ .reason = .resource_missing, .flags = ResyncRequestFlag.resources, .requested_resources = ResyncResource.faces }, .scope = .resources_only },
        .{ .request = .{ .reason = .publisher_restart, .flags = ResyncRequestFlag.full_snapshot | ResyncRequestFlag.resources, .requested_resources = ResyncResource.faces }, .scope = .full },
    };
    for (cases) |case| {
        var control: Control = .{};
        try control.apply(protocol.Message.resync_request, &encodeResyncRequestBytes(case.request));
        try std.testing.expectEqual(ControlStage.resync_requested, control.stage);
        try std.testing.expectError(Error.InvalidSessionStage, control.apply(protocol.Message.resync_request, &encodeResyncRequestBytes(case.request)));

        var begin: [resync_begin_size]u8 = @splat(0);
        std.mem.writeInt(u16, begin[0..2], 1, .little);
        begin[2] = @intFromEnum(case.scope);
        std.mem.writeInt(u64, begin[8..16], 9, .little);
        const first_sequence: u64 = if (case.request.first_missing_sequence == 0) 1 else case.request.first_missing_sequence;
        std.mem.writeInt(u64, begin[16..24], first_sequence, .little);
        try control.apply(protocol.Message.resync_begin, &begin);
        try std.testing.expectEqual(ControlStage.resync_active, control.stage);

        var bad_control: Control = .{};
        try bad_control.apply(protocol.Message.resync_request, &encodeResyncRequestBytes(case.request));
        var bad_begin = begin;
        bad_begin[2] = @intFromEnum(if (case.scope == .display_only) ResyncScope.full else ResyncScope.display_only);
        try std.testing.expectError(Error.InvalidSessionPayload, bad_control.apply(protocol.Message.resync_begin, &bad_begin));
        try std.testing.expectEqual(ControlStage.resync_requested, bad_control.stage);

        var complete: [resync_complete_size]u8 = @splat(0);
        std.mem.writeInt(u16, complete[0..2], 1, .little);
        std.mem.writeInt(u64, complete[8..16], 9, .little);
        if (case.request.first_missing_sequence != 0) {
            std.mem.writeInt(u64, complete[16..24], case.request.last_missing_sequence + 1, .little);
        } else {
            std.mem.writeInt(u64, complete[16..24], first_sequence + 1, .little);
        }
        try control.apply(protocol.Message.resync_complete, &complete);
        try std.testing.expectEqual(ControlStage.active, control.stage);
        try std.testing.expectEqual(@as(?ResyncRequest, null), control.resync_request);
    }

    var control: Control = .{};
    const request: ResyncRequest = .{ .reason = .sequence_gap, .first_missing_sequence = 4, .last_missing_sequence = 4 };
    try control.apply(protocol.Message.resync_request, &encodeResyncRequestBytes(request));
    var begin: [resync_begin_size]u8 = @splat(0);
    std.mem.writeInt(u16, begin[0..2], 1, .little);
    begin[2] = @intFromEnum(ResyncScope.display_only);
    std.mem.writeInt(u64, begin[8..16], 1, .little);
    std.mem.writeInt(u64, begin[16..24], 4, .little);
    try control.apply(protocol.Message.resync_begin, &begin);
    const saved_control = control;
    var complete: [resync_complete_size]u8 = @splat(0);
    std.mem.writeInt(u16, complete[0..2], 1, .little);
    std.mem.writeInt(u64, complete[8..16], 9, .little);
    std.mem.writeInt(u64, complete[16..24], 4, .little);
    try std.testing.expectError(Error.InvalidSessionPayload, control.apply(protocol.Message.resync_complete, &complete));
    try std.testing.expectEqual(saved_control.stage, control.stage);
    try std.testing.expectEqual(saved_control.resync_id, control.resync_id);
}
