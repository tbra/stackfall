class_name MatchFingerprint
extends RefCounted
## Bontago-1pi.46 R3 (docs/MATCH_RESET_AUDIT.md section 6): "after leaving a match and
## starting another, everything is as if freshly launched", made checkable.
##
## capture(main) reads everything a match can leave behind on a real game/Main.tscn
## instance and the persistent autoloads and presentation owners under it, into one flat
## Dictionary of plain values ("section.key" -> bool / int / String / float / Array of
## those). Floats are rounded to ROUND_STEP, so a fingerprint compares with == and prints
## as JSON. diff(a, b) lists the key paths that differ, "key: a != b".
##
## Excluded on purpose (audit D2-D4): monotonic ids, epochs and revisions, the music
## track/playlist position, wall clocks, the quality governor and F3 sim-lag. A
## fingerprint is only comparable between runs with the same config and rng_seed.
##
## Headless limits: GPU particles cannot be read, so this sees node/state, not pixels.
## Everything private is read through Object.get() so a renamed field shows up as a
## missing key (null) in the diff instead of a parse error here.

const ROUND_STEP: float = 0.0001
## Weather/sky/audio statics that only the Sfx and weather owners expose through fields.
const PHYSICS_TUNING_PATH: String = "res://config/physics_tuning.tres"
const WEATHER_PRESENTER_PATH: NodePath = ^"WeatherNet/WeatherPresenter"
const BREEZE_PRESENTER_PATH: NodePath = ^"WeatherNet/BreezeNet/BreezePresenter"
## Gamepad slot polled for a vibration left running (Rumble.stop_all()).
const RUMBLE_PROBE_DEVICE: int = 0


## Fingerprint of `main` (a game/Main.tscn instance) and the shared singletons.
static func capture(main: Node) -> Dictionary:
	var out: Dictionary = {}
	_capture_camera(main, out)
	_capture_field(main, out)
	_capture_sky(main, out)
	_capture_weather(out)
	_capture_rules(out)
	_capture_net(out)
	_capture_globals(main, out)
	_capture_audio(out)
	_capture_ui(main, out)
	_capture_wiring(main, out)
	return out


## Keys that move with wall-clock cadence or per-peer traffic, so two networked runs cannot
## match on them: dropped by without_volatile() for the ENet bench. The in-process unit test
## drives time by hand and compares every key.
const VOLATILE_PREFIXES: PackedStringArray = [
	"rules.countdown_left", "rules.timer_left", "rules.slot_timers", "rules.stats", "camera.shake",
	"net.cursors", "net.intents", "net.snapshot_bodies", "ui.hud_texts",
]


## `fingerprint` minus VOLATILE_PREFIXES.
static func without_volatile(fingerprint: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in fingerprint.keys():
		var skip: bool = false
		for prefix: String in VOLATILE_PREFIXES:
			if String(key).begins_with(prefix):
				skip = true
		if not skip:
			out[key] = fingerprint[key]
	return out


## Key paths whose values differ between `a` and `b` ("key: a != b"), sorted. A key present
## in only one side differs too. `tolerances` is a Dictionary mapping key prefixes to absolute
## tolerance values for numeric comparison; if a key starts with a tolerance entry, that tolerance
## overrides the exact comparison for numbers and number arrays.
static func diff(a: Dictionary, b: Dictionary, tolerances: Dictionary = {}) -> PackedStringArray:
	var keys: Dictionary = {}
	for key: Variant in a.keys():
		keys[key] = true
	for key: Variant in b.keys():
		keys[key] = true
	var sorted_keys: Array = keys.keys()
	sorted_keys.sort()
	var out: PackedStringArray = PackedStringArray()
	for key: Variant in sorted_keys:
		var in_a: bool = a.has(key)
		var in_b: bool = b.has(key)
		var key_str: String = String(key)
		var tolerance: float = 0.0
		for prefix: String in tolerances.keys():
			if key_str.begins_with(prefix):
				tolerance = float(tolerances[prefix])
				break
		if in_a and in_b and values_equal(a[key], b[key], tolerance):
			continue
		out.append("%s: %s != %s" % [key, _show(a, key), _show(b, key)])
	return out


## Same type-tolerant equality the diff uses: ints and floats compare by value (a
## fingerprint round-tripped through var_to_str/JSON turns ints into floats), arrays
## element-wise. When `tolerance` > 0, numeric comparisons use that absolute tolerance
## instead of the default rounding tolerance.
static func values_equal(a: Variant, b: Variant, tolerance: float = 0.0) -> bool:
	var a_num: bool = a is int or a is float
	var b_num: bool = b is int or b is float
	if a_num and b_num:
		var effective_tolerance: float = tolerance if tolerance > 0.0 else (ROUND_STEP * 0.5)
		return absf(float(a) - float(b)) <= effective_tolerance
	if a is Array and b is Array:
		var left: Array = a as Array
		var right: Array = b as Array
		if left.size() != right.size():
			return false
		for i: int in range(left.size()):
			if not values_equal(left[i], right[i], tolerance):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


static func _show(dict: Dictionary, key: Variant) -> String:
	return str(dict[key]) if dict.has(key) else "<missing>"


# --- rounding / flattening ------------------------------------------------------------

static func _r(value: float) -> float:
	return snappedf(value, ROUND_STEP)


static func _v2(v: Vector2) -> Array:
	return [_r(v.x), _r(v.y)]


static func _v3(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]


static func _col(c: Color) -> Array:
	return [_r(c.r), _r(c.g), _r(c.b), _r(c.a)]


static func _basis(b: Basis) -> Array:
	return _v3(b.x) + _v3(b.y) + _v3(b.z)


## A private field of `obj`, or null when `obj` is null/freed or has no such property.
static func _p(obj: Object, field: StringName) -> Variant:
	if obj == null or not is_instance_valid(obj):
		return null
	return obj.get(field)


static func _size_of(value: Variant) -> int:
	if value is Dictionary:
		return (value as Dictionary).size()
	if value is Array:
		return (value as Array).size()
	if value is PackedByteArray:
		return (value as PackedByteArray).size()
	return -1


## Float field that may be null (renamed / absent): -1 sentinel, not a silent 0.
static func _fp(obj: Object, field: StringName) -> float:
	var value: Variant = _p(obj, field)
	return _r(float(value)) if value is float or value is int else -1.0


static func _bp(obj: Object, field: StringName) -> bool:
	return bool(_p(obj, field))


## Script class name or engine class: stable across auto-named nodes.
static func _kind(node: Node) -> String:
	var script: Variant = node.get_script()
	if script is Script:
		var global_name: String = (script as Script).get_global_name()
		if global_name != "":
			return global_name
	return node.get_class()


## Sorted "Kind" list of live (not queued-for-deletion) children: a multiset by value.
static func _child_kinds(parent: Node) -> Array:
	var kinds: Array = []
	if parent == null or not is_instance_valid(parent):
		return kinds
	for child: Node in parent.get_children():
		if child.is_queued_for_deletion():
			continue
		kinds.append(_kind(child))
	kinds.sort()
	return kinds


# --- camera ---------------------------------------------------------------------------

static func _capture_camera(main: Node, out: Dictionary) -> void:
	var rig: CameraRig = _p(main, &"_camera_rig") as CameraRig
	if rig == null:
		out["camera.present"] = false
		return
	out["camera.present"] = true
	out["camera.distance"] = _r(rig.get_distance())
	out["camera.pitch"] = _r(rig.get_pitch())
	out["camera.yaw"] = _r(rig.get_yaw())
	out["camera.target"] = _v3(rig.get_target())
	var camera: Camera3D = rig.get_camera()
	out["camera.origin"] = _v3(camera.global_transform.origin)
	out["camera.basis"] = _basis(camera.global_transform.basis)
	out["camera.fov"] = _r(camera.fov)
	out["camera.shake_offset"] = _v3(rig.shake_offset())
	out["camera.shake_amplitude"] = _fp(rig, &"_shake_amplitude_m")
	out["camera.shake_elapsed"] = _fp(rig, &"_shake_elapsed_s")
	out["camera.peeking"] = rig.is_peeking()
	out["camera.peek_returning"] = _bp(rig, &"_peek_returning")
	out["camera.focus_action"] = str(_p(rig, &"_focus_action"))
	out["camera.focus_hold_elapsed"] = _fp(rig, &"_focus_hold_elapsed_s")
	out["camera.goal_cycle_index"] = int(_p(rig, &"_goal_cycle_index"))
	out["camera.block_held"] = rig.block_held
	out["camera.drop_recovering"] = _bp(rig, &"_drop_recovering")
	out["camera.local_slot"] = int(_p(rig, &"_local_slot"))
	out["camera.follow_position"] = _v3(_p(rig, &"_follow_position") as Vector3)
	out["camera.suppress_pad_home_focus"] = rig.suppress_pad_home_focus
	out["camera.view_tweens"] = _size_of(_p(rig, &"_view_tweens"))


# --- field ----------------------------------------------------------------------------

static func _capture_field(main: Node, out: Dictionary) -> void:
	var field: Field = _p(main, &"_field") as Field
	if field == null:
		out["field.present"] = false
		return
	out["field.present"] = true
	# The beacon collision body is created lazily by the first place_flags() and kept for
	# the session (Field._ensure_beacon_body); only what it still carries is match state.
	var field_kinds: Array = _child_kinds(field)
	field_kinds.erase("AnimatableBody3D")
	out["field.children"] = field_kinds
	var beacon_body: Node = field.beacon_body()
	out["field.beacon_shapes"] = _child_kinds(beacon_body).size() if beacon_body != null else 0
	out["field.tilt"] = _v2(field.tilt_vector())
	out["field.tilt_enabled"] = field.tilt_enabled()
	out["field.mirrored"] = _bp(field, &"_mirrored")
	out["field.physical_balance"] = _bp(field, &"_physical_balance_enabled")
	out["field.balance_torque"] = _v2(field.physical_balance_torque())
	out["field.registry_linked"] = _p(field, &"_registry") != null
	out["field.applied_holes"] = field.applied_hole_count()
	out["field.pending_toggles"] = field.pending_toggle_count()
	out["field.home_flags"] = field.home_flags().size()
	out["field.goal_flags"] = field.goal_flags().size()
	out["field.origin"] = _v3(field.global_transform.origin)
	out["field.basis"] = _basis(field.global_transform.basis)
	var overlay: TerritoryOverlay = field.overlay()
	out["field.overlay_present"] = overlay != null
	if overlay != null:
		out["field.overlay_wet"] = _fp(overlay, &"_wet_amount")
		out["field.overlay_wet_sheen"] = _fp(overlay, &"_wet_sheen_add")
		out["field.overlay_circles"] = overlay.circle_count()
		out["field.overlay_goals"] = overlay.goal_count()
		out["field.overlay_has_raster"] = _p(overlay, &"_raster") != null
		out["field.overlay_churning"] = _bp(overlay, &"_churning")
	var puddles: RainPuddles = field.get_node_or_null(RainPuddles.NODE_NAME) as RainPuddles
	out["field.puddles_present"] = puddles != null
	out["field.puddles_wetness"] = _r(puddles.wetness()) if puddles != null else 0.0


# --- sky ------------------------------------------------------------------------------

static func _capture_sky(main: Node, out: Dictionary) -> void:
	var skybox: Skybox = _p(main, &"_skybox") as Skybox
	if skybox == null:
		out["sky.present"] = false
		return
	out["sky.present"] = true
	out["sky.theme"] = skybox.theme.resource_path if skybox.theme != null else ""
	out["sky.config_theme_name"] = skybox.config.theme_name
	out["sky.cycle_active"] = skybox.is_cycle_active()
	out["sky.locked_phase"] = _r(skybox.locked_phase())
	out["sky.fallback_active"] = skybox.fallback_active
	out["sky.storm"] = _r(skybox.storm_sky_amount())
	out["sky.overcast"] = _r(skybox.overcast_amount())
	out["sky.cloud_overcast"] = _r(skybox.cloud_overcast_amount())
	out["sky.weather_fog"] = _r(skybox.weather_fog_amount())
	var environment: Environment = skybox.environment
	if environment != null:
		if environment.sky != null:
			out["sky.process_mode"] = int(environment.sky.process_mode)
		out["sky.fog_enabled"] = environment.fog_enabled
		out["sky.fog_color"] = _col(environment.fog_light_color)
		out["sky.fog_density"] = _r(environment.fog_density)
		out["sky.fog_sky_affect"] = _r(environment.fog_sky_affect)
		out["sky.volumetric_density"] = _r(environment.volumetric_fog_density)
		out["sky.ambient_energy"] = _r(environment.ambient_light_energy)
		out["sky.ambient_color"] = _col(environment.ambient_light_color)
		out["sky.background_energy"] = _r(environment.background_energy_multiplier)
	var light: DirectionalLight3D = null
	if not skybox.light_path.is_empty():
		light = skybox.get_node_or_null(skybox.light_path) as DirectionalLight3D
	if light != null:
		out["sky.light_basis"] = _basis(light.global_basis)
		out["sky.light_color"] = _col(light.light_color)
		# Bontago-mp0.132: the sun's cloud dimming (CloudShadows, from the live puff occlusion) follows
		# frame count and the drifting clouds, so it is transient by design; the fingerprint reads
		# the undimmed energy.
		out["sky.light_energy"] = _r(light.light_energy / maxf(skybox.sun_cloud_scale(), 0.001))
	var lighting: CloudLighting = skybox.cloud_lighting()
	if lighting != null:
		out["sky.cloud_night"] = _r(lighting.night_mix)
		out["sky.cloud_overcast_lit"] = _r(lighting.overcast)
		out["sky.cloud_storm"] = _r(lighting.storm)
		out["sky.cloud_dim"] = _r(lighting.dim)


# --- weather --------------------------------------------------------------------------

static func _capture_weather(out: Dictionary) -> void:
	var weather: MatchWeather = Match.weather()
	out["weather.running"] = weather.is_running()
	out["weather.active_id"] = str(weather.active_id())
	out["weather.intensity"] = _r(weather.active_intensity())
	out["weather.mode"] = weather.mode()
	out["weather.schedule_phase"] = weather.schedule_phase()
	out["weather.constant"] = weather.is_constant()
	out["weather.debug_override"] = str(weather.debug_override())
	out["weather.event_index"] = weather.event_index()
	var breeze: BreezeEffect = weather.breeze()
	out["weather.breeze_running"] = breeze.is_running()
	out["weather.breeze_enabled"] = breeze.is_enabled()
	out["weather.breeze_gusts"] = breeze.gust_count()
	var presenter: WeatherPresenter = MatchNet.get_node_or_null(WEATHER_PRESENTER_PATH) as WeatherPresenter
	out["weather.presenter_present"] = presenter != null
	if presenter != null:
		out["weather.presenter_active"] = presenter.active_count()
		var ceiling: CloudCeiling = presenter.cloud_ceiling()
		out["weather.ceiling_present"] = ceiling != null
		if ceiling != null:
			out["weather.ceiling_amount"] = _r(ceiling.amount())
			out["weather.ceiling_storm"] = _r(ceiling.storm_amount())
			out["weather.ceiling_overcast"] = _r(ceiling.overcast())
			out["weather.ceiling_targets"] = _size_of(_p(ceiling, &"_targets"))
			out["weather.ceiling_pushed_storm"] = _fp(ceiling, &"_pushed_storm")
			out["weather.ceiling_pushed_overcast"] = _fp(ceiling, &"_pushed_overcast")
	var breeze_presenter: BreezePresenter = MatchNet.get_node_or_null(BREEZE_PRESENTER_PATH) as BreezePresenter
	out["weather.breeze_presenter_live"] = breeze_presenter.live_count() if breeze_presenter != null else -1
	out["weather.fog_shader"] = [
		_r(WeatherFogShader.strength), _r(WeatherFogShader.begin_m), _r(WeatherFogShader.end_m),
		_col(WeatherFogShader.color),
	]


# --- rules ----------------------------------------------------------------------------

static func _capture_rules(out: Dictionary) -> void:
	out["rules.state"] = int(Match.state())
	out["rules.slots"] = Match.slot_count()
	out["rules.countdown_left"] = _r(Match.countdown_remaining())
	out["rules.timer_left"] = _r(Match.match_timer_left())
	out["rules.winner"] = Match.winner_team()
	var circles: Dictionary = Match.circle_render_arrays()
	out["rules.circles"] = [
		_size_of(circles.get("xs")), _size_of(circles.get("zs")), _size_of(circles.get("radii")),
		_size_of(circles.get("teams")), _size_of(circles.get("goal_positions")),
		_size_of(circles.get("goal_radii")), bool(circles.get("argmax_mode", false)),
	]
	out["rules.gift_states"] = Match.gift_states().size()
	var crates: Variant = _p(Match._gifts, &"_crates")
	out["rules.gift_crates"] = _size_of(crates)
	out["rules.gift_queues"] = _size_of(_p(Match._gifts, &"_pending_queues"))
	out["rules.gift_held"] = _size_of(_p(Match._gifts, &"_held_specials"))
	out["rules.gift_slots"] = _size_of(_p(Match._gifts, &"_gift_slots"))
	out["rules.glue_tracked"] = _size_of(_p(Match._gifts, &"_glue_drops"))
	var items: Array = []
	var timers: Array = []
	for slot_id: int in range(Match.slot_count()):
		var held: BlockShape = Match.held_shape(slot_id)
		var next: BlockShape = Match.next_shape(slot_id)
		items.append([
			str(held.id) if held != null else "",
			str(next.id) if next != null else "",
			str(Match.held_special(slot_id)),
			str(Match.next_special(slot_id)),
			Match.pending_special_count(slot_id),
			Match.glue_drops_left(slot_id),
			Match.gift_slot_count(slot_id),
			Match.qol_backlog_count(slot_id),
			Match.qol_timer_paused(slot_id),
			Match.is_release_locked(slot_id),
		])
		timers.append(_r(Match.feed_time_left(slot_id)))
	out["rules.slot_items"] = items
	out["rules.slot_timers"] = timers
	out["rules.stats"] = [
		_size_of(_p(Match._stats, &"_blocks_placed")), _fp(Match._stats, &"_elapsed"),
		str(_p(Match._stats, &"_blocks_placed")), str(_p(Match._stats, &"_blocks_lost")),
		str(_p(Match._stats, &"_gifts_claimed")), str(_p(Match._stats, &"_specials_used")),
		str(_p(Match._stats, &"_eliminated_at")),
	]
	out["rules.blocks_spawned"] = Match.blocks_spawned()
	var registry: BlockRegistry = Match.registry()
	# Match keeps its registered world after a match ends (a launch has none yet): count only blocks.
	out["rules.registry_blocks"] = registry.all_blocks().size() if registry != null else 0
	var blocks_parent: Node3D = Match.blocks_parent()
	out["rules.blocks_parent_children"] = _child_kinds(blocks_parent)
	out["rules.match_children"] = _child_kinds(Match)
	out["rules.cat"] = Match.active_cat() != null
	out["rules.sandbox_territory_mode"] = Match.sandbox_territory_mode()
	out["rules.sandbox_territory_cache"] = _bp(Match, &"_territory_cache_enabled")
	out["rules.sandbox_territory_profile"] = _bp(Match, &"_sandbox_territory_profile_enabled")
	out["rules.feed_timer_enabled"] = Match.feed_timer_enabled()
	out["rules.config_present"] = Match.config != null


# --- net ------------------------------------------------------------------------------

static func _capture_net(out: Dictionary) -> void:
	out["net.mode"] = int(Net.mode())
	out["net.local_slot"] = Net.local_slot()
	var peer_slots: Array = []
	for peer_id: int in Net.peer_ids():
		peer_slots.append(Net.slot_of_peer(peer_id))
	peer_slots.sort()
	out["net.peer_slots"] = peer_slots
	out["net.accepting_joins"] = Net.accepting_joins()
	out["net.match_in_progress"] = Net.match_in_progress()
	out["net.snapshot_running"] = SnapshotSync.is_running()
	out["net.snapshot_bodies"] = _size_of(_p(SnapshotSync, &"_bodies"))
	out["net.snapshot_has_interpolator"] = _p(SnapshotSync, &"_interpolator") != null
	# DECISION: MatchNet's per-match counters are only cleared by reset_counters() when the
	# next host match reaches LOADING (and by a client's net_match_start), so while the
	# session sits in the lobby they still hold the last match's numbers by design; they are
	# fingerprinted from LOADING on. The raster-diff cache is excluded: MatchNet._process fills
	# it on wall-clock cadence, so it differs run to run.
	if Match.state() != Match.State.LOBBY:
		out["net.cursors"] = _size_of(_p(MatchNet, &"_cursors"))
		out["net.spawned_ids"] = _size_of(_p(MatchNet, &"_spawned_net_ids"))
		out["net.replay_pending"] = _size_of(_p(MatchNet, &"_replay_pending"))
		out["net.intents"] = [
			_size_of(_p(MatchNet, &"_intents_sent")), _size_of(_p(MatchNet, &"_intents_accepted")),
			_size_of(_p(MatchNet, &"_intents_refused")), _size_of(_p(MatchNet, &"_auto_drops")),
		]
		out["net.capture_progress"] = [int(_p(MatchNet, &"_capture_team")), _fp(MatchNet, &"_capture_progress")]


# --- globals and statics --------------------------------------------------------------

static func _capture_globals(main: Node, out: Dictionary) -> void:
	out["globals.time_scale"] = _r(Engine.time_scale)
	out["globals.paused"] = main.get_tree().paused if main.is_inside_tree() else false
	var tuning: PhysicsTuning = load(PHYSICS_TUNING_PATH) as PhysicsTuning
	out["globals.gravity_multiplier"] = _r(tuning.gravity_multiplier)
	out["globals.awake_blocks"] = Block.awake_blocks().size()
	out["globals.slept_blocks"] = _size_of(_p(Block, &"_slept_blocks"))
	out["globals.stable_manager"] = StableBlockManager.active != null and is_instance_valid(StableBlockManager.active)
	out["globals.mouse_mode"] = int(Input.mouse_mode)


# --- audio ----------------------------------------------------------------------------

static func _capture_audio(out: Dictionary) -> void:
	out["audio.music_context"] = str(_p(Sfx, &"_music_context"))
	out["audio.tense_active"] = _bp(Sfx, &"_tense_stem_is_active")
	var tween: Variant = _p(Sfx, &"_music_crossfade_tween")
	out["audio.crossfade_live"] = tween is Tween and (tween as Tween).is_valid()
	# Stem volumes are only a calm/tense switch when the contextual playlist is off; with
	# it on the envelope owns the volume and moves with the wall clock.
	if not Sfx.config.contextual_music_enabled:
		var calm: Variant = _p(Sfx, &"_music_player")
		var tense: Variant = _p(Sfx, &"_tense_music_player")
		out["audio.calm_db"] = _r((calm as AudioStreamPlayer).volume_db) if calm is AudioStreamPlayer else 0.0
		out["audio.tense_db"] = _r((tense as AudioStreamPlayer).volume_db) if tense is AudioStreamPlayer else 0.0
	out["audio.rumble"] = _v2(Input.get_joy_vibration_strength(RUMBLE_PROBE_DEVICE))


# --- persistent UI / Main state -------------------------------------------------------

static func _capture_ui(main: Node, out: Dictionary) -> void:
	# _first_territory_ready is left out: it is only re-armed by the LOBBY -> LOADING lobby path
	# and read only inside that path's _finish_loading_when_ready().
	for flag: StringName in [&"_world_built", &"_world_building", &"_start_pending"]:
		out["ui.main%s" % flag] = _bp(main, flag)
	for holder: StringName in [&"_main_menu", &"_lobby", &"_hot_seat", &"_sandbox", &"_tutorial",
			&"_remote_cursors", &"_debug_overlay", &"_stable_block_manager"]:
		var node: Variant = _p(main, holder)
		out["ui.main%s" % holder] = node != null and is_instance_valid(node)
	out["ui.bot_controllers"] = _size_of(_p(main, &"_bot_controllers"))
	var loading: LoadingScreen = _p(main, &"_loading_screen") as LoadingScreen
	if loading != null:
		out["ui.loading_visible"] = loading.visible
		out["ui.loading_pending"] = loading.is_pending()
		out["ui.loading_opacity"] = _r(loading.overlay_opacity())
		out["ui.loading_layer"] = loading.overlay_layer_visible()
		out["ui.loading_timed_out"] = loading.timed_out()
	var results: ResultsScreen = _p(main, &"_results_screen") as ResultsScreen
	if results != null:
		out["ui.results_visible"] = results.visible
	var pause: PauseMenu = _p(main, &"_pause_menu") as PauseMenu
	if pause != null:
		out["ui.pause_visible"] = pause.visible
		out["ui.pause_suppressed"] = pause.suppressed
	# What the player reads on the match HUD: every visible, non-empty label text, sorted.
	var texts: Array = []
	var hot_seat: Node = _p(main, &"_hot_seat") as Node
	if hot_seat != null and is_instance_valid(hot_seat):
		for label: Node in hot_seat.find_children("*", "Label", true, false):
			var control: Label = label as Label
			if control.is_visible_in_tree() and control.text != "":
				texts.append(control.text)
	texts.sort()
	out["ui.hud_texts"] = texts


# --- wiring ---------------------------------------------------------------------------

static func _capture_wiring(main: Node, out: Dictionary) -> void:
	# Every Events signal's connection count: a per-match connect that is never undone
	# (or a persistent one made twice) shows up as a count that grows from match to match.
	for info: Dictionary in Events.get_signal_list():
		var signal_name: StringName = StringName(String(info["name"]))
		out["wiring.events.%s" % signal_name] = Events.get_signal_connection_list(signal_name).size()
	out["wiring.main_children"] = _child_kinds(main)
	# Every node under Main by class path (Field/Area3D/CollisionShape3D): names the kind of
	# node a leak adds. Skipped: the lazily-built Field beacon body and the
	# BlockEffectsManager's pooled bursts/trails, both caches that persist by design.
	var counts: Dictionary = {}
	if main.is_inside_tree():
		var field: Field = _p(main, &"_field") as Field
		var skip: Node = field.beacon_body() if field != null else null
		_count_nodes(main, "", skip, counts)
	for key: Variant in counts.keys():
		out["wiring.node.%s" % key] = counts[key]


const POOLED_CACHE_KINDS: PackedStringArray = ["BlockEffectsManager"]


static func _count_nodes(node: Node, parent_path: String, skip: Node, counts: Dictionary) -> void:
	for child: Node in node.get_children():
		if child.is_queued_for_deletion() or child == skip:
			continue
		var kind: String = _kind(child)
		# Segments are classes, not node names: a rebuilt child (Skybox puffs, the Field's
		# kill plane) can come back under another name, which is not a state difference.
		var path: String = kind if parent_path == "" else parent_path + "/" + kind
		var key: String = path
		counts[key] = int(counts.get(key, 0)) + 1
		if kind not in POOLED_CACHE_KINDS:
			_count_nodes(child, path, skip, counts)
