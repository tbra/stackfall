"""Inspect the native 5-shape x 3-theme loading plate set and artwork crops."""
from pathlib import Path
import json
import hashlib
import re
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'assets/ui/loading_arena_v2'
OUT=ROOT/'docs/art_mockups/loading_arena_v2'
OUT.mkdir(parents=True,exist_ok=True)
manifest=json.loads((ART/'manifest.json').read_text())
enum=re.search(r'enum MapVariant\s*\{([^}]+)\}',(ROOT/'config/MatchConfig.gd').read_text()).group(1)
shapes=[name.strip().lower() for name in enum.split(',')]
themes=['sunset','night','dawn']
expected={(shape,theme) for shape in shapes for theme in themes}
assert {(p['shape'],p['theme']) for p in manifest['plates']}==expected
assert len(manifest['plates'])==len(expected)==15
font=ImageFont.truetype(str(ROOT/'assets/ui/fonts/Manrope-Regular.ttf'),15)
images={};hashes=set()
for plate in manifest['plates']:
    path=ART/plate['filename']; image=Image.open(path).convert('RGB')
    assert image.size==(1920,1080)==tuple(plate['native_size'])
    assert plate['map_variant']==shapes.index(plate['shape'])
    assert plate['map_resource'].endswith('%s_medium.tres'%plate['shape'])
    assert plate['capture_geometry']==('analytic_shape' if plate['map_variant']>=2 else 'game_default')
    assert len(image.getcolors(image.width*image.height))>1000
    digest=hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest not in hashes,plate['filename']
    hashes.add(digest)
    images[(plate['shape'],plate['theme'])]=image
sheet=Image.new('RGB',(1200,1250),'#26323a');draw=ImageDraw.Draw(sheet)
for row,shape in enumerate(shapes):
    for col,theme in enumerate(themes):
        x,y=col*400,row*250
        draw.text((x+8,y+4),'%s / %s'%(shape.capitalize(),theme.capitalize()),font=font,fill='#f5ebd6')
        sheet.paste(images[(shape,theme)].resize((400,225),Image.Resampling.LANCZOS),(x,y+25))
sheet.save(OUT/'all_shapes.png')

sheet=Image.new('RGB',(1800,1500),'#26323a');draw=ImageDraw.Draw(sheet)
sizes=[(1280,720),(1920,1080),(2560,1440),(3440,1440),(720,1280)]
for row,shape in enumerate(shapes):
    for col,size in enumerate(sizes):
        x,y=col*360,row*300
        draw.text((x+8,y+4),'%s %s x %s'%(shape.capitalize(),*size),font=font,fill='#f5ebd6')
        crop=ImageOps.fit(images[(shape,'sunset')],size,Image.Resampling.LANCZOS)
        assert crop.size==size
        crop.thumbnail((352,268),Image.Resampling.LANCZOS)
        sheet.paste(crop,(x+(360-crop.width)//2,y+28+(268-crop.height)//2))
sheet.save(OUT/'crop_review.png')
print('All15 distinct native1920x1080 plates/enum IDs/map resources PASS; contact and cover crop proofs saved')
