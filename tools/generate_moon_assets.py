"""Original vector cel moon and native-raster review; no external art sources."""
import argparse, hashlib, json, math, random
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'source_art/moon_v1';OUT=ROOT/'assets/sky/moon_v1';REVIEW=ROOT/'docs/art_mockups/moon_v1'
def svg(body):
    return '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'+body+'</svg>'
def poly(cx,cy,rx,ry,count,rng):
    return ' '.join('%.2f,%.2f'%(cx+math.cos(k*math.tau/count)*rx*rng.uniform(.86,1.08),cy+math.sin(k*math.tau/count)*ry*rng.uniform(.86,1.08)) for k in range(count))
def generate():
    for p in (SRC,OUT,REVIEW):p.mkdir(parents=True,exist_ok=True)
    for p in (SRC,REVIEW):(p/'.gdignore').write_text('')
    rng=random.Random(10701)
    body='<defs><clipPath id="disc"><circle cx="512" cy="512" r="400"/></clipPath></defs>'
    body+='<circle cx="512" cy="512" r="400" fill="#e8eefb"/>'
    body+='<g clip-path="url(#disc)">'
    # Broad spherical cel light bands; restrained maria are terrain, not rim outlines.
    body+='<path d="M 611 104 C 822 197 928 425 868 654 C 823 826 641 925 439 917 C 646 784 733 587 720 415 C 711 290 674 189 611 104 Z" fill="#b9c9e5"/>'
    body+='<path d="M 784 228 C 920 395 950 665 787 816 C 717 883 606 922 493 919 C 749 789 837 513 784 228 Z" fill="#879fc7"/>'
    for cx,cy,rx,ry in [(380,366,98,63),(485,448,80,100),(343,496,69,54),(619,616,94,58),(695,353,64,43),(455,717,44,28)]:
        body+='<polygon points="%s" fill="#aebfda"/>'%poly(cx,cy,rx,ry,13,rng)
        body+='<polygon points="%s" fill="#c4d1e7"/>'%poly(cx-9,cy-12,rx*.66,ry*.61,10,rng)
    for cx,cy,r in [(558,269,28),(301,618,22),(630,758,35),(762,537,18),(437,565,14),(289,296,16)]:
        body+='<circle cx="%d" cy="%d" r="%d" fill="#c2d0e6"/>'%(cx,cy,r)
        body+='<path d="M %d %d Q %d %d %d %d" fill="none" stroke="#f3f6ff" stroke-width="8" stroke-linecap="round"/>'%(cx-r,cy,cx,cy+r,cx+r,cy)
    body+='</g>'
    (SRC/'moon_disc.svg').write_text(svg(body),encoding='utf8')
    halo='<defs><radialGradient id="halo"><stop offset="0" stop-color="#90b3f0" stop-opacity=".28"/><stop offset=".20" stop-color="#90b3f0" stop-opacity=".25"/><stop offset=".40" stop-color="#90b3f0" stop-opacity=".17"/><stop offset=".65" stop-color="#90b3f0" stop-opacity=".065"/><stop offset=".86" stop-color="#90b3f0" stop-opacity=".014"/><stop offset="1" stop-color="#90b3f0" stop-opacity="0"/></radialGradient></defs><circle cx="512" cy="512" r="480" fill="url(#halo)"/>'
    (SRC/'moon_halo.svg').write_text(svg(halo),encoding='utf8')
    manifest={'version':1,'size':[1024,1024],'center_px':[512,512],'disc_radius_px':400,'halo_radius_px':480,'files':['moon_disc.png','moon_halo.png'],'phase':'full, optional runtime phase mask','palette':{'lit':'#e8eefb','mid':'#b9c9e5','shade':'#879fc7','halo':'#90b3f0'},'seed':10701,'preview':{'source':'assets/ui/loading_arena_v2/round_night.png','screen_size':[1280,720],'center':[960,145],'disc_quad_size':96,'halo_quad_size':432}}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Original moon disc and soft halo SVG sources generated')
def review(native):
    from PIL import ImageStat
    rasters={}
    for name in ('moon_disc','moon_halo'):
        p=Image.open(native/(name+'_1024.png')).convert('RGBA');assert p.size==(1024,1024)
        a=p.getchannel('A');box=a.getbbox();assert box and min(box[0],box[1],1024-box[2],1024-box[3])>=32
        for edge in ((0,0,1024,1),(0,1023,1024,1024),(0,0,1,1024),(1023,0,1024,1024)):
            assert max(a.crop(edge).getdata())==0
        assert a.getpixel((512,512))==(255 if name=='moon_disc' else a.getextrema()[1])
        rasters[name]=p;p.save(OUT/(name+'.png'))
    # Halo has a monotonic transparent falloff along each cardinal radius.
    halo=rasters['moon_halo'].getchannel('A')
    for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
        values=[halo.getpixel((512+dx*r,512+dy*r)) for r in range(0,500)]
        assert all(b<=a for a,b in zip(values,values[1:])),(dx,dy)
        assert values[-1]==0
    for name in rasters:
        for size in (64,128):
            p=Image.open(native/('%s_%d.png'%(name,size))).convert('RGBA');assert p.size==(size,size)
            assert p.getchannel('A').getbbox()
    plate=Image.open(ROOT/'assets/ui/loading_arena_v2/round_night.png').convert('RGBA').resize((1280,720),Image.Resampling.LANCZOS)
    def overlay(image, size, center):
        raster=image.resize((size,size),Image.Resampling.LANCZOS)
        plate.alpha_composite(raster,(center[0]-size//2,center[1]-size//2))
    overlay(rasters['moon_halo'],432,(960,145));overlay(rasters['moon_disc'],96,(960,145))
    plate.convert('RGB').save(REVIEW/'night_composite.png')
    sheet=Image.new('RGBA',(1280,1170),(22,29,48,255));d=ImageDraw.Draw(sheet)
    d.text((24,16),'MOON v1 | original cel disc + separate soft halo | 1024px RGBA',fill='white')
    sheet.alpha_composite(rasters['moon_disc'].resize((352,352),Image.Resampling.LANCZOS),(24,50))
    sheet.alpha_composite(rasters['moon_halo'].resize((352,352),Image.Resampling.LANCZOS),(422,50))
    d.text((24,410),'Disc: cool cel bands / restrained maria',fill='white');d.text((422,410),'Halo: alpha gradient, separate layer',fill='white')
    for k,size in enumerate((64,128)):
        sheet.alpha_composite(Image.open(native/('moon_disc_%d.png'%size)).convert('RGBA'),(866+k*185,140))
        d.text((866+k*185,285),'Native %dpx quad'%size,fill='white')
    sheet.alpha_composite(plate,(0,450));d.text((24,430),'Static composite on real night capture; proposed position/scale, no cloud occlusion simulated',fill='white')
    sheet.convert('RGB').save(REVIEW/'review.png')
    report={'checks':'two1024RGBA textures;32px+ transparent edge padding;opaque disc center;monotonic soft halo alpha on4radii;native64/128 small rasters','sha256':{n:hashlib.sha256((OUT/(n+'.png')).read_bytes()).hexdigest() for n in rasters}}
    (REVIEW/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print(report['checks']+' PASS')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--review-native',type=Path);a=p.parse_args();review(a.review_native) if a.review_native else generate()
