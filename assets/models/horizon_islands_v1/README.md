# Floating horizon islands v1 — Bontago-mp0.112

Three original low-poly world assets for the owner's horizon option3. Broad
faceted rock bodies taper under a restrained grey-green cap; no buildings,
foliage, waterfalls, collisions or gameplay objects. Their unequal widths and
depths provide distinct distant silhouettes. Editable Blender4.5 source and
seeded generator are included; no external images, models or texture references.

| Scene | Nominal width x depth x rock height | LOD0 / LOD1 / LOD2 triangles |
| --- | --- | --- |
| mesa.tscn | 60 x38 x32m | 320 /96 /32 |
| shelf.tscn | 88 x28 x23m | 320 /96 /32 |
| crag.tscn | 42 x50 x43m | 320 /96 /32 |

Irregular contours vary slightly beyond nominal dimensions; `geometry.json`
records actual bounds. Scene roots lie at the cap's surface center. In Godot,
Y is up and the rock extends down; Blender source uses Z-up. Each GLB contains
three same-pivot mesh nodes namedLOD0,LOD1,LOD2. Use the `.tscn` wrapper: the
raw GLB shows all three meshes by default, whereas each wrapper shows onlyLOD0
and assigns the shared vertex-color cel material to all three.

## Placement and compatibility

Place a few islands in world space, well beyond the arena, at unequal distances,
headings, heights, yaw angles and uniform scales. Bury roughly40–65% of the
rock body in the actual lower cloud layer; adjust the surface-center root against
Claude's final cloud height rather than copying the review coordinates. Keep
clear sky gaps and avoid a symmetrical decorative ring. No camera-following
translation or apparent approach is built into the asset: the moving camera
provides parallax naturally. The source has no animation.

`island_cel.gdshader` uses neutralCOLOR_0 facets and three directional-light
bands. It is lit and receives normal environment ambient/haze; it has no baked
sun direction, cloud position, panorama texture, weather state or Cycle phase.
Its white `tint` can be adjusted by the integrator if needed. Do not replace
shared sky/cloud/sun shaders or drive player/team colors through this material.
The plain GLB PBR material is a fallback; the wrappers supply the cel shader.

LOD selection is explicit, not wired. Show exactly one child mesh at a time.
LOD1 removes70% of triangles; LOD2 removes90%. Use screen coverage to decide
switches after integration; for example reviewLOD2 only when an island is a
small distant silhouette. Do not infer a measured frame-time improvement from
these triangle counts. All variants are visual-only and should cast no arena
interaction or collision; shadow/radiance policy belongs to sky integration.

## Evidence

`docs/art_mockups/horizon_islands_v1/` contains:

- multiview.png: three viewing angles per full model.
- lod_comparison.png: same camera framing across all three LODs.
- cloud_review.png: isolated day-like haze, sunset and night palette examples.
- camera_motion.gif: actual moving-camera native3D captures with fixed islands.
- native/:38original1280x720renders and native geometry evidence.
- verification.json: geometry checks and per-angle silhouette overlaps.

The clouds in this asset review are simple3D occluders. This is not the current
or future gameplay sky. It proves view-dependent3D occlusion/parallax in the
isolated stage, not final cloud layering, Cycle behavior or performance. Owner
art acceptance and Claude's integration into the queued sky work remain pending.

All nine exported meshes are closed after positional welding, have unit normals,
COLOR_0 and nondegenerate triangles. At0/60/120degree yaw, LOD1/full silhouette
intersection-over-union is at least.962 and LOD2/full at least.857. Full GLB byte
hashes match after regeneration. One tiny muted offscreen Godot4.7.2 review run
exited0 cleanly; isolated asset import and scene-wrapper checks also exited0
cleanly. No game scene, full suite, benchmark or shared sky files were changed.

## Reproduce

```powershell
blender --factory-startup -b -t 2 --python tools/generate_horizon_islands.py
```

Use factory startup to avoid unrelated installed Blender add-ons. The generated
`.blend` removes unused factory datablocks and has no external brush references.
Copy `source_art/horizon_islands_v1/project.godot.review` into TEMP as
`project.godot`, alongside review.gd/review.tscn. Keep its suffix inside this
repository. Run that isolated project tiny, muted and offscreen:

```powershell
godot --path $helper --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://review.tscn -- "$checkout/assets/models/horizon_islands_v1" "$checkout/docs/art_mockups/horizon_islands_v1/native" --agent-probe
python tools/review_horizon_islands.py
```

Use actual separate CLI arguments (`--position 10000,10000`,
`--resolution 320x180`, Blender `-t 2`). A90s native-run deadline was used.
Review needs Python3.8+, NumPy and Pillow. To validate ready scenes, copy this
asset directory to the same path under the helper, import headlessly, then run
`validate_wrappers.gd`. Claude should perform the final main-project import when
staging, including generated `.import` and `.uid` metadata per the existing gate.
