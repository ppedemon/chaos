const builtin = @import("std").builtin;

const bio = @import("bio.zig");
const console = @import("console.zig");
const fs = @import("fs.zig");
const ide = @import("ide.zig");
const ioapic = @import("ioapic.zig");
const kalloc = @import("kalloc.zig");
const lapic = @import("lapic.zig");
const memlayout = @import("memlayout.zig");
const mmu = @import("mmu.zig");
const mp = @import("mp.zig");
const picirq = @import("picirq.zig");
const proc = @import("proc.zig");
const spinlock = @import("spinlock.zig");
const trap = @import("trap.zig");
const uart = @import("uart.zig");
const vm = @import("vm.zig");
const x86 = @import("x86.zig");

const kstacksize = @import("param.zig").KSTACKSIZE;

extern const end: u8;


// fn readstack(esp: usize) usize {
//     const p: *const usize = @ptrFromInt(esp);
//     return p.*;
// }

// Install global panic function: this will be called by @panic(msg)
pub fn panic(msg: []const u8, _: ?*builtin.StackTrace, _: ?usize) noreturn {
    console.panic(msg);
}

export fn main() align(16) noreturn {
    const end_addr = @intFromPtr(&end);

    kalloc.kinit1(end_addr, memlayout.p2v(4 * 1024 * 1024));
    vm.kvmalloc() orelse @panic("kvmalloc");
    mp.mpinit();
    lapic.lapicinit();
    vm.seginit();
    picirq.picinit();
    ioapic.ioapicinit();
    console.consoleinit();
    uart.uartinit();
    proc.pinit();
    trap.tvinit();
    bio.binit();
    ide.ideinit();
    // TODO startothers()
    kalloc.kinit2(memlayout.p2v(4 * 1024 * 1024), memlayout.p2v(memlayout.PHYSTOP));
    proc.userinit();
    mpmain();
    unreachable;

    // var len: usize = 0;
    // var p = kalloc.kmem.freelist;
    // while (p) |curr| {
    //     len += 1;
    //     p = curr.next;
    // }

    // const cpu = proc.mycpu();

    // console.cprintf("Chaos started!\n", .{});
    // console.cprintf("Kernel end addr = 0x{x}\n", .{end_addr});
    // console.cprintf("Free pages = {d}\n", .{len});
    // console.cprintf("# of CPUs = {d}\n", .{mp.ncpu});
    // console.cprintf("LAPIC addr = 0x{x}\n", .{@intFromPtr(lapic.lapic)});
    // console.cprintf("Current CPU id = {d}\n", .{cpu.apicid});
    // console.cprintf("GDT addr = 0x{x}\n", .{@intFromPtr(&cpu.gdt)});
    // console.cprintf("GDT size = {d}\n", .{@sizeOf(@TypeOf(cpu.gdt))});

    // const popt = proc.allocproc();
    // if (popt) |pr| {
    //     console.cprintf("Jumping to: 0x{x}\n", .{pr.context.eip});
    //     const kp = @as([*]const usize, @ptrFromInt(pr.kstack));
    //     const ret = kp[(4096 - @sizeOf(x86.TrapFrame)) / @sizeOf(usize) - 1];
    //     console.cprintf("Returning to: 0x{x}\n", .{ret});
    // }

    //x86.sti();

    // fs.readsb(0, &fs.superblock);
    // for (0..1_000_000) |_| {}
    // _ = fs.ialloc(0, 1);

    // for (proc.initcode, 0..) |c, i| {
    //     console.cprintf("{x:0>2} ", .{c});
    //     if ((i + 1) % 16 == 0) {
    //         console.cprintf("\n", .{});
    //     } else if ((i+1) % 8 == 0) {
    //         console.cprintf("    ", .{});
    //     }
    // }

    //while (true) {}
}

fn mpmain() void {
    console.consclear();
    console.cprintf("cpu #{d}: starting\n", .{proc.cpuid()});
    trap.idtinit();
    @atomicStore(bool, &proc.mycpu().started, true, builtin.AtomicOrder.seq_cst);
    proc.scheduler();
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
