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
const renderer_policy = proto_ui.renderer;
const input_policy = proto_ui.input;
const protocol = proto_ui.protocol;
const transport = proto_ui.transport;
const live = proto_ui.live;

const SDL_INIT_VIDEO: c_uint = 0x0000_0020;
const SDL_WINDOW_RESIZABLE: c_ulonglong = 0x0000_0020;
const SDL_EVENT_QUIT: c_uint = 0x100;
const SDL_EVENT_KEY_DOWN: c_uint = 0x300;
const SDL_EVENT_TEXT_INPUT: c_uint = 0x303;

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
extern fn SDL_GetRendererName(renderer: *SDL_Renderer) [*:0]const u8;
extern fn SDL_SetRenderVSync(renderer: *SDL_Renderer, vsync: c_int) bool;
extern fn SDL_GetWindowSize(window: *SDL_Window, w: *c_int, h: *c_int) void;
extern fn SDL_SetRenderDrawColor(renderer: *SDL_Renderer, r: u8, g: u8, b: u8, a: u8) bool;
extern fn SDL_RenderClear(renderer: *SDL_Renderer) bool;
extern fn SDL_RenderFillRect(renderer: *SDL_Renderer, rect: ?*const SDL_Rect) bool;
extern fn SDL_RenderPresent(renderer: *SDL_Renderer) bool;
extern fn SDL_RenderDebugText(renderer: *SDL_Renderer, x: f32, y: f32, text: [*:0]const u8) bool;
extern fn SDL_PollEvent(event: *SDL_Event) bool;
extern fn SDL_PushEvent(event: *SDL_Event) bool;
extern fn SDL_Delay(ms: c_uint) void;
extern fn SDL_StartTextInput(window: *SDL_Window) bool;
extern fn SDL_GetTicks() u64;
extern fn SDL_GetPerformanceCounter() u64;
extern fn SDL_GetPerformanceFrequency() u64;
extern fn SDL_GetError() [*:0]const u8;

const SDL_KeyboardEvent = extern struct {
    type: c_uint,
    reserved: c_uint,
    timestamp: u64,
    window_id: c_uint,
    which: c_uint,
    scancode: i32,
    key: c_uint,
    modifiers: u16,
    raw: u16,
    down: bool,
    repeat: bool,
};

const SDL_TextInputEvent = extern struct {
    type: c_uint,
    reserved: c_uint,
    timestamp: u64,
    window_id: c_uint,
    text: ?[*:0]const u8,
};

const SDL_Event = extern union {
    type: c_uint,
    key: SDL_KeyboardEvent,
    text: SDL_TextInputEvent,
    padding: [128]u8,
};

fn keyboardEvent(scancode: i32, down: bool, modifiers: u16) SDL_Event {
    var event: SDL_Event = undefined;
    event.key = .{
        .type = SDL_EVENT_KEY_DOWN,
        .reserved = 0,
        .timestamp = 0,
        .window_id = 0,
        .which = 0,
        .scancode = scancode,
        .key = 0,
        .modifiers = modifiers,
        .raw = 0,
        .down = down,
        .repeat = false,
    };
    return event;
}

fn textEvent(text: [*:0]const u8) SDL_Event {
    var event: SDL_Event = undefined;
    event.text = .{
        .type = SDL_EVENT_TEXT_INPUT,
        .reserved = 0,
        .timestamp = 0,
        .window_id = 0,
        .text = text,
    };
    return event;
}

const SDL_Rect = extern struct {
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
};

const Mode = enum { replay, live, publisher, emacs, facts_publisher, emacs_epxl, emacs_epxl_reconnect, emacs_epxl_input, emacs_epxl_edit, emacs_epxl_sequence, input_translation, emacs_interactive };

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
    renderer_request: []const u8 = "auto",
    present_mode: []const u8 = "off",
    synthetic_interactive: bool = false,
};

const FrameFacts = facts.FrameFacts;

const SharedFacts = struct {
    mutex: std.Io.Mutex = .init,
    facts: ?FrameFacts = null,
    version: u64 = 0,
};

fn runInputTranslationSmoke() !void {
    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow("Emacs Proto-UI Input Translation", 320, 200, SDL_WINDOW_RESIZABLE) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);
    if (!SDL_StartTextInput(window)) return sdlFail("SDL_StartTextInput");

    var queue: input_policy.Queue = .{};
    var synthetic = [_]SDL_Event{
        keyboardEvent(input_policy.SDL_SCANCODE_BACKSPACE, true, 0),
        keyboardEvent(input_policy.SDL_SCANCODE_LEFT, true, 0),
        keyboardEvent(input_policy.SDL_SCANCODE_RIGHT, true, 0),
        keyboardEvent(input_policy.SDL_SCANCODE_UP, true, 0),
        keyboardEvent(input_policy.SDL_SCANCODE_DOWN, true, 0),
        keyboardEvent(input_policy.SDL_SCANCODE_BACKSPACE, true, 1),
        textEvent("Emacs"),
    };
    for (&synthetic) |*event| {
        if (!SDL_PushEvent(event)) return sdlFail("SDL_PushEvent");
    }

    var recognized: usize = 0;
    var polls: usize = 0;
    const expected_accepted: usize = 6;
    while (recognized < expected_accepted and polls < 256) : (polls += 1) {
        var event: SDL_Event = undefined;
        if (!SDL_PollEvent(&event)) {
            SDL_Delay(1);
            continue;
        }
        switch (event.type) {
            SDL_EVENT_QUIT => return error.UnexpectedQuit,
            SDL_EVENT_KEY_DOWN => {
                if (input_policy.translateKey(
                    event.key.scancode,
                    event.key.down,
                    event.key.repeat,
                    event.key.modifiers,
                )) |key| {
                    try queue.pushKey(key);
                    recognized += 1;
                }
            },
            SDL_EVENT_TEXT_INPUT => {
                if (input_policy.translateText(event.text.text)) |text| {
                    try queue.pushText(text.bytes());
                    recognized += 1;
                }
            },
            else => {},
        }
    }

    if (recognized != expected_accepted) return error.InputTranslationIncomplete;
    if (queue.length != expected_accepted) return error.InputQueueCount;
    std.debug.print(
        "sdl3-input-smoke: translated {d} keys and {d} text event; rejected {d} unsupported SDL event(s); lifecycle OK\n",
        .{ queue.length - 1, 1, synthetic.len - recognized },
    );
}

fn writeTranslatedEvent(
    gpa: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    event: input_policy.TranslatedEvent,
) !void {
    switch (event) {
        .key => |key| {
            const action_name: []const u8 = switch (key.action) {
                .backspace => "backspace",
                .cursor_left => "cursor-left",
                .cursor_right => "cursor-right",
                .cursor_up => "cursor-up",
                .cursor_down => "cursor-down",
            };
            try writeActionArtifact(gpa, io, path, "key", action_name);
        },
        .text => |text| try writeActionArtifact(gpa, io, path, "text", text.bytes()),
    }
}

fn runEmacsInteractive(gpa: std.mem.Allocator, io: std.Io, config: *const Config) !void {
    const current_dir = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(current_dir);
    const facts_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ current_dir, config.facts_path });
    defer gpa.free(facts_path);
    const input_path = try std.fmt.allocPrint(gpa, "{s}.keys", .{facts_path});
    defer gpa.free(input_path);
    if (std.fs.path.dirname(facts_path)) |directory| {
        try std.Io.Dir.cwd().createDirPath(io, directory);
    }
    _ = std.Io.Dir.cwd().deleteFile(io, facts_path) catch {};
    _ = std.Io.Dir.cwd().deleteFile(io, input_path) catch {};

    const eval = try std.fmt.allocPrint(gpa,
        \\(progn
        \\  (module-load (expand-file-name "{s}"))
        \\  (let* ((frame (selected-frame))
        \\         (window (selected-window))
        \\         (path (expand-file-name "{s}"))
        \\         (input-path (expand-file-name "{s}"))
        \\         (buffer (window-buffer window))
        \\         (text "")
        \\         (lines [])
        \\         (point (point-min))
        \\         (cursor (list :line 1 :column 0))
        \\         (facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))))
        \\    (set-frame-size frame 240 30)
        \\    (with-current-buffer buffer (erase-buffer) (insert "Emacs Proto-UI\nvisible ASCII") (set-window-point window (point)) (redisplay))
        \\    (while t
        \\      (when (file-readable-p input-path)
        \\        (let ((action (split-string (with-temp-buffer (insert-file-contents input-path) (buffer-string)) "\n" t)))
        \\          (when (= (length action) 3)
        \\            (cond
        \\              ((and (string= (nth 0 action) "key") (string= (nth 1 action) "backspace"))
        \\               (with-current-buffer buffer (when (> (point) (point-min)) (delete-char -1)) (set-window-point window (point)) (redisplay)))
        \\              ((and (string= (nth 0 action) "key") (string= (nth 1 action) "cursor-left"))
        \\               (with-current-buffer buffer (forward-char -1) (set-window-point window (point)) (redisplay)))
        \\              ((and (string= (nth 0 action) "key") (string= (nth 1 action) "cursor-right"))
        \\               (with-current-buffer buffer (forward-char 1) (set-window-point window (point)) (redisplay)))
        \\              ((and (string= (nth 0 action) "key") (string= (nth 1 action) "cursor-up"))
        \\               (with-current-buffer buffer (forward-line -1) (set-window-point window (point)) (redisplay)))
        \\              ((and (string= (nth 0 action) "key") (string= (nth 1 action) "cursor-down"))
        \\               (with-current-buffer buffer (forward-line 1) (set-window-point window (point)) (redisplay)))
        \\              ((and (string= (nth 0 action) "text") (> (length (nth 1 action)) 0))
        \\               (with-current-buffer buffer (insert (nth 1 action)) (set-window-point window (point)) (redisplay))))))
        \\        (delete-file input-path))
        \\      (setq text (with-current-buffer buffer (buffer-substring-no-properties (point-min) (point-max))))
        \\      (setq lines (split-string text "\n"))
        \\      (setq point (with-current-buffer buffer (point)))
        \\      (setq cursor (with-current-buffer buffer (save-excursion (goto-char point) (list :line (line-number-at-pos point) :column (current-column)))))
        \\      (setq facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist)))
        \\      (with-temp-file path (insert (json-serialize (list :frame_width (plist-get facts :frame_width) :frame_height (plist-get facts :frame_height) :window_width (plist-get facts :window_width) :window_height (plist-get facts :window_height) :text (vconcat lines) :cursor cursor))))
        \\      (sit-for 0.05)))))))
    , .{ config.module_path, facts_path, input_path });
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
    const window = SDL_CreateWindow("Emacs Proto-UI Interactive", 960, 600, SDL_WINDOW_RESIZABLE) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);
    const selected_renderer = try createRenderer(gpa, window, config.renderer_request, config.present_mode);
    defer destroyRenderer(selected_renderer);
    const renderer = selected_renderer.handle;
    if (!SDL_StartTextInput(window)) return sdlFail("SDL_StartTextInput");

    var frame_gate: renderer_policy.FrameGate = .{};
    var frame_counters: renderer_policy.FrameCounters = .{};
    var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
    defer draw_list.deinit();
    var input_queue: input_policy.Queue = .{};
    var latest: FrameFacts = .{ .frame_width = 240, .frame_height = 31, .window_width = 240, .window_height = 29 };
    var snapshot_scene: ?frontend.Scene = null;
    defer if (snapshot_scene) |*scene| scene.deinit();
    var previous_snapshot: ?facts.Snapshot = null;
    defer if (previous_snapshot) |*snapshot| snapshot.deinit(gpa);
    var last_version: u64 = 0;
    var observed_versions: u64 = 0;
    var delivered_events: usize = 0;
    var input_applied = false;
    var last_delivery_version: ?u64 = null;

    if (config.synthetic_interactive) {
        try input_queue.pushText("XY");
        try input_queue.pushKey(.{ .action = .cursor_left });
        try input_queue.pushText("Z");
        try input_queue.pushKey(.{ .action = .backspace });
    }

    var quit = false;
    const started_ticks = SDL_GetTicks();
    while (!quit and (!config.synthetic_interactive or SDL_GetTicks() - started_ticks < config.auto_quit_ms)) {
        const snapshot_bytes = std.Io.Dir.cwd().readFileAlloc(io, facts_path, gpa, .limited(64 * 1024)) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (snapshot_bytes) |bytes| {
            defer gpa.free(bytes);
            const next = facts.parseSnapshot(gpa, bytes) catch continue;
            var changed = true;
            if (previous_snapshot) |*previous| {
                changed = !previous.eql(next);
                previous.deinit(gpa);
            }
            previous_snapshot = next;
            if (changed) {
                if (next.text.lines.len >= 2 and std.mem.eql(u8, next.text.lines[1], "visible ASCIIXY")) input_applied = true;
                latest = next.facts;
                last_version += 1;
                observed_versions += 1;
                frame_gate.dirty = true;
            }
            if (changed) {
                const updated = try facts.buildScene(gpa, latest, last_version);
                if (snapshot_scene) |*previous| previous.deinit();
                snapshot_scene = updated;
            }
        }

        var event: SDL_Event = undefined;
        while (SDL_PollEvent(&event)) {
            switch (event.type) {
                SDL_EVENT_QUIT => quit = true,
                SDL_EVENT_KEY_DOWN => {
                    if (input_policy.translateKey(event.key.scancode, event.key.down, event.key.repeat, event.key.modifiers)) |key| {
                        try input_queue.pushKey(key);
                        frame_gate.dirty = true;
                    }
                },
                SDL_EVENT_TEXT_INPUT => {
                    if (input_policy.translateText(event.text.text)) |text| {
                        try input_queue.pushText(text.bytes());
                        frame_gate.dirty = true;
                    }
                },
                else => frame_gate.dirty = true,
            }
        }

        while (input_queue.pop()) |translated_event| {
            if (last_delivery_version) |version| {
                if (observed_versions <= version) break;
            }
            try writeTranslatedEvent(gpa, io, input_path, translated_event);
            delivered_events += 1;
            last_delivery_version = observed_versions;
            var ack_wait_ms: u32 = 0;
            while (ack_wait_ms < 2000) : (ack_wait_ms += 10) {
                if (std.Io.Dir.cwd().statFile(io, input_path, .{})) |_| {
                    SDL_Delay(10);
                } else |_| {
                    break;
                }
            }
        }

        if (snapshot_scene) |*scene| {
            try presentScene(scene, &draw_list, renderer, window, &frame_gate, &frame_counters);
        } else {
            try presentFacts(latest, &draw_list, renderer, window, &frame_gate, &frame_counters);
        }
        SDL_Delay(10);
    }

    if (observed_versions == 0) return error.NoEmacsFacts;
    std.debug.print(
        "sdl3-interactive-smoke: delivered {d} input event(s); observed {d} fact version(s); present={d} skipped={d} frame={d}ns draws={d} clears={d} fills={d} text={d}; lifecycle OK\n",
        .{
            delivered_events,
            observed_versions,
            frame_counters.presented_frames,
            frame_counters.skipped_frames,
            frame_counters.frame_path_total_ns,
            frame_counters.draw_commands_total,
            frame_counters.clear_commands_total,
            frame_counters.fill_commands_total,
            frame_counters.text_commands_total,
        },
    );

    if (config.synthetic_interactive and !input_applied) return error.InteractiveInputNotApplied;
}

const SelectedRenderer = struct {
    handle: *SDL_Renderer,
    tier: renderer_policy.Tier,
    name: []const u8,
};

fn sdlFail(what: []const u8) error{SdlFailed} {
    std.debug.print("sdl3-eup-smoke: {s} failed: {s}\n", .{ what, SDL_GetError() });
    return error.SdlFailed;
}

fn performanceTicksToNanos(ticks: u64) u64 {
    const frequency = SDL_GetPerformanceFrequency();
    if (frequency == 0) return 0;
    return @intCast(@as(u128, ticks) * 1_000_000_000 / @as(u128, frequency));
}

fn createRenderer(
    gpa: std.mem.Allocator,
    window: *SDL_Window,
    request_value: []const u8,
    present_value: []const u8,
) !SelectedRenderer {
    const request = renderer_policy.parseRequest(request_value) orelse return error.UnknownRendererPolicy;
    const present = renderer_policy.parsePresentMode(present_value) orelse return error.UnknownPresentMode;
    for (renderer_policy.candidates(request)) |candidate| {
        const name_z: ?[*:0]const u8 = if (candidate) |name|
            try std.fmt.allocPrintSentinel(gpa, "{s}", .{name}, 0)
        else
            null;
        defer if (name_z) |name| gpa.free(name[0..std.mem.len(name)]);
        const handle = SDL_CreateRenderer(window, name_z) orelse continue;
        const actual_name: []const u8 = std.mem.span(SDL_GetRendererName(handle));
        if (present != .off and !SDL_SetRenderVSync(handle, renderer_policy.vsyncNumber(present))) {
            SDL_DestroyRenderer(handle);
            return sdlFail("SDL_SetRenderVSync");
        }
        return .{ .handle = handle, .tier = renderer_policy.classify(actual_name), .name = actual_name };
    }
    return error.NoRendererAvailable;
}

fn destroyRenderer(selected: SelectedRenderer) void {
    SDL_DestroyRenderer(selected.handle);
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
    const ack_path = try std.fmt.allocPrint(gpa, "{s}.ack", .{input_path});
    defer gpa.free(ack_path);
    _ = std.Io.Dir.cwd().deleteFile(io, ack_path) catch {};
    _ = std.Io.Dir.cwd().deleteFile(io, config.endpoint) catch {};
    const eval = try std.fmt.allocPrint(
        gpa,
        "(progn (module-load (expand-file-name (format \"%s\" (format \"{s}\")))) (let* ((frame (selected-frame)) (window (selected-window)) (path (expand-file-name (format \"%s\" (format \"{s}\")))) (input-path (expand-file-name (format \"%s\" (format \"{s}\")))) (buffer (window-buffer window)) (facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))) (text (with-current-buffer buffer (buffer-substring-no-properties (point-min) (point-max)))) (lines (split-string text \"\\n\")) (point (with-current-buffer buffer (window-point window))) (cursor (with-current-buffer buffer (save-excursion (goto-char point) (list :line (line-number-at-pos point) :column (current-column)))))) (with-current-buffer buffer (erase-buffer) (insert \"Emacs Proto-UI\\nvisible ASCII textZ\") (redisplay)) (setq facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))) (with-temp-file path (insert (json-serialize (list :frame_width (plist-get facts :frame_width) :frame_height (plist-get facts :frame_height) :window_width (plist-get facts :window_width) :window_height (plist-get facts :window_height) :text (vconcat lines) :cursor cursor)))) (sit-for 0.2) (set-frame-size frame 240 30) (while t (when (file-readable-p input-path) (let ((action (split-string (with-temp-buffer (insert-file-contents input-path) (buffer-string)) \"\\n\" t))) (cond ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"backspace\")) (with-current-buffer buffer (goto-char (point-max)) (delete-char -1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"cursor-left\")) (with-current-buffer buffer (backward-char 1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"cursor-right\")) (with-current-buffer buffer (forward-char 1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"cursor-up\")) (with-current-buffer buffer (previous-line 1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"cursor-down\")) (with-current-buffer buffer (next-line 1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"text\") (> (length (nth 2 action)) 0)) (with-current-buffer buffer (goto-char (point-min)) (insert (nth 2 action)) (set-window-point window (point)) (redisplay)))) (with-temp-file (concat input-path \".ack\") (insert (nth 0 action))) (delete-file input-path))) (setq text (with-current-buffer buffer (buffer-substring-no-properties (point-min) (point-max)))) (setq lines (split-string text \"\\n\")) (setq point (with-current-buffer buffer (window-point window))) (setq cursor (with-current-buffer buffer (save-excursion (goto-char point) (list :line (line-number-at-pos point) :column (current-column))))) (setq facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))) (with-temp-file path (insert (json-serialize (list :frame_width (plist-get facts :frame_width) :frame_height (plist-get facts :frame_height) :window_width (plist-get facts :window_width) :window_height (plist-get facts :window_height) :text (vconcat lines) :cursor cursor)))) (sit-for 0.1))))",
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
    sender: *input_policy.SenderState,
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
        .sequence = try sender.takeSequence(),
        .ack_sequence = 0,
        .session_id = envelope.session_id,
        .frame_id = envelope.frame_id,
        .timestamp_ns = 1,
    }, payload.items, &input_message);
    try live.writeFrame(&writer.interface, input_message.items);
    try writer.interface.flush();
    const input_ack = try readControlExact(reader);
    if (input_ack.kind != .ack or !sender.acknowledge(input_ack.sequence)) return error.ExpectedInputAck;
}

fn sendAutoKeyEvent(
    gpa: std.mem.Allocator,
    sender: *input_policy.SenderState,
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
        .sequence = try sender.takeSequence(),
        .ack_sequence = 0,
        .session_id = envelope.session_id,
        .frame_id = envelope.frame_id,
        .timestamp_ns = 1,
    }, payload.items, &input_message);
    try live.writeFrame(&writer.interface, input_message.items);
    try writer.interface.flush();
    const input_ack = try readControlExact(reader);
    if (input_ack.kind != .ack or !sender.acknowledge(input_ack.sequence)) return error.ExpectedInputAck;
}

fn writeActionArtifact(gpa: std.mem.Allocator, io: std.Io, path: []const u8, kind: []const u8, value: []const u8) !void {
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

fn writeEpxlInputArtifact(gpa: std.mem.Allocator, io: std.Io, path: []const u8, sequence: u64, kind: []const u8, value: []const u8) !void {
    const temporary_path = try std.fmt.allocPrint(gpa, "{s}.tmp", .{path});
    defer gpa.free(temporary_path);
    _ = std.Io.Dir.cwd().deleteFile(io, temporary_path) catch {};
    {
        var file = try std.Io.Dir.cwd().createFile(io, temporary_path, .{});
        defer file.close(io);
        var buffer: [256]u8 = undefined;
        var writer = file.writer(io, &buffer);
        try writer.interface.print("{d}\n{s}\n{s}\n", .{ sequence, kind, value });
        try writer.interface.flush();
    }
    std.Io.Dir.renameAbsolute(temporary_path, path, io) catch |err| {
        _ = std.Io.Dir.cwd().deleteFile(io, temporary_path) catch {};
        return err;
    };
}

fn waitForApplyAck(
    gpa: std.mem.Allocator,
    io: std.Io,
    input_path: []const u8,
    sequence: u64,
) !void {
    const ack_path = try std.fmt.allocPrint(gpa, "{s}.ack", .{input_path});
    defer gpa.free(ack_path);
    var waited_ms: u32 = 0;
    while (waited_ms < 2000) : (waited_ms += 10) {
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, ack_path, gpa, .limited(32)) catch |err| switch (err) {
            error.FileNotFound => {
                try io.sleep(.fromMilliseconds(10), .awake);
                continue;
            },
            else => return err,
        };
        defer gpa.free(bytes);
        if (!input_policy.validApplyAck(bytes, sequence)) return error.InvalidApplyAck;
        while (waited_ms < 2000) : (waited_ms += 10) {
            if (std.Io.Dir.cwd().statFile(io, input_path, .{})) |_| {
                try io.sleep(.fromMilliseconds(10), .awake);
            } else |_| break;
        }
        if (std.Io.Dir.cwd().statFile(io, input_path, .{})) |_| {
            return error.ApplyActionCleanupTimeout;
        } else |_| {}
        std.Io.Dir.cwd().deleteFile(io, ack_path) catch |err| return err;
        return;
    }
    return error.ApplyAckTimeout;
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
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "text", input.text);
                } else {
                    const event = try frontend.decodeKeyEvent(payload.bytes);
                    const action_name: []const u8 = switch (event.action) {
                        .backspace => "backspace",
                        .cursor_left => "cursor-left",
                        .cursor_right => "cursor-right",
                        .cursor_up => "cursor-up",
                        .cursor_down => "cursor-down",
                    };
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "key", action_name);
                }
                try waitForApplyAck(gpa, io, input_path, payload.envelope.sequence);
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
        config.mode == .emacs_epxl_input or config.mode == .emacs_epxl_edit or
        config.mode == .emacs_epxl_sequence;
    var scene = frontend.Scene.init(gpa);
    errdefer scene.deinit();
    var resync_complete = false;
    var sent_input = false;
    var sent_key = false;
    var input_sender: input_policy.SenderState = .{};
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
                try sendAutoTextInput(gpa, &input_sender, &writer, &reader, config.auto_input.?, envelope);
                sent_input = true;
            }
            if (config.auto_key != null and !sent_key and envelope.message_type == protocol.Message.frame_update) {
                try sendAutoKeyEvent(gpa, &input_sender, &writer, &reader, config.auto_key.?, envelope);
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
            try sendAutoTextInput(gpa, &input_sender, &writer, &reader, config.auto_input.?, envelope);
            sent_input = true;
        }
        if (config.auto_key != null and !sent_key and envelope.message_type == protocol.Message.frame_update) {
            try sendAutoKeyEvent(gpa, &input_sender, &writer, &reader, config.auto_key.?, envelope);
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

fn buildSceneDrawList(
    scene: *frontend.Scene,
    list: *renderer_policy.DrawList,
    output_width: i32,
    output_height: i32,
) !void {
    const header = scene.frame_header orelse return error.NoFrameUpdate;
    if (output_width <= 0 or output_height <= 0 or header.logical_width <= 0 or header.logical_height <= 0)
        return error.InvalidOutputGeometry;
    const scale: f32 = @min(
        @as(f32, @floatFromInt(output_width)) / @as(f32, @floatFromInt(header.logical_width)),
        @as(f32, @floatFromInt(output_height)) / @as(f32, @floatFromInt(header.logical_height)),
    );
    const pixel: f32 = 1 / scale;

    list.reset();
    list.setLogicalSize(@floatFromInt(header.logical_width), @floatFromInt(header.logical_height));
    try list.clear(.{ .r = 0x18, .g = 0x20, .b = 0x2a });

    for (scene.rows.items) |row| {
        const owner = findSceneWindow(scene, row.window_id) orelse continue;
        const stripe: u8 = if (row.index % 2 == 0) 0x33 else 0x2b;
        try list.fillRect(.{
            .x = @floatFromInt(owner.x + row.x),
            .y = @floatFromInt(owner.y + row.y),
            .width = @floatFromInt(row.width),
            .height = @floatFromInt(row.visible_height),
        }, .{ .r = stripe, .g = stripe + 0x0d, .b = 0x3a });
    }

    for (scene.text.items) |line| {
        const owner = findSceneWindow(scene, scene.rows.items[line.row_index].window_id) orelse continue;
        const row = scene.rows.items[line.row_index];
        try list.drawText(
            @floatFromInt(owner.x + row.x + 2),
            @floatFromInt(owner.y + row.y + @max(1, row.baseline - 8)),
            line.bytes,
        );
    }

    for (scene.windows.items) |window| {
        try list.fillRect(.{
            .x = @floatFromInt(window.x),
            .y = @floatFromInt(window.y),
            .width = @floatFromInt(window.width),
            .height = pixel,
        }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
        try list.fillRect(.{
            .x = @floatFromInt(window.x),
            .y = @as(f32, @floatFromInt(window.y + window.height)) - pixel,
            .width = @floatFromInt(window.width),
            .height = pixel,
        }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
        try list.fillRect(.{
            .x = @floatFromInt(window.x),
            .y = @floatFromInt(window.y),
            .width = pixel,
            .height = @floatFromInt(window.height),
        }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
        try list.fillRect(.{
            .x = @as(f32, @floatFromInt(window.x + window.width)) - pixel,
            .y = @floatFromInt(window.y),
            .width = pixel,
            .height = @floatFromInt(window.height),
        }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
    }

    if (scene.cursor) |cursor| {
        const owner = findSceneWindow(scene, cursor.window_id) orelse return error.CursorWithoutWindow;
        try list.fillRect(.{
            .x = @floatFromInt(owner.x + cursor.x),
            .y = @floatFromInt(owner.y + cursor.y),
            .width = @floatFromInt(@max(2, cursor.width)),
            .height = @floatFromInt(@max(2, cursor.height)),
        }, .{ .r = 0xff, .g = 0xd5, .b = 0x4d });
    }
}

fn buildFactsDrawList(
    snapshot: FrameFacts,
    list: *renderer_policy.DrawList,
    output_width: i32,
    output_height: i32,
) !void {
    if (output_width <= 0 or output_height <= 0) return error.InvalidOutputGeometry;
    const scale: f32 = @min(
        @as(f32, @floatFromInt(output_width)) / @as(f32, @floatFromInt(snapshot.frame_width)),
        @as(f32, @floatFromInt(output_height)) / @as(f32, @floatFromInt(snapshot.frame_height)),
    );
    const pixel: f32 = 1 / scale;
    const row_count: i32 = 15;
    const row_height = @max(1, @divTrunc(snapshot.window_height, row_count));

    list.reset();
    list.setLogicalSize(@floatFromInt(snapshot.frame_width), @floatFromInt(snapshot.frame_height));
    try list.clear(.{ .r = 0x18, .g = 0x20, .b = 0x2a });
    var index: i32 = 0;
    while (index < row_count) : (index += 1) {
        const stripe: u8 = if (@mod(index, 2) == 0) 0x33 else 0x2b;
        try list.fillRect(.{
            .x = 0,
            .y = @as(f32, @floatFromInt(index * row_height)),
            .width = @floatFromInt(snapshot.window_width),
            .height = @floatFromInt(row_height),
        }, .{ .r = stripe, .g = stripe + 0x0d, .b = 0x3a });
    }

    const border: renderer_policy.Color = .{ .r = 0x71, .g = 0xa6, .b = 0xf2 };
    try list.fillRect(.{ .x = 0, .y = 0, .width = @floatFromInt(snapshot.window_width), .height = pixel }, border);
    try list.fillRect(.{
        .x = 0,
        .y = @as(f32, @floatFromInt(snapshot.window_height)) - pixel,
        .width = @floatFromInt(snapshot.window_width),
        .height = pixel,
    }, border);
    try list.fillRect(.{ .x = 0, .y = 0, .width = pixel, .height = @floatFromInt(snapshot.window_height) }, border);
    try list.fillRect(.{
        .x = @as(f32, @floatFromInt(snapshot.window_width)) - pixel,
        .y = 0,
        .width = pixel,
        .height = @floatFromInt(snapshot.window_height),
    }, border);
    try list.fillRect(.{
        .x = 8,
        .y = @floatFromInt(row_height),
        .width = 2,
        .height = 18,
    }, .{ .r = 0xff, .g = 0xd5, .b = 0x4d });
}

fn executeDrawList(
    list: *renderer_policy.DrawList,
    renderer: *SDL_Renderer,
    window: *SDL_Window,
) !void {
    var output_width: c_int = 0;
    var output_height: c_int = 0;
    SDL_GetWindowSize(window, &output_width, &output_height);
    if (output_width <= 0 or output_height <= 0 or
        list.logical_width <= 0 or list.logical_height <= 0) return error.InvalidOutputGeometry;
    const scale: f32 = @min(
        @as(f32, @floatFromInt(output_width)) / list.logical_width,
        @as(f32, @floatFromInt(output_height)) / list.logical_height,
    );

    for (list.commands.items) |command| switch (command) {
        .clear => |color| {
            if (!SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)) return sdlFail("SDL_SetRenderDrawColor");
            if (!SDL_RenderClear(renderer)) return sdlFail("SDL_RenderClear");
        },
        .fill => |draw| {
            const rect = SDL_Rect{
                .x = @intFromFloat(draw.rect.x * scale),
                .y = @intFromFloat(draw.rect.y * scale),
                .w = @max(1, @as(c_int, @intFromFloat(draw.rect.width * scale))),
                .h = @max(1, @as(c_int, @intFromFloat(draw.rect.height * scale))),
            };
            if (!SDL_SetRenderDrawColor(renderer, draw.color.r, draw.color.g, draw.color.b, draw.color.a)) return sdlFail("SDL_SetRenderDrawColor");
            if (!SDL_RenderFillRect(renderer, &rect)) return sdlFail("SDL_RenderFillRect");
        },
        .text => |draw| {
            var text: [121]u8 = undefined;
            @memcpy(text[0..draw.bytes.len], draw.bytes);
            text[draw.bytes.len] = 0;
            if (!SDL_RenderDebugText(renderer, draw.x * scale, draw.y * scale, text[0..draw.bytes.len :0])) return sdlFail("SDL_RenderDebugText");
        },
    };
    if (!SDL_RenderPresent(renderer)) return sdlFail("SDL_RenderPresent");
}

fn presentScene(
    scene: *frontend.Scene,
    list: *renderer_policy.DrawList,
    renderer: *SDL_Renderer,
    window: *SDL_Window,
    gate: *renderer_policy.FrameGate,
    counters: *renderer_policy.FrameCounters,
) !void {
    var width: c_int = 0;
    var height: c_int = 0;
    SDL_GetWindowSize(window, &width, &height);
    if (!gate.shouldPresent(@intCast(width), @intCast(height))) {
        counters.recordSkipped();
        return;
    }
    const started_ticks = SDL_GetPerformanceCounter();
    try buildSceneDrawList(scene, list, @intCast(width), @intCast(height));
    try executeDrawList(list, renderer, window);
    counters.recordDrawList(list.stats);
    const ended_ticks = SDL_GetPerformanceCounter();
    counters.recordPresent(
        performanceTicksToNanos(ended_ticks - started_ticks),
        performanceTicksToNanos(ended_ticks),
    );
}

fn presentFacts(
    snapshot: FrameFacts,
    list: *renderer_policy.DrawList,
    renderer: *SDL_Renderer,
    window: *SDL_Window,
    gate: *renderer_policy.FrameGate,
    counters: *renderer_policy.FrameCounters,
) !void {
    var width: c_int = 0;
    var height: c_int = 0;
    SDL_GetWindowSize(window, &width, &height);
    if (!gate.shouldPresent(@intCast(width), @intCast(height))) {
        counters.recordSkipped();
        return;
    }
    const started_ticks = SDL_GetPerformanceCounter();
    try buildFactsDrawList(snapshot, list, @intCast(width), @intCast(height));
    try executeDrawList(list, renderer, window);
    counters.recordDrawList(list.stats);
    const ended_ticks = SDL_GetPerformanceCounter();
    counters.recordPresent(
        performanceTicksToNanos(ended_ticks - started_ticks),
        performanceTicksToNanos(ended_ticks),
    );
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
        } else if (std.mem.startsWith(u8, arg, "--renderer=")) {
            config.renderer_request = arg["--renderer=".len..];
        } else if (std.mem.eql(u8, arg, "--renderer")) {
            config.renderer_request = args.next() orelse return error.MissingRendererPolicy;
        } else if (std.mem.startsWith(u8, arg, "--present=")) {
            config.present_mode = arg["--present=".len..];
        } else if (std.mem.eql(u8, arg, "--present")) {
            config.present_mode = args.next() orelse return error.MissingPresentMode;
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
        } else if (std.mem.eql(u8, arg, "--emacs-interactive")) {
            config.mode = .emacs_interactive;
        } else if (std.mem.eql(u8, arg, "--emacs-interactive-smoke")) {
            config.mode = .emacs_interactive;
            config.synthetic_interactive = true;
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
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-sequence-smoke")) {
            config.mode = .emacs_epxl_sequence;
            config.auto_input = "X";
            config.auto_key = .backspace;
        } else if (std.mem.eql(u8, arg, "--input-translate-smoke")) {
            config.mode = .input_translation;
        } else if (std.mem.eql(u8, arg, "--facts")) {
            try setString(gpa, &config.facts_path, args.next() orelse return error.MissingFactsPath);
        } else {
            std.debug.print("sdl3-emacs-smoke: unknown argument {s}\n", .{arg});
            return error.UnknownArgument;
        }
    }

    if ((config.mode == .replay or config.mode == .live) and config.replay_path.len == 0) return error.MissingReplayPath;
    if (config.auto_quit_ms > 10_000) return error.AutoQuitMsOutOfRange;
    if (renderer_policy.parseRequest(config.renderer_request) == null) return error.UnknownRendererPolicy;
    if (renderer_policy.parsePresentMode(config.present_mode) == null) return error.UnknownPresentMode;

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

    if (config.mode == .input_translation) {
        try runInputTranslationSmoke();
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

    if (config.mode == .emacs_interactive) {
        if (config.emacs_path.len == 0) return error.MissingEmacsPath;
        if (config.module_path.len == 0) return error.MissingModulePath;
        if (config.facts_path.len == 0) return error.MissingFactsPath;
        try runEmacsInteractive(gpa, io, &config);
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
        const selected_renderer = try createRenderer(gpa, window, config.renderer_request, config.present_mode);
        defer destroyRenderer(selected_renderer);
        const renderer = selected_renderer.handle;
        std.debug.print("sdl3-emacs-smoke: renderer {s} tier={s} present={s}\n", .{
            selected_renderer.name,
            @tagName(selected_renderer.tier),
            config.present_mode,
        });

        var frame_gate: renderer_policy.FrameGate = .{};
        var frame_counters: renderer_policy.FrameCounters = .{};
        var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
        defer draw_list.deinit();

        var shared = SharedFacts{};
        var last_version: u64 = 0;
        var latest: FrameFacts = .{ .frame_width = 800, .frame_height = 600, .window_width = 780, .window_height = 560 };
        var snapshot_scene: ?frontend.Scene = null;
        defer if (snapshot_scene) |*scene| scene.deinit();
        const started_ticks = SDL_GetTicks();
        while (SDL_GetTicks() - started_ticks < config.auto_quit_ms) {
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
                frame_gate.dirty = true;
            }
            var quit = false;
            var event: SDL_Event = undefined;
            while (SDL_PollEvent(&event)) {
                if (event.type == SDL_EVENT_QUIT) {
                    quit = true;
                } else {
                    frame_gate.dirty = true;
                }
            }
            if (quit) break;
            if (snapshot_scene) |*scene| {
                try presentScene(scene, &draw_list, renderer, window, &frame_gate, &frame_counters);
            } else {
                try presentFacts(latest, &draw_list, renderer, window, &frame_gate, &frame_counters);
            }

            SDL_Delay(50);
        }
        if (last_version == 0) return error.NoEmacsFacts;
        std.debug.print(
            "sdl3-emacs-smoke: observed {d} public fact snapshot(s); present={d} skipped={d} frame={d}ns draws={d} clears={d} fills={d} text={d}; lifecycle OK\n",
            .{
                last_version,
                frame_counters.presented_frames,
                frame_counters.skipped_frames,
                frame_counters.frame_path_total_ns,
                frame_counters.draw_commands_total,
                frame_counters.clear_commands_total,
                frame_counters.fill_commands_total,
                frame_counters.text_commands_total,
            },
        );
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
        .input_translation => unreachable,
        .emacs_interactive => unreachable,
        .emacs_epxl => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_reconnect => try runEmacsEpxlSession(gpa, io, &config, 2),
        .emacs_epxl_input => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_edit => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_sequence => try runEmacsEpxlSession(gpa, io, &config, 1),
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
    if (config.mode == .emacs_epxl_sequence) {
        const applied = scene.text.items.len >= 2 and
            std.mem.eql(u8, scene.text.items[0].bytes, "XEmacs Proto-UI") and
            std.mem.eql(u8, scene.text.items[1].bytes, "visible ASCII text") and
            scene.cursor != null and scene.cursor.?.x == 144 and scene.cursor.?.y == 1;
        if (!applied) return error.SequenceInputNotApplied;
    }
    if (scene.stats.frame_updates == 0) return error.NoFrameUpdate;
    if (scene.frame_header == null) return error.NoFrameHeader;

    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();

    const window = SDL_CreateWindow("Emacs Proto-UI EUP Replay", 960, 600, SDL_WINDOW_RESIZABLE) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);

    const selected_renderer = try createRenderer(gpa, window, config.renderer_request, config.present_mode);
    defer destroyRenderer(selected_renderer);
    const renderer = selected_renderer.handle;
    std.debug.print("sdl3-eup-smoke: renderer {s} tier={s} present={s}\n", .{
        selected_renderer.name,
        @tagName(selected_renderer.tier),
        config.present_mode,
    });

    std.debug.print("sdl3-eup-smoke: applied {d} update(s), {d} window(s), {d} row(s); auto quit in {d}ms\n", .{
        scene.stats.frame_updates,
        scene.windows.items.len,
        scene.rows.items.len,
        config.auto_quit_ms,
    });

    var frame_gate: renderer_policy.FrameGate = .{};
    var frame_counters: renderer_policy.FrameCounters = .{};
    var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
    defer draw_list.deinit();

    try presentScene(&scene, &draw_list, renderer, window, &frame_gate, &frame_counters);

    var quit = false;
    const started_ticks = SDL_GetTicks();
    while (!quit and SDL_GetTicks() - started_ticks < config.auto_quit_ms) {
        var event: SDL_Event = undefined;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) {
                quit = true;
            } else {
                frame_gate.dirty = true;
            }
        }
        try presentScene(&scene, &draw_list, renderer, window, &frame_gate, &frame_counters);
        SDL_Delay(10);
    }

    std.debug.print(
        "sdl3-eup-smoke: present={d} skipped={d} frame={d}ns draws={d} clears={d} fills={d} text={d} last_present={d}ns; lifecycle OK ({s})\n",
        .{
            frame_counters.presented_frames,
            frame_counters.skipped_frames,
            frame_counters.frame_path_total_ns,
            frame_counters.draw_commands_total,
            frame_counters.clear_commands_total,
            frame_counters.fill_commands_total,
            frame_counters.text_commands_total,
            frame_counters.present_last_ns,
            if (quit) "closed by quit event" else "auto timeout",
        },
    );
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
