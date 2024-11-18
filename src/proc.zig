const console = @import("console.zig");
const mmu = @import("mmu.zig");
const file = @import("file.zig");
const lapic = @import("lapic.zig");
const mp = @import("mp.zig");
const param = @import("param.zig");
const spinlock = @import("spinlock.zig");
const x86 = @import("x86.zig");

pub const CPU = extern struct {
    apicid: u16,
    scheduler: ?*Context,
    ts: mmu.TaskState,
    gdt: [mmu.NSEGS]mmu.SegDesc,
    started: bool,
    ncli: u32,
    intena: bool,
    proc: *Proc,
};

pub const ProcState = enum {
    UNUSED,
    EMBRYO,
    SLEEPING,
    RUNNABLE,
    RUNNING,
    ZOMBIE,
};

pub const Context = extern struct {
    edi: u32,
    esi: u32,
    ebx: u32,
    ebp: u32,
    eip: u32,
};

pub const Proc = struct {
    sz: usize,
    pgdir: *mmu.PdEntry,
    kstack: usize,
    state: ProcState,
    pid: u32,
    parent: ?*Proc,
    tf: ?*x86.TrapFrame,
    context: ?*Context,
    chan: usize,
    killed: bool,
    ofile: *[param.NPROCFILE]file.File,
    cwd: ?*file.Inode,
    name: []const u8,
};

var ptable = struct {
    lock: spinlock.SpinLock,
    proc: [param.NPROC]Proc,
} {
    .lock = spinlock.SpinLock.init("ptable"),
    .proc = undefined,
};

pub fn mycpu() *CPU {
    if ((x86.readeflags() & mmu.FL_IF) != 0) {
        console.panic("mycpu: interrupts enabled");
    }
    const apicid = lapic.lapicid();
    for (&mp.cpus) |*c| {
        if (c.apicid == apicid) {
            return c;
        }
    }
    console.panic("mycpu: can't determine cpu");
    unreachable;
}

pub fn cpuid() u32 {
    return (@intFromPtr(&mp.cpus) - @intFromPtr(mycpu())) / @sizeOf(CPU);
}

// Disable interrupts, so no scheduling happens while reading the proc from the CPU
pub fn myproc() *Proc {
    spinlock.pushcli();
    defer spinlock.popcli();
    const c = mycpu();
    return c.proc;
}

pub fn sleep(chan: usize, lock: *spinlock.SpinLock) void {
    const p = myproc();

    // Acquire ptable.lock first, then call sched().
    // Once we hold patable.lock, we can be guaranteed we won't miss any
    // wakeup calls, since wakeup() needs to acquire ptable's lock.
    //
    // See: https://pdos.csail.mit.edu/6.828/2012/xv6/book-rev7.pdf, page 57.
    if (lock != &ptable.lock) {
        ptable.lock.acquire();
        lock.release();
    }

    p.chan = chan;
    p.state = ProcState.SLEEPING;

    // TODO enter scheduler

    p.chan = 0;
    if (lock != &ptable.lock) {
        ptable.lock.release();
        lock.acquire();
    }
}

pub fn wakeup1(chan: usize) void {
    for (0..param.NPROC) |i| {
        var p = ptable.proc[i];
        if (p.state == ProcState.SLEEPING and p.chan == chan) {
            p.state = ProcState.RUNNABLE;
        }
    }
}

pub fn wakeup(chan: usize) void {
    ptable.lock.acquire();
    defer ptable.lock.release();
    wakeup1(chan);
}
