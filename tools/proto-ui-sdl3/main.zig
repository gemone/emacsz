//! Independent SDL3 frontend that consumes an EUP replay session.
//!
//! This slice decodes a real EUP `FRAME_UPDATE`, builds frontend-owned scene
//! state, and renders frame/window/row/cursor geometry.  It does not yet open
//! a live transport session or connect to GNU Emacs.

const std = @import("std");
const proto_ui = @import("proto_ui");
const frontend = proto_ui.frontend;
const protocol = proto_ui.protocol;
const transport = proto_ui.transport;

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

const Config = struct {
    replay_path: []const u8,
    auto_quit_ms: u32 = 250,
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

fn findSceneWindow(scene: *frontend.Scene, id: u64) ?frontend.Window {
    for (scene.windows.items) |window| {
        if (window.id == id) return window;
    }
    return null;
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var args = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer args.deinit();
    _ = args.next();

    var config: Config = .{ .replay_path = "" };
    while (args.next()) |arg| {
        const replay_prefix = "--replay=";
        const quit_prefix = "--auto-quit-ms=";
        if (std.mem.startsWith(u8, arg, replay_prefix)) {
            config.replay_path = try gpa.dupe(u8, arg[replay_prefix.len..]);
        } else if (std.mem.eql(u8, arg, "--replay")) {
            config.replay_path = try gpa.dupe(u8, args.next() orelse return error.MissingReplayPath);
        } else if (std.mem.startsWith(u8, arg, quit_prefix)) {
            config.auto_quit_ms = std.fmt.parseInt(u32, arg[quit_prefix.len..], 10) catch return error.InvalidAutoQuitMs;
        } else return error.UnknownArgument;
    }
    defer if (config.replay_path.len != 0) gpa.free(config.replay_path);
    if (config.replay_path.len == 0) return error.MissingReplayPath;
    if (config.auto_quit_ms > 10_000) return error.AutoQuitMsOutOfRange;

    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();

    const wire_messages = try transport.readReplay(gpa, io, config.replay_path);
    defer transport.freeReplay(gpa, wire_messages);

    var scene = frontend.Scene.init(gpa);
    defer scene.deinit();
    for (wire_messages) |message| {
        try scene.apply(message);
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
