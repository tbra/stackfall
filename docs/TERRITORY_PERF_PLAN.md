# Territory solve performance plan (Bontago-1pi.11.21)

Design contract for cutting the host territory solve cost during active play.
Rules do not change: every package must produce output identical to the current
full solve (raster bytes, groups, circle render list, hole/capture timers,
events, replication payloads). Spec anchors: SPEC.md 2.2 "Continuous updates
[OWNER]" ("A moving block cannot retain stale pre-collapse influence") and the
3.3/418 rate note (`solve_hz = 20` is a benchmark candidate, not a rule).

## 1. Measurements (step 1, headless, checkout wt/perf-terrsolve @53d452f)

Tool: `tools/bench_terrphase.gd` (+ `.tscn`). Loads Main with
`--headless-host --bots=4 --match-config=res://tools/botmatch_large.tres`
(large map, radius 60, 11 289 in-disk cells, `hole_mode = TEMPORARY`, so the
live path is the legacy fill), adds frozen cube towers (1-6 high) until the
registry tracks each target, times each phase on fresh scratch objects
(median of 7), then records 20-40 s of live play with the built-in
`sandbox_profile()` split and a revision-bump cause tracker. Another agent's
bot match was running concurrently, so absolute numbers carry some contention.
Logs: session scratchpad `tp_run1.log`, `tp_run2.log`.

Command:
`godot --headless --path . res://tools/bench_terrphase.tscn -- --headless-host --bots=4 --match-config=res://tools/botmatch_large.tres --targets=100,200,300 --live-seconds=40`

Phase cost per full (cache-miss) solve, ms:

| blocks | source sig | registry.influence_circles | cone project | solver | raster fill | circle render + overlay | events/win | full step (live) |
|---|---|---|---|---|---|---|---|---|
| ~100 | 0.14 | 2.6 | 1.1 | 0.15 | 0.2-0.3 | 0.14 + 0.12 | <0.05 | 3.8 |
| ~200 | 0.28 | 3.8 | 2.1 | 0.3-0.5 | 0.2-0.3 | 0.2 + 0.25 | <0.05 | 6.9 |
| ~300 | 0.36-0.46 | 5.8-7.7 | 3.0-4.9 | 0.5-1.3 | 0.2-0.5 legacy, 1.5 v2 | 0.2-0.4 + 0.1-0.3 | <0.05 | 10.3-18.6 (median ~12) |

- **Collect is 85-90 % of the step** (live `collect` 9.2-16.9 ms of 10.3-18.6 ms
  at ~300 blocks). It is all GDScript per block:
  `BlockRegistry.influence_circles()` (game/BlockRegistry.gd:222) calls
  `_local_center_of_mass()` and `_top_height_local()` (L394, L409: every
  MeshInstance3D child, 8 AABB corners, `global_transform *` plus
  `Field.to_local()` each) for every settled block on every miss, about
  20-25 us per block. `SandboxConeExperiment.build()`
  (core/territory/SandboxConeExperiment.gd:15) sorts all candidates with a
  GDScript `sort_custom` lambda (about n log n lambda calls) and runs an
  O(candidates x kept) containment loop that iterates other teams' kept cones
  only to `continue` (2 415 comparisons at 300 blocks).
- Solver, raster, overlay upload, win check and events together cost
  1-2.5 ms. **A dirty-rect incremental raster would save at most about 1.5 ms**
  and would have to reproduce argmax removal, legacy group-order contest ids and
  group renumbering. It is **not** part of this plan.
- Replication/upload bytes: `TerritoryRaster.owner_bytes()` + `state_bytes()`
  (L347, L359: GDScript loops over all 14 400 cells) + MatchNet's per-cell
  compare (net/MatchNet.gd:612-628) = 2.8-3.3 ms per call. `TerritoryOverlay._process`
  (game/TerritoryOverlay.gd:162-171) calls `upload_now()` → both byte builders
  at `raster_upload_hz` (5 Hz) **unconditionally**, on host and clients, and
  `replicate_territory()` rebuilds them again at 5 Hz when clients exist. That
  is 1.5-3 ms spikes 5-10 times per second, whether or not the raster changed.
- Solve rate: with blocks placed about 0.8/s, `_is_clean()` skips about 19 of 20
  ticks (clean_skips/s 17-20). Real steps run 0.4-1.6/s in the bench; each one
  is a cache miss costing a full collect. Bumping ticks were caused by `placed`
  (about 0.8/s), `settle_on`/`settle_off` (1-1.5/s), `moved_eps` (0-5/s, bursts
  when a settled pile creeps), and `removed`. Awake blocks keep
  `_should_defer_solve()` holding the step until `solve_defer_max_s` (0.5 s),
  so churn is already capped near 2 Hz. The 5-20/s in 1pi.11.20 comes from
  settled-but-creeping piles under weather (`moved_eps` with nothing awake)
  solving at the full 20 Hz, where each step still pays the full collect.
- Legacy modes run `_run_clean_legacy_step()` for the remaining catch-up steps
  (cheap). In v2 (`hole_mode = OFF`) a coalesced tick runs `_run_territory_step()`
  twice (MatchTerritory.gd:176-182). The second is a cache hit (signature
  0.4 ms + refill 0.2-1.5 ms).

## 2. Chosen design

Principle: cache the pure per-block geometry keyed on **exact** inputs, and
make the global cone pass native where it can be. With the cache, a creeping
pile no longer forces a recompute of every block's circle, and there is no
approximation to validate.

### 2.1 Per-block geometry cache (P1)

`BlockRegistry._Entry` gains:

```gdscript
var geom_valid: bool = false
var geom_block_xform: Transform3D = Transform3D.IDENTITY
var geom_field_xform: Transform3D = Transform3D.IDENTITY
var geom_child_count: int = -1
var geom_com_xz: Vector2 = Vector2.ZERO   # _local_center_of_mass(block) x,z
var geom_top: float = 0.0                 # _top_height_local(block)
```

`influence_circles()` keeps its signature and output order (dictionary key
order of `_entries`). For each settled entry it reuses `geom_*` when
`geom_valid and block.global_transform == geom_block_xform and
field_xform == geom_field_xform and block.get_child_count() == geom_child_count`.
Otherwise it recomputes both values and stores the key. `field_xform` is read
once per call (`_field.global_transform`, or IDENTITY with no field).
`Transform3D ==` is exact componentwise equality, not `is_equal_approx`, so a
hit returns bit-identical floats to a recompute. Team mapping, tuning and
`field_radius` are still applied fresh through `InfluenceCircle.for_block()`
each call (cheap), so owner changes, tuning-panel edits and team changes need
no invalidation. `top_height_for_block()` and `max_height_for_slot()` may use
the same cache through one private `_geometry(entry, field_xform)` helper.

- DECISION to record: the child-count key guards against a special adding a
  MeshInstance3D child (GlueDrops adds a non-mesh `bond` node; its count change
  just forces one recompute). If a package ever swaps `mesh_instance.mesh` in
  place on a live block, it must call the new
  `BlockRegistry.invalidate_geometry(block)`. P1 greps `\.mesh = ` under
  game/ and autoload/ and wires any live-block mesh swap to it.
- Test seam: `var _geometry_cache_enabled: bool = true` (tests turn it off to
  get the oracle).

Expected: `influence_circles` at 300 blocks goes from 5.8-7.7 ms to about
0.4-0.8 ms (a transform compare per unchanged entry; recompute only the few
that moved).

### 2.2 Cone pass without GDScript lambdas (P1)

`SandboxConeExperiment.build()` keeps its signature and returned dictionary
(including `comparison_count`) exactly:

- Replace the `sort_custom` lambda with a native sort. Build
  `keys: Array = [[-radius, index], ...]` (64-bit float and int) and call
  `keys.sort()` (Variant Array `<` is lexicographic). This gives the same
  order: radius descending, then index ascending. If the Array compare turns out
  not to be lexicographic in 4.7, fall back to a stable native approach and
  prove the order equal in the test. Do not use float32 keys, because rounding
  can reorder near-equal radii.
- Keep per-team kept lists as parallel `PackedFloat64Array` x/z/radius, so the
  containment loop only visits same-team cones. That is exactly the set the
  current loop does not `continue` past, so `is_covered` and `comparisons` are
  unchanged.
- Everything else (projected radius formula, BASE_* modes, home handling,
  output order by original index) stays as it is.

Expected: cone at 300 blocks goes from 3-5 ms to about 0.6-1.2 ms.

Combined P1 expectation: a full step at ~300 blocks goes from about 12 ms
(peaks 19-27 ms in real matches) to about 2.5-4 ms. Creeping piles at 20 Hz
then cost about 50-80 ms/s instead of 240+ ms/s.

### 2.3 Raster byte cache, upload skip and v2 coalesce (P2)

- `TerritoryRaster` keeps `_bytes_dirty: bool` (true after `update()`,
  `advance_time()` when `_opened`/`_closed` are non-empty, `force_hole_cell()`,
  `apply_replicated_state/diff()`, `reset()`, `set_goal_zones()`) and a public
  `content_revision() -> int` bumped at the same points. `owner_bytes()` and
  `state_bytes()` rebuild only when dirty and otherwise return the cached
  buffers. Contents are unchanged. Callers that `.duplicate()` (MatchNet) keep
  doing so.
- `TerritoryOverlay.upload_now()` skips `push_cells()` when
  `_raster.content_revision()` equals the revision it last pushed. `set_source()`
  and `configure()` reset that memo so a new raster always uploads.
- `MatchNet.replicate_territory()`: when not `full` and
  `owners == _last_owner_bytes and states == _last_state_bytes` (native
  PackedByteArray equality), return before the per-cell loop. This is exactly
  the existing `changed.size() == 0` return, reached without the loop.
- v2 coalesce (MatchTerritory.gd:179-182): when `remaining > 0` and
  `_alive_home_count() == alive_before` and `_is_clean()` holds after the first
  step, the second call is a guaranteed cache hit on an identical raster. It
  may be replaced by `_advance_clean(float(remaining) * step)` only if the
  observable output matches. The difference is that `territory_updated` and
  `territory_share_changed` would no longer be re-emitted with identical data,
  and `solve_step_count()`/`clean_skip_count()` would shift by one. P2 checks
  `tests/unit/test_match_flow.gd:1030-1050` and every other assertion on those
  counters. If any test pins the double step, leave this change out and note it.
  It is an optional part of P2.

Expected: the 5 Hz 1.5-3 ms upload spikes disappear while the raster is
unchanged (most ticks), and the replication loop runs only when bytes differ.

### 2.4 Rejected or deferred

- **Dirty-rect incremental raster and incremental connectivity**: at most
  about 1.5 ms of the step, and high equivalence risk (legacy contest
  semantics depend on group order). Revisit only if the post-P1 profile shows
  solver + raster above 40 % of the step.
- **Max solve rate while churning**: churn is already capped by
  `solve_defer_max_s`. A new cap on settled-creep solves would add
  authoritative latency, which is an owner feel question under SPEC 2.2
  "Continuous updates [OWNER]". It is not needed if P1 lands. If the post-P1
  bench still shows more than 5 ms steps at 20 Hz, ask the owner through a
  `decision` bead whether to lower `solve_hz`. Do not add a hidden cap.
- GDExtension/native code: not needed for these gains.

## 3. Invariants (both packages)

1. For any board, `influence_circles()` with the cache equals the uncached
   call element by element: center, radius, team, slot, `body_id`,
   `top_height`, and order.
2. `SandboxConeExperiment.build()` returns identical `circles`,
   `kept_indices`, `candidate_count`, `kept_count`, `culled_count` and
   `comparison_count` to the pre-change algorithm.
3. Raster `owner_bytes()`/`state_bytes()`, `team_share()`, hole
   opened/closed lists, win-checker hold and capture events are unchanged, in
   both v2 and legacy modes.
4. Client replication payloads are byte-identical for the same host state. A
   client never solves.
5. No config literals. Any new tunable goes into `TerritoryTuning`. None is
   planned.

## 4. Packages

### P1: per-block geometry cache and cone fast path (Sonnet, about 30 min)

Owned files:
- `game/BlockRegistry.gd`
- `core/territory/SandboxConeExperiment.gd`
- `tests/unit/test_territory_collect_cache.gd` (new)
- `tests/unit/test_sandbox_cone_experiment.gd` (extend)
- `tools/bench_terrphase.gd`, `tools/bench_terrphase.tscn` (land as-is; may
  add an `--uncached` flag)

Interfaces: `BlockRegistry.invalidate_geometry(block: Block) -> void`,
`var _geometry_cache_enabled: bool`. No other public change.

Acceptance:
- (a) A randomized equivalence test runs 200 steps of random place, move
  (sub-mm and large moves, rotations), remove, owner change and field tilt on
  real Block nodes. It asserts cached == uncached `influence_circles()`
  field by field.
- (b) A randomized cone test (500 sets, 0-300 circles, forced radius ties, all
  three base modes) compares against the old algorithm, which is kept verbatim
  in the test file as the oracle.
- (c) `tools/run_gut.ps1 test_territory_collect_cache,test_sandbox_cone_experiment,test_block_registry,test_match_flow,test_territory_raster`
  passes.
- (d) Import check is clean.
- (e) `bench_terrphase --targets=100,200,300`, run alone on the machine,
  reports a live full step at ~300 blocks at 4 ms or less and
  `reg_circles` + `cone` at 2 ms or less.

### P2: raster byte cache, upload/replication skip, optional v2 coalesce (Sonnet, about 30 min)

Owned files:
- `core/territory/TerritoryRaster.gd`
- `game/TerritoryOverlay.gd`
- `net/MatchNet.gd`
- `autoload/match/MatchTerritory.gd` (coalesce only)
- `tests/unit/test_territory_raster.gd` (extend)
- `tests/unit/test_territory_overlay.gd` (extend)

P2 is disjoint from P1 and can run in parallel in a separate worktree.

Interfaces: `TerritoryRaster.content_revision() -> int`.

Acceptance:
- (a) For random update/advance_time/force_hole/replicated sequences in both
  modes, cached `owner_bytes()`/`state_bytes()` equal a fresh recompute (test
  seam that forces a rebuild).
- (b) The overlay does not call `push_cells` when the revision is unchanged,
  and does call it after any mutation.
- (c) `replicate_territory()` sends nothing on unchanged bytes and an
  identical payload otherwise, covered by an ENet test in `test_net_*`.
- (d) The targeted runner passes on
  `test_territory_raster,test_territory_overlay,test_match_flow,test_net_session`
  and the net territory tests.
- (e) Import check is clean.
- (f) A reviewer is required, because the package touches core/, net/ and
  autoload/.

Integration order: P1 and P2 run in parallel and merge in either order. Then
run one `bench_terrphase` plus one `bench_botmatch` run alone on the machine to
confirm that frame spikes no longer track territory.
