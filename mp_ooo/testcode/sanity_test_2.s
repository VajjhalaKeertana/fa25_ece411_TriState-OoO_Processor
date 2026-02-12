sanity_test_2.s:
.align 4
.section .text
.globl _start
    # RV32I register/immediate ops sanity
    # Starts with li and tests basic immediates, logic, and shifts

_start:

# initialize
li    x1,  1
li    x2, 24

# operations
lui   x5, 0x12345
addi  x6, x5, 1
slti  x7,  x6, 0
sltiu x8,  x6, 0
xori  x9,  x6, 0x55
ori   x10, x6, 0xAA
andi  x11, x6, 0x0F
slli  x12, x6, 3
srli  x13, x6, 2
srai  x14, x6, 2
add   x15, x12, x13
sub   x16, x15, x14

# ensure rs2-based shifts are well-defined on buggy ALUs (mask to 5 LSBs)
andi  x6,  x6, 31

sll   x17, x15, x0       # shift by 0 (masking)
srl   x18, x15, x6       # rs2-based shift (uses x6[4:0])
sra   x19, x6,  x15
slt   x20, x6,  x15
sltu  x21, x6,  x15

halt:
    slti x0, x0, -256     # conventional halt (NOP since rd=x0)
