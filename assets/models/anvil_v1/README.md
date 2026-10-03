# Faceted anvil gift candidate

`anvil_v1.glb` is a standalone, low-poly held-gift art candidate. The body, tapered horn, broad foot, and pale strike face carry the silhouette; a small brass mark ties it to the Stackfall gift palette. The pivot is near the visual center. Its horn extends the total width to about 1.5 block units, so check held-gift clearance before any scene swap. The GLB contains only model meshes, with no camera, lights, or review floor.

`source_art/anvil_v1/anvil_v1.blend` is the editable Blender source (`.gdignore` keeps it out of Godot import). `anvil_v1_preview.png` shows the model under neutral lighting. Rebuild with Blender 4.5: `blender -b --python tools/generate_anvil_model.py`.

The existing `assets/gifts/held/anvil.tscn` stays active. This candidate is for art review and a later scene swap if accepted; no gameplay or scene wiring is changed here.
