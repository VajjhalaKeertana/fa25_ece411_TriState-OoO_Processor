#include <stdint.h>

#define N32 256u  // 256 * 4B = 1 KB
#define NITER 16u

// Main 32-bit backing store (we'll alias as 16- and 8-bit).
volatile uint32_t buf32[N32] __attribute__((aligned(64)));

// A sink so the compiler can't optimize everything away.
volatile uint32_t result_sink = 0;

static uint32_t mix32(uint32_t x) {
    // Cheap mixing to create "random-ish" indices; forces MUL.
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return x;
}

int main(void) {
    uint32_t checksum = 0;
    uint32_t i, it;

    // ----------------------------------------------------------------
    // 1. Initialize buf32 with a pattern (SW + LW)
    // ----------------------------------------------------------------
    for (i = 0; i < N32; ++i) {
        // SW
        buf32[i] = 0xDEAD0000u ^ (i * 0x01010101u);
    }

    for (i = 0; i < N32; ++i) {
        // LW
        uint32_t v = buf32[i];
        checksum ^= v;
    }

    // Aliases to exercise SB/SH/LB/LBU/LH/LHU
    volatile uint8_t  *p8  = (volatile uint8_t  *)buf32;
    volatile uint16_t *p16 = (volatile uint16_t *)buf32;

    // ----------------------------------------------------------------
    // 2. Byte-sized accesses (SB, LB, LBU) mixed with LW
    // ----------------------------------------------------------------
    for (it = 0; it < NITER; ++it) {
        for (i = 0; i < N32 * 4u; i += 3u) {
            uint32_t idx32 = i >> 2;     // same cache line / word
            uint32_t lane  = i & 3u;

            // Store a byte
            // -> SB
            p8[i] = (uint8_t)(i + it);

            // Signed load
            // -> LB
            int8_t s8 = (int8_t)p8[i];

            // Unsigned load
            // -> LBU
            uint8_t u8 = p8[i];

            // Load full word after byte writes
            // -> LW (after SB to same word)
            uint32_t w = buf32[idx32];

            // Use some MUL/DIV with loaded data
            // -> MUL, DIV, REM (signed)
            int32_t sv   = (int32_t)w;
            int32_t prod = sv * (int32_t)(lane + 3);
            int32_t q    = prod / 7;
            int32_t r    = prod % 7;

            checksum ^= (uint32_t)(s8 + u8) ^ (uint32_t)q ^ (uint32_t)r;
        }
    }

    // ----------------------------------------------------------------
    // 3. Halfword-sized accesses (SH, LH, LHU) mixed with LW
    // ----------------------------------------------------------------
    for (it = 0; it < NITER; ++it) {
        for (i = 0; i < N32 * 2u; i += 2u) {
            uint32_t idx32 = i >> 1;   // each 16-bit half maps into buf32

            // Store halfword
            // -> SH
            p16[i] = (uint16_t)(0x1234u + (i ^ it));

            // Signed load
            // -> LH
            int16_t s16 = (int16_t)p16[i];

            // Unsigned load
            // -> LHU
            uint16_t u16 = p16[i];

            // Load full word
            // -> LW (after SH to same word)
            uint32_t w = buf32[idx32 >> 1];

            // Unsigned MUL/DIV/REM
            // -> MUL, DIVU, REMU
            uint32_t prod = w * (uint32_t)(it + 5u);
            uint32_t uq   = prod / 9u;
            uint32_t ur   = prod % 9u;

            checksum ^= (uint32_t)s16;
            checksum ^= (uint32_t)u16 ^ uq ^ ur;
        }
    }

    // ----------------------------------------------------------------
    // 4. Store→Load hazards with words (SW, LW) + MULH/MULHU
    // ----------------------------------------------------------------
    for (it = 0; it < NITER; ++it) {
        for (i = 0; i < N32; ++i) {
            uint32_t val = mix32(i + it * 17u);

            // Store a word
            // -> SW
            buf32[i] = val;

            // Immediately load the same word
            // -> LW with store-load forwarding requirement
            uint32_t w = buf32[i];

            // 64-bit product to trigger MULH/MULHU
            int32_t  a   = (int32_t)w;
            int32_t  b   = (int32_t)(0x1234567u + it);
            int64_t  pss = (int64_t)a * (int64_t)b;              // signed * signed
            uint32_t high_ss = (uint32_t)(pss >> 32);            // -> MULH

            uint32_t ua = (uint32_t)w;
            uint32_t ub = (uint32_t)(0x9ABCDEFu + it);
            uint64_t puu = (uint64_t)ua * (uint64_t)ub;          // unsigned * unsigned
            uint32_t high_uu = (uint32_t)(puu >> 32);            // -> MULHU

            checksum ^= w ^ high_ss ^ high_uu;
        }
    }

    // ----------------------------------------------------------------
    // 5. Pseudo-random indexed accesses with mixed DIV/REM
    // ----------------------------------------------------------------
    for (it = 0; it < NITER * 2u; ++it) {
        uint32_t acc = checksum ^ (it * 0x13579BDFu);

        for (i = 0; i < N32; ++i) {
            uint32_t idx = mix32(i + acc) % N32;  // -> DIVU/REMU by const N32?

            // Load
            // -> LW (random-ish index)
            uint32_t v = buf32[idx];

            // Some signed/unsigned div/rem by non-power-of-two constants
            int32_t  sv  = (int32_t)v;
            int32_t  dq  = sv / 13;
            int32_t  dr  = sv % 13;
            uint32_t uv  = v ^ 0xCAFEBABEu;
            uint32_t duq = uv / 11u;
            uint32_t dur = uv % 11u;

            // Store result back to another location
            // -> SW
            uint32_t dst = (idx * 7u + it * 3u) & (N32 - 1u);
            buf32[dst] = v ^ (uint32_t)dq ^ (uint32_t)dr ^ duq ^ dur;

            checksum ^= buf32[dst];
        }
    }

    // ----------------------------------------------------------------
    // Final reduce to make sure the compiler keeps everything
    // ----------------------------------------------------------------
    result_sink = checksum;
    return (int)checksum;
}