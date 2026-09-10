//! Bounded LRU keying for frontend-owned Unicode text textures.
//!
//! This module deliberately owns cache policy only.  Backend texture creation,
//! rendering, and destruction stay in the SDL frontend; the cache stores an
//! opaque device texture identifier and invokes the supplied destroyer when an
//! entry leaves the cache.

const std = @import("std");
const renderer = @import("renderer.zig");

pub const max_key_bytes: usize = 120;
pub const default_capacity: usize = 64;

pub const Error = error{
    InvalidCacheKey,
    InvalidCachedTexture,
};

pub const DestroyTexture = *const fn (texture_id: usize) void;

pub const CachedTexture = struct {
    texture_id: usize,
    width: f32,
    height: f32,
};

pub const Stats = struct {
    lookups: u64 = 0,
    hits: u64 = 0,
    misses: u64 = 0,
    inserts: u64 = 0,
    updates: u64 = 0,
    evictions: u64 = 0,
    destroys: u64 = 0,
};

pub const Key = struct {
    device: usize,
    color: renderer.Color,
    length: u8,
    bytes: [max_key_bytes]u8 = undefined,

    pub fn init(device: usize, bytes: []const u8, color: renderer.Color) Error!Key {
        if (bytes.len == 0 or bytes.len > max_key_bytes) return Error.InvalidCacheKey;
        var key = Key{
            .device = device,
            .color = color,
            .length = @intCast(bytes.len),
        };
        @memcpy(key.bytes[0..bytes.len], bytes);
        return key;
    }

    pub fn eql(self: Key, other: Key) bool {
        return self.device == other.device and
            std.meta.eql(self.color, other.color) and
            self.length == other.length and
            std.mem.eql(u8, self.bytes[0..self.length], other.bytes[0..other.length]);
    }
};

const Entry = struct {
    key: Key,
    texture_id: usize,
    width: f32,
    height: f32,
    last_use: u64,
};

pub fn Cache(comptime capacity: usize) type {
    if (capacity == 0) @compileError("text cache capacity must be nonzero");

    return struct {
        const Self = @This();

        entries: [capacity]?Entry = [_]?Entry{null} ** capacity,
        clock: u64 = 0,
        stats: Stats = .{},

        pub fn lookup(self: *Self, key: Key) ?CachedTexture {
            self.stats.lookups += 1;
            for (&self.entries) |*entry| {
                const item = entry.* orelse continue;
                if (!item.key.eql(key)) continue;
                self.clock += 1;
                entry.*.?.last_use = self.clock;
                self.stats.hits += 1;
                return .{
                    .texture_id = item.texture_id,
                    .width = item.width,
                    .height = item.height,
                };
            }
            self.stats.misses += 1;
            return null;
        }

        pub fn insert(
            self: *Self,
            key: Key,
            texture_id: usize,
            width: f32,
            height: f32,
            destroy: DestroyTexture,
        ) Error!void {
            if (texture_id == 0 or !std.math.isFinite(width) or !std.math.isFinite(height) or
                width <= 0 or height <= 0) return Error.InvalidCachedTexture;

            self.clock += 1;
            for (&self.entries) |*entry| {
                const item = entry.* orelse continue;
                if (!item.key.eql(key)) continue;
                destroy(item.texture_id);
                self.stats.evictions += 1;
                self.stats.destroys += 1;
                entry.*.?.texture_id = texture_id;
                entry.*.?.width = width;
                entry.*.?.height = height;
                entry.*.?.last_use = self.clock;
                self.stats.updates += 1;
                return;
            }

            var slot: ?usize = null;
            for (&self.entries, 0..) |entry, index| {
                if (entry == null) {
                    slot = index;
                    break;
                }
            }
            if (slot == null) {
                slot = 0;
                for (self.entries[1..], 1..) |entry, index| {
                    if (entry.?.last_use < self.entries[slot.?].?.last_use)
                        slot = index;
                }
                destroy(self.entries[slot.?].?.texture_id);
                self.stats.evictions += 1;
                self.stats.destroys += 1;
            }
            self.entries[slot.?] = .{
                .key = key,
                .texture_id = texture_id,
                .width = width,
                .height = height,
                .last_use = self.clock,
            };
            self.stats.inserts += 1;
        }

        pub fn clear(self: *Self, destroy: DestroyTexture) void {
            for (&self.entries) |*entry| {
                const item = entry.* orelse continue;
                destroy(item.texture_id);
                self.stats.destroys += 1;
                entry.* = null;
            }
            self.clock = 0;
        }
    };
}

pub const TextureCache = Cache(default_capacity);

const Recording = struct {
    var destroyed: [4]usize = undefined;
    var count: usize = 0;
    fn destroy(texture_id: usize) void {
        destroyed[count] = texture_id;
        count += 1;
    }
};

test "cache keys distinguish device color and bounded text" {
    const key = try Key.init(1, "你好", .{ .r = 1, .g = 2, .b = 3, .a = 4 });
    try std.testing.expect(key.eql(try Key.init(1, "你好", .{ .r = 1, .g = 2, .b = 3, .a = 4 })));
    try std.testing.expect(!key.eql(try Key.init(2, "你好", .{ .r = 1, .g = 2, .b = 3, .a = 4 })));
    try std.testing.expect(!key.eql(try Key.init(1, "你好", .{ .r = 3, .g = 2, .b = 3, .a = 4 })));
    try std.testing.expectError(Error.InvalidCacheKey, Key.init(1, "", .{ .r = 1, .g = 2, .b = 3 }));
    const oversized = [_]u8{0} ** (max_key_bytes + 1);
    try std.testing.expectError(Error.InvalidCacheKey, Key.init(1, &oversized, .{ .r = 1, .g = 2, .b = 3 }));
}

test "cache returns the same texture id and records misses then hits" {
    var cache: Cache(2) = .{};
    const key = try Key.init(1, "你好 Emacs", .{ .r = 0xe8, .g = 0xee, .b = 0xf8, .a = 255 });
    try std.testing.expect(cache.lookup(key) == null);
    try cache.insert(key, 0x1000, 32, 16, Recording.destroy);
    const hit = cache.lookup(key) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 0x1000), hit.texture_id);
    try std.testing.expectEqual(@as(f32, 32), hit.width);
    try std.testing.expectEqual(@as(f32, 16), hit.height);
    try std.testing.expectEqual(Stats{ .lookups = 2, .hits = 1, .misses = 1, .inserts = 1 }, cache.stats);
}

test "cache evicts the least recently used texture through the destroyer" {
    Recording.destroyed = [_]usize{0} ** 4;
    Recording.count = 0;

    var cache: Cache(2) = .{};
    const first = try Key.init(1, "first", .{ .r = 1, .g = 2, .b = 3 });
    const second = try Key.init(1, "second", .{ .r = 1, .g = 2, .b = 3 });
    const third = try Key.init(1, "third", .{ .r = 1, .g = 2, .b = 3 });
    try cache.insert(first, 11, 8, 8, Recording.destroy);
    try cache.insert(second, 22, 9, 8, Recording.destroy);
    try std.testing.expect(cache.lookup(first) != null); // make second the LRU entry
    try cache.insert(third, 33, 10, 8, Recording.destroy);
    try std.testing.expectEqual(@as(usize, 22), Recording.destroyed[0]);
    try std.testing.expectEqual(@as(usize, 1), Recording.count);
    try std.testing.expectEqual(@as(u64, 1), cache.stats.evictions);

    cache.clear(Recording.destroy);
    try std.testing.expectEqual(@as(usize, 3), Recording.count);
    try std.testing.expectEqual(@as(u64, 3), cache.stats.destroys);
}

test "cache destroys the old texture when replacing a matching key" {
    Recording.destroyed = [_]usize{0} ** 4;
    Recording.count = 0;

    var cache: Cache(2) = .{};
    const key = try Key.init(1, "replace", .{ .r = 1, .g = 2, .b = 3, .a = 4 });
    try cache.insert(key, 11, 8, 8, Recording.destroy);
    try cache.insert(key, 22, 9, 8, Recording.destroy);
    const cached = cache.lookup(key) orelse return error.TestUnexpectedResult;

    try std.testing.expectEqual(@as(usize, 22), cached.texture_id);
    try std.testing.expectEqual(@as(usize, 11), Recording.destroyed[0]);
    try std.testing.expectEqual(@as(usize, 1), Recording.count);
    try std.testing.expectEqual(@as(u64, 1), cache.stats.updates);
    try std.testing.expectEqual(@as(u64, 1), cache.stats.evictions);
    try std.testing.expectEqual(@as(u64, 1), cache.stats.destroys);
}
