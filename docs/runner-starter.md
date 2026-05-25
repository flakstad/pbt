# Runner Starter

`examples/runner_starter` is the smallest copyable Gransk-facing runner shape.
It is intentionally self-contained:

- a pure property for direct Odin/library checks
- a persistent line-protocol property for external wrappers
- property names, descriptions, and tags for Gransk discovery
- default JSON suite output and replay-compatible CLI flags through `run_cli`

Build it:

```sh
odin build examples/runner_starter -out:/tmp/pbt-runner-starter
```

List properties and tags:

```sh
/tmp/pbt-runner-starter --list-properties --pretty
/tmp/pbt-runner-starter --list-tags --pretty
```

Run it directly:

```sh
/tmp/pbt-runner-starter --tag starter --seed 123 --num-tests 100
```

Run it through Gransk:

```sh
gransk spec check --engine odin/pbt --runner /tmp/pbt-runner-starter --tag starter --seed 123 --num-tests 100 --format text
```

Use it as a starting point:

1. Replace `reverse_twice_property` with a direct property for your Odin
   library or small pure function.
2. Replace the shell command in `line_protocol_echo_property` with a wrapper
   around your target library or service boundary.
3. Keep one generated request per line and one observation per line for fast
   cross-language checks.
4. Add tags that match how you want Gransk to slice the runner, such as
   `unit`, `http`, `cli`, `stateful`, `slow`, or a domain name.
5. Keep timeouts and response caps on external calls so generated cases fail
   cleanly instead of hanging.

For HTTP APIs, copy the shape from `examples/http_target_runner`. For stateful
external targets, copy `examples/stateful_line_protocol_runner`.
