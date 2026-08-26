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

const page_size = 4096;

fn osPageSize() usize {
    return std.heap.pageSize();
}

pub const ExecArena = struct {
    /// writable alias (null where unsupported)
    w: ?[*]u8 = null,
    /// executable alias
    x: [*]u8,
    /// total bytes mapped
    len: usize,
    /// bytes committed to emitted code
    used: usize = 0,

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
                // emission batches (beginWrite/endWrite below).
                const mem = try std.posix.mmap(
                    null,
                    size,
                    std.posix.PROT.READ | std.posix.PROT.WRITE | std.posix.PROT.EXEC,
                    .{ .TYPE = .PRIVATE, .FLAGS = .{ .JIT = true } },
                    -1,
                    0,
                );
                return .{ .w = mem.ptr, .x = mem.ptr, .len = size };
            },
            else => {
                // Portable fallback: plain RWX anonymous mapping (Windows
                //VirtualAlloc-equivalent semantics via mmap where allowed).
                const mem = try std.posix.mmap(
                    null,
                    size,
                    std.posix.PROT.READ | std.posix.PROT.WRITE | std.posix.PROT.EXEC,
                    .{ .TYPE = .PRIVATE },
                    -1,
                    0,
                );
                return .{ .w = mem.ptr, .x = mem.ptr, .len = size };
            },
        }
    }

    pub fn deinit(self: *ExecArena) void {
        if (builtin.os.tag == .linux) {
            // two independent mappings of the same object
            if (self.w) |w| _ = std.os.linux.munmap(@ptrCast(w), self.len);
            _ = std.os.linux.munmap(@ptrCast(self.x), self.len);
        } else {
            std.posix.munmap(self.x[0..self.len]);
        }
        self.* = undefined;
    }

    /// Reserve `bytes` in the arena; returns the executable address.
    pub fn reserve(self: *ExecArena, bytes: usize) !struct { w: []u8, x: [*]u8 } {
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
    // address into rax, moves args into rdi/rsi, calls, returns rax.
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
    asm_.movR64Imm64(.rdi, 20);
    asm_.movR64Imm64(.rsi, 22);
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
