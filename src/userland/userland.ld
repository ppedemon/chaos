OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)
ENTRY(_start)

SECTIONS
{
    . = 0;

    .text : ALIGN(0x1000) {
        *(.text)
    }

    .data : ALIGN(0x1000) {
        *(.data)
    }

    .bss : ALIGN(0x1000) {
        *(.bss)
    }

    .rodata : ALIGN(0x1000) {
        *(.rodata)
    }

    /DISCARD/ : {
        *(.comment)
        *(.note)
        *(.debug*)
    }
}
