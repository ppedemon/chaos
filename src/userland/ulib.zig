comptime {
    asm (
        \\ .global fork
        \\ fork:
        \\  movl $1, %eax
        \\  int $64
        \\  ret
    );

    asm (
        \\ .global exit
        \\ exit:
        \\  movl $2, %eax
        \\  int $64
        \\  ret
    );

    asm (
        \\ .global wait
        \\ wait:
        \\  movl $3, %eax
        \\  int $64
        \\  ret
    );

    asm (
        \\ .global exec
        \\ exec:
        \\  movl $7, %eax
        \\  int $64
        \\  ret
    );

    asm (
        \\ .global dup
        \\ dup:
        \\  movl $10, %eax
        \\  int $64
        \\  ret
    );

    asm (
        \\ .global open
        \\ open:
        \\  movl $15, %eax
        \\  int $64
        \\  ret
    );

    asm (
        \\ .global write
        \\ write:
        \\  movl $16, %eax
        \\  int $64
        \\  ret
    );

    asm (
        \\ .global mknod
        \\ mknod:
        \\  movl $17, %eax
        \\  int $64
        \\  ret
    );
}

pub const O_RDONLY = 0x000;
pub const O_WRONLY = 0x001;
pub const O_RDWR = 0x002;
pub const O_CREATE = 0x200;

pub extern fn fork() callconv(.C) i32;
pub extern fn exit() callconv(.C) noreturn;
pub extern fn wait() callconv(.C) i32;
pub extern fn exec(path: [*:0]const u8, argv: [*]const ?[*:0]const u8) callconv(.C) i32;
pub extern fn dup(fd: u32) callconv(.C) i32;
pub extern fn open(path: [*:0]const u8, omode: u32) callconv(.C) i32;
pub extern fn write(fd: u32, buf: [*]const u8, n: u32) callconv(.C) i32;
pub extern fn mknod(path: [*:0]const u8, major: u32, minor: u32) callconv(.C) i32;

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
