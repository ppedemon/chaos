export fn _start() callconv(.Naked) noreturn {
    asm volatile (
        \\ pushl 0x8(%esp) # push argv
        \\ pushl 0x8(%esp) # push argc
        \\ call main
        \\ pushl %eax     # if main returns call exit with result
        \\ movl $2, %eax  # SYS_exit = 2
        \\ int $64        # T_SYSCALL = 64
    );
}