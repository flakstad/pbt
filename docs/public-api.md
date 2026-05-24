# Public API Draft

`pbt` is an Odin property-based testing library and engine. The core package
should stay small: generation, shrinking, replay, checking, and structured
results. Targets such as HTTP services, command-line programs, libraries, and
statecharts should live in adapters.

The library must be useful in two modes:

1. Native Odin mode, where a property calls Odin code directly.
2. External target mode, where a property drives an HTTP API, CLI, long-running
   subprocess, or a small adapter program wrapping a library written in another
   language.

Odin is the implementation language for this library, not a restriction on what
systems it can test.

## API Influences

- Haskell QuickCheck: `quickCheck`, `Property`, `Gen`, `Arbitrary`, `forAll`,
  `choose`, `oneof`, `frequency`, size-aware generators, shrinking, labels, and
  counterexamples.
- Erlang QuickCheck: state-machine testing with `initial_state`, `command`,
  `precondition`, `next_state`, `postcondition`, `invariant`, `commands`, and
  `run_commands`.
- Clojure test.check: `quick-check`, `for-all`, explicit generators, seed
  replay, shrunk failing values, and result maps.

## Core Package

The package name should be simply:

```odin
package pbt
```

The basic user flow should read like this:

```odin
package cart_test

import pbt "pbt"

cart_total_is_stable :: proc(t: ^pbt.T) -> pbt.Result {
    qty := pbt.draw(t, pbt.int_range(0, 100))
    price := pbt.draw(t, pbt.int_range(0, 10_000))

    expected := qty * price
    actual := cart_total(qty, price)

    return pbt.equal(actual, expected)
}

@(test)
test_cart_total :: proc(t: ^testing.T) {
    result := pbt.check("cart total is stable", cart_total_is_stable, {
        num_tests = 1_000,
        seed = 123,
    })

    pbt.require_pass(t, result)
}
```

## Naming

Prefer short obvious names at the top level:

- `check`
- `draw`
- `Gen`
- `T`
- `Result`
- `Check_Options`
- `Check_Result`
- `Status`
- `Replay`

Avoid copying names that are awkward in Odin. For example, use `int_range`
instead of `choose` if it is clearer at call sites.

`draw` is the primitive operation for consuming one value from a generator inside
a property. It is intentionally lower-level than QuickCheck/test.check-style
`forAll`/`for-all`: the property runner is already executing a universally
quantified check, while `draw` records the choices needed for replay and
shrinking.

## Core Types

```odin
Status :: enum {
    Pass,
    Fail,
    Discard,
    Error,
}

Result :: struct {
    status: Status,
    message: string,
}

Property :: proc(t: ^T) -> Result

Check_Options :: struct {
    num_tests: int,
    max_discards: int,
    seed: u64,
    max_size: int,
    shrink: bool,
    no_shrink: bool,
    max_shrinks: int,
    coverage_warning_only: bool,
    preserve_shrink_labels: bool,
}

Check_Result :: struct {
    name: string,
    status: Status,
    code: string,
    seed: u64,
    num_tests: int,
    num_discards: int,
    duration_ns: i64,
    shrink_attempts: int,
    shrink_duration_ns: i64,
    coverage: []Coverage_Label,
    failing_test: Maybe(Test_Case),
    shrunk_test: Maybe(Test_Case),
    replay: Replay,
    message: string,
}
```

`T` is the per-test context. It owns or references the RNG, allocator, current
size, choice stream, replay prefix, labels, notes, and cleanup hooks.
Generated slices and strings should be allocated in a per-case arena owned by
`T`, so properties do not need to manually free ordinary generated values.

## Result Helpers

```odin
pass :: proc() -> Result
fail :: proc(message: string) -> Result
discard :: proc(message := "") -> Result
error :: proc(message: string) -> Result

assert :: proc(ok: bool, message := "") -> Result
equal :: proc(actual, expected: $T) -> Result
counterexample :: proc(message: string, result: Result) -> Result
```

The property function should return `Result`, not `bool`. That makes discards,
errors, messages, and adapter failures first-class from day one.

`counterexample` adds contextual text to a non-passing result. `equal` includes
the expected and actual values in the failure message.

## Generators

The first implementation uses an explicit generator input type:

```odin
Gen :: struct(Input: typeid, Value: typeid) {
    input: Input,
    produce: proc(t: ^T, input: Input) -> Value,
}

draw :: proc(t: ^T, gen: Gen($Input, $Value)) -> Value
```

This is straightforward in Odin and keeps generator state visible. The tradeoff
is that combinators such as `one_of` and `frequency` currently require their
child generators to have the same input type. We may later introduce a
type-erased generator wrapper if heterogeneous generator composition becomes
important enough to justify the extra allocation/lifetime complexity.

Initial generator set:

```odin
constant :: proc(value: Value) -> Gen(Constant_Input(Value), Value)
boolean :: proc() -> Gen(Bool_Input, bool)
int_range :: proc(min, max: int) -> Gen(Int_Range_Input, int)
u64_range :: proc(min, max: u64) -> Gen(U64_Range_Input, u64)
byte_range :: proc(min := 0, max := 255) -> Gen(Byte_Range_Input, byte)
f64_range :: proc(min, max: f64) -> Gen(F64_Range_Input, f64)
elements :: proc(values: []Value) -> Gen(Elements_Input(Value), Value)
enum_range :: proc(min, max: Value) -> Gen(Enum_Range_Input(Value), Value)
one_of :: proc(gens: []Gen($Input, $Value)) -> Gen(One_Of_Input(Input, Value), Value)
frequency :: proc(weighted: []Weighted_Gen($Input, $Value)) -> Gen(Frequency_Input(Input, Value), Value)
array :: proc(elem: Gen($Input, $Value), min_len := 0, max_len := -1) -> Gen(Array_Input(Input, Value), []Value)
non_empty_array :: proc(elem: Gen($Input, $Value), max_len := -1) -> Gen(Array_Input(Input, Value), []Value)
byte_array :: proc(min_len := 0, max_len := -1, min := 0, max := 255) -> Gen(Byte_Array_Input, []byte)
non_empty_byte_array :: proc(max_len := -1, min := 0, max := 255) -> Gen(Byte_Array_Input, []byte)
unique_array :: proc(elem: Gen($Input, $Value), min_len := 0, max_len := -1) -> Gen(Array_Input(Input, Value), []Value)
string_ascii :: proc(min_len := 0, max_len := -1) -> Gen(String_ASCII_Input, string)
non_empty_string_ascii :: proc(max_len := -1) -> Gen(String_ASCII_Input, string)
string_alphabet :: proc(alphabet: string, min_len := 0, max_len := -1) -> Gen(String_Alphabet_Input, string)
non_empty_string_alphabet :: proc(alphabet: string, max_len := -1) -> Gen(String_Alphabet_Input, string)
hex_string :: proc(min_bytes := 0, max_bytes := -1, uppercase := false) -> Gen(Hex_String_Input, string)
non_empty_hex_string :: proc(max_bytes := -1, uppercase := false) -> Gen(Hex_String_Input, string)
identifier_ascii :: proc(min_len := 1, max_len := -1) -> Gen(Identifier_ASCII_Input, string)
path_segment_ascii :: proc(min_len := 1, max_len := -1) -> Gen(Path_Segment_ASCII_Input, string)
http_method :: proc() -> Gen(HTTP_Method_Input, string)
http_status_code :: proc(min := 100, max := 599) -> Gen(HTTP_Status_Code_Input, int)
http_header_name_ascii :: proc(min_len := 1, max_len := -1) -> Gen(HTTP_Header_Name_ASCII_Input, string)
url_path_ascii :: proc(min_segments := 1, max_segments := -1, min_segment_len := 1, max_segment_len := -1) -> Gen(URL_Path_ASCII_Input, string)
query_component_ascii :: proc(min_len := 0, max_len := -1) -> Gen(Query_Component_ASCII_Input, string)
non_empty_query_component_ascii :: proc(max_len := -1) -> Gen(Query_Component_ASCII_Input, string)
optional :: proc(elem: Gen($Input, $Value)) -> Gen(Optional_Input(Input, Value), Optional(Value))
pair :: proc(first: Gen($First_Input, $First), second: Gen($Second_Input, $Second)) -> Gen(Pair_Input(First_Input, First, Second_Input, Second), Pair(First, Second))
triple :: proc(first: Gen($First_Input, $First), second: Gen($Second_Input, $Second), third: Gen($Third_Input, $Third)) -> Gen(Triple_Input(...), Triple(First, Second, Third))
tuple4 :: proc(first: Gen($First_Input, $First), second: Gen($Second_Input, $Second), third: Gen($Third_Input, $Third), fourth: Gen($Fourth_Input, $Fourth)) -> Gen(Tuple4_Input(...), Tuple4(First, Second, Third, Fourth))
tuple5 :: proc(first: Gen($First_Input, $First), second: Gen($Second_Input, $Second), third: Gen($Third_Input, $Third), fourth: Gen($Fourth_Input, $Fourth), fifth: Gen($Fifth_Input, $Fifth)) -> Gen(Tuple5_Input(...), Tuple5(First, Second, Third, Fourth, Fifth))
dict :: proc(key: Gen($Key_Input, $Key), value: Gen($Value_Input, $Value), min_len := 0, max_len := -1) -> Gen(Dict_Input(Key_Input, Key, Value_Input, Value), map[Key]Value)
map_gen :: proc(gen: Gen($Input, $Value), f: proc(Value) -> Mapped) -> Gen(Map_Input(Input, Value, Mapped), Mapped)
map2 :: proc(first: Gen($First_Input, $First), second: Gen($Second_Input, $Second), f: proc(First, Second) -> Mapped) -> Gen(Map2_Input(...), Mapped)
map3 :: proc(first: Gen($First_Input, $First), second: Gen($Second_Input, $Second), third: Gen($Third_Input, $Third), f: proc(First, Second, Third) -> Mapped) -> Gen(Map3_Input(...), Mapped)
bind :: proc(gen: Gen($Input, $Value), f: proc(Value) -> Gen(Next_Input, Next)) -> Gen(Bind_Input(Input, Value, Next_Input, Next), Next)
lazy :: proc(f: proc() -> Gen($Input, $Value)) -> Gen(Lazy_Input(Input, Value), Value)
sized :: proc(f: proc(size: int) -> Gen($Input, $Value)) -> Gen(Sized_Input(Input, Value), Value)
resize :: proc(gen: Gen($Input, $Value), size: int) -> Gen(Resize_Input(Input, Value), Value)
clamp_size :: proc(gen: Gen($Input, $Value), min_size, max_size: int) -> Gen(Clamp_Size_Input(Input, Value), Value)
scale :: proc(gen: Gen($Input, $Value), f: proc(size: int) -> int) -> Gen(Scale_Input(Input, Value), Value)
smaller :: proc(gen: Gen($Input, $Value)) -> Gen(Scale_Input(Input, Value), Value)
such_that :: proc(gen: Gen($Input, $Value), predicate: proc(Value) -> bool, max_tries := 100) -> Gen(Such_That_Input(Input, Value), Value)
```

Use a size parameter internally. Collection generators should default to size
bounded behavior, with explicit min/max overrides.

Generators can be explored without a full property by sampling:

```odin
samples := pbt.sample(pbt.string_alphabet("abc", 1, 8), {count = 10, seed = 123})
defer pbt.destroy_sample_result(&samples)

for value in samples.values {
    fmt.println(value)
}
```

Generated strings and slices in a sample result live until
`destroy_sample_result` is called.

`lazy` defers generator construction until draw time. It is useful for recursive
or mutually recursive generator definitions where a branch needs to call back
into the generator being defined; combine it with `sized`, `resize`,
`clamp_size`, or `scale` so recursive values shrink toward a base case as size
decreases.

Likely next generator work:

- richer built-in domain generators for structured protocol data

## Shrinking And Replay

The first implementation should shrink the choice stream, not require every
generator to provide a manual shrinker. That makes the library easier to use and
works well for stateful command sequences.

```odin
Replay :: struct {
    seed: u64,
    choices: []Choice,
}

check_replay :: proc(name: string, property: Property, replay: Replay) -> Check_Result
```

Custom generators can add domain-aware shrink hints when one generated value has
a simpler replay encoding than the generic choice shrinker can infer:

```odin
start := pbt.choice_cursor(t)
// draw one or more choices
replacement := [?]u64{0, simpler_choice}
pbt.record_choice_shrink_hint(t, start, pbt.choice_cursor(t) - start, replacement[:])
```

Hints are low-level by design: they replace a range of replay choices with
another range of replay choices. The shrinker only keeps a hint candidate when
replaying it still fails, so incorrect or over-eager hints cannot create false
counterexamples.

The current choice-stream shrinker removes unused choices, tries domain-specific
choice-range hints, uses built-in length hints to remove array/string ranges
while preserving retained element choices, tries marked command-boundary ranges
for stateful properties, reduces the generated command sequence length when
removing a whole stateful command, removes contiguous choice chunks, tries
zeroed suffixes to simplify generated payload contents, and then lowers
individual choice values.

Deterministic choices, such as a fixed-size generator whose bound has only one
possible value, are not recorded in the replay stream. This keeps replay choices
aligned with the decisions that can actually vary.

Set `preserve_shrink_labels` or pass `--preserve-shrink-labels` when the
shrinker should reject candidates that lose labels from the original failing
case. This is useful when labels/classification identify the interesting
subclass of failures and a smaller unlabeled counterexample would be less useful.
Use `require_shrink_label` inside a property when only specific labels should be
pinned during shrinking; unlike `preserve_shrink_labels`, incidental labels from
the original failure may still disappear.

## Diagnostics

Properties need low-friction ways to add useful failure context:

```odin
note :: proc(t: ^T, message: string)
label :: proc(t: ^T, name: string)
require_shrink_label :: proc(t: ^T, name: string)
classify :: proc(t: ^T, condition: bool, name: string)
collect :: proc(t: ^T, value: string)
cover :: proc(t: ^T, condition: bool, required_percent: f64, name: string)
counterexample :: proc(message: string) -> Result
record_event :: proc(t: ^T, kind, name, status, detail: string)
```

For Gransk, `Check_Result` should be serializable to JSON without scraping text
output.

`label`, `classify`, and `collect` aggregate coverage data across successful
generated tests. `require_shrink_label` also records a label, and tells the
shrinker to keep that classification when minimizing a failure. `cover`
additionally records a minimum required percentage; a completed check reports
`Error` with `coverage_not_met` and a message naming the first missed label and
observed percentage. Coverage summaries are included in JSON so Gransk can show
distribution and unmet requirement details.
Set `coverage_warning_only` or pass `--coverage-warning-only` when a run should
report weak coverage without failing.

`note` records explanatory text separately from adapter/state-machine events.
That keeps human context visible without making notes look like target actions
or protocol events.

Runner helpers should make it easy for a project-specific executable to act as a
Gransk engine:

```odin
options := pbt.parse_check_options(os.args[1:])
result := pbt.check("cart property", cart_property, options)
pbt.exit_with_check_result(result)
```

Or use the convenience path that automatically switches to replay when replay
flags are present:

```odin
result := pbt.check_from_args("cart property", cart_property, os.args[1:])
pbt.exit_with_check_result(result)
```

Multi-property runners should expose named properties:

```odin
tags := [?]string{"stateful", "cart"}
properties := [?]pbt.Property_Case{
    {name = "cart total", property = cart_total_property, description = "total is stable"},
    {name = "cart stateful", property = cart_stateful_property, description = "cart command model", tags = tags[:]},
}
result := pbt.check_property_from_args(properties[:], os.args[1:])
pbt.exit_with_check_result(result)
```

Runners that should execute every registered property by default can use the
CLI helper:

```odin
pbt.run_cli(properties[:], os.args[1:], {shrink = true})
```

With no `--property`, this runs all registered properties and emits a suite
JSON object containing `properties`, `passed`, `failed`, `errors`, `checks`,
`discards`, `duration_ns`, and per-property `results`. With `--property`, it
runs the exact or unique substring match and still emits the same suite shape.
Replay flags require `--property` when more than one property is registered.
Use `--tag <tag>` to run only properties whose registered tags contain that
exact tag, for example `--tag stateful` or `--tag http`.
Use `--fail-fast` to stop a suite run after the first failing or errored
property.

`run_cli` also handles `--list-properties`, `--list-tags`, JSON/text output,
exit codes, and suite result cleanup. Lower-level runners can still call
`check_properties_from_args` directly when they need to own process exit or
embed the suite result in another protocol.

Discovery can be handled by checking `pbt.has_list_properties_flag(os.args[1:])`
and printing `pbt.properties_json(properties[:])`.
Discovery JSON includes property names, descriptions, and tags. `--property`
first matches an exact property name, then falls back to a unique substring
match. Ambiguous or missing matches return stable error codes.

Tag discovery can be handled with `pbt.has_list_tags_flag(os.args[1:])` and
`pbt.tags_json(properties[:])`. Tag JSON lists unique tag names and the number
of properties carrying each tag, plus the property names for each tag.

JSON is the default machine-readable output. Human-oriented runner output can
use:

```odin
pbt.print_check_result(result, pbt.use_json_output(os.args[1:]))
```

where `--text` selects compact text output and `--json` selects JSON.

Supported runner options:

- `--num-tests` / `-n`
- `--property` / `-p`
- `--tag` / `-t`
- `--list-properties`
- `--list-tags`
- `--fail-fast`
- `--json`
- `--text`
- `--help` / `-h`
- `--seed`
- `--max-size`
- `--max-discards`
- `--max-shrinks`
- `--shrink`
- `--no-shrink`, equivalent to `no_shrink = true`
- `--coverage-warning-only`
- `--preserve-shrink-labels`
- `--replay-seed`
- `--replay-choices` as a comma-separated choice stream

## Adapter Shape

The core package should not know about HTTP, subprocesses, or statecharts. Those
should be adapters that return normal `Result` values and attach structured
events to the current test context.

Possible packages:

```text
pbt
pbt/http
pbt/process
pbt/statechart
```

If Odin package layout makes nested paths awkward, use sibling package names:

```text
pbt
pbt_http
pbt_process
pbt_statechart
```

## Target Adapters

### Library Target

Direct Odin calls need no adapter. A property can call the library under test
directly.

Libraries in other languages should be tested through a boundary adapter:

- a CLI wrapper that accepts commands or JSON on stdin
- an HTTP test harness around the library
- a long-running subprocess using line-delimited JSON or another simple protocol
- a language-specific runner that speaks a stable Gransk/PBT protocol

The important constraint is that the PBT engine receives structured observations
back from the target so failures can be replayed and shrunk.

### Process Target

```odin
command := [?]string{"my-cli", "cart", "add", sku, qty}
result := pbt.process_run(t, command[:])
```

Use `process_run_with_options` when the target needs a working directory or
controlled environment:

```odin
result := pbt.process_run_with_options(t, command[:], {
    working_dir = "/path/to/project",
    env = env[:],
    timeout_ms = 1_000,
    max_output_bytes = 1_048_576,
})
```

The adapter captures command, args, exit code, stdout, stderr, and duration in
nanoseconds. Use `timeout_ms` for generated or untrusted target calls so a
property fails instead of hanging indefinitely. Process stdout and stderr are
capped at 1 MiB per stream by default; use `max_output_bytes` to set a tighter
cap for noisy targets.

The first process adapter is a one-shot command runner. A persistent process
protocol should come next for faster cross-language library adapters.

### HTTP Target

```odin
res := pbt.http_post_json(t, "http://127.0.0.1:8080/cart/items", body, {
    timeout_ms = 1_000,
    max_body_bytes = 1_048_576,
})
```

`http_request` remains available for fully custom methods, headers, curl path,
and body handling.

Helpers such as `http_expect_status(res, 201)` and `http_expect_success(res)`
turn transport failures, timeouts, and unexpected status codes into normal
`Result` values.

The adapter captures method, URL, status, exit code, body, stderr, and duration
in nanoseconds. Curl-backed HTTP requests support `timeout_ms`, which maps to
curl `--max-time`. HTTP event traces include body/stderr byte counts and short
escaped previews, while the full response body and stderr remain available on
`Http_Response`. Response bodies are capped at 1 MiB by default; use
`max_body_bytes` to set a tighter cap for generated or untrusted targets.

HTTP targets are the main cross-language path: the system under test can be
written in any language as long as the property can drive and observe it over
HTTP.

The first implementation is curl-backed. That keeps the adapter portable enough
for Gransk immediately while avoiding a custom HTTP client in the PBT core.

### Protocol Target

Some libraries are better tested without spinning up HTTP. A protocol adapter
should support a persistent subprocess with structured messages:

```text
pbt engine -> target: {"op":"cart.add","sku":"abc","qty":2}
target -> pbt engine: {"ok":true,"state":{"count":2}}
```

The current request-file protocol is one-shot and can use the same
`Process_Options` through `protocol_call_with_options`, including timeouts and
process output caps.

The line protocol keeps a target process alive and sends one newline-terminated
request per call:

```odin
client, err := pbt.line_protocol_start(command[:], {env = env[:]})
defer pbt.line_protocol_stop(&client)

res := pbt.line_protocol_call(t, &client, request_json)
```

Each response is one newline-terminated line from target stdout. This is the
first persistent adapter path and is intended for small wrappers around
libraries in Go, Python, JavaScript/TypeScript, Clojure, Odin, and shell.
Response lines are capped at 1 MiB by default; use
`line_protocol_call_with_options` to set a tighter per-call cap for a target.
See `examples/line_protocol_runner` for a runnable property using this shape.

Line-delimited JSON is a good transport because it is easy to implement in Go,
Clojure, Python, JavaScript/TypeScript, Odin, and shell wrappers.

The request-file protocol remains useful for very small wrappers: `pbt` writes
the generated request to a temp file and appends that file path to the target
command.

### Stateful Target

Stateful testing should follow the Erlang QuickCheck shape:

```odin
Model :: struct {
    initial: proc(t: ^pbt.T, target: rawptr) -> State,
    command: proc(t: ^pbt.T, state: State) -> Command,
    precondition: proc(state: State, cmd: Command) -> bool,
    next_state: proc(state: State, cmd: Command, actual: Value) -> State,
    run: proc(t: ^pbt.T, target: rawptr, state: State, cmd: Command) -> Value,
    postcondition: proc(state: State, cmd: Command, actual: Value) -> pbt.Result,
    invariant: proc(t: ^pbt.T, state: State) -> pbt.Result,
    command_name: proc(cmd: Command) -> string,
    state_detail: proc(state: State) -> string,
    value_detail: proc(actual: Value) -> string,
}

result := pbt.run_commands(t, model, {
    max_len = 100,
    skip_success_events = false,
})
```

This should be the foundation for testing HTTP services, subprocesses, and
libraries against the same abstract model.

`command_name` is optional, but recommended. It makes shrunk stateful failures
much easier to read because the event trace can say `step 0 reset
postcondition` instead of only `step 0`.

`state_detail` and `value_detail` are optional, but useful for complex failures.
When supplied, captured stateful event details include the model state before
the command, the observed value returned by the target, and the next model state
for successful steps. Normal passing checks do not capture these traces on the
hot path; they are captured for failures, shrinking, replay, and explicit event
capture. Set `skip_success_events` when long successful prefixes would add noise
and only failure/precondition/invariant events should be retained.

### Statechart Target

`statechart` should be a first-class modelling adapter, not a requirement for
all stateful properties. Many systems can be modelled with a small hand-written
state record and transition functions. Statecharts are valuable when the model
has explicit modes, hierarchical states, parallel regions, guarded transitions,
delayed events, history, or entry/exit effects.

The intended use is:

- the statechart describes the simplified model we believe the system should
  obey
- generated events drive both the model and the system under test
- the adapter compares observable system behavior with the model state,
  transition result, or explicit assertions attached to the event
- failures include the generated event sequence, the shrunk sequence, and a
  statechart trace

Example shape:

```odin
events := pbt_statechart.events(chart, {max_len = 100})
result := pbt_statechart.run(t, chart, system, events)
```

The adapter should generate legal events from the current chart state, dispatch
them into the model, perform the corresponding system action, and compare model
expectations with observed system behavior.

The modelling layer is per use case. `pbt_statechart` should provide helpers for
common mechanics, but the project-specific property still decides:

- which events are generated
- which events are legal in each model state
- how an event maps to an HTTP request, CLI invocation, or library call
- which observations are compared
- which invariants must hold after each step

The first `pbt_statechart` adapter package provides:

- `enabled_triggers(instance, &out)` for active-state trigger enumeration
- `draw_enabled_trigger_or_discard(t, instance, fallback)` for generated legal
  event selection
- `dispatch_record(t, instance, trigger, name_proc)` for dispatch plus compact
  PBT trace events

The statechart library may need a few more PBT-facing helpers over time:

- dry-run or clone a model step without mutating the original instance
- emit richer structured transition traces
- attach event metadata used by generators and adapters

## Gransk Integration

Gransk should run Odin PBT tests as an engine and consume structured output:

```text
gransk spec check --engine odin/pbt path/to/spec.odin
```

The result payload should include:

- `schema_version`
- property name
- pass/fail/error/discard status
- stable result code such as `ok`, `property_failed`, `property_not_found`,
  `multiple_properties_matched`, `coverage_not_met`, or `too_many_discards`
- seed
- duration in nanoseconds
- shrink attempts and shrink duration
- replay choices
- replay choices as `choices_csv`, directly usable with `--replay-choices`
- original failure
- shrunk failure
- notes
- labels/classification stats
- adapter events
- stateful trace when present

## First Implementation Slice

1. Core `pbt` package with `check`, `draw`, `Result`, `Check_Result`, seed
   replay, and basic choice-stream shrinking.
2. Basic generators: bool, integer ranges, one-of, frequency, arrays, strings.
3. Odin `testing` integration via `require_pass`.
4. JSON result writer for Gransk.
5. Stateful command runner with `initial`, `command`, `precondition`,
   `next_state`, `run`, `postcondition`, and `invariant`. Implemented as the
   first adapter foundation.
6. Small process and HTTP adapters.
7. Statechart adapter once the stateful runner shape is proven.
