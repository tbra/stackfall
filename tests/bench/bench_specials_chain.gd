extends Node3D
## Spec 3.5 benchmark (docs/M4_SPECIALS_PACKAGES.md's P4-VOLCANO package):
## five Volcano specials placed close enough that their orb blasts overlap,
## covering a full eruption from each plus chain propagation up to
## SpecialTuning.max_chain_depth. Run headless:
##   godot --headless --path . res://tests/bench/bench_specials_chain.tscn
## Prints one machine-readable result line, then quits.
##
## **Must be a .tscn, not a -s script.** Autoload identifiers (Match, Events)
## do not resolve in a bare -s SceneTree (tests/bench/m3a_acceptance.gd's own
## header finding, commit 12d2ec2). VolcanoEffect.physics_tick() spawns real
## orbs through Match.spawn_special_projectile(), which requires a live,
## PLAYING host match with a registered Field/BlockRegistry/blocks-parent
## (autoload/match/MatchPlacement.gd's own guard) -- this scene builds that
## exact fixture (tests/bench/m3a_acceptance.gd's own _run_host() shape,
## minus networking/replication), rather than tests/bench/bench_tower.gd's/
## bench_rain.gd's simpler Field-only setup, since neither of those benches
## ever spawns through Match.
##
## A chain reaction resolves synchronously, all within the one physics tick
## whichever orb detonates first: SpecialBehavior.trigger() calls
## detonate() calls trigger_others_in_range() calls trigger() on every
## in-range neighbor immediately, recursively, up to max_chain_depth (game/
## specials/SpecialBehavior.gd) -- so "chain propagation to max_chain_depth"
## is not something this bench has to wait multiple ticks for on purpose, it
## simply has to place enough volcanoes close enough that when their orbs
## land, several of them are within each other's own orb_explosion_radius at
## the same moment. RUN_SECONDS is sized generously past the slowest
## plausible path (eruption_duration_s's own window, plus an orb spawned
## right at its end still needing to arc, land, and -- absent an early
## impact -- wait out its own SpecialDef.fuse_timeout_s, default 6.0 s) so
## the whole scenario is virtually certain to finish inside the run.
##
## Note: headless timing on any one machine is only a proxy for real in-game
## frame time (no rendering, no vsync, possibly different CPU contention),
## the same caveat tests/bench/bench_rain.gd documents -- treat the printed
## number as a relative regression check, not an absolute 60 fps guarantee.
## A windowed run on real hardware is the owner's own manual step for that.

const VOLCANO_COUNT: int = 5
## Volcanoes sit on a small ring this radius (meters) apart so their own
## orb_explosion_radius (1.5 m default) footprints overlap once orbs land.
const CLUSTER_RADIUS_M: float = 1.2
const PLACE_HEIGHT_M: float = 0.6
const RUN_SECONDS: float = 10.0
const TARGET_STEP_MS: float = 1000.0 / 60.0

var _tick: int = 0
var _total_ticks: int = 0
var _step_time_sum_ms: float = 0.0
var _elapsed_sim_seconds: float = 0.0
var _finished: bool = false
var _triggered_count: int = 0
var _max_chain_depth_seen: int = 0
var _field: Field = null
var _blocks_root: Node3D = null
## Review fix (Bontago-1en.3): the 5 spawned volcano Blocks themselves, kept
## around so the final report can print each one's own
## volcano_orbs_spawned/volcano_orb_count meta -- the reviewer could not tell
## "5 full eruptions" from "some fired zero orbs" (e.g. a volcano detonated by
## a nearby chain reaction before its own eruption ever completed) from the
## single aggregate result line alone.
var _volcano_blocks: Array[Block] = []


func _ready() -> void:
	_total_ticks = int(round(RUN_SECONDS * Engine.physics_ticks_per_second))

	_field = Field.new()
	_field.map_def = MapDef.for_size(MapDef.MapSize.SMALL)
	add_child(_field)
	_blocks_root = Node3D.new()
	add_child(_blocks_root)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child(registry)
	Match.register_world(_field, registry, _blocks_root)

	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = 2
	config.hot_seat = false
	config.rng_seed = 20260923
	Match.start_match(config)

	Events.special_triggered.connect(_on_special_triggered)

	print(
		"BENCH_SPECIALS_CHAIN start volcanoes=%d duration_s=%.1f cluster_radius_m=%.2f" % [
			VOLCANO_COUNT, RUN_SECONDS, CLUSTER_RADIUS_M
		]
	)

	# Same wait shape as tests/bench/m3a_acceptance.gd's own _run_host():
	# Match.COUNTDOWN_SECONDS of simulated time plus a fixed margin, driven by
	# Match's own autoload _process() (never disabled here, unlike the GUT
	# unit tests, which call Match.set_process(false) to drive it manually).
	await get_tree().create_timer(Match.COUNTDOWN_SECONDS + 0.5).timeout
	_spawn_volcanoes()


func _spawn_volcanoes() -> void:
	var volcano_def: SpecialDef = null
	for def: SpecialDef in SpecialDef.load_all_specials():
		if def.id == &"volcano":
			volcano_def = def
			break
	if volcano_def == null:
		push_error("BENCH_SPECIALS_CHAIN: config/specials/volcano.tres not found")
		get_tree().quit(1)
		return

	var cube_shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	for i: int in range(VOLCANO_COUNT):
		var angle: float = TAU * float(i) / float(VOLCANO_COUNT)
		var spot: Vector2 = Vector2(cos(angle), sin(angle)) * CLUSTER_RADIUS_M
		var origin: Vector3 = _field.world_from_disk_local(spot, PLACE_HEIGHT_M)
		var volcano: Block = Match.spawn_special_projectile(
			cube_shape, origin, Basis.IDENTITY, 0, Vector3.ZERO, volcano_def, null
		)
		if volcano != null:
			_volcano_blocks.append(volcano)


func _on_special_triggered(
	_net_id: int, _def_id: StringName, _position: Vector3, chain_depth: int
) -> void:
	_triggered_count += 1
	_max_chain_depth_seen = maxi(_max_chain_depth_seen, chain_depth)


func _physics_process(delta: float) -> void:
	if _finished:
		return
	# Do not let the pre-PLAYING countdown ticks (before any volcano has even
	# spawned) skew the averaged step time below.
	if Match.state() != Match.State.PLAYING:
		return

	_tick += 1
	_elapsed_sim_seconds += delta
	_step_time_sum_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	if _tick < _total_ticks:
		return

	_finished = true
	# Review fix (Bontago-1en.3): one line per volcano so a self-triggered
	# volcano (spawned < orb_count) is visible instead of hidden inside the
	# single aggregate result line below.
	for idx: int in range(_volcano_blocks.size()):
		var volcano: Block = _volcano_blocks[idx]
		var orb_count: int = (
			int(volcano.get_meta(&"volcano_orb_count")) if volcano.has_meta(&"volcano_orb_count") else -1
		)
		var spawned: int = (
			int(volcano.get_meta(&"volcano_orbs_spawned")) if volcano.has_meta(&"volcano_orbs_spawned") else 0
		)
		print(
			"BENCH_SPECIALS_CHAIN volcano=%d spawned=%d orb_count=%d" % [idx, spawned, orb_count]
		)
	var avg_step_ms: float = _step_time_sum_ms / float(_tick)
	var equivalent_fps: float = 1000.0 / avg_step_ms if avg_step_ms > 0.0 else 0.0
	var passed: bool = avg_step_ms <= TARGET_STEP_MS
	print(
		(
			"BENCH_SPECIALS_CHAIN result=%s volcanoes=%d elapsed_sim_s=%.2f avg_physics_step_ms=%.4f "
			+ "equivalent_fps=%.1f target_step_ms=%.4f triggered_count=%d max_chain_depth_seen=%d "
			+ "note=headless_timing_is_a_proxy_only"
		) % [
			"PASS" if passed else "FAIL", VOLCANO_COUNT, _elapsed_sim_seconds,
			avg_step_ms, equivalent_fps, TARGET_STEP_MS, _triggered_count, _max_chain_depth_seen,
		]
	)
	get_tree().quit(0 if passed else 1)
