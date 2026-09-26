# M7 — Presentation polish: art direction & package plan

Bead: Bontago-xtq.24. Spec: §2.10 (lines 302-322), §M7 accept (lines 560-563),
§3.1 Low preset (line 327). Owner supersession honored: the disk is **opaque,
mirror-like, never transparent** (2026-09-23, Bontago-xtq.11), not "glass"
(the 2026-09-22 sentence in §2.10's lead-in is stale).

This document is the art-direction proposal and the M7 package split. It does
not implement anything; `docs/M7_PLAN.md` (not yet written) would carry the
same file-ownership tables once the owner answers §5's questions.

## Owner-selected visual direction (2026-09-26)

The owner selected [cel-shaded Sunset Signal with home beacons](art_mockups/08-cel-shaded-home-beacons.png) as the game's gameplay visual target. This supersedes the more realistic rendering of the original proposal wherever they conflict: use graphic sunset clouds, restrained outlines and banded block lighting, an **opaque** graphite disk with stylized mirror reflections, crisp red/blue territory contours, and low geometric home beacons in place of cloth pennants. The image is a visual target, not a rules-accurate screenshot or finished asset specification.

For menus, retain the red/blue block `STACKFALL` logo and “Build · Balance · Dominate” tagline. The owner rejected the previous generic translucent-panel main-menu and lobby layouts. A replacement design is still under review; no proposed menu flow is implemented. The other implementation choices in §5 remain open; visual selection alone does not settle them.

**All images are references, not final art (owner, 2026-09-26).** Interpret their mood, palette, lighting and shape language; do not reproduce them pixel-for-pixel or treat any layout, count, HUD arrangement or label in them as a requirement. Rules, HUD contents and player counts come from `docs/SPEC.md`; 08 happens to show two players and omits spec-required HUD elements (max height, special indicator), which the game still needs.

**Menu and lobby direction: layered pastel (owner, 2026-09-26).** The owner likes a layered-3D, soft-pastel look for menus and believes it pairs with the 08 gameplay style. The references are five third-party images kept locally only, in `feedback/menu ref/` (gitignored; not redistributable). In words, they show: paper-cut layers stacked with soft drop shadows; a cream/sand ground with mint, powder-blue, apricot and coral accents; slate or deep-teal contrast panels; raised pill-shaped controls and sunken input wells; rounded "plate" cards stacked with offsets; and diorama-style scenery. The mockups are saved locally as [10-main-menu-layered-pastel.png](art_mockups/10-main-menu-layered-pastel.png) and [11-lobby-layered-pastel.png](art_mockups/11-lobby-layered-pastel.png) (canvas originals: row 3 of <https://claude.ai/artifact/WNqknn7JxDHiFRoQX9BDtE>). The owner approved their direction, with the same references-not-final caveat. Key cues:
- stacked paper cards behind the main panel;
- a paper-cut sky with a layered sun and cloud strata;
- a floating layered-plate island carrying 08-style beacons;
- coral as the primary/focused fill, with a dark outline for gamepad focus;
- dark slate ink on cream for text contrast.

The owner has not accepted the menus as final; M7 menu work still needs a design pass that honours both references.

**Open conflict with spec §2.10 (needs an owner answer before block-material work).** 08 shows each cube cell outlined inside a piece. §2.10 and the closed `Bontago-xtq.3` require blocks to read as one solid merged shape with no visible per-cell cubes. This ties to Q2 below (seam style). Either amend the spec (option (a), cell-grid seams, would be the closest match to 08) or keep merged blocks and match 08 only in lighting and colour. Do not decide this in code.

---

## 1. Current state inventory

Per §2.10 bullet, what already ships and where:

**Disk** (mostly done, M2-era + several "Feel" bug rounds):
- Opaque mirror-like surface: `config/TerritoryVisuals.gd` (`disk_metallic`
  0.1, `disk_roughness` 0.3, no opacity fields — removed by Bontago-xtq.11).
- Sky reflection: `game/Skybox.gd` `configure_ssr()` (lines 159-166) writes
  `Environment.ssr_*`; `configure_reflection_probe()` (169-211) sizes a
  static `ReflectionProbe` for `MapDef.RADIUS_LARGE + margin`.
- Per-pixel planar mirror: `game/DiscMirror.gd` (279 lines) renders a mirrored
  `SubViewport` camera; `shaders/territory.gdshader` composites it
  (`mirror_strength`, `mirror_max_luminance` in `TerritoryVisuals.gd` lines
  267-296).
- Territory tint + animated outline: `shaders/territory.gdshader` (448
  lines), driven by `TerritoryVisuals.gd` `tint_alpha`, `outline_*` (98-107).
- Contested shimmer: `TerritoryVisuals.gd` `contested_*` (109-116), consumed
  by the same shader.
- Hole glow: `TerritoryVisuals.gd` `hole_rim_*` (118-122).
- **Gap:** none of §2.10's disk bullet is missing; it is the most complete
  area. Remaining polish is tuning, not new systems (already many owner
  "Feel" rounds — see `bd list --status closed | grep -i feel`).

**Blocks** (partially done):
- Solid single-mesh shapes (no per-cell cubes): `core/blocks/BlockMeshBuilder.gd`
  (built by `game/BlockFactory.gd` lines 128-154), closed as Bontago-xtq.3.
- **Missing:** "Bevelled cubes with a subtle PBR material and an emissive
  seam in the owner's color" and "glow brighter when contributing influence."
  `game/BlockFactory.gd._material_for_color()` (lines 155-161) builds a flat
  `StandardMaterial3D` with only `albedo_color` set — no roughness/metallic,
  no bevel, no emission, no influence-driven glow. This is the single largest
  concrete gap against §2.10.

**Sky** (partial):
- Procedural sky + six-face placeholder box + matching `shader_type sky`
  cubemap (`game/Skybox.gd`, `shaders/cubemap_sky.gdshader`), one set per
  map (`MapDef.skybox_set`), `config/skybox_config.tres` default "beach".
  Sets are the *original 2003 install's* placeholder textures
  (gitignored, `tools/install_original_assets.ps1`), not curated
  dawn/sunset/stormy/night themes.
- **Missing:** volumetric-fog cloud layer below the disk, a distant
  ocean/landscape backdrop, and a real theme set (the spec names
  dawn/sunset/stormy/night; the placeholder sets are whatever the original
  install shipped, e.g. "beach"). `GraphicsPreset.gd`'s own class doc
  (lines 9-12) says explicitly: "SSIL/volumetric fog fields intentionally
  absent... M7 presentation polish adds them."

**Effects** (missing entirely):
- No `GPUParticles3D` node anywhere in `game/` (grep confirmed). No
  explosion/lava/dust/debris particles, no camera shake, no
  falling-block trail/fade. `docs/M6_PLAN.md`/`config/TiltTuning.gd` cover
  physics-side special *behavior*; nothing renders their visual punch yet.

**HUD** (mostly done, missing the minimap):
- Timer ring, next-shape preview, max height, per-player territory share
  list, special/pending-queue indicator, goal capture ring, reject/relocate/
  winner/gift toasts: all in `ui/HUD.gd` (607 lines; see its own class doc,
  lines 1-8: "The minimap and presentation polish are M7.").
- **Missing:** the minimap (top-down territory texture) — the one HUD item
  §2.10 lists that HUD.gd's own doc defers to M7.

**Audio** (mostly done, missing "adaptive"):
- Impact volume/pitch by impulse: `autoload/Sfx.gd` `_on_block_impacted()`
  (226-235), `AudioConfig.impact_volume_db()`.
- Stacking rising tick, specials' warning sounds, custom music folder:
  `autoload/Sfx.gd` events table (`config/AudioConfig.gd` lines 71-90),
  `_refresh_music_root_dir()` (77-91) reading `Settings.custom_music_dir()`
  (Bontago-keo.14, closed).
- **Missing:** "adaptive" music that intensifies as someone nears capture.
  `Sfx.play_music()`/`_play_music_stream()` (147-160) plays one looping
  stream with no intensity parameter; there is no `Events` signal or Sfx
  hook reacting to `goal_capture_progress` for music layering.

**Main menu / graphics presets** (structurally present, not applied):
- `config/GraphicsPreset.gd` + `config/graphics_presets/{low,medium,high}.tres`
  exist and are selectable in `ui/OptionsMenu.gd` (line 127), and
  `Settings.graphics_preset_changed` (Settings.gd line 14) fires on change —
  but **nothing subscribes to it**: grep of `game/*.gd` and `ui/*.gd` for
  consumption of that signal returns only the emitter and the menu that reads
  the current value. MSAA/shadow-atlas/SSR are never actually written to a
  live `Viewport`/`Environment` from a preset pick today. This is the second
  concrete gap: the low/high split exists on paper but has no effect in play.
- `ui/MainMenu.gd` (340 lines) is a functional menu (Host/Join/Steam/Sandbox/
  Tutorial/Options entries) with no stated visual identity beyond default
  Godot `Control` theming — no custom theme resource under `res://ui/` found.

---

## 2. Art direction proposal — "Modernised Bontãgo"

One coherent look: a bright, toy-like arena floating in open sky — a glossy
obsidian-black disk (not literal obsidian color; think wet-stone/onyx dark
neutral, so every owner tint reads clearly against it) holding
candy-coloured, gently bevelled blocks, under a big, legible sky that changes
with match theme. The existing disk/territory shader already nails the
"toy arena" mood (soft tint + pulsing rim + shimmer); the proposal below
extends the same visual grammar to blocks, sky, effects, HUD and audio
instead of introducing a second style.

### Palette
- **Neutral base:** disk `disk_base_color` stays a dark neutral
  (current `Color(0.68, 0.70, 0.74)` reads as light grey-blue; recommend
  darkening toward `Color(0.10, 0.10, 0.12)` so the 8 saturated owner tints
  and the sky reflection both pop — matches `docs/original_stacked-tower.png`
  which shows a dark, glossy floor, not a light one). This is a
  `TerritoryVisuals.disk_base_color` value change, owned by the block/disk
  material package (P2 below), not a new field.
- **Owner colors:** unchanged — `MatchConfig.player_colors` (8 entries) is
  already the single source of truth for every tint (territory, flags,
  blocks, HUD swatches); nothing here proposes new colors, only surfaces
  they render on.
- **Sky/lighting:** warm-to-cool per theme (see Sky themes below); no new
  palette system needed beyond the theme set itself.

### Materials & lighting mood
- Blocks: `StandardMaterial3D` with `metallic ~0.15`, `roughness ~0.35`
  (a "toy plastic" PBR response — not chrome, not chalk), a thin
  `emission` seam in the owner color, and bevelled edges from the mesh
  itself (see block seam options below).
- Lighting stays a single `DirectionalLight3D` + sky ambient (current setup,
  `Main.tscn`) — no new light rigs; §2.10 never asks for more than sky-driven
  lighting, and adding artificial fill lights would fight the disk's own
  planar-mirror reflection (which mirrors whatever is actually lit).

### Sky themes
§2.10: "procedural sky, with support for HDRI panoramas for different themes
(dawn, sunset, stormy, night)." Two real implementation choices:

**Option A — keep the six-face box+cubemap pipeline** (`game/Skybox.gd`,
`shaders/cubemap_sky.gdshader`), add curated theme sets alongside the
existing placeholder "beach" style set, selected per `MapDef.skybox_set` or
a lobby setting.
**Option B — switch to Godot's native `PanoramaSkyMaterial`** (single
equirect HDRI texture, `Sky.sky_material`), dropping the six-face box
entirely.
**Recommendation: Option A.** The six-face pipeline is already built,
tested (`tools/skybox_seam_probe.gd`, `tests/unit/test_skybox.gd`), wired to
reflections (`configure_ssr`/`configure_reflection_probe`), and the box
gives per-face UV control the class doc explicitly says is being kept for
exactly this reason (`game/Skybox.gd` lines 35-48). Rebuilding on
`PanoramaSkyMaterial` would re-litigate reflection wiring already accepted
in three "Feel" rounds (xtq.8, xtq.12, xtq.20) for no described gameplay
gain. New theme sets are just new asset folders (or a licensed/generated
substitute, since the placeholder set is third-party and gitignored — see
owner question 4) plus a `default_set`/theme-id entry in `SkyboxConfig` and
`MapDef`.
- **Cloud layer:** volumetric fog plane below disk height (`FogVolume` +
  `FogMaterial`, Forward+'s native path) — cheap on High, dropped on Low
  (§3.1: "turns off... volumetrics").
- **Distant backdrop:** a simple unshaded ocean/landscape ring mesh at the
  skybox box's radius, textured per theme — not geometry the player can
  approach (box is 400 m, field radius max 60 m per `Skybox.gd` line 14),
  so a flat textured ring reads convincingly from the fixed camera range.

### Motion / effects language
- GPUParticles3D, budgeted per §3 performance rules below:
  - **Landing dust**: small burst on block settle (`Events.block_placed`
    already fires — `autoload/Sfx.gd` line 242 shows the existing hook
    shape to copy).
  - **Impact debris/explosion**: `Events.block_impacted`-scaled burst for
    high-impulse hits and special detonations (Bomb, Volcano, Earthquake —
    `game/specials/EarthquakeEffect.gd` already emits an effect-start signal
    to hook).
  - **Edge-fall trail + fade**: a block whose center leaves the disk radius
    (`BlockRegistry` already tracks per-block position for territory) gets a
    short trail (`GPUTrail`-style ribbon, or a simple particle emitter
    parented to the falling body) and a `modulate.a` tween to 0 before
    `queue_free()`.
- **Camera shake:** scales with impulse magnitude (reuse the impact-speed
  signal `Events.block_impacted` already carries), toggle in
  `ui/OptionsMenu.gd` next to existing sliders, tunable magnitude curve in a
  new `config/CameraShakeConfig.gd` Resource (not raw numbers in
  `CameraRig.gd` — CLAUDE.md "no magic numbers").
  - Two implementation options: **(a)** a positional-noise offset applied to
    `CameraRig`'s follow transform, decaying over a fixed time; **(b)** a
    lightweight spring-mass shake (Godot's `Tween`-free, a critically-damped
    oscillator updated in `_physics_process`). **Recommendation: (a)** —
    simpler, cheaper, and every accepted "Feel" round so far
    (`mv0.21`-`mv0.29`) already tunes `CameraRig` as a direct transform
    write, not a physical simulation; matching that pattern keeps the two
    camera-affecting systems (follow-lag and shake) consistent and easy to
    reason about together.

### HUD styling
- Minimap: a top-down `SubViewport` reusing `TerritoryOverlay`'s existing
  shader output (the overlay is already a single textured disk mesh —
  render it from an orthographic top-down camera into a small
  `SubViewportContainer` in the HUD corner) rather than a second,
  independently-maintained top-down renderer.
  Two options: **(a)** live `SubViewport` camera (always current, small
  continuous render cost) or **(b)** a periodically-refreshed
  `ViewportTexture` snapshot (cheaper, up to N ms stale).
  **Recommendation: (a)** — the territory shader is already cheap (one
  disk, analytic circles, `max_shader_circles` bounded), and a second
  small-resolution (e.g. 256×256) viewport of the same scene is a rounding
  error against the 300-block/144 fps budget; staleness would read as a
  correctness bug on a competitive HUD element.
- Everything else (timer ring, capture ring, share list, special
  indicator, toasts) keeps its current `ui/HUD.gd` drawing approach — no
  redesign, this milestone reskins colors/line-weights to match the new
  disk palette and adds the minimap panel alongside it.
- Main menu: a custom `Theme` resource (`res://ui/theme/stackfall_theme.tres`)
  applied to `MainMenu.tscn`/`Lobby.tscn`/`OptionsMenu.tscn` root controls,
  matching the block/disk palette (dark neutral panels, owner-color accent
  on focused buttons) — no new addon, pure `Theme`/`StyleBoxFlat` resources.

### Audio identity
- Adaptive music: subscribe to `Events.goal_capture_progress` (already
  emitted — `ui/HUD.gd._on_goal_capture_progress()` line 360 shows the
  existing consumer shape) in `autoload/Sfx.gd`, cross-fading between two
  stems of the same track (calm / intense) via
  `AudioStreamPlayer.volume_db` ramps, gated by a new
  `AudioConfig.adaptive_music_enabled` + threshold fields.
  Two options: **(a)** two-stem crossfade (calm/intense) driven by capture
  progress; **(b)** a layered stem stack (drums/bass/lead added
  progressively) for a smoother ramp. **Recommendation: (a)** — only one
  extra stream to source/license and mix, matches the "custom music folder"
  contract (`Settings.custom_music_dir()`) with a predictable two-file
  naming convention (`<track>.mp3` + `<track>_intense.mp3`), and (b)
  requires original stems the project doesn't have licensing evidence for.
- Impact/stacking sounds unchanged — already implemented and closed.

---

## 3. Performance budget (§M7 accept: 144 fps @1440p, 300 blocks, High)

- **Cheap, keep on High and Low:** block material change (still one material
  per owner color, `BlockFactory._material_for_color()`'s cache is
  unaffected by adding roughness/metallic/emission — same draw call count).
  HUD minimap at low resolution (256×256 SubViewport, one extra camera pass
  of already-cheap disk geometry).
- **High-only, drop on Low (§3.1):** volumetric fog cloud layer, SSR
  (already gated by `GraphicsPreset.ssr_enabled` and `Skybox.configure_ssr()`
  — just needs a consumer wiring the preset in, see owner question 3),
  `ReflectionProbe.UPDATE_ALWAYS` → force `UPDATE_ONCE` on Low
  (`TerritoryVisuals.reflection_probe_update_always` already exists as a
  field; Low preset should override it), full-res `DiscMirror` SubViewport →
  drop `mirror_resolution_scale` further or disable the planar mirror
  entirely on Low.
- **Needs a bench before acceptance** (`tests/bench/`, pattern from
  `bench_rain.gd`/`bench_physical_balance.gd`):
  - `bench_block_particles.gd` — 300 settled blocks + a burst of landing/
    impact particles concurrently, measuring ms/frame at High.
  - `bench_disc_mirror_cost.gd` extension (or reuse `bench_territory.gd`'s
    harness) — confirm `DiscMirror` SubViewport + `ReflectionProbe` +
    volumetric fog together, not just individually (each was benched alone
    for earlier "Feel" packages; §M7's accept is the *combination*).
  - A minimap-viewport-cost bench only if the first two benches show headroom
    is already tight; otherwise it is cheap enough to fold into a manual
    fps counter check.
- **Camera shake and adaptive music are free** (no new render/physics cost;
  shake is a transform offset, music is an extra `AudioStreamPlayer` layer).

---

## 4. Proposed package split for the M7 plan

Ownership rule: file ownership, not function ownership; a package that needs
a file another package also needs is flagged below rather than silently
overlapping.

| # | Package | Owned files (new unless noted) | Depends on | Screenshot check? |
|---|---------|--------------------------------|------------|---------------------|
| P1 | **Graphics preset apply** | new `game/GraphicsApplier.gd` (or similar autoload-attached helper) subscribing to `Settings.graphics_preset_changed`, writing MSAA/shadow-atlas/SSR/volumetric-fog-enable onto the live `Viewport`/`Environment`; extend `config/GraphicsPreset.gd` with `volumetric_fog_enabled: bool`, `ssil_enabled: bool` fields (§3.1). | none (first — everything else's Low-preset behavior depends on this existing) | No (headless: assert Viewport/Environment fields change on signal) |
| P2 | **Block material** | `game/BlockFactory.gd` (`_material_for_color`, bevel via `core/blocks/BlockMeshBuilder.gd` — **shared file, coordinate with whoever else touches BlockMeshBuilder**), new `config/BlockVisuals.gd` + `config/block_visuals.tres` (metallic/roughness/emission/seam-width/influence-glow tunables), `config/TerritoryVisuals.gd` `disk_base_color` value edit only (not new fields). | none | Yes (1: block bevel+seam visible; budget 3 max) |
| P3 | **Sky themes + cloud/backdrop** | `config/SkyboxConfig.gd` (add theme-set list/id), `config/skybox_themes/*.tres` (new resources, one per theme), `game/Skybox.gd` (cloud `FogVolume`/backdrop ring child nodes + wiring), `game/Main.tscn`/`Field.tscn` FogVolume node (whichever scene owns environment — confirm with integrator which scene is not already owned by another in-flight package before touching it). | P1 (fog toggled by preset) | Yes (1-2: a theme switch + fog visible) |
| P4 | **Effects (particles, shake, edge-fall trail)** | new `game/effects/LandingDust.gd`, `game/effects/ImpactBurst.gd`, `game/effects/EdgeFallTrail.gd` (each a small pooled `GPUParticles3D` wrapper triggered off `Events.block_placed`/`block_impacted`), new `config/CameraShakeConfig.gd` + `.tres`, `game/CameraRig.gd` (add shake offset — **shared file with existing owner of follow/orbit logic; additive method only, do not restructure**), `ui/OptionsMenu.gd` (add shake-off toggle — **shared file, additive row only**). | P1 (particle density degraded on Low) | Yes (1-2: a burst + a shake) |
| P5 | **HUD minimap** | new `ui/Minimap.gd` + `.tscn` (SubViewport + orthographic camera pointed at the existing `TerritoryOverlay`), `ui/HUD.gd` (wire the new panel in — **additive section only**), `ui/HUD.tscn`. | none (reads existing `TerritoryOverlay`/`Field` nodes by path already established in `Main.tscn`) | Yes (1: minimap panel renders live territory) |
| P6 | **Adaptive music** | `autoload/Sfx.gd` (add capture-progress subscription + crossfade — **additive method + one new signal connection only**), `config/AudioConfig.gd` (add `adaptive_music_enabled`, stem-suffix, crossfade tunables). | none | No (headless: assert stem volume ramps with a synthetic `goal_capture_progress` emit) |
| P7 | **Main menu / UI theme** | new `res://ui/theme/stackfall_theme.tres`, `ui/MainMenu.tscn`/`ui/Lobby.tscn`/`ui/OptionsMenu.tscn` (apply `theme` property only — no logic script edits). | P2 (reuses the same palette decision) | Yes (1: menu look) |

Integration order: **P1 first** (every Low-preset behavior below it depends
on the signal actually being consumed). P2, P3, P5, P6 can run in parallel
worktrees (disjoint files). P4 touches `game/CameraRig.gd` and
`ui/OptionsMenu.gd`, both owned elsewhere in additive-only mode — serialize
P4 after P2/P7 land if the same files are mid-edit, or confirm disjoint
hunks before parallelizing. P7 depends on P2's palette decision (owner
question 1) landing first so the menu theme and the block/disk palette
agree. No package here requires a new interface-stub package ahead of it —
every dependency is on an existing, already-committed signal
(`Events`/`Settings`) or an existing resource type (`GraphicsPreset`,
`TerritoryVisuals`, `SkyboxConfig`), not on a not-yet-built consumer
contract.

Screenshot budget note: per-package max 3 windowed, off-screen
(`--position 10000,10000`) probes, per operating notes — P2/P3/P4/P5/P7 each
plan for 1-2, leaving headroom.

---

## 5. Owner questions

File as a single Beads `decision` issue (`--label human --assignee Tony`)
blocking P2/P3/P7 (P1/P4/P5/P6 do not depend on the answers below and can
start immediately).

**Q1. Disk base color darkening.** `TerritoryVisuals.disk_base_color` is
currently a light grey-blue (`0.68, 0.70, 0.74`). The proposal (§2) darkens
it toward a near-black glossy neutral so owner tints and sky reflections
read more clearly, matching `docs/original_stacked-tower.png`'s dark floor.
- (a) Darken to near-black neutral (recommended — matches the original
  reference screenshot's floor value).
- (b) Keep the current light neutral and rely on tint/outline contrast alone.
- (c) A different specific target color (owner to supply).

**Q2. Block seam/bevel style.** §2.10: "Bevelled cubes with a subtle PBR
material and an emissive seam in the owner's color."
- (a) A thin emissive line running the cell-grid seams of the merged mesh
  (visible even though the shape reads as one solid block) — closest literal
  reading of "seam," recommended.
- (b) A single emissive edge outline around the whole block's silhouette
  only (no interior seams) — simpler, but loses "seam" plural.
- (c) No literal seam geometry; simulate it with a rim-light shader term
  instead (cheapest, most stylized, least literal to the spec text).

**Q3. Sky theme set.** §2.10 names dawn/sunset/stormy/night; the only sets
that currently exist are the original 2003 install's placeholder textures
(gitignored, third-party, not a themed set).
- (a) Commission/generate four new licensed or procedurally-authored HDRI/
  six-face sets for dawn/sunset/stormy/night (recommended — matches the spec
  literally, no licensing risk since these would be original-to-this-project
  assets).
- (b) Keep only the placeholder set(s) as-is and treat "themes" as future
  scope, closing this bullet as partially done.
- (c) Procedurally generate the four themes at runtime by varying the
  existing `ProceduralSkyMaterial`'s sun/horizon/ground parameters (cheapest,
  no new textures, but not a true "HDRI panorama" per the spec wording).

**Q4. Minimap rendering approach.** (§2, HUD styling.) Confirms the live
SubViewport recommendation before P5 starts, since it is the more expensive
of the two options.
- (a) Live orthographic SubViewport camera reused from `TerritoryOverlay`
  (recommended, §2 reasoning above).
- (b) Periodic snapshot-refresh `ViewportTexture` instead, trading a small
  staleness window for lower continuous cost.

**Q5. Adaptive music approach.** (§2, Audio identity.)
- (a) Two-stem crossfade, calm/intense, gated on
  `Events.goal_capture_progress` (recommended).
- (b) Layered stem stack (progressive instrument add-in).
- (c) Simplest option: only raise `music_volume_db`/tempo is out of scope
  (pitch-shifting audio at runtime is not proposed by either a/b) as capture
  nears completion, no second stem needed at all.

**Q6. Third-party addon check** (CLAUDE.md: "Don't add third-party addons
without asking"). None of P1-P7 above currently need one — particles use
core `GPUParticles3D`, fog uses core `FogVolume`, camera shake and the
minimap are hand-rolled. Flagging only because §2.10's HDRI/theme work (Q3)
could tempt a sky-asset-pack addon; recommend **no addon**, source/author
theme textures as plain asset files under `res://assets/` (or gitignored
`assets/original/` pattern already established) instead.
