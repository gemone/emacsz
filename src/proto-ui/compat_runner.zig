//! Validates the tracked Lisp report and republishes exactly one JSON object.

const std = @import("std");

const Error = error{
    InvalidReport,
    MissingReportArg,
    ReportTooLarge,
    ScenarioFailed,
    InvalidMatrix,
};

const semantic_names = [_][]const u8{
    "buffer_undo",
    "point_mark_narrowing",
    "text_overlay_properties",
    "face_definition_readback",
    "window_split_select_delete",
    "window_resize_scroll_recenter",
    "buffer_local_variables",
};

fn text(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |item| item,
        else => null,
    };
}

fn field(value: std.json.Value, name: []const u8) ?std.json.Value {
    return switch (value) {
        .object => |item| item.get(name),
        else => null,
    };
}

fn object(value: std.json.Value) ?std.json.ObjectMap {
    return switch (value) {
        .object => |item| item,
        else => null,
    };
}

fn array(value: std.json.Value) ?std.json.Array {
    return switch (value) {
        .array => |item| item,
        else => null,
    };
}

fn integer(value: std.json.Value) ?i64 {
    return switch (value) {
        .integer => |item| item,
        else => null,
    };
}

fn isDigest(value: []const u8) bool {
    if (value.len != 64) return false;
    for (value) |char| {
        const digit = (char >= '0' and char <= '9') or
            (char >= 'a' and char <= 'f');
        if (!digit) return false;
    }
    return true;
}

fn digestText(value: std.json.Value) ?[]const u8 {
    const item = text(value) orelse return null;
    return if (isDigest(item)) item else null;
}

fn sha256Hex(input: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(input, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

fn expectedCombinedDigest(
    gpa: std.mem.Allocator,
    items: std.json.Array,
) !?[64]u8 {
    var input: std.ArrayListUnmanaged(u8) = .empty;
    defer input.deinit(gpa);
    for (items.items, 0..) |item, index| {
        if (index != 0) try input.appendSlice(gpa, "\x1f");
        const record = object(item) orelse return null;
        const name = text(record.get("name") orelse return null) orelse return null;
        const signature = digestText(record.get("digest") orelse return null) orelse return null;
        try input.appendSlice(gpa, name);
        try input.appendSlice(gpa, "\x1f");
        try input.appendSlice(gpa, signature);
    }
    return sha256Hex(input.items);
}

fn validateSemanticScenarios(
    items: std.json.Array,
) bool {
    if (items.items.len != semantic_names.len) return false;
    for (items.items, semantic_names) |item, expected| {
        const record = object(item) orelse return false;
        const name = text(record.get("name") orelse return false) orelse return false;
        const status = text(record.get("status") orelse return false) orelse return false;
        const signature = text(record.get("signature") orelse return false) orelse return false;
        if (!std.mem.eql(u8, name, expected)) return false;
        if (!std.mem.eql(u8, status, "pass")) return false;
        if (signature.len == 0) return false;
        if (digestText(record.get("digest") orelse return false) == null) return false;
    }
    return true;
}

fn validateBackend(
    gpa: std.mem.Allocator,
    value: std.json.Value,
    context: []const u8,
    allow_skip: bool,
) !bool {
    const backend = object(value) orelse return Error.InvalidMatrix;
    const status = text(backend.get("status") orelse return Error.InvalidMatrix) orelse
        return Error.InvalidMatrix;
    const metadata_value = backend.get("metadata");
    const has_metadata = metadata_value != null and metadata_value.? != .null;
    if (!allow_skip or has_metadata) {
        const metadata = object(metadata_value orelse return Error.InvalidMatrix) orelse
            return Error.InvalidMatrix;
        const item = text(metadata.get("context") orelse return Error.InvalidMatrix) orelse
            return Error.InvalidMatrix;
        if (!std.mem.eql(u8, item, context)) return Error.InvalidMatrix;
    }
    const count = integer(backend.get("scenario_count") orelse return Error.InvalidMatrix) orelse
        return Error.InvalidMatrix;
    const combined = digestText(backend.get("combined_digest") orelse return Error.InvalidMatrix) orelse
        return Error.InvalidMatrix;
    const scenarios = array(backend.get("scenarios") orelse return Error.InvalidMatrix) orelse
        return Error.InvalidMatrix;

    if (std.mem.eql(u8, status, "skip")) {
        if (!allow_skip or scenarios.items.len != 0 or count != 0)
            return Error.InvalidMatrix;
    } else if (std.mem.eql(u8, status, "pass")) {
        if (!validateSemanticScenarios(scenarios))
            return Error.InvalidMatrix;
        if (count != @as(i64, semantic_names.len))
            return Error.InvalidMatrix;
        const expected = (try expectedCombinedDigest(gpa, scenarios)) orelse
            return Error.InvalidMatrix;
        if (!std.mem.eql(u8, combined, &expected))
            return Error.InvalidMatrix;
    } else if (std.mem.eql(u8, status, "fail")) {
        if (!allow_skip or scenarios.items.len != 0 or count != 0)
            return Error.InvalidMatrix;
        return Error.ScenarioFailed;
    } else return Error.InvalidMatrix;
    return std.mem.eql(u8, status, "skip");
}

fn semanticDigests(items: std.json.Array) !?[7][]const u8 {
    var result: [7][]const u8 = undefined;
    for (items.items, 0..) |item, index| {
        const record = object(item) orelse return null;
        result[index] = digestText(record.get("digest") orelse return null) orelse
            return null;
    }
    return result;
}

fn validateMatrix(gpa: std.mem.Allocator, root: std.json.Value) !void {
    const matrix_value = field(root, "matrix") orelse return Error.InvalidMatrix;
    const matrix = object(matrix_value) orelse return Error.InvalidMatrix;
    const schema = text(matrix.get("schema") orelse return Error.InvalidMatrix) orelse
        return Error.InvalidMatrix;
    const kind = text(matrix.get("kind") orelse return Error.InvalidMatrix) orelse
        return Error.InvalidMatrix;
    const version = integer(matrix.get("version") orelse return Error.InvalidMatrix) orelse
        return Error.InvalidMatrix;
    const overall = text(matrix.get("overall") orelse return Error.InvalidMatrix) orelse
        return Error.InvalidMatrix;
    if (!std.mem.eql(u8, schema, "proto-ui-compat-matrix/v1") or
        !std.mem.eql(u8, kind, "proto-ui-compat-matrix") or version != 1 or
        !std.mem.eql(u8, overall, "pass"))
        return Error.InvalidMatrix;

    const backends = object(matrix.get("backends") orelse return Error.InvalidMatrix) orelse
        return Error.InvalidMatrix;
    const tty_skip = try validateBackend(
        gpa,
        backends.get("tty") orelse return Error.InvalidMatrix,
        "batch_tty",
        false,
    );
    if (tty_skip) return Error.InvalidMatrix;
    const pgtk_skip = try validateBackend(
        gpa,
        backends.get("pgtk") orelse return Error.InvalidMatrix,
        "real_pgtk_child",
        true,
    );

    const tty_backend = object(backends.get("tty") orelse return Error.InvalidMatrix) orelse
        return Error.InvalidMatrix;
    const pgtk_backend = object(backends.get("pgtk") orelse return Error.InvalidMatrix) orelse
        return Error.InvalidMatrix;
    const tty_digests = (try semanticDigests(array(
        tty_backend.get("scenarios") orelse return Error.InvalidMatrix,
    ) orelse return Error.InvalidMatrix)) orelse return Error.InvalidMatrix;
    const pgtk_digests: ?[7][]const u8 = if (pgtk_skip)
        null
    else blk: {
        const scenarios = array(pgtk_backend.get("scenarios") orelse return Error.InvalidMatrix) orelse
            return Error.InvalidMatrix;
        break :blk (try semanticDigests(scenarios)) orelse return Error.InvalidMatrix;
    };

    const pairs = array(matrix.get("scenario_pairs") orelse return Error.InvalidMatrix) orelse
        return Error.InvalidMatrix;
    if (pairs.items.len != semantic_names.len) return Error.InvalidMatrix;
    for (pairs.items, semantic_names, 0..) |pair_value, expected, index| {
        const pair = object(pair_value) orelse return Error.InvalidMatrix;
        const name = text(pair.get("name") orelse return Error.InvalidMatrix) orelse
            return Error.InvalidMatrix;
        const status = text(pair.get("status") orelse return Error.InvalidMatrix) orelse
            return Error.InvalidMatrix;
        const tty_digest = digestText(pair.get("tty_digest") orelse return Error.InvalidMatrix) orelse
            return Error.InvalidMatrix;
        const pgtk_field = pair.get("pgtk_digest") orelse return Error.InvalidMatrix;
        const pgtk_digest = text(pgtk_field) orelse return Error.InvalidMatrix;
        if (!std.mem.eql(u8, name, expected)) return Error.InvalidMatrix;
        if (!std.mem.eql(u8, tty_digest, tty_digests[index]))
            return Error.InvalidMatrix;

        if (pgtk_skip) {
            if (!std.mem.eql(u8, status, "skip") or
                !std.mem.eql(u8, pgtk_digest, "unavailable"))
                return Error.InvalidMatrix;
        } else {
            if (!std.mem.eql(u8, status, "match") or
                !isDigest(pgtk_digest) or
                !std.mem.eql(u8, pgtk_digest, pgtk_digests.?[index]))
                return Error.ScenarioFailed;
        }

        const input = try std.fmt.allocPrint(
            gpa,
            "{s}\x1f{s}\x1f{s}",
            .{ name, tty_digest, pgtk_digest },
        );
        defer gpa.free(input);
        const expected_pair = sha256Hex(input);
        const pair_digest = digestText(pair.get("pair_digest") orelse return Error.InvalidMatrix) orelse
            return Error.InvalidMatrix;
        if (!std.mem.eql(u8, pair_digest, &expected_pair))
            return Error.InvalidMatrix;
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
    const path = args.next() orelse return Error.MissingReportArg;

    const report = cwd.readFileAlloc(io, path, gpa, .limited(256 * 1024)) catch
        return Error.ReportTooLarge;
    defer gpa.free(report);

    const trimmed = std.mem.trim(u8, report, " \t\r\n");
    if (trimmed.len == 0 or trimmed[0] != '{' or trimmed[trimmed.len - 1] != '}')
        return Error.InvalidReport;
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, trimmed, .{}) catch
        return Error.InvalidReport;
    defer parsed.deinit();

    const schema = text(field(parsed.value, "schema") orelse return Error.InvalidReport) orelse
        return Error.InvalidReport;
    const kind = text(field(parsed.value, "kind") orelse return Error.InvalidReport) orelse
        return Error.InvalidReport;
    const version = switch (field(parsed.value, "version") orelse return Error.InvalidReport) {
        .integer => |item| item,
        else => return Error.InvalidReport,
    };
    const overall = text(field(parsed.value, "overall") orelse return Error.InvalidReport) orelse
        return Error.InvalidReport;
    if (!std.mem.eql(u8, schema, "proto-ui-compat-report/v1") or
        !std.mem.eql(u8, kind, "proto-ui-compat-report") or version != 1)
        return Error.InvalidReport;

    const scenarios = switch (field(parsed.value, "scenarios") orelse return Error.InvalidReport) {
        .array => |items| items,
        else => return Error.InvalidReport,
    };
    if (scenarios.items.len < 9) return Error.InvalidReport;

    var identity = false;
    var undo = false;
    var narrowing = false;
    var properties = false;
    var face = false;
    var windows = false;
    var scroll = false;
    var locals = false;
    var pgtk_lifecycle = false;
    var pgtk_ui = false;

    for (scenarios.items) |scenario_value| {
        const scenario = switch (scenario_value) {
            .object => |item| item,
            else => return Error.InvalidReport,
        };
        const name = text(scenario.get("name") orelse return Error.InvalidReport) orelse
            return Error.InvalidReport;
        const status = text(scenario.get("status") orelse return Error.InvalidReport) orelse
            return Error.InvalidReport;
        if (scenario.get("details") == null) return Error.InvalidReport;
        if (std.mem.eql(u8, name, "identity")) {
            identity = true;
        } else if (std.mem.eql(u8, name, "buffer_undo")) {
            undo = true;
        } else if (std.mem.eql(u8, name, "point_mark_narrowing")) {
            narrowing = true;
        } else if (std.mem.eql(u8, name, "text_overlay_properties")) {
            properties = true;
        } else if (std.mem.eql(u8, name, "face_definition_readback")) {
            face = true;
        } else if (std.mem.eql(u8, name, "window_split_select_delete")) {
            windows = true;
        } else if (std.mem.eql(u8, name, "window_resize_scroll_recenter")) {
            scroll = true;
        } else if (std.mem.eql(u8, name, "buffer_local_variables")) {
            locals = true;
        } else if (std.mem.eql(u8, name, "pgtk_frame_lifecycle")) {
            pgtk_lifecycle = true;
        } else if (std.mem.eql(u8, name, "pgtk_window_scroll_face")) {
            pgtk_ui = true;
        }
        if (std.mem.eql(u8, status, "fail")) return Error.ScenarioFailed;
        if (!std.mem.eql(u8, status, "pass") and !std.mem.eql(u8, status, "skip"))
            return Error.InvalidReport;
    }

    if (!(identity and undo and narrowing and properties and face and
        windows and scroll and locals and pgtk_lifecycle and pgtk_ui))
        return Error.InvalidReport;
    try validateMatrix(gpa, parsed.value);
    if (!std.mem.eql(u8, overall, "pass")) return Error.ScenarioFailed;

    std.debug.print("{s}\n", .{trimmed});
}
