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

Byte_Range_Input :: struct {
	min: byte,
	max: byte,
}

byte_range :: proc(min: byte = 0, max: byte = 255) -> Gen(Byte_Range_Input, byte) {
	return {
		input = {min = min, max = max},
		produce = proc(t: ^T, input: Byte_Range_Input) -> byte {
			min := int(input.min)
			max := int(input.max)
			if max <= min {
				return input.min
			}

			return byte(min + int(choice(t, u64(max - min + 1))))
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

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			length := input.min_len + int(choice(t, u64(max_len - input.min_len + 1)))
			element_ends: []int
			if t.capture_shrink_hints && length > input.min_len {
				element_ends = make([]int, length + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			values := make([]Value, length, t.value_allocator)
			for i in 0 ..< length {
				values[i] = draw(t, input.elem)
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, input.min_len, length, element_ends)
			}
			return values
		},
	}
}

non_empty_array :: proc(elem: Gen($Gen_Input, $Value), max_len: int = -1) -> Gen(Array_Input(Gen_Input, Value), []Value) {
	return array(elem, 1, max_len)
}

Byte_Array_Input :: struct {
	min_len: int,
	max_len: int,
	min:     byte,
	max:     byte,
}

byte_array :: proc(min_len: int = 0, max_len: int = -1, min: byte = 0, max: byte = 255) -> Gen(Byte_Array_Input, []byte) {
	return {
		input = {min_len = min_len, max_len = max_len, min = min, max = max},
		produce = proc(t: ^T, input: Byte_Array_Input) -> []byte {
			max_len := input.max_len
			if max_len < input.min_len {
				max_len = math.max(input.min_len, t.size)
			}

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			length := input.min_len + int(choice(t, u64(max_len - input.min_len + 1)))
			element_ends: []int
			if t.capture_shrink_hints && length > input.min_len {
				element_ends = make([]int, length + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			values := make([]byte, length, t.value_allocator)
			elem := byte_range(input.min, input.max)
			for i in 0 ..< length {
				values[i] = draw(t, elem)
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, input.min_len, length, element_ends)
			}
			return values
		},
	}
}

non_empty_byte_array :: proc(max_len: int = -1, min: byte = 0, max: byte = 255) -> Gen(Byte_Array_Input, []byte) {
	return byte_array(1, max_len, min, max)
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

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			length := input.min_len + int(choice(t, u64(max_len - input.min_len + 1)))
			element_ends: []int
			if t.capture_shrink_hints && length > input.min_len {
				element_ends = make([]int, length + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			bytes := make([]byte, length, t.value_allocator)
			for i in 0 ..< length {
				bytes[i] = byte(32 + choice(t, 95))
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, input.min_len, length, element_ends)
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

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			length := input.min_len + int(choice(t, u64(max_len - input.min_len + 1)))
			element_ends: []int
			if t.capture_shrink_hints && length > input.min_len {
				element_ends = make([]int, length + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			bytes := make([]byte, length, t.value_allocator)
			for i in 0 ..< length {
				index := int(choice(t, u64(len(input.alphabet))))
				bytes[i] = input.alphabet[index]
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, input.min_len, length, element_ends)
			}
			return string(bytes)
		},
	}
}

non_empty_string_alphabet :: proc(alphabet: string, max_len: int = -1) -> Gen(String_Alphabet_Input, string) {
	return string_alphabet(alphabet, 1, max_len)
}

Hex_String_Input :: struct {
	min_bytes: int,
	max_bytes: int,
	uppercase: bool,
}

hex_string :: proc(min_bytes: int = 0, max_bytes: int = -1, uppercase: bool = false) -> Gen(Hex_String_Input, string) {
	return {
		input = {min_bytes = min_bytes, max_bytes = max_bytes, uppercase = uppercase},
		produce = proc(t: ^T, input: Hex_String_Input) -> string {
			max_bytes := input.max_bytes
			if max_bytes < input.min_bytes {
				max_bytes = math.max(input.min_bytes, t.size)
			}

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			byte_count := input.min_bytes + int(choice(t, u64(max_bytes - input.min_bytes + 1)))
			element_ends: []int
			if t.capture_shrink_hints && byte_count > input.min_bytes {
				element_ends = make([]int, byte_count + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			table := "0123456789abcdef"
			if input.uppercase {
				table = "0123456789ABCDEF"
			}
			values := make([]byte, byte_count * 2, t.value_allocator)
			for i in 0 ..< byte_count {
				value := byte(choice(t, 256))
				values[i * 2] = table[value >> 4]
				values[i * 2 + 1] = table[value & 0x0f]
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, input.min_bytes, byte_count, element_ends)
			}
			return string(values)
		},
	}
}

non_empty_hex_string :: proc(max_bytes: int = -1, uppercase: bool = false) -> Gen(Hex_String_Input, string) {
	return hex_string(1, max_bytes, uppercase)
}

Identifier_ASCII_Input :: struct {
	min_len: int,
	max_len: int,
}

identifier_ascii :: proc(min_len: int = 1, max_len: int = -1) -> Gen(Identifier_ASCII_Input, string) {
	return {
		input = {min_len = min_len, max_len = max_len},
		produce = proc(t: ^T, input: Identifier_ASCII_Input) -> string {
			min_len := input.min_len
			if min_len < 1 {
				min_len = 1
			}
			max_len := input.max_len
			if max_len < min_len {
				max_len = math.max(min_len, t.size)
			}

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			length := min_len + int(choice(t, u64(max_len - min_len + 1)))
			element_ends: []int
			if t.capture_shrink_hints && length > min_len {
				element_ends = make([]int, length + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			first_chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_"
			rest_chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
			values := make([]byte, length, t.value_allocator)
			first_index := int(choice(t, u64(len(first_chars))))
			values[0] = first_chars[first_index]
			if len(element_ends) > 0 {
				element_ends[1] = choice_cursor(t)
			}
			for i in 1 ..< length {
				index := int(choice(t, u64(len(rest_chars))))
				values[i] = rest_chars[index]
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, min_len, length, element_ends)
			}
			return string(values)
		},
	}
}

Path_Segment_ASCII_Input :: struct {
	min_len: int,
	max_len: int,
}

path_segment_ascii :: proc(min_len: int = 1, max_len: int = -1) -> Gen(Path_Segment_ASCII_Input, string) {
	return {
		input = {min_len = min_len, max_len = max_len},
		produce = proc(t: ^T, input: Path_Segment_ASCII_Input) -> string {
			min_len := input.min_len
			if min_len < 1 {
				min_len = 1
			}
			max_len := input.max_len
			if max_len < min_len {
				max_len = math.max(min_len, t.size)
			}

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			length := min_len + int(choice(t, u64(max_len - min_len + 1)))
			element_ends: []int
			if t.capture_shrink_hints && length > min_len {
				element_ends = make([]int, length + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			first_chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
			rest_chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
			values := make([]byte, length, t.value_allocator)
			first_index := int(choice(t, u64(len(first_chars))))
			values[0] = first_chars[first_index]
			if len(element_ends) > 0 {
				element_ends[1] = choice_cursor(t)
			}
			for i in 1 ..< length {
				index := int(choice(t, u64(len(rest_chars))))
				values[i] = rest_chars[index]
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, min_len, length, element_ends)
			}
			return string(values)
		},
	}
}

HTTP_Method_Input :: struct {}

http_method :: proc() -> Gen(HTTP_Method_Input, string) {
	return {
		input = {},
		produce = proc(t: ^T, _: HTTP_Method_Input) -> string {
			switch choice(t, 7) {
			case 0:
				return "GET"
			case 1:
				return "POST"
			case 2:
				return "PUT"
			case 3:
				return "PATCH"
			case 4:
				return "DELETE"
			case 5:
				return "HEAD"
			}
			return "OPTIONS"
		},
	}
}

HTTP_Status_Code_Input :: struct {
	min: int,
	max: int,
}

http_status_code :: proc(min: int = 100, max: int = 599) -> Gen(HTTP_Status_Code_Input, int) {
	return {
		input = {min = min, max = max},
		produce = proc(t: ^T, input: HTTP_Status_Code_Input) -> int {
			min := input.min
			max := input.max
			if min < 100 {
				min = 100
			}
			if max > 599 {
				max = 599
			}
			if max <= min {
				return min
			}
			return min + int(choice(t, u64(max - min + 1)))
		},
	}
}

HTTP_Header_Name_ASCII_Input :: struct {
	min_len: int,
	max_len: int,
}

http_header_name_ascii :: proc(min_len: int = 1, max_len: int = -1) -> Gen(HTTP_Header_Name_ASCII_Input, string) {
	return {
		input = {min_len = min_len, max_len = max_len},
		produce = proc(t: ^T, input: HTTP_Header_Name_ASCII_Input) -> string {
			min_len := input.min_len
			if min_len < 1 {
				min_len = 1
			}
			max_len := input.max_len
			if max_len < min_len {
				max_len = math.max(min_len, t.size)
			}

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			length := min_len + int(choice(t, u64(max_len - min_len + 1)))
			element_ends: []int
			if t.capture_shrink_hints && length > min_len {
				element_ends = make([]int, length + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			token_chars := "!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
			values := make([]byte, length, t.value_allocator)
			for i in 0 ..< length {
				index := int(choice(t, u64(len(token_chars))))
				values[i] = token_chars[index]
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, min_len, length, element_ends)
			}
			return string(values)
		},
	}
}

URL_Path_ASCII_Input :: struct {
	min_segments: int,
	max_segments: int,
	min_segment_len: int,
	max_segment_len: int,
}

url_path_ascii :: proc(min_segments: int = 1, max_segments: int = -1, min_segment_len: int = 1, max_segment_len: int = -1) -> Gen(URL_Path_ASCII_Input, string) {
	return {
		input = {min_segments = min_segments, max_segments = max_segments, min_segment_len = min_segment_len, max_segment_len = max_segment_len},
		produce = proc(t: ^T, input: URL_Path_ASCII_Input) -> string {
			min_segments := input.min_segments
			if min_segments < 0 {
				min_segments = 0
			}
			max_segments := input.max_segments
			if max_segments < min_segments {
				max_segments = math.max(min_segments, t.size)
			}
			min_segment_len := input.min_segment_len
			if min_segment_len < 1 {
				min_segment_len = 1
			}
			max_segment_len := input.max_segment_len
			if max_segment_len < min_segment_len {
				max_segment_len = math.max(min_segment_len, t.size)
			}

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			segment_count := min_segments + int(choice(t, u64(max_segments - min_segments + 1)))
			element_ends: []int
			if t.capture_shrink_hints && segment_count > min_segments {
				element_ends = make([]int, segment_count + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			values := make([dynamic]byte, 0, 1 + segment_count * (max_segment_len + 1), t.value_allocator)
			append(&values, '/')
			segment := path_segment_ascii(min_segment_len, max_segment_len)
			for i in 0 ..< segment_count {
				if i > 0 {
					append(&values, '/')
				}
				part := draw(t, segment)
				for ch in part {
					append(&values, byte(ch))
				}
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, min_segments, segment_count, element_ends)
			}
			return string(values[:])
		},
	}
}

Query_Component_ASCII_Input :: struct {
	min_len: int,
	max_len: int,
}

query_component_ascii :: proc(min_len: int = 0, max_len: int = -1) -> Gen(Query_Component_ASCII_Input, string) {
	return {
		input = {min_len = min_len, max_len = max_len},
		produce = proc(t: ^T, input: Query_Component_ASCII_Input) -> string {
			min_len := input.min_len
			if min_len < 0 {
				min_len = 0
			}
			max_len := input.max_len
			if max_len < min_len {
				max_len = math.max(min_len, t.size)
			}

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			length := min_len + int(choice(t, u64(max_len - min_len + 1)))
			element_ends: []int
			if t.capture_shrink_hints && length > min_len {
				element_ends = make([]int, length + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
			values := make([]byte, length, t.value_allocator)
			for i in 0 ..< length {
				index := int(choice(t, u64(len(chars))))
				values[i] = chars[index]
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, min_len, length, element_ends)
			}
			return string(values)
		},
	}
}

non_empty_query_component_ascii :: proc(max_len: int = -1) -> Gen(Query_Component_ASCII_Input, string) {
	return query_component_ascii(1, max_len)
}

JSON_String_Literal_ASCII_Input :: struct {
	min_len: int,
	max_len: int,
}

json_string_literal_ascii :: proc(min_len: int = 0, max_len: int = -1) -> Gen(JSON_String_Literal_ASCII_Input, string) {
	return {
		input = {min_len = min_len, max_len = max_len},
		produce = proc(t: ^T, input: JSON_String_Literal_ASCII_Input) -> string {
			min_len := input.min_len
			if min_len < 0 {
				min_len = 0
			}
			max_len := input.max_len
			if max_len < min_len {
				max_len = math.max(min_len, t.size)
			}

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			length := min_len + int(choice(t, u64(max_len - min_len + 1)))
			element_ends: []int
			if t.capture_shrink_hints && length > min_len {
				element_ends = make([]int, length + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 _-."
			values := make([]byte, length + 2, t.value_allocator)
			values[0] = '"'
			for i in 0 ..< length {
				index := int(choice(t, u64(len(chars))))
				values[i + 1] = chars[index]
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			values[len(values) - 1] = '"'
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, min_len, length, element_ends)
			}
			return string(values)
		},
	}
}

JSON_Bool_Literal_Input :: struct {}

json_bool_literal :: proc() -> Gen(JSON_Bool_Literal_Input, string) {
	return {
		input = {},
		produce = proc(t: ^T, _: JSON_Bool_Literal_Input) -> string {
			if draw(t, boolean()) {
				return "true"
			}
			return "false"
		},
	}
}

JSON_Int_Literal_Input :: struct {
	min: int,
	max: int,
}

json_int_literal :: proc(min: int = -1000, max: int = 1000) -> Gen(JSON_Int_Literal_Input, string) {
	return {
		input = {min = min, max = max},
		produce = proc(t: ^T, input: JSON_Int_Literal_Input) -> string {
			value := draw(t, int_range(input.min, input.max))
			values := make([dynamic]byte, 0, 24, t.value_allocator)
			append_int_decimal(&values, value)
			return string(values[:])
		},
	}
}

JSON_Object_ASCII_Input :: struct {
	min_fields:     int,
	max_fields:     int,
	max_key_len:    int,
	max_string_len: int,
}

json_object_ascii :: proc(min_fields: int = 0, max_fields: int = -1, max_key_len: int = 12, max_string_len: int = 16) -> Gen(JSON_Object_ASCII_Input, string) {
	return {
		input = {min_fields = min_fields, max_fields = max_fields, max_key_len = max_key_len, max_string_len = max_string_len},
		produce = proc(t: ^T, input: JSON_Object_ASCII_Input) -> string {
			min_fields := input.min_fields
			if min_fields < 0 {
				min_fields = 0
			}
			max_fields := input.max_fields
			if max_fields < min_fields {
				max_fields = math.max(min_fields, t.size)
			}
			max_key_len := input.max_key_len
			if max_key_len < 1 {
				max_key_len = 1
			}
			max_string_len := input.max_string_len
			if max_string_len < 0 {
				max_string_len = 0
			}

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			field_count := min_fields + int(choice(t, u64(max_fields - min_fields + 1)))
			element_ends: []int
			if t.capture_shrink_hints && field_count > min_fields {
				element_ends = make([]int, field_count + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			values := make([dynamic]byte, 0, 2 + field_count * (max_key_len + max_string_len + 8), t.value_allocator)
			append(&values, '{')
			key_gen := identifier_ascii(1, max_key_len)
			string_gen := json_string_literal_ascii(0, max_string_len)
			int_gen := json_int_literal()
			for i in 0 ..< field_count {
				if i > 0 {
					append(&values, ',')
				}
				key := draw(t, key_gen)
				append_json_quoted_content(&values, key)
				append(&values, ':')
				append_json_simple_value(t, &values, string_gen, int_gen)
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			append(&values, '}')
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, min_fields, field_count, element_ends)
			}
			return string(values[:])
		},
	}
}

JSON_Object_Fields_ASCII_Input :: struct {
	fields:         []string,
	max_string_len: int,
}

json_object_fields_ascii :: proc(fields: []string, max_string_len: int = 16) -> Gen(JSON_Object_Fields_ASCII_Input, string) {
	return {
		input = {fields = fields, max_string_len = max_string_len},
		produce = proc(t: ^T, input: JSON_Object_Fields_ASCII_Input) -> string {
			max_string_len := input.max_string_len
			if max_string_len < 0 {
				max_string_len = 0
			}

			values := make([dynamic]byte, 0, 2 + len(input.fields) * (max_string_len + 12), t.value_allocator)
			append(&values, '{')
			string_gen := json_string_literal_ascii(0, max_string_len)
			int_gen := json_int_literal()
			for field, i in input.fields {
				if i > 0 {
					append(&values, ',')
				}
				append_json_quoted_ascii_content(&values, field)
				append(&values, ':')
				append_json_simple_value(t, &values, string_gen, int_gen)
			}
			append(&values, '}')
			return string(values[:])
		},
	}
}

JSON_Object_Field_Subset_ASCII_Input :: struct {
	fields:         []string,
	min_fields:     int,
	max_fields:     int,
	max_string_len: int,
}

json_object_field_subset_ascii :: proc(fields: []string, min_fields: int = 0, max_fields: int = -1, max_string_len: int = 16) -> Gen(JSON_Object_Field_Subset_ASCII_Input, string) {
	return {
		input = {fields = fields, min_fields = min_fields, max_fields = max_fields, max_string_len = max_string_len},
		produce = proc(t: ^T, input: JSON_Object_Field_Subset_ASCII_Input) -> string {
			min_fields := input.min_fields
			if min_fields < 0 {
				min_fields = 0
			}
			if min_fields > len(input.fields) {
				min_fields = len(input.fields)
			}
			max_fields := input.max_fields
			if max_fields < min_fields || max_fields > len(input.fields) {
				max_fields = len(input.fields)
			}
			max_string_len := input.max_string_len
			if max_string_len < 0 {
				max_string_len = 0
			}

			included := make([]bool, len(input.fields), t.value_allocator)
			included_count := 0
			for _, i in input.fields {
				if included_count < max_fields && draw(t, boolean()) {
					included[i] = true
					included_count += 1
				}
			}
			if included_count < min_fields {
				for _, i in input.fields {
					if !included[i] {
						included[i] = true
						included_count += 1
						if included_count >= min_fields {
							break
						}
					}
				}
			}

			values := make([dynamic]byte, 0, 2 + included_count * (max_string_len + 12), t.value_allocator)
			append(&values, '{')
			string_gen := json_string_literal_ascii(0, max_string_len)
			int_gen := json_int_literal()
			written := 0
			for field, i in input.fields {
				if !included[i] {
					continue
				}
				if written > 0 {
					append(&values, ',')
				}
				append_json_quoted_ascii_content(&values, field)
				append(&values, ':')
				append_json_simple_value(t, &values, string_gen, int_gen)
				written += 1
			}
			append(&values, '}')
			return string(values[:])
		},
	}
}

JSON_Value_Kind :: enum {
	String,
	Int,
	Bool,
	Null,
}

JSON_Field_ASCII :: struct {
	name:           string,
	kind:           JSON_Value_Kind,
	min_int:        int,
	max_int:        int,
	max_string_len: int,
}

json_string_field_ascii :: proc(name: string, max_string_len: int = 16) -> JSON_Field_ASCII {
	return {name = name, kind = .String, max_string_len = max_string_len}
}

json_int_field_ascii :: proc(name: string, min: int = -1000, max: int = 1000) -> JSON_Field_ASCII {
	return {name = name, kind = .Int, min_int = min, max_int = max}
}

json_bool_field_ascii :: proc(name: string) -> JSON_Field_ASCII {
	return {name = name, kind = .Bool}
}

json_null_field_ascii :: proc(name: string) -> JSON_Field_ASCII {
	return {name = name, kind = .Null}
}

JSON_Object_Schema_ASCII_Input :: struct {
	fields: []JSON_Field_ASCII,
}

json_object_schema_ascii :: proc(fields: []JSON_Field_ASCII) -> Gen(JSON_Object_Schema_ASCII_Input, string) {
	return {
		input = {fields = fields},
		produce = proc(t: ^T, input: JSON_Object_Schema_ASCII_Input) -> string {
			values := make([dynamic]byte, 0, 2 + len(input.fields) * 24, t.value_allocator)
			append(&values, '{')
			for field, i in input.fields {
				if i > 0 {
					append(&values, ',')
				}
				append_json_quoted_ascii_content(&values, field.name)
				append(&values, ':')
				append_json_schema_value(t, &values, field)
			}
			append(&values, '}')
			return string(values[:])
		},
	}
}

append_json_schema_value :: proc(t: ^T, dst: ^[dynamic]byte, field: JSON_Field_ASCII) {
	switch field.kind {
	case .String:
		max_string_len := field.max_string_len
		if max_string_len < 0 {
			max_string_len = 0
		}
		value := draw(t, json_string_literal_ascii(0, max_string_len))
		append_string_bytes(dst, value)
	case .Int:
		value := draw(t, json_int_literal(field.min_int, field.max_int))
		append_string_bytes(dst, value)
	case .Bool:
		value := draw(t, json_bool_literal())
		append_string_bytes(dst, value)
	case .Null:
		append_string_bytes(dst, "null")
	}
}

JSON_Array_ASCII_Input :: struct {
	min_items:      int,
	max_items:      int,
	max_string_len: int,
}

json_array_ascii :: proc(min_items: int = 0, max_items: int = -1, max_string_len: int = 16) -> Gen(JSON_Array_ASCII_Input, string) {
	return {
		input = {min_items = min_items, max_items = max_items, max_string_len = max_string_len},
		produce = proc(t: ^T, input: JSON_Array_ASCII_Input) -> string {
			min_items := input.min_items
			if min_items < 0 {
				min_items = 0
			}
			max_items := input.max_items
			if max_items < min_items {
				max_items = math.max(min_items, t.size)
			}
			max_string_len := input.max_string_len
			if max_string_len < 0 {
				max_string_len = 0
			}

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			item_count := min_items + int(choice(t, u64(max_items - min_items + 1)))
			element_ends: []int
			if t.capture_shrink_hints && item_count > min_items {
				element_ends = make([]int, item_count + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			values := make([dynamic]byte, 0, 2 + item_count * (max_string_len + 8), t.value_allocator)
			append(&values, '[')
			string_gen := json_string_literal_ascii(0, max_string_len)
			int_gen := json_int_literal()
			for i in 0 ..< item_count {
				if i > 0 {
					append(&values, ',')
				}
				append_json_simple_value(t, &values, string_gen, int_gen)
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			append(&values, ']')
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, min_items, item_count, element_ends)
			}
			return string(values[:])
		},
	}
}

append_json_simple_value :: proc(t: ^T, dst: ^[dynamic]byte, string_gen: Gen(JSON_String_Literal_ASCII_Input, string), int_gen: Gen(JSON_Int_Literal_Input, string)) {
	switch choice(t, 4) {
	case 0:
		value := draw(t, string_gen)
		append_string_bytes(dst, value)
	case 1:
		value := draw(t, json_bool_literal())
		append_string_bytes(dst, value)
	case 2:
		append_string_bytes(dst, "null")
	case 3:
		value := draw(t, int_gen)
		append_string_bytes(dst, value)
	}
}

append_int_decimal :: proc(dst: ^[dynamic]byte, value: int) {
	if value == 0 {
		append(dst, '0')
		return
	}

	n: u64
	if value < 0 {
		append(dst, '-')
		n = u64(-(value + 1)) + 1
	} else {
		n = u64(value)
	}

	digits: [20]byte
	count := 0
	for n > 0 {
		digits[count] = byte('0' + n % 10)
		n /= 10
		count += 1
	}
	for i := count; i > 0; i -= 1 {
		append(dst, digits[i - 1])
	}
}

append_json_quoted_content :: proc(dst: ^[dynamic]byte, value: string) {
	append(dst, '"')
	append_string_bytes(dst, value)
	append(dst, '"')
}

append_json_quoted_ascii_content :: proc(dst: ^[dynamic]byte, value: string) {
	append(dst, '"')
	for ch in value {
		switch ch {
		case '"':
			append_string_bytes(dst, "\\\"")
		case '\\':
			append_string_bytes(dst, "\\\\")
		case '\n':
			append_string_bytes(dst, "\\n")
		case '\r':
			append_string_bytes(dst, "\\r")
		case '\t':
			append_string_bytes(dst, "\\t")
		case:
			if ch >= 0x20 && ch <= 0x7e {
				append(dst, byte(ch))
			}
		}
	}
	append(dst, '"')
}

append_string_bytes :: proc(dst: ^[dynamic]byte, value: string) {
	for ch in value {
		append(dst, byte(ch))
	}
}

record_collection_shrink_hints :: proc(t: ^T, start, min_len, length: int, element_ends: []int) {
	if length <= min_len {
		return
	}

	record_collection_remove_range_hint(t, start, min_len, length, min_len, length - min_len, element_ends)
	if length - 1 > min_len {
		record_collection_remove_range_hint(t, start, min_len, length, length - 1, 1, element_ends)
	}
	record_collection_prefix_hint(t, start, min_len, length, element_ends)
	if length > 1 {
		record_collection_remove_range_hint(t, start, min_len, length, 0, 1, element_ends)
	}
}

record_collection_prefix_hint :: proc(t: ^T, start, min_len, length: int, element_ends: []int) {
	new_length := min_len
	if new_length == 0 && length > 0 {
		new_length = 1
	}
	remove_count := length - new_length
	record_collection_remove_range_hint(t, start, min_len, length, 0, remove_count, element_ends)
}

record_collection_remove_range_hint :: proc(t: ^T, start, min_len, length, remove_start, remove_count: int, element_ends: []int) {
	if remove_count <= 0 || remove_start < 0 || remove_start + remove_count > length {
		return
	}

	new_length := length - remove_count
	if new_length < min_len || new_length >= length {
		return
	}

	end := choice_cursor(t)
	retained_prefix_count := element_ends[remove_start] - element_ends[0]
	retained_suffix_count := element_ends[length] - element_ends[remove_start + remove_count]
	replacement := make([dynamic]u64, 0, 1 + retained_prefix_count + retained_suffix_count, t.value_allocator)
	append(&replacement, u64(new_length - min_len))
	append_choice_range(&replacement, t, element_ends[0], retained_prefix_count)
	append_choice_range(&replacement, t, element_ends[remove_start + remove_count], retained_suffix_count)
	record_choice_shrink_hint(t, start, end - start, replacement[:])
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

Tuple4 :: struct(First: typeid, Second: typeid, Third: typeid, Fourth: typeid) {
	first:  First,
	second: Second,
	third:  Third,
	fourth: Fourth,
}

Tuple4_Input :: struct(First_Input: typeid, First: typeid, Second_Input: typeid, Second: typeid, Third_Input: typeid, Third: typeid, Fourth_Input: typeid, Fourth: typeid) {
	first:  Gen(First_Input, First),
	second: Gen(Second_Input, Second),
	third:  Gen(Third_Input, Third),
	fourth: Gen(Fourth_Input, Fourth),
}

tuple4 :: proc(first: Gen($First_Input, $First), second: Gen($Second_Input, $Second), third: Gen($Third_Input, $Third), fourth: Gen($Fourth_Input, $Fourth)) -> Gen(Tuple4_Input(First_Input, First, Second_Input, Second, Third_Input, Third, Fourth_Input, Fourth), Tuple4(First, Second, Third, Fourth)) {
	return {
		input = {first = first, second = second, third = third, fourth = fourth},
		produce = proc(t: ^T, input: Tuple4_Input(First_Input, First, Second_Input, Second, Third_Input, Third, Fourth_Input, Fourth)) -> Tuple4(First, Second, Third, Fourth) {
			return {
				first = draw(t, input.first),
				second = draw(t, input.second),
				third = draw(t, input.third),
				fourth = draw(t, input.fourth),
			}
		},
	}
}

Tuple5 :: struct(First: typeid, Second: typeid, Third: typeid, Fourth: typeid, Fifth: typeid) {
	first:  First,
	second: Second,
	third:  Third,
	fourth: Fourth,
	fifth:  Fifth,
}

Tuple5_Input :: struct(First_Input: typeid, First: typeid, Second_Input: typeid, Second: typeid, Third_Input: typeid, Third: typeid, Fourth_Input: typeid, Fourth: typeid, Fifth_Input: typeid, Fifth: typeid) {
	first:  Gen(First_Input, First),
	second: Gen(Second_Input, Second),
	third:  Gen(Third_Input, Third),
	fourth: Gen(Fourth_Input, Fourth),
	fifth:  Gen(Fifth_Input, Fifth),
}

tuple5 :: proc(first: Gen($First_Input, $First), second: Gen($Second_Input, $Second), third: Gen($Third_Input, $Third), fourth: Gen($Fourth_Input, $Fourth), fifth: Gen($Fifth_Input, $Fifth)) -> Gen(Tuple5_Input(First_Input, First, Second_Input, Second, Third_Input, Third, Fourth_Input, Fourth, Fifth_Input, Fifth), Tuple5(First, Second, Third, Fourth, Fifth)) {
	return {
		input = {first = first, second = second, third = third, fourth = fourth, fifth = fifth},
		produce = proc(t: ^T, input: Tuple5_Input(First_Input, First, Second_Input, Second, Third_Input, Third, Fourth_Input, Fourth, Fifth_Input, Fifth)) -> Tuple5(First, Second, Third, Fourth, Fifth) {
			return {
				first = draw(t, input.first),
				second = draw(t, input.second),
				third = draw(t, input.third),
				fourth = draw(t, input.fourth),
				fifth = draw(t, input.fifth),
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

Map2_Input :: struct(First_Input: typeid, First: typeid, Second_Input: typeid, Second: typeid, Mapped: typeid) {
	first:  Gen(First_Input, First),
	second: Gen(Second_Input, Second),
	f:      proc(first: First, second: Second) -> Mapped,
}

map2 :: proc(first: Gen($First_Input, $First), second: Gen($Second_Input, $Second), f: proc(first: First, second: Second) -> $Mapped) -> Gen(Map2_Input(First_Input, First, Second_Input, Second, Mapped), Mapped) {
	return {
		input = {first = first, second = second, f = f},
		produce = proc(t: ^T, input: Map2_Input(First_Input, First, Second_Input, Second, Mapped)) -> Mapped {
			return input.f(draw(t, input.first), draw(t, input.second))
		},
	}
}

Map3_Input :: struct(First_Input: typeid, First: typeid, Second_Input: typeid, Second: typeid, Third_Input: typeid, Third: typeid, Mapped: typeid) {
	first:  Gen(First_Input, First),
	second: Gen(Second_Input, Second),
	third:  Gen(Third_Input, Third),
	f:      proc(first: First, second: Second, third: Third) -> Mapped,
}

map3 :: proc(first: Gen($First_Input, $First), second: Gen($Second_Input, $Second), third: Gen($Third_Input, $Third), f: proc(first: First, second: Second, third: Third) -> $Mapped) -> Gen(Map3_Input(First_Input, First, Second_Input, Second, Third_Input, Third, Mapped), Mapped) {
	return {
		input = {first = first, second = second, third = third, f = f},
		produce = proc(t: ^T, input: Map3_Input(First_Input, First, Second_Input, Second, Third_Input, Third, Mapped)) -> Mapped {
			return input.f(draw(t, input.first), draw(t, input.second), draw(t, input.third))
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

Lazy_Input :: struct(Gen_Input: typeid, Value: typeid) {
	f: proc() -> Gen(Gen_Input, Value),
}

lazy :: proc(f: proc() -> Gen($Gen_Input, $Value)) -> Gen(Lazy_Input(Gen_Input, Value), Value) {
	return {
		input = {f = f},
		produce = proc(t: ^T, input: Lazy_Input(Gen_Input, Value)) -> Value {
			return draw(t, input.f())
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

Clamp_Size_Input :: struct(Gen_Input: typeid, Value: typeid) {
	gen:     Gen(Gen_Input, Value),
	min_size: int,
	max_size: int,
}

clamp_size :: proc(gen: Gen($Gen_Input, $Value), min_size, max_size: int) -> Gen(Clamp_Size_Input(Gen_Input, Value), Value) {
	return {
		input = {gen = gen, min_size = min_size, max_size = max_size},
		produce = proc(t: ^T, input: Clamp_Size_Input(Gen_Input, Value)) -> Value {
			previous := t.size
			min_size := input.min_size
			max_size := input.max_size
			if min_size < 0 {
				min_size = 0
			}
			if max_size < min_size {
				max_size = min_size
			}
			if t.size < min_size {
				t.size = min_size
			} else if t.size > max_size {
				t.size = max_size
			}
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
