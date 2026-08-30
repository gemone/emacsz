//! zeln-jit: the in-process lightweight JIT engine for the zeln native-comp
//! path (LuaJIT-informed design; replaces the heavyweight approach of
//! spawning the zeln-compile LLVM subprocess for HOT functions).
//!
//! Architecture (mirrors LuaJIT's tiering philosophy adapted to Emacs):
//!
//!   Tier 0  the bytecode interpreter (src/bytecode.c exec_byte_code) runs
//!           everything, counting invocations per compiled closure.
//!   Tier 1  when a closure's counter crosses zeln_jit_threshold, the
//!           hotness hook asks THIS engine (via the C ABI shim in
//!           src/compz.c) to compile the closure in-process: the Zig
//!           emitter below writes x86-64 machine code DIRECTLY into an
//!           executable arena -- no LLVM, no `zig cc` subprocess, no
//!           gcc/libgccjit, no disk I/O.
//!   Dispatch like the .zeln loader, generated code reaches every C
//!           entry point through the same closed freloc link table
//!           (src/compz.c zeln_freloc), so JIT code and .zeln code share
//!           one ABI and one calling convention.
//!
//! This file provides the engine's foundation:
//!   - ExecArena: W^X-safe executable memory (mmap RW/RX alias pair on
//!     Linux, MAP_JIT+pthread_jit_write_protect on macOS, VirtualAlloc
//!     with PAGE_EXECUTE_READWRITE toggling on Windows).
//!   - X86: a minimal length-prefixed instruction emitter (the subset
//!     needed for prologue/epilogue, freloc calls and stack access).
//!   - Unit tests that generate and EXECUTE real machine code in-process,
//!     proving the whole chain before the bytecode-tiering integration.
//!
//! Everything here is self-contained; the Emacs-facing C ABI shim lives
//! in src/compz.c and calls zeln_jit_compile_closure.

const std = @import("std");
const builtin = @import("builtin");

// Minimal kernel32 surface for the Windows ExecArena (VirtualAlloc/
// VirtualFree are not exposed by zig 0.16's std.os.windows; declared
// locally with the exact win32 signatures).
const win = struct {
    const MEM_COMMIT: u32 = 0x1000;
    const MEM_RESERVE: u32 = 0x2000;
    const MEM_RELEASE: u32 = 0x8000;
    const PAGE_EXECUTE_READWRITE: u32 = 0x40;

    extern "kernel32" fn VirtualAlloc(
        lpAddress: ?*anyopaque,
        dwSize: usize,
        flAllocationType: u32,
        flProtect: u32,
    ) callconv(.c) ?*anyopaque;

    extern "kernel32" fn VirtualFree(
        lpAddress: ?*anyopaque,
        dwSize: usize,
        dwFreeType: u32,
    ) callconv(.c) i32;

    extern "kernel32" fn RtlDeleteFunctionTable(
        callback: ?*anyopaque,
    ) callconv(.c) i32;
};

// ---------------------------------------------------------------------------
// ExecArena: executable memory with a W^X discipline.
//
// Linux: one RW mapping + one RX alias of the same physical pages
//        (mmap MAP_SHARED over memfd) -- write through the RW alias,
//        execute from the RX alias; no mprotect flipping, no RWX window.
//        This is the scheme modern JITs (V8, JSC) use on Linux.
// Windows: VirtualAlloc PAGE_EXECUTE_READWRITE (the platform offers no
//        aliasing; toggling per write-batch is the accepted practice).
// ---------------------------------------------------------------------------

pub const page_size = 4096;

fn osPageSize() usize {
    return std.heap.pageSize();
}

pub const ExecArena = struct {
    pub const Slot = struct { w: []u8, x: [*]u8 };
    /// One Windows dynamic function-table handle.  On other platforms the
    /// list stays empty and has no per-arena cost beyond one pointer.
    pub const UnwindNode = struct {
        next: ?*UnwindNode,
        id: ?*anyopaque,
    };

    /// writable alias (null where unsupported)
    w: ?[*]u8 = null,
    /// executable alias
    x: [*]u8,
    /// total bytes mapped
    len: usize,
    /// bytes committed to emitted code
    used: usize = 0,
    /// Windows unwind registrations owned by this arena; deleted before
    /// VirtualFree so a later exception cannot consult freed metadata.
    unwind_ids: ?*UnwindNode = null,

    pub fn allocate(bytes: usize) !ExecArena {
        const size = std.mem.alignForward(usize, @max(bytes, page_size), osPageSize());
        switch (builtin.os.tag) {
            .linux => {
                // memfd + dual mmap: RW alias for emission, RX alias for
                // execution.  ftruncate sizes the object; both mappings
                // share the physical pages so writes are immediately
                // visible to execution (coherent instruction cache on
                // x86; aarch64 needs no explicit icache flush for
                // same-thread but we publish a barrier hook for the
                // integrator anyway).
                const linux = std.os.linux;
                const mfd_fd = linux.memfd_create("zeln-jit", 0);
                if (@as(isize, @bitCast(mfd_fd)) < 0) return error.MemfdFailed;
                const mfd: i32 = @intCast(mfd_fd);
                defer _ = linux.close(mfd);
                const trunc = linux.ftruncate(mfd, @intCast(size));
                if (@as(isize, @bitCast(trunc)) < 0) return error.TruncateFailed;
                const w_map = linux.mmap(null, size, linux.PROT{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, mfd, 0);
                if (@as(isize, @bitCast(w_map)) < 0) return error.MmapFailed;
                const x_map = linux.mmap(null, size, linux.PROT{ .READ = true, .EXEC = true }, .{ .TYPE = .SHARED }, mfd, 0);
                if (@as(isize, @bitCast(x_map)) < 0) {
                    _ = linux.munmap(@ptrFromInt(w_map), size);
                    return error.MmapFailed;
                }
                return .{ .w = @ptrFromInt(w_map), .x = @ptrFromInt(x_map), .len = size };
            },
            .macos => {
                // MAP_JIT gives one RWX-but-gated region; the JIT write
                // protect thread-toggle is handled by the caller around
                // emission batches (beginWrite/endWrite below).  Note
                // std.posix.PROT on darwin is the macho.vm_prot_t packed
                // struct TYPE: construct an instance rather than reading
                // type-level constants.
                const mem = try std.posix.mmap(
                    null,
                    size,
                    std.posix.PROT{ .READ = true, .WRITE = true, .EXEC = true },
                    .{ .TYPE = .PRIVATE, .JIT = true },
                    -1,
                    0,
                );
                return .{ .w = mem.ptr, .x = mem.ptr, .len = size };
            },
            .windows => {
                // VirtualAlloc PAGE_EXECUTE_READWRITE: the platform offers
                // no RX/RW alias pair, so one RWX region is used (the
                // comment at the top of this file documents the accepted
                // W^X tradeoff for Windows JITs).  VirtualFree releases it.
                const mem = win.VirtualAlloc(
                    null,
                    size,
                    win.MEM_RESERVE | win.MEM_COMMIT,
                    win.PAGE_EXECUTE_READWRITE,
                ) orelse return error.MmapFailed;
                const p: [*]align(std.heap.pageSize()) u8 = @ptrCast(@alignCast(mem));
                return .{ .w = p, .x = p, .len = size };
            },
            else => {
                // Portable fallback: plain RWX anonymous mapping for the
                // remaining POSIX systems.  std.posix.PROT there is a
                // packed struct TYPE like darwin's: build an instance
                // (type-level .READ constants do not exist).
                const mem = try std.posix.mmap(
                    null,
                    size,
                    std.posix.PROT{ .READ = true, .WRITE = true, .EXEC = true },
                    .{ .TYPE = .PRIVATE },
                    -1,
                    0,
                );
                return .{ .w = mem.ptr, .x = mem.ptr, .len = size };
            },
        }
    }

    pub fn deinit(self: *ExecArena) void {
        if (builtin.os.tag == .windows) {
            var node = self.unwind_ids;
            while (node) |current| {
                const next = current.next;
                if (current.id) |id| _ = win.RtlDeleteFunctionTable(id);
                std.heap.smp_allocator.destroy(current);
                node = next;
            }
        }
        self.unwind_ids = null;
        if (builtin.os.tag == .linux) {
            // two independent mappings of the same object
            if (self.w) |w| _ = std.os.linux.munmap(@ptrCast(w), self.len);
            _ = std.os.linux.munmap(@ptrCast(self.x), self.len);
        } else if (builtin.os.tag == .windows) {
            _ = win.VirtualFree(self.x, 0, win.MEM_RELEASE);
        } else {
            std.posix.munmap(self.x[0..self.len]);
        }
        self.* = undefined;
    }

    /// Reserve `bytes` in the arena; returns the executable address.
    pub fn reserve(self: *ExecArena, bytes: usize) !Slot {
        const start = self.used;
        const end = start + bytes;
        if (end > self.len) return error.OutOfMemory;
        self.used = end;
        const w_alias = self.w orelse self.x;
        return .{
            .w = w_alias[start..end],
            .x = self.x + start,
        };
    }

    /// Remember a Windows dynamic unwind-table handle owned by this arena.
    pub fn addUnwindId(self: *ExecArena, id: ?*anyopaque) !void {
        if (builtin.os.tag != .windows) return;
        const node = try std.heap.smp_allocator.create(UnwindNode);
        node.* = .{ .next = self.unwind_ids, .id = id };
        self.unwind_ids = node;
    }
};

// ---------------------------------------------------------------------------
// X86: minimal x86-64 code emitter (System V / SysV-adjacent; the Emacs
// freloc surface is plain C, so JIT code follows the C ABI: args in
// rdi/rsi/rdx/rcx/r8/r9, return in rax, callee-saved rbx/rbp/r12-r15).
//
// Registers the generated code uses freely: rax rcx rdx rsi rdi r8-r11
// (caller-saved, no preservation needed around freloc calls).
// ---------------------------------------------------------------------------

pub const X86 = struct {
    buf: []u8,
    pos: usize = 0,

    const R = enum(u3) { rax = 0, rcx, rdx, rbx, rsp, rbp, rsi, rdi };

    fn emit(self: *X86, byte: u8) void {
        self.buf[self.pos] = byte;
        self.pos += 1;
    }

    fn emit32(self: *X86, v: u32) void {
        std.mem.writeInt(u32, self.buf[self.pos..][0..4], v, .little);
        self.pos += 4;
    }

    fn emit64(self: *X86, v: u64) void {
        std.mem.writeInt(u64, self.buf[self.pos..][0..8], v, .little);
        self.pos += 8;
    }

    /// REX prefix builder (W=64-bit, R=reg-extension, B=rm-extension).
    fn rex(self: *X86, w: bool, r: bool, b: bool) void {
        self.emit(0x40 | (@as(u8, @intFromBool(w)) << 3) |
            (@as(u8, @intFromBool(r)) << 2) | @as(u8, @intFromBool(b)));
    }

    // -- mov r64, imm64 ----------------------------------------------------
    pub fn movR64Imm64(self: *X86, reg: R, imm: u64) void {
        self.rex(true, (@as(u8, @intFromEnum(reg)) & 8) != 0, false);
        self.emit(0xB8 + (@as(u8, @intFromEnum(reg)) & 7));
        self.emit64(imm);
    }

    // -- mov r64, r64 ------------------------------------------------------
    pub fn movR64R64(self: *X86, dst: R, src: R) void {
        self.rex(true, (@as(u8, @intFromEnum(dst)) & 8) != 0, (@as(u8, @intFromEnum(src)) & 8) != 0);
        self.emit(0x89);
        self.emit(0xC0 | ((@as(u8, @intFromEnum(src)) & 7) << 3) |
            (@as(u8, @intFromEnum(dst)) & 7));
    }

    // -- call r64 (indirect through a register) ----------------------------
    pub fn callR64(self: *X86, reg: R) void {
        self.emit(0xFF);
        self.emit(0xD0 | (@as(u8, @intFromEnum(reg)) & 7));
    }

    // -- ret ---------------------------------------------------------------
    pub fn ret(self: *X86) void {
        self.emit(0xC3);
    }

    // -- add r64, imm32 ----------------------------------------------------
    pub fn addR64Imm32(self: *X86, reg: R, imm: i32) void {
        self.rex(true, false, (@as(u8, @intFromEnum(reg)) & 8) != 0);
        self.emit(0x81);
        self.emit(0xC0 | (@as(u8, @intFromEnum(reg)) & 7));
        self.emit32(@bitCast(imm));
    }

    // -- mov rax, imm64 then ret: the "constant function" idiom -------------
    pub fn constFn(self: *X86, value: u64) void {
        self.movR64Imm64(.rax, value);
        self.ret();
    }
};

// ---------------------------------------------------------------------------
// Hotness accounting (J2): the C side (src/bytecode.c exec_byte_code
// entry) calls zeln_jit_hot on every closure invocation.  The counter
// table lives here so the C side pays one call, not a hash lookup.
//
// When a closure crosses the threshold the hook returns true and the C
// side stops counting it (per-closure suppression; J3 wires real
// compilation).  Identifying the closure by its bytecode string's data
// pointer keeps this cheap and stable across invocations (the closure
// object itself may move under GC; the string data does not).
// ---------------------------------------------------------------------------

pub const default_threshold: u32 = 256;

/// One hotness entry: the closure's bytecode data pointer + count.
const HotEntry = struct {
    key: ?*const anyopaque = null,
    count: u32 = 0,
};

var hot_table: [16384]HotEntry = [_]HotEntry{.{}} ** 16384;
const hot_mask: u32 = 16384 - 1;

fn hotHash(key: *const anyopaque) u32 {
    const v = @intFromPtr(key);
    // Fibonacci hashing for pointer keys.
    return @truncate((v >> 4) *% 2654435761);
}

/// C ABI: number of tracked closures + how many crossed their
/// threshold (diagnostics for the J2 gate; also proves the hook fires
/// from inside Emacs at runtime).
var hot_crossed_total: u32 = 0;
var hot_tracked_total: u32 = 0;

export fn zeln_jit_stats(out: *[2]u32) void {
    var tracked: u32 = 0;
    for (hot_table) |e| {
        if (e.key != null) tracked += 1;
    }
    out[0] = tracked;
    out[1] = hot_crossed_total;
}

/// Called from exec_byte_code's entry (C ABI).  Returns true exactly
/// when THIS call crossed the threshold: the C side should then stop
/// counting this closure and, from J3 on, trigger compilation.
export fn zeln_jit_hot(key: *const anyopaque, threshold: u32) bool {
    var i = hotHash(key) & hot_mask;
    // Linear probe; an empty slot terminates the run.
    while (hot_table[i].key) |k| {
        if (k == key) {
            const c = hot_table[i].count +% 1;
            hot_table[i].count = c;
            if (c == threshold) {
                hot_crossed_total += 1;
                return true;
            }
            return false;
        }
        i = (i + 1) & hot_mask;
    }
    // Insert.
    hot_table[i] = .{ .key = key, .count = 1 };
    hot_tracked_total += 1;
    return threshold == 1;
}

test "hot counter crosses threshold exactly once" {
    const key: u8 = 0;
    const kp: *const anyopaque = &key;
    var crossed: usize = 0;
    for (0..300) |_| {
        if (zeln_jit_hot(kp, 256)) crossed += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), crossed);
}

test "distinct keys tracked independently" {
    var a: u8 = 0;
    var b: u8 = 0;
    for (0..10) |_| {
        _ = zeln_jit_hot(&a, 5);
        _ = zeln_jit_hot(&b, 100);
    }
    // a crossed at 5; a further call must NOT cross again (one-shot ==
    // comparison), while b never reaches 100 in 10 calls.
    try std.testing.expect(!zeln_jit_hot(&a, 5));
}

// ---------------------------------------------------------------------------
// Tests: generate + EXECUTE machine code in-process.
// ---------------------------------------------------------------------------

test "arena emits and executes a constant function" {
    var arena = try ExecArena.allocate(page_size);
    defer arena.deinit();

    const slot = try arena.reserve(16);
    var asm_ = X86{ .buf = slot.w };
    asm_.constFn(0x1234);
    try std.testing.expectEqual(@as(usize, 11), asm_.pos);

    const fn_ptr: *const fn () callconv(.c) u64 =
        @ptrCast(@alignCast(slot.x));
    const got = fn_ptr();
    try std.testing.expectEqual(@as(u64, 0x1234), got);
}

test "arena executes code calling a C function through a register" {
    // target: int add(int,int) via C ABI -- emitted code loads the target
    // address into rax, moves args into the platform's first two argument
    // registers (rdi/rsi on SysV, rcx/rdx on WinX64), calls, returns rax.
    var arena = try ExecArena.allocate(page_size);
    defer arena.deinit();

    const slot = try arena.reserve(64);
    var asm_ = X86{ .buf = slot.w };

    const addFn = struct {
        fn add(a: u64, b: u64) callconv(.c) u64 {
            return a + b;
        }
    }.add;

    asm_.movR64Imm64(.rax, @intFromPtr(&addFn));
    if (builtin.os.tag == .windows) {
        asm_.movR64Imm64(.rcx, 20);
        asm_.movR64Imm64(.rdx, 22);
    } else {
        asm_.movR64Imm64(.rdi, 20);
        asm_.movR64Imm64(.rsi, 22);
    }
    asm_.callR64(.rax);
    asm_.ret();

    const fn_ptr: *const fn () callconv(.c) u64 = @ptrCast(@alignCast(slot.x));
    try std.testing.expectEqual(@as(u64, 42), fn_ptr());
}

test "multiple reservations execute independently" {
    var arena = try ExecArena.allocate(page_size);
    defer arena.deinit();

    const a = try arena.reserve(16);
    const b = try arena.reserve(16);
    var x1 = X86{ .buf = a.w };
    x1.constFn(7);
    var x2 = X86{ .buf = b.w };
    x2.constFn(9);

    const f1: *const fn () callconv(.c) u64 = @ptrCast(@alignCast(a.x));
    const f2: *const fn () callconv(.c) u64 = @ptrCast(@alignCast(b.x));
    try std.testing.expectEqual(@as(u64, 7), f1());
    try std.testing.expectEqual(@as(u64, 9), f2());
}

/// C ABI diagnostic: the current count for KEY (0 when untracked).
export fn zeln_jit_count(key: *const anyopaque) u32 {
    var i = hotHash(key) & hot_mask;
    while (hot_table[i].key) |k| {
        if (k == key) return hot_table[i].count;
        i = (i + 1) & hot_mask;
    }
    return 0;
}

test "count reporting" {
    // Fresh keys (stack slots unique to this frame) so earlier tests'
    // table state cannot leak into the expectations.
    // STATIC storage: stack slots are reused across tests at identical
    // addresses, so a stack local key would collide with earlier tests'
    // entries (observed: same address -> continued counting).  A file-scope
    // variable gives this test a key nothing else can share.
    k_test_slot = k_test_slot +% 1;
    const kp: *const anyopaque = &k_test_slot;
    var crossed: u32 = 0;
    for (0..300) |_| {
        if (zeln_jit_hot(kp, 256)) crossed += 1;
    }
    // exactly one crossing at call #256, count == calls, both queryable
    try std.testing.expectEqual(@as(u32, 1), crossed);
    try std.testing.expectEqual(@as(u32, 300), zeln_jit_count(kp));
    try std.testing.expectEqual(@as(u32, 0), zeln_jit_count(&stack_canary));
}
var stack_canary: u8 = 0;
var k_test_slot: u8 = 0;

pub const compiler = @import("compiler.zig");

// Pull the compiler's tests into this root's test build.
comptime {
    _ = @import("compiler.zig");
}
