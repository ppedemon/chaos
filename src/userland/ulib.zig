const std = @import("std");
const syscall = @import("syscall.zig");

const share = @import("share");
const err = share.err;
const fcntl = share.fcntl;

pub fn fork() err.SysErr!u32 {
    return sysret(syscall.fork());
}

pub fn exit() noreturn {
    syscall.exit();
}

pub fn wait() err.SysErr!u32 {
    return sysret(syscall.wait());
}

pub fn pipe(p: [*]u32) err.SysErr!void {
    _ = try sysret(syscall.pipe(p));
}

pub fn read(fd: u32, buf: [*]u8, n: u32) err.SysErr!u32 {
    return sysret(syscall.read(fd, buf, n));
}

pub fn exec(path: [*:0]const u8, argv: [*]const ?[*:0]const u8) err.SysErr!void {
    _ = try sysret(syscall.exec(path, argv));
}

pub fn fstat(fd: u32, st: *share.stat.Stat) err.SysErr!void {
    _ = try sysret(syscall.fstat(fd, st));
}

pub fn chdir(path: [*:0]const u8) err.SysErr!void {
    _ = try sysret(syscall.chdir(path));
}

pub fn dup(fd: u32) err.SysErr!u32 {
    return sysret(syscall.dup(fd));
}

pub fn sbrk(sz: isize) err.SysErr!usize {
    const addr: u32 = try sysret(syscall.sbrk(sz));
    return @intCast(addr);
}

pub fn open(path: [*:0]const u8, omode: u32) err.SysErr!u32 {
    return sysret(syscall.open(path, omode));
}

pub fn write(fd: u32, buf: [*]const u8, n: u32) err.SysErr!u32 {
    return sysret(syscall.write(fd, buf, n));
}

pub fn mknod(path: [*:0]const u8, major: u32, minor: u32) err.SysErr!void {
    _ = try sysret(syscall.mknod(path, major, minor));
}

pub fn mkdir(path: [*:0]const u8) err.SysErr!void {
    _ = try sysret(syscall.mkdir(path));
}

pub fn close(fd: u32) err.SysErr!void {
    _ = try sysret(syscall.close(fd));
}

inline fn sysret(ret: i32) err.SysErr!u32 {
    if (ret >= 0) {
        return @intCast(ret);
    }
    return @errorCast(@errorFromInt(@as(u16, @intCast(-ret))));
}

pub const stdin: u32 = 0;
pub const stdout: u32 = 1;
pub const stderr: u32 = 2;

pub fn init() err.SysErr!void {
    _ = open("console", fcntl.O_RDWR) catch {
        try mknod("console", 1, 1);
        _ = try open("console", fcntl.O_RDWR); // stdin = 0
    };
    _ = try dup(0); // stdout = 1
    _ = try dup(0); // stderr = 2
}

pub fn fputs(fd: u32, s: []const u8) err.SysErr!void {
    _ = try write(fd, @ptrCast(s.ptr), s.len);
}

pub inline fn puts(s: []const u8) err.SysErr!void {
    fputs(stdout, s) catch unreachable;
}

var pbuf: [1024]u8 = undefined;

pub fn fprint(fd: u32, comptime format: []const u8, args: anytype) err.SysErr!void {
    var fba = std.heap.FixedBufferAllocator.init(pbuf[0..]);
    const allocator = fba.allocator();
    const s = std.fmt.allocPrint(allocator, format, args) catch "alloc error";
    _ = try write(fd, @ptrCast(s.ptr), s.len);
}

pub inline fn print(comptime format: []const u8, args: anytype) err.SysErr!void {
    return fprint(stdout, format, args);
}

pub fn gets(buf: []u8) err.SysErr![]u8 {
    var n: usize = 0;
    var c: u8 = undefined;
    for (0..buf.len) |i| {
        const res = try read(stdin, @ptrCast(&c), 1);
        if (res < 1) {
            return buf[0..0];
        }
        n += 1;
        buf[i] = c;
        if (c == '\n' or c == '\r') {
            break;
        }
    }
    return buf[0..n];
}

pub fn stat(path: [*:0]const u8, st: *share.stat.Stat) err.SysErr!void {
    const fd = try open(path, fcntl.O_RDONLY);
    defer {
        _ = close(@intCast(fd)) catch {};
    }
    return fstat(@intCast(fd), st);
}

pub usingnamespace @import("malloc.zig");
