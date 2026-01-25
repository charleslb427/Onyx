
import os
import shutil

def install_specific_icons(source_root, target_root):
    if not os.path.exists(source_root):
        print(f"Error: {source_root} not found")
        return

    # Map source filename to destination folder
    mapping = {
        'mdpi.png': 'mipmap-mdpi',
        'hdpi.png': 'mipmap-hdpi',
        'xhdpi.png': 'mipmap-xhdpi',
        'xxhdpi.png': 'mipmap-xxhdpi',
        'xxxhdpi.png': 'mipmap-xxxhdpi'
    }

    for source_file, target_folder in mapping.items():
        src_path = os.path.join(source_root, source_file)
        
        if os.path.exists(src_path):
            target_dir = os.path.join(target_root, target_folder)
            os.makedirs(target_dir, exist_ok=True)
            
            # Destination filenames
            dest_launcher = os.path.join(target_dir, 'ic_launcher.png')
            dest_round = os.path.join(target_dir, 'ic_launcher_round.png')
            
            # Copy source to dest (Launcher)
            shutil.copy2(src_path, dest_launcher)
            print(f"Installed {source_file} to {target_folder}/ic_launcher.png")
            
            # Copy source to dest (Round variant)
            shutil.copy2(src_path, dest_round)
            print(f"Installed {source_file} to {target_folder}/ic_launcher_round.png")
            
        else:
            print(f"Warning: Source file {source_file} not found in {source_root}")

if __name__ == "__main__":
    source = r"C:\Users\famil\Downloads\IcareLite\AppIcons\android"
    target = r"C:\Users\famil\Downloads\IcareLite\android-app\app\src\main\res"
    install_specific_icons(source, target)
