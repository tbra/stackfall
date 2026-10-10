class_name MainFlowPort
extends RefCounted
## Bontago-1pi.11.84 (MF0): tiny base of the typed ports Main uses to reach flow code that is
## loaded on demand (see docs/MENU_FIRST_PLAN.md 3.1). It names no heavy class_name and no
## autoload facade type, so Main.gd can hold one without compiling the match/sandbox graph.
## Implementations (game/MainSandboxFlow.gd, MainHeadlessBotsFlow.gd, MainMatchFlow.gd) extend
## the per-flow port and are obtained through MenuPrewarmQueue.ensure_script().

## The Main node; implementations re-type it locally as `main_node: Main`.
var main: Node3D = null


func bind(main_node: Node3D) -> void:
	main = main_node


## Drops state held for a torn-down world.
func release() -> void:
	pass
