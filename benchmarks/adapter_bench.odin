package main

import "core:fmt"
import "core:os"
import "core:time"

import pbt "../pbt"

Bench_Sample :: struct {
	ns_total: i64,
	checksum: int,
}

Bench_Summary :: struct {
	best:         Bench_Sample,
	ns_total_sum: i64,
	checksum:     int,
}

Measure_Proc :: proc(units: int) -> int

measure :: proc(label: string, units, samples: int, run: Measure_Proc) -> Bench_Summary {
	summary := Bench_Summary{}
	for sample_index in 0 ..< samples {
		start := time.tick_now()
		checksum := run(units)
		duration := time.tick_diff(start, time.tick_now())
		sample := Bench_Sample {
			ns_total = time.duration_nanoseconds(duration),
			checksum = checksum,
		}
		if sample_index == 0 || sample.ns_total < summary.best.ns_total {
			summary.best = sample
		}
		summary.ns_total_sum += sample.ns_total
		summary.checksum += sample.checksum
	}

	fmt.printf("%s\n", label)
	fmt.printf("  calls/sample: %d\n", units)
	fmt.printf("  samples:      %d\n", samples)
	fmt.printf("  best ns/call: %.2f\n", sample_best_ns(summary, units))
	fmt.printf("  avg ns/call:  %.2f\n", sample_avg_ns(summary, units, samples))
	fmt.printf("  checksum:     %d\n\n", summary.checksum)
	return summary
}

sample_best_ns :: proc(summary: Bench_Summary, units: int) -> f64 {
	return f64(summary.best.ns_total) / f64(units)
}

sample_avg_ns :: proc(summary: Bench_Summary, units, samples: int) -> f64 {
	return f64(summary.ns_total_sum) / f64(units * samples)
}

one_shot_process_calls :: proc(units: int) -> int {
	ctx: pbt.T
	pbt.test_init(&ctx, 1, 1, nil, false, false)
	defer pbt.test_destroy(&ctx)

	command := [?]string{"/bin/sh", "-c", "printf ok"}
	checksum := 0
	for i in 0 ..< units {
		result := pbt.process_run(&ctx, command[:])
		if !result.success {
			return -1
		}
		checksum += len(result.stdout)
		pbt.test_reset(&ctx, u64(i + 2), 1, nil, false, false)
	}
	return checksum
}

line_protocol_calls :: proc(units: int) -> int {
	command := [?]string{"/bin/sh", "-c", "while IFS= read -r line; do printf \"%s\\n\" \"$line\"; done"}
	client, err := pbt.line_protocol_start(command[:])
	if err != nil {
		return -1
	}
	defer pbt.line_protocol_stop(&client)

	ctx: pbt.T
	pbt.test_init(&ctx, 1, 1, nil, false, false)
	defer pbt.test_destroy(&ctx)

	checksum := 0
	for i in 0 ..< units {
		request := fmt.tprintf("msg-%d", i)
		result := pbt.line_protocol_call(&ctx, &client, request)
		if !result.success {
			return -1
		}
		checksum += len(result.response)
		pbt.test_reset(&ctx, u64(i + 2), 1, nil, false, false)
	}
	return checksum
}

main :: proc() {
	units := 50
	samples := 3

	fmt.println("pbt adapter benchmark")
	fmt.println("note: subprocess timings are OS-dependent; compare relative shape on the same machine")
	fmt.println()

	one_shot := measure("one-shot process adapter", units, samples, one_shot_process_calls)
	line := measure("persistent line protocol adapter", units, samples, line_protocol_calls)

	if one_shot.checksum < 0 || line.checksum < 0 {
		fmt.println("benchmark guard: FAIL")
		os.exit(1)
	}

	fmt.println("benchmark guard: PASS")
}
