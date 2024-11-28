# Context switch
#
#   void swtch(struct context **old, struct context *new);
# 
# Save the current registers on the current kstack, creating a struct context, and
# save its address in *old. Switch stacks to new and pop previously-saved registers.
.globl swtch
swtch:
  movl 4(%esp), %eax    # eax = old
  movl 8(%esp), %edx    # edx = new

  # Save old callee-saved registers on current kstack
  pushl %ebp
  pushl %ebx
  pushl %esi
  pushl %edi

  # Switch stacks
  movl %esp, (%eax)   # *old = %esp
  movl %edx, %esp     # %esp = new

  # Restore new context
  popl %edi
  popl %esi
  popl %ebx
  popl %ebp

  # Since we switched stacks, this returns to whoever called swtch in the new context.
  # That is, this won't necessarily return to the current caller of swtch
  ret
