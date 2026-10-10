# Bot self-play data capture during the 2-hour soak (Bontago-1t5.9)

Base main 75b030e3. Design contract only; Beads owns status. Combines Bontago-8or.14 (2 h 8-bot soak,
docs/M8_PLAN.md P8) with the data-capture half of Bontago-1t5.8 (train bots). No ORIGINAL rule is touched;
no gameplay change ships until the owner approves a trained weight set (D4).

## 0. Facts read (anchors)

- Policy: `BotController._tick_generating()` (game/BotController.gd:200) samples `profile.candidate_count`
  (default 60) `BotCandidate`s (core/ai/BotCandidate.gd: origin, orientation_index, support_height,
  footprint_cells, on_top_of_own_stack, corner_support_hits, shape_height); `_tick_acting()` (:433) calls
  `_send_best_placement()` (:542) -> `BotPlacementScorer.pick_best()` (core/ai/BotPlacementScorer.gd:509) ->
  `score()` (:415) = linear sum: weight_height*support_height - weight_goal_progress*goal_metric +
  weight_stability*stability - weight_risk*risk, plus a mode term (`_mode_term`, `_multi_goal_term`).
  All weights are `@export`s on `BotTuning` (config/bot_tuning.tres, loaded at BotController.gd:37).
  Specials go through `BotSpecialPlanner.plan()` (:438) first; held-special decisions are a separate stream.
- Aim noise (`_aim_noise_offset`) and rng (`_seed_rng`, BotController.gd:116) make the placed point differ
  from the chosen candidate; the request returns a reason (`PlacementRules.REASON_*`, `_apply_rejection_backoff`).
- Soak entry: `godot --headless --path . -- --headless-host --bots=8 --seconds=7200 --loop-matches`
  (docs/M8_PLAN.md:398-411; game/MainHeadlessBotsFlow.gd `_on_headless_loop_state_changed` prints one
  `HEADLESS_MATCH index= mode= seed= duration= winner_team= placements= homes_alive=` line per match;
  periodic `HEADLESS_BOTS` lines). Gate = no crash + `tools/triage_log.py` not exiting non-zero.
- Outcome signals that already exist: `Match.territory_share(team_id)` (autoload/Match.gd:921),
  `Match.winner_team()`, `slot.home_flag_alive`.
- Known data bias: 2-4 player Elimination can stall (Bontago-1t5.6, undecided); 8-bot matches do eliminate.
  Data from small elimination matches is low value until 1t5.6 is answered.

## 1. What a decision records (schema v1)

One JSONL record per ordinary-placement decision (`_send_best_placement` with override==null) and, as a
separate `kind`, per special/gift/override decision (logged but flagged `policy="special"` so trainers
can drop them). One file per bot per match; a first line `{"kind":"header",...}` carries schema_version,
match seed, mode, map id, bot count, difficulty, BotTuning weights snapshot, git revision.

Decision record fields (all numbers rounded to 3 dp; ints stay ints):
- `t` (match time s), `slot`, `team`, `shape_id`, `feed_seq`, `piece_index`.
- state: own/enemy `territory_share`, own block count, own tower max height, own home alive, enemies
  alive, nearest enemy circle distance, active special count, `mode_goal` summary (mode, target home index).
- `cands`: array (<= candidate_count) of `{o:[x,z], r:orientation, h:support_height, sh:shape_height,
  ct:corner_support_hits, top:on_top_of_own_stack, terms:[height, goal, stability, risk, mode]}` where
  `terms` are the five unweighted scorer components (see BotScoreTerms below) so any linear weight vector
  can be re-scored offline without Godot.
- `chosen`: index into `cands`; `placed_origin` (after aim noise), `reason` (request result),
  `scored_best` (argmax index recomputed from terms; equals `chosen` unless override/special - mismatches
  are counted in the footer, a passive self-check).
- outcome (appended when the horizon elapses, written as a second record `{"kind":"outcome","id":..}`
  so the decision line can be flushed immediately): `d_share_10s`, `d_share_30s`, `d_share_60s`
  (own territory_share minus its value at decision time), `own_blocks_alive_60s`/`placed_block_alive_60s`
  (bool: the placed block still exists and is inside own territory), `home_alive_60s`.
  Match-end record per bot: `{"kind":"match_end","winner_team","final_share","won","eliminated_at"}`;
  trainers join it to decisions by (file, slot) for the sparse terminal reward.
Reward definition for v1 trainers: dense = `d_share_30s` (+ alive bonus), sparse = match_end `won`/final share.
Horizons live in a new `BotRecordingConfig` Resource (no magic numbers).

Cost estimate (to be MEASURED in BT3 on a 5-min match, scale, record in the Bead):
- Decisions: assume one per ~4 s per bot -> ~1800/bot, ~14k per 2 h at 8 bots (upper bound 3x).
- Bytes: ~60 cands x ~90 B + state/outcome ~600 B ~ 6 KB/decision -> ~90 MB (<= ~300 MB upper bound) of JSONL
  per soak. Optional `.gz` on rotate is a Python-tool step, not in-engine.
- CPU: the recorder only re-evaluates `score_terms` for the already-generated candidates (~60 x one scorer
  pass per decision, ~0.01 decision/frame/bot) and string-formats on the same think frame; budget acceptance
  is p95 physics-frame delta < 5% and peak frame delta < 2 ms on `tools/bench_botmatch.tscn` with recording on vs
  off (idle machine). Disk writes use one buffered `FileAccess` per bot, flushed every N decisions and on match
  end (N in config), never per decision.
- Location: explicit absolute `--bot-record=<dir>`; the sink refuses `res://` and unwritable paths, defaulting
  to nothing (recording is OFF unless the flag is given). Soak runs use
  `M:/Bontago-tools/scratch/bot-data/<run-id>/` (scratch, never committed).

## 2. Soak stays a valid stability gate

- Policy unchanged: the recorder is an observer called AFTER `pick_best` has chosen and the request has been
  sent; it never feeds back (no extra rng draws - it holds no RandomNumberGenerator; no changes to
  `_candidates`, countdown or state; no new `await`). `score()`/`pick_best()` bodies untouched; the new
  `score_terms()` is a separate static (the same sub-terms, returned unweighted) with a unit test asserting
  `weighted_sum(terms, tuning) == score(...)` to 1e-6 across modes, so the observer cannot drift from policy.
- Passivity test (BT2): same seed, two short headless bot matches (recording off vs on), assert identical
  placement counts/sequence (`HEADLESS_MATCH` placements, winner, first N placed origins). Sync-determinism
  is not guaranteed across wall-clock, so the test uses a fixed-step test harness (same as
  tests/unit/test_headless_bot_match.gd pattern) and compares counts plus per-decision chosen index.
- Recorder failure policy: write errors disable the recorder and print one `BOT_RECORD_ERROR` line; the
  match keeps running. That line is NOT an `ERROR:`/`push_error`, so triage_log's signatures are unchanged.
  The recorder's own lines use a `BOT_RECORD` prefix summarised in the final soak report only.
- triage_log gate unchanged: still `python tools/triage_log.py <log>`; exit non-zero on a confident likely-bug
  fails the soak. Recording adds no WARNING/ERROR output by design (acceptance grep).
- Soak run: shipping bots (Hard difficulty profile as configured; mix Easy/Normal/Hard allowed in a
  separate data run, but the gate run uses the same bot mix as the original P8 command) with
  `--bot-record=<dir>` added. Acceptance for 8or.14 is unchanged plus: recorder footer shows
  `policy_mismatch == 0`, files parse (BT4 validator), and recording overhead within budget (above).
- Data validity caveat: the gate run explores only the shipped policy (on-policy, little weight diversity).
  That supports offline regression (T1) but not search; weight diversity comes from separate training runs
  (T2), which are NOT the gate.

## 3. Offline training options for 1t5.8 (ranked effort/risk)

T1 (recommended first; low effort, low risk): offline refit of the existing linear weights. Python
  (tools/, numpy if available, else pure-Python ridge) reads decision files, builds per-decision candidate
  term matrices, fits weights with a listwise softmax/ranking objective weighted by outcome
  (advantage = d_share_30s minus per-team-time baseline; AWR-style) with L2 toward the shipped weights, and
  emits a proposed `config/bot_tuning.tres` weight diff (as text, not applied). Validate by re-scoring held-out
  matches (top-1/regret agreement) then by head-to-head headless matches. Honest limit: on-policy data from
  one weight vector gives weak identifiability; expect modest gains and use it mostly to sanity-check term
  scales and find dead terms.
T2 (medium effort, medium risk, compute heavy): self-play evolution (CMA-ES / simple ES) over ~15
  BotTuning weights. External driver `tools/bot_es.py` launches N parallel headless matches (4 candidate bots with
  perturbed weights vs 4 baseline bots, same seeds paired for variance reduction), fitness = mean
  final territory share and win rate, 8-bot matches only (avoids the 1t5.6 stall). Needs a per-slot
  weight-override seam (`--bot-weights=<json>` -> per-slot BotTuning duplicate in BotController.setup).
  Cost: ~5 min per match; population 12 x 6 paired seeds x 30 generations ~ 2160 matches ~ 180 h serial,
  ~25-45 h on 4-8 parallel processes. Practical only with a shortened match length config
  (`--seconds` bounded) and bench-mode physics; measure first. Output: a tuned `bot_tuning.tres`.
T3 (higher effort/risk): small learned scorer, 14-input x 16 hidden x 1 MLP (+ the 5 terms as inputs)
  trained in Python (numpy/pure Python; no new addon), exported as a Resource of PackedFloat32Arrays and
  evaluated in plain GDScript (`core/ai/BotLearnedScorer.gd`, static, ~0.4k MAC/candidate, ~25k MAC/decision;
  time-slice with `candidates_per_frame`). Needs T2-grade data diversity plus a policy-gradient/ES loop,
  an A/B gate against heuristic, and a per-difficulty switch; deterministic seed and float parity tests.
  Do not start before T1/T2 results show the linear policy is the ceiling.
Not recommended: PyTorch/ONNX/GDExtension inference (new addon/dependency; needs owner approval, CLAUDE.md).

Scope: Hard only first (Easy/Normal are intentionally weaker per spec 2.9); mode terms (CTF/Sky/Elim/
Domination) have separate weights - train Classic + Elimination(8) first.

## 4. Packages (<= ~10 owned files; dependency order BT1 -> BT2 -> BT3 -> soak -> BT4 -> optional BT5/BT6)

BT1 - interface stub + score decomposition (implementer, Sonnet). Owns:
  core/ai/BotScoreTerms.gd, core/ai/BotDecisionRecord.gd, core/ai/BotPlacementScorer.gd (additive only:
  `static func score_terms(...)-> BotScoreTerms`; refactor of score() forbidden), config/BotRecordingConfig.gd,
  config/bot_recording.tres, tests/unit/test_bot_score_terms.gd (+ .uid sidecars). Interfaces:
  `class BotScoreTerms {height, goal, stability, risk, mode: float; func weighted(t: BotTuning) -> float}`;
  `class BotDecisionRecord {static func to_dict(...) -> Dictionary; static func to_json_line(d) -> String}` pure.
  `BotRecordingConfig {horizons_s: PackedFloat32Array, flush_every: int, enabled_default := false}`.
  Acceptance: weighted == score across all modes (Classic, CTF, Sky, Elimination, Domination, multi-goal),
  scorer tests unchanged and green, layer lint clean (core only). Consumers start only after this is merged.
BT2 - recorder + controller hook (implementer or netcode-aware Sonnet). Owns: game/BotDecisionRecorder.gd
  (Node: `begin_match(header)`, `on_decision(slot, candidates, terms, chosen, placed, reason)`, `on_tick(t)`
  horizon sampler, `end_match(final)`, `stats()`), game/BotController.gd (one hook line in
  `_send_best_placement` after the request; one setter `set_recorder`), tests/unit/test_bot_decision_recorder.gd,
  tests/unit/test_bot_recording_passive.gd. Depends BT1. Acceptance: JSONL round-trips, outcome joins, error ->
  disabled not crash, passivity test (section 2) green, no `Match`/Net autoload type refs added to core (lint_layers).
BT3 - CLI + match lifecycle + soak wiring. Owns: game/MainHeadlessBotsFlow.gd (`--bot-record=<dir>`, header,
  per-match file rotation under --loop-matches, `end_match` on END; extend nothing in HEADLESS_MATCH/HEADLESS_BOTS
  formats), tests/unit/test_headless_bot_record_flag.gd, tools/bench_botmatch.gd (optional `--record` toggle for the
  overhead A/B). Depends BT2. Acceptance: 5-min `--bots=8 --seconds=300 --bot-record=<scratch>` run yields
  parseable files, measured decisions/bytes (replace estimates in this doc's Bead comment), overhead within
  budget, `triage_log` clean. Targeted tests only; never full suite.
SOAK (8or.14, integrator, idle machine, after BT3 and P0-P6): run the section 2 command with recording on;
  record revision, log path, data dir, sizes, triage exit code.
BT4 - Python dataset tooling (implementer). Owns: tools/bot_dataset.py (validate/summarise/join/size report),
  tools/bot_fit_weights.py (T1), tools/test_bot_dataset.py (follow the repo's existing tools python-test
  convention; worker checks), tools/README.md (short section). Depends on BT3 files (sample file may be a checked-in tiny
  fixture under tests/fixtures/, <= 100 KB). Acceptance: validator rejects bad schema, T1 on the soak data prints
  held-out top-1 agreement and a weight diff; no `.tres` written without `--write-proposal <path>`.
BT5 (only if owner approves T2) - override seam + ES runner. Owns: game/BotController.gd (setup takes optional
  BotTuning override), game/MainHeadlessBotsFlow.gd (`--bot-weights`), tools/bot_es.py, tests. Depends BT3;
  serialise with BT2/BT3 on the two shared files (file ownership, not function ownership).
BT6 (only if owner approves T3) - learned scorer + export format. Owns core/ai/BotLearnedScorer.gd,
  config/BotLearnedModel.gd, tests, trainer script. Depends BT5 results.

## 5. Risks

- Shared files: BotController.gd and MainHeadlessBotsFlow.gd are touched by BT2/BT3/BT5; strictly serial in one
  checkout.
- Data volume surprise (decisions rate unknown): BT3 measures before the 2 h run; cap with `max_bytes` in config.
- Soak disk write on an idle benchmark machine could perturb timing: buffered writes; compare soak overhead.
- Outcome credit is noisy (many bots place concurrently, share moves for other reasons); paired-seed ES (T2) is
  the honest evaluation, T1 only a heuristic.
- Elimination stalls (1t5.6) and unknown mode mix in --loop-matches: BT3 records `mode` per match; training
  filters on it.
- Tuned weights would change shipped bot behaviour: gated by owner approval (D4) and head-to-head matches.

## 6. Owner decisions (answer through Beads)

D1 Scope: combine as proposed (gate run records passively; training stays a separate offline step)? Recommend yes.
D2 Approach: T1 offline refit first, T2 ES only if T1 shows promise, T3 learned MLP deferred? Recommend yes.
D3 Status: move 8or.14 out of deferred (soak with recording) and 1t5.8 to open/in-progress for BT1-BT4 only?
   Recommend 8or.14 stays deferred until P0-P6 land (as before) but BT1-BT3 can proceed now; 1t5.8 reopens for BT1-BT4.
D4 Shipping: may a trained weight set replace config/bot_tuning.tres for Hard only after it beats the current bots
   in paired head-to-head matches (e.g. >=55% win share over >= 100 matches)? Recommend yes, Hard only.
D5 Compute: authorise multi-hour parallel headless runs for T2 on the owner machine (idle windows)? Optional.
D6 Mode scope for first training: Classic + 8-player Elimination only; others later. Recommend yes.
D7 Related: Bontago-1t5.6 (small-count Elimination stall) still blocks useful small-match data; answer separately.
