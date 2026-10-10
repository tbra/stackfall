class_name MainMatchFlow
extends MainMatchFlowPort
## Bontago-1pi.11.84 (MF3): the match-world flow (state routing, loading hand-off, world build/teardown,
## bot controllers, scope reset) moved verbatim out of game/Main.gd (docs/MENU_FIRST_PLAN.md 3.2).
## Main keeps one forwarder per old name and loads this script before the first match_state_changed
## reaction (R4: the client's net_match_start RPC arrives with no Main involvement, so the Main
## forwarder of `_on_match_state_changed` always ensures this flow first). State fields stay on Main
## because tests read them; this file reads and writes them through `main_node` (DECISION: one
## module split in two, as MainSandboxFlow does). The loading-generation guard stays on Main
## (`_loading_generation`) and every coroutine here re-checks `is_instance_valid(main)` after an await (R5).

## The Main node, typed (the port's `main` is the Node3D it binds).
var main_node: Main:
	get:
		return main as Main

# Read-only views of Main's persistent world nodes, so the moved bodies read as they did on Main.
var _field: Field:
	get:
		return main_node._field
var _registry: BlockRegistry:
	get:
		return main_node._registry
var _camera_rig: CameraRig:
	get:
		return main_node._camera_rig
var _horizon_islands: HorizonIslands:
	get:
		return main_node._horizon_islands
var _world_environment: WorldEnvironment:
	get:
		return main_node._world_environment
var _loading_screen: LoadingScreen:
	get:
		return main_node._loading_screen
var _pause_menu: PauseMenu:
	get:
		return main_node._pause_menu


## The world exists exactly while Match is past the lobby. Match guarantees
## that a genuine start always arrives as LOBBY -> LOADING (start_match()
## goes back through abort_match() first from any later state), with the
## raster, slots and registry already built when the signal fires, so this
## binds them synchronously. The from_state guard is deliberate, not
## belt-and-braces: a client's mirror re-emits the host's replicated LOADING
## as (COUNTDOWN -> LOADING) after net_match_start already ran its own start
## (Match.apply_replicated_state_change), and that must not rebuild anything.
func on_match_state_changed(from_state: int, to_state: int) -> void:
	if to_state == Match.State.LOADING:
		Sfx.set_music_context(&"gameplay")
	# Spec 3.4: joining is lobby-only in M3a. Net must not name Match, so the
	# match flow flips Net's gate here, where every state change is routed: a
	# handshake arriving while the match is past LOBBY is refused with
	# JoinError.MATCH_IN_PROGRESS, and abort_match()'s (old -> LOBBY) emit
	# reopens it (Net.leave() also resets it itself). On a client this is a
	# harmless flag write; _rpc_handshake is host-gated (Beads Bontago-mv0.1.8).
	#
	# Bontago-8or.11 (spec 3.4 "Mid-match joins can be enabled in settings"):
	# a live match also admits new joiners when its config allows it. LOADING
	# (synchronous on the host) and END stay closed; MatchNet replays the
	# world to whoever is admitted. Net is told when a match world starts and
	# when the session really returns to the lobby -- not the transient LOBBY
	# a replay/restart passes through inside start_match() -- so it can keep
	# and drop rejoin reservations and reseat spectators.
	if to_state == Match.State.LOADING:
		Net.set_match_in_progress(true)
	elif to_state == Match.State.LOBBY and not Match._lifecycle.is_starting_match():
		Net.set_match_in_progress(false)
	var live_state: bool = Match.is_replicating(to_state)
	var mid_match_join: bool = live_state and Match.config != null and Match.config.allow_mid_match_join
	Net.set_accepting_joins(to_state == Match.State.LOBBY or mid_match_join)

	# DECISION (game/Main.gd, Bontago-xtq.43 round 2): a sandbox reset
	# (sandbox_reset_field, F5 -- game/Sandbox.gd's _reset_field()) re-runs
	# Match.start_match() with its own current config, which always goes back
	# through abort_match() first (MatchLifecycle.start_match()'s own doc: "A
	# start from anything but LOBBY first goes back through the lobby"), so a
	# reset fires this handler twice in a row, synchronously: (X -> LOBBY)
	# then (LOBBY -> LOADING). game/Sandbox.gd already owns the whole world
	# for every slot in a sandbox match (its own PlayerController/GhostPreview
	# subtree -- never Main's _hot_seat) and already replays Field.
	# place_flags()/set_overlay_source() itself right after start_match()
	# returns (see _reset_field()'s own doc) -- so routing this pair through
	# the ordinary _end_match_world()/_build_match_world() below tore down and
	# then rebuilt a *second*, independent HotSeat (_build_match_world() has
	# no way to know a Sandbox is already serving every slot) bound to the
	# same local slot Sandbox's own controller already drives, both then
	# reading input for it (round 1's reproduction: LOCAL_HELD_GROUP count
	# growing 2 -> 3 -> 4 -> 5 across resets).
	#
	# Checked against the live _sandbox instance rather than Match.config.
	# sandbox: Tutorial also sets that flag on its own config (start_tutorial_
	# from_menu()'s _build_tutorial_config()), and its _on_tutorial_finished()
	# teardown still needs the ordinary _end_match_world() reaction to
	# (-> LOBBY) to run -- unlike Sandbox, Tutorial has a real "return to
	# menu" exit and never mid-session-resets. _sandbox is non-null for
	# exactly the lifetime of a sandbox match on this Main instance (no
	# "return to menu" path out of sandbox exists today), so this only ever
	# diverts the reaction while a sandbox match is actually live.
	#
	# _field.clear_match_state() is still run directly on the (X -> LOBBY)
	# half, so a reset still actually clears holes/tilt/physical-balance state
	# the same way it visibly did before this fix (the previous, buggy
	# _end_match_world() call happened to do that too, as a side effect of
	# also building the duplicate world) -- everything else _end_match_world()/
	# _build_match_world() would otherwise touch (SnapshotSync, _remote_
	# cursors, bot controllers, the debug overlay Sandbox already built itself
	# in _start_sandbox_match_with_args()) is correctly left alone; Sandbox's
	# own place_flags()/set_overlay_source() calls right after start_match()
	# returns pick the field back up from there.
	if main_node._sandbox != null and is_instance_valid(main_node._sandbox):
		if to_state == Match.State.LOBBY:
			_field.clear_match_state()
			# Bontago-1pi.46: a sandbox reset is a new match too -- dry arena;
			# the camera stays where the player put it, and so does the sandbox's
			# own CameraRig.suppress_pad_home_focus (only a camera reset clears it).
			_reset_match_scope(false)
		elif Match.is_start_transition(from_state, to_state) and Match.config != null:
			# Bontago-1pi.127 (owner screenshot: the sandbox showed the painted sunset after
			# F5): the scope reset on the (X -> LOBBY) half returns the Skybox to its launch
			# sky (the static painted-panorama sunset), so the restart sets the sandbox's sky
			# up again like at entry.
			main_node._apply_match_sky(Match.config)
		return

	if to_state == Match.State.LOBBY:
		main_node._loading_generation += 1
		end_match_world()
		# Bontago-1pi.8: safety net for a match aborted mid-load -- see
		# LoadingScreen.cancel()'s own doc.
		_loading_screen.cancel()
		# A results-screen return ends the match without changing Net's mode,
		# so _on_net_mode_changed() cannot rebuild the lobby for us. A replay
		# briefly passes through LOBBY inside start_match(); keep that transition
		# out of the UI route so the new match builds directly.
		if not Match._lifecycle.is_starting_match() and not Net.is_offline():
			main_node._show_lobby()
	elif Match.is_start_transition(from_state, to_state):
		main_node._loading_generation += 1
		main_node._first_territory_ready = false
		# Bontago-1pi.8: shown before _build_match_world() below runs, so the
		# overlay is already queued to composite over this same frame's draw
		# pass -- see ui/LoadingScreen.gd's own header doc.
		_loading_screen.show_for_match(Match.config, main_node._loading_screen_slots())
		# Bontago-mp0.27. # DECISION: the 3-2-1 must start once the loading screen
		# is gone, not run down behind it. Held from here until
		# _finish_loading_when_ready() releases it (a reset/abort also clears it).
		# Skipped headless: no loading screen is ever rendered there, and tests
		# and bot harnesses drive Match by hand.
		if DisplayServer.get_name() != "headless":
			Match.set_countdown_held(true)
		build_match_world()
	elif to_state == Match.State.COUNTDOWN:
		_finish_loading_when_ready(main_node._loading_generation)


func _finish_loading_when_ready(generation: int) -> void:
	while not main_node._world_built:
		await main_node.get_tree().process_frame
		# DECISION (MF3, R5): Main may be freed while this coroutine is suspended.
		if not is_instance_valid(main):
			return
		if generation != main_node._loading_generation or not _loading_screen.visible:
			_release_countdown_hold(generation)
			return
	if not _loading_screen.visible:
		_release_countdown_hold(generation)
		return
	_loading_screen.set_stage("Solving territory", _loading_screen.tuning.solve_progress)
	while not main_node._first_territory_ready:
		await main_node.get_tree().process_frame
		# DECISION (MF3, R5): Main may be freed while this coroutine is suspended.
		if not is_instance_valid(main):
			return
		if generation != main_node._loading_generation or not _loading_screen.visible:
			_release_countdown_hold(generation)
			return
	_loading_screen.set_stage("Warming materials", _loading_screen.tuning.materials_progress)
	_loading_screen.warm_common_materials()
	for frame: int in range(_loading_screen.tuning.stable_frames):
		await main_node.get_tree().process_frame
		# DECISION (MF3, R5): Main may be freed while this coroutine is suspended.
		if not is_instance_valid(main):
			return
		if generation != main_node._loading_generation or not _loading_screen.visible:
			_release_countdown_hold(generation)
			return
		_loading_screen.set_stage("Stabilizing view", lerpf(_loading_screen.tuning.stabilize_start_progress, _loading_screen.tuning.stabilize_end_progress, float(frame + 1) / maxf(float(_loading_screen.tuning.stable_frames), 1.0)))
	_loading_screen.set_stage("Ready", _loading_screen.tuning.complete_progress)
	# Bontago-mp0.27: the camera starts at the local player's own beacon, looking
	# at the centre, whatever the loading frames did to it.
	if main_node._hot_seat != null and _camera_rig != null:
		_camera_rig.begin_start_framing(Net.local_slot())
	if main_node._hot_seat != null:
		(main_node._hot_seat as HotSeat).controller().set_process(main_node._controller_was_processing)
		(main_node._hot_seat as HotSeat).controller().set_process_unhandled_input(main_node._controller_was_handling_input)
	await _loading_screen.fade_out()
	# DECISION (MF3, R5): Main may be freed while this coroutine is suspended.
	if not is_instance_valid(main):
		return
	# Bontago-mp0.27: the screen is gone; now the 3-2-1 starts running down.
	_release_countdown_hold(generation)


## Bontago-mp0.27 review: every exit of the loading hand-off (overlay already
## hidden, cancelled, timed out, superseded) must free the countdown hold, or a
## match could sit held. A stale generation belongs to a newer load, which owns
## the hold now, so only the current generation releases.
func _release_countdown_hold(generation: int) -> void:
	if generation == main_node._loading_generation:
		Match.set_countdown_held(false)


func build_match_world(force_staging_for_test: bool = false) -> void:
	if main_node._world_built or main_node._world_building:
		return
	main_node._world_building = true
	var generation: int = main_node._loading_generation
	# Bontago-1pi.46: the single new-match entry (host, client and headless
	# alike) -- starts from the launch camera and a dry arena whatever the
	# previous match left behind, and tells the persistent owners (Events.
	# match_scope_reset) to do the same. Runs before configure_match_sky() below.
	_reset_match_scope()
	# DECISION: only a visible interactive overlay needs frame-separated stages.
	# Headless hosts and test/probe runs retain the synchronous start contract.
	var stage_build: bool = force_staging_for_test or (_loading_screen != null and _loading_screen.visible and DisplayServer.get_name() != "headless" and not AgentProbe.is_active())
	main_node._clear_menu_and_lobby()
	# Bontago-xtq.42 fix round 2: every real (host/client/headless-bot) match
	# reaches this one guarded builder -- start_sandbox_from_menu() above is
	# the only match-start path that bypasses it (see its own doc comment),
	# so it needs its own copy of this line.
	_pause_menu.suppressed = false

	var config: MatchConfig = Match.config
	_field.rebuild_for_map(config.map_def())
	_camera_rig.set_map_def(config.map_def())
	_loading_screen.set_stage("Placing flags", _loading_screen.tuning.flags_progress)
	if stage_build:
		await main_node.get_tree().process_frame
		# DECISION (MF3, R5): Main may be freed while this coroutine is suspended.
		if not is_instance_valid(main):
			return
		if generation != main_node._loading_generation or not _loading_screen.visible:
			main_node._world_building = false
			return
	_field.place_flags(config.player_count, config.player_colors, config.effective_goal_flag_count())
	_loading_screen.set_stage("Preparing territory", _loading_screen.tuning.territory_progress)
	if stage_build:
		await main_node.get_tree().process_frame
		# DECISION (MF3, R5): Main may be freed while this coroutine is suspended.
		if not is_instance_valid(main):
			return
		if generation != main_node._loading_generation or not _loading_screen.visible:
			main_node._world_building = false
			return
	_field.set_overlay_source(Match.raster(), config.territory_colors())
	main_node._apply_match_sky(config)
	_horizon_islands.rebuild_for_map(config.map_def(), _world_environment.environment if _world_environment != null else null)
	# Bontago-470.4: the lobby's Day/Night/Random, resolved by the host and
	# replicated; the F4 Theme dropdown still overrides live afterwards.

	SnapshotSync.set_disk(_field)
	SnapshotSync.begin_match(Match.registry(), config.map_def())
	_loading_screen.set_stage("Preparing players", _loading_screen.tuning.players_progress)
	if stage_build:
		await main_node.get_tree().process_frame
		# DECISION (MF3, R5): Main may be freed while this coroutine is suspended.
		if not is_instance_valid(main):
			return
		if generation != main_node._loading_generation or not _loading_screen.visible:
			main_node._world_building = false
			return

	main_node._remote_cursors = main_node._load_scene(Main.REMOTE_CURSORS_SCENE_PATH).instantiate() as RemoteCursors
	main_node.add_child(main_node._remote_cursors)

	# Bontago-d5c.6 (M5 P5): a HotSeat instance always binds Net.local_slot()
	# (0 on the host, whether online, offline or the headless-bots path
	# above), so it must not be built when that slot itself is a bot -- the
	# all-bot `--bots=<n>` acceptance command (config.player_count ==
	# config.ai_count, no `--players=` override) leaves no human slot at all.
	# A mixed lobby match (some humans, some bots) still gets it exactly as
	# before: humans always fill the lowest slot ids first (MatchLifecycle.
	# _build_slots()'s `is_bot = i >= player_count - ai_count`), so
	# Net.local_slot() is never a bot slot on any path but this one.
	# Bontago-8or.11: a mid-match spectator (Net.local_slot() == -1) gets no
	# controller at all.
	# DECISION (Bontago-8or.11): it watches through the default camera rig
	# with no HotSeat -- there is no slot for one to drive.
	if config.ai_count < config.player_count and Net.local_slot() >= 0:
		var hot_seat: HotSeat = main_node._load_scene(Main.HOT_SEAT_SCENE_PATH).instantiate() as HotSeat
		main_node._hot_seat = hot_seat
		main_node.add_child(hot_seat)
		hot_seat.set_camera_rig(_camera_rig)
		hot_seat.set_field(_field)
		hot_seat.bind_local_slot(Net.local_slot())
		# Bontago-mv0.26 (owner test 2026-09-22, "the original lets me keep moving
		# once I hit the edge of the screen"): HotSeat.gd's own _ready() already
		# calls this unconditionally (this scene is the exact same HOT_SEAT_SCENE_PATH scene
		# --hot-seat uses), so it should already be captured by the time
		# add_child() above returns. Called again here, explicitly, the same way
		# HotSeat.gd/Sandbox.gd each call it for their own subtree: this world
		# build is the one place that wires a controller into a match Main itself
		# owns, so it gets its own direct call rather than depending solely on a
		# child scene's _ready() timing -- idempotent (enable_mouse_capture() just
		# re-sets Input.mouse_mode) and a no-op headless, so it changes nothing
		# for --headless-host or the test suite.
		hot_seat.controller().enable_mouse_capture()
		main_node._controller_was_processing = hot_seat.controller().is_processing()
		main_node._controller_was_handling_input = hot_seat.controller().is_processing_unhandled_input()
		if stage_build:
			hot_seat.controller().set_process(false)
			hot_seat.controller().set_process_unhandled_input(false)

	spawn_bot_controllers(config)

	# M8 P5's single wiring point (docs/M8_PLAN.md P5): built here, right
	# alongside _spawn_bot_controllers() above, for the same reason every
	# other host-only match manager already lives in this function --
	# BlockRegistry.all_blocks() only has anything to scan once _registry
	# itself is populated, which SnapshotSync.begin_match(Match.registry(),
	# ...) above has already done by this point.
	main_node._stable_block_manager = StableBlockManager.new()
	main_node.add_child(main_node._stable_block_manager)
	main_node._stable_block_manager.setup(_registry)

	main_node._debug_overlay = main_node._load_scene(Main.NET_DEBUG_OVERLAY_SCENE_PATH).instantiate() as NetDebugOverlay
	main_node.add_child(main_node._debug_overlay)

	# Bontago-xtq.26 (M7 P1): re-applies the current preset once the match
	# world exists. _world_environment is a static child of Main today, so
	# this is a no-op repeat of the _ready()-time call -- kept here anyway
	# because this is the one shared scene-load path (lobby-driven and
	# headless-bot matches alike), so a later package that adds a
	# WorldEnvironment under the field rebuilt above (P3's FogVolume) picks up
	# the current preset without this package having to guess at that
	# not-yet-built structure.
	main_node._apply_graphics_preset(Settings.current_graphics_preset())
	main_node._world_built = true
	main_node._world_building = false


## docs/archive/M5_PLAN.md P5 item 3: one BotController per bot slot, for the
## headless-only-bots path above (_start_headless_bot_match_with_args()'s own
## Match.start_match() reaches this function too, via Events.match_state_
## changed -- see its own doc) and an ordinary mixed human+bot lobby match
## alike -- the trailing `config.ai_count` slots, exactly matching
## MatchLifecycle._build_slots()'s own `is_bot` assignment
## (`i >= player_count - ai_count`). Host-gated inside BotController itself
## (`game/BotController.gd`'s own `_is_host()` check), so building one on a
## client too costs nothing and stays inert.
##
## Lobby rework (Bontago-1pi.53): each bot gets its own seat's difficulty
## (MatchConfig.ai_difficulty_for_slot(): slot_ai_difficulties[slot] when the
## lobby set per-seat values, else the lobby-wide ai_difficulty -- so `--bots=N`,
## sandbox and every older config keep the single shared difficulty).
func spawn_bot_controllers(config: MatchConfig) -> void:
	var first_bot_slot: int = config.player_count - config.ai_count
	for slot_id: int in range(first_bot_slot, config.player_count):
		var bot: BotController = BotController.new()
		main_node.add_child(bot)
		bot.setup(slot_id, config.ai_difficulty_for_slot(slot_id), _field, _registry)
		main_node._bot_controllers.append(bot)


## Bontago-1pi.46 (owner playtest: "leaving match and starting a new match
## doesn't reset properly ... my camera and zoom level were the same as when i
## left the old match and the arena still had rain puddles"; owner requirement:
## after leaving a match and starting another, everything is as if freshly
## launched). ROOT CAUSE: the CameraRig, the Field's RainPuddles layer and a
## number of autoloads/presentation nodes are persistent, so they outlived every
## match; a match start re-aimed only the camera's yaw/target, and puddles dry
## over RainTuning.puddle_dry_time_s. This is the one presentation-reset entry
## (docs/MATCH_RESET_AUDIT.md section 4): Main resets the children it owns
## directly, then emits Events.match_scope_reset for every persistent owner it
## cannot name. Run when a match world is built, when one is torn down (also a
## cancelled staged build and a menu sandbox/tutorial) and on a sandbox reset;
## synchronous and idempotent, so the next match starts like a fresh launch.
## `reset_camera` is false only for a sandbox reset (F5), where the player keeps
## their view.
func _reset_match_scope(reset_camera: bool = true) -> void:
	RainPuddles.clear_on(_field)
	if reset_camera and _camera_rig != null:
		_camera_rig.reset_view()
	Events.match_scope_reset.emit()


func end_match_world() -> void:
	# Bontago-1pi.46 (G5). DECISION: the scope reset runs before the _world_built
	# early return, so every (-> LOBBY) -- including a staged build that was
	# cancelled before it finished (_world_built still false), and a CLI
	# --sandbox, which never sets it -- leaves a launch-state camera, dry arena
	# and reset persistent owners. Such a half-built world still touched the
	# Field (flags, rebuild, overlay), so it is cleared here too. Idempotent: a
	# net leave reaches this twice (mode change, then the abort's -> LOBBY).
	if not main_node._world_built:
		_field.clear_match_state()
		_reset_match_scope()
		return
	main_node._world_built = false
	main_node._stop_headless_bots_diagnostics()
	SnapshotSync.end_match()
	# Field is persistent (unlike everything else torn down below) and Match's
	# own teardown never touches it, so its flags, overlay raster reference
	# and open holes would otherwise still belong to the match that just ended
	# (Beads Bontago-mv0.1.9).
	_field.clear_match_state()
	# Bontago-1pi.46: and the menu/lobby behind it looks like a fresh launch too.
	_reset_match_scope()
	if main_node._remote_cursors != null and is_instance_valid(main_node._remote_cursors):
		main_node._remote_cursors.queue_free()
	main_node._remote_cursors = null
	if main_node._hot_seat != null and is_instance_valid(main_node._hot_seat):
		main_node._hot_seat.queue_free()
	main_node._hot_seat = null
	for bot: BotController in main_node._bot_controllers:
		if bot != null and is_instance_valid(bot):
			bot.queue_free()
	main_node._bot_controllers.clear()
	if main_node._stable_block_manager != null and is_instance_valid(main_node._stable_block_manager):
		main_node._stable_block_manager.queue_free()
	main_node._stable_block_manager = null
	if main_node._debug_overlay != null and is_instance_valid(main_node._debug_overlay):
		main_node._debug_overlay.queue_free()
	main_node._debug_overlay = null
