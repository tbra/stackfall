"""Blender4.5: original seeded floating horizon islands and two silhouette LODs."""
import bpy,math,json,random,struct,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/models/horizon_islands_v1';SRC=ROOT/'source_art/horizon_islands_v1'
OUT.mkdir(parents=True,exist_ok=True);SRC.mkdir(parents=True,exist_ok=True);(SRC/'.gdignore').write_text('')
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version=0
SPECS=[('mesa',30,19,32,0),('shelf',44,14,23,1),('crag',21,25,43,2)]
PAL=[(.49,.57,.56,1),(.50,.52,.62,1),(.37,.40,.50,1),(.29,.33,.43,1)]
material=bpy.data.materials.new('Horizon island neutral cel fallback');material.diffuse_color=PAL[1];material.use_nodes=True
nodes=material.node_tree.nodes;bsdf=nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=1;bsdf.inputs['Specular IOR Level'].default_value=0
color=nodes.new('ShaderNodeVertexColor');color.layer_name='CelColor';material.node_tree.links.new(color.outputs['Color'],bsdf.inputs['Base Color'])
report=[]
def build(name,rx,ry,depth,style,lod):
 n=[32,16,8][lod];fractions=[[0,.10,.36,.69,.91],[0,.36,.91],[0,.91]][lod]
 seed=11200+style;rng=random.Random(seed);phase=rng.uniform(0,math.tau)
 rings=[]
 for level,f in enumerate(fractions):
  ring=[]
  for j in range(n):
   a=j*math.tau/n
   irregular=1+.075*math.sin(3*a+phase)+.055*math.cos(5*a-phase)
   if style==1:irregular+=.07*math.sin(2*a+.8)
   taper=(1-f)**.65
   # Broad overhang and tapering buttresses; no thin needle root.
   taper=max(.14,taper);offsetx=rx*.16*f;offsety=-ry*.12*f
   z=-depth*f
   ring.append((math.cos(a)*rx*irregular*taper+offsetx,math.sin(a)*ry*irregular*taper+offsety,z))
  rings.append(ring)
 tris=[];colors=[]
 def tri(a,b,c,tint):
  tris.append((a,b,c));colors.append(tint)
 center=(0,0,.45)
 for j in range(n):tri(center,rings[0][j],rings[0][(j+1)%n],PAL[0])
 for k in range(len(rings)-1):
  for j in range(n):
   q=(j+1)%n
   # Large facet tone variation is angular, shared across LODs.
   index=1 if math.cos(j*math.tau/n+phase)>.30 else (2 if math.cos(j*math.tau/n+phase)>-.60 else 3)
   tint=PAL[index]
   tri(rings[k][j],rings[k+1][j],rings[k+1][q],tint);tri(rings[k][j],rings[k+1][q],rings[k][q],tint)
 bottom=(rx*.16,-ry*.12,-depth)
 for j in range(n):tri(bottom,rings[-1][(j+1)%n],rings[-1][j],PAL[3])
 vertices=[v for t in tris for v in t];faces=[(i,i+1,i+2) for i in range(0,len(vertices),3)]
 mesh=bpy.data.meshes.new(name+'_LOD%d_mesh'%lod);mesh.from_pydata(vertices,[],faces);mesh.update()
 colorset=mesh.color_attributes.new(name='CelColor',type='FLOAT_COLOR',domain='CORNER')
 for i,p in enumerate(mesh.polygons):
  p.use_smooth=False
  for loop in p.loop_indices:colorset.data[loop].color=colors[i]
 obj=bpy.data.objects.new('LOD%d'%lod,mesh);bpy.context.scene.collection.objects.link(obj);obj.data.materials.append(material)
 obj['island_id']=name;obj['lod']=lod;obj['surface_pivot']='Top surface center, Blender Z-up; exported Godot Y-up';obj['nominal_dimensions_m']=[rx*2,depth,ry*2]
 return obj,len(tris)
for name,rx,ry,depth,style in SPECS:
 objs=[];counts=[]
 for lod in range(3):
  obj,count=build(name,rx,ry,depth,style,lod);objs.append(obj);counts.append(count)
 bpy.ops.object.select_all(action='DESELECT')
 for obj in objs:obj.select_set(True)
 bpy.context.view_layer.objects.active=objs[0]
 dest=OUT/(name+'.glb');bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',use_selection=True,export_animations=False,export_cameras=False,export_lights=False,export_yup=True)
 blob=dest.read_bytes();length=struct.unpack_from('<I',blob,12)[0];gltf=json.loads(blob[20:20+length])
 actual=[sum(gltf['accessors'][p['indices']]['count']//3 for p in m['primitives']) for m in gltf['meshes']]
 assert actual==counts,(name,actual,counts)
 assert all('COLOR_0' in p['attributes'] for m in gltf['meshes'] for p in m['primitives'])
 bounds={}
 for lod,obj in enumerate(objs):
  v=[tuple(p.co) for p in obj.data.vertices];bounds['LOD%d'%lod]={'min_blender':[min(p[k] for p in v) for k in range(3)],'max_blender':[max(p[k] for p in v) for k in range(3)]}
 report.append({'id':name,'file':dest.name,'triangles_by_lod':counts,'sha256':hashlib.sha256(blob).hexdigest(),'bytes':len(blob),'bounds':bounds,'nominal_width_depth_height_m':[rx*2,ry*2,depth],'lod_triangle_reduction':[1-counts[i]/counts[0] for i in range(3)]})
 # Keep editable collections separated; all assets stay at origin in their GLB.
 collection=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(collection)
 for obj in objs:
  for c in list(obj.users_collection):c.objects.unlink(obj)
  collection.objects.link(obj)
  obj.hide_render=obj.name!='LOD0';obj.hide_viewport=obj.name!='LOD0'
  # Restore consistent node names after Blender's global-name uniqueness suffixing.
  obj.name=name+'_LOD'+str(obj['lod'])
bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=True,do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'horizon_islands_v1.blend'))
(OUT/'geometry.json').write_text(json.dumps({'version':1,'generator':'tools/generate_horizon_islands.py','units':'meters; default render camera is art review only','pivot':'surface center at origin; rock body extends down','variants':report,'color_semantics':'COLOR_0 contains original neutral facet palette; no player/team state','animation':'none; static world assets, camera supplies parallax'},indent=2)+'\n')
print('3 original horizon islands, each with LOD0/LOD1/LOD2; triangles',[(r['id'],r['triangles_by_lod']) for r in report])
