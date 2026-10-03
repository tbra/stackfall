"""Create an animated low-poly black hole gift model and review render."""

from math import cos, pi, sin
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/black_hole_v1"
SOURCE = ROOT / "source_art/black_hole_v1"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").touch()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, hex_color):
    values = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in values]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = 0.7
    return mat


void = material("Near-black violet core", "#090311")
void.node_tree.nodes.get("Principled BSDF").inputs["Specular IOR Level"].default_value = 0.0
violet = material("Bright violet accretion ring", "#A159E8")
amber = material("Amber inner ring", "#F6A750")
glow = material("Lavender orbit fragments", "#CF9CFF")
floor_mat = material("Preview blue floor", "#435765")
model = bpy.data.collections.new("Black hole gift export")
bpy.context.scene.collection.children.link(model)


def add(obj, name, mat, parent=None):
    obj.name = name
    obj.data.materials.append(mat)
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    model.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def pivot(name, tilt):
    obj = bpy.data.objects.new(name, None)
    model.objects.link(obj)
    obj.rotation_euler.x = tilt
    return obj


def torus(name, major, minor, mat, parent):
    bpy.ops.mesh.primitive_torus_add(major_segments=32, minor_segments=6,
                                     location=(0, 0, 0), major_radius=major,
                                     minor_radius=minor)
    return add(bpy.context.object, name, mat, parent)


bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.255)
core = add(bpy.context.object, "Black hole / faceted core", void)

outer = pivot("Black hole / outer orbit pivot", 0.29)
torus("Black hole / violet ring", 0.405, 0.045, violet, outer)
inner = pivot("Black hole / inner orbit pivot", -0.22)
torus("Black hole / amber ring", 0.317, 0.027, amber, inner)

# Faceted orbit fragments create visible motion; each group is parented to its ring.
for i, angle in enumerate((0.15, 2.30, 4.15)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1,
                                          location=(0.405 * cos(angle),
                                                    0.405 * sin(angle), 0.02))
    obj = add(bpy.context.object, f"Black hole / violet orbit shard {i}", glow, outer)
    obj.scale = (0.083, 0.038, 0.028)
    obj.rotation_euler.z = angle
for i, angle in enumerate((1.1, 3.95)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1,
                                          location=(0.317 * cos(angle),
                                                    0.317 * sin(angle), 0.018))
    obj = add(bpy.context.object, f"Black hole / amber orbit shard {i}", amber, inner)
    obj.scale = (0.06, 0.027, 0.020)
    obj.rotation_euler.z = angle

for obj, end_angle in ((outer, 2 * pi), (inner, -2 * pi)):
    for frame, angle in ((1, 0), (97, end_angle)):
        obj.rotation_euler.z = angle
        obj.keyframe_insert(data_path="rotation_euler", frame=frame)
    action = obj.animation_data.action
    for fcurve in action.fcurves:
        for key in fcurve.keyframe_points:
            key.interpolation = "LINEAR"
    track = obj.animation_data.nla_tracks.new()
    track.name = "orbit_4s"
    track.strips.new("orbit_4s", 1, action)
    obj.animation_data.action = None

scene = bpy.context.scene
scene.render.fps = 24
scene.frame_start = 1
scene.frame_end = 97
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.53))
floor = bpy.context.object
floor.name = "Review / floor"
floor.dimensions = (200, 200, 0.08)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(1.5, -2.4, 1.45))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.50
scene.camera = camera
for name, pos, energy in (("Review / key", (1, -2, 2), 270),
                          ("Review / rim", (-1.3, 1.4, 1.8), 190)):
    light = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    obj.location = pos
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    light.energy = energy
    light.shape = "DISK"
    light.size = 2.8

scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "black_hole_v1_preview.png")
scene.view_settings.view_transform = "Standard"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "black_hole_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = outer
bpy.ops.export_scene.gltf(filepath=str(OUT / "black_hole_v1.glb"), export_format="GLB",
                          use_selection=True, export_cameras=False, export_lights=False,
                          export_animations=True, export_animation_mode="NLA_TRACKS")
scene.frame_set(1)
bpy.ops.render.render(write_still=True)
print(f"Built {OUT / 'black_hole_v1.glb'} and preview")
