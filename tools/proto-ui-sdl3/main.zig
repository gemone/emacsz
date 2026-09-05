//! Independent SDL3 frontend lifecycle smoke.
//!
//! This deliberately opens a real OS window without touching GNU Emacs.  It
//! proves only the process/window/renderer/event lifecycle; EUP consumption,
//! scene state, and Emacs input integration arrive in later slices.

const std = @import("std");

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
extern fn SDL_SetRenderDrawColor(renderer: *SDL_Renderer, r: u8, g: u8, b: u8, a: u8) bool;
extern fn SDL_RenderClear(renderer: *SDL_Renderer) bool;
extern fn SDL_RenderPresent(renderer: *SDL_Renderer) bool;
extern fn SDL_PollEvent(event: *SDL_Event) bool;
extern fn SDL_Delay(ms: c_uint) void;
extern fn SDL_GetError() [*:0]const u8;

const SDL_Event = extern struct {
    type: c_uint = 0,
    padding: [124]u8 align(8) = [_]u8{0} ** 124,
};

const Config = struct {
    auto_quit_ms: u32 = 250,
};

fn sdlFail(what: []const u8) error{SdlFailed} {
    std.debug.print("sdl3-ui-smoke: {s} failed: {s}\n", .{ what, SDL_GetError() });
    return error.SdlFailed;
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var args = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer args.deinit();
    _ = args.next();

    var config: Config = .{};
    while (args.next()) |arg| {
        const prefix = "--auto-quit-ms=";
        if (std.mem.startsWith(u8, arg, prefix)) {
            config.auto_quit_ms = std.fmt.parseInt(u32, arg[prefix.len..], 10) catch return error.InvalidAutoQuitMs;
        } else return error.UnknownArgument;
    }
    if (config.auto_quit_ms > 10_000) return error.AutoQuitMsOutOfRange;

    if (!SDL_Init(SDL_INIT_VIDEO)) return sdlFail("SDL_Init");
    defer SDL_Quit();

    const window = SDL_CreateWindow("Emacs Proto-UI SDL3 Smoke", 800, 600, SDL_WINDOW_RESIZABLE) orelse return sdlFail("SDL_CreateWindow");
    defer SDL_DestroyWindow(window);

    const renderer = SDL_CreateRenderer(window, null) orelse return sdlFail("SDL_CreateRenderer");
    defer SDL_DestroyRenderer(renderer);

    if (!SDL_SetRenderDrawColor(renderer, 0x24, 0x32, 0x48, 0xff)) return sdlFail("SDL_SetRenderDrawColor");
    if (!SDL_RenderClear(renderer)) return sdlFail("SDL_RenderClear");
    if (!SDL_RenderPresent(renderer)) return sdlFail("SDL_RenderPresent");

    std.debug.print("sdl3-ui-smoke: window/renderer ready; auto quit in {d}ms\n", .{config.auto_quit_ms});

    var quit = false;
    var waited_ms: u32 = 0;
    while (!quit and waited_ms < config.auto_quit_ms) {
        var event: SDL_Event = .{};
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) {
                quit = true;
            }
        }
        SDL_Delay(10);
        waited_ms += 10;
    }

    std.debug.print("sdl3-ui-smoke: lifecycle OK ({s})\n", .{if (quit) "closed by quit event" else "auto timeout"});
}
