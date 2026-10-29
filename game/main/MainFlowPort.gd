class_name MainFlowPort
extends RefCounted
## Tiny base of the typed ports Main uses to reach flow code that is loaded on
## demand. It names no heavy class_name and no autoload facade type, so Main.gd
## can hold one without compiling the match/sandbox graph.
## Implementations (game/main/MainSandboxFlow.gd, MainHeadlessBotsFlow.gd, MainMatchFlow.gd) extend
## the per-flow port and are obtained through MenuPrewarmQueue.ensure_script().
## Flows never reach Main: they read `world` and ask Main for navigation through these signals.

## The flow wants the session lobby / the main menu shown.
signal lobby_requested
signal menu_requested
## A mode set the in-match overlays' `suppressed` flags (Main applies them to the overlays it owns).
signal overlays_suppressed(scoreboard: bool, pause_menu: bool)

var world: MainWorld = null


func bind_world(w: MainWorld) -> void:
	world = w
