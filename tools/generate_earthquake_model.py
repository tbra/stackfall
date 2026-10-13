"""Generate the shaking miniature play-disc earthquake gift and review render."""

from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/earthquake_v3"
SOURCE = ROOT / "source_art/earthquake_v3"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").touch()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, color):
    values = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in values]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    node = mat.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value = (*rgb, 1)
    node.inputs["Roughness"].default_value = 0.8
    return mat


dark = material("Disc top dark", "#16121C")
dark_side = material("Disc underside", "#2B2433")
gold = material("Disc gold rim", "#FFC65A")
lip = material("Disc rim lip", "#C9921A")
floor_mat = material("Preview blue floor", "#435765")
block_mats = [material("Tiny block coral", "#F35D4C"), material("Tiny block mint", "#59CC66"),
              material("Tiny block sky", "#4FA8E8"), material("Tiny block cream", "#FFF6EA")]
model = bpy.data.collections.new("Earthquake gift export")
bpy.context.scene.collection.children.link(model)

# Bontago-mp0.165 (owner playtest 2026-10-13): "a shaking miniature version of the disc
# instead". A small replica of the play disc: dark top, gold rim and lip like the arena,
# a few tiny blocks on it, all shaken by the quake_pulse_1s loop on one pivot.
R = 0.45
TOP = 0.0
shaker = bpy.data.objects.new("Earthquake / shaker", None)
model.objects.link(shaker)


def link(obj, name, mat):
    obj.name = name
    obj.data.materials.append(mat)
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    model.objects.link(obj)
    obj.parent = shaker
    return obj


bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=R - 0.04, depth=0.1, location=(0, 0, TOP - 0.05))
link(bpy.context.object, "Earthquake / disc top", dark)
bpy.ops.mesh.primitive_cone_add(vertices=40, radius1=R - 0.1, radius2=R - 0.04, depth=0.12, location=(0, 0, TOP - 0.16))
link(bpy.context.object, "Earthquake / disc underside", dark_side)
bpy.ops.mesh.primitive_torus_add(major_radius=R - 0.03, minor_radius=0.045, major_segments=40,
                                 minor_segments=8, location=(0, 0, TOP - 0.005))
link(bpy.context.object, "Earthquake / gold rim", gold)
bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=R, depth=0.05, location=(0, 0, TOP - 0.075))
link(bpy.context.object, "Earthquake / gold lip", lip)

blocks = []
for i, (x, y, size, yaw) in enumerate(((-0.16, 0.08, 0.13, 0.3), (0.08, 0.14, 0.11, -0.4),
                                       (0.14, -0.1, 0.14, 0.15), (-0.1, -0.15, 0.1, -0.2))):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, TOP + size / 2), rotation=(0, 0, yaw))
    cube = bpy.context.object
    cube.scale = (size, size, size)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    blocks.append(link(cube, f"Earthquake / tiny block {i}", block_mats[i]))

# Quake loop: the whole replica judders and rolls, the blocks chatter on top of it.
for frame, (x, y, z, roll, pitch) in zip((1, 5, 9, 13, 17, 21, 25), (
        (0, 0, 0, 0, 0), (0.02, 0.0, 0.01, 0.03, -0.02), (-0.02, 0.012, 0.0, -0.03, 0.02),
        (0.015, -0.015, 0.012, 0.02, 0.03), (-0.018, 0.01, 0.0, -0.025, -0.03),
        (0.012, 0.015, 0.008, 0.02, -0.01), (0, 0, 0, 0, 0))):
    shaker.location = (x, y, z)
    shaker.rotation_euler = (roll, pitch, 0)
    shaker.keyframe_insert(data_path="location", frame=frame)
    shaker.keyframe_insert(data_path="rotation_euler", frame=frame)
for k, cube in enumerate(blocks):
    base = cube.location.z
    for frame, dz in zip((1, 7 + k, 13 + k, 19, 25), (0, 0.035, 0, 0.02, 0)):
        cube.location.z = base + dz
        cube.keyframe_insert(data_path="location", frame=frame, index=2)
    cube.location.z = base
for obj in [shaker] + blocks:
    action = obj.animation_data.action
    track = obj.animation_data.nla_tracks.new()
    track.name = "quake_pulse_1s"
    track.strips.new("quake_pulse_1s", 1, action)
    obj.animation_data.action = None

scene = bpy.context.scene
scene.render.fps = 24
scene.frame_start = 1
scene.frame_end = 25
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.30))
floor = bpy.context.object
floor.name = "Review / floor"
floor.dimensions = (200, 200, 0.08)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(1.5, -2.3, 1.7))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, -0.08)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.55
scene.camera = camera
for name, pos, energy in (("Review / key", (1, -2, 2), 260), ("Review / rim", (-1.3, 1.4, 1.8), 170)):
    lamp = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, lamp)
    scene.collection.objects.link(obj)
    obj.location = pos
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    lamp.energy = energy
    lamp.shape = "DISK"
    lamp.size = 2.8

scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "earthquake_v3_preview.png")
scene.view_settings.view_transform = "Standard"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "earthquake_v3.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = shaker
bpy.ops.export_scene.gltf(filepath=str(OUT / "earthquake_v3.glb"), export_format="GLB",
                          use_selection=True, export_cameras=False, export_lights=False,
                          export_animations=True, export_animation_mode="NLA_TRACKS")
scene.frame_set(1)
bpy.ops.render.render(write_still=True)
print(f"Built {OUT / 'earthquake_v3.glb'} and preview")
