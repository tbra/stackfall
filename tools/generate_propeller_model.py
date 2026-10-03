"""Build a small animated propeller gift with Blender source, GLB, and preview."""

from math import pi
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/propeller_v1"
SOURCE = ROOT / "source_art/propeller_v1"
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
    bsdf.inputs["Roughness"].default_value = 0.69
    return m


ink = material("Ink motor casing", "#26323A")
teal = material("Sky teal post", "#75CBD1")
paper = material("Warm paper blades", "#F5EBD6")
brass = material("Brass hub", "#E8B85D")
coral = material("Coral blade tips", "#EB6B5C")
floor_mat = material("Review storm floor", "#435765")
model = bpy.data.collections.new("Propeller export")
bpy.context.scene.collection.children.link(model)
rotor = bpy.data.objects.new("Propeller / animated rotor", None)
model.objects.link(rotor)
rotor.location = (0, 0, 0.35)


def add(obj, name, mat, parent=None):
    obj.name = name
    obj.data.materials.append(mat)
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    model.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def cylinder(name, radius, depth, z, mat, vertices=10, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=(0, 0, z))
    obj = bpy.context.object
    if parent is not None:
        # Parent-space coordinates keep the rotor pivot at its own center.
        obj.location.z = z - rotor.location.z
    return add(obj, name, mat, parent)


def blade(name, sign, mat):
    # A thick tapered planform with slight pitch catches light as it turns.
    outline = [(0.07, -0.065), (0.27, -0.135), (0.53, -0.105), (0.59, -0.045),
               (0.59, 0.045), (0.53, 0.105), (0.27, 0.135), (0.07, 0.065)]
    top = [(sign * x, y, 0.038 + 0.16 * y) for x, y in outline]
    bottom = [(sign * x, y, -0.032 + 0.16 * y) for x, y in outline]
    verts = top + bottom
    count = len(outline)
    faces = [tuple(range(count)), tuple(reversed(range(count, 2 * count)))]
    faces += [(i, (i + 1) % count, (i + 1) % count + count, i + count) for i in range(count)]
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    model.objects.link(obj)
    obj.parent = rotor
    obj.data.materials.append(mat)
    return obj


cylinder("Propeller / dark foot", 0.22, 0.10, -0.32, ink)
cylinder("Propeller / teal spindle", 0.115, 0.57, -0.005, teal)
cylinder("Propeller / dark collar", 0.16, 0.10, 0.27, ink)
blade("Propeller / left paper blade", -1, paper)
blade("Propeller / right paper blade", 1, paper)
cylinder("Propeller / brass rotor cap", 0.105, 0.11, 0.35, brass, parent=rotor)

# Two compact colored tips communicate direction without small engraved detail.
for sign in (-1, 1):
    bpy.ops.mesh.primitive_cube_add(size=1)
    tip = bpy.context.object
    tip.dimensions = (0.10, 0.16, 0.078)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    tip.location = (sign * 0.53, 0, 0)
    add(tip, f"Propeller / coral tip {sign}", coral, rotor)

for frame, angle in ((1, 0), (7, pi / 2), (13, pi), (19, 3 * pi / 2), (25, 2 * pi)):
    rotor.rotation_euler.z = angle
    rotor.keyframe_insert(data_path="rotation_euler", frame=frame)
action = rotor.animation_data.action
track = rotor.animation_data.nla_tracks.new()
track.name = "spin_1s"
track.strips.new("spin_1s", 1, action)
rotor.animation_data.action = None

scene = bpy.context.scene
scene.render.fps = 24
scene.frame_start = 1
scene.frame_end = 25
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.42))
floor = bpy.context.object
floor.name = "Review / floor"
floor.dimensions = (200, 200, 0.08)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(1.5, -2.4, 1.4))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, 0.03)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.9
bpy.context.scene.camera = camera
for name, pos, power in (("Review / key", (1, -2, 2.1), 245), ("Review / rim", (-1.3, 1.4, 1.8), 150)):
    data = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = pos
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.energy = power
    data.shape = "DISK"
    data.size = 2.8

scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "propeller_v1_preview.png")
scene.view_settings.view_transform = "Standard"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "propeller_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = rotor
bpy.ops.export_scene.gltf(filepath=str(OUT / "propeller_v1.glb"), export_format="GLB", use_selection=True, export_cameras=False, export_lights=False, export_animations=True, export_animation_mode="NLA_TRACKS")
scene.frame_set(1)
bpy.ops.render.render(write_still=True)
print(f"Built animated {OUT / 'propeller_v1.glb'} and preview")
