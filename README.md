# pbt

Property-based testing for Odin.

The library is intended to be usable directly from Odin tests and as a Gransk
engine for testing libraries, command-line programs, HTTP services, and
stateful systems.

Current status: public API design draft. See [docs/public-api.md](docs/public-api.md).

## First Slice

The current implementation includes:

- `check` with deterministic seeds
- `draw` from generators
- `Result` values with pass/fail/discard/error
- integer, unsigned integer, boolean, array, optional, ASCII string, and fixed
  alphabet string generators
- fixed value, element, enum range, float range, size-aware, resized, scaled,
  and filtered generators
- pair, dictionary, and unique array generators for structured values
- generator combinators: `map_gen`, `bind`, `one_of`, and `frequency`
- strict replay from seed and choices
- default-on choice-stream shrinking
- per-test arena allocation for generated values
- `sample` for quick generator exploration
- stateful model runner for command-sequence properties
- one-shot process adapter for CLI-style targets
- request-file protocol adapter for wrapping non-Odin libraries in small target
  processes
- curl-backed HTTP adapter for external APIs and services
- diagnostic helpers: `note`, `label`, `classify`, `collect`, and `cover`
- coverage/classification aggregation in `Check_Result` and JSON output
- richer failure context with `counterexample` and value-printing `equal`
- structured event capture for HTTP/process/statechart adapters
- JSON result output for Gransk
- runner helpers: `print_check_result_json`, `check_result_exit_code`, and
  `exit_with_check_result`
- runner option parsing with `parse_check_options`
- replay parsing with `parse_replay`
- replay choice CSV formatting for CLI reruns
- `check_from_args` for normal runs and replay runs from one CLI path
- `Property_Case` and `check_property_from_args` for multi-property runners
- `properties_json` and `--list-properties` detection for runner discovery

Run the tests with:

```sh
odin test pbt
```

See [docs/gransk-runner-example.md](docs/gransk-runner-example.md) for a
minimal Gransk-facing runner executable.

See [docs/statechart-model-example.md](docs/statechart-model-example.md) for a
statechart-backed stateful model example.

See [BENCHMARKS.md](BENCHMARKS.md) for performance measurement commands and
current benchmark coverage.

See [docs/api-comparison.md](docs/api-comparison.md) for the current comparison
against QuickCheck and test.check.
