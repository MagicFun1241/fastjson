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
- **Schubfach f64-to-string** — shortest decimal representation for all f64 values (including denormals), no `.str()` or `snprintf` fallback
- **Zero-allocation string decoding** — `extract_string` returns a zero-copy slice into the JSON buffer
- **Generic encode/decode** — `encode[T]()` and `decode[T]()` work with any V struct via compile-time reflection
- **Nested structs, arrays, maps** — `[]string`, `[]int`, `[]f64`, `map[string]string`, and nested struct fields all supported

## Benchmark

Apple M1 Pro, 200,000 iterations, 3 sizes matching sonic's benchmark methodology:

| Size | Operation | V fastjson | Go stdlib | Go sonic | vs stdlib | vs sonic |
|------|-----------|-----------|-----------|---------|-----------|----------|
| **Small (~210B, 11 keys)** | | | | | | |
| | Decode | **531 ns** | 2086 ns | 657 ns | 3.9× faster | 1.2× faster |
| | Encode | 645 ns | **371 ns** | 605 ns | 0.6× | 1.1× |
| | Roundtrip | 656 ns | 1457 ns | 1262 ns | 2.2× faster | 1.9× faster |
| **Medium (~340B, 13 keys)** | | | | | | |
| | Decode | 1306 ns | 3256 ns | **995 ns** | 2.5× faster | 1.3× |
| | Encode | 1689 ns | **754 ns** | 1118 ns | 0.4× | 1.5× |
| | Roundtrip | 1700 ns | 4010 ns | 2113 ns | 2.4× faster | 1.2× |
| **Large (~420B, 9 keys + big arrays/maps)** | | | | | | |
| | Decode | 1565 ns | 4527 ns | **1113 ns** | 2.9× faster | 1.4× |
| | Encode | 2030 ns | **1353 ns** | 1833 ns | 0.7× | 1.1× |
| | Roundtrip | 2103 ns | 5880 ns | 2946 ns | 2.8× faster | 1.4× |

**Takeaways:**
- **Decode**: 2.5–3.9× faster than Go stdlib, competitive with sonic
- **Encode**: now competitive with sonic (1.1–1.5×), closing gap to Go stdlib (Schubfach f64-to-string + C write helpers eliminate V runtime overhead)
- **Roundtrip**: 1.9–2.8× faster than Go stdlib

Run the benchmark yourself:

```bash
# V fastjson
cd examples && v -enable-globals -prod run benchmark_sizes.v

# Go comparison (stdlib + sonic)
cd /tmp/bench_compare && go test -bench=. -benchtime=200000x -benchmem -count=1 -run=^$
```

<details>
<summary>Raw Go benchmark output</summary>

```
cpu: Apple M1 Pro
BenchmarkSmall_StdLib_Decode-8    200000  2086 ns/op   456 B/op   12 allocs/op
BenchmarkSmall_StdLib_Encode-8    200000   371 ns/op   208 B/op    1 allocs/op
BenchmarkSmall_Sonic_Decode-8    200000   657 ns/op   595 B/op    4 allocs/op
BenchmarkSmall_Sonic_Encode-8    200000   605 ns/op   229 B/op    2 allocs/op
BenchmarkMedium_StdLib_Decode-8  200000  3256 ns/op   968 B/op   24 allocs/op
BenchmarkMedium_StdLib_Encode-8  200000   754 ns/op   592 B/op    7 allocs/op
BenchmarkMedium_Sonic_Decode-8   200000   995 ns/op  1209 B/op    8 allocs/op
BenchmarkMedium_Sonic_Encode-8   200000  1118 ns/op   566 B/op    4 allocs/op
BenchmarkLarge_StdLib_Decode-8   200000  4527 ns/op  1288 B/op   48 allocs/op
BenchmarkLarge_StdLib_Encode-8   200000  1353 ns/op  1040 B/op   19 allocs/op
BenchmarkLarge_Sonic_Decode-8    200000  1113 ns/op  1226 B/op    8 allocs/op
BenchmarkLarge_Sonic_Encode-8    200000  1833 ns/op   580 B/op    4 allocs/op
```

</details>

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

- **String decoding is zero-copy** — `extract_string` returns a slice into the JSON buffer. Escape sequences (`\"`, `\\`, `\n`, etc.) are **not** unescaped. This is a deliberate performance tradeoff (same as sonic's `SonicsUseNode` strategy). If you need unescaped strings, post-process the result.
- **No streaming API** — the full JSON string must be in memory.
- **No dynamic typing** — decode only works with concrete struct types.

## License

MIT — see [LICENSE](LICENSE).

Float parsing algorithms adapted from [bytedance/sonic](https://github.com/bytedance/sonic) (Apache 2.0). Integer formatting adapted from sonic's `fastint.h` (Apache 2.0).
