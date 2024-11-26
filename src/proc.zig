const console = @import("console.zig");
const kalloc = @import("kalloc.zig");
const file = @import("file.zig");
const lapic = @import("lapic.zig");
const mmu = @import("mmu.zig");
const mp = @import("mp.zig");
const param = @import("param.zig");
const spinlock = @import("spinlock.zig");
const string = @import("string.zig");
const vm = @import("vm.zig");
const x86 = @import("x86.zig");

const uart = @import("uart.zig");

pub const CPU = extern struct {
    apicid: u16,
    scheduler: ?*Context,
    ts: mmu.TaskState,
    gdt: [mmu.NSEGS]mmu.SegDesc,
    started: bool,
    ncli: u32,
    intena: bool,
    proc: ?*Proc,
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
    pgdir: [*]mmu.PdEntry,
    kstack: usize,
    state: ProcState,
    pid: u32,
    parent: ?*Proc,
    tf: *x86.TrapFrame,
    context: *Context,
    chan: usize,
    killed: bool,
    ofile: *[param.NPROCFILE]file.File,
    cwd: ?*file.Inode,
    name: [15:0]u8,
};

extern fn trapret() void;

const initcode: []const u8 = @embedFile("initcode.bin");
var initproc: *Proc = undefined;


var ptable = struct {
    lock: spinlock.SpinLock,
    proc: [param.NPROC]Proc,
}{
    .lock = spinlock.SpinLock.init("ptable"),
    .proc = undefined,
};

var nextpid: usize = 1;

pub fn mycpu() *CPU {
    if ((x86.readeflags() & mmu.FL_IF) != 0) {
        @panic("mycpu: interrupts enabled");
    }
    const apicid = lapic.lapicid();
    for (&mp.cpus) |*c| {
        if (c.apicid == apicid) {
            return c;
        }
    }
    @panic("mycpu: can't determine cpu");
}

pub fn cpuid() u32 {
    return (@intFromPtr(&mp.cpus) - @intFromPtr(mycpu())) / @sizeOf(CPU);
}

// Disable interrupts, so no scheduling happens while reading the proc from the CPU
pub fn myproc() ?*Proc {
    spinlock.pushcli();
    defer spinlock.popcli();
    const c = mycpu();
    return c.proc;
}

// allocproc: allocate a new process in ptable and setup its kstack.
// kstack is setup such that it works when a process is created by fork or it's the 1st process.
// For this, we want it to enter forkret, and then return to trapret. We need to:
//
//   1. Allocate a page for the kstack
//   2. Push an empty TrapFrame on the kstack (to be filled by fork, left empty for 1st process)
//   3. Push a fake return address to trapret (see trap.S) on the kstack
//   4. Push an empty Context on top of the kstack.
//   5. So set Context.eip = forkret (the kernel thread will start executing with register contents from Context)
//
// We are done. The context switching code will set the stack pointer one past the Context.
// That is, pointing at the trapret return address. This is where forkret will return.
// Then, trapret restores user registers and enters the new process.
// 
pub fn allocproc() ?*Proc {
    ptable.lock.acquire();

    for (&ptable.proc) |*p| {
        if (p.state == ProcState.UNUSED) {
            p.state = ProcState.EMBRYO;
            p.pid = nextpid;
            nextpid += 1;

            // By setting state = EMBRYO, slot is no longer available, we can release the lock now
            ptable.lock.release();

            // Alloc kstack, set sp
            p.kstack = kalloc.kalloc() orelse {
                p.state = ProcState.UNUSED;
                return null;
            };
            var sp = p.kstack + param.KSTACKSIZE;

            // Put TrapFrame in kstack
            sp -= @sizeOf(x86.TrapFrame);
            p.tf = @ptrFromInt(sp);

            // Set ret address = trapframe
            sp -= 4;
            const ret_ptr = @as(*usize, @ptrFromInt(sp));
            ret_ptr.* = @intFromPtr(&trapret);

            // Put a context with eip pointing to forkret
            sp -= @sizeOf(Context);
            p.context = @ptrFromInt(sp);
            string.memset(sp, 0, @sizeOf(Context));
            p.context.eip = @intFromPtr(&forkret);

            return p;
        }
    }

    ptable.lock.release();
    return null;
}

pub fn userinit() void {
    const p = allocproc() orelse unreachable;
    initproc = p;

    p.pgdir = vm.setupkvm() orelse @panic("userinit: out of memory");
    vm.inituvm(p.pgdir, initcode);
    p.sz = mmu.PGSIZE;
    string.memset(@intFromPtr(p.tf), 0, @sizeOf(x86.TrapFrame));
    p.tf.cs = (mmu.SEG_UCODE << 3) | mmu.DPL_USER;
    p.tf.ds = (mmu.SEG_UDATA << 3) | mmu.DPL_USER;
    p.tf.es = p.tf.ds;
    p.tf.ss = p.tf.ds;
    p.tf.eflags = mmu.FL_IF;
    p.tf.esp = mmu.PGSIZE;
    p.tf.eip = 0; // start of init/initcode.S
    string.safecpy(&p.name, "initcode");
    
    // TODO implment
    // p.cwd = namei("/");

    ptable.lock.acquire();
    p.state = ProcState.RUNNABLE;
    ptable.lock.release();
}

fn forkret() void {
    const static = struct {
        var first: bool = true;
    };

    // Held by scheduler
    ptable.lock.release();

    if (static.first) {
        static.first = false;
        // TODO init inodes and log writer
    }

    // This returns to trapret (see allocproc)
}

pub fn sleep(chan: usize, lock: *spinlock.SpinLock) void {
    const p = myproc() orelse @panic("sleep: no process");

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

pub fn procdump() void {
    console.cputs("proc dump!\n");
}
