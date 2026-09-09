//! Audits the R7 packet and verifies its generated input provenance.

const std = @import("std");
const proto_ui = @import("proto_ui");

fn emitPending() void {
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-r7-review-packet\",\"packet\":\"ready_for_review\",\"approved\":false,\"registered\":false,\"runtime_available\":false,\"activation_allowed\":false,\"decision\":\"pending\",\"reason\":\"{s}\"}}\n",
        .{proto_ui.r7_review_packet.reason_code},
    );
}

fn writeExpectedInput(
    gpa: std.mem.Allocator,
    kind: proto_ui.r7_review_packet.InputKind,
    out: *std.ArrayList(u8),
) !void {
    switch (kind) {
        .proposal => try proto_ui.r7_proposal.writeProposal(gpa, out),
        .contract => try proto_ui.host_contract.writeContract(gpa, out),
        .adapter_selection => try proto_ui.host_adapter.writeManifest(gpa, out),
        .activation => try proto_ui.runtime_activation.writeManifest(gpa, out),
        .readiness => try proto_ui.r8_readiness.writeManifest(gpa, out),
    }
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    var args = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer args.deinit();
    _ = args.next();

    const packet_path = args.next() orelse return error.MissingPacketArg;
    var paths: [proto_ui.r7_review_packet.review_inputs.len][]const u8 = undefined;
    for (&paths) |*path| {
        path.* = args.next() orelse return error.MissingInputArtifactArg;
    }

    const actual = try cwd.readFileAlloc(io, packet_path, gpa, .limited(64 * 1024));
    defer gpa.free(actual);

    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(gpa);
    try proto_ui.r7_review_packet.writePacket(gpa, &expected);
    if (!std.mem.eql(u8, actual, expected.items)) {
        emitPending();
        std.debug.print("r7-review-packet gate: artifact mismatch\n", .{});
        return error.InvalidR7ReviewPacketArtifact;
    }
    if (proto_ui.r7_review_packet.validateState()) |problem| {
        emitPending();
        std.debug.print("r7-review-packet gate: {s}\n", .{problem});
        return error.InvalidR7ReviewPacketState;
    }

    for (proto_ui.r7_review_packet.review_inputs, paths) |input, path| {
        const artifact = try cwd.readFileAlloc(io, path, gpa, .limited(64 * 1024));
        defer gpa.free(artifact);
        var source_bytes: std.ArrayList(u8) = .empty;
        defer source_bytes.deinit(gpa);
        try writeExpectedInput(gpa, input.kind, &source_bytes);
        if (!std.mem.eql(u8, artifact, source_bytes.items)) {
            emitPending();
            std.debug.print(
                "r7-review-packet gate: provenance mismatch for {s}\n",
                .{input.name},
            );
            return error.InvalidR7ReviewPacketProvenance;
        }
    }

    emitPending();
}
