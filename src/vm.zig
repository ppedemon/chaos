const console = @import("console.zig");
const fs = @import("fs.zig");
const kalloc = @import("kalloc.zig");
const memlayout = @import("memlayout.zig");
const mmu = @import("mmu.zig");
const mp = @import("mp.zig");
const param = @import("param.zig");
const proc = @import("proc.zig");
const spinlock = @import("spinlock.zig");
const string = @import("string.zig");
const x86 = @import("x86.zig");

extern const data: u8;

pub var kpgdir: [*]mmu.PdEntry = undefined;

comptime {
    asm (
        \\ .globl set_segregs
        \\ .type set_segregs, @function
        \\ set_segregs:
        \\   movw $0x10, %ax # ax = 0b00010_000 = SEG_KDATA
        \\   movw %ax, %ds
        \\   movw %ax, %es
        \\   movw %ax, %fs
        \\   movw %ax, %gs
        \\   movw %ax, %ss
        \\   movw $0x08, %ax  # ax = 0b00001_000 = SEG_KCODE
        \\   movl $.next, %ecx
        \\   pushw %ax
        \\   pushl %ecx
        \\   lret  # long return to %cs:%eip = SEG_KCODE:.next
        \\ .next:
        \\   movl %ebp, %esp
        \\   popl %ebp
        \\   ret
    );
}

extern fn set_segregs() void;

pub fn seginit() void {
    var cpu = proc.mycpu();
    
    cpu.gdt[mmu.SEG_KCODE] = mmu.SegDesc.new(mmu.STA_X | mmu.STA_R, 0, 0xFFFF_FFFF, mmu.DPL_KERNEL);
    cpu.gdt[mmu.SEG_KDATA] = mmu.SegDesc.new(mmu.STA_W, 0, 0xFFFF_FFFF, mmu.DPL_KERNEL);
    cpu.gdt[mmu.SEG_UCODE] = mmu.SegDesc.new(mmu.STA_X | mmu.STA_R, 0, 0xFFFF_FFFF, mmu.DPL_USER);
    cpu.gdt[mmu.SEG_UDATA] = mmu.SegDesc.new(mmu.STA_W, 0, 0xFFFF_FFFF, mmu.DPL_USER);

    x86.lgdt(@intFromPtr(&cpu.gdt), @sizeOf(@TypeOf(cpu.gdt)));
    set_segregs();
}

const KMap = struct {
    virt: usize,
    phys_start: usize,
    phys_end: usize,
    perm: usize,
};

/// Given page directory pointer pgdir and a virtual address va:
///   1. Ensure that the page table referenced by pgdir[pdx(va)] is present
///   2. Return the pointer to the page table entry referenced by pgdir[pdx(va)][ptx(va)]
fn walkpgdir(pgdir: [*]mmu.PdEntry, va: usize, alloc: bool) ?*mmu.PtEntry {
    const pde = &pgdir[mmu.pdx(va)];
    var pgtab: [*]mmu.PtEntry = undefined;

    if (pde.* & mmu.PTE_P != 0) {
        // Page table pointed to in page directory entry pointed by pde is present
        pgtab = @ptrFromInt(memlayout.p2v(mmu.pteaddr(pde.*)));
    } else {
        // Page table pointed to in page directory entry pointed by pde is not present
        if (!alloc) {
            return null;
        }
        const pgtab_va = kalloc.kalloc() orelse return null;
        string.memset(pgtab_va, 0, mmu.PGSIZE);
        pde.* = memlayout.v2p(pgtab_va | mmu.PTE_P | mmu.PTE_W | mmu.PTE_U);
        pgtab = @ptrFromInt(pgtab_va);
    }

    return &pgtab[mmu.ptx(va)];
}

// Create PTEs for virtual addresses starting at va mapping to physical addresses starting at pa.
// Note: va and size might not be page aligned, so round down them to a page boundary
fn mappages(pgdir: [*]mmu.PdEntry, va: usize, size: usize, pa: usize, perm: usize) bool {
    var virt_addr = mmu.pgrounddown(va);
    const last = mmu.pgrounddown(va +% size -% 1);
    var phys_addr = pa;

    while (true) {
        const pte = walkpgdir(pgdir, virt_addr, true) orelse return false;
        if (pte.* & mmu.PTE_P != 0) {
            @panic("remap");
        }
        pte.* = phys_addr | perm | mmu.PTE_P;

        if (virt_addr == last) {
            break;
        }

        virt_addr = virt_addr +% mmu.PGSIZE;
        phys_addr = phys_addr +% mmu.PGSIZE;
    }

    return true;
}

pub fn setupkvm() ?[*]mmu.PdEntry {
    if (memlayout.PHYSTOP > memlayout.DEVSPACE) {
        @panic("PHYSTOP too high");
    }

    const pgdir_va = kalloc.kalloc() orelse return null;
    string.memset(pgdir_va, 0, mmu.PGSIZE);

    const data_addr: usize = @intFromPtr(&data);

    const kmap = [_]KMap{
        .{
            .virt = memlayout.KERNBASE,
            .phys_start = 0,
            .phys_end = memlayout.EXTMEM,
            .perm = mmu.PTE_W,
        },
        .{
            .virt = memlayout.KERNLINK,
            .phys_start = memlayout.v2p(memlayout.KERNLINK),
            .phys_end = memlayout.v2p(data_addr),
            .perm = 0,
        },
        .{
            .virt = data_addr,
            .phys_start = memlayout.v2p(data_addr),
            .phys_end = memlayout.PHYSTOP,
            .perm = mmu.PTE_W,
        },
        .{
            .virt = memlayout.DEVSPACE,
            .phys_start = memlayout.DEVSPACE,
            .phys_end = 0,
            .perm = mmu.PTE_W,
        },
    };

    const pgdir: [*]mmu.PdEntry = @ptrFromInt(pgdir_va);
    for (kmap) |k| {
        const ok = mappages(pgdir, k.virt, k.phys_end -% k.phys_start, k.phys_start, k.perm);
        if (!ok) {
            return null;
        }
    }

    return pgdir;
}

pub fn switchkvm() void {
    x86.lcr3(memlayout.v2p(@intFromPtr(kpgdir)));
}

pub fn switchuvm(p: *const proc.Proc) void {
    if (p.kstack == 0) {
        @panic("switchuvm: no kstack");
    }

    spinlock.pushcli();
    defer spinlock.popcli();

    const cpu = proc.mycpu();
    cpu.gdt[mmu.SEG_TSS] = mmu.SegDesc.new16(mmu.STS_T32A, @intFromPtr(&cpu.ts), @sizeOf(mmu.TaskState) - 1, mmu.DPL_KERNEL);
    cpu.gdt[mmu.SEG_TSS].s = 0;
    cpu.ts.ss0 = mmu.SEG_KDATA << 3;
    cpu.ts.esp0 = p.kstack + param.KSTACKSIZE;
    cpu.ts.iomb = 0xFFFF;

    x86.ltr(mmu.SEG_TSS << 3);
    x86.lcr3(memlayout.v2p(@intFromPtr(p.pgdir)));
}

pub fn kvmalloc() ?void {
    kpgdir = setupkvm() orelse return null;
    switchkvm();
}

pub fn inituvm(pgdir: [*]mmu.PdEntry, src: []const u8) void {
    if (src.len > mmu.PGSIZE) {
        @panic("inituvm: more than one page");
    }

    const mem = kalloc.kalloc() orelse unreachable;
    string.memset(mem, 0, mmu.PGSIZE);
    const succ = mappages(pgdir, 0, mmu.PGSIZE, memlayout.v2p(mem), mmu.PTE_W | mmu.PTE_U);
    if (!succ) {
        @panic("inituvm: no free pages");
    }
    string.memmove(mem, @intFromPtr(&src[0]), src.len);
}

// Load a program segment into pgdir starting at the given addr, which must be
// page aligned. Pages from addr + addr + sz must have been already mapped.
pub fn loaduvm(pgdir: [*]mmu.PdEntry, addr: usize, ip: *fs.Inode, offset: u32, sz: usize) bool {
    if (addr % mmu.PGSIZE != 0) {
        @panic("loduvm: addr must be page aligned");
    }
    var i: usize = 0;
    while (i < sz) : (i += mmu.PGSIZE) {
        if (walkpgdir(pgdir, addr + i, false)) |pte| {
            const va = memlayout.p2v(mmu.pteaddr(pte.*));
            var buf: [*]u8 = @ptrFromInt(va);
            const n = @min(sz - i, mmu.PGSIZE);
            if (ip.readi(buf[0..n], offset + i, n) != n) {
                return false;
            }
        } else {
            @panic("loaduvm: address should be page mapped");
        }
    }
    return true;
}

// Allocate page tables to grow process from oldsz to newsz. The param
// newsz doesn't have to be page aligned. Return new size or 0 on error.
pub fn allocuvm(pgdir: [*]mmu.PdEntry, oldsz: usize, newsz: usize) usize {
    if (newsz > memlayout.KERNBASE) {
        return 0;
    }
    if (newsz <= oldsz) {
        return oldsz;
    }

    var a = mmu.pgroundup(oldsz);
    while (a < newsz) : (a += mmu.PGSIZE) {
        const mem = kalloc.kalloc() orelse {
            console.cputs("allocuvm: out of memory\n");
            _ = deallocuvm(pgdir, newsz, oldsz);
            return 0;
        };
        string.memset(mem, 0, mmu.PGSIZE);
        const ok = mappages(pgdir, a, mmu.PGSIZE, memlayout.v2p(mem), mmu.PTE_W | mmu.PTE_U);
        if (!ok) {
            console.cputs("allocuvm: out of memory\n");
            _ = deallocuvm(pgdir, newsz, oldsz);
            kalloc.kfree(mem);
            return 0;
        }
    }
    return newsz;
}

// Deallocate user pages to bring the process size from oldsz to newsz.
// Size doesn't have top be page-aligned, not newsz be less than oldsz.
// Also oldsz can be larger then the actual process size. Return newsz.
pub fn deallocuvm(pgdir: [*]mmu.PdEntry, oldsz: usize, newsz: usize) usize {
    if (newsz >= oldsz) {
        return oldsz;
    }
    var a = mmu.pgroundup(newsz);
    while (a < oldsz) : (a += mmu.PGSIZE) {
        if (walkpgdir(pgdir, a, false)) |pte| {
            if (pte.* & mmu.PTE_P != 0) {
                // Page table present, so it points to a physical page frame.
                // Get virtual address of page frame and kfree it.
                const pa = mmu.pteaddr(pte.*);
                if (pa == 0) {
                    @panic("deallocuvm: null physical addr");
                }
                const va = memlayout.p2v(pa);
                kalloc.kfree(va);
                pte.* = 0;
            }
        } else {
            // Page directory entry for virtual address 'a' has no page table pointer.
            // Bump 'a' so it moves to next page table pointer in pgdir.
            // NOTE: subtracting PGSIZE, since the while will increment it before next iteration.
            a = mmu.addr(mmu.pdx(a) + 1, 0, 0) - mmu.PGSIZE;
        }
    }
    return newsz;
}

pub fn freevm(pgdir: [*]mmu.PdEntry) void {
    // Free pages
    _ = deallocuvm(pgdir, memlayout.KERNBASE, 0);

    // Free page tables pointed to by pgdir
    for (0..mmu.NPDENTRIES) |i| {
        if (pgdir[i] & mmu.PTE_P != 0) {
                const va = memlayout.p2v(mmu.pteaddr(pgdir[i]));
                kalloc.kfree(va);
            }
        }

    // Free page directory itself
    kalloc.kfree(@intFromPtr(pgdir));
}

// Make the page corresponding to the given va inaccessible to user code.
// Useful to create a 1-page safety zone beneath user stack. This way we
// proetct user code against stack overflow.
pub fn clearpteu(pgdir: [*]mmu.PdEntry, va: usize) void {
    if (walkpgdir(pgdir, va, false)) |pte| {
        pte.* &= ~@as(usize, mmu.PTE_U);
        return;
    }
    @panic("clearpteu: no page");
}

// map user virtual address to kernel virtual address
fn uva2ka(pgdir: [*]mmu.PdEntry, uva: usize) usize {
    if (walkpgdir(pgdir, uva, false)) |pte| {
        if (pte.* & mmu.PTE_P == 0 or pte.* & mmu.PTE_U == 0) {
            return 0;
        }
        return memlayout.p2v(mmu.pteaddr(pte.*));
    }
    @panic("uva2ka: no page");
}

// Copy the slice p to user address va in page directory pgdir.
// Used to move stuff from kernel to user address space.
pub fn copyout(pgdir: [*]mmu.PdEntry, va: usize, p: []const u8) bool {
    var i: usize = 0;
    var len = p.len;
    var v = va;

    while (len > 0) {
        const va_boundary = mmu.pgrounddown(v);
        const pa_boundary = uva2ka(pgdir, va_boundary);
        if (pa_boundary == 0) {
            return false;
        }
        const n = @min(len, mmu.PGSIZE - (v - va_boundary));
        string.memmove(pa_boundary + (v - va_boundary), @intFromPtr(&p[i]), n);
        len -= n;
        i += n;
        v = va_boundary + mmu.PGSIZE;
    }

    return true;
}

pub fn copyuvm(pgdir: [*]mmu.PdEntry, sz: usize) ?[*]mmu.PdEntry {
    const d = setupkvm() orelse return null;

    var i: usize = 0;
    while (i < sz) : (i += mmu.PGSIZE) {
        const pte: *mmu.PtEntry = walkpgdir(pgdir, i, false) orelse {
            @panic("copyuvm: pte should exist");
        };
        if (pte.* & mmu.PTE_P == 0) {
            @panic("copyuvm: page not present");
        }
        const pa = mmu.pteaddr(pte.*);
        const flags = mmu.pteflags(pte.*);
        const va: usize = kalloc.kalloc() orelse {
            freevm(d);
            return null;
        };
        string.memmove(va, memlayout.p2v(pa), mmu.PGSIZE);
        const ok = mappages(d, i, mmu.PGSIZE, memlayout.v2p(va), flags);
        if (!ok) {
            kalloc.kfree(va);
            freevm(d);
            return null;
        }
    }

    return d;
}
