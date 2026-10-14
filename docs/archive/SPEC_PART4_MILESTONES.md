> Historical milestone plan (M0-M8), moved verbatim from docs/SPEC.md Part 4 (Bontago-gmu.2, 2026-10-14).
> Work is tracked in Beads epics; this plan is no longer a live contract.

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
- Territory raster and shader, contested zones, holes (visuals and dissolve-on-contact), placement validation, block feed and timer with auto-drop, next-block preview, goal flag, win check, basic HUD.
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
- Magnet, freeze, glue, black hole (replaces gravity well, owner 2026-10-02).
- Stable-block freezing, body cap and removal, reconnect and late join, 2-hour soak test with bots, crash-free exports for Windows, Linux, and macOS.

---

## Decisions made — current target

- **Fidelity policy [OWNER, latest]:** prioritize original rules when concrete evidence exists. This supersedes conflicting earlier recollections, but not explicitly retained remake exceptions.
- **Cadence:** adopt the developer-described fixed-window placement lock, not immediate reset and not alternating players (§2.4).
- **Holes:** restore overlap holes as the fidelity target. Temporary cell holes remain a provisional approximation; exact original timing/physics are unverified. The no-overlap v2 mode is optional, not the default.
- **Capture hold [OWNER, explicitly confirmed during this audit]:** **20 seconds** (owner playtest 2026-10-03 asked to extend the 3 s confirmed here, 5 s, Bontago-1pi.31; owner playtest 2026-10-06 set 20 s, Bontago-1pi.91). Original all-goal objective and this remake hold must not be conflated.
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

The following is a **summary**, not a verbatim transcript, of [the owner's feedback](../bloody_mess.md) after playing the M3b build. Keep that source unchanged. Later original-evidence priority supersedes the immediate-reset timer and no-overlap/default-no-holes portions below; retained requirements are integrated in Part 2. This record must not override the current decisions above.

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
