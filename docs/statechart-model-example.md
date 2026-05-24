# Statechart Model Example

`examples/statechart_model` demonstrates the intended relationship between
`pbt` and the sibling `statecharts` library.

The statechart is the executable model. The target is a deliberately buggy door
implementation. A generated event sequence drives both. After each event, the
property compares the target's observed state with the model state.

Build it:

```sh
odin build examples/statechart_model -out:/tmp/pbt-statechart-model
```

Run it:

```sh
/tmp/pbt-statechart-model --property "door statechart" --num-tests 100 --seed 123
```

The example intentionally fails and shrinks to the minimal event that exposes
the bug: `lock` from the initial `Closed` state. The JSON result contains both
the PBT replay data and structured `statechart` events.

Replay the shrunk failure with:

```sh
/tmp/pbt-statechart-model \
  --property "door statechart" \
  --replay-seed 123 \
  --replay-choices 0,2
```

The exact choices may change as generators evolve. Use the `replay.seed` and
`replay.choices_csv` fields from the JSON result.
