#ifndef FJ_ITOA_H
#define FJ_ITOA_H

#include <stdint.h>
#include <string.h>

/* Digits[200] lookup: "00".."99" for 2-digit pair conversion */
static const char fj_digits[200] = {
    '0','0','0','1','0','2','0','3','0','4','0','5','0','6','0','7','0','8','0','9',
    '1','0','1','1','1','2','1','3','1','4','1','5','1','6','1','7','1','8','1','9',
    '2','0','2','1','2','2','2','3','2','4','2','5','2','6','2','7','2','8','2','9',
    '3','0','3','1','3','2','3','3','3','4','3','5','3','6','3','7','3','8','3','9',
    '4','0','4','1','4','2','4','3','4','4','4','5','4','6','4','7','4','8','4','9',
    '5','0','5','1','5','2','5','3','5','4','5','5','5','6','5','7','5','8','5','9',
    '6','0','6','1','6','2','6','3','6','4','6','5','6','6','6','7','6','8','6','9',
    '7','0','7','1','7','2','7','3','7','4','7','5','7','6','7','7','7','8','7','9',
    '8','0','8','1','8','2','8','3','8','4','8','5','8','6','8','7','8','8','8','9',
    '9','0','9','1','9','2','9','3','9','4','9','5','9','6','9','7','9','8','9','9',
};

/* ============================================================
 * SSE2 SIMD integer-to-ASCII — itoa8 converts 8 digits
 * in parallel using multiply+pack operations.
 * From sonic native/fastint.h: itoa8_sse2
 * ============================================================ */
#ifdef __SSE2__
#include <emmintrin.h>

/* Precomputed constants for itoa8_sse2 */
static const uint16_t fj_vec8x10[8] __attribute__((aligned(16))) = {10,10,10,10,10,10,10,10};
static const uint32_t fj_vec4x10k[4] __attribute__((aligned(16))) = {10000,10000,10000,10000};
static const uint32_t fj_vec4xdiv10k[4] __attribute__((aligned(16))) = {0xd1b71759,0xd1b71759,0xd1b71759,0xd1b71759};
static const uint16_t fj_vec_div_powers[8] __attribute__((aligned(16))) = {0x20c5,0x147b,0x3334,0x8000,0x20c5,0x147b,0x3334,0x8000};
static const uint16_t fj_vec_shift_powers[8] __attribute__((aligned(16))) = {0x0080,0x0800,0x2000,0x8000,0x0080,0x0800,0x2000,0x8000};
static const char fj_vec16xa0[16] __attribute__((aligned(16))) = {'0','0','0','0','0','0','0','0','0','0','0','0','0','0','0','0'};

/* Shuffle masks for removing leading zeros: 9 masks of 16 bytes each */
static const uint8_t fj_shift_shuffles[144] __attribute__((aligned(16))) = {
    0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,
    0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0xff,
    0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0xff,0xff,
    0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0xff,0xff,0xff,
    0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0xff,0xff,0xff,0xff,
    0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0xff,0xff,0xff,0xff,0xff,
    0x06,0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0xff,0xff,0xff,0xff,0xff,0xff,
    0x07,0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0xff,0xff,0xff,0xff,0xff,0xff,0xff,
    0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,
};

/* Convert an 8-digit number to 8 ASCII digits in parallel using SSE2.
 * Input: v = number in range [0, 99999999]
 * Output: __m128i of 8 uint16 values, each being the digit character minus '0' */
static inline __m128i fj_itoa8(uint32_t v) {
    __m128i v00 = _mm_cvtsi32_si128((int)v);
    /* Divide by 10000 using multiply-high: v / 10000 ≈ (v * 0xd1b71759) >> 45 */
    __m128i v01 = _mm_mul_epu32(v00, _mm_load_si128((const __m128i*)fj_vec4xdiv10k));
    __m128i v02 = _mm_srli_epi64(v01, 45);
    /* Remainder: v - (v/10000)*10000 = lower 4 digits */
    __m128i v03 = _mm_mul_epu32(v02, _mm_load_si128((const __m128i*)fj_vec4x10k));
    __m128i v04 = _mm_sub_epi32(v00, v03);
    /* Interleave high4 and low4 as pairs: [h0,l0,h1,l1,h2,l2,h3,l3] */
    __m128i v05 = _mm_unpacklo_epi16(v02, v04);
    /* Multiply by 4 to get index*2 for Digits lookup (but we use mulhi instead) */
    __m128i v06 = _mm_slli_epi64(v05, 2);
    /* Duplicate each pair to get [h0,h0,l0,l0,h1,h1,l1,l1] */
    __m128i v07 = _mm_unpacklo_epi16(v06, v06);
    __m128i v08 = _mm_unpacklo_epi32(v07, v07);
    /* Parallel modulo-by-10 using mulhi trick: digit = (x * recip) >> shift */
    __m128i v09 = _mm_mulhi_epu16(v08, _mm_load_si128((const __m128i*)fj_vec_div_powers));
    __m128i v10 = _mm_mulhi_epu16(v09, _mm_load_si128((const __m128i*)fj_vec_shift_powers));
    /* Recover digits: result * 10, then subtract from x */
    __m128i v11 = _mm_mullo_epi16(v10, _mm_load_si128((const __m128i*)fj_vec8x10));
    /* Move to high byte of each uint16 */
    __m128i v12 = _mm_slli_epi64(v11, 16);
    __m128i v13 = _mm_sub_epi16(v10, v12);
    return v13;
}

/* Small: 1-4 digits using Digits lookup */
static inline int fj_u32toa_small(char *out, uint32_t val) {
    int n = 0;
    uint32_t d1 = (val / 100);
    uint32_t d2 = (val % 100);
    if (val >= 1000) out[n++] = fj_digits[d1 * 2];
    if (val >= 100)  out[n++] = fj_digits[d1 * 2 + 1];
    if (val >= 10)   out[n++] = fj_digits[d2 * 2];
    out[n++] = fj_digits[d2 * 2 + 1];
    return n;
}

/* Medium: 5-8 digits using Digits lookup */
static inline int fj_u32toa_medium(char *out, uint32_t val) {
    int n = 0;
    uint32_t b = val / 10000;
    uint32_t c = val % 10000;
    uint32_t d1 = (b / 100);
    uint32_t d2 = (b % 100);
    uint32_t d3 = (c / 100);
    uint32_t d4 = (c % 100);
    if (val >= 10000000) out[n++] = fj_digits[d1 * 2];
    if (val >= 1000000)  out[n++] = fj_digits[d1 * 2 + 1];
    if (val >= 100000)   out[n++] = fj_digits[d2 * 2];
    out[n++] = fj_digits[d2 * 2 + 1];
    out[n++] = fj_digits[d3 * 2];
    out[n++] = fj_digits[d3 * 2 + 1];
    out[n++] = fj_digits[d4 * 2];
    out[n++] = fj_digits[d4 * 2 + 1];
    return n;
}

/* Large: 9-16 digits using itoa8_sse2 for each 8-digit half */
static inline int fj_u64toa_large(char *out, uint64_t val) {
    uint32_t a = (uint32_t)(val / 100000000);
    uint32_t b = (uint32_t)(val % 100000000);

    /* Convert each half to 8 digit-pairs */
    __m128i v0 = fj_itoa8(a);
    __m128i v1 = fj_itoa8(b);

    /* Pack 16-bit to 8-bit and add '0' */
    __m128i v2 = _mm_packus_epi16(v0, v1);
    __m128i v3 = _mm_add_epi8(v2, _mm_load_si128((const __m128i*)fj_vec16xa0));

    /* Count leading zeros via comparison mask */
    __m128i v4 = _mm_cmpeq_epi8(v3, _mm_load_si128((const __m128i*)fj_vec16xa0));
    uint32_t bm = (uint32_t)_mm_movemask_epi8(v4);
    uint32_t nd = (uint32_t)__builtin_ctz(~bm | 0x8000);

    /* Shuffle to remove leading zeros */
    __m128i p = _mm_loadu_si128((const __m128i*)&fj_shift_shuffles[nd * 16]);
    __m128i r = _mm_shuffle_epi8(v3, p);

    _mm_storeu_si128((__m128i*)out, r);
    return (int)(16 - nd);
}

/* Extra-large: 17-20 digits using Digits for top + itoa8 for rest */
static inline int fj_u64toa_xlarge(char *out, uint64_t val) {
    int n = 0;
    uint64_t b = val % 10000000000000000ULL;
    uint32_t a = (uint32_t)(val / 10000000000000000ULL);

    if (a < 10) {
        out[n++] = '0' + (char)a;
    } else if (a < 100) {
        out[n++] = fj_digits[a * 2];
        out[n++] = fj_digits[a * 2 + 1];
    } else if (a < 1000) {
        out[n++] = '0' + (char)(a / 100);
        out[n++] = fj_digits[(a % 100) * 2];
        out[n++] = fj_digits[(a % 100) * 2 + 1];
    } else {
        out[n++] = fj_digits[(a / 100) * 2];
        out[n++] = fj_digits[(a / 100) * 2 + 1];
        out[n++] = fj_digits[(a % 100) * 2];
        out[n++] = fj_digits[(a % 100) * 2 + 1];
    }

    /* Remaining 16 digits via itoa8 */
    __m128i v0 = fj_itoa8((uint32_t)(b / 100000000));
    __m128i v1 = fj_itoa8((uint32_t)(b % 100000000));
    __m128i v2 = _mm_packus_epi16(v0, v1);
    __m128i v3 = _mm_add_epi8(v2, _mm_load_si128((const __m128i*)fj_vec16xa0));
    _mm_storeu_si128((__m128i*)&out[n], v3);
    return n + 16;
}

/* Main entry point: unsigned 64-bit to ASCII */
static inline int fj_u64toa(char *out, uint64_t val) {
    if (val < 100000000) {
        if (val < 10000) return fj_u32toa_small(out, (uint32_t)val);
        return fj_u32toa_medium(out, (uint32_t)val);
    }
    if (val < 10000000000000000ULL) return fj_u64toa_large(out, val);
    return fj_u64toa_xlarge(out, val);
}

/* Signed 64-bit to ASCII */
static inline int fj_i64toa(char *out, int64_t val) {
    if (val >= 0) return fj_u64toa(out, (uint64_t)val);
    *out = '-';
    return fj_u64toa(out + 1, (uint64_t)(-(val + 1) + 1)) + 1;
}

#else /* !__SSE2__ */
/* Scalar fallback: uses Digits[200] lookup for 2-digit pairs */

static inline int fj_u32toa_small(char *out, uint32_t val) {
    int n = 0;
    uint32_t d1 = (val / 100);
    uint32_t d2 = (val % 100);
    if (val >= 1000) out[n++] = fj_digits[d1 * 2];
    if (val >= 100)  out[n++] = fj_digits[d1 * 2 + 1];
    if (val >= 10)   out[n++] = fj_digits[d2 * 2];
    out[n++] = fj_digits[d2 * 2 + 1];
    return n;
}

static inline int fj_u32toa_medium(char *out, uint32_t val) {
    int n = 0;
    uint32_t b = val / 10000;
    uint32_t c = val % 10000;
    uint32_t d1 = (b / 100);
    uint32_t d2 = (b % 100);
    uint32_t d3 = (c / 100);
    uint32_t d4 = (c % 100);
    if (val >= 10000000) out[n++] = fj_digits[d1 * 2];
    if (val >= 1000000)  out[n++] = fj_digits[d1 * 2 + 1];
    if (val >= 100000)   out[n++] = fj_digits[d2 * 2];
    out[n++] = fj_digits[d2 * 2 + 1];
    out[n++] = fj_digits[d3 * 2];
    out[n++] = fj_digits[d3 * 2 + 1];
    out[n++] = fj_digits[d4 * 2];
    out[n++] = fj_digits[d4 * 2 + 1];
    return n;
}

static inline int fj_u64toa(char *out, uint64_t val) {
    if (val < 100000000) {
        if (val < 10000) return fj_u32toa_small(out, (uint32_t)val);
        return fj_u32toa_medium(out, (uint32_t)val);
    }
    /* For large numbers, use Digits lookup in pairs */
    char tmp[20];
    int pos = 0;
    while (val >= 100) {
        uint32_t idx = (uint32_t)(val % 100) * 2;
        tmp[pos] = fj_digits[idx + 1];
        tmp[pos + 1] = fj_digits[idx];
        val /= 100;
        pos += 2;
    }
    if (val >= 10) {
        uint32_t idx = (uint32_t)val * 2;
        tmp[pos] = fj_digits[idx + 1];
        tmp[pos + 1] = fj_digits[idx];
        pos += 2;
    } else {
        tmp[pos] = '0' + (char)val;
        pos++;
    }
    for (int j = pos - 1; j >= 0; j--) {
        *out++ = tmp[j];
    }
    return pos;
}

static inline int fj_i64toa(char *out, int64_t val) {
    if (val >= 0) return fj_u64toa(out, (uint64_t)val);
    *out = '-';
    return fj_u64toa(out + 1, (uint64_t)(-(val + 1) + 1)) + 1;
}

#endif /* __SSE2__ */

/* V-compatible wrappers: write to uint8_t buffer */
static inline int fast_int_to_buf(uint8_t* buf, int start, int64_t val) {
    char tmp[21];
    int n = fj_i64toa(tmp, val);
    memcpy(buf + start, tmp, n);
    return n;
}

static inline int fast_uint64_to_buf(uint8_t* buf, int start, uint64_t val) {
    char tmp[20];
    int n = fj_u64toa(tmp, val);
    memcpy(buf + start, tmp, n);
    return n;
}

#endif /* FJ_ITOA_H */