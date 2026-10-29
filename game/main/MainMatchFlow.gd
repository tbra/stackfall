class_name MainMatchFlow
extends MainMatchFlowPort
## The match-world flow (state routing, loading hand-off, world build/teardown,
## bot controllers, scope reset), split out of game/main/Main.gd.
## Main keeps one forwarder per name and loads this script before the first match_state_changed
## reaction (the client's net_match_start RPC arrives with no Main involvement, so the Main
## forwarder of `_on_match_state_changed` always ensures this flow first). Per-match node fields live here;
## this file reaches Main's scene helpers through `main_node` (DECISION: one
## module split in two, as MainSandboxFlow does). The loading-generation guard lives here
## (`_loading_generation`) and every coroutine here re-checks `is_instance_valid(main)` after an await.

const HUD_SCENE_PATH: String = "res://ui/hud/HUD.tscn"
const TUNING_PANEL_SCENE_PATH: String = "res://ui/debug/TuningPanel.tscn"
const POSE_OVERLAY_PATH: String = "res://ui/debug/PoseOverlay.tscn"
## Loaded by path (debug builds only): the bot code behind it stays out of the compile closure.
const BOT_COST_OVERLAY_PATH: String = "res://ui/debug/PerfBotCostOverlay.gd"

## The Main node, typed (the port's `main` is the Node3D it binds).
var main_node: Main:
	get:
		return main as Main

# Per-match nodes and flags this flow owns (they used to sit on Main).
var _local_player: Node = null
var _spectator: Node = null
var _remote_cursors: Node = null
## F2 pose, F3 net and F9 bot-cost panels: round debugs, so they live and die with the match world.
var _debug_overlays: Array[Node] = []
var _stable_block_manager: Node = null
var _bot_controllers: Array[Node] = []
var _controller_was_processing: bool = false
var _controller_was_handling_input: bool = false
var _world_built: bool = false
var _world_building: bool = false
## The Lobby's Start press is awaiting its pre-start frames.
var _start_pending: bool = false
var _first_territory_ready: bool = false
## Bumped on every new load and every return to the lobby; a stale hand-off coroutine sees it differ and stops.
var _loading_generation: int = 0

# Read-only views of Main's persistent world nodes.
var _field: Field:
	get:
		return main_node._field
var _registry: BlockRegistry:
	get:
		return main_node._registry
var _camera_rig: CameraRig:
	get:
		return main_node._camera_rig
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
	# Spec 2.6: joining is lobby-only unless the config allows mid-match joins. Net must not name Match, so the
	# match flow flips Net's gate here, where every state change is routed: a
	# handshake arriving while the match is past LOBBY is refused with
	# JoinError.MATCH_IN_PROGRESS, and abort_match()'s (old -> LOBBY) emit
	# reopens it (Net.leave() also resets it itself). On a client this is a
	# harmless flag write; _rpc_handshake is host-gated.
	#
	# spec 2.6 "Mid-match joins can be enabled in settings":
	# a live match also admits new joiners when its config allows it. LOADING
	# (synchronous on the host) and END stay closed; MatchNet replays the
	# world to whoever is admitted. Net is told when a match world starts and
	# when the session really returns to the lobby -- not the transient LOBBY
	# a replay/restart passes through inside start_match() -- so it can keep
	# and drop rejoin reservations and reseat spectators.
	if to_state == Match.State.LOADING:
		Net.set_match_in_progress(true)
	elif to_state == Match.State.LOBBY and not Match.lifecycle().is_starting_match():
		Net.set_match_in_progress(false)
	var live_state: bool = Match.is_replicating(to_state)
	var mid_match_join: bool = live_state and Match.config != null and Match.config.allow_mid_match_join
	Net.set_accepting_joins(to_state == Match.State.LOBBY or mid_match_join)

	if to_state == Match.State.LOBBY:
		_loading_generation += 1
		end_match_world()
		# safety net for a match aborted mid-load -- see
		# LoadingScreen.cancel()'s own doc.
		_loading_screen.cancel()
		# A results-screen return ends the match without changing Net's mode,
		# so _on_net_mode_changed() cannot rebuild the lobby for us. A replay
		# briefly passes through LOBBY inside start_match(); keep that transition
		# out of the UI route so the new match builds directly.
		if not Match.lifecycle().is_starting_match() and not Net.is_offline():
			if world.watch_bots_active:
				# a watch match has no lobby to return to; Back to menu leaves the
				# session, which routes to the main menu (Main._on_net_mode_changed).
				Net.leave()
			else:
				main_node._show_lobby()
	elif Match.is_start_transition(from_state, to_state):
		_loading_generation += 1
		_first_territory_ready = false
		# shown before _build_match_world() below runs, so the
		# overlay is already queued to composite over this same frame's draw
		# pass -- see ui/menus/LoadingScreen.gd's own header doc.
		var skip_loading: bool = world.mode_extras != null and world.mode_extras.skips_loading_screen()
		if not skip_loading:
			_loading_screen.show_for_match(Match.config, main_node._loading_screen_slots())
		# DECISION: the 3-2-1 must start once the loading screen
		# is gone, not run down behind it. Held from here until
		# _finish_loading_when_ready() releases it (a reset/abort also clears it).
		# Skipped headless: no loading screen is ever rendered there, and tests
		# and bot harnesses drive Match by hand.
		if not skip_loading and DisplayServer.get_name() != "headless":
			Match.set_countdown_held(true)
		build_match_world()
	elif to_state == Match.State.COUNTDOWN:
		_finish_loading_when_ready(_loading_generation)


func _finish_loading_when_ready(generation: int) -> void:
	while not _world_built:
		await main_node.get_tree().process_frame
		# DECISION: Main may be freed while this coroutine is suspended.
		if not is_instance_valid(main):
			return
		if generation != _loading_generation or not _loading_screen.visible:
			_release_countdown_hold(generation)
			return
	if not _loading_screen.visible:
		_release_countdown_hold(generation)
		return
	_loading_screen.set_stage("Solving territory", _loading_screen.tuning.solve_progress)
	while not _first_territory_ready:
		await main_node.get_tree().process_frame
		# DECISION: Main may be freed while this coroutine is suspended.
		if not is_instance_valid(main):
			return
		if generation != _loading_generation or not _loading_screen.visible:
			_release_countdown_hold(generation)
			return
	_loading_screen.set_stage("Warming materials", _loading_screen.tuning.materials_progress)
	_loading_screen.warm_common_materials()
	for frame: int in range(_loading_screen.tuning.stable_frames):
		await main_node.get_tree().process_frame
		# DECISION: Main may be freed while this coroutine is suspended.
		if not is_instance_valid(main):
			return
		if generation != _loading_generation or not _loading_screen.visible:
			_release_countdown_hold(generation)
			return
		_loading_screen.set_stage("Stabilizing view", lerpf(_loading_screen.tuning.stabilize_start_progress, _loading_screen.tuning.stabilize_end_progress, float(frame + 1) / maxf(float(_loading_screen.tuning.stable_frames), 1.0)))
	_loading_screen.set_stage("Ready", _loading_screen.tuning.complete_progress)
	# the camera starts at the local player's own beacon, looking
	# at the centre, whatever the loading frames did to it.
	if _local_player != null and _camera_rig != null:
		_camera_rig.begin_start_framing(Net.local_slot())
	if _local_player != null:
		(_local_player as LocalPlayer).controller().set_process(_controller_was_processing)
		(_local_player as LocalPlayer).controller().set_process_unhandled_input(_controller_was_handling_input)
	await _loading_screen.fade_out()
	# DECISION: Main may be freed while this coroutine is suspended.
	if not is_instance_valid(main):
		return
	# the screen is gone; now the 3-2-1 starts running down.
	_release_countdown_hold(generation)


## Every exit of the loading hand-off (overlay already hidden, cancelled, timed
## out, superseded) must free the countdown hold, or a match could sit held. A
## stale generation belongs to a newer load, which owns the hold now, so only the
## current generation releases.
func _release_countdown_hold(generation: int) -> void:
	if generation == _loading_generation:
		Match.set_countdown_held(false)


## Match.start_match() runs the whole world build synchronously
## in one frame, so an overlay shown inside it is never presented before the
## freeze. The Lobby's Start button therefore lands here first: the overlay (and
## the clients' net_match_loading) goes up, tuning.pre_start_frames rendered
## frames pass, and only then _start_requested_match() starts the match.
## There is no separate match scene to thread-load: Main already hosts the
## world, and the skybox jpgs are decoded from raw files, not ResourceLoader
## resources.
func on_lobby_start_pressed(config: MatchConfig) -> void:
	if not Net.is_host() or _start_pending:
		return
	_start_pending = true
	main_node._ensure_overlays()
	_loading_screen.show_pending(config)
	MatchNet.replicate_match_loading()
	for _i: int in range(_loading_screen.tuning.pre_start_frames):
		await main_node.get_tree().process_frame
		# Main may be freed while this coroutine is suspended.
		if not is_instance_valid(main):
			return
	_start_pending = false
	if not Net.is_host() or not _loading_screen.is_pending():
		return
	_start_requested_match(config)


func _start_requested_match(config: MatchConfig) -> void:
	if not Net.is_host():
		return
	Match.start_match(config)


## Client side of on_lobby_start_pressed(): raise the overlay as soon as the host announces.
func on_match_loading_announced() -> void:
	if Match.state() != Match.State.LOBBY:
		return
	main_node._prefetch_match_scenes()
	main_node._ensure_overlays()  # a client may reach LOADING without ever having built the lobby overlays
	_loading_screen.show_pending(null)


func on_loading_territory_updated(_raster: TerritoryRaster, _groups: TerritoryGroups) -> void:
	# DECISION: an applied result can arrive while the staged world is building.
	if Net.is_host() and _loading_screen_is_running():
		_first_territory_ready = true


func on_loading_territory_replicated(_raster: TerritoryRaster) -> void:
	if Net.is_client() and _loading_screen_is_running():
		_first_territory_ready = true


func on_loading_readiness_timed_out() -> void:
	_release_countdown_hold(_loading_generation)
	_loading_generation += 1
	if Net.is_host():
		Match.abort_match()
	else:
		Net.leave()


## The overlay exists, is up and is past its pending stage. Reads the raw node: the getter would build it.
func _loading_screen_is_running() -> bool:
	var screen: LoadingScreen = main_node._loading_screen_node
	return screen != null and screen.visible and not screen.is_pending()


func build_match_world() -> void:
	if _world_built or _world_building:
		return
	_world_building = true
	var generation: int = _loading_generation
	# the single new-match entry (host, client and headless
	# alike) -- starts from the launch camera and a dry arena whatever the
	# previous match left behind, and tells the persistent owners (Events.
	# match_scope_reset) to do the same. Runs before configure_match_sky() below.
	_reset_match_scope()
	# DECISION: only a visible interactive overlay needs frame-separated stages.
	# Headless hosts and test/probe runs retain the synchronous start contract.
	var stage_build: bool = _loading_screen != null and _loading_screen.visible and DisplayServer.get_name() != "headless" and not AgentProbe.is_active()
	main_node._clear_menu_and_lobby()
	_pause_menu.suppressed = false

	var config: MatchConfig = Match.config
	_field.rebuild_for_map(config.map_def())
	_camera_rig.set_map_def(config.map_def())
	_loading_screen.set_stage("Placing flags", _loading_screen.tuning.flags_progress)
	if stage_build:
		await main_node.get_tree().process_frame
		# DECISION: Main may be freed while this coroutine is suspended.
		if not is_instance_valid(main):
			return
		if generation != _loading_generation or not _loading_screen.visible:
			_world_building = false
			return
	_field.place_flags(config.player_count, config.player_colors, config.effective_goal_flag_count())
	_loading_screen.set_stage("Preparing territory", _loading_screen.tuning.territory_progress)
	if stage_build:
		await main_node.get_tree().process_frame
		# DECISION: Main may be freed while this coroutine is suspended.
		if not is_instance_valid(main):
			return
		if generation != _loading_generation or not _loading_screen.visible:
			_world_building = false
			return
	_field.set_overlay_source(Match.raster(), config.territory_colors())
	main_node._apply_match_sky(config)
	# the lobby's Day/Night/Random, resolved by the host and
	# replicated; the F4 Theme dropdown still overrides live afterwards.

	SnapshotSync.set_disk(_field)
	SnapshotSync.begin_match(Match.registry(), config.map_def())
	_loading_screen.set_stage("Preparing players", _loading_screen.tuning.players_progress)
	if stage_build:
		await main_node.get_tree().process_frame
		# DECISION: Main may be freed while this coroutine is suspended.
		if not is_instance_valid(main):
			return
		if generation != _loading_generation or not _loading_screen.visible:
			_world_building = false
			return

	_remote_cursors = main_node._load_scene(Main.REMOTE_CURSORS_SCENE_PATH).instantiate() as RemoteCursors
	main_node.add_child(_remote_cursors)

	# A LocalPlayer instance always binds Net.local_slot() (0 on the host), so it must not
	# be built when that slot is a bot: the all-bot `--bots=<n>` command
	# (config.player_count == config.ai_count) leaves no human slot. A mixed lobby
	# match still gets it: humans fill the lowest slot ids first
	# (MatchLifecycle._build_slots()'s `is_bot = i >= player_count - ai_count`).
	# A mid-match spectator (Net.local_slot() == -1) gets no controller at all.
	# DECISION: it watches through the default camera rig
	# with no LocalPlayer -- there is no slot for one to drive.
	if world.watch_bots_active and DebugMode.is_enabled():
		build_spectator(config)
	elif config.ai_count < config.player_count and Net.local_slot() >= 0:
		var local_player: LocalPlayer = main_node._load_scene(Main.LOCAL_PLAYER_SCENE_PATH).instantiate() as LocalPlayer
		_local_player = local_player
		main_node.add_child(local_player)
		local_player.set_camera_rig(_camera_rig)
		local_player.set_field(_field)
		local_player.bind_local_slot(Net.local_slot())
		# LocalPlayer.gd's _ready() already captures the mouse; called again here because
		# this is the one place that wires a controller into a match Main owns, so
		# it does not depend on a child scene's _ready() timing. Idempotent and a
		# no-op headless.
		local_player.controller().enable_mouse_capture()
		_controller_was_processing = local_player.controller().is_processing()
		_controller_was_handling_input = local_player.controller().is_processing_unhandled_input()
		if stage_build:
			local_player.controller().set_process(false)
			local_player.controller().set_process_unhandled_input(false)
		main_node._attach_mode_extras(local_player)

	spawn_bot_controllers(config)

	# Single wiring point for the stable-block manager, alongside
	# _spawn_bot_controllers(): BlockRegistry.all_blocks() only has anything to scan
	# once _registry is populated, which SnapshotSync.begin_match() above has done.
	_stable_block_manager = StableBlockManager.new()
	main_node.add_child(_stable_block_manager)
	_stable_block_manager.setup(_registry)

	_build_debug_overlays()

	# Re-applies the current preset once the match world exists. world.world_environment is
	# a static child of Main, so today this repeats the _ready()-time call; kept
	# because this is the one shared scene-load path (lobby-driven and headless-bot
	# matches alike).
	main_node._apply_graphics_preset(Settings.current_graphics_preset())
	_world_built = true
	_world_building = false


## The round debug panels, built with the world and freed with it, so F2/F3/F9 do nothing in the
## menus and lobby and close when the match ends. F2 and F9 are debug builds only; F3 gates its own
## toggle on DebugMode.
func _build_debug_overlays() -> void:
	var net: Node = main_node._load_scene(Main.NET_DEBUG_OVERLAY_SCENE_PATH).instantiate()
	_debug_overlays.append(net)
	if DebugMode.is_enabled():
		var debug_config: DebugConfig = DebugMode.config()
		var pose: Node = main_node._load_scene(POSE_OVERLAY_PATH).instantiate()
		pose.set(&"config", debug_config)
		pose.set(&"camera", _camera_rig.get_camera())
		pose.set(&"field", _field)
		_debug_overlays.append(pose)
		var bot_cost: Node = (load(BOT_COST_OVERLAY_PATH) as GDScript).new() as Node
		bot_cost.set(&"config", debug_config)
		_debug_overlays.append(bot_cost)
	for overlay: Node in _debug_overlays:
		main_node.add_child(overlay)


## debug Watch bots: the local player's whole presence in an all-bot match -- spectator
## camera, follow / speed controls and the match HUD -- in place of a LocalPlayer.
func build_spectator(config: MatchConfig) -> void:
	var spectator: SpectatorController = SpectatorController.new()
	_spectator = spectator
	main_node.add_child(spectator)
	spectator.setup(_camera_rig, config.player_count)
	spectator.build_presentation(main_node._load_scene(HUD_SCENE_PATH), main_node._load_scene(TUNING_PANEL_SCENE_PATH), _field)


## One BotController per bot slot (the trailing `config.ai_count` slots, matching
## MatchLifecycle._build_slots()'s `is_bot` assignment), for both the
## headless-only-bots path (_start_headless_bot_match_with_args() reaches this via
## Events.match_state_changed) and an ordinary mixed human+bot lobby match.
## Host-gated inside BotController (`_is_host()`), so building one on a client costs
## nothing and stays inert.
##
## Each bot gets its own seat's difficulty (MatchConfig.ai_difficulty_for_slot():
## slot_ai_difficulties[slot] when the lobby set per-seat values, else the
## lobby-wide ai_difficulty).
func spawn_bot_controllers(config: MatchConfig) -> void:
	var first_bot_slot: int = config.player_count - config.ai_count
	for slot_id: int in range(first_bot_slot, config.player_count):
		var bot: BotController = BotController.new()
		main_node.add_child(bot)
		bot.setup(slot_id, config.ai_difficulty_for_slot(slot_id), _field, _registry)
		_bot_controllers.append(bot)


## The one presentation-reset entry for a fresh-launch match start. The CameraRig,
## the Field's RainPuddles layer and a number of autoloads/presentation nodes are
## persistent and would otherwise outlive every match (a match start re-aims only
## the camera's yaw/target; puddles dry over RainTuning.puddle_dry_time_s). Main
## resets the children it owns directly, then emits Events.match_scope_reset for
## every persistent holder it cannot name. Run when a match world is built, when
## one is torn down (also a cancelled staged build); synchronous and idempotent.
func _reset_match_scope() -> void:
	RainPuddles.clear_on(_field)
	if _camera_rig != null:
		_camera_rig.reset_view()
	Events.match_scope_reset.emit()


## A restart passes through (X -> LOBBY) inside start_match(); the build that follows
## resets the scope itself, so the pair resets once.
func _reset_match_scope_unless_restarting() -> void:
	if not Match.lifecycle().is_starting_match():
		_reset_match_scope()


func is_world_live() -> bool:
	return _world_built or _world_building


func end_match_world() -> void:
	# DECISION: the scope reset runs before the _world_built
	# early return, so every (-> LOBBY) -- including a staged build that was
	# cancelled before it finished (_world_built still false) -- leaves a
	# launch-state camera, dry arena and reset persistent owners. Such a half-built world still touched the
	# Field (flags, rebuild, overlay), so it is cleared here too. Idempotent: a
	# net leave reaches this twice (mode change, then the abort's -> LOBBY).
	if not _world_built:
		SnapshotSync.end_match()
		_field.clear_match_state()
		_reset_match_scope_unless_restarting()
		_end_mode_extras()
		return
	_world_built = false
	main_node._stop_headless_bots_diagnostics()
	SnapshotSync.end_match()
	# Field is persistent (unlike everything else torn down below) and Match's
	# own teardown never touches it, so its flags, overlay raster reference
	# and open holes would otherwise still belong to the match that just ended.
	_field.clear_match_state()
	# and the menu/lobby behind it looks like a fresh launch too.
	_reset_match_scope_unless_restarting()
	if _remote_cursors != null and is_instance_valid(_remote_cursors):
		_remote_cursors.queue_free()
	_remote_cursors = null
	_free_inert(_local_player)
	_local_player = null
	_end_mode_extras()
	if _spectator != null and is_instance_valid(_spectator):
		(_spectator as SpectatorController).reset_speed()
		_spectator.queue_free()
	_spectator = null
	for bot: BotController in _bot_controllers:
		if bot != null and is_instance_valid(bot):
			bot.queue_free()
	_bot_controllers.clear()
	if _stable_block_manager != null and is_instance_valid(_stable_block_manager):
		_stable_block_manager.queue_free()
	_stable_block_manager = null
	for overlay: Node in _debug_overlays:
		if is_instance_valid(overlay):
			overlay.queue_free()
	_debug_overlays.clear()


## Disabling the subtree first stops its _process/_input at once; queue_free() only
## frees at the end of the frame.
func _free_inert(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.process_mode = Node.PROCESS_MODE_DISABLED
	node.queue_free()


## A mode's node goes with its world; the mode itself ends only on a real return to
## the lobby, not on the (X -> LOBBY) half of a restart. Inert for a lobby match.
func _end_mode_extras() -> void:
	if world.mode_extras == null:
		return
	if world.sandbox != null and main_node._scoreboard_node != null:
		main_node._scoreboard_node.suppressed = false
	_free_inert(world.sandbox)
	world.sandbox = null
	_free_inert(world.tutorial)
	world.tutorial = null
	if not Match.lifecycle().is_starting_match():
		world.mode_extras = null
