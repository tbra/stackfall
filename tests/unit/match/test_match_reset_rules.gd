extends GutTest
## R2 (docs/MATCH_RESET_AUDIT.md G3, G6 + rumble): the rules and
## autoload carry-overs behind "a new match after leaving is indistinguishable from
## a freshly launched one".

var _tiny_map: MapDef
var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry

var _config_before: Dictionary = {}


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
	_restore_stems()


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


class ClientHost extends FakeHostPort:
	var side: ClientSide = null

	func raster() -> TerritoryRaster:
		return side.mirror

	func circle_wire_xz_bound() -> float:
		return side.xz_bound

	func circle_wire_radius_max() -> float:
		return side.radius_max


class ClientReplica extends FakeReplicaPort:
	var side: ClientSide = null

	func apply_replicated_territory(
		_cells: PackedInt32Array, owners: PackedByteArray, states: PackedByteArray, _full: bool,
		xs: PackedFloat32Array = PackedFloat32Array(), zs: PackedFloat32Array = PackedFloat32Array(), radii: PackedFloat32Array = PackedFloat32Array(),
		teams: PackedInt32Array = PackedInt32Array(), goal_positions: PackedVector2Array = PackedVector2Array(), _goal_radii: PackedFloat32Array = PackedFloat32Array(),
		argmax_mode: bool = false
	) -> void:
		side.mirror.apply_replicated_state(owners, states)
		side.received = {
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
	var client_host: ClientHost = ClientHost.new()
	client_host.side = side
	var client_replica: ClientReplica = ClientReplica.new()
	client_replica.side = side
	var client: TerritoryReplicator = TerritoryReplicator.new(client_host, client_replica, net_config)
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
	# Removed internal guards (no public caller reaches them alone), each rule still covered:
	#   The territory clear_circles() -> abort_match() below: its reset calls clear_circles(), and the
	#                                        empty render arrays after it fail if it stops clearing.
	#   The territory _build_territory() -> start_match() from PLAYING below: it rebuilds the territory,
	#                                        and B's countdown arrays are empty only if the rebuild drops circles.
	for path: StringName in [&"abort_match", &"start_match_from_playing"]:
		_start_playing()
		assert_gt(_circle_count(), 0, "%s: fixture: circles live in match A" % path)
		match path:
			&"abort_match":
				Match.abort_match()
				_assert_render_arrays_empty("after abort_match()")
			&"start_match_from_playing":
				Match.start_match(_config(3))
				assert_ne(Match.state(), Match.State.PLAYING)
				_assert_render_arrays_empty("B's countdown after a direct restart")
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

## Turns the stems on through the public settings signal: contextual music off, no bundled
## theme, and two shipped wavs standing in for the calm and tense stem files.
func _install_both_stem_files() -> void:
	var config: AudioConfig = Sfx.config
	_config_before = {
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


func _restore_stems() -> void:
	if _config_before.is_empty():
		return
	Sfx.reset_match_audio()
	var config: AudioConfig = Sfx.config
	config.contextual_music_enabled = _config_before["contextual"]
	config.bundled_theme = _config_before["theme"]
	config.bundled_theme_path = _config_before["theme_path"]
	config.music_stem_calm_file = _config_before["calm"]
	config.music_stem_tense_file = _config_before["tense"]
	_config_before = {}
	Settings.audio_settings_changed.emit()


func test_match_scope_reset_returns_the_tense_stem_to_calm() -> void:
	_install_both_stem_files()
	Events.goal_capture_progress.emit(0, 0.9)
	assert_gt(Sfx.tense_stem_target_volume_db(), Sfx.calm_stem_target_volume_db(), "fixture: tense is up at the end of match A")

	Events.match_scope_reset.emit()

	assert_gt(Sfx.calm_stem_target_volume_db(), Sfx.tense_stem_target_volume_db(), "tense off after the reset: calm is the louder target again")


# --- Rumble ------------------------------------------------------------------------
