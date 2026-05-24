package pbt

import "core:mem"
import "core:strings"

INLINE_CHOICE_CAP :: 32
VALUE_ARENA_BLOCK_SIZE :: 2048
VALUE_ARENA_OUT_OF_BAND_SIZE :: 2048
VALUE_ARENA_ALIGNMENT :: 64

T :: struct {
	allocator:       mem.Allocator,
	value_arena:     mem.Dynamic_Arena,
	value_allocator: mem.Allocator,
	rng:             Rng,
	size:            int,
	choice_inline:   [INLINE_CHOICE_CAP]u64,
	choice_count:    int,
	choice_extra:    [dynamic]u64,
	choice_marks:    [dynamic]Choice_Mark,
	capture_choice_marks: bool,
	events:          [dynamic]Event,
	capture_events:  bool,
	notes:           [dynamic]string,
	labels:          [dynamic]string,
	coverage_requirements: [dynamic]Coverage_Requirement,
	replay_choices:  []u64,
	replay_strict:   bool,
	replay_index:    int,
	replay_overrun: bool,
	force_discard:   bool,
	discard_message: string,
}

Test_Case :: struct {
	choices: [dynamic]u64,
	choice_marks: [dynamic]Choice_Mark,
	events:  [dynamic]Event,
	notes:   [dynamic]string,
	labels:  [dynamic]string,
	result:  Result,
}

Choice_Mark :: struct {
	index: int,
}

Event :: struct {
	kind:   string,
	name:   string,
	status: string,
	detail: string,
	kind_owned:   bool,
	name_owned:   bool,
	status_owned: bool,
	detail_owned: bool,
	kind_copy:    bool,
	name_copy:    bool,
	status_copy:  bool,
	detail_copy:  bool,
}

Coverage_Requirement :: struct {
	label:            string,
	required_percent: f64,
}

test_init :: proc(t: ^T, seed: u64, size: int, replay_choices: []u64, replay_strict: bool, capture_events: bool = true, allocator := context.allocator) {
	t^ = T {
		allocator = allocator,
		events = make([dynamic]Event, allocator),
		notes = make([dynamic]string, allocator),
		labels = make([dynamic]string, allocator),
		coverage_requirements = make([dynamic]Coverage_Requirement, allocator),
	}
	mem.dynamic_arena_init(&t.value_arena, allocator, allocator, VALUE_ARENA_BLOCK_SIZE, VALUE_ARENA_OUT_OF_BAND_SIZE, VALUE_ARENA_ALIGNMENT)
	t.value_allocator = mem.dynamic_arena_allocator(&t.value_arena)
	t.choice_marks.allocator = allocator
	test_reset(t, seed, size, replay_choices, replay_strict, capture_events)
}

test_destroy :: proc(t: ^T) {
	destroy_events(&t.events)
	destroy_strings(&t.notes)
	destroy_strings(&t.labels)
	delete(t.coverage_requirements)
	mem.dynamic_arena_destroy(&t.value_arena)
	delete(t.choice_marks)
	delete(t.choice_extra)
}

test_reset :: proc(t: ^T, seed: u64, size: int, replay_choices: []u64, replay_strict: bool, capture_events: bool) {
	destroy_events_keep_storage(&t.events)
	destroy_strings_keep_storage(&t.notes)
	destroy_strings_keep_storage(&t.labels)
	clear(&t.coverage_requirements)
	clear(&t.choice_marks)
	clear(&t.choice_extra)
	mem.dynamic_arena_reset(&t.value_arena)

	t.rng = rng_init(seed)
	t.size = size
	t.choice_count = 0
	t.replay_choices = replay_choices
	t.replay_strict = replay_strict
	t.replay_index = 0
	t.replay_overrun = false
	t.force_discard = false
	t.discard_message = ""
	t.capture_events = capture_events
	t.capture_choice_marks = false
}

choice :: proc(t: ^T, upper_exclusive: u64) -> u64 {
	if upper_exclusive <= 1 {
		return 0
	}

	value: u64
	if t.replay_index < len(t.replay_choices) {
		value = t.replay_choices[t.replay_index] % upper_exclusive
		t.replay_index += 1
	} else if t.replay_strict {
		t.replay_overrun = true
		value = 0
	} else {
		value = rng_bounded(&t.rng, upper_exclusive)
	}

	record_choice(t, value)
	return value
}

record_choice :: proc(t: ^T, value: u64) {
	if t.choice_count < INLINE_CHOICE_CAP {
		t.choice_inline[t.choice_count] = value
	} else {
		append(&t.choice_extra, value)
	}
	t.choice_count += 1
}

mark_choice_boundary :: proc(t: ^T) {
	if !t.capture_choice_marks {
		return
	}
	append(&t.choice_marks, Choice_Mark{index = t.choice_count})
}

copy_current_choices :: proc(t: ^T, allocator := context.allocator) -> [dynamic]u64 {
	dst := make([dynamic]u64, 0, t.choice_count, allocator)
	inline_count := t.choice_count
	if inline_count > INLINE_CHOICE_CAP {
		inline_count = INLINE_CHOICE_CAP
	}
	for i in 0 ..< inline_count {
		append(&dst, t.choice_inline[i])
	}
	for value in t.choice_extra {
		append(&dst, value)
	}
	return dst
}

copy_current_choice_marks :: proc(t: ^T, allocator := context.allocator) -> [dynamic]Choice_Mark {
	dst := make([dynamic]Choice_Mark, 0, len(t.choice_marks), allocator)
	for mark in t.choice_marks {
		if mark.index >= 0 && mark.index < t.choice_count {
			append(&dst, mark)
		}
	}
	return dst
}

copy_choices :: proc(src: []u64, allocator := context.allocator) -> [dynamic]u64 {
	dst := make([dynamic]u64, 0, len(src), allocator)
	for value in src {
		append(&dst, value)
	}
	return dst
}

copy_choice_marks :: proc(src: []Choice_Mark, allocator := context.allocator) -> [dynamic]Choice_Mark {
	dst := make([dynamic]Choice_Mark, 0, len(src), allocator)
	for mark in src {
		append(&dst, mark)
	}
	return dst
}

record_event :: proc(t: ^T, kind, name, status, detail: string) {
	if !t.capture_events {
		return
	}
	append(&t.events, Event {
		kind = clone_non_empty(kind, t.value_allocator),
		name = clone_non_empty(name, t.value_allocator),
		status = clone_non_empty(status, t.value_allocator),
		detail = clone_non_empty(detail, t.value_allocator),
		kind_copy = kind != "",
		name_copy = name != "",
		status_copy = status != "",
		detail_copy = detail != "",
	})
}

record_event_static_kind_status :: proc(t: ^T, kind, name, status, detail: string) {
	if !t.capture_events {
		return
	}
	append(&t.events, Event {
		kind = kind,
		name = clone_non_empty(name, t.value_allocator),
		status = status,
		detail = clone_non_empty(detail, t.value_allocator),
		name_copy = name != "",
		detail_copy = detail != "",
	})
}

note :: proc(t: ^T, message: string) {
	if !t.capture_events {
		return
	}
	append(&t.notes, clone_non_empty(message, t.allocator))
}

label :: proc(t: ^T, name: string) {
	append(&t.labels, clone_non_empty(name, t.allocator))
}

classify :: proc(t: ^T, condition: bool, name: string) {
	if condition {
		label(t, name)
	}
}

collect :: proc(t: ^T, value: string) {
	label(t, value)
}

cover :: proc(t: ^T, condition: bool, required_percent: f64, name: string) {
	append(&t.coverage_requirements, Coverage_Requirement {
		label = name,
		required_percent = required_percent,
	})
	if condition {
		label(t, name)
	}
}

copy_events :: proc(src: []Event, allocator := context.allocator) -> [dynamic]Event {
	dst := make([dynamic]Event, 0, len(src), allocator)
	for event in src {
		kind, kind_owned := copy_event_string(event.kind, event.kind_owned || event.kind_copy, allocator)
		name, name_owned := copy_event_string(event.name, event.name_owned || event.name_copy, allocator)
		status, status_owned := copy_event_string(event.status, event.status_owned || event.status_copy, allocator)
		detail, detail_owned := copy_event_string(event.detail, event.detail_owned || event.detail_copy, allocator)
		append(&dst, Event {
			kind = kind,
			name = name,
			status = status,
			detail = detail,
			kind_owned = kind_owned,
			name_owned = name_owned,
			status_owned = status_owned,
			detail_owned = detail_owned,
		})
	}
	return dst
}

copy_event_string :: proc(value: string, owned: bool, allocator := context.allocator) -> (string, bool) {
	if !owned {
		return value, false
	}
	return clone_non_empty(value, allocator), value != ""
}

copy_strings :: proc(src: []string, allocator := context.allocator) -> [dynamic]string {
	dst := make([dynamic]string, 0, len(src), allocator)
	for value in src {
		append(&dst, clone_non_empty(value, allocator))
	}
	return dst
}

clone_non_empty :: proc(value: string, allocator := context.allocator) -> string {
	if len(value) == 0 {
		return ""
	}
	return strings.clone(value, allocator)
}

destroy_strings :: proc(values: ^[dynamic]string) {
	for value in values^ {
		if len(value) > 0 {
			delete(value)
		}
	}
	delete(values^)
}

destroy_strings_keep_storage :: proc(values: ^[dynamic]string) {
	for value in values^ {
		if len(value) > 0 {
			delete(value)
		}
	}
	clear(values)
}

destroy_events :: proc(events: ^[dynamic]Event) {
	for event in events^ {
		if event.kind_owned && len(event.kind) > 0 {
			delete(event.kind)
		}
		if event.name_owned && len(event.name) > 0 {
			delete(event.name)
		}
		if event.status_owned && len(event.status) > 0 {
			delete(event.status)
		}
		if event.detail_owned && len(event.detail) > 0 {
			delete(event.detail)
		}
	}
	delete(events^)
}

destroy_events_keep_storage :: proc(events: ^[dynamic]Event) {
	for event in events^ {
		if event.kind_owned && len(event.kind) > 0 {
			delete(event.kind)
		}
		if event.name_owned && len(event.name) > 0 {
			delete(event.name)
		}
		if event.status_owned && len(event.status) > 0 {
			delete(event.status)
		}
		if event.detail_owned && len(event.detail) > 0 {
			delete(event.detail)
		}
	}
	clear(events)
}

destroy_test_case :: proc(tc: ^Test_Case) {
	destroy_events(&tc.events)
	destroy_strings(&tc.notes)
	destroy_strings(&tc.labels)
	delete(tc.choice_marks)
	delete(tc.choices)
}
