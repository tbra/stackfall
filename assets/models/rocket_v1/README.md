# Faceted rocket gift model study

Standalone model candidate following the silhouette and cream/coral/blue palette of `assets/ui/gift_previews/rocket.png`. The mesh is roughly one block tall, with a visual-center origin for held-gift rotation. Four broad fins preserve the silhouette at multiple angles. The small porthole provides an orientation cue.

- Editable source: `source_art/rocket_v1/rocket_v1.blend` (`.gdignore` keeps Blender out of Godot's import scan).
- Game-ready candidate: `rocket_v1.glb`, model meshes only.
- Neutral render: `rocket_v1_preview.png`, with review camera, lighting, and floor excluded from GLB.
- Regenerate: `blender -b --python tools/generate_rocket_model.py` with Blender 4.5.

Original procedural art by Codex, 2026-10-02. This is an asset candidate. Review apparent scale, pivot, and orientation beside the live held gift before integration. No game scene or behavior has been changed.
