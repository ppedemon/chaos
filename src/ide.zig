//! Interfacing ATA devices connected through an IDE cable. For further details, go to:
//!   https://wiki.osdev.org/ATA_PIO_Mode

const bio = @import("bio.zig");
const ioapic = @import("ioapic.zig");
const mp = @import("mp.zig");
const spinlock = @import("spinlock.zig");
const trap = @import("trap.zig");
const x86 = @import("x86.zig");

const SECTOR_SIZE = 512;

const IDE_BSY = 0x80;
const IDE_DRDY = 0x40;
const IDE_DF = 0x20; // Drive Fault error
const IDE_ERR = 0x01;

const IDE_CMD_READ = 0x20;
const IDE_CMD_WRITE = 0x30;
const IDE_CMD_RDMUL = 0xc4;
const IDE_CMD_WRMUL = 0xc5;

var lock = spinlock.SpinLock.init("ide");
var idequeue: *bio.Buf = undefined;

var havedisk1 = false;

fn idewait(checkerr: bool) ?void {
    var r: u8 = undefined;

    // Select disk #0
    x86.out(0x1F6, @as(u8, 0xE0 | 0 << 4));

    while (true) {
        r = x86.in(u8, 0x1F7);
        if (r & (IDE_BSY | IDE_DRDY) == IDE_DRDY) {
            break;
        }
    }

    if (checkerr and (r & (IDE_DF | IDE_ERR)) != 0) {
        return null;
    }
}

pub fn ideinit() void {
    ioapic.ioapicenable(trap.IRQ_IDE, mp.ncpu);
    idewait(false) orelse return;

    // Check if disk 1 is present
    x86.out(0x1F6, @as(u8, 0xE0 | 1 << 4));
    for (0..1000) |_| {
        if (x86.in(u8, 0x1F7) != 0) {
            havedisk1 = true;
            break;
        }
    }

    // Back to disk 0
    x86.out(0x1F6, @as(u8, 0xE0 | 0 << 4));
}
