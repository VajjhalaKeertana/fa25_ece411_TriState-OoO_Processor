dependency_test.s:
.align 4
.section .text
.globl _start
    # This program consists of small snippets
    # containing RAW, WAW, and WAR hazards

    # This test is NOT exhaustive
_start:

# initialize
li x1,  1
auipc x2, 0x200
li x3, 30
add x2,x1,x2
addi x3,x2,1
addi x5,x0,4
addi x3,x2,2
add x4,x0,x0

halt:
    slti x0, x0, -256
