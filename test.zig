const std = @import("std");

const dir = @import("src/dir.zig");
const fs = @import("src/fs.zig");
const string = @import("src/string.zig");

var framebuf: [25 * 80]u16 = undefined;
// const stdout = std.io.getStdOut().writer();

// var pos: usize = 1920;

// fn init() void {
//     var c: u16 = 'A';
//     for (0..framebuf.len) |i| {
//         framebuf[i] = c;
//         if (i % 80 == 79) {
//             c += 1;
//         }
//     }
// }

// fn show() void {
//     for (0..framebuf.len) |i| {
//         if (i % 80 == 0) {
//             stdout.print("{d:0>4}: ", .{i}) catch unreachable;
//         }
//         const c: u8 = if (i == pos) '.' else @intCast(framebuf[i] & 0xFF);
//         stdout.print("{c}", .{c}) catch unreachable;
//         if (i % 80 == 79) {
//             stdout.print(" :{d:0>4}\n", .{i}) catch unreachable;
//         }
//     }
// }

// fn scrollup() void {
//     string.memmove(@intFromPtr(&framebuf), @intFromPtr(&framebuf[80]), @sizeOf(u16) * 23 * 80);
//     pos -= 80;
//     @memset(framebuf[pos .. pos + 24 * 80 - pos], ' ');
// }

// const Buf = struct {
//     n: u32,
//     next: ?*Buf = null,
// };

// var head: ?*Buf = null;

// fn append(n: *Buf) void {
//     var p = &head;
//     while (p.* != null) : (p = &p.*.?.next) {}
//     p.* = n;
// }

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

    // var buf: [512]u8 = undefined;
    // const res = try std.io.getStdIn().reader().readUntilDelimiter(&buf, '\n');
    // std.debug.print("Read: {s}\n", .{res});
    // const x: ?u32 = if (std.mem.eql(u8, res, "null")) null else 20;
    // std.debug.print("x = {?}\n", .{x});
    // const y: u32 = x orelse {
    //     std.debug.print("BAD\n", .{});
    //     return;
    // };
    // std.debug.print("y = {}\n", .{y});

    // {
    //     std.debug.print("In block\n", .{});
    //     defer std.debug.print("Leaving block\n", .{});
    //     if (x) |_| {
    //         std.debug.print("Returning\n", .{});
    //         return;
    //     }
    // }
    // std.debug.print("Not returned\n", .{});

    // var i: u32 = 0;
    // while (i < 5) : (i += 1) {
    //     defer std.debug.print("Deferred for iteration {}\n", .{i});
    //     if (i == 3) break;
    //     std.debug.print("This is iteration {}\n", .{i});
    // }

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

    // var buf: [4096]u8 = [1]u8{0} ** 4096;
    // buf[0] = 'A';
    // buf[10] = 'B';
    // const p = @intFromPtr(&buf[0]);
    // const pbuf: [*]u8 = @ptrFromInt(p);
    // const slice: []u8 = pbuf[0..10000];

    // std.debug.print("buf[0] = {c}\n", .{buf[0]});
    // std.debug.print("p = 0x{x}\n", .{p});
    // std.debug.print("pbuf[0] = {c}\n", .{pbuf[0]});
    // std.debug.print("pbuf[10] = {c}\n", .{pbuf[10]});
    // std.debug.print("slice[0] = {c}\n", .{slice[0]});
    // std.debug.print("slice[10] = {c}\n", .{slice[10]});
    // std.debug.print("slice[30] = {d}\n", .{slice[30]});
    // std.debug.print("slice[6000] = {d}\n", .{slice[9500]});

    //f(@constCast(&[_][]const u8 {"a", "b", "c"}));

    // var page: [4096]u8 align(4) = [_]u8{0} ** 4096;
    // var stack: [*]u8 = @ptrCast(&page);

    // p.sz = @intFromPtr(&stack[4095]);

    // // str at 0xff8
    // const str = "abcde";
    // p.esp = page.len - (str.len + 1) & ~@as(usize, 7);
    // @memcpy(stack[p.esp .. p.esp + str.len], str);
    // std.debug.print("str = 0x{x}, offset = 0x{x}\n", .{
    //     &stack[p.esp],
    //     @intFromPtr(&stack[p.esp]) - @intFromPtr(&stack[0]),
    // });

    // // ptr to str at 0xff0
    // p.esp -= @sizeOf(usize);
    // var ptr: *usize = @ptrCast(@alignCast(&stack[p.esp]));
    // ptr.* = @intFromPtr(&stack[p.esp]) + @sizeOf(usize);
    // std.debug.print("pointer to str = 0x{x}, offset = 0x{x}\n", .{
    //     &stack[p.esp],
    //     @intFromPtr(&stack[p.esp]) - @intFromPtr(&stack[0]),
    // });

    // // 0xcafe_babe at 0xfe8
    // p.esp -= @sizeOf(usize);
    // ptr = @alignCast(@ptrCast(&stack[p.esp]));
    // ptr.* = 0x0bad_babe;
    // std.debug.print("int = 0x{x}, offset = 0x{x}\n", .{
    //     &stack[p.esp],
    //     @intFromPtr(&stack[p.esp]) - @intFromPtr(&stack[0]),
    // });

    // // buffer of size 0x10 at 0xfd8
    // p.esp -= 0x10;
    // const addr = &stack[p.esp];
    // @memset(stack[p.esp..p.esp + 0x10], 0xfa);
    // std.debug.print("buffer = 0x{x}, offset = 0x{x}\n", .{
    //     &stack[p.esp],
    //     @intFromPtr(&stack[p.esp]) - @intFromPtr(&stack[0]),
    // });

    // // Pointer to buffer in 0xfd0
    // p.esp -= @sizeOf(usize);
    // ptr = @alignCast(@ptrCast(&stack[p.esp]));
    // ptr.* = @intFromPtr(addr);
    // std.debug.print("pointer to buffer = 0x{x}, offset = 0x{x}\n", .{
    //     &stack[p.esp],
    //     @intFromPtr(&stack[p.esp]) - @intFromPtr(&stack[0]),
    // });

    // p.esp -= @sizeOf(usize);
    // p.esp = @intFromPtr(&stack[p.esp]);
    // std.debug.print("esp = 0x{x}, offset = 0x{x}\n", .{
    //     p.esp,
    //     p.esp - @intFromPtr(&stack[0]),
    // });

    // Time to test arg functions
    // var i: i64 = undefined;
    // var ok = argint(3, &i); // We count args from zero
    // std.debug.print("i = 0x{x}, ok = {}\n", .{ i, ok });

    // var pp: []const u8 = undefined;
    // const len = argstr(4, &pp);
    // std.debug.print("len = {}, string = {s}, len = {}\n", .{len, pp, pp.len});

    // ok = argptr(0, &pp, 0x10);
    // std.debug.print("buf addr = 0x{x}, len = {}, ok = {}\n", .{&pp[0], pp.len, ok});
    // for (pp, 0..) |c, ix| {
    //     std.debug.print("buf[{d}] = 0x{x}\n", .{ix, c});
    // }

    // const argv: [*]?[*:0]const u8 = @constCast(@ptrCast(&[_]?[*:0]const u8{
    //     "first",
    //     "second",
    //     "third",
    //     null,
    // }));

    // exec("/initcode", argv);
    // var buf: [14]u8 = [_]u8{'*'} ** 14;
    // @memset(&buf, 0);
    // const s: [*:0]const u8 = "hola";
    // const slice = std.mem.sliceTo(s, 0);
    // @memcpy(buf[0..slice.len], slice);
    // std.debug.print("buf = {s}, last = {}, terminator = {}\n", .{slice, buf[3], buf[4]});
    // const static = struct {
    //     var buf: [14]u8 = undefined;
    // };
    // @memset(&static.buf, ' ');
    // const path: [*:0]const u8 = "./letters01.txt+";
    // const slice = std.mem.sliceTo(path, 0);
    // const i = std.mem.lastIndexOf(u8, slice, "/");
    // const filename: []const u8 = if (i) |start| slice[start + 1 ..] else slice;
    // const len = @min(static.buf.len, filename.len);
    // @memcpy(static.buf[0..len], filename[0..len]);
    // const final: []const u8 = &static.buf;
    // std.debug.print("filename = |{s}|\n", .{final});
    var name: [13:0]u8 = undefined;
    @memset(name[0..name.len], 0);
    const s = "hola.txt";
    @memcpy(name[0..s.len], s);
    std.debug.print("|{s}|\n", .{std.mem.sliceTo(&name, 0)});
    std.debug.print("p = {*}, p[0] = {}", .{&name, (&name[0]).*});
}

const whitespace = " \t\r\n";
const symbols = "<|>&;()";

fn parseredirs(input: *[]const u8) void {
    var f: []const u8 = undefined;
    while (peek(input, "<>")) {
        const tok = gettok(input, null);
        if (gettok(input, &f) != 'a') {
            @panic("no redirection");
        }
        std.debug.print("tok = {s}, f = {s}\n", .{ [1]u8{tok}, f });
        break;
    }
}

fn gettok(input: *[]const u8, tok: ?*[]const u8) u8 {
    var s = std.mem.trim(u8, input.*, whitespace);
    if (tok != null) {
        tok.?.* = s;
    }
    var ret: u8 = 0;
    var len: usize = 0;
    if (s.len > 0) {
        ret = s[0];
        switch (s[0]) {
            '|', '(', ')', ';', '&', '<' => {
                len = 1;
                s = s[1..];
            },
            '>' => {
                len = 1;
                s = s[1..];
                if (s.len > 0 and s[0] == '>') {
                    len = 2;
                    ret = '+'; // file append
                    s = s[1..];
                }
            },
            else => {
                ret = 'a'; // alphanum
                len = std.mem.indexOfAny(u8, s, whitespace ++ symbols) orelse s.len;
                s = s[len..];
            },
        }
        if (tok != null) {
            tok.?.* = tok.?.*[0..len];
        }
        s = std.mem.trim(u8, s, whitespace);
    }
    input.* = s;
    return ret;
}

fn peek(input: *[]const u8, toks: []const u8) bool {
    if (std.mem.indexOfNone(u8, input.*, whitespace)) |start| {
        input.* = input.*[start..];
        return std.mem.indexOfAny(u8, toks, input.*[0..1]) != null;
    }
    input.* = input.*[input.len..];
    return false;
}

fn exec(path: [*:0]const u8, argv: [*]?[*:0]const u8) void {
    var i: usize = 0;
    while (path[i] != 0) : (i += 1) {
        std.debug.print("path[{}] = {c}\n", .{ i, path[i] });
    }

    i = 0;
    while (argv[i] != null) : (i += 1) {
        const args = argv[i].?;
        var j: usize = 0;
        while (args[j] != 0) : (j += 1) {
            std.debug.print("args[{}][{}] = {c}\n", .{ i, j, args[j] });
        }
    }

    std.debug.print("&argv = {}\n", .{&argv});
    std.debug.print("&argv[0] = {}\n", .{&argv[0]});
    std.debug.print("&argv[1] = {}\n", .{&argv[1]});

    const n: i32 = if (i % 2 == 1) -1 else 1;
    const m: u32 = @intCast(n);
    std.debug.print("m = {}\n", .{m});
}

pub fn _exec(_: [*:0]const u8, argv: [][*:0]const u8) i32 {
    var args: [argv.len + 1]?[*:0]const u8 = undefined;
    for (argv, 0..) |a, i| {
        args[i] = a;
    }
    argv[argv.len] = null;
    return 0;
}

const Proc = struct {
    sz: usize,
    esp: usize,
};
var p = Proc{
    .sz = 0,
    .esp = 0,
};

pub fn fetchint(addr: usize, ip: *i64) i64 {
    if (addr >= p.sz or addr + @sizeOf(i64) > p.sz) {
        return -1;
    }
    ip.* = @as(*i64, @ptrFromInt(addr)).*;
    return 0;
}

pub fn fetchstr(addr: usize, pp: *[]const u8) i64 {
    if (addr >= p.sz) {
        return -1;
    }
    const buf: [*]const u8 = @ptrFromInt(addr);
    for (0..p.sz) |i| {
        if (buf[i] == 0) {
            pp.* = buf[0..i];
            return @as(i64, @intCast(i));
        }
    }
    return -1;
}

pub fn argint(n: usize, ip: *i64) i64 {
    return fetchint(p.esp + @sizeOf(usize) + n * @sizeOf(usize), ip);
}

pub fn argptr(n: usize, pp: *[]const u8, size: usize) i64 {
    var i: i64 = undefined;
    if (argint(n, &i) < 0) {
        return -1;
    }

    const addr: u64 = @intCast(i);
    if (size < 0 or addr > p.sz or addr + size > p.sz) {
        return -1;
    }

    const buf: [*]const u8 = @ptrFromInt(addr);
    pp.* = buf[0..size];
    return 0;
}

pub fn argstr(n: usize, pp: *[]const u8) i64 {
    var i: i64 = undefined;
    if (argint(n, &i) < 0) {
        return -1;
    }
    return fetchstr(@as(usize, @intCast(i)), pp);
}

// fn f(argv: []const []const u8) void {
//     for (argv, 0..) |arg, i| {
//         std.debug.print("argv[{}] = {s}\n", .{i, arg});
//     }
// }
