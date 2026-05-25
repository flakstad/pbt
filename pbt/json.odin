package pbt

import "core:fmt"
import "core:os"
import "core:strings"

CHECK_RESULT_TEXT_MAX_EVENTS :: 20

check_result_json :: proc(result: Check_Result) -> string {
	builder: strings.Builder
	strings.builder_init(&builder)

	strings.write_string(&builder, "{")
	json_field_string(&builder, "tool", "pbt", true)
	json_field_int(&builder, "schema_version", 1, false)
	json_field_string(&builder, "name", result.name, false)
	json_field_string(&builder, "status", status_string(result.status), false)
	json_field_string(&builder, "code", result.code, false)
	json_field_u64(&builder, "seed", result.seed, false)
	json_field_int(&builder, "num_tests", result.num_tests, false)
	json_field_int(&builder, "num_discards", result.num_discards, false)
	json_field_i64(&builder, "duration_ns", result.duration_ns, false)
	json_field_int(&builder, "shrink_attempts", result.shrink_attempts, false)
	json_field_i64(&builder, "shrink_duration_ns", result.shrink_duration_ns, false)
	json_field_string(&builder, "message", result.message, false)
	strings.write_string(&builder, ",\"coverage\":")
	json_write_coverage(&builder, result.coverage[:], result.num_tests)
	json_write_coverage_missing_fields(&builder, result.coverage[:], result.num_tests, "")

	strings.write_string(&builder, ",\"replay\":{")
	json_field_u64(&builder, "seed", result.replay.seed, true)
	choices_csv := replay_choices_csv(result.replay)
	defer delete(choices_csv)
	json_field_string(&builder, "choices_csv", choices_csv, false)
	strings.write_string(&builder, ",\"choices\":")
	json_write_u64_array(&builder, result.replay.choices[:])
	strings.write_string(&builder, "}")

	strings.write_string(&builder, ",\"events\":")
	json_write_events(&builder, result.shrunk_test.events[:])
	strings.write_string(&builder, ",\"notes\":")
	json_write_strings(&builder, result.shrunk_test.notes[:])

	strings.write_string(&builder, ",\"failing_test\":")
	json_write_test_case(&builder, result.failing_test)
	strings.write_string(&builder, ",\"shrunk_test\":")
	json_write_test_case(&builder, result.shrunk_test)
	strings.write_string(&builder, "}")

	return strings.to_string(builder)
}

print_check_result_json :: proc(result: Check_Result) {
	json := check_result_json(result)
	defer delete(json)
	fmt.println(json)
}

check_result_text :: proc(result: Check_Result) -> string {
	builder: strings.Builder
	strings.builder_init(&builder)

	strings.write_string(&builder, fmt.tprintf("%s: %s\n", result.name, status_string(result.status)))
	if len(result.code) > 0 {
		strings.write_string(&builder, fmt.tprintf("code: %s\n", result.code))
	}
	strings.write_string(&builder, fmt.tprintf("tests: %d, discards: %d, duration: %d ns\n", result.num_tests, result.num_discards, result.duration_ns))
	if len(result.message) > 0 {
		strings.write_string(&builder, fmt.tprintf("message: %s\n", result.message))
	}
	if result.status != .Pass {
		strings.write_string(&builder, fmt.tprintf("replay: --replay-seed %d --replay-choices ", result.replay.seed))
		choices_csv := replay_choices_csv(result.replay)
		defer delete(choices_csv)
		strings.write_string(&builder, choices_csv)
		strings.write_string(&builder, "\n")
		if result.shrink_attempts > 0 {
			strings.write_string(&builder, fmt.tprintf("shrink: %d attempts, %d ns\n", result.shrink_attempts, result.shrink_duration_ns))
		}
		write_notes_text(&builder, result.shrunk_test.notes[:])
		write_event_trace_text(&builder, result.shrunk_test.events[:])
	}
	if len(result.coverage) > 0 {
		strings.write_string(&builder, "coverage:\n")
		for item in result.coverage {
			percent := coverage_percent(item, result.num_tests)
			strings.write_string(&builder, fmt.tprintf("  %s: %d (%.2f%%", item.label, item.count, percent))
			if item.required_percent > 0 {
				strings.write_string(&builder, fmt.tprintf(", required %.2f%%", item.required_percent))
				if percent >= item.required_percent {
					strings.write_string(&builder, ", ok")
				} else {
					strings.write_string(&builder, ", missing")
				}
			}
			strings.write_string(&builder, ")\n")
		}
	}
	return strings.to_string(builder)
}

write_notes_text :: proc(builder: ^strings.Builder, notes: []string) {
	if len(notes) == 0 {
		return
	}

	strings.write_string(builder, "notes:\n")
	for note in notes {
		strings.write_string(builder, fmt.tprintf("  - %s\n", note))
	}
}

write_event_trace_text :: proc(builder: ^strings.Builder, events: []Event) {
	if len(events) == 0 {
		return
	}

	strings.write_string(builder, "events:\n")
	limit := len(events)
	if limit > CHECK_RESULT_TEXT_MAX_EVENTS {
		limit = CHECK_RESULT_TEXT_MAX_EVENTS
	}
	for i in 0 ..< limit {
		event := events[i]
		strings.write_string(builder, fmt.tprintf("  %d. %s", i + 1, event.kind))
		if len(event.name) > 0 {
			strings.write_string(builder, fmt.tprintf(" %s", event.name))
		}
		if len(event.status) > 0 {
			strings.write_string(builder, fmt.tprintf(" [%s]", event.status))
		}
		if len(event.detail) > 0 {
			strings.write_string(builder, fmt.tprintf(": %s", event.detail))
		}
		strings.write_string(builder, "\n")
	}
	if len(events) > limit {
		strings.write_string(builder, fmt.tprintf("  ... %d more events omitted\n", len(events) - limit))
	}
}

print_check_result_text :: proc(result: Check_Result) {
	text := check_result_text(result)
	defer delete(text)
	fmt.print(text)
}

print_check_result :: proc(result: Check_Result, json: bool = true) {
	if json {
		print_check_result_json(result)
	} else {
		print_check_result_text(result)
	}
}

check_suite_result_json :: proc(result: Check_Suite_Result) -> string {
	builder: strings.Builder
	strings.builder_init(&builder)

	strings.write_string(&builder, "{")
	json_field_string(&builder, "tool", "pbt", true)
	json_field_int(&builder, "schema_version", 1, false)
	json_field_string(&builder, "kind", "suite", false)
	json_field_string(&builder, "status", status_string(result.status), false)
	json_field_string(&builder, "code", result.code, false)
	json_field_int(&builder, "properties", result.num_properties, false)
	json_field_int(&builder, "passed", result.passed, false)
	json_field_int(&builder, "failed", result.failed, false)
	json_field_int(&builder, "errors", result.errors, false)
	json_field_int(&builder, "checks", result.checks, false)
	json_field_int(&builder, "discards", result.discards, false)
	json_field_bool(&builder, "fail_fast", result.fail_fast, false)
	json_field_i64(&builder, "duration_ns", result.duration_ns, false)
	json_field_string(&builder, "message", result.message, false)
	failing := check_suite_first_non_pass(result)
	json_field_string(&builder, "failing_property", failing.name, false)
	json_field_string(&builder, "failing_code", failing.code, false)
	json_field_string(&builder, "failing_message", failing.message, false)
	json_write_coverage_missing_fields(&builder, failing.coverage[:], failing.num_tests, "failing_")
	strings.write_string(&builder, ",\"failing_notes\":")
	json_write_strings(&builder, failing.shrunk_test.notes[:])
	strings.write_string(&builder, ",\"failing_events\":")
	json_write_events(&builder, failing.shrunk_test.events[:])
	json_field_int(&builder, "failing_num_tests", failing.num_tests, false)
	json_field_int(&builder, "failing_discards", failing.num_discards, false)
	json_field_i64(&builder, "failing_duration_ns", failing.duration_ns, false)
	json_field_int(&builder, "failing_shrink_attempts", failing.shrink_attempts, false)
	json_field_i64(&builder, "failing_shrink_duration_ns", failing.shrink_duration_ns, false)
	json_field_u64(&builder, "replay_seed", failing.replay.seed, false)
	failing_replay_choices := replay_choices_csv(failing.replay)
	defer delete(failing_replay_choices)
	json_field_string(&builder, "replay_choices", failing_replay_choices, false)
	strings.write_string(&builder, ",\"results\":[")
	for item, i in result.results {
		if i > 0 {
			strings.write_string(&builder, ",")
		}
		item_json := check_result_json(item)
		strings.write_string(&builder, item_json)
		delete(item_json)
	}
	strings.write_string(&builder, "]}")

	return strings.to_string(builder)
}

check_suite_first_non_pass :: proc(result: Check_Suite_Result) -> Check_Result {
	for item in result.results {
		if item.status != .Pass {
			return item
		}
	}
	return {}
}

print_check_suite_result_json :: proc(result: Check_Suite_Result) {
	json := check_suite_result_json(result)
	defer delete(json)
	fmt.println(json)
}

check_suite_result_text :: proc(result: Check_Suite_Result) -> string {
	builder: strings.Builder
	strings.builder_init(&builder)

	strings.write_string(&builder, fmt.tprintf("suite: %s\n", status_string(result.status)))
	if len(result.code) > 0 {
		strings.write_string(&builder, fmt.tprintf("code: %s\n", result.code))
	}
	strings.write_string(&builder, fmt.tprintf("properties: %d, passed: %d, failed: %d, errors: %d, checks: %d, discards: %d, fail-fast: %v, duration: %d ns\n", result.num_properties, result.passed, result.failed, result.errors, result.checks, result.discards, result.fail_fast, result.duration_ns))
	if len(result.message) > 0 {
		strings.write_string(&builder, fmt.tprintf("message: %s\n", result.message))
	}
	for item in result.results {
		strings.write_string(&builder, "\n")
		item_text := check_result_text(item)
		strings.write_string(&builder, item_text)
		delete(item_text)
	}
	return strings.to_string(builder)
}

print_check_suite_result_text :: proc(result: Check_Suite_Result) {
	text := check_suite_result_text(result)
	defer delete(text)
	fmt.print(text)
}

print_check_suite_result :: proc(result: Check_Suite_Result, json: bool = true) {
	if json {
		print_check_suite_result_json(result)
	} else {
		print_check_suite_result_text(result)
	}
}

check_result_exit_code :: proc(result: Check_Result) -> int {
	if result.status == .Pass {
		return 0
	}
	return 1
}

check_suite_result_exit_code :: proc(result: Check_Suite_Result) -> int {
	if result.status == .Pass {
		return 0
	}
	return 1
}

exit_with_check_result :: proc(result: Check_Result) -> ! {
	print_check_result_json(result)
	os.exit(check_result_exit_code(result))
}

exit_with_check_suite_result :: proc(result: Check_Suite_Result) -> ! {
	print_check_suite_result_json(result)
	os.exit(check_suite_result_exit_code(result))
}

replay_choices_csv :: proc(replay: Replay) -> string {
	return u64_list_csv(replay.choices[:])
}

u64_list_csv :: proc(values: []u64) -> string {
	builder: strings.Builder
	strings.builder_init(&builder)
	for value, i in values {
		if i > 0 {
			strings.write_string(&builder, ",")
		}
		strings.write_string(&builder, fmt.tprintf("%d", value))
	}
	return strings.to_string(builder)
}

status_string :: proc(status: Status) -> string {
	switch status {
	case .Pass:
		return "pass"
	case .Fail:
		return "fail"
	case .Discard:
		return "discard"
	case .Error:
		return "error"
	}

	return "unknown"
}

json_write_test_case :: proc(builder: ^strings.Builder, tc: Test_Case) {
	strings.write_string(builder, "{")
	json_field_string(builder, "status", status_string(tc.result.status), true)
	json_field_string(builder, "message", tc.result.message, false)
	strings.write_string(builder, ",\"choices\":")
	json_write_u64_array(builder, tc.choices[:])
	strings.write_string(builder, ",\"events\":")
	json_write_events(builder, tc.events[:])
	strings.write_string(builder, ",\"notes\":")
	json_write_strings(builder, tc.notes[:])
	strings.write_string(builder, ",\"labels\":")
	json_write_strings(builder, tc.labels[:])
	strings.write_string(builder, "}")
}

json_write_events :: proc(builder: ^strings.Builder, events: []Event) {
	strings.write_string(builder, "[")
	for event, i in events {
		if i > 0 {
			strings.write_string(builder, ",")
		}
		strings.write_string(builder, "{")
		json_field_string(builder, "kind", event.kind, true)
		json_field_string(builder, "name", event.name, false)
		json_field_string(builder, "status", event.status, false)
		json_field_string(builder, "detail", event.detail, false)
		strings.write_string(builder, "}")
	}
	strings.write_string(builder, "]")
}

json_write_strings :: proc(builder: ^strings.Builder, values: []string) {
	strings.write_string(builder, "[")
	for value, i in values {
		if i > 0 {
			strings.write_string(builder, ",")
		}
		json_write_string(builder, value)
	}
	strings.write_string(builder, "]")
}

json_write_u64_array :: proc(builder: ^strings.Builder, values: []u64) {
	strings.write_string(builder, "[")
	for value, i in values {
		if i > 0 {
			strings.write_string(builder, ",")
		}
		strings.write_string(builder, fmt.tprintf("%d", value))
	}
	strings.write_string(builder, "]")
}

json_write_coverage :: proc(builder: ^strings.Builder, coverage: []Coverage_Label, num_tests: int) {
	strings.write_string(builder, "[")
	for item, i in coverage {
		if i > 0 {
			strings.write_string(builder, ",")
		}
		percent := coverage_percent(item, num_tests)
		ok := item.required_percent <= 0 || percent >= item.required_percent

		strings.write_string(builder, "{")
		json_field_string(builder, "label", item.label, true)
		json_field_int(builder, "count", item.count, false)
		json_field_f64(builder, "percent", percent, false)
		json_field_f64(builder, "required_percent", item.required_percent, false)
		json_field_bool(builder, "ok", ok, false)
		strings.write_string(builder, "}")
	}
	strings.write_string(builder, "]")
}

json_write_coverage_missing_fields :: proc(builder: ^strings.Builder, coverage: []Coverage_Label, num_tests: int, prefix: string) {
	index := coverage_unmet_index(coverage, num_tests)
	if index < 0 {
		json_field_bool(builder, fmt.tprintf("%scoverage_missing", prefix), false, false)
		json_field_string(builder, fmt.tprintf("%scoverage_missing_label", prefix), "", false)
		json_field_f64(builder, fmt.tprintf("%scoverage_observed_percent", prefix), 0, false)
		json_field_f64(builder, fmt.tprintf("%scoverage_required_percent", prefix), 0, false)
		return
	}

	item := coverage[index]
	json_field_bool(builder, fmt.tprintf("%scoverage_missing", prefix), true, false)
	json_field_string(builder, fmt.tprintf("%scoverage_missing_label", prefix), item.label, false)
	json_field_f64(builder, fmt.tprintf("%scoverage_observed_percent", prefix), coverage_percent(item, num_tests), false)
	json_field_f64(builder, fmt.tprintf("%scoverage_required_percent", prefix), item.required_percent, false)
}

json_field_string :: proc(builder: ^strings.Builder, name, value: string, first: bool) {
	json_field_prefix(builder, name, first)
	json_write_string(builder, value)
}

json_field_int :: proc(builder: ^strings.Builder, name: string, value: int, first: bool) {
	json_field_prefix(builder, name, first)
	strings.write_string(builder, fmt.tprintf("%d", value))
}

json_field_u64 :: proc(builder: ^strings.Builder, name: string, value: u64, first: bool) {
	json_field_prefix(builder, name, first)
	strings.write_string(builder, fmt.tprintf("%d", value))
}

json_field_i64 :: proc(builder: ^strings.Builder, name: string, value: i64, first: bool) {
	json_field_prefix(builder, name, first)
	strings.write_string(builder, fmt.tprintf("%d", value))
}

json_field_f64 :: proc(builder: ^strings.Builder, name: string, value: f64, first: bool) {
	json_field_prefix(builder, name, first)
	strings.write_string(builder, fmt.tprintf("%.2f", value))
}

json_field_bool :: proc(builder: ^strings.Builder, name: string, value: bool, first: bool) {
	json_field_prefix(builder, name, first)
	if value {
		strings.write_string(builder, "true")
	} else {
		strings.write_string(builder, "false")
	}
}

json_field_prefix :: proc(builder: ^strings.Builder, name: string, first: bool) {
	if !first {
		strings.write_string(builder, ",")
	}
	json_write_string(builder, name)
	strings.write_string(builder, ":")
}

json_write_string :: proc(builder: ^strings.Builder, value: string) {
	strings.write_string(builder, "\"")
	for r in value {
		switch r {
		case '\\':
			strings.write_string(builder, "\\\\")
		case '"':
			strings.write_string(builder, "\\\"")
		case '\n':
			strings.write_string(builder, "\\n")
		case '\r':
			strings.write_string(builder, "\\r")
		case '\t':
			strings.write_string(builder, "\\t")
		case:
			strings.write_rune(builder, r)
		}
	}
	strings.write_string(builder, "\"")
}
