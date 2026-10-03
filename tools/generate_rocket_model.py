"""Build a standalone, faceted rocket gift study in Blender 4.5.

Run: blender -b --python tools/generate_rocket_model.py
The GLB contains model meshes only; camera, lights, and floor stay in .blend.
"""

from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "models" / "rocket_v1"
SOURCE = ROOT / "source_art" / "rocket_v1"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").write_text("", encoding="utf-8")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def mat(name, hex_rgb, roughness=0.6, metallic=0.0):
    srgb = [int(hex_rgb[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in srgb]
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*rgb, 1.0)
    result.use_nodes = True
    bsdf = result.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return result


ink = mat("Ink / nozzle", "#26323A")
cream = mat("Warm paper fuselage", "#F5EBD6")
coral = mat("Coral nose and fins", "#EB6B5C", 0.48)
teal = mat("Sky teal porthole", "#75CBD1", 0.35, 0.12)
floor_mat = mat("Review floor", "#D9E6DF")

model = bpy.data.collections.new("Rocket export")
bpy.context.scene.collection.children.link(model)


def move_to_model(obj):
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    model.objects.link(obj)
    return obj


def cylinder(name, radius, depth, z, material, vertices=12, radius_top=None, export=True):
    if radius_top is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=(0, 0, z))
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius_top, depth=depth, location=(0, 0, z))
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    if export:
        move_to_model(obj)
    return obj


def box(name, loc, dims, material, bevel=0.0, export=True):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("One-plane edge", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.data.materials.append(material)
    if export:
        move_to_model(obj)
    return obj


# Origin is near the visual center for a held-gift turntable.
cylinder("Rocket / paper fuselage", 0.29, 0.83, 0.04, cream)
cylinder("Rocket / coral blunt nose", 0.29, 0.34, 0.625, coral, radius_top=0.22)
cylinder("Rocket / dark nozzle", 0.19, 0.16, -0.45, ink)
cylinder("Rocket / nozzle lower lip", 0.22, 0.055, -0.53, ink)

# Four broad fins remain visible as the model turns; the preview shows three.
for sign in (-1, 1):
    box(f"Rocket / fin x {sign}", (sign * 0.34, 0, -0.28), (0.22, 0.15, 0.40), coral, 0.018)
    box(f"Rocket / fin y {sign}", (0, sign * 0.34, -0.28), (0.15, 0.22, 0.40), coral, 0.018)

# Low-poly hemispherical window on the front. No emissive material: readable
# color and silhouette under ordinary in-game lighting.
bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=1, location=(0, -0.289, 0.15))
window = bpy.context.object
window.name = "Rocket / teal porthole"
window.scale = (0.12, 0.035, 0.12)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
window.data.materials.append(teal)
move_to_model(window)

# Review setup stays outside the export collection.
box("Review / floor", (0, 0, -0.60), (200, 200, 0.09), floor_mat, export=False)
bpy.ops.object.camera_add(location=(1.75, -2.7, 1.35))
camera = bpy.context.object
camera.name = "Review / camera"
camera.rotation_euler = (Vector((0, 0, 0.03)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 2.55
bpy.context.scene.camera = camera


def light(name, loc, power, size):
    data = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.energy = power
    data.shape = "DISK"
    data.size = size


light("Review / key", (1.0, -2.0, 2.5), 240, 3.2)
light("Review / rim", (-1.3, 1.4, 1.8), 140, 2.8)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "rocket_v1_preview.png")
scene.view_settings.view_transform = "Standard"

bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "rocket_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = next(iter(model.objects))
bpy.ops.export_scene.gltf(filepath=str(OUT / "rocket_v1.glb"), export_format="GLB", use_selection=True, export_apply=True)
bpy.ops.render.render(write_still=True)
print(f"ROCKET_MODEL_READY {OUT}")
