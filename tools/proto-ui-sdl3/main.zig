//! Independent SDL3 frontend that consumes EUP replay or local live sessions.
//!
//! This slice decodes a real EUP `FRAME_UPDATE`, builds frontend-owned scene
//! state, and renders frame/window/row/cursor geometry.  The local live
//! transport path does not yet connect to GNU Emacs.

const std = @import("std");
const native_os = @import("builtin").os.tag;
const proto_ui = @import("proto_ui");
const frontend = proto_ui.frontend;
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

const Mode = enum { replay, live, publisher };

const Config = struct {
    mode: Mode = .replay,
    self_exe: []const u8 = "",
    replay_path: []const u8 = "",
    endpoint: []const u8 = "",
    token_path: []const u8 = "",
    token: live.Token = undefined,
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
    for (messages) |message| {
        try live.writeFrame(&writer.interface, message);
    }
    try writer.interface.flush();
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

    var scene = frontend.Scene.init(gpa);
    errdefer scene.deinit();
    while (true) {
        const message = (try live.readFrame(&reader.interface, gpa)) orelse break;
        defer gpa.free(message);
        try scene.apply(message);
    }
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
        if (std.mem.eql(u8, arg, "--replay")) {
            try setString(gpa, &config.replay_path, args.next() orelse return error.MissingReplayPath);
        } else if (std.mem.startsWith(u8, arg, replay_prefix)) {
            try setString(gpa, &config.replay_path, arg[replay_prefix.len..]);
        } else if (std.mem.eql(u8, arg, "--endpoint")) {
            try setString(gpa, &config.endpoint, args.next() orelse return error.MissingEndpoint);
        } else if (std.mem.startsWith(u8, arg, endpoint_prefix)) {
            try setString(gpa, &config.endpoint, arg[endpoint_prefix.len..]);
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
        } else return error.UnknownArgument;
    }

    if (config.replay_path.len == 0) return error.MissingReplayPath;
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
    };
    defer scene.deinit();
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
