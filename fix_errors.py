import re

# 1. Fix price_management_screen.dart
price_file = "lib/Screen/price_management_screen.dart"
with open(price_file, "r", encoding="utf-8") as f:
    content = f.read()

# _updatePrice
content = content.replace("""
  Future<void> _updatePrice(
    String table,
    int id,
    String column,
    double newPrice,
  ) async {
""", """
  Future<void> _updatePrice(
    String table,
    int id,
    String column,
    double newPrice,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
""")

# _updateSeriesColorPrice
content = content.replace("""
  Future<void> _updateSeriesColorPrice(
    int seriesId,
    int colorId,
    double price,
  ) async {
""", """
  Future<void> _updateSeriesColorPrice(
    int seriesId,
    int colorId,
    double price,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
""")

# _buildSeriesColorTab
content = content.replace("""
  Widget _buildSeriesColorTab() {
""", """
  Widget _buildSeriesColorTab(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
""")
content = content.replace("child: _buildSeriesColorTab(),", "child: _buildSeriesColorTab(context),")

# _buildList
content = content.replace("""
  Widget _buildList(
    List<Map<String, dynamic>> list,
    String tableName,
    String titleKey,
    String priceKey,
    String priceLabel,
  ) {
""", """
  Widget _buildList(
    BuildContext context,
    List<Map<String, dynamic>> list,
    String tableName,
    String titleKey,
    String priceKey,
    String priceLabel,
  ) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
""")
content = content.replace("_buildList(\n                    glassList,", "_buildList(context,\n                    glassList,")
content = content.replace("_buildList(\n                    shutterList,", "_buildList(context,\n                    shutterList,")
content = content.replace("_buildList(\n                    jointList,", "_buildList(context,\n                    jointList,")
content = content.replace("_buildList(\n                    accessoryList,", "_buildList(context,\n                    accessoryList,")

with open(price_file, "w", encoding="utf-8") as f:
    f.write(content)

# 2. Fix localization.dart
loc_file = "lib/settings/localization.dart"
with open(loc_file, "r", encoding="utf-8") as f:
    lines = f.readlines()

new_lines = []
skip = False
skip_count = 0
for line in lines:
    if "'الألوان': {" in line or "'سعر المتر المربع': {" in line or "'السعر': {" in line or "'حفظ': {" in line:
        # Check if it's in the second block (after line 850)
        if len(new_lines) > 800:
            skip = True
            skip_count = 5
    if skip:
        skip_count -= 1
        if skip_count == 0:
            skip = False
        continue
    new_lines.append(line)

with open(loc_file, "w", encoding="utf-8") as f:
    f.writelines(new_lines)
