import os
from PIL import Image

def resize_and_save(src_path, dest_path, size=(256, 256)):
    try:
        if not os.path.exists(src_path):
            print(f"Source file does not exist: {src_path}")
            return False
        
        img = Image.open(src_path)
        # Convert to RGB if it is RGBA or other modes
        if img.mode != 'RGB':
            img = img.convert('RGB')
            
        img_resized = img.resize(size, Image.Resampling.LANCZOS)
        img_resized.save(dest_path, "JPEG", quality=85)
        print(f"Successfully resized {src_path} -> {dest_path} ({size[0]}x{size[1]})")
        return True
    except Exception as e:
        print(f"Error processing {src_path}: {e}")
        return False

def main():
    # Paths
    artifact_dir = r"C:\Users\hp\.gemini\antigravity\brain\213396db-4afd-4176-888d-f1ee2b4bd741"
    assets_dir = r"assets\images"
    
    # 1. Dark Wood (mahogany texture currently in assets/images/wood_texture.png)
    src_dark = os.path.join(assets_dir, "wood_texture.png")
    dest_dark = os.path.join(assets_dir, "wood_texture_dark.png")
    resize_and_save(src_dark, dest_dark)
    
    # 2. Default Wood & D0 Oak (original light oak texture in artifact directory)
    src_light = os.path.join(artifact_dir, "wood_texture.png")
    dest_default = os.path.join(assets_dir, "wood_texture.png")
    dest_d0 = os.path.join(assets_dir, "wood_texture_d0.png")
    resize_and_save(src_light, dest_default)
    resize_and_save(src_light, dest_d0)
    
    # 3. Antique Wood
    src_antique = os.path.join(assets_dir, "wood_texture_antique.png")
    dest_antique = os.path.join(assets_dir, "wood_texture_antique.png")
    resize_and_save(src_antique, dest_antique)
    
    # 4. Grey Wood
    src_grey = os.path.join(artifact_dir, "grey_wood_texture_1782043307071.png")
    dest_grey = os.path.join(assets_dir, "wood_texture_grey.png")
    resize_and_save(src_grey, dest_grey)

if __name__ == "__main__":
    main()
