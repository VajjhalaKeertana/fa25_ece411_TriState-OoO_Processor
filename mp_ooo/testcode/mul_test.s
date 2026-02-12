dependency_test.s:
.align 4
.section .text
.globl _start
    # This program consists of small snippets
    # containing RAW, WAW, and WAR hazards

    # This test is NOT exhaustive
_start:

# initialize
################################################################
    # Test set 2: a=-3, b=7
    # a4..a7 = {mul, mulh, mulhsu, mulhu}
    ################################################################
    addi    t0, x0, -3
    addi    t1, x0, 7
    mulhsu  a6, t0, t1          # exp ffffffff
    mul     a4, t0, t1          # exp ffffffeb
    mulh    a5, t0, t1          # exp ffffffff
    mulhu   a7, t0, t1          # exp 00000006

################################################################
    # Test set 1: a=2, b=3
    # a0..a3 = {mul, mulh, mulhsu, mulhu}
    ################################################################
    addi    t0, x0, 2
    addi    t1, x0, 3
    mul     a0, t0, t1          # exp 00000006
    mulh    a1, t0, t1          # exp 00000000
    mulhsu  a2, t0, t1          # exp 00000000
    mulhu   a3, t0, t1          # exp 00000000

    

    ################################################################
    # Test set 3: a=0x7fffffff, b=2
    # s1..s4 = {mul, mulh, mulhsu, mulhu}
    ################################################################
    lui     t0, 0x80000         # t0 = 0x8000_0000
    addi    t0, t0, -1          # t0 = 0x7fff_ffff
    addi    t1, x0, 2
    mul     s1, t0, t1          # exp fffffffe
    mulh    s2, t0, t1          # exp 00000000
    mulhsu  s3, t0, t1          # exp 00000000
    mulhu   s4, t0, t1          # exp 00000000

    ################################################################
    # Test set 4: a=0x80000000 (-2147483648), b=3
    # s5..s8 = {mul, mulh, mulhsu, mulhu}
    ################################################################
    lui     t0, 0x80000         # t0 = 0x8000_0000
    addi    t1, x0, 3
    mul     s5, t0, t1          # exp 80000000
    mulh    s6, t0, t1          # exp fffffffe
    mulhsu  s7, t0, t1          # exp fffffffe
    mulhu   s8, t0, t1          # exp 00000001

    ################################################################
    # Test set 5: a=-1, b=-1
    # t2..t5 = {mul, mulh, mulhsu, mulhu}
    ################################################################
    addi    t0, x0, -1
    addi    t1, x0, -1
    mul     t2, t0, t1          # exp 00000001
    mulh    t3, t0, t1          # exp 00000000
    # MULHSU treats rs1 signed, rs2 unsigned (0xffffffff):
    mulhsu  t4, t0, t1          # exp ffffffff
    mulhu   t5, t0, t1          # exp fffffffe

    ################################################################
    # Test set 6: a=0, b=0x075BCD15 (123456789)
    # s9..s11,t6 = {mul, mulh, mulhsu, mulhu}
    ################################################################
    addi    t0, x0, 0
    lui     t1, 0x075BD         # 0x075BD000
    addi    t1, t1, -0x2EB      # -> 0x075BCD15
    mul     s9,  t0, t1         # exp 00000000
    mulh    s10, t0, t1         # exp 00000000
    mulhsu  s11, t0, t1         # exp 00000000
    mulhu   t6,  t0, t1         # exp 00000000

    ################################################################
    # Optional mixed-sign large constants: a=0x12345678, b=0x9ABCDEF0
    # (kept last; comment out if you want fewer regs in use)
    # Results are not stored if you’re tight on regs—uncomment to capture.
    ################################################################
    lui     t0, 0x12345         # 0x12345000
    addi    t0, t0, 0x678       # -> 0x12345678
    lui     t1, 0x9ABCE         # 0x9ABCE000
    addi    t1, t1, -0x110      # -> 0x9ABCDEF0
    mul     s1, t0, t1        # exp 242d2080 (lo)  — reuse a dest if desired
    mulh    s2, t0, t1        # exp f8cc93d6
    mulhsu  s3, t0, t1        # exp 0b00ea4e
    mulhu   s4, t0, t1        # exp 0b00ea4e

halt:
    slti x0, x0, -256
