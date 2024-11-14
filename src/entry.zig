const console = @import("console.zig");
const mmu = @import("mmu.zig");
const param = @import("param.zig");

const MultibootHeader = packed struct {
    magic: u32,
    flags: u32,
    checksum: u32,
    _: u32 = 0,
};

export const multiboot_header align(4) linksection(".multiboot") = multiboot: {
    const MAGIC: u32 = 0x1BADB002;
    const ALIGN: u32 = 1 << 0;
    const MEMINFO: u32 = 1 << 1;
    const FLAGS: u32 = ALIGN | MEMINFO;
    break :multiboot MultibootHeader{
        .magic = MAGIC,
        .flags = FLAGS,
        .checksum = ~(MAGIC +% FLAGS) +% 1,
    };
};

export var stack: [param.KSTACKSIZE]u8 align(16) linksection(".bss") = undefined;

comptime {
    asm (
        \\ .globl _start
        \\ _start = start - 0x80000000
    );
}

export fn start() align(16) callconv(.Naked) noreturn {
    asm volatile (
        \\ movl %cr4, %eax
        \\ orl %[flags], %eax
        \\ movl %eax, %cr4
        :
        : [flags] "{ecx}" (mmu.CR4_PSE),
    );
    asm volatile (
        \\ movl $(entrypgdir - 0x80000000), %eax
        \\ movl %eax, %cr3
    );
    asm volatile (
        \\ movl %cr0, %eax
        \\ orl %[flags], %eax
        \\ movl %eax, %cr0
        :
        : [flags] "{ecx}" (mmu.CR0_PG | mmu.CR0_WP),
    );

    asm volatile (
        \\ movl $stack, %eax
        \\ addl %[sz], %eax
        \\ movl %eax, %esp
        \\ movl $0xFFFFFFFF, %ebp
        \\ movl $main, %eax
        \\ jmp *%eax
        :
        : [sz] "{ecx}" (param.KSTACKSIZE)
    );

    while (true) {}
}
