module fastjson

// f64_to_str converts a float64 to its shortest decimal representation using Schubfach algorithm.
// Writes "null" for inf/nan.
pub fn f64_to_str(val f64) string {
	buf := unsafe { C.malloc(64) }
	n := C.fast_f64_to_buf(buf, 0, val)
	return unsafe { tos(buf, n) }
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
	buf := unsafe { C.malloc(21) }
	n := unsafe { C.fast_int_to_buf(buf, 0, val) }
	return unsafe { tos(buf, n) }
}

fn uint64_to_str(val u64) string {
	buf := unsafe { C.malloc(21) }
	n := unsafe { C.fast_uint64_to_buf(buf, 0, val) }
	return unsafe { tos(buf, n) }
}

fn encode_string_value(s string) string {
	mut buf := unsafe { &u8(C.malloc(s.len + 2)) }
	unsafe {
		buf[0] = `"`
		C.memcpy(buf + 1, s.str, s.len)
		buf[s.len + 1] = `"`
	}
	return unsafe { tos(buf, s.len + 2) }
}

fn encode_struct[T](val T) string {
	// Size pass — uses C helpers to minimize V boundary checks
	mut size := 2 // {}
	$for field in T.fields {
		size += 4 + field.name.len // ,"key":
		$if field.unaliased_typ is string {
			v := val.$(field.name)
			size += v.len + 2
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
			arr := val.$(field.name)
			size += 3
			for item in arr {
				size += item.len + 3
			}
		} $else $if field.unaliased_typ is map[string]string {
			m := val.$(field.name)
			size += 2
			for k, v in m {
				size += k.len + v.len + 6
			}
		} $else $if field.is_struct {
			size += 128
		} $else {
			size += 4
		}
	}

	buf := unsafe { &u8(C.malloc(size)) }
	mut p := 0
	unsafe { buf[p] = `{` }
	p++

	mut first := 1
	$for field in T.fields {
		// Write ,"key": via C — single call, no V buf[p] boundary checks
		p = unsafe { C.fj_write_obj_key(buf, p, first, field.name.str, field.name.len) }
		first = 0

		// Write value — use C helpers where possible to avoid buf[p] checks
		$if field.unaliased_typ is string {
			v := val.$(field.name)
			p = unsafe { C.fj_write_string(buf, p, v.str, v.len) }
		} $else $if field.unaliased_typ is bool {
			v := val.$(field.name)
			p = unsafe { C.fj_write_bool(buf, p, int(v)) }
		} $else $if field.unaliased_typ is int {
			v := val.$(field.name)
			p += unsafe { C.fast_int_to_buf(buf, p, i64(v)) }
		} $else $if field.unaliased_typ is i64 {
			v := val.$(field.name)
			p += unsafe { C.fast_int_to_buf(buf, p, v) }
		} $else $if field.unaliased_typ is i32 {
			v := val.$(field.name)
			p += unsafe { C.fast_int_to_buf(buf, p, i64(v)) }
		} $else $if field.unaliased_typ is i16 {
			v := val.$(field.name)
			p += unsafe { C.fast_int_to_buf(buf, p, i64(v)) }
		} $else $if field.unaliased_typ is i8 {
			v := val.$(field.name)
			p += unsafe { C.fast_int_to_buf(buf, p, i64(v)) }
		} $else $if field.unaliased_typ is u64 {
			v := val.$(field.name)
			p += unsafe { C.fast_uint64_to_buf(buf, p, v) }
		} $else $if field.unaliased_typ is u32 {
			v := val.$(field.name)
			p += unsafe { C.fast_int_to_buf(buf, p, i64(v)) }
		} $else $if field.unaliased_typ is u16 {
			v := val.$(field.name)
			p += unsafe { C.fast_int_to_buf(buf, p, i64(v)) }
		} $else $if field.unaliased_typ is u8 {
			v := val.$(field.name)
			p += unsafe { C.fast_int_to_buf(buf, p, i64(v)) }
		} $else $if field.unaliased_typ is f64 {
			v := val.$(field.name)
			p += unsafe { C.fast_f64_to_buf(buf, p, v) }
		} $else $if field.unaliased_typ is f32 {
			v := val.$(field.name)
			p += unsafe { C.fast_f64_to_buf(buf, p, f64(v)) }
		} $else $if field.unaliased_typ is []string {
			arr := val.$(field.name)
			unsafe { buf[p] = `[` }
			p++
			for i, item in arr {
				if i > 0 {
					unsafe { buf[p] = `,` }
					p++
				}
				unsafe {
					buf[p] = `"`
					p++
					C.memcpy(buf + p, item.str, item.len)
					p += item.len
					buf[p] = `"`
					p++
				}
			}
			unsafe { buf[p] = `]` }
			p++
		} $else $if field.unaliased_typ is map[string]string {
			m := val.$(field.name)
			unsafe { buf[p] = `{` }
			p++
			mut mfirst := true
			for k, v in m {
				if !mfirst {
					unsafe { buf[p] = `,` }
					p++
				}
				mfirst = false
				unsafe {
					buf[p] = `"`
					p++
					C.memcpy(buf + p, k.str, k.len)
					p += k.len
					C.memcpy(buf + p, '":"'.str, 3)
					p += 3
					C.memcpy(buf + p, v.str, v.len)
					p += v.len
					buf[p] = `"`
					p++
				}
			}
			unsafe { buf[p] = `}` }
			p++
		} $else $if field.is_struct {
			sub := encode(val.$(field.name))
			unsafe { C.memcpy(buf + p, sub.str, sub.len) }
			p += sub.len
		} $else {
			p = unsafe { C.fj_write_null(buf, p) }
		}
	}

	unsafe { buf[p] = `}` }
	p++
	return unsafe { tos(buf, p) }
}