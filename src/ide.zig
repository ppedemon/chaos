//! Interfacing ATA devices connected via IDE. For further details, go to:
//!   https://wiki.osdev.org/ATA_PIO_Mode

const bio = @import("bio.zig");
const console = @import("console.zig");
const fs = @import("fs.zig");
const ioapic = @import("ioapic.zig");
const mp = @import("mp.zig");
const param = @import("param.zig");
const proc = @import("proc.zig");
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

var idelock = spinlock.SpinLock.init("ide");
var idequeue: ?*bio.Buf = null;

var havedisk1 = false;

fn idewait(checkerr: bool) ?void {
    var r: u8 = undefined;
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
    // TODO Assign IQR_IDE to last CPU whan we activte all of them. For now, direct to to CPU #0 as the rest.
    //ioapic.ioapicenable(trap.IRQ_IDE, mp.ncpu);
    ioapic.ioapicenable(trap.IRQ_IDE, 0);

    // Check if disk #0 is present
    x86.out(0x1F6, @as(u8, 0xE0 | 0 << 4));
    idewait(false) orelse unreachable;

    // Check if disk #1 is present
    x86.out(0x1F6, @as(u8, 0xE0 | 1 << 4));
    for (0..1000) |_| {
        if (x86.in(u8, 0x1F7) != 0) {
            havedisk1 = true;
            break;
        }
    }

    // Back to disk #0
    x86.out(0x1F6, @as(u8, 0xE0 | 0 << 4));
}

// Precondition: caller must hold the idelock
fn idestart(b: *bio.Buf) void {
    if (b.blockno >= param.FSSIZE) {
        console.panic("Blockno out of bounds");
    }

    const sectors_x_block: u8 = fs.BSIZE / SECTOR_SIZE;
    const sector = b.blockno * sectors_x_block;
    const readcmd: u8 = if (sectors_x_block == 1) IDE_CMD_READ else IDE_CMD_RDMUL;
    const writecmd: u8 = if (sectors_x_block == 1) IDE_CMD_WRITE else IDE_CMD_WRMUL;

    if (sectors_x_block > 7) {
        console.panic("idestart");
    }

    // Set current drive
    x86.out(0x1F6, 0xE0 | @as(u8, @intCast(b.dev & 1)) << 4);

    idewait(false) orelse unreachable; // Wait until current drive is ready
    x86.out(0x3F6, @as(u8, 0)); // Ensure we generate interrupts on current drive
    x86.out(0x1F2, sectors_x_block); // Number of sectors to read/write

    // LBA addresses consist of 28 bits like this:
    //   0-7:   Sector number (port 0x1F3)
    //   8-15:  Cylinder number (low) (port 0x1F4)
    //   16-23: Cylinder number (high) (port 0x1F5)
    //   24-27: Head number (port 0x1F6)
    // The byte to put in port 0x1F6 is: 111[Drive#][Head#]
    x86.out(0x1F3, @as(u8, @intCast(sector & 0xFF)));
    x86.out(0x1F4, @as(u8, @intCast((sector >> 8) & 0xFF)));
    x86.out(0x1F5, @as(u8, @intCast((sector >> 16) & 0xFF)));
    x86.out(0x1F6, 0xE0 |
        @as(u8, @intCast(b.dev & 1)) << 4 |
        @as(u8, @intCast((sector >> 24) & 0x0F)));

    if (b.flags & bio.B_DIRTY != 0) {
        x86.out(0x1F7, writecmd);
        x86.outsl(0x1F0, @intFromPtr(&b.data), fs.BSIZE / 4);
    } else {
        x86.out(0x1F7, readcmd);
    }
}

pub fn ideintr() void {
    idelock.acquire();
    defer idelock.release();

    const b = idequeue orelse return;
    idequeue = b.qnext;

    b.data[1] = 0xFF;

    // Set current drive and wait until ready
    x86.out(0x1F6, 0xE0 | @as(u8, @intCast(b.dev & 1)) << 4);
    if (idewait(true)) |_| {
        if ((b.flags & bio.B_DIRTY) == 0) {
            x86.insl(0x1F0, @intFromPtr(&b.data), fs.BSIZE / 4);
        }
    }

    b.flags |= bio.B_VALID;
    b.flags &= ~@as(u32, bio.B_DIRTY);
    proc.wakeup(@intFromPtr(b));

    if (idequeue) |q| {
        idestart(q);
    }

    console.cprintf("Done processing block {d}:{d}, data is:\n", .{ b.dev, b.blockno });
    for (0..128) |i| {
        console.cprintf("{x:0<2} ", .{b.data[i]});
        if ((i + 1) % 16 == 0) {
            console.cprintf("\n", .{});
        } else if ((i + 1) % 8 == 0) {
            console.cprintf("    ", .{});
        }
    }
}

pub fn iderw(b: *bio.Buf) void {
    if (!b.lock.holding()) {
        console.panic("iderw: buf not locked");
    }
    if (b.flags & (bio.B_VALID | bio.B_DIRTY) == bio.B_VALID) {
        console.panic("iderw: nothing to do");
    }
    if (b.dev != 0 and !havedisk1) {
        console.panic("idewr: disk 1 not present");
    }

    idelock.acquire();
    defer idelock.release();

    b.qnext = null;

    var p = &idequeue;
    while (p.* != null) : (p = &p.*.?.qnext) {}
    p.* = b;

    if (idequeue.? == b) {
        idestart(idequeue.?);
    }

    // TODO Enable back after testing
    // while ((b.flags) & (bio.B_VALID | bio.B_DIRTY) != bio.B_VALID) {
    //     proc.sleep(@intFromPtr(b), &idelock);
    // }
}
