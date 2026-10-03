# Fog colossus: animated 3D background art candidate

This is a camera-independent 3D interpretation of the owner's preferred first fog/megalophobia concept (`Bontago-mp0.59`). The broad, faceted body and eight differently placed tendrils have no face or focal eye. The GLB contains a 12-second looping `drift_and_sway_12s` animation: slow root movement plus separate limb sway. Front and oblique side previews show the depth needed for a camera that moves around the arena.

Files:

- `fog_colossus_v1.glb`: Godot-ready animated model candidate.
- `fog_colossus_v1_front.png`, `fog_colossus_v1_side.png`: neutral inspection renders. These do not simulate final scene fog.
- `source_art/fog_colossus_v1/fog_colossus_v1.blend`: editable Blender source under `.gdignore`.
- `tools/generate_fog_colossus.py`: deterministic geometry, animation, export, and preview source. Run with Blender 4.5: `blender -b --python tools/generate_fog_colossus.py`.

The model uses normalized art units (roughly 11 wide × 11 tall). A later map scene must position and scale it far beyond the arena, add distance fog, and decide how its own movement combines with the asset's loop. Keep much of the body outside the camera frame so the scale remains uncertain. This package does not change the map scene, camera, shaders, or gameplay.
