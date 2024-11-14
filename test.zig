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

pub fn main() void {
    init();
    scrollup();
    show();
}
