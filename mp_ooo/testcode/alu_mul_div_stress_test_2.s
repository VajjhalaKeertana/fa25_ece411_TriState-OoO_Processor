    .option norvc
    .align  4
    .section .text
    .globl  _start

_start:
# ===================== SEED (small constants) =====================
    addi x1,  x0,    7
    addi x2,  x0,   -3
    addi x3,  x0,    5
    addi x4,  x0,   11
    addi x5,  x0,   13
    addi x6,  x0,   17
    addi x7,  x0,   19
    addi x8,  x0,   23
    addi x9,  x0,    1
    addi x10, x0,    2
    addi x11, x0,    3
    addi x12, x0,   29        # reg shamt candidate
    addi x13, x0,   31        # reg shamt edge (low 5b=31)
    addi x14, x0,    0
    addi x15, x0,    0

# ============ 1) BACK-TO-BACK WAW (ALU + MUL/DIV interleaved) ============
# x20: ALU → ALU → MUL (signed) → DIV (signed)  (youngest must commit)
    add   x20, x1,  x2            # WAW(1)
    xor   x20, x3,  x4            # WAW(2)
    mul   x20, x5,  x6            # WAW(3) long (signed* signed, low 32)
    div   x20, x7,  x9            # WAW(4) youngest (signed)

# x21: DIV (signed) → ALU → MULH family to exercise high parts
    div   x21, x8,  x10           # WAW(1) long (signed)
    xori  x21, x21, 0x155         # WAW(2) imm (<= 0x7FF)
    mulh  x21, x4,  x5            # WAW(3) high (signed*signed)

# x22: ALU → DIVU → ALU with imm AND/OR/shift-imm in between
    and   x22, x6,  x7            # WAW(1)
    divu  x22, x5,  x9            # WAW(2) (unsigned)
    addi  x22, x22, 3             # keep within ±2047
    xori  x22, x22, 0x5A5         # 0x5A5 = 1445 fits
    andi  x22, x22, 0x7FF         # mask to <= 0x7FF
    slli  x22, x22, 1             # final WAW(3)

# ============ 2) WAR (older READ; younger WRITE same arch reg) ============
# WAR on x23: older reads x23; younger overwrites x23 via MUL; consume old chain
    add   x16, x23, x1            # older READ x23
    mul   x23, x2,  x3            # younger WRITE x23 (signed low)
    sub   x17, x16, x4            # uses value read before write

# WAR on x24 with long-latency reader (signed DIV)
    div   x18, x24, x9            # older READ x24 (long)
    andi  x24, x5,  0x0FF         # younger WRITE x24 (imm)
    add   x19, x18, x7            # consume div result

# WAR on x25 via rs2 use
    sub   x26, x1,  x25           # older READ x25 as rs2
    mul   x25, x6,  x7            # younger WRITE x25
    xor   x27, x26, x2            # consume older result

# ================= 3) RAW CHAINS (producer → consumers) =================
# RAW-A: producer → ALU → signed DIV (rs1)
    mul   x30, x1,  x4            # signed* signed low
    add   x31, x30, x2            # RAW on rs1
    div   x29, x31, x3            # RAW again (signed)

# RAW-B: producer → rs2 use → unsigned DIVU + safe immediates
    add   x28, x5,  x6            # produce
    sub   x27, x7,  x28           # RAW on rs2
    ori   x27, x27, 0x5A5         # <= 0x7FF
    divu  x26, x27, x9            # unsigned
    andi  x26, x26, 0x7FF         # <= 0x7FF

# RAW-C: XOR/AND chain + shifts (reg & imm)
    xor   x14, x3,  x4            # produce
    and   x15, x14, x5            # RAW
    sll   x10, x15, x12           # shift by reg (rs2 path)
    srli  x11, x10, 2             # imm shift (<=31)
    srai  x11, x11, 1             # imm shift (<=31)
    addi  x11, x11, 7
    xori  x11, x11, 0x3C

# ===== 4) Interleave all MUL-high variants + additional hazards =====
# High multiply family on varied signs:
    mulh   x5,  x1,  x2           # high (signed*signed)
    mulhsu x6,  x3,  x4           # high (signed*unsigned)
    mulhu  x7,  x5,  x6           # high (unsigned*unsigned)

# Signed/Unsigned div/rem mix:
    div    x8,  x7,  x1
    divu   x9,  x7,  x10
    rem    x10, x7,  x3
    remu   x11, x7,  x10

# ========== 5) Interleaved RAW/WAW/WAR on same regs + shifts ==========
    add   x21, x1,  x2            # produce x21
    xor   x9,  x21, x3            # RAW on x21
    mul   x21, x6,  x7            # WAW to x21 (long)
    andi  x9,  x9,  0x3FF         # imm <= 0x7FF
    div   x21, x5,  x10           # WAW to x21 (youngest)
    sll   x9,  x9,  x13           # rs2 reg shamt edge (31)

# WAR on x22 (again), then consume
    add   x5,  x22, x1            # older READ x22
    xori  x22, x22, 0x777         # younger WRITE x22 (<= 0x7FF)
    sub   x6,  x5,  x2

# Final two-src wave (forces ps2 correctness) + imm spices
    and   x7,  x21, x22
    addi  x7,  x7,  1
    xor   x8,  x7,  x20
    ori   x8,  x8,  0x040         # <= 0x7FF
    slli  x8,  x8,  2
    sub   x9,  x8,  x21
    xori  x9,  x9,  0x5A5         # <= 0x7FF

# ========================= HALT sentinel =========================
halt:
    slti  x0,  x0,  -256
