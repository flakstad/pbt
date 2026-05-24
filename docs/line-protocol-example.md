# Line Protocol Example

`examples/line_protocol_runner` demonstrates the persistent subprocess adapter
for external targets.

The example starts a long-running shell process, sends generated integers as
newline-terminated requests, reads one newline-terminated response per request,
and checks that the target doubles each integer correctly.

Build it:

```sh
odin build examples/line_protocol_runner -out:/tmp/pbt-line-protocol-runner
```

Run it:

```sh
/tmp/pbt-line-protocol-runner --property "line protocol doubles integers" --num-tests 100 --seed 123
```

This is the same shape a Go, Python, JavaScript/TypeScript, Clojure, or Odin
wrapper can use: keep the target process alive, send one request line, read one
response line, and return normal `pbt.Result` values from the property.
