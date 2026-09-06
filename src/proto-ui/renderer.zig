//! Renderer selection policy shared by the SDL3 frontend and tests.

const std = @import("std");

pub const Request = union(enum) {
    auto,
    software,
    gpu,
    named: []const u8,
};

pub const Tier = enum {
    software,
    basic,
    advanced,
};

pub const PresentMode = enum {
    off,
    on,
    adaptive,
};

pub fn parseRequest(value: []const u8) ?Request {
    if (std.mem.eql(u8, value, "auto")) return .auto;
    if (std.mem.eql(u8, value, "software")) return .software;
    if (std.mem.eql(u8, value, "gpu")) return .gpu;
    if (value.len == 0) return null;
    return .{ .named = value };
}

pub fn parsePresentMode(value: []const u8) ?PresentMode {
    if (std.mem.eql(u8, value, "off")) return .off;
    if (std.mem.eql(u8, value, "on")) return .on;
    if (std.mem.eql(u8, value, "adaptive")) return .adaptive;
    return null;
}

pub fn requestName(request: Request) []const u8 {
    return switch (request) {
        .auto => "auto",
        .software => "software",
        .gpu => "gpu",
        .named => |name| name,
    };
}

pub fn candidates(request: Request) []const ?[]const u8 {
    return switch (request) {
        .auto => &.{null},
        .software => &.{"software"},
        // An explicit GPU request falls back to software so headless and
        // GPU-less machines retain a usable frontend. A named driver is an
        // operator override and deliberately fails if unavailable.
        .gpu => &.{ "gpu", "software" },
        .named => |name| &.{name},
    };
}

pub fn classify(name: []const u8) Tier {
    if (std.ascii.eqlIgnoreCase(name, "software")) return .software;
    if (std.ascii.eqlIgnoreCase(name, "gpu")) return .advanced;
    const gpu_names = [_][]const u8{
        "opengl",   "opengles2",  "opengles",   "metal", "vulkan",
        "direct3d", "direct3d11", "direct3d12",
    };
    for (gpu_names) |gpu_name| {
        if (std.ascii.eqlIgnoreCase(name, gpu_name)) return .basic;
    }
    return .basic;
}

pub fn vsyncNumber(mode: PresentMode) i32 {
    return switch (mode) {
        .off => 0,
        .adaptive => -1,
        .on => 1,
    };
}

test "parses renderer and present requests" {
    try std.testing.expectEqual(Request.auto, parseRequest("auto").?);
    try std.testing.expectEqual(Request.software, parseRequest("software").?);
    try std.testing.expectEqual(Request.gpu, parseRequest("gpu").?);
    try std.testing.expectEqualStrings("vulkan", parseRequest("vulkan").?.named);
    try std.testing.expectEqual(@as(?Request, null), parseRequest(""));
    try std.testing.expectEqualStrings("bogus-policy", parseRequest("bogus-policy").?.named);

    try std.testing.expectEqual(PresentMode.off, parsePresentMode("off").?);
    try std.testing.expectEqual(PresentMode.on, parsePresentMode("on").?);
    try std.testing.expectEqual(PresentMode.adaptive, parsePresentMode("adaptive").?);
    try std.testing.expectEqual(@as(?PresentMode, null), parsePresentMode("sometimes"));
}

test "gpu selection has explicit software fallback" {
    const auto_candidates = candidates(.auto);
    try std.testing.expectEqual(@as(usize, 1), auto_candidates.len);
    try std.testing.expectEqual(@as(?[]const u8, null), auto_candidates[0]);

    const gpu_candidates = candidates(.gpu);
    try std.testing.expectEqualStrings("gpu", gpu_candidates[0].?);
    try std.testing.expectEqualStrings("software", gpu_candidates[1].?);

    const named_candidates = candidates(.{ .named = "vulkan" });
    try std.testing.expectEqualStrings("vulkan", named_candidates[0].?);
}

test "classifies SDL renderer names into capability tiers" {
    try std.testing.expectEqual(Tier.software, classify("software"));
    try std.testing.expectEqual(Tier.advanced, classify("GPU"));
    try std.testing.expectEqual(Tier.basic, classify("opengl"));
    try std.testing.expectEqual(Tier.basic, classify("Direct3D12"));
    try std.testing.expectEqual(Tier.basic, classify("future-driver"));
}
