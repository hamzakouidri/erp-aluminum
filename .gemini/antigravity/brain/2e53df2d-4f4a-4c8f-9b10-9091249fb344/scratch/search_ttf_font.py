import os

path_cache = r'C:\Users\hp\AppData\Local\Pub\Cache\hosted\pub.dev\pdf-3.12.0'
for root, dirs, files in os.walk(path_cache):
    for file in files:
        if file.endswith('.dart'):
            fullpath = os.path.join(root, file)
            with open(fullpath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                if 'class PdfTtfFont' in content:
                    print("Found class PdfTtfFont in", fullpath)
