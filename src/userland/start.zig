export fn _start() callconv(.Naked) noreturn {
    asm volatile (
        \\ pushl 0x8(%esp) # push argv
        \\ pushl 0x8(%esp) # push argc
        \\ movl $-1, %ebp
        \\ call libinit
        \\ cmpl $0, %eax
        \\ jnz _start_exit
        \\ call main
        \\ _start_exit:
        \\ movl $2, %eax  # SYS_exit = 2
        \\ int $64        # T_SYSCALL = 64
    );
}
