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

		value := model.run(t, model.target, state, command)
		if model.postcondition != nil {
			post_result := model.postcondition(state, command, value)
			if post_result.status != .Pass {
				if t.capture_events {
					record_event(t, "stateful", stateful_step_name(model, step, command, "postcondition"), status_string(post_result.status), post_result.message)
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
					record_event(t, "stateful", stateful_step_name(model, step, command, "invariant"), status_string(invariant_result.status), invariant_result.message)
				}
				return invariant_result
			}
		}

		if t.capture_events {
			record_event(t, "stateful", stateful_step_name(model, step, command, ""), "ok", "")
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
