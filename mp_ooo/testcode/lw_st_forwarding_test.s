    .section .text
    .globl _start
_start:

    lui   x1, 0xAAAAA        # 1  x1 = 0xAAAAA000  (base address)
    addi  x2, x0, 5          # 2  x2 = 5
    addi  x3, x0, 7          # 3  x3 = 7

    ###############################################################
    # (A) STORE → LOAD  (Forwarding must occur)
    ###############################################################
    #sw    x2, 0(x1)          # 4  STORE  0xAAAAA000 = 5
    #lw    x4, 0(x1)          # 5  LOAD   x4 = 5  (forward, NOT from memory)

    ###############################################################
    # (B) LOAD different address → No forwarding
    ###############################################################
    auipc x1,0x4
    lw    x2, 4(x1)          # 6  LOAD   x5 = Mem[0xAAAAA004] (unknown/stale)
                             #     Should NOT forward (no prior store)

    ###############################################################
    # (C) STORE → STORE → LOAD  (Forward newest store)
    ###############################################################
    sh    x2, 8(x1)          # 7  STORE  0xAAAAA008 = 5
    sh    x3, 8(x1)          # 8  STORE  0xAAAAA008 = 7   (WAW overwrite)
    lw    x6, 8(x1)          # 9  LOAD   x6 = 7 (forward x3’s store)

    # End simulation
    slti x0, x0, -256 # this is the magic instruction to end the simulation
