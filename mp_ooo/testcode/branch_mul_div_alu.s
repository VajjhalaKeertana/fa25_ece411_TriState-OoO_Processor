.align 4
.section .text
.globl _start

_start:

    # Init registers
    li x1, 5
    li x2, 10
    li x3, 3
    li x4, 2
    li x10, 4        # loop count

    nop
    nop

loop_start:

    # Branch not taken most of the time
    beq x1, x2, skip1
    mul x5, x1, x3       # executes normally
    add x6, x5, x2
skip1:

    # Branch taken every iteration
    beq x1, x1, taken1
    mul x7, x2, x3       # flushed
    add x8, x7, x1       # flushed
taken1:

    # Mixed ALU/MUL/DIV chain
    sub x9, x2, x1
    mul x11, x9, x4
    div x12, x11, x3
    xor x13, x12, x5

    # Decrement loop counter
    addi x10, x10, -1

    # Loop again if x10 > 0
    bne x10, x0, loop_start

# Halt (your preferred style)
halt:
    slti x0, x0, -256
