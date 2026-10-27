# Stackfall — Design and Technical Spec

Stackfall is a physics-based, competitive block-stacking territory game for 1 to 8 players, built in Godot 4.7 (developed and tested on 4.7.2) with Jolt physics. It plays online over Steam, over a LAN, or by direct IP. It was inspired by Bontãgo (Circular Logic).

This document describes the game as built. Part 1 is the game design (rules, controls, content, interface flow). Part 2 is the technical architecture (engine, code layout, networking, physics, configuration, tooling). Sections are numbered (§N.M) so other files can cite them.

Conventions:
- **Scale:** 1 unit = 1 cube edge = 1 m.
- **Tunables:** every number that shapes gameplay lives in a `Resource` under `res://config/` (§2.8). Numbers quoted here are the shipped values of those resources; the resource is authoritative if the two ever differ.
- **Authority:** the host runs the rules and the physics. Clients send intents and mirror state (§2.6).

---

## PART 1 — Game design

### 1.1 Concept

Players drop blocks onto a floating disc. Each settled block claims the ground around it (its **influence**, §1.5). Territory that connects back to a player's **home flag** is usable: blocks can only be placed inside it. Taller stacks claim more, so stacking is how a player grows, defends and attacks. Where two players' territories overlap, the ground becomes contested and can open into a hole. Matches end by one of five objectives (§1.2): capture every goal flag, capture the flag by score, last team standing, reach a height, or hold the most ground.

Players act concurrently, in real time. Everything is physical: blocks topple, slide and fall off the disc, and gift blocks (§1.6) can explode, tilt the disc, pull blocks, rain blocks and more.

### 1.2 Players, teams and modes

**Seats.** A match has 1 to 8 seats (`MatchConfig.PLAYER_COUNT_MIN`/`PLAYER_COUNT_MAX`). Each seat is a human or a bot. Solo matches are allowed. Slot 0 is the host. Each seat has a color from `MatchConfig.player_colors` (eight entries).

**Teams.** With teams off every player is a team of one. With teams on (`TeamMode` TEAMS_2, TEAMS_3 or TEAMS_4), each lobby seat picks team 1 to 4 or Random. At start the host resolves picks into dense team ids (`core/rules/TeamAssigner.gd`). Without resolved picks, slots interleave across teams (`slot_id % team_count`). Teammates place in each other's territory, never contest each other, and share a win. A team's territory color is its lowest slot's color.

**Game modes** (`MatchConfig.GameMode`, chosen in the lobby; every mode shares placement, territory, gift and physics rules):

| Mode | Objective | Goal flags | Timer |
|---|---|---|---|
| Classic | One team holds every goal flag together for `capture_hold` (§1.5). | Yes | Optional match timer; optional sudden death |
| Capture the Flag | Each held goal flag adds score per second to its team; highest score at the round timer wins; ties share the win. | Yes | Round timer |
| Elimination | A home flag falls only after an attacker controls it continuously for `capture_hold`. Last team with a living player wins. | No | Round timer, may be off |
| Reach the Sky | A player's record is the highest settled block top along the disc normal and never falls. First team to reach `NetConfig.build_height_target_m` (100 m) wins at once; otherwise the highest team record at the timer wins, ties to the team that got there first. Lobby option `sky_team_sum` makes a team's value the sum of its members' records (the early win still needs one member to reach the target). | No | Round timer |
| Domination | No early win; the largest territory share at the round timer wins, equal shares share the win. | No | Round timer, never off |

Timed modes use `round_timer_minutes` (2 to 30, default 5; Elimination alone may be 0 = off) and never run sudden death. Home elimination (§1.5) ends a match early in every mode.

**Other ways to play** (from the main menu, §1.10):
- **Sandbox:** runs the real match path with relaxed rules: no timer by default and no territory limits; it skips the loading screen and the countdown, and resting blocks freeze as in a match. A block picker, a menu to spawn specials, slow motion, pause-physics and tower tools (`game/sandbox/`, `config/match/sandbox.tres`).
- **Tutorial:** five short interactive steps — placing, rotating, territory, specials, camera (`config/match/tutorial_config.tres`). It is a one-player match under the real rules, with no weather and only the gifts a lesson teaches; it ends once, when its steps finish or the match ends.
- **Vs Bots:** an offline match with bots.
- **Turn-based** (`MatchConfig.turn_based`, lobby checkbox, off by default): one player acts at a time; physics settles (all bodies asleep, or `TerritoryTuning.turn_based_max_settle_s` = 6 s) before the next turn.
- **Debug entries** (visible only in debug mode): Gift Demo, Tower Topple, Watch Bots (a spectator view of an all-bot match).

### 1.3 Controls

All input goes through the Input Map (§2.9). Every gameplay action has a keyboard/mouse binding and a gamepad binding unless noted. Mouse motion is read directly and is not an action.

**Held block.** The camera follows the held block. Mouse motion moves the block in the disc plane relative to the camera (mouse captured during play); the wheel raises or lowers it; holding Rotation Mode turns mouse motion into 90° snaps; holding Camera Mode (or the right mouse button) orbits instead.

| Action | Mouse / keyboard | Gamepad |
|---|---|---|
| Move block | Mouse motion | Left stick |
| Place | Left click | A |
| Raise / lower block | Mouse wheel; PageUp / PageDown held | RB / LB held |
| Rotation Mode (hold; 90° snaps) | R | none |
| Rotate yaw 90° (tap) | A counter-clockwise, S clockwise | B (clockwise only) |
| Rotate pitch ±90° (tap) | W / D | D-pad up / down |
| Rotate roll ±90° (tap) | [ / ] | D-pad left / right |
| Free rotate | Middle mouse tapped = 90° yaw snap; held and dragged = free rotation (X = yaw about world up, Y = pitch about the camera's right axis) | RT held + left stick |
| Reset rotation | Home, F or Q | Y |
| Lock to vertical (hold) | Ctrl | none |
| Camera orbit | Right mouse held + motion (C held is an alias); the wheel zooms while held | Right stick |
| Camera zoom | Z / X | LT held + left stick up / down |
| Camera reset to start pose | V | Back |
| Use gift slot (Gift slot experiment only, §1.9) | G | X |
| Show scores (hold) | Tab | Right-stick click |
| Chat (keyboard only) | Enter, Keypad Enter or T | none |
| Toggle HUD | F8 | Paddle 4 |
| Pause menu | Esc | Start |
| Screenshot | F12 | Misc 1 |

Notes:
- While RT (free rotate) or LT (zoom) is held, the left stick drives only that modifier and the cursor does not move.
- Focus home / goal (keys 1 / 2, Back / X) is implemented in `game/player/CameraRig.gd` (tap = turn the camera toward the target, hold = peek) but is disabled in the shipped build: `CameraTuning.snap_enabled = false`.
- Debug-only actions: F1 performance overlay, F2 bot-cost overlay, F3 network overlay, F4 tuning panel, and the sandbox hotkeys F5 to F11 and Tab.
- Menu actions: `ui_accept`, `ui_cancel`, menu tab previous/next (`[` / `]`, LB / RB), lobby confirm (Enter, Start), add bot (X), advanced rules (Y), lobby options (O, Back).
- Watch Bots actions: next/previous follow (N, B / shoulders), overview (H, Y), speed (L, D-pad up), pause (P, D-pad down).

**Throwing and launching a gift** is aimed with the camera forward (§1.6).

**Rotation** is an integer index into the 24 axis-aligned cube orientations (`core/blocks/BlockOrientations.gd`). Free rotation adds a separate quaternion on top; reset clears it and sets the index to 0, so rotation never drifts.

**Camera.** Follow camera behind the held block: `follow_distance` 9 m, `follow_pitch_deg` −35°, orbit pitch clamped −80° to 60°, zoom 4 to 100 m, field of view 75° (adjustable 40° to 100°). The legacy free camera (`follow_block = false`: arrow-key pan, Space-drag) is retained but off.

**Gamepad parity.** Every action and menu is reachable with mouse and keyboard and with a gamepad. Several local gamepads and split screen are not supported.

### 1.4 Blocks and placement

**Shapes.** Every shape is a `BlockShape` resource (`config/blocks/*.tres`) listing cube offsets: cube, domino, bar3, bar4, bar5, L3, L4, T4, S4, square4 (2×2 flat), slab6 (2×3 flat), pillar (1×1×3), plus5, u5, corner4 (3D corner), stair6, arch5, cube8 (2×2×2) and plate9 (3×3 flat). bar4 and bar5 are out of the match bag (`in_match_bag = false`): bag, gifts, bots and the sandbox picker never deal them.

**Feed.** Pieces come from a per-player bag (`core/blocks/BlockBag.gd`) weighted by each shape's `weight` and `BlockFeedConfig` (stabilizer shapes `square4`, `slab6`, `cube` guaranteed at least 2 per bag, bag multiplier 2.0), so no player goes long without a stabilizing shape.

**Body.** Each block is one `RigidBody3D` with a compound shape of 1 m cube `BoxShape3D`s, each shrunk by a 0.02 m margin. Per cube: mass 2.0, friction 0.85, bounce 0.4, linear damping 0.1, angular damping 0.15 (`PhysicsTuning`). Vertical rebound is damped by 0.3 on the step a bounce happens.

**Placement cadence.** There are no alternating turns. Each player has their own interval timer of `block_timer` seconds (3 to 12, default 5; `MatchFeed._feed_time_left`). Each interval permits exactly one release. Releasing early does not restart the interval: the next piece can be positioned immediately but is release-locked until the next boundary. At expiry the game force-releases only a piece still unspent that interval. Equal shapes across players can occur by chance.

**Gift exception.** A gift queued directly behind the held piece can be activated before the next boundary after the player drops the ordinary piece; the next ordinary piece then follows the shared clock without an extra release.

**Held block (ghost).** The held block is not simulated. It follows the cursor ray onto the surface under it (disc or blocks), hovering `hover_height` = 0.3 m above the first thing it would touch. A footprint on the ground and a vertical guide line show where it will land. The ghost is tinted in the player's color when the spot is valid, grey when it cannot be dropped (outside the player's zone, or waiting for the next window), has a distinct locked state, a no-build tint over goal zones, and a hatched pattern over a hole. The ghost collides with placed blocks but never pushes them.

**Placement legality** (`core/rules/PlacementRules.gd` `validate_point`, called from `autoload/match/MatchPlacement.gd`): cast one ray straight down from the horizontal centre of the held piece's rotated bounds (the point the ghost is parked under the cursor; the client preview runs the same code) and classify the hit point in disc-local territory. For an upright or yaw-only piece this equals the bottom-centre pivot; for a tilted or rolled piece it can sit 1-2 m from it. Placement, throw and auto-drop relocation all use this point, and a gift, which spawns upright, is judged upright. The spawned body still uses the pivot as its origin: relocation finds the nearest valid point for the centre and subtracts the pivot-to-centre shift, and `placement_relocated` reports the centre. The point must be owned by the player's team, outside every goal no-build zone, and not a contested or hole point. The whole footprint need not fit. Off-disc or unsupported hits are invalid. Refusal reasons: `outside_territory`, `contested`, `hole`, `off_disk`, `goal_zone`, `no_block`, `not_your_turn`.

**Waivers.** In the sandbox territory ownership is not checked. A held gift ignores territory ownership and may also be used over a hole or a goal zone; off-disc is refused for everyone.

**Invalid actions and expiry.** An invalid manual click neither drops nor consumes the piece; it stays in hand and the cadence does not advance. At expiry with the held block outside the player's zone, the host relocates the drop to the nearest valid point (spiral search, `auto_drop_search_step` 1 m up to `auto_drop_search_max_radius` 12 m). When no valid point exists, the block is spawned and thrown off the map (`reject_impulse` 30, `reject_upward_fraction` 0.35). A held gift at expiry follows its manual-release path (a throwable gift is thrown along the player's last aim).

**Host checks.** The host also refuses duplicate releases for the same interval and piece (`feed_seq`, §2.6).

### 1.5 Territory and scoring

**Influence.** Each settled block of a player produces a circle centered on its center of mass, projected onto the disc plane. With `h` the height of the block's top above the disc along the disc normal, the radius is `r = min(influence_base + h * tan(40°), influence_max_fraction * field_radius)` with `influence_base` 1.5 and `influence_max_fraction` 0.6 (`TerritoryTuning`, `core/territory/InfluenceCircle.gd`). In every hole mode, a same-team block circle completely inside a larger retained one is dropped before the circle budget; home circles are never dropped (it cannot change the result). Moving the disc and a resting tower rigidly together does not change relative heights.
- A block is **settled** when its linear speed is below 0.15 m/s and its angular speed below 0.3 rad/s for 0.5 s (`PhysicsTuning`).
- Circles update continuously: the host re-solves at `solve_hz` = 20, so a collapse or removal changes territory without waiting for another placement.
- A block belongs to the player who placed it, permanently. A block placed on an opponent's tower gives influence to its placer.

**Home flags and homes.** Each player's home flag sits `MapDef.home_flag_edge_inset` = 6 m in from the rim, evenly spaced around the disc (slot 0 at +x, counter-clockwise). While the flag is alive it gives a circle of `home_radius` 6 m.

**Connected territory.** Placement requires influence connected to the player's home. Circles are graph nodes, joined when they overlap (`core/territory/TerritorySolver.gd`: union-find over a spatial hash of `hash_cell_size` 12 m). Circles disconnected from a living home give no usable territory. At most `max_circles` = 400 (largest per team) are kept. For capture, a route must survive in the final owned area, not just the pre-contest circle graph.

**Goal flags and no-build zones.** Classic and Capture the Flag spawn `goal_flag_count` (1 to 5) goal flags. One flag sits at the center; with more than one, all sit evenly spaced on a ring of `0.4 * field_radius`. A disc of `goal_zone_radius` = 4 m around each goal blocks placement only: it is not missing floor and does not block influence or capture.

**Overlap holes.** Where two teams' circles overlap the cell becomes contested; neither may place there. After `hole_delay` = 0.75 s of continuous contest the cell becomes a hole (`HoleMode`):
- `TEMPORARY` (default): a hole closes `hole_close_delay` = 2 s after the contest ends.
- `PERMANENT`: holes never close, so the disc erodes. Elimination defaults to it (the lobby switches to PERMANENT on entering Elimination and back on leaving; the host can still change it).
- `OFF`: no holes. Each cell goes to the single home-anchored circle with the largest `radius − distance` (an additively weighted distance field, not a power diagram); a tie goes to the lower team id; circles cut off from a living home exert nothing; nothing is ever contested.

Holes are a visual void, not an opening: disc collision stays solid. A block whose footprint touches an applied hole cell at disc level dissolves (`HoleDissolveTuning`) and is removed like an edge fall; blocks stacked above land on the void and dissolve too. A block merely above a hole is unaffected. A placed or held gift is never a dissolve candidate. Hole cell toggles are applied in batches of at most `max_cell_toggles_per_frame` = 64.

**Classic win.** Every goal flag's base must lie in the same final controlled area, with an unbroken path to a living allied home, simultaneously for `capture_hold` = 20 s. There is one shared hold: losing any goal or the connecting path resets it; solver group renumbering alone does not. The flag base is the single raster cell at the flag's position (`core/rules/WinChecker.gd`); the Bigger goal claim radius experiment (§1.9) makes cells within the radius vote instead.

**Home elimination.** A player whose home flag is lost is eliminated, and the last surviving team wins.
- In `TEMPORARY` and `PERMANENT` hole modes the trigger is a hole opening under the home flag; in `OFF` it is an enemy area owning the home flag's cell (`autoload/match/MatchTerritory.gd`).
- In Elimination both triggers are replaced by a claim timer: an attacker must control the home continuously for `capture_hold`. Progress shows on the goal-capture ring and restarts at zero when the attacker changes. When control lapses, progress fades at `home_claim_decay_rate` = 0.25 s per second; resumed pressure by the same attacker continues from the faded value.
- A capture and eliminations in the same territory step: the capture latches first, then eliminations resolve; if they leave one team standing it wins, otherwise the capturing team wins.
- Outside Elimination, home flags lost in the same territory step are judged together after any capture: if one team is left it wins; otherwise the capturing team wins if a capture latched in that step; otherwise, if none is left, the largest territory share among the teams that lost a flag wins (equal shares: the lowest team index).
- An eliminated player's held and next block are cleared and their screen shows a large red "Eliminated by <name>" (plain "Eliminated" when no single eliminator).
- A player whose peer is gone longer than `NetConfig.disconnect_grace` = 10 s is eliminated the same way (§2.6).

**Round-timer results.** Elimination: the surviving team with the largest territory share wins, equal shares share the win. Capture the Flag, Reach the Sky and Domination as in §1.2.

**Sudden death** (Classic only; lobby checkbox, default off; starts when the match timer runs out): gift probability climbs toward its maximum over `sudden_death_ramp_s` = 60 s; the disc edge crumbles inward by `sudden_death_shrink_step_m` = 1 m every `sudden_death_shrink_interval_s` = 10 s; the first team to reach the win condition wins; when the disc has shrunk to `sudden_death_tiebreak_radius_m` = 8 m, the team with the largest territory share wins (ties to the lowest team id). With sudden death off, the Classic timer has no gameplay effect.

### 1.6 Gifts and specials

**Spawning.** Gifts are crates that parachute onto the disc. One roll is made per placement window for the whole match (by the lowest living slot, not per player). The chance is `special_frequency / 100 * frequency_to_chance_max` (`GiftConfig`, max 0.5), so the default frequency of 30 gives 0.15. The live-crate cap is `ceil(players / players_per_crate)` clamped to 1..`max_live_crates` (2 per crate, max 4). Crates keep `crate_min_separation_m` = 3 m apart. No roll runs until `first_gift_delay_s` = 10 s of play (skipped in the sandbox and gift demo). Gifts can be switched off in the lobby, and each special can be enabled or disabled there (Cat is off by default).

**Flight and claiming.** A crate descends from `drop_height_m` 18 m at `fall_speed_m_s` 2 m/s with a small sway and shows on the minimap. Any player's held block can catch a crate in the air. On landing, the player whose territory owns that point claims it automatically; if nobody owns it, the first to claim that area gets it. A landed unclaimed crate expires after `life_s` = 25 s. The host decides all claims.

**Queueing.** A claimed gift is queued behind the held piece. By default (`QolExperiments.gift_queue_after_next`) it becomes the block after next; the HUD label reads `NEXT · +1 GIFT`; a later claim replaces a gift still staged after next, and a gift already next is never displaced. With that setting off, or the Backlog or Gift slot experiment on, a claimed gift replaces the next piece.

**Activation.** A substantial impact activates a gift (`arm_impulse` and a 0.4 s `arm_delay` in `SpecialDef`), or its fuse expires (`fuse_timeout_s`). Chain reactions are capped at `SpecialTuning.max_chain_depth` = 4. Gifts cannot be rotated and are never recolored. Gifts are not destroyed by holes.

**Release modes** (`core/gifts/GiftThrow.gd`; the intent carries the camera forward, which the host validates and normalizes; a client speed is never trusted):

| Mode | Gifts | Behavior |
|---|---|---|
| Throw | Bomb, Magnet, Hopper | Ballistic arc at `gift_throw_speed_mps` 22 with `gift_throw_up_ratio` 0.35; an arc preview is shown while held |
| Aimed | Rocket, Paintball | Straight, gravity-free flight along the camera forward |
| Drop | All others | Released in place; a throw is refused |

Balloon, Black Hole, Earthquake, Stackfall and Volcano activate in place at the cursor point with no falling carrier. Anvil spawns `sky_drop_height_m` 14 m above the release point.

| Special | Behavior | Key tunables (`config/gifts/specials/*.tres`) |
|---|---|---|
| Rocket | Flies along the camera aim at any angle; detonates on first contact; fuel is a backstop. Explodes like a Bomb | thrust 60 m/s, fuel 3 s, blast radius 7 m |
| Bomb | Blinks, then explodes, pushing nearby blocks away | blink 3 s, blast radius 8 m, peak 120 m/s |
| Volcano | A volcano rises at the activation point and erupts blocks at random | rise 2 s, erupts 22 s, cone 50°, block cap 600 |
| Earthquake | Shakes the disc and levels existing tilt | `DiscForce` shake, 4 s |
| Anvil | Heavy; lands and tilts the disc toward its side | mass 60 |
| Balloon (id `propeller`) | A team-colour balloon tied to the disc inflates, rises and tilts the disc the opposite way to an Anvil, then pops into confetti | 3 s |
| Hopper (id `jumping_bean`) | Hops randomly and punches a temporary hole at each take-off (no hole under `HoleMode.OFF`) | hop every 1.8 s, hole radius 2.5 m, lives 24 s |
| Magnet | Pulls other players' blocks within 8 m toward itself | pull 6 s |
| Freeze | Makes the activator's own blocks within 6 m static | 20 s |
| Glue | Grants five future placements that fuse on contact (below) | 5 charges |
| Stackfall | Rains ordinary blocks in the activator's color | 28 blocks, 9.5/s, 12 m radius, 30 m height, active-body cap 600 |
| Paintball | Flies straight; splash converts the owning slot and color of nearby blocks | splash 3.5 m, 60 m/s |
| Cat | One per match; a newer activation replaces the old chase; the activator's cursor steers a laser the cat chases | 15 s, 9 m/s; disabled by default |
| Black Hole | Pulls in blocks of all teams, then removes captured blocks | radius 7 m, 6 s |

Each special is a `SpecialDef` resource plus an effect script under `game/gifts/specials/`. Shared behavior (explosion blast, disc force, radial pull, block spawning, hole punching) lives in reusable effect modules.

**Explosions** (`ExplosionTuning`): a sphere query applies a velocity change with falloff `(1 − d/r)^falloff_exponent` (1.5), an upward bias of 0.35 and a per-body clamp `max_delta_v_mps`, waking hit bodies.

**Glue.** The Glue gift sets the activating slot to five drop charges (the activation does not spend one). Each later accepted placement spends one charge and fuses that block, on actual contact, with the disc or any block, whoever placed it. Rejected actions, burned auto-drops, throws and effect-spawned projectiles spend nothing. A glued block fuses within `fuse_window_s` = 0.25 s of landing into one rigid group (`FusedBody`) with everything its faces touch; the group never breaks, has no size cap, ignores wind, and is moved by a blast as one body. Gift blocks never fuse. A black hole takes the whole group.

**Stackfall.** The host spawns blocks at seeded positions on solid ground within the area, spaced apart, through the normal registry and snapshot path; drops stop at the active-body cap and do not count as placements.

**Paintball.** After arming, impact or fuse triggers a splash; the host converts each tracked block whose collider overlaps the radius. Conversion changes the owning slot, color and territory attribution without moving the block, and is replicated by net id (clients ignore unknown, invalid or repeated updates).

**Cat.** The cat is a host-simulated body outside the block registry (no territory). The host checks peer ownership, clamps range and duration, and replicates start and end reliably and poses during the chase; client cats have no collision body.

### 1.7 Maps and field

**Disc.** One map ships: a round disc (`config/match/maps/round.tres`, `MapDef`): `field_radius` 45 m, thickness `disk_height` 0.2 m, cell size 1 m. The lobby's disc-size slider scales the radius by one of six steps (`config/match/disc_size_tuning.tres`): Tiny 50%, Small 75%, Medium 100% (default), Large 125%, Huge 150%, Enormous 175%. Scaling changes lengths (radius, flag positions, influence cap, kill plane) but not block size, cell size or the influence formula.

**Tilt** (`MatchConfig.tilt_mode`):
- `SPECIALS_ONLY` (default): the disc is an animated body driven by a critically damped spring on its tilt; at most `max_tilt_deg` = 12°, return time constant 4 s (`TiltTuning`). Only specials (Anvil, Balloon, Earthquake) tilt or level it.
- `PHYSICAL_BALANCE`: block weight tilts the disc: the torque of settled blocks about the center feeds the same tilt spring (`physical_balance_torque_gain`).

**Out of bounds.** A body below `kill_plane_y` = −40 m is freed.

**Weather and sky** (host-scheduled, replicated; `autoload/match/MatchWeather.gd`, `config/weather/`, `config/sky/`):
- Weather modes: Off, Storm, Rain, Snow, Fog, Random (one type drawn at start, then constant) and Changing (default: random events with calm gaps, at most one at a time). A single-type mode runs that weather constantly.
- Storm pushes live blocks sideways with a force that is zero below a threshold height and rises to a maximum at a cap height, so tall thin stacks topple first. Rain and snow have their own host-side effects. A weak always-on Breeze of short local gusts (`config/breeze/breeze.tres`) pauses spawning while a storm is active.
- Sky themes: Day (locked sunset), Night, Dawn, Random (host picks one of the three) and Cycle (default: a running day/night cycle). The host resolves the theme and variation seeds so every peer shows the same sky.

### 1.8 Bots

Bots run only on the host and spread thinking across physics ticks under a per-frame budget (`think_frame_cap_us`). A bot uses the same authoritative `request_place` and `request_throw` as a human.

**Placement.** For each block it receives, a strategy layer (`core/ai/BotStrategy.gd`) picks an intent: Race, Anchor, Finish, Hold, Defend, Strike, Siege (the Elimination default) or Area (the Domination default; Capture the Flag defaults to Race and Reach the Sky to Anchor on the bot's tallest stack). It evaluates `candidate_count` = 110 sites (frontier tip toward the target, own stack tops, strike and defend points, plus random ones), picks per site the orientation (of 24) with the most reach that passes an analytic stability check, and scores candidates with intent-weighted terms: reach, area gain, chains or towers cut, exposure, tip-over risk, waste and weather hazard. Specials are targeted by `core/ai/BotSpecialPlanner.gd`.

**Difficulty** (`config/bots/bot_tuning.tres`; each bot has its own Easy / Normal / Hard setting in the lobby). All three tiers use the same search and timing (110 candidates, 9 stability probes, reaction delay 0.2 s). They differ in aiming error and strategy:

| | Easy | Normal | Hard |
|---|---|---|---|
| Aim noise | 0.5 m | 0.25 m | 0.05 m |
| Intents | all except Hold, Defend, Strike | all except Strike | all |
| Uses specials | no | yes | yes |
| Gift claim scale | 0.25 | 1.0 | 1.0 |
| Threat lookahead | 0 m | 0 m | 3 m |

A stacking placement must keep every centre-of-mass margin (the new piece over its support, and the combined load above each level over the level below) larger than the tier's aim noise times `aim_margin_share` (`config/bots/bot_stack_tuning.tres`, shipped 1.0, adjustable from the F4 tuning panel). At 1.0 a bot's own aim error never topples its tower in calm conditions; lower tiers instead find fewer stable sites and build wider and lower (Easy cannot place on a single-cube top).

### 1.9 Match settings

Set by the host in the lobby (`MatchConfig`; ranges are enforced by `MatchConfig.sanitize()` on every config the host adopts).

| Setting | Range | Default |
|---|---|---|
| Game mode | Classic, Capture the Flag, Elimination, Reach the Sky, Domination | Classic |
| Disc size | six steps, 50% to 175% (§1.7) | 100% |
| Seats | 1 to 8; bots added with Add bot, each with Easy / Normal / Hard | 4 |
| Teams | Off, or 2 to 4 with per-seat picks (§1.2) | Off |
| Block timer | 3 to 12 s | 5 s |
| Gravity | 0.1× to 2.0× of the base (base is `lobby_gravity_baseline` 1.75, so the default lobby 1.0× is 1.75× engine gravity) | 1.0× |
| Goal flags | 1 to 5 (Classic and CTF only) | 1 |
| Gifts | On / Off | On |
| Gift frequency | 0 to 100 | 30 |
| Enabled specials | per-special checklist | all except Cat |
| Tilt mode | Specials only / Physical balance | Specials only |
| Hole mode | Temporary / Permanent / Off | Temporary (Permanent in Elimination) |
| Match timer (Classic) | Off, or 2 to 30 min | Off |
| Round timer (timed modes) | 2 to 30 min (Elimination may be Off) | 5 min |
| Sudden death (Classic) | Off / On | Off |
| Reach the Sky team sum | Off / On | Off |
| Turn-based | Off / On | Off |
| Mid-match join | Off / On (§2.6) | Off |
| Weather | Off, Storm, Rain, Snow, Fog, Random, Changing | Changing |
| Sky theme | Day, Night, Dawn, Random, Cycle | Cycle |
| Experiments | master switch | On |

**Experiments** (opt-in toggles in `QolExperiments`, default off; host-editable in the lobby's advanced rules and the F4 panel; snapshotted at match start):
- **Pause timer on events:** a slot's block timer freezes for 4 s after any special, or while at least 4 of its blocks move faster than 1.5 m/s; total pause capped at 10 s.
- **Queue expired blocks:** an expired held block joins a backlog (2, max 3) and the player gets a fresh block; the forced drop waits until the backlog is full.
- **Bigger goal claim radius:** goal flag claim radius multiplied (2.0, max 4.0).
- **Gift slot:** a claimed gift waits in a per-player slot (1, max 3) instead of replacing the next block; no timer runs on a slotted gift; spend it with `use_gift_slot`.

### 1.10 Interface flow and presentation

**Flow.** `Boot.tscn` (main scene) loads `Main.tscn` on a worker thread, then:
1. Splash screen, then the main menu.
2. **Main menu:** player name; **Host** (choose Host locally or Host on Steam), **Join** (LAN / IP tab with a game list, a direct address field accepting IP[:port] or a join code, and a Steam lobby tab), **Play Offline** (Vs Bots, Sandbox, Tutorial), **Host Online (Steam)**, **Options**, **Quit**; a Debug page appears in debug mode.
3. **Lobby:** host settings (§1.9), a seat table (name, color, team, ready, bot difficulty), chat, a join code for non-Steam internet hosts, and an Options overlay. The host starts the match (Enter / Start); clients toggle Ready.
4. **Loading screen** until every human peer reports ready, then a 3 s countdown (`countdown_seconds`), then play.
5. **In match:** HUD; pause menu (Resume, Options, Return to lobby — which ends the match for everyone — and Leave match); on the match end a results screen with the winner and per-player stats and the actions Play again and Back to lobby.

**Options** menu tabs: Game (Display, Audio and Rumble sections), Graphics (presets Low / Medium / High plus individual toggles; `config/graphics/presets/`), and Controls (rebinding of actions).

**HUD.** Next-block preview with a timer ring and a minimap (top-down territory), the current height record, territory share per player, goal capture rings, special indicator, scoreboard (hold Tab), chat log and toasts, and an Eliminated banner.

**Visuals.**
- The disc is a polished metal plate. A shader draws territory from the analytic circle list (capped by `TerritoryVisuals.max_shader_circles`): each area is a soft tint in the player's color with an outline; contested areas shimmer; hole edges glow.
- Blocks are one merged cel-shaded shape per piece with thin cell-grid lines and a restrained outline.
- Procedural sky driven by one day/night cycle resource (`config/sky/sky_cycle.tres` keyframes) and a storm overlay that dims the current hour's light by a share and fades the colours in from the current (night-mixed) palette, so night storms stay dark, with clouds that follow the live sky gradient, and weather; GPUParticles3D for explosions, dust and debris; camera shake scales with impulse and can be turned off. Blocks that fall off fade out.

**Audio.** Impact sounds vary in volume and pitch with impulse and material; stacking gives a rising tick that climbs with height; specials have distinct warning sounds. A shared menu and lobby playlist and a three-track gameplay playlist: tracks fade in 4 s, play once, fade out 5 s, then a random quiet gap of 20 to 50 s. A two-stem adaptive mix (calm and tense, crossfading as capture progress passes 0.6) is implemented in `autoload/Sfx.gd` and activates only when a tense-stem file exists (none ships). Capture progress also ducks the music.

**Chat.** Players can send text lines (max 140 characters, rate-limited and de-duplicated, `ChatConfig`); the host validates and replicates them.

### 1.11 Rule scenarios

Target scenarios for rule tests.

1. **Early release:** a player releases mid-window and can orient the next piece but cannot release it until the next window; other players are unaffected; expiry forces exactly one unspent piece.
2. **Collapse without input:** toppling a tower with no placement updates its influence promptly and resets disconnected capture progress.
3. **Local height:** raising a distant tower does not enlarge short towers' influence; each radius comes from that block's own height.
4. **Goal exclusion versus capture:** a point inside a goal's no-build zone refuses placement even if owned; influence can still cover its flag base.
5. **Point legality:** a wide piece whose pivot ray hits a legal point is not rejected because a corner crosses a territory border.
6. **Severed route:** goal coverage beyond a corridor cut by enemy or contested area does not complete capture.
7. **Shared hold:** covering all goal bases for less than `capture_hold` then losing one resets; continuous coverage wins; solver index changes without a geometric break do not reset.
8. **Overlap holes:** opposing influence opens a hole after `hole_delay`; temporary restoration and permanent erosion behave separately; the `OFF` border is not an overlap hole.
9. **Agreement:** normal play, host validation, client preview and bots share one cadence and legality contract.

---

## PART 2 — Technical architecture

### 2.1 Engine and project settings

- **Engine:** Godot 4.7 (developed and tested on 4.7.2), stable build. Renderer Forward+. Language GDScript with static typing everywhere: `debug/gdscript/warnings/untyped_declaration = 2` makes an untyped declaration a compile error (`res://addons` is exempt); `inferred_declaration = 1`.
- **Physics:** `physics/3d/physics_engine = Jolt Physics`, 60 physics ticks per second, physics interpolation on, `max_physics_steps_per_frame` = `PhysicsTuning.catchup_steps_capped` (2). Jolt: `velocity_steps` 192, `position_steps` 4, `sleep_velocity_threshold` 0.03, `sleep_time_threshold` 0.5 s, `body_pair_contact_cache_distance_threshold` 0.0001 (§2.7).
- **Display:** 1280×720 logical canvas, `canvas_items` stretch with `expand` aspect, borderless fullscreen on a fresh launch (windowed in editor runs).
- **Shader globals:** `sky_time`, `sky_sun_dir`, `sky_moon_dir`.
- **Graphics presets:** Low, Medium (default), High (`config/graphics/`); Low turns off screen-space reflections, volumetric fog and many cosmetic effects. A quality governor can adjust load (`core/perf/QualityGovernor.gd`).
- **Platforms:** Windows, Linux and macOS desktop, distributed through Steam (`export_presets.cfg`).
- **Addons:** GodotSteam (installed locally, not vendored) and GUT 9.x (`addons/gut/`). Nothing else without approval.
- **Generated settings:** `tools/bootstrap_project.gd` writes the project settings, the Input Map and the autoload list into `project.godot`; re-run it instead of hand-editing those sections: `godot --headless --path . -s tools/bootstrap_project.gd`.
- **Build version:** `BuildVersion.label()` combines `application/config/version` with a git revision (baked into `build_info.cfg` for exports).

### 2.2 Folder layout and layers

```
res://
  project.godot  export_presets.cfg  .gutconfig.json  README.md  CLAUDE.md
  addons/gut/                  test framework (vendored); GodotSteam installed locally
  autoload/                    boot-time singletons (Events, Settings, Net, Match, Sfx, Rumble, ...)
    match/                     Match autoload's host state-machine parts
  core/                        pure logic, no scene tree, unit tested
    ai/ ambient/ audio/ blocks/ gifts/ net/ perf/ physics/ rules/ sky/ territory/ weather/
  config/                      Resource scripts next to their default .tres, by feature
    audio/ blocks/ (BlockShape .tres, tuning/) bots/ breeze/ gifts/ (specials/) graphics/ (presets/)
    match/ (maps/round.tres) net/ physics/ (presets/) player/ sky/ (noise/) territory/ (disc_surfaces/)
    ui/ weather/
  game/                        scene-tree gameplay and presentation nodes, scenes next to scripts
    main/ field/ blocks/ player/ bots/ flags/ gifts/ (specials/, fx/) sky/ weather/ ambient/
    world/ sandbox/ debug/
  net/                         transport, replication, SnapshotSync and MatchNet autoloads
  ui/                          components/ theme/ hud/ menus/ lobby/ debug/
  shaders/                     territory/ blocks/ sky/ weather/ gifts/ ambient/ include/
  assets/                      audio/{sfx,music}/ models/ textures/{sky,fx}/ ui/
  tests/                       unit/<feature>/  bench/  enet/ (scenario scenes)  support/ (fakes, hooks)
  tools/                       flat: gate, lints, baselines, helper scripts, Godot tool scenes
  docs/                        SPEC.md
```

**Layer rules** (enforced by `tools/lint_layers.py` against `tools/layer_rules.json`):
- `core/` and `config/` hold pure logic and data; they must not depend on the scene tree, on `Match`, `Net`, `net/` or `autoload/match/`.
- `game/` nodes talk to the rest of the game through the `Events` signal bus, the `Match` and `Net` autoloads and, for world code, `MatchContext` — not deep node paths.
- `ui/` connects to `Events` only and never reaches into `game/` nodes by path.
- New scenes sit next to their scripts; shaders go in `res://shaders/`; build-time scripts go in `tools/`.

### 2.3 Autoloads and scene structure

**Autoloads** (order from `tools/bootstrap_project.gd`):

| Name | Script | Role |
|---|---|---|
| StartupPump | `autoload/StartupPump.gd` | Non-singleton; pumps the window while the other scripts compile |
| Events | `autoload/Events.gd` | The global signal bus decoupling systems |
| Settings | `autoload/Settings.gd` | Saved options: graphics preset, window mode, audio, sensitivities, player name, rebinding |
| Net | `autoload/Net.gd` | Session lifecycle, transports, roster, lobby data, chat, ready gates (§2.6) |
| Match | `autoload/Match.gd` | Match state and authoritative entry points; a thin autoload over `autoload/match/` parts |
| SnapshotSync | `net/SnapshotSync.gd` | Body snapshots host to clients (§2.6) |
| MatchNet | `net/MatchNet.gd` | Match RPC surface and wiring (§2.6); its collaborators in `net/match/` hold the logic: `MatchReplication` (spawn, territory, impacts, match start), `MatchWorldReplay` (late-join replay and seat policy), `ClientReplayGate` (client world gate), `SlotCursors` (cursors and AFK auto-drop pose), `GiftWireGuard` (client gift wire checks), with `MatchEventApplier` applying match events |
| Sfx | `autoload/Sfx.gd` | Sound effects and music |
| Screenshots | `autoload/Screenshots.gd` | Screenshot capture |
| Rumble | `autoload/Rumble.gd` | Gamepad haptics |

Support scripts `autoload/UserPaths.gd` and `autoload/LateScripts.gd` are static helpers (not autoloads): `LateScripts` loads the match controllers on demand so the autoload compile closure stays small.

**Match parts** (`autoload/match/`): `MatchFeed` (bags, held and next pieces, interval timers, release locks, expiry), `MatchPlacement` (`request_place`, `request_throw`, validation, spawn, burn), `MatchTerritory` (solve loop, objective update, home checks), `MatchLifecycle` (state machine, slots, countdown, timers, sudden death, elimination, disconnect grace), `MatchGifts` and `MatchGiftActivation`, `MatchStats`, `MatchWeather` with the wind effects, and `MatchContextLive`.

**Scenes.**
- `game/main/Boot.tscn` is the main scene; it loads `Main.tscn` on a worker thread to keep the window responsive. `Main` owns the flow: menu, lobby, loading screen, pause, results, scoreboard, and the match world.
- The match world is `game/main/LocalPlayer.tscn`: one `PlayerController` with `GhostPreview`, the HUD and the tuning panel, plus `Field.tscn` (the disc), `CameraRig.tscn` and `RemoteCursors.tscn`. Every mode plays in it: a mode is a `MatchConfig` (built by `MatchLaunch`) plus optional extras (`ModeExtras`). `game/sandbox/Sandbox.tscn` (the sandbox tools) and `ui/menus/Tutorial.tscn` (the lesson prompts) own no controller; `Main` attaches them to the match world after it is built.
- Pause, chat and the results screen block gameplay and camera input through one `InputGate` (`game/player/InputGate.gd`) held by `CameraRig` and shared with the controller; a match reset clears all three.
- Blocks are `game/blocks/Block.tscn`, created by `BlockFactory`, tracked by `BlockRegistry` (net ids, settled state, per-block influence feed).
- `game/world/MatchContext.gd` is the port world code (fields, specials, presenters, weather effects) uses to reach the running match without naming the `Match` or `Net` autoloads; `autoload/match/MatchContextLive.gd` forwards it to the real autoloads, and tests install a fake.

**Boot paths.** The default run opens the menu. Command-line flags after `--`: `--host`, `--join=<addr>`, `--port=`, `--headless-host` with `--bots=N` (a headless bot match; add `--loop-matches`), `--steam-online` or `--host-online` (initialize Steam), `--sandbox` (the menu's sandbox path), `--mode=`, `--round-timer=`, `--bot-difficulty=`, `--debug` or `--no-debug`, `--soak` and `--soak-fuzz` (debug mode only: the invariant soak monitor and the client intent fuzzer), `--agent-probe` (tool and test runs).

### 2.4 Match state machine

`LOBBY → LOADING → COUNTDOWN → PLAYING → (SUDDEN_DEATH) → END → LOBBY` (`core/rules/MatchPhase.gd`, driven by `autoload/match/MatchLifecycle.gd`).

- **LOADING:** the host announces the match; a loading gate holds until every human peer reports ready (`LoadingReadyGate`); a timeout opens it.
- **COUNTDOWN:** `countdown_seconds` = 3, replicated each second; the sandbox skips it.
- **PLAYING / SUDDEN_DEATH** run these on the host every frame: disconnect grace, the block feed (§1.4), the territory step (§2.5) and gift spawning (§1.6). Sudden death adds the disc shrink and tiebreak.
- **END:** a results payload is built (`MatchStats`, `core/rules/ResultsPayload.gd`) and replicated; players can replay or return to the lobby.
- Disconnect: a slot whose peer leaves keeps its seat for `disconnect_grace` = 10 s; a rejoin with its token inside that window resumes with a full block timer; otherwise the slot is eliminated.

### 2.5 Territory implementation

- **Solver** (`core/territory/TerritorySolver.gd`): takes `(team, center2D, radius)` circles plus home circles and returns connected groups per team via union-find over overlapping circles, accelerated by a spatial hash. Union-find alone does not prove a continuous path once an opponent or contested region cuts a neck, so capture checks final owned-area connectivity. `core/territory/TerritoryCull.gd` removes contained circles before the solver sees them.
- **Rate:** the host solves at `solve_hz` = 20 independent of placement. While any block is still awake, scheduled solves are skipped up to `solve_defer_max_s` = 0.5 s; boards with at least `async_solve_min_circles` = 48 circles solve on a worker thread and apply one frame late. A settled block that moved less than `dirty_move_epsilon` = 5 mm does not dirty the board.
- **Raster** (`core/territory/TerritoryRaster.gd`, `CellGrid.gd`): a square grid at `cell_size` = 1 m (one cell per metre), clipped to the disc. Each cell stores an owning-slot byte and state bits (contested, hole, goal zone). Fills: the legacy fill stamps every circle of every home-anchored group (a cell hit by a second team becomes contested; contested time accumulates toward `hole_delay`); the `OFF` fill takes the largest `radius − distance`. Goal zones are stamped once per match. `MapDef.territory_res` (384 at 100%) is only the size of the overlay texture, not the rule resolution.
- **Rendering:** the overlay shader draws analytic circles (`game/field/TerritoryOverlay.gd`) so outlines are smooth; ownership drawn and ownership enforced come from the same data. Floor is discarded only for physical hole cells, never for goal zones.
- **Disc collision:** one `ConcavePolygonShape3D` (a trimesh with one quad per in-disc cell plus rim walls), built once per map and never rebuilt on a hole change. Holes are applied through `Field.set_hole_cells` and announced; `game/blocks/HoleDissolver.gd` dissolves blocks on hole cells on the host.
- **Win checking:** `core/rules/ModeObjective.gd` is the base class; `ClassicObjective` (wraps `WinChecker`), `CaptureFlagObjective`, `EliminationObjective`, `ReachSkyObjective` and `DominationObjective` implement the modes. `MatchTerritory` runs, in order, the objective update, then the home checks, then finishes the step. Everything is host-only and deterministic; clients mirror replicated state.

### 2.6 Networking

**Model.** A host-authoritative listen server; the host is also a player (slot 0). Only the host simulates physics. Clients freeze every synced `RigidBody3D` and move them by interpolating snapshots. Lockstep is not used. Gameplay code uses only Godot's high-level `MultiplayerAPI`; `autoload/Net.gd` chooses the transport.

| Transport | Used for | Implementation |
|---|---|---|
| Steam (online) | Friends, invites, lobbies, relay | GodotSteam + `SteamMultiplayerPeer` (`net/SteamClient.gd`); lobbies carry match settings as lobby data (up to `steam_lobby_data_max_bytes` 8192) |
| ENet | LAN, direct IP, tests, headless bot matches | `ENetMultiplayerPeer`; game port 47778 |

- **Steam startup:** development uses test app id 480 (`NetIds.STEAM_APP_ID_EXPECTED`). The ordinary local run skips Steam init (the test app's Steam Input intercepts controller events); `--steam-online` or `--host-online` initializes it. If Steam is not running, LAN and direct IP still work and online entries are hidden.
- **Version check:** the build version is compared on lobby join and in the ENet handshake (`_rpc_handshake`); a mismatch is refused (`JoinError.VERSION_MISMATCH`). Other refusals: timeout, server full, match in progress, refused, transport.
- **Wire contract:** `tests/unit/net/test_rpc_contract.gd` pins every RPC and packet layout of the six replicated nodes against `tests/unit/net/fixtures/rpc_contract_golden.json`. An intended wire change bumps `application/config/version`, adds a history entry and regenerates the golden with `tools/gen_rpc_golden.tscn` in the same commit; existing history entries never change.
- **Internet without Steam:** a non-Steam ENet host opens its UDP port with Godot's UPnP on a worker thread (`net/UpnpBackend*.gd`, `UpnpRunner.gd`, `UpnpConfig`); the mapping is removed when hosting stops. The lobby shows a join code (IPv4 + port as `XXXXX-XXXXX`, `core/net/JoinCode.gd`); the Join page accepts IP[:port] or a code. IPv4 only, no relay.
- **LAN discovery** (`net/LanDiscovery.gd`): the host broadcasts `{game, version, name, players, max, map, port}` once per second over UDP to 255.255.255.255 on port 47777; clients list games and drop entries after `discovery_entry_ttl` = 3 s.
- **Anti-cheat:** none beyond the host validating every intent (a friends-only game).

**Channels.** Reliable RPCs carry lobby, roster, match config, spawn and despawn, special events, territory, results and chat. Unreliable RPCs on separate channels carry body snapshots (channel 1) and cosmetic traffic (cursors, impacts, cat state; `CURSOR_CHANNEL`).

**Client to host** (`@rpc("any_peer", "call_remote", ...)` in `net/MatchNet.gd` and `autoload/Net.gd`; the host derives the slot from the sender's peer id and never trusts a client-supplied slot):
- `net_request_place(slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq)`: the host ignores `auto_drop` from the wire (only the host's own timer may relocate); a negative `feed_seq` is refused.
- `net_request_throw(slot_id, origin, orientation_index, free_quat, velocity, feed_seq)`: `velocity` carries the camera forward; the host validates and normalizes it and derives the launch from `core/gifts/GiftAim.gd`.
- `net_request_use_gift_slot`, `net_update_cursor` (unreliable, `cursor_hz` = 15, includes aim), `net_cat_target`, `net_request_replay`, `net_request_return_to_lobby`.
- Lobby and session intents: handshake, ready, loading ready, seat preference (color and team, rate-limited), chat submit, pong. Every one is accepted only from a known (roster or seated) peer and passes a per-peer flood limit (`NetConfig` buckets); per-peer limiter state is dropped when the peer leaves, is kicked or disconnects, so a never-handshaked peer allocates nothing.

**Intent checks.** The host checks the match state, slot range, `feed_seq` (a replay or a double click is refused), the seat's home alive, the turn gate, the held piece, the one-release-per-interval lock, then pose well-formedness and placement legality (§1.4). Refused deliberate placements consume nothing.

**Host to client:** `net_match_loading`, `net_match_start(config, roster, replay_id)`, `net_match_event`, `net_block_spawned`, `net_block_despawned`, `net_territory`, `net_cursor`, `net_block_impacts`, `net_snapshot`, plus weather, snow and breeze state RPCs and the lobby, roster and chat RPCs.

**Match events.** The host's match-event subscribers (`net/match/MatchEventMirror.gd`) turn `Events` into `net_match_event` sends: a broadcast, or a reply to the owning peer only (placement refusals and relocations). A client checks every event against its argument-shape row in `core/net/MatchWireEvents.gd` (arity and types, with `core/net/WireLimits.gd` clamps) before `net/MatchEventApplier.gd` applies it through the replica port; a malformed or unknown event is refused without a script error and changes nothing.

**Snapshots** (`net/SnapshotSync.gd`, `core/net/Quantize.gd`):
- Sent at `snapshot_hz` = 30 as unreliable packets of at most `max_packet_bytes` = 1200, split into independently decodable fragments (78 bodies each).
- Header 12 bytes (version, u16 sequence, fragment index and count, u32 host time in ms, flags, body count); the first fragment of a snapshot adds a 12-byte disc state (quantized offset and tilt quaternion).
- Body record 15 bytes: u24 `net_id`, position as three u16 over the match's position bounds (about 2 mm in X/Z; Y spans `pos_min_y` −48 to the Reach the Sky target plus margin, about 3 mm), rotation as a 48-bit smallest-three quaternion with a sleeping flag.
- Only awake or changed bodies are sent (resend epsilons 5 mm and 0.5°, measured against the last *sent* pose); a full keyframe every `keyframe_interval` = 2 s covers sleeping bodies. A body whose sleep flag changed since it was last sent is resent that tick with its new flag, even inside the resend epsilons; otherwise the host drift-tests a sleeping body only when it was never sent or the disc moved this tick (`core/net/SnapshotSelector.gd`); a sleeping body moved with none of those is resent by its keyframe slice.
- Clients interpolate only active bodies: a body rests once its newest sample is asleep, render time has passed it and its correction offset has decayed; its transform is written once on entering rest, and an awake or moved sample makes it active again. A newly replicated body starts from its spawn pose: the client takes that pose as a first sample one snapshot interval less a physics tick before its first real sample (never extrapolated from), so it neither jumps ahead nor stalls while render time catches up.

**Interpolation** (`net/Interpolator.gd`): render `base_interp_delay_ms` = 100 ms behind the host (adapting between 50 and 300 ms to jitter), interpolate between surrounding snapshots, extrapolate at most 100 ms. Clients write transforms in `_physics_process` so they do not fight physics interpolation.

**Territory replication** (`net_territory`): the host sends the owning-slot and state bytes of the raster (a full keyframe, or a diff when changed cells are under `raster_full_threshold_fraction` 0.35 of the grid; compressed) together with the analytic circle list (`core/net/CircleWire.gd`) and capture state, at `raster_diff_hz` = 5. A client's raster is a mirror: the win check is host-only.

**Impacts.** The host batches block impact events (`core/net/ImpactWire.gd`, `impact_batch_hz` 30, rate-limited) so clients can play impact sounds and puffs.

**Late join and reconnect.** A peer that drops keeps its seat for `disconnect_grace`; rejoining with its token (`REJOIN_TOKEN_BYTES` 16) inside that window restores it. With `allow_mid_match_join` on, the host admits a new peer mid-match (an open human seat, else a spectator) and replays the world to it in chunks (bodies, territory, match state) with an acknowledgement (`replay_ack_timeout` 15 s; a joiner that never acks is kicked once). The ack is rate-limited per peer, and the joiner's intents are refused until it has acked. With it off the match is lobby-only.

**Network simulation.** `NetConfig.sim_lag_ms`, `sim_jitter_ms`, `sim_loss` and the preset values add artificial lag, jitter and loss for testing (`core/net/NetSim.gd`).

### 2.7 Physics

- **Tick rate** 60 Hz with physics interpolation; catch-up steps per frame capped at 2 (`PhysicsTuning.catchup_*`; the F4 panel can restore 8).
- **Solver:** Jolt velocity steps 192 and position steps 4. The velocity count is high because a column of N cubes is a chain of N contacts and needs iterations proportional to its height to distribute support load; at 192 a 40-cube tower settles and sleeps. The contact-cache distance threshold is tightened to 0.0001 m so tall columns do not solve against stale contacts.
- **Gravity:** engine gravity times `PhysicsTuning.gravity_multiplier`, which `start_match` sets to `lobby_gravity_baseline` (1.75) times the lobby's gravity setting.
- **Sleep:** bodies sleep after 0.5 s below 0.03 m/s; they wake when the disc tilts, an explosion hits them, or the cell beneath them changes.
- **Stable-block freeze** (`game/blocks/StableBlockManager.gd`): the host sets a block that has slept for `stable_freeze_delay_s` = 20 s and touches no awake body to static, and releases it on any impulse, tilt or change in the cells under it. A block that stays awake but within 5 mm of the pose its still window started in for `settle_freeze_window_s` = 5 s, with no fast block (above 0.5 m/s) within 1.8 m, is frozen the same way (`settle_freeze_*`, `core/physics/SettleTracker.gd`).
- **Continuous collision:** bodies faster than `ccd_speed_threshold_mps` = 15 m/s (rockets, orbs, thrown gifts).
- **Body limits:** Stackfall, Volcano and Cat each stop spawning at a 600-body cap. There is no global cap on placed blocks.
- **Explosions:** per-body delta-v with falloff and cap (§1.6).
- **Tilt:** `SPECIALS_ONLY`: the disc is an `AnimatableBody3D` (`sync_to_physics`) driven by a critically damped spring (`TiltTuning`); blocks resting on it are carried. `PHYSICAL_BALANCE` adds the torque of settled blocks to the same spring.
- **Materials:** disc friction 0.9; blocks per §1.4; specials vary (Anvil mass 60).
- **Benchmarks** (`tests/bench/`): a 40-block tower stands without jitter; `bench_rain` drops 300 blocks at once; `bench_specials_chain`, `bench_snapshot` and `bench_gpu_frame` cover chained specials, snapshot cost and frame time.

### 2.8 Configuration resources

Every tunable lives in a typed `Resource` under `res://config/` (a script plus its default `.tres`). `tools/lint_magic_numbers.py` flags numeric literals in code against a baseline.

| Resource | Content |
|---|---|
| `MatchConfig` | All lobby settings (§1.9) plus player colors and runtime fields; `to_dict`, `from_dict` and `sanitize` for RPC and lobby data. `match_defaults.tres`. Match start duplicates it, never the shared resource |
| `MapDef`, `DiscSizeTuning` | Disc geometry, flag layout, disc-size steps |
| `TerritoryTuning` | Influence, rates, holes, goal zone, capture hold, sudden death, auto-drop |
| `PhysicsTuning`, `TiltTuning` | Block body, gravity, sleep, freeze, tilt spring |
| `BlockShape` | `id`, `cells` (cube offsets), `weight`, `in_match_bag`, optional mesh |
| `BlockFeedConfig` | Bag stabilizers and multiplier |
| `GiftConfig`, `SpecialTuning`, `SpecialDef` | Gift spawning and flight; throw and aim; one def per special (`id`, `weight`, `enabled_by_default`, `throwable`, `aimed_launch`, `activates_in_place`, `arm_delay`, `arm_impulse`, `fuse_timeout_s`, `effect`) |
| `QolExperiments` | The four opt-in experiments and the gift-after-next setting |
| `BotTuning`, `BotDifficultyProfile` and related | Bot search, evaluation, strategy and think-cost budgets |
| `NetConfig`, `ChatConfig`, `UpnpConfig` | Ports, rates, timeouts, snapshot and interpolation settings, chat limits |
| `CameraTuning`, `GhostTuning` | Camera follow, zoom, focus; cursor, rotation and hover feel |
| `GraphicsPreset`, `QualityGovernorConfig` | Graphics settings per preset |
| `AudioConfig`, `RumbleConfig` | Audio, music and haptics |
| `config/ui/*`, `config/sky/*`, `config/weather/*`, `config/territory/*` visuals | Presentation tuning |

### 2.9 Input

- All input goes through the Input Map. No code checks raw keycodes. Every action has a keyboard or mouse binding and a gamepad binding, or is a documented exception (keyboard-only actions such as Rotation Mode, chat and yaw counter-clockwise; pad-only gestures such as RT free rotate).
- The actions are defined in `tools/bootstrap_project.gd` (`_actions()`), which regenerates the `[input]` section. Bindings use device −1 (any gamepad). Stick actions use a 0.15 dead zone, triggers 0.3, buttons 0.5.
- Mouse motion is read directly by `game/player/PlayerController.gd`. Chorded debug bindings (Back + Y for the network overlay, Start + X for the tuning panel, Back + R3 for the performance overlay) are built from existing actions rather than raw buttons.
- Glyph tables (`config/player/InputGlyphTable.gd`) show device-specific prompts; Options > Controls rebinds actions and persists through `Settings`.

### 2.10 Testing and tooling

- **Unit tests:** GUT under `tests/unit/<feature>/`, mirroring the feature tree; pure logic in `core/` is covered by unit tests. `.gutconfig.json` runs everything under `res://tests/`.
  - Targeted run: `powershell -NoProfile -File tools/run_gut.ps1 <script substrings>` (`-Unit <substring>` for one test, `-Path <checkout>` for another checkout).
  - Full run: `python tools/full_gate.py [--path <checkout>]` shards the whole suite across parallel headless Godot processes, re-runs failures alone once, and prints one `FULL GATE GREEN` or `RED` line. A plain serial run is `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`.
- **Lints** (`python tools/lint_all.py` runs them all): `lint_magic_numbers` (literals must live in config), `lint_single_source` (each cross-cutting concept — names, slot colors, input glyphs, labels, gift names — has one home), `lint_ui_components`, `lint_layers` (§2.2), `lint_dead` (unreferenced code) and `lint_instructions`.
- **Project check:** `godot --headless --editor --path . --quit` must print no errors or new warnings.
- **Network scenarios:** `tests/enet/` holds ENet scenario scenes (host plus client in one machine) driven by `tools/run_*_enet.ps1`; `tests/support/` holds fakes and hooks. Manual multiplayer testing uses the editor's Debug > Customize Run Instances (2 to 4 instances).
- **Headless bot match:** `godot --headless --path . -- --headless-host --bots=8` (soak and balance runs); `tools/bot_h2h.py` compares bot tiers.
- **Invariant soak:** `python tools/run_soak.py` runs a headless host plus ENet clients with `--debug --soak` (load and authority scenarios, the client fuzzing refusable intents with `--soak-fuzz`); each process prints `SOAK_*` lines (host/client agreement, authority, territory fresh-solve, physics, memory, tick budget, snapshot bytes), and `tools/soak_report.py` joins them into one `SOAK RESULT PASS|FAIL|INVALID` line. It runs at session close or on an idle PC; it is not a batch gate.
- **Probes and screenshots:** agent and tool runs use `--agent-probe` (random free port, no LAN advertising); `tools/shot.tscn` and `tools/shot.gd` render screenshots.
- **Diagnostics:** the F1 to F4 debug overlays (§1.3) and `tools/triage_log.py`, which groups a long run's log into ranked distinct signatures.
- **Dependency tools:** `tools/dep_graph.py` builds the script dependency graph the layer lint uses.
