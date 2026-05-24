package pbt

import "core:strconv"
import "core:strings"

Property_Case :: struct {
	name:     string,
	property: Property,
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
		return {status = .Error, message = "no properties registered"}
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

	return {
		name = name,
		status = .Error,
		message = "property not found",
	}
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

has_list_properties_flag :: proc(args: []string) -> bool {
	for arg in args {
		if arg == "--list-properties" {
			return true
		}
	}
	return false
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
