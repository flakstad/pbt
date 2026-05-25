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
- `cli command data`: a passing property drawing a process command vector and
  CLI flag
- `protocol request data`: a passing property drawing an adapter-ready HTTP
  request plus simple JSON array, known-field object, and field-subset object
  bodies, typed schema object/subset bodies with enum fields, a typed
  schema-object array, and a body-aware HTTP request
- `stateful 20-step model`: a passing stateful model with a fixed 20-command
  sequence
- `stateful 20-step captured trace`: the same model run with explicit event
  capture, measuring rich successful-step trace cost
- `stateful 20-step command trace`: the same captured run with
  `compact_success_events`, recording stable command names without rich
  per-step detail
- `stateful 20-step compact trace`: the same captured run with
  `skip_success_events`, measuring the compact trace path
- `failing property with shrink`: a failing property that shrinks an integer
  boundary case
- `payload failure with shrink`: a failing property that draws fixed array and
  string payload data before shrinking an independent failure marker
- `sample array values`: generator sampling of fixed-size arrays, measuring the
  quick exploration path rather than full `check` execution

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
  best ns/call: 3592839.16
  avg ns/call:  3737505.55

persistent line protocol adapter
  calls/sample: 50
  samples:      3
  best ns/call: 80830.84
  avg ns/call:  83099.72
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
- keep copied failure and trace evidence compact; copied `Test_Case` events now
  pool dynamic event strings in one per-case buffer
- add preallocated runners for stateful command sequence testing

## Current Measurement

Measured on May 25, 2026 with:

```sh
odin run benchmarks/check_bench.odin -file -o:speed
```

```text
two integer draws
  generated tests/sample: 100000
  samples:                5
  best ns/unit:           33.26
  avg ns/unit:            33.45
  alloc calls max:        0
  resize calls max:       0
  free calls max:         0
  bytes req max:          0

array and string draws
  generated tests/sample: 100000
  samples:                5
  best ns/unit:           144.38
  avg ns/unit:            147.18
  alloc calls max:        3
  resize calls max:       1
  free calls max:         3
  bytes req max:          2368

cli command data
  generated tests/sample: 100000
  samples:                5
  best ns/unit:           388.63
  avg ns/unit:            396.75
  alloc calls max:        3
  resize calls max:       3
  free calls max:         3
  bytes req max:          3776

protocol request data
  generated tests/sample: 100000
  samples:                5
  best ns/unit:           5072.45
  avg ns/unit:            5082.97
  alloc calls max:        6
  resize calls max:       5
  free calls max:         6
  bytes req max:          13952

stateful 20-step model
  generated tests/sample: 10000
  samples:                5
  best ns/unit:           161.58
  avg ns/unit:            162.69
  alloc calls max:        0
  resize calls max:       0
  free calls max:         0
  bytes req max:          0

stateful 20-step captured trace
  captured cases/sample:  10000
  samples:                5
  best ns/unit:           3476.58
  avg ns/unit:            3550.85
  alloc calls max:        30000
  resize calls max:       0
  free calls max:         30000
  bytes req max:          18100000

stateful 20-step command trace
  captured cases/sample:  10000
  samples:                5
  best ns/unit:           683.62
  avg ns/unit:            687.84
  alloc calls max:        20000
  resize calls max:       0
  free calls max:         20000
  bytes req max:          16000000

stateful 20-step compact trace
  captured cases/sample:  10000
  samples:                5
  best ns/unit:           339.73
  avg ns/unit:            341.28
  alloc calls max:        10000
  resize calls max:       0
  free calls max:         10000
  bytes req max:          1600000

failing property with shrink
  checks/sample:          1
  samples:                5
  best ns/unit:           3041.00
  avg ns/unit:            3699.80
  alloc calls max:        37
  resize calls max:       0
  free calls max:         37
  bytes req max:          296

payload failure with shrink
  checks/sample:          1
  samples:                5
  best ns/unit:           15375.00
  avg ns/unit:            17958.20
  alloc calls max:        124
  resize calls max:       0
  free calls max:         124
  bytes req max:          14032

sample array values
  samples/run:            10000
  samples:                5
  best ns/unit:           45.33
  avg ns/unit:            47.59
  alloc calls max:        316
  resize calls max:       10
  free calls max:         316
  bytes req max:          816384
```

The integer hot path is now allocation-free for short choice streams because
choices are stored inline in the test context. Coverage aggregation added a
small amount of per-test bookkeeping, but did not add allocations to unlabeled
passing properties. Passing stateful checks are now allocation-free in the
normal benchmark because event traces are captured lazily: normal passing runs
skip events, while failing/replay/shrink runs recapture diagnostics. The
explicit captured-trace benchmark shows the cost of recording every successful
step. Stateful event records avoid cloning repeated static kind/status strings,
store per-run dynamic event strings in the case arena, and copy those strings
only when materializing the captured `Test_Case`. That cuts rich trace allocation
calls while preserving owned diagnostics in the returned result. Stateful runs
preallocate event storage when the generated sequence length is known, avoiding
dynamic-array resize churn. The command trace path shows the cheaper full
sequence when stable command names are enough; the compact trace path shows why
`skip_success_events` is useful for long model runs where only
failure/precondition/invariant evidence matters.
Collection generation now reuses a per-check test context and value arena across
passing generated tests. That moves collection allocation from per generated
case to a small fixed cost per `check` run while preserving failure/replay
diagnostics. Shrinking reuses a candidate runner context and can delete chunks
from the choice stream, which helps remove irrelevant sequence choices while
keeping the final replay stream to the choices actually consumed by the failing
case. Deterministic choices are no longer recorded, which keeps fixed-size
generators replay-aligned and substantially reduces shrink work for payloads
that include fixed-size arrays or strings. Domain-specific choice-range shrink
hints and built-in array/string range-removal hints are captured only for
failing/shrinking runs, so normal passing checks keep the same zero-allocation
behavior.
Generator sampling clears replay-choice tracking between produced values while
keeping the value arena alive, so sampled slices/strings remain valid without
letting unused replay metadata grow with sample count.
