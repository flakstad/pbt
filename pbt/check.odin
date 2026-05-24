package pbt

import "core:fmt"
import "core:testing"
import "core:time"

Property :: proc(t: ^T) -> Result

Check_Options :: struct {
	num_tests:    int,
	max_discards: int,
	seed:         u64,
	max_size:     int,
	shrink:       bool,
	no_shrink:    bool,
	max_shrinks:  int,
	coverage_warning_only: bool,
}

Replay :: struct {
	seed:    u64,
	choices: [dynamic]u64,
}

Coverage_Label :: struct {
	label:            string,
	count:            int,
	required_percent: f64,
}

Check_Result :: struct {
	name:         string,
	status:       Status,
	code:         string,
	seed:         u64,
	num_tests:    int,
	num_discards: int,
	duration_ns:  i64,
	shrink_attempts: int,
	shrink_duration_ns: i64,
	coverage:     [dynamic]Coverage_Label,
	failing_test: Test_Case,
	shrunk_test:  Test_Case,
	replay:       Replay,
	message:      string,
}

Check_Suite_Result :: struct {
	status:       Status,
	code:         string,
	num_properties: int,
	passed:       int,
	failed:       int,
	errors:       int,
	checks:       int,
	discards:     int,
	fail_fast:    bool,
	duration_ns:  i64,
	message:      string,
	results:      [dynamic]Check_Result,
}

default_options :: proc(options: Check_Options) -> Check_Options {
	o := options
	if o.num_tests <= 0 {
		o.num_tests = 100
	}
	if o.max_discards <= 0 {
		o.max_discards = o.num_tests * 10
	}
	if o.seed == 0 {
		o.seed = 0x9e37_79b9_7f4a_7c15
	}
	if o.max_size <= 0 {
		o.max_size = 100
	}
	if o.no_shrink {
		o.shrink = false
	} else if !o.shrink {
		o.shrink = true
	}
	if o.max_shrinks <= 0 {
		o.max_shrinks = 1_000
	}
	return o
}

check :: proc(name: string, property: Property, options: Check_Options = {}) -> Check_Result {
	opts := default_options(options)
	start_time := time.tick_now()

	result := Check_Result {
		name = name,
		status = .Pass,
		code = "ok",
		seed = opts.seed,
	}

	runner: T
	test_init(&runner, opts.seed, 1, nil, false, false)
	defer test_destroy(&runner)

	test_index := 0
	discards := 0
	for test_index < opts.num_tests {
		size := size_for_test(test_index, opts)
		case_seed := opts.seed + u64(test_index)
		tc := run_case_with_context(&runner, property, case_seed, size, nil, false, false, false, &result.coverage)
		switch tc.result.status {
		case .Pass:
			result.num_tests += 1
			test_index += 1
			destroy_test_case(&tc)
		case .Discard:
			result.num_discards += 1
			discards += 1
			destroy_test_case(&tc)
			if discards > opts.max_discards {
				result.status = .Error
				result.code = "too_many_discards"
				result.message = "too many discarded tests"
				result.duration_ns = time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
				return result
			}
		case .Fail, .Error:
			captured := run_case(property, case_seed, size, tc.choices[:], true, true, true)
			destroy_test_case(&tc)
			tc = captured

			result.status = tc.result.status
			result.code = result_code_for_status(tc.result.status)
			result.message = tc.result.message
			result.failing_test = tc
			if opts.shrink {
				shrink_start := time.tick_now()
				shrink_result := shrink_case_with_stats(property, tc.choices[:], case_seed, size, opts)
				result.shrunk_test = shrink_result.test
				result.shrink_attempts = shrink_result.attempts
				result.shrink_duration_ns = time.duration_nanoseconds(time.tick_diff(shrink_start, time.tick_now()))
			} else {
				result.shrunk_test = Test_Case {
					choices = copy_choices(tc.choices[:]),
					choice_marks = copy_choice_marks(tc.choice_marks[:]),
					events = copy_events(tc.events[:]),
					notes = copy_strings(tc.notes[:]),
					labels = copy_strings(tc.labels[:]),
					result = tc.result,
				}
			}
			result.replay = Replay {
				seed = case_seed,
				choices = copy_choices(result.shrunk_test.choices[:]),
			}
			result.duration_ns = time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
			return result
		}
	}

	if !opts.coverage_warning_only && !coverage_requirements_met(result.coverage[:], result.num_tests) {
		result.status = .Error
		result.code = "coverage_not_met"
		result.message = coverage_failure_message(result.coverage[:], result.num_tests)
	}
	result.duration_ns = time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
	return result
}

check_replay :: proc(name: string, property: Property, replay: Replay, options: Check_Options = {}) -> Check_Result {
	start_time := time.tick_now()
	opts := default_options(options)
	tc := run_case(property, replay.seed, opts.max_size, replay.choices[:], true, true)
	result := Check_Result {
		name = name,
		status = tc.result.status,
		code = result_code_for_status(tc.result.status),
		seed = replay.seed,
		num_tests = 1,
		failing_test = tc,
		shrunk_test = Test_Case {
			choices = copy_choices(tc.choices[:]),
			choice_marks = copy_choice_marks(tc.choice_marks[:]),
			events = copy_events(tc.events[:]),
			notes = copy_strings(tc.notes[:]),
			labels = copy_strings(tc.labels[:]),
			result = tc.result,
		},
		replay = Replay {
			seed = replay.seed,
			choices = copy_choices(tc.choices[:]),
		},
		message = tc.result.message,
	}
	result.duration_ns = time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
	return result
}

result_code_for_status :: proc(status: Status) -> string {
	switch status {
	case .Pass:
		return "ok"
	case .Fail:
		return "property_failed"
	case .Discard:
		return "property_discarded"
	case .Error:
		return "property_error"
	}
	return "unknown"
}

destroy_check_result :: proc(result: ^Check_Result) {
	destroy_coverage(&result.coverage)
	destroy_test_case(&result.failing_test)
	destroy_test_case(&result.shrunk_test)
	delete(result.replay.choices)
}

destroy_check_suite_result :: proc(result: ^Check_Suite_Result) {
	for i := 0; i < len(result.results); i += 1 {
		destroy_check_result(&result.results[i])
	}
	delete(result.results)
}

check_result_effective_checks :: proc(result: Check_Result) -> int {
	if result.num_tests > 0 {
		return result.num_tests
	}
	if result.status != .Pass {
		return 1
	}
	return 0
}

require_pass :: proc(t: ^testing.T, result: Check_Result) {
	if result.status == .Pass {
		testing.expect(t, true)
		return
	}

	if len(result.message) > 0 {
		fmt.println(result.message)
	}
	fmt.printf("property %q failed with seed %v and choices %v\n", result.name, result.replay.seed, result.replay.choices[:])
	testing.expect(t, false)
}

run_case :: proc(property: Property, seed: u64, size: int, replay_choices: []u64, replay_strict: bool, capture_pass: bool, capture_events: bool = true, coverage: ^[dynamic]Coverage_Label = nil, capture_choice_marks: bool = false) -> Test_Case {
	t: T
	test_init(&t, seed, size, replay_choices, replay_strict, capture_events)
	t.capture_choice_marks = capture_choice_marks
	defer test_destroy(&t)

	return run_case_with_context(&t, property, seed, size, replay_choices, replay_strict, capture_pass, capture_events, coverage, capture_choice_marks)
}

run_case_with_context :: proc(t: ^T, property: Property, seed: u64, size: int, replay_choices: []u64, replay_strict: bool, capture_pass: bool, capture_events: bool = true, coverage: ^[dynamic]Coverage_Label = nil, capture_choice_marks: bool = false) -> Test_Case {
	test_reset(t, seed, size, replay_choices, replay_strict, capture_events)
	t.capture_choice_marks = capture_choice_marks

	result := property(t)
	if t.force_discard && result.status == .Pass {
		result = discard(t.discard_message)
	}
	if t.replay_overrun {
		result = discard("replay choice stream exhausted")
	}
	if coverage != nil && result.status == .Pass && (len(t.labels) > 0 || len(t.coverage_requirements) > 0) {
		merge_case_coverage(coverage, t.labels[:], t.coverage_requirements[:])
	}
	tc := Test_Case{result = result}
	if capture_pass || result.status == .Fail || result.status == .Error {
		tc.choices = copy_current_choices(t)
		if result.status == .Fail || result.status == .Error {
			tc.choice_marks = copy_current_choice_marks(t)
		}
		tc.events = copy_events(t.events[:])
		tc.notes = copy_strings(t.notes[:])
		tc.labels = copy_strings(t.labels[:])
	}
	return tc
}

shrink_case :: proc(property: Property, choices: []u64, seed: u64, size: int, options: Check_Options) -> Test_Case {
	return shrink_case_with_stats(property, choices, seed, size, options).test
}

Shrink_Result :: struct {
	test:     Test_Case,
	attempts: int,
}

shrink_case_with_stats :: proc(property: Property, choices: []u64, seed: u64, size: int, options: Check_Options) -> Shrink_Result {
	runner: T
	test_init(&runner, seed, size, choices, true, true)
	defer test_destroy(&runner)

	initial := run_case_with_context(&runner, property, seed, size, choices, true, true, true, nil, true)
	defer destroy_test_case(&initial)

	best := Test_Case {
		choices = copy_choices(choices),
		choice_marks = copy_choice_marks(initial.choice_marks[:]),
		events = copy_events(initial.events[:]),
		notes = copy_strings(initial.notes[:]),
		labels = copy_strings(initial.labels[:]),
		result = initial.result,
	}

	attempts := 0
	changed := true
	for changed && attempts < options.max_shrinks {
		changed = false

		if len(best.choices) > 0 && try_candidate(&runner, property, &best, best.choices[:len(best.choices) - 1], seed, size, &attempts, options.max_shrinks) {
			changed = true
			continue
		}

		if shrink_choice_mark_ranges(&runner, property, &best, seed, size, &attempts, options.max_shrinks) {
			changed = true
			continue
		}

		if shrink_choice_chunks(&runner, property, &best, seed, size, &attempts, options.max_shrinks) {
			changed = true
			continue
		}

		if shrink_choice_suffix_values(&runner, property, &best, seed, size, &attempts, options.max_shrinks) {
			changed = true
			continue
		}

		for i in 0 ..< len(best.choices) {
			if shrink_choice_value(&runner, property, &best, i, seed, size, &attempts, options.max_shrinks) {
				changed = true
				break
			}
		}
	}

	return {test = best, attempts = attempts}
}

shrink_choice_mark_ranges :: proc(runner: ^T, property: Property, best: ^Test_Case, seed: u64, size: int, attempts: ^int, max_attempts: int) -> bool {
	if len(best.choice_marks) == 0 || len(best.choices) < 2 {
		return false
	}

	for i := len(best.choice_marks) - 1; i >= 0; i -= 1 {
		start := best.choice_marks[i].index
		end := len(best.choices)
		if i + 1 < len(best.choice_marks) {
			end = best.choice_marks[i + 1].index
		}
		if start < 0 || start >= end || end > len(best.choices) {
			continue
		}

		candidate := choices_without_range(best.choices[:], start, end - start)
		if try_candidate_dynamic(runner, property, best, candidate, seed, size, attempts, max_attempts) {
			return true
		}
		if attempts^ >= max_attempts {
			return false
		}
	}

	return false
}

shrink_choice_chunks :: proc(runner: ^T, property: Property, best: ^Test_Case, seed: u64, size: int, attempts: ^int, max_attempts: int) -> bool {
	if len(best.choices) < 2 {
		return false
	}

	chunk := len(best.choices) / 2
	for chunk > 0 && attempts^ < max_attempts {
		start := 0
		for start + chunk <= len(best.choices) && attempts^ < max_attempts {
			candidate := choices_without_range(best.choices[:], start, chunk)
			if try_candidate_dynamic(runner, property, best, candidate, seed, size, attempts, max_attempts) {
				return true
			}
			start += 1
		}
		chunk /= 2
	}

	return false
}

shrink_choice_suffix_values :: proc(runner: ^T, property: Property, best: ^Test_Case, seed: u64, size: int, attempts: ^int, max_attempts: int) -> bool {
	if len(best.choices) < 2 {
		return false
	}

	for start in 0 ..< len(best.choices) {
		changed := false
		candidate := copy_choices(best.choices[:])
		for i in start ..< len(candidate) {
			if candidate[i] != 0 {
				candidate[i] = 0
				changed = true
			}
		}
		if !changed {
			delete(candidate)
			continue
		}
		if try_candidate_dynamic(runner, property, best, candidate, seed, size, attempts, max_attempts) {
			return true
		}
		if attempts^ >= max_attempts {
			return false
		}
	}

	return false
}

shrink_choice_value :: proc(runner: ^T, property: Property, best: ^Test_Case, index: int, seed: u64, size: int, attempts: ^int, max_attempts: int) -> bool {
	current := best.choices[index]
	if current == 0 {
		return false
	}

	changed := false
	low: u64 = 0
	high := current
	for low < high && attempts^ < max_attempts {
		mid := low + (high - low) / 2
		candidate := copy_choices(best.choices[:])
		candidate[index] = mid

		if try_candidate_dynamic(runner, property, best, candidate, seed, size, attempts, max_attempts) {
			changed = true
			high = best.choices[index]
		} else {
			low = mid + 1
		}
	}

	return changed
}

try_candidate :: proc(runner: ^T, property: Property, best: ^Test_Case, candidate: []u64, seed: u64, size: int, attempts: ^int, max_attempts: int) -> bool {
	candidate_copy := copy_choices(candidate)
	return try_candidate_dynamic(runner, property, best, candidate_copy, seed, size, attempts, max_attempts)
}

try_candidate_dynamic :: proc(runner: ^T, property: Property, best: ^Test_Case, candidate: [dynamic]u64, seed: u64, size: int, attempts: ^int, max_attempts: int) -> bool {
	if attempts^ >= max_attempts {
		delete(candidate)
		return false
	}

	attempts^ += 1
	tc := run_case_with_context(runner, property, seed, size, candidate[:], true, true, true, nil, true)
	if tc.result.status == .Fail || tc.result.status == .Error {
		actual_choices := copy_choices(tc.choices[:])
		actual_marks := copy_choice_marks(tc.choice_marks[:])
		destroy_test_case(best)
		best.choices = actual_choices
		best.choice_marks = actual_marks
		best.events = copy_events(tc.events[:])
		best.notes = copy_strings(tc.notes[:])
		best.labels = copy_strings(tc.labels[:])
		best.result = tc.result
		destroy_test_case(&tc)
		delete(candidate)
		return true
	}

	destroy_test_case(&tc)
	delete(candidate)
	return false
}

choices_without_range :: proc(src: []u64, start, count: int, allocator := context.allocator) -> [dynamic]u64 {
	dst := make([dynamic]u64, 0, len(src) - count, allocator)
	for value, i in src {
		if i >= start && i < start + count {
			continue
		}
		append(&dst, value)
	}
	return dst
}

size_for_test :: proc(test_index: int, options: Check_Options) -> int {
	if options.num_tests <= 1 {
		return options.max_size
	}

	return 1 + (test_index * options.max_size) / (options.num_tests - 1)
}

merge_case_coverage :: proc(coverage: ^[dynamic]Coverage_Label, labels: []string, requirements: []Coverage_Requirement) {
	for requirement in requirements {
		index := coverage_index(coverage^[:], requirement.label)
		if index < 0 {
			append(coverage, Coverage_Label {
				label = clone_non_empty(requirement.label),
				required_percent = requirement.required_percent,
			})
		} else if requirement.required_percent > coverage^[index].required_percent {
			coverage^[index].required_percent = requirement.required_percent
		}
	}

	for label, i in labels {
		if label_seen_before(labels, i, label) {
			continue
		}
		index := coverage_index(coverage^[:], label)
		if index < 0 {
			append(coverage, Coverage_Label {
				label = clone_non_empty(label),
				count = 1,
			})
		} else {
			coverage^[index].count += 1
		}
	}
}

coverage_requirements_met :: proc(coverage: []Coverage_Label, num_tests: int) -> bool {
	return coverage_unmet_index(coverage, num_tests) < 0
}

coverage_failure_message :: proc(coverage: []Coverage_Label, num_tests: int) -> string {
	index := coverage_unmet_index(coverage, num_tests)
	if index < 0 {
		return "coverage requirement not met"
	}

	item := coverage[index]
	percent := coverage_percent(item, num_tests)
	return fmt.tprintf("coverage requirement not met: %s %.2f%% < required %.2f%%", item.label, percent, item.required_percent)
}

coverage_unmet_index :: proc(coverage: []Coverage_Label, num_tests: int) -> int {
	if num_tests <= 0 {
		return -1
	}
	for item, i in coverage {
		if item.required_percent <= 0 {
			continue
		}
		percent := coverage_percent(item, num_tests)
		if percent < item.required_percent {
			return i
		}
	}
	return -1
}

coverage_percent :: proc(item: Coverage_Label, num_tests: int) -> f64 {
	if num_tests <= 0 {
		return 0.0
	}
	return f64(item.count) * 100.0 / f64(num_tests)
}

coverage_index :: proc(coverage: []Coverage_Label, label: string) -> int {
	for item, i in coverage {
		if item.label == label {
			return i
		}
	}
	return -1
}

label_seen_before :: proc(labels: []string, index: int, label: string) -> bool {
	for i in 0 ..< index {
		if labels[i] == label {
			return true
		}
	}
	return false
}

destroy_coverage :: proc(coverage: ^[dynamic]Coverage_Label) {
	for item in coverage^ {
		if len(item.label) > 0 {
			delete(item.label)
		}
	}
	delete(coverage^)
}
