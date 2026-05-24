package pbt_statechart

import "core:fmt"

import pbt "../pbt"
import sc "../../statecharts/statecharts"

enabled_triggers :: proc(instance: ^sc.Instance($State, $Trigger), out: ^[dynamic]Trigger, ctx: rawptr = nil) -> bool {
	if out == nil {
		return false
	}
	clear(out)
	if instance == nil || instance.chart == nil {
		return false
	}

	for transition in instance.chart.def.transitions {
		if !sc.is_active(instance, transition.source) {
			continue
		}

		event := sc.Event(Trigger){id = transition.trigger}
		if transition.guard != nil && !transition.guard(ctx, &event) {
			continue
		}
		if trigger_contains(out^[:], transition.trigger) {
			continue
		}

		append(out, transition.trigger)
	}

	return len(out^) > 0
}

draw_enabled_trigger_or_discard :: proc(t: ^pbt.T, instance: ^sc.Instance($State, $Trigger), fallback: Trigger, ctx: rawptr = nil) -> Trigger {
	triggers := make([dynamic]Trigger, t.value_allocator)
	if !enabled_triggers(instance, &triggers, ctx) {
		t.force_discard = true
		t.discard_message = "statechart has no enabled triggers"
		return fallback
	}

	index := pbt.draw(t, pbt.int_range(0, len(triggers) - 1))
	return triggers[index]
}

dispatch_record :: proc(
	t: ^pbt.T,
	instance: ^sc.Instance($State, $Trigger),
	trigger: Trigger,
	name: proc(trigger: Trigger) -> string = nil,
	ctx: rawptr = nil,
) -> sc.Dispatch_Result(State) {
	result := sc.dispatch(instance, sc.Event(Trigger){id = trigger}, ctx)
	event_name := trigger_name(trigger, name)
	if result.status == .Transitioned {
		pbt.record_event(t, "statechart", event_name, dispatch_status_string(result.status), fmt.tprintf("%v -> %v", result.source, result.target))
	} else {
		pbt.record_event(t, "statechart", event_name, dispatch_status_string(result.status), "")
	}
	return result
}

trigger_contains :: proc(values: []$Trigger, target: Trigger) -> bool {
	for value in values {
		if value == target {
			return true
		}
	}
	return false
}

trigger_name :: proc(trigger: $Trigger, name: proc(trigger: Trigger) -> string = nil) -> string {
	if name != nil {
		return name(trigger)
	}
	return fmt.tprintf("%v", trigger)
}

dispatch_status_string :: proc(status: sc.Dispatch_Status) -> string {
	switch status {
	case .Ignored:
		return "ignored"
	case .Transitioned:
		return "transitioned"
	case .Blocked_By_Guard:
		return "blocked-by-guard"
	case .Conflict:
		return "conflict"
	case .Error:
		return "error"
	}
	return "unknown"
}
