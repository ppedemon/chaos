const console = @import("console.zig");
const dir = @import("dir.zig");
const elf = @import("elf.zig");
const fs = @import("fs.zig");
const log = @import("log.zig");
const mmu = @import("mmu.zig");
const vm = @import("vm.zig");

const std = @import("std");

pub fn exec(path: []const u8, _: [][]const u8) i32 {
    log.begin_op();
    defer log.end_op();

    const ip: *fs.Inode = dir.namei(path) orelse {
        console.cprintf("exec: {s} not found", .{path});
        return -1;
    };

    var elfh: elf.ElfHdr = undefined;

    ip.ilock();
    if (ip.readi(std.mem.asBytes(&elfh), 0, @sizeOf(elf.ElfHdr)) != @sizeOf(elf.ElfHdr)) {
        return -1;
    }
    if (elfh.magic != elf.ELF_MAGIC) {
        return -1;
    }

    const pgdir: [*]mmu.PdEntry = vm.setupkvm() orelse {
        return -1;
    };
    _ = pgdir;


    console.cprintf("elf.ty = 0x{d}\n", .{elfh.ty});
    console.cprintf("elf.machine = 0x{x}\n", .{elfh.machine});
    console.cprintf("elf.entry = 0x{x}\n", .{elfh.entry});
    console.cprintf("elf.phnum = 0x{x}\n", .{elfh.phnum});
    // for (0..elfh.phnum) |i| {
    //     console.cprintf("{}", .{i});
    // }

    ip.iunlock();
    return 0;
}
