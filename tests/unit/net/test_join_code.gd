extends GutTest
## join-code encoding, public-address check and the Join page's field routing.


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

