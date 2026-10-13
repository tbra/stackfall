"""Build the paintball gift (Bontago-mp0.160) in Blender 4.5: a Y-slingshot with its band
stretched back, cradling a blob of paint, plus a baked 'fire_500ms' clip (band snaps forward,
blob leaves).

Run:  blender -b --python tools/generate_paintball_model.py

Owner playtest 2026-10-13: "a stretched slingshot loaded with a colour blob that fires the blob
when the gift is activated". The static pose of the GLB is the loaded one; the clip is played
once by game/BlockFactory.gd when the gift is released (GiftModelEntry.activate_animation).
Blender Z up, front facing -Y (glTF +Z). Flat colours only (the toon shader shades them).

Outputs: assets/models/paintball_v3/paintball_v3.glb and source_art/paintball_v3/paintball_v3.blend.
"""

import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import generate_gift_models_v2 as base  # noqa: E402  (helpers only; its main is guarded)

CLIP = "fire_500ms"
FRAME_END = 13
FRAME_Y = -0.12          # the slingshot frame's plane (Y = front/back)
TIP_Z = 0.30
TIP_X = 0.20
POUCH_REST_Y = 0.40      # loaded: pulled back
BLOB_IN_POUCH = 0.02     # blob centre ahead of the leather, in the cradle

col = base.reset()
wood = base.material("Slingshot wood", "#B5773F")
rubber = base.material("Band rubber", "#2E2A33")
leather = base.material("Pouch leather", "#7A4A2A")
paint = base.material("Paint blob", "#FF3EA5")
drip = base.material("Paint drip", "#FFD23F")

# --- Frame: handle + two fork arms (a Y) ---------------------------------------------
base.capsule(col, "Handle", wood, (0, FRAME_Y, -0.42), (0, FRAME_Y, -0.04), 0.075)
for side, sign in (("L", -1), ("R", 1)):
    base.capsule(col, f"Fork {side}", wood, (sign * 0.03, FRAME_Y, -0.06), (sign * TIP_X, FRAME_Y, TIP_Z), 0.058)
    base.sphere(col, f"Fork tip {side}", wood, (sign * TIP_X, FRAME_Y, TIP_Z + 0.015), 0.078, segments=14)

# --- Animated parts ------------------------------------------------------------------
pouch = base.empty(col, "Pouch pivot", (0, POUCH_REST_Y, TIP_Z))
base.sphere(col, "Pouch leather", leather, (0, 0, 0), 0.15, scale=(1.0, 0.2, 1.0), segments=16, parent=pouch)

blob = base.empty(col, "Blob pivot", (0, POUCH_REST_Y + BLOB_IN_POUCH, TIP_Z))
base.sphere(col, "Blob body", paint, (0, 0, 0), 0.115, segments=18, parent=blob)
base.sphere(col, "Blob crown", paint, (0, -0.02, 0.1), 0.06, segments=12, parent=blob)
base.sphere(col, "Blob drip", drip, (0, 0.0, -0.12), 0.045, segments=12, parent=blob)

bands = []
for side, sign in (("L", -1), ("R", 1)):
    pivot = base.empty(col, f"Band pivot {side}", (sign * TIP_X, FRAME_Y, TIP_Z + 0.015))
    pivot.rotation_mode = "XYZ"
    base.cone(col, f"Band {side}", rubber, (0, 0, 0.5), 0.036, 0.036, 1.0, vertices=8, parent=pivot)
    bands.append((pivot, sign))


def pose_bands(pouch_y: float, key_frame=None) -> None:
    """Aim each band pivot from its fork tip at the pouch edge and stretch it to meet it."""
    for pivot, sign in bands:
        delta = Vector((sign * 0.09, pouch_y, TIP_Z)) - pivot.location
        pivot.rotation_euler = delta.to_track_quat("Z", "Y").to_euler()
        pivot.scale = (1.0, 1.0, max(delta.length, 0.02))
        if key_frame is not None:
            pivot.keyframe_insert(data_path="rotation_euler", frame=key_frame)
            pivot.keyframe_insert(data_path="scale", frame=key_frame)


# (frame, pouch_y, blob_y, blob_scale): released at 4, overshoots forward, settles.
KEYS = (
    (1, POUCH_REST_Y, POUCH_REST_Y + BLOB_IN_POUCH, 1.0),
    (4, -0.10, -0.10, 1.0),
    (7, 0.02, -0.75, 0.6),
    (10, -0.06, -1.1, 0.25),
    (FRAME_END, -0.03, -1.3, 0.01),
)
for frame, pouch_y, blob_y, blob_scale in KEYS:
    pouch.location.y = pouch_y
    pouch.keyframe_insert(data_path="location", frame=frame)
    blob.location.y = blob_y
    blob.scale = (blob_scale,) * 3
    blob.keyframe_insert(data_path="location", frame=frame)
    blob.keyframe_insert(data_path="scale", frame=frame)
    pose_bands(pouch_y, frame)

for obj in [pouch, blob] + [pivot for pivot, _sign in bands]:
    action = obj.animation_data.action
    for fcurve in action.fcurves:
        for key in fcurve.keyframe_points:
            key.interpolation = "LINEAR"
    track = obj.animation_data.nla_tracks.new()
    track.name = CLIP
    track.strips.new(CLIP, 1, action)
    obj.animation_data.action = None

# The exported node transforms are the static pose: the loaded slingshot (frame 1 values).
pouch.location.y = POUCH_REST_Y
blob.location.y = POUCH_REST_Y + BLOB_IN_POUCH
blob.scale = (1.0, 1.0, 1.0)
pose_bands(POUCH_REST_Y)

scene = bpy.context.scene
scene.render.fps = base.FPS
scene.frame_start = 1
scene.frame_end = FRAME_END

out = ROOT / "assets/models/paintball_v3"
source = ROOT / "source_art/paintball_v3"
out.mkdir(parents=True, exist_ok=True)
source.mkdir(parents=True, exist_ok=True)
(source / ".gdignore").touch()
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(source / "paintball_v3.blend"), copy=True)
bpy.ops.object.select_all(action="DESELECT")
for obj in col.objects:
    obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(out / "paintball_v3.glb"), export_format="GLB",
                          use_selection=True, export_cameras=False, export_lights=False,
                          export_apply=True, export_animations=True,
                          export_animation_mode="NLA_TRACKS")
print(f"Built {out / 'paintball_v3.glb'}")
