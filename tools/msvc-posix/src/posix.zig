// Native Zig provider of the POSIX-name file/dir functions that the MSVC
// ABI's UCRT does not export (it only exports the underscored _open/_close/
// _mkdir/_unlink/_getcwd/_stati64... forms).  Emacs's lib-src tools
// (emacsclient, etags) and the vendored Zig gnulib-tempname package call the
// plain POSIX names; MinGW's msvcrt.dll exports both spellings, so the GNU
// backend never needs this.  Linked only into the MSVC command-line tools
// (see build.zig): each `export fn` below forwards a POSIX name to its MSVC
// CRT twin.  A Zig package (rather than a C shim) is used because the Emacs
// w32 headers macro-map these very names (open->sys_open, close->sys_close,
// mkdir->sys_mkdir via ms-w32.h), which would rewrite the bodies of any C
// wrapper; `export fn` emits the exact C symbol regardless.
//
// Upstream-sync note: this mirrors the POSIX-name aliases that mingw
// supplies; it is MSVC-backend-only and can be dropped if the UCRT ever
// starts exporting the plain names.

const std = @import("std");

comptime {
    // w32.c ships its own getcwd/stat/fstat/lstat for the temacs build, so
    // those four are exported only when requested (the tools consumers).
    _ = @import("build_options");
}
const options = @import("build_options");

// The CRT's O_BINARY flag (0x8000 on MSVC), matching <fcntl.h>.  We OR it
// onto the flags so the tools behave on Windows exactly as under MinGW.
const O_BINARY: c_int = 0x8000;

// The CRT "_" functions this package forwards to (declared variadic where
// the CRT itself is, so callers passing extra args keep working).
extern "c" fn _open(path: [*:0]const u8, oflag: c_int, ...) c_int;
extern "c" fn _close(fd: c_int) c_int;
extern "c" fn _mkdir(path: [*:0]const u8) c_int;
extern "c" fn _unlink(path: [*:0]const u8) c_int;
extern "c" fn _getcwd(buf: [*]u8, maxlen: c_int) ?[*]u8;
extern "c" fn _stati64(path: [*:0]const u8, buf: *anyopaque) c_int;
extern "c" fn _fstati64(fd: c_int, buf: *anyopaque) c_int;
extern "c" fn _lseek(fd: c_int, offset: c_long, origin: c_int) c_long;
extern "c" fn _stricmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
extern "c" fn _strnicmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) c_int;
extern "c" fn _access(path: [*:0]const u8, mode: c_int) c_int;
extern "c" fn _chdir(path: [*:0]const u8) c_int;
extern "c" fn _tzset() void;

export fn open(path: [*:0]const u8, flags: c_int, mode: c_int) c_int {
    _ = mode; // Windows ignores the creation mode; _open defaults it.
    return _open(path, flags | O_BINARY);
}

export fn close(fd: c_int) c_int {
    return _close(fd);
}

// MSVC's _mkdir takes a single argument; the POSIX/Zig callers pass a mode
// that Windows ignores.
export fn mkdir(path: [*:0]const u8, mode: c_int) c_int {
    _ = mode;
    return _mkdir(path);
}

export fn unlink(path: [*:0]const u8) c_int {
    return _unlink(path);
}

comptime {
    if (options.include_file_status_fns) {
        @export(&stat, .{ .name = "stat" });
        @export(&fstat, .{ .name = "fstat" });
        @export(&lstat, .{ .name = "lstat" });
        @export(&getcwd, .{ .name = "getcwd" });
    }
}

fn getcwd(buf: [*]u8, size: usize) callconv(.c) ?[*]u8 {
    // The CRT's _getcwd takes an int maxlen; sizes that can't fit are not
    // a realistic concern for the callers.
    return _getcwd(buf, @intCast(size));
}

// The lib-src tools only test stat/fstat/lstat for success/failure (they
// never read Emacs's wide gname/uname fields), so forward to the CRT's
// 64-bit _stati64, writing into the caller's (larger) Emacs struct.
fn stat(path: [*:0]const u8, buf: ?*anyopaque) callconv(.c) c_int {
    return _stati64(path, buf.?);
}

fn fstat(fd: c_int, buf: ?*anyopaque) callconv(.c) c_int {
    return _fstati64(fd, buf.?);
}

fn lstat(path: [*:0]const u8, buf: ?*anyopaque) callconv(.c) c_int {
    return _stati64(path, buf.?);
}

// Remaining POSIX names the MSVC UCRT spells with an underscore prefix.
export fn lseek(fd: c_int, offset: c_long, origin: c_int) c_long {
    return _lseek(fd, offset, origin);
}

export fn stricmp(a: [*:0]const u8, b: [*:0]const u8) c_int {
    return _stricmp(a, b);
}

export fn strnicmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) c_int {
    return _strnicmp(a, b, n);
}

export fn access(path: [*:0]const u8, mode: c_int) c_int {
    return _access(path, mode);
}

export fn chdir(path: [*:0]const u8) c_int {
    return _chdir(path);
}

export fn tzset() void {
    _tzset();
}
