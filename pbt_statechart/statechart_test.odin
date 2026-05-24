package pbt_statechart

import "core:strings"
import "core:testing"

import pbt "../pbt"
import sc "../../statecharts/statecharts"

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

@(test)
test_enabled_triggers_follow_active_state :: proc(t: ^testing.T) {
	chart: sc.Chart(Door_State, Door_Event)
	instance: sc.Instance(Door_State, Door_Event)
	ok := door_model_init(&chart, &instance)
	testing.expect(t, ok)
	defer sc.destroy_instance(&instance)
	defer sc.destroy_chart(&chart)

	triggers := make([dynamic]Door_Event)
	defer delete(triggers)

	testing.expect(t, enabled_triggers(&instance, &triggers))
	testing.expect(t, trigger_contains(triggers[:], Door_Event.Open))
	testing.expect(t, trigger_contains(triggers[:], Door_Event.Lock))
	testing.expect(t, !trigger_contains(triggers[:], Door_Event.Close))
	testing.expect(t, !trigger_contains(triggers[:], Door_Event.Unlock))
}

@(test)
test_dispatch_record_adds_statechart_event :: proc(t: ^testing.T) {
	chart: sc.Chart(Door_State, Door_Event)
	instance: sc.Instance(Door_State, Door_Event)
	ok := door_model_init(&chart, &instance)
	testing.expect(t, ok)
	defer sc.destroy_instance(&instance)
	defer sc.destroy_chart(&chart)

	ctx: pbt.T
	pbt.test_init(&ctx, 1, 1, nil, false, true)
	defer pbt.test_destroy(&ctx)

	result := dispatch_record(&ctx, &instance, Door_Event.Lock, door_event_name)
	defer sc.destroy_dispatch_result(&result)

	testing.expect_value(t, result.status, sc.Dispatch_Status.Transitioned)
	testing.expect(t, len(ctx.events) > 0)
	testing.expect_value(t, ctx.events[0].kind, "statechart")
	testing.expect_value(t, ctx.events[0].name, "lock")
	testing.expect_value(t, ctx.events[0].status, "transitioned")
	testing.expect(t, strings.contains(ctx.events[0].detail, "Closed -> Locked"))
}

door_model_init :: proc(chart: ^sc.Chart(Door_State, Door_Event), instance: ^sc.Instance(Door_State, Door_Event)) -> bool {
	def := sc.Chart_Def(Door_State, Door_Event) {
		initial = .Closed,
		states = DOOR_STATES[:],
		transitions = DOOR_TRANSITIONS[:],
	}
	compile_result := sc.compile(chart, def)
	defer sc.destroy_compile_result(&compile_result)
	if !compile_result.ok {
		return false
	}

	if !sc.init(instance, chart) {
		sc.destroy_chart(chart)
		return false
	}

	initial := sc.enter_initial(instance)
	defer sc.destroy_dispatch_result(&initial)
	if initial.status != .Transitioned {
		sc.destroy_instance(instance)
		sc.destroy_chart(chart)
		return false
	}

	return true
}

door_event_name :: proc(event: Door_Event) -> string {
	switch event {
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
