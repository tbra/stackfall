"""Build an animated, camera-independent cosmic horizon creature in Blender 4.5."""

from math import cos, pi, sin
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/fog_colossus_v1"
SOURCE = ROOT / "source_art/fog_colossus_v1"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").write_text("", encoding="utf-8")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, hex_color):
    srgb = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in srgb]
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = 1.0
    return m


deep = material("Distant blue slate", "#354B5B")
middle = material("Mist blue slate", "#496477")
light = material("Fog-lit blue slate", "#658092")
review_floor = material("Review backdrop", "#899CAB")

collection = bpy.data.collections.new("Fog colossus export")
bpy.context.scene.collection.children.link(collection)
root = bpy.data.objects.new("FogColossus / drift root", None)
collection.objects.link(root)


def to_export(obj, name, mat=None):
    obj.name = name
    if mat is not None:
        obj.data.materials.append(mat)
    for prior in list(obj.users_collection):
        prior.objects.unlink(obj)
    collection.objects.link(obj)
    obj.parent = root
    return obj


def lobe(name, center, scale, mat, subdivisions=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1)
    obj = bpy.context.object
    obj.location = center
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return to_export(obj, name, mat)


# The body is an incomplete upper mass. Fog in the future map should obscure it.
lobe("Body / central canopy", (0, 0, 1.65), (3.9, 2.25, 1.75), deep)
lobe("Body / left dissolved flank", (-2.75, 0.1, 1.04), (2.2, 1.8, 1.15), middle)
lobe("Body / right dissolved flank", (2.55, -0.25, 1.15), (2.35, 1.7, 1.2), middle)
lobe("Body / lower hanging mass", (0.1, -0.15, 0.45), (2.45, 1.48, 1.3), deep)


def tendril(name, anchor, length, reach, bend, radius, mat, phase):
    rings, sides = 15, 9
    vertices = []
    faces = []
    for i in range(rings):
        t = i / (rings - 1)
        x = reach * (t ** 1.35) + bend * sin(pi * t * 1.55)
        y = 0.18 * sin(pi * t * 1.8 + phase) * t
        z = -length * t
        ring_radius = max(0.035, radius * (1 - t) ** 1.1)
        for j in range(sides):
            a = 2 * pi * j / sides
            vertices.append((x + ring_radius * cos(a), y + ring_radius * sin(a), z))
    for i in range(rings - 1):
        for j in range(sides):
            a = i * sides + j
            b = i * sides + (j + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple((rings - 1) * sides + j for j in range(sides)))
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.materials.append(mat)
    data.update()
    obj = bpy.data.objects.new(name, data)
    collection.objects.link(obj)
    obj.parent = root
    obj.location = anchor
    for frame in (1, 73, 145, 217, 289):
        cycle = (frame - 1) / 288 * 2 * pi
        obj.rotation_euler = (
            0.045 * sin(cycle + phase),
            0.07 * sin(cycle + phase * 0.7),
            0.055 * sin(cycle + phase * 1.3),
        )
        obj.keyframe_insert(data_path="rotation_euler", frame=frame)
    return obj


# Different directions, depths, widths, and phases prevent a front-only read.
specs = [
    ("Near left", (-2.9, -1.0, 1.18), 7.0, -2.7, -0.7, 0.57, deep, 0.2),
    ("Near right", (2.85, -0.95, 1.25), 7.7, 2.9, 0.8, 0.59, deep, 1.5),
    ("Far left", (-3.15, 1.0, 1.1), 5.5, -2.3, 1.1, 0.39, middle, 2.8),
    ("Far right", (3.25, 0.85, 1.3), 5.9, 2.35, -1.0, 0.43, middle, 4.2),
    ("Center A", (-1.22, -0.65, 0.62), 6.6, -0.45, 0.5, 0.37, light, 0.8),
    ("Center B", (0.75, -0.50, 0.45), 7.3, 0.95, -0.6, 0.46, middle, 2.0),
    ("Center C", (1.65, 0.65, 0.63), 6.0, -0.70, 0.75, 0.32, light, 3.7),
    ("Rear", (-0.45, 1.35, 0.74), 6.4, -0.3, -0.7, 0.38, middle, 5.1),
]
for spec in specs:
    tendril("Tendril / " + spec[0], *spec[1:])

# Root translation is intentionally slow; a map scene may add larger movement.
for frame, x, y, z, yaw in ((1, -0.8, 0, 0, -0.025), (145, 0.8, 0.25, 0.22, 0.025), (289, -0.8, 0, 0, -0.025)):
    root.location = (x, y, z)
    root.rotation_euler = (0, 0, yaw)
    root.keyframe_insert(data_path="location", frame=frame)
    root.keyframe_insert(data_path="rotation_euler", frame=frame)

scene = bpy.context.scene
scene.render.fps = 24
scene.frame_start = 1
scene.frame_end = 289
if root.animation_data and root.animation_data.action:
    root.animation_data.action.name = "drift_and_sway_12s"

# Put all object actions on identically named NLA tracks so glTF exports one
# coordinated clip instead of nine mutually exclusive per-object clips.
for animated in [root, *[obj for obj in collection.objects if obj.name.startswith("Tendril / ")]]:
    action = animated.animation_data.action
    track = animated.animation_data.nla_tracks.new()
    track.name = "drift_and_sway_12s"
    track.strips.new("drift_and_sway_12s", 1, action)
    animated.animation_data.action = None


def light_object(name, position, energy, size):
    data = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = position
    obj.rotation_euler = (Vector((0, 0, -2)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.energy = energy
    data.shape = "DISK"
    data.size = size


light_object("Review / key", (2, -10, 8), 1400, 8)
light_object("Review / fill", (-9, 4, 4), 900, 8)

def camera_object(name, position, target):
    bpy.ops.object.camera_add(location=position)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
    obj.data.type = "ORTHO"
    obj.data.ortho_scale = 17
    return obj


front = camera_object("Review / front camera", (10, -20, 2), (0, 0, -2))
side = camera_object("Review / side camera", (-16, -10, 2), (0, 0, -2))
scene.world.color = (0.36, 0.46, 0.55)
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "Standard"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "fog_colossus_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in collection.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(filepath=str(OUT / "fog_colossus_v1.glb"), export_format="GLB", use_selection=True, export_cameras=False, export_lights=False, export_animations=True, export_animation_mode="NLA_TRACKS")
scene.frame_set(1)
for camera, name in ((front, "front"), (side, "side")):
    scene.camera = camera
    scene.render.filepath = str(OUT / f"fog_colossus_v1_{name}.png")
    bpy.ops.render.render(write_still=True)
print(f"Built animated {OUT / 'fog_colossus_v1.glb'}")
