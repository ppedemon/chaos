const std = @import("std");
const share = @import("share");
const fcntl = share.fcntl;

comptime {
    const syscalls = [_][]const u8{
        "fork",
        "exit",
        "wait",
        "pipe",
        "read",
        "kill",
        "exec",
        "fstat",
        "chdir",
        "dup",
        "getpid",
        "sbrk",
        "sleep",
        "uptime",
        "open",
        "write",
        "mknod",
        "unlink",
        "link",
        "mkdir",
        "close",
    };

    const template =
        \\ .global {s}
        \\ {s}:
        \\  movl ${}, %eax
        \\  int $64
        \\  ret
    ;

    for (syscalls, 1..) |name, i| {
        var buf: [512]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(buf[0..]);
        const allocator = fba.allocator();
        const s = std.fmt.allocPrint(allocator, template, .{ name, name, i }) catch unreachable;
        asm (s);
    }
}

pub extern fn fork() callconv(.C) i32;
pub extern fn exit() callconv(.C) noreturn;
pub extern fn wait() callconv(.C) i32;
pub extern fn pipe(p: [*]u32) callconv(.C) i32;
pub extern fn read(fd: u32, buf: [*]u8, n: u32) callconv(.C) i32;
pub extern fn kill(pid: u32) callconv(.C) i32;
pub extern fn exec(path: [*:0]const u8, argv: [*]const ?[*:0]const u8) callconv(.C) i32;
pub extern fn fstat(fd: u32, st: *share.stat.Stat) callconv(.C) i32;
pub extern fn chdir(path: [*:0]const u8) callconv(.C) i32;
pub extern fn dup(fd: u32) callconv(.C) i32;
pub extern fn getpid() callconv(.C) i32;
pub extern fn sbrk(sz: isize) callconv(.C) i32;
pub extern fn sleep(ticks: u32) callconv(.C) i32;
pub extern fn uptime() callconv(.C) i32;
pub extern fn open(path: [*:0]const u8, omode: u32) callconv(.C) i32;
pub extern fn write(fd: u32, buf: [*]const u8, n: u32) callconv(.C) i32;
pub extern fn mknod(path: [*:0]const u8, major: u32, minor: u32) callconv(.C) i32;
pub extern fn unlink(path: [*:0]const u8) callconv(.C) i32;
pub extern fn link(oldpath: [*:0]const u8, newpath: [*:0]const u8) callconv(.C) i32;
pub extern fn mkdir(path: [*:0]const u8) callconv(.C) i32;
pub extern fn close(fd: u32) callconv(.C) i32;

pub const stdin: u32 = 0;
pub const stdout: u32 = 1;
pub const stderr: u32 = 2;

pub fn init() void {
    if (open("console", fcntl.O_RDWR) < 0) {
        // Create an inode for device major 1 (that is, console)
        _ = mknod("console", 1, 1);
        _ = open("console", fcntl.O_RDWR); // stdin = 0
    }
    _ = dup(0); // stdout = 1
    _ = dup(0); // stderr = 2
}

pub fn fputs(fd: u32, s: []const u8) void {
    _ = write(fd, @ptrCast(s.ptr), s.len);
}

pub inline fn puts(s: []const u8) void {
    fputs(stdout, s);
}

pub fn fprint(fd: u32, comptime format: []const u8, args: anytype) void {
    const static = struct {
        var buf: [1024]u8 = undefined;
    };
    var fba = std.heap.FixedBufferAllocator.init(static.buf[0..]);
    const allocator = fba.allocator();
    const s = std.fmt.allocPrint(allocator, format, args) catch "error";
    _ = write(fd, @ptrCast(s.ptr), s.len);
}

pub inline fn print(comptime format: []const u8, args: anytype) void {
    fprint(stdout, format, args);
}

pub fn gets(buf: []u8) []u8 {
    var n: usize = 0;
    var c: u8 = undefined;
    for (0..buf.len) |i| {
        const res = read(stdin, @ptrCast(&c), 1);
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

pub fn stat(path: [*:0]const u8, st: *share.stat.Stat) i32 {
    const fd: i32 = open(path, fcntl.O_RDONLY);
    if (fd < 0) {
        return -1;
    }
    defer {
        _ = close(@intCast(fd));
    }
    return fstat(@intCast(fd), st);
}

pub usingnamespace @import("malloc.zig");
