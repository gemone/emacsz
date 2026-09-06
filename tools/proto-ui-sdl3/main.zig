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
const SDL_EVENT_RENDER_TARGETS_RESET: c_uint = 0x2000;
const SDL_EVENT_RENDER_DEVICE_RESET: c_uint = 0x2001;
const SDL_EVENT_RENDER_DEVICE_LOST: c_uint = 0x2002;
const SDL_EVENT_KEY_DOWN: c_uint = 0x300;
const SDL_EVENT_TEXT_INPUT: c_uint = 0x303;
const SDL_EVENT_MOUSE_MOTION: c_uint = 0x400;
const SDL_EVENT_MOUSE_BUTTON_DOWN: c_uint = 0x401;
const SDL_EVENT_MOUSE_BUTTON_UP: c_uint = 0x402;
const SDL_EVENT_MOUSE_WHEEL: c_uint = 0x403;
const SDL_BUTTON_LMASK: u32 = 1;
const SDL_MOUSEWHEEL_NORMAL: u32 = 0;

const SDL_Window = opaque {};
const SDL_Renderer = opaque {};
const SDL_Texture = opaque {};

const SDL_PixelFormat = c_uint;
const SDL_TextureAccess = c_int;
const SDL_ScaleMode = c_int;
const SDL_PIXELFORMAT_RGBA8888: SDL_PixelFormat = 0x1646_2004;
const SDL_TEXTUREACCESS_TARGET: SDL_TextureAccess = 2;
const SDL_SCALEMODE_NEAREST: SDL_ScaleMode = 1;

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
extern fn SDL_SetRenderClipRect(renderer: *SDL_Renderer, rect: ?*const SDL_Rect) bool;
extern fn SDL_RenderDebugText(renderer: *SDL_Renderer, x: f32, y: f32, text: [*:0]const u8) bool;
extern fn SDL_CreateTexture(
    renderer: *SDL_Renderer,
    format: SDL_PixelFormat,
    access: SDL_TextureAccess,
    width: c_int,
    height: c_int,
) ?*SDL_Texture;
extern fn SDL_DestroyTexture(texture: *SDL_Texture) void;
extern fn SDL_SetTextureScaleMode(texture: *SDL_Texture, scale_mode: SDL_ScaleMode) bool;
extern fn SDL_SetRenderTarget(renderer: *SDL_Renderer, texture: ?*SDL_Texture) bool;
extern fn SDL_RenderTexture(
    renderer: *SDL_Renderer,
    texture: *SDL_Texture,
    source: ?*const SDL_FRect,
    destination: ?*const SDL_FRect,
) bool;
extern fn SDL_PollEvent(event: *SDL_Event) bool;
extern fn SDL_PushEvent(event: *SDL_Event) bool;
extern fn SDL_Delay(ms: c_uint) void;
extern fn SDL_StartTextInput(window: *SDL_Window) bool;
extern fn SDL_GetClipboardText() [*c]u8;
extern fn SDL_SetClipboardText(text: [*:0]const u8) bool;
extern fn SDL_free(mem: ?*anyopaque) void;
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

const SDL_MouseMotionEvent = extern struct {
    type: c_uint,
    reserved: c_uint,
    timestamp: u64,
    window_id: c_uint,
    which: c_uint,
    state: u32,
    x: f32,
    y: f32,
    xrel: f32,
    yrel: f32,
};

const SDL_MouseButtonEvent = extern struct {
    type: c_uint,
    reserved: c_uint,
    timestamp: u64,
    window_id: c_uint,
    which: c_uint,
    button: u8,
    down: bool,
    clicks: u8,
    padding: u8,
    x: f32,
    y: f32,
};

const SDL_MouseWheelEvent = extern struct {
    type: c_uint,
    reserved: c_uint,
    timestamp: u64,
    window_id: c_uint,
    which: c_uint,
    x: f32,
    y: f32,
    direction: u32,
    mouse_x: f32,
    mouse_y: f32,
    integer_x: i32,
    integer_y: i32,
};

const SDL_Event = extern union {
    type: c_uint,
    key: SDL_KeyboardEvent,
    text: SDL_TextInputEvent,
    motion: SDL_MouseMotionEvent,
    button: SDL_MouseButtonEvent,
    wheel: SDL_MouseWheelEvent,
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

fn mouseMotionEvent(x: f32, y: f32, state: u32) SDL_Event {
    var event: SDL_Event = undefined;
    event.motion = .{
        .type = SDL_EVENT_MOUSE_MOTION,
        .reserved = 0,
        .timestamp = 0,
        .window_id = 0,
        .which = 0,
        .state = state,
        .x = x,
        .y = y,
        .xrel = 0,
        .yrel = 0,
    };
    return event;
}

fn mouseButtonEvent(x: f32, y: f32, event_type: c_uint, down: bool) SDL_Event {
    var event: SDL_Event = undefined;
    event.button = .{
        .type = event_type,
        .reserved = 0,
        .timestamp = 0,
        .window_id = 0,
        .which = 0,
        .button = 1,
        .down = down,
        .clicks = 1,
        .padding = 0,
        .x = x,
        .y = y,
    };
    return event;
}

fn wheelEvent(y: i32) SDL_Event {
    var event: SDL_Event = undefined;
    event.wheel = .{
        .type = SDL_EVENT_MOUSE_WHEEL,
        .reserved = 0,
        .timestamp = 0,
        .window_id = 0,
        .which = 0,
        .x = 0,
        .y = @floatFromInt(y),
        .direction = 0,
        .mouse_x = 0,
        .mouse_y = 0,
        .integer_x = 0,
        .integer_y = y,
    };
    return event;
}

fn queueClipboardText(queue: anytype) !bool {
    const text: ?[*:0]u8 = SDL_GetClipboardText();
    defer if (text) |owned| SDL_free(owned);
    const source: ?[*:0]const u8 = if (text) |owned| owned else null;
    const translated = input_policy.translateText(source) orelse return false;
    try queue.pushText(translated.bytes());
    return true;
}

fn setPlatformClipboard(bytes: []const u8) !void {
    if (!input_policy.validClipboardText(bytes)) return error.ClipboardTextNotAccepted;
    var text: [121]u8 = undefined;
    @memcpy(text[0..bytes.len], bytes);
    text[bytes.len] = 0;
    if (!SDL_SetClipboardText(@ptrCast(&text))) return sdlFail("SDL_SetClipboardText");
}

fn runClipboardSmoke() !void {
    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    if (!SDL_SetClipboardText("XY")) return sdlFail("SDL_SetClipboardText");
    var queue: input_policy.Queue = .{};
    if (!try queueClipboardText(&queue)) return error.ClipboardTextNotAccepted;
    if (queue.length != 1) return error.ClipboardQueueCount;
    std.debug.print("sdl3-clipboard-smoke: captured bounded clipboard text; queue=1; lifecycle OK\n", .{});
}

const SDL_Rect = extern struct {
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
};

const SDL_FRect = extern struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

const Mode = enum { replay, live, publisher, emacs, facts_publisher, emacs_epxl, emacs_epxl_reconnect, emacs_epxl_recovery, emacs_epxl_interactive, emacs_epxl_input, emacs_epxl_edit, emacs_epxl_sequence, input_translation, emacs_interactive, clipboard };

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
    synthetic_copy: bool = false,
    drop_first_input_ack: bool = false,
    interactive_publisher: bool = false,
    interactive_synthetic: bool = false,
    synthetic_pointer: bool = false,
    synthetic_wheel: bool = false,
    synthetic_viewport: bool = false,
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
                .copy => "copy",
                .backspace => "backspace",
                .cursor_left => "cursor-left",
                .cursor_right => "cursor-right",
                .cursor_up => "cursor-up",
                .cursor_down => "cursor-down",
            };
            try writeActionArtifact(gpa, io, path, "key", action_name);
        },
        .text => |text| try writeActionArtifact(gpa, io, path, "text", text.bytes()),
        // Pointer/wheel intents are intentionally EPXL-only; the local fallback
        // does not pretend to support them.
        .pointer => {},
        .wheel => {},
    }
}

fn runEmacsInteractive(gpa: std.mem.Allocator, io: std.Io, config: *const Config) !void {
    const current_dir = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(current_dir);
    const facts_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ current_dir, config.facts_path });
    defer gpa.free(facts_path);
    const input_path = try std.fmt.allocPrint(gpa, "{s}.keys", .{facts_path});
    defer gpa.free(input_path);
    const clipboard_path = try std.fmt.allocPrint(gpa, "{s}.clipboard", .{facts_path});
    defer gpa.free(clipboard_path);
    if (std.fs.path.dirname(facts_path)) |directory| {
        try std.Io.Dir.cwd().createDirPath(io, directory);
    }
    _ = std.Io.Dir.cwd().deleteFile(io, facts_path) catch {};
    _ = std.Io.Dir.cwd().deleteFile(io, input_path) catch {};
    _ = std.Io.Dir.cwd().deleteFile(io, clipboard_path) catch {};

    const eval = try std.fmt.allocPrint(gpa,
        \\(progn
        \\  (module-load (expand-file-name "{s}"))
        \\  (let* ((frame (selected-frame))
        \\         (window (selected-window))
        \\         (path (expand-file-name "{s}"))
        \\         (input-path (expand-file-name "{s}"))
        \\         (clipboard-path (expand-file-name "{s}"))
        \\         (buffer (window-buffer window))
        \\         (text "")
        \\         (lines [])
        \\         (point (point-min))
        \\         (cursor (list :line 1 :column 0))
        \\         (viewport-start-line 1)
        \\         (viewport-line-count 0)
        \\         (facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))))
        \\    (set-frame-size frame 240 30)
        \\    (with-current-buffer buffer (erase-buffer) (insert "Emacs Proto-UI\nvisible ASCII") (set-window-point window (point)) (redisplay))
        \\    (while t
        \\      (when (file-readable-p input-path)
        \\        (let ((action (split-string (with-temp-buffer (insert-file-contents input-path) (buffer-string)) "\n" t)))
        \\          (when (= (length action) 2)
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
        \\              ((and (string= (nth 0 action) "key") (string= (nth 1 action) "copy"))
        \\               (with-current-buffer buffer (let* ((copy-end (progn (goto-char (point-min)) (line-end-position))) (copy-length (<= (- copy-end (point-min)) 120)) (copy-ascii (save-excursion (let ((ascii t) (pos (point-min))) (while (< pos copy-end) (let ((ch (char-after pos))) (when (or (< ch 32) (> ch 126)) (setq ascii nil) (setq pos copy-end))) (setq pos (+ pos 1))) ascii))) (copy-text (and copy-length copy-ascii (buffer-substring-no-properties (point-min) copy-end)))) (when copy-text (kill-ring-save (point-min) copy-end) (with-temp-file clipboard-path (insert copy-text)) (set-window-point window (point)) (redisplay)))))
        \\              ((and (string= (nth 0 action) "text") (> (length (nth 1 action)) 0))
        \\               (with-current-buffer buffer (insert (nth 1 action)) (set-window-point window (point)) (redisplay))))))
        \\        (delete-file input-path))
        \\      (setq text (with-current-buffer buffer (buffer-substring-no-properties (point-min) (point-max))))
        \\      (setq lines (split-string text "\n"))
        \\      (setq viewport-start-line (line-number-at-pos (window-start window)))
        \\      (setq viewport-line-count (length lines))
        \\      (setq point (with-current-buffer buffer (point)))
        \\      (setq cursor (with-current-buffer buffer (save-excursion (goto-char point) (list :line (line-number-at-pos point) :column (current-column)))))
        \\      (setq facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist)))
        \\      (with-temp-file path (insert (json-serialize (list :frame_width (plist-get facts :frame_width) :frame_height (plist-get facts :frame_height) :window_width (plist-get facts :window_width) :window_height (plist-get facts :window_height) :text (vconcat lines) :window_start_line viewport-start-line :window_visible_lines viewport-line-count :cursor cursor))))
        \\      (sit-for 0.05)))))))
    , .{ config.module_path, facts_path, input_path, clipboard_path });
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
    var copy_applied = false;
    var last_delivery_version: ?u64 = null;

    if (config.synthetic_copy) {
        try input_queue.pushKey(.{ .action = .copy });
    }

    if (config.synthetic_interactive) {
        try input_queue.pushText("XY");
    }

    var quit = false;
    const smoke_mode = config.synthetic_interactive or config.synthetic_copy;
    const started_ticks = SDL_GetTicks();
    while (!quit and (!smoke_mode or SDL_GetTicks() - started_ticks < config.auto_quit_ms)) {
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

        const clipboard_bytes = std.Io.Dir.cwd().readFileAlloc(io, clipboard_path, gpa, .limited(121)) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (clipboard_bytes) |bytes| {
            defer gpa.free(bytes);
            if (input_policy.validClipboardText(bytes) and std.mem.eql(u8, bytes, "Emacs Proto-UI")) {
                var text: [121]u8 = undefined;
                @memcpy(text[0..bytes.len], bytes);
                text[bytes.len] = 0;
                if (!SDL_SetClipboardText(@ptrCast(&text))) return sdlFail("SDL_SetClipboardText");
                _ = std.Io.Dir.cwd().deleteFile(io, clipboard_path) catch {};
                copy_applied = true;
                frame_gate.dirty = true;
            }
        }

        var event: SDL_Event = undefined;
        while (SDL_PollEvent(&event)) {
            switch (event.type) {
                SDL_EVENT_QUIT => quit = true,
                SDL_EVENT_KEY_DOWN => {
                    if (input_policy.isPasteShortcut(event.key.scancode, event.key.down, event.key.repeat, event.key.modifiers)) {
                        if (try queueClipboardText(&input_queue)) frame_gate.dirty = true;
                    } else if (input_policy.isCopyShortcut(event.key.scancode, event.key.down, event.key.repeat, event.key.modifiers)) {
                        try input_queue.pushKey(.{ .action = .copy });
                        frame_gate.dirty = true;
                    } else if (input_policy.translateKey(event.key.scancode, event.key.down, event.key.repeat, event.key.modifiers)) |key| {
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

    if (config.synthetic_copy and !copy_applied) return error.ClipboardCopyNotApplied;
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
    const clipboard_path = try std.fmt.allocPrint(gpa, "{s}.clipboard", .{config.facts_path});
    defer gpa.free(clipboard_path);
    _ = std.Io.Dir.cwd().deleteFile(io, ack_path) catch {};
    _ = std.Io.Dir.cwd().deleteFile(io, clipboard_path) catch {};
    _ = std.Io.Dir.cwd().deleteFile(io, config.endpoint) catch {};
    const eval = try std.fmt.allocPrint(
        gpa,
        "(progn (module-load (expand-file-name (format \"%s\" (format \"{s}\")))) (let* ((frame (selected-frame)) (window (selected-window)) (path (expand-file-name (format \"%s\" (format \"{s}\")))) (input-path (expand-file-name (format \"%s\" (format \"{s}\")))) (clipboard-path (expand-file-name (format \"%s\" (format \"{s}\")))) (buffer (window-buffer window)) (facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))) (text (with-current-buffer buffer (buffer-substring-no-properties (point-min) (point-max)))) (lines (split-string text \"\\n\")) (point (with-current-buffer buffer (window-point window))) (cursor (with-current-buffer buffer (save-excursion (goto-char point) (list :line (line-number-at-pos point) :column (current-column))))) (viewport-start (window-start window)) (viewport-end (window-end window t)) (viewport-start-line 1) (viewport-line-count 0) (viewport-cursor-line 1)) (with-current-buffer buffer (erase-buffer) (insert \"Emacs Proto-UI\\nvisible ASCII textZ\") (dotimes (i 28) (insert (format \"\\nline %02d\" i))) (redisplay)) (setq viewport-start (window-start window)) (setq viewport-end (window-end window t)) (setq viewport-start-line (line-number-at-pos viewport-start)) (setq viewport-line-count (count-lines viewport-start viewport-end)) (setq text (buffer-substring-no-properties viewport-start viewport-end)) (setq lines (split-string text \"\\n\" t)) (setq point (window-point window)) (setq viewport-cursor-line (min 15 (max 1 (+ 1 (- (line-number-at-pos point) viewport-start-line))))) (setq cursor (with-current-buffer buffer (save-excursion (goto-char point) (list :line viewport-cursor-line :column (current-column))))) (setq facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))) (with-temp-file path (insert (json-serialize (list :frame_width (plist-get facts :frame_width) :frame_height (plist-get facts :frame_height) :window_width (plist-get facts :window_width) :window_height (plist-get facts :window_height) :text (vconcat lines) :cursor cursor :window_start_line viewport-start-line :window_visible_lines viewport-line-count)))) (sit-for 0.2) (set-frame-size frame 240 30) (while t (when (file-readable-p input-path) (let ((action (split-string (with-temp-buffer (insert-file-contents input-path) (buffer-string)) \"\\n\" t))) (cond ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"backspace\")) (with-current-buffer buffer (goto-char (point-max)) (delete-char -1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"cursor-left\")) (with-current-buffer buffer (backward-char 1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"cursor-right\")) (with-current-buffer buffer (forward-char 1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"cursor-up\")) (with-current-buffer buffer (previous-line 1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"cursor-down\")) (with-current-buffer buffer (next-line 1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"copy\")) (with-current-buffer buffer (let* ((copy-end (progn (goto-char (point-min)) (line-end-position))) (copy-length (<= (- copy-end (point-min)) 120)) (copy-ascii (save-excursion (let ((ascii t) (pos (point-min))) (while (< pos copy-end) (let ((ch (char-after pos))) (when (or (< ch 32) (> ch 126)) (setq ascii nil) (setq pos copy-end))) (setq pos (+ pos 1))) ascii))) (copy-text (and copy-length copy-ascii (buffer-substring-no-properties (point-min) copy-end)))) (when copy-text (kill-ring-save (point-min) copy-end) (with-temp-file clipboard-path (insert copy-text)) (set-window-point window (point)) (redisplay))))) ((and (= (length action) 3) (string= (nth 1 action) \"pointer\")) (let* ((pointer (split-string (nth 2 action) \" \" t)) (pointer-phase (nth 0 pointer)) (pointer-x (string-to-number (nth 1 pointer))) (pointer-y (string-to-number (nth 2 pointer)))) (when (and (= (length pointer) 3) (or (string= pointer-phase \"press\") (string= pointer-phase \"release\"))) (condition-case nil (let ((point (posn-point (posn-at-x-y pointer-x pointer-y window)))) (when point (with-current-buffer buffer (goto-char point) (redisplay)))) (error nil))))) ((and (= (length action) 3) (string= (nth 1 action) \"wheel\")) (let ((wheel (split-string (nth 2 action) \" \" t))) (when (= (length wheel) 2) (with-current-buffer buffer (condition-case nil (if (string= (nth 0 wheel) \"down\") (scroll-up (string-to-number (nth 1 wheel))) (scroll-down (string-to-number (nth 1 wheel)))) (error nil)))))) ((and (= (length action) 3) (string= (nth 1 action) \"text\") (> (length (nth 2 action)) 0)) (with-current-buffer buffer (goto-char (point-min)) (insert (nth 2 action)) (set-window-point window (point)) (redisplay)))) (with-temp-file (concat input-path \".ack\") (insert (nth 0 action))) (delete-file input-path))) (setq viewport-start (window-start window)) (setq viewport-end (window-end window t)) (setq viewport-start-line (line-number-at-pos viewport-start)) (setq viewport-line-count (count-lines viewport-start viewport-end)) (setq text (buffer-substring-no-properties viewport-start viewport-end)) (setq lines (split-string text \"\\n\" t)) (setq point (window-point window)) (setq viewport-cursor-line (min 15 (max 1 (+ 1 (- (line-number-at-pos point) viewport-start-line))))) (setq cursor (with-current-buffer buffer (save-excursion (goto-char point) (list :line viewport-cursor-line :column (current-column))))) (setq facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))) (with-temp-file path (insert (json-serialize (list :frame_width (plist-get facts :frame_width) :frame_height (plist-get facts :frame_height) :window_width (plist-get facts :window_width) :window_height (plist-get facts :window_height) :text (vconcat lines) :cursor cursor :window_start_line viewport-start-line :window_visible_lines viewport-line-count)))) (sit-for 0.1))))",
        .{ config.module_path, config.facts_path, input_path, clipboard_path },
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
    const publish_duration = if (config.interactive_publisher)
        config.auto_quit_ms
    else
        @max(100, config.auto_quit_ms / 2);

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
        try sendSnapshotMessages(gpa, published.?.facts, published.?.text.lines, published.?.cursor, published.?.viewport, &scene, &acks, io, &reader, &writer, input_path, &input_sequence);
        const complete_sequence = scene.next_sequence.? - 1;
        try live.writeControl(&writer.interface, .{ .kind = .resync_complete, .sequence = complete_sequence });
        try writer.interface.flush();

        if (session_index + 1 < @max(1, config.resync_sessions)) continue;
        var waited_ms: u32 = 0;
        var heartbeat_ms: u32 = 0;
        var heartbeat_due = false;
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
                heartbeat_ms += 20;
                continue;
            };
            if (published) |previous| {
                if (previous.eql(next)) {
                    next.deinit(gpa);
                    if (config.interactive_publisher) heartbeat_due = true;
                } else {
                    if (published) |*old| old.deinit(gpa);
                    published = next;
                    heartbeat_due = true;
                }
            }
            if (heartbeat_due and (!config.interactive_publisher or heartbeat_ms >= 100)) {
                var change_acks = live.AckTracker.init(1);
                sendSnapshotMessages(gpa, published.?.facts, published.?.text.lines, published.?.cursor, published.?.viewport, &scene, &change_acks, io, &reader, &writer, input_path, &input_sequence) catch |err| {
                    // The interactive client intentionally closes at its smoke
                    // deadline; stop the healthy publisher instead of failing.
                    if (config.interactive_publisher and
                        (err == error.WriteFailed or err == error.SocketUnconnected)) break;
                    return err;
                };
                heartbeat_due = false;
                heartbeat_ms = 0;
            }
            try io.sleep(.fromMilliseconds(20), .awake);
            waited_ms += 20;
            heartbeat_ms += 20;
        }
    }
    if (scene.stats.frame_updates == 0) return error.NoEmacsFacts;
}

fn readControlExact(reader: anytype) !live.Control {
    var bytes: [live.control_size]u8 = undefined;
    try reader.interface.readSliceAll(&bytes);
    return live.decodeControl(&bytes);
}

const DeliveryOutcome = union(enum) {
    idle,
    ack_lost: input_policy.DeliveryJournal.Sent,
    delivered: input_policy.DeliveryJournal.Sent,
};

fn sendDeliveryEvent(
    gpa: std.mem.Allocator,
    journal: *input_policy.DeliveryJournal,
    config: *const Config,
    writer: anytype,
    reader: anytype,
    envelope: protocol.Envelope,
) !DeliveryOutcome {
    const inject_ack_loss = config.drop_first_input_ack and
        journal.pending == null and journal.attempts == 0 and journal.queue.length > 0;
    const sent = (try journal.take()) orelse return .idle;
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    const message_type: u16 = switch (sent.event) {
        .text => |text| blk: {
            try frontend.encodeTextInput(gpa, .{ .text = text.bytes() }, &payload);
            break :blk protocol.Message.text_input;
        },
        .key => |key| blk: {
            try frontend.encodeKeyEvent(gpa, key, &payload);
            break :blk protocol.Message.key_event;
        },
        .pointer => |pointer| blk: {
            try frontend.encodePointerInput(gpa, pointer, &payload);
            break :blk protocol.Message.pointer_event;
        },
        .wheel => |wheel| blk: {
            try frontend.encodeWheelInput(gpa, wheel, &payload);
            break :blk protocol.Message.wheel_event;
        },
    };
    var input_message: std.ArrayList(u8) = .empty;
    defer input_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.requires_ack,
        .message_type = message_type,
        .sequence = sent.sequence,
        .ack_sequence = 0,
        .session_id = envelope.session_id,
        .frame_id = envelope.frame_id,
        .timestamp_ns = 1,
    }, payload.items, &input_message);
    try live.writeFrame(&writer.interface, input_message.items);
    try writer.interface.flush();
    if (inject_ack_loss) {
        // The wire ACK is deliberately discarded before it reaches the
        // delivery journal, exercising reconnect retry without corrupting the
        // remaining resync handshake.
        _ = try readControlExact(reader);
        return .{ .ack_lost = sent };
    }
    const input_ack = try readControlExact(reader);
    if (input_ack.kind != .ack or !journal.acknowledge(input_ack.sequence)) return error.ExpectedInputAck;
    return .{ .delivered = sent };
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
        // Emacs replaces this non-atomic Lisp artifact in place. A torn or
        // stale payload is retryable; a valid ACK for this sequence must still
        // arrive before the bounded deadline.
        if (!input_policy.validApplyAck(bytes, sequence)) {
            try io.sleep(.fromMilliseconds(10), .awake);
            continue;
        }
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
                const is_pointer = payload.envelope.message_type == protocol.Message.pointer_event;
                const is_wheel = payload.envelope.message_type == protocol.Message.wheel_event;
                if ((!is_text and !is_key and !is_pointer and !is_wheel) or
                    payload.envelope.flags & protocol.Flags.requires_ack == 0 or
                    payload.envelope.ack_sequence != 0 or
                    payload.envelope.session_id != expected_session_id or
                    payload.envelope.frame_id != expected_frame_id)
                    return error.ExpectedAck;
                if (payload.envelope.sequence + 1 == input_sequence.*) {
                    try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = payload.envelope.sequence });
                    try writer.interface.flush();
                    return;
                }
                if (payload.envelope.sequence != input_sequence.*)
                    return error.InvalidSequence;
                if (is_text) {
                    const input = try frontend.decodeTextInput(payload.bytes);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "text", input.text);
                } else if (is_wheel) {
                    const event = try frontend.decodeWheelInput(payload.bytes);
                    const direction: []const u8 = if (event.y > 0) "down" else "up";
                    const value = try std.fmt.allocPrint(gpa, "{s} {d}", .{ direction, @abs(event.y) });
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "wheel", value);
                } else if (is_pointer) {
                    const event = try frontend.decodePointerInput(payload.bytes);
                    const value = try std.fmt.allocPrint(gpa, "{s} {d} {d}", .{ @tagName(event.phase), event.x, event.y });
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "pointer", value);
                } else {
                    const event = try frontend.decodeKeyEvent(payload.bytes);
                    const action_name: []const u8 = switch (event.action) {
                        .copy => "copy",
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
    viewport: facts.ViewportFacts,
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
    try facts.appendWireSnapshot(gpa, snapshot, text, cursor, viewport, scene, &messages);
    for (messages.items) |message| {
        const envelope = (try protocol.decodeEnvelope(message)).envelope;
        try acks.markSent(envelope.sequence);
        try live.writeFrame(&writer.interface, message);
        try writer.interface.flush();
        try awaitFrameAck(gpa, io, reader, writer, envelope.sequence, input_path, input_sequence, envelope.session_id, envelope.frame_id);
        try acks.ack(envelope.sequence);
    }
}

fn runLiveFrontend(
    gpa: std.mem.Allocator,
    io: std.Io,
    config: *const Config,
    delivery: *input_policy.DeliveryJournal,
) !frontend.Scene {
    const address = try std.Io.net.UnixAddress.init(config.endpoint);
    const clipboard_path = try std.fmt.allocPrint(gpa, "{s}.clipboard", .{config.facts_path});
    defer gpa.free(clipboard_path);
    _ = std.Io.Dir.cwd().deleteFile(io, clipboard_path) catch {};
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
    delivery.beginRetry();

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
        config.mode == .emacs_epxl_recovery or config.mode == .emacs_epxl_input or
        config.mode == .emacs_epxl_edit or config.mode == .emacs_epxl_sequence;
    var scene = frontend.Scene.init(gpa);
    errdefer scene.deinit();
    var resync_complete = false;
    var input_ack_lost = false;
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
            if (envelope.message_type == protocol.Message.frame_update) {
                const outcome = try sendDeliveryEvent(gpa, delivery, config, &writer, &reader, envelope);
                if (outcome == .ack_lost) input_ack_lost = true;
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
        const message = (live.readFrame(&reader.interface, gpa) catch |err| {
            // A publisher closes cleanly after its final fact stream. A
            // peer reset at this boundary is session completion, not scene loss.
            if (resync_complete) break;
            return err;
        }) orelse break;
        defer gpa.free(message);
        const envelope = (try protocol.decodeEnvelope(message)).envelope;
        try scene.apply(message);
        if (envelope.message_type == protocol.Message.frame_update)
            _ = try sendDeliveryEvent(gpa, delivery, config, &writer, &reader, envelope);
        try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = envelope.sequence });
        try writer.interface.flush();
        if (use_resync and !resync_complete) return error.IncompleteResync;
    }
    if (use_resync and !resync_complete) return error.IncompleteResync;
    if (scene.stats.frame_updates == 0) return error.NoFrameUpdate;
    return scene;
}

fn boundedPointerCoordinate(value: f32) ?i32 {
    if (!std.math.isFinite(value)) return null;
    if (value < 0 or value > @as(f32, @floatFromInt(frontend.max_pointer_coordinate))) return null;
    return @intFromFloat(value);
}

fn pollEpxlInteractiveInput(
    delivery: *input_policy.DeliveryJournal,
    config: *const Config,
    retained: *RetainedFrame,
    gate: *renderer_policy.FrameGate,
    dirty: *bool,
) !void {
    var event: SDL_Event = undefined;
    while (SDL_PollEvent(&event)) {
        switch (event.type) {
            SDL_EVENT_QUIT => return error.InteractiveQuit,
            SDL_EVENT_KEY_DOWN => {
                if (input_policy.isPasteShortcut(
                    event.key.scancode,
                    event.key.down,
                    event.key.repeat,
                    event.key.modifiers,
                )) {
                    if (try queueClipboardText(delivery)) dirty.* = true;
                } else if (input_policy.isCopyShortcut(
                    event.key.scancode,
                    event.key.down,
                    event.key.repeat,
                    event.key.modifiers,
                )) {
                    try delivery.pushKey(.{ .action = .copy });
                    dirty.* = true;
                } else if (input_policy.translateKey(
                    event.key.scancode,
                    event.key.down,
                    event.key.repeat,
                    event.key.modifiers,
                )) |key| {
                    try delivery.pushKey(key);
                    dirty.* = true;
                }
            },
            SDL_EVENT_TEXT_INPUT => {
                if (input_policy.translateText(event.text.text)) |text| {
                    try delivery.pushText(text.bytes());
                    dirty.* = true;
                }
            },
            SDL_EVENT_MOUSE_WHEEL => {
                if (config.interactive_synthetic and !config.synthetic_wheel) return;
                if (event.wheel.direction != SDL_MOUSEWHEEL_NORMAL) return;
                if (event.wheel.integer_x != 0 or event.wheel.x != 0) return;
                const y = event.wheel.integer_y;
                if (y != 0 and @abs(y) <= frontend.max_wheel_ticks and
                    event.wheel.y == @as(f32, @floatFromInt(y)))
                {
                    try delivery.pushWheel(.{ .y = @intCast(y) });
                    dirty.* = true;
                }
            },
            SDL_EVENT_MOUSE_MOTION => {
                if (config.interactive_synthetic and !config.synthetic_pointer) return;
                const dragging = event.motion.state == SDL_BUTTON_LMASK;
                if (event.motion.state != 0 and !dragging) return;
                if (dragging != delivery.pointer_active) return;
                const x = boundedPointerCoordinate(event.motion.x) orelse return;
                const y = boundedPointerCoordinate(event.motion.y) orelse return;
                if (!dragging and (delivery.pending != null or delivery.queue.length > 0)) return;
                // Idle motion is best-effort and coalesced to the idle boundary.
                // Drag motion is ordered because the left pointer session is active.
                try delivery.pushPointer(.{
                    .phase = .motion,
                    .button = if (dragging) 1 else 0,
                    .x = x,
                    .y = y,
                });
                dirty.* = true;
            },
            SDL_EVENT_MOUSE_BUTTON_DOWN => {
                if (config.interactive_synthetic and !config.synthetic_pointer) return;
                if (!event.button.down) return;
                const x = boundedPointerCoordinate(event.button.x) orelse return;
                const y = boundedPointerCoordinate(event.button.y) orelse return;
                if (event.button.button == 1 and event.button.clicks == 1) {
                    delivery.pushPointer(.{
                        .phase = .press,
                        .button = 1,
                        .x = x,
                        .y = y,
                        .clicks = 1,
                    }) catch |err| switch (err) {
                        error.PointerSessionActive => return,
                        else => return err,
                    };
                    dirty.* = true;
                }
            },
            SDL_EVENT_MOUSE_BUTTON_UP => {
                if (config.interactive_synthetic and !config.synthetic_pointer) return;
                if (event.button.down) return;
                const x = boundedPointerCoordinate(event.button.x) orelse return;
                const y = boundedPointerCoordinate(event.button.y) orelse return;
                if (event.button.button == 1 and event.button.clicks == 1) {
                    delivery.pushPointer(.{
                        .phase = .release,
                        .button = 1,
                        .x = x,
                        .y = y,
                        .clicks = 1,
                    }) catch |err| switch (err) {
                        error.PointerSessionActive => return,
                        else => return err,
                    };
                    dirty.* = true;
                }
            },
            SDL_EVENT_RENDER_TARGETS_RESET, SDL_EVENT_RENDER_DEVICE_RESET, SDL_EVENT_RENDER_DEVICE_LOST => {
                destroyRetainedFrame(retained);
                gate.dirty = true;
            },
            else => {},
        }
    }
}

const debug_text_character_size: i64 = 8;

fn checkedCoordinate(value: i64) ?i32 {
    if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return null;
    return @intCast(value);
}

fn observedTextDamageRect(
    owner: frontend.Window,
    row: frontend.Row,
    text_length: usize,
) ?renderer_policy.TextLineRect {
    const row_x: i64 = @as(i64, owner.x) + row.x;
    const row_y: i64 = @as(i64, owner.y) + row.y;
    const row_right: i64 = row_x + row.width;
    const row_bottom: i64 = row_y + row.visible_height;
    const baseline_offset: i64 = @max(1, @as(i64, row.baseline) - 8);
    const text_x: i64 = row_x + 2;
    const text_y: i64 = row_y + baseline_offset;
    if (text_length > @as(usize, @intCast(std.math.maxInt(i32) / 8))) return null;
    const text_length_i64: i64 = @intCast(text_length);
    const text_width: i64 = text_length_i64 * debug_text_character_size;
    const text_right: i64 = text_x + text_width;
    const text_bottom: i64 = text_y + debug_text_character_size;

    const min_x: i64 = @min(row_x, text_x);
    const min_y: i64 = @min(row_y, text_y);
    const max_right: i64 = @max(row_right, text_right);
    const max_bottom: i64 = @max(row_bottom, text_bottom);
    if (min_x > std.math.maxInt(i32) or max_right < std.math.minInt(i32) or
        min_y > std.math.maxInt(i32) or max_bottom < std.math.minInt(i32)) return null;

    const left = checkedCoordinate(min_x) orelse return null;
    const top = checkedCoordinate(min_y) orelse return null;
    const right = checkedCoordinate(max_right) orelse return null;
    const bottom = checkedCoordinate(max_bottom) orelse return null;
    if (right <= left or bottom <= top) return null;
    return .{ .x = left, .y = top, .width = right - left, .height = bottom - top };
}

fn observeSceneDamage(
    scene: *frontend.Scene,
    gate: *renderer_policy.FrameGate,
    counters: *renderer_policy.FrameCounters,
) renderer_policy.DamageDecision {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (scene.text.items) |line| {
        var row_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &row_bytes, line.row_index, .little);
        hasher.update(&row_bytes);
        hasher.update(line.bytes);
        hasher.update(&.{0});
    }
    var text_hash: [32]u8 = undefined;
    hasher.final(&text_hash);

    var structure_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    if (scene.frame_header) |header| {
        writeStructureField(&structure_hasher, "frame");
        writeStructureI32s(
            &structure_hasher,
            &.{ header.logical_x, header.logical_y, header.logical_width, header.logical_height, header.physical_x, header.physical_y, header.physical_width, header.physical_height },
        );
        writeStructureF32s(&structure_hasher, &.{ header.scale, header.dpi_x, header.dpi_y });
    }
    for (scene.windows.items) |window| {
        writeStructureField(&structure_hasher, "window");
        writeStructureU64s(&structure_hasher, &.{window.id});
        writeStructureI32s(&structure_hasher, &.{ window.x, window.y, window.width, window.height });
    }
    for (scene.rows.items) |row| {
        writeStructureField(&structure_hasher, "row");
        writeStructureU64s(&structure_hasher, &.{row.window_id});
        writeStructureU32s(&structure_hasher, &.{ row.index, row.flags });
        writeStructureI32s(
            &structure_hasher,
            &.{ row.x, row.y, row.width, row.height, row.ascent, row.descent, row.baseline, row.visible_height },
        );
    }
    var structure_hash: [32]u8 = undefined;
    structure_hasher.final(&structure_hash);

    var text_lines = [_]renderer_policy.TextLineObservation{.{}} ** renderer_policy.max_clipped_text_lines;
    var bounded_text_line_count: usize = 0;
    var text_lines_complete = scene.text.items.len <= renderer_policy.max_clipped_text_lines;
    for (scene.text.items) |line| {
        if (bounded_text_line_count == renderer_policy.max_clipped_text_lines) {
            text_lines_complete = false;
            break;
        }
        if (line.row_index >= scene.rows.items.len) {
            text_lines_complete = false;
            break;
        }
        const row = scene.rows.items[line.row_index];
        const owner = findWindowById(scene.windows.items, row.window_id) orelse {
            text_lines_complete = false;
            break;
        };
        const damage_rect = observedTextDamageRect(owner, row, line.bytes.len) orelse {
            text_lines_complete = false;
            break;
        };
        text_lines[bounded_text_line_count] = .{
            .row_index = line.row_index,
            .hash = std.hash.Wyhash.hash(0, line.bytes),
            .rect = damage_rect,
        };
        bounded_text_line_count += 1;
    }

    const cursor_owner = if (scene.cursor) |cursor| findWindowById(scene.windows.items, cursor.window_id) else null;
    const decision = gate.observeScene(.{
        .frame_width = if (scene.frame_header) |header| header.logical_width else 0,
        .frame_height = if (scene.frame_header) |header| header.logical_height else 0,
        .viewport_start_line = if (scene.viewport) |viewport| viewport.start_line else 0,
        .viewport_line_count = if (scene.viewport) |viewport| viewport.line_count else 0,
        .cursor = if (scene.cursor) |cursor| .{
            .window_id = cursor.window_id,
            .owner_x = if (cursor_owner) |owner| owner.x else 0,
            .owner_y = if (cursor_owner) |owner| owner.y else 0,
            .x = cursor.x,
            .y = cursor.y,
            .width = cursor.width,
            .height = cursor.height,
            .kind = cursor.kind,
            .visible = cursor.visible,
            .active = cursor.active,
        } else null,
        .text_hash = text_hash,
        .text_line_count = scene.text.items.len,
        .structure_hash = structure_hash,
        .structure_object_count = scene.windows.items.len + scene.rows.items.len,
        .text_lines = text_lines,
        .bounded_text_line_count = bounded_text_line_count,
        .text_lines_complete = text_lines_complete,
    });
    counters.recordDamage(decision.kind);
    if (decision.kind != .none) gate.dirty = true;
    return decision;
}

fn findWindowById(windows: []const frontend.Window, id: u64) ?frontend.Window {
    for (windows) |window| {
        if (window.id == id) return window;
    }
    return null;
}

fn writeStructureField(hasher: *std.crypto.hash.sha2.Sha256, name: []const u8) void {
    hasher.update(name);
    hasher.update(&.{0});
}

fn writeStructureI32s(hasher: *std.crypto.hash.sha2.Sha256, values: []const i32) void {
    for (values) |value| {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &bytes, value, .little);
        hasher.update(&bytes);
    }
}

fn writeStructureU32s(hasher: *std.crypto.hash.sha2.Sha256, values: []const u32) void {
    for (values) |value| {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, value, .little);
        hasher.update(&bytes);
    }
}

fn writeStructureF32s(hasher: *std.crypto.hash.sha2.Sha256, values: []const f32) void {
    for (values) |value| {
        const bits: u32 = @bitCast(value);
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, bits, .little);
        hasher.update(&bytes);
    }
}

fn writeStructureU64s(hasher: *std.crypto.hash.sha2.Sha256, values: []const u64) void {
    for (values) |value| {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, value, .little);
        hasher.update(&bytes);
    }
}

fn runEpxlInteractiveFrontend(
    gpa: std.mem.Allocator,
    io: std.Io,
    config: *const Config,
    delivery: *input_policy.DeliveryJournal,
) !frontend.Scene {
    const address = try std.Io.net.UnixAddress.init(config.endpoint);
    const clipboard_path = try std.fmt.allocPrint(gpa, "{s}.clipboard", .{config.facts_path});
    defer gpa.free(clipboard_path);
    _ = std.Io.Dir.cwd().deleteFile(io, clipboard_path) catch {};
    var stream: std.Io.net.Stream = undefined;
    var connected = false;
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
    delivery.beginRetry();

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
    var zero_token: live.Token = [_]u8{0} ** live.token_len;
    if (ready.kind != .server_ready or !live.tokenEql(&zero_token, &ready.token))
        return error.InvalidHandshake;

    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow("Emacs Proto-UI EPXL", 960, 600, SDL_WINDOW_RESIZABLE) orelse
        return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);
    const selected_renderer = try createRenderer(gpa, window, config.renderer_request, config.present_mode);
    defer destroyRenderer(selected_renderer);
    var retained_frame: RetainedFrame = .{};
    defer destroyRetainedFrame(&retained_frame);
    if (!SDL_StartTextInput(window)) return sdlFail("SDL_StartTextInput");

    var frame_gate: renderer_policy.FrameGate = .{};
    var frame_counters: renderer_policy.FrameCounters = .{};
    var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
    defer draw_list.deinit();

    var scene = frontend.Scene.init(gpa);
    errdefer scene.deinit();
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
        if (envelope.message_type == protocol.Message.frame_update)
            _ = try sendDeliveryEvent(gpa, delivery, config, &writer, &reader, envelope);
        try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = envelope.sequence });
        try writer.interface.flush();
    }
    const complete = try readControlExact(&reader);
    if (complete.kind != .resync_complete or
        complete.sequence != scene.next_sequence.? - 1) return error.IncompleteResync;

    _ = observeSceneDamage(&scene, &frame_gate, &frame_counters);
    const initial_cursor = scene.cursor;
    const initial_viewport = scene.viewport;
    var input_dirty = false;
    var copy_applied = false;
    var pointer_release_delivered = false;
    var wheel_ticks_delivered: i32 = 0;
    if (config.interactive_synthetic) {
        // Seed the real SDL event queue so headless automation validates the
        // same input translation path as an operator typing in the window.
        var synthetic = textEvent("XY");
        if (!SDL_PushEvent(&synthetic)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_copy) {
        var synthetic = keyboardEvent(input_policy.SDL_SCANCODE_C, true, input_policy.sdl_ctrl_modifiers);
        if (!SDL_PushEvent(&synthetic)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_wheel) {
        var down = wheelEvent(1);
        if (!SDL_PushEvent(&down)) return sdlFail("SDL_PushEvent");
        if (!config.synthetic_viewport) {
            var up = wheelEvent(-1);
            if (!SDL_PushEvent(&up)) return sdlFail("SDL_PushEvent");
        }
    }
    if (config.synthetic_pointer) {
        var idle_motion = mouseMotionEvent(8, 2, 0);
        if (!SDL_PushEvent(&idle_motion)) return sdlFail("SDL_PushEvent");
        var press = mouseButtonEvent(64, 2, SDL_EVENT_MOUSE_BUTTON_DOWN, true);
        if (!SDL_PushEvent(&press)) return sdlFail("SDL_PushEvent");
        var drag_motion = mouseMotionEvent(120, 2, 1);
        if (!SDL_PushEvent(&drag_motion)) return sdlFail("SDL_PushEvent");
        var release = mouseButtonEvent(120, 2, SDL_EVENT_MOUSE_BUTTON_UP, false);
        if (!SDL_PushEvent(&release)) return sdlFail("SDL_PushEvent");
    }
    try pollEpxlInteractiveInput(delivery, config, &retained_frame, &frame_gate, &input_dirty);

    var quit = false;
    const started_ticks = SDL_GetTicks();
    while (!quit and SDL_GetTicks() - started_ticks < config.auto_quit_ms) {
        const message = (live.readFrame(&reader.interface, gpa) catch |err| {
            if (SDL_GetTicks() - started_ticks >= config.auto_quit_ms) break;
            return err;
        }) orelse break;
        defer gpa.free(message);
        const envelope = (try protocol.decodeEnvelope(message)).envelope;
        try scene.apply(message);
        const is_frame_update = envelope.message_type == protocol.Message.frame_update;
        var damage: ?renderer_policy.DamageDecision = null;
        if (is_frame_update) damage = observeSceneDamage(&scene, &frame_gate, &frame_counters);
        if (is_frame_update) {
            const before = delivery.pending == null;
            const outcome = try sendDeliveryEvent(gpa, delivery, config, &writer, &reader, envelope);
            if (before and outcome == .delivered) {
                input_dirty = true;
                switch (outcome.delivered.event) {
                    .pointer => |pointer| if (pointer.phase == .release) {
                        pointer_release_delivered = true;
                    },
                    .wheel => |wheel| wheel_ticks_delivered += @abs(wheel.y),
                    else => {},
                }
            }
        }
        try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = envelope.sequence });
        try writer.interface.flush();
        pollEpxlInteractiveInput(delivery, config, &retained_frame, &frame_gate, &input_dirty) catch |err| switch (err) {
            error.InteractiveQuit => quit = true,
            else => return err,
        };
        const clipboard_bytes = std.Io.Dir.cwd().readFileAlloc(io, clipboard_path, gpa, .limited(121)) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (clipboard_bytes) |bytes| {
            defer gpa.free(bytes);
            const accepted = input_policy.validClipboardText(bytes) and
                (!config.synthetic_copy or std.mem.eql(u8, bytes, "Emacs Proto-UI"));
            if (accepted) {
                try setPlatformClipboard(bytes);
                _ = std.Io.Dir.cwd().deleteFile(io, clipboard_path) catch {};
                copy_applied = true;
                frame_gate.dirty = true;
            }
        }
        if (damage) |decision| {
            try presentSceneDamage(
                &scene,
                &draw_list,
                selected_renderer.handle,
                window,
                &retained_frame,
                &frame_gate,
                &frame_counters,
                decision,
            );
        } else {
            try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters);
        }
    }

    if (scene.stats.frame_updates < 2) return error.UnexpectedFactUpdateCount;
    if (config.interactive_synthetic and !sceneHasText(&scene, "XYEmacs Proto-UI"))
        return error.InteractiveInputNotApplied;
    if (config.synthetic_wheel and !config.synthetic_viewport and wheel_ticks_delivered < 2)
        return error.WheelScrollNotApplied;
    if (config.synthetic_viewport) {
        const moved = scene.viewport != null and
            initial_viewport != null and
            scene.viewport.?.start_line > initial_viewport.?.start_line;
        if (!moved) return error.ViewportDidNotScroll;
    }
    if (config.synthetic_pointer) {
        const applied = pointer_release_delivered and scene.cursor != null and
            (initial_cursor == null or
                scene.cursor.?.x != initial_cursor.?.x or
                scene.cursor.?.y != initial_cursor.?.y);
        if (!applied) return error.PointerDragReleaseNotApplied;
    }
    if (config.synthetic_copy and !copy_applied) return error.ClipboardCopyNotApplied;
    if (config.synthetic_pointer) {
        std.debug.print(
            "sdl3-pointer-smoke: delivered ordered left press/drag/release over EPXL; cursor moved={}\n",
            .{scene.cursor != null and (initial_cursor == null or
                scene.cursor.?.x != initial_cursor.?.x or scene.cursor.?.y != initial_cursor.?.y)},
        );
    }
    std.debug.print(
        "sdl3-epxl-interactive-smoke: delivered SDL input over EPXL; frames={d} present={d} skipped={d} damage=initial:{d}/cursor:{d}/text:{d}/region:{d}/viewport:{d}/unchanged:{d} clipped cursor={d}/text={d}/region={d} fallback cursor={d}/text={d}/region={d} clipped_commands={d}; lifecycle OK\n",
        .{
            scene.stats.frame_updates,
            frame_counters.presented_frames,
            frame_counters.skipped_frames,
            frame_counters.initial_damage_frames,
            frame_counters.cursor_damage_frames,
            frame_counters.text_damage_frames,
            frame_counters.region_damage_frames,
            frame_counters.viewport_damage_frames,
            frame_counters.unchanged_frames,
            frame_counters.cursor_clipped_frames,
            frame_counters.text_clipped_frames,
            frame_counters.region_clipped_frames,
            frame_counters.cursor_full_fallback_frames,
            frame_counters.text_full_fallback_frames,
            frame_counters.region_full_fallback_frames,
            frame_counters.clipped_draw_commands_total,
        },
    );
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
    try list.fillRect(
        .{ .x = 0, .y = 0, .width = @floatFromInt(header.logical_width), .height = @floatFromInt(header.logical_height) },
        .{ .r = 0x18, .g = 0x20, .b = 0x2a },
    );

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
        if (line.row_index >= scene.rows.items.len) return error.InvalidTextRow;
        const row = scene.rows.items[line.row_index];
        const owner = findSceneWindow(scene, row.window_id) orelse continue;
        if (line.bytes.len == 0) continue;
        const text_x: i64 = @as(i64, owner.x) + row.x + 2;
        const baseline_offset: i64 = @max(1, @as(i64, row.baseline) - 8);
        const text_y: i64 = @as(i64, owner.y) + row.y + baseline_offset;
        if (text_x < std.math.minInt(i32) or text_x > std.math.maxInt(i32) or
            text_y < std.math.minInt(i32) or text_y > std.math.maxInt(i32)) return error.InvalidTextGeometry;
        try list.drawText(
            @floatFromInt(text_x),
            @floatFromInt(text_y),
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
        const size = renderer_policy.renderedCursorSize(cursor.width, cursor.height);
        try list.fillRect(.{
            .x = @floatFromInt(owner.x + cursor.x),
            .y = @floatFromInt(owner.y + cursor.y),
            .width = @floatFromInt(size.width),
            .height = @floatFromInt(size.height),
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
    target: ?*SDL_Texture,
    clip: ?renderer_policy.LogicalRect,
) !renderer_policy.DrawStats {
    var output_width: c_int = 0;
    var output_height: c_int = 0;
    SDL_GetWindowSize(window, &output_width, &output_height);
    if (output_width <= 0 or output_height <= 0 or
        list.logical_width <= 0 or list.logical_height <= 0) return error.InvalidOutputGeometry;
    if (target != null and !SDL_SetRenderTarget(renderer, target)) return sdlFail("SDL_SetRenderTarget");

    var executed: renderer_policy.DrawStats = .{};
    var device_clip: SDL_Rect = undefined;
    if (clip) |logical| {
        const x: c_int = @intFromFloat(@max(0, logical.x * @as(f32, @floatFromInt(output_width)) / list.logical_width));
        const y: c_int = @intFromFloat(@max(0, logical.y * @as(f32, @floatFromInt(output_height)) / list.logical_height));
        const right: c_int = @intFromFloat(@min(
            @as(f32, @floatFromInt(output_width)),
            (logical.x + logical.width) * @as(f32, @floatFromInt(output_width)) / list.logical_width,
        ));
        const bottom: c_int = @intFromFloat(@min(
            @as(f32, @floatFromInt(output_height)),
            (logical.y + logical.height) * @as(f32, @floatFromInt(output_height)) / list.logical_height,
        ));
        if (right <= x or bottom <= y) {
            if (target != null and !SDL_SetRenderTarget(renderer, null)) return sdlFail("SDL_SetRenderTarget");
            return executed;
        }
        device_clip = .{ .x = x, .y = y, .w = right - x, .h = bottom - y };
        if (!SDL_SetRenderClipRect(renderer, &device_clip)) return sdlFail("SDL_SetRenderClipRect");
    }

    for (list.commands.items) |command| {
        switch (command) {
            // The retained texture keeps the prior frame, so a cursor-only
            // pass redraws only the old/new cursor union and skips the clear.
            .clear => |color| {
                if (clip != null) continue;
                if (!SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)) return sdlFail("SDL_SetRenderDrawColor");
                if (!SDL_RenderClear(renderer)) return sdlFail("SDL_RenderClear");
                executed.commands += 1;
                executed.clears += 1;
            },
            .fill => |draw| {
                const rect = SDL_Rect{
                    .x = @intFromFloat(draw.rect.x * @as(f32, @floatFromInt(output_width)) / list.logical_width),
                    .y = @intFromFloat(draw.rect.y * @as(f32, @floatFromInt(output_height)) / list.logical_height),
                    .w = @max(1, @as(c_int, @intFromFloat(draw.rect.width * @as(f32, @floatFromInt(output_width)) / list.logical_width))),
                    .h = @max(1, @as(c_int, @intFromFloat(draw.rect.height * @as(f32, @floatFromInt(output_height)) / list.logical_height))),
                };
                if (!SDL_SetRenderDrawColor(renderer, draw.color.r, draw.color.g, draw.color.b, draw.color.a)) return sdlFail("SDL_SetRenderDrawColor");
                if (!SDL_RenderFillRect(renderer, &rect)) return sdlFail("SDL_RenderFillRect");
                executed.commands += 1;
                executed.fills += 1;
            },
            .text => |draw| {
                var text: [121]u8 = undefined;
                @memcpy(text[0..draw.bytes.len], draw.bytes);
                text[draw.bytes.len] = 0;
                if (!SDL_RenderDebugText(
                    renderer,
                    draw.x * @as(f32, @floatFromInt(output_width)) / list.logical_width,
                    draw.y * @as(f32, @floatFromInt(output_height)) / list.logical_height,
                    text[0..draw.bytes.len :0],
                )) return sdlFail("SDL_RenderDebugText");
                executed.commands += 1;
                executed.texts += 1;
            },
        }
    }
    if (clip != null and !SDL_SetRenderClipRect(renderer, null)) return sdlFail("SDL_SetRenderClipRect");
    if (target != null and !SDL_SetRenderTarget(renderer, null)) return sdlFail("SDL_SetRenderTarget");
    return executed;
}

fn presentRetainedOutput(renderer: *SDL_Renderer, texture: *SDL_Texture) !void {
    if (!SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)) return sdlFail("SDL_SetRenderDrawColor");
    if (!SDL_RenderClear(renderer)) return sdlFail("SDL_RenderClear");
    if (!SDL_RenderTexture(renderer, texture, null, null)) return sdlFail("SDL_RenderTexture");
    if (!SDL_RenderPresent(renderer)) return sdlFail("SDL_RenderPresent");
}

const RetainedFrame = struct {
    texture: ?*SDL_Texture = null,
    width: c_int = 0,
    height: c_int = 0,
    primed: bool = false,
};

fn destroyRetainedFrame(frame: *RetainedFrame) void {
    if (frame.texture) |texture| SDL_DestroyTexture(texture);
    frame.* = .{};
}

fn retainedFrameTexture(
    renderer: *SDL_Renderer,
    window: *SDL_Window,
    frame: *RetainedFrame,
) ?*SDL_Texture {
    var width: c_int = 0;
    var height: c_int = 0;
    SDL_GetWindowSize(window, &width, &height);
    if (width <= 0 or height <= 0) return null;
    if (frame.width != width or frame.height != height) destroyRetainedFrame(frame);

    if (frame.texture) |texture| return texture;

    const texture = SDL_CreateTexture(
        renderer,
        SDL_PIXELFORMAT_RGBA8888,
        SDL_TEXTUREACCESS_TARGET,
        width,
        height,
    ) orelse return null;
    if (!SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_NEAREST)) {
        SDL_DestroyTexture(texture);
        return null;
    }
    frame.* = .{ .texture = texture, .width = width, .height = height, .primed = false };
    return texture;
}

fn frameDimensionsRenderable(width: i32, height: i32) bool {
    // f32 coordinate arithmetic is exact through 2^24. Larger protocol frames
    // take the conservative direct path until scaled render coordinates are
    // represented explicitly.
    const precise_f32_limit: i32 = 1 << 24;
    return width >= 0 and height >= 0 and
        width <= precise_f32_limit and height <= precise_f32_limit;
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
    const execution = try executeDrawList(list, renderer, window, null, null);
    if (!SDL_RenderPresent(renderer)) return sdlFail("SDL_RenderPresent");
    counters.recordDrawList(execution);
    const ended_ticks = SDL_GetPerformanceCounter();
    counters.recordPresent(
        performanceTicksToNanos(ended_ticks - started_ticks),
        performanceTicksToNanos(ended_ticks),
    );
}

fn presentSceneDamage(
    scene: *frontend.Scene,
    list: *renderer_policy.DrawList,
    renderer: *SDL_Renderer,
    window: *SDL_Window,
    retained: *RetainedFrame,
    gate: *renderer_policy.FrameGate,
    counters: *renderer_policy.FrameCounters,
    decision: renderer_policy.DamageDecision,
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
    const header = scene.frame_header orelse return error.NoFrameUpdate;
    const renderable = frameDimensionsRenderable(header.logical_width, header.logical_height);
    const texture = if (renderable) retainedFrameTexture(renderer, window, retained) else null;
    const clip: ?renderer_policy.LogicalRect = if (renderable and texture != null and
        retained.primed and (decision.kind == .cursor or decision.kind == .text or decision.kind == .region))
        decision.clip
    else
        null;

    var clipped = false;
    var submitted: u64 = 0;
    var execution: renderer_policy.DrawStats = .{};
    if (texture) |target| {
        if (clip) |rect| {
            execution = try executeDrawList(list, renderer, window, target, rect);
            submitted = execution.commands;
            clipped = submitted != 0;
        }
        if (!clipped) {
            execution = try executeDrawList(list, renderer, window, target, null);
            submitted = execution.commands;
        }
        retained.primed = true;
        try presentRetainedOutput(renderer, target);
    } else {
        execution = try executeDrawList(list, renderer, window, null, null);
        submitted = execution.commands;
        if (!SDL_RenderPresent(renderer)) return sdlFail("SDL_RenderPresent");
        retained.primed = false;
    }
    counters.recordClip(decision.kind, clipped, submitted);
    counters.recordDrawList(execution);
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
    const execution = try executeDrawList(list, renderer, window, null, null);
    if (!SDL_RenderPresent(renderer)) return sdlFail("SDL_RenderPresent");
    counters.recordDrawList(execution);
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
    const auto_quit_arg = try std.fmt.allocPrint(
        gpa,
        "--auto-quit-ms={d}",
        .{if (config.mode == .emacs_epxl_interactive) config.auto_quit_ms + 1000 else 500},
    );
    defer gpa.free(auto_quit_arg);
    config.facts_path = try std.fmt.allocPrint(gpa, "{s}/.zig-cache/proto-ui-epxl-{s}/facts.json", .{ current_dir, suffix });
    try writeTokenFile(io, config.token_path, &config.token);
    config.resync_sessions = sessions;
    var delivery: input_policy.DeliveryJournal = .{};
    if (config.auto_input) |text| try delivery.pushText(text);
    if (config.auto_key) |action| try delivery.pushKey(.{ .action = action });

    const child_argv = if (config.interactive_publisher)
        &[_][]const u8{
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
            auto_quit_arg,
            "--interactive-publisher",
        }
    else
        &[_][]const u8{
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
            auto_quit_arg,
        };
    var child = try std.process.spawn(io, .{
        .argv = child_argv,
    });
    errdefer child.kill(io);
    var loaded: ?frontend.Scene = null;
    errdefer if (loaded != null) loaded.?.deinit();
    if (config.mode == .emacs_epxl_interactive) {
        loaded = try runEpxlInteractiveFrontend(gpa, io, config, &delivery);
    } else {
        for (0..sessions) |session_index| {
            var session = try runLiveFrontend(gpa, io, config, &delivery);
            if (config.drop_first_input_ack and session_index == 0 and delivery.pending != null) {
                // The first session deliberately discarded the ACK event. Discard
                // this scene too so the second authenticated session proves that
                // the original sequence is retried exactly once.
                session.deinit();
                continue;
            }
            if (loaded != null) loaded.?.deinit();
            loaded = session;
            try io.sleep(.fromMilliseconds(100), .awake);
        }
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
            // Real SDL windows now use authenticated EPXL reverse input by
            // default. The local action file is an explicit fallback path.
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-interactive-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.interactive_synthetic = true;
        } else if (std.mem.eql(u8, arg, "--emacs-copy-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.synthetic_copy = true;
        } else if (std.mem.eql(u8, arg, "--emacs-copy-local-smoke")) {
            config.mode = .emacs_interactive;
            config.synthetic_copy = true;
        } else if (std.mem.eql(u8, arg, "--emacs-interactive-local")) {
            config.mode = .emacs_interactive;
        } else if (std.mem.eql(u8, arg, "--emacs-interactive-local-smoke")) {
            config.mode = .emacs_interactive;
            config.synthetic_interactive = true;
        } else if (std.mem.eql(u8, arg, "--facts-publisher")) {
            config.mode = .facts_publisher;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-smoke")) {
            config.mode = .emacs_epxl;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-reconnect-smoke")) {
            config.mode = .emacs_epxl_reconnect;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-recovery-smoke")) {
            config.mode = .emacs_epxl_recovery;
            config.auto_input = "X";
            config.drop_first_input_ack = true;
        } else if (std.mem.eql(u8, arg, "--emacs-viewport-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.synthetic_wheel = true;
            config.synthetic_viewport = true;
        } else if (std.mem.eql(u8, arg, "--emacs-wheel-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.synthetic_wheel = true;
        } else if (std.mem.eql(u8, arg, "--emacs-pointer-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.synthetic_pointer = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-interactive-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.interactive_synthetic = true;
        } else if (std.mem.eql(u8, arg, "--interactive-publisher")) {
            config.interactive_publisher = true;
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
        } else if (std.mem.eql(u8, arg, "--clipboard-smoke")) {
            config.mode = .clipboard;
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

    if (config.mode == .clipboard) {
        try runClipboardSmoke();
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
            var delivery: input_policy.DeliveryJournal = .{};
            var child = try std.process.spawn(io, .{
                .argv = &.{ config.self_exe, "--publisher", "--replay", config.replay_path, "--endpoint", config.endpoint, "--token-file", config.token_path },
            });
            errdefer child.kill(io);
            const loaded = try runLiveFrontend(gpa, io, &config, &delivery);
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
        .clipboard => unreachable,
        .emacs_epxl => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_reconnect => try runEmacsEpxlSession(gpa, io, &config, 2),
        .emacs_epxl_recovery => try runEmacsEpxlSession(gpa, io, &config, 2),
        .emacs_epxl_interactive => try runEmacsEpxlSession(gpa, io, &config, 1),
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
    if (config.mode == .emacs_epxl_recovery and scene.stats.frame_updates < 1)
        return error.UnexpectedFactUpdateCount;
    if (config.mode == .emacs_epxl_recovery) {
        const applied = scene.text.items.len > 0 and
            std.mem.eql(u8, scene.text.items[0].bytes, "XEmacs Proto-UI") and
            scene.cursor != null and scene.cursor.?.x == 8 and scene.cursor.?.y == 0;
        if (!applied) return error.RecoveryInputNotApplied;
    }
    if (config.mode == .emacs_epxl_input and scene.stats.frame_updates < 2)
        return error.UnexpectedFactUpdateCount;
    if (config.mode == .emacs_epxl_input and
        !sceneHasText(&scene, "XEmacs Proto-UI")) return error.InputNotApplied;
    if (config.mode == .emacs_epxl_input and
        (scene.cursor == null or scene.cursor.?.x != 8 or scene.cursor.?.y != 0))
        return error.CursorNotApplied;
    if (config.mode == .emacs_epxl_edit) {
        const applied = sceneHasText(&scene, "visible ASCII text") and
            scene.cursor != null and scene.cursor.?.x == 48 and scene.cursor.?.y == 14;
        if (!applied) return error.EditNotApplied;
    }
    if (config.mode == .emacs_epxl_sequence) {
        const applied = sceneHasText(&scene, "XEmacs Proto-UI") and
            sceneHasText(&scene, "visible ASCII text");
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
