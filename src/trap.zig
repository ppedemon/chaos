const console = @import("console.zig");
const ide = @import("ide.zig");
const kbd = @import("kbd.zig");
const mmu = @import("mmu.zig");
const lapic = @import("lapic.zig");
const proc = @import("proc.zig");
const spinlock = @import("spinlock.zig");
const syscall = @import("syscall.zig");
const uart = @import("uart.zig");
const x86 = @import("x86.zig");

// SW Exception vector numbers (0..31)
pub const T_DIVIDE = 0;
pub const T_DEBUG = 1;
pub const T_NMI = 2;
pub const T_BRKPT = 3;
pub const T_OFLOW = 4;
pub const T_BOUND = 5;
pub const T_ILLOP = 6;
pub const T_DEVICE = 7;
pub const T_DBLFLT = 8;
pub const T_TSS = 10;
pub const T_SEGNP = 11;
pub const T_STACK = 12;
pub const T_GPFLT = 13;
pub const T_PGFLT = 14;
pub const T_FPERR = 16;
pub const T_ALIGN = 17;
pub const T_MCHK = 18;
pub const T_SIMDERR = 19;

pub const T_SYSCALL = 64; // System calls handled by vector #64
pub const T_DEFAULT = 500; // Vector #500 used as default catch-all handler

pub const T_IRQ0 = 32; // Timer IRQ0 (see below) handled by trap vector #32

// IRQ: HW interrupts
// They get vector numbers (32..63) as follows:
// IRQn handled by vector #(32 + n). So:
//   - Timer (IRQ0) → vector #32 (hence, T_IRQ0 = 32)
//   - Keyboard (IRQ1) → vector #33
//   - COM1 (IRQ4) → vector #36
//   - IDE Disk (IRQ14) → vector #46
//   - Interrupt Handling Error (IRQ19) → vector #51
//   - Spurious Exceptions (IRQ31) → vector #63
pub const IRQ_TIMER = 0;
pub const IRQ_KBD = 1;
pub const IRQ_COM1 = 4;
pub const IRQ_IDE = 14;
pub const IRQ_ERROR = 19;
pub const IRQ_SPURIOUS = 31;

var idt: [256]mmu.GateDesc = undefined;
extern const vectors: u32;

var tickslock = spinlock.SpinLock.init("timer");
pub var ticks: u32 = 0;

pub fn tvinit() void {
    const p = @intFromPtr(&vectors);
    const v: [*]u32 = @ptrFromInt(p);

    for (0..idt.len) |i| {
        idt[i] = mmu.GateDesc.new(false, mmu.SEG_KCODE << 3, v[i], mmu.DPL_KERNEL);
    }
    idt[T_SYSCALL] = mmu.GateDesc.new(true, mmu.SEG_KCODE << 3, v[T_SYSCALL], mmu.DPL_USER);
}

pub fn idtinit() void {
    x86.lidt(@intFromPtr(&idt), @sizeOf(@TypeOf(idt)));
}

// var times: usize = 0;

export fn trap(tf: *x86.TrapFrame) callconv(.C) void {
    if (tf.trapno == T_SYSCALL) {
        const curproc: *proc.Proc = proc.myproc() orelse @panic("trap: no proc for syscall");
        if (curproc.killed) {
            proc.exit();
        }
        curproc.tf = tf;
        syscall.syscall();
        if (curproc.killed) {
            proc.exit();
        }
        return;
    }

    switch (tf.trapno) {
        T_IRQ0 + IRQ_TIMER => {
            if (proc.cpuid() == 0) {
                tickslock.acquire();
                ticks +%= 1;
                proc.wakeup(@intFromPtr(&ticks));
                tickslock.release();
            }
            lapic.lapiceoi();
        },
        T_IRQ0 + IRQ_KBD => {
            kbd.kbdintr();
            lapic.lapiceoi();
        },
        T_IRQ0 + IRQ_COM1 => {
            uart.uartintr();
            lapic.lapiceoi();
        },
        T_IRQ0 + IRQ_IDE => {
            ide.ideintr();
            lapic.lapiceoi();
        },
        T_IRQ0 + 7, T_IRQ0 + IRQ_SPURIOUS => {
            console.cprintf("cpu{d}: spurious interrupt at {x}:{x}\n", .{ proc.cpuid(), tf.cs, tf.eip });
            lapic.lapiceoi();
        },
        else => {
            if (proc.myproc() == null or (tf.cs & 3) == 0) {
                // We trapped from the kernel, there's some programming error :(
                console.cprintf("Unexpected trap {d} from cpu {d} eip = {x} cr2 = 0x{x}\n", .{
                    tf.trapno,
                    proc.cpuid(),
                    tf.eip,
                    x86.rcr2(),
                });
                @panic("trap");
            } else {
                // Some userland app trapped
                console.cprintf("pid {d} {s}: trap {d} err {d} on cpu {d} eip = {x} addr = 0x{x} (killing)\n", .{
                    proc.myproc().?.pid,
                    proc.myproc().?.name,
                    tf.trapno,
                    tf.err,
                    proc.cpuid(),
                    tf.eip,
                    x86.rcr2(),
                });
                proc.myproc().?.killed = true;
            }
        },
    }

    if (proc.myproc()) |p| {
        if (p.killed and (tf.cs & 3) == mmu.DPL_USER) {
            proc.exit();
        }
        if (p.state == proc.ProcState.RUNNING and tf.trapno == T_IRQ0 + IRQ_TIMER) {
            proc.yield();
        }
        // NOTE: process might have been killed since yielding
        if (p.killed and (tf.cs & 3) == mmu.DPL_USER) {
            proc.exit();
        }
    }
}
