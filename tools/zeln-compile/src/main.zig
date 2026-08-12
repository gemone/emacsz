//! zeln-compile: the native-compilation tool for the HAVE_NATIVE_COMP_ZIG
//! path (produces `.zeln` from a zunit). It is a separate process per the
//! C<->Zig boundary (plan section 4.1): temacs serializes a zunit; this
//! tool parses it, emits LLVM IR (`.ll`), and drives `zig cc -shared` to
//! produce the `.zeln`.
//!
//! Two zunit formats are accepted (dispatched on the zabi_version byte):
//!
//!   zabi=1 (M0 spike): the hardcoded single-fn zunit written by
//!     comp-z-write-spike-zunit.  The fixed Tier-0 emitter (emitSpikeLLVM)
//!     produces a constant `.ll` for it.  Kept so the M0 CI regression
//!     (plan section 8 / build step `zeln-compile-spike`) stays green
//!     after the entry-struct native_fn moved to the MANY convention and
//!     the freloc surface was generalized in M1.
//!
//!   zabi=2 (M1): a REAL compiled closure serialized by
//!     comp-z-write-zunit.  emitM1LLVM is a bytecode-driven Tier-0
//!     emitter: it decodes the opcodes at compile time (interpreter
//!     FETCH/FETCH2 semantics), REJECTs any opcode outside the M1 subset
//!     (so unsupported opcodes cannot silently misbehave), pre-scans
//!     branch targets into LLVM basic blocks, and lowers each opcode to
//!     straight-line IR over an alloca virtual stack + %top.slot pointer,
//!     calling freloc[IDX_*] for each call/arith/list op.  This is
//!     "unfold dispatch" (plan section 10 lever 1) even at Tier-0; what
//!     Tier-0 keeps in memory is the STACK (Tier-1 virtual-stack->SSA +
//!     specialization is M3).
//!
//! Usage: zeln-compile <zunit-path> <manifest-path> <output-zeln-path>
//! Reads <zunit-path> (binary) + <manifest-path> (ASCII), writes a .ll
//! next to the output, then runs `zig cc -shared` to produce the .zeln.

const std = @import("std");

// "ZUNT" little-endian. Written by src/compz.c's serializers.
const ZUNIT_MAGIC: u32 = 0x5A554E54;

// The freloc surface size — MUST match src/compz.c's ZELN_F_RELOC_COUNT.
// The IR's getelementptr type is `[SURFACE x ptr]` over the loader-patched
// link-table base.  Frozen order: the IDX_* below mirror the compz.c enum.
const SURFACE: u64 = 101;

const IDX_SETUP_ARGS: u64 = 0;
const IDX_FUNCALL: u64 = 1;
const IDX_NILP: u64 = 2;
const IDX_PLUS: u64 = 3;
const IDX_MINUS: u64 = 4;
const IDX_TIMES: u64 = 5;
const IDX_SUB1: u64 = 6;
const IDX_ADD1: u64 = 7;
const IDX_NEGATE: u64 = 8;
const IDX_MAX: u64 = 9;
const IDX_MIN: u64 = 10;
const IDX_EQLSIGN: u64 = 11;
const IDX_GTR: u64 = 12;
const IDX_LSS: u64 = 13;
const IDX_LEQ: u64 = 14;
const IDX_GEQ: u64 = 15;
const IDX_EQUAL: u64 = 16;
const IDX_EQ: u64 = 17;
const IDX_NULL: u64 = 18;
const IDX_CAR: u64 = 19;
const IDX_CDR: u64 = 20;
const IDX_CONS: u64 = 21;
const IDX_LIST1: u64 = 22;
const IDX_LIST2: u64 = 23;
const IDX_LIST3: u64 = 24;
const IDX_LIST4: u64 = 25;
const IDX_LIST: u64 = 26;
const IDX_SYMBOLP: u64 = 27;
const IDX_CONSP: u64 = 28;
const IDX_STRINGP: u64 = 29;
const IDX_LISTP: u64 = 30;
const IDX_NUMBERP: u64 = 31;
const IDX_INTEGERP: u64 = 32;
// ---- M2 surface (must mirror the appended tail of compz.c's IDX enum). ----
const IDX_NTH: u64 = 33;
const IDX_MEMQ: u64 = 34;
const IDX_LENGTH: u64 = 35;
const IDX_AREF: u64 = 36;
const IDX_ASET: u64 = 37;
const IDX_SYMBOL_VALUE: u64 = 38;
const IDX_SYMBOL_FUNCTION: u64 = 39;
const IDX_SET: u64 = 40;
const IDX_FSET: u64 = 41;
const IDX_GET: u64 = 42;
const IDX_SUBSTRING: u64 = 43;
const IDX_CONCAT: u64 = 44;
const IDX_STRING_EQUAL: u64 = 45;
const IDX_STRING_LESSP: u64 = 46;
const IDX_NTHCDR: u64 = 47;
const IDX_ELT: u64 = 48;
const IDX_MEMBER: u64 = 49;
const IDX_ASSQ: u64 = 50;
const IDX_NREVERSE: u64 = 51;
const IDX_SETCAR: u64 = 52;
const IDX_SETCDR: u64 = 53;
const IDX_CAR_SAFE: u64 = 54;
const IDX_CDR_SAFE: u64 = 55;
const IDX_NCONC: u64 = 56;
const IDX_QUO: u64 = 57;
const IDX_REM: u64 = 58;
const IDX_GOTO_CHAR: u64 = 59;
const IDX_INSERT: u64 = 60;
const IDX_CHAR_AFTER: u64 = 61;
const IDX_INDENT_TO: u64 = 62;
const IDX_FORWARD_CHAR: u64 = 63;
const IDX_FORWARD_WORD: u64 = 64;
const IDX_FORWARD_LINE: u64 = 65;
const IDX_CHAR_SYNTAX: u64 = 66;
const IDX_END_OF_LINE: u64 = 67;
const IDX_MATCH_BEGINNING: u64 = 68;
const IDX_MATCH_END: u64 = 69;
const IDX_UPCASE: u64 = 70;
const IDX_DOWNCASE: u64 = 71;
const IDX_POINT: u64 = 72;
const IDX_POINT_MAX: u64 = 73;
const IDX_POINT_MIN: u64 = 74;
const IDX_FOLLOWING_CHAR: u64 = 75;
const IDX_PRECEDING_CHAR: u64 = 76;
const IDX_CURRENT_COLUMN: u64 = 77;
const IDX_EOLP: u64 = 78;
const IDX_EOBP: u64 = 79;
const IDX_BOLP: u64 = 80;
const IDX_BOBP: u64 = 81;
const IDX_CURRENT_BUFFER: u64 = 82;
const IDX_SET_BUFFER: u64 = 83;
const IDX_SKIP_CHARS_FORWARD: u64 = 84;
const IDX_SKIP_CHARS_BACKWARD: u64 = 85;
const IDX_BUFFER_SUBSTRING: u64 = 86;
const IDX_DELETE_REGION: u64 = 87;
const IDX_NARROW_TO_REGION: u64 = 88;
const IDX_WIDEN: u64 = 89;
const IDX_SET_MARKER: u64 = 90;
const IDX_VARSET: u64 = 91;
const IDX_VARBIND: u64 = 92;
const IDX_UNBIND: u64 = 93;
const IDX_SAVE_EXCURSION: u64 = 94;
const IDX_SAVE_CURRENT_BUFFER: u64 = 95;
const IDX_SAVE_RESTRICTION: u64 = 96;
const IDX_UNWIND_PROTECT: u64 = 97;
const IDX_PUSHHANDLER: u64 = 98;
const IDX_RESUME: u64 = 99;
const IDX_POPHANDLER: u64 = 100;

// ---- FRELOC_NAMES: the Zig-side mirror of compz.c's zeln_imports[] order.
// Positional (slot i = the subr at freloc slot i), in the SAME order as the
// IDX_* constants above.  The ABI hash (Vzeln_abi_hash) is computed by
// compz.c over ITS OWN zeln_imports[] only, so a hand-mirror drift here
// (insert/reorder/rename) would pass the hash gate while the .zeln's freloc
// calls land on the wrong subrs.  verifyFrelocSurface() parses the ordered
// signature the manifest carries (compz.c zeln_signature_string) and fails
// the compile if the count or any positional name disagrees -- the mirror is
// CHECKED on every zeln-compile run, not just by the dev-time differential.
const FRELOC_NAMES = [_][]const u8{
    "zeln-setup-args",          // 0
    "zeln-funcall",             // 1
    "zeln-isnil",               // 2
    "+",                        // 3
    "-",                        // 4
    "*",                        // 5
    "1-",                       // 6
    "1+",                       // 7
    "negate",                   // 8
    "max",                      // 9
    "min",                      // 10
    "=",                        // 11
    ">",                        // 12
    "<",                        // 13
    "<=",                       // 14
    ">=",                       // 15
    "equal",                    // 16
    "eq",                       // 17
    "null",                     // 18
    "car",                      // 19
    "cdr",                      // 20
    "cons",                     // 21
    "list1",                    // 22
    "list2",                    // 23
    "list3",                    // 24
    "list4",                    // 25
    "list",                     // 26
    "symbolp",                  // 27
    "consp",                    // 28
    "stringp",                  // 29
    "listp",                    // 30
    "numberp",                  // 31
    "integerp",                 // 32
    "nth",                      // 33
    "memq",                     // 34
    "length",                   // 35
    "aref",                     // 36
    "aset",                     // 37
    "symbol-value",             // 38
    "symbol-function",          // 39
    "set",                      // 40
    "fset",                     // 41
    "get",                      // 42
    "substring",                // 43
    "concat",                   // 44
    "string=",                  // 45
    "string-lessp",             // 46
    "nthcdr",                   // 47
    "elt",                      // 48
    "member",                   // 49
    "assq",                     // 50
    "nreverse",                 // 51
    "setcar",                   // 52
    "setcdr",                   // 53
    "car-safe",                 // 54
    "cdr-safe",                 // 55
    "nconc",                    // 56
    "/",                        // 57
    "%",                        // 58
    "goto-char",                // 59
    "insert",                   // 60
    "char-after",               // 61
    "indent-to",                // 62
    "forward-char",             // 63
    "forward-word",             // 64
    "forward-line",             // 65
    "char-syntax",              // 66
    "end-of-line",              // 67
    "match-beginning",          // 68
    "match-end",                // 69
    "upcase",                   // 70
    "downcase",                 // 71
    "point",                    // 72
    "point-max",                // 73
    "point-min",                // 74
    "following-char",           // 75
    "previous-char",            // 76
    "current-column",           // 77
    "eolp",                     // 78
    "eobp",                     // 79
    "bolp",                     // 80
    "bobp",                     // 81
    "current-buffer",           // 82
    "set-buffer",               // 83
    "skip-chars-forward",       // 84
    "skip-chars-backward",      // 85
    "buffer-substring",         // 86
    "delete-region",            // 87
    "narrow-to-region",         // 88
    "widen",                    // 89
    "set-marker",               // 90
    "zeln-varset",              // 91
    "zeln-varbind",             // 92
    "zeln-unbind",              // 93
    "zeln-save-excursion",      // 94
    "zeln-save-current-buffer", // 95
    "zeln-save-restriction",    // 96
    "zeln-unwind-protect",      // 97
    "zeln-pushhandler",         // 98
    "zeln-resume",              // 99
    "zeln-pophandler",          // 100
};
comptime {
    if (FRELOC_NAMES.len != SURFACE)
        @compileError("FRELOC_NAMES length != SURFACE: update both (freloc surface drift)");
}


// ---- Tier-1 fixnum-arith inline fast path (USE_LSB_TAG). ----------------
// Mirrors src/lisp.h for USE_LSB_TAG=true: a fixnum's low 2 bits are
// Lisp_Int0 (== 2), bit 2 is value, so FIXNUMP(x) = (x & 3) == 2,
// XFIXNUM(x) = x >> 2 (arithmetic), make_fixnum(n) = (n << 2) | 2.
// Valid on every Tier-1 target (all 64-bit, so VALMAX/2 < INTPTR_MAX), and
// the .zeln is built+loaded by the SAME emacs binary (Vzeln_abi_hash + build
// identity already bind it).  Asserted at .zeln load (zeln_freloc_check_fill).
// The constant values mirror src/lisp.h byte-for-byte (EMACS_INT_MAX >> 2).
const FIXNUM_LSB_TAG: i64 = 2; // Lisp_Int0: low 2 bits of a fixnum
const FIXNUM_LSB_MASK: i64 = 3; // FIXNUMP(x) = (x & 3) == 2
const FIXNUM_SHIFT: u6 = 2; // INTTYPEBITS = GCTYPEBITS - 1 = 2
const MOST_POSITIVE_FIXNUM: i64 = 2305843009213693951; // EMACS_INT_MAX >> 2
const MOST_NEGATIVE_FIXNUM: i64 = -2305843009213693952; // -1 - MOST_POSITIVE_FIXNUM

// ---- Tier-1 cons-slot inline fast path (M3b). ---------------------------
// CONSP / XCONS under USE_LSB_TAG (lisp.h:492,519): Lisp_Cons = 3,
// XTYPE(x) = x & 7 (VALMASK = -(1 << GCTYPEBITS) = -8), so CONSP(x) is
// (x & 7) == 3 and XCONS(x) = XUNTAG = clear the low GCTYPEBITS tag bits
// = x & -8 (conses are GCALIGNMENT = 1 << GCTYPEBITS = 8-byte aligned, so
// the cleared bits are exactly the tag).  Valid on every Tier-1 target
// (all 64-bit + LSB_TAG, same as the M3a fixnum inline) and bound to the
// build by Vzeln_abi_hash; the USE_LSB_TAG assumption is asserted at .zeln
// load (compz.c zeln_freloc_check_fill eassert(USE_LSB_TAG)).  Cons slot
// layout is fixed by struct Lisp_Cons (lisp.h:1425): car @ 0, cdr @ 8
// (each a Lisp_Object = EMACS_INT = i64), GCALIGNED.
const CONSP_TAG: i64 = 3; // Lisp_Cons (USE_LSB_TAG ? 3 : 6)
const CONSP_MASK: i64 = 7; // CONSP(x) = (x & 7) == 3  (= ~VALMASK)
const XCONS_UNTAG_MASK: i64 = -8; // XCONS(x) = x & -8  (clear low GCTYPEBITS)
const XCAR_OFFSET: u6 = 0; // struct Lisp_Cons u.s.car (i64 index 0)
const XCDR_OFFSET: u6 = 1; // struct Lisp_Cons u.s.u.cdr (i64 index 1, byte 8)

// M1 opcode subset (values are decimal; mirror src/bytecode.c DEFINE).
// Any opcode NOT classified here is REJECTed at compile time (no .zeln),
// bounding the differential test to proven fns.  M2 widens the subset.
const OPCODE_BCONSTANT_BASE: u8 = 192; // Bconstant bytes 0xC0..0xFF -> idx 0..63
const OPCODE_BSTACK_REF1: u8 = 1;
const OPCODE_BSTACK_REF5: u8 = 5;
const OPCODE_BSTACK_REF6: u8 = 6;
const OPCODE_BSTACK_REF7: u8 = 7;
const OPCODE_BCALL: u8 = 32; // Bcall..Bcall5 = 32..37 (arg = op-Bcall)
const OPCODE_BCALL5: u8 = 37;
const OPCODE_BCALL6: u8 = 38; // arg = FETCH
const OPCODE_BCALL7: u8 = 39; // arg = FETCH2
const OPCODE_BSYMBOLP: u8 = 57;
const OPCODE_BCONSP: u8 = 58;
const OPCODE_BSTRINGP: u8 = 59;
const OPCODE_BLISTP: u8 = 60;
const OPCODE_BEQ: u8 = 61;
const OPCODE_BNOT: u8 = 63;
const OPCODE_BCAR: u8 = 64;
const OPCODE_BCDR: u8 = 65;
const OPCODE_BCONS: u8 = 66;
const OPCODE_BLIST1: u8 = 67;
const OPCODE_BLIST2: u8 = 68;
const OPCODE_BLIST3: u8 = 69;
const OPCODE_BLIST4: u8 = 70;
const OPCODE_BSUB1: u8 = 83;
const OPCODE_BADD1: u8 = 84;
const OPCODE_BEQLSIGN: u8 = 85;
const OPCODE_BGTR: u8 = 86;
const OPCODE_BLSS: u8 = 87;
const OPCODE_BLEQ: u8 = 88;
const OPCODE_BGEQ: u8 = 89;
const OPCODE_BDIFF: u8 = 90;
const OPCODE_BNEGATE: u8 = 91;
const OPCODE_BPLUS: u8 = 92;
const OPCODE_BMAX: u8 = 93;
const OPCODE_BMIN: u8 = 94;
const OPCODE_BMULT: u8 = 95;
const OPCODE_BCONSTANT2: u8 = 129;
const OPCODE_BGOTO: u8 = 130;
const OPCODE_BGOTOIFNIL: u8 = 131;
const OPCODE_BGOTOIFNONNIL: u8 = 132;
const OPCODE_BGOTOIFNILELSEPOP: u8 = 133;
const OPCODE_BGOTOIFNONNILELSEPOP: u8 = 134;
const OPCODE_BRETURN: u8 = 135;
const OPCODE_BDISCARD: u8 = 136;
const OPCODE_BDUP: u8 = 137;
const OPCODE_BEQUAL: u8 = 154;
const OPCODE_BNUMBERP: u8 = 167;
const OPCODE_BINTEGERP: u8 = 168;
const OPCODE_BLISTN: u8 = 175;
const OPCODE_BSTACK_SET: u8 = 178; // arg = FETCH: ptr=top[-arg]; *ptr = POP
const OPCODE_BSTACK_SET2: u8 = 179; // arg = FETCH2

// ---- M2 opcode subset (values are decimal; mirror src/bytecode.c DEFINE,
// which uses OCTAL — converted here).  Ranges are decoded as families. ----
const OPCODE_BVARREF: u8 = 8; // Bvarref..Bvarref5 = 8..13 (arg = op-Bvarref)
const OPCODE_BVARREF5: u8 = 13;
const OPCODE_BVARREF6: u8 = 14; // arg = FETCH
const OPCODE_BVARREF7: u8 = 15; // arg = FETCH2

const OPCODE_BVARSET: u8 = 16; // Bvarset..Bvarset5 = 16..21 (arg = op-Bvarset)
const OPCODE_BVARSET5: u8 = 21;
const OPCODE_BVARSET6: u8 = 22; // arg = FETCH
const OPCODE_BVARSET7: u8 = 23; // arg = FETCH2

const OPCODE_BVARBIND: u8 = 24; // Bvarbind..Bvarbind5 = 24..29 (arg = op-Bvarbind)
const OPCODE_BVARBIND5: u8 = 29;
const OPCODE_BVARBIND6: u8 = 30; // arg = FETCH
const OPCODE_BVARBIND7: u8 = 31; // arg = FETCH2

const OPCODE_BUNBIND: u8 = 40; // Bunbind..Bunbind5 = 40..45 (arg = op-Bunbind)
const OPCODE_BUNBIND5: u8 = 45;
const OPCODE_BUNBIND6: u8 = 46; // arg = FETCH
const OPCODE_BUNBIND7: u8 = 47; // arg = FETCH2

const OPCODE_BPOPHANDLER: u8 = 48;
const OPCODE_BPUSHCONDITIONCASE: u8 = 49; // FETCH2 = handler-body offset
const OPCODE_BPUSHCATCH: u8 = 50; // FETCH2 = handler-body offset

const OPCODE_BNTH: u8 = 56;
const OPCODE_BMEMQ: u8 = 62;
const OPCODE_BLENGTH: u8 = 71;
const OPCODE_BAREF: u8 = 72;
const OPCODE_BASET: u8 = 73;
const OPCODE_BSYMBOL_VALUE: u8 = 74;
const OPCODE_BSYMBOL_FUNCTION: u8 = 75;
const OPCODE_BSET: u8 = 76;
const OPCODE_BFSET: u8 = 77;
const OPCODE_BGET: u8 = 78;
const OPCODE_BSUBSTRING: u8 = 79;
const OPCODE_BCONCAT2: u8 = 80;
const OPCODE_BCONCAT3: u8 = 81;
const OPCODE_BCONCAT4: u8 = 82;
const OPCODE_BPOINT: u8 = 96;
const OPCODE_BGOTO_CHAR: u8 = 98;
const OPCODE_BINSERT: u8 = 99;
const OPCODE_BPOINT_MAX: u8 = 100;
const OPCODE_BPOINT_MIN: u8 = 101;
const OPCODE_BCHAR_AFTER: u8 = 102;
const OPCODE_BFOLLOWING_CHAR: u8 = 103;
const OPCODE_BPRECEDING_CHAR: u8 = 104;
const OPCODE_BCURRENT_COLUMN: u8 = 105;
const OPCODE_BINDENT_TO: u8 = 106;
const OPCODE_BEOLP: u8 = 108;
const OPCODE_BEOBP: u8 = 109;
const OPCODE_BBOLP: u8 = 110;
const OPCODE_BBOBP: u8 = 111;
const OPCODE_BCURRENT_BUFFER: u8 = 112;
const OPCODE_BSET_BUFFER: u8 = 113;
const OPCODE_BSAVE_CURRENT_BUFFER: u8 = 114;
const OPCODE_BFORWARD_CHAR: u8 = 117;
const OPCODE_BFORWARD_WORD: u8 = 118;
const OPCODE_BSKIP_CHARS_FORWARD: u8 = 119;
const OPCODE_BSKIP_CHARS_BACKWARD: u8 = 120;
const OPCODE_BFORWARD_LINE: u8 = 121;
const OPCODE_BCHAR_SYNTAX: u8 = 122;
const OPCODE_BBUFFER_SUBSTRING: u8 = 123;
const OPCODE_BDELETE_REGION: u8 = 124;
const OPCODE_BNARROW_TO_REGION: u8 = 125;
const OPCODE_BWIDEN: u8 = 126;
const OPCODE_BEND_OF_LINE: u8 = 127;
const OPCODE_BSAVE_EXCURSION: u8 = 138;
const OPCODE_BSAVE_RESTRICTION: u8 = 140;
const OPCODE_BUNWIND_PROTECT: u8 = 142;
const OPCODE_BSET_MARKER: u8 = 147;
const OPCODE_BMATCH_BEGINNING: u8 = 148;
const OPCODE_BMATCH_END: u8 = 149;
const OPCODE_BUPCASE: u8 = 150;
const OPCODE_BDOWNCASE: u8 = 151;
const OPCODE_BSTRINGEQLSIGN: u8 = 152;
const OPCODE_BSTRINGLSS: u8 = 153;
const OPCODE_BNTHCDR: u8 = 155;
const OPCODE_BELT: u8 = 156;
const OPCODE_BMEMBER: u8 = 157;
const OPCODE_BASSQ: u8 = 158;
const OPCODE_BNREVERSE: u8 = 159;
const OPCODE_BSETCAR: u8 = 160;
const OPCODE_BSETCDR: u8 = 161;
const OPCODE_BCAR_SAFE: u8 = 162;
const OPCODE_BCDR_SAFE: u8 = 163;
const OPCODE_BNCONC: u8 = 164;
const OPCODE_BQUO: u8 = 165;
const OPCODE_BREM: u8 = 166;
const OPCODE_BCONCATN: u8 = 176; // arg = FETCH
const OPCODE_BINSERTN: u8 = 177; // arg = FETCH
const OPCODE_BDISCARDN: u8 = 182; // arg = FETCH (0x80 bit = preserve-TOS)

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    // Seed the Io instance with the parent environment.  WITHOUT it, the
    // Threaded environ snapshot is empty and `environ_initialized` is set
    // true, so scanEnviron() never runs and the argv[0]="zig" PATH lookup
    // in spawnPosix falls back to default_PATH (/usr/local/bin:/bin:/usr/bin)
    // — which misses Homebrew's /opt/homebrew/bin on macOS (Linux CI's
    // /usr/bin zig masked this) and every `zig cc` link fails FileNotFound.
    var io_threaded: std.Io.Threaded = .init(gpa, .{ .environ = minimal.environ });
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    // Inherit the parent environment for the `zig cc` child: std.process.run
    // passes an EMPTY env on POSIX when no map is given, so without this the
    // spawned `zig` cannot resolve its cache dir (AppDataDirUnavailable) nor
    // find `zig` on PATH.  Mirrors build-aux/env.zig's inherit() helper.
    var env_map = try std.process.Environ.createMap(minimal.environ, gpa);
    defer env_map.deinit();

    var arg_it = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer arg_it.deinit();
    _ = arg_it.next(); // argv[0]
    const zunit_path = arg_it.next() orelse return error.MissingZunitArg;
    const manifest_path = arg_it.next() orelse return error.MissingManifestArg;
    const out_zeln_path = arg_it.next() orelse return error.MissingOutputArg;

    // ---- FDO (profile-guided recompilation) options.  `--profile FILE`
    // recompiles the .zeln with per-fn hotness guidance (hot-first
    // layout + branch weights + hot/cold attributes) read from a
    // loader-written profile file (lines: `<fnname>\t<count>`).
    // `--final` drops the per-fn call counters entirely (the tuned
    // artifact: zero FDO overhead — the loader's last recompile round
    // passes it, and auto-collection stops for the unit).  The counters
    // are emitted by default (gated by @zeln_fdo_active, which stays 0
    // unless the loader flips it), so "load a .zeln" is always ready to
    // auto-collect; `--final` is the only way to strip them.
    var fdo_profile_path: ?[]const u8 = null;
    var fdo_final = false;
    while (arg_it.next()) |a| {
        if (std.mem.eql(u8, a, "--profile")) {
            fdo_profile_path = arg_it.next() orelse {
                std.debug.print("zeln-compile: --profile needs a file argument\n", .{});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, a, "--final")) {
            fdo_final = true;
        } else {
            std.debug.print("zeln-compile: unknown option {s}\n", .{a});
            std.process.exit(1);
        }
    }

    // Parse the FDO profile (if any): map fn symbol name -> (calls,
    // fallbacks).  Calls mark hot fns (count > 0) and reorder the fn
    // table hot-first; FALLBACKS are the REAL count of times this fn's
    // M3 inline fast-path branches took the freloc fallback (bignum/
    // float/non-fixnum), collected by the same gated counter as the
    // calls.  The recompile's !prof branch weights are derived from the
    // two numbers (inline weight = calls - fallbacks, fallback weight =
    // fallbacks), so an overflow-heavy fn whose fallback path is
    // genuinely hot gets weights that let LLVM lay the fallback as
    // fall-through — the fix for the previous hardcoded 1000000:1
    // weights being wrong on such workloads.  Format:
    //   <fnname>\t<calls>[ \t<fallbacks>]
    // (fallbacks omitted => 0, backward compatible).  Keys are OWNED
    // copies (the profile buffer is freed below; dangling keys would
    // silently miss every lookup and leave every fn cold).
    var fdo_counts = std.StringHashMap(u64).init(gpa);
    var fdo_fallbacks = std.StringHashMap(u64).init(gpa);
    defer {
        {
            var it = fdo_counts.keyIterator();
            while (it.next()) |k| gpa.free(k.*);
            fdo_counts.deinit();
        }
        fdo_fallbacks.deinit();
    }
    if (fdo_profile_path) |pp| {
        const data = cwd.readFileAlloc(io, pp, gpa, .limited(16 * 1024 * 1024)) catch |err| {
            std.debug.print("zeln-compile: cannot read profile {s}: {s}\n", .{ pp, @errorName(err) });
            std.process.exit(1);
        };
        defer gpa.free(data);
        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            var fields = std.mem.splitScalar(u8, trimmed, '\t');
            const name = fields.next() orelse continue;
            const count_str = fields.next() orelse continue;
            const count = std.fmt.parseInt(u64, std.mem.trim(u8, count_str, " \t\r"), 10) catch continue;
            var fb: u64 = 0;
            if (fields.next()) |fb_str| {
                const t = std.mem.trim(u8, fb_str, " \t\r");
                if (t.len > 0) fb = std.fmt.parseInt(u64, t, 10) catch 0;
            }
            const owned = try gpa.dupe(u8, name);
            try fdo_counts.put(owned, count);
            try fdo_fallbacks.put(owned, fb);
        }
        std.debug.print("zeln-compile: FDO profile {s}: {d} fns\n", .{ pp, fdo_counts.count() });
    }

    const zunit = try cwd.readFileAlloc(io, zunit_path, gpa, .limited(16 * 1024 * 1024));
    defer gpa.free(zunit);
    if (zunit.len < 5 or std.mem.readInt(u32, zunit[0..4], .little) != ZUNIT_MAGIC) {
        std.debug.print("zeln-compile: bad zunit magic (want 0x{X})\n", .{ZUNIT_MAGIC});
        std.process.exit(1);
    }
    const zabi = zunit[4];

    const manifest = try cwd.readFileAlloc(io, manifest_path, gpa, .limited(4096));
    defer gpa.free(manifest);
    const abi_hash = parseManifestHash(manifest) orelse {
        std.debug.print("zeln-compile: bad manifest (no hash line)\n", .{});
        std.process.exit(1);
    };
    // Checked mirror: fail if the Zig-side FRELOC_NAMES / SURFACE drift from
    // the manifest's ordered freloc signature (compz.c zeln_imports[]).
    verifyFrelocSurface(manifest) catch |err| {
        std.debug.print("zeln-compile: freloc surface drift vs manifest: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    var ll_body: []u8 = undefined;
    if (zabi == 1) {
        // M0 spike path: fixed emitter, constants parsed from the zabi=1 zunit.
        const consts = parseSpikeZunit(zunit) catch |err| {
            std.debug.print("zeln-compile: spike zunit parse failed: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        defer gpa.free(consts);
        ll_body = try emitSpikeLLVM(gpa, consts, abi_hash);
    } else if (zabi == 2) {
        // M1 path: real bytecode-driven emitter.
        const unit = parseM1Zunit(gpa, zunit) catch |err| {
            std.debug.print("zeln-compile: M1 zunit parse failed: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        defer freeM1Unit(gpa, unit);
        ll_body = emitM1LLVM(gpa, unit, abi_hash, zunit, fdo_counts, fdo_fallbacks, fdo_final) catch |err| {
            std.debug.print("zeln-compile: M1 emit failed: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
    } else if (zabi == 3) {
        // M2b path: multi-function file zunit (N defuns + top_level_blob).
        const file_unit = parseFileZunit(gpa, zunit) catch |err| {
            std.debug.print("zeln-compile: file zunit parse failed: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        defer freeFileUnit(gpa, file_unit);
        ll_body = emitFileLLVM(gpa, file_unit.fns, abi_hash, file_unit.top_blob, zunit, fdo_counts, fdo_fallbacks, fdo_final) catch |err| {
            std.debug.print("zeln-compile: file emit failed: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
    } else {
        std.debug.print("zeln-compile: unsupported zabi_version {d} (want 1, 2, or 3)\n", .{zabi});
        std.process.exit(1);
    }
    defer gpa.free(ll_body);

    // Emit the .ll next to the output .zeln (sibling file).
    const ll_path = try std.fmt.allocPrint(gpa, "{s}.ll", .{out_zeln_path});
    defer gpa.free(ll_path);
    try cwd.writeFile(io, .{ .sub_path = ll_path, .data = ll_body });

    // Drive the link: `zig cc -shared -fPIC -O2 -fvisibility=default
    // <fn>.ll -o <name>.zeln`. -fvisibility=default ensures `zeln_entry`
    // is exported in the .so's dynamic symbol table so the loader's dlsym
    // finds it.  The link driver is identical for the M0 spike and M1.
    // Spawn `zig cc` with an EXPLICIT zig executable path when the caller
    // provides one.  argv[0] resolution for a bare "zig" uses the PARENT
    // environment's PATH (std.process.ReplaceOptions: "resolved ... based on
    // every zeln-compile invocation, so the child never needs PATH lookup.
    const zig_cc = env_map.get("ZELN_ZIG_CC");

    const cc_argv = [_][]const u8{
        if (zig_cc) |z| z else "zig",
        "cc",       "-shared",  "-fPIC",
        "-O2",      "-fvisibility=default", ll_path, "-o",
        out_zeln_path,
    };
    const res = std.process.run(gpa, io, .{
        .argv = &cc_argv,
        .environ_map = &env_map,
        .stdout_limit = .unlimited,
        .stderr_limit = .unlimited,
    }) catch |err| {
        std.debug.print("zeln-compile: zig cc spawn failed: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    if (res.term != .exited or res.term.exited != 0) {
        std.debug.print("zeln-compile: zig cc failed\n--- stdout ---\n{s}\n--- stderr ---\n{s}\n", .{ res.stdout, res.stderr });
        std.process.exit(1);
    }
}

// =====================================================================
// Manifest parsing (shared by both zabi versions).  The manifest is
// `<ZELN_ABI_VERSION>\n<sig>\n<8-hex>\n`.  Only the 8-hex hash (line 3)
// is consumed — baked verbatim into the .zeln as freloc_hash_z; the
// loader compares it against Vzeln_abi_hash.  Single source of truth:
// compz.c computes; Zig only embeds.
// =====================================================================
fn parseManifestHash(manifest: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, manifest, '\n');
    _ = it.next(); // ZELN_ABI_VERSION
    _ = it.next(); // sig
    const hash_line = it.next() orelse return null;
    if (hash_line.len < 8) return null;
    return hash_line[0..8];
}

// Verify the Zig-side FRELOC_NAMES mirror against the ordered signature the
// manifest carries (compz.c zeln_signature_string: `name++arity` concatenated,
// arity = `(N . many)` or a single digit).  Using the known name at each step
// makes the parse deterministic (no name/arity ambiguity).  Any count or
// positional-name mismatch fails the compile: the hand-mirror is CHECKED on
// every run, so a Zig-side insert/reorder/rename that skips compz.c cannot
// silently produce misaligned freloc calls behind a passing ABI hash.
fn verifyFrelocSurface(manifest: []const u8) !void {
    var it = std.mem.splitScalar(u8, manifest, '\n');
    _ = it.next(); // ZELN_ABI_VERSION
    const sig = it.next() orelse return error.MissingSignature;
    var pos: usize = 0;
    for (FRELOC_NAMES) |name| {
        if (pos + name.len > sig.len or !std.mem.eql(u8, sig[pos .. pos + name.len], name))
            return error.FrelocNameDrift;
        pos += name.len;
        // Arity: `(N . many)` (consume to ')') or a single digit 0-3.
        if (pos >= sig.len)
            return error.FrelocArityMissing;
        if (sig[pos] == '(') {
            const close = std.mem.indexOfScalarPos(u8, sig, pos + 1, ')') orelse
                return error.FrelocArityMissing;
            pos = close + 1;
        } else {
            pos += 1;
        }
    }
    if (pos != sig.len)
        return error.FrelocTrailingJunk;
}

// =====================================================================
// M0 spike path (zabi=1).  The spike zunit format (unchanged from M0):
//   u32 magic; u8 zabi=1; u8 arity_min; u8 arity_max; u8 stack_depth;
//   u16 opcode_len; u8 opcodes[opcode_len]; u8 nconsts;
//   nconsts × { u8 tag; u32 len; u8 data[len] }.
// Opcodes are validated present (format parity) but NOT translated — the
// fixed emitter ignores them.  Returns the slice of const read-syntax
// payloads (the loader Freads them into d_reloc_z).
// =====================================================================
const Const = struct {
    tag: u8,
    data: []const u8,
};

fn parseSpikeZunit(zunit: []const u8) ![]Const {
    if (zunit.len < 10) return error.ZunitTooShort;
    // header[5..8] = arity_min, arity_max, stack_depth (doc-only at M0).
    var off: usize = 8;
    const opcode_len = std.mem.readInt(u16, zunit[off..][0..2], .little);
    off += 2;
    if (off + opcode_len + 1 > zunit.len) return error.OpcodeOverflow;
    off += opcode_len; // skip opcodes (Tier-0 ignores)
    const nconsts = zunit[off];
    off += 1;

    const consts = try gpaAlloc(Const, nconsts);
    for (0..nconsts) |i| {
        if (off + 5 > zunit.len) return error.ConstHeaderOverflow;
        const tag = zunit[off];
        off += 1;
        const len = std.mem.readInt(u32, zunit[off..][0..4], .little);
        off += 4;
        if (off + len > zunit.len) return error.ConstDataOverflow;
        consts[i] = .{ .tag = tag, .data = zunit[off .. off + len] };
        off += len;
    }
    return consts;
}

// Emit the fixed Tier-0 .ll for the spike fn (M0 regression).  M1 moved
// native_fn to the MANY convention and replaced freloc[0]=&Fmessage with
// the fixed M1 surface, so the spike now exercises the freloc indirection
// via IDX_NILP on d_reloc_z[0] (the string -> 0, discarded) and returns
// d_reloc_z[1] (42).  The zunit->.ll->.zeln->freloc-indirection->ABI-gate
// chain is still proven; the message side-effect was dropped because
// Fmessage is no longer in the surface (M1 routes calls through IDX_FUNCALL).
fn emitSpikeLLVM(gpa: std.mem.Allocator, consts: []Const, abi_hash: []const u8) ![]u8 {
    var blob: std.ArrayList(u8) = .empty;
    defer blob.deinit(gpa);
    try blob.append(gpa, '[');
    for (consts, 0..) |c, i| {
        if (i > 0) try blob.append(gpa, ' ');
        try blob.appendSlice(gpa, c.data);
    }
    try blob.append(gpa, ']');
    const blob_bytes = blob.items;

    var blob_lit: std.ArrayList(u8) = .empty;
    defer blob_lit.deinit(gpa);
    try appendCStringLiteral(gpa, &blob_lit, blob_bytes);

    var hash_lit: std.ArrayList(u8) = .empty;
    defer hash_lit.deinit(gpa);
    try appendCStringLiteral(gpa, &hash_lit, abi_hash);
    try hash_lit.appendSlice(gpa, "\\00");

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    const A = struct {
        fn add(o: *std.ArrayList(u8), a: std.mem.Allocator, s: []const u8) !void {
            try o.appendSlice(a, s);
        }
        fn addf(o: *std.ArrayList(u8), a: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
            const s = try std.fmt.allocPrint(a, fmt, args);
            defer a.free(s);
            try o.appendSlice(a, s);
        }
    };

    try A.add(&out, gpa,
        \\; zeln-spike.ll — Tier-0 emission of the M0 spike fn (plan §6).
        \\; Generated by tools/zeln-compile. The entry struct mirrors
        \\; src/compz.h zeln_entry_t field-for-field.
        \\
        \\@freloc_link_table_z = internal global ptr null
        \\
    );
    try A.addf(&out, gpa, "@d_reloc_z = internal global [2 x i64] zeroinitializer\n\n", .{});
    try A.addf(&out, gpa, "@d_reloc_z_blob = internal constant {{ i64, [{d} x i8] }} {{ i64 {d}, [{d} x i8] c\"{s}\" }}\n\n", .{ blob_bytes.len, blob_bytes.len, blob_bytes.len, blob_lit.items });
    try A.addf(&out, gpa, "@freloc_hash_z_data = internal constant [9 x i8] c\"{s}\"\n\n", .{hash_lit.items});
    try A.add(&out, gpa,
        \\@sym_name_0 = internal constant [11 x i8] c"zeln-spike\00"
        \\@zeln_fn_table = private constant [1 x { ptr, i64, ptr, ptr, i64, ptr }] [
        \\  { ptr, i64, ptr, ptr, i64, ptr } { ptr @zeln_spike_native, i64 0, ptr @sym_name_0, ptr @d_reloc_z, i64 2, ptr @d_reloc_z_blob }
        \\]
        \\@top_level_blob_data = internal constant { i64, [0 x i8] } { i64 0, [0 x i8] c"" }
        \\@zeln_entry_global = internal global { ptr, ptr, i64, ptr, ptr } {
        \\  ptr @freloc_link_table_z,
        \\  ptr @freloc_hash_z_data,
        \\  i64 1,
        \\  ptr @zeln_fn_table,
        \\  ptr @top_level_blob_data
        \\}
        \\
        \\; Spike native body (MANY convention).  INTERNAL linkage so it does
        \\; not interpose across multiple concurrently loaded .zeln (dynlib_open
        \\; uses RTLD_GLOBAL).  Only @zeln_entry is exported.
        \\define internal i64 @zeln_spike_native(i64 %nargs, ptr %args) {
        \\entry:
        \\  %lt = load ptr, ptr @freloc_link_table_z
        \\  %slot = getelementptr inbounds [SURFACE x ptr], ptr %lt, i64 0, i64 2
        \\  %fn = load ptr, ptr %slot
        \\  %nilret = call i64 %fn(i64 1, ptr @d_reloc_z)
        \\  %rv = load i64, ptr getelementptr inbounds ([2 x i64], ptr @d_reloc_z, i64 0, i64 1)
        \\  ret i64 %rv
        \\}
        \\
        \\define dso_local ptr @zeln_entry() {
        \\entry:
        \\  ret ptr @zeln_entry_global
        \\}
        \\
    );
    // Substitute the SURFACE placeholder (kept literal above so the raw
    // multiline string stays readable; the surface grows with the IDX enum).
    const surface_type = try std.fmt.allocPrint(gpa, "[{d} x ptr]", .{SURFACE});
    defer gpa.free(surface_type);
    var tmp = try out.toOwnedSlice(gpa);
    tmp = try std.mem.replaceOwned(u8, gpa, tmp, "[SURFACE x ptr]", surface_type);
    try out.appendSlice(gpa, tmp);
    gpa.free(tmp);
    return out.toOwnedSlice(gpa);
}

// =====================================================================
// M1 path (zabi=2).  Parse the M1 zunit, then drive the real emitter.
// =====================================================================
const M1Unit = struct {
    args_template: u32,
    stack_depth: u32,
    opcodes: []const u8,
    consts: [][]const u8, // read-syntax bytes per constant
};

fn parseM1Zunit(gpa: std.mem.Allocator, zunit: []const u8) !M1Unit {
    // u32 magic; u8 zabi=2; u32 args_template; u16 stack_depth;
    // u32 opcode_len; u8 opcodes[]; u32 nconsts; per-const {u8 tag;u32 len;u8 data[len]}.
    if (zunit.len < 5 + 4 + 2 + 4) return error.ZunitTooShort;
    var off: usize = 5; // past magic+zabi
    const args_template = std.mem.readInt(u32, zunit[off..][0..4], .little);
    off += 4;
    const stack_depth = std.mem.readInt(u16, zunit[off..][0..2], .little);
    off += 2;
    const opcode_len = std.mem.readInt(u32, zunit[off..][0..4], .little);
    off += 4;
    if (off + opcode_len + 4 > zunit.len) return error.OpcodeOverflow;
    const opcodes = zunit[off .. off + opcode_len];
    off += opcode_len;
    const nconsts = std.mem.readInt(u32, zunit[off..][0..4], .little);
    off += 4;

    const consts = try gpa.alloc([]const u8, @intCast(nconsts));
    for (0..nconsts) |i| {
        if (off + 5 > zunit.len) return error.ConstHeaderOverflow;
        off += 1; // tag_advisory (loader ignores; read-syntax is truth)
        const len = std.mem.readInt(u32, zunit[off..][0..4], .little);
        off += 4;
        if (off + len > zunit.len) return error.ConstDataOverflow;
        consts[i] = zunit[off .. off + len];
        off += len;
    }
    return .{
        .args_template = args_template,
        .stack_depth = stack_depth,
        .opcodes = opcodes,
        .consts = consts,
    };
}

fn freeM1Unit(gpa: std.mem.Allocator, u: M1Unit) void {
    gpa.free(u.consts);
}

// =====================================================================
// M2b multi-function zunit (zabi=3).  N function blocks (one per defun)
// + one top_level_blob.  Each block carries the defun symbol name + the
// SAME closure-body shape as zabi=2 (args_template, stack_depth, opcodes,
// consts).  Parsed into a []FnUnit (names owned by this function's
// arena-allocated slices, pointing into the zunit buffer) + the raw
// top_blob bytes (also aliased into the zunit buffer).
// =====================================================================
const FileUnit = struct {
    fns: []FnUnit,
    top_blob: []const u8,
};

fn parseFileZunit(gpa: std.mem.Allocator, zunit: []const u8) !FileUnit {
    // u32 magic; u8 zabi=3; u32 nfuncs; then nfuncs × { u32 sym_name_len;
    //   u8 sym_name[len]; <closure body>; ... }; u32 top_blob_len; u8[].
    if (zunit.len < 5 + 4) return error.ZunitTooShort;
    var off: usize = 5; // past magic+zabi
    const nfuncs = std.mem.readInt(u32, zunit[off..][0..4], .little);
    off += 4;
    if (nfuncs == 0) return error.EmptyBytecode;

    var fns = try gpa.alloc(FnUnit, nfuncs);
    errdefer gpa.free(fns);
    var fn_i: usize = 0;
    while (fn_i < nfuncs) : (fn_i += 1) {
        if (off + 4 > zunit.len) return error.NameLenOverflow;
        const namelen = std.mem.readInt(u32, zunit[off..][0..4], .little);
        off += 4;
        if (off + namelen > zunit.len) return error.NameOverflow;
        const name = zunit[off .. off + namelen];
        off += namelen;

        // closure body: u32 args_template; u16 stack_depth; u32 opcode_len;
        //   u8 opcodes[]; u32 nconsts; consts.
        if (off + 4 + 2 + 4 > zunit.len) return error.ZunitTooShort;
        const args_template = std.mem.readInt(u32, zunit[off..][0..4], .little);
        off += 4;
        const stack_depth = std.mem.readInt(u16, zunit[off..][0..2], .little);
        off += 2;
        const opcode_len = std.mem.readInt(u32, zunit[off..][0..4], .little);
        off += 4;
        if (off + opcode_len + 4 > zunit.len) return error.OpcodeOverflow;
        const opcodes = zunit[off .. off + opcode_len];
        off += opcode_len;
        const nconsts = std.mem.readInt(u32, zunit[off..][0..4], .little);
        off += 4;

        const consts = try gpa.alloc([]const u8, @intCast(nconsts));
        for (0..nconsts) |i| {
            if (off + 5 > zunit.len) return error.ConstHeaderOverflow;
            off += 1; // tag_advisory (loader ignores)
            const len = std.mem.readInt(u32, zunit[off..][0..4], .little);
            off += 4;
            if (off + len > zunit.len) return error.ConstDataOverflow;
            consts[i] = zunit[off .. off + len];
            off += len;
        }
        fns[fn_i] = .{
            .name = name,
            .args_template = args_template,
            .stack_depth = stack_depth,
            .opcodes = opcodes,
            .consts = consts,
        };
    }

    if (off + 4 > zunit.len) return error.ZunitTooShort;
    const top_blob_len = std.mem.readInt(u32, zunit[off..][0..4], .little);
    off += 4;
    if (off + top_blob_len > zunit.len) return error.BlobOverflow;
    const top_blob = zunit[off .. off + top_blob_len];
    return .{ .fns = fns, .top_blob = top_blob };
}

fn freeFileUnit(gpa: std.mem.Allocator, u: FileUnit) void {
    for (u.fns) |f| gpa.free(f.consts);
    gpa.free(u.fns);
}

// ---- Decode (interpreter FETCH/FETCH2 semantics; bytecode.c:278) ----

const Op = enum {
    constant, // imm = const idx
    stack_ref, // imm = depth
    dup,
    discard,
    stack_set, // imm = depth: ptr=top[-depth]; *ptr = POP
    ret,
    goto_, // imm = target
    goto_if_nil, // imm = target (POP first)
    goto_if_nonnil, // imm = target (POP first)
    goto_if_nil_else_pop, // imm = target (no pop; pop only on fallthrough)
    goto_if_nonnil_else_pop, // imm = target
    call, // imm = nargs
    unary, // imm = IDX (operate on TOP, replace in place)
    binary, // imm = IDX (POP v2, TOP=v1, call(2, &newtop))
    listn, // imm = n (DISCARD n-1, Flist(n, &newtop))
    // ---- M2 ----
    varref, // idx = const idx (PUSH Fsymbol_value(const))
    varset, // idx = const idx (set_internal(const, POP))
    varbind, // idx = const idx (specbind(const, POP))
    unbind, // imm = count (unbind_to(SPECPDL_INDEX()-count))
    discard_n, // imm = byte (0x80 set => preserve TOS first; pure stack op)
    push0, // idx = IDX (PUSH fn()) — 0-arg primitive
    noarg, // idx = IDX (call fn(0), discard) — save_*/pophandler
    pushhandler, // idx = type (0=CATCHER,1=CONDITION_CASE); target = handler-body off
    unary_pop, // idx = IDX (POP one, call fn(1,&oldtop), discard) — Bunwind_protect
};

const Instr = struct {
    op: Op,
    start: u32, // starting byte offset (block-label key)
    idx: u64 = 0, // for constant (const idx) or freloc IDX (unary/binary)
    imm: u32 = 0, // depth / nargs / n / list-n
    target: u32 = 0, // branch absolute byte offset
    end: u32, // offset after this instruction
};

fn decode(opcodes: []const u8, pc0: u32) !Instr {
    const b = opcodes[pc0];
    var pc = pc0 + 1;
    var ins = Instr{ .op = .ret, .start = pc0, .end = pc };
    if (b >= OPCODE_BCONSTANT_BASE) {
        ins.op = .constant;
        ins.idx = @as(u64, b - OPCODE_BCONSTANT_BASE);
        ins.end = pc;
        return ins;
    }
    switch (b) {
        OPCODE_BSTACK_REF1...OPCODE_BSTACK_REF5 => {
            ins.op = .stack_ref;
            ins.imm = b; // depth = op (top[-op])
            ins.end = pc;
        },
        OPCODE_BSTACK_REF6 => {
            ins.op = .stack_ref;
            ins.imm = fetch1(opcodes, &pc);
        },
        OPCODE_BSTACK_REF7 => {
            ins.op = .stack_ref;
            ins.imm = fetch2(opcodes, &pc);
        },
        OPCODE_BCONSTANT2 => {
            // Bconstant2: PUSH vectorp[FETCH2] (constant index >= 64).
            ins.op = .constant;
            ins.idx = fetch2(opcodes, &pc);
        },
        OPCODE_BDUP => ins.op = .dup,
        OPCODE_BDISCARD => ins.op = .discard,
        OPCODE_BSTACK_SET => {
            ins.op = .stack_set;
            ins.imm = fetch1(opcodes, &pc);
        },
        OPCODE_BSTACK_SET2 => {
            ins.op = .stack_set;
            ins.imm = fetch2(opcodes, &pc);
        },
        OPCODE_BRETURN => ins.op = .ret,
        OPCODE_BGOTO => {
            ins.op = .goto_;
            ins.target = fetch2(opcodes, &pc);
        },
        OPCODE_BGOTOIFNIL => {
            ins.op = .goto_if_nil;
            ins.target = fetch2(opcodes, &pc);
        },
        OPCODE_BGOTOIFNONNIL => {
            ins.op = .goto_if_nonnil;
            ins.target = fetch2(opcodes, &pc);
        },
        OPCODE_BGOTOIFNILELSEPOP => {
            ins.op = .goto_if_nil_else_pop;
            ins.target = fetch2(opcodes, &pc);
        },
        OPCODE_BGOTOIFNONNILELSEPOP => {
            ins.op = .goto_if_nonnil_else_pop;
            ins.target = fetch2(opcodes, &pc);
        },
        OPCODE_BCALL...OPCODE_BCALL5 => {
            ins.op = .call;
            ins.imm = b - OPCODE_BCALL; // 0..5
        },
        OPCODE_BCALL6 => {
            ins.op = .call;
            ins.imm = fetch1(opcodes, &pc);
        },
        OPCODE_BCALL7 => {
            ins.op = .call;
            ins.imm = fetch2(opcodes, &pc);
        },
        OPCODE_BSUB1 => {
            ins.op = .unary;
            ins.idx = IDX_SUB1;
        },
        OPCODE_BADD1 => {
            ins.op = .unary;
            ins.idx = IDX_ADD1;
        },
        OPCODE_BNEGATE => {
            ins.op = .unary;
            ins.idx = IDX_NEGATE;
        },
        OPCODE_BCAR => {
            ins.op = .unary;
            ins.idx = IDX_CAR;
        },
        OPCODE_BCDR => {
            ins.op = .unary;
            ins.idx = IDX_CDR;
        },
        OPCODE_BNOT => {
            ins.op = .unary;
            ins.idx = IDX_NULL;
        },
        OPCODE_BSYMBOLP => {
            ins.op = .unary;
            ins.idx = IDX_SYMBOLP;
        },
        OPCODE_BCONSP => {
            ins.op = .unary;
            ins.idx = IDX_CONSP;
        },
        OPCODE_BSTRINGP => {
            ins.op = .unary;
            ins.idx = IDX_STRINGP;
        },
        OPCODE_BLISTP => {
            ins.op = .unary;
            ins.idx = IDX_LISTP;
        },
        OPCODE_BNUMBERP => {
            ins.op = .unary;
            ins.idx = IDX_NUMBERP;
        },
        OPCODE_BINTEGERP => {
            ins.op = .unary;
            ins.idx = IDX_INTEGERP;
        },
        OPCODE_BLIST1 => {
            ins.op = .unary;
            ins.idx = IDX_LIST1;
        },
        OPCODE_BPLUS => {
            ins.op = .binary;
            ins.idx = IDX_PLUS;
        },
        OPCODE_BDIFF => {
            ins.op = .binary;
            ins.idx = IDX_MINUS;
        },
        OPCODE_BMULT => {
            ins.op = .binary;
            ins.idx = IDX_TIMES;
        },
        OPCODE_BMAX => {
            ins.op = .binary;
            ins.idx = IDX_MAX;
        },
        OPCODE_BMIN => {
            ins.op = .binary;
            ins.idx = IDX_MIN;
        },
        OPCODE_BEQLSIGN => {
            ins.op = .binary;
            ins.idx = IDX_EQLSIGN;
        },
        OPCODE_BGTR => {
            ins.op = .binary;
            ins.idx = IDX_GTR;
        },
        OPCODE_BLSS => {
            ins.op = .binary;
            ins.idx = IDX_LSS;
        },
        OPCODE_BLEQ => {
            ins.op = .binary;
            ins.idx = IDX_LEQ;
        },
        OPCODE_BGEQ => {
            ins.op = .binary;
            ins.idx = IDX_GEQ;
        },
        OPCODE_BEQUAL => {
            ins.op = .binary;
            ins.idx = IDX_EQUAL;
        },
        OPCODE_BEQ => {
            ins.op = .binary;
            ins.idx = IDX_EQ;
        },
        OPCODE_BCONS => {
            ins.op = .binary;
            ins.idx = IDX_CONS;
        },
        OPCODE_BLIST2 => {
            ins.op = .binary;
            ins.idx = IDX_LIST2;
        },
        OPCODE_BLIST3 => {
            // DISCARD 2; list3(TOP, top[1], top[2]) -> a 3-ary "binary"-style op.
            ins.op = .listn;
            ins.imm = 3;
            ins.idx = IDX_LIST3;
        },
        OPCODE_BLIST4 => {
            ins.op = .listn;
            ins.imm = 4;
            ins.idx = IDX_LIST4;
        },
        OPCODE_BLISTN => {
            ins.op = .listn;
            ins.imm = fetch1(opcodes, &pc);
            ins.idx = IDX_LIST;
        },
        // ---- M2: varref / varset / varbind / unbind families ----
        OPCODE_BVARREF...OPCODE_BVARREF5 => {
            ins.op = .varref;
            ins.idx = @as(u64, b - OPCODE_BVARREF);
        },
        OPCODE_BVARREF6 => {
            ins.op = .varref;
            ins.idx = fetch1(opcodes, &pc);
        },
        OPCODE_BVARREF7 => {
            ins.op = .varref;
            ins.idx = fetch2(opcodes, &pc);
        },
        OPCODE_BVARSET...OPCODE_BVARSET5 => {
            ins.op = .varset;
            ins.idx = @as(u64, b - OPCODE_BVARSET);
        },
        OPCODE_BVARSET6 => {
            ins.op = .varset;
            ins.idx = fetch1(opcodes, &pc);
        },
        OPCODE_BVARSET7 => {
            ins.op = .varset;
            ins.idx = fetch2(opcodes, &pc);
        },
        OPCODE_BVARBIND...OPCODE_BVARBIND5 => {
            ins.op = .varbind;
            ins.idx = @as(u64, b - OPCODE_BVARBIND);
        },
        OPCODE_BVARBIND6 => {
            ins.op = .varbind;
            ins.idx = fetch1(opcodes, &pc);
        },
        OPCODE_BVARBIND7 => {
            ins.op = .varbind;
            ins.idx = fetch2(opcodes, &pc);
        },
        OPCODE_BUNBIND...OPCODE_BUNBIND5 => {
            ins.op = .unbind;
            ins.imm = b - OPCODE_BUNBIND;
        },
        OPCODE_BUNBIND6 => {
            ins.op = .unbind;
            ins.imm = fetch1(opcodes, &pc);
        },
        OPCODE_BUNBIND7 => {
            ins.op = .unbind;
            ins.imm = fetch2(opcodes, &pc);
        },
        OPCODE_BDISCARDN => {
            ins.op = .discard_n;
            ins.imm = fetch1(opcodes, &pc);
        },
        // ---- handler trio (Tier 2) ----
        OPCODE_BPUSHCATCH => {
            ins.op = .pushhandler;
            ins.idx = 0; // CATCHER
            ins.target = fetch2(opcodes, &pc);
        },
        OPCODE_BPUSHCONDITIONCASE => {
            ins.op = .pushhandler;
            ins.idx = 1; // CONDITION_CASE
            ins.target = fetch2(opcodes, &pc);
        },
        OPCODE_BPOPHANDLER => {
            ins.op = .noarg;
            ins.idx = IDX_POPHANDLER;
        },
        // ---- list / seq primitives (binary: POP v2; fn(a[0],a[1])) ----
        OPCODE_BNTH => binaryOp(&ins, IDX_NTH),
        OPCODE_BELT => binaryOp(&ins, IDX_ELT),
        OPCODE_BMEMQ => binaryOp(&ins, IDX_MEMQ),
        OPCODE_BMEMBER => binaryOp(&ins, IDX_MEMBER),
        OPCODE_BASSQ => binaryOp(&ins, IDX_ASSQ),
        OPCODE_BSET => binaryOp(&ins, IDX_SET),
        OPCODE_BFSET => binaryOp(&ins, IDX_FSET),
        OPCODE_BGET => binaryOp(&ins, IDX_GET),
        OPCODE_BAREF => binaryOp(&ins, IDX_AREF),
        OPCODE_BSTRINGEQLSIGN => binaryOp(&ins, IDX_STRING_EQUAL),
        OPCODE_BSTRINGLSS => binaryOp(&ins, IDX_STRING_LESSP),
        OPCODE_BNTHCDR => binaryOp(&ins, IDX_NTHCDR),
        OPCODE_BSETCAR => binaryOp(&ins, IDX_SETCAR),
        OPCODE_BSETCDR => binaryOp(&ins, IDX_SETCDR),
        OPCODE_BQUO => binaryOp(&ins, IDX_QUO),
        OPCODE_BREM => binaryOp(&ins, IDX_REM),
        OPCODE_BSKIP_CHARS_FORWARD => binaryOp(&ins, IDX_SKIP_CHARS_FORWARD),
        OPCODE_BSKIP_CHARS_BACKWARD => binaryOp(&ins, IDX_SKIP_CHARS_BACKWARD),
        OPCODE_BBUFFER_SUBSTRING => binaryOp(&ins, IDX_BUFFER_SUBSTRING),
        OPCODE_BDELETE_REGION => binaryOp(&ins, IDX_DELETE_REGION),
        OPCODE_BNARROW_TO_REGION => binaryOp(&ins, IDX_NARROW_TO_REGION),
        // ---- unary-on-TOP (TOP = fn(a[0]); net 0) ----
        OPCODE_BLENGTH => unaryOp(&ins, IDX_LENGTH),
        OPCODE_BSYMBOL_VALUE => unaryOp(&ins, IDX_SYMBOL_VALUE),
        OPCODE_BSYMBOL_FUNCTION => unaryOp(&ins, IDX_SYMBOL_FUNCTION),
        OPCODE_BGOTO_CHAR => unaryOp(&ins, IDX_GOTO_CHAR),
        OPCODE_BINSERT => unaryOp(&ins, IDX_INSERT),
        OPCODE_BCHAR_AFTER => unaryOp(&ins, IDX_CHAR_AFTER),
        OPCODE_BINDENT_TO => unaryOp(&ins, IDX_INDENT_TO),
        OPCODE_BSET_BUFFER => unaryOp(&ins, IDX_SET_BUFFER),
        OPCODE_BFORWARD_CHAR => unaryOp(&ins, IDX_FORWARD_CHAR),
        OPCODE_BFORWARD_WORD => unaryOp(&ins, IDX_FORWARD_WORD),
        OPCODE_BFORWARD_LINE => unaryOp(&ins, IDX_FORWARD_LINE),
        OPCODE_BCHAR_SYNTAX => unaryOp(&ins, IDX_CHAR_SYNTAX),
        OPCODE_BEND_OF_LINE => unaryOp(&ins, IDX_END_OF_LINE),
        OPCODE_BMATCH_BEGINNING => unaryOp(&ins, IDX_MATCH_BEGINNING),
        OPCODE_BMATCH_END => unaryOp(&ins, IDX_MATCH_END),
        OPCODE_BUPCASE => unaryOp(&ins, IDX_UPCASE),
        OPCODE_BDOWNCASE => unaryOp(&ins, IDX_DOWNCASE),
        OPCODE_BNREVERSE => unaryOp(&ins, IDX_NREVERSE),
        OPCODE_BCAR_SAFE => unaryOp(&ins, IDX_CAR_SAFE),
        OPCODE_BCDR_SAFE => unaryOp(&ins, IDX_CDR_SAFE),
        // ---- 0-arg PUSH (PUSH fn()) ----
        OPCODE_BPOINT => push0Op(&ins, IDX_POINT),
        OPCODE_BPOINT_MAX => push0Op(&ins, IDX_POINT_MAX),
        OPCODE_BPOINT_MIN => push0Op(&ins, IDX_POINT_MIN),
        OPCODE_BFOLLOWING_CHAR => push0Op(&ins, IDX_FOLLOWING_CHAR),
        OPCODE_BPRECEDING_CHAR => push0Op(&ins, IDX_PRECEDING_CHAR),
        OPCODE_BCURRENT_COLUMN => push0Op(&ins, IDX_CURRENT_COLUMN),
        OPCODE_BEOLP => push0Op(&ins, IDX_EOLP),
        OPCODE_BEOBP => push0Op(&ins, IDX_EOBP),
        OPCODE_BBOLP => push0Op(&ins, IDX_BOLP),
        OPCODE_BBOBP => push0Op(&ins, IDX_BOBP),
        OPCODE_BCURRENT_BUFFER => push0Op(&ins, IDX_CURRENT_BUFFER),
        OPCODE_BWIDEN => push0Op(&ins, IDX_WIDEN),
        // ---- no-arg, no-stack-effect (specpdl push / pophandler) ----
        OPCODE_BSAVE_EXCURSION => noargOp(&ins, IDX_SAVE_EXCURSION),
        OPCODE_BSAVE_CURRENT_BUFFER => noargOp(&ins, IDX_SAVE_CURRENT_BUFFER),
        OPCODE_BSAVE_RESTRICTION => noargOp(&ins, IDX_SAVE_RESTRICTION),
        OPCODE_BUNWIND_PROTECT => {
            ins.op = .unary_pop;
            ins.idx = IDX_UNWIND_PROTECT;
        },
        // ---- variadic / ternary (DISCARD n-1; fn(n, &newtop)) ----
        OPCODE_BASET => listnOp(&ins, IDX_ASET, 3),
        OPCODE_BSUBSTRING => listnOp(&ins, IDX_SUBSTRING, 3),
        OPCODE_BSET_MARKER => listnOp(&ins, IDX_SET_MARKER, 3),
        OPCODE_BCONCAT2 => listnOp(&ins, IDX_CONCAT, 2),
        OPCODE_BCONCAT3 => listnOp(&ins, IDX_CONCAT, 3),
        OPCODE_BCONCAT4 => listnOp(&ins, IDX_CONCAT, 4),
        OPCODE_BCONCATN => {
            ins.op = .listn;
            ins.imm = fetch1(opcodes, &pc);
            ins.idx = IDX_CONCAT;
        },
        OPCODE_BNCONC => listnOp(&ins, IDX_NCONC, 2),
        OPCODE_BINSERTN => {
            ins.op = .listn;
            ins.imm = fetch1(opcodes, &pc);
            ins.idx = IDX_INSERT;
        },
        else => {
            std.debug.print("zeln-compile: unsupported opcode 0x{X} at offset {d} (outside M1 subset)\n", .{ b, pc0 });
            return error.UnsupportedOpcode;
        },
    }
    ins.end = pc;
    return ins;
}

fn fetch1(opcodes: []const u8, pc: *u32) u32 {
    const v = @as(u32, opcodes[pc.*]);
    pc.* += 1;
    return v;
}

fn fetch2(opcodes: []const u8, pc: *u32) u32 {
    // FETCH2 = pc[-2] | pc[-1]<<8  (little-endian); pc has already advanced
    // past the opcode, and these are the two immediates after it.
    const lo = @as(u32, opcodes[pc.*]);
    const hi = @as(u32, opcodes[pc.* + 1]);
    pc.* += 2;
    return lo | (hi << 8);
}

// Tiny decode helpers: set the Instr's op + idx (and imm for listn) without
// touching pc/end (the caller's `ins.end = pc` after the switch still applies).
fn unaryOp(ins: *Instr, idx: u64) void {
    ins.op = .unary;
    ins.idx = idx;
}
fn binaryOp(ins: *Instr, idx: u64) void {
    ins.op = .binary;
    ins.idx = idx;
}
fn listnOp(ins: *Instr, idx: u64, n: u32) void {
    ins.op = .listn;
    ins.idx = idx;
    ins.imm = n;
}
fn push0Op(ins: *Instr, idx: u64) void {
    ins.op = .push0;
    ins.idx = idx;
}
fn noargOp(ins: *Instr, idx: u64) void {
    ins.op = .noarg;
    ins.idx = idx;
}

// =====================================================================
// The M1 Tier-0 emitter.
// =====================================================================
const Emitter = struct {
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    next_reg: u32 = 1, // LLVM temporaries start at %1 (params occupy %0-ish names; we use numeric %N)
    // Per-fn d_reloc global name + const count. Set by emitNativeFn before
    // emitting each fn's body, so loadConst / emitVarref reference THIS fn's
    // @d_reloc_z_<i> (each closure has its own constants vector).
    d_reloc_global: []const u8 = "d_reloc_z",
    nconsts: u64 = 0,
    // M3c: every fn's constant vector gets a synthesized `t' (Qt) appended
    // at index unit.consts.len (the last slot) by emitFileLLVM, so the
    // inline predicates / comparisons (emitUnaryPredicate,
    // emitBinaryCompare) can load the LIVE Qt value through d_reloc — the
    // exact pattern gccjit uses (comp.c emit_lisp_obj_reloc_lval).
    qt_const_idx: u64 = 0,
    // FDO: true while emitting a profile-identified HOT fn.  The inline
    // fast-path branches (fixnum-arith bothfix check, comparisons, NILP
    // conds) then get `!prof` branch-weight metadata so LLVM -O2 lays out
    // the inline path as the fall-through (the classic FDO block-layout
    // effect).  Set by emitNativeFn from the profile; off for non-FDO
    // builds so their output stays byte-identical to before.
    is_hot: bool = false,
    // FDO branch weights for THIS fn: [inline_weight, fallback_weight],
    // derived from the profile's real calls vs fallbacks counts.  Used
    // in the inline fast-path branches' !prof metadata.  Only set when
    // is_hot (a profile is present); otherwise the plain branches are
    // emitted and the output matches the non-FDO build.
    fdo_weights: [2]u64 = .{ 0, 0 },
    // FDO index of the fn being emitted (slot in @zeln_fdo_counters /
    // @zeln_fdo_fallbacks).  Set by emitNativeFn; used by the inline
    // branch emitters' fallback-counter increments.
    fn_index: u64 = 0,
    // True while counters are being emitted (not --final).  Gates the
    // fallback-counter blocks (emitFallbackCounter) alongside the
    // call-counter block.
    emit_fb_counters: bool = false,

    fn fresh(self: *Emitter) u32 {
        const r = self.next_reg;
        self.next_reg += 1;
        return r;
    }

    fn w(self: *Emitter, s: []const u8) !void {
        try self.out.appendSlice(self.gpa, s);
    }

    fn wf(self: *Emitter, comptime fmt: []const u8, args: anytype) !void {
        const s = try std.fmt.allocPrint(self.gpa, fmt, args);
        defer self.gpa.free(s);
        try self.out.appendSlice(self.gpa, s);
    }

    // Indented writer (every emitted IR line is indented 2 for readability).
    fn wi(self: *Emitter, s: []const u8) !void {
        try self.out.appendSlice(self.gpa, "  ");
        try self.out.appendSlice(self.gpa, s);
    }
    fn wif(self: *Emitter, comptime fmt: []const u8, args: anytype) !void {
        try self.out.appendSlice(self.gpa, "  ");
        const s = try std.fmt.allocPrint(self.gpa, fmt, args);
        defer self.gpa.free(s);
        try self.out.appendSlice(self.gpa, s);
    }

    // The `, !prof !{!"branch_weights", i32 W_IN, i32 W_FB}` suffix for an
    // inline fast-path branch, from THIS fn's real profile weights.  Empty
    // when not a profile-hot fn (branch emitted plain, non-FDO output
    // unchanged).  The first weight (W_IN) belongs to the inline path
    // (the branch's TRUE edge), the second (W_FB) to the fallback —
    // matches how LLVM consumes branch_weights on `br i1 %c, label %t,
    // label %f` (t = first weight).
    fn profMD(self: *Emitter, gpa: std.mem.Allocator) ![]const u8 {
        if (!self.is_hot) return "";
        return try std.fmt.allocPrint(
            gpa,
            ", !prof !{{!\"branch_weights\", i32 {d}, i32 {d}}}",
            .{ self.fdo_weights[0], self.fdo_weights[1] },
        );
    }

    // The inline-weight string for the hot check: either the real
    // branch_weights MD or empty.  Uses the emitter's stored allocator
    // so per-opcode emitters (which only hold *Emitter) can call it.
    fn profMDAlloc(self: *Emitter) ![]const u8 {
        return self.profMD(self.gpa);
    }

    // load %top.slot -> a fresh ptr register; returns the reg number.
    fn loadTop(self: *Emitter) !u32 {
        const r = self.fresh();
        try self.wif("%{d} = load ptr, ptr %top.slot\n", .{r});
        return r;
    }
    fn storeTop(self: *Emitter, reg: u32) !void {
        try self.wif("store ptr %{d}, ptr %top.slot\n", .{reg});
    }

    // Return a register pointing at %zargs[i] (the 3-slot scratch alloca).
    fn zargsSlot(self: *Emitter, i: u64) !u32 {
        const r = self.fresh();
        try self.wif("%{d} = getelementptr inbounds [3 x i64], ptr %zargs, i64 0, i64 {d}\n", .{ r, i });
        return r;
    }

    // Load d_reloc_z[const_idx] into a fresh register and return it.
    fn loadConst(self: *Emitter, const_idx: u64) !u32 {
        const cslot = self.fresh();
        try self.wif("%{d} = getelementptr inbounds [{d} x i64], ptr @{s}, i64 0, i64 {d}\n", .{ cslot, self.nconsts, self.d_reloc_global, const_idx });
        const cval = self.fresh();
        try self.wif("%{d} = load i64, ptr %{d}\n", .{ cval, cslot });
        return cval;
    }

    // Emit a uniform MANY freloc call (i64 return) and return the result reg.
    //   load link-table base; gep [SURFACE x ptr], 0, idx; load fn; call fn(nargs, argsbase)
    fn frelocCallI64(self: *Emitter, idx: u64, nargs: u64, argsbase: u32) !u32 {
        const rlt = self.fresh();
        try self.wif("%{d} = load ptr, ptr @freloc_link_table_z\n", .{rlt});
        const rslot = self.fresh();
        try self.wif("%{d} = getelementptr inbounds [{d} x ptr], ptr %{d}, i64 0, i64 {d}\n", .{ rslot, SURFACE, rlt, idx });
        const rfn = self.fresh();
        try self.wif("%{d} = load ptr, ptr %{d}\n", .{ rfn, rslot });
        const rret = self.fresh();
        try self.wif("%{d} = call i64 %{d}(i64 {d}, ptr %{d})\n", .{ rret, rfn, nargs, argsbase });
        return rret;
    }
};

// =====================================================================
// M2b multi-function container.  A FnUnit is ONE decoded closure (a
// defun from the source .elc); a .zeln carries N of them plus a
// top_level_blob.  emitFileLLVM emits the shared freloc/hash globals,
// per-fn d_reloc + sym_name globals, the function-table global, the
// top_level_blob global, N native fns (via emitNativeFn), and the
// zeln_entry global in the zeln_entry_t / zeln_fn_entry_t shape that
// matches src/compz.h field-for-field.  zabi=2 (M1) is the N=1 case
// with an empty top_level_blob, so ONE emitter serves both.
// =====================================================================
const FnUnit = struct {
    name: []const u8, // defun symbol name (placeholder "zeln-m1" for zabi=2)
    args_template: u32,
    stack_depth: u32,
    opcodes: []const u8,
    consts: [][]const u8,
};

// Emit ONE native fn: `define internal i64 @FN_NAME(i64 %nargs, ptr
// %args) { prologue + per-opcode body }`.  Pass 1 (decode + block
// pre-scan) + Pass 2 (per-opcode IR) are per-fn.  References @D_RELOC
// (THIS fn's const array) via em.d_reloc_global and the shared
// @freloc_link_table_z.  INTERNAL linkage so symbols do not interpose
// across concurrently loaded .zeln (RTLD_GLOBAL); only @zeln_entry is
// exported.
fn emitNativeFn(
    gpa: std.mem.Allocator,
    em: *Emitter,
    fn_name: []const u8,
    d_reloc_name: []const u8,
    unit: FnUnit,
    is_hot: bool,
    emit_counters: bool,
    fn_index: u64,
    weights: [2]u64,
) !void {
    const opcodes = unit.opcodes;
    if (opcodes.len == 0) return error.EmptyBytecode;
    if (unit.stack_depth > 0xFFFE) return error.StackDepthTooLarge;
    const stack_slots: u64 = @as(u64, unit.stack_depth) + 2;

    // Point the emitter at THIS fn's d_reloc global + const count, and
    // reset the temp register counter for a clean, readable trace.
    em.fn_index = fn_index;
    em.emit_fb_counters = emit_counters;
    em.d_reloc_global = d_reloc_name;
    // FDO hotness + real branch weights for this fn (drive !prof
    // weights on the inline branches below).
    em.is_hot = is_hot;
    em.fdo_weights = weights;
    // nconsts includes the synthesized Qt slot (unit.consts.len is its
    // index); emitFileLLVM appended `t' to the blob + sized the array +
    // fn-table n_d_reloc consistently.
    em.nconsts = unit.consts.len + 1;
    em.qt_const_idx = unit.consts.len;
    em.next_reg = 1;

    // ---- Pass 1: decode + pre-scan branch targets / block starts. ----
    const n = opcodes.len;
    var instrs = std.ArrayList(Instr).empty;
    defer instrs.deinit(gpa);
    var is_instr_start = try gpa.alloc(bool, n + 1);
    defer gpa.free(is_instr_start);
    @memset(is_instr_start, false);
    var is_block_start = try gpa.alloc(bool, n + 1);
    defer gpa.free(is_block_start);
    @memset(is_block_start, false);
    is_block_start[0] = true;

    var pc: u32 = 0;
    while (pc < n) {
        const ins = try decode(opcodes, pc);
        is_instr_start[ins.start] = true;
        try instrs.append(gpa, ins);
        pc = ins.end;
    }
    for (instrs.items) |ins| {
        switch (ins.op) {
            .goto_, .goto_if_nil, .goto_if_nonnil, .goto_if_nil_else_pop, .goto_if_nonnil_else_pop, .pushhandler => {
                if (ins.target >= n or !is_instr_start[ins.target])
                    return error.BranchTargetNotAligned;
                is_block_start[ins.target] = true;
                if (ins.end <= n) is_block_start[ins.end] = true;
            },
            .ret => {
                if (ins.end <= n) is_block_start[ins.end] = true;
            },
            else => {},
        }
    }

    // `hot` attribute on profile-identified hot fns: LLVM -O2 lays out
    // hot fns together and sizes the cold fns for speed, mirroring the
    // classic FDO layout effect.  Off when no profile was given (is_hot
    // false) so the non-FDO output is byte-identical to before.
    // `hot` attribute on profile-identified hot fns: LLVM -O2 lays out
    // hot fns together and sizes the cold fns for speed, mirroring the
    // classic FDO layout effect.  Placed in an attributes group (LLVM
    // rejects `hot` between `define` and the return type — it is a
    // function attribute, not a return-type attribute).  Off when no
    // profile was given (is_hot false) so the non-FDO output is
    // byte-identical to before.
    if (is_hot) {
        try em.wf("define internal i64 @{s}(i64 %nargs, ptr %args) #1 {{\n", .{fn_name});
    } else {
        try em.wf("define internal i64 @{s}(i64 %nargs, ptr %args) {{\n", .{fn_name});
    }
    try em.w("entry:\n");
    try em.wif("%stack = alloca [{d} x i64], align 8\n", .{stack_slots});
    // Zero the WHOLE virtual stack before use.  Only the slots up to `top'
    // are ever written by the bytecode; the slots above `top' (out to
    // stack_depth+2) would otherwise hold alloca garbage.  Emacs GC scans
    // the C stack conservatively (mark_memory over the thread stack), so a
    // stray garbage word whose bits land inside a swept heap block makes GC
    // mark_object it -> PVEC_FREE abort (the M2b gate #2 crash under any
    // GC-during-native-exec).  Zero words are not valid Lisp_Objects and
    // are ignored by mark_maybe_pointer, so this makes the conservative
    // scan safe while still protecting the live slots the bytecode fills.
    try em.wif("  call void @llvm.memset.p0.i64(ptr align 8 %stack, i8 0, i64 {d}, i1 false)\n", .{stack_slots * 8});
    try em.wif("%stackbase = getelementptr inbounds [{d} x i64], ptr %stack, i64 0, i64 1\n", .{stack_slots});
    try em.w("  %top.slot = alloca ptr, align 8\n");
    try em.w("  %zargs = alloca [3 x i64], align 8\n");
    // Zero %zargs too: varset/varbind write only [0..1] before the freloc
    // call (pushhandler writes [0..2]); the unused slot holds alloca garbage
    // that conservative GC scanning can misread as a freed object (the same
    // PVEC-FREE class as the virtual stack).  24 bytes; cheaper than a GC
    // abort on fns with heavy dynamic binding (e.g. cl--parsing-keywords).
    try em.w("  call void @llvm.memset.p0.i64(ptr align 8 %zargs, i8 0, i64 24, i1 false)\n");

    // ---- FDO call counter (auto profile collection, Z5). ----
    // Gated by @zeln_fdo_active: when the flag is 0 (FDO not enabled in
    // this session) the whole block collapses to one load + one icmp +
    // one branch — ~2 cycles, and the branch is perfectly predictable.
    // When the loader flips the flag to 1, every call increments THIS
    // fn's slot in @zeln_fdo_counters; the loader reads the array when
    // flushing the profile (interval-gated, post-GC).  `--final` (the
    // tuned recompile) drops the block entirely: zero FDO overhead on
    // the artifact.  Block labels are keyed on the fn index so multiple
    // fns in one .zeln cannot collide.
    if (emit_counters) {
        const fdo_a = em.fresh();
        try em.wif("%{d} = load i64, ptr @zeln_fdo_active\n", .{fdo_a});
        const fdo_t = em.fresh();
        try em.wif("%{d} = icmp eq i64 %{d}, 0\n", .{ fdo_t, fdo_a });
        try em.wif("br i1 %{d}, label %bb_fdo_sk_{d}, label %bb_fdo_ct_{d}\n", .{ fdo_t, fn_index, fn_index });
        try em.wf("bb_fdo_ct_{d}:\n", .{fn_index});
        const fdo_p = em.fresh();
        try em.wif("%{d} = getelementptr inbounds [{d} x i64], ptr @zeln_fdo_counters, i64 0, i64 {d}\n", .{ fdo_p, fn_index, fn_index });
        const fdo_c = em.fresh();
        try em.wif("%{d} = load i64, ptr %{d}\n", .{ fdo_c, fdo_p });
        const fdo_c1 = em.fresh();
        try em.wif("%{d} = add i64 %{d}, 1\n", .{ fdo_c1, fdo_c });
        try em.wif("store i64 %{d}, ptr %{d}\n", .{ fdo_c1, fdo_p });
        try em.wf("  br label %bb_fdo_sk_{d}\n", .{fn_index});
        try em.wf("bb_fdo_sk_{d}:\n", .{fn_index});
    }
    const rlt = em.fresh();
    try em.wif("%{d} = load ptr, ptr @freloc_link_table_z\n", .{rlt});
    const rslot = em.fresh();
    try em.wif("%{d} = getelementptr inbounds [{d} x ptr], ptr %{d}, i64 0, i64 {d}\n", .{ rslot, SURFACE, rlt, IDX_SETUP_ARGS });
    const rfn = em.fresh();
    try em.wif("%{d} = load ptr, ptr %{d}\n", .{ rfn, rslot });

    // ---- M3e: fixed-arity prologue inline (mirrors exec_byte_code's own
    // arg setup, bytecode.c:531-545).  When args_template is a fixed arity
    // (no &rest bit, mandatory == nonrest == k), copy the k args from %args
    // into the virtual stack inline when nargs == k, falling back to the
    // EXACT zeln_setup_args freloc call only on wrong arity (which signals
    // Qwrong_number_of_arguments identically).  Removes the per-call freloc
    // indirection + C loop for the common exact-arity call; the fallback
    // preserves the setup_args semantics bit-for-bit (same signal, same
    // rest/optional paths, same top computation stackbase + k - 1).
    const rest_bit = (unit.args_template & 128) != 0;
    const mandatory: u32 = unit.args_template & 127;
    const nonrest: u32 = unit.args_template >> 8;
    if (!rest_bit and mandatory == nonrest) {
        const k: i64 = mandatory;
        // Guard: nargs == k -> inline; else -> setup_args freloc call.
        const ok = em.fresh();
        try em.wif("%{d} = icmp eq i64 %nargs, {d}\n", .{ ok, k });
        try em.wif("br i1 %{d}, label %bb_sup_inl, label %bb_sup_fb\n", .{ok});
        // Inline copy: stackbase[i] = args[i] for i in 0..k-1.
        try em.w("bb_sup_inl:\n");
        for (0..@as(usize, @intCast(k))) |i| {
            const aslot = em.fresh();
            try em.wif("%{d} = getelementptr inbounds i64, ptr %args, i64 {d}\n", .{ aslot, i });
            const aval = em.fresh();
            try em.wif("%{d} = load i64, ptr %{d}\n", .{ aval, aslot });
            const sslot = em.fresh();
            try em.wif("%{d} = getelementptr inbounds i64, ptr %stackbase, i64 {d}\n", .{ sslot, i });
            try em.wif("store i64 %{d}, ptr %{d}\n", .{ aval, sslot });
        }
        // top = stackbase + k - 1 (stackbase - 1 for k = 0, mirroring
        // `top = stack - 1` before the k PUSHes).
        const rtop_inl = em.fresh();
        try em.wif("%{d} = getelementptr inbounds i64, ptr %stackbase, i64 {d}\n", .{ rtop_inl, k - 1 });
        try em.wif("store ptr %{d}, ptr %top.slot\n", .{rtop_inl});
        try em.wf("  br label %bb_{d}\n", .{0});
        // Fallback: the byte-identical setup_args freloc call.
        try em.w("bb_sup_fb:\n");
        const rtop0 = em.fresh();
        try em.wif("%{d} = call ptr %{d}(i64 {d}, i64 %nargs, ptr %args, ptr %stackbase)\n", .{ rtop0, rfn, unit.args_template });
        try em.wif("store ptr %{d}, ptr %top.slot\n", .{rtop0});
        try em.wf("  br label %bb_{d}\n", .{0});
    } else {
        const rtop0 = em.fresh();
        try em.wif("%{d} = call ptr %{d}(i64 {d}, i64 %nargs, ptr %args, ptr %stackbase)\n", .{ rtop0, rfn, unit.args_template });
        try em.wif("store ptr %{d}, ptr %top.slot\n", .{rtop0});
        try em.wf("  br label %bb_{d}\n", .{0});
    }

    // ---- Pass 2: per-opcode emission. ----
    var block_open: bool = false;
    for (instrs.items) |ins| {
        if (is_block_start[ins.start]) {
            if (block_open)
                try em.wf("  br label %bb_{d}\n", .{ins.start});
            try em.wf("bb_{d}:\n", .{ins.start});
            block_open = true;
        }

        switch (ins.op) {
            .constant => try emitConstant(em, ins.idx),
            .stack_ref => try emitStackRef(em, ins.imm),
            .dup => try emitDup(em),
            .discard => try emitDiscard(em),
            .stack_set => try emitStackSet(em, ins.imm),
            .ret => {
                try emitReturn(em);
                block_open = false;
            },
            .unary => {
                // Tier-1 inline fast paths for a subset of unary opcodes:
                //   * IDX_SUB1/ADD1/NEGATE -> fixnum-arith inline (M3a).
                //   * IDX_CAR/CDR          -> cons-slot inline (M3b).
                //   * IDX_CONSP/NULL       -> full inline type test (M3c).
                // Every other unary (predicates/list1/car-safe/cdr-safe/...)
                // keeps the Tier-0 freloc call.
                if (ins.idx == IDX_SUB1 or ins.idx == IDX_ADD1 or ins.idx == IDX_NEGATE)
                    try emitUnaryArith(em, ins.idx, ins.start)
                else if (ins.idx == IDX_CAR or ins.idx == IDX_CDR)
                    try emitConsSlot(em, ins.idx, ins.start)
                else if (ins.idx == IDX_CONSP or ins.idx == IDX_NULL)
                    try emitUnaryPredicate(em, ins.idx)
                else
                    try emitUnary(em, ins.idx);
            },
            .binary => {
                // Tier-1 fixnum inline fast paths for the arithmetic binary
                // opcodes (IDX_PLUS/MINUS/TIMES) and the comparisons
                // (IDX_EQLSIGN/GTR/LSS/LEQ/GEQ, M3c); every other binary
                // (cons/list2/eql/...) keeps the Tier-0 freloc call.
                if (ins.idx == IDX_PLUS or ins.idx == IDX_MINUS or ins.idx == IDX_TIMES)
                    try emitBinaryArith(em, ins.idx, ins.start)
                else if (ins.idx == IDX_EQLSIGN or ins.idx == IDX_GTR or ins.idx == IDX_LSS
                    or ins.idx == IDX_LEQ or ins.idx == IDX_GEQ)
                    try emitBinaryCompare(em, ins.idx, ins.start)
                else
                    try emitBinary(em, ins.idx);
            },
            .listn => try emitListN(em, ins.idx, ins.imm),
            .call => try emitCall(em, ins.imm),
            // ---- M2 ----
            .varref => try emitVarref(em, ins.idx),
            .varset => try emitVarset(em, ins.idx),
            .varbind => try emitVarbind(em, ins.idx),
            .unbind => try emitUnbind(em, ins.imm),
            .discard_n => try emitDiscardN(em, ins.imm),
            .push0 => try emitPush0(em, ins.idx),
            .noarg => try emitNoArg(em, ins.idx),
            .unary_pop => try emitUnaryPop(em, ins.idx),
            .pushhandler => {
                try emitPushHandler(em, ins.idx, ins.target, ins.end);
                block_open = false;
            },
            .goto_ => {
                try em.wf("  br label %bb_{d}\n", .{ins.target});
                block_open = false;
            },
            .goto_if_nil => {
                try emitCondPop(em, ins.target, ins.end, .eq_nil);
                block_open = false;
            },
            .goto_if_nonnil => {
                try emitCondPop(em, ins.target, ins.end, .eq_nonnil);
                block_open = false;
            },
            .goto_if_nil_else_pop => {
                try emitCondElsePop(em, ins.start, ins.target, ins.end, .eq_nil);
                block_open = false;
            },
            .goto_if_nonnil_else_pop => {
                try emitCondElsePop(em, ins.start, ins.target, ins.end, .eq_nonnil);
                block_open = false;
            },
        }
    }

    if (block_open) {
        try em.w("  ret i64 0\n");
    }
    try em.w("}\n\n");
}

// Per-fn FALLBACK counter: increment THIS fn's slot in
// @zeln_fdo_fallbacks when an M3 inline fast-path branch takes the
// freloc fallback (bignum/float/non-fixnum).  Same gated pattern as
// the call counter (flag 0 => one load + icmp + branch, ~free), so the
// profile can report the REAL fallback frequency and the PGO recompile
// can weight the branches accordingly.  The caller must have emitted
// the `bb_far_<s>:` / `bb_cfc_<s>:` label already; this function only
// emits the counter + fall-through.  Omitted entirely on --final.
fn emitFallbackCounter(em: *Emitter, start: u32) !void {
    if (!em.emit_fb_counters) return;
    const fdo_a = em.fresh();
    try em.wif("%{d} = load i64, ptr @zeln_fdo_active\n", .{fdo_a});
    const fdo_t = em.fresh();
    try em.wif("%{d} = icmp eq i64 %{d}, 0\n", .{ fdo_t, fdo_a });
    try em.wif("br i1 %{d}, label %bb_fbf_sk_{d}, label %bb_fbf_ct_{d}\n", .{ fdo_t, start, start });
    try em.wf("bb_fbf_ct_{d}:\n", .{start});
    const fdo_p = em.fresh();
    try em.wif("%{d} = getelementptr inbounds [{d} x i64], ptr @zeln_fdo_fallbacks, i64 0, i64 {d}\n", .{ fdo_p, em.fn_index, em.fn_index });
    const fdo_c = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ fdo_c, fdo_p });
    const fdo_c1 = em.fresh();
    try em.wif("%{d} = add i64 %{d}, 1\n", .{ fdo_c1, fdo_c });
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ fdo_c1, fdo_p });
    try em.wf("  br label %bb_fbf_sk_{d}\n", .{start});
    try em.wf("bb_fbf_sk_{d}:\n", .{start});
}

// Emit the whole .ll for a multi-function .zeln: shared globals + per-fn
// globals + fn table + top_level_blob + N native fns + entry.  FNS is
// non-empty (zabi=2 passes 1; zabi=3 passes N).  TOP_BLOB is the raw
// (progn ...) read-syntax ("" for the M1 single-fn case).
fn emitFileLLVM(
    gpa: std.mem.Allocator,
    fns: []const FnUnit,
    abi_hash: []const u8,
    top_blob: []const u8,
    zunit_bytes: []const u8,
    fdo_counts: std.StringHashMap(u64),
    fdo_fallbacks: std.StringHashMap(u64),
    fdo_final: bool,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    var em = Emitter{ .gpa = gpa, .out = &out };

    // FDO hotness map: symbol name -> 1 for "hot" (count > 0 in the
    // profile), kept alive for the whole emission.  The fn table is
    // reordered hot-first when a profile is present (loader matches
    // fns by symbol name, so the reorder is transparent to it).
    var hot_set = std.StringHashMap(bool).init(gpa);
    defer hot_set.deinit();
    if (fdo_counts.count() > 0) {
        var it = fdo_counts.iterator();
        while (it.next()) |e| {
            if (e.value_ptr.* > 0) try hot_set.put(e.key_ptr.*, true);
        }
    }
    const hot = struct {
        fn isHot(s: std.StringHashMap(bool), name: []const u8) bool {
            return s.get(name) orelse false;
        }
    }.isHot;

    // Real branch weights per fn: inline_weight = calls - fallbacks,
    // fallback_weight = fallbacks (both floored at 1).  The inline
    // branches' !prof metadata uses these, so a fn whose fallback path
    // is genuinely hot (bignum/float-heavy) gets weights that let LLVM
    // lay the fallback as fall-through — fixing the hardcoded
    // 1000000:1 weights that were wrong on such workloads.
    const weightOf = struct {
        fn get(counts: std.StringHashMap(u64), fbs: std.StringHashMap(u64), name: []const u8) [2]u64 {
            const calls = counts.get(name) orelse 0;
            const fbs_v = fbs.get(name) orelse 0;
            const inline_w = @max(@as(u64, 1), calls -| fbs_v);
            return .{ inline_w, @max(@as(u64, 1), fbs_v) };
        }
    }.get;

    try em.w("; zeln.ll — Tier-0 emission of a multi-function .zeln (M2b).\n");
    try em.w("; Generated by tools/zeln-compile. N native fns (one per defun)\n");
    try em.w("; plus a top_level_blob replaying the .elc's non-defun forms.\n\n");

    // Shared freloc link-table slot (loader-patched) + ABI hash string.
    try em.w("@freloc_link_table_z = internal global ptr null\n");
    var hash_lit: std.ArrayList(u8) = .empty;
    defer hash_lit.deinit(gpa);
    try appendCStringLiteral(gpa, &hash_lit, abi_hash);
    try hash_lit.appendSlice(gpa, "\\00");
    try em.wf("@freloc_hash_z_data = internal constant [9 x i8] c\"{s}\"\n\n", .{hash_lit.items});

    // ---- FDO state (auto profile-guided recompilation, Z5). ----
    // @zeln_fdo_active gates ALL per-fn call counters: when it is 0
    // (the default; the loader flips it to 1 to start collecting) every
    // counter block falls through after one load+icmp+branch, so an
    // FDO-off session pays ~nothing.  @zeln_fdo_counters is the [n_fns]
    // per-fn call-count array the loader reads when flushing profiles.
    // @zeln_zunit_blob embeds the ORIGINAL zunit bytes so the loader can
    // recompile the unit at runtime (auto-FDO) without the build
    // pipeline: it writes the blob back to disk + a manifest + the
    // profile, then spawns zeln-compile.  --final drops the counters
    // entirely (the tuned artifact); the active flag + counters array +
    // zunit blob are still emitted (entry fields must stay present).
    try em.w("@zeln_fdo_active = internal global i64 0\n");
    try em.wf("@zeln_fdo_counters = internal global [{d} x i64] zeroinitializer\n", .{fns.len});
    // Per-fn FALLBACK counters: how many times each fn's M3 inline
    // fast-path branches took the freloc fallback (bignum/float/non-
    // fixnum operands).  Incremented in the same gated style as the
    // call counters; the loader flushes both to the profile file
    // (format: fnname<calls<TAB>fallbacks), and the PGO recompile
    // derives the !prof branch weights from the REAL ratio.
    try em.wf("@zeln_fdo_fallbacks = internal global [{d} x i64] zeroinitializer\n\n", .{fns.len});

    // The embedded zunit: { i64 len, [len x i8] data }.  The loader Freads
    // nothing from it — it writes the raw bytes to disk for recompile.
    {
        var zu_lit: std.ArrayList(u8) = .empty;
        defer zu_lit.deinit(gpa);
        try appendCStringLiteral(gpa, &zu_lit, zunit_bytes);
        try em.wf("@zeln_zunit_blob_data = internal constant {{ i64, [{d} x i8] }} {{ i64 {d}, [{d} x i8] c\"{s}\" }}\n\n", .{ zunit_bytes.len, zunit_bytes.len, zunit_bytes.len, zu_lit.items });
    }

    // Per-fn emission ORDER: with an FDO profile the fn table is laid out
    // hot-first (higher call counts first) so the hottest code lands first
    // in the .so text segment — better icache locality for the hot loop.
    // WITHOUT a profile the order is the zunit's (stable, matches every
    // non-FDO .zeln).  The loader matches fns by SYMBOL NAME on hot-swap
    // (never by index), so reordering is fully transparent to it.
    var order = try gpa.alloc(usize, fns.len);
    defer gpa.free(order);
    if (fdo_counts.count() > 0) {
        var hot_i: usize = 0;
        var cold_i: usize = fns.len;
        for (fns, 0..) |unit, i| {
            if (hot(hot_set, unit.name)) {
                order[hot_i] = i;
                hot_i += 1;
            } else {
                cold_i -= 1;
                order[cold_i] = i;
            }
        }
    } else {
        for (0..fns.len) |i| order[i] = i;
    }

    // Per-fn globals: d_reloc slot array + d_reloc read-syntax blob +
    // the NUL-terminated defun symbol name.  EVERY fn gets a synthesized
    // trailing `t' constant (the Qt slot, index unit.consts.len) so the
    // M3c inline predicates/comparisons can load the LIVE Qt through
    // d_reloc (gccjit's pattern: emit_lisp_obj_reloc_lval).  The loader
    // Freads the blob and checks its length against n_d_reloc, so the
    // array size, blob, and fn-table n_d_reloc must all count N+1.
    // Globals keep their ORIGINAL index (zeln_fn_<orig_i>) — only the
    // table order changes.
    for (fns, 0..) |unit, i| {
        var blob: std.ArrayList(u8) = .empty;
        defer blob.deinit(gpa);
        try blob.append(gpa, '[');
        for (unit.consts, 0..) |c, j| {
            if (j > 0) try blob.append(gpa, ' ');
            try blob.appendSlice(gpa, c);
        }
        try blob.appendSlice(gpa, " t");
        try blob.append(gpa, ']');
        const blob_bytes = blob.items;
        var blob_lit: std.ArrayList(u8) = .empty;
        defer blob_lit.deinit(gpa);
        try appendCStringLiteral(gpa, &blob_lit, blob_bytes);
        try em.wf("@d_reloc_z_{d} = internal global [{d} x i64] zeroinitializer\n", .{ i, unit.consts.len + 1 });
        try em.wf("@d_reloc_blob_{d} = internal constant {{ i64, [{d} x i8] }} {{ i64 {d}, [{d} x i8] c\"{s}\" }}\n", .{ i, blob_bytes.len, blob_bytes.len, blob_bytes.len, blob_lit.items });

        var name_lit: std.ArrayList(u8) = .empty;
        defer name_lit.deinit(gpa);
        try appendCStringLiteral(gpa, &name_lit, unit.name);
        try name_lit.appendSlice(gpa, "\\00");
        try em.wf("@sym_name_{d} = internal constant [{d} x i8] c\"{s}\"\n", .{ i, unit.name.len + 1, name_lit.items });
    }
    try em.w("\n");

    // Function table: [N x { ptr native_fn, i64 args_template, ptr
    // symbol_name, ptr d_reloc, i64 n_d_reloc, ptr d_reloc_blob }]
    // matching zeln_fn_entry_t (compz.h).  HOT-FIRST order with a
    // profile (see `order` above).
    try em.wf("@zeln_fn_table = private constant [{d} x {{ ptr, i64, ptr, ptr, i64, ptr }}] [\n", .{fns.len});
    for (order, 0..) |orig_i, slot| {
        const unit = fns[orig_i];
        // Each array element needs an explicit struct-type prefix (LLVM
        // rejects a bare struct value as an array element).
        try em.wf("  {{ ptr, i64, ptr, ptr, i64, ptr }} {{ ptr @zeln_fn_{d}, i64 {d}, ptr @sym_name_{d}, ptr @d_reloc_z_{d}, i64 {d}, ptr @d_reloc_blob_{d} }}{s}\n", .{
            orig_i, unit.args_template, orig_i, orig_i, unit.consts.len + 1, orig_i,
            if (slot + 1 < fns.len) "," else "",
        });
    }
    try em.w("]\n\n");

    // top_level_blob: { i64 len, [len x i8] data }.  Zero-len for the M1
    // single-fn case; the loader skips a zero-len blob.
    var top_lit: std.ArrayList(u8) = .empty;
    defer top_lit.deinit(gpa);
    try appendCStringLiteral(gpa, &top_lit, top_blob);
    try em.wf("@top_level_blob_data = internal constant {{ i64, [{d} x i8] }} {{ i64 {d}, [{d} x i8] c\"{s}\" }}\n\n", .{ top_blob.len, top_blob.len, top_blob.len, top_lit.items });

    // _setjmp (sys_setjmp on glibc) declared DIRECTLY in the native fn for
    // the pushhandler trio so longjmp lands in the native frame.
    try em.w("; sys_setjmp == _setjmp on glibc (HAVE__SETJMP first).\n");
    try em.w("declare i32 @_setjmp(ptr) #0\n");
    try em.w("attributes #0 = { nounwind returns_twice }\n");
    // FDO: `hot` function attribute for profile-identified hot fns
    // (LLVM layout hint).  Emitted unconditionally; #1 is only
    // referenced when is_hot fired for at least one fn, and an unused
    // attribute group is dropped by -O2 with no cost.
    try em.w("attributes #1 = { hot }\n");
    // memset intrinsic: zero each native fn's alloca virtual stack at entry
    // (see emitNativeFn) so conservative C-stack GC never marks alloca
    // garbage as a live object.
    try em.w("declare void @llvm.memset.p0.i64(ptr nocapture writeonly, i8, i64, i1 immarg)\n");
    // smul.with.overflow intrinsic: the Bmult inline fast path (emitBinaryArith
    // IDX_TIMES) uses it to mirror the interpreter's ckd_mul on intmax_t
    // (bytecode.c:1379; intmax_t is 64-bit on every Tier-1 target, so this is
    // a signed 64-bit checked multiply — the exact ckd_mul semantic).  Declared
    // unconditionally (like memset/_setjmp); an unreferenced declare is dropped
    // by -O2, so fns with no Bmult pay nothing.
    try em.w("declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)\n\n");

    // N native fns.  Emitted in the HOT-FIRST order so the hottest code
    // lands first in the .so text segment; each keeps its ORIGINAL index
    // (zeln_fn_<orig_i>) so the fn table's globals stay consistent.
    for (order) |orig_i| {
        const unit = fns[orig_i];
        const fn_name = try std.fmt.allocPrint(gpa, "zeln_fn_{d}", .{orig_i});
        defer gpa.free(fn_name);
        const drr = try std.fmt.allocPrint(gpa, "d_reloc_z_{d}", .{orig_i});
        defer gpa.free(drr);
        const this_hot = hot(hot_set, unit.name);
        const w = weightOf(fdo_counts, fdo_fallbacks, unit.name);
        try emitNativeFn(gpa, &em, fn_name, drr, unit, this_hot, !fdo_final, orig_i, w);
    }

    // File entry: { ptr freloc_link_table_z, ptr freloc_hash_z, i64 n_fns,
    // ptr fns, ptr top_level_blob, ptr fdo_active, ptr fdo_counters,
    // ptr fdo_fallbacks, i64 n_fdo, ptr zunit_blob } matching
    // zeln_entry_t (compz.h).  The four FDO fields are appended after
    // top_level_blob (Z5; fdo_fallbacks added in Z6).
    try em.w("@zeln_entry_global = internal global { ptr, ptr, i64, ptr, ptr, ptr, ptr, ptr, i64, ptr } {\n");
    try em.w("  ptr @freloc_link_table_z,\n");
    try em.w("  ptr @freloc_hash_z_data,\n");
    try em.wf("  i64 {d},\n", .{fns.len});
    try em.w("  ptr @zeln_fn_table,\n");
    try em.w("  ptr @top_level_blob_data,\n");
    try em.w("  ptr @zeln_fdo_active,\n");
    try em.w("  ptr @zeln_fdo_counters,\n");
    try em.w("  ptr @zeln_fdo_fallbacks,\n");
    try em.wf("  i64 {d},\n", .{fns.len});
    try em.w("  ptr @zeln_zunit_blob_data\n}\n\n");

    try em.w("define dso_local ptr @zeln_entry() {\n");
    try em.w("entry:\n");
    try em.w("  ret ptr @zeln_entry_global\n");
    try em.w("}\n");

    return out.toOwnedSlice(gpa);
}

// zabi=2 (M1 single-fn): the N=1 case of the multi-function container,
// with a placeholder symbol name and an empty top_level_blob.
fn emitM1LLVM(gpa: std.mem.Allocator, unit: M1Unit, abi_hash: []const u8, zunit_bytes: []const u8, fdo_counts: std.StringHashMap(u64), fdo_fallbacks: std.StringHashMap(u64), fdo_final: bool) ![]u8 {
    var fns = try gpa.alloc(FnUnit, 1);
    defer gpa.free(fns);
    fns[0] = .{
        .name = "zeln-m1",
        .args_template = unit.args_template,
        .stack_depth = unit.stack_depth,
        .opcodes = unit.opcodes,
        .consts = unit.consts,
    };
    return emitFileLLVM(gpa, fns, abi_hash, "", zunit_bytes, fdo_counts, fdo_fallbacks, fdo_final);
}

// ---- Per-opcode IR fragments.  Each assumes a block is currently open
//      and %top.slot holds the current `top`; PUSH/POP mirror the
//      interpreter exactly (`*++top = x`; bytecode.c:283).  All values are
//      raw i64 Lisp_Objects; tag bits are never computed in IR. ----

// Bconstant: PUSH d_reloc_z[idx].
fn emitConstant(em: *Emitter, idx: u64) !void {
    const t = try em.loadTop();
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 1\n", .{ np, t });
    const cval = try em.loadConst(idx);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ cval, np });
    try em.storeTop(np);
}

// Bstack_refN: PUSH top[-depth] (depth>=1).  Bdup is depth 0.
fn emitStackRef(em: *Emitter, depth: u32) !void {
    const t = try em.loadTop();
    const di: i64 = -@as(i64, depth);
    const src = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 {d}\n", .{ src, t, di });
    const v = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ v, src });
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 1\n", .{ np, t });
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ v, np });
    try em.storeTop(np);
}

fn emitDup(em: *Emitter) !void {
    const t = try em.loadTop();
    const v = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ v, t });
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 1\n", .{ np, t });
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ v, np });
    try em.storeTop(np);
}

fn emitDiscard(em: *Emitter) !void {
    const t = try em.loadTop();
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 -1\n", .{ np, t });
    try em.storeTop(np);
}

// Bstack_set/Bstack_set2 (lexical setq): ptr = top[-depth]; *ptr = POP.
// The popped value is the OLD top (t[0]); POP only decrements the pointer
// (bytecode.c:1718-1724), mirroring the interpreter's `*ptr = POP`.
fn emitStackSet(em: *Emitter, depth: u32) !void {
    const t = try em.loadTop();
    const v = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ v, t }); // popped value (TOS)
    const di: i64 = -@as(i64, depth);
    const ptr = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 {d}\n", .{ ptr, t, di });
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ v, ptr });
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 -1\n", .{ np, t });
    try em.storeTop(np);
}

fn emitReturn(em: *Emitter) !void {
    const t = try em.loadTop();
    const v = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ v, t });
    try em.wif("ret i64 %{d}\n", .{v});
}

// Unary op on TOP (Bsub1/Bcar/Bsymbolp/...): TOP = fn(1, &TOP), in place.
fn emitUnary(em: *Emitter, idx: u64) !void {
    const t = try em.loadTop();
    const r = try em.frelocCallI64(idx, 1, t);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ r, t });
}

// Binary op (Bplus/Bdiff/Blss/Bcons/...): v2=POP; v1=TOP; res=fn(2, &v1).
// After POP, newtop[0]=v1 and newtop[1] still holds v2 (POP only decrements
// the pointer — mirror interpreter's `Fplus(2, &TOP)` after POP).
fn emitBinary(em: *Emitter, idx: u64) !void {
    const t = try em.loadTop();
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 -1\n", .{ np, t });
    try em.storeTop(np);
    const r = try em.frelocCallI64(idx, 2, np);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ r, np });
}

// ---- Tier-1 fixnum-arith inline fast path (M3a). -------------------------
// For Bplus/Bdiff/Bmult (IDX_PLUS/MINUS/TIMES) and Bsub1/Badd1/Bnegate
// (IDX_SUB1/ADD1/NEGATE), emit the inline FIXNUMP + tagged-op + overflow
// fast path in the .ll, falling back to the EXACT freloc shim call the
// Tier-0 emitter makes (zeln_plus->Fplus etc.) on overflow or any
// non-fixnum operand.  This removes, for the common fixnum case, BOTH the
// 3-instruction freloc indirection AND the full Fplus/Fminus/Ftimes body.
//
// Identity holds by construction (gate #2 + zeln-diff enforce it):
//   * Inline path produces make_fixnum(XFIXNUM(v1) op XFIXNUM(v2)) under
//     the SAME overflow rule the interpreter uses (bytecode.c:1331 Bplus,
//     1311 Bdiff, 1373 Bmult, 1244 Bsub1, 1250 Badd1, 1325 Bnegate) —
//     which is exactly what Fplus/Fminus/Ftimes return for two
//     non-overflowing fixnums (their own fast path is the same arithmetic).
//   * Fallback path is the byte-identical freloc shim call taken on
//     overflow OR any non-fixnum operand (float/bignum/marker), so bignum
//     arithmetic and the fixnum-overflow edge are unchanged.
// The POP/stack prefixes REUSE emitBinary/emitUnary's exact IR so the
// surrounding stack discipline is untouched.  The freloc surface, IDX
// order, and .zeln layout are UNCHANGED (no ZELN_ABI_VERSION bump).
//
// Bmult note: the interpreter uses `intmax_t res; ckd_mul(&res, ...)`.
// intmax_t is 64-bit on every Tier-1 target, so ckd_mul is a signed 64-bit
// checked multiply — the exact semantic of llvm.smul.with.overflow.i64.
// ------------------------------------------------------------------------

// Binary arith (Bplus/Bdiff/Bmult): same POP as emitBinary, then inline.
// Unique per-instruction block labels are keyed on START (the opcode's byte
// offset, unique within a fn): bb_ari_<s> (arith), bb_aok_<s> (inline-ok),
// bb_far_<s> (fallback), bb_adone_<s> (merge / continuation).
fn emitBinaryArith(em: *Emitter, idx: u64, start: u32) !void {
    // POP prefix — byte-identical to emitBinary: top -= 1; new top[0] = v1,
    // new top[1] = v2 (POP only decrements the pointer).
    const t = try em.loadTop();
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 -1\n", .{ np, t });
    try em.storeTop(np);
    // Load v1 = np[0], v2 = np[1] (both pristine for the fallback call).
    const v1 = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ v1, np });
    const v2slot = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 1\n", .{ v2slot, np });
    const v2 = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ v2, v2slot });
    // FIXNUMP(v) = (v & 3) == 2 (USE_LSB_TAG: Lisp_Int0 low 2 bits).
    const m1 = em.fresh();
    try em.wif("%{d} = and i64 %{d}, {d}\n", .{ m1, v1, FIXNUM_LSB_MASK });
    const f1 = em.fresh();
    try em.wif("%{d} = icmp eq i64 %{d}, {d}\n", .{ f1, m1, FIXNUM_LSB_TAG });
    const m2 = em.fresh();
    try em.wif("%{d} = and i64 %{d}, {d}\n", .{ m2, v2, FIXNUM_LSB_MASK });
    const f2 = em.fresh();
    try em.wif("%{d} = icmp eq i64 %{d}, {d}\n", .{ f2, m2, FIXNUM_LSB_TAG });
    const bothfix = em.fresh();
    try em.wif("%{d} = and i1 %{d}, %{d}\n", .{ bothfix, f1, f2 });
    // both-fixnum -> inline arith; else -> fallback (freloc call).  FDO:
    // hot fns get !prof branch weights from the REAL profile (inline =
    // calls - fallbacks, fallback = fallbacks) so LLVM lays out whichever
    // path is genuinely hot as fall-through.
    const pmd = try em.profMDAlloc();
    defer em.gpa.free(pmd);
    try em.wif("br i1 %{d}, label %bb_ari_{d}, label %bb_far_{d}{s}\n", .{ bothfix, start, start, pmd });

    // Inline arith block: decode operands, compute res, test overflow.
    try em.wf("bb_ari_{d}:\n", .{start});
    const a1 = em.fresh();
    try em.wif("%{d} = ashr i64 %{d}, {d}\n", .{ a1, v1, FIXNUM_SHIFT });
    const a2 = em.fresh();
    try em.wif("%{d} = ashr i64 %{d}, {d}\n", .{ a2, v2, FIXNUM_SHIFT });

    // Allocate `res` lazily inside each branch so the TIMES path can allocate
    // `mul` BEFORE `res` (LLVM textual IR requires `%N` to only reference `%M`
    // with M < N; the extractvalue `%res = extractvalue %mul` needs mul < res).
    var res: u32 = 0;
    const ov_reg: u32 = if (idx == IDX_PLUS) blk: {
        res = em.fresh();
        try em.wif("%{d} = add i64 %{d}, %{d}\n", .{ res, a1, a2 });
        break :blk try emitFixnumRangeCheck(em, res);
    } else if (idx == IDX_MINUS) blk: {
        res = em.fresh();
        try em.wif("%{d} = sub i64 %{d}, %{d}\n", .{ res, a1, a2 });
        break :blk try emitFixnumRangeCheck(em, res);
    } else blk: {
        // IDX_TIMES: ckd_mul (intmax_t==i64) -> smul.with.overflow, then the
        // same range check (mirrors bytecode.c:1378-1380).  mul is allocated
        // first so `%res = extractvalue %mul` is well-numbered.
        const mul = em.fresh();
        try em.wif("%{d} = call {{ i64, i1 }} @llvm.smul.with.overflow.i64(i64 %{d}, i64 %{d})\n", .{ mul, a1, a2 });
        res = em.fresh();
        try em.wif("%{d} = extractvalue {{ i64, i1 }} %{d}, 0\n", .{ res, mul });
        const mulov = em.fresh();
        try em.wif("%{d} = extractvalue {{ i64, i1 }} %{d}, 1\n", .{ mulov, mul });
        const rangeov = try emitFixnumRangeCheck(em, res);
        const both = em.fresh();
        try em.wif("%{d} = or i1 %{d}, %{d}\n", .{ both, mulov, rangeov });
        break :blk both;
    };
    // overflow -> fallback (freloc); else -> inline-ok store.
    try em.wif("br i1 %{d}, label %bb_far_{d}, label %bb_aok_{d}\n", .{ ov_reg, start, start });

    // Inline success: store make_fixnum(res) = (res << 2) | 2 at np[0].
    try em.wf("bb_aok_{d}:\n", .{start});
    try emitStoreMakeFixnum(em, res, np);
    try em.wif("br label %bb_adone_{d}\n", .{start});

    // Fallback: the byte-identical freloc shim call (zeln_plus->Fplus etc.)
    // the Tier-0 emitter makes — np[0]=v1, np[1]=v2 are still pristine.
    try em.wf("bb_far_{d}:\n", .{start});
    try emitFallbackCounter(em, start);
    const r = try em.frelocCallI64(idx, 2, np);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ r, np });
    try em.wif("br label %bb_adone_{d}\n", .{start});

    // Merge: result is at np[0] either way; next instruction attaches here.
    try em.wf("bb_adone_{d}:\n", .{start});
}

// Unary arith (Bsub1/Badd1/Bnegate): same stack prefix as emitUnary (TOP in
// place at t[0]), then inline.  Labels keyed on START (unique per insn).
fn emitUnaryArith(em: *Emitter, idx: u64, start: u32) !void {
    const t = try em.loadTop();
    const v = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ v, t }); // TOP
    // FIXNUMP(v).
    const m = em.fresh();
    try em.wif("%{d} = and i64 %{d}, {d}\n", .{ m, v, FIXNUM_LSB_MASK });
    const fix = em.fresh();
    try em.wif("%{d} = icmp eq i64 %{d}, {d}\n", .{ fix, m, FIXNUM_LSB_TAG });
    const pmd = try em.profMDAlloc();
    defer em.gpa.free(pmd);
    try em.wif("br i1 %{d}, label %bb_ari_{d}, label %bb_far_{d}{s}\n", .{ fix, start, start, pmd });

    // Inline arith block.
    try em.wf("bb_ari_{d}:\n", .{start});
    const a = em.fresh();
    try em.wif("%{d} = ashr i64 %{d}, {d}\n", .{ a, v, FIXNUM_SHIFT });
    const res = em.fresh();
    const ov_reg: u32 = if (idx == IDX_SUB1) blk: {
        // res = a - 1; overflow only at a == MOST_NEGATIVE_FIXNUM.
        try em.wif("%{d} = sub i64 %{d}, 1\n", .{ res, a });
        const o = em.fresh();
        try em.wif("%{d} = icmp eq i64 %{d}, {d}\n", .{ o, a, MOST_NEGATIVE_FIXNUM });
        break :blk o;
    } else if (idx == IDX_ADD1) blk: {
        // res = a + 1; overflow only at a == MOST_POSITIVE_FIXNUM.
        try em.wif("%{d} = add i64 %{d}, 1\n", .{ res, a });
        const o = em.fresh();
        try em.wif("%{d} = icmp eq i64 %{d}, {d}\n", .{ o, a, MOST_POSITIVE_FIXNUM });
        break :blk o;
    } else blk: {
        // IDX_NEGATE: res = 0 - a; overflow only at a == MOST_NEGATIVE_FIXNUM
        // (negating it would yield MOST_POS+1, out of fixnum range).
        try em.wif("%{d} = sub i64 0, %{d}\n", .{ res, a });
        const o = em.fresh();
        try em.wif("%{d} = icmp eq i64 %{d}, {d}\n", .{ o, a, MOST_NEGATIVE_FIXNUM });
        break :blk o;
    };
    try em.wif("br i1 %{d}, label %bb_far_{d}, label %bb_aok_{d}\n", .{ ov_reg, start, start });

    // Inline success: store make_fixnum(res) at t[0].
    try em.wf("bb_aok_{d}:\n", .{start});
    try emitStoreMakeFixnum(em, res, t);
    try em.wif("br label %bb_adone_{d}\n", .{start});

    // Fallback: byte-identical freloc shim call (zeln_sub1->Fsub1 etc.).
    try em.wf("bb_far_{d}:\n", .{start});
    try emitFallbackCounter(em, start);
    const r = try em.frelocCallI64(idx, 1, t);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ r, t });
    try em.wif("br label %bb_adone_{d}\n", .{start});

    try em.wf("bb_adone_{d}:\n", .{start});
}

// ---- Tier-1 cons-slot inline fast path (M3b). ---------------------------
// For Bcar/Bcdr (IDX_CAR/IDX_CDR), emit the inline CONSP-guarded XCAR/XCDR
// read mirroring the interpreter's own Bcar/Bcdr fast path (bytecode.c:658,
// 682: `if (CONSP (TOP)) TOP = XCAR (TOP)`), falling back to the EXACT
// freloc shim call the Tier-0 emitter makes (zeln_car -> Fcar -> CAR,
// zeln_cdr -> Fcdr -> CDR) for nil or any non-cons.  This removes, for the
// common cons case, BOTH the 3-instruction freloc indirection AND the full
// Fcar/Fcdr type-dispatch body, replacing it with a mask test + slot load.
//
// Identity holds by construction (gate #2 + zeln-diff enforce it):
//   * Inline path is taken ONLY when CONSP(v) is true, producing XCAR/XCDR
//     (v) == CAR/CDR (v) == Fcar/Fcdr (v) for every cons (data.c:659,677;
//     lisp.h:1521,1530: CAR/CDR return XCAR/XCDR for conses).  This is the
//     exact same value the interpreter's Bcar/Bcdr stores in the same case.
//   * Fallback path is the byte-identical freloc shim call, taken for nil
//     (Fcar(nil) = CAR(nil) = Qnil, matching the interpreter's fall-through)
//     and for non-list non-nil (Fcar -> CAR -> wrong_type_argument(Qlistp),
//     matching the interpreter's else-branch).  So inline+fallback == the
//     current freloc shim == the interpreter, for all inputs.
//   * The USE_LSB_TAG + cons-layout assumptions are the same ones M3a's
//     fixnum inline makes and are asserted at .zeln load; the freloc
//     surface, IDX order, and .zeln layout are UNCHANGED (no ABI bump).
// -------------------------------------------------------------------------
// Labels keyed on START (the opcode's byte offset, unique within a fn):
// bb_csl_<s> (cons-slot inline), bb_cfr_<s> (fallback), bb_cdone_<s> (merge).
fn emitConsSlot(em: *Emitter, idx: u64, start: u32) !void {
    const t = try em.loadTop();
    const v = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ v, t }); // TOP (pristine for fallback)
    // CONSP(v) = (v & 7) == 3 (USE_LSB_TAG: Lisp_Cons = 3, ~VALMASK = 7).
    const m = em.fresh();
    try em.wif("%{d} = and i64 %{d}, {d}\n", .{ m, v, CONSP_MASK });
    const consp = em.fresh();
    try em.wif("%{d} = icmp eq i64 %{d}, {d}\n", .{ consp, m, CONSP_TAG });
    try em.wif("br i1 %{d}, label %bb_csl_{d}, label %bb_cfr_{d}\n", .{ consp, start, start });

    // Inline cons-slot block: XCONS(v) = v & -8 (clear the low tag bits);
    // then load the car (offset 0) or cdr (offset 8, i64 index 1) slot.
    try em.wf("bb_csl_{d}:\n", .{start});
    const cptr_int = em.fresh();
    try em.wif("%{d} = and i64 %{d}, {d}\n", .{ cptr_int, v, XCONS_UNTAG_MASK });
    const cptr = em.fresh();
    try em.wif("%{d} = inttoptr i64 %{d} to ptr\n", .{ cptr, cptr_int });
    const slot_idx: u6 = if (idx == IDX_CAR) XCAR_OFFSET else XCDR_OFFSET;
    const slot = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 {d}\n", .{ slot, cptr, slot_idx });
    const res = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ res, slot });
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ res, t });
    try em.wif("br label %bb_cdone_{d}\n", .{start});

    // Fallback: byte-identical freloc shim call (zeln_car -> Fcar etc.) the
    // Tier-0 emitter makes — t[0] = v is still pristine.
    try em.wf("bb_cfr_{d}:\n", .{start});
    const r = try em.frelocCallI64(idx, 1, t);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ r, t });
    try em.wif("br label %bb_cdone_{d}\n", .{start});

    // Merge: result is at t[0] either way; next instruction attaches here.
    try em.wf("bb_cdone_{d}:\n", .{start});
}

// ---- Tier-1 inline predicates (M3c). ------------------------------------
// For Bconsp/Bnot (IDX_CONSP/IDX_NULL), emit the FULL inline type test +
// Qt/Qnil select, mirroring the interpreter's own fast paths
// (bytecode.c:1071 `TOP = CONSP (TOP) ? Qt : Qnil`, 1083 `TOP = NILP
// (TOP) ? Qt : Qnil`).  CONSP/NILP are total pure tests (no type errors,
// no side effects, defined for EVERY Lisp_Object), so the inline IS the
// complete semantics — no fallback is needed and none exists.  Identity
// holds by construction:
//   * CONSP(v) = (v & 7) == 3 under USE_LSB_TAG (lisp.h:492,519; same
//     assumption as the M3b cons-slot inline, asserted at .zeln load).
//     Fconsp (data.c) = CONSP (x) ? Qt : Qnil — identical.
//   * NILP(v) = BASE_EQ(v, Qnil) = (v == 0) under USE_LSB_TAG
//     (lisp.h:374 lisp_h_Qnil 0; lisp.h:397 lisp_h_NILP BASE_EQ).
//     Fnull (data.c) = NILP (x) ? Qt : Qnil — identical.
//   * Qt is loaded from the fn's d_reloc synthesized-`t' slot
//     (em.qt_const_idx) — the live value, same mechanism gccjit uses for
//     its Qt relocs.  Qnil = 0 is baked directly.
// The freloc surface, IDX order, and .zeln layout are UNCHANGED (no ABI
// bump); the freloc shim call this replaces is simply never emitted.
fn emitUnaryPredicate(em: *Emitter, idx: u64) !void {
    const t = try em.loadTop();
    const v = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ v, t }); // TOP
    const pred: u32 = if (idx == IDX_CONSP) blk: {
        const m = em.fresh();
        try em.wif("%{d} = and i64 %{d}, {d}\n", .{ m, v, CONSP_MASK });
        const p = em.fresh();
        try em.wif("%{d} = icmp eq i64 %{d}, {d}\n", .{ p, m, CONSP_TAG });
        break :blk p;
    } else blk: {
        // IDX_NULL: NILP(v) = (v == 0) (Qnil = 0 under USE_LSB_TAG).
        const p = em.fresh();
        try em.wif("%{d} = icmp eq i64 %{d}, 0\n", .{ p, v });
        break :blk p;
    };
    // pred ? Qt : Qnil at t[0] (Qt = d_reloc[qt_const_idx], Qnil = 0).
    const qt = try em.loadConst(em.qt_const_idx);
    const res = em.fresh();
    try em.wif("%{d} = select i1 %{d}, i64 %{d}, i64 0\n", .{ res, pred, qt });
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ res, t });
}

// ---- Tier-1 fixnum-comparison inline fast path (M3c). -------------------
// For Bgtr/Blss/Bleq/Bgeq/Beqlsign (IDX_GTR/LSS/LEQ/GEQ/EQLSIGN), emit
// the inline FIXNUMP-guarded signed compare, falling back to the EXACT
// freloc shim call the Tier-0 emitter makes (zeln_gtr->Fgtr etc.) when
// either operand is a non-fixnum (float/bignum/marker).  This mirrors
// BOTH the interpreter's own fast path (bytecode.c:1256-1310: `if
// (FIXNUMP (v1) && FIXNUMP (v2)) TOP = XFIXNUM (v1) OP XFIXNUM (v2) ?
// Qt : Qnil`) AND arithcompare's fixnum-fixnum branch (data.c:2786-2790:
// i1 OP i2, with coerce_marker excluded because markers are never
// FIXNUMP).  For the common all-fixnum case it removes BOTH the 3-
// instruction freloc indirection AND the full Fgtr/Flss/arithcompare
// type-dispatch body, replacing them with a mask test + signed icmp +
// select.
//
// Identity holds by construction (gate #2 + zeln-diff enforce it):
//   * Inline path is taken ONLY when FIXNUMP(v1) && FIXNUMP(v2), producing
//     exactly arithcompare's fixnum-fixnum result for the op:
//       Bgtr  (Cmp_GT)             -> i1 >  i2
//       Blss  (Cmp_LT)             -> i1 <  i2
//       Bleq  (Cmp_LT|Cmp_EQ)      -> i1 <= i2
//       Bgeq  (Cmp_GT|Cmp_EQ)      -> i1 >= i2
//       Beqlsign (Cmp_EQ)          -> i1 == i2
//     == the interpreter's own inline result for the same case.
//   * Fallback path is the byte-identical freloc shim call, taken for
//     any non-fixnum operand (floats/bignums/markers go through
//     coerce_marker + full arithcompare — unchanged).  So inline+fallback
//     == the current freloc shim == the interpreter, for all inputs.
//   * USE_LSB_TAG assumptions are the same ones M3a makes and are
//     asserted at .zeln load; the freloc surface, IDX order, and .zeln
//     layout are UNCHANGED (no ABI bump).
// -------------------------------------------------------------------------
// Labels keyed on START (the opcode's byte offset, unique within a fn):
// bb_cmp_<s> (compare), bb_cfc_<s> (fallback), bb_cdn_<s> (merge).
fn emitBinaryCompare(em: *Emitter, idx: u64, start: u32) !void {
    // POP prefix — byte-identical to emitBinary/emitBinaryArith.
    const t = try em.loadTop();
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 -1\n", .{ np, t });
    try em.storeTop(np);
    // Load v1 = np[0], v2 = np[1] (both pristine for the fallback call).
    const v1 = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ v1, np });
    const v2slot = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 1\n", .{ v2slot, np });
    const v2 = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ v2, v2slot });
    // FIXNUMP(v) = (v & 3) == 2 (USE_LSB_TAG: Lisp_Int0 low 2 bits).
    const m1 = em.fresh();
    try em.wif("%{d} = and i64 %{d}, {d}\n", .{ m1, v1, FIXNUM_LSB_MASK });
    const f1 = em.fresh();
    try em.wif("%{d} = icmp eq i64 %{d}, {d}\n", .{ f1, m1, FIXNUM_LSB_TAG });
    const m2 = em.fresh();
    try em.wif("%{d} = and i64 %{d}, {d}\n", .{ m2, v2, FIXNUM_LSB_MASK });
    const f2 = em.fresh();
    try em.wif("%{d} = icmp eq i64 %{d}, {d}\n", .{ f2, m2, FIXNUM_LSB_TAG });
    const bothfix = em.fresh();
    try em.wif("%{d} = and i1 %{d}, %{d}\n", .{ bothfix, f1, f2 });
    // both-fixnum -> inline compare; else -> fallback (freloc call).
    const pmd = try em.profMDAlloc();
    defer em.gpa.free(pmd);
    try em.wif("br i1 %{d}, label %bb_cmp_{d}, label %bb_cfc_{d}{s}\n", .{ bothfix, start, start, pmd });

    // Inline compare block: decode operands, signed-compare, Qt/Qnil select.
    try em.wf("bb_cmp_{d}:\n", .{start});
    const a1 = em.fresh();
    try em.wif("%{d} = ashr i64 %{d}, {d}\n", .{ a1, v1, FIXNUM_SHIFT });
    const a2 = em.fresh();
    try em.wif("%{d} = ashr i64 %{d}, {d}\n", .{ a2, v2, FIXNUM_SHIFT });
    const cc: u32 = if (idx == IDX_GTR) blk: {
        const c = em.fresh();
        try em.wif("%{d} = icmp sgt i64 %{d}, %{d}\n", .{ c, a1, a2 });
        break :blk c;
    } else if (idx == IDX_LSS) blk: {
        const c = em.fresh();
        try em.wif("%{d} = icmp slt i64 %{d}, %{d}\n", .{ c, a1, a2 });
        break :blk c;
    } else if (idx == IDX_LEQ) blk: {
        const c = em.fresh();
        try em.wif("%{d} = icmp sle i64 %{d}, %{d}\n", .{ c, a1, a2 });
        break :blk c;
    } else if (idx == IDX_GEQ) blk: {
        const c = em.fresh();
        try em.wif("%{d} = icmp sge i64 %{d}, %{d}\n", .{ c, a1, a2 });
        break :blk c;
    } else blk: {
        // IDX_EQLSIGN: i1 == i2 (BASE_EQ on two fixnums).
        const c = em.fresh();
        try em.wif("%{d} = icmp eq i64 %{d}, %{d}\n", .{ c, a1, a2 });
        break :blk c;
    };
    const qt = try em.loadConst(em.qt_const_idx);
    const res = em.fresh();
    try em.wif("%{d} = select i1 %{d}, i64 %{d}, i64 0\n", .{ res, cc, qt });
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ res, np });
    try em.wif("br label %bb_cdn_{d}\n", .{start});

    // Fallback: byte-identical freloc shim call (zeln_gtr->Fgtr etc.) —
    // np[0]=v1, np[1]=v2 are still pristine.
    try em.wf("bb_cfc_{d}:\n", .{start});
    try emitFallbackCounter(em, start);
    const r = try em.frelocCallI64(idx, 2, np);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ r, np });
    try em.wif("br label %bb_cdn_{d}\n", .{start});

    // Merge: result is at np[0] either way; next instruction attaches here.
    try em.wf("bb_cdn_{d}:\n", .{start});
}

// Emit FIXNUM_OVERFLOW_P(res) = (res > MOST_POS) || (res < MOST_NEG) as an
// i1 (true => take the fallback).  Mirrors src/lisp.h FIXNUM_OVERFLOW_P and
// bytecode.c's `!FIXNUM_OVERFLOW_P(res)` gate on Bplus/Bdiff/Bmult.
fn emitFixnumRangeCheck(em: *Emitter, res: u32) !u32 {
    const hipos = em.fresh();
    try em.wif("%{d} = icmp sgt i64 %{d}, {d}\n", .{ hipos, res, MOST_POSITIVE_FIXNUM });
    const hineg = em.fresh();
    try em.wif("%{d} = icmp slt i64 %{d}, {d}\n", .{ hineg, res, MOST_NEGATIVE_FIXNUM });
    const ov = em.fresh();
    try em.wif("%{d} = or i1 %{d}, %{d}\n", .{ ov, hipos, hineg });
    return ov;
}

// Store make_fixnum(RES) = (RES << INTTYPEBITS) | Lisp_Int0 at PTR.
fn emitStoreMakeFixnum(em: *Emitter, res: u32, ptr: u32) !void {
    const shl = em.fresh();
    try em.wif("%{d} = shl i64 %{d}, {d}\n", .{ shl, res, FIXNUM_SHIFT });
    const mf = em.fresh();
    try em.wif("%{d} = or i64 %{d}, {d}\n", .{ mf, shl, FIXNUM_LSB_TAG });
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ mf, ptr });
}

// Blist3/Blist4/BlistN: DISCARD n-1; Flist(n, &newtop).  newtop[0..n-1]
// hold TOP + the n-1 discarded slots (stale-present), in order.
fn emitListN(em: *Emitter, idx: u64, n: u32) !void {
    const t = try em.loadTop();
    const di: i64 = -@as(i64, n - 1);
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 {d}\n", .{ np, t, di });
    try em.storeTop(np);
    const r = try em.frelocCallI64(idx, n, np);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ r, np });
}

// Bcall family.  Interpreter docall (bytecode.c:766): the call group on
// the stack is [fun, arg1..argN] with argN on top and fun at the BOTTOM.
// DISCARD(N) moves `top` down to fun; call_fun = TOP = fun; call_args =
// &TOP+1 = the stale arg slots above.  zeln_funcall(N+1, &fun) reads
// fun=[0], args=[1..N], mirroring that exactly; the result replaces fun's
// slot (net stack effect -N, matching Bcall).
fn emitCall(em: *Emitter, nargs: u32) !void {
    const t = try em.loadTop(); // t = argN (top of the group)
    const di: i64 = -@as(i64, nargs);
    const fp = em.fresh(); // fp = &fun = t - N
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 {d}\n", .{ fp, t, di });
    try em.storeTop(fp); // DISCARD N: top = fun
    const r = try em.frelocCallI64(IDX_FUNCALL, @as(u64, nargs) + 1, fp);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ r, fp }); // TOP = val
}

const CondSense = enum { eq_nil, eq_nonnil };

// Bgotoifnil / Bgotoifnonnil: POP v1; test NILP inline; branch.  The POP
// is unconditional (interpreter pops regardless).
//
// NILP(v) is inlined as `v == 0`: under USE_LSB_TAG, Qnil = 0
// (lisp.h:374 lisp_h_Qnil 0; lisp.h:397 lisp_h_NILP BASE_EQ(x, Qnil)),
// so the C shim zeln_isnil (compz.c:150, `return NILP (args[0]) ? 1 :
// 0`) is EXACTLY `v == 0`.  NILP is a total pure test, so this is a FULL
// inline (no fallback, no freloc indirection) replacing a 3-instruction
// freloc call + shim body on every conditional branch.  Identity holds
// by construction: the branch condition is bit-identical to the shim's.
fn emitCondPop(em: *Emitter, target: u32, fall_off: u32, sense: CondSense) !void {
    const t = try em.loadTop();
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 -1\n", .{ np, t }); // POP
    try em.storeTop(np);
    const v = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ v, t }); // popped v1 (still at t[0])
    const cond = em.fresh();
    switch (sense) {
        .eq_nil => try em.wif("%{d} = icmp eq i64 %{d}, 0\n", .{ cond, v }), // 1 = nil
        .eq_nonnil => try em.wif("%{d} = icmp ne i64 %{d}, 0\n", .{ cond, v }), // 0 = nonnil
    }
    try em.wif("br i1 %{d}, label %bb_{d}, label %bb_{d}\n", .{ cond, target, fall_off });
}

// Bgotoifnilelsepop / Bgotoifnonnilelsepop: test TOP in place (no pop);
// branch if sense matches; otherwise DISCARD(1) then fall through.  The
// discard happens only on the not-taken path, so it lands in its own block.
fn emitCondElsePop(em: *Emitter, start: u32, target: u32, fall_off: u32, sense: CondSense) !void {
    const t = try em.loadTop();
    const v = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ v, t }); // test TOP in place
    const cond = em.fresh();
    switch (sense) {
        .eq_nil => try em.wif("%{d} = icmp eq i64 %{d}, 0\n", .{ cond, v }),
        .eq_nonnil => try em.wif("%{d} = icmp ne i64 %{d}, 0\n", .{ cond, v }),
    }
    try em.wif("br i1 %{d}, label %bb_{d}, label %bb_fall_{d}\n", .{ cond, target, start });
    // Not-taken fallthrough block: discard TOS, then continue.
    try em.wf("bb_fall_{d}:\n", .{start});
    const ft = try em.loadTop();
    const fnp = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 -1\n", .{ fnp, ft });
    try em.storeTop(fnp);
    try em.wif("br label %bb_{d}\n", .{fall_off});
}

// =====================================================================
// M2 per-opcode IR fragments.
// =====================================================================

// Bvarref family: PUSH Fsymbol_value(vectorp[arg]).  The symbol's home slot
// in d_reloc_z[arg] IS the args base (the shim reads a[0] = sym).  Calling
// Fsymbol_value directly is result-identical to the interpreter's
// SYMBOL_PLAINVAL fast path (the fast path only short-circuits the call;
// Fsymbol_value returns the same value and signals void-variable the same).
fn emitVarref(em: *Emitter, const_idx: u64) !void {
    const cslot = em.fresh();
    try em.wif("%{d} = getelementptr inbounds [{d} x i64], ptr @{s}, i64 0, i64 {d}\n", .{ cslot, em.nconsts, em.d_reloc_global, const_idx });
    const r = try em.frelocCallI64(IDX_SYMBOL_VALUE, 1, cslot);
    const t = try em.loadTop();
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 1\n", .{ np, t });
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ r, np });
    try em.storeTop(np);
}

// Bvarset family: set_internal(vectorp[arg], POP).  POP the TOS, scatter
// [sym, val] into %zargs, call IDX_VARSET(2, &zargs); net stack effect -1.
fn emitVarset(em: *Emitter, const_idx: u64) !void {
    const t = try em.loadTop();
    const val = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ val, t }); // popped value
    const sym = try em.loadConst(const_idx);
    const z0 = try em.zargsSlot(0);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ sym, z0 });
    const z1 = try em.zargsSlot(1);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ val, z1 });
    const zbase = try em.zargsSlot(0);
    _ = try em.frelocCallI64(IDX_VARSET, 2, zbase);
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 -1\n", .{ np, t });
    try em.storeTop(np);
}

// Bvarbind family: specbind(vectorp[arg], POP).  Same shape as varset.
fn emitVarbind(em: *Emitter, const_idx: u64) !void {
    const t = try em.loadTop();
    const val = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ val, t });
    const sym = try em.loadConst(const_idx);
    const z0 = try em.zargsSlot(0);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ sym, z0 });
    const z1 = try em.zargsSlot(1);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ val, z1 });
    const zbase = try em.zargsSlot(0);
    _ = try em.frelocCallI64(IDX_VARBIND, 2, zbase);
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 -1\n", .{ np, t });
    try em.storeTop(np);
}

// Bunbind family: unbind_to(SPECPDL_INDEX()-arg, Qnil).  The count rides in
// nargs (the shim reads `n'); the args ptr is unused.
fn emitUnbind(em: *Emitter, count: u32) !void {
    const zbase = try em.zargsSlot(0);
    _ = try em.frelocCallI64(IDX_UNBIND, count, zbase);
}

// BdiscardN: pure stack op.  n=FETCH; if 0x80 set, top[-(n&0x7f)]=TOP first,
// then DISCARD(n&0x7f).  n is a compile-time constant, so the preserve
// store is emitted conditionally (no runtime branch).
fn emitDiscardN(em: *Emitter, n_byte: u32) !void {
    const n = n_byte & 0x7f;
    const preserve = (n_byte & 0x80) != 0;
    const t = try em.loadTop();
    if (preserve) {
        const tos = em.fresh();
        try em.wif("%{d} = load i64, ptr %{d}\n", .{ tos, t });
        const di: i64 = -@as(i64, n);
        const dst = em.fresh();
        try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 {d}\n", .{ dst, t, di });
        try em.wif("store i64 %{d}, ptr %{d}\n", .{ tos, dst });
    }
    const di2: i64 = -@as(i64, n);
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 {d}\n", .{ np, t, di2 });
    try em.storeTop(np);
}

// 0-arg PUSH primitives (Bpoint/Beolp/...): PUSH fn().  Shim ignores args.
fn emitPush0(em: *Emitter, idx: u64) !void {
    const zbase = try em.zargsSlot(0);
    const r = try em.frelocCallI64(idx, 0, zbase);
    const t = try em.loadTop();
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 1\n", .{ np, t });
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ r, np });
    try em.storeTop(np);
}

// No-arg, no-stack-effect (Bsave_excursion/Bsave_*/Bpophandler): call
// fn(0), discard result.  These push/pop the C specpdl (Tier 1).
fn emitNoArg(em: *Emitter, idx: u64) !void {
    const zbase = try em.zargsSlot(0);
    _ = try em.frelocCallI64(idx, 0, zbase);
}

// Bunwind_protect: POP handler; record_unwind_protect(bcall0|prog_ignore,
// handler).  POP one, call fn(1, &oldtop), discard; net stack effect -1.
fn emitUnaryPop(em: *Emitter, idx: u64) !void {
    const t = try em.loadTop();
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 -1\n", .{ np, t });
    try em.storeTop(np);
    _ = try em.frelocCallI64(idx, 1, t); // t[0] still holds the popped handler
}

// Bpushcatch / Bpushconditioncase (Tier 2).  POP the tag, call
// IDX_PUSHHANDLER (which push_handler's + returns the jmpbuf ptr), then call
// _setjmp ON THE JMPBUF DIRECTLY HERE (the native fn — so longjmp lands in
// this frame, whose alloca virtual stack survives).  0 -> guarded body (next
// insn); nonzero -> resume block: call IDX_RESUME (restores %top + PUSHes the
// caught value) then br to the handler block (FETCH2 dest).
fn emitPushHandler(em: *Emitter, type_raw: u64, target: u32, fall_off: u32) !void {
    // POP the tag.
    const t = try em.loadTop();
    const tag = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ tag, t });
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 -1\n", .{ np, t });
    try em.storeTop(np);
    // %zargs[0] = tag, [1] = type (raw 0/1), [2] = ptrtoint(%top.slot).
    const z0 = try em.zargsSlot(0);
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ tag, z0 });
    const z1 = try em.zargsSlot(1);
    try em.wif("store i64 {d}, ptr %{d}\n", .{ type_raw, z1 });
    const z2 = try em.zargsSlot(2);
    const tsi = em.fresh();
    try em.wif("%{d} = ptrtoint ptr %top.slot to i64\n", .{tsi});
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ tsi, z2 });
    const zbase = try em.zargsSlot(0);
    // push_handler + field setup; returns the sys_jmp_buf* as a raw i64.
    const jmpbuf_i64 = try em.frelocCallI64(IDX_PUSHHANDLER, 3, zbase);
    // _setjmp DIRECTLY in the native fn (NOT in the shim): the longjmp
    // resumes here, in this preserved frame.  inttoptr the raw i64 -> ptr.
    const jbptr = em.fresh();
    try em.wif("%{d} = inttoptr i64 %{d} to ptr\n", .{ jbptr, jmpbuf_i64 });
    const sj = em.fresh();
    try em.wif("%{d} = call i32 @_setjmp(ptr %{d})\n", .{ sj, jbptr });
    const cond = em.fresh();
    try em.wif("%{d} = icmp eq i32 %{d}, 0\n", .{ cond, sj });
    // 0 => guarded body; nonzero => resume block (a throw/signal was caught).
    // The resume label is emitted as its own basic block below.
    try em.wif("br i1 %{d}, label %bb_{d}, label %bb_resume_{d}\n", .{ cond, fall_off, fall_off });
    // Resume block: a longjmp was caught.  IDX_RESUME restores %top to the
    // pushtime value and PUSHes h->val (the caught value), so the handler
    // block (FETCH2 dest) just continues with caught value at TOS.
    try em.wf("bb_resume_{d}:\n", .{fall_off});
    const rz0 = try em.zargsSlot(0);
    const rtsi = em.fresh();
    try em.wif("%{d} = ptrtoint ptr %top.slot to i64\n", .{rtsi});
    try em.wif("store i64 %{d}, ptr %{d}\n", .{ rtsi, rz0 });
    const rzbase = try em.zargsSlot(0);
    _ = try em.frelocCallI64(IDX_RESUME, 1, rzbase);
    try em.wif("br label %bb_{d}\n", .{target});
}

// =====================================================================
// Shared helpers.
// =====================================================================

// Append `src` to `out` as an LLVM c"..." literal body (callers wrap
// with c"..."). Inside a c"..." literal, printable ASCII (0x20..0x7e)
// is taken literally EXCEPT `"` and `\`, which — like every
// non-printable byte — must be written as a `\xx` hex escape. (LLVM's
// c"..." does NOT support `\"` or `\\`; only `\xx`.)
fn appendCStringLiteral(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    src: []const u8,
) !void {
    for (src) |b| {
        if (b >= 0x20 and b < 0x7f and b != '"' and b != '\\') {
            try out.append(gpa, b);
        } else {
            try out.print(gpa, "\\{x:0>2}", .{b});
        }
    }
}

// Helper: allocate a T slice of `n` from the allocator used throughout
// this tool (std.heap.smp_allocator in main()).
fn gpaAlloc(comptime T: type, n: u64) ![]T {
    return std.heap.smp_allocator.alloc(T, @intCast(n));
}
