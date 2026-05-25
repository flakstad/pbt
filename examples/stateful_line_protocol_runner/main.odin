package main

import "core:fmt"
import "core:os"
import "core:strconv"

import pbt "../../pbt"

STATEFUL_PROTOCOL_TAGS := [?]string{"stateful", "protocol", "process", "external"}

Counter_Command :: enum {
	Inc,
	Dec,
	Reset,
	Get,
}

Counter_Target :: struct {
	client: ^pbt.Line_Protocol_Client,
}

Counter_Observation :: struct {
	success: bool,
	actual:  int,
	raw:     string,
	error:   string,
}

counter_line_protocol_property :: proc(t: ^pbt.T) -> pbt.Result {
	command := [?]string {
		"/bin/sh",
		"-c",
		"n=0; while IFS= read -r line; do case \"$line\" in inc) n=$((n+1));; dec) n=$((n-1));; reset) n=0;; get) n=$n;; *) printf 'ERR unknown\\n'; continue;; esac; printf \"%d\\n\" \"$n\"; done",
	}
	client, err := pbt.line_protocol_start(command[:])
	if err != nil {
		return pbt.error(fmt.tprintf("could not start counter target: %v", err))
	}
	defer pbt.line_protocol_stop(&client)

	target := Counter_Target{client = &client}
	model := pbt.State_Model(int, Counter_Command, Counter_Observation) {
		target = &target,
		initial = counter_initial,
		command = counter_command,
		precondition = counter_precondition,
		run = counter_run,
		next_state = counter_next_state,
		postcondition = counter_postcondition,
		invariant = counter_invariant,
		command_name = counter_command_name,
		state_detail = counter_state_detail,
		value_detail = counter_value_detail,
	}
	return pbt.run_commands(t, model, {min_len = 1, max_len = 40, skip_success_events = true})
}

main :: proc() {
	properties := [?]pbt.Property_Case {
		{name = "line protocol counter stateful", property = counter_line_protocol_property, description = "stateful counter model checked through a persistent line protocol wrapper", tags = STATEFUL_PROTOCOL_TAGS[:]},
	}

	pbt.run_cli(properties[:], os.args[1:], {shrink = true})
}

counter_initial :: proc(t: ^pbt.T, target: rawptr) -> int {
	return 0
}

counter_command :: proc(t: ^pbt.T, state: int) -> Counter_Command {
	return pbt.draw(t, pbt.enum_range(Counter_Command.Inc, Counter_Command.Get))
}

counter_precondition :: proc(state: int, command: Counter_Command) -> bool {
	if command == .Dec {
		return state > 0
	}
	return true
}

counter_run :: proc(t: ^pbt.T, target: rawptr, state: int, command: Counter_Command) -> Counter_Observation {
	counter := cast(^Counter_Target)target
	response := pbt.line_protocol_call_with_options(t, counter.client, counter_command_name(command), {
		timeout_ms = 500,
		max_response_bytes = 1024,
	})
	if !response.success {
		return {success = false, error = response.error}
	}

	actual, ok := strconv.parse_int(response.response, 10)
	if !ok {
		return {success = false, raw = response.response, error = fmt.tprintf("target returned non-integer response %q", response.response)}
	}
	return {success = true, actual = actual, raw = response.response}
}

counter_next_state :: proc(state: int, command: Counter_Command, value: Counter_Observation) -> int {
	switch command {
	case .Inc:
		return state + 1
	case .Dec:
		return state - 1
	case .Reset:
		return 0
	case .Get:
		return state
	}
	return state
}

counter_postcondition :: proc(state: int, command: Counter_Command, value: Counter_Observation) -> pbt.Result {
	if !value.success {
		return pbt.fail(value.error)
	}
	expected := counter_next_state(state, command, value)
	return pbt.assert(value.actual == expected, fmt.tprintf("command=%s expected=%d actual=%d", counter_command_name(command), expected, value.actual))
}

counter_invariant :: proc(t: ^pbt.T, state: int) -> pbt.Result {
	return pbt.assert(state >= 0, "model counter should not be negative")
}

counter_command_name :: proc(command: Counter_Command) -> string {
	switch command {
	case .Inc:
		return "inc"
	case .Dec:
		return "dec"
	case .Reset:
		return "reset"
	case .Get:
		return "get"
	}
	return "unknown"
}

counter_state_detail :: proc(state: int) -> string {
	return fmt.tprintf("count=%d", state)
}

counter_value_detail :: proc(value: Counter_Observation) -> string {
	if !value.success {
		return fmt.tprintf("error=%s raw=%s", value.error, value.raw)
	}
	return fmt.tprintf("actual=%d", value.actual)
}
