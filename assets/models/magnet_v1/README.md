# Faceted magnet gift study

Original U-shaped magnet asset for a future held-gift visual. `tools/generate_magnet_model.py` creates the editable Blender 4.5 source at `source_art/magnet_v1/magnet_v1.blend`, a GLB export containing only the magnet, and a neutral preview PNG. The source folder has `.gdignore` so Godot imports the GLB without needing its Blender importer. No external meshes, textures or samples are used.

The model is about one block wide and one block tall, centered at the held-object origin. A dark edge surrounds a coral enamel face, with warm silver pole caps and a separate thin teal field arc. The arc is a distinct mesh so an integrator can omit it if the live effect should own magnetic energy. The silhouette reads as a magnet without the arc. The live `assets/gifts/held/magnet.tscn` remains unchanged.

Review the model at the normal held-gift scale and against bright sky and dark storm before considering a replacement. Check the GLB orientation in Godot; no gameplay collision or activation behavior is included in this art asset.

Review (Claude, 2026-10-02, Bontago-mp0.43/45 batch): the back now carries the same coral enamel and pole seams as the front; the first export showed a solid ink U from behind, which a held, turning gift would expose.
