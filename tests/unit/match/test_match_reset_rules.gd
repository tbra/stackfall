extends GutTest
## R2 (docs/MATCH_RESET_AUDIT.md G3, G6 + rumble): the rules and
## autoload carry-overs behind "a new match after leaving is indistinguishable from
## a freshly launched one".

const SFX_SCRIPT: GDScript = preload("res://autoload/Sfx.gd")

var _tiny_map: MapDef
var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry

var _sfx: Node
var _audio_config: AudioConfig
var _tmp_dir: String


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	if _tmp_dir != "" and DirAccess.dir_exists_absolute(_tmp_dir):
		for filename: String in DirAccess.get_files_at(_tmp_dir):
			DirAccess.remove_absolute(_tmp_dir.path_join(filename))


# --- helpers ------------------------------------------------------------------

func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	# Script swap first (see test_match_net.gd's _config()).
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.rng_seed = 4242
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func _start_playing(player_count: int = 2) -> void:
	Match.start_match(_config(player_count))
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture should reach PLAYING")


func _circle_count() -> int:
	return (Match.circle_render_arrays()["xs"] as PackedFloat32Array).size()


## A client's match side: a mirror raster and the circles its replica port was handed.
class ClientSide extends RefCounted:
	var mirror: TerritoryRaster = null
	var xz_bound: float = 0.0
	var radius_max: float = 0.0
	var received: Dictionary = {}

	func raster() -> TerritoryRaster:
		return mirror

	func circle_wire_xz_bound() -> float:
		return xz_bound

	func circle_wire_radius_max() -> float:
		return radius_max

	func apply_replicated_territory(
		_cells: PackedInt32Array, owners: PackedByteArray, states: PackedByteArray, _full: bool,
		xs: PackedFloat32Array, zs: PackedFloat32Array, radii: PackedFloat32Array,
		teams: PackedInt32Array, goal_positions: PackedVector2Array, _goal_radii: PackedFloat32Array,
		argmax_mode: bool
	) -> void:
		mirror.apply_replicated_state(owners, states)
		received = {
			"xs": xs, "zs": zs, "radii": radii, "teams": teams,
			"goal_positions": goal_positions, "argmax_mode": argmax_mode,
		}


## The circle list the host's territory packet carries right now, as a client receives it. Empty
## when the client refused the packet.
func _decoded_circle_payload() -> Dictionary:
	var net_config: NetConfig = NetConfig.new()
	var host: TerritoryReplicator = TerritoryReplicator.new(
		MatchHostPort.new(Match), MatchReplicaPort.new(Match), net_config
	)
	var raster: TerritoryRaster = Match.raster()
	var side: ClientSide = ClientSide.new()
	side.mirror = TerritoryRaster.new(raster.grid(), raster.tuning())
	side.xz_bound = Match.circle_wire_xz_bound()
	side.radius_max = Match.circle_wire_radius_max()
	var client: TerritoryReplicator = TerritoryReplicator.new(
		MatchHostPort.new(side, PackedStringArray(["raster", "circle_wire_xz_bound", "circle_wire_radius_max"])),
		MatchReplicaPort.new(side, PackedStringArray(["apply_replicated_territory"])),
		net_config
	)
	if not client.apply(host.encode_full()):
		return {}
	return side.received


func _assert_render_arrays_empty(context: String) -> void:
	var arrays: Dictionary = Match.circle_render_arrays()
	assert_eq((arrays["xs"] as PackedFloat32Array).size(), 0, "%s: xs empty" % context)
	assert_eq((arrays["zs"] as PackedFloat32Array).size(), 0, "%s: zs empty" % context)
	assert_eq((arrays["radii"] as PackedFloat32Array).size(), 0, "%s: radii empty" % context)
	assert_eq((arrays["teams"] as PackedInt32Array).size(), 0, "%s: teams empty" % context)
	assert_false(bool(arrays["argmax_mode"]), "%s: argmax_mode back to default" % context)


# --- G3: stale influence circles -----------------------------------------------

func test_every_reset_path_drops_the_previous_matchs_circles() -> void:
	# Merged: clear_circles(), abort_match(), a direct start_match() from PLAYING
	# (no explicit abort) and _build_territory() alone (the second guard).
	for path: StringName in [&"clear_circles", &"abort_match", &"start_match_from_playing", &"build_territory"]:
		_start_playing()
		assert_gt(_circle_count(), 0, "%s: fixture: circles live in match A" % path)
		match path:
			&"clear_circles":
				Match._territory.clear_circles()
				_assert_render_arrays_empty("after clear_circles()")
				Match._territory.clear_circles()
				_assert_render_arrays_empty("clear_circles() is idempotent")
			&"abort_match":
				Match.abort_match()
				_assert_render_arrays_empty("after abort_match()")
			&"start_match_from_playing":
				Match.start_match(_config(3))
				assert_ne(Match.state(), Match.State.PLAYING)
				_assert_render_arrays_empty("B's countdown after a direct restart")
			&"build_territory":
				Match._territory._build_territory()
				_assert_render_arrays_empty("after _build_territory()")
		Match.abort_match()


func test_the_hosts_circle_payload_during_the_next_countdown_decodes_to_zero_circles() -> void:
	_start_playing()
	assert_gt((_decoded_circle_payload()["xs"] as PackedFloat32Array).size(), 0, "fixture: A's payload carries circles")

	Match.abort_match()
	Match.start_match(_config(3))
	assert_eq(Match.state(), Match.State.COUNTDOWN)

	var decoded: Dictionary = _decoded_circle_payload()
	assert_false(decoded.is_empty(), "the payload is still a valid, decodable packet")
	assert_eq((decoded["xs"] as PackedFloat32Array).size(), 0, "no stale circles replicated to clients")
	assert_eq((decoded["teams"] as PackedInt32Array).size(), 0)
	assert_eq(
		(decoded["goal_positions"] as PackedVector2Array).size(),
		(Match.circle_render_arrays()["goal_positions"] as PackedVector2Array).size(),
		"B's own goal discs are still shipped"
	)


# --- G6: tense stem carries over -------------------------------------------------

func _make_sfx(contextual: bool) -> void:
	_audio_config = load("res://config/audio/audio_config.tres").duplicate() as AudioConfig
	_audio_config.contextual_music_enabled = contextual
	_audio_config.bundled_theme = null
	_audio_config.bundled_theme_path = ""
	_sfx = autofree(SFX_SCRIPT.new())
	_sfx.config = _audio_config
	add_child_autofree(_sfx)
	_tmp_dir = OS.get_user_data_dir().path_join("test_match_reset_rules_tmp")
	DirAccess.make_dir_recursive_absolute(_tmp_dir)


func _write_tiny_wav(path: String) -> void:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var data: PackedByteArray = PackedByteArray()
	data.resize(2205 * 2)
	wav.data = data
	assert_eq(wav.save_to_wav(path), OK, "fixture wav should save cleanly: %s" % path)


func _install_both_stem_files() -> void:
	_audio_config.music_stem_calm_file = "calm_stem.wav"
	_audio_config.music_stem_tense_file = "tense_stem.wav"
	_write_tiny_wav(_tmp_dir.path_join(_audio_config.music_stem_calm_file))
	_write_tiny_wav(_tmp_dir.path_join(_audio_config.music_stem_tense_file))
	_sfx.set_root_dir_for_test(_tmp_dir)


func test_match_scope_reset_returns_the_tense_stem_to_calm() -> void:
	_make_sfx(false)
	_install_both_stem_files()
	assert_true(_sfx._tense_stem_available, "fixture: both stems installed")
	Events.goal_capture_progress.emit(0, 0.9)
	assert_true(_sfx._tense_stem_is_active, "fixture: tense is up at the end of match A")
	assert_gt(_sfx.tense_stem_target_volume_db(), _sfx.calm_stem_target_volume_db(), "fixture: tense is the louder target")
	assert_not_null(_sfx._music_crossfade_tween, "fixture: the capture started a crossfade")

	Events.match_scope_reset.emit()

	assert_false(_sfx._tense_stem_is_active, "tense off after the reset")
	assert_gt(_sfx.calm_stem_target_volume_db(), _sfx.tense_stem_target_volume_db(), "calm is the louder target again")
	assert_null(_sfx._music_crossfade_tween, "the in-flight crossfade is killed")
	assert_almost_eq(_sfx._music_player.volume_db, _sfx.calm_stem_target_volume_db(), 0.001, "calm stem at its calm volume")
	assert_almost_eq(
		_sfx._tense_music_player.volume_db, _sfx.tense_stem_target_volume_db(), 0.001, "tense stem muted at its calm-state volume"
	)


# --- Rumble ------------------------------------------------------------------------
