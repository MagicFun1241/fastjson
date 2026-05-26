import os
import rand
import time
import fastjson

const pool_size = 256

const names = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve', 'Frank', 'Grace', 'Hank']
const cities = ['Springfield', 'Riverdale', 'Gotham', 'Metropolis', 'StarsHollow']
const domains = ['example.com', 'test.org', 'bench.io', 'fast.dev']
const departments = ['engineering', 'marketing', 'sales', 'design', 'ops']
const levels = ['junior', 'mid', 'senior', 'staff', 'principal']
const teams_list = ['platform', 'backend', 'frontend', 'infra', 'mobile']
const tag_pool = ['developer', 'golang', 'backend', 'frontend', 'devops', 'rust', 'python', 'java']

struct SimpleInput {
	name string
	age  int
}

struct ComplexInput {
	id       int
	name     string
	email    string
	age      int
	address  string
	tags     []string
	metadata map[string]string
	active   bool
	score    f64
}

fn generate_simple_pool() []string {
	mut pool := []string{cap: pool_size}
	rand.seed([u32(42), u32(0)])
	for _ in 0 .. pool_size {
		name := names[rand.intn(names.len) or { panic(err) }]
		age := rand.intn(80) or { panic(err) } + 18
		input := SimpleInput{name, age}
		pool << fastjson.encode(input)
	}
	return pool
}

fn generate_complex_pool() []string {
	mut pool := []string{cap: pool_size}
	rand.seed([u32(42), u32(0)])
	for _ in 0 .. pool_size {
		mut tags := []string{}
		for _ in 0 .. rand.intn(4) or { panic(err) } + 1 {
			tags << tag_pool[rand.intn(tag_pool.len) or { panic(err) }]
		}
		meta := {
			'department': departments[rand.intn(departments.len) or { panic(err) }]
			'level':      levels[rand.intn(levels.len) or { panic(err) }]
			'team':       teams_list[rand.intn(teams_list.len) or { panic(err) }]
		}
		input := ComplexInput{
			id:       rand.intn(100000) or { panic(err) }
			name:     names[rand.intn(names.len) or { panic(err) }]
			email:    '${names[rand.intn(names.len) or { panic(err) }]}@${domains[rand.intn(domains.len) or { panic(err) }]}'
			age:      rand.intn(60) or { panic(err) } + 18
			address:  '${rand.intn(9999) or { panic(err) } + 1} ${names[rand.intn(names.len) or { panic(err) }]} St, ${cities[rand.intn(cities.len) or { panic(err) }]}'
			tags:     tags
			metadata: meta
			active:   rand.intn(2) or { panic(err) } == 1
			score:    rand.f64() * 100.0
		}
		pool << fastjson.encode(input)
	}
	return pool
}

__global (
	g_sink_name string
	g_sink_age   int
	g_sink_str   string
)

fn bench_simple_decode(n int, pool []string) time.Duration {
	mut sw := time.new_stopwatch()
	sw.start()
	for i := 0; i < n; i++ {
		input := fastjson.decode[SimpleInput](pool[i % pool_size]) or { panic(err) }
		g_sink_name = input.name
		g_sink_age = input.age
	}
	sw.stop()
	return sw.elapsed()
}

fn bench_simple_encode(n int, pool []string) time.Duration {
	mut sw := time.new_stopwatch()
	sw.start()
	for i := 0; i < n; i++ {
		input := fastjson.decode[SimpleInput](pool[i % pool_size]) or { panic(err) }
		g_sink_str = fastjson.encode(input)
	}
	sw.stop()
	return sw.elapsed()
}

fn bench_simple_roundtrip(n int, pool []string) time.Duration {
	mut sw := time.new_stopwatch()
	sw.start()
	for i := 0; i < n; i++ {
		input := fastjson.decode[SimpleInput](pool[i % pool_size]) or { panic(err) }
		g_sink_str = fastjson.encode(input)
	}
	sw.stop()
	return sw.elapsed()
}

fn bench_complex_decode(n int, pool []string) time.Duration {
	mut sw := time.new_stopwatch()
	sw.start()
	for i := 0; i < n; i++ {
		input := fastjson.decode[ComplexInput](pool[i % pool_size]) or { panic(err) }
		g_sink_name = input.name
		g_sink_age = input.age
	}
	sw.stop()
	return sw.elapsed()
}

fn bench_complex_encode(n int, pool []string) time.Duration {
	mut sw := time.new_stopwatch()
	sw.start()
	for i := 0; i < n; i++ {
		input := fastjson.decode[ComplexInput](pool[i % pool_size]) or { panic(err) }
		g_sink_str = fastjson.encode(input)
	}
	sw.stop()
	return sw.elapsed()
}

fn bench_complex_roundtrip(n int, pool []string) time.Duration {
	mut sw := time.new_stopwatch()
	sw.start()
	for i := 0; i < n; i++ {
		input := fastjson.decode[ComplexInput](pool[i % pool_size]) or { panic(err) }
		g_sink_str = fastjson.encode(input)
	}
	sw.stop()
	return sw.elapsed()
}

fn main() {
	mut iterations := 100000
	if os.args.len > 1 {
		iterations = os.args[1].int()
		if iterations <= 0 {
			iterations = 100000
		}
	}

	simple_pool := generate_simple_pool()
	complex_pool := generate_complex_pool()

	println('V fastjson (SIMD, generic) — ${iterations} iterations (random pool: ${pool_size})')
	println('==========================================')

	bench := fn(name string, d time.Duration, n int) {
		ns_per_op := d.nanoseconds() / n
		ops_per_sec := f64(n) / d.seconds()
		println('  ${name:-25s} ${ns_per_op:8d} ns/op  ${ops_per_sec:12.0f} ops/sec')
	}

	bench('simple decode', bench_simple_decode(iterations, simple_pool), iterations)
	bench('simple encode', bench_simple_encode(iterations, simple_pool), iterations)
	bench('simple roundtrip', bench_simple_roundtrip(iterations, simple_pool), iterations)
	bench('complex decode', bench_complex_decode(iterations, complex_pool), iterations)
	bench('complex encode', bench_complex_encode(iterations, complex_pool), iterations)
	bench('complex roundtrip', bench_complex_roundtrip(iterations, complex_pool), iterations)
}
