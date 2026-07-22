import os
from PIL import Image

def main():
    src_path = 'assets/images/wood_texture.png'
    if not os.path.exists(src_path):
        print(f"Error: {src_path} does not exist!")
        return
    
    print(f"Original size: {os.path.getsize(src_path)} bytes")
    
    img = Image.open(src_path)
    # Resize to 512x512 to significantly reduce memory and file size while keeping high quality
    img_resized = img.resize((512, 512), Image.Resampling.LANCZOS)
    
    # Save optimized PNG
    img_resized.save(src_path, format='PNG', optimize=True)
    print(f"Optimized size: {os.path.getsize(src_path)} bytes")

if __name__ == '__main__':
    main()
