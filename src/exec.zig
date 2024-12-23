const console = @import("console.zig");
const dir = @import("dir.zig");
const elf = @import("elf.zig");
const fs = @import("fs.zig");
const log = @import("log.zig");
const mmu = @import("mmu.zig");
const vm = @import("vm.zig");

const std = @import("std");

pub fn exec(path: []const u8, _: [][]const u8) i32 {
    var ip: *fs.Inode = undefined;
    var pgdir: [*]mmu.PdEntry = undefined;
    var elfh: elf.ElfHdr = undefined;
    var ph: elf.ProgHdr = undefined;

    var cleanup_inode = false;
    var cleanup_pg = false;

    defer {
        if (cleanup_pg) {
            vm.freevm(pgdir);
        }
        if (cleanup_inode) {
            ip.iunlockput();
            log.end_op();
        }
    }

    log.begin_op();

    ip = dir.namei(path) orelse {
        log.end_op();
        console.cprintf("exec: {s} not found", .{path});
        return -1;
    };
    cleanup_inode = true;

    ip.ilock();
    if (ip.readi(std.mem.asBytes(&elfh), 0, @sizeOf(elf.ElfHdr)) != @sizeOf(elf.ElfHdr)) {
        return -1;
    }
    if (elfh.magic != elf.ELF_MAGIC) {
        return -1;
    }

    pgdir = vm.setupkvm() orelse {
        return -1;
    };
    cleanup_pg = true;

    var sz: usize = 0;
    var off = elfh.phoff;
    for (0..elfh.phnum) |_| {
        if (ip.readi(std.mem.asBytes(&ph), off, @sizeOf(elf.ProgHdr)) != @sizeOf(elf.ProgHdr)) {
            return -1;
        }
        if (ph.ty != elf.ELF_PROG_LOAD) {
            continue;
        }
        if (ph.memsz < ph.filesz) {
            return -1;
        }
        if (ph.vaddr + ph.memsz < ph.vaddr) {
            return -1;
        }
        sz = vm.allocuvm(pgdir, sz, ph.vaddr + ph.memsz);
        if (sz == 0) {
            return -1;
        }
        if (ph.vaddr % mmu.PGSIZE != 0) {
            return -1;
        }
        const loaded = vm.loaduvm(pgdir, ph.vaddr, ip, ph.off, ph.filesz);
        if (!loaded) {
          return -1;
        }
        off += @sizeOf(elf.ProgHdr);
    }
    ip.iunlockput();
    log.end_op();
    cleanup_inode = false;

    console.cprintf("elf.ty = 0x{d}\n", .{elfh.ty});
    console.cprintf("elf.machine = 0x{x}\n", .{elfh.machine});
    console.cprintf("elf.entry = 0x{x}\n", .{elfh.entry});
    console.cprintf("elf.phnum = 0x{x}\n", .{elfh.phnum});
    console.cprintf("elf.phoff = 0x{x}\n", .{elfh.phoff});
    return 0;
}
