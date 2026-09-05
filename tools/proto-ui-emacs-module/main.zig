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
//! This prototype proves only module identity and Lisp string conversion.  It
//! does not expose redisplay, input, fonts, resources, or frames.

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
    return 0;
}
