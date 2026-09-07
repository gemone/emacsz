//! Validates the tracked Lisp report and republishes exactly one JSON object.

const std = @import("std");

const Error = error{
    InvalidReport,
    MissingReportArg,
    ReportTooLarge,
    ScenarioFailed,
};

fn text(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |item| item,
        else => null,
    };
}

fn field(value: std.json.Value, name: []const u8) ?std.json.Value {
    return switch (value) {
        .object => |object| object.get(name),
        else => null,
    };
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
    if (!std.mem.eql(u8, overall, "pass")) return Error.ScenarioFailed;

    std.debug.print("{s}\n", .{trimmed});
}
