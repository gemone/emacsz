//! Native Zig implementation of gnulib's time zone management
//! (lib/time_rz.c, the !HAVE_TZALLOC path): tzalloc / tzfree /
//! set_tz / revert_tz / localtime_rz / mktime_z on top of libc's own
//! TZ machinery.  Backs src/timefns.c (`format-time-string' with a
//! time zone, `encode-time', decode-time) and lib/strftime.c's
//! %Z handling.
//!
//! The C module is itself a thin layer over libc (tzset,
//! localtime_r/gmtime_r, mktime/timegm) plus Emacs's own TZ
//! environment getter/setter (src/timefns.c emacs_getenv_TZ /
//! emacs_setenv_TZ, wired in via conf_post.h's getenv_TZ/setenv_TZ
//! macros); the port replicates it exactly, including the struct-tm_zone
//! abbreviation cache that keeps tm_zone pointers alive across the TZ
//! swap.  The timezone_t handle is opaque to all C callers
//! (src/timefns.c, lib/strftime.c), so the Zig-side layout is private.
//! libc calls remain (the TZ database parsing lives in libc's tzset),
//! matching gnulib's own design; the gnulib C module is replaced, not
//! the libc dependency.
//!
//! Like the C code, this is not thread-safe; races are rare and benign
//! (Emacs manages its own environment for TZ).

const std = @import("std");
const builtin = @import("builtin");

extern fn __errno_location() *c_int;

fn getErrno() c_int {
    return __errno_location().*;
}

fn setErrno(e: c_int) void {
    __errno_location().* = e;
}

const ENOMEM: c_int = 12;

// Emacs manages its own TZ environment buffer (src/timefns.c); the
// getter/setter are the same ones the C time_rz.c calls via conf_post.h.
extern "c" fn emacs_getenv_TZ() ?[*:0]const u8;
extern "c" fn emacs_setenv_TZ(tz: ?[*:0]const u8) c_int;

// libc TZ machinery (present on glibc and mingw-w64).
extern "c" fn tzset() void;
extern "c" fn localtime_r(t: *const time_t, tm: *Tm) ?*Tm;
extern "c" fn gmtime_r(t: *const time_t, tm: *Tm) ?*Tm;
extern "c" fn mktime(tm: *Tm) time_t;
extern "c" fn timegm(tm: *Tm) time_t;

const time_t = i64;

// struct tm as defined by the platform C library (glibc / mingw-w64).
// tm_gmtoff is `long`, whose width follows the target ABI (c_long).
pub const Tm = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
    tm_gmtoff: c_long,
    tm_zone: ?[*:0]const u8,
};

comptime {
    if (builtin.os.tag == .linux and builtin.cpu.arch == .x86_64) {
        if (@sizeOf(Tm) != 56 or @offsetOf(Tm, "tm_gmtoff") != 40 or
            @offsetOf(Tm, "tm_zone") != 48)
            @compileError("struct tm layout mismatch (x86_64 glibc)");
    }
}

// The private time zone representation (the C struct tm_zone): a chain
// of nodes each holding a packed sequence of NUL-terminated
// abbreviations (the first being the TZ environment value when
// tz_is_set).  timezone_t is opaque to C callers.
const TmZone = struct {
    next: ?*TmZone,
    tz_is_set: bool,
    abbrs: []u8,
};

// Sentinel "local time" timezone_t returned by set_tz when the current
// environment already matches (the C code returns the magic
// ((timezone_t) 1) cookie from lib/time-internal.h).  No C caller
// compares set_tz's return value against that magic constant -- only
// revert_tz (and tzfree) consume it -- so a static sentinel address is
// behaviorally identical and avoids Zig's unaligned-pointer rules.
var local_sentinel: TmZone = .{ .next = null, .tz_is_set = false, .abbrs = &.{} };

fn localTzPtr() ?*TmZone {
    return &local_sentinel;
}

pub fn isLocalTz(tz: ?*TmZone) bool {
    return tz == &local_sentinel;
}

// The approximate size to use for small allocation requests: the
// largest "small" request for the GNU C library malloc, minus the
// struct tm_zone header (lib/time_rz.c ABBR_SIZE_MIN = 128 - 16).
const ABBR_SIZE_MIN: usize = 112;

fn strlen(s: [*:0]const u8) usize {
    var n: usize = 0;
    while (s[n] != 0) n += 1;
    return n;
}

fn streq(a: [*:0]const u8, b: [*:0]const u8) bool {
    var i: usize = 0;
    while (a[i] == b[i] and a[i] != 0) i += 1;
    return a[i] == b[i];
}

/// tzalloc from lib/time_rz.c: a newly allocated time zone for NAME
/// (NULL for wall clock time, i.e. unset TZ).
pub export fn tzalloc(name: ?[*:0]const u8) ?*TmZone {
    const alloc = std.heap.page_allocator;
    const name_size = if (name) |n| strlen(n) + 1 else 0;
    const abbr_size: usize = if (name_size < ABBR_SIZE_MIN) ABBR_SIZE_MIN else name_size + 1;

    const tz = alloc.create(TmZone) catch {
        setErrno(ENOMEM);
        return null;
    };
    const buf = alloc.alloc(u8, abbr_size) catch {
        alloc.destroy(tz);
        setErrno(ENOMEM);
        return null;
    };
    tz.* = .{ .next = null, .tz_is_set = name != null, .abbrs = buf };
    if (name) |n| {
        @memcpy(buf[0..name_size], n[0..name_size]);
        buf[name_size] = 0; // extra null marks the end of the packed strings
    } else {
        buf[0] = 0;
    }
    return tz;
}

/// tzfree from lib/time_rz.c.  The magic local_tz cookie is not freed.
pub export fn tzfree(tz: ?*TmZone) void {
    if (tz == null or isLocalTz(tz)) return;
    const alloc = std.heap.page_allocator;
    var node = tz;
    while (node) |n| {
        const next = n.next;
        alloc.free(n.abbrs);
        alloc.destroy(n);
        node = next;
    }
}

// getenv_TZ / setenv_TZ from lib/time_rz.c (renamed by conf_post.h to
// Emacs's own getter and setter).
fn getenvTZ() ?[*:0]const u8 {
    return emacs_getenv_TZ();
}

fn setenvTZ(tz: ?[*:0]const u8) c_int {
    return emacs_setenv_TZ(tz);
}

/// change_env from lib/time_rz.c: set the environment to match TZ and
/// refresh libc's time zone state.
fn changeEnv(tz: *TmZone) bool {
    if (setenvTZ(if (tz.tz_is_set) @ptrCast(tz.abbrs.ptr) else null) != 0)
        return false;
    tzset();
    return true;
}

/// set_tz from lib/time_rz.c: temporarily switch the time zone to TZ.
/// Returns the magic local_tz when the setting is already current, or a
/// newly allocated zone holding the old setting (pass to revert_tz).
pub export fn set_tz(tz: ?*TmZone) ?*TmZone {
    const env_tz = getenvTZ();
    const tz_is_set = if (tz) |t| t.tz_is_set else false;
    const matches = if (env_tz) |env|
        tz_is_set and streq(@ptrCast(tz.?.abbrs.ptr), env)
    else
        !tz_is_set;
    if (matches) return localTzPtr();

    const old_tz = tzalloc(env_tz) orelse return null;
    if (!changeEnv(tz.?)) {
        tzfree(old_tz);
        return null;
    }
    return old_tz;
}

/// revert_tz from lib/time_rz.c: restore the setting returned by
/// set_tz.  Preserves errno on success.
pub export fn revert_tz(tz: ?*TmZone) bool {
    if (isLocalTz(tz)) return true;
    var saved_errno = getErrno();
    const ok = changeEnv(tz.?);
    if (!ok) saved_errno = getErrno();
    tzfree(tz);
    setErrno(saved_errno);
    return ok;
}

/// save_abbr from lib/time_rz.c (HAVE_STRUCT_TM_TM_ZONE path): copy the
/// abbreviation used by TM into TZ's cache so the tm_zone pointer stays
/// valid after the TZ environment is restored.
fn saveAbbr(tz: *TmZone, tm: *Tm) bool {
    const zone = tm.tm_zone orelse return true;
    const tm_addr = @intFromPtr(tm);
    const zone_addr = @intFromPtr(zone);
    // No need to replace null zones, or zones within the struct tm.
    if (tm_addr <= zone_addr and zone_addr < tm_addr + @sizeOf(Tm))
        return true;

    var node = tz;
    var zone_copy: [*]u8 = node.abbrs.ptr;
    if (zone[0] != 0) {
        outer: while (!streq(@ptrCast(zone_copy), zone)) {
            if (zone_copy[0] == 0 and !(zone_copy == node.abbrs.ptr and node.tz_is_set)) {
                const zone_size = strlen(zone) + 1;
                const room_end: usize = @intFromPtr(node.abbrs.ptr) + ABBR_SIZE_MIN;
                if (@intFromPtr(zone_copy) + zone_size < room_end) {
                    // extend_abbrs: copy the abbreviation plus its null,
                    // then an extra null to mark the end of ABBRS.
                    @memcpy(zone_copy[0..zone_size], zone[0..zone_size]);
                    zone_copy[zone_size] = 0;
                } else {
                    const new_node = tzalloc(zone) orelse return false;
                    new_node.tz_is_set = false;
                    node.next = new_node;
                    node = new_node;
                    zone_copy = node.abbrs.ptr;
                }
                break :outer;
            }

            const zlen = strlen(@ptrCast(zone_copy));
            zone_copy = zone_copy + zlen + 1;
            if (zone_copy[0] == 0 and node.next != null) {
                node = node.next.?;
                zone_copy = node.abbrs.ptr;
            }
        }
    }

    // Replace the zone name so that its lifetime matches that of TZ.
    tm.tm_zone = @ptrCast(zone_copy);
    return true;
}

/// localtime_rz from lib/time_rz.c: localtime_r with an explicit time
/// zone (NULL TZ means UTC, i.e. gmtime_r).
pub export fn localtime_rz(tz: ?*TmZone, t: *const time_t, tm: *Tm) ?*Tm {
    if (tz == null)
        return gmtime_r(t, tm);

    const old_tz = set_tz(tz) orelse return null;
    var abbr_saved = false;
    if (localtime_r(t, tm) != null)
        abbr_saved = saveAbbr(tz.?, tm);
    if (revert_tz(old_tz) and abbr_saved)
        return tm;
    return null;
}

/// mktime_z from lib/time_rz.c: mktime with an explicit time zone
/// (NULL TZ means UTC, i.e. timegm).
pub export fn mktime_z(tz: ?*TmZone, tm: *Tm) time_t {
    if (tz == null)
        return timegm(tm);

    const old_tz = set_tz(tz) orelse return -1;
    var tm_1: Tm = undefined;
    tm_1.tm_sec = tm.tm_sec;
    tm_1.tm_min = tm.tm_min;
    tm_1.tm_hour = tm.tm_hour;
    tm_1.tm_mday = tm.tm_mday;
    tm_1.tm_mon = tm.tm_mon;
    tm_1.tm_year = tm.tm_year;
    tm_1.tm_yday = -1;
    tm_1.tm_isdst = tm.tm_isdst;
    const t = mktime(&tm_1);
    var ok = 0 <= tm_1.tm_yday;
    ok = ok and saveAbbr(tz.?, &tm_1);
    if (revert_tz(old_tz) and ok) {
        tm.* = tm_1;
        return t;
    }
    return -1;
}
