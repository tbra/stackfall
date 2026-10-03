# Animated propeller gift candidate

`propeller_v1.glb` is an original held-gift art candidate: dark foot, teal spindle, two broad warm-paper blades, coral tips, and a brass rotor cap. The rotor carries a `spin_1s` loop; the rest of the object stays still. The model spans about 1.2 units across and 0.8 units high, pivoted at the spindle center. The GLB contains only model meshes and the animation, not preview camera or lights.

`source_art/propeller_v1/propeller_v1.blend` is editable Blender source under `.gdignore`. `propeller_v1_preview.png` is the neutral 960 × 720 render. Rebuild with Blender 4.5: `blender -b --python tools/generate_propeller_model.py`.

This is a candidate only. `assets/gifts/held/propeller.tscn` remains active. A later scene integration can choose whether to use the GLB loop or the game's own rotor animation; avoid running both at once.
