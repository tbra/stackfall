class_name MainFlowPort
extends RefCounted
## Tiny base of the typed ports Main uses to reach flow code that is loaded on
## demand. It names no heavy class_name and no autoload facade type, so Main.gd
## can hold one without compiling the match/sandbox graph.
## Implementations (game/main/MainSandboxFlow.gd, MainHeadlessBotsFlow.gd, MainMatchFlow.gd) extend
## the per-flow port and are obtained through MenuPrewarmQueue.ensure_script().

## The Main node; implementations re-type it locally as `main_node: Main`.
var main: Node3D = null


func bind(main_node: Node3D) -> void:
	main = main_node


## STUB (P7 plan section 2.1): the transitional `main`/`bind()` above stay until P7-Inav.
signal lobby_requested
signal menu_requested

var world: MainWorld = null


func bind_world(w: MainWorld) -> void:
	world = w
