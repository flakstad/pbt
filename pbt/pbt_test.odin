package pbt

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

sum_is_commutative :: proc(t: ^T) -> Result {
	a := draw(t, int_range(-100, 100))
	b := draw(t, int_range(-100, 100))
	return equal(a + b, b + a)
}

fails_for_large_values :: proc(t: ^T) -> Result {
	value := draw(t, int_range(0, 100))
	return assert(value < 50, "value should be below 50")
}

always_fails :: proc(t: ^T) -> Result {
	return fail("always fails")
}

same_seed_generates_same_choices :: proc(t: ^T) -> Result {
	a := draw(t, int_range(0, 1000))
	b := draw(t, int_range(0, 1000))
	return assert(a != b || a == b, "unreachable")
}

collections_are_generated_in_case_arena :: proc(t: ^T) -> Result {
	values := draw(t, array(int_range(0, 10), 1, 10))
	name := draw(t, string_ascii(1, 10))
	token := draw(t, string_alphabet("abc123", 1, 10))
	maybe_id := draw(t, optional(u64_range(1, 10)))

	return assert(len(values) >= 1 && len(name) >= 1 && len(token) >= 1 && (!maybe_id.ok || maybe_id.value >= 1), "expected generated collection values")
}

double_int :: proc(value: int) -> int {
	return value * 2
}

string_with_length :: proc(length: int) -> Gen(String_Alphabet_Input, string) {
	return string_alphabet("xy", length, length)
}

int_array_with_size :: proc(size: int) -> Gen(Array_Input(Int_Range_Input, int), []int) {
	return array(int_range(0, 1), size, size)
}

half_size :: proc(size: int) -> int {
	return size / 2
}

is_even :: proc(value: int) -> bool {
	return value % 2 == 0
}

Leaf_Count_Input :: struct {}

leaf_count_gen :: proc() -> Gen(Leaf_Count_Input, int) {
	return {
		input = {},
		produce = leaf_count_produce,
	}
}

leaf_count_produce :: proc(t: ^T, _: Leaf_Count_Input) -> int {
	if t.size <= 1 || draw(t, boolean()) {
		return 1
	}

	previous := t.size
	t.size = previous / 2
	left := draw(t, lazy(leaf_count_gen))
	right := draw(t, lazy(leaf_count_gen))
	t.size = previous
	return left + right
}

Color :: enum {
	Red,
	Green,
	Blue,
}

Credentials :: struct {
	name:    string,
	retries: int,
	active:  bool,
}

credentials_from :: proc(name: string, retries: int, active: bool) -> Credentials {
	return {name = name, retries = retries, active = active}
}

Name_Length :: struct {
	name:   string,
	length: int,
}

name_length_from :: proc(name: string, length: int) -> Name_Length {
	return {name = name, length = length}
}

combinators_generate_domain_values :: proc(t: ^T) -> Result {
	even := draw(t, map_gen(int_range(0, 50), double_int))
	fixed := draw(t, bind(int_range(1, 5), string_with_length))

	return assert(even % 2 == 0 && len(fixed) >= 1 && len(fixed) <= 5, "expected combinator-generated values")
}

generator_catalog_values :: proc(t: ^T) -> Result {
	colors := [?]string{"red", "green", "blue"}
	color := draw(t, elements(colors[:]))
	enum_color := draw(t, enum_range(Color.Red, Color.Blue))
	fixed := draw(t, constant(42))
	int_pair := draw(t, pair(int_range(1, 3), string_alphabet("q", 1, 3)))
	table := draw(t, dict(string_alphabet("ab", 1, 2), int_range(0, 10), 0, 4))
	unique_values := draw(t, unique_array(int_range(0, 20), 0, 8))
	float := draw(t, f64_range(-1.0, 1.0))
	sized_values := draw(t, sized(int_array_with_size))
	resized_values := draw(t, resize(array(int_range(0, 1), 0), 3))
	scaled_values := draw(t, scale(array(int_range(0, 1), 0), half_size))
	smaller_values := draw(t, smaller(array(int_range(0, 1), 0)))
	filtered := draw(t, such_that(int_range(0, 10), is_even))
	non_empty_values := draw(t, non_empty_array(int_range(0, 10), 8))
	non_empty_ascii := draw(t, non_empty_string_ascii(8))
	non_empty_token := draw(t, non_empty_string_alphabet("abc", 8))
	int_triple := draw(t, triple(int_range(1, 3), boolean(), string_alphabet("z", 1, 3)))
	int_tuple4 := draw(t, tuple4(int_range(1, 3), boolean(), string_alphabet("x", 1, 3), u64_range(10, 20)))
	int_tuple5 := draw(t, tuple5(int_range(1, 3), boolean(), string_alphabet("y", 1, 3), u64_range(10, 20), f64_range(0, 1)))
	name_length := draw(t, map2(string_alphabet("ab", 1, 4), int_range(1, 4), name_length_from))
	credentials := draw(t, map3(string_alphabet("cd", 1, 4), int_range(0, 3), boolean(), credentials_from))
	recursive_leaf_count := draw(t, leaf_count_gen())

	return assert(
		(color == "red" || color == "green" || color == "blue") &&
		enum_color >= Color.Red && enum_color <= Color.Blue &&
		fixed == 42 &&
		int_pair.first >= 1 && int_pair.first <= 3 &&
		len(int_pair.second) >= 1 && len(int_pair.second) <= 3 &&
		len(table) <= 4 &&
		len(unique_values) <= 8 &&
		values_are_unique(unique_values) &&
		float >= -1.0 && float <= 1.0 &&
		len(sized_values) == t.size &&
		len(resized_values) <= 3 &&
		len(scaled_values) <= 50 &&
		len(smaller_values) <= 50 &&
		filtered % 2 == 0 &&
		len(non_empty_values) >= 1 && len(non_empty_values) <= 8 &&
		len(non_empty_ascii) >= 1 && len(non_empty_ascii) <= 8 &&
		len(non_empty_token) >= 1 && len(non_empty_token) <= 8 &&
		int_triple.first >= 1 && int_triple.first <= 3 &&
		len(int_triple.third) >= 1 && len(int_triple.third) <= 3 &&
			int_tuple4.first >= 1 && int_tuple4.first <= 3 &&
			len(int_tuple4.third) >= 1 && len(int_tuple4.third) <= 3 &&
			int_tuple4.fourth >= 10 && int_tuple4.fourth <= 20 &&
			int_tuple5.first >= 1 && int_tuple5.first <= 3 &&
			len(int_tuple5.third) >= 1 && len(int_tuple5.third) <= 3 &&
			int_tuple5.fourth >= 10 && int_tuple5.fourth <= 20 &&
			int_tuple5.fifth >= 0 && int_tuple5.fifth <= 1 &&
			len(name_length.name) >= 1 && len(name_length.name) <= 4 &&
			name_length.length >= 1 && name_length.length <= 4 &&
			len(credentials.name) >= 1 && len(credentials.name) <= 4 &&
			credentials.retries >= 0 && credentials.retries <= 3 &&
			(credentials.active || !credentials.active) &&
			recursive_leaf_count >= 1 && recursive_leaf_count <= 16,
		"expected generator catalog values",
	)
}

values_are_unique :: proc(values: []int) -> bool {
	for value, i in values {
		for j in 0 ..< i {
			if values[j] == value {
				return false
			}
		}
	}
	return true
}

coverage_property :: proc(t: ^T) -> Result {
	value := draw(t, int_range(0, 9))
	classify(t, value < 5, "low")
	classify(t, value >= 5, "high")
	cover(t, true, 100.0, "all")
	return pass()
}

coverage_failure_property :: proc(t: ^T) -> Result {
	cover(t, false, 1.0, "impossible")
	return pass()
}

counterexample_property :: proc(t: ^T) -> Result {
	value := draw(t, constant(12))
	return counterexample("while checking invoice total", equal(value, 13))
}

sequence_failure_property :: proc(t: ^T) -> Result {
	length := draw(t, int_range(0, 3))
	for i in 0 ..< length {
		value := draw(t, int_range(0, 10))
		if value >= 7 {
			return fail("sequence contains large value")
		}
	}
	return pass()
}

payload_irrelevant_failure_property :: proc(t: ^T) -> Result {
	marker := draw(t, int_range(0, 1))
	_ = draw(t, int_range(0, 10))
	_ = draw(t, int_range(0, 10))
	return assert(marker == 0, "marker triggers failure")
}

marked_command_failure_property :: proc(t: ^T) -> Result {
	prefix := choice(t, 10)
	for _ in 0 ..< 3 {
		mark_choice_boundary(t)
		command := choice(t, 10)
		if prefix == 3 && command == 7 {
			return fail("bad marked command")
		}
	}
	return pass()
}

fixed_array_failure_property :: proc(t: ^T) -> Result {
	values := draw(t, array(int_range(0, 10), 3, 3))
	if values[0] == 3 && (values[1] == 7 || values[2] == 7) {
		return fail("bad fixed array")
	}
	return pass()
}

array_suffix_failure_property :: proc(t: ^T) -> Result {
	values := draw(t, array(int_range(0, 9), 0, 4))
	if len(values) >= 2 && values[1] == 7 {
		return fail("array prefix contains bad value")
	}
	return pass()
}

string_suffix_failure_property :: proc(t: ^T) -> Result {
	value := draw(t, string_alphabet("az", 0, 4))
	if len(value) >= 2 && value[1] == 'z' {
		return fail("string prefix contains bad byte")
	}
	return pass()
}

array_contains_failure_property :: proc(t: ^T) -> Result {
	values := draw(t, array(int_range(0, 9), 0, 4))
	for value in values {
		if value == 7 {
			return fail("array contains bad value")
		}
	}
	return pass()
}

string_contains_failure_property :: proc(t: ^T) -> Result {
	value := draw(t, string_alphabet("az", 0, 4))
	for ch in value {
		if ch == 'z' {
			return fail("string contains bad byte")
		}
	}
	return pass()
}

domain_encoded_number :: proc(t: ^T) -> int {
	start := choice_cursor(t)
	encoding := choice(t, 2)
	if encoding == 0 {
		return int(choice(t, 10))
	}

	tens := choice(t, 10)
	ones := choice(t, 10)
	value := int(tens * 10 + ones)
	if value < 10 {
		replacement := [?]u64{0, u64(value)}
		record_choice_shrink_hint(t, start, choice_cursor(t) - start, replacement[:])
	}
	return value
}

domain_encoded_failure_property :: proc(t: ^T) -> Result {
	value := domain_encoded_number(t)
	return assert(value != 7, "domain value should not be seven")
}

labelled_failure_property :: proc(t: ^T) -> Result {
	marker := choice(t, 2)
	_ = choice(t, 10)
	if marker == 1 {
		label(t, "interesting")
	}
	return fail("labelled failure")
}

bad_command_initial :: proc(t: ^T, target: rawptr) -> int {
	return 0
}

bad_command_draw :: proc(t: ^T, state: int) -> int {
	return draw(t, int_range(0, 9))
}

bad_command_run :: proc(t: ^T, target: rawptr, state: int, command: int) -> int {
	return command
}

bad_command_next :: proc(state: int, command: int, value: int) -> int {
	return state + 1
}

bad_command_postcondition :: proc(state: int, command: int, value: int) -> Result {
	if value == 7 {
		return fail("bad command")
	}
	return pass()
}

bad_command_stateful_property :: proc(t: ^T) -> Result {
	model := State_Model(int, int, int) {
		initial = bad_command_initial,
		command = bad_command_draw,
		run = bad_command_run,
		next_state = bad_command_next,
		postcondition = bad_command_postcondition,
	}
	return run_commands(t, model, {min_len = 0, max_len = 3})
}

records_structured_event :: proc(t: ^T) -> Result {
	record_event(t, "process", "cart add", "ok", "exit=0")
	note(t, "about to fail")
	label(t, "forced")
	return fail("forced failure")
}

Counter_Command :: enum {
	Inc,
	Dec,
	Reset,
}

Counter_Target :: struct {
	value: int,
}

counter_initial :: proc(t: ^T, target: rawptr) -> int {
	return 0
}

counter_command :: proc(t: ^T, state: int) -> Counter_Command {
	index := draw(t, int_range(0, 2))
	return Counter_Command(index)
}

counter_command_inc_then_reset :: proc(t: ^T, state: int) -> Counter_Command {
	if state == 0 {
		return .Inc
	}
	return .Reset
}

counter_precondition :: proc(state: int, command: Counter_Command) -> bool {
	if command == .Dec {
		return state > 0
	}
	return true
}

counter_run_buggy :: proc(t: ^T, target: rawptr, state: int, command: Counter_Command) -> int {
	counter := cast(^Counter_Target)target
	switch command {
	case .Inc:
		counter.value += 1
	case .Dec:
		counter.value -= 1
	case .Reset:
		counter.value = 1
	}
	return counter.value
}

counter_next_state :: proc(state: int, command: Counter_Command, value: int) -> int {
	switch command {
	case .Inc:
		return state + 1
	case .Dec:
		return state - 1
	case .Reset:
		return 0
	}
	return state
}

counter_postcondition :: proc(state: int, command: Counter_Command, value: int) -> Result {
	expected := counter_next_state(state, command, value)
	return assert(value == expected, "counter target diverged from model")
}

counter_invariant :: proc(t: ^T, state: int) -> Result {
	return assert(state >= 0, "model counter should not be negative")
}

counter_command_name :: proc(command: Counter_Command) -> string {
	switch command {
	case .Inc:
		return "inc"
	case .Dec:
		return "dec"
	case .Reset:
		return "reset"
	}
	return "unknown"
}

counter_state_detail :: proc(state: int) -> string {
	return fmt.tprintf("%d", state)
}

counter_value_detail :: proc(value: int) -> string {
	return fmt.tprintf("%d", value)
}

counter_stateful_property :: proc(t: ^T) -> Result {
	target := Counter_Target{}
	model := State_Model(int, Counter_Command, int) {
		target = &target,
		initial = counter_initial,
		command = counter_command,
		precondition = counter_precondition,
		run = counter_run_buggy,
		next_state = counter_next_state,
		postcondition = counter_postcondition,
		invariant = counter_invariant,
		command_name = counter_command_name,
		state_detail = counter_state_detail,
		value_detail = counter_value_detail,
	}
	return run_commands(t, model, {min_len = 1, max_len = 20})
}

counter_stateful_skip_success_property :: proc(t: ^T) -> Result {
	target := Counter_Target{}
	model := State_Model(int, Counter_Command, int) {
		target = &target,
		initial = counter_initial,
		command = counter_command_inc_then_reset,
		precondition = counter_precondition,
		run = counter_run_buggy,
		next_state = counter_next_state,
		postcondition = counter_postcondition,
		invariant = counter_invariant,
		command_name = counter_command_name,
		state_detail = counter_state_detail,
		value_detail = counter_value_detail,
	}
	return run_commands(t, model, {min_len = 2, max_len = 2, skip_success_events = true})
}

process_property :: proc(t: ^T) -> Result {
	command := [?]string{"/bin/sh", "-c", "printf ok"}
	result := process_run(t, command[:])
	if !result.success {
		return fail("process failed")
	}
	return equal(result.stdout, "ok")
}

protocol_property :: proc(t: ^T) -> Result {
	payload := draw(t, string_ascii(1, 12))
	command := [?]string{"/bin/cat"}
	result := protocol_call(t, command[:], payload)
	if !result.success {
		return fail("protocol process failed")
	}
	return assert(result.stdout == payload, fmt.tprintf("stdout=%q payload=%q", result.stdout, payload))
}

http_property :: proc(t: ^T) -> Result {
	response := http_get(t, "file:///tmp/pbt-http-adapter-ok")
	if !response.success {
		return fail("curl-backed http request failed")
	}
	return equal(response.body, "ok")
}

@(test)
test_check_passes :: proc(t: ^testing.T) {
	result := check("sum is commutative", sum_is_commutative, {num_tests = 50, seed = 123, shrink = true})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.num_tests, 50)
}

@(test)
test_check_finds_and_shrinks_failure :: proc(t: ^testing.T) {
	result := check("large values fail", fails_for_large_values, {num_tests = 100, seed = 123})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect_value(t, result.code, "property_failed")
	testing.expect(t, len(result.replay.choices) > 0)
	testing.expect_value(t, result.replay.choices[0], u64(50))

	replayed := check_replay("large values fail", fails_for_large_values, result.replay)
	defer destroy_check_result(&replayed)

	testing.expect_value(t, replayed.status, Status.Fail)
}

@(test)
test_no_shrink_keeps_original_failure :: proc(t: ^testing.T) {
	result := check("large values fail", fails_for_large_values, {num_tests = 100, seed = 123, no_shrink = true})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect_value(t, result.replay.choices[0], u64(98))
}

@(test)
test_check_result_json_contains_replay :: proc(t: ^testing.T) {
	result := check("large values fail", fails_for_large_values, {num_tests = 100, seed = 123, shrink = true})
	defer destroy_check_result(&result)

	json := check_result_json(result)
	defer delete(json)

	testing.expect(t, strings.contains(json, "\"tool\":\"pbt\""))
	testing.expect(t, strings.contains(json, "\"schema_version\":1"))
	testing.expect(t, strings.contains(json, "\"status\":\"fail\""))
	testing.expect(t, strings.contains(json, "\"code\":\"property_failed\""))
	testing.expect(t, strings.contains(json, "\"duration_ns\""))
	testing.expect(t, strings.contains(json, "\"shrink_attempts\""))
	testing.expect(t, strings.contains(json, "\"shrink_duration_ns\""))
	testing.expect(t, strings.contains(json, "\"replay\""))
	testing.expect(t, strings.contains(json, "\"choices\""))
	testing.expect(t, strings.contains(json, "\"choices_csv\":\"50\""))
	testing.expect_value(t, check_result_exit_code(result), 1)
	testing.expect(t, result.duration_ns > 0)
	testing.expect(t, result.shrink_attempts > 0)
	testing.expect(t, result.shrink_duration_ns > 0)

	choices_csv := replay_choices_csv(result.replay)
	defer delete(choices_csv)
	testing.expect_value(t, choices_csv, "50")

	text := check_result_text(result)
	defer delete(text)
	testing.expect(t, strings.contains(text, "large values fail: fail"))
	testing.expect(t, strings.contains(text, "code: property_failed"))
	testing.expect(t, strings.contains(text, "replay: --replay-seed 123 --replay-choices 50"))
	testing.expect(t, strings.contains(text, "shrink:"))
}

@(test)
test_events_are_reported_as_json :: proc(t: ^testing.T) {
	result := check("events", records_structured_event, {num_tests = 1, seed = 1, shrink = true})
	defer destroy_check_result(&result)

	json := check_result_json(result)
	defer delete(json)

	testing.expect(t, strings.contains(json, "\"events\""))
	testing.expect(t, strings.contains(json, "\"notes\":[\"about to fail\"]"))
	testing.expect(t, strings.contains(json, "\"kind\":\"process\""))
	testing.expect(t, strings.contains(json, "\"name\":\"cart add\""))
	testing.expect(t, strings.contains(json, "\"about to fail\""))
	testing.expect(t, strings.contains(json, "\"labels\":[\"forced\"]"))

	text := check_result_text(result)
	defer delete(text)
	testing.expect(t, strings.contains(text, "notes:"))
	testing.expect(t, strings.contains(text, "  - about to fail"))
	testing.expect(t, strings.contains(text, "events:"))
	testing.expect(t, strings.contains(text, "process cart add [ok]: exit=0"))
	testing.expect(t, !strings.contains(text, "note [ok]: about to fail"))
}

@(test)
test_stateful_runner_finds_model_mismatch :: proc(t: ^testing.T) {
	result := check("counter stateful", counter_stateful_property, {num_tests = 50, seed = 5, shrink = true})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect_value(t, result.message, "counter target diverged from model")
	testing.expect(t, len(result.shrunk_test.choice_marks) > 0)
	testing.expect(t, len(result.shrunk_test.events) > 0)
	testing.expect(t, strings.contains(result.shrunk_test.events[0].name, "reset"))
	testing.expect(t, strings.contains(result.shrunk_test.events[0].detail, "state=0"))
	testing.expect(t, strings.contains(result.shrunk_test.events[0].detail, "value=1"))

	replayed := check_replay("counter stateful", counter_stateful_property, result.replay)
	defer destroy_check_result(&replayed)

	testing.expect_value(t, replayed.status, Status.Fail)
}

@(test)
test_stateful_runner_can_skip_success_events :: proc(t: ^testing.T) {
	choices := [?]u64{0}
	result := run_case(counter_stateful_skip_success_property, 1, 10, choices[:], true, true, true)
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, len(result.events), 1)
	if len(result.events) > 0 {
		testing.expect(t, strings.contains(result.events[0].name, "reset postcondition"))
		testing.expect_value(t, result.events[0].status, "fail")
	}
}

@(test)
test_process_adapter_runs_cli :: proc(t: ^testing.T) {
	result := check("process adapter", process_property, {num_tests = 3, seed = 1})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_process_adapter_records_duration :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	command := [?]string{"/bin/sh", "-c", "printf ok"}
	result := process_run(&ctx, command[:])

	testing.expect(t, result.success)
	testing.expect(t, result.duration_ns > 0)
	testing.expect(t, len(ctx.events) > 0)
	testing.expect(t, strings.contains(ctx.events[0].detail, "duration_ns="))
}

@(test)
test_process_adapter_accepts_working_dir_and_env :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	command := [?]string{"/bin/sh", "-c", "printf \"%s:%s\" \"$PWD\" \"$PBT_PROCESS_TEST\""}
	env := [?]string{"PBT_PROCESS_TEST=ok"}
	result := process_run_with_options(&ctx, command[:], {
		working_dir = "/tmp",
		env = env[:],
	})

	testing.expect(t, result.success)
	testing.expect(t, strings.contains(result.stdout, "/tmp:ok"))
}

@(test)
test_process_adapter_times_out :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	command := [?]string{"/bin/sh", "-c", "sleep 0.2; printf late"}
	result := process_run_with_options(&ctx, command[:], {timeout_ms = 20})

	testing.expect(t, !result.success)
	testing.expect(t, strings.contains(result.error, "timed out after 20 ms"))
	testing.expect(t, result.duration_ns > 0)
	testing.expect(t, result.duration_ns < 150_000_000)
	testing.expect(t, len(ctx.events) > 0)
	testing.expect(t, strings.contains(ctx.events[0].detail, "timeout_ms=20"))
}

@(test)
test_process_adapter_caps_output :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	command := [?]string{"/bin/sh", "-c", "printf abcdef"}
	result := process_run_with_options(&ctx, command[:], {max_output_bytes = 3})

	testing.expect(t, !result.success)
	testing.expect_value(t, result.stdout, "abc")
	testing.expect(t, strings.contains(result.error, "stdout exceeded 3 bytes"))
	testing.expect(t, len(ctx.events) > 0)
	testing.expect(t, strings.contains(ctx.events[0].detail, "max_output_bytes=3"))
}

@(test)
test_protocol_adapter_sends_request_file :: proc(t: ^testing.T) {
	result := check("protocol adapter", protocol_property, {num_tests = 10, seed = 11})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_protocol_adapter_accepts_process_options :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	command := [?]string{"/bin/sh", "-c", "IFS= read -r payload < \"$1\"; printf \"%s:%s\" \"$PBT_PROTOCOL_TEST\" \"$payload\"", "pbt-target"}
	env := [?]string{"PBT_PROTOCOL_TEST=ok"}
	result := protocol_call_with_options(&ctx, command[:], "payload", {env = env[:]})

	testing.expect(t, result.success)
	testing.expect_value(t, result.stdout, "ok:payload")
}

@(test)
test_line_protocol_reuses_process :: proc(t: ^testing.T) {
	command := [?]string{"/bin/sh", "-c", "while IFS= read -r line; do printf \"%s:%s\\n\" \"$PBT_LINE_TEST\" \"$line\"; done"}
	env := [?]string{"PBT_LINE_TEST=ok"}
	client, start_error := line_protocol_start(command[:], {env = env[:]})
	defer line_protocol_stop(&client)

	testing.expect(t, start_error == nil)

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	first := line_protocol_call(&ctx, &client, "one")
	second := line_protocol_call(&ctx, &client, "two")

	testing.expect(t, first.success)
	testing.expect(t, second.success)
	testing.expect_value(t, first.response, "ok:one")
	testing.expect_value(t, second.response, "ok:two")
	testing.expect(t, first.duration_ns > 0)
	testing.expect(t, second.duration_ns > 0)
	testing.expect(t, len(ctx.events) >= 2)
	testing.expect(t, strings.contains(ctx.events[0].detail, "duration_ns="))
}

@(test)
test_line_protocol_rejects_oversized_response :: proc(t: ^testing.T) {
	command := [?]string{"/bin/sh", "-c", "while IFS= read -r line; do printf \"123456789\\n\"; done"}
	client, start_error := line_protocol_start(command[:])
	defer line_protocol_stop(&client)

	testing.expect(t, start_error == nil)

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	result := line_protocol_call_with_options(&ctx, &client, "anything", {max_response_bytes = 4})

	testing.expect(t, !result.success)
	testing.expect(t, strings.contains(result.error, "exceeded 4 bytes"))
	testing.expect(t, !client.alive)
	testing.expect(t, len(ctx.events) > 0)
	testing.expect_value(t, ctx.events[0].status, "error")
}

@(test)
test_http_adapter_fetches_url :: proc(t: ^testing.T) {
	file, err := os.create("/tmp/pbt-http-adapter-ok")
	testing.expect(t, err == nil)
	_, err = os.write_string(file, "ok")
	testing.expect(t, err == nil)
	os.close(file)
	defer os.remove("/tmp/pbt-http-adapter-ok")

	result := check("http adapter", http_property, {num_tests = 3, seed = 12})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_http_adapter_records_duration :: proc(t: ^testing.T) {
	file, err := os.create("/tmp/pbt-http-adapter-duration")
	testing.expect(t, err == nil)
	_, err = os.write_string(file, "ok")
	testing.expect(t, err == nil)
	os.close(file)
	defer os.remove("/tmp/pbt-http-adapter-duration")

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	response := http_get(&ctx, "file:///tmp/pbt-http-adapter-duration")

	testing.expect(t, response.success)
	testing.expect(t, response.duration_ns > 0)
	testing.expect(t, len(ctx.events) > 0)
	testing.expect(t, strings.contains(ctx.events[len(ctx.events) - 1].detail, "duration_ns="))
}

@(test)
test_http_adapter_accepts_timeout :: proc(t: ^testing.T) {
	file, err := os.create("/tmp/pbt-http-adapter-timeout")
	testing.expect(t, err == nil)
	_, err = os.write_string(file, "ok")
	testing.expect(t, err == nil)
	os.close(file)
	defer os.remove("/tmp/pbt-http-adapter-timeout")

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	response := http_request(&ctx, {method = "GET", url = "file:///tmp/pbt-http-adapter-timeout", timeout_ms = 1_500})

	testing.expect(t, response.success)
	testing.expect(t, !response.timed_out)
	testing.expect(t, len(ctx.events) > 0)
	testing.expect(t, strings.contains(ctx.events[0].detail, "--max-time 1.500"))
	testing.expect(t, strings.contains(ctx.events[len(ctx.events) - 1].detail, "timeout_ms=1500"))
}

@(test)
test_http_post_json_adds_json_headers :: proc(t: ^testing.T) {
	fake_curl := "/tmp/pbt-fake-curl-json"
	file, err := os.create(fake_curl)
	testing.expect(t, err == nil)
	_, err = os.write_string(file, "#!/bin/sh\nout=\"\"\nprev=\"\"\nfor arg in \"$@\"; do\n  if [ \"$prev\" = \"-o\" ]; then out=\"$arg\"; fi\n  prev=\"$arg\"\ndone\nprintf '{\"ok\":true}' > \"$out\"\nprintf 201\n")
	testing.expect(t, err == nil)
	os.close(file)
	err = os.chmod(fake_curl, os.Permissions_All)
	testing.expect(t, err == nil)
	defer os.remove(fake_curl)

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	response := http_post_json(&ctx, "http://example.test/items", "{\"sku\":\"abc\"}", {
		curl = fake_curl,
		timeout_ms = 500,
	})

	testing.expect(t, response.success)
	testing.expect_value(t, response.status, 201)
	testing.expect_value(t, response.body, "{\"ok\":true}")
	testing.expect(t, http_events_contain(ctx.events[:], "Content-Type: application/json"))
	testing.expect(t, http_events_contain(ctx.events[:], "Accept: application/json"))
	testing.expect(t, http_events_contain(ctx.events[:], "--max-time 0.500"))
}

@(test)
test_http_adapter_records_body_and_stderr_summary :: proc(t: ^testing.T) {
	fake_curl := "/tmp/pbt-fake-curl-summary"
	file, err := os.create(fake_curl)
	testing.expect(t, err == nil)
	_, err = os.write_string(file, "#!/bin/sh\nout=\"\"\nprev=\"\"\nfor arg in \"$@\"; do\n  if [ \"$prev\" = \"-o\" ]; then out=\"$arg\"; fi\n  prev=\"$arg\"\ndone\nprintf 'hello\\nworld' > \"$out\"\nprintf 'warn\\n' >&2\nprintf 500\n")
	testing.expect(t, err == nil)
	os.close(file)
	err = os.chmod(fake_curl, os.Permissions_All)
	testing.expect(t, err == nil)
	defer os.remove(fake_curl)

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	response := http_request(&ctx, {method = "GET", url = "http://example.test/fail", curl = fake_curl})

	testing.expect(t, response.success)
	testing.expect_value(t, response.status, 500)
	testing.expect_value(t, response.body, "hello\nworld")
	testing.expect(t, strings.contains(response.stderr, "warn"))
	testing.expect(t, len(ctx.events) > 0)
	detail := ctx.events[len(ctx.events) - 1].detail
	testing.expect(t, strings.contains(detail, "body_bytes=11"))
	testing.expect(t, strings.contains(detail, "body_preview=\"hello\\nworld\""))
	testing.expect(t, strings.contains(detail, "stderr_bytes=5"))
	testing.expect(t, strings.contains(detail, "stderr_preview=\"warn\\n\""))
}

@(test)
test_http_adapter_caps_response_body :: proc(t: ^testing.T) {
	fake_curl := "/tmp/pbt-fake-curl-body-cap"
	file, err := os.create(fake_curl)
	testing.expect(t, err == nil)
	_, err = os.write_string(file, "#!/bin/sh\nout=\"\"\nprev=\"\"\nfor arg in \"$@\"; do\n  if [ \"$prev\" = \"-o\" ]; then out=\"$arg\"; fi\n  prev=\"$arg\"\ndone\nprintf abcdef > \"$out\"\nprintf 200\n")
	testing.expect(t, err == nil)
	os.close(file)
	err = os.chmod(fake_curl, os.Permissions_All)
	testing.expect(t, err == nil)
	defer os.remove(fake_curl)

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	response := http_request(&ctx, {method = "GET", url = "http://example.test/large", curl = fake_curl, max_body_bytes = 3})

	testing.expect(t, !response.success)
	testing.expect(t, response.body_too_large)
	testing.expect_value(t, response.body, "abc")
	testing.expect(t, strings.contains(response.error, "exceeded 3 bytes"))
	testing.expect(t, len(ctx.events) > 0)
	detail := ctx.events[len(ctx.events) - 1].detail
	testing.expect(t, strings.contains(detail, "max_body_bytes=3"))
	testing.expect(t, strings.contains(detail, "body_truncated=true"))
	testing.expect(t, strings.contains(detail, "body_bytes=3"))
}

@(test)
test_http_expect_status_helpers :: proc(t: ^testing.T) {
	ok := Http_Response{success = true, status = 201}
	testing.expect_value(t, http_expect_status(ok, 201).status, Status.Pass)
	testing.expect_value(t, http_expect_success(ok).status, Status.Pass)

	wrong_status := http_expect_status(ok, 200)
	testing.expect_value(t, wrong_status.status, Status.Fail)
	testing.expect(t, strings.contains(wrong_status.message, "expected HTTP status 200"))

	transport := Http_Response{success = false, exit_code = 7, error = "connection refused"}
	transport_result := http_expect_success(transport)
	testing.expect_value(t, transport_result.status, Status.Fail)
	testing.expect_value(t, transport_result.message, "connection refused")
}

http_events_contain :: proc(events: []Event, text: string) -> bool {
	for event in events {
		if strings.contains(event.detail, text) {
			return true
		}
	}
	return false
}

@(test)
test_same_seed_replays_choices :: proc(t: ^testing.T) {
	a := check("seed a", same_seed_generates_same_choices, {num_tests = 1, seed = 99})
	defer destroy_check_result(&a)

	b := check("seed b", same_seed_generates_same_choices, {num_tests = 1, seed = 99})
	defer destroy_check_result(&b)

	testing.expect_value(t, len(a.replay.choices), len(b.replay.choices))
	for i in 0 ..< len(a.replay.choices) {
		testing.expect_value(t, a.replay.choices[i], b.replay.choices[i])
	}
}

@(test)
test_collection_generators_do_not_leak :: proc(t: ^testing.T) {
	result := check("collections generate", collections_are_generated_in_case_arena, {num_tests = 25, seed = 77})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_generator_combinators :: proc(t: ^testing.T) {
	result := check("combinators", combinators_generate_domain_values, {num_tests = 25, seed = 91})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_generator_catalog_primitives :: proc(t: ^testing.T) {
	result := check("generator catalog", generator_catalog_values, {num_tests = 25, seed = 191})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_sample_exposes_generator_values :: proc(t: ^testing.T) {
	samples := sample(string_alphabet("ab", 1, 5), {count = 5, seed = 901, size = 5})
	defer destroy_sample_result(&samples)

	testing.expect_value(t, len(samples.values), 5)
	for value in samples.values {
		testing.expect(t, len(value) >= 1 && len(value) <= 5)
		for ch in value {
			testing.expect(t, ch == 'a' || ch == 'b')
		}
	}
}

@(test)
test_coverage_is_aggregated_and_written_to_json :: proc(t: ^testing.T) {
	result := check("coverage", coverage_property, {num_tests = 25, seed = 301})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	all_index := coverage_index(result.coverage[:], "all")
	testing.expect(t, all_index >= 0)
	testing.expect_value(t, result.coverage[all_index].count, 25)
	testing.expect_value(t, result.coverage[all_index].required_percent, 100.0)

	json := check_result_json(result)
	defer delete(json)
	testing.expect(t, strings.contains(json, "\"coverage\""))
	testing.expect(t, strings.contains(json, "\"label\":\"all\""))
	testing.expect(t, strings.contains(json, "\"required_percent\":100.00"))
	testing.expect(t, strings.contains(json, "\"ok\":true"))

	text := check_result_text(result)
	defer delete(text)
	testing.expect(t, strings.contains(text, "all: 25 (100.00%, required 100.00%, ok)"))
}

@(test)
test_unmet_coverage_requirement_fails_check :: proc(t: ^testing.T) {
	result := check("coverage failure", coverage_failure_property, {num_tests = 10, seed = 302})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Error)
	testing.expect_value(t, result.code, "coverage_not_met")
	testing.expect_value(t, result.message, "coverage requirement not met: impossible 0.00% < required 1.00%")
	impossible_index := coverage_index(result.coverage[:], "impossible")
	testing.expect(t, impossible_index >= 0)
	testing.expect_value(t, result.coverage[impossible_index].count, 0)
	testing.expect_value(t, result.coverage[impossible_index].required_percent, 1.0)

	text := check_result_text(result)
	defer delete(text)
	testing.expect(t, strings.contains(text, "impossible: 0 (0.00%, required 1.00%, missing)"))
}

@(test)
test_coverage_warning_only_keeps_check_passing :: proc(t: ^testing.T) {
	result := check("coverage warning", coverage_failure_property, {num_tests = 10, seed = 302, coverage_warning_only = true})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.code, "ok")
	impossible_index := coverage_index(result.coverage[:], "impossible")
	testing.expect(t, impossible_index >= 0)

	json := check_result_json(result)
	defer delete(json)
	testing.expect(t, strings.contains(json, "\"label\":\"impossible\""))
	testing.expect(t, strings.contains(json, "\"ok\":false"))
}

@(test)
test_counterexample_adds_failure_context :: proc(t: ^testing.T) {
	result := check("counterexample", counterexample_property, {num_tests = 1, seed = 401})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect(t, strings.contains(result.message, "while checking invoice total"))
	testing.expect(t, strings.contains(result.message, "expected 13, got 12"))
}

@(test)
test_copy_events_preserves_static_fields :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	record_event_static_kind_status(&ctx, "stateful", "step 0", "ok", "detail")
	testing.expect(t, !ctx.events[0].name_owned)
	testing.expect(t, !ctx.events[0].detail_owned)
	testing.expect(t, ctx.events[0].name_copy)
	testing.expect(t, ctx.events[0].detail_copy)

	copied := copy_events(ctx.events[:])
	defer destroy_events(&copied)

	testing.expect_value(t, len(copied), 1)
	testing.expect_value(t, copied[0].kind, "stateful")
	testing.expect_value(t, copied[0].status, "ok")
	testing.expect(t, !copied[0].kind_owned)
	testing.expect(t, !copied[0].status_owned)
	testing.expect(t, copied[0].name_owned)
	testing.expect(t, copied[0].detail_owned)
}

@(test)
test_shrinker_keeps_consumed_choices_only :: proc(t: ^testing.T) {
	choices := [?]u64{3, 7, 1, 2}
	result := shrink_case(sequence_failure_property, choices[:], 1, 10, default_options({}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(7))
	testing.expect_value(t, len(result.choices), 2)
}

@(test)
test_shrinker_zeroes_irrelevant_choice_suffix :: proc(t: ^testing.T) {
	choices := [?]u64{1, 9, 8}
	result := shrink_case(payload_irrelevant_failure_property, choices[:], 1, 10, default_options({max_shrinks = 8}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(0))
	testing.expect_value(t, result.choices[2], u64(0))
	testing.expect_value(t, len(result.choices), 3)
}

@(test)
test_shrinker_removes_marked_command_range :: proc(t: ^testing.T) {
	choices := [?]u64{3, 1, 7, 2}
	result := shrink_case(marked_command_failure_property, choices[:], 1, 10, default_options({max_shrinks = 4}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "bad marked command")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(3))
	testing.expect_value(t, result.choices[1], u64(7))
}

@(test)
test_stateful_shrinker_removes_command_and_reduces_length :: proc(t: ^testing.T) {
	choices := [?]u64{2, 1, 7}
	result := shrink_case(bad_command_stateful_property, choices[:], 1, 10, default_options({max_shrinks = 10}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "bad command")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(7))
}

@(test)
test_fixed_size_generator_replay_stays_aligned :: proc(t: ^testing.T) {
	choices := [?]u64{3, 1, 7}
	first := run_case(fixed_array_failure_property, 1, 10, choices[:], true, true)
	defer destroy_test_case(&first)

	replayed := run_case(fixed_array_failure_property, 1, 10, first.choices[:], true, true)
	defer destroy_test_case(&replayed)

	testing.expect_value(t, first.result.status, Status.Fail)
	testing.expect_value(t, first.result.message, "bad fixed array")
	testing.expect_value(t, len(first.choices), 3)
	testing.expect_value(t, replayed.result.status, Status.Fail)
	testing.expect_value(t, replayed.result.message, "bad fixed array")
	testing.expect_value(t, len(replayed.choices), 3)
}

@(test)
test_shrinker_shortens_array_suffix_with_length_hint :: proc(t: ^testing.T) {
	choices := [?]u64{3, 1, 7, 2}
	result := shrink_case(array_suffix_failure_property, choices[:], 1, 10, default_options({max_shrinks = 8}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "array prefix contains bad value")
	testing.expect_value(t, len(result.choices), 3)
	testing.expect_value(t, result.choices[0], u64(2))
	testing.expect_value(t, result.choices[1], u64(1))
	testing.expect_value(t, result.choices[2], u64(7))
}

@(test)
test_shrinker_shortens_string_suffix_with_length_hint :: proc(t: ^testing.T) {
	choices := [?]u64{3, 0, 1, 0}
	result := shrink_case(string_suffix_failure_property, choices[:], 1, 10, default_options({max_shrinks = 8}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "string prefix contains bad byte")
	testing.expect_value(t, len(result.choices), 3)
	testing.expect_value(t, result.choices[0], u64(2))
	testing.expect_value(t, result.choices[1], u64(0))
	testing.expect_value(t, result.choices[2], u64(1))
}

@(test)
test_shrinker_removes_array_prefix_with_length_hint :: proc(t: ^testing.T) {
	choices := [?]u64{3, 1, 2, 7}
	result := shrink_case(array_contains_failure_property, choices[:], 1, 10, default_options({max_shrinks = 8}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "array contains bad value")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(7))
}

@(test)
test_shrinker_removes_string_prefix_with_length_hint :: proc(t: ^testing.T) {
	choices := [?]u64{3, 0, 0, 1}
	result := shrink_case(string_contains_failure_property, choices[:], 1, 10, default_options({max_shrinks = 8}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "string contains bad byte")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(1))
}

@(test)
test_shrinker_uses_domain_choice_hints :: proc(t: ^testing.T) {
	choices := [?]u64{1, 0, 7}
	result := shrink_case(domain_encoded_failure_property, choices[:], 1, 10, default_options({max_shrinks = 8}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "domain value should not be seven")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(0))
	testing.expect_value(t, result.choices[1], u64(7))
}

@(test)
test_shrinker_can_preserve_original_failure_labels :: proc(t: ^testing.T) {
	choices := [?]u64{1, 9}
	result := shrink_case(labelled_failure_property, choices[:], 1, 10, default_options({max_shrinks = 20, preserve_shrink_labels = true}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "labelled failure")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(0))
	testing.expect(t, labels_contain(result.labels[:], "interesting"))
}

@(test)
test_parse_check_options :: proc(t: ^testing.T) {
	args := [?]string{
		"--num-tests",
		"250",
		"--seed",
		"1234",
		"--max-size",
		"80",
		"--max-discards",
		"20",
		"--max-shrinks",
		"30",
		"--no-shrink",
		"--coverage-warning-only",
		"--preserve-shrink-labels",
	}
	options := parse_check_options(args[:])

	testing.expect_value(t, options.num_tests, 250)
	testing.expect_value(t, options.seed, u64(1234))
	testing.expect_value(t, options.max_size, 80)
	testing.expect_value(t, options.max_discards, 20)
	testing.expect_value(t, options.max_shrinks, 30)
	testing.expect(t, options.no_shrink)
	testing.expect(t, options.coverage_warning_only)
	testing.expect(t, options.preserve_shrink_labels)
}

@(test)
test_parse_output_mode :: proc(t: ^testing.T) {
	empty := [?]string{}
	text_args := [?]string{"--text"}
	json_args := [?]string{"--text", "--json"}
	testing.expect(t, use_json_output(empty[:]))
	testing.expect(t, !use_json_output(text_args[:]))
	testing.expect(t, use_json_output(json_args[:]))
}

@(test)
test_runner_help_text_lists_options_and_properties :: proc(t: ^testing.T) {
	tags := [?]string{"integer", "shrinking"}
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative, description = "adds numbers", tags = tags[:]},
	}
	text := help_text(properties[:])
	defer delete(text)

	testing.expect(t, strings.contains(text, "Usage: pbt-runner"))
	testing.expect(t, strings.contains(text, "--coverage-warning-only"))
	testing.expect(t, strings.contains(text, "--preserve-shrink-labels"))
	testing.expect(t, strings.contains(text, "--list-properties"))
	testing.expect(t, strings.contains(text, "sum [integer,shrinking] - adds numbers"))
}

@(test)
test_parse_replay :: proc(t: ^testing.T) {
	args := [?]string{
		"--replay-seed",
		"1234",
		"--replay-choices",
		"1, 2,3",
	}
	replay, ok := parse_replay(args[:])
	defer destroy_replay(&replay)

	testing.expect(t, ok)
	testing.expect_value(t, replay.seed, u64(1234))
	testing.expect_value(t, len(replay.choices), 3)
	testing.expect_value(t, replay.choices[0], u64(1))
	testing.expect_value(t, replay.choices[1], u64(2))
	testing.expect_value(t, replay.choices[2], u64(3))
}

@(test)
test_check_from_args_replays_when_requested :: proc(t: ^testing.T) {
	first := check("large values fail", fails_for_large_values, {num_tests = 100, seed = 123, shrink = true})
	defer destroy_check_result(&first)

	args := [?]string{
		"--replay-seed",
		"123",
		"--replay-choices",
		"50",
	}
	replayed := check_from_args("large values fail", fails_for_large_values, args[:])
	defer destroy_check_result(&replayed)

	testing.expect_value(t, first.replay.choices[0], u64(50))
	testing.expect_value(t, replayed.status, Status.Fail)
}

@(test)
test_check_property_from_args_selects_named_property :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "collections", property = collections_are_generated_in_case_arena},
	}
	args := [?]string{"--property", "collections", "--num-tests", "5", "--seed", "88"}

	result := check_property_from_args(properties[:], args[:])
	defer destroy_check_result(&result)

	testing.expect_value(t, result.name, "collections")
	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.num_tests, 5)
}

@(test)
test_check_property_from_args_selects_unique_substring :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "collections", property = collections_are_generated_in_case_arena},
	}
	args := [?]string{"--property", "collect", "--num-tests", "5", "--seed", "88"}

	result := check_property_from_args(properties[:], args[:])
	defer destroy_check_result(&result)

	testing.expect_value(t, result.name, "collections")
	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_check_property_from_args_rejects_ambiguous_substring :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "small sum", property = sum_is_commutative},
		{name = "large sum", property = sum_is_commutative},
	}
	args := [?]string{"--property", "sum"}

	result := check_property_from_args(properties[:], args[:])
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Error)
	testing.expect_value(t, result.code, "multiple_properties_matched")
	testing.expect_value(t, result.message, "multiple properties matched")
}

@(test)
test_check_properties_from_args_runs_all_when_no_property_selected :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "collections", property = collections_are_generated_in_case_arena},
	}
	args := [?]string{"--num-tests", "5", "--seed", "88"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.code, "ok")
	testing.expect_value(t, result.num_properties, 2)
	testing.expect_value(t, result.passed, 2)
	testing.expect_value(t, result.failed, 0)
	testing.expect_value(t, result.errors, 0)
	testing.expect_value(t, result.checks, 10)
	testing.expect_value(t, len(result.results), 2)
}

@(test)
test_check_properties_from_args_runs_selected_property_as_suite :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "collections", property = collections_are_generated_in_case_arena},
	}
	args := [?]string{"--property", "collections", "--num-tests", "5", "--seed", "88"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.num_properties, 1)
	testing.expect_value(t, result.passed, 1)
	testing.expect_value(t, result.checks, 5)
	testing.expect_value(t, len(result.results), 1)
	testing.expect_value(t, result.results[0].name, "collections")
}

@(test)
test_check_properties_from_args_reports_suite_failure :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "always fails", property = always_fails},
	}
	args := [?]string{"--num-tests", "5", "--seed", "88", "--no-shrink"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect_value(t, result.code, "suite_failed")
	testing.expect_value(t, result.passed, 1)
	testing.expect_value(t, result.failed, 1)
	testing.expect_value(t, result.errors, 0)
	testing.expect_value(t, result.checks, 6)
	testing.expect_value(t, len(result.results), 2)
	testing.expect_value(t, result.results[1].name, "always fails")
	testing.expect_value(t, result.results[1].status, Status.Fail)
}

@(test)
test_check_properties_from_args_stops_on_fail_fast :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "always fails", property = always_fails},
		{name = "sum", property = sum_is_commutative},
	}
	args := [?]string{"--num-tests", "5", "--seed", "88", "--no-shrink", "--fail-fast"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect_value(t, result.code, "suite_failed")
	testing.expect_value(t, result.fail_fast, true)
	testing.expect_value(t, result.passed, 0)
	testing.expect_value(t, result.failed, 1)
	testing.expect_value(t, result.checks, 1)
	testing.expect_value(t, len(result.results), 1)
	testing.expect_value(t, result.results[0].name, "always fails")
}

@(test)
test_check_properties_from_args_requires_property_for_replay :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "always fails", property = always_fails},
	}
	args := [?]string{"--replay-seed", "1", "--replay-choices", "50"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Error)
	testing.expect_value(t, result.code, "property_required_for_replay")
	testing.expect_value(t, len(result.results), 0)
}

@(test)
test_check_properties_from_args_filters_by_tag :: proc(t: ^testing.T) {
	core_tag := [?]string{"core"}
	collection_tag := [?]string{"collection", "arena"}
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative, tags = core_tag[:]},
		{name = "collections", property = collections_are_generated_in_case_arena, tags = collection_tag[:]},
	}
	args := [?]string{"--tag", "collection", "--num-tests", "5", "--seed", "88"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.num_properties, 1)
	testing.expect_value(t, len(result.results), 1)
	testing.expect_value(t, result.results[0].name, "collections")
}

@(test)
test_check_properties_from_args_rejects_missing_tag :: proc(t: ^testing.T) {
	core_tag := [?]string{"core"}
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative, tags = core_tag[:]},
	}
	args := [?]string{"--tag", "http"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Error)
	testing.expect_value(t, result.code, "no_properties_matched_tag")
	testing.expect_value(t, len(result.results), 0)
}

@(test)
test_properties_json_lists_registered_properties :: proc(t: ^testing.T) {
	core_tag := [?]string{"core"}
	collection_tag := [?]string{"collection", "arena"}
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative, description = "addition law", tags = core_tag[:]},
		{name = "collections", property = collections_are_generated_in_case_arena, description = "generated collections", tags = collection_tag[:]},
	}

	json := properties_json(properties[:])
	defer delete(json)

	testing.expect(t, strings.contains(json, "\"tool\":\"pbt\""))
	testing.expect(t, strings.contains(json, "\"schema_version\":1"))
	testing.expect(t, strings.contains(json, "\"name\":\"sum\""))
	testing.expect(t, strings.contains(json, "\"description\":\"addition law\""))
	testing.expect(t, strings.contains(json, "\"tags\":[\"core\"]"))
	testing.expect(t, strings.contains(json, "\"name\":\"collections\""))
	testing.expect(t, strings.contains(json, "\"tags\":[\"collection\",\"arena\"]"))
}

@(test)
test_tags_json_lists_unique_tags_and_counts :: proc(t: ^testing.T) {
	core_tag := [?]string{"core"}
	collection_tag := [?]string{"collection", "core"}
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative, tags = core_tag[:]},
		{name = "collections", property = collections_are_generated_in_case_arena, tags = collection_tag[:]},
	}

	json := tags_json(properties[:])
	defer delete(json)

	testing.expect(t, strings.contains(json, "\"tool\":\"pbt\""))
	testing.expect(t, strings.contains(json, "\"schema_version\":1"))
	testing.expect(t, strings.contains(json, "\"name\":\"core\",\"count\":2"))
	testing.expect(t, strings.contains(json, "\"properties\":[\"sum\",\"collections\"]"))
	testing.expect(t, strings.contains(json, "\"name\":\"collection\",\"count\":1"))
	testing.expect(t, strings.contains(json, "\"properties\":[\"collections\"]"))
}

@(test)
test_check_suite_result_json_includes_summary_and_results :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "always fails", property = always_fails},
	}
	args := [?]string{"--num-tests", "5", "--seed", "88", "--no-shrink"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)
	json := check_suite_result_json(result)
	defer delete(json)

	testing.expect(t, strings.contains(json, "\"kind\":\"suite\""))
	testing.expect(t, strings.contains(json, "\"status\":\"fail\""))
	testing.expect(t, strings.contains(json, "\"code\":\"suite_failed\""))
	testing.expect(t, strings.contains(json, "\"properties\":2"))
	testing.expect(t, strings.contains(json, "\"passed\":1"))
	testing.expect(t, strings.contains(json, "\"failed\":1"))
	testing.expect(t, strings.contains(json, "\"fail_fast\":false"))
	testing.expect(t, strings.contains(json, "\"failing_property\":\"always fails\""))
	testing.expect(t, strings.contains(json, "\"failing_code\":\"property_failed\""))
	testing.expect(t, strings.contains(json, "\"failing_message\":\"always fails\""))
	testing.expect(t, strings.contains(json, "\"failing_notes\":[]"))
	testing.expect(t, strings.contains(json, "\"failing_events\":[]"))
	testing.expect(t, strings.contains(json, "\"failing_num_tests\":0"))
	testing.expect(t, strings.contains(json, "\"failing_discards\":0"))
	testing.expect(t, strings.contains(json, "\"failing_duration_ns\":"))
	testing.expect(t, strings.contains(json, "\"failing_shrink_attempts\":0"))
	testing.expect(t, strings.contains(json, "\"failing_shrink_duration_ns\":0"))
	testing.expect(t, strings.contains(json, "\"results\":["))
	testing.expect(t, strings.contains(json, "\"name\":\"always fails\""))
}
