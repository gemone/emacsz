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

// ---- freloc indices - the REAL src/compz.c enum order (read directly
//      from the enum at compz.c:418: SETUP_ARGS=0 FUNCALL=1 NILP=2 PLUS=3
//      MINUS=4 TIMES=5 SUB1=6 ADD1=7 NEGATE=8 ...).  An earlier attempt
//      "enumerated" these wrong by parsing prose comments; always read
//      the enum itself.  ----
pub const IDX_SETUP_ARGS: u64 = 0;
pub const IDX_FUNCALL: u64 = 1;
pub const IDX_NILP: u64 = 2;
pub const IDX_PLUS: u64 = 3;
pub const IDX_MINUS: u64 = 4;
pub const IDX_TIMES: u64 = 5;
pub const IDX_SUB1: u64 = 6;
pub const IDX_ADD1: u64 = 7;
pub const IDX_NEGATE: u64 = 8;
pub const IDX_EQLSIGN: u64 = 11;
pub const IDX_GTR: u64 = 12;
pub const IDX_LSS: u64 = 13;
pub const IDX_LEQ: u64 = 14;
pub const IDX_GEQ: u64 = 15;
pub const IDX_EQUAL: u64 = 16;
pub const IDX_EQ: u64 = 17;
pub const IDX_CAR: u64 = 19;
pub const IDX_CDR: u64 = 20;
pub const IDX_CONS: u64 = 21;
pub const IDX_SYMBOL_VALUE: u64 = 38;
pub const IDX_LIST: u64 = 26;
pub const IDX_CONCAT: u64 = 44;
pub const IDX_LENGTH: u64 = 35;
pub const IDX_VARSET: u64 = 91;
pub const IDX_VARBIND: u64 = 92;
pub const IDX_UNBIND: u64 = 93;

// ---- opcode numbers (mirror zeln-compile; mirror src/bytecode.c) -----
const BSTACK_REF1: u8 = 1;
const BSTACK_REF5: u8 = 5;
const BSTACK_REF6: u8 = 6;
const BSTACK_REF7: u8 = 7;
const BCALL: u8 = 32;
const BCALL5: u8 = 37;
const BCALL6: u8 = 38;
const BCALL7: u8 = 39;
const BNOT: u8 = 63;
const BVARREF: u8 = 8; // Bvarref..Bvarref5 = 8..13
const BCAR: u8 = 64;
const BCDR: u8 = 65;
const BCONS: u8 = 66;
const BSUB1: u8 = 83;
const BADD1: u8 = 84;
const BNEGATE: u8 = 91;
const BVARSET: u8 = 16; // Bvarset..Bvarset5 = 16..21
const BVARSET5: u8 = 21;
const BVARSET6: u8 = 22;
const BVARSET7: u8 = 23;
const BVARBIND: u8 = 24; // Bvarbind..Bvarbind5 = 24..29
const BVARBIND5: u8 = 29;
const BVARBIND6: u8 = 30;
const BVARBIND7: u8 = 31;
const BUNBIND: u8 = 40; // Bunbind..Bunbind5 = 40..45
const BUNBIND5: u8 = 45;
const BUNBIND6: u8 = 46;
const BUNBIND7: u8 = 47;
const BSTACK_SET: u8 = 178; // arg = FETCH: ptr=top[-arg]; *ptr = POP
const BSTACK_SET2: u8 = 179;
const BLENGTH: u8 = 71; // 0107 octal
const BLISTN: u8 = 175;
const BCONCAT2: u8 = 80;
const BCONCAT3: u8 = 81;
const BCONCAT4: u8 = 82;
const BEQLSIGN: u8 = 85;
const BGTR: u8 = 86;
const BLSS: u8 = 87;
const BLEQ: u8 = 88;
const BGEQ: u8 = 89;
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


fn fetch1(opcodes: []const u8, pc: u32) ?u32 {
    if (pc >= opcodes.len) return null;
    return opcodes[pc];
}
fn fetch2(opcodes: []const u8, pc: u32) ?u32 {
    if (pc + 1 >= opcodes.len) return null;
    return @as(u32, opcodes[pc]) | (@as(u32, opcodes[pc + 1]) << 8);
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
    // ---- emit primitives (all REX-verified; see the two bug notes in
    //      git history: REX.R extends REG, REX.B extends R/M) ----

    /// rax = [r12]
    fn loadTosRax(self: *Emitter) void {
        self.raw(0x49); self.raw(0x8B); self.raw(0x04); self.raw(0x24);
    }
    /// [r12+8] = rax; r12 += 8  (PUSH rax, TOS already in rax)
    fn pushRaxNoLoad(self: *Emitter) void {
        self.raw(0x49); self.raw(0x89); self.raw(0x44); self.raw(0x24); self.raw(8);
        self.raw(0x49); self.raw(0x83); self.raw(0xC4); self.raw(8);
    }
    /// r12 += delta bytes
    fn adjustTop(self: *Emitter, delta: i32) void {
        if (delta < 0) {
            self.raw(0x49); self.raw(0x83); self.raw(0xEC); self.raw(@intCast(-delta));
        } else {
            self.raw(0x49); self.raw(0x83); self.raw(0xC4); self.raw(@intCast(delta));
        }
    }
    /// PUSH consts[idx]: mov rax,[r14 + idx*8] with disp8/disp32 as
    /// needed (idx*8 overflows disp8's signed range at idx 16).
    fn pushConst(self: *Emitter, idx: u32) void {
        const disp: i32 = @intCast(idx * 8);
        if (disp < 128) {
            self.raw(0x49); self.raw(0x8B); self.raw(0x46); self.raw(@intCast(disp));
        } else {
            // mod=10 (disp32), rm=110 r14-with-REXB: 8B /r with SIB-free
            self.raw(0x49); self.raw(0x8B); self.raw(0x86); self.imm32(disp);
        }
        self.pushRaxNoLoad();
    }
    /// PUSH top[-depth]
    fn pushStackRef(self: *Emitter, depth: u32) void {
        // rax = [r12 - depth*8]
        self.raw(0x49); self.raw(0x8B); self.raw(0x84); self.raw(0x24);
        self.imm32(-@as(i32, @intCast(depth * 8)));
        self.pushRaxNoLoad();
    }
    /// call [r13 + idx*8] with rdi=n, rsi=ptr; rax = result.
    /// disp32 form (mod=10): the real surface reaches idx 39+
    /// (SYMBOL_VALUE = 312 bytes) which overflows disp8's signed
    /// range - the leftover disp8 form here was the loaddefs RIP=0
    /// crash (gdb: mov 0x18(%r13),%rax reading a wrong/nul slot).
    fn frelocCall(self: *Emitter, idx: u64) void {
        self.raw(0x49); self.raw(0x8B); self.raw(0x85);
        self.imm32(@intCast(idx * 8));
        self.raw(0xFF); self.raw(0xD0); // call rax
    }
    /// unary: v=[r12]; rdi=1; rsi=r12; rax=fn(1,rsi); [r12]=rax
    fn unaryFreloc(self: *Emitter, idx: u64) void {
        self.raw(0x48); self.raw(0xC7); self.raw(0xC7); self.imm32(1); // mov rdi,1
        self.raw(0x4C); self.raw(0x89); self.raw(0xE6); // mov rsi,r12 (REX.WR)
        self.frelocCall(idx);
        self.raw(0x49); self.raw(0x89); self.raw(0x04); self.raw(0x24); // [r12]=rax
    }
    /// binary: v2=[r12]; r12-=8; rdi=2; rsi=r12; rax=fn(2,rsi); [r12]=rax
    fn binaryFreloc(self: *Emitter, idx: u64) void {
        self.adjustTop(-8);
        self.raw(0x48); self.raw(0xC7); self.raw(0xC7); self.imm32(2);
        self.raw(0x4C); self.raw(0x89); self.raw(0xE6);
        self.frelocCall(idx);
        self.raw(0x49); self.raw(0x89); self.raw(0x04); self.raw(0x24);
    }
    /// n-ary (concat/listN): pop n values, call fn(n, base), push result.
    fn naryFreloc(self: *Emitter, idx: u64, n: u32) void {
        self.adjustTop(-@as(i32, @intCast((n - 1) * 8)));
        self.raw(0x48); self.raw(0xC7); self.raw(0xC7); self.imm32(@intCast(n));
        self.raw(0x4C); self.raw(0x89); self.raw(0xE6); // mov rsi,r12
        self.frelocCall(idx);
        self.raw(0x49); self.raw(0x89); self.raw(0x04); self.raw(0x24);
    }
    fn ternaryFreloc(self: *Emitter, idx: u64) void {
        self.naryFreloc(idx, 3);
    }
    fn quatFreloc(self: *Emitter, idx: u64) void {
        self.naryFreloc(idx, 4);
    }
    /// Bstack_set: ptr = top[-arg]; *ptr = POP.
    fn stackSet(self: *Emitter, depth: u32) void {
        // rax = [r12] (value to store); rdx = r12 - depth*8 (slot ptr)
        self.loadTosRax();
        self.raw(0x49); self.raw(0x8B); self.raw(0xD4); // mov rdx,r12
        self.raw(0x48); self.raw(0x81); self.raw(0xEA); self.imm32(@intCast(depth * 8)); // sub rdx,depth*8
        self.raw(0x48); self.raw(0x89); self.raw(0x02); // [rdx] = rax
        self.adjustTop(-8); // POP
    }
    /// Bvarset: set_internal(consts[idx], POP).  Two scratch words live
    /// just below the virtual stack base: [rsp-8]=symbol, [rsp-16]=value.
    fn varsetConst(self: *Emitter, idx: u32) void {
        // rax = value = [r12]; save below stack
        self.loadTosRax();
        self.raw(0x48); self.raw(0x89); self.raw(0x44); self.raw(0x24); self.raw(0xF0); // [rsp-16]=rax
        // rax = consts[idx] -> [rsp-8]
        const disp: i32 = @intCast(idx * 8);
        if (disp < 128) {
            self.raw(0x49); self.raw(0x8B); self.raw(0x46); self.raw(@intCast(disp));
        } else {
            self.raw(0x49); self.raw(0x8B); self.raw(0x86); self.imm32(disp);
        }
        self.raw(0x48); self.raw(0x89); self.raw(0x44); self.raw(0x24); self.raw(0xF8); // [rsp-8]=rax
        // call set_internal(2, rsp-16)
        self.raw(0x48); self.raw(0xC7); self.raw(0xC7); self.imm32(2);
        self.raw(0x48); self.raw(0x89); self.raw(0xE6); // mov rsi,rsp
        self.raw(0x48); self.raw(0x83); self.raw(0xEE); self.raw(16); // sub rsi,16
        self.frelocCall(IDX_VARSET);
        self.adjustTop(-8); // POP
    }
    /// Bvarbind: specbind(consts[idx], POP).
    fn varbindConst(self: *Emitter, idx: u32) void {
        self.loadTosRax();
        self.raw(0x48); self.raw(0x89); self.raw(0x44); self.raw(0x24); self.raw(0xF0);
        const disp: i32 = @intCast(idx * 8);
        if (disp < 128) {
            self.raw(0x49); self.raw(0x8B); self.raw(0x46); self.raw(@intCast(disp));
        } else {
            self.raw(0x49); self.raw(0x8B); self.raw(0x86); self.imm32(disp);
        }
        self.raw(0x48); self.raw(0x89); self.raw(0x44); self.raw(0x24); self.raw(0xF8);
        self.raw(0x48); self.raw(0xC7); self.raw(0xC7); self.imm32(2);
        self.raw(0x48); self.raw(0x89); self.raw(0xE6);
        self.raw(0x48); self.raw(0x83); self.raw(0xEE); self.raw(16);
        self.frelocCall(IDX_VARBIND);
        self.adjustTop(-8);
    }
    /// Bunbind n: unbind_to(specpdl_count - n).  The zeln_unbind shim
    /// takes (n, &n) - C computes the specpdl arithmetic.
    fn unbindN(self: *Emitter, n: u32) void {
        self.raw(0x48); self.raw(0xC7); self.raw(0xC7); self.imm32(@intCast(n));
        self.raw(0x4C); self.raw(0x89); self.raw(0xE6); // mov rsi,r12
        self.frelocCall(IDX_UNBIND);
    }
    /// Bcall n: fp = r12 - n*8 (fun below args); r12 = fp; FUNCALL(n+1, fp);
    /// [fp] = rax; r12 = fp (top = result)
    fn callFrelocN(self: *Emitter, n: u32) void {
        // rdi = n+1, rsi = r12 - n*8 (args+fun group base)
        self.raw(0x48); self.raw(0xC7); self.raw(0xC7); self.imm32(@intCast(n + 1));
        // rsi = r12; rsi -= n*8
        self.raw(0x4C); self.raw(0x89); self.raw(0xE6); // mov rsi,r12 (REX.WR)
        self.raw(0x48); self.raw(0x81); self.raw(0xEE); self.imm32(@intCast(n * 8)); // sub rsi,n*8
        self.frelocCall(IDX_FUNCALL);
        // [r12 - n*8] = rax ; r12 -= n*8
        self.raw(0x49); self.raw(0x89); self.raw(0x84); self.raw(0x24);
        self.imm32(-@as(i32, @intCast(n * 8)));
        self.adjustTop(-@as(i32, @intCast(n * 8)));
    }
    /// jmp to bytecode target (patched later)
    fn emitJump(self: *Emitter, target_bc: u32) void {
        self.raw(0xE9);
        self.patches.append(std.heap.smp_allocator, .{ .at = self.pos, .target_bc = target_bc }) catch {};
        self.imm32(0);
    }
    /// POP v; if (v == 0) [nil when want_nil] jump; else fallthrough
    fn condJump(self: *Emitter, target_bc: u32, want_nil: bool) void {
        // rax = [r12]; r12 -= 8; test rax,rax; jz/jnz patch
        self.loadTosRax();
        self.adjustTop(-8);
        self.raw(0x48); self.raw(0x85); self.raw(0xC0); // test rax,rax
        // two-byte jcc rel32: 0F 84 (jz) / 0F 85 (jnz); the one-byte
        // 74/75 forms carry only rel8 and would truncate our rel32.
        self.raw(0x0F);
        self.raw(if (want_nil) 0x84 else 0x85);
        self.patches.append(std.heap.smp_allocator, .{ .at = self.pos, .target_bc = target_bc }) catch {};
        self.imm32(0);
    }
    /// POP v; if nil jump else keep+pop (else-pop variants)
    fn condJumpKeep(self: *Emitter, target_bc: u32, want_nil: bool) void {
        // rax = [r12] (no pop yet); test; jz/jnz to KEEP path...
        // Semantics: goto-if-nil-else-pop: if nil -> jump (keep value);
        // else pop and fall through.
        self.loadTosRax();
        self.raw(0x48); self.raw(0x85); self.raw(0xC0);
        self.raw(0x0F);
        self.raw(if (want_nil) 0x84 else 0x85);
        self.patches.append(std.heap.smp_allocator, .{ .at = self.pos, .target_bc = target_bc }) catch {};
        self.imm32(0);
        // fallthrough: pop
        self.adjustTop(-8);
    }
    /// Bvarref: PUSH Fsymbol_value(consts[idx]).
    fn varrefConst(self: *Emitter, idx: u32) void {
        const disp: i32 = @intCast(idx * 8);
        if (disp < 128) {
            self.raw(0x49); self.raw(0x8B); self.raw(0x46); self.raw(@intCast(disp));
        } else {
            self.raw(0x49); self.raw(0x8B); self.raw(0x86); self.imm32(disp);
        }
        self.pushRaxNoLoad();
        self.raw(0x48); self.raw(0xC7); self.raw(0xC7); self.imm32(1);
        self.raw(0x4C); self.raw(0x89); self.raw(0xE6); // mov rsi,r12
        self.frelocCall(IDX_SYMBOL_VALUE);
        self.raw(0x49); self.raw(0x89); self.raw(0x04); self.raw(0x24);
    }
    /// epilogue with rax = TOS
    fn epilogueFromTos(self: *Emitter) void {
        self.loadTosRax();
        self.raw(0x48); self.raw(0x8D); self.raw(0x65); self.raw(0xE8);
        self.raw(0x41); self.raw(0x5E);
        self.raw(0x41); self.raw(0x5D);
        self.raw(0x41); self.raw(0x5C);
        self.raw(0x5D);
        self.raw(0xC3);
    }

    /// mov r64, imm64 with REX.W
    fn movImm64(self: *Emitter, dst: u8, v: u64) void {
        self.raw(0x48 | (if (dst >= 8) @as(u8, 1) else @as(u8, 0))); // REX.W(+B)
        self.raw(0xB8 + (dst & 7));
        self.imm64(v);
    }
    /// call [r13 + idx*8] — the freloc indirection.  disp32 form: the
    /// real surface reaches idx 39+ (SYMBOL_VALUE) whose byte offset
    /// 312 overflows disp8's signed range (the RIP=0 crashes).
    fn callFreloc(self: *Emitter, idx: u64) void {
        // mov rax, [r13 + disp32]: 49 8B 85 <disp32> (mod=10 rm=101+rB)
        self.raw(0x49); self.raw(0x8B); self.raw(0x85);
        self.imm32(@intCast(idx * 8));
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
    arity: u32,
) Error!Result {
    // Pre-scan: every branch target must land inside the bytecode.  A
    // malformed closure (observed from dump'd images with truncated or
    // inconsistent bytes) would otherwise make the decode loop read past
    // the buffer and the patch pass jump into garbage.
    {
        var p: u32 = 0;
        while (p < opcodes.len) {
            const b = opcodes[p];
            if (b >= BCONSTANT_BASE) {
                p += 1;
                continue;
            }
            var imm: u32 = 0;
            var tgt: ?u32 = null;
            switch (b) {
                BGOTO, BGOTOIFNIL, BGOTOIFNONNIL, BGOTOIFNILELSEPOP, BGOTOIFNONNILELSEPOP => {
                    tgt = fetch2(opcodes, p + 1);
                    imm = 2;
                },
                9, 10, 11, 12, 13 => imm = 0, // Bvarref1..5: no immediate
                BVARSET6, BVARBIND6, BUNBIND6, BSTACK_SET => imm = 1,
                BVARREF => imm = 0, // plain Bvarref: index in opcode
                15 => imm = 2, // Bvarref7
                BVARSET7, BVARBIND7, BUNBIND7, BSTACK_SET2 => imm = 2,
                BCALL6, BLISTN => imm = 1,
                BCALL7 => imm = 2,
                BCONSTANT2 => imm = 2,
                BSTACK_REF6 => imm = 1,
                BSTACK_REF7 => imm = 2,
                else => {},
            }
            if (tgt) |t| {
                if (t >= opcodes.len) return Error.BadBytecode;
            }
            p += 1 + imm;
        }
    }

    const slot = try arena.reserve(4096);
    // Heap-allocate the emitter ALIGNED TO 16: Zig-0.16 codegen uses
    // vmovaps on the struct (needs 16-byte alignment); @alignOf(Emitter)
    // is only 8, so a plain create() can hand back an 8-mod-16 block -
    // exactly the fault seen in the deep-recursion scrapes.
    const emp_raw = std.heap.smp_allocator.alignedAlloc(
        Emitter, .@"16", 1) catch return Error.OutOfMemory;
    const emp: *Emitter = &emp_raw[0];
    defer std.heap.smp_allocator.free(emp_raw);
    emp.* = .{
        .buf = slot.w,
        .patches = .empty,
        .blocks = .init(std.heap.smp_allocator),
    };
    const em = &emp.*;

    // ---- prologue ----
    em.raw(0x55); // push rbp
    em.raw(0x48); em.raw(0x89); em.raw(0xE5); // mov rbp, rsp
    em.raw(0x41); em.raw(0x54); // push r12
    em.raw(0x41); em.raw(0x55); // push r13
    em.raw(0x41); em.raw(0x56); // push r14
    // Reserve the virtual stack frame sized to stack_depth, padded so
    // that rsp ends up 16-BYTE ALIGNED at call sites: entry rsp is
    // 8-mod-16 (post-call ABI), push rbp -> 0, three pushes -> 8, so the
    // sub must be 8-mod-16 to land at 0.  (Every freloc call from JIT
    // code entered C frames with misaligned rbp before this - the
    // vmovaps crashes in deep library loads.)
    const frame: u32 = (((stack_depth * 8) + 15) & ~@as(u32, 15)) + 8;
    em.raw(0x48); em.raw(0x81); em.raw(0xEC); em.imm32(@intCast(frame)); // sub rsp, imm32
    // r12 = top = the RESERVED frame's virtual stack, one below its
    // first slot (Bconstant does *++top).  The interpreter reuses its
    // own big stack; we use the frame we just reserved so pushes write
    // OUR memory, never the caller's args.
    em.raw(0x4C); em.raw(0x8B); em.raw(0xE4); // mov r12, rsp (8B: rm->reg, reg=r12 via REX.R)
    em.raw(0x49); em.raw(0x83); em.raw(0xEC); em.raw(8); // sub r12, 8: pushes land [r12+8] = [rsp], inside the reserved frame
    // r13 = [freloc_slot]
    em.movImm64(0, @intFromPtr(freloc_slot)); // mov rax, imm64
    em.raw(0x4C); em.raw(0x8B); em.raw(0x28); // mov r13, [rax] (REX.WR)
    // r14 = consts vector
    em.movImm64(14, @intFromPtr(consts_vec)); // mov r14, imm64 (REX.WB)

    // args setup: push args[0..arity] in order (each arg a stack slot,
    // top = last arg; rsi = args at entry).
    var ai: u32 = 0;
    while (ai < arity) : (ai += 1) {
        em.raw(0x48); em.raw(0x8B); em.raw(0x86); em.imm32(@intCast(ai * 8));
        em.pushRaxNoLoad();
    }

    // ---- body: decode loop ----
    var pc: u32 = 0;
    while (pc < opcodes.len) {
        try em.blocks.put(pc, em.pos);
        const b = opcodes[pc];
        pc += 1;
        if (b >= BCONSTANT_BASE) {
            const idx: u32 = b - BCONSTANT_BASE;
            em.pushConst(idx);
            continue;
        }
        switch (b) {
            BRETURN => {
                em.epilogueFromTos();
            },
            // ---- stack discipline ----
            BDUP => {
                // PUSH top[0]: rax=[r12]; [r12+8]=rax; r12+=8
                em.loadTosRax();
                em.pushRaxNoLoad();
            },
            BDISCARD => {
                // POP: r12 -= 8
                em.adjustTop(-8);
            },
            BSTACK_REF1, 2, 3, 4, BSTACK_REF5 => {
                const depth: u32 = b; // top[-depth] with depth = op
                em.pushStackRef(depth);
            },
            BSTACK_REF6 => {
                const d = fetch1(opcodes, pc) orelse return Error.BadBytecode;
                pc += 1;
                em.pushStackRef(d);
            },
            BSTACK_REF7 => {
                const d = fetch2(opcodes, pc) orelse return Error.BadBytecode;
                pc += 2;
                em.pushStackRef(d);
            },
            // ---- unary arith via freloc: POP v, TOP = fn(v) ----
            BSUB1 => em.unaryFreloc(IDX_SUB1),
            BADD1 => em.unaryFreloc(IDX_ADD1),
            BNEGATE => em.unaryFreloc(IDX_NEGATE),
            BCAR => em.unaryFreloc(IDX_CAR),
            BCDR => em.unaryFreloc(IDX_CDR),
            BNOT => em.unaryFreloc(IDX_EQ), // Bnot = eq nil per bytecode.c
            // ---- binary arith: POP v2, TOP=v1, TOP = fn(2,&newtop) ----
            BLENGTH => em.unaryFreloc(IDX_LENGTH),
            // ---- dynamic binding (let) support ----
            BSTACK_SET => {
                const d = fetch1(opcodes, pc) orelse return Error.BadBytecode;
                pc += 1;
                em.stackSet(d);
            },
            BSTACK_SET2 => {
                const d = fetch2(opcodes, pc) orelse return Error.BadBytecode;
                pc += 2;
                em.stackSet(d);
            },
            BVARSET, 17, 18, 19, 20, BVARSET5 => {
                // index encoded in opcode (op - Bvarset); no immediate.
                em.varsetConst(b - BVARSET);
            },
            BVARSET6 => {
                const idx = fetch1(opcodes, pc) orelse return Error.BadBytecode;
                pc += 1;
                em.varsetConst(idx);
            },
            BVARSET7 => {
                const idx = fetch2(opcodes, pc) orelse return Error.BadBytecode;
                pc += 2;
                em.varsetConst(idx);
            },
            BVARBIND, 25, 26, 27, 28, BVARBIND5 => {
                em.varbindConst(b - BVARBIND);
            },
            BVARBIND6 => {
                const idx = fetch1(opcodes, pc) orelse return Error.BadBytecode;
                pc += 1;
                em.varbindConst(idx);
            },
            BVARBIND7 => {
                const idx = fetch2(opcodes, pc) orelse return Error.BadBytecode;
                pc += 2;
                em.varbindConst(idx);
            },
            BUNBIND, 41, 42, 43, 44, BUNBIND5 => {
                em.unbindN(b - BUNBIND);
            },
            BUNBIND6 => {
                const n = fetch1(opcodes, pc) orelse return Error.BadBytecode;
                pc += 1;
                em.unbindN(n);
            },
            BUNBIND7 => {
                const n = fetch2(opcodes, pc) orelse return Error.BadBytecode;
                pc += 2;
                em.unbindN(n);
            },
            BCONCAT2 => em.binaryFreloc(IDX_CONCAT),
            BCONCAT3 => em.ternaryFreloc(IDX_CONCAT),
            BCONCAT4 => em.quatFreloc(IDX_CONCAT),
            BLISTN => {
                const n = fetch1(opcodes, pc) orelse return Error.BadBytecode;
                pc += 1;
                em.naryFreloc(IDX_LIST, n);
            },
            BEQLSIGN => em.binaryFreloc(IDX_EQLSIGN),
            BGTR => em.binaryFreloc(IDX_GTR),
            BLSS => em.binaryFreloc(IDX_LSS),
            BLEQ => em.binaryFreloc(IDX_LEQ),
            BGEQ => em.binaryFreloc(IDX_GEQ),
            BPLUS => em.binaryFreloc(IDX_PLUS),
            BDIFF => em.binaryFreloc(IDX_MINUS),
            BMULT => em.binaryFreloc(IDX_TIMES),
            BCONS => em.binaryFreloc(IDX_CONS),
            // ---- calls: POP n args + fun -> freloc FUNCALL(n+1,&fun) ----
            BCALL, 33, 34, 35, 36, BCALL5 => {
                em.callFrelocN(@intCast(b - BCALL));
            },
            BCALL6 => {
                const n = fetch1(opcodes, pc) orelse return Error.BadBytecode;
                pc += 1;
                em.callFrelocN(n);
            },
            BCALL7 => {
                const n = fetch2(opcodes, pc) orelse return Error.BadBytecode;
                pc += 2;
                em.callFrelocN(n);
            },
            BVARREF, 9, 10, 11, 12, 13 => {
                // Bvarref..Bvarref5: the const index is ENCODED IN THE
                // OPCODE (op - Bvarref); NO immediate byte.  (The old
                // fetch1 here consumed the NEXT byte as a bogus index -
                // varref consts[196] garbage -> symbolp errors.)
                em.varrefConst(b - 8);
            },
            // ---- branches ----
            BGOTO => {
                const t = fetch2(opcodes, pc) orelse return Error.BadBytecode;
                pc += 2;
                em.emitJump(t);
            },
            BGOTOIFNIL, BGOTOIFNONNIL => {
                const t = fetch2(opcodes, pc) orelse return Error.BadBytecode;
                pc += 2;
                em.condJump(t, b == BGOTOIFNIL);
            },
            BGOTOIFNILELSEPOP, BGOTOIFNONNILELSEPOP => {
                const t = fetch2(opcodes, pc) orelse return Error.BadBytecode;
                pc += 2;
                em.condJumpKeep(t, b == BGOTOIFNILELSEPOP);
            },
            else => return Error.UnsupportedOpcode,
        }
    }
    if (pc != opcodes.len) return Error.BadBytecode;

    // ---- patch pass: resolve every branch to its block's code offset.
    // rel32 = target_code - (patch_site + 4).
    for (em.patches.items) |p| {
        const target_code = em.blocks.get(p.target_bc) orelse
            return Error.BadBytecode; // branch to a non-instruction offset
        const rel: i64 = @as(i64, target_code) - @as(i64, p.at + 4);
        std.mem.writeInt(i32, slot.w[p.at..][0..4], @intCast(rel), .little);
    }

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

    const res = try compile(&arena, &opcodes, 8, freloc_slot, consts_ptr, 0);
    try testing.expect(res.rejected == null);

    // Call: entry(0, args) — args unused by this bytecode.
    var args: [1]u64 = .{0};
    const got = res.entry(0, &args);
    try testing.expectEqual(@as(u64, 42), got);
}

test "compile and run: arithmetic via freloc (fib-shape call)" {
    var arena = try jit.ExecArena.allocate(jit.page_size);
    defer arena.deinit();

    // A C-ABI freloc shim implementing funcall/plus/sub1 semantics over
    // plain fixnums (tagged <<3 with LSB-tag 0 like Lisp_Int0=0? Here we
    // just use raw words; the shim proves the CALL PATH).
    const Shim = struct {
        fn funcall(n: i64, args: [*]const u64) callconv(.c) u64 {
            // last arg = "function" word; here functions are small ints:
            // f=2 -> recursive identity chain: sum of args[0..n-1]
            var sum: u64 = 0;
            var i: u64 = 0;
            const nargs: u64 = @intCast(@max(n - 1, 0));
            while (i < nargs) : (i += 1) sum += args[i];
            return sum + 100; // marker to prove the call happened
        }
        fn plus(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            return args[0] +% args[1];
        }
    };
    var freloc_table = [_]*const anyopaque{ undefined, &Shim.funcall, undefined, &Shim.plus };
    var freloc_base: *const anyopaque = &freloc_table;
    const freloc_slot: *const *const anyopaque = &freloc_base;

    // bytecode: Bconstant 0 pushes consts[0]=30; Bconstant 1 pushes
    // consts[1]=12; Bplus; Breturn.
    const opcodes = [_]u8{ 0xC0, 0xC0 + 1, BPLUS, BRETURN };
    var consts = [_]u64{ 30, 12 };
    const res = try compile(&arena, &opcodes, 8, freloc_slot, &consts, 0);
    var args: [1]u64 = .{0};
    const got = res.entry(0, &args);
    try testing.expectEqual(@as(u64, 42), got);
}

test "compile and run: loop with branch (countdown)" {
    var arena = try jit.ExecArena.allocate(jit.page_size);
    defer arena.deinit();

    // freloc: IDX_SUB1(6) = a C shim decrementing a fixnum word.
    const Shim = struct {
        fn sub1(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            return args[0] -% 1;
        }
    };
    var freloc_table = [_]*const anyopaque{ undefined, undefined, undefined, undefined, undefined, undefined, &Shim.sub1 };
    var freloc_base: *const anyopaque = &freloc_table;
    const freloc_slot: *const *const anyopaque = &freloc_base;

    // countdown(n): [0] Bstack_ref 1? -- layout: arg slots live below the
    // virtual stack base in the interpreter; for the J4 integration the
    // shim copies args in.  Here we simulate a 0-arg fn whose TOS is the
    // counter: bytecode:
    //   Bconstant 0 (n)   ; push 10
    // L: Bdup             ; 10 10
    //    Bgotoifnonnil L2? -- instead simple: Bsub1 pops v pushes v-1,
    //    then Bgotoifnil(non-nil loop) back to L when nonzero.
    // Simplest executable loop:
    //   0: Bconstant(0)=10
    //   1: L: Bsub1
    //   3: Bdup
    //   4: Bgotoifnonnil -> L   (loops until 0)
    //   6: Breturn         (returns the 0 / final dup)
    const opcodes = [_]u8{
        0xC0,             // 0: push consts[0]=10
        BSUB1,            // 1: L: top--
        BDUP,             // 2: dup
        BGOTOIFNONNIL,    // 3: branch imm16=1 (L) -- condJump POPs the dup
        1, 0,             //    little-endian target=1
        BRETURN,          // 5: top = the countdown result (0)
    };
    var consts = [_]u64{10};
    const res = try compile(&arena, &opcodes, 8, freloc_slot, &consts, 0);
    var args: [1]u64 = .{0};
    const got = res.entry(0, &args);
    // loop runs 10 decrements -> final top = 0
    try testing.expectEqual(@as(u64, 0), got);
}

// ---------------------------------------------------------------------------
// C ABI: the entry src/compz.c's hotness shim calls.  freloc_slot points
// at a C-side pointer-to-table (compz.c exposes zeln_freloc.link_table
// through a stable address).  Returns null when the bytecode uses opcodes
// outside the supported subset (caller silently falls back to the
// interpreter).
// ---------------------------------------------------------------------------

/// ONE shared arena for all compiled entries: each compile reserves a
/// 4 KiB region from it.  (The earlier per-compile allocation leaked
/// 256 KiB per closure and exhausted memory after a few thousand
/// compiles - the serialize phase walks 1547 files and hit exactly
/// that, crashing inside the emitter's HashMap init under exhaustion.)
/// The arena grows by reallocation only when full; entries are never
/// freed (bounded by the hot-closure count, and the process reclaims
/// everything at exit).
var g_arena: ?jit.ExecArena = null;

export fn zeln_jit_compile_closure(
    bc: [*]const u8,
    bc_len: usize,
    stack_depth: u32,
    arity: u32,
    consts: [*]const u64,
    freloc_slot: *const *const anyopaque,
) ?*const fn (i64, [*]const u64) callconv(.c) u64 {
    if (g_arena == null)
        g_arena = jit.ExecArena.allocate(4 * 1024 * 1024) catch return null;
    const res = compile(&g_arena.?, bc[0..bc_len], stack_depth, freloc_slot, consts, arity) catch return null;
    return res.entry;
}
