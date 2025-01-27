const elf = @import("src/elf.zig");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        std.debug.print("usage: snip.zig [entrycode] [output]\n", .{});
        return error.BadArguments;
    }

    const fd = try std.fs.cwd().openFile(args[1], .{ .mode = .read_only });
    defer fd.close();

    var elf_header: elf.ElfHdr = undefined;
    var n = try fd.readAll(std.mem.asBytes(&elf_header));
    if (n != @sizeOf(elf.ElfHdr)) {
        std.debug.print("error reading elf header\n", .{});
        return error.InvalidExe;
    }

    var ph: elf.ProgHdr = undefined;
    var off: usize = elf_header.phoff;
    var found = false;

    for (0..elf_header.phnum) |i| {
        try fd.seekTo(off);
        n = try fd.readAll(std.mem.asBytes(&ph));
        if (n != @sizeOf(elf.ProgHdr)) {
            std.debug.print("error reading program header {}\n", .{i});
            return error.ErrIO;
        }
        if (ph.ty != elf.ELF_PROG_LOAD) {
            off += @sizeOf(elf.ProgHdr);
            continue;
        }
        if (found) {
            std.debug.print("program has multiple loadable headers\n", .{});
            return error.InvalidExe;
        }

        // Found relevant program header
        found = true;
        const buf = try allocator.alloc(u8, ph.filesz);
        defer allocator.free(buf);
        
        try fd.seekTo(ph.off);
        n = try fd.readAll(buf);
        if (n != ph.filesz) {
            std.debug.print("error reading entryother binary code\n", .{});
            return error.ErrIO;
        }
        off += ph.off;
        const od = try std.fs.cwd().createFile(args[2], .{.read = true, .truncate = true});
        try od.writeAll(buf);
        od.close();
    }

    if (!found) {
        std.debug.print("invalid file {s}\n", .{args[1]});
        return error.InvalidExe;
    }
}
