module fastjson

// decode_nested recursively decodes a nested struct field from a JSON substring.
fn decode_nested[T](s string, mut val T) {
	$if T is $struct {
		fields := scan_object(s)
		$for field in T.fields {
			json_name := field.name
			$if field.unaliased_typ is string {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					val.$(field.name) = extract_string(s, fields[idx])
				}
			} $else $if field.unaliased_typ is int {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					val.$(field.name) = extract_int(s, fields[idx])
				}
			} $else $if field.unaliased_typ is i64 {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					val.$(field.name) = extract_i64(s, fields[idx])
				}
			} $else $if field.unaliased_typ is f64 {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					val.$(field.name) = extract_f64(s, fields[idx])
				}
			} $else $if field.unaliased_typ is bool {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					val.$(field.name) = extract_bool(s, fields[idx])
				}
			} $else $if field.is_struct {
				idx := find_field(s, fields, json_name)
				if idx >= 0 && fields[idx].kind == .object_ {
					sub := extract_substring(s, fields[idx])
					decode_nested(sub, mut val.$(field.name))
				}
			}
		}
	}
}

// decode parses a JSON string into type T using SIMD-accelerated scanning.
// Supports structs with fields of type: string, int, i64, f64, bool, []string, []int, []f64, map[string]string, and nested structs.
pub fn decode[T](s string) !T {
	mut result := T{}
	$if T is $struct {
		fields := scan_object(s)
		$for field in T.fields {
			json_name := field.name
			$if field.unaliased_typ is string {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = extract_string(s, fields[idx])
				}
			} $else $if field.unaliased_typ is int {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = extract_int(s, fields[idx])
				}
			} $else $if field.unaliased_typ is i64 {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = extract_i64(s, fields[idx])
				}
			} $else $if field.unaliased_typ is i32 {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = i32(extract_int(s, fields[idx]))
				}
			} $else $if field.unaliased_typ is i16 {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = i16(extract_int(s, fields[idx]))
				}
			} $else $if field.unaliased_typ is i8 {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = i8(extract_int(s, fields[idx]))
				}
			} $else $if field.unaliased_typ is u64 {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = u64(extract_i64(s, fields[idx]))
				}
			} $else $if field.unaliased_typ is u32 {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = u32(extract_int(s, fields[idx]))
				}
			} $else $if field.unaliased_typ is u16 {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = u16(extract_int(s, fields[idx]))
				}
			} $else $if field.unaliased_typ is u8 {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = u8(extract_int(s, fields[idx]))
				}
			} $else $if field.unaliased_typ is f64 {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = extract_f64(s, fields[idx])
				}
			} $else $if field.unaliased_typ is f32 {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = f32(extract_f64(s, fields[idx]))
				}
			} $else $if field.unaliased_typ is bool {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = extract_bool(s, fields[idx])
				}
			} $else $if field.unaliased_typ is []string {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = extract_string_array(s, fields[idx])
				}
			} $else $if field.unaliased_typ is []int {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = extract_int_array(s, fields[idx])
				}
			} $else $if field.unaliased_typ is []f64 {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = extract_f64_array(s, fields[idx])
				}
			} $else $if field.unaliased_typ is map[string]string {
				idx := find_field(s, fields, json_name)
				if idx >= 0 {
					result.$(field.name) = extract_map(s, fields[idx])
				}
			} $else $if field.is_struct {
				idx := find_field(s, fields, json_name)
				if idx >= 0 && fields[idx].kind == .object_ {
					sub := extract_substring(s, fields[idx])
					decode_nested(sub, mut result.$(field.name))
				}
			}
		}
	} $else {
		return error('fastjson.decode only supports struct types')
	}
	return result
}

// extract_int_array extracts a []int from a JSON array.
fn extract_int_array(json string, f FieldPos) []int {
	if f.kind != .array_ {
		return []
	}
	mut result := []int{}
	buf := json.str
	len := json.len
	mut pos := f.val_start + 1
	end := f.val_start + f.val_len

	for pos < end {
		pos = unsafe { C.simd_skip_ws(buf, len, pos) }
		if pos >= end {
			break
		}
		if unsafe { buf[pos] } == `]` {
			break
		}
		if unsafe { buf[pos] } == `,` {
			pos++
			continue
		}
		mut consumed := 0
		val := unsafe { C.fast_parse_int(buf + pos, end - pos, &consumed) }
		result << int(val)
		pos += consumed
	}
	return result
}

// extract_f64_array extracts a []f64 from a JSON array.
fn extract_f64_array(json string, f FieldPos) []f64 {
	if f.kind != .array_ {
		return []
	}
	mut result := []f64{}
	buf := json.str
	len := json.len
	mut pos := f.val_start + 1
	end := f.val_start + f.val_len

	for pos < end {
		pos = unsafe { C.simd_skip_ws(buf, len, pos) }
		if pos >= end {
			break
		}
		if unsafe { buf[pos] } == `]` {
			break
		}
		if unsafe { buf[pos] } == `,` {
			pos++
			continue
		}
		mut consumed := 0
		val := unsafe { C.fast_parse_f64(buf + pos, end - pos, &consumed) }
		result << val
		pos += consumed
	}
	return result
}