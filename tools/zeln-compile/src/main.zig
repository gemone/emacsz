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
const SURFACE: u64 = 33;

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

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
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
        ll_body = emitM1LLVM(gpa, unit, abi_hash) catch |err| {
            std.debug.print("zeln-compile: M1 emit failed: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
    } else {
        std.debug.print("zeln-compile: unsupported zabi_version {d} (want 1 or 2)\n", .{zabi});
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
    const cc_argv = [_][]const u8{
        "zig",       "cc",          "-shared",   "-fPIC",
        "-O2",       "-fvisibility=default", ll_path, "-o",
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
        \\@zeln_entry_global = internal global { ptr, ptr, ptr, ptr, i64, ptr } {
        \\  ptr @zeln_spike_native,
        \\  ptr @freloc_link_table_z,
        \\  ptr @freloc_hash_z_data,
        \\  ptr @d_reloc_z,
        \\  i64 2,
        \\  ptr @d_reloc_z_blob
        \\}
        \\
        \\; Spike native body (MANY convention).  INTERNAL linkage so it does
        \\; not interpose across multiple concurrently loaded .zeln (dynlib_open
        \\; uses RTLD_GLOBAL).  Only @zeln_entry is exported.
        \\define internal i64 @zeln_spike_native(i64 %nargs, ptr %args) {
        \\entry:
        \\  %lt = load ptr, ptr @freloc_link_table_z
        \\  %slot = getelementptr inbounds [33 x ptr], ptr %lt, i64 0, i64 2
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

// =====================================================================
// The M1 Tier-0 emitter.
// =====================================================================
const Emitter = struct {
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    next_reg: u32 = 1, // LLVM temporaries start at %1 (params occupy %0-ish names; we use numeric %N)

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

    // load %top.slot -> a fresh ptr register; returns the reg number.
    fn loadTop(self: *Emitter) !u32 {
        const r = self.fresh();
        try self.wif("%{d} = load ptr, ptr %top.slot\n", .{r});
        return r;
    }
    fn storeTop(self: *Emitter, reg: u32) !void {
        try self.wif("store ptr %{d}, ptr %top.slot\n", .{reg});
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

fn emitM1LLVM(gpa: std.mem.Allocator, unit: M1Unit, abi_hash: []const u8) ![]u8 {
    const opcodes = unit.opcodes;
    if (opcodes.len == 0) return error.EmptyBytecode;
    if (unit.stack_depth > 0xFFFE) return error.StackDepthTooLarge;
    // maxdepth+2: +1 for the pre-base slot (so `top = frame_base - 1` stays
    // inbounds), +1 because interpreter guarantees <=maxdepth live values.
    const stack_slots: u64 = @as(u64, unit.stack_depth) + 2;

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
    // Validate every branch target lands on an instruction boundary
    // (bytecomp guarantees this; reject malformed zunits defensively) and
    // record block starts at each target + each branch/return fallthrough.
    for (instrs.items) |ins| {
        switch (ins.op) {
            .goto_, .goto_if_nil, .goto_if_nonnil, .goto_if_nil_else_pop, .goto_if_nonnil_else_pop => {
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

    // ---- Build the d_reloc read-syntax blob: `[<c0> <c1> ...]`. ----
    var blob: std.ArrayList(u8) = .empty;
    defer blob.deinit(gpa);
    try blob.append(gpa, '[');
    for (unit.consts, 0..) |c, i| {
        if (i > 0) try blob.append(gpa, ' ');
        try blob.appendSlice(gpa, c);
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

    // ---- Emit. ----
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    var em = Emitter{ .gpa = gpa, .out = &out };

    try em.w("; zeln-m1.ll — Tier-0 emission of an M1 compiled closure.\n");
    try em.w("; Generated by tools/zeln-compile from the zabi=2 zunit.  Every\n");
    try em.w("; opcode is decoded at COMPILE time (no runtime fetch/dispatch);\n");
    try em.w("; branch targets become LLVM basic blocks.  The virtual stack is an\n");
    try em.w("; alloca (C stack memory -> conservatively GC-rooted by mark_c_stack,\n");
    try em.w("; the same guarantee gccjit's .eln relies on).  The IR never computes\n");
    try em.w("; Lisp_Object tag bits: every value is a raw i64 from loader-filled\n");
    try em.w("; slots, so USE_LSB_TAG never leaks into IR.\n\n");

    try em.w("@freloc_link_table_z = internal global ptr null\n");
    try em.wf("@d_reloc_z = internal global [{d} x i64] zeroinitializer\n\n", .{unit.consts.len});
    try em.wf("@d_reloc_z_blob = internal constant {{ i64, [{d} x i8] }} {{ i64 {d}, [{d} x i8] c\"{s}\" }}\n\n", .{ blob_bytes.len, blob_bytes.len, blob_bytes.len, blob_lit.items });
    try em.wf("@freloc_hash_z_data = internal constant [9 x i8] c\"{s}\"\n\n", .{hash_lit.items});

    try em.w("@zeln_entry_global = internal global { ptr, ptr, ptr, ptr, i64, ptr } {\n");
    try em.w("  ptr @zeln_m1_native,\n");
    try em.w("  ptr @freloc_link_table_z,\n");
    try em.w("  ptr @freloc_hash_z_data,\n");
    try em.w("  ptr @d_reloc_z,\n");
    try em.wf("  i64 {d},\n", .{unit.consts.len});
    try em.w("  ptr @d_reloc_z_blob\n}\n\n");

    // Native fn: MANY convention `i64 (i64 %nargs, ptr %args)`.  INTERNAL
    // linkage so the symbol does not interpose across multiple concurrently
    // loaded .zeln (dynlib_open uses RTLD_GLOBAL): each .zeln's
    // zeln_entry_global resolves to ITS OWN @zeln_m1_native at link time.
    // Only @zeln_entry is exported (the loader's dlsym target).
    try em.w("define internal i64 @zeln_m1_native(i64 %nargs, ptr %args) {\n");
    try em.w("entry:\n");
    // Virtual stack alloca + top.slot.
    try em.wif("%stack = alloca [{d} x i64], align 8\n", .{stack_slots});
    try em.wif("%stackbase = getelementptr inbounds [{d} x i64], ptr %stack, i64 0, i64 1\n", .{stack_slots});
    try em.w("  %top.slot = alloca ptr, align 8\n");
    // Prologue: zeln_setup_args(args_template, nargs, args, stackbase) -> top.
    const rlt = em.fresh();
    try em.wif("%{d} = load ptr, ptr @freloc_link_table_z\n", .{rlt});
    const rslot = em.fresh();
    try em.wif("%{d} = getelementptr inbounds [{d} x ptr], ptr %{d}, i64 0, i64 {d}\n", .{ rslot, SURFACE, rlt, IDX_SETUP_ARGS });
    const rfn = em.fresh();
    try em.wif("%{d} = load ptr, ptr %{d}\n", .{ rfn, rslot });
    const rtop0 = em.fresh();
    try em.wif("%{d} = call ptr %{d}(i64 {d}, i64 %nargs, ptr %args, ptr %stackbase)\n", .{ rtop0, rfn, unit.args_template });
    try em.wif("store ptr %{d}, ptr %top.slot\n", .{rtop0});
    try em.wf("  br label %bb_{d}\n", .{0});

    // ---- Pass 2: per-opcode emission. ----
    var block_open: bool = false;
    for (instrs.items) |ins| {
        // Open a basic block at every block start. If the prior block is
        // still open (straight-line fallthrough into a label), close it with
        // an explicit `br` to this label first.
        if (is_block_start[ins.start]) {
            if (block_open)
                try em.wf("  br label %bb_{d}\n", .{ins.start});
            try em.wf("bb_{d}:\n", .{ins.start});
            block_open = true;
        }

        switch (ins.op) {
            .constant => try emitConstant(&em, unit.consts.len, ins.idx),
            .stack_ref => try emitStackRef(&em, ins.imm),
            .dup => try emitDup(&em),
            .discard => try emitDiscard(&em),
            .stack_set => try emitStackSet(&em, ins.imm),
            .ret => {
                try emitReturn(&em);
                block_open = false;
            },
            .unary => try emitUnary(&em, ins.idx),
            .binary => try emitBinary(&em, ins.idx),
            .listn => try emitListN(&em, ins.idx, ins.imm),
            .call => try emitCall(&em, ins.imm),
            .goto_ => {
                try em.wf("  br label %bb_{d}\n", .{ins.target});
                block_open = false;
            },
            .goto_if_nil => {
                try emitCondPop(&em, ins.target, ins.end, .eq_nil);
                block_open = false;
            },
            .goto_if_nonnil => {
                try emitCondPop(&em, ins.target, ins.end, .eq_nonnil);
                block_open = false;
            },
            .goto_if_nil_else_pop => {
                try emitCondElsePop(&em, ins.start, ins.target, ins.end, .eq_nil);
                block_open = false;
            },
            .goto_if_nonnil_else_pop => {
                try emitCondElsePop(&em, ins.start, ins.target, ins.end, .eq_nonnil);
                block_open = false;
            },
        }
    }

    // If the final block fell through without a terminator (bytecomp always
    // ends lexical closures with Breturn, so this is defensive), close it.
    if (block_open) {
        try em.w("  ret i64 0\n");
    }

    try em.w("}\n\n");
    try em.w("define dso_local ptr @zeln_entry() {\n");
    try em.w("entry:\n");
    try em.w("  ret ptr @zeln_entry_global\n");
    try em.w("}\n");

    return out.toOwnedSlice(gpa);
}

// ---- Per-opcode IR fragments.  Each assumes a block is currently open
//      and %top.slot holds the current `top`; PUSH/POP mirror the
//      interpreter exactly (`*++top = x`; bytecode.c:283).  All values are
//      raw i64 Lisp_Objects; tag bits are never computed in IR. ----

// Bconstant: PUSH d_reloc_z[idx].
fn emitConstant(em: *Emitter, nconsts: usize, idx: u64) !void {
    const t = try em.loadTop();
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 1\n", .{ np, t });
    const cslot = em.fresh();
    try em.wif("%{d} = getelementptr inbounds [{d} x i64], ptr @d_reloc_z, i64 0, i64 {d}\n", .{ cslot, nconsts, idx });
    const cval = em.fresh();
    try em.wif("%{d} = load i64, ptr %{d}\n", .{ cval, cslot });
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

// Bgotoifnil / Bgotoifnonnil: POP v1; test via zeln_isnil (returns raw 0/1);
// branch.  The POP is unconditional (interpreter pops regardless).
fn emitCondPop(em: *Emitter, target: u32, fall_off: u32, sense: CondSense) !void {
    const t = try em.loadTop();
    const np = em.fresh();
    try em.wif("%{d} = getelementptr inbounds i64, ptr %{d}, i64 -1\n", .{ np, t }); // POP
    try em.storeTop(np);
    const r = try em.frelocCallI64(IDX_NILP, 1, t); // test popped v1 (still at t[0])
    const cond = em.fresh();
    switch (sense) {
        .eq_nil => try em.wif("%{d} = icmp eq i64 %{d}, 1\n", .{ cond, r }), // 1 = nil
        .eq_nonnil => try em.wif("%{d} = icmp eq i64 %{d}, 0\n", .{ cond, r }), // 0 = nonnil
    }
    try em.wif("br i1 %{d}, label %bb_{d}, label %bb_{d}\n", .{ cond, target, fall_off });
}

// Bgotoifnilelsepop / Bgotoifnonnilelsepop: test TOP in place (no pop);
// branch if sense matches; otherwise DISCARD(1) then fall through.  The
// discard happens only on the not-taken path, so it lands in its own block.
fn emitCondElsePop(em: *Emitter, start: u32, target: u32, fall_off: u32, sense: CondSense) !void {
    const t = try em.loadTop();
    const r = try em.frelocCallI64(IDX_NILP, 1, t); // test TOP in place
    const cond = em.fresh();
    switch (sense) {
        .eq_nil => try em.wif("%{d} = icmp eq i64 %{d}, 1\n", .{ cond, r }),
        .eq_nonnil => try em.wif("%{d} = icmp eq i64 %{d}, 0\n", .{ cond, r }),
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
