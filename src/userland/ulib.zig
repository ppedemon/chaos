comptime {
    asm (
        \\ .global exit
        \\ exit:
        \\  movl $2, %eax
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
        \\ .global open
        \\ open:
        \\  movl $15, %eax
        \\  int $64
        \\  ret 
    );
}

pub const O_RDONLY = 0x000;
pub const O_WRONLY = 0x001;
pub const O_RDWR = 0x002;
pub const O_CREATE = 0x200;

pub extern fn exit() callconv(.C) noreturn;
pub extern fn exec(path: [*:0]const u8, argv: [*]?[*:0]const u8) callconv(.C) i32;
pub extern fn open(path: [*:0]const u8, omode: u32) callconv(.C) i32;
