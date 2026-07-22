import os

paths = ["assets", "extracted_pdf_images"]
for p in paths:
    if os.path.exists(p):
        print(f"=== Files in {p} ===")
        for root, dirs, files in os.walk(p):
            for file in files:
                print(os.path.join(root, file))
    else:
        print(f"Path {p} does not exist.")
