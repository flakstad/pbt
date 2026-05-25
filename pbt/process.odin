package pbt

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

LINE_PROTOCOL_DEFAULT_MAX_RESPONSE_BYTES :: 1_048_576
PROCESS_DEFAULT_MAX_OUTPUT_BYTES :: 1_048_576

Process_Output_Limit :: enum {
	None,
	Stdout,
	Stderr,
}

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
	stdin:       string,
	timeout_ms:  int,
	max_output_bytes: int,
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
	timeout_ms:         int,
}

CLI_Arg_ASCII_Input :: struct {
	min_len: int,
	max_len: int,
}

cli_arg_ascii :: proc(min_len: int = 1, max_len: int = -1) -> Gen(CLI_Arg_ASCII_Input, string) {
	return {
		input = {min_len = min_len, max_len = max_len},
		produce = proc(t: ^T, input: CLI_Arg_ASCII_Input) -> string {
			min_len := input.min_len
			if min_len < 0 {
				min_len = 0
			}
			max_len := input.max_len
			if max_len < min_len {
				max_len = max(min_len, t.size)
			}

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			length := min_len + int(choice(t, u64(max_len - min_len + 1)))
			element_ends: []int
			if t.capture_shrink_hints && length > min_len {
				element_ends = make([]int, length + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
			values := make([]byte, length, t.value_allocator)
			for i in 0 ..< length {
				index := int(choice(t, u64(len(chars))))
				values[i] = chars[index]
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, min_len, length, element_ends)
			}
			return string(values)
		},
	}
}

CLI_Flag_ASCII_Input :: struct {
	max_len: int,
	long:    bool,
}

cli_flag_ascii :: proc(max_len: int = 12, long: bool = true) -> Gen(CLI_Flag_ASCII_Input, string) {
	return {
		input = {max_len = max_len, long = long},
		produce = proc(t: ^T, input: CLI_Flag_ASCII_Input) -> string {
			max_len := input.max_len
			if max_len < 1 {
				max_len = 1
			}
			name := draw(t, path_segment_ascii(1, max_len))
			values := make([dynamic]byte, 0, len(name) + 2, t.value_allocator)
			append(&values, '-')
			if input.long {
				append(&values, '-')
			}
			append_string_bytes(&values, name)
			return string(values[:])
		},
	}
}

Process_Command_ASCII_Input :: struct {
	program:     string,
	min_args:    int,
	max_args:    int,
	max_arg_len: int,
}

process_command_ascii :: proc(program: string, min_args: int = 0, max_args: int = -1, max_arg_len: int = 16) -> Gen(Process_Command_ASCII_Input, []string) {
	return {
		input = {program = program, min_args = min_args, max_args = max_args, max_arg_len = max_arg_len},
		produce = proc(t: ^T, input: Process_Command_ASCII_Input) -> []string {
			program := input.program
			if program == "" {
				program = "target"
			}
			min_args := input.min_args
			if min_args < 0 {
				min_args = 0
			}
			max_args := input.max_args
			if max_args < min_args {
				max_args = max(min_args, t.size)
			}
			max_arg_len := input.max_arg_len
			if max_arg_len < 1 {
				max_arg_len = 1
			}

			start := 0
			if t.capture_shrink_hints {
				start = choice_cursor(t)
			}
			arg_count := min_args + int(choice(t, u64(max_args - min_args + 1)))
			element_ends: []int
			if t.capture_shrink_hints && arg_count > min_args {
				element_ends = make([]int, arg_count + 1, t.value_allocator)
				element_ends[0] = choice_cursor(t)
			}
			command := make([]string, arg_count + 1, t.value_allocator)
			command[0] = program
			arg_gen := cli_arg_ascii(1, max_arg_len)
			for i in 0 ..< arg_count {
				command[i + 1] = draw(t, arg_gen)
				if len(element_ends) > 0 {
					element_ends[i + 1] = choice_cursor(t)
				}
			}
			if len(element_ends) > 0 {
				record_collection_shrink_hints(t, start, min_args, arg_count, element_ends)
			}
			return command
		},
	}
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
	output_limit := Process_Output_Limit.None
	max_output_bytes := process_max_output_bytes(options)
	state, stdout_bytes, stderr_bytes, err, timed_out, output_limit = process_exec_guarded(os.Process_Desc {
		command = command,
		working_dir = options.working_dir,
		env = options.env,
	}, options.timeout_ms, max_output_bytes, options.stdin, t.allocator)
	duration_ns := time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
	defer delete(stdout_bytes)
	defer delete(stderr_bytes)

	result := Process_Result {
		exit_code = state.exit_code,
		success = err == nil && state.success && !timed_out && output_limit == .None,
		stdout = clone_non_empty(string(stdout_bytes), t.value_allocator),
		stderr = clone_non_empty(string(stderr_bytes), t.value_allocator),
		duration_ns = duration_ns,
	}

	status := "ok"
	if timed_out {
		status = "error"
		result.error = clone_non_empty(fmt.tprintf("process timed out after %d ms", options.timeout_ms), t.value_allocator)
	} else if output_limit != .None {
		status = "error"
		result.error = clone_non_empty(fmt.tprintf("process %s exceeded %d bytes", process_output_limit_name(output_limit), max_output_bytes), t.value_allocator)
	} else if err != nil || !state.success {
		status = "error"
		result.error = clone_non_empty(fmt.tprintf("%v", err), t.value_allocator)
	}

	record_event(t, "process", command[0] if len(command) > 0 else "", status, fmt.tprintf("%s exit=%d duration_ns=%d timeout_ms=%d max_output_bytes=%d stdin_bytes=%d", detail, state.exit_code, duration_ns, options.timeout_ms, max_output_bytes, len(options.stdin)))
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

protocol_stdin_call :: proc(t: ^T, command: []string, request: string) -> Process_Result {
	return protocol_stdin_call_with_options(t, command, request, {})
}

protocol_stdin_call_with_options :: proc(t: ^T, command: []string, request: string, options: Process_Options = {}) -> Process_Result {
	o := options
	o.stdin = request
	return process_run_with_options(t, command, o)
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

	response, read_error, response_too_long, timed_out := line_protocol_read_line(client.stdout, line_protocol_max_response_bytes(options), options.timeout_ms, t.allocator)
	duration_ns := time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
	if read_error != "" {
		err_text := read_error
		record_event(t, "protocol", "line", "error", fmt.tprintf("%s duration_ns=%d", err_text, duration_ns))
		if response_too_long || timed_out {
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

process_max_output_bytes :: proc(options: Process_Options) -> int {
	if options.max_output_bytes > 0 {
		return options.max_output_bytes
	}
	return PROCESS_DEFAULT_MAX_OUTPUT_BYTES
}

process_output_limit_name :: proc(limit: Process_Output_Limit) -> string {
	switch limit {
	case .Stdout:
		return "stdout"
	case .Stderr:
		return "stderr"
	case .None:
		return "output"
	}
	return "output"
}

process_exec_guarded :: proc(desc: os.Process_Desc, timeout_ms: int, max_output_bytes: int, stdin: string = "", allocator := context.allocator) -> (os.Process_State, []byte, []byte, os.Error, bool, Process_Output_Limit) {
	stdout_r, stdout_w, stdout_pipe_err := os.pipe()
	if stdout_pipe_err != nil {
		return {}, nil, nil, stdout_pipe_err, false, .None
	}
	defer os.close(stdout_r)

	stderr_r, stderr_w, stderr_pipe_err := os.pipe()
	if stderr_pipe_err != nil {
		os.close(stdout_w)
		return {}, nil, nil, stderr_pipe_err, false, .None
	}
	defer os.close(stderr_r)

	process_desc := desc
	stdin_w: ^os.File
	if len(stdin) > 0 && process_desc.stdin == nil {
		stdin_r, stdin_write, stdin_pipe_err := os.pipe()
		if stdin_pipe_err != nil {
			os.close(stdout_w)
			os.close(stderr_w)
			return {}, nil, nil, stdin_pipe_err, false, .None
		}
		process_desc.stdin = stdin_r
		stdin_w = stdin_write
	}
	process_desc.stdout = stdout_w
	process_desc.stderr = stderr_w
	process, start_err := os.process_start(process_desc)
	os.close(stdout_w)
	os.close(stderr_w)
	if len(stdin) > 0 && desc.stdin == nil {
		os.close(process_desc.stdin)
	}
	if start_err != nil {
		if stdin_w != nil {
			os.close(stdin_w)
		}
		return {}, nil, nil, start_err, false, .None
	}
	if stdin_w != nil {
		_, write_err := os.write_string(stdin_w, stdin)
		os.close(stdin_w)
		if write_err != nil {
			state, _ := os.process_wait(process, 0)
			if !state.exited {
				_ = os.process_kill(process)
				state, _ = os.process_wait(process)
			}
			return state, nil, nil, write_err, false, .None
		}
	}

	stdout_b := make([dynamic]byte, allocator)
	stderr_b := make([dynamic]byte, allocator)
	stdout_done := false
	stderr_done := false
	timed_out := false
	output_limit := Process_Output_Limit.None
	state: os.Process_State
	err: os.Error
	start := time.tick_now()

	for err == nil && (!stdout_done || !stderr_done) {
		if !stdout_done {
			limit_hit := false
			err = process_drain_pipe(stdout_r, &stdout_b, &stdout_done, max_output_bytes, &limit_hit)
			if err != nil {
				break
			}
			if limit_hit {
				output_limit = .Stdout
				_ = os.process_kill(process)
				state, _ = os.process_wait(process)
				stdout_done = true
				stderr_done = true
				break
			}
		}
		if !stderr_done {
			limit_hit := false
			err = process_drain_pipe(stderr_r, &stderr_b, &stderr_done, max_output_bytes, &limit_hit)
			if err != nil {
				break
			}
			if limit_hit {
				output_limit = .Stderr
				_ = os.process_kill(process)
				state, _ = os.process_wait(process)
				stdout_done = true
				stderr_done = true
				break
			}
		}

		if timeout_ms > 0 && time.duration_milliseconds(time.tick_diff(start, time.tick_now())) >= f64(timeout_ms) {
			timed_out = true
			_ = os.process_kill(process)
			state, _ = os.process_wait(process)
			stdout_done = true
			stderr_done = true
			break
		}

		if !stdout_done || !stderr_done {
			time.sleep(1 * time.Millisecond)
		}
	}

	if err != nil {
		state, _ = os.process_wait(process, 0)
		if !state.exited {
			_ = os.process_kill(process)
			state, _ = os.process_wait(process)
		}
	} else if !timed_out && output_limit == .None {
		state, err = os.process_wait(process)
	}

	return state, stdout_b[:], stderr_b[:], err, timed_out, output_limit
}

process_drain_pipe :: proc(file: ^os.File, out: ^[dynamic]byte, done: ^bool, max_bytes: int, limit_hit: ^bool) -> os.Error {
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
			if max_bytes > 0 && len(out^) + n > max_bytes {
				remaining := max_bytes - len(out^)
				if remaining > 0 {
					append(out, ..buffer[:remaining])
				}
				limit_hit^ = true
				done^ = true
				return nil
			}
			append(out, ..buffer[:n])
		case .EOF, .Broken_Pipe:
			done^ = true
			return nil
		case:
			return read_err
		}
	}
}

line_protocol_read_line :: proc(file: ^os.File, max_response_bytes, timeout_ms: int, allocator := context.allocator) -> (string, string, bool, bool) {
	builder := strings.builder_make(allocator)
	byte_count := 0
	buffer: [1]byte
	start := time.tick_now()
	for {
		if timeout_ms > 0 {
			has_data, data_err := os.pipe_has_data(file)
			if data_err == .Broken_Pipe || data_err == .EOF {
				strings.builder_destroy(&builder)
				return "", "read error: EOF", false, false
			}
			if data_err != nil {
				strings.builder_destroy(&builder)
				return "", fmt.tprintf("read error: %v", data_err), false, false
			}
			if !has_data {
				if time.duration_milliseconds(time.tick_diff(start, time.tick_now())) >= f64(timeout_ms) {
					strings.builder_destroy(&builder)
					return "", fmt.tprintf("line protocol response timed out after %d ms", timeout_ms), false, true
				}
				time.sleep(1 * time.Millisecond)
				continue
			}
		}
		n, err := os.read(file, buffer[:])
		if err != nil {
			strings.builder_destroy(&builder)
			return "", fmt.tprintf("read error: %v", err), false, false
		}
		if n == 0 {
			if timeout_ms > 0 && time.duration_milliseconds(time.tick_diff(start, time.tick_now())) >= f64(timeout_ms) {
				strings.builder_destroy(&builder)
				return "", fmt.tprintf("line protocol response timed out after %d ms", timeout_ms), false, true
			}
			strings.builder_destroy(&builder)
			return "", "read error: EOF", false, false
		}
		if buffer[0] == '\n' {
			break
		}
		if buffer[0] != '\r' {
			if byte_count >= max_response_bytes {
				strings.builder_destroy(&builder)
				return "", fmt.tprintf("line protocol response exceeded %d bytes", max_response_bytes), true, false
			}
			strings.write_byte(&builder, buffer[0])
			byte_count += 1
		}
	}
	return strings.to_string(builder), "", false, false
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
