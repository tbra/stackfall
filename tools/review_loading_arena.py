"""Review native renders and centered cover crops; does not modify source art."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/ui/loading_arena_v1'
OUT = ROOT / 'docs/art_mockups/loading_arena_v1'
OUT.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype(str(ROOT / 'assets/ui/fonts/Manrope-Regular.ttf'), 15)
themes = {}
for theme in ('sunset', 'night', 'dawn'):
    image = Image.open(ART / ('arena_%s.png' % theme)).convert('RGB')
    assert image.size == (1920, 1080), (theme, image.size)
    assert len(image.getcolors(image.width * image.height)) > 1000, theme
    themes[theme] = image
assert len({image.tobytes() for image in themes.values()}) == 3, 'Theme renders must differ'
sheet = Image.new('RGB', (1200, 250), '#26323a')
draw = ImageDraw.Draw(sheet)
for index, (theme, image) in enumerate(themes.items()):
    draw.text((index*400+8, 4), theme.capitalize(), fill='#f5ebd6', font=font)
    sheet.paste(image.resize((400, 225), Image.Resampling.LANCZOS), (index*400, 25))
sheet.save(OUT / 'themes.png')

sheet = Image.new('RGB', (1200, 640), '#26323a')
draw = ImageDraw.Draw(sheet)
sizes = [(1280,720), (1920,1080), (2560,1440), (3440,1440), (720,1280)]
for index, size in enumerate(sizes):
    # Same centered cover rule as TextureRect.STRETCH_KEEP_ASPECT_COVERED.
    crop = ImageOps.fit(themes['sunset'], size, Image.Resampling.LANCZOS)
    crop.thumbnail((392, 282), Image.Resampling.LANCZOS)
    x,y=index%3*400,index//3*320
    draw.text((x+8,y+5), '%s x %s centered cover' % size, fill='#f5ebd6', font=font)
    sheet.paste(crop, (x+(400-crop.width)//2,y+30+(282-crop.height)//2))
composition = Image.open(OUT / 'loading_composition.png').convert('RGB')
assert composition.size == (1280,720)
composition.thumbnail((392,282), Image.Resampling.LANCZOS)
draw.text((808,325), 'Actual loading UI composition', fill='#f5ebd6', font=font)
sheet.paste(composition, (804,350+(282-composition.height)//2))
sheet.save(OUT / 'crop_review.png')
print('Three distinct native 1920x1080 plates and five centered cover crop proofs PASS')
