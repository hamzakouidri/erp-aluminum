import re

def main():
    file_path = r'lib\items_produits\catalogue_manager.dart'
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. Remove final thicknessCtrl declaration in Add
    content = re.sub(r'final thicknessCtrl = TextEditingController\(\);\n\s*', '', content)

    # 2. Remove final thicknessCtrl declaration in Edit
    content = re.sub(r'final thicknessCtrl = TextEditingController\(\s*text: section\[\'thickness\'\]\?\.toString\(\) \?\? \'\',\s*\);\n\s*', '', content)

    # 3. Remove the UI TextField block
    pattern_ui = r"if \(selectedType != 'parclose' &&\s*selectedType != 'batmo' &&\s*selectedType != 'bouchon_batmo' &&\s*selectedType != 'renfort'\)\s*TextField\(\s*controller: thicknessCtrl,\s*keyboardType: TextInputType.number,\s*decoration: InputDecoration\(\s*labelText: 'السماكة \(العمق الكلي\) / Thickness \(mm\)',\s*\),\s*\),\s*SizedBox\(height: 10\),"
    # Actually wait, the UI is slightly different in Add vs Edit and has no SizedBox at the bottom in Add.
    
    # 4. Remove `thicknessCtrl.text.isNotEmpty` from validation
    content = content.replace("thicknessCtrl.text.isNotEmpty", "true")

    # 5. Remove `double.tryParse(thicknessCtrl.text) ?? 0.0`
    content = content.replace("double.tryParse(thicknessCtrl.text) ?? 0.0", "0.0")

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

    print("Partial python script.")

if __name__ == '__main__':
    main()
