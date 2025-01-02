const console = @import("console.zig");
const dir = @import("dir.zig");
const elf = @import("elf.zig");
const err = @import("err.zig");
const fs = @import("fs.zig");
const log = @import("log.zig");
const mmu = @import("mmu.zig");
const param = @import("param.zig");
const proc = @import("proc.zig");
const string = @import("string.zig");
const vm = @import("vm.zig");

const std = @import("std");

pub fn exec(path: []const u8, argv: []const []const u8) err.SysErr!u32 {
    var ip: *fs.Inode = undefined;
    var pgdir: [*]mmu.PdEntry = undefined;
    var elfh: elf.ElfHdr = undefined;
    var ph: elf.ProgHdr = undefined;

    var cleanup_ip = false;
    var cleanup_pgdir = false;

    defer {
        if (cleanup_ip) {
            ip.iunlockput();
            log.end_op();
        }
        if (cleanup_pgdir) {
            vm.freevm(pgdir);
        }
    }

    log.begin_op();

    ip = dir.namei(path) orelse {
        log.end_op();
        console.cprintf("exec: {s} not found", .{path});
        return err.SysErr.ErrNoFile;
    };
    cleanup_ip = true;

    ip.ilock();
    if (ip.readi(std.mem.asBytes(&elfh), 0, @sizeOf(elf.ElfHdr)) != @sizeOf(elf.ElfHdr)) {
        return err.SysErr.ErrIO;
    }
    if (elfh.magic != elf.ELF_MAGIC) {
        return err.SysErr.ErrNoExec;
    }

    pgdir = vm.setupkvm() orelse {
        return err.SysErr.ErrNoMem;
    };
    cleanup_pgdir = true;

    var sz: usize = 0;
    var off = elfh.phoff;
    for (0..elfh.phnum) |_| {
        if (ip.readi(std.mem.asBytes(&ph), off, @sizeOf(elf.ProgHdr)) != @sizeOf(elf.ProgHdr)) {
            return err.SysErr.ErrIO;
        }
        if (ph.ty != elf.ELF_PROG_LOAD) {
            continue;
        }
        if (ph.memsz < ph.filesz) {
            return err.SysErr.ErrNoExec;
        }
        if (ph.vaddr + ph.memsz < ph.vaddr) {
            return err.SysErr.ErrNoExec;
        }
        sz = vm.allocuvm(pgdir, sz, ph.vaddr + ph.memsz);
        if (sz == 0) {
            return err.SysErr.ErrNoMem;
        }
        if (ph.vaddr % mmu.PGSIZE != 0) {
            return err.SysErr.ErrNoExec;
        }
        const loaded = vm.loaduvm(pgdir, ph.vaddr, ip, ph.off, ph.filesz);
        if (!loaded) {
            return err.SysErr.ErrFault;
        }
        off += @sizeOf(elf.ProgHdr);
    }
    ip.iunlockput();
    log.end_op();
    cleanup_ip = false;

    // Allocate two further pages for user program starting at next page boundary:
    //
    // [...user prog pages...] + [page_1 (buffer zone)] + [page_2 (stack)]
    //
    // [page_1] will be a user-inaccessible page between the program and the stack,
    // protecting against stack overflows.
    sz = mmu.pgroundup(sz);
    sz = vm.allocuvm(pgdir, sz, sz + 2 * mmu.PGSIZE);
    if (sz == 0) {
        return err.SysErr.ErrNoMem;
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
        return err.SysErr.ErrArgs;
    }
    for (0..argc) |i| {
        sp = (sp - (argv[i].len + 1)) & ~@as(usize, 3); // ensure args are 4-aligned in the stack
        const ok = vm.copyout(pgdir, sp, argv[i]);
        if (!ok) {
            return err.SysErr.ErrFault;
        }
        ustack[3 + i] = sp;
    }
    ustack[3 + argc] = 0;

    ustack[0] = 0xFFFF_FFFF;
    ustack[1] = argc;
    ustack[2] = sp - (argc + 1) * @sizeOf(usize); // points to future location of argv in page acting as stack

    sp -= (3 + argc + 1) * @sizeOf(usize);
    const slice: []const u8 = std.mem.sliceAsBytes(ustack[0..(3 + argc + 1)]);
    const ok = vm.copyout(pgdir, sp, slice);
    if (!ok) {
        return err.SysErr.ErrFault;
    }

    // NOTE from now on exec can't fail, so we *MUST* clear the cleanup_pgdir flag.
    // Otherwise the deferred block will free the new process pgdir on exit!
    cleanup_pgdir = false;

    const curproc: *proc.Proc = proc.myproc() orelse @panic("exec: no current process");
    var start: usize = 0;
    if (std.mem.lastIndexOf(u8, path, "/")) |index| {
        start = index + 1;
    }
    string.safecpy(&curproc.name, path[start..]);

    const oldpgdir = curproc.pgdir;
    curproc.pgdir = pgdir;
    curproc.sz = sz;
    curproc.tf.eip = elfh.entry;
    curproc.tf.esp = sp;
    vm.switchuvm(curproc);
    vm.freevm(oldpgdir);

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

// Debug: turn a process virtual address into a kernel virtual address
fn va2ka(pgdir: [*]mmu.PdEntry, va: usize) usize {
    const memlayout = @import("memlayout.zig");
    const pt_ptr: [*]mmu.PtEntry = @ptrFromInt(memlayout.p2v(mmu.pteaddr(pgdir[mmu.pdx(va)])));
    const pa = mmu.pteaddr(pt_ptr[mmu.ptx(va)]) + (va & 0xFFF);
    return memlayout.p2v(pa);
}
