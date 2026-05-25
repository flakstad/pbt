package main

import "core:fmt"
import "core:os"

import pbt "../../pbt"

HTTP_TAGS := [?]string{"external", "http", "api"}

http_post_schema_property :: proc(t: ^pbt.T) -> pbt.Result {
	base_url := http_target_url()
	if base_url == "" {
		return pbt.error("set --target or PBT_HTTP_BASE_URL to the HTTP endpoint under test")
	}

	statuses := [?]string{"draft", "active", "archived"}
	fields := [?]pbt.JSON_Field_ASCII {
		pbt.json_uuid_v4_field_ascii("id"),
		pbt.json_string_field_ascii("sku", 16),
		pbt.json_email_field_ascii("owner", 1, 16, 1, 12),
		pbt.json_string_enum_field_ascii("status", statuses[:]),
		pbt.json_int_field_ascii("quantity", 1, 100),
		pbt.json_bool_field_ascii("active"),
		pbt.json_date_ymd_field_ascii("created_on", 2020, 2030),
	}
	body := pbt.draw(t, pbt.json_object_schema_ascii(fields[:]))

	response := pbt.http_post_json(t, base_url, body, {
		timeout_ms = 1_000,
		max_body_bytes = 65_536,
	})
	result := pbt.http_expect_success(response)
	if result.status != .Pass {
		return pbt.counterexample(fmt.tprintf("request body: %s", body), result)
	}
	return pbt.pass()
}

http_target_url :: proc() -> string {
	for i := 1; i < len(os.args); i += 1 {
		if os.args[i] == "--target" && i + 1 < len(os.args) {
			return os.args[i + 1]
		}
	}

	base_url, found := os.lookup_env("PBT_HTTP_BASE_URL", context.temp_allocator)
	if found {
		return base_url
	}
	return ""
}

main :: proc() {
	properties := [?]pbt.Property_Case {
		{name = "http accepts schema json", property = http_post_schema_property, description = "generated schema-shaped JSON is accepted by an HTTP endpoint", tags = HTTP_TAGS[:]},
	}

	pbt.run_cli(properties[:], os.args[1:], {shrink = true})
}
