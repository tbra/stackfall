# Match reset audit and plan (Bontago-1pi.46)

Owner requirement (2026-10-03): after leaving a match (pause Leave, results Back
to lobby, Replay, disconnect, lobby Back, tutorial exit) and starting another
(any mode, map, weather or sky; local, host or client) the new match must be
indistinguishable from the same match started first after launch. User
preferences (Options, bindings) persist.

Base: `wt/reset-audit` = `84c70a0` + pass 1 `01bcf1f` (`CameraRig.reset_view()`,
`RainPuddles.clear_on()`, `Main._reset_match_presentation()` at world build/end).
Read-only audit; no code was run.

## 1. Lifecycle paths traced

| Path | Route in code | Reaches today |
|---|---|---|
| Pause Leave, online | `Main._on_pause_leave_requested` (Main.gd:1176) -> `Net.leave()` -> `_on_net_mode_changed(OFFLINE)` (1041) -> `_end_match_world()` + `Match.abort_match()` | world teardown, rules reset |
| Pause Leave, sandbox | Main.gd:1180-1185: free `_sandbox` first, `abort_match()` -> `(X->LOBBY)` -> `_end_match_world()` | same; Sandbox `_exit_tree` (Sandbox.gd:124-133) restores `Engine.time_scale`, `paused`, territory flags |
| Results Back to lobby / Replay | `abort_match()` or `start_match()` from END (MatchLifecycle.gd:172-176) -> `(X->LOBBY)` then `(LOBBY->LOADING)` | `_end_match_world()` then `_build_match_world()` |
| Client: host quits / timeout | `Net._on_server_disconnected` -> `leave()`; `_on_loading_readiness_timed_out` (Main.gd:1112) | same as online Leave |
| Lobby Back | `_on_lobby_back_requested` -> `Net.leave()` (Main.gd:1133) | menu |
| Tutorial exit | Tutorial aborts -> `(X->LOBBY)` -> `_end_match_world()`; `_on_tutorial_finished` (547) | menu |
| New match, lobby/client/headless | `(LOBBY->LOADING)` -> `_build_match_world()` (1365); client via `MatchNet.net_match_start` -> `reset_counters()` + `start_match()` (MatchNet.gd:2108-2113) | pass-1 reset at top of build |
| New match, sandbox/tutorial from menu | `start_sandbox_from_menu` (431), `start_tutorial_from_menu` (503) set `_world_built = true` and bypass `_build_match_world` | **no reset, no `configure_match_sky`** |

The rules half already has one entry point: `MatchLifecycle._reset_match_state()`
(MatchLifecycle.gd:264-320), run by every `start_match()` and `abort_match()` on host
and client. It covers blocks, slots, feed, gifts (`MatchGifts.reset`, :1220),
stats, territory objects, loading gate, countdown hold, tilt/balance. The
presentation half has no equivalent.

## 2. State-holder table

Survives = state from match A is still visible/active when B starts (after pass 1).

| Holder (file:line) | Holds | Survives? Evidence | Reset today |
|---|---|---|---|
| CameraRig (game/CameraRig.gd:99-167) | zoom, pitch, yaw, target, peek/focus, shake, tweens | No (pass 1) | `reset_view()` :433 from Main build/end |
| CameraRig.suppress_pad_home_focus (:92) | pad Back = home focus disabled | **Yes**: set true by `Sandbox.set_camera_rig` (Sandbox.gd:149); nothing clears it | none (**G4**) |
| Field RainPuddles child (vfx/weather/RainPuddles.gd) | wetness, patch layout | No (pass 1) | `clear_on()` from Main |
| Field tilt/holes/flags/overlay (game/Field.gd:987-1022) | tilt spring, mirror, balance, holes, flags, raster, circles | No | `clear_match_state()` from `_end_match_world` |
| Field snow caps/cover | snow geometry | No | `SnowEffect.restore` (SnowEffect.gd:165-185), `SnowNet.clear_client` (SnowNet.gd:181-197) |
| TerritoryOverlay wet/fog (game/TerritoryOverlay.gd:78, 1101, 1112) | wet sheen, disc fog | No | Rain/Fog presentation `_exit_tree` (RainPresentation.gd:160, FogPresentation.gd:39) |
| Skybox theme/cycle (game/Skybox.gd:148-188, 933-945) | theme, `_cycle_theme`, sky `process_mode`, light, ambient life; `set_theme_by_id` writes shared `config.theme_name` | **Yes** for sandbox/tutorial-from-menu and menu time: only `_build_match_world` calls `configure_match_sky` (Main.gd:1403); launch theme is never restored | partial (**G1**) |
| Skybox weather look (:355-393, 756, 1310-1346) | storm blend, overcast, weather fog | Fades with CloudCeiling (below) | presentation exits / ceiling push |
| CloudCeiling (vfx/weather/CloudCeiling.gd:15-25, 77-90) under MatchNet autoload | `_amount`, `_storm_amount`, `_overcast`, pushed storm sky | **Yes** for `fade_out_s` = 7 s (WeatherCeilingTuning.gd:69): B (Replay, quick re-host, sandbox) starts overcast/storm-tinted | none (**G2**) |
| WeatherPresenter `_instances` (vfx/weather/WeatherPresenter.gd:8) | live presentation scenes | No: `weather_stopped` frees them | `_on_stopped` :69 (queue_free) |
| BreezePresenter (vfx/weather/BreezePresenter.gd:42-51) | gust visuals | No | clears on LOADING/LOBBY/END |
| WeatherFogShader statics (vfx/weather/WeatherFogShader.gd:14-17) | fog strength/begin/end/color | strength 0, other values stale (no visual) | parity only |
| MatchWeather (autoload/match/MatchWeather.gd:250-305) | schedule, event, effect physics, debug override | No | `reset()` on LOADING/LOBBY/END; effects `restore()` (RainEffect.gd:105, StormEffect.gd:148) |
| BreezeEffect (autoload/match/BreezeEffect.gd:58-74) | gusts, F4 enabled | No | `begin()` re-reads `tuning.enabled` |
| MatchTerritory circle arrays (autoload/match/MatchTerritory.gd:75-79, 787-791) | last solve's influence circles | **Yes**: not cleared by `_reset_match_state` or `_build_territory` (:112-161). During B's LOADING/COUNTDOWN the host's `MatchNet._process` -> `replicate_territory()` (MatchNet.gd:371-375) sends `_encode_circles()` (:749) = A's circles, so clients draw A's influence over B's empty disc until the PLAYING seed solve (MatchLifecycle.gd:419); bots/diagnostics read them too (BotController.gd:683, Main.gd:914) | none (**G3**) |
| Match cat/specials (autoload/Match.gd:206-237, 390-408) | cat, paintball/black-hole visuals under blocks parent | No | `end_cat`, `_clear_blocks` (MatchPlacement.gd:897) |
| StackfallRain under Match (game/specials/StackfallEffect.gd:31) | rain of blocks | No | frees on LOBBY/END (StackfallRain.gd:96-98) |
| Gift crates/container (MatchGifts.gd:1220-1242) | crates, queues, glue, slots | No | `reset()` |
| MatchFeed QoL/backlog (MatchFeed.gd:400-423) | backlog, timer pause | No | `_build_bags()` |
| MatchStats (MatchStats.gd:127) | results tallies | No | `reset()` |
| MatchNet (net/MatchNet.gd:848-874) | cursors, intents, spawned ids, raster diff, replay | No | `reset_counters()` host LOADING / client start |
| SnapshotSync (net/SnapshotSync.gd:191-248) | bodies, interpolator, sim, clock, signal hooks | No | `begin_match()`/`end_match()` |
| Net (autoload/Net.gd:352-398, 1577-1613) | peers, rejoin tokens, accepting joins, in-progress | No | `leave()`, `set_match_in_progress` |
| BlockRegistry (game/BlockRegistry.gd:121-127) | entries, net ids, dissolver | No | `reset()` in `start_match` |
| Block statics `_awake/_slept_*` (game/Block.gd:40-46) | awake set | No | `_exit_tree` erase (:169-173) |
| StableBlockManager.active (game/StableBlockManager.gd:37, 63-68) | static current manager | No | cleared on exit |
| PerchingBirds (vfx/PerchingBirds.gd:176, 604) | perched birds | No | `reset()` on every state change |
| BlockEffectsManager trails/bursts (game/BlockEffectsManager.gd:513-538) | trails, pooled bursts | Self-heals in <= `trail_release_fade_s` | per-id cleanup |
| Main per-match nodes (game/Main.gd:1515-1543) | HotSeat(+HUD, TuningPanel, PlayerController), RemoteCursors, bots, StableBlockManager, NetDebugOverlay | No | `_end_match_world()`; mouse released in PlayerController `_exit_tree` (:343) |
| Main reset coverage (Main.gd:1515-1517, 431-439, 503-516) | when presentation reset runs | **Gap**: `_end_match_world` returns before the reset when a staged build was cancelled (`_world_built` false, Field `clear_match_state` also skipped); menu sandbox/tutorial starts never call it | partial (**G5**) |
| Engine.time_scale / tree paused (Sandbox.gd:124-133, 274-284, 343-368) | slow-mo, F11 pause | No | Sandbox `_exit_tree`, `_reset_field` |
| Sfx tense stem (autoload/Sfx.gd:65-72, 418-445) | `_tense_stem_is_active` + crossfade tween | **Yes** when `contextual_music_enabled` is off: only a later `goal_capture_progress` clears it | none (**G6**) |
| Sfx music context/playlist (Sfx.gd:454-466) | menu/gameplay context, track history | Carries by design (D2) | context set by Main |
| Rumble (autoload/Rumble.gd:77-80) | active vibration | Duration-bounded; `stop_all` only on pause open | defensive add |
| ResultsScreen / LoadingScreen / PauseMenu (persistent under Main) | overlay visibility, last results | No | hide on non-END (ResultsScreen.gd:141), `cancel()`, `force_close()` |
| Events connections | per-match connects | No duplicates found: per-match nodes are freed; persistent connects are guarded (MatchTerritory.gd:480, MatchGifts.gd:131, SnapshotSync.gd:216-221) | pin in fingerprint |
| PhysicsTuning.gravity_multiplier (MatchLifecycle.gd:213) | lobby gravity on shared resource | No | rewritten each start |
| F4 tuning resources (ui/TuningPanel.gd:117, 1386-1434) | edited shared `.tres` instances | Carries by design (D1) | panel Reset |
| Monotonic ids (MatchWeather `_host_epoch_counter` :63, BlockRegistry `_territory_revision` :64, Net steam generation) | stale-packet guards | Carries by design (D3) | n/a |
| QualityGovernorDriver, Net F3 `_sim` | perf level, debug lag | Session-level (D4) | n/a |

## 3. Gaps (6 open; camera and puddles closed in pass 1)

- **G1 Sky not restored to launch.** Sandbox/tutorial from the menu, and the menu itself, keep A's Night/Cycle theme; `set_theme_by_id` also rewrites the shared `SkyboxConfig.theme_name`.
- **G2 Weather overcast/storm sky fades over 7 s into B.** CloudCeiling is a persistent node under the MatchNet autoload.
- **G3 Stale influence circles.** A's circles are replicated to clients during B's loading/countdown and visible to bots/diagnostics.
- **G4 Pad home-focus stays suppressed after a sandbox session.**
- **G5 Reset coverage.** No presentation reset on a cancelled staged build or on menu sandbox/tutorial starts.
- **G6 Tense music stem carries over** (contextual music off).

## 4. One mechanism

**Entry point:** `Main._reset_match_scope(reset_camera: bool = true)`, which renames and replaces
`_reset_match_presentation()`. Main resets its own children directly, using
`RainPuddles.clear_on(_field)` and `_camera_rig.reset_view()`. It then emits **`Events.match_scope_reset()`**.
Every persistent owner Main cannot name (Skybox, CloudCeiling, WeatherPresenter,
Sfx, Rumble) connects in its `_ready()` and runs an idempotent `reset_to_launch()`.
Each reset must leave state exactly as `_ready()` leaves it, and should share code with
`_ready()` (the pass-1 `_apply_default_view()` pattern). Rules state stays on its existing
single entry, `MatchLifecycle._reset_match_state()`. That entry also runs on clients inside
`net_match_start`, so G3 is fixed there rather than through Main.

Call sites (all synchronous, all idempotent):
1. Top of `_build_match_world()` (already there). This runs before `configure_match_sky()`, so the sky is launch-then-configured.
2. Top of `_end_match_world()`, **before** the `_world_built` early return. This covers every
   `->LOBBY`, the client OFFLINE path and a cancelled staged build. When `_world_built` is false,
   `_field.clear_match_state()` must also run.
3. `start_sandbox_from_menu()` and `start_tutorial_from_menu()`, before `set_camera_rig()`/`start_match()`.
4. Sandbox F5 branch (Main.gd:1265-1271) with `reset_camera = false`. This is pass-1's DECISION, and the sandbox re-sets `suppress_pad_home_focus` itself.

```gdscript
# autoload/Events.gd
## Bontago-1pi.46: a match world is about to be built or was torn down. Persistent
## owners return to launch state (idempotent; host, client, sandbox alike).
signal match_scope_reset
# game/Main.gd
func _reset_match_scope(reset_camera: bool = true) -> void
# game/Skybox.gd
func reset_to_launch() -> void            # launch theme, config.theme_name, _cycle_* , QUALITY, faces hidden, storm/overcast/wfog 0
# vfx/weather/CloudCeiling.gd
func snap_clear() -> void                 # _targets, _amount, _storm_amount, _overcast = 0; _pushed_* = -1; push 0
# vfx/weather/WeatherPresenter.gd
func clear_now() -> void                  # free live presentations now (their _exit_tree zeroes mood/fog); ceiling.snap_clear()
# vfx/weather/WeatherFogShader.gd
static func reset_to_launch(tree: SceneTree) -> void   # launch defaults, refresh group
# autoload/match/MatchTerritory.gd
func clear_circles() -> void              # _circle_* empty, _circle_argmax_mode false
# autoload/Sfx.gd
func reset_match_audio() -> void          # tense off, kill crossfade, stems at calm targets
```

**Decisions** (record each one as a `# DECISION:` comment in the code):
- **D1:** F4 resource edits persist for the session, because they are dev tuning (and the panel can Save/Reset them). F4 runtime overrides held by match objects reset with the match: weather debug, breeze toggle, sky dropdown and sandbox territory mode. This is already true; the sky one is fixed by G1.
- **D2:** Music playlist position and context continue across matches; only the tense stem resets.
- **D3:** Monotonic ids, epochs and revisions keep counting, and the fingerprint excludes them.
- **D4:** The quality-governor level and Net F3 sim-lag are session-level.
- **D5:** CameraRig.map_def keeps the launch default, so a fresh launch is identical; the map scaling bug is out of scope.

## 5. Packages (Sonnet; dependency order R0 -> R1 || R2 -> R3)

**R0 hub + interface stub** (must be committed before R1/R2/R3 dispatch; they need the signal)
- Owns: `autoload/Events.gd`, `game/Main.gd`, `game/CameraRig.gd`, `tests/unit/test_match_restart.gd`.
- Work: add the signal; rename to `_reset_match_scope` and wire call sites 1-4 (G5); `reset_view()` also sets `suppress_pad_home_focus = false` (G4).
- Tests in test_match_restart: the signal fires once per build and once per teardown; it fires on a cancelled staged build (`_build_match_world(true)` and then `abort`); menu sandbox -> Leave -> lobby match leaves `suppress_pad_home_focus` false; menu sandbox start emits the signal.
- Checks: `tools/run_gut.ps1 test_match_restart,test_sandbox,test_match_lifecycle,test_tutorial`; open-project check.

**R1 sky + weather presentation** (G1, G2, fog parity)
- Owns: `game/Skybox.gd`, `vfx/weather/CloudCeiling.gd`, `vfx/weather/WeatherPresenter.gd`, `vfx/weather/WeatherFogShader.gd`, `tests/unit/test_match_reset_sky.gd`.
- Work: capture the launch theme and `config.theme_name` in `Skybox._ready()`; listeners connect in `_ready()` and disconnect in `_exit_tree` where these files already do so.
- Tests:
  - A Skybox put through CYCLE, then `set_theme_by_id("night")`, then `set_storm_sky(0.8)`, then `set_overcast(1, ...)` and `reset_to_launch()` matches a fresh Skybox (theme, config.theme_name, `_cycle_theme` null, process_mode, storm/overcast/wfog amounts, light basis/energy).
  - CloudCeiling at storm 1, after `weather_stopped` and `snap_clear()`, reads amount/storm/overcast 0, and the skyboxes received 0.
  - `match_scope_reset` triggers all of these.
- Checks: `run_gut.ps1 test_match_reset_sky,test_skybox,test_cloud_ceiling,test_weather_presenter` (use whichever of these exist).
- Visual: one windowed pair, B after A(storm+night+rain) vs fresh B, `--render-size=640x360` (owner probe rules, at most 3 runs).

**R2 rules + autoload carry-overs** (G3, G6, rumble)
- Owns: `autoload/match/MatchTerritory.gd`, `autoload/match/MatchLifecycle.gd`, `autoload/Sfx.gd`, `autoload/Rumble.gd`, `tests/unit/test_match_reset_rules.gd`.
- Work: call `clear_circles()` from `_reset_match_state()` and at the top of `_build_territory()`. Sfx and Rumble connect to `match_scope_reset` (`Rumble.stop_all()`).
- Tests:
  - After a solved match A, `abort_match()` + `start_match(B)` gives a `circle_render_arrays()` with empty xs/teams before PLAYING.
  - The host's `MatchNet._encode_circles()` during B's COUNTDOWN decodes to 0 circles.
  - Tense on -> `match_scope_reset` -> tense off, at calm volumes.
- Checks: `run_gut.ps1 test_match_reset_rules,test_match_territory,test_match_net,test_sfx,test_rumble` (use whichever exist).

**R3 fingerprint acceptance** (may be authored after R0; its gate runs on integrated R0+R1+R2)
- Owns: `tests/unit/support/MatchFingerprint.gd`, `tests/unit/test_match_reset_fingerprint.gd`, `tests/bench/reset_enet.gd`, `tests/bench/reset_enet.tscn`, `tools/run_reset_enet.ps1`.

Total: 4 packages, 19 owned files, no file shared between packages.

## 6. Acceptance design

`MatchFingerprint.capture(main: Node) -> Dictionary` (static; plain values only, floats rounded to 1e-4) and
`MatchFingerprint.diff(a: Dictionary, b: Dictionary) -> PackedStringArray` (key paths that differ). Captured keys:
- **camera:** distance, pitch, yaw, target, camera global transform, fov, shake offset, peek/focus flags, `suppress_pad_home_focus`, `_view_tweens.size()`.
- **field:** sorted child names, tilt, `_mirrored`, balance flag, applied-hole count, flag counts, overlay wet amount, overlay circle count, RainPuddles present.
- **sky:** theme resource_path, `config.theme_name`, cycle active, `environment.sky.process_mode`, `fallback_active`, storm/overcast/cloud-overcast/wfog amounts, light basis/color/energy, environment fog color/density and ambient energy.
- **weather:** `Match.weather()` running/active_id/intensity/mode, breeze running/enabled/gust_count, CloudCeiling amount/storm/overcast/target count, WeatherPresenter.active_count, BreezePresenter.live_count, WeatherFogShader statics.
- **rules:** state, slot count, `circle_render_arrays()` sizes, gift states size, pending specials, glue, stats arrays, blocks-parent child count, active cat, Match child count, sandbox territory flags.
- **net:** SnapshotSync running/bodies, MatchNet cursors/spawned ids/replay pending sizes, Net accepting joins and match in progress.
- **globals:** `Engine.time_scale`, `get_tree().paused`, PhysicsTuning.gravity_multiplier, `Block.awake_blocks().size()`, `StableBlockManager.active` valid.
- **audio:** Sfx music context and tense active.
- **wiring:** `Events.get_signal_connection_list(s).size()` for match_state_changed, weather_started/stopped/intensity_changed, block_placed/removed, special_triggered, match_scope_reset; plus Main child-name multiset (HotSeat/RemoteCursors/BotController/StableBlockManager/NetDebugOverlay counts).
- **excluded (D2-D4):** epochs, revisions, music track, wall clocks, governor. Use a fixed `rng_seed` everywhere.

`test_match_reset_fingerprint.gd` uses the test_match_restart fixture (real Main, tiny map, Net host on a free port, `_run_seconds`):
1. Reference: a fresh Main M1 hosts and starts B (2 players incl. 1 bot, Day, weather OFF, seed 777) and runs to COUNTDOWN + 0.5 s and PLAYING + 1 s, taking fingerprints `F_ref` at both checkpoints. Then Leave and free M1.
2. Dirty: a fresh Main M2 hosts match A (Night or Cycle, storm via `set_debug_override(&"storm")`, then rain, breeze gusts ticked):
   - Run long enough for puddles to appear and the circles to solve.
   - Queue a gift and a special (`debug_queue_special` on a sandbox-flag config, or emit `special_triggered` for black hole/paintball visuals).
   - Spawn a cat; zoom/orbit/peek/shake the camera; set `Sfx` tense.
   - Leave via the pause path.
   - Then run a menu sandbox: F10 slow-mo, F11 pause, Leave.
   - Then host and start B with the same config.
3. Take `F_test` at the same two checkpoints and assert `MatchFingerprint.diff(F_ref, F_test).is_empty()`. Print the diff on failure.
4. Variants (one test each): exit A via Replay (`start_match` from END), and via results Back to lobby; B as menu sandbox and as tutorial (compare against fresh-M1 sandbox/tutorial); B with a different map and weather RAIN (compare against a fresh B of the same config).

ENet variant, `tools/run_reset_enet.ps1` (modelled on `tools/run_qol_enet.ps1`: `--headless --agent-probe`, free port, `--sim-lag=50`, hard deadline, kills the process tree):
- **Mode `fresh`:** host+client start B and print `RESETFP <checkpoint> <json>` per peer.
- **Mode `dirty`:** the host plays A (storm, rain, gifts, black hole) and the client also dirties its own camera. Then Replay, then a second cycle where the client leaves and re-joins the lobby. Then B. Both peers print RESETFP.
- The script runs both modes and diffs per peer and checkpoint; it exits 0 only when every diff is empty. The client fingerprint must include the circle count decoded during COUNTDOWN (G3).

## 7. Review, risks, manual steps

**Review:**
- R0 (Main router + Events) and R2 (autoload + replicated circles) need `stackfall-reviewer`.
- R1 gets a standard review plus one visual pair.
- R3 gets a test review.
- The orchestrator runs the full gate once after R0-R2, and again with R3.

**Risks:**
- `Skybox.reset_to_launch()` followed by `configure_match_sky()` twice per start adds a reflection refresh. The loading screen covers it; if it shows in the perf log, skip the refresh when the theme is unchanged.
- Signal listeners in tests reset every live Skybox/rig in the tree. This is harmless but can surprise unrelated fixtures.
- R3 is red until R1+R2 are integrated.
- Headless fingerprints cannot see GPU particles; R1's visual pair covers the look.

**Manual (owner):**
- **Sky, weather and camera:** Vs bots with Night + Storm. Zoom out, wait for rain puddles, then pause and Leave. Start Vs bots with Day + Clear and check: launch camera framing, no puddles, a day sky with no overcast or storm tint, and the countdown shows no old influence circles.
- **Sandbox carry-over:** open Sandbox, press F10 and then Leave. Start a match and check it runs at normal speed and gamepad Back focuses home.
- **Online:** repeat the first check as an ENet host plus client (Replay, then Back to lobby).
