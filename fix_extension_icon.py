
import os
from PIL import Image

def fix_extension_icons_maximized(source_path):
    if not os.path.exists(source_path):
        print(f"Error: {source_path} not found")
        return

    # Chrome standard sizes
    sizes = [16, 32, 48, 128]
    root_dir = os.path.dirname(source_path)
    
    try:
        img = Image.open(source_path)
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        
        # 1. AUTOCROP: Remove empty/transparent borders to maximize logo size
        bbox = img.getbbox()
        if bbox:
            img = img.crop(bbox)
            print(f"Auto-cropped source image to {img.size} (removed whitespace)")
        
        # Calculate aspect ratio of the cropped logo
        width, height = img.size
        aspect_ratio = width / height

        for size in sizes:
            target_filename = f"icon{size}.png"
            target_path = os.path.join(root_dir, target_filename)
            
            # Create a blank square transparent canvas
            canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
            
            # Calculate dimensions to fit inside the square MAXIMALLY
            # We leave a tiny padding (e.g. 5%) so it doesn't touch edges unpleasantly
            padding = int(size * 0.05) 
            available_size = size - (padding * 2)
            
            if width > height:
                new_width = available_size
                new_height = int(available_size / aspect_ratio)
            else:
                new_height = available_size
                new_width = int(available_size * aspect_ratio)
            
            # Resize source image with High Quality Lanczos
            resized_source = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
            
            # Center the image on the canvas
            x_offset = (size - new_width) // 2
            y_offset = (size - new_height) // 2
            
            canvas.paste(resized_source, (x_offset, y_offset), resized_source)
            
            # Save
            canvas.save(target_path, 'PNG', optimize=False, compress_level=0)
            print(f"Generated maximized {target_filename}")

    except Exception as e:
        print(f"Failed to process image: {e}")

if __name__ == "__main__":
    source = r"c:\Users\famil\Downloads\IcareLite\OnyxIcon.png"
    fix_extension_icons_maximized(source)
