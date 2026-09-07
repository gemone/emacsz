//! W15-c disabled/default isolation audit.
//!
//! The scanner is intentionally conservative: any exact runtime marker in an
//! inherited C/Header/Lisp file is forbidden, including comments.  Owned
//! Proto-UI roots are excluded before reading, and build artifacts are never
//! traversed.  This proves the default is isolated; it does not enable
//! output_proto.

const std = @import("std");

pub const schema = "proto-ui-isolation-audit/v1";
pub const kind = "proto-ui-isolation-audit";
pub const version: u32 = 1;

pub const runtime_markers = [_][]const u8{
    "output_proto",
    "proto_ui",
    "proto-ui",
};

pub const config_markers = [_][]const u8{
    "HAVE_PROTO_UI",
    "output_proto",
};

pub const inherited_roots = [_][]const u8{
    "src/**/*.c or src/**/*.h, excluding src/proto-ui",
    "lisp/**/*.el",
    "src/config.h (generated, when present)",
};

pub const excluded_owned_roots = [_][]const u8{
    "src/proto-ui",
    "test/proto-ui",
    "tools/proto-ui-*",
    "docs",
    "zig-out",
    ".zig-cache",
    ".git",
};

pub const max_files: usize = 100_000;
pub const max_file_bytes: usize = 8 * 1024 * 1024;

pub const Class = enum {
    inherited_c_header,
    inherited_lisp,
    generated_config,
    owned,
    build_artifact,
    ignored,
};

pub const Report = struct {
    scanned_files: usize = 0,
    excluded_files: usize = 0,
    binary_skipped: usize = 0,
    marker_counts: [runtime_markers.len]usize = [_]usize{0} ** runtime_markers.len,
    config_present: bool = false,
    config_scanned: usize = 0,
    config_counts: [config_markers.len]usize = [_]usize{0} ** config_markers.len,
    truncated_or_skipped_files: usize = 0,

    pub fn inheritedMarkerTotal(self: Report) usize {
        var total: usize = 0;
        for (self.marker_counts) |count| total += count;
        return total;
    }

    pub fn configMarkerTotal(self: Report) usize {
        var total: usize = 0;
        for (self.config_counts) |count| total += count;
        return total;
    }

    pub fn pass(self: Report) bool {
        return self.inheritedMarkerTotal() == 0 and self.configMarkerTotal() == 0 and
            self.truncated_or_skipped_files == 0;
    }

    pub fn runtimeAdapterIntegrationAbsent(self: Report) bool {
        return self.pass();
    }
};

pub fn classifyPath(path: []const u8) Class {
    if (startsWith(path, "src/proto-ui/")) return .owned;
    if (startsWith(path, "test/proto-ui/")) return .owned;
    if (startsWith(path, "tools/proto-ui-")) return .owned;
    if (startsWith(path, "docs/")) return .owned;
    if (isArtifactPath(path)) return .build_artifact;
    if (std.mem.eql(u8, path, "src/config.h")) return .generated_config;

    if (startsWith(path, "src/")) {
        const extension = std.fs.path.extension(path);
        if (std.mem.eql(u8, extension, ".c") or std.mem.eql(u8, extension, ".h"))
            return .inherited_c_header;
    }
    if (startsWith(path, "lisp/") and std.mem.eql(u8, std.fs.path.extension(path), ".el"))
        return .inherited_lisp;
    return .ignored;
}

pub fn countMarker(content: []const u8, marker: []const u8) usize {
    if (marker.len == 0) return 0;
    var total: usize = 0;
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, content, offset, marker)) |at| {
        total += 1;
        offset = at + 1;
    }
    return total;
}

pub fn addMarkerCounts(content: []const u8, markers: []const []const u8, counts: []usize) void {
    for (markers, 0..) |marker, index| counts[index] += countMarker(content, marker);
}

pub fn auditPaths(
    paths: []const []const u8,
    config_text: ?[]const u8,
) Report {
    var report: Report = .{};
    for (paths) |path| {
        switch (classifyPath(path)) {
            .owned => report.excluded_files += 1,
            .inherited_c_header, .inherited_lisp => {
                report.scanned_files += 1;
            },
            .generated_config => {
                report.config_present = true;
                if (config_text) |text| {
                    report.config_scanned += 1;
                    addMarkerCounts(text, &config_markers, &report.config_counts);
                }
            },
            .build_artifact, .ignored => {},
        }
    }
    return report;
}

pub fn auditContent(
    content: []const u8,
    config_text: ?[]const u8,
    report: *Report,
) void {
    report.scanned_files += 1;
    if (std.mem.indexOfScalar(u8, content, 0) != null) {
        report.binary_skipped += 1;
        return;
    }
    addMarkerCounts(content, &runtime_markers, &report.marker_counts);
    if (config_text) |config| {
        report.config_present = true;
        report.config_scanned += 1;
        addMarkerCounts(config, &config_markers, &report.config_counts);
    }
}

pub fn appendReport(gpa: std.mem.Allocator, report: Report, out: *std.ArrayList(u8)) !void {
    try out.print(gpa,
        \\{{
        \\  "schema":"proto-ui-isolation-audit/v1",
        \\  "kind":"proto-ui-isolation-audit",
        \\  "version":1,
        \\  "runtime":{{"available":false,"terminal_registered":false,"host_registration_pending":true}},
        \\  "inherited_roots":[
    , .{});
    for (inherited_roots, 0..) |root, index| {
        try out.appendSlice(gpa, "\n    \"");
        try appendJsonText(gpa, out, root);
        try out.appendSlice(gpa, "\"");
        if (index + 1 != inherited_roots.len) try out.appendSlice(gpa, ",");
    }
    try out.appendSlice(gpa, "\n  ],\n  \"excluded_owned_roots\":[");
    for (excluded_owned_roots, 0..) |root, index| {
        try out.appendSlice(gpa, "\n    \"");
        try appendJsonText(gpa, out, root);
        try out.appendSlice(gpa, "\"");
        if (index + 1 != excluded_owned_roots.len) try out.appendSlice(gpa, ",");
    }
    try out.print(gpa,
        \\
        \\  ],
        \\  "scanned_files":{d},
        \\  "excluded_files":{d},
        \\  "binary_skipped":{d},
        \\  "truncated_or_skipped_files":{d},
        \\  "markers":[
    , .{
        report.scanned_files,
        report.excluded_files,
        report.binary_skipped,
        report.truncated_or_skipped_files,
    });
    for (runtime_markers, 0..) |marker, index| {
        try out.appendSlice(gpa, "\n    {\"name\":\"");
        try appendJsonText(gpa, out, marker);
        try out.print(gpa, "\",\"count\":{d}}}", .{report.marker_counts[index]});
        if (index + 1 != runtime_markers.len) try out.appendSlice(gpa, ",");
    }
    try out.print(gpa,
        \\
        \\  ],
        \\  "config":{{"present":{},"scanned":{d},"markers":[
    , .{ report.config_present, report.config_scanned });
    for (config_markers, 0..) |marker, index| {
        try out.appendSlice(gpa, "{\"name\":\"");
        try appendJsonText(gpa, out, marker);
        try out.print(gpa, "\",\"count\":{d}}}", .{report.config_counts[index]});
        if (index + 1 != config_markers.len) try out.appendSlice(gpa, ",");
    }
    try out.print(gpa,
        \\]}},
        \\  "runtime_adapter_integration_absent":{},
        \\  "result":"{s}"
        \\}}
        \\
    , .{
        report.runtimeAdapterIntegrationAbsent(),
        if (report.pass()) "pass" else "fail",
    });
}

fn appendJsonText(gpa: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
    for (text) |byte| {
        switch (byte) {
            '"' => try out.appendSlice(gpa, "\\\""),
            '\\' => try out.appendSlice(gpa, "\\\\"),
            else => {
                if (byte < 0x20) return error.InvalidJsonText;
                try out.append(gpa, byte);
            },
        }
    }
}

fn startsWith(path: []const u8, prefix: []const u8) bool {
    // Every call site already includes "/" or the intentional "tools/proto-ui-"
    // wildcard suffix in its prefix, so plain prefix matching is correct.
    return std.mem.startsWith(u8, path, prefix);
}

fn isArtifactPath(path: []const u8) bool {
    const roots = [_][]const u8{ "zig-out", ".zig-cache", ".git" };
    for (roots) |root| {
        if (path.len >= root.len and std.mem.startsWith(u8, path, root) and
            (path.len == root.len or path[root.len] == '/'))
        {
            return true;
        }
    }
    return false;
}

fn isSourceOwned(path: []const u8) bool {
    return classifyPath(path) == .owned;
}

fn scanWorkspace(gpa: std.mem.Allocator, io: std.Io, root: std.Io.Dir) !Report {
    var report: Report = .{};
    var seen: usize = 0;
    {
        var src = try root.openDir(io, "src", .{ .iterate = true });
        defer src.close(io);
        var walked = try src.walk(gpa);
        defer walked.deinit();
        while (try walked.next(io)) |entry| {
            seen += 1;
            if (seen > max_files) return error.TooManyFiles;
            if (entry.kind != .file) continue;
            if (std.mem.startsWith(u8, entry.path, "proto-ui/")) {
                report.excluded_files += 1;
                continue;
            }
            const extension = std.fs.path.extension(entry.path);
            if (!std.mem.eql(u8, extension, ".c") and !std.mem.eql(u8, extension, ".h"))
                continue;
            try scanFile(gpa, io, src, entry.path, &report, false);
        }
    }
    {
        var lisp = try root.openDir(io, "lisp", .{ .iterate = true });
        defer lisp.close(io);
        var walked = try lisp.walk(gpa);
        defer walked.deinit();
        while (try walked.next(io)) |entry| {
            seen += 1;
            if (seen > max_files) return error.TooManyFiles;
            if (entry.kind != .file) continue;
            if (!std.mem.eql(u8, std.fs.path.extension(entry.path), ".el")) continue;
            try scanFile(gpa, io, lisp, entry.path, &report, false);
        }
    }

    if (root.statFile(io, "src/config.h", .{})) |stat| {
        report.config_present = true;
        if (stat.size <= max_file_bytes) {
            const text = try root.readFileAlloc(io, "src/config.h", gpa, .limited(max_file_bytes));
            defer gpa.free(text);
            if (std.mem.indexOfScalar(u8, text, 0) == null) {
                report.config_scanned += 1;
                addMarkerCounts(text, &config_markers, &report.config_counts);
            } else {
                report.binary_skipped += 1;
            }
        } else {
            report.truncated_or_skipped_files += 1;
        }
    } else |_| {}

    return report;
}

fn scanFile(
    gpa: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    path: []const u8,
    report: *Report,
    is_config: bool,
) !void {
    const stat = try dir.statFile(io, path, .{});
    if (stat.size > max_file_bytes) {
        report.truncated_or_skipped_files += 1;
        if (is_config) report.config_present = true;
        return;
    }
    const text = try dir.readFileAlloc(io, path, gpa, .limited(max_file_bytes));
    defer gpa.free(text);
    if (std.mem.indexOfScalar(u8, text, 0) != null) {
        report.binary_skipped += 1;
        return;
    }
    if (is_config) {
        report.config_present = true;
        report.config_scanned += 1;
        addMarkerCounts(text, &config_markers, &report.config_counts);
    } else {
        report.scanned_files += 1;
        addMarkerCounts(text, &runtime_markers, &report.marker_counts);
    }
}

pub fn validateManifest(value: std.json.Value) ?[]const u8 {
    if (value != .object) return "root is not an object";
    const object = value.object;
    const expected = [_]struct { name: []const u8, expected: []const u8 }{
        .{ .name = "schema", .expected = schema },
        .{ .name = "kind", .expected = kind },
    };
    for (expected) |item| {
        const actual = object.get(item.name) orelse return "missing manifest field";
        if (!isString(actual, item.expected)) return "unexpected manifest identity";
    }
    if (!isInteger(object.get("version"), version)) return "unexpected manifest identity";
    const runtime = object.get("runtime") orelse return "missing runtime";
    if (runtime != .object) return "runtime is not an object";
    if (!isBoolean(runtime.object.get("available"), false)) return "runtime is available";
    if (!isBoolean(runtime.object.get("terminal_registered"), false)) return "terminal is registered";
    if (!isBoolean(runtime.object.get("host_registration_pending"), true))
        return "host registration is not pending";

    const markers = object.get("markers") orelse return "missing markers";
    if (markers != .array or markers.array.items.len != runtime_markers.len)
        return "invalid marker table";
    for (markers.array.items, 0..) |item, index| {
        if (item != .object) return "marker is not an object";
        if (!isInteger(item.object.get("count"), 0)) return "inherited marker is present";
        if (!isString(item.object.get("name"), runtime_markers[index]))
            return "marker order changed";
    }
    const config = object.get("config") orelse return "missing config";
    if (config != .object) return "config is not an object";
    const config_table = config.object.get("markers").?.array;
    for (config_table.items) |item| {
        if (!isInteger(item.object.get("count"), 0)) return "config marker is present";
    }
    const result = object.get("result").?;
    if (!isString(result, "pass")) return "audit result is not pass";
    return null;
}

fn isString(value: ?std.json.Value, expected: []const u8) bool {
    return value != null and value.? == .string and std.mem.eql(u8, value.?.string, expected);
}

fn isBoolean(value: ?std.json.Value, expected: bool) bool {
    return value != null and value.? == .bool and value.?.bool == expected;
}

fn isInteger(value: ?std.json.Value, expected: u32) bool {
    return value != null and value.? == .integer and value.?.integer == expected;
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    var args = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer args.deinit();
    _ = args.next();
    const output_path = args.next() orelse return error.MissingOutputArg;
    if (args.next() != null) return error.UnexpectedArgument;

    const report = try scanWorkspace(gpa, io, cwd);
    var manifest: std.ArrayList(u8) = .empty;
    defer manifest.deinit(gpa);
    try appendReport(gpa, report, &manifest);
    try cwd.writeFile(io, .{ .sub_path = output_path, .data = manifest.items });

    std.debug.print(
        "isolation-audit: {s} scanned={d} excluded={d} markers={d} config={d}\n",
        .{
            if (report.pass()) "pass" else "fail",
            report.scanned_files,
            report.excluded_files,
            report.inheritedMarkerTotal(),
            report.configMarkerTotal(),
        },
    );
    if (!report.pass()) return error.ForbiddenInheritedProtoUiMarker;
}

test "path classification excludes owned roots and build outputs" {
    try std.testing.expectEqual(Class.inherited_c_header, classifyPath("src/frame.c"));
    try std.testing.expectEqual(Class.inherited_c_header, classifyPath("src/lisp.h"));
    try std.testing.expectEqual(Class.inherited_lisp, classifyPath("lisp/subr.el"));
    try std.testing.expectEqual(Class.generated_config, classifyPath("src/config.h"));
    try std.testing.expectEqual(Class.owned, classifyPath("src/proto-ui/protocol.zig"));
    try std.testing.expectEqual(Class.owned, classifyPath("src/proto-ui/nested/file.c"));
    try std.testing.expectEqual(Class.owned, classifyPath("test/proto-ui/compat.el"));
    try std.testing.expectEqual(Class.owned, classifyPath("tools/proto-ui-sdl3/main.zig"));
    try std.testing.expectEqual(Class.owned, classifyPath("docs/proto-ui/README.md"));
    try std.testing.expectEqual(Class.build_artifact, classifyPath("zig-out/proto-ui/runtime_manifest.json"));
    try std.testing.expectEqual(Class.build_artifact, classifyPath(".zig-cache/x/y"));
    try std.testing.expectEqual(Class.ignored, classifyPath("src/foo.txt"));
    try std.testing.expectEqual(Class.ignored, classifyPath("README.md"));
}

test "marker counts are exact, overlapping, and comment-visible" {
    var counts: [runtime_markers.len]usize = [_]usize{0} ** runtime_markers.len;
    const text = "output_proto proto_ui proto-ui output_proto // proto_ui";
    addMarkerCounts(text, &runtime_markers, &counts);
    try std.testing.expectEqual([_]usize{ 2, 2, 1 }, counts);
    try std.testing.expectEqual(@as(usize, 3), countMarker("aaaa", "aa"));
    try std.testing.expectEqual(@as(usize, 0), countMarker("safe", ""));
}

test "synthetic audit counts inherited, excluded, and config paths deterministically" {
    const paths = [_][]const u8{
        "src/frame.c",
        "src/proto-ui/protocol.zig",
        "lisp/subr.el",
        "src/config.h",
        "docs/x.md",
        "zig-out/x.bin",
    };
    const first = auditPaths(&paths, "/* HAVE_PROTO_UI output_proto */");
    const second = auditPaths(&paths, "/* HAVE_PROTO_UI output_proto */");
    try std.testing.expectEqual(first.scanned_files, second.scanned_files);
    try std.testing.expectEqual(first.excluded_files, second.excluded_files);
    try std.testing.expectEqual(@as(usize, 2), first.scanned_files);
    try std.testing.expectEqual(@as(usize, 2), first.excluded_files);
    try std.testing.expectEqual(@as(usize, 1), first.config_scanned);
    try std.testing.expectEqual([_]usize{ 1, 1 }, first.config_counts);
    try std.testing.expect(!first.pass());
}

test "content audit detects comments and binary files are skipped" {
    var report: Report = .{};
    auditContent("// output_proto\n/* proto_ui */\n", null, &report);
    try std.testing.expectEqual(@as(usize, 1), report.scanned_files);
    try std.testing.expectEqual(@as(usize, 1), report.marker_counts[0]);
    try std.testing.expectEqual(@as(usize, 1), report.marker_counts[1]);

    var binary: Report = .{};
    auditContent("text\x00proto-ui", "output_proto", &binary);
    try std.testing.expectEqual(@as(usize, 1), binary.binary_skipped);
    try std.testing.expectEqual(@as(usize, 0), binary.inheritedMarkerTotal());
    try std.testing.expectEqual(@as(usize, 0), binary.config_scanned);

    var config: Report = .{};
    config.config_present = true;
    config.config_scanned = 1;
    config.config_counts[0] = 1;
    try std.testing.expect(!config.pass());
}

test "oversized text cannot hide a marker behind a passing report" {
    var report: Report = .{};
    report.truncated_or_skipped_files = 1;
    try std.testing.expect(!report.pass());
}

test "report JSON is deterministic, machine-readable, and fail-closed" {
    const gpa = std.testing.allocator;
    var report: Report = .{};
    report.scanned_files = 123;
    report.excluded_files = 45;
    report.config_present = true;
    report.config_scanned = 1;

    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(gpa);
    try appendReport(gpa, report, &first);
    try appendReport(gpa, report, &second);
    try std.testing.expectEqualSlices(u8, first.items, second.items);
    try std.testing.expect(first.items.len < 8 * 1024);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, first.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?[]const u8, null), validateManifest(parsed.value));
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"runtime_adapter_integration_absent\":true") != null);

    var bad: Report = .{};
    bad.marker_counts[0] = 1;
    var json: std.ArrayList(u8) = .empty;
    defer json.deinit(gpa);
    try appendReport(gpa, bad, &json);
    var bad_parsed = try std.json.parseFromSlice(std.json.Value, gpa, json.items, .{});
    defer bad_parsed.deinit();
    try std.testing.expectEqualStrings("inherited marker is present", validateManifest(bad_parsed.value).?);
}
