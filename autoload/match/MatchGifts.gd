class_name MatchGifts
extends RefCounted
## Match's gift-crate lifecycle (spec 2.6): per-window spawn rolls, the
## territory-tick claim/expire sweep, and the per-slot pending-special array
## P2 reads (held_special()/_clear_held_special()).
##
## Split out the same way MatchFeed/MatchPlacement/MatchTerritory/MatchLifecycle
## are (docs/AGENT_WORKFLOW.md "file ownership over function ownership"): a
## RefCounted wired to autoload/Match.gd via setup(self) in Match's own
## _ready(), so it never walks the scene tree looking for its collaborators.
##
## Host-only logic is gated exactly like MatchTerritory's (`if not
## _match._is_host(): return`); a client only ever mirrors the three replicated
## gift events into visuals via apply_replicated_*() below and never claims or
## spawns anything itself.

var _match: MatchAutoload = null
var _gift_config: GiftConfig = preload("res://config/gift_config.tres")

const GIFT_CRATE_SCENE: PackedScene = preload("res://game/GiftCrate.tscn")

## The placeholder special id every claim hands out in M4 P1 (docs/M4_PLAN.md
## P2 defines the real SpecialDef roster and swaps the held shape where
## _clear_held_special() already runs; P1 only needs one stable, inspectable
## value so held_special() is meaningful before that roster exists).
const PENDING_SPECIAL_ID: StringName = &"special_pending"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rng_ready: bool = false
var _next_gift_id: int = 0

## Live, unclaimed crates: gift_id -> {"position": Vector2 (disk-local),
## "age": float, "node": GiftCrate}. Every entry, host or client mirror, is
## created and freed only through _make_crate_node()/_free_crate_visual() so
## the two paths cannot drift.
var _crates: Dictionary = {}

## Parallel to Match's slots (see MatchLifecycle._build_slots()): the pending
## special each slot is holding, or &"" for none. Grown lazily by
## _ensure_capacity() rather than sized off slot_count() at reset() time,
## because _reset_match_state() runs *before* the new match's slots are built
## (autoload/match/MatchLifecycle.gd's start_match(): reset, then
## _build_slots()) -- see that file's one-line reset() call below.
var _held_specials: Array[StringName] = []

## Lazily created the first time a crate needs a visual (host spawn or client
## mirror), as a SIBLING of Match's own blocks_parent (a child of that node's
## own parent) -- never a child of blocks_parent itself. Review fix (regression
## found while re-validating this change): blocks_parent's children are
## trusted elsewhere to be exactly the placed Blocks (test_match_flow.gd's
## `_blocks_root.get_child_count()`/`get_child(0)` assumption, and the same
## contract BlockRegistry/SnapshotSync rely on) -- a GiftCrates container
## parented there broke that the moment any match, hot-seat included, rolled
## a real spawn. Freed and re-created by reset() rather than reused across
## matches so a stale crate can never survive into a new one.
var _container: Node3D = null


func setup(match_ref: MatchAutoload) -> void:
	_match = match_ref


## The pending special `slot_id` is holding, or &"" for none. P2 reads this to
## decide whether the next spawned block should be a special.
func held_special(slot_id: int) -> StringName:
	if slot_id < 0 or slot_id >= _held_specials.size():
		return &""
	return _held_specials[slot_id]


## Reconciling this with docs/M4_PLAN.md P2's own text (review fix 4): P2's
## `_spawn_block()` extension (autoload/match/MatchPlacement.gd) runs before
## MatchFeed._consume_and_refeed()'s clear -- request_place() resolves and
## spawns the physical Block for the *currently* held shape first, and only
## afterwards consumes/refeeds the slot -- so P2 reading held_special() inside
## _spawn_block() always sees the value this package's on_feed_block_issued()
## set for that slot's *previous* window, never the one this same placement
## is about to clear. P2 is therefore safe to read held_special() there
## without moving anything in this file.
func _clear_held_special(slot_id: int) -> void:
	if slot_id < 0 or slot_id >= _held_specials.size():
		return
	_held_specials[slot_id] = &""


func _ensure_capacity(slot_id: int) -> void:
	while _held_specials.size() <= slot_id:
		_held_specials.append(&"")


## DECISION (autoload/match/MatchGifts.gd, M4 P1b): "the feed issues a new
## window" is Events.feed_block_issued -- MatchFeed._issue_next_block() emits
## it every time any slot is handed a new held piece, on an early release, a
## forced auto-drop, or a hot-seat turn change alike. autoload/Match.gd
## connects this to Events.feed_block_issued and forwards slot_id here; both
## the special-clear and the spawn-roll gate below share the one connection
## since P2's own clear needs the identical "a slot's next block was just
## issued" moment.
##
## The clear always runs, for every slot, every window. The *roll* is gated
## by _should_roll_for_window() below -- see review fix (Beads Bontago-4fa):
## outside hot-seat every slot's window advances independently (spec 2.4's
## "players act concurrently, each handling their own supplied piece"), so
## rolling here unconditionally gave an N-player match ~N rolls per window
## instead of GiftSpawner.should_spawn()'s documented "one roll per window,
## for the whole match, not per player".
func on_feed_block_issued(slot_id: int) -> void:
	if not _match._is_host():
		return
	_clear_held_special(slot_id)
	if not _should_roll_for_window(slot_id):
		return
	_try_spawn()


## DECISION (autoload/match/MatchGifts.gd, Bontago-4fa): outside hot-seat,
## every slot's own window fires this signal independently, so rolling on
## every one of them would multiply the match-wide roll by player_count. The
## lowest-indexed slot that still has a home flag stands in for "the match's
## own window" here -- it need not be synchronized with anyone else's timer
## (early releases desync individual slots' windows over time), but it is
## always exactly one slot at any instant, which is all should_spawn()'s
## contract actually needs: one roll, somewhere, per window. Hot-seat already
## has only one slot issuing at a time, so it always rolls (spec 2.4's
## turn-based mode needs no such gate).
func _should_roll_for_window(slot_id: int) -> bool:
	if _match.config == null:
		return false
	if _match.config.hot_seat:
		return true
	return slot_id == _lowest_alive_slot()


func _lowest_alive_slot() -> int:
	for i: int in range(_match.slot_count()):
		var slot: PlayerSlot = _match.slot(i)
		if slot != null and slot.home_flag_alive:
			return i
	return -1


func _try_spawn() -> void:
	if _match.config == null or not _match.config.gifts_enabled:
		return
	var raster: TerritoryRaster = _match.raster()
	var grid: CellGrid = _match.cell_grid()
	if raster == null or grid == null:
		return
	_ensure_rng()
	if not GiftSpawner.should_spawn(_gift_config, float(_match.config.special_frequency), _crates.size(), _rng):
		return
	var point: Vector2 = GiftSpawner.pick_spawn_point(raster, grid, _rng, _gift_config)
	if GiftSpawner.is_no_spawn_point(point):
		return
	_spawn_crate_at(point)


## DECISION (autoload/match/MatchGifts.gd): rng_seed + a large odd offset,
## the same stride convention MatchFeed._build_bags() uses per slot, so a
## fixed match seed reproduces gift spawns deterministically without ever
## colliding with a slot's own bag sequence. Lazy (not done in setup()/reset())
## because reset() runs before start_match() assigns the new config.
func _ensure_rng() -> void:
	if _rng_ready:
		return
	_rng_ready = true
	if _match.config != null and _match.config.rng_seed >= 0:
		_rng.seed = _match.config.rng_seed + 999983
	else:
		_rng.randomize()


func _spawn_crate_at(point: Vector2) -> void:
	var gift_id: int = _next_gift_id
	_next_gift_id += 1
	_crates[gift_id] = {"position": point, "age": 0.0, "node": _make_crate_node(point)}
	Events.gift_spawned.emit(gift_id, point)


## Runs once per territory solve tick, right after autoload/Match.gd's
## _run_territory_step() forward updates the raster, so team_at() below reads
## this tick's freshest ownership. `delta` is the same step the territory
## solve just ran with, so a crate's age advances in real time regardless of
## TerritoryTuning.solve_hz.
func claim_or_expire_gifts(delta: float) -> void:
	if not _match._is_host():
		return
	if _crates.is_empty():
		return
	var raster: TerritoryRaster = _match.raster()
	var grid: CellGrid = _match.cell_grid()
	if raster == null or grid == null:
		return

	var to_claim: Dictionary = {}
	var to_expire: Array[int] = []
	for gift_id: int in _crates.keys():
		var entry: Dictionary = _crates[gift_id]
		var age: float = float(entry["age"]) + delta
		entry["age"] = age
		var position: Vector2 = entry["position"]
		var cell: Vector2i = grid.world_to_cell(position)
		# DECISION (autoload/match/MatchGifts.gd, per docs/M4_PLAN.md P1):
		# M4 ships with MatchConfig.team_count() == player_count
		# (free-for-all only), so team_at()'s team id and the claiming
		# slot id are the same number here. Revisit once M6 wires real
		# teams -- which teammate's next block becomes the special is
		# genuinely ambiguous then and is not decided by this file.
		var team: int = raster.team_at(cell.x, cell.y) if grid.in_bounds(cell.x, cell.y) else -1
		if team >= 0:
			to_claim[gift_id] = team
		elif age >= _gift_config.life_s:
			to_expire.append(gift_id)

	for gift_id: int in to_claim.keys():
		_claim_gift(gift_id, int(to_claim[gift_id]))
	for gift_id: int in to_expire:
		_expire_gift(gift_id)


## DECISION (autoload/match/MatchGifts.gd, Bontago-59u): a new claim REPLACES
## an existing pending special -- latest wins, never queued. There is only one
## placeholder id in P1, so this matters only in that a second claim does not
## error or stack; P2's real roster is where two different pending ids would
## actually make the replacement observable end to end.
func _claim_gift(gift_id: int, team_id: int) -> void:
	if not _free_crate_visual(gift_id):
		return
	_ensure_capacity(team_id)
	if team_id >= 0 and team_id < _held_specials.size():
		_held_specials[team_id] = PENDING_SPECIAL_ID
	Events.gift_claimed.emit(gift_id, team_id)


func _expire_gift(gift_id: int) -> void:
	if not _free_crate_visual(gift_id):
		return
	Events.gift_expired.emit(gift_id)


func _free_crate_visual(gift_id: int) -> bool:
	var entry: Dictionary = _crates.get(gift_id, {})
	if entry.is_empty():
		return false
	_crates.erase(gift_id)
	var node: GiftCrate = entry.get("node") as GiftCrate
	if node != null and is_instance_valid(node):
		node.queue_free()
	return true


func _gifts_container() -> Node3D:
	if _container != null and is_instance_valid(_container):
		return _container
	var blocks_parent: Node3D = _match.blocks_parent()
	if blocks_parent == null:
		return null
	var parent: Node = blocks_parent.get_parent()
	if parent == null:
		return null
	_container = Node3D.new()
	_container.name = &"GiftCrates"
	parent.add_child(_container)
	return _container


## Builds the one crate scene both the host's real spawn and a client's
## mirrored spawn use, so the two visuals can never disagree. `point` is
## disk-local (x, z); the crate sits on the field surface (spec 2.6:
## "stationary pickups"), lifted by half its own visual height so it rests on
## the surface rather than being bisected by it.
func _make_crate_node(point: Vector2) -> GiftCrate:
	var container: Node3D = _gifts_container()
	if container == null:
		return null
	var crate: GiftCrate = GIFT_CRATE_SCENE.instantiate() as GiftCrate
	container.add_child(crate)
	var field: Field = _match.field()
	if field != null:
		crate.global_position = field.world_from_disk_local(point, GiftCrate.CRATE_SIZE.y * 0.5)
	else:
		crate.global_position = Vector3(point.x, GiftCrate.CRATE_SIZE.y * 0.5, point.y)
	return crate


# --- The client's read model (spec 3.4) -------------------------------------
# Called only by net/MatchNet.gd's net_match_event, only on a client (a
# well-behaved host never receives its own replicated RPC). A client never
# claims or expires anything itself -- these three only ever build or free a
# visual, and the claim mirror also keeps held_special() accurate for a
# client's own future HUD/P2 use.

func apply_replicated_spawn(gift_id: int, position: Vector2) -> void:
	if _crates.has(gift_id):
		return
	_crates[gift_id] = {"position": position, "age": 0.0, "node": _make_crate_node(position)}


## Review fix (Must #1): slot_id arrives over the wire, so it is bounds-checked
## against _match.slot_count() before it ever reaches _ensure_capacity() --
## an unchecked garbage id would otherwise grow _held_specials without limit
## on every client that received it. Mirrors MatchLifecycle.
## apply_replicated_elimination()'s own slot(slot_id) null-check convention.
func apply_replicated_claim(gift_id: int, slot_id: int) -> void:
	_free_crate_visual(gift_id)
	if slot_id < 0 or slot_id >= _match.slot_count():
		return
	_ensure_capacity(slot_id)
	_held_specials[slot_id] = PENDING_SPECIAL_ID


func apply_replicated_expire(gift_id: int) -> void:
	_free_crate_visual(gift_id)


## autoload/match/MatchLifecycle.gd's _reset_match_state() one-line call:
## drops every live crate (host-spawned or client-mirrored) and every pending
## special, and un-seeds the RNG so the next match reseeds from its own
## config.rng_seed. Leaves _match alone -- same shape as every other
## controller's reset.
func reset() -> void:
	for gift_id: int in _crates.keys():
		var entry: Dictionary = _crates[gift_id]
		var node: GiftCrate = entry.get("node") as GiftCrate
		if node != null and is_instance_valid(node):
			node.queue_free()
	_crates.clear()
	_held_specials.clear()
	_next_gift_id = 0
	_rng_ready = false
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
