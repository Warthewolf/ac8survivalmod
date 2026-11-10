"""label_survey.py : each survey picture's name and what it shows written along its foot (plain Python with PIL):
  python tools/tanicorn/label_survey.py <survey dir>      (the folder survey_tanacorn.py wrote: survey.json + PNGs)
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

d = sys.argv[1]
try:
    font = ImageFont.truetype("DejaVuSans.ttf", 20)
except OSError:
    font = ImageFont.load_default()
for row in json.load(open(os.path.join(d, "survey.json"))):
    path = os.path.join(d, row["file"])
    im = Image.open(path).convert("RGB")
    w, h = im.size
    out = Image.new("RGB", (w, h + 36), (20, 20, 20))
    out.paste(im, (0, 0))
    ImageDraw.Draw(out).text((12, h + 7), "%s: %s" % (row["name"], row["note"]), fill=(235, 235, 235), font=font)
    out.save(path)
print("label_survey: %d pictures labelled" % len(json.load(open(os.path.join(d, "survey.json")))))
