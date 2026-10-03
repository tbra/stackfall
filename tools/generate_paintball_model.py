"""Build a colorful, faceted paintball gift art candidate in Blender 4.5."""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/paintball_v1"
SOURCE = ROOT / "source_art/paintball_v1"
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
    bsdf.inputs["Roughness"].default_value = 0.71
    return m


blue = material("Sky blue shell", "#4F91D9")
coral = material("Coral splash", "#EB6B5C")
brass = material("Brass splash", "#E8B85D")
mint = material("Mint splash", "#75CBD1")
ink = material("Ink seam", "#26323A")
floor_mat = material("Review floor", "#DCE5DF")
model = bpy.data.collections.new("Paintball export")
bpy.context.scene.collection.children.link(model)


def add(obj, name, mat):
    obj.name = name
    obj.data.materials.append(mat)
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    model.objects.link(obj)
    return obj


def sphere(name, center, scale, mat, segments=12, rings=7):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=center)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return add(obj, name, mat)


def splash(name, base, tip, radius, mat):
    direction = Vector(tip) - Vector(base)
    center = (Vector(tip) + Vector(base)) / 2
    bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=radius, radius2=0.0, depth=direction.length, location=center)
    obj = bpy.context.object
    obj.rotation_euler = direction.to_track_quat("Z", "Y").to_euler()
    return add(obj, name, mat)


sphere("Paintball / faceted blue body", (0, 0, 0), (0.31, 0.31, 0.31), blue)
bpy.ops.mesh.primitive_torus_add(major_segments=16, minor_segments=4, location=(0, 0, -0.025), major_radius=0.292, minor_radius=0.018)
add(bpy.context.object, "Paintball / dark capsule seam", ink)

# Broad front patch reads as a splash at normal held-gift size.
sphere("Paintball / coral front splash", (-0.045, -0.301, 0.045), (0.15, 0.032, 0.13), coral)
sphere("Paintball / brass splash dot", (0.135, -0.280, -0.11), (0.082, 0.027, 0.073), brass)
sphere("Paintball / small mint dot", (-0.17, -0.275, -0.115), (0.058, 0.023, 0.052), mint)

# Three different splash tips break the sphere's outline without noisy detail.
splash("Paintball / coral upper droplet", (-0.18, 0, 0.24), (-0.29, 0.015, 0.49), 0.077, coral)
splash("Paintball / brass right droplet", (0.25, 0.02, 0.055), (0.48, 0.04, 0.16), 0.072, brass)
splash("Paintball / mint left droplet", (-0.26, 0.0, -0.095), (-0.43, 0.05, -0.20), 0.067, mint)

bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.40))
floor = bpy.context.object
floor.name = "Review / floor"
floor.dimensions = (200, 200, 0.08)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(1.45, -2.2, 1.05))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, 0.03)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.55
bpy.context.scene.camera = camera
for name, pos, power in (("Review / key", (1, -2, 1.9), 250), ("Review / rim", (-1.3, 1.2, 1.6), 130)):
    data = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = pos
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.energy = power
    data.shape = "DISK"
    data.size = 2.7

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "paintball_v1_preview.png")
scene.view_settings.view_transform = "Standard"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "paintball_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = next(iter(model.objects))
bpy.ops.export_scene.gltf(filepath=str(OUT / "paintball_v1.glb"), export_format="GLB", use_selection=True, export_cameras=False, export_lights=False)
bpy.ops.render.render(write_still=True)
print(f"Built {OUT / 'paintball_v1.glb'} and preview")
