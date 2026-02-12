    .align 4
    .section .text
    .globl _start
_start:
    # --- Simple JALR test: jump to jalr_target and skip the next instruction ---
    li x0,0xaaaa
    addi x10, x0, 0        # x10 = 0  (signature / scratch)
    lui x1,0xaaaaa
    addi x1,  x1, 0x014       # x1 = 16 = address of jalr_target (see layout below)

    jalr x0, x1, 0         # PC = x1 + 0 = 16  -> should jump to jalr_target

    addi x10, x0, 0x55     # THIS SHOULD BE SKIPPED if jalr works

jalr_target:               # at address 16 (0x10), if _start is at 0
    addi x10, x10, 1       # x10 should end up as 1 if jump was correct

halt:
    slti x0, x0, -256      # halt / illegal loop