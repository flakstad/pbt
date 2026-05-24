package pbt

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

LINE_PROTOCOL_DEFAULT_MAX_RESPONSE_BYTES :: 1_048_576

Process_Result :: struct {
	exit_code: int,
	success:   bool,
	stdout:    string,
	stderr:    string,
	duration_ns: i64,
	error:     string,
}

Process_Options :: struct {
	working_dir: string,
	env:         []string,
	timeout_ms:  int,
}

Line_Protocol_Client :: struct {
	process: os.Process,
	stdin:   ^os.File,
	stdout:  ^os.File,
	alive:   bool,
}

Line_Protocol_Result :: struct {
	success:     bool,
	response:    string,
	duration_ns: i64,
	error:       string,
}

Line_Protocol_Call_Options :: struct {
	max_response_bytes: int,
}

process_run :: proc(t: ^T, command: []string) -> Process_Result {
	return process_run_with_options(t, command, {})
}

process_run_with_options :: proc(t: ^T, command: []string, options: Process_Options = {}) -> Process_Result {
	detail := process_command_string(command, t.allocator)
	defer delete(detail)

	start_time := time.tick_now()
	state: os.Process_State
	stdout_bytes: []byte
	stderr_bytes: []byte
	err: os.Error
	timed_out := false
	if options.timeout_ms > 0 {
		state, stdout_bytes, stderr_bytes, err, timed_out = process_exec_timed(os.Process_Desc {
			command = command,
			working_dir = options.working_dir,
			env = options.env,
		}, options.timeout_ms, t.allocator)
	} else {
		state, stdout_bytes, stderr_bytes, err = os.process_exec(os.Process_Desc {
			command = command,
			working_dir = options.working_dir,
			env = options.env,
		}, t.allocator)
	}
	duration_ns := time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
	defer delete(stdout_bytes)
	defer delete(stderr_bytes)

	result := Process_Result {
		exit_code = state.exit_code,
		success = err == nil && state.success,
		stdout = clone_non_empty(string(stdout_bytes), t.value_allocator),
		stderr = clone_non_empty(string(stderr_bytes), t.value_allocator),
		duration_ns = duration_ns,
	}

	status := "ok"
	if timed_out {
		status = "error"
		result.error = clone_non_empty(fmt.tprintf("process timed out after %d ms", options.timeout_ms), t.value_allocator)
	} else if err != nil || !state.success {
		status = "error"
		result.error = clone_non_empty(fmt.tprintf("%v", err), t.value_allocator)
	}

	record_event(t, "process", command[0] if len(command) > 0 else "", status, fmt.tprintf("%s exit=%d duration_ns=%d timeout_ms=%d", detail, state.exit_code, duration_ns, options.timeout_ms))
	return result
}

protocol_call :: proc(t: ^T, command: []string, request: string) -> Process_Result {
	return protocol_call_with_options(t, command, request, {})
}

protocol_call_with_options :: proc(t: ^T, command: []string, request: string, options: Process_Options = {}) -> Process_Result {
	request_path, ok := protocol_write_request_file(t, request)
	if !ok {
		return {success = false, error = "could not write protocol request file"}
	}
	defer delete(request_path)
	defer os.remove(request_path)

	full_command := make([dynamic]string, 0, len(command) + 1, t.allocator)
	defer delete(full_command)
	for arg in command {
		append(&full_command, arg)
	}
	append(&full_command, request_path)

	return process_run_with_options(t, full_command[:], options)
}

line_protocol_start :: proc(command: []string, options: Process_Options = {}) -> (Line_Protocol_Client, os.Error) {
	stdin_read, stdin_write, stdin_err := os.pipe()
	if stdin_err != nil {
		return {}, stdin_err
	}

	stdout_read, stdout_write, stdout_err := os.pipe()
	if stdout_err != nil {
		os.close(stdin_read)
		os.close(stdin_write)
		return {}, stdout_err
	}

	process, start_err := os.process_start(os.Process_Desc {
		command = command,
		working_dir = options.working_dir,
		env = options.env,
		stdin = stdin_read,
		stdout = stdout_write,
	})
	os.close(stdin_read)
	os.close(stdout_write)
	if start_err != nil {
		os.close(stdin_write)
		os.close(stdout_read)
		return {}, start_err
	}

	return {
		process = process,
		stdin = stdin_write,
		stdout = stdout_read,
		alive = true,
	}, nil
}

line_protocol_call :: proc(t: ^T, client: ^Line_Protocol_Client, request: string) -> Line_Protocol_Result {
	return line_protocol_call_with_options(t, client, request, {})
}

line_protocol_call_with_options :: proc(t: ^T, client: ^Line_Protocol_Client, request: string, options: Line_Protocol_Call_Options = {}) -> Line_Protocol_Result {
	start_time := time.tick_now()
	if client == nil || !client.alive || client.stdin == nil || client.stdout == nil {
		return {
			success = false,
			duration_ns = time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now())),
			error = "line protocol client is not running",
		}
	}

	_, write_err := os.write_string(client.stdin, request)
	if write_err == nil {
		_, write_err = os.write_string(client.stdin, "\n")
	}
	if write_err != nil {
		duration_ns := time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
		err_text := fmt.tprintf("write error: %v", write_err)
		record_event(t, "protocol", "line", "error", fmt.tprintf("%s duration_ns=%d", err_text, duration_ns))
		return {
			success = false,
			duration_ns = duration_ns,
			error = clone_non_empty(err_text, t.value_allocator),
		}
	}

	response, read_error, response_too_long := line_protocol_read_line(client.stdout, line_protocol_max_response_bytes(options), t.allocator)
	duration_ns := time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
	if read_error != "" {
		err_text := read_error
		record_event(t, "protocol", "line", "error", fmt.tprintf("%s duration_ns=%d", err_text, duration_ns))
		if response_too_long {
			line_protocol_stop(client)
		}
		return {
			success = false,
			duration_ns = duration_ns,
			error = clone_non_empty(err_text, t.value_allocator),
		}
	}

	record_event(t, "protocol", "line", "ok", fmt.tprintf("duration_ns=%d", duration_ns))
	result_response := clone_non_empty(response, t.value_allocator)
	if len(response) > 0 {
		delete(response, t.allocator)
	}
	return {
		success = true,
		response = result_response,
		duration_ns = duration_ns,
	}
}

line_protocol_stop :: proc(client: ^Line_Protocol_Client) {
	if client == nil {
		return
	}
	if client.stdin != nil {
		os.close(client.stdin)
		client.stdin = nil
	}
	if client.alive {
		state, wait_err := os.process_wait(client.process, 100 * time.Millisecond)
		if wait_err != nil || !state.exited {
			_ = os.process_kill(client.process)
			_, _ = os.process_wait(client.process)
		}
		client.alive = false
	}
	if client.stdout != nil {
		os.close(client.stdout)
		client.stdout = nil
	}
}

line_protocol_max_response_bytes :: proc(options: Line_Protocol_Call_Options) -> int {
	if options.max_response_bytes > 0 {
		return options.max_response_bytes
	}
	return LINE_PROTOCOL_DEFAULT_MAX_RESPONSE_BYTES
}

process_exec_timed :: proc(desc: os.Process_Desc, timeout_ms: int, allocator := context.allocator) -> (os.Process_State, []byte, []byte, os.Error, bool) {
	stdout_r, stdout_w, stdout_pipe_err := os.pipe()
	if stdout_pipe_err != nil {
		return {}, nil, nil, stdout_pipe_err, false
	}
	defer os.close(stdout_r)

	stderr_r, stderr_w, stderr_pipe_err := os.pipe()
	if stderr_pipe_err != nil {
		os.close(stdout_w)
		return {}, nil, nil, stderr_pipe_err, false
	}
	defer os.close(stderr_r)

	process_desc := desc
	process_desc.stdout = stdout_w
	process_desc.stderr = stderr_w
	process, start_err := os.process_start(process_desc)
	os.close(stdout_w)
	os.close(stderr_w)
	if start_err != nil {
		return {}, nil, nil, start_err, false
	}

	stdout_b := make([dynamic]byte, allocator)
	stderr_b := make([dynamic]byte, allocator)
	stdout_done := false
	stderr_done := false
	exited := false
	timed_out := false
	state: os.Process_State
	err: os.Error
	start := time.tick_now()

	for !stdout_done || !stderr_done || !exited {
		if !stdout_done {
			err = process_drain_pipe(stdout_r, &stdout_b, &stdout_done)
			if err != nil {
				break
			}
		}
		if !stderr_done {
			err = process_drain_pipe(stderr_r, &stderr_b, &stderr_done)
			if err != nil {
				break
			}
		}

		if !exited {
			wait_state, wait_err := os.process_wait(process, 0)
			if wait_err == nil {
				state = wait_state
				exited = state.exited
			} else if wait_err != .Timeout {
				err = wait_err
				break
			}
		}

		if !exited && time.duration_milliseconds(time.tick_diff(start, time.tick_now())) >= f64(timeout_ms) {
			timed_out = true
			_ = os.process_kill(process)
			state, _ = os.process_wait(process)
			exited = true
			stdout_done = true
			stderr_done = true
		}

		if (!stdout_done || !stderr_done || !exited) && err == nil {
			time.sleep(1 * time.Millisecond)
		}
	}

	if err != nil {
		state, _ = os.process_wait(process, 0)
		if !state.exited {
			_ = os.process_kill(process)
			state, _ = os.process_wait(process)
		}
	}

	return state, stdout_b[:], stderr_b[:], err, timed_out
}

process_drain_pipe :: proc(file: ^os.File, out: ^[dynamic]byte, done: ^bool) -> os.Error {
	buffer: [1024]byte
	for {
		has_data, data_err := os.pipe_has_data(file)
		if data_err == .Broken_Pipe || data_err == .EOF {
			done^ = true
			return nil
		}
		if data_err != nil {
			return data_err
		}
		if !has_data {
			return nil
		}
		n, read_err := os.read(file, buffer[:])
		switch read_err {
		case nil:
			append(out, ..buffer[:n])
		case .EOF, .Broken_Pipe:
			done^ = true
			return nil
		case:
			return read_err
		}
	}
}

line_protocol_read_line :: proc(file: ^os.File, max_response_bytes: int, allocator := context.allocator) -> (string, string, bool) {
	builder := strings.builder_make(allocator)
	byte_count := 0
	buffer: [1]byte
	for {
		n, err := os.read(file, buffer[:])
		if err != nil {
			strings.builder_destroy(&builder)
			return "", fmt.tprintf("read error: %v", err), false
		}
		if n == 0 {
			strings.builder_destroy(&builder)
			return "", "read error: EOF", false
		}
		if buffer[0] == '\n' {
			break
		}
		if buffer[0] != '\r' {
			if byte_count >= max_response_bytes {
				strings.builder_destroy(&builder)
				return "", fmt.tprintf("line protocol response exceeded %d bytes", max_response_bytes), true
			}
			strings.write_byte(&builder, buffer[0])
			byte_count += 1
		}
	}
	return strings.to_string(builder), "", false
}

protocol_write_request_file :: proc(t: ^T, request: string) -> (string, bool) {
	path := strings.clone(fmt.tprintf("/tmp/pbt-request-%d-%d", os.get_pid(), uintptr(t)), t.allocator)

	file, create_err := os.create(path)
	if create_err != nil {
		delete(path)
		record_event(t, "protocol", "request-file", "error", fmt.tprintf("create error: %v", create_err))
		return "", false
	}

	_, write_err := os.write_string(file, request)
	os.close(file)
	if write_err != nil {
		os.remove(path)
		delete(path)
		record_event(t, "protocol", "request-file", "error", fmt.tprintf("write error: %v", write_err))
		return "", false
	}

	return path, true
}

process_expect_success :: proc(t: ^T, command: []string) -> Result {
	result := process_run(t, command)
	if result.success {
		return pass()
	}

	if len(result.stderr) > 0 {
		return fail(result.stderr)
	}
	if len(result.error) > 0 {
		return fail(result.error)
	}
	return fail(fmt.tprintf("process exited with %d", result.exit_code))
}

process_command_string :: proc(command: []string, allocator := context.allocator) -> string {
	builder := strings.builder_make(allocator)
	for arg, i in command {
		if i > 0 {
			strings.write_string(&builder, " ")
		}
		strings.write_string(&builder, arg)
	}
	return strings.to_string(builder)
}
