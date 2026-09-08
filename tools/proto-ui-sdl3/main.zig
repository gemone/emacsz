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
const capability = proto_ui.capability;
const session_codec = proto_ui.session;
const transport = proto_ui.transport;
const live = proto_ui.live;
const runtime_bridge = proto_ui.runtime_bridge;
const runtime_host = proto_ui.runtime_host;

const SDL_INIT_VIDEO: c_uint = 0x0000_0020;
const SDL_WINDOW_RESIZABLE: c_ulonglong = 0x0000_0020;
const SDL_EVENT_QUIT: c_uint = 0x100;
const SDL_EVENT_RENDER_TARGETS_RESET: c_uint = 0x2000;
const SDL_EVENT_RENDER_DEVICE_RESET: c_uint = 0x2001;
const SDL_EVENT_RENDER_DEVICE_LOST: c_uint = 0x2002;
const SDL_EVENT_KEY_DOWN: c_uint = 0x300;
const SDL_EVENT_KEY_UP: c_uint = 0x301;
const SDL_EVENT_TEXT_INPUT: c_uint = 0x303;
const SDL_EVENT_MOUSE_MOTION: c_uint = 0x400;
const SDL_EVENT_MOUSE_BUTTON_DOWN: c_uint = 0x401;
const SDL_EVENT_MOUSE_BUTTON_UP: c_uint = 0x402;
const SDL_EVENT_MOUSE_WHEEL: c_uint = 0x403;
const SDL_BUTTON_LMASK: u32 = 1;
const SDL_MOUSEWHEEL_NORMAL: u32 = 0;
/// EUP sequences 1..4 are consumed by capability/setup.  Reverse-direction
/// PONGs start at the first ordinary frontend producer sequence.
const frontend_pong_sequence_start: u64 = 5;

const SDL_Window = opaque {};
const SDL_Renderer = opaque {};
const SDL_Texture = opaque {};
const SDL_Surface = opaque {};

const SDL_PixelFormat = c_uint;
const SDL_TextureAccess = c_int;
const SDL_ScaleMode = c_int;
const SDL_PIXELFORMAT_RGBA8888: SDL_PixelFormat = 0x1646_2004;
const SDL_TEXTUREACCESS_TARGET: SDL_TextureAccess = 2;
const SDL_SCALEMODE_NEAREST: SDL_ScaleMode = 1;

const SDLInitFlags = c_uint;
const SDLWindowFlags = c_ulonglong;
const SDL_WINDOW_BORDERLESS: SDLWindowFlags = 0x10;
const SDL_WINDOW_FULLSCREEN: SDLWindowFlags = 0x01;
const SDL_WINDOW_MAXIMIZED: SDLWindowFlags = 0x80;
const SDL_WINDOW_ALWAYS_ON_TOP: SDLWindowFlags = 0x10000;
const SDL_DisplayID = c_uint;

extern fn SDL_Init(flags: SDLInitFlags) bool;
extern fn SDL_Quit() void;
extern fn SDL_CreateWindow(title: [*:0]const u8, w: c_int, h: c_int, flags: SDLWindowFlags) ?*SDL_Window;
extern fn SDL_DestroyWindow(window: *SDL_Window) void;
extern fn SDL_SetWindowTitle(window: *SDL_Window, title: [*:0]const u8) void;
extern fn SDL_SetWindowOpacity(window: *SDL_Window, opacity: f32) bool;
extern fn SDL_GetWindowOpacity(window: *SDL_Window) f32;
extern fn SDL_SetWindowBordered(window: *SDL_Window, bordered: bool) bool;
extern fn SDL_GetWindowFlags(window: *SDL_Window) SDLWindowFlags;
extern fn SDL_GetWindowDisplayScale(window: *SDL_Window) f32;
extern fn SDL_GetWindowBordersSize(window: *SDL_Window, top: *c_int, left: *c_int, bottom: *c_int, right: *c_int) bool;
extern fn SDL_SetWindowIcon(window: *SDL_Window, icon: *SDL_Surface) bool;
extern fn SDL_CreateSurfaceFrom(width: c_int, height: c_int, format: SDL_PixelFormat, pixels: ?*anyopaque, pitch: c_int) ?*SDL_Surface;
extern fn SDL_DestroySurface(surface: *SDL_Surface) void;
extern fn SDL_SetWindowParent(window: *SDL_Window, parent: ?*SDL_Window) bool;
extern fn SDL_SetWindowMinimumSize(window: *SDL_Window, min_w: c_int, min_h: c_int) bool;
extern fn SDL_SetWindowMaximumSize(window: *SDL_Window, max_w: c_int, max_h: c_int) bool;
extern fn SDL_SetWindowAspectRatio(window: *SDL_Window, min_aspect: f32, max_aspect: f32) bool;
extern fn SDL_SetWindowAlwaysOnTop(window: *SDL_Window, on_top: bool) bool;
extern fn SDL_GetWindowMinimumSize(window: *SDL_Window, w: *c_int, h: *c_int) bool;
extern fn SDL_GetWindowMaximumSize(window: *SDL_Window, w: *c_int, h: *c_int) bool;
extern fn SDL_GetWindowAspectRatio(window: *SDL_Window, min_aspect: *f32, max_aspect: *f32) bool;
extern fn SDL_SetWindowFullscreen(window: *SDL_Window, fullscreen: bool) bool;
extern fn SDL_SyncWindow(window: *SDL_Window) bool;
extern fn SDL_GetDisplayForWindow(window: *SDL_Window) SDL_DisplayID;
extern fn SDL_GetDisplayBounds(display: SDL_DisplayID, rect: *SDL_Rect) bool;
extern fn SDL_SetWindowResizable(window: *SDL_Window, resizable: bool) bool;
extern fn SDL_MaximizeWindow(window: *SDL_Window) bool;
extern fn SDL_RestoreWindow(window: *SDL_Window) bool;
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
extern fn SDL_UpdateTexture(texture: *SDL_Texture, rect: ?*const SDL_Rect, pixels: *const anyopaque, pitch: c_int) bool;
extern fn SDL_RenderTexture(renderer: *SDL_Renderer, texture: *SDL_Texture, source: ?*const SDL_FRect, destination: ?*const SDL_FRect) bool;
extern fn SDL_SetRenderTarget(renderer: *SDL_Renderer, texture: ?*SDL_Texture) bool;
extern fn SDL_PollEvent(event: *SDL_Event) bool;
extern fn SDL_PushEvent(event: *SDL_Event) bool;
extern fn SDL_GetWindowID(window: *SDL_Window) u32;
extern fn SDL_Delay(ms: c_uint) void;
extern fn SDL_StartTextInput(window: *SDL_Window) bool;
extern fn SDL_GetKeyName(key: c_uint) ?[*:0]const u8;
extern fn SDL_GetModState() u16;
extern fn SDL_SetModState(modifiers: u16) void;
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

const SDL_WindowEvent = extern struct {
    type: c_uint,
    reserved: c_uint,
    timestamp: u64,
    window_id: u32,
    data1: i32,
    data2: i32,
};

const SDL_Event = extern union {
    type: c_uint,
    key: SDL_KeyboardEvent,
    text: SDL_TextInputEvent,
    motion: SDL_MouseMotionEvent,
    button: SDL_MouseButtonEvent,
    wheel: SDL_MouseWheelEvent,
    window: SDL_WindowEvent,
    padding: [128]u8,
};

fn windowEvent(event_type: c_uint, window_id: u32, data1: i32, data2: i32) SDL_Event {
    var event: SDL_Event = undefined;
    event.window = .{
        .type = event_type,
        .reserved = 0,
        .timestamp = 0,
        .window_id = window_id,
        .data1 = data1,
        .data2 = data2,
    };
    return event;
}

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

fn pointerMotionEventV2(x: f32, y: f32, state: u32, _: u32) SDL_Event {
    return mouseMotionEvent(x, y, state);
}

fn pointerButtonEvent(
    x: f32,
    y: f32,
    event_type: c_uint,
    down: bool,
    button: u8,
    clicks: u8,
) SDL_Event {
    var event = mouseButtonEvent(x, y, event_type, down);
    event.button.button = button;
    event.button.clicks = clicks;
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

fn queueClipboardText(queue: anytype, support: input_policy.TextSupport) !bool {
    const text: ?[*:0]u8 = SDL_GetClipboardText();
    defer if (text) |owned| SDL_free(owned);
    const source: ?[*:0]const u8 = if (text) |owned| owned else null;
    const translated = input_policy.translateText(source, support) orelse return false;
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
    if (!try queueClipboardText(&queue, .ascii)) return error.ClipboardTextNotAccepted;
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

const Mode = enum { replay, live, publisher, emacs, facts_publisher, emacs_epxl, emacs_epxl_reconnect, emacs_epxl_recovery, emacs_epxl_interactive, emacs_epxl_input, emacs_epxl_unicode_input, emacs_epxl_key_v2, pointer_v2_translation, emacs_epxl_edit, emacs_epxl_sequence, frame_lifecycle, input_translation, focus_window_translation, emacs_interactive, clipboard, emacs_clipboard_unicode, emacs_pointer_selection, emacs_pointer_middle_paste, glyph_run_smoke, runtime_bridge_smoke };

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
    standard_session_control: bool = false,
    version_mismatch: bool = false,
    auto_input: ?[]const u8 = null,
    auto_key: ?frontend.KeyAction = null,
    renderer_request: []const u8 = "auto",
    present_mode: []const u8 = "off",
    synthetic_interactive: bool = false,
    synthetic_copy: bool = false,
    synthetic_clipboard_unicode: bool = false,
    clipboard_unicode_publisher: bool = false,
    pointer_selection_publisher: bool = false,
    pointer_middle_paste_publisher: bool = false,
    drop_first_input_ack: bool = false,
    interactive_publisher: bool = false,
    interactive_synthetic: bool = false,
    synthetic_pointer: bool = false,
    synthetic_pointer_v2: bool = false,
    synthetic_pointer_selection: bool = false,
    synthetic_pointer_middle_paste: bool = false,
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
                if (input_policy.translateText(event.text.text, .ascii)) |text| {
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

fn runPointerV2Smoke() !void {
    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow("Emacs Proto-UI Pointer V2", 480, 320, SDL_WINDOW_RESIZABLE) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);
    var journal: input_policy.DeliveryJournal = .{};
    journal.pointer_v2_negotiated = true;
    if (!input_policy.pointerV2Negotiated(&journal, true)) return error.CapabilityJournalMismatch;
    const modifiers = input_policy.sdlModifiersToEup(input_policy.sdl_kmod_lctrl);
    SDL_SetModState(input_policy.sdl_kmod_lctrl);
    defer SDL_SetModState(0);
    var synthetic = [_]SDL_Event{
        pointerButtonEvent(8, 2, SDL_EVENT_MOUSE_BUTTON_DOWN, true, 1, 1),
        pointerMotionEventV2(16, 4, input_policy.pointer_button_left, modifiers),
        pointerButtonEvent(24, 6, SDL_EVENT_MOUSE_BUTTON_UP, false, 1, 1),
        pointerButtonEvent(32, 8, SDL_EVENT_MOUSE_BUTTON_DOWN, true, 2, 1),
        pointerButtonEvent(32, 8, SDL_EVENT_MOUSE_BUTTON_UP, false, 2, 1),
        pointerButtonEvent(40, 10, SDL_EVENT_MOUSE_BUTTON_DOWN, true, 3, 1),
        pointerButtonEvent(40, 10, SDL_EVENT_MOUSE_BUTTON_UP, false, 3, 1),
    };
    for (&synthetic) |*event| {
        if (!SDL_PushEvent(event)) return sdlFail("SDL_PushEvent");
    }
    const expected = [_][]const u8{ "press", "drag", "release", "press", "release", "press", "release" };
    var received: usize = 0;
    var polls: usize = 0;
    while (received < expected.len and polls < 256) : (polls += 1) {
        var event: SDL_Event = undefined;
        if (!SDL_PollEvent(&event)) {
            SDL_Delay(1);
            continue;
        }
        const source: input_policy.PointerSource = switch (event.type) {
            input_policy.SDL_EVENT_MOUSE_MOTION => .{ .event_type = event.type, .x = @intFromFloat(event.motion.x), .y = @intFromFloat(event.motion.y), .state = event.motion.state, .modifiers = modifiers },
            input_policy.SDL_EVENT_MOUSE_BUTTON_DOWN, input_policy.SDL_EVENT_MOUSE_BUTTON_UP => .{ .event_type = event.type, .sdl_button = event.button.button, .down = event.button.down, .clicks = event.button.clicks, .x = @intFromFloat(event.button.x), .y = @intFromFloat(event.button.y), .modifiers = input_policy.sdlModifiersToEup(SDL_GetModState()) },
            else => continue,
        };
        const translated = input_policy.translatePointerV2(source) orelse return error.PointerTranslationFailed;
        try journal.pushPointerV2(translated);
        if (!std.mem.eql(u8, @tagName(translated.phase), expected[received])) return error.PointerOrderMismatch;
        received += 1;
    }
    if (received != expected.len or journal.queue.length != expected.len) return error.PointerTranslationIncomplete;
    std.debug.print("sdl3-pointer-v2-smoke: {{\"kind\":\"sdl3-pointer-v2-smoke\",\"received\":{d},\"order\":[\"left-modified-press\",\"left-modified-drag\",\"left-modified-release\",\"middle-click\",\"middle-release\",\"right-click\",\"right-release\"],\"emacs_destroyed\":false,\"result\":\"pass\"}}\n", .{received});
}

fn runFocusWindowSmoke() !void {
    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow(
        "Emacs Proto-UI Focus Window Translation",
        480,
        320,
        SDL_WINDOW_RESIZABLE,
    ) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);
    const sdl_window_id = SDL_GetWindowID(window);
    if (sdl_window_id == 0) return error.InvalidSdlWindowId;

    var journal: input_policy.DeliveryJournal = .{};
    journal.platform_negotiated = true;
    if (!input_policy.platformEventsNegotiated(&journal, true)) return error.CapabilityJournalMismatch;
    var synthetic = [_]SDL_Event{
        windowEvent(input_policy.SDL_EVENT_WINDOW_FOCUS_GAINED, sdl_window_id, 0, 0),
        windowEvent(input_policy.SDL_EVENT_WINDOW_RESIZED, sdl_window_id, 480, 320),
        windowEvent(input_policy.SDL_EVENT_WINDOW_CLOSE_REQUESTED, sdl_window_id, 0, 0),
    };
    for (&synthetic) |*event| {
        if (!SDL_PushEvent(event)) return sdlFail("SDL_PushEvent");
    }

    var received: usize = 0;
    const expected_received: usize = 3;
    var polls: usize = 0;
    while (received < expected_received and polls < 256) : (polls += 1) {
        var event: SDL_Event = undefined;
        if (!SDL_PollEvent(&event)) {
            SDL_Delay(1);
            continue;
        }
        if (input_policy.translateFocus(event.type, 0x4567, event.window.window_id)) |focus| {
            try journal.pushFocus(focus);
            received += 1;
        } else if (input_policy.translateWindow(
            event.type,
            event.window.window_id,
            event.window.data1,
            event.window.data2,
        )) |request| {
            try journal.pushWindow(request);
            received += 1;
        }
    }
    if (received != expected_received) return error.PlatformTranslationIncomplete;
    if (journal.queue.length != expected_received) return error.PlatformQueueCount;

    const first = journal.queue.items[0].focus;
    const second = journal.queue.items[1].window;
    const third = journal.queue.items[2].window;
    const ordered = first.phase == .gained and first.frame_id == 0x4567 and
        first.sdl_window_id == sdl_window_id and
        second.kind == .resize and second.width == 480 and second.height == 320 and
        third.kind == .close and third.width == 0 and third.height == 0;
    if (!ordered) return error.PlatformIntentOrderMismatch;
    std.debug.print(
        "sdl3-focus-window-smoke: {{\"kind\":\"sdl3-focus-window-smoke\",\"window_id\":{d},\"received\":{d},\"order\":[\"focus-gained\",\"resize\",\"close-request\"],\"emacs_destroyed\":false,\"result\":\"pass\"}}\n",
        .{ sdl_window_id, received },
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
        // Full keys are negotiated EPXL-only; the local file path has no
        // capability table and therefore must not pretend to deliver them.
        .key_v2 => {},
        // Pointer/wheel intents are intentionally EPXL-only; the local fallback
        // does not pretend to support them.
        .pointer => {},
        .pointer_v2 => {},
        .wheel => {},
        // Platform observation is EPXL-only by design; there is no inherited
        // Emacs core fallback and no local mutation.
        .focus => {},
        .window => {},
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
        \\        (let ((action (split-string (with-temp-buffer (let ((coding-system-for-read (quote utf-8))) (insert-file-contents input-path)) (buffer-string)) "\n" t)))
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
        \\      (let ((coding-system-for-write (quote utf-8))) (with-temp-file path (insert (json-serialize (list :frame_width (plist-get facts :frame_width) :frame_height (plist-get facts :frame_height) :window_width (plist-get facts :window_width) :window_height (plist-get facts :window_height) :text (vconcat lines) :window_start_line viewport-start-line :window_visible_lines viewport-line-count :cursor cursor)))))
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
                        if (try queueClipboardText(&input_queue, .ascii)) frame_gate.dirty = true;
                    } else if (input_policy.isCopyShortcut(event.key.scancode, event.key.down, event.key.repeat, event.key.modifiers)) {
                        try input_queue.pushKey(.{ .action = .copy });
                        frame_gate.dirty = true;
                    } else if (input_policy.translateKey(event.key.scancode, event.key.down, event.key.repeat, event.key.modifiers)) |key| {
                        try input_queue.pushKey(key);
                        frame_gate.dirty = true;
                    }
                },
                SDL_EVENT_TEXT_INPUT => {
                    if (input_policy.translateText(event.text.text, .ascii)) |text| {
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

fn capabilitySetMessage(
    gpa: std.mem.Allocator,
    set: capability.Set,
    message_type: u16,
    sequence: u64,
    ack_sequence: u64,
) ![]u8 {
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(gpa);
    try capability.encodeMessage(gpa, set, message_type, sequence, ack_sequence, &message);
    return message.toOwnedSlice(gpa);
}

fn sendCapabilitySet(
    gpa: std.mem.Allocator,
    writer: anytype,
    set: capability.Set,
    message_type: u16,
    sequence: u64,
    ack_sequence: u64,
) !void {
    const message = try capabilitySetMessage(gpa, set, message_type, sequence, ack_sequence);
    defer gpa.free(message);
    try live.writeFrame(writer, message);
    try writer.flush();
}

fn readCapabilitySet(
    gpa: std.mem.Allocator,
    reader: anytype,
    expected_message_type: u16,
    expected_sequence: u64,
    expected_ack_sequence: u64,
) !capability.Set {
    const message = (try live.readFrame(reader, gpa)) orelse return error.InvalidNegotiationMessage;
    defer gpa.free(message);
    const payload = try protocol.decodeEnvelope(message);
    const envelope = payload.envelope;
    if (envelope.message_type != expected_message_type or envelope.sequence != expected_sequence or
        envelope.ack_sequence != expected_ack_sequence or envelope.session_id != capability.session_id or
        envelope.flags != protocol.Flags.idempotent or envelope.frame_id != 0)
        return error.InvalidNegotiationMessage;
    return try capability.decodeSet(gpa, payload.bytes);
}

fn sendReadyAck(
    gpa: std.mem.Allocator,
    writer: anytype,
    hash: *const [capability.hash_len]u8,
    sequence: u64,
    ack_sequence: u64,
) !void {
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(gpa);
    try capability.encodeReadyAck(gpa, hash, sequence, ack_sequence, &message);
    try live.writeFrame(writer, message.items);
    try writer.flush();
}

fn readReadyAck(
    gpa: std.mem.Allocator,
    reader: anytype,
    expected_sequence: u64,
    expected_ack_sequence: u64,
    expected_hash: *const [capability.hash_len]u8,
) !void {
    const message = (try live.readFrame(reader, gpa)) orelse return error.InvalidNegotiationMessage;
    defer gpa.free(message);
    const payload = try protocol.decodeEnvelope(message);
    const envelope = payload.envelope;
    if (envelope.message_type != protocol.Message.ready_ack or envelope.sequence != expected_sequence or
        envelope.ack_sequence != expected_ack_sequence or envelope.session_id != capability.session_id or
        envelope.flags != protocol.Flags.idempotent or envelope.frame_id != 0 or
        payload.bytes.len != capability.hash_len)
        return error.InvalidNegotiationMessage;
    var mismatch: u8 = 0;
    for (expected_hash, payload.bytes) |expected, actual| mismatch |= expected ^ actual;
    if (mismatch != 0) return error.CapabilityHashMismatch;
}

fn negotiatePublisherSide(
    gpa: std.mem.Allocator,
    reader: anytype,
    writer: anytype,
) !capability.Negotiated {
    const backend = capability.backendSupported();
    try sendCapabilitySet(gpa, writer, backend, protocol.Message.capabilities, 1, 0);
    const frontend_set = try readCapabilitySet(gpa, reader, protocol.Message.capabilities_ack, 2, 1);
    var negotiated = try capability.negotiate(backend, frontend_set);
    try sendCapabilitySet(gpa, writer, negotiated.effective, protocol.Message.session_ready, 3, 2);
    try readReadyAck(gpa, reader, 4, 3, &negotiated.hash);
    return negotiated;
}

fn reserveFrontendInputSequence(delivery: *input_policy.DeliveryJournal) void {
    delivery.sender.next_sequence = @max(delivery.sender.next_sequence, 5);
}

fn negotiateFrontendSide(
    gpa: std.mem.Allocator,
    reader: anytype,
    writer: anytype,
) !capability.Negotiated {
    const backend = try readCapabilitySet(gpa, reader, protocol.Message.capabilities, 1, 0);
    const frontend_set = capability.frontendSupported();
    try sendCapabilitySet(gpa, writer, frontend_set, protocol.Message.capabilities_ack, 2, 1);
    const effective = try readCapabilitySet(gpa, reader, protocol.Message.session_ready, 3, 2);
    var negotiated = try capability.negotiate(backend, frontend_set);
    if (!std.meta.eql(effective.bits, negotiated.effective.bits)) return error.CapabilityHashMismatch;
    try sendReadyAck(gpa, writer, &negotiated.hash, 4, 3);
    return negotiated;
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
    const negotiated = try negotiatePublisherSide(gpa, &reader.interface, &writer.interface);

    if (config.version_mismatch) {
        if (!negotiated.effective.contains(.session_control_v1))
            return error.SessionControlCapabilityNotNegotiated;
        var acks = live.AckTracker.init(1);
        var payload: [8]u8 = undefined;
        std.mem.writeInt(u16, payload[0..2], 1, .little);
        std.mem.writeInt(u16, payload[2..4], 0, .little);
        std.mem.writeInt(u16, payload[4..6], 2, .little);
        std.mem.writeInt(u16, payload[6..8], 0, .little);
        try sendStandardEupFrame(
            gpa,
            &reader.interface,
            &writer.interface,
            &acks,
            5,
            protocol.Message.version_mismatch,
            0,
            0,
            5,
            &payload,
        );
        std.debug.print("sdl3-live-smoke: standard EUP VERSION_MISMATCH carried over authenticated EPXL frames\n", .{});
        return;
    }

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

    if (config.standard_session_control) {
        if (!negotiated.effective.contains(.session_control_v1))
            return error.SessionControlCapabilityNotNegotiated;
        const base_sequence = acks.next_sequence orelse return error.InvalidSequence;
        // The backend sends seven sequence values after replay.  Reject the
        // sequence base before using any of the offsets below.  The frontend's
        // PONG uses a separate reverse-direction sequence.
        _ = std.math.add(u64, base_sequence, 6) catch return error.InvalidSequence;
        const sequences = [4]u64{
            base_sequence,
            base_sequence + 1,
            base_sequence + 2,
            base_sequence + 3,
        };
        var suspend_payload: [4]u8 = .{ 4, 0, 0, 0 };
        var resume_payload: [4]u8 = .{ 1, 0, 0, 0 };
        var resumed_payload: [8]u8 = undefined;
        std.mem.writeInt(u64, &resumed_payload, base_sequence + 3, .little);

        const control_messages = [_]struct { sequence: u64, message_type: u16, payload: []const u8 }{
            .{ .sequence = sequences[0], .message_type = protocol.Message.session_suspend, .payload = &suspend_payload },
            .{ .sequence = sequences[1], .message_type = protocol.Message.session_resume, .payload = &resume_payload },
            .{ .sequence = sequences[2], .message_type = protocol.Message.session_resumed, .payload = &resumed_payload },
        };
        for (control_messages) |item| {
            try sendStandardEupFrame(
                gpa,
                &reader.interface,
                &writer.interface,
                &acks,
                item.sequence,
                item.message_type,
                0,
                0,
                item.sequence,
                item.payload,
            );
        }

        var last_update: ?usize = null;
        for (messages, 0..) |message, index| {
            if ((try protocol.decodeEnvelope(message)).envelope.message_type == protocol.Message.frame_update)
                last_update = index;
        }
        const update_index = last_update orelse return error.NoFrameUpdate;
        const encoded_update = try protocol.decodeEnvelope(messages[update_index]);
        var update = try protocol.decodeFrameUpdate(gpa, encoded_update.bytes);
        defer protocol.freeFrameUpdate(gpa, &update);
        update.header.sequence = base_sequence + 3;
        var update_payload: std.ArrayList(u8) = .empty;
        defer update_payload.deinit(gpa);
        try protocol.encodeFrameUpdate(gpa, update, &update_payload);
        try sendStandardEupFrame(
            gpa,
            &reader.interface,
            &writer.interface,
            &acks,
            sequences[3],
            encoded_update.envelope.message_type,
            encoded_update.envelope.flags,
            encoded_update.envelope.frame_id,
            encoded_update.envelope.timestamp_ns,
            update_payload.items,
        );

        var ping_payload: [8]u8 = undefined;
        std.mem.writeInt(u64, &ping_payload, 42, .little);
        try sendStandardEupFrame(
            gpa,
            &reader.interface,
            &writer.interface,
            &acks,
            base_sequence + 4,
            protocol.Message.ping,
            0,
            0,
            base_sequence + 4,
            &ping_payload,
        );

        // The frontend automatically answers PING.  Read that reverse-direction
        // EUP frame, verify the echoed probe, and ACK it like every control.
        // The PONG payload owns the echoed timestamp; the envelope owns the
        // responder's monotonic send time.
        const pong_message = (try live.readFrame(&reader.interface, gpa)) orelse return error.ExpectedPong;
        defer gpa.free(pong_message);
        const pong = try protocol.decodeEnvelope(pong_message);
        if (pong.envelope.message_type != protocol.Message.pong or
            pong.envelope.flags != 0 or
            pong.envelope.sequence != frontend_pong_sequence_start or
            pong.envelope.ack_sequence != 0 or
            pong.envelope.session_id != capability.session_id or
            pong.envelope.frame_id != 0) return error.ExpectedPong;
        const pong_value = try session_codec.decodePong(pong.bytes);
        if (pong_value.original_timestamp_ns != 42) return error.ExpectedPong;
        if (pong.envelope.timestamp_ns == 0) return error.ExpectedPong;
        try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = pong.envelope.sequence });
        try writer.interface.flush();

        var error_payload: std.ArrayList(u8) = .empty;
        defer error_payload.deinit(gpa);
        try session_codec.encodeSessionError(gpa, .{
            .code = 101,
            .severity = .recoverable,
            .recoverable = true,
            .message_resource_id = 12,
            .detail = "recoverable",
        }, &error_payload);
        try sendStandardEupFrame(
            gpa,
            &reader.interface,
            &writer.interface,
            &acks,
            base_sequence + 5,
            protocol.Message.session_error,
            0,
            0,
            base_sequence + 5,
            error_payload.items,
        );

        const close_payload: [4]u8 = .{ 1, 0, 0, 0 };
        try sendStandardEupFrame(
            gpa,
            &reader.interface,
            &writer.interface,
            &acks,
            base_sequence + 6,
            protocol.Message.session_close,
            0,
            0,
            base_sequence + 6,
            &close_payload,
        );
        std.debug.print("sdl3-live-smoke: standard EUP suspend/resume, automatic PONG, recoverable error, and ordered close carried over EPXL frames\n", .{});
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
        "(progn (setq-default buffer-file-coding-system (quote utf-8)) (module-load (expand-file-name (format \"%s\" (format \"{s}\")))) (let* ((frame (selected-frame)) (window (selected-window)) (path (expand-file-name (format \"%s\" (format \"{s}\")))) (input-path (expand-file-name (format \"%s\" (format \"{s}\")))) (clipboard-path (expand-file-name (format \"%s\" (format \"{s}\")))) (buffer (window-buffer window)) (buffer-ready (progn (with-current-buffer buffer (set-buffer-multibyte t)) t)) (bounded-selection nil) (clipboard-unicode {s}) (facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))) (text (with-current-buffer buffer (buffer-substring-no-properties (point-min) (point-max)))) (lines (split-string text \"\\n\")) (point (with-current-buffer buffer (window-point window))) (cursor (with-current-buffer buffer (save-excursion (goto-char point) (list :line (line-number-at-pos point) :column (current-column))))) (viewport-start (window-start window)) (viewport-end (window-end window t)) (viewport-start-line 1) (viewport-line-count 0) (viewport-cursor-line 1)) (with-current-buffer buffer (erase-buffer) (insert \"Emacs Proto-UI\\nvisible ASCII textZ\") (dotimes (i 28) (insert (format \"\\nline %02d\" i))) (redisplay)) (setq viewport-start (window-start window)) (setq viewport-end (window-end window t)) (setq viewport-start-line (line-number-at-pos viewport-start)) (setq viewport-line-count (count-lines viewport-start viewport-end)) (setq text (buffer-substring-no-properties viewport-start viewport-end)) (setq lines (split-string text \"\\n\" t)) (setq point (window-point window)) (setq viewport-cursor-line (min 15 (max 1 (+ 1 (- (line-number-at-pos point) viewport-start-line))))) (setq cursor (with-current-buffer buffer (save-excursion (goto-char point) (list :line viewport-cursor-line :column (current-column))))) (setq facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))) (let ((coding-system-for-write (quote utf-8))) (with-temp-file path (insert (json-serialize (list :frame_width (plist-get facts :frame_width) :frame_height (plist-get facts :frame_height) :window_width (plist-get facts :window_width) :window_height (plist-get facts :window_height) :text (vconcat lines) :cursor cursor :window_start_line viewport-start-line :window_visible_lines viewport-line-count))))) (sit-for 0.2) (set-frame-size frame 240 30) (while t (when (file-readable-p input-path) (let ((action (split-string (with-temp-buffer (let ((coding-system-for-read (quote utf-8))) (insert-file-contents input-path)) (buffer-string)) \"\\n\" t))) (cond ((and (= (length action) 3) (string= (nth 1 action) \"key-v2\")) (let* ((event (json-parse-string (nth 2 action) :object-type (quote plist))) (logical (decode-coding-string (base64-decode-string (plist-get event :logical_key)) (quote utf-8))) (state (plist-get event :state)) (modifiers (plist-get event :modifiers)) (physical (plist-get event :physical_key))) (when (and (= state 1) (= modifiers 2)) (with-current-buffer buffer (cond ((and (= physical 4) (string= logical \"a\")) (beginning-of-line)) ((and (= physical 8) (string= logical \"e\")) (end-of-line))) (set-window-point window (point)) (redisplay))))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"backspace\")) (with-current-buffer buffer (goto-char (point-max)) (delete-char -1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"cursor-left\")) (with-current-buffer buffer (backward-char 1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"cursor-right\")) (with-current-buffer buffer (forward-char 1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"cursor-up\")) (with-current-buffer buffer (previous-line 1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"cursor-down\")) (with-current-buffer buffer (next-line 1) (set-window-point window (point)) (redisplay))) ((and (= (length action) 3) (string= (nth 1 action) \"key\") (string= (nth 2 action) \"copy\")) (with-current-buffer buffer (let* ((copy-end (progn (goto-char (point-min)) (line-end-position))) (copy-length (<= (- copy-end (point-min)) 120)) (copy-ascii (save-excursion (let ((ascii t) (pos (point-min))) (while (< pos copy-end) (let ((ch (char-after pos))) (when (or (< ch 32) (> ch 126)) (setq ascii nil) (setq pos copy-end))) (setq pos (+ pos 1))) ascii))) (copy-text (if clipboard-unicode \"Emacs 你好\" (and copy-length copy-ascii (buffer-substring-no-properties (point-min) copy-end))))) (when copy-text (kill-ring-save (point-min) copy-end) (with-temp-file clipboard-path (insert (if clipboard-unicode (concat \"base64:\" (base64-encode-string (encode-coding-string copy-text (quote utf-8)) t)) copy-text))) (set-window-point window (point)) (redisplay))))) ((and (= (length action) 3) (string= (nth 1 action) \"pointer-v2\") (or {s} {s})) (let* ((event (condition-case nil (json-parse-string (nth 2 action) :object-type (quote plist)) (error nil))) (phase (and event (plist-get event :phase))) (buttons (and event (plist-get event :buttons))) (pointer-x (and event (plist-get event :x))) (pointer-y (and event (plist-get event :y))) (pointer-clicks (and event (plist-get event :clicks))) (pointer-modifiers (and event (plist-get event :modifiers)))) (cond ((and {s} (member phase (list \"press\" \"drag\" \"release\")) (eql buttons 1) (eql pointer-clicks 1) (eql pointer-modifiers 0) (numberp pointer-x) (numberp pointer-y)) (condition-case nil (let ((point (posn-point (posn-at-x-y pointer-x pointer-y window)))) (when point (with-current-buffer buffer (goto-char point) (when (string= phase \"press\") (push-mark point nil t)) (when (string= phase \"release\") (let* ((copy-start (min (mark) (point))) (copy-end (max (mark) (point))) (copy-length (<= (- copy-end copy-start) 120)) (copy-ascii (save-excursion (let ((ascii t) (pos copy-start)) (while (< pos copy-end) (let ((ch (char-after pos))) (when (or (< ch 32) (> ch 126)) (setq ascii nil) (setq pos copy-end))) (setq pos (+ pos 1))) ascii))) (copy-text (and mark-active copy-length copy-ascii (buffer-substring-no-properties copy-start copy-end)))) (when copy-text (kill-ring-save copy-start copy-end) (with-temp-file clipboard-path (insert (concat \"base64:\" (base64-encode-string (encode-coding-string copy-text (quote utf-8)) t)))) (setq mark-active nil) (setq bounded-selection t)))) (set-window-point window (point)) (redisplay)))) (error nil))) ((and {s} bounded-selection (string= phase \"release\") (eql buttons 2) (eql pointer-clicks 1) (eql pointer-modifiers 0) (numberp pointer-x) (numberp pointer-y)) (condition-case nil (let ((point (posn-point (posn-at-x-y pointer-x pointer-y window)))) (when point (with-current-buffer buffer (goto-char point) (yank) (set-window-point window (point)) (redisplay)))) (error nil))) (t nil)))) ((and (= (length action) 3) (string= (nth 1 action) \"pointer\")) (let* ((pointer (split-string (nth 2 action) \" \" t)) (pointer-phase (nth 0 pointer)) (pointer-x (string-to-number (nth 1 pointer))) (pointer-y (string-to-number (nth 2 pointer)))) (when (and (= (length pointer) 3) (or (string= pointer-phase \"press\") (string= pointer-phase \"release\"))) (condition-case nil (let ((point (posn-point (posn-at-x-y pointer-x pointer-y window)))) (when point (with-current-buffer buffer (goto-char point) (redisplay)))) (error nil))))) ((and (= (length action) 3) (string= (nth 1 action) \"wheel\")) (let ((wheel (split-string (nth 2 action) \" \" t))) (when (= (length wheel) 2) (with-current-buffer buffer (condition-case nil (if (string= (nth 0 wheel) \"down\") (scroll-up (string-to-number (nth 1 wheel))) (scroll-down (string-to-number (nth 1 wheel)))) (error nil)))))) ((and (= (length action) 3) (string= (nth 1 action) \"text\") (> (length (nth 2 action)) 0)) (with-current-buffer buffer (goto-char (point-min)) (insert (decode-coding-string (base64-decode-string (nth 2 action)) (quote utf-8))) (set-window-point window (point)) (redisplay)))) (let ((coding-system-for-write (quote utf-8))) (with-temp-file (concat input-path \".ack\") (insert (nth 0 action)))) (delete-file input-path))) (setq viewport-start (window-start window)) (setq viewport-end (window-end window t)) (setq viewport-start-line (line-number-at-pos viewport-start)) (setq viewport-line-count (count-lines viewport-start viewport-end)) (setq text (buffer-substring-no-properties viewport-start viewport-end)) (setq lines (split-string text \"\\n\" t)) (setq point (window-point window)) (setq viewport-cursor-line (min 15 (max 1 (+ 1 (- (line-number-at-pos point) viewport-start-line))))) (setq cursor (with-current-buffer buffer (save-excursion (goto-char point) (list :line viewport-cursor-line :column (current-column))))) (setq facts (json-parse-string (proto-ui-frame-facts frame) :object-type (quote plist))) (let ((coding-system-for-write (quote utf-8))) (with-temp-file path (insert (json-serialize (list :frame_width (plist-get facts :frame_width) :frame_height (plist-get facts :frame_height) :window_width (plist-get facts :window_width) :window_height (plist-get facts :window_height) :text (vconcat lines) :cursor cursor :window_start_line viewport-start-line :window_visible_lines viewport-line-count))))) (sit-for 0.1))))",
        .{
            config.module_path,
            config.facts_path,
            input_path,
            clipboard_path,
            if (config.clipboard_unicode_publisher) "t" else "nil",
            if (config.pointer_selection_publisher) "t" else "nil",
            if (config.pointer_middle_paste_publisher) "t" else "nil",
            if (config.pointer_selection_publisher) "t" else "nil",
            if (config.pointer_middle_paste_publisher) "t" else "nil",
        },
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
    var input_sequence: u64 = 5;
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
        const negotiated = try negotiatePublisherSide(gpa, &reader.interface, &writer.interface);

        const request = try readControlExact(&reader);
        if (request.kind != .resync_request or request.sequence != 1)
            return error.InvalidResyncRequest;
        scene.resetForResync();
        scene.next_sequence = 5; // capability exchange reserved session sequences 1..4
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
        try sendSnapshotMessages(gpa, published.?.facts, published.?.text.lines, published.?.cursor, published.?.viewport, &scene, &acks, io, &reader, &writer, input_path, &input_sequence, negotiated.effective);
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
                sendSnapshotMessages(gpa, published.?.facts, published.?.text.lines, published.?.cursor, published.?.viewport, &scene, &change_acks, io, &reader, &writer, input_path, &input_sequence, negotiated.effective) catch |err| {
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
        .key_v2 => |key| blk: {
            try input_policy.encodeFullKeyEvent(gpa, key, &payload);
            break :blk protocol.Message.key_event;
        },
        .pointer => |pointer| blk: {
            try frontend.encodePointerInput(gpa, pointer, &payload);
            break :blk protocol.Message.pointer_event;
        },
        .pointer_v2 => |pointer| blk: {
            try input_policy.encodePointerEventV2(gpa, pointer, &payload);
            break :blk protocol.Message.pointer_event;
        },
        .wheel => |wheel| blk: {
            try frontend.encodeWheelInput(gpa, wheel, &payload);
            break :blk protocol.Message.wheel_event;
        },
        .focus => |focus| blk: {
            try protocol.encodeFocusEvent(gpa, focus, &payload);
            break :blk protocol.Message.focus_event;
        },
        .window => |request| blk: {
            try protocol.encodeWindowRequest(gpa, request, &payload);
            break :blk protocol.Message.window_request;
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
        var buffer: [1024]u8 = undefined;
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

fn base64Alloc(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const encoded = try gpa.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
    errdefer gpa.free(encoded);
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    return encoded;
}

fn writeKeyV2Artifact(
    gpa: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    sequence: u64,
    event: input_policy.FullKeyEvent,
) !void {
    const logical = try base64Alloc(gpa, event.logicalKey());
    defer gpa.free(logical);
    const text = try base64Alloc(gpa, event.text());
    defer gpa.free(text);
    const value = try std.fmt.allocPrint(
        gpa,
        "{{\"schema\":2,\"state\":{d},\"modifiers\":{d},\"physical_key\":{d},\"repeat_count\":{d},\"device_id\":{d},\"layout_id\":{d},\"logical_key\":\"{s}\",\"text\":\"{s}\",\"execution\":\"observed\"}}",
        .{
            @intFromEnum(event.state), event.modifiers,
            event.physical_key,        event.repeat_count,
            event.device_id,           event.layout_id,
            logical,                   text,
        },
    );
    defer gpa.free(value);
    try writeEpxlInputArtifact(gpa, io, path, sequence, "key-v2", value);
}

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
    capabilities: capability.Set,
) !void {
    while (true) {
        const inbound = try readInbound(reader, gpa);
        switch (inbound) {
            .control => |control| {
                if (control.kind != .ack or control.sequence != expected_sequence) {
                    return error.ExpectedAck;
                }
                return;
            },
            .frame => |frame| {
                defer gpa.free(frame);
                const payload = try protocol.decodeEnvelope(frame);
                const is_text = payload.envelope.message_type == protocol.Message.text_input;
                const is_key = payload.envelope.message_type == protocol.Message.key_event;
                const is_key_v2 = is_key and payload.bytes.len >= input_policy.key_v2_fixed_tail and
                    std.mem.readInt(u16, payload.bytes[0..2], .little) == 0 and
                    std.mem.readInt(u16, payload.bytes[2..4], .little) == input_policy.key_v2_schema;
                var full_key: ?input_policy.FullKeyEvent = null;
                const is_pointer = payload.envelope.message_type == protocol.Message.pointer_event;
                const is_pointer_v2 = is_pointer and input_policy.isPointerEventV2(payload.bytes);
                const is_wheel = payload.envelope.message_type == protocol.Message.wheel_event;
                const is_focus = payload.envelope.message_type == protocol.Message.focus_event;
                const is_window = payload.envelope.message_type == protocol.Message.window_request;
                var copy_action = false;
                if (is_key_v2) {
                    full_key = try input_policy.decodeFullKeyEvent(payload.bytes);
                } else if (is_key) {
                    const key = try frontend.decodeKeyEvent(payload.bytes);
                    copy_action = key.action == .copy;
                }
                const input_allowed = (is_text and capabilities.contains(.input_text_ascii)) or
                    (is_key_v2 and capabilities.contains(.input_key_full_v2)) or
                    (is_key and capabilities.contains(.input_key_bounded) and
                        (!copy_action or capabilities.contains(.clipboard_ascii_bounded))) or
                    ((is_pointer_v2 and capabilities.contains(.input_pointer_v2)) or
                        (is_pointer and !is_pointer_v2 and capabilities.contains(.input_pointer_bounded))) or
                    (is_wheel and capabilities.contains(.input_wheel_line)) or
                    (is_focus and capabilities.contains(.platform_focus_window_events)) or
                    (is_window and capabilities.contains(.platform_focus_window_events));
                if (!input_allowed or
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
                if (payload.envelope.sequence != input_sequence.*) {
                    return error.InvalidSequence;
                }
                if (is_text) {
                    const input = try frontend.decodeTextInput(payload.bytes);
                    var encoded: [176]u8 = undefined;
                    const encoded_len = std.base64.standard.Encoder.calcSize(input.text.len);
                    _ = std.base64.standard.Encoder.encode(encoded[0..encoded_len], input.text);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "text", encoded[0..encoded_len]);
                } else if (is_wheel) {
                    const event = try frontend.decodeWheelInput(payload.bytes);
                    const direction: []const u8 = if (event.y > 0) "down" else "up";
                    const value = try std.fmt.allocPrint(gpa, "{s} {d}", .{ direction, @abs(event.y) });
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "wheel", value);
                } else if (is_pointer_v2) {
                    const event = try input_policy.decodePointerEventV2(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"phase\":\"{s}\",\"buttons\":{d},\"x\":{d},\"y\":{d},\"clicks\":{d},\"modifiers\":{d},\"execution\":\"observed\"}}",
                        .{ @tagName(event.phase), event.buttons, event.x, event.y, event.clicks, event.modifiers },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "pointer-v2", value);
                } else if (is_pointer) {
                    const event = try frontend.decodePointerInput(payload.bytes);
                    const value = try std.fmt.allocPrint(gpa, "{s} {d} {d}", .{ @tagName(event.phase), event.x, event.y });
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "pointer", value);
                } else if (is_key_v2) {
                    try writeKeyV2Artifact(gpa, io, input_path, payload.envelope.sequence, full_key.?);
                } else if (is_focus) {
                    const event = try protocol.decodeFocusEvent(payload.bytes);
                    const phase = if (event.phase == .gained) "focus-gained" else "focus-lost";
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"phase\":\"{s}\",\"frame_id\":{d},\"sdl_window_id\":{d},\"execution\":\"observed\"}}",
                        .{ phase, event.frame_id, event.sdl_window_id },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "platform-focus", value);
                } else if (is_window) {
                    const event = try protocol.decodeWindowRequest(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"request\":\"{s}\",\"sdl_window_id\":{d},\"width\":{d},\"height\":{d},\"x\":{d},\"y\":{d},\"execution\":\"observed\"}}",
                        .{
                            @tagName(event.kind),
                            event.sdl_window_id,
                            event.width,
                            event.height,
                            event.x,
                            event.y,
                        },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "platform-window", value);
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
                // That control ACK acknowledged the reverse-input message.  The
                // backend frame ACK is a separate control and may arrive next.
                continue;
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
    capabilities: capability.Set,
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
        try awaitFrameAck(gpa, io, reader, writer, envelope.sequence, input_path, input_sequence, envelope.session_id, envelope.frame_id, capabilities);
        try acks.ack(envelope.sequence);
    }
}

fn glyphRunDeleteMessage(
    gpa: std.mem.Allocator,
    delete: frontend.GlyphRunDeleteWire,
    sequence: u64,
) ![]u8 {
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(gpa);
    try frontend.encodeGlyphRunDelete(gpa, delete, &payload);
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.debug,
        .message_type = protocol.Message.glyph_run_delete,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = 1,
        .timestamp_ns = sequence,
    }, payload.items, &message);
    return message.toOwnedSlice(gpa);
}

fn runGlyphRunSmoke(gpa: std.mem.Allocator, config: *const Config) !void {
    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();

    var create_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, create_payload[0..4], 1, .little);
    std.mem.writeInt(u32, create_payload[4..8], 1, .little);
    var create: std.ArrayList(u8) = .empty;
    defer create.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_create,
        .sequence = 1,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = 1,
        .timestamp_ns = 1,
    }, &create_payload, &create);
    try scene.apply(create.items);

    var window_bytes: std.ArrayList(u8) = .empty;
    defer window_bytes.deinit(gpa);
    try frontend.encodeWindow(gpa, .{
        .id = 100,
        .frame_id = 1,
        .x = 0,
        .y = 0,
        .width = 200,
        .height = 40,
    }, &window_bytes);
    var row_bytes: std.ArrayList(u8) = .empty;
    defer row_bytes.deinit(gpa);
    try frontend.encodeRow(gpa, .{
        .window_id = 100,
        .index = 0,
        .flags = 0,
        .x = 0,
        .y = 0,
        .width = 200,
        .height = 40,
        .ascent = 8,
        .descent = 2,
        .baseline = 8,
        .visible_height = 40,
    }, &row_bytes);
    var text_bytes: std.ArrayList(u8) = .empty;
    defer text_bytes.deinit(gpa);
    try frontend.encodeTextLine(gpa, .{
        .row_index = 0,
        .line = "stale facts text",
    }, &text_bytes);
    var damage_bytes: std.ArrayList(u8) = .empty;
    defer damage_bytes.deinit(gpa);
    try frontend.encodeRect(gpa, .{ .x = 0, .y = 0, .width = 200, .height = 60 }, &damage_bytes);
    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = window_bytes.items },
        .{ .kind = protocol.SectionKind.rows, .records = row_bytes.items },
        .{ .kind = protocol.SectionKind.extension_min, .records = text_bytes.items },
        .{ .kind = protocol.SectionKind.damage, .records = damage_bytes.items },
    };
    var update_payload: std.ArrayList(u8) = .empty;
    defer update_payload.deinit(gpa);
    try protocol.encodeFrameUpdate(gpa, .{
        .header = .{
            .frame_id = 1,
            .frame_generation = 1,
            .sequence = 2,
            .redisplay_generation = 1,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = 200,
            .logical_height = 60,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = 200,
            .physical_height = 60,
            .scale = 1,
            .dpi_x = 96,
            .dpi_y = 96,
            .damage_mode = 2,
            .update_cause = 1,
            .coalesced_count = 0,
            .timestamp_ns = 2,
        },
        .sections = &sections,
    }, &update_payload);
    var update: std.ArrayList(u8) = .empty;
    defer update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.delta,
        .message_type = protocol.Message.frame_update,
        .sequence = 2,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = 1,
        .timestamp_ns = 2,
    }, update_payload.items, &update);
    try scene.apply(update.items);

    var glyph_payload: std.ArrayList(u8) = .empty;
    defer glyph_payload.deinit(gpa);
    try frontend.encodeGlyphRun(gpa, .{
        .run_id = 9,
        .generation = 1,
        .window_id = 100,
        .row_index = 0,
        .x = 8,
        .y = 2,
        .width = 40,
        .height = 8,
        .text = "Emacs",
    }, &glyph_payload);
    var glyph: std.ArrayList(u8) = .empty;
    defer glyph.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.debug,
        .message_type = protocol.Message.glyph_run,
        .sequence = 3,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = 1,
        .timestamp_ns = 3,
    }, glyph_payload.items, &glyph);
    try scene.apply(glyph.items);

    if (scene.frame == null or scene.frames.frames[0].status != .active or
        scene.windows.items.len != 1 or scene.rows.items.len != 1 or
        scene.glyph_runs.items.len != 1 or
        !std.mem.eql(u8, scene.glyph_runs.items[0].text, "Emacs"))
        return error.GlyphRunSceneStateInvalid;

    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow("Emacs Proto-UI Glyph Run", 240, 96, 0) orelse
        return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);
    const selected_renderer = try createRenderer(gpa, window, config.renderer_request, config.present_mode);
    defer destroyRenderer(selected_renderer);

    var frame_gate: renderer_policy.FrameGate = .{};
    var frame_counters: renderer_policy.FrameCounters = .{};
    var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
    defer draw_list.deinit();
    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var run_rendered = false;
    var stale_text_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .text => |text| {
                if (text.x == 8 and text.y == 2 and std.mem.eql(u8, text.bytes, "Emacs"))
                    run_rendered = true;
                if (std.mem.indexOf(u8, text.bytes, "stale facts text") != null)
                    stale_text_rendered = true;
            },
            else => {},
        }
    }
    const active_run_rendered = run_rendered;
    const active_facts_suppressed = !stale_text_rendered;
    if (!run_rendered or stale_text_rendered) return error.GlyphRunNotRendered;

    const mismatch = try glyphRunDeleteMessage(gpa, .{
        .run_id = 9,
        .generation = 2,
        .window_id = 100,
        .row_index = 0,
    }, 4);
    defer gpa.free(mismatch);
    if (scene.apply(mismatch)) |_| {
        return error.GlyphRunMismatchedDeleteAccepted;
    } else |_| {}
    if (scene.next_sequence.? != 4 or scene.glyph_runs.items.len != 1 or
        !std.mem.eql(u8, scene.glyph_runs.items[0].text, "Emacs"))
        return error.GlyphRunMismatchedDeleteMutatedScene;

    const delete_message = try glyphRunDeleteMessage(gpa, .{
        .run_id = 9,
        .generation = 1,
        .window_id = 100,
        .row_index = 0,
    }, 4);
    defer gpa.free(delete_message);
    try scene.apply(delete_message);
    if (scene.next_sequence.? != 5 or scene.glyph_runs.items.len != 0)
        return error.GlyphRunDeleteFailed;

    run_rendered = false;
    stale_text_rendered = false;
    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    for (draw_list.commands.items) |command| {
        switch (command) {
            .text => |text| {
                if (text.x == 8 and text.y == 2 and std.mem.eql(u8, text.bytes, "Emacs"))
                    run_rendered = true;
                if (std.mem.indexOf(u8, text.bytes, "stale facts text") != null)
                    stale_text_rendered = true;
            },
            else => {},
        }
    }
    if (active_run_rendered and active_facts_suppressed and
        (run_rendered or !stale_text_rendered))
        return error.GlyphRunDeleteFallbackFailed;

    try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters);
    var quit = false;
    const started = SDL_GetTicks();
    while (!quit and SDL_GetTicks() - started < config.auto_quit_ms) {
        var event: SDL_Event = undefined;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) quit = true;
        }
        try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters);
        SDL_Delay(10);
    }
    if (frame_counters.text_commands_total == 0) return error.GlyphRunNotRendered;
    std.debug.print(
        "sdl3-glyph-run-smoke: {{\"kind\":\"sdl3-glyph-run-smoke\",\"active_runs\":0,\"text\":\"Emacs\",\"delete\":\"exact\",\"facts_fallback\":true,\"rendered\":true,\"auto_closed\":true,\"result\":\"pass\"}}\n",
        .{},
    );
}

fn encodeSessionControlEnvelope(
    gpa: std.mem.Allocator,
    sequence: u64,
    message_type: u16,
    payload: []const u8,
) ![]u8 {
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .timestamp_ns = 1,
    }, payload, &message);
    return message.toOwnedSlice(gpa);
}

fn sendStandardEupFrame(
    gpa: std.mem.Allocator,
    reader: anytype,
    writer: anytype,
    acks: *live.AckTracker,
    sequence: u64,
    message_type: u16,
    flags: u16,
    frame_id: u32,
    timestamp_ns: u64,
    payload: []const u8,
) !void {
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = flags,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = frame_id,
        .timestamp_ns = timestamp_ns,
    }, payload, &message);
    try acks.markSent(sequence);
    try live.writeFrame(writer, message.items);
    try writer.flush();
    var control_bytes: [live.control_size]u8 = undefined;
    try reader.readSliceAll(&control_bytes);
    const control = try live.decodeControl(&control_bytes);
    if (control.kind != .ack or control.sequence != sequence) return error.ExpectedAck;
    try acks.ack(sequence);
}

fn runRuntimeBridgeSmoke(gpa: std.mem.Allocator, config: *const Config) !void {
    var host: runtime_host.FakeHost = undefined;
    const table = runtime_host.fakeTable(&host);
    var bridge = try runtime_bridge.Bridge.init(table);

    try bridge.createTerminal(.{ .requested_generation = 1 });
    try bridge.activateTerminal();
    try bridge.registerFrame(.{ .id = 22, .generation = 1 });
    _ = try bridge.refreshFrameGeometry();
    try bridge.beginCapture(1);

    try bridge.observeWindow(.{
        .id = 10,
        .generation = 1,
        .x = 8,
        .y = 8,
        .width = 200,
        .height = 40,
    });
    try bridge.observeRow(.{
        .window_id = 10,
        .row_index = 0,
        .x = 4,
        .y = 4,
        .width = 192,
        .height = 24,
        .ascent = 8,
        .descent = 2,
        .baseline = 8,
        .visible_height = 24,
    });
    var run_text = [_]u8{0} ** 120;
    @memcpy(run_text[0..5], "Emacs");
    try bridge.observeRun(.{
        .run_id = 1,
        .window_id = 10,
        .row_index = 0,
        .face_id = 7,
        .face_generation = 1,
        .x = 12,
        .y = 8,
        .width = 40,
        .height = 8,
        .text_length = 5,
        .text = run_text,
    });
    try bridge.observeCursor(.{
        .window_id = 10,
        .row_index = 0,
        .x = 12,
        .y = 8,
        .width = 2,
        .height = 8,
        .visible = true,
        .active = true,
    });
    try bridge.observeDamage(.{ .width = 800, .height = 600 });
    try bridge.commitCapture();

    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    var face_payload: std.ArrayList(u8) = .empty;
    defer face_payload.deinit(gpa);
    try protocol.encodeFaceDefine(gpa, .{
        .face_id = 7,
        .generation = 1,
        .presence = .{ .foreground = true, .background = true },
        .foreground = .{ 0xff, 0xd5, 0x4d, 255 },
        .background = .{ 0x20, 0x28, 0x38, 255 },
    }, &face_payload);
    var face_define: std.ArrayList(u8) = .empty;
    defer face_define.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.face_define,
        .sequence = 1,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = 1,
        .timestamp_ns = 1,
    }, face_payload.items, &face_define);
    try scene.apply(face_define.items);

    var string_payload: std.ArrayList(u8) = .empty;
    defer string_payload.deinit(gpa);
    try protocol.encodeStringDefine(gpa, .{
        .resource_id = 12,
        .generation = 1,
        .bytes = "Emacs Proto-UI",
    }, &string_payload);
    var string_define: std.ArrayList(u8) = .empty;
    defer string_define.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.string_define,
        .sequence = 2,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = 1,
        .timestamp_ns = 1,
    }, string_payload.items, &string_define);
    try scene.apply(string_define.items);

    var create: std.ArrayList(u8) = .empty;
    defer create.deinit(gpa);
    try bridge.encodeFrameCreate(gpa, 3, capability.session_id, 1, &create);
    try scene.apply(create.items);

    var title_payload: std.ArrayList(u8) = .empty;
    defer title_payload.deinit(gpa);
    try protocol.encodeFrameTitle(gpa, .{
        .string_resource_id = 12,
        .string_generation = 1,
        .frame_generation = bridge.eup_frame_generation,
    }, &title_payload);
    var title: std.ArrayList(u8) = .empty;
    defer title.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_title,
        .sequence = 4,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, title_payload.items, &title);
    try scene.apply(title.items);

    var alpha_payload: std.ArrayList(u8) = .empty;
    defer alpha_payload.deinit(gpa);
    try protocol.encodeFrameAlpha(gpa, .{
        .active_opacity = 8000,
        .inactive_opacity = 6000,
        .background_opacity = 9000,
        .frame_generation = bridge.eup_frame_generation,
    }, &alpha_payload);
    var alpha: std.ArrayList(u8) = .empty;
    defer alpha.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_alpha,
        .sequence = 5,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, alpha_payload.items, &alpha);
    try scene.apply(alpha.items);

    var decorations_payload: std.ArrayList(u8) = .empty;
    defer decorations_payload.deinit(gpa);
    try protocol.encodeFrameDecorations(gpa, .{
        .decorated = false,
        .frame_generation = bridge.eup_frame_generation,
    }, &decorations_payload);
    var decorations: std.ArrayList(u8) = .empty;
    defer decorations.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_decorations,
        .sequence = 6,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, decorations_payload.items, &decorations);
    try scene.apply(decorations.items);

    var scale_payload: std.ArrayList(u8) = .empty;
    defer scale_payload.deinit(gpa);
    try protocol.encodeFrameScale(gpa, .{
        .scale = 1,
        .dpi_x = 96,
        .dpi_y = 96,
        .frame_generation = bridge.eup_frame_generation,
    }, &scale_payload);
    var scale: std.ArrayList(u8) = .empty;
    defer scale.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_scale,
        .sequence = 7,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, scale_payload.items, &scale);
    try scene.apply(scale.items);

    var fullscreen_payload: std.ArrayList(u8) = .empty;
    defer fullscreen_payload.deinit(gpa);
    try protocol.encodeFrameFullscreen(gpa, .{
        .mode = .fullboth,
        .frame_generation = bridge.eup_frame_generation,
    }, &fullscreen_payload);
    var fullscreen: std.ArrayList(u8) = .empty;
    defer fullscreen.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_fullscreen,
        .sequence = 8,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, fullscreen_payload.items, &fullscreen);
    try scene.apply(fullscreen.items);

    var monitor_payload: std.ArrayList(u8) = .empty;
    defer monitor_payload.deinit(gpa);
    try protocol.encodeFrameMonitor(gpa, .{
        .flags = protocol.FrameMonitorFlags.primary,
        .monitor_id = 1,
        .x = 0,
        .y = 0,
        .width = 1920,
        .height = 1080,
        .frame_generation = bridge.eup_frame_generation,
    }, &monitor_payload);
    var monitor: std.ArrayList(u8) = .empty;
    defer monitor.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_monitor,
        .sequence = 9,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, monitor_payload.items, &monitor);
    try scene.apply(monitor.items);

    var maximize_payload: std.ArrayList(u8) = .empty;
    defer maximize_payload.deinit(gpa);
    try protocol.encodeFrameMaximize(gpa, .{
        .flags = protocol.FrameMaximizeFlags.both,
        .frame_generation = bridge.eup_frame_generation,
    }, &maximize_payload);
    var maximize: std.ArrayList(u8) = .empty;
    defer maximize.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_maximize,
        .sequence = 10,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, maximize_payload.items, &maximize);
    try scene.apply(maximize.items);

    const control_suspend = try encodeSessionControlEnvelope(
        gpa,
        11,
        protocol.Message.session_suspend,
        &.{ 4, 0, 0, 0 },
    );
    defer gpa.free(control_suspend);
    try scene.apply(control_suspend);
    if (scene.control.stage != .suspended) return error.RuntimeBridgeSuspendStateInvalid;

    var update: std.ArrayList(u8) = .empty;
    defer update.deinit(gpa);
    try bridge.encodeFrameUpdate(gpa, 12, capability.session_id, 2, &update);
    if (scene.apply(update.items)) |_| {
        return error.RuntimeBridgeSuspendNotBlocking;
    } else |err| {
        if (err != frontend.Error.SessionSuspended) return err;
    }

    const control_resume = try encodeSessionControlEnvelope(
        gpa,
        12,
        protocol.Message.session_resume,
        &.{ 2, 0, 0, 0 },
    );
    defer gpa.free(control_resume);
    try scene.apply(control_resume);
    if (scene.control.stage != .resume_pending)
        return error.RuntimeBridgeResumePendingStateInvalid;

    const control_resumed = try encodeSessionControlEnvelope(
        gpa,
        13,
        protocol.Message.session_resumed,
        &.{ 14, 0, 0, 0, 0, 0, 0, 0 },
    );
    defer gpa.free(control_resumed);
    try scene.apply(control_resumed);
    if (scene.control.stage != .active or scene.next_sequence.? != 14)
        return error.RuntimeBridgeResumeSequenceInvalid;

    var active_update: std.ArrayList(u8) = .empty;
    defer active_update.deinit(gpa);
    try bridge.encodeFrameUpdate(gpa, 14, capability.session_id, 2, &active_update);
    try scene.apply(active_update.items);
    try bridge.acceptFrameUpdate(14);

    var run: std.ArrayList(u8) = .empty;
    defer run.deinit(gpa);
    try bridge.encodeRun(gpa, 0, 15, capability.session_id, 3, &run);
    try scene.apply(run.items);
    if (scene.control.stage != .active or scene.next_sequence.? != 16)
        return error.RuntimeBridgeControlSequenceInvalid;

    var image_define_payload: std.ArrayList(u8) = .empty;
    defer image_define_payload.deinit(gpa);
    try protocol.encodeImageDefine(gpa, .{
        .image_id = 31,
        .generation = 1,
        .width = 4,
        .height = 4,
        .total_byte_count = 64,
        .cache_policy = .pinned,
    }, &image_define_payload);
    var image_define: std.ArrayList(u8) = .empty;
    defer image_define.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.image_define,
        .sequence = 16,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, image_define_payload.items, &image_define);
    try scene.apply(image_define.items);

    var icon_pixels: [64]u8 = undefined;
    for (&icon_pixels, 0..) |*byte, index| byte.* = @truncate(index * 7 + 9);
    var image_data_payload: std.ArrayList(u8) = .empty;
    defer image_data_payload.deinit(gpa);
    try protocol.encodeImageData(gpa, .{
        .image_id = 31,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 1,
        .bytes = &icon_pixels,
    }, &image_data_payload);
    var image_data: std.ArrayList(u8) = .empty;
    defer image_data.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.image_data,
        .sequence = 17,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, image_data_payload.items, &image_data);
    try scene.apply(image_data.items);

    var icon_payload: std.ArrayList(u8) = .empty;
    defer icon_payload.deinit(gpa);
    try protocol.encodeFrameIcon(gpa, .{
        .flags = protocol.FrameIconFlags.present,
        .image_id = 31,
        .image_generation = 1,
        .hotspot_x = 1,
        .hotspot_y = 1,
        .frame_generation = bridge.eup_frame_generation,
    }, &icon_payload);
    var icon: std.ArrayList(u8) = .empty;
    defer icon.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_icon,
        .sequence = 18,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, icon_payload.items, &icon);
    try scene.apply(icon.items);
    if (scene.icon == null or scene.icon.?.image_id != 31)
        return error.RuntimeBridgeIconInvalid;

    var geometry_payload: std.ArrayList(u8) = .empty;
    defer geometry_payload.deinit(gpa);
    try protocol.encodeFrameGeometry(gpa, .{
        .frame_generation = bridge.eup_frame_generation,
        .outer = .{ .x = 0, .y = 0, .width = 248, .height = 104 },
        .content = .{ .x = 4, .y = 4, .width = 240, .height = 96 },
        .text = .{ .x = 4, .y = 4, .width = 240, .height = 96 },
        .window = .{ .x = 4, .y = 4, .width = 240, .height = 96 },
        .body = .{ .x = 4, .y = 4, .width = 240, .height = 96 },
    }, &geometry_payload);
    var geometry: std.ArrayList(u8) = .empty;
    defer geometry.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_geometry,
        .sequence = 19,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, geometry_payload.items, &geometry);
    try scene.apply(geometry.items);
    if (scene.geometry == null or scene.geometry.?.content.width != 240)
        return error.RuntimeBridgeGeometryInvalid;

    var size_hints_payload: std.ArrayList(u8) = .empty;
    defer size_hints_payload.deinit(gpa);
    try protocol.encodeFrameSizeHints(gpa, .{
        .flags = protocol.FrameSizeHintFlags.min_size |
            protocol.FrameSizeHintFlags.max_size |
            protocol.FrameSizeHintFlags.size_increment |
            protocol.FrameSizeHintFlags.aspect_ratio,
        .frame_generation = bridge.eup_frame_generation,
        .min_width = 120,
        .min_height = 48,
        .max_width = 960,
        .max_height = 480,
        .width_increment = 8,
        .height_increment = 8,
        .aspect_min_numerator = 1,
        .aspect_min_denominator = 4,
        .aspect_max_numerator = 4,
        .aspect_max_denominator = 1,
    }, &size_hints_payload);
    var size_hints: std.ArrayList(u8) = .empty;
    defer size_hints.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_size_hints,
        .sequence = 20,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, size_hints_payload.items, &size_hints);
    try scene.apply(size_hints.items);
    if (scene.size_hints == null or scene.size_hints.?.min_width != 120)
        return error.RuntimeBridgeSizeHintsInvalid;

    var z_order_payload: std.ArrayList(u8) = .empty;
    defer z_order_payload.deinit(gpa);
    try protocol.encodeFrameZOrder(gpa, .{
        .operation = .top,
        .frame_generation = bridge.eup_frame_generation,
    }, &z_order_payload);
    var z_order: std.ArrayList(u8) = .empty;
    defer z_order.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_z_order,
        .sequence = 21,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, z_order_payload.items, &z_order);
    try scene.apply(z_order.items);
    if (scene.z_order == null or scene.z_order.?.operation != .top)
        return error.RuntimeBridgeZOrderInvalid;

    var parent_payload: std.ArrayList(u8) = .empty;
    defer parent_payload.deinit(gpa);
    try protocol.encodeFrameParent(gpa, .{
        .child_frame_generation = bridge.eup_frame_generation,
    }, &parent_payload);
    var parent: std.ArrayList(u8) = .empty;
    defer parent.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_parent,
        .sequence = 22,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, parent_payload.items, &parent);
    try scene.apply(parent.items);
    if (scene.parent == null or scene.parent.?.flags & protocol.FrameParentFlags.present != 0)
        return error.RuntimeBridgeParentInvalid;

    var cursor_update_payload: std.ArrayList(u8) = .empty;
    defer cursor_update_payload.deinit(gpa);
    try frontend.encodeCursorUpdate(gpa, bridge.eup_frame_generation, .{
        .window_id = 10,
        .x = 16,
        .y = 12,
        .width = 2,
        .height = 8,
        .kind = 1,
        .visible = true,
        .active = true,
    }, &cursor_update_payload);
    var cursor_update: std.ArrayList(u8) = .empty;
    defer cursor_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.cursor_update,
        .sequence = 23,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, cursor_update_payload.items, &cursor_update);
    try scene.apply(cursor_update.items);
    if (scene.cursor == null or scene.cursor.?.x != 16)
        return error.RuntimeBridgeCursorUpdateInvalid;

    var clear_area_payload: std.ArrayList(u8) = .empty;
    defer clear_area_payload.deinit(gpa);
    try frontend.encodeClearArea(gpa, .{
        .window_id = 10,
        .rect = .{ .x = 40, .y = 24, .width = 32, .height = 16 },
        .face_id = 7,
        .face_generation = 1,
        .frame_generation = bridge.eup_frame_generation,
    }, &clear_area_payload);
    var clear_area: std.ArrayList(u8) = .empty;
    defer clear_area.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.clear_area,
        .sequence = 24,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, clear_area_payload.items, &clear_area);
    try scene.apply(clear_area.items);
    if (scene.clear_areas.items.len != 1 or scene.clear_areas.items[0].rect.width != 32)
        return error.RuntimeBridgeClearAreaInvalid;

    var scroll_payload: std.ArrayList(u8) = .empty;
    defer scroll_payload.deinit(gpa);
    try frontend.encodeScrollRun(gpa, .{
        .window_id = 10,
        .source_y = 0,
        .destination_y = 8,
        .width = 200,
        .height = 20,
        .frame_generation = bridge.eup_frame_generation,
    }, &scroll_payload);
    var scroll_run: std.ArrayList(u8) = .empty;
    defer scroll_run.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.scroll_run,
        .sequence = 25,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, scroll_payload.items, &scroll_run);
    try scene.apply(scroll_run.items);
    const scroll_plan = renderer_policy.planScrollCopy(
        @intCast(scene.windows.items[0].width),
        @intCast(scene.windows.items[0].height),
        scene.scroll_runs.items[0].source_y,
        scene.scroll_runs.items[0].destination_y,
        scene.scroll_runs.items[0].width,
        scene.scroll_runs.items[0].height,
    ) orelse return error.RuntimeBridgeScrollPlanInvalid;

    var damage_rects: std.ArrayList(u8) = .empty;
    defer damage_rects.deinit(gpa);
    try bridge.encodeDamageRects(gpa, 26, capability.session_id, 1, &damage_rects);
    try scene.apply(damage_rects.items);
    if (scene.damage.items.len != 1 or scene.damage.items[0].width != 800)
        return error.RuntimeBridgeDamageRectsInvalid;

    if (scene.frame_header == null) return error.RuntimeBridgeFrameHeaderInvalid;
    try bridge.setRenderHint(.{
        .mode = .mailbox,
        .workload = .typing,
        .damage_only_allowed = true,
        .deadline_ns = 2,
    });
    var flush: std.ArrayList(u8) = .empty;
    defer flush.deinit(gpa);
    try bridge.encodeFlush(gpa, 27, capability.session_id, 1, &flush);
    try scene.apply(flush.items);
    if (scene.flush == null or scene.flush.?.damage_kind != .full)
        return error.RuntimeBridgeFlushInvalid;

    var render_hint: std.ArrayList(u8) = .empty;
    defer render_hint.deinit(gpa);
    try bridge.encodeRenderHint(gpa, 28, capability.session_id, 1, &render_hint);
    try scene.apply(render_hint.items);
    if (scene.render_hint == null or scene.render_hint.?.preferred_mode != .mailbox)
        return error.RuntimeBridgeRenderHintInvalid;

    var border_payload: std.ArrayList(u8) = .empty;
    defer border_payload.deinit(gpa);
    try frontend.encodeBorderUpdate(gpa, .{
        .sides = frontend.BorderSides.top | frontend.BorderSides.right |
            frontend.BorderSides.bottom | frontend.BorderSides.left,
        .thickness = 6,
        .color = .{ 0x88, 0x22, 0xcc, 255 },
        .frame_generation = bridge.eup_frame_generation,
    }, &border_payload);
    var border_update: std.ArrayList(u8) = .empty;
    defer border_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.border_update,
        .sequence = 29,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, border_payload.items, &border_update);
    try scene.apply(border_update.items);
    if (scene.border == null or scene.border.?.thickness != 6)
        return error.RuntimeBridgeBorderInvalid;

    var divider_payload: std.ArrayList(u8) = .empty;
    defer divider_payload.deinit(gpa);
    try frontend.encodeDividerUpdate(gpa, .{
        .orientation = .vertical,
        .divider_id = 8,
        .divider_generation = 1,
        .window_id = 10,
        .position = 100,
        .offset = 8,
        .span = 20,
        .thickness = 4,
        .frame_generation = bridge.eup_frame_generation,
    }, &divider_payload);
    var divider_update: std.ArrayList(u8) = .empty;
    defer divider_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.divider_update,
        .sequence = 30,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, divider_payload.items, &divider_update);
    try scene.apply(divider_update.items);
    if (scene.dividers.items.len != 1 or scene.dividers.items[0].position != 100)
        return error.RuntimeBridgeDividerInvalid;

    var fringe_payload: std.ArrayList(u8) = .empty;
    defer fringe_payload.deinit(gpa);
    try frontend.encodeFringeUpdate(gpa, .{
        .side = .left,
        .fringe_id = 9,
        .fringe_generation = 1,
        .window_id = 10,
        .y = 8,
        .height = 24,
        .width = 8,
        .color = .{ 0x22, 0x66, 0xaa, 255 },
        .frame_generation = bridge.eup_frame_generation,
    }, &fringe_payload);
    var fringe_update: std.ArrayList(u8) = .empty;
    defer fringe_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.fringe_update,
        .sequence = 31,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, fringe_payload.items, &fringe_update);
    try scene.apply(fringe_update.items);
    if (scene.fringes.items.len != 1 or scene.fringes.items[0].width != 8)
        return error.RuntimeBridgeFringeInvalid;

    var scrollbar_payload: std.ArrayList(u8) = .empty;
    defer scrollbar_payload.deinit(gpa);
    try frontend.encodeWindowScrollState(gpa, .{
        .flags = frontend.WindowScrollFlags.vertical_visible,
        .window_id = 10,
        .frame_generation = bridge.eup_frame_generation,
        .content_size = 2000,
        .viewport_size = 400,
        .position = 400,
        .track_width = 12,
    }, &scrollbar_payload);
    var scrollbar_update: std.ArrayList(u8) = .empty;
    defer scrollbar_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.window_scroll_state,
        .sequence = 32,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, scrollbar_payload.items, &scrollbar_update);
    try scene.apply(scrollbar_update.items);
    if (scene.scroll_states.items.len != 1 or scene.scroll_states.items[0].position != 400)
        return error.RuntimeBridgeScrollbarInvalid;

    if (scene.windows.items.len != 1 or scene.rows.items.len != 1 or
        scene.glyph_runs.items.len != 1 or scene.cursor == null)
        return error.RuntimeBridgeSceneInvalid;
    if (!std.mem.eql(u8, scene.glyph_runs.items[0].text, "Emacs"))
        return error.RuntimeBridgeRunInvalid;
    if (scene.title == null or !std.mem.eql(u8, scene.title.?, "Emacs Proto-UI"))
        return error.RuntimeBridgeTitleInvalid;
    if (scene.alpha == null or scene.alpha.?.active_opacity != 8000)
        return error.RuntimeBridgeAlphaInvalid;
    if (scene.decorations == null or scene.decorations.?.decorated)
        return error.RuntimeBridgeDecorationsInvalid;
    if (scene.scale == null or scene.scale.?.scale != 1)
        return error.RuntimeBridgeScaleInvalid;
    if (scene.fullscreen == null or scene.fullscreen.?.mode != .fullboth)
        return error.RuntimeBridgeFullscreenInvalid;
    if (scene.monitor == null or scene.monitor.?.monitor_id == 0)
        return error.RuntimeBridgeMonitorInvalid;
    if (scene.maximize == null or scene.maximize.?.flags != protocol.FrameMaximizeFlags.both)
        return error.RuntimeBridgeMaximizeInvalid;

    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow("Emacs Proto-UI Runtime Bridge", 240, 96, 0) orelse
        return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);
    SDL_SetWindowTitle(window, scene.title.?.ptr);
    const parent_unparented = SDL_SetWindowParent(window, null);
    if (!parent_unparented) return sdlFail("SDL_SetWindowParent");
    var icon_applied = false;
    if (scene.icon) |icon_state| {
        if (icon_state.flags & protocol.FrameIconFlags.present != 0) {
            const image = scene.images.lookup(icon_state.image_id) orelse
                return error.RuntimeBridgeIconInvalid;
            if (!image.complete or image.generation != icon_state.image_generation or
                image.bytes.len != image.metadata.total_byte_count)
                return error.RuntimeBridgeIconInvalid;
            const surface = SDL_CreateSurfaceFrom(
                @intCast(image.metadata.width),
                @intCast(image.metadata.height),
                SDL_PIXELFORMAT_RGBA8888,
                image.bytes.ptr,
                @intCast(image.metadata.width * 4),
            ) orelse return sdlFail("SDL_CreateSurfaceFrom");
            defer SDL_DestroySurface(surface);
            icon_applied = SDL_SetWindowIcon(window, surface);
            if (!icon_applied) return sdlFail("SDL_SetWindowIcon");
        }
    }
    if (!icon_applied) return error.RuntimeBridgeIconInvalid;
    var border_top: c_int = 0;
    var border_left: c_int = 0;
    var border_bottom: c_int = 0;
    var border_right: c_int = 0;
    const borders_supported = SDL_GetWindowBordersSize(window, &border_top, &border_left, &border_bottom, &border_right) and
        border_top >= 0 and border_left >= 0 and border_bottom >= 0 and border_right >= 0;
    var z_order_supported = false;
    if (scene.z_order != null and scene.z_order.?.operation == .top) {
        z_order_supported = SDL_SetWindowAlwaysOnTop(window, true) and SDL_SyncWindow(window) and
            (SDL_GetWindowFlags(window) & SDL_WINDOW_ALWAYS_ON_TOP) != 0;
        if (z_order_supported) {
            const restored = SDL_SetWindowAlwaysOnTop(window, false) and SDL_SyncWindow(window) and
                (SDL_GetWindowFlags(window) & SDL_WINDOW_ALWAYS_ON_TOP) == 0;
            if (!restored) return error.RuntimeBridgeZOrderRestoreFailed;
        }
    }
    var size_hints_supported = false;
    if (scene.size_hints) |hints| {
        size_hints_supported = true;
        if (hints.flags & protocol.FrameSizeHintFlags.min_size != 0)
            size_hints_supported = SDL_SetWindowMinimumSize(
                window,
                @intCast(hints.min_width),
                @intCast(hints.min_height),
            );
        if (size_hints_supported and hints.flags & protocol.FrameSizeHintFlags.min_size != 0) {
            var actual_width: c_int = 0;
            var actual_height: c_int = 0;
            size_hints_supported = SDL_GetWindowMinimumSize(window, &actual_width, &actual_height) and
                actual_width == @as(c_int, @intCast(hints.min_width)) and
                actual_height == @as(c_int, @intCast(hints.min_height));
        }
        if (hints.flags & protocol.FrameSizeHintFlags.max_size != 0)
            size_hints_supported = SDL_SetWindowMaximumSize(
                window,
                @intCast(hints.max_width),
                @intCast(hints.max_height),
            );
        if (size_hints_supported and hints.flags & protocol.FrameSizeHintFlags.max_size != 0) {
            var actual_width: c_int = 0;
            var actual_height: c_int = 0;
            size_hints_supported = SDL_GetWindowMaximumSize(window, &actual_width, &actual_height) and
                actual_width == @as(c_int, @intCast(hints.max_width)) and
                actual_height == @as(c_int, @intCast(hints.max_height));
        }
        if (hints.flags & protocol.FrameSizeHintFlags.aspect_ratio != 0)
            size_hints_supported = SDL_SetWindowAspectRatio(
                window,
                @as(f32, @floatFromInt(hints.aspect_min_numerator)) / @as(f32, @floatFromInt(hints.aspect_min_denominator)),
                @as(f32, @floatFromInt(hints.aspect_max_numerator)) / @as(f32, @floatFromInt(hints.aspect_max_denominator)),
            );
        if (size_hints_supported and hints.flags & protocol.FrameSizeHintFlags.aspect_ratio != 0) {
            const requested_min = @as(f32, @floatFromInt(hints.aspect_min_numerator)) /
                @as(f32, @floatFromInt(hints.aspect_min_denominator));
            const requested_max = @as(f32, @floatFromInt(hints.aspect_max_numerator)) /
                @as(f32, @floatFromInt(hints.aspect_max_denominator));
            var actual_min: f32 = 0;
            var actual_max: f32 = 0;
            size_hints_supported = SDL_GetWindowAspectRatio(window, &actual_min, &actual_max) and
                @abs(actual_min - requested_min) <= 0.001 and
                @abs(actual_max - requested_max) <= 0.001;
        }
    }
    var opacity_supported = false;
    if (scene.alpha) |alpha_state| {
        const requested_opacity = @as(f32, @floatFromInt(alpha_state.active_opacity)) / 10000.0;
        opacity_supported = SDL_SetWindowOpacity(window, requested_opacity);
        if (opacity_supported) {
            const actual_opacity = SDL_GetWindowOpacity(window);
            if (@abs(actual_opacity - requested_opacity) > 0.001) {
                _ = SDL_SetWindowOpacity(window, 1.0);
                opacity_supported = false;
            }
        }
        // Restore the diagnostic window even if the platform accepted fade;
        // alpha state remains authoritative in the Scene.
        _ = SDL_SetWindowOpacity(window, 1.0);
    }
    var decorations_supported = false;
    if (scene.decorations) |decoration_state| {
        decorations_supported = SDL_SetWindowBordered(window, decoration_state.decorated);
        const undecorated = (SDL_GetWindowFlags(window) & SDL_WINDOW_BORDERLESS) != 0;
        if (!undecorated) decorations_supported = false;
        // Restore a decorated diagnostic window; Scene remains authoritative.
        _ = SDL_SetWindowBordered(window, true);
    }
    var scale_supported = false;
    var platform_scale_milli: u32 = 0;
    if (scene.scale != null) {
        const platform_scale = SDL_GetWindowDisplayScale(window);
        if (platform_scale > 0 and std.math.isFinite(platform_scale)) {
            const scale_milli = @round(platform_scale * 1000.0);
            if (scale_milli >= 0 and scale_milli <= 64000) {
                scale_supported = true;
                platform_scale_milli = @intFromFloat(scale_milli);
            }
        }
    }
    var fullscreen_supported = false;
    if (scene.fullscreen != null) {
        fullscreen_supported = SDL_SetWindowFullscreen(window, true);
        if (fullscreen_supported) fullscreen_supported = SDL_SyncWindow(window);
        if (fullscreen_supported and (SDL_GetWindowFlags(window) & SDL_WINDOW_FULLSCREEN) == 0)
            fullscreen_supported = false;
        if (fullscreen_supported) {
            const restored = SDL_SetWindowFullscreen(window, false) and
                SDL_SyncWindow(window) and
                (SDL_GetWindowFlags(window) & SDL_WINDOW_FULLSCREEN) == 0;
            if (!restored) return error.RuntimeBridgeFullscreenRestoreFailed;
        }
    }
    var monitor_supported = false;
    var platform_monitor_id: SDL_DisplayID = 0;
    var platform_monitor = SDL_Rect{ .x = 0, .y = 0, .w = 0, .h = 0 };
    if (scene.monitor != null) {
        platform_monitor_id = SDL_GetDisplayForWindow(window);
        if (platform_monitor_id != 0 and SDL_GetDisplayBounds(platform_monitor_id, &platform_monitor)) {
            monitor_supported = platform_monitor.w > 0 and platform_monitor.h > 0;
        }
    }
    var maximize_supported = false;
    if (scene.maximize != null and scene.maximize.?.flags == protocol.FrameMaximizeFlags.both) {
        if (SDL_SetWindowResizable(window, true)) {
            const requested = SDL_MaximizeWindow(window);
            maximize_supported = requested and SDL_SyncWindow(window) and
                (SDL_GetWindowFlags(window) & SDL_WINDOW_MAXIMIZED) != 0;
            const restore_required = requested or
                (SDL_GetWindowFlags(window) & SDL_WINDOW_MAXIMIZED) != 0;
            if (restore_required) {
                const restored = SDL_RestoreWindow(window) and SDL_SyncWindow(window) and
                    (SDL_GetWindowFlags(window) & SDL_WINDOW_MAXIMIZED) == 0;
                if (!restored) return error.RuntimeBridgeMaximizeRestoreFailed;
            }
        }
        _ = SDL_SetWindowResizable(window, false);
    }
    const selected_renderer = try createRenderer(gpa, window, config.renderer_request, config.present_mode);
    defer destroyRenderer(selected_renderer);

    var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
    defer draw_list.deinit();
    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var run_rendered = false;
    var face_background = false;
    var cursor_update_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 20 and fill.rect.y == 16 and fill.color.r == 0x20 and fill.color.g == 0x28 and fill.color.b == 0x38)
                    face_background = true;
                if (fill.rect.x == 24 and fill.rect.y == 20 and
                    fill.color.r == 0xff and fill.color.g == 0xd5 and fill.color.b == 0x4d)
                    cursor_update_rendered = true;
            },
            .text => |text| {
                if (text.x == 20 and text.y == 16 and text.color != null and
                    text.color.?.r == 0xff and text.color.?.g == 0xd5 and
                    std.mem.eql(u8, text.bytes, "Emacs"))
                    run_rendered = true;
            },
            else => {},
        }
    }
    if (!face_background or !run_rendered or !cursor_update_rendered)
        return error.RuntimeBridgeNotRendered;

    var frame_gate: renderer_policy.FrameGate = .{};
    var frame_counters: renderer_policy.FrameCounters = .{};
    var retained_frame: RetainedFrame = .{};
    defer destroyRetainedFrame(&retained_frame);
    var partial_capabilities: capability.Set = .{};
    partial_capabilities.insert(.damage_retained_clip);
    try presentSceneDamage(
        &scene,
        &draw_list,
        selected_renderer.handle,
        window,
        &retained_frame,
        &frame_gate,
        &frame_counters,
        .{ .kind = .initial },
        partial_capabilities,
        null,
    );
    if (frame_counters.presented_frames != 1) return error.RuntimeBridgePresentCounterInvalid;
    if (scene.frame_header) |header| {
        const presented_payload: protocol.FramePresentedPayload = .{
            .frame_generation = bridge.eup_frame_generation,
            .redisplay_generation = header.redisplay_generation,
            .frame_sequence = header.sequence,
            .presented_at_ns = frame_counters.present_last_ns,
            .frame_path_ns = frame_counters.frame_path_last_ns,
            .draw_command_count = frame_counters.draw_commands_total,
            .damage_kind = .initial,
        };
        var presented_bytes: std.ArrayList(u8) = .empty;
        defer presented_bytes.deinit(gpa);
        try protocol.encodeFramePresented(gpa, presented_payload, &presented_bytes);
        const presented = try protocol.decodeFramePresented(presented_bytes.items);
        if (presented.frame_generation != bridge.eup_frame_generation or
            presented.redisplay_generation != header.redisplay_generation or
            presented.frame_sequence != header.sequence or
            presented.presented_at_ns != frame_counters.present_last_ns or
            presented.frame_path_ns != frame_counters.frame_path_last_ns or
            presented.draw_command_count != frame_counters.draw_commands_total or
            presented.damage_kind != .initial)
            return error.RuntimeBridgePresentedFeedbackInvalid;

        const dropped_payload: protocol.FrameDroppedPayload = .{
            .frame_generation = bridge.eup_frame_generation,
            .redisplay_generation = header.redisplay_generation,
            .frame_sequence = header.sequence + 1,
            .last_presented_sequence = header.sequence,
            .observed_at_ns = frame_counters.present_last_ns + 1,
            .reason = .superseded,
        };
        var dropped_bytes: std.ArrayList(u8) = .empty;
        defer dropped_bytes.deinit(gpa);
        try protocol.encodeFrameDropped(gpa, dropped_payload, &dropped_bytes);
        const dropped = try protocol.decodeFrameDropped(dropped_bytes.items);
        if (dropped.frame_generation != bridge.eup_frame_generation or
            dropped.redisplay_generation != header.redisplay_generation or
            dropped.frame_sequence != header.sequence + 1 or
            dropped.last_presented_sequence != header.sequence or
            dropped.observed_at_ns <= presented.presented_at_ns or
            dropped.reason != .superseded)
            return error.RuntimeBridgeDroppedFeedbackInvalid;
    } else return error.RuntimeBridgeFrameHeaderInvalid;

    var scroll_scratch: ScrollCopyScratch = .{};
    defer destroyScrollCopyScratch(&scroll_scratch);
    const scroll_header = scene.frame_header orelse return error.RuntimeBridgeFrameHeaderInvalid;
    const scroll_commands = try executeScrollCopy(
        selected_renderer.handle,
        window,
        &retained_frame,
        &scroll_scratch,
        scroll_plan,
        @intCast(scroll_header.logical_width),
        @intCast(scroll_header.logical_height),
    );
    frame_counters.recordScrollCopy(scroll_plan.estimated_upload_bytes, scroll_commands);
    try presentRetainedOutput(selected_renderer.handle, retained_frame.texture.?);
    frame_counters.recordPresent(1, 1);

    const explicit_damage = [_]renderer_policy.I32Rect{.{ .x = 16, .y = 8, .width = 96, .height = 48 }};
    var explicit_payload: std.ArrayList(u8) = .empty;
    defer explicit_payload.deinit(gpa);
    try frontend.encodeDamageRects(gpa, bridge.eup_frame_generation, &.{
        .{ .x = explicit_damage[0].x, .y = explicit_damage[0].y, .width = explicit_damage[0].width, .height = explicit_damage[0].height },
    }, &explicit_payload);
    var explicit_message: std.ArrayList(u8) = .empty;
    defer explicit_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.damage_rects,
        .sequence = 33,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, explicit_payload.items, &explicit_message);
    try scene.apply(explicit_message.items);
    if (scene.damage.items.len != 1 or scene.damage.items[0].width != explicit_damage[0].width)
        return error.RuntimeBridgeDamageRectsInvalid;

    const explicit_clip = renderer_policy.explicitDamageClip(240, 96, &explicit_damage);
    if (explicit_clip == null) return error.RuntimeBridgeExplicitClipInvalid;
    frame_gate.dirty = true;
    try presentSceneDamage(
        &scene,
        &draw_list,
        selected_renderer.handle,
        window,
        &retained_frame,
        &frame_gate,
        &frame_counters,
        .{ .kind = .region, .clip = explicit_clip },
        partial_capabilities,
        explicit_clip,
    );
    if (frame_counters.explicit_damage_frames != 1 or
        frame_counters.explicit_clipped_frames != 1 or
        frame_counters.explicit_full_fallback_frames != 0 or
        frame_counters.explicit_skipped_commands == 0 or
        frame_counters.explicit_submitted_commands == 0)
        return error.RuntimeBridgeExplicitPresentInvalid;

    var key: runtime_host.InputEvent = .{
        .event_id = 11,
        .kind = runtime_bridge.input_kind_key,
        .code = 4,
    };
    var text: runtime_host.InputEvent = .{
        .event_id = 12,
        .kind = runtime_bridge.input_kind_text,
        .payload_length = 5,
    };
    @memcpy(text.payload[0..5], "Emacs");
    var sdl_key = keyEvent(&key);
    var sdl_text = textEventFromPayload(&text);
    if (!SDL_PushEvent(&sdl_key)) return sdlFail("SDL_PushEvent");
    if (!SDL_PushEvent(&sdl_text)) return sdlFail("SDL_PushEvent");

    var delivered_key = false;
    var delivered_text = false;
    var quit = false;
    const started = SDL_GetTicks();
    while (!quit and SDL_GetTicks() - started < config.auto_quit_ms) {
        var event: SDL_Event = undefined;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) {
                quit = true;
                continue;
            }
            var input: runtime_host.InputEvent = .{
                .event_id = if (!delivered_key) key.event_id else text.event_id,
                .kind = if (!delivered_key) key.kind else text.kind,
                .code = key.code,
                .payload_length = text.payload_length,
            };
            if (!delivered_text and event.type == SDL_EVENT_TEXT_INPUT) {
                const source_pointer = event.text.text orelse return error.RuntimeBridgeInputMismatch;
                const source = std.mem.span(source_pointer);
                if (source.len != text.payload_length or
                    !std.mem.eql(u8, source, text.payload[0..text.payload_length]))
                    return error.RuntimeBridgeInputMismatch;
                @memcpy(input.payload[0..text.payload_length], text.payload[0..text.payload_length]);
            } else if (!delivered_key and event.type == SDL_EVENT_KEY_DOWN) {
                input.code = std.math.cast(u32, event.key.scancode) orelse return error.RuntimeBridgeInputMismatch;
            } else continue;

            _ = try bridge.deliverInput(input);
            try bridge.deliverResult(.{
                .event_id = input.event_id,
                .command_status = @intFromEnum(runtime_host.CommandStatus.ok),
            });
            try bridge.deliverCompletion(.{
                .transaction_id = input.event_id,
                .status = .ok,
                .completed = true,
            });
            if (!delivered_key) {
                delivered_key = true;
            } else if (!delivered_text) {
                delivered_text = true;
            }
        }
        try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters);
        SDL_Delay(10);
    }
    if (!delivered_key or !delivered_text or frame_counters.text_commands_total == 0)
        return error.RuntimeBridgeNotRendered;
    std.debug.print(
        "sdl3-runtime-bridge-smoke: {{\"kind\":\"sdl3-runtime-bridge-smoke\",\"runs\":1,\"text\":\"Emacs\",\"title_applied\":true,\"session_suspend_resume\":true,\"present_feedback_codec\":true,\"geometry_scene_applied\":true,\"border_query\":{},\"icon_applied\":{},\"size_hints_applied\":{},\"z_order_applied\":{},\"parent_unparented\":{},\"cursor_update_rendered\":{},\"damage_rects\":{},\"scroll_run_plan\":{},\"scroll_copy_executed\":{},\"scroll_copy_bytes\":{},\"border_style\":{},\"divider_update\":{},\"fringe_update\":{},\"scrollbar_state\":{},\"flush_boundary\":{},\"render_hint_applied\":{},\"opacity_supported\":{},\"decorations_supported\":{},\"scale_supported\":{},\"platform_scale_milli\":{},\"fullscreen_supported\":{},\"monitor_supported\":{},\"platform_monitor_id\":{},\"platform_monitor_width\":{},\"platform_monitor_height\":{},\"maximize_supported\":{},\"explicit_submitted_commands\":{},\"explicit_skipped_commands\":{},\"inputs\":2,\"rendered\":true,\"emacs_registered\":false,\"result\":\"pass\"}}\n",
        .{
            borders_supported,
            icon_applied,
            size_hints_supported,
            z_order_supported,
            parent_unparented,
            cursor_update_rendered,
            scene.damage.items.len != 0,
            scroll_plan.estimated_upload_bytes > 0,
            frame_counters.scroll_copies == 1,
            scroll_plan.estimated_upload_bytes,
            scene.border != null,
            scene.dividers.items.len == 1,
            scene.fringes.items.len == 1,
            scene.scroll_states.items.len == 1,
            scene.flush != null,
            scene.render_hint != null,
            opacity_supported,
            decorations_supported,
            scale_supported,
            platform_scale_milli,
            fullscreen_supported,
            monitor_supported,
            platform_monitor_id,
            platform_monitor.w,
            platform_monitor.h,
            maximize_supported,
            frame_counters.explicit_submitted_commands,
            frame_counters.explicit_skipped_commands,
        },
    );
}

fn keyEvent(input: *const runtime_host.InputEvent) SDL_Event {
    return keyboardEvent(@intCast(input.code), true, 0);
}

var runtime_bridge_text_payload: [runtime_host.InputEvent.payload_bytes + 1]u8 = undefined;

fn textEventFromPayload(input: *const runtime_host.InputEvent) SDL_Event {
    @memset(&runtime_bridge_text_payload, 0);
    @memcpy(runtime_bridge_text_payload[0..input.payload_length], input.payload[0..input.payload_length]);
    return textEvent(@ptrCast(&runtime_bridge_text_payload));
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
    const negotiated = try negotiateFrontendSide(gpa, &reader.interface, &writer.interface);
    if (config.standard_session_control and !negotiated.effective.contains(.session_control_v1))
        return error.SessionControlCapabilityNotNegotiated;
    syncDeliveryCapabilities(delivery, negotiated.effective);
    if (negotiated.effective.contains(.platform_focus_window_events) != delivery.platform_negotiated)
        return error.CapabilityJournalMismatch;

    if (config.mode == .emacs_epxl_unicode_input) {
        if (!negotiated.effective.contains(.input_text_ascii) or
            !negotiated.effective.contains(.input_text_unicode))
            return error.TextCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-epxl-unicode-input-smoke: {{\"kind\":\"sdl3-epxl-unicode-input-smoke\",\"negotiated\":{{\"input.text_ascii\":true,\"input.text_unicode\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
    }

    if (config.mode == .emacs_epxl_key_v2) {
        if (!negotiated.effective.contains(.input_key_bounded) or
            !negotiated.effective.contains(.input_key_full_v2))
            return error.FullKeyCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-epxl-key-v2-smoke: {{\"kind\":\"sdl3-epxl-key-v2-smoke\",\"negotiated\":{{\"input.key_bounded\":true,\"input.key_full_v2\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
        try delivery.pushKeyV2(input_policy.translateFullKey(4, "a", true, false, input_policy.sdl_kmod_lctrl, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(8, "e", true, false, input_policy.sdl_kmod_lctrl, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(60, "F5", true, false, 0, 0).?);
    }

    reserveFrontendInputSequence(delivery);

    const use_resync = config.mode == .emacs_epxl or config.mode == .emacs_epxl_reconnect or
        config.mode == .emacs_epxl_recovery or config.mode == .emacs_epxl_input or
        config.mode == .emacs_epxl_unicode_input or config.mode == .emacs_epxl_edit or
        config.mode == .emacs_epxl_key_v2 or config.mode == .emacs_epxl_sequence;
    var scene = frontend.Scene.init(gpa);
    errdefer scene.deinit();
    var frontend_sequence: u64 = frontend_pong_sequence_start;
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
                try deliveryAllowed(delivery, negotiated.effective);
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
        if (envelope.message_type == protocol.Message.frame_update) {
            try deliveryAllowed(delivery, negotiated.effective);
            _ = try sendDeliveryEvent(gpa, delivery, config, &writer, &reader, envelope);
        }
        try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = envelope.sequence });
        try writer.interface.flush();
        if (envelope.message_type == protocol.Message.ping and
            negotiated.effective.contains(.session_control_v1))
        {
            if (frontend_sequence == std.math.maxInt(u64)) return error.InvalidSequence;
            const ping_wire = try protocol.decodeEnvelope(message);
            const ping = try session_codec.decodePing(ping_wire.bytes);
            var pong_payload: std.ArrayList(u8) = .empty;
            defer pong_payload.deinit(gpa);
            try session_codec.encodePong(gpa, .{ .original_timestamp_ns = ping.timestamp_ns }, &pong_payload);
            // Keep the liveness correlation in the PONG payload.  The envelope
            // timestamp remains a fresh monotonic sender timestamp as required
            // by the EUP envelope contract.
            const pong_timestamp_ns: u64 = @intCast(
                std.Io.Timestamp.now(io, .awake).nanoseconds,
            );
            try scene.control.apply(protocol.Message.pong, pong_payload.items);
            var pong: std.ArrayList(u8) = .empty;
            defer pong.deinit(gpa);
            try protocol.encodeEnvelope(gpa, .{
                .flags = 0,
                .message_type = protocol.Message.pong,
                .sequence = frontend_sequence,
                .ack_sequence = 0,
                .session_id = envelope.session_id,
                .frame_id = 0,
                .timestamp_ns = pong_timestamp_ns,
            }, pong_payload.items, &pong);
            try live.writeFrame(&writer.interface, pong.items);
            try writer.interface.flush();
            const pong_ack = try readControlExact(&reader);
            if (pong_ack.kind != .ack or pong_ack.sequence != frontend_sequence)
                return error.ExpectedPongAck;
            frontend_sequence += 1;
        }
        if (use_resync and !resync_complete) return error.IncompleteResync;
    }
    if (use_resync and !resync_complete) return error.IncompleteResync;
    if (scene.stats.frame_updates == 0) return error.NoFrameUpdate;
    return scene;
}

fn runVersionMismatchFrontend(
    gpa: std.mem.Allocator,
    io: std.Io,
    config: *const Config,
) !frontend.Scene {
    const address = try std.Io.net.UnixAddress.init(config.endpoint);
    var stream: std.Io.net.Stream = undefined;
    var connected = false;
    try io.sleep(.fromMilliseconds(10), .awake);
    for (0..200) |_| {
        stream = address.connect(io) catch {
            try io.sleep(.fromMilliseconds(10), .awake);
            continue;
        };
        connected = true;
        break;
    }
    if (!connected) return error.VersionMismatchEndpointUnavailable;
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
    const negotiated = try negotiateFrontendSide(gpa, &reader.interface, &writer.interface);
    if (!negotiated.effective.contains(.session_control_v1))
        return error.SessionControlCapabilityNotNegotiated;

    var scene = frontend.Scene.init(gpa);
    errdefer scene.deinit();
    const message = (try live.readFrame(&reader.interface, gpa)) orelse return error.ExpectedVersionMismatch;
    defer gpa.free(message);
    const wire = try protocol.decodeEnvelope(message);
    if (wire.envelope.message_type != protocol.Message.version_mismatch or
        wire.envelope.sequence != 5 or
        wire.envelope.session_id != capability.session_id or
        wire.envelope.frame_id != 0) return error.ExpectedVersionMismatch;
    const mismatch = try session_codec.decodeVersionMismatch(wire.bytes);
    if (mismatch.required_major != 1 or mismatch.required_minor != 0 or
        mismatch.observed_major != 2 or mismatch.observed_minor != 0)
        return error.ExpectedVersionMismatch;
    try scene.apply(message);
    try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = wire.envelope.sequence });
    try writer.interface.flush();
    if (scene.control.stage != .fatal) return error.VersionMismatchNotFatal;
    return scene;
}

fn boundedPointerCoordinate(value: f32) ?i32 {
    if (!std.math.isFinite(value)) return null;
    if (value < 0 or value > @as(f32, @floatFromInt(frontend.max_pointer_coordinate))) return null;
    return @intFromFloat(value);
}

fn inputEventAllowed(capabilities: capability.Set, event: input_policy.TranslatedEvent) bool {
    return switch (event) {
        .text => |text| if (input_policy.isAsciiText(text.bytes()))
            capabilities.contains(.input_text_ascii) or capabilities.contains(.input_text_unicode)
        else
            capabilities.contains(.input_text_unicode),
        .key => capabilities.contains(.input_key_bounded),
        .key_v2 => capabilities.contains(.input_key_full_v2),
        .pointer => capabilities.contains(.input_pointer_bounded),
        .pointer_v2 => capabilities.contains(.input_pointer_v2),
        .wheel => capabilities.contains(.input_wheel_line),
        .focus => capabilities.contains(.platform_focus_window_events),
        .window => capabilities.contains(.platform_focus_window_events),
    };
}

fn enqueueSdlFullKey(
    delivery: *input_policy.DeliveryJournal,
    event_key: SDL_KeyboardEvent,
    capabilities: capability.Set,
) !bool {
    if (!capabilities.contains(.input_key_full_v2)) return false;
    const translated = input_policy.translateFullKey(
        event_key.scancode,
        SDL_GetKeyName(event_key.key),
        event_key.down,
        event_key.repeat,
        event_key.modifiers,
        @intCast(event_key.which),
    ) orelse return false;
    if (event_key.down and !event_key.repeat and
        input_policy.duplicatesTextInput(translated) and
        (capabilities.contains(.input_text_ascii) or capabilities.contains(.input_text_unicode)))
        return true;
    try delivery.pushKeyV2(translated);
    return true;
}

fn textSupportFor(capabilities: capability.Set) ?input_policy.TextSupport {
    if (capabilities.contains(.input_text_unicode)) return .unicode;
    if (capabilities.contains(.input_text_ascii)) return .ascii;
    return null;
}

fn deliveryAllowed(delivery: *input_policy.DeliveryJournal, capabilities: capability.Set) !void {
    if (delivery.pending) |event| {
        if (!inputEventAllowed(capabilities, event)) return error.CapabilityNotNegotiated;
    }
    for (delivery.queue.items[0..delivery.queue.length]) |event| {
        if (!inputEventAllowed(capabilities, event)) return error.CapabilityNotNegotiated;
    }
}

fn clipboardSupportFor(capabilities: capability.Set) ?input_policy.TextSupport {
    if (!capabilities.contains(.clipboard_ascii_bounded)) return null;
    return if (capabilities.contains(.clipboard_text_unicode))
        .unicode
    else
        .ascii;
}

fn syncDeliveryCapabilities(delivery: *input_policy.DeliveryJournal, capabilities: capability.Set) void {
    delivery.key_v2_negotiated = capabilities.contains(.input_key_full_v2);
    delivery.pointer_v2_negotiated = capabilities.contains(.input_pointer_v2);
    delivery.platform_negotiated = capabilities.contains(.platform_focus_window_events);
}

fn usePointerV2(capabilities: capability.Set, config: *const Config) bool {
    return capabilities.contains(.input_pointer_v2) and config.synthetic_pointer_v2;
}

fn pollEpxlInteractiveInput(
    delivery: *input_policy.DeliveryJournal,
    config: *const Config,
    retained: *RetainedFrame,
    scene: *frontend.Scene,
    gate: *renderer_policy.FrameGate,
    capabilities: capability.Set,
    dirty: *bool,
) !void {
    var event: SDL_Event = undefined;
    while (SDL_PollEvent(&event)) {
        switch (event.type) {
            SDL_EVENT_QUIT => return error.InteractiveQuit,
            SDL_EVENT_KEY_DOWN, SDL_EVENT_KEY_UP => {
                const is_paste = input_policy.isPasteShortcut(
                    event.key.scancode,
                    event.key.down,
                    event.key.repeat,
                    event.key.modifiers,
                );
                const is_copy = input_policy.isCopyShortcut(
                    event.key.scancode,
                    event.key.down,
                    event.key.repeat,
                    event.key.modifiers,
                );
                if (event.type == SDL_EVENT_KEY_DOWN and is_paste) {
                    if (clipboardSupportFor(capabilities)) |support| {
                        if (try queueClipboardText(delivery, support)) dirty.* = true;
                    }
                } else if (event.type == SDL_EVENT_KEY_DOWN and is_copy and
                    capabilities.contains(.clipboard_ascii_bounded))
                {
                    try delivery.pushKey(.{ .action = .copy });
                    dirty.* = true;
                } else if (try enqueueSdlFullKey(delivery, event.key, capabilities)) {
                    dirty.* = true;
                } else if (event.type == SDL_EVENT_KEY_DOWN) {
                    if (input_policy.translateKey(
                        event.key.scancode,
                        event.key.down,
                        event.key.repeat,
                        event.key.modifiers,
                    )) |key| {
                        try delivery.pushKey(key);
                        dirty.* = true;
                    }
                }
            },
            SDL_EVENT_TEXT_INPUT => {
                if (textSupportFor(capabilities)) |support| {
                    if (input_policy.translateText(event.text.text, support)) |text| {
                        try delivery.pushTextAllowed(text.bytes(), support);
                        dirty.* = true;
                    }
                }
            },
            input_policy.SDL_EVENT_WINDOW_FOCUS_GAINED,
            input_policy.SDL_EVENT_WINDOW_FOCUS_LOST,
            => {
                if (input_policy.platformEventsNegotiated(
                    delivery,
                    capabilities.contains(.platform_focus_window_events),
                )) {
                    if (scene.frame_header) |header| {
                        if (input_policy.translateFocus(
                            event.type,
                            header.frame_id,
                            event.window.window_id,
                        )) |focus| {
                            if (try delivery.pushFocusIfNegotiated(
                                capabilities.contains(.platform_focus_window_events),
                                focus,
                            )) dirty.* = true;
                        }
                    }
                }
            },
            input_policy.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
            input_policy.SDL_EVENT_WINDOW_RESIZED,
            input_policy.SDL_EVENT_WINDOW_MOVED,
            input_policy.SDL_EVENT_WINDOW_MINIMIZED,
            input_policy.SDL_EVENT_WINDOW_MAXIMIZED,
            input_policy.SDL_EVENT_WINDOW_RESTORED,
            => {
                if (input_policy.platformEventsNegotiated(
                    delivery,
                    capabilities.contains(.platform_focus_window_events),
                )) {
                    if (scene.frame_header != null) {
                        if (input_policy.translateWindow(
                            event.type,
                            event.window.window_id,
                            event.window.data1,
                            event.window.data2,
                        )) |request| {
                            if (try delivery.pushWindowIfNegotiated(
                                capabilities.contains(.platform_focus_window_events),
                                request,
                            )) dirty.* = true;
                        }
                    }
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
                if (config.interactive_synthetic and !config.synthetic_pointer and !config.synthetic_pointer_v2) return;
                const x = boundedPointerCoordinate(event.motion.x) orelse return;
                const y = boundedPointerCoordinate(event.motion.y) orelse return;
                if (usePointerV2(capabilities, config)) {
                    const translated = input_policy.translatePointerV2(.{
                        .event_type = event.type,
                        .x = x,
                        .y = y,
                        .state = event.motion.state,
                        .modifiers = input_policy.sdlModifiersToEup(SDL_GetModState()),
                    }) orelse return;
                    delivery.pushPointerV2(translated) catch |err| switch (err) {
                        error.PointerSessionActive => return,
                        else => return err,
                    };
                } else {
                    const dragging = event.motion.state == SDL_BUTTON_LMASK;
                    if (event.motion.state != 0 and !dragging) return;
                    if (dragging != delivery.pointer_active) return;
                    if (!dragging and (delivery.pending != null or delivery.queue.length > 0)) return;
                    // Idle motion is best-effort and coalesced to the idle boundary.
                    // Drag motion is ordered because the left pointer session is active.
                    try delivery.pushPointer(.{
                        .phase = .motion,
                        .button = if (dragging) 1 else 0,
                        .x = x,
                        .y = y,
                    });
                }
                dirty.* = true;
            },
            SDL_EVENT_MOUSE_BUTTON_DOWN, SDL_EVENT_MOUSE_BUTTON_UP => {
                if (config.interactive_synthetic and !config.synthetic_pointer and !config.synthetic_pointer_v2) return;
                const down = event.type == SDL_EVENT_MOUSE_BUTTON_DOWN;
                if (down != event.button.down) return;
                const x = boundedPointerCoordinate(event.button.x) orelse return;
                const y = boundedPointerCoordinate(event.button.y) orelse return;
                if (usePointerV2(capabilities, config)) {
                    const translated = input_policy.translatePointerV2(.{
                        .event_type = event.type,
                        .sdl_button = event.button.button,
                        .down = down,
                        .clicks = event.button.clicks,
                        .x = x,
                        .y = y,
                        .modifiers = input_policy.sdlModifiersToEup(SDL_GetModState()),
                    }) orelse return;
                    delivery.pushPointerV2(translated) catch |err| switch (err) {
                        error.PointerSessionActive => return,
                        else => return err,
                    };
                    dirty.* = true;
                    return;
                }
                if (event.button.button == 1 and event.button.clicks == 1) {
                    delivery.pushPointer(.{
                        .phase = if (down) .press else .release,
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
    const negotiated = try negotiateFrontendSide(gpa, &reader.interface, &writer.interface);
    syncDeliveryCapabilities(delivery, negotiated.effective);
    if (negotiated.effective.contains(.platform_focus_window_events) != delivery.platform_negotiated)
        return error.CapabilityJournalMismatch;

    if (config.mode == .emacs_clipboard_unicode) {
        if (!negotiated.effective.contains(.clipboard_ascii_bounded) or
            !negotiated.effective.contains(.clipboard_text_unicode))
            return error.ClipboardCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-clipboard-unicode-smoke: {{\"kind\":\"sdl3-clipboard-unicode-smoke\",\"negotiated\":{{\"clipboard.ascii_bounded\":true,\"clipboard.text_unicode\":true,\"platform_focus_window_events\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
    }
    if (config.mode == .emacs_pointer_selection) {
        if (!negotiated.effective.contains(.input_pointer_v2) or
            !negotiated.effective.contains(.input_pointer_selection_left))
            return error.PointerSelectionCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-pointer-selection-smoke: {{\"kind\":\"sdl3-pointer-selection-smoke\",\"negotiated\":{{\"input.pointer_v2\":true,\"input.pointer_selection_left\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
    }
    if (config.mode == .emacs_pointer_middle_paste) {
        if (!negotiated.effective.contains(.input_pointer_v2) or
            !negotiated.effective.contains(.input_pointer_selection_left) or
            !negotiated.effective.contains(.input_pointer_middle_paste))
            return error.PointerMiddlePasteCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-pointer-middle-paste-smoke: {{\"kind\":\"sdl3-pointer-middle-paste-smoke\",\"negotiated\":{{\"input.pointer_v2\":true,\"input.pointer_selection_left\":true,\"input.pointer_middle_paste\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
    }

    reserveFrontendInputSequence(delivery);

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
        if (envelope.message_type == protocol.Message.frame_update) {
            try deliveryAllowed(delivery, negotiated.effective);
            _ = try sendDeliveryEvent(gpa, delivery, config, &writer, &reader, envelope);
        }
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
    var selection_copy_applied = false;
    var left_release_sequence: u64 = 0;
    var middle_release_sequence: u64 = 0;
    var paste_unicode_applied = false;
    var copy_unicode_exact = false;
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
    if (config.synthetic_clipboard_unicode) {
        if (!SDL_SetClipboardText("你好")) return sdlFail("SDL_SetClipboardText");
        var paste = keyboardEvent(input_policy.SDL_SCANCODE_V, true, input_policy.sdl_ctrl_modifiers);
        if (!SDL_PushEvent(&paste)) return sdlFail("SDL_PushEvent");
        var copy = keyboardEvent(input_policy.SDL_SCANCODE_C, true, input_policy.sdl_ctrl_modifiers);
        if (!SDL_PushEvent(&copy)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_wheel) {
        var down = wheelEvent(1);
        if (!SDL_PushEvent(&down)) return sdlFail("SDL_PushEvent");
        if (!config.synthetic_viewport) {
            var up = wheelEvent(-1);
            if (!SDL_PushEvent(&up)) return sdlFail("SDL_PushEvent");
        }
    }
    if (config.synthetic_pointer_selection) {
        var press = pointerButtonEvent(0, 0, SDL_EVENT_MOUSE_BUTTON_DOWN, true, 1, 1);
        if (!SDL_PushEvent(&press)) return sdlFail("SDL_PushEvent");
        var drag = pointerMotionEventV2(5, 0, input_policy.pointer_button_left, 0);
        if (!SDL_PushEvent(&drag)) return sdlFail("SDL_PushEvent");
        var release = pointerButtonEvent(5, 0, SDL_EVENT_MOUSE_BUTTON_UP, false, 1, 1);
        if (!SDL_PushEvent(&release)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_pointer_middle_paste) {
        var press = pointerButtonEvent(5, 0, SDL_EVENT_MOUSE_BUTTON_DOWN, true, 2, 1);
        if (!SDL_PushEvent(&press)) return sdlFail("SDL_PushEvent");
        var release = pointerButtonEvent(5, 0, SDL_EVENT_MOUSE_BUTTON_UP, false, 2, 1);
        if (!SDL_PushEvent(&release)) return sdlFail("SDL_PushEvent");
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
    try pollEpxlInteractiveInput(delivery, config, &retained_frame, &scene, &frame_gate, negotiated.effective, &input_dirty);
    try deliveryAllowed(delivery, negotiated.effective);

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
                    .pointer_v2 => |pointer| if (pointer.phase == .release) {
                        pointer_release_delivered = true;
                        if (pointer.buttons == input_policy.pointer_button_left)
                            left_release_sequence = outcome.delivered.sequence;
                        if (pointer.buttons == input_policy.pointer_button_middle)
                            middle_release_sequence = outcome.delivered.sequence;
                    },
                    .wheel => |wheel| wheel_ticks_delivered += @abs(wheel.y),
                    else => {},
                }
            }
        }
        try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = envelope.sequence });
        try writer.interface.flush();
        pollEpxlInteractiveInput(delivery, config, &retained_frame, &scene, &frame_gate, negotiated.effective, &input_dirty) catch |err| switch (err) {
            error.InteractiveQuit => quit = true,
            else => return err,
        };
        try deliveryAllowed(delivery, negotiated.effective);
        const clipboard_bytes = std.Io.Dir.cwd().readFileAlloc(io, clipboard_path, gpa, .limited(input_policy.max_clipboard_artifact_bytes + 1)) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (clipboard_bytes) |bytes| {
            defer gpa.free(bytes);
            var unicode_artifact = false;
            var clipboard_text: []const u8 = bytes;
            var decoded_text: ?[]u8 = null;
            defer if (decoded_text) |owned| gpa.free(owned);
            if (std.mem.startsWith(u8, bytes, input_policy.clipboard_artifact_prefix)) {
                unicode_artifact = true;
                decoded_text = input_policy.decodeClipboardArtifact(gpa, bytes) catch null;
                clipboard_text = decoded_text orelse "";
            }
            const expected_copy: ?[]const u8 = if (config.synthetic_clipboard_unicode)
                "Emacs 你好"
            else if (config.synthetic_copy)
                "Emacs Proto-UI"
            else if (config.synthetic_pointer_selection)
                "Emacs"
            else
                null;
            const clipboard_support = clipboardSupportFor(negotiated.effective);
            const expected_exact = expected_copy == null or
                std.mem.eql(u8, clipboard_text, expected_copy.?);
            const accepted = clipboard_text.len != 0 and
                input_policy.validClipboardText(clipboard_text) and
                clipboard_support != null and
                (if (clipboard_support) |support|
                    (unicode_artifact == (support == .unicode))
                else
                    false) and
                expected_exact;
            if (accepted) {
                try setPlatformClipboard(clipboard_text);
                _ = std.Io.Dir.cwd().deleteFile(io, clipboard_path) catch {};
                copy_applied = true;
                selection_copy_applied = selection_copy_applied or
                    (config.synthetic_pointer_selection and
                        std.mem.eql(u8, clipboard_text, "Emacs"));
                if (config.synthetic_clipboard_unicode) {
                    copy_unicode_exact = unicode_artifact;
                    if (SDL_GetClipboardText()) |owned| {
                        copy_unicode_exact = copy_unicode_exact and
                            std.mem.eql(u8, std.mem.span(owned), "Emacs 你好");
                        SDL_free(owned);
                    }
                }
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
                negotiated.effective,
                null,
            );
        } else {
            try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters);
        }
    }

    if (scene.stats.frame_updates < 2) return error.UnexpectedFactUpdateCount;
    if (config.mode == .emacs_clipboard_unicode) {
        paste_unicode_applied = sceneHasText(&scene, "你好") and
            sceneHasText(&scene, "Emacs Proto-UI") and
            sceneHasText(&scene, "visible ASCII text");
        if (!paste_unicode_applied) return error.ClipboardPasteNotApplied;
        if (!copy_applied or !copy_unicode_exact) return error.ClipboardCopyNotApplied;
        std.debug.print(
            "sdl3-clipboard-unicode-smoke: {{\"kind\":\"sdl3-clipboard-unicode-smoke\",\"paste\":\"你好\",\"marker\":\"visible ASCII text\",\"copy\":\"Emacs 你好\",\"copy_bytes_exact\":true,\"result\":\"pass\"}}\n",
            .{},
        );
    }
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
    if (config.synthetic_pointer_selection) {
        if (!pointer_release_delivered) return error.PointerSelectionReleaseNotDelivered;
        if (!selection_copy_applied) return error.PointerSelectionClipboardMismatch;
        std.debug.print(
            "sdl3-pointer-selection-smoke: {{\"kind\":\"sdl3-pointer-selection-smoke\",\"release_delivered\":true,\"clipboard\":\"Emacs\",\"result\":\"pass\"}}\n",
            .{},
        );
    }
    if (config.mode == .emacs_pointer_middle_paste) {
        if (left_release_sequence == 0) return error.PointerSelectionReleaseNotDelivered;
        if (middle_release_sequence == 0) return error.PointerMiddlePasteReleaseNotDelivered;
        if (left_release_sequence >= middle_release_sequence)
            return error.PointerMiddlePasteOutOfOrder;
        const pasted = scene.text.items.len > 0 and
            std.mem.eql(u8, scene.text.items[0].bytes, "EmacsEmacs Proto-UI");
        if (!pasted) return error.PointerMiddlePasteNotApplied;
        std.debug.print(
            "sdl3-pointer-middle-paste-smoke: {{\"kind\":\"sdl3-pointer-middle-paste-smoke\",\"left_release\":{d},\"middle_release\":{d},\"first_line\":\"EmacsEmacs Proto-UI\",\"result\":\"pass\"}}\n",
            .{ left_release_sequence, middle_release_sequence },
        );
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

fn spanInside(offset: i32, extent: i32, limit: i32) bool {
    return offset >= 0 and extent >= 0 and limit >= 0 and
        offset <= limit and extent <= limit - offset;
}

fn debugTextOrigin(owner: frontend.Window, row: frontend.Row) struct { x: i64, y: i64 } {
    const baseline_offset: i64 = @max(1, @as(i64, row.baseline) - debug_text_character_size);
    return .{
        .x = @as(i64, owner.x) + row.x + 2,
        .y = @as(i64, owner.y) + row.y + baseline_offset,
    };
}

fn publicFactsGlyphRun(
    scene: *const frontend.Scene,
    text: []const u8,
) !frontend.GlyphRunWire {
    if (text.len == 0 or text.len > frontend.max_glyph_text_bytes or
        scene.windows.items.len == 0 or scene.rows.items.len == 0 or
        scene.text.items.len != 1)
        return error.GlyphRunSceneStateInvalid;
    const observed = scene.text.items[0];
    if (!std.mem.eql(u8, observed.bytes, text) or
        observed.row_index >= scene.rows.items.len)
        return error.GlyphRunSceneStateInvalid;
    const owner = scene.windows.items[0];
    const row = scene.rows.items[observed.row_index];
    if (row.window_id != owner.id or row.index != 0 or row.visible_height <= 0)
        return error.GlyphRunSceneStateInvalid;
    const origin = debugTextOrigin(owner, row);
    const x = std.math.cast(i32, origin.x - owner.x) orelse return error.InvalidTextGeometry;
    const y = std.math.cast(i32, origin.y - owner.y) orelse return error.InvalidTextGeometry;
    const width = std.math.cast(
        i32,
        text.len * @as(usize, @intCast(debug_text_character_size)),
    ) orelse return error.InvalidTextGeometry;
    if (!spanInside(x, width, owner.width) or
        !spanInside(y, row.visible_height, owner.height))
        return error.InvalidTextGeometry;
    return .{
        .run_id = 1,
        .generation = 1,
        .window_id = owner.id,
        .row_index = row.index,
        .x = x,
        .y = y,
        .width = width,
        .height = row.visible_height,
        .text = text,
    };
}

fn rowHasGlyphRun(scene: *const frontend.Scene, window_id: u64, row_index: u32) bool {
    for (scene.glyph_runs.items) |run| {
        if (run.window_id == window_id and run.row_index == row_index) return true;
    }
    return false;
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

    for (scene.clear_areas.items) |area| {
        const owner = findSceneWindow(scene, area.window_id) orelse continue;
        const face = scene.faces.lookup(area.face_id) orelse continue;
        if (face.generation != area.face_generation or !face.payload.presence.background) continue;
        try list.fillRect(.{
            .x = @floatFromInt(owner.x + area.rect.x),
            .y = @floatFromInt(owner.y + area.rect.y),
            .width = @floatFromInt(area.rect.width),
            .height = @floatFromInt(area.rect.height),
        }, .{
            .r = face.payload.background[0],
            .g = face.payload.background[1],
            .b = face.payload.background[2],
            .a = face.payload.background[3],
        });
    }

    for (scene.fringes.items) |fringe| {
        const owner = findSceneWindow(scene, fringe.window_id) orelse continue;
        const rect = frontend.fringeRect(fringe, owner.width);
        try list.fillRect(.{
            .x = @floatFromInt(owner.x + rect.x),
            .y = @floatFromInt(owner.y + rect.y),
            .width = @floatFromInt(rect.width),
            .height = @floatFromInt(rect.height),
        }, .{ .r = fringe.color[0], .g = fringe.color[1], .b = fringe.color[2], .a = fringe.color[3] });
    }

    for (scene.scroll_states.items) |state| {
        const owner = findSceneWindow(scene, state.window_id) orelse continue;
        if (state.flags & frontend.WindowScrollFlags.vertical_visible == 0) continue;
        const x: f32 = @floatFromInt(owner.x + owner.width - @as(i32, @intCast(state.track_width)));
        const track = renderer_policy.LogicalRect{
            .x = x,
            .y = @floatFromInt(owner.y),
            .width = @floatFromInt(state.track_width),
            .height = @floatFromInt(owner.height),
        };
        try list.fillRect(track, .{ .r = 0x20, .g = 0x24, .b = 0x2c, .a = 255 });
        const scrollable: f32 = @floatFromInt(state.content_size - state.viewport_size);
        const ratio: f32 = if (scrollable > 0) @as(f32, @floatFromInt(state.position)) / scrollable else 0;
        const thumb_height: f32 = track.height * (@as(f32, @floatFromInt(state.viewport_size)) / @as(f32, @floatFromInt(state.content_size)));
        try list.fillRect(.{
            .x = track.x,
            .y = track.y + (track.height - thumb_height) * ratio,
            .width = track.width,
            .height = thumb_height,
        }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2, .a = 255 });
    }

    for (scene.dividers.items) |divider| {
        const owner = findSceneWindow(scene, divider.window_id) orelse continue;
        const rect = frontend.dividerRect(divider);
        try list.fillRect(.{
            .x = @floatFromInt(owner.x + rect.x),
            .y = @floatFromInt(owner.y + rect.y),
            .width = @floatFromInt(rect.width),
            .height = @floatFromInt(rect.height),
        }, .{ .r = 0x8a, .g = 0x2b, .b = 0x5a, .a = 255 });
    }

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
        if (rowHasGlyphRun(scene, owner.id, row.index)) continue;
        // The ASCII bitmap path has no text shaping or CJK font fallback.
        // Unicode is still observed and asserted by the EPXL smoke.
        if (!input_policy.isAsciiText(line.bytes)) continue;
        const origin = debugTextOrigin(owner, row);
        const text_x: i64 = origin.x;
        const text_y: i64 = origin.y;
        if (text_x < std.math.minInt(i32) or text_x > std.math.maxInt(i32) or
            text_y < std.math.minInt(i32) or text_y > std.math.maxInt(i32)) return error.InvalidTextGeometry;
        try list.drawText(
            @floatFromInt(text_x),
            @floatFromInt(text_y),
            line.bytes,
            null,
        );
    }

    for (scene.image_placements[0..scene.image_placement_count]) |placement| {
        const image = scene.images.lookup(placement.image_id) orelse continue;
        if (!image.complete or image.generation != placement.image_generation) continue;
        const owner = findSceneWindow(scene, placement.window_id) orelse continue;
        try list.drawImage(.{
            .x = @floatFromInt(owner.x + placement.x),
            .y = @floatFromInt(owner.y + placement.y),
            .width = @floatFromInt(placement.width),
            .height = @floatFromInt(placement.height),
        }, image.bytes, image.metadata.width, image.metadata.height);
    }

    for (scene.glyph_runs.items) |run| {
        const owner = findSceneWindow(scene, run.window_id) orelse continue;
        const face = if (run.face_id == 0) null else scene.faces.lookup(run.face_id);
        if (face) |resource| {
            if (resource.payload.presence.background) {
                try list.fillRect(.{
                    .x = @floatFromInt(owner.x + run.x),
                    .y = @floatFromInt(owner.y + run.y),
                    .width = @floatFromInt(run.width),
                    .height = @floatFromInt(run.height),
                }, .{
                    .r = resource.payload.background[0],
                    .g = resource.payload.background[1],
                    .b = resource.payload.background[2],
                    .a = resource.payload.background[3],
                });
            }
        }
        const foreground: ?renderer_policy.Color = if (face) |resource| (if (resource.payload.presence.foreground) renderer_policy.Color{
            .r = resource.payload.foreground[0],
            .g = resource.payload.foreground[1],
            .b = resource.payload.foreground[2],
            .a = resource.payload.foreground[3],
        } else null) else null;
        if (face) |resource| {
            const decorations = renderer_policy.faceDecorationBars(
                @floatFromInt(owner.x + run.x),
                @floatFromInt(owner.y + run.y),
                @floatFromInt(run.width),
                @floatFromInt(run.height),
                .{
                    .underline = @enumFromInt(@intFromEnum(resource.payload.underline)),
                    .overline = @enumFromInt(@intFromEnum(resource.payload.overline)),
                    .strike_through = @enumFromInt(@intFromEnum(resource.payload.strike_through)),
                    .box = @enumFromInt(@intFromEnum(resource.payload.box)),
                    .underline_color = if (resource.payload.presence.underline_color)
                        renderer_policy.Color{ .r = resource.payload.underline_color[0], .g = resource.payload.underline_color[1], .b = resource.payload.underline_color[2], .a = resource.payload.underline_color[3] }
                    else
                        null,
                    .overline_color = if (resource.payload.presence.overline_color)
                        renderer_policy.Color{ .r = resource.payload.overline_color[0], .g = resource.payload.overline_color[1], .b = resource.payload.overline_color[2], .a = resource.payload.overline_color[3] }
                    else
                        null,
                    .strike_color = if (resource.payload.presence.strike_color)
                        renderer_policy.Color{ .r = resource.payload.strike_color[0], .g = resource.payload.strike_color[1], .b = resource.payload.strike_color[2], .a = resource.payload.strike_color[3] }
                    else
                        null,
                    .box_color = if (resource.payload.presence.box_color)
                        renderer_policy.Color{ .r = resource.payload.box_color[0], .g = resource.payload.box_color[1], .b = resource.payload.box_color[2], .a = resource.payload.box_color[3] }
                    else
                        null,
                    .foreground = foreground,
                },
            );
            for (decorations.slice()) |bar| {
                try list.fillRect(bar.rect, bar.color);
            }
        }
        // GLYPH_RUN remains bounded ASCII fallback; face color does not imply
        // shaped text, fonts, atlas rendering, or full Emacs face parity.
        try list.drawText(
            @floatFromInt(owner.x + run.x),
            @floatFromInt(owner.y + run.y),
            run.text,
            foreground,
        );
    }

    for (scene.windows.items) |window| {
        const border = scene.border;
        const thickness: f32 = if (border) |state|
            @floatFromInt(state.thickness)
        else
            pixel;
        const color: renderer_policy.Color = if (border) |state|
            .{ .r = state.color[0], .g = state.color[1], .b = state.color[2], .a = state.color[3] }
        else
            .{ .r = 0x71, .g = 0xa6, .b = 0xf2 };
        const sides: u8 = if (border) |state|
            state.sides
        else
            frontend.BorderSides.top | frontend.BorderSides.right |
                frontend.BorderSides.bottom | frontend.BorderSides.left;
        if (sides & frontend.BorderSides.top != 0) {
            try list.fillRect(.{
                .x = @floatFromInt(window.x),
                .y = @floatFromInt(window.y),
                .width = @floatFromInt(window.width),
                .height = thickness,
            }, color);
        }
        if (sides & frontend.BorderSides.bottom != 0) {
            try list.fillRect(.{
                .x = @floatFromInt(window.x),
                .y = @as(f32, @floatFromInt(window.y + window.height)) - thickness,
                .width = @floatFromInt(window.width),
                .height = thickness,
            }, color);
        }
        if (sides & frontend.BorderSides.left != 0) {
            try list.fillRect(.{
                .x = @floatFromInt(window.x),
                .y = @floatFromInt(window.y),
                .width = thickness,
                .height = @floatFromInt(window.height),
            }, color);
        }
        if (sides & frontend.BorderSides.right != 0) {
            try list.fillRect(.{
                .x = @as(f32, @floatFromInt(window.x + window.width)) - thickness,
                .y = @floatFromInt(window.y),
                .width = thickness,
                .height = @floatFromInt(window.height),
            }, color);
        }
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
    cull_explicit_damage: bool,
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
        if (cull_explicit_damage) {
            executed.examined_commands += 1;
            if (!renderer_policy.drawCommandIntersectsClip(command, clip orelse
                renderer_policy.LogicalRect{ .x = 0, .y = 0, .width = 0, .height = 0 }))
            {
                executed.skipped_commands += 1;
                continue;
            }
        }
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
            .image => |draw| {
                const texture = SDL_CreateTexture(
                    renderer,
                    SDL_PIXELFORMAT_RGBA8888,
                    SDL_TEXTUREACCESS_TARGET,
                    @intCast(draw.width),
                    @intCast(draw.height),
                ) orelse return sdlFail("SDL_CreateTexture");
                defer SDL_DestroyTexture(texture);
                if (!SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_NEAREST)) return sdlFail("SDL_SetTextureScaleMode");
                if (!SDL_UpdateTexture(texture, null, draw.pixels.ptr, @intCast(draw.width * 4))) return sdlFail("SDL_UpdateTexture");
                const destination = SDL_FRect{
                    .x = draw.rect.x * @as(f32, @floatFromInt(output_width)) / list.logical_width,
                    .y = draw.rect.y * @as(f32, @floatFromInt(output_height)) / list.logical_height,
                    .w = draw.rect.width * @as(f32, @floatFromInt(output_width)) / list.logical_width,
                    .h = draw.rect.height * @as(f32, @floatFromInt(output_height)) / list.logical_height,
                };
                if (!SDL_RenderTexture(renderer, texture, null, &destination)) return sdlFail("SDL_RenderTexture");
                executed.commands += 1;
                executed.images += 1;
            },
            .text => |draw| {
                var text: [121]u8 = undefined;
                @memcpy(text[0..draw.bytes.len], draw.bytes);
                text[draw.bytes.len] = 0;
                if (draw.color) |color| {
                    if (!SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)) return sdlFail("SDL_SetRenderDrawColor");
                }
                const rendered = SDL_RenderDebugText(
                    renderer,
                    draw.x * @as(f32, @floatFromInt(output_width)) / list.logical_width,
                    draw.y * @as(f32, @floatFromInt(output_height)) / list.logical_height,
                    text[0..draw.bytes.len :0],
                );
                if (draw.color) |_| {
                    if (!SDL_SetRenderDrawColor(renderer, 0xd8, 0xd8, 0xd8, 255)) return sdlFail("SDL_SetRenderDrawColor");
                }
                if (!rendered) return sdlFail("SDL_RenderDebugText");
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

const ScrollCopyScratch = struct {
    texture: ?*SDL_Texture = null,
    width: c_int = 0,
    height: c_int = 0,
};

fn destroyScrollCopyScratch(scratch: *ScrollCopyScratch) void {
    if (scratch.texture) |texture| SDL_DestroyTexture(texture);
    scratch.* = .{};
}

fn scrollCopyScratchTexture(
    renderer: *SDL_Renderer,
    scratch: *ScrollCopyScratch,
    width: c_int,
    height: c_int,
) ?*SDL_Texture {
    if (width <= 0 or height <= 0) return null;
    if (scratch.width != width or scratch.height != height) destroyScrollCopyScratch(scratch);
    if (scratch.texture) |texture| return texture;

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
    scratch.* = .{ .texture = texture, .width = width, .height = height };
    return texture;
}

fn executeScrollCopy(
    renderer: *SDL_Renderer,
    window: *SDL_Window,
    retained: *RetainedFrame,
    scratch: *ScrollCopyScratch,
    plan: renderer_policy.ScrollCopyPlan,
    logical_width: i32,
    logical_height: i32,
) !u64 {
    if (retained.texture == null or !retained.primed or
        logical_width <= 0 or logical_height <= 0) return error.ScrollCopyTargetInvalid;
    var output_width: c_int = 0;
    var output_height: c_int = 0;
    SDL_GetWindowSize(window, &output_width, &output_height);
    if (output_width <= 0 or output_height <= 0) return error.ScrollCopyTargetInvalid;

    const scale_x: f32 = @as(f32, @floatFromInt(retained.width)) / @as(f32, @floatFromInt(logical_width));
    const scale_y: f32 = @as(f32, @floatFromInt(retained.height)) / @as(f32, @floatFromInt(logical_height));
    const copy_width: c_int = @max(1, @as(c_int, @intFromFloat(@as(f32, @floatFromInt(plan.width)) * scale_x)));
    const copy_height: c_int = @max(1, @as(c_int, @intFromFloat(@as(f32, @floatFromInt(plan.height)) * scale_y)));
    const source_texture = scrollCopyScratchTexture(renderer, scratch, copy_width, copy_height) orelse
        return error.ScrollCopyScratchInvalid;

    // A render target cannot safely sample itself. Snapshot the source band to
    // scratch first, then draw that snapshot to the destination band.
    if (!SDL_SetRenderTarget(renderer, source_texture)) return sdlFail("SDL_SetRenderTarget");
    if (!SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)) return sdlFail("SDL_SetRenderDrawColor");
    if (!SDL_RenderClear(renderer)) return sdlFail("SDL_RenderClear");
    const source = SDL_FRect{
        .x = 0,
        .y = @as(f32, @floatFromInt(plan.source_y)) * scale_y,
        .w = @floatFromInt(copy_width),
        .h = @floatFromInt(copy_height),
    };
    if (!SDL_RenderTexture(renderer, retained.texture.?, &source, null)) return sdlFail("SDL_RenderTexture");

    if (!SDL_SetRenderTarget(renderer, retained.texture.?)) return sdlFail("SDL_SetRenderTarget");
    const destination = SDL_FRect{
        .x = 0,
        .y = @as(f32, @floatFromInt(plan.destination_y)) * scale_y,
        .w = @floatFromInt(copy_width),
        .h = @floatFromInt(copy_height),
    };
    if (!SDL_RenderTexture(renderer, source_texture, null, &destination)) return sdlFail("SDL_RenderTexture");
    if (!SDL_SetRenderTarget(renderer, null)) return sdlFail("SDL_SetRenderTarget");
    return 1;
}

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
    const execution = try executeDrawList(list, renderer, window, null, null, false);
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
    capabilities: capability.Set,
    explicit_clip: ?renderer_policy.LogicalRect,
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
    const explicit_allowed = explicit_clip != null and
        capabilities.contains(.damage_retained_clip) and retained.primed;
    const clip: ?renderer_policy.LogicalRect = if (renderable and texture != null and
        capabilities.contains(.damage_retained_clip) and retained.primed and
        (explicit_allowed or
            (decision.kind == .cursor or decision.kind == .text or decision.kind == .region)))
        if (explicit_allowed) explicit_clip else decision.clip
    else
        null;

    var clipped = false;
    var submitted: u64 = 0;
    var execution: renderer_policy.DrawStats = .{};
    if (texture) |target| {
        if (clip) |rect| {
            execution = try executeDrawList(list, renderer, window, target, rect, explicit_clip != null);
            submitted = execution.commands;
            clipped = submitted != 0;
        }
        if (!clipped) {
            execution = try executeDrawList(list, renderer, window, target, null, false);
            submitted = execution.commands;
        }
        retained.primed = true;
        try presentRetainedOutput(renderer, target);
    } else {
        execution = try executeDrawList(list, renderer, window, null, null, false);
        submitted = execution.commands;
        if (!SDL_RenderPresent(renderer)) return sdlFail("SDL_RenderPresent");
        retained.primed = false;
    }
    counters.recordClip(decision.kind, clipped, submitted);
    if (explicit_clip != null) counters.recordExplicitDamage(clipped, submitted, execution.skipped_commands);
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
    const execution = try executeDrawList(list, renderer, window, null, null, false);
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
        .{if (config.interactive_publisher) config.auto_quit_ms + 1000 else 500},
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
            if (config.clipboard_unicode_publisher) "--clipboard-unicode-publisher" else "--clipboard-ascii-publisher",
            if (config.pointer_selection_publisher) "--pointer-selection-publisher" else "--clipboard-ascii-publisher",
            if (config.pointer_middle_paste_publisher) "--pointer-middle-paste-publisher" else "--clipboard-ascii-publisher",
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
    if (config.mode == .emacs_epxl_interactive or config.mode == .emacs_clipboard_unicode or
        config.mode == .emacs_pointer_selection or
        config.mode == .emacs_pointer_middle_paste)
    {
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
        } else if (std.mem.eql(u8, arg, "--standard-control")) {
            config.standard_session_control = true;
        } else if (std.mem.eql(u8, arg, "--version-mismatch")) {
            config.version_mismatch = true;
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
        } else if (std.mem.eql(u8, arg, "--emacs-frame-smoke")) {
            config.mode = .frame_lifecycle;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-interactive-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.interactive_synthetic = true;
        } else if (std.mem.eql(u8, arg, "--interactive-publisher")) {
            config.interactive_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-input-smoke")) {
            config.mode = .emacs_epxl_input;
            config.auto_input = "X";
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-unicode-input-smoke")) {
            config.mode = .emacs_epxl_unicode_input;
            config.auto_input = "你好";
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-key-v2-smoke")) {
            config.mode = .emacs_epxl_key_v2;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-edit-smoke")) {
            config.mode = .emacs_epxl_edit;
            config.auto_key = .backspace;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-sequence-smoke")) {
            config.mode = .emacs_epxl_sequence;
            config.auto_input = "X";
            config.auto_key = .backspace;
        } else if (std.mem.eql(u8, arg, "--clipboard-smoke")) {
            config.mode = .clipboard;
        } else if (std.mem.eql(u8, arg, "--clipboard-unicode-smoke")) {
            config.mode = .emacs_clipboard_unicode;
            config.interactive_publisher = true;
            config.synthetic_clipboard_unicode = true;
            config.clipboard_unicode_publisher = true;
        } else if (std.mem.eql(u8, arg, "--pointer-selection-publisher")) {
            config.pointer_selection_publisher = true;
        } else if (std.mem.eql(u8, arg, "--pointer-middle-paste-publisher")) {
            config.pointer_middle_paste_publisher = true;
        } else if (std.mem.eql(u8, arg, "--clipboard-unicode-publisher")) {
            config.clipboard_unicode_publisher = true;
        } else if (std.mem.eql(u8, arg, "--clipboard-ascii-publisher")) {
            config.clipboard_unicode_publisher = false;
        } else if (std.mem.eql(u8, arg, "--input-translate-smoke")) {
            config.mode = .input_translation;
        } else if (std.mem.eql(u8, arg, "--emacs-pointer-selection-smoke")) {
            config.mode = .emacs_pointer_selection;
            config.interactive_publisher = true;
            config.synthetic_pointer_selection = true;
            config.synthetic_pointer_v2 = true;
            config.pointer_selection_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-pointer-middle-paste-smoke")) {
            config.mode = .emacs_pointer_middle_paste;
            config.interactive_publisher = true;
            config.synthetic_pointer_selection = true;
            config.synthetic_pointer_middle_paste = true;
            config.synthetic_pointer_v2 = true;
            config.pointer_selection_publisher = true;
            config.pointer_middle_paste_publisher = true;
        } else if (std.mem.eql(u8, arg, "--pointer-v2-smoke")) {
            config.mode = .pointer_v2_translation;
            config.synthetic_pointer_v2 = true;
        } else if (std.mem.eql(u8, arg, "--glyph-run-smoke")) {
            config.mode = .glyph_run_smoke;
            config.auto_quit_ms = 180;
        } else if (std.mem.eql(u8, arg, "--runtime-bridge-smoke")) {
            config.mode = .runtime_bridge_smoke;
            config.auto_quit_ms = 180;
        } else if (std.mem.eql(u8, arg, "--focus-window-smoke")) {
            config.mode = .focus_window_translation;
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
    if (config.mode == .pointer_v2_translation) {
        try runPointerV2Smoke();
        return;
    }
    if (config.mode == .glyph_run_smoke) {
        try runGlyphRunSmoke(gpa, &config);
        return;
    }
    if (config.mode == .runtime_bridge_smoke) {
        try runRuntimeBridgeSmoke(gpa, &config);
        return;
    }
    if (config.mode == .focus_window_translation) {
        try runFocusWindowSmoke();
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
            // The publisher below always sends the standard-control sequence.
            // Mark it on the parent before starting the frontend so capability
            // enforcement and final-state assertions cannot be skipped.
            config.standard_session_control = true;
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
                .argv = &.{ config.self_exe, "--publisher", "--standard-control", "--replay", config.replay_path, "--endpoint", config.endpoint, "--token-file", config.token_path },
            });
            errdefer child.kill(io);
            const loaded = try runLiveFrontend(gpa, io, &config, &delivery);
            const term = try child.wait(io);
            if (term != .exited or term.exited != 0) return error.PublisherFailed;
            if (config.standard_session_control) {
                if (loaded.control.stage != .closed or loaded.control.close_reason != .normal)
                    return error.SessionControlNotClosed;
                if (loaded.control.outstanding_ping_ns != 0)
                    return error.SessionLivenessNotResolved;
                if (loaded.control.recoverable_error_count != 1 or
                    loaded.control.last_error_code != 101 or
                    loaded.control.last_error_severity != .recoverable)
                    return error.SessionErrorNotRecovered;
            }

            // A closed session cannot accept another control, so prove the
            // final VERSION_MISMATCH transport case on a fresh connection.
            config.version_mismatch = true;
            var mismatch_child = try std.process.spawn(io, .{
                .argv = &.{ config.self_exe, "--publisher", "--version-mismatch", "--standard-control", "--replay", config.replay_path, "--endpoint", config.endpoint, "--token-file", config.token_path },
            });
            errdefer mismatch_child.kill(io);
            var mismatch_scene = try runVersionMismatchFrontend(gpa, io, &config);
            mismatch_scene.deinit();
            const mismatch_term = try mismatch_child.wait(io);
            if (mismatch_term != .exited or mismatch_term.exited != 0) return error.PublisherFailed;

            std.Io.Dir.cwd().deleteTree(io, private_dir) catch {};
            gpa.free(private_dir);
            break :blk loaded;
        },
        .publisher => unreachable,
        .emacs => unreachable,
        .input_translation => unreachable,
        .pointer_v2_translation => unreachable,
        .focus_window_translation => unreachable,
        .emacs_interactive => unreachable,
        .clipboard => unreachable,
        .emacs_epxl => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_reconnect => try runEmacsEpxlSession(gpa, io, &config, 2),
        .emacs_epxl_recovery => try runEmacsEpxlSession(gpa, io, &config, 2),
        .emacs_epxl_interactive => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_input => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_unicode_input => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_key_v2 => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_edit => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_sequence => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_clipboard_unicode => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_pointer_selection,
        .emacs_pointer_middle_paste,
        => try runEmacsEpxlSession(gpa, io, &config, 1),
        .frame_lifecycle => {
            try runFrameLifecycleSmoke(gpa, io, &config);
            return;
        },
        .glyph_run_smoke => unreachable,
        .runtime_bridge_smoke => unreachable,
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
    if (config.mode == .emacs_epxl_unicode_input and scene.stats.frame_updates < 2)
        return error.UnexpectedFactUpdateCount;
    if (config.mode == .emacs_epxl_key_v2 and scene.stats.frame_updates < 3)
        return error.UnexpectedFactUpdateCount;
    if (config.mode == .emacs_epxl_key_v2 and
        (scene.cursor == null or scene.cursor.?.x != 56 or scene.cursor.?.y != 14))
        return error.FullKeyExecutionNotApplied;
    if (config.mode == .emacs_epxl_key_v2)
        std.debug.print(
            "sdl3-epxl-key-v2-smoke: {{\"kind\":\"sdl3-epxl-key-v2-smoke\",\"assertion\":\"ctrl-a/ctrl-e/end-of-line\",\"unhandled_acked\":true,\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{scene.stats.frame_updates},
        );
    if (config.mode == .emacs_epxl_unicode_input and
        !sceneHasText(&scene, "你好Emacs Proto-UI")) return error.UnicodeInputNotApplied;
    if (config.mode == .emacs_epxl_unicode_input)
        std.debug.print(
            "sdl3-epxl-unicode-input-smoke: {{\"kind\":\"sdl3-epxl-unicode-input-smoke\",\"assertion\":\"你好Emacs Proto-UI\",\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{scene.stats.frame_updates},
        );
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

fn atomicWriteFile(gpa: std.mem.Allocator, io: std.Io, path: []const u8, data: []const u8) !void {
    const temporary = try std.fmt.allocPrint(gpa, "{s}.tmp", .{path});
    defer gpa.free(temporary);
    _ = std.Io.Dir.cwd().deleteFile(io, temporary) catch {};
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = temporary, .data = data });
    errdefer _ = std.Io.Dir.cwd().deleteFile(io, temporary) catch {};
    try std.Io.Dir.rename(std.Io.Dir.cwd(), temporary, std.Io.Dir.cwd(), path, io);
}

fn waitForFile(gpa: std.mem.Allocator, io: std.Io, path: []const u8, timeout_ms: u32) !void {
    _ = gpa;
    var waited: u32 = 0;
    while (waited < timeout_ms) : (waited += 20) {
        _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch {
            try io.sleep(.fromMilliseconds(20), .awake);
            continue;
        };
        return;
    }
    return error.FrameLifecycleTimeout;
}

fn waitForFilePrefix(gpa: std.mem.Allocator, io: std.Io, path: []const u8, prefix: []const u8, timeout_ms: u32) !void {
    var waited: u32 = 0;
    while (waited < timeout_ms) : (waited += 20) {
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64)) catch {
            try io.sleep(.fromMilliseconds(20), .awake);
            waited += 20;
            continue;
        };
        defer gpa.free(bytes);
        if (std.mem.startsWith(u8, bytes, prefix)) return;
        try io.sleep(.fromMilliseconds(20), .awake);
        waited += 20;
    }
    return error.FrameLifecycleTimeout;
}

fn emacsClientOnce(
    io: std.Io,
    emacsclient_path: []const u8,
    socket_path: []const u8,
    eval: []const u8,
) !std.process.Child.Term {
    var child = try std.process.spawn(io, .{
        .argv = &.{
            emacsclient_path,
            "-a",
            "",
            "--socket-name",
            socket_path,
            "-e",
            eval,
        },
    });
    return child.wait(io);
}

fn runFrameLifecycleSmoke(
    gpa: std.mem.Allocator,
    io: std.Io,
    config: *const Config,
) !void {
    var token_bytes: [8]u8 = undefined;
    try io.randomSecure(&token_bytes);
    const suffix = std.fmt.bytesToHex(token_bytes, .lower);
    const private_dir = try std.fmt.allocPrint(gpa, "/tmp/proto-ui-frame-{s}", .{suffix});
    errdefer gpa.free(private_dir);
    const directory_permissions: std.Io.Dir.Permissions = if (native_os == .windows)
        .default_dir
    else
        @enumFromInt(0o700);
    try std.Io.Dir.cwd().createDir(io, private_dir, directory_permissions);
    errdefer std.Io.Dir.cwd().deleteTree(io, private_dir) catch {};

    const socket_path = try std.fmt.allocPrint(gpa, "{s}/emacs.sock", .{private_dir});
    defer gpa.free(socket_path);
    const facts_path = try std.fmt.allocPrint(gpa, "{s}/facts.json", .{private_dir});
    defer gpa.free(facts_path);
    const ready_path = try std.fmt.allocPrint(gpa, "{s}/created", .{private_dir});
    defer gpa.free(ready_path);
    const delete_path = try std.fmt.allocPrint(gpa, "{s}/delete", .{private_dir});
    defer gpa.free(delete_path);
    const deleted_path = try std.fmt.allocPrint(gpa, "{s}/deleted", .{private_dir});
    defer gpa.free(deleted_path);
    const emacs_dir = std.fs.path.dirname(config.emacs_path) orelse ".";
    const emacsclient_path = try std.fmt.allocPrint(gpa, "{s}/emacsclient", .{emacs_dir});
    defer gpa.free(emacsclient_path);

    _ = std.Io.Dir.cwd().deleteFile(io, facts_path) catch {};
    _ = std.Io.Dir.cwd().deleteFile(io, ready_path) catch {};
    _ = std.Io.Dir.cwd().deleteFile(io, delete_path) catch {};
    _ = std.Io.Dir.cwd().deleteFile(io, deleted_path) catch {};

    const display_ptr = std.c.getenv("DISPLAY") orelse "wayland-0";
    const display: []const u8 = std.mem.span(display_ptr);
    var daemon = try std.process.spawn(io, .{
        .argv = &.{ config.emacs_path, "-Q", "-d", display, try std.fmt.allocPrint(gpa, "--fg-daemon={s}", .{socket_path}) },
        .environ_map = null,
    });
    var daemon_running = true;
    defer if (daemon_running) daemon.kill(io);
    try waitForFile(gpa, io, socket_path, 10000);

    // Bounded daemon readiness ping.  The empty alternate editor ensures this
    // cannot fall back to launching a second or user Emacs instance.
    var daemon_ready = false;
    var attempt: usize = 0;
    while (attempt < 20) : (attempt += 1) {
        if (emacsClientOnce(io, emacsclient_path, socket_path, "(+ 1 1)")) |term| {
            if (term == .exited and term.exited == 0) {
                daemon_ready = true;
                break;
            }
        } else |err| return err;
        try io.sleep(.fromMilliseconds(250), .awake);
    }
    if (!daemon_ready) return error.FrameLifecycleTimeout;

    const current_dir = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(current_dir);
    const absolute_module = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ current_dir, config.module_path });
    defer gpa.free(absolute_module);
    const module_eval = try std.fmt.allocPrint(
        gpa,
        "(progn (module-load (expand-file-name (format \"%s\" (format \"{s}\")))) t)",
        .{absolute_module},
    );
    defer gpa.free(module_eval);
    const module_term = try emacsClientOnce(io, emacsclient_path, socket_path, module_eval);
    if (module_term != .exited or module_term.exited != 0) return error.ModuleLoadFailed;

    const lifecycle_eval = try std.fmt.allocPrint(
        gpa,
        \\(let* ((frame (make-frame-on-display (format "%s" (format "{s}")) (quote ((width . 30) (height . 10) (left . 20) (top . 20)))))
        \\       (facts-file (expand-file-name (format "%s" (format "{s}"))))
        \\       (ready-file (expand-file-name (format "%s" (format "{s}"))))
        \\       (delete-file-name (expand-file-name (format "%s" (format "{s}"))))
        \\       (deleted-file (expand-file-name (format "%s" (format "{s}")))))
        \\  (unless (and (frame-live-p frame) (frame-visible-p frame))
        \\    (error "Proto-UI lifecycle frame is not visible"))
        \\  (redisplay t)
        \\  (let* ((window (frame-selected-window frame))
        \\         (buffer (window-buffer window))
        \\         (deadline (+ (float-time) 8.0))
        \\         (previous (cons (frame-pixel-width frame)
        \\                         (frame-pixel-height frame)))
        \\         (matching-samples 1))
        \\    (while (< matching-samples 3)
        \\      (sleep-for 0.15)
        \\      (when (>= (float-time) deadline)
        \\        (error "Proto-UI lifecycle frame geometry settle timed out"))
        \\      (let ((sample (cons (frame-pixel-width frame)
        \\                          (frame-pixel-height frame))))
        \\        (if (and (= (car previous) (car sample))
        \\                 (= (cdr previous) (cdr sample)))
        \\            (setq matching-samples (+ matching-samples 1))
        \\          (setq previous sample
        \\                matching-samples 1))))
        \\      (with-current-buffer (get-buffer-create "*Proto-UI Lifecycle*")
        \\        (erase-buffer)
        \\        (insert "Emacs Proto-UI")
        \\        (set-window-buffer window (current-buffer)))
        \\      (redisplay t)
        \\      (let ((facts-temp (make-temp-file "proto-ui-facts")))
        \\        (with-temp-file facts-temp
        \\          (insert (proto-ui-frame-facts frame)))
        \\        (rename-file facts-temp facts-file t))
        \\      (let ((ready-temp (make-temp-file "proto-ui-ready")))
        \\        (with-temp-file ready-temp (insert "created"))
        \\        (rename-file ready-temp ready-file t))
        \\      (let ((deadline (+ (float-time) 12)))
        \\        (while (and (not (file-exists-p delete-file-name))
        \\                    (< (float-time) deadline))
        \\          (sit-for 0.1 t)))
        \\      (unless (file-exists-p delete-file-name)
        \\        (error "Proto-UI frame delete request timed out"))
        \\      (delete-file delete-file-name)
        \\      (delete-frame frame)
        \\      (let ((deleted-temp (make-temp-file "proto-ui-deleted")))
        \\        (with-temp-file deleted-temp (insert "deleted"))
        \\        (rename-file deleted-temp deleted-file t))))))
    ,
        .{ display, facts_path, ready_path, delete_path, deleted_path },
    );
    defer gpa.free(lifecycle_eval);

    var client = try std.process.spawn(io, .{
        .argv = &.{
            emacsclient_path,
            "-a",
            "",
            "--socket-name",
            socket_path,
            "-e",
            lifecycle_eval,
        },
        .environ_map = null,
    });
    var client_running = true;
    defer if (client_running) client.kill(io);

    try waitForFile(gpa, io, facts_path, 15000);
    try waitForFile(gpa, io, ready_path, 1000);
    const facts_bytes = std.Io.Dir.cwd().readFileAlloc(io, facts_path, gpa, .limited(64 * 1024)) catch return error.NoEmacsFacts;
    defer gpa.free(facts_bytes);
    const frame_facts = try facts.parse(gpa, facts_bytes);
    if (frame_facts.frame_width <= 0 or frame_facts.frame_height <= 0)
        return error.FrameLifecycleRoundTripFailed;

    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow("Emacs Proto-UI Frame Lifecycle", 720, 480, SDL_WINDOW_RESIZABLE) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);
    const selected_renderer = try createRenderer(gpa, window, config.renderer_request, config.present_mode);
    defer destroyRenderer(selected_renderer);
    std.debug.print("sdl3-frame-smoke: renderer {s} tier={s}\n", .{ selected_renderer.name, @tagName(selected_renderer.tier) });

    var producer_scene = frontend.Scene.init(gpa);
    defer producer_scene.deinit();
    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
    defer draw_list.deinit();
    var frame_gate: renderer_policy.FrameGate = .{};
    var frame_counters: renderer_policy.FrameCounters = .{};
    producer_scene.next_sequence = 5; // reserve W12a control/capability sequences 1..4
    scene.next_sequence = 5;

    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| gpa.free(message);
        messages.deinit(gpa);
    }
    try facts.appendWireSnapshot(
        gpa,
        frame_facts,
        &.{"Emacs Proto-UI"},
        .{ .line = 1, .column = 0 },
        .{ .start_line = 1, .line_count = 1 },
        &producer_scene,
        &messages,
    );
    if (messages.items.len != 2) return error.FrameLifecycleRoundTripFailed;
    for (messages.items, 0..) |message, index| {
        try scene.apply(message);
        if (index == 0) {
            if (!SDL_SetRenderDrawColor(selected_renderer.handle, 0x10, 0x12, 0x18, 255)) return sdlFail("SDL_SetRenderDrawColor");
            if (!SDL_RenderClear(selected_renderer.handle)) return sdlFail("SDL_RenderClear");
            if (!SDL_RenderPresent(selected_renderer.handle)) return sdlFail("SDL_RenderPresent");
            SDL_Delay(250);
        } else {
            try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters);
        }
    }
    if (scene.stats.frame_updates != 1 or scene.frame == null or
        scene.frames.len != 1 or scene.frames.frames[0].status != .active)
        return error.FrameLifecycleRoundTripFailed;

    const marker = "Emacs Proto-UI";
    const glyph_run = try publicFactsGlyphRun(&scene, marker);
    var glyph_payload: std.ArrayList(u8) = .empty;
    defer glyph_payload.deinit(gpa);
    try frontend.encodeGlyphRun(gpa, glyph_run, &glyph_payload);
    var glyph_message: std.ArrayList(u8) = .empty;
    defer glyph_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = protocol.Flags.debug,
        .message_type = protocol.Message.glyph_run,
        .sequence = 7,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = 1,
        .timestamp_ns = 7,
    }, glyph_payload.items, &glyph_message);
    try producer_scene.apply(glyph_message.items);
    try scene.apply(glyph_message.items);
    if (producer_scene.next_sequence != 8 or scene.next_sequence != 8)
        return error.FrameLifecycleRoundTripFailed;
    try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters);
    if (scene.glyph_runs.items.len != 1) return error.GlyphRunSceneStateInvalid;
    const active_run = scene.glyph_runs.items[0];
    if (!std.mem.eql(u8, active_run.text, marker) or
        active_run.window_id != glyph_run.window_id or
        active_run.row_index != glyph_run.row_index or
        active_run.x != glyph_run.x or active_run.y != glyph_run.y or
        active_run.width != glyph_run.width or active_run.height != glyph_run.height)
        return error.GlyphRunSceneStateInvalid;

    const delete_message = try glyphRunDeleteMessage(gpa, .{
        .run_id = active_run.run_id,
        .generation = active_run.generation,
        .window_id = active_run.window_id,
        .row_index = active_run.row_index,
    }, 8);
    defer gpa.free(delete_message);
    try producer_scene.apply(delete_message);
    try scene.apply(delete_message);
    if (producer_scene.next_sequence != 9 or scene.next_sequence != 9 or
        scene.glyph_runs.items.len != 0 or !sceneHasText(&scene, marker))
        return error.GlyphRunDeleteFailed;
    try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters);
    var marker_rendered = false;
    for (draw_list.commands.items) |command| {
        if (command == .text and std.mem.eql(u8, command.text.bytes, marker))
            marker_rendered = true;
    }
    if (!marker_rendered) return error.GlyphRunFactsFallbackFailed;

    // Atomic delete request; the Emacs client consumes it before deleting.
    try atomicWriteFile(gpa, io, delete_path, "delete");
    try waitForFilePrefix(gpa, io, deleted_path, "deleted", 12000);
    const client_term = try client.wait(io);
    client_running = false;
    if (client_term != .exited or client_term.exited != 0)
        return error.FrameLifecycleRoundTripFailed;

    var destroy_payload: [8]u8 = undefined;
    std.mem.writeInt(u32, destroy_payload[0..4], 1, .little);
    std.mem.writeInt(u32, destroy_payload[4..8], 1, .little);
    var destroy_message: std.ArrayList(u8) = .empty;
    defer destroy_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_destroy,
        .sequence = 9,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = 1,
        .timestamp_ns = 9,
    }, &destroy_payload, &destroy_message);
    try producer_scene.apply(destroy_message.items);
    try scene.apply(destroy_message.items);
    if (producer_scene.next_sequence != 10 or scene.next_sequence != 10)
        return error.FrameLifecycleRoundTripFailed;
    if (scene.frame != null or scene.frames.len != 1 or
        scene.frames.frames[0].status != .destroyed or scene.windows.items.len != 0)
        return error.FrameLifecycleRoundTripFailed;
    if (producer_scene.frame != null or producer_scene.frames.len != 1 or
        producer_scene.frames.frames[0].status != .destroyed)
        return error.FrameLifecycleRoundTripFailed;

    var width: c_int = 0;
    var height: c_int = 0;
    SDL_GetWindowSize(window, &width, &height);
    if (!SDL_SetRenderDrawColor(selected_renderer.handle, 0x10, 0x12, 0x18, 255)) return sdlFail("SDL_SetRenderDrawColor");
    if (!SDL_RenderClear(selected_renderer.handle)) return sdlFail("SDL_RenderClear");
    if (!SDL_RenderPresent(selected_renderer.handle)) return sdlFail("SDL_RenderPresent");
    SDL_Delay(250);

    const stop_term = try emacsClientOnce(io, emacsclient_path, socket_path, "(kill-emacs 0)");
    if (stop_term != .exited or stop_term.exited != 0) return error.FrameLifecycleCleanupFailed;
    const daemon_term = try daemon.wait(io);
    daemon_running = false;
    if (daemon_term != .exited and daemon_term != .signal) return error.FrameLifecycleCleanupFailed;

    std.debug.print(
        "sdl3-frame-smoke: real Emacs frame {d}x{d} created, rendered, and deleted through SDL3; lifecycle OK\n",
        .{ frame_facts.frame_width, frame_facts.frame_height },
    );
    std.Io.Dir.cwd().deleteTree(io, private_dir) catch {};
    gpa.free(private_dir);
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
