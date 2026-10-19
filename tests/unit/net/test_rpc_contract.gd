extends GutTest
## Golden RPC contract: the guard for every netcode change. The six replicated
## nodes (Net, MatchNet, SnapshotSync, WeatherNet, SnowNet, BreezeNet; 39 RPCs)
## must keep the wire surface recorded in fixtures/rpc_contract_golden.json.
##
## What is pinned (tests/support/RpcSurface.gd builds it from the loaded
## scripts): per RPC the mode, transfer mode, channel and call_local; the
## argument names, types and defaults; the sorted name list, the ids (index in
## that list) and their md5 (the one value the engine compares across peers);
## the node paths; and the layout constants a packet depends on
## (SnapshotSync.PACKET_VERSION and offsets, MatchNet.RASTER_VERSION, the
## EVENT_* names, the LAN advert port).
##
## VERSION-BUMP POLICY. The golden keeps `history`: {config/version: md5 of the
## whole surface}. The live surface must equal the golden `surface` AND its md5
## must equal the history entry of the current `application/config/version`.
## An intended wire change (RPC added, removed or renamed, argument list, mode,
## channel or transfer change, snapshot/raster/event layout change) therefore
## needs, in the same commit: (a) a bump of `application/config/version` in
## project.godot (orchestrator-owned), (b) a new history entry, (c) the updated
## `surface`, and (d) never an edit of an existing history entry. Reviewers check
## the golden diff. A package that must change the wire says so and waits for
## the orchestrator instead of editing this file.
##
## Regenerate only through res://tools/gen_rpc_golden.tscn, never by hand.

const GOLDEN_PATH: String = "res://tests/unit/net/fixtures/rpc_contract_golden.json"
const VERSION_SETTING: String = "application/config/version"
const EXPECTED_TOTAL: int = 39
## Production code adds these children by name (the parent script source holds
## `<var>.name = "<child>"`); the engine node path depends on it.
const CHILD_NAME_ASSIGNMENT: String = ".name = \"%s\""

var _golden: Dictionary
var _live: Dictionary


func before_all() -> void:
	_golden = _load_golden()
	_live = RpcSurface.normalise(RpcSurface.build()) as Dictionary


func test_golden_file_is_well_formed() -> void:
	assert_true(_golden.has("history"), "golden has a history table")
	assert_true(_golden.has("surface"), "golden has a surface")
	assert_true(_golden.get("history") is Dictionary and not (_golden["history"] as Dictionary).is_empty(), "history is a non-empty table")


func test_rpc_counts_total_39() -> void:
	var nodes: Dictionary = _live["nodes"] as Dictionary
	for key: String in RpcSurface.EXPECTED_COUNTS.keys():
		assert_eq(int((nodes[key] as Dictionary)["rpc_count"]), int(RpcSurface.EXPECTED_COUNTS[key]), "%s RPC count" % key)
	assert_eq(int(_live["rpc_total"]), EXPECTED_TOTAL, "total production RPCs")


func test_each_node_matches_golden() -> void:
	var golden_nodes: Dictionary = (_golden["surface"] as Dictionary)["nodes"] as Dictionary
	var live_nodes: Dictionary = _live["nodes"] as Dictionary
	assert_eq(live_nodes.keys().size(), golden_nodes.keys().size(), "same set of replicated nodes")
	for key: String in golden_nodes.keys():
		assert_true(live_nodes.has(key), "%s is still a replicated node" % key)
		if live_nodes.has(key):
			_assert_node_equal(key, live_nodes[key] as Dictionary, golden_nodes[key] as Dictionary)


func test_wire_constants_match_golden() -> void:
	var golden_constants: Dictionary = (_golden["surface"] as Dictionary)["constants"] as Dictionary
	var live_constants: Dictionary = _live["constants"] as Dictionary
	for key: String in golden_constants.keys():
		assert_eq(live_constants.get(key), golden_constants[key], "wire constant group %s" % key)
	assert_eq(live_constants.keys().size(), golden_constants.keys().size(), "no new wire constant group without a golden entry")


func test_snapshot_and_raster_versions_are_pinned_by_name() -> void:
	# Redundant with the golden on purpose: these two are the values a layout
	# change must bump, so they fail with a readable message of their own.
	var constants: Dictionary = _live["constants"] as Dictionary
	var snapshot: Dictionary = constants["res://net/SnapshotSync.gd"] as Dictionary
	var raster: Dictionary = constants["res://net/MatchNet.gd"] as Dictionary
	assert_eq(int(snapshot["PACKET_VERSION"]), 2, "SnapshotSync.PACKET_VERSION")
	assert_eq(int(raster["RASTER_VERSION"]), 1, "MatchNet.RASTER_VERSION")


func test_surface_md5_matches_history_for_current_version() -> void:
	var version: String = String(ProjectSettings.get_setting(VERSION_SETTING, ""))
	var history: Dictionary = _golden["history"] as Dictionary
	assert_true(history.has(version), "golden history has an entry for config/version %s (an intended wire change bumps the version and adds an entry)" % version)
	if history.has(version):
		assert_eq(RpcSurface.surface_md5(_live), String(history[version]), "live surface md5 equals the history entry for %s" % version)


func test_golden_surface_md5_is_a_history_entry() -> void:
	# Editing `surface` without adding its md5 to the history cannot pass.
	var history: Dictionary = _golden["history"] as Dictionary
	var recorded: String = RpcSurface.surface_md5(_golden["surface"] as Dictionary)
	assert_true(history.values().has(recorded), "golden surface md5 %s is recorded in history" % recorded)


func test_rpc_ids_follow_the_sorted_name_list() -> void:
	for key: String in (_live["nodes"] as Dictionary).keys():
		var node: Dictionary = (_live["nodes"] as Dictionary)[key] as Dictionary
		var names: Array = node["names"] as Array
		var sorted_names: Array = names.duplicate()
		sorted_names.sort()
		assert_eq(names, sorted_names, "%s names are in id order" % key)
		for index: int in names.size():
			assert_eq(int((node["ids"] as Dictionary)[names[index]]), index, "%s id of %s" % [key, names[index]])
		assert_eq(String(node["names_md5"]), RpcSurface.names_md5(names), "%s names md5" % key)


func test_node_paths_follow_production_wiring() -> void:
	for node: Dictionary in RpcSurface.NODES:
		var key: String = String(node["key"])
		var path: String = String((_live["nodes"] as Dictionary)[key]["node_path"])
		assert_eq(path, String(node["node_path"]), "%s node path in the surface" % key)
		if node.has("autoload"):
			var setting: String = String(ProjectSettings.get_setting("autoload/%s" % String(node["autoload"]), "")).trim_prefix("*")
			assert_eq(setting, String(node["script"]), "%s is the autoload at /root/%s" % [key, String(node["autoload"])])
			assert_eq(path, "/root/%s" % String(node["autoload"]), "%s path is /root/<autoload>" % key)
		else:
			var parent: Script = load(String(node["parent_script"])) as Script
			var expected: String = CHILD_NAME_ASSIGNMENT % String(node["child_name"])
			assert_true(parent.source_code.contains(expected), "%s adds the child with %s" % [String(node["parent_script"]), expected])
			assert_true(path.ends_with("/" + String(node["child_name"])), "%s path ends with its child name" % key)


func test_bare_node_exposes_rpcs_only_through_its_script() -> void:
	# Engine fact the helper relies on: Node.get_node_rpc_config() is empty for
	# script-declared @rpc methods, the script holds them.
	var script: Script = load("res://net/BreezeNet.gd") as Script
	var node: Node = script.new() as Node
	assert_true(node.get_node_rpc_config() == null or (node.get_node_rpc_config() as Dictionary).is_empty(), "bare node has no node-level rpc config")
	assert_true((script.get_rpc_config() as Dictionary).has(&"net_breeze_gust") or (script.get_rpc_config() as Dictionary).has("net_breeze_gust"), "script carries net_breeze_gust")
	node.free()


func _load_golden() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(GOLDEN_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("rpc contract golden is missing or not a JSON object: %s" % GOLDEN_PATH)
		return { }
	return parsed as Dictionary


## Names the RPC that drifted instead of dumping two large dictionaries.
func _assert_node_equal(key: String, live: Dictionary, golden: Dictionary) -> void:
	for field: String in ["script", "node_path", "rpc_count", "names", "ids", "names_md5"]:
		assert_eq(live.get(field), golden.get(field), "%s %s" % [key, field])
	var live_methods: Dictionary = live["methods"] as Dictionary
	var golden_methods: Dictionary = golden["methods"] as Dictionary
	for rpc_name: String in golden_methods.keys():
		assert_true(live_methods.has(rpc_name), "%s.%s still exists" % [key, rpc_name])
		if live_methods.has(rpc_name):
			assert_eq(live_methods[rpc_name], golden_methods[rpc_name], "%s.%s mode/channel/transfer/args" % [key, rpc_name])
	for rpc_name: String in live_methods.keys():
		assert_true(golden_methods.has(rpc_name), "%s.%s is a new RPC not in the golden" % [key, rpc_name])
