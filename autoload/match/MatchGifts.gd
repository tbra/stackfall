class_name MatchGifts
extends RefCounted
## Match's gift-crate lifecycle (spec 1.6): per-window spawn rolls, the
## territory-tick claim/expire sweep, and one replaceable next gift per slot.
##
## A RefCounted wired to autoload/Match.gd via setup(self) in Match's own
## _ready(), so it never walks the scene tree looking for its collaborators.
##
## Host-only logic is gated exactly like MatchTerritory's (`if not
## _match._is_host(): return`); a client only ever mirrors the three replicated
## gift events into visuals via apply_replicated_*() below and never claims or
## spawns anything itself.

var _match: MatchAutoload = null
var _cat: CatSession = null
var _gift_config: GiftConfig = preload("res://config/gifts/gift_config.tres")
var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _physics_tuning: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
## Host seconds of live play this match (physics ticks), for GiftConfig.first_gift_delay_s.
var _play_time_s: float = 0.0

const GIFT_CRATE_SCENE: PackedScene = preload("res://game/gifts/GiftCrate.tscn")
const FALLING: int = GiftWirePhase.FALLING
const LANDED: int = GiftWirePhase.LANDED


## The id the default drawer hands out until the real weighted SpecialDef pick
## is installed (set_special_drawer() below). Also the fallback a malformed
## drawer result is replaced with -- see _draw_special_id().
const PENDING_SPECIAL_ID: StringName = SpecialIds.PENDING

## DECISION (autoload/match/MatchGifts.gd): ui/lobby/Lobby.gd's specials
## checklist writes this exact literal into config.enabled_specials when the
## host unchecks every special (its own matching ALL_DISABLED_SENTINEL
## constant/DECISION) -- an autoload must not import a ui/ script just to
## share one StringName, so both files carry the same literal instead.
## _ensure_special_drawer_installed() below checks for it explicitly, rather
## than relying on it simply never matching a real SpecialDef.id, so a
## real .tres someone ever misnames "__none__" could never sneak into the
## roster once every special is meant to be off.
const ALL_DISABLED_SENTINEL: StringName = &"__none__"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rng_ready: bool = false
var _next_gift_id: int = 0

## The special TYPE is drawn here, at claim time, on the host -- not at spawn
## time. Spec 2.6 hands a player "a special as the next piece", so the player
## (and the HUD/ghost) must know what they hold while aiming, not just that
## they hold something. _draw_special_id() is the one call site;
## _ensure_special_drawer_installed() installs the real weighted
## SpecialDef.pick_weighted() draw through set_special_drawer(). Kept an
## injectable Callable rather than a hard SpecialDef dependency.
var _special_drawer: Callable = _default_special_drawer

## The roster _weighted_special_drawer() draws from, filtered to
## `_match.config.enabled_specials` (empty means every special, per
## config/match/MatchConfig.gd's doc comment) once per match, plus the own
## RNG that draw uses. Reset flags (`_roster_ready`/`_special_rng_ready`) so a
## new match re-filters against its own config rather than reusing the
## previous match's roster or reseeding an already-seeded RNG.
##
## DECISION (autoload/match/MatchGifts.gd): the real drawer is installed
## lazily on first real use -- _ensure_special_drawer_installed(), called from
## _claim_gift() right before _draw_special_id() -- not at match start:
## autoload/Match.gd's _ready() runs before config is assigned, and a
## start_match() hook would need MatchLifecycle to know about it. Mirrors
## _ensure_rng()'s lazy convention.
var _roster_ready: bool = false
var _special_roster: Array[SpecialDef] = []
var _special_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _special_rng_ready: bool = false

## Live, unclaimed crates: gift_id -> GiftFlight. Every entry, host or client
## mirror, is created and freed only through _make_crate_node()/_free_crate_visual()
## so the two paths cannot drift.
var _crates: Dictionary = {}
## gift_id -> GiftCrate visual (absent when no container exists), kept beside _crates.
var _crate_nodes: Dictionary = {}

## Parallel to Match's slots: each inner array has zero or one next gift.
## A new claim replaces its element and never changes the current held piece.
## Grown lazily by _ensure_capacity() rather than sized off slot_count() at
## reset() time, because _reset_match_state() runs *before* the new match's
## slots are built (autoload/match/MatchLifecycle.gd's start_match(): reset,
## then _build_slots()).
##
## Keyed by RECIPIENT SLOT, not by team. A crate claimed in a team's territory
## is offered to the one teammate whose home circle is nearest the crate
## (_resolve_recipient_slot() below), never to a queue shared by the whole team
## -- so index i here is always slot i's own queue, with no team_of_slot()
## translation.
##
## DECISION (autoload/match/MatchGifts.gd): Godot 4.7.2 rejects
## `Array[Array[StringName]]` ("nested typed collections are not supported").
## The outer array is therefore a plain `Array[Array]`;
## each inner queue is still built exactly once, as a real `Array[StringName]`,
## by _new_typed_queue() below, so every element still carries StringName's
## runtime type check. Only the outer container's own element type is
## unenforced by the engine.
var _pending_queues: Array[Array] = []
## The queued gift is separate from the currently held piece. A claim never
## changes this value; only the subsequent feed activates the queued gift.
var _held_specials: Dictionary = {}
## DECISION: a dictionary keyed by recipient slot keeps charges independent of the shared GlueEffect resource and gift queue.
## A later Glue activation replaces the count instead of adding to it.
var _glue_drops: Dictionary = {}
## Absolute charge updates carry a per-slot revision so duplicate or delayed
## reliable packets cannot restore a spent charge on a client.
var _glue_revisions: Dictionary = {}

## Lazily created the first time a crate needs a visual (host spawn or client
## mirror), as a SIBLING of Match's own blocks_parent (a child of that node's
## own parent) -- never a child of blocks_parent itself: its children are
## trusted elsewhere to be exactly the placed Blocks (test_match_flow.gd, and
## the contract BlockRegistry/SnapshotSync rely on). Freed and re-created by
## reset() rather than reused across matches so a stale crate can never
## survive into a new one.
var _container: Node3D = null


## True once the crate model table, GLB and toon materials were built once.
var _crate_prewarmed: bool = false


## DECISION: the first GiftCrate of a process cost 42-70 ms inside a bot's
## placement frame (GiftModelTable load + crate GLB instantiate + toon materials),
## the worst frame of the bot bench; one throwaway build_crate_visual() at setup (host and client both run
## setup) moves that cost out of the match. Once per process; nothing is added to the tree.
func setup(match_ref: MatchAutoload) -> void:
	_match = match_ref
	_cat = CatSession.new()
	_cat.setup(match_ref, match_ref)
	if not _crate_prewarmed:
		_crate_prewarmed = true
		var visual: Node3D = GiftModelTable.shared().build_crate_visual()
		if visual != null:
			visual.free()
	if not Events.player_eliminated.is_connected(_on_player_eliminated_clear_glue):
		Events.player_eliminated.connect(_on_player_eliminated_clear_glue)


## DECISION: an eliminated slot can never drop again, so the host zeroes its Glue charges (harmless to rules) and publishes the change,
## which hides the glue presentation everywhere. Clients ignore it: they get
## the host's zero through glue_charges_changed.
func _on_player_eliminated_clear_glue(slot_id: int, _team_id: int) -> void:
	if _match == null or not _match._is_host() or glue_drops_left(slot_id) <= 0:
		return
	_glue_drops.erase(slot_id)
	_publish_glue_charges(slot_id)


## The one cat session of the match.
func cat() -> CatSession:
	return _cat


## The default drawer: always PENDING_SPECIAL_ID, until the real weighted
## SpecialDef pick is installed via set_special_drawer().
func _default_special_drawer() -> StringName:
	return PENDING_SPECIAL_ID


## Host-only entry point for installing a drawer; `drawer`
## must be a `func() -> StringName`. Passing an invalid/null Callable is not
## guarded here -- Callable.call() on one simply fails at the call site in
## _draw_special_id(), which is guarded (see its own doc comment).
func set_special_drawer(drawer: Callable) -> void:
	_special_drawer = drawer


## Restores the placeholder drawer, so a forced-special drawer cannot leak into
## the next match (Match.start_match).
func reset_special_drawer() -> void:
	_special_drawer = _default_special_drawer


## Builds one fresh per-slot queue. A real Array[StringName], not a plain
## Array -- see _pending_queues' own DECISION for why the *outer* container
## cannot also be typed on this engine version.
func _new_typed_queue() -> Array[StringName]:
	var queue: Array[StringName] = []
	return queue


## Used by _resolve_recipient_slot() to test whether a slot is on the claiming
## team. `_match.config` can be null before a match ever starts; a null config falls
## back to `slot_id` itself, exactly what team_of_slot() returns for
## TeamMode.OFF.
func _team_id_for_slot(slot_id: int) -> int:
	if _match.config == null:
		return slot_id
	return _match.config.team_of_slot(slot_id)


## The special `slot_id` is holding, or &"" for none -- a peek, not a pop.
## The HUD reads pending_special_count() for the queued-count indicator.
func held_special(slot_id: int) -> StringName:
	return StringName(_held_specials.get(slot_id, &""))


## Host-authoritative activation. The activation block is already placed by
## the time its SpecialBehavior triggers, so no charge is spent here.
func grant_glue_drops(slot_id: int, count: int) -> bool:
	if _match == null or not _match._is_host():
		return false
	if slot_id < 0 or slot_id >= _match.slot_count() or count <= 0 or count > 100:
		return false
	_glue_drops[slot_id] = count
	_publish_glue_charges(slot_id)
	return true


## DECISION: Glue is a modifier, not a held piece. On claim the host grants its charges at once and leaves the queued gift and the
## feed untouched; every other gift queues as the next held piece.
const GLUE_SPECIAL_ID: StringName = &"glue"
const GLUE_DEF: SpecialDef = preload("res://config/gifts/specials/glue.tres")


## `immediate` skips the after-next trial: the sandbox's forced special (debug_queue_special) is
## documented as the NEXT gift and the sandbox is host-local, so no client mirror is involved.
func _queue_claimed_special(slot_id: int, special_id: StringName, immediate: bool = false) -> void:
	if special_id == GLUE_SPECIAL_ID:
		var effect: GlueEffect = GLUE_DEF.effect as GlueEffect
		if effect != null:
			grant_glue_drops(slot_id, effect.drop_charges)
		return
	if gift_slot_capacity() > 0:
		_store_in_gift_slot(slot_id, special_id)
		return
	_ensure_capacity(slot_id)
	if not immediate and _match.feed().gift_after_next_active():
		var had_staged: bool = _match.feed().has_staged_gift(slot_id)
		if _match.feed().stage_gift_after_next(slot_id) != &"":
			_enqueue_after_next(slot_id, special_id, had_staged)
			return
	var queue: Array = _pending_queues[slot_id]
	queue.clear()
	queue.append(special_id)
	_match.feed().replace_next_with_gift(slot_id)


## Queue order is [gift that is next (if any), staged gift].
## A later claim replaces an earlier staged gift (latest wins);
## a gift already next is never displaced.
func _enqueue_after_next(slot_id: int, special_id: StringName, had_staged: bool) -> void:
	var queue: Array = _pending_queues[slot_id]
	if had_staged and not queue.is_empty():
		queue.pop_back()
	queue.append(special_id)


## The claimed gift staged as the block after next, or &"" for none.
func after_next_special(slot_id: int) -> StringName:
	if slot_id < 0 or slot_id >= _pending_queues.size() or not _match.feed().has_staged_gift(slot_id):
		return &""
	var queue: Array = _pending_queues[slot_id]
	return StringName(queue.back()) if not queue.is_empty() else &""


## QoL gift slot: per-slot gifts waiting to be spent with use_gift_slot, oldest first. Empty (and never touched) with the toggle off.
var _gift_slots: Dictionary = {}


## Slots in force (0 = toggle off, so every claim queues as before).
func gift_slot_capacity() -> int:
	if _match == null or _match.config == null or _match.config.qol == null:
		return 0
	return _match.config.qol.effective_gift_slot_capacity()


func gift_slot_contents(slot_id: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in _gift_slots.get(slot_id, []):
		out.append(StringName(id))
	return out


## The gift the next use_gift_slot would spend, or &"" for an empty slot.
func gift_slot_head(slot_id: int) -> StringName:
	var contents: Array = _gift_slots.get(slot_id, [])
	return StringName(contents[0]) if not contents.is_empty() else &""


func gift_slot_count(slot_id: int) -> int:
	return (_gift_slots.get(slot_id, []) as Array).size()


func _store_in_gift_slot(slot_id: int, special_id: StringName) -> void:
	var contents: Array = _gift_slots.get(slot_id, [])
	# DECISION: a claim into a full slot drops the OLDEST slotted gift (with
	# capacity 1: the new gift replaces the old one), the same "latest claim
	# wins" rule the block queue uses.
	while contents.size() >= gift_slot_capacity():
		contents.pop_front()
	contents.append(special_id)
	_gift_slots[slot_id] = contents
	Events.gift_slot_changed.emit(slot_id, gift_slot_contents(slot_id), &"", &"")


## Host-validated activation of `slot_id`'s slotted gift: exactly what a gift
## arriving in the block queue does (it becomes the held piece, or triggers if
## instant), without waiting for the next block and without a timer reset.
## Refused (false, nothing changes) off-host, outside PLAYING, for an
## eliminated slot, with an empty slot, with no held piece, or while a gift is
## already held or queued for this slot.
func request_use_gift_slot(slot_id: int) -> bool:
	if _match == null or gift_slot_capacity() <= 0:
		return false
	# The shared host/live/slot/home/turn/held-shape preamble (the same
	# one-actor-at-a-time gate request_place uses: off-turn seats cannot spend).
	if not _match._placement.can_use_gift_slot(slot_id):
		return false
	var special_id: StringName = gift_slot_head(slot_id)
	if special_id == &"":
		return false
	if held_special(slot_id) != &"" or next_special(slot_id) != &"":
		return false
	var contents: Array = _gift_slots[slot_id]
	contents.pop_front()
	_ensure_capacity(slot_id)
	var queue: Array = _pending_queues[slot_id]
	queue.clear()
	queue.append(special_id)
	var carrier_id: StringName = _match.feed().replace_next_with_gift(slot_id)
	if carrier_id == &"":
		queue.clear()
		contents.push_front(special_id)
		return false
	# Clients mirror the queue and carrier before the feed event that follows.
	Events.gift_slot_changed.emit(slot_id, gift_slot_contents(slot_id), special_id, carrier_id)
	_match.feed().issue_gift_now(slot_id, _match.config.qol.effective_gift_min_window_s())
	return true


## Client mirror of Events.gift_slot_changed (net/MatchNet.gd).
func apply_replicated_gift_slot(slot_id: int, contents: Array, activated: StringName, carrier_id: StringName) -> void:
	if slot_id < 0 or slot_id >= _match.slot_count():
		return
	if contents.is_empty():
		_gift_slots.erase(slot_id)
	else:
		_gift_slots[slot_id] = contents.duplicate()
	if activated != &"":
		_ensure_capacity(slot_id)
		var queue: Array = _pending_queues[slot_id]
		queue.clear()
		queue.append(activated)
		_match.feed().apply_replicated_next_gift(slot_id, carrier_id)


func glue_drops_left(slot_id: int) -> int:
	if _match == null or slot_id < 0 or slot_id >= _match.slot_count():
		return 0
	return int(_glue_drops.get(slot_id, 0))


func glue_revision(slot_id: int) -> int:
	return int(_glue_revisions.get(slot_id, 0))


func apply_replicated_glue_charges(slot_id: int, count: int, revision: int) -> bool:
	if _match == null or _match._is_host():
		return false
	if slot_id < 0 or slot_id >= _match.slot_count() or count < 0 or count > 100:
		return false
	if revision <= glue_revision(slot_id):
		return false
	_glue_revisions[slot_id] = revision
	if count == 0:
		_glue_drops.erase(slot_id)
	else:
		_glue_drops[slot_id] = count
	Events.glue_charges_changed.emit(slot_id, count, revision)
	return true


func _publish_glue_charges(slot_id: int) -> void:
	var revision: int = glue_revision(slot_id) + 1
	_glue_revisions[slot_id] = revision
	Events.glue_charges_changed.emit(slot_id, glue_drops_left(slot_id), revision)


## Called only after a successful future drop by the placement package.
func consume_glue_drop(slot_id: int) -> bool:
	if _match == null or not _match._is_host():
		return false
	if slot_id < 0 or slot_id >= _match.slot_count():
		return false
	var left: int = glue_drops_left(slot_id)
	if left <= 0:
		return false
	if left == 1:
		_glue_drops.erase(slot_id)
	else:
		_glue_drops[slot_id] = left - 1
	_publish_glue_charges(slot_id)
	return true


func activate_next_special(slot_id: int) -> void:
	if slot_id < 0 or slot_id >= _pending_queues.size():
		return
	var queue: Array = _pending_queues[slot_id]
	if queue.is_empty():
		return
	_held_specials[slot_id] = StringName(queue[0])
	# Pop only the activated gift; a staged one stays queued.
	queue.pop_front()


## Presentation getter: the queued gift that will be the slot's NEXT held piece, or &"" for none. A peek; changes no state.
func next_special(slot_id: int) -> StringName:
	if slot_id < 0 or slot_id >= _pending_queues.size():
		return &""
	var queue: Array = _pending_queues[slot_id]
	if queue.is_empty():
		return &""
	# A lone staged gift is not next yet (after_next_special()).
	if queue.size() == 1 and _match.feed().has_staged_gift(slot_id):
		return &""
	return StringName(queue[0])


func clear_held_special(slot_id: int) -> void:
	_held_specials.erase(slot_id)


func defer_held_special_after_burn(slot_id: int) -> void:
	var special_id: StringName = held_special(slot_id)
	if special_id == &"":
		return
	_ensure_capacity(slot_id)
	var queue: Array = _pending_queues[slot_id]
	# DECISION: a later claim already owns the next slot, and a burned held gift
	# must not replace it with the older gift. Without a later claim, retry this
	# gift as the next held piece, replacing the next ordinary draw.
	if queue.is_empty():
		queue.append(special_id)
		_match.feed().replace_next_with_gift(slot_id)
	_held_specials.erase(slot_id)


## Consumes the held gift, or returns &"" for an ordinary piece. The next
## gift remains untouched until MatchFeed issues it as a held piece.
##
## The one host-side emit site for Events.special_consumed --
## _attach_pending_special() (autoload/match/MatchPlacement.gd) is this
## function's only caller, on the place-spawn non-burn path and always on a
## throw, so a single emit here covers both. A burned auto-drop never reaches
## this call (see that function's doc comment), so it never emits either: a
## burn keeps the special queued. Both real callers are host-only
## (request_place()/request_throw() refuse off-host).
func pop_pending_special(slot_id: int) -> StringName:
	var popped: StringName = held_special(slot_id)
	if popped == &"":
		return &""
	_held_specials.erase(slot_id)
	Events.special_consumed.emit(slot_id, popped)
	return popped


## Count the held gift and the one queued behind it for the HUD.
func pending_special_count(slot_id: int) -> int:
	if slot_id < 0 or slot_id >= _pending_queues.size():
		return 1 if held_special(slot_id) != &"" else 0
	var queue: Array = _pending_queues[slot_id]
	return queue.size() + (1 if held_special(slot_id) != &"" else 0)


## The gift_id every debug_queue_special() claim reports.
## _spawn_crate_at()'s real ids start at 0 and only ever increase, so a
## negative sentinel can never collide with one.
const DEBUG_GIFT_ID: int = -1


## Sandbox-only debug entry point (game/sandbox/Sandbox.gd's F9
## sandbox_force_special hotkey and `--force-special=`): replaces `slot_id`'s
## next gift and emits Events.gift_claimed with DEBUG_GIFT_ID, the same signal
## _claim_gift() fires for a real claim, so the HUD/ghost/client mirrors follow
## the normal path. Skips the crate roll and the territory-tick claim sweep --
## there is no crate to free.
##
## Gated on the host plus `_match.config.sandbox or _match.config.scripted_gifts`
## (the tutorial's scripted lesson, set only by MatchLaunch.tutorial_config), so a
## real match can never be handed a free special through this seam.
func debug_queue_special(slot_id: int, special_id: StringName) -> bool:
	if not _match._is_host():
		return false
	if _match.config == null or not (_match.config.sandbox or _match.config.scripted_gifts):
		return false
	if slot_id < 0 or slot_id >= _match.slot_count():
		return false
	_ensure_capacity(slot_id)
	_queue_claimed_special(slot_id, special_id, true)
	# slot_id, not a team id: gift_claimed's second parameter is the resolved
	# recipient slot (Events.gd).
	Events.gift_claimed.emit(DEBUG_GIFT_ID, slot_id, special_id)
	return true


## Sandbox-only reset seam (game/sandbox/Sandbox.gd's F9 hotkey turning back
## "off"): re-runs the lazy install _ensure_special_drawer_installed() performs
## at a match's first real claim. Resets `_roster_ready` first, otherwise the
## idempotency guard would make the call a no-op after a forced special's own
## set_special_drawer() replaced the drawer.
func restore_default_special_drawer() -> void:
	_roster_ready = false
	_ensure_special_drawer_installed()


func _ensure_capacity(slot_id: int) -> void:
	while _pending_queues.size() <= slot_id:
		_pending_queues.append(_new_typed_queue())


## DECISION (autoload/match/MatchGifts.gd): "the feed issues a new window" is
## Events.feed_block_issued -- MatchFeed._issue_next_block() emits it every time
## any slot is handed a new held piece, on an early release, a forced
## auto-drop, or a turn change alike. autoload/Match.gd connects this
## to Events.feed_block_issued and forwards slot_id here.
##
## Feed issuance activates a queued gift in MatchFeed before this callback.
## Gift activation and the ordinary piece after gift use do not create new
## ordinary placement windows, so neither gets a gift-spawn roll. Other rolls
## are gated by _should_roll_for_window(): every slot's window
## advances independently (spec 1.4), so rolling unconditionally would give an
## N-player match ~N rolls per window instead of GiftSpawner.should_spawn()'s
## "one roll per window, for the whole match, not per player".
func on_feed_block_issued(slot_id: int) -> void:
	if not _match._is_host():
		return
	if _match.feed().gift_roll_suppressed():
		return
	# Start grace; the roll is skipped outright, not queued.
	# DECISION: sandbox / gift-demo matches skip the grace (a testing aid; the
	# grace is about real matches).
	if _play_time_s < _gift_config.first_gift_delay_s and not (_match.config != null and _match.config.sandbox):
		return
	if not _should_roll_for_window(slot_id):
		return
	_try_spawn()


## DECISION (autoload/match/MatchGifts.gd): every slot's own window fires this signal independently, so rolling on
## every one of them would multiply the match-wide roll by player_count. The
## lowest-indexed slot that still has a home flag stands in for "the match's
## own window" here -- it need not be synchronized with anyone else's timer
## (early releases desync individual slots' windows over time), but it is
## always exactly one slot at any instant, which is all should_spawn()'s
## contract actually needs: one roll, somewhere, per window.
func _should_roll_for_window(slot_id: int) -> bool:
	if _match.config == null:
		return false
	return slot_id == _lowest_alive_slot()


func _lowest_alive_slot() -> int:
	for i: int in range(_match.slot_count()):
		var slot: PlayerSlot = _match.slot(i)
		if slot != null and slot.home_flag_alive:
			return i
	return -1


## Spec 1.9's sudden-death bullet: "Gift probability climbs toward the
## maximum of the finalized spawn model (2.6)." Outside sudden death this is
## exactly `_match.config.special_frequency`; once
## MatchLifecycle.sudden_death_active() is true it lerps monotonically toward
## MatchConfig.SPECIAL_FREQUENCY_MAX over TerritoryTuning.sudden_death_ramp_s,
## then clamps there for the rest of the match. GiftConfig.frequency_to_chance_max
## is already the spawn model's maximum chance (spec 1.6), so only the
## frequency handed to should_spawn() changes. See the ramp tunable's DECISION
## for why its duration is not spec-given.
func _effective_special_frequency() -> float:
	var base_frequency: float = float(_match.config.special_frequency) if _match.config != null else 0.0
	if not _match.lifecycle().sudden_death_active():
		return base_frequency
	var t: float = _match.lifecycle().sudden_death_ramp(_territory_tuning.sudden_death_ramp_s)
	return lerpf(base_frequency, float(MatchConfig.SPECIAL_FREQUENCY_MAX), t)


func _live_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for flight: GiftFlight in _crates.values():
		result.append(flight.position)
	return result


func _try_spawn() -> void:
	if _match.config == null or not _match.config.gifts_enabled:
		return
	var raster: TerritoryRaster = _match.raster()
	var grid: CellGrid = _match.cell_grid()
	if raster == null or grid == null:
		return
	_ensure_rng()
	if not GiftSpawner.should_spawn(_gift_config, _effective_special_frequency(), _crates.size(), _rng, _match.slot_count()):
		return
	var point: Vector2 = GiftSpawner.pick_spawn_point(raster, grid, _rng, _gift_config, _live_positions())
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


## Lazily installs the real weighted-SpecialDef drawer the first time a
## match actually claims a crate, filtered to
## `_match.config.enabled_specials` (empty means every special --
## config/match/MatchConfig.gd). Idempotent per match via `_roster_ready`,
## cleared by reset(). Keeps `_special_drawer` at its default
## (_default_special_drawer, always PENDING_SPECIAL_ID) when the filtered
## roster is empty, so a spawn with no draw stays an ordinary block.
func _ensure_special_drawer_installed() -> void:
	if _roster_ready:
		return
	_roster_ready = true
	# The draw honours SpecialDef.enabled_by_default (Cat is off).
	# The lobby checklist and the sandbox cycle list use the same roster.
	var all_defs: Array[SpecialDef] = SpecialDef.load_selectable_specials()
	var enabled: Array[StringName] = _match.config.enabled_specials if _match.config != null else []
	var roster: Array[SpecialDef] = []
	if enabled.has(ALL_DISABLED_SENTINEL):
		return
	if enabled.is_empty():
		roster = all_defs
	else:
		for def: SpecialDef in all_defs:
			if enabled.has(def.id):
				roster.append(def)
	if roster.is_empty():
		return
	_special_roster = roster
	_ensure_special_rng()
	_special_drawer = _weighted_special_drawer


## DECISION (autoload/match/MatchGifts.gd): rng_seed + a distinct odd
## offset from _ensure_rng()'s own 999983, so a fixed match seed reproduces
## the special-type draw deterministically without ever colliding with the
## gift-spawn-point RNG or a slot's own bag sequence (same stride convention
## as MatchFeed._build_bags()/this file's _ensure_rng()).
func _ensure_special_rng() -> void:
	if _special_rng_ready:
		return
	_special_rng_ready = true
	if _match.config != null and _match.config.rng_seed >= 0:
		_special_rng.seed = _match.config.rng_seed + 999979
	else:
		_special_rng.randomize()


## The real drawer, installed by _ensure_special_drawer_installed() once the
## filtered roster is non-empty. Roulette-weighted via
## SpecialDef.pick_weighted(), which returns null on an empty array; guarded
## here too so this function always returns a valid, non-empty StringName.
func _weighted_special_drawer() -> StringName:
	var picked: SpecialDef = SpecialDef.pick_weighted(_special_roster, _special_rng)
	return picked.id if picked != null else PENDING_SPECIAL_ID


func _spawn_crate_at(point: Vector2) -> void:
	var gift_id: int = _next_gift_id
	_next_gift_id += 1
	var landing: Vector3 = _world_at(point, GiftCrate.CRATE_SIZE.y * 0.5)
	var origin: Vector3 = landing + Vector3.UP * _gift_config.drop_height_m
	var node: GiftCrate = _make_crate_node(point, gift_id)
	_crates[gift_id] = GiftFlight.new(gift_id, point, origin, landing, FALLING)
	if node != null:
		_crate_nodes[gift_id] = node
		node.global_position = origin
		node.set_falling(true)
	Events.gift_flight_spawned.emit(gift_id, origin, landing)
	Events.gift_spawned.emit(gift_id, point)


func _world_at(point: Vector2, height: float) -> Vector3:
	var field: Field = _match.field()
	return field.world_from_disk_local(point, height) if field != null else Vector3(point.x, height, point.y)


## Where the crate node is drawn: the spawn-time arc, shifted toward the live disc surface
## under its point as it falls (full shift at progress 1.0, and for a landed crate). The flight's
## own landing stays the spawn-time world value, which the wire and the applier compare.
func _live_crate_position(flight: GiftFlight, progress: float) -> Vector3:
	var live: Vector3 = _world_at(flight.position, GiftCrate.CRATE_SIZE.y * 0.5)
	return flight.world_position(_gift_config, progress) + (live - flight.landing) * clampf(progress, 0.0, 1.0)


## A copy safe for minimap and network consumers. Position is host-authored.
func gift_state(gift_id: int) -> Dictionary:
	var flight: GiftFlight = _crates.get(gift_id) as GiftFlight
	return {} if flight == null else flight.snapshot()


func gift_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[int] = []
	for gift_id: int in _crates.keys():
		ids.append(gift_id)
	ids.sort()
	for gift_id: int in ids:
		result.append(gift_state(gift_id))
	return result


## Host and client use the same time/id-derived arc (GiftFlight.world_position); no extra
## wire data or random state is needed. Clients begin on event receipt, so their visual can
## trail the host by transport latency; only the host resolves airborne touch.
## Runs only on host physics ticks. Sorted ids and slots make contention stable.
func tick_host(delta: float) -> void:
	if not _match._is_host():
		return
	if delta > 0.0:
		_play_time_s += delta
	if delta <= 0.0 or _crates.is_empty():
		return
	var ids: Array[int] = []
	for gift_id: int in _crates.keys():
		ids.append(gift_id)
	ids.sort()
	for gift_id: int in ids:
		if not _crates.has(gift_id):
			continue
		var flight: GiftFlight = _crates[gift_id]
		if flight.phase == FALLING:
			var progress: float = flight.advance_fall(delta, _gift_config)
			var world_position: Vector3 = _live_crate_position(flight, progress)
			var node: GiftCrate = _crate_nodes.get(gift_id) as GiftCrate
			if node != null and is_instance_valid(node):
				node.global_position = world_position
			for slot_id: int in range(_match.slot_count()):
				if _held_block_touches(slot_id, world_position):
					if _claim_gift_for_slot(gift_id, slot_id):
						break
			if not _crates.has(gift_id):
				continue
			if progress >= 1.0:
				flight.phase = LANDED
				flight.age = 0.0
				if node != null and is_instance_valid(node):
					node.set_falling(false)
				Events.gift_landed.emit(gift_id, flight.landing)
				_claim_landed(gift_id)
		else:
			var landed_node: GiftCrate = _crate_nodes.get(gift_id) as GiftCrate
			if landed_node != null and is_instance_valid(landed_node):
				landed_node.global_position = _live_crate_position(flight, 1.0)
			_claim_landed(gift_id)
			if not _crates.has(gift_id):
				continue
			flight.age += delta
			if flight.age >= _gift_config.life_s:
				_expire_gift(gift_id)


func _claim_landed(gift_id: int) -> void:
	var raster: TerritoryRaster = _match.raster()
	var grid: CellGrid = _match.cell_grid()
	if raster == null or grid == null:
		return
	var flight: GiftFlight = _crates.get(gift_id) as GiftFlight
	if flight == null or flight.phase != LANDED:
		return
	var cell: Vector2i = grid.world_to_cell(flight.position)
	var team: int = raster.team_at(cell.x, cell.y) if grid.in_bounds(cell.x, cell.y) else -1
	if team >= 0:
		_claim_gift(gift_id, team)


## Only an accepted host cursor or the local held view is eligible.
func _held_block_touches(slot_id: int, crate_world: Vector3) -> bool:
	var slot: PlayerSlot = _match.slot(slot_id)
	var shape: BlockShape = _match.held_shape(slot_id)
	if slot == null or not slot.home_flag_alive or shape == null:
		return false
	if _match.config.turn_based and slot_id != _match.active_slot():
		return false
	var origin: Vector3 = Vector3.ZERO
	var orientation: int = 0
	var free_quat: Quaternion = Quaternion.IDENTITY
	var found: bool = false
	var replicator: Variant = _match.replicator()
	if replicator != null and replicator.has_method("cursor_for_slot"):
		var cursor: Dictionary = replicator.cursor_for_slot(slot_id)
		if not cursor.is_empty() and float(cursor.get("age", INF)) <= _gift_config.cursor_max_age_s:
			origin = cursor.get("origin", Vector3.ZERO)
			orientation = int(cursor.get("orientation_index", 0))
			free_quat = cursor.get("free_quat", Quaternion.IDENTITY)
			found = true
	var local_slot: bool = slot_id == _match.active_slot() if Net.is_offline() else Net.is_local_slot(slot_id)
	if not found and local_slot:
		# DECISION: read the published view through the MatchContext port, not the scene tree.
		var held: LocalHeldView = MatchContext.current().local_held()
		if held.slot_id == slot_id and held.shape == shape:
			origin = held.origin
			orientation = held.orientation_index
			free_quat = held.free_quat
			found = true
	if not found or not _match.is_pose_well_formed(origin, orientation, free_quat):
		return false
	var basis: Basis = Basis(free_quat) * BlockOrientations.get_basis(orientation)
	var half: float = _physics_tuning.cube_size * 0.5 + _gift_config.air_touch_margin_m
	var crate_half: Vector3 = GiftCrate.CRATE_SIZE * 0.5
	var pivot: Vector3 = shape.bottom_center()
	# A held gift is one cell where its model sits, matching the
	# collider it will be delivered with, not the whole carrier piece.
	if _match.held_special(slot_id) != &"":
		var gift_center: Vector3 = origin + basis * BlockFactory.gift_cell_center(shape, _physics_tuning)
		return GiftCrateTouch.cell_overlaps_crate(gift_center, basis, half, crate_world, crate_half)
	return GiftCrateTouch.shape_overlaps_crate(
		shape.cells, pivot, origin, basis, _physics_tuning.cube_size, half, crate_world, crate_half)


func _claim_gift_for_slot(gift_id: int, slot_id: int) -> bool:
	if not _crates.has(gift_id):
		return false
	_ensure_capacity(slot_id)
	if not _free_crate_visual(gift_id):
		return false
	_ensure_special_drawer_installed()
	var special_id: StringName = _draw_special_id()
	_queue_claimed_special(slot_id, special_id)
	Events.gift_claimed.emit(gift_id, slot_id, special_id)
	return true


## A crate claimed in `team_id`'s territory is offered to the ONE teammate
## whose home circle is nearest the crate, not to every teammate through a
## shared queue. _resolve_recipient_slot() does that resolution; if no
## teammate's home flag is still alive, the crate is left untouched (no claim,
## no crate consumed, no event).
##
## The latest claim replaces this recipient's next gift or ordinary draw.
## Resolve the recipient before freeing the crate because its position is
## needed for that choice.
func _claim_gift(gift_id: int, team_id: int) -> void:
	if team_id < 0:
		return
	var flight: GiftFlight = _crates.get(gift_id) as GiftFlight
	if flight == null:
		return
	var crate_position: Vector2 = flight.position
	var recipient_slot: int = _resolve_recipient_slot(team_id, crate_position)
	if recipient_slot < 0:
		return
	_claim_gift_for_slot(gift_id, recipient_slot)


## Picks the alive (home_flag_alive) member of `team_id` whose home circle
## (PlayerSlot.home_position, disk-local, computed once by
## MatchLifecycle._build_slots()) is closest to `crate_position`. Returns -1
## if `team_id` has no living teammate to give the special to.
##
## DECISION (autoload/match/MatchGifts.gd): the spec settles "nearest wins" but
## not an exact tie (two teammates equidistant from the crate). Iterating
## slots in ascending id order and
## only replacing the current best on a strict `<` (not `<=`) comparison
## makes the lowest slot id win a tie with no extra branching -- simplest
## reasonable option, not a spec requirement.
func _resolve_recipient_slot(team_id: int, crate_position: Vector2) -> int:
	var best_slot: int = -1
	var best_distance_sq: float = 0.0
	for slot_id: int in range(_match.slot_count()):
		var slot: PlayerSlot = _match.slot(slot_id)
		if slot == null or not slot.home_flag_alive:
			continue
		if _team_id_for_slot(slot_id) != team_id:
			continue
		var distance_sq: float = slot.home_position.distance_squared_to(crate_position)
		if best_slot < 0 or distance_sq < best_distance_sq:
			best_slot = slot_id
			best_distance_sq = distance_sq
	return best_slot


## The special TYPE is drawn here, at claim time.
## A drawer that returns something that isn't a real, non-empty StringName is
## treated as a bug in whatever installed it, not trusted silently -- an
## empty id is held_special()'s own "nothing queued" sentinel, so queuing one
## would silently swallow a claim. Checked with typeof() rather than an `as`
## cast: casting an arbitrary Variant to StringName is not a safe no-op for
## every input type on this engine, and a syntactic type check is all this
## guard needs.
func _draw_special_id() -> StringName:
	var drawn: Variant = _special_drawer.call()
	if typeof(drawn) == TYPE_STRING_NAME and String(drawn) != "":
		return drawn
	push_warning("MatchGifts: special drawer returned an invalid id (%s); falling back to PENDING_SPECIAL_ID" % [drawn])
	return PENDING_SPECIAL_ID


## Unclaimed crates respawn in a different place. Captures the expiring crate's own position before _free_crate_visual()
## erases its `_crates` entry, so _relocate_after_expiry() can measure the
## replacement's minimum distance against it.
func _expire_gift(gift_id: int) -> void:
	var flight: GiftFlight = _crates.get(gift_id) as GiftFlight
	if flight == null:
		return
	var old_position: Vector2 = flight.position
	if not _free_crate_visual(gift_id):
		return
	Events.gift_expired.emit(gift_id)
	_relocate_after_expiry(old_position)


## An expired (unclaimed) crate is immediately replaced by a
## fresh one at a new valid random location at least
## GiftConfig.relocate_min_distance_m from the one it replaces, using the same
## seeded gift-spawn RNG and GiftSpawner.pick_spawn_point() location logic
## _try_spawn() itself uses (_ensure_rng() is idempotent, so this never
## reseeds), so replays stay deterministic under a fixed rng_seed.
##
## The per-window spawn chance (should_spawn()) and max_live_crates cap are
## deliberately NOT re-checked here -- the crate that just expired already
## counted against max_live_crates, and this relocation directly replaces it
## one-for-one, so the live-crate count this produces is exactly what it was
## the instant before expiry (spec 1.6 unchanged; owner instruction: "the
## relocated crate counts as the live crate").
##
## DECISION (autoload/match/MatchGifts.gd): if no valid spot clearing
## relocate_min_distance_m can be found (raster/grid missing, gifts disabled
## mid-match, or _pick_relocation_point() exhausts its attempt budget), the
## crate stays gone and the next spawn comes from the ordinary per-window roll,
## rather than forcing a spawn at a too-close or invalid point.
func _relocate_after_expiry(old_position: Vector2) -> void:
	if _match.config == null or not _match.config.gifts_enabled:
		return
	var raster: TerritoryRaster = _match.raster()
	var grid: CellGrid = _match.cell_grid()
	if raster == null or grid == null:
		return
	_ensure_rng()
	var new_point: Vector2 = _pick_relocation_point(raster, grid, old_position)
	if GiftSpawner.is_no_spawn_point(new_point):
		# DECISION: no immediate replacement; the next ordinary per-window
		# roll will spawn one (see the doc comment above).
		return
	_spawn_crate_at(new_point)


## Retries GiftSpawner.pick_spawn_point() -- the exact same seeded-RNG,
## contested/hole-avoiding, edge-margined logic _try_spawn() calls -- up to
## GiftConfig.spawn_max_attempts times (reusing that existing attempts budget
## rather than adding a second one, since the two loops serve the same
## "give up eventually" purpose), until a candidate lands at least
## GiftConfig.relocate_min_distance_m from `old_position`. Returns
## GiftSpawner.NO_SPAWN_POINT if every retry was either invalid or too close.
##
## Bails out immediately, without spending the rest of the attempt budget, the
## first time pick_spawn_point() itself returns its own sentinel: that only
## happens when no cell in the whole disk is valid at all (spec/GiftSpawner's
## own contract), which retrying with a different RNG draw cannot fix within
## the same raster/grid snapshot.
func _pick_relocation_point(raster: TerritoryRaster, grid: CellGrid, old_position: Vector2) -> Vector2:
	var min_distance_sq: float = _gift_config.relocate_min_distance_m * _gift_config.relocate_min_distance_m
	for attempt: int in range(_gift_config.spawn_max_attempts):
		var candidate: Vector2 = GiftSpawner.pick_spawn_point(raster, grid, _rng, _gift_config, _live_positions())
		if GiftSpawner.is_no_spawn_point(candidate):
			return GiftSpawner.NO_SPAWN_POINT
		if candidate.distance_squared_to(old_position) >= min_distance_sq:
			return candidate
	return GiftSpawner.NO_SPAWN_POINT


func _free_crate_visual(gift_id: int) -> bool:
	if not _crates.has(gift_id):
		return false
	_crates.erase(gift_id)
	var node: GiftCrate = _crate_nodes.get(gift_id) as GiftCrate
	_crate_nodes.erase(gift_id)
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
## disk-local (x, z); the crate sits on the field surface (spec 1.6:
## "stationary pickups"), lifted by half its own visual height so it rests on
## the surface rather than being bisected by it.
func _make_crate_node(point: Vector2, gift_id: int) -> GiftCrate:
	var container: Node3D = _gifts_container()
	if container == null:
		return null
	var crate: GiftCrate = GIFT_CRATE_SCENE.instantiate() as GiftCrate
	crate.gift_id = gift_id
	container.add_child(crate)
	var field: Field = _match.field()
	if field != null:
		crate.global_position = field.world_from_disk_local(point, GiftCrate.CRATE_SIZE.y * 0.5)
	else:
		crate.global_position = Vector3(point.x, GiftCrate.CRATE_SIZE.y * 0.5, point.y)
	return crate


# --- The client's read model (spec 2.6) -------------------------------------
# Called only by net/MatchNet.gd's net_match_event, only on a client (a
# well-behaved host never receives its own replicated RPC). A client never
# claims or expires anything itself -- these only build or free a visual, and
# the claim mirror keeps held_special()/pending_special_count() accurate for
# the client's HUD.

## Interpolate visuals only. Reaching the endpoint does not grant landing,
## claim or expiry authority; the reliable host event commits each transition.
func tick_client(delta: float) -> void:
	if _match._is_host() or not is_finite(delta) or delta <= 0.0:
		return
	for gift_id: int in _crates.keys():
		var flight: GiftFlight = _crates[gift_id]
		var progress: float = 1.0 if flight.phase != FALLING else flight.advance_fall(delta, _gift_config)
		var node: GiftCrate = _crate_nodes.get(gift_id) as GiftCrate
		if node != null and is_instance_valid(node):
			node.global_position = _live_crate_position(flight, progress)


func apply_replicated_spawn(gift_id: int, position: Vector2) -> void:
	if gift_id < 0 or not position.is_finite() or _crates.has(gift_id):
		return
	var landing: Vector3 = _world_at(position, GiftCrate.CRATE_SIZE.y * 0.5)
	_crates[gift_id] = GiftFlight.new(gift_id, position, landing, landing, LANDED)
	var node: GiftCrate = _make_crate_node(position, gift_id)
	if node != null:
		_crate_nodes[gift_id] = node


func apply_replicated_flight(gift_id: int, origin: Vector3, landing: Vector3) -> void:
	if gift_id < 0 or not origin.is_finite() or not landing.is_finite():
		return
	var field: Field = _match.field()
	var point: Vector2 = field.disk_local_from_world(landing) if field != null else Vector2(landing.x, landing.z)
	if not _crates.has(gift_id):
		apply_replicated_spawn(gift_id, point)
	var flight: GiftFlight = _crates[gift_id]
	if flight.flight_received:
		return
	flight.flight_received = true
	flight.position = point
	flight.origin = origin
	flight.landing = landing
	flight.phase = FALLING
	flight.elapsed = 0.0
	var node: GiftCrate = _crate_nodes.get(gift_id) as GiftCrate
	if node != null and is_instance_valid(node):
		node.global_position = origin
		node.set_falling(true)


func apply_replicated_landing(gift_id: int, landing: Vector3) -> void:
	if not _crates.has(gift_id) or not landing.is_finite():
		return
	var flight: GiftFlight = _crates[gift_id]
	if flight.phase != FALLING:
		return
	flight.land(landing)
	var node: GiftCrate = _crate_nodes.get(gift_id) as GiftCrate
	if node != null and is_instance_valid(node):
		node.global_position = _live_crate_position(flight, 1.0)
		node.set_falling(false)


## The resolved RECIPIENT slot arrives over the wire (the host already picked
## the one teammate nearest the crate in _claim_gift()), so this bounds-checks
## against _match.slot_count() before it reaches _ensure_capacity(): an
## unchecked garbage id would otherwise grow _pending_queues without limit on
## every client. net/MatchNet.gd's wire check has already rejected a malformed
## `special_id`.
##
## The crate visual is freed unconditionally: a well-behaved host only sends
## MatchWireEvents.GIFT_CLAIMED for a claim it actually accepted, so the host really did
## free that crate.
func apply_replicated_claim(gift_id: int, slot_id: int, special_id: StringName) -> void:
	_free_crate_visual(gift_id)
	if slot_id < 0 or slot_id >= _match.slot_count():
		return
	if special_id == GLUE_SPECIAL_ID:
		return # charges arrive through apply_replicated_glue_charges()
	_ensure_capacity(slot_id)
	if _match.feed().gift_after_next_active():
		# Mirrors the host's _queue_claimed_special(); the applier stages the carrier right after.
		_enqueue_after_next(slot_id, special_id, _match.feed().has_staged_gift(slot_id))
		return
	var queue: Array = _pending_queues[slot_id]
	queue.clear()
	queue.append(special_id)


func apply_replicated_expire(gift_id: int) -> void:
	_free_crate_visual(gift_id)


## The client mirror of pop_pending_special(), called by net/MatchNet.gd's
## MatchWireEvents.SPECIAL_CONSUMED dispatch (after its own wire check) right before it
## re-emits Events.special_consumed. Keeps a client's held_special() in step
## with the host, the spend-side counterpart of apply_replicated_claim().
##
## A garbage slot_id must never grow _pending_queues, so this bounds-checks
## against _match.slot_count() and never calls _ensure_capacity() itself.
##
## `_pending_queues` is keyed by recipient slot, the same slot
## pop_pending_special() popped on the host, so this indexes `slot_id`
## directly with no team_of_slot() translation.
func apply_replicated_special_consumed(slot_id: int, special_id: StringName) -> void:
	if slot_id < 0 or slot_id >= _match.slot_count():
		return
	if held_special(slot_id) != special_id:
		push_warning(
			"MatchGifts: special_consumed mirror mismatch for slot %d (head=%s, reported=%s); popping head anyway"
			% [slot_id, held_special(slot_id), special_id]
		)
	_held_specials.erase(slot_id)


## autoload/match/MatchLifecycle.gd's _reset_match_state() one-line call:
## drops every live crate (host-spawned or client-mirrored) and every pending
## special queue, and un-seeds the RNG so the next match reseeds from its own
## config.rng_seed. Leaves _match alone -- same shape as every other
## controller's reset. Leaves _special_drawer untouched: it is an injectable
## dependency (set_special_drawer()), not per-match state, the same way
## _gift_config is never reset here either.
func reset() -> void:
	_gift_slots.clear()
	_held_specials.clear()
	_glue_drops.clear()
	_glue_revisions.clear()
	for node: Object in _crate_nodes.values():
		if is_instance_valid(node):
			(node as GiftCrate).queue_free()
	_crate_nodes.clear()
	_crates.clear()
	_pending_queues.clear()
	_next_gift_id = 0
	_play_time_s = 0.0
	_rng_ready = false
	_roster_ready = false
	_special_roster = []
	_special_rng_ready = false
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
