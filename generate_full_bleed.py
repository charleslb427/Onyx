
import os
from PIL import Image, ImageChops

def trim(im):
    bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
    diff = ImageChops.difference(im, bg)
    diff = ImageChops.add(diff, diff, 2.0, -100)
    bbox = diff.getbbox()
    if bbox:
        return im.crop(bbox)
    return im

def generate_full_bleed_icons(source_path, res_path):
    if not os.path.exists(source_path):
        print(f"Error: {source_path} not found")
        return

    try:
        img = Image.open(source_path).convert('RGBA')
        
        # 1. Trim everything
        img = trim(img)
        
        width, height = img.size
        aspect_ratio = width / height

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
            
            # NO PADDING. FULL SIZE.
            # We want the logo to be as big as possible.
            # If the logo is rectangular, we fit the smallest dimension to the full size.
            # This ensures NO whitespace on the sides/top.
            
            if width > height:
                # Landscape logo: Fit height to 100%, crop width?
                # No, user wants to see the whole logo. 
                # So we fit width to 100% (size).
                new_width = size
                new_height = int(size / aspect_ratio)
            else:
                new_height = size
                new_width = int(size * aspect_ratio)
            
            # High quality resize
            resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
            
            x = (size - new_width) // 2
            y = (size - new_height) // 2
            
            canvas.paste(resized, (x, y), resized)
            
            # Overwrite both standard and round
            canvas.save(os.path.join(target_dir, 'ic_launcher.png'), 'PNG')
            canvas.save(os.path.join(target_dir, 'ic_launcher_round.png'), 'PNG')
            
            print(f"Full Bleed {size}x{size} in {folder}")

    except Exception as e:
        print(f"Failed: {e}")

if __name__ == "__main__":
    source = r"c:\Users\famil\Downloads\IcareLite\OnyxIcon.png"
    target = r"c:\Users\famil\Downloads\IcareLite\android-app\app\src\main\res"
    generate_full_bleed_icons(source, target)
