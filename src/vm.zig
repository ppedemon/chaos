const console = @import("console.zig");
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
    if (proc.cpuid() != 0) {
        @panic("segint: not running on cpu #0");
    }

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
    @memcpy(@as([*]u8, @ptrFromInt(mem)), src);
}
