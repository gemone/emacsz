//! Source-authoritative implementation coverage for every assigned EUP v1 ID.
//!
//! This manifest is an honest completeness audit, not a claim that EUP is
//! production complete.  A `planned` entry means the assigned ID remains to be
//! implemented and must not be sent or accepted as a concrete codec.

const std = @import("std");
const protocol = @import("protocol.zig");

pub const manifest_version: u32 = 1;
pub const coverage_schema_version: u32 = 1;
pub const authoritative_source = "src/proto-ui/protocol.zig";

pub const Status = enum(u8) {
    implemented_codec = 0,
    partial = 1,
    planned = 2,
    reserved_diagnostic = 3,
};

pub const Domain = enum(u8) {
    session = 0,
    frame = 1,
    window = 2,
    render = 3,
    resource = 4,
    input = 5,
    ime = 6,
    selection = 7,
    widget = 8,
    diagnostic = 9,
    extension = 10,
};

pub const Entry = struct {
    id: u16,
    status: Status,
    domain: Domain,
    name: []const u8,
    evidence_or_gap: []const u8,
};

pub const Counters = struct {
    total: usize,
    implemented_codec: usize,
    partial: usize,
    planned: usize,
    reserved_diagnostic: usize,
};

const Range = struct {
    low: u16,
    high: u16,
    status: Status,
    domain: Domain,
    family: []const u8,
    note: []const u8,
};

const ranges = [_]Range{
    .{ .low = 0x0001, .high = 0x0002, .status = .implemented_codec, .domain = .session, .family = "handshake", .note = "standard HELLO/HELLO_ACK codecs, setup state machine, EPXL transport" },
    .{ .low = 0x0003, .high = 0x0004, .status = .implemented_codec, .domain = .session, .family = "capabilities", .note = "capability table encode/decode and negotiation tests" },
    .{ .low = 0x0005, .high = 0x0006, .status = .implemented_codec, .domain = .session, .family = "session-ready", .note = "standard ready handshake codecs and bounded state machine" },
    .{ .low = 0x0007, .high = 0x000e, .status = .implemented_codec, .domain = .session, .family = "session-control", .note = "codecs and control state machine; not EPXL-wired" },
    .{ .low = 0x000f, .high = 0x0011, .status = .partial, .domain = .session, .family = "resync", .note = "authenticated local resync/recovery smoke; arbitrary recovery pending" },
    .{ .low = 0x0200, .high = 0x0200, .status = .implemented_codec, .domain = .frame, .family = "frame-create", .note = "frontend lifecycle and runtime bridge conformance" },
    .{ .low = 0x0201, .high = 0x0202, .status = .planned, .domain = .frame, .family = "frame-state", .note = "patch and snapshot payload pending" },
    .{ .low = 0x0203, .high = 0x0203, .status = .implemented_codec, .domain = .frame, .family = "frame-update", .note = "atomic header/section codec, Scene apply, replay tests" },
    .{ .low = 0x0204, .high = 0x0205, .status = .implemented_codec, .domain = .frame, .family = "frame-feedback", .note = "presented/dropped codecs and SDL counter feedback conformance; core consumer pending" },
    .{ .low = 0x0206, .high = 0x0206, .status = .implemented_codec, .domain = .frame, .family = "frame-destroy", .note = "frontend and runtime bridge lifecycle conformance" },
    .{ .low = 0x0207, .high = 0x0207, .status = .implemented_codec, .domain = .frame, .family = "frame-geometry", .note = "outer/content/text/window/body rectangles, Scene state, SDL border query" },
    .{ .low = 0x0208, .high = 0x0208, .status = .implemented_codec, .domain = .frame, .family = "frame-visibility", .note = "state codec, Scene registry, bridge conformance" },
    .{ .low = 0x0209, .high = 0x0209, .status = .implemented_codec, .domain = .frame, .family = "frame-title", .note = "generation-qualified title codec, Scene state, SDL smoke" },
    .{ .low = 0x020a, .high = 0x020a, .status = .implemented_codec, .domain = .frame, .family = "frame-icon", .note = "nullable generation-qualified icon resource codec, Scene validation, SDL surface icon" },
    .{ .low = 0x020b, .high = 0x020b, .status = .implemented_codec, .domain = .frame, .family = "frame-fullscreen", .note = "Emacs fullscreen-mode codec, Scene state, SDL fullboth probe" },
    .{ .low = 0x020c, .high = 0x020c, .status = .implemented_codec, .domain = .frame, .family = "frame-maximize", .note = "horizontal/vertical maximize codec, Scene state, SDL both-axis probe" },
    .{ .low = 0x020d, .high = 0x020d, .status = .implemented_codec, .domain = .frame, .family = "frame-alpha", .note = "active/inactive/background opacity codec, Scene state, SDL probe" },
    .{ .low = 0x020e, .high = 0x020e, .status = .implemented_codec, .domain = .frame, .family = "frame-monitor", .note = "generation-qualified monitor identity, primary flag, bounds codec, SDL query" },
    .{ .low = 0x020f, .high = 0x020f, .status = .implemented_codec, .domain = .frame, .family = "frame-scale", .note = "generation-qualified scale/DPI codec, Scene state, SDL probe" },
    .{ .low = 0x0210, .high = 0x0210, .status = .implemented_codec, .domain = .frame, .family = "frame-focus", .note = "state codec, Scene registry, bridge conformance" },
    .{ .low = 0x0211, .high = 0x0211, .status = .implemented_codec, .domain = .frame, .family = "frame-size-hints", .note = "min/max, increment, and aspect-ratio hints; Scene state with SDL min/max/aspect, increments pending" },
    .{ .low = 0x0212, .high = 0x0212, .status = .implemented_codec, .domain = .frame, .family = "frame-z-order", .note = "raise/lower/top/bottom/above/below codec, Scene state, SDL always-on-top probe" },
    .{ .low = 0x0213, .high = 0x0213, .status = .implemented_codec, .domain = .frame, .family = "frame-parent", .note = "nullable parent/modal codec, Scene state, SDL unparent probe; linked child windows pending" },
    .{ .low = 0x0214, .high = 0x0214, .status = .implemented_codec, .domain = .frame, .family = "frame-decorations", .note = "undecorated/decorated codec, Scene state, SDL probe" },
    .{ .low = 0x0300, .high = 0x0300, .status = .implemented_codec, .domain = .window, .family = "window-tree", .note = "bounded complete-tree codec and Scene validation" },
    .{ .low = 0x0301, .high = 0x0301, .status = .implemented_codec, .domain = .window, .family = "window-create", .note = "bounded visible-window create codec and Scene lifecycle" },
    .{ .low = 0x0302, .high = 0x0302, .status = .implemented_codec, .domain = .window, .family = "window-patch", .note = "bounded geometry/parent/visibility/face/depth patch with Scene validation" },
    .{ .low = 0x0303, .high = 0x0303, .status = .implemented_codec, .domain = .window, .family = "window-delete", .note = "bounded empty-window delete codec and Scene lifecycle" },
    .{ .low = 0x0304, .high = 0x0304, .status = .implemented_codec, .domain = .window, .family = "window-geometry", .note = "bounded content/body geometry codec, owner validation, Scene upsert, SDL body-boundary render evidence" },
    .{ .low = 0x0305, .high = 0x0305, .status = .implemented_codec, .domain = .window, .family = "window-zones", .note = "bounded mode/header/tab/margin/fringe/scrollbar zone codec, disjoint owner validation, Scene upsert, SDL render evidence" },
    .{ .low = 0x0306, .high = 0x0306, .status = .implemented_codec, .domain = .window, .family = "window-face", .note = "bounded window default-face state codec, active resource validation, Scene upsert, SDL render evidence" },
    .{ .low = 0x0307, .high = 0x0307, .status = .implemented_codec, .domain = .window, .family = "window-position", .note = "bounded diagnostic buffer identity/start/point codec, active-frame/window validation, and Scene upsert; no text/layout transport" },
    .{ .low = 0x0308, .high = 0x0308, .status = .implemented_codec, .domain = .window, .family = "scroll-state", .note = "bounded scrollbar state codec, active-frame/window validation, Scene upsert, SDL render evidence" },
    .{ .low = 0x0309, .high = 0x0309, .status = .implemented_codec, .domain = .window, .family = "scroll-request", .note = "bounded absolute/relative reverse intent codec and delivery journal queue" },
    .{ .low = 0x030a, .high = 0x030a, .status = .implemented_codec, .domain = .window, .family = "mouse-highlight", .note = "bounded visible mouse-face rect codec, live face/window validation, Scene upsert, SDL render evidence; full mouse-face semantics pending" },
    .{ .low = 0x0400, .high = 0x0401, .status = .implemented_codec, .domain = .render, .family = "render-debug", .note = "strict BEGIN/END update boundary codecs, active-frame validation, and Scene nesting/state lifecycle" },
    .{ .low = 0x0402, .high = 0x0404, .status = .implemented_codec, .domain = .render, .family = "row-lifecycle", .note = "bounded row snapshot/update/delete codecs with owner bounds, generation validation, and Scene lifecycle" },
    .{ .low = 0x0405, .high = 0x0405, .status = .implemented_codec, .domain = .render, .family = "glyph-run", .note = "bounded ASCII v1/v2 and shaped atlas v3 with Scene validation" },
    .{ .low = 0x0406, .high = 0x0406, .status = .implemented_codec, .domain = .render, .family = "glyph-run-delete", .note = "exact identity deletion and fallback restore" },
    .{ .low = 0x0407, .high = 0x0407, .status = .implemented_codec, .domain = .render, .family = "cursor-update", .note = "dedicated cursor codec, owner/geometry validation, Scene state, SDL render evidence" },
    .{ .low = 0x0408, .high = 0x0408, .status = .implemented_codec, .domain = .render, .family = "fringe-update", .note = "bounded side/color fringe codec, generation replacement, Scene validation, SDL render evidence" },
    .{ .low = 0x0409, .high = 0x0409, .status = .implemented_codec, .domain = .render, .family = "divider-update", .note = "bounded vertical/horizontal divider codec, generation replacement, Scene validation, SDL render evidence" },
    .{ .low = 0x040a, .high = 0x040a, .status = .implemented_codec, .domain = .render, .family = "border-update", .note = "bounded side mask, thickness/color codec, Scene state, SDL border evidence" },
    .{ .low = 0x040c, .high = 0x040c, .status = .implemented_codec, .domain = .render, .family = "scroll-run", .note = "bounded vertical scroll codec, Scene validation, and copy plan metrics; SDL copy backend pending" },
    .{ .low = 0x040b, .high = 0x040b, .status = .implemented_codec, .domain = .render, .family = "clear-area", .note = "bounded face-colored rect codec, active-frame validation, Scene state, SDL render evidence" },
    .{ .low = 0x040d, .high = 0x040d, .status = .implemented_codec, .domain = .render, .family = "damage-rects", .note = "bounded active-frame damage array codec, Scene atomic replacement, bridge emission" },
    .{ .low = 0x040e, .high = 0x040e, .status = .implemented_codec, .domain = .render, .family = "flush", .note = "strict codec, bridge emission, Scene generation/sequence validation, SDL smoke evidence" },
    .{ .low = 0x040f, .high = 0x040f, .status = .implemented_codec, .domain = .render, .family = "render-hint", .note = "strict codec, bridge emission, Scene state, SDL smoke evidence" },
    .{ .low = 0x0500, .high = 0x0500, .status = .implemented_codec, .domain = .resource, .family = "face-define", .note = "bounded face resource codec and Scene ownership" },
    .{ .low = 0x0501, .high = 0x0501, .status = .implemented_codec, .domain = .resource, .family = "face-patch", .note = "bounded color patch, strict generation replacement, Scene validation; full face attributes pending" },
    .{ .low = 0x0502, .high = 0x0502, .status = .implemented_codec, .domain = .resource, .family = "face-delete", .note = "generation-qualified bounded delete" },
    .{ .low = 0x0503, .high = 0x0503, .status = .implemented_codec, .domain = .resource, .family = "font-define", .note = "bounded font resource codec and Scene ownership" },
    .{ .low = 0x0504, .high = 0x0504, .status = .implemented_codec, .domain = .resource, .family = "font-patch", .note = "bounded scalar descriptor patch, exact generation replacement, stale shaped-run invalidation, Scene state, and runtime smoke; string/metric/full font patching pending" },
    .{ .low = 0x0505, .high = 0x0505, .status = .implemented_codec, .domain = .resource, .family = "font-metrics", .note = "bounded metrics patch, strict generation replacement, Scene validation" },
    .{ .low = 0x0506, .high = 0x0506, .status = .implemented_codec, .domain = .resource, .family = "font-delete", .note = "generation-qualified bounded delete" },
    .{ .low = 0x0507, .high = 0x0509, .status = .implemented_codec, .domain = .resource, .family = "image-lifecycle", .note = "bounded static RGBA define/data/delete codecs" },
    .{ .low = 0x050a, .high = 0x050b, .status = .implemented_codec, .domain = .resource, .family = "fringe-bitmap", .note = "bounded monochrome bitmap define/delete, exact-generation registry lifecycle, stale placement removal, snapshot restore, and SDL pixel rendering; color/alpha bitmap and full fringe semantics pending" },
    .{ .low = 0x050c, .high = 0x050d, .status = .planned, .domain = .resource, .family = "icon-resource", .note = "standalone icon resource codecs pending" },
    .{ .low = 0x050e, .high = 0x050f, .status = .implemented_codec, .domain = .resource, .family = "string-lifecycle", .note = "bounded UTF-8 string define/delete" },
    .{ .low = 0x0510, .high = 0x0512, .status = .implemented_codec, .domain = .resource, .family = "resource-policy-snapshot", .note = "request, eviction, and atomic concrete snapshot codecs" },
    .{ .low = 0x0513, .high = 0x0516, .status = .implemented_codec, .domain = .resource, .family = "atlas-lifecycle", .note = "bounded atlas define/page update/glyph add/invalidate codecs and Scene state" },
    .{ .low = 0x0600, .high = 0x0603, .status = .implemented_codec, .domain = .input, .family = "key-text-pointer-wheel", .note = "bounded codecs plus SDL/EPXL delivery paths" },
    .{ .low = 0x0604, .high = 0x0605, .status = .planned, .domain = .input, .family = "touch-gesture", .note = "touch and gesture codecs pending" },
    .{ .low = 0x0606, .high = 0x0607, .status = .implemented_codec, .domain = .input, .family = "platform-focus-window", .note = "strict focus/window intent codecs and smoke" },
    .{ .low = 0x0608, .high = 0x060c, .status = .planned, .domain = .input, .family = "extended-platform", .note = "extended platform input intents pending" },
    .{ .low = 0x0700, .high = 0x0719, .status = .planned, .domain = .ime, .family = "ime", .note = "IME composition and candidate payloads pending" },
    .{ .low = 0x0800, .high = 0x0826, .status = .planned, .domain = .selection, .family = "selection-clipboard-dnd", .note = "MIME, PRIMARY/SECONDARY, and DND codecs pending" },
    .{ .low = 0x0900, .high = 0x0941, .status = .planned, .domain = .widget, .family = "widgets", .note = "menu/toolbar/dialog/tooltip/scrollbar models pending" },
    .{ .low = 0x0a00, .high = 0x0a09, .status = .planned, .domain = .diagnostic, .family = "diagnostics", .note = "performance/trace/replay diagnostic payloads pending" },
};

fn rangeFor(id: u16) ?Range {
    for (ranges) |range| {
        if (id >= range.low and id <= range.high) return range;
    }
    return null;
}

pub fn domainName(domain: Domain) []const u8 {
    return @tagName(domain);
}

pub fn statusName(status: Status) []const u8 {
    return @tagName(status);
}

fn entryFor(id: u16) !Entry {
    if (!protocol.knownMessage(id)) return error.UnknownMessageId;
    if (id == 0x0001 or id == 0x0002 or id == 0x0005 or id == 0x0006) return Entry{
        .id = id,
        .status = .implemented_codec,
        .domain = .session,
        .name = "session-setup",
        .evidence_or_gap = "standard EUP setup codec and bounded state-machine tests",
    };
    if (id == 0x0300) return Entry{
        .id = id,
        .status = .implemented_codec,
        .domain = .window,
        .name = "window-tree-snapshot",
        .evidence_or_gap = "bounded complete tree codec and Scene state validation",
    };
    const range = rangeFor(id) orelse return error.UnclassifiedMessageId;
    return .{
        .id = id,
        .status = range.status,
        .domain = range.domain,
        .name = range.family,
        .evidence_or_gap = range.note,
    };
}

pub fn entries() [protocol.known_message_ids.len]Entry {
    var result: [protocol.known_message_ids.len]Entry = undefined;
    for (protocol.known_message_ids, 0..) |id, index| {
        result[index] = entryFor(id) catch unreachable;
    }
    return result;
}

pub fn counters() Counters {
    var result = Counters{
        .total = protocol.known_message_ids.len,
        .implemented_codec = 0,
        .partial = 0,
        .planned = 0,
        .reserved_diagnostic = 0,
    };
    for (protocol.known_message_ids) |id| {
        const entry = entryFor(id) catch unreachable;
        switch (entry.status) {
            .implemented_codec => result.implemented_codec += 1,
            .partial => result.partial += 1,
            .planned => result.planned += 1,
            .reserved_diagnostic => result.reserved_diagnostic += 1,
        }
    }
    return result;
}

pub fn validateState() ?[]const u8 {
    if (protocol.known_message_ids.len == 0) return "assigned ID table is empty";
    var previous: u16 = 0;
    for (protocol.known_message_ids, 0..) |id, index| {
        if (index != 0 and id <= previous) return "assigned IDs are not sorted/unique";
        previous = id;
        _ = entryFor(id) catch return "assigned ID is unclassified";
    }
    const counts = counters();
    if (counts.total != counts.implemented_codec + counts.partial +
        counts.planned + counts.reserved_diagnostic) return "coverage counters do not sum";
    if (counts.implemented_codec == 0) return "no implemented codecs recorded";
    if (counts.planned == 0) return "coverage dishonestly omits planned IDs";
    return null;
}

fn appendJsonString(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.append(gpa, '"');
    for (value) |char| {
        switch (char) {
            '"' => try out.appendSlice(gpa, "\\\""),
            '\\' => try out.appendSlice(gpa, "\\\\"),
            '\n' => try out.appendSlice(gpa, "\\n"),
            '\r' => try out.appendSlice(gpa, "\\r"),
            '\t' => try out.appendSlice(gpa, "\\t"),
            else => {
                if (char < 0x20) {
                    try out.print(gpa, "\\u{x:0>4}", .{char});
                } else {
                    try out.append(gpa, char);
                }
            },
        }
    }
    try out.append(gpa, '"');
}

pub fn writeManifest(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    if (validateState() != null) return error.InvalidProtocolCoverage;
    try out.appendSlice(gpa, "{\"manifest_version\":");
    try out.print(gpa, "{d}", .{manifest_version});
    try out.appendSlice(gpa, ",\"kind\":\"proto-ui-eup-message-coverage\",");
    try out.appendSlice(gpa, "\"authoritative_source\":");
    try appendJsonString(gpa, out, authoritative_source);
    try out.appendSlice(gpa, ",\"coverage_schema_version\":");
    try out.print(gpa, "{d}", .{coverage_schema_version});
    try out.appendSlice(gpa, ",\"counters\":");
    const counts = counters();
    try out.print(gpa, "{{\"total\":{d},\"implemented_codec\":{d},\"partial\":{d},\"planned\":{d},\"reserved_diagnostic\":{d}}}", .{
        counts.total,
        counts.implemented_codec,
        counts.partial,
        counts.planned,
        counts.reserved_diagnostic,
    });
    try out.appendSlice(gpa, ",\"entries\":[");
    for (protocol.known_message_ids, 0..) |id, index| {
        const entry = try entryFor(id);
        if (index != 0) try out.append(gpa, ',');
        try out.print(gpa, "{{\"id\":\"0x{x:0>4}\",\"status\":", .{id});
        try appendJsonString(gpa, out, statusName(entry.status));
        try out.appendSlice(gpa, ",\"domain\":");
        try appendJsonString(gpa, out, domainName(entry.domain));
        try out.appendSlice(gpa, ",\"name\":");
        try appendJsonString(gpa, out, entry.name);
        try out.appendSlice(gpa, ",\"evidence_or_gap\":");
        try appendJsonString(gpa, out, entry.evidence_or_gap);
        try out.append(gpa, '}');
    }
    try out.appendSlice(gpa, "]}\n");
}

test "coverage table covers every assigned ID exactly once" {
    try std.testing.expectEqual(protocol.known_message_ids.len, counters().total);
    try std.testing.expectEqual(@as(?[]const u8, null), validateState());
}

test "implemented and planned protocol coverage remain honest" {
    const implemented = entryFor(0x0203) catch unreachable;
    try std.testing.expectEqual(Status.implemented_codec, implemented.status);
    const window_geometry = entryFor(0x0304) catch unreachable;
    try std.testing.expectEqual(Status.implemented_codec, window_geometry.status);
    const zones = entryFor(0x0305) catch unreachable;
    try std.testing.expectEqual(Status.implemented_codec, zones.status);
    const window_face = entryFor(0x0306) catch unreachable;
    try std.testing.expectEqual(Status.implemented_codec, window_face.status);
    const position = entryFor(0x0307) catch unreachable;
    try std.testing.expectEqual(Status.implemented_codec, position.status);
    try std.testing.expectError(error.UnknownMessageId, entryFor(0xffff));
}

test "protocol coverage manifest is deterministic" {
    const gpa = std.testing.allocator;
    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(gpa);
    try writeManifest(gpa, &first);
    try writeManifest(gpa, &second);
    try std.testing.expectEqualSlices(u8, first.items, second.items);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"planned\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.items, "\"domain\":\"frame\"") != null);
}
