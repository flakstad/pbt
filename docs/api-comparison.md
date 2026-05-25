# API Comparison

This document compares the current `pbt` API with Haskell QuickCheck and
Clojure test.check.

## Good Shape

The current core is in a reasonable place:

- `check` maps well to QuickCheck `quickCheck` and test.check `quick-check`.
- `Result` is better than returning bare `bool` because discards, errors, and
  messages are first-class.
- `draw` is an Odin-friendly primitive for generator consumption.
- seed + choice-stream replay is useful for Gransk and external targets.
- default-on shrinking is the right default.
- JSON output and property discovery make the library usable as a Gransk engine.
- `Check_Result.code` provides stable machine-readable result codes in addition
  to human messages.
- `label`, `classify`, `collect`, and `cover` now aggregate coverage data in
  `Check_Result` and JSON output.
- `require_shrink_label` lets a property pin only the classifications that must
  survive shrinking.
- size-aware generators now cover the basic QuickCheck/test.check shape:
  `sized`, `resize`, `clamp_size`, `scale`, `smaller`, and `such_that`.
- byte and hex generators cover common payload/token cases for HTTP, CLI, and
  protocol testing.
- `identifier_ascii` covers common generated names for fields, flags, commands,
  and fixtures.
- `path_segment_ascii` covers reusable path/key segments without choosing a
  filesystem or URL policy for the caller.
- CLI argument, flag, and command-vector generators cover safe process adapter
  inputs without forcing generated values through shell quoting.
- HTTP method, status-code, and header-name generators cover common adapter
  inputs without requiring a full HTTP request model.
- `http_request_ascii` generates adapter-ready HTTP requests from a caller-owned
  base URL, including path/query data and JSON bodies for body methods.
- `http_request_body_ascii` composes HTTP request generation with a
  caller-provided body generator for schema-shaped request bodies.
- URL path and query component generators cover route and query data while
  keeping base URL and escaping policy explicit in the property.
- JSON string, boolean, integer, simple object, and simple array generators
  cover request-body construction without committing to a full JSON AST model.
- `json_object_fields_ascii` covers schema-shaped JSON bodies where field names
  are fixed by the API and generated values provide the variation.
- `json_object_field_subset_ascii` covers optional/missing-field API cases while
  still keeping the generated body inside a known field set.
- `json_object_schema_ascii` covers simple typed API bodies with per-field
  string, string-enum, integer, boolean, or null values.
- `json_object_schema_subset_ascii` combines missing-field coverage with typed
  schema-shaped JSON values.
- `json_array_of_ascii` composes any JSON body generator into bounded JSON
  arrays for batch API and protocol payloads.
- `enum_range` covers the common state-machine command enum case.
- `sample` supports quick generator exploration outside a full property.
- `counterexample` and value-printing `equal` give failures more useful context.
- `pair`, `triple`, `tuple4`, `tuple5`, `dict`, `map2`, and `map3` cover common
  structured inputs without requiring custom generators for every small
  record-like value.
- `lazy` supports recursive and mutually recursive generator definitions when
  combined with size-aware generators.
- non-empty collection and string helpers cover a frequent precondition without
  forcing `such_that`.
- `unique_array` covers set-style generated data where duplicate values would
  mostly add noise.
- stateful testing has the important Erlang QuickCheck shape: initial state,
  command generation, preconditions, target run, next-state update,
  postcondition, invariant, command names, and state/value details for traces.
- stateful traces can suppress successful-step events when long prefixes would
  obscure the failing step.
- the stateful line-protocol example shows the core cross-language model:
  generated commands, persistent target wrapper, independent model state, and
  per-step observations.
- external target adapters now cover one-shot process calls, one-shot
  request-file protocol calls, persistent line protocol calls, and curl-backed
  HTTP calls.
- process and protocol target calls have basic generated-input guardrails:
  timeouts, process output caps, line-protocol response caps, and
  line-protocol per-call timeouts.
- one-shot process calls can feed generated stdin, which covers CLIs and small
  wrapper programs that read JSON or commands from standard input.
- `protocol_stdin_call_with_options` provides a named one-shot stdin protocol
  path alongside request-file and persistent line protocols.

## Useful Missing Features

### Coverage And Classification

QuickCheck has labels/classification/collection and coverage checks. `pbt` now
has the first useful version of this:

- label counts in `Check_Result`
- `cover(t, condition, percent, label)`
- coverage requirement enforcement at the end of a successful check
- warning-only coverage mode for exploratory runs
- coverage failure messages name the first unmet label and observed percentage
- JSON coverage summaries for Gransk reports
- optional label-preserving shrinking when a smaller counterexample would
  otherwise lose the interesting classification

### Generator Catalog

test.check has a broad generator catalog: scalar types, collections, and
combinators. `pbt` has a useful starter set. The remaining generator work is now
mostly about richer built-in domain generators for structured protocol schemas
rather than basic shape.

### Shrinking

The current shrinker minimizes the choice stream. That gives broad shrinking
without every generator needing a custom shrinker. Custom generators can also
record domain-specific choice-range shrink hints for values that have a simpler
alternate replay encoding.

It now tries domain-specific choice hints, built-in length hints for removing
array/string ranges while preserving retained element choices, and marked
command-boundary ranges for stateful properties, reducing the generated
command-sequence length when a whole command is removed. JSON field-subset
generators also record hints that remove optional fields while preserving
retained value choices. It also removes chunks from the choice stream, tries
zeroed suffixes for simpler array/string/payload contents, and lowers individual
choice values. When a replay candidate consumes fewer choices than it was given,
the shrinker keeps only the consumed choices, producing cleaner replay strings.
`Check_Result` also records shrink attempts and shrink duration.

Useful additions:

- deeper structure-aware collection shrinking
- coverage-goal guided generation or shrinking

### Result And Counterexample Diagnostics

QuickCheck has strong counterexample/reporting ergonomics. `pbt` has first-class
notes, events, labels, messages, JSON, and compact text output with capped event
traces.

### Runner Integration

The runner API is already useful for Gransk. `--json` and `--text` output modes
are supported by the shared CLI helpers, discovery includes property metadata,
`--property` supports exact or unique substring matching, and
`check_properties_from_args` can execute every registered property in one
invocation with aggregate suite JSON.

## Performance Notes

The benchmark harnesses are in `benchmarks/check_bench.odin` and
`benchmarks/adapter_bench.odin`.

The current fast path is promising:

- two integer draws: roughly `22 ns/generated test`
- zero allocations for short choice streams
- collection generation reuses per-check storage for passing cases
- normal passing stateful checks avoid event allocation unless diagnostics are
  captured
- compact stateful traces are available when rich successful-step traces would
  add noise or cost

Known performance work:

- captured rich stateful traces still allocate heavily because each step stores
  human-readable event strings
- one-shot process adapters are orders of magnitude slower than the persistent
  line protocol path and should be reserved for simple targets
- guarded process execution adds some overhead versus bare `os.process_exec`,
  but gives bounded output and timeout behavior for generated inputs
- result construction should remain cheap for passing tests

The broad strategy should be:

1. Keep the simple generated-test hot path allocation-free.
2. Add richer diagnostics without slowing the hot path.
3. Optimize stateful command traces separately, because they are essential for
   Gransk but expensive if every successful step allocates strings.
