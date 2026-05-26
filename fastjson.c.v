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
fn C.fast_int_to_buf(buf &u8, start int, val i64) int
fn C.fast_uint64_to_buf(buf &u8, start int, val u64) int
fn C.fast_f64_to_buf(buf &u8, start int, val f64) int
fn C.fj_write_obj_key(buf &u8, p int, first int, key &u8, key_len int) int
fn C.fj_write_string(buf &u8, p int, s &u8, s_len int) int
fn C.fj_write_bool(buf &u8, p int, val int) int
fn C.fj_write_null(buf &u8, p int) int
fn C.fj_write_string_array(buf &u8, p int, strs &&u8, lens &int, count int) int
fn C.fj_write_string_map(buf &u8, p int, keys &&u8, key_lens &int, vals &&u8, val_lens &int, count int) int
fn C.simd_memcmp(s1 &u8, s2 &u8, n int) int

// Zero-allocation scan iterator — V struct mirrors C fj_scan_pair layout
struct ScanPair {
	key_start int
	key_len   int
	val_start int
	val_len   int
	kind      int // 0=null, 1=bool, 2=int, 3=float, 4=string, 5=array, 6=object
}

fn C.fj_scan_open(buf &u8, len int) int
fn C.fj_scan_next(buf &u8, len int, pos int, pair &ScanPair) int
