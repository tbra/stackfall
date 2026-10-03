# Animated jumping bean gift candidate

`jumping_bean_v1.glb` is an original, block-sized, faceted curved bean with a minimal face. Its `idle_hop_1p5s` loop includes a tall hop, short follow-up, slight roll, and contact squash. The model is roughly 0.7 units wide and 0.5 units high, with a center pivot. The GLB contains only model meshes and one coordinated animation.

`source_art/jumping_bean_v1/jumping_bean_v1.blend` is editable Blender source under `.gdignore`. `jumping_bean_v1_preview.png` shows the hop apex at 960 × 720. Rebuild with Blender 4.5: `blender -b --python tools/generate_jumping_bean_model.py`.

This is an art candidate. `assets/gifts/held/jumping_bean.tscn` remains active. A later scene integration should use either the GLB idle-hop or existing scene motion, avoiding two overlapping hops.
