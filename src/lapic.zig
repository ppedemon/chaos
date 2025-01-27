//! Recommended readig to understand how to program the LAPIC unit:
//!   - https://wiki.osdev.org/APIC#Local_Vector_Table_Registers

const memlayout = @import("memlayout.zig");
const string = @import("string.zig");
const trap = @import("trap.zig");
const x86 = @import("x86.zig");

// LAPIC registers, divided by 4 for indexing a []u32
const ID = 0x0020 / @sizeOf(u32); // ID
const VER = 0x0030 / @sizeOf(u32); // Version
const TPR = 0x0080 / @sizeOf(u32); // Task Priority
const EOI = 0x00B0 / @sizeOf(u32); // Enf Of Interruption

const SVR = 0x00F0 / @sizeOf(u32); // Spurious Interrupt Vector
const ENABLE = 0x0000_0100; // Enable LAPIC

const ESR = 0x0280 / @sizeOf(u32); // Error Status

const ICRLO = 0x0300 / @sizeOf(u32); // Interrupt Command register (lo 32 bits)
const INIT = 0x00000500; // INIT/RESET
const STARTUP = 0x00000600; // Startup IPI
const DELIVS = 0x00001000; // Delivery status
const ASSERT = 0x00004000; // Assert interrupt (vs deassert)
const DEASSERT = 0x00000000;
const LEVEL = 0x00008000; // Level triggered
const BCAST = 0x00080000; // Send to all APICs, including self
const BUSY = 0x00001000;
const FIXED = 0x00000000;

const ICRHI = 0x0310 / @sizeOf(u32); // Interrupt Command Register (hi 32 bits)

const TIMER = 0x0320 / @sizeOf(u32); // LVT Timer Register
const X1 = 0x0000000B; // Divide counts by 1
const PERIODIC = 0x00020000; // Periodic

const PCINT = 0x0340 / @sizeOf(u32); // Performance Counter LVT
const LINT0 = 0x0350 / @sizeOf(u32); // LVT #1
const LINT1 = 0x0360 / @sizeOf(u32); // LVT #2

const ERROR = 0x0370 / @sizeOf(u32); // LVT #2
const MASKED = 0x0001_0000; // Interrupt masked

const TICR = 0x0380 / @sizeOf(u32); // Timer Initial Count
const TCCR = 0x0390 / @sizeOf(u32); // Timer Current Count
const TDCR = 0x03E0 / @sizeOf(u32); // Timir Divide Configuration

// Initialized in mp.mpinit()
pub var lapic: [*]u32 = undefined;

fn lapicw(index: u32, value: u32) void {
    lapic[index] = value;
    _ = lapic[index];
}

pub fn lapicinit() void {
    // Spurious Vector Register:
    // Bit 8 set = Local APIC enabled
    // Bits 0..7 = Spurious interrupt Vector (set to 32 + 31 = 63)
    lapicw(SVR, ENABLE | (trap.T_IRQ0 + trap.IRQ_SPURIOUS));

    // Timer config:
    //   - Set bits [0,1,3] (0b1011 = 0xB) of TDCR: divide by 1
    //   - Set timer in periodic mode, with timer interrupt vector = 32 + 0 = 32
    //   - Set Timer Initial Count Register to 1e7
    //
    // Since Qemu's LAPIC timer operates at 1Ghz:
    //  - Timer count will decrease 1Ghz/1 = 1e9 times per second
    //  - So initial count = 1e7 will reach zero 1e9/1e7 = 100 times per second
    //  - That is, with this config we will get a timer interrupt 100 times per second
    lapicw(TDCR, X1);
    lapicw(TIMER, PERIODIC | (trap.T_IRQ0 + trap.IRQ_TIMER));
    lapicw(TICR, 10_000_000);

    // Mask local interrupt lines, so no local interrupts.
    lapicw(LINT0, MASKED);
    lapicw(LINT1, MASKED);

    // Version register bits (16..23): number of Local Vector Table entries - 1
    // More than 4 LVT entries signal a new enough CPU that does performance monitoring.
    // If that's the case mask performance monitoring interrupts.
    if (((lapic[VER] >> 16) & 0xFF) >= 4) {
        lapicw(PCINT, MASKED);
    }

    // Map interrupt handling error to vector 32 + 19 = 51
    lapicw(ERROR, trap.T_IRQ0 + trap.IRQ_ERROR);

    // Clear error status (twice, since ESR requires back-to-back writer)
    lapicw(ESR, 0);
    lapicw(ESR, 0);

    // Ack any previous interrupts
    lapicw(EOI, 0);

    // Send an Init Level De-Assert to synchronise arbitration ID's
    lapicw(ICRHI, 0);
    lapicw(ICRLO, BCAST | INIT | LEVEL);
    while (lapic[ICRLO] & DELIVS != 0) {}

    // Route to the processor interrupts with priority > 0 (so, all of them)
    lapicw(TPR, 0);
}

pub fn lapicid() u32 {
    return lapic[ID] >> 24;
}

pub fn lapiceoi() void {
    lapicw(EOI, 0);
}

pub fn microdelay(_: u32) void {}

const CMOS_PORT = 0x70;

pub fn lapitstartap(apicid: u16, addr: u32) void {
    // Set CMOS shutdown code = 0x0A
    x86.out(CMOS_PORT, @as(u8, 0x0F));
    x86.out(CMOS_PORT + 1, @as(u8, 0x0A));

    // Warm reset vector at 0x40:0x67 must point at the AP startup code
    const pa = @as(u16, @intCast(addr)) >> 4;
    const wrv: [*]u8 = @ptrFromInt(memlayout.p2v(0x40 << 4 | 0x67));

    // NOTE Zig panics when trying to write an u16 to 0x40:0x67, a non-aligned
    // destination address. So hacky hacky, we write one byte at the time.
    // Mind endianness!
    wrv[0] = 0;
    wrv[1] = 0;
    wrv[2] = @intCast(pa & 0xFF);
    wrv[3] = @intCast(pa >> 8);

    // Universal startup algorithm:
    // Sent INIT (level triggered interrupt) to reset the other CPU
    lapicw(ICRHI, @as(u32, apicid) << 24);
    lapicw(ICRLO, INIT | LEVEL | ASSERT);
    microdelay(200);
    lapicw(ICRLO, INIT | LEVEL);
    microdelay(100);

    // Sent STARTUP inter-processor-interrupt to enter code in addr from the other cpu
    // The Intel algorithm states to send the interrupt twice, hence the loop below
    for (0..2) |_| {
        lapicw(ICRHI, @as(u32, apicid) << 24);
        lapicw(ICRLO, STARTUP | (addr >> 12));
        microdelay(200);
    }
}