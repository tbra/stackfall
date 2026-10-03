# QoL friction experiments: design contract (Bontago-1pi.18)

Planner output, design only. Checkout `M:/Bontago-worktrees/qol-plan`, branch `wt/qol-plan`,
base `bbbeaca` (verified: `git rev-parse` = bbbeaca, clean).
Owner source: game_roadmap 2026-10-02 "Qol tests". Each experiment is an opt-in toggle,
**default OFF**, so the shipped rules do not change until the owner picks.

## 0. Key finding: the four experiments are already built and merged

`git merge-base --is-ancestor` confirms 85763b0 (Bontago-1pi.18.1), 8c66ca1 (1pi.18.2) and
69a8f11 (1pi.18.3) are in the base. All four toggles exist, replicate, and have tests. So this
contract is **(a) the as-built contract with anchors, (b) the audit gaps, (c) the remaining
packages Q0-Q5**. Nothing below re-implements a toggle. Children 18.1-18.3 are closed.

Gaps found against the owner's request ("opt-in lobby/dev toggle"): there is **no lobby toggle**
(only the host-local F4 "QoL" tab), **no claim-radius visual**, **no experiment indicator for
clients**, **no ceiling on a continuous timer pause**, and the **SPEC does not mention the
experiments**. Plus two feel questions for the owner (section 6).

## 1. As-built shared wiring (anchors)

- Config: `config/QolExperiments.gd` (`class_name QolExperiments`, `Resource`), shared instance
  `config/qol_experiments.tres` (all toggles off). Pure helpers `effective_goal_radius()`,
  `effective_backlog_max()`, `effective_gift_slot_capacity()`, `sanitize()`, `to_dict()`,
  `static from_dict()` (wrong-typed or non-finite values fall back to the OFF defaults).
- Snapshot: `MatchConfig.qol: QolExperiments = null` (`config/MatchConfig.gd:102`; `sanitize()`
  :386; `to_dict()` writes key `"qol"` last :462; `from_dict()` :513). The host copies the shared
  tres once at `MatchLifecycle.start_match()` only when `config.qol == null`
  (`autoload/match/MatchLifecycle.gd:136-141`); a client keeps what `net_match_start` carried.
  Only the host's copy decides anything.
- Dev toggle: `ui/TuningPanel.gd:507` `_add_tab("QoL", [qol_experiments])`; hints in
  `config/tuning_panel_hints.tres` (lines ~655-663 ranges, ~1565-1578 descriptions).
- Replication: `Events.qol_feed_changed(slot_id, backlog, paused)`; `MatchNet.EVENT_QOL_FEED`
  (`net/MatchNet.gd:55`), host emit :1363, client validate+apply :2199-2205 (types and slot range
  checked, backlog clamped 0..`BACKLOG_MAX_CEILING` in `MatchFeed.apply_replicated_qol`); late-join
  replay only when non-default :1746-1751. Gift slot: `EVENT_GIFT_SLOT` + replay :2187.
- Existing tests: `tests/unit/test_qol_experiments.gd` (24 tests), `test_playercontroller_gift_slot.gd`,
  `test_hud.gd:765`; ENet: `tests/bench/qol_enet.gd` + `tools/run_qol_enet.ps1`,
  `tests/bench/gift_slot_enet.gd` + `tools/run_gift_slot_enet.ps1` (both under a 180 s deadline).

## 2. Experiment 1: pause the block timer on events / big topples (as built)

- **Rule.** `core/rules/TimerPause.gd` (pure) freezes a slot's timer when (i) a special triggered
  anywhere (`note_special()`: every slot paused for `pause_event_s`, refreshed by the next one) or
  (ii) the slot's own placed blocks above `topple_speed_threshold_mps` number at least
  `topple_moving_blocks_min` at a host scan (slot paused, held `pause_tail_s` after the condition
  last held). Gate: `timer_pause_enabled`; `timer_pause_on_special` selects (i).
- **Measured from existing signals.** (i) `Events.special_triggered`, mirrored host-side in
  `MatchNet._on_special_triggered` (:1450) which calls `MatchFeed.note_special_triggered()` (:388).
  (ii) `BlockRegistry.count_fast_blocks_by_owner(limit_sq, counts)` (`game/BlockRegistry.gd:494`),
  scanned every `topple_scan_interval_s` by `MatchFeed._tick_qol_pause()` (:354); test seam
  `MatchFeed._qol_moving_counts_source`. "Event" = special trigger only (not weather, sudden death,
  tilt); tilt/earthquake effects register through the topple count.
- **Where it bites.** `MatchFeed._tick_feed()` (:198): concurrent branch `if timer_paused(i): continue`
  before the decrement (so neither countdown, expiry nor the release-lock boundary advance); the
  hot-seat/turn-based branch does the same for the active slot. Client display timer holds while
  `_paused_mirror[slot]` (`_tick_client_display`). Disconnect-grace and eliminated slots are skipped
  before the pause check, unchanged.
- **Edge cases.** Early-release lock: the boundary that unlocks the prepared piece is also frozen.
  Sandbox timer-off still wins (`_feed_timer_enabled`). Blocks sliding off the disc count until
  removed (a few seconds, bounded by the kill plane/hole dissolve). **Gap:** no ceiling on a
  continuous pause (specials chaining to `max_chain_depth`, a long avalanche); see Q0.
- **Fields (all in `QolExperiments`, defaults).** `timer_pause_enabled: bool = false`,
  `timer_pause_on_special: bool = true`, `pause_event_s: float = 4.0` (0..30),
  `topple_moving_blocks_min: int = 4` (1..64), `topple_speed_threshold_mps: float = 1.5` (0.1..50),
  `pause_tail_s: float = 1.5` (0..30), `topple_scan_interval_s: float = 0.25` (0.05..2).
- **HUD.** Timer numeral becomes `||` and the ring turns the locked colour while paused
  (`ui/HUD.gd:145`, :342-347, :1099, :1111). No other change.
- **Tests.** `test_timer_pause_rule_special_and_topple`, `test_timer_freezes_during_topple_when_on_and_runs_when_off`,
  `test_timer_not_paused_with_toggle_off`, `test_special_event_pauses_timers_when_on`,
  `test_off_expiry_still_fires_the_forced_drop`.

## 3. Experiment 2: gift slot instead of the block queue (as built)

- **Rule.** With `gift_slot_enabled`, a claimed gift goes to a per-slot list
  (`MatchGifts._store_in_gift_slot`, `autoload/match/MatchGifts.gd:256`) instead of
  `replace_next_with_gift`; the ordinary queue and next preview are untouched. Instant gifts (Glue)
  still resolve at claim. A new claim into a full slot drops the OLDEST slotted gift (capacity 1:
  latest wins, matching the 2026-09-29 rule).
- **Activation.** New action `use_gift_slot` -> `PlayerController._use_gift_slot()` (`game/PlayerController.gd:661`)
  -> host or `MatchNet.submit_use_gift_slot()` (`net/MatchNet.gd:941`, RPC `net_request_use_gift_slot`
  :2043) -> `MatchGifts.request_use_gift_slot()` (:274). Host refuses (nothing changes) off-host, outside
  PLAYING/SUDDEN_DEATH, wrong or eliminated slot, off-turn seat in hot-seat/turn-based, empty slot, no held
  piece, or while a gift is already held or queued. Success pops the head, queues it, calls
  `MatchFeed.issue_gift_now(slot, gift_slot_min_window_s)` (:566): bumps `feed_seq` (retires in-flight
  intents), makes the gift the **held** piece immediately, no timer reset, but never below the minimum window
  so it is not auto-dropped on the spot.
- **Edge cases.** Slot use **discards the held ordinary piece** and burns the previewed next draw
  (`replace_next_with_gift` calls `bag.next()` once before the carrier draw). A gift held at expiry is force-dropped
  (never backlogged). After the gift is released the ordinary cadence continues (gift exception, SPEC 2.4); a locked
  prepared piece stays locked.
- **Fields.** `gift_slot_enabled: bool = false`, `gift_slot_capacity: int = 1` (1..3),
  `gift_slot_min_window_s: float = 2.0` (0..10).
- **Input Map.** `a["use_gift_slot"] = [_key(KEY_G), _pad(JOY_BUTTON_RIGHT_STICK)]`
  (`tools/bootstrap_project.gd:227`, mirrored in `project.godot`). The pad press shares R3 with the debug
  perf-overlay chord; `PlayerController` ignores it while Back is held (:632). Keyboard and gamepad both bound.
  Options rebinding picks it up automatically (`ui/OptionsMenu.gd` excludes only debug actions).
- **HUD.** A third card `GIFT: <name> [xN]` beside HELD/NEXT (`ui/HUD.gd:194`, `_refresh_gift_slot` :1247).
  **Gap:** the card does not show the bound key/button.
- **Bots.** `game/BotController.gd:190` spends a slotted gift as soon as legal via the same host method.
- **Tests.** `test_gift_slot_*` (9 in `test_qol_experiments.gd`), `test_playercontroller_gift_slot.gd`,
  `test_hud.gd:765`; ENet `gift_slot_enet` (slot replicates, client intent, host validates).

## 4. Experiment 3: backlog instead of force-drop (as built)

- **Rule.** `MatchFeed._try_backlog_push()` (:320) runs at expiry in the concurrent branch only when the piece is
  unspent (not release-locked): if `effective_backlog_max()` has room and the held piece is not a gift, the held
  piece is appended to `_backlog[slot]`, a fresh bag piece is issued, `feed_seq` bumps, and a new full interval
  starts; no `feed_timer_expired`. When the backlog is full the next expiry force-drops the held piece as today.
- **Cap and full.** `backlog_max: int = 2` (clamped 1..`BACKLOG_MAX_CEILING` = 3). Owner asked for 2-3.
- **Draw order.** `_issue_next_block()` (:165) pops the backlog (FIFO, oldest first) **before** touching the bag, so
  placing consumes the backlog first; `next_shape()` previews the backlog head; the `feed_block_issued` next id
  names it. A pending gift carrier stays pending for the first bag draw after the backlog.
- **Replication.** Count only (`qol_feed_changed`); clients get the head shape through `next_id`. Cleared at
  `_build_bags()` (:400).
- **HUD.** `NEXT` label gets ` +N` (`ui/HUD.gd:923`). Hot-seat and turn-based never backlog (single-actor branch).
- **Tests.** `test_backlog_queues_until_full_then_forces`, `test_placing_takes_from_the_backlog_first`,
  `test_late_join_replay_carries_qol_feed_state_only_when_set`; ENet `qol_enet` (backlog mirror = 1 each).

## 5. Experiment 4: bigger goal claim radius (as built)

- **Rule.** The no-build disc, its drawn circle and the replicated circle wire keep `goal_zone_radius`
  (`MatchTerritory.gd:161`, `_goal_radii`). The **claim radius** `effective_goal_radius(goal_zone_radius)` =
  `goal_zone_radius * goal_radius_multiplier` (default 2.0, clamp 1..4) feeds `WinChecker.claim_at()`
  (`core/rules/WinChecker.gd:172`): every in-group owned cell centre within the radius votes; the team with the most
  cells claims the goal (that team's most common group, lowest id on a tie); a tie or no owner claims nothing.
  Radius 0 reads the single flag cell exactly as today.
- **Territory interplay.** Influence/contest is untouched; only the claim test widens. The shared 3 s hold, the
  "all goals in one group" test and home connectivity still apply (`WinChecker` :77, :142-147). A no-build disc is still
  unplaceable. A contested neighbour tying inside the radius leaves the goal unclaimed.
- **Call sites** (all use `MatchTerritory._claim_radius()` :172): `ClassicObjective`/`CaptureFlagObjective`
  `set_claim_radius`, bot `beacon_held_by_own` (:387), `game/Main.gd:787` diagnostics. Host and client both read it from
  `Match.config.qol`.
- **Fields.** `goal_radius_enabled: bool = false`, `goal_radius_multiplier: float = 2.0`.
- **Gaps.** No ring is drawn for the claim radius (DECISION at `MatchTerritory.gd:169`); cost of
  `claim_at` grows with `(2*reach+1)^2` cells per goal per solve (5 goals at multiplier 4 is the worst case) and has no
  benchmark.
- **Tests.** `test_goal_radius_toggle_leaves_no_build_disc_and_scales_claim_radius`,
  `test_claim_radius_captures_when_territory_reaches_radius_not_flag_cell`, `test_claim_radius_tie_between_teams_is_unclaimed`,
  `test_bot_beacon_held_follows_claim_radius_toggle`.

## 6. Remaining work: interfaces, packages, order

### Interface stub (lands first): Q0 adds to `config/QolExperiments.gd`
```gdscript
const ID_TIMER_PAUSE: StringName = &"timer_pause"   # likewise ID_BACKLOG, ID_GOAL_RADIUS, ID_GIFT_SLOT
@export var pause_max_s: float = 10.0                # NEW: longest continuous pause; sanitize 1.0..60.0
func any_enabled() -> bool
func active_ids() -> PackedStringArray               # ids of the enabled toggles, fixed order
static func with_toggles(base: QolExperiments, timer_pause: bool, backlog: bool,
		goal_radius: bool, gift_slot: bool) -> QolExperiments   # duplicate(base) + the four enable flags
```
`pause_max_s` joins `to_dict/from_dict/sanitize` (appended key, missing key keeps the default). It is an F4-visible
`@export`: add its description to `config/tuning_panel_hints.tres` `descriptions` and a slider range
(`Vector2(1.0, 60.0)`); `test_tuning_panel` is a **required** check for Q0.

### Package table (one outcome each, disjoint files, ~30 min, Sonnet unless stated)

| Id | Outcome | Owned files | Needs | Targeted tests (run, then one retry) |
|----|---------|-------------|-------|------------------------------------|
| Q0 | Stall guard + interface stub. `TimerPause` latches a slot "exhausted" once continuously paused `pause_max_s`, returns false until its raw cause fully clears, then re-arms. `any_enabled/active_ids/with_toggles` | `config/QolExperiments.gd`, `config/tuning_panel_hints.tres`, `core/rules/TimerPause.gd`, `tests/unit/test_timer_pause.gd` (new), `tests/unit/test_qol_experiments.gd` | none | `test_timer_pause,test_qol_experiments,test_tuning_panel,test_match_config` |
| Q1 | Lobby "Experiments" section: four host-editable checkboxes in the Advanced rules popup; clients see them read-only | `ui/Lobby.gd`, `ui/Lobby.tscn`, `tests/unit/test_lobby_qol.gd` (new) | Q0 | `test_lobby,test_lobby_qol,test_match_config,test_net_match_config_flag,test_qol_experiments` |
| Q2 | Claim-radius ring visual on each beacon when the toggle is on | `game/GoalFlag.gd`, `game/GoalFlag.tscn`, `game/Field.gd` (one call site), `autoload/Match.gd` (accessor `qol_claim_radius() -> float`), `config/BeaconVisualTuning.gd`, `config/beacon_visual_tuning.tres`, `config/tuning_panel_hints.tres`, `tests/unit/test_goal_flag_claim_ring.gd` (new) | Q0 merged (hints file) | `test_goal_flag_claim_ring,test_goal_control,test_beacon_collision,test_qol_experiments,test_tuning_panel` |
| Q3 | HUD: "Experiments: ..." muted line from `Match.config.qol.active_ids()`; gift-slot card shows the bound `use_gift_slot` glyph | `ui/HUD.gd`, `ui/HUD.tscn` (only if a node is needed), `tests/unit/test_hud.gd` | Q0; after Bontago-1pi.23 (HUD hotspot) | `test_hud` |
| Q4 | Acceptance: ENet matrix + claim_at cost bench | `tests/bench/qol_enet.gd`, `tools/run_qol_enet.ps1`, `tests/bench/bench_claim_radius.gd` + `.tscn` (new), `config/BenchBudgets.gd` | Q0, Q1 | `run_qol_enet.ps1` (one run, 180 s kill), `run_gift_slot_enet.ps1` (one run), bench alone on an idle machine |
| Q5 | SPEC note: an "Experimental toggles (default off)" row group in 2.8, the `use_gift_slot` row in the 2.5 controls table, and the [ORIGINAL] exceptions (section 8) | `docs/SPEC.md` (orchestrator or Haiku; no review) | none | doc proofread |

**Order.** Q0 and Q5 first (parallel). Then Q1, Q2, Q3 in parallel (disjoint files; `tuning_panel_hints.tres` is
touched only by Q0 and Q2, hence "Q2 after Q0"). Q4 last. Each package: targeted GUT only, no full suite; the orchestrator
runs the full gate once for the combined game-code batch. Q0/Q1/Q2 touch `config/`, `core/` or `ui/Lobby*`: Q0 needs the
reviewer pass (`core/` rule); Q1-Q3 are UI, no independent review.

### Q1 specifics (lobby toggle, host authority, replication)
- Controls `%QolTimerPauseCheck`, `%QolBacklogCheck`, `%QolGoalRadiusCheck`, `%QolGiftSlotCheck` (CheckBox, default
  unpressed), registered in `_settings_controls` (host-only editable, `_update_host_only_state()` disables them for clients),
  wired in `_connect_control_signals()` to `_on_toggled`, added to `_wire_focus_chain()` (gamepad), plus a chip
  "Experiments: N on" in `_update_advanced_rules_summary()` (:835).
- `_config_from_controls()` (:966) sets `config.qol = QolExperiments.with_toggles(shared.duplicate(), ...)` where `shared` is the
  preload of `config/qol_experiments.tres` (numeric parameters stay F4-tunable; the four enable flags come from the checkboxes).
  `_apply_data()` (:1025) reads `config.qol` null-safely inside the `_applying_remote_data` guard so a client mirrors the host.
- Flow: `Net.set_lobby_data()` (`autoload/Net.gd:554`, reliable `_rpc_lobby_data`, Steam JSON key) carries `"qol"`;
  `_on_start_pressed()` duplicates `_last_config` into `start_requested`; `start_match()` keeps the non-null `qol` (:140) so
  the lobby wins over the F4 snapshot. Hot-seat/sandbox/tutorial have no lobby and keep the F4 shared-resource path.
- Host authority is unchanged: a client cannot start or edit; `MatchConfig.from_dict()/sanitize()` clamp wire garbage.
- Tests: defaults off; toggle publishes `qol` booleans; client controls disabled; remote data sets checkboxes without
  re-publishing; all-off still publishes an explicit all-off `qol` (a shared-tres toggle left on in F4 must not leak in:
  the test sets then restores the shared resource); `start_requested` config carries the toggles.

## 7. Block pool interaction (Bontago-1pi.19, undecided)

`docs/BLOCK_POOL_PLAN.md` changes what the bag draws, not the feed state machine. Backlog holds `BlockShape` objects the
bag already drew and announces them by id; gift carriers also resolve by id (`MatchFeed._shape_by_id`). So any pool or custom
shape registered before match start (BLOCK_POOL section 4/5) works unchanged, and a smaller pool just repeats shapes in the
backlog. Gift slot is independent of the pool. Conflicts are file-level only: BLOCK_POOL P2 edits `MatchFeed._build_bags()`
(:400) and must keep the QoL lines (`_backlog.clear()`, `_timer_pause` init, mirror arrays); BLOCK_POOL P3 and Q1 both own
`ui/Lobby.gd` and `ui/Lobby.tscn` (serialize, either order); BLOCK_POOL P0 and nothing here touch `MatchConfig.gd`.
Add `test_qol_experiments` to BLOCK_POOL P2's targeted set.

## 8. [ORIGINAL] rules touched and owner decisions

**[ORIGINAL] impact (default OFF, so shipped behaviour is unchanged).** SPEC 1.2/2.4/2.5 "Expiry forces release" is tagged
[ORIGINAL, developer explanation]: experiments 1 (pause) and 3 (backlog) change it only when toggled on. "Next-block preview
[ORIGINAL]": the backlog head shows as NEXT only with the toggle. The 3 s capture hold, goal no-build zones and overlap holes
are not changed. No pause point is triggered by building or shipping the toggles; **promoting any experiment to a default is a
separate owner decision after playtest.**

**Owner decisions needed (none blocks Q0-Q5).**
- **O1, confirm the reading above.** Options: (A) as written: opt-in only, owner decides after play; (B) treat any
  [ORIGINAL] expiry change as needing a `decision` bead before even the opt-in ships. Recommend A: the owner requested these
  as tests and they are already merged default-off.
- **O2, gift-slot use discards the held ordinary piece (and the previewed next draw).** Options: (A) as built, consistent with
  "latest gift wins"; (B) stash the held piece as the next piece so the gift costs nothing; (C) allow use only while no
  ordinary piece is unspent. Recommend A for the first playtest; revisit with the owner's feel feedback.
- **O3, claim rule inside the radius.** As built: majority of owned cells within `goal_zone_radius * multiplier`, tie = unclaimed.
  Alternatives: any owned cell of one team (more generous), or the territory edge reaching the radius while the base must still be
  covered (tighter). Recommend keep as built, and let the owner pick the multiplier (default 2.0, ceiling 4) once Q2 shows the ring.

## 9. Planner DECISIONs (minor, recorded)

1. Lobby publishes an explicit `qol` (never null) so checkboxes are the single source for the four enable flags; numeric
   parameters stay in the shared tres (F4). Wire cost is one small dict; Steam lobby JSON stays far below its value limit.
2. `pause_max_s` default 10.0 s; after the cap a slot behaves unpaused until the raw cause clears, then re-arms. The cap is a host
   decision; clients follow the existing `qol_feed_changed` event, so no wire change.
3. "Events" for experiment 1 stay = special triggers (as built); weather, tilt and sudden death are not separate triggers.
4. Gifts are never backlogged (a held gift expires into a forced drop as today).
5. `use_gift_slot` is unthrottled: the host refusal path is cheap and idempotent.
6. Q2 draws one flat translucent ring (neutral colour) per beacon whenever the claim-radius toggle is on (as built: at multiplier 1.0 it coincides with the no-build circle); the overlay
   circle wire stays untouched (no protocol change). A beacon colour/alpha `@export` on `BeaconVisualTuning` needs F4 hints.
7. Q4's cost budget lives in `BenchBudgets` (no magic numbers); baseline recorded from the first run on an idle machine.

## 10. Risks

- Pause plus backlog interplay: a slot paused through its boundary never backlogs; correct, but a long pause stalls the whole
  cadence for that slot until Q0's cap.
- `claim_at` cost at multiplier 4, five goals, 20 Hz solve: unmeasured (Q4 bench). If over budget, cache per-goal cell lists.
- Q1 and BLOCK_POOL P3 both edit Lobby; and Q3 shares `ui/HUD.gd` with Bontago-1pi.23. Serialize, do not parallelize those pairs.
- Tests touching the shared `qol_experiments.tres` must restore it (global state), else the full gate goes order-dependent.
