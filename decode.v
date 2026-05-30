module fastjson

// decode_nested recursively decodes a nested struct field from a JSON substring.
fn decode_nested[T](s string, mut val T) {
	$if T is $struct {
		buf := s.str
		len_ := s.len
		mut pair := ScanPair{}
		mut pos := unsafe { C.fj_scan_open(buf, len_) }
		if pos < 0 {
			return
		}
		for {
			pos = unsafe { C.fj_scan_next(buf, len_, pos, &pair) }
			if pos < 0 {
				break
			}
			$for field in T.fields {
				if pair.key_len == field.name.len && unsafe { C.simd_memcmp(buf + pair.key_start, field.name.str, pair.key_len) == 0 } {
					$if field.unaliased_typ is string {
						val.$(field.name) = extract_string_from(s, pair.val_start, pair.val_len, pair.kind)
					} $else $if field.unaliased_typ is int {
						val.$(field.name) = extract_int_from(buf, pair.val_start, pair.val_len, pair.kind)
					} $else $if field.unaliased_typ is i64 {
						val.$(field.name) = extract_i64_from(buf, pair.val_start, pair.val_len, pair.kind)
					} $else $if field.unaliased_typ is f64 {
						val.$(field.name) = extract_f64_from(buf, pair.val_start, pair.val_len, pair.kind)
					} $else $if field.unaliased_typ is bool {
						val.$(field.name) = extract_bool_from(buf, pair.val_start, pair.kind)
					} $else $if field.is_struct {
						if pair.kind == 6 {
							// Clone: substring must own its data for autofree safety.
								// Zero-copy tos() slice would be freed by autofree, corrupting memory.
								sub := unsafe { tos(buf + pair.val_start, pair.val_len) }.clone()
							decode_nested(sub, mut val.$(field.name))
						}
					}
				}
			}
		}
	}
}

// decode parses a JSON string into type T using zero-allocation scan iterator.
// Supports structs with fields of type: string, int, i64, f64, bool, []string, []int, []f64, map[string]string, and nested structs.
pub fn decode[T](s string) !T {
	mut result := T{}
	$if T is $struct {
		buf := s.str
		len_ := s.len
		mut pair := ScanPair{}
		mut pos := unsafe { C.fj_scan_open(buf, len_) }
		if pos < 0 {
			return error('fastjson: invalid JSON: expected opening brace')
		}
		for {
			pos = unsafe { C.fj_scan_next(buf, len_, pos, &pair) }
			if pos < 0 {
				break
			}
			$for field in T.fields {
				if pair.key_len == field.name.len && unsafe { C.simd_memcmp(buf + pair.key_start, field.name.str, pair.key_len) == 0 } {
					$if field.unaliased_typ is string {
						result.$(field.name) = extract_string_from(s, pair.val_start, pair.val_len, pair.kind)
					} $else $if field.unaliased_typ is int {
						result.$(field.name) = extract_int_from(buf, pair.val_start, pair.val_len, pair.kind)
					} $else $if field.unaliased_typ is i64 {
						result.$(field.name) = extract_i64_from(buf, pair.val_start, pair.val_len, pair.kind)
					} $else $if field.unaliased_typ is i32 {
						result.$(field.name) = i32(extract_int_from(buf, pair.val_start, pair.val_len, pair.kind))
					} $else $if field.unaliased_typ is i16 {
						result.$(field.name) = i16(extract_int_from(buf, pair.val_start, pair.val_len, pair.kind))
					} $else $if field.unaliased_typ is i8 {
						result.$(field.name) = i8(extract_int_from(buf, pair.val_start, pair.val_len, pair.kind))
					} $else $if field.unaliased_typ is u64 {
						result.$(field.name) = u64(extract_i64_from(buf, pair.val_start, pair.val_len, pair.kind))
					} $else $if field.unaliased_typ is u32 {
						result.$(field.name) = u32(extract_int_from(buf, pair.val_start, pair.val_len, pair.kind))
					} $else $if field.unaliased_typ is u16 {
						result.$(field.name) = u16(extract_int_from(buf, pair.val_start, pair.val_len, pair.kind))
					} $else $if field.unaliased_typ is u8 {
						result.$(field.name) = u8(extract_int_from(buf, pair.val_start, pair.val_len, pair.kind))
					} $else $if field.unaliased_typ is f64 {
						result.$(field.name) = extract_f64_from(buf, pair.val_start, pair.val_len, pair.kind)
					} $else $if field.unaliased_typ is f32 {
						result.$(field.name) = f32(extract_f64_from(buf, pair.val_start, pair.val_len, pair.kind))
					} $else $if field.unaliased_typ is bool {
						result.$(field.name) = extract_bool_from(buf, pair.val_start, pair.kind)
					} $else $if field.unaliased_typ is []string {
						result.$(field.name) = extract_string_array_from(s, pair.val_start, pair.val_len, pair.kind)
					} $else $if field.unaliased_typ is []int {
						result.$(field.name) = extract_int_array_from(s, pair.val_start, pair.val_len, pair.kind)
					} $else $if field.unaliased_typ is []f64 {
						result.$(field.name) = extract_f64_array_from(s, pair.val_start, pair.val_len, pair.kind)
					} $else $if field.unaliased_typ is map[string]string {
						result.$(field.name) = extract_map_from(s, pair.val_start, pair.val_len, pair.kind)
					} $else $if field.is_struct {
						if pair.kind == 6 {
							// Clone: substring must own its data for autofree safety.
								// Zero-copy tos() slice would be freed by autofree, corrupting memory.
								sub := unsafe { tos(buf + pair.val_start, pair.val_len) }.clone()
							decode_nested(sub, mut result.$(field.name))
						}
					}
				}
			}
		}
	} $else {
		return error('fastjson.decode only supports struct types')
	}
	return result
}

// extract_string_from extracts a JSON string value (zero-copy slice).
fn extract_string_from(json string, val_start int, val_len int, kind int) string {
	if kind != 4 || val_len < 2 {
		return ''
	}
	return unsafe { tos(json.str + val_start + 1, val_len - 2) }
}

// extract_int_from extracts an integer value directly from buffer.
fn extract_int_from(buf &u8, val_start int, val_len int, kind int) int {
	if kind != 2 {
		return 0
	}
	mut consumed := 0
	val := unsafe { C.fast_parse_int(buf + val_start, val_len, &consumed) }
	return int(val)
}

// extract_i64_from extracts an i64 value directly from buffer.
fn extract_i64_from(buf &u8, val_start int, val_len int, kind int) i64 {
	if kind != 2 {
		return 0
	}
	mut consumed := 0
	return unsafe { C.fast_parse_int(buf + val_start, val_len, &consumed) }
}

// extract_f64_from extracts a float value directly from buffer.
fn extract_f64_from(buf &u8, val_start int, val_len int, kind int) f64 {
	if kind != 3 && kind != 2 {
		return 0.0
	}
	mut consumed := 0
	return unsafe { C.fast_parse_f64(buf + val_start, val_len, &consumed) }
}

// extract_bool_from extracts a boolean value directly from buffer.
fn extract_bool_from(buf &u8, val_start int, kind int) bool {
	if kind != 1 {
		return false
	}
	return unsafe { buf[val_start] } == `t`
}

// extract_string_array_from extracts a []string from a JSON array.
fn extract_string_array_from(json string, val_start int, val_len int, kind int) []string {
	if kind != 5 {
		return []
	}
	mut result := []string{}
	buf := json.str
	len_ := json.len
	mut pos := val_start + 1
	end := val_start + val_len

	for pos < end {
		pos = unsafe { C.simd_skip_ws(buf, len_, pos) }
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
		if unsafe { buf[pos] } == `"` {
			mut cs := 0
			mut cl := 0
			pos = unsafe { C.scan_json_string(buf, len_, pos, &cs, &cl) }
			// Clone: array elements must own their data for autofree safety.
			// Zero-copy tos() slices would be freed by autofree, corrupting the array.
			result << unsafe { tos(buf + cs, cl) }.clone()
		} else {
			pos = unsafe { C.skip_json_value(buf, len_, pos) }
		}
	}
	return result
}

// extract_int_array_from extracts a []int from a JSON array.
fn extract_int_array_from(json string, val_start int, val_len int, kind int) []int {
	if kind != 5 {
		return []
	}
	mut result := []int{}
	buf := json.str
	len_ := json.len
	mut pos := val_start + 1
	end := val_start + val_len

	for pos < end {
		pos = unsafe { C.simd_skip_ws(buf, len_, pos) }
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

// extract_f64_array_from extracts a []f64 from a JSON array.
fn extract_f64_array_from(json string, val_start int, val_len int, kind int) []f64 {
	if kind != 5 {
		return []
	}
	mut result := []f64{}
	buf := json.str
	len_ := json.len
	mut pos := val_start + 1
	end := val_start + val_len

	for pos < end {
		pos = unsafe { C.simd_skip_ws(buf, len_, pos) }
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

// extract_map_from extracts a map[string]string from a JSON object.
fn extract_map_from(json string, val_start int, val_len int, kind int) map[string]string {
	if kind != 6 {
		return {}
	}
	mut result := map[string]string{}
	buf := json.str
	len_ := json.len
	mut pos := val_start + 1
	end := val_start + val_len

	for pos < end {
		pos = unsafe { C.simd_skip_ws(buf, len_, pos) }
		if pos >= end {
			break
		}
		if unsafe { buf[pos] } == `}` {
			break
		}
		if unsafe { buf[pos] } == `,` {
			pos++
			continue
		}
		if unsafe { buf[pos] } != `"` {
			pos++
			continue
		}
		mut ks := 0
		mut kl := 0
		pos = unsafe { C.scan_json_string(buf, len_, pos, &ks, &kl) }
		// Clone key: map keys must own their data for autofree safety.
		key := unsafe { tos(buf + ks, kl) }.clone()

		colon := unsafe { C.simd_find_char(buf + pos, end - pos, u8(`:`)) }
		if colon < 0 {
			break
		}
		pos += colon + 1
		pos = unsafe { C.simd_skip_ws(buf, len_, pos) }

		if pos < end && unsafe { buf[pos] } == `"` {
			mut vs := 0
			mut vl := 0
			pos = unsafe { C.scan_json_string(buf, len_, pos, &vs, &vl) }
			// Clone value: map values must own their data for autofree safety.
			result[key] = unsafe { tos(buf + vs, vl) }.clone()
		} else {
			pos = unsafe { C.skip_json_value(buf, len_, pos) }
		}
	}
	return result
}