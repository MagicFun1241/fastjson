module fastjson

// encode serializes a value of type T to a JSON string using direct buffer building.
pub fn encode[T](val T) string {
	$if T.unaliased_typ is string {
		return encode_string_value(val)
	} $else $if T.unaliased_typ is bool {
		return if val { 'true' } else { 'false' }
	} $else $if T.unaliased_typ is int || T.unaliased_typ is i32 {
		return int(val).str()
	} $else $if T.unaliased_typ is i64 {
		return i64(val).str()
	} $else $if T.unaliased_typ is i16 {
		return i16(val).str()
	} $else $if T.unaliased_typ is i8 {
		return i8(val).str()
	} $else $if T.unaliased_typ is u64 {
		return u64(val).str()
	} $else $if T.unaliased_typ is u32 {
		return u32(val).str()
	} $else $if T.unaliased_typ is u16 {
		return u16(val).str()
	} $else $if T.unaliased_typ is u8 {
		return u8(val).str()
	} $else $if T.unaliased_typ is f64 {
		return f64(val).str()
	} $else $if T.unaliased_typ is f32 {
		return f32(val).str()
	} $else $if T.unaliased_typ is $struct {
		return encode_struct(val)
	} $else {
		return 'null'
	}
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
	// Two-pass: first calculate size, then write
	mut size := 2 // {}
	$for field in T.fields {
		size += 4 // ,"k":
		size += field.name.len
		$if field.unaliased_typ is string {
			v := val.$(field.name)
			size += v.len + 2 // quotes
		} $else $if field.unaliased_typ is bool {
			size += 5 // "false"
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
			size += 3 // []
			for item in arr {
				size += item.len + 3 // "item",
			}
		} $else $if field.unaliased_typ is map[string]string {
			m := val.$(field.name)
			size += 2 // {}
			for k, v in m {
				size += k.len + v.len + 6 // "k":"v",
			}
		} $else $if field.is_struct {
			size += 128 // estimate for nested struct
		} $else {
			size += 4 // null
		}
	}

	mut buf := unsafe { &u8(C.malloc(size)) }
	mut p := 0
	unsafe { buf[p] = `{` }
	p++

	mut first := true
	$for field in T.fields {
		if !first {
			unsafe { buf[p] = `,` }
			p++
		}
		first = false

		// Write "fieldname":
		unsafe {
			buf[p] = `"`
			p++
			C.memcpy(buf + p, field.name.str, field.name.len)
			p += field.name.len
			buf[p] = `"`
			p++
			buf[p] = `:`
			p++
		}

		// Write value
		$if field.unaliased_typ is string {
			v := val.$(field.name)
			unsafe {
				buf[p] = `"`
				p++
				C.memcpy(buf + p, v.str, v.len)
				p += v.len
				buf[p] = `"`
				p++
			}
		} $else $if field.unaliased_typ is bool {
			v := val.$(field.name)
			if v {
				unsafe { C.memcpy(buf + p, 'true'.str, 4) }
				p += 4
			} else {
				unsafe { C.memcpy(buf + p, 'false'.str, 5) }
				p += 5
			}
		} $else $if field.unaliased_typ is int {
			v := val.$(field.name)
			p += int_to_buf(buf, p, v)
		} $else $if field.unaliased_typ is i64 {
			v := val.$(field.name)
			p += i64_to_buf(buf, p, v)
		} $else $if field.unaliased_typ is i32 {
			v := val.$(field.name)
			p += int_to_buf(buf, p, int(v))
		} $else $if field.unaliased_typ is i16 {
			v := val.$(field.name)
			p += int_to_buf(buf, p, int(v))
		} $else $if field.unaliased_typ is i8 {
			v := val.$(field.name)
			p += int_to_buf(buf, p, int(v))
		} $else $if field.unaliased_typ is u64 {
			v := val.$(field.name)
			p += u64_to_buf(buf, p, v)
		} $else $if field.unaliased_typ is u32 {
			v := val.$(field.name)
			p += int_to_buf(buf, p, int(v))
		} $else $if field.unaliased_typ is u16 {
			v := val.$(field.name)
			p += int_to_buf(buf, p, int(v))
		} $else $if field.unaliased_typ is u8 {
			v := val.$(field.name)
			p += int_to_buf(buf, p, int(v))
		} $else $if field.unaliased_typ is f64 {
			v := val.$(field.name)
			s := v.str()
			unsafe { C.memcpy(buf + p, s.str, s.len) }
			p += s.len
		} $else $if field.unaliased_typ is f32 {
			v := val.$(field.name)
			s := f64(v).str()
			unsafe { C.memcpy(buf + p, s.str, s.len) }
			p += s.len
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
			unsafe { C.memcpy(buf + p, 'null'.str, 4) }
			p += 4
		}
	}

	unsafe { buf[p] = `}` }
	p++
	return unsafe { tos(buf, p) }
}

fn int_to_buf(buf &u8, start int, val int) int {
	if val == 0 {
		unsafe { buf[start] = `0` }
		return 1
	}
	mut neg := false
	mut v := val
	if v < 0 {
		neg = true
		v = -v
	}
	mut tmp := [20]u8{}
	mut pos := 0
	for v > 0 {
		tmp[pos] = u8(v % 10) + `0`
		v = v / 10
		pos++
	}
	mut p := start
	if neg {
		unsafe { buf[p] = `-` }
		p++
	}
	for j := 0; j < pos; j++ {
		unsafe { buf[p] = tmp[pos - 1 - j] }
		p++
	}
	return p - start
}

fn i64_to_buf(buf &u8, start int, val i64) int {
	if val == 0 {
		unsafe { buf[start] = `0` }
		return 1
	}
	mut neg := false
	mut v := val
	if v < 0 {
		neg = true
		v = -v
	}
	mut tmp := [20]u8{}
	mut pos := 0
	for v > 0 {
		tmp[pos] = u8(v % 10) + `0`
		v = v / 10
		pos++
	}
	mut p := start
	if neg {
		unsafe { buf[p] = `-` }
		p++
	}
	for j := 0; j < pos; j++ {
		unsafe { buf[p] = tmp[pos - 1 - j] }
		p++
	}
	return p - start
}

fn u64_to_buf(buf &u8, start int, val u64) int {
	if val == 0 {
		unsafe { buf[start] = `0` }
		return 1
	}
	mut tmp := [20]u8{}
	mut pos := 0
	mut v := val
	for v > 0 {
		tmp[pos] = u8(v % 10) + `0`
		v = v / 10
		pos++
	}
	mut p := start
	for j := 0; j < pos; j++ {
		unsafe { buf[p] = tmp[pos - 1 - j] }
		p++
	}
	return p - start
}
