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

fn integerOf(env: *emacs.struct_emacs_env_32, value: emacs.emacs_value) ?i64 {
    if (pending(env) or env.is_not_nil.?(env, value) == false) return null;
    return @intCast(env.extract_integer.?(env, value));
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

export fn emacs_module_init(runtime: *emacs.struct_emacs_runtime) c_int {
    if (runtime.size < @sizeOf(emacs.struct_emacs_runtime)) return 1;
    if (runtime.get_environment == null) return 2;
    const env = runtime.get_environment.?(runtime) orelse return 3;
    if (env.*.size < @sizeOf(emacs.struct_emacs_env_31)) return 4;
    if (env.*.non_local_exit_check.?(env) != 0) return 5;

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
    return 0;
}
