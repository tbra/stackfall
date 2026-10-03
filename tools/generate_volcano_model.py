"""Build an original faceted volcano gift study with source, GLB, and preview."""

from math import cos, pi, sin
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/volcano_v1"
SOURCE = ROOT / "source_art/volcano_v1"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").write_text("", encoding="utf-8")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, color, roughness=0.79):
    srgb = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in srgb]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*rgb, 1)
    shader.inputs["Roughness"].default_value = roughness
    return mat


rock = material("Slate rock", "#4F6571")
rock_shadow = material("Fractured ink rock", "#26323A")
rim_highlight = material("Ash lit edge", "#81939B")
lava = material("Coral lava", "#EB6B5C", 0.55)
lava_light = material("Brass hot center", "#E8B85D", 0.48)
floor_mat = material("Review floor", "#DCE5DF")
model = bpy.data.collections.new("Volcano export")
bpy.context.scene.collection.children.link(model)


def add_mesh(name, vertices, faces, face_materials, materials):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    for mat in materials:
        data.materials.append(mat)
    data.update()
    for polygon, index in zip(data.polygons, face_materials):
        polygon.material_index = index
    obj = bpy.data.objects.new(name, data)
    model.objects.link(obj)
    return obj


segments = 12
rings = [
    (0.45, -0.37),
    (0.38, -0.25),
    (0.31, -0.08),
    (0.22, 0.28),
    (0.135, 0.31),
    (0.105, 0.13),
]
vertices = []
for ring, (radius, z) in enumerate(rings):
    for i in range(segments):
        angle = i * 2 * pi / segments
        irregularity = 1 + 0.075 * sin(i * 2.7 + ring * 1.5)
        height = z + (0.018 * sin(i * 3.1) if ring in (0, 3) else 0)
        vertices.append((radius * irregularity * cos(angle), radius * irregularity * sin(angle), height))
faces = []
face_materials = []
for ring in range(len(rings) - 1):
    for i in range(segments):
        next_i = (i + 1) % segments
        faces.append((ring * segments + i, ring * segments + next_i, (ring + 1) * segments + next_i, (ring + 1) * segments + i))
        if ring == 3:
            face_materials.append(2)
        elif ring == 4:
            face_materials.append(1)
        else:
            face_materials.append(1 if (i + ring) % 5 == 0 else 0)
faces.append(tuple(reversed(range(segments))))
face_materials.append(1)
add_mesh("Volcano / hollow faceted cone", vertices, faces, face_materials, [rock, rock_shadow, rim_highlight])


def disk(name, radius, z, mat, count=12):
    verts = [(0, 0, z)] + [(radius * cos(2 * pi * i / count), radius * sin(2 * pi * i / count), z) for i in range(count)]
    triangles = [(0, i + 1, (i + 1) % count + 1) for i in range(count)]
    return add_mesh(name, verts, triangles, [0] * len(triangles), [mat])


disk("Volcano / glowing crater pool", 0.125, 0.255, lava)
disk("Volcano / hot pool center", 0.064, 0.258, lava_light)


def rivulet(name, angle, side, width, mat):
    # Four broad points stay visible at held-gift size without noisy lines.
    path = [(0.197, 0.275), (0.245, 0.175), (0.325, -0.13), (0.402, -0.31)]
    verts = []
    for step, (radius, z) in enumerate(path):
        half = width * (1.0 if step < 2 else 0.62)
        for offset in (-half, half):
            a = angle + offset
            r = radius + 0.014
            verts.append((r * cos(a), r * sin(a), z))
    faces = [(i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2) for i in range(3)]
    return add_mesh(name, verts, faces, [0] * 3, [mat])


for i, (angle, width) in enumerate(((0.25, 0.19), (2.45, 0.14), (4.72, 0.18))):
    rivulet(f"Volcano / lava rivulet {i + 1}", angle, i, width, lava if i != 1 else lava_light)


# Neutral review setup is kept outside the export collection.
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.47))
floor = bpy.context.object
floor.name = "Review / floor"
floor.dimensions = (200, 200, 0.08)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(1.5, -2.2, 1.25))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.8
bpy.context.scene.camera = camera

for name, pos, power in (("Review / key", (1.0, -1.8, 2.1), 230), ("Review / rim", (-1.4, 1.3, 1.6), 125)):
    data = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = pos
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    data.energy = power
    data.shape = "DISK"
    data.size = 2.8

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "volcano_v1_preview.png")
scene.view_settings.view_transform = "Standard"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "volcano_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = next(iter(model.objects))
bpy.ops.export_scene.gltf(filepath=str(OUT / "volcano_v1.glb"), export_format="GLB", use_selection=True, export_cameras=False, export_lights=False)
bpy.ops.render.render(write_still=True)
print(f"Built {OUT / 'volcano_v1.glb'} and preview")
