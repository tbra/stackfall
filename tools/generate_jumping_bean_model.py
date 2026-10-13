"""Build the v3 Jumping Bean gift model in Blender 4.5 (Bontago-mp0.158).

Run:  blender -b --python tools/generate_jumping_bean_model.py

Owner playtest 2026-10-13: "I like the face but there is no reason it needs to be a
bean (that is what the original called it)." The gift keeps its id and gameplay name
(jumping_bean); the body is now a squat orange jelly blob sitting on a steel coil
spring, with the v2 face (eyes, glints, cheeks, smile) unchanged.

DECISION (mp0.158): body = squashed jelly blob on a coil spring (readable at held
size, says "jumps" without needing the old bean silhouette). The idle_hop_1p5s clip
keeps its name and 37-frame length: the spring compresses on contact, stretches in
the air, and the blob rides its top.

Outputs: assets/models/jumping_bean_v3/jumping_bean_v3.glb and
source_art/jumping_bean_v3/jumping_bean_v3.blend. Reuses the v2 generator's helpers.
"""

import math
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_gift_models_v2 as g  # noqa: E402

CLIP = "idle_hop_1p5s"
SPRING_BASE_Z = -0.40
SPRING_HEIGHT = 0.2
COILS = 4


def key_clip(obj, frames, clip):
    for frame, loc, scale in frames:
        obj.location = loc
        obj.scale = scale
        obj.keyframe_insert("location", frame=frame)
        obj.keyframe_insert("scale", frame=frame)
    action = obj.animation_data.action
    track = obj.animation_data.nla_tracks.new()
    track.name = clip
    track.strips.new(clip, 1, action)
    obj.animation_data.action = None


def export_v3(collection, model_id: str, animated: bool) -> None:
    out = g.ROOT / f"assets/models/{model_id}_v3"
    source = g.ROOT / f"source_art/{model_id}_v3"
    out.mkdir(parents=True, exist_ok=True)
    source.mkdir(parents=True, exist_ok=True)
    (source / ".gdignore").touch()
    bpy.ops.wm.save_as_mainfile(filepath=str(source / f"{model_id}_v3.blend"), copy=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection.objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(out / f"{model_id}_v3.glb"), export_format="GLB",
                              use_selection=True, export_cameras=False, export_lights=False,
                              export_apply=True, export_animations=animated,
                              export_animation_mode="NLA_TRACKS")
    print(f"Built {out / f'{model_id}_v3.glb'}")


def build() -> None:
    col = g.reset()
    jelly = g.material("Jelly", "#E08A3A")
    belly = g.material("Jelly belly", "#F4B26A")
    steel = g.material("Spring steel", "#8E9AA6")
    white = g.material("Eye white", "#FFFFFF")
    ink = g.material("Pupil", "#1B1A2E")
    mouth = g.material("Mouth", "#7A1E2E")
    blush = g.material("Blush", "#FF8FA3")

    root = g.empty(col, "Jumping root")
    # Spring: a flat steel foot plus stacked coil rings, pivoting at its base.
    spring = g.empty(col, "Spring pivot", (0, 0, SPRING_BASE_Z), parent=root)
    g.cone(col, "Spring foot", steel, (0, 0, 0.015), 0.2, 0.2, 0.03, vertices=18, parent=spring)
    pitch = SPRING_HEIGHT / COILS
    for i in range(COILS):
        g.torus(col, f"Spring coil {i}", steel, (0, 0, 0.05 + pitch * i), 0.115, 0.03, parent=spring)
    # Blob: squat jelly dome with a lighter belly and the v2 face, riding the spring top.
    blob = g.empty(col, "Blob pivot", (0, 0, SPRING_BASE_Z + 0.04 + SPRING_HEIGHT), parent=root)
    g.sphere(col, "Jelly body", jelly, (0, 0, 0.2), 0.33, scale=(1.0, 0.95, 0.82), segments=28, parent=blob)
    g.sphere(col, "Jelly belly", belly, (0, -0.1, 0.09), 0.17, scale=(1.0, 0.6, 0.55), segments=18, parent=blob)
    for side in (-1, 1):
        x = side * 0.095
        g.sphere(col, f"Eye {side}", white, (x, -0.27, 0.27), 0.075, scale=(0.85, 0.45, 1.1), parent=blob)
        g.sphere(col, f"Pupil {side}", ink, (x + 0.012, -0.305, 0.26), 0.04, scale=(0.9, 0.4, 1.1), parent=blob)
        g.sphere(col, f"Glint {side}", white, (x + 0.025, -0.321, 0.285), 0.013, scale=(1, 0.4, 1), parent=blob)
        g.sphere(col, f"Cheek {side}", blush, (side * 0.2, -0.25, 0.17), 0.04, scale=(1.2, 0.35, 0.7), parent=blob)
    g.sphere(col, "Smile", mouth, (0.0, -0.285, 0.155), 0.05, scale=(1.0, 0.35, 0.55), parent=blob)

    # 37 frames at 24 fps: contact squash, tall hop, contact, small hop, contact.
    # (frame, root hop height, spring z scale, blob squash)
    beats = [(1, 0.0, 0.55, 1.1), (8, 0.14, 1.15, 0.94), (19, 0.2, 1.0, 1.0),
             (30, 0.0, 0.55, 1.1), (37, 0.0, 0.55, 1.1)]
    base_top = SPRING_BASE_Z + 0.04 + SPRING_HEIGHT
    key_clip(root, [(f, (0, 0, h), (1, 1, 1)) for f, h, _s, _q in beats], CLIP)
    key_clip(spring, [(f, (0, 0, SPRING_BASE_Z), (1, 1, s)) for f, _h, s, _q in beats], CLIP)
    key_clip(blob, [(f, (0, 0, base_top - (1 - s) * (0.04 + SPRING_HEIGHT)), (1 / math.sqrt(q), 1 / math.sqrt(q), q))
                    for f, _h, s, q in beats], CLIP)
    bpy.context.scene.frame_end = 37
    export_v3(col, "jumping_bean", True)


if __name__ == "__main__":
    build()
