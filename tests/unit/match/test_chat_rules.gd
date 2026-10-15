extends GutTest
## ChatRules, ChatConfig defaults and the chat_open action (Bontago-1pi.192.1).

const MAX_NAME: int = 24
const HUGE_CHARS: int = 10 * 1024 * 1024
const HUGE_BUDGET_MS: int = 500
const CLAMP_HISTORY_MAX: int = 200
const SMALL_RING: int = 3
const OVER_RING: int = 5


func _cfg() -> ChatConfig:
	return load("res://config/net/chat_config.tres") as ChatConfig


func test_defaults_are_owner_values() -> void:
	var cfg: ChatConfig = _cfg()
	assert_true(cfg.enabled)
	assert_eq(cfg.max_chars, 140)
	assert_eq(cfg.burst, 3)
	assert_eq(cfg.refill_per_s, 0.5)
	assert_eq(cfg.duplicate_window_s, 3.0)
	assert_eq(cfg.notice_min_interval_s, 1.5)
	assert_eq(cfg.history_lines, 30)
	assert_eq(cfg.hud_lines, 6)
	assert_eq(cfg.line_visible_s, 8.0)
	assert_eq(cfg.fade_s, 1.0)


func test_sanitize_clamps() -> void:
	var cfg: ChatConfig = ChatConfig.new()
	cfg.max_chars = -5
	cfg.burst = 0
	cfg.history_lines = 99999
	cfg.sanitize()
	assert_eq(cfg.max_chars, 1)
	assert_eq(cfg.burst, 1)
	assert_eq(cfg.history_lines, CLAMP_HISTORY_MAX)


func test_clean_strips_controls_bidi_zero_width() -> void:
	var raw: String = "a" + String.chr(0x1B) + "b" + String.chr(0x202E) + "c" + String.chr(0x200B) + "d" + String.chr(0x85)
	assert_eq(ChatRules.clean(raw, 140), "abcd")


func test_clean_newline_tab_become_one_space_and_trim() -> void:
	assert_eq(ChatRules.clean("  hi\n\n\tthere \r\n ", 140), "hi there")


func test_clean_collapses_spaces() -> void:
	assert_eq(ChatRules.clean("a     b", 140), "a b")


func test_clean_cuts_to_code_points() -> void:
	assert_eq(ChatRules.clean("x".repeat(200), 140).length(), 140)
	var wide: String = String.chr(0x1F600).repeat(10)
	assert_eq(ChatRules.clean(wide, 4).length(), 4)


func test_clean_non_string_and_empty() -> void:
	assert_eq(ChatRules.clean(5, 140), "")
	assert_eq(ChatRules.clean(null, 140), "")
	assert_eq(ChatRules.clean([1], 140), "")
	assert_eq(ChatRules.clean({}, 140), "")
	assert_eq(ChatRules.clean(" \n\t ", 140), "")


func test_clean_huge_input_is_bounded() -> void:
	var raw: String = "ab".repeat(HUGE_CHARS / 2)
	var started: int = Time.get_ticks_msec()
	var out: String = ChatRules.clean(raw, 140)
	var elapsed: int = Time.get_ticks_msec() - started
	assert_eq(out.length(), 140)
	assert_lt(elapsed, HUGE_BUDGET_MS, "scan must not cover the whole 10 MB string")


func test_clean_keeps_bbcode_literally() -> void:
	var raw: String = "[b]x[/b] [url=a]u[/url] [img]i[/img] [GG]"
	assert_eq(ChatRules.clean(raw, 140), raw)


func test_make_line_and_validate() -> void:
	var cfg: ChatConfig = _cfg()
	var line: Dictionary = ChatRules.make_line(4, 7, 2, "Ann", 1, "hello")
	assert_eq(line[ChatRules.KEY_KIND], ChatRules.KIND_TEXT)
	assert_true(ChatRules.validate_line(line, cfg, MAX_NAME))
	var sys: Dictionary = ChatRules.make_line(5, 1, -1, "Host", 0, "joined", ChatRules.KIND_SYSTEM)
	assert_true(ChatRules.validate_line(sys, cfg, MAX_NAME))


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


func test_bucket_burst_then_refill() -> void:
	var bucket: ChatRules.Bucket = ChatRules.Bucket.new()
	assert_true(bucket.take(0.0, 3, 0.5))
	assert_true(bucket.take(0.0, 3, 0.5))
	assert_true(bucket.take(0.0, 3, 0.5))
	assert_false(bucket.take(0.0, 3, 0.5), "burst spent")
	assert_false(bucket.take(1.0, 3, 0.5), "half a token is not enough")
	assert_true(bucket.take(2.0, 3, 0.5), "one token after 2 s")
	assert_false(bucket.take(2.0, 3, 0.5))
	# A long idle never banks more than the burst.
	assert_true(bucket.take(1000.0, 3, 0.5))
	assert_true(bucket.take(1000.0, 3, 0.5))
	assert_true(bucket.take(1000.0, 3, 0.5))
	assert_false(bucket.take(1000.0, 3, 0.5))


func test_history_ring_and_clear() -> void:
	var hist: ChatRules.History = ChatRules.History.new(SMALL_RING)
	for i: int in range(OVER_RING):
		hist.push(ChatRules.make_line(i, 1, 0, "A", 0, str(i)))
	var lines: Array[Dictionary] = hist.lines()
	assert_eq(lines.size(), SMALL_RING)
	assert_eq(lines[0][ChatRules.KEY_SEQ], OVER_RING - SMALL_RING)
	assert_eq(lines[SMALL_RING - 1][ChatRules.KEY_SEQ], OVER_RING - 1)
	lines.clear()
	assert_eq(hist.lines().size(), SMALL_RING, "lines() is a copy")
	hist.clear()
	assert_eq(hist.lines().size(), 0)


func test_chat_signals_exist() -> void:
	for sig: String in ["chat_send_requested", "chat_line_received", "chat_history_received", "chat_notice", "chat_input_opened", "chat_input_closed"]:
		assert_true(Events.has_signal(sig), sig)


func test_chat_open_is_keyboard_only() -> void:
	assert_true(InputMap.has_action("chat_open"))
	var keys: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(&"chat_open"):
		assert_true(event is InputEventKey, "no non-keyboard binding")
		keys.append((event as InputEventKey).physical_keycode)
	assert_true(keys.has(KEY_ENTER))
	assert_true(keys.has(KEY_KP_ENTER))
	assert_true(keys.has(KEY_T))


func test_clean_cut_strips_trailing_joiner() -> void:
	# "ab" + ZWJ + "c" cut to 3 code points would end in the ZWJ.
	var joined: String = "ab" + String.chr(0x200D) + "c"
	assert_eq(ChatRules.clean(joined, 3), "ab")
	assert_eq(ChatRules.clean(joined, 4), joined, "kept between visible characters")


func test_validate_rejects_control_characters_in_name_and_text() -> void:
	var cfg: ChatConfig = _cfg()
	for bad: String in ["a" + String.chr(0x07) + "b", "a
b", "a" + String.chr(0x202E) + "b", "a" + String.chr(0x200B)]:
		assert_false(ChatRules.validate_line(ChatRules.make_line(1, 2, 0, "Bo", 0, bad), cfg, MAX_NAME), "text " + bad.c_escape())
		assert_false(ChatRules.validate_line(ChatRules.make_line(1, 2, 0, bad, 0, "hi"), cfg, MAX_NAME), "name " + bad.c_escape())
	var joined: String = "a" + String.chr(0x200D) + "b"
	assert_true(ChatRules.validate_line(ChatRules.make_line(1, 2, 0, "Bo", 0, joined), cfg, MAX_NAME))
