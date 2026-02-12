.align 4
.section .text
.globl _start
    # -------------------------------------
    # Small OOO Branch Test (ALU + Branch)
    # -------------------------------------
_start:

# Initialize registers
li x1, 5
li x2, 10
li x3, 5

nop
nop

# Branch not taken (x1 != x2)
beq x1, x2, branch_not_taken
nop

# Branch taken (x1 == x3)
beq x1, x3, branch_taken
nop

# These should be flushed if branch taken
add x4, x1, x2
nop

branch_not_taken:
add x5, x1, x3     # Executes regardless of taken/not-taken
nop

branch_taken:
sub x6, x2, x1     # Should execute only when branch taken
nop

# Final ALU check
xor x7, x5, x6
nop

# Halt
halt:
    slti x0, x0, -256
