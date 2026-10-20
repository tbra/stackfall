class_name RpcSurface
extends RefCounted
## Builds the wire surface of the six replicated nodes as plain data, for the
## golden contract test (tests/unit/net/test_rpc_contract.gd).
##
## Engine facts this relies on (checked in the 4.7.2 engine source,
## modules/multiplayer/scene_rpc_interface.cpp and scene/main/node.cpp):
##  - A script's `@rpc` methods live in `Script.get_rpc_config()`; the node-level
##    `Node.get_node_rpc_config()` stays empty for them, so a bare instance
##    reports nothing and the surface is read from the loaded script instead
##    (the same dictionary the engine merges into its cache).
##  - The RPC id is the index in the name-sorted list of those methods, and the
##    only cross-peer check is an md5 of the concatenated sorted names. Mode,
##    channel, transfer mode and argument lists are NOT checked by the engine,
##    which is why this surface records them: a drift there is silent.
##
## Nothing here instantiates a node, so building the surface has no side
## effects and needs no multiplayer peer.

## One entry per replicated node: script, the engine node path it is reached
## by, and the parent script plus the child name the parent adds it under
## (empty for autoloads, whose path is /root/<autoload name>).
const NODES: Array[Dictionary] = [
	{
		"key": "Net",
		"script": "res://autoload/Net.gd",
		"node_path": "/root/Net",
		"autoload": "Net",
	},
	{
		"key": "MatchNet",
		"script": "res://net/MatchNet.gd",
		"node_path": "/root/MatchNet",
		"autoload": "MatchNet",
	},
	{
		"key": "SnapshotSync",
		"script": "res://net/SnapshotSync.gd",
		"node_path": "/root/SnapshotSync",
		"autoload": "SnapshotSync",
	},
	{
		"key": "WeatherNet",
		"script": "res://net/WeatherNet.gd",
		"node_path": "/root/MatchNet/WeatherNet",
		"parent_script": "res://net/MatchNet.gd",
		"child_name": "WeatherNet",
	},
	{
		"key": "SnowNet",
		"script": "res://net/SnowNet.gd",
		"node_path": "/root/MatchNet/WeatherNet/SnowNet",
		"parent_script": "res://net/WeatherNet.gd",
		"child_name": "SnowNet",
	},
	{
		"key": "BreezeNet",
		"script": "res://net/BreezeNet.gd",
		"node_path": "/root/MatchNet/WeatherNet/BreezeNet",
		"parent_script": "res://net/WeatherNet.gd",
		"child_name": "BreezeNet",
	},
]

## Production RPC count per node (spec 2.6); the sum is the program's 39.
const EXPECTED_COUNTS: Dictionary = {
	"Net": 17,
	"MatchNet": 18,
	"SnapshotSync": 1,
	"WeatherNet": 1,
	"SnowNet": 1,
	"BreezeNet": 1,
}

## Integer constants that define a packet layout or a channel, per script.
## A change to any of them is a wire change even when no RPC signature moves.
## The SnapshotSync group key is kept for golden stability; its values are read
## from SnapshotWire, which owns them.
const LAYOUT_CONSTANTS: Dictionary = {
	"res://net/SnapshotSync.gd": [
		"PACKET_VERSION", "HEADER_BYTES", "DISK_STATE_BYTES", "FLAG_DISK_STATE",
		"FLAG_KEYFRAME", "SNAPSHOT_CHANNEL", "OFFSET_VERSION", "OFFSET_SEQUENCE",
		"OFFSET_FRAGMENT_INDEX", "OFFSET_FRAGMENT_COUNT", "OFFSET_HOST_TIME",
		"OFFSET_FLAGS", "OFFSET_BODY_COUNT", "SEQUENCE_MODULUS", "MAX_FRAGMENTS",
	],
	"res://net/MatchNet.gd": ["RASTER_VERSION", "CURSOR_CHANNEL"],
}

## Layout group key -> script that actually defines its constants.
const LAYOUT_SOURCES: Dictionary = {
	"res://net/SnapshotSync.gd": "res://core/net/SnapshotWire.gd",
}

const EVENT_PREFIX: String = "EVENT_"
const _NET_CONFIG_SCRIPT: GDScript = preload("res://config/net/NetConfig.gd")
const _NET_CONFIG_RES: String = "res://config/net/net_config.tres"


## Everything the golden pins, as JSON-safe data (strings, ints, bools, arrays,
## dictionaries). Keys are stable; dictionary order is irrelevant.
static func build() -> Dictionary:
	var nodes: Dictionary = { }
	var total: int = 0
	for node: Dictionary in NODES:
		var entry: Dictionary = _node_surface(node)
		nodes[String(node["key"])] = entry
		total += int(entry["rpc_count"])
	return {
		"nodes": nodes,
		"rpc_total": total,
		"constants": _wire_constants(),
	}


## Round-trips through JSON so a live surface compares equal to a parsed golden
## (JSON turns every number into a float and drops Godot types).
static func normalise(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))


## md5 of the whole surface: the value the golden history keeps per
## `application/config/version`.
static func surface_md5(surface: Dictionary) -> String:
	return JSON.stringify(surface, "", true).md5_text()


## The value the engine compares across peers: md5 of the concatenated names in
## id order.
static func names_md5(names: Array) -> String:
	var joined: String = ""
	for entry: Variant in names:
		joined += String(entry)
	return joined.md5_text()


static func _node_surface(node: Dictionary) -> Dictionary:
	var script: Script = load(String(node["script"])) as Script
	var config: Dictionary = script.get_rpc_config() as Dictionary if script != null else { }
	var names: Array = []
	var configs: Dictionary = { }
	for key: Variant in config.keys():
		names.append(String(key))
		configs[String(key)] = config[key]
	names.sort()
	var method_index: Dictionary = { }
	if script != null:
		for method: Dictionary in script.get_script_method_list():
			method_index[String(method["name"])] = method
	var methods: Dictionary = { }
	for rpc_name: String in names:
		methods[rpc_name] = _method_surface(
			configs[rpc_name] as Dictionary,
			method_index.get(rpc_name, { }) as Dictionary,
		)
	var ids: Dictionary = { }
	for index: int in names.size():
		ids[names[index]] = index
	return {
		"script": node["script"],
		"node_path": node["node_path"],
		"rpc_count": names.size(),
		"names": names,
		"ids": ids,
		"names_md5": names_md5(names),
		"methods": methods,
	}


static func _method_surface(cfg: Dictionary, method: Dictionary) -> Dictionary:
	var args: Array = []
	for arg: Dictionary in method.get("args", []) as Array:
		args.append(
			{
				"name": String(arg.get("name", "")),
				"type": int(arg.get("type", 0)),
				"class_name": String(arg.get("class_name", "")),
			},
		)
	var defaults: Array = []
	for value: Variant in method.get("default_args", []) as Array:
		defaults.append(var_to_str(value))
	var return_info: Dictionary = method.get("return", { }) as Dictionary
	return {
		"rpc_mode": int(cfg.get("rpc_mode", MultiplayerAPI.RPC_MODE_AUTHORITY)),
		"transfer_mode": int(cfg.get("transfer_mode", MultiplayerPeer.TRANSFER_MODE_RELIABLE)),
		"channel": int(cfg.get("channel", 0)),
		"call_local": bool(cfg.get("call_local", false)),
		"args": args,
		"default_args": defaults,
		"return_type": int(return_info.get("type", 0)),
	}


static func _wire_constants() -> Dictionary:
	var out: Dictionary = { }
	for path: String in LAYOUT_CONSTANTS.keys():
		var script: Script = load(LAYOUT_SOURCES.get(path, path)) as Script
		var map: Dictionary = script.get_script_constant_map()
		var values: Dictionary = { }
		for const_name: String in LAYOUT_CONSTANTS[path] as Array:
			values[const_name] = int(map.get(const_name, -1))
		out[path] = values
	var match_script: Script = load("res://net/MatchNet.gd") as Script
	var events: Array = []
	var match_consts: Dictionary = match_script.get_script_constant_map()
	for const_name: Variant in match_consts.keys():
		if String(const_name).begins_with(EVENT_PREFIX) and typeof(match_consts[const_name]) == TYPE_STRING_NAME:
			events.append(String(match_consts[const_name]))
	events.sort()
	out["match_event_names"] = events
	var default_config: Variant = _NET_CONFIG_SCRIPT.new()
	var shipped_config: Variant = load(_NET_CONFIG_RES)
	out["discovery_port_default"] = int(default_config.discovery_port)
	out["discovery_port_shipped"] = int(shipped_config.discovery_port)
	return out
