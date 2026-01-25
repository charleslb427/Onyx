
import os
import shutil

def install_android_icons(source_root, target_root):
    if not os.path.exists(source_root):
        print(f"Error: {source_root} not found")
        return

    folders = [
        'mipmap-mdpi',
        'mipmap-hdpi',
        'mipmap-xhdpi',
        'mipmap-xxhdpi',
        'mipmap-xxxhdpi'
    ]

    for folder in folders:
        src_dir = os.path.join(source_root, folder)
        dst_dir = os.path.join(target_root, folder)
        
        if os.path.exists(src_dir):
            # Create destination if needed
            os.makedirs(dst_dir, exist_ok=True)
            
            src_file = os.path.join(src_dir, 'ic_launcher.png')
            if os.path.exists(src_file):
                # Copy ic_launcher.png
                shutil.copy2(src_file, os.path.join(dst_dir, 'ic_launcher.png'))
                
                # Copy as ic_launcher_round.png too (since specific round version is missing)
                shutil.copy2(src_file, os.path.join(dst_dir, 'ic_launcher_round.png'))
                
                print(f"Installed icons in {folder}")
            else:
                print(f"Warning: No ic_launcher.png in {folder}")
        else:
            print(f"Warning: Source folder {folder} not found")

if __name__ == "__main__":
    source = r"C:\Users\famil\Downloads\IcareLite\AppIcons\android"
    target = r"C:\Users\famil\Downloads\IcareLite\android-app\app\src\main\res"
    install_android_icons(source, target)
