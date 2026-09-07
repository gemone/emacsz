//! Audits deterministic implementation coverage for every assigned EUP ID.

const std = @import("std");
const proto_ui = @import("proto_ui");

fn emitCoverage() void {
    const counts = proto_ui.protocol_coverage.counters();
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-protocol-coverage\",\"total\":{d},\"implemented_codec\":{d},\"partial\":{d},\"planned\":{d},\"reserved_diagnostic\":{d},\"result\":\"pass\"}}\n",
        .{ counts.total, counts.implemented_codec, counts.partial, counts.planned, counts.reserved_diagnostic },
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
    try proto_ui.protocol_coverage.writeManifest(gpa, &expected);
    if (!std.mem.eql(u8, actual, expected.items)) {
        emitCoverage();
        std.debug.print("protocol-coverage gate: manifest mismatch\n", .{});
        return error.InvalidProtocolCoverageArtifact;
    }
    if (proto_ui.protocol_coverage.validateState()) |problem| {
        emitCoverage();
        std.debug.print("protocol-coverage gate: {s}\n", .{problem});
        return error.InvalidProtocolCoverageState;
    }
    emitCoverage();
}
