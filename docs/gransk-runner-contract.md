# Gransk Runner Contract

A `pbt` runner is a normal executable that Gransk can call with
`gransk spec check --engine odin/pbt --runner <binary>`.

## Discovery

List properties:

```sh
runner --list-properties
```

Output:

```json
{"tool":"pbt","schema_version":1,"properties":[{"name":"property name","description":"...","tags":["http"]}]}
```

List tags:

```sh
runner --list-tags
```

Output:

```json
{"tool":"pbt","schema_version":1,"tags":[{"name":"http","count":1,"properties":["property name"]}]}
```

## Execution

Run all properties:

```sh
runner --num-tests 100 --seed 123
```

Run one property:

```sh
runner --property "property name" --num-tests 100 --seed 123
```

Run by tag:

```sh
runner --tag http --num-tests 100 --seed 123
```

Replay a failure:

```sh
runner --property "property name" --replay-seed 123 --replay-choices 4,0,19
```

Supported runner flags:

- `--json` and `--text`
- `--property` / `-p`
- `--tag` / `-t`
- `--target`
- `--num-tests` / `-n`
- `--seed`
- `--max-size`
- `--max-discards`
- `--max-shrinks`
- `--shrink` / `--no-shrink`
- `--coverage-warning-only`
- `--preserve-shrink-labels`
- `--fail-fast`
- `--replay-seed`
- `--replay-choices`

Exit code `0` means the selected property suite passed. Exit code `1` means a
property failed, errored, or the runner could not satisfy the request.

## Result JSON

Normal execution prints suite JSON by default:

```json
{
  "tool": "pbt",
  "schema_version": 1,
  "kind": "suite",
  "status": "pass",
  "code": "ok",
  "properties": 1,
  "passed": 1,
  "failed": 0,
  "errors": 0,
  "checks": 100,
  "discards": 0,
  "results": []
}
```

On failure, suite JSON promotes the first failing property into top-level
fields so Gransk does not need to scan every nested result:

- `failing_property`
- `failing_code`
- `failing_message`
- `failing_coverage_missing`
- `failing_coverage_missing_label`
- `failing_coverage_observed_percent`
- `failing_coverage_required_percent`
- `failing_notes`
- `failing_events`
- `failing_shrink_attempts`
- `failing_shrink_duration_ns`
- `replay_seed`
- `replay_choices`

Individual property results also include:

- `status`: `pass`, `fail`, `discard`, or `error`
- `code`: stable machine-readable status such as `ok` or `property_failed`
- `seed`
- `num_tests`
- `num_discards`
- `duration_ns`
- `coverage`
- `coverage_missing`
- `coverage_missing_label`
- `coverage_observed_percent`
- `coverage_required_percent`
- `replay`
- `events`
- `notes`
- `failing_test`
- `shrunk_test`

## Target Boundaries

The property decides how to drive the target. Current adapter paths are:

- direct Odin library calls
- CLI argv with `process_run_with_options`
- one-shot stdin protocol with `protocol_stdin_call_with_options`
- one-shot request-file protocol with `protocol_call_with_options`
- persistent line protocol with `line_protocol_call`
- HTTP API calls with `http_request` or `http_post_json`
- stateful model checks with `run_commands`
- statechart-backed models through `pbt_statechart`

External calls should normally set timeouts and output/body caps. This keeps
generated tests bounded and gives Gransk useful failure evidence instead of
hanging processes or unbounded output.
