# fastjson

A blazingly fast JSON serializing & deserializing library for [V](https://vlang.io), accelerated by **SSE2 SIMD** and algorithms from [bytedance/sonic](https://github.com/bytedance/sonic).

## Requirements

- V 0.5.x+
- CPU with SSE2 support (AMD64); scalar fallback for ARM/other platforms
- OS: macOS / Linux / Windows

## Features

- **SIMD-accelerated scanning** — field lookup, whitespace skip, structural char detection all use SSE2 16-byte blocks
- **Eisel-Lemire float parsing** — 128-bit power-of-10 lookup avoids `strtod` for common doubles
- **itoa8 SSE2 integer formatting** — parallel 8-digit int-to-string from sonic's `fastint.h`, with Digits[200] scalar fallback
- **Schubfach f64-to-string** — shortest decimal representation for all f64 values (including denormals), no `.str()` or `snprintf` fallbacks
- **Zero-allocation string decoding** — `decode[T]()` returns strings as slices into the JSON buffer (GC-safe; cloned where needed for container types)
- **Generic encode/decode** — `encode[T]()` and `decode[T]()` work with any V struct via compile-time reflection
- **Nested structs, arrays, maps** — `[]string`, `[]int`, `[]f64`, `map[string]string`, and nested struct fields all supported

## Benchmark

Apple M1 Pro, 200,000 iterations, 3 sizes matching sonic's benchmark methodology.

### Throughput

| Size | Operation | V fastjson | Go stdlib | Go sonic | vs stdlib | vs sonic |
|------|-----------|-----------|-----------|---------|-----------|----------|
| **Small (~210B, 11 keys)** | | | | | | |
| | Decode | **234 ns** | 2154 ns | 650 ns | 9.2× faster | 2.8× faster |
| | Encode | **194 ns** | 369 ns | 625 ns | 1.9× faster | 3.2× faster |
| | Roundtrip | **438 ns** | 2523 ns | 1275 ns | 5.8× faster | 2.9× faster |
| **Medium (~340B, 13 keys)** | | | | | | |
| | Decode | **858 ns** | 3343 ns | 1158 ns | 3.9× faster | 1.3× faster |
| | Encode | **609 ns** | 778 ns | 1185 ns | 1.3× faster | 1.9× faster |
| | Roundtrip | **1480 ns** | 4121 ns | 2343 ns | 2.8× faster | 1.6× faster |
| **Large (~420B, 9 keys + big arrays/maps)** | | | | | | |
| | Decode | **1435 ns** | 4841 ns | 1171 ns | 3.4× faster | ~0.8× |
| | Encode | **549 ns** | 1546 ns | 1946 ns | 2.8× faster | 3.5× faster |
| | Roundtrip | **1891 ns** | 6387 ns | 3117 ns | 3.4× faster | 1.6× faster |

### Memory (B/op, allocs/op)

| Size | Operation | V fastjson | Go stdlib | Go sonic |
|------|-----------|-----------|-----------|----------|
| **Small** | | | | |
| | Decode | **0 B** | 456 B (12) | 563 B (4) |
| | Encode | **463 B** | 208 B (1) | 226 B (2) |
| | Roundtrip | **463 B** | 664 B (13) | 789 B (6) |
| **Medium** | | | | |
| | Decode | **1106 B** | 968 B (24) | 1072 B (8) |
| | Encode | **1252 B** | 592 B (7) | 567 B (4) |
| | Roundtrip | **2358 B** | 1560 B (31) | 1639 B (12) |
| **Large** | | | | |
| | Decode | **1596 B** | 1288 B (48) | 1310 B (8) |
| | Encode | **1062 B** | 1040 B (19) | 588 B (4) |
| | Roundtrip | **2658 B** | 2328 B (67) | 1898 B (12) |

> *V fastjson B/op measured via Boehm GC cumulative allocator counter (`GC_get_total_bytes` delta). Go B/op via `testing.B.ReportAllocs`. Numbers in parentheses are Go heap allocations per operation. Peak RSS: 3.3 MB.*

**Takeaways:**
- **Decode**: 3.4–9.2× faster than Go stdlib, 0.8–2.8× faster than sonic
- **Encode**: 1.3–2.8× faster than Go stdlib, 1.9–3.5× faster than sonic
- **Roundtrip**: 2.8–5.8× faster than Go stdlib, 1.6–2.9× faster than sonic
- **Memory**: peak RSS 3.3 MB; per-op encode B/op is higher due to `strings.Builder.str()` buffer copy

Run the benchmark yourself:

```bash
# V fastjson
cd examples && v -enable-globals -prod run benchmark_sizes.v

# Go comparison (stdlib + sonic)
cd /tmp/bench_compare && go test -bench=. -benchtime=200000x -benchmem -count=1 -run=^$
```

## Usage

### Install

```bash
v install https://github.com/magicfun1241/fastjson
```

### Decode (deserialize)

```v
import fastjson

struct User {
	name  string
	age   int
	score f64
	active bool
	tags  []string
	meta  map[string]string
	profile NestedInner
}

struct NestedInner {
	x f64
	y int
}

data := '{"name":"Alice","age":30,"score":95.5,"active":true,"tags":["dev","go"],"meta":{"dept":"eng"},"profile":{"x":1.5,"y":42}}'

user := fastjson.decode[User](data) or { panic(err) }
println(user.name)    // Alice
println(user.age)     // 30
println(user.score)   // 95.5
println(user.tags[0]) // dev
```

### Encode (serialize)

```v
user := User{
	name: 'Bob'
	age: 25
	score: 88.0
	active: true
	tags: ['dev', 'rust']
	meta: {'dept': 'infra'}
	profile: NestedInner{x: 2.0, y: 7}
}

json_str := fastjson.encode(user)
println(json_str)
// {"name":"Bob","age":25,"score":88.0,"active":true,"tags":["dev","rust"],"meta":{"dept":"infra"},"profile":{"x":2.0,"y":7}}
```

### Low-level scanner API

For maximum control, use the scanner and extract functions directly:

```v
fields := fastjson.scan_object(json_str)
idx := fastjson.find_field(json_str, fields, 'name')
name := fastjson.extract_string(json_str, fields[idx])
age := fastjson.extract_int(json_str, fields[age_idx])
score := fastjson.extract_f64(json_str, fields[score_idx])
```


## Limitations

- **String decoding is zero-copy** — `decode[T]()` returns strings as slices into the JSON buffer. Escape sequences (`\"`, `\\`, `\n`, etc.) are **not** unescaped. This is a deliberate performance tradeoff (same as sonic's `SonicsUseNode` strategy). If you need unescaped strings, post-process the result.
- **No streaming API** — the full JSON string must be in memory.
- **No dynamic typing** — decode only works with concrete struct types.

## License

MIT — see [LICENSE](LICENSE).

Float parsing algorithms adapted from [bytedance/sonic](https://github.com/bytedance/sonic) (Apache 2.0). Integer formatting adapted from sonic's `fastint.h` (Apache 2.0).
