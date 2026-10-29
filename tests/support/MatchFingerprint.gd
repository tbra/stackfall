class_name MatchFingerprint
extends RefCounted
## R3 (docs/MATCH_RESET_AUDIT.md section 6): "after leaving a match and
## starting another, everything is as if freshly launched", made checkable.
##
## capture(main) reads everything a match can leave behind on a real game/main/Main.tscn
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
## Main is read through the scene tree only (child nodes found by script class), never through
## its private fields. Other objects' private fields are
## read through Object.get() so a renamed field shows up as a missing key (null) in the diff
## instead of a parse error here.

const ROUND_STEP: float = 0.0001
## Weather/sky/audio statics that only the Sfx and weather owners expose through fields.
const PHYSICS_TUNING_PATH: String = "res://config/physics/physics_tuning.tres"
const WEATHER_PRESENTER_PATH: NodePath = ^"WeatherNet/WeatherPresenter"
const BREEZE_PRESENTER_PATH: NodePath = ^"WeatherNet/BreezeNet/BreezePresenter"
## Gamepad slot polled for a vibration left running (Rumble.stop_all()).
const RUMBLE_PROBE_DEVICE: int = 0


## Fingerprint of `main` (a game/main/Main.tscn instance) and the shared singletons.
static func capture(main: Node) -> Dictionary:
	var out: Dictionary = {}
	# MF5: the four overlays are created lazily; build them first so a
	# fresh launch and a session that already needed some compare like for like.
	if main != null and main.has_method(&"_ensure_overlays"):
		main.call(&"_ensure_overlays")
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
## the loading overlay (its fade state and the backdrop SubViewport nodes it
## frees when the fade ends) is a transient: under machine load the fade can still be running
## at COUNTDOWN + 0.5 s on one peer and not on the other, so it is excluded too.
# DECISION: exclude the transient rather than wait for it, since a loaded peer's fade can
# outlast the whole countdown and a wait would then never capture.
## The disc's sync_to_physics drops once the tilt spring has rested for its hold time, counted
## in real physics ticks, so at COUNTDOWN + 0.5 s it also depends on machine load.
const VOLATILE_PREFIXES: PackedStringArray = [
	"rules.countdown_left", "rules.timer_left", "rules.slot_timers", "rules.stats", "camera.shake",
	"net.cursors", "net.intents", "net.snapshot_bodies", "ui.hud_texts",
	"ui.loading_", "wiring.node.LoadingScreen", "field.sync_to_physics",
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


## First live direct child of `parent` whose script class (or engine class) is `kind`, else null.
static func _child_of_kind(parent: Node, kind: String) -> Node:
	if parent == null or not is_instance_valid(parent):
		return null
	for child: Node in parent.get_children():
		if not child.is_queued_for_deletion() and _kind(child) == kind:
			return child
	return null


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
	var rig: CameraRig = _child_of_kind(main, "CameraRig") as CameraRig
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
	out["camera.drop_recovering"] = _bp(rig, &"_drop_recovering")
	out["camera.local_slot"] = int(_p(rig, &"_local_slot"))
	out["camera.follow_position"] = _v3(_p(rig, &"_follow_position") as Vector3)
	out["camera.suppress_pad_home_focus"] = rig.suppress_pad_home_focus
	out["camera.view_tweens"] = _size_of(_p(rig, &"_view_tweens"))


# --- field ----------------------------------------------------------------------------

static func _capture_field(main: Node, out: Dictionary) -> void:
	var field: Field = _child_of_kind(main, "Field") as Field
	if field == null:
		out["field.present"] = false
		return
	out["field.present"] = true
	# The beacon collision body is created lazily by the first place_flags() and kept for
	# the session (Field._ensure_beacon_body); only what it still carries is match state.
	var field_kinds: Array = _child_kinds(field)
	field_kinds.erase("AnimatableBody3D")
	out["field.children"] = field_kinds
	var beacon_body: Node = field.find_child(&"BeaconBody", true, false)
	out["field.beacon_shapes"] = _child_kinds(beacon_body).size() if beacon_body != null else 0
	out["field.tilt"] = _v2(field.tilt_vector())
	out["field.sync_to_physics"] = field.sync_to_physics
	out["field.applied_holes"] = field.applied_hole_count()
	out["field.home_flags"] = field.home_flags().size()
	out["field.goal_flags"] = field.goal_flags().size()
	out["field.origin"] = _v3(field.global_transform.origin)
	out["field.basis"] = _basis(field.global_transform.basis)
	var overlay: TerritoryOverlay = field.overlay()
	out["field.overlay_present"] = overlay != null
	if overlay != null:
		out["field.overlay_wet"] = _fp(overlay, &"_wet_amount")
		out["field.overlay_wet_sheen"] = _fp(overlay, &"_wet_sheen_add")
		out["field.overlay_circles"] = int(_p(overlay, &"_circle_count"))
		out["field.overlay_goals"] = overlay.goal_count()
		out["field.overlay_has_raster"] = _p(overlay, &"_raster") != null
		out["field.overlay_churning"] = _bp(overlay, &"_churning")
	var puddles: RainPuddles = field.get_node_or_null(RainPuddles.NODE_NAME) as RainPuddles
	out["field.puddles_present"] = puddles != null


# --- sky ------------------------------------------------------------------------------

static func _capture_sky(main: Node, out: Dictionary) -> void:
	var skybox: Skybox = _child_of_kind(main, "Skybox") as Skybox
	if skybox == null:
		out["sky.present"] = false
		return
	out["sky.present"] = true
	SkyTestKit.settle(skybox)
	# Resolved sky identity: the sky definition in use, the launch sky id, and (below) the cycle flag and
	# locked phase that id resolves to; a sky that did not reset differs in at least one of them.
	out["sky.def_path"] = skybox.sky_def.resource_path if skybox.sky_def != null else ""
	out["sky.config_theme_name"] = skybox.config.theme_name
	out["sky.variation_seed"] = skybox.variation_seed()
	out["sky.cycle_active"] = skybox.is_cycle_active()
	out["sky.locked_phase"] = _r(skybox.locked_phase())
	var weather_lighting: CloudLighting = (skybox.get_node("CloudSea") as CloudSea).lighting
	out["sky.storm"] = _r(weather_lighting.storm)
	out["sky.overcast"] = _r(weather_lighting.overcast)
	var environment: Environment = skybox.environment
	if environment != null:
		if environment.sky != null:
			out["sky.process_mode"] = int(environment.sky.process_mode)
		out["sky.fog_mode"] = int(environment.fog_mode)
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
	var sea: CloudSea = skybox.get_node_or_null("CloudSea") as CloudSea
	var lighting: CloudLighting = sea.lighting if sea != null else null
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
	out["weather.debug_override"] = str(weather.debug_override())
	out["weather.event_index"] = weather.event_index()
	var breeze: BreezeEffect = weather.breeze()
	out["weather.breeze_running"] = breeze.is_running()
	out["weather.breeze_enabled"] = breeze.is_enabled()
	out["weather.breeze_gusts"] = breeze.gusts().size()
	var presenter: WeatherPresenter = MatchNet.get_node_or_null(WEATHER_PRESENTER_PATH) as WeatherPresenter
	out["weather.presenter_present"] = presenter != null
	if presenter != null:
		var ceiling: CloudCeiling = presenter.get_node("CloudCeiling") as CloudCeiling
		out["weather.ceiling_present"] = ceiling != null
		if ceiling != null:
			out["weather.ceiling_amount"] = _fp(ceiling, &"_amount")
			out["weather.ceiling_storm"] = _fp(ceiling, &"_storm_amount")
			out["weather.ceiling_targets"] = _size_of(_p(ceiling, &"_targets"))
			out["weather.ceiling_pushed_storm"] = _fp(ceiling, &"_pushed_storm")
			out["weather.ceiling_pushed_overcast"] = _fp(ceiling, &"_pushed_overcast")
	var breeze_presenter: BreezePresenter = MatchNet.get_node_or_null(BREEZE_PRESENTER_PATH) as BreezePresenter
	var live_gusts: int = -1
	if breeze_presenter != null:
		live_gusts = 0
		for child: Node in breeze_presenter.get_children():
			if child is GustPresentation and not child.is_queued_for_deletion():
				live_gusts += 1
	out["weather.breeze_presenter_live"] = live_gusts
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
	out["rules.gift_crates"] = Match.gift_states().size()
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
	var registry: BlockRegistry = Match.registry()
	# Match keeps its registered world after a match ends (a launch has none yet): count only blocks.
	out["rules.registry_blocks"] = registry.all_blocks().size() if registry != null else 0
	var blocks_parent: Node3D = Match.blocks_parent()
	out["rules.blocks_parent_children"] = _child_kinds(blocks_parent)
	out["rules.match_children"] = _child_kinds(Match)
	out["rules.cat"] = Match.active_cat() != null
	out["rules.sandbox_territory_cache"] = _bp(Match, &"_territory_cache_enabled")
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
		var cursor_slots: int = 0
		for slot_id: int in Match.slot_count():
			if not MatchNet.cursor_for_slot(slot_id).is_empty():
				cursor_slots += 1
		out["net.cursors"] = cursor_slots
		var intents: Array = []
		for slot_id: int in Match.slot_count():
			intents.append([MatchNet.intents_sent(slot_id), MatchNet.intents_accepted(slot_id), MatchNet.intents_refused(slot_id)])
		out["net.intents"] = intents
		# The claim progress is not fingerprinted: it is only broadcast (Events.goal_capture_progress)
		# and no public member holds it between emissions.


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
	# Stem targets are the public view of the calm/tense switch. They only move when the stems
	# are installed (enable_stems) and the contextual playlist is off; with it on the envelope
	# owns the volume and moves with the wall clock.
	# Not fingerprinted (no public observable): the music context and a live crossfade Tween.
	out["audio.calm_target_db"] = _r(Sfx.calm_stem_target_volume_db())
	out["audio.tense_target_db"] = _r(Sfx.tense_stem_target_volume_db())
	out["audio.rumble"] = _v2(Input.get_joy_vibration_strength(RUMBLE_PROBE_DEVICE))


## Turns the adaptive stems on through the public settings signal: contextual music off, no
## bundled theme, two shipped wavs standing in for the calm and tense stem files. Returns the
## state restore_stems() puts back.
static func enable_stems() -> Dictionary:
	var config: AudioConfig = Sfx.config
	var saved: Dictionary = {
		"contextual": config.contextual_music_enabled,
		"theme": config.bundled_theme,
		"theme_path": config.bundled_theme_path,
		"calm": config.music_stem_calm_file,
		"tense": config.music_stem_tense_file,
	}
	config.contextual_music_enabled = false
	config.bundled_theme = null
	config.bundled_theme_path = ""
	config.music_stem_calm_file = config.thud_files[0]
	config.music_stem_tense_file = config.thud_files[1]
	Settings.audio_settings_changed.emit()
	return saved


static func restore_stems(saved: Dictionary) -> void:
	if saved.is_empty():
		return
	Sfx.reset_match_audio()
	var config: AudioConfig = Sfx.config
	config.contextual_music_enabled = saved["contextual"]
	config.bundled_theme = saved["theme"]
	config.bundled_theme_path = saved["theme_path"]
	config.music_stem_calm_file = saved["calm"]
	config.music_stem_tense_file = saved["tense"]
	Settings.audio_settings_changed.emit()


# --- persistent UI / Main state -------------------------------------------------------

static func _capture_ui(main: Node, out: Dictionary) -> void:
	# the flow's _first_territory_ready is left out: it is only re-armed by the LOBBY -> LOADING lobby path
	# and read only inside that path's _finish_loading_when_ready().
	out["ui.main_world_built"] = MainNodes.world_is_built(main)
	# Node holders: the live child of that class under Main (the key keeps the old field name).
	var holders: Dictionary = {
		&"_main_menu": "MainMenu", &"_lobby": "Lobby", &"_local_player": "LocalPlayer",
		&"_sandbox": "Sandbox", &"_tutorial": "Tutorial", &"_remote_cursors": "RemoteCursors",
		&"_debug_overlay": "NetDebugOverlay", &"_stable_block_manager": "StableBlockManager",
	}
	for holder: StringName in holders.keys():
		out["ui.main%s" % holder] = _child_of_kind(main, holders[holder]) != null
	var bots: int = 0
	for child: Node in main.get_children():
		if child is BotController and not child.is_queued_for_deletion():
			bots += 1
	out["ui.bot_controllers"] = bots
	var loading: LoadingScreen = _child_of_kind(main, "LoadingScreen") as LoadingScreen
	if loading != null:
		out["ui.loading_visible"] = loading.visible
		out["ui.loading_pending"] = loading.is_pending()
	var results: ResultsScreen = _child_of_kind(main, "ResultsScreen") as ResultsScreen
	if results != null:
		out["ui.results_visible"] = results.visible
	var pause: PauseMenu = _child_of_kind(main, "PauseMenu") as PauseMenu
	if pause != null:
		out["ui.pause_visible"] = pause.visible
		out["ui.pause_suppressed"] = pause.suppressed
	# What the player reads on the match HUD: every visible, non-empty label text, sorted.
	var texts: Array = []
	var local_player: Node = _child_of_kind(main, "LocalPlayer")
	if local_player != null and is_instance_valid(local_player):
		for label: Node in local_player.find_children("*", "Label", true, false):
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
		var field: Field = _child_of_kind(main, "Field") as Field
		var skip: Node = field.find_child(&"BeaconBody", true, false) if field != null else null
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
