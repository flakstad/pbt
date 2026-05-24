package main

import "core:fmt"
import "core:os"

import pbt "../../pbt"
import sc "../../../statecharts"

Door_State :: enum {
	Closed,
	Open,
	Locked,
}

Door_Event :: enum {
	Open,
	Close,
	Lock,
	Unlock,
}

Door_Target :: struct {
	state: Door_State,
}

Door_Context :: struct {
	chart:  sc.Chart(Door_State, Door_Event),
	model:  sc.Instance(Door_State, Door_Event),
	target: Door_Target,
}

Door_Observation :: struct {
	target_state: Door_State,
	model_state:  Door_State,
}

DOOR_STATES := [?]sc.State_Def(Door_State) {
	{id = .Closed},
	{id = .Open},
	{id = .Locked},
}

DOOR_TRANSITIONS := [?]sc.Transition_Def(Door_State, Door_Event) {
	{source = .Closed, target = .Open, trigger = .Open},
	{source = .Open, target = .Closed, trigger = .Close},
	{source = .Closed, target = .Locked, trigger = .Lock},
	{source = .Locked, target = .Closed, trigger = .Unlock},
}

door_property :: proc(t: ^pbt.T) -> pbt.Result {
	ctx: Door_Context
	if !door_context_init(&ctx) {
		return pbt.error("could not initialize door statechart")
	}
	defer door_context_destroy(&ctx)

	model := pbt.State_Model(^Door_Context, Door_Event, Door_Observation) {
		target = &ctx,
		initial = door_initial,
		command = door_command,
		run = door_run,
		next_state = door_next_state,
		postcondition = door_postcondition,
		command_name = door_event_name,
	}
	return pbt.run_commands(t, model, {min_len = 1, max_len = 20})
}

main :: proc() {
	properties := [?]pbt.Property_Case {
		{name = "door statechart", property = door_property},
	}

	args := os.args[1:]
	if pbt.has_list_properties_flag(args) {
		json := pbt.properties_json(properties[:])
		fmt.println(json)
		delete(json)
		os.exit(0)
	}

	result := pbt.check_property_from_args(properties[:], args, {shrink = true})
	pbt.print_check_result_json(result)
	exit_code := pbt.check_result_exit_code(result)
	pbt.destroy_check_result(&result)
	os.exit(exit_code)
}

door_context_init :: proc(ctx: ^Door_Context) -> bool {
	def := sc.Chart_Def(Door_State, Door_Event) {
		initial = .Closed,
		states = DOOR_STATES[:],
		transitions = DOOR_TRANSITIONS[:],
	}

	compile_result := sc.compile(&ctx.chart, def)
	defer sc.destroy_compile_result(&compile_result)
	if !compile_result.ok {
		return false
	}

	if !sc.init(&ctx.model, &ctx.chart) {
		return false
	}

	initial := sc.enter_initial(&ctx.model)
	defer sc.destroy_dispatch_result(&initial)
	if initial.status != .Transitioned {
		return false
	}

	ctx.target.state = .Closed
	return true
}

door_context_destroy :: proc(ctx: ^Door_Context) {
	sc.destroy_instance(&ctx.model)
	sc.destroy_chart(&ctx.chart)
}

door_initial :: proc(t: ^pbt.T, target: rawptr) -> ^Door_Context {
	return cast(^Door_Context)target
}

door_command :: proc(t: ^pbt.T, state: ^Door_Context) -> Door_Event {
	return Door_Event(pbt.draw(t, pbt.int_range(0, 3)))
}

door_run :: proc(t: ^pbt.T, target: rawptr, state: ^Door_Context, command: Door_Event) -> Door_Observation {
	ctx := cast(^Door_Context)target

	dispatch_result := sc.dispatch(&ctx.model, sc.Event(Door_Event){id = command})
	defer sc.destroy_dispatch_result(&dispatch_result)
	if dispatch_result.status == .Transitioned {
		pbt.record_event(t, "statechart", door_event_name(command), "transitioned", fmt.tprintf("%v -> %v", dispatch_result.source, dispatch_result.target))
	} else {
		pbt.record_event(t, "statechart", door_event_name(command), "ignored", fmt.tprintf("%v", dispatch_result.status))
	}

	door_target_apply_buggy(&ctx.target, command)

	return {
		target_state = ctx.target.state,
		model_state = door_model_state(ctx),
	}
}

door_next_state :: proc(state: ^Door_Context, command: Door_Event, value: Door_Observation) -> ^Door_Context {
	return state
}

door_postcondition :: proc(state: ^Door_Context, command: Door_Event, value: Door_Observation) -> pbt.Result {
	return pbt.assert(value.target_state == value.model_state, fmt.tprintf("target=%v model=%v", value.target_state, value.model_state))
}

door_event_name :: proc(command: Door_Event) -> string {
	switch command {
	case .Open:
		return "open"
	case .Close:
		return "close"
	case .Lock:
		return "lock"
	case .Unlock:
		return "unlock"
	}
	return "unknown"
}

door_model_state :: proc(ctx: ^Door_Context) -> Door_State {
	if sc.is_active(&ctx.model, Door_State.Open) {
		return .Open
	}
	if sc.is_active(&ctx.model, Door_State.Locked) {
		return .Locked
	}
	return .Closed
}

door_target_apply_buggy :: proc(target: ^Door_Target, command: Door_Event) {
	switch command {
	case .Open:
		if target.state == .Closed {
			target.state = .Open
		}
	case .Close:
		if target.state == .Open {
			target.state = .Closed
		}
	case .Lock:
		// Intentional bug: locking a closed door leaves the target closed.
		if target.state == .Closed {
			target.state = .Closed
		}
	case .Unlock:
		if target.state == .Locked {
			target.state = .Closed
		}
	}
}
