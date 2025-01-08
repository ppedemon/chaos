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
pub extern fn exec(path: [*:0]const u8, argv: [*]?[*:0]const u8) callconv(.C) i32;
pub extern fn dup(fd: u32) callconv(.C) i32;
pub extern fn open(path: [*:0]const u8, omode: u32) callconv(.C) i32;
pub extern fn write(fd: u32, buf: [*]const u8, n: u32) callconv(.C) i32;
pub extern fn mknod(path: [*:0]const u8, major: u32, minor: u32) callconv(.C) i32;
