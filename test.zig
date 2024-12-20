const std = @import("std");

const dir = @import("src/dir.zig");
const fs = @import("src/fs.zig");
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

pub fn main() !void {
    // var n = Buf{.n = 1};
    // append(&n);

    // var u = Buf{.n = 2};
    // append(&u);

    // var v = Buf{.n = 3};
    // append(&v);

    // var p = head;
    // while (p != null) : (p = p.?.next) {
    //     std.debug.print("Node: {d}\n", .{p.?.n});
    // }

    // init();
    // scrollup();
    // show();

    // var dst: [15:0]u8 = undefined;
    // string.safecpy(&dst, "initcode");
    // const n = string.safeslice(&dst);
    // std.debug.print("Scanned = {s}\n", .{n});
    // for (dst, 0..) |c, i| {
    //     std.debug.print("dst[{d}] = {d}\n", .{i, c});
    // }
    // std.debug.print("dst[15] = {d}\n", .{dst[15]});

    // const fs = @import("src/fs.zig");
    // const dir = @import("src/dir.zig");

    // const s: []const u8 = "a";

    // const ts = "a";
    // var t: [fs.DIRSIZE:0]u8 = undefined;
    // @memset(&t, 0);
    // @memcpy(t[0..ts.len], ts);

    // std.debug.print("s == t = {}\n", .{dir.namecmp(&t, s)});

    // var name: [fs.DIRSIZE]u8 = undefined;
    // const np = dir.skipelem(".", &name);
    // std.debug.print("Result = {s}, rest = {s}\n", .{ name, np orelse "NULL" });
    // var name: [fs.DIRSIZE]u8 = undefined;
    // @memset(&name, 0);
    // @memcpy(name[0..13], "mkfs.zigaaaaa");
    // //const n = std.mem.span(@as([*:0]u8, @ptrCast(&name)));
    // const n = string.safeslice(@as([:0]u8, @ptrCast(&name)));
    // for (n, 0..) |c, i| {
    //     std.debug.print("c[{d}] = {c} {d}\n", .{i, c, i});
    // }

    var buf: [512]u8 = undefined;
    const res = try std.io.getStdIn().reader().readUntilDelimiter(&buf, '\n');
    std.debug.print("Read: {s}\n", .{res});
    const x: ?u32 = if (std.mem.eql(u8, res, "null")) null else 20;
    std.debug.print("x = {?}\n", .{x});
    const y: u32 = x orelse {
        std.debug.print("BAD\n", .{});
        return;
    };
    std.debug.print("y = {}\n", .{y});

    {
        std.debug.print("In block\n", .{});
        defer std.debug.print("Leaving block\n", .{});
        if (x) |_| {
            std.debug.print("Returning\n", .{});
            return;
        }
    }
    std.debug.print("Not returned\n", .{});

    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        defer std.debug.print("Deferred for iteration {}\n", .{i});
        if (i == 3) break;
        std.debug.print("This is iteration {}\n", .{i});
    }

    // const File = struct {
    //     ty: enum { FD_NONE, FD_PIPE, FI_INODE },
    //     ref: u32,
    //     readable: bool,
    //     writable: bool,
    // };

    // var f: File = .{
    //     .ty = .FD_NONE,
    //     .ref = 1,
    //     .readable = true,
    //     .writable = false,
    // };
    // const pf: *File = &f;
    // var fc: File = pf.*;

    // pf.ty = .FI_INODE;
    // pf.ref = 0;
    // pf.readable = false;

    // fc.ty = .FD_PIPE;
    // fc.ref = 3;
    // fc.writable = true;

    // {
    //     defer std.debug.print("Leaving block\n", .{});
    //     std.debug.print("In block\n", .{});
    // }

    // std.debug.print("pf = {any}\n", .{pf.*});
    // std.debug.print("fc = {any}\n", .{fc});
}
