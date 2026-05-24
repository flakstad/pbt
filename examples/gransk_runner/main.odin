package main

import "core:fmt"
import "core:os"

import pbt "../../pbt"

STRING_TAGS := [?]string{"string", "unit"}
BOUNDARY_TAGS := [?]string{"integer", "shrinking"}

reverse_twice_property :: proc(t: ^pbt.T) -> pbt.Result {
	value := pbt.draw(t, pbt.string_alphabet("abcdef", 0, 20))
	reversed := reverse_string(value)
	round_tripped := reverse_string(reversed)

	return pbt.equal(round_tripped, value)
}

small_numbers_property :: proc(t: ^pbt.T) -> pbt.Result {
	value := pbt.draw(t, pbt.int_range(0, 100))
	return pbt.assert(value < 50, "generated value should stay below 50")
}

main :: proc() {
	properties := [?]pbt.Property_Case {
		{name = "reverse twice", property = reverse_twice_property, description = "reversing a string twice returns the original value", tags = STRING_TAGS[:]},
		{name = "small numbers", property = small_numbers_property, description = "intentional failing integer boundary example", tags = BOUNDARY_TAGS[:]},
	}

	args := os.args[1:]
	if pbt.has_list_properties_flag(args) {
		json := pbt.properties_json(properties[:])
		fmt.println(json)
		delete(json)
		os.exit(0)
	}

	result := pbt.check_property_from_args(properties[:], args, {shrink = true})
	pbt.print_check_result(result, pbt.use_json_output(args))
	exit_code := pbt.check_result_exit_code(result)
	pbt.destroy_check_result(&result)
	os.exit(exit_code)
}

reverse_string :: proc(value: string) -> string {
	bytes := make([]byte, len(value), context.temp_allocator)
	for i := 0; i < len(value); i += 1 {
		bytes[i] = value[len(value) - 1 - i]
	}
	return string(bytes)
}
