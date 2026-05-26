import time
import fastjson

struct FloatTest {
	value f64
}

fn bench_float_decode(n int, pool []string, pool_size int) time.Duration {
	mut sw := time.new_stopwatch()
	sw.start()
	mut sink := f64(0)
	for i := 0; i < n; i++ {
		result := fastjson.decode[FloatTest](pool[i % pool_size]) or { panic(err) }
		sink += result.value
	}
	sw.stop()
	println('  sink=${sink}')
	return sw.elapsed()
}

fn main() {
	pool_size := 256
	iterations := 500000

	// Generate diverse float values
	mut pool := []string{cap: pool_size}
	for i := 0; i < pool_size; i++ {
		if i % 4 == 0 {
			pool << '{"value":${f64(i % 1000) * 3.14159 + 0.5}}'
		} else if i % 4 == 1 {
			pool << '{"value":${f64(i % 100) * 0.001}}'
		} else if i % 4 == 2 {
			pool << '{"value":${f64(i % 50 + 1) * 999.99}}'
		} else {
			val := f64(i % 200) * 0.00001 + 0.00001
			pool << '{"value":${val}}'
		}
	}

	println('Float decode benchmark: ${iterations} iterations, ${pool_size} pool')
	println('==========================================')

	bench := fn(name string, d time.Duration, n int) {
		ns_per_op := d.nanoseconds() / n
		ops_per_sec := f64(n) / d.seconds()
		println('  ${name:-25s} ${ns_per_op:8d} ns/op  ${ops_per_sec:12.0f} ops/sec')
	}

	// Warmup
	bench_float_decode(1000, pool, pool_size)

	for run := 0; run < 3; run++ {
		println('\n--- Run ${run + 1} ---')
		bench('float decode', bench_float_decode(iterations, pool, pool_size), iterations)
	}
}
