.align 4
.section .text
.globl _start
_start:

# ------------------------
# Register initialization
# ------------------------
li x1, 7
li x2, 14
li x3, 21
li x4, 28

nop
nop

# ------------------------
# ALU ops BEFORE JALR
# ------------------------
add x5, x1, x2
xor x6, x3, x4
and x7, x1, x3
nop

# ------------------------
# Compute JALR jump target with AUIPC + ADDI
# (Forward jump, short offset → safe for assembler)
# ------------------------
auipc x8, 0
addi  x8, x8, 12      # Jump forward by 12 bytes → lands at label 1f
nop

jalr x9, 0(x8)        # x9 = return address
add x10, x2, x4       # skipped due to JALR
nop

# ------------------------
# Landing spot for JALR
# ------------------------
1:
sub x11, x4, x1
or  x12, x3, x2
nop

# ------------------------
# More ALU after jump
# ------------------------
add x13, x11, x12
xor x14, x13, x1
nop

halt:
    slti x0, x0, -256
