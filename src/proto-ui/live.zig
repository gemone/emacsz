//! Versioned local live-transport handshake and stream framing.
//!
//! The handshake is intentionally small and audit-friendly.  Authentication is
//! a 256-bit token; the token is exchanged only over a local endpoint whose
//! creation and permissions are owned by the adapter/publisher process.

const std = @import("std");
const protocol = @import("protocol.zig");

pub const magic = [4]u8{ 'E', 'P', 'X', 'L' };
pub const version: u16 = 1;
pub const token_len: usize = 32;
pub const Token = [token_len]u8;
pub const handshake_size: usize = magic.len + 2 + 2 + token_len;
pub const max_frame_len: usize = 16 * 1024 * 1024;

pub const Error = protocol.Error || error{
    InvalidToken,
    TruncatedFrame,
    HandshakeVersion,
    HandshakeToken,
};

pub const Handshake = struct {
    kind: Kind,
    version: u16 = version,
    token: Token = [_]u8{0} ** token_len,

    pub const Kind = enum(u16) {
        client_hello = 1,
        server_ready = 2,
    };
};

pub fn encodeHandshake(handshake: Handshake, out: *[handshake_size]u8) void {
    @memcpy(out[0..magic.len], &magic);
    std.mem.writeInt(u16, out[4..6], handshake.version, .little);
    std.mem.writeInt(u16, out[6..8], @intFromEnum(handshake.kind), .little);
    @memcpy(out[8..][0..token_len], &handshake.token);
}

pub fn decodeHandshake(bytes: *const [handshake_size]u8) Error!Handshake {
    if (!std.mem.eql(u8, bytes[0..magic.len], &magic)) return Error.InvalidEnvelope;
    const version_value = std.mem.readInt(u16, bytes[4..6], .little);
    if (version_value != version) return Error.HandshakeVersion;
    const kind_value = std.mem.readInt(u16, bytes[6..8], .little);
    const kind: Handshake.Kind = if (kind_value == 1) .client_hello else if (kind_value == 2) .server_ready else return Error.InvalidEnvelope;
    var token: Token = undefined;
    @memcpy(&token, bytes[8..][0..token_len]);
    if (kind == .server_ready and tokenEql(&token, &([_]u8{0} ** token_len)) == false)
        return Error.InvalidEnvelope;
    return .{ .kind = kind, .version = version_value, .token = token };
}

/// Compares in constant time for the selected token length.
pub fn tokenEql(a: []const u8, b: []const u8) bool {
    if (a.len != token_len or b.len != token_len) return false;
    var difference: u8 = 0;
    for (a, b) |x, y| difference |= x ^ y;
    return difference == 0;
}

pub fn encodeFrameHeader(length: usize, out: *[4]u8) Error!void {
    if (length == 0 or length > max_frame_len) return Error.Unsupported;
    std.mem.writeInt(u32, out, @intCast(length), .little);
}

pub fn encodeFrame(a: std.mem.Allocator, message: []const u8, out: *std.ArrayList(u8)) !void {
    var header: [4]u8 = undefined;
    try encodeFrameHeader(message.len, &header);
    try out.ensureUnusedCapacity(a, message.len + 4);
    try out.appendSlice(a, &header);
    try out.appendSlice(a, message);
}

pub fn decodeFrameLength(header: *const [4]u8) Error!usize {
    const length = std.mem.readInt(u32, header, .little);
    if (length == 0 or length > max_frame_len) return Error.InvalidEnvelope;
    return length;
}

pub fn parseToken(text: []const u8) Error![token_len]u8 {
    if (text.len != token_len) return Error.InvalidToken;
    var token: Token = undefined;
    @memcpy(&token, text);
    return token;
}

pub fn writeFrame(writer: anytype, message: []const u8) !void {
    var header: [4]u8 = undefined;
    try encodeFrameHeader(message.len, &header);
    try writer.writeAll(&header);
    try writer.writeAll(message);
}

pub fn readFrame(reader: anytype, allocator: std.mem.Allocator) !?[]u8 {
    var header: [4]u8 = undefined;
    header[0] = reader.takeByte() catch |err| switch (err) {
        error.EndOfStream => return null,
        else => return err,
    };
    reader.readSliceAll(header[1..]) catch return Error.TruncatedFrame;
    const length = try decodeFrameLength(&header);
    const message = try allocator.alloc(u8, length);
    errdefer allocator.free(message);
    reader.readSliceAll(message) catch return Error.TruncatedFrame;
    return message;
}

test "handshake round trip and token comparison" {
    var token: Token = undefined;
    for (&token, 0..) |*byte, i| byte.* = @truncate(i + 1);
    var bytes: [handshake_size]u8 = undefined;
    encodeHandshake(.{ .kind = .client_hello, .token = token }, &bytes);
    const decoded = try decodeHandshake(&bytes);
    try std.testing.expectEqual(Handshake.Kind.client_hello, decoded.kind);
    try std.testing.expect(tokenEql(&token, &decoded.token));
    token[0] ^= 1;
    try std.testing.expect(!tokenEql(&token, &decoded.token));

    bytes[4] = 2;
    try std.testing.expectError(Error.HandshakeVersion, decodeHandshake(&bytes));
}

test "frame codec enforces nonempty bounded frames" {
    const a = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(a);
    try encodeFrame(a, "EUP", &out);
    try std.testing.expectEqualSlices(u8, &.{ 3, 0, 0, 0, 'E', 'U', 'P' }, out.items);
    try std.testing.expectEqual(@as(usize, 3), try decodeFrameLength(out.items[0..4]));

    var bad: [4]u8 = undefined;
    std.mem.writeInt(u32, &bad, 0, .little);
    try std.testing.expectError(Error.InvalidEnvelope, decodeFrameLength(&bad));
}

test "handshake rejects invalid kind and nonzero server token" {
    var bytes: [handshake_size]u8 = undefined;
    encodeHandshake(.{ .kind = .client_hello }, &bytes);
    std.mem.writeInt(u16, bytes[6..8], 7, .little);
    try std.testing.expectError(Error.InvalidEnvelope, decodeHandshake(&bytes));

    var token: Token = [_]u8{1} ** token_len;
    encodeHandshake(.{ .kind = .server_ready, .token = token }, &bytes);
    try std.testing.expectError(Error.InvalidEnvelope, decodeHandshake(&bytes));

    token = [_]u8{0} ** token_len;
    encodeHandshake(.{ .kind = .server_ready, .token = token }, &bytes);
    try std.testing.expect((try decodeHandshake(&bytes)).kind == .server_ready);
}

test "stream frame reader separates clean eof from truncation" {
    const a = std.testing.allocator;
    var clean: [0]u8 = .{};
    var reader = std.Io.Reader.fixed(&clean);
    try std.testing.expect((try readFrame(&reader, a)) == null);

    var truncated_header = [_]u8{1};
    reader = std.Io.Reader.fixed(&truncated_header);
    try std.testing.expectError(Error.TruncatedFrame, readFrame(&reader, a));

    var truncated_body = [_]u8{ 2, 0, 0, 0, 'A' };
    reader = std.Io.Reader.fixed(&truncated_body);
    try std.testing.expectError(Error.TruncatedFrame, readFrame(&reader, a));

    var maximum: [4]u8 = undefined;
    std.mem.writeInt(u32, &maximum, max_frame_len, .little);
    try std.testing.expectEqual(max_frame_len, try decodeFrameLength(&maximum));
    std.mem.writeInt(u32, &maximum, max_frame_len + 1, .little);
    try std.testing.expectError(Error.InvalidEnvelope, decodeFrameLength(&maximum));
}
