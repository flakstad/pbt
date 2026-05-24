package pbt

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

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
}

process_run :: proc(t: ^T, command: []string) -> Process_Result {
	return process_run_with_options(t, command, {})
}

process_run_with_options :: proc(t: ^T, command: []string, options: Process_Options = {}) -> Process_Result {
	detail := process_command_string(command, t.allocator)
	defer delete(detail)

	start_time := time.tick_now()
	state, stdout_bytes, stderr_bytes, err := os.process_exec(os.Process_Desc {
		command = command,
		working_dir = options.working_dir,
		env = options.env,
	}, t.allocator)
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
	if err != nil || !state.success {
		status = "error"
		result.error = clone_non_empty(fmt.tprintf("%v", err), t.value_allocator)
	}

	record_event(t, "process", command[0] if len(command) > 0 else "", status, fmt.tprintf("%s exit=%d duration_ns=%d", detail, state.exit_code, duration_ns))
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
