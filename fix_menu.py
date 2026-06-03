import re

path = 'lib/items_produits/products_menu_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

target = '''              },
            ),
          ],
        ),
      ),
    );
  }'''

replacement = '''              },
            ),
            const SizedBox(height: 16),
            _buildMenuCard(
              context,
              title: Localization.translate("الألوان", lang),
              icon: Icons.color_lens_rounded,
              color: Colors.purple,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ColorsScreen(db: db)),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildMenuCard(
              context,
              title: Localization.translate("الإكسسوارات", lang),
              icon: Icons.construction_rounded,
              color: Colors.orange,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AccessoriesScreen(db: db),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildMenuCard(
              context,
              title: Localization.translate("الجوانات", lang),
              icon: Icons.line_weight_rounded,
              color: Colors.teal,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => JointScreen(db: db)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }'''

if target in content:
    content = content.replace(target, replacement)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Success")
else:
    print("Target not found")
