# Stateful Line Protocol Example

`examples/stateful_line_protocol_runner` demonstrates the main pattern for
testing a stateful external target through a persistent wrapper process.

The example starts a small line-protocol counter target, generates command
sequences, keeps an independent model state in the PBT runner, sends each
command to the target, and checks the observed counter value after every step.

Build it:

```sh
odin build examples/stateful_line_protocol_runner -out:/tmp/pbt-stateful-line-protocol-runner
```

Run it directly:

```sh
/tmp/pbt-stateful-line-protocol-runner --tag stateful --num-tests 100 --seed 123
```

Run it through Gransk:

```sh
gransk spec check --engine odin/pbt --runner /tmp/pbt-stateful-line-protocol-runner --tag stateful --seed 123 --num-tests 100
```

To see the failure and replay flow, enable the intentionally buggy target mode:

```sh
PBT_COUNTER_BUG=reset /tmp/pbt-stateful-line-protocol-runner --tag stateful --num-tests 100 --seed 123
```

In that mode, the wrapper incorrectly changes `reset` to `1` instead of `0`.
The model stays independent from the target and expects `reset` to produce `0`,
so PBT reports a shrunk stateful counterexample with the failing command,
target observation, model state, and replay choices.

Through Gransk, the same failure is easier to read:

```sh
PBT_COUNTER_BUG=reset gransk spec check --engine odin/pbt --runner /tmp/pbt-stateful-line-protocol-runner --tag stateful --seed 123 --num-tests 20 --format text
```

The shrunk failure is one command:

```text
line protocol counter stateful: fail
message: command=reset expected=0 actual=1
replay: --replay-seed 123 --replay-choices 0,2
events:
  1. protocol line [ok]: duration_ns=... timeout_ms=500 max_response_bytes=1024
  2. stateful step 0 reset postcondition [fail]: state=count=0 value=actual=1 message=command=reset expected=0 actual=1
```

Replay just that case:

```sh
PBT_COUNTER_BUG=reset gransk spec check --engine odin/pbt --runner /tmp/pbt-stateful-line-protocol-runner --tag stateful --replay-seed 123 --replay-choices 0,2 --no-shrink --format text
```

This is the shape to use for libraries in other languages:

1. Write a small target wrapper in Go, Python, JavaScript/TypeScript, Clojure,
   Odin, shell, or another convenient language.
2. Keep that wrapper process alive for the whole property.
3. Send one generated command per line.
4. Return one observation per line.
5. Keep the simplified model inside the PBT runner and compare each observation
   against the model.

Use `line_protocol_call_with_options` to set per-call timeouts and response
size caps. On timeout, the PBT adapter stops the client because a late response
could otherwise be consumed as the answer to a later command.
