package pbt

import "core:fmt"
import "core:os"
import "core:strings"

check_result_json :: proc(result: Check_Result) -> string {
	builder: strings.Builder
	strings.builder_init(&builder)

	strings.write_string(&builder, "{")
	json_field_string(&builder, "tool", "pbt", true)
	json_field_int(&builder, "schema_version", 1, false)
	json_field_string(&builder, "name", result.name, false)
	json_field_string(&builder, "status", status_string(result.status), false)
	json_field_u64(&builder, "seed", result.seed, false)
	json_field_int(&builder, "num_tests", result.num_tests, false)
	json_field_int(&builder, "num_discards", result.num_discards, false)
	json_field_string(&builder, "message", result.message, false)
	strings.write_string(&builder, ",\"coverage\":")
	json_write_coverage(&builder, result.coverage[:], result.num_tests)

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

check_result_exit_code :: proc(result: Check_Result) -> int {
	if result.status == .Pass {
		return 0
	}
	return 1
}

exit_with_check_result :: proc(result: Check_Result) -> ! {
	print_check_result_json(result)
	os.exit(check_result_exit_code(result))
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
		percent := 0.0
		if num_tests > 0 {
			percent = f64(item.count) * 100.0 / f64(num_tests)
		}
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
