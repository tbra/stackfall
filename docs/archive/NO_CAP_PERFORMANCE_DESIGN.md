# No-cap performance design

Research date: 2026-09-27. Owner direction: retain blocks; consider different
block architectures, not just local optimizations. Research task: Bontago-sog.
No game behavior or pending Claude implementation was changed by this research.

## Recommendation

Use **centralized block data, change-driven territory, and independently sleeping
Jolt bodies**. Move repeated bookkeeping out of individual scene objects. Keep
each block physically independent, but stop recomputing unchanged block data
and territory. Batch visuals independently of physics. This is a substantial
change in handling architecture, not a block cap or a cheaper approximation of
tower behavior.

First attack territory and repeated scene queries. Introduce a BlockStore behind
BlockRegistry before considering a native backend or a wholesale engine switch.
Do not weld settled piles into rigid compounds as the default: that changes
internal sliding and collapse.

## What is measured, and what is not

Claude's quoted GPU measurements are approximate, use different populations,
and concern its pending territory-glow spatial-bin fix. They are not a CPU stage
profile. This design does not assume that 160 bodies is a Jolt limit.

I ran the existing pure-core territory benchmark, then a temporary diagnostic
that duplicates its tuning and sets `max_circles=0`. No other Godot process was
visible before these serial runs. The uncapped probe uses the existing seeded
scatter fixture, medium map, 20 repeated measurements, temporary-hole mode:

| Block circles (plus 8 homes) | Solver | Raster | Win check | Total per solve |
| --- | ---: | ---: | ---: | ---: |
| 200 | 2.878 ms | 0.928 ms | 0.009 ms | 3.815 ms |
| 400 | 10.106 ms | 9.181 ms | 0.014 ms | 19.301 ms |
| 800 | 35.389 ms | 22.334 ms | 0.013 ms | 57.736 ms |

These are Godot debug-interpreter CPU measurements, **not rendered frame times**
or promised release-build performance. The probe excludes registry collection,
HUD height sampling, physics, GPU uploads, networking and bots. Averaging 20
calls does not characterize gameplay p95 or eliminate all external system load.
Logs and reproduction helper are local under `feedback/no_cap_research_*` and
`feedback/no_cap_territory_probe.*`.

Live tuning schedules 20 solves/second, giving 50 ms between solves. The current
catch-up loop can run multiple expensive solves in one frame. The 800-circle
probe already exceeds that interval without the rest of the game. At 400 circles,
the measured repeated solve cost alone corresponds to ~386 ms of CPU work per
second in this synthetic workload; spikes matter as well as average utilization.

There is also a **hidden influence limit**, distinct from a body cap:
`config/territory_tuning.tres` sets `max_circles=400`; the solver omits some
influence circles above it. The existing 600-block benchmark consequently does
not exercise a fully uncapped solve. Do not simply disable this safeguard in the
live game before replacing the scaling behavior. A no-cap acceptance benchmark
must retain and count every authoritative influence circle.

## Source-proven repeated work

1. `TerritorySolver._collect_pairs()` enumerates pairs in every occupied hash
   bucket before canonical-cell duplicate rejection. Large overlapping circles
   share many buckets, multiplying iteration work. Cross-team rejection happens
   later too. Its reported pair counter excludes duplicates, hiding that cost.
2. `TerritoryRaster` clears ownership and restamps all connected circles every
   solve. Cost grows with total covered circle area, including redundant coverage.
3. `BlockRegistry` polls every block's velocities at 60 Hz. Both influence
   collection and HUD height queries discover mesh children and transform eight
   AABB corners repeatedly, including for unchanged settled blocks.
4. `MatchTerritory` rebuilds, sorts and uploads analytic circle arrays every solve;
   static goal data is uploaded repeatedly. Coordinate this area with Claude's
   pending GPU fix rather than replacing its shader independently.

## Proposed architecture

### Central BlockStore with stable handles

Keep stable block/net IDs and central arrays for owner, shape, body handle, pose,
velocity, settling state, cached visual bounds, influence and dirty generations.
Initially retain lightweight RigidBody3D bodies and adapt BlockRegistry's public
interface, so replication, specials and placement can migrate incrementally.

Poll only awake/unsettled entries, not the entire settled population. Native
sleep/wake notifications and explicit script freeze/impulse actions maintain the
active set. Preserve the existing velocity-based settling rule: an awake,
slow-moving block can still be eligible for territory. Do not equate settling,
sleeping and freezing. Saturate settled timers once eligible.

Cache immutable shape geometry once per shape/tuning combination. Cache influence
and top height against block pose, field transform, shape/tuning, ownership and
settling generations. For bounds height, the exact transformed AABB maximum is
transformed center height plus the sum of absolute y-row basis coefficients times
the corresponding half extents; it avoids eight separate corner transforms.
Live geometry/tuning and disc tilt invalidate this cache.

### Change-driven authoritative territory

Separate **geometry/connectivity** from **time-dependent rules**:

- Reuse connectivity and raster coverage when the circle inputs and rule/tuning
  revisions are identical. Static boards should not pay for a full solve 20 times
  per second.
- Keep hole contest/closure timers and the 3-second capture hold advancing at the
  existing cadence, even with no geometry changes. Hole timers can alter ownership
  bytes and win checks; cached coverage is not permission to skip those updates.
- On change, initially rebuild exactly once and retain a reference implementation.
  Then invalidate old/new circle bounds and affected connected components rather
  than restamping the whole disc. A connectivity change can affect remote cells
  of an entire disconnected group: local bounds alone are insufficient.
- Force-hole events, shrinking disc, elimination, teams, mode changes and tuning
  changes must explicitly invalidate the appropriate caches. Keep per-cell timer
  state independent of coverage recomputation.

This reduces stable-board work toward active timers plus changed blocks, rather
than total accumulated blocks. It does not remove or approximate their influence.

### Exact cold-solve improvements

Group candidate generation by team **before** pair enumeration. Investigate an
AABB sweep or center-index query that considers each potential same-team pair
once, preserving original circle indices and deterministic group assembly. Dense
true overlaps can still be quadratic; spatial indexing is not a universal cure.
Measure raw candidate visits separately from successful overlap tests/unions.

Prune fully contained circles from the **raster input only**, within the same
connected group. If distance between centers plus smaller radius is no greater
than larger radius, the larger disc covers the smaller disc. Its radius-minus-
distance kernel is also nowhere weaker, by the triangle inequality. Preserve
boundary/tie precision and group ordering; test against the existing raster.
Use a spatial index for containment; naive all-pairs pruning can move the problem.

Do not prune these circles from the visual metaball sum, network circle payload,
or authoritative connectivity: those have different semantics. Metaball glow can
change even when hard circle coverage is redundant.

If changing geometry remains CPU-bound, put the pure solver/raster hot loops in
a small C++ GDExtension behind the same packed-data interface. Preserve precision,
tie breaks and timer semantics and compare outputs to GDScript. Do not introduce
threads until exact inputs/results and snapshot ownership are established;
delayed authoritative territory results could change placement and capture timing.

### Rendering separate from simulation

Batch block visuals by shape/material and spatial region using MultiMesh, with
player color and contribution state in instance data. Retain independent bodies
and collision geometry. Preserve outlines, interpolation and per-block picking.
Update only moving/dirty transforms. MultiMesh visibility is batch-wide, so avoid
one giant world batch. This helps render/scene overhead, not Jolt contact solving.
Make it conditional on a stage profile showing those costs, since Claude found
the disc glow dominant in its current GPU experiment.

## Physics: preserve behavior before optimizing harder

Jolt naturally sleeps contact islands while retaining collision/wake behavior.
That differs from `freeze=true`/STATIC. Current StableBlockManager assumes sleep
changes can unfreeze static bodies; Field tilt changes its transform without
releasing stable-freeze reasons, and hole handling directly changes `freeze`,
bypassing that bookkeeping. Explicit special impulses have better wake coverage.
Audit these paths before relying on stronger static freezing.

Retain sleeping dynamic bodies as the safe default architecture. Explicitly wake
affected bodies for support removal/holes and appropriate board movement; keep
intentional Freeze-special reasons distinct. No cap on total or awake bodies is
proposed. A simultaneous whole-board collapse will still require real CPU work.

Global Jolt velocity iterations are unusually high (192, position iterations 4).
Project history records tower failures below ~100 and rain costs around 2.8 ms
with older settings versus 5 ms with the chosen settings. These are dated evidence,
not current whole-game timings. Do not reduce iterations, damping, collision detail
or physics tick rate just to obtain a better number and reintroduce tower/feel bugs.
If native physics is dominant, investigate equivalent primitive decomposition
and per-body quality experimentally. Current per-cell collision margins leave
small gaps; merging cells into one box can change collision geometry and inertia.

## Alternatives considered

| Approach | Assessment |
| --- | --- |
| Central BlockStore + lightweight bodies | Recommended first migration; removes repeated script work, retains individual dynamics. |
| PhysicsServer-only bodies / native block manager | Strong later option if node/callback overhead remains dominant; requires explicit RID lifecycle, identity, picking, interpolation, specials and replication. Same Jolt solver, so not an automatic physics speedup. |
| Render-only batching/chunks | Compatible with full physics; pursue when measured draw/scene overhead warrants it. |
| Static or rigid compound settled piles | Not equivalent: piles can no longer slide internally or collapse until deaggregated. Pre-contact/tilt/support-loss deaggregation has correctness and wake-spike risks. Not recommended as default. |
| Switch to Tokamak | Original provenance is valuable for game feel, not proof of better performance. Requires Godot integration and different collision, sleep, solver and threading behavior. Only compare engines after isolating native physics cost with identical workloads. |
| Delete/cap blocks or silently omit influence | Rejected by owner direction; not this design. |

## Bounded implementation and acceptance

1. Add whole-match stage counters and a reproducible seeded board fixture: 200,
   400, 800 and 1600 blocks; settled, mixed awake, dense tower, tilt and collapse.
   Count retained circles and raw pair visits. Report script/physics/GPU separately,
   stage averages and frame p95. Use identical populations and idle serial runs.
2. Implement central geometry/influence caches and unchanged-input solve reuse.
   Keep the existing raster as an oracle. Validate both hole modes, disconnected
   groups, home elimination, goal capture, sudden death and live tuning changes.
3. Replace cold-solve candidate generation and add indexed raster containment
   pruning. Compare randomized and adversarial outputs byte-for-byte, including
   team/group tie behavior and hole timelines. Include same-team and eight-team
   clustered circles; scattered-only fixtures miss the pathological workload.
4. Introduce central active-block bookkeeping and correct wake paths. Validate
   aged towers hit by a falling block, tilt, hole opening, explosion and overlapping
   Freeze effects. Use existing rain/tower/physical-balance tests, not blanket probes.
5. Profile again; migrate rendering or pure math to native code only if their
   measured cost still exceeds the agreed target. Ship changes in bounded packages,
   with one integrated suite rather than one full suite per package.

Target rendered 60 fps means a ~16.7 ms frame budget, but no speedup/FPS guarantee
is established yet. Choose an explicit representative population and fidelity
contract; indefinite block accumulation cannot mean infinite work on finite hardware.

## Primary sources

- [Godot CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html): profile stages, cache repeated work, and consider native hot loops.
- [Godot server APIs](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html): scene objects are optional, with manual RID lifecycle responsibilities.
- [Godot MultiMesh guidance](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html): batched visuals and batch-wide culling limits.
- [Jolt architecture](https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md): sleep islands, automatic contact waking, and explicit waking after removal.
- [Jolt performance harness](https://github.com/jrouwe/JoltPhysics/blob/master/Docs/PerformanceTest.md): includes a 1,240-box pyramid; this is not a Stackfall benchmark or proof of a specific FPS.
- [RigidBody3D semantics](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html): sleeping and frozen bodies are not interchangeable.
