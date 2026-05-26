module main

import fastjson
import time

fn main() {
	// Test accuracy first
	test_vals := [1.0, 0.0, 3.14, 2.718281828, -42.5, 123.456, 0.001, 999999.999999,
		1.5e10, 3.0e-5, 1.23456789012345, -0.0001, 1e20, 1e-20,
		1.7976931348623157e308, 2.2250738585072014e-308]

	println('f64 encode accuracy test:')
	for v in test_vals {
		schubfach_str := fastjson.f64_to_str(v)
		v_str := v.str()
		println('  schubfach=${schubfach_str:30s} v.str()=${v_str}')
	}
	println('')

	// Benchmark: fastjson.f64_to_str vs V .str()
	iter := 200000
	mut sink := 0

	for run_num in 1 .. 4 {
		// V .str() benchmark
		mut sw1 := time.new_stopwatch()
		mut s1 := ''
		for i in 0 .. iter {
			v := test_vals[i % test_vals.len]
			s1 = v.str()
			sink += s1.len
		}
		e1 := sw1.elapsed().nanoseconds()
		ns1 := int(e1 / iter)

		// fastjson.f64_to_str (Schubfach) benchmark
		mut sw2 := time.new_stopwatch()
		mut s2 := ''
		for i in 0 .. iter {
			v := test_vals[i % test_vals.len]
			s2 = fastjson.f64_to_str(v)
			sink += s2.len
		}
		e2 := sw2.elapsed().nanoseconds()
		ns2 := int(e2 / iter)

		println('--- Run ${run_num} ---')
		println('  V .str()       ${ns1:6d} ns/op')
		println('  Schubfach      ${ns2:6d} ns/op')
		if ns2 > 0 {
			println('  ratio          ${ns1 / ns2}x')
		}
		println('')
	}
	println('sink=${sink}')
}