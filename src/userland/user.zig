
comptime {
  asm (
    \\ .global exec
    \\ exec:
    \\  movl $7, %eax
    \\  int $64
    \\  ret 
  );
}

pub extern fn exec(path: [*:0]const u8, argv: [*]?[*:0]const u8) callconv(.C) i32;
