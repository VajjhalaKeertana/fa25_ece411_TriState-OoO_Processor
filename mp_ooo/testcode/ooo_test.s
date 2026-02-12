.align 4
.section .text
.globl _start
    # Simple OOO test with AUIPC instruction
_start:

# initialize
li x1, 10
li x2, 20
li x5, 50
li x6, 60
li x8, 21
li x9, 28
li x11, 8
li x12, 4
li x14, 3
li x15, 1

nop
nop
nop
nop
nop
nop

# AUIPC test — adds an immediate to PC
# This instruction is independent, so it can execute out of order
auipc x16, 0x1        # x16 = PC + (0x1 << 12) = PC + 4096
                      # You can also try other immediates like 0 or 0xFFFFF

# this should take many cycles
# if this writes back to the ROB after the following instructions, you get credit for CP2
mul x3, x1, x2

# these instructions should resolve before the multiply
add x4, x5, x6
xor x7, x8, x9
sll x10, x11, x12
and x13, x14, x15

halt:
    slti x0, x0, -256
