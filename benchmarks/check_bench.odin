package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:time"

import pbt "../pbt"

Counting_Allocator :: struct {
	backing:         runtime.Allocator,
	alloc_calls:     int,
	resize_calls:    int,
	free_calls:      int,
	bytes_requested: int,
}

Bench_Sample :: struct {
	ns_total:        i64,
	alloc_calls:     int,
	resize_calls:    int,
	free_calls:      int,
	bytes_requested: int,
	checksum:        int,
}

Bench_Summary :: struct {
	best:                Bench_Sample,
	ns_total_sum:        i64,
	alloc_calls_max:     int,
	resize_calls_max:    int,
	free_calls_max:      int,
	bytes_requested_max: int,
	checksum:            int,
}

Bench_Limit :: struct {
	label:       string,
	max_best_ns: f64,
	max_avg_ns:  f64,
}

counting_allocator :: proc(counter: ^Counting_Allocator) -> runtime.Allocator {
	return runtime.Allocator {
		procedure = counting_allocator_proc,
		data = counter,
	}
}

counting_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	counter := cast(^Counting_Allocator)allocator_data
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		counter.alloc_calls += 1
		counter.bytes_requested += size
	case .Resize, .Resize_Non_Zeroed:
		counter.resize_calls += 1
		counter.bytes_requested += size
	case .Free:
		counter.free_calls += 1
	}
	return counter.backing.procedure(
		counter.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

int_property :: proc(t: ^pbt.T) -> pbt.Result {
	a := pbt.draw(t, pbt.int_range(-1_000, 1_000))
	b := pbt.draw(t, pbt.int_range(-1_000, 1_000))
	return pbt.assert(a + b == b + a)
}

collection_property :: proc(t: ^pbt.T) -> pbt.Result {
	values := pbt.draw(t, pbt.array(pbt.int_range(0, 100), 0, 20))
	name := pbt.draw(t, pbt.string_alphabet("abcdef012345", 0, 20))
	return pbt.assert(len(values) >= 0 && len(name) >= 0)
}

cli_command_property :: proc(t: ^pbt.T) -> pbt.Result {
	command := pbt.draw(t, pbt.process_command_ascii("target-cli", 0, 8, 16))
	flag := pbt.draw(t, pbt.cli_flag_ascii(12))
	return pbt.assert(len(command) > 0 && command[0] == "target-cli" && len(flag) > 2)
}

protocol_property :: proc(t: ^pbt.T) -> pbt.Result {
	request := pbt.draw(t, pbt.http_request_ascii("http://127.0.0.1:8080/api", 4, 12, 4, 16))
	items := pbt.draw(t, pbt.json_array_ascii(0, 6, 16))
	fields := [?]string{"sku", "quantity", "active"}
	body := pbt.draw(t, pbt.json_object_fields_ascii(fields[:], 16))
	partial_body := pbt.draw(t, pbt.json_object_field_subset_ascii(fields[:], 1, 2, 16))
	status_values := [?]string{"draft", "active", "archived"}
	schema := [?]pbt.JSON_Field_ASCII {
		pbt.json_string_field_ascii("sku", 16),
		pbt.json_string_enum_field_ascii("status", status_values[:]),
		pbt.json_int_field_ascii("quantity", 1, 100),
		pbt.json_bool_field_ascii("active"),
	}
	typed_body := pbt.draw(t, pbt.json_object_schema_ascii(schema[:]))
	typed_partial_body := pbt.draw(t, pbt.json_object_schema_subset_ascii(schema[:], 1, 2))
	typed_items := pbt.draw(t, pbt.json_array_of_ascii(pbt.json_object_schema_ascii(schema[:]), 1, 4))
	body_request := pbt.draw(t, pbt.http_request_body_ascii("http://127.0.0.1:8080/api", pbt.json_object_schema_ascii(schema[:]), 4, 12))
	return pbt.assert(len(request.method) > 0 && len(request.url) > 0 && len(items) >= 2 && len(body) >= 2 && len(partial_body) >= 2 && len(typed_body) >= 2 && len(typed_partial_body) >= 2 && len(typed_items) >= 2 && len(body_request.body) >= 2)
}

failure_property :: proc(t: ^pbt.T) -> pbt.Result {
	value := pbt.draw(t, pbt.int_range(0, 100))
	return pbt.assert(value < 50)
}

payload_failure_property :: proc(t: ^pbt.T) -> pbt.Result {
	marker := pbt.draw(t, pbt.int_range(0, 1))
	_ = pbt.draw(t, pbt.array(pbt.int_range(0, 100), 4, 4))
	_ = pbt.draw(t, pbt.string_alphabet("abcdef012345", 4, 4))
	return pbt.assert(marker == 0)
}

State :: struct {
	value: int,
}

Command :: enum {
	Inc,
	Dec,
}

stateful_initial :: proc(t: ^pbt.T, target: rawptr) -> State {
	return {}
}

stateful_command :: proc(t: ^pbt.T, state: State) -> Command {
	return Command(pbt.draw(t, pbt.int_range(0, 1)))
}

stateful_run :: proc(t: ^pbt.T, target: rawptr, state: State, command: Command) -> int {
	switch command {
	case .Inc:
		return state.value + 1
	case .Dec:
		if state.value > 0 {
			return state.value - 1
		}
	}
	return state.value
}

stateful_next :: proc(state: State, command: Command, value: int) -> State {
	return {value = value}
}

stateful_postcondition :: proc(state: State, command: Command, value: int) -> pbt.Result {
	return pbt.assert(value >= 0)
}

stateful_command_name :: proc(command: Command) -> string {
	switch command {
	case .Inc:
		return "inc"
	case .Dec:
		return "dec"
	}
	return "unknown"
}

stateful_property :: proc(t: ^pbt.T) -> pbt.Result {
	model := pbt.State_Model(State, Command, int) {
		initial = stateful_initial,
		command = stateful_command,
		run = stateful_run,
		next_state = stateful_next,
		postcondition = stateful_postcondition,
		command_name = stateful_command_name,
	}
	return pbt.run_commands(t, model, {min_len = 20, max_len = 20})
}

stateful_compact_trace_property :: proc(t: ^pbt.T) -> pbt.Result {
	model := pbt.State_Model(State, Command, int) {
		initial = stateful_initial,
		command = stateful_command,
		run = stateful_run,
		next_state = stateful_next,
		postcondition = stateful_postcondition,
		command_name = stateful_command_name,
	}
	return pbt.run_commands(t, model, {min_len = 20, max_len = 20, skip_success_events = true})
}

stateful_command_trace_property :: proc(t: ^pbt.T) -> pbt.Result {
	model := pbt.State_Model(State, Command, int) {
		initial = stateful_initial,
		command = stateful_command,
		run = stateful_run,
		next_state = stateful_next,
		postcondition = stateful_postcondition,
		command_name = stateful_command_name,
	}
	return pbt.run_commands(t, model, {min_len = 20, max_len = 20, compact_success_events = true})
}

measure_check :: proc(
	label: string,
	property: pbt.Property,
	num_tests: int,
	sample_count: int,
	options: pbt.Check_Options = {},
) -> Bench_Summary {
	return measure_check_units(label, property, num_tests, num_tests, "generated tests/sample", sample_count, options)
}

measure_check_units :: proc(
	label: string,
	property: pbt.Property,
	num_tests: int,
	units: int,
	unit_label: string,
	sample_count: int,
	options: pbt.Check_Options = {},
) -> Bench_Summary {
	summary := Bench_Summary{}

	for sample_index in 0 ..< sample_count {
		counter := Counting_Allocator{backing = context.allocator}
		old_allocator := context.allocator
		context.allocator = counting_allocator(&counter)

		start := time.tick_now()
		result := pbt.check(label, property, {
			num_tests = num_tests,
			seed = u64(123 + sample_index),
			no_shrink = options.no_shrink,
			max_size = options.max_size,
			max_discards = options.max_discards,
			max_shrinks = options.max_shrinks,
		})
		checksum := int(result.status) + result.num_tests + result.num_discards + len(result.replay.choices)
		pbt.destroy_check_result(&result)
		duration := time.tick_diff(start, time.tick_now())

		context.allocator = old_allocator

		summarize_sample(&summary, Bench_Sample {
			ns_total = time.duration_nanoseconds(duration),
			alloc_calls = counter.alloc_calls,
			resize_calls = counter.resize_calls,
			free_calls = counter.free_calls,
			bytes_requested = counter.bytes_requested,
			checksum = checksum,
		}, sample_index)
	}

	print_summary(label, units, unit_label, sample_count, summary)
	return summary
}

measure_captured_cases :: proc(
	label: string,
	property: pbt.Property,
	case_count: int,
	sample_count: int,
) -> Bench_Summary {
	summary := Bench_Summary{}

	for sample_index in 0 ..< sample_count {
		counter := Counting_Allocator{backing = context.allocator}
		old_allocator := context.allocator
		context.allocator = counting_allocator(&counter)

		start := time.tick_now()
		checksum := 0
		for case_index in 0 ..< case_count {
			tc := pbt.run_case(property, u64(2_000 + sample_index * case_count + case_index), 20, nil, false, true, true)
			checksum += len(tc.events) + len(tc.choices)
			pbt.destroy_test_case(&tc)
		}
		duration := time.tick_diff(start, time.tick_now())

		context.allocator = old_allocator

		summarize_sample(&summary, Bench_Sample {
			ns_total = time.duration_nanoseconds(duration),
			alloc_calls = counter.alloc_calls,
			resize_calls = counter.resize_calls,
			free_calls = counter.free_calls,
			bytes_requested = counter.bytes_requested,
			checksum = checksum,
		}, sample_index)
	}

	print_summary(label, case_count, "captured cases/sample", sample_count, summary)
	return summary
}

measure_sample_arrays :: proc(sample_count_per_run: int, sample_count: int) -> Bench_Summary {
	summary := Bench_Summary{}

	for sample_index in 0 ..< sample_count {
		counter := Counting_Allocator{backing = context.allocator}
		old_allocator := context.allocator
		context.allocator = counting_allocator(&counter)

		start := time.tick_now()
		samples := pbt.sample(pbt.array(pbt.int_range(0, 9), 8, 8), {count = sample_count_per_run, seed = u64(4_000 + sample_index), size = 8})
		checksum := len(samples.values) + samples.ctx.choice_count + len(samples.ctx.choice_extra)
		pbt.destroy_sample_result(&samples)
		duration := time.tick_diff(start, time.tick_now())

		context.allocator = old_allocator

		summarize_sample(&summary, Bench_Sample {
			ns_total = time.duration_nanoseconds(duration),
			alloc_calls = counter.alloc_calls,
			resize_calls = counter.resize_calls,
			free_calls = counter.free_calls,
			bytes_requested = counter.bytes_requested,
			checksum = checksum,
		}, sample_index)
	}

	print_summary("sample array values", sample_count_per_run, "samples/run", sample_count, summary)
	return summary
}

summarize_sample :: proc(summary: ^Bench_Summary, sample: Bench_Sample, sample_index: int) {
	if sample_index == 0 || sample.ns_total < summary.best.ns_total {
		summary.best = sample
	}
	summary.ns_total_sum += sample.ns_total
	if sample.alloc_calls > summary.alloc_calls_max do summary.alloc_calls_max = sample.alloc_calls
	if sample.resize_calls > summary.resize_calls_max do summary.resize_calls_max = sample.resize_calls
	if sample.free_calls > summary.free_calls_max do summary.free_calls_max = sample.free_calls
	if sample.bytes_requested > summary.bytes_requested_max do summary.bytes_requested_max = sample.bytes_requested
	summary.checksum += sample.checksum
}

print_summary :: proc(label: string, units: int, unit_label: string, sample_count: int, summary: Bench_Summary) {
	fmt.printf("%s\n", label)
	fmt.printf("  %s: %d\n", unit_label, units)
	fmt.printf("  samples:                %d\n", sample_count)
	fmt.printf("  best ns/unit:           %.2f\n", sample_best_ns(summary, units))
	fmt.printf("  avg ns/unit:            %.2f\n", sample_avg_ns(summary, units, sample_count))
	fmt.printf("  alloc calls max:        %d\n", summary.alloc_calls_max)
	fmt.printf("  resize calls max:       %d\n", summary.resize_calls_max)
	fmt.printf("  free calls max:         %d\n", summary.free_calls_max)
	fmt.printf("  bytes req max:          %d\n", summary.bytes_requested_max)
	fmt.printf("  checksum:               %d\n\n", summary.checksum)
}

sample_best_ns :: proc(summary: Bench_Summary, units: int) -> f64 {
	return f64(summary.best.ns_total) / f64(units)
}

sample_avg_ns :: proc(summary: Bench_Summary, units: int, sample_count: int) -> f64 {
	return f64(summary.ns_total_sum) / f64(units * sample_count)
}

check_limit :: proc(summary: Bench_Summary, units: int, sample_count: int, limit: Bench_Limit) -> bool {
	ok := true
	best_ns := sample_best_ns(summary, units)
	avg_ns := sample_avg_ns(summary, units, sample_count)

	if limit.max_best_ns > 0 && best_ns > limit.max_best_ns {
		fmt.printf("REGRESSION: %s best %.2f ns exceeds %.2f ns\n", limit.label, best_ns, limit.max_best_ns)
		ok = false
	}
	if limit.max_avg_ns > 0 && avg_ns > limit.max_avg_ns {
		fmt.printf("REGRESSION: %s avg %.2f ns exceeds %.2f ns\n", limit.label, avg_ns, limit.max_avg_ns)
		ok = false
	}
	return ok
}

main :: proc() {
	tests := 100_000
	samples := 5

	fmt.println("pbt check benchmark")
	fmt.println("note: allocation counts include complete pbt.check lifecycle and result destruction")
	fmt.println()

	ints := measure_check("two integer draws", int_property, tests, samples, {no_shrink = true})
	collections := measure_check("array and string draws", collection_property, tests, samples, {no_shrink = true})
	cli_commands := measure_check("cli command data", cli_command_property, tests, samples, {no_shrink = true})
	protocol := measure_check("protocol request data", protocol_property, tests, samples, {no_shrink = true})
	stateful := measure_check("stateful 20-step model", stateful_property, tests / 10, samples, {no_shrink = true})
	stateful_trace := measure_captured_cases("stateful 20-step captured trace", stateful_property, 10_000, samples)
	stateful_command_trace := measure_captured_cases("stateful 20-step command trace", stateful_command_trace_property, 10_000, samples)
	stateful_compact_trace := measure_captured_cases("stateful 20-step compact trace", stateful_compact_trace_property, 10_000, samples)
	failing := measure_check_units("failing property with shrink", failure_property, 100, 1, "checks/sample", samples)
	payload_failing := measure_check_units("payload failure with shrink", payload_failure_property, 100, 1, "checks/sample", samples)
	sample_arrays := measure_sample_arrays(10_000, samples)

	ok := true
	ok = check_limit(ints, tests, samples, {label = "two integer draws", max_best_ns = 250, max_avg_ns = 350}) && ok
	ok = check_limit(collections, tests, samples, {label = "array and string draws", max_best_ns = 750, max_avg_ns = 1_000}) && ok
	ok = check_limit(cli_commands, tests, samples, {label = "cli command data", max_best_ns = 1_000, max_avg_ns = 1_500}) && ok
	ok = check_limit(protocol, tests, samples, {label = "protocol request data", max_best_ns = 5_500, max_avg_ns = 6_500}) && ok
	ok = check_limit(stateful, tests / 10, samples, {label = "stateful 20-step model", max_best_ns = 750, max_avg_ns = 1_000}) && ok
	ok = check_limit(stateful_trace, 10_000, samples, {label = "stateful 20-step captured trace", max_best_ns = 20_000, max_avg_ns = 30_000}) && ok
	ok = check_limit(stateful_command_trace, 10_000, samples, {label = "stateful 20-step command trace", max_best_ns = 5_000, max_avg_ns = 10_000}) && ok
	ok = check_limit(stateful_compact_trace, 10_000, samples, {label = "stateful 20-step compact trace", max_best_ns = 5_000, max_avg_ns = 10_000}) && ok
	ok = check_limit(failing, 100, samples, {label = "failing property with shrink", max_best_ns = 250_000, max_avg_ns = 350_000}) && ok
	ok = check_limit(payload_failing, 100, samples, {label = "payload failure with shrink", max_best_ns = 350_000, max_avg_ns = 500_000}) && ok
	ok = check_limit(sample_arrays, 10_000, samples, {label = "sample array values", max_best_ns = 750, max_avg_ns = 1_000}) && ok

	if ok {
		fmt.println("benchmark guard: PASS")
	} else {
		fmt.println("benchmark guard: FAIL")
		os.exit(1)
	}
}
