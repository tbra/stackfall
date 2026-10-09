# UI Reskin Plan: "Stackfall Arcade"

Epic bead: _to be created by the orchestrator_ (suggested title "UI reskin: Stackfall Arcade design system").
Design source: the **Stackfall Arcade** design system (claude.ai Design System artifact, owner's account; a frozen copy
of its tokens, fonts, logos, player markers and reference screens is in `docs/ui_reskin/`). Reference captures:
`M:/Bontago-tools/scratch/menu-atlas/final/` (menu atlas, 3 resolutions) and
`M:/Bontago-tools/scratch/screenshots-20261009/` (gameplay). Audited against `origin/main` @ `e0611e0`.

Owner decision 2026-10-10: **full in-game reskin** of menus, lobby, options, pause, loading, HUD, scoreboard and
results to the Arcade direction (chosen over "sky-glass" and "golden-hour poster" mockups). This is a
look-and-feel change only: no rule, input binding, network message or match setting changes. It is not an
`[ORIGINAL]` rule change. The few player-facing *behaviour* additions are fenced behind the owner questions below.

Every package obeys `CLAUDE.md` unchanged: static typing, **no magic numbers** (every colour/size below lives in a
`res://config` Resource), all input through the Input Map, gamepad focus must stay visible on every control,
no new addons (Bungee and Rubik are OFL font files, not addons).

## Design summary (what "done" looks like)

- **Surfaces are cut from the arena disc**, not the sky: warm violet-black `disc-950…400`
  (`#0e0b12 #16121c #1f1a26 #2a2433 #383040 #4a4154 #6e6478`). Text `cream #fff6ea`, `sand #d9cbbd`, `dust #a89aa8`.
  The UI never takes colour from the sky (peach day / navy night / storm green all change).
- **One accent glows: `rim #ffc65a`**, the disc's gold edge (active-tab notch, minimap ring, timer hurry, winner row, GO).
- **One primary action per screen: `flare #ff5a3d`** with **ink (`disc-900`) labels**, never white (white on flare is
  2.9:1; ink is 6.0:1). Positive `mint #59cc66`, negative `alert` = flare + ✕.
- **Players = `MatchConfig.player_colors` unchanged**, always shown with the existing diamond (`SlotDiamond`), restyled
  as the faceted beacon diamond in `docs/ui_reskin/markers/`.
- **Every raised control is a block**: face + 3 px lit top (face 38 % → white) + 6 px dark lip (face 30 % → black) +
  6 px solid ledge in `disc-950`; pressed = moves down 6 px, no ledge. Sunken controls (fields, meters, lists) are
  wells. Radii 3 / 5 / 8 / 12 px, **no pills** (current `pill_corner_radius_px = 26` goes away).
- **Type**: Bungee (display: wordmark, numbers, countdown, results banner) + Rubik variable (everything else);
  Manrope is retired from the UI. Buttons/labels/headings UPPERCASE; values and sentences sentence case.
- **HUD keeps today's layout** (scoreboard TL, timer ring TC, held/next BL, minimap BR) on `disc-900 @ 0.86` plates.
- Full token list with usage notes and contrast ratios: `docs/ui_reskin/tokens.json`. Component behaviour: the design
  system's component READMEs (copied into `docs/ui_reskin/components.md`).

## Current-state audit

- **One shared Theme**, `ui/theme/stackfall_theme.tres`, assigned in 7 scenes (`MainMenu`, `Lobby`, `OptionsMenu`,
  `PauseMenu`, `LoadingScreen`, `ResultsScreen`, `ScoreboardOverlay` `.tscn`) and preloaded once in `HUD.gd:997`
  (toast style). Not set project-wide in `project.godot`.
- **Per-instance menu styling** comes from `ui/theme/MenuStyleFactory.gd` (pills, wells, chips, cards, badges, glyph
  circle, `apply_ink`, WCAG `contrast_ratio`) fed by `config/MenuVisualTuning.gd` / `menu_visual_tuning.tres`
  (~120 exported tunables). Called from 11 UI scripts: `Lobby`, `lobby/LobbySeatRow`, `lobby/LobbyPlayersPanel`,
  `OptionsMenu`, `LoadingScreen`, `ScoreboardOverlay`, `MainMenu`, `ScoreTable`, `KeyRebindRow`, `ResultsScreen`,
  `PauseMenu`. Theme overrides are densest in `Lobby.gd` (23), `MainMenu.gd` (16), `HUD.gd` (16),
  `LobbySeatRow.gd` (12).
- **HUD styling** is code-built in `ui/HUD.gd` (1 616 lines: `_style_panel`, `_style_toast`, `_on_timer_ring_draw`,
  `_ensure_share_row_count`/`_update_share_row`, `_on_shape_preview_draw`) from `config/HUDVisualTuning.gd`
  (`panel_background_color`, `surface_*`, `ink_color`, share-bar, countdown, toast and minimap colours).
  `ui/ShareBar.gd`, `ui/SlotDiamond.gd`, `ui/Minimap.gd` draw their own pieces.
- **Input prompts** are drawn by `ui/InputGlyph.gd` (`_draw()` keycaps/mouse/pad) + `ui/InputPromptFlow.gd`.
- **Main menu backdrop** is `ui/MenuBackdrop.gd` + `ui/MenuDiorama.gd` (pastel sky, sun, diorama disc).
- **Dev panels** (`TuningPanel`, `NetDebugOverlay`, `SandboxPanel`, `SandboxConePanel`, `PerfOverlay`,
  `PhysicsComparisonPanel`) style themselves ad hoc.
- **Existing guards to keep green:** `tests/unit/test_menu_icons.gd` (icon contrast ≥ `icon_min_contrast_ratio`),
  `tests/unit/test_confirm_dialog_theme.gd`.
- **In-flight work:** `ui/Lobby.gd` was modified locally on 2026-10-10 (uncommitted at audit time). P3 must start from
  whatever lands, not from `e0611e0`.

## Packages

P0 is serial and first. P1–P7 then run in parallel with disjoint file ownership. P8 closes.
`MenuStyleFactory.gd`, `stackfall_theme.tres` and the new tuning Resource are **owned by P0 only**: a later
package that needs a new factory helper asks for a P0 follow-up rather than editing them.

### P0 — Foundation (blocks everything)
Owns: `assets/ui/fonts/` (add Bungee-Regular.ttf, Rubik-Variable.ttf + OFL), `assets/ui/markers/` (new),
`assets/ui/stackfall_mark.svg` (replace with `docs/ui_reskin/logos/stackfall-mark.svg`, add lockups),
`config/ArcadeVisualTuning.gd` + `config/arcade_visual_tuning.tres` (new), `ui/theme/BlockStyleBox.gd` (new),
`ui/theme/stackfall_theme.tres`, `ui/theme/MenuStyleFactory.gd`, `docs/ART_DESIGN_SYSTEM.md` (mark superseded).
- `ArcadeVisualTuning` exports every token in `docs/ui_reskin/tokens.json` (colours, spacing, radii, depth, opacity,
  font sizes). `MenuVisualTuning`/`HUDVisualTuning` keep their API this package; their `.tres` values are re-pointed to
  arcade values where a 1:1 mapping exists (table in `docs/ui_reskin/mapping.md`).
- `BlockStyleBox extends StyleBox` with `_draw()` implementing the block recipe (face, top light, lip, ledge,
  optional pressed state) from `ArcadeVisualTuning`. A single `StyleBoxFlat` cannot do it (one `border_color` for all
  sides). Wells stay `StyleBoxFlat`.
- Rebuild `stackfall_theme.tres` values: fonts (Rubik 500/800 variations, Bungee display variation), Button
  normal/hover/pressed/disabled/focus as `BlockStyleBox`, LineEdit/OptionButton/ItemList/HSlider/CheckButton per
  design system; focus = 3 px `cream` outline, 3 px outside.
- `MenuStyleFactory`: add `apply_block(button, face, ink)` and `make_plate()`; keep old function names working by
  routing them to the new look (so P1–P7 can migrate call sites gradually without breaking the build).
- Tests: theme loads; every text/face pair in `ArcadeVisualTuning` meets its documented ratio (reuse
  `MenuStyleFactory.contrast_ratio`); `test_menu_icons` stays green with ink-on-face icons.
- Acceptance: `godot --headless --editor --path . --quit` clean; game runs; every menu already reads disc-dark
  through the shared theme even before P1–P7.

### P1 — Main menu
Owns `ui/MainMenu.tscn/.gd`, `ui/MenuBackdrop.gd`, `ui/MenuDiorama.gd`. Left column per *Main menu (screen)*:
lockup, Name field, HOST (primary), JOIN, PLAY OFFLINE, then OPTIONS / QUIT small; Join and Local sub-pages swap
in place. Backdrop per **owner question 1**. Footer KeyPrompts bottom-right on a plate.

### P2 — Options, pause, rebinding
Owns `ui/OptionsMenu.tscn/.gd`, `ui/PauseMenu.tscn/.gd`, `ui/KeyRebindRow.tscn/.gd`, `ui/SliderNav.gd`,
`ui/CycleSelector.gd`, `ui/FocusScrollContainer.gd`. Side tabs with `rim` notch; group rule headers; sliders become
SegmentMeters (keep `SliderNav` stepping semantics; cell count from tuning); dropdown blocks; BindingRow listening
state ("PRESS A KEY…" in `rim`); pause = centred Dialog, RESUME primary, LEAVE MATCH flare-label secondary.

### P3 — Lobby
Owns `ui/Lobby.tscn/.gd`, `ui/lobby/*`. Two panels (Match settings / Players), StatusBadge, Advanced/Experiments as
Section headers with value summaries, gift/special/experiment ChipToggles (✓ box), PlayerSlot rows with beacon
diamond, ready badge, bot difficulty dropdown and ✕ remove, dashed open seat, START MATCH primary bottom-right.
Starts only after the in-flight `Lobby.gd` work is integrated.

### P4 — Match HUD
Owns `ui/HUD.tscn/.gd`, `ui/ShareBar.gd`, `ui/SlotDiamond.tscn/.gd`, `ui/Minimap.gd`, `ui/Tutorial.tscn/.gd`,
`config/HUDVisualTuning.gd`, `config/hud_visual_tuning.tres`. Plates at `hud-plate`; scoreboard rows (diamond, name,
10 %-tick bar, Bungee %; local row "· YOU" in `rim`); timer ring in slot colour → `rim` in last 2 s → `locked` full
ring "LOCKED"; held/next block cards ("NEXT · GIFT" in `rim`); minimap with 3 px `rim` ring + glow; toasts →
Callouts (✕/✓/★ ink tile); countdown in Bungee 128 px, GO in `rim`; tutorial TipBanner with step block, under the
ring, never over it. Must be checked over day, night, storm and snow skies.

### P5 — Results, scoreboard overlay, loading
Owns `ui/ResultsScreen.tscn/.gd`, `ui/ScoreboardOverlay.tscn/.gd`, `ui/ScoreTable.gd`, `ui/LoadingScreen.tscn/.gd`,
`config/LoadingScreenTuning.gd` + `.tres`. Results: mode kicker in `rim`, Bungee banner, table rows on `disc-700`,
winner row tinted toward `rim` with 4 px rim edge, PLAY AGAIN primary. Loading: card with mode name in Bungee and
4 mint progress cells per player (no spinners).

### P6 — Input prompts
Owns `ui/InputGlyph.tscn/.gd`, `ui/InputPromptFlow.gd`, `config/InputGlyphTable.gd`/`.tres` (colours only).
Keycaps become `cream` blocks with ink legend and lip; pad face buttons A mint / B flare / X player-2 blue / Y rim
with ink letters. Keep every existing binding/label path and the `_draw()` fallback.

### P7 — Dev overlays (token swap only)
Owns `ui/TuningPanel.*`, `ui/NetDebugOverlay.*`, `ui/SandboxPanel.*`, `ui/SandboxConePanel.gd`,
`ui/PerfOverlay.gd`, `ui/PhysicsComparisonPanel.gd`. Replace ad-hoc colours with `ArcadeVisualTuning` plate/ink
tokens at caption size. No layout redesign.

### P8 — Integration & review
Re-run the menu-atlas capture at 1280×720, 1920×1080 and 3440×1440 plus the gameplay set; side-by-side against
`docs/ui_reskin/screens/`. Checks: gamepad focus visible on every focusable control (synthetic `InputEventJoypad*`
traversal test per screen), no text under 13 px except dev overlays, contrast test green, full gate green.
Reviewer (`stackfall-reviewer`) compares each screen against the component READMEs.

## Owner decisions needed before dispatch

1. **Main-menu backdrop** — (a) keep the pastel diorama but re-lit in disc/rim colours (P1 only, cheap), or
   (b) a slow orbit over a live arena (the design system's reference; needs a scene in the menu, perf budget check).
2. **Colour-assist diamonds** — the design system adds an optional per-slot shape mark inside each diamond for
   players who can't separate red/blue/purple. Ship it as a new Options toggle (new setting = player-facing,
   would be its own small package P9), or leave out for now?
3. **Font change** — confirm Manrope is retired in favour of Bungee + Rubik (affects every screen and tests that
   assert font resources).

## Suggested Beads (orchestrator creates; `--actor stackfall-orchestrator`)

Epic + 10 children: P0 (blocks P1–P7), P1, P2, P3 (also blocked by in-flight lobby work), P4, P5, P6, P7,
P8 (blocked by P1–P7), and a `decision` issue with `--label human --assignee Tony` for the three owner questions
above, gating P1 (Q1), P9/P2 (Q2) and P0 (Q3). Routing: P0, P4 Sonnet (P4's HUD.gd is large); P1–P3, P5–P7 Sonnet;
P7 Haiku is acceptable; reviews Sonnet.
