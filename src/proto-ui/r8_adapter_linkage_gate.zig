//! Audits the R8 adapter linkage record for the selected build state.

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
    var runtime_linking = false;
    while (args.next()) |argument| {
        if (std.mem.eql(u8, argument, "--runtime-linking=true")) {
            runtime_linking = true;
        } else if (std.mem.eql(u8, argument, "--runtime-linking=false")) {
            runtime_linking = false;
        } else return error.UnknownGateArgument;
    }
    const state = proto_ui.r8_adapter_linkage.linkedState(runtime_linking);

    const actual = try cwd.readFileAlloc(io, manifest_path, gpa, .limited(64 * 1024));
    defer gpa.free(actual);
    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(gpa);
    try proto_ui.r8_adapter_linkage.writeLinkedManifest(gpa, &expected, runtime_linking);
    if (!std.mem.eql(u8, actual, expected.items)) {
        std.debug.print("r8-adapter-linkage gate: artifact mismatch\n", .{});
        return error.InvalidAdapterLinkageArtifact;
    }
    if (proto_ui.r8_adapter_linkage.validateLinkedState(runtime_linking)) |problem| {
        std.debug.print("r8-adapter-linkage gate: {s}\n", .{problem});
        return error.InvalidAdapterLinkageState;
    }
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-r8-adapter-linkage\",\"status\":\"{s}\",\"runtime_linking\":{},\"selected\":true,\"linked\":{},\"registered\":false,\"runtime_available\":false,\"result\":\"pass\"}}\n",
        .{ state.status, runtime_linking, state.linked_into_emacs },
    );
}
