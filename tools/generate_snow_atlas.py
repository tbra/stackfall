"""Original cel snow atlas; standard-library vector generation, Pillow review."""
import argparse, hashlib, json, math, random
from pathlib import Path
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'source_art/snow_atlas_v1'
OUT = ROOT / 'assets/vfx/snow_atlas_v1'
REVIEW = ROOT / 'docs/art_mockups/snow_atlas_v1'
NAMES = ['crystal_broad','crystal_short','crystal_split','crystal_star','crystal_long','crystal_compact','crystal_tilted','crystal_uneven','clump_round','clump_flat','clump_twin','clump_diamond','clump_long','clump_chunky','clump_soft','clump_scattered']
def svg(body, size=128):
    return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>' % (size,size,size,size,body)
def polygon(points):
    return ' '.join('%.3f,%.3f' % p for p in points)
def tile(i):
    rng = random.Random(10600+i)
    if i < 8:
        # Filled broad spokes; no tiny ornamental branches needed for particles.
        pts=[]
        rotation = math.radians([0,15,30,8,22,0,40,12][i])
        for k in range(24):
            a=rotation+k*math.pi/12
            radii=[39+i%3*2, 16, 21, 16]
            r=radii[k%4]*(rng.uniform(.92,1.06) if i==7 else 1)
            pts.append((64+math.cos(a)*r,64+math.sin(a)*r))
    else:
        count = [10,9,12,6,10,11,13,12][i-8]
        pts=[]
        sx=[1,.99,1.03,.93,1.1,.96,1,1][i-8]
        sy=[1,.72,.88,1,.73,.95,.91,.94][i-8]
        for k in range(count):
            a=-math.pi/2+k*2*math.pi/count
            r=rng.uniform(28,40)
            if i==10 and k%3==1: r*=.68
            if i==15 and k%2: r*=.72
            pts.append((64+math.cos(a)*r*sx,64+math.sin(a)*r*sy))
    p=polygon(pts)
    # Translucent outer rim plus opaque core border, raster AA supplies edge softness.
    body='<polygon points="%s" fill="none" stroke="#56627c" stroke-opacity=".18" stroke-width="11" stroke-linejoin="round"/>'%p
    body+='<polygon points="%s" fill="#f7f9ff" stroke="#56627c" stroke-opacity=".78" stroke-width="6" stroke-linejoin="round"/>'%p
    # A broad cool facet clipped to the actual silhouette.
    body+='<defs><clipPath id="facet%d"><polygon points="%s"/></clipPath></defs>'%(i,p)
    body+='<g clip-path="url(#facet%d)"><polygon points="34,91 64,62 97,72 105,103 34,111" fill="#cbd4eb"/><polygon points="37,80 62,63 54,29 37,27" fill="#e5ebf8"/></g>'%i
    # Restore border on top so the clipped facet cannot cover the silhouette rim.
    body+='<polygon points="%s" fill="none" stroke="#56627c" stroke-opacity=".78" stroke-width="6" stroke-linejoin="round"/>'%p
    return body

def generate():
    for p in (SRC,OUT,REVIEW):p.mkdir(parents=True,exist_ok=True)
    (SRC/'.gdignore').write_text('',encoding='utf8')
    (REVIEW/'.gdignore').write_text('',encoding='utf8')
    bodies=[]; records=[]
    for i,name in enumerate(NAMES):
        body=tile(i); (SRC/(name+'.svg')).write_text(svg(body),encoding='utf8')
        x,y=i%4*128,i//4*128
        bodies.append('<g transform="translate(%d,%d)">%s</g>'%(x,y,body))
        records.append({'index':i,'id':name,'cell':[i%4,i//4], 'region_px':[x,y,128,128], 'uv_rect':[x/512,y/512,.25,.25], 'kind':'flake' if i<8 else 'clump'})
    (SRC/'atlas.svg').write_text(svg(''.join(bodies),512),encoding='utf8')
    manifest={'version':1,'file':'snow_atlas.png','size':[512,512],'grid':[4,4],'cell_size':[128,128],'order':'row-major, top-left origin','seed_base':10600,'tiles':records}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8')
    print('16 original vector variants generated')

def review(native):
    atlas=Image.open(native/'atlas_512.png').convert('RGBA')
    assert atlas.size==(512,512)
    hashes=[]
    for i,name in enumerate(NAMES):
        x,y=i%4*128,i//4*128
        cell=atlas.crop((x,y,x+128,y+128)); bbox=cell.getchannel('A').getbbox()
        assert bbox and min(bbox[0],bbox[1],128-bbox[2],128-bbox[3])>=14,(name,bbox)
        hashes.append(hashlib.sha256(cell.tobytes()).hexdigest())
        for size in (8,16,32,128):
            image=Image.open(native/('%s_%d.png'%(name,size))).convert('RGBA')
            assert image.size==(size,size)
            alpha=image.getchannel('A')
            assert alpha.getbbox() and alpha.getextrema()[1]>230,(name,size)
            assert max(alpha.crop((0,0,size,1)).getdata())==0
            assert max(alpha.crop((0,size-1,size,size)).getdata())==0
            assert max(alpha.crop((0,0,1,size)).getdata())==0
            assert max(alpha.crop((size-1,0,size,size)).getdata())==0
        assert cell.tobytes()==Image.open(native/('%s_128.png'%name)).convert('RGBA').tobytes()
    assert len(set(hashes))==16
    atlas.save(OUT/'snow_atlas.png')
    # Real rendered game plate; fixed source regions keep sky/disc backgrounds honest.
    plate=Image.open(ROOT/'assets/ui/loading_arena_v2/round_dawn.png').convert('RGBA')
    sky=plate.crop((100,60,700,530)).resize((600,470),Image.Resampling.LANCZOS)
    disc=plate.crop((885,800,1185,950)).resize((600,300),Image.Resampling.LANCZOS)
    sheet=Image.new('RGBA',(1200,1110),(28,33,47,255));d=ImageDraw.Draw(sheet)
    d.text((24,14),'SNOW ATLAS v1 | 16 original variants | native Godot SVG raster',fill='white')
    for i,name in enumerate(NAMES):
        x=24+(i%8)*146;y=48+(i//8)*185
        d.rectangle((x,y,x+130,y+135),fill=(56,65,84))
        cell=Image.open(native/(name+'_128.png')).convert('RGBA');sheet.alpha_composite(cell,(x+1,y+2))
        d.text((x,y+141),'%02d %s'%(i,name.replace('crystal_','').replace('clump_','')),fill='white')
        for k,size in enumerate((8,16,32)):
            sheet.alpha_composite(Image.open(native/('%s_%d.png'%(name,size))).convert('RGBA'),(x+k*39,y+156))
    sheet.alpha_composite(sky,(0,452));sheet.alpha_composite(sky,(600,452))
    sheet.alpha_composite(disc,(0,808));sheet.alpha_composite(disc,(600,808))
    d=ImageDraw.Draw(sheet)
    d.rectangle((0,420,1200,451),fill=(28,33,47));d.text((24,430),'REAL DAWN SKY | left: 32px tiles, right: 16px tiles, native screen sizes',fill='white')
    d.rectangle((0,776,1200,807),fill=(28,33,47));d.text((24,786),'REAL DARK DISC | left: 32px tiles, right: 16px tiles',fill='white')
    for i,name in enumerate(NAMES):
        for side,size in ((0,32),(1,16)):
            for top,spacing in ((475,65),(843,55)):
                x=45+(i%4)*135+side*600;y=top+(i//4)*spacing
                sheet.alpha_composite(Image.open(native/('%s_%d.png'%(name,size))).convert('RGBA'),(x,y))
    sheet.convert('RGB').save(REVIEW/'review.png')
    report={'checks':'512 RGBA;16 nonempty unique cells;14px+ transparent padding;cell and individual raster exact match;8/16/32/128 native rasters with clear outer edges','atlas_sha256':hashlib.sha256((OUT/'snow_atlas.png').read_bytes()).hexdigest(),'tile_rgba_sha256':hashes}
    (REVIEW/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print(report['checks']+' PASS')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--review-native',type=Path);a=parser.parse_args()
    review(a.review_native) if a.review_native else generate()
