# Opening gift crate candidate

`gift_crate_reveal_v1.glb` is an optional animated version of the static tabletop crate. The warm paper, coral frame, brass ribbon and teal seal are retained. The body now has four walls and a dark interior floor. The lid opens around a rear hinge, briefly overshoots, then rests at 110 degrees open.

The closed bounds match the original: 1.11 units wide, about 1.165 deep including the projecting seal, and 1.093 high. The root remains at the bottom center. This export has two mesh groups (body and articulated lid), five shared materials and 836 triangles. It has no review camera, lights, floor or external textures.

`open_reveal_1s` is a one-shot clip; hold its final pose, rather than looping it. Blender's export places samples from 0.041667 to 1.041667 seconds, a one-second motion span. `opening_review.gif` adds pauses at the endpoints and resets to the closed state for inspection. That preview reset is not a closing animation. `opening_contact_sheet.png` shows four poses.

Editable source: `source_art/gift_crate_reveal_v1/gift_crate_reveal_v1.blend`. `.gdignore` keeps the art source out of game imports. Rebuild with Blender 4.5 and Pillow:

```text
blender --factory-startup -b --python tools/build_gift_crate_reveal.py -- --source source_art/gift_crate_v1/gift_crate_v1.blend
python tools/build_gift_crate_reveal.py --assemble
python tools/build_gift_crate_reveal.py --verify
```

The original source is read without editing it. Temporary frames go to the system temp directory `codex_gift_crate_reveal`. `geometry_review.json` records bounds, hinge and playback intent; `glb_review.json` checks the exported meshes, palette count, quaternion normalization, lid rotation, timeline and GIF decoding.

This package is an art candidate. Godot import, apparent size beside blocks, animation playback, any gift reveal timing and owner appearance acceptance remain for Claude review. There are no colliders or game scene changes, and this does not replace the existing carrier automatically.
