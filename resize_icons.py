
import os
from PIL import Image

def resize_icon_smart(source_path, res_path):
    if not os.path.exists(source_path):
        print(f"Error: {source_path} not found")
        return

    sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192
    }

    try:
        img = Image.open(source_path)
        print(f"Original Size: {img.size}")
        
        if img.mode != 'RGBA':
            img = img.convert('RGBA')

        # Calculate aspect ratio
        width, height = img.size
        aspect_ratio = width / height

        for folder, target_size in sizes.items():
            target_dir = os.path.join(res_path, folder)
            os.makedirs(target_dir, exist_ok=True)
            
            # Create a blank square transparent canvas
            canvas = Image.new('RGBA', (target_size, target_size), (0, 0, 0, 0))
            
            # Calculate dimensions to fit inside the square while maintaining aspect ratio
            if width > height:
                # Width is dominant, fit to width
                new_width = target_size
                new_height = int(target_size / aspect_ratio)
            else:
                # Height is dominant, fit to height
                new_height = target_size
                new_width = int(target_size * aspect_ratio)
            
            # Resize source image with High Quality Lanczos
            resized_source = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
            
            # Center the image on the canvas
            x_offset = (target_size - new_width) // 2
            y_offset = (target_size - new_height) // 2
            
            canvas.paste(resized_source, (x_offset, y_offset), resized_source)
            
            # Save Uncompressed
            canvas.save(os.path.join(target_dir, 'ic_launcher.png'), 'PNG', optimize=False, compress_level=0)
            canvas.save(os.path.join(target_dir, 'ic_launcher_round.png'), 'PNG', optimize=False, compress_level=0)
            
            print(f"Generated {target_size}x{target_size} icon in {folder} (Centered, Uncompressed)")

    except Exception as e:
        print(f"Failed to process image: {e}")

if __name__ == "__main__":
    source = r"c:\Users\famil\Downloads\IcareLite\OnyxIcon.png"
    res_dir = r"c:\Users\famil\Downloads\IcareLite\android-app\app\src\main\res"
    resize_icon_smart(source, res_dir)
