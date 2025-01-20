const std = @import("std");

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

const stat = @import("share").stat;

pub extern fn fork() callconv(.C) i32;
pub extern fn exit() callconv(.C) noreturn;
pub extern fn wait() callconv(.C) i32;
pub extern fn pipe(p: [*]u32) callconv(.C) i32;
pub extern fn read(fd: u32, buf: [*]u8, n: u32) callconv(.C) i32;
pub extern fn exec(path: [*:0]const u8, argv: [*]const ?[*:0]const u8) callconv(.C) i32;
pub extern fn fstat(fd: u32, st: *stat.Stat) callconv(.C) i32;
pub extern fn chdir(path: [*:0]const u8) callconv(.C) i32;
pub extern fn dup(fd: u32) callconv(.C) i32;
pub extern fn sbrk(sz: isize) callconv(.C) i32;
pub extern fn open(path: [*:0]const u8, omode: u32) callconv(.C) i32;
pub extern fn write(fd: u32, buf: [*]const u8, n: u32) callconv(.C) i32;
pub extern fn mknod(path: [*:0]const u8, major: u32, minor: u32) callconv(.C) i32;
pub extern fn mkdir(path: [*:0]const u8) callconv(.C) i32;
pub extern fn close(fd: u32) callconv(.C) i32;