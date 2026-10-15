extends SceneTree
## Headless probe for the GodotSteam GDExtension setup.
##
## Confirms the GodotSteam GDExtension classes are registered and exercises
## Steam.steamInitEx() without assuming a running Steam client. Never calls the
## bare Steam.steamInit() (it can crash in the editor).
##
## Run with:
##   godot --headless --path . -s res://tools/steam_probe.gd
##
## Not part of the shipped game; lives in tools/ as a build-time diagnostic
## per CLAUDE.md's folder layout rule.

const STEAM_APP_ID: int = 480 # Steam's public test app ("Spacewar"), spec §3.4.

func _initialize() -> void:
	var has_steam_class: bool = ClassDB.class_exists(&"Steam")
	var has_peer_class: bool = ClassDB.class_exists(&"SteamMultiplayerPeer")
	print("ClassDB.class_exists(\"Steam\") = %s" % has_steam_class)
	print("ClassDB.class_exists(\"SteamMultiplayerPeer\") = %s" % has_peer_class)

	if not has_steam_class:
		print("GodotSteam extension not loaded in this checkout; proceeding without Steam.")
		quit(0)
		return

	# Extension-optional pattern: reach the
	# singleton as Object through Engine.get_singleton() and call through .call()
	# rather than a bare Steam. identifier to keep the script parseable when the
	# addon is absent, matching net/SteamClient.gd's own pattern.
	var steam: Object = Engine.get_singleton(&"Steam")
	var init_result: Dictionary = steam.call("steamInitEx", STEAM_APP_ID, false)
	print("Steam.steamInitEx(%d, false) = %s" % [STEAM_APP_ID, init_result])
	quit(0)
