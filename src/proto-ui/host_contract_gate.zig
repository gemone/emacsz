//! Audits schema, policy, determinism, and current fail-closed runtime state.

const std = @import("std");
const proto_ui = @import("proto_ui");

fn emitDecision(reason: []const u8) void {
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-host-contract\",\"decision\":\"approved\",\"runtime_available\":false,\"reason\":\"{s}\"}}\n",
        .{reason},
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

    const contract_path = args.next() orelse return error.MissingContractArg;
    const actual = try cwd.readFileAlloc(io, contract_path, gpa, .limited(64 * 1024));
    defer gpa.free(actual);

    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(gpa);
    try proto_ui.host_contract.writeContract(gpa, &expected);
    if (!std.mem.eql(u8, actual, expected.items)) {
        emitDecision(proto_ui.runtime.reason_code);
        std.debug.print("host-contract gate: artifact mismatch\n", .{});
        return error.InvalidHostContractArtifact;
    }
    if (proto_ui.host_contract.validateState()) |problem| {
        emitDecision(proto_ui.runtime.reason_code);
        std.debug.print("host-contract gate: {s}\n", .{problem});
        return error.InvalidHostContractState;
    }

    var parsed = std.json.parseFromSlice(std.json.Value, gpa, actual, .{}) catch |err| {
        emitDecision(proto_ui.runtime.reason_code);
        std.debug.print("host-contract gate: invalid JSON: {s}\n", .{@errorName(err)});
        return err;
    };
    defer parsed.deinit();
    if (proto_ui.host_contract.validateArtifact(parsed.value)) |problem| {
        emitDecision(proto_ui.runtime.reason_code);
        std.debug.print("host-contract gate: {s}\n", .{problem});
        return error.InvalidHostContractSchema;
    }

    emitDecision(proto_ui.runtime.reason_code);
}
