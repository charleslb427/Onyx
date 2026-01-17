
import os
import shutil
from PIL import Image, ImageChops

def trim(im):
    bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
    diff = ImageChops.difference(im, bg)
    diff = ImageChops.add(diff, diff, 2.0, -100)
    bbox = diff.getbbox()
    if bbox:
        return im.crop(bbox)
    return im

def generate_maximized_android_icons(source_path, res_path):
    if not os.path.exists(source_path):
        print(f"Error: {source_path} not found")
        return

    try:
        img = Image.open(source_path).convert('RGBA')
        print(f"Original: {img.size}")

        # 1. Trim whitespace/transparency aggressively
        img = trim(img)
        print(f"Trimmed: {img.size}")
        
        width, height = img.size
        aspect_ratio = width / height

        # Android standard sizes
        sizes = {
            'mipmap-mdpi': 48,
            'mipmap-hdpi': 72,
            'mipmap-xhdpi': 96,
            'mipmap-xxhdpi': 144,
            'mipmap-xxxhdpi': 192
        }

        for folder, size in sizes.items():
            target_dir = os.path.join(res_path, folder)
            os.makedirs(target_dir, exist_ok=True)
            
            canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
            
            # Use minimal padding (8%) to maximize logo size inside the circle mask
            # Android adaptive icon mask diameter is roughly 66% of the full dimension.
            # But here we render standard icons (legacy), so we can use more space.
            # We target fitting well within the visual center.
            padding = int(size * 0.08)
            available_size = size - (padding * 2)
            
            if width > height:
                new_width = available_size
                new_height = int(available_size / aspect_ratio)
            else:
                new_height = available_size
                new_width = int(available_size * aspect_ratio)
                
            resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
            
            x = (size - new_width) // 2
            y = (size - new_height) // 2
            
            canvas.paste(resized, (x, y), resized)
            
            # Determine background color for non-transparent pixels? No, keep transparency.
            # If the user wants a white background circle, we can add it.
            # Usually, standard icons (ic_launcher.png) can be transparent shapes.
            # But modern Android often puts them on a white squircle if they are not adaptive.
            # Let's create a filled background version just in case "round" needs it?
            # Actually, let's keep it simple: Transparent canvas + Logo.
            
            canvas.save(os.path.join(target_dir, 'ic_launcher.png'), 'PNG')
            
            # For "round", some devices impose a background. 
            # We save the same file for now.
            canvas.save(os.path.join(target_dir, 'ic_launcher_round.png'), 'PNG')
            
            print(f"Generated {size}x{size} in {folder}")

    except Exception as e:
        print(f"Failed: {e}")

if __name__ == "__main__":
    source = r"c:\Users\famil\Downloads\IcareLite\OnyxIcon.png"
    target = r"c:\Users\famil\Downloads\IcareLite\android-app\app\src\main\res"
    generate_maximized_android_icons(source, target)
