const console = @import("console.zig");
const dir = @import("dir.zig");
const file = @import("file.zig");
const fs = @import("fs.zig");
const kalloc = @import("kalloc.zig");
const lapic = @import("lapic.zig");
const log = @import("log.zig");
const mmu = @import("mmu.zig");
const mp = @import("mp.zig");
const param = @import("param.zig");
const spinlock = @import("spinlock.zig");
const string = @import("string.zig");
const vm = @import("vm.zig");
const x86 = @import("x86.zig");

const memlayout = @import("memlayout.zig");

pub const CPU = extern struct {
    apicid: u16,
    scheduler: *Context,
    ts: mmu.TaskState,
    gdt: [mmu.NSEGS]mmu.SegDesc,
    started: bool,
    ncli: u32,
    intena: bool,
    proc: ?*Proc,
};

pub const ProcState = enum(u8) {
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
    cwd: ?*fs.Inode,
    name: [15:0]u8,
};

extern fn trapret() callconv(.C) void;
extern fn swtch(old: **Context, new: *Context) callconv(.C) void;

const initcode: []const u8 = @embedFile("init/initcode.bin");
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
// Then, trapret restores user registers and returns from the original interruption.
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

            // Set ret address = trapret
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

    p.cwd = dir.namei("/");

    ptable.lock.acquire();
    p.state = ProcState.RUNNABLE;
    ptable.lock.release();
}

pub fn scheduler() void {
    const cpu: *CPU = mycpu();
    cpu.proc = null;

    while (true) {
        // If there are any pending interrupts, handle them
        x86.sti();

        // Now disable them again and lock the ptable so we can safely operate on process scheduling
        ptable.lock.acquire();
        for (&ptable.proc) |*p| {
            if (p.state != ProcState.RUNNABLE) {
                continue;
            }

            cpu.proc = p;
            vm.switchuvm(p); // Interrupts from now on will use p.kstack
            p.state = ProcState.RUNNING;

            // After this call, we will start executing process p, which must:
            //  - release the ptable lock before starting execution (forkret does this)
            //  - re-acquire the ptable lock and update state before yielding back to the scheduler
            swtch(&cpu.scheduler, p.context);

            // p yielded back the the scheduler
            vm.switchkvm(); // Start using kernel's memory pages
            cpu.proc = null; // We are no longer running a process
        }
        ptable.lock.release();
    }
}

fn sched() void {
    const cpu = mycpu();
    const p = myproc() orelse unreachable;

    if (!ptable.lock.holding()) {
        @panic("sched: not holding table lock");
    }
    if (cpu.ncli != 1) {
        @panic("sched: locks");
    }
    if (p.state == ProcState.RUNNING) {
        @panic("sched: current process still running");
    }
    if (x86.readeflags() & mmu.FL_IF != 0) {
        @panic("sched: interruptible");
    }
    const intena = cpu.intena;
    swtch(&p.context, cpu.scheduler);
    mycpu().intena = intena;
}

pub fn yield() void {
    ptable.lock.acquire();
    myproc().?.state = ProcState.RUNNABLE;
    sched();
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
        fs.iinit(param.ROOTDEV);
        log.init(param.ROOTDEV);

        // TODO test code, remove
        const exec = @import("exec.zig");
        _ = exec.exec("./prog", @constCast(&[_][]const u8{ "ab", "abcd", "abc", "abdcef" }));
        console.cputs("Done testing\n");
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

    sched();

    p.chan = 0;
    if (lock != &ptable.lock) {
        ptable.lock.release();
        lock.acquire();
    }
}

pub fn wakeup1(chan: usize) void {
    for (&ptable.proc) |*p| {
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
    for (&ptable.proc) |*p| {
        if (p.state == ProcState.UNUSED) {
            continue;
        }
        const state = @tagName(p.state);
        console.cprintf("{d} {s} {s}", .{ p.pid, state, p.name });
        if (p.state == ProcState.SLEEPING) {
            var pcs: [10]usize = [1]usize{0} ** 10;
            procpcs(p, &pcs);
            var i: usize = 0;
            while (i < pcs.len and pcs[i] != 0) : (i += 1) {
                console.cprintf(" {x}", .{pcs[i]});
            }
        }
        console.cputs("\n");
    }
}

fn procpcs(proc: *Proc, pcs: []usize) void {
    const ebp_ptr: *usize = @ptrFromInt(@intFromPtr(&proc.context.ebp) + 2 * @sizeOf(usize));
    var ebp = ebp_ptr.*;
    var i: usize = 0;
    while (ebp != 0 and ebp != 0xFFFF_FFFF and ebp >= memlayout.KERNBASE and i < pcs.len) : (i += 1) {
        const p: [*]const usize = @ptrFromInt(ebp);
        ebp = p[0];
        pcs[i] = p[1];
    }
    while (i < pcs.len) : (i += 1) {
        pcs[i] = 0;
    }
}
