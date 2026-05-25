# Stateful HTTP Runner

`examples/stateful_http_runner` demonstrates model-based testing against a
real HTTP API boundary.

The runner starts a tiny local todo HTTP service, generates command sequences,
keeps an independent model of expected todo IDs, and checks `GET /todos` after
each generated command.

Build it:

```sh
odin build examples/stateful_http_runner -out:/tmp/pbt-stateful-http-runner
```

Run it directly:

```sh
/tmp/pbt-stateful-http-runner --tag stateful --seed 123 --num-tests 25
```

Run it through Gransk:

```sh
gransk spec check --engine odin/pbt --runner /tmp/pbt-stateful-http-runner --tag stateful --seed 123 --num-tests 25 --format text
```

The example uses these operations:

- `create`: `POST /todos`, expecting `201` and a new ID
- `delete <id>`: `DELETE /todos/<id>`, expecting `204`
- `list`: `GET /todos`, returning the current IDs

The useful pattern is not the tiny todo service. The pattern is:

1. Generate commands from the current model state.
2. Use preconditions to avoid meaningless operations, such as deleting a missing
   ID.
3. Apply one command to the HTTP target.
4. Observe a compact snapshot endpoint after each command.
5. Compare the snapshot to the independent model.

To see the failure/replay flow, enable the intentionally buggy delete mode:

```sh
PBT_TODO_BUG=delete gransk spec check --engine odin/pbt --runner /tmp/pbt-stateful-http-runner --tag stateful --seed 123 --num-tests 20 --format text
```

In that mode, `DELETE /todos/<id>` returns `204` but does not remove the item.
PBT shrinks the failure to a short create/delete sequence:

```text
todo http stateful: fail
message: command=delete 1 expected=[] actual=[1]
replay: --replay-seed 124 --replay-choices 1,0,1
```

Replay the minimized case without another shrink pass:

```sh
PBT_TODO_BUG=delete gransk spec check --engine odin/pbt --runner /tmp/pbt-stateful-http-runner --tag stateful --replay-seed 124 --replay-choices 1,0,1 --no-shrink --format text
```

That reruns only the create/delete/list observations needed to reproduce the
bug, while still keeping the HTTP request/response events in the report.
