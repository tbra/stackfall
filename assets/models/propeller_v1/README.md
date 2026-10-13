# Animated propeller gift candidate

`propeller_v1.glb` is a caged five-blade desk fan (Bontago-mp0.161; formerly an aircraft-style two-blade propeller): dark foot, teal neck and guard cage, five pitched warm-paper blades on a brass hub. The blade rotor carries a `spin_1s` loop about the facing (Y) axis; the rest stays still. The model fits one cell, pivoted at the hub.

`source_art/propeller_v1/propeller_v1.blend` is editable Blender source under `.gdignore`. `propeller_v1_preview.png` is the neutral 960 × 720 render. Rebuild with Blender 4.5: `blender -b --python tools/generate_propeller_model.py`.

This is a candidate only. `assets/gifts/held/propeller.tscn` remains active. A later scene integration can choose whether to use the GLB loop or the game's own rotor animation; avoid running both at once.
