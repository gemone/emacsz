//! Audits the honest planned state of the PGTK-to-Proto parity manifest.

const std = @import("std");
const proto_ui = @import("proto_ui");

fn emitPlanned() void {
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-pgtk-parity-plan\",\"plan\":\"planned\",\"parity\":\"not_implemented\",\"pgtk_runtime_fallback\":false,\"tty_runtime_fallback\":false}}\n",
        .{},
    );
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    var args = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer args.deinit();
    _ = args.next();

    const manifest_path = args.next() orelse return error.MissingManifestArg;
    const actual = try cwd.readFileAlloc(io, manifest_path, gpa, .limited(1024 * 1024));
    defer gpa.free(actual);

    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(gpa);
    try proto_ui.pgtk_parity.writeManifest(gpa, &expected);
    if (!std.mem.eql(u8, actual, expected.items)) {
        emitPlanned();
        std.debug.print("pgtk-parity-plan gate: artifact mismatch\n", .{});
        return error.InvalidParityPlanArtifact;
    }
    if (proto_ui.pgtk_parity.validateState()) |problem| {
        emitPlanned();
        std.debug.print("pgtk-parity-plan gate: {s}\n", .{problem});
        return error.InvalidParityPlanState;
    }
    emitPlanned();
}
