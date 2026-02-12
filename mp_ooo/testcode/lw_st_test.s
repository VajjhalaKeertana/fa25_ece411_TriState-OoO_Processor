.section .text
.globl _start
_start:
    # Base pointer
    lui   x1, 0xaaaaa          # x1 = 0xAAAAA000

    # Initialize operands
    addi  x2, x0, 6            # x2 = 6
    addi  x3, x0, 7            # x3 = 7
    mul   x4, x2, x3           # x4 = 42   (mul depends on x2,x3)
    sw    x4, 0(x1)            # MEM[0xAAAAA000] = 42

    # Dependent load
    lw    x5, 0(x1)            # x5 = 42 (depends on sw)

    # Divide by a value derived from the loaded data
    addi  x6, x5, -40          # x6 = 2
    div   x7, x5, x6           # x7 = 21  (depends on load result)

    # Store division result (dependency chain)
    sw    x7, 4(x1)            # MEM[0xAAAAA004] = 21

    # Load it back for branch condition
    lw    x8, 4(x1)            # x8 = 21 (depends on prior store)

    # Compute branch target dynamically
    addi  x9, x8, -20          # x9 = 1
    add   x10, x1, x9          # x10 = 0xAAAAA001 (target address region)

    # Branch condition depends on divided result
    bne   x8, x7, skip         # Not taken (equal)
    beq   x8, x7, branch_taken # Taken path (control dependency)

skip:
    addi  x11, x0, 99          # (won’t execute)
    j     end

branch_taken:
    mul   x12, x7, x6          # x12 = 21*2 = 42 (depends on div)
    div   x13, x12, x3         # x13 = 6 (depends on mul)
    sw    x13, 8(x1)           # MEM[0xAAAAA008] = 6 (depends on div result)
    lw    x14, 8(x1)           # x14 = 6 (depends on store)

    addi  x15, x14, 10         # x15 = 16
    sw    x15, 12(x1)          # MEM[0xAAAAA00C] = 16

end:
    slti  x1, x1, -256         # magic end
