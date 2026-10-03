"""Build a faceted gift anvil, source Blend, GLB, and neutral preview."""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/anvil_v1"
SOURCE = ROOT / "source_art/anvil_v1"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").write_text("", encoding="utf-8")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, color, metallic=0.0):
    srgb = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in srgb]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*rgb, 1)
    shader.inputs["Roughness"].default_value = 0.68
    shader.inputs["Metallic"].default_value = metallic
    return mat


iron = material("Blue ink iron", "#26323A", 0.22)
edge = material("Pale cut edges", "#8BA7AD", 0.10)
shadow = material("Underside iron", "#17242B", 0.12)
brass = material("Brass maker mark", "#E8B85D", 0.13)
floor_mat = material("Review floor", "#DCE5DF")

collection = bpy.data.collections.new("Anvil export")
bpy.context.scene.collection.children.link(collection)


def move_to_export(obj):
    for previous in list(obj.users_collection):
        previous.objects.unlink(obj)
    collection.objects.link(obj)
    return obj


def box(name, center, size, mat, bevel=0.0, export=True):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new("Broad cut edge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.data.materials.append(mat)
    if export:
        move_to_export(obj)
    return obj


def mesh(name, vertices, faces, mat):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.materials.append(mat)
    data.update()
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    return obj


# Roughly one block across; pivot lies at the visual center.
box("Anvil / broad foot", (0, 0, -0.36), (0.91, 0.48, 0.14), shadow, 0.055)
box("Anvil / tapered waist", (0, 0, -0.15), (0.44, 0.37, 0.33), iron, 0.055)
box("Anvil / face slab", (-0.08, 0, 0.095), (0.79, 0.50, 0.20), iron, 0.055)
box("Anvil / polished top", (-0.08, 0, 0.20), (0.77, 0.48, 0.035), edge, 0.012)

# Wedge horn with broad planar facets, pointing toward +X.
horn_verts = [
    (0.24, -0.20, -0.01), (0.24, 0.20, -0.01),
    (0.24, -0.20, 0.18), (0.24, 0.20, 0.18),
    (0.74, -0.095, 0.055), (0.74, 0.095, 0.055),
    (1.02, 0.0, 0.085),
]
horn_faces = [(0, 1, 3, 2), (0, 2, 4), (1, 5, 3), (2, 3, 5, 4), (4, 5, 6), (0, 4, 6, 5, 1)]
mesh("Anvil / tapered horn", horn_verts, horn_faces, iron)
box("Anvil / gold maker mark", (-0.18, -0.257, -0.155), (0.20, 0.018, 0.085), brass, 0.008)

# Review scene is excluded from the GLB.
box("Review / floor", (0, 0, -0.49), (200, 200, 0.08), floor_mat, export=False)
bpy.ops.object.camera_add(location=(2.0, -2.65, 1.52))
camera = bpy.context.object
camera.name = "Review / camera"
camera.rotation_euler = (Vector((0.04, 0, -0.04)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 2.45
bpy.context.scene.camera = camera


def light(name, point, energy, size):
    data = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = point
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.energy = energy
    data.shape = "DISK"
    data.size = size


light("Review / key", (1.0, -2.0, 2.4), 270, 3.0)
light("Review / rim", (-1.5, 1.4, 2.0), 170, 2.8)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "anvil_v1_preview.png")
scene.view_settings.view_transform = "Standard"

bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "anvil_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in collection.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = next(iter(collection.objects))
bpy.ops.export_scene.gltf(filepath=str(OUT / "anvil_v1.glb"), export_format="GLB", use_selection=True, export_cameras=False, export_lights=False)
bpy.ops.render.render(write_still=True)
print(f"Built {OUT / 'anvil_v1.glb'} and preview")
