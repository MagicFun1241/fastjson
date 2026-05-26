import fastjson
import math

// ============================================================
// Struct types for testing
// ============================================================

struct FloatVal {
	value f64
}

struct IntVal {
	value int
}

struct I64Val {
	value i64
}

struct BoolVal {
	value bool
}

struct StringVal {
	value string
}

struct NestedInner {
	x f64
	y int
}

struct NestedOuter {
	name  string
	inner NestedInner
}

struct ArrayVal {
	items []string
}

struct IntArrayVal {
	numbers []int
}

struct FloatArrayVal {
	scores []f64
}

struct MapVal {
	meta map[string]string
}

struct AllTypes {
	name    string
	age     int
	score   f64
	active  bool
	tags    []string
	meta    map[string]string
	profile NestedInner
}

struct NegativeVal {
	ival int
	fval f64
}

// ============================================================
// Float decode tests (adapted from sonic/Go atof_test.go)
// ============================================================

struct FloatTestCase {
	input  string
	expect f64
}

fn test_float_decode() {
	cases := [
		FloatTestCase{'1', 1.0},
		FloatTestCase{'1e23', 1e23},
		FloatTestCase{'1E23', 1e23},
		FloatTestCase{'123456700', 123456700.0},
		FloatTestCase{'-1', -1.0},
		FloatTestCase{'-0.1', -0.1},
		// zeros
		FloatTestCase{'0', 0.0},
		FloatTestCase{'0e0', 0.0},
		// scientific notation
		FloatTestCase{'1e-20', 1e-20},
		FloatTestCase{'625e-3', 0.625},
		// large numbers
		FloatTestCase{'1.7976931348623157e308', 1.7976931348623157e308},
		FloatTestCase{'-1.7976931348623157e308', -1.7976931348623157e308},
		// denormalized
		FloatTestCase{'1e-305', 1e-305},
		FloatTestCase{'1e-308', 1e-308},
		FloatTestCase{'5e-324', 5e-324},
		// small decimals
		FloatTestCase{'0.001', 0.001},
		FloatTestCase{'3.14', 3.14},
		FloatTestCase{'2.718281828', 2.718281828},
		FloatTestCase{'999999.999999', 999999.999999},
		// integers parsed as float
		FloatTestCase{'42', 42.0},
		FloatTestCase{'-42', -42.0},
		// negative zero
		FloatTestCase{'-0', -0.0},
	]

	mut passed := 0
	mut failed := 0
	for i, tc in cases {
		json_str := '{"value":${tc.input}}'
		result := fastjson.decode[FloatVal](json_str) or {
			eprintln('  FAIL [$i] decode error for input="${tc.input}": $err')
			failed++
			continue
		}
		// Check NaN/Inf/zero specially, otherwise relative check
		if math.is_nan(tc.expect) {
			if !math.is_nan(result.value) {
				eprintln('  FAIL [$i] expected NaN, got ${result.value} (input="${tc.input}")')
				failed++
			} else {
				passed++
			}
		} else if math.is_inf(tc.expect, 0) {
			if !math.is_inf(result.value, 0) || math.signbit(result.value) != math.signbit(tc.expect) {
				eprintln('  FAIL [$i] expected ${tc.expect}, got ${result.value} (input="${tc.input}")')
				failed++
			} else {
				passed++
			}
		} else if tc.expect == 0.0 {
			if result.value != 0.0 || math.signbit(result.value) != math.signbit(tc.expect) {
				eprintln('  FAIL [$i] expected ${tc.expect}, got ${result.value} (input="${tc.input}")')
				failed++
			} else {
				passed++
			}
		} else {
			// Relative tolerance: 1e-15 for normal numbers
			rel_diff := math.abs(result.value - tc.expect) / math.abs(tc.expect)
			if rel_diff > 1e-15 && result.value != tc.expect {
				eprintln('  FAIL [$i] expected ${tc.expect}, got ${result.value} (rel_diff=${rel_diff:.2e}, input="${tc.input}")')
				failed++
			} else {
				passed++
			}
		}
	}
	println('Float decode: $passed passed, $failed failed')
}

// ============================================================
// Integer decode tests
// ============================================================

fn test_int_decode() {
	cases := ['0', '1', '-1', '100', '-100', '2147483647', '-2147483648', '999999999']
	mut passed := 0
	mut failed := 0
	for input in cases {
		json_str := '{"value":${input}}'
		result := fastjson.decode[IntVal](json_str) or {
			eprintln('  FAIL decode error for input="${input}": $err')
			failed++
			continue
		}
		expected := input.int()
		if result.value != expected {
			eprintln('  FAIL expected ${expected}, got ${result.value} (input="${input}")')
			failed++
		} else {
			passed++
		}
	}
	println('Int decode: $passed passed, $failed failed')
}

// ============================================================
// Bool decode tests
// ============================================================

fn test_bool_decode() {
	cases := ['true', 'false']
	mut passed := 0
	mut failed := 0
	for input in cases {
		result := fastjson.decode[BoolVal]('{"value":${input}}') or {
			eprintln('  FAIL decode error for input="${input}": $err')
			failed++
			continue
		}
		expected := input == 'true'
		if result.value != expected {
			eprintln('  FAIL expected ${expected}, got ${result.value}')
			failed++
		} else {
			passed++
		}
	}
	println('Bool decode: $passed passed, $failed failed')
}

// ============================================================
// String decode tests
// ============================================================

fn test_string_decode() {
	cases := [
		'', 'hello', 'hello world', 'with/slash', 'unicode: éè',
	]
	mut passed := 0
	mut failed := 0
	for i, input in cases {
		// Escape the string for JSON
		escaped := input.replace('\\', '\\\\').replace('"', '\\"')
		json_str := '{"value":"${escaped}"}'
		result := fastjson.decode[StringVal](json_str) or {
			eprintln('  FAIL [$i] decode error for input="${input}": $err')
			failed++
			continue
		}
		if result.value != input {
			eprintln('  FAIL [$i] expected "${input}", got "${result.value}"')
			failed++
		} else {
			passed++
		}
	}
	println('String decode: $passed passed, $failed failed')
}

// ============================================================
// Null handling tests
// ============================================================

fn test_null_handling() {
	mut passed := 0
	mut failed := 0

	// Null values should leave defaults
	r1 := fastjson.decode[AllTypes]('{"name":null,"age":null,"score":null,"active":null}') or {
		eprintln('  FAIL decode null: $err')
		failed++
		return
	}
	if r1.name != '' { eprintln('  FAIL null string: expected "", got "${r1.name}"'); failed++ } else { passed++ }
	if r1.age != 0 { eprintln('  FAIL null int: expected 0, got ${r1.age}'); failed++ } else { passed++ }
	if r1.score != 0.0 { eprintln('  FAIL null f64: expected 0.0, got ${r1.score}'); failed++ } else { passed++ }
	if r1.active != false { eprintln('  FAIL null bool: expected false'); failed++ } else { passed++ }

	println('Null handling: $passed passed, $failed failed')
}

// ============================================================
// Encode/decode roundtrip tests
// ============================================================

fn test_roundtrip_simple() {
	mut passed := 0
	mut failed := 0

	// String roundtrips
	for i, inp in [
		'hello',
		'',
		'with spaces',
		'with/slash',
	] {
		orig := StringVal{inp}
		encoded := fastjson.encode(orig)
		decoded := fastjson.decode[StringVal](encoded) or {
			eprintln('  FAIL [$i] string decode error: $err')
			failed++
			continue
		}
		if decoded.value != orig.value {
			eprintln('  FAIL [$i] roundtrip string: "${orig.value}" -> "${encoded}" -> "${decoded.value}"')
			failed++
		} else {
			passed++
		}
	}
	// Int roundtrips
	for i, inp in [0, 42, -1, 2147483647, -2147483648] {
		orig := IntVal{inp}
		encoded := fastjson.encode(orig)
		decoded := fastjson.decode[IntVal](encoded) or {
			eprintln('  FAIL [$i] int decode error: $err')
			failed++
			continue
		}
		if decoded.value != orig.value {
			eprintln('  FAIL [$i] roundtrip int: ${orig.value} -> ${encoded} -> ${decoded.value}')
			failed++
		} else {
			passed++
		}
	}
	// Float roundtrips
	for i, inp in [0.0, 3.14, -0.5, 1e10, 1e-10] {
		orig := FloatVal{inp}
		encoded := fastjson.encode(orig)
		decoded := fastjson.decode[FloatVal](encoded) or {
			eprintln('  FAIL [$i] float decode error: $err')
			failed++
			continue
		}
		if math.is_nan(orig.value) && math.is_nan(decoded.value) {
			passed++
		} else if orig.value == decoded.value {
			passed++
		} else if math.abs(decoded.value - orig.value) / math.abs(orig.value) < 1e-15 {
			passed++
		} else {
			eprintln('  FAIL [$i] roundtrip float: ${orig.value} -> ${encoded} -> ${decoded.value}')
			failed++
		}
	}
	// Bool roundtrips
	for i, inp in [true, false] {
		orig := BoolVal{inp}
		encoded := fastjson.encode(orig)
		decoded := fastjson.decode[BoolVal](encoded) or {
			eprintln('  FAIL [$i] bool decode error: $err')
			failed++
			continue
		}
		if decoded.value != orig.value {
			eprintln('  FAIL [$i] roundtrip bool: ${orig.value} -> ${decoded.value}')
			failed++
		} else {
			passed++
		}
	}
	println('Roundtrip simple: $passed passed, $failed failed')
}

fn test_roundtrip_complex() {
	original := AllTypes{
		name: 'Alice'
		age: 30
		score: 95.5
		active: true
		tags: ['dev', 'go']
		meta: {'department': 'engineering', 'level': 'senior'}
		profile: NestedInner{x: 1.5, y: 42}
	}

	encoded := fastjson.encode(original)
	decoded := fastjson.decode[AllTypes](encoded) or {
		eprintln('  FAIL complex roundtrip decode: $err')
		return
	}

	mut passed := 0
	mut failed := 0
	if decoded.name != original.name { eprintln('  FAIL name'); failed++ } else { passed++ }
	if decoded.age != original.age { eprintln('  FAIL age'); failed++ } else { passed++ }
	if decoded.score != original.score { eprintln('  FAIL score'); failed++ } else { passed++ }
	if decoded.active != original.active { eprintln('  FAIL active'); failed++ } else { passed++ }
	if decoded.tags.len != original.tags.len { eprintln('  FAIL tags len'); failed++ } else { passed++
		if decoded.tags[0] != original.tags[0] { eprintln('  FAIL tag[0]'); failed++ } else { passed++ }
		if decoded.tags[1] != original.tags[1] { eprintln('  FAIL tag[1]'); failed++ } else { passed++ }
	}
	if decoded.meta['department'] != original.meta['department'] { eprintln('  FAIL meta dept'); failed++ } else { passed++ }
	if decoded.meta['level'] != original.meta['level'] { eprintln('  FAIL meta level'); failed++ } else { passed++ }
	if decoded.profile.x != original.profile.x { eprintln('  FAIL profile.x'); failed++ } else { passed++ }
	if decoded.profile.y != original.profile.y { eprintln('  FAIL profile.y'); failed++ } else { passed++ }

	println('Roundtrip complex: $passed passed, $failed failed')
}

// ============================================================
// Negative number edge cases
// ============================================================

fn test_negative_numbers() {
	mut passed := 0
	mut failed := 0

	cases := [
		'{"ival":-5,"fval":-3.14}',
		'{"ival":-2147483648,"fval":-0.0}',
		'{"ival":0,"fval":-999999.999999}',
	]

	for i, json_str in cases {
		result := fastjson.decode[NegativeVal](json_str) or {
			eprintln('  FAIL [$i] decode error: $err')
			failed++
			continue
		}
		passed++
	}

	println('Negative numbers: $passed passed, $failed failed')
}

// ============================================================
// Array decode tests
// ============================================================

fn test_array_decode() {
	mut passed := 0
	mut failed := 0

	// String array
	r1 := fastjson.decode[ArrayVal]('{"items":["hello","world","test"]}') or {
		eprintln('  FAIL string array decode: $err')
		failed++
		return
	}
	if r1.items.len != 3 { eprintln('  FAIL string array len'); failed++ } else { passed++ }
	if r1.items[0] != 'hello' { eprintln('  FAIL string[0]'); failed++ } else { passed++ }
	if r1.items[1] != 'world' { eprintln('  FAIL string[1]'); failed++ } else { passed++ }
	if r1.items[2] != 'test' { eprintln('  FAIL string[2]'); failed++ } else { passed++ }

	// Int array
	r2 := fastjson.decode[IntArrayVal]('{"numbers":[1,2,3,42,-1]}') or {
		eprintln('  FAIL int array decode: $err')
		failed++
		return
	}
	if r2.numbers.len != 5 { eprintln('  FAIL int array len'); failed++ } else { passed++ }
	if r2.numbers[0] != 1 { eprintln('  FAIL int[0]'); failed++ } else { passed++ }
	if r2.numbers[3] != 42 { eprintln('  FAIL int[3]'); failed++ } else { passed++ }
	if r2.numbers[4] != -1 { eprintln('  FAIL int[4]'); failed++ } else { passed++ }

	// Float array
	r3 := fastjson.decode[FloatArrayVal]('{"scores":[1.5,2.7,-0.3,100.0]}') or {
		eprintln('  FAIL float array decode: $err')
		failed++
		return
	}
	if r3.scores.len != 4 { eprintln('  FAIL float array len'); failed++ } else { passed++ }
	if r3.scores[0] != 1.5 { eprintln('  FAIL float[0]'); failed++ } else { passed++ }
	if r3.scores[2] != -0.3 { eprintln('  FAIL float[2]'); failed++ } else { passed++ }

	// Empty array
	r4 := fastjson.decode[ArrayVal]('{"items":[]}') or {
		eprintln('  FAIL empty array decode: $err')
		failed++
		return
	}
	if r4.items.len != 0 { eprintln('  FAIL empty array len'); failed++ } else { passed++ }

	println('Array decode: $passed passed, $failed failed')
}

// ============================================================
// Map decode tests
// ============================================================

fn test_map_decode() {
	mut passed := 0
	mut failed := 0

	r := fastjson.decode[MapVal]('{"meta":{"key1":"val1","key2":"val2"}}') or {
		eprintln('  FAIL map decode: $err')
		failed++
		return
	}
	if r.meta.len != 2 { eprintln('  FAIL map len'); failed++ } else { passed++ }
	if r.meta['key1'] != 'val1' { eprintln('  FAIL map[key1]'); failed++ } else { passed++ }
	if r.meta['key2'] != 'val2' { eprintln('  FAIL map[key2]'); failed++ } else { passed++ }

	// Empty map
	r2 := fastjson.decode[MapVal]('{"meta":{}}') or {
		eprintln('  FAIL empty map decode: $err')
		failed++
		return
	}
	if r2.meta.len != 0 { eprintln('  FAIL empty map len'); failed++ } else { passed++ }

	println('Map decode: $passed passed, $failed failed')
}

fn main() {
	test_float_decode()
	test_int_decode()
	test_bool_decode()
	test_string_decode()
	test_null_handling()
	test_roundtrip_simple()
	test_roundtrip_complex()
	test_negative_numbers()
	test_array_decode()
	test_map_decode()
}