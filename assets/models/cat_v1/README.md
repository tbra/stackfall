# Animated faceted cat gift candidate

`cat_v1.glb` is an original, block-sized sitting cat with a violet head/body, tall ears, brass eyes, coral nose, pale chest, visible paws, and a curved tail. The `tail_sway_2s` loop moves only the tail; the cat stays seated. The model is about 0.8 units wide including the tail and 0.9 units high, with a center pivot. The GLB contains only model meshes and the animation.

`source_art/cat_v1/cat_v1.blend` is editable Blender source under `.gdignore`. `cat_v1_preview.png` is a storm-floor 960 × 720 review render. Rebuild with Blender 4.5: `blender -b --python tools/generate_cat_model.py`.

This is an art candidate. `assets/gifts/held/cat.tscn` remains active; no scene or gameplay logic is changed. A later scene integration can choose whether to use the GLB tail loop.
