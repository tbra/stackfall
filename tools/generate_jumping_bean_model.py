"""Build an original hopping bean gift model and GLB idle loop."""

from math import cos, pi, sin
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/jumping_bean_v1"
SOURCE = ROOT / "source_art/jumping_bean_v1"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").write_text("", encoding="utf-8")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, color):
    srgb = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in srgb]
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = 0.73
    return m


mint = material("Mint shell", "#75CBD1")
mint_shadow = material("Mint underside", "#3A9B91")
ink = material("Ink face", "#26323A")
coral = material("Coral cheek", "#EB6B5C")
floor_mat = material("Review floor", "#DCE5DF")
model = bpy.data.collections.new("Jumping bean export")
bpy.context.scene.collection.children.link(model)
root = bpy.data.objects.new("Bean / idle-hop root", None)
model.objects.link(root)


def add(obj, name, mat):
    obj.name = name
    obj.data.materials.append(mat)
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    model.objects.link(obj)
    obj.parent = root
    return obj


def sphere(name, center, scale, mat, segments=12, rings=7):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1)
    obj = bpy.context.object
    obj.location = center
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return add(obj, name, mat)


# Curved cross-sections form a low kidney shape instead of a pointed droplet.
rings = 11
sides = 12
vertices = []
faces = []
for i in range(rings):
    t = i / (rings - 1)
    x = -0.33 + 0.66 * t
    z_center = 0.11 * (2 * t - 1) ** 2 - 0.035
    y_radius = 0.115 + 0.10 * sin(pi * t)
    z_radius = 0.12 + 0.075 * sin(pi * t)
    for j in range(sides):
        angle = j * 2 * pi / sides
        vertices.append((x, y_radius * cos(angle), z_center + z_radius * sin(angle)))
for i in range(rings - 1):
    for j in range(sides):
        next_j = (j + 1) % sides
        faces.append((i * sides + j, i * sides + next_j, (i + 1) * sides + next_j, (i + 1) * sides + j))
faces.extend([tuple(reversed(range(sides))), tuple((rings - 1) * sides + j for j in range(sides))])
data = bpy.data.meshes.new("Curved bean body")
data.from_pydata(vertices, [], faces)
data.materials.append(mint)
data.materials.append(mint_shadow)
data.update()
for polygon in data.polygons:
    if polygon.index % 7 == 0:
        polygon.material_index = 1
body = bpy.data.objects.new("Bean / faceted curved body", data)
model.objects.link(body)
body.parent = root

# Raised facial marks are broad enough to survive a tiny gift preview.
sphere("Bean / left eye", (-0.10, -0.207, 0.035), (0.024, 0.017, 0.031), ink)
sphere("Bean / right eye", (0.10, -0.207, 0.035), (0.024, 0.017, 0.031), ink)
sphere("Bean / small smile", (0, -0.212, -0.066), (0.073, 0.013, 0.018), ink)
sphere("Bean / coral cheek", (-0.205, -0.178, -0.035), (0.038, 0.014, 0.027), coral)

# Contact, tall hop, contact, little follow-up, contact: 1.5-second loop.
for frame, height, angle, squash in (
    (1, 0, -0.07, 0.94),
    (10, 0.24, 0.10, 1.06),
    (19, 0, -0.05, 0.91),
    (28, 0.09, 0.04, 1.02),
    (37, 0, -0.07, 0.94),
):
    root.location = (0, 0, height)
    root.rotation_euler = (0, angle, 0)
    root.scale = (1 / squash, 1 / squash, squash)
    root.keyframe_insert(data_path="location", frame=frame)
    root.keyframe_insert(data_path="rotation_euler", frame=frame)
    root.keyframe_insert(data_path="scale", frame=frame)
action = root.animation_data.action
track = root.animation_data.nla_tracks.new()
track.name = "idle_hop_1p5s"
track.strips.new("idle_hop_1p5s", 1, action)
root.animation_data.action = None

scene = bpy.context.scene
scene.render.fps = 24
scene.frame_start = 1
scene.frame_end = 37
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.39))
floor = bpy.context.object
floor.name = "Review / floor"
floor.dimensions = (200, 200, 0.08)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(1.4, -2.1, 1.05))
camera = bpy.context.object
camera.rotation_euler = (Vector((0.05, 0, 0.015)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.75
bpy.context.scene.camera = camera
for name, pos, power in (("Review / key", (1, -2, 1.9), 240), ("Review / rim", (-1.3, 1.2, 1.6), 140)):
    lamp = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, lamp)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = pos
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    lamp.energy = power
    lamp.shape = "DISK"
    lamp.size = 2.6

scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "jumping_bean_v1_preview.png")
scene.view_settings.view_transform = "Standard"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "jumping_bean_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(filepath=str(OUT / "jumping_bean_v1.glb"), export_format="GLB", use_selection=True, export_cameras=False, export_lights=False, export_animations=True, export_animation_mode="NLA_TRACKS")
scene.frame_set(10)
bpy.ops.render.render(write_still=True)
print(f"Built animated {OUT / 'jumping_bean_v1.glb'} and preview")
