"""Build the round-two gift models (Bontago-9cv) in Blender 4.5.

Run:  blender -b --python tools/generate_gift_models_v2.py [-- earthquake black_hole ...]

Owner 2026-10-12: the gift models read poorly and were not cel-shaded. Shading is
handled at runtime (config/GiftModelTable.gd + shaders/gift_toon.gdshader); this
script remodels the five weakest silhouettes with chunkier, bolder shapes:
earthquake, black_hole, jumping_bean, paintball and volcano, plus the gift box
(owner: "do a pass on the gift box as well") as a wrapped present, closed and
opening (gift_crate / gift_crate_reveal keep v1's bottom-centre origin, size and
hinged-lid open_reveal_1s clip, so the crate code is unchanged). Each model fits a
one-cell cube centred on the origin (Blender Z up, front facing -Y, which glTF
turns into Godot +Z), uses flat colours only (the toon shader does the shading)
and keeps its v1 loop-animation name so config/gift_model_table.tres can swap
scenes without touching code.

Outputs: assets/models/<id>_v2/<id>_v2.glb and source_art/<id>_v2/<id>_v2.blend.
"""

import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector

ROOT = Path(__file__).resolve().parents[1]
FPS = 24


# --- Scene helpers ------------------------------------------------------------------

def reset() -> bpy.types.Collection:
    # DECISION (Bontago-9cv): never wm.read_factory_settings here. Factory
    # settings disable the user's extensions, and Blender's wheel sync then
    # deletes their Python packages from extensions/.local (it did, once, for
    # Bonsai; a normal start restores them). Clear the open file by hand instead.
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for collection in (bpy.data.collections, bpy.data.meshes, bpy.data.materials, bpy.data.actions,
                       bpy.data.metaballs, bpy.data.curves, bpy.data.lights, bpy.data.cameras):
        for block in list(collection):
            collection.remove(block)
    scene = bpy.context.scene
    scene.render.fps = FPS
    collection = bpy.data.collections.new("Gift export")
    scene.collection.children.link(collection)
    return collection


def material(name: str, hex_value: str, emission: float = 0.0) -> bpy.types.Material:
    srgb = [int(hex_value[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in srgb]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*linear, 1)
    bsdf.inputs["Roughness"].default_value = 0.8
    if emission > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*linear, 1)
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def finish(obj, collection, mat, smooth: bool = True, bevel: float = 0.0, parent=None):
    for coll in list(obj.users_collection):
        coll.objects.unlink(obj)
    collection.objects.link(obj)
    if obj.type == "MESH":
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        for poly in obj.data.polygons:
            poly.use_smooth = smooth
        if bevel > 0.0:
            mod = obj.modifiers.new("Bevel", "BEVEL")
            mod.width = bevel
            mod.segments = 2
            mod.limit_method = "ANGLE"
    if parent is not None:
        obj.parent = parent
    return obj


def apply_transform(obj) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def box(collection, name, mat, loc, size, rot=(0, 0, 0), bevel=0.025, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    apply_transform(obj)
    return finish(obj, collection, mat, smooth=False, bevel=bevel, parent=parent)


def sphere(collection, name, mat, loc, radius, scale=(1, 1, 1), rot=(0, 0, 0), segments=24, parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=segments // 2, radius=radius,
                                         location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    apply_transform(obj)
    return finish(obj, collection, mat, parent=parent)


def rock(collection, name, mat, loc, radius, seed, parent=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=radius, location=loc)
    obj = bpy.context.object
    obj.name = name
    rng = random.Random(seed)
    for vert in obj.data.vertices:
        vert.co *= rng.uniform(0.8, 1.15)
    return finish(obj, collection, mat, smooth=False, parent=parent)


def torus(collection, name, mat, loc, major, minor, rot=(0, 0, 0), scale=(1, 1, 1), parent=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=40,
                                     minor_segments=12, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    apply_transform(obj)
    return finish(obj, collection, mat, parent=parent)


def cone(collection, name, mat, loc, r1, r2, depth, vertices=12, rot=(0, 0, 0), smooth=True, parent=None):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2, depth=depth,
                                    location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    apply_transform(obj)
    return finish(obj, collection, mat, smooth=smooth, parent=parent)


def capsule(collection, name, mat, start, end, radius, parent=None):
    a, b = Vector(start), Vector(end)
    mid = (a + b) / 2
    length = (b - a).length
    bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=radius, depth=length, location=mid)
    body = bpy.context.object
    body.rotation_euler = (b - a).to_track_quat("Z", "Y").to_euler()
    apply_transform(body)
    finish(body, collection, mat)
    body.name = name
    for i, end_point in enumerate((a, b)):
        sphere(collection, f"{name} cap {i}", mat, tuple(end_point), radius, segments=14, parent=parent)
    if parent is not None:
        body.parent = parent
    return body


def metaball_mesh(collection, name, mat, balls, resolution=0.04):
    meta = bpy.data.metaballs.new(name)
    meta.resolution = resolution
    meta.render_resolution = resolution
    obj = bpy.data.objects.new(name, meta)
    bpy.context.scene.collection.objects.link(obj)
    for co, radius in balls:
        element = meta.elements.new()
        element.co = co
        element.radius = radius
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    mesh_obj = bpy.context.object
    mesh_obj.name = name
    return finish(mesh_obj, collection, mat)


def empty(collection, name, loc=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.location = loc
    if parent is not None:
        obj.parent = parent
    return obj


def keyed(obj, data_path: str, frames_values, clip: str) -> None:
    for frame, value in frames_values:
        setattr(obj, data_path, value)
        obj.keyframe_insert(data_path=data_path, frame=frame)
    action = obj.animation_data.action
    for fcurve in action.fcurves:
        for key in fcurve.keyframe_points:
            key.interpolation = "LINEAR" if data_path == "rotation_euler" else "BEZIER"
    track = obj.animation_data.nla_tracks.new()
    track.name = clip
    track.strips.new(clip, 1, action)
    obj.animation_data.action = None


def export(collection, model_id: str, animated: bool) -> None:
    out = ROOT / f"assets/models/{model_id}_v2"
    source = ROOT / f"source_art/{model_id}_v2"
    out.mkdir(parents=True, exist_ok=True)
    source.mkdir(parents=True, exist_ok=True)
    (source / ".gdignore").touch()
    bpy.ops.wm.save_as_mainfile(filepath=str(source / f"{model_id}_v2.blend"), copy=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection.objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(out / f"{model_id}_v2.glb"), export_format="GLB",
                              use_selection=True, export_cameras=False, export_lights=False,
                              export_apply=True, export_animations=animated,
                              export_animation_mode="NLA_TRACKS")
    print(f"Built {out / f'{model_id}_v2.glb'}")


# --- Models -------------------------------------------------------------------------

def earthquake() -> None:
    # A chunk of ground split into three tilted slabs by a glowing lava fault,
    # with pebbles jumping above it.
    col = reset()
    grass = material("Grass top", "#6CC24A")
    dirt = material("Earth", "#9A6236")
    dark = material("Deep earth", "#5B3A22")
    lava = material("Fault lava", "#FF6A1A", emission=1.2)
    stone = material("Pebble", "#B9A389")
    clip = "quake_pulse_1s"
    slabs = [
        ("left", (-0.2, 0.02, -0.08), (0.36, 0.7, 0.34), (0, math.radians(-8), math.radians(4))),
        ("right", (0.21, 0.06, -0.02), (0.34, 0.5, 0.34), (math.radians(6), math.radians(10), 0)),
        ("front", (0.05, -0.27, -0.12), (0.72, 0.22, 0.28), (math.radians(-12), 0, 0)),
    ]
    for name, loc, size, rot in slabs:
        pivot = empty(col, f"Slab {name}", loc)
        pivot.rotation_euler = rot
        box(col, f"{name} earth", dirt, (0, 0, -0.02), (size[0], size[1], size[2] - 0.06), parent=pivot)
        box(col, f"{name} deep", dark, (0, 0, -size[2] / 2 + 0.03), (size[0] * 0.94, size[1] * 0.94, 0.06),
            parent=pivot)
        box(col, f"{name} grass", grass, (0, 0, size[2] / 2 - 0.035), (size[0] + 0.03, size[1] + 0.03, 0.07),
            parent=pivot)
        jitter = 0.022
        keyed(pivot, "location", [
            (1, Vector(loc)), (7, Vector(loc) + Vector((jitter, 0, jitter))),
            (13, Vector(loc) + Vector((-jitter, 0, 0))), (19, Vector(loc) + Vector((0, jitter, jitter * 0.6))),
            (25, Vector(loc)),
        ], clip)
    for i, (x, y) in enumerate(((0.0, -0.05), (0.01, 0.12), (-0.02, -0.17))):
        box(col, f"Fault lava {i}", lava, (x, y, 0.02), (0.1, 0.2, 0.42), rot=(0, 0, math.radians(35 * (-1) ** i)),
            bevel=0.0)
    for i, (loc, radius) in enumerate((((-0.18, -0.05, 0.3), 0.07), ((0.2, 0.08, 0.34), 0.055),
                                       ((0.02, -0.25, 0.27), 0.05))):
        pebble = rock(col, f"Pebble {i}", stone, loc, radius, 30 + i)
        keyed(pebble, "location", [(1, Vector(loc)), (7 + 3 * i, Vector(loc) + Vector((0, 0, 0.07))),
                                   (25, Vector(loc))], clip)
    bpy.context.scene.frame_end = 25
    export(col, "earthquake", True)


def black_hole() -> None:
    # A dark core inside a tilted, glowing accretion disk with block debris orbiting.
    col = reset()
    core = material("Event horizon", "#120A22")
    rim = material("Horizon glow", "#9B5CFF", emission=0.8)
    hot = material("Accretion hot", "#FFD15C", emission=0.9)
    warm = material("Accretion", "#FF7A2E", emission=0.35)
    debris_colors = ["#4FA3FF", "#FF6B5A", "#FFD24A", "#7ED957"]
    clip = "orbit_4s"
    tilt = empty(col, "Disk tilt")
    # Mostly flat, tipped toward the viewer so the disk reads as a ring around the core.
    tilt.rotation_euler = (math.radians(-22), math.radians(8), 0)
    spin = empty(col, "Disk spin", parent=tilt)
    torus(col, "Accretion outer", warm, (0, 0, 0), 0.34, 0.07, scale=(1, 1, 0.35), parent=spin)
    torus(col, "Accretion inner", hot, (0, 0, 0), 0.245, 0.032, parent=spin)
    for i, hex_value in enumerate(debris_colors):
        angle = i * math.tau / len(debris_colors) + 0.4
        box(col, f"Debris {i}", material(f"Debris {i}", hex_value),
            (math.cos(angle) * 0.4, math.sin(angle) * 0.4, 0.02 * (-1) ** i), (0.075, 0.075, 0.075),
            rot=(0.5 * i, 0.3, 0.7 * i), bevel=0.012, parent=spin)
    sphere(col, "Core", core, (0, 0, 0), 0.19)
    torus(col, "Horizon ring", rim, (0, 0, 0), 0.2, 0.02, rot=(math.radians(90), 0, 0))
    frames = 4 * FPS
    keyed(spin, "rotation_euler", [(1, Euler((0, 0, 0))), (frames + 1, Euler((0, 0, math.tau)))], clip)
    bpy.context.scene.frame_end = frames + 1
    export(col, "black_hole", True)


def jumping_bean() -> None:
    # A plump, caramel kidney bean with a cheeky face, squashing and stretching
    # through a little idle hop.
    col = reset()
    bean = material("Bean", "#E08A3A")
    belly = material("Bean belly", "#F4B26A")
    white = material("Eye white", "#FFFFFF")
    ink = material("Pupil", "#1B1A2E")
    mouth = material("Mouth", "#7A1E2E")
    blush = material("Blush", "#FF8FA3")
    clip = "idle_hop_1p5s"
    root = empty(col, "Bean root")
    body = metaball_mesh(col, "Bean body", bean, [
        ((-0.2, 0.0, -0.06), 0.3), ((0.0, 0.0, 0.03), 0.32), ((0.2, 0.0, -0.06), 0.3),
    ])
    body.parent = root
    body.scale = (1.0, 0.82, 0.92)
    stripe = metaball_mesh(col, "Bean belly", belly, [
        ((-0.12, -0.04, -0.2), 0.14), ((0.12, -0.04, -0.2), 0.14),
    ])
    stripe.parent = root
    for side in (-1, 1):
        x = side * 0.095
        sphere(col, f"Eye {side}", white, (x, -0.235, 0.08), 0.075, scale=(0.85, 0.45, 1.1), parent=root)
        sphere(col, f"Pupil {side}", ink, (x + 0.012, -0.27, 0.07), 0.04, scale=(0.9, 0.4, 1.1), parent=root)
        sphere(col, f"Glint {side}", white, (x + 0.025, -0.286, 0.095), 0.013, scale=(1, 0.4, 1), parent=root)
        sphere(col, f"Cheek {side}", blush, (side * 0.19, -0.215, -0.02), 0.04, scale=(1.2, 0.35, 0.7), parent=root)
    sphere(col, "Smile", mouth, (0.0, -0.25, -0.035), 0.05, scale=(1.0, 0.35, 0.55), parent=root)
    hop = [(1, (0, 0, 0), (1.12, 1.12, 0.84)), (8, (0, 0, 0.12), (0.92, 0.92, 1.14)),
           (19, (0, 0, 0.16), (1.0, 1.0, 1.0)), (30, (0, 0, 0.0), (1.1, 1.1, 0.86)), (37, (0, 0, 0), (1.12, 1.12, 0.84))]
    for f, loc, sc in hop:
        root.location = loc
        root.scale = sc
        root.keyframe_insert("location", frame=f)
        root.keyframe_insert("scale", frame=f)
    action = root.animation_data.action
    track = root.animation_data.nla_tracks.new()
    track.name = clip
    track.strips.new(clip, 1, action)
    root.animation_data.action = None
    bpy.context.scene.frame_end = 37
    export(col, "jumping_bean", True)


def paintball() -> None:
    # A glossy paintball with a seam, crowned by a splash of paint dripping down.
    col = reset()
    shell = material("Paintball shell", "#FF3EA5")
    seam = material("Seam", "#FFFFFF")
    paint = material("Paint splash", "#FFD23F")
    sphere(col, "Ball", shell, (0, 0, -0.05), 0.32)
    torus(col, "Seam", seam, (0, 0, -0.05), 0.322, 0.016, rot=(math.radians(18), math.radians(-24), 0))
    metaball_mesh(col, "Splash crown", paint, [
        ((0.0, 0.0, 0.25), 0.2), ((0.1, -0.06, 0.24), 0.14), ((-0.11, 0.05, 0.23), 0.13),
        ((0.02, 0.1, 0.24), 0.12), ((0.18, 0.06, 0.17), 0.09), ((-0.17, -0.07, 0.17), 0.09),
    ], resolution=0.03)
    for i, (angle, length) in enumerate(((-0.5, 0.2), (1.1, 0.27), (2.5, 0.17), (3.9, 0.23))):
        # Drips hug the ball's surface (radius 0.32 around z = -0.05) from the crown down.
        top_z, bottom_z = 0.14, 0.14 - length
        def on_surface(z: float, out: float = 0.012) -> tuple:
            r = math.sqrt(max(0.32 ** 2 - (z + 0.05) ** 2, 0.0)) + out
            return (math.cos(angle) * r, math.sin(angle) * r, z)
        capsule(col, f"Drip {i}", paint, on_surface(top_z), on_surface(bottom_z), 0.038)
        sphere(col, f"Drop {i}", paint, on_surface(bottom_z - 0.03, 0.025), 0.055, segments=16)
    export(col, "paintball", False)


def volcano() -> None:
    # A chunky rocky cone with a bubbling lava crater, lava flows and a smoke puff.
    col = reset()
    rock_mat = material("Volcano rock", "#5E4438")
    dark_rock = material("Volcano base", "#4A3A33")
    lava = material("Lava", "#FF6A1A", emission=1.2)
    hot = material("Lava hot", "#FFD34A", emission=1.5)
    smoke = material("Smoke", "#EDE6F2")
    body = cone(col, "Cone", rock_mat, (0, 0, -0.08), 0.46, 0.17, 0.62, vertices=10, smooth=False)
    rng = random.Random(9)
    for vert in body.data.vertices:
        if vert.co.z < 0.25:
            vert.co.x *= rng.uniform(0.92, 1.06)
            vert.co.y *= rng.uniform(0.92, 1.06)
    cone(col, "Base rocks", dark_rock, (0, 0, -0.42), 0.5, 0.44, 0.08, vertices=10, smooth=False)
    cone(col, "Crater lava", lava, (0, 0, 0.215), 0.15, 0.15, 0.04, vertices=16)
    sphere(col, "Lava bubble", hot, (0.04, -0.02, 0.24), 0.05, scale=(1, 1, 0.7), segments=14)
    for i, (angle, length) in enumerate(((-1.9, 0.42), (-0.9, 0.34), (2.3, 0.3))):
        direction = Vector((math.cos(angle), math.sin(angle), 0))
        top = direction * 0.15 + Vector((0, 0, 0.2))
        bottom = direction * (0.15 + length * 0.42) + Vector((0, 0, 0.2 - length))
        capsule(col, f"Lava flow {i}", lava, tuple(top), tuple(bottom), 0.035)
    for i, (loc, radius) in enumerate((((0.02, 0.0, 0.36), 0.1), ((0.12, 0.03, 0.43), 0.08),
                                       ((-0.06, 0.02, 0.45), 0.07))):
        sphere(col, f"Smoke {i}", smoke, loc, radius, segments=16)
    export(col, "volcano", False)


# --- Gift box (crate + opening reveal) ------------------------------------------------

def apply_modifiers(obj) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def join(objects, name: str):
    for obj in objects:
        apply_modifiers(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    return joined


# Box proportions (Blender units, origin at the bottom centre like gift_crate_v1, so
# config/gift_model_table.tres keeps its scale/offset): body 1.0 wide, 0.78 tall,
# lid 1.08 wide x 0.2 tall on top, bow above it.
BODY_W = 1.0
BODY_H = 0.78
LID_W = 1.08
LID_H = 0.2
RIBBON_W = 0.17
WALL = 0.09


def present(hollow: bool):
    # A cartoon wrapped present: cream paper (takes the player/hint tint overlay
    # cleanly), crossing red ribbons, a chunky bow with tails. `hollow` builds the
    # reveal body (walls + floor, so the glow core shows) and a hinged lid.
    col = reset()
    paper = material("Wrapping paper", "#FFF1D6")
    paper_shade = material("Paper inside", "#3A2E3F")
    ribbon = material("Ribbon", "#E8414F")
    knot = material("Ribbon knot", "#C42D45")
    body_parts = []
    if hollow:
        for x in (-1, 1):
            body_parts.append(box(col, f"Body wall x{x}", paper, (x * (BODY_W - WALL) / 2, 0, BODY_H / 2),
                                  (WALL, BODY_W, BODY_H), bevel=0.02))
        for y in (-1, 1):
            body_parts.append(box(col, f"Body wall y{y}", paper, (0, y * (BODY_W - WALL) / 2, BODY_H / 2),
                                  (BODY_W - 2 * WALL, WALL, BODY_H), bevel=0.02))
        body_parts.append(box(col, "Body floor", paper_shade, (0, 0, 0.04), (BODY_W - 2 * WALL, BODY_W - 2 * WALL, 0.08),
                              bevel=0.0))
    else:
        body_parts.append(box(col, "Body", paper, (0, 0, BODY_H / 2), (BODY_W, BODY_W, BODY_H), bevel=0.03))
    if hollow:
        # Thin ribbon strips on the outside of each wall keep the opening clear.
        for x in (-1, 1):
            body_parts.append(box(col, f"Wall ribbon x{x}", ribbon, (x * (BODY_W / 2 + 0.005), 0, BODY_H / 2),
                                  (0.02, RIBBON_W, BODY_H), bevel=0.0))
        for y in (-1, 1):
            body_parts.append(box(col, f"Wall ribbon y{y}", ribbon, (0, y * (BODY_W / 2 + 0.005), BODY_H / 2),
                                  (RIBBON_W, 0.02, BODY_H), bevel=0.0))
    else:
        for i in range(2):
            size = (RIBBON_W, BODY_W + 0.02, BODY_H) if i == 0 else (BODY_W + 0.02, RIBBON_W, BODY_H)
            body_parts.append(box(col, f"Body ribbon {i}", ribbon, (0, 0, BODY_H / 2), size, bevel=0.01))
    lid_parts = [box(col, "Lid", paper, (0, 0, BODY_H + LID_H / 2), (LID_W, LID_W, LID_H), bevel=0.03)]
    for i in range(2):
        size = (RIBBON_W, LID_W + 0.02, LID_H + 0.02) if i == 0 else (LID_W + 0.02, RIBBON_W, LID_H + 0.02)
        lid_parts.append(box(col, f"Lid ribbon {i}", ribbon, (0, 0, BODY_H + LID_H / 2), size, bevel=0.01))
    top = BODY_H + LID_H
    for side in (-1, 1):
        lid_parts.append(torus(col, f"Bow loop {side}", ribbon, (side * 0.19, 0, top + 0.15), 0.17, 0.065,
                               rot=(math.radians(90), math.radians(side * 28), 0), scale=(1.0, 1.0, 0.75)))
        lid_parts.append(box(col, f"Bow tail {side}", ribbon, (side * 0.16, -0.12, top + 0.01), (0.11, 0.26, 0.03),
                             rot=(0, 0, math.radians(side * 35)), bevel=0.01))
    lid_parts.append(sphere(col, "Bow knot", knot, (0, 0, top + 0.09), 0.1, scale=(1.0, 0.9, 0.85), segments=18))
    if not hollow:
        export(col, "gift_crate", False)
        return
    body = join(body_parts, "Crate body / hollow")
    lid = join(lid_parts, "Crate lid / hinged")
    scene = bpy.context.scene
    scene.cursor.location = (0, LID_W / 2, BODY_H)
    bpy.ops.object.select_all(action="DESELECT")
    lid.select_set(True)
    bpy.context.view_layer.objects.active = lid
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    root = empty(col, "Gift crate reveal root")
    body.parent = root
    lid.parent = root
    clip = "open_reveal_1s"
    for frame, angle in ((1, 0), (5, -6), (12, -115), (19, -104), (25, -110)):
        lid.rotation_euler.x = math.radians(angle)
        lid.keyframe_insert(data_path="rotation_euler", frame=frame)
    action = lid.animation_data.action
    track = lid.animation_data.nla_tracks.new()
    track.name = clip
    track.strips.new(clip, 1, action)
    lid.animation_data.action = None
    scene.frame_end = 25
    export(col, "gift_crate_reveal", True)


def gift_crate() -> None:
    present(False)


def gift_crate_reveal() -> None:
    present(True)


MODELS = {
    "earthquake": earthquake,
    "black_hole": black_hole,
    "jumping_bean": jumping_bean,
    "paintball": paintball,
    "volcano": volcano,
    "gift_crate": gift_crate,
    "gift_crate_reveal": gift_crate_reveal,
}

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for model_id in args or list(MODELS):
        MODELS[model_id]()
