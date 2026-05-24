package pbt

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

Http_Header :: struct {
	name:  string,
	value: string,
}

Http_Request :: struct {
	method:  string,
	url:     string,
	headers: []Http_Header,
	body:    string,
	curl:    string,
	timeout_ms: int,
}

Http_Response :: struct {
	status:    int,
	success:   bool,
	body:      string,
	stderr:    string,
	exit_code: int,
	duration_ns: i64,
	timed_out: bool,
	error:     string,
}

http_get :: proc(t: ^T, url: string) -> Http_Response {
	return http_request(t, {method = "GET", url = url})
}

http_post :: proc(t: ^T, url, body: string, headers: []Http_Header = nil) -> Http_Response {
	return http_request(t, {method = "POST", url = url, body = body, headers = headers})
}

http_request :: proc(t: ^T, request: Http_Request) -> Http_Response {
	start_time := time.tick_now()
	curl := request.curl
	if curl == "" {
		curl = "curl"
	}

	response_path := strings.clone(fmt.tprintf("/tmp/pbt-http-response-%d-%d", os.get_pid(), uintptr(t)), t.allocator)
	defer delete(response_path)
	defer os.remove(response_path)

	command := make([dynamic]string, 0, 16 + len(request.headers) * 2, t.allocator)
	defer delete(command)
	append(&command, curl)
	append(&command, "-sS")
	append(&command, "-o")
	append(&command, response_path)
	append(&command, "-w")
	append(&command, "%{http_code}")
	if request.timeout_ms > 0 {
		append(&command, "--max-time")
		append(&command, fmt.tprintf("%.3f", f64(request.timeout_ms) / 1000.0))
	}

	if request.method != "" {
		append(&command, "-X")
		append(&command, request.method)
	}

	for header in request.headers {
		append(&command, "-H")
		append(&command, fmt.tprintf("%s: %s", header.name, header.value))
	}

	body_path: string
	if len(request.body) > 0 {
		body_path = strings.clone(fmt.tprintf("/tmp/pbt-http-body-%d-%d", os.get_pid(), uintptr(t)), t.allocator)
		defer delete(body_path)
		defer os.remove(body_path)

		file, create_err := os.create(body_path)
		if create_err != nil {
			duration_ns := time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
			record_event(t, "http", http_event_name(request), "error", fmt.tprintf("body create error: %v", create_err))
			return {success = false, duration_ns = duration_ns, error = clone_non_empty(fmt.tprintf("%v", create_err), t.value_allocator)}
		}
		_, write_err := os.write_string(file, request.body)
		os.close(file)
		if write_err != nil {
			duration_ns := time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
			record_event(t, "http", http_event_name(request), "error", fmt.tprintf("body write error: %v", write_err))
			return {success = false, duration_ns = duration_ns, error = clone_non_empty(fmt.tprintf("%v", write_err), t.value_allocator)}
		}

		append(&command, "--data-binary")
		append(&command, fmt.tprintf("@%s", body_path))
	}

	append(&command, request.url)

	process_result := process_run(t, command[:])
	response := Http_Response {
		exit_code = process_result.exit_code,
		success = process_result.success,
		stderr = process_result.stderr,
		error = process_result.error,
		timed_out = process_result.exit_code == 28,
	}

	status_text := strings.trim_space(process_result.stdout)
	status, status_ok := strconv.parse_int(status_text, 10)
	if status_ok {
		response.status = status
	}

	body_bytes, read_err := os.read_entire_file(response_path, t.allocator)
	if read_err == nil {
		response.body = clone_non_empty(string(body_bytes), t.value_allocator)
		delete(body_bytes)
	}
	response.duration_ns = time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))

	event_status := "ok"
	if !response.success {
		event_status = "error"
	}
	record_event(t, "http", http_event_name(request), event_status, fmt.tprintf("status=%d exit=%d duration_ns=%d timeout_ms=%d", response.status, response.exit_code, response.duration_ns, request.timeout_ms))
	return response
}

http_event_name :: proc(request: Http_Request) -> string {
	method := request.method
	if method == "" {
		method = "GET"
	}
	return fmt.tprintf("%s %s", method, request.url)
}
