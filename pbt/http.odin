package pbt

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

HTTP_EVENT_PREVIEW_BYTES :: 120
HTTP_DEFAULT_MAX_BODY_BYTES :: 1_048_576

Http_Header :: struct {
	name:  string,
	value: string,
}

Http_Options :: struct {
	headers:    []Http_Header,
	curl:       string,
	timeout_ms: int,
	max_body_bytes: int,
}

Http_Request :: struct {
	method:  string,
	url:     string,
	headers: []Http_Header,
	body:    string,
	curl:    string,
	timeout_ms: int,
	max_body_bytes: int,
}

Http_Response :: struct {
	status:    int,
	success:   bool,
	body:      string,
	stderr:    string,
	exit_code: int,
	duration_ns: i64,
	timed_out: bool,
	body_too_large: bool,
	error:     string,
}

HTTP_Request_ASCII_Input :: struct {
	base_url:        string,
	max_path_segments: int,
	max_query_len:   int,
	max_body_fields: int,
	max_body_string_len: int,
	timeout_ms:      int,
	max_body_bytes:  int,
}

http_request_ascii :: proc(
	base_url: string,
	max_path_segments: int = 4,
	max_query_len: int = 12,
	max_body_fields: int = 4,
	max_body_string_len: int = 16,
	timeout_ms: int = 1_000,
	max_body_bytes: int = HTTP_DEFAULT_MAX_BODY_BYTES,
) -> Gen(HTTP_Request_ASCII_Input, Http_Request) {
	return {
		input = {
			base_url = base_url,
			max_path_segments = max_path_segments,
			max_query_len = max_query_len,
			max_body_fields = max_body_fields,
			max_body_string_len = max_body_string_len,
			timeout_ms = timeout_ms,
			max_body_bytes = max_body_bytes,
		},
		produce = proc(t: ^T, input: HTTP_Request_ASCII_Input) -> Http_Request {
			base_url := input.base_url
			if base_url == "" {
				base_url = "http://127.0.0.1"
			}

			max_path_segments := input.max_path_segments
			if max_path_segments < 1 {
				max_path_segments = 1
			}
			max_query_len := input.max_query_len
			if max_query_len < 0 {
				max_query_len = 0
			}
			max_body_fields := input.max_body_fields
			if max_body_fields < 0 {
				max_body_fields = 0
			}
			max_body_string_len := input.max_body_string_len
			if max_body_string_len < 0 {
				max_body_string_len = 0
			}

			method := draw(t, http_method())
			path := draw(t, url_path_ascii(1, max_path_segments, 1, 12))
			query := ""
			if max_query_len > 0 && draw(t, boolean()) {
				key := draw(t, non_empty_query_component_ascii(max_query_len))
				value := draw(t, query_component_ascii(0, max_query_len))
				query = http_build_query(t, key, value)
			}

			url := http_build_url(t, base_url, path, query)
			request := Http_Request {
				method = method,
				url = url,
				timeout_ms = input.timeout_ms,
				max_body_bytes = input.max_body_bytes,
			}

			if http_method_supports_generated_body(method) {
				request.body = draw(t, json_object_ascii(0, max_body_fields, 12, max_body_string_len))
				headers := make([]Http_Header, 2, t.value_allocator)
				headers[0] = http_header("Content-Type", "application/json")
				headers[1] = http_header("Accept", "application/json")
				request.headers = headers
			}
			return request
		},
	}
}

http_method_supports_generated_body :: proc(method: string) -> bool {
	switch method {
	case "POST", "PUT", "PATCH":
		return true
	}
	return false
}

http_build_query :: proc(t: ^T, key, value: string) -> string {
	values := make([dynamic]byte, 0, len(key) + len(value) + 1, t.value_allocator)
	append_string_bytes(&values, key)
	append(&values, '=')
	append_string_bytes(&values, value)
	return string(values[:])
}

http_build_url :: proc(t: ^T, base_url, path, query: string) -> string {
	capacity := len(base_url) + len(path) + len(query) + 1
	values := make([dynamic]byte, 0, capacity, t.value_allocator)
	append_string_bytes(&values, base_url)
	if len(base_url) > 0 && base_url[len(base_url) - 1] == '/' && len(path) > 0 && path[0] == '/' {
		append_string_bytes(&values, path[1:])
	} else if len(base_url) > 0 && base_url[len(base_url) - 1] != '/' && (len(path) == 0 || path[0] != '/') {
		append(&values, '/')
		append_string_bytes(&values, path)
	} else {
		append_string_bytes(&values, path)
	}
	if len(query) > 0 {
		append(&values, '?')
		append_string_bytes(&values, query)
	}
	return string(values[:])
}

http_header :: proc(name, value: string) -> Http_Header {
	return {name = name, value = value}
}

http_get :: proc(t: ^T, url: string) -> Http_Response {
	return http_request(t, {method = "GET", url = url})
}

http_get_with_options :: proc(t: ^T, url: string, options: Http_Options = {}) -> Http_Response {
	return http_request(t, {
		method = "GET",
		url = url,
		headers = options.headers,
		curl = options.curl,
		timeout_ms = options.timeout_ms,
		max_body_bytes = options.max_body_bytes,
	})
}

http_post :: proc(t: ^T, url, body: string, headers: []Http_Header = nil) -> Http_Response {
	return http_request(t, {method = "POST", url = url, body = body, headers = headers})
}

http_post_json :: proc(t: ^T, url, body: string, options: Http_Options = {}) -> Http_Response {
	headers := make([dynamic]Http_Header, 0, 2 + len(options.headers), t.allocator)
	defer delete(headers)
	append(&headers, http_header("Content-Type", "application/json"))
	append(&headers, http_header("Accept", "application/json"))
	for header in options.headers {
		append(&headers, header)
	}

	return http_request(t, {
		method = "POST",
		url = url,
		body = body,
		headers = headers[:],
		curl = options.curl,
		timeout_ms = options.timeout_ms,
		max_body_bytes = options.max_body_bytes,
	})
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

	max_body_bytes := http_max_body_bytes(request)
	body_bytes, body_too_large, read_err := http_read_response_body(response_path, max_body_bytes, t.allocator)
	if read_err == nil {
		response.body = clone_non_empty(string(body_bytes), t.value_allocator)
		delete(body_bytes)
		response.body_too_large = body_too_large
		if body_too_large {
			response.success = false
			response.error = clone_non_empty(fmt.tprintf("HTTP response body exceeded %d bytes", max_body_bytes), t.value_allocator)
		}
	} else if response.success {
		response.success = false
		response.error = clone_non_empty(fmt.tprintf("HTTP response body read error: %v", read_err), t.value_allocator)
	}
	response.duration_ns = time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))

	event_status := "ok"
	if !response.success {
		event_status = "error"
	}
	event_detail := http_event_detail(response, request.timeout_ms, max_body_bytes, t.allocator)
	defer delete(event_detail)
	record_event(t, "http", http_event_name(request), event_status, event_detail)
	return response
}

http_expect_status :: proc(response: Http_Response, expected: int) -> Result {
	if !response.success {
		if response.timed_out {
			return fail(fmt.tprintf("HTTP request timed out after %d ns", response.duration_ns))
		}
		if len(response.error) > 0 {
			return fail(response.error)
		}
		if len(response.stderr) > 0 {
			return fail(response.stderr)
		}
		return fail(fmt.tprintf("HTTP request failed with exit code %d", response.exit_code))
	}
	if response.status != expected {
		return fail(fmt.tprintf("expected HTTP status %d, got %d", expected, response.status))
	}
	return pass()
}

http_expect_success :: proc(response: Http_Response) -> Result {
	if !response.success {
		return http_expect_status(response, 200)
	}
	if response.status < 200 || response.status >= 300 {
		return fail(fmt.tprintf("expected HTTP 2xx status, got %d", response.status))
	}
	return pass()
}

http_event_name :: proc(request: Http_Request) -> string {
	method := request.method
	if method == "" {
		method = "GET"
	}
	return fmt.tprintf("%s %s", method, request.url)
}

http_max_body_bytes :: proc(request: Http_Request) -> int {
	if request.max_body_bytes > 0 {
		return request.max_body_bytes
	}
	return HTTP_DEFAULT_MAX_BODY_BYTES
}

http_read_response_body :: proc(path: string, max_body_bytes: int, allocator := context.allocator) -> ([]byte, bool, os.Error) {
	file, open_err := os.open(path)
	if open_err != nil {
		return nil, false, open_err
	}
	defer os.close(file)

	size, size_err := os.file_size(file)
	if size_err == nil && max_body_bytes > 0 && size > i64(max_body_bytes) {
		body, read_err := http_read_file_prefix(file, max_body_bytes, allocator)
		return body, true, read_err
	}

	body, read_err := os.read_entire_file(file, allocator)
	return body, false, read_err
}

http_read_file_prefix :: proc(file: ^os.File, max_bytes: int, allocator := context.allocator) -> ([]byte, os.Error) {
	if max_bytes <= 0 {
		return []byte{}, nil
	}

	body := make([]byte, max_bytes, allocator)
	total := 0
	for total < len(body) {
		n, err := os.read(file, body[total:])
		total += n
		if err != nil {
			if err == .EOF {
				err = nil
			}
			return body[:total], err
		}
		if n == 0 {
			break
		}
	}
	return body[:total], nil
}

http_event_detail :: proc(response: Http_Response, timeout_ms: int, max_body_bytes: int, allocator := context.allocator) -> string {
	builder := strings.builder_make(allocator)
	strings.write_string(&builder, fmt.tprintf("status=%d exit=%d duration_ns=%d timeout_ms=%d max_body_bytes=%d", response.status, response.exit_code, response.duration_ns, timeout_ms, max_body_bytes))
	if response.body_too_large {
		strings.write_string(&builder, " body_truncated=true")
	}
	http_write_event_preview(&builder, "body", response.body)
	http_write_event_preview(&builder, "stderr", response.stderr)
	return strings.to_string(builder)
}

http_write_event_preview :: proc(builder: ^strings.Builder, label, value: string) {
	if len(value) == 0 {
		return
	}

	strings.write_string(builder, fmt.tprintf(" %s_bytes=%d %s_preview=\"", label, len(value), label))
	limit := len(value)
	if limit > HTTP_EVENT_PREVIEW_BYTES {
		limit = HTTP_EVENT_PREVIEW_BYTES
	}
	for i in 0 ..< limit {
		switch value[i] {
		case '\n':
			strings.write_string(builder, "\\n")
		case '\r':
			strings.write_string(builder, "\\r")
		case '\t':
			strings.write_string(builder, "\\t")
		case '"':
			strings.write_string(builder, "\\\"")
		case '\\':
			strings.write_string(builder, "\\\\")
		case:
			if value[i] < 32 || value[i] > 126 {
				strings.write_byte(builder, '?')
			} else {
				strings.write_byte(builder, value[i])
			}
		}
	}
	if len(value) > limit {
		strings.write_string(builder, "...")
	}
	strings.write_string(builder, "\"")
}
