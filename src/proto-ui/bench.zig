//! Opt-in adapter-only hot-path benchmark evidence.
//!
//! The harness exercises real EUP/Scene/CaptureService/transport adapters on
//! synthetic display facts.  It does not connect to Emacs, register a
//! terminal, enable output_proto, touch SDL, or use timing to decide success.

const std = @import("std");
const builtin = @import("builtin");
const adapter = @import("adapter.zig");
const capture_service = @import("capture_service.zig");
const frame_service = @import("frame_service.zig");
const frontend = @import("frontend.zig");
const lifecycle = @import("lifecycle.zig");
const protocol = @import("protocol.zig");
const terminal = @import("terminal.zig");
const transport = @import("transport.zig");

const schema_version: u32 = 1;
const logical_width: i32 = 960;
const logical_height: i32 = 600;
const row_count: usize = 30;
const row_height: i32 = 20;
const text_columns: usize = 100;

pub const Error = error{
    IterationsOutOfRange,
    WarmupOutOfRange,
    UnknownScenario,
    UnknownBenchOption,
    MissingOptionValue,
    InvalidNumber,
    InvalidStatistic,
    ClockResolutionInsufficient,
};

pub const Scenario = enum {
    eup_encode,
    envelope_decode_validate,
    scene_apply_fresh,
    capture_atomic_encode,
    memory_sink_send,

    pub fn name(self: Scenario) []const u8 {
        return @tagName(self);
    }

    pub const all = [_]Scenario{
        .eup_encode,
        .envelope_decode_validate,
        .scene_apply_fresh,
        .capture_atomic_encode,
        .memory_sink_send,
    };
};

pub const Options = struct {
    iterations: u32 = 512,
    warmup: u32 = 32,
    scenario: ?Scenario = null,
};

pub const min_iterations: u32 = 1;
pub const max_iterations: u32 = 100_000;
pub const min_warmup: u32 = 0;
pub const max_warmup: u32 = 10_000;

const CountingAllocator = struct {
    base: std.mem.Allocator,
    allocations: u64 = 0,
    vtable: std.mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    },

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &self.vtable };
    }

    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        const bytes = self.base.rawAlloc(len, alignment, ret_addr);
        if (bytes != null) self.allocations += 1;
        return bytes;
    }

    fn resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        return self.base.rawResize(memory, alignment, new_len, ret_addr);
    }

    fn remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        return self.base.rawRemap(memory, alignment, new_len, ret_addr);
    }

    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(context));
        self.base.rawFree(memory, alignment, ret_addr);
    }
};

const Fixture = struct {
    allocator: std.mem.Allocator,
    windows: []u8,
    rows: []u8,
    cursor: []u8,
    damage: []u8,
    text: []u8,
    update_payload: []u8,
    create_message: []u8,
    update_message: []u8,

    fn deinit(self: *Fixture) void {
        const a = self.allocator;
        a.free(self.windows);
        a.free(self.rows);
        a.free(self.cursor);
        a.free(self.damage);
        a.free(self.text);
        a.free(self.update_payload);
        a.free(self.create_message);
        a.free(self.update_message);
    }

    fn header() protocol.FrameUpdateHeader {
        return .{
            .frame_id = 301,
            .frame_generation = 1,
            .sequence = 2,
            .redisplay_generation = 1,
            .logical_x = 0,
            .logical_y = 0,
            .logical_width = logical_width,
            .logical_height = logical_height,
            .physical_x = 0,
            .physical_y = 0,
            .physical_width = logical_width,
            .physical_height = logical_height,
            .scale = 1.0,
            .dpi_x = 96.0,
            .dpi_y = 96.0,
            .damage_mode = 1,
            .update_cause = 1,
            .coalesced_count = 0,
            .timestamp_ns = 42,
        };
    }

    fn validate(self: *const Fixture) !void {
        const payload = try protocol.decodeEnvelope(self.update_message);
        if (payload.envelope.message_type != protocol.Message.frame_update) return error.InvalidFixture;
        if (!std.mem.eql(u8, self.update_payload, payload.bytes)) return error.InvalidFixture;
        const update = try protocol.decodeFrameUpdate(self.allocator, payload.bytes);
        defer self.allocator.free(update.sections);
        try protocol.validateFrameEnvelope(update.header, payload.envelope);
        if (!std.meta.eql(update.header, header())) return error.InvalidFixture;
        if (update.sections.len != 5) return error.InvalidFixture;
        if (self.rows.len / frontend.row_record_size != row_count) return error.InvalidFixture;
    }
};

fn buildFixture(a: std.mem.Allocator) !Fixture {
    var windows: std.ArrayList(u8) = .empty;
    errdefer windows.deinit(a);
    var rows: std.ArrayList(u8) = .empty;
    errdefer rows.deinit(a);
    var cursor: std.ArrayList(u8) = .empty;
    errdefer cursor.deinit(a);
    var damage: std.ArrayList(u8) = .empty;
    errdefer damage.deinit(a);
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(a);

    try frontend.encodeWindow(a, .{
        .id = 10,
        .frame_id = 301,
        .x = 0,
        .y = 0,
        .width = logical_width,
        .height = logical_height,
    }, &windows);

    for (0..row_count) |index| {
        const y: i32 = @intCast(index * @as(usize, @intCast(row_height)));
        try frontend.encodeRow(a, .{
            .window_id = 10,
            .index = @intCast(index + 1),
            .flags = 0,
            .x = 0,
            .y = y,
            .width = logical_width,
            .height = row_height,
            .ascent = 16,
            .descent = 4,
            .baseline = 16,
            .visible_height = row_height,
        }, &rows);
    }

    try frontend.encodeCursor(a, .{
        .window_id = 10,
        .x = 8,
        .y = 0,
        .width = 2,
        .height = row_height,
        .kind = 1,
        .visible = true,
        .active = true,
    }, &cursor);

    try frontend.encodeRect(a, .{
        .x = 0,
        .y = row_height,
        .width = logical_width,
        .height = row_height,
    }, &damage);

    var line: [text_columns]u8 = undefined;
    for (0..row_count) |index| {
        for (&line, 0..) |*byte, column| {
            byte.* = 'a' + @as(u8, @intCast((index + column) % 26));
        }
        try frontend.encodeTextLine(a, .{
            .row_index = @intCast(index),
            .line = &line,
        }, &text);
    }

    const sections = [_]protocol.Section{
        .{ .kind = protocol.SectionKind.windows, .records = windows.items },
        .{ .kind = protocol.SectionKind.rows, .records = rows.items },
        .{ .kind = protocol.SectionKind.cursors, .records = cursor.items },
        .{ .kind = protocol.SectionKind.damage, .records = damage.items },
        .{ .kind = protocol.SectionKind.extension_min, .records = text.items },
    };

    var update_payload: std.ArrayList(u8) = .empty;
    errdefer update_payload.deinit(a);
    try protocol.encodeFrameUpdate(a, .{ .header = Fixture.header(), .sections = &sections }, &update_payload);

    var create_message: std.ArrayList(u8) = .empty;
    errdefer create_message.deinit(a);
    var create_id: [4]u8 = undefined;
    var create_generation: [4]u8 = undefined;
    std.mem.writeInt(u32, &create_id, 301, .little);
    std.mem.writeInt(u32, &create_generation, 1, .little);
    const create_bytes = create_id ++ create_generation;
    try protocol.encodeEnvelope(a, .{
        .flags = 0,
        .message_type = protocol.Message.frame_create,
        .sequence = 1,
        .ack_sequence = 0,
        .session_id = 77,
        .frame_id = 301,
        .timestamp_ns = 1,
    }, &create_bytes, &create_message);

    var update_message: std.ArrayList(u8) = .empty;
    errdefer update_message.deinit(a);
    try protocol.encodeEnvelope(a, .{
        .flags = protocol.Flags.delta | protocol.Flags.requires_ack,
        .message_type = protocol.Message.frame_update,
        .sequence = 2,
        .ack_sequence = 0,
        .session_id = 77,
        .frame_id = 301,
        .timestamp_ns = 42,
    }, update_payload.items, &update_message);

    var result: Fixture = .{
        .allocator = a,
        .windows = undefined,
        .rows = undefined,
        .cursor = undefined,
        .damage = undefined,
        .text = undefined,
        .update_payload = undefined,
        .create_message = undefined,
        .update_message = undefined,
    };
    result.windows = try windows.toOwnedSlice(a);
    errdefer a.free(result.windows);
    result.rows = try rows.toOwnedSlice(a);
    errdefer a.free(result.rows);
    result.cursor = try cursor.toOwnedSlice(a);
    errdefer a.free(result.cursor);
    result.damage = try damage.toOwnedSlice(a);
    errdefer a.free(result.damage);
    result.text = try text.toOwnedSlice(a);
    errdefer a.free(result.text);
    result.update_payload = try update_payload.toOwnedSlice(a);
    errdefer a.free(result.update_payload);
    result.create_message = try create_message.toOwnedSlice(a);
    errdefer a.free(result.create_message);
    result.update_message = try update_message.toOwnedSlice(a);
    return result;
}

const BenchHost = struct {
    generation: u64 = 1,

    fn table(self: *BenchHost) adapter.HostV1 {
        return .{
            .context = self,
            .read_generation = readGeneration,
            .read_geometry = readGeometry,
            .read_frame_state = readFrameState,
        };
    }

    fn readGeneration(context: *anyopaque, object_id: u64) callconv(.c) u64 {
        _ = object_id;
        const self: *BenchHost = @ptrCast(@alignCast(context));
        return self.generation;
    }

    fn readGeometry(context: *anyopaque, object_id: u64, geometry: *adapter.Geometry) callconv(.c) u8 {
        _ = context;
        _ = object_id;
        geometry.* = .{ .x = 0, .y = 0, .width = logical_width, .height = logical_height };
        return 1;
    }

    fn readFrameState(context: *anyopaque, frame_id: u64, frame_state: *adapter.FrameState) callconv(.c) u8 {
        _ = context;
        _ = frame_id;
        frame_state.* = .{
            .generation = 1,
            .visibility = @intFromEnum(adapter.FrameVisibility.visible),
            .focused = 1,
        };
        return 1;
    }
};

const CaptureRig = struct {
    allocator: std.mem.Allocator,
    host: BenchHost = .{},
    host_table: adapter.HostV1 = undefined,
    terminals: terminal.TerminalRegistry = .{},
    frames: lifecycle.FrameRegistry = .{},
    runtime: *adapter.Runtime,
    service: frame_service.FrameService,
    capture: capture_service.CaptureService,

    fn create(allocator: std.mem.Allocator) !*CaptureRig {
        const rig = try allocator.create(CaptureRig);
        errdefer allocator.destroy(rig);
        rig.* = .{
            .allocator = allocator,
            .host_table = undefined,
            .runtime = undefined,
            .service = undefined,
            .capture = undefined,
        };
        rig.host_table = rig.host.table();
        try rig.terminals.create(1, terminal.initial_generation);
        _ = try rig.terminals.activate(1, terminal.initial_generation);
        rig.runtime = try allocator.create(adapter.Runtime);
        errdefer allocator.destroy(rig.runtime);
        rig.runtime.* = try adapter.Runtime.init(allocator, &rig.host_table);
        errdefer rig.runtime.deinit();
        rig.service = try frame_service.FrameService.init(
            rig.runtime,
            &rig.frames,
            &rig.terminals,
            1,
        );
        _ = try rig.service.register(101, 301);
        rig.capture = capture_service.CaptureService.init(&rig.service);
        return rig;
    }

    fn deinit(self: *CaptureRig) void {
        self.runtime.deinit();
        self.allocator.destroy(self.runtime);
    }

    fn runCapture(self: *CaptureRig) ![]u8 {
        try self.capture.begin(101);
        try self.capture.captureWindow(10);
        for (0..row_count) |index| {
            const y: i32 = @intCast(index * @as(usize, @intCast(row_height)));
            try self.capture.captureRow(.{
                .window_id = 10,
                .index = @intCast(index + 1),
                .x = 0,
                .y = y,
                .width = logical_width,
                .height = row_height,
                .ascent = 16,
                .descent = 4,
                .baseline = 16,
                .visible_height = row_height,
            });
        }
        try self.capture.captureCursor(.{
            .window_id = 10,
            .x = 8,
            .y = 0,
            .width = 2,
            .height = row_height,
            .kind = 1,
            .visible = true,
            .active = true,
        });
        try self.capture.captureDamage(.{
            .x = 0,
            .y = row_height,
            .width = logical_width,
            .height = row_height,
        });
        return self.capture.encodePending(.{
            .sequence = 2,
            .session_id = 77,
            .timestamp_ns = 42,
        });
    }
};

pub const Stats = struct {
    p50_ns: u64,
    p95_ns: u64,
    p99_ns: u64,
    mean_ns: f64,
};

pub fn percentile(sorted: []const u64, percent: f64) Error!u64 {
    if (sorted.len == 0) return Error.InvalidStatistic;
    if (!std.math.isFinite(percent) or percent < 0.0 or percent > 100.0)
        return Error.InvalidStatistic;
    const rank = (percent / 100.0) * @as(f64, @floatFromInt(sorted.len));
    const rounded = @ceil(rank);
    if (!std.math.isFinite(rounded) or rounded < 1.0 or rounded > @as(f64, @floatFromInt(sorted.len)))
        return Error.InvalidStatistic;
    const index: usize = @intFromFloat(rounded - 1.0);
    return sorted[index];
}

pub fn statistics(samples: []const u64) Error!Stats {
    if (samples.len == 0) return Error.InvalidStatistic;
    const sorted = std.heap.page_allocator.dupe(u64, samples) catch return Error.InvalidStatistic;
    defer std.heap.page_allocator.free(sorted);
    std.mem.sort(u64, sorted, {}, std.sort.asc(u64));
    var total: u128 = 0;
    for (samples) |sample| {
        total += sample;
    }
    const mean = @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(samples.len));
    if (!std.math.isFinite(mean) or mean <= 0.0) return Error.ClockResolutionInsufficient;
    return .{
        .p50_ns = try percentile(sorted, 50.0),
        .p95_ns = try percentile(sorted, 95.0),
        .p99_ns = try percentile(sorted, 99.0),
        .mean_ns = mean,
    };
}

pub fn throughput(bytes_per_op: u64, mean_ns: f64) Error!struct { ops_per_second: f64, mib_per_second: f64 } {
    if (bytes_per_op == 0 or !std.math.isFinite(mean_ns) or mean_ns <= 0.0)
        return Error.InvalidStatistic;
    const ops_per_second = std.time.ns_per_s / mean_ns;
    if (!std.math.isFinite(ops_per_second) or ops_per_second <= 0.0)
        return Error.InvalidStatistic;
    const bytes_per_op_f64: f64 = @floatFromInt(bytes_per_op);
    const mib_per_second = ops_per_second * bytes_per_op_f64 / (1024.0 * 1024.0);
    if (!std.math.isFinite(mib_per_second) or mib_per_second < 0.0)
        return Error.InvalidStatistic;
    return .{ .ops_per_second = ops_per_second, .mib_per_second = mib_per_second };
}

pub fn parseOptions(arguments: []const []const u8, defaults: Options) Error!Options {
    var result = defaults;
    var index: usize = 0;
    while (index < arguments.len) : (index += 1) {
        const argument = arguments[index];
        var option_name: []const u8 = "";
        var value: []const u8 = "";
        if (std.mem.startsWith(u8, argument, "--iterations=")) {
            option_name = "iterations";
            value = argument["--iterations=".len..];
        } else if (std.mem.eql(u8, argument, "--iterations")) {
            if (index + 1 >= arguments.len) return Error.MissingOptionValue;
            index += 1;
            option_name = "iterations";
            value = arguments[index];
        } else if (std.mem.startsWith(u8, argument, "--warmup=")) {
            option_name = "warmup";
            value = argument["--warmup=".len..];
        } else if (std.mem.eql(u8, argument, "--warmup")) {
            if (index + 1 >= arguments.len) return Error.MissingOptionValue;
            index += 1;
            option_name = "warmup";
            value = arguments[index];
        } else if (std.mem.startsWith(u8, argument, "--scenario=")) {
            const scenario_value = argument["--scenario=".len..];
            result.scenario = std.meta.stringToEnum(Scenario, scenario_value) orelse return Error.UnknownScenario;
            continue;
        } else if (std.mem.eql(u8, argument, "--scenario")) {
            if (index + 1 >= arguments.len) return Error.MissingOptionValue;
            index += 1;
            result.scenario = std.meta.stringToEnum(Scenario, arguments[index]) orelse return Error.UnknownScenario;
            continue;
        } else return Error.UnknownBenchOption;

        const parsed = std.fmt.parseInt(u32, value, 10) catch return Error.InvalidNumber;
        if (std.mem.eql(u8, option_name, "iterations")) {
            if (parsed < min_iterations or parsed > max_iterations) return Error.IterationsOutOfRange;
            result.iterations = parsed;
        } else if (std.mem.eql(u8, option_name, "warmup")) {
            if (parsed < min_warmup or parsed > max_warmup) return Error.WarmupOutOfRange;
            result.warmup = parsed;
        }
    }
    return result;
}

const Outcome = struct {
    bytes: u64,
};

fn monotonicNs(io: std.Io, start: std.Io.Timestamp) Error!u64 {
    const end = std.Io.Clock.awake.now(io);
    const duration = start.durationTo(end);
    if (duration.nanoseconds < 0) return Error.InvalidStatistic;
    const value = duration.toNanoseconds();
    if (value < 0 or value > std.math.maxInt(u64)) return Error.InvalidStatistic;
    return @intCast(value);
}

const BenchContext = struct {
    fixture: *Fixture,
    counter: *CountingAllocator,
    output: *std.ArrayList(u8),
    sink: *transport.MemorySink,
    capture_rig: ?*CaptureRig,
    operation_index: u64,
};

fn runScenarioOperation(context: BenchContext, scenario: Scenario) !Outcome {
    const a = context.counter.allocator();
    switch (scenario) {
        .eup_encode => {
            context.output.clearRetainingCapacity();
            try protocol.encodeEnvelope(a, .{
                .flags = protocol.Flags.delta | protocol.Flags.requires_ack,
                .message_type = protocol.Message.frame_update,
                .sequence = 2,
                .ack_sequence = 0,
                .session_id = 77,
                .frame_id = 301,
                .timestamp_ns = 42,
            }, context.fixture.update_payload, context.output);
            return .{ .bytes = context.output.items.len };
        },
        .envelope_decode_validate => {
            const payload = try protocol.decodeEnvelope(context.fixture.update_message);
            var update = try protocol.decodeFrameUpdate(a, payload.bytes);
            defer protocol.freeFrameUpdate(a, &update);
            try protocol.validateFrameEnvelope(update.header, payload.envelope);
            return .{ .bytes = context.fixture.update_message.len };
        },
        .scene_apply_fresh => {
            var scene = frontend.Scene.init(a);
            defer scene.deinit();
            try scene.apply(context.fixture.create_message);
            try scene.apply(context.fixture.update_message);
            return .{
                .bytes = context.fixture.create_message.len + context.fixture.update_message.len,
            };
        },
        .capture_atomic_encode => {
            const rig = context.capture_rig.?;
            const encoded = try rig.runCapture();
            rig.runtime.allocator.free(encoded);
            rig.capture.cancel();
            return .{ .bytes = encoded.len };
        },
        .memory_sink_send => {
            const message = try context.sink.send(.{
                .flags = protocol.Flags.delta | protocol.Flags.requires_ack,
                .message_type = protocol.Message.frame_update,
                .sequence = transport.max_retained_messages + context.operation_index + 1,
                .ack_sequence = 0,
                .session_id = 77,
                .frame_id = 301,
                .timestamp_ns = 42,
            }, context.fixture.update_payload);
            return .{ .bytes = message.len };
        },
    }
}

pub const ScenarioResult = struct {
    scenario: Scenario,
    iterations: u32,
    warmup: u32,
    successful_operations: u32,
    bytes_per_op: u64,
    stats: Stats,
    allocations_per_op: ?f64,
};

pub fn measureScenario(
    allocator: std.mem.Allocator,
    io: std.Io,
    scenario: Scenario,
    options: Options,
) !ScenarioResult {
    var counter = CountingAllocator{ .base = allocator };
    const a = counter.allocator();
    var fixture = try buildFixture(a);
    defer fixture.deinit();
    try fixture.validate();

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(a);
    var sink = transport.MemorySink.init(a);
    defer sink.deinit();
    const capture_rig: ?*CaptureRig = if (scenario == .capture_atomic_encode)
        try CaptureRig.create(a)
    else
        null;
    defer if (capture_rig) |rig| {
        rig.deinit();
        a.destroy(rig);
    };

    const latencies = try allocator.alloc(u64, options.iterations);
    defer allocator.free(latencies);
    var successful: u32 = 0;
    var bytes_per_op: u64 = 0;
    var allocation_total: u64 = 0;

    // Pre-fill the sink so every timed send measures steady-state bounded
    // eviction instead of initial growth.
    if (scenario == .memory_sink_send) {
        for (0..transport.max_retained_messages) |index| {
            _ = try sink.send(.{
                .flags = protocol.Flags.delta | protocol.Flags.requires_ack,
                .message_type = protocol.Message.frame_update,
                .sequence = index + 1,
                .ack_sequence = 0,
                .session_id = 77,
                .frame_id = 301,
                .timestamp_ns = 42,
            }, fixture.update_payload);
        }
    }

    const total: u64 = @as(u64, options.iterations) + options.warmup;
    for (0..total) |index| {
        counter.allocations = 0;
        const context = BenchContext{
            .fixture = &fixture,
            .counter = &counter,
            .output = &output,
            .sink = &sink,
            .capture_rig = capture_rig,
            .operation_index = index,
        };
        const start = std.Io.Clock.awake.now(io);
        const outcome = try runScenarioOperation(context, scenario);
        const elapsed = try monotonicNs(io, start);
        if (index >= options.warmup) {
            const sample_index = index - options.warmup;
            latencies[sample_index] = elapsed;
            if (bytes_per_op == 0) {
                bytes_per_op = outcome.bytes;
            } else if (bytes_per_op != outcome.bytes) {
                return error.WorkloadByteCountChanged;
            }
            allocation_total += counter.allocations;
            successful += 1;
        }
    }

    if (successful != options.iterations) return error.OperationCountMismatch;
    const stats = try statistics(latencies);
    const throughput_values = try throughput(bytes_per_op, stats.mean_ns);
    _ = throughput_values;
    const allocations_per_op: ?f64 = @as(f64, @floatFromInt(allocation_total)) /
        @as(f64, @floatFromInt(options.iterations));
    return .{
        .scenario = scenario,
        .iterations = options.iterations,
        .warmup = options.warmup,
        .successful_operations = successful,
        .bytes_per_op = bytes_per_op,
        .stats = stats,
        .allocations_per_op = allocations_per_op,
    };
}

fn writeNumber(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: f64) !void {
    const rendered = try std.fmt.allocPrint(allocator, "{d}", .{value});
    defer allocator.free(rendered);
    try out.appendSlice(allocator, rendered);
}

pub fn writeReport(
    allocator: std.mem.Allocator,
    options: Options,
    results: []const ScenarioResult,
    out: *std.ArrayList(u8),
) !void {
    if (results.len == 0) return error.EmptyReport;
    try out.appendSlice(allocator, "{\"schema_version\":");
    try out.print(allocator, "{d}", .{schema_version});
    try out.appendSlice(allocator, ",\"kind\":\"proto-ui-adapter-hotpath-benchmark\",\"protocol\":{\"name\":\"EUP\",\"version\":\"1.0\"},\"transport\":\"memory\",\"renderer_tier\":\"not-applicable\",\"optimization_mode\":\"");
    try out.appendSlice(allocator, @tagName(builtin.mode));
    try out.appendSlice(allocator, "\",\"iterations\":");
    try out.print(allocator, "{d}", .{options.iterations});
    try out.appendSlice(allocator, ",\"warmup\":");
    try out.print(allocator, "{d}", .{options.warmup});
    try out.appendSlice(allocator, ",\"result\":\"pass\",\"scenarios\":[");
    for (results, 0..) |result, index| {
        if (index != 0) try out.appendSlice(allocator, ",");
        if (result.successful_operations != result.iterations) return error.OperationCountMismatch;
        const rates = try throughput(result.bytes_per_op, result.stats.mean_ns);
        try out.appendSlice(allocator, "{\"name\":\"");
        try out.appendSlice(allocator, result.scenario.name());
        try out.appendSlice(allocator, "\",\"iterations\":");
        try out.print(allocator, "{d}", .{result.iterations});
        try out.appendSlice(allocator, ",\"warmup\":");
        try out.print(allocator, "{d}", .{result.warmup});
        try out.appendSlice(allocator, ",\"successful_operations\":");
        try out.print(allocator, "{d}", .{result.successful_operations});
        try out.appendSlice(allocator, ",\"bytes_per_op\":");
        try out.print(allocator, "{d}", .{result.bytes_per_op});
        try out.appendSlice(allocator, ",\"latency_ns\":{\"p50\":");
        try out.print(allocator, "{d}", .{result.stats.p50_ns});
        try out.appendSlice(allocator, ",\"p95\":");
        try out.print(allocator, "{d}", .{result.stats.p95_ns});
        try out.appendSlice(allocator, ",\"p99\":");
        try out.print(allocator, "{d}", .{result.stats.p99_ns});
        try out.appendSlice(allocator, ",\"mean\":");
        try writeNumber(out, allocator, result.stats.mean_ns);
        try out.appendSlice(allocator, "},\"ops_per_second\":");
        try writeNumber(out, allocator, rates.ops_per_second);
        try out.appendSlice(allocator, ",\"mib_per_second\":");
        try writeNumber(out, allocator, rates.mib_per_second);
        try out.appendSlice(allocator, ",\"allocation_count_op\":");
        if (result.allocations_per_op) |value| {
            try writeNumber(out, allocator, value);
        } else {
            try out.appendSlice(allocator, "null");
        }
        try out.appendSlice(allocator, ",\"transport\":\"memory\",\"renderer_tier\":\"not-applicable\",\"result\":\"pass\"}");
    }
    try out.appendSlice(allocator, "]}\n");
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const allocator = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();

    var iterator = try std.process.Args.Iterator.initAllocator(minimal.args, allocator);
    defer iterator.deinit();
    _ = iterator.next();
    var arguments: std.ArrayList([]const u8) = .empty;
    defer arguments.deinit(allocator);
    while (iterator.next()) |argument| try arguments.append(allocator, argument);
    const options = try parseOptions(arguments.items, .{});

    var results: std.ArrayList(ScenarioResult) = .empty;
    defer results.deinit(allocator);
    const scenarios = if (options.scenario) |scenario| &[_]Scenario{scenario} else &Scenario.all;
    for (scenarios) |scenario| {
        try results.append(allocator, try measureScenario(allocator, io, scenario, options));
    }

    var report: std.ArrayList(u8) = .empty;
    defer report.deinit(allocator);
    try writeReport(allocator, options, results.items, &report);
    try std.Io.File.stdout().writeStreamingAll(io, report.items);
}

test "fixture has realistic bounded sections and round trips" {
    const a = std.testing.allocator;
    var fixture = try buildFixture(a);
    defer fixture.deinit();
    try fixture.validate();
    try std.testing.expectEqual(@as(usize, 1), fixture.windows.len / frontend.window_record_size);
    try std.testing.expectEqual(row_count, fixture.rows.len / frontend.row_record_size);
    try std.testing.expectEqual(@as(usize, 1), fixture.cursor.len / frontend.cursor_record_size);
    try std.testing.expectEqual(@as(usize, 1), fixture.damage.len / frontend.damage_record_size);
    try std.testing.expect(fixture.text.len > row_count * text_columns);
}

test "fixture workloads are byte-identical and scene application is correct" {
    const a = std.testing.allocator;
    var first = try buildFixture(a);
    defer first.deinit();
    var second = try buildFixture(a);
    defer second.deinit();
    try std.testing.expectEqualSlices(u8, first.update_message, second.update_message);
    try std.testing.expectEqualSlices(u8, first.create_message, second.create_message);

    var scene = frontend.Scene.init(a);
    defer scene.deinit();
    try scene.apply(first.create_message);
    try scene.apply(first.update_message);
    try std.testing.expectEqual(@as(u64, 1), scene.stats.frame_updates);
    try std.testing.expectEqual(@as(usize, 1), scene.windows.items.len);
    try std.testing.expectEqual(row_count, scene.rows.items.len);
    try std.testing.expectEqual(row_count, scene.text.items.len);
    try std.testing.expectEqual(@as(usize, 1), scene.damage.items.len);
    try std.testing.expect(scene.cursor != null);
}

test "capture fixture encodes a deterministic atomic batch" {
    const a = std.testing.allocator;
    const rig = try CaptureRig.create(a);
    defer a.destroy(rig);
    defer rig.deinit();
    const first = try rig.runCapture();
    defer a.free(first);
    rig.capture.cancel();
    try rig.capture.begin(101);
    try std.testing.expectError(error.CaptureIncomplete, rig.capture.encodePending(.{
        .sequence = 3,
        .session_id = 77,
        .timestamp_ns = 43,
    }));
    rig.capture.cancel();

    const rig_two = try CaptureRig.create(a);
    defer a.destroy(rig_two);
    defer rig_two.deinit();
    const second = try rig_two.runCapture();
    defer a.free(second);
    try std.testing.expectEqualSlices(u8, first, second);
}

test "percentiles nearest-rank and throughput calculations validate inputs" {
    const samples = [_]u64{ 10, 20, 30, 40 };
    const sorted = try std.heap.page_allocator.dupe(u64, &samples);
    defer std.heap.page_allocator.free(sorted);
    try std.testing.expectEqual(@as(u64, 20), try percentile(sorted, 50));
    try std.testing.expectEqual(@as(u64, 40), try percentile(sorted, 95));
    try std.testing.expectEqual(@as(u64, 40), try percentile(sorted, 99));
    try std.testing.expectError(Error.InvalidStatistic, percentile(sorted, -0.1));
    try std.testing.expectError(Error.InvalidStatistic, percentile(sorted, 100.1));

    const stats = [_]u64{ 1_000, 2_000, 3_000 };
    const result = try statistics(&stats);
    try std.testing.expectEqual(@as(u64, 2_000), result.p50_ns);
    try std.testing.expectApproxEqAbs(@as(f64, 2_000), result.mean_ns, 0.001);

    const rates = try throughput(1_048_576, 1_000);
    try std.testing.expectEqual(@as(f64, 1_000_000), rates.ops_per_second);
    try std.testing.expectEqual(@as(f64, 1_000_000), rates.mib_per_second);
    try std.testing.expectError(Error.InvalidStatistic, throughput(0, 1));
    try std.testing.expectError(Error.InvalidStatistic, throughput(1, 0));
}

test "CLI parsing accepts equals/separate forms and enforces bounds" {
    const combined = try parseOptions(&.{ "--iterations=512", "--warmup=32", "--scenario=capture_atomic_encode" }, .{});
    try std.testing.expectEqual(@as(u32, 512), combined.iterations);
    try std.testing.expectEqual(@as(u32, 32), combined.warmup);
    try std.testing.expectEqual(Scenario.capture_atomic_encode, combined.scenario.?);

    const separate = try parseOptions(&.{ "--iterations", "1024", "--warmup", "64", "--scenario", "memory_sink_send" }, .{});
    try std.testing.expectEqual(@as(u32, 1024), separate.iterations);
    try std.testing.expectEqual(@as(u32, 64), separate.warmup);
    try std.testing.expectEqual(Scenario.memory_sink_send, separate.scenario.?);

    try std.testing.expectError(Error.IterationsOutOfRange, parseOptions(&.{"--iterations=0"}, .{}));
    try std.testing.expectError(Error.IterationsOutOfRange, parseOptions(&.{"--iterations=100001"}, .{}));
    try std.testing.expectError(Error.WarmupOutOfRange, parseOptions(&.{"--warmup=10001"}, .{}));
    try std.testing.expectError(Error.UnknownScenario, parseOptions(&.{"--scenario=nope"}, .{}));
    try std.testing.expectError(Error.UnknownBenchOption, parseOptions(&.{"--network"}, .{}));
    try std.testing.expectError(Error.MissingOptionValue, parseOptions(&.{"--iterations"}, .{}));
}

test "scenario registration covers all requested hot paths" {
    try std.testing.expectEqual(@as(usize, 5), Scenario.all.len);
    inline for (Scenario.all) |scenario| {
        try std.testing.expect(scenario.name().len > 0);
    }
}

test "short measurement run reports all operations and bounded JSON" {
    const a = std.testing.allocator;
    var io_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_threaded.io();
    var results: std.ArrayList(ScenarioResult) = .empty;
    defer results.deinit(a);
    const options: Options = .{ .iterations = 2, .warmup = 1 };
    for (Scenario.all) |scenario| {
        try results.append(a, try measureScenario(a, io, scenario, options));
    }
    var report: std.ArrayList(u8) = .empty;
    defer report.deinit(a);
    try writeReport(a, options, results.items, &report);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "\"result\":\"pass\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "\"transport\":\"memory\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "\"renderer_tier\":\"not-applicable\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, report.items, "\"optimization_mode\":\"") != null);
}
