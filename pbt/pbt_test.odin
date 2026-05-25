package pbt

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

sum_is_commutative :: proc(t: ^T) -> Result {
	a := draw(t, int_range(-100, 100))
	b := draw(t, int_range(-100, 100))
	return equal(a + b, b + a)
}

fails_for_large_values :: proc(t: ^T) -> Result {
	value := draw(t, int_range(0, 100))
	return assert(value < 50, "value should be below 50")
}

fails_with_value_message :: proc(t: ^T) -> Result {
	value := draw(t, int_range(0, 100))
	return assert(value < 50, fmt.tprintf("value should be below 50: %d", value))
}

always_fails :: proc(t: ^T) -> Result {
	return fail("always fails")
}

same_seed_generates_same_choices :: proc(t: ^T) -> Result {
	a := draw(t, int_range(0, 1000))
	b := draw(t, int_range(0, 1000))
	return assert(a != b || a == b, "unreachable")
}

collections_are_generated_in_case_arena :: proc(t: ^T) -> Result {
	values := draw(t, array(int_range(0, 10), 1, 10))
	name := draw(t, string_ascii(1, 10))
	token := draw(t, string_alphabet("abc123", 1, 10))
	maybe_id := draw(t, optional(u64_range(1, 10)))

	return assert(len(values) >= 1 && len(name) >= 1 && len(token) >= 1 && (!maybe_id.ok || maybe_id.value >= 1), "expected generated collection values")
}

double_int :: proc(value: int) -> int {
	return value * 2
}

string_with_length :: proc(length: int) -> Gen(String_Alphabet_Input, string) {
	return string_alphabet("xy", length, length)
}

int_array_with_size :: proc(size: int) -> Gen(Array_Input(Int_Range_Input, int), []int) {
	return array(int_range(0, 1), size, size)
}

half_size :: proc(size: int) -> int {
	return size / 2
}

is_even :: proc(value: int) -> bool {
	return value % 2 == 0
}

Leaf_Count_Input :: struct {}

leaf_count_gen :: proc() -> Gen(Leaf_Count_Input, int) {
	return {
		input = {},
		produce = leaf_count_produce,
	}
}

leaf_count_produce :: proc(t: ^T, _: Leaf_Count_Input) -> int {
	if t.size <= 1 || draw(t, boolean()) {
		return 1
	}

	previous := t.size
	t.size = previous / 2
	left := draw(t, lazy(leaf_count_gen))
	right := draw(t, lazy(leaf_count_gen))
	t.size = previous
	return left + right
}

Color :: enum {
	Red,
	Green,
	Blue,
}

Credentials :: struct {
	name:    string,
	retries: int,
	active:  bool,
}

credentials_from :: proc(name: string, retries: int, active: bool) -> Credentials {
	return {name = name, retries = retries, active = active}
}

Name_Length :: struct {
	name:   string,
	length: int,
}

name_length_from :: proc(name: string, length: int) -> Name_Length {
	return {name = name, length = length}
}

combinators_generate_domain_values :: proc(t: ^T) -> Result {
	even := draw(t, map_gen(int_range(0, 50), double_int))
	fixed := draw(t, bind(int_range(1, 5), string_with_length))

	return assert(even % 2 == 0 && len(fixed) >= 1 && len(fixed) <= 5, "expected combinator-generated values")
}

generator_catalog_values :: proc(t: ^T) -> Result {
	colors := [?]string{"red", "green", "blue"}
	color := draw(t, elements(colors[:]))
	enum_color := draw(t, enum_range(Color.Red, Color.Blue))
	fixed := draw(t, constant(42))
	raw_byte := draw(t, byte_range(10, 20))
	payload_bytes := draw(t, byte_array(0, 6, 1, 3))
	non_empty_payload := draw(t, non_empty_byte_array(6, 1, 3))
	token_hex := draw(t, hex_string(1, 4))
	upper_hex := draw(t, non_empty_hex_string(4, true))
	uuid := draw(t, uuid_v4_ascii())
	upper_uuid := draw(t, uuid_v4_ascii(true))
	email := draw(t, email_ascii(1, 12, 1, 8))
	birth_date := draw(t, date_ymd_ascii(1990, 2020))
	identifier := draw(t, identifier_ascii(1, 8))
	path_segment := draw(t, path_segment_ascii(1, 8))
	cli_arg := draw(t, cli_arg_ascii(1, 8))
	cli_flag := draw(t, cli_flag_ascii(8))
	cli_command := draw(t, process_command_ascii("target-cli", 0, 3, 8))
	method := draw(t, http_method())
	status_code := draw(t, http_status_code())
	header_name := draw(t, http_header_name_ascii(1, 12))
	request := draw(t, http_request_ascii("http://example.test/api", 3, 8, 3, 8))
	body_schema := [?]JSON_Field_ASCII {
		json_string_field_ascii("sku", 8),
		json_int_field_ascii("quantity", 1, 10),
	}
	body_request := draw(t, http_request_body_ascii("http://example.test/api", json_object_schema_ascii(body_schema[:]), 3, 8))
	url_path := draw(t, url_path_ascii(1, 3, 1, 6))
	query_value := draw(t, query_component_ascii(0, 8))
	query_key := draw(t, non_empty_query_component_ascii(8))
	json_name := draw(t, json_string_literal_ascii(0, 8))
	json_flag := draw(t, json_bool_literal())
	json_count := draw(t, json_int_literal(-20, 20))
	json_body := draw(t, json_object_ascii(0, 3, 8, 8))
	json_fields := [?]string{"sku", "quantity", "active"}
	json_schema_body := draw(t, json_object_fields_ascii(json_fields[:], 8))
	json_subset_body := draw(t, json_object_field_subset_ascii(json_fields[:], 1, 2, 8))
	status_values := [?]string{"draft", "active", "archived"}
	json_typed_fields := [?]JSON_Field_ASCII {
		json_uuid_v4_field_ascii("id"),
		json_string_field_ascii("sku", 8),
		json_email_field_ascii("owner", 1, 12, 1, 8),
		json_string_enum_field_ascii("status", status_values[:]),
		json_int_field_ascii("quantity", 1, 99),
		json_bool_field_ascii("active"),
		json_date_ymd_field_ascii("born_on", 1990, 2020),
		json_null_field_ascii("deleted_at"),
	}
	json_typed_body := draw(t, json_object_schema_ascii(json_typed_fields[:]))
	json_typed_subset_body := draw(t, json_object_schema_subset_ascii(json_typed_fields[:], 1, 3))
	json_items := draw(t, json_array_ascii(0, 4, 8))
	json_typed_items := draw(t, json_array_of_ascii(json_object_schema_ascii(json_typed_fields[:]), 1, 3))
	int_pair := draw(t, pair(int_range(1, 3), string_alphabet("q", 1, 3)))
	table := draw(t, dict(string_alphabet("ab", 1, 2), int_range(0, 10), 0, 4))
	unique_values := draw(t, unique_array(int_range(0, 20), 0, 8))
	float := draw(t, f64_range(-1.0, 1.0))
	sized_values := draw(t, sized(int_array_with_size))
	resized_values := draw(t, resize(array(int_range(0, 1), 0), 3))
	clamped_values := draw(t, clamp_size(array(int_range(0, 1), 0), 0, 3))
	scaled_values := draw(t, scale(array(int_range(0, 1), 0), half_size))
	smaller_values := draw(t, smaller(array(int_range(0, 1), 0)))
	filtered := draw(t, such_that(int_range(0, 10), is_even))
	non_empty_values := draw(t, non_empty_array(int_range(0, 10), 8))
	non_empty_ascii := draw(t, non_empty_string_ascii(8))
	non_empty_token := draw(t, non_empty_string_alphabet("abc", 8))
	int_triple := draw(t, triple(int_range(1, 3), boolean(), string_alphabet("z", 1, 3)))
	int_tuple4 := draw(t, tuple4(int_range(1, 3), boolean(), string_alphabet("x", 1, 3), u64_range(10, 20)))
	int_tuple5 := draw(t, tuple5(int_range(1, 3), boolean(), string_alphabet("y", 1, 3), u64_range(10, 20), f64_range(0, 1)))
	name_length := draw(t, map2(string_alphabet("ab", 1, 4), int_range(1, 4), name_length_from))
	credentials := draw(t, map3(string_alphabet("cd", 1, 4), int_range(0, 3), boolean(), credentials_from))
	recursive_leaf_count := draw(t, leaf_count_gen())

	return assert(
		(color == "red" || color == "green" || color == "blue") &&
		enum_color >= Color.Red && enum_color <= Color.Blue &&
		fixed == 42 &&
		raw_byte >= 10 && raw_byte <= 20 &&
		len(payload_bytes) <= 6 &&
		bytes_in_range(payload_bytes, 1, 3) &&
		len(non_empty_payload) >= 1 && len(non_empty_payload) <= 6 &&
		bytes_in_range(non_empty_payload, 1, 3) &&
		len(token_hex) >= 2 && len(token_hex) <= 8 && len(token_hex) % 2 == 0 &&
		hex_is_lower(token_hex) &&
		len(upper_hex) >= 2 && len(upper_hex) <= 8 && len(upper_hex) % 2 == 0 &&
		hex_is_upper(upper_hex) &&
		uuid_v4_is_ascii(uuid, false) &&
		uuid_v4_is_ascii(upper_uuid, true) &&
		email_is_ascii(email) &&
		date_ymd_is_valid(birth_date, 1990, 2020) &&
		len(identifier) >= 1 && len(identifier) <= 8 &&
		identifier_is_ascii(identifier) &&
		len(path_segment) >= 1 && len(path_segment) <= 8 &&
		path_segment_is_ascii(path_segment) &&
		cli_arg_is_ascii(cli_arg) &&
		cli_flag_is_ascii(cli_flag) &&
		process_command_is_ascii(cli_command) &&
		http_method_is_common(method) &&
		status_code >= 100 && status_code <= 599 &&
		len(header_name) >= 1 && len(header_name) <= 12 &&
		http_header_name_is_ascii(header_name) &&
		http_request_is_ascii(request) &&
		http_body_request_is_ascii(body_request) &&
		url_path_is_ascii(url_path) &&
		query_component_is_ascii(query_value) &&
		len(query_key) >= 1 && len(query_key) <= 8 &&
		query_component_is_ascii(query_key) &&
		json_string_literal_is_safe_ascii(json_name) &&
		(json_flag == "true" || json_flag == "false") &&
		json_int_literal_is_decimal(json_count) &&
		json_object_is_simple_ascii(json_body) &&
		json_object_has_fields(json_schema_body, json_fields[:]) &&
		json_object_field_count(json_subset_body) >= 1 &&
		json_object_field_count(json_subset_body) <= 2 &&
		json_object_schema_is_typed(json_typed_body) &&
		json_object_field_count(json_typed_subset_body) >= 1 &&
		json_object_field_count(json_typed_subset_body) <= 3 &&
		json_object_is_simple_ascii(json_typed_subset_body) &&
		json_array_is_simple_ascii(json_items) &&
		json_array_of_schema_is_typed(json_typed_items) &&
		int_pair.first >= 1 && int_pair.first <= 3 &&
		len(int_pair.second) >= 1 && len(int_pair.second) <= 3 &&
		len(table) <= 4 &&
		len(unique_values) <= 8 &&
		values_are_unique(unique_values) &&
		float >= -1.0 && float <= 1.0 &&
		len(sized_values) == t.size &&
		len(resized_values) <= 3 &&
		len(clamped_values) <= 3 &&
		len(scaled_values) <= 50 &&
		len(smaller_values) <= 50 &&
		filtered % 2 == 0 &&
		len(non_empty_values) >= 1 && len(non_empty_values) <= 8 &&
		len(non_empty_ascii) >= 1 && len(non_empty_ascii) <= 8 &&
		len(non_empty_token) >= 1 && len(non_empty_token) <= 8 &&
		int_triple.first >= 1 && int_triple.first <= 3 &&
		len(int_triple.third) >= 1 && len(int_triple.third) <= 3 &&
			int_tuple4.first >= 1 && int_tuple4.first <= 3 &&
			len(int_tuple4.third) >= 1 && len(int_tuple4.third) <= 3 &&
			int_tuple4.fourth >= 10 && int_tuple4.fourth <= 20 &&
			int_tuple5.first >= 1 && int_tuple5.first <= 3 &&
			len(int_tuple5.third) >= 1 && len(int_tuple5.third) <= 3 &&
			int_tuple5.fourth >= 10 && int_tuple5.fourth <= 20 &&
			int_tuple5.fifth >= 0 && int_tuple5.fifth <= 1 &&
			len(name_length.name) >= 1 && len(name_length.name) <= 4 &&
			name_length.length >= 1 && name_length.length <= 4 &&
			len(credentials.name) >= 1 && len(credentials.name) <= 4 &&
			credentials.retries >= 0 && credentials.retries <= 3 &&
			(credentials.active || !credentials.active) &&
			recursive_leaf_count >= 1 && recursive_leaf_count <= 128,
		"expected generator catalog values",
	)
}

bytes_in_range :: proc(values: []byte, min, max: byte) -> bool {
	for value in values {
		if value < min || value > max {
			return false
		}
	}
	return true
}

hex_is_lower :: proc(value: string) -> bool {
	for ch in value {
		if !((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) {
			return false
		}
	}
	return true
}

hex_is_upper :: proc(value: string) -> bool {
	for ch in value {
		if !((ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'F')) {
			return false
		}
	}
	return true
}

identifier_is_ascii :: proc(value: string) -> bool {
	for ch, i in value {
		if i == 0 {
			if !((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_') {
				return false
			}
			continue
		}
		if !((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_') {
			return false
		}
	}
	return len(value) > 0
}

path_segment_is_ascii :: proc(value: string) -> bool {
	for ch, i in value {
		if ch == '/' || ch == '\\' {
			return false
		}
		if i == 0 {
			if !((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-') {
				return false
			}
			continue
		}
		if !((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-' || ch == '.') {
			return false
		}
	}
	return len(value) > 0
}

cli_arg_is_ascii :: proc(value: string) -> bool {
	for ch in value {
		if !((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-' || ch == '.') {
			return false
		}
	}
	return len(value) > 0
}

cli_flag_is_ascii :: proc(value: string) -> bool {
	return strings.has_prefix(value, "--") && cli_arg_is_ascii(value[2:])
}

process_command_is_ascii :: proc(command: []string) -> bool {
	if len(command) == 0 || command[0] != "target-cli" || len(command) > 4 {
		return false
	}
	for arg in command[1:] {
		if !cli_arg_is_ascii(arg) {
			return false
		}
	}
	return true
}

http_method_is_common :: proc(value: string) -> bool {
	switch value {
	case "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS":
		return true
	}
	return false
}

http_header_name_is_ascii :: proc(value: string) -> bool {
	for ch in value {
		if !((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '!' || ch == '#' || ch == '$' || ch == '%' || ch == '&' || ch == '\'' || ch == '*' || ch == '+' || ch == '-' || ch == '.' || ch == '^' || ch == '_' || ch == '`' || ch == '|' || ch == '~') {
			return false
		}
	}
	return len(value) > 0
}

http_request_is_ascii :: proc(request: Http_Request) -> bool {
	if !http_method_is_common(request.method) || !strings.has_prefix(request.url, "http://example.test/api") {
		return false
	}
	if request.timeout_ms != 1_000 || request.max_body_bytes != HTTP_DEFAULT_MAX_BODY_BYTES {
		return false
	}
	if http_method_supports_generated_body(request.method) {
		if len(request.headers) != 2 || !json_object_is_simple_ascii(request.body) {
			return false
		}
	} else if len(request.headers) != 0 || len(request.body) != 0 {
		return false
	}
	for ch in request.url {
		if ch < 0x20 || ch > 0x7e || ch == '\\' {
			return false
		}
	}
	return true
}

http_body_request_is_ascii :: proc(request: Http_Request) -> bool {
	if !http_method_supports_generated_body(request.method) || !strings.has_prefix(request.url, "http://example.test/api") {
		return false
	}
	if request.timeout_ms != 1_000 || request.max_body_bytes != HTTP_DEFAULT_MAX_BODY_BYTES {
		return false
	}
	if len(request.headers) != 2 || !json_object_is_simple_ascii(request.body) {
		return false
	}
	if !strings.contains(request.body, "\"sku\":\"") || !strings.contains(request.body, "\"quantity\":") || strings.contains(request.body, "\"quantity\":\"") {
		return false
	}
	for ch in request.url {
		if ch < 0x20 || ch > 0x7e || ch == '\\' {
			return false
		}
	}
	return true
}

url_path_is_ascii :: proc(value: string) -> bool {
	if len(value) == 0 || value[0] != '/' {
		return false
	}
	for ch in value[1:] {
		if ch == '\\' || ch == '?' || ch == '#' {
			return false
		}
		if !((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-' || ch == '.' || ch == '/') {
			return false
		}
	}
	return true
}

query_component_is_ascii :: proc(value: string) -> bool {
	for ch in value {
		if !((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '.' || ch == '_' || ch == '~') {
			return false
		}
	}
	return true
}

json_string_literal_is_safe_ascii :: proc(value: string) -> bool {
	if len(value) < 2 || value[0] != '"' || value[len(value) - 1] != '"' {
		return false
	}
	for ch in value[1:len(value) - 1] {
		if ch == '"' || ch == '\\' || ch < 0x20 {
			return false
		}
	}
	return true
}

json_int_literal_is_decimal :: proc(value: string) -> bool {
	if len(value) == 0 {
		return false
	}

	start := 0
	if value[0] == '-' {
		if len(value) == 1 {
			return false
		}
		start = 1
	}
	for ch in value[start:] {
		if ch < '0' || ch > '9' {
			return false
		}
	}
	return true
}

json_object_is_simple_ascii :: proc(value: string) -> bool {
	if len(value) < 2 || value[0] != '{' || value[len(value) - 1] != '}' {
		return false
	}

	for ch in value {
		if !json_simple_ascii_char_is_allowed(ch) && ch != '{' && ch != '}' && ch != ':' {
			return false
		}
	}
	return true
}

json_object_has_fields :: proc(value: string, fields: []string) -> bool {
	if !json_object_is_simple_ascii(value) {
		return false
	}
	for field in fields {
		needle := fmt.tprintf("\"%s\":", field)
		if !strings.contains(value, needle) {
			return false
		}
	}
	return true
}

json_object_field_count :: proc(value: string) -> int {
	if !json_object_is_simple_ascii(value) || value == "{}" {
		return 0
	}

	count := 1
	for ch in value {
		if ch == ',' {
			count += 1
		}
	}
	return count
}

json_object_schema_is_typed :: proc(value: string) -> bool {
	if !json_object_is_simple_ascii(value) {
		return false
	}
	return strings.contains(value, "\"id\":\"") &&
		strings.contains(value, "\"sku\":\"") &&
		strings.contains(value, "\"owner\":\"") &&
		(strings.contains(value, "\"status\":\"draft\"") || strings.contains(value, "\"status\":\"active\"") || strings.contains(value, "\"status\":\"archived\"")) &&
		strings.contains(value, "\"quantity\":") &&
		!strings.contains(value, "\"quantity\":\"") &&
		(strings.contains(value, "\"active\":true") || strings.contains(value, "\"active\":false")) &&
		strings.contains(value, "\"born_on\":\"") &&
		strings.contains(value, "\"deleted_at\":null")
}

json_array_is_simple_ascii :: proc(value: string) -> bool {
	if len(value) < 2 || value[0] != '[' || value[len(value) - 1] != ']' {
		return false
	}

	for ch in value {
		if !json_simple_ascii_char_is_allowed(ch) && ch != '[' && ch != ']' {
			return false
		}
	}
	return true
}

json_array_of_schema_is_typed :: proc(value: string) -> bool {
	if len(value) < 2 || value[0] != '[' || value[len(value) - 1] != ']' {
		return false
	}
	for ch in value {
		if !json_simple_ascii_char_is_allowed(ch) && ch != '[' && ch != ']' && ch != '{' && ch != '}' && ch != ':' {
			return false
		}
	}
	return strings.contains(value, "\"sku\":\"") &&
		strings.contains(value, "\"id\":\"") &&
		strings.contains(value, "\"owner\":\"") &&
		(strings.contains(value, "\"status\":\"draft\"") || strings.contains(value, "\"status\":\"active\"") || strings.contains(value, "\"status\":\"archived\"")) &&
		strings.contains(value, "\"quantity\":") &&
		!strings.contains(value, "\"quantity\":\"") &&
		strings.contains(value, "\"born_on\":\"") &&
		strings.contains(value, "\"deleted_at\":null")
}

json_simple_ascii_char_is_allowed :: proc(ch: rune) -> bool {
	if ch < 0x20 {
		return false
	}
	return (ch >= 'A' && ch <= 'Z') ||
		(ch >= 'a' && ch <= 'z') ||
		(ch >= '0' && ch <= '9') ||
		ch == '_' || ch == '-' || ch == '.' || ch == ' ' ||
		ch == '"' || ch == ',' || ch == '@'
}

uuid_v4_is_ascii :: proc(value: string, uppercase: bool) -> bool {
	if len(value) != 36 {
		return false
	}
	for ch, i in value {
		switch i {
		case 8, 13, 18, 23:
			if ch != '-' {
				return false
			}
		case 14:
			if ch != '4' {
				return false
			}
		case 19:
			if uppercase {
				if !(ch >= '8' && ch <= '9' || ch >= 'A' && ch <= 'B') {
					return false
				}
			} else if !(ch >= '8' && ch <= '9' || ch >= 'a' && ch <= 'b') {
				return false
			}
		case:
			if uppercase {
				if !((ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'F')) {
					return false
				}
			} else if !((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) {
				return false
			}
		}
	}
	return true
}

email_is_ascii :: proc(value: string) -> bool {
	at := strings.index(value, "@")
	if at <= 0 || !strings.has_suffix(value, ".test") {
		return false
	}
	domain_len := len(value) - at - len("@.test")
	if domain_len <= 0 {
		return false
	}
	for ch, i in value {
		if i < at {
			if !((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '.' || ch == '_' || ch == '-') {
				return false
			}
		} else if i == at {
			if ch != '@' {
				return false
			}
		} else if i < len(value) - len(".test") {
			if !((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-') {
				return false
			}
		}
	}
	return true
}

date_ymd_is_valid :: proc(value: string, min_year, max_year: int) -> bool {
	if len(value) != 10 || value[4] != '-' || value[7] != '-' {
		return false
	}
	year, ok_year := parse_fixed_digits(value[0:4])
	month, ok_month := parse_fixed_digits(value[5:7])
	day, ok_day := parse_fixed_digits(value[8:10])
	if !ok_year || !ok_month || !ok_day {
		return false
	}
	if year < min_year || year > max_year || month < 1 || month > 12 {
		return false
	}
	return day >= 1 && day <= days_in_month(year, month)
}

parse_fixed_digits :: proc(value: string) -> (int, bool) {
	result := 0
	for ch in value {
		if ch < '0' || ch > '9' {
			return 0, false
		}
		result = result * 10 + int(ch - '0')
	}
	return result, true
}

values_are_unique :: proc(values: []int) -> bool {
	for value, i in values {
		for j in 0 ..< i {
			if values[j] == value {
				return false
			}
		}
	}
	return true
}

coverage_property :: proc(t: ^T) -> Result {
	value := draw(t, int_range(0, 9))
	classify(t, value < 5, "low")
	classify(t, value >= 5, "high")
	cover(t, true, 100.0, "all")
	return pass()
}

coverage_failure_property :: proc(t: ^T) -> Result {
	cover(t, false, 1.0, "impossible")
	return pass()
}

coverage_extra_property :: proc(t: ^T) -> Result {
	value := draw(t, int_range(0, 2))
	cover(t, value == 2, 30.0, "two")
	return pass()
}

discard_one_property :: proc(t: ^T) -> Result {
	value := draw(t, int_range(0, 1))
	if value == 1 {
		return discard("one")
	}
	return pass()
}

counterexample_property :: proc(t: ^T) -> Result {
	value := draw(t, constant(12))
	return counterexample("while checking invoice total", equal(value, 13))
}

transient_event_property :: proc(t: ^T) -> Result {
	record_event_transient_static_kind_status(t, "stateful", fmt.tprintf("step %d inc", 0), "ok", fmt.tprintf("state=%d value=%d next=%d", 0, 1, 1))
	return pass()
}

sequence_failure_property :: proc(t: ^T) -> Result {
	length := draw(t, int_range(0, 3))
	for i in 0 ..< length {
		value := draw(t, int_range(0, 10))
		if value >= 7 {
			return fail("sequence contains large value")
		}
	}
	return pass()
}

payload_irrelevant_failure_property :: proc(t: ^T) -> Result {
	marker := draw(t, int_range(0, 1))
	_ = draw(t, int_range(0, 10))
	_ = draw(t, int_range(0, 10))
	return assert(marker == 0, "marker triggers failure")
}

optional_irrelevant_failure_property :: proc(t: ^T) -> Result {
	marker := draw(t, int_range(0, 1))
	_ = draw(t, optional(int_range(0, 9)))
	return assert(marker == 0, "marker triggers failure")
}

marked_command_failure_property :: proc(t: ^T) -> Result {
	prefix := choice(t, 10)
	for _ in 0 ..< 3 {
		mark_choice_boundary(t)
		command := choice(t, 10)
		if prefix == 3 && command == 7 {
			return fail("bad marked command")
		}
	}
	return pass()
}

fixed_array_failure_property :: proc(t: ^T) -> Result {
	values := draw(t, array(int_range(0, 10), 3, 3))
	if values[0] == 3 && (values[1] == 7 || values[2] == 7) {
		return fail("bad fixed array")
	}
	return pass()
}

array_suffix_failure_property :: proc(t: ^T) -> Result {
	values := draw(t, array(int_range(0, 9), 0, 4))
	if len(values) >= 2 && values[1] == 7 {
		return fail("array prefix contains bad value")
	}
	return pass()
}

string_suffix_failure_property :: proc(t: ^T) -> Result {
	value := draw(t, string_alphabet("az", 0, 4))
	if len(value) >= 2 && value[1] == 'z' {
		return fail("string prefix contains bad byte")
	}
	return pass()
}

array_contains_failure_property :: proc(t: ^T) -> Result {
	values := draw(t, array(int_range(0, 9), 0, 4))
	for value in values {
		if value == 7 {
			return fail("array contains bad value")
		}
	}
	return pass()
}

unique_array_contains_failure_property :: proc(t: ^T) -> Result {
	values := draw(t, unique_array(int_range(0, 9), 0, 4))
	for value in values {
		if value == 7 {
			return fail("unique array contains bad value")
		}
	}
	return pass()
}

array_middle_irrelevant_failure_property :: proc(t: ^T) -> Result {
	values := draw(t, array(int_range(0, 9), 0, 4))
	if len(values) >= 2 && values[0] == 1 && values[len(values) - 1] == 7 {
		return fail("array boundary values expose bug")
	}
	return pass()
}

triple_middle_irrelevant_failure_property :: proc(t: ^T) -> Result {
	values := draw(t, triple(int_range(0, 9), array(int_range(0, 9), 2, 2), int_range(0, 9)))
	if values.first == 3 && values.third == 7 {
		return fail("triple boundary values expose bug")
	}
	return pass()
}

one_of_payload_irrelevant_failure_property :: proc(t: ^T) -> Result {
	low := array(int_range(0, 9), 2, 2)
	high := array(int_range(10, 19), 2, 2)
	branches := [?]Gen(Array_Input(Int_Range_Input, int), []int){low, high}
	values := draw(t, one_of(branches[:]))
	marker := draw(t, int_range(0, 9))
	if len(values) > 0 && values[0] >= 10 && marker == 7 {
		return fail("one_of branch and marker expose bug")
	}
	return pass()
}

string_contains_failure_property :: proc(t: ^T) -> Result {
	value := draw(t, string_alphabet("az", 0, 4))
	for ch in value {
		if ch == 'z' {
			return fail("string contains bad byte")
		}
	}
	return pass()
}

domain_encoded_number :: proc(t: ^T) -> int {
	start := choice_cursor(t)
	encoding := choice(t, 2)
	if encoding == 0 {
		return int(choice(t, 10))
	}

	tens := choice(t, 10)
	ones := choice(t, 10)
	value := int(tens * 10 + ones)
	if value < 10 {
		replacement := [?]u64{0, u64(value)}
		record_choice_shrink_hint(t, start, choice_cursor(t) - start, replacement[:])
	}
	return value
}

domain_encoded_failure_property :: proc(t: ^T) -> Result {
	value := domain_encoded_number(t)
	return assert(value != 7, "domain value should not be seven")
}

json_subset_field_failure_property :: proc(t: ^T) -> Result {
	fields := [?]string{"a", "b", "c"}
	body := draw(t, json_object_field_subset_ascii(fields[:], 1, 3, 0))
	return assert(!strings.contains(body, "\"b\":"), "json subset contains b")
}

json_schema_subset_field_failure_property :: proc(t: ^T) -> Result {
	fields := [?]JSON_Field_ASCII {
		json_null_field_ascii("a"),
		json_null_field_ascii("b"),
		json_null_field_ascii("c"),
	}
	body := draw(t, json_object_schema_subset_ascii(fields[:], 1, 3))
	return assert(!strings.contains(body, "\"b\":"), "json schema subset contains b")
}

json_array_of_failure_property :: proc(t: ^T) -> Result {
	body := draw(t, json_array_of_ascii(json_int_literal(0, 10), 1, 3))
	return assert(!strings.contains(body, "7"), "json array contains seven")
}

dict_entry_failure_property :: proc(t: ^T) -> Result {
	values := draw(t, dict(int_range(0, 9), int_range(0, 9), 0, 3))
	_, found := values[7]
	return assert(!found, "dict contains bad key")
}

labelled_failure_property :: proc(t: ^T) -> Result {
	marker := choice(t, 2)
	_ = choice(t, 10)
	if marker == 1 {
		label(t, "interesting")
	}
	return fail("labelled failure")
}

required_shrink_label_failure_property :: proc(t: ^T) -> Result {
	marker := choice(t, 2)
	noise := choice(t, 10)
	if marker == 1 {
		require_shrink_label(t, "interesting")
	}
	if noise == 9 {
		label(t, "noise")
	}
	return fail("required shrink label failure")
}

bad_command_initial :: proc(t: ^T, target: rawptr) -> int {
	return 0
}

bad_command_draw :: proc(t: ^T, state: int) -> int {
	return draw(t, int_range(0, 9))
}

bad_command_run :: proc(t: ^T, target: rawptr, state: int, command: int) -> int {
	return command
}

bad_command_next :: proc(state: int, command: int, value: int) -> int {
	return state + 1
}

bad_command_postcondition :: proc(state: int, command: int, value: int) -> Result {
	if value == 7 {
		return fail("bad command")
	}
	return pass()
}

bad_command_stateful_property :: proc(t: ^T) -> Result {
	model := State_Model(int, int, int) {
		initial = bad_command_initial,
		command = bad_command_draw,
		run = bad_command_run,
		next_state = bad_command_next,
		postcondition = bad_command_postcondition,
	}
	return run_commands(t, model, {min_len = 0, max_len = 3})
}

records_structured_event :: proc(t: ^T) -> Result {
	record_event(t, "process", "cart add", "ok", "exit=0")
	note(t, "about to fail")
	label(t, "forced")
	return fail("forced failure")
}

Counter_Command :: enum {
	Inc,
	Dec,
	Reset,
}

Counter_Target :: struct {
	value: int,
}

counter_initial :: proc(t: ^T, target: rawptr) -> int {
	return 0
}

counter_command :: proc(t: ^T, state: int) -> Counter_Command {
	index := draw(t, int_range(0, 2))
	return Counter_Command(index)
}

counter_command_inc_then_reset :: proc(t: ^T, state: int) -> Counter_Command {
	if state == 0 {
		return .Inc
	}
	return .Reset
}

counter_precondition :: proc(state: int, command: Counter_Command) -> bool {
	if command == .Dec {
		return state > 0
	}
	return true
}

counter_run_buggy :: proc(t: ^T, target: rawptr, state: int, command: Counter_Command) -> int {
	counter := cast(^Counter_Target)target
	switch command {
	case .Inc:
		counter.value += 1
	case .Dec:
		counter.value -= 1
	case .Reset:
		counter.value = 1
	}
	return counter.value
}

counter_next_state :: proc(state: int, command: Counter_Command, value: int) -> int {
	switch command {
	case .Inc:
		return state + 1
	case .Dec:
		return state - 1
	case .Reset:
		return 0
	}
	return state
}

counter_postcondition :: proc(state: int, command: Counter_Command, value: int) -> Result {
	expected := counter_next_state(state, command, value)
	return assert(value == expected, "counter target diverged from model")
}

counter_invariant :: proc(t: ^T, state: int) -> Result {
	return assert(state >= 0, "model counter should not be negative")
}

counter_command_name :: proc(command: Counter_Command) -> string {
	switch command {
	case .Inc:
		return "inc"
	case .Dec:
		return "dec"
	case .Reset:
		return "reset"
	}
	return "unknown"
}

counter_state_detail :: proc(state: int) -> string {
	return fmt.tprintf("%d", state)
}

counter_value_detail :: proc(value: int) -> string {
	return fmt.tprintf("%d", value)
}

counter_stateful_property :: proc(t: ^T) -> Result {
	target := Counter_Target{}
	model := State_Model(int, Counter_Command, int) {
		target = &target,
		initial = counter_initial,
		command = counter_command,
		precondition = counter_precondition,
		run = counter_run_buggy,
		next_state = counter_next_state,
		postcondition = counter_postcondition,
		invariant = counter_invariant,
		command_name = counter_command_name,
		state_detail = counter_state_detail,
		value_detail = counter_value_detail,
	}
	return run_commands(t, model, {min_len = 1, max_len = 20})
}

counter_stateful_skip_success_property :: proc(t: ^T) -> Result {
	target := Counter_Target{}
	model := State_Model(int, Counter_Command, int) {
		target = &target,
		initial = counter_initial,
		command = counter_command_inc_then_reset,
		precondition = counter_precondition,
		run = counter_run_buggy,
		next_state = counter_next_state,
		postcondition = counter_postcondition,
		invariant = counter_invariant,
		command_name = counter_command_name,
		state_detail = counter_state_detail,
		value_detail = counter_value_detail,
	}
	return run_commands(t, model, {min_len = 2, max_len = 2, skip_success_events = true})
}

counter_run_correct :: proc(t: ^T, target: rawptr, state: int, command: Counter_Command) -> int {
	counter := cast(^Counter_Target)target
	switch command {
	case .Inc:
		counter.value += 1
	case .Dec:
		counter.value -= 1
	case .Reset:
		counter.value = 0
	}
	return counter.value
}

counter_stateful_compact_success_property :: proc(t: ^T) -> Result {
	target := Counter_Target{}
	model := State_Model(int, Counter_Command, int) {
		target = &target,
		initial = counter_initial,
		command = counter_command,
		precondition = counter_precondition,
		run = counter_run_correct,
		next_state = counter_next_state,
		postcondition = counter_postcondition,
		invariant = counter_invariant,
		command_name = counter_command_name,
		state_detail = counter_state_detail,
		value_detail = counter_value_detail,
	}
	return run_commands(t, model, {min_len = 2, max_len = 2, compact_success_events = true})
}

counter_stateful_limited_success_property :: proc(t: ^T) -> Result {
	target := Counter_Target{}
	model := State_Model(int, Counter_Command, int) {
		target = &target,
		initial = counter_initial,
		command = counter_command,
		precondition = counter_precondition,
		run = counter_run_correct,
		next_state = counter_next_state,
		postcondition = counter_postcondition,
		invariant = counter_invariant,
		command_name = counter_command_name,
		state_detail = counter_state_detail,
		value_detail = counter_value_detail,
	}
	return run_commands(t, model, {min_len = 3, max_len = 3, max_success_events = 1})
}

counter_stateful_limited_success_failure_property :: proc(t: ^T) -> Result {
	target := Counter_Target{}
	model := State_Model(int, Counter_Command, int) {
		target = &target,
		initial = counter_initial,
		command = counter_command_inc_then_reset,
		precondition = counter_precondition,
		run = counter_run_buggy,
		next_state = counter_next_state,
		postcondition = counter_postcondition,
		invariant = counter_invariant,
		command_name = counter_command_name,
		state_detail = counter_state_detail,
		value_detail = counter_value_detail,
	}
	return run_commands(t, model, {min_len = 2, max_len = 2, max_success_events = 1})
}

process_property :: proc(t: ^T) -> Result {
	command := [?]string{"/bin/sh", "-c", "printf ok"}
	result := process_run(t, command[:])
	if !result.success {
		return fail("process failed")
	}
	return equal(result.stdout, "ok")
}

protocol_property :: proc(t: ^T) -> Result {
	payload := draw(t, string_ascii(1, 12))
	command := [?]string{"/bin/cat"}
	result := protocol_call(t, command[:], payload)
	if !result.success {
		return fail("protocol process failed")
	}
	return assert(result.stdout == payload, fmt.tprintf("stdout=%q payload=%q", result.stdout, payload))
}

http_property :: proc(t: ^T) -> Result {
	response := http_get(t, "file:///tmp/pbt-http-adapter-ok")
	if !response.success {
		return fail("curl-backed http request failed")
	}
	return equal(response.body, "ok")
}

@(test)
test_check_passes :: proc(t: ^testing.T) {
	result := check("sum is commutative", sum_is_commutative, {num_tests = 50, seed = 123, shrink = true})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.num_tests, 50)
}

@(test)
test_check_finds_and_shrinks_failure :: proc(t: ^testing.T) {
	result := check("large values fail", fails_for_large_values, {num_tests = 100, seed = 123})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect_value(t, result.code, "property_failed")
	testing.expect(t, len(result.replay.choices) > 0)
	testing.expect_value(t, result.replay.choices[0], u64(50))

	replayed := check_replay("large values fail", fails_for_large_values, result.replay)
	defer destroy_check_result(&replayed)

	testing.expect_value(t, replayed.status, Status.Fail)
}

@(test)
test_check_failure_message_uses_shrunk_case :: proc(t: ^testing.T) {
	result := check("large values fail", fails_with_value_message, {num_tests = 100, seed = 123, shrink = true})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect_value(t, result.replay.choices[0], u64(50))
	testing.expect_value(t, result.message, "value should be below 50: 50")
	testing.expect_value(t, result.shrunk_test.result.message, result.message)
}

@(test)
test_no_shrink_keeps_original_failure :: proc(t: ^testing.T) {
	result := check("large values fail", fails_for_large_values, {num_tests = 100, seed = 123, no_shrink = true})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect_value(t, result.replay.choices[0], u64(98))
}

@(test)
test_check_result_json_contains_replay :: proc(t: ^testing.T) {
	result := check("large values fail", fails_for_large_values, {num_tests = 100, seed = 123, shrink = true})
	defer destroy_check_result(&result)

	json := check_result_json(result)
	defer delete(json)

	testing.expect(t, strings.contains(json, "\"tool\":\"pbt\""))
	testing.expect(t, strings.contains(json, "\"schema_version\":1"))
	testing.expect(t, strings.contains(json, "\"status\":\"fail\""))
	testing.expect(t, strings.contains(json, "\"code\":\"property_failed\""))
	testing.expect(t, strings.contains(json, "\"duration_ns\""))
	testing.expect(t, strings.contains(json, "\"shrink_attempts\""))
	testing.expect(t, strings.contains(json, "\"shrink_duration_ns\""))
	testing.expect(t, strings.contains(json, "\"replay\""))
	testing.expect(t, strings.contains(json, "\"choices\""))
	testing.expect(t, strings.contains(json, "\"choices_csv\":\"50\""))
	testing.expect_value(t, check_result_exit_code(result), 1)
	testing.expect(t, result.duration_ns > 0)
	testing.expect(t, result.shrink_attempts > 0)
	testing.expect(t, result.shrink_duration_ns > 0)

	choices_csv := replay_choices_csv(result.replay)
	defer delete(choices_csv)
	testing.expect_value(t, choices_csv, "50")

	text := check_result_text(result)
	defer delete(text)
	testing.expect(t, strings.contains(text, "large values fail: fail"))
	testing.expect(t, strings.contains(text, "code: property_failed"))
	testing.expect(t, strings.contains(text, "replay: --replay-seed 123 --replay-choices 50"))
	testing.expect(t, strings.contains(text, "shrink:"))
}

@(test)
test_events_are_reported_as_json :: proc(t: ^testing.T) {
	result := check("events", records_structured_event, {num_tests = 1, seed = 1, shrink = true})
	defer destroy_check_result(&result)

	json := check_result_json(result)
	defer delete(json)

	testing.expect(t, strings.contains(json, "\"events\""))
	testing.expect(t, strings.contains(json, "\"notes\":[\"about to fail\"]"))
	testing.expect(t, strings.contains(json, "\"kind\":\"process\""))
	testing.expect(t, strings.contains(json, "\"name\":\"cart add\""))
	testing.expect(t, strings.contains(json, "\"about to fail\""))
	testing.expect(t, strings.contains(json, "\"labels\":[\"forced\"]"))

	text := check_result_text(result)
	defer delete(text)
	testing.expect(t, strings.contains(text, "notes:"))
	testing.expect(t, strings.contains(text, "  - about to fail"))
	testing.expect(t, strings.contains(text, "events:"))
	testing.expect(t, strings.contains(text, "process cart add [ok]: exit=0"))
	testing.expect(t, !strings.contains(text, "note [ok]: about to fail"))
}

@(test)
test_stateful_runner_finds_model_mismatch :: proc(t: ^testing.T) {
	result := check("counter stateful", counter_stateful_property, {num_tests = 50, seed = 5, shrink = true})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect_value(t, result.message, "counter target diverged from model")
	testing.expect(t, len(result.shrunk_test.choice_marks) > 0)
	testing.expect(t, len(result.shrunk_test.events) > 0)
	testing.expect(t, strings.contains(result.shrunk_test.events[0].name, "reset"))
	testing.expect(t, strings.contains(result.shrunk_test.events[0].detail, "state=0"))
	testing.expect(t, strings.contains(result.shrunk_test.events[0].detail, "value=1"))

	replayed := check_replay("counter stateful", counter_stateful_property, result.replay)
	defer destroy_check_result(&replayed)

	testing.expect_value(t, replayed.status, Status.Fail)
}

@(test)
test_stateful_runner_can_skip_success_events :: proc(t: ^testing.T) {
	choices := [?]u64{0}
	result := run_case(counter_stateful_skip_success_property, 1, 10, choices[:], true, true, true)
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, len(result.events), 1)
	if len(result.events) > 0 {
		testing.expect(t, strings.contains(result.events[0].name, "reset postcondition"))
		testing.expect_value(t, result.events[0].status, "fail")
	}
}

@(test)
test_stateful_runner_can_record_compact_success_events :: proc(t: ^testing.T) {
	choices := [?]u64{0, 0}
	result := run_case(counter_stateful_compact_success_property, 1, 10, choices[:], true, true, true)
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Pass)
	testing.expect_value(t, len(result.events), 2)
	if len(result.events) > 0 {
		testing.expect_value(t, result.events[0].kind, "stateful")
		testing.expect_value(t, result.events[0].name, "inc")
		testing.expect_value(t, result.events[0].status, "ok")
		testing.expect_value(t, result.events[0].detail, "")
		testing.expect(t, !event_name_owned(result.events[0]))
	}
}

@(test)
test_stateful_runner_can_limit_success_events :: proc(t: ^testing.T) {
	choices := [?]u64{0, 0, 0}
	result := run_case(counter_stateful_limited_success_property, 1, 10, choices[:], true, true, true)
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Pass)
	testing.expect_value(t, len(result.events), 1)
	if len(result.events) > 0 {
		testing.expect_value(t, result.events[0].kind, "stateful")
		testing.expect(t, strings.contains(result.events[0].name, "step 0 inc"))
		testing.expect_value(t, result.events[0].status, "ok")
	}
}

@(test)
test_stateful_success_event_limit_keeps_failure_event :: proc(t: ^testing.T) {
	choices := [?]u64{0}
	result := run_case(counter_stateful_limited_success_failure_property, 1, 10, choices[:], true, true, true)
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, len(result.events), 2)
	if len(result.events) == 2 {
		testing.expect_value(t, result.events[0].status, "ok")
		testing.expect_value(t, result.events[1].status, "fail")
		testing.expect(t, strings.contains(result.events[1].name, "reset postcondition"))
	}
}

@(test)
test_case_runner_keeps_captured_case_events_after_reuse :: proc(t: ^testing.T) {
	runner: Case_Runner
	case_runner_init(&runner)
	defer case_runner_destroy(&runner)

	first_choices := [?]u64{0, 0, 0}
	first := case_runner_run(&runner, counter_stateful_limited_success_property, 1, 10, first_choices[:], true, {
		capture_pass = true,
		capture_events = true,
	})
	defer destroy_test_case(&first)

	second_choices := [?]u64{2, 2, 2}
	second := case_runner_run(&runner, counter_stateful_limited_success_property, 2, 10, second_choices[:], true, {
		capture_pass = true,
		capture_events = true,
	})
	defer destroy_test_case(&second)

	testing.expect_value(t, first.result.status, Status.Pass)
	testing.expect_value(t, second.result.status, Status.Pass)
	testing.expect_value(t, len(first.events), 1)
	testing.expect_value(t, len(second.events), 1)
	if len(first.events) > 0 && len(second.events) > 0 {
		testing.expect(t, strings.contains(first.events[0].name, "step 0 inc"))
		testing.expect(t, strings.contains(second.events[0].name, "step 0 reset"))
	}
}

@(test)
test_case_runner_can_borrow_captured_events_and_choices :: proc(t: ^testing.T) {
	runner: Case_Runner
	case_runner_init(&runner)
	defer case_runner_destroy(&runner)

	choices := [?]u64{0, 0, 0}
	result := case_runner_run_borrowed(&runner, counter_stateful_limited_success_property, 1, 10, choices[:], true, {
		capture_pass = true,
		capture_events = true,
	})
	choices_csv := borrowed_choices_csv(result)
	defer delete(choices_csv)

	testing.expect_value(t, result.result.status, Status.Pass)
	testing.expect_value(t, result.choice_count, 3)
	testing.expect_value(t, borrowed_choice_at(result, 0), u64(0))
	testing.expect_value(t, choices_csv, "0,0,0")
	testing.expect_value(t, len(result.events), 1)
	if len(result.events) > 0 {
		testing.expect(t, strings.contains(result.events[0].name, "step 0 inc"))
		testing.expect_value(t, result.events[0].status, "ok")
	}
}

@(test)
test_case_runner_can_skip_borrowed_pass_choices :: proc(t: ^testing.T) {
	runner: Case_Runner
	case_runner_init(&runner)
	defer case_runner_destroy(&runner)

	choices := [?]u64{0, 0, 0}
	result := case_runner_run_borrowed(&runner, counter_stateful_limited_success_property, 1, 10, choices[:], true, {
		capture_pass = true,
		capture_events = true,
		skip_choices = true,
	})

	testing.expect_value(t, result.result.status, Status.Pass)
	testing.expect_value(t, result.choice_count, 0)
	testing.expect_value(t, len(result.events), 1)
}

@(test)
test_case_runner_keeps_borrowed_failure_choices_when_skip_requested :: proc(t: ^testing.T) {
	runner: Case_Runner
	case_runner_init(&runner)
	defer case_runner_destroy(&runner)

	choices := [?]u64{50}
	result := case_runner_run_borrowed(&runner, fails_for_large_values, 1, 10, choices[:], true, {
		capture_events = true,
		skip_choices = true,
	})

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.choice_count, 1)
	testing.expect_value(t, borrowed_choice_at(result, 0), u64(50))
}

@(test)
test_process_adapter_runs_cli :: proc(t: ^testing.T) {
	result := check("process adapter", process_property, {num_tests = 3, seed = 1})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_process_adapter_records_duration :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	command := [?]string{"/bin/sh", "-c", "printf ok"}
	result := process_run(&ctx, command[:])

	testing.expect(t, result.success)
	testing.expect(t, result.duration_ns > 0)
	testing.expect(t, len(ctx.events) > 0)
	testing.expect(t, strings.contains(ctx.events[0].detail, "duration_ns="))
}

@(test)
test_process_adapter_accepts_working_dir_and_env :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	command := [?]string{"/bin/sh", "-c", "printf \"%s:%s\" \"$PWD\" \"$PBT_PROCESS_TEST\""}
	env := [?]string{"PBT_PROCESS_TEST=ok"}
	result := process_run_with_options(&ctx, command[:], {
		working_dir = "/tmp",
		env = env[:],
	})

	testing.expect(t, result.success)
	testing.expect(t, strings.contains(result.stdout, "/tmp:ok"))
}

@(test)
test_process_adapter_accepts_stdin :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	command := [?]string{"/bin/sh", "-c", "cat"}
	result := process_run_with_options(&ctx, command[:], {stdin = "payload"})

	testing.expect(t, result.success)
	testing.expect_value(t, result.stdout, "payload")
	testing.expect(t, len(ctx.events) > 0)
	testing.expect(t, strings.contains(ctx.events[0].detail, "stdin_bytes=7"))
}

@(test)
test_process_adapter_times_out :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	command := [?]string{"/bin/sh", "-c", "sleep 0.2; printf late"}
	result := process_run_with_options(&ctx, command[:], {timeout_ms = 20})

	testing.expect(t, !result.success)
	testing.expect(t, strings.contains(result.error, "timed out after 20 ms"))
	testing.expect(t, result.duration_ns > 0)
	testing.expect(t, result.duration_ns < 150_000_000)
	testing.expect(t, len(ctx.events) > 0)
	testing.expect(t, strings.contains(ctx.events[0].detail, "timeout_ms=20"))
}

@(test)
test_process_adapter_caps_output :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	command := [?]string{"/bin/sh", "-c", "printf abcdef"}
	result := process_run_with_options(&ctx, command[:], {max_output_bytes = 3})

	testing.expect(t, !result.success)
	testing.expect_value(t, result.stdout, "abc")
	testing.expect(t, strings.contains(result.error, "stdout exceeded 3 bytes"))
	testing.expect(t, len(ctx.events) > 0)
	testing.expect(t, strings.contains(ctx.events[0].detail, "max_output_bytes=3"))
}

@(test)
test_protocol_adapter_sends_request_file :: proc(t: ^testing.T) {
	result := check("protocol adapter", protocol_property, {num_tests = 10, seed = 11})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_protocol_adapter_accepts_process_options :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	command := [?]string{"/bin/sh", "-c", "IFS= read -r payload < \"$1\"; printf \"%s:%s\" \"$PBT_PROTOCOL_TEST\" \"$payload\"", "pbt-target"}
	env := [?]string{"PBT_PROTOCOL_TEST=ok"}
	result := protocol_call_with_options(&ctx, command[:], "payload", {env = env[:]})

	testing.expect(t, result.success)
	testing.expect_value(t, result.stdout, "ok:payload")
}

@(test)
test_protocol_stdin_adapter_sends_request_on_stdin :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	command := [?]string{"/bin/sh", "-c", "IFS= read -r payload; printf \"%s:%s\" \"$PBT_PROTOCOL_TEST\" \"$payload\""}
	env := [?]string{"PBT_PROTOCOL_TEST=ok"}
	result := protocol_stdin_call_with_options(&ctx, command[:], "payload", {env = env[:]})

	testing.expect(t, result.success)
	testing.expect_value(t, result.stdout, "ok:payload")
	testing.expect(t, len(ctx.events) > 0)
	testing.expect(t, strings.contains(ctx.events[0].detail, "stdin_bytes=7"))
}

@(test)
test_line_protocol_reuses_process :: proc(t: ^testing.T) {
	command := [?]string{"/bin/sh", "-c", "while IFS= read -r line; do printf \"%s:%s\\n\" \"$PBT_LINE_TEST\" \"$line\"; done"}
	env := [?]string{"PBT_LINE_TEST=ok"}
	client, start_error := line_protocol_start(command[:], {env = env[:]})
	defer line_protocol_stop(&client)

	testing.expect(t, start_error == nil)

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	first := line_protocol_call(&ctx, &client, "one")
	second := line_protocol_call(&ctx, &client, "two")

	testing.expect(t, first.success)
	testing.expect(t, second.success)
	testing.expect_value(t, first.response, "ok:one")
	testing.expect_value(t, second.response, "ok:two")
	testing.expect(t, first.duration_ns > 0)
	testing.expect(t, second.duration_ns > 0)
	testing.expect(t, len(ctx.events) >= 2)
	testing.expect(t, strings.contains(ctx.events[0].detail, "duration_ns="))
	testing.expect(t, strings.contains(ctx.events[0].detail, "max_response_bytes=1048576"))
}

@(test)
test_line_protocol_rejects_oversized_response :: proc(t: ^testing.T) {
	command := [?]string{"/bin/sh", "-c", "while IFS= read -r line; do printf \"123456789\\n\"; done"}
	client, start_error := line_protocol_start(command[:])
	defer line_protocol_stop(&client)

	testing.expect(t, start_error == nil)

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	result := line_protocol_call_with_options(&ctx, &client, "anything", {max_response_bytes = 4})

	testing.expect(t, !result.success)
	testing.expect(t, strings.contains(result.error, "exceeded 4 bytes"))
	testing.expect(t, !client.alive)
	testing.expect(t, len(ctx.events) > 0)
	testing.expect_value(t, ctx.events[0].status, "error")
}

@(test)
test_line_protocol_times_out_waiting_for_response :: proc(t: ^testing.T) {
	command := [?]string{"/bin/sh", "-c", "while IFS= read -r line; do sleep 1; done"}
	client, start_error := line_protocol_start(command[:])
	defer line_protocol_stop(&client)

	testing.expect(t, start_error == nil)

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	result := line_protocol_call_with_options(&ctx, &client, "anything", {timeout_ms = 10})

	testing.expect(t, !result.success)
	testing.expect(t, !client.alive)
	testing.expect(t, strings.contains(result.error, "line protocol response timed out after 10 ms"))
	testing.expect(t, len(ctx.events) > 0)
	testing.expect_value(t, ctx.events[0].status, "error")
	testing.expect(t, strings.contains(ctx.events[0].detail, "timeout_ms=10"))
	testing.expect(t, strings.contains(ctx.events[0].detail, "max_response_bytes=1048576"))
}

@(test)
test_http_adapter_fetches_url :: proc(t: ^testing.T) {
	file, err := os.create("/tmp/pbt-http-adapter-ok")
	testing.expect(t, err == nil)
	_, err = os.write_string(file, "ok")
	testing.expect(t, err == nil)
	os.close(file)
	defer os.remove("/tmp/pbt-http-adapter-ok")

	result := check("http adapter", http_property, {num_tests = 3, seed = 12})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_http_adapter_records_duration :: proc(t: ^testing.T) {
	file, err := os.create("/tmp/pbt-http-adapter-duration")
	testing.expect(t, err == nil)
	_, err = os.write_string(file, "ok")
	testing.expect(t, err == nil)
	os.close(file)
	defer os.remove("/tmp/pbt-http-adapter-duration")

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	response := http_get(&ctx, "file:///tmp/pbt-http-adapter-duration")

	testing.expect(t, response.success)
	testing.expect(t, response.duration_ns > 0)
	testing.expect(t, len(ctx.events) > 0)
	testing.expect(t, strings.contains(ctx.events[len(ctx.events) - 1].detail, "duration_ns="))
}

@(test)
test_http_adapter_accepts_timeout :: proc(t: ^testing.T) {
	file, err := os.create("/tmp/pbt-http-adapter-timeout")
	testing.expect(t, err == nil)
	_, err = os.write_string(file, "ok")
	testing.expect(t, err == nil)
	os.close(file)
	defer os.remove("/tmp/pbt-http-adapter-timeout")

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	response := http_request(&ctx, {method = "GET", url = "file:///tmp/pbt-http-adapter-timeout", timeout_ms = 1_500})

	testing.expect(t, response.success)
	testing.expect(t, !response.timed_out)
	testing.expect(t, len(ctx.events) > 0)
	testing.expect(t, strings.contains(ctx.events[0].detail, "--max-time 1.500"))
	testing.expect(t, strings.contains(ctx.events[len(ctx.events) - 1].detail, "timeout_ms=1500"))
}

@(test)
test_http_post_json_adds_json_headers :: proc(t: ^testing.T) {
	fake_curl := "/tmp/pbt-fake-curl-json"
	file, err := os.create(fake_curl)
	testing.expect(t, err == nil)
	_, err = os.write_string(file, "#!/bin/sh\nout=\"\"\nprev=\"\"\nfor arg in \"$@\"; do\n  if [ \"$prev\" = \"-o\" ]; then out=\"$arg\"; fi\n  prev=\"$arg\"\ndone\nprintf '{\"ok\":true}' > \"$out\"\nprintf 201\n")
	testing.expect(t, err == nil)
	os.close(file)
	err = os.chmod(fake_curl, os.Permissions_All)
	testing.expect(t, err == nil)
	defer os.remove(fake_curl)

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	response := http_post_json(&ctx, "http://example.test/items", "{\"sku\":\"abc\"}", {
		curl = fake_curl,
		timeout_ms = 500,
	})

	testing.expect(t, response.success)
	testing.expect_value(t, response.status, 201)
	testing.expect_value(t, response.body, "{\"ok\":true}")
	testing.expect(t, http_events_contain(ctx.events[:], "Content-Type: application/json"))
	testing.expect(t, http_events_contain(ctx.events[:], "Accept: application/json"))
	testing.expect(t, http_events_contain(ctx.events[:], "--max-time 0.500"))
	testing.expect(t, http_events_contain(ctx.events[:], "--data-binary @-"))
	testing.expect(t, http_events_contain(ctx.events[:], "stdin_bytes=13"))
}

@(test)
test_http_adapter_records_body_and_stderr_summary :: proc(t: ^testing.T) {
	fake_curl := "/tmp/pbt-fake-curl-summary"
	file, err := os.create(fake_curl)
	testing.expect(t, err == nil)
	_, err = os.write_string(file, "#!/bin/sh\nout=\"\"\nprev=\"\"\nfor arg in \"$@\"; do\n  if [ \"$prev\" = \"-o\" ]; then out=\"$arg\"; fi\n  prev=\"$arg\"\ndone\nprintf 'hello\\nworld' > \"$out\"\nprintf 'warn\\n' >&2\nprintf 500\n")
	testing.expect(t, err == nil)
	os.close(file)
	err = os.chmod(fake_curl, os.Permissions_All)
	testing.expect(t, err == nil)
	defer os.remove(fake_curl)

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	response := http_request(&ctx, {method = "GET", url = "http://example.test/fail", curl = fake_curl})

	testing.expect(t, response.success)
	testing.expect_value(t, response.status, 500)
	testing.expect_value(t, response.body, "hello\nworld")
	testing.expect(t, strings.contains(response.stderr, "warn"))
	testing.expect(t, len(ctx.events) > 0)
	detail := ctx.events[len(ctx.events) - 1].detail
	testing.expect(t, strings.contains(detail, "body_bytes=11"))
	testing.expect(t, strings.contains(detail, "body_preview=\"hello\\nworld\""))
	testing.expect(t, strings.contains(detail, "stderr_bytes=5"))
	testing.expect(t, strings.contains(detail, "stderr_preview=\"warn\\n\""))
}

@(test)
test_http_adapter_caps_response_body :: proc(t: ^testing.T) {
	fake_curl := "/tmp/pbt-fake-curl-body-cap"
	file, err := os.create(fake_curl)
	testing.expect(t, err == nil)
	_, err = os.write_string(file, "#!/bin/sh\nout=\"\"\nprev=\"\"\nfor arg in \"$@\"; do\n  if [ \"$prev\" = \"-o\" ]; then out=\"$arg\"; fi\n  prev=\"$arg\"\ndone\nprintf abcdef > \"$out\"\nprintf 200\n")
	testing.expect(t, err == nil)
	os.close(file)
	err = os.chmod(fake_curl, os.Permissions_All)
	testing.expect(t, err == nil)
	defer os.remove(fake_curl)

	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	response := http_request(&ctx, {method = "GET", url = "http://example.test/large", curl = fake_curl, max_body_bytes = 3})

	testing.expect(t, !response.success)
	testing.expect(t, response.body_too_large)
	testing.expect_value(t, response.body, "abc")
	testing.expect(t, strings.contains(response.error, "exceeded 3 bytes"))
	testing.expect(t, len(ctx.events) > 0)
	detail := ctx.events[len(ctx.events) - 1].detail
	testing.expect(t, strings.contains(detail, "max_body_bytes=3"))
	testing.expect(t, strings.contains(detail, "body_truncated=true"))
	testing.expect(t, strings.contains(detail, "body_bytes=3"))
}

@(test)
test_http_expect_status_helpers :: proc(t: ^testing.T) {
	ok := Http_Response{success = true, status = 201}
	testing.expect_value(t, http_expect_status(ok, 201).status, Status.Pass)
	testing.expect_value(t, http_expect_success(ok).status, Status.Pass)

	wrong_status := http_expect_status(ok, 200)
	testing.expect_value(t, wrong_status.status, Status.Fail)
	testing.expect(t, strings.contains(wrong_status.message, "expected HTTP status 200"))

	transport := Http_Response{success = false, exit_code = 7, error = "connection refused"}
	transport_result := http_expect_success(transport)
	testing.expect_value(t, transport_result.status, Status.Fail)
	testing.expect_value(t, transport_result.message, "connection refused")
}

http_events_contain :: proc(events: []Event, text: string) -> bool {
	for event in events {
		if strings.contains(event.detail, text) {
			return true
		}
	}
	return false
}

@(test)
test_same_seed_replays_choices :: proc(t: ^testing.T) {
	a := check("seed a", same_seed_generates_same_choices, {num_tests = 1, seed = 99})
	defer destroy_check_result(&a)

	b := check("seed b", same_seed_generates_same_choices, {num_tests = 1, seed = 99})
	defer destroy_check_result(&b)

	testing.expect_value(t, len(a.replay.choices), len(b.replay.choices))
	for i in 0 ..< len(a.replay.choices) {
		testing.expect_value(t, a.replay.choices[i], b.replay.choices[i])
	}
}

@(test)
test_collection_generators_do_not_leak :: proc(t: ^testing.T) {
	result := check("collections generate", collections_are_generated_in_case_arena, {num_tests = 25, seed = 77})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_generator_combinators :: proc(t: ^testing.T) {
	result := check("combinators", combinators_generate_domain_values, {num_tests = 25, seed = 91})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_generator_catalog_primitives :: proc(t: ^testing.T) {
	result := check("generator catalog", generator_catalog_values, {num_tests = 25, seed = 191})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_sample_exposes_generator_values :: proc(t: ^testing.T) {
	samples := sample(string_alphabet("ab", 1, 5), {count = 5, seed = 901, size = 5})
	defer destroy_sample_result(&samples)

	testing.expect_value(t, len(samples.values), 5)
	for value in samples.values {
		testing.expect(t, len(value) >= 1 && len(value) <= 5)
		for ch in value {
			testing.expect(t, ch == 'a' || ch == 'b')
		}
	}
}

@(test)
test_sample_does_not_accumulate_replay_choices :: proc(t: ^testing.T) {
	samples := sample(array(int_range(0, 9), 8, 8), {count = 25, seed = 902, size = 8})
	defer destroy_sample_result(&samples)

	testing.expect_value(t, len(samples.values), 25)
	testing.expect_value(t, samples.ctx.choice_count, 8)
	testing.expect_value(t, len(samples.ctx.choice_extra), 0)
}

@(test)
test_coverage_is_aggregated_and_written_to_json :: proc(t: ^testing.T) {
	result := check("coverage", coverage_property, {num_tests = 25, seed = 301})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	all_index := coverage_index(result.coverage[:], "all")
	testing.expect(t, all_index >= 0)
	testing.expect_value(t, result.coverage[all_index].count, 25)
	testing.expect_value(t, result.coverage[all_index].required_percent, 100.0)

	json := check_result_json(result)
	defer delete(json)
	testing.expect(t, strings.contains(json, "\"coverage\""))
	testing.expect(t, strings.contains(json, "\"label\":\"all\""))
	testing.expect(t, strings.contains(json, "\"required_percent\":100.00"))
	testing.expect(t, strings.contains(json, "\"ok\":true"))
	testing.expect(t, strings.contains(json, "\"coverage_missing\":false"))

	text := check_result_text(result)
	defer delete(text)
	testing.expect(t, strings.contains(text, "all: 25 (100.00%, required 100.00%, ok)"))
}

@(test)
test_unmet_coverage_requirement_fails_check :: proc(t: ^testing.T) {
	result := check("coverage failure", coverage_failure_property, {num_tests = 10, seed = 302})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Error)
	testing.expect_value(t, result.code, "coverage_not_met")
	testing.expect_value(t, result.message, "coverage requirement not met: impossible 0.00% < required 1.00%")
	impossible_index := coverage_index(result.coverage[:], "impossible")
	testing.expect(t, impossible_index >= 0)
	testing.expect_value(t, result.coverage[impossible_index].count, 0)
	testing.expect_value(t, result.coverage[impossible_index].required_percent, 1.0)

	json := check_result_json(result)
	defer delete(json)
	testing.expect(t, strings.contains(json, "\"coverage_missing\":true"))
	testing.expect(t, strings.contains(json, "\"coverage_missing_label\":\"impossible\""))
	testing.expect(t, strings.contains(json, "\"coverage_observed_percent\":0.00"))
	testing.expect(t, strings.contains(json, "\"coverage_required_percent\":1.00"))

	text := check_result_text(result)
	defer delete(text)
	testing.expect(t, strings.contains(text, "impossible: 0 (0.00%, required 1.00%, missing)"))
}

@(test)
test_coverage_warning_only_keeps_check_passing :: proc(t: ^testing.T) {
	result := check("coverage warning", coverage_failure_property, {num_tests = 10, seed = 302, coverage_warning_only = true})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.code, "ok")
	impossible_index := coverage_index(result.coverage[:], "impossible")
	testing.expect(t, impossible_index >= 0)

	json := check_result_json(result)
	defer delete(json)
	testing.expect(t, strings.contains(json, "\"label\":\"impossible\""))
	testing.expect(t, strings.contains(json, "\"ok\":false"))
	testing.expect(t, strings.contains(json, "\"coverage_missing\":true"))
	testing.expect(t, strings.contains(json, "\"coverage_missing_label\":\"impossible\""))
}

@(test)
test_coverage_extra_tests_can_satisfy_requirement :: proc(t: ^testing.T) {
	result := check("coverage extra", coverage_extra_property, {num_tests = 2, seed = 7, coverage_extra_tests = 1})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.code, "ok")
	testing.expect_value(t, result.num_tests, 3)
	two_index := coverage_index(result.coverage[:], "two")
	testing.expect(t, two_index >= 0)
	testing.expect_value(t, result.coverage[two_index].count, 1)
	testing.expect_value(t, result.coverage[two_index].required_percent, 30.0)
}

@(test)
test_check_advances_seed_after_discard :: proc(t: ^testing.T) {
	result := check("discard retry", discard_one_property, {num_tests = 1, max_discards = 1, seed = 1})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.num_tests, 1)
	testing.expect_value(t, result.num_discards, 1)
}

@(test)
test_counterexample_adds_failure_context :: proc(t: ^testing.T) {
	result := check("counterexample", counterexample_property, {num_tests = 1, seed = 401})
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect(t, strings.contains(result.message, "while checking invoice total"))
	testing.expect(t, strings.contains(result.message, "expected 13, got 12"))
}

@(test)
test_copy_events_preserves_static_fields :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	record_event_static_kind_status(&ctx, "stateful", "step 0", "ok", "detail")
	testing.expect(t, !event_name_owned(ctx.events[0]))
	testing.expect(t, !event_detail_owned(ctx.events[0]))
	testing.expect(t, event_name_copy(ctx.events[0]))
	testing.expect(t, event_detail_copy(ctx.events[0]))

	copied := copy_events(ctx.events[:])
	defer destroy_events(&copied)

	testing.expect_value(t, len(copied), 1)
	testing.expect_value(t, copied[0].kind, "stateful")
	testing.expect_value(t, copied[0].status, "ok")
	testing.expect(t, !event_kind_owned(copied[0]))
	testing.expect(t, !event_status_owned(copied[0]))
	testing.expect(t, event_name_owned(copied[0]))
	testing.expect(t, event_detail_owned(copied[0]))
}

@(test)
test_copy_events_to_test_case_pools_dynamic_fields :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	record_event_static_kind_status(&ctx, "stateful", "step 0", "ok", "detail")

	tc: Test_Case
	copy_events_to_test_case(&tc, ctx.events[:])
	defer destroy_test_case(&tc)

	testing.expect_value(t, len(tc.events), 1)
	testing.expect_value(t, tc.events[0].kind, "stateful")
	testing.expect_value(t, tc.events[0].name, "step 0")
	testing.expect_value(t, tc.events[0].status, "ok")
	testing.expect_value(t, tc.events[0].detail, "detail")
	testing.expect(t, !event_name_owned(tc.events[0]))
	testing.expect(t, !event_detail_owned(tc.events[0]))
	testing.expect(t, event_name_copy(tc.events[0]))
	testing.expect(t, event_detail_copy(tc.events[0]))
	testing.expect_value(t, len(tc.event_string_storage), len("step 0") + len("detail"))
}

@(test)
test_copy_events_to_test_case_recopies_pooled_fields :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	record_event_static_kind_status(&ctx, "http", "POST /items", "fail", "expected 2xx")

	first: Test_Case
	copy_events_to_test_case(&first, ctx.events[:])
	second: Test_Case
	copy_events_to_test_case(&second, first.events[:])
	destroy_test_case(&first)
	defer destroy_test_case(&second)

	testing.expect_value(t, len(second.events), 1)
	testing.expect_value(t, second.events[0].kind, "http")
	testing.expect_value(t, second.events[0].name, "POST /items")
	testing.expect_value(t, second.events[0].status, "fail")
	testing.expect_value(t, second.events[0].detail, "expected 2xx")
}

@(test)
test_transient_event_fields_are_copied_to_test_case :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	name := strings.clone("step 0 inc", context.temp_allocator)
	detail := strings.clone("state=0 value=1 next=1", context.temp_allocator)
	record_event_transient_static_kind_status(&ctx, "stateful", name, "ok", detail)
	testing.expect(t, event_name_copy(ctx.events[0]))
	testing.expect(t, event_detail_copy(ctx.events[0]))
	testing.expect(t, !event_name_owned(ctx.events[0]))
	testing.expect(t, !event_detail_owned(ctx.events[0]))

	tc: Test_Case
	copy_events_to_test_case(&tc, ctx.events[:])
	defer destroy_test_case(&tc)

	testing.expect_value(t, len(tc.events), 1)
	testing.expect_value(t, tc.events[0].kind, "stateful")
	testing.expect_value(t, tc.events[0].name, "step 0 inc")
	testing.expect_value(t, tc.events[0].status, "ok")
	testing.expect_value(t, tc.events[0].detail, "state=0 value=1 next=1")
	testing.expect(t, event_name_copy(tc.events[0]))
	testing.expect(t, event_detail_copy(tc.events[0]))
}

@(test)
test_run_case_moves_events_with_copied_transient_fields :: proc(t: ^testing.T) {
	tc := run_case(transient_event_property, 1, 1, nil, false, true, true)
	defer destroy_test_case(&tc)

	testing.expect_value(t, len(tc.events), 1)
	testing.expect_value(t, tc.events[0].kind, "stateful")
	testing.expect_value(t, tc.events[0].name, "step 0 inc")
	testing.expect_value(t, tc.events[0].status, "ok")
	testing.expect_value(t, tc.events[0].detail, "state=0 value=1 next=1")
	testing.expect(t, event_name_copy(tc.events[0]))
	testing.expect(t, event_detail_copy(tc.events[0]))
}

@(test)
test_run_case_with_options_can_skip_pass_choices :: proc(t: ^testing.T) {
	tc := run_case_with_options(transient_event_property, 1, 1, nil, false, {
		capture_pass = true,
		capture_events = true,
		skip_choices = true,
	})
	defer destroy_test_case(&tc)

	testing.expect_value(t, tc.result.status, Status.Pass)
	testing.expect_value(t, len(tc.choices), 0)
	testing.expect_value(t, len(tc.events), 1)
}

@(test)
test_run_case_with_options_keeps_failure_choices_when_skip_requested :: proc(t: ^testing.T) {
	choices := [?]u64{50}
	tc := run_case_with_options(fails_for_large_values, 1, 10, choices[:], true, {
		capture_pass = true,
		capture_events = true,
		skip_choices = true,
	})
	defer destroy_test_case(&tc)

	testing.expect_value(t, tc.result.status, Status.Fail)
	testing.expect(t, len(tc.choices) > 0)
}

@(test)
test_copy_events_preserves_fully_static_fields :: proc(t: ^testing.T) {
	ctx: T
	test_init(&ctx, 1, 1, nil, false, true)
	defer test_destroy(&ctx)

	record_event_static(&ctx, "stateful", "inc", "ok", "")
	testing.expect(t, !event_kind_owned(ctx.events[0]))
	testing.expect(t, !event_name_owned(ctx.events[0]))
	testing.expect(t, !event_status_owned(ctx.events[0]))
	testing.expect(t, !event_detail_owned(ctx.events[0]))
	testing.expect(t, !event_kind_copy(ctx.events[0]))
	testing.expect(t, !event_name_copy(ctx.events[0]))
	testing.expect(t, !event_status_copy(ctx.events[0]))
	testing.expect(t, !event_detail_copy(ctx.events[0]))

	copied := copy_events(ctx.events[:])
	defer destroy_events(&copied)

	testing.expect_value(t, len(copied), 1)
	testing.expect_value(t, copied[0].kind, "stateful")
	testing.expect_value(t, copied[0].name, "inc")
	testing.expect_value(t, copied[0].status, "ok")
	testing.expect(t, !event_kind_owned(copied[0]))
	testing.expect(t, !event_name_owned(copied[0]))
	testing.expect(t, !event_status_owned(copied[0]))
	testing.expect(t, !event_detail_owned(copied[0]))
}

@(test)
test_shrinker_keeps_consumed_choices_only :: proc(t: ^testing.T) {
	choices := [?]u64{3, 7, 1, 2}
	result := shrink_case(sequence_failure_property, choices[:], 1, 10, default_options({}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(7))
	testing.expect_value(t, len(result.choices), 2)
}

@(test)
test_shrinker_zeroes_irrelevant_choice_suffix :: proc(t: ^testing.T) {
	choices := [?]u64{1, 9, 8}
	result := shrink_case(payload_irrelevant_failure_property, choices[:], 1, 10, default_options({max_shrinks = 8}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(0))
	testing.expect_value(t, result.choices[2], u64(0))
	testing.expect_value(t, len(result.choices), 3)
}

@(test)
test_shrinker_uses_optional_absent_hint :: proc(t: ^testing.T) {
	choices := [?]u64{1, 1, 9}
	result := shrink_case(optional_irrelevant_failure_property, choices[:], 1, 10, default_options({max_shrinks = 2}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "marker triggers failure")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(0))
}

@(test)
test_shrinker_removes_marked_command_range :: proc(t: ^testing.T) {
	choices := [?]u64{3, 1, 7, 2}
	result := shrink_case(marked_command_failure_property, choices[:], 1, 10, default_options({max_shrinks = 4}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "bad marked command")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(3))
	testing.expect_value(t, result.choices[1], u64(7))
}

@(test)
test_stateful_shrinker_removes_command_and_reduces_length :: proc(t: ^testing.T) {
	choices := [?]u64{2, 1, 7}
	result := shrink_case(bad_command_stateful_property, choices[:], 1, 10, default_options({max_shrinks = 10}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "bad command")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(7))
}

@(test)
test_fixed_size_generator_replay_stays_aligned :: proc(t: ^testing.T) {
	choices := [?]u64{3, 1, 7}
	first := run_case(fixed_array_failure_property, 1, 10, choices[:], true, true)
	defer destroy_test_case(&first)

	replayed := run_case(fixed_array_failure_property, 1, 10, first.choices[:], true, true)
	defer destroy_test_case(&replayed)

	testing.expect_value(t, first.result.status, Status.Fail)
	testing.expect_value(t, first.result.message, "bad fixed array")
	testing.expect_value(t, len(first.choices), 3)
	testing.expect_value(t, replayed.result.status, Status.Fail)
	testing.expect_value(t, replayed.result.message, "bad fixed array")
	testing.expect_value(t, len(replayed.choices), 3)
}

@(test)
test_shrinker_shortens_array_suffix_with_length_hint :: proc(t: ^testing.T) {
	choices := [?]u64{3, 1, 7, 2}
	result := shrink_case(array_suffix_failure_property, choices[:], 1, 10, default_options({max_shrinks = 8}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "array prefix contains bad value")
	testing.expect_value(t, len(result.choices), 3)
	testing.expect_value(t, result.choices[0], u64(2))
	testing.expect_value(t, result.choices[1], u64(1))
	testing.expect_value(t, result.choices[2], u64(7))
}

@(test)
test_shrinker_shortens_string_suffix_with_length_hint :: proc(t: ^testing.T) {
	choices := [?]u64{3, 0, 1, 0}
	result := shrink_case(string_suffix_failure_property, choices[:], 1, 10, default_options({max_shrinks = 8}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "string prefix contains bad byte")
	testing.expect_value(t, len(result.choices), 3)
	testing.expect_value(t, result.choices[0], u64(2))
	testing.expect_value(t, result.choices[1], u64(0))
	testing.expect_value(t, result.choices[2], u64(1))
}

@(test)
test_shrinker_removes_array_prefix_with_length_hint :: proc(t: ^testing.T) {
	choices := [?]u64{3, 1, 2, 7}
	result := shrink_case(array_contains_failure_property, choices[:], 1, 10, default_options({max_shrinks = 8}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "array contains bad value")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(7))
}

@(test)
test_shrinker_removes_unique_array_values_with_length_hint :: proc(t: ^testing.T) {
	choices := [?]u64{2, 1, 7}
	result := shrink_case(unique_array_contains_failure_property, choices[:], 1, 10, default_options({max_shrinks = 8}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "unique array contains bad value")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(7))
}

@(test)
test_shrinker_removes_string_prefix_with_length_hint :: proc(t: ^testing.T) {
	choices := [?]u64{3, 0, 0, 1}
	result := shrink_case(string_contains_failure_property, choices[:], 1, 10, default_options({max_shrinks = 8}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "string contains bad byte")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(1))
}

@(test)
test_shrinker_removes_array_middle_range_with_length_hint :: proc(t: ^testing.T) {
	choices := [?]u64{4, 1, 2, 3, 7}
	result := shrink_case(array_middle_irrelevant_failure_property, choices[:], 1, 10, default_options({max_shrinks = 12}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "array boundary values expose bug")
	testing.expect_value(t, len(result.choices), 3)
	testing.expect_value(t, result.choices[0], u64(2))
	testing.expect_value(t, result.choices[1], u64(1))
	testing.expect_value(t, result.choices[2], u64(7))
}

@(test)
test_shrinker_zeroes_irrelevant_tuple_component_with_hint :: proc(t: ^testing.T) {
	choices := [?]u64{3, 9, 8, 7}
	result := shrink_case(triple_middle_irrelevant_failure_property, choices[:], 1, 10, default_options({max_shrinks = 3}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "triple boundary values expose bug")
	testing.expect_value(t, len(result.choices), 4)
	testing.expect_value(t, result.choices[0], u64(3))
	testing.expect_value(t, result.choices[1], u64(0))
	testing.expect_value(t, result.choices[2], u64(0))
	testing.expect_value(t, result.choices[3], u64(7))
}

@(test)
test_shrinker_zeroes_irrelevant_one_of_payload_with_hint :: proc(t: ^testing.T) {
	choices := [?]u64{1, 9, 8, 7}
	result := shrink_case(one_of_payload_irrelevant_failure_property, choices[:], 1, 10, default_options({max_shrinks = 2}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "one_of branch and marker expose bug")
	testing.expect_value(t, len(result.choices), 4)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(0))
	testing.expect_value(t, result.choices[2], u64(0))
	testing.expect_value(t, result.choices[3], u64(7))
}

@(test)
test_shrinker_uses_domain_choice_hints :: proc(t: ^testing.T) {
	choices := [?]u64{1, 0, 7}
	result := shrink_case(domain_encoded_failure_property, choices[:], 1, 10, default_options({max_shrinks = 8}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "domain value should not be seven")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(0))
	testing.expect_value(t, result.choices[1], u64(7))
}

@(test)
test_shrinker_removes_json_subset_fields_with_hints :: proc(t: ^testing.T) {
	choices := [?]u64{1, 1, 1, 2, 2, 2}
	result := shrink_case(json_subset_field_failure_property, choices[:], 1, 10, default_options({max_shrinks = 20}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "json subset contains b")
	testing.expect_value(t, len(result.choices), 4)
	testing.expect_value(t, result.choices[0], u64(0))
	testing.expect_value(t, result.choices[1], u64(1))
	testing.expect_value(t, result.choices[2], u64(0))
	testing.expect_value(t, result.choices[3], u64(0))
}

@(test)
test_shrinker_removes_json_schema_subset_fields_with_hints :: proc(t: ^testing.T) {
	choices := [?]u64{1, 1, 1}
	result := shrink_case(json_schema_subset_field_failure_property, choices[:], 1, 10, default_options({max_shrinks = 20}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "json schema subset contains b")
	testing.expect_value(t, len(result.choices), 3)
	testing.expect_value(t, result.choices[0], u64(0))
	testing.expect_value(t, result.choices[1], u64(1))
	testing.expect_value(t, result.choices[2], u64(0))
}

@(test)
test_shrinker_removes_json_array_items_with_hints :: proc(t: ^testing.T) {
	choices := [?]u64{2, 1, 7, 2}
	result := shrink_case(json_array_of_failure_property, choices[:], 1, 10, default_options({max_shrinks = 20}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "json array contains seven")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(0))
	testing.expect_value(t, result.choices[1], u64(7))
}

@(test)
test_shrinker_removes_dict_entries_with_hints :: proc(t: ^testing.T) {
	choices := [?]u64{2, 1, 1, 7, 7}
	result := shrink_case(dict_entry_failure_property, choices[:], 1, 10, default_options({max_shrinks = 12}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "dict contains bad key")
	testing.expect_value(t, len(result.choices), 3)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(7))
	testing.expect_value(t, result.choices[2], u64(0))
}

@(test)
test_shrinker_can_preserve_original_failure_labels :: proc(t: ^testing.T) {
	choices := [?]u64{1, 9}
	result := shrink_case(labelled_failure_property, choices[:], 1, 10, default_options({max_shrinks = 20, preserve_shrink_labels = true}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "labelled failure")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(0))
	testing.expect(t, labels_contain(result.labels[:], "interesting"))
}

@(test)
test_shrinker_preserves_required_shrink_labels :: proc(t: ^testing.T) {
	choices := [?]u64{1, 9}
	result := shrink_case(required_shrink_label_failure_property, choices[:], 1, 10, default_options({max_shrinks = 20}))
	defer destroy_test_case(&result)

	testing.expect_value(t, result.result.status, Status.Fail)
	testing.expect_value(t, result.result.message, "required shrink label failure")
	testing.expect_value(t, len(result.choices), 2)
	testing.expect_value(t, result.choices[0], u64(1))
	testing.expect_value(t, result.choices[1], u64(0))
	testing.expect(t, labels_contain(result.labels[:], "interesting"))
	testing.expect(t, !labels_contain(result.labels[:], "noise"))
}

@(test)
test_parse_check_options :: proc(t: ^testing.T) {
	args := [?]string{
		"--num-tests",
		"250",
		"--seed",
		"1234",
		"--max-size",
		"80",
		"--max-discards",
		"20",
		"--max-shrinks",
		"30",
		"--coverage-extra-tests",
		"40",
		"--no-shrink",
		"--coverage-warning-only",
		"--preserve-shrink-labels",
	}
	options := parse_check_options(args[:])

	testing.expect_value(t, options.num_tests, 250)
	testing.expect_value(t, options.seed, u64(1234))
	testing.expect_value(t, options.max_size, 80)
	testing.expect_value(t, options.max_discards, 20)
	testing.expect_value(t, options.max_shrinks, 30)
	testing.expect_value(t, options.coverage_extra_tests, 40)
	testing.expect(t, options.no_shrink)
	testing.expect(t, options.coverage_warning_only)
	testing.expect(t, options.preserve_shrink_labels)
}

@(test)
test_parse_output_mode :: proc(t: ^testing.T) {
	empty := [?]string{}
	text_args := [?]string{"--text"}
	json_args := [?]string{"--text", "--json"}
	testing.expect(t, use_json_output(empty[:]))
	testing.expect(t, !use_json_output(text_args[:]))
	testing.expect(t, use_json_output(json_args[:]))
}

@(test)
test_runner_help_text_lists_options_and_properties :: proc(t: ^testing.T) {
	tags := [?]string{"integer", "shrinking"}
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative, description = "adds numbers", tags = tags[:]},
	}
	text := help_text(properties[:])
	defer delete(text)

	testing.expect(t, strings.contains(text, "Usage: pbt-runner"))
	testing.expect(t, strings.contains(text, "--coverage-extra-tests"))
	testing.expect(t, strings.contains(text, "--coverage-warning-only"))
	testing.expect(t, strings.contains(text, "--preserve-shrink-labels"))
	testing.expect(t, strings.contains(text, "--list-properties"))
	testing.expect(t, strings.contains(text, "--target <url>"))
	testing.expect(t, strings.contains(text, "sum [integer,shrinking] - adds numbers"))
}

@(test)
test_parse_replay :: proc(t: ^testing.T) {
	args := [?]string{
		"--replay-seed",
		"1234",
		"--replay-choices",
		"1, 2,3",
	}
	replay, ok := parse_replay(args[:])
	defer destroy_replay(&replay)

	testing.expect(t, ok)
	testing.expect_value(t, replay.seed, u64(1234))
	testing.expect_value(t, len(replay.choices), 3)
	testing.expect_value(t, replay.choices[0], u64(1))
	testing.expect_value(t, replay.choices[1], u64(2))
	testing.expect_value(t, replay.choices[2], u64(3))
}

@(test)
test_check_from_args_replays_when_requested :: proc(t: ^testing.T) {
	first := check("large values fail", fails_for_large_values, {num_tests = 100, seed = 123, shrink = true})
	defer destroy_check_result(&first)

	args := [?]string{
		"--replay-seed",
		"123",
		"--replay-choices",
		"50",
	}
	replayed := check_from_args("large values fail", fails_for_large_values, args[:])
	defer destroy_check_result(&replayed)

	testing.expect_value(t, first.replay.choices[0], u64(50))
	testing.expect_value(t, replayed.status, Status.Fail)
}

@(test)
test_check_property_from_args_selects_named_property :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "collections", property = collections_are_generated_in_case_arena},
	}
	args := [?]string{"--property", "collections", "--num-tests", "5", "--seed", "88"}

	result := check_property_from_args(properties[:], args[:])
	defer destroy_check_result(&result)

	testing.expect_value(t, result.name, "collections")
	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.num_tests, 5)
}

@(test)
test_check_property_from_args_selects_unique_substring :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "collections", property = collections_are_generated_in_case_arena},
	}
	args := [?]string{"--property", "collect", "--num-tests", "5", "--seed", "88"}

	result := check_property_from_args(properties[:], args[:])
	defer destroy_check_result(&result)

	testing.expect_value(t, result.name, "collections")
	testing.expect_value(t, result.status, Status.Pass)
}

@(test)
test_check_property_from_args_rejects_ambiguous_substring :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "small sum", property = sum_is_commutative},
		{name = "large sum", property = sum_is_commutative},
	}
	args := [?]string{"--property", "sum"}

	result := check_property_from_args(properties[:], args[:])
	defer destroy_check_result(&result)

	testing.expect_value(t, result.status, Status.Error)
	testing.expect_value(t, result.code, "multiple_properties_matched")
	testing.expect_value(t, result.message, "multiple properties matched")
}

@(test)
test_check_properties_from_args_runs_all_when_no_property_selected :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "collections", property = collections_are_generated_in_case_arena},
	}
	args := [?]string{"--num-tests", "5", "--seed", "88"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.code, "ok")
	testing.expect_value(t, result.num_properties, 2)
	testing.expect_value(t, result.passed, 2)
	testing.expect_value(t, result.failed, 0)
	testing.expect_value(t, result.errors, 0)
	testing.expect_value(t, result.checks, 10)
	testing.expect_value(t, len(result.results), 2)
}

@(test)
test_check_properties_from_args_runs_selected_property_as_suite :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "collections", property = collections_are_generated_in_case_arena},
	}
	args := [?]string{"--property", "collections", "--num-tests", "5", "--seed", "88"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.num_properties, 1)
	testing.expect_value(t, result.passed, 1)
	testing.expect_value(t, result.checks, 5)
	testing.expect_value(t, len(result.results), 1)
	testing.expect_value(t, result.results[0].name, "collections")
}

@(test)
test_check_properties_from_args_reports_suite_failure :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "always fails", property = always_fails},
	}
	args := [?]string{"--num-tests", "5", "--seed", "88", "--no-shrink"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect_value(t, result.code, "suite_failed")
	testing.expect_value(t, result.passed, 1)
	testing.expect_value(t, result.failed, 1)
	testing.expect_value(t, result.errors, 0)
	testing.expect_value(t, result.checks, 6)
	testing.expect_value(t, len(result.results), 2)
	testing.expect_value(t, result.results[1].name, "always fails")
	testing.expect_value(t, result.results[1].status, Status.Fail)
}

@(test)
test_check_properties_from_args_promotes_suite_coverage_failure :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "coverage failure", property = coverage_failure_property},
	}
	args := [?]string{"--num-tests", "5", "--seed", "88"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Error)
	testing.expect_value(t, result.code, "suite_error")
	testing.expect_value(t, result.results[0].code, "coverage_not_met")

	json := check_suite_result_json(result)
	defer delete(json)
	testing.expect(t, strings.contains(json, "\"failing_coverage_missing\":true"))
	testing.expect(t, strings.contains(json, "\"failing_coverage_missing_label\":\"impossible\""))
	testing.expect(t, strings.contains(json, "\"failing_coverage_observed_percent\":0.00"))
	testing.expect(t, strings.contains(json, "\"failing_coverage_required_percent\":1.00"))
}

@(test)
test_check_properties_from_args_stops_on_fail_fast :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "always fails", property = always_fails},
		{name = "sum", property = sum_is_commutative},
	}
	args := [?]string{"--num-tests", "5", "--seed", "88", "--no-shrink", "--fail-fast"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Fail)
	testing.expect_value(t, result.code, "suite_failed")
	testing.expect_value(t, result.fail_fast, true)
	testing.expect_value(t, result.passed, 0)
	testing.expect_value(t, result.failed, 1)
	testing.expect_value(t, result.checks, 1)
	testing.expect_value(t, len(result.results), 1)
	testing.expect_value(t, result.results[0].name, "always fails")
}

@(test)
test_check_properties_from_args_requires_property_for_replay :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "always fails", property = always_fails},
	}
	args := [?]string{"--replay-seed", "1", "--replay-choices", "50"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Error)
	testing.expect_value(t, result.code, "property_required_for_replay")
	testing.expect_value(t, len(result.results), 0)
}

@(test)
test_check_properties_from_args_filters_by_tag :: proc(t: ^testing.T) {
	core_tag := [?]string{"core"}
	collection_tag := [?]string{"collection", "arena"}
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative, tags = core_tag[:]},
		{name = "collections", property = collections_are_generated_in_case_arena, tags = collection_tag[:]},
	}
	args := [?]string{"--tag", "collection", "--num-tests", "5", "--seed", "88"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Pass)
	testing.expect_value(t, result.num_properties, 1)
	testing.expect_value(t, len(result.results), 1)
	testing.expect_value(t, result.results[0].name, "collections")
}

@(test)
test_check_properties_from_args_rejects_missing_tag :: proc(t: ^testing.T) {
	core_tag := [?]string{"core"}
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative, tags = core_tag[:]},
	}
	args := [?]string{"--tag", "http"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)

	testing.expect_value(t, result.status, Status.Error)
	testing.expect_value(t, result.code, "no_properties_matched_tag")
	testing.expect_value(t, len(result.results), 0)
}

@(test)
test_properties_json_lists_registered_properties :: proc(t: ^testing.T) {
	core_tag := [?]string{"core"}
	collection_tag := [?]string{"collection", "arena"}
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative, description = "addition law", tags = core_tag[:]},
		{name = "collections", property = collections_are_generated_in_case_arena, description = "generated collections", tags = collection_tag[:]},
	}

	json := properties_json(properties[:])
	defer delete(json)

	testing.expect(t, strings.contains(json, "\"tool\":\"pbt\""))
	testing.expect(t, strings.contains(json, "\"schema_version\":1"))
	testing.expect(t, strings.contains(json, "\"name\":\"sum\""))
	testing.expect(t, strings.contains(json, "\"description\":\"addition law\""))
	testing.expect(t, strings.contains(json, "\"tags\":[\"core\"]"))
	testing.expect(t, strings.contains(json, "\"name\":\"collections\""))
	testing.expect(t, strings.contains(json, "\"tags\":[\"collection\",\"arena\"]"))
}

@(test)
test_tags_json_lists_unique_tags_and_counts :: proc(t: ^testing.T) {
	core_tag := [?]string{"core"}
	collection_tag := [?]string{"collection", "core"}
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative, tags = core_tag[:]},
		{name = "collections", property = collections_are_generated_in_case_arena, tags = collection_tag[:]},
	}

	json := tags_json(properties[:])
	defer delete(json)

	testing.expect(t, strings.contains(json, "\"tool\":\"pbt\""))
	testing.expect(t, strings.contains(json, "\"schema_version\":1"))
	testing.expect(t, strings.contains(json, "\"name\":\"core\",\"count\":2"))
	testing.expect(t, strings.contains(json, "\"properties\":[\"sum\",\"collections\"]"))
	testing.expect(t, strings.contains(json, "\"name\":\"collection\",\"count\":1"))
	testing.expect(t, strings.contains(json, "\"properties\":[\"collections\"]"))
}

@(test)
test_check_suite_result_json_includes_summary_and_results :: proc(t: ^testing.T) {
	properties := [?]Property_Case{
		{name = "sum", property = sum_is_commutative},
		{name = "always fails", property = always_fails},
	}
	args := [?]string{"--num-tests", "5", "--seed", "88", "--no-shrink"}

	result := check_properties_from_args(properties[:], args[:])
	defer destroy_check_suite_result(&result)
	json := check_suite_result_json(result)
	defer delete(json)

	testing.expect(t, strings.contains(json, "\"kind\":\"suite\""))
	testing.expect(t, strings.contains(json, "\"status\":\"fail\""))
	testing.expect(t, strings.contains(json, "\"code\":\"suite_failed\""))
	testing.expect(t, strings.contains(json, "\"properties\":2"))
	testing.expect(t, strings.contains(json, "\"passed\":1"))
	testing.expect(t, strings.contains(json, "\"failed\":1"))
	testing.expect(t, strings.contains(json, "\"fail_fast\":false"))
	testing.expect(t, strings.contains(json, "\"failing_property\":\"always fails\""))
	testing.expect(t, strings.contains(json, "\"failing_code\":\"property_failed\""))
	testing.expect(t, strings.contains(json, "\"failing_message\":\"always fails\""))
	testing.expect(t, strings.contains(json, "\"failing_notes\":[]"))
	testing.expect(t, strings.contains(json, "\"failing_events\":[]"))
	testing.expect(t, strings.contains(json, "\"failing_num_tests\":0"))
	testing.expect(t, strings.contains(json, "\"failing_discards\":0"))
	testing.expect(t, strings.contains(json, "\"failing_duration_ns\":"))
	testing.expect(t, strings.contains(json, "\"failing_shrink_attempts\":0"))
	testing.expect(t, strings.contains(json, "\"failing_shrink_duration_ns\":0"))
	testing.expect(t, strings.contains(json, "\"results\":["))
	testing.expect(t, strings.contains(json, "\"name\":\"always fails\""))
}
