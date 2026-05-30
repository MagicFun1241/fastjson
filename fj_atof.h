#ifndef FJ_ATOF_H
#define FJ_ATOF_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "fj_eisel_lemire.h"

/* Powers of 10 for the exact fast path */
static const double fj_p10[23] = {
    1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7,
    1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15,
    1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22,
};

/* ============================================================
 * Exact fast path: mantissa fits in 52 bits, small exponent
 * Handles the majority of real-world float values.
 * ============================================================ */
static inline int fj_atof_exact(uint64_t man, int exp10, int sgn, double *val) {
    *val = (double)man;
    if (man >> 52 != 0) return 0;

    /* Apply sign via bit manipulation */
    if (sgn < 0) *(uint64_t*)val |= (1ull << 63);

    if (exp10 == 0 || man == 0) return 1;
    if (exp10 > 0 && exp10 <= 22) {
        *val *= fj_p10[exp10];
        /* Check we didn't lose precision */
        if (*val > 1e15 || *val < -1e15) return 0;
        return 1;
    }
    if (exp10 < 0 && exp10 >= -22) {
        *val /= fj_p10[-exp10];
        return 1;
    }
    return 0;
}

/* ============================================================
 * Fast float parser: parse mantissa+exponent, then convert
 * Chain: exact → Eisel-Lemire → strtod fallback
 * ============================================================ */
static inline double fj_parse_f64(const uint8_t* buf, int len, int* consumed) {
    int i = 0;
    int sgn = 1;

    /* Sign */
    if (i < len && buf[i] == '-') { sgn = -1; i++; }
    else if (i < len && buf[i] == '+') { i++; }

    /* Integer part → mantissa */
    uint64_t man = 0;
    int man_nd = 0;
    int exp10 = 0;
    int trunc = 0;

    while (i < len && buf[i] >= '0' && buf[i] <= '9') {
        if (man_nd < 19) {
            man = man * 10 + (buf[i] - '0');
            man_nd++;
        } else {
            exp10++;
            trunc = 1;
        }
        i++;
    }

    /* Decimal point */
    if (i < len && buf[i] == '.') {
        i++;
        /* Skip leading zeros after decimal point */
        if (man == 0 && man_nd == 0) {
            while (i < len && buf[i] == '0') {
                exp10--;
                i++;
            }
        }
        while (i < len && buf[i] >= '0' && buf[i] <= '9') {
            if (man_nd < 19) {
                man = man * 10 + (buf[i] - '0');
                man_nd++;
                exp10--;
            } else if (buf[i] != '0') {
                trunc = 1;
            }
            i++;
        }
    }

    /* Exponent */
    if (i < len && (buf[i] == 'e' || buf[i] == 'E')) {
        i++;
        int esgn = 1;
        if (i < len && buf[i] == '+') { i++; }
        else if (i < len && buf[i] == '-') { esgn = -1; i++; }
        int e = 0;
        while (i < len && buf[i] >= '0' && buf[i] <= '9') {
            if (e < 10000) e = e * 10 + (buf[i] - '0');
            i++;
        }
        exp10 += e * esgn;
    }

    *consumed = i;

    /* Zero mantissa */
    if (man == 0) {
        return sgn < 0 ? -0.0 : 0.0;
    }

    /* Try exact fast path */
    double val;
    if (!trunc && fj_atof_exact(man, exp10, sgn, &val)) {
        return val;
    }

    /* Try Eisel-Lemire */
    if (fj_eisel_lemire(man, exp10, sgn, &val)) {
        return val;
    }

    /* Fallback: strtod — copy into null-terminated tmp buffer */
    char tmp[64];
    int n = (len < 63) ? len : 63;
    memcpy(tmp, buf, n);
    tmp[n] = '\0';
    char* end;
    val = strtod(tmp, &end);
    *consumed = (int)(end - tmp);
    return val;
}

#endif /* FJ_ATOF_H */
