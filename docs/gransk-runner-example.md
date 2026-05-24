# Gransk Runner Example

The example in `examples/gransk_runner` shows the intended executable shape for
Gransk integration.

Build it:

```sh
odin build examples/gransk_runner -out:/tmp/pbt-gransk-runner
```

List exposed properties:

```sh
/tmp/pbt-gransk-runner --list-properties
```

Run one property:

```sh
/tmp/pbt-gransk-runner --property "reverse twice" --num-tests 100 --seed 123
```

Run all registered properties:

```sh
/tmp/pbt-gransk-runner --num-tests 100 --seed 123
```

Run the intentionally failing example:

```sh
/tmp/pbt-gransk-runner --property "small numbers" --num-tests 100 --seed 123
```

Replay a shrunk failure using the `replay.seed` and `replay.choices_csv` fields
from the JSON result:

```sh
/tmp/pbt-gransk-runner \
  --property "small numbers" \
  --replay-seed 123 \
  --replay-choices 50
```

The runner prints suite JSON by default and exits with `0` on pass or `1` on
fail/error. Suite JSON includes aggregate counts plus each property result. That
gives Gransk a stable process boundary without requiring every property file to
implement its own CLI.
