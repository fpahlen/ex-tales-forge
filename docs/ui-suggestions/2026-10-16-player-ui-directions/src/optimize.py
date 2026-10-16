"""Shrink the rendered PNGs. A screens (flat colours) get lossless oxipng only.
Textured screens (B, C, overviews) get libimagequant palette reduction with dithering, then oxipng.
Needs: pip install pyoxipng imagequant"""
import glob, os, oxipng, imagequant
from PIL import Image
OUT=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','images')
for f in sorted(glob.glob(os.path.join(OUT,'*.png'))):
    n=os.path.basename(f); a=os.path.getsize(f)
    if not n.startswith('a'):
        im=Image.open(f).convert('RGBA')
        imagequant.quantize_pil_image(im,dithering_level=1.0,max_colors=256,min_quality=80,max_quality=98).save(f)
    oxipng.optimize(f,level=3,strip=oxipng.StripChunks.safe())
    print(n,a//1024,'->',os.path.getsize(f)//1024,'KB')
