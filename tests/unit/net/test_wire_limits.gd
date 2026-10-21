extends GutTest
## core/net/WireLimits.gd: the wire id, length and arity checks whose limits live in NetConfig.

var _config: NetConfig


func before_each() -> void:
	_config = NetConfig.new()


# --- special_id_ok -------------------------------------------------------------

func test_special_id_accepts_shipped_style_ids() -> void:
	assert_true(WireLimits.special_id_ok(&"rocket", _config))
	assert_true(WireLimits.special_id_ok(&"Glue_Coat_2", _config))


func test_special_id_refuses_empty_and_bad_characters() -> void:
	assert_false(WireLimits.special_id_ok(&"", _config))
	assert_false(WireLimits.special_id_ok(&"a b", _config))
	assert_false(WireLimits.special_id_ok(&"a-b", _config))
	assert_false(WireLimits.special_id_ok(&"na\u00efve", _config))
	assert_false(WireLimits.special_id_ok(&"a/b", _config))


func test_special_id_character_classes_include_both_ends_and_exclude_their_neighbours() -> void:
	for accepted: String in ["a", "z", "A", "Z", "0", "9", "_"]:
		assert_true(WireLimits.special_id_ok(StringName(accepted), _config), "%s is a legal id character" % accepted)
	for refused: String in ["`", "{", "@", "[", "/", ":", "^", "`"]:
		assert_false(WireLimits.special_id_ok(StringName(refused), _config), "%s is not" % refused)


func test_special_id_length_follows_the_config() -> void:
	var at_cap: String = "a".repeat(_config.special_id_max_length)
	assert_true(WireLimits.special_id_ok(StringName(at_cap), _config), "exactly the cap passes")
	assert_false(WireLimits.special_id_ok(StringName(at_cap + "a"), _config), "one past the cap is refused")
	_config.special_id_max_length = 4
	assert_true(WireLimits.special_id_ok(&"abcd", _config))
	assert_false(WireLimits.special_id_ok(&"abcde", _config))


# --- reject_reason_clamped -------------------------------------------------------

func test_reject_reason_is_cut_to_the_configured_length() -> void:
	assert_eq(WireLimits.reject_reason_clamped("short", _config), "short")
	var long_reason: String = "x".repeat(_config.reject_reason_max_length + 20)
	assert_eq(WireLimits.reject_reason_clamped(long_reason, _config).length(), _config.reject_reason_max_length)
	_config.reject_reason_max_length = 3
	assert_eq(WireLimits.reject_reason_clamped("abcdef", _config), "abc")
	assert_eq(WireLimits.reject_reason_clamped("", _config), "")


# --- cat_duration_clamped --------------------------------------------------------

func test_cat_duration_is_clamped_into_range() -> void:
	assert_eq(WireLimits.cat_duration_clamped(5.0, _config), 5.0)
	assert_eq(WireLimits.cat_duration_clamped(_config.cat_duration_max_s + 100.0, _config), _config.cat_duration_max_s)
	assert_eq(WireLimits.cat_duration_clamped(-3.0, _config), 0.0)


func test_cat_duration_non_finite_comes_back_zero() -> void:
	assert_eq(WireLimits.cat_duration_clamped(NAN, _config), 0.0)
	assert_eq(WireLimits.cat_duration_clamped(INF, _config), 0.0)
	assert_eq(WireLimits.cat_duration_clamped(-INF, _config), 0.0)


# --- args_shape_ok ---------------------------------------------------------------

func test_args_shape_arity_must_match() -> void:
	var shape: Array = [TYPE_INT, TYPE_VECTOR3]
	assert_true(WireLimits.args_shape_ok([1, Vector3.ONE], shape))
	assert_false(WireLimits.args_shape_ok([1], shape), "too few")
	assert_false(WireLimits.args_shape_ok([1, Vector3.ONE, 2], shape), "too many")
	assert_true(WireLimits.args_shape_ok([], []), "an event with no arguments")
	assert_false(WireLimits.args_shape_ok([1], []))


func test_args_shape_checks_typeof_per_entry() -> void:
	var shape: Array = [TYPE_INT, TYPE_STRING]
	assert_true(WireLimits.args_shape_ok([3, "x"], shape))
	assert_false(WireLimits.args_shape_ok(["3", "x"], shape), "a string where an int is wanted")
	assert_false(WireLimits.args_shape_ok([3, 4], shape), "an int where a string is wanted")
	assert_false(WireLimits.args_shape_ok([3.0, "x"], shape), "a float does not pass for an int")
	assert_false(WireLimits.args_shape_ok([null, "x"], shape))


func test_args_shape_leniencies_match_the_applier() -> void:
	assert_true(WireLimits.args_shape_ok([4], [TYPE_FLOAT]), "an int passes for a float")
	assert_true(WireLimits.args_shape_ok([&"a"], [TYPE_STRING]), "a StringName passes for a String")
	assert_true(WireLimits.args_shape_ok(["a"], [TYPE_STRING_NAME]), "and the other way round")
	assert_true(WireLimits.args_shape_ok([Vector2.ZERO, 1], [TYPE_NIL, TYPE_NIL]), "TYPE_NIL means any type")
