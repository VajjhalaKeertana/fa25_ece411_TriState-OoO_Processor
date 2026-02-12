    .section .text
    .align  4
    .globl  _start

_start:
    # Start with BEQ tests
    jal   x0, test_beq

############################################################
# BEQ tests
############################################################
test_beq:
    # Taken BEQ: equal operands
    addi x2, x0, 5
    addi x3, x0, 5
    beq  x2, x3, 1f      # should be taken
    jal  x0, fail
1:
    # Not taken BEQ: unequal operands
    addi x3, x0, 6
    beq  x2, x3, fail    # should NOT be taken

    jal  x0, test_bne

############################################################
# BNE tests
############################################################
test_bne:
    # Taken BNE: unequal
    addi x2, x0, 5
    addi x3, x0, 6
    bne  x2, x3, 1f      # should be taken
    jal  x0, fail
1:
    # Not taken BNE: equal
    addi x3, x0, 5
    bne  x2, x3, fail    # should NOT be taken

    jal  x0, test_blt

############################################################
# BLT (signed) tests
############################################################
test_blt:
    # -1 < 1 (signed)
    addi x2, x0, -1      # 0xffffffff
    addi x3, x0, 1
    blt  x2, x3, 1f      # should be taken
    jal  x0, fail
1:
    # 1 < -1 ? (signed, should be false)
    blt  x3, x2, fail    # should NOT be taken

    # INT_MIN < INT_MAX (signed)
    lui  x2, 0x80000     # x2 = 0x80000000 (INT_MIN)
    lui  x3, 0x80000     # x3 = 0x80000000
    addi x3, x3, -1      # x3 = 0x7fffffff (INT_MAX)

    blt  x2, x3, 2f      # INT_MIN < INT_MAX => true
    jal  x0, fail
2:
    blt  x3, x2, fail    # INT_MAX < INT_MIN => false

    jal  x0, test_bge

############################################################
# BGE (signed) tests
############################################################
test_bge:
    # -1 >= 1 ?  (false)
    addi x2, x0, -1
    addi x3, x0, 1
    bge  x2, x3, fail    # should NOT be taken

    # 1 >= -1 ?  (true)
    bge  x3, x2, 1f      # should be taken
    jal  x0, fail
1:
    # -1 >= -1 ?  (true, equality case)
    addi x3, x0, -1
    bge  x2, x3, 2f
    jal  x0, fail
2:
    jal  x0, test_bltu

############################################################
# BLTU (unsigned) tests
############################################################
test_bltu:
    # 0 < 1 (unsigned)
    addi x2, x0, 0
    addi x3, x0, 1
    bltu x2, x3, 1f      # 0 < 1 => true
    jal  x0, fail
1:
    # 1 < 0 (unsigned) ? (false)
    bltu x3, x2, fail

    # 0xffffffff (unsigned max) vs 0
    addi x2, x0, -1      # 0xffffffff
    addi x3, x0, 0       # 0x00000000

    bltu x2, x3, fail    # 0xffffffff < 0 ? false
    bltu x3, x2, 2f      # 0 < 0xffffffff ? true
    jal  x0, fail
2:
    jal  x0, test_bgeu

############################################################
# BGEU (unsigned) tests
############################################################
test_bgeu:
    # 0 >= 1 (unsigned)?  false
    addi x2, x0, 0
    addi x3, x0, 1
    bgeu x2, x3, fail

    # 1 >= 0 (unsigned)?  true
    bgeu x3, x2, 1f
    jal  x0, fail
1:
    # 0xffffffff >= 0 ?  true
    addi x2, x0, -1      # 0xffffffff
    addi x3, x0, 0

    bgeu x2, x3, 2f      # should be taken
    jal  x0, fail
2:
    # 0 >= 0xffffffff ? false
    bgeu x3, x2, fail

    jal  x0, test_backward_branch

############################################################
# Backward branch (negative offset) test
############################################################
test_backward_branch:
    # Simple countdown loop using backward BNE
    addi x4, x0, 5       # loop counter = 5
1:
    addi x4, x4, -1
    bne  x4, x0, 1b      # branch backward until x4 == 0

    # If we exit the loop, backward branch works
    jal  x0, test_far_forward_branch

############################################################
# Forward branch with sizeable offset
############################################################
test_far_forward_branch:
    addi x5, x0, 1
    beq  x5, x5, 1f      # always taken, jumping over NOPs
    jal  x0, fail

    # Forward-skipped block (just NOPs)
    addi x0, x0, 0       # NOP
    addi x0, x0, 0       # NOP
    addi x0, x0, 0       # NOP
    addi x0, x0, 0       # NOP
    addi x0, x0, 0       # NOP
    addi x0, x0, 0       # NOP
    addi x0, x0, 0       # NOP
    addi x0, x0, 0       # NOP

    
1:
    # If we’re here, forward branch target is correct
    jal  x0, test_jal

############################################################
# JAL tests (forward and backward)
############################################################
test_jal:
    # Forward JAL: should jump to jal_mid
    jal  x1, jal_mid     # link in x1 (not strictly checked here)
    jal  x0, fail        # executed only if JAL not taken

jal_after:
    # We get here via backward JAL from jal_mid
    jal  x0, test_jalr

jal_mid:
    # Backward JAL to jal_after
    jal  x0, jal_after

############################################################
# JALR tests (return via RA, and odd-LSB target masking)
############################################################
test_jalr:
    # Simple call/return using JAL + JALR
    jal  x1, jalr_func
    jal  x0, fail          # if JAL not taken

after_jalr_simple:
    # Now test JALR with odd LSB in target address
    jal  x1, jalr_odd_target
    jal  x0, fail          # if this executes, JAL failed

after_jalr_odd:
    # If we reach here, JALR masking of LSB worked
    jal  x0, pass

# Subroutine: JALR uses RA to return
jalr_func:
    jalr x0, 0(x1)         # return to after_jalr_simple
    jal  x0, fail          # if we fall through, JALR failed

# Subroutine: JALR with odd LSB (must be masked)
jalr_odd_target:
    addi x1, x1, 1         # make RA odd
    jalr x0, 0(x1)         # target = (x1) & ~1, should still be after_jalr_odd
    jal  x0, fail          # if we fall through, JALR failed

############################################################
# PASS / FAIL / HALT
############################################################
pass:
    # All tests passed: go to HALT pattern
    jal  x0, halt

fail:
    # Failure: spin forever so testbench can detect
    jal  x0, fail

halt:
    # Standard HALT pattern
    slti x0, x0, -256