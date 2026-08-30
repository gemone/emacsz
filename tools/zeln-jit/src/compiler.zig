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
const builtin = @import("builtin");
const jit = @import("jit.zig");

// Windows cannot unwind JIT frames from metadata embedded in read-only
// sections: every generated function must have a RUNTIME_FUNCTION that
// covers its prologue.  Without this, a Lisp error signaled by a freloc
// helper can enter the debugger/error printer, stack walk through the
// JIT frame, and abort while trying to unwind undocumented executable
// memory.  Linux/macOS use frame-pointer or DWARF-compatible unwinding
// and do not need this table.
const win_unwind = struct {
    const RUNTIME_FUNCTION = extern struct {
        begin_rva: u32,
        end_rva: u32,
        unwind_rva: u32,
    };

    const UWOP_PUSH_NONVOL: u16 = 0;
    const UWOP_ALLOC_SMALL: u16 = 2;
    const UWOP_ALLOC_LARGE: u16 = 1;

    extern "kernel32" fn RtlAddFunctionTable(
        function_table: [*]RUNTIME_FUNCTION,
        entry_count: u32,
        base_address: usize,
    ) callconv(.c) ?*anyopaque;

    extern "kernel32" fn RtlDeleteFunctionTable(
        callback: ?*anyopaque,
    ) callconv(.c) i32;
};

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
pub const IDX_MAX: u64 = 9;
pub const IDX_MIN: u64 = 10;
pub const IDX_EQLSIGN: u64 = 11;
pub const IDX_GTR: u64 = 12;
pub const IDX_LSS: u64 = 13;
pub const IDX_LEQ: u64 = 14;
pub const IDX_GEQ: u64 = 15;
pub const IDX_EQUAL: u64 = 16;
pub const IDX_EQ: u64 = 17;
pub const IDX_NULL: u64 = 18;
pub const IDX_CAR: u64 = 19;
pub const IDX_CDR: u64 = 20;
pub const IDX_CONS: u64 = 21;
pub const IDX_LIST1: u64 = 22;
pub const IDX_LIST2: u64 = 23;
pub const IDX_LIST3: u64 = 24;
pub const IDX_LIST4: u64 = 25;
pub const IDX_LIST: u64 = 26;
pub const IDX_SYMBOLP: u64 = 27;
pub const IDX_CONSP: u64 = 28;
pub const IDX_STRINGP: u64 = 29;
pub const IDX_LISTP: u64 = 30;
pub const IDX_NUMBERP: u64 = 31;
pub const IDX_INTEGERP: u64 = 32;
pub const IDX_NTH: u64 = 33;
pub const IDX_MEMQ: u64 = 34;
pub const IDX_LENGTH: u64 = 35;
pub const IDX_AREF: u64 = 36;
pub const IDX_ASET: u64 = 37;
pub const IDX_SYMBOL_VALUE: u64 = 38;
pub const IDX_SYMBOL_FUNCTION: u64 = 39;
pub const IDX_SET: u64 = 40;
pub const IDX_FSET: u64 = 41;
pub const IDX_GET: u64 = 42;
pub const IDX_SUBSTRING: u64 = 43;
pub const IDX_CONCAT: u64 = 44;
pub const IDX_STRING_EQUAL: u64 = 45;
pub const IDX_STRING_LESSP: u64 = 46;
pub const IDX_NTHCDR: u64 = 47;
pub const IDX_ELT: u64 = 48;
pub const IDX_MEMBER: u64 = 49;
pub const IDX_ASSQ: u64 = 50;
pub const IDX_NREVERSE: u64 = 51;
pub const IDX_SETCAR: u64 = 52;
pub const IDX_SETCDR: u64 = 53;
pub const IDX_CAR_SAFE: u64 = 54;
pub const IDX_CDR_SAFE: u64 = 55;
pub const IDX_NCONC: u64 = 56;
pub const IDX_QUO: u64 = 57;
pub const IDX_REM: u64 = 58;
pub const IDX_GOTO_CHAR: u64 = 59;
pub const IDX_INSERT: u64 = 60;
pub const IDX_CHAR_AFTER: u64 = 61;
pub const IDX_INDENT_TO: u64 = 62;
pub const IDX_FORWARD_CHAR: u64 = 63;
pub const IDX_FORWARD_WORD: u64 = 64;
pub const IDX_FORWARD_LINE: u64 = 65;
pub const IDX_CHAR_SYNTAX: u64 = 66;
pub const IDX_END_OF_LINE: u64 = 67;
pub const IDX_MATCH_BEGINNING: u64 = 68;
pub const IDX_MATCH_END: u64 = 69;
pub const IDX_UPCASE: u64 = 70;
pub const IDX_DOWNCASE: u64 = 71;
pub const IDX_POINT: u64 = 72;
pub const IDX_POINT_MAX: u64 = 73;
pub const IDX_POINT_MIN: u64 = 74;
pub const IDX_FOLLOWING_CHAR: u64 = 75;
pub const IDX_PRECEDING_CHAR: u64 = 76;
pub const IDX_CURRENT_COLUMN: u64 = 77;
pub const IDX_EOLP: u64 = 78;
pub const IDX_EOBP: u64 = 79;
pub const IDX_BOLP: u64 = 80;
pub const IDX_BOBP: u64 = 81;
pub const IDX_CURRENT_BUFFER: u64 = 82;
pub const IDX_SET_BUFFER: u64 = 83;
pub const IDX_SKIP_CHARS_FORWARD: u64 = 84;
pub const IDX_SKIP_CHARS_BACKWARD: u64 = 85;
pub const IDX_BUFFER_SUBSTRING: u64 = 86;
pub const IDX_DELETE_REGION: u64 = 87;
pub const IDX_NARROW_TO_REGION: u64 = 88;
pub const IDX_WIDEN: u64 = 89;
pub const IDX_SET_MARKER: u64 = 90;
pub const IDX_VARSET: u64 = 91;
pub const IDX_VARBIND: u64 = 92;
pub const IDX_UNBIND: u64 = 93;
pub const IDX_SAVE_EXCURSION: u64 = 94;
pub const IDX_SAVE_CURRENT_BUFFER: u64 = 95;
pub const IDX_SAVE_RESTRICTION: u64 = 96;
pub const IDX_UNWIND_PROTECT: u64 = 97;
pub const IDX_PUSHHANDLER: u64 = 98;
pub const IDX_RESUME: u64 = 99;
pub const IDX_POPHANDLER: u64 = 100;
pub const IDX_SWITCH_TARGET: u64 = 101;
pub const IDX_JIT_CALL: u64 = 102;

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
const BMAX: u8 = 93;
const BMIN: u8 = 94;
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
const BDISCARD_N: u8 = 182; // 0266: bit 7 preserves TOP while discarding
const BSWITCH: u8 = 183; // 0267: TOS=jump-table, below=TOS=key
const BCONSTANT_BASE: u8 = 192;

// ---- M1/M2 opcodes shared with zeln-compile and lowered through the
// frozen freloc surface.  Octal source values were converted to decimal. ----
const BPOPHANDLER: u8 = 48;
const BNTH: u8 = 56;
const BSYMBOLP: u8 = 57;
const BCONSP: u8 = 58;
const BSTRINGP: u8 = 59;
const BLISTP: u8 = 60;
const BEQ: u8 = 61;
const BMEMQ: u8 = 62;
const BLIST1: u8 = 67;
const BLIST2: u8 = 68;
const BLIST3: u8 = 69;
const BLIST4: u8 = 70;
const BAREF: u8 = 72;
const BASET: u8 = 73;
const BSYMBOL_VALUE: u8 = 74;
const BSYMBOL_FUNCTION: u8 = 75;
const BSET: u8 = 76;
const BFSET: u8 = 77;
const BGET: u8 = 78;
const BSUBSTRING: u8 = 79;
const BPOINT: u8 = 96;
const BGOTO_CHAR: u8 = 98;
const BINSERT: u8 = 99;
const BPOINT_MAX: u8 = 100;
const BPOINT_MIN: u8 = 101;
const BCHAR_AFTER: u8 = 102;
const BFOLLOWING_CHAR: u8 = 103;
const BPRECEDING_CHAR: u8 = 104;
const BCURRENT_COLUMN: u8 = 105;
const BINDENT_TO: u8 = 106;
const BEOLP: u8 = 108;
const BEOBP: u8 = 109;
const BBOLP: u8 = 110;
const BBOBP: u8 = 111;
const BCURRENT_BUFFER: u8 = 112;
const BSET_BUFFER: u8 = 113;
const BSAVE_CURRENT_BUFFER: u8 = 114;
const BFORWARD_CHAR: u8 = 117;
const BFORWARD_WORD: u8 = 118;
const BSKIP_CHARS_FORWARD: u8 = 119;
const BSKIP_CHARS_BACKWARD: u8 = 120;
const BFORWARD_LINE: u8 = 121;
const BCHAR_SYNTAX: u8 = 122;
const BBUFFER_SUBSTRING: u8 = 123;
const BDELETE_REGION: u8 = 124;
const BNARROW_TO_REGION: u8 = 125;
const BWIDEN: u8 = 126;
const BEND_OF_LINE: u8 = 127;
const BSAVE_EXCURSION: u8 = 138;
const BSAVE_RESTRICTION: u8 = 140;
const BUNWIND_PROTECT: u8 = 142;
const BSET_MARKER: u8 = 147;
const BMATCH_BEGINNING: u8 = 148;
const BMATCH_END: u8 = 149;
const BUPCASE: u8 = 150;
const BDOWNCASE: u8 = 151;
const BSTRINGEQLSIGN: u8 = 152;
const BSTRINGLSS: u8 = 153;
const BEQUAL: u8 = 154;
const BNTHCDR: u8 = 155;
const BELT: u8 = 156;
const BMEMBER: u8 = 157;
const BASSQ: u8 = 158;
const BNREVERSE: u8 = 159;
const BSETCAR: u8 = 160;
const BSETCDR: u8 = 161;
const BCAR_SAFE: u8 = 162;
const BCDR_SAFE: u8 = 163;
const BNCONC: u8 = 164;
const BQUO: u8 = 165;
const BREM: u8 = 166;
const BNUMBERP: u8 = 167;
const BINTEGERP: u8 = 168;
const BCONCATN: u8 = 176;
const BINSERTN: u8 = 177;

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
    UnsupportedPlatform,
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

/// Write and register a minimal WinX64 unwind record for one JIT entry.
/// The generated prologue is fixed: push rbp/r12/r13/r14, then
/// `sub rsp, total_frame`.  We describe those operations in reverse
/// execution order as required by the Windows unwinder.
fn registerWindowsUnwind(
    arena: *jit.ExecArena,
    slot: jit.ExecArena.Slot,
    code_size: u32,
    total_frame: u32,
) Error!void {
    if (builtin.os.tag != .windows or builtin.cpu.arch != .x86_64) return;

    // Large frame allocation consumes two unwind-code slots, plus four
    // pushes.  Five slots only covered the small-frame special case.
    var codes: [6]u16 = undefined;
    var count: usize = 0;
    if (total_frame == 0 or (total_frame & 7) != 0) return Error.BadBytecode;
    if (total_frame <= 128) {
        codes[count] = (win_unwind.UWOP_ALLOC_SMALL << 12) | @as(u16, @intCast(total_frame / 8 - 1));
        count += 1;
    } else if (total_frame <= 65536) {
        codes[count] = win_unwind.UWOP_ALLOC_LARGE << 12;
        count += 1;
        codes[count] = @intCast(total_frame / 8);
        count += 1;
    } else {
        // The emitter's `sub rsp, imm32` supports larger frames, but the
        // compact unwind encoding does not.  Such functions remain on the
        // interpreter rather than risking an unwinnable JIT frame.
        return Error.UnsupportedPlatform;
    }
    // Unwind codes are reverse-execution ordered.  The sub runs last,
    // so it is described first, followed by the four pushes.
    codes[count] = (win_unwind.UWOP_PUSH_NONVOL << 12) | 14;
    count += 1;
    codes[count] = (win_unwind.UWOP_PUSH_NONVOL << 12) | 13;
    count += 1;
    codes[count] = (win_unwind.UWOP_PUSH_NONVOL << 12) | 12;
    count += 1;
    codes[count] = (win_unwind.UWOP_PUSH_NONVOL << 12) | 5;
    count += 1;

    const rf_offset = std.mem.alignForward(u32, code_size, @alignOf(win_unwind.RUNTIME_FUNCTION));
    const info_offset = rf_offset + @sizeOf(win_unwind.RUNTIME_FUNCTION);
    const info_size = 4 + ((count + 1) & ~@as(usize, 1)) * 2; // count is padded to even slots.
    const needed = info_offset + info_size;
    if (needed > slot.w.len) return Error.OutOfMemory;

    const rf: *win_unwind.RUNTIME_FUNCTION = @ptrCast(@alignCast(slot.w[rf_offset..].ptr));
    rf.* = .{
        .begin_rva = 0,
        .end_rva = code_size,
        .unwind_rva = info_offset,
    };

    const info = slot.w[info_offset..needed];
    info[0] = 1; // UNW_VERSION 1, no flags/handler
    info[1] = 17; // prologue size: 1+3+2+2+2+6+1? fixed prologue is 17 bytes
    info[2] = @intCast(count);
    info[3] = 0; // no frame-register chain (nonvolatile pushes are sufficient)
    for (codes[0..count], 0..) |code, i| {
        std.mem.writeInt(u16, info[4 + i * 2 ..][0..2], code, .little);
    }
    if ((count & 1) != 0) {
        std.mem.writeInt(u16, info[4 + count * 2 ..][0..2], 0, .little);
    }

    const id = win_unwind.RtlAddFunctionTable(@ptrCast(rf), 1, @intFromPtr(slot.x));
    if (id == null)
        return Error.OutOfMemory;
    arena.addUnwindId(id) catch {
        _ = win_unwind.RtlDeleteFunctionTable(id);
        return Error.OutOfMemory;
    };
}

/// One pending branch fixup: code offset -> bytecode target.
const Patch = struct { at: u32, target_bc: u32 };

/// A jump inside one generated function.  Unlike `Patch`, the target is
/// a locally allocated label rather than an Emacs bytecode offset.
const LocalJump = struct {
    at: u32,
    label: u32,
    kind: enum { jmp, je, jne, jg, jl, jle, jge, jo },
};

const Emitter = struct {
    allocator: std.mem.Allocator,
    buf: []u8,
    pos: u32 = 0,
    patches: std.ArrayList(Patch),
    local_jumps: std.ArrayList(LocalJump) = .empty,
    local_labels: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    next_local_label: u32 = 0,
    /// bytecode offset -> code offset
    blocks: std.AutoHashMap(u32, u32),
    /// Calling convention of the HOST process (the C caller and the
    /// freloc helpers): SysV (rdi/rsi) on Linux/macOS, WinX64 (rcx/rdx)
    /// on Windows -- mingw and MSVC both use the Microsoft x64 ABI, so
    /// the generated entry convention and every freloc call must place
    /// (nargs, args) in the ABI's first two argument registers.
    win64: bool = false,
    /// Canonical Qt raw Lisp word, supplied by the runtime.  Tests may use 0
    /// when they do not execute tagged comparisons.
    qt_raw: u64 = 0,
    overflow: bool = false,

    fn need(self: *Emitter, count: u32) void {
        const end: usize = @as(usize, self.pos) + count;
        if (end > self.buf.len) self.overflow = true;
    }

    /// mov <arg1reg>, imm32   (rdi on SysV, ecx on WinX64)
    fn loadArg1Imm(self: *Emitter, n: i32) void {
        if (self.win64) {
            self.raw(0x48);
            self.raw(0xC7);
            self.raw(0xC1);
            self.imm32(n); // mov rcx,n
        } else {
            self.raw(0x48);
            self.raw(0xC7);
            self.raw(0xC7);
            self.imm32(n); // mov rdi,n
        }
    }
    /// mov <arg2reg>, r12   (rsi on SysV, rdx on WinX64)
    fn loadArg2R12(self: *Emitter) void {
        if (self.win64) {
            self.raw(0x4C);
            self.raw(0x89);
            self.raw(0xE2); // mov rdx,r12
        } else {
            self.raw(0x4C);
            self.raw(0x89);
            self.raw(0xE6); // mov rsi,r12
        }
    }

    /// mov <arg2reg>, rsp+32   (the scratch pair address)
    fn loadArg2Scratch(self: *Emitter) void {
        if (self.win64) {
            self.raw(0x48);
            self.raw(0x8D);
            self.raw(0x54);
            self.raw(0x24);
            self.raw(32); // lea rdx,[rsp+32]
        } else {
            self.raw(0x48);
            self.raw(0x8D);
            self.raw(0x74);
            self.raw(0x24);
            self.raw(32); // lea rsi,[rsp+32]
        }
    }

    fn raw(self: *Emitter, b: u8) void {
        self.need(1);
        if (self.overflow) return;
        self.buf[self.pos] = b;
        self.pos += 1;
    }
    fn imm32(self: *Emitter, v: i32) void {
        self.need(4);
        if (self.overflow) return;
        std.mem.writeInt(i32, self.buf[self.pos..][0..4], v, .little);
        self.pos += 4;
    }
    fn imm64(self: *Emitter, v: u64) void {
        self.need(8);
        if (self.overflow) return;
        std.mem.writeInt(u64, self.buf[self.pos..][0..8], v, .little);
        self.pos += 8;
    }
    // ---- emit primitives (all REX-verified; see the two bug notes in
    //      git history: REX.R extends REG, REX.B extends R/M) ----

    /// rax = [r12]
    fn loadTosRax(self: *Emitter) void {
        self.raw(0x49);
        self.raw(0x8B);
        self.raw(0x04);
        self.raw(0x24);
    }
    /// [r12+8] = rax; r12 += 8  (PUSH rax, TOS already in rax)
    fn pushRaxNoLoad(self: *Emitter) void {
        self.raw(0x49);
        self.raw(0x89);
        self.raw(0x44);
        self.raw(0x24);
        self.raw(8);
        self.raw(0x49);
        self.raw(0x83);
        self.raw(0xC4);
        self.raw(8);
    }
    /// r12 += delta bytes
    fn adjustTop(self: *Emitter, delta: i32) void {
        // Keep -128 in the imm32 path: its positive magnitude would not fit
        // back into an i8 when forming the x86 displacement byte.
        if (delta >= -127 and delta <= 127) {
            const imm8: i8 = @intCast(delta);
            if (imm8 < 0) {
                self.raw(0x49);
                self.raw(0x83);
                self.raw(0xEC);
                self.raw(@intCast(-imm8));
            } else {
                self.raw(0x49);
                self.raw(0x83);
                self.raw(0xC4);
                self.raw(@intCast(imm8));
            }
        } else {
            // BdiscardN with a 127-slot count (and listN/call forms in
            // general) can move r12 by far more than an imm8 can encode.
            if (delta < 0) {
                self.raw(0x49);
                self.raw(0x81);
                self.raw(0xEC);
                self.imm32(-delta);
            } else {
                self.raw(0x49);
                self.raw(0x81);
                self.raw(0xC4);
                self.imm32(delta);
            }
        }
    }
    /// PUSH consts[idx]: mov rax,[r14 + idx*8] with disp8/disp32 as
    /// needed (idx*8 overflows disp8's signed range at idx 16).
    fn pushConst(self: *Emitter, idx: u32) void {
        const disp: i32 = @intCast(idx * 8);
        if (disp < 128) {
            self.raw(0x49);
            self.raw(0x8B);
            self.raw(0x46);
            self.raw(@intCast(disp));
        } else {
            // mod=10 (disp32), rm=110 r14-with-REXB: 8B /r with SIB-free
            self.raw(0x49);
            self.raw(0x8B);
            self.raw(0x86);
            self.imm32(disp);
        }
        self.pushRaxNoLoad();
    }
    /// PUSH top[-depth]
    fn pushStackRef(self: *Emitter, depth: u32) void {
        // rax = [r12 - depth*8]
        self.raw(0x49);
        self.raw(0x8B);
        self.raw(0x84);
        self.raw(0x24);
        self.imm32(-@as(i32, @intCast(depth * 8)));
        self.pushRaxNoLoad();
    }
    /// call [r13 + idx*8] with rdi=n, rsi=ptr; rax = result.
    /// disp32 form (mod=10): the real surface reaches idx 39+
    /// (SYMBOL_VALUE = 312 bytes) which overflows disp8's signed
    /// range - the leftover disp8 form here was the loaddefs RIP=0
    /// crash (gdb: mov 0x18(%r13),%rax reading a wrong/nul slot).
    fn frelocCall(self: *Emitter, idx: u64) void {
        self.raw(0x49);
        self.raw(0x8B);
        self.raw(0x85);
        self.imm32(@intCast(idx * 8));
        self.raw(0xFF);
        self.raw(0xD0); // call rax
    }
    /// unary: v=[r12]; arg1=1; arg2=r12; rax=fn(1,r12); [r12]=rax
    fn unaryFreloc(self: *Emitter, idx: u64) void {
        self.loadArg1Imm(1);
        self.loadArg2R12();
        self.frelocCall(idx);
        self.raw(0x49);
        self.raw(0x89);
        self.raw(0x04);
        self.raw(0x24); // [r12]=rax
    }
    /// binary: v2=[r12]; r12-=8; arg1=2; arg2=r12; rax=fn(2,r12); [r12]=rax
    fn binaryFreloc(self: *Emitter, idx: u64) void {
        self.adjustTop(-8);
        self.loadArg1Imm(2);
        self.loadArg2R12();
        self.frelocCall(idx);
        self.raw(0x49);
        self.raw(0x89);
        self.raw(0x04);
        self.raw(0x24);
    }
    /// n-ary (concat/listN): pop n values, call fn(n, base), push result.
    fn naryFreloc(self: *Emitter, idx: u64, n: u32) void {
        self.adjustTop(-@as(i32, @intCast((n - 1) * 8)));
        self.loadArg1Imm(@intCast(n));
        self.loadArg2R12();
        self.frelocCall(idx);
        self.raw(0x49);
        self.raw(0x89);
        self.raw(0x04);
        self.raw(0x24);
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
        self.raw(0x49);
        self.raw(0x8B);
        self.raw(0xD4); // mov rdx,r12
        self.raw(0x48);
        self.raw(0x81);
        self.raw(0xEA);
        self.imm32(@intCast(depth * 8)); // sub rdx,depth*8
        self.raw(0x48);
        self.raw(0x89);
        self.raw(0x02); // [rdx] = rax
        self.adjustTop(-8); // POP
    }
    /// Bvarset: set_internal(a[0]=symbol, a[1]=value).  The pair lives in
    /// the prologue's scratch area at [rsp+32]=symbol, [rsp+40]=value -
    /// ABOVE the WinX64 shadow space (callee homes trash [rsp..rsp+32))
    /// and never below rsp (the call's return-address push used to
    /// clobber a [rsp-8] scratch word).
    fn varsetConst(self: *Emitter, idx: u32) void {
        // rax = value = [r12] -> [rsp+40]
        self.loadTosRax();
        self.raw(0x48);
        self.raw(0x89);
        self.raw(0x44);
        self.raw(0x24);
        self.raw(40); // [rsp+40]=rax
        // rax = consts[idx] (symbol) -> [rsp+32]
        const disp: i32 = @intCast(idx * 8);
        if (disp < 128) {
            self.raw(0x49);
            self.raw(0x8B);
            self.raw(0x46);
            self.raw(@intCast(disp));
        } else {
            self.raw(0x49);
            self.raw(0x8B);
            self.raw(0x86);
            self.imm32(disp);
        }
        self.raw(0x48);
        self.raw(0x89);
        self.raw(0x44);
        self.raw(0x24);
        self.raw(32); // [rsp+32]=rax
        // call set_internal(2, rsp+32)
        self.loadArg1Imm(2);
        self.loadArg2Scratch();
        self.frelocCall(IDX_VARSET);
        self.adjustTop(-8); // POP
    }
    /// Bvarbind: specbind(a[0]=symbol, a[1]=value) - same scratch pair.
    fn varbindConst(self: *Emitter, idx: u32) void {
        self.loadTosRax();
        self.raw(0x48);
        self.raw(0x89);
        self.raw(0x44);
        self.raw(0x24);
        self.raw(40); // [rsp+40]=value
        const disp: i32 = @intCast(idx * 8);
        if (disp < 128) {
            self.raw(0x49);
            self.raw(0x8B);
            self.raw(0x46);
            self.raw(@intCast(disp));
        } else {
            self.raw(0x49);
            self.raw(0x8B);
            self.raw(0x86);
            self.imm32(disp);
        }
        self.raw(0x48);
        self.raw(0x89);
        self.raw(0x44);
        self.raw(0x24);
        self.raw(32); // [rsp+32]=symbol
        self.loadArg1Imm(2);
        self.loadArg2Scratch();
        self.frelocCall(IDX_VARBIND);
        self.adjustTop(-8);
    }
    /// Bunbind n: unbind_to(specpdl_count - n).  The zeln_unbind shim
    /// takes (n, &n) - C computes the specpdl arithmetic.
    fn unbindN(self: *Emitter, n: u32) void {
        self.loadArg1Imm(@intCast(n));
        self.loadArg2R12();
        self.frelocCall(IDX_UNBIND);
    }

    /// PUSH fn(): buffer-point predicates and accessors with no stack args.
    fn push0Freloc(self: *Emitter, idx: u64) void {
        self.loadArg1Imm(0);
        self.loadArg2R12();
        self.frelocCall(idx);
        self.pushRaxNoLoad();
    }

    /// fn(0), discard result: specpdl-affecting operations (save-excursion,
    /// widen, pop-handler).  The helper result is deliberately ignored.
    fn noargFreloc(self: *Emitter, idx: u64) void {
        self.loadArg1Imm(0);
        self.loadArg2R12();
        self.frelocCall(idx);
    }

    /// POP handler; fn(1,&oldtop), discard result (Bunwind_protect).
    fn unaryPopFreloc(self: *Emitter, idx: u64) void {
        self.frelocCall(idx);
        self.adjustTop(-8);
    }
    /// Bcall n: fp = r12 - n*8 (fun below args); r12 = fp; FUNCALL(n+1, fp);
    /// [fp] = rax; r12 = fp (top = result)
    fn callFrelocN(self: *Emitter, idx: u64, n: u32) void {
        // arg1 = n+1, arg2 = r12 - n*8 (args+fun group base)
        self.loadArg1Imm(@intCast(n + 1));
        // arg2 = r12; arg2 -= n*8
        self.loadArg2R12();
        if (self.win64) {
            self.raw(0x48);
            self.raw(0x81);
            self.raw(0xEA);
            self.imm32(@intCast(n * 8)); // sub rdx,n*8
        } else {
            self.raw(0x48);
            self.raw(0x81);
            self.raw(0xEE);
            self.imm32(@intCast(n * 8)); // sub rsi,n*8
        }
        self.frelocCall(idx);
        // [r12 - n*8] = rax ; r12 -= n*8
        self.raw(0x49);
        self.raw(0x89);
        self.raw(0x84);
        self.raw(0x24);
        self.imm32(-@as(i32, @intCast(n * 8)));
        self.adjustTop(-@as(i32, @intCast(n * 8)));
    }
    /// jmp to bytecode target (patched later)
    fn emitJump(self: *Emitter, target_bc: u32) Error!void {
        self.raw(0xE9);
        self.patches.append(self.allocator, .{ .at = self.pos, .target_bc = target_bc }) catch return Error.OutOfMemory;
        self.imm32(0);
    }
    /// POP v; if (v == 0) [nil when want_nil] jump; else fallthrough
    fn condJump(self: *Emitter, target_bc: u32, want_nil: bool) Error!void {
        // rax = [r12]; r12 -= 8; test rax,rax; jz/jnz patch
        self.loadTosRax();
        self.adjustTop(-8);
        self.raw(0x48);
        self.raw(0x85);
        self.raw(0xC0); // test rax,rax
        // two-byte jcc rel32: 0F 84 (jz) / 0F 85 (jnz); the one-byte
        // 74/75 forms carry only rel8 and would truncate our rel32.
        self.raw(0x0F);
        self.raw(if (want_nil) 0x84 else 0x85);
        self.patches.append(self.allocator, .{ .at = self.pos, .target_bc = target_bc }) catch return Error.OutOfMemory;
        self.imm32(0);
    }
    /// POP v; if nil jump else keep+pop (else-pop variants)
    fn condJumpKeep(self: *Emitter, target_bc: u32, want_nil: bool) Error!void {
        // rax = [r12] (no pop yet); test; jz/jnz to KEEP path...
        // Semantics: goto-if-nil-else-pop: if nil -> jump (keep value);
        // else pop and fall through.
        self.loadTosRax();
        self.raw(0x48);
        self.raw(0x85);
        self.raw(0xC0);
        self.raw(0x0F);
        self.raw(if (want_nil) 0x84 else 0x85);
        self.patches.append(self.allocator, .{ .at = self.pos, .target_bc = target_bc }) catch return Error.OutOfMemory;
        self.imm32(0);
        // fallthrough: pop
        self.adjustTop(-8);
    }
    /// Bvarref: PUSH Fsymbol_value(consts[idx]).
    fn varrefConst(self: *Emitter, idx: u32) void {
        const disp: i32 = @intCast(idx * 8);
        if (disp < 128) {
            self.raw(0x49);
            self.raw(0x8B);
            self.raw(0x46);
            self.raw(@intCast(disp));
        } else {
            self.raw(0x49);
            self.raw(0x8B);
            self.raw(0x86);
            self.imm32(disp);
        }
        self.pushRaxNoLoad();
        self.loadArg1Imm(1);
        self.loadArg2R12();
        self.frelocCall(IDX_SYMBOL_VALUE);
        self.raw(0x49);
        self.raw(0x89);
        self.raw(0x04);
        self.raw(0x24);
    }
    /// epilogue with rax = TOS
    fn epilogueFromTos(self: *Emitter) void {
        self.loadTosRax();
        self.raw(0x48);
        self.raw(0x8D);
        self.raw(0x65);
        self.raw(0xE8);
        self.raw(0x41);
        self.raw(0x5E);
        self.raw(0x41);
        self.raw(0x5D);
        self.raw(0x41);
        self.raw(0x5C);
        self.raw(0x5D);
        self.raw(0xC3);
    }

    /// BdiscardN: preserve TOP at top[-n] when bit 7 is set, then pop n.
    fn discardN(self: *Emitter, byte: u32) void {
        const n = byte & 0x7F;
        if ((byte & 0x80) != 0) {
            self.loadTosRax();
            self.raw(0x49); // mov [r12-n*8],rax
            self.raw(0x89);
            if (n * 8 < 128) {
                self.raw(0x44);
                self.raw(0x24);
                self.raw(@bitCast(@as(i8, @intCast(-@as(i32, @intCast(n * 8))))));
            } else {
                self.raw(0x84);
                self.raw(0x24);
                self.imm32(-@as(i32, @intCast(n * 8)));
            }
        }
        self.adjustTop(-@as(i32, @intCast(n * 8)));
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
        self.raw(0x49);
        self.raw(0x8B);
        self.raw(0x85);
        self.imm32(@intCast(idx * 8));
        self.raw(0xFF);
        self.raw(0xD0); // call rax
    }

    fn newLocalLabel(self: *Emitter) Error!u32 {
        const label = self.next_local_label;
        self.next_local_label += 1;
        return label;
    }

    fn bindLocalLabel(self: *Emitter, label: u32) Error!void {
        self.local_labels.put(self.allocator, label, self.pos) catch return Error.OutOfMemory;
    }

    fn localJump(self: *Emitter, label: u32, kind: @FieldType(LocalJump, "kind")) Error!void {
        switch (kind) {
            .jmp => {
                self.raw(0xE9);
                self.local_jumps.append(self.allocator, .{
                    .at = self.pos,
                    .label = label,
                    .kind = kind,
                }) catch return Error.OutOfMemory;
                self.imm32(0);
            },
            .je, .jne, .jg, .jl, .jle, .jge, .jo => {
                const opcode: u8 = switch (kind) {
                    .je => 0x84,
                    .jne => 0x85,
                    .jg => 0x8F,
                    .jl => 0x8C,
                    .jle => 0x8E,
                    .jge => 0x8D,
                    .jo => 0x80,
                    else => unreachable,
                };
                self.raw(0x0F);
                self.raw(opcode);
                self.local_jumps.append(self.allocator, .{
                    .at = self.pos,
                    .label = label,
                    .kind = kind,
                }) catch return Error.OutOfMemory;
                self.imm32(0);
            },
        }
    }

    fn resolveLocalJumps(self: *Emitter, slot: []u8) Error!void {
        for (self.local_jumps.items) |jump| {
            const target = self.local_labels.get(jump.label) orelse return Error.BadBytecode;
            const rel: i64 = @as(i64, target) - @as(i64, jump.at + 4);
            std.mem.writeInt(i32, slot[jump.at..][0..4], @intCast(rel), .little);
        }
    }

    fn relBranch(self: *Emitter, target_bc: u32, opcode: u8) Error!void {
        self.raw(0x0F);
        self.raw(opcode);
        self.patches.append(self.allocator, .{
            .at = self.pos,
            .target_bc = target_bc,
        }) catch return Error.OutOfMemory;
        self.imm32(0);
    }

    /// Dispatch the signed raw offset returned by zeln_switch_target.
    /// Bytecode offsets are small nonnegative values, while a miss is -1.
    fn switchDispatch(
        self: *Emitter,
        targets: []const u32,
        fall_bc: u32,
    ) Error!void {
        for (targets) |target_bc| {
            const target: i32 = @intCast(target_bc);
            self.raw(0x48);
            self.raw(0x3D);
            self.imm32(target);
            try self.relBranch(target_bc, 0x84); // je -> case
        }
        try self.emitJump(fall_bc); // miss (-1) / default
    }

    /// Tagged Bplus/Bdiff fast path, matching zeln-compile's M3a model.
    /// Non-fixnum and overflow operands fall back to the identical freloc
    /// primitive used by AOT/interpreter.  The fast path is pure register
    /// arithmetic: it never allocates, retains, or moves a Lisp object.
    fn inlineBinaryAddSub(self: *Emitter, idx: u64) Error!void {
        const fallback = try self.newLocalLabel();
        const done = try self.newLocalLabel();

        // Load v2 (TOP) and v1 (TOP-1).
        self.raw(0x49); // mov rax,[r12]
        self.raw(0x8B);
        self.raw(0x04);
        self.raw(0x24);
        self.raw(0x49); // mov rcx,[r12-8]
        self.raw(0x8B);
        self.raw(0x4C);
        self.raw(0x24);
        self.raw(0xF8);

        // FIXNUMP under USE_LSB_TAG: (raw & 3) == 2.
        self.raw(0x48); // mov rdx,rax
        self.raw(0x89);
        self.raw(0xC2);
        self.raw(0x48); // and rdx,3
        self.raw(0x83);
        self.raw(0xE2);
        self.raw(0x03);
        self.raw(0x48); // cmp rdx,2
        self.raw(0x83);
        self.raw(0xFA);
        self.raw(0x02);
        try self.localJump(fallback, .jne);

        self.raw(0x48); // mov rdx,rcx
        self.raw(0x89);
        self.raw(0xCA);
        self.raw(0x48); // and rdx,3
        self.raw(0x83);
        self.raw(0xE2);
        self.raw(0x03);
        self.raw(0x48); // cmp rdx,2
        self.raw(0x83);
        self.raw(0xFA);
        self.raw(0x02);
        try self.localJump(fallback, .jne);

        // Decode tagged values: signed = raw >>> 2 (arithmetic).
        self.raw(0x48); // sar rcx,2
        self.raw(0xC1);
        self.raw(0xF9);
        self.raw(0x02);
        self.raw(0x48); // sar rax,2
        self.raw(0xC1);
        self.raw(0xF8);
        self.raw(0x02);

        if (idx == IDX_PLUS) {
            self.raw(0x48); // add rcx,rax
            self.raw(0x01);
            self.raw(0xC1);
        } else if (idx == IDX_MINUS) {
            self.raw(0x48); // sub rcx,rax
            self.raw(0x29);
            self.raw(0xC1);
        } else return Error.UnsupportedOpcode;

        // Range-check against MOST_POSITIVE/MOST_NEGATIVE_FIXNUM.
        self.raw(0x49); // movabs r10,0x1fffffffffffffff
        self.raw(0xBA);
        self.imm64(0x1FFF_FFFF_FFFF_FFFF);
        self.raw(0x4C); // cmp rcx,r10
        self.raw(0x39);
        self.raw(0xD1);
        try self.localJump(fallback, .jg);
        self.raw(0x49); // movabs r10,0xe000000000000000 (= -2^61)
        self.raw(0xBA);
        self.imm64(0xE000_0000_0000_0000);
        self.raw(0x4C); // cmp rcx,r10
        self.raw(0x39);
        self.raw(0xD1);
        try self.localJump(fallback, .jl);

        // make_fixnum(result): raw = (signed << 2) | Lisp_Int0.
        self.raw(0x48); // shl rcx,2
        self.raw(0xC1);
        self.raw(0xE1);
        self.raw(0x02);
        self.raw(0x48); // or rcx,2
        self.raw(0x83);
        self.raw(0xC9);
        self.raw(0x02);
        self.raw(0x49); // store result at TOP-1, then POP v2.
        self.raw(0x89);
        self.raw(0x4C);
        self.raw(0x24);
        self.raw(0xF8);
        self.adjustTop(-8);
        try self.localJump(done, .jmp);

        // Identical fallback to binaryFreloc.
        try self.bindLocalLabel(fallback);
        self.adjustTop(-8);
        self.loadArg1Imm(2);
        self.loadArg2R12();
        self.frelocCall(idx);
        self.raw(0x49);
        self.raw(0x89);
        self.raw(0x04);
        self.raw(0x24);
        try self.localJump(done, .jmp);

        try self.bindLocalLabel(done);
    }

    /// Tagged Bsub1/Badd1/Bnegate fast path.  This mirrors AOT's M3a
    /// lowering: only fixnums take native arithmetic, and the exact boundary
    /// that would leave the fixnum range falls back to the same freloc helper.
    /// The operation is unary, so successful lowering leaves TOP unchanged.
    fn inlineUnaryArith(self: *Emitter, idx: u64) Error!void {
        const fallback = try self.newLocalLabel();
        const done = try self.newLocalLabel();

        self.loadTosRax();
        self.raw(0x48); // mov rdx,rax
        self.raw(0x89);
        self.raw(0xC2);
        self.raw(0x48); // and rdx,3
        self.raw(0x83);
        self.raw(0xE2);
        self.raw(0x03);
        self.raw(0x48); // cmp rdx,Lisp_Int0
        self.raw(0x83);
        self.raw(0xFA);
        self.raw(0x02);
        try self.localJump(fallback, .jne);

        // signed = arithmetics raw >> 2.
        self.raw(0x48); // sar rax,2
        self.raw(0xC1);
        self.raw(0xF8);
        self.raw(0x02);
        self.raw(0x48); // mov rcx,rax
        self.raw(0x89);
        self.raw(0xC1);

        switch (idx) {
            IDX_SUB1 => {
                self.raw(0x48); // sub rcx,1
                self.raw(0x83);
                self.raw(0xE9);
                self.raw(0x01);
                self.raw(0x49); // movabs r10,MOST_NEGATIVE_FIXNUM
                self.raw(0xBA);
                self.imm64(0xE000_0000_0000_0000);
                self.raw(0x4C); // cmp rax,r10
                self.raw(0x39);
                self.raw(0xD0);
                try self.localJump(fallback, .je);
            },
            IDX_ADD1 => {
                self.raw(0x48); // add rcx,1
                self.raw(0x83);
                self.raw(0xC1);
                self.raw(0x01);
                self.raw(0x49); // movabs r10,MOST_POSITIVE_FIXNUM
                self.raw(0xBA);
                self.imm64(0x1FFF_FFFF_FFFF_FFFF);
                self.raw(0x4C); // cmp rax,r10
                self.raw(0x39);
                self.raw(0xD0);
                try self.localJump(fallback, .je);
            },
            IDX_NEGATE => {
                self.raw(0x48); // xor ecx,ecx (REX needed for rcx)
                self.raw(0x31);
                self.raw(0xC9);
                self.raw(0x48); // sub rcx,rax
                self.raw(0x29);
                self.raw(0xC1);
                self.raw(0x49); // movabs r10,MOST_NEGATIVE_FIXNUM
                self.raw(0xBA);
                self.imm64(0xE000_0000_0000_0000);
                self.raw(0x4C); // cmp rax,r10
                self.raw(0x39);
                self.raw(0xD0);
                try self.localJump(fallback, .je);
            },
            else => return Error.UnsupportedOpcode,
        }

        // make_fixnum(result), then replace TOP in place.
        self.raw(0x48); // shl rcx,2
        self.raw(0xC1);
        self.raw(0xE1);
        self.raw(0x02);
        self.raw(0x48); // or rcx,2
        self.raw(0x83);
        self.raw(0xC9);
        self.raw(0x02);
        self.raw(0x49); // mov [r12],rcx
        self.raw(0x89);
        self.raw(0x0C);
        self.raw(0x24);
        try self.localJump(done, .jmp);

        // Byte-identical primitive fallback.  TOP was never popped.
        try self.bindLocalLabel(fallback);
        self.unaryFreloc(idx);
        try self.bindLocalLabel(done);
    }

    /// Tagged Bcar/Bcdr fast path, matching AOT M3b.  For conses this is
    /// exactly XCAR/XCDR: mask the three low tag bits, then load the cons
    /// slot directly.  Nil and every other non-cons fall back to the same
    /// freloc primitive, preserving errors and total-car/cdr semantics.
    fn inlineConsSlot(self: *Emitter, idx: u64) Error!void {
        const fallback = try self.newLocalLabel();
        const done = try self.newLocalLabel();

        self.loadTosRax();

        // CONSP(v) = (raw & 7) == Lisp_Cons.
        self.raw(0x48); // mov rdx,rax
        self.raw(0x89);
        self.raw(0xC2);
        self.raw(0x48); // and rdx,7
        self.raw(0x83);
        self.raw(0xE2);
        self.raw(0x07);
        self.raw(0x48); // cmp rdx,3
        self.raw(0x83);
        self.raw(0xFA);
        self.raw(0x03);
        try self.localJump(fallback, .jne);

        // XCONS(v): clear the three low tag bits.
        self.raw(0x48); // and rax,-8
        self.raw(0x83);
        self.raw(0xE0);
        self.raw(0xF8);

        switch (idx) {
            IDX_CAR => self.raw(0x48), // mov rax,[rax]
            IDX_CDR => {
                self.raw(0x48); // mov rax,[rax+8]
                self.raw(0x8B);
                self.raw(0x40);
                self.raw(0x08);
            },
            else => return Error.UnsupportedOpcode,
        }
        if (idx == IDX_CAR) {
            self.raw(0x8B);
            self.raw(0x00);
        }

        self.raw(0x49); // mov [r12],rax (memory operand needs ModRM/SIB)
        self.raw(0x89);
        self.raw(0x04);
        self.raw(0x24);
        try self.localJump(done, .jmp);

        // TOP was left pristine, so the helper sees the original operand.
        try self.bindLocalLabel(fallback);
        self.unaryFreloc(idx);
        try self.bindLocalLabel(done);
    }

    /// Pure predicate fast paths.  Bconsp/Bnot are total inline tests and
    /// match AOT M3c.  Bsymbolp/Bstringp/Blistp/Bnumberp/Bintegerp take
    /// the tagged fast path for their common representation; anything not
    /// recognized falls back to the same freloc primitive (which still
    /// handles symbol-with-pos, bignums, floats, and every other shape).
    fn inlineUnaryPredicate(self: *Emitter, idx: u64) Error!void {
        const true_path = try self.newLocalLabel();
        const fallback = try self.newLocalLabel();
        const done = try self.newLocalLabel();

        self.loadTosRax();
        switch (idx) {
            IDX_CONSP => {
                self.raw(0x48); // mov rdx,rax
                self.raw(0x89);
                self.raw(0xC2);
                self.raw(0x48); // and rdx,7
                self.raw(0x83);
                self.raw(0xE2);
                self.raw(0x07);
                self.raw(0x48); // cmp rdx,Lisp_Cons
                self.raw(0x83);
                self.raw(0xFA);
                self.raw(0x03);
                try self.localJump(true_path, .je);
            },
            IDX_NULL => {
                // NILP(v): Qnil is the untagged zero word.
                self.raw(0x48); // test rax,rax
                self.raw(0x85);
                self.raw(0xC0);
                try self.localJump(true_path, .je);
            },
            IDX_SYMBOLP => {
                self.raw(0x48); // and rax,7
                self.raw(0x83);
                self.raw(0xE0);
                self.raw(0x07);
                self.raw(0x48); // test rax,rax
                self.raw(0x85);
                self.raw(0xC0);
                try self.localJump(true_path, .je);
                try self.localJump(fallback, .jmp);
            },
            IDX_STRINGP => {
                self.raw(0x48); // and rax,7
                self.raw(0x83);
                self.raw(0xE0);
                self.raw(0x07);
                self.raw(0x48); // cmp rax,Lisp_String
                self.raw(0x83);
                self.raw(0xF8);
                self.raw(0x04);
                try self.localJump(true_path, .je);
                try self.localJump(fallback, .jmp);
            },
            IDX_LISTP => {
                self.raw(0x48); // and rax,7
                self.raw(0x83);
                self.raw(0xE0);
                self.raw(0x07);
                self.raw(0x48); // cmp rax,Lisp_Cons
                self.raw(0x83);
                self.raw(0xF8);
                self.raw(0x03);
                try self.localJump(true_path, .je);
                self.raw(0x48); // test rax,rax (the masked copy: 0 iff Qnil)
                self.raw(0x85);
                self.raw(0xC0);
                try self.localJump(true_path, .je);
                try self.localJump(fallback, .jmp);
            },
            IDX_NUMBERP, IDX_INTEGERP => {
                // A fixnum is immediate: under USE_LSB_TAG this fast path
                // accepts both Lisp_Int0 and Lisp_Int1.  Bignum and float
                // inputs take the helper fallback.
                self.raw(0x48); // and rax,3
                self.raw(0x83);
                self.raw(0xE0);
                self.raw(0x03);
                self.raw(0x48); // cmp rax,Lisp_Int0
                self.raw(0x83);
                self.raw(0xF8);
                self.raw(0x02);
                try self.localJump(true_path, .je);
                try self.localJump(fallback, .jmp);
            },
            else => return Error.UnsupportedOpcode,
        }

        // False result: Qnil = 0.
        self.raw(0x4D); // xor r10,r10
        self.raw(0x31);
        self.raw(0xD2);
        self.raw(0x4D); // mov [r12],r10
        self.raw(0x89);
        self.raw(0x14);
        self.raw(0x24);
        try self.localJump(done, .jmp);

        // True result: the canonical Qt supplied by the runtime.
        try self.bindLocalLabel(true_path);
        self.movImm64(10, self.qt_raw);
        self.raw(0x4D); // mov [r12],r10
        self.raw(0x89);
        self.raw(0x14);
        self.raw(0x24);
        try self.localJump(done, .jmp);
        try self.bindLocalLabel(done);

        // TOP was never modified, so the primitive observes the original
        // operand and remains the exact semantic fallback.
        try self.bindLocalLabel(fallback);
        self.unaryFreloc(idx);
        try self.localJump(done, .jmp);

        try self.bindLocalLabel(done);
    }

    /// Tagged Bmult fast path.  Signed 64-bit `imul' sets CF/OF for a
    /// truncated product; the same flags also reject every result outside the
    /// 61-bit fixnum range, matching AOT's smul-with-overflow plus range
    /// check without a helper call on the hot path.
    fn inlineBinaryMultiply(self: *Emitter) Error!void {
        const fallback = try self.newLocalLabel();
        const done = try self.newLocalLabel();

        // Load v2 (TOP) and v1 (TOP-1), exactly like Bplus/Bdiff.
        self.raw(0x49); // mov rax,[r12]
        self.raw(0x8B);
        self.raw(0x04);
        self.raw(0x24);
        self.raw(0x49); // mov rcx,[r12-8]
        self.raw(0x8B);
        self.raw(0x4C);
        self.raw(0x24);
        self.raw(0xF8);

        // FIXNUMP under USE_LSB_TAG: (raw & 3) == Lisp_Int0.
        self.raw(0x48); // mov rdx,rax
        self.raw(0x89);
        self.raw(0xC2);
        self.raw(0x48); // and rdx,3
        self.raw(0x83);
        self.raw(0xE2);
        self.raw(0x03);
        self.raw(0x48); // cmp rdx,2
        self.raw(0x83);
        self.raw(0xFA);
        self.raw(0x02);
        try self.localJump(fallback, .jne);

        self.raw(0x48); // mov rdx,rcx
        self.raw(0x89);
        self.raw(0xCA);
        self.raw(0x48); // and rdx,3
        self.raw(0x83);
        self.raw(0xE2);
        self.raw(0x03);
        self.raw(0x48); // cmp rdx,2
        self.raw(0x83);
        self.raw(0xFA);
        self.raw(0x02);
        try self.localJump(fallback, .jne);

        // Decode both tagged operands.
        self.raw(0x48); // sar rcx,2
        self.raw(0xC1);
        self.raw(0xF9);
        self.raw(0x02);
        self.raw(0x48); // sar rax,2
        self.raw(0xC1);
        self.raw(0xF8);
        self.raw(0x02);

        // Signed multiply into rcx.  CF/OF are set if the full product does
        // not fit in 64 bits; for two valid fixnums this precisely subsumes
        // the 61-bit fixnum range check.
        self.raw(0x48); // imul rcx,rax
        self.raw(0x0F);
        self.raw(0xAF);
        self.raw(0xC8);
        try self.localJump(fallback, .jo);

        // make_fixnum(result), then binary-op POP to TOP-1.
        self.raw(0x48); // shl rcx,2
        self.raw(0xC1);
        self.raw(0xE1);
        self.raw(0x02);
        self.raw(0x48); // or rcx,2
        self.raw(0x83);
        self.raw(0xC9);
        self.raw(0x02);
        self.raw(0x49); // mov [r12-8],rcx
        self.raw(0x89);
        self.raw(0x4C);
        self.raw(0x24);
        self.raw(0xF8);
        self.adjustTop(-8);
        try self.localJump(done, .jmp);

        // Identical fallback to the frozen times primitive.
        try self.bindLocalLabel(fallback);
        self.adjustTop(-8);
        self.loadArg1Imm(2);
        self.loadArg2R12();
        self.frelocCall(IDX_TIMES);
        self.raw(0x49);
        self.raw(0x89);
        self.raw(0x04);
        self.raw(0x24);
        try self.localJump(done, .jmp);

        try self.bindLocalLabel(done);
    }

    /// Tagged Beqlsign/Bgtr/Blss/Bleq/Bgeq fast path.  For fixnums this is
    /// exactly `arithcompare', except that the runtime supplies the canonical
    /// Qt raw word so the generated code can materialize Lisp booleans without
    /// calling a helper.  Non-fixnums (floats, bignums, markers) fall back to
    /// the identical freloc primitive.
    fn inlineBinaryCompare(self: *Emitter, idx: u64) Error!void {
        const fallback = try self.newLocalLabel();
        const set_true = try self.newLocalLabel();
        const set_result = try self.newLocalLabel();
        const done = try self.newLocalLabel();

        self.raw(0x49); // mov rax,[r12]      (v2)
        self.raw(0x8B);
        self.raw(0x04);
        self.raw(0x24);
        self.raw(0x49); // mov rcx,[r12-8]    (v1)
        self.raw(0x8B);
        self.raw(0x4C);
        self.raw(0x24);
        self.raw(0xF8);

        // FIXNUMP(v) = (raw & 3) == Lisp_Int0.
        self.raw(0x48); // mov rdx,rax
        self.raw(0x89);
        self.raw(0xC2);
        self.raw(0x48); // and rdx,3
        self.raw(0x83);
        self.raw(0xE2);
        self.raw(0x03);
        self.raw(0x48); // cmp rdx,2
        self.raw(0x83);
        self.raw(0xFA);
        self.raw(0x02);
        try self.localJump(fallback, .jne);

        self.raw(0x48); // mov rdx,rcx
        self.raw(0x89);
        self.raw(0xCA);
        self.raw(0x48); // and rdx,3
        self.raw(0x83);
        self.raw(0xE2);
        self.raw(0x03);
        self.raw(0x48); // cmp rdx,2
        self.raw(0x83);
        self.raw(0xFA);
        self.raw(0x02);
        try self.localJump(fallback, .jne);

        // Decode both tagged operands.
        self.raw(0x48); // sar rcx,2
        self.raw(0xC1);
        self.raw(0xF9);
        self.raw(0x02);
        self.raw(0x48); // sar rax,2
        self.raw(0xC1);
        self.raw(0xF8);
        self.raw(0x02);

        self.raw(0x48); // cmp rax,rcx  (v2 OP v1; branch predicates below are normalized)
        self.raw(0x39);
        self.raw(0xC8);
        switch (idx) {
            IDX_EQLSIGN => try self.localJump(set_true, .je),
            IDX_GTR => try self.localJump(set_true, .jl),
            IDX_LSS => try self.localJump(set_true, .jg),
            IDX_LEQ => try self.localJump(set_true, .jge),
            IDX_GEQ => try self.localJump(set_true, .jle),
            else => return Error.UnsupportedOpcode,
        }

        // Qnil = 0.  Use the r10 scratch register: r14 holds the constants
        // vector for the rest of the generated function.
        self.raw(0x4D); // xor r10,r10
        self.raw(0x31);
        self.raw(0xD2);
        try self.localJump(set_result, .jmp);

        try self.bindLocalLabel(set_true);
        self.movImm64(10, self.qt_raw); // r10 = Qt

        try self.bindLocalLabel(set_result);
        self.adjustTop(-8); // binary ops pop one slot
        self.raw(0x4D); // mov [r12],r10 (REX.R source, REX.B r12 base)
        self.raw(0x89);
        self.raw(0x14);
        self.raw(0x24);
        try self.localJump(done, .jmp);

        // Identical freloc fallback, including the binary stack pop.
        try self.bindLocalLabel(fallback);
        self.binaryFreloc(idx);
        try self.bindLocalLabel(done);
    }

    /// Bswitch: POP table, POP key; ask the same AOT freloc helper for
    /// the absolute bytecode target (or -1), then POP 2 and dispatch.
    fn switchFreloc(
        self: *Emitter,
        const_idx: u32,
        targets: []const u32,
        fall_bc: u32,
    ) Error!void {
        // key = [r12-8] -> scratch[0]; table = consts[idx] -> scratch[1].
        self.raw(0x49);
        self.raw(0x8B);
        self.raw(0x44);
        self.raw(0x24);
        self.raw(0xF8); // mov rax,[r12-8] (disp8)
        self.raw(0x48);
        self.raw(0x89);
        self.raw(0x44);
        self.raw(0x24);
        self.raw(32);
        const disp: i32 = @intCast(const_idx * 8);
        if (disp < 128) {
            self.raw(0x49);
            self.raw(0x8B);
            self.raw(0x46);
            self.raw(@intCast(disp));
        } else {
            self.raw(0x49);
            self.raw(0x8B);
            self.raw(0x86);
            self.imm32(disp);
        }
        self.raw(0x48);
        self.raw(0x89);
        self.raw(0x44);
        self.raw(0x24);
        self.raw(40);
        self.loadArg1Imm(2);
        self.loadArg2Scratch();
        self.frelocCall(IDX_SWITCH_TARGET);
        self.adjustTop(-16); // POP key and table
        try self.switchDispatch(targets, fall_bc);
    }
};

fn missingUnaryFreloc(b: u8) ?u64 {
    return switch (b) {
        BCAR_SAFE => IDX_CAR_SAFE,
        BCDR_SAFE => IDX_CDR_SAFE,
        BLIST1 => IDX_LIST1,
        BSYMBOL_VALUE => IDX_SYMBOL_VALUE,
        BSYMBOL_FUNCTION => IDX_SYMBOL_FUNCTION,
        BGOTO_CHAR => IDX_GOTO_CHAR,
        BINSERT => IDX_INSERT,
        BCHAR_AFTER => IDX_CHAR_AFTER,
        BINDENT_TO => IDX_INDENT_TO,
        BSET_BUFFER => IDX_SET_BUFFER,
        BFORWARD_CHAR => IDX_FORWARD_CHAR,
        BFORWARD_WORD => IDX_FORWARD_WORD,
        BFORWARD_LINE => IDX_FORWARD_LINE,
        BCHAR_SYNTAX => IDX_CHAR_SYNTAX,
        BEND_OF_LINE => IDX_END_OF_LINE,
        BMATCH_BEGINNING => IDX_MATCH_BEGINNING,
        BMATCH_END => IDX_MATCH_END,
        BUPCASE => IDX_UPCASE,
        BDOWNCASE => IDX_DOWNCASE,
        BNREVERSE => IDX_NREVERSE,
        else => null,
    };
}

fn missingBinaryFreloc(b: u8) ?u64 {
    return switch (b) {
        BEQ => IDX_EQ,
        BMAX => IDX_MAX,
        BMIN => IDX_MIN,
        BEQUAL => IDX_EQUAL,
        BNTH => IDX_NTH,
        BMEMQ => IDX_MEMQ,
        BAREF => IDX_AREF,
        BSET => IDX_SET,
        BFSET => IDX_FSET,
        BGET => IDX_GET,
        BMEMBER => IDX_MEMBER,
        BASSQ => IDX_ASSQ,
        BNTHCDR => IDX_NTHCDR,
        BELT => IDX_ELT,
        BQUO => IDX_QUO,
        BREM => IDX_REM,
        BSKIP_CHARS_FORWARD => IDX_SKIP_CHARS_FORWARD,
        BSKIP_CHARS_BACKWARD => IDX_SKIP_CHARS_BACKWARD,
        BBUFFER_SUBSTRING => IDX_BUFFER_SUBSTRING,
        BDELETE_REGION => IDX_DELETE_REGION,
        BNARROW_TO_REGION => IDX_NARROW_TO_REGION,
        BSTRINGEQLSIGN => IDX_STRING_EQUAL,
        BSTRINGLSS => IDX_STRING_LESSP,
        BSETCAR => IDX_SETCAR,
        BSETCDR => IDX_SETCDR,
        else => null,
    };
}

fn push0FrelocIdx(b: u8) ?u64 {
    return switch (b) {
        BPOINT => IDX_POINT,
        BPOINT_MAX => IDX_POINT_MAX,
        BPOINT_MIN => IDX_POINT_MIN,
        BCHAR_AFTER => IDX_CHAR_AFTER,
        BFOLLOWING_CHAR => IDX_FOLLOWING_CHAR,
        BPRECEDING_CHAR => IDX_PRECEDING_CHAR,
        BCURRENT_COLUMN => IDX_CURRENT_COLUMN,
        BEOLP => IDX_EOLP,
        BEOBP => IDX_EOBP,
        BBOLP => IDX_BOLP,
        BBOBP => IDX_BOBP,
        BCURRENT_BUFFER => IDX_CURRENT_BUFFER,
        BWIDEN => IDX_WIDEN,
        BEND_OF_LINE => IDX_END_OF_LINE,
        else => null,
    };
}

fn noargFrelocIdx(b: u8) ?u64 {
    return switch (b) {
        BPOPHANDLER => IDX_POPHANDLER,
        BSAVE_CURRENT_BUFFER => IDX_SAVE_CURRENT_BUFFER,
        BSAVE_EXCURSION => IDX_SAVE_EXCURSION,
        BSAVE_RESTRICTION => IDX_SAVE_RESTRICTION,
        else => null,
    };
}

/// bytecomp always emits the switch jump-table as the immediately
/// preceding Bconstant (Bconstant for indices 0..63, Bconstant2 above).
fn switchConstantIndex(
    opcodes: []const u8,
    constant_at: u32,
    switch_at: u32,
) Error!u32 {
    if (constant_at >= switch_at) return Error.BadBytecode;
    const prev = opcodes[constant_at];
    if (prev >= BCONSTANT_BASE) return prev - BCONSTANT_BASE;
    if (prev == BCONSTANT2) {
        return fetch2(opcodes, constant_at + 1) orelse Error.BadBytecode;
    }
    return Error.BadBytecode;
}

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
    switch_targets: []const u32,
    qt_raw: u64,
) Error!Result {
    // Keep every derived frame size within the compact WinX64 unwind
    // encoding and within the emitter's imm32 `sub rsp` range.
    if (stack_depth > 8190 or arity > 8) return Error.UnsupportedPlatform;

    var switch_op_count: usize = 0;
    var fast_add_sub_count: usize = 0;
    var fast_unary_count: usize = 0;
    var fast_compare_count: usize = 0;
    var fast_multiply_count: usize = 0;

    // Pre-scan: every branch target must land inside the bytecode.  A
    // malformed closure (observed from dump'd images with truncated or
    // inconsistent bytes) would otherwise make the decode loop read past
    // the buffer and the patch pass jump into garbage.
    {
        var p: u32 = 0;
        while (p < opcodes.len) {
            const b = opcodes[p];
            if (b == BSWITCH) switch_op_count += 1;
            if (b == BPLUS or b == BDIFF) fast_add_sub_count += 1;
            if (b == BMULT) fast_multiply_count += 1;
            if (b == BSUB1 or b == BADD1 or b == BNEGATE) fast_unary_count += 1;
            if (b == BEQLSIGN or b == BGTR or b == BLSS or b == BLEQ or b == BGEQ)
                fast_compare_count += 1;
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
                9, 10, 11, 12, 13 => imm = 0,
                BVARSET6, BVARBIND6, BUNBIND6, BSTACK_SET, BDISCARD_N => imm = 1,
                BVARREF => imm = 0,
                15 => imm = 2,
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

    // A conservative capacity prevents a long accepted closure from
    // silently running past its 4 KiB reservation.  The worst supported
    // lowering is well under 48 bytes per bytecode byte.  A single Bswitch
    // can expand to a compare/branch pair for every jump-table target, so
    // capacity also has a dedicated per-target term.
    const base_estimated_size: usize =
        opcodes.len *| 48 +| 256 +| switch_op_count *| 48 +|
        switch_targets.len *| 64 +| fast_add_sub_count *| 256 +|
        fast_unary_count *| 256;
    const estimated_size: usize =
        base_estimated_size +| fast_compare_count *| 256 +|
        fast_multiply_count *| 256;
    if (estimated_size > std.math.maxInt(u32)) return Error.UnsupportedPlatform;
    const code_capacity: u32 = @intCast(@max(4096, estimated_size));
    const slot = try arena.reserve(code_capacity);
    // Heap-allocate the emitter ALIGNED TO 16: Zig-0.16 codegen uses
    // vmovaps on the struct (needs 16-byte alignment); @alignOf(Emitter)
    // is only 8, so a plain create() can hand back an 8-mod-16 block -
    // exactly the fault seen in the deep-recursion scrapes.
    const emp_raw = std.heap.smp_allocator.alignedAlloc(Emitter, .@"16", 1) catch return Error.OutOfMemory;
    const emp: *Emitter = &emp_raw[0];
    defer std.heap.smp_allocator.free(emp_raw);
    emp.* = .{
        .allocator = std.heap.smp_allocator,
        .buf = slot.w,
        .patches = .empty,
        .local_jumps = .empty,
        .local_labels = .empty,
        .blocks = .init(std.heap.smp_allocator),
        // The JIT code runs inside THIS process: Windows hosts (mingw or
        // MSVC ABI) need the WinX64 calling convention.
        .win64 = builtin.os.tag == .windows,
        .qt_raw = qt_raw,
    };
    const em = &emp.*;
    defer {
        em.patches.deinit(std.heap.smp_allocator);
        em.local_jumps.deinit(std.heap.smp_allocator);
        em.local_labels.deinit(std.heap.smp_allocator);
        em.blocks.deinit();
    }

    // ---- prologue ----
    em.raw(0x55); // push rbp
    em.raw(0x48);
    em.raw(0x89);
    em.raw(0xE5); // mov rbp, rsp
    em.raw(0x41);
    em.raw(0x54); // push r12
    em.raw(0x41);
    em.raw(0x55); // push r13
    em.raw(0x41);
    em.raw(0x56); // push r14
    // Reserve (a) the virtual stack frame sized to stack_depth and
    // (b) 48 bytes BELOW it: [rsp..rsp+32) is the WinX64 SHADOW SPACE
    // (a WinX64 callee is entitled to home rcx/rdx/r8/r9 into
    // [entry_rsp+8 .. entry_rsp+40) = [call_rsp .. call_rsp+32); the
    // earlier layout had the virtual stack start AT rsp, so the first
    // four freloc calls' home writes CORRUPTED the bottom live slots -
    // the "compiles fine, executes once, then AVs" Windows signature:
    // SysV has no shadow space, which is why Linux never saw it), and
    // [rsp+32..rsp+48) is a 16-byte SCRATCH PAIR for varset/varbind
    // (safe from homes and from the return-address push).  Alignment:
    // entry rsp is 8-mod-16, four pushes add 32 -> 8, frame is
    // 8-mod-16 and 48 is 0-mod-16, so rsp lands 0-mod-16 at calls.
    const frame: u32 = (((stack_depth * 8) + 15) & ~@as(u32, 15)) + 8;
    const total: u32 = frame + 48;
    em.raw(0x48);
    em.raw(0x81);
    em.raw(0xEC);
    em.imm32(@intCast(total)); // sub rsp, imm32
    // r12 = top = the virtual stack's lowest slot minus 8, i.e. the
    // stack occupies [rsp+48 .. rsp+48+frame): Bconstant does *++top,
    // so the first push writes [rsp+48] (above shadow+scratch).
    em.raw(0x4C);
    em.raw(0x8D);
    em.raw(0x64);
    em.raw(0x24);
    em.raw(40); // lea r12, [rsp+40]
    // r13 = [freloc_slot]
    em.movImm64(0, @intFromPtr(freloc_slot)); // mov rax, imm64
    em.raw(0x4C);
    em.raw(0x8B);
    em.raw(0x28); // mov r13, [rax] (REX.WR)
    // r14 = consts vector
    em.movImm64(14, @intFromPtr(consts_vec)); // mov r14, imm64 (REX.WB)

    // args setup: push args[0..arity] in order (each arg a stack slot,
    // top = last arg; arg2 reg = args pointer at entry: rsi SysV / rdx WinX64).
    var ai: u32 = 0;
    while (ai < arity) : (ai += 1) {
        if (em.win64) {
            // mov rax, [rdx + ai*8]
            em.raw(0x48);
            em.raw(0x8B);
            em.raw(0x92);
            em.imm32(@intCast(ai * 8));
        } else {
            // mov rax, [rsi + ai*8]
            em.raw(0x48);
            em.raw(0x8B);
            em.raw(0x86);
            em.imm32(@intCast(ai * 8));
        }
        em.pushRaxNoLoad();
    }

    // ---- body: decode loop ----
    var pc: u32 = 0;
    var prev_start: ?u32 = null;
    while (pc < opcodes.len) {
        const op_start = pc;
        try em.blocks.put(pc, em.pos);
        const b = opcodes[pc];
        pc += 1;
        if (b >= BCONSTANT_BASE) {
            const idx: u32 = b - BCONSTANT_BASE;
            em.pushConst(idx);
            prev_start = op_start;
            continue;
        }
        // AOT-parity opcode families.  Keeping these in compact maps makes
        // the primitive surface auditable against compz.c/zeln-compile.
        if (missingUnaryFreloc(b)) |idx| {
            em.unaryFreloc(idx);
            prev_start = op_start;
            continue;
        }
        if (missingBinaryFreloc(b)) |idx| {
            em.binaryFreloc(idx);
            prev_start = op_start;
            continue;
        }
        if (push0FrelocIdx(b)) |idx| {
            em.push0Freloc(idx);
            prev_start = op_start;
            continue;
        }
        if (noargFrelocIdx(b)) |idx| {
            em.noargFreloc(idx);
            prev_start = op_start;
            continue;
        }
        if (b == BUNWIND_PROTECT) {
            em.unaryPopFreloc(IDX_UNWIND_PROTECT);
            prev_start = op_start;
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
            BDISCARD_N => {
                const n = fetch1(opcodes, pc) orelse return Error.BadBytecode;
                pc += 1;
                em.discardN(n);
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
            BSUB1 => try em.inlineUnaryArith(IDX_SUB1),
            BADD1 => try em.inlineUnaryArith(IDX_ADD1),
            BNEGATE => try em.inlineUnaryArith(IDX_NEGATE),
            BCAR => try em.inlineConsSlot(IDX_CAR),
            BCDR => try em.inlineConsSlot(IDX_CDR),
            BCONSP => try em.inlineUnaryPredicate(IDX_CONSP),
            BNOT => try em.inlineUnaryPredicate(IDX_NULL), // Bnot = NILP? Qt : Qnil
            BSYMBOLP => try em.inlineUnaryPredicate(IDX_SYMBOLP),
            BSTRINGP => try em.inlineUnaryPredicate(IDX_STRINGP),
            BLISTP => try em.inlineUnaryPredicate(IDX_LISTP),
            BNUMBERP => try em.inlineUnaryPredicate(IDX_NUMBERP),
            BINTEGERP => try em.inlineUnaryPredicate(IDX_INTEGERP),
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
            BEQLSIGN => try em.inlineBinaryCompare(IDX_EQLSIGN),
            BGTR => try em.inlineBinaryCompare(IDX_GTR),
            BLSS => try em.inlineBinaryCompare(IDX_LSS),
            BLEQ => try em.inlineBinaryCompare(IDX_LEQ),
            BGEQ => try em.inlineBinaryCompare(IDX_GEQ),
            BPLUS => try em.inlineBinaryAddSub(IDX_PLUS),
            BDIFF => try em.inlineBinaryAddSub(IDX_MINUS),
            BMULT => try em.inlineBinaryMultiply(),
            BCONS => em.binaryFreloc(IDX_CONS),
            // ---- calls: POP n args + fun -> hot JIT-to-JIT dispatch when
            // the callee already has a validated fixed-arity entry; the
            // helper falls back to the exact generic funcall otherwise. ----
            BCALL, 33, 34, 35, 36, BCALL5 => {
                em.callFrelocN(IDX_JIT_CALL, @intCast(b - BCALL));
            },
            BCALL6 => {
                const n = fetch1(opcodes, pc) orelse return Error.BadBytecode;
                pc += 1;
                em.callFrelocN(IDX_JIT_CALL, n);
            },
            BCALL7 => {
                const n = fetch2(opcodes, pc) orelse return Error.BadBytecode;
                pc += 2;
                em.callFrelocN(IDX_JIT_CALL, n);
            },
            BSWITCH => {
                if (switch_targets.len == 0) return Error.BadBytecode;
                const const_idx = try switchConstantIndex(
                    opcodes,
                    prev_start orelse return Error.BadBytecode,
                    op_start,
                );
                try em.switchFreloc(const_idx, switch_targets, pc);
            },
            BASET => em.naryFreloc(IDX_ASET, 3),
            BSUBSTRING => em.naryFreloc(IDX_SUBSTRING, 3),
            BSET_MARKER => em.naryFreloc(IDX_SET_MARKER, 3),
            BNCONC => em.binaryFreloc(IDX_NCONC),
            BCONCATN => {
                const n = fetch1(opcodes, pc) orelse return Error.BadBytecode;
                pc += 1;
                em.naryFreloc(IDX_CONCAT, n);
            },
            BINSERTN => {
                const n = fetch1(opcodes, pc) orelse return Error.BadBytecode;
                pc += 1;
                em.naryFreloc(IDX_INSERT, n);
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
                try em.emitJump(t);
            },
            BGOTOIFNIL, BGOTOIFNONNIL => {
                const t = fetch2(opcodes, pc) orelse return Error.BadBytecode;
                pc += 2;
                try em.condJump(t, b == BGOTOIFNIL);
            },
            BGOTOIFNILELSEPOP, BGOTOIFNONNILELSEPOP => {
                const t = fetch2(opcodes, pc) orelse return Error.BadBytecode;
                pc += 2;
                try em.condJumpKeep(t, b == BGOTOIFNILELSEPOP);
            },
            else => return Error.UnsupportedOpcode,
        }
        prev_start = op_start;
    }
    if (pc != opcodes.len) return Error.BadBytecode;
    if (em.overflow) return Error.OutOfMemory;

    // ---- patch pass: resolve every branch to its block's code offset.
    // rel32 = target_code - (patch_site + 4).
    for (em.patches.items) |p| {
        const target_code = em.blocks.get(p.target_bc) orelse
            return Error.BadBytecode; // branch to a non-instruction offset
        const rel: i64 = @as(i64, target_code) - @as(i64, p.at + 4);
        std.mem.writeInt(i32, slot.w[p.at..][0..4], @intCast(rel), .little);
    }
    try em.resolveLocalJumps(slot.w);
    try registerWindowsUnwind(arena, slot, em.pos, frame + 48);

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

    const res = try compile(&arena, &opcodes, 8, freloc_slot, consts_ptr, 0, &[_]u32{}, 0);
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
    const res = try compile(&arena, &opcodes, 8, freloc_slot, &consts, 0, &[_]u32{}, 0);
    var args: [1]u64 = .{0};
    const got = res.entry(0, &args);
    try testing.expectEqual(@as(u64, 42), got);
}

test "compile and run: tagged plus/minus fast path and primitive fallback" {
    var arena = try jit.ExecArena.allocate(jit.page_size);
    defer arena.deinit();

    const Shim = struct {
        fn plus(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0xAAAA;
        }
        fn minus(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0xBBBB;
        }
    };
    var freloc_table =
        [_]*const anyopaque{ undefined, undefined, undefined, &Shim.plus, &Shim.minus };
    var freloc_base: *const anyopaque = &freloc_table;
    const freloc_slot: *const *const anyopaque = &freloc_base;
    var args: [1]u64 = .{0};

    const plus_ops = [_]u8{ 0xC0, 0xC0 + 1, BPLUS, BRETURN };
    const minus_ops = [_]u8{ 0xC0, 0xC0 + 1, BDIFF, BRETURN };
    const fixnum = struct {
        fn make(n: u64) u64 {
            return (n << 2) | 2;
        }
    }.make;

    var plus_consts = [_]u64{ fixnum(1), fixnum(2) };
    const plus = try compile(&arena, &plus_ops, 8, freloc_slot, &plus_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(fixnum(3), plus.entry(0, &args));

    // Bplus has net stack effect -1.  A following instruction must observe
    // the result at the popped TOP, not the stale v2 slot.
    const plus_pop_ops = [_]u8{ 0xC0, 0xC0 + 1, BPLUS, 0xC2, BDIFF, BRETURN };
    var plus_pop_arena = try jit.ExecArena.allocate(jit.page_size);
    defer plus_pop_arena.deinit();
    var plus_pop_consts = [_]u64{ fixnum(1), fixnum(2), fixnum(10) };
    const plus_pop = try compile(
        &plus_pop_arena,
        &plus_pop_ops,
        8,
        freloc_slot,
        &plus_pop_consts,
        0,
        &[_]u32{},
        0,
    );
    // Raw make_fixnum(-7) = (-7 << 2) + 2.
    try testing.expectEqual(@as(u64, 0xFFFF_FFFF_FFFF_FFE6), plus_pop.entry(0, &args));

    var minus_arena = try jit.ExecArena.allocate(jit.page_size);
    defer minus_arena.deinit();
    var minus_consts = [_]u64{ fixnum(2), fixnum(1) };
    const minus =
        try compile(&minus_arena, &minus_ops, 8, freloc_slot, &minus_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(fixnum(1), minus.entry(0, &args));

    // Non-fixnum raw words and fixnum overflow must reach the same C primitive
    // as AOT/interpreter.  The marker proves the fallback branch was taken.
    var fallback_arena = try jit.ExecArena.allocate(jit.page_size);
    defer fallback_arena.deinit();
    var fallback_consts = [_]u64{ 8, fixnum(1) };
    const fallback =
        try compile(&fallback_arena, &plus_ops, 8, freloc_slot, &fallback_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 0xAAAA), fallback.entry(0, &args));

    var overflow_arena = try jit.ExecArena.allocate(jit.page_size);
    defer overflow_arena.deinit();
    const most_positive = fixnum(0x1FFF_FFFF_FFFF_FFFF);
    var overflow_consts = [_]u64{ most_positive, most_positive };
    const overflow =
        try compile(&overflow_arena, &plus_ops, 8, freloc_slot, &overflow_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 0xAAAA), overflow.entry(0, &args));
}

test "compile and run: tagged unary arith fast path and primitive fallback" {
    var arena = try jit.ExecArena.allocate(jit.page_size * 64);
    defer arena.deinit();

    const Shim = struct {
        fn sub1(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0xAAA1;
        }
        fn add1(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0xAAA2;
        }
        fn negate(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0xAAA3;
        }
    };
    var freloc_table = [_]*const anyopaque{
        undefined,
        undefined,
        undefined,
        undefined,
        undefined,
        undefined,
        &Shim.sub1,
        &Shim.add1,
        &Shim.negate,
    };
    var freloc_base: *const anyopaque = &freloc_table;
    const freloc_slot: *const *const anyopaque = &freloc_base;
    var args: [1]u64 = .{0};
    const tagged = struct {
        fn fixnum(n: i64) u64 {
            return @bitCast((n << 2) | 2);
        }
    }.fixnum;
    const sub1_ops = [_]u8{ 0xC0, BSUB1, BRETURN };
    const add1_ops = [_]u8{ 0xC0, BADD1, BRETURN };
    const negate_ops = [_]u8{ 0xC0, BNEGATE, BRETURN };

    var sub1_consts = [_]u64{tagged(10)};
    const sub1 = try compile(&arena, &sub1_ops, 8, freloc_slot, &sub1_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(tagged(9), sub1.entry(0, &args));

    var add1_consts = [_]u64{tagged(10)};
    const add1 = try compile(&arena, &add1_ops, 8, freloc_slot, &add1_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(tagged(11), add1.entry(0, &args));

    var negate_consts = [_]u64{tagged(7)};
    const negate = try compile(&arena, &negate_ops, 8, freloc_slot, &negate_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(tagged(-7), negate.entry(0, &args));

    // Non-fixnums and exact fixnum boundaries use the unchanged primitives.
    var nonfix_consts = [_]u64{8};
    const nonfix = try compile(&arena, &sub1_ops, 8, freloc_slot, &nonfix_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 0xAAA1), nonfix.entry(0, &args));

    const most_positive = tagged(0x1FFF_FFFF_FFFF_FFFF);
    const most_negative = tagged(-0x2000_0000_0000_0000);
    var sub1_boundary_consts = [_]u64{most_negative};
    const sub1_boundary =
        try compile(&arena, &sub1_ops, 8, freloc_slot, &sub1_boundary_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 0xAAA1), sub1_boundary.entry(0, &args));

    var add1_boundary_consts = [_]u64{most_positive};
    const add1_boundary =
        try compile(&arena, &add1_ops, 8, freloc_slot, &add1_boundary_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 0xAAA2), add1_boundary.entry(0, &args));

    var negate_boundary_consts = [_]u64{most_negative};
    const negate_boundary =
        try compile(&arena, &negate_ops, 8, freloc_slot, &negate_boundary_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 0xAAA3), negate_boundary.entry(0, &args));
}

test "compile and run: loop with branch (countdown)" {
    var arena = try jit.ExecArena.allocate(jit.page_size);
    defer arena.deinit();

    // freloc: IDX_EQ(17) is the only primitive this loop needs.  BSUB1 now
    // uses the real tagged fast path, so it terminates on fixnum zero.
    const Shim = struct {
        fn eq(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            return if (args[0] == args[1]) 0xAAAA else 0;
        }
    };
    var freloc_table = [_]*const anyopaque{undefined} ** 18;
    freloc_table[IDX_EQ] = &Shim.eq;
    var freloc_base: *const anyopaque = &freloc_table;
    const freloc_slot: *const *const anyopaque = &freloc_base;

    // countdown(10):
    //   push 10
    // L: sub1
    //   dup
    //   push 0
    //   eq
    //   goto-if-nil L
    //   return counter
    const opcodes = [_]u8{
        0xC0, // 0: push consts[0]=10
        BSUB1, // 1: L: top in place
        BDUP, // 2: dup
        0xC0 + 1, // 3: push zero
        BEQ, // 4
        BGOTOIFNIL, // 5: branch imm16=1 (L) if counter != zero
        1, 0, //    little-endian target=1
        BRETURN, // 7: return counter zero
    };
    const tagged = struct {
        fn fixnum(n: i64) u64 {
            return @bitCast((n << 2) | 2);
        }
    }.fixnum;
    var consts = [_]u64{ tagged(10), tagged(0) };
    const res = try compile(&arena, &opcodes, 8, freloc_slot, &consts, 0, &[_]u32{}, 0);
    var args: [1]u64 = .{0};
    const got = res.entry(0, &args);
    try testing.expectEqual(tagged(0), got);
}

test "compile and run: Bswitch dispatches through AOT freloc helper" {
    var arena = try jit.ExecArena.allocate(jit.page_size);
    defer arena.deinit();

    const Shim = struct {
        fn switch_target(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 5; // absolute bytecode offset selected by the table
        }
    };
    var freloc_table = [_]*const anyopaque{undefined} ** 103;
    freloc_table[IDX_SWITCH_TARGET] = &Shim.switch_target;
    var freloc_base: *const anyopaque = &freloc_table;
    const freloc_slot: *const *const anyopaque = &freloc_base;

    // 0: push table; 1: push key; 2: Bswitch (default falls to 3).
    // The miss/default path at 3 returns the key.  The fake helper
    // selects 5, which pushes consts[2] and proves the generated jump.
    const opcodes = [_]u8{
        0xC0, // 0: table
        0xC0 + 1, // 1: key
        BSWITCH, // 2: pop table/key, dispatch
        0xC0 + 1, // 3: default: push key
        BRETURN, // 4
        0xC0 + 2, // 5: selected: push marker
        BRETURN, // 6
    };
    var consts = [_]u64{ 111, 222, 999 };
    const res = try compile(&arena, &opcodes, 8, freloc_slot, &consts, 0, &[_]u32{ 3, 5 }, 0);
    var args: [1]u64 = .{0};
    try testing.expectEqual(@as(u64, 999), res.entry(0, &args));
}

test "compile and run: dense switch targets reserve per-target capacity" {
    var arena = try jit.ExecArena.allocate(jit.page_size * 128);
    defer arena.deinit();

    const Shim = struct {
        fn switch_target(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 7;
        }
    };
    var freloc_table = [_]*const anyopaque{undefined} ** 103;
    freloc_table[IDX_SWITCH_TARGET] = &Shim.switch_target;
    var freloc_base: *const anyopaque = &freloc_table;
    const freloc_slot: *const *const anyopaque = &freloc_base;

    // Bswitch is one bytecode byte but emits one compare/branch pair per
    // target.  A dense target block provides a large, valid target set while
    // the old estimate reserved for only the Bswitch opcode itself.
    const target_count: usize = 256;
    var opcodes: [target_count + 4]u8 = undefined;
    opcodes[0] = 0xC0; // table constant
    opcodes[1] = 0xC0 + 1; // key constant
    opcodes[2] = BSWITCH;
    for (0..target_count) |i| {
        opcodes[3 + i] = BRETURN;
    }
    // Make one selected target push a marker instead of returning stale TOS.
    opcodes[7] = 0xC0 + 2;
    opcodes[8] = BRETURN;
    opcodes[3 + target_count] = BRETURN; // default
    var targets: [target_count]u32 = undefined;
    for (0..target_count) |i| targets[i] = @intCast(3 + i);
    var consts = [_]u64{ 111, 222, 999 };
    var args: [1]u64 = .{0};
    const res = try compile(&arena, &opcodes, 8, freloc_slot, &consts, 0, &targets, 0);
    try testing.expectEqual(@as(u64, 999), res.entry(0, &args));
}

test "compile and run: Bswitch out-of-range helper result uses default" {
    var arena = try jit.ExecArena.allocate(jit.page_size);
    defer arena.deinit();

    const Shim = struct {
        fn switch_target(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return @bitCast(@as(i64, -1));
        }
    };
    var freloc_table = [_]*const anyopaque{undefined} ** 103;
    freloc_table[IDX_SWITCH_TARGET] = &Shim.switch_target;
    var freloc_base: *const anyopaque = &freloc_table;
    const freloc_slot: *const *const anyopaque = &freloc_base;

    const opcodes = [_]u8{ 0xC0, 0xC0 + 1, BSWITCH, 0xC0 + 1, BRETURN, 0xC0 + 2, BRETURN };
    var consts = [_]u64{ 111, 222, 999 };
    const res = try compile(&arena, &opcodes, 8, freloc_slot, &consts, 0, &[_]u32{ 3, 5 }, 0);
    var args: [1]u64 = .{0};
    try testing.expectEqual(@as(u64, 222), res.entry(0, &args));
}

test "compile and run: AOT-parity helper opcodes preserve stack effects" {
    var arena = try jit.ExecArena.allocate(jit.page_size);
    defer arena.deinit();

    const Shim = struct {
        fn symbolp(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 91;
        }
        fn eq(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 42;
        }
        fn point(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 77;
        }
        fn save_excursion(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0;
        }
        fn unwind_protect(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0;
        }
    };
    var freloc_table = [_]*const anyopaque{undefined} ** 103;
    freloc_table[IDX_SYMBOLP] = &Shim.symbolp;
    freloc_table[IDX_EQ] = &Shim.eq;
    freloc_table[IDX_POINT] = &Shim.point;
    freloc_table[IDX_SAVE_EXCURSION] = &Shim.save_excursion;
    freloc_table[IDX_UNWIND_PROTECT] = &Shim.unwind_protect;
    var freloc_base: *const anyopaque = &freloc_table;
    const freloc_slot: *const *const anyopaque = &freloc_base;
    var consts = [_]u64{ 111, 222 };
    var args: [1]u64 = .{0};

    const unary_ops = [_]u8{ 0xC0, BSYMBOLP, BRETURN };
    const unary = try compile(&arena, &unary_ops, 8, freloc_slot, &consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 91), unary.entry(0, &args));

    var eq_arena = try jit.ExecArena.allocate(jit.page_size);
    defer eq_arena.deinit();
    const binary_ops = [_]u8{ 0xC0, 0xC0 + 1, BEQ, BRETURN };
    const eq = try compile(&eq_arena, &binary_ops, 8, freloc_slot, &consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 42), eq.entry(0, &args));

    var push_arena = try jit.ExecArena.allocate(jit.page_size);
    defer push_arena.deinit();
    const push_ops = [_]u8{ BPOINT, BRETURN };
    const push = try compile(&push_arena, &push_ops, 8, freloc_slot, &consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 77), push.entry(0, &args));

    var noarg_arena = try jit.ExecArena.allocate(jit.page_size);
    defer noarg_arena.deinit();
    const noarg_ops = [_]u8{ 0xC0, BSAVE_EXCURSION, BRETURN };
    const noarg = try compile(&noarg_arena, &noarg_ops, 8, freloc_slot, &consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 111), noarg.entry(0, &args));

    var pop_arena = try jit.ExecArena.allocate(jit.page_size);
    defer pop_arena.deinit();
    const pop_ops = [_]u8{ 0xC0, 0xC0 + 1, BUNWIND_PROTECT, BRETURN };
    const pop = try compile(&pop_arena, &pop_ops, 8, freloc_slot, &consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 111), pop.entry(0, &args));
}

test "compile and run: discard-N with and without TOP preservation" {
    var arena = try jit.ExecArena.allocate(jit.page_size);
    defer arena.deinit();

    var freloc_base: u64 = 0;
    const freloc_slot: *const *const anyopaque = @ptrCast(&freloc_base);
    var consts = [_]u64{ 111, 222, 333 };
    const consts_ptr: [*]const u64 = &consts;
    var args: [1]u64 = .{0};

    // push 111; push 222; push 333; discardN|0x80 (2) -> [111,333].
    const preserve = [_]u8{ 0xC0, 0xC1, 0xC2, BDISCARD_N, (2 | 0x80), BRETURN };
    const p1 = try compile(&arena, &preserve, 8, freloc_slot, consts_ptr, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 333), p1.entry(0, &args));

    // Fresh arena: push 111/222/333; discardN(2) -> [111].
    var discard_arena = try jit.ExecArena.allocate(jit.page_size);
    defer discard_arena.deinit();
    const plain = [_]u8{ 0xC0, 0xC1, 0xC2, BDISCARD_N, 2, BRETURN };
    const p2 = try compile(&discard_arena, &plain, 8, freloc_slot, consts_ptr, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 111), p2.entry(0, &args));
}

test "compile and run: wide discard-N uses the 32-bit stack adjustment" {
    var arena = try jit.ExecArena.allocate(jit.page_size * 4);
    defer arena.deinit();

    var freloc_base: u64 = 0;
    const freloc_slot: *const *const anyopaque = @ptrCast(&freloc_base);
    var consts = [_]u64{0} ** 17;
    const consts_ptr: [*]const u64 = &consts;
    var args: [1]u64 = .{0};
    const marker: u64 = 0x51DE110;
    consts[16] = marker;

    // Push 17 values, preserve TOP (the marker pushed as constants[16]) while
    // discarding 16 slots, and return TOP.  The resulting r12 adjustment is
    // 128 bytes, so the encoder must select `sub r12, imm32`; the old
    // imm8-only encoder could panic/truncate for any discard count above 15.
    var ops: [20]u8 = undefined;
    for (0..17) |i| ops[i] = @intCast(BCONSTANT_BASE + i);
    ops[17] = BDISCARD_N;
    ops[18] = 0x80 | 16;
    ops[19] = BRETURN;

    const entry = try compile(&arena, &ops, 17, freloc_slot, consts_ptr, 0, &[_]u32{}, 0);
    try testing.expectEqual(marker, entry.entry(0, &args));
}

test "emitter capacity overflow stops all later writes" {
    var buf: [5]u8 = @splat(0xaa);
    var em = Emitter{
        .allocator = testing.allocator,
        .buf = &buf,
        .patches = .empty,
        .blocks = .init(testing.allocator),
    };
    defer em.blocks.deinit();

    // Fill the buffer exactly, then provoke byte and multi-byte overflows.
    em.raw(0x11);
    em.imm32(0x22334455);
    try testing.expectEqual(@as(u32, 5), em.pos);
    try testing.expect(!em.overflow);

    em.raw(0x66);
    em.imm64(0x778899aabbccdde1);
    try testing.expect(em.overflow);
    try testing.expectEqual(@as(u32, 5), em.pos);
    try testing.expectEqualSlices(u8, &.{ 0x11, 0x55, 0x44, 0x33, 0x22 }, &buf);
}

test "branch-patch allocation failure fails closed" {
    var buf: [32]u8 = undefined;
    var blocks = std.AutoHashMap(u32, u32).init(testing.allocator);
    defer blocks.deinit();
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    var em = Emitter{
        .allocator = failing.allocator(),
        .buf = &buf,
        .patches = .empty,
        .blocks = blocks,
    };

    // A missing patch record would leave rel32 at zero and turn a Lisp
    // branch into a jump to address zero.  Allocation failure must reject
    // the compilation instead.
    try testing.expectError(Error.OutOfMemory, em.emitJump(0));
    try testing.expectEqual(@as(usize, 0), em.patches.items.len);
}

// ---------------------------------------------------------------------------
// C ABI: the entry src/compz.c's hotness shim calls.  freloc_slot points
// at a C-side pointer-to-table (compz.c exposes zeln_freloc.link_table
// through a stable address).  Returns null when the bytecode uses opcodes
// outside the supported subset (caller silently falls back to the
// interpreter).
// ---------------------------------------------------------------------------

/// Executable chunks live for the process because generated code can be
/// called again after later GC cycles.  Unlike the original single 4 MiB
/// arena, however, a long-lived Emacs session now opens a fresh chunk when
/// one fills instead of silently disabling all further JIT compilation.
var g_arenas: std.ArrayListUnmanaged(jit.ExecArena) = .empty;

fn nextCompileArena(min_capacity: usize) ?*jit.ExecArena {
    const chunk_size = @max(min_capacity, 4 * 1024 * 1024);
    if (g_arenas.items.len == 0) {
        g_arenas.append(std.heap.smp_allocator, jit.ExecArena.allocate(chunk_size) catch return null) catch return null;
    }
    const current = &g_arenas.items[g_arenas.items.len - 1];
    if (current.len - current.used >= min_capacity) return current;
    g_arenas.append(std.heap.smp_allocator, jit.ExecArena.allocate(chunk_size) catch return null) catch return null;
    return &g_arenas.items[g_arenas.items.len - 1];
}

export fn zeln_jit_compile_closure(
    bc: [*]const u8,
    bc_len: usize,
    stack_depth: u32,
    arity: u32,
    consts: [*]const u64,
    freloc_slot: *const *const anyopaque,
    switch_targets: [*]const u32,
    switch_target_count: usize,
    qt_raw: u64,
) ?*const fn (i64, [*]const u64) callconv(.c) u64 {
    const estimated_capacity: usize = @as(usize, bc_len) *| 48 +|
        switch_target_count *| 64 +| 256;
    const arena = nextCompileArena(estimated_capacity) orelse return null;
    const res = compile(
        arena,
        bc[0..bc_len],
        stack_depth,
        freloc_slot,
        consts,
        arity,
        switch_targets[0..switch_target_count],
        qt_raw,
    ) catch return null;
    return res.entry;
}

test "temporary tagged comparisons and branch integration" {
    var arena = try jit.ExecArena.allocate(jit.page_size * 16);
    defer arena.deinit();
    const Shim = struct {
        fn fallback(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0xAAA2;
        }
    };
    var freloc_table = [_]*const anyopaque{undefined} ** 16;
    for (IDX_EQLSIGN..IDX_GEQ + 1) |i| freloc_table[i] = &Shim.fallback;
    var freloc_base: *const anyopaque = &freloc_table;
    const freloc_slot: *const *const anyopaque = &freloc_base;
    var args: [1]u64 = .{0};
    const tagged = struct {
        fn fixnum(n: i64) u64 {
            return @bitCast((n << 2) | 2);
        }
    }.fixnum;
    var consts = [_]u64{ tagged(3), tagged(2), 111, 222 };
    const Case = struct { op: u8, expected: u64 };
    const cases = [_]Case{
        .{ .op = BEQLSIGN, .expected = 222 },
        .{ .op = BGTR, .expected = 111 },
        .{ .op = BLSS, .expected = 222 },
        .{ .op = BLEQ, .expected = 222 },
        .{ .op = BGEQ, .expected = 111 },
    };
    inline for (cases) |case| {
        const ops = [_]u8{
            0xC0, // 0: a
            0xC0 + 1, // 1: b
            case.op, // 2
            BGOTOIFNIL, // 3: false jumps to 7
            8,
            0,
            0xC0 + 2, // 5: true marker
            BRETURN, // 6
            0xC0 + 3, // 7: false marker
            BRETURN, // 8
        };
        const res = try compile(&arena, &ops, 8, freloc_slot, &consts, 0, &[_]u32{}, 0xAAAA);
        try testing.expectEqual(case.expected, res.entry(0, &args));
    }
}

test "compile and run: tagged multiply fast path and primitive fallback" {
    var arena = try jit.ExecArena.allocate(jit.page_size * 8);
    defer arena.deinit();

    const Shim = struct {
        fn times(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0xAAAA;
        }
    };
    var freloc_table = [_]*const anyopaque{undefined} ** 6;
    freloc_table[IDX_TIMES] = &Shim.times;
    var freloc_base: *const anyopaque = &freloc_table;
    const freloc_slot: *const *const anyopaque = &freloc_base;
    var args: [1]u64 = .{0};
    const tagged = struct {
        fn fixnum(n: i64) u64 {
            return @bitCast((n << 2) | 2);
        }
    }.fixnum;
    const ops = [_]u8{ 0xC0, 0xC0 + 1, BMULT, BRETURN };

    var normal_consts = [_]u64{ tagged(7), tagged(-6) };
    const normal = try compile(&arena, &ops, 8, freloc_slot, &normal_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(tagged(-42), normal.entry(0, &args));

    // Any non-fixnum raw word must reach the same C primitive as AOT.
    var fallback_consts = [_]u64{ 8, tagged(2) };
    const fallback = try compile(&arena, &ops, 8, freloc_slot, &fallback_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 0xAAAA), fallback.entry(0, &args));

    // 2^61-1 squared overflows both int64 and the fixnum range.
    const most_positive = tagged(0x1FFF_FFFF_FFFF_FFFF);
    var overflow_consts = [_]u64{ most_positive, most_positive };
    const overflow = try compile(&arena, &ops, 8, freloc_slot, &overflow_consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 0xAAAA), overflow.entry(0, &args));
}

test "inline cons slots and primitive fallback" {
    var arena = try jit.ExecArena.allocate(jit.page_size);
    defer arena.deinit();
    const Shim = struct {
        fn car(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0xAAAA;
        }
        fn cdr(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0xBBBB;
        }
    };
    var freloc_table = [_]*const anyopaque{undefined} ** 21;
    freloc_table[IDX_CAR] = &Shim.car;
    freloc_table[IDX_CDR] = &Shim.cdr;
    var freloc_base: *const anyopaque = &freloc_table;
    const freloc_slot: *const *const anyopaque = &freloc_base;
    var args: [1]u64 = .{0};
    var cell align(16) = [_]u64{ 0x1234, 0x5678 };
    const cons_raw = @intFromPtr(&cell) | 3;

    var consts = [_]u64{cons_raw};
    const car_ops = [_]u8{ 0xC0, BCAR, BRETURN };
    const car = try compile(&arena, &car_ops, 8, freloc_slot, &consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 0x1234), car.entry(0, &args));

    var cdr_arena = try jit.ExecArena.allocate(jit.page_size);
    defer cdr_arena.deinit();
    const cdr_ops = [_]u8{ 0xC0, BCDR, BRETURN };
    const cdr = try compile(&cdr_arena, &cdr_ops, 8, freloc_slot, &consts, 0, &[_]u32{}, 0);
    try testing.expectEqual(@as(u64, 0x5678), cdr.entry(0, &args));

    // The generated fast path must preserve exact fallback behavior for
    // every non-cons Lisp word.  Reuse the baked constants pointer rather
    // than compiling a separate closure.
    consts[0] = 0; // Qnil reaches the freloc helper, never a fake cons.
    try testing.expectEqual(@as(u64, 0xAAAA), car.entry(0, &args));
    try testing.expectEqual(@as(u64, 0xBBBB), cdr.entry(0, &args));
}

test "inline consp and not predicates" {
    var arena = try jit.ExecArena.allocate(jit.page_size);
    defer arena.deinit();
    var args: [1]u64 = .{0};
    var freloc_base: *const anyopaque = undefined;
    const freloc_slot: *const *const anyopaque = &freloc_base;
    const qt = 0xAAAA;
    var cell align(16) = [_]u64{ 1, 2 };
    var operand: u64 = @intFromPtr(&cell) | 3;
    const operand_ptr: [*]const u64 = @ptrCast(&operand);
    const cons_ops = [_]u8{ 0xC0, BCONSP, BRETURN };
    const consp = try compile(&arena, &cons_ops, 8, freloc_slot, operand_ptr, 0, &[_]u32{}, qt);
    try testing.expectEqual(qt, consp.entry(0, &args));
    operand = 0;
    try testing.expectEqual(@as(u64, 0), consp.entry(0, &args));
    operand = 42;
    try testing.expectEqual(@as(u64, 0), consp.entry(0, &args));

    var not_arena = try jit.ExecArena.allocate(jit.page_size);
    defer not_arena.deinit();
    const not_ops = [_]u8{ 0xC0, BNOT, BRETURN };
    operand = 0;
    const isnil = try compile(&not_arena, &not_ops, 8, freloc_slot, operand_ptr, 0, &[_]u32{}, qt);
    try testing.expectEqual(qt, isnil.entry(0, &args));
    operand = 42;
    try testing.expectEqual(@as(u64, 0), isnil.entry(0, &args));
}

test "inline representation predicates keep exact fallback" {
    var arena = try jit.ExecArena.allocate(jit.page_size * 8);
    defer arena.deinit();
    const Shim = struct {
        fn symbolp(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0x1001;
        }
        fn stringp(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0x2002;
        }
        fn listp(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0x3003;
        }
        fn numberp(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0x4004;
        }
        fn integerp(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            _ = args;
            return 0x5005;
        }
    };
    var freloc_table = [_]*const anyopaque{undefined} ** 33;
    freloc_table[IDX_SYMBOLP] = &Shim.symbolp;
    freloc_table[IDX_STRINGP] = &Shim.stringp;
    freloc_table[IDX_LISTP] = &Shim.listp;
    freloc_table[IDX_NUMBERP] = &Shim.numberp;
    freloc_table[IDX_INTEGERP] = &Shim.integerp;
    var freloc_base: *const anyopaque = &freloc_table;
    const freloc_slot: *const *const anyopaque = &freloc_base;
    var args: [1]u64 = .{0};
    const qt = 0xAAAA;
    var operand: u64 = 0;
    const operand_ptr: [*]const u64 = @ptrCast(&operand);
    const tagged = struct {
        fn fixnum(n: i64) u64 {
            return @bitCast((n << 2) | 2);
        }
    }.fixnum;

    const Case = struct {
        op: u8,
        idx: u64,
        true_raw: u64,
        false_raw: u64,
        yes: u64,
        no: u64,
    };
    const cases = [_]Case{
        .{ .op = BSYMBOLP, .idx = IDX_SYMBOLP, .true_raw = 0x1000, .false_raw = 0x1004, .yes = qt, .no = 0x1001 },
        .{ .op = BSTRINGP, .idx = IDX_STRINGP, .true_raw = 0x1004, .false_raw = 0x1000, .yes = qt, .no = 0x2002 },
        .{ .op = BLISTP, .idx = IDX_LISTP, .true_raw = 0x1003, .false_raw = 0x1004, .yes = qt, .no = 0x3003 },
        .{ .op = BNUMBERP, .idx = IDX_NUMBERP, .true_raw = tagged(7), .false_raw = 0x1004, .yes = qt, .no = 0x4004 },
        .{ .op = BINTEGERP, .idx = IDX_INTEGERP, .true_raw = tagged(7), .false_raw = 0x1004, .yes = qt, .no = 0x5005 },
    };
    inline for (cases) |case| {
        const ops = [_]u8{ 0xC0, case.op, BRETURN };
        const compiled = try compile(
            &arena,
            &ops,
            8,
            freloc_slot,
            operand_ptr,
            0,
            &[_]u32{},
            qt,
        );
        operand = case.true_raw;
        try testing.expectEqual(case.yes, compiled.entry(0, &args));
        operand = case.false_raw;
        try testing.expectEqual(case.no, compiled.entry(0, &args));
    }

    // Blistp has two immediate true representations.
    const list_ops = [_]u8{ 0xC0, BLISTP, BRETURN };
    const listp = try compile(&arena, &list_ops, 8, freloc_slot, operand_ptr, 0, &[_]u32{}, qt);
    operand = 0x1003;
    try testing.expectEqual(qt, listp.entry(0, &args));
    operand = 0;
    try testing.expectEqual(qt, listp.entry(0, &args));
    operand = 42;
    try testing.expectEqual(@as(u64, 0x3003), listp.entry(0, &args));
}
