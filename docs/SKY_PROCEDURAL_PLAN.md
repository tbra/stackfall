# Procedural sky plan (Bontago-59o.9)

Owner ask: "If the sky look can be recreated in Godot with shaders and nodes that would be fantastic."
Design contract only. Base: main @ 07f8fc0. Do not touch `game/Skybox.gd` / `shaders/cloud_puffs.gdshader` until the birds/cloud-spread worktree merges (P0 gate).

## 1. What the sky look consists of today

Selected by `SkyThemeDef.sky_material` (`sunset.tres`, `night.tres`); `Skybox.apply_theme()` installs it on `environment.sky` (Skybox.gd ~501-548).

| # | Layer | Where | Baked or procedural |
|---|-------|-------|---------------------|
| 1 | Sunset gradient, painted sun disc, painted cumulus sea below horizon, painted upper strata | `assets/sky/sunset-clouds-v1.png` (1774x887 equirect) sampled in `sunset_clouds.gdshader` `sample_panorama()`/`sky()` | BAKED (only baked layer of the sunset theme) |
| 2 | Panorama animation: latitude sway, noise warp (faded near sun), two-phase flow drift of the far sea (`flow_phases`) | sunset_clouds L192-224 | procedural distortion of a texture |
| 3 | Cel-banded cloud layer above horizon (fbm on `noise_tex`, `cel_quantize`, `cel_ramp`, rim, sun-side warming) | sunset_clouds L230-255, `cloud_common.gdshaderinc` | procedural (noise texture `cloud_noise.tres`) |
| 4 | Sun core/halo (intensity 0 by default, panorama supplies the disc) and god rays (angular comb) | sunset_clouds L257-279 | procedural |
| 5 | 3D cel cumulus puffs (near/mid cloud sea), ellipsoid ray-intersect, fade into panorama by sampling it along the view ray | `vfx/CloudSea.gd`, `cloud_puffs.gdshader` (`puff_noise.tres`) | procedural, but its far fade reads the PANORAMA |
| 6 | Depth fog, FogVolume cloud deck, sun lens flare, birds, fireflies | Skybox.gd, vfx/ | procedural |
| 7 | Night: gradient, stars, twinkle, moon+phase, cel clouds | `night_sky.gdshader` | fully procedural EXCEPT the below-horizon sea, which is the sunset panorama graded via `moonlit_grade` |
| 8 | Optional original six-face jpg box + `cubemap_sky.gdshader` | Skybox.load_set (gitignored third-party art) | baked, separate look, unaffected |

Conclusion: layers 2, 3, 4, 5, 6 are already procedural. Only layer 1 (and its dependants: puff far-fade, night sea) is baked. The task is to replace the panorama's contribution: gradient + sun disc + upper strata + far cloud sea.

## 2. Feasibility per element (Godot 4.7 Forward+, `shader_type sky`)

- Gradient + sun + glow: trivial. Multi-stop vertical ramp on `EYEDIR.y` (zenith/mid/horizon/below), warm horizon band biased toward `sun_direction` (`pow(max(dot,0),k)`), hard-edged disc (`smoothstep` on angle) + halo. Uniforms already exist (`sun_*`). Cost: negligible.
- Upper strata / cel clouds: already implemented (layer 3). Extend with a second parallax layer (different scale/wind/bands) for the "layered sun and cloud strata" of mockup 08 (`docs/M7_ART_DIRECTION.md` L22). Cost: 2 x fbm (currently 2 fbm + 2 warp taps); fbm octave count is the lever.
- Cel banding: `cel_quantize` exists. Reuse.
- Far cloud sea below the horizon (the hard part): the painted cumulus is the only large-scale organised detail. Options: (a) plane-projected cel cloud layer for `eyedir.y < 0` using the same fbm/`cumulus_height`/`billow` helpers as puffs, with 2-3 depth strata by `1/(-y+lift)` projection, banded shading toward the sun; (b) raymarched volume (rejected: cost, and near-plane view from a disc camera at fixed height gains nothing). Pick (a). The near/mid 3D puffs already sell depth; the sky shader only needs the distant sheet. Cost: ~3 fbm per pixel below horizon; the sea covers a large screen area in gameplay (camera looks down at the disc) so this is the dominant new cost.
- Animated drift: `TIME`-scrolled noise coordinates, already used; flow_phases only needed if textures are warped, unnecessary for scrolling noise.
- Volumetric look for puffs: already achieved by ellipsoid + dome noise + cel bands. No change beyond swapping the far-fade colour source (P3).
- Reflection/radiance pass (`AT_CUBEMAP_PASS`): must stay cheap and static; compute gradient + sun + ONE static sea sample only (as today). Keep `PROCESS_MODE` as is.

## 3. Cost (target 144 fps, 1440p, High)

Sky pixels are shaded once per frame before geometry only where uncovered (Forward+ draws the sky last with early-z), so the disc/blocks/UI mask a large share. Budget: procedural sky <= the current shader + ~1.0 ms at 1440p on the reference mid-range GPU (spec §perf; 144 fps = 6.94 ms frame). Current cost is 1 mipmapped panorama read x1-2 (+ 4 noise taps, fbm). New: replace the panorama taps with ~3 extra fbm calls (each 3-4 noise taps) in the lower hemisphere. Mitigations: octave count uniform, sea only computed where `eyedir.y < 0`, radiance pass skips all noise, Low preset drops to one strata layer (GraphicsPreset flag). Measure with `tools/perf` sampler and stable-territory benchmark (recent commits b2210e6/b95ce55); acceptance is delta frame time, measured on an idle machine.

## 4. Risks

1. Art-direction: procedural noise clouds will not exactly match a painted plate; "same look" is an approximation and must be owner-approved (M7 pause point). Mitigation: side-by-side toggle and sign-off before swap.
2. Pixel-level sun/puff alignment: panorama is rotated by `sky_yaw_offset_deg` (184.06 deg) to sit under `sun_direction` and the DirectionalLight; procedural sun uses `sun_direction` directly, removing that coupling (a plus) but the two-sun bug (Bontago-1pi.1) returns if disc intensity is on with the panorama still shown. Toggle must switch the panorama fully off.
3. Puffs' far fade and the night sea sample the panorama (`cloud_puffs.gdshader` `panorama_lod`, `night_sky.gdshader` sea). The procedural sea must expose a shared GLSL function (in `cloud_common.gdshaderinc`) so puffs sample the same colour along the view ray; otherwise seams appear.
4. `cloud_puffs.gdshader` / `Skybox.gd` / `CloudSea.gd` are being edited by another worker: P0 gate.
5. Reflection/ambient: sky radiance drives ambient light and disc mirror; a different average colour changes lighting. Tune horizon/ground ramps to match measured average of the panorama (compute once in a tool, store as constants in the SkyThemeDef).
6. Aliasing/shimmer on the horizon at high frequency noise; fade strata to horizon colour (already done for cloud layer via `cloud_fade_*`).
7. Night sea grade: depends on panorama luminance; needs its own procedural sea or reuse of the new one graded with `moonlit_grade` (function takes colour, so works).
8. Removing a 1774x887 PNG gains nothing in perf; keep the asset until sign-off, then delete in a follow-up.

## 5. Owner approval / comparison toggle (M7 pause point)

Ship the procedural look as an OPT-IN alternative first; default stays painted. A new bool uniform `procedural_sea_mix` (0 = panorama, 1 = procedural; also fractional for a wipe) lives in `sunset_clouds.gdshader`. Exposed in the F4 `TuningPanel` Sky tab (it auto-lists `SkyThemeDef` exports; add a `sky_look_procedural: bool` export on `SkyThemeDef` written to the shader by `Skybox.apply_theme()`), plus a split-screen debug (`procedural_split` uniform: left of screen x = painted, right = procedural, using `SCREEN_UV`... note sky shaders lack SCREEN_UV, so use an eyedir-yaw split relative to camera by passing `split_yaw_deg` set from CameraRig yaw, or simply a hotkey toggle A/B). Recommended: plain toggle plus an off-screen screenshot tool that renders both looks from identical camera and stitches a side-by-side PNG for the owner. Owner sign-off (a `decision` bead, label human) is required before flipping the default or deleting the PNG. This is a look change, not an ORIGINAL rule change.

## 6. Staged packages (each <= 10 files, ~30 min)

Interface-stub package: P1 owns adding the `SkyThemeDef` fields and shader uniform defaults so consumers compile.

- P0 (gate, no work): confirm the birds/cloud-spread worktree is merged; base must contain it.
- P1 Stub + toggle wiring. Files: `config/SkyThemeDef.gd` (`sky_look_procedural: bool = false`, `procedural_sea_mix: float`, gradient stops/sea uniforms as typed exports), `game/Skybox.gd` (write toggle + params in `apply_theme`), `ui/TuningPanel.gd` only if the Sky tab does not auto-render the new exports, `tests/unit/test_skybox.gd`. Acceptance: with default false, sky pixel-identical (screenshot diff = 0); test asserts params reach the material.
- P2 Procedural gradient + sun/halo + horizon glow in `sunset_clouds.gdshader` (new branch under `procedural_sea_mix`), `shaders/include/cloud_common.gdshaderinc` (new pure functions `sky_gradient`, `sun_disc`). Files: those two + `config/sky_themes/sunset.tres` (uniform values). Acceptance: toggled sky sun on `sun_direction`, no second disc, luminance histogram of top/horizon bands within tolerance of the panorama render.
- P3 Procedural upper strata (second parallax layer) + far cloud sea (plane-projected strata below horizon) in the same shader + include; expose `procedural_sea_color(dir, time)` for the puffs. Files: `sunset_clouds.gdshader`, `cloud_common.gdshaderinc`, `sunset.tres`. Acceptance: perf delta <= 1.0 ms (stable benchmark), no NaN at `eyedir.y == 0`, radiance pass has no noise taps.
- P4 Consumers: `cloud_puffs.gdshader` far-fade and `night_sky.gdshader` sea use the shared function when the toggle is on; `vfx/CloudSea.gd` copies the new uniforms. Files: those three + `night.tres`. Requires P0 merged. Acceptance: no visible seam between puffs and sea at 3 distances (screenshot), night graded sea present.
- P5 Compare tool. `tools/screenshot_sky_compare.gd/.tscn` (+ .uid): headless-off-screen (`--windowed --position 10000,10000`, quit after capture) renders painted vs procedural at the same 3 camera poses (default, low orbit, looking at sun) and stitches side-by-side PNG under `docs/`. Acceptance: PNG produced; owner reviews. Then a `decision` bead for approval.
- P6 (after approval) flip default, drop unused panorama taps, delete `assets/sky/sunset-clouds-v1.png` and the `panorama` uniform, Low-preset strata reduction (`GraphicsPreset` + `config/graphics_presets/low.tres`). Acceptance: full GUT, open-project check clean, perf sample.

Order: P0 -> P1 -> P2 -> P3 -> P4 -> P5 -> owner decision -> P6. P2/P3 both own `sunset_clouds.gdshader` so they are serialised.

## 7. Checks common to all

`godot --headless --editor --path . --quit` clean; `tools/run_gut.ps1 test_skybox`; off-screen screenshot comparison per P2-P5 (max 3 windowed runs per package, off-screen position 10000,10000). Exposure/weather overcast: `Skybox._apply_sky_exposure` writes the `exposure` uniform, so the procedural branch must multiply by `exposure` too.
