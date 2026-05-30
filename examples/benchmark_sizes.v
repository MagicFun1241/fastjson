import os
import rand
import time
import fastjson

#include <sys/resource.h>
#include <gc/gc.h>

fn C.getrusage(int, voidptr) int
fn C.GC_get_total_bytes() u64
fn C.GC_gcollect()
fn C.malloc(size usize) voidptr
fn C.free(ptr voidptr)

const pool_size = 256

// Small: ~400B, 11 keys, 3 layers (matches sonic's Small benchmark)
struct SmallStruct {
	name    string
	age     int
	score   f64
	active  bool
	email   string
	address string
	city    string
	zip     int
	phone   string
	company string
	title   string
}

// Medium: ~2KB, many keys, nested (matches sonic's Medium benchmark spirit)
struct Profile {
	x        f64
	y        int
	bio      string
	verified bool
}

struct MediumStruct {
	id       int
	name     string
	email    string
	age      int
	address  string
	tags     []string
	metadata map[string]string
	active   bool
	score    f64
	profile  Profile
}

// Large: ~8KB, many repeated fields (matches sonic's Large benchmark spirit)
struct LargeStruct {
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

const names = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve', 'Frank', 'Grace', 'Hank']
const cities = ['Springfield', 'Riverdale', 'Gotham', 'Metropolis', 'StarsHollow']
const domains = ['example.com', 'test.org', 'bench.io', 'fast.dev']
const departments = ['engineering', 'marketing', 'sales', 'design', 'ops']
const levels = ['junior', 'mid', 'senior', 'staff', 'principal']
const tag_pool = ['developer', 'golang', 'backend', 'frontend', 'devops', 'rust', 'python', 'java']

struct BenchResult {
	duration   time.Duration
	gc_bytes   u64 // total GC bytes allocated during benchmark
}

fn bench_gc_collect() {
	C.GC_gcollect()
}

fn bench_gc_total_bytes() u64 {
	return C.GC_get_total_bytes()
}

// Peak RSS in KB via getrusage (struct rusage, ru_maxrss at offset 32 on 64-bit)
fn peak_rss_kb() i64 {
	buf := unsafe { C.malloc(144) }
	C.getrusage(0, buf) // RUSAGE_SELF = 0
	// ru_maxrss at byte offset 32: after ru_utime (16B) + ru_stime (16B)
	maxrss := unsafe { *(&i64(byteptr(buf) + 32)) }
	unsafe { C.free(buf) }
	$if macos {
		return maxrss / 1024 // macOS: bytes -> KB
	} $else {
		return maxrss // Linux: already KB
	}
}

fn generate_small_pool() []string {
	mut pool := []string{cap: pool_size}
	rand.seed([u32(42), u32(0)])
	for _ in 0 .. pool_size {
		input := SmallStruct{
			name:    names[rand.intn(names.len) or { panic(err) }]
			age:     rand.intn(80) or { panic(err) } + 18
			score:   rand.f64() * 100.0
			active:  rand.intn(2) or { panic(err) } == 1
			email:   '${names[rand.intn(names.len) or { panic(err) }]}@${domains[rand.intn(domains.len) or { panic(err) }]}'
			address: '${rand.intn(9999) or { panic(err) }} Main St'
			city:    cities[rand.intn(cities.len) or { panic(err) }]
			zip:     rand.intn(90000) or { panic(err) } + 10000
			phone:   '${rand.intn(900) or { panic(err) } + 100}-${rand.intn(900) or { panic(err) } + 100}-${rand.intn(9000) or { panic(err) } + 1000}'
			company: 'Acme${rand.intn(100) or { panic(err) }}'
			title:   'Engineer L${rand.intn(6) or { panic(err) }}'
		}
		pool << fastjson.encode(input)
	}
	return pool
}

fn generate_medium_pool() []string {
	mut pool := []string{cap: pool_size}
	rand.seed([u32(42), u32(0)])
	for _ in 0 .. pool_size {
		mut tags := []string{}
		for _ in 0 .. rand.intn(4) or { panic(err) } + 1 {
			tags << tag_pool[rand.intn(tag_pool.len) or { panic(err) }]
		}
		meta := {
			'department': departments[rand.intn(departments.len) or { panic(err) }]
			'level':       levels[rand.intn(levels.len) or { panic(err) }]
		}
		input := MediumStruct{
			id:       rand.intn(100000) or { panic(err) }
			name:     names[rand.intn(names.len) or { panic(err) }]
			email:    '${names[rand.intn(names.len) or { panic(err) }]}@${domains[rand.intn(domains.len) or { panic(err) }]}'
			age:      rand.intn(60) or { panic(err) } + 18
			address:  '${rand.intn(9999) or { panic(err) }} ${names[rand.intn(names.len) or { panic(err) }]} St, ${cities[rand.intn(cities.len) or { panic(err) }]}'
			tags:     tags
			metadata: meta
			active:   rand.intn(2) or { panic(err) } == 1
			score:    rand.f64() * 100.0
			profile: Profile{
				x:        rand.f64() * 100.0
				y:        rand.intn(1000) or { panic(err) }
				bio:      'Software engineer with ${rand.intn(20) or { panic(err) }} years experience'
				verified: rand.intn(2) or { panic(err) } == 1
			}
		}
		pool << fastjson.encode(input)
	}
	return pool
}

fn generate_large_pool() []string {
	mut pool := []string{cap: pool_size}
	rand.seed([u32(42), u32(0)])
	for _ in 0 .. pool_size {
		mut tags := []string{}
		for _ in 0 .. rand.intn(10) or { panic(err) } + 2 {
			tags << tag_pool[rand.intn(tag_pool.len) or { panic(err) }]
		}
		mut meta := map[string]string{}
		for _ in 0 .. 8 {
			meta['key${rand.intn(100) or { panic(err) }}'] = 'value${rand.intn(1000) or { panic(err) }}'
		}
		input := LargeStruct{
			id:       rand.intn(100000) or { panic(err) }
			name:     names[rand.intn(names.len) or { panic(err) }]
			email:    '${names[rand.intn(names.len) or { panic(err) }]}@${domains[rand.intn(domains.len) or { panic(err) }]}'
			age:      rand.intn(60) or { panic(err) } + 18
			address:  '${rand.intn(9999) or { panic(err) }} ${names[rand.intn(names.len) or { panic(err) }]} St, ${cities[rand.intn(cities.len) or { panic(err) }]}'
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
	g_sink_name   string
	g_sink_age    int
	g_sink_str    string
	g_sink_score  f64
	g_sink_active bool
)

fn bench_decode[T](n int, pool []string) BenchResult {
	bench_gc_collect()
	gc_before := bench_gc_total_bytes()
	mut sw := time.new_stopwatch()
	sw.start()
	for i := 0; i < n; i++ {
		input := fastjson.decode[T](pool[i % pool_size]) or { panic(err) }
		g_sink_name = input.name
		g_sink_age = input.age
	}
	sw.stop()
	gc_after := bench_gc_total_bytes()
	return BenchResult{
		duration: sw.elapsed()
		gc_bytes: gc_after - gc_before
	}
}

fn bench_encode[T](n int, pool []string) BenchResult {
	// Pre-decode all values so we only measure encode
	mut decoded := []T{cap: pool.len}
	for i := 0; i < pool.len; i++ {
		decoded << fastjson.decode[T](pool[i]) or { panic(err) }
	}
	bench_gc_collect()
	gc_before := bench_gc_total_bytes()
	mut sw := time.new_stopwatch()
	sw.start()
	for i := 0; i < n; i++ {
		g_sink_str = fastjson.encode(decoded[i % pool.len])
	}
	sw.stop()
	gc_after := bench_gc_total_bytes()
	return BenchResult{
		duration: sw.elapsed()
		gc_bytes: gc_after - gc_before
	}
}

fn bench_roundtrip[T](n int, pool []string) BenchResult {
	bench_gc_collect()
	gc_before := bench_gc_total_bytes()
	mut sw := time.new_stopwatch()
	sw.start()
	for i := 0; i < n; i++ {
		input := fastjson.decode[T](pool[i % pool_size]) or { panic(err) }
		g_sink_str = fastjson.encode(input)
	}
	sw.stop()
	gc_after := bench_gc_total_bytes()
	return BenchResult{
		duration: sw.elapsed()
		gc_bytes: gc_after - gc_before
	}
}

fn print_bench(name string, res BenchResult, n int) {
	ns_per_op := res.duration.nanoseconds() / n
	ops_per_sec := f64(n) / res.duration.seconds()
	bytes_per_op := f64(res.gc_bytes) / f64(n)
	println('  ${name:-25s} ${ns_per_op:8d} ns/op  ${ops_per_sec:12.0f} ops/sec  ${bytes_per_op:8.1f} B/op')
}

fn main() {
	mut iterations := 200000
	if os.args.len > 1 {
		iterations = os.args[1].int()
		if iterations <= 0 {
			iterations = 200000
		}
	}

	small_pool := generate_small_pool()
	medium_pool := generate_medium_pool()
	large_pool := generate_large_pool()

	// Print average payload sizes
	small_size := small_pool[0].len
	medium_size := medium_pool[0].len
	large_size := large_pool[0].len

	println('V fastjson benchmark — ${iterations} iterations')
	println('='.repeat(68))
	println('  Small:  ~${small_size}B  (11 keys, 3 layers)')
	println('  Medium: ~${medium_size}B  (13 keys + nested struct, map)')
	println('  Large:  ~${large_size}B  (9 keys + large tags, map)')
	println('')

	// Warmup
	bench_decode[SmallStruct](5000, small_pool)
	bench_decode[MediumStruct](5000, medium_pool)
	bench_decode[LargeStruct](5000, large_pool)

	println('--- Small (~${small_size}B, 11 keys) ---')
	print_bench('decode', bench_decode[SmallStruct](iterations, small_pool), iterations)
	print_bench('encode', bench_encode[SmallStruct](iterations, small_pool), iterations)
	print_bench('roundtrip', bench_roundtrip[SmallStruct](iterations, small_pool), iterations)
	println('')

	println('--- Medium (~${medium_size}B, 13 keys + nested) ---')
	print_bench('decode', bench_decode[MediumStruct](iterations, medium_pool), iterations)
	print_bench('encode', bench_encode[MediumStruct](iterations, medium_pool), iterations)
	print_bench('roundtrip', bench_roundtrip[MediumStruct](iterations, medium_pool), iterations)
	println('')

	println('--- Large (~${large_size}B, 9 keys + big arrays/maps) ---')
	print_bench('decode', bench_decode[LargeStruct](iterations, large_pool), iterations)
	print_bench('encode', bench_encode[LargeStruct](iterations, large_pool), iterations)
	print_bench('roundtrip', bench_roundtrip[LargeStruct](iterations, large_pool), iterations)
	println('')

	rss := peak_rss_kb()
	println('Peak RSS: ${rss} KB')
	println('sink: name=${g_sink_name} age=${g_sink_age} score=${g_sink_score}')
}