import re

def main():
    file_path = r'lib\items_produits\catalogue_manager.dart'

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. Expand the visibleWidth TextField condition
    content = content.replace(
        "if (selectedType == 'sash')\n                    TextField(\n                      controller: visibleWidthCtrl,",
        "if (selectedType != 'parclose' &&\n                        selectedType != 'batmo' &&\n                        selectedType != 'bouchon_batmo' &&\n                        selectedType != 'renfort')\n                    TextField(\n                      controller: visibleWidthCtrl,"
    )

    # 2. In insertSection, map thickness to visibleWidthCtrl
    content = content.replace(
        "thickness:\n                              (selectedType == 'parclose' ||\n                                  selectedType == 'batmo' ||\n                                  selectedType == 'bouchon_batmo' ||\n                                  selectedType == 'renfort')\n                              ? 0.0\n                            : 0.0,",
        "thickness:\n                              (selectedType == 'parclose' ||\n                                  selectedType == 'batmo' ||\n                                  selectedType == 'bouchon_batmo' ||\n                                  selectedType == 'renfort')\n                              ? 0.0\n                            : (double.tryParse(visibleWidthCtrl.text) ?? 0.0),"
    )

    # 3. In updateSection, map 'thickness' to visibleWidthCtrl
    content = content.replace(
        "'thickness':\n                              (selectedType == 'parclose' ||\n                                  selectedType == 'batmo' ||\n                                  selectedType == 'bouchon_batmo' ||\n                                  selectedType == 'renfort')\n                              ? 0.0\n                            : 0.0,",
        "'thickness':\n                              (selectedType == 'parclose' ||\n                                  selectedType == 'batmo' ||\n                                  selectedType == 'bouchon_batmo' ||\n                                  selectedType == 'renfort')\n                              ? 0.0\n                            : (double.tryParse(visibleWidthCtrl.text) ?? 0.0),"
    )

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

    print("Restored visibleWidth logic.")

if __name__ == '__main__':
    main()
