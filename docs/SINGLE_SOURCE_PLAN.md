# Single owners for cross-cutting player-facing concepts (Bontago-1pi.86)

Base main 957a5c1. Evidence is `grep -rn` over ui/ game/ autoload/ net/ core/ vfx/ (*.gd, *.tscn);
counts are lines. Design only; no game code. Lint design follows `tools/lint_magic_numbers.py`
(fca.35, wt/tool-magic f7135fb, called from `tools/full_gate.py` before the shards).

## 1. Inventory: concept, owner, API, bypass rule

Rule ids are used by the lint table in section 2. "Allowed" = files the rule skips.

### N. Player / bot / team / winner names -- owner `core/rules/PlayerNames.gd` (extend)
Existing: `clean`, `sanitize`, `fallback_for_slot` (:62), `label_for_slot`, `bot_label`, `FALLBACK_FORMAT`.
`core/bot_names.gd:9` keeps a second `FALLBACK_FORMAT = "Bot %d"`; BotNames only picks names from the list.
Bypasses today (6 format sites + 1 duplicate const):
- `"Player %d"`: ResultsScreen.gd:254, MatchStats.gd:396.
- `"Bot %d"`: LobbyPlayersPanel.gd:256 (the 1pi.83 "Bot 1" bug).
- `"Team %d"`: HUD.gd:627 ("wins!"), ResultsScreen.gd:230, ScoreTable.gd:88, LobbySeatRow.gd:222, MatchStats.gd:401.
- Team *number* derived three ways: `HUD._team_number` (HUD.gd:979), `ResultsScreen.team_number_in` (:268, used HUD:715-738, ScoreTable:88), `MatchConfig.team_number_for` (MatchConfig.gd:440).
Add to PlayerNames (all static, pure): `team_label(team_number:int)->String`, `winner_text(team_number)->String` ("Team N wins!"),
`bot_fallback(ordinal:int)->String` (BotNames and LobbyPlayersPanel call it; `BotNames.FALLBACK_FORMAT` deleted),
`slot_label(slot_id, slots:Array, peer_name)` is the existing `label_for_slot`. Team number stays `MatchConfig.team_number_for`;
`ResultsScreen.team_number_in` becomes a thin pass-through or is removed (it indexes a results-carried `team_numbers`, which is
legitimate for a finished match -- PlayerNames.team_label takes that number, so only the *format* is centralised).
- Rule `NAME_FMT`: regex `["'](Player|Bot|Team|Spectator)\s*(%d|%s|\{)` and `"(Player|Bot|Team) "\s*\+`. Allowed: `core/rules/PlayerNames.gd`. Comments skipped.
- Rule `NAME_RAW`: regex `\.display_name` in `ui/**` outside the allowed list is NOT enforced (46 hits, mostly legit PlayerSlot reads);
  instead rule `NAME_RAW` bans `slot\.display_name if .* else` (inline fallback). Allowed: PlayerNames.gd.

### C. Slot colour and the colour diamond -- owners `core/rules/SlotColors.gd` (pure, new) + `ui/SlotDiamond.gd` (new, built by 1pi.81)
Slot-colour-with-fallback is re-implemented 5 times, each a different order:
BlockEffectsManager.gd:285 `_color_for_owner_slot`, GiftCrate.gd:289 `_claim_color`, HUD.gd:1033 `_color_for_slot`, ScoreTable.gd:110 `slot_color`,
LobbyPlayersPanel.gd:690 `_seat_color` (lobby: seat index -> palette, GRAY fallback). Palette read straight from config in
HUD.gd:1037, ScoreTable.gd:120, LobbySeats.gd:100/105/588, BlockEffectsManager.gd:292, Minimap/Field via `player_colors` (27 team/slot colour lines).
API: `SlotColors.resolve(slot_id:int, live_color:Variant, palette:PackedColorArray, fallback:Color=Color.WHITE)->Color` (pure order:
live PlayerSlot.color, else palette[slot_id], else fallback) and `SlotColors.palette_color(index:int, palette)->Color`.
Runtime accessor `Match.slot_color(slot_id, fallback:=Color.WHITE)->Color` on the Match autoload (the only caller that reads
`Match.slot()` + `Match.config`); HUD and ScoreTable keep their `match_provider` test seam by passing it to `SlotColors.resolve`.
Diamond: `ui/SlotDiamond.gd` (Control, `set_color(Color)`, `size` from `HUDVisualTuning`), used by HUD share rows (HUD.gd:1242 `_on_row_glyph_draw`),
lobby seat row, round-score overview, Minimap home beacons (Minimap.gd:560-581, polygon drawn on the canvas: exposes static `SlotDiamond.points(center,half)->PackedVector2Array`).
- Rule `COLOR_LOOKUP`: regex `(player_colors|default_player_colors)\s*(\[|\.size|\()` . Allowed: `config/MatchConfig.gd`, `core/rules/SlotColors.gd`, `core/rules/LobbySeats.gd`, `autoload/Match.gd`, `game/Field.gd`, `ui/Minimap.gd` (raster/shader take the whole array; allowed until migrated, baseline covers them).
- Rule `DIAMOND`: regex `(?i)diamond` in code (not comment) in `ui/**` outside `ui/SlotDiamond.gd`. Baseline: HUD.gd, Minimap.gd.

### G. Input glyphs and prompts -- owner `ui/InputGlyph.gd` + `config/InputGlyphTable.gd` (extend)
Correction to the Bead evidence: glyph *texture paths* live only in InputGlyph.gd (`GLYPH_ASSET_ROOT` :151) and `config/input_glyph_table.tres`;
the 17 files listed mostly instantiate InputGlyph (legitimate: 37 `InputGlyph` lines in 7 files) or reference menu icons
(`res://assets/ui/icons/*.svg`, 22 lines in MainMenu.tscn, PauseMenu.tscn, OptionsMenu.gd/.tscn -- that is menu iconography, not input glyphs, see Q3).
Real bypass: each consumer re-derives "action -> events -> glyph list -> device family":
`InputMap.action_get_events` at HUD.gd:1522, KeyRebindRow.gd:351, LoadingScreen.gd:696, GiftDemoStrip.gd:56 (Settings.gd:751 is binding editing, legit);
`event.as_text()` HUD.gd:1500 (cache signature) and InputGlyph.gd:269.
API (new, static, in InputGlyph.gd or a sibling `ui/InputPrompt.gd` if InputGlyph.gd exceeds the file budget):
`InputGlyph.events_for_action(action:StringName, device:StringName)->Array[InputEvent]` (filters by `Settings.active_input_device()` family),
`InputGlyph.build_for_action(parent:Control, action:StringName)->Array[InputGlyph]` (instantiates + `set_event`), and `InputGlyph.signature_for_action(action)->String`.
Consumers keep their own layout; none calls `InputMap` or `as_text`. Device-change rebuild stays `Settings.input_device_changed`.
- Rule `GLYPH_EVENTS`: `InputMap\.action_get_events|\.as_text\(\)` in ui/ game/ vfx/. Allowed: `ui/InputGlyph.gd`, `ui/InputPrompt.gd`, `autoload/Settings.gd`.
- Rule `GLYPH_ASSET`: `assets/ui/input_glyphs|input_glyph_table`. Allowed: `ui/InputGlyph.gd`, `config/InputGlyphTable.gd`.
- Rule `GLYPH_TEXT`: hard-coded key/button words in prompt strings, regex `"[^"]*\b(Press|Hold|Tap|Click)\s+(Enter|Space|Esc|[A-Z]|A|B|X|Y)\b[^"]*"` in ui/ game/. Allowed: InputGlyph.gd. (Current hits are keycap label tables in InputGlyph.gd only; rule is preventive.)

### M. Mode / map / sky / weather labels -- owner new `core/rules/DisplayNames.gd` (pure statics; wraps existing tables)
Today: modes `MatchConfig.GAME_MODE_LABELS` (Lobby.gd:464, ResultsScreen.gd:215/232 -- already single; keep as the data and expose through DisplayNames);
mode tips `Lobby.MODE_TIPS` (:254); sky `Lobby.SKY_THEME_LABELS`/`_ITEM_TIPS` (:266); weather `MatchWeather.mode_labels()` (MatchWeather.gd:204, `capitalize()` of enum keys)
vs `TuningPanel` `def.display_name` else capitalize (:1200); map variant/size `enum.keys()[...].capitalize()` LoadingScreen.gd:440-441 (and Lobby map picker, 25 map/thumbnail lines);
`LobbySection` header summary builds "Classic . Round . Medium" (LobbySection.gd:85).
API: `DisplayNames.mode(mode_id)`, `.mode_tip(mode_id)`, `.map_variant(v)`, `.map_size(s)`, `.sky_theme(i)`, `.weather(i)`, `.special(id:StringName)`; unknown id returns a stable fallback, never "".
- Rule `ENUM_LABEL`: `\.keys\(\)\[[^\]]+\][^\n]*\.(capitalize|to_lower|to_upper)\(\)|\.keys\(\)\[` in ui/ autoload/. Allowed: DisplayNames.gd, core/, config/MapDef.gd (asset-path building, :220).
- Rule `CAPITALIZE_ID`: `\.capitalize\(\)` in ui/ game/ autoload/ outside DisplayNames.gd (hits: HUD.gd:1145, Lobby.gd:536, LoadingScreen.gd:440-441, TuningPanel.gd:1200-1201, MatchWeather.gd:207; game/Skybox.gd:795 is a node name: allowed).

### S. Gift (special) names and icons -- owners `config/specials/SpecialDef.gd` (add `display_name`) + `config/GiftIconTable.gd` (icons, existing)
No name owner: `String(id).capitalize()` is the label in HUD.gd:1145 (`_special_display_name`, used :639,:1111,:1129,:1483) and Lobby.gd:536 (its own comment notes SpecialDef lacks display_name).
Icons are already single (`GiftIconTable.shared().gift_pictogram`, Lobby.gd:532/451, HUD). Names flow through `DisplayNames.special(id)` which reads `SpecialDef.display_name` (fallback: capitalised id for the pending placeholder `MatchGifts.PENDING_SPECIAL_ID` -> "Special"). Rules `CAPITALIZE_ID` above; `GIFT_ICON`: `res://assets/gifts/` outside GiftIconTable/GiftModelTable allowed list (`config/`, `game/GiftCrate.gd`, `game/BlockFactory.gd` as 3D art owners; baseline records current hits).

## 2. Step 2: `tools/lint_single_source.py`
- Rule table in the script: `RULES = [Rule(id, regex, scope_globs, allowed_files, message)]` using the section 1 ids (NAME_FMT, NAME_RAW, COLOR_LOOKUP, DIAMOND, GLYPH_EVENTS, GLYPH_ASSET, GLYPH_TEXT, ENUM_LABEL, CAPITALIZE_ID, GIFT_ICON). Reuse `strip_line` from lint_magic_numbers (drops comments and, for regexes that need the string, a `keep_strings` flag per rule: NAME_FMT and GLYPH_TEXT match inside strings, the rest do not).
- Skip dirs as the magic lint (`.godot addons .git build feedback .claude tests tools source_art`) plus `config/` for ui-only rules; `.tscn` scanned only for GLYPH_ASSET.
- Baseline `tools/single_source_baseline.json`: `{rule: {file: count}}`. A file/rule may never exceed its baseline; a file absent from a rule's baseline must have zero; `--update` only lowers (same `--allow-new` escape as fca.35); `--list` prints violations with line numbers for a migration worker. Exit 1 on growth; print `SINGLE-SOURCE LINT GREEN|RED`.
- Wired like fca.35: import in `tools/full_gate.py`, `lint_code` joins the verdict, `single_source_lint` key in result.json and in the final line. Document in docs/AGENT_WORKFLOW.md.
- Tests `tools/test_lint_single_source.py`: per rule a synthetic bypass file fails (acceptance criterion), an allowed-file occurrence passes, baseline growth fails, `--update` refuses to raise. Concept-complete criterion: when a migration lands, its rules' baseline entries are deleted so any reappearance fails.
- Owned files: `tools/lint_single_source.py`, `tools/single_source_baseline.json`, `tools/test_lint_single_source.py`, `tools/full_gate.py`, `docs/AGENT_WORKFLOW.md`. Depends on fca.35 being on main (it edits the same `full_gate.py` lines; rebase on it).

## 3. Step 3: migration packages (disjoint files, ordered)
In-flight: 1pi.83 owns lobby files (Lobby.gd, LobbyPlayersPanel.gd, LobbySeatRow.gd, LobbySection.gd, lobby tscn); 1pi.81 owns the shared diamond in HUD.gd, lobby seat row and ResultsScreen/ScoreTable round overview. Do not touch those files until they merge; the core packages touch none of them.

| Pkg | Outcome | Owned files | Starts after |
|---|---|---|---|
| P0 | Lint (step 2), baseline of all current violations | tools/ files above | fca.35 on main |
| P1 | Core owners: PlayerNames additions, `SlotColors`, `DisplayNames`, `SpecialDef.display_name` (+ .tres display names for all specials), `Match.slot_color`; unit tests | core/rules/PlayerNames.gd, core/rules/SlotColors.gd, core/rules/DisplayNames.gd, core/bot_names.gd, config/specials/SpecialDef.gd + specials .tres, autoload/Match.gd, tests/unit/test_player_names.gd, test_slot_colors.gd, test_display_names.gd | now (parallel with P0, no UI) |
| P2 | Non-UI-overlap migrations: names in MatchStats; slot colour in BlockEffectsManager, GiftCrate; weather/enum labels in MatchWeather, LoadingScreen, TuningPanel; delete baselines for those files | autoload/match/MatchStats.gd, game/BlockEffectsManager.gd, game/GiftCrate.gd, autoload/match/MatchWeather.gd, ui/LoadingScreen.gd, ui/TuningPanel.gd | P1 |
| P3 | Glyph owner API + consumers: `InputGlyph.events_for_action/build_for_action`, migrate KeyRebindRow, LoadingScreen (also touched by P2: serialize P3 after P2), GiftDemoStrip. HUD gift glyph deferred to P6 | ui/InputGlyph.gd (or ui/InputPrompt.gd), ui/KeyRebindRow.gd, game/GiftDemoStrip.gd, tests | P1; P2 for LoadingScreen.gd |
| P4 | Lobby migration: "Bot N", "Team N", seat colour, mode/sky/map labels, special names, diamond via SlotDiamond | ui/Lobby.gd, ui/lobby/LobbyPlayersPanel.gd, ui/lobby/LobbySeatRow.gd, ui/lobby/LobbySection.gd, core/rules/LobbySeats.gd | 1pi.83 AND 1pi.81 merged, P1 |
| P5 | Results/ScoreTable/Minimap: names, colour resolve, team number | ui/ResultsScreen.gd, ui/ScoreTable.gd, ui/Minimap.gd | 1pi.81 merged, P1 |
| P6 | HUD migration: winner text, team label, colour, special name, gift glyph via build_for_action, share-row diamond | ui/HUD.gd | 1pi.81 merged, P3 |
Final: P7 (orchestrator-sized) removes empty baseline entries and asserts each rule's baseline is `{}`. **Done (Bontago-1pi.86.8):** all rules at zero, baseline `{}`; the lint fails any baseline entry unless `--allow-baseline` (test-only ratchet mode); `test_checked_in_baseline_is_empty` asserts it.
Each package ends with `python tools/lint_single_source.py` showing that concept's baseline reduced to zero for its files.

## 4. Decisions made (routine) and owner questions
- D1 slot-colour precedence stays live `PlayerSlot.color` then palette then fallback (all five copies already agree except GiftCrate argument order).
- D2 team number stays `MatchConfig.team_number_for`; only formatting moves.
- D3 `DisplayNames` is pure and lives in core/ (no scene tree); enum label tables stay where they are (MatchConfig.GAME_MODE_LABELS) and are re-exported.
- Q1 DECISION (orchestrator 2026-10-05: no gameplay effect, recommended option (a) taken; owner may override): gift display names. Placeholder is the capitalised id ("Jumping Bean"). Options: (a) add `SpecialDef.display_name` authored per special (recommended, P1 fills it from the capitalised id so nothing visible changes); (b) a `GiftConfig` label table. Visible only if you want different words.
- Q2 DECISION (orchestrator 2026-10-05: no gameplay effect, recommended option (a) taken; owner may override): localisation. Options: (a) plain strings in the single owners now, `tr()` later is a one-file change (recommended); (b) wrap in `tr()` keys from the start. Affects P1 only.
- Q3 DECISION (orchestrator 2026-10-05: no gameplay effect, recommended option (a) taken; owner may override): menu icons (`assets/ui/icons/*.svg` in MainMenu/PauseMenu/OptionsMenu) are plain scene assets today. Options: (a) leave them as scene resources, no rule (recommended); (b) a `MenuIcons` table. Pure consistency choice, no gameplay effect.
- Risk: lint regexes are line-based; multi-line string formats can slip. Mitigated by NAME_FMT matching the literal, not the call. Risk: P2/P3 both touch LoadingScreen.gd; serialized above.
