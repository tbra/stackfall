class_name MatchGifts
extends RefCounted
## Match's gift-crate lifecycle (spec 2.6): per-window spawn rolls, the
## territory-tick claim/expire sweep, and one replaceable next gift per slot.
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
const FALLING: int = 0
const LANDED: int = 1

## The id MatchGifts.PENDING_SPECIAL_ID's default drawer hands out until P2c
## installs the real weighted SpecialDef pick (set_special_drawer() below).
## Also the fallback a malformed drawer result is replaced with -- see
## _draw_special_id().
const PENDING_SPECIAL_ID: StringName = &"special_pending"

## DECISION (autoload/match/MatchGifts.gd, M6 A4): ui/Lobby.gd's specials
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

## Orchestrator amendment 1 (docs/M4_P2_PACKAGES.md, 2026-09-23): the special
## TYPE is drawn here, at claim time, on the host -- not at spawn time. Spec
## 2.6 hands a player "a special as the next piece", so the player (and
## later the HUD/ghost) must be able to know what they hold while aiming,
## not just that they hold something. _draw_special_id() is the one call
## site; P2c installs the real weighted SpecialDef.pick_weighted() draw
## through set_special_drawer() once config/specials/ exists. Kept an
## injectable Callable rather than a hard SpecialDef dependency so P2a and
## P2b can land in parallel with fully disjoint files.
var _special_drawer: Callable = _default_special_drawer

## M4 P2c: the roster _weighted_special_drawer() draws from, filtered to
## `_match.config.enabled_specials` (empty means every special, per
## config/MatchConfig.gd:57's own doc comment) once per match, plus the own
## RNG that draw uses. Reset flags (`_roster_ready`/`_special_rng_ready`) so a
## new match re-filters against its own config rather than reusing the
## previous match's roster or reseeding an already-seeded RNG.
##
## DECISION (autoload/match/MatchGifts.gd, M4 P2c): the P2c package brief
## says the real drawer is installed "on match start/setup"; there is no
## start_match() hook this package may add one to without editing
## autoload/match/MatchLifecycle.gd (owned by a different package, and not
## this package's file) or autoload/Match.gd's _ready() (config is not yet
## assigned there either). Installing lazily on first real use --
## _ensure_special_drawer_installed(), called from _claim_gift() right before
## _draw_special_id() -- mirrors _ensure_rng()'s own lazy convention just
## below and needs no other file to know P2c exists.
var _roster_ready: bool = false
var _special_roster: Array[SpecialDef] = []
var _special_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _special_rng_ready: bool = false

## Live, unclaimed crates: gift_id -> {"position": Vector2 (disk-local),
## "age": float, "node": GiftCrate}. Every entry, host or client mirror, is
## created and freed only through _make_crate_node()/_free_crate_visual() so
## the two paths cannot drift.
var _crates: Dictionary = {}

## Parallel to Match's slots: each inner array has zero or one next gift.
## A new claim replaces its element and never changes the current held piece.
## Grown lazily by
## _ensure_capacity() rather than sized off slot_count() at reset() time,
## because _reset_match_state() runs *before* the new match's slots are built
## (autoload/match/MatchLifecycle.gd's start_match(): reset, then
## _build_slots()) -- see that file's one-line reset() call below.
##
## Bontago-keo.17 (owner decision "b"): keyed by RECIPIENT SLOT, not by team.
## A crate claimed in a team's territory is offered to the one teammate whose
## home circle is nearest the crate (_resolve_recipient_slot() below), never
## to a queue shared by the whole team -- so index i here is always slot i's
## own queue, read/written directly, with no team_of_slot() translation.
##
## DECISION (autoload/match/MatchGifts.gd, M4 P2b): this engine (Godot
## 4.7.2) parses `Array[Array[StringName]]` as a "nested typed collections
## are not supported" error -- verified directly against this build, not
## assumed from docs. The outer array is therefore a plain `Array[Array]`;
## each inner queue is still built exactly once, as a real `Array[StringName]`,
## by _new_typed_queue() below, so every element still carries StringName's
## runtime type check. Only the outer container's own element type is
## unenforced by the engine.
var _pending_queues: Array[Array] = []
## The queued gift is separate from the currently held piece. A claim never
## changes this value; only the subsequent feed activates the queued gift.
var _held_specials: Dictionary = {}
## DECISION (Bontago-22y.3.1): a dictionary keyed by recipient slot keeps
## charges independent of the shared GlueEffect resource and gift queue.
## A later Glue activation replaces the count instead of adding to it.
var _glue_drops: Dictionary = {}
## Absolute charge updates carry a per-slot revision so duplicate or delayed
## reliable packets cannot restore a spent charge on a client.
var _glue_revisions: Dictionary = {}

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


## The default drawer: always PENDING_SPECIAL_ID, until P2c installs the real
## weighted SpecialDef pick via set_special_drawer(). Bound as a Callable
## default at declaration time (autoload/match/MatchGifts.gd's field-order
## comment above _special_drawer), so P2a and P2b's file sets never overlap.
func _default_special_drawer() -> StringName:
	return PENDING_SPECIAL_ID


## Host-only entry point P2c calls once config/specials/ exists; `drawer`
## must be a `func() -> StringName`. Passing an invalid/null Callable is not
## guarded here -- Callable.call() on one simply fails at the call site in
## _draw_special_id(), which is guarded (see its own doc comment).
func set_special_drawer(drawer: Callable) -> void:
	_special_drawer = drawer


## Builds one fresh per-slot queue. A real Array[StringName], not a plain
## Array -- see _pending_queues' own DECISION for why the *outer* container
## cannot also be typed on this engine version.
func _new_typed_queue() -> Array[StringName]:
	var queue: Array[StringName] = []
	return queue


## Bontago-keo.17: still needed by _resolve_recipient_slot() below to test
## whether a given slot is on the claiming team at all (team membership), now
## that `_pending_queues` itself is keyed by recipient slot, not by team --
## held_special()/pop_pending_special()/pending_special_count()/
## debug_queue_special() no longer translate through this.
## `_match.config` can be null before a match ever starts; a null config falls
## back to `slot_id` itself, exactly what team_of_slot() returns for
## TeamMode.OFF.
func _team_id_for_slot(slot_id: int) -> int:
	if _match.config == null:
		return slot_id
	return _match.config.team_of_slot(slot_id)


## The oldest pending special `slot_id` is holding, or &"" for none -- a
## peek, not a pop. P2c reads this to decide whether the next spawned block
## should be a special; the HUD (Bontago-1en.16, split out of this package)
## reads pending_special_count() for the queued-count indicator.
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
	queue.clear()


## Presentation getter (Bontago-59o.13): the queued gift that will be the
## slot's NEXT held piece, or &"" for none. A peek; changes no state.
func next_special(slot_id: int) -> StringName:
	if slot_id < 0 or slot_id >= _pending_queues.size():
		return &""
	var queue: Array = _pending_queues[slot_id]
	return StringName(queue[0]) if not queue.is_empty() else &""


func clear_held_special(slot_id: int) -> void:
	_held_specials.erase(slot_id)


func defer_held_special_after_burn(slot_id: int) -> void:
	var special_id: StringName = held_special(slot_id)
	if special_id == &"":
		return
	_ensure_capacity(slot_id)
	var queue: Array = _pending_queues[slot_id]
	# DECISION (Bontago-3ow.5): a later claim already owns the next slot.
	# A burned held gift must not replace it with the older gift again.
	# Without a later claim, keep the existing burn behavior: retry this gift
	# as the next held piece, replacing the next ordinary draw.
	if queue.is_empty():
		queue.append(special_id)
		_match._feed.replace_next_with_gift(slot_id)
	_held_specials.erase(slot_id)


## Consumes the held gift, or returns &"" for an ordinary piece. The next
## gift remains untouched until MatchFeed issues it as a held piece.
##
## Bontago-1en.21: the one host-side emit site for Events.special_consumed --
## _attach_pending_special() (autoload/match/MatchPlacement.gd) is this
## function's only caller, on the place-spawn non-burn path and always on a
## throw, so a single emit here covers both consumers without a second call
## site in MatchPlacement.gd. A burned auto-drop never reaches this call at
## all (see that function's own doc comment on why), so it never emits either
## -- exactly the P2c-i rule that a burn keeps the special queued. Both
## real callers are host-only (request_place()/request_throw() refuse
## immediately off-host), so this never runs on a client in the shipped game;
## unit tests that call it directly (test_gift_claim.gd,
## test_match_throw.gd) exercise the same host-only emit deliberately.
func pop_pending_special(slot_id: int) -> StringName:
	var popped: StringName = held_special(slot_id)
	if popped == &"":
		return &""
	_held_specials.erase(slot_id)
	Events.special_consumed.emit(slot_id, popped)
	return popped


## Count the held gift and the one queued behind it for HUD compatibility.
func pending_special_count(slot_id: int) -> int:
	if slot_id < 0 or slot_id >= _pending_queues.size():
		return 1 if held_special(slot_id) != &"" else 0
	var queue: Array = _pending_queues[slot_id]
	return queue.size() + (1 if held_special(slot_id) != &"" else 0)


## The gift_id every debug_queue_special() claim reports (Bontago-1en.24).
## _spawn_crate_at()'s real ids start at 0 and only ever increase, so a
## negative sentinel can never collide with one -- a client/HUD watching
## Events.gift_claimed sees an id it can recognize as "not a real crate" if it
## ever needs to (nothing does today).
const DEBUG_GIFT_ID: int = -1


## Sandbox-only debug entry point (Bontago-1en.24, game/Sandbox.gd's F9
## sandbox_force_special hotkey and `--force-special=`): replaces `slot_id`'s
## next gift and emits Events.gift_claimed with
## DEBUG_GIFT_ID, exactly the same signal _claim_gift() fires for a real
## claim, so the HUD/ghost/client mirrors all follow the normal path with no
## second code path to keep in sync. Skips the crate roll and the
## territory-tick claim sweep entirely -- there is no crate to free.
##
## Gated the same way _claim_gift()/claim_or_expire_gifts() already are
## (`if not _match._is_host(): return`) plus one more check this package adds
## on top: `_match.config.sandbox` must also be true, so a real match can
## never be handed a free special through this seam even if something
## mistakenly called it host-side.
func debug_queue_special(slot_id: int, special_id: StringName) -> bool:
	if not _match._is_host():
		return false
	if _match.config == null or not _match.config.sandbox:
		return false
	if slot_id < 0 or slot_id >= _match.slot_count():
		return false
	_ensure_capacity(slot_id)
	var queue: Array = _pending_queues[slot_id]
	queue.clear()
	queue.append(special_id)
	_match._feed.replace_next_with_gift(slot_id)
	# slot_id, not a team id -- matches _claim_gift()'s own gift_claimed emit
	# below, whose second parameter is the resolved recipient slot
	# (Events.gd's gift_claimed signal -- Bontago-keo.17).
	Events.gift_claimed.emit(DEBUG_GIFT_ID, slot_id, special_id)
	return true


## Sandbox-only reset seam (Bontago-1en.24, game/Sandbox.gd's F9 hotkey
## turning back "off"): re-runs the exact same lazy install
## _ensure_special_drawer_installed() already performs at a match's first
## real claim, rather than a second, divergent copy of that roster-filtering
## logic living in game/Sandbox.gd. Resets `_roster_ready` first so the lazy
## install actually runs again -- a forced special's own set_special_drawer()
## call already replaced whatever ran before, so a plain
## _ensure_special_drawer_installed() call would otherwise stay a no-op
## forever, per its own idempotency guard.
func restore_default_special_drawer() -> void:
	_roster_ready = false
	_ensure_special_drawer_installed()


func _ensure_capacity(slot_id: int) -> void:
	while _pending_queues.size() <= slot_id:
		_pending_queues.append(_new_typed_queue())


## DECISION (autoload/match/MatchGifts.gd, M4 P1b): "the feed issues a new
## window" is Events.feed_block_issued -- MatchFeed._issue_next_block() emits
## it every time any slot is handed a new held piece, on an early release, a
## forced auto-drop, or a hot-seat turn change alike. autoload/Match.gd
## connects this to Events.feed_block_issued and forwards slot_id here.
##
## Feed issuance activates a queued gift in MatchFeed before this callback.
## Gift activation and the ordinary piece after gift use do not create new
## ordinary placement windows, so neither gets a gift-spawn roll. Other
## rolls are gated here by _should_roll_for_window()
## below -- see review fix (Beads Bontago-4fa): outside hot-seat every
## slot's window advances independently (spec 2.4's "players act
## concurrently, each handling their own supplied piece"), so rolling here
## unconditionally gave an N-player match ~N rolls per window instead of
## GiftSpawner.should_spawn()'s documented "one roll per window, for the
## whole match, not per player".
func on_feed_block_issued(slot_id: int) -> void:
	if not _match._is_host():
		return
	if _match._feed._suppress_gift_roll:
		return
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


## Spec 2.8's sudden-death bullet: "Gift probability climbs toward the
## maximum of the finalized spawn model (2.6)." Outside sudden death this is
## exactly `_match.config.special_frequency` (should_spawn()'s existing
## input, unchanged behaviour); once MatchLifecycle.sudden_death_active() is
## true it lerps monotonically toward MatchConfig.SPECIAL_FREQUENCY_MAX --
## GiftConfig.frequency_to_chance_max is already the finalized spawn model's
## own maximum spawn chance (spec 2.6), so should_spawn() itself needs no
## change, only what frequency value it is handed -- over
## TerritoryTuning.sudden_death_ramp_s, then clamps there for the rest of the
## match. See that tunable's own DECISION for why the ramp duration is not
## spec-given.
func _effective_special_frequency() -> float:
	var base_frequency: float = float(_match.config.special_frequency) if _match.config != null else 0.0
	if not _match._lifecycle.sudden_death_active():
		return base_frequency
	var ramp_s: float = maxf(_match._territory_tuning.sudden_death_ramp_s, 0.001)
	var t: float = clampf(_match._lifecycle._sudden_death_elapsed / ramp_s, 0.0, 1.0)
	return lerpf(base_frequency, float(MatchConfig.SPECIAL_FREQUENCY_MAX), t)


func _try_spawn() -> void:
	if _match.config == null or not _match.config.gifts_enabled:
		return
	var raster: TerritoryRaster = _match.raster()
	var grid: CellGrid = _match.cell_grid()
	if raster == null or grid == null:
		return
	_ensure_rng()
	if not GiftSpawner.should_spawn(_gift_config, _effective_special_frequency(), _crates.size(), _rng):
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


## Lazily installs the real weighted-SpecialDef drawer the first time a
## match actually claims a crate, filtered to
## `_match.config.enabled_specials` (empty means every special --
## config/MatchConfig.gd:57). Idempotent per match via `_roster_ready`,
## cleared by reset(). Keeps `_special_drawer` at its default
## (_default_special_drawer, always PENDING_SPECIAL_ID) when the filtered
## roster is empty -- P3-P5 have not landed any config/specials/*.tres yet,
## so a spawn with no draw stays a safe, ordinary block (see
## MatchPlacement._spawn_block()'s own P2c extension).
func _ensure_special_drawer_installed() -> void:
	if _roster_ready:
		return
	_roster_ready = true
	var all_defs: Array[SpecialDef] = SpecialDef.load_all_specials()
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


## DECISION (autoload/match/MatchGifts.gd, M4 P2c): rng_seed + a distinct odd
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
## filtered roster is non-empty. Roulette-weighted via SpecialDef.
## pick_weighted() -- see that function's own null-on-empty-array contract,
## guarded against here too since `_special_roster` could in principle be
## reassigned empty only by _ensure_special_drawer_installed() itself, which
## never installs this Callable in that case; kept anyway so this function's
## own contract (always a valid, non-empty StringName) never depends on that.
func _weighted_special_drawer() -> StringName:
	var picked: SpecialDef = SpecialDef.pick_weighted(_special_roster, _special_rng)
	return picked.id if picked != null else PENDING_SPECIAL_ID


func _spawn_crate_at(point: Vector2) -> void:
	var gift_id: int = _next_gift_id
	_next_gift_id += 1
	var landing: Vector3 = _world_at(point, GiftCrate.CRATE_SIZE.y * 0.5)
	var origin: Vector3 = landing + Vector3.UP * _gift_config.drop_height_m
	var node: GiftCrate = _make_crate_node(point, gift_id)
	_crates[gift_id] = {"position": point, "origin": origin, "landing": landing,
		"elapsed": 0.0, "age": 0.0, "phase": FALLING, "node": node}
	if node != null:
		node.global_position = origin
		node.set_falling(true)
	Events.gift_flight_spawned.emit(gift_id, origin, landing)
	Events.gift_spawned.emit(gift_id, point)


func _world_at(point: Vector2, height: float) -> Vector3:
	var field: Field = _match.field()
	return field.world_from_disk_local(point, height) if field != null else Vector3(point.x, height, point.y)


## Host and client use the same time/id-derived arc; no extra wire data or
## random state is needed. Clients begin on event receipt, so their visual can
## trail the host by transport latency; only the host resolves airborne touch.
## Height stays linear, and sway fades to the exact authoritative landing point.
func _flight_position(gift_id: int, origin: Vector3, landing: Vector3,
		elapsed: float, progress: float) -> Vector3:
	if progress <= 0.0:
		return origin
	if progress >= 1.0:
		return landing
	var straight: Vector3 = origin.lerp(landing, progress)
	var amplitude: float = maxf(_gift_config.sway_amplitude_m, 0.0) * sin(PI * progress)
	var angle: float = TAU * maxf(_gift_config.sway_frequency_hz, 0.0) * elapsed + float(gift_id) * 2.39996323
	return straight + Vector3(sin(angle), 0.0, sin(angle * 0.73 + 0.8)) * amplitude


## A copy safe for minimap and network consumers. Position is host-authored.
func gift_state(gift_id: int) -> Dictionary:
	var entry: Dictionary = _crates.get(gift_id, {})
	if entry.is_empty():
		return {}
	return {"id": gift_id, "phase": int(entry.get("phase", LANDED)),
		"position": entry["position"], "origin": entry.get("origin", Vector3.ZERO),
		"landing": entry.get("landing", Vector3.ZERO),
		"elapsed": float(entry.get("elapsed", 0.0)), "landed_age": float(entry.get("age", 0.0))}


func gift_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[int] = []
	for gift_id: int in _crates.keys():
		ids.append(gift_id)
	ids.sort()
	for gift_id: int in ids:
		result.append(gift_state(gift_id))
	return result


## Runs only on host physics ticks. Sorted ids and slots make contention stable.
func tick_host(delta: float) -> void:
	if not _match._is_host():
		return
	if delta <= 0.0 or _crates.is_empty():
		return
	var ids: Array[int] = []
	for gift_id: int in _crates.keys():
		ids.append(gift_id)
	ids.sort()
	for gift_id: int in ids:
		if not _crates.has(gift_id):
			continue
		var entry: Dictionary = _crates[gift_id]
		if int(entry.get("phase", LANDED)) == FALLING:
			var origin: Vector3 = entry["origin"]
			var landing: Vector3 = entry["landing"]
			var distance: float = origin.distance_to(landing)
			var elapsed: float = float(entry["elapsed"]) + delta
			entry["elapsed"] = elapsed
			var progress: float = 1.0 if distance <= 0.0 else minf(elapsed * maxf(_gift_config.fall_speed_m_s, 0.001) / distance, 1.0)
			var world_position: Vector3 = _flight_position(gift_id, origin, landing, elapsed, progress)
			var node: GiftCrate = entry.get("node") as GiftCrate
			if node != null and is_instance_valid(node):
				node.global_position = world_position
			for slot_id: int in range(_match.slot_count()):
				if _held_block_touches(slot_id, world_position):
					if _claim_gift_for_slot(gift_id, slot_id):
						break
			if not _crates.has(gift_id):
				continue
			if progress >= 1.0:
				entry["phase"] = LANDED
				entry["age"] = 0.0
				if node != null and is_instance_valid(node):
					node.set_falling(false)
				Events.gift_landed.emit(gift_id, landing)
				_claim_landed(gift_id)
		else:
			_claim_landed(gift_id)
			if not _crates.has(gift_id):
				continue
			entry["age"] = float(entry.get("age", 0.0)) + delta
			if float(entry["age"]) >= _gift_config.life_s:
				_expire_gift(gift_id)


## Territory can change between physics ticks; this hook follows each solve.
func claim_or_expire_gifts(_delta: float) -> void:
	if not _match._is_host():
		return
	for gift_id: int in _crates.keys():
		if _crates.has(gift_id) and int(_crates[gift_id].get("phase", LANDED)) == LANDED:
			_claim_landed(gift_id)


func _claim_landed(gift_id: int) -> void:
	var raster: TerritoryRaster = _match.raster()
	var grid: CellGrid = _match.cell_grid()
	if raster == null or grid == null:
		return
	var entry: Dictionary = _crates.get(gift_id, {})
	if entry.is_empty() or int(entry.get("phase", LANDED)) != LANDED:
		return
	var cell: Vector2i = grid.world_to_cell(entry["position"])
	var team: int = raster.team_at(cell.x, cell.y) if grid.in_bounds(cell.x, cell.y) else -1
	if team >= 0:
		_claim_gift(gift_id, team)


## Only an accepted host cursor or the local held ghost is eligible.
func _held_block_touches(slot_id: int, crate_world: Vector3) -> bool:
	var slot: PlayerSlot = _match.slot(slot_id)
	var shape: BlockShape = _match.held_shape(slot_id)
	if slot == null or not slot.home_flag_alive or shape == null:
		return false
	if (_match.config.hot_seat or _match.config.turn_based) and slot_id != _match.active_slot():
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
		var tree: SceneTree = _match.get_tree()
		var ghost: GhostPreview = tree.get_first_node_in_group(GhostPreview.LOCAL_HELD_GROUP) as GhostPreview
		if ghost != null and ghost.get_shape() == shape:
			origin = ghost.global_position
			orientation = ghost.orientation_index
			free_quat = ghost.free_quaternion
			found = true
	if not found or not _match.is_pose_well_formed(origin, orientation, free_quat):
		return false
	var basis: Basis = Basis(free_quat) * BlockOrientations.get_basis(orientation)
	var half: float = _match._physics_tuning.cube_size * 0.5 + _gift_config.air_touch_margin_m
	var crate_half: Vector3 = GiftCrate.CRATE_SIZE * 0.5
	var pivot: Vector3 = shape.bottom_center()
	for cell: Vector3i in shape.cells:
		var center: Vector3 = origin + basis * ((Vector3(cell) - pivot) * _match._physics_tuning.cube_size)
		if _oriented_cube_overlaps_crate(center, basis, half, crate_world, crate_half):
			return true
	return false


## Separating-axis test for a rotated held cell and the world-aligned crate.
## The three face axes of each box plus nine edge cross-products cover every
## possible separation. Only the held cell expands by the configured margin.
func _oriented_cube_overlaps_crate(
	cell_center: Vector3, basis: Basis, cell_half: float,
	crate_center: Vector3, crate_half: Vector3
) -> bool:
	var world_axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var cell_axes: Array[Vector3] = [basis.x, basis.y, basis.z]
	var axes: Array[Vector3] = []
	axes.append_array(world_axes)
	axes.append_array(cell_axes)
	for world_axis: Vector3 in world_axes:
		for cell_axis: Vector3 in cell_axes:
			var cross_axis: Vector3 = world_axis.cross(cell_axis)
			if cross_axis.length_squared() > 0.00000001:
				axes.append(cross_axis)
	var displacement: Vector3 = crate_center - cell_center
	for axis: Vector3 in axes:
		var crate_radius: float = (
			crate_half.x * absf(axis.x) + crate_half.y * absf(axis.y)
			+ crate_half.z * absf(axis.z)
		)
		var cell_radius: float = cell_half * (
			absf(axis.dot(cell_axes[0])) + absf(axis.dot(cell_axes[1]))
			+ absf(axis.dot(cell_axes[2]))
		)
		if absf(displacement.dot(axis)) > crate_radius + cell_radius:
			return false
	return true


func _claim_gift_for_slot(gift_id: int, slot_id: int) -> bool:
	if not _crates.has(gift_id):
		return false
	_ensure_capacity(slot_id)
	var queue: Array = _pending_queues[slot_id]
	if not _free_crate_visual(gift_id):
		return false
	_ensure_special_drawer_installed()
	var special_id: StringName = _draw_special_id()
	queue.clear()
	queue.append(special_id)
	_match._feed.replace_next_with_gift(slot_id)
	Events.gift_claimed.emit(gift_id, slot_id, special_id)
	return true


## Bontago-keo.17 (owner decision "b", overriding this file's earlier "one
## shared team queue" design): a crate claimed in `team_id`'s territory is
## offered to the ONE teammate whose home circle is nearest the crate, not to
## every teammate through a queue they all share. _resolve_recipient_slot()
## below does that resolution; if no teammate's home flag is still alive, the
## crate is left untouched (no claim, no crate consumed, no event).
##
## Bontago-3ow.5: the latest claim replaces this recipient's next gift or
## ordinary draw. Resolve the recipient before freeing the crate because its
## position is needed for that choice.
func _claim_gift(gift_id: int, team_id: int) -> void:
	if team_id < 0:
		return
	var entry: Dictionary = _crates.get(gift_id, {})
	if entry.is_empty():
		return
	var crate_position: Vector2 = entry["position"]
	var recipient_slot: int = _resolve_recipient_slot(team_id, crate_position)
	if recipient_slot < 0:
		return
	_ensure_capacity(recipient_slot)
	var queue: Array = _pending_queues[recipient_slot]
	if not _free_crate_visual(gift_id):
		return
	_ensure_special_drawer_installed()
	var special_id: StringName = _draw_special_id()
	queue.clear()
	queue.append(special_id)
	_match._feed.replace_next_with_gift(recipient_slot)
	Events.gift_claimed.emit(gift_id, recipient_slot, special_id)


## Bontago-keo.17 (owner decision "b" on docs/M6_PLAN.md's Owner Q1): picks
## the alive (home_flag_alive) member of `team_id` whose home circle
## (PlayerSlot.home_position, disk-local, computed once by
## MatchLifecycle._build_slots()) is closest to `crate_position`. Returns -1
## if `team_id` has no living teammate to give the special to.
##
## DECISION (autoload/match/MatchGifts.gd, Bontago-keo.17): the spec/owner
## answer settles "nearest wins" but not an exact tie (two teammates
## equidistant from the crate). Iterating slots in ascending id order and
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


## Orchestrator amendment 1: the special TYPE is drawn here, at claim time.
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


## Owner playtest report (Bontago-1pi.2, "Unclaimed presents should respawn in
## different places when unclaimed"): captures the expiring crate's own
## position before _free_crate_visual() erases its `_crates` entry, so
## _relocate_after_expiry() below has something to measure the replacement's
## minimum distance against.
func _expire_gift(gift_id: int) -> void:
	var entry: Dictionary = _crates.get(gift_id, {})
	if entry.is_empty():
		return
	var old_position: Vector2 = entry["position"]
	if not _free_crate_visual(gift_id):
		return
	Events.gift_expired.emit(gift_id)
	_relocate_after_expiry(old_position)


## Bontago-1pi.2: an expired (unclaimed) crate is immediately replaced by a
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
## the instant before expiry (spec 2.6 unchanged; owner instruction: "the
## relocated crate counts as the live crate").
##
## DECISION (autoload/match/MatchGifts.gd, Bontago-1pi.2): if no valid spot
## clearing relocate_min_distance_m can be found (raster/grid missing, gifts
## disabled mid-match, or _pick_relocation_point() exhausts its attempt
## budget), this simply falls back to the existing pre-Bontago-1pi.2 behavior
## -- the crate stays gone and the next spawn comes from the ordinary
## per-window roll -- rather than forcing a spawn at a too-close or invalid
## point.
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
		# DECISION: fall back to the existing behavior (no immediate
		# replacement; the next ordinary per-window roll will spawn one) --
		# see this function's own doc comment above.
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
		var candidate: Vector2 = GiftSpawner.pick_spawn_point(raster, grid, _rng, _gift_config)
		if GiftSpawner.is_no_spawn_point(candidate):
			return GiftSpawner.NO_SPAWN_POINT
		if candidate.distance_squared_to(old_position) >= min_distance_sq:
			return candidate
	return GiftSpawner.NO_SPAWN_POINT


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


# --- The client's read model (spec 3.4) -------------------------------------
# Called only by net/MatchNet.gd's net_match_event, only on a client (a
# well-behaved host never receives its own replicated RPC). A client never
# claims or expires anything itself -- these three only ever build or free a
# visual, and the claim mirror also keeps held_special()/pending_special_
# count() accurate for a client's own future HUD/P2c use.

## Interpolate visuals only. Reaching the endpoint does not grant landing,
## claim or expiry authority; the reliable host event commits each transition.
func tick_client(delta: float) -> void:
	if _match._is_host() or not is_finite(delta) or delta <= 0.0:
		return
	for gift_id: int in _crates.keys():
		var entry: Dictionary = _crates[gift_id]
		if int(entry.get("phase", LANDED)) != FALLING:
			continue
		var origin: Vector3 = entry["origin"]
		var landing: Vector3 = entry["landing"]
		var distance: float = origin.distance_to(landing)
		var elapsed: float = float(entry["elapsed"]) + delta
		entry["elapsed"] = elapsed
		var progress: float = 1.0 if distance <= 0.0 else minf(elapsed * maxf(_gift_config.fall_speed_m_s, 0.001) / distance, 1.0)
		var node: GiftCrate = entry.get("node") as GiftCrate
		if node != null and is_instance_valid(node):
			node.global_position = _flight_position(gift_id, origin, landing, elapsed, progress)


func apply_replicated_spawn(gift_id: int, position: Vector2) -> void:
	if gift_id < 0 or not position.is_finite() or _crates.has(gift_id):
		return
	var landing: Vector3 = _world_at(position, GiftCrate.CRATE_SIZE.y * 0.5)
	_crates[gift_id] = {"position": position, "origin": landing, "landing": landing,
		"elapsed": 0.0, "age": 0.0, "phase": LANDED, "node": _make_crate_node(position, gift_id)}


func apply_replicated_flight(gift_id: int, origin: Vector3, landing: Vector3) -> void:
	if gift_id < 0 or not origin.is_finite() or not landing.is_finite():
		return
	var field: Field = _match.field()
	var point: Vector2 = field.disk_local_from_world(landing) if field != null else Vector2(landing.x, landing.z)
	if not _crates.has(gift_id):
		apply_replicated_spawn(gift_id, point)
	var entry: Dictionary = _crates[gift_id]
	if entry.get("flight_received", false):
		return
	entry["flight_received"] = true
	entry["position"] = point
	entry["origin"] = origin
	entry["landing"] = landing
	entry["phase"] = FALLING
	entry["elapsed"] = 0.0
	var node: GiftCrate = entry.get("node") as GiftCrate
	if node != null and is_instance_valid(node):
		node.global_position = origin
		node.set_falling(true)


func apply_replicated_landing(gift_id: int, landing: Vector3) -> void:
	if not _crates.has(gift_id) or not landing.is_finite():
		return
	var entry: Dictionary = _crates[gift_id]
	if int(entry.get("phase", LANDED)) != FALLING:
		return
	entry["phase"] = LANDED
	entry["landing"] = landing
	entry["age"] = 0.0
	var node: GiftCrate = entry.get("node") as GiftCrate
	if node != null and is_instance_valid(node):
		node.global_position = landing
		node.set_falling(false)


## Bontago-keo.17 (owner decision "b"): the resolved RECIPIENT slot arrives
## over the wire -- the host already picked the one teammate nearest the
## crate in _claim_gift() before it ever replicated this event -- so this
## bounds-checks against _match.slot_count() before it ever reaches
## _ensure_capacity(). An unchecked garbage id would otherwise grow
## _pending_queues without limit on every client that received it. Mirrors
## MatchLifecycle.apply_replicated_elimination()'s own slot(slot_id)
## null-check convention.
##
## Bontago-csc: mirrors _claim_gift()'s own cap check (net/MatchNet.gd's wire
## check has already rejected a malformed `special_id` by the time this
## runs) -- a client's queue can never exceed the same
## GiftConfig.max_pending_specials the host enforces. The crate visual is
## freed unconditionally either way: a well-behaved host only ever sends
## EVENT_GIFT_CLAIMED for a claim it actually accepted (amendment 3 keeps a
## claim into a full queue from firing gift_claimed at all), so by the time a
## client applies this, the host really did free that crate.
func apply_replicated_claim(gift_id: int, slot_id: int, special_id: StringName) -> void:
	_free_crate_visual(gift_id)
	if slot_id < 0 or slot_id >= _match.slot_count():
		return
	_ensure_capacity(slot_id)
	var queue: Array = _pending_queues[slot_id]
	queue.clear()
	queue.append(special_id)


func apply_replicated_expire(gift_id: int) -> void:
	_free_crate_visual(gift_id)


## Bontago-1en.21: the client mirror of pop_pending_special(), called by
## net/MatchNet.gd's EVENT_SPECIAL_CONSUMED dispatch (after its own wire
## check) right before it re-emits Events.special_consumed. Keeps a client's
## pending_special_count()/held_special() shrinking in step with the host's
## queue, the spend-side counterpart of apply_replicated_claim()'s own
## grow-side mirror.
##
## Review fix pattern (Must #1, mirrored from apply_replicated_claim()): a
## garbage slot_id must never grow _pending_queues, so this bounds-checks
## against _match.slot_count() and never calls _ensure_capacity() itself --
## unlike a claim, a consumed-special mirror has nothing useful to do for a
## slot whose queue was never grown by an earlier claim anyway.
##
## Bontago-keo.17 (owner decision "b", superseding the earlier M6 A1 team
## translation here): `_pending_queues` is now keyed by recipient slot, the
## same slot pop_pending_special() popped on the host, so this indexes
## `slot_id` directly -- no team_of_slot() translation needed or correct
## anymore (a teammate other than the resolved recipient never held this
## special in the first place).
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
	_held_specials.clear()
	_glue_drops.clear()
	_glue_revisions.clear()
	# MatchLifecycle clears the feed arrays before calling this reset.
	_match._feed._next_gift_shapes.clear()
	_match._feed._held_is_gift.clear()
	for gift_id: int in _crates.keys():
		var entry: Dictionary = _crates[gift_id]
		var node: GiftCrate = entry.get("node") as GiftCrate
		if node != null and is_instance_valid(node):
			node.queue_free()
	_crates.clear()
	_pending_queues.clear()
	_next_gift_id = 0
	_rng_ready = false
	_roster_ready = false
	_special_roster = []
	_special_rng_ready = false
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
	_container = null
