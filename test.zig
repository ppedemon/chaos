const std = @import("std");
const string = @import("src/string.zig");

var framebuf: [25 * 80]u16 = undefined;
const stdout = std.io.getStdOut().writer();

var pos: usize = 1920;

fn init() void {
    var c: u16 = 'A';
    for (0..framebuf.len) |i| {
        framebuf[i] = c;
        if (i % 80 == 79) {
            c += 1;
        }
    }
}

fn show() void {
    for (0..framebuf.len) |i| {
        if (i % 80 == 0) {
            stdout.print("{d:0>4}: ", .{i}) catch unreachable;
        }
        const c: u8 = if (i == pos) '.' else @intCast(framebuf[i] & 0xFF);
        stdout.print("{c}", .{c}) catch unreachable;
        if (i % 80 == 79) {
            stdout.print(" :{d:0>4}\n", .{i}) catch unreachable;
        }
    }
}

fn scrollup() void {
    string.memmove(@intFromPtr(&framebuf), @intFromPtr(&framebuf[80]), @sizeOf(u16) * 23 * 80);
    pos -= 80;
    @memset(framebuf[pos .. pos + 24 * 80 - pos], ' ');
}

const Buf = struct {
    n: u32,
    next: ?*Buf = null,
};

var head: ?*Buf = null;

fn append(n: *Buf) void {
    var p = &head;
    while (p.* != null) : (p = &p.*.?.next) {}
    p.* = n;
}

pub fn main() void {
    var n = Buf{.n = 1};
    append(&n);

    var u = Buf{.n = 2};
    append(&u);

    var v = Buf{.n = 3};
    append(&v);

    var p = head;
    while (p != null) : (p = p.?.next) {
        std.debug.print("Node: {d}\n", .{p.?.n});
    }

    // init();
    // scrollup();
    // show();
}
