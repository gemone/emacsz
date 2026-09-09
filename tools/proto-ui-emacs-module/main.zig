//! Adapter-owned Emacs dynamic-module seam.
//!
//! Copyright (C) 2026 Free Software Foundation, Inc.
//!
//! This file is part of GNU Emacs.
//!
//! GNU Emacs is free software: you can redistribute it and/or modify it under
//! the terms of the GNU General Public License as published by the Free
//! Software Foundation, either version 3 of the License, or (at your option)
//! any later version.
//!
//! GNU Emacs is distributed in the hope that it will be useful, but WITHOUT ANY
//! WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
//! FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
//! details.  You should have received a copy of the GNU General Public License
//! along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.
//!
//! This bridge observes only public, Emacs-observable frame/window facts.  It
//! does not expose redisplay internals, input, fonts, resources, or rendering.

const std = @import("std");
const emacs = @cImport(@cInclude("emacs-module.h"));

export var plugin_is_GPL_compatible: c_int = 0;

fn signalError(env: *emacs.struct_emacs_env_32, message: []const u8) void {
    const symbol = env.intern.?(env, "error") orelse return;
    const data = env.make_string.?(env, message.ptr, @intCast(message.len)) orelse return;
    env.non_local_exit_signal.?(env, symbol, data);
}

fn nilValue(env: *emacs.struct_emacs_env_32) emacs.emacs_value {
    return env.intern.?(env, "nil");
}

fn pending(env: *emacs.struct_emacs_env_32) bool {
    return env.non_local_exit_check.?(env) != 0;
}

fn call1(env: *emacs.struct_emacs_env_32, function: [*:0]const u8, argument: emacs.emacs_value) emacs.emacs_value {
    const function_value = env.intern.?(env, function) orelse return null;
    var args = [_]emacs.emacs_value{argument};
    return env.funcall.?(env, function_value, 1, &args);
}

fn call0(env: *emacs.struct_emacs_env_32, function: [*:0]const u8) emacs.emacs_value {
    const function_value = env.intern.?(env, function) orelse return null;
    return env.funcall.?(env, function_value, 0, null);
}

fn call2(
    env: *emacs.struct_emacs_env_32,
    function: [*:0]const u8,
    first: emacs.emacs_value,
    second: emacs.emacs_value,
) emacs.emacs_value {
    const function_value = env.intern.?(env, function) orelse return null;
    var args = [_]emacs.emacs_value{ first, second };
    return env.funcall.?(env, function_value, 2, &args);
}

fn call3(
    env: *emacs.struct_emacs_env_32,
    function: [*:0]const u8,
    first: emacs.emacs_value,
    second: emacs.emacs_value,
    third: emacs.emacs_value,
) emacs.emacs_value {
    const function_value = env.intern.?(env, function) orelse return null;
    var args = [_]emacs.emacs_value{ first, second, third };
    return env.funcall.?(env, function_value, 3, &args);
}

fn call4(
    env: *emacs.struct_emacs_env_32,
    function: [*:0]const u8,
    first: emacs.emacs_value,
    second: emacs.emacs_value,
    third: emacs.emacs_value,
    fourth: emacs.emacs_value,
) emacs.emacs_value {
    const function_value = env.intern.?(env, function) orelse return null;
    var args = [_]emacs.emacs_value{ first, second, third, fourth };
    return env.funcall.?(env, function_value, 4, &args);
}

fn integerOf(env: *emacs.struct_emacs_env_32, value: emacs.emacs_value) ?i64 {
    if (pending(env) or env.is_not_nil.?(env, value) == false) return null;
    return @intCast(env.extract_integer.?(env, value));
}

const max_observed_windows: usize = 16;
const max_window_facts_bytes: usize = 2048;

const ObservedWindow = struct {
    id: u32,
    index: usize,
    x: i64,
    y: i64,
    width: u32,
    height: u32,
    selected: bool,
};

const WindowFacts = struct {
    selected_index: usize,
    windows: []const ObservedWindow,

    fn format(self: WindowFacts, buffer: []u8) []const u8 {
        var writer: std.Io.Writer = .fixed(buffer);
        writer.writeAll("{\"ordering\":\"selection_relative\",\"identity\":\"process_lifetime\",\"selected_index\":") catch return "";
        writer.print("{d},\"window_count\":{d},\"windows\":[", .{
            self.selected_index,
            self.windows.len,
        }) catch return "";
        for (self.windows, 0..) |window, index| {
            if (index != 0) writer.writeAll(",") catch return "";
            writer.print(
                "{{\"id\":{d},\"index\":{d},\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d},\"selected\":{s}}}",
                .{
                    window.id,
                    window.index,
                    window.x,
                    window.y,
                    window.width,
                    window.height,
                    if (window.selected) "true" else "false",
                },
            ) catch return "";
        }
        writer.writeAll("]}") catch return "";
        return writer.buffered();
    }
};

fn geometryComponent(
    env: *emacs.struct_emacs_env_32,
    edges: emacs.emacs_value,
    index: usize,
    name: []const u8,
) ?i64 {
    if (pending(env)) return null;
    const index_value = env.make_integer.?(env, @intCast(index)) orelse return null;
    const item = call2(env, "nth", index_value, edges) orelse return null;
    if (pending(env)) return null;
    const value = integerOf(env, item) orelse {
        signalError(env, name);
        return null;
    };
    return value;
}

fn registrySymbol(env: *emacs.struct_emacs_env_32) emacs.emacs_value {
    return env.intern.?(env, "proto-ui-window-id-table");
}

fn counterSymbol(env: *emacs.struct_emacs_env_32) emacs.emacs_value {
    return env.intern.?(env, "proto-ui-window-next-id");
}

fn ensureWindowRegistry(env: *emacs.struct_emacs_env_32) bool {
    const registry = registrySymbol(env) orelse return false;
    const bound = call1(env, "boundp", registry) orelse return false;
    if (pending(env) or env.is_not_nil.?(env, bound) == false) {
        const test_keyword = env.intern.?(env, ":test") orelse return false;
        const eq_symbol = env.intern.?(env, "eq") orelse return false;
        const weakness_keyword = env.intern.?(env, ":weakness") orelse return false;
        const key_symbol = env.intern.?(env, "key") orelse return false;
        const table = call4(
            env,
            "make-hash-table",
            test_keyword,
            eq_symbol,
            weakness_keyword,
            key_symbol,
        ) orelse return false;
        _ = call2(env, "set", registry, table) orelse return false;
    }
    const counter = counterSymbol(env) orelse return false;
    const counter_bound = call1(env, "boundp", counter) orelse return false;
    if (pending(env) or env.is_not_nil.?(env, counter_bound) == false) {
        const zero = env.make_integer.?(env, 0) orelse return false;
        _ = call2(env, "set", counter, zero) orelse return false;
    }
    if (pending(env)) return false;
    return true;
}

fn stableWindowId(env: *emacs.struct_emacs_env_32, window: emacs.emacs_value) ?u32 {
    const registry = call1(env, "symbol-value", registrySymbol(env) orelse return null) orelse return null;
    if (pending(env)) return null;
    const existing = call2(env, "gethash", window, registry) orelse return null;
    if (pending(env)) return null;
    if (env.is_not_nil.?(env, existing)) {
        const id = integerOf(env, existing) orelse {
            signalError(env, "Proto-UI window identity was not an integer");
            return null;
        };
        if (id <= 0 or id > std.math.maxInt(u32)) {
            signalError(env, "Proto-UI persisted window identity is invalid");
            return null;
        }
        return @intCast(id);
    }

    const counter_symbol = counterSymbol(env) orelse return null;
    const counter = call1(env, "symbol-value", counter_symbol) orelse return null;
    if (pending(env)) return null;
    const next = call2(env, "+", counter, env.make_integer.?(env, 1) orelse return null) orelse return null;
    if (pending(env)) return null;
    const next_id = integerOf(env, next) orelse {
        signalError(env, "Proto-UI window identity counter was not an integer");
        return null;
    };
    if (pending(env)) return null;
    if (next_id <= 0 or next_id > std.math.maxInt(u32)) {
        signalError(env, "Proto-UI window identity space exhausted");
        return null;
    }
    _ = call2(env, "set", counter_symbol, next) orelse return null;
    if (pending(env)) return null;
    _ = call3(env, "puthash", window, next, registry) orelse return null;
    if (pending(env)) return null;
    return @intCast(next_id);
}

fn windowFacts(
    maybe_env: ?*emacs.struct_emacs_env_32,
    nargs: c_long,
    args: [*c]emacs.emacs_value,
    data: ?*anyopaque,
) callconv(.c) emacs.emacs_value {
    _ = data;
    const env = maybe_env orelse return null;
    if (pending(env)) return null;
    if (nargs != 1) {
        signalError(env, "Wrong number of arguments: proto-ui-window-facts, 1");
        return null;
    }
    if (env.should_quit.?(env)) return null;
    const frame_live = call1(env, "frame-live-p", args[0]) orelse return null;
    if (pending(env)) return null;
    if (env.is_not_nil.?(env, frame_live) == false) {
        signalError(env, "Proto-UI window facts require a live frame");
        return null;
    }
    if (!ensureWindowRegistry(env)) return null;

    const selected = call1(env, "frame-selected-window", args[0]) orelse return null;
    if (pending(env)) return null;
    const list = call1(env, "window-list", args[0]) orelse return null;
    if (pending(env)) return null;

    var windows: [max_observed_windows]ObservedWindow = undefined;
    var count: usize = 0;
    var selected_index: ?usize = null;
    var rest = list;
    while (count < max_observed_windows and env.is_not_nil.?(env, rest)) {
        const window = call1(env, "car", rest) orelse return null;
        if (pending(env)) return null;
        const id = stableWindowId(env, window) orelse return null;
        if (pending(env)) return null;
        const edges = call1(env, "window-pixel-edges", window) orelse return null;
        if (pending(env)) return null;

        const left = geometryComponent(env, edges, 0, "Proto-UI window left edge was not an integer") orelse return null;
        const top = geometryComponent(env, edges, 1, "Proto-UI window top edge was not an integer") orelse return null;
        const right = geometryComponent(env, edges, 2, "Proto-UI window right edge was not an integer") orelse return null;
        const bottom = geometryComponent(env, edges, 3, "Proto-UI window bottom edge was not an integer") orelse return null;
        if (left < 0 or top < 0 or right < left or bottom < top or
            right > 1_000_000 or bottom > 1_000_000)
        {
            signalError(env, "Proto-UI window geometry exceeds bounded facts");
            return null;
        }

        const selected_value = call2(env, "eq", window, selected) orelse return null;
        if (pending(env)) return null;
        const is_selected = env.is_not_nil.?(env, selected_value);
        if (is_selected) {
            if (selected_index != null) {
                signalError(env, "Proto-UI observed multiple selected windows");
                return null;
            }
            selected_index = count;
        }

        windows[count] = .{
            .id = id,
            .index = count,
            .x = left,
            .y = top,
            .width = @intCast(right - left),
            .height = @intCast(bottom - top),
            .selected = is_selected,
        };
        count += 1;
        rest = call1(env, "cdr", rest) orelse return null;
        if (pending(env)) return null;
    }

    if (env.is_not_nil.?(env, rest) or count == 0 or selected_index == null) {
        signalError(env, "Proto-UI window facts exceeded bounded observation");
        return null;
    }

    var buffer: [max_window_facts_bytes]u8 = undefined;
    const text = (WindowFacts{
        .selected_index = selected_index.?,
        .windows = windows[0..count],
    }).format(&buffer);
    if (text.len == 0) {
        signalError(env, "Proto-UI window facts exceeded buffer");
        return null;
    }
    return env.make_string.?(env, text.ptr, @intCast(text.len));
}

fn echo(
    maybe_env: ?*emacs.struct_emacs_env_32,
    nargs: c_long,
    args: [*c]emacs.emacs_value,
    data: ?*anyopaque,
) callconv(.c) emacs.emacs_value {
    _ = data;
    const env = maybe_env orelse return null;
    if (env.non_local_exit_check.?(env) != 0) return null;
    const nil = nilValue(env) orelse return null;
    if (nargs != 1) {
        signalError(env, "Wrong number of arguments: proto-ui-echo, 1");
        return nil;
    }
    if (env.should_quit.?(env)) return nil;

    var required: isize = 0;
    if (!env.copy_string_contents.?(env, args[0], null, &required)) return nil;
    if (required <= 0 or required > 128) {
        signalError(env, "Proto-UI input exceeds 127 bytes");
        return nil;
    }

    var buffer: [128]u8 = undefined;
    var length: isize = required;
    if (!env.copy_string_contents.?(env, args[0], &buffer, &length)) return nil;
    const text_length: usize = @intCast(length - 1);
    const prefix = "proto-ui:";
    if (prefix.len + text_length > buffer.len) {
        signalError(env, "Proto-UI input exceeds 127 bytes");
        return nil;
    }

    var response: [128]u8 = undefined;
    @memcpy(response[0..prefix.len], prefix);
    @memcpy(response[prefix.len..][0..text_length], buffer[0..text_length]);
    return env.make_string.?(env, &response, @intCast(prefix.len + text_length));
}

fn frameFacts(
    maybe_env: ?*emacs.struct_emacs_env_32,
    nargs: c_long,
    args: [*c]emacs.emacs_value,
    data: ?*anyopaque,
) callconv(.c) emacs.emacs_value {
    _ = data;
    const env = maybe_env orelse return null;
    if (pending(env)) return null;
    const nil = nilValue(env) orelse return null;
    if (nargs != 1) {
        signalError(env, "Wrong number of arguments: proto-ui-frame-facts, 1");
        return nil;
    }
    if (env.should_quit.?(env)) return nil;

    const window = call1(env, "frame-selected-window", args[0]) orelse return nil;
    if (pending(env)) return nil;
    const width_value = call1(env, "frame-pixel-width", args[0]) orelse return nil;
    const height_value = call1(env, "frame-pixel-height", args[0]) orelse return nil;
    const window_width_value = call1(env, "window-pixel-width", window) orelse return nil;
    const window_height_value = call1(env, "window-pixel-height", window) orelse return nil;

    const width = integerOf(env, width_value) orelse {
        signalError(env, "Proto-UI frame width was not an integer");
        return nil;
    };
    if (pending(env)) return nil;
    const height = integerOf(env, height_value) orelse {
        signalError(env, "Proto-UI frame height was not an integer");
        return nil;
    };
    if (pending(env)) return nil;
    const window_width = integerOf(env, window_width_value) orelse {
        signalError(env, "Proto-UI window width was not an integer");
        return nil;
    };
    if (pending(env)) return nil;
    const window_height = integerOf(env, window_height_value) orelse {
        signalError(env, "Proto-UI window height was not an integer");
        return nil;
    };
    if (pending(env)) return nil;

    var facts: [160]u8 = undefined;
    const text = std.fmt.bufPrint(&facts, "{{\"frame_width\":{d},\"frame_height\":{d},\"window_width\":{d},\"window_height\":{d}}}", .{
        width,
        height,
        window_width,
        window_height,
    }) catch {
        signalError(env, "Proto-UI frame facts exceeded buffer");
        return nil;
    };
    return env.make_string.?(env, text.ptr, @intCast(text.len));
}

fn windowId(
    maybe_env: ?*emacs.struct_emacs_env_32,
    nargs: c_long,
    args: [*c]emacs.emacs_value,
    data: ?*anyopaque,
) callconv(.c) emacs.emacs_value {
    _ = data;
    const env = maybe_env orelse return null;
    if (pending(env)) return null;
    if (nargs != 1) {
        signalError(env, "Wrong number of arguments: proto-ui-window-id, 1");
        return null;
    }
    if (env.should_quit.?(env)) return null;
    const live = call1(env, "window-live-p", args[0]) orelse return null;
    if (pending(env)) return null;
    if (env.is_not_nil.?(env, live) == false) {
        signalError(env, "Proto-UI window identity requires a live window");
        return null;
    }
    if (!ensureWindowRegistry(env)) return null;
    const id = stableWindowId(env, args[0]) orelse return null;
    if (pending(env)) return null;
    return env.make_integer.?(env, @intCast(id));
}

export fn emacs_module_init(runtime: *emacs.struct_emacs_runtime) c_int {
    if (runtime.size < @sizeOf(emacs.struct_emacs_runtime)) return 1;
    if (runtime.get_environment == null) return 2;
    const env = runtime.get_environment.?(runtime) orelse return 3;
    if (env.*.size < @sizeOf(emacs.struct_emacs_env_31)) return 4;
    if (env.*.non_local_exit_check.?(env) != 0) return 5;
    if (!ensureWindowRegistry(env)) return 18;

    const echo_value = env.*.make_function.?(
        env,
        1,
        1,
        echo,
        "Return ARG prefixed by the adapter-owned Proto-UI bridge.",
        null,
    ) orelse return 6;
    const symbol = env.*.intern.?(env, "proto-ui-echo") orelse return 7;
    const defalias = env.*.intern.?(env, "defalias") orelse return 8;
    var args = [_]emacs.emacs_value{ symbol, echo_value };
    _ = env.*.funcall.?(env, defalias, 2, &args);
    if (env.*.non_local_exit_check.?(env) != 0) return 9;

    const facts_value = env.*.make_function.?(
        env,
        1,
        1,
        frameFacts,
        "Return public frame/window dimensions as adapter-owned JSON.",
        null,
    ) orelse return 10;
    const facts_symbol = env.*.intern.?(env, "proto-ui-frame-facts") orelse return 11;
    const facts_defalias = env.*.intern.?(env, "defalias") orelse return 12;
    var facts_args = [_]emacs.emacs_value{ facts_symbol, facts_value };
    _ = env.*.funcall.?(env, facts_defalias, 2, &facts_args);
    if (env.*.non_local_exit_check.?(env) != 0) return 13;

    const window_facts_value = env.*.make_function.?(
        env,
        1,
        1,
        windowFacts,
        "Return bounded public multi-window geometry as adapter-owned JSON.",
        null,
    ) orelse return 14;
    const window_facts_symbol = env.*.intern.?(env, "proto-ui-window-facts") orelse return 15;
    const window_facts_defalias = env.*.intern.?(env, "defalias") orelse return 16;
    var window_facts_args = [_]emacs.emacs_value{ window_facts_symbol, window_facts_value };
    _ = env.*.funcall.?(env, window_facts_defalias, 2, &window_facts_args);
    if (env.*.non_local_exit_check.?(env) != 0) return 17;
    const window_id_value = env.*.make_function.?(
        env,
        1,
        1,
        windowId,
        "Return the adapter-owned process-lifetime ID for WINDOW, which must be live.",
        null,
    ) orelse return 18;
    const window_id_symbol = env.*.intern.?(env, "proto-ui-window-id") orelse return 19;
    const window_id_defalias = env.*.intern.?(env, "defalias") orelse return 20;
    var window_id_args = [_]emacs.emacs_value{ window_id_symbol, window_id_value };
    _ = env.*.funcall.?(env, window_id_defalias, 2, &window_id_args);
    if (env.*.non_local_exit_check.?(env) != 0) return 21;
    return 0;
}

test "formats bounded multi-window facts" {
    var windows = [_]ObservedWindow{
        .{ .id = 101, .index = 0, .x = 0, .y = 0, .width = 120, .height = 80, .selected = true },
        .{ .id = 102, .index = 1, .x = 120, .y = 0, .width = 80, .height = 80, .selected = false },
    };
    var buffer: [max_window_facts_bytes]u8 = undefined;
    const text = (WindowFacts{ .selected_index = 0, .windows = &windows }).format(&buffer);
    try std.testing.expectEqualStrings(
        "{\"ordering\":\"selection_relative\",\"identity\":\"process_lifetime\",\"selected_index\":0,\"window_count\":2,\"windows\":[{\"id\":101,\"index\":0,\"x\":0,\"y\":0,\"width\":120,\"height\":80,\"selected\":true},{\"id\":102,\"index\":1,\"x\":120,\"y\":0,\"width\":80,\"height\":80,\"selected\":false}]}",
        text,
    );
}
