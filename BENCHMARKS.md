# Benchmarks

Benchmarks are part of the development feedback loop. Performance changes should
be measured before and after when they affect generation, shrinking, replay,
stateful testing, allocation behavior, or Gransk runner output.

## Check Benchmark

Benchmark source:

```text
benchmarks/check_bench.odin
```

Run:

```sh
odin run benchmarks/check_bench.odin -file -o:speed
```

The benchmark measures complete `pbt.check` runs, including result destruction.
It reports:

- best and average nanoseconds per generated test across repeated samples
- maximum allocator calls across samples
- maximum resize calls across samples
- maximum free calls across samples
- maximum bytes requested across samples
- a loose regression guard

The benchmark includes these modes:

- `two integer draws`: a passing property drawing two integers
- `array and string draws`: a passing property drawing an integer array and
  fixed-alphabet string
- `stateful 20-step model`: a passing stateful model with a fixed 20-command
  sequence
- `stateful 20-step captured trace`: the same model run with explicit event
  capture, measuring rich successful-step trace cost
- `stateful 20-step compact trace`: the same captured run with
  `skip_success_events`, measuring the compact trace path
- `failing property with shrink`: a failing property that shrinks an integer
  boundary case

## Adapter Benchmark

Benchmark source:

```text
benchmarks/adapter_bench.odin
```

Run:

```sh
odin run benchmarks/adapter_bench.odin -file -o:speed
```

The benchmark measures external-target adapter call overhead:

- `one-shot process adapter`: starts a short shell process for each call
- `persistent line protocol adapter`: starts one shell process and exchanges one
  newline-terminated request/response per call

Subprocess timings are OS-dependent, so this benchmark is mainly for comparing
relative shape on the same machine while developing adapters.

Measured on May 24, 2026 with:

```sh
odin run benchmarks/adapter_bench.odin -file -o:speed
```

```text
one-shot process adapter
  calls/sample: 50
  samples:      3
  best ns/call: 3187494.16
  avg ns/call:  3310309.72

persistent line protocol adapter
  calls/sample: 50
  samples:      3
  best ns/call: 79288.32
  avg ns/call:  85878.89
```

## Interpreting Results

The current implementation prioritizes correctness and API shape. It allocates
per generated test case for choice/event/label tracking and per-case arenas.
That is acceptable for the first milestone, but it is not the final performance
target.

The first performance goal is not a specific nanosecond number. It is to make
allocation behavior visible and prevent accidental slowdowns while we decide
which APIs should become allocation-free hot paths.

Likely optimization areas:

- reuse `T` and its choice buffers across passing generated tests
- avoid creating a dynamic arena for generated tests that do not allocate values
- make diagnostic/event capture lazy or opt-in for hot passing runs
- separate fast `check` execution from rich failure reporting
- add preallocated runners for stateful command sequence testing

## Current Measurement

Measured on May 24, 2026 with:

```sh
odin run benchmarks/check_bench.odin -file -o:speed
```

```text
two integer draws
  generated tests/sample: 100000
  samples:                5
  best ns/unit:           22.41
  avg ns/unit:            23.47
  alloc calls max:        0
  resize calls max:       0
  free calls max:         0
  bytes req max:          0

array and string draws
  generated tests/sample: 100000
  samples:                5
  best ns/unit:           131.62
  avg ns/unit:            133.76
  alloc calls max:        3
  resize calls max:       1
  free calls max:         3
  bytes req max:          2368

stateful 20-step model
  generated tests/sample: 10000
  samples:                5
  best ns/unit:           146.47
  avg ns/unit:            148.04
  alloc calls max:        0
  resize calls max:       0
  free calls max:         0
  bytes req max:          0

stateful 20-step captured trace
  captured cases/sample:  10000
  samples:                5
  best ns/unit:           5788.40
  avg ns/unit:            5827.31
  alloc calls max:        1230000
  resize calls max:       10000
  free calls max:         1230000
  bytes req max:          43160000

stateful 20-step compact trace
  captured cases/sample:  10000
  samples:                5
  best ns/unit:           299.24
  avg ns/unit:            300.65
  alloc calls max:        10000
  resize calls max:       0
  free calls max:         10000
  bytes req max:          1680000

failing property with shrink
  checks/sample:          1
  samples:                5
  best ns/unit:           2250.00
  avg ns/unit:            2691.80
  alloc calls max:        37
  resize calls max:       0
  free calls max:         37
  bytes req max:          296
```

The integer hot path is now allocation-free for short choice streams because
choices are stored inline in the test context. Coverage aggregation added a
small amount of per-test bookkeeping, but did not add allocations to unlabeled
passing properties. Passing stateful checks are now allocation-free in the
normal benchmark because event traces are captured lazily: normal passing runs
skip events, while failing/replay/shrink runs recapture diagnostics. The
explicit captured-trace benchmark shows the cost of recording every successful
step; the compact trace path shows why `skip_success_events` is useful for long
model runs where only failure/precondition/invariant evidence matters.
Collection generation now reuses a per-check test context and value arena across
passing generated tests. That moves collection allocation from per generated
case to a small fixed cost per `check` run while preserving failure/replay
diagnostics. Shrinking reuses a candidate runner context and can delete chunks
from the choice stream, which helps remove irrelevant sequence choices while
keeping the final replay stream to the choices actually consumed by the failing
case.
