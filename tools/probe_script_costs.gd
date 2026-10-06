extends Node
## Bontago-1pi.11.53 probe: marginal synchronous load time of Main.gd's dependencies, in order.
const PATHS: Array[String] = [
	"res://ui/MainMenu.gd", "res://ui/Lobby.gd", "res://game/HotSeat.gd", "res://game/Sandbox.gd",
	"res://ui/Tutorial.gd", "res://game/RemoteCursors.gd", "res://ui/NetDebugOverlay.gd",
	"res://ui/PauseMenu.gd", "res://ui/ResultsScreen.gd", "res://ui/ScoreboardOverlay.gd",
	"res://ui/LoadingScreen.gd", "res://game/Main.gd",
]


func _ready() -> void:
	for path: String in PATHS:
		var t0: int = Time.get_ticks_msec()
		load(path)
		print("SCRIPT_COST ", path, " ", Time.get_ticks_msec() - t0, " ms")
	get_tree().quit()
