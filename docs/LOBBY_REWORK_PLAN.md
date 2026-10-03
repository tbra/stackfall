# Lobby rework plan (Bontago-1pi.53)

Planning only; Beads owns status. Base `a674bb6` (main). Source of the requirements: owner playtest 2026-10-03 night
(bead description). **Structure changes only: keep the existing cream-card / pastel-pill style**
(`ui/theme/MenuStyleFactory.gd`, `config/MenuVisualTuning.gd`); no new colours, no `MenuVisualTuning` edits.

## 1. Current state (read at a674bb6)

| Fact | Anchor |
|---|---|
| `Lobby.gd` is 1606 lines; the hidden `%TeamModeOption`, `%MapVariantOption`, `%MapSizeOption` stay the source of truth behind visible front ends (segmented Teams buttons, map combo) | `ui/Lobby.gd:81-101`, `:556-567`, `:944-948` |
| Main card = ROUND (`GameModeOption`, one of `RoundTimerSlider`/`MatchTimerSlider`), MAP (combo, `SkyThemeOption`), PLAYERS/AI spins + `AiDifficultyOption`, TEAMS segmented, right column block timer / gravity / gift frequency / goal flags / gifts | `ui/Lobby.tscn:138-503` |
| Advanced popup (`AdvRulesBar` + chips + modal): specials checklist (dynamic, `_build_specials_checklist` L408), tilt, hole, weather, sky team sum, sudden death, turn-based, mid-join, QoL Experiments (4 checks) | `ui/Lobby.tscn:505-603, 709-918`; `ui/Lobby.gd:850-919` |
| Focus: runtime closed loops, `_main_chain` / `_popup_chain`, `_visible_chain()` hides only four conditional columns | `ui/Lobby.gd:449-512` |
| Gamepad shortcuts: `lobby_quick_advanced` (Y) toggles the popup, `lobby_quick_start` (X) starts, `ui_cancel` closes popup else Back | `ui/Lobby.gd:872-891`; `tools/bootstrap_project.gd:457-458` |
| Timer sliders (1pi.30) step themselves via `gui_input` (so GUT can drive them) | `ui/Lobby.gd:1012-1041` |
| Round trip: `_config_from_controls` L1073 -> `_publish_lobby_data` L1065 (+`"roster"`) -> `Net.set_lobby_data` (`autoload/Net.gd:557`, RPC `_rpc_lobby_data` L1705, Steam tee) -> `_apply_data` L1146 (`from_dict` + `sanitize`, `_applying_remote_data` guard) | |
| Right panel = rows only (colour cube, name, subtitle, ready badge); **no per-row controls**. Humans from `Net.peer_info`, synthetic bot rows `slot_id = player_count - ai_count ..` named `"Bot n (Difficulty)"` | `ui/Lobby.gd:1257-1387, 1403` |
| Row colour reads `default_config.player_colors[slot_id]`, not the live config | `ui/Lobby.gd:1341` |
| Seat counts: hidden spins; `ai_count` max = seats - humans; `player_count` mirrors peers + bots | `ui/Lobby.gd:1505-1533` |
| Match-side: ONE `ai_difficulty` for all bots (`Main._spawn_bot_controllers` L1500-1507 -> `bot.setup(slot, config.ai_difficulty, ...)`); bots are the trailing slots (`MatchLifecycle._build_slots` L907-918); `player_colors[8]` is per-slot and already in `to_dict` (L493) | `game/Main.gd:1505` |
| Teams: `team_mode` OFF/2/3/4 only; `team_of_slot = slot % team_count` (interleave); `team_count()` = `min(count, players)`; consumers loop `range(team_count())` (dense ids required) | `config/MatchConfig.gd:325-352`; `autoload/match/MatchTerritory.gd:141,354,477,689`; `MatchLifecycle.gd:802,1055`; `net/MatchNet.gd:1266` |
| Territory/minimap colour is `player_colors` indexed by **team id** (equals teammate-0 colour only because of interleave) | `game/Main.gd:346,390,528,1408`; `ui/HUD.gd:835`; `game/TerritoryOverlay.gd:304` |
| Client edits: none. Only own Ready via any_peer RPC; precedent for a validated client intent = `request_loading_ready` / `_rpc_loading_ready` | `autoload/Net.gd:1618-1660` |
| Net lobby slots are monotonic (`_take_next_lobby_slot` L1385, never compacted): a leave/rejoin leaves a hole that can collide with trailing bot slots (latent, see R4) | |
| Results "Quick settings" republishes `config.to_dict()` + preserved `"roster"` and edits `ai_count`/`ai_difficulty` | `ui/ResultsScreen.gd:437-460` |
| Tests drive controls by `%UniqueName`, `signal.emit()`, `gui_input.emit()`, `_unhandled_input(event)`, and walk `focus_neighbor_*`; `FakeNet` is the seam (`tests/unit/support/FakeNet.gd`) | `tests/unit/test_lobby.gd:878-984`, `test_lobby_qol.gd` |

**Pending branches** (merge-base diffs): `wt/sky-u1` edits only `Lobby.gd` (`SKY_THEME_LABELS`, "Sunset", tooltips in `_populate_options`) + `test_lobby.gd`: trivial, land first.
`wt/hud-revert` reverts the 2026-10-02 redesign and rewrites `Lobby.gd`, `Lobby.tscn`, `test_lobby.gd` and `MenuVisualTuning.gd`, **moving the Round controls back into the popup on a pre-1pi.30 (spin) base**: it conflicts with this rework wholesale. Orchestrator must decide before E1 dispatches (see R1). All new tunables here go to a new `config/LobbyLayoutTuning.gd`, so they never touch `MenuVisualTuning`.

## 2. Target layout (host edits everything; client sees it read-only)

Left card = a single scroll column of `LobbySection`s (header = CaptionLabel + right-aligned summary text, activated by click / `ui_accept`).
Each section may carry one **Advanced** block (flat toggle chip, collapsed by default, not persisted). Keep every `%UniqueName` unless stated.

| Section | Main (always visible) | Advanced (collapsed) | Maps to |
|---|---|---|---|
| **GAME** | Game mode `%GameModeOption`; Map `%MapComboOption`+`%MapThumbnail`; Time of day `%SkyThemeOption` (sky-u1 labels, default Cycle); Weather `%WeatherOption` | Gravity `%GravitySlider`; Turn-based `%TurnBasedCheck`; Hole mode `%HoleModeOption`; Tilt mode `%TiltModeOption`; Allow join mid-match `%MidJoinCheck` | `game_mode, map_variant/size, sky_theme_mode, weather_mode, gravity_multiplier, turn_based, hole_mode, tilt_mode, allow_mid_match_join` |
| **ROUND** | Round length (match timer in Classic / round timer otherwise, existing show/hide `_refresh_timer_control` L974); Sudden death `%SuddenDeathCheck` (Classic only); Block timer `%BlockTimerSlider`; Goal flags `%GoalFlagSpin` (only `MatchConfig.mode_uses_goal_flags`, L296); Team height `%SkyTeamSumCheck` (Reach the Sky only, relabel "Team height: sum of members") | none (not crowded) | `match_timer_minutes, round_timer_minutes, sudden_death, block_timer, goal_flag_count, sky_team_sum` |
| **GIFTS** | On/off `%GiftsCheck`; Frequency `%SpecialFreqSlider` (dimmed while off) | Per-gift checkboxes `%SpecialsChecklist` (existing dynamic list + all-disabled sentinel `ALL_DISABLED_SENTINEL`) | `gifts_enabled, special_frequency, enabled_specials` |
| **EXPERIMENTS** | header only, summary "n on" | the four `%Qol*Check` chips | `qol` (via `_qol_from_controls`) |

Removed: `AdvRulesBarPanel`, chips, `AdvancedPopup*`, the Players/AI spins and `AiDifficultyOption` and the segmented Teams control from the visible tree. The spins and `%TeamModeOption` **stay as hidden sources of truth** (the pattern already used for map/teams, L81) so `_config_from_controls`/`_apply_data`/`ai_count` clamping and most existing tests keep working.

**Right panel** (`LobbyPlayersPanel`): title + `n players - m bots - k/8 seats`; header row [`Teams` toggle chip (host only)] [`+ Add bot` pill (host only, disabled at 8 seats / no room)]; one row per seat; footer Invite Friends + Ready. Seat row = colour box button, name + subtitle, **team button** (only when teams on), **difficulty `OptionButton`** (bots only, Easy/Normal/Hard), remove "x" (bots, host only), ready badge.
- Colour box click: next palette colour; if another seat holds it the two **swap** (colours stay unique, 8 seats always valid). Right-click = previous.
- Team button cycles `1 > 2 > 3 > 4 > Random(?) > 1` (cap = `MatchConfig.team_pick_cap()`; a legacy TEAMS_2/3 lobby cycles to 2/3). Same number = same team. Random is resolved at match start (D3).
- Toggle on seeds picks 1,2,1,2...; a new seat joins the smaller of teams 1/2. Toggle off keeps picks (hidden). Maps to `team_mode`: OFF <-> `TEAMS_4` ("on, up to 4 teams").
- Client may change only its own colour/team; everything else is host-only.
- Start gate: host Start is disabled with the reason shown when teams are on and every seat is explicitly on one team (`TeamAssigner.blocker`).

## 3. Data and network design

**New `MatchConfig` fields** (all optional in `from_dict`; empty = legacy behaviour, so old saved lobbies, `--bots=N`, sandbox and every existing `team_mode = TEAMS_2` test are untouched):
```gdscript
const TEAM_PICK_RANDOM: int = 0        # lobby numbers are 1..TEAM_PICK_MAX
const TEAM_PICK_MAX: int = 4
@export var slot_team_ids: PackedInt32Array = PackedInt32Array()        # host-resolved at Start; dense 0..n-1 per slot
@export var team_numbers: PackedInt32Array = PackedInt32Array()        # dense team id -> lobby number (labels)
@export var slot_ai_difficulties: PackedInt32Array = PackedInt32Array() # per slot; [] -> ai_difficulty
func teams_enabled() -> bool                       # team_mode != OFF
func team_pick_cap() -> int                        # 0 off, else team_mode_team_count()
func ai_difficulty_for_slot(slot_id: int) -> AiDifficulty
func team_number_for(team_id: int) -> int          # team_numbers[id] or id + 1 when unresolved
func territory_colors() -> PackedColorArray        # player_colors if OFF/unresolved, else colour of each team's lowest slot
```
`team_of_slot` returns `slot_team_ids[slot]` when `team_mode != OFF` and the array covers the slot, else the old interleave; `team_count()` returns `team_numbers.size()` when resolved. `sanitize()` drops both team arrays unless sizes/ranges are consistent (so a bad wire value degrades to legacy) and clamps `slot_ai_difficulties`. `ai_difficulty` stays as the default for new bots.
Precedent for host-resolved + replicated-in-`to_dict`: `resolve_sky_theme` (`MatchConfig.gd:420`, called host-side at `MatchLifecycle.start_match` L188).

**Lobby seat table** (lobby data only, sibling of `"roster"`, **not** a `MatchConfig` field; humans keyed by peer id and bots by ordinal so a join/leave never shifts anyone's prefs):
```
"seats": { "humans": [ {"peer_id": int, "color": int, "team": int} ],   # color = palette index 0-7, team = 0 Random | 1..4
           "bots":   [ {"color": int, "team": int, "difficulty": int} ] }  # length == ai_count
```
Pure rules in `core/rules/LobbySeats.gd` (static, no scene tree): `empty()`, `reconcile(seats, peer_ids, ai_count, default_difficulty, cap)`, `set_color(seats, key, idx)` (swap), `set_team(seats, key, pick)`, `add_bot`, `remove_bot(ordinal)` (compacts), `human_key/bot_key`, `flatten_to_config(seats, slot_of_peer, config, rng_seed)` (writes `player_colors[slot]`, `slot_ai_difficulties`, calls the assigner; humans use their real Net slots, bots the trailing slots) and `team_picks_by_slot`.
`core/rules/TeamAssigner.gd`:
```gdscript
class Result: var team_ids: PackedInt32Array; var team_numbers: PackedInt32Array
static func resolve(picks: PackedInt32Array, cap: int, rng_seed: int) -> Result  # per-slot picks in, dense ids out
static func blocker(picks: PackedInt32Array, cap: int) -> String                 # "" or reason
static func next_pick(current: int, cap: int, backwards: bool = false) -> int    # 1..cap, Random, wrap
static func default_picks(seat_count: int) -> PackedInt32Array                   # 1,2,1,2...
```
Resolve: `K = clampi(max(2, highest explicit number), 2, cap)`; Random seats in a seeded shuffled order each join the least-populated team of `1..K` (seeded tie-break); then compact used numbers ascending to dense ids (every downstream loop keeps its dense-id assumption). Seed = `config.rng_seed` if >= 0 else a host `randi()`.

**Wire/host validation.** Humans' prefs are host-owned. A client changes its own via `Net.request_seat_pref(color_index: int, team_pick: int)` (`-1` = unchanged) -> any_peer RPC `_rpc_request_seat_pref` on the host (pattern: `request_loading_ready`, `Net.gd:1640-1657`): host takes the peer id from `get_remote_sender_id()` (never the payload), requires a seated peer (slot >= 0) in lobby phase (`not _match_in_progress`), rejects out-of-range ints (no clamping), then emits `Events.net_seat_pref_requested(peer_id, color_index, team_pick)`. Net stays transport-only; the host-side `LobbyPlayersPanel` applies it through `LobbySeats` (uniqueness/swap) and republishes. The client UI does not update optimistically; it follows the next lobby-data echo. Host/offline calls the same path locally with `local_peer_id()`. N1 also changes `_take_next_lobby_slot` to reuse the lowest free slot while not mid-match (fixes R4).
Compat: `seats`, `slot_team_ids`, `team_numbers`, `slot_ai_difficulties` are new dict keys that `from_dict` reads defensively and old readers ignore; the build-version check already refuses mixed builds (`Net.gd:1314`). Size: well under `steam_lobby_data_max_bytes` (8192); a test asserts the 8-seat lobby dict encodes below it. Rematch from Results reuses the flattened start config (resolved teams persist); lobby re-entry calls `reconcile`, so a stale/missing `seats` degrades to defaults.

## 4. Focus and input design (no new Input Map actions, so no bootstrap re-run)
- `LobbySection` header and its Advanced chip are `FOCUS_ALL` buttons: `ui_accept` toggles; every toggle calls `Lobby._rewire_focus()`. `_visible_chain` generalises to `is_visible_in_tree()` and `not disabled`; rewire happens on section toggle, game-mode change, seat-row rebuild and editable-state change, **not** every `_process` frame (`_update_host_only_state` runs per frame, `Lobby.gd:322-331`).
- Main chain order = visual order: GAME, ROUND, GIFTS, EXPERIMENTS (section header, its visible controls, its advanced block), then the players panel (Teams toggle, Add bot, rows), then Back / Invite / Ready / Start. Closed loop up/down as today (`_wire_loop` L504); `FocusScrollContainer`/`follow_focus` keeps the focus visible (`ui/FocusScrollContainer.gd`).
- `lobby_quick_advanced` (Y) now expands/collapses the Advanced block of the section containing focus (first section when focus is elsewhere); `ui_cancel` backs out of the lobby (the popup case disappears); `lobby_quick_start` (X) unchanged.
- Seat rows: `focus_neighbor_left/right` move between a row's controls (colour, team, difficulty, remove); `focus_neighbor_top/bottom` link the same control in the neighbouring row (a "team column" runs straight down). **`ui_accept` / click cycles** (colour next, team next); the difficulty `OptionButton` opens its popup as usual. Right-click and `gui_input` handling follow the `_on_timer_slider_gui_input` pattern (L1030) so tests drive them with plain emits.
- Disabled controls (client on other rows) are excluded from the chain; the rows' own focus is rewired in `LobbyPlayersPanel`, which returns `focus_entries() -> Array[Control]` for the Lobby's chain.
- Tests drive: `button.pressed.emit()` (accept/click), `gui_input.emit(InputEventMouseButton)` (right-click), `InputEventAction` through `_unhandled_input` for Y/B, real `InputEventJoypadButton` for the binding check (as `test_lobby.gd:972`), and chain walks via `focus_neighbor_*`.

## 5. Packages (each <= ~10 files, ~30 min; file ownership disjoint; `.uid` files follow their scripts)

Dependency order: **P1 -> (P2 ‖ N1 ‖ E1 ‖ M1) -> S1a -> S1b ‖ PL1a -> PL1b -> final docs**. Land `wt/sky-u1` and resolve `wt/hud-revert` before E1.

| ID | Outcome | Owned files | Depends on |
|---|---|---|---|
| **P1** *(interface stub + core)* | `MatchConfig` fields/methods above; `TeamAssigner` (+Result); serialization/sanitize | `config/MatchConfig.gd`, `core/rules/TeamAssigner.gd`, `tests/unit/test_match_config.gd`, `tests/unit/test_team_assigner.gd` | base only |
| **P2** | `LobbySeats` pure rules incl. `flatten_to_config` | `core/rules/LobbySeats.gd`, `tests/unit/test_lobby_seats.gd` | P1 |
| **N1** *(netcode)* | `Net.request_seat_pref` + RPC + `Events.net_seat_pref_requested`; lowest-free-slot in lobby; `FakeNet.request_seat_pref` stub (+`request_seat_pref_calls`) | `autoload/Net.gd`, `autoload/Events.gd`, `tests/unit/support/FakeNet.gd`, `tests/unit/test_net_session.gd` | P1 |
| **E1** *(Lobby stub/extraction)* | Move roster/row code into `LobbyPlayersPanel` (1:1 behaviour) and install the narrow Lobby hooks: `seats_data()` merged in `_publish_lobby_data`, `apply(config, roster, seats)` in `_apply_data`, `on_roster_changed`, `finalize_start_config` + `start_blocker()` in `_on_start_pressed`/`_update_host_only_state`, signals `seats_changed`, `teams_toggled`, `add_bot_requested`, `remove_bot_requested`. Add `LobbyLayoutTuning` (section spacing, colour-box size, row min height, advanced indent). No-op stubs where P2/N1 are not needed yet | `ui/Lobby.gd`, `ui/Lobby.tscn`, `ui/lobby/LobbyPlayersPanel.gd`, `ui/lobby/LobbyPlayersPanel.tscn`, `config/LobbyLayoutTuning.gd`, `config/lobby_layout_tuning.tres`, `tests/unit/test_lobby.gd` | sky-u1 (+hud-revert decision) |
| **M1** | Match consumers: per-slot bot difficulty; `territory_colors()` at the four overlay sites + minimap; team labels via `team_number_for`; Results republish preserves `"seats"` | `game/Main.gd`, `ui/HUD.gd`, `ui/ResultsScreen.gd`, `tests/unit/test_team_slots.gd` | P1 |
| **S1a** | `LobbySection` + restructure `Lobby.tscn` SettingsCard into GAME/ROUND/GIFTS(/EXPERIMENTS) sections; goal-flag and Reach-the-Sky visibility; popup still present (runnable intermediate) | `ui/Lobby.tscn`, `ui/Lobby.gd`, `ui/lobby/LobbySection.gd`, `tests/unit/test_lobby.gd`, `tests/unit/test_lobby_sections.gd` | E1 |
| **S1b** | Move the popup content into the Advanced blocks, delete popup/bar/chips/segmented Teams, generalised `_visible_chain`, Y semantics, screenshot tool | `ui/Lobby.tscn`, `ui/Lobby.gd`, `tests/unit/test_lobby.gd`, `tests/unit/test_lobby_qol.gd`, `tests/unit/test_lobby_sections.gd`, `tools/screenshot_lobby_rework.gd`(+`.tscn`) | S1a |
| **PL1a** | `LobbySeatRow`: colour box, team button, bot difficulty dropdown, remove; host edits via `LobbySeats`; rows built from the panel's seats | `ui/lobby/LobbySeatRow.gd`, `ui/lobby/LobbyPlayersPanel.gd`, `ui/lobby/LobbyPlayersPanel.tscn`, `tests/unit/test_lobby_players.gd` | E1, P2 |
| **PL1b** | Teams toggle, Add bot, client self-edit via `net_provider.request_seat_pref`, host handling of `net_seat_pref_requested`, Start blocker text, focus entries | same four files as PL1a (sequential, same worktree) | PL1a, N1 |
| **D1** *(docs, orchestrator-owned)* | `docs/SPEC.md` 2.8 table rows (Teams -> per-seat numbers; AI difficulty per bot; Players/AI -> add-bot) | `docs/SPEC.md` | all |

S1a/S1b and PL1a/PL1b are the two UI tracks and are file-disjoint after E1 (S1 owns `Lobby.gd`/`Lobby.tscn`, PL1 owns `ui/lobby/LobbyPlayers*`/`LobbySeatRow`). PL1 never edits `Lobby.gd`: E1's hooks are the contract. Interface stubs are P1 (config API), E1 (Lobby<->panel hooks) and N1's `FakeNet` method; verify each consumer's base contains them before dispatch.
S1a/S1b and PL1a/PL1b are each sized ~35-45 min: checkpoint at the stated intermediate state if the 30-minute budget runs out; do not merge a half-collapsed lobby.

### Package-specific tests
- **P1:** `to_dict`/`from_dict` round trip of the new keys; old dict without them keeps interleave; `team_of_slot`/`team_count` resolved vs legacy; `sanitize` drops inconsistent arrays; `territory_colors` for teams {0,1}/{2,3}; `TeamAssigner`: determinism per seed, Random balancing, K rule, dense compaction, blocker, `next_pick` wrap for cap 2/3/4.
- **P2:** colour swap keeps uniqueness (8 seats); reconcile on join/leave/ai_count change keeps others' prefs; `remove_bot` compaction; flatten maps humans to real slots and bots to trailing slots; default 1,2,1,2.
- **N1:** ENet-free via the existing `Net` test seams: spoofed payload sender ignored; spectator/out-of-range/mid-match refused; valid request emits the event; host-local path; lowest-free-slot reuse. ENet harness once (host+client, `test_net_session`-style) for the RPC.
- **E1:** every pre-existing roster/start/ready test still green against the panel; hooks no-op safe.
- **M1:** `_build_slots` with resolved teams; `bot.setup` receives the slot's difficulty; `--bots=N` path unchanged; winner/results label uses `team_number_for`.
- **S1:** each `%UniqueName` still resolves (list asserted); defaults collapsed; Advanced toggle changes `_visible_chain`; focus loop closed through headers and open blocks; client controls disabled; round-trip of every GAME/ROUND/GIFTS field; Y toggles the focused section; `test_lobby_qol` unchanged semantics.
- **PL1:** host cycles colour/team/difficulty -> published `seats`; client edits only own row (FakeNet `request_seat_pref_calls`), others disabled; Add bot respects seat cap; Random shown as `?`; start blocker disables Start; row focus neighbours; right-click backward.

## 6. Reviews, checks and visual probes
- Review required: **P1+P2** (rules core, determinism, compat), **N1** (any_peer RPC validation; `stackfall-netcode` author, independent reviewer), **M1** (match-flow touch; light), **S1b/PL1b** (UI + screenshots). Integrator pass once all land: ENet host+client with simulated lag, 4 seats + 2 bots, teams on, client changes own colour/team.
- Gate: targeted `tools/run_gut.ps1` per package (`test_lobby`, `test_lobby_qol`, `test_lobby_sections`, `test_lobby_players`, `test_lobby_seats`, `test_team_assigner`, `test_match_config`, `test_net_session`, `test_team_slots`, `test_match_lifecycle`); one full gate per integrated game-code batch (orchestrator). `godot --headless --editor --path . --quit` clean.
- Visual (off-screen, owner flags): `--windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy -- --agent-probe --render-size=1280x720`, quit after the capture, **max 2 shots per package**: S1a default-collapsed host view; S1b all Advanced blocks open (Reach the Sky to show Team height); PL1a 4 humans+bots with teams on; PL1b client view (own row only editable) + Random showing. No iterating visually; stop and report.
- Manual steps for the owner (written at hand-off): two instances over direct IP; host adds a bot, sets Hard; both change colours (swap visible); both cycle teams with mouse and with a pad; Random resolves at Start; 3v1 and Random-only starts; Start blocked when all on one team.

## 7. Decisions (minor, recorded; code comments `# DECISION:` in the packages)
- **D1:** ROUND has no Advanced block (not crowded); Sudden death sits in ROUND main (Classic only). Weather lives in GAME main (owner's list).
- **D2:** QoL Experiments get their own collapsed **EXPERIMENTS** section (header "n on"), not spread over the others: clearly opt-in, keeps the F4 grouping. Alternative (distribute: timer pause/backlog/goal radius to ROUND-advanced, gift slot to GIFTS-advanced) is cheap to switch to later because the `%Qol*Check` names are stable.
- **D3:** Random resolves at match start, host-side, seeded (`TeamAssigner.resolve`), result replicated in `slot_team_ids`/`team_numbers`; Random fills the least-populated of teams `1..K`.
- **D4:** Team ids stay dense; lobby numbers survive only in `team_numbers` for labels ("Team 3 wins" matches the lobby). Territory/minimap colour of a team = colour of its lowest slot (`territory_colors`); per-player colours stay independent, block tints use the player's own colour.
- **D5:** Colours are the existing 8-colour palette, unique across seats, conflicts **swap**; host owns bots' colours, humans own theirs.
- **D6:** The hidden spins/`%TeamModeOption` remain the source of truth for counts/mode; Add bot = `ai_count+1` and `player_count+1` through the existing clamp (`_clamp_ai_count_to_seats`); remove-bot compacts the bot list. No min-seat Start gate is added (current permissive behaviour kept).
- **D7:** Section expanded state is not persisted; all Advanced blocks start collapsed.
- **D8:** Legacy `TEAMS_2/3` data stays valid (cap 2/3); the UI itself writes only OFF or `TEAMS_4`.
- **D9:** `LobbyLayoutTuning.tres` carries new sizes/spacings; no `MenuVisualTuning` change.

## 8. Risks
- **R1 (high):** `wt/hud-revert` vs this rework (see section 1): decide merge order or drop its Lobby hunks before E1; otherwise E1 rebases onto a different layout. Also `wt/sky-u1` must be in E1's base (it edits the same `_populate_options`).
- **R2:** `Lobby.gd`/`Lobby.tscn` single-owner windows (E1 -> S1a -> S1b); PL1 must not edit them. A package needing a hook that E1 did not install stops and reports.
- **R3:** Focus/gamepad: collapsed blocks and disabled client controls must never leave a focused control hidden; chain rewiring only on state change (per-frame `_process` calls `_update_host_only_state`).
- **R4 (existing):** monotonic lobby slot ids can leave holes that collide with trailing bot slots at Start; N1 reuses the lowest free slot, and `flatten_to_config` asserts every human slot < `player_count - ai_count`.
- **R5:** `player_colors` flows into 10+ sites (flags, overlay, minimap, HUD); only the team-indexed overlay/minimap sites switch to `territory_colors()`; flags and block tints stay per-slot.
- **R6:** Unbalanced teams (3v1) and 4 single-player "teams" become possible. Both follow from the owner's "same number = same team"; the rule that a team needs one connected allied component is unchanged (SPEC 2.2/146). No [ORIGINAL] rule changes.
- **R7:** Results "Quick settings" edits `ai_count` outside the lobby: `reconcile` truncates/extends the bot list on re-entry.

## 9. Owner questions (genuine, non-blocking)
1. **Gifts "distribution?"** Does it mean per-gift spawn weights? Options: (a) not now: per-gift checkboxes only; weights stay in `config/specials/*.tres`; (b) per-gift Rare/Normal/Common selector in GIFTS-Advanced (new `special_weights` in `MatchConfig`, ~1 extra package). **Recommend (a)**; (b) can follow on request.
2. **Random pool.** Recommended: Random fills the least-populated team among `1..K` (K = highest team number anyone picked, min 2), so all-Random gives balanced teams (4 players -> 2v2; 8 -> up to 4 teams). Alternative: each Random seat draws uniformly from 1-4 (can yield 1 team or all singles). **Recommend the balanced fill.**
