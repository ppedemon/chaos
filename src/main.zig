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
const param = @import("param.zig");
const picirq = @import("picirq.zig");
const proc = @import("proc.zig");
const spinlock = @import("spinlock.zig");
const string = @import("string.zig");
const trap = @import("trap.zig");
const uart = @import("uart.zig");
const vm = @import("vm.zig");
const x86 = @import("x86.zig");

const entryother: []const u8 = @embedFile("mp/entryother.bin");

const kstacksize = @import("param.zig").KSTACKSIZE;

extern const end: u8;

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
    startothers();
    kalloc.kinit2(memlayout.p2v(4 * 1024 * 1024), memlayout.p2v(memlayout.PHYSTOP));
    proc.userinit();
    mpmain();
    unreachable;
}

fn mpmain() void {
    console.cprintf("cpu #{d}: starting\n", .{proc.cpuid()});
    trap.idtinit();
    @atomicStore(bool, &proc.mycpu().started, true, builtin.AtomicOrder.seq_cst);
    proc.scheduler();
}

fn mpenter() void {
    vm.switchkvm();
    vm.seginit();
    lapic.lapicinit();
    mpmain();
}

fn startothers() void {
    const code: u32 = memlayout.p2v(0x7000);
    string.memmove(code, @intFromPtr(&entryother[0]), entryother.len);

    var i: u8 = 0;
    while (i < mp.ncpu) : (i += 1) {
        const cpu = &mp.cpus[i];
        if (cpu == proc.mycpu()) {
            continue;
        }

        const stack: usize = kalloc.kalloc() orelse @panic("no mem for extra cpu stack");
        @as(*usize, @ptrFromInt(code - 4)).* = stack + param.KSTACKSIZE;
        @as(*usize, @ptrFromInt(code - 8)).* = @intFromPtr(&mpenter);
        @as(*usize, @ptrFromInt(code - 12)).* = memlayout.v2p(@intFromPtr(&entrypgdir[0]));
        lapic.lapitstartap(cpu.apicid, memlayout.v2p(code));

        while (!cpu.started) {}
    }
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
