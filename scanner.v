module fastjson

pub enum ValueKind {
	null_
	bool_
	int_
	float_
	string_
	array_
	object_
}

// FieldPos records position info for a key-value pair in a JSON object.
pub struct FieldPos {
pub:
	key_start int
	key_len   int
	val_start int
	val_len   int
	kind      ValueKind
}

// scan_object scans a JSON object string and returns field positions.
// Single SIMD-accelerated pass — no string allocations.
pub fn scan_object(json string) []FieldPos {
	mut fields := []FieldPos{cap: 16}
	buf := json.str
	len := json.len
	mut pos := 0

	pos = unsafe { C.simd_skip_ws(buf, len, pos) }
	if pos >= len || unsafe { buf[pos] } != `{` {
		return fields
	}
	pos++ // skip {

	for pos < len {
		pos = unsafe { C.simd_skip_ws(buf, len, pos) }
		if pos >= len {
			break
		}
		if unsafe { buf[pos] } == `}` {
			break
		}
		if unsafe { buf[pos] } == `,` {
			pos++
			pos = unsafe { C.simd_skip_ws(buf, len, pos) }
			if pos >= len {
				break
			}
		}

		// Parse key
		if unsafe { buf[pos] } != `"` {
			pos++
			continue
		}
		mut key_start := 0
		mut key_len := 0
		pos = unsafe { C.scan_json_string(buf, len, pos, &key_start, &key_len) }

		// Skip to colon
		colon := unsafe { C.simd_find_char(buf + pos, len - pos, u8(`:`)) }
		if colon < 0 {
			break
		}
		pos += colon + 1
		pos = unsafe { C.simd_skip_ws(buf, len, pos) }
		if pos >= len {
			break
		}

		// Determine value kind and position
		val_start := pos
		ch := unsafe { buf[pos] }
		mut kind := ValueKind.null_
		match ch {
			`"` {
				kind = .string_
				mut cs := 0
				mut cl := 0
				pos = unsafe { C.scan_json_string(buf, len, pos, &cs, &cl) }
			}
			`{` {
				kind = .object_
				pos = unsafe { C.skip_json_value(buf, len, pos) }
			}
			`[` {
				kind = .array_
				pos = unsafe { C.skip_json_value(buf, len, pos) }
			}
			`t`, `f` {
				kind = .bool_
				pos = unsafe { C.skip_json_value(buf, len, pos) }
			}
			`n` {
				kind = .null_
				pos = unsafe { C.skip_json_value(buf, len, pos) }
			}
			else {
				// Number: check for decimal point
				mut dot_pos := unsafe { C.simd_find_char(buf + pos, len - pos, u8(`.`)) }
				if dot_pos >= 0 {
					// Check if dot is actually part of this number (not past a comma/brace)
					dot_abs := pos + dot_pos
					comma := unsafe { C.simd_find_char(buf + pos, len - pos, u8(`,`)) }
					brace := unsafe { C.simd_find_char(buf + pos, len - pos, u8(`}`)) }
					mut end_ch := comma
					if brace >= 0 && (end_ch < 0 || brace < end_ch) {
						end_ch = brace
					}
					if end_ch >= 0 && dot_abs < pos + end_ch {
						kind = .float_
					} else {
						kind = .int_
					}
				} else {
					kind = .int_
				}
				pos = unsafe { C.skip_json_value(buf, len, pos) }
			}
		}
		val_len := pos - val_start

		fields << FieldPos{
			key_start: key_start
			key_len: key_len
			val_start: val_start
			val_len: val_len
			kind: kind
		}
	}

	return fields
}

// find_field finds a field by key name in scanned fields. Returns index or -1.
@[direct_array_access]
pub fn find_field(json string, fields []FieldPos, key string) int {
	for i, f in fields {
		if f.key_len == key.len {
			if unsafe { C.simd_memcmp(json.str + f.key_start, key.str, key.len) == 0 } {
				return i
			}
		}
	}
	return -1
}

// extract_string extracts a JSON string value (zero-copy slice).
@[direct_array_access]
pub fn extract_string(json string, f FieldPos) string {
	if f.kind != .string_ || f.val_len < 2 {
		return ''
	}
	// val_start points to opening ", val_start + val_len is past closing "
	// Content is between the quotes
	return unsafe { tos(json.str + f.val_start + 1, f.val_len - 2) }
}

// extract_int extracts an integer value.
@[direct_array_access]
pub fn extract_int(json string, f FieldPos) int {
	if f.kind != .int_ {
		return 0
	}
	mut consumed := 0
	val := unsafe { C.fast_parse_int(json.str + f.val_start, f.val_len, &consumed) }
	return int(val)
}

// extract_i64 extracts an i64 value.
@[direct_array_access]
pub fn extract_i64(json string, f FieldPos) i64 {
	if f.kind != .int_ {
		return 0
	}
	mut consumed := 0
	return unsafe { C.fast_parse_int(json.str + f.val_start, f.val_len, &consumed) }
}

// extract_f64 extracts a float value.
@[direct_array_access]
pub fn extract_f64(json string, f FieldPos) f64 {
	if f.kind != .float_ && f.kind != .int_ {
		return 0.0
	}
	mut consumed := 0
	return unsafe { C.fast_parse_f64(json.str + f.val_start, f.val_len, &consumed) }
}

// extract_bool extracts a boolean value.
@[direct_array_access]
pub fn extract_bool(json string, f FieldPos) bool {
	if f.kind != .bool_ {
		return false
	}
	return unsafe { json.str[f.val_start] } == `t`
}

// extract_string_array extracts a []string from a JSON array.
pub fn extract_string_array(json string, f FieldPos) []string {
	if f.kind != .array_ {
		return []
	}
	mut result := []string{}
	buf := json.str
	len := json.len
	mut pos := f.val_start + 1 // skip [
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
		if unsafe { buf[pos] } == `"` {
			mut cs := 0
			mut cl := 0
			pos = unsafe { C.scan_json_string(buf, len, pos, &cs, &cl) }
			result << unsafe { tos(buf + cs, cl) }
		} else {
			pos = unsafe { C.skip_json_value(buf, len, pos) }
		}
	}
	return result
}

// extract_map extracts a map[string]string from a JSON object.
pub fn extract_map(json string, f FieldPos) map[string]string {
	if f.kind != .object_ {
		return {}
	}
	mut result := map[string]string{}
	buf := json.str
	len_ := json.len
	mut pos := f.val_start + 1 // skip {
	end := f.val_start + f.val_len

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
		// Parse key
		if unsafe { buf[pos] } != `"` {
			pos++
			continue
		}
		mut ks := 0
		mut kl := 0
		pos = unsafe { C.scan_json_string(buf, len_, pos, &ks, &kl) }
		key := unsafe { tos(buf + ks, kl) }

		// Skip colon
		colon := unsafe { C.simd_find_char(buf + pos, end - pos, u8(`:`)) }
		if colon < 0 {
			break
		}
		pos += colon + 1
		pos = unsafe { C.simd_skip_ws(buf, len_, pos) }

		// Parse value
		if pos < end && unsafe { buf[pos] } == `"` {
			mut vs := 0
			mut vl := 0
			pos = unsafe { C.scan_json_string(buf, len_, pos, &vs, &vl) }
			result[key] = unsafe { tos(buf + vs, vl) }
		} else {
			pos = unsafe { C.skip_json_value(buf, len_, pos) }
		}
	}
	return result
}

// extract_substring returns the raw JSON value as a string slice.
@[direct_array_access]
pub fn extract_substring(json string, f FieldPos) string {
	return unsafe { tos(json.str + f.val_start, f.val_len) }
}
