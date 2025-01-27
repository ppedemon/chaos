OUTPUT_FORMAT("elf32-i386", "elf32-i386", "elf32-i386")
OUTPUT_ARCH(i386)
ENTRY(_start)

SECTIONS
{
	. = 0x7000;

	.text : AT(0x7000) {
		*(.text)
	}
    
    /DISCARD/ : {
        *(.text.*)
        *(.data)
        *(.bss)
        *(.rodata)
        *(.comment)
        *(.note)
        *(.debug*)
    }
}
