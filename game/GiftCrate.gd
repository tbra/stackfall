class_name GiftCrate
extends Area3D
## A gift crate (spec 2.6): a stationary pickup that shows which player it
## belongs to once claimed. Presence-only for M4 P1 -- a block or a thrown
## special can be seen to strike it, matching the chain-reaction flavor text,
## even though nothing here currently *reacts* to that contact: body_entered
## is wired to a documented, harmless no-op a later milestone can fill in
## (P3/P4/P5's specials do not need to know about crates this milestone).
##
## Built from meshes, the same reason game/HomeFlag.gd is: M2-era placeholder
## art, replaced whole in M7. autoload/match/MatchGifts.gd owns the only two
## calls that matter here -- instancing this scene and calling
## set_owner_tint() -- so no rule of any kind lives on this script.
##
## DECISION (game/GiftCrate.gd): CRATE_SIZE/UNCLAIMED_COLOR are fixed visual
## constants, not gameplay tunables -- this package owns no config file
## (docs/M4_P1b brief); move them into GiftConfig if a later package needs
## them configurable (flagged under Unresolved in the P1b report).
const CRATE_SIZE: Vector3 = Vector3(0.6, 0.6, 0.6)
const UNCLAIMED_COLOR: Color = Color(0.85, 0.75, 0.15)

## Set by MatchGifts right after instancing. -1 (this crate is not tracked by
## anything) is never a real id (MatchGifts._next_gift_id starts at 0).
var gift_id: int = -1
var owner_slot: int = -1

var _mesh: MeshInstance3D = null
var _material: StandardMaterial3D = null

## Bontago-d04 (owner report "I grabbed a yellow cube but nothing seemed to
## happen"): the claim rule itself was never broken (spec 2.6 [ORIGINAL]: a
## crate claims only when it lands inside the claiming slot's own territory
## — see autoload/match/MatchGifts.gd's claim_or_expire_gifts()), but a
## successful claim had no visible feedback at all: MatchGifts.
## _free_crate_visual() queue_free()s this node the instant it is claimed, so
## by the time Events.gift_claimed reaches any listener the crate is already
## marked for deferred deletion. A Tween created on a node after queue_free()
## has already been called is unreliable — Godot kills a node-bound Tween the
## moment the node is actually freed, which can land mid-animation — so
## _on_gift_claimed() below reads this node's still-valid position/state and
## hands the actual "pop" animation off to a brand-new, independently-lived
## node (spawn_claim_pop()) rather than trying to animate itself.
@export var gift_config: GiftConfig = preload("res://config/gift_config.tres")

## True once this crate's own claim has been handled (its _on_gift_claimed()
## has already fired for its own gift_id), so a redundant second delivery of
## the same signal (there should never be one) can't spawn two pop effects,
## and so _process()'s hint pulse stops touching a node that is about to be
## freed anyway.
var _claimed: bool = false
var _hint_time: float = 0.0


func _ready() -> void:
	_build()
	body_entered.connect(_on_body_entered)
	Events.gift_claimed.connect(_on_gift_claimed)


func _process(delta: float) -> void:
	if _claimed:
		return
	_update_hint(delta)


func _build() -> void:
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	shape_node.name = &"Collision"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = CRATE_SIZE
	shape_node.shape = box_shape
	add_child(shape_node)

	_mesh = MeshInstance3D.new()
	_mesh.name = &"Mesh"
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = CRATE_SIZE
	_mesh.mesh = box_mesh
	_material = StandardMaterial3D.new()
	_material.albedo_color = UNCLAIMED_COLOR
	_mesh.material_override = _material
	add_child(_mesh)


## Tints the crate the claiming slot's color. Nothing in M4 P1 calls this yet
## (a claimed crate is freed the same tick it is claimed -- see
## MatchGifts._claim_gift()), but it is the documented seam a later package
## can use if a claimed-but-not-yet-despawned state is ever wanted.
func set_owner_tint(slot_id: int, color: Color) -> void:
	owner_slot = slot_id
	if _material != null:
		_material.albedo_color = color


## Documented no-op (see class doc): a later milestone may want a thrown
## special or an ordinary block striking a crate to do something. Nothing in
## M4 P1 needs it.
func _on_body_entered(_body: Node3D) -> void:
	pass


# --- Claim feedback (Bontago-d04) --------------------------------------------

## Every live GiftCrate listens for its own claim. MatchGifts._claim_gift()
## (host) and MatchNet.gd's EVENT_GIFT_CLAIMED dispatch (client) both call
## _free_crate_visual() — which queue_free()s the matching node — strictly
## before they emit Events.gift_claimed (see MatchGifts._claim_gift()'s own
## call order and net/MatchNet.gd's _authority().apply_replicated_gift_claimed()
## / Events.gift_claimed.emit() pair), so this handler still reads a fully
## valid node: queue_free() only defers the actual deletion, it doesn't
## invalidate the node the same frame it's called.
## Bontago-keo.17 (owner decision "b"): `slot_id` is now the RESOLVED
## RECIPIENT -- the one teammate whose home circle is nearest the crate
## (autoload/match/MatchGifts.gd's _resolve_recipient_slot()), not a team id.
func _on_gift_claimed(claimed_gift_id: int, slot_id: int, _special_id: StringName) -> void:
	if claimed_gift_id != gift_id or _claimed:
		return
	_claimed = true
	var parent: Node = get_parent()
	if parent == null or not (parent is Node3D):
		return
	spawn_claim_pop(parent as Node3D, global_position, _claim_color(slot_id), gift_config)


## HUD._color_for_slot()'s own fallback shape: a real PlayerSlot's own colour
## when Match can name one, otherwise MatchConfig.player_colors[slot_id], and
## white if neither resolves. Kept as its own copy rather than a shared
## helper -- ui/HUD.gd is a different node with its own match_provider test
## seam, and this is three lines, not worth a new coupling between the two
## owned files for.
##
## Bontago-keo.17 (owner decision "b"): `slot_id` is now the actual resolved
## recipient's own slot (MatchGifts._resolve_recipient_slot()), so
## Match.slot(slot_id) is literally that player's own colour -- no team-proxy
## trick needed anymore (an earlier revision of this comment explained why a
## team id safely stood in for a teammate's colour; that no longer applies
## now that the payload is a real slot).
func _claim_color(slot_id: int) -> Color:
	var slot: PlayerSlot = Match.slot(slot_id)
	if slot != null:
		return slot.color
	var palette: MatchConfig = load("res://config/match_defaults.tres") as MatchConfig
	if palette != null and slot_id >= 0 and slot_id < palette.player_colors.size():
		return palette.player_colors[slot_id]
	return Color.WHITE


## The actual "pop": a brand-new box mesh (not a continuation of the claimed
## GiftCrate instance -- see _on_gift_claimed()'s own doc comment for why),
## tinted the claiming slot's colour, growing from its real size up to
## GiftConfig.claim_pop_scale_factor and back down to nothing before freeing
## itself. Static so it needs no `self` from an already-claimed (and about to
## be deleted) crate instance beyond the position/colour it already read.
static func spawn_claim_pop(parent: Node3D, world_position: Vector3, color: Color, config: GiftConfig) -> void:
	var pop: Node3D = Node3D.new()
	pop.name = &"GiftClaimPop"
	parent.add_child(pop)
	pop.global_position = world_position

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = CRATE_SIZE
	mesh_instance.mesh = box_mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.0
	mesh_instance.material_override = material
	pop.add_child(mesh_instance)

	var tween: Tween = pop.create_tween()
	tween.tween_property(pop, ^"scale", Vector3.ONE * config.claim_pop_scale_factor, config.claim_pop_grow_duration_s)
	tween.tween_property(pop, ^"scale", Vector3.ZERO, config.claim_pop_shrink_duration_s)
	tween.tween_callback(pop.queue_free)


# --- Not-claimable hint (Bontago-d04) ----------------------------------------

## Pulses this crate's own tint while the local player's held ghost hovers
## near it AND it sits outside that player's own territory -- the case that
## used to read as "nothing happened" (spec 2.6's claim rule is
## territory-only [ORIGINAL]; walking a held block over a crate elsewhere
## does nothing by design). Resets to the flat UNCLAIMED_COLOR the moment
## either condition stops holding, so the hint never lingers on a crate the
## ghost has moved away from or that just became claimable.
func _update_hint(delta: float) -> void:
	if not _is_hint_hovering():
		if _hint_time > 0.0:
			_hint_time = 0.0
			_material.albedo_color = UNCLAIMED_COLOR
		return
	_hint_time += delta
	var t: float = 0.5 + 0.5 * sin(_hint_time * gift_config.hint_pulse_speed)
	_material.albedo_color = UNCLAIMED_COLOR.lerp(gift_config.hint_pulse_color, t)


func _is_hint_hovering() -> bool:
	# Cheap early-out before the per-frame scene-tree group lookup: with no
	# local human slot (e.g. an all-bot headless host) there is nobody to hint.
	if _local_watch_slot() < 0:
		return false
	var ghost: GhostPreview = get_tree().get_first_node_in_group(GhostPreview.LOCAL_HELD_GROUP) as GhostPreview
	if ghost == null or ghost.get_shape() == null:
		return false
	var field: Field = Match.field()
	if field == null:
		return false
	var ghost_local: Vector2 = field.disk_local_from_world(ghost.global_position)
	var crate_local: Vector2 = field.disk_local_from_world(global_position)
	if ghost_local.distance_to(crate_local) > gift_config.hint_pulse_radius_m:
		return false
	return not _crate_in_local_territory(crate_local)


## DECISION (game/GiftCrate.gd, Bontago-d04): "the local player's own slot",
## the same distinction ui/HUD.gd's own _hot_seat_active()/_active_slot pair
## makes -- in hot-seat exactly one human drives whichever slot's turn it is
## (Match.active_slot()); outside hot-seat each running instance drives
## exactly one slot of its own (Net.is_local_slot()). Recomputed here rather
## than reused from HUD.gd: this file owns no reference to that HUD instance
## (or any node path to one), and both branches are two public, already
## existing calls each.
func _local_watch_slot() -> int:
	if Match.config != null and Match.config.hot_seat:
		return Match.active_slot()
	for slot_id: int in range(Match.slot_count()):
		if Net.is_local_slot(slot_id):
			return slot_id
	return -1


## Bontago-keo.17 (A1 review fix, same bug class as _on_gift_claimed()):
## TerritoryRaster.team_at() returns a TEAM id (territory is per-team), so a
## local slot has to be resolved to its own team before the comparison --
## under TeamMode.OFF, MatchConfig.team_of_slot() is the identity, so this is
## a no-op there and only changes behaviour for a real TEAMS_2+ match.
func _crate_in_local_territory(crate_local: Vector2) -> bool:
	var raster: TerritoryRaster = Match.raster()
	var grid: CellGrid = Match.cell_grid()
	if raster == null or grid == null:
		return false
	var cell: Vector2i = grid.world_to_cell(crate_local)
	if not grid.in_bounds(cell.x, cell.y):
		return false
	var watch_slot: int = _local_watch_slot()
	if watch_slot < 0:
		return false
	var watch_team: int = watch_slot
	if Match.config != null:
		watch_team = Match.config.team_of_slot(watch_slot)
	return raster.team_at(cell.x, cell.y) == watch_team
