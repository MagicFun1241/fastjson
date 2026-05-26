#ifndef FASTJSON_IMPL_H
#define FASTJSON_IMPL_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "fj_atof.h"
#include "fj_itoa.h"

/* ============================================================
 * SSE2 SIMD primitives
 * ============================================================ */
#ifdef __SSE2__
#include <emmintrin.h>

static inline int simd_find_char(const uint8_t* buf, int len, uint8_t c) {
    int i = 0;
    const __m128i vc = _mm_set1_epi8((char)c);
    for (; i + 16 <= len; i += 16) {
        __m128i chunk = _mm_loadu_si128((const __m128i*)(buf + i));
        int mask = _mm_movemask_epi8(_mm_cmpeq_epi8(chunk, vc));
        if (mask) return i + __builtin_ctz(mask);
    }
    for (; i < len; i++) {
        if (buf[i] == c) return i;
    }
    return -1;
}

static inline void simd_find_two(const uint8_t* buf, int len, uint8_t c1, uint8_t c2,
                                  int* out_pos, int* out_is_c2) {
    int i = 0;
    const __m128i vc1 = _mm_set1_epi8((char)c1);
    const __m128i vc2 = _mm_set1_epi8((char)c2);
    for (; i + 16 <= len; i += 16) {
        __m128i chunk = _mm_loadu_si128((const __m128i*)(buf + i));
        int m1 = _mm_movemask_epi8(_mm_cmpeq_epi8(chunk, vc1));
        int m2 = _mm_movemask_epi8(_mm_cmpeq_epi8(chunk, vc2));
        int combined = m1 | m2;
        if (combined) {
            int bit = __builtin_ctz(combined);
            *out_pos = i + bit;
            *out_is_c2 = (m2 >> bit) & 1;
            return;
        }
    }
    for (; i < len; i++) {
        if (buf[i] == c2) { *out_pos = i; *out_is_c2 = 1; return; }
        if (buf[i] == c1) { *out_pos = i; *out_is_c2 = 0; return; }
    }
    *out_pos = -1;
    *out_is_c2 = 0;
}

static inline int simd_skip_ws(const uint8_t* buf, int len, int start) {
    int i = start;
    if (i >= len) return len;
    if (buf[i] != ' ' && buf[i] != '\t' && buf[i] != '\r' && buf[i] != '\n') return i;
    i++;
    const __m128i vsp = _mm_set1_epi8(' ');
    const __m128i vtab = _mm_set1_epi8('\t');
    const __m128i vcr = _mm_set1_epi8('\r');
    const __m128i vlf = _mm_set1_epi8('\n');
    for (; i + 16 <= len; i += 16) {
        __m128i chunk = _mm_loadu_si128((const __m128i*)(buf + i));
        __m128i eq = _mm_or_si128(
            _mm_or_si128(_mm_cmpeq_epi8(chunk, vsp), _mm_cmpeq_epi8(chunk, vtab)),
            _mm_or_si128(_mm_cmpeq_epi8(chunk, vcr), _mm_cmpeq_epi8(chunk, vlf)));
        int mask = _mm_movemask_epi8(eq);
        if (mask != 0xffff) {
            return i + __builtin_ctz(~mask);
        }
    }
    for (; i < len; i++) {
        if (buf[i] != ' ' && buf[i] != '\t' && buf[i] != '\r' && buf[i] != '\n') return i;
    }
    return len;
}

/* Find first structural character (}, ], ,) — used for fast number skip.
 * Returns offset from buf, or len if not found. */
static inline int simd_structural_mask(const uint8_t* buf, int len) {
    const __m128i vbrace = _mm_set1_epi8('}');
    const __m128i vbracket = _mm_set1_epi8(']');
    const __m128i vcomma = _mm_set1_epi8(',');
    int i = 0;
    for (; i + 16 <= len; i += 16) {
        __m128i chunk = _mm_loadu_si128((const __m128i*)(buf + i));
        __m128i sv = _mm_or_si128(
            _mm_or_si128(_mm_cmpeq_epi8(chunk, vbrace), _mm_cmpeq_epi8(chunk, vbracket)),
            _mm_cmpeq_epi8(chunk, vcomma));
        int mask = _mm_movemask_epi8(sv);
        if (mask) return i + __builtin_ctz(mask);
    }
    for (; i < len; i++) {
        if (buf[i] == '}' || buf[i] == ']' || buf[i] == ',') return i;
    }
    return len;
}

/* SIMD memory comparison — 16 bytes at a time.
 * Returns 0 if equal, 1 if different. */
static inline int simd_memcmp(const uint8_t* s1, const uint8_t* s2, int n) {
    int i = 0;
    for (; i + 16 <= n; i += 16) {
        __m128i v1 = _mm_loadu_si128((const __m128i*)(s1 + i));
        __m128i v2 = _mm_loadu_si128((const __m128i*)(s2 + i));
        int mask = ~_mm_movemask_epi8(_mm_cmpeq_epi8(v1, v2));
        if (mask) return 1;
    }
    for (; i < n; i++) {
        if (s1[i] != s2[i]) return 1;
    }
    return 0;
}

#else
/* Scalar fallback for ARM / non-SSE2 platforms */

static inline int simd_find_char(const uint8_t* buf, int len, uint8_t c) {
    for (int i = 0; i < len; i++) {
        if (buf[i] == c) return i;
    }
    return -1;
}

static inline void simd_find_two(const uint8_t* buf, int len, uint8_t c1, uint8_t c2,
                                  int* out_pos, int* out_is_c2) {
    for (int i = 0; i < len; i++) {
        if (buf[i] == c2) { *out_pos = i; *out_is_c2 = 1; return; }
        if (buf[i] == c1) { *out_pos = i; *out_is_c2 = 0; return; }
    }
    *out_pos = -1;
    *out_is_c2 = 0;
}

static inline int simd_skip_ws(const uint8_t* buf, int len, int start) {
    for (int i = start; i < len; i++) {
        if (buf[i] != ' ' && buf[i] != '\t' && buf[i] != '\r' && buf[i] != '\n') return i;
    }
    return len;
}

static inline int simd_structural_mask(const uint8_t* buf, int len) {
    for (int i = 0; i < len; i++) {
        if (buf[i] == '}' || buf[i] == ']' || buf[i] == ',') return i;
    }
    return len;
}

static inline int simd_memcmp(const uint8_t* s1, const uint8_t* s2, int n) {
    return memcmp(s1, s2, n) != 0;
}

#endif /* __SSE2__ */

/* ============================================================
 * Common fast parsers (all platforms)
 * ============================================================ */

static inline int64_t fast_parse_int(const uint8_t* buf, int len, int* consumed) {
    int64_t val = 0;
    int i = 0;
    int neg = 0;
    if (i < len && buf[i] == '-') { neg = 1; i++; }
    for (; i + 4 <= len; i += 4) {
        if (buf[i] < '0' || buf[i] > '9') break;
        if (buf[i+1] < '0' || buf[i+1] > '9') { val = val * 10 + (buf[i] - '0'); i++; break; }
        if (buf[i+2] < '0' || buf[i+2] > '9') { val = val * 100 + (buf[i] - '0') * 10 + (buf[i+1] - '0'); i += 2; break; }
        if (buf[i+3] < '0' || buf[i+3] > '9') { val = val * 1000 + (buf[i] - '0') * 100 + (buf[i+1] - '0') * 10 + (buf[i+2] - '0'); i += 3; break; }
        val = val * 10000
            + (buf[i] - '0') * 1000
            + (buf[i+1] - '0') * 100
            + (buf[i+2] - '0') * 10
            + (buf[i+3] - '0');
    }
    for (; i < len; i++) {
        if (buf[i] < '0' || buf[i] > '9') break;
        val = val * 10 + (buf[i] - '0');
    }
    *consumed = i;
    return neg ? -val : val;
}

static inline double fast_parse_f64(const uint8_t* buf, int len, int* consumed) {
    return fj_parse_f64(buf, len, consumed);
}

/* Scan a JSON string value, handling escape sequences.
 * Returns position after closing quote.
 * Sets content_start/content_len for zero-copy slice. */
static inline int scan_json_string(const uint8_t* buf, int len, int start,
                                    int* content_start, int* content_len) {
    if (start >= len || buf[start] != '"') { *content_start = start; *content_len = 0; return start; }
    int cs = start + 1;
    int pos = cs;
    while (pos < len) {
        int fp = 0, fe = 0;
        simd_find_two(buf + pos, len - pos, '"', '\\', &fp, &fe);
        if (fp < 0) { *content_start = cs; *content_len = len - cs; return len; }
        if (fe) { pos += fp + 2; continue; }
        *content_start = cs;
        *content_len = pos + fp - cs;
        return pos + fp + 1;
    }
    *content_start = cs;
    *content_len = 0;
    return len;
}

/* ============================================================
 * Optimized skip_json_value — SIMD-accelerated
 *   - Numbers: SIMD structural char scan (find },],, in 16B blocks)
 *   - Containers: combined SIMD check for quote + open + close
 * ============================================================ */
static inline int skip_json_value(const uint8_t* buf, int len, int pos) {
    if (pos >= len) return len;
    uint8_t ch = buf[pos];

    if (ch == '"') {
        int cs = 0, cl = 0;
        return scan_json_string(buf, len, pos, &cs, &cl);

    } else if (ch == '{' || ch == '[') {
        /* SIMD-accelerated container skip */
        uint8_t open_ch = ch;
        uint8_t close_ch = (ch == '{') ? '}' : ']';
        int depth = 1;
        int p = pos + 1;

#ifdef __SSE2__
        const __m128i vquote = _mm_set1_epi8('"');
        const __m128i vopen = _mm_set1_epi8((char)open_ch);
        const __m128i vclose = _mm_set1_epi8((char)close_ch);

        while (p + 16 <= len && depth > 0) {
            __m128i chunk = _mm_loadu_si128((const __m128i*)(buf + p));
            int mq = _mm_movemask_epi8(_mm_cmpeq_epi8(chunk, vquote));
            int mo = _mm_movemask_epi8(_mm_cmpeq_epi8(chunk, vopen));
            int mc = _mm_movemask_epi8(_mm_cmpeq_epi8(chunk, vclose));

            if (!(mq | mo | mc)) {
                p += 16;
                continue;
            }

            /* Find earliest relevant char */
            int earliest = p + 16;
            if (mq) { int x = p + __builtin_ctz(mq); if (x < earliest) earliest = x; }
            if (mo) { int x = p + __builtin_ctz(mo); if (x < earliest) earliest = x; }
            if (mc) { int x = p + __builtin_ctz(mc); if (x < earliest) earliest = x; }

            uint8_t c = buf[earliest];
            if (c == '"') {
                int cs2 = 0, cl2 = 0;
                p = scan_json_string(buf, len, earliest, &cs2, &cl2);
                continue;
            }
            if (c == open_ch) depth++;
            if (c == close_ch) { depth--; }
            p = earliest + 1;
        }
#endif

        /* Scalar fallback / tail */
        while (p < len && depth > 0) {
            if (buf[p] == '"') {
                int cs2 = 0, cl2 = 0;
                p = scan_json_string(buf, len, p, &cs2, &cl2);
                continue;
            }
            if (buf[p] == open_ch) depth++;
            if (buf[p] == close_ch) { depth--; }
            p++;
        }
        return p;

    } else if ((ch >= '0' && ch <= '9') || ch == '-') {
        /* SIMD structural char scan for fast number termination */
        int remaining = len - pos;
        int end = simd_structural_mask(buf + pos, remaining);
        int p = pos + end;
        /* Trim trailing whitespace before structural char */
        while (p > pos && (buf[p-1] == ' ' || buf[p-1] == '\t' || buf[p-1] == '\r' || buf[p-1] == '\n')) p--;
        return p;

    } else if (ch == 't') { return (pos + 4 <= len) ? pos + 4 : len; }
    else if (ch == 'f') { return (pos + 5 <= len) ? pos + 5 : len; }
    else if (ch == 'n') { return (pos + 4 <= len) ? pos + 4 : len; }
    return pos + 1;
}

#endif /* FASTJSON_IMPL_H */
