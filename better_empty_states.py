import re

file_path = "lib/Screen/price_management_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

better_empty_states = """
  Widget _buildSeriesColorTab() {
    if (seriesList.isEmpty) {
      return Center(
        child: Text(
          'No series found. Please add series first.',
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
        ),
      );
    }
    if (colorList.isEmpty) {
      return Center(
        child: Text(
          'No colors found. Please add colors from the products menu first.',
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
"""

content = re.sub(r'  Widget _buildSeriesColorTab\(\) \{\n    if \(seriesList\.isEmpty \|\| colorList\.isEmpty\) \{\n      return Center\(child: Text\(\'No data found\'\)\);\n    \}\n\n    return Column\(', better_empty_states, content)

better_list_empty = """
  Widget _buildList(List<Map<String, dynamic>> list, String tableName, String nameCol, String priceCol, String subtitle) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          'No items found. Please add them from the products menu first.',
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }
"""

content = re.sub(r'  Widget _buildList\(List<Map<String, dynamic>> list, String tableName, String nameCol, String priceCol, String subtitle\) \{\n    if \(list\.isEmpty\) \{\n      return Center\(child: Text\(\'No data found\'\)\);\n    \}', better_list_empty, content)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
