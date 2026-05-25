# External Target Examples

`examples/external_targets` demonstrates two Gransk-relevant target shapes:

- a normal CLI target driven through generated argv
- a one-shot protocol target that reads one generated JSON request on stdin

Build it:

```sh
odin build examples/external_targets -out:/tmp/pbt-external-targets
```

List properties:

```sh
/tmp/pbt-external-targets --list-properties
```

Run both examples:

```sh
/tmp/pbt-external-targets --num-tests 100 --seed 123
```

Run only the CLI example:

```sh
/tmp/pbt-external-targets --tag cli --num-tests 100 --seed 123 --text
```

Run only the stdin protocol example:

```sh
/tmp/pbt-external-targets --tag stdin --num-tests 100 --seed 123 --text
```

The sample targets are deliberately tiny shell commands so the example is
self-contained. In real Gransk use, replace those commands with a compiled Go,
Odin, Python, JavaScript/TypeScript, Clojure, or shell wrapper around the system
under test.

The important boundary is stable and language-neutral:

- generated argv values go to `process_run_with_options`
- generated JSON requests go to `protocol_stdin_call_with_options`
- timeouts and output caps are set on every external call
- failures include process events in the returned PBT result JSON

For long-running wrappers, prefer the persistent line protocol shown in
`examples/line_protocol_runner`.
