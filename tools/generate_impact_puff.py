"""Original seeded vector dust/chip flipbooks; Pillow contact sheet and GIF."""
import argparse, hashlib, json, math, random
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'source_art/impact_puff_v1';OUT=ROOT/'assets/vfx/impact_puff_v1';REVIEW=ROOT/'docs/art_mockups/impact_puff_v1'
def svg(body,size):
    return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>'%(size,size,size,size,body)
def points(p):return ' '.join('%.3f,%.3f'%xy for xy in p)
def frame(i,variant):
    if i==15:return ''
    t=i/14; ease=1-(1-t)**2
    opacity=(.45+.55*min(t/.18,1))*(1-t*.96)**1.4
    scale=1 if variant=='hard' else .55
    body='<g transform="translate(128,156) scale(%.3f)" opacity="%.5f">'%(scale,opacity)
    rng=random.Random(10900)
    # Seeded broad dust lobes travel away from the common contact point.
    for k in range(7):
        angle=math.radians(-155+k*21+rng.uniform(-5,5))
        speed=rng.uniform(45,68); maxradius=rng.uniform(13,22)
        cx=math.cos(angle)*speed*ease;cy=math.sin(angle)*speed*ease-16*t
        r=3.5+maxradius*math.sin(math.pi*(.10+.78*t))
        phase=rng.uniform(0,math.tau)
        contour=[]
        for n in range(11):
            a=phase+n*math.tau/11;v=r*rng.uniform(.85,1.13)
            contour.append((cx+math.cos(a)*v,cy+math.sin(a)*v*.82))
        start=((contour[-1][0]+contour[0][0])/2,(contour[-1][1]+contour[0][1])/2)
        path='M %.3f %.3f'%start
        for n,control in enumerate(contour):
            following=contour[(n+1)%len(contour)]
            midpoint=((control[0]+following[0])/2,(control[1]+following[1])/2)
            path+=' Q %.3f %.3f %.3f %.3f'%(*control,*midpoint)
        path+=' Z'
        p=path;clip='%s_%d_%d'%(variant,i,k)
        body+='<defs><clipPath id="%s"><path d="%s"/></clipPath></defs>'%(clip,p)
        body+='<path d="%s" fill="#9eacc2" stroke="#53627d" stroke-opacity=".28" stroke-width="1.5" stroke-linejoin="round"/>'%p
        body+='<g clip-path="url(#%s)"><polygon points="%s" fill="#d2dce9"/><polygon points="%s" fill="#b8c6da"/></g>'%(clip,points([(cx-r*1.3,cy-r),(cx+r*1.3,cy-r),(cx+r,cy-r*.12),(cx-r,cy+r*.25)]),points([(cx-r,cy),(cx,cy-r*.25),(cx+r,cy+r*.25),(cx+r,cy+r),(cx-r,cy+r)]))
    # Small neutral chips: ballistic spread, rotation and a short opacity tail.
    for k in range(6 if variant=='hard' else 3):
        angle=math.radians(-165+k*29);speed=84+k%3*8
        x=math.cos(angle)*speed*t;y=math.sin(angle)*speed*t+42*t*t
        half=3.2+k%2
        body+='<g transform="translate(%.3f,%.3f) rotate(%.3f)" opacity="%.4f"><polygon points="%s" fill="#e1e8f3" stroke="#53627d" stroke-width="1.8"/><polygon points="%s" fill="#899bb7"/></g>'%(x,y,k*23+t*(110 if k%2 else -140),max(0,1-t/.86),points([(-half,-half),(half,-half*.75),(half*.8,half),(-half*.85,half*.8)]),points([(-half*.85,half*.8),(0,-half*.6),(half*.8,half)]))
    return body+'</g>'
def generate():
    for p in (SRC,OUT,REVIEW):p.mkdir(parents=True,exist_ok=True)
    for p in (SRC,REVIEW):(p/'.gdignore').write_text('')
    records=[]
    for variant in ('hard','soft'):
        bodies=[]
        for i in range(16):
            b=frame(i,variant);(SRC/('%s_%02d.svg'%(variant,i))).write_text(svg(b,256),encoding='utf8')
            bodies.append('<g transform="translate(%d,%d)">%s</g>'%(i%4*256,i//4*256,b))
        (SRC/(variant+'_atlas.svg')).write_text(svg(''.join(bodies),1024),encoding='utf8')
        records.append({'id':variant,'file':'impact_'+variant+'.png','art_scale':1 if variant=='hard' else .55})
    manifest={'version':1,'size':[1024,1024],'grid':[4,4],'cell_size':[256,256],'frames':16,'fps':30,'duration_s':16/30,'loop':False,'order':'top-left row-major','contact_pivot_px':[128,156],'contact_pivot_uv':[.5,156/256],'terminal_frame':15,'variants':records,'seed':10900,'regions_px':[[i%4*256,i//4*256,256,256] for i in range(16)]}
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('32 original impact frames and2 atlas SVG sources generated')
def review(native):
    frames={};stats={}
    for variant in ('hard','soft'):
        atlas=Image.open(native/(variant+'_atlas_1024.png')).convert('RGBA');assert atlas.size==(1024,1024)
        images=[];areas=[];mass=[];hashes=[]
        for i in range(16):
            cell=atlas.crop((i%4*256,i//4*256,i%4*256+256,i//4*256+256));a=cell.getchannel('A');box=a.getbbox()
            if i==15:assert box is None
            else:
                assert box and min(box[0],box[1],256-box[2],256-box[3])>=12,(variant,i,box)
                individual=Image.open(native/('%s_%02d_256.png'%(variant,i))).convert('RGBA')
                changed=0
                for a_px,b_px in zip(cell.getdata(),individual.getdata()):
                    if a_px!=b_px:changed+=1
                    assert abs(a_px[3]-b_px[3])<=1
                    assert all(abs(a_px[k]*a_px[3]/255-b_px[k]*b_px[3]/255)<=2 for k in range(3))
                assert changed<=64 # Subpixel offset may round edge antialiasing by1LSB.

            pixels=list(a.getdata());areas.append(sum(v>0 for v in pixels));mass.append(sum(pixels));hashes.append(hashlib.sha256(cell.tobytes()).hexdigest());images.append(cell)
        assert len(set(hashes))==16
        assert max(mass)>mass[0]*4
        assert mass[14]<max(mass)*.03
        frames[variant]=images;stats[variant]={'alpha_mass':mass,'nonzero_area':areas,'tile_sha256':hashes}
        atlas.save(OUT/('impact_'+variant+'.png'))
    assert max(stats['soft']['nonzero_area'])<max(stats['hard']['nonzero_area'])*.4
    sheet=Image.new('RGBA',(1200,650),(24,31,47));d=ImageDraw.Draw(sheet)
    d.text((24,16),'IMPACT PUFF v1 | hard / soft | 16frames at30fps | last frame clear',fill='white')
    for row,variant in enumerate(('hard','soft')):
        for i,cell in enumerate(frames[variant]):
            x=20+i%8*147;y=50+row*290+i//8*140
            d.rectangle((x,y,x+134,y+130),fill=(53,61,80))
            sheet.alpha_composite(cell.resize((128,128),Image.Resampling.LANCZOS),(x+3,y))
            d.text((x+5,y+117),'%s %02d'%(variant,i),fill='white')
    sheet.convert('RGB').save(REVIEW/'contact_sheet.png')
    # Side-by-side preview uses static sky/disc crops only, no world state simulation.
    plate=Image.open(ROOT/'assets/ui/loading_arena_v2/round_dawn.png').convert('RGBA')
    sky=plate.crop((100,60,700,530)).resize((256,256),Image.Resampling.LANCZOS)
    disc=plate.crop((885,800,1185,950)).resize((256,256),Image.Resampling.LANCZOS)
    gifframes=[]
    for i in list(range(16))+[15]*12:
        p=Image.new('RGBA',(1024,286),(24,31,47));d=ImageDraw.Draw(p)
        for k,(variant,bg) in enumerate((('hard',sky),('hard',disc),('soft',sky),('soft',disc))):
            p.alpha_composite(bg,(k*256,30));p.alpha_composite(frames[variant][i],(k*256,30))
            d.text((k*256+12,10),variant+' / '+('sky' if k%2==0 else 'disc'),fill='white')
        gifframes.append(p.convert('RGB'))
    gifframes[0].save(REVIEW/'motion.gif',save_all=True,append_images=gifframes[1:],duration=[30,30,40]*9+[30],loop=0,optimize=False,disposal=2)
    report={'checks':'2 x 1024 RGBA;16distinct frames each;12px+padding;terminal frame clear;atlas/frame edge-AA tolerance1alphaLSB/2premultiplied RGB;soft silhouette area<40percent hard;tail alpha mass<3percent peak','stats':stats,'sha256':{v:hashlib.sha256((OUT/('impact_'+v+'.png')).read_bytes()).hexdigest() for v in frames}}
    (REVIEW/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    print(report['checks']+' PASS')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--review-native',type=Path);a=p.parse_args();review(a.review_native) if a.review_native else generate()
