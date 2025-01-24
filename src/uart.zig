//! Find relevent article explining how to program a UART device here:
//!   - https://wiki.osdev.org/Serial_Ports

const console = @import("console.zig");
const ioapic = @import("ioapic.zig");
const lapic = @import("lapic.zig");
const trap = @import("trap.zig");
const x86 = @import("x86.zig");

const COM1 = 0x3f8;

var uart: bool = false;

pub fn uartinit() void {
    // Turn off FIFO signals
    x86.out(COM1 + 2, @as(u8, 0));

    // Set 9600 baud rate
    x86.out(COM1 + 3, @as(u8, 0x80));
    x86.out(COM1 + 0, @as(u8, 115200 / 9600));
    x86.out(COM1 + 1, @as(u8, 0));

    // 8 bits chars, 1 stop bit
    x86.out(COM1 + 3, @as(u8, 0x03));

    // Zero-out modem state, enable interrups on received data available
    x86.out(COM1 + 4, @as(u8, 0));
    x86.out(COM1 + 1, @as(u8, 0x01));

    // All bits set indicate no COM1 port
    if (x86.in(u8, COM1 + 5) == 0xFF) {
        return;
    }

    uart = true;

    // Ack preexisting interrupts and data, then enable interrupts
    _ = x86.in(u8, COM1 + 2);
    _ = x86.in(u8, COM1 + 0);

    // Send COM1 interrupts to CPU #0
    ioapic.ioapicenable(trap.IRQ_COM1, 0);

    // Write something to announce the OS is listening
    const str = "chaos!\n";
    for (str) |c| {
      putc(c);
    }
}

pub fn putc(c: u8) void {
  if (!uart) {
    return;
  }

  // Loop until Transmitter Holding Register Empty flag is set, then send c
  var i: u32 = 0;
  while (i < 128 and (x86.in(u8, COM1 + 5)) & 0x20 == 0) : (i += 1) {
    lapic.microdelay(10);
  }
  x86.out(COM1 + 0, c);
}

fn getc() ?u8 {
  if (!uart) {
    return null;
  }

  // If Data Ready flag not set there's nothing to return, otherwise read a byte
  if (x86.in(u8, COM1 + 5) & 0x01 == 0) {
    return null;
  }
  return x86.in(u8, COM1 + 0);
}

pub fn uartintr() void {
  console.consoleintr(getc);
}
