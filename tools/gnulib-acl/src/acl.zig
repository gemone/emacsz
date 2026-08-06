//! Native Zig implementation of gnulib's ACL copying for Emacs
//! (lib/qcopy-acl.c under USE_XATTR), backing `Fcopy_file' with
//! preserve-permissions in src/fileio.c.
//!
//! The C chain is replicated with no libc call on Linux: the mode bits
//! are set with a raw chmod/fchmod syscall, then the ACL extended
//! attributes are copied with the same semantics as libattr's
//! attr_copy_file / attr_copy_fd (llistxattr/lgetxattr/lsetxattr,
//! flistxattr/fgetxattr/fsetxattr), filtered by the same
//! is_attr_permissions callback (hardcoded ACL names plus the
//! /etc/xattr.conf `permissions' actions, matched with fnmatch).  The
//! libattr error_context is passed as NULL by qcopy_acl, so all error
//! reporting is silent and only the return value plus errno matter.
//!
//! The EOPNOTSUPP fallback (Bug#78328) is also ported: when the copy
//! fails with EOPNOTSUPP and the source turns out to have no nontrivial
//! ACL (fdfile_has_aclinfo, the USE_LINUX_XATTR path of lib/file-has-acl.c),
//! the chmod_or_fchmod above suffices and no error is reported.
//!
//! Non-Linux targets fall back to mode-bit preservation via libc
//! chmod/fchmod (on Windows fchmod is emulated through the CRT handle
//! and SetFileInformationByHandle, since mingw has no fchmod); xattr
//! ACL copying is Linux-only for now.

const std = @import("std");
const linux = std.os.linux;
const builtin = @import("builtin");

extern fn __errno_location() *c_int;

fn setErrno(e: c_int) void {
    __errno_location().* = e;
}

fn getErrno() c_int {
    return __errno_location().*;
}

/// Convert a raw syscall return value (negative errno when failed) into
/// the C errno: set errno on failure and return it; return 0 on success.
inline fn rcErrno(rc: usize) c_int {
    const r = @as(isize, @bitCast(rc));
    if (r < 0) {
        const e: c_int = @intCast(-r);
        setErrno(e);
        return e;
    }
    return 0;
}

// errno values used by the ACL code (Linux values; the package runs on
// Linux, where ENOTSUP == EOPNOTSUPP).
const ENOSYS: c_int = @intFromEnum(linux.E.NOSYS);
const EOPNOTSUPP: c_int = @intFromEnum(linux.E.OPNOTSUPP);
const ERANGE: c_int = @intFromEnum(linux.E.RANGE);
const EACCES: c_int = @intFromEnum(linux.E.ACCES);
const E2BIG: c_int = @intFromEnum(linux.E.@"2BIG");
const EINVAL: c_int = @intFromEnum(linux.E.INVAL);
const ENODATA: c_int = @intFromEnum(linux.E.NODATA);
const ENOENT: c_int = @intFromEnum(linux.E.NOENT);
const EBUSY: c_int = @intFromEnum(linux.E.BUSY);

const XATTR_NAME_POSIX_ACL_ACCESS: [:0]const u8 = "system.posix_acl_access";
const XATTR_NAME_POSIX_ACL_DEFAULT: [:0]const u8 = "system.posix_acl_default";
const XATTR_NAME_NFSV4_ACL: [:0]const u8 = "system.nfs4_acl";

const ATTR_ACTION_SKIP: c_int = 1;
const ATTR_ACTION_PERMISSIONS: c_int = 2;

const XATTR_CONF = "/etc/xattr.conf";

// Linux <dirent.h> d_type values and gnulib's _GL_DT_NOTDIR bit.
const DT_UNKNOWN: u32 = 0;
const DT_DIR: u32 = 4;
const GL_DT_NOTDIR: u32 = 0x100;

// acl.h ACL_GET_SCONTEXT / ACL_SYMLINK_FOLLOW flags; only the follow
// bit is ever set by qcopy_acl.
const ACL_SYMLINK_FOLLOW: c_int = 0x20000;

const SSIZE_MAX: usize = std.math.maxInt(isize);

const mode_t = u32;

/// qcopy_acl (lib/qcopy-acl.c).  Copy access control lists from one file
/// to another; MODE should be the source file's st_mode.  If SOURCE_DESC
/// is a valid file descriptor use fd-based operations, else use
/// filename-based operations on SRC_NAME; likewise for DEST_DESC and
/// DST_NAME.  Return 0 if successful, -2 (errno set) for a source error,
/// -1 (errno set) for a destination error.
pub export fn qcopy_acl(
    src_name: [*:0]const u8,
    source_desc: c_int,
    dst_name: [*:0]const u8,
    dest_desc: c_int,
    mode: mode_t,
) c_int {
    if (builtin.os.tag == .linux)
        return qcopyAclLinux(src_name, source_desc, dst_name, dest_desc, mode);

    // Non-Linux: no xattr ACL support; set the mode bits only (gnulib's
    // non-XATTR path reduces to chmod_or_fchmod when the source has no
    // ACLs).  Uses libc chmod/fchmod; errno is set by libc.  On Windows
    // the fd variant goes through the CRT (mingw lacks fchmod).
    if (dest_desc != -1)
        return if (comptime builtin.os.tag == .windows)
            fchmodWindows(dest_desc, mode)
        else
            fchmod(dest_desc, mode);
    return chmod(dst_name, mode);
}

extern "c" fn chmod(path: [*:0]const u8, mode: mode_t) c_int;
extern "c" fn fchmod(fd: c_int, mode: mode_t) c_int;

// Windows fchmod emulation: the CRT _get_osfhandle plus
// SetFileInformationByHandle(FILE_BASIC_INFO), toggling the read-only
// attribute exactly as _chmod does for a path.
extern "c" fn _get_osfhandle(fd: c_int) ?*anyopaque;
extern "c" fn SetFileInformationByHandle(
    h: ?*anyopaque,
    class: u32,
    info: *anyopaque,
    len: u32,
) c_int;
extern "c" fn _errno() *c_int;

const FileBasicInfo = extern struct {
    creation_time: i64,
    last_access_time: i64,
    last_write_time: i64,
    change_time: i64,
    file_attributes: u32,
    pad: u32,
};

const FileBasicInfoClass: u32 = 0; // FileBasicInfo
const FILE_ATTRIBUTE_READONLY: u32 = 0x1;

fn fchmodWindows(fd: c_int, mode: mode_t) c_int {
    const h = _get_osfhandle(fd);
    const invalid: ?*anyopaque = @ptrFromInt(~@as(usize, 0));
    if (h == invalid)
        return -1; // CRT set errno
    var info: FileBasicInfo = undefined;
    if (SetFileInformationByHandle(h, FileBasicInfoClass, &info, @sizeOf(FileBasicInfo)) == 0) {
        _errno().* = EINVAL;
        return -1;
    }
    if (mode & 0o222 != 0)
        info.file_attributes &= ~FILE_ATTRIBUTE_READONLY
    else
        info.file_attributes |= FILE_ATTRIBUTE_READONLY;
    if (SetFileInformationByHandle(h, FileBasicInfoClass, &info, @sizeOf(FileBasicInfo)) == 0) {
        _errno().* = EINVAL;
        return -1;
    }
    return 0;
}

fn qcopyAclLinux(
    src_name: [*:0]const u8,
    source_desc: c_int,
    dst_name: [*:0]const u8,
    dest_desc: c_int,
    mode: mode_t,
) c_int {
    // chmod first (also sets S_ISUID/S_ISGID/S_ISVTX); setting ACLs
    // afterwards would otherwise clobber the mode bits (the POSIX ACL
    // "mask" hack and NFSv4 alike).
    var ret = chmodOrFchmod(dst_name, dest_desc, mode);
    if (ret == 0) {
        ret = if (source_desc <= 0 or dest_desc <= 0)
            attrCopyFile(src_name, dst_name)
        else
            attrCopyFd(src_name, source_desc, dst_name, dest_desc);

        // Copying can fail with EOPNOTSUPP even when the source
        // permissions are trivial (Bug#78328).  Don't report an error
        // in this case, as the chmod_or_fchmod suffices.
        if (ret < 0 and getErrno() == EOPNOTSUPP) {
            const flags: c_int = if (isDirMode(mode))
                @intCast(DT_DIR)
            else
                @intCast(GL_DT_NOTDIR | DT_UNKNOWN);
            if (fileHasAcl(source_desc, src_name, flags) == 0)
                ret = 0;
            setErrno(EOPNOTSUPP);
        }
    }
    return ret;
}

fn isDirMode(mode: mode_t) bool {
    return (mode & 0o170000) == 0o040000;
}

// chmod_or_fchmod from lib/set-permissions.c: fchmod(2) on a valid
// descriptor, chmod(2) otherwise.
fn chmodOrFchmod(name: [*:0]const u8, desc: c_int, mode: mode_t) c_int {
    const rc = if (desc != -1)
        linux.fchmod(desc, mode)
    else
        linux.chmod(name, mode);
    return if (rcErrno(rc) != 0) -1 else 0;
}

/// attr_copy_file from libattr (attr-2.5.2, libattr/attr_copy_file.c)
/// with qcopy_acl's is_attr_permissions callback and a NULL error
/// context (so all error reporting is a no-op).  Copies the ACL-related
/// extended attributes from SRC_PATH to DST_PATH with l* syscalls.
fn attrCopyFile(src_path: [*:0]const u8, dst_path: [*:0]const u8) c_int {
    return attrCopyImpl(
        src_path,
        dst_path,
        null,
        null,
    );
}

/// attr_copy_fd from libattr (libattr/attr_copy_fd.c), same callback and
/// silent error context; uses the f* syscalls on SRC_FD and DST_FD.
fn attrCopyFd(
    src_path: [*:0]const u8,
    src_fd: c_int,
    dst_path: [*:0]const u8,
    dst_fd: c_int,
) c_int {
    return attrCopyImpl(src_path, dst_path, src_fd, dst_fd);
}

// Dispatch on whether the fd variant is requested; implemented as two
// separate loops below for clarity (mirroring the two libattr files).
fn attrCopyImpl(
    src_path: [*:0]const u8,
    dst_path: [*:0]const u8,
    src_fd: ?c_int,
    dst_fd: ?c_int,
) c_int {
    const alloc = std.heap.page_allocator;
    var ret: c_int = 0;
    var setxattr_enotsup: c_uint = 0;

    var dummy: [1]u8 = .{0};
    var size_rc: usize = undefined;
    if (src_fd) |sfd| {
        size_rc = linux.flistxattr(sfd, &dummy, 0);
    } else {
        size_rc = linux.llistxattr(src_path, &dummy, 0);
    }
    var size = @as(isize, @bitCast(size_rc));
    if (size < 0) {
        const e = rcErrno(size_rc);
        // ENOSYS / ENOTSUP mean xattrs are unsupported: not an error.
        if (e != ENOSYS and e != EOPNOTSUPP)
            ret = -1;
        return ret;
    }

    const nsize: usize = @intCast(size);
    var names_buf = alloc.alloc(u8, nsize + 1) catch return -1;
    defer alloc.free(names_buf);

    if (src_fd) |sfd| {
        size_rc = linux.flistxattr(sfd, names_buf.ptr, names_buf.len);
    } else {
        size_rc = linux.llistxattr(src_path, names_buf.ptr, names_buf.len);
    }
    size = @as(isize, @bitCast(size_rc));
    if (size < 0) {
        _ = rcErrno(size_rc);
        return -1;
    }
    const end: usize = @intCast(size);
    names_buf[end] = 0;

    var value_buf: ?[]u8 = null;
    defer if (value_buf) |vb| alloc.free(vb);

    var pos: usize = 0;
    while (pos < end) {
        const name_start = pos;
        while (pos < end and names_buf[pos] != 0) pos += 1;
        const name = names_buf[name_start..pos];
        const next_pos = pos + 1;
        if (name.len == 0 or !isAttrPermissions(name)) {
            pos = next_pos;
            continue;
        }
        const name_z: [*:0]const u8 = @ptrCast(names_buf[name_start..].ptr);

        // Query the value size, then fetch it (libattr reallocs the
        // value buffer per attribute; we allocate fresh each time).
        if (src_fd) |sfd| {
            size_rc = linux.fgetxattr(sfd, name_z, &dummy, 0);
        } else {
            size_rc = linux.lgetxattr(src_path, name_z, &dummy, 0);
        }
        size = @as(isize, @bitCast(size_rc));
        if (size < 0) {
            _ = rcErrno(size_rc);
            ret = -1;
            pos = next_pos;
            continue;
        }
        const vsize: usize = @intCast(size);
        var vp: [*]u8 = &dummy;
        if (vsize != 0) {
            const nb = alloc.alloc(u8, vsize) catch {
                ret = -1;
                pos = next_pos;
                continue;
            };
            if (value_buf) |vb| alloc.free(vb);
            value_buf = nb;
            vp = nb.ptr;
        }
        if (src_fd) |sfd| {
            size_rc = linux.fgetxattr(sfd, name_z, vp, vsize);
        } else {
            size_rc = linux.lgetxattr(src_path, name_z, vp, vsize);
        }
        size = @as(isize, @bitCast(size_rc));
        if (size < 0) {
            _ = rcErrno(size_rc);
            ret = -1;
            pos = next_pos;
            continue;
        }

        const set_rc = if (dst_fd) |dfd|
            linux.fsetxattr(dfd, name_z, vp, vsize, 0)
        else
            linux.lsetxattr(dst_path, name_z, vp, vsize, 0);
        if (@as(isize, @bitCast(set_rc)) != 0) {
            const e = rcErrno(set_rc);
            if (e == EOPNOTSUPP) {
                setxattr_enotsup += 1;
            } else if (e == ENOSYS) {
                // No hope of getting any further.
                ret = -1;
                break;
            } else {
                ret = -1;
            }
        }
        pos = next_pos;
    }

    if (setxattr_enotsup != 0) {
        setErrno(EOPNOTSUPP);
        ret = -1;
    }
    return ret;
}

/// is_attr_permissions from lib/qcopy-acl.c: true for the known ACL
/// extended-attribute names, or for names whose /etc/xattr.conf action
/// is `permissions'.  (attr_copy_action is also what libattr consults;
/// on CentOS 7 it did not classify the ACL names, hence the explicit
/// tests.)
fn isAttrPermissions(name: []const u8) bool {
    return std.mem.eql(u8, name, XATTR_NAME_POSIX_ACL_ACCESS) or
        std.mem.eql(u8, name, XATTR_NAME_POSIX_ACL_DEFAULT) or
        std.mem.eql(u8, name, XATTR_NAME_NFSV4_ACL) or
        attrCopyAction(name) == ATTR_ACTION_PERMISSIONS;
}

/// attr_copy_action from libattr (libattr/attr_copy_action.c): the
/// configured action for NAME from /etc/xattr.conf (0 when unlisted or
/// the file is unreadable/unparsable).
var attr_actions: ?*AttrAction = null;

const AttrAction = struct {
    pattern: []u8,
    action: c_int,
    next: ?*AttrAction,
};

fn attrCopyAction(name: []const u8) c_int {
    if (attr_actions == null) {
        const alloc = std.heap.page_allocator;
        const text = readXattrConf(alloc) orelse return 0;
        defer alloc.free(text);
        attr_actions = parseXattrConf(text, alloc);
    }
    var node = attr_actions;
    while (node) |n| : (node = n.next) {
        if (fnmatchPattern(n.pattern, name))
            return n.action;
    }
    return 0;
}

/// Read the whole of /etc/xattr.conf; null on failure (errno set).  The
/// C code reads with a doubling buffer and re-reads until EOF, which is
/// equivalent for a static config file.
fn readXattrConf(alloc: std.mem.Allocator) ?[]u8 {
    const fd_rc = linux.openat(linux.AT.FDCWD, XATTR_CONF, .{}, 0);
    const fd_s = @as(isize, @bitCast(fd_rc));
    if (fd_s < 0) {
        setErrno(@intCast(-fd_s));
        return null;
    }
    const fd: i32 = @intCast(fd_s);
    defer _ = linux.close(fd);

    var buf = alloc.alloc(u8, 4096) catch return null;
    defer alloc.free(buf);
    var total: usize = 0;
    while (true) {
        if (total == buf.len) {
            buf = alloc.realloc(buf, buf.len * 2) catch return null;
        }
        const rc = linux.read(fd, buf.ptr + total, buf.len - total);
        const n = @as(isize, @bitCast(rc));
        if (n < 0) {
            setErrno(@intCast(-n));
            return null;
        }
        if (n == 0)
            return alloc.dupe(u8, buf[0..total]) catch null;
        total += @intCast(n);
    }
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n';
}

/// Parse /etc/xattr.conf, replicating libattr's attr_parse_attr_conf
/// (lines are "<pattern> <skip|permissions>", '#' comments, blank lines
/// are errors).  Returns the action list (head) or null on a parse
/// error; the list is cached in static state by attrCopyAction.
fn parseXattrConf(text: []const u8, alloc: std.mem.Allocator) ?*AttrAction {
    var head: ?*AttrAction = null;
    var t: usize = 0;
    while (true) {
        while (t < text.len and isSpace(text[t])) t += 1;

        // len = strcspn(t, " \t\n#")
        var len = t;
        while (len < text.len and !isSpace(text[len]) and text[len] != '#') len += 1;

        if (len < text.len and text[len] == '#') {
            // A comment must start the line; otherwise parse error.
            if (len != t) return failParse(head, alloc);
            while (t < text.len and text[t] != '\n') t += 1;
            continue;
        }
        if (len == text.len) break; // EOF
        if (text[len] == '\n') return failParse(head, alloc); // blank line

        const pattern = alloc.dupe(u8, text[t..len]) catch return failParse(head, alloc);
        t = len;
        while (t < text.len and (text[t] == ' ' or text[t] == '\t')) t += 1;

        len = t;
        while (len < text.len and !isSpace(text[len]) and text[len] != '#') len += 1;
        const action: c_int = if (len - t == 4 and std.mem.eql(u8, text[t..len], "skip"))
            ATTR_ACTION_SKIP
        else if (len - t == 11 and std.mem.eql(u8, text[t..len], "permissions"))
            ATTR_ACTION_PERMISSIONS
        else {
            alloc.free(pattern);
            return failParse(head, alloc);
        };
        t = len;
        while (t < text.len and (text[t] == ' ' or text[t] == '\t')) t += 1;
        if (t == text.len or (text[t] != '#' and text[t] != '\n')) {
            alloc.free(pattern);
            return failParse(head, alloc);
        }

        const node = alloc.create(AttrAction) catch {
            alloc.free(pattern);
            return failParse(head, alloc);
        };
        node.* = .{ .pattern = pattern, .action = action, .next = head };
        head = node;

        while (t < text.len and text[t] != '\n') t += 1;
    }
    return head;
}

fn failParse(head: ?*AttrAction, alloc: std.mem.Allocator) ?*AttrAction {
    var node = head;
    while (node) |n| {
        const next = n.next;
        alloc.free(n.pattern);
        alloc.destroy(n);
        node = next;
    }
    return null;
}

/// POSIX fnmatch (flags 0) restricted to what /etc/xattr.conf uses:
/// '*' and '?' wildcards and [...] bracket expressions, with backslash
/// escapes.  Since FNM_PATHNAME and FNM_PERIOD are not set, '*' matches
/// '/' too and a leading '.' is not special.
fn fnmatchPattern(pattern: []const u8, name: []const u8) bool {
    var p: usize = 0;
    var s: usize = 0;
    while (p < pattern.len) {
        const c = pattern[p];
        if (c == '*') {
            while (p < pattern.len and pattern[p] == '*') p += 1;
            if (p == pattern.len) return true;
            var k = s;
            while (k <= name.len) : (k += 1) {
                if (fnmatchPattern(pattern[p..], name[k..])) return true;
            }
            return false;
        } else if (c == '?') {
            if (s >= name.len) return false;
            p += 1;
            s += 1;
        } else if (c == '[') {
            if (s >= name.len) return false;
            var j = p + 1;
            var negate = false;
            if (j < pattern.len and (pattern[j] == '!' or pattern[j] == '^')) {
                negate = true;
                j += 1;
            }
            var matched = false;
            var first = true;
            while (j < pattern.len and (pattern[j] != ']' or first)) {
                first = false;
                if (j + 2 < pattern.len and pattern[j + 1] == '-' and pattern[j + 2] != ']') {
                    if (name[s] >= pattern[j] and name[s] <= pattern[j + 2])
                        matched = true;
                    j += 3;
                } else {
                    if (pattern[j] == name[s]) matched = true;
                    j += 1;
                }
            }
            if (j >= pattern.len) return false; // unterminated bracket
            p = j + 1;
            s += 1;
            if (matched == negate) return false;
        } else {
            if (s >= name.len or pattern[p] != name[s]) return false;
            p += 1;
            s += 1;
        }
    }
    return s == name.len;
}

// ---------------------------------------------------------------------
// fdfile_has_aclinfo (USE_LINUX_XATTR path of lib/file-has-acl.c),
// reduced to what qcopy_acl's EOPNOTSUPP diagnostic needs.  The
// scontext parts are unreachable (qcopy_acl never sets ACL_GET_SCONTEXT)
// and are omitted.
// ---------------------------------------------------------------------

const AclInfo = struct {
    // Small array big enough for most listxattr results (the C code's
    // aclinfo.u._gl_acl_ch); must live inside the struct so the pointer
    // stays valid across calls, exactly like the C layout.
    small: [152]u8,
    buf: []u8,
    size: isize,
    err: c_int,
    heap: ?[]u8,
};

/// Return 1 if FD aka NAME has a nontrivial ACL, 0 if ACLs are not
/// supported or NAME has no/base ACL only, -1 (errno set) on error.
pub fn fileHasAcl(fd: c_int, name: [*:0]const u8, flags: c_int) c_int {
    const initial_errno = getErrno();
    var info: AclInfo = undefined;
    getAclInfo(fd, name, flags, &info);
    defer if (info.heap) |hb| std.heap.page_allocator.free(hb);

    if (!(info.size < 0 and
        (!aclErrnoValid(info.err) or info.err == EACCES or info.err == E2BIG)) and
        info.size <= 0)
    {
        setErrno(if (info.size < 0) info.err else initial_errno);
        return @intCast(info.size);
    }

    // An NFSv4 ACL wins over POSIX ACLs when both are present.
    if (!hasXattr(fd, name, flags, &info, XATTR_NAME_NFSV4_ACL)) {
        const d_type: u32 = @as(u32, @bitCast(flags)) & 0xff;
        return @intFromBool(
            hasXattr(fd, name, flags, &info, XATTR_NAME_POSIX_ACL_ACCESS) or
                ((d_type == DT_DIR or d_type == DT_UNKNOWN) and
                    hasXattr(fd, name, flags, &info, XATTR_NAME_POSIX_ACL_DEFAULT)),
        );
    }

    // A buffer large enough for any trivial NFSv4 ACL (see the C code:
    // 2 * (6 + 6 + 7) words).
    var nfs4: [38]u32 = undefined;
    const rc = if (fd < 0)
        (if ((flags & ACL_SYMLINK_FOLLOW) != 0)
            linux.getxattr(name, XATTR_NAME_NFSV4_ACL, @ptrCast(&nfs4), @sizeOf(@TypeOf(nfs4)))
        else
            linux.lgetxattr(name, XATTR_NAME_NFSV4_ACL, @ptrCast(&nfs4), @sizeOf(@TypeOf(nfs4))))
    else
        linux.fgetxattr(fd, XATTR_NAME_NFSV4_ACL, @ptrCast(&nfs4), @sizeOf(@TypeOf(nfs4)));
    const ret = @as(isize, @bitCast(rc));
    if (ret < 0) {
        const e = rcErrno(rc);
        return switch (e) {
            ENODATA => 0,
            ERANGE => 1, // ACL must be nontrivial
            else => -@as(c_int, @intFromBool(aclErrnoValid(e))),
        };
    }

    // It looks like a trivial ACL; investigate further.
    const bytes = std.mem.asBytes(&nfs4)[0..@intCast(ret)];
    const nontrivial = aclNfs4Nontrivial(bytes);
    setErrno(if (nontrivial < 0) EINVAL else initial_errno);
    return nontrivial;
}

/// get_aclinfo from lib/file-has-acl.c: list the xattrs into a buffer
/// starting at 152 bytes, growing (1.5x, at least the needed size) on
/// ERANGE.  A security context is never requested by qcopy_acl, so the
/// scontext fields are omitted.
fn getAclInfo(fd: c_int, name: [*:0]const u8, flags: c_int, info: *AclInfo) void {
    info.buf = info.small[0..];
    info.heap = null;
    var acl_alloc: usize = info.small.len;
    const follow = (flags & ACL_SYMLINK_FOLLOW) != 0;
    var dummy: [1]u8 = .{0};

    while (true) {
        const rc = if (fd < 0)
            (if (follow)
                linux.listxattr(name, info.buf.ptr, info.buf.len)
            else
                linux.llistxattr(name, info.buf.ptr, info.buf.len))
        else
            linux.flistxattr(fd, info.buf.ptr, info.buf.len);
        const sz = @as(isize, @bitCast(rc));
        if (sz > 0) {
            info.size = sz;
            return;
        }
        info.err = if (sz < 0) @intCast(-sz) else 0;
        if (!(sz < 0 and info.err == ERANGE and acl_alloc < SSIZE_MAX)) {
            info.size = sz;
            return;
        }

        // The buffer was too small; find how large it should have been.
        const rc2 = if (fd < 0)
            (if (follow)
                linux.listxattr(name, &dummy, 0)
            else
                linux.llistxattr(name, &dummy, 0))
        else
            linux.flistxattr(fd, &dummy, 0);
        const sz2 = @as(isize, @bitCast(rc2));
        if (sz2 <= 0) {
            info.size = sz2;
            info.err = if (sz2 < 0) @intCast(-sz2) else 0;
            return;
        }

        // Grow by a nontrivial amount, defending against an adversary
        // that fiddles with ACLs (ckd_add semantics: saturate).
        if (info.heap) |hb| std.heap.page_allocator.free(hb);
        info.heap = null;
        info.buf = info.small[0..];
        acl_alloc = std.math.add(usize, acl_alloc, acl_alloc >> 1) catch SSIZE_MAX;
        if (acl_alloc < @as(usize, @intCast(sz2)))
            acl_alloc = @intCast(sz2);
        const nb = std.heap.page_allocator.alloc(u8, acl_alloc) catch {
            info.size = sz;
            info.err = getErrno();
            return;
        };
        info.heap = nb;
        info.buf = nb;
    }
}

/// aclinfo_has_xattr + has_xattr from lib/file-has-acl.c: whether the
/// listed xattrs contain XATTR, falling back to a direct getxattr probe
/// when the list itself was inconclusive (E2BIG / EACCES / unsupported).
fn hasXattr(
    fd: c_int,
    name: [*:0]const u8,
    flags: c_int,
    info: *const AclInfo,
    xattr: [:0]const u8,
) bool {
    if (aclinfoHasXattr(info, xattr))
        return true;
    if (info.size < 0 and
        (!aclErrnoValid(info.err) or info.err == EACCES or info.err == E2BIG))
    {
        var dummy: [1]u8 = .{0};
        const rc = if (fd < 0)
            (if ((flags & ACL_SYMLINK_FOLLOW) != 0)
                linux.getxattr(name, xattr, &dummy, 0)
            else
                linux.lgetxattr(name, xattr, &dummy, 0))
        else
            linux.fgetxattr(fd, xattr, &dummy, 0);
        if (@as(isize, @bitCast(rc)) >= 0) return true;
        const e = rcErrno(rc);
        if (e == ERANGE or e == E2BIG) return true;
    }
    return false;
}

fn aclinfoHasXattr(info: *const AclInfo, xattr: []const u8) bool {
    if (info.size > 0) {
        const blim: usize = @intCast(info.size);
        var b: usize = 0;
        while (b < blim) {
            var e = b;
            while (e < blim and info.buf[e] != 0) e += 1;
            if (e - b == xattr.len and std.mem.eql(u8, info.buf[b..e], xattr))
                return true;
            b = e + 1;
        }
    }
    return false;
}

/// acl_errno_valid from lib/acl-errno-valid.c: whether an errno from an
/// ACL-related syscall indicates ACLs are well supported here.
pub export fn acl_errno_valid(errnum: c_int) bool {
    return switch (errnum) {
        EBUSY, EINVAL, ENOSYS, EOPNOTSUPP => false,
        else => true,
    };
}

fn aclErrnoValid(errnum: c_int) bool {
    return acl_errno_valid(errnum);
}

const ACE4_ACCESS_DENIED_ACE_TYPE: u32 = 1;
const ACE4_IDENTIFIER_GROUP: u32 = 0x40;

/// acl_nfs4_nontrivial from lib/file-has-acl.c: whether an XDR-format
/// NFSv4 ACL is nontrivial.  Trivial ACLs have at most one allow and
/// one deny ACE for each of OWNER@ / GROUP@ / EVERYONE@.
fn aclNfs4Nontrivial(bytes: []const u8) c_int {
    var off: usize = 0;
    if (bytes.len < 4) return -1;
    const num_aces = be32At(bytes, off);
    off = 4;
    if (num_aces > 6) return 1;

    var ace_found: u32 = 0;
    var ace_n: u32 = 0;
    while (ace_n < num_aces) : (ace_n += 1) {
        if (bytes.len - off < 16) return -1;
        const ace_type = be32At(bytes, off);
        const ace_flag = be32At(bytes, off + 4);
        const wholen = be32At(bytes, off + 12);
        off += 16;
        const whowords: usize = wholen / 4 + @intFromBool(wholen % 4 != 0);
        const wholen4: usize = whowords * 4;

        // Trivial ACLs have only ACE4_ACCESS_ALLOWED_ACE_TYPE or
        // ACE4_ACCESS_DENIED_ACE_TYPE.
        if (ace_type > ACE4_ACCESS_DENIED_ACE_TYPE) return 1;

        // RFC 7530 says FLAG should be 0, but be generous to NetApp and
        // also accept the group flag.
        if (ace_flag & ~ACE4_IDENTIFIER_GROUP != 0) return 1;

        if (bytes.len - off < wholen4) return -1;
        var who2: c_int = -1;
        if (wholen == 6 and std.mem.eql(u8, bytes[off..][0..6], "OWNER@"))
            who2 = 0
        else if (wholen == 6 and std.mem.eql(u8, bytes[off..][0..6], "GROUP@"))
            who2 = 2
        else if (wholen == 9 and std.mem.eql(u8, bytes[off..][0..9], "EVERYONE@"))
            who2 = 4;
        if (who2 < 0) return 1;

        const shift: u5 = @intCast(@as(u32, @intCast(who2)) | ace_type);
        const ace_found_bit: u32 = @as(u32, 1) << shift;
        if (ace_found & ace_found_bit != 0) return 1;
        ace_found |= ace_found_bit;
        off += whowords * 4;
    }
    return 0;
}

fn be32At(bytes: []const u8, off: usize) u32 {
    const p: *const [4]u8 = @ptrCast(bytes.ptr + off);
    return std.mem.readInt(u32, p, .big);
}
