import fastjson

// Direct float parsing benchmark
struct FloatTest {
	value f64
}

fn main() {
	values := [
		'1.0',
		'0.0',
		'3.14',
		'2.718281828',
		'-42.5',
		'123.456',
		'0.001',
		'999999.999999',
		'1.5e10',
		'3.0e-5',
		'1.23456789012345',
		'-0.0001',
		'1e20',
		'1e-20',
		'1.7976931348623157e308',
		'2.2250738585072014e-308',
	]

	println('Float decode accuracy test:')
	for v in values {
		result := fastjson.decode[FloatTest]('{"value":${v}}') or { panic(err) }
		println('  ${v:-30s} => ${result.value}')
	}

	// Benchmark: encode floats, then decode them
	pool_size := 256
	iterations := 100000

	mut pool := []string{cap: pool_size}
	for i := 0; i < pool_size; i++ {
		val := f64(i % 1000) * 3.14159 + 0.5
		pool << '{"value":${val}}'
	}

	mut sink := f64(0)
	for i := 0; i < iterations; i++ {
		s := pool[i % pool_size]
		// manual timing to isolate float parse
		result := fastjson.decode[FloatTest](s) or { panic(err) }
		sink += result.value
	}

	println('\nFloat decode benchmark: ${iterations} iterations on ${pool_size} pool')
	println('  (sink = ${sink})')
}
