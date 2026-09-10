//! Audits the adapter-only TP2 registration-policy manifest.

const std = @import("std");
const proto_ui = @import("proto_ui");

fn emit() void {
    std.debug.print(
        "{{\"manifest_version\":1,\"gate\":\"proto-ui-tpe-registration\",\"policy\":\"{s}\",\"registered\":false,\"runtime_available\":false,\"reason\":\"{s}\",\"result\":\"pass\"}}\n",
        .{
            proto_ui.tpe_registration.policy_status,
            proto_ui.tpe_registration.fail_closed_reason,
        },
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
    if (args.next() != null) return error.UnknownGateArgument;

    const actual = try cwd.readFileAlloc(io, manifest_path, gpa, .limited(64 * 1024));
    defer gpa.free(actual);
    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(gpa);
    try proto_ui.tpe_registration.writeManifest(gpa, &expected);
    if (!std.mem.eql(u8, actual, expected.items))
        return error.InvalidTpeRegistrationArtifact;
    if (proto_ui.tpe_registration.validatePolicy() != null)
        return error.InvalidTpeRegistrationState;
    emit();
}
