const console = @import("console.zig");
const kbd = @import("kbd.zig");
const mmu = @import("mmu.zig");
const lapic = @import("lapic.zig");
const proc = @import("proc.zig");
const sh = @import("sh.zig");
const spinlock = @import("spinlock.zig");
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

export fn trap(tf: *x86.TrapFrame) void {
  if (tf.trapno == T_SYSCALL) {
    // TODO sys calls
  }

  switch (tf.trapno) {
    T_IRQ0 + IRQ_TIMER => {
      tickslock.acquire();
      ticks +%= 1;
      proc.wakeup(@intFromPtr(&ticks));
      tickslock.release();
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
      // TODO Implement
    },
    else => {
      sh.panic("Unhandled Exception");
    },
  }
}