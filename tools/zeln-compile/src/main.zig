//! zeln-compile: the native-compilation tool for the HAVE_NATIVE_COMP_ZIG
//! path (produces `.zeln` from a zunit). It is a separate process per the
//! C<->Zig boundary (plan section 4.1): temacs serializes a zunit; this
//! tool parses it, emits LLVM IR (`.ll`), and drives `zig cc -shared` to
//! produce the `.zeln`.
//!
//! M0 spike (plan section 6): a TIER-0 emitter. It validates the zunit
//! contract (magic + ABI version) and emits a FIXED `.ll` for the ONE
//! hardcoded spike fn — it does NOT translate the zunit's bytecode
//! opcodes (that is M1's opcode-table codegen). This is the minimal
//! artifact that proves the zunit -> .ll -> .zeln -> load -> call chain.
//! The production (Tier-1) emitter lands in M3.
//!
//! Usage: zeln-compile <zunit-path> <manifest-path> <output-zeln-path>
//! Reads <zunit-path> (binary) + <manifest-path> (ASCII), writes a .ll
//! next to the output, then runs `zig cc -shared` to produce the .zeln.

const std = @import("std");

// "ZUNT" little-endian. Written by src/compz.c's serializer.
const ZUNIT_MAGIC: u32 = 0x5A554E54;
// ZELN spike ABI version (the zabi_version byte the zunit carries and
// this tool requires). Mirrors ZELN_SPIKE_ABI in the plan; bumped in
// lockstep with the zunit format.
const ZABI_VERSION: u8 = 1;

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

    const zunit = try cwd.readFileAlloc(io, zunit_path, gpa, .limited(4 * 1024 * 1024));
    defer gpa.free(zunit);
    const consts = try parseZunit(zunit);
    defer gpa.free(consts);

    const manifest = try cwd.readFileAlloc(io, manifest_path, gpa, .limited(4096));
    defer gpa.free(manifest);
    const abi_hash = parseManifestHash(manifest) orelse return error.BadManifest;

    // Emit the .ll next to the output .zeln (sibling file).
    const ll_path = try std.fmt.allocPrint(gpa, "{s}.ll", .{out_zeln_path});
    defer gpa.free(ll_path);
    const ll_body = try emitLLVMIR(gpa, consts, abi_hash);
    defer gpa.free(ll_body);
    try cwd.writeFile(io, .{ .sub_path = ll_path, .data = ll_body });

    // Drive the link: `zig cc -shared -fPIC -O2 -fvisibility=default
    // <spike>.ll -o <name>.zeln`. -fvisibility=default ensures the
    // `zeln_entry` symbol is exported in the .so's dynamic symbol table
    // so the loader's dlsym finds it (mirrors how .eln exports its entry).
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

// A parsed zunit constant: a tag (0=nil 1=fixnum 2=symbol 3=string)
// plus its read-syntax payload. The Zig tool never interprets Lisp —
// it only carries the read-syntax bytes verbatim into the .ll blob.
const Const = struct {
    tag: u8,
    data: []const u8,
};

// Parse + validate the zunit header and constants. Returns the slice of
// Const payloads (read-syntax strings). Opcodes are validated to be
// present (format parity) but NOT translated — the Tier-0 emitter emits
// a fixed .ll regardless (sanctioned by plan section 6).
fn parseZunit(zunit: []const u8) ![]Const {
    if (zunit.len < 10) return error.ZunitTooShort;
    const magic = std.mem.readInt(u32, zunit[0..4], .little);
    if (magic != ZUNIT_MAGIC) {
        std.debug.print("zeln-compile: bad zunit magic 0x{X} (want 0x{X})\n", .{ magic, ZUNIT_MAGIC });
        return error.BadMagic;
    }
    if (zunit[4] != ZABI_VERSION) {
        std.debug.print("zeln-compile: bad zabi_version {d} (want {d})\n", .{ zunit[4], ZABI_VERSION });
        return error.BadAbiVersion;
    }
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

// The manifest is `Z1\n<message(1 . many)>\n<8-hex>\n`. Return the 8-hex
// hash line (line 3). This is baked verbatim into the .zeln as
// freloc_hash_z; the loader compares it against Vzeln_abi_hash. Single
// source of truth: compz.c computes; Zig only embeds.
fn parseManifestHash(manifest: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, manifest, '\n');
    _ = it.next(); // Z1
    _ = it.next(); // sig
    const hash_line = it.next() orelse return null;
    if (hash_line.len < 8) return null;
    return hash_line[0..8];
}

// Emit the fixed Tier-0 .ll for the spike fn. The native body loads
// freloc[IDX_MESSAGE] (= &Fmessage, patched by the loader), calls it
// once with d_reloc_z[0] (the string "zeln-spike alive") as the sole
// argument, then returns d_reloc_z[1] (the fixnum 42). The .ll never
// encodes Lisp_Object tag bits: every value is loaded as a raw i64 from
// the loader-filled d_reloc_z, so USE_LSB_TAG / INTTYPEBITS never leak
// into the IR.
fn emitLLVMIR(gpa: std.mem.Allocator, consts: []Const, abi_hash: []const u8) ![]u8 {
    // Build the d_reloc read-syntax blob: a vector of the const
    // payloads, `[<c0> <c1> ...]`. The loader Freads this once into a
    // vector and scatters AREF into d_reloc_z[0..n].
    var blob: std.ArrayList(u8) = .empty;
    defer blob.deinit(gpa);
    try blob.append(gpa, '[');
    for (consts, 0..) |c, i| {
        if (i > 0) try blob.append(gpa, ' ');
        try blob.appendSlice(gpa, c.data);
    }
    try blob.append(gpa, ']');
    const blob_bytes = blob.items;

    // LLVM c"..." literals escape non-printable / `"` / `\` as \xx.
    var blob_lit: std.ArrayList(u8) = .empty;
    defer blob_lit.deinit(gpa);
    try appendCStringLiteral(gpa, &blob_lit, blob_bytes);

    var hash_lit: std.ArrayList(u8) = .empty;
    defer hash_lit.deinit(gpa);
    try appendCStringLiteral(gpa, &hash_lit, abi_hash);
    // The freloc_hash_z symbol is 8 hex chars + NUL.
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
        \\; src/compz.h zeln_entry_t field-for-field (no padding: all
        \\; 8-byte fields on x86-64).
        \\
        \\; --- freloc link-table slot (loader writes the live
        \\;     zeln_freloc.link_table base here; native code derefs
        \\;     base -> base[0] -> &Fmessage).  Mirror comp.c:5295/5311.  ---
        \\@freloc_link_table_z = internal global ptr null
        \\
        \\; --- data reloc array: loader Freads consts into [0], [1].  ---
        \\@d_reloc_z = internal global [2 x i64] zeroinitializer
        \\
        \\; --- data reloc read-syntax blob (a vector; loader Freads +
        \\;     AREFs).  Mirror comp.c load_static_obj (DATA_RELOC_SYM).  ---
        \\
    );
    try A.addf(&out, gpa, "@d_reloc_z_blob = internal constant {{ i64, [{d} x i8] }} {{ i64 {d}, [{d} x i8] c\"{s}\" }}\n\n", .{ blob_bytes.len, blob_bytes.len, blob_bytes.len, blob_lit.items });
    try A.add(&out, gpa,
        \\; --- freloc hash (8 hex + NUL), baked verbatim from the
        \\;     manifest.  Loader compares vs Vzeln_abi_hash.  ---
        \\
    );
    try A.addf(&out, gpa, "@freloc_hash_z_data = internal constant [9 x i8] c\"{s}\"\n\n", .{hash_lit.items});
    try A.add(&out, gpa,
        \\; --- the entry struct (zeln_entry_t in compz.h):
        \\;       { native_fn, freloc_link_table_z, freloc_hash_z,
        \\;         d_reloc_z, n_d_reloc, d_reloc_blob }  ---
        \\@zeln_entry_global = internal global { ptr, ptr, ptr, ptr, i64, ptr } {
        \\  ptr @zeln_spike_native,
        \\  ptr @freloc_link_table_z,
        \\  ptr @freloc_hash_z_data,
        \\  ptr @d_reloc_z,
        \\  i64 2,
        \\  ptr @d_reloc_z_blob
        \\}
        \\
        \\; The native body of the spike fn.  Calls Fmessage once with
        \\; d_reloc_z[0] (the string), discards the result, then returns
        \\; d_reloc_z[1] (the fixnum 42).  The Fmessage call uses the
        \\; Emacs MANY calling convention (i64, ptr) -> i64, matching
        \\; struct Lisp_Subr's aMANY slot — reached purely through the
        \\; freloc pointer, so no extern symbol / -rdynamic is needed.
        \\define i64 @zeln_spike_native() {
        \\entry:
        \\  %lt = load ptr, ptr @freloc_link_table_z
        \\  %fn = load ptr, ptr %lt
        \\  %msgret = call i64 %fn(i64 1, ptr @d_reloc_z)
        \\  %rv = load i64, ptr getelementptr inbounds ([2 x i64], ptr @d_reloc_z, i64 0, i64 1)
        \\  ret i64 %rv
        \\}
        \\
        \\; The exported entry: loader resolves it via dlsym(handle,
        \\; "zeln_entry") and calls it to get the zeln_entry_t*.
        \\; -fvisibility=default on the `zig cc -shared` line exports it.
        \\define dso_local ptr @zeln_entry() {
        \\entry:
        \\  ret ptr @zeln_entry_global
        \\}
        \\
    );

    return out.toOwnedSlice(gpa);
}

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

// Helper: allocate a T slice of `n` from the page allocator used
// throughout this tool (std.heap.smp_allocator). Keeps the per-call
// allocator uniform with main().
fn gpaAlloc(comptime T: type, n: usize) ![]T {
    return std.heap.smp_allocator.alloc(T, n);
}
