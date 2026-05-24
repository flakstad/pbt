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

Color :: enum {
	Red,
	Green,
	Blue,
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
		filtered % 2 == 0,
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
	}
	return run_commands(t, model, {min_len = 1, max_len = 20})
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
	testing.expect(t, strings.contains(json, "\"kind\":\"process\""))
	testing.expect(t, strings.contains(json, "\"name\":\"cart add\""))
	testing.expect(t, strings.contains(json, "\"about to fail\""))
	testing.expect(t, strings.contains(json, "\"labels\":[\"forced\"]"))
}

@(test)
test_stateful_runner_finds_model_mismatch :: proc(t: ^testing.T) {
	result := check("counter stateful", counter_stateful_property, {num_tests = 50, seed = 5, shrink = true})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect_value(t, result.message, "counter target diverged from model")
	testing.expect(t, len(result.shrunk_test.events) > 0)
	testing.expect(t, strings.contains(result.shrunk_test.events[0].name, "reset"))

	replayed := check_replay("counter stateful", counter_stateful_property, result.replay)
	defer destroy_check_result(&replayed)

	testing.expect_value(t, replayed.status, Status.Fail)
}

@(test)
test_process_adapter_runs_cli :: proc(t: ^testing.T) {
	result := check("process adapter", process_property, {num_tests = 3, seed = 1})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_protocol_adapter_sends_request_file :: proc(t: ^testing.T) {
	result := check("protocol adapter", protocol_property, {num_tests = 10, seed = 11})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
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
}

@(test)
test_unmet_coverage_requirement_fails_check :: proc(t: ^testing.T) {
	result := check("coverage failure", coverage_failure_property, {num_tests = 10, seed = 302})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Error)
	testing.expect_value(t, result.message, "coverage requirement not met")
	impossible_index := coverage_index(result.coverage[:], "impossible")
	testing.expect(t, impossible_index >= 0)
	testing.expect_value(t, result.coverage[impossible_index].count, 0)
	testing.expect_value(t, result.coverage[impossible_index].required_percent, 1.0)
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
	}
	options := parse_check_options(args[:])

	testing.expect_value(t, options.num_tests, 250)
	testing.expect_value(t, options.seed, u64(1234))
	testing.expect_value(t, options.max_size, 80)
	testing.expect_value(t, options.max_discards, 20)
	testing.expect_value(t, options.max_shrinks, 30)
	testing.expect(t, options.no_shrink)
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
test_properties_json_lists_registered_properties :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "collections", property = collections_are_generated_in_case_arena},
	}

	json := properties_json(properties[:])
	defer delete(json)

	testing.expect(t, strings.contains(json, "\"tool\":\"pbt\""))
	testing.expect(t, strings.contains(json, "\"schema_version\":1"))
	testing.expect(t, strings.contains(json, "\"name\":\"sum\""))
	testing.expect(t, strings.contains(json, "\"name\":\"collections\""))
}
