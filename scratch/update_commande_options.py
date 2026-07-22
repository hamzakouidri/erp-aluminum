import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/Commande/commande.dart'
content = open(path, encoding='utf-8').read()

# 1. Add import
old_import = "import 'package:database_data/Commande/order_required_goods_screen.dart';"
new_import = """import 'package:database_data/Commande/order_required_goods_screen.dart';
import 'package:database_data/Commande/order_measurements_confirm_screen.dart';"""

content = content.replace(old_import, new_import)

# 2. Add ListTile before the Divider and Confirmer tile
old_block = """              // 3.5 السلع المطلوبة (مجمّعة من كل المنتجات)
              ListTile(
                leading: const Icon(Icons.shopping_basket, color: Colors.deepPurple),
                title: const Text('السلع المطلوبة'),
                subtitle: const Text(
                  'مجموع سلع جميع المنتجات مجمّعة',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderRequiredGoodsScreen(
                        orderData: orderData,
                        db: db,
                      ),
                    ),
                  );
                },
              ),

              const Divider(),"""

new_block = """              // 3.5 السلع المطلوبة (مجمّعة من كل المنتجات)
              ListTile(
                leading: const Icon(Icons.shopping_basket, color: Colors.deepPurple),
                title: const Text('السلع المطلوبة'),
                subtitle: const Text(
                  'مجموع سلع جميع المنتجات مجمّعة',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderRequiredGoodsScreen(
                        orderData: orderData,
                        db: db,
                      ),
                    ),
                  );
                },
              ),

              // 3.8 تأكيد القياسات والملصقات
              ListTile(
                leading: const Icon(Icons.line_weight_rounded, color: Colors.indigoAccent),
                title: const Text('تأكيد القياسات والملصقات (Stickers)'),
                subtitle: const Text(
                  'تعديل القياسات الفعلية للموقع وطباعة الباركود لكل قطعة',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderMeasurementsConfirmScreen(
                        orderData: orderData,
                        db: db,
                      ),
                    ),
                  );
                },
              ),

              const Divider(),"""

content = content.replace(old_block, new_block)
open(path, 'w', encoding='utf-8').write(content)
print("Done updating commande.dart to integrate OrderMeasurementsConfirmScreen!")
