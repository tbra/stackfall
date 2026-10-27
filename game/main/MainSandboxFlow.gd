class_name MainSandboxFlow
extends MainSandboxFlowPort
## The sandbox and tutorial entry points, split out of game/main/Main.gd
## so Main.gd does not compile Sandbox/Tutorial.
## Main loads this script on demand through MenuPrewarmQueue.ensure_script() and keeps one-line
## forwarders for every old member name tests/tools call. DECISION: this file reads Main's
## underscore-prefixed state through `main_node` (one module split in two; tests already do).

## The Main node, typed (the port's `main` is the Node3D it binds).
var main_node: Main:
	get:
		return main as Main


## The tutorial's lesson, read before its scene exists: the config's demo gift is the only one
## the match may grant (MatchLaunch.tutorial_config).
const TUTORIAL_LESSON_PATH: String = "res://config/match/tutorial_config.tres"


## `godot --path . -- --sandbox [--players=N] [--force-special=<id>]`: the same path the menu entry takes.
func start_sandbox_match() -> void:
	start_sandbox_match_with_args(OS.get_cmdline_user_args())


## Split from start_sandbox_match() so a test can drive both the --players= parsing and the
## resulting world build with a manufactured argument list.
func start_sandbox_match_with_args(args: PackedStringArray) -> void:
	_launch_sandbox(null, args)


func start_sandbox_from_menu() -> void:
	_launch_sandbox(null, PackedStringArray())


## The Debug page's Gift demo: the sandbox with config/match/sandbox_gift_demo.tres
## (pre-placed opponent towers, gifts on at high frequency).
func start_gift_demo_from_menu() -> void:
	if not DebugMode.is_enabled():
		return
	_launch_sandbox(load(Main.GIFT_DEMO_PRESET_PATH) as SandboxConfig, PackedStringArray())


## The Debug page's Tower topple: the sandbox with config/match/sandbox_tower_topple.tres.
func start_tower_topple_from_menu() -> void:
	if not DebugMode.is_enabled():
		return
	_launch_sandbox(load(Main.TOWER_TOPPLE_PRESET_PATH) as SandboxConfig, PackedStringArray())


func start_tutorial_from_menu() -> void:
	var lesson: TutorialConfig = load(TUTORIAL_LESSON_PATH) as TutorialConfig
	launch(MatchLaunch.tutorial_config(main_node.match_config, lesson), ModeExtras.tutorial())


func _launch_sandbox(preset: SandboxConfig, args: PackedStringArray) -> void:
	var players: int = MatchLaunch.sandbox_player_count(args, preset, main_node.sandbox_config)
	var forced: StringName = MatchLaunch.forced_special_arg(args)
	# --force-special is a debug tool; ignored unless debug mode.
	if not DebugMode.is_enabled():
		forced = &""
	launch(MatchLaunch.sandbox_config(main_node.match_config, players, preset), ModeExtras.sandbox(preset, forced))


## Starts a non-lobby match: the one world builder (MainMatchFlow) does the rest and calls
## attach_extras() once the local player exists.
func launch(config: MatchConfig, extras: ModeExtras) -> void:
	world.mode_extras = extras
	Match.register_world(world.field, world.registry, world.blocks_container)
	Match.start_match(config)


## Adds the mode's node to the freshly built world. Runs inside build_match_world, after it
## unsuppressed the pause menu, and before the match is PLAYING.
func attach_extras(extras: ModeExtras, local_player: Node) -> void:
	var player: LocalPlayer = local_player as LocalPlayer
	if extras.kind == ModeExtras.Kind.SANDBOX:
		var sandbox: Sandbox = world.loader.load_scene(Main.SANDBOX_SCENE_PATH).instantiate() as Sandbox
		world.sandbox = sandbox
		world.parent.add_child(sandbox)
		sandbox.attach(player, world.camera_rig, world.field, extras)
		# DECISION: no scoreboard in the sandbox; Tab stays sandbox_next_slot.
		# SHORTCUT: lazy overlay owned by Main, removed by P7-Inav
		if main_node._scoreboard_node != null:
			main_node._scoreboard_node.suppressed = true
	else:
		var tutorial: Tutorial = world.loader.load_scene(Main.TUTORIAL_SCENE_PATH).instantiate() as Tutorial
		world.tutorial = tutorial
		world.parent.add_child(tutorial)
		tutorial.attach(player)
		tutorial.finished.connect(on_tutorial_finished)
		# See PauseMenu's `suppressed` doc: Tutorial owns ui_cancel/Escape for its own quit gesture.
		# SHORTCUT: lazy overlay owned by Main, removed by P7-Inav
		main_node._pause_menu.suppressed = true


## Tutorial's `finished` (step 5, END, or its quit gesture): it already aborted the match, so the
## world and the Tutorial node are gone or going; only the menu is left to show.
func on_tutorial_finished() -> void:
	# SHORTCUT: menu owned by Main, removed by P7-Inav
	main_node._show_main_menu()
