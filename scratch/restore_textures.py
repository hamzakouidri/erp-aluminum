import os
import shutil

def copy_file(src, dest):
    try:
        if not os.path.exists(src):
            print(f"Source does not exist: {src}")
            return False
        shutil.copy2(src, dest)
        print(f"Successfully copied {src} -> {dest}")
        return True
    except Exception as e:
        print(f"Error copying {src}: {e}")
        return False

def main():
    artifact_dir = r"C:\Users\hp\.gemini\antigravity\brain\213396db-4afd-4176-888d-f1ee2b4bd741"
    assets_dir = r"assets\images"
    
    # 1. Restore D0 Oak to original light oak texture
    src_d0 = os.path.join(artifact_dir, "wood_texture.png")
    dest_d0 = os.path.join(assets_dir, "wood_texture_d0.png")
    copy_file(src_d0, dest_d0)
    
    # 2. Restore Antique to original antique texture
    src_antique = os.path.join(artifact_dir, "wood_texture_antique_1782042804142.png")
    dest_antique = os.path.join(assets_dir, "wood_texture_antique.png")
    copy_file(src_antique, dest_antique)
    
    # 3. Restore Default Wood (الخشبي) to original mahogany texture (the one they approved)
    src_mahogany = os.path.join(artifact_dir, "wood_texture_new_1782041321823.png")
    dest_mahogany = os.path.join(assets_dir, "wood_texture.png")
    copy_file(src_mahogany, dest_mahogany)
    
    # 4. Restore Grey Wood to original grey texture
    src_grey = os.path.join(artifact_dir, "grey_wood_texture_1782043307071.png")
    dest_grey = os.path.join(assets_dir, "wood_texture_grey.png")
    copy_file(src_grey, dest_grey)

if __name__ == "__main__":
    main()
