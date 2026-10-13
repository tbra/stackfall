"""Build the v3 Volcano gift model in Blender 4.5 (Bontago-mp0.163).

Run:  blender -b --python tools/generate_volcano_model.py

Owner playtest 2026-10-13: "animated smoke, and update the big volcano that spawns to
match the handheld model." The v2 cone/crater/lava-flow silhouette is kept; the static
smoke balls become four puffs ("Smoke N") that rise out of the crater, swell and fade
to nothing on the looping smoke_rise_2s clip. The same GLB is the big spawned volcano's
model (assets/models/volcano_v3 via config/specials/volcano.tres; VolcanoStructure
ignores "Smoke*" nodes when fitting its footprint so the gameplay size is unchanged).

DECISION (mp0.163): puffs shrink to zero at both ends of their life (scale-in/out)
instead of using alpha, so the toon/outline materials need no transparency. Four puffs
start 2 steps (8 frames) apart, live 6 steps and are all hidden on frame 1 and the
last frame, so the loop wraps exactly and the rest pose (frame 1) is the bare cone.

Outputs: assets/models/volcano_v3/volcano_v3.glb and
source_art/volcano_v3/volcano_v3.blend. Reuses the v2 generator's helpers.
"""

import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_gift_models_v2 as g  # noqa: E402

CLIP = "smoke_rise_2s"
LOOP_FRAMES = 48
STEP_FRAMES = 4
PUFF_RISE = 0.34
PUFF_LIFE_STEPS = 6
PUFFS = (  # (crater offset x, y, base z, radius, start step)
    ((0.03, 0.0, 0.25), 0.095, 0),
    ((-0.05, 0.03, 0.25), 0.08, 2),
    ((0.05, -0.04, 0.25), 0.088, 4),
    ((-0.02, -0.03, 0.25), 0.075, 6),
)


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


def animate_puff(obj, base: tuple, phase: int) -> None:
    steps = LOOP_FRAMES // STEP_FRAMES
    for k in range(steps + 1):
        u = (k - phase) / PUFF_LIFE_STEPS
        alive = 0.0 < u < 1.0
        u = min(max(u, 0.0), 1.0)
        swell = math.sin(math.pi * u) ** 0.7
        obj.location = (base[0] + 0.05 * u, base[1], base[2] + PUFF_RISE * u)
        obj.scale = (0.2 + swell,) * 3 if alive else (0.001,) * 3
        obj.keyframe_insert("location", frame=1 + k * STEP_FRAMES)
        obj.keyframe_insert("scale", frame=1 + k * STEP_FRAMES)
    action = obj.animation_data.action
    for fcurve in action.fcurves:
        for key in fcurve.keyframe_points:
            key.interpolation = "LINEAR"
    track = obj.animation_data.nla_tracks.new()
    track.name = CLIP
    track.strips.new(CLIP, 1, action)
    obj.animation_data.action = None
    # Rest pose (before the clip plays): a hidden speck in the crater, so the static
    # bounds stay the cone's and the cell-fit budget holds.
    obj.location = base
    obj.scale = (0.001, 0.001, 0.001)


def build() -> None:
    col = g.reset()
    rock_mat = g.material("Volcano rock", "#5E4438")
    dark_rock = g.material("Volcano base", "#4A3A33")
    lava = g.material("Lava", "#FF6A1A", emission=1.2)
    hot = g.material("Lava hot", "#FFD34A", emission=1.5)
    smoke = g.material("Smoke", "#EDE6F2")
    body = g.cone(col, "Cone", rock_mat, (0, 0, -0.08), 0.46, 0.17, 0.62, vertices=10, smooth=False)
    rng = random.Random(9)
    for vert in body.data.vertices:
        if vert.co.z < 0.25:
            vert.co.x *= rng.uniform(0.92, 1.06)
            vert.co.y *= rng.uniform(0.92, 1.06)
    g.cone(col, "Base rocks", dark_rock, (0, 0, -0.42), 0.5, 0.44, 0.08, vertices=10, smooth=False)
    g.cone(col, "Crater lava", lava, (0, 0, 0.215), 0.15, 0.15, 0.04, vertices=16)
    g.sphere(col, "Lava bubble", hot, (0.04, -0.02, 0.24), 0.05, scale=(1, 1, 0.7), segments=14)
    for i, (angle, length) in enumerate(((-1.9, 0.42), (-0.9, 0.34), (2.3, 0.3))):
        direction = Vector((math.cos(angle), math.sin(angle), 0))
        top = direction * 0.15 + Vector((0, 0, 0.2))
        bottom = direction * (0.15 + length * 0.42) + Vector((0, 0, 0.2 - length))
        g.capsule(col, f"Lava flow {i}", lava, tuple(top), tuple(bottom), 0.035)
    for i, (base, radius, phase) in enumerate(PUFFS):
        puff = g.sphere(col, f"Smoke {i}", smoke, base, radius, segments=16)
        animate_puff(puff, base, phase)
    bpy.context.scene.frame_end = LOOP_FRAMES + 1
    export_v3(col, "volcano", True)


if __name__ == "__main__":
    build()
