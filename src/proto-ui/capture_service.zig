//! Adapter-owned atomic redisplay capture and EUP FRAME_UPDATE encoding.
//!
//! Emacs remains the source of display truth.  This service only observes a
//! bounded HostV1 batch, maps it through the FrameService identity, encodes a
//! deterministic EUP envelope, and hands that completed envelope to transport.
//! It does not register a terminal or host, install redisplay hooks, own an
//! output_proto frame, or open a transport socket.

const std = @import("std");
const adapter = @import("adapter.zig");
const frame_service = @import("frame_service.zig");
const frontend = @import("frontend.zig");
const lifecycle = @import("lifecycle.zig");
const protocol = @import("protocol.zig");
const terminal = @import("terminal.zig");
const transport = @import("transport.zig");

pub const Error = adapter.Error || frame_service.Error ||
    frontend.Error || protocol.Error || error{
    CaptureNotActive,
    CaptureAlreadyEncoded,
    CaptureIncomplete,
    EncodeContextMismatch,
    UnknownFrameMapping,
};

pub const default_scale: f32 = 1.0;
pub const default_dpi: f32 = 96.0;

pub const Options = struct {
    sequence: u64,
    session_id: u64,
    timestamp_ns: u64,
    scale: f32 = default_scale,
    dpi_x: f32 = default_dpi,
    dpi_y: f32 = default_dpi,
    update_cause: u8 = 0,
    coalesced_count: u32 = 0,
};

pub const CaptureService = struct {
    frames: *frame_service.FrameService,
    encoded: bool = false,

    pub fn init(frames: *frame_service.FrameService) CaptureService {
        return .{ .frames = frames };
    }

    pub fn begin(self: *CaptureService, host_handle: u64) Error!void {
        if (self.encoded) return Error.CaptureAlreadyEncoded;
        _ = try self.activeMapping(host_handle);
        try self.frames.runtime.begin(host_handle);
    }

    pub fn captureWindow(self: *CaptureService, window_id: u64) Error!void {
        const runtime = try self.mutableRuntime();
        try runtime.captureWindow(window_id);
    }

    pub fn captureRow(self: *CaptureService, row: adapter.Row) Error!void {
        const runtime = try self.mutableRuntime();
        for (runtime.rows.items) |existing| {
            if (existing.index == row.index) return Error.InvalidArgument;
            if (rectsOverlap(
                existing.x,
                existing.y,
                existing.width,
                existing.height,
                row.x,
                row.y,
                row.width,
                row.height,
            )) return Error.InvalidArgument;
        }
        try runtime.captureRow(row);
    }

    pub fn captureCursor(self: *CaptureService, cursor: adapter.Cursor) Error!void {
        try (try self.mutableRuntime()).captureCursor(cursor);
    }

    pub fn captureDamage(self: *CaptureService, damage: adapter.Damage) Error!void {
        const runtime = try self.mutableRuntime();
        if (!frontendInside(damage.x, damage.width, runtime.geometry.width) or
            !frontendInside(damage.y, damage.height, runtime.geometry.height))
            return Error.InvalidArgument;
        try runtime.captureDamage(damage);
    }

    /// Returns an EUP transport envelope owned by the Runtime allocator
    /// (`service.frames.runtime.allocator`).  Runtime capture state is not
    /// consumed until `commitAndPublish`; a failed encode leaves it coherent.
    pub fn encodePending(self: *CaptureService, options: Options) Error![]u8 {
        const runtime = try self.mutableRuntime();
        const mapping = try self.activeMapping(runtime.frame_id);
        try validateBatch(runtime);
        try validateOptions(options);

        const allocator = runtime.allocator;
        var sections: [4]protocol.Section = undefined;
        var section_count: usize = 0;
        var window_bytes: std.ArrayList(u8) = .empty;
        defer window_bytes.deinit(allocator);
        var row_bytes: std.ArrayList(u8) = .empty;
        defer row_bytes.deinit(allocator);
        var cursor_bytes: std.ArrayList(u8) = .empty;
        defer cursor_bytes.deinit(allocator);
        var damage_bytes: std.ArrayList(u8) = .empty;
        defer damage_bytes.deinit(allocator);

        try frontend.encodeWindow(allocator, .{
            .id = runtime.window_id,
            .frame_id = mapping.eup_frame_id,
            .x = runtime.geometry.x,
            .y = runtime.geometry.y,
            .width = runtime.geometry.width,
            .height = runtime.geometry.height,
        }, &window_bytes);
        sections[section_count] = .{
            .kind = protocol.SectionKind.windows,
            .records = window_bytes.items,
        };
        section_count += 1;

        var rows: [adapter.max_rows]adapter.Row = undefined;
        const row_count = runtime.rows.items.len;
        @memcpy(rows[0..row_count], runtime.rows.items);
        sortRows(rows[0..row_count]);
        for (rows[0..row_count]) |row| {
            try frontend.encodeRow(allocator, .{
                .window_id = row.window_id,
                .index = row.index,
                .flags = 0,
                .x = row.x,
                .y = row.y,
                .width = row.width,
                .height = row.height,
                .ascent = row.ascent,
                .descent = row.descent,
                .baseline = row.baseline,
                .visible_height = row.visible_height,
            }, &row_bytes);
        }
        sections[section_count] = .{
            .kind = protocol.SectionKind.rows,
            .records = row_bytes.items,
        };
        section_count += 1;

        if (runtime.cursor) |cursor| {
            try frontend.encodeCursor(allocator, .{
                .window_id = cursor.window_id,
                .x = cursor.x,
                .y = cursor.y,
                .width = cursor.width,
                .height = cursor.height,
                .kind = cursor.kind,
                .visible = cursor.visible,
                .active = cursor.active,
            }, &cursor_bytes);
            sections[section_count] = .{
                .kind = protocol.SectionKind.cursors,
                .records = cursor_bytes.items,
            };
            section_count += 1;
        }

        var damage: [adapter.max_damage]adapter.Damage = undefined;
        const damage_count = runtime.damage.items.len;
        @memcpy(damage[0..damage_count], runtime.damage.items);
        sortDamage(damage[0..damage_count]);
        for (damage[0..damage_count]) |rect| {
            try frontend.encodeRect(allocator, .{
                .x = rect.x,
                .y = rect.y,
                .width = rect.width,
                .height = rect.height,
            }, &damage_bytes);
        }
        sections[section_count] = .{
            .kind = protocol.SectionKind.damage,
            .records = damage_bytes.items,
        };
        section_count += 1;

        var update_bytes: std.ArrayList(u8) = .empty;
        defer update_bytes.deinit(allocator);
        try protocol.encodeFrameUpdate(allocator, .{
            .header = .{
                .frame_id = mapping.eup_frame_id,
                .frame_generation = mapping.protocol_frame_generation,
                .sequence = options.sequence,
                .redisplay_generation = runtime.generation,
                .logical_x = runtime.geometry.x,
                .logical_y = runtime.geometry.y,
                .logical_width = runtime.geometry.width,
                .logical_height = runtime.geometry.height,
                .physical_x = runtime.geometry.x,
                .physical_y = runtime.geometry.y,
                .physical_width = runtime.geometry.width,
                .physical_height = runtime.geometry.height,
                .scale = options.scale,
                .dpi_x = options.dpi_x,
                .dpi_y = options.dpi_y,
                .damage_mode = damageMode(runtime.geometry, damage[0..damage_count]),
                .update_cause = options.update_cause,
                .coalesced_count = options.coalesced_count,
                .timestamp_ns = options.timestamp_ns,
            },
            .sections = sections[0..section_count],
        }, &update_bytes);

        try validateEncodedPayload(allocator, update_bytes.items, options, mapping.eup_frame_id);
        var envelope: std.ArrayList(u8) = .empty;
        errdefer envelope.deinit(allocator);
        try protocol.encodeEnvelope(allocator, .{
            .flags = protocol.Flags.delta | protocol.Flags.requires_ack,
            .message_type = protocol.Message.frame_update,
            .sequence = options.sequence,
            .ack_sequence = 0,
            .session_id = options.session_id,
            .frame_id = mapping.eup_frame_id,
            .timestamp_ns = options.timestamp_ns,
        }, update_bytes.items, &envelope);
        try validateEncodedEnvelope(envelope.items, options, mapping.eup_frame_id);

        self.encoded = true;
        return envelope.toOwnedSlice(allocator);
    }

    /// Encoding happens before Runtime commit.  Runtime's stale-generation
    /// check therefore runs before the sink can observe the envelope.
    pub fn commitAndPublish(
        self: *CaptureService,
        options: Options,
        sink: *transport.MemorySink,
    ) Error!void {
        const runtime = try self.mutableRuntime();
        const mapping = try self.activeMapping(runtime.frame_id);
        if (self.encoded) return Error.EncodeContextMismatch;

        const encoded = try self.encodePending(options);
        defer runtime.allocator.free(encoded);
        const current = try self.activeMapping(runtime.frame_id);
        if (!mappingIdentityEquals(mapping, current))
            return Error.EncodeContextMismatch;

        _ = try runtime.commit();
        self.encoded = false;
        _ = try sink.send(.{
            .flags = protocol.Flags.delta | protocol.Flags.requires_ack,
            .message_type = protocol.Message.frame_update,
            .sequence = options.sequence,
            .ack_sequence = 0,
            .session_id = options.session_id,
            .frame_id = current.eup_frame_id,
            .timestamp_ns = options.timestamp_ns,
        }, encoded);
    }

    pub fn cancel(self: *CaptureService) void {
        self.frames.runtime.cancel();
        self.encoded = false;
    }

    fn mutableRuntime(self: *CaptureService) Error!*adapter.Runtime {
        if (self.encoded) return Error.CaptureAlreadyEncoded;
        const runtime = self.frames.runtime;
        if (runtime.phase != .capturing) return Error.CaptureNotActive;
        _ = try self.activeMapping(runtime.frame_id);
        return runtime;
    }

    fn activeMapping(self: *CaptureService, host_handle: u64) Error!frame_service.Mapping {
        if (host_handle == 0) return Error.InvalidArgument;
        return self.frames.lookupHost(host_handle) orelse Error.UnknownFrameMapping;
    }

    fn validateBatch(runtime: *adapter.Runtime) Error!void {
        if (!runtime.has_window or !runtime.has_row or runtime.rows.items.len == 0 or
            !runtime.has_damage or runtime.damage.items.len == 0)
            return Error.CaptureIncomplete;
        if (!runtime.has_cursor or runtime.cursor == null)
            return Error.CaptureIncomplete;
        if (runtime.cursor) |cursor| {
            if (cursor.window_id != runtime.window_id or !cursorWithin(runtime, cursor))
                return Error.InvalidArgument;
        }

        for (runtime.rows.items, 0..) |row, index| {
            if (row.window_id != runtime.window_id or row.index == 0)
                return Error.InvalidArgument;
            if (!frontendInside(row.x, row.width, runtime.geometry.width) or
                !frontendInside(row.y, row.height, runtime.geometry.height) or
                row.ascent < 0 or row.descent < 0 or row.visible_height < 0)
                return Error.InvalidArgument;
            for (runtime.rows.items[0..index]) |prior| {
                if (prior.index == row.index or rowsOverlap(prior, row))
                    return Error.InvalidArgument;
            }
        }

        for (runtime.damage.items) |damage| {
            if (!frontendInside(damage.x, damage.width, runtime.geometry.width) or
                !frontendInside(damage.y, damage.height, runtime.geometry.height))
                return Error.InvalidArgument;
        }
    }

    fn validateOptions(options: Options) Error!void {
        if (options.sequence == 0 or options.session_id == 0)
            return Error.InvalidArgument;
        if (!std.math.isFinite(options.scale) or options.scale <= 0 or
            !std.math.isFinite(options.dpi_x) or options.dpi_x <= 0 or
            !std.math.isFinite(options.dpi_y) or options.dpi_y <= 0)
            return Error.InvalidArgument;
    }

    fn validateEncodedPayload(
        allocator: std.mem.Allocator,
        payload: []const u8,
        options: Options,
        frame_id: u32,
    ) Error!void {
        var decoded = try protocol.decodeFrameUpdate(allocator, payload);
        defer protocol.freeFrameUpdate(allocator, &decoded);
        if (decoded.header.frame_id != frame_id or
            decoded.header.sequence != options.sequence or
            decoded.header.timestamp_ns != options.timestamp_ns)
            return Error.InvalidMessage;
    }

    fn validateEncodedEnvelope(
        envelope_bytes: []const u8,
        options: Options,
        frame_id: u32,
    ) Error!void {
        const decoded = try protocol.decodeEnvelope(envelope_bytes);
        if (decoded.envelope.message_type != protocol.Message.frame_update or
            decoded.envelope.sequence != options.sequence or
            decoded.envelope.session_id != options.session_id or
            decoded.envelope.frame_id != frame_id or
            decoded.envelope.timestamp_ns != options.timestamp_ns)
            return Error.InvalidMessage;
    }

    fn damageMode(geometry: adapter.Geometry, damage: []const adapter.Damage) u8 {
        if (damage.len == 1 and damage[0].x == 0 and damage[0].y == 0 and
            damage[0].width == geometry.width and damage[0].height == geometry.height)
            return 2;
        return 1;
    }

    fn mappingIdentityEquals(
        left: frame_service.Mapping,
        right: frame_service.Mapping,
    ) bool {
        return left.host_handle == right.host_handle and
            left.eup_frame_id == right.eup_frame_id and
            left.host_generation == right.host_generation and
            left.protocol_frame_generation == right.protocol_frame_generation and
            left.active and right.active;
    }

    fn rowsOverlap(left: adapter.Row, right: adapter.Row) bool {
        return rectsOverlap(
            left.x,
            left.y,
            left.width,
            left.height,
            right.x,
            right.y,
            right.width,
            right.height,
        );
    }

    fn rectsOverlap(
        left_x: i32,
        left_y: i32,
        left_width: i32,
        left_height: i32,
        right_x: i32,
        right_y: i32,
        right_width: i32,
        right_height: i32,
    ) bool {
        if (left_width <= 0 or left_height <= 0 or
            right_width <= 0 or right_height <= 0) return false;
        return left_x < right_x + right_width and right_x < left_x + left_width and
            left_y < right_y + right_height and right_y < left_y + left_height;
    }

    fn cursorWithin(runtime: *const adapter.Runtime, cursor: adapter.Cursor) bool {
        return frontendInside(cursor.x, cursor.width, runtime.geometry.width) and
            frontendInside(cursor.y, cursor.height, runtime.geometry.height);
    }

    fn frontendInside(offset: i32, extent: i32, limit: i32) bool {
        return offset >= 0 and extent >= 0 and offset <= limit and extent <= limit - offset;
    }

    fn sortRows(rows: []adapter.Row) void {
        insertionSort(adapter.Row, rows, rowLess);
    }

    fn sortDamage(damage: []adapter.Damage) void {
        insertionSort(adapter.Damage, damage, damageLess);
    }

    fn rowLess(left: adapter.Row, right: adapter.Row) bool {
        return left.index < right.index;
    }

    fn damageLess(left: adapter.Damage, right: adapter.Damage) bool {
        if (left.x != right.x) return left.x < right.x;
        if (left.y != right.y) return left.y < right.y;
        if (left.width != right.width) return left.width < right.width;
        return left.height < right.height;
    }

    fn insertionSort(
        comptime T: type,
        items: []T,
        comptime less: fn (left: T, right: T) bool,
    ) void {
        var index: usize = 1;
        while (index < items.len) : (index += 1) {
            const value = items[index];
            var position = index;
            while (position > 0 and less(value, items[position - 1])) : (position -= 1) {
                items[position] = items[position - 1];
            }
            items[position] = value;
        }
    }
};

test "capture service encodes, applies, deterministically re-encodes, and replays" {
    const a = std.testing.allocator;
    var fixture = try TestFixture.init(.{ .generation = 1 });
    defer fixture.deinit();
    _ = try fixture.frames_service.register(11, 7);
    var service = CaptureService.init(fixture.frames_service);
    try fixture.populate(&service);
    const options: Options = .{ .sequence = 2, .session_id = 8, .timestamp_ns = 44 };
    const first = try service.encodePending(options);
    defer a.free(first);
    try std.testing.expectError(Error.CaptureAlreadyEncoded, service.captureWindow(1));
    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try applyCreate(a, &scene, 7, 8, 1);
    try scene.apply(first);

    service.cancel();
    try fixture.populate(&service);
    const second = try service.encodePending(options);
    defer a.free(second);
    try std.testing.expectEqualSlices(u8, first, second);

    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = try std.fmt.allocPrint(a, ".zig-cache/tmp/{s}/capture", .{tmp.sub_path});
    defer a.free(path);
    try transport.writeReplay(a, io, path, &.{ first, second });
    const replay = try transport.readReplay(a, io, path);
    defer transport.freeReplay(a, replay);
    try std.testing.expectEqual(@as(usize, 2), replay.len);
    try std.testing.expectEqualSlices(u8, first, replay[0]);
    try std.testing.expectEqualSlices(u8, second, replay[1]);
}

test "capture service commit publishes only after a fresh generation check" {
    const a = std.testing.allocator;
    var fixture = try TestFixture.init(.{ .generation = 1 });
    defer fixture.deinit();
    _ = try fixture.frames_service.register(11, 7);
    var service = CaptureService.init(fixture.frames_service);
    try fixture.populate(&service);
    var sink = transport.MemorySink.init(a);
    defer sink.deinit();
    try service.commitAndPublish(
        .{ .sequence = 2, .session_id = 8, .timestamp_ns = 9 },
        &sink,
    );
    try std.testing.expectEqual(@as(usize, 1), sink.messages.items.len);
    try std.testing.expectEqual(adapter.Phase.idle, fixture.runtime.phase);
    try std.testing.expectEqual(@as(u64, 1), fixture.runtime.committed_updates);

    try fixture.populate(&service);
    fixture.host.generation = 99;
    try std.testing.expectError(
        adapter.Error.GenerationMismatch,
        service.commitAndPublish(
            .{ .sequence = 3, .session_id = 8, .timestamp_ns = 10 },
            &sink,
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), sink.messages.items.len);
    try std.testing.expectEqual(adapter.Phase.capturing, fixture.runtime.phase);
    service.cancel();
}

test "capture service rejects incomplete and malformed batches atomically" {
    var fixture = try TestFixture.init(.{ .generation = 1 });
    defer fixture.deinit();
    _ = try fixture.frames_service.register(11, 7);
    var service = CaptureService.init(fixture.frames_service);

    try std.testing.expectError(Error.UnknownFrameMapping, service.begin(999));
    try service.begin(11);
    const options: Options = .{ .sequence = 2, .session_id = 1, .timestamp_ns = 1 };
    try std.testing.expectError(Error.CaptureIncomplete, service.encodePending(options));

    try service.captureWindow(1);
    try std.testing.expectError(Error.CaptureIncomplete, service.encodePending(options));
    try service.captureRow(.{ .window_id = 1, .index = 2, .x = 0, .y = 0, .width = 40, .height = 5, .ascent = 4, .descent = 1, .baseline = 4, .visible_height = 5 });
    try std.testing.expectError(adapter.Error.InvalidArgument, service.captureRow(.{ .window_id = 1, .index = 2, .x = 0, .y = 20, .width = 1, .height = 1, .ascent = 1, .descent = 0, .baseline = 1, .visible_height = 1 }));
    try std.testing.expectError(adapter.Error.InvalidArgument, service.captureRow(.{ .window_id = 999, .index = 3, .x = 0, .y = 10, .width = 1, .height = 1, .ascent = 1, .descent = 0, .baseline = 1, .visible_height = 1 }));
    try std.testing.expectError(Error.CaptureIncomplete, service.encodePending(options));
    try service.captureCursor(.{ .window_id = 1, .x = 1, .y = 1, .width = 1, .height = 2, .kind = 1, .visible = true, .active = true });
    try std.testing.expectError(adapter.Error.InvalidArgument, service.captureCursor(.{ .window_id = 999, .x = 1, .y = 1, .width = 1, .height = 2, .kind = 1, .visible = true, .active = true }));
    try std.testing.expectError(Error.CaptureIncomplete, service.encodePending(options));
    try service.captureDamage(.{ .x = 0, .y = 0, .width = 40, .height = 10 });
    const encoded = try service.encodePending(options);
    defer fixture.runtime.allocator.free(encoded);
    service.cancel();
    try std.testing.expectEqual(@as(usize, 0), fixture.runtime.rows.items.len);
    try std.testing.expectError(Error.CaptureNotActive, service.captureWindow(1));
}

test "capture service requires an active frame mapping and coherent encode state" {
    var fixture = try TestFixture.init(.{ .generation = 1 });
    defer fixture.deinit();
    var service = CaptureService.init(fixture.frames_service);
    try std.testing.expectError(Error.UnknownFrameMapping, service.begin(11));
    _ = try fixture.frames_service.register(11, 7);
    try fixture.populate(&service);
    const encoded = try service.encodePending(.{ .sequence = 2, .session_id = 8, .timestamp_ns = 3 });
    defer fixture.runtime.allocator.free(encoded);
    try std.testing.expectError(Error.CaptureAlreadyEncoded, service.begin(11));
    try std.testing.expectError(Error.CaptureAlreadyEncoded, service.captureRow(baseRow()));
    try std.testing.expectEqual(@as(usize, 1), fixture.runtime.rows.items.len);
    service.cancel();
    try std.testing.expectEqual(@as(usize, 0), fixture.runtime.rows.items.len);
}

test "capture service enforces stable row order and bounded rows" {
    var fixture = try TestFixture.init(.{ .generation = 1 });
    defer fixture.deinit();
    _ = try fixture.frames_service.register(11, 7);
    var service = CaptureService.init(fixture.frames_service);
    try service.begin(11);
    try service.captureWindow(1);
    try service.captureRow(.{ .window_id = 1, .index = 3, .x = 0, .y = 0, .width = 40, .height = 0, .ascent = 0, .descent = 0, .baseline = 0, .visible_height = 0 });
    try service.captureRow(.{ .window_id = 1, .index = 1, .x = 0, .y = 0, .width = 40, .height = 0, .ascent = 0, .descent = 0, .baseline = 0, .visible_height = 0 });
    try service.captureRow(.{ .window_id = 1, .index = 2, .x = 0, .y = 0, .width = 40, .height = 0, .ascent = 0, .descent = 0, .baseline = 0, .visible_height = 0 });
    for (4..adapter.max_rows + 1) |index| {
        try service.captureRow(.{
            .window_id = 1,
            .index = @intCast(index),
            .x = 0,
            .y = 0,
            .width = 40,
            .height = 0,
            .ascent = 0,
            .descent = 0,
            .baseline = 0,
            .visible_height = 0,
        });
    }
    try std.testing.expectError(adapter.Error.LimitExceeded, service.captureRow(.{
        .window_id = 1,
        .index = @intCast(adapter.max_rows + 1),
        .x = 0,
        .y = 0,
        .width = 40,
        .height = 0,
        .ascent = 0,
        .descent = 0,
        .baseline = 0,
        .visible_height = 0,
    }));
    try service.captureCursor(.{ .window_id = 1, .x = 0, .y = 0, .width = 1, .height = 1, .kind = 0, .visible = true, .active = true });
    try service.captureDamage(.{ .x = 0, .y = 0, .width = 1, .height = 1 });
    const encoded = try service.encodePending(.{ .sequence = 2, .session_id = 8, .timestamp_ns = 3 });
    defer fixture.runtime.allocator.free(encoded);
    const decoded = try protocol.decodeEnvelope(encoded);
    var update = try protocol.decodeFrameUpdate(fixture.runtime.allocator, decoded.bytes);
    defer protocol.freeFrameUpdate(fixture.runtime.allocator, &update);
    const rows_section = update.sections[1];
    try std.testing.expectEqual(protocol.SectionKind.rows, rows_section.kind);
    try std.testing.expectEqual(adapter.max_rows * 56, rows_section.records.len);
    try std.testing.expectEqual(@as(u32, 1), std.mem.readInt(u32, rows_section.records[8..12], .little));
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, rows_section.records[64..68], .little));
    try std.testing.expectError(Error.CaptureAlreadyEncoded, service.captureDamage(.{ .x = 100, .y = 0, .width = 1, .height = 1 }));
}

test "capture service damage mode is full frame only for the logical window" {
    const allocator = std.testing.allocator;
    var fixture = try TestFixture.init(.{ .generation = 1 });
    defer fixture.deinit();
    _ = try fixture.frames_service.register(11, 7);
    var service = CaptureService.init(fixture.frames_service);
    try fixture.populate(&service);
    const full = try service.encodePending(.{ .sequence = 2, .session_id = 8, .timestamp_ns = 1 });
    defer allocator.free(full);
    const full_decoded = try protocol.decodeEnvelope(full);
    var full_update = try protocol.decodeFrameUpdate(allocator, full_decoded.bytes);
    defer protocol.freeFrameUpdate(allocator, &full_update);
    try std.testing.expectEqual(@as(u8, 2), full_update.header.damage_mode);

    service.cancel();
    try service.begin(11);
    try service.captureWindow(1);
    try service.captureRow(baseRow());
    try service.captureCursor(.{ .window_id = 1, .x = 0, .y = 0, .width = 1, .height = 1, .kind = 0, .visible = true, .active = true });
    try service.captureDamage(.{ .x = 0, .y = 0, .width = 40, .height = 10 });
    try service.captureDamage(.{ .x = 0, .y = 0, .width = 1, .height = 1 });
    const partial = try service.encodePending(.{ .sequence = 2, .session_id = 8, .timestamp_ns = 1 });
    defer allocator.free(partial);
    const partial_decoded = try protocol.decodeEnvelope(partial);
    var partial_update = try protocol.decodeFrameUpdate(allocator, partial_decoded.bytes);
    defer protocol.freeFrameUpdate(allocator, &partial_update);
    try std.testing.expectEqual(@as(u8, 1), partial_update.header.damage_mode);
}

test "different cursor or damage encodes a different applicable update" {
    const a = std.testing.allocator;
    var fixture = try TestFixture.init(.{ .generation = 1 });
    defer fixture.deinit();
    _ = try fixture.frames_service.register(11, 7);
    var service = CaptureService.init(fixture.frames_service);
    try fixture.populate(&service);
    const first = try service.encodePending(.{ .sequence = 2, .session_id = 8, .timestamp_ns = 1 });
    defer a.free(first);
    var scene_one = frontend.Scene.init(a);
    defer scene_one.deinit();
    try applyCreate(a, &scene_one, 7, 8, 1);
    try scene_one.apply(first);

    service.cancel();
    try fixture.populate(&service);
    fixture.runtime.cursor.?.x = 8;
    const second = try service.encodePending(.{ .sequence = 2, .session_id = 8, .timestamp_ns = 1 });
    defer a.free(second);
    try std.testing.expect(!std.mem.eql(u8, first, second));
    var scene_two = frontend.Scene.init(a);
    defer scene_two.deinit();
    try applyCreate(a, &scene_two, 7, 8, 1);
    try scene_two.apply(second);
    try std.testing.expectEqual(@as(i32, 8), scene_two.cursor.?.x);

    service.cancel();
    try fixture.populate(&service);
    try service.captureDamage(.{ .x = 0, .y = 0, .width = 1, .height = 1 });
    fixture.runtime.damage.items[0] = .{ .x = 1, .y = 1, .width = 38, .height = 8 };
    const third = try service.encodePending(.{ .sequence = 2, .session_id = 8, .timestamp_ns = 1 });
    defer a.free(third);
    try std.testing.expect(!std.mem.eql(u8, first, third));
    var scene_three = frontend.Scene.init(a);
    defer scene_three.deinit();
    try applyCreate(a, &scene_three, 7, 8, 1);
    try scene_three.apply(third);
    try std.testing.expectEqual(@as(usize, 2), scene_three.damage.items.len);
}

test "bounded runtime limits propagate before encoding" {
    var fixture = try TestFixture.init(.{ .generation = 1 });
    defer fixture.deinit();
    _ = try fixture.frames_service.register(11, 7);
    var service = CaptureService.init(fixture.frames_service);
    try service.begin(11);
    try service.captureWindow(1);
    try service.captureRow(baseRow());
    for (0..adapter.max_damage) |index| {
        try service.captureDamage(.{ .x = @intCast(index % 40), .y = @intCast(index % 10), .width = 1, .height = 1 });
    }
    try std.testing.expectError(adapter.Error.LimitExceeded, service.captureDamage(.{ .x = 0, .y = 0, .width = 1, .height = 1 }));
    service.cancel();
}

const TestFixture = struct {
    host: *CaptureHost,
    table: *adapter.HostV1,
    runtime: *adapter.Runtime,
    frames: *lifecycle.FrameRegistry,
    terminals: *terminal.TerminalRegistry,
    frames_service: *frame_service.FrameService,

    const InitOptions = struct { generation: u64 };

    fn init(options: InitOptions) !TestFixture {
        const allocator = std.testing.allocator;
        const host = try allocator.create(CaptureHost);
        host.* = CaptureHost.init(options.generation);
        const table = try allocator.create(adapter.HostV1);
        table.* = host.table();
        const runtime = try allocator.create(adapter.Runtime);
        runtime.* = try adapter.Runtime.init(allocator, table);
        const frames = try allocator.create(lifecycle.FrameRegistry);
        frames.* = .{};
        const terminals = try allocator.create(terminal.TerminalRegistry);
        terminals.* = .{};
        _ = try terminals.create(9, terminal.initial_generation);
        _ = try terminals.activate(9, terminal.initial_generation);
        const service = try allocator.create(frame_service.FrameService);
        service.* = try frame_service.FrameService.init(runtime, frames, terminals, 9);
        return .{
            .host = host,
            .table = table,
            .runtime = runtime,
            .frames = frames,
            .terminals = terminals,
            .frames_service = service,
        };
    }

    fn deinit(self: *TestFixture) void {
        const allocator = std.testing.allocator;
        self.runtime.deinit();
        self.frames.reset();
        self.terminals.reset();
        allocator.destroy(self.frames_service);
        allocator.destroy(self.runtime);
        allocator.destroy(self.table);
        allocator.destroy(self.frames);
        allocator.destroy(self.terminals);
        allocator.destroy(self.host);
    }

    fn populate(self: *TestFixture, service: *CaptureService) !void {
        _ = self;
        try service.begin(11);
        try service.captureWindow(1);
        try service.captureRow(baseRow());
        try service.captureCursor(.{ .window_id = 1, .x = 3, .y = 4, .width = 2, .height = 4, .kind = 1, .visible = true, .active = true });
        try service.captureDamage(.{ .x = 0, .y = 0, .width = 40, .height = 10 });
    }
};

const CaptureHost = struct {
    generation: u64,

    fn init(generation: u64) CaptureHost {
        return .{ .generation = generation };
    }

    fn table(self: *CaptureHost) adapter.HostV1 {
        return .{
            .context = self,
            .read_generation = readGeneration,
            .read_geometry = readGeometry,
            .read_frame_state = readFrameState,
        };
    }

    fn readGeneration(context: *anyopaque, frame_id: u64) callconv(.c) u64 {
        _ = frame_id;
        const self: *CaptureHost = @ptrCast(@alignCast(context));
        return self.generation;
    }

    fn readGeometry(context: *anyopaque, object_id: u64, geometry: *adapter.Geometry) callconv(.c) u8 {
        _ = context;
        _ = object_id;
        geometry.* = .{ .x = 0, .y = 0, .width = 40, .height = 10 };
        return 1;
    }

    fn readFrameState(context: *anyopaque, frame_id: u64, state: *adapter.FrameState) callconv(.c) u8 {
        _ = frame_id;
        const self: *CaptureHost = @ptrCast(@alignCast(context));
        state.* = .{
            .generation = self.generation,
            .visibility = @intFromEnum(adapter.FrameVisibility.visible),
            .focused = 1,
        };
        return 1;
    }
};

fn baseRow() adapter.Row {
    return .{
        .window_id = 1,
        .index = 1,
        .x = 0,
        .y = 0,
        .width = 40,
        .height = 5,
        .ascent = 4,
        .descent = 1,
        .baseline = 4,
        .visible_height = 5,
    };
}

fn applyCreate(
    allocator: std.mem.Allocator,
    scene: *frontend.Scene,
    frame_id: u32,
    session_id: u64,
    sequence: u64,
) !void {
    var create_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, create_payload[0..4], frame_id, .little);
    std.mem.writeInt(u32, create_payload[4..8], 1, .little);
    var create: std.ArrayList(u8) = .empty;
    defer create.deinit(allocator);
    try protocol.encodeEnvelope(allocator, .{
        .flags = 0,
        .message_type = protocol.Message.frame_create,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = session_id,
        .frame_id = frame_id,
        .timestamp_ns = 0,
    }, &create_payload, &create);
    try scene.apply(create.items);
}
