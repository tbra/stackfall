class_name MainNodes
extends RefCounted
## Reads a Main scene the way a player's tree shows it: nodes found by class under Main, ignoring
## any already queued for deletion. Replaces reads of Main's private fields (_lobby, _main_menu,
## _local_player, _world_built, ...) so tests keep working when the flows own that state.


## The first live node of `type_name` (a class_name) anywhere under `main`, or null.
static func first(main: Node, type_name: StringName) -> Node:
	for node: Node in main.find_children("*", String(type_name), true, false):
		if not node.is_queued_for_deletion():
			return node
	return null


static func count(main: Node, type_name: StringName) -> int:
	var total: int = 0
	for node: Node in main.find_children("*", String(type_name), true, false):
		if not node.is_queued_for_deletion():
			total += 1
	return total


## True while a match world is built: the StableBlockManager is created once per built world and
## freed with it (a staged build adds it just before the world counts as built).
static func world_is_built(main: Node) -> bool:
	return first(main, &"StableBlockManager") != null


static func lobby(main: Node) -> Lobby:
	return first(main, &"Lobby") as Lobby


static func main_menu(main: Node) -> MainMenu:
	return first(main, &"MainMenu") as MainMenu


static func pause_menu(main: Node) -> PauseMenu:
	return first(main, &"PauseMenu") as PauseMenu


static func results_screen(main: Node) -> ResultsScreen:
	return first(main, &"ResultsScreen") as ResultsScreen


static func loading_screen(main: Node) -> LoadingScreen:
	return first(main, &"LoadingScreen") as LoadingScreen


static func local_player(main: Node) -> LocalPlayer:
	return first(main, &"LocalPlayer") as LocalPlayer
