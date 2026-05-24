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
- `failing property with shrink`: a failing property that shrinks an integer
  boundary case

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
  best ns/unit:           25.24
  avg ns/unit:            25.71
  alloc calls max:        0
  resize calls max:       0
  free calls max:         0
  bytes req max:          0

array and string draws
  generated tests/sample: 100000
  samples:                5
  best ns/unit:           132.26
  avg ns/unit:            133.23
  alloc calls max:        3
  resize calls max:       1
  free calls max:         3
  bytes req max:          2368

stateful 20-step model
  generated tests/sample: 10000
  samples:                5
  best ns/unit:           187.02
  avg ns/unit:            192.76
  alloc calls max:        0
  resize calls max:       0
  free calls max:         0
  bytes req max:          0

failing property with shrink
  checks/sample:          1
  samples:                5
  best ns/unit:           1834.00
  avg ns/unit:            3233.80
  alloc calls max:        37
  resize calls max:       0
  free calls max:         37
  bytes req max:          296
```

The integer hot path is now allocation-free for short choice streams because
choices are stored inline in the test context. Coverage aggregation added a
small amount of per-test bookkeeping, but did not add allocations to unlabeled
passing properties. Passing stateful checks are now also allocation-free in this
benchmark because event traces are captured lazily: normal passing runs skip
events, while failing/replay/shrink runs recapture diagnostics. Collection
generation now reuses a per-check test context and value arena across passing
generated tests. That moves collection allocation from per generated case to a
small fixed cost per `check` run while preserving failure/replay diagnostics.
Shrinking reuses a candidate runner context and can delete chunks from the
choice stream, which helps remove irrelevant sequence choices while keeping the
final replay stream to the choices actually consumed by the failing case.
