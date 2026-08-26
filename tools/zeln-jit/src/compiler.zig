//! J3: the bytecode -> x86-64 machine-code compiler for the in-process JIT.
//!
//! Port of zeln-compile's M1 decoder to DIRECT machine-code emission
//! (no LLVM, no subprocess, no gcc): each supported opcode lowers to the
//! same push/pop discipline the interpreter uses (`*++top = x`), with
//! every Lisp operation reached through the freloc link table exactly
//! like .zeln code — one ABI, one GC discipline.
//!
//! Generated code shape (System V AMD64), entry convention = the zeln
//! MANY convention `Lisp_Object fn (ptrdiff_t nargs, Lisp_Object *args)`:
//!
//!   prologue:  push rbp; mov rbp,rsp; push r12; push r13; push r14
//!              sub rsp, 8*stack_depth        ; the virtual stack
//!              mov r12, rsi                  ; top = args-1 (interpreter
//!                                             ; frames start at args-1)
//!              mov r13, [freloc_slot_addr]   ; r13 = link-table base
//!              mov r14, consts_ptr           ; r14 = constants vector
//!   body:      one straight-line lowering per opcode; branches patch
//!              forward to block starts.
//!   epilogue:  mov rsp, rbp-reversed; ret with rax = TOS.
//!
//! ABI note: r12/r13/r14 are callee-saved — the prologue preserves them
//! and the epilogue restores, so freloc C helpers observe the C ABI.
//! Args arrive in rdi (nargs) / rsi (args) per SysV.

const std = @import("std");
const jit = @import("jit.zig");

// ---- freloc indices (MUST match src/compz.c's frozen enum) -----------
pub const IDX_SETUP_ARGS: u64 = 0;
pub const IDX_FUNCALL: u64 = 1;
pub const IDX_NILP: u64 = 2;
pub const IDX_PLUS: u64 = 3;
pub const IDX_MINUS: u64 = 4;
pub const IDX_TIMES: u64 = 5;
pub const IDX_SUB1: u64 = 6;
pub const IDX_ADD1: u64 = 7;
pub const IDX_NEGATE: u64 = 8;
pub const IDX_EQ: u64 = 17;
pub const IDX_CAR: u64 = 19;
pub const IDX_CDR: u64 = 20;
pub const IDX_CONS: u64 = 21;

// ---- opcode numbers (mirror zeln-compile; mirror src/bytecode.c) -----
const BSTACK_REF1: u8 = 1;
const BSTACK_REF5: u8 = 5;
const BSTACK_REF6: u8 = 6;
const BSTACK_REF7: u8 = 7;
const BCALL: u8 = 32;
const BCALL5: u8 = 37;
const BCALL6: u8 = 38;
const BCALL7: u8 = 39;
const BCAR: u8 = 64;
const BCDR: u8 = 65;
const BCONS: u8 = 66;
const BSUB1: u8 = 83;
const BADD1: u8 = 84;
const BNEGATE: u8 = 91;
const BPLUS: u8 = 92;
const BMULT: u8 = 95;
const BDIFF: u8 = 90;
const BCONSTANT2: u8 = 129;
const BGOTO: u8 = 130;
const BGOTOIFNIL: u8 = 131;
const BGOTOIFNONNIL: u8 = 132;
const BGOTOIFNILELSEPOP: u8 = 133;
const BGOTOIFNONNILELSEPOP: u8 = 134;
const BRETURN: u8 = 135;
const BDISCARD: u8 = 136;
const BDUP: u8 = 137;
const BCONSTANT_BASE: u8 = 192;

fn gpa0() std.mem.Allocator {
    return std.heap.smp_allocator;
}

pub const Error = error{
    UnsupportedOpcode,
    OutOfMemory,
    BadBytecode,
};

pub const Fn = *const fn (i64, [*]const u64) callconv(.c) u64;

pub const Result = struct {
    entry: Fn,
    /// code bytes consumed
    size: u32,
    /// opcode names rejected (null on success)
    rejected: ?u8 = null,
};

/// One pending branch fixup: code offset -> bytecode target.
const Patch = struct { at: u32, target_bc: u32 };

const Emitter = struct {
    buf: []u8,
    pos: u32 = 0,
    patches: std.ArrayList(Patch),
    /// bytecode offset -> code offset
    blocks: std.AutoHashMap(u32, u32),

    fn raw(self: *Emitter, b: u8) void {
        self.buf[self.pos] = b;
        self.pos += 1;
    }
    fn imm32(self: *Emitter, v: i32) void {
        std.mem.writeInt(i32, self.buf[self.pos..][0..4], v, .little);
        self.pos += 4;
    }
    fn imm64(self: *Emitter, v: u64) void {
        std.mem.writeInt(u64, self.buf[self.pos..][0..8], v, .little);
        self.pos += 8;
    }
    /// mov r64, imm64 with REX.W
    fn movImm64(self: *Emitter, dst: u8, v: u64) void {
        self.raw(0x48 | (if (dst >= 8) @as(u8, 1) else @as(u8, 0))); // REX.W(+B)
        self.raw(0xB8 + (dst & 7));
        self.imm64(v);
    }
    /// call [r13 + idx*8] — the freloc indirection.
    fn callFreloc(self: *Emitter, idx: u64) void {
        // mov rax, [r13 + idx*8]; call rax
        self.raw(0x49); self.raw(0x8B); // mov r64, [r13+disp8] REX.WB
        self.raw(0x45); // modrm: rax <- [r13+disp8]
        self.raw(@intCast(idx * 8)); // disp8 (surface < 32 entries)
        self.raw(0xFF); self.raw(0xD0); // call rax
    }
};

/// Compile ONE function's bytecode.  `freloc_slot` is the address of the
/// pointer the loader patches (we bake a load of it into the prologue so
/// the code picks up the table at entry — cheap and re-read safe).
/// `consts` are the Lisp_Object constants as raw words.
pub fn compile(
    arena: *jit.ExecArena,
    opcodes: []const u8,
    stack_depth: u32,
    freloc_slot: *const *const anyopaque,
    consts_vec: [*]const u64,
) Error!Result {
    const slot = try arena.reserve(4096);
    var em = Emitter{
        .buf = slot.w,
        .patches = .empty,
        .blocks = .init(std.heap.smp_allocator),
    };
    defer em.patches.deinit(std.heap.smp_allocator);
    defer em.blocks.deinit();

    // ---- prologue ----
    em.raw(0x55); // push rbp
    em.raw(0x48); em.raw(0x89); em.raw(0xE5); // mov rbp, rsp
    em.raw(0x41); em.raw(0x54); // push r12
    em.raw(0x41); em.raw(0x55); // push r13
    em.raw(0x41); em.raw(0x56); // push r14
    // sub rsp, stack_depth*8 (align 16)
    const frame: u32 = ((stack_depth * 8) + 15) & ~@as(u32, 15);
    em.raw(0x48); em.raw(0x81); em.raw(0xEC); em.imm32(@intCast(frame)); // sub rsp, imm32
    // r12 = top = args-1 (interpreter semantics: slots are 1-based from
    // args-1; Bconstant does *++top)
    em.raw(0x49); em.raw(0x89); em.raw(0xF4); // mov r12, rsi
    em.raw(0x49); em.raw(0x83); em.raw(0xEC); em.raw(8); // sub r12, 8
    // r13 = [freloc_slot]
    em.movImm64(0, @intFromPtr(freloc_slot)); // mov rax, imm64
    em.raw(0x4C); em.raw(0x8B); em.raw(0x28); // mov r13, [rax] (REX.WR)
    // r14 = consts vector
    em.movImm64(14, @intFromPtr(consts_vec)); // mov r14, imm64 (REX.WB)

    // ---- body: decode loop ----
    var pc: u32 = 0;
    while (pc < opcodes.len) {
        try em.blocks.put(pc, em.pos);
        const b = opcodes[pc];
        pc += 1;
        if (b >= BCONSTANT_BASE) {
            const idx: u32 = b - BCONSTANT_BASE;
            // PUSH consts[idx]:  mov rax,[r14+idx*8]; mov [r12+8],rax; add r12,8
            em.raw(0x49); em.raw(0x8B); em.raw(0x46); em.raw(@intCast(idx * 8));
            em.raw(0x49); em.raw(0x89); em.raw(0x44); em.raw(0x24); em.raw(8);
            em.raw(0x49); em.raw(0x83); em.raw(0xC4); em.raw(8);
            continue;
        }
        switch (b) {
            BRETURN => {
                // rax = [r12]; jmp epilogue
                em.raw(0x49); em.raw(0x8B); em.raw(0x04); em.raw(0x24);
                // epilogue inline
                em.raw(0x48); em.raw(0x8D); em.raw(0x65); em.raw(0xE8); // lea rsp,[rbp-0x18]
                em.raw(0x41); em.raw(0x5E); // pop r14
                em.raw(0x41); em.raw(0x5D); // pop r13
                em.raw(0x41); em.raw(0x5C); // pop r12
                em.raw(0x5D); // pop rbp
                em.raw(0xC3); // ret
            },
            else => return Error.UnsupportedOpcode,
        }
    }
    if (pc != opcodes.len) return Error.BadBytecode;

    const entry_ptr: Fn = @ptrCast(@alignCast(slot.x));
    return .{ .entry = entry_ptr, .size = em.pos };
}

// ---------------------------------------------------------------------------
// Tests: compile minimal bytecode and EXECUTE it in-process.
// ---------------------------------------------------------------------------

const testing = std.testing;

test "compile and run: constant then return" {
    var arena = try jit.ExecArena.allocate(jit.page_size);
    defer arena.deinit();

    // A tiny fake freloc surface: entry 0 unused here; we only need the
    // slot indirection to resolve.
    var freloc_base: u64 = 0;
    const freloc_slot: *const *const anyopaque = @ptrCast(&freloc_base);

    // bytecode: Bconstant 0 (0xC0), Breturn (135)
    const opcodes = [_]u8{ 0xC0, 135 };
    // constants: the "Lisp object" 42 (a raw word for the test)
    var consts = [_]u64{42};
    const consts_ptr: [*]const u64 = &consts;

    const res = try compile(&arena, &opcodes, 8, freloc_slot, consts_ptr);
    try testing.expect(res.rejected == null);

    // Call: entry(0, args) — args unused by this bytecode.
    var args: [1]u64 = .{0};
    const got = res.entry(0, &args);
    try testing.expectEqual(@as(u64, 42), got);
}
