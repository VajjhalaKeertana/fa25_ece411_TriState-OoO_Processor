.section .text
.globl _start
_start:
    

lui   x1, 0xaaaaa        # x1 = 0xaaaaa000 (base pointer)

# Store a constant into memory
addi  x2, x0, 10         # x2 = 10
sw    x2, 0(x1)          # MEM[0xaaaaa000] = 10

# Load it back
lw    x3, 0(x1)          # x3 = MEM[0xaaaaa000] = 10


addi x10, x0, 0          # base register

# 1–40 dependent operations
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1

    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1

    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1

    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1

    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1

    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1

    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1

    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1

    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1

    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, 1

# Add with another constant
addi  x4, x0, 5          # x4 = 5
add   x5, x3, x4         # x5 = 10 + 5 = 15
# Store result at next location
sw    x5, 4(x1)          # MEM[0xaaaaa004] = 15

slti x0, x0, -256 # this is the magic instruction to end the simulation

    