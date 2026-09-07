//! Adapter-owned deterministic differential gate for replay and live recovery.
//!
//! The gate compares independent recovery routes through the public Scene model.
//! It is intentionally in-process: no socket opens, no Emacs runtime starts, and
//! output_proto remains unavailable.  Ownership follows the existing adapter
//! boundary: Emacs/producer state is authoritative, this module only observes
//! already-encoded EUP and frontend-owned recovery state.

const std = @import("std");
const frontend = @import("frontend.zig");
const facts = @import("facts.zig");
const input = @import("input.zig");
const live = @import("live.zig");
const protocol = @import("protocol.zig");
const transport = @import("transport.zig");

pub const Error = frontend.Error || facts.Error || error{
    ControlSequenceMismatch,
    DigestMismatch,
    IdempotenceMismatch,
    RecoveryTokenMismatch,
    ReplayPathMissing,
};

pub const Digest = [std.crypto.hash.sha2.Sha256.digest_length]u8;
pub const session_token = blk: {
    @setEvalBranchQuota(10_000);
    var digest: Digest = undefined;
    std.crypto.hash.sha2.Sha256.hash("proto-ui-recovery-differential-gate/v1", &digest, .{});
    break :blk digest;
};

pub const PathName = enum {
    direct_ordered,
    authenticated_resync,
    ack_loss_retry,
    erp1_replay,

    pub fn name(self: PathName) []const u8 {
        return @tagName(self);
    }
};

pub const PathResult = struct {
    path: PathName,
    digest: Digest,
    accepted_count: u64 = 0,
};

pub const Summary = struct {
    paths: [@typeInfo(PathName).@"enum".fields.len]PathResult,
    digest: Digest,
    accepted_count: u64,
    result: []const u8 = "pass",

    pub fn eql(left: Summary, right: Summary) bool {
        return std.mem.eql(u8, &left.digest, &right.digest) and
            left.accepted_count == right.accepted_count and
            std.meta.eql(left.paths, right.paths);
    }
};

const Messages = struct {
    items: std.ArrayList([]const u8) = .empty,

    fn deinit(self: *Messages, gpa: std.mem.Allocator) void {
        for (self.items.items) |message| gpa.free(message);
        self.items.deinit(gpa);
        self.* = .{};
    }
};

const Snapshot = struct {
    text: []const []const u8,
    cursor_line: i32,
    cursor_column: i32,
    viewport_start: i32,
    viewport_count: i32,
};

const base_snapshot = Snapshot{
    .text = &.{"alpha"},
    .cursor_line = 1,
    .cursor_column = 1,
    .viewport_start = 1,
    .viewport_count = 2,
};

const final_snapshot = Snapshot{
    .text = &.{ "alpha", "beta" },
    .cursor_line = 2,
    .cursor_column = 5,
    .viewport_start = 1,
    .viewport_count = 3,
};

fn frameFacts() facts.FrameFacts {
    return .{
        .frame_width = 120,
        .frame_height = 90,
        .window_width = 110,
        .window_height = 75,
    };
}

fn appendSnapshot(
    gpa: std.mem.Allocator,
    snapshot: Snapshot,
    scene: *frontend.Scene,
    messages: *Messages,
) !void {
    try facts.appendWireSnapshot(
        gpa,
        frameFacts(),
        snapshot.text,
        .{ .line = snapshot.cursor_line, .column = snapshot.cursor_column },
        .{ .start_line = snapshot.viewport_start, .line_count = snapshot.viewport_count },
        scene,
        &messages.items,
    );
}

fn createMessage(gpa: std.mem.Allocator) ![]const u8 {
    var payload: [8]u8 = undefined;
    std.mem.writeInt(u32, payload[0..4], 1, .little);
    std.mem.writeInt(u32, payload[4..8], 1, .little);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_create,
        .sequence = 1,
        .ack_sequence = 0,
        .session_id = 0x1001,
        .frame_id = 1,
        .timestamp_ns = 1,
    }, &payload, &message);
    return message.toOwnedSlice(gpa);
}

/// One FRAME_CREATE plus one final FRAME_UPDATE keeps the differential input
/// minimal and avoids depending on replacement-update allocation behavior.
fn buildMessages(gpa: std.mem.Allocator) !Messages {
    var messages: Messages = .{};
    errdefer messages.deinit(gpa);
    try messages.items.append(gpa, try createMessage(gpa));

    var generator = frontend.Scene.init(gpa);
    defer generator.deinit();
    try generator.apply(messages.items.items[0]);
    try appendSnapshot(gpa, final_snapshot, &generator, &messages);
    return messages;
}

fn putScalar(hasher: *std.crypto.hash.sha2.Sha256, value: anytype) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .@"enum" => hasher.update(&.{@intFromEnum(value)}),
        .bool => hasher.update(&.{@intFromBool(value)}),
        .int => {
            comptime std.debug.assert(@typeInfo(T).int.bits % 8 == 0);
            var bytes: [@typeInfo(T).int.bits / 8]u8 = undefined;
            std.mem.writeInt(T, &bytes, value, .little);
            hasher.update(&bytes);
        },
        else => @compileError("unsupported fingerprint scalar"),
    }
}
fn putText(hasher: *std.crypto.hash.sha2.Sha256, text: []const u8) void {
    putScalar(hasher, @as(u64, text.len));
    hasher.update(text);
}

fn putOptional(hasher: *std.crypto.hash.sha2.Sha256, present: bool) void {
    putScalar(hasher, present);
}

fn hashFrame(hasher: *std.crypto.hash.sha2.Sha256, frame: ?frontend.FrameIdentity) void {
    putOptional(hasher, frame != null);
    if (frame) |value| {
        putScalar(hasher, value.frame_id);
        putScalar(hasher, value.generation);
    }
}

fn hashRect(hasher: *std.crypto.hash.sha2.Sha256, rect: frontend.Rect) void {
    putScalar(hasher, rect.x);
    putScalar(hasher, rect.y);
    putScalar(hasher, rect.width);
    putScalar(hasher, rect.height);
}

/// Canonicalizes equal state by stable section order and row/text identity.
/// Sequence, timestamps, and ACK bookkeeping are deliberately excluded; those
/// are delivery metadata, not final display truth.
pub fn fingerprint(gpa: std.mem.Allocator, scene: *const frontend.Scene) !Digest {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("PROTO-UI-RECOVERY-V1" ++ [1]u8{0});

    hashFrame(&hasher, scene.frame);
    putScalar(&hasher, @as(u64, scene.frames.len));
    for (scene.frames.frames[0..scene.frames.len]) |frame| {
        putScalar(&hasher, frame.id);
        putScalar(&hasher, frame.generation);
        putScalar(&hasher, frame.status);
        putScalar(&hasher, frame.visibility);
        putScalar(&hasher, frame.focused);
    }

    putScalar(&hasher, @as(u64, scene.windows.items.len));
    for (scene.windows.items) |window| {
        putScalar(&hasher, window.id);
        putScalar(&hasher, window.frame_id);
        putScalar(&hasher, window.x);
        putScalar(&hasher, window.y);
        putScalar(&hasher, window.width);
        putScalar(&hasher, window.height);
    }

    putScalar(&hasher, @as(u64, scene.rows.items.len));
    for (scene.rows.items) |row| {
        putScalar(&hasher, row.window_id);
        putScalar(&hasher, row.index);
        putScalar(&hasher, row.flags);
        putScalar(&hasher, row.x);
        putScalar(&hasher, row.y);
        putScalar(&hasher, row.width);
        putScalar(&hasher, row.height);
        putScalar(&hasher, row.ascent);
        putScalar(&hasher, row.descent);
        putScalar(&hasher, row.baseline);
        putScalar(&hasher, row.visible_height);
    }

    // Text is sorted by row index so equal state has one digest regardless of
    // extension-section ordering.  This small bounded copy also proves that the
    // digest never aliases owned text storage.
    const text_index = try gpa.alloc(u32, scene.text.items.len);
    defer gpa.free(text_index);
    for (scene.text.items, 0..) |line, index| text_index[index] = line.row_index;
    std.mem.sort(u32, text_index, {}, comptime std.sort.asc(u32));
    putScalar(&hasher, @as(u64, text_index.len));
    for (text_index) |row_index| {
        const line = for (scene.text.items) |line| {
            if (line.row_index == row_index) break line;
        } else unreachable;
        putScalar(&hasher, line.row_index);
        putText(&hasher, line.bytes);
    }

    putOptional(&hasher, scene.cursor != null);
    if (scene.cursor) |cursor| {
        putScalar(&hasher, cursor.window_id);
        putScalar(&hasher, cursor.x);
        putScalar(&hasher, cursor.y);
        putScalar(&hasher, cursor.width);
        putScalar(&hasher, cursor.height);
        putScalar(&hasher, cursor.kind);
        putScalar(&hasher, cursor.visible);
        putScalar(&hasher, cursor.active);
    }

    putScalar(&hasher, @as(u64, scene.damage.items.len));
    for (scene.damage.items) |rect| hashRect(&hasher, rect);

    putOptional(&hasher, scene.present != null);
    if (scene.present) |present| {
        putScalar(&hasher, present.mode);
        putScalar(&hasher, present.flags);
        putScalar(&hasher, present.deadline_ns);
    }

    putOptional(&hasher, scene.viewport != null);
    if (scene.viewport) |viewport| {
        putScalar(&hasher, viewport.start_line);
        putScalar(&hasher, viewport.line_count);
    }

    putScalar(&hasher, @as(u64, scene.resources.len));
    for (scene.resources.resources[0..scene.resources.len]) |resource| {
        putScalar(&hasher, resource.kind);
        putScalar(&hasher, resource.id);
        putScalar(&hasher, resource.generation);
        putScalar(&hasher, resource.status);
    }

    var digest: Digest = undefined;
    hasher.final(&digest);
    return digest;
}

fn applyAll(scene: *frontend.Scene, messages: []const []const u8) !u64 {
    var accepted: u64 = 0;
    for (messages) |message| {
        try scene.apply(message);
        accepted += 1;
    }
    return accepted;
}

fn expectControl(control_bytes: *const [live.control_size]u8, kind: live.Control.Kind, sequence: u64) !u64 {
    const control = try live.decodeControl(control_bytes);
    if (control.kind != kind or control.sequence != sequence) return Error.ControlSequenceMismatch;
    return 1;
}

/// A request, begin, and complete must be contiguous and carry the session
/// token.  BEGIN is the only reset point; COMPLETE merely releases replay.
pub const ResyncController = struct {
    token: Digest = session_token,
    state: enum { idle, requested, begun } = .idle,
    request_sequence: u64 = 0,

    pub fn request(self: *ResyncController, sequence: u64) Error!void {
        if (sequence == 0 or self.state != .idle or self.request_sequence != 0) return Error.ControlSequenceMismatch;
        self.request_sequence = sequence;
        self.state = .requested;
    }

    pub fn begin(self: *ResyncController, sequence: u64, scene: *frontend.Scene) Error!void {
        if (self.state != .requested or sequence != self.request_sequence + 1) return Error.ControlSequenceMismatch;
        scene.resetForResync();
        self.state = .begun;
    }

    pub fn complete(self: *ResyncController, sequence: u64) Error!void {
        if (self.state != .begun or sequence != self.request_sequence + 2) return Error.ControlSequenceMismatch;
        self.* = .{};
    }

    pub fn authenticated(self: ResyncController) bool {
        return std.mem.eql(u8, &self.token, &session_token);
    }
};

fn encodeTokenizedControl(
    gpa: std.mem.Allocator,
    kind: live.Control.Kind,
    sequence: u64,
    out: *std.ArrayList(u8),
) !void {
    var control_bytes: [live.control_size]u8 = undefined;
    live.encodeControl(.{ .kind = kind, .sequence = sequence }, &control_bytes);
    try out.appendSlice(gpa, &control_bytes);
    // Token authentication is local to the in-process recovery adapter.  This
    // mirrors the EPXL smoke's token gate without adding a socket or transport.
    var mac_value: [32]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&mac_value, &control_bytes, session_token[0..]);
    try out.appendSlice(gpa, &mac_value);
}

fn decodeTokenizedControl(
    _gpa: std.mem.Allocator,
    bytes: []const u8,
    expected_kind: live.Control.Kind,
    expected_sequence: u64,
) !u64 {
    _ = _gpa;
    if (bytes.len != live.control_size + 32) return Error.ControlSequenceMismatch;
    var expected_mac: [32]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&expected_mac, bytes[0..live.control_size], session_token[0..]);
    if (!std.crypto.timing_safe.eql([32]u8, expected_mac, bytes[live.control_size..][0..32].*))
        return Error.RecoveryTokenMismatch;
    return try expectControl(bytes[0..live.control_size], expected_kind, expected_sequence);
}

fn directPath(gpa: std.mem.Allocator, messages: *const Messages) !PathResult {
    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    const accepted = try applyAll(&scene, messages.items.items);
    return .{ .path = .direct_ordered, .digest = try fingerprint(gpa, &scene), .accepted_count = accepted };
}

fn resyncPath(gpa: std.mem.Allocator, messages: *const Messages) !PathResult {
    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    var controller: ResyncController = .{};
    if (!controller.authenticated()) return Error.RecoveryTokenMismatch;

    const stale_accepted = try applyAll(&scene, messages.items.items);
    // A normal same-session replay is rejected before recovery is authorized.
    const same_sequence_accepted = scene.apply(messages.items.items[0]);
    if (same_sequence_accepted) |_| return Error.ControlSequenceMismatch else |_| {}

    var controls: std.ArrayList(u8) = .empty;
    defer controls.deinit(gpa);
    try encodeTokenizedControl(gpa, .resync_request, 7, &controls);
    try encodeTokenizedControl(gpa, .resync_begin, 8, &controls);
    try encodeTokenizedControl(gpa, .resync_complete, 9, &controls);

    var accepted: u64 = stale_accepted;
    var offset: usize = 0;
    accepted += try decodeTokenizedControl(gpa, controls.items[offset..][0..52], .resync_request, 7);
    try controller.request(7);
    offset += 52;
    accepted += try decodeTokenizedControl(gpa, controls.items[offset..][0..52], .resync_begin, 8);
    try controller.begin(8, &scene);
    accepted += try applyAll(&scene, messages.items.items);
    offset += 52;
    accepted += try decodeTokenizedControl(gpa, controls.items[offset..][0..52], .resync_complete, 9);
    try controller.complete(9);
    return .{ .path = .authenticated_resync, .digest = try fingerprint(gpa, &scene), .accepted_count = accepted };
}

const Applier = struct {
    applied_sequence: ?u64 = null,
    accepted_retries: u64 = 0,
    applications: u64 = 0,

    fn applyOnce(self: *Applier, sequence: u64) bool {
        if (self.applied_sequence != sequence) {
            self.applied_sequence = sequence;
            self.applications += 1;
            return true;
        }
        self.accepted_retries += 1;
        return false;
    }
};

fn ackLossPath(gpa: std.mem.Allocator) !PathResult {
    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    const create = try createMessage(gpa);
    defer gpa.free(create);
    try scene.apply(create);

    var baseline: Messages = .{};
    defer baseline.deinit(gpa);
    try baseline.items.append(gpa, try gpa.dupe(u8, create));

    var journal: input.DeliveryJournal = .{};
    var applier: Applier = .{};
    try journal.pushText("beta");
    const first = (try journal.take()) orelse return Error.IdempotenceMismatch; // ACK lost

    var controller: ResyncController = .{};
    try controller.request(1);
    try controller.begin(2, &scene);
    _ = try applyAll(&scene, baseline.items.items);
    try controller.complete(3);

    journal.beginRetry();
    const retry = (try journal.take()) orelse return Error.IdempotenceMismatch;
    if (retry.sequence != first.sequence or
        !std.mem.eql(u8, retry.event.text.bytes(), first.event.text.bytes()) or
        !std.mem.eql(u8, retry.event.text.bytes(), "beta")) return Error.IdempotenceMismatch;

    // The publisher observes the retry, but only the first post-resync delivery
    // is allowed to request the authoritative update.
    const applied_once = applier.applyOnce(first.sequence);
    const applied_on_retry = applier.applyOnce(retry.sequence);

    var final_messages: Messages = .{};
    defer final_messages.deinit(gpa);
    if (applied_once) try appendSnapshot(gpa, final_snapshot, &scene, &final_messages);

    var tracker = live.AckTracker.init(1);
    try tracker.markSent(scene.frame_header.?.sequence);
    try tracker.ack(scene.frame_header.?.sequence);
    const duplicate_tracker_ack: bool = if (tracker.ack(scene.frame_header.?.sequence)) |_| true else |_| false;
    const journal_ack = journal.acknowledge(retry.sequence);
    const duplicate_journal_ack = journal.acknowledge(retry.sequence);

    const valid = applied_once and !applied_on_retry and applier.applications == 1 and
        applier.accepted_retries == 1 and journal_ack and !duplicate_journal_ack and
        !duplicate_tracker_ack;
    if (!valid or scene.stats.frame_updates != 1) return Error.IdempotenceMismatch;

    return .{
        .path = .ack_loss_retry,
        .digest = try fingerprint(gpa, &scene),
        .accepted_count = 1 + baseline.items.items.len + 3 + final_messages.items.items.len + 1 + 1 + 1,
    };
}

fn replayPath(gpa: std.mem.Allocator, io: std.Io, messages: *const Messages, replay_path: []const u8) !PathResult {
    try transport.writeReplay(gpa, io, replay_path, messages.items.items);
    const loaded = try transport.readReplay(gpa, io, replay_path);
    defer transport.freeReplay(gpa, loaded);
    if (loaded.len != messages.items.items.len) return Error.DigestMismatch;
    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    const accepted = try applyAll(&scene, loaded);
    return .{ .path = .erp1_replay, .digest = try fingerprint(gpa, &scene), .accepted_count = accepted + 1 };
}

pub fn run(gpa: std.mem.Allocator, io: std.Io, replay_path: []const u8) !Summary {
    var messages = try buildMessages(gpa);
    defer messages.deinit(gpa);
    var paths: [4]PathResult = undefined;
    paths[0] = try directPath(gpa, &messages);
    paths[1] = try resyncPath(gpa, &messages);
    paths[2] = try ackLossPath(gpa);
    paths[3] = try replayPath(gpa, io, &messages, replay_path);

    const digest = paths[0].digest;
    var accepted_count: u64 = 0;
    for (paths) |path| {
        if (!std.mem.eql(u8, &path.digest, &digest)) return Error.DigestMismatch;
        accepted_count += path.accepted_count;
    }
    return .{ .paths = paths, .digest = digest, .accepted_count = accepted_count };
}

fn mismatchedRun(gpa: std.mem.Allocator, io: std.Io, replay_path: []const u8) !Summary {
    var summary = try run(gpa, io, replay_path);
    summary.paths[1].digest[0] ^= 1;
    return summary;
}

pub fn compare(left: Summary, right: Summary) Error!void {
    if (!std.mem.eql(u8, &left.digest, &right.digest)) return Error.DigestMismatch;
    for (left.paths, right.paths) |left_path, right_path| {
        if (left_path.path != right_path.path or
            !std.mem.eql(u8, &left_path.digest, &right_path.digest) or
            left_path.accepted_count != right_path.accepted_count) return Error.DigestMismatch;
    }
}

fn printDigestHex(digest: Digest) [64]u8 {
    var output: [64]u8 = undefined;
    for (digest, 0..) |byte, index| {
        output[index * 2] = std.fmt.hex_charset[byte >> 4];
        output[index * 2 + 1] = std.fmt.hex_charset[byte & 15];
    }
    return output;
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, "zig-out/proto-ui");
    const replay_path = "zig-out/proto-ui/recovery-diff.erp1";
    defer cwd.deleteFile(io, replay_path) catch {};

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const summary = run(gpa, io, replay_path) catch |err| {
        std.debug.print("{{\"result\":\"fail\",\"reason\":\"{s}\"}}\n", .{@errorName(err)});
        return err;
    };
    _ = minimal;

    const digest_hex = printDigestHex(summary.digest);
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    try output.appendSlice(arena,
        \\{"summary":"proto-ui-recovery-diff","paths":[
    );
    for (summary.paths, 0..) |path, index| {
        const path_digest = printDigestHex(path.digest);
        try output.print(arena, "{s}{{\"name\":\"{s}\",\"digest\":\"{s}\",\"accepted\":{d}}}", .{
            if (index == 0) "" else ",",
            path.path.name(),
            &path_digest,
            path.accepted_count,
        });
    }
    try output.print(arena, "],\"final_digest\":\"{s}\",\"accepted_count\":{d},\"result\":\"pass\"}}\n", .{
        &digest_hex,
        summary.accepted_count,
    });
    try std.Io.File.stdout().writeStreamingAll(io, output.items);
}

test "canonical fingerprint is stable and detects changed scene state" {
    const gpa = std.testing.allocator;
    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    const create = try createMessage(gpa);
    defer gpa.free(create);
    try scene.apply(create);
    var messages: Messages = .{};
    defer messages.deinit(gpa);
    try appendSnapshot(gpa, final_snapshot, &scene, &messages);

    const first = try fingerprint(gpa, &scene);
    const second = try fingerprint(gpa, &scene);
    try std.testing.expectEqualSlices(u8, &first, &second);

    const altered_update = try gpa.dupe(u8, messages.items.items[0]);
    defer gpa.free(altered_update);
    altered_update[altered_update.len - 8] ^= 0x01;
    try std.testing.expectError(protocol.Error.InvalidEnvelope, scene.apply(altered_update));

    // Sensitivity is checked without another replacement allocation: the next
    // authoritative update would change this public viewport value.
    scene.viewport.?.line_count += 1;
    const changed = try fingerprint(gpa, &scene);
    try std.testing.expect(!std.mem.eql(u8, &first, &changed));
}

test "four paths converge through direct, resync, ACK retry, and replay" {
    const gpa = std.testing.allocator;
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();
    const replay_path = "recovery-diff-unit.erp1";
    defer std.Io.Dir.cwd().deleteFile(io, replay_path) catch {};
    const summary = try run(gpa, io, replay_path);
    try std.testing.expectEqualStrings("pass", summary.result);
    try std.testing.expectEqual(@as(u64, 21), summary.accepted_count);

    const replayed = try transport.readReplay(gpa, io, replay_path);
    defer transport.freeReplay(gpa, replayed);
    try std.testing.expectEqual(@as(usize, 2), replayed.len);
}

test "ACK-loss retry is accepted once and duplicate ACKs are rejected" {
    const gpa = std.testing.allocator;
    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    const create = try createMessage(gpa);
    defer gpa.free(create);
    try scene.apply(create);

    var baseline: Messages = .{};
    defer baseline.deinit(gpa);
    try baseline.items.append(gpa, try gpa.dupe(u8, create));

    var journal: input.DeliveryJournal = .{};
    try journal.pushText("beta");
    const first = (try journal.take()).?;
    journal.beginRetry();
    const retry = (try journal.take()).?;
    try std.testing.expectEqual(first.sequence, retry.sequence);
    try std.testing.expectEqualSlices(u8, first.event.text.bytes(), retry.event.text.bytes());
    try std.testing.expect(journal.acknowledge(first.sequence));
    try std.testing.expect(!journal.acknowledge(first.sequence));
}

test "mismatch detection rejects a deliberately altered update path" {
    const gpa = std.testing.allocator;
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();
    const replay_path = "recovery-diff-mismatch.erp1";
    defer std.Io.Dir.cwd().deleteFile(io, replay_path) catch {};
    const baseline = try run(gpa, io, replay_path);
    const altered = try mismatchedRun(gpa, io, replay_path);
    try std.testing.expectError(Error.DigestMismatch, compare(baseline, altered));
}

test "resync controller enforces request, begin, and complete order" {
    const gpa = std.testing.allocator;
    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    var controller: ResyncController = .{};
    try std.testing.expectError(Error.ControlSequenceMismatch, controller.begin(2, &scene));
    try controller.request(1);
    try std.testing.expectError(Error.ControlSequenceMismatch, controller.begin(3, &scene));
    try controller.begin(2, &scene);
    try std.testing.expectError(Error.ControlSequenceMismatch, controller.complete(4));
    try controller.complete(3);
    try std.testing.expectError(Error.ControlSequenceMismatch, controller.request(0));
}

test "tokenized resync controls authenticate only exact bytes" {
    const gpa = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(gpa);
    try encodeTokenizedControl(gpa, .resync_request, 4, &bytes);
    try std.testing.expectEqual(@as(u64, 1), try decodeTokenizedControl(gpa, bytes.items, .resync_request, 4));
    bytes.items[bytes.items.len - 1] ^= 1;
    try std.testing.expectError(Error.RecoveryTokenMismatch, decodeTokenizedControl(gpa, bytes.items, .resync_request, 4));
}
