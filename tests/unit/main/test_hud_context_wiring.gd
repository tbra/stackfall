extends GutTest
## Each builder hands the HUD and the scoreboard the match context it was given (LocalPlayer, the spectator
## presentation) or the installed one (Main's scoreboard), so they read the match through one port.
## The globally installed context is a different object in every test, so only the handed-over one can pass.

const LOCAL_PLAYER_SCENE: PackedScene = preload("res://game/main/LocalPlayer.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/hud/HUD.tscn")
const TUNING_PANEL_SCENE: PackedScene = preload("res://ui/debug/TuningPanel.tscn")
const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")

var _installed: FakeMatchContext = null
var _previous: MatchContext = null


func before_each() -> void:
	_previous = MatchContext.installed()
	_installed = FakeMatchContext.new()
	MatchContext.install(_installed)


func after_each() -> void:
	MatchContext.install(_previous)
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()


func _local_player(context: MatchContext) -> LocalPlayer:
	var player: LocalPlayer = autofree(LOCAL_PLAYER_SCENE.instantiate())
	# LocalPlayer.match_context is declared by the wiring package; set() keeps this file compiling before then.
	player.set(&"match_context", context)
	add_child_autofree(player)
	return player


func test_local_player_hud_reads_the_context_assigned_before_add_child() -> void:
	var given: FakeMatchContext = FakeMatchContext.new()
	var player: LocalPlayer = _local_player(given)
	assert_same(player.hud().match_context, given)


func test_local_player_hud_follows_a_context_reassigned_before_binding_the_slot() -> void:
	var player: LocalPlayer = _local_player(FakeMatchContext.new())
	var later: FakeMatchContext = FakeMatchContext.new()
	player.set(&"match_context", later)
	player.bind_local_slot(0)
	assert_same(player.hud().match_context, later)


func test_spectator_hud_reads_the_context_passed_to_build_presentation() -> void:
	var given: FakeMatchContext = FakeMatchContext.new()
	var spectator: SpectatorController = SpectatorController.new()
	add_child_autofree(spectator)
	spectator.setup(null, 2)
	# The wiring package adds the MatchContext parameter (last); callv keeps this file compiling before then.
	spectator.callv(&"build_presentation", [HUD_SCENE, TUNING_PANEL_SCENE, null, given])
	var hud: HUD = MainNodes.first(spectator, &"HUD") as HUD
	assert_not_null(hud, "the spectator presentation builds a HUD")
	if hud != null:
		assert_same(hud.match_context, given)


func test_main_scoreboard_reads_the_installed_context() -> void:
	var main: Node = MAIN_SCENE.instantiate()
	var tiny: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny.field_radius = 20.0
	(main.get_node("Field") as Field).map_def = tiny
	add_child_autofree(main)
	assert_eq(Net.host_game(0, "Host", false), OK)
	var scoreboard: ScoreboardOverlay = MainNodes.first(main, &"ScoreboardOverlay") as ScoreboardOverlay
	assert_not_null(scoreboard, "hosting builds the scoreboard")
	if scoreboard != null:
		assert_same(scoreboard.match_context, _installed)
