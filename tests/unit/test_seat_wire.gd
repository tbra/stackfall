extends GutTest
## LobbySeats roster-entry wire (Bontago-fca.36.8 part B): the writer keeps the legacy
## byte layout, the validator pins what a client accepts and rejects.

const HOST_ID: int = 1
const PEER_ID: int = 7
const SLOT: int = 3
const BIG: int = 2147483647


func _legacy_joiner() -> Dictionary:
	return {
		"peer_id": PEER_ID, "slot_id": SLOT, "name": "Ann", "name_auto": false,
		"ready": false, "ping_ms": 0.0, "build": "1.0",
	}


func _wire() -> Dictionary:
	return LobbySeats.entry_to_wire(PEER_ID, SLOT, "Ann", false, 0.0, "1.0", true, false)


func test_joiner_entry_matches_legacy_layout() -> void:
	var entry: Dictionary = _wire()
	assert_eq(entry, _legacy_joiner())
	assert_eq(entry.keys(), _legacy_joiner().keys(), "key order unchanged")
	assert_eq(typeof(entry["ping_ms"]), TYPE_FLOAT)


func test_host_entry_has_no_name_auto() -> void:
	var entry: Dictionary = LobbySeats.entry_to_wire(HOST_ID, 0, "Host", false, 0.0, "1.0")
	assert_eq(entry, {"peer_id": 1, "slot_id": 0, "name": "Host", "ready": false, "ping_ms": 0.0, "build": "1.0"})
	assert_false(entry.has("name_auto"))


func test_round_trip_accepts() -> void:
	assert_eq(LobbySeats.entry_from_wire(_wire()), _legacy_joiner())
	var host: Dictionary = LobbySeats.entry_to_wire(HOST_ID, 0, "H", true, 12.5, "")
	assert_eq(LobbySeats.entry_from_wire(host), host)


func test_spectator_and_large_midmatch_slot_accepted() -> void:
	for slot: int in [-1, 0, 8, 500, BIG]:
		var entry: Dictionary = _wire()
		entry["slot_id"] = slot
		assert_false(LobbySeats.entry_from_wire(entry).is_empty(), "slot %d" % slot)


func test_rejects_non_dictionary() -> void:
	for bad: Variant in [null, 5, "x", [], PackedInt32Array([1])]:
		assert_true(LobbySeats.entry_from_wire(bad).is_empty())


func test_rejects_missing_each_key() -> void:
	for key: String in _legacy_joiner().keys():
		var entry: Dictionary = _wire()
		entry.erase(key)
		var accepted: bool = not LobbySeats.entry_from_wire(entry).is_empty()
		# name_auto is the only optional key.
		assert_eq(accepted, key == "name_auto", "missing %s" % key)


func test_rejects_extra_key() -> void:
	var entry: Dictionary = _wire()
	entry["token"] = "abc"
	assert_true(LobbySeats.entry_from_wire(entry).is_empty())


func test_rejects_out_of_range_ids() -> void:
	var cases: Array[Dictionary] = [
		{"slot_id": -2}, {"slot_id": BIG + 1}, {"peer_id": 0}, {"peer_id": -5}, {"peer_id": BIG + 1},
	]
	for patch: Dictionary in cases:
		var entry: Dictionary = _wire()
		for key: String in patch:
			entry[key] = patch[key]
		assert_true(LobbySeats.entry_from_wire(entry).is_empty(), str(patch))


func test_rejects_wrong_types() -> void:
	var cases: Array[Dictionary] = [
		{"peer_id": 7.0}, {"peer_id": "7"}, {"slot_id": 3.0}, {"slot_id": null}, {"name": 5},
		{"name": "x".repeat(LobbySeats.ROSTER_NAME_MAX + 1)}, {"ready": 1}, {"ready": "true"},
		{"name_auto": 0}, {"ping_ms": "1"}, {"ping_ms": INF}, {"ping_ms": NAN}, {"ping_ms": -1.0},
		{"build": 1}, {"build": "x".repeat(LobbySeats.ROSTER_BUILD_MAX + 1)},
	]
	for patch: Dictionary in cases:
		var entry: Dictionary = _wire()
		for key: String in patch:
			entry[key] = patch[key]
		assert_true(LobbySeats.entry_from_wire(entry).is_empty(), str(patch))


func test_ping_int_is_normalised_to_float() -> void:
	var entry: Dictionary = _wire()
	entry["ping_ms"] = 5
	var clean: Dictionary = LobbySeats.entry_from_wire(entry)
	assert_eq(typeof(clean["ping_ms"]), TYPE_FLOAT)


## Net._rpc_roster_update on a client: malformed entries are skipped (before: a
## non-Dictionary entry crashed the handler, any dictionary was trusted).
func test_client_roster_update_skips_malformed_entries() -> void:
	var net: Node = (preload("res://autoload/Net.gd") as GDScript).new()
	add_child_autofree(net)
	net._mode = net.Mode.CLIENT
	var good: Dictionary = _wire()
	var bad_slot: Dictionary = _wire()
	bad_slot["peer_id"] = 9
	bad_slot["slot_id"] = -7
	var roster: Array = [good, bad_slot, null, "x", {"peer_id": 5}]
	net._rpc_roster_update(roster)
	assert_eq(net.peer_ids(), PackedInt32Array([PEER_ID]))
	assert_eq(net.peer_info(PEER_ID), _legacy_joiner())
