# Glue fusion design contract (Bontago-1pi.85.74)

Status: planning contract, written against main `81ba673b`. Bead: `Bontago-1pi.85.74` (parent
`Bontago-1pi.85`). Beads owns status; this file is the design only.

Owner decisions this plan implements (2026-10-12): glued blocks fuse into **one rigid body** with merged
collision shapes instead of `GlueJoint` bonds; **blasts do not split a fused body** (supersedes the "glued
pair breaks under a two metre blast" behaviour); bonds must hold under normal play at base gravity 1.25x
(1pi.179). Existing answered decisions kept: five charges (Bontago-sen.3), the charge is spent on an
accepted placement and fuses on actual contact with the disc or any block regardless of owner (SPEC
section 2.6 Glue paragraph, lines 291 and 303), glue is inelastic (1pi.85.65, `GlueDrops._absorb_impact`),
Jumping Bean never takes a charge (1pi.85.70), gifts are never destroyed by territory holes (1pi.85.73).

## 1. Verified starting point

- Checkout `M:/Bontago` on `main` at `81ba673b`, worktree dirty only with unrelated files (orchestrator
  agent profile, `addons/godot_ai`, art mockups); nothing glue-related is uncommitted.
- Existing glue code: `game/specials/GlueDrops.gd` (71 lines; per-charged-block contact monitor, `try_bond`
  builds a `Generic6DOFJoint3D` under a `GlueJoint`), `game/specials/GlueJoint.gd` (155 lines; break rules:
  separation / relative speed / one-tick velocity shock / `release_bonds_for`), `config/GlueDropTuning.gd`
  (`break_force`, `break_separation_m`, `break_speed_mps`, `break_shock_mps`, `max_contacts_reported`,
  `absorb_impact`), `game/specials/GlueEffect.gd` (charge grant only; unaffected).
- Charge plumbing is body-agnostic and **stays unchanged**: `MatchGifts.grant_glue_drops/consume_glue_drop`
  (`autoload/match/MatchGifts.gd:205, 388`), `MatchPlacement` spawn hook (`autoload/match/MatchPlacement.gd:
  358-371`: `GlueDrops.new()` added to the spawned block, `Events.glue_drop_charged`), charge replication
  (`EVENT_GLUE_CHARGES`).
- Replication today is block-level coat only: `Events.glue_bond_changed` (`autoload/Events.gd:253`) ->
  `MatchNet._on_glue_bond_changed` (`net/MatchNet.gd:1718`, per-block bond count, `EVENT_BLOCK_GLUED`
  `[net_id, glued]`), late-join replay `net/MatchNet.gd:2214-2221`. The bond itself is never on the wire:
  clients see ordinary frozen-kinematic blocks moved by snapshots (`net/SnapshotSync.gd:462 freeze_body`).

## 2. Answers to the seven design questions

### Q1. Disc fusion: how a glued-to-disc block unfreezes

Today the bond is a joint between the block and the `Field` AnimatableBody3D (`GlueDrops.try_bond`, lines
29-45 accept `Field`); the block therefore rides the disc through tilt, shake and any pose change. Fusion
cannot add collision shapes to the Field (one ConcavePolygonShape3D rebuilt from hole cells), so:

- A fused group holding a **disc anchor** is a kinematic carrier: `freeze=true, freeze_mode=KINEMATIC`
  (NOT `request_freeze_static`; STATIC bodies do not ride a moving disc, see the Bontago-sen.11 comment at
  `game/StableBlockManager.gd:130-136`) and the carrier's pose is recomputed every tick as
  `field.global_transform * anchor_local`. This is behaviour-identical to the joint (rides tilt / shake /
  Propeller / Earthquake) and costs nothing at rest.
- **No new unfreeze rule is needed.** The group loses its disc anchor exactly when the anchored member is
  removed, and members are removed by the rules that already exist: a hole under the footprint
  (`HoleDissolver.touches_hole`, `game/HoleDissolver.gd:206`), the Black hole, the kill plane / sudden-death
  rim (`Field.remove_fallen_block`, `game/Field.gd:1319`). When the last anchored member goes, the carrier
  switches to dynamic (`freeze=false`, `wake()`), keeping its velocity (the disc's), and the remainder
  falls or topples under normal physics.
- Tilt: the disc tilt-from-weight (`BlockRegistry.settled_torque_samples`, `game/BlockRegistry.gd:546`)
  keeps counting every member's mass because followers retain their own `mass` (section 3).
- StableBlockManager skips disc-anchored carriers (kinematic, not sleeping, nothing to save). Documented as
  `# DECISION`.
- Note for the owner: the bead text says the block "becomes static/frozen"; the plan implements "rides the
  disc rigidly" because a literal world-static block would clip through a tilting disc (the failure the
  sen.11 fix removed). Player-visible outcome is the same as today's joint, so this is a DECISION, not a
  question.

### Q2. Block identity: per-shape mapping vs multi-block bodies (decision: followers + carrier)

Everything identity-related keys on a `Block` node: `net_id` (`BlockRegistry._on_block_placed`, line 181),
owner / recolor / Paintball (`BlockRegistry._set_owner`, 461), territory circle per entry (`influence_circles`,
335), stats on `block_removed`, despawn replication by net_id (`MatchNet._on_block_removed`, 1768), snapshots
(`SnapshotSync._record`, 759), hole dissolve (`HoleDissolver` keyed by Block), bots. Rewriting all of that for
multi-block bodies is the large, risky route. Chosen design (section 3): **the member Blocks stay as
identity "followers"; a new `FusedBody` carrier owns the physics.**

### Q3. Hole dissolve / kill plane on a fused body with one doomed block

- **Hole**: remove **only the touching member** (its shapes leave the carrier, mass / COM / inertia are
  recomputed, `Events.block_removed(follower, kill_plane)` fires for that follower alone). This matches the
  spec rule "a block whose footprint touches an applied hole cell dissolves ... blocks stacked above then land
  on the void and dissolve too" (SPEC line 140; holes are a visual void, the disc collision stays solid).
  The remainder stays rigid; if it still has members over the hole it peels one layer at a time, exactly as
  an unglued stack does. Old joint behaviour (doomed block removed, partner freed) is the same shape.
  `HoleDissolver` footprint must read the member's own shapes (section 6, WP3), and `_wake_supported`
  (`game/HoleDissolver.gd:367`) already wakes the carrier because the query hits its remaining shapes.
- **Kill plane**: the carrier enters the Area3D as one body (`Field._on_kill_plane_body_entered`,
  `game/Field.gd:1283-1300`); `remove_fallen_block(carrier)` expands to every member (emit
  `block_removed` per follower, then free carrier). Stats count each lost block.
- **Dissolve fade**: the doomed member's shapes stay (as today the whole block stays) for
  `dissolve_delay_s`; the removal happens in `HoleDissolver._finish`.
- **Black hole capture** (`BlackHoleField._capture` -> `HoleDissolver.request_dissolve`, `game/HoleDissolver.
  gd:150`): called with a carrier it dissolves the **whole group** (a rigid body sucked into the core).
  See OPEN QUESTION OQ6.
- When a removal leaves one member, `FusedBody` collapses: the survivor gets its shapes back and becomes a
  plain dynamic Block again (coat off via the existing glued=false event); carrier freed.

### Q4. Mass, centre of mass, inertia; interpolation; replication

- Carrier `mass = sum(member masses)` (`cube_mass * cubes` already on each follower). Leave
  `center_of_mass_mode = AUTO` so Jolt derives COM and inertia from the merged shapes (this is what every
  Block does today; `BlockRegistry._local_center_of_mass`, line 610, reads `center_of_mass`). Recomputed
  automatically on every shape add / remove; `FusedBody` re-sets `mass` after each membership change.
- Followers keep their own `mass` (needed by `settled_torque_samples`, line 556, and Rain/Storm force maths)
  and get `center_of_mass_mode = CUSTOM` with the COM captured **before** their shapes leave (otherwise
  the territory circle centre, `_local_center_of_mass`, would read zero).
- Interpolation: followers are frozen-kinematic Blocks written in `_physics_process` from the carrier's
  post-step transform (`carrier.global_transform * offset`), so Godot physics interpolation smooths them like
  any node; the carrier itself has no mesh.
- Replication (host-only physics): **Phase 1 (this plan): no new wire format.** Followers have real
  `net_id`s and are already sent by `SnapshotSync._select_bodies` (`net/SnapshotSync.gd:731`). Clients render
  them as ordinary blocks and see one rigid group because all members are written from one carrier.
  Relative jitter between members is bounded by quantisation: 2-3 mm position, 0.0074 degrees rotation
  (`core/net/Quantize.gd` header). Bandwidth for a moving fused group equals today's per-block cost (what the
  joint version paid). Only change: `SnapshotSync` must read `net_sleeping()` (virtual on `BlockBody`) so a
  settled group's followers are treated as sleepers (keyframe rotation, not every-tick resend), because a
  frozen-kinematic follower's own `sleeping` is not meaningful. **Phase 2 (optional, only if the ENet test shows
  visible seams or bandwidth pain): group records** `{group_net_id, transform}` plus a one-shot `fuse` event
  carrying `[member net_id, local offset]` so clients derive members; not planned now because it needs a wire
  version bump and gains little at 15 bytes per body.
- Late join: no change in mechanism. A joiner receives every follower through the normal spawn replay and
  snapshot, plus the existing coat replay (`MatchNet.gd:2214-2221`, rebased on the fused-id set).
  Clients never create carriers.

### Q5. Performance vs joints (expectation, to be proven by the bench in section 8)

- Fewer Jolt bodies per glued group in the contact graph (N dynamic bodies + N-1 six-DOF joints -> 1 dynamic
  body with a StaticCompound of 4N boxes + N kinematic shape-less followers). No constraint rows to solve, no
  joint-limited sleeping island chatter (the 1pi.11.24 observation that islands never sleep applies less).
- Per-tick script cost: before = N `Block._batch_tick` + N `GlueJoint._physics_process`; after = 1 batch tick
  on the carrier + N transform writes while the carrier is awake and none when it sleeps. Net: neutral to
  better while moving, clearly better at rest and for stable-block freezing (one body to freeze).
- One-off cost at fuse / member removal: reparent shapes and one Jolt compound rebuild (O(shape count)).
  Large merged groups (a charged block touching two towers) are the worst case; `max_fused_members` safety
  cap (OQ5).
- Acceptance is a measured comparison, not a promise: `tests/bench/bench_glue_drops.gd` on an idle machine,
  joint baseline from `main@81ba673b` versus fusion; target: no regression of `avg_physics_step_ms` for the
  existing 100-block / 3-charged scene, and a new 6x6-cube glued tower scene at least equal.

### Q6. Bots' statics / plan assumptions

- `core/ai/BotStatics.gd` and `BotWorldView` read no body state: they consume `BlockRegistry.influence_circles`
  (per member circles, preserved) and the placement raycasts. No glue-specific logic exists in
  `BotSpecialPlanner` beyond target choice for `&"freeze", &"glue"` (line 198), which is rule-level and
  unchanged.
- One real touch point: `BotController._is_own_block(collider, team_id)` (`game/BotController.gd:698-701`)
  casts the ray hit to `Block` and reads `owner_slot`. A ray hitting fused geometry returns the **carrier**.
  Fix: `FusedBody.owner_slot_at(world_point)` (nearest member shape) used when the collider is a `FusedBody`.
  Without it a mixed group would read as "not own". Everything else (support-height raycasts at
  `BotController.gd:~680`) is geometry-only and works on carriers.
- Bot strategy value of Glue is unchanged (hold the tower); bots may now rely on it holding. No planner change.

### Q7. Migration of GlueJoint / GlueDrops and tests

See section 7 (file list) and section 8 (tests). In short: `GlueJoint.gd` is deleted, `GlueDrops` keeps its
name, contact monitor and `try_bond` seam but calls `GlueFusion`; `Events.glue_bond_changed` is replaced by
`Events.blocks_fused` / `Events.fused_member_released`; break tuning fields removed.

## 3. Data model: comparison and choice

### Option A (REJECTED): primary Block absorbs the others, secondary Blocks freed

The first (or oldest) Block keeps the body and gets the others' CollisionShape3D and MeshInstance3D children;
secondary Blocks are removed and survive only as records in the primary.
- Pros: fewest nodes; matches the literal wording "join the other block's body".
- Cons: every identity consumer must learn multi-member bodies at once: registry entries (territory circle per
  member, owner per member), net_id per member (despawn of one member needs a "partial despawn" wire
  message, clients must also fuse), HoleDissolver / Paintball / stats per member, snapshot replication needs
  group records and per-member offsets (new wire format, spawn-replay of fusion for late join), carrier
  handoff when the primary member is the doomed one. High blast radius across registry, net, hole, stats,
  bots, and every one of ~80 `as Block` sites.

### Option B (CHOSEN): `FusedBody` carrier + member Blocks as kinematic followers

- `FusedBody extends Block` (class_name `FusedBody`, no scene, no `net_id`, never emitted as
  `block_placed`). It is the only Jolt-dynamic body of the group and owns every member's `CollisionShape3D`
  (reparented, local transform preserved) and `mass`. It sits in the same `blocks_parent`, so match reset
  (`Match` clears `blocks_parent`) and teardown free it with its followers. Because it extends `Block` it
  inherits tuning, rebound damping, impact audio, awake set, `request_freeze_static`, `wake_for_impulse`,
  `kick`, and every physics-query based special (Bomb / Rocket / Volcano blast
  `ExplosionFx.blast`, Magnet `MagnetEffect`, Black hole `RadialPull`, Anvil / Propeller / Earthquake tilt):
  those find the **body that owns the shapes**, i.e. the carrier, and `SpecialPhysics.wake_and_impulse`
  (`game/specials/SpecialPhysics.gd:92`) works unchanged.
- Member Blocks remain full identities: `net_id`, `owner_slot`, `shape_id`, `cube_count`, meshes, coat, colour,
  registry entry, territory circle, despawn by net_id, snapshot record. They become **followers**:
  `freeze=true, freeze_mode=KINEMATIC`, `collision_layer = collision_mask = 0`, no shapes, `center_of_mass_mode
  CUSTOM`, `mass` retained, pose written each tick as `carrier.global_transform * member_offset`
  (`FusedBody.sync_followers()`, run from `FusedBody._batch_tick` after `super`, and from `_physics_process`
  for a disc-anchored carrier); `linear_velocity` / `angular_velocity` mirrored from the carrier so the
  registry settle test and `HoleDissolver.touches_hole` (`block.linear_velocity`) keep working.
- Meshes are **not merged**: members can have different owners and therefore different per-owner
  `ShaderMaterial`s (`BlockFactory._material_for_color`), and a block's honey coat / territory glow / recolor
  are per member. The owner wording "mesh joins" is satisfied visually (the members move as one) while
  keeping per-owner colour. Seam outlines: OQ4.
- Why a separate carrier instead of electing a member as the body: merging two fused groups, removing the
  member that holds the body, and disc-anchoring are uniform operations on the carrier; no handoff cases.
- Cost: `BlockBody` gets three virtuals (`fused_carrier()`, `net_sleeping()`, `is_fused_member()`), `Block` gets
  forwarding for the freeze / wake API when it is a follower, and the registry distinguishes physics bodies
  from identity blocks (section 4).

## 4. Treatment per system (file:line evidence)

| System | Behaviour with a fused body |
|---|---|
| Territory / influence | Unchanged per member. `BlockRegistry.influence_circles` (335) iterates `_entries` = followers; circle centre = follower COM, top = follower mesh AABB (`_top_height_local`, 625), owner = follower owner. Mixed-owner groups keep each member's own circle. A member is `is_settled` when its **carrier** is settled (see below). |
| Settled rule | `BlockRegistry._physics_process` (228) / `_step_entry` (282) tests `block.linear_velocity`. Followers are skipped there; the carrier is stepped with the same arithmetic (new `_carriers` dict) and writes `is_settled` / `settled_time` into each member entry, emitting `block_settled` per member. `all_settled()` (526) therefore stays correct. |
| Ownership / Paintball | `_set_owner` (461) works per follower (net_id > 0). `PaintballEffect.detonate` (`game/specials/PaintballEffect.gd:~100`) casts the query hit to `Block`; for a `FusedBody` hit it converts `members_in_sphere(center, splash_radius)` (per-member distance, DECISION). Carrier `owner_slot` = the common slot when uniform else `-1` (mixed), so Magnet's `owner_slot !=` filter attracts mixed groups and ignores purely own groups. |
| Scoring / stats | Per follower `block_removed` (stats `blocks_lost`, despawn replication, effects). `Events.block_removed` is never emitted for a carrier. |
| Hole dissolve of one member | Q3. `HoleDissolver._footprint` (256) and `_collision_signature` read `block.get_children()` shapes; for a follower they must read `FusedBody.member_shapes(block)`. `touches_hole` stays per member (candidates list = `moving` of followers). `gift_id != &""` exemption (`touches_hole`, line ~213) is untouched; gifts do not fuse (OQ1). |
| Kill plane | Q3. `Field.remove_fallen_block` (1319) expands a `FusedBody`. |
| Freeze (special) | `FreezeEffect.freeze_block(target)` (84) writes `target.linear_velocity` and `request_freeze_static(REASON)`. On a follower, `Block.request_freeze_static / release_freeze_static / is_freeze_static / wake / wake_for_impulse` forward to the carrier (the freeze reason set is on the carrier). Known limitation recorded: two Freeze holds on one group share one reason key, so the first release frees both (same reason-set semantics as today). `FreezeEffect.release_hold` in `start_dissolve` (HoleDissolver 165) is per member and harmless. A group freeze freezes the whole rigid body (inevitable). |
| Magnet / Black hole pull / Bomb / Rocket / Volcano impulses | Physics queries return the carrier. `ExplosionFx.blast` (`game/specials/fx/ExplosionFx.gd:21-43`) applies `delta_v * body.mass`, i.e. the **same delta-v as a single block**, measured to `body.global_position` = carrier origin. Blasts do not split (owner decision) and push the whole body. Feel of equal delta-v on a heavy group: OQ2. Carrier origin is placed at the first member's origin (stable), not the COM. |
| Rocket / Propeller / Bomb / Bean / Anvil / Cat / Paintball flights (gift behaviours) | **Gift bodies are never fused** and a charge is not spent on them (extends the 1pi.85.70 bean rule; OQ1). These behaviours write the gift block's own velocity / mass directly (`RocketEffect.gd:189`, `AnvilEffect.gd:47`, `FreezeEffect.gd:87`, `CatController.gd`) and cannot be forwarded cheaply. |
| Tilt (release tilt) | `Block._apply_release_tilt` (`game/Block.gd:445`) is a first-integration one-shot on the falling charged block, before fusion. The carrier is created with `_release_checked = true`. Field tilt: see Q1. |
| StableBlockManager | `_scan` (167) and `check_field_motion` (130) iterate `registry.all_blocks()` and call `request_freeze_static` / read `sleeping`. Switch them to a new `BlockRegistry.physics_bodies()` (unfused blocks + carriers, no followers) so a settled carrier freezes as one body (spec 3.5 rules unchanged: asleep 20 s, rest epsilon, settle-awake window). Disc-anchored carriers skipped. Stale ids are already pruned (lines 224-233). |
| Weather (Wind / Storm / Breeze / Rain / Snow) | `WindEffect._owns_physics` (`autoload/match/WindEffect.gd:67-73`), `StormEffect` (doc line 24) and `BreezeEffect` (line 26) skip blocks with a `GlueJoint` child so glued pairs are immune to wind. Preserve that: skip `FusedBody` (and followers). They iterate `all_blocks()` (`WindEffect.gd:92`, Rain 159, Snow 296): followers are skipped anyway because they have no physics, but the carrier must not receive force. See OQ3. |
| Kill of the gift/bean | `JumpingBeanEffect.gd:195` `GlueJoint.release_bonds_for` call is removed (beans never fuse). |
| Late join / reconnect | No mechanism change (Q4). |
| Match reset / teardown | Carrier lives under `blocks_parent`; `MatchFingerprint` (tests/unit/support) must be checked that it does not count carriers as blocks (it iterates registry entries = followers, so expected unaffected). |

## 5. Algorithm sketch (host only)

`GlueFusion.fuse(charged: Block, target: PhysicsBody3D, tuning: GlueDropTuning) -> FusedBody`
(called from `GlueDrops.try_bond`, unchanged guards: target is `Block` or `Field`, not self, not already in the
same group, no `gift_id`):
1. Resolve groups: `ga = charged.fused_carrier()`, `gb = target` as Block's carrier. Same carrier -> no-op.
2. Pick/create the carrier: the larger existing group, else a new `FusedBody` at the **partner's** pose (so
   the settled partner does not jump), velocity = partner velocity, angular = 0 when `tuning.absorb_impact`
   (reproduces `GlueDrops._absorb_impact` lines 61-71).
3. For each unfused block to absorb: record `offset` and COM, move every direct-child `CollisionShape3D` to the
   carrier with `reparent(carrier, false)` and re-set its `transform` from the captured world transform
   (single Jolt rebuild after the batch), freeze the block as a follower (layers 0, kinematic freeze,
   CUSTOM COM), `carrier.members.append(block)`. For a merge, move the smaller group's members the same way
   and free its carrier. Union freeze reasons except `FREEZE_REASON_STABLE`; copy `anchored_members`.
4. If `target is Field`: add `charged` to `anchored_members`, set `anchor_local = field.global_transform.
   affine_inverse() * carrier.global_transform`, carrier -> kinematic mode.
5. `carrier.mass = sum`, `wake()`, emit `Events.blocks_fused(carrier, newly_fused_members)` (MatchNet marks the
   coat on each new member).
6. `GlueDrops` frees itself afterwards (its block has no shapes left; no contact monitor needed).

`FusedBody.remove_member(member, reason)`: remove its shapes, drop from `members` / `anchored_members`, recompute
mass, `Events.block_removed(member, reason)` + `member.queue_free()`; 1 member left -> collapse (give shapes
back, un-follow, free carrier, emit `fused_member_released`); 0 -> free carrier; anchored set empty and
disc-anchored -> release kinematic mode.

Tick order: followers must be written after the physics sync and before `BlockRegistry._physics_process` /
`SnapshotSync.host_tick`. `FusedBody._batch_tick` (runs in `BlockStepBatch`, first on `physics_frame`,
`game/BlockStepBatch.gd` header) is the hook for a dynamic carrier; a disc-anchored carrier uses its own
`_physics_process` with `process_physics_priority` above `Field` so it reads the disc pose of the same tick.

Spikes the first worker must prove before building on them (record results in the Bead): (a) a frozen
KINEMATIC `RigidBody3D` with zero shapes, layers 0, moved by script, produces no engine error/warning in Jolt 4.7.2
(fallback: one disabled tiny shape); (b) assigning `linear_velocity` on such a follower reads back; if not,
add `BlockBody.sim_linear_velocity()` and switch the four read sites (registry `_step_entry`/
`count_fast_blocks_by_owner` 502, `HoleDissolver.touches_hole`, `StableBlockManager._fast_positions`);
(c) reparenting `CollisionShape3D`s of a live body inside `_physics_process` is safe; (d) a kinematic carrier
written from `_physics_process` carries dynamic blocks resting on it (the existing disc does).

## 6. Work packages (file ownership; dependency order)

Order: **WP0 (stubs) -> WP1 (core) -> WP2 || WP3 || WP4 (parallel, disjoint) -> WP5 (net) -> WP6 (cleanup, docs,
bench)**. WP0 and WP1 serialize in one checkout; WP2-WP4 may use separate worktrees only after WP1 is
committed (a new worktree cannot see uncommitted contracts). Each is <= ~10 files.

### WP0 - interface stubs (Sonnet, ~20 min). Must land first.
Owns: `game/FusedBody.gd` (+`.uid`), `game/world/BlockBody.gd`, `autoload/Events.gd`, `config/GlueDropTuning.gd`
(+ keep tres in step), `tests/unit/test_fused_body_stub.gd`.
Stubs (typed, bodies are no-ops / return defaults; no behaviour):
```gdscript
# game/world/BlockBody.gd  (virtual defaults; Block/FusedBody override)
func fused_carrier() -> RigidBody3D: return null
func is_fused_member() -> bool: return false
func net_sleeping() -> bool: return sleeping

# autoload/Events.gd
## Host-only: `members` (Array[Block], newly fused) joined `carrier` (FusedBody).
signal blocks_fused(carrier: Node, members: Array)
## Host-only: a member left its fused body (dissolved, collapsed to a single block, or the body ended).
signal fused_member_released(member: Node)

# game/FusedBody.gd
class_name FusedBody
extends Block
var members: Array[Block] = []
var anchored_members: Dictionary = {}   # instance id (int) -> true; non-empty = disc-anchored
func is_disc_anchored() -> bool: return false
func member_shapes(_member: Block) -> Array[CollisionShape3D]: return []
func members_in_sphere(_center: Vector3, _radius: float) -> Array[Block]: return []
func owner_slot_at(_world_point: Vector3) -> int: return -1
func sync_followers() -> void: pass
func remove_member(_member: Block, _reason: StringName) -> void: pass
func remove_all_members(_reason: StringName) -> void: pass

# config/GlueDropTuning.gd  (add; old break_* fields stay until WP6)
## Safety cap on cubes in one fused body; 0 = unlimited.  (OQ5)
@export_range(0, 512, 1) var max_fused_cubes: int = 0
```
Acceptance: project opens clean (`godot --headless --editor --path . --quit`), stub test loads classes.

### WP1 - FusedBody core + GlueFusion (Sonnet). Depends WP0.
Owns: `game/FusedBody.gd`, `game/GlueFusion.gd` (+uids), `game/Block.gd` (follower state + forwarding of
`request_freeze_static`, `release_freeze_static`, `is_freeze_static`, `wake`, `wake_for_impulse`, `kick`,
`mark_script_kick` to the carrier when a follower; override the three `BlockBody` virtuals),
`tests/unit/test_fused_body.gd`, `tests/unit/test_glue_fusion.gd`.
Delivers sections 3 and 5, incl. merge, collapse, disc anchor, spikes (a)-(d) as tests.
Acceptance (unit): two blocks fuse -> one dynamic body, equal mass, members keep net_id / owner / meshes; shape
count conserved; COM equals mass-weighted; push the carrier -> followers' world poses keep their rigid offsets
within 1e-4; remove middle member -> mass drops, others stay; collapse to one restores a normal dynamic Block;
merge of two groups; disc-anchored carrier follows a tilted Field and stays after a 2 s tilt cycle; anchor member
removed -> group falls; 8 m/s impact and a 2 m blast do **not** split it.

### WP2 - GlueDrops wiring + joint removal (Sonnet). Depends WP1.
Owns: `game/specials/GlueDrops.gd`, `game/specials/GlueJoint.gd` (delete, with .uid), `game/specials/
JumpingBeanEffect.gd` (remove line 195 call), `tests/unit/test_glue_drops.gd`, `tests/unit/test_glue_effect.gd`,
`tests/unit/test_glue_sticks_overhang.gd`. (`MatchPlacement.gd` needs no change except the OQ1 gift rule at
lines 358-371: if the owner approves, add `and gift_id == &""` there; list that file as owned only then.)
`try_bond(other) -> bool` seam retained; `_has_bond` becomes "same carrier".

### WP3 - registry / stable / holes / kill plane (Sonnet). Depends WP1.
Owns: `game/BlockRegistry.gd` (`_carriers`, carrier-driven settle, `physics_bodies()`), `game/
StableBlockManager.gd`, `game/HoleDissolver.gd` (member footprints, `request_dissolve` on carrier, `_finish`
via `remove_member`), `game/Field.gd` (only `remove_fallen_block`), `tests/unit/test_block_registry.gd`,
`tests/unit/test_stable_block_manager.gd`, `tests/unit/test_hole_dissolver.gd`, `tests/unit/
test_fused_territory.gd` (new). No overlap with WP2/WP4.
Acceptance: per-member circles identical to unfused equivalents; settled flags propagate; hole under one
member removes only it, rest stays and its column wakes; kill plane removes all members with one
`block_removed` each; stable freeze freezes the carrier once and wind/impulse release works; disc-anchored carrier
never freeze-statics.

### WP4 - specials / weather / bots routing (Sonnet). Depends WP1.
Owns: `autoload/match/WindEffect.gd`, `autoload/match/StormEffect.gd`, `autoload/match/BreezeEffect.gd`
(skip `FusedBody`), `game/specials/PaintballEffect.gd` (per-member conversion), `game/BotController.gd`
(`_is_own_block` via `owner_slot_at`), `tests/unit/test_weather_storm.gd`, `tests/unit/
test_paintball_effect*.gd` (the existing file, whichever matches), `tests/unit/test_bot_controller*.gd` if
present. Acceptance: wind/storm leave a fused body untouched; Paintball converts only members inside the
splash; bot ray over a mixed group reads the member's owner.

### WP5 - netcode (netcode worker, Sonnet). Depends WP1, WP2.
Owns: `net/MatchNet.gd` (replace `_glue_bond_counts` with a fused-id set fed by `Events.blocks_fused` /
`fused_member_released` / `block_removed`; keep `EVENT_BLOCK_GLUED` semantics and the late-join replay),
`net/SnapshotSync.gd` (`_select_bodies`, `_record` and client-tick sleeping use `net_sleeping()`),
`tests/unit/test_glue_coat_replication.gd`, `tests/unit/test_match_net.gd` (glue block only),
`tests/unit/test_late_join.gd` (glue block only), `tests/bench/glue_fall_enet.gd` + `.tscn`,
`tools/run_glue_fall_enet.ps1` (extend, or add `tests/bench/glue_fuse_enet.gd`).
Acceptance: ENet host+client: host drops charged blocks onto a base; client sees both coated, members within
quantisation of rigid offsets while moving (max relative error < 1 cm) and at rest (< 5 mm); a late joiner
sees the same group and coat; hole dissolve of one member despawns only it on the client; kill-plane
despawns all members; simulated 100 ms lag leaves no stray body.

### WP6 - cleanup, SPEC, bench (Haiku or Sonnet). Depends WP2-WP5.
Owns: `autoload/Events.gd` (remove `glue_bond_changed`), `config/GlueDropTuning.gd` + `config/
glue_drop_tuning.tres` (remove `break_*`), `docs/SPEC.md` (gifts-table Glue row line 291 and paragraph 303:
record the owner decisions below; drop "breakable"), `tests/bench/bench_glue_drops.gd` + `.tscn`,
`tests/unit/test_hole_*` untouched. Idle-machine physics bench (below). Verify `grep -rn GlueJoint` is empty.

## 7. Migration list

- Delete: `game/specials/GlueJoint.gd` (+.uid). Remove: `Events.glue_bond_changed` (`autoload/Events.gd:251-253`),
  `MatchNet._on_glue_bond_changed` (`net/MatchNet.gd:1718`), `_glue_bond_counts` (160, 1021, 1771, 2215),
  `GlueDropTuning.break_*` fields and tres lines, `WindEffect/StormEffect/BreezeEffect` `GlueJoint` checks,
  `JumpingBeanEffect.gd:195`.
- Rewrite: `GlueDrops.gd` (keep `bind`, `try_bond` seam, contact monitor, `_absorb_impact` semantics).
- Keep unchanged: `GlueEffect.gd`, `MatchGifts` charge code, `EVENT_GLUE_CHARGES`, `HoneyCoat`, `BLOCK_GLUED` event.
- SPEC edits (WP6) record: fusion semantics (rigid, unbreakable, no joint); blasts do not split; disc anchor rides the
  disc; hole dissolve removes only the touching member; gifts do not fuse (if approved); mixed-owner groups keep
  per-member territory.

## 8. Tests

Changed existing tests (must be rewritten, not just re-run):
- `tests/unit/test_glue_drops.gd`: joint-specific cases replaced - `test_real_physics_contact_forms_a_bond`,
  `test_real_disc_contact_forms_a_bond`, `test_joint_constrains_a_falling_partner`,
  `test_bond_cleans_up_when_partner_despawns`, `test_bond_breaks_above_tuned_stress` (delete),
  `test_bonding_uses_contact_targets_and_deduplicates_both_directions`, `test_glued_pair_survives_tilt_cycle_...`,
  `test_glued_pair_breaks_under_a_two_metre_blast` (**inverted**: now survives), `test_old_glue_tuning_breaks_under_
  a_sideways_kick` (delete), `test_new_glue_tuning_survives_a_sideways_kick`, `test_glued_pair_survives_a_sustained_
  wind_gust`, `test_bean_bonded_to_disc_hops_after_release`, `test_bean_with_bond_stored_under_partner_is_freed`
  (rewrite: bean never fuses), `test_jumping_bean_drop_keeps_the_glue_charge` (keep). Charge tests (lines
  175-260) unchanged.
- `tests/unit/test_glue_effect.gd`: `test_glue_joint_breaks_above_threshold`, `test_glue_joint_keeps_below_threshold`
  deleted; charge tests unchanged.
- `tests/unit/test_glue_sticks_overhang.gd`: `_drop_off_side` counts `GlueJoint` children (line ~60); assert
  same-carrier membership instead.
- `tests/unit/test_glue_coat_replication.gd`: bond-count tests (`two_bonds_keep_the_coat...`, `destroyed_block_
  uncoats_its_partner`, `host_coats_glued_pair_and_removes_coat_when_bond_breaks`) rewritten on fuse / member
  removal; client-mirror and late-join tests keep.
- `tests/unit/test_weather_storm.gd` (GlueJoint skip), `tests/unit/test_stable_block_manager.gd`,
  `tests/unit/test_block_registry.gd` (new carrier cases), `tests/unit/test_hole_dissolver.gd`,
  `tests/unit/test_match_net.gd` / `test_late_join.gd` (glue replay), `tests/unit/support/FakeMatch.gd`,
  `FakeMatchContext.gd`, `MatchFingerprint.gd` (check only), `tests/bench/bench_glue_drops.gd/.tscn`,
  `tests/bench/glue_fall_enet.gd/.tscn`, `tools/run_glue_fall_enet.ps1`.
- New: `test_fused_body.gd`, `test_glue_fusion.gd`, `test_fused_territory.gd`.

Gates per package: targeted `powershell -NoProfile -File tools/run_gut.ps1 <names>`; project-open check; full
`python tools/full_gate.py` once per integrated batch by the orchestrator.
- ENet: WP5 scenario above (loopback, simulated lag 100 ms / 5 % loss, existing `Net` simulation).
- Bot smoke: `godot --headless --path . -- --headless-host --bots=8` for one match with glue gifts enabled
  (force a Glue gift at spawn via the sandbox/gift demo flow); no new errors, `tools/triage_log.py` clean.
- Idle-machine physics bench: `godot --headless --path . res://tests/bench/bench_glue_drops.tscn` on an otherwise idle
  machine, before (checkout `81ba673b`) and after, plus the 6x6 glued tower scene; record avg physics ms in the
  Bead; also `tests/bench` tower scene with `--baseline` flag as the unglued control.

## 9. Decisions recorded (minor, no owner input needed)

1. Followers + carrier model (section 3); carrier is a `Block` subclass but never registered or replicated.
2. Disc fusion = kinematic ride, not world-static (Q1).
3. Hole dissolve removes the touching member only; remainder collapses to a single Block at one member (Q3).
4. Mixed-owner groups keep per-member territory circles and ownership; carrier `owner_slot` is the common slot or -1.
5. Paintball converts per member inside the splash radius; Black hole capture removes the whole group.
6. Weather immunity of glued blocks is preserved (whole group).
7. Phase 1 replication adds no wire format; Phase 2 group records only on measured need.
8. Meshes are not merged (per-owner material); seams are OQ4.

## 10. OPEN QUESTIONS for the owner (player-facing; plan defaults shown)

- **OQ1 Gift bodies.** A gift block (Bomb, Rocket, Propeller, Anvil, Cat, Paintball, Bean...) can carry a Glue charge today
  and be bonded to, and its behaviour writes its own velocity. Default proposal: a gift body neither fuses nor
  spends a charge (like the Jumping Bean rule 1pi.85.70, which this would generalise); the charge stays for
  the next ordinary drop. Alternative: allow fusing and route every special through the carrier (large extra
  scope). Also needs your yes because the SPEC wording "fuses that block ... regardless of owner" does not mention gifts.
- **OQ2 Blast strength on a fused group.** The blast gives the same delta-v to any body regardless of mass
  (`ExplosionFx.blast`, "mass independent"). A 12-cube fused tower would fly as fast as one block. Default: leave
  as is (blasts push, never split). Alternative: scale delta-v down with the group's cube count.
- **OQ3 Weather.** Glued blocks are currently immune to wind / storm / breeze (only the bond owner). Default:
  whole fused group immune. Alternative: groups are pushed like any block.
- **OQ4 Look.** Members keep their own mesh, colour and outline, so seams between fused members remain visible
  (and mixed-owner groups stay two-coloured). Is that acceptable, or should adjacent faces get a seamless
  treatment later (separate art task)?
- **OQ5 Size cap.** A charged block touching two towers merges them into one body. Default: no cap
  (`max_fused_cubes = 0`). Suggest a cap (e.g. 48) only if the bench shows a cost.
- **OQ6 Black hole on a group.** Default: capture removes the whole group when its collision centre is inside the core.
  Alternative: remove only members whose own centre is inside.

None of these changes an [ORIGINAL] rule (Glue is NEW; holes follow the existing owner decision of 2026-10-01).

## 11. Risks

- Jolt behaviour of shape-less kinematic followers and velocity read-back (spikes a/b); fallback paths listed.
- Registry coupling: carriers must be stepped before followers' entries are read; WP3 owns this and its test is the gate.
- Many `as Block` sites (about 80) treat any `Block` hit as an identity block; only the ones that read owner / net_id from a
  *physics query result* matter (Paintball, bot `_is_own_block`, Magnet filter). Audit list in WP4; add a debug
  assertion in `FusedBody` that `net_id == -1`.
- Tick-order bug would show as followers lagging one tick (visible jitter on clients); covered by the ENet check.
- Large merged groups: one Jolt compound rebuild; mitigated by OQ5 cap if needed.
