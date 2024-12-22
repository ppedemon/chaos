export fn _start() callconv(.Naked) noreturn {
    asm volatile (
        \\ movl $0xFFFFFFFF, %ebp
        \\ call main
        \\ pushl %eax
        \\ movl $2, %eax  # SYS_exit = 2
        \\ int $64        # T_SYSCALL = 64
    );
}
