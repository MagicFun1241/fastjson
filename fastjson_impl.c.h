#ifndef FASTJSON_IMPL_H
#define FASTJSON_IMPL_H

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include "fj_atof.h"
#include "fj_itoa.h"
#include "fj_dtoa.h"

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

/* Fast float-to-string using Schubfach algorithm.
 * Writes directly into the output buffer. Returns number of characters written.
 * Returns -1 only for inf/nan (writes "null" for JSON). */
static inline int fast_f64_to_buf(uint8_t* buf, int start, double val) {
    int n = fj_f64toa((char*)(buf + start), val);
    if (n <= 0) {
        /* inf or nan — write "null" for JSON */
        memcpy(buf + start, "null", 4);
        return 4;
    }
    return n;
}

/* Write JSON object key:  ,"key":
 * Returns number of bytes written. */
static inline int fj_write_obj_key(uint8_t* buf, int p, int first,
                                    const char* key, int key_len) {
    if (!first) { buf[p] = ','; p++; }
    buf[p] = '"'; p++;
    memcpy(buf + p, key, key_len); p += key_len;
    buf[p] = '"'; p++;
    buf[p] = ':'; p++;
    return p;
}

/* Write JSON string value:  "str"
 * Returns new position p. */
static inline int fj_write_string(uint8_t* buf, int p, const char* s, int s_len) {
    buf[p] = '"'; p++;
    memcpy(buf + p, s, s_len); p += s_len;
    buf[p] = '"'; p++;
    return p;
}

/* Write JSON bool:  true / false
 * Returns new position p. */
static inline int fj_write_bool(uint8_t* buf, int p, int val) {
    if (val) {
        memcpy(buf + p, "true", 4); p += 4;
    } else {
        memcpy(buf + p, "false", 5); p += 5;
    }
    return p;
}

/* Write JSON null
 * Returns new position p. */
static inline int fj_write_null(uint8_t* buf, int p) {
    memcpy(buf + p, "null", 4); p += 4;
    return p;
}

/* Write JSON array of strings:  ["a","b"]
 * Returns new position p. */
static inline int fj_write_string_array(uint8_t* buf, int p,
                                          const char** strs, const int* lens, int count) {
    buf[p] = '['; p++;
    for (int i = 0; i < count; i++) {
        if (i > 0) { buf[p] = ','; p++; }
        buf[p] = '"'; p++;
        memcpy(buf + p, strs[i], lens[i]); p += lens[i];
        buf[p] = '"'; p++;
    }
    buf[p] = ']'; p++;
    return p;
}

/* Write JSON map of strings:  {"k":"v","k2":"v2"}
 * Returns new position p. */
static inline int fj_write_string_map(uint8_t* buf, int p,
                                        const char** keys, const int* key_lens,
                                        const char** vals, const int* val_lens, int count) {
    buf[p] = '{'; p++;
    for (int i = 0; i < count; i++) {
        if (i > 0) { buf[p] = ','; p++; }
        buf[p] = '"'; p++;
        memcpy(buf + p, keys[i], key_lens[i]); p += key_lens[i];
        memcpy(buf + p, "\":\"", 3); p += 3;
        memcpy(buf + p, vals[i], val_lens[i]); p += val_lens[i];
        buf[p] = '"'; p++;
    }
    buf[p] = '}'; p++;
    return p;
}

/* ============================================================
 * Zero-allocation scan iterator
 *   - fj_scan_pair: stack struct for key/value pair info
 *   - fj_scan_open: skip ws, validate '{', return pos after it
 *   - fj_scan_next: find next key/value pair, fill pair, return new pos
 * ============================================================ */

typedef struct fj_scan_pair {
    int key_start;
    int key_len;
    int val_start;
    int val_len;
    int kind;  /* 0=null, 1=bool, 2=int, 3=float, 4=string, 5=array, 6=object */
} fj_scan_pair;

/* Skip whitespace and validate opening '{'.
 * Returns position after '{', or -1 on error. */
static inline int fj_scan_open(const uint8_t* buf, int len) {
    int pos = simd_skip_ws(buf, len, 0);
    if (pos >= len || buf[pos] != '{') return -1;
    return pos + 1;
}

/* Find next key/value pair in a JSON object.
 * *pair is filled with key position/length, value position/length, and kind.
 * Returns new position (after value), or -1 if '}' or end reached. */
static inline int fj_scan_next(const uint8_t* buf, int len, int pos, fj_scan_pair* pair) {
    pos = simd_skip_ws(buf, len, pos);
    if (pos >= len || buf[pos] == '}') return -1;
    if (buf[pos] == ',') {
        pos++;
        pos = simd_skip_ws(buf, len, pos);
        if (pos >= len || buf[pos] == '}') return -1;
    }

    /* Parse key */
    if (buf[pos] != '"') { pos++; return pos; }
    int cs = 0, cl = 0;
    pos = scan_json_string(buf, len, pos, &cs, &cl);
    pair->key_start = cs;
    pair->key_len = cl;

    /* Skip to colon */
    int colon = simd_find_char(buf + pos, len - pos, ':');
    if (colon < 0) return -1;
    pos += colon + 1;
    pos = simd_skip_ws(buf, len, pos);
    if (pos >= len) return -1;

    /* Determine value kind and position */
    int val_start = pos;
    uint8_t ch = buf[pos];
    switch (ch) {
        case '"': {
            pair->kind = 4; /* string */
            int vs = 0, vl = 0;
            pos = scan_json_string(buf, len, pos, &vs, &vl);
            break;
        }
        case '{': {
            pair->kind = 6; /* object */
            pos = skip_json_value(buf, len, pos);
            break;
        }
        case '[': {
            pair->kind = 5; /* array */
            pos = skip_json_value(buf, len, pos);
            break;
        }
        case 't': case 'f': {
            pair->kind = 1; /* bool */
            pos = skip_json_value(buf, len, pos);
            break;
        }
        case 'n': {
            pair->kind = 0; /* null */
            pos = skip_json_value(buf, len, pos);
            break;
        }
        default: {
            /* Number: single structural scan to find end, then check for '.' within range */
            if ((ch >= '0' && ch <= '9') || ch == '-') {
                int remaining = len - pos;
                int end_off = simd_structural_mask(buf + pos, remaining);
                /* Check if '.' appears before the structural char */
                int is_float = 0;
                /* Scan only up to the structural char for '.' */
                int scan_end = (end_off < remaining) ? end_off : remaining;
                for (int i = 0; i < scan_end; i++) {
                    if (buf[pos + i] == '.') { is_float = 1; break; }
                }
                pair->kind = is_float ? 3 : 2; /* float or int */
                pos += end_off;
                /* Trim trailing whitespace before structural char */
                while (pos > val_start && (buf[pos-1] == ' ' || buf[pos-1] == '\t' || buf[pos-1] == '\r' || buf[pos-1] == '\n')) pos--;
            } else {
                pair->kind = 0; /* unknown -> null */
                pos++;
            }
            break;
        }
    }
    pair->val_start = val_start;
    pair->val_len = pos - val_start;
    return pos;
}

#endif /* FASTJSON_IMPL_H */
