const console = @import("console.zig");
const ide = @import("ide.zig");
const ioapic = @import("ioapic.zig");
const kalloc = @import("kalloc.zig");
const lapic = @import("lapic.zig");
const memlayout = @import("memlayout.zig");
const mmu = @import("mmu.zig");
const mp = @import("mp.zig");
const picirq = @import("picirq.zig");
const proc = @import("proc.zig");
const sh = @import("sh.zig");
const spinlock = @import("spinlock.zig");
const trap = @import("trap.zig");
const uart = @import("uart.zig");
const vm = @import("vm.zig");
const x86 = @import("x86.zig");

const kstacksize = @import("param.zig").KSTACKSIZE;

extern const end: u8;

var buf: [32]u8 = undefined;

// fn readstack(esp: usize) usize {
//     const p: *const usize = @ptrFromInt(esp);
//     return p.*;
// }

fn locktest() void {
    var lock = spinlock.SpinLock.init("test");
    lock.acquire();
    lock.release();
    lock.acquire();
    lock.release();
    lock.acquire();
    lock.release();
}

export fn main() align(16) noreturn {
    const end_addr = @intFromPtr(&end);

    kalloc.kinit1(end_addr, memlayout.p2v(4 * 1024 * 1024));
    vm.kvmalloc() orelse sh.panic("kvmalloc");
    mp.mpinit();
    lapic.lapicinit();
    vm.seginit();
    picirq.picinit();
    ioapic.ioapicinit();
    console.consoleinit();
    uart.uartinit();
    ide.ideinit();
    trap.tvinit();
    trap.idtinit();

    var len: usize = 0;
    var p = kalloc.kmem.freelist;
    while (p) |curr| {
        len += 1;
        p = curr.next;
    }

    locktest();
    const cpu = proc.mycpu();

    console.consclear();
    console.cprintf("Chaos started!\n", .{});
    console.cprintf("Kernel end addr = 0x{x}\n", .{end_addr});
    console.cprintf("Free pages = {d}\n", .{len});
    console.cprintf("# of CPUs = {d}\n", .{mp.ncpu});
    console.cprintf("LAPIC addr = 0x{x}\n", .{@intFromPtr(lapic.lapic)});
    console.cprintf("Current CPU id = {d}\n", .{cpu.apicid});
    console.cprintf("GDT addr = 0x{x}\n", .{@intFromPtr(&cpu.gdt)});
    console.cprintf("GDT size = {d}\n", .{@sizeOf(@TypeOf(cpu.gdt))});

    x86.sti();

    while (true) {}
}

export const entrypgdir: [mmu.NPDENTRIES]u32 align(mmu.PGSIZE) = init: {
    var dir: [mmu.NPDENTRIES]u32 = undefined;
    // Two page dir entries, mapping different VA areas to the [0, 4Mb] physical address interval:
    //   1. VA [0, 4Mb] → PA [0, 4Mb]
    //   2. VA [KERNBASE, KERNBASE + 4mb] → PA [0, 4Mb]
    dir[0] = 0 | mmu.PTE_P | mmu.PTE_W | mmu.PTE_S;
    dir[memlayout.KERNBASE >> mmu.PDXSHIFT] = 0 | mmu.PTE_P | mmu.PTE_W | mmu.PTE_S;
    break :init dir;
};
