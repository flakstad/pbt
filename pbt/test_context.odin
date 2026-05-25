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
	choice_shrink_hints: [dynamic]Choice_Shrink_Hint,
	choice_shrink_candidates: [dynamic]Choice_Shrink_Candidate,
	choice_shrink_values: [dynamic]u64,
	capture_choice_marks: bool,
	capture_shrink_hints: bool,
	events:          [dynamic]Event,
	capture_events:  bool,
	notes:           [dynamic]string,
	labels:          [dynamic]string,
	shrink_labels:   [dynamic]string,
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
	choice_shrink_hints: [dynamic]Choice_Shrink_Hint,
	choice_shrink_candidates: [dynamic]Choice_Shrink_Candidate,
	choice_shrink_values: [dynamic]u64,
	events:  [dynamic]Event,
	event_string_storage: [dynamic]byte,
	notes:   [dynamic]string,
	labels:  [dynamic]string,
	shrink_labels: [dynamic]string,
	result:  Result,
}

Choice_Mark :: struct {
	index:        int,
	length_index: int,
}

Choice_Shrink_Hint :: struct {
	start:           int,
	count:           int,
	candidate_start: int,
	candidate_count: int,
}

Choice_Shrink_Candidate :: struct {
	start: int,
	count: int,
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
		shrink_labels = make([dynamic]string, allocator),
		coverage_requirements = make([dynamic]Coverage_Requirement, allocator),
	}
	mem.dynamic_arena_init(&t.value_arena, allocator, allocator, VALUE_ARENA_BLOCK_SIZE, VALUE_ARENA_OUT_OF_BAND_SIZE, VALUE_ARENA_ALIGNMENT)
	t.value_allocator = mem.dynamic_arena_allocator(&t.value_arena)
	t.choice_marks.allocator = allocator
	t.choice_shrink_hints.allocator = allocator
	t.choice_shrink_candidates.allocator = allocator
	t.choice_shrink_values.allocator = allocator
	test_reset(t, seed, size, replay_choices, replay_strict, capture_events)
}

test_destroy :: proc(t: ^T) {
	destroy_events(&t.events)
	destroy_strings(&t.notes)
	destroy_strings(&t.labels)
	destroy_strings(&t.shrink_labels)
	delete(t.coverage_requirements)
	mem.dynamic_arena_destroy(&t.value_arena)
	delete(t.choice_marks)
	delete(t.choice_shrink_hints)
	delete(t.choice_shrink_candidates)
	delete(t.choice_shrink_values)
	delete(t.choice_extra)
}

test_reset :: proc(t: ^T, seed: u64, size: int, replay_choices: []u64, replay_strict: bool, capture_events: bool) {
	destroy_events_keep_storage(&t.events)
	destroy_strings_keep_storage(&t.notes)
	destroy_strings_keep_storage(&t.labels)
	destroy_strings_keep_storage(&t.shrink_labels)
	clear(&t.coverage_requirements)
	clear(&t.choice_marks)
	if len(t.choice_shrink_hints) > 0 {
		clear(&t.choice_shrink_hints)
	}
	if len(t.choice_shrink_candidates) > 0 {
		clear(&t.choice_shrink_candidates)
	}
	if len(t.choice_shrink_values) > 0 {
		clear(&t.choice_shrink_values)
	}
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
	t.capture_shrink_hints = false
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
	append(&t.choice_marks, Choice_Mark{index = t.choice_count, length_index = -1})
}

mark_choice_boundary_with_length :: proc(t: ^T, length_index: int) {
	if !t.capture_choice_marks {
		return
	}
	append(&t.choice_marks, Choice_Mark{index = t.choice_count, length_index = length_index})
}

choice_cursor :: proc(t: ^T) -> int {
	return t.choice_count
}

record_choice_shrink_hint :: proc(t: ^T, start, count: int, replacement: []u64) {
	if !t.capture_shrink_hints {
		return
	}
	if start < 0 || count <= 0 || start + count > t.choice_count {
		return
	}

	value_start := len(t.choice_shrink_values)
	for value in replacement {
		append(&t.choice_shrink_values, value)
	}

	candidate_start := len(t.choice_shrink_candidates)
	append(&t.choice_shrink_candidates, Choice_Shrink_Candidate {
		start = value_start,
		count = len(replacement),
	})
	append(&t.choice_shrink_hints, Choice_Shrink_Hint {
		start = start,
		count = count,
		candidate_start = candidate_start,
		candidate_count = 1,
	})
}

choice_value_at :: proc(t: ^T, index: int) -> u64 {
	if index < 0 || index >= t.choice_count {
		return 0
	}
	if index < INLINE_CHOICE_CAP {
		return t.choice_inline[index]
	}
	return t.choice_extra[index - INLINE_CHOICE_CAP]
}

append_choice_range :: proc(dst: ^[dynamic]u64, t: ^T, start, count: int) {
	for i in start ..< start + count {
		append(dst, choice_value_at(t, i))
	}
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

copy_current_choice_shrink_hints :: proc(t: ^T, allocator := context.allocator) -> [dynamic]Choice_Shrink_Hint {
	return copy_choice_shrink_hints(t.choice_shrink_hints[:], allocator)
}

copy_current_choice_shrink_candidates :: proc(t: ^T, allocator := context.allocator) -> [dynamic]Choice_Shrink_Candidate {
	return copy_choice_shrink_candidates(t.choice_shrink_candidates[:], allocator)
}

copy_current_choice_shrink_values :: proc(t: ^T, allocator := context.allocator) -> [dynamic]u64 {
	return copy_choices(t.choice_shrink_values[:], allocator)
}

copy_choice_shrink_hints :: proc(src: []Choice_Shrink_Hint, allocator := context.allocator) -> [dynamic]Choice_Shrink_Hint {
	dst := make([dynamic]Choice_Shrink_Hint, 0, len(src), allocator)
	for hint in src {
		append(&dst, hint)
	}
	return dst
}

copy_choice_shrink_candidates :: proc(src: []Choice_Shrink_Candidate, allocator := context.allocator) -> [dynamic]Choice_Shrink_Candidate {
	dst := make([dynamic]Choice_Shrink_Candidate, 0, len(src), allocator)
	for candidate in src {
		append(&dst, candidate)
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

record_event_static :: proc(t: ^T, kind, name, status, detail: string) {
	if !t.capture_events {
		return
	}
	append(&t.events, Event {
		kind = kind,
		name = name,
		status = status,
		detail = detail,
	})
}

reserve_events_empty :: proc(t: ^T, capacity: int) {
	if !t.capture_events || capacity <= 0 || len(t.events) > 0 || cap(t.events) >= capacity {
		return
	}
	delete(t.events)
	t.events = make([dynamic]Event, 0, capacity, t.allocator)
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

require_shrink_label :: proc(t: ^T, name: string) {
	label(t, name)
	append(&t.shrink_labels, clone_non_empty(name, t.allocator))
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

copy_events_to_test_case :: proc(tc: ^Test_Case, src: []Event, allocator := context.allocator) {
	tc.events = make([dynamic]Event, 0, len(src), allocator)
	storage_size := event_storage_size(src)
	if storage_size > 0 {
		tc.event_string_storage = make([dynamic]byte, 0, storage_size, allocator)
	}
	for event in src {
		kind_copy := event.kind_owned || event.kind_copy
		name_copy := event.name_owned || event.name_copy
		status_copy := event.status_owned || event.status_copy
		detail_copy := event.detail_owned || event.detail_copy
		append(&tc.events, Event {
			kind = copy_event_string_to_test_case(tc, event.kind, kind_copy),
			name = copy_event_string_to_test_case(tc, event.name, name_copy),
			status = copy_event_string_to_test_case(tc, event.status, status_copy),
			detail = copy_event_string_to_test_case(tc, event.detail, detail_copy),
			kind_copy = kind_copy,
			name_copy = name_copy,
			status_copy = status_copy,
			detail_copy = detail_copy,
		})
	}
}

event_storage_size :: proc(src: []Event) -> int {
	total := 0
	for event in src {
		if event.kind_owned || event.kind_copy {
			total += len(event.kind)
		}
		if event.name_owned || event.name_copy {
			total += len(event.name)
		}
		if event.status_owned || event.status_copy {
			total += len(event.status)
		}
		if event.detail_owned || event.detail_copy {
			total += len(event.detail)
		}
	}
	return total
}

copy_event_string_to_test_case :: proc(tc: ^Test_Case, value: string, owned: bool) -> string {
	if !owned || len(value) == 0 {
		return value
	}
	start := len(tc.event_string_storage)
	append_string_bytes(&tc.event_string_storage, value)
	return string(tc.event_string_storage[start:len(tc.event_string_storage)])
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
	delete(tc.event_string_storage)
	destroy_strings(&tc.notes)
	destroy_strings(&tc.labels)
	destroy_strings(&tc.shrink_labels)
	delete(tc.choice_shrink_values)
	delete(tc.choice_shrink_candidates)
	delete(tc.choice_shrink_hints)
	delete(tc.choice_marks)
	delete(tc.choices)
}
