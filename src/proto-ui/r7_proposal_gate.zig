//! Audits the approved R7 proposal and enforces its fail-closed runtime boundary.

const std = @import("std");
const proto_ui = @import("proto_ui");

fn emitApproved() void {
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-r7-proposal\",\"proposal\":\"approved\",\"registered\":false,\"runtime_available\":false,\"decision\":\"approved\",\"reason\":\"{s}\"}}\n",
        .{proto_ui.r7_proposal.reason_code},
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

    const proposal_path = args.next() orelse return error.MissingProposalArg;
    const actual = try cwd.readFileAlloc(io, proposal_path, gpa, .limited(64 * 1024));
    defer gpa.free(actual);

    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(gpa);
    try proto_ui.r7_proposal.writeProposal(gpa, &expected);
    if (!std.mem.eql(u8, actual, expected.items)) {
        emitApproved();
        std.debug.print("r7-proposal gate: artifact mismatch\n", .{});
        return error.InvalidR7ProposalArtifact;
    }
    if (proto_ui.r7_proposal.validateState()) |problem| {
        emitApproved();
        std.debug.print("r7-proposal gate: {s}\n", .{problem});
        return error.InvalidR7ProposalState;
    }
    emitApproved();
}
