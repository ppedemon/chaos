//! IOAPIC configuration. For the full details, check manual at:
//!   - https://pdos.csail.mit.edu/6.828/2016/readings/ia32/ioapic.pdf

const mp = @import("mp.zig");
const sh = @import("sh.zig");
const trap = @import("trap.zig");

const IOAPIC = 0xFEC0_0000;

const REG_ID = 0x00;
const REG_VER = 0x01;
const REG_TABLE = 0x10;

const INT_DISABLED = 0x0001_0000;
const INT_LEVEL = 0x0000_8000;
const INT_ACTIVELOW = 0x0000_2000;
const INT_LOGICAL = 0x0000_0800;

var ioapic: *IOApic = undefined;

const IOApic = extern struct {
    reg: u32,
    pad: [12]u8,
    data: u32,

    const Self = @This();

    fn read(self: *Self, reg: u32) u32 {
        self.reg = reg;
        return self.data;
    }

    fn write(self: *Self, reg: u32, data: u32) void {
        self.reg = reg;
        self.data = data;
    }
};

pub fn ioapicinit() void {
    ioapic = @ptrFromInt(IOAPIC);

    const maxintr = (ioapic.read(REG_VER) >> 16) & 0xFF;
    const id = (ioapic.read(REG_ID) >> 24) & 0x0F;
    if (id != mp.ioapicid) {
        sh.panic("Unrecognized IOAPIC id");
    }

    var i: u32 = 0;
    while (i <= maxintr) : (i += 1) {
        ioapic.write(REG_TABLE + 2 * i, INT_DISABLED | (trap.T_IRQ0 + i));
        ioapic.write(REG_TABLE + 2 * i + 1, 0);
    }
}

pub fn ioapicenable(irq: u32, cpunum: u32) void {
    ioapic.write(REG_TABLE + 2 * irq, trap.T_IRQ0 + irq);
    ioapic.write(REG_TABLE + 2 * irq + 1, cpunum << 24);
}
