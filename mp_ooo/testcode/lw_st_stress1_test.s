.section .text
.globl _start
_start:

    ###############################################
    # Base pointer BELOW PC and 4-byte aligned
    ###############################################
    lui   x1, 0xccccc        # x1 = 0xAAAA9000 (safe, < PC)

    addi  x2, x0, 1
    addi  x3, x0, 2
    addi  x4, x0, 3
    addi  x5, x0, 4
    addi  x6, x0, 5
    addi  x7, x0, 6

    ###############################################
    # 50 LSQ STRESS OPS (word-aligned only)
    ###############################################

    # 1–10 RAW and WAW
    sw    x2,   0(x1)
    lw    x8,   0(x1)
    sw    x3,   4(x1)
    lw    x9,   4(x1)
    sw    x4,   8(x1)
    lw    x10,  8(x1)
    sw    x5,  12(x1)
    lw    x11, 12(x1)
    sw    x6,  16(x1)
    lw    x12, 16(x1)

    # 11–20  More hazards
    sw    x7,  20(x1)
    sw    x2,  20(x1)       # WAW
    lw    x13, 20(x1)
    lw    x14, 24(x1)
    sw    x3,  24(x1)       # WAR (load then write)
    lw    x15, 24(x1)
    sw    x4,  28(x1)
    sw    x5,  28(x1)       # WAW
    lw    x16, 28(x1)

    # 21–30  Different banks, still aligned
    sw    x6,  32(x1)
    lw    x17, 32(x1)
    sw    x7,  36(x1)
    lw    x18, 36(x1)
    sw    x2,  40(x1)
    lw    x19, 40(x1)
    sw    x3,  44(x1)
    lw    x20, 44(x1)
    sw    x4,  48(x1)
    lw    x21, 48(x1)

    # 31–40  Independent addresses (encourage OoO)
    sw    x5,  100(x1)
    lw    x22, 100(x1)
    sw    x6,  200(x1)
    lw    x23, 200(x1)
    sw    x7,  300(x1)
    lw    x24, 300(x1)
    sw    x2,  400(x1)
    lw    x25, 400(x1)
    sw    x3,  500(x1)
    lw    x26, 500(x1)

    # 41–50  Tight back-to-back hazards on same addresses
    sw    x4,   0(x1)
    lw    x27,  0(x1)
    sw    x5,   4(x1)
    lw    x28,  4(x1)
    sw    x6,   8(x1)
    sw    x7,   8(x1)       # WAW
    lw    x29,  8(x1)
    lw    x30,  8(x1)       # double-load same address
    sw    x2,  12(x1)
    lw    x31, 12(x1)

    ###############################################
    # End simulation
    ###############################################
    slti x0, x0, -256
