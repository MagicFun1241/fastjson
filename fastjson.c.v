module fastjson

#flag -I @VMODROOT
#include "fastjson_impl.c.h"

fn C.simd_find_char(buf &u8, len int, c u8) int
fn C.simd_find_two(buf &u8, len int, c1 u8, c2 u8, out_pos &int, out_is_c2 &int)
fn C.simd_skip_ws(buf &u8, len int, start int) int
fn C.fast_parse_int(buf &u8, len int, consumed &int) i64
fn C.fast_parse_f64(buf &u8, len int, consumed &int) f64
fn C.scan_json_string(buf &u8, len int, start int, content_start &int, content_len &int) int
fn C.skip_json_value(buf &u8, len int, pos int) int
