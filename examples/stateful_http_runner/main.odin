package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

import pbt "../../pbt"

HTTP_STATEFUL_TAGS := [?]string{"stateful", "http", "api", "external"}
TODO_MAX_ID :: 16

Todo_Command_Kind :: enum {
	Create,
	Delete,
	List,
}

Todo_Command :: struct {
	kind: Todo_Command_Kind,
	id:   int,
}

Todo_Model :: struct {
	next_id: int,
	present: [TODO_MAX_ID]bool,
}

Todo_Target :: struct {
	base_url: string,
	process:  os.Process,
	started:  bool,
}

Todo_Observation :: struct {
	success: bool,
	status:  int,
	id:      int,
	listed:  [TODO_MAX_ID]bool,
	body:    string,
	error:   string,
}

todo_stateful_http_property :: proc(t: ^pbt.T) -> pbt.Result {
	target, ok := todo_target_start(t)
	if !ok {
		return pbt.error("could not start todo HTTP target")
	}
	defer todo_target_stop(&target)

	model := pbt.State_Model(Todo_Model, Todo_Command, Todo_Observation) {
		target = &target,
		initial = todo_initial,
		command = todo_command,
		precondition = todo_precondition,
		run = todo_run,
		next_state = todo_next_state,
		postcondition = todo_postcondition,
		invariant = todo_invariant,
		command_name = todo_command_name,
		state_detail = todo_state_detail,
		value_detail = todo_value_detail,
	}
	return pbt.run_commands(t, model, {min_len = 1, max_len = 25, skip_success_events = true})
}

main :: proc() {
	properties := [?]pbt.Property_Case {
		{name = "todo http stateful", property = todo_stateful_http_property, description = "stateful CRUD model checked against a tiny HTTP API", tags = HTTP_STATEFUL_TAGS[:]},
	}

	pbt.run_cli(properties[:], os.args[1:], {shrink = true})
}

todo_target_start :: proc(t: ^pbt.T) -> (Todo_Target, bool) {
	port := 18_500 + int(os.get_pid() % 1000)
	base_url := strings.clone(fmt.tprintf("http://127.0.0.1:%d", port), t.value_allocator)
	code := todo_server_code()
	defer delete(code)
	port_arg := fmt.tprintf("%d", port)
	command := [?]string{"python3", "-u", "-c", code, port_arg}
	process, err := os.process_start(os.Process_Desc{command = command[:]})
	if err != nil {
		return {}, false
	}

	target := Todo_Target{base_url = base_url, process = process, started = true}
	if !todo_wait_ready(target.base_url) {
		todo_target_stop(&target)
		return {}, false
	}
	return target, true
}

todo_target_stop :: proc(target: ^Todo_Target) {
	if target == nil || !target.started {
		return
	}
	state, wait_err := os.process_wait(target.process, 0)
	if wait_err != nil || !state.exited {
		_ = os.process_kill(target.process)
		_, _ = os.process_wait(target.process)
	}
	target.started = false
}

todo_wait_ready :: proc(base_url: string) -> bool {
	url := strings.concatenate({base_url, "/todos"}, context.temp_allocator)
	for _ in 0 ..< 50 {
		command := [?]string{"curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "0.100", "-X", "GET", url}
		state, stdout, stderr, err := os.process_exec(os.Process_Desc{command = command[:]}, context.temp_allocator)
		_ = stderr
		if err == nil && state.success && strings.trim_space(string(stdout)) == "200" {
			return true
		}
		time.sleep(20 * time.Millisecond)
	}
	return false
}

todo_server_code :: proc() -> string {
	return strings.concatenate({
		"import os,sys\n",
		"from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer\n",
		"port=int(sys.argv[1]); todos=set(); next_id=1; bug=os.environ.get('PBT_TODO_BUG')\n",
		"class H(BaseHTTPRequestHandler):\n",
		" def body(self,s):\n",
		"  b=s.encode(); self.send_response(200); self.send_header('Content-Type','text/plain'); self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)\n",
		" def do_GET(self):\n",
		"  global todos\n",
		"  if self.path=='/todos': self.body(','.join(str(x) for x in sorted(todos))); return\n",
		"  self.send_response(404); self.end_headers()\n",
		" def do_POST(self):\n",
		"  global todos,next_id\n",
		"  if self.path!='/todos': self.send_response(404); self.end_headers(); return\n",
		"  n=int(self.headers.get('Content-Length','0')); self.rfile.read(n) if n else None\n",
		"  item=next_id; next_id+=1; todos.add(item); b=str(item).encode(); self.send_response(201); self.send_header('Content-Type','text/plain'); self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)\n",
		" def do_DELETE(self):\n",
		"  global todos,bug\n",
		"  if not self.path.startswith('/todos/'): self.send_response(404); self.end_headers(); return\n",
		"  try: item=int(self.path.rsplit('/',1)[1])\n",
		"  except Exception: item=-1\n",
		"  if bug!='delete': todos.discard(item)\n",
		"  self.send_response(204); self.end_headers()\n",
		" def log_message(self,fmt,*args): return\n",
		"ThreadingHTTPServer(('127.0.0.1',port),H).serve_forever()\n",
	}, context.allocator)
}

todo_initial :: proc(t: ^pbt.T, target: rawptr) -> Todo_Model {
	return {next_id = 1}
}

todo_command :: proc(t: ^pbt.T, state: Todo_Model) -> Todo_Command {
	kind := pbt.draw(t, pbt.enum_range(Todo_Command_Kind.Create, Todo_Command_Kind.List))
	command := Todo_Command{kind = kind}
	if kind == .Delete {
		command.id = todo_draw_present_id(t, state)
	}
	return command
}

todo_draw_present_id :: proc(t: ^pbt.T, state: Todo_Model) -> int {
	count := todo_present_count(state)
	if count == 0 {
		return 0
	}
	index := pbt.draw(t, pbt.int_range(0, count - 1))
	seen := 0
	for id in 1 ..< TODO_MAX_ID {
		if state.present[id] {
			if seen == index {
				return id
			}
			seen += 1
		}
	}
	return 0
}

todo_precondition :: proc(state: Todo_Model, command: Todo_Command) -> bool {
	switch command.kind {
	case .Create:
		return state.next_id < TODO_MAX_ID
	case .Delete:
		return command.id > 0 && command.id < TODO_MAX_ID && state.present[command.id]
	case .List:
		return true
	}
	return true
}

todo_run :: proc(t: ^pbt.T, target: rawptr, state: Todo_Model, command: Todo_Command) -> Todo_Observation {
	todo := cast(^Todo_Target)target
	switch command.kind {
	case .Create:
		body := fmt.tprintf("{\"title\":\"todo-%d\"}", state.next_id)
		response := pbt.http_post_json(t, strings.concatenate({todo.base_url, "/todos"}, context.temp_allocator), body, {timeout_ms = 500, max_body_bytes = 1024})
		obs := todo_observation_from_response(response)
		if obs.success {
			id, ok := strconv.parse_int(strings.trim_space(response.body), 10)
			if ok {
				obs.id = id
			} else {
				obs.success = false
				obs.error = fmt.tprintf("create returned non-integer id %q", response.body)
			}
		}
		return todo_observe_list(t, todo, obs)
	case .Delete:
		url := fmt.tprintf("%s/todos/%d", todo.base_url, command.id)
		response := pbt.http_request(t, {method = "DELETE", url = url, timeout_ms = 500, max_body_bytes = 1024})
		obs := todo_observation_from_response(response)
		return todo_observe_list(t, todo, obs)
	case .List:
		return todo_observe_list(t, todo, {success = true, status = 200})
	}
	return {success = false, error = "unknown command"}
}

todo_observation_from_response :: proc(response: pbt.Http_Response) -> Todo_Observation {
	if !response.success {
		return {success = false, status = response.status, body = response.body, error = response.error}
	}
	return {success = true, status = response.status, body = response.body}
}

todo_observe_list :: proc(t: ^pbt.T, target: ^Todo_Target, obs: Todo_Observation) -> Todo_Observation {
	result := obs
	response := pbt.http_get_with_options(t, strings.concatenate({target.base_url, "/todos"}, context.temp_allocator), {timeout_ms = 500, max_body_bytes = 1024})
	if !response.success {
		result.success = false
		result.error = response.error
		return result
	}
	if response.status != 200 {
		result.success = false
		result.error = fmt.tprintf("list returned HTTP %d", response.status)
		return result
	}
	result.listed = todo_parse_list(response.body)
	return result
}

todo_parse_list :: proc(body: string) -> [TODO_MAX_ID]bool {
	present: [TODO_MAX_ID]bool
	start := 0
	for i := 0; i <= len(body); i += 1 {
		if i == len(body) || body[i] == ',' {
			if i > start {
				id, ok := strconv.parse_int(body[start:i], 10)
				if ok && id > 0 && id < TODO_MAX_ID {
					present[id] = true
				}
			}
			start = i + 1
		}
	}
	return present
}

todo_next_state :: proc(state: Todo_Model, command: Todo_Command, value: Todo_Observation) -> Todo_Model {
	next := state
	switch command.kind {
	case .Create:
		next.present[state.next_id] = true
		next.next_id += 1
	case .Delete:
		next.present[command.id] = false
	case .List:
	}
	return next
}

todo_postcondition :: proc(state: Todo_Model, command: Todo_Command, value: Todo_Observation) -> pbt.Result {
	if !value.success {
		return pbt.fail(value.error)
	}
	if command.kind == .Create {
		if value.status != 201 {
			return pbt.fail(fmt.tprintf("create expected HTTP 201, got %d", value.status))
		}
		if value.id != state.next_id {
			return pbt.fail(fmt.tprintf("create expected id=%d actual=%d", state.next_id, value.id))
		}
	}
	if command.kind == .Delete && value.status != 204 {
		return pbt.fail(fmt.tprintf("delete expected HTTP 204, got %d", value.status))
	}

	expected := todo_next_state(state, command, value)
	if !todo_present_equal(expected.present, value.listed) {
		return pbt.fail(fmt.tprintf("command=%s expected=%s actual=%s", todo_command_name(command), todo_present_detail(expected.present), todo_present_detail(value.listed)))
	}
	return pbt.pass()
}

todo_invariant :: proc(t: ^pbt.T, state: Todo_Model) -> pbt.Result {
	return pbt.assert(state.next_id > 0 && state.next_id <= TODO_MAX_ID, "model next id should stay in range")
}

todo_command_name :: proc(command: Todo_Command) -> string {
	switch command.kind {
	case .Create:
		return "create"
	case .Delete:
		return fmt.tprintf("delete %d", command.id)
	case .List:
		return "list"
	}
	return "unknown"
}

todo_state_detail :: proc(state: Todo_Model) -> string {
	return fmt.tprintf("next=%d present=%s", state.next_id, todo_present_detail(state.present))
}

todo_value_detail :: proc(value: Todo_Observation) -> string {
	if !value.success {
		return fmt.tprintf("status=%d error=%s body=%s", value.status, value.error, value.body)
	}
	return fmt.tprintf("status=%d id=%d listed=%s", value.status, value.id, todo_present_detail(value.listed))
}

todo_present_count :: proc(state: Todo_Model) -> int {
	count := 0
	for id in 1 ..< TODO_MAX_ID {
		if state.present[id] {
			count += 1
		}
	}
	return count
}

todo_present_equal :: proc(a, b: [TODO_MAX_ID]bool) -> bool {
	for id in 1 ..< TODO_MAX_ID {
		if a[id] != b[id] {
			return false
		}
	}
	return true
}

todo_present_detail :: proc(present: [TODO_MAX_ID]bool) -> string {
	builder: strings.Builder
	strings.builder_init(&builder)
	strings.write_string(&builder, "[")
	first := true
	for id in 1 ..< TODO_MAX_ID {
		if !present[id] {
			continue
		}
		if !first {
			strings.write_string(&builder, ",")
		}
		strings.write_string(&builder, fmt.tprintf("%d", id))
		first = false
	}
	strings.write_string(&builder, "]")
	out := strings.clone(strings.to_string(builder), context.temp_allocator)
	strings.builder_destroy(&builder)
	return out
}
