import re
file_path = r'lib\items_produits\catalogue_manager.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace thicknessCtrl with barLengthCtrl in declarations
content = content.replace('final thicknessCtrl = TextEditingController();', 'final barLengthCtrl = TextEditingController(text: \'5.8\');')
content = content.replace('final thicknessCtrl = TextEditingController(\n      text: section[\'thickness\']?.toString() ?? \'\',\n    );', 'final barLengthCtrl = TextEditingController(\n      text: section[\'bar_length\']?.toString() ?? \'5.8\',\n    );')

# In Add UI
content = re.sub(
    r"if \(selectedType != 'parclose' &&\s*selectedType != 'batmo' &&\s*selectedType != 'bouchon_batmo' &&\s*selectedType != 'renfort'\)\s*TextField\(\s*controller: thicknessCtrl,\s*keyboardType: TextInputType\.number,\s*decoration: InputDecoration\(\s*labelText: 'سماكة القطاع / Thickness \(mm\)',\s*\),\s*\),",
    "TextField(\n                      controller: barLengthCtrl,\n                      keyboardType: TextInputType.numberWithOptions(decimal: true),\n                      decoration: InputDecoration(\n                        labelText: 'طول البار (متر) / Bar Length (m)',\n                      ),\n                    ),",
    content
)

# Replace 'sash' with 'sash' || 'frame' || 'mullion' for visibleWidthCtrl
content = re.sub(
    r"if \(selectedType == 'sash'\)\s*TextField\(\s*controller: visibleWidthCtrl,\s*keyboardType: TextInputType\.number,\s*decoration: InputDecoration\(\s*labelText: 'العرض الظاهر / Visible Width \(mm\)',\s*\),\s*\),",
    "if (selectedType == 'sash' || selectedType == 'frame' || selectedType == 'mullion' || selectedType == 'side_cover')\n                    TextField(\n                      controller: visibleWidthCtrl,\n                      keyboardType: TextInputType.number,\n                      decoration: InputDecoration(\n                        labelText: 'العرض الظاهر / Visible Width (mm)',\n                      ),\n                    ),",
    content
)

# Update insertSection logic
content = re.sub(
    r"thickness:\s*\(selectedType == 'parclose' \|\|\s*selectedType == 'batmo' \|\|\s*selectedType == 'bouchon_batmo' \|\|\s*selectedType == 'renfort'\)\s*\?\s*0\.0\s*:\s*\(double\.tryParse\(thicknessCtrl\.text\) \?\? 0\.0\),",
    "thickness: double.tryParse(visibleWidthCtrl.text) ?? 45.0,\n                      barLength: double.tryParse(barLengthCtrl.text) ?? 5.8,",
    content
)

# Remove thicknessCtrl from validation check
content = content.replace('thicknessCtrl.text.isNotEmpty', 'barLengthCtrl.text.isNotEmpty')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Success')
