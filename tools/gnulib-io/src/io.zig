//! Native Zig implementation of the remaining live gnulib I/O wrappers
//! used by Emacs: close_stream (lib/close-stream.c), set_binary_mode
//! (lib/binary-io.c + binary-io.h) and rpl_pipe2 (lib/pipe2.c).  Backs
//! src/sysdep.c (exit-time stdout/stderr flush and emacs_pipe),
//! src/fileio.c (`set-binary-mode'), and src/minibuf.c / src/emacs.c
//! (binary stdin/stdout).  The FILE* functions delegate to libc
//! (ferror/fclose/__fpending) exactly like the gnulib C code; the pipe
//! and fcntl work uses raw Linux syscalls, with a libc-based fallback
//! for other systems.

const std = @import("std");
const linux = std.os.linux;
const builtin = @import("builtin");

extern fn __errno_location() *c_int;

fn getErrno() c_int {
    return __errno_location().*;
}

fn setErrno(e: c_int) void {
    __errno_location().* = e;
}

fn rcErrno(rc: usize) c_int {
    const r = @as(isize, @bitCast(rc));
    if (r < 0) {
        const e: c_int = @intCast(-r);
        setErrno(e);
        return e;
    }
    return 0;
}

// ---------------------------------------------------------------------
// close_stream (lib/close-stream.c)
// ---------------------------------------------------------------------

extern "c" fn fclose(stream: *anyopaque) c_int;
extern "c" fn ferror(stream: *anyopaque) c_int;
extern "c" fn __fpending(stream: *anyopaque) usize;

const EBADF: c_int = 9; // Linux and mingw agree

/// close_stream: close STREAM with nicer error checking than fclose.
/// Return 0 if successful, EOF (-1, errno set) otherwise; a failure may
/// set errno to 0 when the error number cannot be determined.  The
/// fclose EBADF exception (no previous error, nothing pending) matches
/// gnulib's behavior for programs run with stdout/stderr closed.
pub export fn close_stream(stream: *anyopaque) c_int {
    const some_pending = pendingBytes(stream) != 0;
    const prev_fail = ferror(stream) != 0;
    const fclose_fail = fclose(stream) != 0;

    if (prev_fail or (fclose_fail and (some_pending or getErrno() != EBADF))) {
        if (!fclose_fail)
            setErrno(0);
        return -1; // EOF
    }
    return 0;
}

fn pendingBytes(stream: *anyopaque) usize {
    if (builtin.os.tag == .linux and builtin.abi == .gnu)
        return __fpending(stream);
    // Non-glibc: there is no portable pending-byte count (gnulib's
    // fpending reaches into FILE internals per platform); treat as no
    // pending data, which only affects the closed-fd EBADF exception.
    return 0;
}

// ---------------------------------------------------------------------
// set_binary_mode (lib/binary-io.c + binary-io.h)
// ---------------------------------------------------------------------

extern "c" fn _setmode(fd: c_int, mode: c_int) c_int;

/// set_binary_mode: set FD's mode to MODE (O_BINARY or O_TEXT), return
/// the old mode or -1 (errno set) on failure.  On POSIX, binary I/O is
/// the only choice, so O_BINARY (0) is returned; on Windows this is the
/// CRT _setmode.
pub export fn set_binary_mode(fd: c_int, mode: c_int) c_int {
    if (builtin.os.tag == .windows)
        return setBinaryModeWindows(fd, mode);
    return 0; // O_BINARY on POSIX: binary I/O is the only choice
}

fn setBinaryModeWindows(fd: c_int, mode: c_int) c_int {
    return _setmode(fd, mode);
}

// ---------------------------------------------------------------------
// rpl_pipe2 (lib/pipe2.c)
// ---------------------------------------------------------------------

// Linux fcntl.h values (O_BINARY and O_TEXT are 0 on POSIX).
const O_CLOEXEC_LINUX: c_int = 0x80000;
const O_NONBLOCK_LINUX: c_int = 0x800;
const FD_CLOEXEC: c_int = 1;

const ENOSYS_LINUX: c_int = 38;
const EINVAL: c_int = 22;

// Cache whether the pipe2 syscall really exists (the kernel may lack it
// even when libc has the function); 0 = unknown, 1 = yes, -1 = no.
var have_pipe2_really: c_int = 0;

/// rpl_pipe2 (the gnulib replacement name from lib/unistd.h): create a
/// pipe with FLAGS applied.  On failure fd[0]/fd[1] are left unchanged
/// (the C code saves them across the attempt) and -1 is returned with
/// errno set.
pub export fn rpl_pipe2(fd: [*]c_int, flags: c_int) c_int {
    if (builtin.os.tag == .linux)
        return rplPipe2Linux(fd, flags);
    return rplPipe2Portable(fd, flags);
}

fn rplPipe2Linux(fd: [*]c_int, flags: c_int) c_int {
    if (have_pipe2_really >= 0) {
        const rc = linux.pipe2(@ptrCast(fd), @bitCast(@as(u32, @intCast(flags))));
        const r = @as(isize, @bitCast(rc));
        if (r >= 0) {
            have_pipe2_really = 1;
            return 0;
        }
        const e = rcErrno(rc);
        if (e != ENOSYS_LINUX) {
            have_pipe2_really = 1;
            return -1;
        }
        have_pipe2_really = -1;
    }
    return pipeFallbackLinux(fd, flags);
}

// The C code's Unix fallback: pipe(2) then apply the flags with fcntl.
fn pipeFallbackLinux(fd: [*]c_int, flags: c_int) c_int {
    const supported = O_CLOEXEC_LINUX | O_NONBLOCK_LINUX;
    if ((flags & ~supported) != 0) {
        setErrno(EINVAL);
        return -1;
    }
    const tmp0 = fd[0];
    const tmp1 = fd[1];

    var pfd: [2]c_int = undefined;
    if (rcErrno(linux.pipe(&pfd)) != 0)
        return -1;
    fd[0] = pfd[0];
    fd[1] = pfd[1];

    if ((flags & O_NONBLOCK_LINUX) != 0) {
        if (setFdFlagLinux(fd[1], linux.F.GETFL, linux.F.SETFL, O_NONBLOCK_LINUX) != 0 or
            setFdFlagLinux(fd[0], linux.F.GETFL, linux.F.SETFL, O_NONBLOCK_LINUX) != 0)
            return pipeFailRestore(fd, tmp0, tmp1);
    }
    if ((flags & O_CLOEXEC_LINUX) != 0) {
        if (setFdFlagLinux(fd[1], linux.F.GETFD, linux.F.SETFD, FD_CLOEXEC) != 0 or
            setFdFlagLinux(fd[0], linux.F.GETFD, linux.F.SETFD, FD_CLOEXEC) != 0)
            return pipeFailRestore(fd, tmp0, tmp1);
    }
    return 0;
}

fn setFdFlagLinux(fd: c_int, get_cmd: i32, set_cmd: i32, flag: c_int) c_int {
    const rc1 = linux.fcntl(fd, get_cmd, 0);
    if (rcErrno(rc1) != 0)
        return -1;
    const old: c_int = @intCast(rc1);
    if (rcErrno(linux.fcntl(fd, set_cmd, @intCast(old | flag))) != 0)
        return -1;
    return 0;
}

fn pipeFailRestore(fd: [*]c_int, tmp0: c_int, tmp1: c_int) c_int {
    const saved_errno = getErrno();
    _ = linux.close(fd[0]);
    _ = linux.close(fd[1]);
    fd[0] = tmp0;
    fd[1] = tmp1;
    setErrno(saved_errno);
    return -1;
}

// Non-Linux fallback: the same Unix algorithm via libc pipe/fcntl, with
// per-platform O_* values; Windows uses the CRT _pipe like the C code.
extern "c" fn pipe(fd: [*]c_int) c_int;
// libc fcntl is variadic (the third arg is only read for F_SETFL /
// F_SETFD); a fixed-arity extern drops the arg on Apple arm64, leaving
// the FD_CLOEXEC bit unset, so the child inherits the exec-monitor
// pipe and make-process blocks until the child exits.  Declare it
// variadic and cast the mode at every call site.
extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn _pipe(fd: [*]c_int, bufsize: c_uint, mode: c_int) c_int;

const PortableO = struct {
    nonblock: c_int,
    cloexec: c_int,
    binary: c_int,
    text: c_int,
};

fn portableO() PortableO {
    return switch (builtin.os.tag) {
        .macos, .ios, .tvos, .watchos => .{ .nonblock = 0x4, .cloexec = 0x1000000, .binary = 0, .text = 0 },
        .freebsd, .openbsd, .netbsd, .dragonfly => .{ .nonblock = 0x4, .cloexec = 0x100000, .binary = 0, .text = 0 },
        .windows => .{ .nonblock = 0x40000000, .cloexec = 0x80, .binary = 0x8000, .text = 0x4000 },
        else => .{ .nonblock = 0, .cloexec = 0, .binary = 0, .text = 0 },
    };
}

fn rplPipe2Portable(fd: [*]c_int, flags: c_int) c_int {
    const o = portableO();
    if (builtin.os.tag == .windows) {
        // Mirrors the C pipe2.c Windows path: _pipe with the binary/
        // text mode bits; gnulib's O_NONBLOCK (0x40000000) would need
        // the nonblocking module, so it is not applied.
        const tmp0 = fd[0];
        const tmp1 = fd[1];
        if (_pipe(fd, 4096, flags & ~o.nonblock) != 0) {
            fd[0] = tmp0;
            fd[1] = tmp1;
            return -1;
        }
        return 0;
    }

    const supported = o.nonblock | o.cloexec | o.binary | o.text;
    if ((flags & ~supported) != 0) {
        setErrno(EINVAL);
        return -1;
    }
    const tmp0 = fd[0];
    const tmp1 = fd[1];
    if (pipe(fd) != 0)
        return -1; // errno set by libc

    if ((flags & o.nonblock) != 0) {
        if (setFdFlagPortable(fd[1], 3, 4, o.nonblock) != 0 or // F_GETFL/F_SETFL
            setFdFlagPortable(fd[0], 3, 4, o.nonblock) != 0)
            return pipeFailRestorePortable(fd, tmp0, tmp1);
    }
    if ((flags & o.cloexec) != 0) {
        if (setFdFlagPortable(fd[1], 1, 2, 1) != 0 or // F_GETFD/F_SETFD, FD_CLOEXEC
            setFdFlagPortable(fd[0], 1, 2, 1) != 0)
            return pipeFailRestorePortable(fd, tmp0, tmp1);
    }
    return 0;
}

fn setFdFlagPortable(fd: c_int, get_cmd: c_int, set_cmd: c_int, flag: c_int) c_int {
    const old = fcntl(fd, get_cmd, @as(c_int, 0));
    if (old < 0)
        return -1;
    if (fcntl(fd, set_cmd, @as(c_int, @intCast(old | flag))) < 0)
        return -1;
    return 0;
}

fn pipeFailRestorePortable(fd: [*]c_int, tmp0: c_int, tmp1: c_int) c_int {
    const saved_errno = getErrno();
    _ = close(fd[0]);
    _ = close(fd[1]);
    fd[0] = tmp0;
    fd[1] = tmp1;
    setErrno(saved_errno);
    return -1;
}
