//! Audits the real native Linux glibc temacs link graph.
//!
//! The gate is part of the R8 link dependency: it rejects the build unless the
//! selected adapter-owned static candidate's forced ABI symbol exists in the
//! linked ELF.  Presence in the symbol table is linkage evidence only; it is
//! not initialization, terminal registration, output_proto enablement, or
//! runtime availability.

const std = @import("std");
const adapter_linkage = @import("r8_adapter_linkage.zig");
const runtime = @import("runtime.zig");

const Error = error{
    AdapterSymbolMissing,
    InvalidElf,
    InvalidLinkageTarget,
};

fn hashFile(
    gpa: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    path: []const u8,
) ![]const u8 {
    const data = try cwd.readFileAlloc(io, path, gpa, .limited(128 * 1024 * 1024));
    defer gpa.free(data);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    const hex = try gpa.alloc(u8, 64);
    @memcpy(hex, &std.fmt.bytesToHex(digest, .lower));
    return hex;
}

fn findSymbol(
    gpa: std.mem.Allocator,
    io: std.Io,
    cwd: std.Io.Dir,
    elf_path: []const u8,
    symbol_name: []const u8,
) !?struct { value: u64, size: u64 } {
    const file = try cwd.openFile(io, elf_path, .{});
    defer file.close(io);
    const search_paths = std.debug.ElfFile.DebugInfoSearchPaths.native(elf_path);
    var elf_file = try std.debug.ElfFile.load(gpa, io, file, null, &search_paths);
    defer elf_file.deinit(gpa);

    if (!elf_file.is_64 or elf_file.endian != .little) return Error.InvalidElf;
    const symtab = elf_file.symtab orelse return Error.InvalidElf;
    const strtab = elf_file.strtab orelse return Error.InvalidElf;
    if (symtab.entry_size != @sizeOf(std.elf.Elf64_Sym)) return Error.InvalidElf;
    const symbols: []align(1) const std.elf.Elf64_Sym = @ptrCast(symtab.bytes);

    for (symbols) |symbol| {
        if (symbol.st_name == 0 or symbol.st_name >= strtab.len) continue;
        if (symbol.st_type() != @intFromEnum(std.elf.STT.FUNC)) continue;
        if (symbol.st_bind() != @intFromEnum(std.elf.STB.GLOBAL)) continue;
        const name = std.mem.sliceTo(strtab[symbol.st_name..], 0);
        if (!std.mem.eql(u8, name, symbol_name)) continue;
        if (symbol.st_shndx == std.elf.SHN_UNDEF) continue;
        if (symbol.st_size == 0) continue;
        return .{ .value = symbol.st_value, .size = symbol.st_size };
    }
    return null;
}

fn writeAuditManifest(
    gpa: std.mem.Allocator,
    out: *std.ArrayList(u8),
    target: []const u8,
    symbol_name: []const u8,
    symbol_value: u64,
    symbol_size: u64,
    adapter_hash: []const u8,
    abi_hash: []const u8,
) !void {
    try out.appendSlice(gpa, "{\"manifest_version\":1,\"kind\":\"proto-ui-r8-link-audit\",");
    try out.appendSlice(gpa, "\"status\":\"linked_not_registered\",\"linked\":true,");
    try out.print(gpa, "\"registered\":false,\"runtime_available\":false,\"target\":\"{s}\",", .{target});
    try out.appendSlice(gpa, "\"linkage\":\"static_archive_forced_undefined\",");
    try out.print(gpa, "\"symbol\":\"{s}\",\"symbol_present\":true,", .{symbol_name});
    try out.print(gpa, "\"symbol_value\":{d},\"symbol_size\":{d},", .{ symbol_value, symbol_size });
    try out.appendSlice(gpa, "\"adapter_artifact_sha256\":");
    try runtime.appendJsonStringPublic(gpa, out, adapter_hash);
    try out.appendSlice(gpa, ",\"abi_table_sha256\":");
    try runtime.appendJsonStringPublic(gpa, out, abi_hash);
    try out.appendSlice(gpa, ",\"result\":\"pass\"}\n");
}

pub fn main(minimal: std.process.Init.Minimal) !void {
    const gpa = std.heap.smp_allocator;
    var io_threaded: std.Io.Threaded = .init(gpa, .{});
    const io = io_threaded.io();
    const cwd = std.Io.Dir.cwd();

    var args = try std.process.Args.Iterator.initAllocator(minimal.args, gpa);
    defer args.deinit();
    _ = args.next();

    const temacs = args.next() orelse return error.MissingTemacsArg;
    const adapter = args.next() orelse return error.MissingAdapterArg;
    const output = args.next() orelse return error.MissingOutputArg;
    const target = args.next() orelse return error.MissingTargetArg;
    if (!std.mem.eql(u8, target, adapter_linkage.linked_target))
        return Error.InvalidLinkageTarget;
    if (adapter_linkage.validateLinkedState(true)) |problem| {
        std.debug.print("r8-link audit: {s}\n", .{problem});
        return error.InvalidAdapterLinkageState;
    }

    const symbol = try findSymbol(gpa, io, cwd, temacs, adapter_linkage.linked_symbol);
    if (symbol == null) {
        std.debug.print("r8-link audit: {s} is absent from {s}\n", .{
            adapter_linkage.linked_symbol,
            temacs,
        });
        return Error.AdapterSymbolMissing;
    }
    const adapter_hash = try hashFile(gpa, io, cwd, adapter);
    defer gpa.free(adapter_hash);

    const abi_hash = adapter_linkage.abiTableHash();
    var manifest: std.ArrayList(u8) = .empty;
    defer manifest.deinit(gpa);
    try writeAuditManifest(
        gpa,
        &manifest,
        target,
        adapter_linkage.linked_symbol,
        symbol.?.value,
        symbol.?.size,
        adapter_hash,
        &abi_hash,
    );
    try cwd.writeFile(io, .{ .sub_path = output, .data = manifest.items });

    std.debug.print(
        "{{\"gate\":\"proto-ui-r8-link\",\"status\":\"linked_not_registered\",\"registered\":false,\"runtime_available\":false,\"result\":\"pass\"}}\n",
        .{},
    );
}

test "link audit manifest is deterministic valid JSON" {
    const gpa = std.testing.allocator;
    const hash: [64]u8 = @splat('a');
    var first: std.ArrayList(u8) = .empty;
    defer first.deinit(gpa);
    var second: std.ArrayList(u8) = .empty;
    defer second.deinit(gpa);
    try writeAuditManifest(gpa, &first, "native-linux-gnu", "symbol", 0x1234, 4, &hash, &hash);
    try writeAuditManifest(gpa, &second, "native-linux-gnu", "symbol", 0x1234, 4, &hash, &hash);
    try std.testing.expectEqualSlices(u8, first.items, second.items);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, first.items, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u64, 4), @intCast(parsed.value.object.get("symbol_size").?.integer));
    try std.testing.expect(!parsed.value.object.get("registered").?.bool);
}
