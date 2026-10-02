"""Build an original tabletop gift crate and render a review image in Blender.

Run: blender -b --python tools/generate_gift_crate_model.py
The model's origin is the bottom center; one crate is about one ordinary block.
Only the named Crate objects are exported to GLB. Camera, lights and floor stay
in the editable .blend source for repeatable visual review.
"""

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "models" / "gift_crate_v1"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = ROOT / "source_art" / "gift_crate_v1"
SOURCE.mkdir(parents=True, exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, hex_rgb, roughness=0.72, metallic=0.0):
    srgb = tuple(int(hex_rgb[i:i + 2], 16) / 255 for i in (1, 3, 5))
    # Blender node inputs are scene-linear; our art tokens are sRGB hex.
    rgb = tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb)
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


ink = material("Ink edge", "#26323A")
paper = material("Warm ceramic panel", "#F5EBD6")
coral = material("Coral enamel", "#EB6B5C", 0.48)
brass = material("Brass ribbon", "#E8B85D", 0.38, 0.35)
teal = material("Sky teal seal", "#75CBD1", 0.40)

crate = bpy.data.collections.new("Crate export")
bpy.context.scene.collection.children.link(crate)


def box(name, location, dimensions, mat, bevel=0.0, export=True):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Broad cel edge", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(mat)
    if export:
        for collection in list(obj.users_collection):
            collection.objects.unlink(obj)
        crate.objects.link(obj)
    return obj


# Dark lower chassis, inset paper faces and coral framing. Every face has a
# broad material region; no texture noise or tiny baked lettering is needed.
box("Crate / shadow plinth", (0, 0, 0.10), (1.05, 1.05, 0.20), ink, 0.035)
box("Crate / warm body", (0, 0, 0.52), (0.91, 0.91, 0.68), paper, 0.035)
for x in (-0.47, 0.47):
    for y in (-0.47, 0.47):
        box(f"Crate / corner post {x:+.2f} {y:+.2f}", (x, y, 0.53), (0.11, 0.11, 0.71), coral, 0.012)
box("Crate / lid dark lip", (0, 0, 0.92), (1.11, 1.11, 0.16), ink, 0.032)
box("Crate / lid coral", (0, 0, 1.00), (1.07, 1.07, 0.13), coral, 0.03)
box("Crate / lid brass cross east-west", (0, 0, 1.074), (1.04, 0.12, 0.035), brass, 0.01)
box("Crate / lid brass cross north-south", (0, 0, 1.075), (0.12, 1.04, 0.035), brass, 0.01)
box("Crate / front ribbon", (0, -0.482, 0.52), (0.13, 0.035, 0.61), brass, 0.006)
box("Crate / right ribbon", (0.482, 0, 0.52), (0.035, 0.13, 0.61), brass, 0.006)

# A clear front seal reads from normal camera distance and distinguishes the
# crate from a plain stackable block. Its teal center is visible in grayscale
# through the surrounding ink and bright brass.
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.205, depth=0.052, location=(0, -0.54, 0.62), rotation=(math.pi / 2, 0, 0))
seal = bpy.context.object
seal.name = "Crate / twelve sided seal"
seal.data.materials.append(ink)
for collection in list(seal.users_collection):
    collection.objects.unlink(seal)
crate.objects.link(seal)
gem = box("Crate / teal lozenge", (0, -0.576, 0.62), (0.235, 0.045, 0.235), teal, 0.012)
gem.rotation_euler.y = math.pi / 4
box("Crate / seal glint", (-0.035, -0.603, 0.68), (0.06, 0.013, 0.02), paper, 0.003)

# Review environment only.
ground = material("Review floor", "#D9E6DF")
box("Review / floor", (0, 0, -0.09), (200, 200, 0.15), ground, export=False)
bpy.ops.object.camera_add(location=(2.35, -3.0, 2.1))
camera = bpy.context.object
camera.name = "Review / camera"
direction = Vector((0, 0, 0.55)) - camera.location
camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 2.45
bpy.context.scene.camera = camera

def area(name, location, power, size):
    data = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, 0.55)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.energy = power
    data.shape = "DISK"
    data.size = size


area("Review / key", (1.2, -2.0, 3.0), 220, 4.0)
area("Review / rim", (-2.2, 0.9, 2.2), 120, 3.0)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "gift_crate_v1_preview.png")
scene.world.color = (0.46, 0.64, 0.68)
scene.view_settings.view_transform = "Standard"

bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "gift_crate_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in crate.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = next(iter(crate.objects))
bpy.ops.export_scene.gltf(filepath=str(OUT / "gift_crate_v1.glb"), export_format="GLB", use_selection=True, export_apply=True)
bpy.ops.render.render(write_still=True)
print(f"GIFT_CRATE_MODEL_READY {OUT}")
