import re

path_goods = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\order_required_goods_screen.dart'

with open(path_goods, 'r', encoding='utf-8') as f:
    code = f.read()

# Remove the unused imports from the top of the file
OLD_UNUSEDS = """import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:provider/provider.dart';"""

if OLD_UNUSEDS in code:
    code = code.replace(OLD_UNUSEDS, "")
    print("Unused imports removed from order_required_goods_screen.dart.")
else:
    # If there are differences in formatting, let's look for them individually
    code = code.replace("import 'package:database_data/settings/app_settings.dart';\n", "")
    code = code.replace("import 'package:database_data/settings/localization.dart';\n", "")
    code = code.replace("import 'package:provider/provider.dart';\n", "")
    print("Unused imports removed individually from order_required_goods_screen.dart.")

with open(path_goods, 'w', encoding='utf-8') as f:
    f.write(code)
