"""Read exported GLB geometry and native render evidence; create review layouts."""
import hashlib,json,math,struct
from collections import Counter
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/models/horizon_islands_v1';REVIEW=ROOT/'docs/art_mockups/horizon_islands_v1';NATIVE=REVIEW/'native'
def read_glb(path):
 blob=path.read_bytes();assert blob[:4]==b'glTF';size=struct.unpack_from('<I',blob,12)[0];meta=json.loads(blob[20:20+size]);pos=20+size
 bsize,kind=struct.unpack_from('<II',blob,pos);assert kind==0x004e4942;binary=blob[pos+8:pos+8+bsize]
 return meta,binary
def accessor(meta,binary,index):
 a=meta['accessors'][index];v=meta['bufferViews'][a['bufferView']];shape={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']];code={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];fmt='<'+code*shape;stride=v.get('byteStride',struct.calcsize(fmt));start=v.get('byteOffset',0)+a.get('byteOffset',0)
 return [struct.unpack_from(fmt,binary,start+i*stride) for i in range(a['count'])]
def verify():
 evidence=[]
 for name in ('mesa','shelf','crag'):
  meta,binary=read_glb(OUT/(name+'.glb'));assert not meta.get('animations') and not meta.get('textures')
  assert {n['name'] for n in meta['nodes']}=={'LOD0','LOD1','LOD2'}
  counts=[]
  for mesh in meta['meshes']:
   edges=Counter();triangles=0
   for primitive in mesh['primitives']:
    v=accessor(meta,binary,primitive['attributes']['POSITION']);n=accessor(meta,binary,primitive['attributes']['NORMAL']);c=accessor(meta,binary,primitive['attributes']['COLOR_0']);idx=[x[0] for x in accessor(meta,binary,primitive['indices'])]
    assert len(n)==len(c)==len(v) and len(idx)%3==0
    assert all(all(math.isfinite(x) for x in p) for p in v+n)
    assert all(abs(sum(x*x for x in p)-1)<.001 for p in n)
    for k in range(0,len(idx),3):
     a,b,d=[tuple(round(x,5) for x in v[idx[k+t]]) for t in range(3)]
     assert len({a,b,d})==3
     cross=np.cross(np.array(b)-a,np.array(d)-a);assert np.linalg.norm(cross)>.0001
     for first,second in ((a,b),(b,d),(d,a)):edges[tuple(sorted((first,second)))]+=1
     triangles+=1
   assert all(v==2 for v in edges.values()),'mesh not closed after position weld'
   counts.append(triangles)
  assert counts==[320,96,32]
  comparisons=[]
  for yaw in (0,60,120):
   masks=[]
   for lod in range(3):
    img=Image.open(NATIVE/('%s_yaw%d_lod%d.png'%(name,yaw,lod))).convert('RGB');assert img.size==(1280,720)
    a=np.array(img).astype(int);masks.append(np.max(abs(a-a[0,0]),axis=2)>6)
    assert masks[-1].sum()>1000
   scores=[float(np.logical_and(masks[0],masks[k]).sum()/np.logical_or(masks[0],masks[k]).sum()) for k in (1,2)]
   assert scores[0]>.95 and scores[1]>.85,(name,yaw,scores)
   comparisons.append({'yaw':yaw,'lod1_iou':scores[0],'lod2_iou':scores[1]})
  evidence.append({'id':name,'triangles':counts,'watertight_position_weld':True,'normals_and_colors':True,'render_silhouette_iou':comparisons})
 for kind in ('multiview','lod_comparison'):
  sheet=Image.new('RGB',(1200,786),(25,32,48));draw=ImageDraw.Draw(sheet)
  for row,name in enumerate(('mesa','shelf','crag')):
   for col in range(3):
    yaw=[0,60,120][col] if kind=='multiview' else 60;lod=0 if kind=='multiview' else col
    draw.text((col*400+12,row*262+12),'%s | yaw%d | LOD%d'%(name,yaw,lod),fill='white')
    image=Image.open(NATIVE/('%s_yaw%d_lod%d.png'%(name,yaw,lod))).convert('RGB').resize((400,225),Image.Resampling.LANCZOS)
    sheet.paste(image,(col*400,row*262+32))
  sheet.save(REVIEW/(kind+'.png'))
 cloudsheet=Image.new('RGB',(1280,1152),(25,32,48));draw=ImageDraw.Draw(cloudsheet)
 for row,(label,file) in enumerate((('Neutral haze / 3D occluders','cloud_orbit_04.png'),('Sunset palette example','cloud_sunset.png'),('Night palette example','cloud_night.png'))):
  draw.text((12,row*384+12),label+' | isolated asset stage, not gameplay sky',fill='white')
  cloudsheet.paste(Image.open(NATIVE/file).resize((640,360),Image.Resampling.LANCZOS),(320,row*384+24))
 cloudsheet.save(REVIEW/'cloud_review.png')
 frames=[Image.open(NATIVE/('cloud_orbit_%02d.png'%i)).convert('RGB').resize((640,360),Image.Resampling.LANCZOS) for i in list(range(9))+list(range(7,0,-1))]
 frames[0].save(REVIEW/'camera_motion.gif',save_all=True,append_images=frames[1:],duration=120,loop=0,disposal=2)
 (REVIEW/'verification.json').write_text(json.dumps({'checks':'3closed colored meshes x3LODs;unit normals;nondegenerate triangles;LOD1 silhouetteIoU>.95 andLOD2>.85 at3angles; native mesh colors/pivots','variants':evidence},indent=2)+'\n')
 print('Island geometry,9LOD meshes,27native angle renders and silhouette comparison PASS')
if __name__=='__main__':verify()
