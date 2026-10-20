extends GutTest
## ChatRules, ChatConfig defaults and the chat_open action.

const MAX_NAME: int = 24
const SMALL_RING: int = 3
const OVER_RING: int = 5
## Raw characters scanned for a 3-character cap (the documented scan factor of 4).
const SCAN_WINDOW: int = 12


func _cfg() -> ChatConfig:
	return load("res://config/net/chat_config.tres") as ChatConfig


func test_clean_strips_controls_bidi_zero_width() -> void:
	var raw: String = "a" + String.chr(0x1B) + "b" + String.chr(0x202E) + "c" + String.chr(0x200B) + "d" + String.chr(0x85)
	assert_eq(ChatRules.clean(raw, 140), "abcd")


func test_clean_newline_tab_become_one_space_and_trim() -> void:
	assert_eq(ChatRules.clean("  hi\n\n\tthere \r\n ", 140), "hi there")


func test_clean_cuts_to_code_points() -> void:
	assert_eq(ChatRules.clean("x".repeat(200), 140).length(), 140)
	var wide: String = String.chr(0x1F600).repeat(10)
	assert_eq(ChatRules.clean(wide, 4).length(), 4)


func test_validate_rejects_bad_lines() -> void:
	var cfg: ChatConfig = _cfg()
	var good: Dictionary = ChatRules.make_line(1, 2, 0, "Bo", 0, "hi")
	for bad: Variant in [null, 5, "x", [], {}]:
		assert_false(ChatRules.validate_line(bad, cfg, MAX_NAME))
	var extra: Dictionary = good.duplicate()
	extra["evil"] = 1
	assert_false(ChatRules.validate_line(extra, cfg, MAX_NAME), "extra key")
	var missing: Dictionary = good.duplicate()
	missing.erase(ChatRules.KEY_TEXT)
	assert_false(ChatRules.validate_line(missing, cfg, MAX_NAME), "missing key")
	var wrong_type: Dictionary = good.duplicate()
	wrong_type[ChatRules.KEY_SEQ] = 1.5
	assert_false(ChatRules.validate_line(wrong_type, cfg, MAX_NAME), "float seq")
	var text_int: Dictionary = good.duplicate()
	text_int[ChatRules.KEY_TEXT] = 9
	assert_false(ChatRules.validate_line(text_int, cfg, MAX_NAME), "int text")
	var long_text: Dictionary = good.duplicate()
	long_text[ChatRules.KEY_TEXT] = "x".repeat(cfg.max_chars + 1)
	assert_false(ChatRules.validate_line(long_text, cfg, MAX_NAME), "long text")
	var long_name: Dictionary = good.duplicate()
	long_name[ChatRules.KEY_NAME] = "n".repeat(MAX_NAME + 1)
	assert_false(ChatRules.validate_line(long_name, cfg, MAX_NAME), "long name")
	var bad_kind: Dictionary = good.duplicate()
	bad_kind[ChatRules.KEY_KIND] = 9
	assert_false(ChatRules.validate_line(bad_kind, cfg, MAX_NAME), "kind")
	var neg: Dictionary = good.duplicate()
	neg[ChatRules.KEY_SEQ] = -1
	assert_false(ChatRules.validate_line(neg, cfg, MAX_NAME), "negative seq")


func test_history_ring_drops_the_oldest() -> void:
	var hist: ChatRules.History = ChatRules.History.new(SMALL_RING)
	for i: int in range(OVER_RING):
		hist.push(ChatRules.make_line(i, 1, 0, "A", 0, str(i)))
	var lines: Array[Dictionary] = hist.lines()
	assert_eq(lines.size(), SMALL_RING)
	assert_eq(lines[0][ChatRules.KEY_SEQ], OVER_RING - SMALL_RING)
	assert_eq(lines[SMALL_RING - 1][ChatRules.KEY_SEQ], OVER_RING - 1)
	lines.clear()
	assert_eq(hist.lines().size(), SMALL_RING, "lines() is a copy")


func test_chat_open_is_keyboard_only() -> void:
	assert_true(InputMap.has_action("chat_open"))
	var keys: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(&"chat_open"):
		assert_true(event is InputEventKey, "no non-keyboard binding")
		keys.append((event as InputEventKey).physical_keycode)
	assert_true(keys.has(KEY_ENTER))
	assert_true(keys.has(KEY_KP_ENTER))
	assert_true(keys.has(KEY_T))


func test_validate_rejects_control_characters_in_name_and_text() -> void:
	var cfg: ChatConfig = _cfg()
	for bad: String in ["a" + String.chr(0x07) + "b", "a
b", "a" + String.chr(0x202E) + "b", "a" + String.chr(0x200B)]:
		assert_false(ChatRules.validate_line(ChatRules.make_line(1, 2, 0, "Bo", 0, bad), cfg, MAX_NAME), "text " + bad.c_escape())
		assert_false(ChatRules.validate_line(ChatRules.make_line(1, 2, 0, bad, 0, "hi"), cfg, MAX_NAME), "name " + bad.c_escape())
	var joined: String = "a" + String.chr(0x200D) + "b"
	assert_true(ChatRules.validate_line(ChatRules.make_line(1, 2, 0, "Bo", 0, joined), cfg, MAX_NAME))


func test_the_wire_codes_are_pinned_and_distinct() -> void:
	assert_eq(ChatRules.KIND_TEXT, 0)
	assert_eq(ChatRules.KIND_SYSTEM, 1)
	assert_eq(ChatRules.NOTICE_RATE, 0)
	assert_eq(ChatRules.NOTICE_DUPLICATE, 1)


func test_clean_keeps_the_first_max_chars_code_points_in_order() -> void:
	assert_eq(ChatRules.clean("abcdef", 3), "abc")
	assert_eq(ChatRules.clean("abc", 3), "abc")
	assert_eq(ChatRules.clean("abc", 0), "a", "a zero cap still keeps one character")


func test_clean_drops_a_joiner_the_cut_leaves_hanging() -> void:
	assert_eq(ChatRules.clean("ab" + String.chr(0x200D) + "cd", 3), "ab")


func test_clean_scan_window_is_bounded_by_scan_factor() -> void:
	var limit: int = 3
	var padding: String = String.chr(0x200B).repeat(SCAN_WINDOW)
	assert_eq(ChatRules.clean(padding + "abc", limit), "", "text past the scanned window is never read")
	var inside: String = String.chr(0x200B).repeat(SCAN_WINDOW - limit)
	assert_eq(ChatRules.clean(inside + "abc", limit), "abc")


func test_validate_rejects_a_slot_below_spectator() -> void:
	var cfg: ChatConfig = _cfg()
	assert_true(ChatRules.validate_line(ChatRules.make_line(1, 2, -1, "Bo", 0, "hi"), cfg, MAX_NAME), "a spectator line")
	assert_false(ChatRules.validate_line(ChatRules.make_line(1, 2, -2, "Bo", 0, "hi"), cfg, MAX_NAME))


func test_validate_accepts_text_and_name_exactly_at_their_caps() -> void:
	var cfg: ChatConfig = _cfg()
	var line: Dictionary = ChatRules.make_line(1, 2, 0, "n".repeat(MAX_NAME), 0, "x".repeat(cfg.max_chars))
	assert_true(ChatRules.validate_line(line, cfg, MAX_NAME))


func test_validate_treats_a_negative_name_cap_as_zero() -> void:
	var cfg: ChatConfig = _cfg()
	assert_true(ChatRules.validate_line(ChatRules.make_line(1, 2, 0, "", 0, "hi"), cfg, -5), "an empty name fits a zero cap")
	assert_false(ChatRules.validate_line(ChatRules.make_line(1, 2, 0, "n", 0, "hi"), cfg, 0), "one character exceeds a zero cap")
	assert_false(ChatRules.validate_line(ChatRules.make_line(1, 2, 0, "n", 0, "hi"), cfg, -5))
