dependency_test.s:
.align 4
.section .text
.globl _start
    # This program consists of small snippets
    # containing RAW, WAW, and WAR hazards

    # This test is NOT exhaustive
_start:

# --- Case 1: 0 / 0 ---
# DIV  = 0xFFFFFFFF   REM  = 0x00000000
# DIVU = 0xFFFFFFFF   REMU = 0x00000000
    li x5, 0
    li x6, 0
    div   x10, x5, x6
    rem   x11, x5, x6
    divu  x12, x5, x6
    remu  x13, x5, x6

# --- Case 2: 1 / 0 ---
# DIV  = 0xFFFFFFFF   REM  = 0x00000001
# DIVU = 0xFFFFFFFF   REMU = 0x00000001
    li x5, 1
    li x6, 0
    div   x10, x5, x6
    rem   x11, x5, x6
    divu  x12, x5, x6
    remu  x13, x5, x6

# --- Case 3: -1 / 0 ---
# DIV  = 0xFFFFFFFF   REM  = 0xFFFFFFFF
# DIVU = 0xFFFFFFFF   REMU = 0xFFFFFFFF
    li x5, -1
    li x6, 0
    div   x10, x5, x6
    rem   x11, x5, x6
    divu  x12, x5, x6
    remu  x13, x5, x6

# --- Case 4: INT_MIN / -1 ---
# DIV  = 0x80000000   REM  = 0x00000000
# DIVU = 0x00000000   REMU = 0x80000000   (because 0x80000000 < 0xFFFFFFFF)
    li x5, 0x80000000
    li x6, -1
    div   x10, x5, x6
    rem   x11, x5, x6
    divu  x12, x5, x6
    remu  x13, x5, x6

# --- Case 5: INT_MIN / 1 ---
# DIV  = 0x80000000   REM  = 0x00000000
# DIVU = 0x80000000   REMU = 0x00000000
    li x5, 0x80000000
    li x6, 1
    div   x10, x5, x6
    rem   x11, x5, x6
    divu  x12, x5, x6
    remu  x13, x5, x6

# --- Case 6: -1 / INT_MIN ---
# DIV  = 0x00000000   REM  = 0xFFFFFFFF
# DIVU = 0x00000001   REMU = 0x7FFFFFFF
    li x5, -1
    li x6, 0x80000000
    div   x10, x5, x6
    rem   x11, x5, x6
    divu  x12, x5, x6
    remu  x13, x5, x6

# --- Case 7: 123 / 7 ---
# DIV  = 0x00000011   REM  = 0x00000004
# DIVU = 0x00000011   REMU = 0x00000004
    li x5, 123
    li x6, 7
    div   x10, x5, x6
    rem   x11, x5, x6
    divu  x12, x5, x6
    remu  x13, x5, x6

# --- Case 8: -123 / 7 ---
# DIV  = 0xFFFFFFEF   REM  = 0xFFFFFFFC
# DIVU = 0x24924913   REMU = 0x00000000   (since 0xFFFFFF85 / 7 is exact)
    li x5, -123
    li x6, 7
    div   x10, x5, x6
    rem   x11, x5, x6
    divu  x12, x5, x6
    remu  x13, x5, x6

# --- Case 9: 123 / -7 ---
# DIV  = 0xFFFFFFEF   REM  = 0x00000004
# DIVU = 0x00000000   REMU = 0x0000007B   (123 < 0xFFFFFFF9)
    li x5, 123
    li x6, -7
    div   x10, x5, x6
    rem   x11, x5, x6
    divu  x12, x5, x6
    remu  x13, x5, x6

# --- Case 10: -123 / -7 ---
# DIV  = 0x00000011   REM  = 0xFFFFFFFC
# DIVU = 0x00000000   REMU = 0xFFFFFF85   (dividend < divisor in unsigned)
    li x5, -123
    li x6, -7
    div   x10, x5, x6
    rem   x11, x5, x6
    divu  x12, x5, x6
    remu  x13, x5, x6

# --- Case 11: 5 / 10 ---
# DIV  = 0x00000000   REM  = 0x00000005
# DIVU = 0x00000000   REMU = 0x00000005
    li x5, 5
    li x6, 10
    div   x10, x5, x6
    rem   x11, x5, x6
    divu  x12, x5, x6
    remu  x13, x5, x6

# --- Case 12: -5 / 10 ---
# DIV  = 0x00000000   REM  = 0xFFFFFFFB
# DIVU = 0x19999999   REMU = 0x00000001   (0xFFFFFFFB / 10)
    li x5, -5
    li x6, 10
    div   x10, x5, x6
    rem   x11, x5, x6
    divu  x12, x5, x6
    remu  x13, x5, x6


halt:
    slti x0, x0, -256
