package pbt

import "core:fmt"

Status :: enum {
	Pass,
	Fail,
	Discard,
	Error,
}

Result :: struct {
	status:  Status,
	message: string,
}

pass :: proc() -> Result {
	return {status = .Pass}
}

fail :: proc(message: string) -> Result {
	return {status = .Fail, message = message}
}

counterexample :: proc(message: string, result: Result) -> Result {
	if result.status == .Pass {
		return result
	}
	if len(result.message) == 0 {
		return {status = result.status, message = message}
	}
	return {status = result.status, message = fmt.tprintf("%s\n%s", message, result.message)}
}

discard :: proc(message: string = "") -> Result {
	return {status = .Discard, message = message}
}

error :: proc(message: string) -> Result {
	return {status = .Error, message = message}
}

assert :: proc(ok: bool, message: string = "assertion failed") -> Result {
	if ok {
		return pass()
	}

	return fail(message)
}

equal :: proc(actual, expected: $T) -> Result {
	if actual == expected {
		return pass()
	}

	return fail(fmt.tprintf("expected %v, got %v", expected, actual))
}
