"""Build a standalone low-poly glue gift jar with source and neutral preview."""

from pathlib import Path
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/glue_v1"
SOURCE = ROOT / "source_art/glue_v1"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").write_text("", encoding="utf-8")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=0.7):
    srgb = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in srgb]
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    return m


teal = material("Opaque mint glue", "#75CBD1", 0.55)
mint_dark = material("Glaze underside", "#3D8F90")
ink = material("Ink twist cap", "#26323A")
paper = material("Warm paper label", "#F5EBD6")
brass = material("Brass drop emblem", "#E8B85D", 0.55)
floor_mat = material("Review floor", "#DCE5DF")
export = bpy.data.collections.new("Glue jar export")
bpy.context.scene.collection.children.link(export)


def add(obj, name, mat, to_export=True):
    obj.name = name
    obj.data.materials.append(mat)
    if to_export:
        for old in list(obj.users_collection):
            old.objects.unlink(obj)
        export.objects.link(obj)
    return obj


def cylinder(name, radius, depth, z, mat, vertices=12, radius_top=None):
    if radius_top is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=(0, 0, z))
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius_top, depth=depth, location=(0, 0, z))
    return add(bpy.context.object, name, mat)


def box(name, location, dimensions, mat, bevel=0.0, to_export=True):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Single cut edge", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return add(obj, name, mat, to_export)


# Broad jar, shoulder, and twist cap remain readable as a tiny held gift.
cylinder("Glue / faceted body", 0.30, 0.56, -0.10, teal)
cylinder("Glue / dark base rim", 0.305, 0.055, -0.41, mint_dark)
cylinder("Glue / shoulder", 0.30, 0.13, 0.24, teal, radius_top=0.22)
cylinder("Glue / neck", 0.17, 0.09, 0.34, mint_dark)
cylinder("Glue / twist cap", 0.23, 0.17, 0.46, ink, vertices=10)
cylinder("Glue / cap top", 0.19, 0.025, 0.56, ink, vertices=10)

# One bold label and raised drop mark on the front, facing the review camera.
box("Glue / paper label", (0, -0.302, -0.10), (0.42, 0.023, 0.28), paper, 0.025)
bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=1, location=(0, -0.321, -0.105))
drop = bpy.context.object
drop.scale = (0.069, 0.018, 0.081)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
add(drop, "Glue / raised drop emblem", brass)

box("Review / floor", (0, 0, -0.49), (200, 200, 0.08), floor_mat, to_export=False)
bpy.ops.object.camera_add(location=(1.7, -2.5, 1.25))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 2.12
bpy.context.scene.camera = camera

for name, location, energy in (("Review / key", (1, -2, 2.3), 250), ("Review / rim", (-1.3, 1.5, 1.8), 145)):
    data = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.energy = energy
    data.shape = "DISK"
    data.size = 3.0

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "glue_v1_preview.png")
scene.view_settings.view_transform = "Standard"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "glue_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in export.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = next(iter(export.objects))
bpy.ops.export_scene.gltf(filepath=str(OUT / "glue_v1.glb"), export_format="GLB", use_selection=True, export_cameras=False, export_lights=False)
bpy.ops.render.render(write_still=True)
print(f"Built {OUT / 'glue_v1.glb'} and preview")
