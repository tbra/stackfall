"""Build an animated, faceted sitting cat gift model in Blender 4.5."""

from math import cos, pi, sin
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/cat_v1"
SOURCE = ROOT / "source_art/cat_v1"
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
    bsdf.inputs["Roughness"].default_value = 0.75
    return m


violet = material("Playful violet fur", "#9E6DD9")
violet_dark = material("Violet underside", "#66528A")
brass = material("Brass eyes", "#E8B85D")
ink = material("Ink pupils", "#26323A")
coral = material("Coral nose and ears", "#EB6B5C")
paper = material("Warm chest patch", "#F5EBD6")
floor_mat = material("Review storm floor", "#435765")
model = bpy.data.collections.new("Cat export")
bpy.context.scene.collection.children.link(model)


def add(obj, name, mat, parent=None):
    obj.name = name
    obj.data.materials.append(mat)
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    model.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def sphere(name, center, scale, mat, segments=12, rings=7):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=center)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return add(obj, name, mat)


def ear(name, side, mat, inner=False):
    center = side * 0.165
    width = 0.085 if inner else 0.128
    z_base = 0.285 if inner else 0.27
    z_tip = 0.495 if inner else 0.54
    y_front = -0.217 if inner else -0.15
    depth = 0.012 if inner else 0.09
    vertices = [
        (center - width, y_front, z_base), (center + width, y_front, z_base),
        (center, y_front, z_tip),
        (center - width, y_front + depth, z_base), (center + width, y_front + depth, z_base),
        (center, y_front + depth, z_tip),
    ]
    faces = [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    model.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


sphere("Cat / sitting body", (0, 0.04, -0.19), (0.225, 0.205, 0.27), violet_dark)
sphere("Cat / wide head", (0, -0.035, 0.145), (0.275, 0.23, 0.195), violet)
ear("Cat / left ear", -1, violet)
ear("Cat / right ear", 1, violet)
ear("Cat / left inner ear", -1, coral, inner=True)
ear("Cat / right inner ear", 1, coral, inner=True)
sphere("Cat / chest patch", (0, -0.167, -0.135), (0.115, 0.053, 0.16), paper)
for side in (-1, 1):
    sphere(f"Cat / paw {side}", (side * 0.12, -0.12, -0.365), (0.105, 0.105, 0.058), violet)
    sphere(f"Cat / brass eye {side}", (side * 0.105, -0.254, 0.17), (0.044, 0.020, 0.043), brass)
    sphere(f"Cat / dark pupil {side}", (side * 0.105, -0.273, 0.17), (0.015, 0.012, 0.027), ink)
sphere("Cat / coral nose", (0, -0.269, 0.07), (0.034, 0.017, 0.025), coral)

# One tapered curved tail stays visible from the front and oblique sides.
tail_pivot = bpy.data.objects.new("Cat / animated tail pivot", None)
model.objects.link(tail_pivot)
tail_pivot.location = (0.19, 0.12, -0.27)
rings, sides = 12, 8
vertices = []
faces = []
for i in range(rings):
    t = i / (rings - 1)
    x = 0.40 * t
    y = 0.08 * sin(pi * t)
    z = 0.42 * t + 0.09 * sin(pi * t)
    radius = 0.073 * (1 - t) + 0.028 * t
    for j in range(sides):
        angle = 2 * pi * j / sides
        vertices.append((x, y + radius * cos(angle), z + radius * sin(angle)))
for i in range(rings - 1):
    for j in range(sides):
        nxt = (j + 1) % sides
        faces.append((i * sides + j, i * sides + nxt, (i + 1) * sides + nxt, (i + 1) * sides + j))
faces.extend([tuple(reversed(range(sides))), tuple((rings - 1) * sides + j for j in range(sides))])
tail_mesh = bpy.data.meshes.new("Curved tail")
tail_mesh.from_pydata(vertices, [], faces)
tail_mesh.update()
tail = bpy.data.objects.new("Cat / curved tail", tail_mesh)
model.objects.link(tail)
tail.parent = tail_pivot
tail.data.materials.append(violet)

for frame, angle in ((1, -0.12), (13, 0.17), (25, -0.12), (37, -0.28), (49, -0.12)):
    tail_pivot.rotation_euler.z = angle
    tail_pivot.keyframe_insert(data_path="rotation_euler", frame=frame)
action = tail_pivot.animation_data.action
track = tail_pivot.animation_data.nla_tracks.new()
track.name = "tail_sway_2s"
track.strips.new("tail_sway_2s", 1, action)
tail_pivot.animation_data.action = None

scene = bpy.context.scene
scene.render.fps = 24
scene.frame_start = 1
scene.frame_end = 49
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.47))
floor = bpy.context.object
floor.name = "Review / floor"
floor.dimensions = (200, 200, 0.08)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(1.5, -2.4, 1.35))
camera = bpy.context.object
camera.rotation_euler = (Vector((0.05, 0, 0.06)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.67
bpy.context.scene.camera = camera
for name, pos, power in (("Review / key", (1, -2, 2), 245), ("Review / rim", (-1.3, 1.4, 1.8), 150)):
    lamp = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, lamp)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = pos
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    lamp.energy = power
    lamp.shape = "DISK"
    lamp.size = 2.8

scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "cat_v1_preview.png")
scene.view_settings.view_transform = "Standard"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "cat_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = tail_pivot
bpy.ops.export_scene.gltf(filepath=str(OUT / "cat_v1.glb"), export_format="GLB", use_selection=True, export_cameras=False, export_lights=False, export_animations=True, export_animation_mode="NLA_TRACKS")
scene.frame_set(1)
bpy.ops.render.render(write_still=True)
print(f"Built animated {OUT / 'cat_v1.glb'} and preview")
