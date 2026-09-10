//! Audits R8 entry readiness.  Normal mode accepts a blocked entry; negative
//! mode (`--expect=ready`) intentionally fails until every readiness condition
//! and adapter linkage/registration are complete.

const std = @import("std");
const proto_ui = @import("proto_ui");

const Mode = enum { blocked, ready };

fn emit(mode: Mode) void {
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-r8-readiness\",\"entry\":\"{s}\",\"allowed\":false,\"registered\":false,\"runtime_available\":false,\"reason\":\"{s}\",\"result\":\"pass\"}}\n",
        .{ @tagName(mode), proto_ui.r8_readiness.reason_code },
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
    var mode: Mode = .blocked;
    while (args.next()) |argument| {
        if (std.mem.eql(u8, argument, "--expect=blocked")) {
            mode = .blocked;
        } else if (std.mem.eql(u8, argument, "--expect=ready")) {
            mode = .ready;
        } else return error.UnknownGateArgument;
    }

    const actual = try cwd.readFileAlloc(io, manifest_path, gpa, .limited(64 * 1024));
    defer gpa.free(actual);
    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(gpa);
    try proto_ui.r8_readiness.writeManifest(gpa, &expected);
    if (!std.mem.eql(u8, actual, expected.items)) {
        std.debug.print("r8-readiness gate: artifact mismatch\n", .{});
        return error.InvalidR8ReadinessArtifact;
    }
    if (proto_ui.r8_readiness.validateState()) |problem| {
        std.debug.print("r8-readiness gate: {s}\n", .{problem});
        return error.InvalidR8ReadinessState;
    }

    if (mode == .ready) {
        std.debug.print(
            "r8-readiness gate: entry is blocked by {s}\n",
            .{proto_ui.r8_readiness.reason_code},
        );
        return error.R8AdapterLinkageOrRegistrationMissing;
    }
    emit(.blocked);
}
