package pbt

import "core:fmt"

State_Model :: struct(State: typeid, Command: typeid, Value: typeid) {
	target: rawptr,

	initial: proc(t: ^T, target: rawptr) -> State,
	command: proc(t: ^T, state: State) -> Command,
	precondition: proc(state: State, command: Command) -> bool,
	run: proc(t: ^T, target: rawptr, state: State, command: Command) -> Value,
	next_state: proc(state: State, command: Command, value: Value) -> State,
	postcondition: proc(state: State, command: Command, value: Value) -> Result,
	invariant: proc(t: ^T, state: State) -> Result,
	command_name: proc(command: Command) -> string,
	state_detail: proc(state: State) -> string,
	value_detail: proc(value: Value) -> string,
}

State_Run_Options :: struct {
	min_len:                  int,
	max_len:                  int,
	max_precondition_retries: int,
}

state_run_options :: proc(options: State_Run_Options) -> State_Run_Options {
	o := options
	if o.min_len < 0 {
		o.min_len = 0
	}
	if o.max_len <= 0 {
		o.max_len = 100
	}
	if o.max_len < o.min_len {
		o.max_len = o.min_len
	}
	if o.max_precondition_retries <= 0 {
		o.max_precondition_retries = 100
	}
	return o
}

run_commands :: proc(t: ^T, model: State_Model($State, $Command, $Value), options: State_Run_Options = {}) -> Result {
	opts := state_run_options(options)

	state := model.initial(t, model.target)
	length := opts.min_len + int(choice(t, u64(opts.max_len - opts.min_len + 1)))

	if model.invariant != nil {
		invariant_result := model.invariant(t, state)
		if invariant_result.status != .Pass {
			if t.capture_events {
				record_event(t, "stateful", "initial invariant", status_string(invariant_result.status), invariant_result.message)
			}
			return invariant_result
		}
	}

	for step in 0 ..< length {
		command: Command
		found_command := false
		for attempt in 0 ..< opts.max_precondition_retries {
			command = model.command(t, state)
			if model.precondition == nil || model.precondition(state, command) {
				found_command = true
				break
			}
			if t.capture_events {
				record_event(t, "stateful", stateful_step_name(model, step, command, "precondition"), "discard", fmt.tprintf("attempt %d", attempt))
			}
		}

		if !found_command {
			return discard(fmt.tprintf("could not generate valid command at step %d", step))
		}

		state_before := state
		value := model.run(t, model.target, state, command)
		if model.postcondition != nil {
			post_result := model.postcondition(state, command, value)
			if post_result.status != .Pass {
				if t.capture_events {
					record_event(t, "stateful", stateful_step_name(model, step, command, "postcondition"), status_string(post_result.status), stateful_value_detail(model, state_before, value, post_result.message))
				}
				return post_result
			}
		}

		if model.next_state != nil {
			state = model.next_state(state, command, value)
		}

		if model.invariant != nil {
			invariant_result := model.invariant(t, state)
			if invariant_result.status != .Pass {
				if t.capture_events {
					record_event(t, "stateful", stateful_step_name(model, step, command, "invariant"), status_string(invariant_result.status), stateful_state_detail(model, state, invariant_result.message))
				}
				return invariant_result
			}
		}

		if t.capture_events {
			record_event(t, "stateful", stateful_step_name(model, step, command, ""), "ok", stateful_step_detail(model, state_before, value, state))
		}
	}

	return pass()
}

stateful_step_name :: proc(model: State_Model($State, $Command, $Value), step: int, command: Command, phase: string) -> string {
	command_name := ""
	if model.command_name != nil {
		command_name = model.command_name(command)
	}

	if command_name == "" {
		command_name = "command"
	}
	if phase == "" {
		return fmt.tprintf("step %d %s", step, command_name)
	}
	return fmt.tprintf("step %d %s %s", step, command_name, phase)
}

stateful_state_detail :: proc(model: State_Model($State, $Command, $Value), state: State, message: string) -> string {
	state_text := stateful_format_state(model, state)
	if state_text == "" {
		return message
	}
	if message == "" {
		return fmt.tprintf("state=%s", state_text)
	}
	return fmt.tprintf("state=%s message=%s", state_text, message)
}

stateful_value_detail :: proc(model: State_Model($State, $Command, $Value), state: State, value: Value, message: string) -> string {
	state_text := stateful_format_state(model, state)
	value_text := stateful_format_value(model, value)
	detail := stateful_join_state_value(state_text, value_text)
	if detail == "" {
		return message
	}
	if message == "" {
		return detail
	}
	return fmt.tprintf("%s message=%s", detail, message)
}

stateful_step_detail :: proc(model: State_Model($State, $Command, $Value), state_before: State, value: Value, state_after: State) -> string {
	state_before_text := stateful_format_state(model, state_before)
	value_text := stateful_format_value(model, value)
	state_after_text := stateful_format_state(model, state_after)
	if state_before_text == "" && value_text == "" && state_after_text == "" {
		return ""
	}
	detail := stateful_join_state_value(state_before_text, value_text)
	if state_after_text == "" {
		return detail
	}
	if detail == "" {
		return fmt.tprintf("next=%s", state_after_text)
	}
	return fmt.tprintf("%s next=%s", detail, state_after_text)
}

stateful_format_state :: proc(model: State_Model($State, $Command, $Value), state: State) -> string {
	if model.state_detail == nil {
		return ""
	}
	return model.state_detail(state)
}

stateful_format_value :: proc(model: State_Model($State, $Command, $Value), value: Value) -> string {
	if model.value_detail == nil {
		return ""
	}
	return model.value_detail(value)
}

stateful_join_state_value :: proc(state_text, value_text: string) -> string {
	if state_text == "" {
		if value_text == "" {
			return ""
		}
		return fmt.tprintf("value=%s", value_text)
	}
	if value_text == "" {
		return fmt.tprintf("state=%s", state_text)
	}
	return fmt.tprintf("state=%s value=%s", state_text, value_text)
}
