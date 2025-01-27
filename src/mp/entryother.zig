export fn _start() callconv(.Naked) noreturn {
    asm volatile ("call start");
}
