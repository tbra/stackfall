class_name MainSandboxFlow
extends MainSandboxFlowPort
## The hot-seat, sandbox and tutorial entry points, split out of game/main/Main.gd
## so Main.gd does not compile HotSeat/Sandbox/Tutorial.
## Main loads this script on demand through MenuPrewarmQueue.ensure_script() and keeps one-line
## forwarders for every old member name tests/tools call. DECISION: this file reads Main's
## underscore-prefixed state through `main_node` (one module split in two; tests already do).

## The Main node, typed (the port's `main` is the Node3D it binds).
var main_node: Main:
	get:
		return main as Main


# --- Hot-seat ------------------------------------------

func start_hot_seat_match() -> void:
	Sfx.set_music_context(&"gameplay")
	var hot_seat: HotSeat = main_node._load_scene(Main.HOT_SEAT_SCENE_PATH).instantiate() as HotSeat
	main_node._hot_seat = hot_seat
	main_node.add_child(hot_seat)
	hot_seat.set_camera_rig(main_node._camera_rig)
	hot_seat.set_field(main_node._field)
	Match.register_world(main_node._field, main_node._registry, main_node._blocks_container)
	Match.start_match(_build_hot_seat_config())

	var config: MatchConfig = Match.config
	main_node._field.rebuild_for_map(config.map_def())
	main_node._camera_rig.set_map_def(config.map_def())
	main_node._field.place_flags(config.player_count, config.player_colors, config.effective_goal_flag_count())
	main_node._field.set_overlay_source(Match.raster(), config.territory_colors())
	main_node._apply_match_sky(config)
	main_node._horizon_islands.rebuild_for_map(config.map_def(), main_node._world_environment.environment if main_node._world_environment != null else null)


## The lobby settings a real lobby screen collects, for the one path that
## skips it. Hot-seat and the player count are the only overrides; everything
## else is whatever config/match/match_defaults.tres says.
func _build_hot_seat_config() -> MatchConfig:
	var config: MatchConfig = main_node.match_config.duplicate(true) as MatchConfig
	config.player_count = main_node.player_count
	config.hot_seat = true
	return config


# --- Sandbox: unlisted debug entry point ---------------------
#
# `godot --path . -- --sandbox [--players=N]` starts an *offline* match, same
# shape as _start_hot_seat_match() above (register_world() -> start_match()
# -> place_flags()/set_overlay_source()), but with every slot locally
# controllable, no feed timer, and unlimited blocks (config/match/MatchConfig.gd's
# `sandbox` flag; autoload/Match.gd's `_feed_timer_enabled`). Never reached by
# the menu/lobby, so it changes nothing about --hot-seat or the networked
# path above.

func start_sandbox_match() -> void:
	start_sandbox_match_with_args(OS.get_cmdline_user_args())


## Split from _start_sandbox_match() so a test can drive both the --players=
## parsing and the resulting world build with a manufactured argument list —
## the same seam autoload/Net.gd's _apply_command_line_args() uses, since
## there is no OS.set_cmdline_user_args() to fake the real one with.
func start_sandbox_match_with_args(args: PackedStringArray) -> void:
	Sfx.set_music_context(&"gameplay")
	var sandbox: Sandbox = main_node._load_scene(Main.SANDBOX_SCENE_PATH).instantiate() as Sandbox
	main_node._sandbox = sandbox
	main_node.add_child(sandbox)
	# DECISION: no scoreboard in the sandbox; Tab stays sandbox_next_slot.
	if main_node._scoreboard_node != null:
		main_node._scoreboard_node.suppressed = true
	sandbox.set_camera_rig(main_node._camera_rig)
	sandbox.set_field(main_node._field)
	Match.register_world(main_node._field, main_node._registry, main_node._blocks_container)
	Match.start_match(_build_sandbox_config(_sandbox_player_count(args)))

	var config: MatchConfig = Match.config
	main_node._field.rebuild_for_map(config.map_def())
	main_node._camera_rig.set_map_def(config.map_def())
	main_node._field.place_flags(config.player_count, config.player_colors, config.effective_goal_flag_count())
	main_node._field.set_overlay_source(Match.raster(), config.territory_colors())
	main_node._apply_match_sky(config)
	main_node._horizon_islands.rebuild_for_map(config.map_def(), main_node._world_environment.environment if main_node._world_environment != null else null)
	# The Skybox cycle reads the one shared match clock (SnapshotSync.sky_cycle_seconds()),
	# which only runs between begin_match()
	# and end_match(). DECISION: begin the real SnapshotSync like a normal match (one clock, no second
	# sky clock): offline host_tick() only advances the clock and returns before any selection or send,
	# and nothing it turns on ends or times a sandbox. Teardown is the ordinary end_match_world().
	SnapshotSync.set_disk(main_node._field)
	SnapshotSync.begin_match(Match.registry(), config.map_def())

	# F3's overlay works offline too (Net.stats() reports Offline/0 peers,
	# which is still useful context while sandbox-testing); it costs nothing
	# unopened, exactly as in the networked path below.
	var debug_overlay: NetDebugOverlay = main_node._load_scene(Main.NET_DEBUG_OVERLAY_SCENE_PATH).instantiate() as NetDebugOverlay
	main_node._debug_overlay = debug_overlay
	main_node.add_child(debug_overlay)

	# `--force-special=<id>` sets the state F9 (sandbox_force_special) toggles at
	# runtime. _sandbox is already _ready() (add_child() runs it synchronously), so
	# its roster cache exists by the time this reaches it.
	var forced: String = _sandbox_force_special_arg(args)
	# --force-special is a debug tool; ignored unless debug mode.
	if forced != "" and DebugMode.is_enabled():
		sandbox.force_special_by_id(StringName(forced))


## The Main Menu's entry point (ui/menus/MainMenu.gd's %SandboxButton), unlike the
## CLI-only start_sandbox_match(): reachable only once the ordinary menu/lobby path
## in _ready() has connected Events.match_state_changed, so Match.start_match()'s
## (LOBBY -> LOADING) emit would otherwise also run _build_match_world(), which
## builds a *HotSeat*-driven world, not the Sandbox one, and duplicates the field
## rebuild/overlay/debug-overlay work.
##
## _world_built = true here is belt-and-braces: _on_match_state_changed() itself
## diverts every state change away from _build_match_world()/_end_match_world()
## while _sandbox is a live instance (see that handler's DECISION), which is also
## what makes a later sandbox_reset_field (F5, game/sandbox/Sandbox.gd's
## _reset_field()) safe. start_sandbox_match_with_args([]) runs the same as the CLI
## path: default player count, no forced special.
func start_sandbox_from_menu() -> void:
	main_node._sandbox_preset = null
	_launch_sandbox_from_menu()


func _launch_sandbox_from_menu() -> void:
	main_node._clear_menu_and_lobby()
	# This path bypasses _build_match_world(), so it needs its own new-match reset,
	# before Sandbox.set_camera_rig() below, which re-sets
	# CameraRig.suppress_pad_home_focus that reset_view() clears.
	main_node._reset_match_scope()
	main_node._world_built = true
	# _build_match_world() owns this line for every other match-start path and never
	# runs for sandbox-from-menu, so this path needs its own explicit unsuppress.
	main_node._pause_menu.suppressed = false
	start_sandbox_match_with_args(PackedStringArray())


## the Debug page's Gift demo. The ordinary sandbox launched
## with config/match/sandbox_gift_demo.tres: pre-placed opponent towers, gifts on at
## high frequency. Leaving goes through the sandbox pause menu like any sandbox.
func start_gift_demo_from_menu() -> void:
	if not DebugMode.is_enabled():
		return
	main_node._sandbox_preset = load(Main.GIFT_DEMO_PRESET_PATH) as SandboxConfig
	_launch_sandbox_from_menu()
	(main_node._sandbox as Sandbox).apply_preset(main_node._sandbox_preset)


## the Debug page's Tower topple. Same sandbox path with
## config/match/sandbox_tower_topple.tres: a row of settled towers (the tower tests'
## heights, up to the 30/40-block acceptance towers) to knock down with blocks
## and gifts.
func start_tower_topple_from_menu() -> void:
	if not DebugMode.is_enabled():
		return
	main_node._sandbox_preset = load(Main.TOWER_TOPPLE_PRESET_PATH) as SandboxConfig
	_launch_sandbox_from_menu()
	(main_node._sandbox as Sandbox).apply_preset(main_node._sandbox_preset)


## Same lobby-settings-minus-a-few-overrides shape as _build_hot_seat_config().
## config.sandbox is what lets MatchConfig.sanitize() allow `player_count`
## below spec 1.9's normal floor of 2, and tells Match to start with its feed
## timer paused (autoload/Match.gd's start_match()).
func _build_sandbox_config(requested_player_count: int) -> MatchConfig:
	var config: MatchConfig = main_node.match_config.duplicate(true) as MatchConfig
	config.player_count = requested_player_count
	config.hot_seat = false
	config.ai_count = 0
	config.sandbox = true
	if main_node._sandbox_preset != null:
		if main_node._sandbox_preset.special_frequency_override >= 0:
			config.gifts_enabled = true
			config.special_frequency = main_node._sandbox_preset.special_frequency_override
	return config


## `--players=<n>`, parsed with the same "-"-stripping loop
## _has_cmdline_flag() and autoload/Net.gd's _apply_command_line_args() both
## use. Takes the argument list explicitly rather than reading
## OS.get_cmdline_user_args() itself (see _start_sandbox_match_with_args()),
## so a test can drive it with a manufactured list. Out-of-range values are
## not clamped here — MatchConfig.sanitize() (Match.start_match()) already
## does that against this config's own `sandbox` flag.
func _sandbox_player_count(args: PackedStringArray) -> int:
	const PREFIX: String = "players="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return int(text.substr(PREFIX.length()))
	if main_node._sandbox_preset != null:
		return main_node._sandbox_preset.default_player_count
	return main_node.sandbox_config.default_player_count


## `--force-special=<id>`, same "-"-stripping loop and same "takes the
## argument list explicitly" seam as _sandbox_player_count() right above (so a
## test can drive it with a manufactured list) -- validation of `<id>` against
## the real roster is game/sandbox/Sandbox.gd's force_special_by_id()'s job, not this
## file's; an unrecognized id there warns and leaves forcing off rather than
## this parser guessing at the roster itself.
func _sandbox_force_special_arg(args: PackedStringArray) -> String:
	const PREFIX: String = "force-special="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return text.substr(PREFIX.length())
	return ""


# --- Tutorial: single-player onboarding ---------------------------------------
#
# Reachable only from the Main Menu's own %TutorialButton (ui/menus/MainMenu.gd's
# tutorial_requested signal, the same direct child-signal convention
# start_sandbox_from_menu() above uses for sandbox_requested): a one-player,
# offline match built exactly like start_sandbox_from_menu()'s own
# register_world() -> start_match() -> place_flags()/set_overlay_source(),
# with config.sandbox = true (so ui/menus/Tutorial.gd's own Match.debug_queue_
# special() call is allowed through MatchGifts.debug_queue_special()'s own
# host/config.sandbox gate) and config.player_count = 1 (there is only ever
# one tutorial participant). Never reached from --hot-seat/--sandbox or the
# real lobby/net path, so it changes nothing about either.

func start_tutorial_from_menu() -> void:
	main_node._clear_menu_and_lobby()
	# Same bypass of _build_match_world() as the sandbox start above, so the same
	# new-match reset.
	main_node._reset_match_scope()
	main_node._world_built = true
	# See PauseMenu's `suppressed` doc: Tutorial owns ui_cancel/Escape for its own
	# quit gesture, and the dispatch order of the two scenes' _unhandled_input()
	# (unrelated siblings) is not a documented guarantee.
	main_node._pause_menu.suppressed = true
	var tutorial: Tutorial = main_node._load_scene(Main.TUTORIAL_SCENE_PATH).instantiate() as Tutorial
	main_node._tutorial = tutorial
	main_node.add_child(tutorial)
	tutorial.set_camera_rig(main_node._camera_rig)
	tutorial.finished.connect(on_tutorial_finished)
	Match.register_world(main_node._field, main_node._registry, main_node._blocks_container)
	Match.start_match(_build_tutorial_config())

	var config: MatchConfig = Match.config
	main_node._field.rebuild_for_map(config.map_def())
	main_node._camera_rig.set_map_def(config.map_def())
	main_node._field.place_flags(config.player_count, config.player_colors, config.effective_goal_flag_count())
	main_node._field.set_overlay_source(Match.raster(), config.territory_colors())
	main_node._apply_match_sky(config)
	main_node._horizon_islands.rebuild_for_map(config.map_def(), main_node._world_environment.environment if main_node._world_environment != null else null)


## Same lobby-settings-minus-a-few-overrides shape as _build_sandbox_config()
## above: always exactly one player, config.sandbox = true so ui/menus/Tutorial.gd's
## forced special (Match.debug_queue_special()) is let through.
func _build_tutorial_config() -> MatchConfig:
	var config: MatchConfig = main_node.match_config.duplicate(true) as MatchConfig
	config.player_count = 1
	config.hot_seat = false
	config.ai_count = 0
	config.sandbox = true
	return config


## ui/menus/Tutorial.gd's `finished` signal (step 5 completing, or ui_cancel at any
## step): frees the Tutorial subtree start_tutorial_from_menu() built and returns to
## the Main Menu. Tutorial already called Match.abort_match() before emitting, so
## _on_match_state_changed()'s _end_match_world() has run by now; this only cleans
## up the one node added here.
func on_tutorial_finished() -> void:
	if main_node._tutorial != null and is_instance_valid(main_node._tutorial):
		main_node._tutorial.queue_free()
	main_node._tutorial = null
	# _show_main_menu() owns re-suppressing/force-closing this menu for every "no
	# match world" screen, so no explicit `= false` write belongs here.
	main_node._show_main_menu()
