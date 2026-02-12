.align 4
.section .text
.globl _start

_start:

################################################################
# ADD / SUB
################################################################
    addi    t0, x0, 10
    addi    t1, x0, 5
    add     a0, t0, t1       # 10 + 5 = 15
    sub     a1, t0, t1       # 10 - 5 = 5
    sub     a2, t1, t0       # 5 - 10 = -5 (0xFFFFFFFB)
    add     a3, a0, a2       # RAW hazard: 15 + (-5) = 10

################################################################
# SLT / SLTU (signed/unsigned comparison)
################################################################
    addi    t0, x0, -1       # 0xFFFFFFFF
    addi    t1, x0, 1
    slt     a0, t0, t1       # signed: -1 < 1 → 1
    sltu    a1, t0, t1       # unsigned: 0xFFFFFFFF < 1 → 0
    slt     a2, t1, t0       # signed: 1 < -1 → 0
    sltu    a3, t1, t0       # unsigned: 1 < 0xFFFFFFFF → 1

################################################################
# LOGICAL ops (AND, OR, XOR)
################################################################
    lui     t0, 0xFFFF0      # 0xFFFF0000
    addi    t0, t0, 0xF0     # 0xFFFF00F0
    lui     t1, 0x00FF0      # 0x00FF0000

    and     a0, t0, t1       # 0x00FF0000
    or      a1, t0, t1       # 0xFFFF0FFF
    xor     a2, t0, t1       # 0xFF00FFF
    and     a3, a1, a2       # RAW hazard chain

################################################################
# SHIFT ops (register)
################################################################
    addi    t0, x0, 0xF0     # 0x000000F0
    addi    t1, x0, 4
    sll     a0, t0, t1       # 0x00000F00
    li      x11, 0xffbfffff
    li      x12, 0x0000000f
    srl     a1, x11, x12       # 0x000000F0
    sra     a2, a0, t1       # 0x000000F0 (same since positive)
    addi    t2, x0, -8       # 0xFFFFFFF8
    sra     a3, t2, t1       # arithmetic right shift (preserves sign) → 0xFFFFFFFF

################################################################
# IMMEDIATE arithmetic/logical ops
################################################################
    addi    t0, x0, 10
    addi    a0, t0, -5       # 10 + (-5) = 5
    slti    a1, t0, 20       # 10 < 20 → 1
    sltiu   a2, t0, 5        # 10 < 5 unsigned → 0
    xori    a3, t0, 0x0F     # 10 ^ 15 = 5
    ori     a4, t0, 0xF0     # 10 | 0xF0 = 0xFA
    andi    a5, t0, 0xF      # 10 & 15 = 10

################################################################
# SHIFT-IMMEDIATE ops
################################################################
    lui     t0, 0x00010      # 0x00010000
    slli    a0, t0, 3        # 0x00080000
    srli    a1, a0, 3        # 0x00010000
    srai    a2, a0, 3        # 0x00010000
    addi    t1, x0, -16
    srai    a3, t1, 2        # 0xFFFFFFF0 >>2 (arith) → 0xFFFFFFFC

################################################################
# LUI and mixing with arithmetic
################################################################
    lui     a0, 0x12345      # 0x12345000
    addi    a1, a0, 0x678    # 0x12345678
    addi    a2, a1, -0x678   # 0x12345000 again (reverse check)
    sub     a3, a1, a0       # 0x678

################################################################
# RAW/WAW/WAR dependency stress
################################################################
    addi    t0, x0, 1
    addi    t1, x0, 2
    add     t2, t0, t1       # 3
    sub     t2, t2, t0       # WAW: overwrite t2 (3-1=2)
    add     t3, t2, t1       # RAW: 2+2=4
    xor     t1, t3, t0       # WAR: t1 overwritten (4^1=5)
    and     t4, t1, t2       # final chain check

################################################################
# END / HALT
################################################################
halt:
    slti x0, x0, -256
