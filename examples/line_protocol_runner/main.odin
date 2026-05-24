package main

import "core:fmt"
import "core:os"
import "core:strconv"

import pbt "../../pbt"

PROTOCOL_TAGS := [?]string{"protocol", "process", "external"}

line_protocol_double_property :: proc(t: ^pbt.T) -> pbt.Result {
	command := [?]string {
		"/bin/sh",
		"-c",
		"while IFS= read -r line; do printf \"%d\\n\" $((line * 2)); done",
	}
	client, err := pbt.line_protocol_start(command[:])
	if err != nil {
		return pbt.error(fmt.tprintf("could not start line protocol target: %v", err))
	}
	defer pbt.line_protocol_stop(&client)

	values := pbt.draw(t, pbt.array(pbt.int_range(-100, 100), 1, 20))
	for value in values {
		response := pbt.line_protocol_call(t, &client, fmt.tprintf("%d", value))
		if !response.success {
			return pbt.fail(response.error)
		}

		actual, ok := strconv.parse_int(response.response, 10)
		if !ok {
			return pbt.fail(fmt.tprintf("target returned non-integer response %q", response.response))
		}

		expected := value * 2
		if actual != expected {
			return pbt.fail(fmt.tprintf("value=%d expected=%d actual=%d", value, expected, actual))
		}
	}

	return pbt.pass()
}

main :: proc() {
	properties := [?]pbt.Property_Case {
		{name = "line protocol doubles integers", property = line_protocol_double_property, description = "persistent subprocess protocol adapter doubles generated integers", tags = PROTOCOL_TAGS[:]},
	}

	pbt.run_cli(properties[:], os.args[1:], {shrink = true})
}
