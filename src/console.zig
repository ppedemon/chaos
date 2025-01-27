const std = @import("std");

const file = @import("file.zig");
const fs = @import("fs.zig");
const ioapic = @import("ioapic.zig");
const lapic = @import("lapic.zig");
const memlayout = @import("memlayout.zig");
const mp = @import("mp.zig");
const proc = @import("proc.zig");
const spinlock = @import("spinlock.zig");
const string = @import("string.zig");
const trap = @import("trap.zig");
const uart = @import("uart.zig");
const x86 = @import("x86.zig");

const ctrl = @import("kbd.zig").ctrl;

var panicked: bool = false;

pub var cons = struct {
    lock: spinlock.SpinLock,
    locking: bool,
}{
    .lock = spinlock.SpinLock.init("console"),
    .locking = false,
};

const CRTPORT = 0x3d4;

const bs = std.ascii.control_code.bs;
var crt: [*]volatile u16 = @ptrFromInt(memlayout.p2v(0xB8000));

pub fn consclear() void {
    string.memset(@intFromPtr(&crt[0]), 0, @sizeOf(u16) * 80 * 25);
    x86.out(CRTPORT, @as(u8, 14));
    x86.out(CRTPORT + 1, @as(u8, 0));
    x86.out(CRTPORT, @as(u8, 15));
    x86.out(CRTPORT + 1, @as(u8, 0));
}

pub fn cputs(msg: []const u8) void {
    if (cons.locking and !cons.lock.holding()) {
        cons.lock.acquire();
        defer cons.lock.release();
    }

    for (msg) |c| {
        consputc(c);
    }
}

var pbuf: [1024]u8 = undefined;

pub fn cprintf(comptime format: []const u8, args: anytype) void {
    if (cons.locking and !cons.lock.holding()) {
        cons.lock.acquire();
        defer cons.lock.release();
    }

    var fba = std.heap.FixedBufferAllocator.init(pbuf[0..]);
    const allocator = fba.allocator();
    const s = std.fmt.allocPrint(allocator, format, args) catch "error";
    cputs(s);
}

pub fn panic(msg: []const u8) noreturn {
    // If CPUs not inititialized yet, it's too early for a proper panic.
    // Just emit to console the given message and spin.
    if (mp.ncpu == 0) {
        cputs(msg);
        while (true) {}
    }

    x86.cli();
    cons.locking = true;

    cprintf("lapic id {d} panic: ", .{lapic.lapicid()});
    cprintf("{s}", .{msg});
    consputc('\n');

    var pcs: [10]usize = undefined;
    spinlock.getpcs(pcs[0..]);
    for (pcs) |pc| {
        cprintf("0x{x} ", .{pc});
    }
    consputc('\n');

    panicked = true;
    while (true) {}
}

fn cgaputc(c: u32) void {
    x86.out(CRTPORT, @as(u8, 14));
    var pos = @as(u16, x86.in(u8, CRTPORT + 1)) << 8;
    x86.out(CRTPORT, @as(u8, 15));
    pos |= @as(u16, x86.in(u8, CRTPORT + 1));

    switch (c) {
        '\n' => pos += 80 - pos % 80,
        bs => if (pos > 0) {
            pos -= 1;
        },
        else => {
            crt[pos] = @as(u16, @intCast(c & 0xFF)) | 0x0700; // Light gray on black background
            pos += 1;
        },
    }

    if (pos < 0 or pos > 25 * 80) {
        panic("pos under/overflow");
    }

    if (pos / 80 >= 24) {
        string.memmove(@intFromPtr(&crt[0]), @intFromPtr(&crt[80]), @sizeOf(u16) * 23 * 80);
        pos -= 80;
        string.memset(@intFromPtr(&crt[pos]), 0, @sizeOf(u16) * (24 * 80 - pos));
    }

    x86.out(CRTPORT, @as(u8, 14));
    x86.out(CRTPORT + 1, pos >> 8);
    x86.out(CRTPORT, @as(u8, 15));
    x86.out(CRTPORT + 1, pos);
    crt[pos] = ' ' | 0x0700;
}

fn consputc(c: u8) void {
    // If some CPU panicked, freeze other CPUs when they want to print
    if (panicked) {
        x86.cli();
        while (true) {}
    }

    if (c == bs) {
        uart.putc(bs);
        uart.putc(' ');
        uart.putc(bs);
    } else {
        uart.putc(c);
    }
    cgaputc(c);
}

const INPUT_BUF = 0x100;
var input = struct {
    buf: [INPUT_BUF]u8,
    r: u8,
    w: u8,
    e: u8,
}{
    .buf = undefined,
    .r = 0,
    .w = 0,
    .e = 0,
};

pub fn consoleread(ip: *fs.Inode, dst: []u8, n: u32) ?u32 {
    ip.iunlock();
    cons.lock.acquire();
    defer {
        cons.lock.release();
        ip.ilock();
    }

    var read_count: u32 = 0;
    while (read_count < n) {
        // Sleep while no input, leave if killed while sleeping
        while (input.r == input.w) {
            if (proc.myproc().?.killed) {
                return null;
            }
            proc.sleep(@intFromPtr(&input.r), &cons.lock);
        }

        const c = input.buf[input.r];
        input.r +%= 1;

        if (c == ctrl('D')) { // Ctrl+D = EOF
            // If part of the input buffer was already consumed,
            // leave so caller gets a 0-byte result on next read
            if (read_count > 0) {
                input.r -%= 1;
            }
            break;
        }

        dst[read_count] = c;
        read_count += 1;
        if (c == '\n') {
            break;
        }
    }

    return read_count;
}

pub fn consolewrite(ip: *fs.Inode, buf: []const u8, n: u32) ?u32 {
    ip.iunlock();
    cons.lock.acquire();
    defer {
        cons.lock.release();
        ip.ilock();
    }

    for (0..n) |i| {
        consputc(buf[i]);
    }

    return n;
}

pub fn consoleintr(getc: *const fn () ?u8) void {
    var procdump = false;

    cons.lock.acquire();
    defer {
        cons.lock.release();
        if (procdump) {
            proc.procdump();
        }
    }

    while (true) {
        var c = getc() orelse break;
        switch (c) {
            ctrl('P') => {
                procdump = true;
            },
            ctrl('U') => {
                while (input.e != input.w and input.buf[input.e -% 1] != '\n') {
                    input.e -%= 1;
                    consputc(bs);
                }
            },
            ctrl('H'), '\x7f' => {
                if (input.e != input.w) {
                    input.e -%= 1;
                    consputc(bs);
                }
            },
            else => {
                if (c != 0 and input.e -% input.r < INPUT_BUF) {
                    c = if (c == '\r') '\n' else c;
                    input.buf[input.e] = c;
                    input.e +%= 1;
                    consputc(c);
                    if (c == '\n' or c == ctrl('D') or input.e == input.r) {
                        input.w = input.e;
                        proc.wakeup(@intFromPtr(&input.r));
                    }
                }
            },
        }
    }
}

pub fn consoleinit() void {
    consclear();
    file.devsw[file.CONSOLE].write = consolewrite;
    file.devsw[file.CONSOLE].read = consoleread;
    cons.locking = true;
    ioapic.ioapicenable(trap.IRQ_KBD, 0);
}
