extends GutTest
## Bontago-1pi.164: join-code encoding, public-address check and the Join page's field routing.


func test_round_trip_known_addresses() -> void:
	var cases: Array[Array] = [
		["1.2.3.4", 47778], ["203.0.113.250", 65535], ["255.255.255.255", 1], ["8.8.8.8", 47999], ["0.0.0.1", 1024],
	]
	for c: Array in cases:
		var code: String = JoinCode.encode(str(c[0]), int(c[1]))
		assert_eq(code.length(), 11, "XXXXX-XXXXX for %s" % c[0])
		var back: Dictionary = JoinCode.decode(code)
		assert_true(bool(back["valid"]), code)
		assert_eq(str(back["address"]), str(c[0]))
		assert_eq(int(back["port"]), int(c[1]))


func test_decode_ignores_case_dash_and_spaces() -> void:
	var code: String = JoinCode.encode("81.9.44.7", 47778)
	var loose: String = "  " + code.to_lower().replace("-", " ") + " "
	assert_eq(JoinCode.decode(loose), JoinCode.decode(code))
	assert_true(bool(JoinCode.decode(loose)["valid"]))


func test_encode_rejects_bad_input() -> void:
	assert_eq(JoinCode.encode("1.2.3", 5), "")
	assert_eq(JoinCode.encode("1.2.3.256", 5), "")
	assert_eq(JoinCode.encode("a.b.c.d", 5), "")
	assert_eq(JoinCode.encode("1.2.3.4", 0), "")
	assert_eq(JoinCode.encode("1.2.3.4", 65536), "")


func test_bad_codes_give_a_reason() -> void:
	for text: String in ["", "ABC", "7XK2M-9QD4R-7", "7XK2M-9QD4I", "7XK2M-9QD4O", "7XK2M-9QD4U", "7XK2M-9QD4L", "!!!!!-!!!!!"]:
		var r: Dictionary = JoinCode.decode(text)
		assert_false(bool(r["valid"]), text)
		assert_ne(str(r["reason"]), "", text)


func test_first_char_above_seven_is_a_checksum_failure() -> void:
	var good: String = JoinCode.encode("1.2.3.4", 47778).replace("-", "")
	var bad: String = "Z" + good.substr(1)
	assert_false(bool(JoinCode.decode(bad)["valid"]))


func test_port_zero_code_is_rejected() -> void:
	assert_false(bool(JoinCode.decode("0000000000")["valid"]))


func test_is_public_ipv4() -> void:
	for ip: String in ["8.8.8.8", "81.9.44.7", "172.32.0.1", "100.63.0.1", "100.128.0.1", "198.17.255.1", "198.20.0.1", "192.0.1.1", "192.0.3.1", "198.51.101.1", "203.0.114.1"]:
		assert_true(JoinCode.is_public_ipv4(ip), ip)
	for ip: String in ["10.0.0.1", "192.168.1.5", "172.16.0.1", "172.31.255.1", "127.0.0.1", "169.254.1.1", "100.64.0.1", "100.127.9.9", "198.18.0.1", "198.19.255.254", "192.0.0.9", "192.0.2.5", "198.51.100.7", "203.0.113.250", "0.0.0.0", "224.0.0.1", "", "x"]:
		assert_false(JoinCode.is_public_ipv4(ip), ip)


func test_join_field_routes_ip_or_code() -> void:
	var by_ip: Dictionary = MainMenu.resolve_join_text("1.2.3.4:47999")
	assert_true(bool(by_ip["valid"]))
	assert_eq(int(by_ip["port"]), 47999)
	var code: String = JoinCode.encode("81.9.44.7", 47778)
	var by_code: Dictionary = MainMenu.resolve_join_text(code)
	assert_true(bool(by_code["valid"]))
	assert_eq(str(by_code["address"]), "81.9.44.7")
	assert_eq(int(by_code["port"]), 47778)
	var bad: Dictionary = MainMenu.resolve_join_text("HELLO-WORLD")
	assert_false(bool(bad["valid"]))
	assert_ne(str(bad.get("reason", "")), "")
	assert_false(bool(MainMenu.resolve_join_text("")["valid"]))
