const x86 = @import("x86.zig");

const IO_PIC1 = 0x20;
const IO_PIC2 = 0xA0;

pub fn picinit() void {
    // Mask out all interrupts in master and slave PICs, we will use the APIC instead
    x86.out(IO_PIC1 + 1, @as(u8, 0xFF));
    x86.out(IO_PIC2 + 1, @as(u8, 0xFF));
}
