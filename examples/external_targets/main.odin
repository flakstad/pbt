package main

import "core:fmt"
import "core:os"

import pbt "../../pbt"

CLI_TAGS := [?]string{"external", "cli", "process"}
STDIN_TAGS := [?]string{"external", "protocol", "stdin"}

cli_uppercase_property :: proc(t: ^pbt.T) -> pbt.Result {
	value := pbt.draw(t, pbt.string_alphabet("abcdefghijklmnopqrstuvwxyz", 0, 24))
	command := [?]string {
		"/bin/sh",
		"-c",
		"printf \"%s\" \"$1\" | tr '[:lower:]' '[:upper:]'",
		"pbt-target",
		value,
	}

	result := pbt.process_run_with_options(t, command[:], {
		timeout_ms = 1_000,
		max_output_bytes = 4_096,
	})
	if !result.success {
		return process_failure(result)
	}

	return pbt.equal(result.stdout, ascii_upper(value))
}

stdin_echo_protocol_property :: proc(t: ^pbt.T) -> pbt.Result {
	ops := [?]string{"echo"}
	fields := [?]pbt.JSON_Field_ASCII {
		pbt.json_string_enum_field_ascii("op", ops[:]),
		pbt.json_string_field_ascii("value", 24),
	}
	request := pbt.draw(t, pbt.json_object_schema_ascii(fields[:]))
	command := [?]string{"/bin/sh", "-c", "cat"}

	result := pbt.protocol_stdin_call_with_options(t, command[:], request, {
		timeout_ms = 1_000,
		max_output_bytes = 4_096,
	})
	if !result.success {
		return process_failure(result)
	}

	return pbt.equal(result.stdout, request)
}

process_failure :: proc(result: pbt.Process_Result) -> pbt.Result {
	if result.error != "" {
		return pbt.fail(result.error)
	}
	if result.stderr != "" {
		return pbt.fail(result.stderr)
	}
	return pbt.fail(fmt.tprintf("target exited with %d", result.exit_code))
}

ascii_upper :: proc(value: string) -> string {
	bytes := make([]byte, len(value), context.temp_allocator)
	for i := 0; i < len(value); i += 1 {
		ch := value[i]
		if ch >= 'a' && ch <= 'z' {
			ch -= 'a' - 'A'
		}
		bytes[i] = ch
	}
	return string(bytes)
}

main :: proc() {
	properties := [?]pbt.Property_Case {
		{name = "cli uppercases argv", property = cli_uppercase_property, description = "generated argv value is uppercased by an external CLI target", tags = CLI_TAGS[:]},
		{name = "stdin protocol echoes json", property = stdin_echo_protocol_property, description = "generated JSON request is sent to a one-shot stdin protocol target", tags = STDIN_TAGS[:]},
	}

	pbt.run_cli(properties[:], os.args[1:], {shrink = true})
}
