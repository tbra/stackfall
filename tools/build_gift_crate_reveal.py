"""Blender --source <gift_crate_v1.blend>; Python --assemble makes review."""
from pathlib import Path
import json
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/gift_crate_reveal_v1"
SOURCE = ROOT / "source_art/gift_crate_reveal_v1"
TEMP = Path(tempfile.gettempdir()) / "codex_gift_crate_reveal"


def verify():
    import math
    import struct
    from PIL import Image, ImageSequence
    path = OUT / "gift_crate_reveal_v1.glb"
    raw = path.read_bytes()
    assert struct.unpack_from("<4sII",raw) == (b"glTF",2,len(raw))
    size,kind = struct.unpack_from("<II",raw,12)
    assert kind == 0x4E4F534A
    document = json.loads(raw[20:20+size])
    binary_size,binary_kind = struct.unpack_from("<II",raw,20+size)
    assert binary_kind == 0x004E4942
    binary = raw[28+size:28+size+binary_size]
    assert len(document["meshes"]) == 2 and len(document["materials"]) == 5
    assert len(document["animations"]) == 1
    assert not document.get("cameras") and not document.get("extensions",{}).get("KHR_lights_punctual")
    clip = document["animations"][0]
    assert len(clip["channels"]) == 1
    channel = clip["channels"][0]
    assert channel["target"]["path"] == "rotation"
    assert document["nodes"][channel["target"]["node"]]["name"] == "Crate lid / hinged"
    sampler = clip["samplers"][channel["sampler"]]
    def values(index):
        accessor = document["accessors"][index]
        view = document["bufferViews"][accessor["bufferView"]]
        assert accessor["componentType"] == 5126
        width = {"SCALAR":1,"VEC4":4}[accessor["type"]]
        offset = view.get("byteOffset",0)+accessor.get("byteOffset",0)
        stride = view.get("byteStride",width*4)
        return [struct.unpack_from("<"+"f"*width,binary,offset+i*stride) for i in range(accessor["count"])]
    times = [item[0] for item in values(sampler["input"])]
    rotations = values(sampler["output"])
    assert all(b>=a for a,b in zip(times,times[1:]))
    assert all(abs(sum(v*v for v in q)-1)<.00001 for q in rotations)
    angle = math.degrees(2*math.acos(min(1,abs(sum(a*b for a,b in zip(rotations[0],rotations[-1]))))))
    assert abs(angle-110)<.001
    gif = Image.open(OUT / "opening_review.gif")
    frames = [image.copy() for image in ImageSequence.Iterator(gif)]
    assert len(frames) == 25 and all(frame.size==(384,384) for frame in frames)
    report = {"glb_bytes":len(raw),"mesh_count":2,"material_count":5,
        "triangles":sum(document["accessors"][p["indices"]]["count"]//3
                        for mesh in document["meshes"] for p in mesh["primitives"]),
        "clip_name":clip.get("name"),"clip_time_range_seconds":[times[0],times[-1]],
        "rotation_samples":len(rotations),"start_to_end_angle_degrees":angle,
        "gif_frames":len(frames),"gif_preview_has_endpoint_holds":True}
    (OUT / "glb_review.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report,indent=2))


def assemble():
    from PIL import Image, ImageDraw
    images = [Image.open(TEMP / f"frame_{i:02}.png").convert("RGB") for i in range(1,26)]
    assert all(image.size == (384,384) for image in images)
    images[0].save(OUT / "opening_review.gif",save_all=True,append_images=images[1:],
                   duration=[500]+[40]*23+[900],loop=0,disposal=2,optimize=False)
    sheet = Image.new("RGB",(768,824),"#182832")
    draw = ImageDraw.Draw(sheet)
    for cell,index in enumerate((0,7,12,24)):
        x,y = cell%2*384,cell//2*412
        sheet.paste(images[index],(x,y))
        draw.text((x+8,y+392),f"frame {index+1} / {index/24:.2f}s",fill="#eee8d9")
    sheet.save(OUT / "opening_contact_sheet.png")
    print("25-frame opening GIF and four-pose sheet assembled")


def build():
    import bpy
    from math import radians
    from mathutils import Vector
    assert "--source" in sys.argv
    bpy.ops.wm.open_mainfile(filepath=sys.argv[sys.argv.index("--source")+1])
    collection = bpy.data.collections["Crate export"]
    original_bounds = [obj.matrix_world @ Vector(corner)
                       for obj in collection.objects for corner in obj.bound_box]
    original_low = [min(point[i] for point in original_bounds) for i in range(3)]
    original_high = [max(point[i] for point in original_bounds) for i in range(3)]
    old_body = bpy.data.objects["Crate / warm body"]
    paper = old_body.data.materials[0]
    ink = bpy.data.objects["Crate / shadow plinth"].data.materials[0]
    bpy.data.objects.remove(old_body,do_unlink=True)
    def box(name,location,dimensions,material,bevel):
        bpy.ops.mesh.primitive_cube_add(size=1,location=location)
        obj = bpy.context.object
        obj.name = name
        obj.dimensions = dimensions
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        modifier = obj.modifiers.new("Broad cel edge","BEVEL")
        modifier.width,modifier.segments = bevel,1
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.data.materials.append(material)
        for owner in list(obj.users_collection):
            owner.objects.unlink(obj)
        collection.objects.link(obj)
    for x in (-.405,.405):
        box(f"Crate / hollow side {x}",(x,0,.52),(.1,.91,.68),paper,.015)
    for y in (-.405,.405):
        box(f"Crate / hollow end {y}",(0,y,.52),(.71,.1,.68),paper,.015)
    box("Crate / interior floor",(0,0,.215),(.72,.72,.03),ink,.008)
    lid_parts = [obj for obj in collection.objects if obj.name.startswith("Crate / lid")]
    static_parts = [obj for obj in collection.objects if obj not in lid_parts]
    def join(objects,name):
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = name
        return obj
    body = join(static_parts,"Crate body / hollow")
    lid = join(lid_parts,"Crate lid / hinged")
    scene = bpy.context.scene
    scene.cursor.location = (0,.555,.92)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    root = bpy.data.objects.new("Gift crate reveal root",None)
    collection.objects.link(root)
    body.parent = lid.parent = root
    for frame,angle in ((1,0),(5,-6),(12,-115),(19,-104),(25,-110)):
        lid.rotation_euler.x = radians(angle)
        lid.keyframe_insert(data_path="rotation_euler",frame=frame)
    action = lid.animation_data.action
    action.name = "open_reveal_1s"
    track = lid.animation_data.nla_tracks.new()
    track.name = "open_reveal_1s"
    track.strips.new("open_reveal_1s",1,action)
    lid.animation_data.action = None
    scene.render.fps = 24
    scene.frame_start,scene.frame_end = 1,25
    scene.render.resolution_x = scene.render.resolution_y = 384
    camera = scene.camera
    camera.location = (2.6,-3.3,2.5)
    camera.rotation_euler = (Vector((0,0,.95))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.ortho_scale = 3.0
    scene.frame_set(1)
    bpy.context.view_layer.update()
    bounds = [root.matrix_world.inverted() @ obj.matrix_world @ Vector(corner)
              for obj in (body,lid) for corner in obj.bound_box]
    low = [min(point[i] for point in bounds) for i in range(3)]
    high = [max(point[i] for point in bounds) for i in range(3)]
    assert abs(low[2]) < .001, f"Bottom offset {low}"
    assert max(abs(a-b) for a,b in zip(low+high,original_low+original_high)) < .001, f"Closed bounds changed: {low,high} vs {original_low,original_high}"
    scene.frame_set(25)
    assert abs(lid.rotation_euler.x-radians(-110)) < .00001
    scene.frame_set(1)
    assert abs(lid.rotation_euler.x) < .00001
    OUT.mkdir(parents=True,exist_ok=True)
    SOURCE.mkdir(parents=True,exist_ok=True)
    TEMP.mkdir(parents=True,exist_ok=True)
    (SOURCE / ".gdignore").write_text("")
    (OUT / "geometry_review.json").write_text(json.dumps({
        "closed_bounds_blender_min":low,"closed_bounds_blender_max":high,
        "origin":"bottom center", "mesh_groups":[body.name,lid.name],
        "hinge_blender_xyz":[0,.555,.92],"clip_seconds":1,
        "final_lid_degrees":-110,"playback":"one shot, hold final pose"
    },indent=2)+"\n")
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "gift_crate_reveal_v1.blend"))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=str(OUT / "gift_crate_reveal_v1.glb"),export_format="GLB",
        use_selection=True,export_cameras=False,export_lights=False,
        export_animations=True,export_animation_mode="NLA_TRACKS")
    for frame in range(1,26):
        scene.frame_set(frame)
        scene.render.filepath = str(TEMP / f"frame_{frame:02}.png")
        bpy.ops.render.render(write_still=True)
    print("Hollow gift crate and one-shot lid reveal rendered")


if __name__ == "__main__":
    if "--verify" in sys.argv:
        verify()
    elif "--assemble" in sys.argv:
        assemble()
    else:
        build()
