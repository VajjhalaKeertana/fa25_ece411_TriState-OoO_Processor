.align 4
.section .text
.globl _start
_start:

###############################################
# Register initialization
###############################################
lui  x1, 0x00000
addi x1, x1, 0x100     # base address for loads (safe)

li   x2, 4
li   x3, 8
li   x4, 12
li   x5, 16
li   x6, 20
li   x7, 24
li   x8, 28

nop
nop
nop

###########################################################
# 1. RAW CHAIN — deep dependency chain with mul latency
###########################################################
lw   x9,  0(x1)
add  x10, x9,  x2
mul  x11, x10, x3
xor  x12, x11, x4
add  x13, x12, x5
mul  x14, x13, x6
and  x15, x14, x7

###########################################################
# 2. Independent instructions (should run OOO immediately)
###########################################################
add  x16, x2, x3
xor  x17, x4, x5
mul  x18, x6, x7
or   x19, x3, x5
and  x20, x4, x6
sll  x21, x2, x3
srl  x22, x7, x1

###########################################################
# 3. WAW STRESS — x23 hammered with many writes
###########################################################
add  x23, x2, x3
sub  x23, x4, x5
mul  x23, x6, x7    # long latency WAW
xor  x23, x3, x2
and  x23, x7, x6
or   x23, x1, x2

###########################################################
# 4. WAR STRESS — younger writes overwrite needed values
###########################################################
add  x24, x2, x3
xor  x2,  x4,  x5      # younger write (WAR)
mul  x25, x24, x2      # uses NEW x2
sub  x2,  x1,  x3      # overwrite again
add  x26, x2,  x24     # uses NEWEST x2

###########################################################
# 5. LOAD-USE HAZARDS
###########################################################
lw   x27, 4(x1)
mul  x28, x27, x9
add  x29, x28, x10
xor  x30, x29, x11

###########################################################
# 6. Parallel loads — load queue + OOO pressure
###########################################################
lw   x31,  8(x1)
lw   x3,  12(x1)       # reusing x3 intentionally = hazard pressure
lw   x4,  16(x1)
lw   x5,  20(x1)

add  x6, x31, x3
mul  x7, x4,  x5
xor  x8, x7,  x6

###########################################################
# 7. RAW + MUL + LOAD mixed chain
###########################################################
mul  x9,  x2,  x3
lw   x10, 0(x1)
add  x11, x9,  x10
mul  x12, x11, x5
xor  x13, x12, x6
sub  x14, x13, x7

###########################################################
# HALT
###########################################################
slti x0, x0, -256
