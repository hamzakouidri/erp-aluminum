import re

path_goods = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\order_required_goods_screen.dart'

with open(path_goods, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Fix dbInstance type declaration to be non-nullable
OLD_DB_INSTANCE_DECL = """    final dbInstance = await widget.db.db;"""
NEW_DB_INSTANCE_DECL = """    final dbInstance = (await widget.db.db)!;"""

assert OLD_DB_INSTANCE_DECL in code, "OLD_DB_INSTANCE_DECL not found in order_required_goods_screen.dart"
code = code.replace(OLD_DB_INSTANCE_DECL, NEW_DB_INSTANCE_DECL, 1)

# 2. Remove unused _loadKitBundleData method to clean up compiler warnings
# Let's search for _loadKitBundleData body
# It starts at: Future<Map<String, List<Map<String, dynamic>>>> _loadKitBundleData(
# and ends with its closing brace.
# Let's find it using regex or replacement block.
OLD_KIT_BUNDLE_DATA_METHOD = """  // ─────────────────────────────────────────────────────────────────
  // تحميل بيانات الكيت من قاعدة البيانات (مطابق لـ material_consumption_screen)
  // ─────────────────────────────────────────────────────────────────
  Future<Map<String, List<Map<String, dynamic>>>> _loadKitBundleData(
    WindowModel model,
  ) async {
    final kitBundleData = <String, List<Map<String, dynamic>>>{};
    final kitPerLeafResult = <String, bool>{};
    try {
      final sqlDb = widget.db;
      final kits = await sqlDb.readKitBundles();

      for (final kit in kits) {
        final kitName = kit['name'] as String? ?? '';
        if (kitName.isEmpty) continue;
        final kitId = kit['id'] as int;
        final details = await sqlDb.readKitBundleItemsWithDetails(kitId);

        final mutableDetails = <Map<String, dynamic>>[];
        for (final item in details) {
          mutableDetails.add(Map<String, dynamic>.from(item));
        }
        kitBundleData[kitName] = mutableDetails;
        kitPerLeafResult[kitName] = (kit['per_leaf'] ?? 0) == 1;
      }
    } catch (_) {}
    return kitBundleData;
  }"""

# Let's verify if this matches the file content.
# Yes, let's replace it with empty string.
if OLD_KIT_BUNDLE_DATA_METHOD in code:
    code = code.replace(OLD_KIT_BUNDLE_DATA_METHOD, "")
else:
    # Let's try matching with single spacing differences
    # Let's view order_required_goods_screen.dart lines 500 to 540 to check the exact method format.
    print("_loadKitBundleData method not matched exactly.")

with open(path_goods, 'w', encoding='utf-8') as f:
    f.write(code)
print("order_required_goods_screen.dart updated successfully.")
