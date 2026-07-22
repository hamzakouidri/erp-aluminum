import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/Commande/order_required_goods_screen.dart'
content = open(path, encoding='utf-8').read()

old_bom_code = """          // توليد قائمة BOM لهذا المنتج
          final bomItems = ComponentCalculator.generateBom(
            model,
            activeVariants,
            kitBundleData: kitBundleData,
            kitPerLeafMap: kitPerLeafMap,
          );"""

new_bom_code = """          // Read instances if they exist
          final instancesJson = item['instances_json'];
          List<Map<String, dynamic>> instances = [];
          if (instancesJson != null && instancesJson.toString().isNotEmpty) {
            try {
              final decoded = jsonDecode(instancesJson.toString()) as List<dynamic>;
              instances = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
            } catch (_) {}
          }

          final List<BomItem> bomItems = [];

          if (instances.isNotEmpty) {
            final double origW = model.width;
            final double origH = model.height;
            final int origQty = model.quantity;

            for (final inst in instances) {
              final double w = (inst['width'] as num).toDouble();
              final double h = (inst['height'] as num).toDouble();
              final int qty = inst['qty'] as int;

              model.width = w;
              model.height = h;
              model.quantity = qty;

              // Generate BOM for this specific instance
              final instBom = ComponentCalculator.generateBom(
                model,
                activeVariants,
                kitBundleData: kitBundleData,
                kitPerLeafMap: kitPerLeafMap,
              );
              bomItems.addAll(instBom);
            }

            // Restore original values
            model.width = origW;
            model.height = origH;
            model.quantity = origQty;
          } else {
            final instBom = ComponentCalculator.generateBom(
              model,
              activeVariants,
              kitBundleData: kitBundleData,
              kitPerLeafMap: kitPerLeafMap,
            );
            bomItems.addAll(instBom);
          }"""

content = content.replace(old_bom_code, new_bom_code)
open(path, 'w', encoding='utf-8').write(content)
print("Done updating order_required_goods_screen.dart to use detailed window measurements!")
