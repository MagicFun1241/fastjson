import fastjson

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

fn test_decode_simple() {
	s := '{"name":"Alice","age":30}'
	result := fastjson.decode[SimpleInput](s) or { panic(err) }
	assert result.name == 'Alice'
	assert result.age == 30
}

fn test_decode_complex() {
	s := '{"id":42,"name":"Bob","email":"bob@test.org","age":25,"address":"123 Main St, Gotham","tags":["dev","go"],"metadata":{"department":"engineering","level":"senior"},"active":true,"score":95.5}'
	result := fastjson.decode[ComplexInput](s) or { panic(err) }
	assert result.id == 42
	assert result.name == 'Bob'
	assert result.email == 'bob@test.org'
	assert result.age == 25
	assert result.address == '123 Main St, Gotham'
	assert result.tags.len == 2
	assert result.tags[0] == 'dev'
	assert result.tags[1] == 'go'
	assert result.metadata['department'] == 'engineering'
	assert result.metadata['level'] == 'senior'
	assert result.active == true
	assert result.score == 95.5
}

fn test_encode_simple() {
	input := SimpleInput{'Charlie', 35}
	s := fastjson.encode(input)
	assert s == '{"name":"Charlie","age":35}'
}

fn test_encode_complex() {
	input := ComplexInput{
		id: 1
		name: 'Diana'
		email: 'diana@bench.io'
		age: 28
		address: '456 Oak St, Springfield'
		tags: ['rust', 'backend']
		metadata: {'team': 'platform'}
		active: false
		score: 87.3
	}
	s := fastjson.encode(input)
	assert s.contains('"name":"Diana"')
	assert s.contains('"age":28')
	assert s.contains('"active":false')
	assert s.contains('"tags":["rust","backend"]')
	assert s.contains('"team":"platform"')
}

fn test_roundtrip() {
	original := SimpleInput{'Eve', 42}
	encoded := fastjson.encode(original)
	decoded := fastjson.decode[SimpleInput](encoded) or { panic(err) }
	assert decoded.name == original.name
	assert decoded.age == original.age
}

fn test_decode_negative_numbers() {
	s := '{"name":"Test","age":-5}'
	result := fastjson.decode[SimpleInput](s) or { panic(err) }
	assert result.age == -5
}

fn test_encode_bool_false() {
	input := SimpleInput{'Test', 0}
	s := fastjson.encode(input)
	assert s.contains('"age":0')
}
