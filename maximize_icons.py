
import os
import math
from PIL import Image, ImageChops

def trim(im):
    """
    Trims the image by removing borders that are the same color as the top-left pixel.
    Works for both transparent and solid backgrounds.
    """
    bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
    diff = ImageChops.difference(im, bg)
    diff = ImageChops.add(diff, diff, 2.0, -100)
    bbox = diff.getbbox()
    if bbox:
        return im.crop(bbox)
    return im

def maximize_icon(source_path, base_path_android, base_path_extension):
    if not os.path.exists(source_path):
        print(f"Error: {source_path} not found")
        return

    try:
        # Load and convert
        img = Image.open(source_path).convert('RGBA')
        print(f"Original Size: {img.size}")

        # 1. AGGRESSIVE TRIM
        # First, trim based on transparency
        img = trim(img)
        
        # Second, specifically check for white background if transparency didn't catch it
        # (Create a white background version to diff against)
        bg_white = Image.new("RGBA", img.size, (255, 255, 255, 255))
        diff_white = ImageChops.difference(img, bg_white)
        # Using a slight threshold for compression artifacts
        diff_white = ImageChops.add(diff_white, diff_white, 2.0, -100)
        bbox_white = diff_white.getbbox()
        if bbox_white:
             # Check if this crop is smaller (meaning we found white borders)
             cropped_white = img.crop(bbox_white)
             if cropped_white.size[0] * cropped_white.size[1] < img.size[0] * img.size[1]:
                 print("Detected white borders, cropping...")
                 img = cropped_white

        print(f"Trimmed Size (Active Content): {img.size}")
        
        # Calculate aspect ratio of the content
        width, height = img.size
        aspect_ratio = width / height

        # --- ANDROID GENERATION ---
        android_sizes = {
            'mipmap-mdpi': 48,
            'mipmap-hdpi': 72,
            'mipmap-xhdpi': 96,
            'mipmap-xxhdpi': 144,
            'mipmap-xxxhdpi': 192
        }
        
        for folder, size in android_sizes.items():
            target_dir = os.path.join(base_path_android, folder)
            os.makedirs(target_dir, exist_ok=True)
            
            canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
            
            # Android needs ~15% padding for safe zone (adaptive icons masks)
            # We want it BIG, but not cut off by the circle.
            padding = int(size * 0.15) 
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
            
            canvas.save(os.path.join(target_dir, 'ic_launcher.png'), 'PNG')
            canvas.save(os.path.join(target_dir, 'ic_launcher_round.png'), 'PNG')
            print(f"Android {folder}: {size}x{size}")

        # --- EXTENSION GENERATION ---
        # For Chrome, we can go nearly edge-to-edge (very small padding)
        ext_sizes = [16, 32, 48, 128]
        ext_dir = os.path.dirname(source_path)
        
        for size in ext_sizes:
            canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
            
            # Tiny padding (5%) just to look nice
            padding = int(size * 0.05) if size > 16 else 0
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
            
            target_path = os.path.join(ext_dir, f"icon{size}.png")
            canvas.save(target_path, 'PNG')
            print(f"Extension: {size}x{size}")

    except Exception as e:
        print(f"Failed: {e}")

if __name__ == "__main__":
    source = r"c:\Users\famil\Downloads\IcareLite\OnyxIcon.png"
    android_res = r"c:\Users\famil\Downloads\IcareLite\android-app\app\src\main\res"
    # Extension dir is parent of source
    maximize_icon(source, android_res, None) 
