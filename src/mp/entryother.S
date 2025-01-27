#define SEG_NULLASM  \
  .word 0, 0;        \
  .byte 0, 0, 0, 0   \

#define SEG_ASM(type,base,lim)                            \
  .word (((lim) >> 12) & 0xffff), ((base) & 0xffff);      \
  .byte (((base) >> 16) & 0xff), (0x90 | (type)),         \
          (0xC0 | (((lim) >> 28) & 0xf)), (((base) >> 24) & 0xff)

#define STA_X     0x8 // Executable segment
#define STA_W     0x2 // Writeable (non-executable segments)
#define STA_R     0x2 // Readable (executable segments)

#define SEG_KCODE 0x1 // Kernel code
#define SEG_KDATA 0x2 // Kernel data + stack

#define CR0_PE 0x00000001 // Protected mode enable
#define CR0_WP 0x00010000 // Write protect: forbid writing to read only pages with privilege level = 0
#define CR0_PG 0x80000000 // Enable paging

#define CR4_PSE 0x00000010 // Page size extension

.code16
.globl start
start:
  cli
  xorw %ax, %ax
  movw %ax, %ds
  movw %ax, %es
  movw %ax, %ss
  
  # Load a global descriptor table defining segments spanning
  # the [0, 4Gb] address range, and switch to protected mode.
  lgdt gdtdesc
  movl %cr0, %eax
  orl $CR0_PE, %eax
  movl %eax, %cr0

  # Complete transition to 32-bit protected mode
  ljmpl $(SEG_KCODE << 3), $start32

.code32
start32:
  movw $(SEG_KDATA << 3), %ax
  movw %ax, %ds
  movw %ax, %es
  movw %ax, %ss
  movw $0, %ax
  movw %ax, %fs
  movw %ax, %gs

  # Turn on page size extension for 4 Mb pages
  movl %cr4, %eax
  orl $CR4_PSE, %eax
  movl %eax, %cr4

  # Use entrypgdir as our initial page table
  movl (start-12), %eax
  movl %eax, %cr3

  # Turn on paging
  movl %cr0, %eax
  orl $(CR0_PE|CR0_PG|CR0_WP), %eax
  movl %eax, %cr0

  # Setup stack
  movl (start-4), %esp

  # Call mpenter()
  call *(start - 8)

spin:
  # We shouldn't reach here!
  jmp spin

.p2align 2
gdt:
  SEG_NULLASM
  SEG_ASM(STA_X|STA_R, 0, 0xffffffff)
  SEG_ASM(STA_W, 0, 0xffffffff)

gdtdesc:
  .word (gdtdesc - gdt - 1)
  .long gdt
