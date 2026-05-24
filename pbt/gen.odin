package pbt

import "core:math"

Gen :: struct(Input: typeid, Value: typeid) {
	input:   Input,
	produce: proc(t: ^T, input: Input) -> Value,
}

draw :: proc(t: ^T, gen: Gen($Input, $Value)) -> Value {
	return gen.produce(t, gen.input)
}

Sample_Options :: struct {
	count: int,
	seed:  u64,
	size:  int,
}

Sample_Result :: struct(Value: typeid) {
	values: [dynamic]Value,
	ctx:    T,
}

sample_options :: proc(options: Sample_Options) -> Sample_Options {
	o := options
	if o.count <= 0 {
		o.count = 10
	}
	if o.seed == 0 {
		o.seed = 0x9e37_79b9_7f4a_7c15
	}
	if o.size <= 0 {
		o.size = 10
	}
	return o
}

sample :: proc(gen: Gen($Input, $Value), options: Sample_Options = {}) -> Sample_Result(Value) {
	opts := sample_options(options)
	result := Sample_Result(Value) {
		values = make([dynamic]Value, 0, opts.count),
	}
	test_init(&result.ctx, opts.seed, opts.size, nil, false, false)
	for i in 0 ..< opts.count {
		result.ctx.size = 1 + (i * opts.size) / opts.count
		append(&result.values, draw(&result.ctx, gen))
	}
	return result
}

destroy_sample_result :: proc(result: ^Sample_Result($Value)) {
	delete(result.values)
	test_destroy(&result.ctx)
}

Constant_Input :: struct(Value: typeid) {
	value: Value,
}

constant :: proc(value: $Value) -> Gen(Constant_Input(Value), Value) {
	return {
		input = {value = value},
		produce = proc(_: ^T, input: Constant_Input(Value)) -> Value {
			return input.value
		},
	}
}

Bool_Input :: struct {}

boolean :: proc() -> Gen(Bool_Input, bool) {
	return {
		input = {},
		produce = proc(t: ^T, _: Bool_Input) -> bool {
			return choice(t, 2) == 1
		},
	}
}

Int_Range_Input :: struct {
	min: int,
	max: int,
}

int_range :: proc(min, max: int) -> Gen(Int_Range_Input, int) {
	return {
		input = {min = min, max = max},
		produce = proc(t: ^T, input: Int_Range_Input) -> int {
			if input.max <= input.min {
				return input.min
			}

			width := u64(input.max - input.min + 1)
			return input.min + int(choice(t, width))
		},
	}
}

U64_Range_Input :: struct {
	min: u64,
	max: u64,
}

u64_range :: proc(min, max: u64) -> Gen(U64_Range_Input, u64) {
	return {
		input = {min = min, max = max},
		produce = proc(t: ^T, input: U64_Range_Input) -> u64 {
			if input.max <= input.min {
				return input.min
			}

			width := input.max - input.min + 1
			return input.min + choice(t, width)
		},
	}
}

F64_Range_Input :: struct {
	min: f64,
	max: f64,
}

f64_range :: proc(min, max: f64) -> Gen(F64_Range_Input, f64) {
	return {
		input = {min = min, max = max},
		produce = proc(t: ^T, input: F64_Range_Input) -> f64 {
			if input.max <= input.min {
				return input.min
			}

			// Use 53 random bits so the generated fraction fits exactly in an f64 mantissa.
			raw := choice(t, 1 << 53)
			fraction := f64(raw) / f64(1 << 53)
			return input.min + (input.max - input.min) * fraction
		},
	}
}

Elements_Input :: struct(Value: typeid) {
	values: []Value,
}

elements :: proc(values: []$Value) -> Gen(Elements_Input(Value), Value) {
	return {
		input = {values = values},
		produce = proc(t: ^T, input: Elements_Input(Value)) -> Value {
			if len(input.values) == 0 {
				return {}
			}

			index := int(choice(t, u64(len(input.values))))
			return input.values[index]
		},
	}
}

Enum_Range_Input :: struct(Value: typeid) {
	min: Value,
	max: Value,
}

enum_range :: proc(min, max: $Value) -> Gen(Enum_Range_Input(Value), Value) {
	return {
		input = {min = min, max = max},
		produce = proc(t: ^T, input: Enum_Range_Input(Value)) -> Value {
			min := int(input.min)
			max := int(input.max)
			if max <= min {
				return input.min
			}

			return Value(min + int(choice(t, u64(max - min + 1))))
		},
	}
}

One_Of_Input :: struct(Gen_Input: typeid, Value: typeid) {
	gens: []Gen(Gen_Input, Value),
}

one_of :: proc(gens: []Gen($Gen_Input, $Value)) -> Gen(One_Of_Input(Gen_Input, Value), Value) {
	return {
		input = {gens = gens},
		produce = proc(t: ^T, input: One_Of_Input(Gen_Input, Value)) -> Value {
			index := int(choice(t, u64(len(input.gens))))
			return draw(t, input.gens[index])
		},
	}
}

Weighted_Gen :: struct(Gen_Input: typeid, Value: typeid) {
	weight: int,
	gen:    Gen(Gen_Input, Value),
}

Frequency_Input :: struct(Gen_Input: typeid, Value: typeid) {
	gens: []Weighted_Gen(Gen_Input, Value),
}

frequency :: proc(gens: []Weighted_Gen($Gen_Input, $Value)) -> Gen(Frequency_Input(Gen_Input, Value), Value) {
	return {
		input = {gens = gens},
		produce = proc(t: ^T, input: Frequency_Input(Gen_Input, Value)) -> Value {
			total := 0
			for weighted in input.gens {
				if weighted.weight > 0 {
					total += weighted.weight
				}
			}

			if total <= 0 {
				return draw(t, input.gens[0].gen)
			}

			pick := int(choice(t, u64(total)))
			running := 0
			for weighted in input.gens {
				if weighted.weight <= 0 {
					continue
				}

				running += weighted.weight
				if pick < running {
					return draw(t, weighted.gen)
				}
			}

			return draw(t, input.gens[len(input.gens) - 1].gen)
		},
	}
}

Array_Input :: struct(Gen_Input: typeid, Value: typeid) {
	elem:    Gen(Gen_Input, Value),
	min_len: int,
	max_len: int,
}

array :: proc(elem: Gen($Gen_Input, $Value), min_len: int = 0, max_len: int = -1) -> Gen(Array_Input(Gen_Input, Value), []Value) {
	return {
		input = {elem = elem, min_len = min_len, max_len = max_len},
		produce = proc(t: ^T, input: Array_Input(Gen_Input, Value)) -> []Value {
			max_len := input.max_len
			if max_len < input.min_len {
				max_len = math.max(input.min_len, t.size)
			}

			length := input.min_len + int(choice(t, u64(max_len - input.min_len + 1)))
			values := make([]Value, length, t.value_allocator)
			for i in 0 ..< length {
				values[i] = draw(t, input.elem)
			}
			return values
		},
	}
}

non_empty_array :: proc(elem: Gen($Gen_Input, $Value), max_len: int = -1) -> Gen(Array_Input(Gen_Input, Value), []Value) {
	return array(elem, 1, max_len)
}

unique_array :: proc(elem: Gen($Gen_Input, $Value), min_len: int = 0, max_len: int = -1) -> Gen(Array_Input(Gen_Input, Value), []Value) {
	return {
		input = {elem = elem, min_len = min_len, max_len = max_len},
		produce = proc(t: ^T, input: Array_Input(Gen_Input, Value)) -> []Value {
			max_len := input.max_len
			if max_len < input.min_len {
				max_len = math.max(input.min_len, t.size)
			}

			target_len := input.min_len + int(choice(t, u64(max_len - input.min_len + 1)))
			values := make([dynamic]Value, 0, target_len, t.value_allocator)
			max_attempts := target_len * 8 + 16
			for len(values) < target_len && max_attempts > 0 {
				value := draw(t, input.elem)
				if !contains_value(values[:], value) {
					append(&values, value)
				}
				max_attempts -= 1
			}
			return values[:]
		},
	}
}

contains_value :: proc(values: []$Value, value: Value) -> bool {
	for existing in values {
		if existing == value {
			return true
		}
	}
	return false
}

String_ASCII_Input :: struct {
	min_len: int,
	max_len: int,
}

string_ascii :: proc(min_len: int = 0, max_len: int = -1) -> Gen(String_ASCII_Input, string) {
	return {
		input = {min_len = min_len, max_len = max_len},
		produce = proc(t: ^T, input: String_ASCII_Input) -> string {
			max_len := input.max_len
			if max_len < input.min_len {
				max_len = math.max(input.min_len, t.size)
			}

			length := input.min_len + int(choice(t, u64(max_len - input.min_len + 1)))
			bytes := make([]byte, length, t.value_allocator)
			for i in 0 ..< length {
				bytes[i] = byte(32 + choice(t, 95))
			}
			return string(bytes)
		},
	}
}

non_empty_string_ascii :: proc(max_len: int = -1) -> Gen(String_ASCII_Input, string) {
	return string_ascii(1, max_len)
}

String_Alphabet_Input :: struct {
	alphabet: string,
	min_len:  int,
	max_len:  int,
}

string_alphabet :: proc(alphabet: string, min_len: int = 0, max_len: int = -1) -> Gen(String_Alphabet_Input, string) {
	return {
		input = {alphabet = alphabet, min_len = min_len, max_len = max_len},
		produce = proc(t: ^T, input: String_Alphabet_Input) -> string {
			if len(input.alphabet) == 0 {
				return ""
			}

			max_len := input.max_len
			if max_len < input.min_len {
				max_len = math.max(input.min_len, t.size)
			}

			length := input.min_len + int(choice(t, u64(max_len - input.min_len + 1)))
			bytes := make([]byte, length, t.value_allocator)
			for i in 0 ..< length {
				index := int(choice(t, u64(len(input.alphabet))))
				bytes[i] = input.alphabet[index]
			}
			return string(bytes)
		},
	}
}

non_empty_string_alphabet :: proc(alphabet: string, max_len: int = -1) -> Gen(String_Alphabet_Input, string) {
	return string_alphabet(alphabet, 1, max_len)
}

Optional :: struct(Value: typeid) {
	ok:    bool,
	value: Value,
}

Optional_Input :: struct(Gen_Input: typeid, Value: typeid) {
	elem: Gen(Gen_Input, Value),
}

optional :: proc(elem: Gen($Gen_Input, $Value)) -> Gen(Optional_Input(Gen_Input, Value), Optional(Value)) {
	return {
		input = {elem = elem},
		produce = proc(t: ^T, input: Optional_Input(Gen_Input, Value)) -> Optional(Value) {
			if !draw(t, boolean()) {
				return {}
			}
			return {ok = true, value = draw(t, input.elem)}
		},
	}
}

Pair :: struct(First: typeid, Second: typeid) {
	first:  First,
	second: Second,
}

Pair_Input :: struct(First_Input: typeid, First: typeid, Second_Input: typeid, Second: typeid) {
	first:  Gen(First_Input, First),
	second: Gen(Second_Input, Second),
}

pair :: proc(first: Gen($First_Input, $First), second: Gen($Second_Input, $Second)) -> Gen(Pair_Input(First_Input, First, Second_Input, Second), Pair(First, Second)) {
	return {
		input = {first = first, second = second},
		produce = proc(t: ^T, input: Pair_Input(First_Input, First, Second_Input, Second)) -> Pair(First, Second) {
			return {
				first = draw(t, input.first),
				second = draw(t, input.second),
			}
		},
	}
}

Triple :: struct(First: typeid, Second: typeid, Third: typeid) {
	first:  First,
	second: Second,
	third:  Third,
}

Triple_Input :: struct(First_Input: typeid, First: typeid, Second_Input: typeid, Second: typeid, Third_Input: typeid, Third: typeid) {
	first:  Gen(First_Input, First),
	second: Gen(Second_Input, Second),
	third:  Gen(Third_Input, Third),
}

triple :: proc(first: Gen($First_Input, $First), second: Gen($Second_Input, $Second), third: Gen($Third_Input, $Third)) -> Gen(Triple_Input(First_Input, First, Second_Input, Second, Third_Input, Third), Triple(First, Second, Third)) {
	return {
		input = {first = first, second = second, third = third},
		produce = proc(t: ^T, input: Triple_Input(First_Input, First, Second_Input, Second, Third_Input, Third)) -> Triple(First, Second, Third) {
			return {
				first = draw(t, input.first),
				second = draw(t, input.second),
				third = draw(t, input.third),
			}
		},
	}
}

Dict_Input :: struct(Key_Input: typeid, Key: typeid, Value_Input: typeid, Value: typeid) {
	key:     Gen(Key_Input, Key),
	value:   Gen(Value_Input, Value),
	min_len: int,
	max_len: int,
}

dict :: proc(key: Gen($Key_Input, $Key), value: Gen($Value_Input, $Value), min_len: int = 0, max_len: int = -1) -> Gen(Dict_Input(Key_Input, Key, Value_Input, Value), map[Key]Value) {
	return {
		input = {key = key, value = value, min_len = min_len, max_len = max_len},
		produce = proc(t: ^T, input: Dict_Input(Key_Input, Key, Value_Input, Value)) -> map[Key]Value {
			max_len := input.max_len
			if max_len < input.min_len {
				max_len = math.max(input.min_len, t.size)
			}

			target_len := input.min_len + int(choice(t, u64(max_len - input.min_len + 1)))
			values := make(map[Key]Value, target_len, t.value_allocator)
			max_attempts := target_len * 4 + 8
			for len(values) < target_len && max_attempts > 0 {
				values[draw(t, input.key)] = draw(t, input.value)
				max_attempts -= 1
			}
			return values
		},
	}
}

Map_Input :: struct(Gen_Input: typeid, Value: typeid, Mapped: typeid) {
	gen: Gen(Gen_Input, Value),
	f:   proc(value: Value) -> Mapped,
}

map_gen :: proc(gen: Gen($Gen_Input, $Value), f: proc(value: Value) -> $Mapped) -> Gen(Map_Input(Gen_Input, Value, Mapped), Mapped) {
	return {
		input = {gen = gen, f = f},
		produce = proc(t: ^T, input: Map_Input(Gen_Input, Value, Mapped)) -> Mapped {
			return input.f(draw(t, input.gen))
		},
	}
}

Bind_Input :: struct(Gen_Input: typeid, Value: typeid, Next_Input: typeid, Next: typeid) {
	gen: Gen(Gen_Input, Value),
	f:   proc(value: Value) -> Gen(Next_Input, Next),
}

bind :: proc(gen: Gen($Gen_Input, $Value), f: proc(value: Value) -> Gen($Next_Input, $Next)) -> Gen(Bind_Input(Gen_Input, Value, Next_Input, Next), Next) {
	return {
		input = {gen = gen, f = f},
		produce = proc(t: ^T, input: Bind_Input(Gen_Input, Value, Next_Input, Next)) -> Next {
			next := input.f(draw(t, input.gen))
			return draw(t, next)
		},
	}
}

Sized_Input :: struct(Gen_Input: typeid, Value: typeid) {
	f: proc(size: int) -> Gen(Gen_Input, Value),
}

sized :: proc(f: proc(size: int) -> Gen($Gen_Input, $Value)) -> Gen(Sized_Input(Gen_Input, Value), Value) {
	return {
		input = {f = f},
		produce = proc(t: ^T, input: Sized_Input(Gen_Input, Value)) -> Value {
			return draw(t, input.f(t.size))
		},
	}
}

Resize_Input :: struct(Gen_Input: typeid, Value: typeid) {
	gen:  Gen(Gen_Input, Value),
	size: int,
}

resize :: proc(gen: Gen($Gen_Input, $Value), size: int) -> Gen(Resize_Input(Gen_Input, Value), Value) {
	return {
		input = {gen = gen, size = size},
		produce = proc(t: ^T, input: Resize_Input(Gen_Input, Value)) -> Value {
			previous := t.size
			t.size = input.size
			value := draw(t, input.gen)
			t.size = previous
			return value
		},
	}
}

Scale_Input :: struct(Gen_Input: typeid, Value: typeid) {
	gen: Gen(Gen_Input, Value),
	f:   proc(size: int) -> int,
}

scale :: proc(gen: Gen($Gen_Input, $Value), f: proc(size: int) -> int) -> Gen(Scale_Input(Gen_Input, Value), Value) {
	return {
		input = {gen = gen, f = f},
		produce = proc(t: ^T, input: Scale_Input(Gen_Input, Value)) -> Value {
			previous := t.size
			t.size = input.f(t.size)
			value := draw(t, input.gen)
			t.size = previous
			return value
		},
	}
}

smaller_size :: proc(size: int) -> int {
	return size / 2
}

smaller :: proc(gen: Gen($Gen_Input, $Value)) -> Gen(Scale_Input(Gen_Input, Value), Value) {
	return scale(gen, smaller_size)
}

Such_That_Input :: struct(Gen_Input: typeid, Value: typeid) {
	gen:       Gen(Gen_Input, Value),
	predicate: proc(value: Value) -> bool,
	max_tries: int,
}

such_that :: proc(gen: Gen($Gen_Input, $Value), predicate: proc(value: Value) -> bool, max_tries: int = 100) -> Gen(Such_That_Input(Gen_Input, Value), Value) {
	return {
		input = {gen = gen, predicate = predicate, max_tries = max_tries},
		produce = proc(t: ^T, input: Such_That_Input(Gen_Input, Value)) -> Value {
			max_tries := input.max_tries
			if max_tries <= 0 {
				max_tries = 100
			}

			last: Value
			for _ in 0 ..< max_tries {
				last = draw(t, input.gen)
				if input.predicate(last) {
					return last
				}
			}

			t.force_discard = true
			t.discard_message = "such_that predicate did not match"
			return last
		},
	}
}
