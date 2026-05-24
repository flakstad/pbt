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
- size-aware generators now cover the basic QuickCheck/test.check shape:
  `sized`, `resize`, `scale`, `smaller`, and `such_that`.
- `enum_range` covers the common state-machine command enum case.
- `sample` supports quick generator exploration outside a full property.
- `counterexample` and value-printing `equal` give failures more useful context.
- `pair` and `dict` cover common structured inputs without requiring custom
  generators for every small record-like value.
- `unique_array` covers set-style generated data where duplicate values would
  mostly add noise.
- stateful testing has the important Erlang QuickCheck shape: initial state,
  command generation, preconditions, target run, next-state update,
  postcondition, invariant, and command names for traces.

## Useful Missing Features

### Coverage And Classification

QuickCheck has labels/classification/collection and coverage checks. `pbt` now
has the first useful version of this:

- label counts in `Check_Result`
- `cover(t, condition, percent, label)`
- coverage requirement enforcement at the end of a successful check
- JSON coverage summaries for Gransk reports

Useful additions still missing:

- richer human-readable coverage reports
- warning-only coverage mode
- coverage-aware shrinking when a property wants to preserve interesting cases

### Generator Catalog

test.check has a broad generator catalog: scalar types, collections, and
combinators. `pbt` has a useful starter set, but still lacks:

- tuples / records helpers
- richer recursive generator conveniences

### Shrinking

The current shrinker minimizes the choice stream. That gives broad shrinking
without every generator needing a custom shrinker. It is a good foundation, but
not enough long-term.

It now lowers individual choice values and removes chunks from the choice
stream. When a replay candidate consumes fewer choices than it was given, the
shrinker keeps only the consumed choices, producing cleaner replay strings.
`Check_Result` also records shrink attempts and shrink duration.

Useful additions:

- generator-specific shrink hooks for domain types
- better array/string shrinking
- command-aware stateful shrink passes
- preserve interesting coverage during shrinking when requested

### Result And Counterexample Diagnostics

QuickCheck has strong counterexample/reporting ergonomics. `pbt` has events,
notes, labels, messages, JSON, and compact text output, but still needs:

- multiple notes without forcing event semantics
- richer text formatting for long event traces

### Runner Integration

The runner API is already useful for Gransk. `--json` and `--text` output modes
are supported by the shared CLI helpers, discovery includes property metadata,
`--property` supports exact or unique substring matching, and
`check_properties_from_args` can execute every registered property in one
invocation with aggregate suite JSON.

## Performance Notes

The first benchmark harness is in `benchmarks/check_bench.odin`.

The current fast path is promising:

- two integer draws: roughly `40 ns/generated test`
- zero allocations for short choice streams

Known performance work:

- collection generators allocate heavily through per-case arenas
- stateful tests allocate heavily because every command records events
- rich diagnostics should probably be lazy or failure-only in hot passing runs
- result construction should remain cheap for passing tests

The broad strategy should be:

1. Keep the simple generated-test hot path allocation-free.
2. Add richer diagnostics without slowing the hot path.
3. Optimize stateful command traces separately, because they are essential for
   Gransk but expensive if every successful step allocates strings.
