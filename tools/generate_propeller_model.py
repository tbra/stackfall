"""Build a small animated caged desk-fan gift (kept id: propeller) with Blender source, GLB, and preview."""

from math import cos, pi, sin
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

# Bontago-mp0.161 (owner playtest 2026-10-13: "less propeller, more fan"): a caged
# five-blade desk fan facing -Y (Godot +Z). Foot + neck + guard cage stay still; the
# blade/hub mesh is the "Propeller / animated rotor" and spins about the Y axis.
HUB_Z = 0.1
CAGE_R = 0.4
BLADES = 5


def link(obj, name, mat):
    obj.name = name
    obj.data.materials.append(mat)
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    model.objects.link(obj)
    return obj


def ring(name, radius, minor, y, mat):
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=minor, major_segments=28,
                                     minor_segments=6, location=(0, y, HUB_Z), rotation=(pi / 2, 0, 0))
    return link(bpy.context.object, name, mat)


def spoke(angle, y0, r0, r1, thick, mat):
    # Flat radial wire from radius r0..r1 at depth y0, joined later into the guard.
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.object
    obj.dimensions = (r1 - r0, thick, thick)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.location = ((r0 + r1) / 2, y0, 0)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    obj.rotation_euler = (0, -angle, 0)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
    obj.location.z = HUB_Z
    return obj


def join(objs, name, mat):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    return link(bpy.context.object, name, mat)


# Still parts: dark base foot, teal neck, motor pod behind the cage.
bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.27, depth=0.07, location=(0, 0.02, -0.44))
link(bpy.context.object, "Propeller / dark foot", ink)
bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.055, depth=0.38, location=(0, 0.02, -0.28))
link(bpy.context.object, "Propeller / teal neck", teal)
bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.12, depth=0.16, location=(0, 0.1, HUB_Z), rotation=(pi / 2, 0, 0))
link(bpy.context.object, "Propeller / dark motor", ink)

# Guard cage: front and back rings plus radial wires and two inner hoops.
ring("Propeller / cage back ring", CAGE_R, 0.022, 0.1, teal)
ring("Propeller / cage front ring", CAGE_R, 0.022, -0.11, teal)
wires = [spoke(k * 2 * pi / 12, -0.11, 0.07, CAGE_R, 0.025, teal) for k in range(12)]
join(wires, "Propeller / cage wires", teal)
ring("Propeller / cage hoop outer", CAGE_R * 0.62, 0.016, -0.11, teal)
ring("Propeller / cage hoop inner", CAGE_R * 0.3, 0.016, -0.11, teal)

# Rotor: five broad pitched paper blades + brass hub in one mesh.
def fan_blade(index):
    base = index * 2 * pi / BLADES
    outline = [(0.06, -0.05), (0.2, -0.115), (0.34, -0.1), (0.35, 0.0), (0.34, 0.1), (0.2, 0.115), (0.06, 0.05)]
    pts_top, pts_bot = [], []
    for r, t in outline:
        # Pitch: tangential offset lifts one edge toward the viewer so the blade reads as twisted.
        for pts, dy in ((pts_top, 0.016 + 0.1 * t), (pts_bot, -0.016 + 0.1 * t)):
            ang = base
            x = r * cos(ang) - t * sin(ang)
            z = r * sin(ang) + t * cos(ang)
            pts.append((x, dy, z))
    n = len(outline)
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    data = bpy.data.meshes.new(f"blade{index}")
    data.from_pydata(pts_top + pts_bot, [], faces)
    data.update()
    obj = bpy.data.objects.new(f"blade{index}", data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = (0, 0, 0)
    return obj


blades = [fan_blade(i) for i in range(BLADES)]
bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.075, depth=0.1, location=(0, -0.02, 0), rotation=(pi / 2, 0, 0))
hub = bpy.context.object
hub.name = "hubmesh"
bpy.ops.object.select_all(action="DESELECT")
for o in blades:
    o.select_set(True)
bpy.context.view_layer.objects.active = blades[0]
bpy.ops.object.join()
rotor_blades = bpy.context.object
link(rotor_blades, "Propeller / paper blades", paper)
rotor_blades.location = (0, 0, 0)
hub.parent = rotor_blades
link(hub, "Propeller / brass hub", brass)
rotor = rotor_blades
rotor.location = (0, 0, HUB_Z)
hub.location = (0, -0.02, 0)

for frame, angle in ((1, 0), (7, pi / 2), (13, pi), (19, 3 * pi / 2), (25, 2 * pi)):
    rotor.rotation_euler = (0, angle, 0)
    rotor.keyframe_insert(data_path="rotation_euler", frame=frame)
for fcurve in rotor.animation_data.action.fcurves:
    for key in fcurve.keyframe_points:
        key.interpolation = "LINEAR"
action = rotor.animation_data.action
track = rotor.animation_data.nla_tracks.new()
track.name = "spin_1s"
track.strips.new("spin_1s", 1, action)
rotor.animation_data.action = None

scene = bpy.context.scene
scene.render.fps = 24
scene.frame_start = 1
scene.frame_end = 25
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.52))
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
