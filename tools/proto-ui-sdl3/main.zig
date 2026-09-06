//! Independent SDL3 frontend that consumes EUP replay or local live sessions.
//!
//! This slice decodes a real EUP `FRAME_UPDATE`, builds frontend-owned scene
//! state, and renders frame/window/row/cursor geometry.  The local live
//! transport path does not yet connect to GNU Emacs.

const std = @import("std");
const native_os = @import("builtin").os.tag;
const proto_ui = @import("proto_ui");
const frontend = proto_ui.frontend;
const facts = proto_ui.facts;
const protocol = proto_ui.protocol;
const transport = proto_ui.transport;
const live = proto_ui.live;

const SDL_INIT_VIDEO: c_uint = 0x0000_0020;
const SDL_WINDOW_RESIZABLE: c_ulonglong = 0x0000_0020;
const SDL_EVENT_QUIT: c_uint = 0x100;

const SDL_Window = opaque {};
const SDL_Renderer = opaque {};

const SDLInitFlags = c_uint;
const SDLWindowFlags = c_ulonglong;

extern fn SDL_Init(flags: SDLInitFlags) bool;
extern fn SDL_Quit() void;
extern fn SDL_CreateWindow(title: [*:0]const u8, w: c_int, h: c_int, flags: SDLWindowFlags) ?*SDL_Window;
extern fn SDL_DestroyWindow(window: *SDL_Window) void;
extern fn SDL_CreateRenderer(window: *SDL_Window, name: ?[*:0]const u8) ?*SDL_Renderer;
extern fn SDL_DestroyRenderer(renderer: *SDL_Renderer) void;
extern fn SDL_GetWindowSize(window: *SDL_Window, w: *c_int, h: *c_int) void;
extern fn SDL_SetRenderDrawColor(renderer: *SDL_Renderer, r: u8, g: u8, b: u8, a: u8) bool;
extern fn SDL_RenderClear(renderer: *SDL_Renderer) bool;
extern fn SDL_RenderFillRect(renderer: *SDL_Renderer, rect: ?*const SDL_Rect) bool;
extern fn SDL_RenderPresent(renderer: *SDL_Renderer) bool;
extern fn SDL_RenderDebugText(renderer: *SDL_Renderer, x: f32, y: f32, text: [*:0]const u8) bool;
extern fn SDL_PollEvent(event: *SDL_Event) bool;
extern fn SDL_Delay(ms: c_uint) void;
extern fn SDL_GetError() [*:0]const u8;

const SDL_Event = extern struct {
    type: c_uint = 0,
    padding: [124]u8 align(8) = [_]u8{0} ** 124,
};

const SDL_Rect = extern struct {
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
};

const Mode = enum { replay, live, publisher, emacs, facts_publisher, emacs_epxl, emacs_epxl_reconnect, emacs_epxl_input, emacs_epxl_edit };

const Config = struct {
    mode: Mode = .replay,
    self_exe: []const u8 = "",
    replay_path: []const u8 = "",
    endpoint: []const u8 = "",
    token_path: []const u8 = "",
    token: live.Token = undefined,
    emacs_path: []const u8 = "",
    module_path: []const u8 = "",
    facts_path: []const u8 = "",
    auto_quit_ms: u32 = 250,
    resync_sessions: u32 = 1,
    auto_input: ?[]const u8 = null,
    auto_key: ?frontend.KeyAction = null,
};

const FrameFacts = facts.FrameFacts;

const SharedFacts = struct {
    mutex: std.Io.Mutex = .init,
    facts: ?FrameFacts = null,
    version: u64 = 0,
};

fn sdlFail(what: []const u8) error{SdlFailed} {
    std.debug.print("sdl3-eup-smoke: {s} failed: {s}\n", .{ what, SDL_GetError() });
    return error.SdlFailed;
}

fn drawRect(renderer: *SDL_Renderer, rect: SDL_Rect, r: u8, g: u8, b: u8) !void {
    if (!SDL_SetRenderDrawColor(renderer, r, g, b, 255)) return sdlFail("SDL_SetRenderDrawColor");
    if (!SDL_RenderFillRect(renderer, &rect)) return sdlFail("SDL_RenderFillRect");
}

fn renderScene(scene: *frontend.Scene, renderer: *SDL_Renderer, window: *SDL_Window) !void {
    const header = scene.frame_header orelse return error.NoFrameUpdate;
    var output_w: c_int = 0;
    var output_h: c_int = 0;
    SDL_GetWindowSize(window, &output_w, &output_h);
    if (output_w <= 0 or output_h <= 0 or header.logical_width <= 0 or header.logical_height <= 0)
        return error.InvalidOutputGeometry;

    const scale: f32 = @min(
        @as(f32, @floatFromInt(output_w)) / @as(f32, @floatFromInt(header.logical_width)),
        @as(f32, @floatFromInt(output_h)) / @as(f32, @floatFromInt(header.logical_height)),
    );

    if (!SDL_SetRenderDrawColor(renderer, 0x18, 0x20, 0x2a, 255)) return sdlFail("SDL_SetRenderDrawColor");
    if (!SDL_RenderClear(renderer)) return sdlFail("SDL_RenderClear");

    for (scene.rows.items) |row| {
        const owner = findSceneWindow(scene, row.window_id) orelse continue;
        const row_rect = SDL_Rect{
            .x = @intFromFloat(@as(f32, @floatFromInt(owner.x + row.x)) * scale),
            .y = @intFromFloat(@as(f32, @floatFromInt(owner.y + row.y)) * scale),
            .w = @max(1, @as(c_int, @intFromFloat(@as(f32, @floatFromInt(row.width)) * scale))),
            .h = @max(1, @as(c_int, @intFromFloat(@as(f32, @floatFromInt(row.visible_height)) * scale))),
        };
        const stripe: u8 = if (row.index % 2 == 0) 0x33 else 0x2b;
        try drawRect(renderer, row_rect, stripe, stripe + 0x0d, 0x3a);
    }

    if (!SDL_SetRenderDrawColor(renderer, 0xe8, 0xee, 0xf6, 255)) return sdlFail("SDL_SetRenderDrawColor");
    for (scene.text.items) |line| {
        const owner = findSceneWindow(scene, scene.rows.items[line.row_index].window_id) orelse continue;
        const row = scene.rows.items[line.row_index];
        const text_x: f32 = @floatFromInt(owner.x + row.x + 2);
        const text_y: f32 = @floatFromInt(owner.y + row.y + @max(1, row.baseline - 8));
        if (!SDL_RenderDebugText(renderer, text_x, text_y, line.bytes)) return sdlFail("SDL_RenderDebugText");
    }

    for (scene.windows.items) |scene_window| {
        const border = SDL_Rect{
            .x = @intFromFloat(@as(f32, @floatFromInt(scene_window.x)) * scale),
            .y = @intFromFloat(@as(f32, @floatFromInt(scene_window.y)) * scale),
            .w = @max(1, @as(c_int, @intFromFloat(@as(f32, @floatFromInt(scene_window.width)) * scale))),
            .h = @max(1, @as(c_int, @intFromFloat(@as(f32, @floatFromInt(scene_window.height)) * scale))),
        };
        if (!SDL_SetRenderDrawColor(renderer, 0x71, 0xa6, 0xf2, 255)) return sdlFail("SDL_SetRenderDrawColor");
        if (!SDL_RenderFillRect(renderer, &.{ .x = border.x, .y = border.y, .w = border.w, .h = 1 })) return sdlFail("SDL_RenderFillRect");
        if (!SDL_RenderFillRect(renderer, &.{ .x = border.x, .y = border.y + border.h - 1, .w = border.w, .h = 1 })) return sdlFail("SDL_RenderFillRect");
        if (!SDL_RenderFillRect(renderer, &.{ .x = border.x, .y = border.y, .w = 1, .h = border.h })) return sdlFail("SDL_RenderFillRect");
        if (!SDL_RenderFillRect(renderer, &.{ .x = border.x + border.w - 1, .y = border.y, .w = 1, .h = border.h })) return sdlFail("SDL_RenderFillRect");
    }

    if (scene.cursor) |cursor| {
        const owner = findSceneWindow(scene, cursor.window_id) orelse return error.CursorWithoutWindow;
        const cursor_rect = SDL_Rect{
            .x = @intFromFloat(@as(f32, @floatFromInt(owner.x + cursor.x)) * scale),
            .y = @intFromFloat(@as(f32, @floatFromInt(owner.y + cursor.y)) * scale),
            .w = @max(2, @as(c_int, @intFromFloat(@as(f32, @floatFromInt(cursor.width)) * scale))),
            .h = @max(2, @as(c_int, @intFromFloat(@as(f32, @floatFromInt(cursor.height)) * scale))),
        };
        try drawRect(renderer, cursor_rect, 0xff, 0xd5, 0x4d);
    }

    if (!SDL_RenderPresent(renderer)) return sdlFail("SDL_RenderPresent");
}

fn setString(gpa: std.mem.Allocator, field: *[]const u8, value: []const u8) !void {
    const copied = try gpa.dupe(u8, value);
    errdefer gpa.free(copied);
    field.* = copied;
}

fn freeConfig(gpa: std.mem.Allocator, config: *const Config) void {
    if (config.self_exe.len != 0) gpa.free(config.self_exe);
    if (config.replay_path.len != 0) gpa.free(config.replay_path);
    if (config.endpoint.len != 0) gpa.free(config.endpoint);
    if (config.token_path.len != 0) gpa.free(config.token_path);
    if (config.facts_path.len != 0) gpa.free(config.facts_path);
}

fn runPublisher(gpa: std.mem.Allocator, io: std.Io, config: *Config) !void {
    config.token = try readTokenFile(gpa, io, config.token_path);
    _ = std.Io.Dir.cwd().deleteFile(io, config.endpoint) catch {};

    const address = try std.Io.net.UnixAddress.init(config.endpoint);
    var server = try address.listen(io, .{ .kernel_backlog = 1 });
    defer server.deinit(io);

    var stream = try server.accept(io);
    defer stream.close(io);

    var read_buffer: [16 * 1024]u8 = undefined;
    var write_buffer: [16 * 1024]u8 = undefined;
    var reader = stream.reader(io, &read_buffer);
    var writer = stream.writer(io, &write_buffer);

    var hello_bytes: [live.handshake_size]u8 = undefined;
    try reader.interface.readSliceAll(&hello_bytes);
    const hello = try live.decodeHandshake(&hello_bytes);
    if (hello.kind != .client_hello or !live.tokenEql(&config.token, &hello.token))
        return error.InvalidHandshake;

    var ready: [live.handshake_size]u8 = undefined;
    live.encodeHandshake(.{ .kind = .server_ready }, &ready);
    try writer.interface.writeAll(&ready);
    try writer.interface.flush();

    const messages = try transport.readReplay(gpa, io, config.replay_path);
    defer transport.freeReplay(gpa, messages);
    var acks = live.AckTracker.init(1);
    for (messages) |message| {
        const envelope = (try protocol.decodeEnvelope(message)).envelope;
        try acks.markSent(envelope.sequence);
        try live.writeFrame(&writer.interface, message);
        try writer.interface.flush();
        var control_bytes: [live.control_size]u8 = undefined;
        try reader.interface.readSliceAll(&control_bytes);
        const control = try live.decodeControl(&control_bytes);
        if (control.kind != .ack) return error.ExpectedAck;
        try acks.ack(control.sequence);
    }
}

fn runFactsPublisher(gpa: std.mem.Allocator, io: std.Io, config: *Config) !void {
    _ = std.Io.Dir.cwd().deleteFile(io, config.facts_path) catch {};
    const input_path = try std.fmt.allocPrint(gpa, "{s}.keys", .{config.facts_path});
    defer gpa.free(input_path);
    _ = std.Io.Dir.cwd().deleteFile(io, input_path) catch {};
    _ = std.Io.Dir.cwd().deleteFile(io, config.endpoint) catch {};
    const eval = try std.fmt.allocPrint(
        gpa,
        "(progn (module-load (expand-file-name (format \"%s\" (format \"{s}\")))) (let* ((frame (selected-frame)) (window (selected-window)) (path (expand-file-name (format \"%s\" (format \"{s}\")))) (input-path (expand-file-name (format \"%s\" (format \"{s}\")))) (buffer (window-buffer window)) (facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))) (text (with-current-buffer buffer (buffer-substring-no-properties (point-min) (point-max)))) (lines (split-string text \"\\n\")) (point (with-current-buffer buffer (window-point window))) (cursor (with-current-buffer buffer (save-excursion (goto-char point) (list :line (line-number-at-pos point) :column (current-column)))))) (with-current-buffer buffer (erase-buffer) (insert \"Emacs Proto-UI\\nvisible ASCII textZ\") (redisplay)) (setq facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))) (with-temp-file path (insert (json-serialize (list :frame_width (plist-get facts :frame_width) :frame_height (plist-get facts :frame_height) :window_width (plist-get facts :window_width) :window_height (plist-get facts :window_height) :text (vconcat lines) :cursor cursor)))) (sit-for 0.2) (set-frame-size frame 240 30) (while t (when (file-readable-p input-path) (let ((action (split-string (with-temp-buffer (insert-file-contents input-path) (buffer-string)) \"\\n\" t))) (if (and (= (length action) 2) (string= (nth 0 action) \"key\") (string= (nth 1 action) \"backspace\")) (with-current-buffer buffer (goto-char (point-max)) (delete-char -1) (set-window-point window (point)) (redisplay)) (when (and (= (length action) 2) (string= (nth 0 action) \"text\") (> (length (nth 1 action)) 0)) (with-current-buffer buffer (goto-char (point-min)) (insert (nth 1 action)) (set-window-point window (point)) (redisplay)))) (delete-file input-path))) (setq text (with-current-buffer buffer (buffer-substring-no-properties (point-min) (point-max)))) (setq lines (split-string text \"\\n\")) (setq point (with-current-buffer buffer (window-point window))) (setq cursor (with-current-buffer buffer (save-excursion (goto-char point) (list :line (line-number-at-pos point) :column (current-column))))) (setq facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))) (with-temp-file path (insert (json-serialize (list :frame_width (plist-get facts :frame_width) :frame_height (plist-get facts :frame_height) :window_width (plist-get facts :window_width) :window_height (plist-get facts :window_height) :text (vconcat lines) :cursor cursor)))) (sit-for 0.1))))",
        .{ config.module_path, config.facts_path, input_path },
    );
    defer gpa.free(eval);

    var child_environment = try buildDisplayEnvironment(gpa);
    defer child_environment.deinit();
    var emacs_child = try std.process.spawn(io, .{
        .argv = &.{ config.emacs_path, "--batch", "--eval", eval },
        .environ_map = &child_environment,
    });
    defer emacs_child.kill(io);

    const address = try std.Io.net.UnixAddress.init(config.endpoint);
    var server = try address.listen(io, .{ .kernel_backlog = 1 });
    defer server.deinit(io);

    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    var published: ?facts.Snapshot = null;
    defer if (published != null) published.?.deinit(gpa);
    var input_sequence: u64 = 1;
    const publish_duration = @max(100, config.auto_quit_ms / 2);

    for (0..@max(1, config.resync_sessions)) |session_index| {
        var stream = try server.accept(io);
        defer stream.close(io);
        var read_buffer: [16 * 1024]u8 = undefined;
        var write_buffer: [16 * 1024]u8 = undefined;
        var reader = stream.reader(io, &read_buffer);
        var writer = stream.writer(io, &write_buffer);

        var hello_bytes: [live.handshake_size]u8 = undefined;
        try reader.interface.readSliceAll(&hello_bytes);
        const hello = try live.decodeHandshake(&hello_bytes);
        if (hello.kind != .client_hello or !live.tokenEql(&config.token, &hello.token))
            return error.InvalidHandshake;
        var ready: [live.handshake_size]u8 = undefined;
        live.encodeHandshake(.{ .kind = .server_ready }, &ready);
        try writer.interface.writeAll(&ready);
        try writer.interface.flush();

        const request = try readControlExact(&reader);
        if (request.kind != .resync_request or request.sequence != 1)
            return error.InvalidResyncRequest;
        scene.resetForResync();
        try live.writeControl(&writer.interface, .{ .kind = .resync_begin, .sequence = 1 });
        try writer.interface.flush();

        var initial_snapshot: ?facts.Snapshot = null;
        var facts_wait_ms: u32 = 0;
        while (initial_snapshot == null and facts_wait_ms < 1000) : (facts_wait_ms += 20) {
            const snapshot_bytes = std.Io.Dir.cwd().readFileAlloc(io, config.facts_path, gpa, .limited(64 * 1024)) catch |err| switch (err) {
                error.FileNotFound => null,
                else => return err,
            };
            if (snapshot_bytes) |bytes| {
                defer gpa.free(bytes);
                initial_snapshot = facts.parseSnapshot(gpa, bytes) catch null;
            }
            if (initial_snapshot == null)
                try io.sleep(.fromMilliseconds(20), .awake);
        }
        if (initial_snapshot == null) return error.NoEmacsFacts;
        if (published) |*previous| previous.deinit(gpa);
        published = initial_snapshot;
        var acks = live.AckTracker.init(1);
        try sendSnapshotMessages(gpa, published.?.facts, published.?.text.lines, published.?.cursor, &scene, &acks, io, &reader, &writer, input_path, &input_sequence);
        const complete_sequence = scene.next_sequence.? - 1;
        try live.writeControl(&writer.interface, .{ .kind = .resync_complete, .sequence = complete_sequence });
        try writer.interface.flush();

        if (session_index + 1 < @max(1, config.resync_sessions)) continue;
        var waited_ms: u32 = 0;
        while (waited_ms < publish_duration) {
            const facts_bytes = std.Io.Dir.cwd().readFileAlloc(io, config.facts_path, gpa, .limited(64 * 1024)) catch |err| switch (err) {
                error.FileNotFound => {
                    try io.sleep(.fromMilliseconds(20), .awake);
                    waited_ms += 20;
                    continue;
                },
                else => return err,
            };
            defer gpa.free(facts_bytes);
            var next = facts.parseSnapshot(gpa, facts_bytes) catch {
                try io.sleep(.fromMilliseconds(20), .awake);
                waited_ms += 20;
                continue;
            };
            if (published) |previous| {
                if (previous.eql(next)) {
                    next.deinit(gpa);
                    try io.sleep(.fromMilliseconds(20), .awake);
                    waited_ms += 20;
                    continue;
                }
            }
            if (published) |*previous| previous.deinit(gpa);
            published = next;
            var change_acks = live.AckTracker.init(1);
            try sendSnapshotMessages(gpa, next.facts, next.text.lines, next.cursor, &scene, &change_acks, io, &reader, &writer, input_path, &input_sequence);
            try io.sleep(.fromMilliseconds(100), .awake);
            waited_ms += 100;
        }
    }
    if (scene.stats.frame_updates == 0) return error.NoEmacsFacts;
}

fn readControlExact(reader: anytype) !live.Control {
    var bytes: [live.control_size]u8 = undefined;
    try reader.interface.readSliceAll(&bytes);
    return live.decodeControl(&bytes);
}

fn sendAutoTextInput(
    gpa: std.mem.Allocator,
    writer: anytype,
    reader: anytype,
    text: []const u8,
    envelope: protocol.Envelope,
) !void {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try frontend.encodeTextInput(gpa, .{ .text = text }, &payload);
    var input_message: std.ArrayList(u8) = .empty;
    defer input_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.requires_ack,
        .message_type = protocol.Message.text_input,
        .sequence = 1,
        .ack_sequence = 0,
        .session_id = envelope.session_id,
        .frame_id = envelope.frame_id,
        .timestamp_ns = 1,
    }, payload.items, &input_message);
    try live.writeFrame(&writer.interface, input_message.items);
    try writer.interface.flush();
    const input_ack = try readControlExact(reader);
    if (input_ack.kind != .ack or input_ack.sequence != 1) return error.ExpectedInputAck;
}

fn sendAutoKeyEvent(
    gpa: std.mem.Allocator,
    writer: anytype,
    reader: anytype,
    action: frontend.KeyAction,
    envelope: protocol.Envelope,
) !void {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try frontend.encodeKeyEvent(gpa, .{ .action = action }, &payload);
    var input_message: std.ArrayList(u8) = .empty;
    defer input_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.requires_ack,
        .message_type = protocol.Message.key_event,
        .sequence = 1,
        .ack_sequence = 0,
        .session_id = envelope.session_id,
        .frame_id = envelope.frame_id,
        .timestamp_ns = 1,
    }, payload.items, &input_message);
    try live.writeFrame(&writer.interface, input_message.items);
    try writer.interface.flush();
    const input_ack = try readControlExact(reader);
    if (input_ack.kind != .ack or input_ack.sequence != 1) return error.ExpectedInputAck;
}

fn writeInputArtifact(gpa: std.mem.Allocator, io: std.Io, path: []const u8, kind: []const u8, value: []const u8) !void {
    const temporary_path = try std.fmt.allocPrint(gpa, "{s}.tmp", .{path});
    defer gpa.free(temporary_path);
    _ = std.Io.Dir.cwd().deleteFile(io, temporary_path) catch {};
    {
        var file = try std.Io.Dir.cwd().createFile(io, temporary_path, .{});
        defer file.close(io);
        var buffer: [256]u8 = undefined;
        var writer = file.writer(io, &buffer);
        try writer.interface.writeAll(kind);
        try writer.interface.writeAll("\n");
        try writer.interface.writeAll(value);
        try writer.interface.writeAll("\n");
        try writer.interface.flush();
    }
    std.Io.Dir.renameAbsolute(temporary_path, path, io) catch |err| {
        _ = std.Io.Dir.cwd().deleteFile(io, temporary_path) catch {};
        return err;
    };
}

const Inbound = union(enum) {
    control: live.Control,
    frame: []u8,
};

fn readInbound(reader: anytype, gpa: std.mem.Allocator) !Inbound {
    const header = try reader.interface.peekArray(4);
    if (std.mem.eql(u8, header, &live.control_magic)) {
        return .{ .control = try readControlExact(reader) };
    }
    return .{ .frame = (try live.readFrame(&reader.interface, gpa)) orelse return error.ExpectedFrame };
}

fn awaitFrameAck(
    gpa: std.mem.Allocator,
    io: std.Io,
    reader: anytype,
    writer: anytype,
    expected_sequence: u64,
    input_path: []const u8,
    input_sequence: *u64,
    expected_session_id: u64,
    expected_frame_id: u32,
) !void {
    while (true) {
        const inbound = try readInbound(reader, gpa);
        switch (inbound) {
            .control => |control| {
                if (control.kind != .ack or control.sequence != expected_sequence) return error.ExpectedAck;
                return;
            },
            .frame => |frame| {
                defer gpa.free(frame);
                const payload = try protocol.decodeEnvelope(frame);
                const is_text = payload.envelope.message_type == protocol.Message.text_input;
                const is_key = payload.envelope.message_type == protocol.Message.key_event;
                if ((!is_text and !is_key) or
                    payload.envelope.flags & protocol.Flags.requires_ack == 0 or
                    payload.envelope.ack_sequence != 0 or
                    payload.envelope.session_id != expected_session_id or
                    payload.envelope.frame_id != expected_frame_id)
                    return error.ExpectedAck;
                if (payload.envelope.sequence != input_sequence.*)
                    return error.InvalidSequence;
                if (is_text) {
                    const input = try frontend.decodeTextInput(payload.bytes);
                    try writeInputArtifact(gpa, io, input_path, "text", input.text);
                } else {
                    const event = try frontend.decodeKeyEvent(payload.bytes);
                    if (event.action != .backspace) return error.Unsupported;
                    try writeInputArtifact(gpa, io, input_path, "key", "backspace");
                }
                try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = input_sequence.* });
                try writer.interface.flush();
                input_sequence.* += 1;
            },
        }
    }
}

fn sendSnapshotMessages(
    gpa: std.mem.Allocator,
    snapshot: facts.FrameFacts,
    text: []const []const u8,
    cursor: facts.CursorFacts,
    scene: *frontend.Scene,
    acks: *live.AckTracker,
    io: std.Io,
    reader: anytype,
    writer: anytype,
    input_path: []const u8,
    input_sequence: *u64,
) !void {
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| gpa.free(message);
        messages.deinit(gpa);
    }
    try facts.appendWireSnapshot(gpa, snapshot, text, cursor, scene, &messages);
    for (messages.items) |message| {
        const envelope = (try protocol.decodeEnvelope(message)).envelope;
        try acks.markSent(envelope.sequence);
        try live.writeFrame(&writer.interface, message);
        try writer.interface.flush();
        try awaitFrameAck(gpa, io, reader, writer, envelope.sequence, input_path, input_sequence, envelope.session_id, envelope.frame_id);
        try acks.ack(envelope.sequence);
    }
}

fn runLiveFrontend(gpa: std.mem.Allocator, io: std.Io, config: *const Config) !frontend.Scene {
    const address = try std.Io.net.UnixAddress.init(config.endpoint);
    var stream: std.Io.net.Stream = undefined;
    var connected = false;
    try io.sleep(.fromMilliseconds(25), .awake);
    for (0..200) |_| {
        stream = address.connect(io) catch {
            try io.sleep(.fromMilliseconds(10), .awake);
            continue;
        };
        connected = true;
        break;
    }
    if (!connected) return error.LiveEndpointUnavailable;
    defer stream.close(io);

    var write_buffer: [16 * 1024]u8 = undefined;
    var read_buffer: [16 * 1024]u8 = undefined;
    var writer = stream.writer(io, &write_buffer);
    var reader = stream.reader(io, &read_buffer);

    var hello: [live.handshake_size]u8 = undefined;
    live.encodeHandshake(.{ .kind = .client_hello, .token = config.token }, &hello);
    try writer.interface.writeAll(&hello);
    try writer.interface.flush();

    var ready_bytes: [live.handshake_size]u8 = undefined;
    try reader.interface.readSliceAll(&ready_bytes);
    const ready = try live.decodeHandshake(&ready_bytes);
    if (ready.kind != .server_ready) return error.InvalidHandshake;
    var zero_token: live.Token = [_]u8{0} ** live.token_len;
    if (!live.tokenEql(&zero_token, &ready.token)) return error.InvalidHandshake;

    const use_resync = config.mode == .emacs_epxl or config.mode == .emacs_epxl_reconnect or
        config.mode == .emacs_epxl_input or config.mode == .emacs_epxl_edit;
    var scene = frontend.Scene.init(gpa);
    errdefer scene.deinit();
    var resync_complete = false;
    var sent_input = false;
    var sent_key = false;
    if (use_resync) {
        try live.writeControl(&writer.interface, .{ .kind = .resync_request, .sequence = 1 });
        try writer.interface.flush();
        const begin = try readControlExact(&reader);
        if (begin.kind != .resync_begin or begin.sequence != 1) return error.InvalidResyncRequest;
        scene.resetForResync();
        for (0..2) |_| {
            const message = (try live.readFrame(&reader.interface, gpa)) orelse return error.IncompleteResync;
            defer gpa.free(message);
            const envelope = (try protocol.decodeEnvelope(message)).envelope;
            try scene.apply(message);
            if (config.auto_input != null and !sent_input and envelope.message_type == protocol.Message.frame_update) {
                try sendAutoTextInput(gpa, &writer, &reader, config.auto_input.?, envelope);
                sent_input = true;
            }
            if (config.auto_key != null and !sent_key and envelope.message_type == protocol.Message.frame_update) {
                try sendAutoKeyEvent(gpa, &writer, &reader, config.auto_key.?, envelope);
                sent_key = true;
            }
            try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = envelope.sequence });
            try writer.interface.flush();
        }
        const complete = try readControlExact(&reader);
        if (complete.kind != .resync_complete) return error.IncompleteResync;
        if (complete.sequence != scene.next_sequence.? - 1) return error.InvalidSequence;
        resync_complete = true;
    }
    while (true) {
        const message = (try live.readFrame(&reader.interface, gpa)) orelse break;
        defer gpa.free(message);
        const envelope = (try protocol.decodeEnvelope(message)).envelope;
        try scene.apply(message);
        if (config.auto_input != null and !sent_input and envelope.message_type == protocol.Message.frame_update) {
            try sendAutoTextInput(gpa, &writer, &reader, config.auto_input.?, envelope);
            sent_input = true;
        }
        if (config.auto_key != null and !sent_key and envelope.message_type == protocol.Message.frame_update) {
            try sendAutoKeyEvent(gpa, &writer, &reader, config.auto_key.?, envelope);
            sent_key = true;
        }
        try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = envelope.sequence });
        try writer.interface.flush();
        if (use_resync and !resync_complete) return error.IncompleteResync;
    }
    if (use_resync and !resync_complete) return error.IncompleteResync;
    if (scene.stats.frame_updates == 0) return error.NoFrameUpdate;
    return scene;
}

fn readTokenFile(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !live.Token {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64));
    defer gpa.free(bytes);
    if (bytes.len != live.token_len) return error.InvalidTokenFile;
    var token: live.Token = undefined;
    @memcpy(&token, bytes);
    return token;
}

fn writeTokenFile(io: std.Io, path: []const u8, token: *const live.Token) !void {
    const file_permissions: std.Io.Dir.Permissions = if (native_os == .windows)
        .default_file
    else
        @enumFromInt(0o600);
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .permissions = file_permissions });
    defer file.close(io);
    var buffer: [64]u8 = undefined;
    var writer = file.writer(io, &buffer);
    try writer.interface.writeAll(token);
    try writer.interface.flush();
}

fn findSceneWindow(scene: *frontend.Scene, id: u64) ?frontend.Window {
    for (scene.windows.items) |window| {
        if (window.id == id) return window;
    }
    return null;
}

fn sceneHasText(scene: *const frontend.Scene, needle: []const u8) bool {
    for (scene.text.items) |line| {
        if (std.mem.indexOf(u8, line.bytes, needle) != null) return true;
    }
    return false;
}

fn renderFacts(snapshot: FrameFacts, renderer: *SDL_Renderer, window: *SDL_Window) !void {
    var output_w: c_int = 0;
    var output_h: c_int = 0;
    SDL_GetWindowSize(window, &output_w, &output_h);
    if (output_w <= 0 or output_h <= 0) return error.InvalidOutputGeometry;
    const scale: f32 = @min(
        @as(f32, @floatFromInt(output_w)) / @as(f32, @floatFromInt(snapshot.frame_width)),
        @as(f32, @floatFromInt(output_h)) / @as(f32, @floatFromInt(snapshot.frame_height)),
    );

    if (!SDL_SetRenderDrawColor(renderer, 0x18, 0x20, 0x2a, 255)) return sdlFail("SDL_SetRenderDrawColor");
    if (!SDL_RenderClear(renderer)) return sdlFail("SDL_RenderClear");

    const row_count: i32 = 15;
    const row_height = @max(1, @divTrunc(snapshot.window_height, row_count));
    var index: i32 = 0;
    while (index < row_count) : (index += 1) {
        const stripe: u8 = if (@mod(index, 2) == 0) 0x33 else 0x2b;
        try drawRect(renderer, .{
            .x = @intFromFloat(0),
            .y = @intFromFloat(@as(f32, @floatFromInt(index * row_height)) * scale),
            .w = @max(1, @as(c_int, @intFromFloat(@as(f32, @floatFromInt(snapshot.window_width)) * scale))),
            .h = @max(1, @as(c_int, @intFromFloat(@as(f32, @floatFromInt(row_height)) * scale))),
        }, stripe, stripe + 0x0d, 0x3a);
    }

    if (!SDL_SetRenderDrawColor(renderer, 0x71, 0xa6, 0xf2, 255)) return sdlFail("SDL_SetRenderDrawColor");
    const border_w = @as(c_int, @intFromFloat(@as(f32, @floatFromInt(snapshot.window_width)) * scale));
    const border_h = @as(c_int, @intFromFloat(@as(f32, @floatFromInt(snapshot.window_height)) * scale));
    if (!SDL_RenderFillRect(renderer, &.{ .x = 0, .y = 0, .w = border_w, .h = 1 })) return sdlFail("SDL_RenderFillRect");
    if (!SDL_RenderFillRect(renderer, &.{ .x = 0, .y = border_h - 1, .w = border_w, .h = 1 })) return sdlFail("SDL_RenderFillRect");
    if (!SDL_RenderFillRect(renderer, &.{ .x = 0, .y = 0, .w = 1, .h = border_h })) return sdlFail("SDL_RenderFillRect");
    if (!SDL_RenderFillRect(renderer, &.{ .x = border_w - 1, .y = 0, .w = 1, .h = border_h })) return sdlFail("SDL_RenderFillRect");

    try drawRect(renderer, .{
        .x = @intFromFloat(8 * scale),
        .y = @intFromFloat(@as(f32, @floatFromInt(row_height)) * scale),
        .w = 2,
        .h = @intFromFloat(18 * scale),
    }, 0xff, 0xd5, 0x4d);

    if (!SDL_RenderPresent(renderer)) return sdlFail("SDL_RenderPresent");
}

fn runEmacsEpxlSession(
    gpa: std.mem.Allocator,
    io: std.Io,
    config: *Config,
    sessions: u32,
) !frontend.Scene {
    var token_bytes: [8]u8 = undefined;
    try io.randomSecure(&token_bytes);
    try io.randomSecure(&config.token);
    const suffix = std.fmt.bytesToHex(token_bytes, .lower);
    const private_dir = try std.fmt.allocPrint(gpa, ".zig-cache/proto-ui-epxl-{s}", .{suffix});
    errdefer gpa.free(private_dir);
    const directory_permissions: std.Io.Dir.Permissions = if (native_os == .windows)
        .default_dir
    else
        @enumFromInt(0o700);
    try std.Io.Dir.cwd().createDir(io, private_dir, directory_permissions);
    errdefer std.Io.Dir.cwd().deleteTree(io, private_dir) catch {};
    config.token_path = try std.fmt.allocPrint(gpa, "{s}/token", .{private_dir});
    config.endpoint = try std.fmt.allocPrint(gpa, "{s}/live.sock", .{private_dir});
    const current_dir = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(current_dir);
    const absolute_module_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ current_dir, config.module_path });
    defer gpa.free(absolute_module_path);
    const resync_sessions_arg = try std.fmt.allocPrint(gpa, "--resync-sessions={d}", .{sessions});
    defer gpa.free(resync_sessions_arg);
    config.facts_path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/proto-ui-epxl-{s}/facts.json", .{ current_dir, suffix });
    try writeTokenFile(io, config.token_path, &config.token);
    config.resync_sessions = sessions;

    var child = try std.process.spawn(io, .{
        .argv = &.{
            config.self_exe,
            "--facts-publisher",
            "--emacs",
            config.emacs_path,
            "--module",
            absolute_module_path,
            "--facts",
            config.facts_path,
            "--endpoint",
            config.endpoint,
            "--token-file",
            config.token_path,
            resync_sessions_arg,
            "--auto-quit-ms=500",
        },
    });
    errdefer child.kill(io);
    var loaded: ?frontend.Scene = null;
    errdefer if (loaded != null) loaded.?.deinit();
    for (0..sessions) |_| {
        const session = try runLiveFrontend(gpa, io, config);
        if (loaded != null) loaded.?.deinit();
        loaded = session;
        try io.sleep(.fromMilliseconds(100), .awake);
    }
    const term = try child.wait(io);
    if (term != .exited or term.exited != 0) return error.PublisherFailed;
    std.Io.Dir.cwd().deleteTree(io, private_dir) catch {};
    gpa.free(private_dir);
    return loaded.?;
}

fn parseFacts(gpa: std.mem.Allocator, bytes: []const u8) !FrameFacts {
    return facts.parse(gpa, bytes);
}

fn readFactsFile(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !?FrameFacts {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer gpa.free(bytes);
    return try parseFacts(gpa, bytes);
}

fn pollEmacsFacts(shared: *SharedFacts, gpa: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    if (try readFactsFile(gpa, io, path)) |snapshot| {
        shared.mutex.lockUncancelable(io);
        defer shared.mutex.unlock(io);
        shared.facts = snapshot;
        shared.version += 1;
    }
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var args = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer args.deinit();

    var config: Config = .{};
    config.self_exe = try gpa.dupe(u8, args.next() orelse return error.MissingSelfPath);
    defer freeConfig(gpa, &config);

    while (args.next()) |arg| {
        const replay_prefix = "--replay=";
        const quit_prefix = "--auto-quit-ms=";
        const endpoint_prefix = "--endpoint=";
        const resync_sessions_prefix = "--resync-sessions=";
        if (std.mem.eql(u8, arg, "--replay")) {
            try setString(gpa, &config.replay_path, args.next() orelse return error.MissingReplayPath);
        } else if (std.mem.startsWith(u8, arg, replay_prefix)) {
            try setString(gpa, &config.replay_path, arg[replay_prefix.len..]);
        } else if (std.mem.eql(u8, arg, "--endpoint")) {
            try setString(gpa, &config.endpoint, args.next() orelse return error.MissingEndpoint);
        } else if (std.mem.startsWith(u8, arg, endpoint_prefix)) {
            try setString(gpa, &config.endpoint, arg[endpoint_prefix.len..]);
        } else if (std.mem.startsWith(u8, arg, resync_sessions_prefix)) {
            config.resync_sessions = try std.fmt.parseInt(u32, arg[resync_sessions_prefix.len..], 10);
        } else if (std.mem.eql(u8, arg, "--token-file")) {
            try setString(gpa, &config.token_path, args.next() orelse return error.MissingTokenFile);
        } else if (std.mem.eql(u8, arg, "--auto-quit-ms")) {
            config.auto_quit_ms = std.fmt.parseInt(u32, args.next() orelse return error.InvalidAutoQuitMs, 10) catch return error.InvalidAutoQuitMs;
        } else if (std.mem.startsWith(u8, arg, quit_prefix)) {
            config.auto_quit_ms = std.fmt.parseInt(u32, arg[quit_prefix.len..], 10) catch return error.InvalidAutoQuitMs;
        } else if (std.mem.eql(u8, arg, "--live-smoke")) {
            config.mode = .live;
        } else if (std.mem.eql(u8, arg, "--publisher")) {
            config.mode = .publisher;
        } else if (std.mem.eql(u8, arg, "--emacs")) {
            try setString(gpa, &config.emacs_path, args.next() orelse return error.MissingEmacsPath);
        } else if (std.mem.eql(u8, arg, "--module")) {
            try setString(gpa, &config.module_path, args.next() orelse return error.MissingModulePath);
        } else if (std.mem.eql(u8, arg, "--emacs-facts")) {
            config.mode = .emacs;
        } else if (std.mem.eql(u8, arg, "--facts-publisher")) {
            config.mode = .facts_publisher;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-smoke")) {
            config.mode = .emacs_epxl;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-reconnect-smoke")) {
            config.mode = .emacs_epxl_reconnect;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-input-smoke")) {
            config.mode = .emacs_epxl_input;
            config.auto_input = "X";
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-edit-smoke")) {
            config.mode = .emacs_epxl_edit;
            config.auto_key = .backspace;
        } else if (std.mem.eql(u8, arg, "--facts")) {
            try setString(gpa, &config.facts_path, args.next() orelse return error.MissingFactsPath);
        } else {
            std.debug.print("sdl3-emacs-smoke: unknown argument {s}\n", .{arg});
            return error.UnknownArgument;
        }
    }

    if ((config.mode == .replay or config.mode == .live) and config.replay_path.len == 0) return error.MissingReplayPath;
    if (config.auto_quit_ms > 10_000) return error.AutoQuitMsOutOfRange;

    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();

    if (config.mode == .publisher) {
        if (config.endpoint.len == 0) return error.MissingEndpoint;
        if (config.token_path.len == 0) return error.MissingTokenPath;
        config.token = try readTokenFile(gpa, io, config.token_path);
        try runPublisher(gpa, io, &config);
        return;
    }

    if (config.mode == .facts_publisher) {
        if (config.emacs_path.len == 0) return error.MissingEmacsPath;
        if (config.module_path.len == 0) return error.MissingModulePath;
        if (config.facts_path.len == 0) return error.MissingFactsPath;
        if (config.endpoint.len == 0) return error.MissingEndpoint;
        if (config.token_path.len == 0) return error.MissingTokenPath;
        config.token = try readTokenFile(gpa, io, config.token_path);
        try runFactsPublisher(gpa, io, &config);
        return;
    }

    if (config.mode == .emacs) {
        if (config.emacs_path.len == 0) return error.MissingEmacsPath;
        if (config.module_path.len == 0) return error.MissingModulePath;
        const facts_path = ".zig-cache/proto-ui-emacs-facts.json";
        _ = std.Io.Dir.cwd().deleteFile(io, facts_path) catch {};
        const eval = try std.fmt.allocPrint(
            gpa,
            "(progn (module-load (expand-file-name (format \"%s\" (format \"{s}\")))) (let ((frame (selected-frame)) (path (expand-file-name (format \"%s\" (format \"{s}\"))))) (while t (with-temp-file path (insert (proto-ui-frame-facts frame))) (sit-for 0.1))))",
            .{ config.module_path, facts_path },
        );
        defer gpa.free(eval);
        var child_environment = try buildDisplayEnvironment(gpa);
        defer child_environment.deinit();
        var child = try std.process.spawn(io, .{
            .argv = &.{ config.emacs_path, "--batch", "--eval", eval },
            .environ_map = &child_environment,
        });
        defer child.kill(io);

        if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
        defer SDL_Quit();
        const window = SDL_CreateWindow("Emacs Proto-UI Continuous Facts", 960, 600, SDL_WINDOW_RESIZABLE) orelse return sdlFail("SDL_CreateWindow");
        defer SDL_DestroyWindow(window);
        const renderer = SDL_CreateRenderer(window, null) orelse return sdlFail("SDL_CreateRenderer");
        defer SDL_DestroyRenderer(renderer);

        var shared = SharedFacts{};
        var last_version: u64 = 0;
        var latest: FrameFacts = .{ .frame_width = 800, .frame_height = 600, .window_width = 780, .window_height = 560 };
        var snapshot_scene: ?frontend.Scene = null;
        defer if (snapshot_scene) |*scene| scene.deinit();
        var waited_ms: u32 = 0;
        while (waited_ms < config.auto_quit_ms) {
            try pollEmacsFacts(&shared, gpa, io, facts_path);
            shared.mutex.lockUncancelable(io);
            const changed = shared.version != last_version;
            if (changed) {
                last_version = shared.version;
                latest = shared.facts.?;
            }
            shared.mutex.unlock(io);
            if (changed) {
                const updated = try facts.buildScene(gpa, latest, last_version);
                if (snapshot_scene) |*previous| previous.deinit();
                snapshot_scene = updated;
            }
            if (snapshot_scene) |*scene| {
                try renderScene(scene, renderer, window);
            } else {
                try renderFacts(latest, renderer, window);
            }

            var quit = false;
            var event: SDL_Event = .{};
            while (SDL_PollEvent(&event)) {
                if (event.type == SDL_EVENT_QUIT) quit = true;
            }
            if (quit) break;
            SDL_Delay(50);
            waited_ms += 50;
        }
        if (last_version == 0) return error.NoEmacsFacts;
        std.debug.print("sdl3-emacs-smoke: observed {d} public fact snapshot(s); lifecycle OK\n", .{last_version});
        return;
    }

    var scene = switch (config.mode) {
        .replay => blk: {
            const wire_messages = try transport.readReplay(gpa, io, config.replay_path);
            defer transport.freeReplay(gpa, wire_messages);
            var loaded = frontend.Scene.init(gpa);
            errdefer loaded.deinit();
            for (wire_messages) |message| try loaded.apply(message);
            break :blk loaded;
        },
        .live => blk: {
            var token_bytes: [8]u8 = undefined;
            try io.randomSecure(&token_bytes);
            try io.randomSecure(&config.token);
            const suffix = std.fmt.bytesToHex(token_bytes, .lower);
            const private_dir = try std.fmt.allocPrint(gpa, ".zig-cache/proto-ui-live-{s}", .{suffix});
            errdefer gpa.free(private_dir);
            const directory_permissions: std.Io.Dir.Permissions = if (native_os == .windows)
                .default_dir
            else
                @enumFromInt(0o700);
            try std.Io.Dir.cwd().createDir(io, private_dir, directory_permissions);
            errdefer std.Io.Dir.cwd().deleteTree(io, private_dir) catch {};
            config.token_path = try std.fmt.allocPrint(gpa, "{s}/token", .{private_dir});
            config.endpoint = try std.fmt.allocPrint(gpa, "{s}/live.sock", .{private_dir});
            try writeTokenFile(io, config.token_path, &config.token);
            var child = try std.process.spawn(io, .{
                .argv = &.{ config.self_exe, "--publisher", "--replay", config.replay_path, "--endpoint", config.endpoint, "--token-file", config.token_path },
            });
            errdefer child.kill(io);
            const loaded = try runLiveFrontend(gpa, io, &config);
            const term = try child.wait(io);
            if (term != .exited or term.exited != 0) return error.PublisherFailed;
            std.Io.Dir.cwd().deleteTree(io, private_dir) catch {};
            gpa.free(private_dir);
            break :blk loaded;
        },
        .publisher => unreachable,
        .emacs => unreachable,
        .emacs_epxl => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_reconnect => try runEmacsEpxlSession(gpa, io, &config, 2),
        .emacs_epxl_input => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_edit => try runEmacsEpxlSession(gpa, io, &config, 1),
        .facts_publisher => unreachable,
    };
    defer scene.deinit();
    if (config.mode == .emacs_epxl and scene.stats.frame_updates != 2)
        return error.UnexpectedFactUpdateCount;
    if (config.mode == .emacs_epxl_reconnect and scene.stats.frame_updates < 2)
        return error.UnexpectedFactUpdateCount;
    if ((config.mode == .emacs_epxl or config.mode == .emacs_epxl_reconnect) and
        !sceneHasText(&scene, "Emacs Proto-UI")) return error.NoEmacsText;
    if (config.mode == .emacs_epxl_input and scene.stats.frame_updates < 2)
        return error.UnexpectedFactUpdateCount;
    if (config.mode == .emacs_epxl_input and
        !sceneHasText(&scene, "XEmacs Proto-UI")) return error.InputNotApplied;
    if (config.mode == .emacs_epxl_input and
        (scene.cursor == null or scene.cursor.?.x != 8 or scene.cursor.?.y != 0))
        return error.CursorNotApplied;
    if (config.mode == .emacs_epxl_edit) {
        const applied = scene.text.items.len > 0 and
            std.mem.eql(u8, scene.text.items[0].bytes, "Emacs Proto-UI") and
            scene.cursor != null and scene.cursor.?.x == 144 and scene.cursor.?.y == 1;
        if (!applied) return error.EditNotApplied;
    }
    if (scene.stats.frame_updates == 0) return error.NoFrameUpdate;
    if (scene.frame_header == null) return error.NoFrameHeader;

    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();

    const window = SDL_CreateWindow("Emacs Proto-UI EUP Replay", 960, 600, SDL_WINDOW_RESIZABLE) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);

    const renderer = SDL_CreateRenderer(window, null) orelse return sdlFail("SDL_CreateRenderer");
    defer SDL_DestroyRenderer(renderer);

    try renderScene(&scene, renderer, window);
    std.debug.print("sdl3-eup-smoke: applied {d} update(s), {d} window(s), {d} row(s); auto quit in {d}ms\n", .{
        scene.stats.frame_updates,
        scene.windows.items.len,
        scene.rows.items.len,
        config.auto_quit_ms,
    });

    var quit = false;
    var waited_ms: u32 = 0;
    while (!quit and waited_ms < config.auto_quit_ms) {
        var event: SDL_Event = .{};
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) quit = true;
        }
        try renderScene(&scene, renderer, window);
        SDL_Delay(10);
        waited_ms += 10;
    }

    std.debug.print("sdl3-eup-smoke: lifecycle OK ({s})\n", .{if (quit) "closed by quit event" else "auto timeout"});
}

fn buildDisplayEnvironment(gpa: std.mem.Allocator) !std.process.Environ.Map {
    var map = std.process.Environ.Map.init(gpa);
    errdefer map.deinit();
    const names = [_][*:0]const u8{
        "DISPLAY",          "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR",
        "XDG_SESSION_TYPE", "XDG_DATA_DIRS",   "XDG_CONFIG_DIRS",
        "HOME",             "PATH",            "LANG",
        "LC_ALL",           "LC_CTYPE",        "XMODIFIERS",
        "GTK_IM_MODULE",    "QT_IM_MODULE",
    };
    for (names) |name| {
        const value = std.c.getenv(name) orelse continue;
        const value_slice: []const u8 = std.mem.span(value);
        const name_slice: []const u8 = std.mem.span(name);
        try map.put(try gpa.dupe(u8, name_slice), value_slice);
    }
    return map;
}
