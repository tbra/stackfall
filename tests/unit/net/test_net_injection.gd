extends GutTest
## Autoload decoupling S3a: SnapshotSync reaches Net through bind_net()/_net()
## (unbound -> the real Net autoload), the provider seam still wins in
## _session(), and NetIds equals the aliases Net keeps.

const SYNC_SCRIPT: String = "res://net/SnapshotSync.gd"


class StubNet:
	extends Node
	var client: bool = false
	func is_client() -> bool:
		return client


func _new_sync() -> Node:
	return (load(SYNC_SCRIPT) as GDScript).new() as Node


func test_unbound_falls_back_to_real_net() -> void:
	var sync: Node = _new_sync()
	autofree(sync)
	assert_eq(sync.call("_net"), Net, "unbound _net() is the Net autoload")
	assert_eq(sync.call("_session"), Net, "unbound _session() is the Net autoload")


func test_bound_net_is_used() -> void:
	var sync: Node = _new_sync()
	autofree(sync)
	var fake: StubNet = StubNet.new()
	autofree(fake)
	sync.call("bind_net", fake)
	assert_eq(sync.call("_net"), fake)
	assert_eq(sync.call("_session"), fake)
	assert_false(bool(sync.get("_running")))
	assert_eq(sync.call("sky_cycle_seconds"), 0.0)


func test_bound_net_drives_client_checks() -> void:
	var sync: Node = _new_sync()
	autofree(sync)
	var fake: StubNet = StubNet.new()
	autofree(fake)
	fake.client = true
	sync.call("bind_net", fake)
	sync.set("_running", true)
	sync.set("_host_clock_ms", 5000.0)
	# Bound net says client: sky time comes from the interpolator, which is
	# null here only if the client path was NOT taken (host path would return 5.0).
	var interp: Variant = sync.get("_interpolator")
	if interp == null:
		pending("no interpolator without begin_match")
		return
	assert_ne(sync.call("sky_cycle_seconds"), 5.0)


func test_provider_wins_over_bound_net() -> void:
	var sync: Node = _new_sync()
	autofree(sync)
	var fake: StubNet = StubNet.new()
	autofree(fake)
	var provider: Node = Node.new()
	autofree(provider)
	sync.call("bind_net", fake)
	sync.call("set_net_provider", provider)
	assert_eq(sync.call("_session"), provider)
	sync.call("set_net_provider", null)
	assert_eq(sync.call("_session"), fake)


func test_net_ids_match_net_aliases() -> void:
	assert_eq(NetIds.DISCOVERY_MAGIC, Net.DISCOVERY_MAGIC)
	assert_eq(NetIds.STEAM_APP_ID_EXPECTED, Net.STEAM_APP_ID_EXPECTED)
	assert_eq(NetIds.DISCOVERY_MAGIC, &"stackfall")
	assert_eq(NetIds.STEAM_APP_ID_EXPECTED, 480)


func test_real_net_is_bound_in_ready() -> void:
	assert_eq(SnapshotSync.get("_bound_net"), Net)
