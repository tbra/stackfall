# Cosmic fog texture candidates

Three transparent 512 × 512 RGBA textures are designed for separate fog planes or particle layers at different depths around the arena. `fog_veil.png` is broad and quiet; `fog_wisps.png` breaks the silhouette; `fog_wisps_offset.png` is the same field shifted by one third of a tile for a second parallax layer. All use pale blue-gray RGB with alpha carrying the density, leaving tint and final opacity to the later map art setup.

The edges wrap exactly and can repeat in both directions. Layers can move at different speeds as the camera moves, but these images are assets only: no fog shader, camera rig, scene, or gameplay wiring is changed. Keep the distant creature mostly obscured so the owner's preferred megalophobia composition remains uncertain.

`tools/generate_cosmic_fog_textures.py` is the deterministic source. `docs/art_mockups/cosmic_fog_texture_preview.png` shows each tile over a dark blue-gray field. Requires NumPy and Pillow to rebuild.
