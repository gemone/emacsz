//! Audits the selected but unlinked R8 adapter linkage record.

const std = @import("std");
const proto_ui = @import("proto_ui");

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    var args = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer args.deinit();
    _ = args.next();
    const manifest_path = args.next() orelse return error.MissingManifestArg;

    const actual = try cwd.readFileAlloc(io, manifest_path, gpa, .limited(64 * 1024));
    defer gpa.free(actual);
    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(gpa);
    try proto_ui.r8_adapter_linkage.writeManifest(gpa, &expected);
    if (!std.mem.eql(u8, actual, expected.items)) {
        std.debug.print("r8-adapter-linkage gate: artifact mismatch\n", .{});
        return error.InvalidAdapterLinkageArtifact;
    }
    if (proto_ui.r8_adapter_linkage.validateState()) |problem| {
        std.debug.print("r8-adapter-linkage gate: {s}\n", .{problem});
        return error.InvalidAdapterLinkageState;
    }
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-r8-adapter-linkage\",\"status\":\"prepared_not_linked\",\"selected\":true,\"linked\":false,\"registered\":false,\"runtime_available\":false,\"result\":\"pass\"}}\n",
        .{},
    );
}
