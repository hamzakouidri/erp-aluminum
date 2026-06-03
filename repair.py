import os
import re

loc_file = r"c:\Users\hp\AndroidStudioProjects\database_data\lib\settings\localization.dart"

with open(loc_file, 'r', encoding='utf-8') as f:
    content = f.read()

# We know the dictionary ends right after:
# 'حدد فئة المنتجات التی تريد إدارتها': {
#       AppLanguage.arabic: 'حدد فئة المنتجات التی تريد إدارتها',
#       AppLanguage.french: 'Sélectionnez la catégorie de produits à gérer',
#       AppLanguage.english: 'Select the product category to manage',
#     },
#  };

target = "'Select the product category to manage',\n    },"

idx = content.find(target)
if idx != -1:
    end_of_good_dict = idx + len(target)
    
    # We want to remove all the injected keys which look like:
    #     ''' ... ''': { ... },
    
    # Let's find the closing of the dictionary, which is '  };\n'
    # Wait, my dart script injected right before the last '};', so there's a lot of stuff.
    # Actually, the static methods were pushed to the very end of the file.
    
    # Let's just find the first static method: '  static String translate'
    method_idx = content.find("  static String translate(String key, AppLanguage lang) {")
    
    if method_idx != -1:
        clean_content = content[:end_of_good_dict] + "\n  };\n\n" + content[method_idx:]
        with open(loc_file, 'w', encoding='utf-8') as f:
            f.write(clean_content)
        print("Successfully repaired localization.dart")
    else:
        print("Could not find static method")
else:
    print("Could not find target good dictionary end")

