#ifndef FJ_EISEL_LEMIRE_H
#define FJ_EISEL_LEMIRE_H

#include <stdint.h>

/* 128-bit unsigned integer represented as two 64-bit halves */
typedef struct { uint64_t hi; uint64_t lo; } fj_u128;

/* 64x64 -> 128 multiply using GCC __uint128_t */
static inline fj_u128 fj_mul64(uint64_t x, uint64_t y) {
    __uint128_t z = (__uint128_t)x * (__uint128_t)y;
    fj_u128 r;
    r.hi = (uint64_t)(z >> 64);
    r.lo = (uint64_t)z;
    return r;
}

static inline int fj_clz64(uint64_t u) {
    return u ? __builtin_clzl(u) : 64;
}

/* Powers of 10 table: fj_pow10_tab[exp10 + 348] = {lo64, hi64}
 * 128-bit mantissa approximations of 10^k for k in [-348, 348].
 * Included from fj_pow10.h (generated from sonic). */
#include "fj_pow10.h"

/* ============================================================
 * Eisel-Lemire fast float parsing
 * Reference: https://nigeltao.github.io/blog/2020/eisel-lemire.html
 *
 * Returns true on success, writes result to *val.
 * Returns false if fallback (strtod) is needed.
 * ============================================================ */
static inline int fj_eisel_lemire(uint64_t mant, int exp10, int sgn, double *val) {
    if (exp10 < -348 || exp10 > 347) return 0;

    /* Normalize mantissa to have leading 1 bit */
    int clz = fj_clz64(mant);
    mant <<= clz;

    /* Binary exponent: lg10/lg2 ≈ 217706/65536 */
    uint64_t ret_exp2 = ((uint64_t)((217706 * exp10) >> 16) + 64 + 1023) - (uint64_t)clz;

    /* First multiplication: mant × hi64(pow10) */
    fj_u128 x = fj_mul64(mant, fj_pow10_tab[exp10 + 348][1]);

    /* Check for ambiguous case in lower 9 bits */
    if ((x.hi & 0x1FF) == 0x1FF && (x.lo + mant) < mant) {
        /* Second multiplication: mant × lo64(pow10) for extra precision */
        fj_u128 y = fj_mul64(mant, fj_pow10_tab[exp10 + 348][0]);
        uint64_t merged_hi = x.hi;
        uint64_t merged_lo = x.lo + y.hi;
        if (merged_lo < x.lo) merged_hi++;

        /* Still ambiguous */
        if ((merged_hi & 0x1FF) == 0x1FF && (merged_lo + 1) == 0 && (y.lo + mant) < mant) {
            return 0;
        }
        x.hi = merged_hi;
        x.lo = merged_lo;
    }

    /* Extract 54 bits of mantissa */
    int msb = (int)(x.hi >> 63);
    uint64_t ret_man = x.hi >> (msb + 9);
    ret_exp2 -= 1 ^ msb;

    /* Half-way ambiguity check */
    if (x.lo == 0 && (x.hi & 0x1FF) == 0 && (ret_man & 3) == 1) {
        return 0;
    }

    /* Round to nearest even (53 bits) */
    ret_man += ret_man & 1;
    ret_man >>= 1;

    /* Rounding overflow */
    if ((ret_man >> 53) > 0) {
        ret_man >>= 1;
        ret_exp2 += 1;
    }

    /* Subnormal or overflow → fallback */
    if ((ret_exp2 - 1) >= (0x7FF - 1)) return 0;

    /* Assemble IEEE 754 double */
    uint64_t bits = (ret_exp2 << 52) | (ret_man & 0x000FFFFFFFFFFFFF);
    if (sgn < 0) bits |= 1ull << 63;
    *(uint64_t*)val = bits;
    return 1;
}

#endif /* FJ_EISEL_LEMIRE_H */
