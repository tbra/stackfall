"""Mechanical contact-sheet layout and verification; generated paintings unchanged."""
import hashlib,json,shutil
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/art_mockups/horizon_concepts_v1'
meta=json.loads((OUT/'provenance.json').read_text())
labels=['Original reference','A - Towering cumulus ring','B - Stratus and haze','C - Floating islands','D - Distant storm cell','E - Cumulus plus stratus']
reference=OUT/'reference_morning.png'
shutil.copyfile(meta['edit_target'],str(reference))
entries=[reference];records=[]
for variant in meta['variants']:
    # The tool's hint names both destination directory and exact file.
    variant['generated_source']=variant['generated_source'].split(' as ')[-1]
    source=Path(variant['generated_source']);dest=OUT/variant['file']
    shutil.copyfile(str(source),str(dest))
    assert source.read_bytes()==dest.read_bytes()
    with Image.open(dest) as image:
        assert image.format=='PNG' and abs(image.width/image.height-16/9)<.02
        image.verify()
    digest=hashlib.sha256(dest.read_bytes()).hexdigest()
    records.append({'id':variant['id'],'file':variant['file'],'size':list(Image.open(dest).size),'sha256':digest})
    entries.append(dest)
assert len(set(v['sha256'] for v in records))==5
meta['reference_sha256']=hashlib.sha256(reference.read_bytes()).hexdigest()
(OUT/'provenance.json').write_text(json.dumps(meta,indent=2)+'\n')
# Montage only: resize whole paintings for page layout; never retouch their content.
sheet=Image.new('RGB',(1280,1228),(23,28,43));draw=ImageDraw.Draw(sheet)
for i,p in enumerate(entries):
    x=i%2*640;y=i//2*404
    draw.text((x+14,y+12),labels[i],fill='white')
    image=Image.open(p).convert('RGB');image.thumbnail((640,360),Image.Resampling.LANCZOS)
    sheet.paste(image,(x+(640-image.width)//2,y+36+(360-image.height)//2))
sheet.save(OUT/'contact_sheet.png')
(OUT/'.gdignore').write_text('')
report={'checks':'five valid unique near16:9 PNGs; workspace copies byte-identical to tool originals; all input/output files present','variants':records,'contact_sheet_size':list(sheet.size),'concept_limitations':['AI edit may alter HUD pixels; not UI validation','Single camera and morning lighting only','Not a seamless panorama, 3D asset or game capture after integration']}
(OUT/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
print('Five concept PNGs, original-preserving copies, manifest, contact sheet PASS')
