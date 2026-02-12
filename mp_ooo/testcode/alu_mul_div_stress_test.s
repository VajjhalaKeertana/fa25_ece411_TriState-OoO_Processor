.align 4
.section .text
.globl _start

_start:

################################################################
# STRESS TEST: 128 PHYSICAL REG ALLOCATION VIA 32 ARCH REGS
################################################################

# Iteration 1: Arch x1-x31
    addi x1, x0, 1
    addi x2, x0, 2
    addi x3, x0, 3
    addi x4, x0, 4
    add x5, x1, x2
    mul x6, x3, x4
    divu x7, x6, x1
    remu x8, x7, x2
    xor x9, x8, x3
    or x10, x9, x4
    and x11, x10, x5
    sll x12, x11, 1
    srl x13, x12, 2
    addi x14, x13, 5
    sub x15, x14, x9
    mul x16, x15, x11
    divu x17, x16, x7
    remu x18, x17, x12
    add x19, x18, x13
    add x20, x19, x14
    add x21, x20, x15
    add x22, x21, x16
    add x23, x22, x17
    add x24, x23, x18
    add x25, x24, x19
    add x26, x25, x20
    add x27, x26, x21
    add x28, x27, x22
    add x29, x28, x23
    add x30, x29, x24
    add x31, x30, x25

# Iteration 2: x1-x31 again, new values
    addi x1, x31, 1
    addi x2, x1, 1
    addi x3, x2, 1
    addi x4, x3, 1
    add x5, x1, x2
    mul x6, x3, x4
    divu x7, x6, x1
    remu x8, x7, x2
    xor x9, x8, x3
    or x10, x9, x4
    and x11, x10, x5
    sll x12, x11, 2
    srl x13, x12, 1
    addi x14, x13, 6
    sub x15, x14, x9
    mul x16, x15, x11
    divu x17, x16, x7
    remu x18, x17, x12
    add x19, x18, x13
    add x20, x19, x14
    add x21, x20, x15
    add x22, x21, x16
    add x23, x22, x17
    add x24, x23, x18
    add x25, x24, x19
    add x26, x25, x20
    add x27, x26, x21
    add x28, x27, x22
    add x29, x28, x23
    add x30, x29, x24
    add x31, x30, x25

# Iteration 3: x1-x31 again
    addi x1, x31, 2
    addi x2, x1, 2
    addi x3, x2, 2
    addi x4, x3, 2
    add x5, x1, x2
    mul x6, x3, x4
    divu x7, x6, x1
    remu x8, x7, x2
    xor x9, x8, x3
    or x10, x9, x4
    and x11, x10, x5
    sll x12, x11, 3
    srl x13, x12, 1
    addi x14, x13, 7
    sub x15, x14, x9
    mul x16, x15, x11
    divu x17, x16, x7
    remu x18, x17, x12
    add x19, x18, x13
    add x20, x19, x14
    add x21, x20, x15
    add x22, x21, x16
    add x23, x22, x17
    add x24, x23, x18
    add x25, x24, x19
    add x26, x25, x20
    add x27, x26, x21
    add x28, x27, x22
    add x29, x28, x23
    add x30, x29, x24
    add x31, x30, x25

# Iteration 4: x1-x31 final
    addi x1, x31, 3
    addi x2, x1, 3
    addi x3, x2, 3
    addi x4, x3, 3
    add x5, x1, x2
    mul x6, x3, x4
    divu x7, x6, x1
    remu x8, x7, x2
    xor x9, x8, x3
    or x10, x9, x4
    and x11, x10, x5
    sll x12, x11, 4
    srl x13, x12, 2
    addi x14, x13, 8
    sub x15, x14, x9
    mul x16, x15, x11
    divu x17, x16, x7
    remu x18, x17, x12
    add x19, x18, x13
    add x20, x19, x14
    add x21, x20, x15
    add x22, x21, x16
    add x23, x22, x17
    add x24, x23, x18
    add x25, x24, x19
    add x26, x25, x20
    add x27, x26, x21
    add x28, x27, x22
    add x29, x28, x23
    add x30, x29, x24
    add x31, x30, x25

################################################################
# HALT
################################################################
halt:
    slti x0, x0, -256
