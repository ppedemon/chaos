# All traps handled by this function

.globl alltraps
alltraps:
  # Build trap frame
  pushl %ds
  pushl %es
  pushl %fs
  pushl %gs
  pushal

  # Setup data segments
  movw $(2<<3), %ax
  movw %ax, %ds
  movw %ax, %es

  # Call trap(tf), where tf = %esp
  pushl %esp
  call trap
  addl $4, %esp

# Return falls through trapret
.globl trapret
trapret:
  popal
  popl %gs
  popl %fs
  popl %es
  popl %ds
  addl $0x8, %esp # discard trapno and error code
  iret

# Hopefully unreachable
loop:
  jmp loop
