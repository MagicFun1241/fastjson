module fastjson

import strings

// f64_to_str converts a float64 to its shortest decimal representation using Schubfach algorithm.
// Writes "null" for inf/nan.
pub fn f64_to_str(val f64) string {
	mut sb := strings.new_builder(32)
	n := unsafe { C.fast_f64_to_buf(sb.data, 0, val) }
	unsafe { sb.len = n }
	return sb.str()
}

// encode serializes a value of type T to a JSON string using direct buffer building.
pub fn encode[T](val T) string {
	$if T.unaliased_typ is string {
		return encode_string_value(val)
	} $else $if T.unaliased_typ is bool {
		return if val { 'true' } else { 'false' }
	} $else $if T.unaliased_typ is int || T.unaliased_typ is i32 {
		return int_to_str(i64(val))
	} $else $if T.unaliased_typ is i64 {
		return int_to_str(val)
	} $else $if T.unaliased_typ is i16 {
		return int_to_str(i64(val))
	} $else $if T.unaliased_typ is i8 {
		return int_to_str(i64(val))
	} $else $if T.unaliased_typ is u64 {
		return uint64_to_str(val)
	} $else $if T.unaliased_typ is u32 {
		return int_to_str(i64(val))
	} $else $if T.unaliased_typ is u16 {
		return int_to_str(i64(val))
	} $else $if T.unaliased_typ is u8 {
		return int_to_str(i64(val))
	} $else $if T.unaliased_typ is f64 {
		return f64_to_str(f64(val))
	} $else $if T.unaliased_typ is f32 {
		return f64_to_str(f64(val))
	} $else $if T.unaliased_typ is $struct {
		return encode_struct(val)
	} $else {
		return 'null'
	}
}

// Direct int-to-string via C, avoiding V's .str() allocation overhead.
fn int_to_str(val i64) string {
	mut sb := strings.new_builder(24)
	n := unsafe { C.fast_int_to_buf(sb.data, 0, val) }
	unsafe { sb.len = n }
	return sb.str()
}

fn uint64_to_str(val u64) string {
	mut sb := strings.new_builder(24)
	n := unsafe { C.fast_uint64_to_buf(sb.data, 0, val) }
	unsafe { sb.len = n }
	return sb.str()
}

fn encode_string_value(s string) string {
	mut sb := strings.new_builder(s.len + 2)
	buf := unsafe { &u8(sb.data) }
	total := s.len + 2
	unsafe {
		buf[0] = u8(`"`)
		C.memcpy(buf + 1, s.str, s.len)
		buf[s.len + 1] = u8(`"`)
	}
	unsafe { sb.len = total }
	return sb.str()
}

fn encode_struct[T](val T) string {
	// Size pass — compute exact buffer size
	mut size := 2 // {}
	$for field in T.fields {
		size += 4 + field.name.len // ,"key":
		$if field.unaliased_typ is string {
			size += val.$(field.name).len + 2
		} $else $if field.unaliased_typ is bool {
			size += 5
		} $else $if field.unaliased_typ is int {
			size += 12
		} $else $if field.unaliased_typ is i64 {
			size += 21
		} $else $if field.unaliased_typ is i32 {
			size += 12
		} $else $if field.unaliased_typ is i16 {
			size += 7
		} $else $if field.unaliased_typ is i8 {
			size += 5
		} $else $if field.unaliased_typ is u64 {
			size += 21
		} $else $if field.unaliased_typ is u32 {
			size += 11
		} $else $if field.unaliased_typ is u16 {
			size += 6
		} $else $if field.unaliased_typ is u8 {
			size += 4
		} $else $if field.unaliased_typ is f64 {
			size += 24
		} $else $if field.unaliased_typ is f32 {
			size += 16
		} $else $if field.unaliased_typ is []string {
			size += 3
			for item in val.$(field.name) {
				size += item.len + 3
			}
		} $else $if field.unaliased_typ is map[string]string {
			size += 2
			for k, v in val.$(field.name) {
				size += k.len + v.len + 6
			}
		} $else $if field.is_struct {
			sub := encode(val.$(field.name))
			size += sub.len
		} $else {
			size += 4
		}
	}

	mut sb := strings.new_builder(size)
	// Write directly into builder's buffer using C helpers
	buf := unsafe { &u8(sb.data) }
	mut p := 0
	unsafe { buf[p] = u8(`{`) }
	p++

	mut first := 1
	$for field in T.fields {
		// Write ,"key": via C — single call, no V buf[p] boundary checks
		p = unsafe { C.fj_write_obj_key(buf, p, first, field.name.str, field.name.len) }
		first = 0

		// Write value — local vars for primitives (safe under autofree, value types).
		// Arrays/maps use direct field access to avoid V autofree ComptimeSelector bug.
		$if field.unaliased_typ is string {
			v := val.$(field.name)
			p = unsafe { C.fj_write_string(buf, p, v.str, v.len) }
		} $else $if field.unaliased_typ is bool {
			v := val.$(field.name)
			p = unsafe { C.fj_write_bool(buf, p, int(v)) }
		} $else $if field.unaliased_typ is int {
			p += unsafe { C.fast_int_to_buf(buf, p, i64(val.$(field.name))) }
		} $else $if field.unaliased_typ is i64 {
			p += unsafe { C.fast_int_to_buf(buf, p, val.$(field.name)) }
		} $else $if field.unaliased_typ is i32 {
			p += unsafe { C.fast_int_to_buf(buf, p, i64(val.$(field.name))) }
		} $else $if field.unaliased_typ is i16 {
			p += unsafe { C.fast_int_to_buf(buf, p, i64(val.$(field.name))) }
		} $else $if field.unaliased_typ is i8 {
			p += unsafe { C.fast_int_to_buf(buf, p, i64(val.$(field.name))) }
		} $else $if field.unaliased_typ is u64 {
			p += unsafe { C.fast_uint64_to_buf(buf, p, val.$(field.name)) }
		} $else $if field.unaliased_typ is u32 {
			p += unsafe { C.fast_int_to_buf(buf, p, i64(val.$(field.name))) }
		} $else $if field.unaliased_typ is u16 {
			p += unsafe { C.fast_int_to_buf(buf, p, i64(val.$(field.name))) }
		} $else $if field.unaliased_typ is u8 {
			p += unsafe { C.fast_int_to_buf(buf, p, i64(val.$(field.name))) }
		} $else $if field.unaliased_typ is f64 {
			p += unsafe { C.fast_f64_to_buf(buf, p, val.$(field.name)) }
		} $else $if field.unaliased_typ is f32 {
			p += unsafe { C.fast_f64_to_buf(buf, p, f64(val.$(field.name))) }
		} $else $if field.unaliased_typ is []string {
			unsafe { buf[p] = u8(`[`) }
			p++
			mut arr_first := true
			for item in val.$(field.name) {
				if !arr_first {
					unsafe { buf[p] = u8(`,`) }
					p++
				}
				arr_first = false
				unsafe {
					buf[p] = u8(`"`)
					p++
					C.memcpy(buf + p, item.str, item.len)
					p += item.len
					buf[p] = u8(`"`)
					p++
				}
			}
			unsafe { buf[p] = u8(`]`) }
			p++
		} $else $if field.unaliased_typ is map[string]string {
			unsafe { buf[p] = u8(`{`) }
			p++
			mut mfirst := true
			for k, v in val.$(field.name) {
				if !mfirst {
					unsafe { buf[p] = u8(`,`) }
					p++
				}
				mfirst = false
				unsafe {
					buf[p] = u8(`"`)
					p++
					C.memcpy(buf + p, k.str, k.len)
					p += k.len
					C.memcpy(buf + p, '":"'.str, 3)
					p += 3
					C.memcpy(buf + p, v.str, v.len)
					p += v.len
					buf[p] = u8(`"`)
					p++
				}
			}
			unsafe { buf[p] = u8(`}`) }
			p++
		} $else $if field.is_struct {
			sub := encode(val.$(field.name))
			unsafe { C.memcpy(buf + p, sub.str, sub.len) }
			p += sub.len
		} $else {
			p = unsafe { C.fj_write_null(buf, p) }
		}
	}

	unsafe { buf[p] = u8(`}`) }
	p++
	unsafe { sb.len = p }
	return sb.str()
}
