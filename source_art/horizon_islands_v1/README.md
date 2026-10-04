# Editable horizon island source

Original seeded mesh construction in `tools/generate_horizon_islands.py`.
`horizon_islands_v1.blend` has separate mesa/shelf/crag collections, with full and
two reduced meshes each. Mesh colors use the CelColor corner attribute, exported
asCOLOR_0. BlenderZ-up becomes GodotY-up; all GLB roots stay at the cap center.

The review project is an isolated asset helper. Preserve its `.review` suffix
inside the repository; copy and rename only in TEMP. See the asset README for
commands and limitations. Do not place these helper cloud occluders in gameplay.
