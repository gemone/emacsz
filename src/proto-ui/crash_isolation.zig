//! Adapter-only process-isolation gate for hostile EUP frontend inputs.
//!
//! The parent builds one deterministic corpus, passes each bounded input to a
//! child image of itself, and requires either a clean machine-readable handled
//! result or the one controlled nonzero frontend simulation.  This proves
//! frontend-process containment only; it says nothing about inherited Emacs
//! internals and does not enable any runtime.

const std = @import("std");
const protocol = @import("protocol.zig");
const frontend = @import("frontend.zig");

pub const default_seed: u64 = 0x7021;
pub const max_input_bytes: usize = 8 * 1024;
pub const max_corpus_cases: usize = 64;
pub const child_timeout_seconds: u32 = 10;

pub const Family = enum {
    raw_eup_envelope,
    frame_update_payload,
    resource_snapshot,
    string_resource,
    face_resource,
    font_resource,
    image_resource,
    frontend_scene_apply,
    controlled_frontend_failure,

    pub fn name(self: Family) []const u8 {
        return @tagName(self);
    }
};

pub const Mutation = enum {
    valid,
    truncated,
    trailing,
    stale_generation,
    malformed_utf8,
    invalid_reserved,
    duplicate,
    oversized,

    pub fn name(self: Mutation) []const u8 {
        return @tagName(self);
    }
};

pub const Action = enum {
    decode_envelope,
    decode_frame_update,
    decode_snapshot,
    decode_string,
    decode_face,
    decode_font,
    decode_image,
    apply_scene,
};

pub const Case = struct {
    index: u16,
    family: Family,
    mutation: Mutation,
    action: Action,
    input: []const u8,
};

pub const Corpus = struct {
    cases: [max_corpus_cases]Case = undefined,
    len: usize = 0,

    pub fn slice(self: *const Corpus) []const Case {
        return self.cases[0..self.len];
    }
};

pub const Options = struct {
    seed: u64 = default_seed,
};

pub const ParseError = error{
    MissingOptionValue,
    UnknownOption,
    SeedOutOfRange,
    InvalidChildMode,
};

pub const ChildMode = struct {
    case_index: u16,
    simulate_crash: bool,
};

pub const ChildStatus = enum {
    accepted,
    handled,
};

pub const ParentOutcome = enum {
    clean_handled,
    simulated_frontend_failure,
    unexpected,

    pub fn name(self: ParentOutcome) []const u8 {
        return @tagName(self);
    }
};

pub const Summary = struct {
    seed: u64,
    total_cases: usize,
    clean_handled_cases: usize,
    simulated_frontend_failure_cases: usize,
    failed_checks: usize,

    pub fn result(self: Summary) []const u8 {
        return if (self.failed_checks == 0) "pass" else "fail";
    }
};

fn putU32(bytes: []u8, offset: usize, value: u32) void {
    if (offset + 4 <= bytes.len)
        std.mem.writeInt(u32, bytes[offset..][0..4], value, .little);
}

fn envelope(
    a: std.mem.Allocator,
    payload: []const u8,
    message_type: u16,
    sequence: u64,
    frame_id: u32,
    out: *std.ArrayList(u8),
) !void {
    try protocol.encodeEnvelope(a, .{
        .flags = if (message_type == protocol.Message.frame_update) protocol.Flags.delta else 0,
        .message_type = message_type,
        .sequence = sequence,
        .ack_sequence = 0,
        .session_id = 0x1001,
        .frame_id = frame_id,
        .timestamp_ns = sequence,
    }, payload, out);
}

fn owned(a: std.mem.Allocator, list: *std.ArrayList(u8)) ![]const u8 {
    defer list.deinit(a);
    return try a.dupe(u8, list.items);
}

fn facePayload() protocol.FaceDefine {
    return .{
        .face_id = 51,
        .generation = 3,
        .presence = .{ .foreground = true, .background = true, .box_color = true },
        .foreground = .{ 8, 16, 24, 255 },
        .background = .{ 32, 40, 48, 255 },
        .box_color = .{ 32, 40, 48, 255 },
        .underline = .single,
        .box = .simple,
        .box_line_width = 1,
    };
}

fn fontPayload() protocol.FontDefine {
    var family = [_]u8{0} ** protocol.max_font_family_bytes;
    var foundry = [_]u8{0} ** protocol.max_font_foundry_bytes;
    var style = [_]u8{0} ** protocol.max_font_style_bytes;
    @memcpy(family[0..7], "Adaptor");
    @memcpy(foundry[0..1], "Z");
    @memcpy(style[0..7], "Regular");
    return .{
        .font_id = 61,
        .generation = 4,
        .foundry = foundry,
        .foundry_len = 1,
        .family = family,
        .family_len = 7,
        .style = style,
        .style_len = 7,
        .slant = .roman,
        .spacing = .mono,
        .scalable = true,
        .fixed_pitch = true,
        .pixel_size = 16,
        .point_size_tenths = 120,
        .x_dpi = 96,
        .y_dpi = 96,
        .ascent = 12,
        .descent = 4,
        .line_height = 16,
        .average_advance = 8,
        .space_advance = 8,
        .max_advance = 10,
        .min_advance = 6,
        .underline_position = 2,
        .underline_thickness = 1,
    };
}

fn imageMetadata() protocol.ImageDefine {
    return .{
        .image_id = 71,
        .generation = 5,
        .width = 1,
        .height = 1,
        .total_byte_count = 4,
    };
}

fn imagePayload(a: std.mem.Allocator) ![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(a);
    try protocol.encodeImageDefine(a, imageMetadata(), &list);
    try list.appendSlice(a, &.{ 1, 2, 3, 4 });
    return owned(a, &list);
}

fn sceneCreate(a: std.mem.Allocator, sequence: u64) ![]const u8 {
    var payload = [_]u8{
        0, 0, 0, 0,
        1, 0, 0, 0,
    };
    std.mem.writeInt(u32, payload[0..4], 7, .little);
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(a);
    try envelope(a, &payload, protocol.Message.frame_create, sequence, 7, &list);
    return owned(a, &list);
}

fn sceneValidUpdate(a: std.mem.Allocator, sequence: u64) ![]const u8 {
    const header: protocol.FrameUpdateHeader = .{
        .frame_id = 7,
        .frame_generation = 1,
        .sequence = sequence,
        .redisplay_generation = 2,
        .logical_x = 0,
        .logical_y = 0,
        .logical_width = 20,
        .logical_height = 10,
        .physical_x = 0,
        .physical_y = 0,
        .physical_width = 40,
        .physical_height = 20,
        .scale = 2,
        .dpi_x = 96,
        .dpi_y = 96,
        .damage_mode = 2,
        .update_cause = 1,
        .coalesced_count = 0,
        .timestamp_ns = sequence,
    };
    var windows: std.ArrayList(u8) = .empty;
    defer windows.deinit(a);
    var rows: std.ArrayList(u8) = .empty;
    defer rows.deinit(a);
    var damage: std.ArrayList(u8) = .empty;
    defer damage.deinit(a);
    try frontend.encodeWindow(a, .{ .id = 7, .frame_id = 7, .x = 0, .y = 0, .width = 20, .height = 10 }, &windows);
    try frontend.encodeRow(a, .{ .window_id = 7, .index = 0, .flags = 0, .x = 0, .y = 0, .width = 20, .height = 10, .ascent = 7, .descent = 3, .baseline = 7, .visible_height = 10 }, &rows);
    try frontend.encodeRect(a, .{ .x = 0, .y = 0, .width = 20, .height = 10 }, &damage);
    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = windows.items },
        .{ .kind = protocol.SectionKind.rows, .records = rows.items },
        .{ .kind = protocol.SectionKind.damage, .records = damage.items },
    };
    var payload: std.ArrayList(u8) = .empty;
    defer payload.deinit(a);
    try protocol.encodeFrameUpdate(a, .{ .header = header, .sections = &sections }, &payload);
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(a);
    try envelope(a, payload.items, protocol.Message.frame_update, sequence, 7, &list);
    return owned(a, &list);
}

fn appendCase(
    corpus: *Corpus,
    a: std.mem.Allocator,
    family: Family,
    mutation: Mutation,
    action: Action,
    input: []const u8,
) !void {
    if (corpus.len == max_corpus_cases) return error.CorpusTooLarge;
    if (input.len == 0 or input.len > max_input_bytes) return error.CaseInputOutOfRange;
    corpus.cases[corpus.len] = .{
        .index = @intCast(corpus.len),
        .family = family,
        .mutation = mutation,
        .action = action,
        .input = try a.dupe(u8, input),
    };
    corpus.len += 1;
}

fn transformed(
    a: std.mem.Allocator,
    source: []const u8,
    action: Action,
    mutation: Mutation,
) ![]const u8 {
    switch (mutation) {
        .valid => return a.dupe(u8, source),
        .truncated => {
            if (source.len < 2) return error.CaseInputOutOfRange;
            return a.dupe(u8, source[0 .. source.len - 1]);
        },
        .trailing => {
            const result = try a.alloc(u8, source.len + 1);
            @memcpy(result[0..source.len], source);
            result[source.len] = 0;
            return result;
        },
        .stale_generation => {
            const result = try a.dupe(u8, source);
            if (result.len < 8) return error.CaseInputOutOfRange;
            const generation = std.mem.readInt(u32, result[4..8], .little);
            putU32(result, 4, if (generation > 1) generation - 1 else 0);
            return result;
        },
        .malformed_utf8 => {
            const result = try a.dupe(u8, source);
            if (result.len < 13) return error.CaseInputOutOfRange;
            result[result.len - 1] = 0xff;
            return result;
        },
        .invalid_reserved => {
            const result = try a.dupe(u8, source);
            if (result.len < 1) return error.CaseInputOutOfRange;
            result[result.len - 1] = 0xa5;
            return result;
        },
        .duplicate => {
            // The first snapshot entry is face metadata plus its 16-byte
            // envelope.  Repeating that exact wire record while increasing the
            // count builds the duplicate shape the decoder must reject.
            const record_bytes = protocol.snapshot_entry_size + protocol.face_record_size;
            if (source.len < 8 + record_bytes) return error.CaseInputOutOfRange;
            const result = try a.alloc(u8, source.len + record_bytes);
            @memcpy(result[0..source.len], source);
            std.mem.writeInt(u32, result[4..8], 2, .little);
            @memcpy(result[source.len..], source[8..][0..record_bytes]);
            return result;
        },
        .oversized => {
            const result = try a.dupe(u8, source);
            if (result.len < 12) return error.CaseInputOutOfRange;
            // Snapshot count lives at offset 4; variable-length resource
            // payloads put their length at offset 8.
            const length_offset: usize = if (action == .decode_snapshot) 4 else 8;
            putU32(result, length_offset, std.math.maxInt(u32));
            return result;
        },
    }
}

/// Fixed order is part of the gate's contract.  The first eight records are
/// valid baselines across every decoder/Scene family; the remaining records
/// cover every requested hostile class while preserving decoder identity.
pub fn buildCorpus(a: std.mem.Allocator) !Corpus {
    var corpus: Corpus = .{};
    errdefer corpus = .{};

    var raw: std.ArrayList(u8) = .empty;
    defer raw.deinit(a);
    try envelope(a, "ok", protocol.Message.hello, 1, 0, &raw);
    const raw_bytes = try a.dupe(u8, raw.items);

    const frame_header: protocol.FrameUpdateHeader = .{
        .frame_id = 7,
        .frame_generation = 7,
        .sequence = 9,
        .redisplay_generation = 11,
        .logical_x = 0,
        .logical_y = 0,
        .logical_width = 20,
        .logical_height = 10,
        .physical_x = 0,
        .physical_y = 0,
        .physical_width = 40,
        .physical_height = 20,
        .scale = 2,
        .dpi_x = 96,
        .dpi_y = 96,
        .damage_mode = 2,
        .update_cause = 0,
        .coalesced_count = 0,
        .timestamp_ns = 9,
    };
    const resource_record = [_]u8{
        @intFromEnum(protocol.ResourceKind.font), 0, 0, 0,
        7,                                        0, 0, 0,
        1,                                        0, 0, 0,
        0,                                        0, 0, 0,
    };
    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.resources, .records = &resource_record },
    };
    var frame: std.ArrayList(u8) = .empty;
    defer frame.deinit(a);
    try protocol.encodeFrameUpdate(a, .{ .header = frame_header, .sections = &sections }, &frame);
    const frame_bytes = try a.dupe(u8, frame.items);

    const font = try protocol.encodeFontDefineBytes(fontPayload());
    const image = try imagePayload(a);
    var snapshot_entries = [_]protocol.ResourceSnapshotEntry{
        .{ .kind = .face, .status = .live, .resource_id = 51, .generation = 3, .payload = &try protocol.encodeFaceDefineBytes(facePayload()) },
        .{ .kind = .font, .status = .live, .resource_id = 61, .generation = 4, .payload = &font },
        .{ .kind = .string, .status = .live, .resource_id = 81, .generation = 6, .payload = "ok" },
        .{ .kind = .image, .status = .live, .resource_id = 71, .generation = 5, .payload = image },
    };
    var snapshot: std.ArrayList(u8) = .empty;
    defer snapshot.deinit(a);
    try protocol.encodeResourceSnapshot(a, .{ .entries = &snapshot_entries }, &snapshot);
    const snapshot_bytes = try a.dupe(u8, snapshot.items);

    var string: std.ArrayList(u8) = .empty;
    defer string.deinit(a);
    try protocol.encodeStringDefine(a, .{ .resource_id = 81, .generation = 6, .bytes = "ok" }, &string);
    const string_bytes = try a.dupe(u8, string.items);

    const face = try protocol.encodeFaceDefineBytes(facePayload());
    const face_bytes = try a.dupe(u8, &face);
    const font_bytes = try a.dupe(u8, &font);
    const image_bytes = try a.dupe(u8, image);
    const scene_create = try sceneCreate(a, 1);
    const scene_update = try sceneValidUpdate(a, 2);

    const baselines = [_]struct { family: Family, action: Action, bytes: []const u8 }{
        .{ .family = .raw_eup_envelope, .action = .decode_envelope, .bytes = raw_bytes },
        .{ .family = .frame_update_payload, .action = .decode_frame_update, .bytes = frame_bytes },
        .{ .family = .resource_snapshot, .action = .decode_snapshot, .bytes = snapshot_bytes },
        .{ .family = .string_resource, .action = .decode_string, .bytes = string_bytes },
        .{ .family = .face_resource, .action = .decode_face, .bytes = face_bytes },
        .{ .family = .font_resource, .action = .decode_font, .bytes = font_bytes },
        .{ .family = .image_resource, .action = .decode_image, .bytes = image_bytes },
        .{ .family = .frontend_scene_apply, .action = .apply_scene, .bytes = scene_update },
    };
    for (baselines) |baseline| {
        try appendCase(&corpus, a, baseline.family, .valid, baseline.action, baseline.bytes);
    }

    const hostile = [_]struct { family: Family, action: Action, bytes: []const u8, mutation: Mutation }{
        .{ .family = .raw_eup_envelope, .action = .decode_envelope, .bytes = raw_bytes, .mutation = .truncated },
        .{ .family = .frame_update_payload, .action = .decode_frame_update, .bytes = frame_bytes, .mutation = .trailing },
        .{ .family = .resource_snapshot, .action = .decode_snapshot, .bytes = snapshot_bytes, .mutation = .duplicate },
        .{ .family = .resource_snapshot, .action = .decode_snapshot, .bytes = snapshot_bytes, .mutation = .oversized },
        .{ .family = .string_resource, .action = .decode_string, .bytes = string_bytes, .mutation = .malformed_utf8 },
        .{ .family = .string_resource, .action = .decode_string, .bytes = string_bytes, .mutation = .oversized },
        .{ .family = .face_resource, .action = .decode_face, .bytes = face_bytes, .mutation = .invalid_reserved },
        .{ .family = .face_resource, .action = .decode_face, .bytes = face_bytes, .mutation = .stale_generation },
        .{ .family = .font_resource, .action = .decode_font, .bytes = font_bytes, .mutation = .stale_generation },
        .{ .family = .font_resource, .action = .decode_font, .bytes = font_bytes, .mutation = .truncated },
        .{ .family = .image_resource, .action = .decode_image, .bytes = image_bytes, .mutation = .truncated },
        .{ .family = .image_resource, .action = .decode_image, .bytes = image_bytes, .mutation = .invalid_reserved },
        .{ .family = .frontend_scene_apply, .action = .apply_scene, .bytes = scene_create, .mutation = .invalid_reserved },
        .{ .family = .frontend_scene_apply, .action = .apply_scene, .bytes = scene_update, .mutation = .stale_generation },
        .{ .family = .frontend_scene_apply, .action = .apply_scene, .bytes = scene_update, .mutation = .truncated },
    };
    for (hostile) |case| {
        const bytes = try transformed(a, case.bytes, case.action, case.mutation);
        try appendCase(&corpus, a, case.family, case.mutation, case.action, bytes);
    }

    try appendCase(&corpus, a, .controlled_frontend_failure, .valid, .decode_envelope, raw_bytes);
    return corpus;
}

/// Unit-test and child entry point.  Non-OOM protocol/Scene errors are the
/// expected, contained result; `OutOfMemory` always escapes.
pub fn executeCaseInput(a: std.mem.Allocator, case_item: Case) !ChildStatus {
    switch (case_item.action) {
        .decode_envelope => {
            _ = protocol.decodeEnvelope(case_item.input) catch |err| return contained(err);
        },
        .decode_frame_update => {
            var update = protocol.decodeFrameUpdate(a, case_item.input) catch |err| return contained(err);
            defer protocol.freeFrameUpdate(a, &update);
        },
        .decode_snapshot => {
            var snapshot = protocol.decodeResourceSnapshot(a, case_item.input) catch |err| return contained(err);
            defer protocol.freeResourceSnapshot(a, &snapshot);
        },
        .decode_string => {
            _ = protocol.decodeStringDefine(case_item.input) catch |err| return contained(err);
        },
        .decode_face => {
            _ = protocol.decodeFaceDefine(case_item.input) catch |err| return contained(err);
        },
        .decode_font => {
            _ = protocol.decodeFontDefine(case_item.input) catch |err| return contained(err);
        },
        .decode_image => {
            _ = protocol.decodeImageDefine(case_item.input) catch |err| return contained(err);
        },
        .apply_scene => {
            var scene = frontend.Scene.init(a);
            defer scene.deinit();
            scene.apply(case_item.input) catch |err| return contained(err);
        },
    }
    return .accepted;
}

fn contained(err: anyerror) std.mem.Allocator.Error!ChildStatus {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    return .handled;
}

fn parseU64(text: []const u8) ParseError!u64 {
    return std.fmt.parseInt(u64, text, 10) catch error.SeedOutOfRange;
}

pub fn parseOptions(arguments: []const []const u8, defaults: Options) ParseError!Options {
    var options = defaults;
    var index: usize = 0;
    while (index < arguments.len) : (index += 1) {
        const argument = arguments[index];
        if (std.mem.startsWith(u8, argument, "--seed=")) {
            const parsed = try parseU64(argument["--seed=".len..]);
            if (parsed == 0) return error.SeedOutOfRange;
            options.seed = parsed;
        } else if (std.mem.eql(u8, argument, "--seed")) {
            index += 1;
            if (index >= arguments.len) return error.MissingOptionValue;
            const parsed = try parseU64(arguments[index]);
            if (parsed == 0) return error.SeedOutOfRange;
            options.seed = parsed;
        } else return error.UnknownOption;
    }
    return options;
}

pub fn parseChildMode(arguments: []const []const u8) ParseError!?ChildMode {
    var mode: ?ChildMode = null;
    var simulate = false;
    for (arguments) |argument| {
        if (std.mem.startsWith(u8, argument, "--crash-child=")) {
            const index = std.fmt.parseInt(u16, argument["--crash-child=".len..], 10) catch
                return error.InvalidChildMode;
            if (mode != null) return error.InvalidChildMode;
            mode = .{ .case_index = index, .simulate_crash = false };
        } else if (std.mem.eql(u8, argument, "--simulate-crash")) {
            if (simulate) return error.InvalidChildMode;
            simulate = true;
        } else if (std.mem.startsWith(u8, argument, "--seed=")) {
            // Child mode preserves parent-option compatibility; seed does not
            // affect the fixed corpus.
        } else if (std.mem.startsWith(u8, argument, "--input-hex=")) {
            // accepted in child mode; the parent parser owns validation
        } else return error.UnknownOption;
    }
    if (simulate) {
        var selected = mode orelse return error.InvalidChildMode;
        selected.simulate_crash = true;
        mode = selected;
    }
    return mode;
}

pub fn hexEncode(a: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const characters = "0123456789abcdef";
    const result = try a.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |byte, index| {
        result[index * 2] = characters[byte >> 4];
        result[index * 2 + 1] = characters[byte & 0x0f];
    }
    return result;
}

pub fn hexDecode(a: std.mem.Allocator, text: []const u8) ![]u8 {
    if (text.len == 0 or text.len % 2 != 0 or text.len > max_input_bytes * 2)
        return error.InvalidChildMode;
    const result = try a.alloc(u8, text.len / 2);
    errdefer a.free(result);
    var offset: usize = 0;
    while (offset < text.len) : (offset += 2) {
        result[offset / 2] = std.fmt.parseInt(u8, text[offset..][0..2], 16) catch
            return error.InvalidChildMode;
    }
    return result;
}

pub fn classifyChild(case_item: Case, term: std.process.Child.Term, stdout: []const u8) ParentOutcome {
    const expected_controlled = case_item.family == .controlled_frontend_failure;
    switch (term) {
        .exited => |code| {
            if (expected_controlled) {
                return if (code == 75 and stdout.len == 0) .simulated_frontend_failure else .unexpected;
            }
            if (code != 0) return .unexpected;
            if (!std.mem.startsWith(u8, stdout, "{\"kind\":\"proto-ui-crash-child\"")) return .unexpected;
            if (!std.mem.endsWith(u8, stdout, "\"result\":\"pass\"}\n")) return .unexpected;
            return .clean_handled;
        },
        else => return .unexpected,
    }
}

pub fn aggregate(seed: u64, outcomes: []const ParentOutcome) Summary {
    var summary = Summary{
        .seed = seed,
        .total_cases = outcomes.len,
        .clean_handled_cases = 0,
        .simulated_frontend_failure_cases = 0,
        .failed_checks = 0,
    };
    for (outcomes) |outcome| {
        switch (outcome) {
            .clean_handled => summary.clean_handled_cases += 1,
            .simulated_frontend_failure => summary.simulated_frontend_failure_cases += 1,
            .unexpected => summary.failed_checks += 1,
        }
    }
    if (outcomes.len == 0 or summary.clean_handled_cases + summary.simulated_frontend_failure_cases != outcomes.len)
        summary.failed_checks += 1;
    if (summary.simulated_frontend_failure_cases != 1 or summary.clean_handled_cases == 0)
        summary.failed_checks += 1;
    return summary;
}

fn writeChildReport(io: std.Io, status: ChildStatus) !void {
    const message = switch (status) {
        .accepted => "{\"kind\":\"proto-ui-crash-child\",\"status\":\"accepted\",\"result\":\"pass\"}\n",
        .handled => "{\"kind\":\"proto-ui-crash-child\",\"status\":\"handled\",\"result\":\"pass\"}\n",
    };
    try std.Io.File.stdout().writeStreamingAll(io, message);
}

fn runChild(io: std.Io, case_index: u16, input_hex: []const u8, simulate: bool) !void {
    if (case_index >= max_corpus_cases) return error.InvalidChildMode;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const corpus = try buildCorpus(a);
    if (case_index >= corpus.len) return error.InvalidChildMode;
    const item = corpus.cases[case_index];
    const actual_hex = try hexEncode(a, item.input);
    if (!std.mem.eql(u8, actual_hex, input_hex)) return error.InvalidChildMode;
    if (simulate) std.process.exit(75);
    try writeChildReport(io, try executeCaseInput(a, item));
}

fn spawnChild(
    gpa: std.mem.Allocator,
    io: std.Io,
    self_path: []const u8,
    item: Case,
) !struct { term: std.process.Child.Term, stdout: []u8, stderr: []u8 } {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const temporary = arena.allocator();
    const case_arg = try std.fmt.allocPrint(temporary, "--crash-child={d}", .{item.index});
    const input_hex = try hexEncode(temporary, item.input);
    const input_arg = try std.fmt.allocPrint(temporary, "--input-hex={s}", .{input_hex});
    var argv = [_][]const u8{ self_path, case_arg, input_arg, "" };
    var argv_len: usize = 3;
    if (item.family == .controlled_frontend_failure) {
        argv[3] = "--simulate-crash";
        argv_len = 4;
    }
    const result = std.process.run(gpa, io, .{
        .argv = argv[0..argv_len],
        .stdout_limit = .limited(4 * 1024),
        .stderr_limit = .limited(16 * 1024),
        .timeout = .{ .duration = .{ .raw = std.Io.Duration.fromSeconds(child_timeout_seconds), .clock = .awake } },
    }) catch |err| {
        std.debug.print("crash-isolation: spawn failed: {s}\n", .{@errorName(err)});
        return error.ChildSpawnFailed;
    };
    return .{ .term = result.term, .stdout = result.stdout, .stderr = result.stderr };
}

fn runParent(gpa: std.mem.Allocator, io: std.Io, self_path: []const u8, options: Options) !Summary {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const corpus = try buildCorpus(a);
    const outcomes = try a.alloc(ParentOutcome, corpus.len);
    for (corpus.slice(), outcomes) |item, *outcome| {
        const child = try spawnChild(gpa, io, self_path, item);
        defer gpa.free(child.stdout);
        defer gpa.free(child.stderr);
        outcome.* = classifyChild(item, child.term, child.stdout);
        if (outcome.* == .unexpected) {
            std.debug.print(
                "crash-isolation: case {d} ({s}/{s}) failed: term={any}, stdout={d} bytes, stderr={s}\n",
                .{ item.index, item.family.name(), item.mutation.name(), child.term, child.stdout.len, child.stderr },
            );
        }
    }
    return aggregate(options.seed, outcomes);
}

fn writeParentSummary(io: std.Io, summary: Summary) !void {
    var buffer: [512]u8 = undefined;
    const message = try std.fmt.bufPrint(&buffer,
        \\{{"summary":"proto-ui-crash-isolation","seed":{d},"total_cases":{d},"clean_handled_cases":{d},"simulated_frontend_failure_cases":{d},"failed_checks":{d},"result":"{s}"}}
        \\
    , .{
        summary.seed,
        summary.total_cases,
        summary.clean_handled_cases,
        summary.simulated_frontend_failure_cases,
        summary.failed_checks,
        summary.result(),
    });
    try std.Io.File.stdout().writeStreamingAll(io, message);
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var iterator = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer iterator.deinit();
    const argv0 = iterator.next() orelse return error.MissingExecutablePath;

    var arguments: std.ArrayList([]const u8) = .empty;
    defer arguments.deinit(gpa);
    while (iterator.next()) |argument| try arguments.append(gpa, argument);

    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();

    if (try parseChildMode(arguments.items)) |mode| {
        var input_hex: []const u8 = "";
        for (arguments.items) |argument| {
            if (std.mem.startsWith(u8, argument, "--input-hex="))
                input_hex = argument["--input-hex=".len..];
        }
        try runChild(io, mode.case_index, input_hex, mode.simulate_crash);
        return;
    }

    const options = try parseOptions(arguments.items, .{});
    const self_path = try gpa.dupe(u8, argv0);
    defer gpa.free(self_path);
    const summary = try runParent(gpa, io, self_path, options);
    try writeParentSummary(io, summary);
    if (summary.failed_checks != 0) std.process.exit(1);
}

test "corpus is ordered bounded and covers all required families and mutations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const corpus = try buildCorpus(arena.allocator());
    try std.testing.expect(corpus.len > 16 and corpus.len < max_corpus_cases);
    const cases = corpus.slice();
    for (cases, 0..) |item, index| {
        try std.testing.expectEqual(index, item.index);
        try std.testing.expect(item.input.len > 0 and item.input.len <= max_input_bytes);
        if (index != 0) try std.testing.expect(item.index > cases[index - 1].index);
    }
    inline for (@typeInfo(Family).@"enum".fields) |field| {
        const family: Family = @enumFromInt(field.value);
        var found = false;
        for (cases) |item| found = found or item.family == family;
        try std.testing.expect(found);
    }
    inline for (@typeInfo(Mutation).@"enum".fields) |field| {
        const mutation: Mutation = @enumFromInt(field.value);
        var found = false;
        for (cases) |item| found = found or item.mutation == mutation;
        try std.testing.expect(found);
    }
}

test "child mode parser requires a case and supports one controlled crash" {
    try std.testing.expectEqual(@as(?ChildMode, null), try parseChildMode(&.{"--seed=1"}));
    try std.testing.expectEqual(
        ChildMode{ .case_index = 4, .simulate_crash = false },
        (try parseChildMode(&.{"--crash-child=4"})).?,
    );
    try std.testing.expectEqual(
        ChildMode{ .case_index = 7, .simulate_crash = true },
        (try parseChildMode(&.{ "--crash-child=7", "--simulate-crash" })).?,
    );
    try std.testing.expectError(error.InvalidChildMode, parseChildMode(&.{"--simulate-crash"}));
    try std.testing.expectError(error.InvalidChildMode, parseChildMode(&.{ "--crash-child=1", "--crash-child=2" }));
    try std.testing.expectError(error.UnknownOption, parseChildMode(&.{"--bogus"}));
}

test "parent options enforce seed bounds" {
    try std.testing.expectEqual(Options{}, try parseOptions(&.{}, .{}));
    try std.testing.expectEqual(@as(u64, 9), (try parseOptions(&.{"--seed=9"}, .{})).seed);
    try std.testing.expectError(error.SeedOutOfRange, parseOptions(&.{"--seed=0"}, .{}));
    try std.testing.expectError(error.MissingOptionValue, parseOptions(&.{"--seed"}, .{}));
}

test "hex transfer round trips and rejects malformed or oversized input" {
    const a = std.testing.allocator;
    const original = "EUP1\x00\xff";
    const encoded = try hexEncode(a, original);
    defer a.free(encoded);
    const decoded = try hexDecode(a, encoded);
    defer a.free(decoded);
    try std.testing.expectEqualSlices(u8, original, decoded);
    try std.testing.expectError(error.InvalidChildMode, hexDecode(a, "0"));
    try std.testing.expectError(error.InvalidChildMode, hexDecode(a, "zz"));
    try std.testing.expectError(error.InvalidChildMode, hexDecode(a, "0" ** ((max_input_bytes + 1) * 2)));
}

test "every corpus case is accepted or cleanly handled without leaks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const corpus = try buildCorpus(arena.allocator());
    for (corpus.slice()) |item| {
        if (item.family == .controlled_frontend_failure) continue;
        _ = try executeCaseInput(arena.allocator(), item);
    }
}

test "aggregate requires exactly one contained simulation and no unexpected cases" {
    const outcomes = [_]ParentOutcome{
        .clean_handled, .clean_handled, .simulated_frontend_failure,
    };
    const summary = aggregate(77, &outcomes);
    try std.testing.expectEqual(@as(usize, 3), summary.total_cases);
    try std.testing.expectEqual(@as(usize, 2), summary.clean_handled_cases);
    try std.testing.expectEqual(@as(usize, 1), summary.simulated_frontend_failure_cases);
    try std.testing.expectEqual(@as(usize, 0), summary.failed_checks);
    try std.testing.expectEqualStrings("pass", summary.result());

    const crash_only = [_]ParentOutcome{.simulated_frontend_failure};
    try std.testing.expect(aggregate(77, &crash_only).failed_checks > 0);
    const unexpected = [_]ParentOutcome{ .clean_handled, .simulated_frontend_failure, .unexpected };
    try std.testing.expect(aggregate(77, &unexpected).failed_checks == 2);
}

test "classification distinguishes clean reports from controlled nonzero exit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const corpus = try buildCorpus(arena.allocator());
    const normal = corpus.cases[0];
    const controlled = corpus.cases[corpus.len - 1];
    const report = "{\"kind\":\"proto-ui-crash-child\",\"status\":\"handled\",\"result\":\"pass\"}\n";
    try std.testing.expectEqual(ParentOutcome.clean_handled, classifyChild(normal, .{ .exited = 0 }, report));
    try std.testing.expectEqual(ParentOutcome.simulated_frontend_failure, classifyChild(controlled, .{ .exited = 75 }, ""));
    try std.testing.expectEqual(ParentOutcome.unexpected, classifyChild(normal, .{ .exited = 1 }, report));
    try std.testing.expectEqual(ParentOutcome.unexpected, classifyChild(controlled, .{ .exited = 0 }, report));
    try std.testing.expectEqual(ParentOutcome.unexpected, classifyChild(normal, .{ .signal = @enumFromInt(6) }, report));
}
