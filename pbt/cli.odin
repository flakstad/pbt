package pbt

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

Property_Case :: struct {
	name:        string,
	property:    Property,
	description: string,
	tags:        []string,
}

Property_Tag :: struct {
	name:       string,
	count:      int,
	properties: [dynamic]string,
}

parse_check_options :: proc(args: []string, defaults: Check_Options = {}) -> Check_Options {
	options := defaults

	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "--num-tests", "-n":
			if i + 1 < len(args) {
				if value, ok := strconv.parse_int(args[i + 1], 10); ok {
					options.num_tests = value
				}
				i += 1
			}
		case "--max-discards":
			if i + 1 < len(args) {
				if value, ok := strconv.parse_int(args[i + 1], 10); ok {
					options.max_discards = value
				}
				i += 1
			}
		case "--seed":
			if i + 1 < len(args) {
				if value, ok := strconv.parse_uint(args[i + 1], 10); ok {
					options.seed = u64(value)
				}
				i += 1
			}
		case "--max-size":
			if i + 1 < len(args) {
				if value, ok := strconv.parse_int(args[i + 1], 10); ok {
					options.max_size = value
				}
				i += 1
			}
		case "--max-shrinks":
			if i + 1 < len(args) {
				if value, ok := strconv.parse_int(args[i + 1], 10); ok {
					options.max_shrinks = value
				}
				i += 1
			}
		case "--shrink":
			options.shrink = true
			options.no_shrink = false
		case "--no-shrink":
			options.shrink = false
			options.no_shrink = true
		}
	}

	return options
}

check_from_args :: proc(name: string, property: Property, args: []string, defaults: Check_Options = {}) -> Check_Result {
	options := parse_check_options(args, defaults)
	if replay, ok := parse_replay(args); ok {
		defer destroy_replay(&replay)
		return check_replay(name, property, replay, options)
	}

	return check(name, property, options)
}

check_property_from_args :: proc(properties: []Property_Case, args: []string, defaults: Check_Options = {}) -> Check_Result {
	if len(properties) == 0 {
		return {status = .Error, code = "no_properties_registered", message = "no properties registered"}
	}

	name := parse_property_name(args)
	if name == "" && len(properties) == 1 {
		return check_from_args(properties[0].name, properties[0].property, args, defaults)
	}

	for property in properties {
		if property.name == name {
			return check_from_args(property.name, property.property, args, defaults)
		}
	}

	if name != "" {
		matches := 0
		match_index := -1
		for property, i in properties {
			if strings.contains(property.name, name) {
				matches += 1
				match_index = i
			}
		}

		if matches == 1 {
			property := properties[match_index]
			return check_from_args(property.name, property.property, args, defaults)
		}
		if matches > 1 {
			return {
				name = name,
				status = .Error,
				code = "multiple_properties_matched",
				message = "multiple properties matched",
			}
		}
	}

	return {
		name = name,
		status = .Error,
		code = "property_not_found",
		message = "property not found",
	}
}

check_properties_from_args :: proc(properties: []Property_Case, args: []string, defaults: Check_Options = {}) -> Check_Suite_Result {
	start_time := time.tick_now()
	result := Check_Suite_Result {
		status = .Pass,
		code = "ok",
		fail_fast = has_fail_fast_flag(args),
	}

	if len(properties) == 0 {
		result.status = .Error
		result.code = "no_properties_registered"
		result.message = "no properties registered"
		result.duration_ns = time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
		return result
	}

	tag := parse_property_tag(args)
	filtered := make([dynamic]Property_Case)
	defer delete(filtered)
	active_properties := properties
	if tag != "" {
		for property in properties {
			if property_has_tag(property, tag) {
				append(&filtered, property)
			}
		}
		active_properties = filtered[:]
		if len(active_properties) == 0 {
			result.status = .Error
			result.code = "no_properties_matched_tag"
			result.message = "no properties matched tag"
			result.duration_ns = time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
			return result
		}
	}

	name := parse_property_name(args)
	if name == "" && has_replay_args(args) && len(active_properties) > 1 {
		result.status = .Error
		result.code = "property_required_for_replay"
		result.message = "replay requires --property when multiple properties are registered"
		result.duration_ns = time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
		return result
	}

	result.results = make([dynamic]Check_Result)

	if name != "" || len(active_properties) == 1 {
		property_result := check_property_from_args(active_properties, args, defaults)
		append(&result.results, property_result)
		check_suite_add_result(&result, property_result)
		check_suite_finalize(&result, start_time)
		return result
	}

	for property in active_properties {
		property_result := check_from_args(property.name, property.property, args, defaults)
		append(&result.results, property_result)
		check_suite_add_result(&result, property_result)
		if result.fail_fast && property_result.status != .Pass {
			break
		}
	}
	check_suite_finalize(&result, start_time)
	return result
}

run_cli :: proc(properties: []Property_Case, args: []string, defaults: Check_Options = {}) -> ! {
	if has_list_properties_flag(args) {
		json := properties_json(properties)
		fmt.println(json)
		delete(json)
		os.exit(0)
	}
	if has_list_tags_flag(args) {
		json := tags_json(properties)
		fmt.println(json)
		delete(json)
		os.exit(0)
	}

	result := check_properties_from_args(properties, args, defaults)
	print_check_suite_result(result, use_json_output(args))
	exit_code := check_suite_result_exit_code(result)
	destroy_check_suite_result(&result)
	os.exit(exit_code)
}

check_suite_add_result :: proc(suite: ^Check_Suite_Result, result: Check_Result) {
	suite.num_properties += 1
	suite.checks += check_result_effective_checks(result)
	suite.discards += result.num_discards
	switch result.status {
	case .Pass:
		suite.passed += 1
	case .Fail:
		suite.failed += 1
	case .Discard, .Error:
		suite.errors += 1
	}
}

check_suite_finalize :: proc(suite: ^Check_Suite_Result, start_time: time.Tick) {
	if suite.errors > 0 {
		suite.status = .Error
		suite.code = "suite_error"
		suite.message = "one or more properties errored"
	} else if suite.failed > 0 {
		suite.status = .Fail
		suite.code = "suite_failed"
		suite.message = "one or more properties failed"
	} else {
		suite.status = .Pass
		suite.code = "ok"
		suite.message = ""
	}
	suite.duration_ns = time.duration_nanoseconds(time.tick_diff(start_time, time.tick_now()))
}

parse_property_name :: proc(args: []string) -> string {
	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "--property", "-p":
			if i + 1 < len(args) {
				return args[i + 1]
			}
			i += 1
		}
	}

	return ""
}

parse_property_tag :: proc(args: []string) -> string {
	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "--tag", "-t":
			if i + 1 < len(args) {
				return args[i + 1]
			}
			i += 1
		}
	}

	return ""
}

property_has_tag :: proc(property: Property_Case, tag: string) -> bool {
	for candidate in property.tags {
		if candidate == tag {
			return true
		}
	}
	return false
}

has_list_properties_flag :: proc(args: []string) -> bool {
	for arg in args {
		if arg == "--list-properties" {
			return true
		}
	}
	return false
}

has_list_tags_flag :: proc(args: []string) -> bool {
	for arg in args {
		if arg == "--list-tags" {
			return true
		}
	}
	return false
}

has_fail_fast_flag :: proc(args: []string) -> bool {
	return has_arg(args, "--fail-fast")
}

property_tags :: proc(properties: []Property_Case) -> [dynamic]Property_Tag {
	tags := make([dynamic]Property_Tag)
	for property in properties {
		for tag in property.tags {
			property_tags_add(&tags, tag, property.name)
		}
	}
	return tags
}

destroy_property_tags :: proc(tags: ^[dynamic]Property_Tag) {
	for i := 0; i < len(tags^); i += 1 {
		delete(tags^[i].properties)
	}
	delete(tags^)
}

property_tags_add :: proc(tags: ^[dynamic]Property_Tag, name, property_name: string) {
	for i := 0; i < len(tags^); i += 1 {
		if tags^[i].name == name {
			tags^[i].count += 1
			append(&tags^[i].properties, property_name)
			return
		}
	}
	properties := make([dynamic]string)
	append(&properties, property_name)
	append(tags, Property_Tag{name = name, count = 1, properties = properties})
}

has_replay_args :: proc(args: []string) -> bool {
	return has_arg(args, "--replay-seed") || has_arg(args, "--replay-choices")
}

has_arg :: proc(args: []string, name: string) -> bool {
	for arg in args {
		if arg == name {
			return true
		}
	}
	return false
}

use_json_output :: proc(args: []string, default_json: bool = true) -> bool {
	use_json := default_json
	for arg in args {
		switch arg {
		case "--json":
			use_json = true
		case "--text":
			use_json = false
		}
	}
	return use_json
}

properties_json :: proc(properties: []Property_Case) -> string {
	builder: strings.Builder
	strings.builder_init(&builder)

	strings.write_string(&builder, "{\"tool\":\"pbt\",\"schema_version\":1,\"properties\":[")
	for property, i in properties {
		if i > 0 {
			strings.write_string(&builder, ",")
		}
		strings.write_string(&builder, "{")
		json_field_string(&builder, "name", property.name, true)
		json_field_string(&builder, "description", property.description, false)
		strings.write_string(&builder, ",\"tags\":")
		json_write_strings(&builder, property.tags)
		strings.write_string(&builder, "}")
	}
	strings.write_string(&builder, "]}")
	return strings.to_string(builder)
}

tags_json :: proc(properties: []Property_Case) -> string {
	tags := property_tags(properties)
	defer destroy_property_tags(&tags)

	builder: strings.Builder
	strings.builder_init(&builder)

	strings.write_string(&builder, "{\"tool\":\"pbt\",\"schema_version\":1,\"tags\":[")
	for tag, i in tags {
		if i > 0 {
			strings.write_string(&builder, ",")
		}
		strings.write_string(&builder, "{")
		json_field_string(&builder, "name", tag.name, true)
		json_field_int(&builder, "count", tag.count, false)
		strings.write_string(&builder, ",\"properties\":")
		json_write_strings(&builder, tag.properties[:])
		strings.write_string(&builder, "}")
	}
	strings.write_string(&builder, "]}")
	return strings.to_string(builder)
}

parse_replay :: proc(args: []string, allocator := context.allocator) -> (Replay, bool) {
	seed: u64
	choices_text := ""

	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "--replay-seed":
			if i + 1 < len(args) {
				if value, ok := strconv.parse_uint(args[i + 1], 10); ok {
					seed = u64(value)
				}
				i += 1
			}
		case "--replay-choices":
			if i + 1 < len(args) {
				choices_text = args[i + 1]
				i += 1
			}
		}
	}

	if seed == 0 || choices_text == "" {
		return {}, false
	}

	return Replay {
		seed = seed,
		choices = parse_u64_list(choices_text, allocator),
	}, true
}

destroy_replay :: proc(replay: ^Replay) {
	delete(replay.choices)
}

parse_u64_list :: proc(text: string, allocator := context.allocator) -> [dynamic]u64 {
	values := make([dynamic]u64, allocator)
	start := 0
	for i := 0; i <= len(text); i += 1 {
		if i == len(text) || text[i] == ',' {
			part := strings.trim_space(text[start:i])
			if part != "" {
				if value, ok := strconv.parse_uint(part, 10); ok {
					append(&values, u64(value))
				}
			}
			start = i + 1
		}
	}
	return values
}
