# Game roadmap build plan (owner 2026-09-29)

Source: `feedback/game_roadmap.md`. These are new remake features. The seven
documented original specials and the current default objective remain
available. Beads epic `Bontago-22y` tracks delivery; this file is the design
contract for interfaces, ownership, order and acceptance checks.

## Sequence and shared rules

Complete `docs/GIFT_REWORK_PLAN.md` before adding Stackfall, Paintball, Glue or
Cat. The gift framework supplies claiming, next-piece behavior,
activation and replication. Weather begins with `Bontago-22y.10`; modes begin
with `Bontago-22y.11`. A package that edits one of the shared files below runs
after its predecessor, not in a parallel checkout. Workers use targeted tests;
the orchestrator runs one integrated full GUT gate per game-code batch when
the environment supports `user://` writes. Physics benchmarks run alone.

## New gifts

1. **Roster contract:** Extend `SpecialDef` resources, weighted draw and the
   lobby's existing enabled-special checklist. A per-slot drop modifier needs
   a typed state separate from a one-shot impact special. Ownership:
   `config/specials/`, `autoload/match/MatchGifts.gd`, focused roster tests.
2. **Glue drops (`Bontago-22y.3`):** Count successful drops for a tunable
   number of charges. Bonds form on contact with the disc or another block,
   deduplicate body pairs, and clean up on break or despawn. Reuse
   `GlueEffect`/`GlueJoint` contact and stress logic. The shipped Glue is a
   one-shot radius joint special; the roadmap's multi-drop buff is a distinct
   behavior. Ownership: new GlueDrops effect/state, `MatchPlacement`, joint
   helpers and focused effect tests. Rejected clicks spend no charge.
3. **Paintball (`Bontago-22y.2`):** The host simulates the thrown glob, finds
   blocks in a tunable splash radius, and changes owner slot, registry
   attribution, material color and territory source together. Replicate each
   conversion by block net ID, validating repeats and unknown IDs. Ownership:
   new projectile/effect, `Block`, `BlockRegistry`, `BlockFactory`, `MatchNet`
   and focused paintball/net tests. Avoid mutating a shared color material.
4. **Stackfall (`Bontago-22y.1`):** The host drops a bounded, seeded rain of
   ordinary blocks in the activating player's color through the normal
   `BlockFactory`/registry/snapshot path. Ownership: new effect, placement
   spawn seam, SpecialDef and focused tests. Tune count, area, altitude,
   spacing and rate; enforce the body cap. Benchmark peak snapshot load.
5. **Cat (`Bontago-22y.13`):** Spawn one host-simulated cat and give the
   activating player a laser-pointer aim state. The cat pursues the replicated
   target and collides with stacks through ordinary physics; all peers see its
   movement and impacts. Define activation duration, steering speed, target
   range and body-cap behavior as tunables. Own a Cat effect/controller, pointer
   input and preview, and network state; test authority, input ownership,
   collision, reset and late join before a visual/gamepad pass.

## Weather

`Bontago-22y.10` adds weather selection to `MatchConfig`/Lobby, a host-owned
weather lifecycle, replicated state and per-weather tunables. Client particle
systems are presentation; physics changes happen on the host and restore the
baseline when weather or match ends. Own `MatchWeather`, `WeatherTuning`,
`MatchConfig`, Lobby, `MatchNet` and focused config/network tests. No per-block
contact monitor: the existing `bench_rain` records a substantial cost at
hundreds of blocks.

- **Wind (`Bontago-22y.4`):** bounded impulses stronger at greater height,
  sampled from live blocks with sleep-aware work. Test height response and
  reset; benchmark moving-pile cost.
- **Rain (`Bontago-22y.5`):** lower friction on existing and future blocks
  and the disc; restore originals on stop. Reuse `Block.apply_physics_tuning()`
  and Field material setup. Test friction round trip and network state.
- **Snow (`Bontago-22y.6`):** bounded visible and colliding accumulation on
  blocks and disc, with geometry cleanup. Visual depth must match collision.
  Test collider correspondence and measure 300-block physics cost before
  acceptance.

## Additional modes

`Bontago-22y.11` adds a mode objective interface with host-owned scoring,
round-end policy, replication and result fields. Add mode and timer settings to
`MatchConfig`/Lobby. Keep `WinChecker` as the classic-mode objective; the
territory solve must not end every other mode on all-goal hold. Existing
`match_timer_minutes` does not finish a match when sudden death is disabled,
so timed modes need an explicit timer-end path. Own `ModeObjective`,
`MatchLifecycle`, `MatchTerritory`, `MatchStats`, `Events`, `MatchNet`, Lobby and
focused lifecycle/net tests. Classic-mode results must remain unchanged.

- **Capture the Flag (`Bontago-22y.7`):** score each independently owned
  beacon once per elapsed time slice. Multiple held beacons increase score
  proportionally. Highest score at the lobby-set round end wins. Reuse GoalFlag,
  Field's goal list and team mapping. Test one/two beacons, loss/reclaim,
  coarse/fine tick equivalence, team scores and timer winner.
- **Elimination (`Bontago-22y.8`):** reuse home flags, elimination and
  last-team-standing logic with a mode-specific home capture rule; disable
  classic all-goal victory. Test FFA, teams, simultaneous home loss and
  reconnection state.
- **Reach the Sky (`Bontago-22y.9`):** record each player's highest placed
  block during the round as a monotonic value; a later collapse cannot lower
  it. At timer end, the highest record wins. Reuse block height sampling and
  result presentation. Test multi-cube height, collapse persistence, ties and
  team aggregation.

## Rule decisions before dependent packages

Before weather implementation, settle whether one weather is fixed for the
whole match or changes during the round, and whether effects can coexist.
Before Capture the Flag, settle whether home-connected territory is required
and whether ownership needs a hold duration. Before Elimination, define home
capture under the default overlap-hole model, which the current spec leaves
open. Before Reach the Sky, choose the height sampling moment (release,
settlement or later peak), plus team and tie handling. Put these decisions in
Beads when the package is prepared; counts, strengths and radii can start as
resource tunables.
