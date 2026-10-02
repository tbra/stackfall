"""Build a standalone faceted magnet gift model in Blender 4.5.

Run: blender -b --python tools/generate_magnet_model.py
The U silhouette is a concave filled curve converted to mesh. The GLB
contains only the magnet; floor, camera and lights stay in the .blend source.
"""

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "models" / "magnet_v1"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = ROOT / "source_art" / "magnet_v1"
SOURCE.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def mat(name, hex_rgb, roughness=0.65, metallic=0.0):
    srgb = [int(hex_rgb[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    rgb = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*rgb, 1)
    result.use_nodes = True
    bsdf = result.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return result


ink = mat("Ink edge", "#26323A")
coral = mat("Coral enamel", "#EB6B5C", 0.45)
silver = mat("Warm silver poles", "#D7DEE0", 0.35, 0.45)
teal = mat("Magnetic field teal", "#75CBD1", 0.40)
paper = mat("Review floor", "#D9E6DF")

model = bpy.data.collections.new("Magnet export")
bpy.context.scene.collection.children.link(model)


def move_to_model(obj):
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    model.objects.link(obj)


def u_outline(scale=1.0):
    pts = [(-0.50, 0.55)]
    pts += [(0.50 * math.cos(math.pi + math.pi * i / 10),
             0.05 + 0.50 * math.sin(math.pi + math.pi * i / 10)) for i in range(11)]
    pts += [(0.50, 0.55), (0.27, 0.55)]
    pts += [(0.27 * math.cos(-math.pi * i / 10),
             0.05 + 0.27 * math.sin(-math.pi * i / 10)) for i in range(11)]
    pts += [(-0.27, 0.55)]
    return [(x * scale, z * scale) for x, z in pts]


def u_mesh(name, material, scale, thickness, front_offset):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "2D"
    curve.fill_mode = "BOTH"
    curve.extrude = thickness
    curve.bevel_depth = 0.012 if scale < 1 else 0.025
    curve.bevel_resolution = 1
    points = u_outline(scale)
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, (x, z) in zip(spline.points, points):
        point.co = (x, z, 0.0, 1.0)
    spline.use_cyclic_u = True
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    obj.rotation_euler.x = math.pi / 2
    obj.location.y = front_offset
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    obj.data.materials.append(material)
    move_to_model(obj)
    return obj


u_mesh("Magnet / ink rim and sidewalls", ink, 1.0, 0.15, 0.0)
u_mesh("Magnet / coral enamel face", coral, 0.948, 0.011, -0.165)
# Held gifts turn in hand: the back needs the same enamel or it reads as a black U.
u_mesh("Magnet / coral enamel back", coral, 0.948, 0.011, 0.165)


def box(name, location, dimensions, material, bevel=0.0, export=True):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Faceted edge", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(material)
    if export:
        move_to_model(obj)
    return obj


for sign, label in ((-1, "left"), (1, "right")):
    x = sign * 0.385
    box(f"Magnet / {label} pole tip", (x, 0, 0.54), (0.235, 0.37, 0.19), silver, 0.017)
    for side, y in (("front", -0.193), ("back", 0.193)):
        box(f"Magnet / {label} pole ink seam {side}", (x, y, 0.455), (0.225, 0.025, 0.018), ink, 0.003)


def field_arc():
    curve = bpy.data.curves.new("Field arc", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 1
    curve.bevel_depth = 0.014
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(12)
    for i, point in enumerate(spline.points):
        x = -0.26 + 0.52 * i / 12
        z = 0.33 - 0.14 * (1 - (x / 0.26) ** 2)
        point.co = (x, -0.205, z, 1.0)
    obj = bpy.data.objects.new("Magnet / field arc", curve)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    obj.data.materials.append(teal)
    move_to_model(obj)


field_arc()

# Review environment only.
box("Review / floor", (0, 0, -0.51), (200, 200, 0.09), paper, export=False)
bpy.ops.object.camera_add(location=(1.75, -2.9, 1.25))
camera = bpy.context.object
camera.name = "Review / camera"
camera.rotation_euler = (Vector((0, 0, 0.05)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.72
bpy.context.scene.camera = camera


def light(name, location, energy, size):
    data = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.energy = energy
    data.shape = "DISK"
    data.size = size


light("Review / key", (1.0, -2.0, 2.5), 210, 3.3)
light("Review / rim", (-1.5, 1.2, 1.7), 110, 2.8)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "magnet_v1_preview.png")
scene.view_settings.view_transform = "Standard"

bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "magnet_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = next(iter(model.objects))
bpy.ops.export_scene.gltf(filepath=str(OUT / "magnet_v1.glb"), export_format="GLB", use_selection=True, export_apply=True)
bpy.ops.render.render(write_still=True)
print(f"MAGNET_MODEL_READY {OUT}")
