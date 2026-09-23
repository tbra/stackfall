# Bontãgo Remake — Design & Technical Spec (Godot 4)

> Hand-off document for Claude Code. Part 1 records historical evidence, not an implementation contract. Part 2 defines the remake's rules. Part 3 describes implementation proposals. Part 4 gives acceptance criteria. Rules/evidence audit: **2026-09-20**.
>
> Each rule is tagged by where it comes from:
> - **[ORIGINAL]** is supported by an identified historical source; it does not imply exact internals or consistency across all releases.
> - **[OWNER]** is the owner's explicit requirement for this remake, even where historical evidence differs.
> - **[REPORTED]** is a player/reviewer account, not developer confirmation.
> - **[RECONSTRUCTED]** is a provisional interpretation of incomplete evidence, not a verified original rule.
> - **[NEW]** is a design decision for the remake.
> - **[OPEN]** requires a decision or verification; existing code is not proof of the intended rule.
>
> **Precedence (owner, 2026-09-20): prioritize original rules where concrete evidence exists.** Such evidence supersedes earlier recollections/reconstructions. Explicit retained remake exceptions (including the owner's confirmed 3-second capture hold) remain exceptions. Otherwise use owner clarifications, then provisional Part 2 designs. Part 3, older plans and completed tests cannot override this rule. Record the source and the displaced assumption whenever applying it.
>
> **Instructions for Claude Code:** Work milestone by milestone (Part 4). Every milestone must be runnable and playable before you start the next one. Put tunable numbers in config resources and never hard-code them. Ask before changing approved gameplay, including [ORIGINAL] rules adopted by the remake. This audit changes documentation, not game code; it does not assert that the working build already conforms.

---

## PART 1 — Research: the original game

### 1.1 Facts
- **Title:** Bontãgo (also written "Bontago")
- **Release:** DigiPen's [game gallery](https://games.digipen.edu/games/bontago) records May 1, 2003. Later releases must not be assumed mechanically identical.
- **Developer:** Circular Logic: Eric Anderson, Jason Bolton, Tristan Hall and Justin Kinchen. The [2004 interview](https://www.gamedev.net/tutorials/industry/interviews/circular-logic-r2060/) identifies Jason as technical director and Eric as graphics programmer; DigiPen's current page labels Eric technical director. Preserve the attribution difference rather than silently choosing one.
- **Awards:** DigiPen confirms the 2004 IGF Innovation in Game Design win and Open Category finalist status. [DigiPen showcase](https://www.digipen.edu/showcase/student-games/bontago).
- **Development:** The team reported seven months plus cleanup, Tokamak physics after trying ODE, and a networking rewrite. [Developer interview](https://www.gamedev.net/tutorials/industry/interviews/circular-logic-r2060/).
- **Tilt:** Ordinary block weight was originally intended to balance the board continuously, but that feature was abandoned; specials tilted the shipped board instead. This supports specials-driven tilt, **not** a particular spring equation, tilt angle or return time. The interview discusses possible future maps, specials and a turn-based mode; these are not evidence that those features shipped. [Developer interview](https://www.gamedev.net/tutorials/industry/interviews/circular-logic-r2060/).

### 1.2 Core rules — evidence and limits

**[ORIGINAL, preserved description]** Home flags supply initial circles around a disk. Players place randomly supplied cube-based shapes within their controlled area. Structure height perpendicular to the disk expands influence; victory requires one continuous area containing all world flags. The preserved text explicitly describes holes at opposing territory overlaps. It does not specify their collision geometry, lifetime or exact ownership formula. [Description mirror](https://fileplanet.download.it/p-18772/Bontago).

**[ORIGINAL, developer explanation]** On March 15, 2004, developer Vulcan/Eric described fixed placement intervals: an early drop gives the next piece for preparation, but it cannot be released until the next interval. Expiry forces release. This is simultaneous real-time play, not players taking alternate turns. The post does not establish network clock synchronization. [Release thread](https://gamedev.net/forums/topic/177069-bontago/).

**Fidelity decision:** the owner's later instruction to prioritize concrete original evidence adopts the documented timer in §2.4 and restores overlap holes as the default target in §2.2. Earlier immediate-timer/no-overlap proposals remain documented alternatives, not the original rules. The 3-second capture hold is an explicitly retained remake exception.

**[ORIGINAL, installed tutorial]** The owner-installed executable advertises version 1.1. Its embedded tutorial confirms timer locking, overlap sinking, height-based influence, allied placement and the all-white-flags objective. Its menu documents a configurable requirement to connect influence to the home flag for dropping. See [installed-file evidence, offsets and hash](ORIGINAL_INSTALL_EVIDENCE.md). This is direct textual inspection, not a gameplay test.

**[REPORTED]** Tower-top ownership tricks, exact default timers and invalid-drop rejection behavior in the earlier draft still lack sufficiently specific evidence. Do not derive an exact height-credit algorithm or auto-drop relocation rule from them.

### 1.3 Gifts / specials — evidence and limits

**[ORIGINAL, preserved description]** Enclosing a randomly dropped gift box awards a special as the next piece; impact activates it. Volcano, earthquake and rocket are named. Exact thresholds, queues, targeting and fuse behavior are not supplied. [Description mirror](https://fileplanet.download.it/p-18772/Bontago).

**[REPORTED]** Contemporary players describe throwing specials beyond territory, normal-block throwing in sandbox, and chain reactions. The review names rockets, volcanoes, earthquakes and a tilting anvil. These accounts do not establish the precise behaviors or numbers in §2.6. [JayIsGames review/comments](https://jayisgames.com/review/bontago.php).

**[ORIGINAL, installed tutorial/menu]** Seven documented types are **DaBomb/Bomb, Volcano, Earthquake, Propeller, Anvil, Rocket and Jumping Bean**. Rocket launches upward and explodes after its fuel is spent; Earthquake helps level the field; Propeller rises and tilts it; Jumping Bean creates a hole between random hops. The earlier homing Rocket, proximity-mine Bomb and horizontal-blowing Fan were unsupported reconstructions. §2.6 now follows the installed descriptions. [Artifact evidence](ORIGINAL_INSTALL_EVIDENCE.md).

The options describe **gift spawning probability per turn**, plus separate probabilities for the seven types. A seconds-based spawn interval and a specific 0–100 mapping were not recovered from this binary's text.

### 1.4 Modes & options [REPORTED unless stated otherwise]
The following inventory is retained from the earlier research; it is not a verified list of original defaults/ranges. Sandbox is also named in the preserved description. [JayIsGames review/comments](https://jayisgames.com/review/bontago.php); [MobyGames](https://www.mobygames.com/game/13746/bontago/).
- **Modes:** Solo against AI, multiplayer, sandbox (free building with no rules), and tutorials (including a "misc" section).
- **Players:** Up to 8 total, so you plus 7 opponents. Free-for-all or teams. Any mix of humans and AI.
- **Multiplayer:** LAN and direct-IP join are confirmed by installed menu text. Ready/team controls and pre-game chat also exist, so the earlier blanket "no lobby" claim was wrong. A public matchmaking service is not established. [Artifact evidence](ORIGINAL_INSTALL_EVIDENCE.md).
- **Game setup options:** Number of opponents, gravity strength, number of goal flags, special frequency, gifts on or off, block timer, and map size (a "largest map" is mentioned).
- **Music:** Installed tutorial confirms custom music paths and Control-modified shortcuts: Ctrl+R for shuffle and Ctrl+L for looping. [Artifact evidence](ORIGINAL_INSTALL_EVIDENCE.md).
- **HUD:** Shows tower height as a number. Players quote heights like 87 and 102.93.

### 1.5 Original controls [REPORTED; verify against the relevant build's tutorial]
Do not treat this historical key list as the remake's binding contract; §2.5 owns that. Player comments corroborate the middle-button/Home reset and throwing, not every mapping below. [JayIsGames](https://jayisgames.com/review/bontago.php).
- The mouse moves the held block over the field.
- A and S rotate the block. Tapping the middle mouse button rotates it by 90°. There was also a free-rotate mode.
- Q levels the block, and holding the middle mouse button and pressing Home resets the block to its original orientation.
- Mouse flick throws a special.
- The camera used all three mouse buttons.

### 1.6 Reported appeal (qualitative notes, not rule evidence)
- Stacking felt satisfying and physical, with a real sense of weight and balance.
- The core tension was whether to build one tall tower (fast, fragile) or a network of shorter, sturdier towers (slow, safe). The best strategy was a mix.
- Chaos: tilting boards, volcano chains, and towers collapsing. It was a huge amount of fun in multiplayer and with teams.
- Sandbox building: dominoes, silly structures, and height records.
- Visuals: reflective floor, smooth slightly glowing blocks, shadows, and large skyboxes.

### 1.7 Reported problems and proposed remake responses
Retained qualitative notes from the earlier draft, not a verified defect list for every original version. Proposed responses are design ideas, not guarantees of fixes.

| Problem | Remake fix |
|---|---|
| Rotation drifted until blocks sat lopsided, and was hard to recover | Snap to 90° by default, free rotation behind a modifier key, one-key reset (§2.5) |
| Frame rate collapsed with many specials or a crowded board | Jolt physics, sleeping bodies, cap on active bodies, pooled effects (§3.5) |
| Game slowed down after a few minutes as blocks piled up | Remove fallen blocks, freeze old stable blocks as static (§3.5) |
| Crashes: on startup, when a song ended, and in network play | Rely on Godot's audio and networking instead of custom code |
| Games lasted 4 hours with no winner | Optional match timer and escalating sudden death (§2.8) |
| Gifts felt too random, and the anvil hurt everyone | Tunable weights per special, more targeted specials, better throw aiming (§2.6) |
| Throwing was hard to discover and hard to judge | Arc preview while aiming, clear territory edge at the cursor (§2.5) |
| No verified public matchmaking service; original has pre-game setup/chat | Modern Steam lobbies plus LAN discovery and direct IP (§3.4) |
| Only one real strategy once learned | Map variety (odd-shaped tables were planned for 2.0), team modes, special variety |

### 1.8 Sources
- [Installed Bontago 1.1 textual evidence](ORIGINAL_INSTALL_EVIDENCE.md): executable SHA-256, byte offsets and paraphrased tutorial/menu findings, inspected read-only on 2026-09-20. Stronger evidence than secondary accounts where they conflict, but not a runtime behavioral test.
- [DigiPen showcase](https://www.digipen.edu/showcase/student-games/bontago) and [game gallery](https://games.digipen.edu/games/bontago): primary institutional sources for credits, date, awards and broad premise; not detailed rulebooks.
- [GameDev.net developer interview, March 9, 2004](https://www.gamedev.net/tutorials/industry/interviews/circular-logic-r2060/): primary developer testimony, especially shipped versus abandoned tilt behavior.
- [GameDev.net release thread, 2003–2004](https://gamedev.net/forums/topic/177069-bontago/): developer Vulcan/Eric's March 15 timing explanation; August 28 player bug report and developer response concerning overlaps/falling blocks. Bug reports are not idealized rules.
- [Preserved developer-description mirror](https://fileplanet.download.it/p-18772/Bontago): useful historical wording, but third-party hosting and an unspecified build, not an inspected original manual.
- MobyGames: https://www.mobygames.com/game/13746/bontago/
- JayIsGames review and comments, 2007: https://jayisgames.com/review/bontago.php
- GameFAQs review, 2009: https://gamefaqs.gamespot.com/pc/919886-bontago/reviews/137421
- Unknown Worlds forum thread, 2004 (includes a developer post): https://forums.unknownworlds.com/discussion/69613/bontago

Audit date: 2026-09-20. DigiPen, the interview, release thread, description mirror and JayIsGames were inspected. MobyGames returned an access error; GameFAQs and remaining legacy citations are retained leads, not newly verified evidence. Secondary reviews and comments establish reported observations only. The older draft's exact numerical defaults, controls and special-effect details remain provisional where no specific evidence is attached. Owner requirements are separately sourced to [the owner's feedback](bloody_mess.md) and the decision record at the end of this document.

---

## PART 2 — Remake game design

**Working title:** Use a placeholder such as "Stackfall" rather than "Bontãgo" if the game will ever be shared publicly. The name and assets belong to DigiPen and Circular Logic.

**Scale:** 1 unit = 1 cube edge = 1 m. All numerical tunings, randomizer details and physical-effect equations below are **[NEW]** unless individually evidenced. They must not be presented as recovered original constants. Part 2 is the target contract, not a claim about the currently integrated build.

### 2.1 Field
- **Shape:** A disk with radius `field_radius`: 30 on small maps, 45 on medium, 60 on large. [ORIGINAL sizes existed; values are NEW]
- **Structure:** The disk pivots around its center. Body type depends on the selected mode:
  - `tilt_mode = SPECIALS_ONLY` (default): **[ORIGINAL]** specials-driven tilt (§1.1). The animated body, spring-damper, 12° maximum and approximately 4 s return are **[NEW]** implementation choices, not original measurements.
  - `tilt_mode = PHYSICAL_BALANCE`: **[NEW]**, inspired by the scrapped idea, feasibility still to be benchmarked. The disk is a RigidBody3D attached to the fulcrum with a joint that allows rotation on two axes. Torque from block weight tilts it, and a restoring spring plus angular damping keeps it controllable. Optional, not an original-fidelity requirement.
- **Holes:** The disk surface is divided into cells so that holes can appear (§3.3).
- **Out of bounds:** Any body that drops below `kill_plane_y = -40` is removed.
- **Map variants** [NEW, based on the planned 2.0 feature]: Round (default), Oval, Ring (with a hole in the middle and the goal flag on a bridge), Twin disks joined by a bridge, and Cross.

### 2.2 Players, flags, territory
- **Start positions:** 2–8 players; each home flag sits at `0.85 * field_radius`. Evenly distributed home flags are evidenced in §1.2; the exact radius and supported remake player range are design choices.
- **Goal flags:** 1 central flag by default; setup allows 1–5 with extras arranged at `0.4 * field_radius`. Multiple goals are historically described; these limits/layout values are **[NEW]**, not a recovered original maximum.
- **Home circle:** `home_radius = 6` while the home flag is alive. Initial home influence is evidenced; its exact size and lifetime model are **[NEW]**.
- **Goal no-build zones [OWNER, original unverified]:** keep the earlier requirement for a no-placement disc around each goal; the installed tutorial does not settle these zones. Nothing found proves they cannot coexist with original overlap sinking. `goal_zone_radius = 4 m` is the v2 plan's provisional tuning, not an original value. Zones block placement, **not influence or capture**. Do not confuse them with missing floor or assume that claiming the zone's edge is enough to capture the flag base.
- **Influence per block** [RECONSTRUCTED]:
  - Each of your blocks that is settled (see below) produces an influence circle.
  - The circle is centered on the block's center of mass, projected onto the disk plane.
  - Provisional radius: `r = min(influence_base + influence_k * h, influence_max)`, where `h` is that block's highest point above the disk surface, measured along the disk normal. This is a **[RECONSTRUCTED]** per-block-elevation model, not proof that every member of a physical stack shares its top block's height. The exact original height sample, radius curve and cap are unknown.
  - Moving the disk and a resting tower rigidly together must not change their relative height. Tilt affects influence when blocks move relative to the disk; measuring along the normal does not itself imply that tilt changes a rigid tower's influence.
  - Starting values: `influence_base = 1.5`, `influence_k = 0.9`, and `r` is capped at `influence_max = 0.6 * field_radius`.
  - Current **[NEW]** settled filter: linear speed below 0.15 m/s and angular speed below 0.3 rad/s for 0.5 s. Losing influence while moving versus smoothly shrinking with current height is a fidelity question, not a verified original threshold.
  - **Continuous updates [OWNER]:** movement, collapse and removal must update influence without waiting for another placement. `solve_hz = 20` is the v2 plan's candidate rate, subject to benchmarks, not an original rule. A moving block cannot retain stale pre-collapse influence.
- **Connected territory [OWNER requirement, reconstructed algorithm]:**
  - Installed original menu text makes flag-connected **placement** configurable. Keep it required for the remake's current target; original default and disconnected-play win rules remain unknown. This does not establish that disconnected circles disappear visually.
  - Build a graph where each influence circle is a node, and two circles are connected if they overlap.
  - Home-connected circles form candidate influence. Final usable territory also excludes contested/removed regions according to the active mode.
  - Circles disconnected from home provide no usable territory. For capture, a route must survive in the **final owned area**, not merely in a pre-contest circle graph. Enemy territory or a hole cutting the only route must break capture. The propagation/cut-off algorithm needs review (§3.3).
- **Height credit [RECONSTRUCTED]:** permanent placer ownership and influence from a block on an opponent's tower are provisional remake choices. Do not infer support-chain ownership, a whole-stack transfer, or original permission to place there regardless of territory.
- **Overlap holes [ORIGINAL target; mechanics RECONSTRUCTED]:** use the historical evidence in §1.2 rather than the earlier assertion that holes meant only goal zones. Opposing candidate influence creates a contested region that neither player may use for placement. The old cell-collision implementation is one approximation, not verified original geometry.
  - Retained prototype tuning: `hole_delay = 0.75 s`; opened cells remove floor support. A wide body can bridge a small opening; do not promise that any overlap with a hole destroys the entire body. Exact original activation/collision behavior is **[OPEN]**.
  - `hole_mode` values:
    - `TEMPORARY` — **provisional default** toward original overlap-hole behavior; closes 2 s after contest ends. These delays and closure semantics are **[NEW]**, not historical facts.
    - `PERMANENT` — **[NEW]** erosion variant.
    - `OFF` — earlier owner/v2 **alternative**: intact floor and locally height-weighted, mutually exclusive borders. No longer the fidelity default after the latest owner instruction. The border formula remains unverified (§3.3).
  - A visible rejection impulse is a remake choice, not established original behavior. Invalid clicks and expiry must follow distinct rules (§2.5).
- **Teams:** allied placement is **[ORIGINAL]**, explicitly documented in the installed tutorial. Teammates do not contest each other in the remake; goals still need one continuous allied component, not disconnected patches merely sharing a team ID. Exact original team-win/home-anchor semantics remain unverified.

### 2.3 Win condition
- Every goal flag's **base** must be in the same final controlled component with an unbroken path to a living allied home. All goals must satisfy this **simultaneously** for `capture_hold = 3 s`. The owner explicitly retained this hold on 2026-09-20; it is not claimed as original timing.
- There is one shared hold condition, not independent permanent flag captures. Losing any goal or the connecting path resets the hold. Internal solver group renumbering alone must not reset a continuously valid capture. The exact base footprint (point versus finite base) remains **[OPEN]**; current code samples the flag position.
- **Home elimination [OWNER intent, original unverified; default interaction OPEN]:** retain the intent that an engulfed home eliminates its player and the last surviving team wins. However, in the default overlap-hole model an always-active home circle makes invasion contested rather than enemy-owned. The v2 "enemy owns the home point" trigger therefore cannot simply be reused. Decide whether home loss depends on invading influence, loss of physical support or another explicit condition; none is established here as original behavior. Unowned ground alone is not proof of enemy capture. Until resolved, do not claim default-mode elimination complies merely because v2 elimination tests pass; also specify simultaneous elimination/goal-capture precedence.
- **Capture display [NEW]:** radial rings communicate the shared hold. A goal no-build zone remains no-build even while influence/capture passes across it.

### 2.4 Blocks
**Placement cadence [ORIGINAL target, §1.2]:** players act concurrently, each handling their own supplied piece; never rotate through players as in hot-seat. Each fixed interval permits one release. Releasing early does not restart the interval: the next piece can be positioned but remains release-locked until the interval boundary. At expiry, force release only if that interval's piece is still unspent. Crossing a boundary must not release a prepared next piece automatically merely because the previous piece was placed early. Equal shapes can occur by chance; "own piece" does not require distinct shapes across players.

The original global-versus-per-player phase alignment is **[OPEN]**; it must not be confused with player turn-taking or immediate-reset timers. The earlier owner-requested immediate-reset behavior is superseded by the later original-evidence priority. A future cadence option may preserve it, but adding such a setting is not required by this documentation audit.

- **Rigid bodies:** Every block is one RigidBody3D with a compound shape made of cube BoxShape3Ds. The cube size is 1 m, minus a 0.02 m margin so neighboring blocks don't jam against each other.
- **Mass:** Each cube has a mass of 1.
- **Physics material:** Friction 0.8, bounce 0.05.
- **Shape set:** Every shape is defined as a `BlockShape` resource. [ORIGINAL: base cube plus combinations; the exact original set is unknown]

| id | cubes | notes |
|---|---|---|
| cube | 1 | |
| domino | 2 in a line | |
| bar3 | 3 in a line | |
| bar4 | 4 in a line | tall-tower maker, rare |
| L3 | 3, L shape | |
| L4 | 4, L shape | |
| T4 | 4, T shape | |
| S4 | 4, S shape | |
| square4 | 2×2 flat | stable base |
| slab6 | 2×3 flat | rare, strong base |
| pillar | 1×1×3 upright variant of bar3 | |

- **Weighted random feed:** Weights are set per shape in `BlockFeedConfig`. Use a "bag" randomizer so no player goes long without getting a stabilizing shape. [NEW]
- **Next-block preview [ORIGINAL]:** installed tutorial confirms the preview's next piece and timer plus a top-down territory minimap. Distinguish queued preview from the actual held-but-locked preparation piece. Three-piece preview is a remake option.

### 2.5 Controls & placement feel [ORIGINAL base with NEW fixes]

**Held block (ghost):**
- The held block isn't simulated.
- It follows the cursor raycast on the surface under it (disk or existing blocks), hovering `hover_height = 0.3 m` above the first thing it would touch.
- A projected drop shadow and a vertical guide line show exactly where it will land.
- The ghost is tinted in the player's color when the spot is valid, red when it's outside territory or contested, and has a hatched pattern when over a hole.
- A distinct **timer-locked** state must remain visible even at a legal location. A location-valid ghost does not imply that the current interval permits release. Goal zones also need a no-build tint, distinct from physical missing floor.

**Placement legality [OWNER, retained where not contradicted by evidence]:** cast one ray straight down from the ghost's middle and classify its hit point in disk-local territory. It must be owned by the player's team, outside goal no-build zones, and not a contested/hole point. Do not require the whole footprint to fit. Missing support/off-disk hits are invalid. Ghost overlap/collision avoidance and anti-cheat bounds are separate checks, not permission to reintroduce footprint territory tests. Exact ray origin and world-down versus disk-normal behavior during tilt remain an implementation/feel question (§3.3).

**Control model [ORIGINAL, implemented 2026-09-21 — Bontago-mv0.14]:** the camera is attached to
the held block and follows it (`CameraTuning.follow_block`, smoothed by `follow_lag_seconds`);
mouse motion moves the block in the disk plane relative to the camera (mouse captured during
play); the wheel raises/lowers the block; holding Rotation Mode turns motion into 90° snaps;
holding Camera Mode orbits instead of moving the block. Key choices below are [NEW] where the
original's tutorial only names the action, not the key.

| Action | Mouse/Keyboard | Gamepad [NEW] |
|---|---|---|
| Move block | Mouse motion | Left stick |
| Place (drop) | Left click | A / Cross |
| Raise / lower block | Mouse wheel; PageUp / PageDown held | RS click / X held |
| Rotation Mode (hold) | R | RT |
| Rotate yaw ±90° (tap) | A / S | LB / RB |
| Rotate pitch ±90° (tap) | W / D | D-pad up / down |
| Rotate roll ±90° (tap) | [ / ] | D-pad left / right |
| Rotate block (hold + drag) [ORIGINAL, owner test 2026-09-22] | Middle mouse held + mouse motion, full 3-DOF: X = yaw about world up, Y = pitch about the camera's right axis (like the orbit, for the block) | (RB snaps 90° yaw) |
| Reset rotation | Home or F | Y |
| Lock to vertical (hold) | Ctrl | (stick and height are already separate) |
| Camera orbit (hold + drag) [ORIGINAL, owner test 2026-09-22] | Right mouse held + mouse motion; mouse wheel zooms while held (C + mouse remains as a keyboard alias) | Right stick (always) |
| Camera zoom | Z / X | Triggers while no block is held |
| Throw (specials only) | **[OWNER decision 2026-09-22, Bontago-mvl]** hold left mouse on the held special, drag, flick-release; drag distance/speed sets the arc. Right mouse stays camera orbit | Hold LT, aim, release |
| Pause / release mouse | Esc | Start |

**Held-block behaviour [ORIGINAL, owner test 2026-09-22]:** the held (ghost) block collides with already placed blocks — it cannot pass through a tower — but it never pushes or knocks them; placed blocks are unaffected by the ghost. A drop outside the player's own territory is **refused** (the block stays in hand; no drop, feedback only). When the placement window expires while the held block is outside the zone, the block and the camera jump to the nearest valid point inside the player's territory and the block drops there. Owner-tuned feel: `follow_lag_seconds` 0, `follow_pitch_deg` −35, `block_move_sensitivity` 0.015. The held block is tinted grey whenever it cannot be dropped (outside the player's zone, or waiting for the next window); its only ground marker is the projected footprint of the rotated shape (no separate shadow). Mouse capture keeps the cursor moving past the screen edge in every match mode.

Legacy free camera (pan with arrows / Space-drag, snap 1 / 2) remains behind
`CameraTuning.follow_block = false`.

**Rotation:**
- Store rotation as an integer orientation index. There are 24 axis-aligned orientations of a cube.
- Free rotation adds a separate quaternion on top of that. Reset clears the free rotation and sets the index back to 0. This prevents the drift the original had.

**Throwing:**
- While aiming, show an arc preview.
- Throw strength scales with drag distance, capped at `throw_max_speed = 25 m/s`.
- The release point has to be inside your own territory, so show the territory edge clearly near the cursor.

**Expiry and invalid actions [ORIGINAL, owner test 2026-09-22]:** forced release at interval expiry is evidenced (§1.2). An invalid manual click does **not** drop and does **not** consume the piece: the game refuses it and the block stays in hand. At expiry with the held block outside the player's zone, the block and camera jump to the nearest valid point inside the zone and the block drops there (the earlier **[NEW]** closest-valid-point fallback is confirmed as original behaviour for expiry). **[OPEN]:** when no valid point exists at expiry; how expiry handles a held special. Failed clicks never advance the cadence.

**Gamepad parity [NEW, OWNER priority]:** every action/menu must be usable with mouse/keyboard and gamepad via Input Map. Camera-relative stick movement, zoom-scaled speed/dead zone, optional top/edge snap aid, throw arc/strength and device-specific prompts remain remake requirements. Multiple local gamepads/split-screen are outside v1. Blank bindings in the table and A/S versus WASD conflicts are unresolved mappings, not permission to ship inaccessible controls.

### 2.6 Gifts & specials
Use the [installed tutorial/menu](ORIGINAL_INSTALL_EVIDENCE.md) as the primary effect contract. It documents behavior but not numerical tuning. All radii, force values, durations and projectile counts below remain **[NEW]** starting values, not decoded original constants.
- **Gift spawning [ORIGINAL target]:** probability per placement turn/window, not the earlier seconds-based interval with ±40% jitter. Original trial scope (one per match or per player), distribution and probability scale are unverified; **[OWNER decision 2026-09-22, Bontago-4fa]** ship the M4 P1 tunables (`spawn_chance_per_window` 0.15, one roll per window for the whole match, `max_live_crates` 1, crate expiry 60 s, lobby frequency 0–100 → chance 0–0.5) and tune via F4. Type-specific probability controls exist. Do not implement the removed 20 → 45 s / 100 → 6 s mapping as original behavior.
- **Crate life [RECONSTRUCTED; owner decision 2026-09-22]:** crates are **stationary pickups** — they land at a host-chosen point and stay put until claimed or expired (60 s expiry remains a prototype starting value). Installed text says specials fall to the field but does not establish lifetime or crate physics; the owner chose the stationary design over rigid-body crates for M4 (Beads `Bontago-1en`).
- **Claiming:** When a crate is inside your territory, it pops. It shows which player it belongs to, and your next fed block becomes a special. [ORIGINAL]
- **Activation [ORIGINAL]:** substantial impact activates a special. Numeric impulse threshold and the earlier 0.4 s arm delay are **[NEW]** tunings. Whether explosion proximity alone activates an untouched special needs verification.
  - Remove the universal eight-second auto-trigger from the fidelity target: it has no recovered basis. Type-specific lifecycle is separate, notably Rocket's fuel-exhaustion explosion after activation.
- **Chain reactions:** Retained from player reports. Cap them at `max_chain_depth = 4` as a remake performance choice. Multiple simultaneous claims and replacement of an already prepared piece remain **[OPEN]**. **[OWNER decision 2026-09-22, Bontago-59u]** pending specials form a per-player FIFO queue capped at `max_pending_specials` (tunable; Bontago-csc), not a latest-wins single slot.

| Special | Behavior | Tunables | Source |
|---|---|---|---|
| **Rocket** | On activation launches upward, then explodes when fuel is exhausted. No homing target or mandatory impact detonation is documented | fuel duration/trajectory OPEN; speed 18, radius 3, impulse 14 are provisional | ORIGINAL tutorial effect |
| **DaBomb / Bomb** | Large explosion on activation; do not assume adhesive or proximity-mine behavior | radius 3.5, impulse 18 provisional | ORIGINAL tutorial effect |
| **Volcano** | Erupts for 3 s, firing 8–14 burning orbs upward in a cone. Each orb explodes on impact and can set off other specials | orb impulse 6, cone 35° | ORIGINAL name; NEW parameters |
| **Earthquake** | Shakes the field and helps level existing tilt; extra local shaking is not documented | 4 s, amplitude 0.25 m / 2.5° provisional; leveling strength OPEN | ORIGINAL tutorial effect |
| **Anvil** | Applies weight to tilt the field; exact coupling/direction needs observation | mass 60 and tilt impulse by distance are provisional | ORIGINAL tutorial effect |
| **Propeller** | Gradually lifts upward and tilts the field; replaces the speculative Fan/wind-emitter design | lift, duration and coupling OPEN | ORIGINAL tutorial effect |
| **Jumping Bean** | Hops randomly around the board; creates a local hole between hops | hop interval/strength and hole radius/lifetime OPEN | ORIGINAL tutorial effect; previously missing |
| **Magnet** | Pulls enemy blocks within 8 m toward itself for 3 s | | NEW |
| **Freeze** | Makes your own blocks within 6 m static for 20 s | | NEW (defensive, cuts down on luck) |
| **Glue** | Joins touching blocks of yours within 4 m with breakable joints | break force 40 | NEW |
| **Gravity well** | Flips gravity to 30% within 10 m for 5 s | | NEW |

Every special is its own `SpecialDef` resource plus a script. The seven evidenced effects are the original-fidelity roster; Magnet, Freeze, Glue and Gravity well are optional remake extras, not original discoveries. Type probabilities are original menu features; per-type enable checkboxes are the remake interface. Jumping Bean's local hole is independent of opponent overlap; **[OWNER decision 2026-09-22, Bontago-z4h]** under `HoleMode.OFF` the Jumping Bean punches no hole and keeps only its hop knockback.

### 2.7 Modes
- **Free-for-all:** 2–8 players, humans and AI.
- **Teams:** 2–4 teams.
- **Sandbox:** No timer and no territory limits. Throwing ordinary blocks is allowed, and there's a block picker. Specials can be spawned from a menu. It also has slow-motion, pause-physics, and height-record tools. [ORIGINAL + NEW tools]
- **Tutorial:** 5 short interactive steps: placing, rotating, territory, specials and throwing, and camera.
- **Turn-based** [NEW, a planned 2.0 feature]: Players take turns. Physics settles completely (all bodies asleep, or after 6 s) before the next player's turn starts.

### 2.8 Match settings (lobby)
| Setting | Range | Default |
|---|---|---|
| Map | Round / Oval / Ring / Twin / Cross | Round |
| Map size | S/M/L | M |
| Players / AI count & difficulty | 2–8, Easy/Normal/Hard | 4 |
| Teams | Off / 2 / 3 / 4 | Off |
| Block timer | 3–12 s | 6 s |
| Gravity | 0.5×–2× | 1× |
| Goal flags | 1–5 | 1 |
| Gifts | On/Off | On |
| Gift probability per window | 0–100% as remake UI; original numeric scale/trial scope unverified | tuning OPEN; earlier 35 seconds-interval mapping superseded |
| Enabled specials | checklist + type weights | seven documented types in §2.6; NEW extras opt-in |
| Tilt mode | Specials only / Physical balance | Specials only |
| Hole mode | Temporary / Permanent / Off (v2 alternative) | Temporary, provisional approximation of original overlap holes |
| Match timer | Off / 10–40 min | Off |
| Sudden death | Off/On | On if match timer is set |

**Sudden death** [NEW]: Starts when the match timer runs out.
- Gift probability climbs toward the maximum of the finalized spawn model (§2.6).
- The disk's edge crumbles inward by 1 m every 10 s.
- The first player or team to reach the win condition wins. If nobody has won when the disk has shrunk to a radius of 8, the player or team with the most territory wins.

### 2.9 AI bots [ORIGINAL feature, NEW implementation]
The AI runs only on the host, and for multiple bots it spreads its thinking across several frames.

**Placement:** Each time a bot receives a block, it samples 40–120 candidate spots. Each spot combines a position in its territory, the orientation (out of the 24) that gives the flattest base, and whether to stack on a block or place on the disk. Each candidate gets a score:
- **Height gained** at that spot, found by raycasting down onto whatever is below it.
- **Progress toward the goal**, i.e. how much closer its territory edge gets to the goal flag.
- **Stability:** The area of contact under the block, and whether its center of mass sits over that contact area. Estimate this with raycasts from the block's footprint cells.
- **Risk:** Distance from enemy territory and from active specials.

**Specials:** replan bot targeting around §2.6's verified effect types. Do not aim a Rocket as if it homes or a Propeller as if it blows sideways. Offensive/defensive placement heuristics must account for launch-upward, leveling, tilt and Jumping Bean holes; exact scoring is **[NEW]**.

**Difficulty:** Affects how many spots are sampled, a random aiming error, reaction delay, and whether the bot uses defensive specials.

### 2.10 Presentation [NEW, modernizing the original look]

**Owner direction 2026-09-22:** blocks render as solid single shapes (no visible per-cell cubes, as in the original); the map disc reads as glass — slightly transparent and reflective — with territory colours still legible on it (superseded 2026-09-23: the disc is an opaque, mirror-like reflective surface, not glass — Bontago-xtq.11); camera FOV is a tunable.
- **Disk:** Opaque, mirror-like polished surface (reflective, never transparent; owner 2026-09-23), with sky reflections via the Environment sky and a reflection probe for nearby blocks.
  - Territory is drawn by a shader. Each player's area is a soft tint in their color with an animated outline.
  - Contested areas shimmer. Hole edges glow and crackle.
- **Blocks:** Bevelled cubes with a subtle PBR material and an emissive seam in the owner's color. They glow brighter when they're contributing influence.
- **Sky:** Starts with a procedural sky, with support for HDRI panoramas for different themes (dawn, sunset, stormy, night). A cloud layer below the disk made with volumetric fog, and a distant ocean or landscape.
- **Effects:** GPUParticles3D for explosions, lava orbs, dust when blocks land, and debris falling off the edge.
  - Camera shake scales with the size of the impulse, and can be turned off in settings.
  - Blocks that fall off leave a trail and fade out.
- **HUD:** Timer ring around the next-block preview, current max height in meters, territory percentage per player, special indicator, goal capture ring, and a minimap (top-down territory texture).
- **Audio:**
  - Impact sounds vary in volume and pitch with impulse and material.
  - Stacking a block gives a rising "tick" that climbs in pitch with height.
  - Specials have distinct warning sounds.
  - Music is adaptive, getting more intense as someone gets close to capturing.
  - A custom music folder is supported. [REPORTED original feature, retained remake requirement]

---

## PART 3 — Technical architecture

### 3.1 Stack
- **Engine:** Godot **4.6 or newer**, stable release. 4.6 makes Jolt the default 3D physics engine for new projects. Confirm `physics/3d/physics_engine = Jolt Physics` in project settings.
- **Renderer:** Forward+. Include a "Low" graphics preset that turns off SSR, SSIL, and volumetrics.
- **Language:** GDScript with static typing (`@warning_ignore` sparingly, enable `untyped_declaration` warnings).
- **Tests:** GUT or gdUnit4 for pure-logic unit tests: territory math, connectivity, win check, block feed.
- **Platforms:** Windows, Linux, and macOS desktop, distributed through Steam.
- **Plugins:** GodotSteam (from M3b). Keep third-party addons in `res://addons/` and pin their versions.

### 3.2 Project layout
```
res://
  project.godot
  autoload/
    Events.gd            # global signal bus
    Settings.gd          # user settings (graphics, audio, controls), saved to user://
    Net.gd               # NetworkManager: host/join, discovery, peer registry
    Match.gd             # match config + state machine (Lobby, Countdown, Playing, SuddenDeath, End)
  config/
    match_defaults.tres  # MatchConfig resource
    physics_tuning.tres  # PhysicsTuning resource
    blocks/*.tres        # BlockShape resources
    specials/*.tres      # SpecialDef resources
    maps/*.tres          # MapDef resources
  core/                  # pure logic, no nodes where possible -> unit testable
    territory/TerritorySolver.gd
    territory/InfluenceCircle.gd
    feed/BlockBag.gd
    rules/WinChecker.gd
  game/
    Field.tscn / Field.gd          # disk, cells, fulcrum, tilt controller
    Block.tscn / Block.gd          # RigidBody3D, built from BlockShape
    GiftCrate.tscn
    specials/*.tscn + *.gd
    PlayerController.gd            # local input -> intents
    GhostPreview.tscn              # non-physics held block
    BotController.gd
    CameraRig.tscn
  net/
    SnapshotSync.gd                # host->client body state
    Interpolator.gd
    LanDiscovery.gd
  ui/
    MainMenu.tscn, Lobby.tscn, HUD.tscn, Settings.tscn, Tutorial.tscn
  vfx/, sfx/, shaders/
    territory.gdshader, block.gdshader, hole_edge.gdshader
  tests/
```

### 3.3 Territory & holes implementation
**Implementation status:** this is a target/design contract. The legacy M2 raster and the in-progress `TERRITORY_V2_PLAN.md` implement different interpretations; neither is proof of original rules. The latest fidelity instruction restores overlap holes as the default target (§2.2), while preserving owner requirements not contradicted by evidence. Do not integrate the v2 `OFF` default as if it were still the approved default.

- **Data:** `TerritorySolver` takes a list of `(owner_team, center2D, radius)` circles plus the home circles. It returns connected groups for each team.
  - Union-find over overlapping circles finds **candidate** connections. It does not prove a continuous path after an opponent/contested region removes the connecting neck. Final owned-area connectivity must be checked for capture; do not treat the pre-contest group ID as sufficient evidence.
  - Use a spatial hash grid (cell size = `influence_max`) so it doesn't check every pair against every other pair.
- **Rate [NEW]:** continuously sample moving structures, independent of placement events. The v2 plan proposes 20 Hz host solves (legacy 10 Hz); benchmark before accepting the rate. Replication/render cadence is separate, so smooth visuals must not hide stale authoritative rules.
- **Raster map:** A `territory_res × territory_res` grid (256 for S, 384 for M, 512 for L) in disk-local polar-free Cartesian space.
  - Each pixel stores which team owns it, or a contested flag, or a hole flag.
  - Fill each connected group's circles onto the grid. Pixels with more than one team are contested.
  - Keep a separate float array so each pixel's contested time can build up toward `hole_delay`.
- **Rendering:** smooth circle-derived outlines are an owner requirement. Merely enlarging a coarse nearest-sampled ownership raster cannot recover a curved boundary. Interpolation, analytic circles or a field shader are implementation options, not historical facts. Keep visual ownership, legal placement and capture sufficiently aligned at borders; GPU-only apparent ownership is not permission to build. Discard floor pixels only for actual physical holes, never merely for goal no-build zones.
- **Physics holes:**
  - The disk's collision is built from `cells` (a square grid of `cell_size = 1.0` BoxShape3Ds clipped to the disk shape) inside one body.
  - When a cell's hole state changes, toggle `shape_owner_set_disabled` on that cell's shape.
  - Batch the toggles so there are at most 64 per frame.
  - Wake up any sleeping blocks above cells that change state.
- **Placement validation:** one downward ray and the hit-point test in §2.5, for the normal target rules. A grid may cache ownership; it must not turn the rule back into a full footprint check. Host validation also checks placement-interval eligibility and rejects duplicate releases for the same interval/piece.
- **Win check:** final owned connectivity plus simultaneous all-goal coverage and the shared hold (§2.3). A cached group label from before contest resolution is not a substitute.

**V2 alternative: known mathematical limitations (analysis, not recovered original code).**

The plan's `radius - distance` score is an *additively weighted distance* field, not the squared-distance power/Laguerre diagram it calls itself. It gives local moving borders, but cannot guarantee the claim that a taller tower never takes the entire smaller circle: if radii are 10 and 2 and centers are 3 apart, the triangle inequality makes the larger circle's score exceed the smaller's everywhere. Likewise, taking the maximum of circle scores is a circle union, not a summed metaball field. Those approaches can look and play differently.

Do not invent a replacement formula in the name of accuracy. These are review findings for the optional v2 mode: decide whether complete engulfment is allowed (also relevant to home elimination), how ties behave, and how cut-off influence is resolved. The original formula has not been recovered. The default overlap-hole mode must not silently inherit v2's exclusive-owner argmax behavior.

### 3.4 Networking
**Online from the start.** Gameplay code only talks to Godot's high-level `MultiplayerAPI` and never to a specific transport. `Net.gd` picks the transport:

| Transport | Used for | Implementation |
|---|---|---|
| **Steam** (default online) | Internet play with friends, invites, lobbies, NAT traversal through Valve's relay network | GodotSteam (GDExtension or the precompiled editor) plus its `SteamMultiplayerPeer`. Steam lobbies store match settings as lobby data. Friends join through the Steam overlay invite or "Join Game". |
| **ENet** | LAN (auto-discovery), direct IP, local multi-instance testing, headless bot tests | `ENetMultiplayerPeer` |

- **Development app ID:** Use Steam's public test app ID **480** ("Spacewar") in `steam_appid.txt` during development. Your own app ID (paid Steam Direct fee) is only needed before release.
- **Steam startup:** If Steam isn't running, the game still works with LAN and direct IP. Hide the online menu entries and show a notice.
- **Channels:** Use a separate channel for snapshots only if the chosen Steam peer supports channels. Otherwise send snapshots as unreliable packets and tag each with a sequence number.
- **Version check:** Refuse connections when the game build version doesn't match. Compare the version when joining a lobby and during the ENet handshake.
- **Anti-cheat:** Out of scope beyond the host checking every intent (friends-only game).

**Model:** Host-authoritative listen server. The host is also a player. It uses the high-level multiplayer API on top of whichever transport is selected. **Only the host simulates physics.** Clients set every synced RigidBody3D to `freeze = true` (kinematic) and move them by interpolating snapshots. [NEW]

Deterministic lockstep isn't an option, because Godot's Jolt integration doesn't guarantee determinism.

**Channels:**
- **Reliable** (RPCs): lobby, match config, block spawn/despawn, special trigger events, territory raster diffs (sent compressed at 5 Hz), win and end, chat.
- **Unreliable sequenced** (custom packets on their own channel): body snapshots.

**Client → host intents** (RPCs with `@rpc("any_peer", "call_remote", "reliable")`, checked on the host):
- `request_place(slot_id, pos: Vector3, orient_index: int, free_quat: Quaternion)`
- `request_throw(slot_id, pos, orient, velocity: Vector3)`: the host clamps velocity to `throw_max_speed`.
- `update_cursor(pos)`: unreliable, 15 Hz. Only used to show other players' ghosts.

The host checks territory, the timer, and that the slot matches, then spawns the block. The client shows the ghost immediately and plays a small placement effect. If the host rejects the request, the client shows a "reject" effect.

**Snapshots:**
- **Rate:** 30 Hz.
- **Contents per body:** `net_id: u16`, position quantized to int16 per axis over map bounds (≈1–2 mm precision), rotation as a 48-bit "smallest three" quaternion, and a sleeping flag.
- **What to send:** Only bodies that are awake or changed since the last acknowledgement. Every 2 s, send a full "keyframe" for sleeping bodies at a low rate.
- **Disk state:** Tilt quaternion and position offset, sent every snapshot.
- **Size:** 300 awake bodies × ~13 bytes ≈ 4 KB per packet. Split into several packets if needed to stay under ~1200 bytes each.

**Client interpolation:** Render 100 ms behind the host (the delay adjusts to measured jitter), interpolating between the two surrounding snapshots. If snapshots are late, extrapolate for at most 100 ms.

**Late join / reconnect:** Send the full world state in chunks: all bodies, the territory raster, and match state. Match time pauses while a player is joining in lobby-only mode. Mid-match joins can be enabled in settings.

**LAN discovery (`LanDiscovery.gd`):**
- The host broadcasts `{game, version, name, players, max, map, port}` once per second over `PacketPeerUDP` to 255.255.255.255 on port 47777.
- Clients listen and show a list of games.
- Direct IP entry is available as a fallback.
- The default game port is 47778.

**Testing:** Use the editor's "Customize Run Instances" to run 2–4 instances locally. Add a `--headless-host` command-line flag for automated bot-versus-bot soak tests.

### 3.5 Physics tuning (Jolt)
- **Tick rate:** `physics/common/physics_ticks_per_second = 60`. Turn on physics interpolation (`physics/common/physics_interpolation = true`) so rendering stays smooth at high refresh rates.
- **Solver:** Raise Jolt's solver velocity and position iterations from the defaults. Start at 10 and 4, and tune using a benchmark scene with a 40-block tower.
- **Sleep:** Bodies sleep after 0.5 s below the speed thresholds. Wake them when the disk tilts, when something nearby explodes, or when the hole cell under them changes.
- **Stable-block optimization** [NEW]: If a block has been asleep for more than 20 s and isn't touching any awake body, the host switches it to `freeze_mode = STATIC`. It goes back to normal the moment any impulse, tilt, or change in the cells under it happens. When the disk tilts, all frozen blocks within the tilted region wake up, because the disk moving must affect them.
- **Continuous collision:** Rockets, lava orbs, thrown specials, and any body moving faster than 15 m/s use `continuous_cd`.
- **Body limits:**
  - `max_active_blocks = 600`. Beyond that, the lowest-influence blocks that are off the disk or fully buried are removed first, with a visible dissolve.
  - Explosion chains are capped (§2.6).
- **Explosions:**
  - Query bodies in range with `PhysicsDirectSpaceState3D.intersect_shape` (sphere).
  - Apply `apply_impulse` with falloff `(1 - d/r)^2`.
  - Clamp the impulse per body to `max_explosion_impulse`.
  - Wake the bodies it hits.
- **Tilt:**
  - In `SPECIALS_ONLY` mode, the disk is an `AnimatableBody3D` with `sync_to_physics = true`, driven by a critically damped spring on its tilt vector. Blocks resting on it are carried along correctly.
  - In `PHYSICAL_BALANCE` mode, the disk is a RigidBody3D pinned at the fulcrum with a `Generic6DOFJoint3D` or `ConeTwistJoint3D`. It has a restoring angular spring.
- **Gravity:** Multiply the default gravity by the match setting.
- **Materials:** Disk friction 0.9. Blocks as in §2.4. Specials' friction varies with type, for example the anvil is 1.0.
- **Benchmark scenes** (in `tests/bench/`):
  - A tower of 40 blocks that must stay standing for 60 s with no jitter.
  - 300 blocks falling at once, which must hold ≥120 fps on a mid-range PC.
  - A chain of 5 volcanoes, which must never drop below 60 fps.

### 3.6 Key data resources
```gdscript
class_name BlockShape extends Resource
@export var id: StringName
@export var cells: Array[Vector3i]        # cube offsets
@export var weight: float = 1.0           # feed weight
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
# all §2.8 settings, serializable to Dictionary for RPC

class_name PhysicsTuning extends Resource
# §3.5 physical tuning

class_name TerritoryTuning extends Resource
# influence, hole/goal-zone, solve-rate and capture-hold tuning;
# actual project resources take precedence over this illustrative class sketch
```

### 3.7 Match state machine (host)
`Lobby → Loading → Countdown(3s) → Playing → (SuddenDeath) → End → Lobby`

**Playing loop on the host:**
- **Block feed:** concurrent players with fixed placement windows (§2.4). Track the interval's release eligibility separately from the next prepared piece. Early release does not reset the window. Only an unspent current piece auto-drops at expiry. Special substitution must respect the resolved queue policy, not accidentally grant an extra release.
- **Territory:** continuously recomputed at the configured solve rate (§3.3); territory diffs currently target 5 Hz. Do not wait for a new block placement to update collapse effects.
- **Gifts:** use the per-placement-window probability contract in §2.6 once trial scope is resolved; the old independent-seconds spawner is not established original behavior.
- **Win check:** Runs every territory update.

---

## PART 4 — Build plan (milestones)

Each milestone ends with a playable build and passes its acceptance criteria.

### M0 — Project setup (short)
- Create the Godot 4.6+ project and set Jolt, 60 Hz, and physics interpolation.
- Set up the folder layout, autoloads, typed-GDScript warnings, the test framework, and `.gitignore`.
- **Accept:** The project opens and runs an empty scene. A sample unit test passes.

### M1 — Physics sandbox (offline)
- Disk (static for now), camera rig, and block spawning from `BlockShape` resources.
- Ghost preview with drop shadow, 24-orientation rotation plus free rotation and reset, placing blocks, kill plane.
- Benchmark scenes from §3.5.
- **Accept:**
  - You can build a stable 30-block tower, with mouse and keyboard and with a gamepad.
  - Rotation never drifts.
  - The benchmarks hit their targets.

### M2 — Rules & territory (historical prototype; revised acceptance below)
- `TerritorySolver` with unit tests covering overlap, connectivity, being cut off, and teams.
- Territory raster and shader, contested zones, holes (visuals and collision), placement validation, block feed and timer with auto-drop, next-block preview, goal flag, win check, basic HUD.
- The original hot-seat build was a test harness, not evidence of original player turn-taking. Its closed milestone does not certify the corrected rules.
- **Current rule acceptance:** use concurrent players (local multi-instance or bots), validate §2.4 cadence, overlap holes under the provisional default, no-build goal zones and point-based placement, continuous collapse updates, and home-connected capture. See the scenarios below. A separate hot-seat/turn-based test mode must not become normal play.

### M3 — Multiplayer (ENet, then Steam)
- **M3a:** Transport abstraction in `Net.gd`, ENet host and join, LAN discovery, direct IP, lobby with MatchConfig, host-authoritative physics, snapshot sync with interpolation, intent RPCs, other players' ghost cursors, disconnect handling.
- **M3b:** GodotSteam integration with app ID 480. Create Steam lobbies, invite friends, join through the overlay, use `SteamMultiplayerPeer` for gameplay traffic, and fall back to ENet when Steam isn't running.
- **Accept:**
  - 4 local instances play a full match.
  - A client with 100 ms of simulated lag and 2% packet loss sees smooth towers.
  - Placements are never duplicated or lost.
  - Two PCs on different home networks play a full match over Steam.

### M4 — Gifts & specials
- Gift crates, claiming them, special feed, throwing with arc preview, arming and triggering, chain cap.
- Rocket, DaBomb/Bomb, Volcano, Earthquake, Anvil, Propeller and Jumping Bean per §2.6. Tilt controller (SPECIALS_ONLY). The older M4 plan requires reconciliation before reuse.
- **Accept:**
  - Every special works in both single-player and LAN.
  - A 5-volcano chain stays ≥60 fps on the host.

### M5 — AI bots
- `BotController` with placement scoring, using specials, and 3 difficulty levels. Mix bots and humans in the lobby.
- **Accept:**
  - A Hard bot beats a passive player in under 10 minutes.
  - An 8-bot headless match finishes without errors.

### M6 — Modes & settings
- Teams, sandbox (with its tools), tutorial, turn-based mode, match timer and sudden death, map variants, PHYSICAL_BALANCE tilt mode, all lobby settings, user settings (graphics presets, key rebinding, audio, custom music folder).
- **Accept:** Every setting in §2.8 changes gameplay as described.

### M7 — Presentation polish
- Block and disk materials, sky themes, clouds, particles, camera shake, sound design, adaptive music, full HUD with minimap, main menu styling.
- **Accept:** Looks and feels good. Holds 144 fps at 1440p with 300 blocks on the High preset on a mid-range GPU (tune as needed).

### M8 — Extra specials & hardening
- Magnet, freeze, glue, gravity well.
- Stable-block freezing, body cap and removal, reconnect and late join, 2-hour soak test with bots, crash-free exports for Windows, Linux, and macOS.

---

## Decisions made — current target

- **Fidelity policy [OWNER, latest]:** prioritize original rules when concrete evidence exists. This supersedes conflicting earlier recollections, but not explicitly retained remake exceptions.
- **Cadence:** adopt the developer-described fixed-window placement lock, not immediate reset and not alternating players (§2.4).
- **Holes:** restore overlap holes as the fidelity target. Temporary cell holes remain a provisional approximation; exact original timing/physics are unverified. The no-overlap v2 mode is optional, not the default.
- **Capture hold [OWNER, explicitly confirmed during this audit]:** keep **3 seconds**. Original all-goal objective and this remake hold must not be conflated.
- **Other retained owner requirements:** point-ray placement, continuous influence updates, smooth presentation, goal no-build zones and home elimination remain where not contradicted by concrete evidence. Their exact original status is not asserted.
- **Online/controls [NEW]:** Steam plus ENet, and equal gamepad priority remain remake requirements.

## Fidelity gaps / unresolved rule contract

These are design uncertainties, not an alternate task backlog; assignments and status belong in Beads.

| Gap | Known / provisional behavior | Evidence or decision needed |
|---|---|---|
| Original build | Installed file advertises 1.1; hash and tutorial offsets recorded | Runtime behavior and release provenance still not independently verified |
| Feed clock | Fixed release windows established; independent pieces | Whether windows align globally; expiry/invalid-location handling |
| Influence | Height-based growth; current formula uses each block's top elevation | Original radius law, height reference, settled/support criteria, caps and mixed-owner stacks |
| Holes | Opponent-overlap holes evidenced | Delay, closure, exact collision/removal rules; interaction with goal zones |
| Goal geometry | Owner says base of every flag, connected to home | Center point versus whole base footprint; no-build radius and whether physical intrusions after release are allowed |
| Connectivity | Capture needs one surviving controlled route | Ownership clipping can sever precomputed circle groups; cut-off/reconnection propagation and allied home anchoring |
| Elimination | Owner retains home engulfment and last-team-standing intent | In overlap mode the persistent home circle prevents enemy ownership at its center; resolve the trigger before implementation, then eliminated blocks and simultaneous outcomes |
| Gifts/specials | Seven tutorial-described types; collection through connected influence; gift probability per turn | Queue/tie policy, already-prepared piece, trial scope, numerical thresholds and actual runtime trajectories |
| Controls | Remake wants full device parity | Resolve conflicting/bare bindings; verify original tutorial separately |

### Rule acceptance scenarios (target, not a claim of passed tests)

1. **Early release:** player A releases during a window and can orient the next piece but cannot release it until the next window. Player B keeps playing independently; no active-player rotation. Expiry forces exactly one unspent piece, never a prepared future piece.
2. **Collapse without input:** move/topple a tower, then issue no placement. Its influence updates promptly; disconnected capture progress resets.
3. **Local versus global height:** raising a distant tower must not arbitrarily enlarge every short tower's local influence. Measure radius from the chosen local model, not a per-player maximum.
4. **Goal exclusion versus capture:** a point inside a goal's no-build zone refuses placement even if owned. Influence can still cover its flag base. No physical floor is removed solely because it is a goal zone.
5. **Point legality:** a wide piece centered at a legal ray hit is not rejected only because a corner crosses a territory border. This is distinct from spawning interpenetrating bodies or invalid network poses.
6. **Severed route:** raw circles still form a graph, but enemy/contested area cuts its only corridor. Goal coverage beyond the cut must not complete capture.
7. **Shared hold:** all goal bases are covered for less than 3 s, then one is lost: reset. Continuous coverage for 3 s wins. Solver index changes without a geometric break do not reset progress.
8. **Overlap mode:** opposing influence opens a hole according to explicit provisional tuning. Temporary restoration and permanent erosion are tested separately. No test should mistake v2's winner-takes-point border for an overlap hole.
9. **Mode/network agreement:** normal play, host validation, client preview and bots use the same cadence and legality contract. The existing code/test suite must be reconciled; changing this document alone does not establish compliance.

## Owner clarifications — 2026-09-20 (historical decision record)

The following is a **summary**, not a verbatim transcript, of [the owner's feedback](bloody_mess.md) after playing the M3b build. Keep that source unchanged. Later original-evidence priority supersedes the immediate-reset timer and no-overlap/default-no-holes portions below; retained requirements are integrated in Part 2. This record must not override the current decisions above.

- Everyone plays at the same time. Each player gets their own block (not shared) and
  must place it before their timer runs out; on placement they immediately get a new
  block and a new timer. No waiting for other players. (Already the M3a behaviour.)
- A player may only place inside their own **area of influence**. At the start that is
  a small circle around their start flag plus some extra space. Every placed block adds a
  new circle; a lone block's circle is very small and grows with the **height of the stack
  it belongs to**. A tall tower or several smaller ones are both valid strategies.
- The area must update **continuously** — if a stack falls (physics, powerups, anything)
  the circles shrink/vanish immediately, not only when a new block is placed.
- **Goal flags** have their own area of influence in which no player may place a block.
  That is what the "hole" mechanic is: a no-build zone around each goal flag, not floor
  that opens under contested territory.
- To win, a player's area of influence must **encapsulate the base of every goal flag**
  with an undisrupted path back to their start flag (built from one or more connecting
  towers).
- Placement check: **one raycast from the middle of the ghost block straight down**; the
  hit point must be inside your own area and outside every goal flag's area. No cell
  footprint tests.
- The area should look **smooth** (a metaball-style union of circles), not a jagged cell
  grid.
- Areas of different players **never overlap**. Where they meet, the border is pushed by
  the heights of the stacks producing the contested area: the taller local stack gets
  more of the shared region, but not all of it, and it is the individual contesting
  stacks that count, never a global per-player value.

Owner answers (same day): floor holes are removed from the default rules but kept
behind a lobby "holes" mode for later; home-flag elimination stays (an enemy area
swallowing your start flag eliminates you; last team standing wins).

**Later in the same day's spec audit:** owner confirmed the 3-second capture hold, then instructed: prioritize original rules when concrete evidence exists. Accordingly the historical hole-mode/default and immediate-timer statements above are superseded; home elimination remains an owner requirement pending contrary evidence.
