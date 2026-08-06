// Native Zig implementation of gnulib's lib/careadlinkat.c
// (careadlinkat), reading a symlink's value via the caller-provided
// preadlinkat callback into a caller buffer or an allocator-managed
// buffer, growing on truncation. Backs `file-symlink-p' and
// `file-truename' (src/fileio.c emacs_readlinkat). The readlink
// callback and the allocator are provided by the caller, so no libc
// call happens on the Emacs path; the C's NULL-allocator stdlib
// fallback is kept for full API compatibility.

const std = @import("std");
const builtin = @import("builtin");

comptime {
    if (builtin.os.tag != .linux and builtin.os.tag != .android)
        @compileError("gnulib-careadlinkat: current port targets Linux-like POSIX readlinkat");
}

extern fn __errno_location() *c_int;
extern fn malloc(size: usize) ?*anyopaque;
extern fn realloc(p: ?*anyopaque, size: usize) ?*anyopaque;
extern fn free(p: ?*anyopaque) void;

const ENAMETOOLONG: c_int = 36;
const ENOMEM: c_int = 12;
const STACK_BUF_SIZE: usize = 1024;

// gnulib struct allocator (lib/allocator.h): four function pointers.
pub const Allocator = extern struct {
    allocate: ?*const fn (usize) callconv(.c) ?*anyopaque,
    reallocate: ?*const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque,
    free: ?*const fn (?*anyopaque) callconv(.c) void,
    die: ?*const fn (usize) callconv(.c) void,
};

const stdlibAllocator = Allocator{
    .allocate = malloc,
    .reallocate = realloc,
    .free = free,
    .die = null,
};

const PreReadlinkat = *const fn (c_int, [*:0]const u8, [*]u8, usize) callconv(.c) isize;

fn readlinkStk(
    fd: c_int,
    filename: [*:0]const u8,
    buffer_in: ?[*]u8,
    buffer_size_in: usize,
    alloc_in: ?*const Allocator,
    preadlinkat: PreReadlinkat,
    stack_buf: *[STACK_BUF_SIZE]u8,
) ?[*:0]u8 {
    const alloc = alloc_in orelse &stdlibAllocator;

    var buffer = buffer_in;
    var buffer_size = buffer_size_in;
    if (buffer == null) {
        buffer = stack_buf;
        buffer_size = STACK_BUF_SIZE;
    }
    const original_buffer = buffer_in;

    var buf: ?[*]u8 = buffer;
    const buf_size_max: usize = std.math.maxInt(isize);
    var buf_size = @min(buffer_size, buf_size_max);

    while (buf) |b| {
        const link_length = preadlinkat(fd, filename, b, buf_size);
        if (link_length < 0) {
            if (b != original_buffer) {
                // free() may clobber errno, which preadlinkat set.
                const saved_errno = __errno_location().*;
                alloc.free.?(b);
                __errno_location().* = saved_errno;
            }
            return null;
        }

        var link_size: usize = @intCast(link_length);
        if (link_size < buf_size) {
            b[link_size] = 0;
            link_size += 1;

            if (b == stack_buf) {
                // Copy the small link out of the stack buffer.
                const nb: [*]u8 = @ptrCast(alloc.allocate.?(link_size) orelse break);
                @memcpy(nb[0..link_size], b[0..link_size]);
                return @ptrCast(nb);
            }

            if (link_size < buf_size and b != original_buffer and alloc.reallocate != null) {
                // Shrink the heap buffer before returning it.
                if (alloc.reallocate.?(b, link_size)) |nb|
                    return @ptrCast(nb);
            }
            return @ptrCast(b);
        }

        // The link was truncated; grow the buffer and retry.
        if (b != original_buffer)
            alloc.free.?(b);
        if (buf_size_max / 2 <= buf_size) {
            __errno_location().* = ENAMETOOLONG;
            return null;
        }
        buf_size = 2 * buf_size + 1;
        const grown = alloc.allocate.?(buf_size) orelse break;
        buf = @ptrCast(grown);
    }

    if (alloc.die) |die|
        die(buf_size);
    __errno_location().* = ENOMEM;
    return null;
}

// Read the symbolic link value of FILENAME relative to FD (AT_FDCWD for
// the current directory) into BUFFER when it fits, else into a buffer
// managed by ALLOC (NULL for the standard allocator).  Returns the
// buffer address or NULL with errno set.
pub export fn careadlinkat(
    fd: c_int,
    filename: [*:0]const u8,
    buffer: ?[*]u8,
    buffer_size: usize,
    alloc: ?*const Allocator,
    preadlinkat: PreReadlinkat,
) ?[*:0]u8 {
    var stack_buf: [STACK_BUF_SIZE]u8 = undefined;
    return readlinkStk(fd, filename, buffer, buffer_size, alloc, preadlinkat, &stack_buf);
}
