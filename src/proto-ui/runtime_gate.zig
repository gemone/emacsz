//! Audits the generated runtime manifest and enforces its fail-closed gate.
//! With `-Dproto-ui-runtime=true`, a nonzero exit and machine-readable reason
//! are the intended contract until the host registration adapter exists.

const std = @import("std");
const proto_ui = @import("proto_ui");

fn emitUnavailable() void {
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-runtime\",\"runtime_available\":false,\"fail_closed\":true,\"reason\":{{\"code\":\"{s}\",\"message\":\"{s}\"}}}}\n",
        .{ proto_ui.runtime.reason_code, proto_ui.runtime.fail_closed_reason },
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
    const mode = args.next() orelse "audit";
    const actual = try cwd.readFileAlloc(io, manifest_path, gpa, .limited(64 * 1024));
    defer gpa.free(actual);

    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(gpa);
    try proto_ui.runtime.writeManifest(gpa, &expected);
    if (!std.mem.eql(u8, actual, expected.items)) {
        emitUnavailable();
        std.debug.print("runtime gate: manifest mismatch\n", .{});
        return error.InvalidRuntimeManifest;
    }
    if (proto_ui.runtime.validateState()) |problem| {
        emitUnavailable();
        std.debug.print("runtime gate: {s}\n", .{problem});
        return error.InvalidRuntimeState;
    }

    // The successful audit still must not open a runtime path.  It proves the
    // generated artifact accurately records the unavailable/fail-closed state.
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-runtime\",\"runtime_available\":false,\"fail_closed\":true,\"reason\":{{\"code\":\"{s}\"}}}}\n",
        .{proto_ui.runtime.reason_code},
    );
    if (std.mem.eql(u8, mode, "require")) return error.RuntimeUnavailableByContract;
    if (!std.mem.eql(u8, mode, "audit")) return error.InvalidGateMode;
}
