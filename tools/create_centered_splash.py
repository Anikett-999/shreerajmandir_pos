from PIL import Image
import os

root = os.path.dirname(os.path.dirname(__file__))
src = os.path.join(root, 'assets', 'branding', 'app_icon.png')
dst = os.path.join(root, 'assets', 'branding', 'splash_logo_centered.png')

if not os.path.exists(src):
    raise SystemExit(f"Source not found: {src}")

img = Image.open(src).convert('RGBA')
w, h = img.size
# Target canvas and scaled image size
canvas_size = 2000
target_width = 1600
# compute scale preserving aspect ratio
scale = target_width / w
new_w_img = int(w * scale)
new_h_img = int(h * scale)
resized = img.resize((new_w_img, new_h_img), Image.LANCZOS)
# create canvas (transparent) and paste centered — no extra padding beyond canvas
canvas = Image.new('RGBA', (canvas_size, canvas_size), (255, 255, 255, 0))
offset_x = (canvas_size - new_w_img) // 2
offset_y = (canvas_size - new_h_img) // 2
canvas.paste(resized, (offset_x, offset_y), resized)
canvas.save(dst)
print(f"Saved larger centered splash: {dst} (canvas {canvas_size}x{canvas_size}, image {new_w_img}x{new_h_img}, offset ({offset_x},{offset_y}))")
