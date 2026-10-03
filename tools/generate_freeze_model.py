"""Build a stylized freeze gift crystal with source, GLB, and preview."""

from math import cos, pi, sin
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/freeze_v1"
SOURCE = ROOT / "source_art/freeze_v1"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").write_text("", encoding="utf-8")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=0.62):
    srgb = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in srgb]
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*rgb, 1)
    result.use_nodes = True
    bsdf = result.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    return result


blue = material("Glacial teal", "#75CBD1")
shadow = material("Deep ice", "#407E99")
ice = material("Frost edge", "#C6E5E9", 0.58)
ink = material("Ink socket", "#26323A")
floor_mat = material("Review storm floor", "#435765")
model = bpy.data.collections.new("Freeze export")
bpy.context.scene.collection.children.link(model)


def add(obj, name, mat):
    obj.name = name
    obj.data.materials.append(mat)
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    model.objects.link(obj)
    return obj


def box(name, loc, size, mat, bevel=0.0, export=True):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Broad cut", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if export:
        return add(obj, name, mat)
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def shard(name, position, height, radius, lean, mat):
    sides = 6
    verts = []
    for z, size, xoff in ((0, radius * 0.7, 0), (height * 0.46, radius, lean * 0.45)):
        for side in range(sides):
            angle = 2 * pi * side / sides
            verts.append((size * cos(angle) + xoff, size * sin(angle), z))
    verts.append((lean, 0, height))
    faces = []
    for side in range(sides):
        following = (side + 1) % sides
        faces.append((side, following, sides + following, sides + side))
        faces.append((sides + side, sides + following, sides * 2))
    faces.append(tuple(reversed(range(sides))))
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    model.objects.link(obj)
    obj.location = position
    obj.data.materials.append(mat)
    return obj


box("Freeze / dark lower socket", (0, 0, -0.32), (0.65, 0.65, 0.12), ink, 0.035)
box("Freeze / solid blue core", (0, 0, -0.04), (0.56, 0.56, 0.55), blue, 0.055)
box("Freeze / upper frost facet", (0, 0, 0.235), (0.53, 0.53, 0.055), ice, 0.012)

# An asymmetrical crown and three broad satellites read as ice at a glance.
shard("Freeze / tall rear shard", (0.03, 0.12, 0.17), 0.57, 0.145, 0.045, ice)
shard("Freeze / left shard", (-0.34, 0.05, -0.18), 0.49, 0.125, -0.20, ice)
shard("Freeze / right shard", (0.30, 0.06, -0.20), 0.39, 0.11, 0.17, shadow)
shard("Freeze / front chip", (0.19, -0.29, -0.21), 0.29, 0.08, 0.07, ice)

# An ink snowflake cross is visible when the crystal is small or desaturated.
box("Freeze / vertical mark", (0, -0.296, -0.055), (0.047, 0.018, 0.31), ink, 0.008)
box("Freeze / horizontal mark", (0, -0.299, -0.055), (0.28, 0.018, 0.047), ink, 0.008)

box("Review / floor", (0, 0, -0.45), (200, 200, 0.08), floor_mat, export=False)
bpy.ops.object.camera_add(location=(1.5, -2.4, 1.2))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, 0.1)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.9
bpy.context.scene.camera = camera
for name, pos, power in (("Review / key", (1, -2, 2.1), 245), ("Review / rim", (-1.3, 1.4, 1.8), 145)):
    data = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = pos
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.energy = power
    data.shape = "DISK"
    data.size = 2.8

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "freeze_v1_preview.png")
scene.view_settings.view_transform = "Standard"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "freeze_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = next(iter(model.objects))
bpy.ops.export_scene.gltf(filepath=str(OUT / "freeze_v1.glb"), export_format="GLB", use_selection=True, export_cameras=False, export_lights=False)
bpy.ops.render.render(write_still=True)
print(f"Built {OUT / 'freeze_v1.glb'} and preview")
