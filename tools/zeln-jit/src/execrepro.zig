const std = @import("std");
const builtin = @import("builtin");
const jit = @import("jit.zig");
const compiler = @import("compiler.zig");

// Execute the EXACT 24-byte closure that AVs inside temacs on Windows
// (trace: const[0], stack_ref1, const[1], Bgeq, gotoifnil... Bcall1, Breturn)
// with realistic freloc shims: each takes (n, args) and returns a fixnum-ish
// word; FUNCALL returns args[0].  If this passes in-process but the temacs
// build AVs, the defect is in the temacs linkage (not the emitter).
test "exec crash repro: exact 24-byte closure with call" {
    var arena = try jit.ExecArena.allocate(4 * 1024 * 1024);
    defer arena.deinit();

    const Shims = struct {
        fn geq(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            return if (args[0] == args[1]) 0x18 else 0x0; // fixnum 3 or nil-ish
        }
        fn leq(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            return if (args[0] == args[1]) 0x18 else 0x0;
        }
        fn diff(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            return args[0] -% args[1];
        }
        fn plus(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            return args[0] +% args[1];
        }
        fn funcall(n: i64, args: [*]const u64) callconv(.c) u64 {
            _ = n;
            return args[0]; // "call the function": return its own word
        }
    };
    // IDX order: PLUS=3 MINUS=4 TIMES=5 ... EQLSIGN=11 GTR=12 LSS=13
    // LEQ=14 GEQ=15 ... FUNCALL=1
    var table: [64]*const anyopaque = undefined;
    for (&table) |*t| t.* = &Shims.funcall;
    table[3] = &Shims.plus;
    table[4] = &Shims.diff;
    table[14] = &Shims.leq;
    table[15] = &Shims.geq;
    table[1] = &Shims.funcall;
    var freloc_base: *const anyopaque = &table;
    const freloc_slot: *const *const anyopaque = &freloc_base;

    const opcodes = [_]u8{
        0xC0, // const[0]
        0x01, // stack_ref1
        0xC1, // const[1]
        89, // Bgeq
        0x83, 21, 0, // Bgotoifnil 21
        0x01, // stack_ref1
        0xC2, // const[2]
        88, // Bleq
        0x83, 21, 0, // Bgotoifnil 21
        0x01, // stack_ref1
        0xC1, // const[1]
        90, // Bdiff
        0xC3, // const[3]
        92, // Bplus
        0x82, 22, 0, // Bgoto 22
        0x01, // stack_ref1 (target 21)
        33, // Bcall1 (target 22)
        135, // Breturn
    };
    var consts = [_]u64{ 0x30, 0x30, 0x30, 0x30 };
    const res = try compiler.compile(&arena, &opcodes, 8, freloc_slot, &consts, 1);
    try std.testing.expect(res.rejected == null);
    var args = [_]u64{0x30};
    const got = res.entry(1, &args);
    std.debug.print("executed OK, result={x}\n", .{got});
}