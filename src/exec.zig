const console = @import("console.zig");
const dir = @import("dir.zig");
const elf = @import("elf.zig");
const fs = @import("fs.zig");
const log = @import("log.zig");
const mmu = @import("mmu.zig");
const param = @import("param.zig");
const proc = @import("proc.zig");
const string = @import("string.zig");
const vm = @import("vm.zig");

const std = @import("std");

pub fn exec(path: []const u8, argv: []const []const u8) i32 {
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

        // TODO Debug code, remove
        // dumpuvm(pgdir, ph.vaddr, ph.memsz);
    }
    ip.iunlockput();
    log.end_op();
    cleanup_inode = false;

    // Allocate two further pages for user program starting at next page boundary:
    //
    // [...user prog pages...] + [page_1 (buffer zone)] + [page_2 (stack)]
    //
    // [page_1] will be a user-inaccessible page between the program and the stack,
    // protecting against stack overflows.
    sz = mmu.pgroundup(sz);
    sz = vm.allocuvm(pgdir, sz, sz + 2 * mmu.PGSIZE);
    if (sz == 0) {
        return -1;
    }
    vm.clearpteu(pgdir, sz - 2 * mmu.PGSIZE);

    // user stack:
    //
    //   [ fake ret addr | argc | argv | argv[0] | ... | argv[argc-1] | 0 ]
    //
    // So in addition to all args (up to param.MAXARG), we need to account
    // for four extra slots: fake return addr, argc, the argv variable
    // pointing to argv[0], and a final zero signaling the end of argv.
    var ustack: [3 + param.MAXARG + 1]u32 = [_]u32{0} ** (3 + param.MAXARG + 1);
    var sp = sz;

    const argc = argv.len;
    if (argc >= param.MAXARG) {
        return -1;
    }
    for (0..argc) |i| {
        sp = (sp - (argv[i].len + 1)) & ~@as(usize, 3); // ensure args are 4-aligned in the stack
        const ok = vm.copyout(pgdir, sp, argv[i]);
        if (!ok) {
            return -1;
        }
        ustack[3 + i] = sp;
    }
    ustack[3 + argc] = 0;

    ustack[0] = 0xFFFF_FFFF;
    ustack[1] = argc;
    ustack[2] = sp - (argc + 1) * @sizeOf(usize); // points to future location of argv in page acting as stack

    sp -= (3 + argc + 1) * @sizeOf(usize);

    // const memlayout = @import("memlayout.zig");
    // console.cputs(">>> pg dir looks like:\n");
    // var i: usize = 0;
    // while (pgdir[i] != 0) : (i += 1) {
    //     const pte_p = mmu.pteaddr(pgdir[i]);
    //     console.cprintf("pgdir[{}] = 0x{x} (kva = 0x{x})\n", .{ i, pte_p, memlayout.p2v(pte_p) });

    //     console.cputs(">>> page table looks like:\n");
    //     const pte: [*]mmu.PtEntry = @ptrFromInt(memlayout.p2v(pte_p));
    //     var j: usize = 0;
    //     while (pte[j] != 0) : (j += 1) {
    //         const pa = mmu.pteaddr(pte[j]);
    //         console.cprintf("pte[{}] = 0x{x} (kva = 0x{x})\n", .{ j, pa, memlayout.p2v(pa) });
    //     }
    // }

    const slice: []const u8 = std.mem.sliceAsBytes(ustack[0..(3 + argc + 1)]);

    // const pa = mmu.pteaddr(@as([*]mmu.PtEntry, @ptrFromInt(memlayout.p2v(mmu.pteaddr(pgdir[mmu.pdx(sp)]))))[mmu.ptx(sp)]) + (sp & 0xFFF);
    // console.cprintf(">>> copyout: uva = 0x{x}, pa = 0x{x}, kva = 0x{x}, size = 0x{x}\n", .{ sp, pa, memlayout.p2v(pa), slice.len });

    const ok = vm.copyout(pgdir, sp, slice);
    if (!ok) {
        return -1;
    }

    const curproc: *proc.Proc = proc.myproc() orelse @panic("exec: no current process");
    var start: usize = 0;
    if (std.mem.lastIndexOf(u8, path, "/")) |index| {
        start = index + 1;
    }
    string.safecpy(&curproc.name, path[start..]);
    // console.cprintf("new proc name = {s}\n", .{curproc.name});

    console.cprintf("sz = 0x{x}, sp[0] = 0x{x}, eip = 0x{x}, *eip = 0x{x}\n", .{
        sz,
        @as(*u32, @ptrFromInt(va2ka(pgdir, sp))).*,
        elfh.entry,
        @as(*u8, @ptrFromInt(va2ka(pgdir, elfh.entry))).*,
    });

    const oldpgdir = curproc.pgdir;
    curproc.pgdir = pgdir;
    curproc.sz = sz;
    curproc.tf.eip = elfh.entry;
    curproc.tf.esp = sp;
    vm.switchuvm(curproc);
    vm.freevm(oldpgdir);

    // const ksp: [*]u32 = @ptrFromInt(va2ka(pgdir, sp));
    // console.cprintf("fake ip addr = 0x{x}, kernel = {}, value = 0x{x}\n", .{ sp, &ksp[0], ksp[0] });
    // console.cprintf("argc addr = 0x{x}, kernel = {}, value = {}\n", .{ sp + 4, &ksp[1], ksp[1] });
    // console.cprintf("argv addr = 0x{x}, kernel = {}, value = 0x{x}\n", .{ sp + 8, &ksp[2], ksp[2] });
    // for (0..ksp[1]) |i| {
    //     console.cprintf("argv[{}] addr = 0x{x}, kernel = {}, value = 0x{x}\n", .{
    //         i,
    //         sp + 12 + 4 * i,
    //         &ksp[3 + i],
    //         ksp[3 + i],
    //     });
    // }
    // console.cprintf("sentinel addr = 0x{x}, kernel = {}, value = 0x{x}\n", .{ sp + 28, &ksp[7], ksp[7] });

    // const kargv: [*]usize = @ptrFromInt(va2ka(pgdir, ksp[2]));
    // console.cprintf("argv = {*}\n", .{kargv});
    // for (0..ksp[1]) |i| {
    //     const arg: [*:0]u8 = @ptrFromInt(va2ka(pgdir, kargv[i]));
    //     console.cprintf("arg[{}] = {s}\n", .{ i, arg });
    // }

    // console.cprintf("elf.ty = 0x{d}\n", .{elfh.ty});
    // console.cprintf("elf.machine = 0x{x}\n", .{elfh.machine});
    // console.cprintf("elf.entry = 0x{x}\n", .{elfh.entry});
    // console.cprintf("elf.phnum = 0x{x}\n", .{elfh.phnum});
    // console.cprintf("elf.phoff = 0x{x}\n", .{elfh.phoff});
    return 0;
}

// Debug: dump vm contents of loaded user program
fn dumpuvm(pgdir: [*]mmu.PdEntry, vstart: usize, sz: usize) void {
    const memlayout = @import("memlayout.zig");
    for (vstart..vstart + sz) |va| {
        const pt_p = mmu.pteaddr(pgdir[mmu.pdx(va)]);
        const pt: [*]mmu.PtEntry = @ptrFromInt(memlayout.p2v(pt_p));
        const pg_p = mmu.pteaddr(pt[mmu.ptx(va)]);
        const pa = pg_p + (va & 0xFFF);
        const kva: *u8 = @ptrFromInt(memlayout.p2v(pa));
        console.cprintf("uva = 0x{x}, pa = 0x{x}, kva = 0x{x}, v = 0x{x:0>2}\n", .{
            va, pa, memlayout.p2v(pa), kva.*,
        });
    }
}

fn va2ka(pgdir: [*]mmu.PdEntry, va: usize) usize {
    const memlayout = @import("memlayout.zig");
    const pt_ptr: [*]mmu.PtEntry = @ptrFromInt(memlayout.p2v(mmu.pteaddr(pgdir[mmu.pdx(va)])));
    const pa = mmu.pteaddr(pt_ptr[mmu.ptx(va)]) + (va & 0xFFF);
    return memlayout.p2v(pa);
}
