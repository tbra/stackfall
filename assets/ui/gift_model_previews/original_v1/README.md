# Original gift model preview candidates

Seven transparent 384×384 PNGs rendered from the imported `*_v1.glb` gift models at frame 1, with a shared orthographic camera, lighting and 80% framing target. The models themselves determine the silhouettes and colors. The contact sheet includes a dark backdrop and a light inset to inspect edge transparency.

Rebuild with Blender 4.5: `blender -b --python tools/render_original_gift_model_icons.py`. Build the sheet with system Python and Pillow: `python tools/render_original_gift_model_icons.py --sheet`.

These are UI art candidates. The live `assets/ui/gift_previews` folder and held-gift scenes remain separately reviewed assets. Use these previews when the corresponding model becomes the held representation, so the HUD and held gift agree. Blender shading differs from the game's toon material; Claude should compare the pack at the HUD's displayed size before adopting it or use it as framing guidance for a Godot render.
