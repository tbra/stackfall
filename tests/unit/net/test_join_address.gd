extends GutTest
## JoinCode.parse_address / resolve_text: the direct-join field's IP[:port] and join-code parsing.

const BARE_PORT: int = 0


func test_bare_ip_is_valid_with_no_port() -> void:
	var r: Dictionary = JoinCode.parse_address("1.2.3.4")
	assert_true(bool(r.get("valid")))
	assert_eq(r.get("address"), "1.2.3.4")
	assert_eq(int(r.get("port", -1)), BARE_PORT)


func test_ip_with_port() -> void:
	var r: Dictionary = JoinCode.parse_address("10.0.0.7:47999")
	assert_true(bool(r.get("valid")))
	assert_eq(r.get("address"), "10.0.0.7")
	assert_eq(int(r.get("port", -1)), 47999)


func test_surrounding_whitespace_is_ignored() -> void:
	var r: Dictionary = JoinCode.parse_address("  1.2.3.4:5  ")
	assert_true(bool(r.get("valid")))
	assert_eq(r.get("address"), "1.2.3.4")
	assert_eq(int(r.get("port", -1)), 5)


func test_port_bounds() -> void:
	assert_false(bool(JoinCode.parse_address("1.2.3.4:0").get("valid")), "port 0")
	assert_true(bool(JoinCode.parse_address("1.2.3.4:1").get("valid")), "port 1")
	assert_eq(int(JoinCode.parse_address("1.2.3.4:1").get("port", -1)), 1)
	assert_true(bool(JoinCode.parse_address("1.2.3.4:65535").get("valid")), "port 65535")
	assert_eq(int(JoinCode.parse_address("1.2.3.4:65535").get("port", -1)), 65535)
	assert_false(bool(JoinCode.parse_address("1.2.3.4:65536").get("valid")), "port 65536")
	assert_false(bool(JoinCode.parse_address("1.2.3.4:-1").get("valid")), "negative port")


func test_octet_bounds() -> void:
	assert_true(bool(JoinCode.parse_address("0.0.0.0").get("valid")), "all zero")
	assert_true(bool(JoinCode.parse_address("255.255.255.255").get("valid")), "all 255")
	for i: int in 4:
		var low: PackedStringArray = ["1", "1", "1", "1"]
		low[i] = "256"
		assert_false(bool(JoinCode.parse_address(".".join(low)).get("valid")), "256 in octet %d" % i)
		low[i] = "-1"
		assert_false(bool(JoinCode.parse_address(".".join(low)).get("valid")), "-1 in octet %d" % i)
		low[i] = "255"
		assert_true(bool(JoinCode.parse_address(".".join(low)).get("valid")), "255 in octet %d" % i)


func test_malformed_addresses_are_rejected() -> void:
	var junk_values: PackedStringArray = [
		"", "   ", "not an ip", "1.2.3", "1.2.3.4.5", "1.2.3.999", "1.2.3.4:notaport", "1.2.3.4:",
		"1.2.3.4:5:6", ":47999", "1.2..4", "a.b.c.d",
	]
	for junk: String in junk_values:
		assert_false(bool(JoinCode.parse_address(junk).get("valid")), "'%s' should be rejected" % junk)


func test_resolve_text_routes_address() -> void:
	var r: Dictionary = JoinCode.resolve_text("192.168.1.9:4000")
	assert_true(bool(r.get("valid")))
	assert_eq(r.get("address"), "192.168.1.9")
	assert_eq(int(r.get("port", -1)), 4000)


func test_resolve_text_routes_bare_address() -> void:
	var r: Dictionary = JoinCode.resolve_text("8.8.4.4")
	assert_true(bool(r.get("valid")))
	assert_eq(r.get("address"), "8.8.4.4")
	assert_eq(int(r.get("port", -1)), BARE_PORT)


func test_resolve_text_routes_code() -> void:
	var code: String = JoinCode.encode("203.0.113.250", 47778)
	var r: Dictionary = JoinCode.resolve_text(code)
	assert_true(bool(r.get("valid")))
	assert_eq(r.get("address"), "203.0.113.250")
	assert_eq(int(r.get("port", -1)), 47778)


func test_resolve_text_accepts_lowercase_unspaced_code() -> void:
	var code: String = JoinCode.encode("8.8.8.8", 1)
	var r: Dictionary = JoinCode.resolve_text(code.replace("-", "").to_lower())
	assert_true(bool(r.get("valid")))
	assert_eq(r.get("address"), "8.8.8.8")
	assert_eq(int(r.get("port", -1)), 1)


func test_resolve_text_code_with_bad_length_gives_reason() -> void:
	var r: Dictionary = JoinCode.resolve_text("ABC")
	assert_false(bool(r.get("valid")))
	assert_false(str(r.get("reason", "")).is_empty())


func test_resolve_text_code_with_unused_letter_names_it() -> void:
	var r: Dictionary = JoinCode.resolve_text("7XK2M-9QD4O")
	assert_false(bool(r.get("valid")))
	assert_true(str(r.get("reason", "")).contains("O"))


func test_resolve_text_typo_reason_when_checksum_bits_set() -> void:
	# First character above 7 sets the spare bits above the 48 data bits.
	var r: Dictionary = JoinCode.resolve_text("80000-00001")
	assert_false(bool(r.get("valid")))
	assert_true(str(r.get("reason", "")).contains("typo"))


func test_resolve_text_typo_reason_when_port_is_zero() -> void:
	var r: Dictionary = JoinCode.resolve_text("00000-00000")
	assert_false(bool(r.get("valid")))
	assert_true(str(r.get("reason", "")).contains("typo"))


func test_resolve_text_invalid_address_has_no_code_reason() -> void:
	var r: Dictionary = JoinCode.resolve_text("1.2.3.999")
	assert_false(bool(r.get("valid")))
	assert_false(r.has("address"))
