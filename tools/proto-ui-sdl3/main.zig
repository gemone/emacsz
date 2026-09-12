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
const runtime = proto_ui.runtime;
const runtime_bridge = proto_ui.runtime_bridge;
const runtime_host = proto_ui.runtime_host;

const SDL_INIT_VIDEO: c_uint = 0x0000_0020;
const SDL_WINDOW_RESIZABLE: c_ulonglong = 0x0000_0020;
const SDL_WINDOW_HIDDEN: c_ulonglong = 0x0000_0008;
const SDL_EVENT_QUIT: c_uint = 0x100;
const SDL_EVENT_SYSTEM_THEME_CHANGED: c_uint = 0x14f;
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
const SDL_EVENT_DROP_FILE: c_uint = 0x1000;
const SDL_EVENT_DROP_TEXT: c_uint = 0x1001;
const SDL_EVENT_DROP_BEGIN: c_uint = 0x1002;
const SDL_EVENT_DROP_COMPLETE: c_uint = 0x1003;
const SDL_EVENT_DROP_POSITION: c_uint = 0x1004;

/// Bounded deterministic drop payload for the synthetic drag-and-drop smoke.
const dnd_drop_text = "Dropped!";
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
const SDL_BlendMode = c_int;
const SDL_PIXELFORMAT_RGBA8888: SDL_PixelFormat = 0x1646_2004;
const SDL_TEXTUREACCESS_STATIC: SDL_TextureAccess = 0;
const SDL_TEXTUREACCESS_TARGET: SDL_TextureAccess = 2;
const SDL_BLENDMODE_BLEND: SDL_BlendMode = 1;
const SDL_SCALEMODE_NEAREST: SDL_ScaleMode = 1;

const SDLInitFlags = c_uint;
const SDLWindowFlags = c_ulonglong;
const SDL_WINDOW_BORDERLESS: SDLWindowFlags = 0x10;
const SDL_WINDOW_FULLSCREEN: SDLWindowFlags = 0x01;
const SDL_WINDOW_MAXIMIZED: SDLWindowFlags = 0x80;
const SDL_WINDOW_ALWAYS_ON_TOP: SDLWindowFlags = 0x10000;
const SDL_DisplayID = c_uint;
const SDL_SystemTheme = c_uint;
const SDL_SYSTEM_THEME_UNKNOWN: SDL_SystemTheme = 0;
const SDL_SYSTEM_THEME_LIGHT: SDL_SystemTheme = 1;
const SDL_SYSTEM_THEME_DARK: SDL_SystemTheme = 2;
extern fn SDL_GetSystemTheme() SDL_SystemTheme;
extern fn SDL_GetDisplayContentScale(SDL_DisplayID) f32;

extern fn SDL_Init(flags: SDLInitFlags) bool;
extern fn SDL_Quit() void;
extern fn SDL_CreateWindow(title: [*:0]const u8, w: c_int, h: c_int, flags: SDLWindowFlags) ?*SDL_Window;
extern fn SDL_DestroyWindow(window: *SDL_Window) void;
extern fn SDL_SetWindowTitle(window: *SDL_Window, title: [*:0]const u8) void;
extern fn SDL_GetWindowTitle(window: *SDL_Window) [*:0]const u8;
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
extern fn SDL_SetWindowSize(window: *SDL_Window, width: c_int, height: c_int) bool;
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
extern fn SDL_GetPrimaryDisplay() SDL_DisplayID;
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
extern fn SDL_SetRenderScale(renderer: *SDL_Renderer, scale_x: f32, scale_y: f32) bool;
extern fn SDL_GetRenderScale(renderer: *SDL_Renderer, scale_x: *f32, scale_y: *f32) void;
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
extern fn SDL_SetTextureBlendMode(texture: *SDL_Texture, mode: SDL_BlendMode) bool;
extern fn SDL_UpdateTexture(texture: *SDL_Texture, rect: ?*const SDL_Rect, pixels: *const anyopaque, pitch: c_int) bool;
extern fn SDL_RenderTexture(renderer: *SDL_Renderer, texture: *SDL_Texture, source: ?*const SDL_FRect, destination: ?*const SDL_FRect) bool;
extern fn SDL_CreateTextureFromSurface(renderer: *SDL_Renderer, surface: *SDL_Surface) ?*SDL_Texture;
extern fn SDL_GetTextureSize(texture: *SDL_Texture, width: *f32, height: *f32) bool;
extern fn SDL_SetRenderTarget(renderer: *SDL_Renderer, texture: ?*SDL_Texture) bool;
extern fn SDL_PollEvent(event: *SDL_Event) bool;
extern fn SDL_PushEvent(event: *SDL_Event) bool;
extern fn SDL_GetWindowID(window: *SDL_Window) u32;
extern fn SDL_Delay(ms: c_uint) void;
extern fn SDL_StartTextInput(window: *SDL_Window) bool;
extern fn SDL_StopTextInput(window: *SDL_Window) void;
extern fn SDL_SetTextInputArea(window: *SDL_Window, rect: *const SDL_Rect, cursor: c_int) bool;
extern fn SDL_GetKeyName(key: c_uint) ?[*:0]const u8;
extern fn SDL_GetModState() u16;

const TTF_Font = opaque {};
const SDL_Color = extern struct { r: u8, g: u8, b: u8, a: u8 };
extern fn TTF_Init() bool;
extern fn TTF_Quit() void;
extern fn TTF_OpenFont(file: [*:0]const u8, point_size: f32) ?*TTF_Font;
extern fn TTF_CloseFont(font: *TTF_Font) void;
extern fn TTF_RenderText_Blended(font: *TTF_Font, text: [*]const u8, length: usize, foreground: SDL_Color) ?*SDL_Surface;
extern fn TTF_GetFontHeight(font: *const TTF_Font) c_int;
extern fn TTF_SetFontStyle(font: *TTF_Font, style: c_int) void;
extern fn TTF_AddFallbackFont(font: *TTF_Font, fallback: *TTF_Font) bool;
extern fn TTF_FontHasGlyph(font: *TTF_Font, ch: u32) bool;
extern fn SDL_SetModState(modifiers: u16) void;
extern fn SDL_GetClipboardText() [*c]u8;
extern fn SDL_SetClipboardText(text: [*:0]const u8) bool;
extern fn SDL_GetPrimarySelectionText() [*c]u8;
extern fn SDL_SetPrimarySelectionText(text: [*:0]const u8) bool;
extern fn SDL_HasPrimarySelectionText() bool;
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

const SDL_TouchFingerEvent = extern struct {
    type: c_uint,
    reserved: c_uint,
    timestamp: u64,
    touch_id: u64,
    finger_id: u64,
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,
    pressure: f32,
    window_id: u32,
};

const SDL_DropEvent = extern struct {
    type: c_uint,
    reserved: c_uint,
    timestamp: u64,
    window_id: u32,
    x: f32,
    y: f32,
    source: ?[*:0]const u8,
    data: ?[*:0]const u8,
};

const SDL_PenMotionEvent = extern struct {
    type: c_uint,
    reserved: c_uint,
    timestamp: u64,
    window_id: u32,
    which: u32,
    pen_state: u32,
    x: f32,
    y: f32,
};

const SDL_Event = extern union {
    type: c_uint,
    key: SDL_KeyboardEvent,
    text: SDL_TextInputEvent,
    motion: SDL_MouseMotionEvent,
    button: SDL_MouseButtonEvent,
    wheel: SDL_MouseWheelEvent,
    window: SDL_WindowEvent,
    finger: SDL_TouchFingerEvent,
    drop: SDL_DropEvent,
    pen: SDL_PenMotionEvent,
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

fn wheelEvent(x: i32, y: i32) SDL_Event {
    var event: SDL_Event = undefined;
    event.wheel = .{
        .type = SDL_EVENT_MOUSE_WHEEL,
        .reserved = 0,
        .timestamp = 0,
        .window_id = 0,
        .which = 0,
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .direction = 0,
        .mouse_x = 0,
        .mouse_y = 0,
        .integer_x = x,
        .integer_y = y,
    };
    return event;
}

fn dropEvent(event_type: c_uint, x: f32, y: f32, data: ?[*:0]const u8) SDL_Event {
    var event: SDL_Event = undefined;
    event.drop = .{
        .type = event_type,
        .reserved = 0,
        .timestamp = 0,
        .window_id = 0,
        .x = x,
        .y = y,
        .source = null,
        .data = data,
    };
    return event;
}

fn penEvent(event_type: c_uint, x: f32, y: f32, pen_state: u32) SDL_Event {
    var event: SDL_Event = undefined;
    event.pen = .{
        .type = event_type,
        .reserved = 0,
        .timestamp = 0,
        .window_id = 0,
        .which = 1,
        .pen_state = pen_state,
        .x = x,
        .y = y,
    };
    return event;
}

fn touchFingerEvent(event_type: c_uint, normalized_x: f32, normalized_y: f32) SDL_Event {
    var event: SDL_Event = undefined;
    event.finger = .{
        .type = event_type,
        .reserved = 0,
        .timestamp = 0,
        .touch_id = 1,
        .finger_id = 1,
        .x = normalized_x,
        .y = normalized_y,
        .dx = 0,
        .dy = 0,
        .pressure = 1,
        .window_id = 0,
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

fn queuePrimarySelectionText(queue: anytype, support: input_policy.TextSupport) !bool {
    const text: ?[*:0]u8 = SDL_GetPrimarySelectionText();
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

fn setPlatformPrimarySelection(bytes: []const u8) !void {
    if (!input_policy.validClipboardText(bytes)) return error.ClipboardTextNotAccepted;
    var text: [121]u8 = undefined;
    @memcpy(text[0..bytes.len], bytes);
    text[bytes.len] = 0;
    if (!SDL_SetPrimarySelectionText(@ptrCast(&text))) return sdlFail("SDL_SetPrimarySelectionText");
}

fn clearPlatformPrimarySelection() !void {
    if (!SDL_SetPrimarySelectionText("")) return sdlFail("SDL_SetPrimarySelectionText");
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

fn runPrimarySelectionSmoke() !void {
    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    if (!SDL_SetPrimarySelectionText("Emacs 你好")) return sdlFail("SDL_SetPrimarySelectionText");
    if (!SDL_HasPrimarySelectionText()) return error.PrimarySelectionUnavailable;
    var queue: input_policy.Queue = .{};
    if (!try queuePrimarySelectionText(&queue, .unicode)) return error.PrimarySelectionTextNotAccepted;
    if (queue.length != 1) return error.PrimarySelectionQueueCount;
    std.debug.print("sdl3-primary-selection-smoke: captured bounded UTF-8 primary text; queue=1; lifecycle OK\n", .{});
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

const Mode = enum { replay, live, publisher, emacs, facts_publisher, emacs_epxl, emacs_epxl_reconnect, emacs_epxl_recovery, emacs_epxl_gap, emacs_epxl_interactive, emacs_epxl_input, emacs_epxl_unicode_input, emacs_epxl_ime_commit, emacs_epxl_dnd, emacs_epxl_face, emacs_epxl_cursor, emacs_epxl_scrollbar, emacs_epxl_scroll_interaction, emacs_epxl_hscroll, emacs_epxl_menu_bar, emacs_epxl_menu_open, emacs_epxl_menu_apply, emacs_epxl_graphic, emacs_epxl_mouse, cursor_style_smoke, emacs_epxl_key_v2, emacs_epxl_key_modifier, emacs_window_split, emacs_window_navigation, emacs_window_restore, emacs_window_pointer_select, renderer_bench, pointer_v2_translation, touch_tap_smoke, pen_tap_smoke, face_text_smoke, menu_hit_smoke, toolbar_hit_smoke, dialog_hit_smoke, scrollbar_smoke, emacs_epxl_edit, emacs_epxl_bench, emacs_epxl_sequence, frame_lifecycle, input_translation, focus_window_translation, emacs_interactive, clipboard, primary_selection, emacs_clipboard_unicode, emacs_primary_selection, emacs_pointer_selection, emacs_pointer_middle_paste, glyph_run_smoke, runtime_bridge_smoke, emacs_epxl_failure_cleanup, provider_frame };

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
    benchmark_output: []const u8 = "",
    benchmark_iterations: u32 = 240,
    benchmark_warmup: u32 = 16,
    synthetic_interactive: bool = false,
    synthetic_copy: bool = false,
    synthetic_clipboard_unicode: bool = false,
    synthetic_primary_selection: bool = false,
    clipboard_unicode_publisher: bool = false,
    primary_selection_publisher: bool = false,
    pointer_selection_publisher: bool = false,
    pointer_generic_publisher: bool = false,
    pointer_middle_paste_publisher: bool = false,
    visible_edit_publisher: bool = false,
    dnd_text_publisher: bool = false,
    face_smoke_publisher: bool = false,
    cursor_smoke_publisher: bool = false,
    scrollbar_smoke_publisher: bool = false,
    hscroll_smoke_publisher: bool = false,
    graphic_frame_publisher: bool = false,
    region_smoke_publisher: bool = false,
    runs_smoke_publisher: bool = false,
    header_smoke_publisher: bool = false,
    mouse_smoke_publisher: bool = false,
    echo_smoke_publisher: bool = false,
    menu_icon_publisher: bool = false,
    drop_first_input_ack: bool = false,
    gap_fault: bool = false,
    interactive_publisher: bool = false,
    manual_emacs_session: bool = false,
    interactive_synthetic: bool = false,
    title_smoke: bool = false,
    synthetic_theme_event: bool = false,
    synthetic_focus_events: bool = false,
    synthetic_window_resize: bool = false,
    synthetic_window_move: bool = false,
    synthetic_window_maximize: bool = false,
    synthetic_window_fullscreen: bool = false,
    synthetic_window_minimize_restore: bool = false,
    selection_owner_smoke: bool = false,
    selection_transfer_smoke: bool = false,
    synthetic_monitor_change: bool = false,
    force_frontend_failure: bool = false,
    synthetic_pointer: bool = false,
    synthetic_pointer_v2: bool = false,
    synthetic_pointer_selection: bool = false,
    synthetic_pointer_middle_paste: bool = false,
    synthetic_wheel: bool = false,
    synthetic_dnd: bool = false,
    synthetic_pen: bool = false,
    synthetic_viewport: bool = false,
};

const FrameFacts = facts.FrameFacts;

const SharedFacts = struct {
    mutex: std.Io.Mutex = .init,
    facts: ?FrameFacts = null,
    version: u64 = 0,
};

extern fn read(fd: c_int, buffer: *anyopaque, count: usize) isize;
extern fn write(fd: c_int, buffer: *const anyopaque, count: usize) isize;
extern fn recv(fd: c_int, buffer: *anyopaque, count: usize, flags: c_int) isize;
const MSG_DONTWAIT: c_int = 0x40;

fn providerReadExact(buffer: []u8) !void {
    var offset: usize = 0;
    while (offset < buffer.len) {
        const count = read(3, buffer[offset..].ptr, buffer.len - offset);
        if (count < 0) return error.ProviderSurfaceReadFailed;
        if (count == 0) return error.ProviderSurfaceClosed;
        offset += @intCast(count);
    }
}

fn providerWriteAll(bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const count = write(3, bytes[offset..].ptr, bytes.len - offset);
        if (count <= 0) return error.ProviderSurfaceClosed;
        offset += @intCast(count);
    }
}

fn providerReadAvailable(buffer: []u8) !usize {
    const count = recv(3, buffer.ptr, buffer.len, MSG_DONTWAIT);
    if (count > 0) return @intCast(count);
    if (count == 0) return error.ProviderSurfaceClosed;
    return 0;
}

fn providerApplySnapshot(bytes: []const u8, scene: *frontend.Scene) !struct { rows: usize, runs: usize } {
    var offset: usize = 0;
    while (offset < bytes.len) {
        if (bytes.len - offset < 4) return error.ProviderSnapshotTruncated;
        const message_len = std.mem.readInt(u32, bytes[offset..][0..4], .little);
        offset += 4;
        if (message_len == 0 or offset + message_len > bytes.len)
            return error.ProviderSnapshotTruncated;
        try scene.apply(bytes[offset..][0..message_len]);
        offset += message_len;
    }
    if (offset != bytes.len or scene.frame == null or scene.frame_header == null)
        return error.ProviderSnapshotIncomplete;
    return .{ .rows = scene.rows.items.len, .runs = scene.glyph_runs.items.len };
}

fn providerFirstCodepoint(text: []const u8) ?u21 {
    if (text.len == 0) return null;
    const byte = text[0];
    if (byte < 0x80) return byte;
    const length: usize = if (byte & 0xe0 == 0xc0) 2 else if (byte & 0xf0 == 0xe0) 3 else if (byte & 0xf8 == 0xf0) 4 else return null;
    if (text.len < length) return null;
    var code: u21 = switch (length) {
        2 => byte & 0x1f,
        3 => byte & 0x0f,
        else => byte & 0x07,
    };
    for (text[1..length]) |continuation| {
        if (continuation & 0xc0 != 0x80) return null;
        code = (code << 6) | (continuation & 0x3f);
    }
    return code;
}

fn providerEmacsModifiers(modifiers: u16) u32 {
    var result: u32 = 0;
    if (modifiers & (input_policy.sdl_kmod_lshift | input_policy.sdl_kmod_rshift) != 0) result |= 0x0200000;
    if (modifiers & (input_policy.sdl_kmod_lctrl | input_policy.sdl_kmod_rctrl) != 0) result |= 0x0400000;
    if (modifiers & (input_policy.sdl_kmod_lalt | input_policy.sdl_kmod_ralt) != 0) result |= 0x0040000;
    if (modifiers & (input_policy.sdl_kmod_lgui | input_policy.sdl_kmod_rgui) != 0) result |= 0x0080000;
    if (modifiers & input_policy.sdl_kmod_mode != 0) result |= 0x0800000;
    return result;
}

fn providerEmacsKey(scancode: i32) ?u32 {
    return switch (scancode) {
        input_policy.SDL_SCANCODE_BACKSPACE => 0xff08,
        43 => 0xff09,
        input_policy.SDL_SCANCODE_RETURN => 0xff0d,
        input_policy.SDL_SCANCODE_ESCAPE => 0xff1b,
        input_policy.SDL_SCANCODE_LEFT => 0xff51,
        input_policy.SDL_SCANCODE_UP => 0xff52,
        input_policy.SDL_SCANCODE_RIGHT => 0xff53,
        input_policy.SDL_SCANCODE_DOWN => 0xff54,
        75 => 0xff55,
        78 => 0xff56,
        74 => 0xff50,
        77 => 0xff57,
        73 => 0xff63,
        76 => 0xffff,
        44 => ' ',
        58...69 => @intCast(0xffbe + scancode - 58),
        else => null,
    };
}

fn providerSendInput(kind: u16, flags: u16, modifiers: u32, code: u32, x: i32, y: i32, timestamp: u64) !void {
    var packet: [48]u8 = undefined;
    @memcpy(packet[0..8], "TPEINP1\x00");
    std.mem.writeInt(u16, packet[8..10], kind, .little);
    std.mem.writeInt(u16, packet[10..12], flags, .little);
    std.mem.writeInt(u32, packet[12..16], modifiers, .little);
    std.mem.writeInt(u32, packet[16..20], code, .little);
    std.mem.writeInt(u64, packet[24..32], timestamp, .little);
    std.mem.writeInt(i32, packet[32..36], x, .little);
    std.mem.writeInt(i32, packet[36..40], y, .little);
    std.mem.writeInt(i32, packet[40..44], 0, .little);
    std.mem.writeInt(i32, packet[44..48], 0, .little);
    try providerWriteAll(&packet);
}

fn providerSendKeyEvent(key: SDL_KeyboardEvent) !void {
    if (!key.down or key.repeat) return;
    const name = SDL_GetKeyName(key.key);
    const logical: []const u8 = if (name) |value| std.mem.span(value) else "";
    const modifiers = providerEmacsModifiers(key.modifiers);
    if (providerFirstCodepoint(logical)) |code| {
        if (code >= 0x20 and code <= 0x7e) {
            try providerSendInput(0, 0, modifiers, code, 0, 0, key.timestamp);
            return;
        }
    }
    if (providerEmacsKey(key.scancode)) |code|
        try providerSendInput(0, 0, modifiers, code, 0, 0, key.timestamp);
}

fn providerSendMouseEvent(kind: u16, flags: u16, modifiers: u32, code: u32, x: f32, y: f32, timestamp: u64) !void {
    try providerSendInput(kind, flags, modifiers, code, @intFromFloat(x), @intFromFloat(y), timestamp);
}

fn providerSendTextInput(text: []const u8, timestamp: u64) !void {
    const view = std.unicode.Utf8View.init(text) catch return;
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |code| {
        if (code <= 0x7e or code <= 0x1f) continue;
        try providerSendInput(1, 0, 0, code, 0, 0, timestamp);
    }
}

fn runProviderFrameSurface(gpa: std.mem.Allocator) !void {
    var wire: [48]u8 = undefined;
    try providerReadExact(&wire);
    if (!std.mem.eql(u8, wire[0..8], "TPESURF1")) return error.ProviderSurfaceMagicInvalid;
    const terminal_id = std.mem.readInt(u64, wire[8..16], .little);
    const terminal_generation = std.mem.readInt(u64, wire[16..24], .little);
    const frame_id = std.mem.readInt(u64, wire[24..32], .little);
    const frame_generation = std.mem.readInt(u64, wire[32..40], .little);
    const width = std.mem.readInt(i32, wire[40..44], .little);
    const height = std.mem.readInt(i32, wire[44..48], .little);
    if (terminal_id == 0 or terminal_generation == 0 or frame_id == 0 or
        frame_generation == 0 or width <= 0 or height <= 0)
        return error.ProviderSurfaceIdentityInvalid;

    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow("Emacs Proto Frame", width, height, SDL_WINDOW_RESIZABLE) orelse
        return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);
    const renderer = SDL_CreateRenderer(window, null) orelse return sdlFail("SDL_CreateRenderer");
    defer SDL_DestroyRenderer(renderer);
    if (!SDL_SetRenderDrawColor(renderer, 0x10, 0x12, 0x18, 255)) return sdlFail("SDL_SetRenderDrawColor");
    if (!SDL_RenderClear(renderer)) return sdlFail("SDL_RenderClear");
    if (!SDL_RenderPresent(renderer)) return sdlFail("SDL_RenderPresent");
    try providerWriteAll("OK");
    if (!SDL_StartTextInput(window)) return sdlFail("SDL_StartTextInput");

    var length_prefix: [4]u8 = undefined;
    var length_prefix_read: usize = 0;
    var snapshot: ?[]u8 = null;
    var snapshot_rows: usize = 0;
    var snapshot_runs: usize = 0;
    var first_snapshot_rendered = false;
    var smoke_hover_resent = false;
    var draw_list = renderer_policy.DrawList{ .allocator = gpa };
    defer draw_list.deinit();
    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    var texture_cache = FrameTextureCache.init(gpa);
    defer texture_cache.deinit();
    unicode_text_renderer.ensure() catch {};
    while (true) {
        var event: SDL_Event = undefined;
        while (SDL_PollEvent(&event)) {
            switch (event.type) {
                SDL_EVENT_QUIT => {
                    std.debug.print("sdl3-provider-frame: terminal={d}:{d} frame={d}:{d} surface={d}x{d} rows={d} runs={d} pass\n", .{
                        terminal_id, terminal_generation, frame_id,      frame_generation,
                        width,       height,              snapshot_rows, snapshot_runs,
                    });
                    return;
                },
                SDL_EVENT_KEY_DOWN => try providerSendKeyEvent(event.key),
                SDL_EVENT_TEXT_INPUT => {
                    const text: []const u8 = if (event.text.text) |value| std.mem.span(value) else "";
                    try providerSendTextInput(text, event.text.timestamp);
                },
                input_policy.SDL_EVENT_MOUSE_MOTION => {
                    const modifiers = providerEmacsModifiers(SDL_GetModState());
                    try providerSendMouseEvent(4, 2, modifiers, 0, event.motion.x, event.motion.y, event.motion.timestamp);
                },
                input_policy.SDL_EVENT_MOUSE_BUTTON_DOWN, input_policy.SDL_EVENT_MOUSE_BUTTON_UP => {
                    const modifiers = providerEmacsModifiers(SDL_GetModState());
                    const release: u16 = if (event.type == input_policy.SDL_EVENT_MOUSE_BUTTON_UP) 1 else 0;
                    try providerSendMouseEvent(2, release, modifiers, event.button.button - 1, event.button.x, event.button.y, event.button.timestamp);
                },
                SDL_EVENT_MOUSE_WHEEL => {
                    const modifiers = providerEmacsModifiers(SDL_GetModState());
                    const down: u32 = if (event.wheel.y > 0) 1 else 0;
                    try providerSendMouseEvent(5, 0, modifiers, down, event.wheel.mouse_x, event.wheel.mouse_y, event.wheel.timestamp);
                },
                input_policy.SDL_EVENT_WINDOW_FOCUS_GAINED, input_policy.SDL_EVENT_WINDOW_FOCUS_LOST => {
                    const gained = event.type == input_policy.SDL_EVENT_WINDOW_FOCUS_GAINED;
                    try providerSendMouseEvent(if (gained) 7 else 8, 0, 0, 0, 0, 0, event.window.timestamp);
                },
                input_policy.SDL_EVENT_WINDOW_RESIZED => {
                    try providerSendMouseEvent(10, 0, 0, 0, @floatFromInt(event.window.data1), @floatFromInt(event.window.data2), event.window.timestamp);
                },
                input_policy.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                    try providerSendMouseEvent(9, 0, 0, 0, 0, 0, event.window.timestamp);
                },
                else => {},
            }
        }

        if (snapshot == null and length_prefix_read == 0) {
            length_prefix_read = providerReadAvailable(&length_prefix) catch |err| {
                if (err == error.ProviderSurfaceClosed) break;
                return err;
            };
            if (length_prefix_read == 0) {
                SDL_Delay(10);
                continue;
            }
        }
        if (snapshot == null) {
            if (length_prefix_read < length_prefix.len) {
                try providerReadExact(length_prefix[length_prefix_read..]);
                length_prefix_read = length_prefix.len;
            }
            const length = std.mem.readInt(u32, &length_prefix, .little);
            const owned = try gpa.alloc(u8, length);
            try providerReadExact(owned);
            snapshot = owned;
        }
        if (snapshot) |bytes| {
            const result = try providerApplySnapshot(bytes, &scene);
            if (result.rows == 0 or result.runs == 0) return error.ProviderSnapshotEmpty;
            snapshot_rows = result.rows;
            snapshot_runs = result.runs;
            gpa.free(bytes);
            snapshot = null;
            length_prefix_read = 0;
            if (!first_snapshot_rendered) {
                std.debug.print("sdl3-provider-frame: terminal={d}:{d} frame={d}:{d} surface={d}x{d} rows={d} runs={d} pass\n", .{
                    terminal_id, terminal_generation, frame_id,      frame_generation,
                    width,       height,              snapshot_rows, snapshot_runs,
                });
                first_snapshot_rendered = true;
                if (std.c.getenv("TPE_INPUT_SMOKE") != null) {
                    var synthetic = keyboardEvent(input_policy.SDL_SCANCODE_LEFT, true, 0);
                    if (!SDL_PushEvent(&synthetic)) return sdlFail("SDL_PushEvent");
                    var mouse = mouseButtonEvent(17, 21, input_policy.SDL_EVENT_MOUSE_BUTTON_DOWN, true);
                    mouse.button.timestamp = 1;
                    if (!SDL_PushEvent(&mouse)) return sdlFail("SDL_PushEvent");
                    mouse = mouseButtonEvent(17, 21, input_policy.SDL_EVENT_MOUSE_BUTTON_UP, false);
                    mouse.button.timestamp = 2;
                    if (!SDL_PushEvent(&mouse)) return sdlFail("SDL_PushEvent");
                    mouse = pointerButtonEvent(17, 21, input_policy.SDL_EVENT_MOUSE_BUTTON_DOWN, true, 2, 1);
                    mouse.button.timestamp = 3;
                    if (!SDL_PushEvent(&mouse)) return sdlFail("SDL_PushEvent");
                    mouse = pointerButtonEvent(17, 21, input_policy.SDL_EVENT_MOUSE_BUTTON_UP, false, 2, 1);
                    mouse.button.timestamp = 4;
                    if (!SDL_PushEvent(&mouse)) return sdlFail("SDL_PushEvent");
                    mouse = pointerButtonEvent(17, 21, input_policy.SDL_EVENT_MOUSE_BUTTON_DOWN, true, 3, 1);
                    mouse.button.timestamp = 5;
                    if (!SDL_PushEvent(&mouse)) return sdlFail("SDL_PushEvent");
                    mouse = pointerButtonEvent(17, 21, input_policy.SDL_EVENT_MOUSE_BUTTON_UP, false, 3, 1);
                    mouse.button.timestamp = 6;
                    if (!SDL_PushEvent(&mouse)) return sdlFail("SDL_PushEvent");
                    var wheel = wheelEvent(0, 1);
                    if (!SDL_PushEvent(&wheel)) return sdlFail("SDL_PushEvent");
                    var resized = windowEvent(
                        input_policy.SDL_EVENT_WINDOW_RESIZED,
                        SDL_GetWindowID(window),
                        1200,
                        760,
                    );
                    if (!SDL_PushEvent(&resized)) return sdlFail("SDL_PushEvent");
                    var text = textEvent("\u{e9}\u{4e2d}");
                    if (!SDL_PushEvent(&text)) return sdlFail("SDL_PushEvent");
                    var hover = mouseMotionEvent(2, 0, 0);
                    if (!SDL_PushEvent(&hover)) return sdlFail("SDL_PushEvent");
                }
            }

            var output_width: c_int = 0;
            var output_height: c_int = 0;
            SDL_GetWindowSize(window, &output_width, &output_height);
            try buildSceneDrawList(&scene, &draw_list, output_width, output_height);
            _ = try executeDrawList(&texture_cache, null, &draw_list, renderer, window, null, null, false);
            if (!SDL_RenderPresent(renderer)) return sdlFail("SDL_RenderPresent");
            if (!SDL_SetRenderDrawColor(renderer, 0x10, 0x12, 0x18, 255)) return sdlFail("SDL_SetRenderDrawColor");
            if (!SDL_RenderClear(renderer)) return sdlFail("SDL_RenderClear");
            if (!SDL_RenderPresent(renderer)) return sdlFail("SDL_RenderPresent");
            try providerWriteAll("R");
            first_snapshot_rendered = true;
            if (std.c.getenv("TPE_INPUT_SMOKE") != null and
                snapshot_rows > 24 and !smoke_hover_resent)
            {
                smoke_hover_resent = true;
                SDL_Delay(100);
                var hover = mouseMotionEvent(2, 0, 0);
                if (!SDL_PushEvent(&hover)) return sdlFail("SDL_PushEvent");
            }
        }
    }
}

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

fn runTouchTapSmoke() !void {
    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow(
        "Emacs Proto-UI Touch",
        480,
        320,
        SDL_WINDOW_RESIZABLE,
    ) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);
    var window_width: c_int = 0;
    var window_height: c_int = 0;
    SDL_GetWindowSize(window, &window_width, &window_height);
    if (window_width <= 0 or window_height <= 0) return error.TouchWindowSizeUnavailable;
    const width: f32 = @floatFromInt(window_width);
    const height: f32 = @floatFromInt(window_height);
    const Expected = struct { phase: input_policy.PointerPhaseV2, x: i32, y: i32 };
    const expected = [_]Expected{
        .{ .phase = .press, .x = @intFromFloat(0.5 * width), .y = @intFromFloat(0.25 * height) },
        .{ .phase = .drag, .x = @intFromFloat(0.5 * width), .y = @intFromFloat(0.5 * height) },
        .{ .phase = .release, .x = @intFromFloat(0.5 * width), .y = @intFromFloat(0.5 * height) },
        .{ .phase = .press, .x = @intFromFloat(0.5 * width), .y = @intFromFloat(0.75 * height) },
        .{ .phase = .cancel, .x = @intFromFloat(0.5 * width), .y = @intFromFloat(0.75 * height) },
    };
    var synthetic = [_]SDL_Event{
        touchFingerEvent(input_policy.SDL_EVENT_FINGER_DOWN, 0.5, 0.25),
        touchFingerEvent(input_policy.SDL_EVENT_FINGER_MOTION, 0.5, 0.5),
        touchFingerEvent(input_policy.SDL_EVENT_FINGER_UP, 0.5, 0.5),
        touchFingerEvent(input_policy.SDL_EVENT_FINGER_DOWN, 0.5, 0.75),
        touchFingerEvent(input_policy.SDL_EVENT_FINGER_CANCELED, 0.5, 0.75),
    };
    for (&synthetic) |*event| {
        if (!SDL_PushEvent(event)) return sdlFail("SDL_PushEvent");
    }
    var journal: input_policy.DeliveryJournal = .{};
    journal.pointer_v2_negotiated = true;
    if (!input_policy.pointerV2Negotiated(&journal, true)) return error.CapabilityJournalMismatch;
    var received: usize = 0;
    var polls: usize = 0;
    while (received < expected.len and polls < 256) : (polls += 1) {
        var event: SDL_Event = undefined;
        if (!SDL_PollEvent(&event)) {
            SDL_Delay(1);
            continue;
        }
        if (event.type < input_policy.SDL_EVENT_FINGER_DOWN or
            event.type > input_policy.SDL_EVENT_FINGER_CANCELED) continue;
        const translated = input_policy.translateFinger(.{
            .event_type = event.type,
            .normalized_x = event.finger.x,
            .normalized_y = event.finger.y,
            .window_width = window_width,
            .window_height = window_height,
        }) orelse return error.TouchTranslationFailed;
        if (translated.phase != expected[received].phase or
            translated.x != expected[received].x or
            translated.y != expected[received].y)
            return error.TouchTranslationMismatch;
        try journal.pushPointerV2(translated);
        received += 1;
    }
    if (received != expected.len or journal.queue.length != expected.len)
        return error.TouchTranslationIncomplete;
    // A second concurrent contact cannot open a second bounded session.
    var single: input_policy.DeliveryJournal = .{};
    single.pointer_v2_negotiated = true;
    const press = input_policy.translateFinger(.{
        .event_type = input_policy.SDL_EVENT_FINGER_DOWN,
        .normalized_x = 0.5,
        .normalized_y = 0.5,
        .window_width = window_width,
        .window_height = window_height,
    }).?;
    try single.pushPointerV2(press);
    single.pushPointerV2(press) catch |err| switch (err) {
        error.PointerSessionActive => {},
        else => return err,
    };
    if (!single.pointer_active) return error.TouchMultiContactAdmitted;
    single.pushPointerV2(input_policy.translateFinger(.{
        .event_type = input_policy.SDL_EVENT_FINGER_CANCELED,
        .normalized_x = 0.5,
        .normalized_y = 0.5,
        .window_width = window_width,
        .window_height = window_height,
    }).?) catch |err| switch (err) {
        error.PointerSessionActive => {},
        else => return err,
    };
    if (single.pointer_active) return error.TouchMultiContactAdmitted;
    if (input_policy.translateFinger(.{
        .event_type = input_policy.SDL_EVENT_FINGER_DOWN,
        .normalized_x = 1.5,
        .normalized_y = 0.5,
        .window_width = window_width,
        .window_height = window_height,
    }) != null) return error.TouchOutOfRangeAdmitted;
    std.debug.print(
        "sdl3-touch-tap-smoke: {{\"kind\":\"sdl3-touch-tap-smoke\",\"capability\":\"input.touch_bounded_v1\",\"order\":[\"press\",\"drag\",\"release\",\"press\",\"cancel\"],\"window\":\"{d}x{d}\",\"converted\":[{d},{d}],\"multi_contact_rejected\":true,\"out_of_range_rejected\":true,\"result\":\"pass\"}}\n",
        .{ window_width, window_height, expected[0].x, expected[0].y },
    );
}

fn runMenuHitSmoke(gpa: std.mem.Allocator) !void {
    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow(
        "Emacs Proto-UI Menu Hit",
        80,
        60,
        SDL_WINDOW_HIDDEN,
    ) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);

    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    {
        var payload: [8]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], 7, .little);
        std.mem.writeInt(u32, payload[4..8], 1, .little);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.frame_create,
            1,
            capability.session_id,
            7,
            &payload,
        );
    }
    {
        const header: protocol.FrameUpdateHeader = .{
            .frame_id = 7,
            .frame_generation = 1,
            .sequence = 2,
            .redisplay_generation = 1,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = 80,
            .logical_height = 60,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = 80,
            .physical_height = 60,
            .scale = 1,
            .dpi_x = 96,
            .dpi_y = 96,
            .damage_mode = 2,
            .update_cause = 1,
            .coalesced_count = 0,
            .timestamp_ns = 2,
        };
        var windows: std.ArrayList(u8) = .empty;
        defer windows.deinit(gpa);
        try frontend.encodeWindow(gpa, .{
            .id = 100,
            .frame_id = 7,
            .x = 0,
            .y = 0,
            .width = 80,
            .height = 60,
        }, &windows);
        var damage: std.ArrayList(u8) = .empty;
        defer damage.deinit(gpa);
        try frontend.encodeRect(gpa, .{ .x = 0, .y = 0, .width = 80, .height = 60 }, &damage);
        const sections = [_]protocol.Section{
            .{ .kind = protocol.SectionKind.windows, .records = windows.items },
            .{ .kind = protocol.SectionKind.damage, .records = damage.items },
        };
        var frame_payload: std.ArrayList(u8) = .empty;
        defer frame_payload.deinit(gpa);
        try protocol.encodeFrameUpdate(gpa, .{ .header = header, .sections = &sections }, &frame_payload);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.frame_update,
            2,
            capability.session_id,
            7,
            frame_payload.items,
        );
    }
    const menu_icon_pixels: [16]u8 = .{
        0x10, 0x20, 0x30, 255, 0x40, 0x50, 0x60, 255,
        0x70, 0x80, 0x90, 255, 0xa0, 0xb0, 0xc0, 255,
    };
    const menu_icon_define = try protocol.encodeImageDefineBytes(.{
        .image_id = 41,
        .generation = 1,
        .width = 2,
        .height = 2,
        .total_byte_count = menu_icon_pixels.len,
        .cache_policy = .pinned,
    });
    try applyRuntimeSceneMessage(
        gpa,
        &scene,
        protocol.Message.image_define,
        3,
        capability.session_id,
        7,
        &menu_icon_define,
    );
    var menu_icon_data: std.ArrayList(u8) = .empty;
    defer menu_icon_data.deinit(gpa);
    try protocol.encodeImageData(gpa, .{
        .image_id = 41,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 1,
        .bytes = &menu_icon_pixels,
    }, &menu_icon_data);
    try applyRuntimeSceneMessage(
        gpa,
        &scene,
        protocol.Message.image_data,
        4,
        capability.session_id,
        7,
        menu_icon_data.items,
    );
    var nodes = [_]protocol.MenuNode{
        .{
            .item_id = 20,
            .parent_item_id = 0,
            .kind = .submenu,
            .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
            .depth = 0,
            .label_len = 4,
        },
        .{
            .item_id = 21,
            .parent_item_id = 20,
            .kind = .command,
            .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
            .depth = 1,
            .label_len = 3,
            .icon_image_id = 41,
            .icon_image_generation = 1,
        },
        .{
            .item_id = 22,
            .parent_item_id = 20,
            .kind = .separator,
            .flags = protocol.MenuNodeFlags.visible,
            .depth = 1,
            .label_len = 0,
        },
        .{
            .item_id = 24,
            .parent_item_id = 20,
            .kind = .checkbox,
            .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible |
                protocol.MenuNodeFlags.selected,
            .depth = 1,
            .label_len = 4,
        },
        .{
            .item_id = 25,
            .parent_item_id = 20,
            .kind = .command,
            .flags = protocol.MenuNodeFlags.visible,
            .depth = 1,
            .label_len = 8,
        },
        .{
            .item_id = 26,
            .parent_item_id = 20,
            .kind = .submenu,
            .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
            .depth = 1,
            .label_len = 6,
            .help_len = 4,
        },
        .{
            .item_id = 27,
            .parent_item_id = 20,
            .kind = .radio,
            .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible |
                protocol.MenuNodeFlags.selected,
            .depth = 1,
            .label_len = 5,
        },
    };
    @memcpy(nodes[0].label[0..4], "File");
    @memcpy(nodes[1].label[0..3], "New");
    @memcpy(nodes[3].label[0..4], "Wrap");
    @memcpy(nodes[4].label[0..8], "Disabled");
    @memcpy(nodes[5].label[0..6], "Sorted");
    @memcpy(nodes[5].help[0..4], "Sort");
    @memcpy(nodes[6].label[0..5], "Radio");
    var menu_payload: std.ArrayList(u8) = .empty;
    defer menu_payload.deinit(gpa);
    try protocol.encodeMenuModelSnapshot(gpa, .{
        .header = .{ .frame_id = 7, .frame_generation = 1, .menu_id = 3, .menu_generation = 1 },
        .nodes = &nodes,
    }, &menu_payload);
    try applyRuntimeSceneMessage(
        gpa,
        &scene,
        protocol.Message.menu_model,
        5,
        capability.session_id,
        7,
        menu_payload.items,
    );
    menu_payload.clearRetainingCapacity();
    try protocol.encodeMenuOpen(gpa, .{
        .menu_id = 3,
        .menu_generation = 1,
        .item_id = 20,
        .window_id = 100,
        .frame_generation = 1,
        .x = 16,
        .y = 16,
        .width = 48,
        .height = 40,
    }, &menu_payload);
    try applyRuntimeSceneMessage(
        gpa,
        &scene,
        protocol.Message.menu_open,
        6,
        capability.session_id,
        7,
        menu_payload.items,
    );

    const bounds = frontend.menuPopupBounds(&scene) orelse return error.MenuHitNoBounds;
    if (bounds.child_count != 6) return error.MenuHitUnexpectedRows;

    var delivery: input_policy.DeliveryJournal = .{};
    delivery.menu_result_negotiated = true;
    delivery.menu_hover_negotiated = true;
    delivery.menu_open_request_negotiated = true;
    var menu_pointer_capabilities: capability.Set = .{};
    menu_pointer_capabilities.insert(.widget_menu_result_v1);
    menu_pointer_capabilities.insert(.widget_menu_open_request_v1);
    const inside_x: i32 = @as(i32, @intFromFloat(bounds.x)) + 4;
    const first_row_y: i32 = @intFromFloat(bounds.y + bounds.row_height * 0.5);
    const second_row_y: i32 = @intFromFloat(bounds.y + bounds.row_height * 1.5);

    // A press on the command row selects it; the matching release is consumed.
    if (!try handleOpenMenuPointer(&delivery, &scene, window, menu_pointer_capabilities, true, inside_x, first_row_y))
        return error.MenuHitPressNotConsumed;
    if (!try handleOpenMenuPointer(&delivery, &scene, window, menu_pointer_capabilities, false, inside_x, first_row_y))
        return error.MenuHitReleaseNotConsumed;
    // A separator row and a press outside the popup are consumed without a
    // selection; only the outside press reports a dismissal.
    if (!try handleOpenMenuPointer(&delivery, &scene, window, menu_pointer_capabilities, true, inside_x, second_row_y))
        return error.MenuHitSeparatorNotConsumed;
    if (!try handleOpenMenuPointer(&delivery, &scene, window, menu_pointer_capabilities, false, inside_x, second_row_y))
        return error.MenuHitSeparatorReleaseNotConsumed;
    if (!try handleOpenMenuPointer(&delivery, &scene, window, menu_pointer_capabilities, true, 90, 90))
        return error.MenuHitOutsideNotConsumed;
    if (!try handleOpenMenuPointer(&delivery, &scene, window, menu_pointer_capabilities, false, 90, 90))
        return error.MenuHitOutsideReleaseNotConsumed;

    var selected_item: u32 = 0;
    var cancel_user = false;
    while (delivery.queue.pop()) |event| switch (event) {
        .menu_result => |result| {
            if (selected_item != 0) return error.MenuHitDuplicateResult;
            selected_item = result.item_id;
        },
        .menu_cancel => |cancel| {
            if (cancel.reason != .user) return error.MenuHitUnexpectedCancel;
            cancel_user = true;
        },
        else => return error.MenuHitUnexpectedEvent,
    };
    if (selected_item != 21) return error.MenuHitWrongItem;
    if (!cancel_user) return error.MenuHitNoDismissal;

    // Escape on an open popup reports the keyboard dismissal.
    const escape_key: SDL_KeyboardEvent = .{
        .type = SDL_EVENT_KEY_DOWN,
        .reserved = 0,
        .timestamp = 0,
        .window_id = 0,
        .which = 0,
        .scancode = input_policy.SDL_SCANCODE_ESCAPE,
        .key = 0,
        .modifiers = 0,
        .raw = 0,
        .down = true,
        .repeat = false,
    };
    if (!try consumeOpenMenuEscape(&delivery, &scene, escape_key))
        return error.MenuEscapeNotConsumed;
    var escape_cancel = false;
    while (delivery.queue.pop()) |event| switch (event) {
        .menu_cancel => |cancel| {
            if (cancel.reason != .escape) return error.MenuEscapeWrongReason;
            escape_cancel = true;
        },
        else => return error.MenuEscapeUnexpectedEvent,
    };
    if (!escape_cancel) return error.MenuEscapeNoCancel;
    if (scene.menu_highlight_item != 0) return error.MenuHighlightNotCleared;

    // Pointer hover drives the same highlight cursor: entering a selectable row
    // reports one enter, moving onto the separator row reports a leave, and the
    // keyboard then walks the selectable rows without touching the separator.
    const third_row_y: i32 = @intFromFloat(bounds.y + bounds.row_height * 2.5);
    const submenu_row_y: i32 = @intFromFloat(bounds.y + bounds.row_height * 4.5);
    const radio_row_y: i32 = @intFromFloat(bounds.y + bounds.row_height * 5.5);
    if (!try handleMenuHoverMotion(&delivery, &scene, window, menu_pointer_capabilities, inside_x, radio_row_y))
        return error.MenuHoverMotionNotConsumed;
    if (scene.menu_highlight_item != 27) return error.MenuHoverRadioHighlightWrong;
    if (!try handleMenuHoverMotion(&delivery, &scene, window, menu_pointer_capabilities, inside_x, first_row_y))
        return error.MenuHoverMotionNotConsumed;
    if (scene.menu_highlight_item != 21) return error.MenuHoverHighlightWrong;
    if (!try handleMenuHoverMotion(&delivery, &scene, window, menu_pointer_capabilities, inside_x, second_row_y))
        return error.MenuHoverMotionNotConsumed;
    if (scene.menu_highlight_item != 0) return error.MenuHoverSeparatorHighlighted;
    if (!try handleMenuHoverMotion(&delivery, &scene, window, menu_pointer_capabilities, inside_x, third_row_y))
        return error.MenuHoverMotionNotConsumed;
    if (scene.menu_highlight_item != 24) return error.MenuHoverHighlightWrong;
    if (!try handleMenuHoverMotion(&delivery, &scene, window, menu_pointer_capabilities, inside_x, submenu_row_y))
        return error.MenuHoverMotionNotConsumed;
    if (scene.menu_highlight_item != 26) return error.MenuHoverSubmenuHighlightWrong;

    const hover_phases = [_]protocol.MenuHoverPhase{ .enter, .leave, .enter, .leave, .enter, .leave, .enter };
    const hover_items = [_]u32{ 27, 0, 21, 0, 24, 0, 26 };
    var hover_index: usize = 0;
    var hover_open_request = false;
    while (delivery.queue.pop()) |event| switch (event) {
        .menu_hover => |hover| {
            if (hover_index >= hover_phases.len) return error.MenuHoverSequenceTooLong;
            if (hover.phase != hover_phases[hover_index] or
                hover.item_id != hover_items[hover_index])
                return error.MenuHoverSequenceMismatch;
            if (hover.menu_id != 3 or hover.window_id != 100 or hover.frame_generation != 1)
                return error.MenuHoverWrongIdentity;
            if (hover.phase == .leave and (hover.item_id != 0 or hover.x != 0 or hover.y != 0))
                return error.MenuHoverLeaveNotEmpty;
            hover_index += 1;
        },
        .menu_open_request => |request| {
            if (hover_open_request or request.item_id != 26) return error.MenuHoverOpenRequestWrong;
            hover_open_request = true;
        },
        else => return error.MenuHoverUnexpectedEvent,
    };
    if (hover_index != hover_phases.len or !hover_open_request)
        return error.MenuHoverSequenceIncomplete;

    // Keyboard navigation skips the separator and Enter chooses the highlight.
    const up_key: SDL_KeyboardEvent = .{
        .type = SDL_EVENT_KEY_DOWN,
        .reserved = 0,
        .timestamp = 0,
        .window_id = 0,
        .which = 0,
        .scancode = input_policy.SDL_SCANCODE_UP,
        .key = 0,
        .modifiers = 0,
        .raw = 0,
        .down = true,
        .repeat = false,
    };
    var down_key = up_key;
    down_key.scancode = input_policy.SDL_SCANCODE_DOWN;
    var return_key = up_key;
    return_key.scancode = input_policy.SDL_SCANCODE_RETURN;

    if (!try handleMenuKey(&delivery, &scene, up_key)) return error.MenuNavUpNotConsumed;
    if (scene.menu_highlight_item != 24) return error.MenuNavUpWrongRow;
    _ = delivery.queue.pop();
    _ = delivery.queue.pop();
    if (!try consumeMenuEnter(&delivery, &scene, return_key, menu_pointer_capabilities))
        return error.MenuEnterNotConsumed;
    var chosen = false;
    while (delivery.queue.pop()) |event| switch (event) {
        .menu_result => |result| {
            if (result.item_id != 24) return error.MenuEnterWrongItem;
            chosen = true;
        },
        else => return error.MenuEnterUnexpectedEvent,
    };
    if (!chosen) return error.MenuEnterNoResult;
    if (!try handleMenuKey(&delivery, &scene, down_key)) return error.MenuNavDownNotConsumed;
    if (scene.menu_highlight_item != 26) return error.MenuNavDownWrongRow;
    if (!try handleMenuKey(&delivery, &scene, down_key)) return error.MenuNavDownNotConsumed;
    if (scene.menu_highlight_item != 27) return error.MenuNavDownRadioWrong;
    if (!try handleMenuKey(&delivery, &scene, up_key)) return error.MenuNavUpNotConsumed;
    if (scene.menu_highlight_item != 26) return error.MenuNavUpWrongRow;
    const nav_phases = [_]protocol.MenuHoverPhase{ .leave, .enter, .leave, .enter, .leave, .enter };
    const nav_items = [_]u32{ 0, 26, 0, 27, 0, 26 };
    var nav_index: usize = 0;
    while (delivery.queue.pop()) |event| switch (event) {
        .menu_hover => |hover| {
            if (nav_index >= nav_phases.len) return error.MenuNavSequenceTooLong;
            if (hover.phase != nav_phases[nav_index] or hover.item_id != nav_items[nav_index])
                return error.MenuNavSequenceMismatch;
            nav_index += 1;
        },
        else => return error.MenuNavUnexpectedEvent,
    };
    if (nav_index != nav_phases.len) return error.MenuNavSequenceIncomplete;
    if (!try consumeMenuEnter(&delivery, &scene, return_key, menu_pointer_capabilities))
        return error.MenuEnterNotConsumed;
    var keyboard_open_request = false;
    while (delivery.queue.pop()) |event| switch (event) {
        .menu_open_request => |request| {
            if (keyboard_open_request or request.item_id != 26)
                return error.MenuEnterOpenRequestWrong;
            keyboard_open_request = true;
        },
        else => return error.MenuEnterUnexpectedEvent,
    };
    if (!keyboard_open_request) return error.MenuEnterNoOpenRequest;

    // Backend-owned item state is rendered faithfully: a selected checkbox gets
    // a leading marker with a shifted label, a disabled row is dimmed, and an
    // enabled command stays bright at the unreserved label offset.
    var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
    defer draw_list.deinit();
    try buildSceneDrawList(&scene, &draw_list, 80, 60);
    const checkbox_row: f32 = bounds.y + bounds.row_height * 2;
    var marker_rendered = false;
    var radio_dot_rendered = false;
    var menu_icon_rendered = false;
    var checkbox_label_shifted = false;
    var radio_label_shifted = false;
    var disabled_dimmed = false;
    var enabled_bright = false;
    var help_tip_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .image => |draw| {
                if (draw.rect.x == bounds.x + 3 and
                    draw.rect.y == bounds.y + 1 and
                    draw.rect.width == 4 and draw.rect.height == 4 and
                    draw.width == 2 and draw.height == 2 and
                    std.mem.eql(u8, draw.pixels, &menu_icon_pixels))
                    menu_icon_rendered = true;
            },
            .fill => |fill| {
                if (fill.rect.x == bounds.x + 3 and
                    fill.rect.y == checkbox_row + (bounds.row_height - 4) / 2 and
                    fill.rect.width == 4 and fill.rect.height == 4 and
                    fill.color.r == 0x71 and fill.color.g == 0xa6 and fill.color.b == 0xf2)
                    marker_rendered = true;
                const radio_row: f32 = bounds.y + bounds.row_height * 5;
                if (fill.rect.x == bounds.x + 4 and
                    fill.rect.y == radio_row + (bounds.row_height - 2) / 2 and
                    fill.rect.width == 2 and fill.rect.height == 2 and
                    fill.color.r == 0x71 and fill.color.g == 0xa6 and fill.color.b == 0xf2)
                    radio_dot_rendered = true;
            },
            .unicode_text => |text| {
                if (text.x == bounds.x + 12 and std.mem.eql(u8, text.bytes, "Wrap") and
                    text.color.r == 0xff)
                    checkbox_label_shifted = true;
                if (text.x == bounds.x + 12 and std.mem.eql(u8, text.bytes, "Radio") and
                    text.color.r == 0xff)
                    radio_label_shifted = true;
                if (std.mem.eql(u8, text.bytes, "Disabled") and text.color.r == 0x88)
                    disabled_dimmed = true;
                if (text.x == bounds.x + 12 and std.mem.eql(u8, text.bytes, "New") and
                    text.color.r == 0xff)
                    enabled_bright = true;
                if (std.mem.eql(u8, text.bytes, "Sort") and text.color.b == 0xf0)
                    help_tip_rendered = true;
            },
            else => {},
        }
    }
    if (!marker_rendered or !radio_dot_rendered or !menu_icon_rendered or
        !checkbox_label_shifted or !radio_label_shifted or !disabled_dimmed or
        !enabled_bright or !help_tip_rendered)
    {
        return error.MenuItemStateNotRendered;
    }

    std.debug.print(
        "sdl3-menu-hit-smoke: {{\"kind\":\"sdl3-menu-hit-smoke\",\"capability\":\"widget.menu_result_v1\",\"rows\":{d},\"selected_item\":{d},\"dismiss\":\"user\",\"escape\":\"escape\",\"hover\":[\"enter\",\"leave\",\"enter\",\"leave\",\"enter\"],\"nav\":[\"leave\",\"enter\",\"leave\",\"enter\",\"leave\",\"enter\"],\"enter_item\":24,\"selected_marker\":true,\"radio_dot\":true,\"menu_icon\":true,\"popup_help\":true,\"disabled_dimmed\":true,\"result\":\"pass\"}}\n",
        .{ bounds.child_count, selected_item },
    );
}

fn runToolbarHitSmoke(gpa: std.mem.Allocator) !void {
    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow(
        "Emacs Proto-UI Toolbar Hit",
        80,
        60,
        SDL_WINDOW_HIDDEN,
    ) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);

    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    {
        var payload: [8]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], 7, .little);
        std.mem.writeInt(u32, payload[4..8], 1, .little);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.frame_create,
            1,
            capability.session_id,
            7,
            &payload,
        );
    }
    {
        const header: protocol.FrameUpdateHeader = .{
            .frame_id = 7,
            .frame_generation = 1,
            .sequence = 2,
            .redisplay_generation = 1,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = 80,
            .logical_height = 60,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = 80,
            .physical_height = 60,
            .scale = 1,
            .dpi_x = 96,
            .dpi_y = 96,
            .damage_mode = 2,
            .update_cause = 1,
            .coalesced_count = 0,
            .timestamp_ns = 2,
        };
        var windows: std.ArrayList(u8) = .empty;
        defer windows.deinit(gpa);
        try frontend.encodeWindow(gpa, .{
            .id = 100,
            .frame_id = 7,
            .x = 0,
            .y = 0,
            .width = 80,
            .height = 60,
        }, &windows);
        var damage: std.ArrayList(u8) = .empty;
        defer damage.deinit(gpa);
        try frontend.encodeRect(gpa, .{ .x = 0, .y = 0, .width = 80, .height = 60 }, &damage);
        const sections = [_]protocol.Section{
            .{ .kind = protocol.SectionKind.windows, .records = windows.items },
            .{ .kind = protocol.SectionKind.damage, .records = damage.items },
        };
        var frame_payload: std.ArrayList(u8) = .empty;
        defer frame_payload.deinit(gpa);
        try protocol.encodeFrameUpdate(gpa, .{ .header = header, .sections = &sections }, &frame_payload);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.frame_update,
            2,
            capability.session_id,
            7,
            frame_payload.items,
        );
    }
    var toolbar_items: [4]protocol.ToolbarItem = undefined;
    const model = protocol.toolbarModelFixture(&toolbar_items);
    // The first button carries a live 2x2 icon resource; the second has no
    // icon and must keep its text label.
    toolbar_items[0].icon_image_id = 31;
    toolbar_items[0].icon_image_generation = 1;
    // The second item references a stale icon generation, so it must fall back
    // to its text label instead of drawing a mismatched resource.
    toolbar_items[1].icon_image_id = 31;
    toolbar_items[1].icon_image_generation = 2;
    var toolbar_payload: std.ArrayList(u8) = .empty;
    defer toolbar_payload.deinit(gpa);
    try protocol.encodeToolbarModel(gpa, model, &toolbar_payload);
    try applyRuntimeSceneMessage(
        gpa,
        &scene,
        protocol.Message.toolbar_model,
        3,
        capability.session_id,
        7,
        toolbar_payload.items,
    );
    const icon_pixels: [16]u8 = .{
        1, 2, 3, 255, 4,  5,  6,  255,
        7, 8, 9, 255, 10, 11, 12, 255,
    };
    const icon_define = try protocol.encodeImageDefineBytes(.{
        .image_id = 31,
        .generation = 1,
        .width = 2,
        .height = 2,
        .total_byte_count = icon_pixels.len,
        .cache_policy = .pinned,
    });
    try applyRuntimeSceneMessage(
        gpa,
        &scene,
        protocol.Message.image_define,
        4,
        capability.session_id,
        7,
        &icon_define,
    );
    var icon_data: std.ArrayList(u8) = .empty;
    defer icon_data.deinit(gpa);
    try protocol.encodeImageData(gpa, .{
        .image_id = 31,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 1,
        .bytes = &icon_pixels,
    }, &icon_data);
    try applyRuntimeSceneMessage(
        gpa,
        &scene,
        protocol.Message.image_data,
        5,
        capability.session_id,
        7,
        icon_data.items,
    );
    const layout = frontend.toolbarLayout(&scene) orelse return error.ToolbarHitNoLayout;
    if (layout.slot_count != 2) return error.ToolbarHitUnexpectedSlots;

    var delivery: input_policy.DeliveryJournal = .{};
    delivery.toolbar_click_negotiated = true;
    var tracker: ToolbarPressTracker = .{};
    const first_x: i32 = @as(i32, @intFromFloat(layout.slots[0].x)) + 4;
    const second_x: i32 = @as(i32, @intFromFloat(layout.slots[1].x)) + 4;
    const row_y: i32 = @as(i32, @intFromFloat(layout.slots[0].y)) + 4;
    const separator_x: i32 = @as(i32, @intFromFloat(
        layout.slots[1].x + layout.slots[1].width,
    )) + 2;

    // Both button rows complete a press/release pair.
    if (!try handleToolbarPointer(&delivery, &scene, &tracker, window, true, 1, 1, first_x, row_y))
        return error.ToolbarHitPressNotConsumed;
    if (!try handleToolbarPointer(&delivery, &scene, &tracker, window, false, 1, 1, first_x, row_y))
        return error.ToolbarHitReleaseNotConsumed;
    if (!try handleToolbarPointer(&delivery, &scene, &tracker, window, true, 1, 1, second_x, row_y))
        return error.ToolbarHitToggleNotConsumed;
    if (!try handleToolbarPointer(&delivery, &scene, &tracker, window, false, 1, 1, second_x, row_y))
        return error.ToolbarHitToggleReleaseNotConsumed;
    // A separator and the area outside the row are not consumed.
    if (try handleToolbarPointer(&delivery, &scene, &tracker, window, true, 1, 1, separator_x, row_y))
        return error.ToolbarHitSeparatorConsumed;
    if (try handleToolbarPointer(&delivery, &scene, &tracker, window, false, 1, 1, separator_x, row_y))
        return error.ToolbarHitSeparatorReleaseConsumed;
    if (try handleToolbarPointer(&delivery, &scene, &tracker, window, true, 1, 1, 300, 200))
        return error.ToolbarHitOutsideConsumed;

    var presses: usize = 0;
    var releases: usize = 0;
    var first_item: u32 = 0;
    var second_item: u32 = 0;
    while (delivery.queue.pop()) |event| switch (event) {
        .toolbar_click => |click| {
            if (click.toolbar_id != 9 or click.window_id != 100 or click.frame_generation != 1)
                return error.ToolbarHitWrongIdentity;
            switch (click.phase) {
                .press => {
                    presses += 1;
                    if (presses == 1) first_item = click.item_id else second_item = click.item_id;
                },
                .release => releases += 1,
            }
        },
        else => return error.ToolbarHitUnexpectedEvent,
    };
    if (presses != 2 or releases != 2) return error.ToolbarHitUnbalanced;
    if (first_item != 40 or second_item != 41) return error.ToolbarHitWrongItem;

    // A live icon resource replaces the label for that item; an icon-less item
    // keeps its text label.  This is checked before the model is replaced.
    var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
    defer draw_list.deinit();
    try buildSceneDrawList(&scene, &draw_list, 80, 60);
    var icon_rendered = false;
    var icon_label_suppressed = true;
    var label_only_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .image => |draw| {
                if (draw.rect.x == layout.slots[0].x and draw.rect.y == layout.slots[0].y and
                    draw.rect.width == layout.slots[0].width and
                    draw.rect.height == layout.slots[0].height and
                    draw.width == 2 and draw.height == 2 and
                    draw.pixels.len == icon_pixels.len and
                    std.mem.eql(u8, draw.pixels, &icon_pixels))
                    icon_rendered = true;
            },
            .unicode_text => |text| {
                if (std.mem.eql(u8, text.bytes, "Save")) icon_label_suppressed = false;
                if (text.x == layout.slots[1].x + 4 and
                    std.mem.eql(u8, text.bytes, "Overwrite"))
                    label_only_rendered = true;
            },
            else => {},
        }
    }
    if (!icon_rendered or !icon_label_suppressed or !label_only_rendered)
        return error.ToolbarIconNotRendered;

    // A replaced toolbar generation drops a stale press instead of reporting a
    // release for an item the backend has already retired.
    if (!try handleToolbarPointer(&delivery, &scene, &tracker, window, true, 1, 1, first_x, row_y))
        return error.ToolbarHitStalePressNotConsumed;
    var patch_operations = [_]protocol.ToolbarPatchOperation{.{ .operation = .delete, .item = .{
        .item_id = 40,
        .kind = .button,
        .flags = 0,
    } }};
    var patch_payload: std.ArrayList(u8) = .empty;
    defer patch_payload.deinit(gpa);
    try protocol.encodeToolbarPatch(gpa, .{
        .frame_id = 7,
        .frame_generation = 1,
        .toolbar_id = 9,
        .expected_generation = model.header.toolbar_generation,
        .new_generation = model.header.toolbar_generation + 1,
    }, &patch_operations, &patch_payload);
    try applyRuntimeSceneMessage(
        gpa,
        &scene,
        protocol.Message.toolbar_patch,
        6,
        capability.session_id,
        7,
        patch_payload.items,
    );
    if (try handleToolbarPointer(&delivery, &scene, &tracker, window, false, 1, 1, first_x, row_y))
        return error.ToolbarHitStaleReleaseConsumed;
    if (tracker.pressed != null) return error.ToolbarHitStalePressRetained;
    // Only the press emitted before the replacement may remain.
    if (delivery.queue.length != 1) return error.ToolbarHitStaleEventEmitted;
    switch (delivery.queue.pop() orelse return error.ToolbarHitStaleEventEmitted) {
        .toolbar_click => |click| {
            if (click.phase != .press or click.item_id != 40)
                return error.ToolbarHitStaleEventEmitted;
        },
        else => return error.ToolbarHitStaleEventEmitted,
    }

    std.debug.print(
        "sdl3-toolbar-hit-smoke: {{\"kind\":\"sdl3-toolbar-hit-smoke\",\"capability\":\"widget.toolbar_click_v1\",\"slots\":{d},\"items\":[{d},{d}],\"presses\":{d},\"releases\":{d},\"separator_inert\":true,\"stale_generation_dropped\":true,\"icon_rendered\":true,\"label_fallback\":true,\"result\":\"pass\"}}\n",
        .{ layout.slot_count, first_item, second_item, presses, releases },
    );
}

fn runCursorStyleSmoke(gpa: std.mem.Allocator) !void {
    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow(
        "Emacs Proto-UI Cursor Style",
        80,
        60,
        SDL_WINDOW_HIDDEN,
    ) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);

    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    {
        var payload: [8]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], 7, .little);
        std.mem.writeInt(u32, payload[4..8], 1, .little);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.frame_create,
            1,
            capability.session_id,
            7,
            &payload,
        );
    }
    {
        const header: protocol.FrameUpdateHeader = .{
            .frame_id = 7,
            .frame_generation = 1,
            .sequence = 2,
            .redisplay_generation = 1,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = 80,
            .logical_height = 60,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = 80,
            .physical_height = 60,
            .scale = 1,
            .dpi_x = 96,
            .dpi_y = 96,
            .damage_mode = 2,
            .update_cause = 1,
            .coalesced_count = 0,
            .timestamp_ns = 2,
        };
        var windows: std.ArrayList(u8) = .empty;
        defer windows.deinit(gpa);
        try frontend.encodeWindow(gpa, .{
            .id = 100,
            .frame_id = 7,
            .x = 0,
            .y = 0,
            .width = 80,
            .height = 60,
        }, &windows);
        var damage: std.ArrayList(u8) = .empty;
        defer damage.deinit(gpa);
        try frontend.encodeRect(gpa, .{ .x = 0, .y = 0, .width = 80, .height = 60 }, &damage);
        const sections = [_]protocol.Section{
            .{ .kind = protocol.SectionKind.windows, .records = windows.items },
            .{ .kind = protocol.SectionKind.damage, .records = damage.items },
        };
        var frame_payload: std.ArrayList(u8) = .empty;
        defer frame_payload.deinit(gpa);
        try protocol.encodeFrameUpdate(gpa, .{ .header = header, .sections = &sections }, &frame_payload);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.frame_update,
            2,
            capability.session_id,
            7,
            frame_payload.items,
        );
    }
    // A defined window face supplies the cursor color, so the style check also
    // proves the face foreground reaches the cursor.
    const cursor_foreground = [4]u8{ 0x20, 0xc0, 0x40, 255 };
    {
        var face_payload: std.ArrayList(u8) = .empty;
        defer face_payload.deinit(gpa);
        try protocol.encodeFaceDefine(gpa, .{
            .face_id = 7,
            .generation = 1,
            .presence = .{ .foreground = true, .background = true },
            .foreground = cursor_foreground,
            .background = .{ 0x10, 0x18, 0x20, 255 },
        }, &face_payload);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.face_define,
            3,
            capability.session_id,
            7,
            face_payload.items,
        );
        var face_state: std.ArrayList(u8) = .empty;
        defer face_state.deinit(gpa);
        try frontend.encodeWindowFaceState(gpa, .{
            .window_id = 100,
            .frame_generation = 1,
            .face_id = 7,
            .face_generation = 1,
        }, &face_state);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.window_face,
            4,
            capability.session_id,
            7,
            face_state.items,
        );
    }

    const cursor: frontend.Cursor = .{
        .window_id = 100,
        .x = 8,
        .y = 6,
        .width = 2,
        .height = 10,
        .kind = frontend.cursor_kind_box,
        .visible = true,
        .active = true,
    };
    var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
    defer draw_list.deinit();
    var sequence: u64 = 5;
    const sample = [_]struct { kind: u8, shape: frontend.CursorShape, fills: usize }{
        .{ .kind = frontend.cursor_kind_box, .shape = .box, .fills = 1 },
        .{ .kind = frontend.cursor_kind_bar, .shape = .bar, .fills = 1 },
        .{ .kind = frontend.cursor_kind_hbar, .shape = .hbar, .fills = 1 },
        .{ .kind = frontend.cursor_kind_hollow, .shape = .hollow, .fills = 4 },
        .{ .kind = frontend.cursor_kind_underline, .shape = .underline, .fills = 1 },
        .{ .kind = 99, .shape = .box, .fills = 1 },
    };
    for (sample) |step| {
        var update: std.ArrayList(u8) = .empty;
        defer update.deinit(gpa);
        var next = cursor;
        next.kind = step.kind;
        try frontend.encodeCursorUpdate(gpa, 1, next, &update);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.cursor_update,
            sequence,
            capability.session_id,
            7,
            update.items,
        );
        sequence += 1;
        try buildSceneDrawList(&scene, &draw_list, 80, 60);
        var cursor_fills: usize = 0;
        var color_matched = false;
        for (draw_list.commands.items) |command| switch (command) {
            .fill => |fill| {
                // Only the cursor uses the face foreground here.
                if (fill.color.r != cursor_foreground[0] or
                    fill.color.g != cursor_foreground[1] or
                    fill.color.b != cursor_foreground[2]) continue;
                cursor_fills += 1;
                color_matched = true;
            },
            else => {},
        };
        if (cursor_fills != step.fills or !color_matched) return error.CursorStyleMismatch;
        if (frontend.cursorShape(step.kind) != step.shape) return error.CursorShapeMappingMismatch;
    }
    std.debug.print(
        "sdl3-cursor-style-smoke: {{\"kind\":\"sdl3-cursor-style-smoke\",\"capability\":\"cursor.update_v1\",\"shapes\":[\"box\",\"bar\",\"hbar\",\"hollow\",\"underline\"],\"unknown_fallback\":\"box\",\"face_color\":[{d},{d},{d}],\"result\":\"pass\"}}\n",
        .{ cursor_foreground[0], cursor_foreground[1], cursor_foreground[2] },
    );
}

fn runFaceTextSmoke(gpa: std.mem.Allocator) !void {
    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow(
        "Emacs Proto-UI Face Text",
        80,
        60,
        SDL_WINDOW_HIDDEN,
    ) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);

    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    {
        var payload: [8]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], 7, .little);
        std.mem.writeInt(u32, payload[4..8], 1, .little);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.frame_create,
            1,
            capability.session_id,
            7,
            &payload,
        );
    }
    {
        const header: protocol.FrameUpdateHeader = .{
            .frame_id = 7,
            .frame_generation = 1,
            .sequence = 2,
            .redisplay_generation = 1,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = 80,
            .logical_height = 60,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = 80,
            .physical_height = 60,
            .scale = 1,
            .dpi_x = 96,
            .dpi_y = 96,
            .damage_mode = 2,
            .update_cause = 1,
            .coalesced_count = 0,
            .timestamp_ns = 2,
        };
        var windows: std.ArrayList(u8) = .empty;
        defer windows.deinit(gpa);
        try frontend.encodeWindow(gpa, .{
            .id = 100,
            .frame_id = 7,
            .x = 0,
            .y = 0,
            .width = 80,
            .height = 60,
        }, &windows);
        var rows: std.ArrayList(u8) = .empty;
        defer rows.deinit(gpa);
        try frontend.encodeRow(gpa, .{
            .window_id = 100,
            .index = 0,
            .flags = 0,
            .x = 0,
            .y = 0,
            .width = 80,
            .height = 10,
            .ascent = 7,
            .descent = 3,
            .baseline = 7,
            .visible_height = 10,
        }, &rows);
        var damage: std.ArrayList(u8) = .empty;
        defer damage.deinit(gpa);
        try frontend.encodeRect(gpa, .{ .x = 0, .y = 0, .width = 80, .height = 60 }, &damage);
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(gpa);
        try frontend.encodeTextLineV2(gpa, .{
            .window_id = 100,
            .row_index = 0,
            .line = "FaceText",
        }, &text);
        const sections = [_]protocol.Section{
            .{ .kind = protocol.SectionKind.windows, .records = windows.items },
            .{ .kind = protocol.SectionKind.rows, .records = rows.items },
            .{ .kind = protocol.SectionKind.damage, .records = damage.items },
            .{ .kind = protocol.SectionKind.extension_min + 2, .records = text.items },
        };
        var frame_payload: std.ArrayList(u8) = .empty;
        defer frame_payload.deinit(gpa);
        try protocol.encodeFrameUpdate(gpa, .{ .header = header, .sections = &sections }, &frame_payload);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.frame_update,
            2,
            capability.session_id,
            7,
            frame_payload.items,
        );
    }

    // Without a window face the live text keeps the draw default.
    var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
    defer draw_list.deinit();
    try buildSceneDrawList(&scene, &draw_list, 80, 60);
    var default_color = true;
    for (draw_list.commands.items) |command| switch (command) {
        .text => |draw| {
            if (std.mem.eql(u8, draw.bytes, "FaceText") and draw.color != null)
                default_color = false;
        },
        else => {},
    };
    if (!default_color) return error.FaceTextDefaultColorMismatch;

    // A defined window default face drives the live text foreground, and a
    // replacement generation is honoured on the next frame.
    const sample = [_]struct { generation: u32, foreground: [4]u8 }{
        .{ .generation = 1, .foreground = .{ 0xff, 0xd5, 0x4d, 255 } },
        .{ .generation = 2, .foreground = .{ 0x10, 0xe0, 0x40, 255 } },
    };
    var sequence: u64 = 3;
    for (sample) |step| {
        var face_payload: std.ArrayList(u8) = .empty;
        defer face_payload.deinit(gpa);
        try protocol.encodeFaceDefine(gpa, .{
            .face_id = 7,
            .generation = step.generation,
            .presence = .{ .foreground = true, .background = true },
            .foreground = step.foreground,
            .background = .{ 0x20, 0x28, 0x38, 255 },
        }, &face_payload);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.face_define,
            sequence,
            capability.session_id,
            7,
            face_payload.items,
        );
        sequence += 1;
        var face_state: std.ArrayList(u8) = .empty;
        defer face_state.deinit(gpa);
        try frontend.encodeWindowFaceState(gpa, .{
            .window_id = 100,
            .frame_generation = 1,
            .face_id = 7,
            .face_generation = step.generation,
        }, &face_state);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.window_face,
            sequence,
            capability.session_id,
            7,
            face_state.items,
        );
        sequence += 1;

        try buildSceneDrawList(&scene, &draw_list, 80, 60);
        var matched = false;
        for (draw_list.commands.items) |command| switch (command) {
            .text => |draw| {
                if (!std.mem.eql(u8, draw.bytes, "FaceText")) continue;
                const color = draw.color orelse return error.FaceTextColorMissing;
                if (color.r != step.foreground[0] or color.g != step.foreground[1] or
                    color.b != step.foreground[2] or color.a != step.foreground[3])
                    return error.FaceTextColorMismatch;
                matched = true;
            },
            else => {},
        };
        if (!matched) return error.FaceTextNotRendered;
    }

    std.debug.print(
        "sdl3-face-text-smoke: {{\"kind\":\"sdl3-face-text-smoke\",\"capability\":\"window.face_state_v1\",\"default_color_fallback\":true,\"face_foreground\":[{d},{d},{d}],\"generation_honoured\":true,\"result\":\"pass\"}}\n",
        .{ sample[1].foreground[0], sample[1].foreground[1], sample[1].foreground[2] },
    );
}

fn runPenSmoke() !void {
    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow(
        "Emacs Proto-UI Pen",
        480,
        320,
        SDL_WINDOW_HIDDEN,
    ) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);
    if (SDL_GetWindowID(window) == 0) return error.InvalidSdlWindowId;

    var journal: input_policy.DeliveryJournal = .{};
    journal.pointer_v2_negotiated = true;
    if (!input_policy.pointerV2Negotiated(&journal, true)) return error.CapabilityJournalMismatch;

    var synthetic = [_]SDL_Event{
        penEvent(input_policy.SDL_EVENT_PEN_MOTION, 20, 6, 0x8000_0000),
        penEvent(input_policy.SDL_EVENT_PEN_DOWN, 24, 8, input_policy.SDL_PEN_INPUT_DOWN),
        penEvent(input_policy.SDL_EVENT_PEN_MOTION, 40, 12, input_policy.SDL_PEN_INPUT_DOWN),
        penEvent(input_policy.SDL_EVENT_PEN_UP, 40, 12, 0),
        penEvent(input_policy.SDL_EVENT_PEN_DOWN, 8, 4, input_policy.SDL_PEN_INPUT_DOWN | input_policy.SDL_PEN_INPUT_ERASER_TIP),
    };
    for (&synthetic) |*event| {
        if (!SDL_PushEvent(event)) return sdlFail("SDL_PushEvent");
    }
    // Air hover (tip up), tip-down press, tip-down drag, tip-up release, and an
    // eraser event that must produce no intent at all.
    const expected = [_]?input_policy.PointerPhaseV2{ .motion, .press, .drag, .release, null };
    var received: usize = 0;
    var polls: usize = 0;
    while (received < expected.len and polls < 256) : (polls += 1) {
        var event: SDL_Event = undefined;
        if (!SDL_PollEvent(&event)) {
            SDL_Delay(1);
            continue;
        }
        if (event.type < input_policy.SDL_EVENT_PEN_DOWN or
            event.type > input_policy.SDL_EVENT_PEN_MOTION) continue;
        const translated = input_policy.translatePen(.{
            .event_type = event.type,
            .x = @intFromFloat(event.pen.x),
            .y = @intFromFloat(event.pen.y),
            .pen_state = event.pen.pen_state,
        });
        const want = expected[received];
        if (want == null) {
            if (translated != null) return error.PenEraserNotRejected;
            received += 1;
            continue;
        }
        const intent = translated orelse return error.PenTranslationFailed;
        if (intent.phase != want.?) return error.PenPhaseMismatch;
        if (!intent.valid()) return error.PenIntentInvalid;
        try journal.pushPointerV2(intent);
        received += 1;
    }
    if (received != expected.len) return error.PenTranslationIncomplete;
    if (journal.queue.length != 4) return error.PenQueueMismatch;
    // The journal preserves the tip lifecycle: hover, press, drag, release.
    const phases = [_]input_policy.PointerPhaseV2{ .motion, .press, .drag, .release };
    for (phases) |phase| {
        const sent = (try journal.take()) orelse return error.PenQueueMismatch;
        if (sent.event.pointer_v2.phase != phase) return error.PenOrderMismatch;
        if (!journal.acknowledge(sent.sequence)) return error.UnexpectedAckFailure;
    }

    std.debug.print(
        "sdl3-pen-tap-smoke: {{\"kind\":\"sdl3-pen-tap-smoke\",\"capability\":\"input.pen_bounded_v1\",\"order\":[\"motion\",\"press\",\"drag\",\"release\"],\"eraser_rejected\":true,\"result\":\"pass\"}}\n",
        .{},
    );
}

fn runScrollbarSmoke(gpa: std.mem.Allocator) !void {
    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow(
        "Emacs Proto-UI Scrollbar",
        80,
        60,
        SDL_WINDOW_HIDDEN,
    ) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);

    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    {
        var payload: [8]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], 7, .little);
        std.mem.writeInt(u32, payload[4..8], 1, .little);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.frame_create,
            1,
            capability.session_id,
            7,
            &payload,
        );
    }
    {
        const header: protocol.FrameUpdateHeader = .{
            .frame_id = 7,
            .frame_generation = 1,
            .sequence = 2,
            .redisplay_generation = 1,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = 80,
            .logical_height = 60,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = 80,
            .physical_height = 60,
            .scale = 1,
            .dpi_x = 96,
            .dpi_y = 96,
            .damage_mode = 2,
            .update_cause = 1,
            .coalesced_count = 0,
            .timestamp_ns = 2,
        };
        var windows: std.ArrayList(u8) = .empty;
        defer windows.deinit(gpa);
        try frontend.encodeWindow(gpa, .{
            .id = 100,
            .frame_id = 7,
            .x = 0,
            .y = 0,
            .width = 80,
            .height = 60,
        }, &windows);
        var damage: std.ArrayList(u8) = .empty;
        defer damage.deinit(gpa);
        try frontend.encodeRect(gpa, .{ .x = 0, .y = 0, .width = 80, .height = 60 }, &damage);
        const sections = [_]protocol.Section{
            .{ .kind = protocol.SectionKind.windows, .records = windows.items },
            .{ .kind = protocol.SectionKind.damage, .records = damage.items },
        };
        var frame_payload: std.ArrayList(u8) = .empty;
        defer frame_payload.deinit(gpa);
        try protocol.encodeFrameUpdate(gpa, .{ .header = header, .sections = &sections }, &frame_payload);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.frame_update,
            2,
            capability.session_id,
            7,
            frame_payload.items,
        );
    }
    var scroll_payload: std.ArrayList(u8) = .empty;
    defer scroll_payload.deinit(gpa);
    try frontend.encodeWindowScrollState(gpa, .{
        .flags = frontend.WindowScrollFlags.vertical_visible,
        .window_id = 100,
        .frame_generation = 1,
        .content_size = 2000,
        .viewport_size = 400,
        .position = 100,
        .track_width = 12,
    }, &scroll_payload);
    try applyRuntimeSceneMessage(
        gpa,
        &scene,
        protocol.Message.scrollbar_state,
        3,
        capability.session_id,
        7,
        scroll_payload.items,
    );

    const layout = frontend.scrollbarLayout(&scene, 100) orelse return error.ScrollbarNoLayout;
    // 60-pixel track, 400/2000 thumb, position 100 of 1600 scrollable.
    if (@abs(layout.thumb_y - 3) > 0.001 or @abs(layout.thumb_height - 12) > 0.001)
        return error.ScrollbarThumbGeometryMismatch;

    var delivery: input_policy.DeliveryJournal = .{};
    delivery.scroll_request_negotiated = true;
    var drag: input_policy.ScrollbarDragTracker = .{};
    const track_x: i32 = 74;
    const thumb_y: i32 = 9;
    const trough_below_y: i32 = 40;
    const trough_above_y: i32 = 1;

    // A press on the thumb opens a session and the matching release ends it.
    if (!try handleScrollbarPointer(&delivery, &scene, &drag, window, true, track_x, thumb_y))
        return error.ScrollbarThumbPressNotConsumed;
    if (!drag.active) return error.ScrollbarDragNotActive;
    if (!try handleScrollbarPointer(&delivery, &scene, &drag, window, false, track_x, thumb_y))
        return error.ScrollbarThumbReleaseNotConsumed;
    if (drag.active) return error.ScrollbarDragNotEnded;
    if (delivery.queue.length != 0) return error.ScrollbarIdlePressEmitted;
    // A release without an active session falls through to the pointer path.
    if (try handleScrollbarPointer(&delivery, &scene, &drag, window, false, track_x, thumb_y))
        return error.ScrollbarStrayReleaseConsumed;

    // Dragging the thumb reports relative deltas and stops with the session.
    if (!try handleScrollbarPointer(&delivery, &scene, &drag, window, true, track_x, thumb_y))
        return error.ScrollbarThumbPressNotConsumed;
    const dragged = (try drag.drag(track_x, thumb_y + 11, 1)) orelse
        return error.ScrollbarDragNoRequest;
    if (dragged.kind != .relative or dragged.axis != .vertical or
        dragged.delta != 11 or dragged.window_id != 100 or dragged.frame_generation != 1)
        return error.ScrollbarDragRequestMismatch;
    drag.release(1);

    // Trough presses page by exactly one viewport in the matching direction.
    if (!try handleScrollbarPointer(
        &delivery,
        &scene,
        &drag,
        window,
        true,
        track_x,
        trough_below_y,
    )) return error.ScrollbarTroughPressNotConsumed;
    if (!try handleScrollbarPointer(
        &delivery,
        &scene,
        &drag,
        window,
        true,
        track_x,
        trough_above_y,
    )) return error.ScrollbarTroughPressNotConsumed;
    // A press outside the track falls through to the ordinary pointer path.
    if (try handleScrollbarPointer(&delivery, &scene, &drag, window, true, 10, 10))
        return error.ScrollbarOutsideConsumed;

    var page_delta: [2]i32 = .{ 0, 0 };
    var page_index: usize = 0;
    while (delivery.queue.pop()) |event| switch (event) {
        .scroll => |request| {
            if (page_index >= page_delta.len) return error.ScrollbarTooManyRequests;
            if (request.kind != .relative or request.axis != .vertical or
                request.window_id != 100 or request.frame_generation != 1 or
                request.position != 0)
                return error.ScrollbarPageRequestMismatch;
            page_delta[page_index] = request.delta;
            page_index += 1;
        },
        else => return error.ScrollbarUnexpectedEvent,
    };
    if (page_index != page_delta.len) return error.ScrollbarPageRequestMissing;
    if (page_delta[0] != 400 or page_delta[1] != -400)
        return error.ScrollbarPageDeltaMismatch;

    // The horizontal bar of the same window is an independent state with
    // mirrored geometry and horizontal intents from the same shared layout.
    var horizontal_payload: std.ArrayList(u8) = .empty;
    defer horizontal_payload.deinit(gpa);
    try frontend.encodeWindowScrollState(gpa, .{
        .flags = frontend.WindowScrollFlags.horizontal_visible,
        .window_id = 100,
        .frame_generation = 1,
        .content_size = 200,
        .viewport_size = 40,
        .position = 60,
        .track_width = 8,
    }, &horizontal_payload);
    try applyRuntimeSceneMessage(
        gpa,
        &scene,
        protocol.Message.scrollbar_state,
        4,
        capability.session_id,
        7,
        horizontal_payload.items,
    );
    if (scene.scroll_states.items.len != 2) return error.ScrollbarStateReplaced;
    const horizontal = frontend.horizontalScrollbarLayout(&scene, 100) orelse
        return error.ScrollbarNoLayout;
    // Owner is 80x60 with a 12-wide vertical bar, so the horizontal track is 68
    // wide along the bottom with a 40/200 thumb at position 60 of 160
    // scrollable, and its corner stops where the vertical bar starts.
    if (@abs(horizontal.track_y - 52) > 0.001 or
        @abs(horizontal.track_height - 8) > 0.001 or
        @abs(horizontal.track_width - 68) > 0.001 or
        @abs(horizontal.thumb_width - 13.6) > 0.001 or
        @abs(horizontal.thumb_x - 20.4) > 0.001)
        return error.ScrollbarThumbGeometryMismatch;
    if (frontend.scrollbarLayout(&scene, 100) == null)
        return error.ScrollbarVerticalStateLost;

    const horizontal_hit = frontend.hitTestHorizontalScrollbar(&scene, 27, 56) orelse
        return error.ScrollbarNoLayout;
    if (horizontal_hit.part != .thumb) return error.ScrollbarHitMismatch;
    if (!try handleScrollbarPointer(&delivery, &scene, &drag, window, true, 27, 56))
        return error.ScrollbarThumbPressNotConsumed;
    if (!drag.active) return error.ScrollbarDragNotActive;
    const horizontal_drag = (try drag.drag(47, 56, 1)) orelse
        return error.ScrollbarDragNoRequest;
    if (horizontal_drag.axis != .horizontal or horizontal_drag.delta != 20 or
        horizontal_drag.window_id != 100)
        return error.ScrollbarDragRequestMismatch;
    drag.release(1);
    // A press right of the thumb (and left of the vertical bar's column) pages
    // one viewport to the right.
    if (!try handleScrollbarPointer(&delivery, &scene, &drag, window, true, 50, 56))
        return error.ScrollbarTroughPressNotConsumed;
    var horizontal_page: ?i32 = null;
    while (delivery.queue.pop()) |event| switch (event) {
        .scroll => |request| {
            if (horizontal_page != null or request.kind != .relative or
                request.axis != .horizontal or request.delta != 40 or
                request.window_id != 100)
                return error.ScrollbarPageRequestMismatch;
            horizontal_page = request.delta;
        },
        else => return error.ScrollbarUnexpectedEvent,
    };
    if (horizontal_page == null) return error.ScrollbarPageRequestMissing;

    var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
    defer draw_list.deinit();
    try buildSceneDrawList(&scene, &draw_list, 80, 60);
    var horizontal_thumb_drawn = false;
    for (draw_list.commands.items) |command| switch (command) {
        .fill => |fill| {
            if (@abs(fill.rect.x - horizontal.thumb_x) <= 0.001 and
                @abs(fill.rect.y - horizontal.track_y) <= 0.001 and
                @abs(fill.rect.width - horizontal.thumb_width) <= 0.001 and
                @abs(fill.rect.height - horizontal.track_height) <= 0.001 and
                fill.color.r == 0x71 and fill.color.g == 0xa6 and fill.color.b == 0xf2)
                horizontal_thumb_drawn = true;
        },
        else => {},
    };
    if (!horizontal_thumb_drawn) return error.ScrollbarThumbNotDrawn;

    std.debug.print(
        "sdl3-scrollbar-smoke: {{\"kind\":\"sdl3-scrollbar-smoke\",\"capability\":\"window.scroll_request_v1\",\"thumb_height\":{d},\"drag_delta\":{d},\"page_delta\":[{d},{d}],\"thumb_release_ends_session\":true,\"outside_fallthrough\":true,\"horizontal_thumb_width\":{d},\"horizontal_drag_delta\":{d},\"horizontal_page_delta\":{d},\"result\":\"pass\"}}\n",
        .{
            @as(i32, @intFromFloat(layout.thumb_height)),
            dragged.delta,
            page_delta[0],
            page_delta[1],
            @as(i32, @intFromFloat(horizontal.thumb_width)),
            horizontal_drag.delta,
            horizontal_page.?,
        },
    );
}

fn runDialogHitSmoke(gpa: std.mem.Allocator) !void {
    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow(
        "Emacs Proto-UI Dialog Hit",
        80,
        60,
        SDL_WINDOW_HIDDEN,
    ) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);

    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    {
        var payload: [8]u8 = undefined;
        std.mem.writeInt(u32, payload[0..4], 7, .little);
        std.mem.writeInt(u32, payload[4..8], 1, .little);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.frame_create,
            1,
            capability.session_id,
            7,
            &payload,
        );
    }
    {
        const header: protocol.FrameUpdateHeader = .{
            .frame_id = 7,
            .frame_generation = 1,
            .sequence = 2,
            .redisplay_generation = 1,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = 80,
            .logical_height = 60,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = 80,
            .physical_height = 60,
            .scale = 1,
            .dpi_x = 96,
            .dpi_y = 96,
            .damage_mode = 2,
            .update_cause = 1,
            .coalesced_count = 0,
            .timestamp_ns = 2,
        };
        var windows: std.ArrayList(u8) = .empty;
        defer windows.deinit(gpa);
        try frontend.encodeWindow(gpa, .{
            .id = 100,
            .frame_id = 7,
            .x = 0,
            .y = 0,
            .width = 80,
            .height = 60,
        }, &windows);
        var damage: std.ArrayList(u8) = .empty;
        defer damage.deinit(gpa);
        try frontend.encodeRect(gpa, .{ .x = 0, .y = 0, .width = 80, .height = 60 }, &damage);
        const sections = [_]protocol.Section{
            .{ .kind = protocol.SectionKind.windows, .records = windows.items },
            .{ .kind = protocol.SectionKind.damage, .records = damage.items },
        };
        var frame_payload: std.ArrayList(u8) = .empty;
        defer frame_payload.deinit(gpa);
        try protocol.encodeFrameUpdate(gpa, .{ .header = header, .sections = &sections }, &frame_payload);
        try applyRuntimeSceneMessage(
            gpa,
            &scene,
            protocol.Message.frame_update,
            2,
            capability.session_id,
            7,
            frame_payload.items,
        );
    }
    var dialog: protocol.DialogState = .{
        .kind = .prompt,
        .dialog_id = 80,
        .dialog_generation = 1,
        .window_id = 100,
        .frame_generation = 1,
        .x = 8,
        .y = 8,
        .width = 64,
        .height = 52,
        .title_len = 7,
        .text_len = 9,
        .buttons = protocol.DialogButtons.ok | protocol.DialogButtons.cancel,
    };
    @memcpy(dialog.title[0..7], "Save as");
    @memcpy(dialog.text[0..9], "File name");
    var dialog_payload: std.ArrayList(u8) = .empty;
    defer dialog_payload.deinit(gpa);
    try protocol.encodeDialogState(gpa, dialog, &dialog_payload);
    try applyRuntimeSceneMessage(
        gpa,
        &scene,
        protocol.Message.dialog_open,
        3,
        capability.session_id,
        7,
        dialog_payload.items,
    );
    const layout = frontend.dialogLayout(&scene) orelse return error.DialogHitNoLayout;
    if (layout.button_count != 2) return error.DialogHitUnexpectedButtons;

    // A prompt dialog exposes a bounded text field; input and backspace go to
    // the field instead of Emacs, and the accepted text rides the result tail.
    const field = frontend.dialogFieldRect(&scene) orelse return error.DialogHitNoField;
    if (field.x != layout.x + 4 or field.y != layout.y + frontend.dialog_field_y_offset or
        field.width != layout.width - 8)
        return error.DialogHitFieldGeometryMismatch;
    var typed = textEvent("abX");
    typed.text.window_id = SDL_GetWindowID(window);
    var dialog_result_only: capability.Set = .{};
    dialog_result_only.bits[@intFromEnum(capability.Feature.widget_dialog_result_v1)] = true;
    if (!handleDialogFieldInput(&scene, dialog_result_only, typed))
        return error.DialogFieldTextNotConsumed;
    if (!std.mem.eql(u8, frontend.dialogInput(&scene), "abX"))
        return error.DialogFieldTextMismatch;
    // Control bytes and non-ASCII stay out of the ASCII field.
    var rejected = textEvent("a\x01\xc3\xa9");
    rejected.text.window_id = SDL_GetWindowID(window);
    _ = handleDialogFieldInput(&scene, dialog_result_only, rejected);
    if (!std.mem.eql(u8, frontend.dialogInput(&scene), "abXa"))
        return error.DialogFieldRejectionMismatch;
    {
        var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
        defer draw_list.deinit();
        try buildSceneDrawList(&scene, &draw_list, 80, 60);
        var field_box_rendered = false;
        var field_text_rendered = false;
        for (draw_list.commands.items) |command| {
            switch (command) {
                .fill => |fill| {
                    if (fill.rect.x == field.x and fill.rect.y == field.y and
                        fill.rect.width == field.width and fill.rect.height == field.height)
                        field_box_rendered = true;
                },
                .unicode_text => |text| {
                    if (text.x == field.x + 2 and std.mem.eql(u8, text.bytes, "abXa"))
                        field_text_rendered = true;
                },
                else => {},
            }
        }
        if (!field_box_rendered or !field_text_rendered)
            return error.DialogFieldNotRendered;
    }
    // The field is bounded: capacity stops further input instead of overflowing.
    var overflow: [200]u8 = @splat('x');
    _ = frontend.dialogAppendInput(&scene, &overflow);
    if (scene.dialog_text_len != frontend.max_dialog_input)
        return error.DialogFieldNotBounded;
    while (frontend.dialogBackspace(&scene)) {}
    _ = frontend.dialogAppendInput(&scene, "abX");
    if (!std.mem.eql(u8, frontend.dialogInput(&scene), "abX"))
        return error.DialogFieldBackspaceMismatch;

    var delivery: input_policy.DeliveryJournal = .{};
    delivery.dialog_result_negotiated = true;
    var cancel_slot: ?frontend.DialogButtonSlot = null;
    for (layout.buttons[0..layout.button_count]) |slot| {
        if (slot.button == .cancel) cancel_slot = slot;
    }
    const cancel_button = cancel_slot orelse return error.DialogHitNoCancelButton;
    const click_x: i32 = @intFromFloat(cancel_button.x + cancel_button.width / 2);
    const click_y: i32 = @intFromFloat(cancel_button.y + cancel_button.height / 2);

    // A press on a standard button reports its result; the release is consumed.
    if (!try handleDialogPointer(&delivery, &scene, window, true, click_x, click_y))
        return error.DialogHitPressNotConsumed;
    if (!try handleDialogPointer(&delivery, &scene, window, false, click_x, click_y))
        return error.DialogHitReleaseNotConsumed;
    // A click on the box body is consumed without a result, and a click outside
    // the box falls through to the ordinary pointer path.
    if (!try handleDialogPointer(&delivery, &scene, window, true, 20, 10))
        return error.DialogHitBodyNotConsumed;
    if (try handleDialogPointer(&delivery, &scene, window, true, 200, 200))
        return error.DialogHitOutsideConsumed;

    var result_button: ?protocol.DialogResultButton = null;
    while (delivery.queue.pop()) |event| switch (event) {
        .dialog_result => |result| {
            if (result.dialog_id != 80 or result.window_id != 100 or result.frame_generation != 1)
                return error.DialogHitWrongIdentity;
            if (result.text_len != 3 or !std.mem.eql(u8, result.text[0..3], "abX"))
                return error.DialogHitUnexpectedText;
            if (result_button != null) return error.DialogHitDuplicateResult;
            result_button = result.button;
        },
        else => return error.DialogHitUnexpectedEvent,
    };
    if (result_button != .cancel) return error.DialogHitWrongButton;

    // Escape reports the keyboard dismissal for a policy that offers cancel.
    const escape_key: SDL_KeyboardEvent = .{
        .type = SDL_EVENT_KEY_DOWN,
        .reserved = 0,
        .timestamp = 0,
        .window_id = 0,
        .which = 0,
        .scancode = input_policy.SDL_SCANCODE_ESCAPE,
        .key = 0,
        .modifiers = 0,
        .raw = 0,
        .down = true,
        .repeat = false,
    };
    if (!try consumeDialogEscape(&delivery, &scene, escape_key))
        return error.DialogEscapeNotConsumed;
    var escape_button: ?protocol.DialogResultButton = null;
    while (delivery.queue.pop()) |event| switch (event) {
        .dialog_result => |result| {
            if (escape_button != null) return error.DialogEscapeUnexpectedEvent;
            if (result.text_len != 3 or !std.mem.eql(u8, result.text[0..3], "abX"))
                return error.DialogEscapeUnexpectedText;
            escape_button = result.button;
        },
        else => return error.DialogEscapeUnexpectedEvent,
    };
    if (escape_button != .cancel) return error.DialogEscapeWrongButton;

    std.debug.print(
        "sdl3-dialog-hit-smoke: {{\"kind\":\"sdl3-dialog-hit-smoke\",\"capability\":\"widget.dialog_result_v1\",\"buttons\":{d},\"clicked\":\"cancel\",\"body_consumed\":true,\"outside_fallthrough\":true,\"escape\":\"cancel\",\"prompt_field\":true,\"prompt_text\":\"abX\",\"field_bounded\":true,\"result\":\"pass\"}}\n",
        .{layout.button_count},
    );
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
        .monitor => {},
        .dpi => {},
        .theme => {},
        .window => {},
        // Reverse scroll intents are EPXL-only and require negotiated capability.
        .scroll => {},
        .scrollbar_event => {},
        // Menu intents are EPXL-only and require negotiated capability.
        .menu_result => {},
        .menu_cancel => {},
        .menu_hover => {},
        .menu_open_request => {},
        .toolbar_click => {},
        // Dialog results are EPXL-only and require negotiated capability.
        .dialog_result => {},
        // Drag-and-drop reports are EPXL-only and require negotiated capability.
        .dnd_enter => {},
        .dnd_drop => {},
        .dnd_position => {},
        .dnd_data => {},
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

    var child_environment = try buildDisplayEnvironment(gpa);
    defer child_environment.deinit();
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_MODULE_PATH"), config.module_path);
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_FACTS_PATH"), facts_path);
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_INPUT_PATH"), input_path);
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_CLIPBOARD_PATH"), clipboard_path);
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_CLIPBOARD_UNICODE"), "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_POINTER_SELECTION"), "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_POINTER_MIDDLE_PASTE"), "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_LOCAL_COMPAT"), "1");

    var child = try std.process.spawn(io, .{
        .argv = &.{ config.emacs_path, "--batch", "--load", "tools/proto-ui-sdl3/facts_publisher.el" },
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
                SDL_EVENT_RENDER_TARGETS_RESET,
                SDL_EVENT_RENDER_DEVICE_RESET,
                SDL_EVENT_RENDER_DEVICE_LOST,
                => {
                    unicode_text_renderer.clearTextures();
                    frame_gate.dirty = true;
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
            _ = try presentScene(scene, &draw_list, renderer, window, &frame_gate, &frame_counters, null);
        } else {
            try presentFacts(latest, &draw_list, renderer, window, &frame_gate, &frame_counters, null);
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

const FrameTextureCacheEntry = struct {
    texture: *SDL_Texture,
    source_width: u32,
    source_height: u32,
};

const FrameTextureCache = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(*const anyopaque, FrameTextureCacheEntry),

    fn init(allocator: std.mem.Allocator) FrameTextureCache {
        return .{ .allocator = allocator, .entries = std.AutoHashMap(*const anyopaque, FrameTextureCacheEntry).init(allocator) };
    }

    fn deinit(self: *FrameTextureCache) void {
        var iterator = self.entries.valueIterator();
        while (iterator.next()) |entry| SDL_DestroyTexture(entry.texture);
        self.entries.deinit();
    }

    fn getOrCreate(
        self: *FrameTextureCache,
        renderer: *SDL_Renderer,
        pixels: []const u8,
        width: u32,
        height: u32,
    ) !*SDL_Texture {
        const key: *const anyopaque = @ptrCast(pixels.ptr);
        if (self.entries.get(key)) |entry| {
            if (entry.source_width == width and entry.source_height == height) return entry.texture;
            return error.TextureCacheKeyCollision;
        }
        const texture = SDL_CreateTexture(
            renderer,
            SDL_PIXELFORMAT_RGBA8888,
            SDL_TEXTUREACCESS_STATIC,
            @intCast(width),
            @intCast(height),
        ) orelse return sdlFail("SDL_CreateTexture");
        errdefer SDL_DestroyTexture(texture);
        if (!SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_NEAREST)) return sdlFail("SDL_SetTextureScaleMode");
        if (!SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND)) return sdlFail("SDL_SetTextureBlendMode");
        if (!SDL_UpdateTexture(texture, null, pixels.ptr, @intCast(width * 4))) return sdlFail("SDL_UpdateTexture");
        try self.entries.put(key, .{ .texture = texture, .source_width = width, .source_height = height });
        return texture;
    }
};

const AtlasTextureKey = struct {
    atlas_id: u32,
    page_index: u16,
    generation: u32,
    revision: u32,

    fn eql(self: AtlasTextureKey, other: AtlasTextureKey) bool {
        return self.atlas_id == other.atlas_id and
            self.page_index == other.page_index and
            self.generation == other.generation and
            self.revision == other.revision;
    }

    fn hash(self: AtlasTextureKey) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&self.atlas_id));
        hasher.update(std.mem.asBytes(&self.page_index));
        hasher.update(std.mem.asBytes(&self.generation));
        hasher.update(std.mem.asBytes(&self.revision));
        return hasher.final();
    }
};

const AtlasTextureCacheEntry = struct {
    texture: *SDL_Texture,
    key: AtlasTextureKey,
    revision: u32,
    source_width: u32,
    source_height: u32,
};

const AtlasTextureCache = struct {
    allocator: std.mem.Allocator,
    entries: std.AutoHashMap(AtlasTextureKey, AtlasTextureCacheEntry),
    uploads: u64 = 0,
    hits: u64 = 0,

    fn init(allocator: std.mem.Allocator) AtlasTextureCache {
        return .{ .allocator = allocator, .entries = std.AutoHashMap(AtlasTextureKey, AtlasTextureCacheEntry).init(allocator) };
    }

    fn deinit(self: *AtlasTextureCache) void {
        self.clear();
        self.entries.deinit();
    }

    fn clear(self: *AtlasTextureCache) void {
        var iterator = self.entries.valueIterator();
        while (iterator.next()) |entry| SDL_DestroyTexture(entry.texture);
        self.entries.clearRetainingCapacity();
    }

    fn getOrCreate(
        self: *AtlasTextureCache,
        renderer: *SDL_Renderer,
        key: AtlasTextureKey,
        pixels: []const u8,
        width: u32,
        height: u32,
    ) !*SDL_Texture {
        if (self.entries.get(key)) |entry| {
            if (entry.revision == key.revision and
                entry.source_width == width and entry.source_height == height)
            {
                self.hits += 1;
                return entry.texture;
            }
            _ = self.entries.remove(key);
            SDL_DestroyTexture(entry.texture);
        }
        const texture = SDL_CreateTexture(
            renderer,
            SDL_PIXELFORMAT_RGBA8888,
            SDL_TEXTUREACCESS_STATIC,
            @intCast(width),
            @intCast(height),
        ) orelse return sdlFail("SDL_CreateTexture");
        errdefer SDL_DestroyTexture(texture);
        if (!SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_NEAREST)) return sdlFail("SDL_SetTextureScaleMode");
        if (!SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND)) return sdlFail("SDL_SetTextureBlendMode");
        if (!SDL_UpdateTexture(texture, null, pixels.ptr, @intCast(width * 4))) return sdlFail("SDL_UpdateTexture");
        try self.entries.put(key, .{
            .texture = texture,
            .key = key,
            .revision = key.revision,
            .source_width = width,
            .source_height = height,
        });
        self.uploads += 1;
        return texture;
    }
};

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
    unicode_text_renderer.clearTextures();
    SDL_DestroyRenderer(selected.handle);
}

fn finishPublisherResync(
    gpa: std.mem.Allocator,
    snapshot: facts.Snapshot,
    scene: *frontend.Scene,
    io: std.Io,
    reader: anytype,
    writer: anytype,
    input_path: []const u8,
    input_sequence: *u64,
    capabilities: capability.Set,
) !void {
    scene.resetForResync();
    scene.next_sequence = 5; // capability exchange reserved session sequences 1..4
    const wire_writer = @constCast(&writer.interface);
    try live.writeControl(wire_writer, .{ .kind = .resync_begin, .sequence = 1 });
    try wire_writer.flush();
    var acks = live.AckTracker.init(1);
    try sendSnapshotMessages(gpa, snapshot, snapshot.text.lines, snapshot.cursor, snapshot.viewport, scene, &acks, io, reader, writer, input_path, input_sequence, capabilities, false);
    try live.writeControl(wire_writer, .{ .kind = .resync_complete, .sequence = scene.next_sequence.? - 1 });
    try wire_writer.flush();
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
    keymap_loop_allowed: bool,
) !capability.Negotiated {
    var backend = capability.backendSupported();
    if (!keymap_loop_allowed)
        backend.bits[@intFromEnum(capability.Feature.input_keymap_loop_v1)] = false;
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
    const negotiated = try negotiatePublisherSide(
        gpa,
        &reader.interface,
        &writer.interface,
        config.graphic_frame_publisher,
    );

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
        if (envelope.message_type == protocol.Message.frame_update) {
            // The live fixture now provides deterministic reverse-direction
            // wire evidence: the frontend emits a dedicated scrollbar event
            // before acknowledging the frame that triggered delivery.
            const reverse_message = (try live.readFrame(&reader.interface, gpa)) orelse
                return error.ExpectedScrollbarEvent;
            defer gpa.free(reverse_message);
            const reverse = try protocol.decodeEnvelope(reverse_message);
            if (reverse.envelope.message_type != protocol.Message.scrollbar_event or
                reverse.envelope.flags & protocol.Flags.requires_ack == 0 or
                reverse.envelope.ack_sequence != 0 or
                reverse.envelope.session_id != capability.session_id)
                return error.ExpectedScrollbarEvent;
            const request = try protocol.decodeScrollRequest(reverse.bytes);
            if (request.kind != .absolute or request.axis != .vertical or
                request.window_id != 10 or request.position != 40)
                return error.InvalidScrollbarEvent;
            try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = reverse.envelope.sequence });
            try writer.interface.flush();
        }
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
    var child_environment = try buildDisplayEnvironment(gpa);
    defer child_environment.deinit();
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_MODULE_PATH"), config.module_path);
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_FACTS_PATH"), config.facts_path);
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_INPUT_PATH"), input_path);
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_CLIPBOARD_PATH"), clipboard_path);
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_CLIPBOARD_UNICODE"), if (config.clipboard_unicode_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_POINTER_SELECTION"), if (config.pointer_selection_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_POINTER_GENERIC"), if (config.pointer_generic_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_POINTER_MIDDLE_PASTE"), if (config.pointer_middle_paste_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_VISIBLE_EDIT"), if (config.visible_edit_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_DND_TEXT"), if (config.dnd_text_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_FACE_SMOKE"), if (config.face_smoke_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_CURSOR_SMOKE"), if (config.cursor_smoke_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_SCROLLBAR_SMOKE"), if (config.scrollbar_smoke_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_HSCROLL_SMOKE"), if (config.hscroll_smoke_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_REGION_SMOKE"), if (config.region_smoke_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_RUNS_SMOKE"), if (config.runs_smoke_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_HEADER_SMOKE"), if (config.header_smoke_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_MOUSE_SMOKE"), if (config.mouse_smoke_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_ECHO_SMOKE"), if (config.echo_smoke_publisher) "1" else "0");
    try child_environment.put(try gpa.dupe(u8, "PROTO_UI_TITLE_SMOKE"), if (config.title_smoke) "1" else "0");
    try child_environment.put(
        try gpa.dupe(u8, "PROTO_UI_MENU_ICON_TEST"),
        if (config.menu_icon_publisher) "1" else "0",
    );

    // A display-backed frame is what makes the real mode line, fringes, and
    // scroll bars observable, so the graphic publisher starts Emacs without
    // --batch and lets it open its own PGTK/X frame from the inherited DISPLAY.
    const publisher_argv: []const []const u8 = if (config.graphic_frame_publisher)
        &.{ config.emacs_path, "-Q", "--load", "tools/proto-ui-sdl3/facts_publisher.el" }
    else
        // -Q keeps the probe independent of the user's init file now that the
        // publisher child inherits HOME with the display environment.
        &.{ config.emacs_path, "-Q", "--batch", "--load", "tools/proto-ui-sdl3/facts_publisher.el" };
    var emacs_child = try std.process.spawn(io, .{
        .argv = publisher_argv,
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
    var gap_fault_pending = config.gap_fault;
    const publish_forever = config.auto_quit_ms == 0 and config.interactive_publisher;
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
        const negotiated = try negotiatePublisherSide(
            gpa,
            &reader.interface,
            &writer.interface,
            config.graphic_frame_publisher,
        );

        const request = try readControlExact(&reader);
        if (request.kind != .resync_request or request.sequence != 1)
            return error.InvalidResyncRequest;
        scene.resetForResync();
        scene.next_sequence = 5; // capability exchange reserved session sequences 1..4
        try live.writeControl(&writer.interface, .{ .kind = .resync_begin, .sequence = 1 });
        try writer.interface.flush();

        var initial_snapshot: ?facts.Snapshot = null;
        var facts_wait_ms: u32 = 0;
        while (initial_snapshot == null and facts_wait_ms < 30000) : (facts_wait_ms += 20) {
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
        try sendSnapshotMessages(gpa, published.?, published.?.text.lines, published.?.cursor, published.?.viewport, &scene, &acks, io, &reader, &writer, input_path, &input_sequence, negotiated.effective, false);
        if (published.?.title) |title| {
            var title_messages: std.ArrayList([]const u8) = .empty;
            defer {
                for (title_messages.items) |message| gpa.free(message);
                title_messages.deinit(gpa);
            }
            try facts.appendTitleMessages(gpa, &scene, title, &title_messages);
            for (title_messages.items) |message| {
                const envelope = (try protocol.decodeEnvelope(message)).envelope;
                try acks.markSent(envelope.sequence);
                try live.writeFrame(&writer.interface, message);
                try writer.interface.flush();
                try awaitFrameAck(gpa, io, &reader, &writer, envelope.sequence, input_path, &input_sequence, envelope.session_id, envelope.frame_id, negotiated.effective);
                try acks.ack(envelope.sequence);
            }
        }
        if (config.selection_owner_smoke and
            negotiated.effective.contains(.selection_primary_ownership_v1))
        {
            const offers = [_]protocol.SelectionOffer{
                .{ .target = "UTF8_STRING", .priority = 2 },
                .{ .target = "STRING", .priority = 1 },
            };
            const sequence = scene.next_sequence.?;
            var owner_payload: std.ArrayList(u8) = .empty;
            defer owner_payload.deinit(gpa);
            try protocol.encodeSelectionOwnerSet(gpa, .{
                .kind = .primary,
                .generation = 1,
                .flags = protocol.SelectionOwnerFlags.export_to_platform |
                    protocol.SelectionOwnerFlags.notify_on_loss,
                .offers = offers[0..],
            }, &owner_payload);
            var owner_message: std.ArrayList(u8) = .empty;
            defer owner_message.deinit(gpa);
            try protocol.encodeEnvelope(gpa, .{
                .flags = 0,
                .message_type = protocol.Message.selection_owner_set,
                .sequence = sequence,
                .ack_sequence = 0,
                .session_id = capability.session_id,
                .frame_id = 1,
                .timestamp_ns = sequence,
            }, owner_payload.items, &owner_message);
            try scene.apply(owner_message.items);

            const lost_sequence = sequence + 1;
            var lost_payload: std.ArrayList(u8) = .empty;
            defer lost_payload.deinit(gpa);
            try protocol.encodeSelectionLost(gpa, .{
                .kind = .primary,
                .reason = .owner_cancelled,
                .generation = 1,
            }, &lost_payload);
            var lost_message: std.ArrayList(u8) = .empty;
            defer lost_message.deinit(gpa);
            try protocol.encodeEnvelope(gpa, .{
                .flags = 0,
                .message_type = protocol.Message.selection_lost,
                .sequence = lost_sequence,
                .ack_sequence = 0,
                .session_id = capability.session_id,
                .frame_id = 1,
                .timestamp_ns = lost_sequence,
            }, lost_payload.items, &lost_message);
            try scene.apply(lost_message.items);

            const replacement_sequence = sequence + 2;
            var replacement_payload: std.ArrayList(u8) = .empty;
            defer replacement_payload.deinit(gpa);
            try protocol.encodeSelectionOwnerSet(gpa, .{
                .kind = .primary,
                .generation = 2,
                .flags = protocol.SelectionOwnerFlags.export_to_platform,
                .offers = offers[0..],
            }, &replacement_payload);
            var replacement_message: std.ArrayList(u8) = .empty;
            defer replacement_message.deinit(gpa);
            try protocol.encodeEnvelope(gpa, .{
                .flags = 0,
                .message_type = protocol.Message.selection_owner_set,
                .sequence = replacement_sequence,
                .ack_sequence = 0,
                .session_id = capability.session_id,
                .frame_id = 1,
                .timestamp_ns = replacement_sequence,
            }, replacement_payload.items, &replacement_message);
            try scene.apply(replacement_message.items);

            const clear_sequence = sequence + 3;
            var clear_payload: std.ArrayList(u8) = .empty;
            defer clear_payload.deinit(gpa);
            try protocol.encodeSelectionClear(gpa, .{
                .generation = 2,
                .kind = .primary,
            }, &clear_payload);
            var clear_message: std.ArrayList(u8) = .empty;
            defer clear_message.deinit(gpa);
            try protocol.encodeEnvelope(gpa, .{
                .flags = 0,
                .message_type = protocol.Message.selection_owner_clear,
                .sequence = clear_sequence,
                .ack_sequence = 0,
                .session_id = capability.session_id,
                .frame_id = 1,
                .timestamp_ns = clear_sequence,
            }, clear_payload.items, &clear_message);
            try scene.apply(clear_message.items);

            const messages = [_]std.ArrayList(u8){ owner_message, lost_message, replacement_message, clear_message };
            for (messages) |message| {
                const envelope = (try protocol.decodeEnvelope(message.items)).envelope;
                try acks.markSent(envelope.sequence);
                try live.writeFrame(&writer.interface, message.items);
                try writer.interface.flush();
                try awaitFrameAck(gpa, io, &reader, &writer, envelope.sequence, input_path, &input_sequence, envelope.session_id, envelope.frame_id, negotiated.effective);
                try acks.ack(envelope.sequence);
            }
        }
        if (config.selection_transfer_smoke and
            negotiated.effective.contains(.selection_primary_ownership_v1) and
            negotiated.effective.contains(.selection_primary_transfer_v1))
        {
            const offers = [_]protocol.SelectionOffer{
                .{ .target = "UTF8_STRING", .priority = 1 },
                .{ .target = "STRING", .priority = 2 },
            };
            const base_sequence = scene.next_sequence.?;
            var messages: [6]std.ArrayList(u8) = .{ .empty, .empty, .empty, .empty, .empty, .empty };
            defer {
                for (&messages) |*message| message.deinit(gpa);
            }

            var owner_payload: std.ArrayList(u8) = .empty;
            defer owner_payload.deinit(gpa);
            try protocol.encodeSelectionOwnerSet(gpa, .{
                .kind = .primary,
                .generation = 1,
                .flags = protocol.SelectionOwnerFlags.export_to_platform,
                .offers = offers[0..],
            }, &owner_payload);
            try protocol.encodeEnvelope(gpa, .{
                .flags = 0,
                .message_type = protocol.Message.selection_owner_set,
                .sequence = base_sequence,
                .ack_sequence = 0,
                .session_id = capability.session_id,
                .frame_id = 1,
                .timestamp_ns = base_sequence,
            }, owner_payload.items, &messages[0]);
            try scene.apply(messages[0].items);

            var request_payload: std.ArrayList(u8) = .empty;
            defer request_payload.deinit(gpa);
            try protocol.encodeSelectionRequest(gpa, .{
                .kind = .primary,
                .request_id = 9001,
                .generation = 1,
                .target = "UTF8_STRING",
            }, &request_payload);
            try protocol.encodeEnvelope(gpa, .{
                .flags = 0,
                .message_type = protocol.Message.selection_request,
                .sequence = base_sequence + 1,
                .ack_sequence = 0,
                .session_id = capability.session_id,
                .frame_id = 1,
                .timestamp_ns = base_sequence + 1,
            }, request_payload.items, &messages[1]);
            try scene.apply(messages[1].items);

            var data_payload: std.ArrayList(u8) = .empty;
            defer data_payload.deinit(gpa);
            try protocol.encodeSelectionData(gpa, .{
                .kind = .primary,
                .request_id = 9001,
                .generation = 1,
                .bytes = "Proto-UI transfer",
            }, &data_payload);
            try protocol.encodeEnvelope(gpa, .{
                .flags = 0,
                .message_type = protocol.Message.selection_data,
                .sequence = base_sequence + 2,
                .ack_sequence = 0,
                .session_id = capability.session_id,
                .frame_id = 1,
                .timestamp_ns = base_sequence + 2,
            }, data_payload.items, &messages[2]);
            try scene.apply(messages[2].items);

            var error_request_payload: std.ArrayList(u8) = .empty;
            defer error_request_payload.deinit(gpa);
            try protocol.encodeSelectionRequest(gpa, .{
                .kind = .primary,
                .request_id = 9002,
                .generation = 1,
                .target = "STRING",
            }, &error_request_payload);
            try protocol.encodeEnvelope(gpa, .{
                .flags = 0,
                .message_type = protocol.Message.selection_request,
                .sequence = base_sequence + 3,
                .ack_sequence = 0,
                .session_id = capability.session_id,
                .frame_id = 1,
                .timestamp_ns = base_sequence + 3,
            }, error_request_payload.items, &messages[3]);
            try scene.apply(messages[3].items);

            var error_payload: std.ArrayList(u8) = .empty;
            defer error_payload.deinit(gpa);
            try protocol.encodeSelectionError(gpa, .{
                .kind = .primary,
                .request_id = 9002,
                .generation = 1,
                .reason = .conversion_failed,
                .message = "conversion unavailable",
            }, &error_payload);
            try protocol.encodeEnvelope(gpa, .{
                .flags = 0,
                .message_type = protocol.Message.selection_error,
                .sequence = base_sequence + 4,
                .ack_sequence = 0,
                .session_id = capability.session_id,
                .frame_id = 1,
                .timestamp_ns = base_sequence + 4,
            }, error_payload.items, &messages[4]);
            try scene.apply(messages[4].items);

            var clear_payload: std.ArrayList(u8) = .empty;
            defer clear_payload.deinit(gpa);
            try protocol.encodeSelectionClear(gpa, .{
                .generation = 1,
                .kind = .primary,
            }, &clear_payload);
            try protocol.encodeEnvelope(gpa, .{
                .flags = 0,
                .message_type = protocol.Message.selection_owner_clear,
                .sequence = base_sequence + 5,
                .ack_sequence = 0,
                .session_id = capability.session_id,
                .frame_id = 1,
                .timestamp_ns = base_sequence + 5,
            }, clear_payload.items, &messages[5]);
            try scene.apply(messages[5].items);

            for (messages) |message| {
                const envelope = (try protocol.decodeEnvelope(message.items)).envelope;
                try acks.markSent(envelope.sequence);
                try live.writeFrame(&writer.interface, message.items);
                try writer.interface.flush();
                try awaitFrameAck(gpa, io, &reader, &writer, envelope.sequence, input_path, &input_sequence, envelope.session_id, envelope.frame_id, negotiated.effective);
                try acks.ack(envelope.sequence);
            }
        }
        const complete_sequence = scene.next_sequence.? - 1;
        try live.writeControl(&writer.interface, .{ .kind = .resync_complete, .sequence = complete_sequence });
        try writer.interface.flush();

        if (session_index + 1 < @max(1, config.resync_sessions)) continue;
        var waited_ms: u32 = 0;
        var heartbeat_ms: u32 = 0;
        // A reconnect smoke has a static Emacs snapshot, so the post-resync
        // frame is deterministic instead of relying on incidental fact churn.
        var heartbeat_due = config.resync_sessions > 1;
        while (publish_forever or waited_ms < publish_duration) {
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
                var title_messages: std.ArrayList([]const u8) = .empty;
                defer {
                    for (title_messages.items) |message| gpa.free(message);
                    title_messages.deinit(gpa);
                }
                sendSnapshotMessages(gpa, published.?, published.?.text.lines, published.?.cursor, published.?.viewport, &scene, &change_acks, io, &reader, &writer, input_path, &input_sequence, negotiated.effective, gap_fault_pending) catch |err| {
                    if (err == error.ResyncRequested) {
                        gap_fault_pending = false;
                        try finishPublisherResync(gpa, published.?, &scene, io, &reader, &writer, input_path, &input_sequence, negotiated.effective);
                    } else {
                        // The interactive client intentionally closes at its smoke
                        // deadline; stop the healthy publisher instead of failing.
                        // The close can surface on either side of the socket, so a
                        // read failure at that boundary is also a clean stop.
                        if (config.interactive_publisher and
                            (err == error.WriteFailed or err == error.ReadFailed or
                                err == error.SocketUnconnected or err == error.EndOfStream)) break;
                        return err;
                    }
                };
                if (published.?.title) |title| {
                    facts.appendTitleMessages(gpa, &scene, title, &title_messages) catch |append_err| {
                        if (append_err == error.SocketUnconnected or append_err == error.WriteFailed) break;
                        return append_err;
                    };
                    for (title_messages.items) |message| {
                        const title_envelope = (try protocol.decodeEnvelope(message)).envelope;
                        try change_acks.markSent(title_envelope.sequence);
                        live.writeFrame(&writer.interface, message) catch |write_err| {
                            if (write_err == error.SocketUnconnected or write_err == error.WriteFailed) break;
                            return write_err;
                        };
                        try writer.interface.flush();
                        awaitFrameAck(gpa, io, &reader, &writer, title_envelope.sequence, input_path, &input_sequence, title_envelope.session_id, title_envelope.frame_id, negotiated.effective) catch |read_err| {
                            if (read_err == error.ReadFailed or read_err == error.SocketUnconnected) break;
                            return read_err;
                        };
                        try change_acks.ack(title_envelope.sequence);
                    }
                }
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

fn countEpxlSessionDirs(gpa: std.mem.Allocator, io: std.Io) !usize {
    var count: usize = 0;
    var cwd = std.Io.Dir.cwd();
    var cache = cwd.openDir(io, ".zig-cache", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };
    defer cache.close(io);
    var walked = try cache.walk(gpa);
    defer walked.deinit();
    while (try walked.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        const name = std.fs.path.basename(entry.path);
        if (std.mem.startsWith(u8, name, "proto-ui-epxl-")) count += 1;
    }
    return count;
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
        .theme => |theme| blk: {
            try protocol.encodeThemeEvent(gpa, theme, &payload);
            break :blk protocol.Message.theme_event;
        },
        .monitor => |monitor| blk: {
            try protocol.encodeMonitorEvent(gpa, monitor, &payload);
            break :blk protocol.Message.monitor_event;
        },
        .dpi => |dpi| blk: {
            try protocol.encodeDpiEvent(gpa, dpi, &payload);
            break :blk protocol.Message.dpi_event;
        },
        .window => |request| blk: {
            try protocol.encodeWindowRequest(gpa, request, &payload);
            break :blk protocol.Message.window_request;
        },
        .scroll => |request| blk: {
            try protocol.encodeScrollRequest(gpa, request, &payload);
            break :blk protocol.Message.scroll_request;
        },
        .scrollbar_event => |request| blk: {
            try protocol.encodeScrollRequest(gpa, request, &payload);
            break :blk protocol.Message.scrollbar_event;
        },
        .menu_result => |result| blk: {
            try protocol.encodeMenuResult(gpa, result, &payload);
            break :blk protocol.Message.menu_result;
        },
        .menu_cancel => |cancel| blk: {
            try protocol.encodeMenuCancel(gpa, cancel, &payload);
            break :blk protocol.Message.menu_cancel;
        },
        .menu_hover => |hover| blk: {
            try protocol.encodeMenuHover(gpa, hover, &payload);
            break :blk protocol.Message.menu_hover;
        },
        .menu_open_request => |request| blk: {
            try protocol.encodeMenuOpenRequest(gpa, request, &payload);
            break :blk protocol.Message.menu_open_request;
        },
        .toolbar_click => |click| blk: {
            try protocol.encodeToolbarClick(gpa, click, &payload);
            break :blk protocol.Message.toolbar_click;
        },
        .dialog_result => |result| blk: {
            try protocol.encodeDialogResult(gpa, result, &payload);
            break :blk protocol.Message.dialog_result;
        },
        .dnd_enter => |event| blk: {
            const offers = [_]protocol.SelectionOffer{.{ .target = event.target(), .priority = 1 }};
            try protocol.encodeDndEnter(gpa, .{
                .allowed_actions = protocol.DndActionMask.copy,
                .current_action = .copy,
                .drag_id = event.drag_id,
                .x = event.x,
                .y = event.y,
                .offers = &offers,
            }, &payload);
            break :blk protocol.Message.dnd_enter;
        },
        .dnd_drop => |event| blk: {
            try protocol.encodeDndDrop(gpa, .{
                .action = .copy,
                .drag_id = event.drag_id,
                .x = event.x,
                .y = event.y,
            }, &payload);
            break :blk protocol.Message.dnd_drop;
        },
        .dnd_position => |event| blk: {
            try protocol.encodeDndPosition(gpa, .{
                .allowed_actions = protocol.DndActionMask.copy,
                .current_action = .copy,
                .drag_id = event.drag_id,
                .x = event.x,
                .y = event.y,
            }, &payload);
            break :blk protocol.Message.dnd_position;
        },
        .dnd_data => |event| blk: {
            try protocol.encodeDndData(gpa, .{
                .drag_id = event.drag_id,
                .target = event.target(),
                .bytes = event.payload(),
            }, &payload);
            break :blk protocol.Message.dnd_data;
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

fn appendEpxlBenchSamples(
    gpa: std.mem.Allocator,
    report: *std.ArrayList(u8),
    field_name: []const u8,
    samples: []const u64,
) !void {
    const summary = try renderer_policy.summarizeLatencies(samples);
    try report.print(gpa, ",\"{s}\":{{\"summary\":{{\"count\":{d},\"p50_ns\":{d},\"p95_ns\":{d},\"p99_ns\":{d},\"mean_ns\":{d:.2}}},\"samples_ns\":[", .{
        field_name,
        samples.len,
        summary.p50_ns,
        summary.p95_ns,
        summary.p99_ns,
        summary.mean_ns,
    });
    for (samples, 0..) |sample, index| {
        if (index != 0) try report.appendSlice(gpa, ",");
        try report.print(gpa, "{d}", .{sample});
    }
    try report.appendSlice(gpa, "]}");
}

fn writeEpxlRoundTripReport(
    gpa: std.mem.Allocator,
    io: std.Io,
    config: *const Config,
    intents_submitted: usize,
    input_lost: usize,
    ack_samples: []const u64,
    update_samples: []const u64,
) !void {
    if (ack_samples.len != update_samples.len or ack_samples.len == 0)
        return error.EpxlBenchmarkSampleMismatch;
    for (ack_samples) |sample| if (sample == 0) return error.InvalidEpxlLatencySample;
    for (update_samples) |sample| if (sample == 0) return error.InvalidEpxlLatencySample;

    var report: std.ArrayList(u8) = .empty;
    defer report.deinit(gpa);
    try report.appendSlice(gpa, "{\"schema_version\":1,\"kind\":\"proto-ui-sdl3-epxl-roundtrip-benchmark\",\"protocol\":{\"name\":\"EUP\",\"version\":\"1.0\"},\"transport\":\"unix_epxl\",\"measurement_kind\":\"bounded_public_facts_bridge\",\"workload\":{\"name\":\"emacs_text_edit_alternating\",\"iterations\":");
    try report.print(gpa, "{d},\"warmup_operations\":{d},\"optimization_mode\":", .{
        config.benchmark_iterations,
        config.benchmark_warmup,
    });
    try runtime.appendJsonStringPublic(gpa, &report, @tagName(@import("builtin").mode));
    try report.appendSlice(gpa, "},\"boundaries\":{\"clock\":\"SDL_GetPerformanceCounter\",\"ack\":\"before EPXL intent wire write through authenticated EPXL control ACK read completion; excludes Emacs apply and Scene apply\",\"frame_update\":\"the same intent wire-write start through receipt of the next FRAME_UPDATE bytes; excludes envelope decode, Scene apply, damage, draw, and present\",\"renderer_present\":\"excluded\"}");
    try appendEpxlBenchSamples(gpa, &report, "ack", ack_samples);
    try appendEpxlBenchSamples(gpa, &report, "update", update_samples);
    try report.print(
        gpa,
        ",\"intents_submitted\":{d},\"intents_acked\":{d},\"frame_updates_used\":{d},\"input_lost\":{d},\"operation_sequence\":[",
        .{ intents_submitted, ack_samples.len, update_samples.len, input_lost },
    );
    for (0..ack_samples.len) |index| {
        if (index != 0) try report.appendSlice(gpa, ",");
        try report.appendSlice(gpa, if (index % 2 == 0) "\"backspace\"" else "\"insert_x\"");
    }
    try report.appendSlice(
        gpa,
        "],\"scope\":{\"output_proto\":false,\"redisplay_owned_rendering\":false,\"gpu_rendering_evidence\":false,\"end_to_end_present_latency\":false,\"pgtk_comparison\":false,\"host_independent_regression\":false},\"result\":\"pass\"}\n",
    );
    if (config.benchmark_output.len > 0) {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = config.benchmark_output, .data = report.items });
    }
    std.debug.print("{s}", .{report.items});
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

fn appendKeyDescriptionModifier(gpa: std.mem.Allocator, out: *std.ArrayList(u8), enabled: bool, prefix: []const u8) !void {
    if (enabled) try out.appendSlice(gpa, prefix);
}

/// Translate a bounded full-key event to a canonical Emacs key description.
/// The mapping is deliberately closed: unknown names, lock-only input,
/// text-producing input, and non-ASCII logical keys stay observation-only
/// rather than reaching Emacs.
fn emacsKeyDescription(
    gpa: std.mem.Allocator,
    event: input_policy.FullKeyEvent,
    allow_prefixes: bool,
) !?[]u8 {
    if (event.state == .up or event.logicalKey().len == 0 or event.text().len != 0)
        return null;
    var description: std.ArrayList(u8) = .empty;
    errdefer description.deinit(gpa);
    const modifiers = event.modifiers;
    try appendKeyDescriptionModifier(gpa, &description, modifiers & input_policy.key_modifier_control != 0, "C-");
    try appendKeyDescriptionModifier(gpa, &description, modifiers & (input_policy.key_modifier_alt | input_policy.key_modifier_meta) != 0, "M-");
    try appendKeyDescriptionModifier(gpa, &description, modifiers & input_policy.key_modifier_super != 0, "s-");
    try appendKeyDescriptionModifier(gpa, &description, modifiers & input_policy.key_modifier_hyper != 0, "H-");
    try appendKeyDescriptionModifier(gpa, &description, modifiers & input_policy.key_modifier_shift != 0, "S-");

    const logical = event.logicalKey();
    const physical = event.physical_key;
    var key_name: ?[]const u8 = null;
    var fixed_buffer: [4]u8 = undefined;
    var function_buffer: [5]u8 = undefined;
    // Shifted printable characters belong to TEXT_INPUT in this slice.  A
    // command twin would double-insert when both reverse inputs are enabled.
    if (!allow_prefixes and
        logical.len == 1 and logical[0] >= 0x20 and logical[0] <= 0x7e and
        modifiers & ~input_policy.key_modifier_shift == 0) return null;
    if (physical >= 4 and physical <= 29) {
        // SDL keyboard-layout scancodes 4..29 are A..Z.  Canonical Emacs
        // command descriptions use lowercase base keys.
        fixed_buffer[0] = @intCast('a' + (physical - 4));
        key_name = fixed_buffer[0..1];
    } else if (physical >= 30 and physical <= 39) {
        // SDL scancodes 30..39 are the top-digit row 1..9 followed by 0.
        fixed_buffer[0] = if (physical == 39)
            '0'
        else
            @intCast('1' + (physical - 30));
        key_name = fixed_buffer[0..1];
    } else if (std.ascii.eqlIgnoreCase(logical, "return") or std.ascii.eqlIgnoreCase(logical, "enter")) {
        key_name = "RET";
    } else if (std.ascii.eqlIgnoreCase(logical, "escape")) {
        key_name = "ESC";
    } else if (std.ascii.eqlIgnoreCase(logical, "backspace")) {
        key_name = "DEL";
    } else if (std.ascii.eqlIgnoreCase(logical, "tab")) {
        key_name = "TAB";
    } else if (std.ascii.eqlIgnoreCase(logical, "space")) {
        key_name = "SPC";
    } else if (std.ascii.eqlIgnoreCase(logical, "up")) {
        key_name = "<up>";
    } else if (std.ascii.eqlIgnoreCase(logical, "down")) {
        key_name = "<down>";
    } else if (std.ascii.eqlIgnoreCase(logical, "left")) {
        key_name = "<left>";
    } else if (std.ascii.eqlIgnoreCase(logical, "right")) {
        key_name = "<right>";
    } else if (std.ascii.eqlIgnoreCase(logical, "home")) {
        key_name = "<home>";
    } else if (std.ascii.eqlIgnoreCase(logical, "end")) {
        key_name = "<end>";
    } else if (std.ascii.eqlIgnoreCase(logical, "pageup")) {
        key_name = "<prior>";
    } else if (std.ascii.eqlIgnoreCase(logical, "pagedown")) {
        key_name = "<next>";
    } else if (std.ascii.eqlIgnoreCase(logical, "insert")) {
        key_name = "<insert>";
    } else if (std.ascii.eqlIgnoreCase(logical, "delete")) {
        key_name = "<delete>";
    } else if (logical.len >= 2 and std.ascii.toLower(logical[0]) == 'f') {
        var number: usize = 0;
        var valid = true;
        for (logical[1..]) |byte| {
            if (byte < '0' or byte > '9') {
                valid = false;
                break;
            }
            number = number * 10 + (byte - '0');
            if (number > 24) {
                valid = false;
                break;
            }
        }
        if (valid and number > 0) {
            function_buffer[0] = '<';
            function_buffer[1] = 'f';
            var length: usize = 2;
            var value = number;
            var digits: [2]u8 = undefined;
            var digit_count: usize = 0;
            while (value > 0) {
                digits[digit_count] = @intCast('0' + value % 10);
                digit_count += 1;
                value /= 10;
            }
            while (digit_count > 0) {
                digit_count -= 1;
                function_buffer[length] = digits[digit_count];
                length += 1;
            }
            function_buffer[length] = '>';
            key_name = function_buffer[0 .. length + 1];
        }
    }

    if (key_name == null and logical.len == 1) {
        const byte = logical[0];
        if (byte >= 'a' and byte <= 'z') {
            fixed_buffer[0] = byte;
            key_name = fixed_buffer[0..1];
        } else if (byte >= 'A' and byte <= 'Z') {
            fixed_buffer[0] = byte + ('a' - 'A');
            key_name = fixed_buffer[0..1];
        } else if (byte >= 0x20 and byte <= 0x7e and byte != ' ') {
            fixed_buffer[0] = byte;
            key_name = fixed_buffer[0..1];
        }
    }
    const name = key_name orelse {
        description.deinit(gpa);
        return null;
    };
    try description.appendSlice(gpa, name);
    // The rollback translator deliberately excludes control/prefix entry
    // points.  The general keymap loop sends them to Emacs unchanged.
    const rollback_suppressed = !allow_prefixes and
        (std.mem.eql(u8, description.items, "ESC") or
            std.mem.eql(u8, description.items, "C-g") or
            std.mem.eql(u8, description.items, "C-]") or
            std.mem.eql(u8, description.items, "C-u") or
            std.mem.eql(u8, description.items, "C-x") or
            std.mem.eql(u8, description.items, "M-x"));
    if (rollback_suppressed) {
        description.deinit(gpa);
        return null;
    }
    if (description.items.len > 32) {
        description.deinit(gpa);
        return null;
    }
    return try description.toOwnedSlice(gpa);
}

fn emacsGeneralKeyDescription(
    gpa: std.mem.Allocator,
    event: input_policy.FullKeyEvent,
) !?[]u8 {
    return emacsKeyDescription(gpa, event, true);
}

/// Turns an exact `C-x` prefix followed by one whitelisted base key into one
/// bounded Emacs command. The prefix event itself is never sent to Emacs, so
/// the bridge cannot leave an interactive prefix state pending.
const EmacsKeyCommandTranslator = struct {
    pending_c_x: bool = false,

    fn reset(self: *EmacsKeyCommandTranslator) void {
        self.pending_c_x = false;
    }

    fn suffixByte(event: input_policy.FullKeyEvent) ?u8 {
        if (event.state != .down or event.text().len != 0 or
            event.modifiers != 0) return null;
        const physical = event.physical_key;
        if (physical >= 4 and physical <= 29) {
            return @intCast('a' + (physical - 4));
        }
        if (physical >= 30 and physical <= 32) {
            return @intCast('1' + (physical - 30));
        }
        return null;
    }

    fn translate(
        self: *EmacsKeyCommandTranslator,
        gpa: std.mem.Allocator,
        event: input_policy.FullKeyEvent,
        single_command_allowed: bool,
        composite_command_allowed: bool,
    ) !?[]u8 {
        const is_c_x = event.state == .down and
            event.modifiers == input_policy.key_modifier_control and
            event.logicalKey().len == 1 and
            std.ascii.toLower(event.logicalKey()[0]) == 'x';
        if (is_c_x) {
            self.pending_c_x = true;
            return null;
        }
        if (self.pending_c_x) {
            self.pending_c_x = false;
            const suffix_byte = suffixByte(event) orelse return null;
            const allowed = suffix_byte == '1' or suffix_byte == '2' or
                suffix_byte == '3' or suffix_byte == 'o';
            if (!composite_command_allowed or !allowed)
                return null;
            return try std.fmt.allocPrint(gpa, "C-x {c}", .{suffix_byte});
        }

        const base = try emacsKeyDescription(gpa, event, false);
        if (base == null) return null;
        if (!single_command_allowed) return null;
        return base;
    }
};

var emacs_key_command_translator: EmacsKeyCommandTranslator = .{};
var window_restore_edited_split_observed = false;

fn writeKeyV2Artifact(
    gpa: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    sequence: u64,
    event: input_policy.FullKeyEvent,
    single_command_allowed: bool,
    composite_command_allowed: bool,
    keymap_loop_allowed: bool,
) !void {
    const logical = try base64Alloc(gpa, event.logicalKey());
    defer gpa.free(logical);
    const text = try base64Alloc(gpa, event.text());
    defer gpa.free(text);
    const command_key = if (keymap_loop_allowed)
        try emacsGeneralKeyDescription(gpa, event)
    else
        try emacs_key_command_translator.translate(
            gpa,
            event,
            single_command_allowed,
            composite_command_allowed,
        );
    const encoded_key = if (command_key) |key| try base64Alloc(gpa, key) else null;
    defer if (encoded_key) |key| gpa.free(key);
    const value = try std.fmt.allocPrint(
        gpa,
        "{{\"schema\":2,\"state\":{d},\"modifiers\":{d},\"physical_key\":{d},\"repeat_count\":{d},\"device_id\":{d},\"layout_id\":{d},\"logical_key\":\"{s}\",\"text\":\"{s}\",\"command_key\":\"{s}\",\"execution\":\"{s}\"}}",
        .{
            @intFromEnum(event.state), event.modifiers,
            event.physical_key,        event.repeat_count,
            event.device_id,           event.layout_id,
            logical,                   text,
            encoded_key orelse "",
            if (encoded_key != null)
                if (keymap_loop_allowed) "keymap" else "command"
            else
                "observed",
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
                if (control.kind == .resync_request) return error.ResyncRequested;
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
                const is_monitor = payload.envelope.message_type == protocol.Message.monitor_event;
                const is_dpi = payload.envelope.message_type == protocol.Message.dpi_event;
                const is_theme = payload.envelope.message_type == protocol.Message.theme_event;
                const is_window = payload.envelope.message_type == protocol.Message.window_request;
                const is_scroll_request = payload.envelope.message_type == protocol.Message.scroll_request;
                const is_scrollbar_event = payload.envelope.message_type == protocol.Message.scrollbar_event;
                const is_menu_result = payload.envelope.message_type == protocol.Message.menu_result;
                const is_menu_cancel = payload.envelope.message_type == protocol.Message.menu_cancel;
                const is_menu_hover = payload.envelope.message_type == protocol.Message.menu_hover;
                const is_menu_open_request =
                    payload.envelope.message_type == protocol.Message.menu_open_request;
                const is_toolbar_click = payload.envelope.message_type == protocol.Message.toolbar_click;
                const is_dialog_result = payload.envelope.message_type == protocol.Message.dialog_result;
                const is_dnd_enter = payload.envelope.message_type == protocol.Message.dnd_enter;
                const is_dnd_drop = payload.envelope.message_type == protocol.Message.dnd_drop;
                const is_dnd_position = payload.envelope.message_type == protocol.Message.dnd_position;
                const is_dnd_data = payload.envelope.message_type == protocol.Message.dnd_data;
                var copy_action = false;
                if (is_key_v2) {
                    full_key = try input_policy.decodeFullKeyEvent(payload.bytes);
                } else if (is_key) {
                    const key = try frontend.decodeKeyEvent(payload.bytes);
                    copy_action = key.action == .copy;
                }
                var text_allowed = false;
                if (is_text) {
                    const text = try frontend.decodeTextInput(payload.bytes);
                    text_allowed = if (input_policy.isAsciiText(text.text))
                        capabilities.contains(.input_text_ascii) or
                            capabilities.contains(.input_text_unicode)
                    else
                        capabilities.contains(.input_text_unicode);
                }
                const input_allowed = (is_text and text_allowed) or
                    (is_key_v2 and capabilities.contains(.input_key_full_v2)) or
                    (is_key and capabilities.contains(.input_key_bounded) and
                        (!copy_action or capabilities.contains(.clipboard_ascii_bounded))) or
                    ((is_pointer_v2 and capabilities.contains(.input_pointer_v2)) or
                        (is_pointer and !is_pointer_v2 and capabilities.contains(.input_pointer_bounded))) or
                    (is_wheel and capabilities.contains(.input_wheel_line)) or
                    (is_focus and capabilities.contains(.platform_focus_window_events)) or
                    (is_monitor and capabilities.contains(.platform_monitor_events)) or
                    (is_dpi and capabilities.contains(.platform_dpi_events)) or
                    (is_theme and capabilities.contains(.platform_theme_events)) or
                    (is_window and capabilities.contains(.platform_focus_window_events)) or
                    (is_scroll_request and capabilities.contains(.window_scroll_request_v1)) or
                    (is_scrollbar_event and capabilities.contains(.window_scrollbar_event_v1)) or
                    (is_menu_result and capabilities.contains(.widget_menu_result_v1)) or
                    (is_menu_cancel and capabilities.contains(.widget_menu_result_v1)) or
                    (is_menu_hover and capabilities.contains(.widget_menu_hover_v1)) or
                    (is_menu_open_request and capabilities.contains(.widget_menu_open_request_v1)) or
                    (is_toolbar_click and capabilities.contains(.widget_toolbar_click_v1)) or
                    (is_dialog_result and capabilities.contains(.widget_dialog_result_v1)) or
                    ((is_dnd_enter or is_dnd_drop or is_dnd_position or is_dnd_data) and
                        capabilities.contains(.dnd_bounded_v1));
                if (!input_allowed or
                    payload.envelope.flags & protocol.Flags.requires_ack == 0 or
                    payload.envelope.ack_sequence != 0 or
                    payload.envelope.session_id != expected_session_id or
                    payload.envelope.frame_id != expected_frame_id)
                    return error.ExpectedAck;
                // Composite-prefix state is deliberately local to the key
                // stream. Any other reverse-input channel makes a stale C-x
                // prefix ineligible so a later digit cannot become a command.
                if (!is_key_v2) {
                    emacs_key_command_translator.reset();
                }
                if (payload.envelope.sequence + 1 == input_sequence.*) {
                    try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = payload.envelope.sequence });
                    try writer.interface.flush();
                    // The retried input only satisfies its own reverse-input
                    // ACK; the backend frame ACK we are awaiting is a separate
                    // control that still follows, so keep waiting for it.
                    continue;
                }
                if (payload.envelope.sequence != input_sequence.*) {
                    return error.InvalidSequence;
                }
                if (is_text) {
                    const input = try frontend.decodeTextInput(payload.bytes);
                    var encoded: [std.base64.standard.Encoder.calcSize(input_policy.max_dnd_payload)]u8 = undefined;
                    const encoded_len = std.base64.standard.Encoder.calcSize(input.text.len);
                    _ = std.base64.standard.Encoder.encode(encoded[0..encoded_len], input.text);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "text", encoded[0..encoded_len]);
                } else if (is_wheel) {
                    const event = try frontend.decodeWheelInput(payload.bytes);
                    const direction: []const u8 = if (event.x != 0)
                        (if (event.x > 0) "right" else "left")
                    else if (event.y > 0) "down" else "up";
                    const amount = if (event.x != 0) @abs(event.x) else @abs(event.y);
                    const value = try std.fmt.allocPrint(gpa, "{s} {d}", .{ direction, amount });
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
                    try writeKeyV2Artifact(
                        gpa,
                        io,
                        input_path,
                        payload.envelope.sequence,
                        full_key.?,
                        capabilities.contains(.input_key_command_v1),
                        capabilities.contains(.input_composite_key_command_v1),
                        capabilities.contains(.input_keymap_loop_v1),
                    );
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
                } else if (is_scroll_request or is_scrollbar_event) {
                    const event = try protocol.decodeScrollRequest(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"kind\":\"{s}\",\"axis\":\"{s}\",\"window_id\":{d},\"position\":{d},\"delta\":{d},\"frame_generation\":{d},\"execution\":\"observed\"}}",
                        .{
                            @tagName(event.kind),
                            @tagName(event.axis),
                            event.window_id,
                            event.position,
                            event.delta,
                            event.frame_generation,
                        },
                    );
                    defer gpa.free(value);
                    const artifact_kind: []const u8 = if (is_scrollbar_event) "scrollbar-event" else "scroll-request";
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, artifact_kind, value);
                } else if (is_menu_result) {
                    const event = try protocol.decodeMenuResult(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"menu_id\":{d},\"menu_generation\":{d},\"item_id\":{d},\"window_id\":{d},\"frame_generation\":{d},\"execution\":\"observed\"}}",
                        .{
                            event.menu_id,
                            event.menu_generation,
                            event.item_id,
                            event.window_id,
                            event.frame_generation,
                        },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "menu-result", value);
                } else if (is_menu_cancel) {
                    const event = try protocol.decodeMenuCancel(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"reason\":\"{s}\",\"menu_id\":{d},\"menu_generation\":{d},\"window_id\":{d},\"frame_generation\":{d},\"execution\":\"observed\"}}",
                        .{
                            @tagName(event.reason),
                            event.menu_id,
                            event.menu_generation,
                            event.window_id,
                            event.frame_generation,
                        },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "menu-cancel", value);
                } else if (is_toolbar_click) {
                    const event = try protocol.decodeToolbarClick(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"phase\":\"{s}\",\"toolbar_id\":{d},\"toolbar_generation\":{d},\"item_id\":{d},\"window_id\":{d},\"frame_generation\":{d},\"click_count\":{d},\"button\":{d},\"modifiers\":{d},\"x\":{d},\"y\":{d},\"execution\":\"observed\"}}",
                        .{
                            @tagName(event.phase),
                            event.toolbar_id,
                            event.toolbar_generation,
                            event.item_id,
                            event.window_id,
                            event.frame_generation,
                            event.click_count,
                            event.button,
                            event.modifiers,
                            event.x,
                            event.y,
                        },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "toolbar-click", value);
                } else if (is_dialog_result) {
                    const event = try protocol.decodeDialogResult(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"button\":\"{s}\",\"dialog_id\":{d},\"dialog_generation\":{d},\"window_id\":{d},\"frame_generation\":{d},\"has_text\":{},\"execution\":\"observed\"}}",
                        .{
                            @tagName(event.button),
                            event.dialog_id,
                            event.dialog_generation,
                            event.window_id,
                            event.frame_generation,
                            event.text_len != 0,
                        },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "dialog-result", value);
                } else if (is_dnd_enter) {
                    var event = try protocol.decodeDndEnter(gpa, payload.bytes);
                    defer protocol.freeDndEnter(gpa, &event);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"drag_id\":{d},\"x\":{d},\"y\":{d},\"action\":\"{s}\",\"offers\":{d},\"execution\":\"observed\"}}",
                        .{
                            event.drag_id,
                            event.x,
                            event.y,
                            @tagName(event.current_action),
                            event.offers.len,
                        },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "dnd-enter", value);
                } else if (is_dnd_drop) {
                    const event = try protocol.decodeDndDrop(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"drag_id\":{d},\"x\":{d},\"y\":{d},\"action\":\"{s}\",\"execution\":\"observed\"}}",
                        .{ event.drag_id, event.x, event.y, @tagName(event.action) },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "dnd-drop", value);
                } else if (is_dnd_position) {
                    const event = try protocol.decodeDndPosition(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"drag_id\":{d},\"x\":{d},\"y\":{d},\"action\":\"{s}\",\"execution\":\"observed\"}}",
                        .{ event.drag_id, event.x, event.y, @tagName(event.current_action) },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "dnd-position", value);
                } else if (is_dnd_data) {
                    const event = try protocol.decodeDndData(payload.bytes);
                    // The payload is delivered to Emacs as base64 so the
                    // artifact stays a single bounded line for any bytes.
                    var encoded: [176]u8 = undefined;
                    const encoded_len = std.base64.standard.Encoder.calcSize(event.bytes.len);
                    if (encoded_len > encoded.len) return error.InvalidDndData;
                    _ = std.base64.standard.Encoder.encode(encoded[0..encoded_len], event.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"drag_id\":{d},\"target\":\"{s}\",\"payload\":\"{s}\",\"execution\":\"observed\"}}",
                        .{ event.drag_id, event.target, encoded[0..encoded_len] },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "dnd-data", value);
                } else if (is_menu_hover) {
                    const event = try protocol.decodeMenuHover(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"phase\":\"{s}\",\"menu_id\":{d},\"menu_generation\":{d},\"item_id\":{d},\"window_id\":{d},\"frame_generation\":{d},\"x\":{d},\"y\":{d},\"execution\":\"observed\"}}",
                        .{
                            @tagName(event.phase),
                            event.menu_id,
                            event.menu_generation,
                            event.item_id,
                            event.window_id,
                            event.frame_generation,
                            event.x,
                            event.y,
                        },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "menu-hover", value);
                } else if (is_menu_open_request) {
                    const event = try protocol.decodeMenuOpenRequest(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"menu_id\":{d},\"menu_generation\":{d},\"item_id\":{d},\"window_id\":{d},\"frame_generation\":{d},\"x\":{d},\"y\":{d},\"execution\":\"observed\"}}",
                        .{
                            event.menu_id,
                            event.menu_generation,
                            event.item_id,
                            event.window_id,
                            event.frame_generation,
                            event.x,
                            event.y,
                        },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "menu-open-request", value);
                } else if (is_theme) {
                    const event = try protocol.decodeThemeEvent(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"appearance\":\"{s}\",\"contrast\":{d},\"flags\":{d},\"execution\":\"observed\"}}",
                        .{ @tagName(event.appearance), event.contrast, event.flags },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "theme", value);
                } else if (is_monitor) {
                    const event = try protocol.decodeMonitorEvent(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"kind\":\"{s}\",\"monitor_id\":{d},\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d},\"scale\":{d},\"refresh\":{d},\"primary\":{},\"current\":{},\"execution\":\"observed\"}}",
                        .{
                            @tagName(event.kind),
                            event.monitor_id,
                            event.x,
                            event.y,
                            event.width,
                            event.height,
                            event.scale_milli_percent,
                            event.refresh_milli_hz,
                            event.primary,
                            event.current,
                        },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "monitor", value);
                } else if (is_dpi) {
                    const event = try protocol.decodeDpiEvent(payload.bytes);
                    const value = try std.fmt.allocPrint(
                        gpa,
                        "{{\"frame_id\":{d},\"sdl_window_id\":{d},\"scale\":{d},\"dpi_x\":{d},\"dpi_y\":{d},\"execution\":\"observed\"}}",
                        .{
                            event.frame_id,
                            event.sdl_window_id,
                            event.scale_milli_percent,
                            event.dpi_x_milli,
                            event.dpi_y_milli,
                        },
                    );
                    defer gpa.free(value);
                    try writeEpxlInputArtifact(gpa, io, input_path, payload.envelope.sequence, "dpi", value);
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
                try waitForApplyAck(gpa, io, input_path, input_sequence.*);
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
    snapshot: facts.Snapshot,
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
    skip_first: bool,
) !void {
    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| gpa.free(message);
        messages.deinit(gpa);
    }
    try facts.appendWireSnapshotWindows(gpa, snapshot.facts, snapshot.windows, snapshot.contents, text, cursor, viewport, scene, &messages);
    if (snapshot.menu_bar.len != 0)
        try facts.appendMenuMessages(gpa, scene, snapshot.menu_bar, snapshot.open_menu, &messages);
    if (snapshot.tool_bar.len != 0)
        try facts.appendToolbarMessages(gpa, scene, snapshot.tool_bar, &messages);
    if (snapshot.font_file != null or snapshot.facts.font_pixel_size > 0)
        try facts.appendFontMessages(gpa, scene, snapshot.font_file, snapshot.facts.font_pixel_size, snapshot.variable_font_file, snapshot.alt_font_files, &messages);
    try facts.appendEchoMessages(gpa, scene, snapshot.echo, &messages);
    for (messages.items, 0..) |message, index| {
        if (skip_first and index == 0) continue;
        const envelope = (try protocol.decodeEnvelope(message)).envelope;
        try acks.markSent(envelope.sequence);
        try live.writeFrame(&writer.interface, message);
        try writer.interface.flush();
        // A skipped sequence makes the frontend reject the next frame and ask
        // for an authoritative snapshot instead of ACKing it.
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
                if (std.mem.eql(u8, text.bytes, "Emacs"))
                    run_rendered = true;
                if (std.mem.indexOf(u8, text.bytes, "stale facts text") != null)
                    stale_text_rendered = true;
            },
            .unicode_text => |text| {
                if (std.mem.eql(u8, text.bytes, "Emacs"))
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
            .unicode_text => |text| {
                if (std.mem.eql(u8, text.bytes, "Emacs"))
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

    _ = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters, null);
    var quit = false;
    const started = SDL_GetTicks();
    while (!quit and SDL_GetTicks() - started < config.auto_quit_ms) {
        var event: SDL_Event = undefined;
        while (SDL_PollEvent(&event)) {
            switch (event.type) {
                SDL_EVENT_QUIT => quit = true,
                SDL_EVENT_RENDER_TARGETS_RESET,
                SDL_EVENT_RENDER_DEVICE_RESET,
                SDL_EVENT_RENDER_DEVICE_LOST,
                => unicode_text_renderer.clearTextures(),
                else => {},
            }
        }
        _ = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters, null);
        SDL_Delay(10);
    }
    if (frame_counters.text_commands_total + frame_counters.unicode_text_commands_total == 0)
        return error.GlyphRunNotRendered;
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

fn applyRuntimeSceneMessage(
    gpa: std.mem.Allocator,
    scene: *frontend.Scene,
    message_type: u16,
    sequence: u64,
    session_id: u64,
    frame_id: u32,
    payload: []const u8,
) !void {
    var message: std.ArrayList(u8) = .empty;
    defer message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = session_id,
        .frame_id = frame_id,
        .timestamp_ns = 1,
    }, payload, &message);
    try scene.apply(message.items);
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

    const captured_face = try protocol.encodeFaceDefineBytes(.{
        .face_id = 7,
        .generation = 1,
        .presence = .{ .foreground = true, .background = true },
        .foreground = .{ 0xff, 0xd5, 0x4d, 255 },
        .background = .{ 0x20, 0x28, 0x38, 255 },
    });
    try bridge.observeFace(.{ .bytes = captured_face });

    var family: [64]u8 = @splat(0);
    @memcpy(family[0..7], "Adaptor");
    var foundry: [32]u8 = @splat(0);
    @memcpy(foundry[0..4], "Test");
    var style: [32]u8 = @splat(0);
    @memcpy(style[0..4], "Mono");
    const captured_font = try protocol.encodeFontDefineBytes(.{
        .font_id = 8,
        .generation = 1,
        .family = family,
        .family_len = "Adaptor".len,
        .foundry = foundry,
        .foundry_len = "Test".len,
        .style = style,
        .style_len = "Mono".len,
        .pixel_size = 16,
        .x_dpi = 96,
        .y_dpi = 96,
        .ascent = 10,
        .descent = 3,
        .line_height = 13,
        .average_advance = 8,
        .space_advance = 8,
        .max_advance = 8,
        .min_advance = 8,
        .fixed_pitch = true,
        .spacing = .mono,
    });
    try bridge.observeFont(.{ .bytes = captured_font });

    var captured_image_pixels: [1024]u8 = @splat(0);
    for (&captured_image_pixels, 0..) |*byte, index| byte.* = @truncate(index * 7 + 9);
    const captured_image_define = try protocol.encodeImageDefineBytes(.{
        .image_id = 31,
        .generation = 1,
        .width = 4,
        .height = 4,
        .total_byte_count = 64,
        .cache_policy = .pinned,
    });
    try bridge.observeImageDefine(.{ .bytes = captured_image_define });
    var image_fragment: runtime_host.ImageFragmentRecord = .{
        .image_id = 31,
        .generation = 1,
        .fragment_index = 0,
        .fragment_count = 1,
        .byte_length = 64,
        .reserved = 0,
    };
    @memcpy(image_fragment.bytes[0..64], captured_image_pixels[0..64]);
    try bridge.observeImageFragment(image_fragment);

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
    var face_define: std.ArrayList(u8) = .empty;
    defer face_define.deinit(gpa);
    try bridge.encodeFaceDefine(gpa, 0, 1, capability.session_id, 1, &face_define);
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

    var image_define: std.ArrayList(u8) = .empty;
    defer image_define.deinit(gpa);
    try bridge.encodeImageDefine(gpa, 0, 16, capability.session_id, 1, &image_define);
    try scene.apply(image_define.items);

    var image_data: std.ArrayList(u8) = .empty;
    defer image_data.deinit(gpa);
    try bridge.encodeImageFragment(gpa, 0, 0, 17, capability.session_id, 1, &image_data);
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
        .message_type = protocol.Message.scrollbar_state,
        .sequence = 32,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, scrollbar_payload.items, &scrollbar_update);
    try scene.apply(scrollbar_update.items);
    if (scene.scroll_states.items.len != 1 or scene.scroll_states.items[0].position != 400)
        return error.RuntimeBridgeScrollbarInvalid;

    var window_face_payload: std.ArrayList(u8) = .empty;
    defer window_face_payload.deinit(gpa);
    try frontend.encodeWindowFaceState(gpa, .{
        .window_id = 10,
        .frame_generation = bridge.eup_frame_generation,
        .face_id = 7,
        .face_generation = 1,
    }, &window_face_payload);
    var window_face_update: std.ArrayList(u8) = .empty;
    defer window_face_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.window_face,
        .sequence = 33,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, window_face_payload.items, &window_face_update);
    try scene.apply(window_face_update.items);
    if (scene.window_faces.items.len != 1 or scene.window_faces.items[0].face_id != 7)
        return error.RuntimeBridgeWindowFaceInvalid;

    var window_geometry_payload: std.ArrayList(u8) = .empty;
    defer window_geometry_payload.deinit(gpa);
    try frontend.encodeWindowGeometryState(gpa, .{
        .window_id = 10,
        .frame_generation = bridge.eup_frame_generation,
        .content = .{ .x = 2, .y = 2, .width = 60, .height = 36 },
        .body = .{ .x = 4, .y = 4, .width = 50, .height = 30 },
    }, &window_geometry_payload);
    var window_geometry_update: std.ArrayList(u8) = .empty;
    defer window_geometry_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.window_geometry,
        .sequence = 34,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, window_geometry_payload.items, &window_geometry_update);
    try scene.apply(window_geometry_update.items);
    if (scene.window_geometries.items.len != 1 or scene.window_geometries.items[0].body.width != 50)
        return error.RuntimeBridgeWindowGeometryInvalid;

    var window_zones_payload: std.ArrayList(u8) = .empty;
    defer window_zones_payload.deinit(gpa);
    var window_zones_state: frontend.WindowZonesState = .{
        .window_id = 10,
        .frame_generation = bridge.eup_frame_generation,
        .presence = frontend.WindowZoneBits.left_fringe |
            frontend.WindowZoneBits.vertical_scrollbar,
    };
    window_zones_state.zones[@ctz(frontend.WindowZoneBits.left_fringe)] = .{ .x = 0, .y = 0, .width = 3, .height = 40 };
    window_zones_state.zones[@ctz(frontend.WindowZoneBits.vertical_scrollbar)] = .{ .x = 188, .y = 0, .width = 12, .height = 40 };
    try frontend.encodeWindowZonesState(gpa, window_zones_state, &window_zones_payload);
    var window_zones_update: std.ArrayList(u8) = .empty;
    defer window_zones_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.window_zones,
        .sequence = 35,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, window_zones_payload.items, &window_zones_update);
    try scene.apply(window_zones_update.items);
    if (scene.window_zones.items.len != 1 or scene.window_zones.items[0].presence != 288)
        return error.RuntimeBridgeWindowZonesInvalid;

    var window_position_payload: std.ArrayList(u8) = .empty;
    defer window_position_payload.deinit(gpa);
    try frontend.encodeWindowPositionState(gpa, .{
        .flags = frontend.WindowPositionFlags.point_visible,
        .window_id = 10,
        .frame_generation = bridge.eup_frame_generation,
        .buffer_id = 31,
        .buffer_generation = 7,
        .window_start = 101,
        .point = 122,
    }, &window_position_payload);
    var window_position_update: std.ArrayList(u8) = .empty;
    defer window_position_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.window_position,
        .sequence = 36,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, window_position_payload.items, &window_position_update);
    try scene.apply(window_position_update.items);
    if (scene.window_positions.items.len != 1 or scene.window_positions.items[0].point != 122)
        return error.RuntimeBridgeWindowPositionInvalid;

    var mouse_highlight_payload: std.ArrayList(u8) = .empty;
    defer mouse_highlight_payload.deinit(gpa);
    try frontend.encodeMouseHighlightState(gpa, .{
        .flags = frontend.MouseHighlightFlags.visible,
        .window_id = 10,
        .frame_generation = bridge.eup_frame_generation,
        .rect = .{ .x = 48, .y = 24, .width = 32, .height = 16 },
        .face_id = 7,
        .face_generation = 1,
    }, &mouse_highlight_payload);
    var mouse_highlight_update: std.ArrayList(u8) = .empty;
    defer mouse_highlight_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.mouse_highlight,
        .sequence = 37,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, mouse_highlight_payload.items, &mouse_highlight_update);
    try scene.apply(mouse_highlight_update.items);
    if (scene.mouse_highlight_count != 1 or scene.mouse_highlights[0].face_id != 7)
        return error.RuntimeBridgeMouseHighlightInvalid;

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
    var window_face_background_rendered = false;
    var window_geometry_rendered = false;
    var window_zones_rendered = false;
    var mouse_highlight_rendered = false;
    var fringe_bitmap_rendered = false;
    var tooltip_box_rendered = false;
    var tooltip_text_rendered = false;
    var cursor_update_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 20 and fill.rect.y == 16 and fill.color.r == 0x20 and fill.color.g == 0x28 and fill.color.b == 0x38)
                    face_background = true;
                if (fill.rect.x == 8 and fill.rect.y == 8 and
                    fill.rect.width == 200 and fill.rect.height == 40 and
                    fill.color.r == 0x20 and fill.color.g == 0x28 and fill.color.b == 0x38)
                    window_face_background_rendered = true;
                if (fill.rect.x == 12 and fill.rect.y == 12 and
                    fill.rect.width == 50 and fill.rect.height == 1 and
                    fill.color.r == 0x38 and fill.color.g == 0xd9 and fill.color.b == 0xa9)
                    window_geometry_rendered = true;
                if (fill.rect.x == 8 and fill.rect.y == 8 and
                    fill.rect.width == 3 and fill.rect.height == 1 and
                    fill.color.r == 0xcc and fill.color.g == 0x66 and fill.color.b == 0x33)
                    window_zones_rendered = true;
                if (fill.rect.x == 56 and fill.rect.y == 32 and
                    fill.rect.width == 32 and fill.rect.height == 16 and
                    fill.color.r == 0x20 and fill.color.g == 0x28 and fill.color.b == 0x38)
                    mouse_highlight_rendered = true;
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
            .unicode_text => |text| {
                if (text.color.r == 0xff and text.color.g == 0xd5 and
                    std.mem.eql(u8, text.bytes, "Emacs"))
                    run_rendered = true;
            },
            else => {},
        }
    }
    if (!face_background or !window_face_background_rendered or !window_geometry_rendered or
        !window_zones_rendered or !mouse_highlight_rendered or !run_rendered or !cursor_update_rendered)
        return error.RuntimeBridgeNotRendered;

    var frame_gate: renderer_policy.FrameGate = .{};
    var frame_counters: renderer_policy.FrameCounters = .{};
    var retained_frame: RetainedFrame = .{};
    defer destroyRetainedFrame(&retained_frame);
    var atlas_texture_cache = AtlasTextureCache.init(gpa);
    defer atlas_texture_cache.deinit();
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
        &atlas_texture_cache,
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
        .sequence = 38,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, explicit_payload.items, &explicit_message);
    try scene.apply(explicit_message.items);
    if (scene.damage.items.len != 1 or scene.damage.items[0].width != explicit_damage[0].width)
        return error.RuntimeBridgeDamageRectsInvalid;

    var captured_font_message: std.ArrayList(u8) = .empty;
    defer captured_font_message.deinit(gpa);
    try bridge.encodeFontDefine(gpa, 0, 39, capability.session_id, 39, &captured_font_message);
    try scene.apply(captured_font_message.items);
    if (scene.fonts.lookup(8) == null)
        return error.RuntimeBridgeFontInvalid;

    var atlas_define_message: std.ArrayList(u8) = .empty;
    defer atlas_define_message.deinit(gpa);
    var atlas_define_payload: std.ArrayList(u8) = .empty;
    defer atlas_define_payload.deinit(gpa);
    try protocol.encodeAtlasDefine(gpa, .{
        .atlas_id = 7,
        .generation = 1,
        .width = 64,
        .height = 8,
        .page_count = 1,
    }, &atlas_define_payload);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.atlas_define,
        .sequence = 40,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, atlas_define_payload.items, &atlas_define_message);
    try scene.apply(atlas_define_message.items);

    var atlas_pixels: [2048]u8 = @splat(255);
    var atlas_page_payload: std.ArrayList(u8) = .empty;
    defer atlas_page_payload.deinit(gpa);
    try protocol.encodeAtlasPageUpdate(gpa, .{
        .atlas_id = 7,
        .generation = 1,
        .page_index = 0,
        .page_count = 1,
        .x = 0,
        .y = 0,
        .width = 64,
        .height = 8,
        .bytes = &atlas_pixels,
    }, &atlas_page_payload);
    var atlas_page_message: std.ArrayList(u8) = .empty;
    defer atlas_page_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.atlas_page_update,
        .sequence = 41,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, atlas_page_payload.items, &atlas_page_message);
    try scene.apply(atlas_page_message.items);
    if (scene.atlases.lookup(7) == null)
        return error.RuntimeBridgeAtlasInvalid;

    const atlas_glyphs = [_]protocol.AtlasGlyphAdd{
        .{ .atlas_id = 7, .generation = 1, .glyph_id = 'E', .font_id = 8, .size_px = 8, .variation_hash = 0, .x = 0, .y = 0, .width = 6, .height = 8, .baseline = 8, .advance_x = 6 },
        .{ .atlas_id = 7, .generation = 1, .glyph_id = 'm', .font_id = 8, .size_px = 8, .variation_hash = 0, .x = 8, .y = 0, .width = 8, .height = 8, .baseline = 8, .advance_x = 8 },
        .{ .atlas_id = 7, .generation = 1, .glyph_id = 'a', .font_id = 8, .size_px = 8, .variation_hash = 0, .x = 18, .y = 0, .width = 6, .height = 8, .baseline = 8, .advance_x = 6 },
        .{ .atlas_id = 7, .generation = 1, .glyph_id = 'c', .font_id = 8, .size_px = 8, .variation_hash = 0, .x = 26, .y = 0, .width = 6, .height = 8, .baseline = 8, .advance_x = 6 },
        .{ .atlas_id = 7, .generation = 1, .glyph_id = 's', .font_id = 8, .size_px = 8, .variation_hash = 0, .x = 34, .y = 0, .width = 6, .height = 8, .baseline = 8, .advance_x = 6 },
    };
    for (atlas_glyphs, 0..) |glyph, index| {
        var atlas_glyph_payload: std.ArrayList(u8) = .empty;
        defer atlas_glyph_payload.deinit(gpa);
        try protocol.encodeAtlasGlyphAdd(gpa, .{
            .atlas_id = 7,
            .generation = 1,
            .glyph_id = glyph.glyph_id,
            .font_id = glyph.font_id,
            .size_px = glyph.size_px,
            .variation_hash = glyph.variation_hash,
            .x = glyph.x,
            .y = glyph.y,
            .width = glyph.width,
            .height = glyph.height,
            .baseline = glyph.baseline,
            .advance_x = glyph.advance_x,
        }, &atlas_glyph_payload);
        var atlas_glyph_message: std.ArrayList(u8) = .empty;
        defer atlas_glyph_message.deinit(gpa);
        try protocol.encodeEnvelope(gpa, .{
            .flags = 0,
            .message_type = protocol.Message.atlas_glyph_add,
            .sequence = 42 + @as(u64, @intCast(index)),
            .ack_sequence = 0,
            .session_id = capability.session_id,
            .frame_id = @intCast(bridge.frame.id),
            .timestamp_ns = 1,
        }, atlas_glyph_payload.items, &atlas_glyph_message);
        try scene.apply(atlas_glyph_message.items);
    }
    if (scene.atlases.lookup(7).?.glyphs.items.len != 5)
        return error.RuntimeBridgeAtlasGlyphsInvalid;

    var font_patch_payload: std.ArrayList(u8) = .empty;
    defer font_patch_payload.deinit(gpa);
    try protocol.encodeFontPatch(gpa, .{
        .font_id = 8,
        .expected_generation = 1,
        .new_generation = 2,
        .weight = 700,
        .width_percent = 100,
        .pixel_size = 16,
        .point_size_tenths = 0,
        .x_dpi = 96,
        .y_dpi = 96,
        .slant = .roman,
        .spacing = .mono,
        .scalable = false,
        .fixed_pitch = true,
    }, &font_patch_payload);
    var font_patch_update: std.ArrayList(u8) = .empty;
    defer font_patch_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.font_patch,
        .sequence = 47,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, font_patch_payload.items, &font_patch_update);
    try scene.apply(font_patch_update.items);
    const patched_font = scene.fonts.lookup(8) orelse return error.RuntimeBridgeFontPatchInvalid;
    if (patched_font.generation != 2 or patched_font.payload.weight != 700)
        return error.RuntimeBridgeFontPatchInvalid;

    var fringe_bitmap_payload: std.ArrayList(u8) = .empty;
    defer fringe_bitmap_payload.deinit(gpa);
    var fringe_bitmap: protocol.FringeBitmapDefine = .{
        .bitmap_id = 9,
        .generation = 1,
        .width = 2,
        .height = 2,
    };
    fringe_bitmap.bits[0] = 0x80;
    fringe_bitmap.bits[(protocol.max_fringe_bitmap_dimension + 7) / 8] = 0x40;
    try protocol.encodeFringeBitmapDefine(gpa, fringe_bitmap, &fringe_bitmap_payload);
    var fringe_bitmap_update: std.ArrayList(u8) = .empty;
    defer fringe_bitmap_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.fringe_bitmap_define,
        .sequence = 48,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, fringe_bitmap_payload.items, &fringe_bitmap_update);
    try scene.apply(fringe_bitmap_update.items);
    if (scene.fringe_bitmaps.lookup(9) == null)
        return error.RuntimeBridgeFringeBitmapInvalid;

    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 8 and fill.rect.y == 16 and
                    fill.rect.width == 4 and fill.rect.height == 12 and
                    fill.color.r == 0x22 and fill.color.g == 0x66 and fill.color.b == 0xaa)
                    fringe_bitmap_rendered = true;
            },
            else => {},
        }
    }
    if (!fringe_bitmap_rendered) return error.RuntimeBridgeFringeBitmapNotRendered;

    var tooltip_show: frontend.TooltipShow = .{
        .tooltip_id = 10,
        .generation = 1,
        .window_id = 10,
        .frame_generation = bridge.eup_frame_generation,
        .x = 16,
        .y = 16,
        .max_width = 32,
        .max_height = 16,
    };
    const tooltip_text = "Tooltip";
    tooltip_show.text_length = tooltip_text.len;
    @memcpy(tooltip_show.text[0..tooltip_text.len], tooltip_text);
    var tooltip_payload: std.ArrayList(u8) = .empty;
    defer tooltip_payload.deinit(gpa);
    try frontend.encodeTooltipShow(gpa, tooltip_show, &tooltip_payload);
    var tooltip_update: std.ArrayList(u8) = .empty;
    defer tooltip_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.tooltip_show,
        .sequence = 49,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, tooltip_payload.items, &tooltip_update);
    try scene.apply(tooltip_update.items);

    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 24 and fill.rect.y == 24 and
                    fill.rect.width == 32 and fill.rect.height == 16 and
                    fill.color.r == 0x20 and fill.color.g == 0x24 and fill.color.b == 0x2c)
                    tooltip_box_rendered = true;
            },
            .unicode_text => |text| {
                if (text.x == 28 and std.mem.eql(u8, text.bytes, tooltip_text))
                    tooltip_text_rendered = true;
            },
            else => {},
        }
    }
    if (!tooltip_box_rendered or !tooltip_text_rendered)
        return error.RuntimeBridgeTooltipNotRendered;

    tooltip_payload.clearRetainingCapacity();
    try frontend.encodeTooltipMove(gpa, .{
        .tooltip_id = 10,
        .generation = 1,
        .window_id = 10,
        .frame_generation = bridge.eup_frame_generation,
        .x = 24,
        .y = 24,
    }, &tooltip_payload);
    tooltip_update.clearRetainingCapacity();
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.tooltip_move,
        .sequence = 50,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, tooltip_payload.items, &tooltip_update);
    try scene.apply(tooltip_update.items);
    if (scene.tooltip.?.x != 24 or scene.tooltip.?.y != 24)
        return error.RuntimeBridgeTooltipMoveInvalid;

    var moved_tooltip_box = false;
    var moved_tooltip_text = false;
    var stale_tooltip_box = false;
    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 32 and fill.rect.y == 32 and
                    fill.rect.width == 32 and fill.rect.height == 16 and
                    fill.color.r == 0x20 and fill.color.g == 0x24 and fill.color.b == 0x2c)
                    moved_tooltip_box = true;
                if (fill.rect.x == 24 and fill.rect.y == 24 and
                    fill.rect.width == 32 and fill.rect.height == 16 and
                    fill.color.r == 0x20 and fill.color.g == 0x24 and fill.color.b == 0x2c)
                    stale_tooltip_box = true;
            },
            .unicode_text => |text| {
                if (text.x == 36 and std.mem.eql(u8, text.bytes, tooltip_text))
                    moved_tooltip_text = true;
            },
            else => {},
        }
    }
    if (!moved_tooltip_box or !moved_tooltip_text or stale_tooltip_box)
        return error.RuntimeBridgeTooltipMoveNotRendered;

    tooltip_payload.clearRetainingCapacity();
    try frontend.encodeTooltipHide(gpa, .{ .tooltip_id = 10, .generation = 1 }, &tooltip_payload);
    tooltip_update.clearRetainingCapacity();
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.tooltip_hide,
        .sequence = 51,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, tooltip_payload.items, &tooltip_update);
    try scene.apply(tooltip_update.items);
    if (scene.tooltip != null) return error.RuntimeBridgeTooltipHideInvalid;

    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 32 and fill.rect.y == 32 and
                    fill.rect.width == 32 and fill.rect.height == 16 and
                    fill.color.r == 0x20 and fill.color.g == 0x24 and fill.color.b == 0x2c)
                    return error.RuntimeBridgeTooltipHideNotRendered;
            },
            else => {},
        }
    }

    var menu_nodes = [_]protocol.MenuNode{ .{
        .item_id = 20,
        .parent_item_id = 0,
        .kind = .submenu,
        .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
        .depth = 0,
        .label_len = 4,
    }, .{
        .item_id = 21,
        .parent_item_id = 20,
        .kind = .command,
        .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
        .depth = 1,
        .label_len = 8,
    }, .{
        .item_id = 22,
        .parent_item_id = 0,
        .kind = .command,
        .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
        .depth = 0,
        .label_len = 8,
    } };
    @memcpy(menu_nodes[0].label[0..4], "File");
    @memcpy(menu_nodes[1].label[0..8], "NewFrame");
    @memcpy(menu_nodes[2].label[0..8], "Файл");
    var menu_payload: std.ArrayList(u8) = .empty;
    defer menu_payload.deinit(gpa);
    try protocol.encodeMenuModelSnapshot(gpa, .{
        .header = .{
            .frame_id = @intCast(bridge.frame.id),
            .frame_generation = bridge.eup_frame_generation,
            .menu_id = 3,
            .menu_generation = 1,
        },
        .nodes = &menu_nodes,
    }, &menu_payload);
    var menu_update: std.ArrayList(u8) = .empty;
    defer menu_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.menu_model,
        .sequence = 52,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, menu_payload.items, &menu_update);
    try scene.apply(menu_update.items);
    if (scene.menu_model == null or scene.menu_model.?.nodes.len != 3)
        return error.RuntimeBridgeMenuModelInvalid;

    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var menu_box_rendered = false;
    var menu_text_rendered = false;
    var unicode_text_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 0 and fill.rect.y == 0 and
                    fill.rect.width == 6 and fill.rect.height == 8 and
                    fill.color.r == 0x20 and fill.color.g == 0x24 and fill.color.b == 0x2c)
                    menu_box_rendered = true;
            },
            .unicode_text => |text| {
                if (std.mem.eql(u8, text.bytes, "File"))
                    menu_text_rendered = true;
                if (std.mem.eql(u8, text.bytes, "Файл"))
                    unicode_text_rendered = true;
            },
            else => {},
        }
    }
    if (!menu_box_rendered or !menu_text_rendered or unicode_text_rendered)
        return error.RuntimeBridgeMenuModelNotRendered;

    var menu_open_payload: std.ArrayList(u8) = .empty;
    defer menu_open_payload.deinit(gpa);
    try protocol.encodeMenuOpen(gpa, .{
        .menu_id = 3,
        .menu_generation = 1,
        .item_id = 20,
        .window_id = 10,
        .frame_generation = bridge.eup_frame_generation,
        .x = 16,
        .y = 16,
        .width = 48,
        .height = 16,
    }, &menu_open_payload);
    var menu_open_update: std.ArrayList(u8) = .empty;
    defer menu_open_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.menu_open,
        .sequence = 53,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, menu_open_payload.items, &menu_open_update);
    try scene.apply(menu_open_update.items);

    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var menu_popup_box_rendered = false;
    var menu_popup_text_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 24 and fill.rect.y == 24 and
                    fill.rect.width == 48 and fill.rect.height == 16 and
                    fill.color.r == 0x20 and fill.color.g == 0x24 and fill.color.b == 0x2c)
                    menu_popup_box_rendered = true;
            },
            .unicode_text => |text| {
                if (std.mem.eql(u8, text.bytes, "NewFrame"))
                    menu_popup_text_rendered = true;
            },
            else => {},
        }
    }
    if (!menu_popup_box_rendered or !menu_popup_text_rendered)
        return error.RuntimeBridgeMenuOpenNotRendered;

    var menu_close_payload: std.ArrayList(u8) = .empty;
    defer menu_close_payload.deinit(gpa);
    try protocol.encodeMenuClose(gpa, .{
        .reason = .dismissal,
        .menu_id = 3,
        .menu_generation = 1,
        .item_id = 21,
        .frame_generation = bridge.eup_frame_generation,
    }, &menu_close_payload);
    var menu_close_update: std.ArrayList(u8) = .empty;
    defer menu_close_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.menu_close,
        .sequence = 54,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, menu_close_payload.items, &menu_close_update);
    try scene.apply(menu_close_update.items);
    if (scene.menu_open != null) return error.RuntimeBridgeMenuCloseInvalid;

    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var menu_close_box_rendered = false;
    var menu_close_text_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 24 and fill.rect.y == 24 and
                    fill.rect.width == 48 and fill.rect.height == 16)
                    menu_close_box_rendered = true;
            },
            .text => |text| {
                if (std.mem.eql(u8, text.bytes, "NewFrame"))
                    menu_close_text_rendered = true;
            },
            else => {},
        }
    }
    if (menu_close_box_rendered or menu_close_text_rendered)
        return error.RuntimeBridgeMenuCloseStillRendered;

    var frame_patch_payload: std.ArrayList(u8) = .empty;
    defer frame_patch_payload.deinit(gpa);
    try protocol.encodeFramePatch(gpa, .{
        .presence = protocol.FramePatchFlags.visibility |
            protocol.FramePatchFlags.focus | protocol.FramePatchFlags.alpha |
            protocol.FramePatchFlags.decorations | protocol.FramePatchFlags.scale,
        .frame_generation = bridge.eup_frame_generation,
        .visibility = .visible,
        .focused = true,
        .decorated = false,
        .active_opacity = 9000,
        .inactive_opacity = 7000,
        .background_opacity = 9500,
        .scale = 1.25,
        .dpi_x = 96,
        .dpi_y = 120,
    }, &frame_patch_payload);
    var frame_patch_update: std.ArrayList(u8) = .empty;
    defer frame_patch_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_patch,
        .sequence = 55,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, frame_patch_payload.items, &frame_patch_update);
    try scene.apply(frame_patch_update.items);
    if (scene.alpha == null or scene.alpha.?.active_opacity != 9000 or
        scene.decorations == null or scene.decorations.?.decorated or
        scene.scale == null or scene.scale.?.scale != 1.25 or
        scene.scale.?.dpi_x != 96 or scene.scale.?.dpi_y != 120)
        return error.RuntimeBridgeFramePatchInvalid;

    const frame_patch_opacity = @as(f32, @floatFromInt(scene.alpha.?.active_opacity)) / 10000.0;
    var frame_patch_opacity_applied = SDL_SetWindowOpacity(window, frame_patch_opacity);
    if (frame_patch_opacity_applied and
        @abs(SDL_GetWindowOpacity(window) - frame_patch_opacity) > 0.001)
        frame_patch_opacity_applied = false;
    _ = SDL_SetWindowOpacity(window, 1.0);

    var frame_patch_decorations_applied = SDL_SetWindowBordered(
        window,
        scene.decorations.?.decorated,
    );
    if (frame_patch_decorations_applied and
        (SDL_GetWindowFlags(window) & SDL_WINDOW_BORDERLESS) == 0)
        frame_patch_decorations_applied = false;
    _ = SDL_SetWindowBordered(window, true);

    const frame_patch_scale = scene.scale.?.scale;
    const frame_patch_scale_applied = SDL_SetRenderScale(
        selected_renderer.handle,
        frame_patch_scale,
        frame_patch_scale,
    );
    if (frame_patch_scale_applied) {
        var actual_scale_x: f32 = 0;
        var actual_scale_y: f32 = 0;
        SDL_GetRenderScale(selected_renderer.handle, &actual_scale_x, &actual_scale_y);
        if (@abs(actual_scale_x - frame_patch_scale) > 0.001 or
            @abs(actual_scale_y - frame_patch_scale) > 0.001)
            return error.RuntimeBridgeFramePatchScaleUnreadable;
        if (!SDL_SetRenderScale(selected_renderer.handle, 1, 1))
            return error.RuntimeBridgeFramePatchScaleRestoreInvalid;
    }
    if (!frame_patch_opacity_applied or !frame_patch_decorations_applied or
        !frame_patch_scale_applied)
        return error.RuntimeBridgeFramePatchNotApplied;

    var frame_snapshot_payload: std.ArrayList(u8) = .empty;
    defer frame_snapshot_payload.deinit(gpa);
    try protocol.encodeFrameSnapshot(gpa, .{
        .frame_generation = bridge.eup_frame_generation,
        .visibility = .visible,
        .focused = true,
        .fullscreen = .none,
        .maximize_flags = protocol.FrameMaximizeFlags.both,
        .decorated = false,
        .active_opacity = 9000,
        .inactive_opacity = 7000,
        .background_opacity = 9500,
        .outer = .{ .x = 0, .y = 0, .width = 248, .height = 96 },
        .content = .{ .x = 4, .y = 4, .width = 240, .height = 88 },
        .text = .{ .x = 4, .y = 4, .width = 240, .height = 88 },
        .window = .{ .x = 4, .y = 4, .width = 240, .height = 88 },
        .body = .{ .x = 8, .y = 8, .width = 232, .height = 80 },
    }, &frame_snapshot_payload);
    var frame_snapshot_update: std.ArrayList(u8) = .empty;
    defer frame_snapshot_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.frame_snapshot,
        .sequence = 56,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, frame_snapshot_payload.items, &frame_snapshot_update);
    try scene.apply(frame_snapshot_update.items);
    if (scene.geometry == null or scene.geometry.?.outer.width != 248 or
        scene.fullscreen == null or scene.fullscreen.?.mode != .none or
        scene.maximize == null or scene.maximize.?.flags != protocol.FrameMaximizeFlags.both)
        return error.RuntimeBridgeFrameSnapshotInvalid;

    const snapshot_opacity = @as(f32, @floatFromInt(scene.alpha.?.active_opacity)) / 10000.0;
    var snapshot_opacity_applied = SDL_SetWindowOpacity(window, snapshot_opacity);
    if (snapshot_opacity_applied and
        @abs(SDL_GetWindowOpacity(window) - snapshot_opacity) > 0.001)
        snapshot_opacity_applied = false;
    _ = SDL_SetWindowOpacity(window, 1.0);

    var snapshot_decorations_applied = SDL_SetWindowBordered(
        window,
        scene.decorations.?.decorated,
    );
    if (snapshot_decorations_applied and
        (SDL_GetWindowFlags(window) & SDL_WINDOW_BORDERLESS) == 0)
        snapshot_decorations_applied = false;
    _ = SDL_SetWindowBordered(window, true);

    var snapshot_scale_applied = SDL_SetRenderScale(
        selected_renderer.handle,
        scene.scale.?.scale,
        scene.scale.?.scale,
    );
    if (snapshot_scale_applied) {
        var snapshot_scale_x: f32 = 0;
        var snapshot_scale_y: f32 = 0;
        SDL_GetRenderScale(selected_renderer.handle, &snapshot_scale_x, &snapshot_scale_y);
        snapshot_scale_applied = @abs(snapshot_scale_x - scene.scale.?.scale) <= 0.001 and
            @abs(snapshot_scale_y - scene.scale.?.scale) <= 0.001;
    }
    _ = SDL_SetRenderScale(selected_renderer.handle, 1, 1);

    const snapshot_fullscreen_applied = scene.fullscreen.?.mode == .none and
        (SDL_GetWindowFlags(window) & SDL_WINDOW_FULLSCREEN) == 0;

    var snapshot_maximize_applied = false;
    if (SDL_SetWindowResizable(window, true)) {
        const requested = SDL_MaximizeWindow(window);
        snapshot_maximize_applied = requested and SDL_SyncWindow(window) and
            (SDL_GetWindowFlags(window) & SDL_WINDOW_MAXIMIZED) != 0;
        const restored = SDL_RestoreWindow(window) and SDL_SyncWindow(window) and
            (SDL_GetWindowFlags(window) & SDL_WINDOW_MAXIMIZED) == 0;
        if (!restored) return error.RuntimeBridgeFrameSnapshotMaximizeRestoreFailed;
    }
    _ = SDL_SetWindowResizable(window, false);

    // Probe geometry on a fresh bounded window so earlier size-hint/maximize
    // diagnostics do not contaminate restoration.
    const snapshot_window = SDL_CreateWindow(
        "Emacs Proto-UI Frame Snapshot",
        240,
        96,
        SDL_WINDOW_RESIZABLE,
    ) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(snapshot_window);
    var snapshot_geometry_applied = SDL_SetWindowSize(
        snapshot_window,
        @intCast(scene.geometry.?.outer.width),
        @intCast(scene.geometry.?.outer.height),
    ) and
        SDL_SyncWindow(snapshot_window);
    if (snapshot_geometry_applied) {
        var width: c_int = 0;
        var height: c_int = 0;
        SDL_GetWindowSize(snapshot_window, &width, &height);
        snapshot_geometry_applied = width == scene.geometry.?.outer.width and
            height == scene.geometry.?.outer.height;
    }
    var snapshot_geometry_restored = SDL_SetWindowSize(snapshot_window, 240, 96) and
        SDL_SyncWindow(snapshot_window);
    if (snapshot_geometry_restored) {
        var width: c_int = 0;
        var height: c_int = 0;
        SDL_GetWindowSize(snapshot_window, &width, &height);
        snapshot_geometry_restored = width == 240 and height == 96;
    }
    if (!snapshot_geometry_applied) return error.RuntimeBridgeFrameSnapshotNotApplied;
    if (!snapshot_geometry_restored) return error.RuntimeBridgeFrameSnapshotGeometryRestoreFailed;

    if (!snapshot_opacity_applied or !snapshot_decorations_applied or
        !snapshot_scale_applied or !snapshot_fullscreen_applied or
        !snapshot_maximize_applied or !snapshot_geometry_applied)
        return error.RuntimeBridgeFrameSnapshotNotApplied;

    var menu_patch_operations = [_]protocol.MenuPatchOperation{
        .{ .operation = .upsert, .node = .{
            .item_id = 20,
            .parent_item_id = 0,
            .kind = .submenu,
            .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
            .depth = 0,
            .label_len = 5,
        } },
        .{ .operation = .upsert, .node = .{
            .item_id = 21,
            .parent_item_id = 20,
            .kind = .command,
            .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
            .depth = 1,
            .label_len = 8,
        } },
        .{ .operation = .upsert, .node = .{
            .item_id = 22,
            .parent_item_id = 0,
            .kind = .command,
            .flags = protocol.MenuNodeFlags.enabled | protocol.MenuNodeFlags.visible,
            .depth = 0,
            .label_len = 8,
        } },
    };
    @memcpy(menu_patch_operations[0].node.label[0..5], "Files");
    @memcpy(menu_patch_operations[1].node.label[0..8], "NewFrame");
    @memcpy(menu_patch_operations[2].node.label[0..8], "Файл");
    var menu_patch_payload: std.ArrayList(u8) = .empty;
    defer menu_patch_payload.deinit(gpa);
    try protocol.encodeMenuPatch(gpa, .{
        .frame_id = @intCast(bridge.frame.id),
        .frame_generation = bridge.eup_frame_generation,
        .menu_id = 3,
        .expected_generation = 1,
        .new_generation = 2,
    }, &menu_patch_operations, &menu_patch_payload);
    var menu_patch_update: std.ArrayList(u8) = .empty;
    defer menu_patch_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.menu_patch,
        .sequence = 57,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, menu_patch_payload.items, &menu_patch_update);
    try scene.apply(menu_patch_update.items);
    if (scene.menu_model == null or scene.menu_model.?.header.menu_generation != 2 or
        scene.menu_model.?.nodes.len != 3)
        return error.RuntimeBridgeMenuPatchInvalid;

    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var menu_patch_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .unicode_text => |text| {
                if (std.mem.eql(u8, text.bytes, "Files"))
                    menu_patch_rendered = true;
            },
            else => {},
        }
    }
    if (!menu_patch_rendered) return error.RuntimeBridgeMenuPatchNotRendered;

    var toolbar_fixture_items: [4]protocol.ToolbarItem = undefined;
    var toolbar_model = protocol.toolbarModelFixture(&toolbar_fixture_items);
    toolbar_model.header.frame_id = @intCast(bridge.frame.id);
    toolbar_model.header.frame_generation = bridge.eup_frame_generation;
    var toolbar_payload: std.ArrayList(u8) = .empty;
    defer toolbar_payload.deinit(gpa);
    try protocol.encodeToolbarModel(gpa, toolbar_model, &toolbar_payload);
    var toolbar_update: std.ArrayList(u8) = .empty;
    defer toolbar_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.toolbar_model,
        .sequence = 58,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, toolbar_payload.items, &toolbar_update);
    try scene.apply(toolbar_update.items);
    if (scene.toolbar == null or scene.toolbar.?.items.len != 4)
        return error.RuntimeBridgeToolbarInvalid;

    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    const toolbar_slot = (frontend.toolbarLayout(&scene) orelse
        return error.RuntimeBridgeToolbarNotRendered).slots[0];
    var toolbar_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == toolbar_slot.x and fill.rect.y == toolbar_slot.y and
                    fill.rect.width == toolbar_slot.width and fill.rect.height == toolbar_slot.height and
                    fill.color.r == 0x27 and fill.color.g == 0x2e and fill.color.b == 0x3b)
                    toolbar_rendered = true;
            },
            .unicode_text => |text| {
                if (text.x == toolbar_slot.x + 4 and std.mem.eql(u8, text.bytes, "Save"))
                    toolbar_rendered = toolbar_rendered and true;
            },
            else => {},
        }
    }
    if (!toolbar_rendered) return error.RuntimeBridgeToolbarNotRendered;

    var undo = protocol.ToolbarItem{ .item_id = 40, .kind = .button, .flags = protocol.ToolbarItemFlags.enabled | protocol.ToolbarItemFlags.visible, .label_len = 4 };
    @memcpy(undo.label[0..4], "Undo");
    var toolbar_patch_operations = [_]protocol.ToolbarPatchOperation{.{ .operation = .upsert, .item = undo }};
    var toolbar_patch_payload: std.ArrayList(u8) = .empty;
    defer toolbar_patch_payload.deinit(gpa);
    try protocol.encodeToolbarPatch(gpa, .{
        .frame_id = @intCast(bridge.frame.id),
        .frame_generation = bridge.eup_frame_generation,
        .toolbar_id = 9,
        .expected_generation = toolbar_model.header.toolbar_generation,
        .new_generation = toolbar_model.header.toolbar_generation + 1,
    }, &toolbar_patch_operations, &toolbar_patch_payload);
    var toolbar_patch_update: std.ArrayList(u8) = .empty;
    defer toolbar_patch_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.toolbar_patch,
        .sequence = 59,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, toolbar_patch_payload.items, &toolbar_patch_update);
    try scene.apply(toolbar_patch_update.items);
    if (scene.toolbar.?.header.toolbar_generation != toolbar_model.header.toolbar_generation + 1)
        return error.RuntimeBridgeToolbarPatchInvalid;

    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    const patched_slot = (frontend.toolbarLayout(&scene) orelse
        return error.RuntimeBridgeToolbarPatchNotRendered).slots[0];
    var toolbar_patch_rendered = false;
    var toolbar_old_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .unicode_text => |text| {
                if (text.x == patched_slot.x + 4 and std.mem.eql(u8, text.bytes, "Undo"))
                    toolbar_patch_rendered = true;
                if (std.mem.eql(u8, text.bytes, "Save"))
                    toolbar_old_rendered = true;
            },
            else => {},
        }
    }
    if (!toolbar_patch_rendered or toolbar_old_rendered)
        return error.RuntimeBridgeToolbarPatchNotRendered;

    var dialog_payload: std.ArrayList(u8) = .empty;
    defer dialog_payload.deinit(gpa);
    var dialog_title: [64]u8 = @splat(0);
    var dialog_text: [192]u8 = @splat(0);
    @memcpy(dialog_title[0..6], "Dialog");
    @memcpy(dialog_text[0..11], "Save buffer");
    try protocol.encodeDialogState(gpa, .{
        .kind = .message,
        .dialog_id = 80,
        .dialog_generation = 1,
        .window_id = 10,
        .frame_generation = bridge.eup_frame_generation,
        .x = 32,
        .y = 16,
        .width = 96,
        .height = 24,
        .title_len = 6,
        .text_len = 11,
        .buttons = protocol.DialogButtons.ok | protocol.DialogButtons.cancel,
        .title = dialog_title,
        .text = dialog_text,
    }, &dialog_payload);
    var dialog_update: std.ArrayList(u8) = .empty;
    defer dialog_update.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.dialog_open,
        .sequence = 60,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, dialog_payload.items, &dialog_update);
    try scene.apply(dialog_update.items);

    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var dialog_box_rendered = false;
    var dialog_title_rendered = false;
    var dialog_message_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 40 and fill.rect.y == 24 and
                    fill.rect.width == 96 and fill.rect.height == 24 and
                    fill.color.r == 0x20 and fill.color.g == 0x24 and fill.color.b == 0x2c)
                    dialog_box_rendered = true;
            },
            .unicode_text => |text| {
                if (text.x == 44 and std.mem.eql(u8, text.bytes, "Dialog"))
                    dialog_title_rendered = true;
                if (text.x == 44 and std.mem.eql(u8, text.bytes, "Save buffer"))
                    dialog_message_rendered = true;
            },
            else => {},
        }
    }
    if (!dialog_box_rendered or !dialog_title_rendered or !dialog_message_rendered)
        return error.RuntimeBridgeDialogNotRendered;

    dialog_payload.clearRetainingCapacity();
    @memcpy(dialog_title[0..6], "Dialog");
    @memcpy(dialog_text[0..11], "Buffer done");
    try protocol.encodeDialogState(gpa, .{
        .kind = .message,
        .dialog_id = 80,
        .dialog_generation = 2,
        .window_id = 10,
        .frame_generation = bridge.eup_frame_generation,
        .x = 40,
        .y = 16,
        .width = 96,
        .height = 24,
        .title_len = 6,
        .text_len = 11,
        .buttons = protocol.DialogButtons.ok | protocol.DialogButtons.cancel,
        .title = dialog_title,
        .text = dialog_text,
    }, &dialog_payload);
    dialog_update.clearRetainingCapacity();
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.dialog_update,
        .sequence = 61,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, dialog_payload.items, &dialog_update);
    try scene.apply(dialog_update.items);
    if (scene.dialog.?.x != 40 or !std.mem.eql(u8, scene.dialog.?.text[0..11], "Buffer done"))
        return error.RuntimeBridgeDialogUpdateInvalid;

    var dialog_close_payload: std.ArrayList(u8) = .empty;
    defer dialog_close_payload.deinit(gpa);
    try protocol.encodeDialogClose(gpa, .{
        .reason = .escape,
        .dialog_id = 80,
        .dialog_generation = 2,
        .window_id = 10,
        .frame_generation = bridge.eup_frame_generation,
    }, &dialog_close_payload);
    dialog_update.clearRetainingCapacity();
    try protocol.encodeEnvelope(gpa, .{
        .flags = 0,
        .message_type = protocol.Message.dialog_close,
        .sequence = 62,
        .ack_sequence = 0,
        .session_id = capability.session_id,
        .frame_id = @intCast(bridge.frame.id),
        .timestamp_ns = 1,
    }, dialog_close_payload.items, &dialog_update);
    try scene.apply(dialog_update.items);
    if (scene.dialog != null) return error.RuntimeBridgeDialogCloseInvalid;

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
        &atlas_texture_cache,
    );
    if (frame_counters.explicit_damage_frames != 1 or
        frame_counters.explicit_clipped_frames != 1 or
        frame_counters.explicit_full_fallback_frames != 0 or
        frame_counters.explicit_skipped_commands == 0 or
        frame_counters.explicit_submitted_commands == 0)
        return error.RuntimeBridgeExplicitPresentInvalid;
    if (frame_counters.atlas_glyphs_total < 5)
        return error.RuntimeBridgeAtlasRenderInvalid;
    if (atlas_texture_cache.uploads != 1 or atlas_texture_cache.hits < 4)
        return error.RuntimeBridgeAtlasCacheInvalid;

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
            if (event.type == SDL_EVENT_RENDER_TARGETS_RESET or
                event.type == SDL_EVENT_RENDER_DEVICE_RESET or
                event.type == SDL_EVENT_RENDER_DEVICE_LOST)
            {
                unicode_text_renderer.clearTextures();
                atlas_texture_cache.clear();
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
        _ = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters, null);
        SDL_Delay(10);
    }
    if (!delivered_key or !delivered_text or
        frame_counters.text_commands_total + frame_counters.unicode_text_commands_total == 0)
    {
        return error.RuntimeBridgeNotRendered;
    }
    const mode_sequence = scene.next_sequence.?;
    const mode_frame_id: u32 = scene.frame.?.frame_id;
    var mode_windows: std.ArrayList(u8) = .empty;
    defer mode_windows.deinit(gpa);
    var mode_rows: std.ArrayList(u8) = .empty;
    defer mode_rows.deinit(gpa);
    var mode_records: std.ArrayList(u8) = .empty;
    defer mode_records.deinit(gpa);
    var aux_records: std.ArrayList(u8) = .empty;
    defer aux_records.deinit(gpa);
    var mode_damage: std.ArrayList(u8) = .empty;
    defer mode_damage.deinit(gpa);
    try frontend.encodeWindow(gpa, .{ .id = 10, .frame_id = mode_frame_id, .x = 8, .y = 8, .width = 200, .height = 40 }, &mode_windows);
    try frontend.encodeRow(gpa, .{ .window_id = 10, .index = 0, .flags = 0, .x = 4, .y = 4, .width = 192, .height = 24, .ascent = 8, .descent = 2, .baseline = 8, .visible_height = 24 }, &mode_rows);
    try frontend.encodeModeLineV1(gpa, .{ .window_id = 10, .x = 0, .y = 24, .width = 200, .height = 16, .flags = frontend.mode_line_active, .line = "Mode" }, &mode_records);
    try frontend.encodeWindowAuxLineV1(gpa, .{ .window_id = 10, .x = 0, .y = 0, .width = 200, .height = 16, .flags = frontend.aux_line_header, .line = "Header" }, &aux_records);
    try frontend.encodeWindowAuxLineV1(gpa, .{ .window_id = 10, .x = 0, .y = 16, .width = 200, .height = 16, .flags = frontend.aux_line_tab, .line = "Tab" }, &aux_records);
    try frontend.encodeRect(gpa, .{ .x = 0, .y = 0, .width = 240, .height = 96 }, &mode_damage);
    const mode_sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = mode_windows.items },
        .{ .kind = protocol.SectionKind.rows, .records = mode_rows.items },
        .{ .kind = protocol.SectionKind.extension_min + 3, .records = mode_records.items },
        .{ .kind = protocol.SectionKind.extension_min + 4, .records = aux_records.items },
        .{ .kind = protocol.SectionKind.damage, .records = mode_damage.items },
    };
    var mode_payload: std.ArrayList(u8) = .empty;
    defer mode_payload.deinit(gpa);
    try protocol.encodeFrameUpdate(gpa, .{ .header = .{
        .frame_id = mode_frame_id,
        .frame_generation = scene.frame.?.generation,
        .sequence = mode_sequence,
        .redisplay_generation = scene.stats.frame_updates + 1,
        .logical_x = 0,
        .logical_y = 0,
        .logical_width = 240,
        .logical_height = 96,
        .physical_x = 0,
        .physical_y = 0,
        .physical_width = 240,
        .physical_height = 96,
        .scale = 1,
        .dpi_x = 96,
        .dpi_y = 96,
        .damage_mode = 2,
        .update_cause = 1,
        .coalesced_count = 0,
        .timestamp_ns = mode_sequence,
    }, .sections = &mode_sections }, &mode_payload);
    var mode_message: std.ArrayList(u8) = .empty;
    defer mode_message.deinit(gpa);
    try protocol.encodeEnvelope(gpa, .{ .flags = protocol.Flags.delta, .message_type = protocol.Message.frame_update, .sequence = mode_sequence, .ack_sequence = 0, .session_id = capability.session_id, .frame_id = mode_frame_id, .timestamp_ns = mode_sequence }, mode_payload.items, &mode_message);
    try scene.apply(mode_message.items);
    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var mode_line_rendered = false;
    var mode_bar_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 8 and fill.rect.y == 32 and
                    fill.rect.width == 200 and fill.rect.height == 16)
                    mode_bar_rendered = true;
            },
            .text => |mode_text| {
                if (std.mem.eql(u8, mode_text.bytes, "Mode"))
                    mode_line_rendered = true;
            },
            .unicode_text => |mode_text| {
                if (std.mem.eql(u8, mode_text.bytes, "Mode"))
                    mode_line_rendered = true;
            },
            else => {},
        }
    }
    var header_text_rendered = false;
    var tab_text_rendered = false;
    var header_bar_rendered = false;
    var tab_bar_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 8 and fill.rect.y == 8 and fill.rect.width == 200 and fill.rect.height == 16)
                    header_bar_rendered = true;
                if (fill.rect.x == 8 and fill.rect.y == 24 and fill.rect.width == 200 and fill.rect.height == 16)
                    tab_bar_rendered = true;
            },
            .text => |line_text| {
                if (std.mem.eql(u8, line_text.bytes, "Header"))
                    header_text_rendered = true;
                if (std.mem.eql(u8, line_text.bytes, "Tab"))
                    tab_text_rendered = true;
            },
            .unicode_text => |line_text| {
                if (std.mem.eql(u8, line_text.bytes, "Header"))
                    header_text_rendered = true;
                if (std.mem.eql(u8, line_text.bytes, "Tab"))
                    tab_text_rendered = true;
            },
            else => {},
        }
    }
    if (!header_bar_rendered or !header_text_rendered or !tab_bar_rendered or !tab_text_rendered or
        scene.aux_line_count != 2)
        return error.WindowLineRenderFailed;
    if (!mode_bar_rendered or !mode_line_rendered or scene.mode_line_count != 1)
        return error.ModeLineRenderFailed;

    // A focused focused-context IME fixture proves the preedit state reaches
    // the draw list, while Unicode preedit remains state-only in this renderer.
    var ime_payload: std.ArrayList(u8) = .empty;
    defer ime_payload.deinit(gpa);
    const ime_sequence = scene.next_sequence.?;
    const ime_frame: u32 = scene.frame.?.frame_id;
    try frontend.encodeImeAttach(gpa, .{ .context_id = 11, .window_id = 10 }, &ime_payload);
    try applyRuntimeSceneMessage(gpa, &scene, protocol.Message.ime_attach, ime_sequence, capability.session_id, ime_frame, ime_payload.items);
    ime_payload.clearRetainingCapacity();
    try frontend.encodeImeFocus(gpa, .{ .context_id = 11, .window_id = 10, .focused = true }, &ime_payload);
    try applyRuntimeSceneMessage(gpa, &scene, protocol.Message.ime_focus, ime_sequence + 1, capability.session_id, ime_frame, ime_payload.items);
    ime_payload.clearRetainingCapacity();
    try frontend.encodeImeCursorRect(gpa, .{ .context_id = 11, .window_id = 10, .x = 20, .y = 0, .width = 4, .height = 12 }, &ime_payload);
    try applyRuntimeSceneMessage(gpa, &scene, protocol.Message.ime_cursor_rect, ime_sequence + 2, capability.session_id, ime_frame, ime_payload.items);
    ime_payload.clearRetainingCapacity();
    try frontend.encodeImePreeditStart(gpa, 11, &ime_payload);
    try applyRuntimeSceneMessage(gpa, &scene, protocol.Message.ime_preedit_start, ime_sequence + 3, capability.session_id, ime_frame, ime_payload.items);
    ime_payload.clearRetainingCapacity();
    try frontend.encodeImePreeditUpdate(gpa, .{ .context_id = 11, .cursor_offset = 3, .selected_length = 1, .bytes = "abc" }, &ime_payload);
    try applyRuntimeSceneMessage(gpa, &scene, protocol.Message.ime_preedit_update, ime_sequence + 4, capability.session_id, ime_frame, ime_payload.items);

    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var preedit_box_rendered = false;
    var preedit_text_rendered = false;
    var preedit_text_position_rendered = false;
    var preedit_top_border_rendered = false;
    var preedit_bottom_border_rendered = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 28 and fill.rect.y == 8 and
                    fill.rect.width == 72 and fill.rect.height == 16 and
                    fill.color.r == 0x20 and fill.color.g == 0x28 and
                    fill.color.b == 0x38 and fill.color.a == 255)
                    preedit_box_rendered = true;
                if (fill.rect.x == 28 and fill.rect.y == 8 and
                    fill.rect.width == 72 and fill.rect.height == 1 and
                    fill.color.r == 0x71 and fill.color.g == 0xa6 and
                    fill.color.b == 0xf2 and fill.color.a == 255)
                    preedit_top_border_rendered = true;
                if (fill.rect.x == 28 and fill.rect.y == 23 and
                    fill.rect.width == 72 and fill.rect.height == 1 and
                    fill.color.r == 0x71 and fill.color.g == 0xa6 and
                    fill.color.b == 0xf2 and fill.color.a == 255)
                    preedit_bottom_border_rendered = true;
            },
            .unicode_text => |preedit_text| {
                if (preedit_text.x == 32 and std.mem.eql(u8, preedit_text.bytes, "abc"))
                    preedit_text_rendered = true;
                if (preedit_text.x == 32 and
                    preedit_text.color.r == 0xff and preedit_text.color.g == 0xd5 and
                    preedit_text.color.b == 0x4d and preedit_text.color.a == 255)
                    preedit_text_position_rendered = true;
            },
            else => {},
        }
    }
    if (!preedit_box_rendered or !preedit_text_rendered or
        !preedit_top_border_rendered or !preedit_bottom_border_rendered)
        return error.ImePreeditNotRendered;
    if (!preedit_text_position_rendered)
        return error.ImePreeditTextIncomplete;

    ime_payload.clearRetainingCapacity();
    try frontend.encodeImePreeditEnd(gpa, 11, &ime_payload);
    try applyRuntimeSceneMessage(gpa, &scene, protocol.Message.ime_preedit_end, ime_sequence + 5, capability.session_id, ime_frame, ime_payload.items);
    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var stale_preedit_overlay = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 28 and fill.rect.y == 8 and
                    fill.rect.width == 72 and
                    ((fill.rect.height == 16 and fill.color.r == 0x20 and
                        fill.color.g == 0x28 and fill.color.b == 0x38 and fill.color.a == 255) or
                        (fill.rect.height == 1 and fill.color.r == 0x71 and
                            fill.color.g == 0xa6 and fill.color.b == 0xf2 and fill.color.a == 255)))
                    stale_preedit_overlay = true;
            },
            .text => |preedit_text| {
                if (preedit_text.x == 32 and preedit_text.y == 11 and
                    preedit_text.color != null and
                    preedit_text.color.?.r == 0xff and preedit_text.color.?.g == 0xd5 and
                    preedit_text.color.?.b == 0x4d and preedit_text.color.?.a == 255)
                    return error.ImePreeditClearFailed;
            },
            else => {},
        }
    }
    if (stale_preedit_overlay) return error.ImePreeditClearFailed;

    ime_payload.clearRetainingCapacity();
    try frontend.encodeImePreeditStart(gpa, 11, &ime_payload);
    try applyRuntimeSceneMessage(gpa, &scene, protocol.Message.ime_preedit_start, ime_sequence + 6, capability.session_id, ime_frame, ime_payload.items);
    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var empty_preedit_overlay = false;
    var empty_preedit_text = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 28 and fill.rect.y == 8 and
                    fill.rect.width == 72 and fill.rect.height == 16)
                    empty_preedit_overlay = true;
            },
            .text => |preedit_text| {
                if (preedit_text.x == 32 and preedit_text.y == 11)
                    empty_preedit_text = true;
            },
            else => {},
        }
    }
    if (!empty_preedit_overlay or empty_preedit_text)
        return error.ImePreeditEmptyTextInvalid;

    ime_payload.clearRetainingCapacity();
    try frontend.encodeImePreeditUpdate(gpa, .{ .context_id = 11, .cursor_offset = 3, .selected_length = 0, .bytes = "汉" }, &ime_payload);
    try applyRuntimeSceneMessage(gpa, &scene, protocol.Message.ime_preedit_update, ime_sequence + 7, capability.session_id, ime_frame, ime_payload.items);
    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    for (draw_list.commands.items) |command| {
        switch (command) {
            .text => |preedit_text| {
                if (preedit_text.x == 32 and preedit_text.y == 11)
                    return error.ImePreeditUnicodeTextRendered;
            },
            else => {},
        }
    }
    ime_payload.clearRetainingCapacity();
    try frontend.encodeImeCandidateUpdate(gpa, .{
        .context_id = 11,
        .selected_index = 1,
        .candidate_count = 3,
        .page_index = 0,
        .page_count = 2,
        .cursor_x = 16,
        .cursor_y = 16,
        .cursor_width = 60,
        .cursor_height = 16,
        .selected_label = "abc",
    }, &ime_payload);
    try applyRuntimeSceneMessage(gpa, &scene, protocol.Message.ime_candidate_update, ime_sequence + 8, capability.session_id, ime_frame, ime_payload.items);

    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var candidate_box = false;
    var candidate_top = false;
    var candidate_bottom = false;
    var candidate_metadata = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 24 and fill.rect.y == 24 and
                    fill.rect.width == 120 and fill.rect.height == 16 and
                    fill.color.r == 0x20 and fill.color.g == 0x24 and
                    fill.color.b == 0x2c and fill.color.a == 255)
                    candidate_box = true;
                if (fill.rect.x == 24 and fill.rect.y == 24 and
                    fill.rect.width == 120 and fill.rect.height == 1 and
                    fill.color.r == 0x71 and fill.color.g == 0xa6 and
                    fill.color.b == 0xf2 and fill.color.a == 255)
                    candidate_top = true;
                if (fill.rect.x == 24 and fill.rect.y == 39 and
                    fill.rect.width == 120 and fill.rect.height == 1 and
                    fill.color.r == 0x71 and fill.color.g == 0xa6 and
                    fill.color.b == 0xf2 and fill.color.a == 255)
                    candidate_bottom = true;
            },
            .unicode_text => |candidate_text| {
                if (candidate_text.x == 28 and
                    candidate_text.color.r == 0xff and candidate_text.color.g == 0xd5 and
                    candidate_text.color.b == 0x4d and candidate_text.color.a == 255 and
                    std.mem.eql(u8, candidate_text.bytes, "C 2/3 P 1/2 abc"))
                    candidate_metadata = true;
            },
            else => {},
        }
    }
    if (!candidate_box or !candidate_top or !candidate_bottom or !candidate_metadata)
        return error.ImeCandidateNotRendered;

    ime_payload.clearRetainingCapacity();
    try frontend.encodeImeCandidateUpdate(gpa, .{
        .context_id = 11,
        .selected_index = 1,
        .candidate_count = 3,
        .page_index = 0,
        .page_count = 2,
        .cursor_x = 16,
        .cursor_y = 16,
        .cursor_width = 60,
        .cursor_height = 16,
        .selected_label = "乙",
    }, &ime_payload);
    try applyRuntimeSceneMessage(gpa, &scene, protocol.Message.ime_candidate_update, ime_sequence + 9, capability.session_id, ime_frame, ime_payload.items);
    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var unicode_candidate_metadata = false;
    var unicode_candidate_label = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .unicode_text => |candidate_text| {
                if (candidate_text.x != 28) continue;
                if (std.mem.eql(u8, candidate_text.bytes, "C 2/3 P 1/2"))
                    unicode_candidate_metadata = true;
                if (std.mem.eql(u8, candidate_text.bytes, "乙"))
                    unicode_candidate_label = true;
            },
            else => {},
        }
    }
    if (!unicode_candidate_metadata or unicode_candidate_label)
        return error.ImeCandidateUnicodeTextRendered;

    ime_payload.clearRetainingCapacity();
    try frontend.encodeImeCancel(gpa, 11, &ime_payload);
    try applyRuntimeSceneMessage(gpa, &scene, protocol.Message.ime_cancel, ime_sequence + 10, capability.session_id, ime_frame, ime_payload.items);
    try buildSceneDrawList(&scene, &draw_list, 240, 96);
    var stale_candidate_overlay = false;
    for (draw_list.commands.items) |command| {
        switch (command) {
            .fill => |fill| {
                if (fill.rect.x == 28 and fill.rect.y == 24 and
                    fill.rect.width == 120 and
                    ((fill.rect.height == 16 and fill.color.r == 0x20 and
                        fill.color.g == 0x24 and fill.color.b == 0x2c and fill.color.a == 255) or
                        (fill.rect.height == 1 and fill.color.r == 0x71 and
                            fill.color.g == 0xa6 and fill.color.b == 0xf2 and fill.color.a == 255)))
                    stale_candidate_overlay = true;
            },
            else => {},
        }
    }
    if (stale_candidate_overlay) return error.ImeCandidateClearFailed;
    std.debug.print(
        "sdl3-runtime-bridge-smoke: {{\"kind\":\"sdl3-runtime-bridge-smoke\",\"runs\":1,\"text\":\"Emacs\",\"title_applied\":true,\"session_suspend_resume\":true,\"present_feedback_codec\":true,\"geometry_scene_applied\":true,\"border_query\":{},\"icon_applied\":{},\"size_hints_applied\":{},\"z_order_applied\":{},\"parent_unparented\":{},\"cursor_update_rendered\":{},\"damage_rects\":{},\"scroll_run_plan\":{},\"scroll_copy_executed\":{},\"scroll_copy_bytes\":{},\"border_style\":{},\"divider_update\":{},\"fringe_update\":{},\"scrollbar_state\":{},\"font_patch\":true,\"fringe_bitmap\":true,\"tooltip\":true,\"menu_model\":true,\"menu_open\":true,\"frame_patch\":true,\"frame_snapshot\":true,\"menu_patch\":true,\"toolbar_model\":true,\"toolbar_patch\":true,\"dialog\":true,\"window_face\":{},\"window_geometry\":{},\"window_zones\":{},\"window_position\":true,\"mouse_highlight\":{},\"flush_boundary\":{},\"render_hint_applied\":{},\"opacity_supported\":{},\"decorations_supported\":{},\"scale_supported\":{},\"platform_scale_milli\":{},\"fullscreen_supported\":{},\"monitor_supported\":{},\"platform_monitor_id\":{},\"platform_monitor_width\":{},\"platform_monitor_height\":{},\"maximize_supported\":{},\"explicit_submitted_commands\":{},\"explicit_skipped_commands\":{},\"inputs\":2,\"rendered\":true,\"emacs_registered\":false,\"result\":\"pass\"}}\n",
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
            window_face_background_rendered,
            window_geometry_rendered,
            window_zones_rendered,
            mouse_highlight_rendered,
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
    std.debug.print("sdl3-runtime-bridge-smoke: mode_line_rendered={any} count={d} aux_line_rendered={any} aux_count={d}\n", .{ mode_line_rendered, scene.mode_line_count, header_text_rendered and tab_text_rendered, scene.aux_line_count });
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

fn recoverLiveScene(
    gpa: std.mem.Allocator,
    io: std.Io,
    reader: anytype,
    writer: anytype,
    scene: *frontend.Scene,
    delivery: *input_policy.DeliveryJournal,
    capabilities: capability.Set,
    config: *const Config,
    input_ack_lost: *bool,
    scrollbar_event_delivered: *bool,
) !void {
    _ = io;
    const wire_writer = @constCast(&writer.interface);
    try live.writeControl(wire_writer, .{ .kind = .resync_request, .sequence = 1 });
    try wire_writer.flush();
    var began = false;
    var recovered_snapshot = false;
    while (true) {
        const inbound = try readInbound(reader, gpa);
        switch (inbound) {
            .control => |control| {
                if (control.kind == .resync_begin) {
                    if (began or control.sequence != 1) return error.InvalidResyncRequest;
                    scene.resetForResync();
                    began = true;
                    recovered_snapshot = false;
                    continue;
                }
                if (control.kind == .resync_complete) {
                    const next_sequence = scene.next_sequence orelse return error.InvalidSequence;
                    if (!began or !recovered_snapshot or
                        control.sequence != next_sequence - 1) return error.InvalidSequence;
                    return;
                }
                return error.ExpectedResyncControl;
            },
            .frame => |message| {
                defer gpa.free(message);
                if (!began) return error.ExpectedResyncBegin;
                const envelope = try protocol.decodeEnvelope(message);
                try scene.apply(message);
                recovered_snapshot = true;
                if (envelope.envelope.message_type == protocol.Message.frame_update) {
                    try deliveryAllowed(delivery, capabilities);
                    const outcome = try sendDeliveryEvent(gpa, delivery, config, writer, reader, envelope.envelope);
                    if (outcome == .ack_lost) input_ack_lost.* = true;
                    if (outcome == .delivered) {
                        switch (outcome.delivered.event) {
                            .scrollbar_event => scrollbar_event_delivered.* = true,
                            else => {},
                        }
                    }
                }
                try live.writeControl(wire_writer, .{ .kind = .ack, .sequence = envelope.envelope.sequence });
                try wire_writer.flush();
            },
        }
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
    emacs_key_command_translator.reset();

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
    if (config.force_frontend_failure) return error.FrontendFailureRequested;
    var scrollbar_event_delivered = false;
    if (config.mode == .live) {
        if (!negotiated.effective.contains(.window_scrollbar_event_v1))
            return error.ScrollbarEventCapabilityNotNegotiated;
        try delivery.pushScrollbarEvent(.{
            .kind = .absolute,
            .axis = .vertical,
            .window_id = 10,
            .position = 40,
            .delta = 0,
            .frame_generation = 1,
        });
    }

    if (config.mode == .emacs_epxl_unicode_input) {
        if (!negotiated.effective.contains(.input_text_ascii) or
            !negotiated.effective.contains(.input_text_unicode) or
            !negotiated.effective.contains(.render_unicode_text_v1))
            return error.TextCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-epxl-unicode-input-smoke: {{\"kind\":\"sdl3-epxl-unicode-input-smoke\",\"negotiated\":{{\"input.text_ascii\":true,\"input.text_unicode\":true,\"render.unicode_text_v1\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
    }

    if (config.mode == .emacs_epxl_key_v2) {
        if (!negotiated.effective.contains(.input_key_bounded) or
            !negotiated.effective.contains(.input_key_full_v2) or
            !negotiated.effective.contains(.input_key_command_v1))
            return error.FullKeyCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-epxl-key-v2-smoke: {{\"kind\":\"sdl3-epxl-key-v2-smoke\",\"negotiated\":{{\"input.key_bounded\":true,\"input.key_full_v2\":true,\"input.key_command_v1\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
        try delivery.pushKeyV2(input_policy.translateFullKey(4, "a", true, false, input_policy.sdl_kmod_lctrl, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(8, "e", true, false, input_policy.sdl_kmod_lctrl, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(60, "F5", true, false, 0, 0).?);
    }

    if (config.mode == .emacs_epxl_key_modifier) {
        if (!negotiated.effective.contains(.input_key_bounded) or
            !negotiated.effective.contains(.input_key_full_v2) or
            !negotiated.effective.contains(.input_key_command_v1))
            return error.FullKeyCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-key-modifier-smoke: {{\"kind\":\"sdl3-key-modifier-smoke\",\"negotiated\":{{\"input.key_bounded\":true,\"input.key_full_v2\":true,\"input.key_command_v1\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
        try delivery.pushKeyV2(input_policy.translateFullKey(9, "f", true, false, input_policy.sdl_kmod_lctrl, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(9, "f", true, false, input_policy.sdl_kmod_lalt, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(5, "b", true, false, input_policy.sdl_kmod_lctrl, 0).?);
    }

    if (config.mode == .emacs_window_split) {
        if (!negotiated.effective.contains(.input_key_bounded) or
            !negotiated.effective.contains(.input_key_full_v2) or
            !negotiated.effective.contains(.input_key_command_v1) or
            !negotiated.effective.contains(.input_composite_key_command_v1))
            return error.CompositeCommandCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-emacs-window-split-smoke: {{\"kind\":\"sdl3-emacs-window-split-smoke\",\"negotiated\":{{\"input.key_command_v1\":true,\"input.composite_key_command_v1\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
        emacs_key_command_translator.reset();
        try delivery.pushKeyV2(input_policy.translateFullKey(27, "x", true, false, input_policy.sdl_kmod_lctrl, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(31, "2", true, false, 0, 0).?);
    }

    if (config.mode == .emacs_window_navigation) {
        if (!negotiated.effective.contains(.input_key_bounded) or
            !negotiated.effective.contains(.input_text_ascii) or
            !negotiated.effective.contains(.input_key_full_v2) or
            !negotiated.effective.contains(.input_key_command_v1) or
            !negotiated.effective.contains(.input_composite_key_command_v1))
            return error.CompositeCommandCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-emacs-window-navigation-smoke: {{\"kind\":\"sdl3-emacs-window-navigation-smoke\",\"negotiated\":{{\"input.key_bounded\":true,\"input.text_ascii\":true,\"input.key_full_v2\":true,\"input.key_command_v1\":true,\"input.composite_key_command_v1\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
        emacs_key_command_translator.reset();
        try delivery.pushKeyV2(input_policy.translateFullKey(27, "x", true, false, input_policy.sdl_kmod_lctrl, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(32, "3", true, false, 0, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(27, "x", true, false, input_policy.sdl_kmod_lctrl, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(18, "o", true, false, 0, 0).?);
        try delivery.pushText("Z");
    }

    if (config.mode == .emacs_epxl_bench) {
        if (!negotiated.effective.contains(.input_key_bounded) or
            !negotiated.effective.contains(.input_text_ascii))
            return error.TextEditBenchmarkCapabilityNotNegotiated;
    }

    if (config.mode == .emacs_window_restore) {
        if (!negotiated.effective.contains(.input_key_bounded) or
            !negotiated.effective.contains(.input_text_ascii) or
            !negotiated.effective.contains(.input_key_full_v2) or
            !negotiated.effective.contains(.input_key_command_v1) or
            !negotiated.effective.contains(.input_composite_key_command_v1))
            return error.CompositeCommandCapabilityNotNegotiated;
        emacs_key_command_translator.reset();
        std.debug.print(
            "sdl3-emacs-window-restore-smoke: {{\"kind\":\"sdl3-emacs-window-restore-smoke\",\"negotiated\":{{\"input.key_bounded\":true,\"input.text_ascii\":true,\"input.key_full_v2\":true,\"input.key_command_v1\":true,\"input.composite_key_command_v1\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
        window_restore_edited_split_observed = false;
        try delivery.pushKeyV2(input_policy.translateFullKey(27, "x", true, false, input_policy.sdl_kmod_lctrl, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(32, "3", true, false, 0, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(27, "x", true, false, input_policy.sdl_kmod_lctrl, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(18, "o", true, false, 0, 0).?);
        try delivery.pushText("Z");
    }

    if (config.mode == .emacs_window_pointer_select) {
        if (!negotiated.effective.contains(.input_key_bounded) or
            !negotiated.effective.contains(.input_text_ascii) or
            !negotiated.effective.contains(.input_key_full_v2) or
            !negotiated.effective.contains(.input_key_command_v1) or
            !negotiated.effective.contains(.input_composite_key_command_v1) or
            !negotiated.effective.contains(.input_pointer_v2))
            return error.PointerWindowSelectCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-emacs-window-pointer-select-smoke: {{\"kind\":\"sdl3-emacs-window-pointer-select-smoke\",\"negotiated\":{{\"input.text_ascii\":true,\"input.key_command_v1\":true,\"input.composite_key_command_v1\":true,\"input.pointer_v2\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
        emacs_key_command_translator.reset();
        try delivery.pushKeyV2(input_policy.translateFullKey(27, "x", true, false, input_policy.sdl_kmod_lctrl, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(32, "3", true, false, 0, 0).?);
        try delivery.pushPointerV2(.{
            .phase = .press,
            .buttons = input_policy.pointer_button_left,
            .x = 60,
            .y = 10,
            .clicks = 1,
            .modifiers = 0,
        });
        try delivery.pushPointerV2(.{
            .phase = .release,
            .buttons = input_policy.pointer_button_left,
            .x = 60,
            .y = 10,
            .clicks = 1,
            .modifiers = 0,
        });
        try delivery.pushText("Z");
    }

    reserveFrontendInputSequence(delivery);

    const use_resync = config.mode == .emacs_epxl or config.mode == .emacs_epxl_reconnect or
        config.mode == .emacs_epxl_recovery or config.mode == .emacs_epxl_gap or config.mode == .emacs_epxl_input or
        config.mode == .emacs_epxl_unicode_input or config.mode == .emacs_epxl_edit or
        config.mode == .emacs_epxl_key_v2 or config.mode == .emacs_epxl_key_modifier or
        config.mode == .emacs_epxl_bench or
        config.mode == .emacs_window_split or config.mode == .emacs_window_navigation or
        config.mode == .emacs_window_restore or config.mode == .emacs_window_pointer_select or
        config.mode == .emacs_epxl_sequence;
    var scene = frontend.Scene.init(gpa);
    errdefer scene.deinit();
    var restore_restore_queued = false;
    var frontend_sequence: u64 = frontend_pong_sequence_start;
    var resync_complete = false;
    var input_ack_lost = false;
    if (use_resync) {
        try recoverLiveScene(
            gpa,
            io,
            &reader,
            &writer,
            &scene,
            delivery,
            negotiated.effective,
            config,
            &input_ack_lost,
            &scrollbar_event_delivered,
        );
        resync_complete = true;
    }
    const benchmark = config.mode == .emacs_epxl_bench;
    const bench_total: usize = @as(usize, config.benchmark_warmup) + config.benchmark_iterations;
    var bench_ack_samples: []u64 = &.{};
    var bench_update_samples: []u64 = &.{};
    var bench_owns_samples = false;
    defer if (bench_owns_samples) {
        gpa.free(bench_ack_samples);
        gpa.free(bench_update_samples);
    };
    if (benchmark) {
        bench_ack_samples = try gpa.alloc(u64, config.benchmark_iterations);
        errdefer gpa.free(bench_ack_samples);
        bench_update_samples = try gpa.alloc(u64, config.benchmark_iterations);
        bench_owns_samples = true;
        @memset(bench_ack_samples, 0);
        @memset(bench_update_samples, 0);
    }
    var bench_sent: usize = 0;
    var bench_samples: usize = 0;
    // ponytail: strictly one intent in flight, so this measures round-trip
    // latency, not throughput. Pipeline the journal if throughput matters.
    var bench_submit_ticks: u64 = 0;
    var bench_receipt_ticks: u64 = 0;
    var bench_awaiting_update = false;
    var bench_reported = false;
    var bench_next_intent: usize = 0;
    // Move the point off point-min first so the alternating backspace/insert
    // pair always edits a real character; the visible-edit publisher applies
    // both at window point, so every step changes a fact.
    const bench_setup_intents: usize = 7;
    if (benchmark) {
        while (bench_next_intent < bench_setup_intents + bench_total and
            delivery.queue.length < input_policy.queue_capacity)
        {
            if (bench_next_intent < bench_setup_intents) {
                try delivery.pushKey(.{ .action = .cursor_right });
            } else if ((bench_next_intent - bench_setup_intents) % 2 == 0) {
                try delivery.pushKey(.{ .action = .backspace });
            } else {
                try delivery.pushText("x");
            }
            bench_next_intent += 1;
        }
    }
    while (true) {
        const message = (live.readFrame(&reader.interface, gpa) catch |err| {
            // A publisher closes cleanly after its final fact stream. A
            // peer reset at this boundary is session completion, not scene loss.
            if (resync_complete) break;
            return err;
        }) orelse break;
        if (benchmark) bench_receipt_ticks = SDL_GetPerformanceCounter();
        defer gpa.free(message);
        const envelope = (try protocol.decodeEnvelope(message)).envelope;
        scene.apply(message) catch |err| {
            if (err != frontend.Error.InvalidSequence or !scene.recovery_requested)
                return err;
            try recoverLiveScene(
                gpa,
                io,
                &reader,
                &writer,
                &scene,
                delivery,
                negotiated.effective,
                config,
                &input_ack_lost,
                &scrollbar_event_delivered,
            );
            continue;
        };
        if (config.mode == .emacs_window_restore) {
            var left: ?frontend.Window = null;
            var right: ?frontend.Window = null;
            for (scene.windows.items) |window| {
                if (window.x == 0) {
                    if (left == null) left = window;
                } else if (window.x > 0) {
                    if (right == null) right = window;
                }
            }
            if (scene.windows.items.len == 2 and left != null and right != null) {
                const left_window = left.?;
                const right_window = right.?;
                const cursor = scene.cursor;
                window_restore_edited_split_observed = left_window.width > 0 and
                    right_window.width > 0 and left_window.y == right_window.y and
                    left_window.height == right_window.height and cursor != null and
                    cursor.?.active and cursor.?.window_id == right_window.id and
                    cursor.?.x <= 16 and cursor.?.y == 0 and
                    sceneWindowTextStartsWith(&scene, right_window.id, "Z");
                if (window_restore_edited_split_observed and !restore_restore_queued and
                    delivery.pending == null and delivery.queue.length == 0)
                {
                    restore_restore_queued = true;
                    try delivery.pushKeyV2(input_policy.translateFullKey(27, "x", true, false, input_policy.sdl_kmod_lctrl, 0).?);
                    try delivery.pushKeyV2(input_policy.translateFullKey(30, "1", true, false, 0, 0).?);
                }
            }
        }
        if (envelope.message_type == protocol.Message.frame_update) {
            if (benchmark and bench_awaiting_update) {
                const sample_index = bench_samples - 1;
                bench_update_samples[sample_index] =
                    performanceTicksToNanos(bench_receipt_ticks - bench_submit_ticks);
                bench_awaiting_update = false;
            }
            try deliveryAllowed(delivery, negotiated.effective);
            if (benchmark) bench_submit_ticks = SDL_GetPerformanceCounter();
            const outcome = try sendDeliveryEvent(gpa, delivery, config, &writer, &reader, envelope);
            if (outcome == .delivered) {
                if (benchmark) {
                    const operation_matches = if (bench_sent < bench_setup_intents)
                        switch (outcome.delivered.event) {
                            .key => |key| key.action == .cursor_right,
                            else => false,
                        }
                    else blk: {
                        const expected_backspace =
                            (bench_sent - bench_setup_intents) % 2 == 0;
                        break :blk switch (outcome.delivered.event) {
                            .key => |key| expected_backspace and key.action == .backspace,
                            .text => |text| !expected_backspace and std.mem.eql(u8, text.bytes(), "x"),
                            else => false,
                        };
                    };
                    if (!operation_matches) return error.EpxlBenchmarkOperationMismatch;
                    const submit_ticks = bench_submit_ticks;
                    const ack_ticks = SDL_GetPerformanceCounter();
                    if (bench_sent >= bench_setup_intents) {
                        const operation_index = bench_sent - bench_setup_intents;
                        if (operation_index >= config.benchmark_warmup) {
                            bench_ack_samples[bench_samples] =
                                performanceTicksToNanos(ack_ticks - submit_ticks);
                            bench_samples += 1;
                            bench_awaiting_update = true;
                        }
                    }
                    bench_sent += 1;
                }
                switch (outcome.delivered.event) {
                    .scrollbar_event => scrollbar_event_delivered = true,
                    else => {},
                }

                // A suppressed prefix (for example the first half of C-x o)
                // can produce no Emacs fact change. Drain already-acknowledged
                // intents without waiting for another frame update so bounded
                // command sequences remain live. Scope the forced pacing change
                // to this smoke so recovery and interactive modes retain their
                // existing one-event-per-frame behavior.
                if (config.mode == .emacs_window_navigation or config.mode == .emacs_window_restore or config.mode == .emacs_window_pointer_select) {
                    while (delivery.pending == null and delivery.queue.length > 0) {
                        const queued = try sendDeliveryEvent(
                            gpa,
                            delivery,
                            config,
                            &writer,
                            &reader,
                            envelope,
                        );
                        if (queued != .delivered) break;
                        switch (queued.delivered.event) {
                            .scrollbar_event => scrollbar_event_delivered = true,
                            else => {},
                        }
                    }
                }
            }
        }
        const bench_intent_total = bench_setup_intents + bench_total;
        if (benchmark and bench_next_intent < bench_intent_total and delivery.queue.length < input_policy.queue_capacity) {
            if (bench_next_intent < bench_setup_intents) {
                try delivery.pushKey(.{ .action = .cursor_right });
            } else if ((bench_next_intent - bench_setup_intents) % 2 == 0) {
                try delivery.pushKey(.{ .action = .backspace });
            } else {
                try delivery.pushText("x");
            }
            bench_next_intent += 1;
        }
        try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = envelope.sequence });
        try writer.interface.flush();
        if (benchmark and !bench_reported and bench_samples == config.benchmark_iterations and !bench_awaiting_update) {
            const expected_intents = bench_setup_intents +
                @as(usize, config.benchmark_warmup) + config.benchmark_iterations;
            const input_lost = expected_intents - bench_sent;
            if (bench_sent != expected_intents or bench_next_intent != expected_intents or
                delivery.pending != null or
                delivery.queue.length != 0 or input_lost != 0)
                return error.EpxlBenchmarkInputIncomplete;
            if (!input_policy.validTextInput("x"))
                return error.InvalidBenchmarkText;
            try writeEpxlRoundTripReport(
                gpa,
                io,
                config,
                bench_sent,
                input_lost,
                bench_ack_samples,
                bench_update_samples,
            );
            // The publisher keeps its bounded publish window open until its own
            // deadline; drain the remaining frames so it shuts down cleanly
            // instead of being killed mid-session.
            bench_reported = true;
        }
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
    if (config.mode == .live and !scrollbar_event_delivered)
        return error.ScrollbarEventNotDelivered;
    if (config.mode == .live)
        std.debug.print(
            "sdl3-live-smoke: dedicated scrollbar-event 0x0941 encoded, transported, and acknowledged over EPXL\n",
            .{},
        );
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
        .monitor => capabilities.contains(.platform_monitor_events),
        .dpi => capabilities.contains(.platform_dpi_events),
        .theme => capabilities.contains(.platform_theme_events),
        .window => capabilities.contains(.platform_focus_window_events),
        .scroll => capabilities.contains(.window_scroll_request_v1),
        .scrollbar_event => capabilities.contains(.window_scrollbar_event_v1),
        .menu_result => capabilities.contains(.widget_menu_result_v1),
        .menu_cancel => capabilities.contains(.widget_menu_result_v1),
        .menu_hover => capabilities.contains(.widget_menu_hover_v1),
        .menu_open_request => capabilities.contains(.widget_menu_open_request_v1),
        .toolbar_click => capabilities.contains(.widget_toolbar_click_v1),
        .dialog_result => capabilities.contains(.widget_dialog_result_v1),
        .dnd_enter, .dnd_drop, .dnd_data => capabilities.contains(.dnd_bounded_v1),
        .dnd_position => capabilities.contains(.dnd_bounded_v1),
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

const TextInputPlacement = struct {
    window_id: u64,
    area: SDL_Rect,
    cursor: c_int,
};

const TextInputAreaSync = enum { synced, unavailable, failed };

fn sceneTextInputPlacement(scene: *const frontend.Scene) ?TextInputPlacement {
    const cursor = scene.cursor orelse return null;
    if (!cursor.visible or !cursor.active or
        cursor.width <= 0 or cursor.height <= 0) return null;
    for (scene.windows.items) |owner| {
        if (owner.id != cursor.window_id or !owner.visible) continue;
        if (cursor.x < 0 or cursor.y < 0 or
            cursor.x >= owner.width or cursor.y >= owner.height) return null;
        return .{
            .window_id = owner.id,
            .area = .{
                // Scene windows are frame-relative; SDL text-input areas are
                // relative to the SDL window itself.
                .x = 0,
                .y = 0,
                .w = owner.width,
                .h = owner.height,
            },
            .cursor = cursor.x,
        };
    }
    return null;
}

fn syncTextInputArea(window: *SDL_Window, scene: *const frontend.Scene) TextInputAreaSync {
    const placement = sceneTextInputPlacement(scene) orelse return .unavailable;
    if (!SDL_SetTextInputArea(window, &placement.area, placement.cursor)) return .failed;
    return .synced;
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
    delivery.scroll_request_negotiated = capabilities.contains(.window_scroll_request_v1);
    delivery.scrollbar_event_negotiated = capabilities.contains(.window_scrollbar_event_v1);
    delivery.menu_result_negotiated = capabilities.contains(.widget_menu_result_v1);
    delivery.menu_hover_negotiated = capabilities.contains(.widget_menu_hover_v1);
    delivery.menu_open_request_negotiated = capabilities.contains(.widget_menu_open_request_v1);
    delivery.toolbar_click_negotiated = capabilities.contains(.widget_toolbar_click_v1);
    delivery.dialog_result_negotiated = capabilities.contains(.widget_dialog_result_v1);
    delivery.key_v2_negotiated = capabilities.contains(.input_key_full_v2);
    delivery.pointer_v2_negotiated = capabilities.contains(.input_pointer_v2);
    delivery.platform_negotiated = capabilities.contains(.platform_focus_window_events);
    delivery.monitor_negotiated = capabilities.contains(.platform_monitor_events);
    delivery.dpi_negotiated = capabilities.contains(.platform_dpi_events);
    delivery.theme_negotiated = capabilities.contains(.platform_theme_events);
    delivery.dnd_negotiated = capabilities.contains(.dnd_bounded_v1);
}

fn usePointerV2(capabilities: capability.Set, config: *const Config) bool {
    return capabilities.contains(.input_pointer_v2) and config.synthetic_pointer_v2;
}

/// Bounded open-popup pointer policy.
///
/// While a popup menu is open and `widget.menu_result_v1` is negotiated, a
/// primary click belongs to the menu: a press on a selectable row reports
/// `MENU_RESULT`, a press outside the popup reports `MENU_CANCEL`, and a press
/// on a separator, submenu, or disabled row reports nothing.  The matching
/// release is consumed so it cannot also become a text click.  Returns true
/// when the event was consumed by the menu.
fn handleOpenMenuPointer(
    delivery: *input_policy.DeliveryJournal,
    scene: *const frontend.Scene,
    window: *SDL_Window,
    capabilities: capability.Set,
    down: bool,
    x: i32,
    y: i32,
) !bool {
    const open = scene.menu_open orelse return false;
    const header = scene.frame_header orelse return false;
    var output_width: c_int = 0;
    var output_height: c_int = 0;
    SDL_GetWindowSize(window, &output_width, &output_height);
    if (output_width <= 0 or output_height <= 0) return false;
    const scale = sceneFrameScale(header, @intCast(output_width), @intCast(output_height));
    if (!(scale > 0)) return false;
    switch (frontend.hitTestOpenMenu(
        scene,
        @as(f32, @floatFromInt(x)) / scale,
        @as(f32, @floatFromInt(y)) / scale,
    ) orelse return false) {
        .item => |item| {
            if (!down) return true;
            try delivery.pushMenuResult(.{
                .menu_id = item.menu_id,
                .menu_generation = item.menu_generation,
                .item_id = item.item_id,
                .window_id = item.window_id,
                .frame_generation = item.frame_generation,
            });
        },
        .submenu => |hit| {
            if (!down) return true;
            if (!capabilities.contains(.widget_menu_open_request_v1)) return true;
            const origin = frontend.menuSubmenuOrigin(scene, hit.item_id) orelse
                return error.MenuSubmenuOriginUnavailable;
            try delivery.pushMenuOpenRequest(.{
                .menu_id = hit.menu_id,
                .menu_generation = hit.menu_generation,
                .item_id = hit.item_id,
                .window_id = hit.window_id,
                .frame_generation = hit.frame_generation,
                .x = origin.x,
                .y = origin.y,
            });
        },
        .inside => {
            if (!down) return true;
        },
        .outside => {
            if (!down) return true;
            try delivery.pushMenuCancel(.{
                .reason = .user,
                .menu_id = open.menu_id,
                .menu_generation = open.menu_generation,
                .window_id = open.window_id,
                .frame_generation = open.frame_generation,
            });
        },
    }
    return true;
}

/// Bounded tool-bar press tracking.
///
/// A press that lands on a selectable item records its full identity so the
/// matching release reports the same item.  A release is only reported while
/// the recorded toolbar generation is still live, so a stale press cannot
/// produce a click for an item the backend has already replaced.
const ToolbarPressTracker = struct {
    pressed: ?frontend.ToolbarHit = null,

    fn reset(self: *ToolbarPressTracker) void {
        self.pressed = null;
    }
};

fn toolbarClickPayload(
    hit: frontend.ToolbarHit,
    phase: protocol.ToolbarClickPhase,
    clicks: u8,
    button: u8,
    x: i32,
    y: i32,
) protocol.ToolbarClick {
    return .{
        .phase = phase,
        .toolbar_id = hit.toolbar_id,
        .toolbar_generation = hit.toolbar_generation,
        .item_id = hit.item_id,
        .window_id = hit.window_id,
        .frame_generation = hit.frame_generation,
        .click_count = if (clicks == 0) 1 else clicks,
        .button = button,
        .modifiers = @intCast(input_policy.sdlModifiersToEup(SDL_GetModState())),
        .x = x,
        .y = y,
    };
}

/// Bounded scrollbar pointer policy.
///
/// A press on the thumb opens a relative drag session; a press on the trough
/// above or below the thumb pages by exactly one viewport; the matching release
/// always ends an active session.  A press outside the track falls through to
/// the ordinary pointer path.  Returns true when the event was consumed.
fn handleScrollbarPointer(
    delivery: *input_policy.DeliveryJournal,
    scene: *frontend.Scene,
    drag: *input_policy.ScrollbarDragTracker,
    window: *SDL_Window,
    down: bool,
    x: i32,
    y: i32,
) !bool {
    if (!down) {
        if (!drag.active) return false;
        drag.release(1);
        return true;
    }
    const header = scene.frame_header orelse return false;
    var output_width: c_int = 0;
    var output_height: c_int = 0;
    SDL_GetWindowSize(window, &output_width, &output_height);
    if (output_width <= 0 or output_height <= 0) return false;
    const scale = sceneFrameScale(header, @intCast(output_width), @intCast(output_height));
    if (!(scale > 0)) return false;
    // SDL reports window coordinates; the hit test, the drag tracker, and the
    // published scroll state all work in frame-logical units, so convert once
    // here.  (Passing raw window coordinates let a scaled live window open no
    // drag session at all.)
    const logical_x: i32 = @intFromFloat(@as(f32, @floatFromInt(x)) / scale);
    const logical_y: i32 = @intFromFloat(@as(f32, @floatFromInt(y)) / scale);
    const logical_x_f: f32 = @floatFromInt(logical_x);
    const logical_y_f: f32 = @floatFromInt(logical_y);
    const stateFor = struct {
        fn get(
            active: *const frontend.Scene,
            window_id: u64,
            flag: u8,
        ) ?frontend.WindowScrollState {
            for (active.scroll_states.items) |candidate| {
                if (candidate.window_id == window_id and candidate.flags & flag != 0)
                    return candidate;
            }
            return null;
        }
    }.get;
    if (frontend.hitTestScrollbar(scene, logical_x_f, logical_y_f)) |hit| {
        const owner = findSceneWindow(scene, hit.layout.window_id) orelse return false;
        const state = stateFor(scene, hit.layout.window_id, frontend.WindowScrollFlags.vertical_visible) orelse
            return false;
        switch (hit.part) {
            .thumb => {
                // The tracker re-validates the same geometry, so a rejected
                // press falls through to the ordinary pointer path.
                drag.begin(state, owner, false, logical_x, logical_y, 1) catch |err| switch (err) {
                    error.NotOnScrollbar, error.ScrollbarDragActive => return false,
                    else => return err,
                };
                return true;
            },
            .trough_above, .trough_below => {
                const page: i32 = @intCast(@min(
                    hit.layout.viewport_size,
                    @as(u32, @intCast(std.math.maxInt(i32))),
                ));
                try delivery.pushScrollRequest(.{
                    .kind = .relative,
                    .axis = .vertical,
                    .window_id = hit.layout.window_id,
                    .position = 0,
                    .delta = if (hit.part == .trough_above) -page else page,
                    .frame_generation = hit.layout.frame_generation,
                });
                return true;
            },
        }
    }
    if (frontend.hitTestHorizontalScrollbar(scene, logical_x_f, logical_y_f)) |hit| {
        const owner = findSceneWindow(scene, hit.layout.window_id) orelse return false;
        const state = stateFor(scene, hit.layout.window_id, frontend.WindowScrollFlags.horizontal_visible) orelse
            return false;
        switch (hit.part) {
            .thumb => {
                drag.begin(state, owner, true, logical_x, logical_y, 1) catch |err| switch (err) {
                    error.NotOnScrollbar, error.ScrollbarDragActive => return false,
                    else => return err,
                };
                return true;
            },
            .trough_left, .trough_right => {
                const page: i32 = @intCast(@min(
                    hit.layout.viewport_size,
                    @as(u32, @intCast(std.math.maxInt(i32))),
                ));
                try delivery.pushScrollRequest(.{
                    .kind = .relative,
                    .axis = .horizontal,
                    .window_id = hit.layout.window_id,
                    .position = 0,
                    .delta = if (hit.part == .trough_left) -page else page,
                    .frame_generation = hit.layout.frame_generation,
                });
                return true;
            },
        }
    }
    return false;
}

/// Bounded menu-bar pointer policy.
///
/// A primary press on a visible menu-bar slot reports one bounded
/// `MENU_OPEN_REQUEST` naming the backend-owned item and its logical slot
/// origin, so the backend decides whether a menu opens and what it contains.
/// The frontend never opens, reorders, relabels, or executes a menu item.
fn handleMenuBarPointer(
    delivery: *input_policy.DeliveryJournal,
    scene: *frontend.Scene,
    window: *SDL_Window,
    x: i32,
    y: i32,
) !bool {
    const bar = frontend.menuBarLayout(scene) orelse return false;
    const model = scene.menu_model orelse return false;
    const header = scene.frame_header orelse return false;
    const frame = scene.frame orelse return false;
    const scale = sceneWindowScale(window, header);
    if (!(scale > 0)) return false;
    const logical_x: i32 = @intFromFloat(@as(f32, @floatFromInt(x)) / scale);
    const logical_y: i32 = @intFromFloat(@as(f32, @floatFromInt(y)) / scale);
    const slot = frontend.hitTestMenuBar(scene, @floatFromInt(logical_x), @floatFromInt(logical_y)) orelse
        return false;
    const request: protocol.MenuOpenRequest = .{
        .menu_id = model.header.menu_id,
        .menu_generation = model.header.menu_generation,
        .item_id = slot.item_id,
        .window_id = bar.window_id,
        .frame_generation = frame.generation,
        .x = slot.x,
        .y = bar.strip_height,
    };
    delivery.pushMenuOpenRequest(request) catch |err| switch (err) {
        error.MenuOpenRequestCapabilityNotNegotiated => return false,
        else => return err,
    };
    return true;
}

/// Bounded tool-bar pointer policy.
///
/// A primary press on a visible enabled button or toggle reports
/// `TOOLBAR_CLICK(press)` and is consumed so it cannot also become a text
/// click; the matching release reports `TOOLBAR_CLICK(release)` for the same
/// item while its generation is still live.  A press on a separator, a space,
/// a disabled item, or outside the row is not consumed and falls through to the
/// ordinary pointer path.  Dragging off the item before release still reports
/// the release so the pair stays balanced.  Returns true when the event was
/// consumed.
fn handleToolbarPointer(
    delivery: *input_policy.DeliveryJournal,
    scene: *const frontend.Scene,
    tracker: *ToolbarPressTracker,
    window: *SDL_Window,
    down: bool,
    clicks: u8,
    button: u8,
    x: i32,
    y: i32,
) !bool {
    const model = scene.toolbar orelse {
        tracker.reset();
        return false;
    };
    if (!down) {
        const pressed = tracker.pressed orelse return false;
        tracker.reset();
        if (pressed.toolbar_generation != model.header.toolbar_generation) return false;
        try delivery.pushToolbarClick(toolbarClickPayload(pressed, .release, clicks, button, x, y));
        return true;
    }
    const header = scene.frame_header orelse return false;
    var output_width: c_int = 0;
    var output_height: c_int = 0;
    SDL_GetWindowSize(window, &output_width, &output_height);
    if (output_width <= 0 or output_height <= 0) return false;
    const scale = sceneFrameScale(header, @intCast(output_width), @intCast(output_height));
    if (!(scale > 0)) return false;
    const hit = frontend.hitTestToolbar(
        scene,
        @as(f32, @floatFromInt(x)) / scale,
        @as(f32, @floatFromInt(y)) / scale,
    ) orelse {
        tracker.reset();
        return false;
    };
    tracker.pressed = hit;
    try delivery.pushToolbarClick(toolbarClickPayload(hit, .press, clicks, button, x, y));
    return true;
}

/// The delivery journal admits one in-flight intent and a bounded queue.
///
/// Best-effort observations — idle pointer motion, pen air hover, and drag
/// position feedback — are coalesced to an idle journal boundary instead of
/// filling that queue.  A fast pointer or a slow backend must never turn a
/// routine observation into a full queue, and a full queue must never fail the
/// session.  Ordered press/drag/release and every payload report stay exact.
fn journalIdle(delivery: *const input_policy.DeliveryJournal) bool {
    return delivery.pending == null and delivery.queue.length == 0;
}

/// Bounded platform drag-and-drop tracker.
///
/// SDL reports a drop as an ordered begin/position/file-or-text/complete
/// sequence, so the tracker accumulates one bounded offer and one bounded
/// payload and reports the whole drop on completion.  A payload longer than the
/// bounded capacity is not reported rather than silently truncated.
///
/// ponytail: one offer and 256 payload bytes per drop; raise the bound (and the
/// selection-style request/data handshake) if large or multi-format drops matter.
const DndTracker = struct {
    active: bool = false,
    has_payload: bool = false,
    drag_id: u32 = 1,
    window_x: i32 = 0,
    window_y: i32 = 0,
    target_buf: [input_policy.max_dnd_target]u8 = @splat(0),
    target_len: u8 = 0,
    payload_buf: [input_policy.max_dnd_payload]u8 = @splat(0),
    payload_len: usize = 0,

    fn reset(self: *DndTracker) void {
        self.* = .{};
    }

    fn target(self: *const DndTracker) []const u8 {
        return self.target_buf[0..self.target_len];
    }

    fn payload(self: *const DndTracker) []const u8 {
        return self.payload_buf[0..self.payload_len];
    }

    fn lastX(self: *const DndTracker) i32 {
        return self.window_x;
    }

    fn lastY(self: *const DndTracker) i32 {
        return self.window_y;
    }

    /// Record one bounded offer.  Returns false when the target or payload does
    /// not fit the bounded reverse-intent storage.
    fn setPayload(self: *DndTracker, target_name: []const u8, payload_bytes: []const u8) bool {
        if (!protocol.validSelectionTarget(target_name) or target_name.len > self.target_buf.len)
            return false;
        if (payload_bytes.len == 0 or payload_bytes.len > self.payload_buf.len) return false;
        @memcpy(self.target_buf[0..target_name.len], target_name);
        self.target_len = @intCast(target_name.len);
        @memcpy(self.payload_buf[0..payload_bytes.len], payload_bytes);
        self.payload_len = payload_bytes.len;
        self.has_payload = true;
        return true;
    }
};

/// Bounded drag-and-drop receive policy.
///
/// A drop is only reported when `dnd.bounded_v1` is negotiated and the whole
/// begin/position/payload/complete sequence arrives for this window.  The report
/// is the exact `DND_ENTER` / `DND_DROP` / `DND_DATA` triple with a synthesized
/// copy action, because SDL does not expose the source's action policy; Emacs
/// decides what to do with the offered target and payload.  Returns true when
/// the event was consumed by the drop tracker.
fn handleDndEvent(
    delivery: *input_policy.DeliveryJournal,
    tracker: *DndTracker,
    capabilities: capability.Set,
    window: *SDL_Window,
    event: SDL_Event,
) !bool {
    if (!capabilities.contains(.dnd_bounded_v1)) return false;
    const window_id = SDL_GetWindowID(window);
    if (event.drop.window_id != 0 and event.drop.window_id != window_id) return false;
    switch (event.type) {
        SDL_EVENT_DROP_BEGIN => {
            tracker.reset();
            tracker.active = true;
            return true;
        },
        SDL_EVENT_DROP_POSITION => {
            if (!tracker.active) return false;
            const x = boundedPointerCoordinate(event.drop.x) orelse return true;
            const y = boundedPointerCoordinate(event.drop.y) orelse return true;
            tracker.window_x = x;
            tracker.window_y = y;
            // Position feedback is best-effort: report it only when the journal
            // is idle so it can never delay or displace the payload report.
            if (journalIdle(delivery)) {
                try delivery.pushDndPosition(.{
                    .drag_id = tracker.drag_id,
                    .x = x,
                    .y = y,
                });
            }
            return true;
        },
        SDL_EVENT_DROP_FILE, SDL_EVENT_DROP_TEXT => {
            if (!tracker.active) return false;
            const data = event.drop.data orelse return true;
            const bytes = std.mem.span(data);
            const target: []const u8 = if (event.type == SDL_EVENT_DROP_TEXT)
                "text/plain"
            else
                "text/uri-list";
            _ = tracker.setPayload(target, bytes);
            return true;
        },
        SDL_EVENT_DROP_COMPLETE => {
            if (!tracker.active) return false;
            defer tracker.reset();
            if (!tracker.has_payload) return true;
            try delivery.pushDndEnter(.{
                .drag_id = tracker.drag_id,
                .x = tracker.lastX(),
                .y = tracker.lastY(),
                .target_buf = tracker.target_buf,
                .target_len = tracker.target_len,
            });
            try delivery.pushDndDrop(.{
                .drag_id = tracker.drag_id,
                .x = tracker.lastX(),
                .y = tracker.lastY(),
            });
            try delivery.pushDndData(.{
                .drag_id = tracker.drag_id,
                .target_buf = tracker.target_buf,
                .target_len = tracker.target_len,
                .payload_buf = tracker.payload_buf,
                .payload_len = tracker.payload_len,
            });
            return true;
        },
        else => return false,
    }
}

/// Build a bounded dialog result for the open dialog, carrying the current
/// frontend prompt text (empty for a non-prompt dialog).
fn dialogResultPayload(scene: *const frontend.Scene, button: protocol.DialogResultButton) ?protocol.DialogResult {
    const dialog = scene.dialog orelse return null;
    return .{
        .button = button,
        .dialog_id = dialog.dialog_id,
        .dialog_generation = dialog.dialog_generation,
        .window_id = dialog.window_id,
        .frame_generation = dialog.frame_generation,
        .text_len = scene.dialog_text_len,
        .text = scene.dialog_text,
    };
}

/// Bounded prompt text-field policy.
///
/// While a prompt dialog is open the field owns text input and backspace, so
/// the bytes never reach Emacs as buffer input; the accepted text is submitted
/// only inside the bounded `DIALOG_RESULT` tail when the user chooses a button.
/// Returns true when the event was consumed by the field.
fn handleDialogFieldInput(
    scene: *frontend.Scene,
    capabilities: capability.Set,
    event: SDL_Event,
) bool {
    if (!capabilities.contains(.widget_dialog_result_v1)) return false;
    const dialog = scene.dialog orelse return false;
    if (dialog.kind != .prompt) return false;
    if (frontend.dialogFieldRect(scene) == null) return false;
    if (event.type == SDL_EVENT_TEXT_INPUT) {
        const data = event.text.text orelse return false;
        _ = frontend.dialogAppendInput(scene, std.mem.span(data));
        return true;
    }
    if (event.type == SDL_EVENT_KEY_DOWN and !event.key.repeat and
        event.key.scancode == input_policy.SDL_SCANCODE_BACKSPACE)
    {
        _ = frontend.dialogBackspace(scene);
        return true;
    }
    return false;
}

/// Bounded dialog pointer policy.
///
/// A modal dialog owns every click inside its box: a press on a standard button
/// reports `DIALOG_RESULT` with the backend-owned identity and no input text, a
/// press elsewhere in the box is consumed without a result, and the matching
/// release is consumed either way.  A press outside the box falls through to
/// the ordinary pointer path.  Returns true when the event was consumed.
fn handleDialogPointer(
    delivery: *input_policy.DeliveryJournal,
    scene: *const frontend.Scene,
    window: *SDL_Window,
    down: bool,
    x: i32,
    y: i32,
) !bool {
    if (scene.dialog == null) return false;
    const header = scene.frame_header orelse return false;
    var output_width: c_int = 0;
    var output_height: c_int = 0;
    SDL_GetWindowSize(window, &output_width, &output_height);
    if (output_width <= 0 or output_height <= 0) return false;
    const scale = sceneFrameScale(header, @intCast(output_width), @intCast(output_height));
    if (!(scale > 0)) return false;
    switch (frontend.hitTestDialog(
        scene,
        @as(f32, @floatFromInt(x)) / scale,
        @as(f32, @floatFromInt(y)) / scale,
    ) orelse return false) {
        .outside => return false,
        .inside => return true,
        .button => |hit| {
            if (!down) return true;
            // The reported identity comes from the hit test; the text tail is
            // the frontend's bounded prompt field.
            var result = dialogResultPayload(scene, hit.button) orelse return true;
            result.dialog_id = hit.dialog_id;
            result.dialog_generation = hit.dialog_generation;
            result.window_id = hit.window_id;
            result.frame_generation = hit.frame_generation;
            try delivery.pushDialogResult(result);
            return true;
        },
    }
}

/// Escape on an open dialog reports the keyboard dismissal when the backend
/// button policy offers a cancel or close button.  Returns true when the key
/// was consumed by the dialog.
fn consumeDialogEscape(
    delivery: *input_policy.DeliveryJournal,
    scene: *const frontend.Scene,
    key: SDL_KeyboardEvent,
) !bool {
    if (!key.down or key.repeat or key.scancode != input_policy.SDL_SCANCODE_ESCAPE) return false;
    const dialog = scene.dialog orelse return false;
    const button = frontend.dialogEscapeButton(dialog) orelse return false;
    try delivery.pushDialogResult(dialogResultPayload(scene, button) orelse return false);
    return true;
}

/// Report a frontend popup highlight transition as `MENU_HOVER`.
///
/// The frontend owns the highlight cursor and the backend owns what the
/// highlight means.  A `leave` carries no item identity by wire contract, so a
/// transition is reported as `leave` followed by `enter` for the new row.  The
/// reported coordinates are the highlighted row's origin when the transition
/// came from the keyboard, or the pointer position when it came from motion.
fn reportMenuHighlight(
    delivery: *input_policy.DeliveryJournal,
    scene: *const frontend.Scene,
    previous: u32,
    pointer: ?struct { x: i32, y: i32 },
) !void {
    const open = scene.menu_open orelse return;
    if (previous != 0) {
        try delivery.pushMenuHover(.{
            .phase = .leave,
            .menu_id = open.menu_id,
            .menu_generation = open.menu_generation,
            .window_id = open.window_id,
            .frame_generation = open.frame_generation,
        });
    }
    const slot = frontend.menuHighlightSlot(scene) orelse return;
    const x = if (pointer) |point| point.x else @as(i32, @intFromFloat(slot.x));
    const y = if (pointer) |point| point.y else @as(i32, @intFromFloat(slot.y));
    try delivery.pushMenuHover(.{
        .phase = .enter,
        .menu_id = open.menu_id,
        .menu_generation = open.menu_generation,
        .item_id = slot.item_id,
        .window_id = open.window_id,
        .frame_generation = open.frame_generation,
        .x = @max(0, x),
        .y = @max(0, y),
    });
}

/// Ask the backend to replace the popup through an enabled submenu row.
fn requestSubmenuOpen(
    delivery: *input_policy.DeliveryJournal,
    scene: *const frontend.Scene,
    hit: frontend.MenuHit,
) !void {
    const origin = frontend.menuSubmenuOrigin(scene, hit.item_id) orelse
        return error.MenuSubmenuOriginUnavailable;
    try delivery.pushMenuOpenRequest(.{
        .menu_id = hit.menu_id,
        .menu_generation = hit.menu_generation,
        .item_id = hit.item_id,
        .window_id = hit.window_id,
        .frame_generation = hit.frame_generation,
        .x = origin.x,
        .y = origin.y,
    });
}

/// Bounded popup highlight policy for pointer motion.
///
/// While a popup is open, motion moves the frontend highlight to the selectable
/// row under the pointer (or clears it when the pointer leaves the rows) and
/// reports exactly one transition.  Returns true when the motion was consumed,
/// so it cannot also become a text hover/drag sample behind the popup.
fn handleMenuHoverMotion(
    delivery: *input_policy.DeliveryJournal,
    scene: *frontend.Scene,
    window: *SDL_Window,
    capabilities: capability.Set,
    x: i32,
    y: i32,
) !bool {
    if (scene.menu_open == null) return false;
    const header = scene.frame_header orelse return false;
    var output_width: c_int = 0;
    var output_height: c_int = 0;
    SDL_GetWindowSize(window, &output_width, &output_height);
    if (output_width <= 0 or output_height <= 0) return false;
    const scale = sceneFrameScale(header, @intCast(output_width), @intCast(output_height));
    if (!(scale > 0)) return false;
    var item_id: u32 = 0;
    var submenu_hit: ?frontend.MenuHit = null;
    switch (frontend.hitTestOpenMenu(
        scene,
        @as(f32, @floatFromInt(x)) / scale,
        @as(f32, @floatFromInt(y)) / scale,
    ) orelse return false) {
        .outside, .inside => {},
        .submenu => |hit| {
            item_id = hit.item_id;
            submenu_hit = hit;
        },
        .item => |hit| item_id = hit.item_id,
    }
    const previous = scene.menu_highlight_item;
    if (item_id == previous) return true;
    scene.menu_highlight_item = item_id;
    try reportMenuHighlight(delivery, scene, previous, .{ .x = x, .y = y });
    if (submenu_hit) |hit| {
        if (!capabilities.contains(.widget_menu_open_request_v1)) return true;
        try requestSubmenuOpen(delivery, scene, hit);
    }
    return true;
}

/// Bounded popup keyboard policy.  Up/Down move the highlight between
/// selectable rows and Enter chooses the highlighted row; Escape is handled
/// separately as the dismissal.  Returns true when the key was consumed.
fn handleMenuKey(
    delivery: *input_policy.DeliveryJournal,
    scene: *frontend.Scene,
    key: SDL_KeyboardEvent,
) !bool {
    if (!key.down or key.repeat) return false;
    if (scene.menu_open == null) return false;
    const delta: i32 = switch (key.scancode) {
        input_policy.SDL_SCANCODE_UP => -1,
        input_policy.SDL_SCANCODE_DOWN => 1,
        else => return false,
    };
    const previous = scene.menu_highlight_item;
    if (!frontend.menuMoveHighlight(scene, delta)) return true;
    try reportMenuHighlight(delivery, scene, previous, null);
    return true;
}

/// Choose the highlighted popup row.  Returns true when a row was reported.
fn consumeMenuEnter(
    delivery: *input_policy.DeliveryJournal,
    scene: *const frontend.Scene,
    key: SDL_KeyboardEvent,
    capabilities: capability.Set,
) !bool {
    if (!key.down or key.repeat) return false;
    const open = scene.menu_open orelse return false;
    if (key.scancode != input_policy.SDL_SCANCODE_RETURN) return false;
    const slot = frontend.menuHighlightSlot(scene) orelse return false;
    if (slot.submenu) {
        if (!capabilities.contains(.widget_menu_open_request_v1)) return true;
        try requestSubmenuOpen(delivery, scene, .{
            .menu_id = open.menu_id,
            .menu_generation = open.menu_generation,
            .item_id = slot.item_id,
            .window_id = open.window_id,
            .frame_generation = open.frame_generation,
        });
        return true;
    }
    try delivery.pushMenuResult(.{
        .menu_id = open.menu_id,
        .menu_generation = open.menu_generation,
        .item_id = slot.item_id,
        .window_id = open.window_id,
        .frame_generation = open.frame_generation,
    });
    return true;
}

/// Escape on an open popup reports the keyboard dismissal.  Returns true when
/// the key was consumed by the menu.
fn consumeOpenMenuEscape(
    delivery: *input_policy.DeliveryJournal,
    scene: *const frontend.Scene,
    key: SDL_KeyboardEvent,
) !bool {
    if (!key.down or key.repeat or key.scancode != input_policy.SDL_SCANCODE_ESCAPE) return false;
    const open = scene.menu_open orelse return false;
    try delivery.pushMenuCancel(.{
        .reason = .escape,
        .menu_id = open.menu_id,
        .menu_generation = open.menu_generation,
        .window_id = open.window_id,
        .frame_generation = open.frame_generation,
    });
    return true;
}

fn pollEpxlInteractiveInput(
    delivery: *input_policy.DeliveryJournal,
    scrollbar_drag: *input_policy.ScrollbarDragTracker,
    toolbar_press: *ToolbarPressTracker,
    dnd_tracker: *DndTracker,
    config: *const Config,
    window: *SDL_Window,
    retained: *RetainedFrame,
    scene: *frontend.Scene,
    gate: *renderer_policy.FrameGate,
    capabilities: capability.Set,
    dirty: *bool,
    primary_paste_queued: *bool,
    monitor_refresh_needed: *bool,
) !void {
    var event: SDL_Event = undefined;
    while (SDL_PollEvent(&event)) {
        switch (event.type) {
            SDL_EVENT_QUIT => return error.InteractiveQuit,
            SDL_EVENT_KEY_DOWN, SDL_EVENT_KEY_UP => {
                if (handleDialogFieldInput(scene, capabilities, event)) {
                    dirty.* = true;
                    return;
                }
                if (scene.dialog != null and
                    capabilities.contains(.widget_dialog_result_v1) and
                    try consumeDialogEscape(delivery, scene, event.key))
                {
                    dirty.* = true;
                    return;
                }
                if (scene.menu_open != null and
                    capabilities.contains(.widget_menu_result_v1) and
                    try consumeOpenMenuEscape(delivery, scene, event.key))
                {
                    dirty.* = true;
                    return;
                }
                if (scene.menu_open != null and
                    capabilities.contains(.widget_menu_hover_v1) and
                    try handleMenuKey(delivery, scene, event.key))
                {
                    dirty.* = true;
                    return;
                }
                if (scene.menu_open != null and
                    capabilities.contains(.widget_menu_result_v1) and
                    try consumeMenuEnter(delivery, scene, event.key, capabilities))
                {
                    dirty.* = true;
                    return;
                }
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
                const is_primary_paste = input_policy.isPrimarySelectionPasteShortcut(
                    event.key.scancode,
                    event.key.down,
                    event.key.repeat,
                    event.key.modifiers,
                );
                if (event.type == SDL_EVENT_KEY_DOWN and is_primary_paste) {
                    const support = clipboardSupportFor(capabilities) orelse return;
                    if (!capabilities.contains(.clipboard_primary_selection_bounded)) return;
                    if (try queuePrimarySelectionText(delivery, support)) {
                        primary_paste_queued.* = true;
                        dirty.* = true;
                    }
                } else if (event.type == SDL_EVENT_KEY_DOWN and is_paste) {
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
                if (handleDialogFieldInput(scene, capabilities, event)) {
                    dirty.* = true;
                    return;
                }
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
                if (event.type == input_policy.SDL_EVENT_WINDOW_FOCUS_GAINED) {
                    if (!SDL_StartTextInput(window)) return sdlFail("SDL_StartTextInput");
                } else {
                    SDL_StopTextInput(window);
                }
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
                const x = event.wheel.integer_x;
                const y = event.wheel.integer_y;
                if ((x != 0) == (y != 0)) return;
                if (@abs(x) <= frontend.max_wheel_ticks and @abs(y) <= frontend.max_wheel_ticks and
                    event.wheel.x == @as(f32, @floatFromInt(x)) and
                    event.wheel.y == @as(f32, @floatFromInt(y)))
                {
                    try delivery.pushWheel(.{
                        .x = @intCast(x),
                        .y = @intCast(y),
                    });
                    dirty.* = true;
                }
            },
            SDL_EVENT_MOUSE_MOTION => {
                if (config.interactive_synthetic and !config.synthetic_pointer and !config.synthetic_pointer_v2) return;
                const x = boundedPointerCoordinate(event.motion.x) orelse return;
                const y = boundedPointerCoordinate(event.motion.y) orelse return;
                const frame_x = pointerFrameCoordinate(window, scene, x);
                const frame_y = pointerFrameCoordinate(window, scene, y);
                if (scene.menu_open != null and
                    capabilities.contains(.widget_menu_hover_v1) and
                    try handleMenuHoverMotion(delivery, scene, window, capabilities, x, y))
                {
                    dirty.* = true;
                    return;
                }
                if (scrollbar_drag.active) {
                    // A drag session ends as soon as the primary button is no
                    // longer held, so a motion sample can never keep dragging
                    // after the user released outside the window.
                    if (event.motion.state & SDL_BUTTON_LMASK == 0) {
                        scrollbar_drag.release(1);
                        return;
                    }
                    const header = scene.frame_header orelse return;
                    var output_width: c_int = 0;
                    var output_height: c_int = 0;
                    SDL_GetWindowSize(window, &output_width, &output_height);
                    const scale = sceneFrameScale(header, output_width, output_height);
                    if (!(scale > 0)) return;
                    const logical_x: i32 = @intFromFloat(@as(f32, @floatFromInt(x)) / scale);
                    const logical_y: i32 = @intFromFloat(@as(f32, @floatFromInt(y)) / scale);
                    if (try scrollbar_drag.drag(logical_x, logical_y, 1)) |request| {
                        try delivery.pushScrollRequest(request);
                        dirty.* = true;
                    }
                    return;
                }
                if (usePointerV2(capabilities, config)) {
                    const translated = input_policy.translatePointerV2(.{
                        .event_type = event.type,
                        .x = frame_x,
                        .y = frame_y,
                        .state = event.motion.state,
                        .modifiers = input_policy.sdlModifiersToEup(SDL_GetModState()),
                    }) orelse return;
                    // Idle v2 hover is best-effort and coalesced to the idle
                    // journal boundary instead of filling the bounded queue.
                    if (translated.phase == .motion and !journalIdle(delivery)) return;
                    delivery.pushPointerV2(translated) catch |err| switch (err) {
                        error.PointerSessionActive => return,
                        else => return err,
                    };
                } else {
                    const dragging = event.motion.state == SDL_BUTTON_LMASK;
                    if (event.motion.state != 0 and !dragging) return;
                    if (dragging != delivery.pointer_active) return;
                    if (!dragging and !journalIdle(delivery)) return;
                    // Idle motion is best-effort and coalesced to the idle boundary.
                    // Drag motion is ordered because the left pointer session is active.
                    try delivery.pushPointer(.{
                        .phase = .motion,
                        .button = if (dragging) 1 else 0,
                        .x = frame_x,
                        .y = frame_y,
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
                if (event.button.button == 1 and
                    scene.dialog != null and
                    capabilities.contains(.widget_dialog_result_v1) and
                    try handleDialogPointer(delivery, scene, window, down, x, y))
                {
                    dirty.* = true;
                    return;
                }
                if (event.button.button == 1 and event.button.clicks == 1 and
                    scene.menu_open != null and
                    (capabilities.contains(.widget_menu_result_v1) or
                        capabilities.contains(.widget_menu_open_request_v1)) and
                    try handleOpenMenuPointer(delivery, scene, window, capabilities, down, x, y))
                {
                    dirty.* = true;
                    return;
                }
                // A press on a real menu-bar slot belongs to the backend: the
                // frontend reports which item was asked for and never opens,
                // reorders, or executes anything itself.
                if (down and event.button.button == 1 and event.button.clicks == 1 and
                    scene.menu_open == null and
                    capabilities.contains(.widget_menu_open_request_v1) and
                    try handleMenuBarPointer(delivery, scene, window, x, y))
                {
                    dirty.* = true;
                    return;
                }
                if (event.button.button == 1 and
                    scene.toolbar != null and
                    capabilities.contains(.widget_toolbar_click_v1) and
                    try handleToolbarPointer(
                        delivery,
                        scene,
                        toolbar_press,
                        window,
                        down,
                        event.button.clicks,
                        event.button.button,
                        x,
                        y,
                    ))
                {
                    dirty.* = true;
                    return;
                }
                const frame_x = pointerFrameCoordinate(window, scene, x);
                const frame_y = pointerFrameCoordinate(window, scene, y);
                if (usePointerV2(capabilities, config)) {
                    const translated = input_policy.translatePointerV2(.{
                        .event_type = event.type,
                        .sdl_button = event.button.button,
                        .down = down,
                        .clicks = event.button.clicks,
                        .x = frame_x,
                        .y = frame_y,
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
                    if (capabilities.contains(.window_scroll_request_v1) and
                        try handleScrollbarPointer(
                            delivery,
                            scene,
                            scrollbar_drag,
                            window,
                            down,
                            x,
                            y,
                        ))
                    {
                        dirty.* = true;
                        return;
                    }
                    delivery.pushPointer(.{
                        .phase = if (down) .press else .release,
                        .button = 1,
                        .x = frame_x,
                        .y = frame_y,
                        .clicks = 1,
                    }) catch |err| switch (err) {
                        error.PointerSessionActive => return,
                        else => return err,
                    };
                    dirty.* = true;
                }
            },
            input_policy.SDL_EVENT_FINGER_DOWN,
            input_policy.SDL_EVENT_FINGER_UP,
            input_policy.SDL_EVENT_FINGER_MOTION,
            input_policy.SDL_EVENT_FINGER_CANCELED,
            => {
                if (!capabilities.contains(.input_touch_bounded_v1)) return;
                // A contact reported for another window is not ours.
                if (event.finger.window_id != 0 and
                    event.finger.window_id != SDL_GetWindowID(window)) return;
                var window_width: c_int = 0;
                var window_height: c_int = 0;
                SDL_GetWindowSize(window, &window_width, &window_height);
                if (window_width <= 0 or window_height <= 0) return;
                const translated = input_policy.translateFinger(.{
                    .event_type = event.type,
                    .normalized_x = event.finger.x,
                    .normalized_y = event.finger.y,
                    .window_width = window_width,
                    .window_height = window_height,
                }) orelse return;
                delivery.pushPointerV2(translated) catch |err| switch (err) {
                    // A second concurrent contact or an out-of-order phase is
                    // dropped; the bounded single-contact session is intact.
                    error.PointerSessionActive => return,
                    else => return err,
                };
                dirty.* = true;
            },
            input_policy.SDL_EVENT_PEN_DOWN,
            input_policy.SDL_EVENT_PEN_UP,
            input_policy.SDL_EVENT_PEN_MOTION,
            => {
                if (config.interactive_synthetic and !config.synthetic_pen) return;
                if (!capabilities.contains(.input_pen_bounded_v1)) return;
                const pen_x = boundedPointerCoordinate(event.pen.x) orelse return;
                const pen_y = boundedPointerCoordinate(event.pen.y) orelse return;
                const translated = input_policy.translatePen(.{
                    .event_type = event.type,
                    .x = pen_x,
                    .y = pen_y,
                    .pen_state = event.pen.pen_state,
                }) orelse return;
                // Pen air hover is the same best-effort observation as mouse
                // hover and is coalesced to the idle journal boundary.
                if (translated.phase == .motion and !journalIdle(delivery)) return;
                delivery.pushPointerV2(translated) catch |err| switch (err) {
                    // An out-of-order phase is dropped; the bounded pointer
                    // session is intact.
                    error.PointerSessionActive => return,
                    else => return err,
                };
                dirty.* = true;
            },
            SDL_EVENT_DROP_BEGIN,
            SDL_EVENT_DROP_POSITION,
            SDL_EVENT_DROP_FILE,
            SDL_EVENT_DROP_TEXT,
            SDL_EVENT_DROP_COMPLETE,
            => {
                if (config.interactive_synthetic and !config.synthetic_dnd) return;
                if (try handleDndEvent(delivery, dnd_tracker, capabilities, window, event)) {
                    dirty.* = true;
                }
            },
            input_policy.SDL_EVENT_WINDOW_DISPLAY_CHANGED,
            input_policy.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED,
            => {
                if (scene.frame_header == null) return;
                monitor_refresh_needed.* = true;
                const display = SDL_GetDisplayForWindow(window);
                if (display == 0) return error.MonitorBoundsUnavailable;
                var bounds: SDL_Rect = undefined;
                if (!SDL_GetDisplayBounds(display, &bounds)) return error.MonitorBoundsUnavailable;
                const monitor_scale_milli = try validatedScaleMilli(SDL_GetDisplayContentScale(display));
                _ = try delivery.pushMonitorIfNegotiated(
                    capabilities.contains(.platform_monitor_events),
                    .{
                        .kind = .current_changed,
                        .monitor_id = display,
                        .x = bounds.x,
                        .y = bounds.y,
                        .width = bounds.w,
                        .height = bounds.h,
                        .scale_milli_percent = monitor_scale_milli,
                        .primary = display == SDL_GetPrimaryDisplay(),
                        .current = true,
                    },
                );
                if (event.type == input_policy.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED) {
                    const window_scale_milli = try validatedScaleMilli(SDL_GetWindowDisplayScale(window));
                    const dpi_milli = window_scale_milli * 96;
                    _ = try delivery.pushDpiIfNegotiated(
                        capabilities.contains(.platform_dpi_events),
                        .{
                            .frame_id = scene.frame_header.?.frame_id,
                            .sdl_window_id = event.window.window_id,
                            .scale_milli_percent = window_scale_milli,
                            .dpi_x_milli = dpi_milli,
                            .dpi_y_milli = dpi_milli,
                        },
                    );
                }
            },
            SDL_EVENT_SYSTEM_THEME_CHANGED => {
                const raw_theme = SDL_GetSystemTheme();
                const appearance: protocol.ThemeAppearance = switch (raw_theme) {
                    SDL_SYSTEM_THEME_LIGHT => .light,
                    SDL_SYSTEM_THEME_DARK => .dark,
                    else => .unknown,
                };
                if (try delivery.pushThemeIfNegotiated(
                    capabilities.contains(.platform_theme_events),
                    .{ .appearance = appearance },
                )) dirty.* = true;
            },
            SDL_EVENT_RENDER_TARGETS_RESET, SDL_EVENT_RENDER_DEVICE_RESET, SDL_EVENT_RENDER_DEVICE_LOST => {
                unicode_text_renderer.clearTextures();
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
        var window_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &window_bytes, line.window_id, .little);
        hasher.update(&window_bytes);
        hasher.update(&row_bytes);
        hasher.update(line.bytes);
        hasher.update(&.{0});
    }
    var mode_line_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (scene.mode_lines[0..scene.mode_line_count]) |*mode_line| {
        var window_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &window_bytes, mode_line.window_id, .little);
        mode_line_hasher.update(&window_bytes);
        var flag_bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &flag_bytes, mode_line.flags, .little);
        mode_line_hasher.update(&flag_bytes);
        mode_line_hasher.update(mode_line.bytes[0..mode_line.len]);
        var geometry_bytes: [16]u8 = undefined;
        std.mem.writeInt(i32, geometry_bytes[0..4], mode_line.x, .little);
        std.mem.writeInt(i32, geometry_bytes[4..8], mode_line.y, .little);
        std.mem.writeInt(i32, geometry_bytes[8..12], mode_line.width, .little);
        std.mem.writeInt(i32, geometry_bytes[12..16], mode_line.height, .little);
        mode_line_hasher.update(&geometry_bytes);
        mode_line_hasher.update(&.{0});
    }
    var text_hash: [32]u8 = undefined;
    hasher.final(&text_hash);
    var mode_line_digest: [32]u8 = undefined;
    mode_line_hasher.final(&mode_line_digest);
    const mode_line_hash = std.mem.readInt(u64, mode_line_digest[0..8], .little);

    var aux_line_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (scene.aux_lines[0..scene.aux_line_count]) |line| {
        var window_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &window_bytes, line.window_id, .little);
        aux_line_hasher.update(&window_bytes);
        var flag_bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &flag_bytes, line.flags, .little);
        aux_line_hasher.update(&flag_bytes);
        aux_line_hasher.update(line.bytes[0..line.len]);
        var geometry_bytes: [16]u8 = undefined;
        std.mem.writeInt(i32, geometry_bytes[0..4], line.x, .little);
        std.mem.writeInt(i32, geometry_bytes[4..8], line.y, .little);
        std.mem.writeInt(i32, geometry_bytes[8..12], line.width, .little);
        std.mem.writeInt(i32, geometry_bytes[12..16], line.height, .little);
        aux_line_hasher.update(&geometry_bytes);
        aux_line_hasher.update(&.{0});
    }
    var aux_line_digest: [32]u8 = undefined;
    aux_line_hasher.final(&aux_line_digest);
    const aux_line_hash = std.mem.readInt(u64, aux_line_digest[0..8], .little);

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

    var cursor_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var cursor_observations_complete = scene.cursor_count <= renderer_policy.max_observed_cursors;
    for (scene.cursors[0..scene.cursor_count]) |cursor| {
        var window_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &window_bytes, cursor.window_id, .little);
        cursor_hasher.update(&window_bytes);
        var cursor_bytes: [17]u8 = undefined;
        std.mem.writeInt(i32, cursor_bytes[0..4], cursor.x, .little);
        std.mem.writeInt(i32, cursor_bytes[4..8], cursor.y, .little);
        std.mem.writeInt(i32, cursor_bytes[8..12], cursor.width, .little);
        std.mem.writeInt(i32, cursor_bytes[12..16], cursor.height, .little);
        cursor_bytes[16] = cursor.kind;
        cursor_hasher.update(&cursor_bytes);
        cursor_hasher.update(&.{ @intFromBool(cursor.visible), @intFromBool(cursor.active) });
        _ = findWindowById(scene.windows.items, cursor.window_id) orelse {
            cursor_observations_complete = false;
            continue;
        };
    }
    var cursor_hash: u64 = 0;
    if (cursor_observations_complete) {
        var digest: [32]u8 = undefined;
        cursor_hasher.final(&digest);
        cursor_hash = std.mem.readInt(u64, digest[0..8], .little);
    }

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
        const row = findSceneRow(scene, line.window_id, line.row_index) orelse {
            text_lines_complete = false;
            break;
        };
        const owner = findWindowById(scene.windows.items, line.window_id) orelse {
            text_lines_complete = false;
            break;
        };
        const damage_rect = observedTextDamageRect(owner, row, line.bytes.len) orelse {
            text_lines_complete = false;
            break;
        };
        text_lines[bounded_text_line_count] = .{
            .window_id = line.window_id,
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
        .cursor_hash = cursor_hash,
        .cursor_count = scene.cursor_count,
        .text_hash = text_hash,
        .mode_line_hash = mode_line_hash ^ aux_line_hash,
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

fn refreshSceneMonitorFromSDL(window: *SDL_Window, scene: *frontend.Scene) !bool {
    if (scene.frame == null or scene.session_id == null or scene.next_sequence == null)
        return false;
    const display = SDL_GetDisplayForWindow(window);
    if (display == 0) return false;
    var bounds: SDL_Rect = undefined;
    if (!SDL_GetDisplayBounds(display, &bounds)) return false;
    scene.monitor = .{
        .monitor_id = display,
        .x = bounds.x,
        .y = bounds.y,
        .width = bounds.w,
        .height = bounds.h,
        .flags = if (display == SDL_GetPrimaryDisplay()) protocol.FrameMonitorFlags.primary else 0,
        .frame_generation = scene.frame.?.generation,
    };
    return true;
}

fn validatedScaleMilli(value: f32) !u32 {
    if (!std.math.isFinite(value) or value <= 0 or value > 64.0)
        return error.InvalidDisplayScale;
    return @intFromFloat(@round(value * 1000.0));
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
    if (config.force_frontend_failure) return error.FrontendFailureRequested;

    if (config.mode == .emacs_clipboard_unicode) {
        if (!negotiated.effective.contains(.clipboard_ascii_bounded) or
            !negotiated.effective.contains(.clipboard_text_unicode))
            return error.ClipboardCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-clipboard-unicode-smoke: {{\"kind\":\"sdl3-clipboard-unicode-smoke\",\"negotiated\":{{\"clipboard.ascii_bounded\":true,\"clipboard.text_unicode\":true,\"platform_focus_window_events\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
    }
    if (config.mode == .emacs_primary_selection) {
        if (!negotiated.effective.contains(.clipboard_ascii_bounded) or
            !negotiated.effective.contains(.clipboard_text_unicode) or
            !negotiated.effective.contains(.clipboard_primary_selection_bounded))
            return error.PrimarySelectionCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-primary-selection-smoke: {{\"kind\":\"sdl3-primary-selection-smoke\",\"negotiated\":{{\"clipboard.ascii_bounded\":true,\"clipboard.text_unicode\":true,\"clipboard.primary_selection_bounded\":true}},\"result\":\"negotiated\"}}\n",
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
    if (config.mode == .emacs_epxl_ime_commit) {
        if (!negotiated.effective.contains(.input_text_ascii) or
            !negotiated.effective.contains(.input_text_unicode) or
            !negotiated.effective.contains(.render_unicode_text_v1))
            return error.TextCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-ime-commit-smoke: {{\"kind\":\"sdl3-ime-commit-smoke\",\"negotiated\":{{\"input.text_ascii\":true,\"input.text_unicode\":true,\"render.unicode_text_v1\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
    }
    if (config.mode == .emacs_epxl_dnd) {
        if (!negotiated.effective.contains(.dnd_bounded_v1))
            return error.DndCapabilityNotNegotiated;
        std.debug.print(
            "sdl3-dnd-drop-smoke: {{\"kind\":\"sdl3-dnd-drop-smoke\",\"negotiated\":{{\"dnd.bounded_v1\":true}},\"result\":\"negotiated\"}}\n",
            .{},
        );
    }

    reserveFrontendInputSequence(delivery);

    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow("Emacs Proto-UI EPXL", 960, 600, SDL_WINDOW_RESIZABLE) orelse
        return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);
    defer SDL_StopTextInput(window);
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
    var scrollbar_event_delivered = false;
    var title_applied = false;
    var focus_gained_delivered = false;
    var focus_lost_delivered = false;
    var observed_focus_gained = false;
    var observed_focus_transition = false;
    var window_request_delivered = false;
    var fullscreen_request_delivered = false;
    var selection_owner_set_seen = false;
    var minimize_request_delivered = false;
    var restore_request_delivered = false;
    var minimize_sequence: u64 = 0;
    var restore_sequence: u64 = 0;
    var selection_owner_clear_seen = false;
    var selection_lost_seen = false;
    var selection_replacement_seen = false;
    var initial_platform_claimed = false;
    var lost_platform_released = false;
    var replacement_platform_claimed = false;
    var clear_platform_released = false;
    var selection_transfer_owner_seen = false;
    var selection_transfer_request_seen = false;
    var selection_transfer_data_seen = false;
    var selection_error_request_seen = false;
    var selection_error_seen = false;
    var selection_transfer_clear_seen = false;
    var transfer_platform_claimed = false;
    var transfer_platform_released = false;
    var theme_event_delivered = false;
    var dnd_position_count: usize = 0;
    var dnd_position_point: input_policy.DndPositionEvent = .{ .drag_id = 0, .x = 0, .y = 0 };
    var face_binding_observed = false;
    var face_text_drawn = false;
    var scrollbar_observed = false;
    var scroll_page_seeded = false;
    var scroll_page_position: ?u32 = null;
    var scroll_drag_seeded = false;
    var scroll_drag_position: ?u32 = null;
    var menu_open_seeded = false;
    var menu_open_request_delivered: ?protocol.MenuOpenRequest = null;
    var menu_popup_observed = false;
    var menu_popup_disabled = false;
    var menu_popup_key = false;
    var menu_popup_help = false;
    var menu_popup_icon = false;
    var menu_help_drawn = false;
    var menu_key_drawn = false;
    var menu_row_pressed = false;
    var menu_result_delivered = false;
    var menu_popup_closed = false;
    const menu_mode = config.mode == .emacs_epxl_menu_open or
        config.mode == .emacs_epxl_menu_apply;
    var menu_apply_edited = false;
    var menu_apply_undone = false;
    var graphic_scroll_width: u32 = 0;
    var graphic_fringe_left: i32 = 0;
    var graphic_fringe_right: i32 = 0;
    var graphic_fringe_drawn = false;
    var graphic_inactive_mode_line_seen = false;
    var graphic_inactive_mode_line_colored = false;
    var graphic_region_seen = false;
    var graphic_region_rects: usize = 0;
    var graphic_runs_seen = false;
    var graphic_runs_colored = false;
    var graphic_run_rows: usize = 0;
    var graphic_run_background_colored = false;
    var graphic_run_underline_drawn = false;
    var graphic_run_inverse_drawn = false;
    var graphic_run_style_drawn = false;
    var graphic_run_overlay_seen = false;
    var graphic_multi_window_run = false;
    var graphic_variable_font_seen = false;
    var graphic_variable_font_drawn = false;
    var graphic_variable_metrics = false;
    var graphic_wire_snapshot: ?facts.Snapshot = null;
    defer if (graphic_wire_snapshot) |*snapshot| snapshot.deinit(gpa);
    var graphic_mode_line_bold = false;
    var graphic_header_line_run = false;
    var graphic_tab_line_run = false;
    var graphic_partial_run = false;
    var graphic_header_line_drawn = false;
    var graphic_tab_line_drawn = false;
    var graphic_max_text_lines: usize = 0;
    var graphic_region_colored = false;
    var mouse_face_seen = false;
    var mouse_face_rects: usize = 0;
    var hscroll_observed = false;
    var hscroll_position: ?u32 = null;
    var delivered_monitor: ?protocol.MonitorEvent = null;
    var delivered_dpi: ?protocol.DpiEvent = null;
    try live.writeControl(&writer.interface, .{ .kind = .resync_request, .sequence = 1 });
    try writer.interface.flush();
    const begin = try readControlExact(&reader);
    if (begin.kind != .resync_begin or begin.sequence != 1) return error.InvalidResyncRequest;
    scene.resetForResync();

    while (true) {
        const inbound = try readInbound(&reader, gpa);
        switch (inbound) {
            .control => |control| {
                if (control.kind != .resync_complete or
                    control.sequence != scene.next_sequence.? - 1)
                    return error.IncompleteResync;
                break;
            },
            .frame => |message| {
                defer gpa.free(message);
                const decoded = try protocol.decodeEnvelope(message);
                const envelope = decoded.envelope;
                try scene.apply(message);
                if (config.mode == .emacs_epxl_ime_commit and
                    syncTextInputArea(window, &scene) == .failed)
                    return error.TextInputAreaNotAccepted;
                if (config.selection_owner_smoke) {
                    if (envelope.message_type == protocol.Message.selection_owner_set and
                        scene.selection_kind != null and
                        scene.selection_generation == 1 and
                        scene.selection_flags & protocol.SelectionOwnerFlags.export_to_platform != 0)
                    {
                        selection_owner_set_seen = true;
                        try setPlatformPrimarySelection("Proto-UI primary");
                        if (!SDL_HasPrimarySelectionText()) return error.PrimarySelectionUnavailable;
                        if (SDL_GetPrimarySelectionText()) |owned| {
                            initial_platform_claimed =
                                std.mem.eql(u8, std.mem.span(owned), "Proto-UI primary");
                            SDL_free(owned);
                        }
                    }
                    if (envelope.message_type == protocol.Message.selection_owner_clear and
                        scene.selection_kind == null and
                        scene.selection_generation == 0)
                    {
                        selection_owner_clear_seen = true;
                        try clearPlatformPrimarySelection();
                        clear_platform_released = !SDL_HasPrimarySelectionText();
                    }
                    if (envelope.message_type == protocol.Message.selection_lost and
                        scene.selection_kind == null and
                        scene.selection_generation == 0)
                    {
                        const lost = try protocol.decodeSelectionLost(decoded.bytes);
                        if (lost.kind == .primary and lost.generation == 1 and
                            lost.reason == .owner_cancelled)
                        {
                            selection_lost_seen = true;
                            try clearPlatformPrimarySelection();
                            lost_platform_released = !SDL_HasPrimarySelectionText();
                        }
                    }
                    if (envelope.message_type == protocol.Message.selection_owner_set and
                        scene.selection_kind != null and
                        scene.selection_generation == 2 and
                        scene.selection_flags & protocol.SelectionOwnerFlags.export_to_platform != 0)
                    {
                        selection_replacement_seen = true;
                        try setPlatformPrimarySelection("Proto-UI replacement");
                        if (!SDL_HasPrimarySelectionText()) return error.PrimarySelectionUnavailable;
                        if (SDL_GetPrimarySelectionText()) |owned| {
                            replacement_platform_claimed =
                                std.mem.eql(u8, std.mem.span(owned), "Proto-UI replacement");
                            SDL_free(owned);
                        }
                    }
                }
                if (config.selection_transfer_smoke) {
                    if (envelope.message_type == protocol.Message.selection_owner_set and
                        scene.selection_kind != null and
                        scene.selection_generation == 1)
                    {
                        selection_transfer_owner_seen = true;
                    }
                    if (envelope.message_type == protocol.Message.selection_request and
                        scene.selection_transfer != null and
                        scene.selection_transfer.?.request_id == 9001 and
                        scene.selection_transfer.?.status == .waiting and
                        std.mem.eql(u8, scene.selection_transfer.?.targetSlice(), "UTF8_STRING"))
                    {
                        selection_transfer_request_seen = true;
                    }
                    if (envelope.message_type == protocol.Message.selection_data and
                        scene.selection_transfer != null and
                        scene.selection_transfer.?.request_id == 9001 and
                        scene.selection_transfer.?.status == .completed and
                        scene.selection_flags & protocol.SelectionOwnerFlags.export_to_platform != 0 and
                        std.mem.eql(u8, scene.selection_transfer.?.dataSlice(), "Proto-UI transfer"))
                    {
                        selection_transfer_data_seen = true;
                        try setPlatformPrimarySelection(scene.selection_transfer.?.dataSlice());
                        if (!SDL_HasPrimarySelectionText()) return error.PrimarySelectionUnavailable;
                        if (SDL_GetPrimarySelectionText()) |owned| {
                            transfer_platform_claimed =
                                std.mem.eql(u8, std.mem.span(owned), "Proto-UI transfer");
                            SDL_free(owned);
                        }
                    }
                    if (envelope.message_type == protocol.Message.selection_request and
                        scene.selection_transfer != null and
                        scene.selection_transfer.?.request_id == 9002 and
                        scene.selection_transfer.?.status == .waiting and
                        std.mem.eql(u8, scene.selection_transfer.?.targetSlice(), "STRING"))
                    {
                        selection_error_request_seen = true;
                    }
                    if (envelope.message_type == protocol.Message.selection_error and
                        scene.selection_transfer != null and
                        scene.selection_transfer.?.request_id == 9002 and
                        scene.selection_transfer.?.status == .failed and
                        scene.selection_transfer.?.error_reason.? == .conversion_failed and
                        std.mem.eql(u8, scene.selection_transfer.?.errorSlice(), "conversion unavailable"))
                    {
                        selection_error_seen = true;
                    }
                    if (envelope.message_type == protocol.Message.selection_owner_clear and
                        scene.selection_kind == null and
                        scene.selection_transfer == null)
                    {
                        selection_transfer_clear_seen = true;
                        try clearPlatformPrimarySelection();
                        transfer_platform_released = !SDL_HasPrimarySelectionText();
                    }
                }
                if (envelope.message_type == protocol.Message.frame_title) {
                    if (scene.title) |title| {
                        SDL_SetWindowTitle(window, title.ptr);
                        title_applied = std.mem.eql(
                            u8,
                            std.mem.span(SDL_GetWindowTitle(window)),
                            title,
                        );
                    }
                }
                if (envelope.message_type == protocol.Message.frame_update) {
                    try deliveryAllowed(delivery, negotiated.effective);
                    const outcome = try sendDeliveryEvent(gpa, delivery, config, &writer, &reader, envelope);
                    if (outcome == .delivered) {
                        switch (outcome.delivered.event) {
                            .scrollbar_event => scrollbar_event_delivered = true,
                            else => {},
                        }
                    }
                }
                try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = envelope.sequence });
                try writer.interface.flush();
            },
        }
    }

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
    var primary_copy_exact = false;
    var primary_paste_queued = false;
    var pointer_release_delivered = false;
    var wheel_ticks_delivered: i32 = 0;
    var horizontal_wheel_ticks_delivered: i32 = 0;
    var expected_monitor_id: SDL_DisplayID = 0;
    var expected_bounds: SDL_Rect = undefined;
    var initial_ime_placement: ?TextInputPlacement = null;
    var ime_event_delivered = false;
    var ime_area_refreshes: usize = 0;
    if (config.mode == .emacs_epxl_ime_commit) {
        // Seed the real SDL event queue.  pollEpxlInteractiveInput receives the
        // committed text through SDL polling before it enters DeliveryJournal.
        var synthetic = textEvent("你好");
        synthetic.text.window_id = SDL_GetWindowID(window);
        if (!SDL_PushEvent(&synthetic)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_dnd) {
        if (!negotiated.effective.contains(.dnd_bounded_v1))
            return error.DndCapabilityNotNegotiated;
        // Seed the real SDL event queue with one complete bounded drop.
        const drop_window_id = SDL_GetWindowID(window);
        if (drop_window_id == 0) return error.InvalidSdlWindowId;
        var drop_begin = dropEvent(SDL_EVENT_DROP_BEGIN, 0, 0, null);
        drop_begin.drop.window_id = drop_window_id;
        if (!SDL_PushEvent(&drop_begin)) return sdlFail("SDL_PushEvent");
        var position = dropEvent(SDL_EVENT_DROP_POSITION, 12, 6, null);
        position.drop.window_id = drop_window_id;
        if (!SDL_PushEvent(&position)) return sdlFail("SDL_PushEvent");
        var text = dropEvent(SDL_EVENT_DROP_TEXT, 12, 6, dnd_drop_text);
        text.drop.window_id = drop_window_id;
        if (!SDL_PushEvent(&text)) return sdlFail("SDL_PushEvent");
        // A second position after the payload is known: the first is reported
        // and the second is coalesced away because the journal is busy.
        var later_position = dropEvent(SDL_EVENT_DROP_POSITION, 20, 10, null);
        later_position.drop.window_id = drop_window_id;
        if (!SDL_PushEvent(&later_position)) return sdlFail("SDL_PushEvent");
        var complete = dropEvent(SDL_EVENT_DROP_COMPLETE, 12, 6, null);
        complete.drop.window_id = drop_window_id;
        if (!SDL_PushEvent(&complete)) return sdlFail("SDL_PushEvent");
    }
    if (config.interactive_synthetic) {
        // Seed the real SDL event queue so headless automation validates the
        // same input translation path as an operator typing in the window.
        var synthetic = textEvent("XY");
        if (!SDL_PushEvent(&synthetic)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_theme_event) {
        var theme_changed: SDL_Event = std.mem.zeroes(SDL_Event);
        theme_changed.type = SDL_EVENT_SYSTEM_THEME_CHANGED;
        if (!SDL_PushEvent(&theme_changed)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_focus_events) {
        const window_id = SDL_GetWindowID(window);
        var focus_gained = windowEvent(input_policy.SDL_EVENT_WINDOW_FOCUS_GAINED, window_id, 0, 0);
        if (!SDL_PushEvent(&focus_gained)) return sdlFail("SDL_PushEvent");
        var focus_lost = windowEvent(input_policy.SDL_EVENT_WINDOW_FOCUS_LOST, window_id, 0, 0);
        if (!SDL_PushEvent(&focus_lost)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_window_resize) {
        var resized = windowEvent(
            input_policy.SDL_EVENT_WINDOW_RESIZED,
            SDL_GetWindowID(window),
            720,
            480,
        );
        if (!SDL_PushEvent(&resized)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_window_move) {
        var moved = windowEvent(
            input_policy.SDL_EVENT_WINDOW_MOVED,
            SDL_GetWindowID(window),
            32,
            24,
        );
        if (!SDL_PushEvent(&moved)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_window_maximize) {
        var maximized = windowEvent(
            input_policy.SDL_EVENT_WINDOW_MAXIMIZED,
            SDL_GetWindowID(window),
            0,
            0,
        );
        if (!SDL_PushEvent(&maximized)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_window_fullscreen) {
        // SDL fullscreen notifications report completed transitions; inject
        // the validated request itself for deterministic request-to-Emacs
        // evidence.
        try delivery.pushWindow(.{
            .kind = .fullscreen,
            .sdl_window_id = SDL_GetWindowID(window),
        });
    }
    if (config.synthetic_window_minimize_restore) {
        const window_id = SDL_GetWindowID(window);
        var minimized = windowEvent(
            input_policy.SDL_EVENT_WINDOW_MINIMIZED,
            window_id,
            0,
            0,
        );
        if (!SDL_PushEvent(&minimized)) return sdlFail("SDL_PushEvent");
        var restored = windowEvent(
            input_policy.SDL_EVENT_WINDOW_RESTORED,
            window_id,
            0,
            0,
        );
        if (!SDL_PushEvent(&restored)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_monitor_change) {
        expected_monitor_id = SDL_GetDisplayForWindow(window);
        if (expected_monitor_id == 0 or
            !SDL_GetDisplayBounds(expected_monitor_id, &expected_bounds))
            return error.MonitorBoundsUnavailable;
        var scale_changed = windowEvent(
            input_policy.SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED,
            SDL_GetWindowID(window),
            @intCast(expected_monitor_id),
            0,
        );
        if (!SDL_PushEvent(&scale_changed)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_copy) {
        var synthetic = keyboardEvent(input_policy.SDL_SCANCODE_C, true, input_policy.sdl_ctrl_modifiers);
        if (!SDL_PushEvent(&synthetic)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_clipboard_unicode) {
        if (!SDL_SetClipboardText("你好")) return sdlFail("SDL_SetClipboardText");
        if (config.synthetic_primary_selection) {
            if (!SDL_SetPrimarySelectionText("stale")) return sdlFail("SDL_SetPrimarySelectionText");
        }
        var paste = keyboardEvent(input_policy.SDL_SCANCODE_V, true, input_policy.sdl_ctrl_modifiers);
        if (!SDL_PushEvent(&paste)) return sdlFail("SDL_PushEvent");
        var copy = keyboardEvent(input_policy.SDL_SCANCODE_C, true, input_policy.sdl_ctrl_modifiers);
        if (!SDL_PushEvent(&copy)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_wheel) {
        var down = wheelEvent(0, 1);
        if (!SDL_PushEvent(&down)) return sdlFail("SDL_PushEvent");
        if (!config.synthetic_viewport) {
            var up = wheelEvent(0, -1);
            if (!SDL_PushEvent(&up)) return sdlFail("SDL_PushEvent");
            var right = wheelEvent(1, 0);
            if (!SDL_PushEvent(&right)) return sdlFail("SDL_PushEvent");
            var left = wheelEvent(-1, 0);
            if (!SDL_PushEvent(&left)) return sdlFail("SDL_PushEvent");
        }
    }
    if (config.synthetic_pointer_selection) {
        var press = pointerButtonEvent(0, 12, SDL_EVENT_MOUSE_BUTTON_DOWN, true, 1, 1);
        if (!SDL_PushEvent(&press)) return sdlFail("SDL_PushEvent");
        var drag = pointerMotionEventV2(60, 12, input_policy.pointer_button_left, 0);
        if (!SDL_PushEvent(&drag)) return sdlFail("SDL_PushEvent");
        var release = pointerButtonEvent(60, 12, SDL_EVENT_MOUSE_BUTTON_UP, false, 1, 1);
        if (!SDL_PushEvent(&release)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_pointer_middle_paste) {
        var press = pointerButtonEvent(60, 12, SDL_EVENT_MOUSE_BUTTON_DOWN, true, 2, 1);
        if (!SDL_PushEvent(&press)) return sdlFail("SDL_PushEvent");
        var release = pointerButtonEvent(60, 12, SDL_EVENT_MOUSE_BUTTON_UP, false, 2, 1);
        if (!SDL_PushEvent(&release)) return sdlFail("SDL_PushEvent");
    }
    if (config.synthetic_pointer) {
        var idle_motion = mouseMotionEvent(8, 12, 0);
        if (!SDL_PushEvent(&idle_motion)) return sdlFail("SDL_PushEvent");
        var press = mouseButtonEvent(64, 12, SDL_EVENT_MOUSE_BUTTON_DOWN, true);
        if (!SDL_PushEvent(&press)) return sdlFail("SDL_PushEvent");
        var drag_motion = mouseMotionEvent(120, 12, 1);
        if (!SDL_PushEvent(&drag_motion)) return sdlFail("SDL_PushEvent");
        var release = mouseButtonEvent(120, 12, SDL_EVENT_MOUSE_BUTTON_UP, false);
        if (!SDL_PushEvent(&release)) return sdlFail("SDL_PushEvent");
    }
    var scrollbar_drag: input_policy.ScrollbarDragTracker = .{};
    var toolbar_press: ToolbarPressTracker = .{};
    var dnd_tracker: DndTracker = .{};
    var monitor_refresh_needed = false;
    try pollEpxlInteractiveInput(delivery, &scrollbar_drag, &toolbar_press, &dnd_tracker, config, window, &retained_frame, &scene, &frame_gate, negotiated.effective, &input_dirty, &primary_paste_queued, &monitor_refresh_needed);
    try deliveryAllowed(delivery, negotiated.effective);
    if (config.mode == .emacs_epxl_menu_apply) {
        // Seed one bounded, undoable edit so the real "Undo" menu item has
        // something to undo when the round trip selects it.
        try delivery.pushText("zz");
    }
    if (config.mode == .emacs_epxl_graphic) {
        // Split the real frame so both an active and an inactive mode line
        // exist; the two faces have different colors in the default theme.
        if (!negotiated.effective.contains(.input_composite_key_command_v1))
            return error.CompositeCommandCapabilityNotNegotiated;
        emacs_key_command_translator.reset();
        try delivery.pushKeyV2(input_policy.translateFullKey(27, "x", true, false, input_policy.sdl_kmod_lctrl, 0).?);
        try delivery.pushKeyV2(input_policy.translateFullKey(31, "2", true, false, 0, 0).?);
    }
    if (config.mode == .emacs_epxl_mouse) {
        // One real pointer sample over the first body row drives the live
        // mouse-face resolution path in the publisher.
        if (!negotiated.effective.contains(.input_pointer_v2))
            return error.PointerV2CapabilityNotNegotiated;
        try delivery.pushPointerV2(.{ .phase = .motion, .buttons = 0, .x = 2, .y = 1 });
    }

    var quit = false;
    const started_ticks = SDL_GetTicks();
    const timed_frontend = config.auto_quit_ms != 0;
    while (!quit and (!timed_frontend or SDL_GetTicks() - started_ticks < config.auto_quit_ms)) {
        const message = (live.readFrame(&reader.interface, gpa) catch |err| {
            if (timed_frontend and SDL_GetTicks() - started_ticks >= config.auto_quit_ms) break;
            return err;
        }) orelse break;
        defer gpa.free(message);
        const envelope = (try protocol.decodeEnvelope(message)).envelope;
        try scene.apply(message);
        // The mode line's own segments arrive as runs on every publish.
        if (config.mode == .emacs_epxl_graphic) {
            for (scene.glyph_runs.items) |run| {
                if (!graphic_mode_line_bold and run.mode_line and run.style & 1 != 0)
                    graphic_mode_line_bold = true;
                if (run.header_line) graphic_header_line_run = true;
                if (run.tab_line) graphic_tab_line_run = true;
                if (run.partial) graphic_partial_run = true;
            }
            // The header and tab lines carry their own segment faces as runs.
            // Each run is drawn with its face color, which can only come from
            // the run, so a matching draw also proves the plain aux text was
            // suppressed.  Sample per message: the run is gone once the next
            // authoritative frame update clears the glyph-run table.
            if ((graphic_header_line_run and !graphic_header_line_drawn) or
                (graphic_tab_line_run and !graphic_tab_line_drawn))
            {
                var output_width: c_int = 0;
                var output_height: c_int = 0;
                SDL_GetWindowSize(window, &output_width, &output_height);
                if (output_width > 0 and output_height > 0) {
                    var probe_list: renderer_policy.DrawList = .{ .allocator = gpa };
                    defer probe_list.deinit();
                    try buildSceneDrawList(&scene, &probe_list, @intCast(output_width), @intCast(output_height));
                    for (scene.glyph_runs.items) |run| {
                        if (!run.header_line and !run.tab_line) continue;
                        const run_face = scene.faces.lookup(run.face_id) orelse continue;
                        if (!run_face.payload.presence.foreground) continue;
                        const want = run_face.payload.foreground;
                        for (probe_list.commands.items) |command| switch (command) {
                            .unicode_text => |draw| {
                                if (!std.mem.eql(u8, draw.bytes, run.text)) continue;
                                const color = draw.color;
                                if (color.r != want[0] or color.g != want[1] or color.b != want[2]) continue;
                                if (run.header_line) graphic_header_line_drawn = true;
                                if (run.tab_line) graphic_tab_line_drawn = true;
                            },
                            else => {},
                        };
                    }
                }
            }
        }
        // The mouse-face highlight arrives as its own message, so sample it on
        // every apply rather than only while a frame update holds.
        if (config.mode == .emacs_epxl_mouse) {
            var seen: usize = 0;
            for (scene.mouse_highlights[0..scene.mouse_highlight_count]) |highlight| {
                const is_mouse = highlight.face_id == facts.mouse_face_id or
                    (highlight.face_id >= facts.mouse_rect_face_base_id and
                        highlight.face_id < facts.mouse_rect_face_base_id + facts.max_mouse_rects);
                if (!is_mouse) continue;
                if (scene.faces.lookup(highlight.face_id)) |mouse_face| {
                    if (mouse_face.payload.presence.background and
                        mouse_face.payload.background[0] == 0x33 and
                        mouse_face.payload.background[1] == 0xaa and
                        mouse_face.payload.background[2] == 0x77)
                    {
                        mouse_face_seen = true;
                        seen += 1;
                    }
                }
            }
            if (seen > mouse_face_rects) mouse_face_rects = seen;
        }
        if ((config.mode == .emacs_epxl_scrollbar or
            config.mode == .emacs_epxl_scroll_interaction) and
            envelope.message_type == protocol.Message.scrollbar_state and
            scene.scroll_states.items.len == 1)
        {
            // FRAME_UPDATE is authoritative window state and replaces the
            // scroll state, so sample it while it holds rather than assuming
            // the timing race with the smoke deadline leaves it at the end.
            const state = scene.scroll_states.items[0];
            if (!scrollbar_observed and state.track_width == 12 and
                state.content_size == 200 and state.viewport_size == 32 and
                state.position == 10)
            {
                if (frontend.scrollbarLayout(&scene, state.window_id)) |layout| {
                    const ratio = @as(f32, @floatFromInt(state.viewport_size)) /
                        @as(f32, @floatFromInt(state.content_size));
                    scrollbar_observed =
                        @abs(layout.thumb_height - layout.track_height * ratio) <= 0.001;
                    if (scrollbar_observed and
                        config.mode == .emacs_epxl_scroll_interaction and !scroll_page_seeded)
                    {
                        if (scene.frame_header) |header| {
                            scroll_page_seeded = true;
                            const scale = sceneWindowScale(window, header);
                            if (scale > 0) {
                                // Middle of the trough below the thumb: one
                                // bounded page intent through the real path.
                                const logical_x = layout.track_x + layout.track_width / 2;
                                const logical_y =
                                    (layout.thumb_y + layout.thumb_height +
                                        layout.track_y + layout.track_height) / 2;
                                var press = mouseButtonEvent(
                                    logical_x * scale,
                                    logical_y * scale,
                                    SDL_EVENT_MOUSE_BUTTON_DOWN,
                                    true,
                                );
                                if (!SDL_PushEvent(&press)) return sdlFail("SDL_PushEvent");
                            }
                        }
                    }
                }
            }
            if (config.mode == .emacs_epxl_scroll_interaction and state.position == 42)
                scroll_page_position = state.position;
            if (config.mode == .emacs_epxl_scroll_interaction and
                state.position == 42 and !scroll_drag_seeded)
            {
                // The republished state moved the thumb; drag it by four
                // logical units through the same scaled live path.
                if (frontend.scrollbarLayout(&scene, state.window_id)) |layout| {
                    if (scene.frame_header) |header| {
                        const scale = sceneWindowScale(window, header);
                        if (scale > 0) {
                            scroll_drag_seeded = true;
                            const thumb_x = layout.track_x + layout.track_width / 2;
                            const thumb_y = layout.thumb_y + layout.thumb_height / 2;
                            var press = mouseButtonEvent(
                                thumb_x * scale,
                                thumb_y * scale,
                                SDL_EVENT_MOUSE_BUTTON_DOWN,
                                true,
                            );
                            if (!SDL_PushEvent(&press)) return sdlFail("SDL_PushEvent");
                            var motion = mouseMotionEvent(
                                thumb_x * scale,
                                (thumb_y + 4) * scale,
                                SDL_BUTTON_LMASK,
                            );
                            if (!SDL_PushEvent(&motion)) return sdlFail("SDL_PushEvent");
                            var release = mouseButtonEvent(
                                thumb_x * scale,
                                (thumb_y + 4) * scale,
                                SDL_EVENT_MOUSE_BUTTON_UP,
                                false,
                            );
                            if (!SDL_PushEvent(&release)) return sdlFail("SDL_PushEvent");
                        }
                    }
                }
            }
            if (config.mode == .emacs_epxl_scroll_interaction and state.position == 46)
                scroll_drag_position = state.position;
        }
        if (config.mode == .emacs_epxl_hscroll and
            envelope.message_type == protocol.Message.scrollbar_state and
            scene.scroll_states.items.len == 1)
        {
            const state = scene.scroll_states.items[0];
            if (!hscroll_observed and
                state.flags & frontend.WindowScrollFlags.horizontal_visible != 0 and
                state.track_width == 8 and state.content_size == 100 and
                state.viewport_size == 80 and state.position == 5)
            {
                if (frontend.horizontalScrollbarLayout(&scene, state.window_id)) |layout| {
                    if (scene.frame_header) |header| {
                        const scale = sceneWindowScale(window, header);
                        if (scale > 0) {
                            hscroll_observed = true;
                            // Press the live thumb and drag it ten columns right
                            // through the same scaled pointer path.
                            const thumb_x = layout.thumb_x + layout.thumb_width / 2;
                            const thumb_y = layout.track_y + layout.track_height / 2;
                            var press = mouseButtonEvent(
                                thumb_x * scale,
                                thumb_y * scale,
                                SDL_EVENT_MOUSE_BUTTON_DOWN,
                                true,
                            );
                            if (!SDL_PushEvent(&press)) return sdlFail("SDL_PushEvent");
                            var motion = mouseMotionEvent(
                                (thumb_x + 10) * scale,
                                thumb_y * scale,
                                SDL_BUTTON_LMASK,
                            );
                            if (!SDL_PushEvent(&motion)) return sdlFail("SDL_PushEvent");
                            var release = mouseButtonEvent(
                                (thumb_x + 10) * scale,
                                thumb_y * scale,
                                SDL_EVENT_MOUSE_BUTTON_UP,
                                false,
                            );
                            if (!SDL_PushEvent(&release)) return sdlFail("SDL_PushEvent");
                        }
                    }
                }
            }
            if (hscroll_observed and state.position == 15) hscroll_position = state.position;
        }
        if (config.mode == .emacs_epxl_graphic) {
            // FRAME_UPDATE is authoritative and clears the scroll state, so
            // sample the real scroll-bar width while it holds.
            for (scene.scroll_states.items) |state| {
                if (state.flags & frontend.WindowScrollFlags.vertical_visible != 0)
                    graphic_scroll_width = state.track_width;
            }
            for (scene.fringes.items) |fringe| {
                switch (fringe.side) {
                    .left => graphic_fringe_left = fringe.width,
                    .right => graphic_fringe_right = fringe.width,
                }
            }
            // The frame's real font pixel size sizes the text font (the line
            // height is the fallback), so glyphs match the frame's own text.
            const published_size: ?i32 = if (scene.strings.lookup(facts.default_font_size_string_id)) |resource|
                (std.fmt.parseInt(i32, resource.bytes, 10) catch null)
            else
                null;
            if (published_size) |size|
                unicode_text_renderer.adoptTextSize(size)
            else if (scene.rows.items.len != 0)
                unicode_text_renderer.adoptTextSize(scene.rows.items[0].height);
            // The mirror must carry a real screenful of the window, not just a
            // handful of lines.
            graphic_max_text_lines = @max(graphic_max_text_lines, scene.text.items.len);
            // The first line's real font-lock runs must arrive as bounded
            // face-colored glyph runs with at least two distinct colors.
            if (scene.glyph_runs.items.len >= 2) {
                var colors: [8][4]u8 = undefined;
                var color_count: usize = 0;
                for (scene.glyph_runs.items) |run| {
                    const face = scene.faces.lookup(run.face_id) orelse continue;
                    if (!face.payload.presence.foreground) continue;
                    var known = false;
                    for (colors[0..color_count]) |existing| {
                        if (std.meta.eql(existing, face.payload.foreground)) known = true;
                    }
                    if (!known and color_count < colors.len) {
                        colors[color_count] = face.payload.foreground;
                        color_count += 1;
                    }
                }
                if (color_count >= 2) {
                    graphic_runs_seen = true;
                    // Count the visible rows with two or more distinct run
                    // colors while the runs hold: the profile pins three Lisp
                    // lines, so real font-lock must color more than one row.
                    var rows: [8]u32 = undefined;
                    var row_colors: [8][4][4]u8 = undefined;
                    var row_color_count: [8]usize = .{0} ** 8;
                    var tracked: usize = 0;
                    for (scene.glyph_runs.items) |run| {
                        const face = scene.faces.lookup(run.face_id) orelse continue;
                        if (!face.payload.presence.foreground) continue;
                        var slot: ?usize = null;
                        for (rows[0..tracked], 0..) |row, index| {
                            if (row == run.row_index) {
                                slot = index;
                                break;
                            }
                        }
                        if (slot == null) {
                            if (tracked == rows.len) continue;
                            rows[tracked] = run.row_index;
                            row_color_count[tracked] = 0;
                            slot = tracked;
                            tracked += 1;
                        }
                        const at = slot.?;
                        var known_color = false;
                        for (row_colors[at][0..row_color_count[at]]) |known| {
                            if (std.meta.eql(known, face.payload.foreground)) known_color = true;
                        }
                        if (!known_color and row_color_count[at] < 4) {
                            row_colors[at][row_color_count[at]] = face.payload.foreground;
                            row_color_count[at] += 1;
                        }
                    }
                    var fontified_rows: usize = 0;
                    for (row_color_count[0..tracked]) |count| {
                        if (count >= 2) fontified_rows += 1;
                    }
                    graphic_run_rows = @max(graphic_run_rows, fontified_rows);
                    if (!graphic_runs_colored) {
                        var output_width: c_int = 0;
                        var output_height: c_int = 0;
                        SDL_GetWindowSize(window, &output_width, &output_height);
                        if (output_width > 0 and output_height > 0) {
                            var probe_list: renderer_policy.DrawList = .{ .allocator = gpa };
                            defer probe_list.deinit();
                            try buildSceneDrawList(&scene, &probe_list, @intCast(output_width), @intCast(output_height));
                            var drawn: usize = 0;
                            for (colors[0..color_count]) |color| {
                                var found = false;
                                for (probe_list.commands.items) |command| switch (command) {
                                    .text => |draw| {
                                        if (draw.color) |draw_color| {
                                            if (draw_color.r == color[0] and draw_color.g == color[1] and
                                                draw_color.b == color[2]) found = true;
                                        }
                                    },
                                    .unicode_text => |draw| {
                                        if (draw.color.r == color[0] and draw.color.g == color[1] and
                                            draw.color.b == color[2]) found = true;
                                    },
                                    else => {},
                                };
                                if (found) drawn += 1;
                            }
                            if (drawn >= 2) graphic_runs_colored = true;
                        }
                    }
                    // A published run face background must reach a fill command.
                    if (!graphic_run_background_colored) {
                        var run_background: ?[4]u8 = null;
                        for (scene.glyph_runs.items) |run| {
                            const face = scene.faces.lookup(run.face_id) orelse continue;
                            // An inverse run fills with its foreground half.
                            if (face.payload.inverse_video) continue;
                            if (face.payload.presence.background) {
                                run_background = face.payload.background;
                                break;
                            }
                        }
                        if (run_background) |color| {
                            var output_width: c_int = 0;
                            var output_height: c_int = 0;
                            SDL_GetWindowSize(window, &output_width, &output_height);
                            if (output_width > 0 and output_height > 0) {
                                var probe_list: renderer_policy.DrawList = .{ .allocator = gpa };
                                defer probe_list.deinit();
                                try buildSceneDrawList(&scene, &probe_list, @intCast(output_width), @intCast(output_height));
                                for (probe_list.commands.items) |command| switch (command) {
                                    .fill => |fill| {
                                        if (fill.color.r == color[0] and fill.color.g == color[1] and
                                            fill.color.b == color[2]) graphic_run_background_colored = true;
                                    },
                                    else => {},
                                };
                            }
                        }
                    }
                    // A published run face underline must reach a bar fill.
                    if (!graphic_run_underline_drawn) {
                        var underline_color: ?[4]u8 = null;
                        for (scene.glyph_runs.items) |run| {
                            const face = scene.faces.lookup(run.face_id) orelse continue;
                            if (face.payload.underline != .unspecified and
                                face.payload.presence.underline_color)
                                underline_color = face.payload.underline_color;
                        }
                        if (underline_color) |color| {
                            var output_width: c_int = 0;
                            var output_height: c_int = 0;
                            SDL_GetWindowSize(window, &output_width, &output_height);
                            if (output_width > 0 and output_height > 0) {
                                var probe_list: renderer_policy.DrawList = .{ .allocator = gpa };
                                defer probe_list.deinit();
                                try buildSceneDrawList(&scene, &probe_list, @intCast(output_width), @intCast(output_height));
                                for (probe_list.commands.items) |command| switch (command) {
                                    .fill => |fill| {
                                        if (fill.rect.height <= 3 and
                                            fill.color.r == color[0] and fill.color.g == color[1] and
                                            fill.color.b == color[2]) graphic_run_underline_drawn = true;
                                    },
                                    else => {},
                                };
                            }
                        }
                    }
                    // An inverse-video run must fill with its foreground half.
                    if (!graphic_run_inverse_drawn) {
                        var inverse_fill: ?[4]u8 = null;
                        for (scene.glyph_runs.items) |run| {
                            const face = scene.faces.lookup(run.face_id) orelse continue;
                            if (face.payload.inverse_video and face.payload.presence.foreground)
                                inverse_fill = face.payload.foreground;
                        }
                        if (inverse_fill) |color| {
                            var output_width: c_int = 0;
                            var output_height: c_int = 0;
                            SDL_GetWindowSize(window, &output_width, &output_height);
                            if (output_width > 0 and output_height > 0) {
                                var probe_list: renderer_policy.DrawList = .{ .allocator = gpa };
                                defer probe_list.deinit();
                                try buildSceneDrawList(&scene, &probe_list, @intCast(output_width), @intCast(output_height));
                                for (probe_list.commands.items) |command| switch (command) {
                                    .fill => |fill| {
                                        if (fill.color.r == color[0] and fill.color.g == color[1] and
                                            fill.color.b == color[2]) graphic_run_inverse_drawn = true;
                                    },
                                    else => {},
                                };
                            }
                        }
                    }
                    // A bold-italic run keeps its style bits into the draw list.
                    if (!graphic_run_style_drawn) {
                        var styled = false;
                        for (scene.glyph_runs.items) |run| {
                            if (run.style == 3) styled = true;
                        }
                        if (styled) {
                            var output_width: c_int = 0;
                            var output_height: c_int = 0;
                            SDL_GetWindowSize(window, &output_width, &output_height);
                            if (output_width > 0 and output_height > 0) {
                                var probe_list: renderer_policy.DrawList = .{ .allocator = gpa };
                                defer probe_list.deinit();
                                try buildSceneDrawList(&scene, &probe_list, @intCast(output_width), @intCast(output_height));
                                for (probe_list.commands.items) |command| switch (command) {
                                    .unicode_text => |draw| {
                                        if (draw.style == 3) graphic_run_style_drawn = true;
                                    },
                                    else => {},
                                };
                            }
                        }
                    }
                    if (!graphic_variable_font_drawn) {
                        var output_width: c_int = 0;
                        var output_height: c_int = 0;
                        SDL_GetWindowSize(window, &output_width, &output_height);
                        if (output_width > 0 and output_height > 0) {
                            var probe_list: renderer_policy.DrawList = .{ .allocator = gpa };
                            defer probe_list.deinit();
                            try buildSceneDrawList(&scene, &probe_list, @intCast(output_width), @intCast(output_height));
                            for (probe_list.commands.items) |command| switch (command) {
                                .unicode_text => |draw| {
                                    if (draw.style & 0x80 != 0) graphic_variable_font_drawn = true;
                                },
                                else => {},
                            };
                        }
                    }
                    // A split frame colors both windows: at least one run must
                    // belong to a window other than the first.
                    if (!graphic_multi_window_run and scene.windows.items.len > 1) {
                        for (scene.glyph_runs.items) |run| {
                            if (run.window_id != scene.windows.items[0].id)
                                graphic_multi_window_run = true;
                        }
                    }
                    // An overlay face outranks the text property, so its color
                    // must reach a run face.
                    if (!graphic_run_overlay_seen) {
                        for (scene.glyph_runs.items) |run| {
                            const face = scene.faces.lookup(run.face_id) orelse continue;
                            if (face.payload.presence.foreground and
                                face.payload.foreground[0] == 0xcc and
                                face.payload.foreground[1] == 0x55 and
                                face.payload.foreground[2] == 0x00)
                                graphic_run_overlay_seen = true;
                        }
                    }
                }
            }
            // The real active region must arrive as a bounded highlight using
            // the published region face.
            if (scene.mouse_highlight_count != 0) {
                graphic_region_seen = true;
                // A multi-line region arrives as one rectangle per displayed
                // row, so more than one region-colored fill proves the per-row
                // path rather than a single bounding box.
                graphic_region_rects = @max(graphic_region_rects, scene.mouse_highlight_count);
                if (!graphic_region_colored) {
                    if (scene.faces.lookup(facts.region_face_id)) |region_face| {
                        if (region_face.payload.presence.background) {
                            var output_width: c_int = 0;
                            var output_height: c_int = 0;
                            SDL_GetWindowSize(window, &output_width, &output_height);
                            if (output_width > 0 and output_height > 0) {
                                var probe_list: renderer_policy.DrawList = .{ .allocator = gpa };
                                defer probe_list.deinit();
                                try buildSceneDrawList(&scene, &probe_list, @intCast(output_width), @intCast(output_height));
                                for (probe_list.commands.items) |command| switch (command) {
                                    .fill => |fill| {
                                        if (fill.color.r == region_face.payload.background[0] and
                                            fill.color.g == region_face.payload.background[1] and
                                            fill.color.b == region_face.payload.background[2])
                                            graphic_region_colored = true;
                                    },
                                    else => {},
                                };
                            }
                        }
                    }
                }
            }
            // With the real split in place, the inactive window's mode line
            // must use the inactive face color.
            if (scene.mode_line_count >= 2) graphic_inactive_mode_line_seen = true;
            if (graphic_inactive_mode_line_seen and !graphic_inactive_mode_line_colored) {
                if (scene.faces.lookup(facts.mode_line_inactive_face_id)) |inactive| {
                    if (inactive.payload.presence.background) {
                        var output_width: c_int = 0;
                        var output_height: c_int = 0;
                        SDL_GetWindowSize(window, &output_width, &output_height);
                        if (output_width > 0 and output_height > 0) {
                            var probe_list: renderer_policy.DrawList = .{ .allocator = gpa };
                            defer probe_list.deinit();
                            try buildSceneDrawList(&scene, &probe_list, @intCast(output_width), @intCast(output_height));
                            for (probe_list.commands.items) |command| switch (command) {
                                .fill => |fill| {
                                    if (fill.color.r == inactive.payload.background[0] and
                                        fill.color.g == inactive.payload.background[1] and
                                        fill.color.b == inactive.payload.background[2])
                                        graphic_inactive_mode_line_colored = true;
                                },
                                else => {},
                            };
                        }
                    }
                }
            }
            // The frame's real font file, when it published one, replaces the
            // bundled fallback for the diagnostic text.
            if (scene.strings.lookup(facts.default_font_string_id)) |resource|
                unicode_text_renderer.adoptFontFile(resource.bytes);
            if (scene.strings.lookup(facts.variable_font_string_id)) |resource|
                unicode_text_renderer.adoptVariableFontFile(1, resource.bytes);
            for (0..facts.max_alt_font_families) |index| {
                const resource_id = facts.variable_font_string_id + 1 +
                    @as(u32, @intCast(index));
                if (scene.strings.lookup(resource_id)) |resource|
                    unicode_text_renderer.adoptVariableFontFile(@intCast(2 + index), resource.bytes);
            }
            if (graphic_wire_snapshot == null) {
                if (std.Io.Dir.cwd().readFileAlloc(
                    io,
                    config.facts_path,
                    gpa,
                    .limited(64 * 1024),
                )) |bytes| {
                    defer gpa.free(bytes);
                    graphic_wire_snapshot = facts.parseSnapshot(gpa, bytes) catch null;
                } else |_| {}
            }
            for (scene.glyph_runs.items) |run| {
                if (!run.variable_pitch) continue;
                graphic_variable_font_seen = true;
                const wire_index = run.run_id - facts.line_run_glyph_base_id;
                if (graphic_wire_snapshot) |wire| {
                    if (wire_index < wire.facts.line_runs.len) {
                        const line_run = wire.facts.line_runs[wire_index];
                        graphic_variable_metrics = line_run.pixel_x >= 0 and
                            run.x == graphic_fringe_left + line_run.pixel_x and
                            run.width == line_run.pixel_width;
                    }
                }
            }
            if (!graphic_fringe_drawn and scene.fringes.items.len != 0) {
                var output_width: c_int = 0;
                var output_height: c_int = 0;
                SDL_GetWindowSize(window, &output_width, &output_height);
                if (output_width > 0 and output_height > 0) {
                    var probe_list: renderer_policy.DrawList = .{ .allocator = gpa };
                    defer probe_list.deinit();
                    try buildSceneDrawList(&scene, &probe_list, @intCast(output_width), @intCast(output_height));
                    const fringe_color_match = if (scene.faces.lookup(facts.fringe_face_id)) |face|
                        if (face.payload.presence.background) face.payload.background else null
                    else
                        null;
                    for (probe_list.commands.items) |command| switch (command) {
                        .fill => |fill| {
                            if (fill.rect.width != @as(f32, @floatFromInt(graphic_fringe_left)) and
                                fill.rect.width != @as(f32, @floatFromInt(graphic_fringe_right))) continue;
                            if (fringe_color_match) |color| {
                                if (fill.color.r != color[0] or fill.color.g != color[1] or
                                    fill.color.b != color[2]) continue;
                            }
                            graphic_fringe_drawn = true;
                        },
                        else => {},
                    };
                }
            }
        }
        if (menu_mode and !menu_open_seeded) {
            // Once the real menu bar is in the scene, press the slot labelled
            // "Edit" through the same scaled pointer path an operator uses.
            if (frontend.menuBarLayout(&scene)) |bar| {
                for (bar.slots[0..bar.count]) |slot| {
                    if (!std.mem.eql(u8, slot.label, "Edit")) continue;
                    if (scene.frame_header) |header| {
                        const scale = sceneWindowScale(window, header);
                        if (scale > 0) {
                            menu_open_seeded = true;
                            const press_x = @as(f32, @floatFromInt(slot.x + @divTrunc(slot.width, 2))) * scale;
                            const press_y = @as(f32, @floatFromInt(@divTrunc(bar.strip_height, 2))) * scale;
                            var press = mouseButtonEvent(
                                press_x,
                                press_y,
                                SDL_EVENT_MOUSE_BUTTON_DOWN,
                                true,
                            );
                            if (!SDL_PushEvent(&press)) return sdlFail("SDL_PushEvent");
                        }
                    }
                    break;
                }
            }
        }
        if (menu_mode and menu_open_seeded) {
            // The backend answers the request with the real child rows of that
            // menu-bar item, so the live popup must own them; then choose the
            // first selectable row and require the backend to close the menu.
            if (!menu_popup_observed) {
                if (scene.menu_open) |open| {
                    if (scene.menu_model) |model| {
                        for (model.nodes) |*node| {
                            if (node.parent_item_id != open.item_id) continue;
                            if (std.mem.eql(u8, node.label[0..node.label_len], "Undo")) {
                                menu_popup_observed = true;
                                menu_popup_help = node.help_len != 0;
                            }
                            // The real Edit menu's Cut/Copy need an active mark,
                            // so the live model must carry a disabled row.
                            if (node.kind != .separator and
                                node.flags & protocol.MenuNodeFlags.enabled == 0)
                                menu_popup_disabled = true;
                            if (node.key_len != 0) menu_popup_key = true;
                            if (node.icon_image_id != 0 and
                                node.icon_image_generation != 0)
                            {
                                if (scene.images.lookup(node.icon_image_id)) |image| {
                                    menu_popup_icon = image.complete and
                                        image.generation == node.icon_image_generation;
                                }
                            }
                        }
                    }
                }
            }
            if (menu_popup_observed and !menu_row_pressed) {
                if (scene.menu_open != null) {
                    const bounds = frontend.menuPopupBounds(&scene) orelse
                        return error.MenuPopupBoundsUnavailable;
                    const rows = frontend.menuRows(&scene) orelse
                        return error.MenuPopupRowsUnavailable;
                    var chosen: ?usize = null;
                    for (rows.rows[0..rows.count], 0..) |row, index| {
                        if (!row.selectable) continue;
                        chosen = index;
                        break;
                    }
                    if (chosen) |index| {
                        if (scene.frame_header) |header| {
                            const scale = sceneWindowScale(window, header);
                            if (scale > 0) {
                                menu_row_pressed = true;
                                const row_x = bounds.x + bounds.width / 2;
                                const row_y = bounds.y +
                                    (@as(f32, @floatFromInt(index)) + 0.5) * bounds.row_height;
                                scene.menu_highlight_item =
                                    (frontend.menuRows(&scene) orelse return error.MenuPopupRowsUnavailable).rows[index].item_id;
                                if (menu_popup_help and !menu_help_drawn) {
                                    var help_list: renderer_policy.DrawList = .{ .allocator = gpa };
                                    defer help_list.deinit();
                                    buildSceneDrawList(&scene, &help_list, 80, 60) catch {};
                                    if (frontend.menuHelpTip(&scene)) |tip| {
                                        for (help_list.commands.items) |command| {
                                            const draw = switch (command) {
                                                .unicode_text => |draw| draw,
                                                else => continue,
                                            };
                                            for (tip.lines[0..tip.line_count]) |line| {
                                                if (std.mem.eql(u8, draw.bytes, line)) {
                                                    menu_help_drawn = true;
                                                    break;
                                                }
                                            }
                                        }
                                    }
                                }
                                var press = mouseButtonEvent(
                                    row_x * scale,
                                    row_y * scale,
                                    SDL_EVENT_MOUSE_BUTTON_DOWN,
                                    true,
                                );
                                if (!SDL_PushEvent(&press)) return sdlFail("SDL_PushEvent");
                            }
                        }
                    }
                }
            }
            if (menu_result_delivered and scene.menu_open == null)
                menu_popup_closed = true;
            // The live row keys must reach the same draw list the popup uses.
            if (menu_popup_help and !menu_help_drawn and scene.menu_open != null) {
                var help_list: renderer_policy.DrawList = .{ .allocator = gpa };
                defer help_list.deinit();
                buildSceneDrawList(&scene, &help_list, 80, 60) catch {};
                if (frontend.menuHelpTip(&scene)) |tip| {
                    for (help_list.commands.items) |command| {
                        const draw = switch (command) {
                            .unicode_text => |draw| draw,
                            else => continue,
                        };
                        for (tip.lines[0..tip.line_count]) |line| {
                            if (std.mem.eql(u8, draw.bytes, line)) {
                                menu_help_drawn = true;
                                break;
                            }
                        }
                    }
                }
            }
            if (menu_popup_key and !menu_key_drawn) {
                var output_width: c_int = 0;
                var output_height: c_int = 0;
                SDL_GetWindowSize(window, &output_width, &output_height);
                if (output_width > 0 and output_height > 0) {
                    var probe_list: renderer_policy.DrawList = .{ .allocator = gpa };
                    defer probe_list.deinit();
                    buildSceneDrawList(&scene, &probe_list, @intCast(output_width), @intCast(output_height)) catch {};
                    if (scene.menu_model) |model| {
                        for (model.nodes) |*node| {
                            if (node.key_len == 0) continue;
                            const key = node.key[0..node.key_len];
                            for (probe_list.commands.items) |command| switch (command) {
                                .unicode_text => |draw| {
                                    if (std.mem.eql(u8, draw.bytes, key)) menu_key_drawn = true;
                                },
                                else => {},
                            };
                        }
                    }
                }
            }
            if (config.mode == .emacs_epxl_menu_apply) {
                // The resolved command really ran: the seeded edit appears
                // before the round trip and is gone after "Undo" was chosen.
                if (!menu_apply_edited and sceneHasText(&scene, "zz"))
                    menu_apply_edited = true;
                if (menu_apply_edited and !sceneHasText(&scene, "zz"))
                    menu_apply_undone = true;
            }
        }
        if (config.mode == .emacs_epxl_face and !face_text_drawn) {
            // FRAME_UPDATE is authoritative window state, so the binding is only
            // visible between a window-face message and the next update; sample
            // it while it holds instead of assuming it survives to the deadline.
            if (scene.faces.lookup(facts.default_face_id)) |face| {
                const expected_foreground = [4]u8{ 0x10, 0x20, 0x30, 255 };
                if (std.meta.eql(face.payload.foreground, expected_foreground)) {
                    for (scene.window_faces.items) |state| {
                        if (state.face_id != facts.default_face_id or
                            state.face_generation != face.generation) continue;
                        face_binding_observed = true;
                        var output_width: c_int = 0;
                        var output_height: c_int = 0;
                        SDL_GetWindowSize(window, &output_width, &output_height);
                        if (output_width > 0 and output_height > 0) {
                            var probe_list: renderer_policy.DrawList = .{ .allocator = gpa };
                            defer probe_list.deinit();
                            try buildSceneDrawList(&scene, &probe_list, @intCast(output_width), @intCast(output_height));
                            for (probe_list.commands.items) |command| switch (command) {
                                .text => |draw| {
                                    if (draw.color) |color| {
                                        if (color.r == expected_foreground[0] and
                                            color.g == expected_foreground[1] and
                                            color.b == expected_foreground[2])
                                            face_text_drawn = true;
                                    }
                                },
                                .unicode_text => |draw| {
                                    if (draw.color.r == expected_foreground[0] and
                                        draw.color.g == expected_foreground[1] and
                                        draw.color.b == expected_foreground[2])
                                        face_text_drawn = true;
                                },
                                else => {},
                            };
                        }
                        break;
                    }
                }
            }
        }
        if (config.mode == .emacs_epxl_ime_commit and
            syncTextInputArea(window, &scene) == .failed)
            return error.TextInputAreaNotAccepted;
        if (config.synthetic_focus_events) {
            if (scene.frames.lookup(1)) |frame| {
                if (frame.focused and !observed_focus_gained) {
                    observed_focus_gained = true;
                } else if (observed_focus_gained and !frame.focused) {
                    observed_focus_transition = true;
                }
            }
        }
        if (envelope.message_type == protocol.Message.frame_title) {
            if (scene.title) |title| {
                SDL_SetWindowTitle(window, title.ptr);
                title_applied = std.mem.eql(
                    u8,
                    std.mem.span(SDL_GetWindowTitle(window)),
                    title,
                );
            }
        }
        if (monitor_refresh_needed and try refreshSceneMonitorFromSDL(window, &scene))
            monitor_refresh_needed = false;
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
                    .wheel => |wheel| {
                        wheel_ticks_delivered += @abs(wheel.y);
                        horizontal_wheel_ticks_delivered += @abs(wheel.x);
                    },
                    .scrollbar_event => scrollbar_event_delivered = true,
                    .menu_open_request => |request| menu_open_request_delivered = request,
                    .menu_result => |result| {
                        if (result.item_id != 0) menu_result_delivered = true;
                    },
                    .focus => |focus| switch (focus.phase) {
                        .gained => focus_gained_delivered = true,
                        .lost => focus_lost_delivered = true,
                    },
                    .window => |request| {
                        const resize_matches = request.kind == .resize and
                            config.synthetic_window_resize and
                            request.width == 720 and request.height == 480;
                        const move_matches = request.kind == .move and
                            config.synthetic_window_move and
                            request.x == 32 and request.y == 24;
                        const maximize_matches = request.kind == .maximize and
                            config.synthetic_window_maximize and
                            request.sdl_window_id == SDL_GetWindowID(window);
                        const fullscreen_matches = request.kind == .fullscreen and
                            config.synthetic_window_fullscreen and
                            request.sdl_window_id == SDL_GetWindowID(window);
                        const minimize_matches = request.kind == .minimize and
                            config.synthetic_window_minimize_restore and
                            request.sdl_window_id == SDL_GetWindowID(window);
                        const restore_matches = request.kind == .restore and
                            config.synthetic_window_minimize_restore and
                            request.sdl_window_id == SDL_GetWindowID(window);
                        if (resize_matches or move_matches or maximize_matches)
                            window_request_delivered = true;
                        if (fullscreen_matches)
                            fullscreen_request_delivered = true;
                        if (minimize_matches) {
                            minimize_request_delivered = true;
                            minimize_sequence = outcome.delivered.sequence;
                        }
                        if (restore_matches) {
                            restore_request_delivered = true;
                            restore_sequence = outcome.delivered.sequence;
                        }
                    },
                    .monitor => |monitor| delivered_monitor = monitor,
                    .dpi => |dpi| delivered_dpi = dpi,
                    .theme => theme_event_delivered = true,
                    .dnd_position => |position| {
                        dnd_position_count += 1;
                        dnd_position_point = position;
                    },
                    .text => |text| {
                        ime_event_delivered = ime_event_delivered or
                            config.mode == .emacs_epxl_ime_commit and
                                std.mem.eql(u8, text.bytes(), "你好");
                    },
                    else => {},
                }
            }
        }
        try live.writeControl(&writer.interface, .{ .kind = .ack, .sequence = envelope.sequence });
        try writer.interface.flush();
        pollEpxlInteractiveInput(delivery, &scrollbar_drag, &toolbar_press, &dnd_tracker, config, window, &retained_frame, &scene, &frame_gate, negotiated.effective, &input_dirty, &primary_paste_queued, &monitor_refresh_needed) catch |err| switch (err) {
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
                if (negotiated.effective.contains(.clipboard_primary_selection_bounded)) {
                    try setPlatformPrimarySelection(clipboard_text);
                    if (SDL_GetPrimarySelectionText()) |owned| {
                        primary_copy_exact = std.mem.eql(u8, std.mem.span(owned), "Emacs 你好");
                        SDL_free(owned);
                    }
                    if (config.synthetic_primary_selection) {
                        var primary_paste = keyboardEvent(
                            input_policy.SDL_SCANCODE_INSERT,
                            true,
                            0x0001,
                        );
                        if (!SDL_PushEvent(&primary_paste)) return sdlFail("SDL_PushEvent");
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
                null,
            );
        } else {
            _ = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters, null);
        }
        if (config.mode == .emacs_epxl_ime_commit) {
            if (initial_ime_placement == null)
                initial_ime_placement = sceneTextInputPlacement(&scene);
            if (syncTextInputArea(window, &scene) == .synced)
                ime_area_refreshes += 1;
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
    if (config.mode == .emacs_primary_selection) {
        if (!copy_applied or !copy_unicode_exact or !primary_copy_exact)
            return error.PrimarySelectionCopyNotApplied;
        const primary_pasted = sceneHasText(&scene, "你好") and
            sceneHasText(&scene, "Emacs 你好");
        if (!primary_paste_queued) return error.PrimarySelectionPasteNotQueued;
        if (!primary_pasted)
            return error.PrimarySelectionPasteNotApplied;
        std.debug.print(
            "sdl3-primary-selection-smoke: {{\"kind\":\"sdl3-primary-selection-smoke\",\"copy\":\"Emacs 你好\",\"first_line\":\"你好Emacs 你好\",\"round_trip\":true,\"result\":\"pass\"}}\n",
            .{},
        );
    }
    if (config.mode == .emacs_epxl_ime_commit) {
        const final_placement = sceneTextInputPlacement(&scene) orelse
            return error.TextInputAreaUnavailable;
        const initial = initial_ime_placement orelse
            return error.TextInputAreaUnavailable;
        if (!ime_event_delivered or final_placement.cursor <= initial.cursor or
            (final_placement.window_id != initial.window_id or
                ime_area_refreshes < 2 or
                frame_counters.unicode_text_commands_total == 0) or
            scene.stats.frame_updates < 2 or
            !sceneWindowHasText(&scene, final_placement.window_id, "你好"))
            return error.ImeCommitNotApplied;
        std.debug.print(
            "sdl3-ime-commit-smoke: {{\"kind\":\"sdl3-ime-commit-smoke\",\"committed\":\"你好\",\"emacs_applied\":true,\"area\":{{\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d}}},\"cursor\":{d},\"area_refreshes\":{d},\"unicode_draws\":{d},\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{
                final_placement.area.x,
                final_placement.area.y,
                final_placement.area.w,
                final_placement.area.h,
                final_placement.cursor,
                ime_area_refreshes,
                frame_counters.unicode_text_commands_total,
                scene.stats.frame_updates,
            },
        );
    }
    if (config.mode == .emacs_epxl_cursor) {
        // The owned publisher reports the frame's bounded cursor kind (pinned by
        // the smoke profile), so the live scene must carry it.
        const cursor = scene.cursor orelse return error.CursorSmokeMissingCursor;
        if (!cursor.active or cursor.kind != frontend.cursor_kind_hbar)
            return error.CursorSmokeKindMismatch;
        std.debug.print(
            "sdl3-emacs-cursor-smoke: {{\"kind\":\"sdl3-emacs-cursor-smoke\",\"capability\":\"cursor.update_v1\",\"cursor_kind\":{d},\"shape\":\"hbar\",\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{ cursor.kind, scene.stats.frame_updates },
        );
    }
    if (config.mode == .emacs_epxl_scrollbar) {
        // The owned publisher reports the real window's line count and scroll
        // position behind a pinned scroll-bar width; the state is sampled
        // while it holds because the next FRAME_UPDATE replaces it.
        if (!scrollbar_observed) return error.ScrollbarSmokeNotObserved;
        std.debug.print(
            "sdl3-emacs-scrollbar-smoke: {{\"kind\":\"sdl3-emacs-scrollbar-smoke\",\"capability\":\"window.scrollbar_state_v1\",\"content_size\":200,\"viewport_size\":32,\"position\":10,\"track_width\":12,\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{scene.stats.frame_updates},
        );
    }
    if (config.mode == .emacs_epxl_scroll_interaction) {
        // The trough press and the thumb drag are each delivered as one bounded
        // relative scroll intent over EPXL, the owned publisher applies them to
        // the real window, and the republished state must show both scrolls.
        if (!scrollbar_observed or !scroll_page_seeded)
            return error.ScrollInteractionSmokeNotSeeded;
        if (scroll_page_position == null or scroll_page_position.? != 42)
            return error.ScrollPageNotApplied;
        if (scroll_drag_position == null or scroll_drag_position.? != 46)
            return error.ScrollDragNotApplied;
        std.debug.print(
            "sdl3-emacs-scrollbar-interaction-smoke: {{\"kind\":\"sdl3-emacs-scrollbar-interaction-smoke\",\"capability\":\"window.scroll_request_v1\",\"initial_position\":10,\"page_delta\":32,\"page_position\":{d},\"drag_delta\":4,\"drag_position\":{d},\"emacs_applied\":true,\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{ scroll_page_position.?, scroll_drag_position.?, scene.stats.frame_updates },
        );
    }
    if (config.mode == .emacs_epxl_hscroll) {
        // The live horizontal bar's thumb drag is delivered as one bounded
        // relative horizontal intent, the publisher adjusts the real
        // `window-hscroll`, and the republished state shows the new offset.
        if (!hscroll_observed) return error.HscrollSmokeNotObserved;
        if (hscroll_position == null or hscroll_position.? != 15)
            return error.HscrollDragNotApplied;
        // The mirror drops the horizontally scrolled-off columns, so the base
        // line "visible ASCII textZ" is mirrored as its remaining "extZ".
        var hscroll_trimmed = false;
        for (scene.text.items) |line| {
            if (std.mem.eql(u8, line.bytes, "extZ")) hscroll_trimmed = true;
        }
        if (!hscroll_trimmed) return error.HscrollSmokeTextNotTrimmed;
        std.debug.print(
            "sdl3-emacs-hscroll-smoke: {{\"kind\":\"sdl3-emacs-hscroll-smoke\",\"capability\":\"window.scroll_request_v1\",\"initial_position\":5,\"drag_delta\":10,\"position\":{d},\"text_trimmed\":true,\"emacs_applied\":true,\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{ hscroll_position.?, scene.stats.frame_updates },
        );
    }
    if (config.mode == .emacs_epxl_menu_bar) {
        // The owned publisher reports the frame's real menu-bar labels, so the
        // live scene must own a model whose depth-0 nodes are those items in
        // order and the bar row must draw each of them.
        const model = scene.menu_model orelse return error.MenuBarSmokeNoModel;
        const expected = [_][]const u8{ "File", "Edit", "Options", "Buffers", "Tools", "Help" };
        var matched: usize = 0;
        for (model.nodes) |node| {
            if (node.parent_item_id != 0 or
                node.flags & protocol.MenuNodeFlags.visible == 0) continue;
            const label = node.label[0..node.label_len];
            if (matched < expected.len and std.mem.eql(u8, label, expected[matched]))
                matched += 1;
        }
        if (matched != expected.len) return error.MenuBarSmokeLabelsMismatch;
        var output_width: c_int = 0;
        var output_height: c_int = 0;
        SDL_GetWindowSize(window, &output_width, &output_height);
        var menu_draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
        defer menu_draw_list.deinit();
        try buildSceneDrawList(&scene, &menu_draw_list, @intCast(output_width), @intCast(output_height));
        var drawn: usize = 0;
        for (expected) |label| {
            var found = false;
            for (menu_draw_list.commands.items) |command| switch (command) {
                // The bar labels are drawn with the frame's real font.
                .unicode_text => |text| {
                    if (std.mem.eql(u8, text.bytes, label)) found = true;
                },
                else => {},
            };
            if (found) drawn += 1;
        }
        if (drawn != expected.len) return error.MenuBarSmokeNotDrawn;
        std.debug.print(
            "sdl3-emacs-menu-bar-smoke: {{\"kind\":\"sdl3-emacs-menu-bar-smoke\",\"capability\":\"widget.menu_model_v1\",\"items\":{d},\"labels_drawn\":{d},\"font_backed\":true,\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{ model.nodes.len, drawn, scene.stats.frame_updates },
        );
    }
    if (config.mode == .emacs_epxl_menu_open) {
        // The bar press must reach the backend as exactly one bounded
        // open-request naming the clicked item and its logical slot origin.
        const request = menu_open_request_delivered orelse
            return error.MenuOpenRequestNotDelivered;
        if (request.item_id == 0 or request.menu_id == 0 or
            request.menu_generation == 0 or request.frame_generation == 0 or
            delivery.pending != null)
            return error.MenuOpenRequestInvalid;
        if (!menu_popup_observed) return error.MenuPopupNotObserved;
        if (!menu_row_pressed) return error.MenuPopupRowNotPressed;
        if (!menu_result_delivered) return error.MenuResultNotDelivered;
        if (!menu_popup_closed) return error.MenuPopupNotClosed;
        // The live popup carries the frame's real `:enable` state, so the rows
        // that need an active mark (Cut/Copy/Clear) arrive disabled.
        if (!menu_popup_disabled) return error.MenuPopupEnableStateMissing;
        // The live Edit menu's rows carry their real key hints (Undo -> C-x u),
        // and the drawn popup must contain them.
        if (!menu_popup_key or !menu_key_drawn) return error.MenuPopupKeyHintMissing;
        if (!menu_popup_help) return error.MenuPopupHelpMissing;
        if (!menu_popup_icon) return error.MenuPopupIconPayloadMissing;
        std.debug.print(
            "sdl3-emacs-menu-open-smoke: {{\"kind\":\"sdl3-emacs-menu-open-smoke\",\"capability\":\"widget.menu_open_request_v1\",\"item_id\":{d},\"slot_x\":{d},\"window_id\":{d},\"popup_rows\":\"real\",\"popup_enable_state\":true,\"popup_key_hint\":true,\"popup_help\":true,\"popup_icon_payload\":true,\"result_sent\":true,\"popup_closed\":true,\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{
                request.item_id,
                request.x,
                request.window_id,
                scene.stats.frame_updates,
            },
        );
    }
    if (config.mode == .emacs_epxl_menu_apply) {
        // Choosing the real "Undo" row must resolve to the real command and run
        // it: the seeded edit is gone and the popup closed.
        const request = menu_open_request_delivered orelse
            return error.MenuApplyRequestNotDelivered;
        if (request.item_id == 0 or
            !menu_apply_edited or !menu_apply_undone or
            !menu_popup_observed or !menu_result_delivered or !menu_popup_closed)
            return error.MenuApplyRoundTripIncomplete;
        std.debug.print(
            "sdl3-emacs-menu-apply-smoke: {{\"kind\":\"sdl3-emacs-menu-apply-smoke\",\"capability\":\"widget.menu_result_v1\",\"item_id\":{d},\"command\":\"undo\",\"edit_applied\":true,\"undo_applied\":true,\"popup_closed\":true,\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{ request.item_id, scene.stats.frame_updates },
        );
    }
    if (config.mode == .emacs_epxl_mouse) {
        if (!mouse_face_seen) return error.MouseFaceSmokeMissingHighlight;
        // The pinned overlay spans more than one displayed row, so the
        // mouse-face highlight must arrive as one rectangle per row.
        if (mouse_face_rects < 2) return error.MouseFaceSmokeSingleRect;
        std.debug.print(
            "sdl3-emacs-mouse-smoke: {{\"kind\":\"sdl3-emacs-mouse-smoke\",\"capability\":\"window.mouse_face_v1\",\"mouse_face\":true,\"mouse_rects\":{d},\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{ mouse_face_rects, scene.stats.frame_updates },
        );
    }
    if (config.mode == .emacs_epxl_graphic) {
        // A display-backed PGTK frame is what makes these real: the selected
        // window owns a non-empty real mode line and the frame reports a real
        // scroll-bar width, and the mode line text reaches the draw list.
        if (scene.mode_line_count == 0) return error.GraphicSmokeNoModeLine;
        const mode_line = scene.mode_lines[0];
        const text = mode_line.bytes[0..mode_line.len];
        if (mode_line.height < 8 or std.mem.indexOf(u8, text, "scratch") == null)
            return error.GraphicSmokeModeLineMismatch;
        const scroll_width = graphic_scroll_width;
        if (scroll_width == 0) return error.GraphicSmokeNoScrollBar;
        var output_width: c_int = 0;
        var output_height: c_int = 0;
        SDL_GetWindowSize(window, &output_width, &output_height);
        var graphic_draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
        defer graphic_draw_list.deinit();
        try buildSceneDrawList(&scene, &graphic_draw_list, @intCast(output_width), @intCast(output_height));
        var mode_line_drawn = false;
        for (graphic_draw_list.commands.items) |command| switch (command) {
            .text => |draw| {
                if (std.mem.indexOf(u8, draw.bytes, "scratch") != null) mode_line_drawn = true;
            },
            .unicode_text => |draw| {
                if (std.mem.indexOf(u8, draw.bytes, "scratch") != null) mode_line_drawn = true;
            },
            else => {},
        };
        if (!mode_line_drawn) return error.GraphicSmokeModeLineNotDrawn;
        // The real mode-line face colors reach the bar: the drawn bar uses the
        // published mode-line background instead of the diagnostic default.
        const mode_line_face = scene.faces.lookup(facts.mode_line_face_id) orelse
            return error.GraphicSmokeModeLineFaceMissing;
        if (!mode_line_face.payload.presence.background)
            return error.GraphicSmokeModeLineFaceMissing;
        var mode_line_bar_colored = false;
        for (graphic_draw_list.commands.items) |command| switch (command) {
            .fill => |fill| {
                if (fill.rect.height == @as(f32, @floatFromInt(mode_line.height)) and
                    fill.color.r == mode_line_face.payload.background[0] and
                    fill.color.g == mode_line_face.payload.background[1] and
                    fill.color.b == mode_line_face.payload.background[2])
                    mode_line_bar_colored = true;
            },
            else => {},
        };
        if (!mode_line_bar_colored) return error.GraphicSmokeModeLineFaceNotDrawn;
        if (!graphic_inactive_mode_line_seen)
            return error.GraphicSmokeInactiveModeLineMissing;
        if (!graphic_inactive_mode_line_colored)
            return error.GraphicSmokeInactiveModeLineFaceNotDrawn;
        // The real header-line and tab-line faces reach their own aux bars.
        var header_line_seen = false;
        var tab_line_seen = false;
        for (scene.aux_lines[0..scene.aux_line_count]) |aux| {
            if (aux.flags & frontend.aux_line_header != 0) header_line_seen = true;
            if (aux.flags & frontend.aux_line_tab != 0) tab_line_seen = true;
        }
        if (!header_line_seen) return error.GraphicSmokeHeaderLineMissing;
        if (!tab_line_seen) return error.GraphicSmokeTabLineMissing;
        const header_line_face = scene.faces.lookup(facts.header_line_face_id) orelse
            return error.GraphicSmokeHeaderLineFaceMissing;
        if (!header_line_face.payload.presence.background)
            return error.GraphicSmokeHeaderLineFaceMissing;
        const tab_line_face = scene.faces.lookup(facts.tab_line_face_id);
        var header_bar_colored = false;
        var tab_bar_colored = false;
        for (graphic_draw_list.commands.items) |command| switch (command) {
            .fill => |fill| {
                if (fill.color.r == header_line_face.payload.background[0] and
                    fill.color.g == header_line_face.payload.background[1] and
                    fill.color.b == header_line_face.payload.background[2])
                    header_bar_colored = true;
                if (tab_line_face) |tab_face| {
                    if (tab_face.payload.presence.background and
                        fill.color.r == tab_face.payload.background[0] and
                        fill.color.g == tab_face.payload.background[1] and
                        fill.color.b == tab_face.payload.background[2])
                        tab_bar_colored = true;
                }
            },
            else => {},
        };
        if (!header_bar_colored) return error.GraphicSmokeHeaderLineFaceNotDrawn;
        if (tab_line_face) |tab_face| {
            if (!tab_face.payload.presence.background)
                return error.GraphicSmokeTabLineFaceMissing;
            if (!tab_bar_colored) return error.GraphicSmokeTabLineFaceNotDrawn;
        }
        if (graphic_run_rows < 3) return error.GraphicSmokeRunsRowCount;
        if (graphic_max_text_lines < 24) return error.GraphicSmokeTooFewTextLines;
        if (!graphic_run_background_colored) return error.GraphicSmokeRunBackgroundNotDrawn;
        if (!graphic_run_underline_drawn) return error.GraphicSmokeRunUnderlineNotDrawn;
        if (!graphic_run_inverse_drawn) return error.GraphicSmokeRunInverseNotDrawn;
        if (!graphic_region_seen) return error.GraphicSmokeRegionMissing;
        if (!graphic_runs_seen) return error.GraphicSmokeRunsMissing;
        if (!graphic_runs_colored) return error.GraphicSmokeRunsNotDrawn;
        if (!graphic_region_colored) return error.GraphicSmokeRegionNotDrawn;
        // A multi-line region is not a rectangle: it must arrive as one record
        // per displayed row.
        if (graphic_region_rects < 2) return error.GraphicSmokeRegionNotPerRow;
        // Plain body rows are drawn with the frame's real font, not SDL's
        // eight-pixel debug font.
        var body_text_font = false;
        for (graphic_draw_list.commands.items) |command| switch (command) {
            .unicode_text => |draw| {
                if (std.mem.eql(u8, draw.bytes, "Emacs Proto-UI")) body_text_font = true;
            },
            else => {},
        };
        if (!body_text_font) return error.GraphicSmokeBodyTextFontMissing;
        // A pinned mixed ASCII/non-ASCII line keeps its plain text (the run
        // wire is ASCII-only) while its ASCII span still carries its face
        // colour as a partial run drawn over that text.
        var non_ascii_drawn = false;
        for (graphic_draw_list.commands.items) |command| switch (command) {
            .unicode_text => |draw| {
                if (std.mem.eql(u8, draw.bytes, "你好 note4")) non_ascii_drawn = true;
            },
            else => {},
        };
        if (!non_ascii_drawn) return error.GraphicSmokeNonAsciiNotDrawn;
        if (!graphic_partial_run) return error.GraphicSmokePartialRunMissing;
        // The mirror follows displayed rows: a line wider than the window is
        // wrapped into several rows, an over-long row is truncated to the wire
        // bound, and a blank line keeps its row so the rows after it stay
        // aligned (a dropped row would shift every following row).
        var wrapped_rows: usize = 0;
        var longest_row_bytes: usize = 0;
        var blankmark_window: ?u64 = null;
        var blankmark_row: u32 = 0;
        for (scene.text.items) |line| {
            if (std.mem.startsWith(u8, line.bytes, "xxxx")) {
                wrapped_rows += 1;
                longest_row_bytes = @max(longest_row_bytes, line.bytes.len);
            }
            if (std.mem.eql(u8, line.bytes, "BLANKMARK")) {
                blankmark_window = line.window_id;
                blankmark_row = line.row_index;
            }
        }
        if (wrapped_rows < 3) return error.GraphicSmokeWrappedRowsMissing;
        // The row wire bound is larger than the chrome bound, so a wide frame's
        // row is mirrored past 120 bytes instead of being cut short.  A narrow
        // frame's display rows are naturally shorter, so only assert when the
        // window can hold a wider row.
        if (scene.rows.items[0].width > 120 * 8 and longest_row_bytes <= 120)
            return error.GraphicSmokeRowBoundNotRaised;
        if (blankmark_window == null) return error.GraphicSmokeRowAlignmentLost;
        var alignmark_after_blank = false;
        var text_on_blank_row = false;
        for (scene.text.items) |line| {
            if (line.window_id != blankmark_window.?) continue;
            if (line.row_index == blankmark_row + 2 and
                std.mem.eql(u8, line.bytes, "ALIGNMARK"))
                alignmark_after_blank = true;
            if (line.row_index == blankmark_row + 1) text_on_blank_row = true;
        }
        if (!alignmark_after_blank) return error.GraphicSmokeRowAlignmentLost;
        if (text_on_blank_row) return error.GraphicSmokeRowAlignmentLost;
        // The real echo area reaches the frame's bottom strip.
        const echo_resource = scene.strings.lookup(facts.echo_string_id) orelse
            return error.GraphicSmokeEchoMissing;
        if (!std.mem.eql(u8, echo_resource.bytes, "ProtoEcho"))
            return error.GraphicSmokeEchoMismatch;
        var echo_drawn = false;
        var echo_face_color = false;
        const echo_default_face = scene.faces.lookup(facts.default_face_id);
        for (graphic_draw_list.commands.items) |command| switch (command) {
            .unicode_text => |draw| {
                if (std.mem.eql(u8, draw.bytes, "ProtoEcho")) {
                    echo_drawn = true;
                    // The echo strip carries the frame's own default face
                    // color, not the diagnostic strip color.
                    if (echo_default_face) |face| {
                        if (face.payload.presence.foreground and
                            draw.color.r == face.payload.foreground[0] and
                            draw.color.g == face.payload.foreground[1] and
                            draw.color.b == face.payload.foreground[2])
                            echo_face_color = true;
                    }
                }
            },
            else => {},
        };
        if (!echo_drawn) return error.GraphicSmokeEchoNotDrawn;
        if (!echo_face_color) return error.GraphicSmokeEchoFaceColorMissing;
        if (!graphic_run_style_drawn) return error.GraphicSmokeRunStyleNotDrawn;
        if (!graphic_run_overlay_seen) return error.GraphicSmokeRunOverlayMissing;
        if (!graphic_multi_window_run) return error.GraphicSmokeMultiWindowRunMissing;
        if (!graphic_variable_font_seen) return error.GraphicSmokeVariableFontMissing;
        if (!graphic_variable_font_drawn) return error.GraphicSmokeVariableFontNotDrawn;
        if (!graphic_variable_metrics) return error.GraphicSmokeVariableMetricsMissing;
        try unicode_text_renderer.ensure();
        _ = unicode_text_renderer.openVariableFont(1);
        if (!unicode_text_renderer.hasVariableFont()) return error.GraphicSmokeVariableFontUnavailable;
        // The default mode line's buffer id is bold, so a mode-line run must
        // carry the bold style.
        if (!graphic_mode_line_bold) return error.GraphicSmokeModeLineRunMissing;
        // The header and tab lines carry their own segment faces as runs too.
        if (!graphic_header_line_run) return error.GraphicSmokeHeaderLineRunMissing;
        if (!graphic_tab_line_run) return error.GraphicSmokeTabLineRunMissing;
        if (!graphic_header_line_drawn) return error.GraphicSmokeHeaderLineRunNotDrawn;
        if (!graphic_tab_line_drawn) return error.GraphicSmokeTabLineRunNotDrawn;
        // The real tool bar is mirrored from the live tool-bar map, so its
        // items and labels arrive as the bounded toolbar model and draw.
        const tool_bar = scene.toolbar orelse return error.GraphicSmokeToolBarMissing;
        if (tool_bar.items.len < 6) return error.GraphicSmokeToolBarMissing;
        var tool_bar_labels_drawn: usize = 0;
        for (tool_bar.items) |item| {
            const label = item.label[0..item.label_len];
            if (label.len == 0) continue;
            for (graphic_draw_list.commands.items) |command| switch (command) {
                .unicode_text => |draw| {
                    if (std.mem.eql(u8, draw.bytes, label)) tool_bar_labels_drawn += 1;
                },
                else => {},
            };
        }
        if (tool_bar_labels_drawn < 4) return error.GraphicSmokeToolBarNotDrawn;
        // The real tool-bar face colors reach the strip: the drawn row or slot
        // uses the published tool-bar background instead of the diagnostic one.
        const tool_bar_face = scene.faces.lookup(facts.tool_bar_face_id) orelse
            return error.GraphicSmokeToolBarFaceMissing;
        if (!tool_bar_face.payload.presence.background)
            return error.GraphicSmokeToolBarFaceMissing;
        var tool_bar_face_colored = false;
        for (graphic_draw_list.commands.items) |command| switch (command) {
            .fill => |fill| {
                if (fill.color.r == tool_bar_face.payload.background[0] and
                    fill.color.g == tool_bar_face.payload.background[1] and
                    fill.color.b == tool_bar_face.payload.background[2])
                    tool_bar_face_colored = true;
            },
            else => {},
        };
        if (!tool_bar_face_colored) return error.GraphicSmokeToolBarFaceNotDrawn;
        // The real mode-line and tool-bar faces carry a released-button box, so
        // the mirror draws their borders as approximation bars.
        const mode_line_box_face = scene.faces.lookup(facts.mode_line_face_id) orelse
            return error.GraphicSmokeModeLineFaceMissing;
        if (mode_line_box_face.payload.box == .none)
            return error.GraphicSmokeModeLineBoxMissing;
        if (tool_bar_face.payload.box == .none)
            return error.GraphicSmokeToolBarBoxMissing;
        // The published box carries a real `:line-width`, and the released
        // button style draws a light/dark bevel, so the tool-bar button border
        // must reach the draw list in two distinct colors.
        if (mode_line_box_face.payload.box_line_width <= 0 or
            tool_bar_face.payload.box_line_width <= 0)
            return error.GraphicSmokeBoxWidthMissing;
        var tool_bar_box_drawn = false;
        var tool_bar_box_colors: [4]renderer_policy.Color = undefined;
        var tool_bar_box_color_count: usize = 0;
        if (frontend.toolbarLayout(&scene)) |layout| {
            if (layout.slot_count != 0) {
                const slot = layout.slots[0];
                for (graphic_draw_list.commands.items) |command| switch (command) {
                    .fill => |fill| {
                        if (fill.rect.x == slot.x and fill.rect.width == slot.width and
                            fill.rect.height < slot.height and fill.rect.y >= slot.y and
                            fill.rect.y < slot.y + slot.height)
                        {
                            tool_bar_box_drawn = true;
                            var seen = false;
                            for (tool_bar_box_colors[0..tool_bar_box_color_count]) |color| {
                                if (std.meta.eql(color, fill.color)) seen = true;
                            }
                            if (!seen and tool_bar_box_color_count < tool_bar_box_colors.len) {
                                tool_bar_box_colors[tool_bar_box_color_count] = fill.color;
                                tool_bar_box_color_count += 1;
                            }
                        }
                    },
                    else => {},
                };
            }
        }
        if (!tool_bar_box_drawn) return error.GraphicSmokeToolBarBoxNotDrawn;
        if (tool_bar_box_color_count < 2) return error.GraphicSmokeToolBarBoxNotBeveled;
        // The frame's real font pixel size sizes the text font, and it must not
        // exceed the row's line height.
        const published_size: i32 = if (scene.strings.lookup(facts.default_font_size_string_id)) |resource|
            (std.fmt.parseInt(i32, resource.bytes, 10) catch 0)
        else
            0;
        if (!unicode_text_renderer.hasFallback()) return error.GraphicSmokeFallbackMissing;
        if (!unicode_text_renderer.providesCjk()) return error.GraphicSmokeFallbackNotUsed;
        if (published_size < 8 or
            unicode_text_renderer.activePointSize() !=
                @as(f32, @floatFromInt(published_size)) or
            unicode_text_renderer.activePointSize() >
                @as(f32, @floatFromInt(scene.rows.items[0].height)))
            return error.GraphicSmokeTextFontMismatch;
        const active_font = unicode_text_renderer.activeFontFile();
        const published_font = if (scene.strings.lookup(facts.default_font_string_id)) |resource|
            resource.bytes
        else
            "";
        if (active_font.len == 0 or published_font.len == 0 or
            !std.mem.eql(u8, active_font, published_font) or
            !std.mem.endsWith(u8, active_font, ".ttf"))
            return error.GraphicSmokeFontFileMismatch;
        // The real character cell also drives the cursor: a display-backed
        // frame reports a cell width, so the cursor is one cell wide instead
        // of the two-unit diagnostic bar.
        const live_cursor = scene.cursor orelse return error.GraphicSmokeCursorMissing;
        if (live_cursor.width <= 2 or live_cursor.width > 64 or
            live_cursor.height != scene.rows.items[0].height)
            return error.GraphicSmokeCursorGeometryMismatch;
        // The scene's tracked cursor is the active one, not whichever window
        // was emitted last.
        if (!live_cursor.active) return error.GraphicSmokeActiveCursorNotTracked;
        // The split frame draws two carets: the selected window's stays solid,
        // while the inactive window's is drawn hollow like Emacs.
        if (scene.cursor_count < 2) return error.GraphicSmokeInactiveCursorMissing;
        var active_cursor_solid = false;
        var inactive_cursor_solid = false;
        for (scene.cursors[0..scene.cursor_count]) |cursor| {
            const owner = findSceneWindow(&scene, cursor.window_id) orelse continue;
            const size = renderer_policy.renderedCursorSize(cursor.width, cursor.height);
            const rect = renderer_policy.LogicalRect{
                .x = @floatFromInt(owner.x + cursor.x),
                .y = @floatFromInt(owner.y + cursor.y),
                .width = @floatFromInt(size.width),
                .height = @floatFromInt(size.height),
            };
            var solid = false;
            for (graphic_draw_list.commands.items) |command| switch (command) {
                .fill => |fill| {
                    if (fill.rect.x == rect.x and fill.rect.y == rect.y and
                        fill.rect.width == rect.width and fill.rect.height == rect.height)
                        solid = true;
                },
                else => {},
            };
            if (cursor.active) {
                active_cursor_solid = solid;
            } else {
                inactive_cursor_solid = solid;
            }
        }
        if (!active_cursor_solid or inactive_cursor_solid)
            return error.GraphicSmokeInactiveCursorShapeWrong;
        // The real cursor and fringe faces also reach the draw path.
        const cursor_face = scene.faces.lookup(facts.cursor_face_id) orelse
            return error.GraphicSmokeCursorFaceMissing;
        var cursor_color_drawn = false;
        for (graphic_draw_list.commands.items) |command| switch (command) {
            .fill => |fill| {
                if (fill.rect.width == @as(f32, @floatFromInt(live_cursor.width)) and
                    fill.rect.height == @as(f32, @floatFromInt(live_cursor.height)) and
                    cursor_face.payload.presence.background and
                    fill.color.r == cursor_face.payload.background[0] and
                    fill.color.g == cursor_face.payload.background[1] and
                    fill.color.b == cursor_face.payload.background[2])
                    cursor_color_drawn = true;
            },
            else => {},
        };
        if (!cursor_color_drawn) return error.GraphicSmokeCursorFaceNotDrawn;
        const fringe_face = scene.faces.lookup(facts.fringe_face_id) orelse
            return error.GraphicSmokeFringeFaceMissing;
        if (!cursor_face.payload.presence.background or
            !fringe_face.payload.presence.background)
            return error.GraphicSmokeCursorFaceMissing;
        // The real line height reaches row layout: rows are spaced by the
        // frame's own line height (the mode line is one such line) instead of
        // the bounded fifteen-row guess.
        if (scene.rows.items.len < 2 or scene.rows.items[0].height < 8)
            return error.GraphicSmokeRowMetricsMissing;
        if (scene.rows.items[0].height != mode_line.height or
            scene.rows.items[1].y != scene.rows.items[0].height)
            return error.GraphicSmokeRowMetricsMismatch;
        // The real frame also reports real fringe widths, which the frontend
        // draws as edge bars from the shared fringe records.
        const fringe_left = graphic_fringe_left;
        const fringe_right = graphic_fringe_right;
        if (fringe_left <= 0 or fringe_right <= 0)
            return error.GraphicSmokeFringeMissing;
        if (!graphic_fringe_drawn) return error.GraphicSmokeFringeNotDrawn;
        // The fringe columns are reserved: rows (and the cursor) start after
        // the left fringe instead of under it.
        // Rows (and the mode line) stop before the real scroll bar as well.
        if (scene.rows.items[0].x != fringe_left or
            scene.rows.items[0].width != scene.windows.items[0].width - fringe_left -
                fringe_right - @as(i32, @intCast(scroll_width)) or
            scene.mode_lines[0].width != scene.windows.items[0].width -
                @as(i32, @intCast(scroll_width)))
            return error.GraphicSmokeRowInsetMismatch;
        std.debug.print(
            "sdl3-emacs-graphic-smoke: {{\"kind\":\"sdl3-emacs-graphic-smoke\",\"capability\":\"window.mode_line_bounded_v1\",\"mode_line\":\"real\",\"height\":{d},\"scroll_bar_width\":{d},\"mode_line_drawn\":true,\"mode_line_face_colors\":true,\"mode_line_inactive_face_colors\":true,\"header_line_face_colors\":true,\"tab_line_face_colors\":true,\"region_highlight\":true,\"region_rects\":true,\"line_font_lock_runs\":true,\"mirrored_lines\":{d},\"line_font_lock_row_count\":{d},\"line_font_lock_run_backgrounds\":true,\"line_font_lock_run_decorations\":true,\"line_font_lock_run_inverse\":true,\"line_font_lock_run_style\":true,\"line_font_lock_run_overlay\":true,\"line_font_lock_run_mixed\":true,\"line_font_lock_multi_window\":true,\"row_alignment\":true,\"row_bound_256\":true,\"wrapped_rows\":{d},\"row_height\":{d},\"text_font_size\":{d},\"body_text_font\":true,\"non_ascii_text\":true,\"echo_area\":true,\"echo_face_color\":true,\"mode_line_face_runs\":true,\"header_line_face_runs\":true,\"tab_line_face_runs\":true,\"tool_bar\":true,\"tool_bar_items\":{d},\"tool_bar_face_colors\":true,\"mode_line_box\":true,\"tool_bar_box\":true,\"tool_bar_box_bevel\":true,\"tool_bar_box_width\":{d},\"variable_pitch_font\":true,\"variable_pitch_metrics\":true,\"font_families\":{d},\"font_file\":\"{s}\",\"variable_font_file\":\"{s}\",\"cjk_fallback\":true,\"cursor\":[{d},{d}],\"inactive_cursor_hollow\":true,\"row_width\":{d},\"fringe\":[{d},{d}],\"fringe_drawn\":true,\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{
                mode_line.height,
                scroll_width,
                graphic_max_text_lines,
                graphic_run_rows,
                wrapped_rows,
                scene.rows.items[0].height,
                @as(i32, @intFromFloat(unicode_text_renderer.activePointSize())),
                tool_bar.items.len,
                tool_bar_face.payload.box_line_width,
                unicode_text_renderer.altFontCount(),
                std.fs.path.basename(unicode_text_renderer.activeFontFile()),
                std.fs.path.basename(unicode_text_renderer.activeVariableFontFile()),
                live_cursor.width,
                live_cursor.height,
                scene.rows.items[0].width,
                fringe_left,
                fringe_right,
                scene.stats.frame_updates,
            },
        );
    }
    if (config.mode == .emacs_epxl_face) {
        // The owned publisher reports its real default face (pinned by the smoke
        // profile), so the frontend must own that face resource, bind the live
        // window to it, and draw the body text with it.  Both facts are sampled
        // while the binding holds, because the next FRAME_UPDATE replaces it.
        if (!face_binding_observed or !face_text_drawn) return error.FaceSmokeNotObserved;
        const face = scene.faces.lookup(facts.default_face_id) orelse return error.FaceSmokeMissingFace;
        if (!face.payload.presence.foreground or !face.payload.presence.background)
            return error.FaceSmokeMissingPresence;
        std.debug.print(
            "sdl3-emacs-face-smoke: {{\"kind\":\"sdl3-emacs-face-smoke\",\"capability\":\"window.face_state_v1\",\"foreground\":[16,32,48],\"background\":[208,224,240],\"window_bound\":true,\"text_drawn\":true,\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{scene.stats.frame_updates},
        );
    }
    if (config.mode == .emacs_epxl_dnd) {
        // The drop is delivered as ENTER/DROP/DATA and Emacs applies the bounded
        // payload, so the republished facts must show exactly that text.
        if (scene.stats.frame_updates < 2 or !sceneHasText(&scene, "Dropped!Emacs Proto-UI") or
            delivery.pending != null or delivery.queue.length != 0)
            return error.DndDropNotApplied;
        // Exactly one bounded position report: the second seeded position is
        // coalesced away because the journal was busy when it arrived.
        if (dnd_position_count != 1 or dnd_position_point.x != 12 or dnd_position_point.y != 6)
            return error.DndPositionFeedbackMismatch;
        std.debug.print(
            "sdl3-dnd-drop-smoke: {{\"kind\":\"sdl3-dnd-drop-smoke\",\"capability\":\"dnd.bounded_v1\",\"target\":\"text/plain\",\"payload\":\"Dropped!\",\"sequence\":[\"position\",\"enter\",\"drop\",\"data\"],\"position\":[{d},{d}],\"position_coalesced\":true,\"emacs_applied\":true,\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{ dnd_position_point.x, dnd_position_point.y, scene.stats.frame_updates },
        );
    }
    if (config.synthetic_focus_events) {
        if (!focus_gained_delivered or !focus_lost_delivered or
            !observed_focus_gained or !observed_focus_transition)
            return error.FocusEventNotDelivered;
        const frame = scene.frames.lookup(1) orelse return error.FrameNotActive;
        if (frame.focused) return error.FocusStateNotObserved;
        std.debug.print(
            "sdl3-focus-roundtrip-smoke: {{\"kind\":\"sdl3-focus-roundtrip-smoke\",\"gained_then_lost\":true,\"emacs_focused\":false,\"result\":\"pass\"}}\n",
            .{},
        );
    }
    if (config.selection_owner_smoke) {
        if (!selection_owner_set_seen or !selection_owner_clear_seen or
            !selection_lost_seen or !selection_replacement_seen or
            !initial_platform_claimed or !lost_platform_released or
            !replacement_platform_claimed or !clear_platform_released)
            return error.SelectionOwnershipTransitionNotObserved;
        std.debug.print(
            "sdl3-selection-owner-smoke: {{\"kind\":\"sdl3-selection-owner-smoke\",\"selection\":\"primary\",\"targets\":[\"UTF8_STRING\",\"STRING\"],\"generations\":[1,2],\"owner_cancelled\":true,\"replacement\":true,\"initial_claimed\":true,\"lost_released\":true,\"replacement_claimed\":true,\"clear_released\":true,\"result\":\"pass\"}}\n",
            .{},
        );
    }
    if (config.selection_transfer_smoke) {
        if (!selection_transfer_owner_seen or !selection_transfer_request_seen or
            !selection_transfer_data_seen or !selection_error_request_seen or
            !selection_error_seen or !selection_transfer_clear_seen or
            !transfer_platform_claimed or !transfer_platform_released)
            return error.SelectionTransferNotObserved;
        std.debug.print(
            "sdl3-selection-transfer-smoke: {{\"kind\":\"sdl3-selection-transfer-smoke\",\"selection\":\"primary\",\"request_id\":9001,\"target\":\"UTF8_STRING\",\"data\":\"Proto-UI transfer\",\"status\":\"completed\",\"platform_claimed\":true,\"platform_released\":true,\"error_request_id\":9002,\"error_reason\":\"conversion_failed\",\"error_message\":\"conversion unavailable\",\"cleared\":true,\"result\":\"pass\"}}\n",
            .{},
        );
    }
    if (config.synthetic_monitor_change) {
        expected_monitor_id = SDL_GetDisplayForWindow(window);
        if (expected_monitor_id == 0 or
            !SDL_GetDisplayBounds(expected_monitor_id, &expected_bounds))
            return error.MonitorBoundsUnavailable;
        const monitor_scale_milli = try validatedScaleMilli(SDL_GetDisplayContentScale(expected_monitor_id));
        const window_scale_milli = try validatedScaleMilli(SDL_GetWindowDisplayScale(window));
        const dpi_milli = window_scale_milli * 96;
        const expected_monitor: protocol.MonitorEvent = .{
            .kind = .current_changed,
            .monitor_id = expected_monitor_id,
            .x = expected_bounds.x,
            .y = expected_bounds.y,
            .width = expected_bounds.w,
            .height = expected_bounds.h,
            .scale_milli_percent = monitor_scale_milli,
            .primary = expected_monitor_id == SDL_GetPrimaryDisplay(),
            .current = true,
        };
        const expected_dpi: protocol.DpiEvent = .{
            .frame_id = scene.frame_header.?.frame_id,
            .sdl_window_id = SDL_GetWindowID(window),
            .scale_milli_percent = window_scale_milli,
            .dpi_x_milli = dpi_milli,
            .dpi_y_milli = dpi_milli,
        };
        if (delivered_monitor == null or delivered_dpi == null or
            !std.meta.eql(delivered_monitor.?, expected_monitor) or
            !std.meta.eql(delivered_dpi.?, expected_dpi))
            return error.MonitorEventPayloadMismatch;
    }
    if (config.synthetic_window_resize) {
        if (!window_request_delivered or
            !sceneHasText(&scene, "ResizeApplied"))
            return error.WindowResizeNotApplied;
        std.debug.print(
            "sdl3-window-resize-roundtrip-smoke: {{\"kind\":\"sdl3-window-resize-roundtrip-smoke\",\"width\":720,\"height\":480,\"emacs_applied\":true,\"result\":\"pass\"}}\n",
            .{},
        );
    }
    if (config.synthetic_window_move) {
        if (!window_request_delivered or
            !sceneHasText(&scene, "MoveApplied"))
            return error.WindowMoveNotApplied;
        std.debug.print(
            "sdl3-window-move-roundtrip-smoke: {{\"kind\":\"sdl3-window-move-roundtrip-smoke\",\"x\":32,\"y\":24,\"emacs_applied\":true,\"result\":\"pass\"}}\n",
            .{},
        );
    }
    if (config.synthetic_window_maximize) {
        if (!window_request_delivered or
            !sceneHasText(&scene, "MaximizeApplied"))
            return error.WindowMaximizeNotApplied;
        std.debug.print(
            "sdl3-window-maximize-roundtrip-smoke: {{\"kind\":\"sdl3-window-maximize-roundtrip-smoke\",\"fullscreen\":\"maximized\",\"emacs_parameter_accepted\":true,\"result\":\"pass\"}}\n",
            .{},
        );
    }
    if (config.synthetic_window_fullscreen) {
        if (!fullscreen_request_delivered or
            !sceneHasText(&scene, "FullscreenApplied"))
            return error.WindowFullscreenNotApplied;
        std.debug.print(
            "sdl3-window-fullscreen-roundtrip-smoke: {{\"kind\":\"sdl3-window-fullscreen-roundtrip-smoke\",\"fullscreen\":\"fullboth\",\"emacs_parameter_accepted\":true,\"result\":\"pass\"}}\n",
            .{},
        );
    }
    if (config.synthetic_monitor_change) {
        const monitor = scene.monitor orelse return error.MonitorChangeNotObserved;
        if (monitor.monitor_id != expected_monitor_id or
            monitor.x != expected_bounds.x or monitor.y != expected_bounds.y or
            monitor.width != expected_bounds.w or monitor.height != expected_bounds.h)
            return error.MonitorChangeNotObserved;
        std.debug.print(
            "sdl3-monitor-change-smoke: {{\"kind\":\"sdl3-monitor-change-smoke\",\"monitor_id\":{d},\"width\":{d},\"height\":{d},\"monitor_transport\":\"verified\",\"dpi_transport\":\"verified\",\"publisher\":\"observation-only\",\"result\":\"pass\"}}\n",
            .{ monitor.monitor_id, monitor.width, monitor.height },
        );
    }

    if (config.synthetic_window_minimize_restore) {
        if (!minimize_request_delivered or !restore_request_delivered or
            minimize_sequence == 0 or restore_sequence == 0 or minimize_sequence >= restore_sequence or
            !sceneHasText(&scene, "MinimizeApplied") or
            !sceneHasText(&scene, "RestoreApplied"))
            return error.WindowMinimizeRestoreNotApplied;
        std.debug.print(
            "sdl3-window-minimize-restore-smoke: {{\"kind\":\"sdl3-window-minimize-restore-smoke\",\"minimize_request\":\"accepted\",\"restore_request\":\"accepted\",\"platform_state\":\"pending\",\"result\":\"pass\"}}\n",
            .{},
        );
    }

    if (config.interactive_synthetic and !sceneHasText(&scene, "XYEmacs Proto-UI"))
        return error.InteractiveInputNotApplied;
    if (config.synthetic_wheel and !config.synthetic_viewport and wheel_ticks_delivered < 2)
        return error.WheelScrollNotApplied;
    if (config.synthetic_wheel and !config.synthetic_viewport and
        horizontal_wheel_ticks_delivered < 2)
        return error.HorizontalWheelScrollNotApplied;
    if (config.synthetic_theme_event and !theme_event_delivered)
        return error.ThemeEventNotDelivered;
    if (config.synthetic_theme_event) {
        const raw_theme = SDL_GetSystemTheme();
        const appearance_name: []const u8 = switch (raw_theme) {
            SDL_SYSTEM_THEME_LIGHT => "light",
            SDL_SYSTEM_THEME_DARK => "dark",
            else => "unknown",
        };
        std.debug.print(
            "sdl3-theme-event-smoke: {{\"kind\":\"sdl3-theme-event-smoke\",\"appearance\":\"{s}\",\"verification\":\"negotiated-delivery\",\"publisher\":\"observation-only\",\"result\":\"pass\"}}\n",
            .{appearance_name},
        );
    }

    if (config.title_smoke) {
        const expected_title = "Emacs Proto-UI Title";
        if (!title_applied or scene.title == null or
            !std.mem.eql(u8, scene.title.?, expected_title))
        {
            return error.EmacsTitleNotApplied;
        }
        std.debug.print(
            "sdl3-emacs-interactive-smoke: {{\"kind\":\"sdl3-emacs-interactive-smoke\",\"title\":\"{s}\",\"result\":\"pass\"}}\n",
            .{scene.title.?},
        );
    }
    if (scene.title != null and !title_applied)
        return error.EmacsTitleNotApplied;

    if (config.synthetic_wheel and !config.synthetic_viewport) {
        std.debug.print(
            "sdl3-wheel-smoke: {{\"kind\":\"sdl3-wheel-smoke\",\"vertical_ticks\":{d},\"horizontal_ticks\":{d},\"result\":\"pass\"}}\n",
            .{ wheel_ticks_delivered, horizontal_wheel_ticks_delivered },
        );
    }
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
        // A window manager can prepend its own marker text at point-min, so
        // the bounded evidence is that the yank landed at the selection point.
        const pasted = scene.text.items.len > 0 and
            std.mem.endsWith(u8, scene.text.items[0].bytes, "EmacsEmacs Proto-UI");
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

/// Draw one diagnostic string with the frame's real font, centred in a band of
/// HEIGHT starting at Y.  The chassis widgets (dialogs, tool bar, tooltips,
/// IME) share this so their text matches the body.
fn drawLabel(
    list: *renderer_policy.DrawList,
    x: f32,
    y: f32,
    height: f32,
    bytes: []const u8,
    color: renderer_policy.Color,
) !void {
    const font_height: f32 = @floatFromInt(unicode_text_renderer.fontHeight());
    const offset: f32 = @max(0, @divTrunc(height - font_height, 2));
    try list.drawUnicodeText(x, y + offset, bytes, color, 0);
}

fn findSceneRow(scene: *const frontend.Scene, window_id: u64, row_index: u32) ?frontend.Row {
    for (scene.rows.items) |row| {
        if (row.window_id == window_id and row.index == row_index) return row;
    }
    return null;
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
        // Only runs that replace the row's plain text suppress it; a mode-line
        // run attaches to a row for validation but draws its own text.
        if (run.covers_row and run.window_id == window_id and run.row_index == row_index)
            return true;
    }
    return false;
}

/// Which window chrome row a run replaces.
const ChromeLine = enum { mode_line, header_line, tab_line };

/// True when the window's chrome row of KIND is already drawn as runs.
fn chromeLineHasRuns(scene: *const frontend.Scene, window_id: u64, kind: ChromeLine) bool {
    for (scene.glyph_runs.items) |run| {
        const matches = switch (kind) {
            .mode_line => run.mode_line,
            .header_line => run.header_line,
            .tab_line => run.tab_line,
        };
        if (matches and run.window_id == window_id) return true;
    }
    return false;
}

fn sceneHasText(scene: *const frontend.Scene, needle: []const u8) bool {
    for (scene.text.items) |line| {
        if (std.mem.indexOf(u8, line.bytes, needle) != null) return true;
    }
    return false;
}

fn sceneWindowHasText(scene: *const frontend.Scene, window_id: u64, needle: []const u8) bool {
    for (scene.text.items) |line| {
        if (line.window_id == window_id and
            std.mem.indexOf(u8, line.bytes, needle) != null) return true;
    }
    return false;
}

fn sceneWindowTextStartsWith(
    scene: *const frontend.Scene,
    window_id: u64,
    prefix: []const u8,
) bool {
    for (scene.text.items) |line| {
        if (line.window_id == window_id and
            line.bytes.len >= prefix.len and
            std.mem.eql(u8, line.bytes[0..prefix.len], prefix)) return true;
    }
    return false;
}

/// Fill color for a window's cursor: the published cursor face background when
/// there is one, else the window's default-face foreground.
fn cursorColor(scene: *const frontend.Scene, window_id: u64) renderer_policy.Color {
    if (scene.faces.lookup(facts.cursor_face_id)) |face| {
        if (face.payload.presence.background) {
            return .{
                .r = face.payload.background[0],
                .g = face.payload.background[1],
                .b = face.payload.background[2],
                .a = 255,
            };
        }
    }
    return windowFaceForeground(scene, window_id) orelse
        .{ .r = 0xff, .g = 0xd5, .b = 0x4d, .a = 255 };
}

fn drawDiagnosticWindowLine(
    scene: *frontend.Scene,
    list: *renderer_policy.DrawList,
    line: *const frontend.ModeLine,
) !void {
    const owner = findSceneWindow(scene, line.window_id) orelse return error.WindowLineWithoutWindow;
    // A published face keeps the bar on Emacs's own colors: the real
    // header-line and tab-line faces for those aux lines, the active or
    // inactive mode-line face otherwise.  Without one the bounded diagnostic
    // colors are used.
    const active_mode_line = line.flags & frontend.mode_line_active != 0;
    const primary_face_id: u32 = if (line.flags & frontend.aux_line_header != 0)
        facts.header_line_face_id
    else if (line.flags & frontend.aux_line_tab != 0)
        facts.tab_line_face_id
    else if (active_mode_line)
        facts.mode_line_face_id
    else
        facts.mode_line_inactive_face_id;
    const window_line_face = scene.faces.lookup(primary_face_id) orelse scene.faces.lookup(facts.mode_line_face_id);
    const bar_color: renderer_policy.Color = if (window_line_face) |face|
        if (face.payload.presence.background)
            .{
                .r = face.payload.background[0],
                .g = face.payload.background[1],
                .b = face.payload.background[2],
                .a = 255,
            }
        else
            .{ .r = 0x20, .g = 0x24, .b = 0x2c, .a = 255 }
    else
        .{ .r = 0x20, .g = 0x24, .b = 0x2c, .a = 255 };
    const text_color: renderer_policy.Color = if (window_line_face) |face|
        if (face.payload.presence.foreground)
            .{
                .r = face.payload.foreground[0],
                .g = face.payload.foreground[1],
                .b = face.payload.foreground[2],
                .a = 255,
            }
        else
            .{ .r = 0xe0, .g = 0xe6, .b = 0xf0, .a = 255 }
    else
        .{ .r = 0xe0, .g = 0xe6, .b = 0xf0, .a = 255 };
    const bar_rect = renderer_policy.LogicalRect{
        .x = @floatFromInt(owner.x + line.x),
        .y = @floatFromInt(owner.y + line.y),
        .width = @floatFromInt(line.width),
        .height = @floatFromInt(line.height),
    };
    try list.fillRect(bar_rect, bar_color);
    // A real mode-line face carries a released-button box, so the approximation
    // bars draw its border (the header/tab lines have no box).
    if (window_line_face) |face| {
        if (face.payload.box != .none) {
            const bars = renderer_policy.faceDecorationBars(bar_rect.x, bar_rect.y, bar_rect.width, bar_rect.height, .{
                .box = @enumFromInt(@intFromEnum(face.payload.box)),
                .box_color = if (face.payload.presence.box_color) .{
                    .r = face.payload.box_color[0],
                    .g = face.payload.box_color[1],
                    .b = face.payload.box_color[2],
                    .a = 255,
                } else null,
                .box_width = face.payload.box_line_width,
                .foreground = text_color,
            });
            for (bars.slice()) |bar| try list.fillRect(bar.rect, bar.color);
        }
    }
    // Real display-backed frames report mode lines around 15 pixels tall, so a
    // sixteen-pixel floor would hide a real Emacs mode line; eight pixels still
    // keeps the one- or two-pixel diagnostic bars textless.
    // Only runs for this exact chrome row suppress its plain text, so a mode
    // line with runs never hides a header or tab line's own text.
    const chrome_has_runs = if (line.flags & frontend.aux_line_header != 0)
        chromeLineHasRuns(scene, line.window_id, .header_line)
    else if (line.flags & frontend.aux_line_tab != 0)
        chromeLineHasRuns(scene, line.window_id, .tab_line)
    else
        chromeLineHasRuns(scene, line.window_id, .mode_line);
    if (line.height >= 8 and input_policy.isAsciiText(line.bytes[0..line.len]) and
        !chrome_has_runs)
    {
        const available_width: i64 = @as(i64, line.width) - 8;
        const visible_bytes: usize = if (available_width < 8)
            0
        else
            @min(line.len, @as(usize, @intCast(@divTrunc(available_width, 8))));
        if (visible_bytes > 0) {
            // The bar text uses the frame's real font, centred in the line.
            const font_height = unicode_text_renderer.fontHeight();
            const text_y: i64 = @as(i64, owner.y + line.y) +
                @max(1, @divTrunc(@as(i64, line.height) - font_height, 2));
            try list.drawUnicodeText(
                @floatFromInt(owner.x + line.x + 4),
                @floatFromInt(text_y),
                line.bytes[0..visible_bytes],
                text_color,
                0,
            );
        }
    }
}

/// Draw one cursor in its bounded shape.
///
/// Box, bar, and horizontal-bar cursors are solid: their shape already comes
/// from the cursor geometry the adapter published.  The hollow and underline
/// shapes are rendered inside the same rectangle so the cursor can never draw
/// outside the geometry the backend validated.
fn drawCursor(
    list: *renderer_policy.DrawList,
    rect: renderer_policy.LogicalRect,
    shape: frontend.CursorShape,
    color: renderer_policy.Color,
) !void {
    switch (shape) {
        .box, .bar, .hbar => try list.fillRect(rect, color),
        .hollow => {
            try list.fillRect(.{ .x = rect.x, .y = rect.y, .width = rect.width, .height = 1 }, color);
            try list.fillRect(.{
                .x = rect.x,
                .y = rect.y + rect.height - 1,
                .width = rect.width,
                .height = 1,
            }, color);
            try list.fillRect(.{ .x = rect.x, .y = rect.y, .width = 1, .height = rect.height }, color);
            try list.fillRect(.{
                .x = rect.x + rect.width - 1,
                .y = rect.y,
                .width = 1,
                .height = rect.height,
            }, color);
        },
        .underline => try list.fillRect(.{
            .x = rect.x,
            .y = rect.y + rect.height - 2,
            .width = rect.width,
            .height = 2,
        }, color),
    }
}

/// Foreground color of the live default face bound to a window, if any.
///
/// The bounded facts rows carry no per-line or per-run face, so a window's
/// default face is the only face live text can honour.  A missing binding, a
/// stale generation, or a face without a foreground falls back to the draw
/// default instead of guessing a color.
fn windowFaceForeground(scene: *const frontend.Scene, window_id: u64) ?renderer_policy.Color {
    for (scene.window_faces.items) |state| {
        if (state.window_id != window_id) continue;
        const face = scene.faces.lookup(state.face_id) orelse return null;
        if (face.generation != state.face_generation) return null;
        if (!face.payload.presence.foreground) return null;
        return .{
            .r = face.payload.foreground[0],
            .g = face.payload.foreground[1],
            .b = face.payload.foreground[2],
            .a = face.payload.foreground[3],
        };
    }
    return null;
}

/// Single source of truth for the logical-to-output scale.  The draw path and
/// pointer hit testing must agree or a rendered row would not be clickable.
fn sceneFrameScale(
    header: protocol.FrameUpdateHeader,
    output_width: i32,
    output_height: i32,
) f32 {
    return @min(
        @as(f32, @floatFromInt(output_width)) / @as(f32, @floatFromInt(header.logical_width)),
        @as(f32, @floatFromInt(output_height)) / @as(f32, @floatFromInt(header.logical_height)),
    );
}

/// SDL reports window coordinates, but the bounded pointer intents, the
/// geometry facts, and the scrollbar and menu-bar hit tests all use the frame's
/// logical coordinates, so a scaled window converts before an intent is built.
fn pointerFrameCoordinate(window: *SDL_Window, scene: *const frontend.Scene, value: i32) i32 {
    const header = scene.frame_header orelse return value;
    const scale = sceneWindowScale(window, header);
    if (!(scale > 0)) return value;
    return @intFromFloat(@as(f32, @floatFromInt(value)) / scale);
}

/// The logical-to-window scale of the live SDL window, or zero when the window
/// has no usable size.
fn sceneWindowScale(window: *SDL_Window, header: protocol.FrameUpdateHeader) f32 {
    var output_width: c_int = 0;
    var output_height: c_int = 0;
    SDL_GetWindowSize(window, &output_width, &output_height);
    if (output_width <= 0 or output_height <= 0) return 0;
    return sceneFrameScale(header, output_width, output_height);
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
    const scale = sceneFrameScale(header, output_width, output_height);
    const pixel: f32 = 1 / scale;

    list.reset();
    list.setLogicalSize(@floatFromInt(header.logical_width), @floatFromInt(header.logical_height));
    try list.clear(.{ .r = 0x18, .g = 0x20, .b = 0x2a });
    try list.fillRect(
        .{ .x = 0, .y = 0, .width = @floatFromInt(header.logical_width), .height = @floatFromInt(header.logical_height) },
        .{ .r = 0x18, .g = 0x20, .b = 0x2a },
    );

    for (scene.window_faces.items) |state| {
        const owner = findSceneWindow(scene, state.window_id) orelse continue;
        if (!owner.visible) continue;
        const face = scene.faces.lookup(state.face_id) orelse continue;
        if (face.generation != state.face_generation or !face.payload.presence.background) continue;
        try list.fillRect(.{
            .x = @floatFromInt(owner.x),
            .y = @floatFromInt(owner.y),
            .width = @floatFromInt(owner.width),
            .height = @floatFromInt(owner.height),
        }, .{
            .r = face.payload.background[0],
            .g = face.payload.background[1],
            .b = face.payload.background[2],
            .a = face.payload.background[3],
        });
    }

    for (scene.window_geometries.items) |state| {
        const owner = findSceneWindow(scene, state.window_id) orelse continue;
        if (!owner.visible) continue;
        const left: f32 = @floatFromInt(owner.x + state.body.x);
        const top: f32 = @floatFromInt(owner.y + state.body.y);
        const width: f32 = @floatFromInt(state.body.width);
        const height: f32 = @floatFromInt(state.body.height);
        const color = renderer_policy.Color{ .r = 0x38, .g = 0xd9, .b = 0xa9, .a = 255 };
        try list.fillRect(.{ .x = left, .y = top, .width = width, .height = 1 }, color);
        try list.fillRect(.{
            .x = left,
            .y = top + height - 1,
            .width = width,
            .height = 1,
        }, color);
        try list.fillRect(.{ .x = left, .y = top, .width = 1, .height = height }, color);
        try list.fillRect(.{
            .x = left + width - 1,
            .y = top,
            .width = 1,
            .height = height,
        }, color);
    }

    for (scene.window_zones.items) |state| {
        const owner = findSceneWindow(scene, state.window_id) orelse continue;
        if (!owner.visible) continue;
        var index: usize = 0;
        while (index < frontend.window_zone_count) : (index += 1) {
            const bit = @as(u32, 1) << @intCast(index);
            const rect = frontend.zoneRect(state, bit) orelse continue;
            const color = renderer_policy.Color{ .r = 0xcc, .g = 0x66, .b = 0x33, .a = 255 };
            try list.fillRect(.{
                .x = @floatFromInt(owner.x + rect.x),
                .y = @floatFromInt(owner.y + rect.y),
                .width = @floatFromInt(rect.width),
                .height = 1,
            }, color);
        }
    }

    for (scene.mouse_highlights[0..scene.mouse_highlight_count]) |highlight| {
        const owner = findSceneWindow(scene, highlight.window_id) orelse continue;
        if (!owner.visible or highlight.flags & frontend.MouseHighlightFlags.visible == 0) continue;
        const face = scene.faces.lookup(highlight.face_id) orelse continue;
        if (face.generation != highlight.face_generation) continue;
        const color = if (face.payload.presence.background)
            renderer_policy.Color{
                .r = face.payload.background[0],
                .g = face.payload.background[1],
                .b = face.payload.background[2],
                .a = face.payload.background[3],
            }
        else
            renderer_policy.Color{ .r = 0x4c, .g = 0xaf, .b = 0x50, .a = 255 };
        try list.fillRect(.{
            .x = @floatFromInt(owner.x + highlight.rect.x),
            .y = @floatFromInt(owner.y + highlight.rect.y),
            .width = @floatFromInt(highlight.rect.width),
            .height = @floatFromInt(highlight.rect.height),
        }, color);
    }

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
        const color = renderer_policy.Color{ .r = fringe.color[0], .g = fringe.color[1], .b = fringe.color[2], .a = fringe.color[3] };
        if (scene.fringe_bitmaps.lookup(fringe.fringe_id)) |resource| {
            if (resource.generation != fringe.fringe_generation) continue;
            const cell_width: f32 = @as(f32, @floatFromInt(rect.width)) / @as(f32, @floatFromInt(resource.payload.width));
            const cell_height: f32 = @as(f32, @floatFromInt(rect.height)) / @as(f32, @floatFromInt(resource.payload.height));
            var y: usize = 0;
            while (y < resource.payload.height) : (y += 1) {
                var x: usize = 0;
                while (x < resource.payload.width) : (x += 1) {
                    if (!frontend.fringeBitmapBit(resource.payload, x, y)) continue;
                    try list.fillRect(.{
                        .x = @as(f32, @floatFromInt(owner.x + rect.x)) + @as(f32, @floatFromInt(x)) * cell_width,
                        .y = @as(f32, @floatFromInt(owner.y + rect.y)) + @as(f32, @floatFromInt(y)) * cell_height,
                        .width = cell_width,
                        .height = cell_height,
                    }, color);
                }
            }
        } else {
            try list.fillRect(.{
                .x = @floatFromInt(owner.x + rect.x),
                .y = @floatFromInt(owner.y + rect.y),
                .width = @floatFromInt(rect.width),
                .height = @floatFromInt(rect.height),
            }, color);
        }
    }

    for (scene.scroll_states.items) |state| {
        if (state.flags & frontend.WindowScrollFlags.horizontal_visible != 0) {
            const layout = frontend.horizontalScrollbarLayout(scene, state.window_id) orelse continue;
            try list.fillRect(.{
                .x = layout.track_x,
                .y = layout.track_y,
                .width = layout.track_width,
                .height = layout.track_height,
            }, .{ .r = 0x20, .g = 0x24, .b = 0x2c, .a = 255 });
            try list.fillRect(.{
                .x = layout.thumb_x,
                .y = layout.track_y,
                .width = layout.thumb_width,
                .height = layout.track_height,
            }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2, .a = 255 });
            continue;
        }
        const layout = frontend.scrollbarLayout(scene, state.window_id) orelse continue;
        const track = renderer_policy.LogicalRect{
            .x = layout.track_x,
            .y = layout.track_y,
            .width = layout.track_width,
            .height = layout.track_height,
        };
        try list.fillRect(track, .{ .r = 0x20, .g = 0x24, .b = 0x2c, .a = 255 });
        try list.fillRect(.{
            .x = track.x,
            .y = layout.thumb_y,
            .width = track.width,
            .height = layout.thumb_height,
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

    for (scene.windows.items) |owner| {
        const rect = renderer_policy.LogicalRect{
            .x = @floatFromInt(owner.x),
            .y = @floatFromInt(owner.y),
            .width = @floatFromInt(owner.width),
            .height = @floatFromInt(owner.height),
        };
        const outline = renderer_policy.Color{ .r = 0x46, .g = 0x51, .b = 0x66, .a = 255 };
        try list.fillRect(.{ .x = rect.x, .y = rect.y, .width = rect.width, .height = 1 }, outline);
        try list.fillRect(.{ .x = rect.x, .y = rect.y + rect.height - 1, .width = rect.width, .height = 1 }, outline);
        try list.fillRect(.{ .x = rect.x, .y = rect.y, .width = 1, .height = rect.height }, outline);
        try list.fillRect(.{ .x = rect.x + rect.width - 1, .y = rect.y, .width = 1, .height = rect.height }, outline);
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
        const row = findSceneRow(scene, line.window_id, line.row_index) orelse continue;
        const owner = findSceneWindow(scene, line.window_id) orelse continue;
        if (line.bytes.len == 0) continue;
        if (rowHasGlyphRun(scene, owner.id, row.index)) continue;
        const origin = debugTextOrigin(owner, row);
        const text_x: i64 = origin.x;
        // The body rows use the frame's real font, centred in the row: its
        // glyph box is shorter than the line height, so the debug-text baseline
        // offset would push it into the next row.
        const font_height = unicode_text_renderer.fontHeight();
        const text_y: i64 = @as(i64, owner.y + row.y) +
            @max(0, @divTrunc(@as(i64, row.visible_height) - font_height, 2));
        if (text_x < std.math.minInt(i32) or text_x > std.math.maxInt(i32) or
            text_y < std.math.minInt(i32) or text_y > std.math.maxInt(i32)) return error.InvalidTextGeometry;
        try list.drawUnicodeText(
            @floatFromInt(text_x),
            @floatFromInt(text_y),
            line.bytes,
            windowFaceForeground(scene, owner.id) orelse .{ .r = 0xe8, .g = 0xee, .b = 0xf8, .a = 255 },
            0,
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
        // `:inverse-video` swaps the run's fill and text halves, which is how
        // the default theme's `match`/`secondary-selection` faces read.
        const inverse = if (face) |resource| resource.payload.inverse_video else false;
        if (face) |resource| {
            const fill_source: ?[4]u8 = if (inverse)
                (if (resource.payload.presence.foreground) resource.payload.foreground else null)
            else
                (if (resource.payload.presence.background) resource.payload.background else null);
            if (fill_source) |color| {
                try list.fillRect(.{
                    .x = @floatFromInt(owner.x + run.x),
                    .y = @floatFromInt(owner.y + run.y),
                    .width = @floatFromInt(run.width),
                    .height = @floatFromInt(run.height),
                }, .{
                    .r = color[0],
                    .g = color[1],
                    .b = color[2],
                    .a = color[3],
                });
            }
        }
        const foreground: ?renderer_policy.Color = if (face) |resource| blk: {
            const text_source: ?[4]u8 = if (inverse)
                (if (resource.payload.presence.background) resource.payload.background else null)
            else
                (if (resource.payload.presence.foreground) resource.payload.foreground else null);
            break :blk if (text_source) |color| renderer_policy.Color{
                .r = color[0],
                .g = color[1],
                .b = color[2],
                .a = color[3],
            } else null;
        } else null;
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
                    .box_width = resource.payload.box_line_width,
                    .foreground = foreground,
                },
            );
            for (decorations.slice()) |bar| {
                try list.fillRect(bar.rect, bar.color);
            }
        }
        if (run.shaped) {
            if (scene.atlases.first() == null) return error.AtlasGlyphsMissing;
            var shaped_pen_x: f32 = @floatFromInt(owner.x + run.x);
            for (run.shaped_glyphs[0..run.shaped_count]) |glyph| {
                const sampled = scene.atlases.findGlyphPixels(run.font_id, glyph.glyph_id) orelse
                    return error.AtlasGlyphsMissing;
                try list.drawAtlasGlyph(.{
                    .x = shaped_pen_x + @as(f32, @floatFromInt(glyph.x_offset)),
                    .y = @floatFromInt(owner.y + run.y + glyph.y_offset),
                    .width = @floatFromInt(sampled.width),
                    .height = @floatFromInt(sampled.height),
                }, .{
                    .x = @floatFromInt(sampled.x),
                    .y = @floatFromInt(sampled.y),
                    .width = @floatFromInt(sampled.width),
                    .height = @floatFromInt(sampled.height),
                }, sampled.bytes, sampled.page_width, sampled.page_height, sampled.cache_key, sampled.cache_revision, sampled.atlas_id, sampled.page_index, sampled.generation);
                shaped_pen_x += @floatFromInt(glyph.advance_x);
            }
            continue;
        }
        // ASCII GLYPH_RUN v1/v2 remains a fallback; it does not imply shaped
        // text, full fonts, complete atlas rendering, or full Emacs face parity.
        var atlas_rendered = scene.atlases.first() != null;
        const pen_y: f32 = @floatFromInt(owner.y + run.y);
        const preferred_font: u32 = if (face) |resource|
            (if (resource.payload.presence.font) resource.payload.font_id else 0)
        else
            0;
        if (atlas_rendered) {
            for (run.text) |code| {
                if (scene.atlases.findGlyphPixels(preferred_font, code) == null) {
                    atlas_rendered = false;
                    break;
                }
            }
        }
        var pen_x: f32 = @floatFromInt(owner.x + run.x);
        if (atlas_rendered) {
            for (run.text) |code| {
                const sampled = scene.atlases.findGlyphPixels(preferred_font, code).?;
                try list.drawAtlasGlyph(.{
                    .x = pen_x,
                    .y = pen_y,
                    .width = @floatFromInt(sampled.width),
                    .height = @floatFromInt(sampled.height),
                }, .{
                    .x = @floatFromInt(sampled.x),
                    .y = @floatFromInt(sampled.y),
                    .width = @floatFromInt(sampled.width),
                    .height = @floatFromInt(sampled.height),
                }, sampled.bytes, sampled.page_width, sampled.page_height, sampled.cache_key, sampled.cache_revision, sampled.atlas_id, sampled.page_index, sampled.generation);
                pen_x += @floatFromInt(sampled.advance_x);
            }
        }
        if (!atlas_rendered) {
            // The ASCII run fallback uses the frame's real font, centred in the
            // run's row so it matches the plain body rows.
            const font_height = unicode_text_renderer.fontHeight();
            const run_base_y: f32 = @floatFromInt(owner.y + run.y);
            const run_offset: i64 = @max(0, @divTrunc(@as(i64, run.height) - font_height, 2));
            const run_y: f32 = run_base_y + @as(f32, @floatFromInt(run_offset));
            try list.drawUnicodeText(
                @floatFromInt(owner.x + run.x),
                run_y,
                run.text,
                foreground orelse .{ .r = 0xe8, .g = 0xee, .b = 0xf8, .a = 255 },
                run.style | (if (run.font_family >= 1)
                    @as(u8, 0x80) | (@as(u8, @intCast(run.font_family - 1)) << 4)
                else
                    0),
            );
        }
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

    for (scene.mode_lines[0..scene.mode_line_count]) |mode_line| {
        try drawDiagnosticWindowLine(scene, list, &mode_line);
    }
    for (scene.aux_lines[0..scene.aux_line_count]) |*aux_line| {
        try drawDiagnosticWindowLine(scene, list, aux_line);
    }

    // The frame's echo area is the bottom strip below the root window.
    if (scene.strings.lookup(facts.echo_string_id)) |resource| {
        if (resource.bytes.len != 0 and scene.frame_header != null and
            input_policy.isAsciiText(resource.bytes))
        {
            const echo_header = scene.frame_header.?;
            const row_height: i32 = if (scene.rows.items.len != 0) scene.rows.items[0].height else 15;
            const echo_y: i32 = echo_header.logical_height - row_height;
            if (echo_y >= 0 and row_height > 0) {
                // The echo area is the frame's bottom strip and carries the
                // frame's own default face colors, so a message on a light
                // frame is not drawn in the diagnostic dark-strip colors.
                const echo_face = scene.faces.lookup(facts.default_face_id);
                const strip: renderer_policy.Color = if (echo_face) |face| blk: {
                    break :blk if (face.payload.presence.background)
                        .{
                            .r = face.payload.background[0],
                            .g = face.payload.background[1],
                            .b = face.payload.background[2],
                            .a = 255,
                        }
                    else
                        .{ .r = 0x20, .g = 0x24, .b = 0x2c, .a = 255 };
                } else .{ .r = 0x20, .g = 0x24, .b = 0x2c, .a = 255 };
                const ink: renderer_policy.Color = if (echo_face) |face| blk: {
                    break :blk if (face.payload.presence.foreground)
                        .{
                            .r = face.payload.foreground[0],
                            .g = face.payload.foreground[1],
                            .b = face.payload.foreground[2],
                            .a = 255,
                        }
                    else
                        .{ .r = 0xff, .g = 0xd5, .b = 0x4d, .a = 255 };
                } else .{ .r = 0xff, .g = 0xd5, .b = 0x4d, .a = 255 };
                try list.fillRect(.{
                    .x = 0,
                    .y = @floatFromInt(echo_y),
                    .width = @floatFromInt(echo_header.logical_width),
                    .height = @floatFromInt(row_height),
                }, strip);
                try drawLabel(
                    list,
                    4,
                    @floatFromInt(echo_y),
                    @floatFromInt(row_height),
                    resource.bytes,
                    ink,
                );
            }
        }
    }

    for (scene.cursors[0..scene.cursor_count]) |cursor| {
        if (!cursor.visible) continue;
        const owner = findSceneWindow(scene, cursor.window_id) orelse return error.CursorWithoutWindow;
        const size = renderer_policy.renderedCursorSize(cursor.width, cursor.height);
        try drawCursor(
            list,
            .{
                .x = @floatFromInt(owner.x + cursor.x),
                .y = @floatFromInt(owner.y + cursor.y),
                .width = @floatFromInt(size.width),
                .height = @floatFromInt(size.height),
            },
            // A non-selected window marks its caret hollow, which is how Emacs
            // draws the inactive cursor; the selected window keeps its real kind.
            frontend.cursorShape(if (cursor.active) cursor.kind else frontend.cursor_kind_hollow),
            // A published cursor face keeps the cursor on Emacs's own color;
            // otherwise the window's default face foreground is used.
            cursorColor(scene, owner.id),
        );
    }

    if (frontend.menuBarLayout(scene)) |bar| {
        // The menu-bar row is reserved above the window, so the bar is anchored
        // at the frame origin and spans the reserved strip.  Geometry and
        // identity come from the shared layout the hit test also uses; the
        // backend owns the labels and their order.
        for (bar.slots[0..bar.count]) |slot| {
            const rect = renderer_policy.LogicalRect{
                .x = @floatFromInt(slot.x),
                .y = 0,
                .width = @floatFromInt(slot.width),
                .height = @floatFromInt(bar.strip_height),
            };
            try list.fillRect(rect, .{ .r = 0x20, .g = 0x24, .b = 0x2c });
            try list.fillRect(.{ .x = rect.x, .y = rect.y + rect.height - 1, .width = rect.width, .height = 1 }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
            if (input_policy.isAsciiText(slot.label)) {
                // The bar label uses the frame's real font, centred in the
                // reserved strip.
                const font_height = unicode_text_renderer.fontHeight();
                try list.drawUnicodeText(
                    rect.x + 1,
                    rect.y + @max(0, @divTrunc(rect.height - @as(f32, @floatFromInt(font_height)), 2)),
                    slot.label,
                    .{ .r = 0xff, .g = 0xd5, .b = 0x4d },
                    0,
                );
            }
        }
    }

    if (scene.menu_open) |open| {
        const model = scene.menu_model orelse return error.MenuWithoutModel;
        if (findSceneWindow(scene, open.window_id) == null) return error.MenuWithoutWindow;
        const bounds = frontend.menuPopupBounds(scene) orelse return error.MenuWithoutChildren;
        const rect = renderer_policy.LogicalRect{
            .x = bounds.x,
            .y = bounds.y,
            .width = bounds.width,
            .height = bounds.height,
        };
        try list.fillRect(rect, .{ .r = 0x20, .g = 0x24, .b = 0x2c });
        var row_index: usize = 0;
        for (model.nodes) |*node| {
            const row: f32 = rect.y + @as(f32, @floatFromInt(row_index)) * bounds.row_height;
            if (node.parent_item_id != open.item_id or
                node.flags & protocol.MenuNodeFlags.visible == 0) continue;
            const highlighted = scene.menu_highlight_item != 0 and
                node.item_id == scene.menu_highlight_item;
            try list.fillRect(.{
                .x = rect.x,
                .y = row,
                .width = rect.width,
                .height = bounds.row_height,
            }, if (highlighted)
                renderer_policy.Color{ .r = 0x39, .g = 0x45, .b = 0x5c }
            else
                renderer_policy.Color{ .r = 0x2a, .g = 0x30, .b = 0x3c });
            // Checkbox and radio rows reserve a leading slot for the selection
            // marker; the marker only reflects the backend-owned `selected`
            // flag and never changes it.
            const stateful = node.kind == .checkbox or node.kind == .radio or
                (node.icon_image_id != 0 and node.icon_image_generation != 0);
            const selected = node.flags & protocol.MenuNodeFlags.selected != 0;
            const menu_icon = if (node.icon_image_id != 0 and
                node.icon_image_generation != 0)
                scene.images.lookup(node.icon_image_id)
            else
                null;
            var icon_occupies_marker = false;
            if (menu_icon) |image| {
                if (image.complete and image.generation == node.icon_image_generation) {
                    icon_occupies_marker = true;
                    try list.drawImage(.{
                        .x = rect.x + 3,
                        .y = row + 1,
                        .width = 4,
                        .height = 4,
                    }, image.bytes, image.metadata.width, image.metadata.height);
                }
            }
            if (node.kind == .checkbox and selected and !icon_occupies_marker) {
                try list.fillRect(.{
                    .x = rect.x + 3,
                    .y = row + (bounds.row_height - 4) / 2,
                    .width = 4,
                    .height = 4,
                }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
            } else if (node.kind == .radio and selected and !icon_occupies_marker) {
                try list.fillRect(.{
                    .x = rect.x + 4,
                    .y = row + (bounds.row_height - 2) / 2,
                    .width = 2,
                    .height = 2,
                }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
            }
            const label = node.label[0..node.label_len];
            // A separator row has no label; the draw list rejects empty text.
            if (label.len != 0 and input_policy.isAsciiText(label)) {
                // A disabled row is drawn dimmed because the model says so; the
                // frontend never decides enablement itself.
                const color: renderer_policy.Color = if (node.flags & protocol.MenuNodeFlags.enabled == 0)
                    .{ .r = 0x88, .g = 0x90, .b = 0x9c }
                else
                    .{ .r = 0xff, .g = 0xd5, .b = 0x4d };
                // The row label uses the frame's real font, centred in the row.
                const font_height = unicode_text_renderer.fontHeight();
                try list.drawUnicodeText(
                    rect.x + (if (stateful) @as(f32, 12) else 4),
                    row + @max(0, @divTrunc(bounds.row_height - @as(f32, @floatFromInt(font_height)), 2)),
                    label,
                    color,
                    0,
                );
            }
            // The row's real key hint is right-aligned in the popup row, the
            // way Emacs's own menu draws it.
            const key = node.key[0..node.key_len];
            if (key.len != 0 and input_policy.isAsciiText(key)) {
                const font_height = unicode_text_renderer.fontHeight();
                const key_width: f32 = @floatFromInt(@as(i32, @intCast(key.len)) * 7);
                try list.drawUnicodeText(
                    rect.x + rect.width - key_width - 4,
                    row + @max(0, @divTrunc(bounds.row_height - @as(f32, @floatFromInt(font_height)), 2)),
                    key,
                    .{ .r = 0x88, .g = 0x90, .b = 0x9c },
                    0,
                );
            }
            row_index += 1;
        }
    }

    if (frontend.menuHelpTip(scene)) |tip| {
        try list.fillRect(.{
            .x = tip.x,
            .y = tip.y,
            .width = tip.width,
            .height = tip.height(),
        }, .{ .r = 0x13, .g = 0x19, .b = 0x24 });
        const font_height = unicode_text_renderer.fontHeight();
        for (tip.lines[0..tip.line_count], 0..) |line, line_index| {
            try list.drawUnicodeText(
                tip.x + 4,
                tip.y + @as(f32, @floatFromInt(line_index)) * tip.line_height +
                    @max(0, @divTrunc(tip.line_height - @as(f32, @floatFromInt(font_height)), 2)),
                line,
                .{ .r = 0xe0, .g = 0xe6, .b = 0xf0 },
                0,
            );
        }
    }

    if (scene.toolbar) |model| {
        if (frontend.toolbarLayout(scene)) |layout| {
            // The frame's real tool-bar face colors keep the strip on Emacs's
            // own colors; without them the bounded diagnostic colors are used.
            const toolbar_face = scene.faces.lookup(facts.tool_bar_face_id);
            const strip_color: renderer_policy.Color = if (toolbar_face) |face| blk: {
                break :blk if (face.payload.presence.background)
                    .{
                        .r = face.payload.background[0],
                        .g = face.payload.background[1],
                        .b = face.payload.background[2],
                        .a = 255,
                    }
                else
                    .{ .r = 0x1d, .g = 0x22, .b = 0x2c };
            } else .{ .r = 0x1d, .g = 0x22, .b = 0x2c };
            const label_color: renderer_policy.Color = if (toolbar_face) |face| blk: {
                break :blk if (face.payload.presence.foreground)
                    .{
                        .r = face.payload.foreground[0],
                        .g = face.payload.foreground[1],
                        .b = face.payload.foreground[2],
                        .a = 255,
                    }
                else
                    .{ .r = 0xff, .g = 0xd5, .b = 0x4d };
            } else .{ .r = 0xff, .g = 0xd5, .b = 0x4d };
            const slot_color: renderer_policy.Color = if (toolbar_face) |face| blk: {
                // A real tool-bar face colors the buttons the same as its strip;
                // the press/selection highlight still distinguishes them.
                break :blk if (face.payload.presence.background) strip_color else .{ .r = 0x27, .g = 0x2e, .b = 0x3b };
            } else .{ .r = 0x27, .g = 0x2e, .b = 0x3b };
            const row = renderer_policy.LogicalRect{
                .x = layout.row_x,
                .y = layout.row_y,
                .width = layout.row_width,
                .height = layout.row_height,
            };
            try list.fillRect(row, strip_color);
            for (layout.slots[0..layout.slot_count]) |slot| {
                // Keep the label slice pointing into the Scene-owned model; the
                // draw list retains the bytes pointer past this iteration.
                const item = &model.items[slot.item_index];
                const rect = renderer_policy.LogicalRect{
                    .x = slot.x,
                    .y = slot.y,
                    .width = slot.width,
                    .height = slot.height,
                };
                const selected = item.flags & protocol.ToolbarItemFlags.selected != 0;
                const pressed = item.flags & protocol.ToolbarItemFlags.pressed != 0;
                try list.fillRect(rect, if (pressed or selected)
                    renderer_policy.Color{ .r = 0x39, .g = 0x45, .b = 0x5c }
                else
                    slot_color);
                // A real tool-bar face carries a released-button box, so the
                // button border is drawn as approximation bars.
                if (toolbar_face) |face| {
                    if (face.payload.box != .none) {
                        const bars = renderer_policy.faceDecorationBars(rect.x, rect.y, rect.width, rect.height, .{
                            .box = @enumFromInt(@intFromEnum(face.payload.box)),
                            .box_width = face.payload.box_line_width,
                            .foreground = label_color,
                        });
                        for (bars.slice()) |bar| try list.fillRect(bar.rect, bar.color);
                    }
                }
                const text = item.label[0..item.label_len];
                // A live icon resource replaces the label.  Only the
                // backend-owned id/generation is honoured: an incomplete or
                // stale resource falls back to the label instead of drawing a
                // guessed icon.
                const icon = if (item.icon_image_id != 0 and item.icon_image_generation != 0)
                    scene.images.lookup(item.icon_image_id)
                else
                    null;
                if (icon) |image| {
                    if (image.complete and image.generation == item.icon_image_generation) {
                        try list.drawImage(
                            rect,
                            image.bytes,
                            image.metadata.width,
                            image.metadata.height,
                        );
                        continue;
                    }
                }
                if (text.len != 0 and input_policy.isAsciiText(text)) {
                    try drawLabel(list, rect.x + 4, rect.y, rect.height, text, label_color);
                }
            }
        }
    }

    if (scene.dialog) |dialog| {
        const layout = frontend.dialogLayout(scene) orelse return error.DialogWithoutWindow;
        const rect = renderer_policy.LogicalRect{
            .x = layout.x,
            .y = layout.y,
            .width = layout.width,
            .height = layout.height,
        };
        try list.fillRect(rect, .{ .r = 0x20, .g = 0x24, .b = 0x2c });
        try list.fillRect(.{ .x = rect.x, .y = rect.y, .width = rect.width, .height = 1 }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
        try list.fillRect(.{ .x = rect.x, .y = rect.y + rect.height - 1, .width = rect.width, .height = 1 }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
        try list.fillRect(.{ .x = rect.x, .y = rect.y, .width = 1, .height = rect.height }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
        try list.fillRect(.{ .x = rect.x + rect.width - 1, .y = rect.y, .width = 1, .height = rect.height }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
        const title = dialog.title[0..dialog.title_len];
        if (input_policy.isAsciiText(title)) {
            try drawLabel(list, rect.x + 4, rect.y, rect.height, title, .{ .r = 0xff, .g = 0xd5, .b = 0x4d });
        }
        const message = dialog.text[0..dialog.text_len];
        if (input_policy.isAsciiText(message)) {
            try drawLabel(list, rect.x + 4, rect.y + 9, 15, message, .{ .r = 0xe0, .g = 0xe6, .b = 0xf0 });
        }
        if (frontend.dialogFieldRect(scene)) |field| {
            try list.fillRect(.{
                .x = field.x,
                .y = field.y,
                .width = field.width,
                .height = field.height,
            }, .{ .r = 0x14, .g = 0x18, .b = 0x20 });
            const typed = frontend.dialogInput(scene);
            if (typed.len != 0 and input_policy.isAsciiText(typed)) {
                try drawLabel(
                    list,
                    field.x + 2,
                    field.y,
                    field.height,
                    typed,
                    .{ .r = 0xe0, .g = 0xe6, .b = 0xf0 },
                );
            }
        }
        for (layout.buttons[0..layout.button_count]) |slot| {
            try list.fillRect(.{
                .x = slot.x,
                .y = slot.y,
                .width = slot.width,
                .height = slot.height,
            }, .{ .r = 0x2a, .g = 0x30, .b = 0x3c });
            try list.fillRect(.{
                .x = slot.x,
                .y = slot.y,
                .width = slot.width,
                .height = 1,
            }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
            try drawLabel(list, slot.x + 4, slot.y, slot.height, slot.label, .{ .r = 0xff, .g = 0xd5, .b = 0x4d });
        }
    }

    if (scene.tooltip) |tip| {
        const owner = findSceneWindow(scene, tip.window_id) orelse return error.TooltipWithoutWindow;
        const rect = renderer_policy.LogicalRect{
            .x = @floatFromInt(owner.x + tip.x),
            .y = @floatFromInt(owner.y + tip.y),
            .width = @floatFromInt(tip.max_width),
            .height = @floatFromInt(tip.max_height),
        };
        try list.fillRect(rect, .{ .r = 0x20, .g = 0x24, .b = 0x2c });
        try list.fillRect(.{ .x = rect.x, .y = rect.y, .width = rect.width, .height = 1 }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
        try list.fillRect(.{ .x = rect.x, .y = rect.y + rect.height - 1, .width = rect.width, .height = 1 }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
        try list.fillRect(.{ .x = rect.x, .y = rect.y, .width = 1, .height = rect.height }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
        try list.fillRect(.{ .x = rect.x + rect.width - 1, .y = rect.y, .width = 1, .height = rect.height }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2 });
        const text = tip.text[0..tip.text_length];
        // The debug text path is ASCII-only; Unicode tooltip state is validated
        // and retained, but full font rendering is not claimed here.
        if (input_policy.isAsciiText(text)) {
            try drawLabel(list, rect.x + 4, rect.y, rect.height, text, .{ .r = 0xff, .g = 0xd5, .b = 0x4d });
        }
    }

    var preedit_context: ?*const frontend.ImeContext = null;
    for (scene.ime_contexts[0..scene.ime_context_count]) |*context| {
        const active_frame = scene.frame orelse return error.NoFrameUpdate;
        if (context.frame_id == active_frame.frame_id and context.focused and
            context.has_preedit and context.cursor_width > 0 and context.cursor_height > 0)
        {
            preedit_context = context;
            break;
        }
    }
    if (preedit_context) |context| {
        const owner = findSceneWindow(scene, context.window_id) orelse
            return error.ImePreeditWithoutWindow;
        const width: i32 = @max(72, context.cursor_width + 8);
        const height: i32 = @max(16, context.cursor_height);
        const rect = renderer_policy.LogicalRect{
            .x = @floatFromInt(owner.x + context.cursor_x),
            .y = @floatFromInt(owner.y + context.cursor_y),
            .width = @floatFromInt(width),
            .height = @floatFromInt(height),
        };
        try list.fillRect(rect, .{ .r = 0x20, .g = 0x28, .b = 0x38, .a = 255 });
        try list.fillRect(.{
            .x = rect.x,
            .y = rect.y,
            .width = rect.width,
            .height = 1,
        }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2, .a = 255 });
        try list.fillRect(.{
            .x = rect.x,
            .y = rect.y + rect.height - 1,
            .width = rect.width,
            .height = 1,
        }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2, .a = 255 });
        const preedit = context.preedit_bytes[0..context.preedit_len];
        if (preedit.len > 0 and input_policy.isAsciiText(preedit)) {
            try drawLabel(
                list,
                rect.x + 4,
                rect.y,
                rect.height,
                preedit,
                .{ .r = 0xff, .g = 0xd5, .b = 0x4d, .a = 255 },
            );
        }
    }

    var candidate_context: ?*const frontend.ImeContext = null;
    for (scene.ime_contexts[0..scene.ime_context_count]) |*context| {
        const active_frame = scene.frame orelse return error.NoFrameUpdate;
        if (context.frame_id == active_frame.frame_id and context.focused and
            context.has_candidates and context.candidate_width > 0 and context.candidate_height > 0)
        {
            candidate_context = context;
            break;
        }
    }
    if (candidate_context) |context| {
        const owner = findSceneWindow(scene, context.window_id) orelse
            return error.ImeCandidateWithoutWindow;
        const label = context.candidate_label[0..context.candidate_label_len];
        const selected_label = if (input_policy.isAsciiText(label)) label else "";
        const metadata_text = if (selected_label.len > 0)
            std.fmt.bufPrint(&list.candidate_metadata, "C {d}/{d} P {d}/{d} {s}", .{
                context.candidate_selected_index + 1,
                context.candidate_count,
                context.candidate_page_index + 1,
                context.candidate_page_count,
                selected_label,
            }) catch return error.ImeCandidateMetadataTooLarge
        else
            std.fmt.bufPrint(&list.candidate_metadata, "C {d}/{d} P {d}/{d}", .{
                context.candidate_selected_index + 1,
                context.candidate_count,
                context.candidate_page_index + 1,
                context.candidate_page_count,
            }) catch return error.ImeCandidateMetadataTooLarge;
        list.candidate_metadata_len = metadata_text.len;
        const rect = renderer_policy.LogicalRect{
            .x = @floatFromInt(owner.x + context.candidate_x),
            .y = @floatFromInt(owner.y + context.candidate_y),
            .width = @floatFromInt(@max(120, context.candidate_width)),
            .height = @floatFromInt(@max(16, context.candidate_height)),
        };
        try list.fillRect(rect, .{ .r = 0x20, .g = 0x24, .b = 0x2c, .a = 255 });
        try list.fillRect(.{
            .x = rect.x,
            .y = rect.y,
            .width = rect.width,
            .height = 1,
        }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2, .a = 255 });
        try list.fillRect(.{
            .x = rect.x,
            .y = rect.y + rect.height - 1,
            .width = rect.width,
            .height = 1,
        }, .{ .r = 0x71, .g = 0xa6, .b = 0xf2, .a = 255 });
        try drawLabel(
            list,
            rect.x + 4,
            rect.y,
            rect.height,
            metadata_text,
            .{ .r = 0xff, .g = 0xd5, .b = 0x4d, .a = 255 },
        );
    }
}

const UnicodeTextRenderer = struct {
    initialized: bool = false,
    font: ?*TTF_Font = null,
    /// Producer-negotiated alternate fonts indexed by family - 1: family 1 is
    /// the variable-pitch font, families 2 and 3 the extra bounded alternates.
    alt_fonts: [3]?*TTF_Font = .{ null, null, null },
    alt_font_paths: [3][128]u8 = .{ @splat(0), @splat(0), @splat(0) },
    alt_font_path_lens: [3]usize = .{ 0, 0, 0 },
    /// Bold/italic variants of `font`, indexed by the style bit mask.
    styled_fonts: [4]?*TTF_Font = .{ null, null, null, null },
    /// Optional fallback font covering scripts the adopted font lacks.
    fallback_font: ?*TTF_Font = null,
    cache: proto_ui.text_cache.TextureCache = .{},
    /// Point size the text font is opened at.  A real frame's published line
    /// height replaces the bounded default so the diagnostic text fits the rows
    /// the frame itself lays out.
    point_size: f32 = 16,
    /// Real font file the frame uses, when the producer resolved one.
    font_path: [128]u8 = @splat(0),
    font_path_len: usize = 0,

    fn fontPointSize(self: *const UnicodeTextRenderer) f32 {
        if (std.c.getenv("PROTO_UI_FONT_SIZE")) |raw| {
            const value = std.fmt.parseFloat(f32, std.mem.span(raw)) catch return self.point_size;
            if (value >= 8 and value <= 72) return value;
        }
        return self.point_size;
    }

    /// Adopt a real frame text size (font pixel size, or the line height as a
    /// fallback) when it is plausible; anything outside that range keeps the
    /// current size.
    fn adoptTextSize(self: *UnicodeTextRenderer, pixels: i32) void {
        if (pixels < 8 or pixels > 72) return;
        const value: f32 = @floatFromInt(pixels);
        if (value == self.point_size) return;
        self.point_size = value;
        self.closeFonts();
        self.clearTextures();
    }

    fn activePointSize(self: *const UnicodeTextRenderer) f32 {
        return self.fontPointSize();
    }

    /// Real height of the adopted font, or the point size before it is opened.
    fn fontHeight(self: *const UnicodeTextRenderer) i64 {
        if (self.font) |font| {
            const height = TTF_GetFontHeight(font);
            if (height > 0) return height;
        }
        return @intFromFloat(self.fontPointSize());
    }

    /// Adopt the frame's real font file when it changes.  A file that cannot be
    /// opened leaves the bundled candidates in place, so the frontend never
    /// depends on a producer that cannot resolve its font.
    fn adoptFontFile(self: *UnicodeTextRenderer, bytes: []const u8) void {
        if (bytes.len == 0 or bytes.len >= self.font_path.len) return;
        const current = self.font_path[0..self.font_path_len];
        if (std.mem.eql(u8, current, bytes)) return;
        @memcpy(self.font_path[0..bytes.len], bytes);
        self.font_path_len = bytes.len;
        self.closeFonts();
        self.clearTextures();
    }

    fn activeFontFile(self: *const UnicodeTextRenderer) []const u8 {
        return self.font_path[0..self.font_path_len];
    }

    fn adoptVariableFontFile(self: *UnicodeTextRenderer, family: u8, bytes: []const u8) void {
        if (family == 0) return;
        const index: usize = family - 1;
        if (index >= self.alt_font_paths.len) return;
        if (bytes.len == 0 or bytes.len >= self.alt_font_paths[index].len) return;
        const current = self.alt_font_paths[index][0..self.alt_font_path_lens[index]];
        if (std.mem.eql(u8, current, bytes)) return;
        @memcpy(self.alt_font_paths[index][0..bytes.len], bytes);
        self.alt_font_path_lens[index] = bytes.len;
        if (self.alt_fonts[index]) |font| TTF_CloseFont(font);
        self.alt_fonts[index] = null;
        self.clearTextures();
    }

    fn activeVariableFontFile(self: *const UnicodeTextRenderer) []const u8 {
        return self.alt_font_paths[0][0..self.alt_font_path_lens[0]];
    }

    /// Number of alternate font families the producer negotiated (family 1
    /// always counts as one once its file is adopted).
    fn altFontCount(self: *const UnicodeTextRenderer) usize {
        var count: usize = 0;
        for (self.alt_font_path_lens) |len| {
            if (len != 0) count += 1;
        }
        return count;
    }

    fn hasVariableFont(self: *const UnicodeTextRenderer) bool {
        return self.alt_fonts[0] != null;
    }

    fn openFont(self: *UnicodeTextRenderer) ?*TTF_Font {
        if (std.c.getenv("PROTO_UI_FONT")) |configured| {
            return TTF_OpenFont(configured, self.fontPointSize());
        }
        if (self.font_path_len != 0) {
            self.font_path[self.font_path_len] = 0;
            const path: [*:0]const u8 = @ptrCast(&self.font_path);
            if (TTF_OpenFont(path, self.fontPointSize())) |font| return font;
        }
        const candidates = [_][*:0]const u8{
            "/usr/share/fonts/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/TTF/DejaVuSans.ttf",
            "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
            "/System/Library/Fonts/Supplemental/Georgia.ttf",
            "C:\\Windows\\Fonts\\arial.ttf",
            "C:\\Windows\\Fonts\\segoeui.ttf",
        };
        for (candidates) |path| {
            if (TTF_OpenFont(path, self.fontPointSize())) |font| return font;
        }
        return null;
    }

    fn ensure(self: *UnicodeTextRenderer) !void {
        if (self.font != null) return;
        if (self.initialized) return error.UnicodeFontUnavailable;
        if (!TTF_Init()) return sdlFail("TTF_Init");
        self.initialized = true;
        self.font = self.openFont();
        if (self.font == null) return error.UnicodeFontUnavailable;
        self.attachFallback(self.font.?);
    }

    /// Open the first available fallback font and attach it to FONT.
    ///
    /// Emacs falls back to a font that covers the character, so the mirror does
    /// the same with SDL_ttf's fallback list instead of drawing tofu; the
    /// adopted font stays the primary face for text it covers.
    fn attachFallback(self: *UnicodeTextRenderer, font: *TTF_Font) void {
        const candidates = [_][*:0]const u8{
            "/usr/share/fonts/wqy-microhei/wqy-microhei.ttc",
            "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
            "/usr/share/fonts/sarasa-gothic/sarasa-gothic-ttc-nerd-regular.ttc",
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
            "/usr/share/fonts/truetype/unifont/unifont.ttf",
            "/usr/share/fonts/unifont/unifont.ttf",
            "/System/Library/Fonts/PingFang.ttc",
            "C:\\Windows\\Fonts\\msyh.ttc",
            "C:\\Windows\\Fonts\\simsun.ttc",
        };
        if (self.fallback_font == null) {
            for (candidates) |path| {
                if (TTF_OpenFont(path, self.fontPointSize())) |fallback| {
                    self.fallback_font = fallback;
                    break;
                }
            }
        }
        if (self.fallback_font) |fallback| _ = TTF_AddFallbackFont(font, fallback);
    }

    /// True when a script-covering fallback font is installed.
    fn hasFallback(self: *const UnicodeTextRenderer) bool {
        return self.fallback_font != null;
    }

    /// True when the renderer can resolve a CJK codepoint (through the
    /// fallback list when the adopted font does not cover it).
    fn providesCjk(self: *const UnicodeTextRenderer) bool {
        const font = self.font orelse return false;
        return TTF_FontHasGlyph(font, 0x4F60) and TTF_FontHasGlyph(font, 0x597D);
    }

    /// Open the adopted font again with an SDL_ttf style applied.
    ///
    /// `TTF_SetFontStyle` mutates the font object, so each style needs its own
    /// handle.  A style that cannot be opened falls back to the plain font.
    fn openVariableFont(self: *UnicodeTextRenderer, family: u8) ?*TTF_Font {
        if (family == 0) return null;
        const index: usize = family - 1;
        if (index >= self.alt_fonts.len) return null;
        if (self.alt_fonts[index]) |font| return font;
        const length = self.alt_font_path_lens[index];
        if (length == 0) return null;
        self.alt_font_paths[index][length] = 0;
        const path: [*:0]const u8 = @ptrCast(&self.alt_font_paths[index]);
        const font = TTF_OpenFont(path, self.fontPointSize()) orelse return null;
        self.attachFallback(font);
        self.alt_fonts[index] = font;
        return font;
    }

    fn styleFont(self: *UnicodeTextRenderer, style: u8) ?*TTF_Font {
        if (style & 0x80 != 0) return self.openVariableFont(1 + ((style >> 4) & 0x3));
        const index: usize = style & 0x3;
        if (index == 0) return self.font;
        if (self.styled_fonts[index]) |font| return font;
        const font = self.openFont() orelse return null;
        TTF_SetFontStyle(font, @intCast(index));
        self.attachFallback(font);
        self.styled_fonts[index] = font;
        return font;
    }

    fn closeFonts(self: *UnicodeTextRenderer) void {
        if (self.font) |font| TTF_CloseFont(font);
        self.font = null;
        for (&self.styled_fonts) |*font| {
            if (font.*) |open| TTF_CloseFont(open);
            font.* = null;
        }
        for (&self.alt_fonts) |*font| {
            if (font.*) |open| TTF_CloseFont(open);
            font.* = null;
        }
        self.alt_font_path_lens = .{ 0, 0, 0 };
        if (self.fallback_font) |fallback| TTF_CloseFont(fallback);
        self.fallback_font = null;
    }

    fn deinit(self: *UnicodeTextRenderer) void {
        self.cache.clear(destroyUnicodeTexture);
        self.closeFonts();
        if (self.initialized) TTF_Quit();
        self.* = .{};
    }

    fn clearTextures(self: *UnicodeTextRenderer) void {
        self.cache.clear(destroyUnicodeTexture);
    }

    fn render(
        self: *UnicodeTextRenderer,
        renderer: *SDL_Renderer,
        x: f32,
        y: f32,
        bytes: []const u8,
        color: renderer_policy.Color,
        scale_x: f32,
        scale_y: f32,
        style: u8,
    ) !void {
        try self.ensure();
        const styled = self.styleFont(style);
        const font = styled orelse self.font.?;
        const effective_style: u8 = if (styled != null)
            (style & 0xb0) | (style & 0x3)
        else
            0;
        const cache_key = try proto_ui.text_cache.Key.init(
            @intFromPtr(renderer),
            bytes,
            color,
            effective_style,
        );
        if (self.cache.lookup(cache_key)) |cached| {
            return renderUnicodeTexture(
                renderer,
                @ptrFromInt(cached.texture_id),
                cached.width,
                cached.height,
                x,
                y,
                scale_x,
                scale_y,
            );
        }
        const surface = TTF_RenderText_Blended(
            font,
            bytes.ptr,
            bytes.len,
            .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a },
        ) orelse return sdlFail("TTF_RenderText_Blended");
        defer SDL_DestroySurface(surface);
        const texture = SDL_CreateTextureFromSurface(renderer, surface) orelse
            return sdlFail("SDL_CreateTextureFromSurface");
        var owns_texture = true;
        defer if (owns_texture) SDL_DestroyTexture(texture);
        if (!SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND)) return sdlFail("SDL_SetTextureBlendMode");
        var texture_width: f32 = 0;
        var texture_height: f32 = 0;
        if (!SDL_GetTextureSize(texture, &texture_width, &texture_height)) return sdlFail("SDL_GetTextureSize");
        if (texture_width <= 0 or texture_height <= 0) return error.InvalidUnicodeTexture;
        self.cache.insert(
            cache_key,
            @intFromPtr(texture),
            texture_width,
            texture_height,
            destroyUnicodeTexture,
        ) catch {
            return error.UnicodeTextureCacheInsert;
        };
        owns_texture = false;
        return renderUnicodeTexture(
            renderer,
            texture,
            texture_width,
            texture_height,
            x,
            y,
            scale_x,
            scale_y,
        );
    }

    fn renderUnicodeTexture(
        renderer: *SDL_Renderer,
        texture: *SDL_Texture,
        texture_width: f32,
        texture_height: f32,
        x: f32,
        y: f32,
        scale_x: f32,
        scale_y: f32,
    ) !void {
        if (!SDL_RenderTexture(renderer, texture, null, &.{
            .x = x * scale_x,
            .y = y * scale_y,
            .w = texture_width * scale_x,
            .h = texture_height * scale_y,
        })) return sdlFail("SDL_RenderTexture");
    }
};

var unicode_text_renderer: UnicodeTextRenderer = .{};

fn destroyUnicodeTexture(texture_id: usize) void {
    SDL_DestroyTexture(@ptrFromInt(texture_id));
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

fn benchmarkInside(offset: i32, extent: i32, limit: i32) bool {
    return offset >= 0 and extent >= 0 and
        @as(i64, offset) <= @as(i64, limit) and
        @as(i64, extent) <= @as(i64, limit) - @as(i64, offset);
}

fn alternateTypingProxy(scene: *frontend.Scene) !void {
    if (scene.cursor_count == 0) return error.NoBenchmarkCursor;
    var cursor_index: usize = 0;
    for (scene.cursors[0..scene.cursor_count], 0..) |candidate, index| {
        if (candidate.visible and candidate.active) {
            cursor_index = index;
            break;
        }
    }
    const cursor = &scene.cursors[cursor_index];
    const owner = findWindowById(scene.windows.items, cursor.window_id) orelse
        return error.NoBenchmarkCursorWindow;
    if (!owner.visible or !cursor.visible or !cursor.active or
        owner.width <= 0 or owner.height <= 0 or
        cursor.width <= 0 or cursor.height <= 0 or
        !benchmarkInside(cursor.x, cursor.width, owner.width) or
        !benchmarkInside(cursor.y, cursor.height, owner.height))
        return error.InvalidBenchmarkCursor;

    const base_x: i64 = 8;
    const maximum_x: i64 = @as(i64, owner.width) - @as(i64, cursor.width);
    const alternate_x: i64 = @min(maximum_x, base_x + 16);
    if (alternate_x <= base_x) return error.InvalidBenchmarkCursorGeometry;
    cursor.x = if (cursor.x == base_x)
        @intCast(alternate_x)
    else
        @intCast(base_x);
    scene.cursor = cursor.*;
}

fn alternateScrollProxy(scene: *frontend.Scene, row_index: usize, original_y: i32) !void {
    if (row_index >= scene.rows.items.len) return error.NoBenchmarkRow;
    const row = &scene.rows.items[row_index];
    const owner = findWindowById(scene.windows.items, row.window_id) orelse
        return error.NoBenchmarkRowWindow;
    if (!owner.visible or owner.width <= 0 or owner.height <= 0 or
        row.visible_height <= 0 or
        !benchmarkInside(row.x, row.width, owner.width) or
        !benchmarkInside(row.y, row.height, owner.height))
        return error.InvalidBenchmarkRowGeometry;

    const next_y: i64 = if (row.y == original_y)
        @as(i64, row.y) + 1
    else
        original_y;
    const bottom: i64 = next_y + @as(i64, row.visible_height);
    if (next_y < 0 or bottom > @as(i64, owner.height)) return error.InvalidBenchmarkRowGeometry;
    row.y = @intCast(next_y);
}

const RendererWorkload = struct {
    name: []const u8,
    iterations: usize,
    warmup: usize,
    summary: renderer_policy.LatencySummary,
    draw_commands_total: u64,
    presented_frames: u64,
    skipped_frames: u64,
};

fn appendRendererWorkload(
    gpa: std.mem.Allocator,
    report: *std.ArrayList(u8),
    workload: RendererWorkload,
    first: bool,
) !void {
    if (first) try report.appendSlice(gpa, ",\"workloads\":[");
    if (!first) try report.appendSlice(gpa, ",");
    const commands_per_frame: f64 =
        @as(f64, @floatFromInt(workload.draw_commands_total)) /
        @as(f64, @floatFromInt(workload.iterations));
    try report.appendSlice(gpa, "{\"name\":");
    try runtime.appendJsonStringPublic(gpa, report, workload.name);
    try report.appendSlice(
        gpa,
        ",\"workload_kind\":\"renderer_proxy\",\"iterations_policy\":\"bounded\",",
    );
    try report.print(
        gpa,
        "\"iterations\":{d},\"warmup\":{d},\"warmup_policy\":\"none\",\"p50_ns\":{d},\"p95_ns\":{d},\"p99_ns\":{d},\"mean_ns\":{d:.2},\"fps\":{d:.2},\"draw_commands_total\":{d},\"commands_per_frame\":{d:.2},\"presented_frames\":{d},\"skipped_frames\":{d}}}",
        .{
            workload.iterations,
            workload.warmup,
            workload.summary.p50_ns,
            workload.summary.p95_ns,
            workload.summary.p99_ns,
            workload.summary.mean_ns,
            workload.summary.fps,
            workload.draw_commands_total,
            commands_per_frame,
            workload.presented_frames,
            workload.skipped_frames,
        },
    );
}

fn restoreRendererBenchState(
    scene: *frontend.Scene,
    window: *SDL_Window,
    typing_cursor: frontend.Cursor,
    typing_cursor_index: usize,
    scroll_row_index: usize,
    scroll_row_y: i32,
    original_width: c_int,
    original_height: c_int,
) !void {
    scene.cursors[typing_cursor_index] = typing_cursor;
    scene.cursor = typing_cursor;
    scene.rows.items[scroll_row_index].y = scroll_row_y;
    if (!SDL_SetWindowSize(window, original_width, original_height)) return sdlFail("SDL_SetWindowSize");
    if (!SDL_SyncWindow(window)) return sdlFail("SDL_SyncWindow");
    var restored_width: c_int = 0;
    var restored_height: c_int = 0;
    SDL_GetWindowSize(window, &restored_width, &restored_height);
    if (restored_width != original_width or restored_height != original_height)
        return error.BenchmarkResizeRestoreFailed;
}

fn runRendererBench(
    gpa: std.mem.Allocator,
    io: std.Io,
    config: *const Config,
) !void {
    const wire_messages = try transport.readReplay(gpa, io, config.replay_path);
    defer transport.freeReplay(gpa, wire_messages);
    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    var update_bytes: usize = 0;
    for (wire_messages) |message| {
        const envelope = (try protocol.decodeEnvelope(message)).envelope;
        if (envelope.message_type == protocol.Message.frame_update) update_bytes += message.len;
        try scene.apply(message);
    }
    if (scene.stats.frame_updates == 0 or scene.frame_header == null) return error.NoFrameUpdate;

    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();
    const window = SDL_CreateWindow(
        "Emacs Proto-UI Renderer Benchmark",
        960,
        600,
        SDL_WINDOW_HIDDEN,
    ) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);
    const selected_renderer = try createRenderer(gpa, window, config.renderer_request, config.present_mode);
    defer destroyRenderer(selected_renderer);
    var original_width: c_int = 0;
    var original_height: c_int = 0;
    SDL_GetWindowSize(window, &original_width, &original_height);
    if (original_width <= 0 or original_height <= 0) return error.InvalidOutputGeometry;

    var frame_gate: renderer_policy.FrameGate = .{};
    var counters: renderer_policy.FrameCounters = .{};
    var draw_list: renderer_policy.DrawList = .{ .allocator = gpa };
    defer draw_list.deinit();

    const warmup: usize = config.benchmark_warmup;
    for (0..warmup) |_| {
        frame_gate.dirty = true;
        _ = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &counters, null);
    }

    const iterations: usize = config.benchmark_iterations;
    const full_samples = try gpa.alloc(u64, iterations);
    defer gpa.free(full_samples);
    const skip_samples = try gpa.alloc(u64, iterations);
    defer gpa.free(skip_samples);
    const workload_samples = try gpa.alloc(u64, iterations);
    defer gpa.free(workload_samples);
    counters = .{};
    var full_draws: u64 = 0;

    for (0..iterations) |index| {
        frame_gate.dirty = true;
        const started = SDL_GetPerformanceCounter();
        const execution = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &counters, null);
        const ended = SDL_GetPerformanceCounter();
        const elapsed = performanceTicksToNanos(ended - started);
        full_samples[index] = if (elapsed == 0) 1 else elapsed;
        full_draws += execution.commands;
    }
    for (0..iterations) |index| {
        frame_gate.dirty = false;
        const started = SDL_GetPerformanceCounter();
        _ = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &counters, null);
        const ended = SDL_GetPerformanceCounter();
        const elapsed = performanceTicksToNanos(ended - started);
        skip_samples[index] = if (elapsed == 0) 1 else elapsed;
    }
    const baseline_counters = counters;

    const full = try renderer_policy.summarizeLatencies(full_samples);
    const skipped = try renderer_policy.summarizeLatencies(skip_samples);

    // These are renderer-call proxies: the deterministic replay scene is
    // mutated locally and never originates Emacs, redisplay, or transport work.
    const typing_cursor = scene.cursor orelse return error.NoBenchmarkCursor;
    const typing_cursor_index: usize = blk: {
        for (scene.cursors[0..scene.cursor_count], 0..) |candidate, index| {
            if (std.meta.eql(candidate, typing_cursor)) break :blk index;
        }
        return error.NoBenchmarkCursor;
    };
    if (scene.rows.items.len == 0) return error.NoBenchmarkRow;
    const scroll_row_index: usize = 0;
    const scroll_row_y = scene.rows.items[scroll_row_index].y;
    errdefer restoreRendererBenchState(
        &scene,
        window,
        typing_cursor,
        typing_cursor_index,
        scroll_row_index,
        scroll_row_y,
        original_width,
        original_height,
    ) catch |restore_error| std.debug.print(
        "sdl3-eup-smoke: renderer benchmark restore failed: {s}\n",
        .{@errorName(restore_error)},
    );

    counters = .{};
    var workload_draws: u64 = 0;
    for (0..iterations) |index| {
        try alternateTypingProxy(&scene);
        frame_gate.dirty = true;
        const started = SDL_GetPerformanceCounter();
        const execution = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &counters, null);
        const ended = SDL_GetPerformanceCounter();
        const elapsed = performanceTicksToNanos(ended - started);
        workload_samples[index] = if (elapsed == 0) 1 else elapsed;
        if (execution.commands == 0) return error.RendererWorkloadSkipped;
        workload_draws += execution.commands;
    }
    if (counters.presented_frames != iterations or counters.skipped_frames != 0)
        return error.RendererWorkloadIncomplete;
    const typing = try renderer_policy.summarizeLatencies(workload_samples);
    const typing_result: RendererWorkload = .{
        .name = "typing_proxy",
        .iterations = iterations,
        .warmup = 0,
        .summary = typing,
        .draw_commands_total = workload_draws,
        .presented_frames = counters.presented_frames,
        .skipped_frames = counters.skipped_frames,
    };

    counters = .{};
    workload_draws = 0;
    for (0..iterations) |index| {
        try alternateScrollProxy(&scene, scroll_row_index, scroll_row_y);
        frame_gate.dirty = true;
        const started = SDL_GetPerformanceCounter();
        const execution = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &counters, null);
        const ended = SDL_GetPerformanceCounter();
        const elapsed = performanceTicksToNanos(ended - started);
        workload_samples[index] = if (elapsed == 0) 1 else elapsed;
        if (execution.commands == 0) return error.RendererWorkloadSkipped;
        workload_draws += execution.commands;
    }
    if (counters.presented_frames != iterations or counters.skipped_frames != 0)
        return error.RendererWorkloadIncomplete;
    const scrolling = try renderer_policy.summarizeLatencies(workload_samples);
    const scroll_result: RendererWorkload = .{
        .name = "scroll_proxy",
        .iterations = iterations,
        .warmup = 0,
        .summary = scrolling,
        .draw_commands_total = workload_draws,
        .presented_frames = counters.presented_frames,
        .skipped_frames = counters.skipped_frames,
    };

    counters = .{};
    workload_draws = 0;
    const resize_sizes = [_]@Vector(2, c_int){
        .{ 720, 480 },
        .{ 1200, 800 },
    };
    for (0..iterations) |index| {
        // Keep synchronous geometry setup and validation outside the measured
        // region so every resize proxy sample remains a renderer-call sample.
        const size = resize_sizes[index % resize_sizes.len];
        if (!SDL_SetWindowSize(window, size[0], size[1])) return sdlFail("SDL_SetWindowSize");
        if (!SDL_SyncWindow(window)) return sdlFail("SDL_SyncWindow");
        var actual_width: c_int = 0;
        var actual_height: c_int = 0;
        SDL_GetWindowSize(window, &actual_width, &actual_height);
        if (actual_width != size[0] or actual_height != size[1])
            return error.InvalidBenchmarkResize;
        frame_gate.width = 0;
        frame_gate.height = 0;
        frame_gate.dirty = true;
        const started = SDL_GetPerformanceCounter();
        const execution = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &counters, null);
        const ended = SDL_GetPerformanceCounter();
        const elapsed = performanceTicksToNanos(ended - started);
        workload_samples[index] = if (elapsed == 0) 1 else elapsed;
        if (execution.commands == 0) return error.RendererWorkloadSkipped;
        workload_draws += execution.commands;
    }
    if (counters.presented_frames != iterations or counters.skipped_frames != 0)
        return error.RendererWorkloadIncomplete;
    const resizing = try renderer_policy.summarizeLatencies(workload_samples);
    const resize_result: RendererWorkload = .{
        .name = "resize_proxy",
        .iterations = iterations,
        .warmup = 0,
        .summary = resizing,
        .draw_commands_total = workload_draws,
        .presented_frames = counters.presented_frames,
        .skipped_frames = counters.skipped_frames,
    };

    // Restore the hidden benchmark output and deterministic replay scene so the
    // measured resize phase does not leak its last synthetic state forward.
    try restoreRendererBenchState(
        &scene,
        window,
        typing_cursor,
        typing_cursor_index,
        scroll_row_index,
        scroll_row_y,
        original_width,
        original_height,
    );
    frame_gate.dirty = true;
    _ = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &counters, null);

    var report: std.ArrayList(u8) = .empty;
    defer report.deinit(gpa);
    try report.appendSlice(gpa, "{\"schema_version\":2,\"kind\":\"proto-ui-sdl3-renderer-benchmark\",\"protocol\":{\"name\":\"EUP\",\"version\":\"1.0\"},\"workload_kind\":\"renderer_proxy\",\"renderer_tier\":");
    try runtime.appendJsonStringPublic(gpa, &report, @tagName(selected_renderer.tier));
    try report.appendSlice(gpa, ",\"renderer_name\":");
    try runtime.appendJsonStringPublic(gpa, &report, selected_renderer.name);
    try report.appendSlice(gpa, ",\"present_mode\":");
    try runtime.appendJsonStringPublic(gpa, &report, config.present_mode);
    try report.appendSlice(gpa, ",\"optimization_mode\":");
    try runtime.appendJsonStringPublic(gpa, &report, @tagName(@import("builtin").mode));
    try report.print(gpa, ",\"iterations\":{d},\"warmup\":{d},\"frame_update_bytes\":{d},\"full_draw\":{{\"p50_ns\":{d},\"p95_ns\":{d},\"p99_ns\":{d},\"mean_ns\":{d:.2},\"fps\":{d:.2},\"draw_commands_total\":{d},\"commands_per_frame\":{d:.2}}},\"unchanged_skip\":{{\"p50_ns\":{d},\"p95_ns\":{d},\"p99_ns\":{d},\"mean_ns\":{d:.2},\"fps\":{d:.2}}},\"presented_frames\":{d},\"skipped_frames\":{d}", .{
        iterations,
        warmup,
        update_bytes,
        full.p50_ns,
        full.p95_ns,
        full.p99_ns,
        full.mean_ns,
        full.fps,
        full_draws,
        @as(f64, @floatFromInt(full_draws)) / @as(f64, @floatFromInt(iterations)),
        skipped.p50_ns,
        skipped.p95_ns,
        skipped.p99_ns,
        skipped.mean_ns,
        skipped.fps,
        baseline_counters.presented_frames,
        baseline_counters.skipped_frames,
    });
    try appendRendererWorkload(gpa, &report, typing_result, true);
    try appendRendererWorkload(gpa, &report, scroll_result, false);
    try appendRendererWorkload(gpa, &report, resize_result, false);
    try report.appendSlice(gpa, "],\"result\":\"pass\"}\n");
    if (config.benchmark_output.len > 0) {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = config.benchmark_output, .data = report.items });
    }
    std.debug.print("{s}", .{report.items});
}

fn executeDrawList(
    cache: *FrameTextureCache,
    atlas_cache: ?*AtlasTextureCache,
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
                const texture = try cache.getOrCreate(renderer, draw.pixels, draw.width, draw.height);
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
            .image_region => |draw| {
                const texture = if (atlas_cache) |persistent|
                    try persistent.getOrCreate(renderer, .{
                        .atlas_id = draw.atlas_id,
                        .page_index = draw.page_index,
                        .generation = draw.generation,
                        .revision = draw.cache_revision,
                    }, draw.pixels, draw.source_width, draw.source_height)
                else
                    try cache.getOrCreate(renderer, draw.pixels, draw.source_width, draw.source_height);
                const source = SDL_FRect{
                    .x = draw.source.x,
                    .y = draw.source.y,
                    .w = draw.source.width,
                    .h = draw.source.height,
                };
                const destination = SDL_FRect{
                    .x = draw.destination.x * @as(f32, @floatFromInt(output_width)) / list.logical_width,
                    .y = draw.destination.y * @as(f32, @floatFromInt(output_height)) / list.logical_height,
                    .w = draw.destination.width * @as(f32, @floatFromInt(output_width)) / list.logical_width,
                    .h = draw.destination.height * @as(f32, @floatFromInt(output_height)) / list.logical_height,
                };
                if (!SDL_RenderTexture(renderer, texture, &source, &destination)) return sdlFail("SDL_RenderTexture");
                executed.commands += 1;
                executed.images += 1;
                executed.atlas_glyphs += 1;
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
            .unicode_text => |draw| {
                try unicode_text_renderer.render(
                    renderer,
                    draw.x,
                    draw.y,
                    draw.bytes,
                    draw.color,
                    @as(f32, @floatFromInt(output_width)) / list.logical_width,
                    @as(f32, @floatFromInt(output_height)) / list.logical_height,
                    draw.style,
                );
                executed.commands += 1;
                executed.unicode_texts += 1;
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
    atlas_cache: ?*AtlasTextureCache,
) !renderer_policy.DrawStats {
    var texture_cache = FrameTextureCache.init(std.heap.smp_allocator);
    defer texture_cache.deinit();
    var width: c_int = 0;
    var height: c_int = 0;
    SDL_GetWindowSize(window, &width, &height);
    if (!gate.shouldPresent(@intCast(width), @intCast(height))) {
        counters.recordSkipped();
        return .{};
    }
    const started_ticks = SDL_GetPerformanceCounter();
    try buildSceneDrawList(scene, list, @intCast(width), @intCast(height));
    const execution = try executeDrawList(&texture_cache, atlas_cache, list, renderer, window, null, null, false);
    if (!SDL_RenderPresent(renderer)) return sdlFail("SDL_RenderPresent");
    counters.recordDrawList(execution);
    const ended_ticks = SDL_GetPerformanceCounter();
    counters.recordPresent(
        performanceTicksToNanos(ended_ticks - started_ticks),
        performanceTicksToNanos(ended_ticks),
    );
    return execution;
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
    atlas_cache: ?*AtlasTextureCache,
) !void {
    var texture_cache = FrameTextureCache.init(std.heap.smp_allocator);
    defer texture_cache.deinit();
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
            execution = try executeDrawList(&texture_cache, atlas_cache, list, renderer, window, target, rect, explicit_clip != null);
            submitted = execution.commands;
            clipped = submitted != 0;
        }
        if (!clipped) {
            execution = try executeDrawList(&texture_cache, atlas_cache, list, renderer, window, target, null, false);
            submitted = execution.commands;
        }
        retained.primed = true;
        try presentRetainedOutput(renderer, target);
    } else {
        execution = try executeDrawList(&texture_cache, atlas_cache, list, renderer, window, null, null, false);
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
    atlas_cache: ?*AtlasTextureCache,
) !void {
    var texture_cache = FrameTextureCache.init(std.heap.smp_allocator);
    defer texture_cache.deinit();
    var width: c_int = 0;
    var height: c_int = 0;
    SDL_GetWindowSize(window, &width, &height);
    if (!gate.shouldPresent(@intCast(width), @intCast(height))) {
        counters.recordSkipped();
        return;
    }
    const started_ticks = SDL_GetPerformanceCounter();
    try buildFactsDrawList(snapshot, list, @intCast(width), @intCast(height));
    const execution = try executeDrawList(&texture_cache, atlas_cache, list, renderer, window, null, null, false);
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
    const gap_fault_arg = try std.fmt.allocPrint(gpa, "--gap-fault={}", .{config.gap_fault});
    defer gpa.free(gap_fault_arg);
    const visible_edit_arg = try std.fmt.allocPrint(
        gpa,
        "--visible-edit-publisher={}",
        .{config.visible_edit_publisher},
    );
    defer gpa.free(visible_edit_arg);
    const dnd_text_arg = try std.fmt.allocPrint(
        gpa,
        "--dnd-text-publisher={}",
        .{config.dnd_text_publisher},
    );
    defer gpa.free(dnd_text_arg);
    const face_smoke_arg = try std.fmt.allocPrint(
        gpa,
        "--face-smoke-publisher={}",
        .{config.face_smoke_publisher},
    );
    defer gpa.free(face_smoke_arg);
    const cursor_smoke_arg = try std.fmt.allocPrint(
        gpa,
        "--cursor-smoke-publisher={}",
        .{config.cursor_smoke_publisher},
    );
    defer gpa.free(cursor_smoke_arg);
    const scrollbar_smoke_arg = try std.fmt.allocPrint(
        gpa,
        "--scrollbar-smoke-publisher={}",
        .{config.scrollbar_smoke_publisher},
    );
    defer gpa.free(scrollbar_smoke_arg);
    const hscroll_smoke_arg = try std.fmt.allocPrint(
        gpa,
        "--hscroll-smoke-publisher={}",
        .{config.hscroll_smoke_publisher},
    );
    defer gpa.free(hscroll_smoke_arg);
    const graphic_frame_arg = try std.fmt.allocPrint(
        gpa,
        "--graphic-frame-publisher={}",
        .{config.graphic_frame_publisher},
    );
    defer gpa.free(graphic_frame_arg);
    const region_smoke_arg = try std.fmt.allocPrint(
        gpa,
        "--region-smoke-publisher={}",
        .{config.region_smoke_publisher},
    );
    defer gpa.free(region_smoke_arg);
    const header_smoke_arg = try std.fmt.allocPrint(
        gpa,
        "--header-smoke-publisher={}",
        .{config.header_smoke_publisher},
    );
    defer gpa.free(header_smoke_arg);
    const mouse_smoke_arg = try std.fmt.allocPrint(
        gpa,
        "--mouse-smoke-publisher={}",
        .{config.mouse_smoke_publisher},
    );
    defer gpa.free(mouse_smoke_arg);
    const echo_smoke_arg = try std.fmt.allocPrint(
        gpa,
        "--echo-smoke-publisher={}",
        .{config.echo_smoke_publisher},
    );
    defer gpa.free(echo_smoke_arg);
    const runs_smoke_arg = try std.fmt.allocPrint(
        gpa,
        "--runs-smoke-publisher={}",
        .{config.runs_smoke_publisher},
    );
    defer gpa.free(runs_smoke_arg);
    const menu_icon_arg = try std.fmt.allocPrint(
        gpa,
        "--menu-icon-publisher={}",
        .{config.mode == .emacs_epxl_menu_open},
    );
    defer gpa.free(menu_icon_arg);
    const auto_quit_arg = try std.fmt.allocPrint(
        gpa,
        "--auto-quit-ms={d}",
        .{if (config.interactive_publisher)
            if (config.auto_quit_ms == 0) 0 else config.auto_quit_ms + 1000
        else if (config.mode == .emacs_epxl_bench)
            // The bounded edit benchmark needs a live publisher for its whole
            // run; the default 500ms publisher window would end it mid-stream.
            config.auto_quit_ms
        else
            500},
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
            gap_fault_arg,
            visible_edit_arg,
            dnd_text_arg,
            face_smoke_arg,
            cursor_smoke_arg,
            scrollbar_smoke_arg,
            hscroll_smoke_arg,
            graphic_frame_arg,
            region_smoke_arg,
            header_smoke_arg,
            mouse_smoke_arg,
            echo_smoke_arg,
            runs_smoke_arg,
            menu_icon_arg,
            auto_quit_arg,
            if (config.title_smoke) "--title-smoke" else "--no-title-smoke",
            if (config.clipboard_unicode_publisher) "--clipboard-unicode-publisher" else "--clipboard-ascii-publisher",
            if (config.pointer_selection_publisher)
                "--pointer-selection-publisher"
            else if (config.pointer_generic_publisher)
                "--pointer-generic-publisher"
            else
                "--interactive-publisher",
            if (config.primary_selection_publisher)
                "--primary-selection-publisher"
            else
                "--interactive-publisher",
            if (config.pointer_middle_paste_publisher) "--pointer-middle-paste-publisher" else "--interactive-publisher",
            if (config.selection_owner_smoke) "--selection-owner-smoke" else "--interactive-publisher",
            if (config.selection_transfer_smoke) "--selection-transfer-smoke" else "--interactive-publisher",
            if (config.synthetic_window_minimize_restore) "--window-minimize-restore-smoke" else "--interactive-publisher",
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
            gap_fault_arg,
            visible_edit_arg,
            dnd_text_arg,
            face_smoke_arg,
            cursor_smoke_arg,
            scrollbar_smoke_arg,
            hscroll_smoke_arg,
            graphic_frame_arg,
            region_smoke_arg,
            header_smoke_arg,
            mouse_smoke_arg,
            echo_smoke_arg,
            runs_smoke_arg,
            auto_quit_arg,
        };
    var publisher_environment = try buildDisplayEnvironment(gpa);
    defer publisher_environment.deinit();
    var child = try std.process.spawn(io, .{
        .argv = child_argv,
        // The publisher starts its own Emacs child, and a display-backed frame
        // needs the display and locale environment to be forwarded rather than
        // left to an empty child environment.
        .environ_map = &publisher_environment,
    });
    var child_running = true;
    var loaded: ?frontend.Scene = null;
    errdefer if (loaded != null) loaded.?.deinit();
    if (config.mode == .emacs_epxl_interactive or config.mode == .emacs_clipboard_unicode or
        config.mode == .emacs_epxl_ime_commit or config.mode == .emacs_epxl_dnd or
        config.mode == .emacs_epxl_face or config.mode == .emacs_epxl_cursor or
        config.mode == .emacs_epxl_scrollbar or
        config.mode == .emacs_epxl_scroll_interaction or
        config.mode == .emacs_epxl_hscroll or
        config.mode == .emacs_epxl_menu_bar or
        config.mode == .emacs_epxl_menu_open or
        config.mode == .emacs_epxl_menu_apply or
        config.mode == .emacs_epxl_graphic or
        config.mode == .emacs_epxl_mouse or
        config.mode == .emacs_primary_selection or
        config.mode == .emacs_pointer_selection or
        config.mode == .emacs_pointer_middle_paste)
    {
        loaded = runEpxlInteractiveFrontend(gpa, io, config, &delivery) catch |err| {
            // Close-on-return lets the publisher terminate its own Emacs
            // child.  Reap it and let the function errdefer clean artifacts.
            child_running = false;
            _ = try child.wait(io);
            return err;
        };
    } else {
        for (0..sessions) |session_index| {
            var session = runLiveFrontend(gpa, io, config, &delivery) catch |err| {
                // Ensure publisher/Emacs shutdown precedes artifact cleanup.
                child_running = false;
                _ = try child.wait(io);
                return err;
            };
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
    child_running = false;
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
    defer unicode_text_renderer.deinit();
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
            config.manual_emacs_session = true;
        } else if (std.mem.eql(u8, arg, "--title-smoke")) {
            config.title_smoke = true;
        } else if (std.mem.eql(u8, arg, "--no-title-smoke")) {
            config.title_smoke = false;
        } else if (std.mem.eql(u8, arg, "--emacs-interactive-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.interactive_synthetic = true;
            config.title_smoke = true;
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
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-gap-recovery-smoke")) {
            config.mode = .emacs_epxl_gap;
            config.auto_input = "X";
            config.interactive_publisher = true;
            config.gap_fault = true;
        } else if (std.mem.eql(u8, arg, "--gap-fault=true")) {
            config.gap_fault = true;
        } else if (std.mem.eql(u8, arg, "--gap-fault=false")) {
            config.gap_fault = false;
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
            config.synthetic_pointer_v2 = true;
            config.pointer_generic_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-frame-smoke")) {
            config.mode = .frame_lifecycle;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-interactive-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.interactive_synthetic = true;
        } else if (std.mem.eql(u8, arg, "--emacs-focus-roundtrip-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.synthetic_focus_events = true;
        } else if (std.mem.eql(u8, arg, "--emacs-window-resize-roundtrip-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.synthetic_window_resize = true;
        } else if (std.mem.eql(u8, arg, "--emacs-window-move-roundtrip-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.synthetic_window_move = true;
        } else if (std.mem.eql(u8, arg, "--emacs-window-maximize-roundtrip-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.synthetic_window_maximize = true;
        } else if (std.mem.eql(u8, arg, "--emacs-window-fullscreen-roundtrip-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.synthetic_window_fullscreen = true;
        } else if (std.mem.eql(u8, arg, "--emacs-window-minimize-restore-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.synthetic_window_minimize_restore = true;
        } else if (std.mem.eql(u8, arg, "--emacs-selection-owner-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.selection_owner_smoke = true;
        } else if (std.mem.eql(u8, arg, "--interactive-publisher")) {
            config.interactive_publisher = true;
        } else if (std.mem.eql(u8, arg, "--selection-owner-smoke")) {
            config.selection_owner_smoke = true;
        } else if (std.mem.eql(u8, arg, "--selection-transfer-smoke")) {
            config.selection_transfer_smoke = true;
        } else if (std.mem.eql(u8, arg, "--window-minimize-restore-smoke")) {
            config.synthetic_window_minimize_restore = true;
        } else if (std.mem.eql(u8, arg, "--emacs-selection-transfer-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.selection_transfer_smoke = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-input-smoke")) {
            config.mode = .emacs_epxl_input;
            config.auto_input = "X";
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-unicode-input-smoke")) {
            config.mode = .emacs_epxl_unicode_input;
            config.auto_input = "你好";
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-ime-commit-smoke")) {
            config.mode = .emacs_epxl_ime_commit;
            config.interactive_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-dnd-smoke")) {
            config.mode = .emacs_epxl_dnd;
            config.interactive_publisher = true;
            config.synthetic_dnd = true;
            config.dnd_text_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-face-smoke")) {
            config.mode = .emacs_epxl_face;
            config.interactive_publisher = true;
            config.face_smoke_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-cursor-smoke")) {
            config.mode = .emacs_epxl_cursor;
            config.interactive_publisher = true;
            config.cursor_smoke_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-scrollbar-smoke")) {
            config.mode = .emacs_epxl_scrollbar;
            config.interactive_publisher = true;
            config.scrollbar_smoke_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-scrollbar-interaction-smoke")) {
            config.mode = .emacs_epxl_scroll_interaction;
            config.interactive_publisher = true;
            config.scrollbar_smoke_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-hscroll-smoke")) {
            config.mode = .emacs_epxl_hscroll;
            config.interactive_publisher = true;
            config.hscroll_smoke_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-menu-bar-smoke")) {
            config.mode = .emacs_epxl_menu_bar;
            config.interactive_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-menu-open-smoke")) {
            config.mode = .emacs_epxl_menu_open;
            config.interactive_publisher = true;
            config.menu_icon_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-graphic-smoke")) {
            config.mode = .emacs_epxl_graphic;
            config.interactive_publisher = true;
            config.graphic_frame_publisher = true;
            config.region_smoke_publisher = true;
            config.runs_smoke_publisher = true;
            config.header_smoke_publisher = true;
            config.echo_smoke_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-mouse-smoke")) {
            config.mode = .emacs_epxl_mouse;
            config.interactive_publisher = true;
            config.mouse_smoke_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-menu-apply-smoke")) {
            config.mode = .emacs_epxl_menu_apply;
            config.interactive_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-key-v2-smoke")) {
            config.mode = .emacs_epxl_key_v2;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-key-modifier-smoke")) {
            config.mode = .emacs_epxl_key_modifier;
        } else if (std.mem.eql(u8, arg, "--emacs-monitor-change-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.interactive_synthetic = true;
            config.synthetic_monitor_change = true;
        } else if (std.mem.eql(u8, arg, "--emacs-theme-event-smoke")) {
            config.mode = .emacs_epxl_interactive;
            config.interactive_publisher = true;
            config.interactive_synthetic = true;
            config.synthetic_theme_event = true;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-edit-smoke")) {
            config.mode = .emacs_epxl_edit;
            config.auto_key = .backspace;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-bench")) {
            config.mode = .emacs_epxl_bench;
            config.visible_edit_publisher = true;
            config.benchmark_iterations = 32;
            config.benchmark_warmup = 2;
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-sequence-smoke")) {
            config.mode = .emacs_epxl_sequence;
            config.auto_input = "X";
            config.auto_key = .backspace;
        } else if (std.mem.eql(u8, arg, "--emacs-window-split-smoke")) {
            config.mode = .emacs_window_split;
        } else if (std.mem.eql(u8, arg, "--emacs-window-navigation-smoke")) {
            config.mode = .emacs_window_navigation;
        } else if (std.mem.eql(u8, arg, "--emacs-window-restore-smoke")) {
            config.mode = .emacs_window_restore;
        } else if (std.mem.eql(u8, arg, "--emacs-window-pointer-select-smoke")) {
            config.mode = .emacs_window_pointer_select;
            config.interactive_publisher = true;
            config.pointer_generic_publisher = true;
        } else if (std.mem.eql(u8, arg, "--clipboard-smoke")) {
            config.mode = .clipboard;
        } else if (std.mem.eql(u8, arg, "--primary-selection-smoke")) {
            config.mode = .primary_selection;
        } else if (std.mem.eql(u8, arg, "--primary-selection-publisher")) {
            config.primary_selection_publisher = true;
        } else if (std.mem.eql(u8, arg, "--clipboard-unicode-smoke")) {
            config.mode = .emacs_clipboard_unicode;
            config.interactive_publisher = true;
            config.synthetic_clipboard_unicode = true;
            config.clipboard_unicode_publisher = true;
        } else if (std.mem.eql(u8, arg, "--emacs-primary-selection-smoke")) {
            config.mode = .emacs_primary_selection;
            config.interactive_publisher = true;
            config.synthetic_clipboard_unicode = true;
            config.synthetic_primary_selection = true;
            config.primary_selection_publisher = true;
            config.clipboard_unicode_publisher = true;
        } else if (std.mem.eql(u8, arg, "--pointer-selection-publisher")) {
            config.pointer_selection_publisher = true;
        } else if (std.mem.eql(u8, arg, "--pointer-generic-publisher")) {
            config.pointer_generic_publisher = true;
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
        } else if (std.mem.eql(u8, arg, "--emacs-epxl-failure-cleanup-smoke")) {
            config.mode = .emacs_epxl_failure_cleanup;
            config.interactive_publisher = true;
            config.interactive_synthetic = false;
            config.force_frontend_failure = true;
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
        } else if (std.mem.eql(u8, arg, "--touch-tap-smoke")) {
            config.mode = .touch_tap_smoke;
        } else if (std.mem.eql(u8, arg, "--pen-tap-smoke")) {
            config.mode = .pen_tap_smoke;
        } else if (std.mem.eql(u8, arg, "--face-text-smoke")) {
            config.mode = .face_text_smoke;
        } else if (std.mem.eql(u8, arg, "--cursor-style-smoke")) {
            config.mode = .cursor_style_smoke;
        } else if (std.mem.eql(u8, arg, "--menu-hit-smoke")) {
            config.mode = .menu_hit_smoke;
        } else if (std.mem.eql(u8, arg, "--toolbar-hit-smoke")) {
            config.mode = .toolbar_hit_smoke;
        } else if (std.mem.eql(u8, arg, "--dialog-hit-smoke")) {
            config.mode = .dialog_hit_smoke;
        } else if (std.mem.eql(u8, arg, "--scrollbar-smoke")) {
            config.mode = .scrollbar_smoke;
        } else if (std.mem.eql(u8, arg, "--glyph-run-smoke")) {
            config.mode = .glyph_run_smoke;
            config.auto_quit_ms = 180;
        } else if (std.mem.eql(u8, arg, "--runtime-bridge-smoke")) {
            config.mode = .runtime_bridge_smoke;
            config.auto_quit_ms = 180;
        } else if (std.mem.eql(u8, arg, "--provider-frame")) {
            config.mode = .provider_frame;
        } else if (std.mem.eql(u8, arg, "--focus-window-smoke")) {
            config.mode = .focus_window_translation;
        } else if (std.mem.eql(u8, arg, "--facts")) {
            try setString(gpa, &config.facts_path, args.next() orelse return error.MissingFactsPath);
        } else if (std.mem.eql(u8, arg, "--renderer-bench")) {
            config.mode = .renderer_bench;
        } else if (std.mem.startsWith(u8, arg, "--benchmark-output=")) {
            try setString(gpa, &config.benchmark_output, arg["--benchmark-output=".len..]);
        } else if (std.mem.eql(u8, arg, "--benchmark-output")) {
            try setString(gpa, &config.benchmark_output, args.next() orelse return error.MissingBenchmarkOutput);
        } else if (std.mem.startsWith(u8, arg, "--benchmark-iterations=")) {
            config.benchmark_iterations = std.fmt.parseInt(u32, arg["--benchmark-iterations=".len..], 10) catch return error.InvalidBenchmarkIterations;
        } else if (std.mem.eql(u8, arg, "--benchmark-iterations")) {
            config.benchmark_iterations = std.fmt.parseInt(u32, args.next() orelse return error.MissingBenchmarkIterations, 10) catch return error.InvalidBenchmarkIterations;
        } else if (std.mem.startsWith(u8, arg, "--benchmark-warmup=")) {
            config.benchmark_warmup = std.fmt.parseInt(u32, arg["--benchmark-warmup=".len..], 10) catch return error.InvalidBenchmarkIterations;
        } else if (std.mem.eql(u8, arg, "--benchmark-warmup")) {
            config.benchmark_warmup = std.fmt.parseInt(u32, args.next() orelse return error.MissingBenchmarkIterations, 10) catch return error.InvalidBenchmarkIterations;
        } else if (std.mem.startsWith(u8, arg, "--visible-edit-publisher=")) {
            const value = arg["--visible-edit-publisher=".len..];
            if (std.mem.eql(u8, value, "true")) {
                config.visible_edit_publisher = true;
            } else if (std.mem.eql(u8, value, "false")) {
                config.visible_edit_publisher = false;
            } else return error.InvalidVisibleEditPublisher;
        } else if (std.mem.startsWith(u8, arg, "--dnd-text-publisher=")) {
            const value = arg["--dnd-text-publisher=".len..];
            if (std.mem.eql(u8, value, "true")) {
                config.dnd_text_publisher = true;
            } else if (std.mem.eql(u8, value, "false")) {
                config.dnd_text_publisher = false;
            } else return error.InvalidDndTextPublisher;
        } else if (std.mem.startsWith(u8, arg, "--cursor-smoke-publisher=")) {
            const value = arg["--cursor-smoke-publisher=".len..];
            if (std.mem.eql(u8, value, "true")) {
                config.cursor_smoke_publisher = true;
            } else if (std.mem.eql(u8, value, "false")) {
                config.cursor_smoke_publisher = false;
            } else return error.InvalidCursorSmokePublisher;
        } else if (std.mem.startsWith(u8, arg, "--scrollbar-smoke-publisher=")) {
            const value = arg["--scrollbar-smoke-publisher=".len..];
            if (std.mem.eql(u8, value, "true")) {
                config.scrollbar_smoke_publisher = true;
            } else if (std.mem.eql(u8, value, "false")) {
                config.scrollbar_smoke_publisher = false;
            } else return error.InvalidScrollbarSmokePublisher;
        } else if (std.mem.startsWith(u8, arg, "--runs-smoke-publisher=")) {
            const value = arg["--runs-smoke-publisher=".len..];
            if (std.mem.eql(u8, value, "true")) {
                config.runs_smoke_publisher = true;
            } else if (std.mem.eql(u8, value, "false")) {
                config.runs_smoke_publisher = false;
            } else return error.InvalidRunsSmokePublisher;
        } else if (std.mem.startsWith(u8, arg, "--region-smoke-publisher=")) {
            const value = arg["--region-smoke-publisher=".len..];
            if (std.mem.eql(u8, value, "true")) {
                config.region_smoke_publisher = true;
            } else if (std.mem.eql(u8, value, "false")) {
                config.region_smoke_publisher = false;
            } else return error.InvalidRegionSmokePublisher;
        } else if (std.mem.startsWith(u8, arg, "--header-smoke-publisher=")) {
            const value = arg["--header-smoke-publisher=".len..];
            if (std.mem.eql(u8, value, "true")) {
                config.header_smoke_publisher = true;
            } else if (std.mem.eql(u8, value, "false")) {
                config.header_smoke_publisher = false;
            } else return error.InvalidHeaderSmokePublisher;
        } else if (std.mem.startsWith(u8, arg, "--mouse-smoke-publisher=")) {
            const value = arg["--mouse-smoke-publisher=".len..];
            if (std.mem.eql(u8, value, "true")) {
                config.mouse_smoke_publisher = true;
            } else if (std.mem.eql(u8, value, "false")) {
                config.mouse_smoke_publisher = false;
            } else return error.InvalidMouseSmokePublisher;
        } else if (std.mem.startsWith(u8, arg, "--echo-smoke-publisher=")) {
            const value = arg["--echo-smoke-publisher=".len..];
            if (std.mem.eql(u8, value, "true")) {
                config.echo_smoke_publisher = true;
            } else if (std.mem.eql(u8, value, "false")) {
                config.echo_smoke_publisher = false;
            } else return error.InvalidEchoSmokePublisher;
        } else if (std.mem.startsWith(u8, arg, "--graphic-frame-publisher=")) {
            const value = arg["--graphic-frame-publisher=".len..];
            if (std.mem.eql(u8, value, "true")) {
                config.graphic_frame_publisher = true;
            } else if (std.mem.eql(u8, value, "false")) {
                config.graphic_frame_publisher = false;
            } else return error.InvalidGraphicFramePublisher;
        } else if (std.mem.startsWith(u8, arg, "--hscroll-smoke-publisher=")) {
            const value = arg["--hscroll-smoke-publisher=".len..];
            if (std.mem.eql(u8, value, "true")) {
                config.hscroll_smoke_publisher = true;
            } else if (std.mem.eql(u8, value, "false")) {
                config.hscroll_smoke_publisher = false;
            } else return error.InvalidHscrollSmokePublisher;
        } else if (std.mem.startsWith(u8, arg, "--face-smoke-publisher=")) {
            const value = arg["--face-smoke-publisher=".len..];
            if (std.mem.eql(u8, value, "true")) {
                config.face_smoke_publisher = true;
            } else if (std.mem.eql(u8, value, "false")) {
                config.face_smoke_publisher = false;
            } else return error.InvalidFaceSmokePublisher;
        } else if (std.mem.startsWith(u8, arg, "--menu-icon-publisher=")) {
            const value = arg["--menu-icon-publisher=".len..];
            if (std.mem.eql(u8, value, "true")) {
                config.menu_icon_publisher = true;
            } else if (std.mem.eql(u8, value, "false")) {
                config.menu_icon_publisher = false;
            } else return error.InvalidMenuIconPublisher;
        } else {
            std.debug.print("sdl3-emacs-smoke: unknown argument {s}\n", .{arg});
            return error.UnknownArgument;
        }
    }

    if ((config.mode == .replay or config.mode == .live or config.mode == .renderer_bench) and config.replay_path.len == 0) return error.MissingReplayPath;
    if (config.auto_quit_ms > 60_000) return error.AutoQuitMsOutOfRange;
    if (config.benchmark_iterations == 0 or config.benchmark_iterations > 10_000) return error.BenchmarkIterationsOutOfRange;
    if (config.benchmark_warmup > 10_000) return error.BenchmarkIterationsOutOfRange;
    if (config.mode == .emacs_epxl_bench) {
        if (config.benchmark_iterations == 0 or config.benchmark_iterations > 256)
            return error.BenchmarkIterationsOutOfRange;
        if (config.benchmark_warmup == 0 or config.benchmark_warmup > 256)
            return error.BenchmarkIterationsOutOfRange;
    }
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
    if (config.mode == .touch_tap_smoke) {
        try runTouchTapSmoke();
        return;
    }
    if (config.mode == .pen_tap_smoke) {
        try runPenSmoke();
        return;
    }
    if (config.mode == .face_text_smoke) {
        try runFaceTextSmoke(gpa);
        return;
    }
    if (config.mode == .cursor_style_smoke) {
        try runCursorStyleSmoke(gpa);
        return;
    }
    if (config.mode == .menu_hit_smoke) {
        try runMenuHitSmoke(gpa);
        return;
    }
    if (config.mode == .toolbar_hit_smoke) {
        try runToolbarHitSmoke(gpa);
        return;
    }
    if (config.mode == .dialog_hit_smoke) {
        try runDialogHitSmoke(gpa);
        return;
    }
    if (config.mode == .scrollbar_smoke) {
        try runScrollbarSmoke(gpa);
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
    if (config.mode == .provider_frame) {
        try runProviderFrameSurface(gpa);
        return;
    }
    if (config.mode == .renderer_bench) {
        try runRendererBench(gpa, io, &config);
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

    if (config.mode == .primary_selection) {
        try runPrimarySelectionSmoke();
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
                switch (event.type) {
                    SDL_EVENT_QUIT => quit = true,
                    SDL_EVENT_RENDER_TARGETS_RESET,
                    SDL_EVENT_RENDER_DEVICE_RESET,
                    SDL_EVENT_RENDER_DEVICE_LOST,
                    => unicode_text_renderer.clearTextures(),
                    else => frame_gate.dirty = true,
                }
            }
            if (quit) break;
            if (snapshot_scene) |*scene| {
                _ = try presentScene(scene, &draw_list, renderer, window, &frame_gate, &frame_counters, null);
            } else {
                try presentFacts(latest, &draw_list, renderer, window, &frame_gate, &frame_counters, null);
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

    if (config.mode == .emacs_epxl_failure_cleanup) {
        const before = try countEpxlSessionDirs(gpa, io);
        var session_config = config;
        session_config.mode = .emacs_epxl_interactive;
        session_config.auto_quit_ms = @min(session_config.auto_quit_ms, 500);
        var forced_failure = false;
        _ = runEmacsEpxlSession(gpa, io, &session_config, 1) catch |err| switch (err) {
            error.FrontendFailureRequested => forced_failure = true,
            else => return err,
        };
        if (!forced_failure) return error.FrontendFailureNotExercised;
        const after = try countEpxlSessionDirs(gpa, io);
        if (before != after) return error.PublisherSessionArtifactsRemain;
        std.debug.print(
            "sdl3-epxl-failure-cleanup-smoke: publisher and Emacs child exited before cleanup; dirs_before={d} dirs_after={d}; lifecycle OK\n",
            .{ before, after },
        );
        return;
    }

    if (config.mode == .emacs_epxl_interactive and config.manual_emacs_session) {
        var session = try runEmacsEpxlSession(gpa, io, &config, 1);
        session.deinit();
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
        .touch_tap_smoke => unreachable,
        .pen_tap_smoke => unreachable,
        .face_text_smoke => unreachable,
        .cursor_style_smoke => unreachable,
        .menu_hit_smoke => unreachable,
        .toolbar_hit_smoke => unreachable,
        .dialog_hit_smoke => unreachable,
        .scrollbar_smoke => unreachable,
        .focus_window_translation => unreachable,
        .emacs_interactive => unreachable,
        .clipboard => unreachable,
        .primary_selection => unreachable,
        .emacs_epxl => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_reconnect => try runEmacsEpxlSession(gpa, io, &config, 2),
        .emacs_epxl_recovery => try runEmacsEpxlSession(gpa, io, &config, 2),
        .emacs_epxl_gap => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_interactive => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_input => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_unicode_input => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_ime_commit => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_dnd => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_face => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_cursor => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_scrollbar => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_scroll_interaction => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_hscroll => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_menu_bar => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_menu_open => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_menu_apply => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_mouse => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_graphic => blk: {
            // The graphic publisher needs a display server to open the frame
            // that makes the real mode line and scroll bar observable, so a
            // headless run reports a bounded skip instead of failing.
            if (std.c.getenv("DISPLAY") == null and std.c.getenv("WAYLAND_DISPLAY") == null) {
                std.debug.print(
                    "sdl3-emacs-graphic-smoke: {{\"kind\":\"sdl3-emacs-graphic-smoke\",\"result\":\"skipped\",\"reason\":\"no-display\"}}\n",
                    .{},
                );
                break :blk frontend.Scene.init(gpa);
            }
            break :blk try runEmacsEpxlSession(gpa, io, &config, 1);
        },
        .emacs_epxl_key_v2 => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_key_modifier => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_window_split => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_window_navigation => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_window_restore => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_window_pointer_select => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_edit => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_bench => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_epxl_sequence => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_clipboard_unicode => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_primary_selection => try runEmacsEpxlSession(gpa, io, &config, 1),
        .emacs_pointer_selection,
        .emacs_pointer_middle_paste,
        => try runEmacsEpxlSession(gpa, io, &config, 1),
        .frame_lifecycle => {
            try runFrameLifecycleSmoke(gpa, io, &config);
            return;
        },
        .emacs_epxl_failure_cleanup => unreachable,
        .glyph_run_smoke => unreachable,
        .runtime_bridge_smoke => unreachable,
        .renderer_bench => unreachable,
        .facts_publisher => unreachable,
        .provider_frame => unreachable,
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
    if (config.mode == .emacs_epxl_gap and scene.resync_count != 2)
        return error.GapNotRecovered;
    if (config.mode == .emacs_epxl_gap and scene.stats.frame_updates < 2)
        return error.UnexpectedFactUpdateCount;
    if (config.mode == .emacs_epxl_gap and
        !sceneHasText(&scene, "XEmacs Proto-UI")) return error.GapInputNotApplied;
    if (config.mode == .emacs_epxl_recovery) {
        const applied = scene.text.items.len > 0 and
            std.mem.eql(u8, scene.text.items[0].bytes, "XEmacs Proto-UI") and
            scene.cursor != null and scene.cursor.?.x <= 16 and scene.cursor.?.y == 0;
        if (!applied) return error.RecoveryInputNotApplied;
    }
    if (config.mode == .emacs_epxl_input and scene.stats.frame_updates < 2)
        return error.UnexpectedFactUpdateCount;
    if (config.mode == .emacs_epxl_input and
        !sceneHasText(&scene, "XEmacs Proto-UI")) return error.InputNotApplied;
    if (config.mode == .emacs_epxl_input and
        (scene.cursor == null or scene.cursor.?.x < 1 or scene.cursor.?.y != 0))
        return error.CursorNotApplied;
    if (config.mode == .emacs_epxl_unicode_input and scene.stats.frame_updates < 2)
        return error.UnexpectedFactUpdateCount;
    if (config.mode == .emacs_epxl_key_modifier and scene.stats.frame_updates < 2)
        return error.UnexpectedFactUpdateCount;
    if (config.mode == .emacs_window_split and scene.stats.frame_updates < 2)
        return error.UnexpectedFactUpdateCount;
    if (config.mode == .emacs_window_split and scene.windows.items.len < 2)
        return error.WindowSplitNotObserved;
    if (config.mode == .emacs_window_split)
        std.debug.print(
            "sdl3-emacs-window-split-smoke: {{\"kind\":\"sdl3-emacs-window-split-smoke\",\"command\":\"C-x 2\",\"windows\":{d},\"rows\":{d},\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{ scene.windows.items.len, scene.rows.items.len, scene.stats.frame_updates },
        );
    if (config.mode == .emacs_window_navigation and scene.stats.frame_updates < 3)
        return error.UnexpectedFactUpdateCount;
    if (config.mode == .emacs_window_navigation) {
        if (scene.windows.items.len != 2) return error.WindowNavigationLayoutNotObserved;
        var left_window: ?frontend.Window = null;
        var right_window: ?frontend.Window = null;
        for (scene.windows.items) |window| {
            if (window.x == 0) {
                if (left_window != null) return error.WindowNavigationLayoutNotObserved;
                left_window = window;
            } else {
                if (right_window != null) return error.WindowNavigationLayoutNotObserved;
                right_window = window;
            }
        }
        const left = left_window orelse return error.WindowNavigationLayoutNotObserved;
        const right = right_window orelse return error.WindowNavigationLayoutNotObserved;
        if (left.width <= 0 or right.width <= 0 or right.x <= 0 or
            left.y != right.y or left.height != right.height)
            return error.WindowNavigationLayoutNotObserved;
        const cursor = scene.cursor orelse return error.WindowNavigationSelectionNotObserved;
        // The caret sits at the start of the selected window's first line; the
        // exact x is the frame's fringe width, which is display-dependent.
        if (!cursor.active or cursor.window_id == 0 or cursor.x > 16 or cursor.y != 0)
            return error.WindowNavigationSelectionNotObserved;
        const selected = findWindowById(scene.windows.items, cursor.window_id) orelse
            return error.WindowNavigationSelectionNotObserved;
        if (selected.x == 0 or selected.id != right.id or
            !sceneWindowTextStartsWith(&scene, left.id, "Z") or
            !sceneWindowTextStartsWith(&scene, right.id, "Z"))
            return error.WindowNavigationTextNotApplied;
        std.debug.print(
            "sdl3-emacs-window-navigation-smoke: {{\"kind\":\"sdl3-emacs-window-navigation-smoke\",\"commands\":\"C-x 3,C-x o,insert Z\",\"windows\":{d},\"selected_window_id\":{d},\"cursor_x\":{d},\"frame_updates\":{d},\"result\":\"pass\"}}\n",
            .{ scene.windows.items.len, selected.id, cursor.x, scene.stats.frame_updates },
        );
    }

    if (config.mode == .emacs_window_restore) {
        if (!window_restore_edited_split_observed or scene.windows.items.len != 1)
            return error.WindowRestoreNotObserved;
        const window = scene.windows.items[0];
        const cursor = scene.cursor orelse return error.WindowRestoreNotObserved;
        if (window.x != 0 or window.width <= 0 or window.id != cursor.window_id or
            !cursor.active or cursor.x > 16 or cursor.y != 0 or
            !sceneWindowTextStartsWith(&scene, window.id, "Z"))
            return error.WindowRestoreNotObserved;
        std.debug.print(
            "sdl3-emacs-window-restore-smoke: {{\"kind\":\"sdl3-emacs-window-restore-smoke\",\"commands\":\"C-x 3,C-x o,insert Z,C-x 1\",\"windows\":{d},\"selected_window_id\":{d},\"width\":{d},\"cursor_x\":{d},\"result\":\"pass\"}}\n",
            .{ scene.windows.items.len, window.id, window.width, cursor.x },
        );
    }

    if (config.mode == .emacs_window_pointer_select) {
        if (scene.windows.items.len != 2) return error.PointerWindowSelectLayoutNotObserved;
        var left: ?frontend.Window = null;
        var right: ?frontend.Window = null;
        for (scene.windows.items) |window| {
            if (window.x == 0) {
                if (left != null) return error.PointerWindowSelectLayoutNotObserved;
                left = window;
            } else {
                if (right != null) return error.PointerWindowSelectLayoutNotObserved;
                right = window;
            }
        }
        const left_window = left orelse return error.PointerWindowSelectLayoutNotObserved;
        const right_window = right orelse return error.PointerWindowSelectLayoutNotObserved;
        if (left_window.width <= 0 or right_window.width <= 0 or right_window.x <= 0 or
            left_window.y != right_window.y or left_window.height != right_window.height)
            return error.PointerWindowSelectLayoutNotObserved;
        const cursor = scene.cursor orelse return error.PointerWindowSelectSelectionNotObserved;
        if (!cursor.active or cursor.window_id != right_window.id or
            cursor.x > 16 or cursor.y != 0)
            return error.PointerWindowSelectSelectionNotObserved;
        if (!sceneWindowTextStartsWith(&scene, left_window.id, "Z") or
            !sceneWindowTextStartsWith(&scene, right_window.id, "Z"))
            return error.PointerWindowSelectTextNotApplied;
        std.debug.print(
            "sdl3-emacs-window-pointer-select-smoke: {{\"kind\":\"sdl3-emacs-window-pointer-select-smoke\",\"commands\":\"C-x 3,click right,insert Z\",\"windows\":{d},\"selected_window_id\":{d},\"cursor_x\":{d},\"result\":\"pass\"}}\n",
            .{ scene.windows.items.len, right_window.id, cursor.x },
        );
    }

    if (config.mode == .emacs_epxl_key_modifier) {
        if (scene.cursor == null or scene.cursor.?.x != 32 or scene.cursor.?.y != 0)
            return error.ModifierCursorNotApplied;
        std.debug.print(
            "sdl3-key-modifier-smoke: {{\"kind\":\"sdl3-key-modifier-smoke\",\"cursor_x\":{d},\"cursor_y\":{d},\"first_text\":\"{s}\",\"result\":\"pass\"}}\n",
            .{ scene.cursor.?.x, scene.cursor.?.y, scene.text.items[0].bytes[0..@min(scene.text.items[0].bytes.len, 16)] },
        );
    }
    if (config.mode == .emacs_epxl_key_v2 and
        (scene.cursor == null or scene.cursor.?.x != 72 or scene.cursor.?.y != 0))
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
        const applied = sceneHasText(&scene, "visible ASCII text");
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

    const initial_execution = try presentScene(&scene, &draw_list, renderer, window, &frame_gate, &frame_counters, null);

    // Force one deliberate repeat so the Unicode smoke can prove texture reuse
    // independently of whether the host delivers a benign window event.
    frame_gate.dirty = true;
    var repeated_execution = initial_execution;
    if (config.mode == .emacs_epxl_unicode_input) {
        // Force one deliberate repeat so the Unicode smoke can prove texture reuse
        // independently of whether the host delivers a benign window event.
        frame_gate.dirty = true;
        repeated_execution = try presentScene(&scene, &draw_list, renderer, window, &frame_gate, &frame_counters, null);
    }

    var quit = false;
    const started_ticks = SDL_GetTicks();
    while (!quit and SDL_GetTicks() - started_ticks < config.auto_quit_ms) {
        var event: SDL_Event = undefined;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) {
                quit = true;
                continue;
            }
            if (event.type == SDL_EVENT_RENDER_TARGETS_RESET or
                event.type == SDL_EVENT_RENDER_DEVICE_RESET or
                event.type == SDL_EVENT_RENDER_DEVICE_LOST)
            {
                unicode_text_renderer.clearTextures();
                frame_gate.dirty = true;
                continue;
            }
            frame_gate.dirty = true;
        }
        _ = try presentScene(&scene, &draw_list, renderer, window, &frame_gate, &frame_counters, null);
        SDL_Delay(10);
    }

    std.debug.print(
        "sdl3-eup-smoke: present={d} skipped={d} frame={d}ns draws={d} clears={d} fills={d} text={d} unicode={d} last_present={d}ns; lifecycle OK ({s})\n",
        .{
            frame_counters.presented_frames,
            frame_counters.skipped_frames,
            frame_counters.frame_path_total_ns,
            frame_counters.draw_commands_total,
            frame_counters.clear_commands_total,
            frame_counters.fill_commands_total,
            frame_counters.text_commands_total,
            frame_counters.unicode_text_commands_total,
            frame_counters.present_last_ns,
            if (quit) "closed by quit event" else "auto timeout",
        },
    );
    if (config.mode == .emacs_epxl_unicode_input) {
        if (initial_execution.unicode_texts == 0) return error.UnicodeTextNotRendered;
        if (repeated_execution.unicode_texts == 0) return error.UnicodeTextNotRendered;
        const cache_stats = unicode_text_renderer.cache.stats;
        if (cache_stats.misses == 0 or cache_stats.hits == 0 or cache_stats.evictions != 0)
            return error.UnicodeTextureCacheNotObserved;
        std.debug.print(
            "sdl3-unicode-render-smoke: {{\"kind\":\"sdl3-unicode-render-smoke\",\"text\":\"你好Emacs Proto-UI\",\"unicode_draws\":{d},\"cache_misses\":{d},\"cache_hits\":{d},\"cache_evictions\":{d},\"result\":\"pass\"}}\n",
            .{
                initial_execution.unicode_texts + repeated_execution.unicode_texts,
                cache_stats.misses,
                cache_stats.hits,
                cache_stats.evictions,
            },
        );
    }
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
            _ = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters, null);
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
    _ = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters, null);
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
    _ = try presentScene(&scene, &draw_list, selected_renderer.handle, window, &frame_gate, &frame_counters, null);
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
