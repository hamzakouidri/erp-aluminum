import os
import re

def find_arabic_strings(root_dir):
    arabic_pattern = re.compile(r"['\"]([\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF\s\d\w\.,:\(\)\-؟!]+[\u0600-\u06FF]+.*?)['\"]")
    all_strings = set()
    
    for subdir, _, files in os.walk(root_dir):
        for file in files:
            if file.endswith('.dart'):
                path = os.path.join(subdir, file)
                with open(path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    matches = arabic_pattern.findall(content)
                    for match in matches:
                        all_strings.add(match)
                        
    return all_strings

if __name__ == '__main__':
    project_dir = r"c:\Users\hp\AndroidStudioProjects\database_data\lib"
    all_strings = find_arabic_strings(project_dir)
    
    # Read existing dictionary
    loc_file = r"c:\Users\hp\AndroidStudioProjects\database_data\lib\settings\localization.dart"
    with open(loc_file, 'r', encoding='utf-8') as f:
        loc_content = f.read()
        
    missing = []
    for s in all_strings:
        # Ignore very short strings
        if len(s.strip()) <= 1:
            continue
            
        # Check if exactly in localization file
        if f"'{s}'" not in loc_content and f'"{s}"' not in loc_content:
            missing.append(s)
            
    with open('missing_arabic.txt', 'w', encoding='utf-8') as f:
        for m in sorted(missing):
            f.write(m + "\n")
            
    print(f"Found {len(missing)} missing Arabic strings. Written to missing_arabic.txt")
