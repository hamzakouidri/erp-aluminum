import re

file_path = "lib/items_produits/products_menu_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Replace the Scaffold background and AppBar color
content = content.replace("backgroundColor: Colors.blueAccent,", "backgroundColor: Colors.blue, centerTitle: true,")
content = content.replace("decoration: BoxDecoration(color: Colors.grey.shade50),", "decoration: BoxDecoration(color: Colors.grey[100]),")

# Update _buildMenuCard to match ChooseSystem exactly
new_card = """
  Widget _buildMenuCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(width: 1, color: Colors.grey),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.2),
              spreadRadius: 5,
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.blue,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
"""

content = re.sub(r'  Widget _buildMenuCard\(.*?\)\n  \}', new_card, content, flags=re.DOTALL)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
