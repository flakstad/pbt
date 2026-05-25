package main

import "core:fmt"
import "core:os"

import pbt "../../pbt"

UNIT_TAGS := [?]string{"starter", "unit"}
PROTOCOL_TAGS := [?]string{"starter", "external", "protocol"}

reverse_twice_property :: proc(t: ^pbt.T) -> pbt.Result {
	value := pbt.draw(t, pbt.string_alphabet("abcdefghijklmnopqrstuvwxyz0123456789-_", 0, 32))
	return pbt.equal(reverse_string(reverse_string(value)), value)
}

line_protocol_echo_property :: proc(t: ^pbt.T) -> pbt.Result {
	command := [?]string {
		"/bin/sh",
		"-c",
		"while IFS= read -r line; do printf \"%s\\n\" \"$line\"; done",
	}
	client, err := pbt.line_protocol_start(command[:])
	if err != nil {
		return pbt.error(fmt.tprintf("could not start line protocol target: %v", err))
	}
	defer pbt.line_protocol_stop(&client)

	ops := [?]string{"echo"}
	fields := [?]pbt.JSON_Field_ASCII {
		pbt.json_string_enum_field_ascii("op", ops[:]),
		pbt.json_string_field_ascii("value", 32),
	}
	request := pbt.draw(t, pbt.json_object_schema_ascii(fields[:]))
	response := pbt.line_protocol_call_with_options(t, &client, request, {
		timeout_ms = 500,
		max_response_bytes = 4096,
	})
	if !response.success {
		return pbt.fail(response.error)
	}
	return pbt.equal(response.response, request)
}

main :: proc() {
	properties := [?]pbt.Property_Case {
		{name = "reverse twice", property = reverse_twice_property, description = "pure starter property", tags = UNIT_TAGS[:]},
		{name = "line protocol echoes json", property = line_protocol_echo_property, description = "persistent wrapper starter property", tags = PROTOCOL_TAGS[:]},
	}

	pbt.run_cli(properties[:], os.args[1:], {shrink = true})
}

reverse_string :: proc(value: string) -> string {
	bytes := make([]byte, len(value), context.temp_allocator)
	for i := 0; i < len(value); i += 1 {
		bytes[i] = value[len(value) - 1 - i]
	}
	return string(bytes)
}
