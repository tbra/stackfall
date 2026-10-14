# Stackfall — Game Design & Technical Spec

> The design reference for Stackfall, a physics-based, competitive block-stacking territory game for 2–8 players (Godot 4.6+, Jolt, Steam and LAN). Part 2 states the game rules as built and intended; Part 3 is the technical architecture. Where this spec and code disagree, the disagreement is a bug or an open decision, marked `(open: <bead id>)`.
>
> Rule changes go through the owner (Beads `decision` issue). Owner-decision provenance (bead id and date) is kept where it explains why a rule is the way it is. Tunable numbers live in config resources under `res://config/`, never in code.
>
> Open questions that are not tied to a bead are marked `(open)`. Status and tasks belong in Beads, not here.

---

## PART 1 — Origins (historical)

Stackfall began as a remake of Bontago (2003, Circular Logic). That phase is complete: the original is history, not a reference to build against. The research is kept in [docs/archive/BONTAGO_ORIGINAL_RESEARCH.md](archive/BONTAGO_ORIGINAL_RESEARCH.md) (with [install evidence](ORIGINAL_INSTALL_EVIDENCE.md)); nothing there gates a design decision.

### 1.1 Facts
Archived: [original research](archive/BONTAGO_ORIGINAL_RESEARCH.md).

### 1.2 Core rules
Archived. Current rules are in 2.2 (territory), 2.3 (win) and 2.4 (placement cadence).

### 1.3 Gifts / specials
Archived. Current gifts are in 2.6.

### 1.4 Modes & options
Archived. Current modes are in 2.7 and lobby settings in 2.8.

### 1.5 Original controls
Archived; current controls are 2.5.

### 1.6 Reported appeal
Archived. The design goals it noted (physical weight and balance, tall versus wide strategies, chaos, sandbox play) still guide 2.7 and 2.10.

### 1.7 Reported problems and responses
Archived. Responses carried into Stackfall: snapped rotation with reset (2.5), body caps and freezing (3.5), match timer and sudden death (2.8), tunable gifts (2.6), throw arc preview (2.5), Steam lobbies, LAN discovery and direct IP (3.4).

### 1.8 Sources
Archived in the research file.

---

## PART 2 — Game design

**Scale:** 1 unit = 1 cube edge = 1 m. Numbers below are the current values of the config resources.

### 2.1 Field
- **Shape:** a disk of radius `field_radius` (`MapDef`, `config/maps/*.tres`): 30 small, 45 medium, 60 large. The lobby has a disc-size slider (index into `config/disc_size_tuning.tres`, 50% to 175%, default 100%; owner 2026-10-07, Bontago-1pi.107); map shape and size are not otherwise lobby-selectable (`MatchConfig.gd:117-122`).
- **Map shapes:** round only. Oval, Ring, Twin and Cross were removed (owner decision Bontago-fca.74 = B, `MapDef.gd:13-18`).
- **Tilt:** `tilt_mode = SPECIALS_ONLY` (default): the disk is an animated body driven by a critically damped spring on its tilt vector, 12° maximum, about 4 s return; only specials (Anvil, Propeller, Earthquake) tilt or level it. `PHYSICAL_BALANCE`: the disk is a RigidBody3D on a two-axis joint; block weight tilts it and a restoring spring and angular damping keep it controllable. Both are selectable in the lobby.
- **Holes:** the disk surface is divided into cells so holes can appear (2.2, 3.3).
- **Out of bounds:** any body below `kill_plane_y = -40` is removed.

### 2.2 Players, flags, territory
- **Start positions:** 1–8 players (solo matches allowed, owner 2026-10-13, Bontago-1pi.206). Each home flag sits `MapDef.home_flag_edge_inset` (6.0 m) in from the rim, evenly spread, on every map size (owner 2026-10-12, Bontago-1pi.184).
- **Goal flags:** 1 central flag by default; 1–5 selectable, extras at `0.4 * field_radius`.
- **Home circle:** `home_radius = 6` while the home flag is alive.
- **Goal no-build zones:** a disc of `goal_zone_radius = 4 m` around each goal blocks placement, not influence or capture. It is not missing floor, and claiming its edge is not enough to capture the flag base.
- **Influence per block:**
  - Each settled block of a player produces an influence circle centered on its center of mass, projected onto the disk plane.
  - Radius uses the block's top height `h` above the disk, measured along the disk normal, and a 40° cone half-angle (owner 2026-10-10; cone model chosen 2026-09-30, per-block linear model removed 2026-10-08, Bontago-1pi.111): `r = min(influence_base + h * tan(40°), influence_max)`, with `influence_base = 1.5` and `influence_max = 0.6 * field_radius` (`TerritoryTuning`). A same-team block circle is omitted only when a larger projected circle completely contains it; home circles are never omitted.
  - Moving the disk and a resting tower rigidly together does not change their relative height; tilt affects influence only when blocks move relative to the disk.
  - Settled filter: linear speed below 0.15 m/s and angular speed below 0.3 rad/s for 0.5 s.
  - **Continuous updates:** movement, collapse and removal update influence at `solve_hz = 20` without waiting for another placement. A moving block never retains stale pre-collapse influence.
- **Connected territory:**
  - Placement requires influence connected to the player's home flag. Each influence circle is a graph node; two circles are connected if they overlap. Circles disconnected from home give no usable territory.
  - For capture, a route must survive in the final owned area, not merely in the pre-contest circle graph. Enemy territory or a hole cutting the only route breaks capture (3.3).
- **Height credit:** a block's owner is its placer permanently. A block placed on an opponent's tower gives influence to its placer, not to the tower's owner.
- **Overlap holes:** opposing candidate influence creates a contested region that neither player may use for placement.
  - `hole_delay = 0.75 s` of continuous contest opens a hole.
  - Holes are a visual void, not a physical opening (owner 2026-10-01, Bontago-gdb option A): the disc collision stays solid, and a block whose footprint touches an applied hole cell at disc level dissolves (short fade, `HoleDissolveTuning`) and is removed like an edge fall. Blocks stacked above then land on the void and dissolve too. A block merely above a hole, or rising away from it, is unaffected.
  - `hole_mode`: `TEMPORARY` (default; a hole closes `hole_close_delay = 2 s` after the contest ends), `PERMANENT` (erosion; Elimination defaults to it, the lobby switching to `PERMANENT` on entering Elimination and back to `TEMPORARY` on leaving, owner 2026-10-12, Bontago-1pi.178; the host can still change it), `OFF` (intact floor, locally height-weighted exclusive borders; see 3.3).
  - Jumping Bean holes are independent of opponent overlap; under `HoleMode.OFF` the Bean punches no hole and keeps only its hop knockback (owner 2026-09-22, Bontago-z4h).
- **Teams:** teammates place in each other's territory and do not contest each other. Goals still need one continuous allied component, not disconnected patches sharing a team id.

### 2.3 Win condition
- **Classic:** every goal flag's base must be in the same final controlled component, with an unbroken path to a living allied home, simultaneously for `capture_hold = 20 s` (owner playtest 2026-10-06, Bontago-1pi.91; F4-tunable, Bontago-1pi.31). There is one shared hold, not independent permanent captures. Losing any goal or the connecting path resets the hold; solver group renumbering alone does not. The flag base is the single raster cell at the flag position (`WinChecker.claim_at`); the "Bigger goal claim radius" experiment (2.8) makes the cells within the radius vote instead.
- **Home elimination:** a player whose home flag is lost is eliminated; the last surviving team wins. In `TEMPORARY`/`PERMANENT` hole modes the trigger is a hole opening under the home flag (`MatchTerritory._check_home_flags`); in `OFF` it is an enemy area owning the home flag's cell (`_check_home_flags_v2`). In the Elimination game mode both triggers are replaced by the claim timer below. Elimination and a goal capture completing in the same territory step: the capture is latched first, then eliminations resolve; if the eliminations leave one team standing that team wins, otherwise the capturing team wins (even if its own home was lost in that step). Deterministic and host-only (`MatchTerritory` step: objective update, then home checks, then `_finish_objective_step`; Bontago-gmu.3). Bots knocking out homes in Elimination: (open: Bontago-1t5.50).
- **Elimination game mode:** the hole and ownership triggers above do not apply; a home flag is knocked out only after the attacker controls it continuously for `TerritoryTuning.capture_hold` (owner 2026-10-12, Bontago-1pi.185). Progress shows on the goal-capture ring (most advanced claim, host-authoritative, replicated) and restarts at zero when the attacker changes. When control is lost, progress fades at `home_claim_decay_rate` (0.25 s per second) and the claim is removed at zero; resumed pressure from the same attacker continues from the faded value (owner 2026-10-12, Bontago-9s9 b). Goal-beacon claims reset at once. An eliminated player's held and next block are cleared and their screen shows a large red "Eliminated by <name>" (plain "Eliminated" if no single eliminator; owner 2026-10-12, Bontago-1pi.186). Elimination defaults to a 5-minute round timer (`MatchConfig.ROUND_TIMER_DEFAULT_MINUTES`; Off selectable); at expiry the surviving team with the largest territory share wins, equal shares share the win (owner 2026-10-13, Bontago-1t5.6 b).
- **Other game modes** (`MatchConfig.GameMode`, 2.7): each replaces the Classic objective; see 2.7.
- **Capture display:** radial rings show the shared hold. A goal no-build zone stays no-build while influence and capture cross it.

### 2.4 Blocks
**Placement cadence:** players act concurrently, each with their own supplied piece; there are no alternating turns. Each fixed interval (`block_timer`) permits one release. Releasing early does not restart the interval: the next piece can be positioned but is release-locked until the next boundary. At expiry the game force-releases only a piece still unspent that interval; crossing a boundary never auto-releases a prepared next piece. Equal shapes across players can occur by chance. Each slot has its own interval timer (`MatchFeed._feed_time_left`, reset to `block_timer` per slot), so boundaries are per player, not global.

**Gift exception (owner 2026-09-29):** after a player drops their held ordinary piece, a gift queued immediately behind it can be activated before the next release boundary. The next ordinary piece then follows the shared clock without an extra ordinary release (`docs/GIFT_REWORK_PLAN.md`).

- **Rigid bodies:** every block is one RigidBody3D with a compound shape of 1 m cube BoxShape3Ds, each shrunk by a 0.02 m margin so neighbors do not jam. Mass 1 per cube; friction 0.8, bounce 0.05.
- **Shapes:** every shape is a `BlockShape` resource (`config/blocks/*.tres`). Shapes: cube, domino, bar3, bar4, bar5, L3, L4, T4, S4, square4 (2×2 flat), slab6 (2×3 flat), pillar (1×1×3 upright), plus5 (flat plus), u5 (flat U), corner4 (3D corner, chiral), stair6, arch5 (upright arch), cube8 (2×2×2), plate9 (3×3 flat). Five-cell and larger shapes were added by owner 2026-10-08. bar4 and bar5 are out of the match bag (`in_match_bag = false`; bag, gifts, bots, preview and Sandbox picker never deal them; owner 2026-10-12, Bontago-1pi.180).
- **Weighted random feed:** per-shape weights in `BlockFeedConfig`, dealt from a bag randomizer (`core/feed/BlockBag.gd`) so no player goes long without a stabilizing shape.
- **Next-block preview:** shows the next piece, its timer and a top-down territory minimap. The queued preview is distinct from the held-but-locked piece. A three-piece preview is a possible option.

### 2.5 Controls & placement feel

**Held block (ghost):**
- The held block is not simulated. It follows the cursor raycast onto the surface under it (disk or existing blocks), hovering `hover_height = 0.3 m` above the first thing it would touch.
- A projected footprint on the ground and a vertical guide line show where it will land (no separate shadow).
- The ghost is tinted in the player's color when the spot is valid and grey whenever it cannot be dropped (outside the player's zone, or waiting for the next window). A distinct timer-locked state stays visible at a legal location. Goal zones show a no-build tint, distinct from physical missing floor. A hatched pattern marks hover over a hole.
- The ghost collides with placed blocks (it cannot pass through a tower) but never pushes them.

**Placement legality:** cast one ray straight down from the ghost's middle and classify its hit point in disk-local territory. The point must be owned by the player's team, outside goal no-build zones, and not a contested or hole point. The whole footprint need not fit. Off-disk or unsupported hits are invalid. Ghost overlap and anti-cheat bounds are separate checks, not footprint territory tests. Code tests the piece's unrotated bottom-centre pivot (`autoload/match/MatchPlacement.gd:234-243`), which equals the middle only for an upright piece; the spec rule is the middle of the piece (open: Bontago-1pi.210).

**Control model (Bontago-mv0.14):** the camera is attached to the held block and follows it (`CameraTuning.follow_block`, smoothed by `follow_lag_seconds`, default 0). Mouse motion moves the block in the disk plane relative to the camera (mouse captured during play and kept moving past the screen edge in every match mode); the wheel raises or lowers it; holding Rotation Mode turns motion into 90° snaps; holding Camera Mode orbits instead. Owner-tuned feel: `follow_pitch_deg` −35, `block_move_sensitivity` 0.015.

| Action | Mouse/Keyboard | Gamepad |
|---|---|---|
| Move block | Mouse motion | Left stick |
| Place (drop) | Left click | A / Cross |
| Raise / lower block | Mouse wheel; PageUp / PageDown held | RB raise / LB lower, held (owner 2026-09-28) |
| Rotation Mode (hold, 90° snap grid) | R | keyboard only |
| Rotate yaw ±90° (tap) | A / S | B (clockwise snap) |
| Rotate pitch ±90° (tap) | W / D | D-pad up / down |
| Rotate roll ±90° (tap) | [ / ] | D-pad left / right |
| Rotate block (tap = snap, hold + drag = free; owner 2026-09-22, Bontago-iry) | Middle mouse tapped snaps 90° yaw; held past the drag threshold, X = yaw about world up and Y = pitch about the camera's right axis (3-DOF) | B snaps 90° yaw; RT held + left stick free-rotates the same 3-DOF way |
| Reset rotation | Home, F, or Q | Y |
| Lock to vertical (hold) | Ctrl | (stick and height are already separate) |
| Camera orbit | Right mouse held + motion; wheel zooms while held (C + mouse is an alias) | Right stick |
| Camera zoom | Z / X | LT held + left stick up (in) / down (out); not while aiming a throw |
| Throw (specials only) | A held throwable gift is aimed with the camera: the arc preview is always shown from the camera forward, and a plain click throws it (owner 2026-10-06, Bontago-1pi.85.29). The host computes the launch from the camera forward only (speed 22 m/s, up ratio 0.35, spawn 8 m back; `SpecialTuning`); a client-sent speed is never trusted. Rocket and Paintball fly a straight line along the same aim | A (ghost_place); no LT needed |
| Focus home / goal (tap = turn, hold = peek; owner 2026-09-28, Bontago-aem) | 1 (home) / 2 (goal) | Back (home) / X (goal) |
| Use gift slot (only with the Gift slot experiment on, 2.8) | G | X |
| Pause / release mouse | Esc | Start |

While a trigger-held modifier (RT free-rotate, LT zoom) is active, the gamepad's left stick drives only that modifier and the ghost cursor does not move (owner controller update 2026-09-28). `GhostTuning.gamepad_cursor_base_speed` is 18.

**Focus home / goal:** in the follow camera, a tap (released before `CameraTuning.focus_hold_threshold_s`) turns the camera yaw so the target (own home beacon, or the next goal beacon, cycling on each press) lies straight ahead of the held block; the player can orbit away afterward. A hold peeks: the camera glides to frame the target (`focus_peek_distance`, `focus_peek_pitch_deg`) while held and glides back on release. The ghost cursor never moves during a peek and gameplay input is suppressed. It falls back to the disk center if no beacon exists. The legacy free camera (`CameraTuning.follow_block = false`: arrow pan, Space-drag, snap 1/2) keeps a single instant snap.

**Rotation:** orientation is an integer index into the 24 axis-aligned cube orientations. Free rotation adds a separate quaternion on top; reset clears it and sets the index to 0, so rotation never drifts.

**Throwing:** the arc preview is shown while aiming; the host computes the launch from the camera aim at a fixed speed (`gift_throw_speed_mps` 22 m/s) and never uses a client-sent speed (`throw_max_speed` 25 m/s is the clamp for other thrown bodies). The release point must be inside the player's own territory.

**Expiry and invalid actions:** an invalid manual click neither drops nor consumes the piece: the game refuses it and the block stays in hand (owner test 2026-09-22). At expiry with the held block outside the player's zone, the block and camera jump to the nearest valid point inside the zone and the block drops there; when no valid point exists, the block is still spawned and thrown off the map (`MatchPlacement`, forced release). A held throwable gift at expiry is thrown along the player's current aim as a manual release would be (owner 2026-10-08, Bontago-1pi.133); other held specials follow their manual-release path. Failed clicks never advance the cadence.

**Experiment toggles (default off, 2.8):** the timer-pause and backlog experiments change forced release at expiry; the backlog experiment also shows its head as NEXT. With every toggle off, behavior is as above. Promoting any experiment to a default is a separate owner decision (Bontago-1pi.18.10).

**Gamepad parity:** every action and menu is usable with mouse and keyboard and with a gamepad, through the Input Map. Camera-relative stick movement, zoom-scaled speed and dead zone, and device-specific prompts are requirements. Multiple local gamepads and split-screen are out of scope.

### 2.6 Gifts & specials
- **Spawning:** probability per placement window, one roll per window for the whole match (owner 2026-09-22, Bontago-4fa): `spawn_chance_per_window` 0.15, live-crate cap `ceil(players / players_per_crate)` clamped to 1..`max_live_crates` (2 per crate, max 4; `GiftConfig`, owner 2026-10-07 and Bontago-1pi.85.58), crates spaced `crate_min_separation_m` (3 m), lobby frequency 0–100 maps to chance 0–0.5. Tuned via F4. Type-specific probabilities exist; per-type enable checkboxes are in the lobby.
- **Start grace:** no spawn roll runs until `GiftConfig.first_gift_delay_s` (10 s) of host play; a skipped roll is not queued. Sandbox and gift-demo matches skip the grace (owner 2026-10-11, Bontago-1pi.85.68).
- **Flight and life (owner 2026-09-29 and 2026-09-30):** gifts descend with parachutes from 18 m at 2 m/s with a small deterministic sway, and appear on the minimap. Any player's held block can capture a gift in the air. On landing, the gift is claimed automatically by the player whose territory owns that point; if unclaimed, the first player to claim that area gets it. A landed unclaimed gift expires after `GiftConfig.life_s` (25 s, owner 2026-09-30, Bontago-sen.2). The host decides and replicates claims; simultaneous midair claims use a deterministic host order (`docs/GIFT_REWORK_PLAN.md`).
- **Claiming and next piece:** a claimed gift is queued behind the held piece (owner 2026-09-29, Bontago-3ow.5). Trial on by default (`QolExperiments.gift_queue_after_next`, F4 toggle; owner 2026-10-11, Bontago-1pi.85.69): the gift becomes the block after next, the ordinary next piece stays, the HUD NEXT label reads `NEXT · +1 GIFT`, a later claim replaces a gift still staged after next, and a gift already next is never displaced. With the trial off, or with the backlog or gift-slot experiment on, a claimed gift replaces the next piece and a later claim replaces an earlier one (the displaced piece is discarded).
- **Activation:** substantial impact activates a special (impulse threshold and 0.4 s arm delay in `SpecialDef`). There is no universal auto-trigger. Whether an explosion's proximity alone activates an untouched special follows each effect's script (a nearby explosion chains into the Jumping Bean). Chain reactions are capped at `max_chain_depth = 4`.
- **Gifts-wide rules (owner 2026-10-05, Bontago-1pi.85):** gifts cannot be rotated and are never recolored with the player color. Only some gifts can be thrown, with one fixed trajectory (`docs/GIFT_EFFECTS_PLAN.md`). Shared behavior (hole punching, explosion impulse, disc force and tilt, radial pull, block spawning) lives in shared effect modules that gifts compose.
- **Holes and gifts (owner 2026-10-12, Bontago-1pi.85.73):** gifts are not destroyed by holes, and a gift may be used (placed, thrown, launched) while its aim point is above a hole or a goal zone. Uncollected crates are removed by no hole logic. A placed or held gift special is never a hole-dissolve candidate (`HoleDissolver.touches_hole`). Over an open hole a held gift whose flat projection is inside the disc is accepted. Plain blocks and the sandbox keep refusing hole and goal-zone points; off-disc is refused for everyone.

| Special | Behavior | Starting tunables |
|---|---|---|
| **Rocket** | Works like the Bomb but detonates on impact with a block, disc or map surface; fuel exhaustion is only a backstop. Flies exactly where the camera aims, at any angle including straight up (owner 2026-10-05, Bontago-1pi.85; 2026-10-06, 1pi.85.34 and 1pi.85.38; direction in `docs/GIFT_EFFECTS_PLAN.md`) | speed 18, radius 3, impulse 14 |
| **Bomb** | Blinks for a few seconds after dropping, then explodes, sending nearby blocks away from the center (owner 2026-10-05) | radius 3.5, impulse 18 |
| **Volcano** | On activation a large volcano rises from the disc at the activation point, stays in place, and erupts blocks at random for at least 20 s (owner 2026-10-05) | orb impulse 6, cone 35° |
| **Earthquake** | Shakes the field and levels existing tilt | 4 s, amplitude 0.25 m / 2.5° |
| **Anvil** | Applies weight to tilt the field | mass 60, tilt impulse by distance |
| **Propeller** | Anvil in reverse: the same disc-tilt coupling with opposite sign; works every time, with no dependence on the block falling asleep (owner 2026-10-05) | lift, duration, coupling |
| **Jumping Bean** | Hops randomly around the board and creates a local hole between hops | hop interval and strength, hole radius and lifetime |
| **Magnet** | Pulls enemy blocks within 8 m toward itself for 3 s | |
| **Freeze** | Makes your own blocks within 6 m static for 20 s | |
| **Glue** | Grants five future placed blocks contact fusion with the disc or any block (details below) | charges 5 (owner 2026-09-30, Bontago-sen.3) |
| **Stackfall** | Rains ordinary blocks in the activating player's color onto the map | 12 blocks, 6/s, 12 m radius, 18 m height, 1.5 m spacing, 600 active-body cap |
| **Paintball** | Thrown gift splashes its owner's color and converts nearby block ownership on impact or fuse | 3.5 m radius, 6 s fuse |
| **Cat** | One per match; a newer activation replaces the previous chase. Disabled (in no gift draw) while the owner rethinks the concept; code and resource stay (owner 2026-10-05) | 15 s, 9 m/s, 25 m pointer range, 0.8 m body radius |
| **Black hole** | Pulls in nearby blocks of all teams (replaced Gravity well, owner 2026-10-02). Captured-block behavior: `docs/GIFT_EFFECTS_PLAN.md` | radius, pull, lifetime |

Each special is a `SpecialDef` resource plus a script.

**Glue (owner roadmap 2026-09-29, Bontago-22y.3; 1pi.85.74):** the Glue gift's impact or fuse refreshes the owning slot to five future drop charges. The activation block does not consume a charge. Each later accepted placement, including a valid relocated auto-drop, spends one charge and fuses that block on actual contact with the disc or another block regardless of owner. Rejected actions, burned auto-drops, throws and effect-spawned projectiles spend nothing. A glued block fuses into one rigid group (a `FusedBody` carrier) with everything its faces touch within `fuse_window_s` of landing; it never breaks. Gift blocks never fuse, a blast pushes a group like one block, groups ignore wind, members keep their look, there is no size cap, and a black hole takes the whole group (owner decisions, Bontago-vxs = a).

**Stackfall (Bontago-22y.1):** seeded positions within the configured area around the activating block, restricted to solid surface and spaced from its other rain blocks. The host spawns ordinary owner-colored blocks over time through the normal registry and snapshot path, skips remaining drops when the active-body cap is reached, and does not count them as player placements.

**Paintball (Bontago-22y.2):** the thrown gift block is the glob. After arming, impact or the fuse triggers a visible splash. The host converts each tracked block whose real collider overlaps the splash radius, regardless of previous owner or team. Conversion changes owner slot, individual color material and territory attribution together; it does not move the block. Each conversion is replicated by net id; clients ignore unknown, invalid or repeated updates.

**Cat (Bontago-22y.13):** activation replaces any prior cat and creates one host-simulated physical body outside the block registry (no territory, no block feed). The activating player's cursor steers a red laser target; the host checks peer ownership, limits range and chase duration, and replicates start/end reliably and poses during the chase. Client cats have no collision body; a match reset removes the cat.

### 2.7 Modes
- **Game modes** (`MatchConfig.GameMode`, selected in the lobby; all share placement, territory and gift rules):
  - **Classic:** the all-goal capture win (2.3). With the match timer set and sudden death on, the timer ends in sudden death; with sudden death off the timer has no gameplay effect (`MatchLifecycle.gd` timer path).
  - **Capture the Flag** (owner decision Bontago-pi8, Bontago-22y.7): each held goal beacon adds score per second to its team; the highest score at the round timer wins, ties share the win. A beacon scores only when held as in 2.3.
  - **Elimination** (Bontago-fim, 22y.8): last team with a living player wins; claims and timer as in 2.3.
  - **Reach the Sky** (Bontago-0tn, 22y.9): a player's record is the highest settled block top along the disk normal; it never falls. The first team whose settled block reaches `NetConfig.build_height_target_m` wins at once (Bontago-1pi.166); otherwise the highest team record at the round timer wins, ties to the team that got there first. `sky_team_sum` (lobby, default off) makes a team's record the sum of its members' records instead of its best member's; the early win still needs one member's own record to reach the target.
  - **Domination** (Bontago-1pi.25): no early win; the largest territory share at the round timer wins, equal shares share the win.
  - Timed modes use `round_timer_minutes` (2–30, default 5) and never run sudden death. Home elimination still ends a match early in every mode.
- **Free-for-all:** 1–8 players, humans and bots.
- **Teams:** 2–4 teams, picked per seat in the lobby (2.8).
- **Sandbox:** no timer and no territory limits. Throwing ordinary blocks is allowed, with a block picker and a menu to spawn specials, plus slow-motion, pause-physics and height-record tools.
- **Tutorial:** 5 short interactive steps: placing, rotating, territory, specials and throwing, and camera.
- **Turn-based** (`MatchConfig.turn_based`, off by default): players take turns; physics settles fully (all bodies asleep, or after 6 s) before the next turn. It is a lobby option, not normal play.

### 2.8 Match settings (lobby)
| Setting | Range | Default |
|---|---|---|
| Game mode | Classic / Capture the Flag / Elimination / Reach the Sky / Domination | Classic |
| Disc size | slider, 50%–175% (Bontago-1pi.107) | 100% |
| Players / bots | 1–8 seats; bots added with the players panel's Add bot button, each with its own Easy/Normal/Hard dropdown (Bontago-1pi.53, 1pi.206) | 4 |
| Teams | Teams toggle; each seat picks team 1–4 or Random (balanced fill at start); same number = same team (Bontago-1pi.53) | Off |
| Block timer | 3–12 s | 5 s (`match_defaults.tres`) |
| Gravity | 0.1×–2× (owner 2026-10-12, Bontago-1pi.179) | 1× of a base raised 1.25× (`lobby_gravity_baseline` 1.4 → 1.75) |
| Goal flags | 1–5 | 1 |
| Gifts | On/Off | On |
| Gift probability per window | 0–100 | 30 (`special_frequency`) |
| Enabled specials | checklist + type weights | all except disabled ones (Cat) |
| Tilt mode | Specials only / Physical balance | Specials only |
| Hole mode | Temporary / Permanent / Off | Temporary (Permanent in Elimination) |
| Match timer (Classic) | Off / 2–30 min (owner 2026-10-03, Bontago-1pi.30) | Off |
| Round timer (timed modes) | 2–30 min; Elimination may be Off | 5 min |
| Sudden death | Off/On | Off (`match_defaults.tres`) |
| Weather / sky theme | `WeatherMode` and `SkyThemeMode` (day, night, dawn, random, cycle) | Changing / Cycle |
| **Experimental toggles** (opt-in only, Bontago-1pi.18; the owner decides after playtest whether any becomes a default, 1pi.18.10). Host-editable checkboxes in the lobby's Advanced rules (clients read-only) and in F4 > QoL; snapshotted at match start | | Off |
| Pause timer on events | a slot's block timer freezes 4 s after any special, or while at least 4 of its blocks move faster than 1.5 m/s; longest pause capped (10 s) | Off |
| Queue expired blocks | an expired held block joins a backlog (2, max 3) and the player gets a fresh block; the forced drop waits until the backlog is full | Off |
| Bigger goal claim radius | goal beacon radius multiplied (2.0, max 4.0) | Off |
| Gift slot | a claimed gift waits in a per-player slot (1, max 3) instead of replacing the next block; no timer runs on a slotted gift; spend it with `use_gift_slot` | Off |

"Gift after next block" (2.6) is on by default and is not part of the experiment group. Lobby layout of the players row is an open decision (Bontago-1pi.159.47).

**Sudden death:** starts when the Classic match timer runs out. Gift probability climbs toward its maximum; the disk edge crumbles inward by 1 m every 10 s; the first player or team to reach the win condition wins; if nobody has when the disk has shrunk to radius 8, the player or team with the most territory wins.

### 2.9 AI bots
The AI runs only on the host and spreads its thinking across frames for multiple bots.

**Placement (V2 brain, default since Bontago-1t5.38; the earlier uniform-sampling brain stays behind `--bot-brain=legacy`):** each time a bot receives a block, a strategy layer picks an intent (race, anchor, finish, hold, defend, strike, plus per-mode siege and area). The bot evaluates 40–120 targeted sites (frontier tip toward the target, own stack tops, strike and defend points) plus a few random ones. Per site it picks the orientation (of 24) with the most reach that passes an analytic stability check (upright at the tip, flat as a tower base). Candidates are scored by intent-weighted terms:
- **Reach** toward the target and measured territory gain from raster samples.
- **Chains and towers cut:** enemy snake joints or towers the site would cut.
- **Exposure** to enemy reach and tip-over risk; wasted overlap inside own land.

**Specials:** targeting follows 2.6's effect types and accounts for launch, leveling, tilt and Bean holes. V2 targets enemy chain joints and towers and its own key towers deliberately (Paintball, Freeze and Glue included).

**Difficulty (owner decision Bontago-1t5.57, 2026-10-14):** the game is about stacking, so no tier builds piles. In the V2 brain every tier uses Hard's mechanics (spots sampled, targeted versus random share, support probes, evaluation depth, pick, think time, reaction delay); Easy and Normal differ only by a slightly larger random aiming error (0.5 / 0.25 / 0.05 m for Easy / Normal / Hard), so their towers fall more often. Strategy and goals (intent set, gift weighting, specials) may differ per tier on top. Profiles: `easy_v2`/`normal_v2`/`hard_v2`; the legacy brain keeps its older profiles.

### 2.10 Presentation
- **Disk:** an opaque, polished, mirror-like metal plate (owner 2026-09-23, Bontago-xtq.11; mirror pass removed 2026-10-07), with sky reflections from the Environment sky and a reflection probe for nearby blocks. A shader draws territory: each player's area is a soft tint in their color with an animated outline; contested areas shimmer; hole edges glow and crackle.
- **Blocks:** one merged solid shape per piece, cel-shaded (banded toon lighting, restrained silhouette outline) with thin dark cell-grid lines drawn by the shader (owner 2026-09-26, Bontago-5h7 Q1; the reference is `docs/art_mockups/08-cel-shaded-home-beacons.png`). Collision and connectivity are unchanged. The lines stay dark; an owner-colour glow is an off-by-default tunable (glow dropped after playtest, Bontago-xtq.39). Camera FOV is a tunable.
- **Sky:** procedural sky with HDRI panorama themes (dawn, sunset, night), cloud layers, weather (storm, rain, snow, fog) and distant horizon scenery; theme and weather come from the lobby (2.8).
- **Effects:** GPUParticles3D for explosions, lava orbs, landing dust and debris. Camera shake scales with impulse and can be turned off in settings. Blocks that fall off leave a trail and fade out.
- **HUD:** timer ring around the next-block preview, current max height in meters, territory percentage per player, special indicator, goal capture ring, minimap (top-down territory texture), chat and scoreboard.
- **Audio:**
  - Impact sounds vary in volume and pitch with impulse and material; stacking gives a rising tick that climbs with height; specials have distinct warning sounds.
  - Music (owner 2026-09-27): a shared two-track menu/lobby playlist and a three-track gameplay playlist. Menu and lobby navigation preserve the current song and quiet interval. Tracks fade in (4 s), play once and fade out (5 s), followed by a random 30–75 s quiet gap; playlists avoid immediate repeats. Adaptive capture-intensity stems are deferred.
  - The custom music folder override and its Options control are disabled (owner 2026-09-27); saved folder preferences remain for possible restoration.

### 2.11 Rule acceptance scenarios
Target scenarios for rule tests; they are not a claim of passed tests.

1. **Early release:** player A releases during a window and can orient the next piece but cannot release it until the next window. Player B keeps playing independently. Expiry forces exactly one unspent piece, never a prepared future piece.
2. **Collapse without input:** move or topple a tower and issue no placement. Its influence updates promptly; disconnected capture progress resets.
3. **Local height:** raising a distant tower does not enlarge every short tower's influence; each radius comes from that block's own height.
4. **Goal exclusion versus capture:** a point inside a goal's no-build zone refuses placement even if owned. Influence can still cover its flag base. No floor is removed solely because it is a goal zone.
5. **Point legality:** a wide piece centered at a legal ray hit is not rejected only because a corner crosses a territory border. This is distinct from spawning interpenetrating bodies or invalid network poses.
6. **Severed route:** raw circles form a graph, but enemy or contested area cuts its only corridor. Goal coverage beyond the cut does not complete capture.
7. **Shared hold:** all goal bases covered for less than `capture_hold`, then one is lost: reset. Continuous coverage for `capture_hold` wins. Solver index changes without a geometric break do not reset progress.
8. **Overlap holes:** opposing influence opens a hole after `hole_delay`. Temporary restoration and permanent erosion are tested separately. A winner-takes-point border (the `OFF` mode) is not an overlap hole.
9. **Mode and network agreement:** normal play, host validation, client preview and bots use the same cadence and legality contract.

---

## PART 3 — Technical architecture

### 3.1 Stack
- **Engine:** Godot 4.6 or newer (developed on 4.7.2), stable. `physics/3d/physics_engine = Jolt Physics`.
- **Renderer:** Forward+, with a Low graphics preset that turns off SSR, SSIL and volumetrics.
- **Language:** GDScript with static typing everywhere (`untyped_declaration` is an error; `res://addons` exempt).
- **Tests:** GUT 9.6.1 for pure-logic unit tests (territory math, connectivity, win check, block feed); benchmarks in `tests/bench/`.
- **Platforms:** Windows, Linux and macOS desktop, distributed through Steam.
- **Plugins:** GodotSteam and GUT only, in `res://addons/`, versions pinned.

### 3.2 Project layout
```
res://
  project.godot
  autoload/              # Events (signal bus), Settings, Net, Match (+ match/ state-machine parts), Sfx, Rumble, ...
    match/               # MatchLifecycle, MatchFeed, MatchPlacement, MatchTerritory, MatchGifts, MatchStats, MatchWeather, ...
  config/                # Resource scripts + .tres: MatchConfig, PhysicsTuning, TerritoryTuning, NetConfig,
                         #   CameraTuning, GiftConfig, ... blocks/*.tres, maps/*.tres, specials/*.tres
  core/                  # pure logic, no scene tree, unit tested
    territory/           # TerritorySolver, InfluenceCircle, TerritoryRaster, TerritoryGroups, CellGrid
    feed/BlockBag.gd
    rules/               # WinChecker, PlacementRules, *Objective (game modes), TeamAssigner, MatchPhase, ...
    blocks/ gifts/ net/ physics/ ai/ weather/ ...
  game/                  # Field, Block, BlockRegistry, GiftCrate, GhostPreview, PlayerController, BotController,
                         #   CameraRig, StableBlockManager, HoleDissolver, Sandbox, Main (+ specials/, world/)
  net/                   # SnapshotSync, Interpolator, LanDiscovery, MatchNet, SteamClient, UpnpBackend, ...
  ui/                    # MainMenu, Lobby, HUD, OptionsMenu, PauseMenu, Tutorial, ResultsScreen, Minimap, ...
  vfx/, sfx/, shaders/   # territory, block, hole-edge shaders and effects
  tests/                 # unit/, bench/
  tools/                 # build-time and agent scripts (not part of the running game)
```

### 3.3 Territory & holes implementation
- **Data:** `TerritorySolver` takes `(owner_team, center2D, radius)` circles plus home circles and returns connected groups per team.
  - Union-find over overlapping circles finds candidate connections. It does not prove a continuous path after an opponent or contested region removes a connecting neck; final owned-area connectivity must be checked for capture, and a pre-contest group id is not sufficient.
  - A spatial hash grid (see `TerritoryTuning` cell-size decision) avoids checking every pair.
- **Rate:** the host solves continuously at `solve_hz` (20) independent of placement events. Replication and render cadence are separate; smooth visuals must not hide stale authoritative rules.
- **Raster map** (`core/territory/TerritoryRaster.gd`): a `territory_res × territory_res` grid (256 S, 384 M, 512 L) in disk-local Cartesian space. Each pixel stores owning team, contested flag or hole flag; fill each group's circles; pixels with more than one team are contested. A separate float array accumulates each pixel's contested time toward `hole_delay`.
- **Rendering:** outlines are smooth and circle-derived; enlarging a coarse nearest-sampled raster cannot recover a curved boundary (interpolation, analytic circles or a field shader are all acceptable). Visual ownership, legal placement and capture stay aligned at borders; GPU-only apparent ownership does not permit building. Discard floor pixels only for actual physical holes, never for goal no-build zones.
- **Physics holes:** the disk's collision is built from a square grid of `cell_size = 1.0` BoxShape3Ds clipped to the disk, in one body. Holes are visual voids with solid collision (2.2); blocks touching an applied hole cell dissolve (`game/HoleDissolver.gd`). Hole toggles are batched and sleeping blocks above changed cells wake.
- **Placement validation:** one downward ray and the hit-point test in 2.5. A grid may cache ownership; it never turns the rule back into a full footprint check. The host also checks interval eligibility and rejects duplicate releases for the same interval and piece.
- **Win check:** final owned connectivity plus simultaneous all-goal coverage and the shared hold (2.3), via `core/rules/WinChecker.gd` and the mode objectives. A cached pre-contest group label is not a substitute.
- **`OFF` mode borders:** local height-weighted, mutually exclusive borders using an additively weighted distance field (`radius - distance`), not a true power diagram. A taller circle can swallow a smaller one entirely when the radii differ by more than their separation. Complete engulfment is possible; an exact tie on a cell goes to the lower team id; circles cut off from a living home exert no influence; cells outside every anchored circle are unowned (`TerritoryRaster._argmax`; host computes, clients mirror the replicated raster; Bontago-gmu.3). `OFF` is not the default.

### 3.4 Networking
Gameplay code talks only to Godot's high-level `MultiplayerAPI`, never to a transport. `autoload/Net.gd` picks the transport.

| Transport | Used for | Implementation |
|---|---|---|
| **Steam** (default online) | Internet play with friends, invites, lobbies, NAT traversal via Valve's relay | GodotSteam plus `SteamMultiplayerPeer` (`net/SteamClient.gd`). Lobbies store match settings as lobby data; friends join through the overlay invite or Join Game. |
| **ENet** | LAN (auto-discovery), direct IP, local multi-instance tests, headless bot tests | `ENetMultiplayerPeer` |

- **Development app ID:** Steam test app 480 in `steam_appid.txt`; a real app ID is needed before release. The ordinary local run skips Steam init (test app 480's Steam Input intercepts controller events); `--steam-online` or `--host-online` initializes it.
- **Steam startup:** if Steam is not running, LAN and direct IP still work; online menu entries are hidden with a notice.
- **Version check:** connections are refused when the build version differs, compared on lobby join and in the ENet handshake.
- **Internet play without Steam (owner 2026-10-10):** a non-Steam ENet host opens its UDP port with Godot's built-in UPnP (worker thread; mapping removed when hosting stops and at quit; `net/UpnpBackend*.gd`). The lobby shows a join code (IPv4 + port, `XXXXX-XXXXX`, `core/net/JoinCode.gd`); the Join page's address field accepts IP[:port] or a join code. If the router refuses, the lobby says so and suggests Steam or a manual UDP forward. IPv4 only; no relay.
- **Anti-cheat:** out of scope beyond the host checking every intent (friends-only game).

**Model:** host-authoritative listen server; the host is also a player. **Only the host simulates physics.** Clients freeze every synced RigidBody3D (kinematic) and move them by interpolating snapshots. Deterministic lockstep is not an option (Jolt determinism is not guaranteed).

**Channels:** reliable RPCs carry lobby, match config, block spawn/despawn, special events, territory raster diffs (5 Hz, `NetConfig.raster_diff_hz`), win and end, and chat. Body snapshots are unreliable sequenced packets on their own channel (tagged with a sequence number when the peer lacks channels).

**Client → host intents** (`@rpc("any_peer", "call_remote", "reliable")`, checked on the host): `request_place(slot_id, pos, orient_index, free_quat)`; `request_throw(...)`, where the host computes the launch from the aim (2.5) and never trusts a client speed; `update_cursor(pos)` (unreliable, 15 Hz, other players' ghosts). The host checks territory, the timer and the slot, then spawns the block. The client shows the ghost immediately and a reject effect if refused.

**Snapshots** (`net/SnapshotSync.gd`, `core/net/Quantize.gd`):
- 30 Hz (`NetConfig.snapshot_hz`).
- Per body: `net_id: u16`, position quantized to int16 per axis over map bounds (X/Z about 2 mm; Y spans the kill plane up to the Reach the Sky target plus margin, 198 m by default, about 3 mm per step; accepted, Bontago-1pi.165), rotation as a 48-bit smallest-three quaternion, and a sleeping flag.
- Only awake or changed bodies are sent; a full keyframe covers sleeping bodies every `keyframe_interval` (2 s). Disk tilt quaternion and offset ride every snapshot. Packets split to stay under about 1200 bytes.

**Client interpolation** (`net/Interpolator.gd`): render about 100 ms behind the host (`base_interp_delay_ms`, adapting between 50 and 300 ms to measured jitter), interpolating between surrounding snapshots; extrapolate at most 100 ms when late.

**Late join / reconnect:** full world state sent in chunks (bodies, territory raster, match state); match time pauses while a player joins in lobby-only mode; mid-match joins can be enabled in settings (open: Bontago-8or; the raster full-keyframe path exists, reconnect and late join are not complete).

**LAN discovery** (`net/LanDiscovery.gd`): the host broadcasts `{game, version, name, players, max, map, port}` once per second over UDP to 255.255.255.255 on port 47777; clients list games; direct IP is the fallback. Default game port 47778 (`NetConfig`).

**Testing:** run 2–4 instances via the editor's Customize Run Instances; `--headless-host --bots=N` runs automated bot matches for soak tests.

### 3.5 Physics tuning (Jolt)
- **Tick rate:** 60 physics ticks per second with physics interpolation on.
- **Solver:** Jolt velocity and position iterations raised from defaults (start 10 and 4), tuned on a 40-block tower benchmark.
- **Sleep:** bodies sleep after 0.5 s below the speed thresholds; they wake when the disk tilts, something nearby explodes, or the hole cell under them changes.
- **Stable-block optimization:** a block asleep for more than 20 s and touching no awake body is switched to `freeze_mode = STATIC` by the host (`game/StableBlockManager.gd`), and returns to normal on any impulse, tilt or change in the cells under it; tilting the disk wakes all frozen blocks in the tilted region. A block that stays awake but within 5 mm (and a small rotation threshold) of the pose its still window started in for 5 continuous seconds, with no fast-moving block next to it, is frozen the same way (`settle_freeze_*` in `PhysicsTuning`, master toggle `settle_freeze_enabled`; owner 2026-10-09, Bontago-e7o; 20 s lowered to 5 s, owner 2026-10-12, Bontago-1pi.176; `core/physics/SettleTracker.gd`). Catch-up physics steps per frame are capped at 2 (`catchup_*`; F4 toggle restores 8).
- **Continuous collision:** Rockets, lava orbs, thrown specials and any body faster than 15 m/s use continuous collision detection.
- **Body limits:** `max_active_blocks = 600`; beyond that, the lowest-influence blocks that are off the disk or fully buried are removed first with a visible dissolve. Explosion chains are capped (2.6).
- **Explosions:** `PhysicsDirectSpaceState3D.intersect_shape` (sphere), `apply_impulse` with falloff `(1 - d/r)^2`, clamped per body to `max_explosion_impulse`, waking hit bodies.
- **Tilt:** `SPECIALS_ONLY`: the disk is an `AnimatableBody3D` with `sync_to_physics = true` driven by a critically damped spring (`TiltTuning`); blocks resting on it are carried. `PHYSICAL_BALANCE`: a RigidBody3D pinned at the fulcrum by a `Generic6DOFJoint3D` or `ConeTwistJoint3D` with a restoring angular spring.
- **Gravity:** the default is multiplied by the match setting; base gravity is raised 1.25× (owner 2026-10-12, Bontago-1pi.179; 2.8).
- **Materials:** disk friction 0.9; blocks per 2.4; specials vary (the anvil is 1.0).
- **Benchmarks** (`tests/bench/`): a 40-block tower stands for 60 s with no jitter; 300 blocks falling at once hold at least 120 fps on a mid-range PC; a chain of 5 volcanoes never drops below 60 fps; 144 fps at 1440p with 300 blocks on High on a mid-range GPU (tune as needed).
- **Hardening targets (open: Bontago-8or):** Magnet, Freeze, Glue and Black hole work correctly; a 2-hour bot soak test runs crash-free; Windows, Linux and macOS exports run without crashing; reconnect and late join (3.4).

### 3.6 Key data resources
```gdscript
class_name BlockShape extends Resource
@export var id: StringName
@export var cells: Array[Vector3i]        # cube offsets
@export var weight: float = 1.0           # feed weight
@export var in_match_bag: bool = true     # false removes it from every deal
@export var mesh: Mesh                    # optional custom mesh (else generated)

class_name SpecialDef extends Resource
@export var id: StringName
@export var scene: PackedScene
@export var weight: float = 1.0
@export var enabled_by_default: bool = true
@export var arm_delay: float = 0.4
@export var arm_impulse: float = 6.0
@export var params: Dictionary

class_name MatchConfig extends Resource
# all 2.8 settings, serializable to Dictionary for RPC (to_dict / from_dict / sanitize)

class_name PhysicsTuning extends Resource
# 3.5 physical tuning

class_name TerritoryTuning extends Resource
# influence, hole/goal-zone, solve-rate and capture-hold tuning
```
These are illustrative sketches; the resources in `config/` are authoritative.

### 3.7 Match state machine (host)
`LOBBY → LOADING → COUNTDOWN (3 s) → PLAYING → (SUDDEN_DEATH) → END → LOBBY` (`core/rules/MatchPhase.gd`, driven by `autoload/match/MatchLifecycle.gd`).

**Playing loop on the host:**
- **Block feed:** concurrent players with fixed placement windows (2.4). Release eligibility for the interval is tracked separately from the next prepared piece; early release does not reset the window; only an unspent current piece auto-drops at expiry; special substitution follows the resolved queue policy and never grants an extra release.
- **Territory:** recomputed continuously at the solve rate (3.3); diffs go to clients at 5 Hz. Collapse effects never wait for a new placement.
- **Gifts:** the per-placement-window probability contract in 2.6.
- **Win check:** runs every territory update, through the active mode's objective (2.3, 2.7).

---

## PART 4 — Milestones (historical)

Work is tracked in Beads epics, not here. The M0–M8 plan and its old decision record are archived in [docs/archive/SPEC_PART4_MILESTONES.md](archive/SPEC_PART4_MILESTONES.md) and are no longer a live contract; live M8 items are carried in 3.4 and 3.5.
