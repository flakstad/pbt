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
