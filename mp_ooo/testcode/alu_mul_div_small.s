.align 4
.section .text
.globl _start

_start:

################################################################
# STRESS TEST: 128 PHYSICAL REG ALLOCATION VIA 32 ARCH REGS
################################################################

# Cycle assumptions:
# MUL/DIV = 2 cycles, ALU = 1 cycle

li      x11, 0xffbfffff
    li      x12, 0x0000000f
    srl     a1, x11, x12 


################################################################
# HALT
################################################################
halt:
    slti x0, x0, -256
