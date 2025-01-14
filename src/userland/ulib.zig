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

pub const O_RDONLY = 0x000;
pub const O_WRONLY = 0x001;
pub const O_RDWR = 0x002;
pub const O_CREATE = 0x200;

pub extern fn fork() callconv(.C) i32;
pub extern fn exit() callconv(.C) noreturn;
pub extern fn wait() callconv(.C) i32;
pub extern fn read(fd: u32, buf: [*]u8, n: u32) callconv(.C) i32;
pub extern fn exec(path: [*:0]const u8, argv: [*]const ?[*:0]const u8) callconv(.C) i32;
pub extern fn chdir(path: [*:0]const u8) callconv(.C) i32;
pub extern fn dup(fd: u32) callconv(.C) i32;
pub extern fn sbrk(sz: isize) callconv(.C) i32;
pub extern fn open(path: [*:0]const u8, omode: u32) callconv(.C) i32;
pub extern fn write(fd: u32, buf: [*]const u8, n: u32) callconv(.C) i32;
pub extern fn mknod(path: [*:0]const u8, major: u32, minor: u32) callconv(.C) i32;
pub extern fn close(fd: u32) callconv(.C) i32;

const std = @import("std");

pub var stdin: u32 = undefined;
pub var stdout: u32 = undefined;
pub var stderr: u32 = undefined;

export fn libinit() i32 {
    if (open("console", O_RDWR) < 0) {
        // Create an inode for device major 1 (that is, console)
        if (mknod("console", 1, 1) < 0) {
            return -1;
        }
        const result = open("console", O_RDWR);
        if (result < 0) {
            return -1;
        }
        stdin = @intCast(result);
        stdout = @intCast(dup(stdin));
        stderr = @intCast(dup(stdin));
    }
    return 0;
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

pub usingnamespace @import("malloc.zig");
