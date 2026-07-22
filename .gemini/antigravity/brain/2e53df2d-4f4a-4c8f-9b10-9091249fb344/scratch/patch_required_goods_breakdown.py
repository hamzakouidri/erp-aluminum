import re

path_goods = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\order_required_goods_screen.dart'

with open(path_goods, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update imports
OLD_IMPORTS = """import 'package:database_data/Commande/Systeme/calculate_component.dart';"""
NEW_IMPORTS = """import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/window_painter.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:provider/provider.dart';"""

assert OLD_IMPORTS in code, "OLD_IMPORTS not found"
code = code.replace(OLD_IMPORTS, NEW_IMPORTS, 1)

# 2. Add ProductBreakdown class
OLD_CLASS_GOOD = """class AggregatedGoodItem {"""
NEW_CLASS_GOOD = """class ProductBreakdown {
  final int index;
  final String name;
  final int qty;
  final double width;
  final double height;
  final WindowModel model;
  final List<BomItem> bomItems;

  ProductBreakdown({
    required this.index,
    required this.name,
    required this.qty,
    required this.width,
    required this.height,
    required this.model,
    required this.bomItems,
  });
}

class AggregatedGoodItem {"""

assert OLD_CLASS_GOOD in code, "OLD_CLASS_GOOD not found"
code = code.replace(OLD_CLASS_GOOD, NEW_CLASS_GOOD, 1)

# 3. Add _productBreakdowns state variable
OLD_STATE_VARS = """  List<AggregatedGoodItem> _aggregatedItems = [];
  int _productCount = 0;"""
NEW_STATE_VARS = """  List<AggregatedGoodItem> _aggregatedItems = [];
  int _productCount = 0;
  List<ProductBreakdown> _productBreakdowns = [];"""

assert OLD_STATE_VARS in code, "OLD_STATE_VARS not found"
code = code.replace(OLD_STATE_VARS, NEW_STATE_VARS, 1)

# 4. Update _loadAndAggregate to clear and populate breakdownsTemp
# Let's locate the BOM generation part inside _loadAndAggregate
OLD_BOM_GEN_LOOP = """          final List<BomItem> bomItems = [];

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

              // Generate BOM for this specific instance using the new resolver
              final instBom = await _resolveBomForModel(model, kitBundleData, kitPerLeafMap);
              bomItems.addAll(instBom);
            }

            // Restore original values
            model.width = origW;
            model.height = origH;
            model.quantity = origQty;
          } else {
            final instBom = await _resolveBomForModel(model, kitBundleData, kitPerLeafMap);
            bomItems.addAll(instBom);
          }"""

NEW_BOM_GEN_LOOP = """          final List<BomItem> bomItems = [];
          final productName = item['name']?.toString() ?? 'منتج ${successCount + 1}';

          if (instances.isNotEmpty) {
            final double origW = model.width;
            final double origH = model.height;
            final int origQty = model.quantity;

            int instIdx = 1;
            for (final inst in instances) {
              final double w = (inst['width'] as num).toDouble();
              final double h = (inst['height'] as num).toDouble();
              final int qty = inst['qty'] as int;

              model.width = w;
              model.height = h;
              model.quantity = qty;

              // Generate BOM for this specific instance using the new resolver
              final instBom = await _resolveBomForModel(model, kitBundleData, kitPerLeafMap);
              bomItems.addAll(instBom);

              // Create a dedicated instance model for drawing and individual listing
              final instanceModel = WindowModel(db: widget.db);
              await applyWindowModelAndLoadCatalog(instanceModel, modelMap);
              instanceModel.width = w;
              instanceModel.height = h;
              instanceModel.quantity = qty;

              breakdownsTemp.add(ProductBreakdown(
                index: successCount + 1,
                name: '$productName (#$instIdx)',
                qty: qty,
                width: w,
                height: h,
                model: instanceModel,
                bomItems: instBom.where((b) => b.isActive && !b.isMissing).toList(),
              ));
              instIdx++;
            }

            // Restore original values
            model.width = origW;
            model.height = origH;
            model.quantity = origQty;
          } else {
            final instBom = await _resolveBomForModel(model, kitBundleData, kitPerLeafMap);
            bomItems.addAll(instBom);

            breakdownsTemp.add(ProductBreakdown(
              index: successCount + 1,
              name: productName,
              qty: model.quantity,
              width: model.width,
              height: model.height,
              model: model,
              bomItems: instBom.where((b) => b.isActive && !b.isMissing).toList(),
            ));
          }"""

assert OLD_BOM_GEN_LOOP in code, "OLD_BOM_GEN_LOOP not found"
code = code.replace(OLD_BOM_GEN_LOOP, NEW_BOM_GEN_LOOP, 1)

# 5. Initialize and set breakdownsTemp in _loadAndAggregate
OLD_AGGREGATION_START = """      // مخزن التجميع: مفتاح التجميع → السلعة المجمّعة
      // مفتاح التجميع = (originalName + unit + imagePath) لتمييز السلع الفريدة
      final Map<String, AggregatedGoodItem> aggregationMap = {};
      int successCount = 0;"""
NEW_AGGREGATION_START = """      // مخزن التجميع: مفتاح التجميع → السلعة المجمّعة
      // مفتاح التجميع = (originalName + unit + imagePath) لتمييز السلع الفريدة
      final Map<String, AggregatedGoodItem> aggregationMap = {};
      int successCount = 0;
      final List<ProductBreakdown> breakdownsTemp = [];"""

assert OLD_AGGREGATION_START in code, "OLD_AGGREGATION_START not found"
code = code.replace(OLD_AGGREGATION_START, NEW_AGGREGATION_START, 1)

# Set breakdownsTemp in setState
OLD_SETSTATE = """      setState(() {
        _aggregatedItems = sorted;
        _productCount = successCount;
        _isLoading = false;
      });"""
NEW_SETSTATE = """      setState(() {
        _aggregatedItems = sorted;
        _productCount = successCount;
        _productBreakdowns = breakdownsTemp;
        _isLoading = false;
      });"""

assert OLD_SETSTATE in code, "OLD_SETSTATE not found"
code = code.replace(OLD_SETSTATE, NEW_SETSTATE, 1)

# 6. Add new button to AppBar actions
OLD_APPBAR_ACTIONS = """        actions: [
          if (!_isLoading && _errorMessage == null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'إعادة الحساب',
              onPressed: _loadAndAggregate,
            ),
        ],"""
NEW_APPBAR_ACTIONS = """        actions: [
          if (!_isLoading && _errorMessage == null && _productBreakdowns.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.table_chart_outlined, color: Colors.white),
              label: const Text(
                'تفاصيل كل منتج',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: _showProductBreakdownDialog,
            ),
          if (!_isLoading && _errorMessage == null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'إعادة الحساب',
              onPressed: _loadAndAggregate,
            ),
        ],"""

assert OLD_APPBAR_ACTIONS in code, "OLD_APPBAR_ACTIONS not found"
code = code.replace(OLD_APPBAR_ACTIONS, NEW_APPBAR_ACTIONS, 1)

# 7. Add _showProductBreakdownDialog method before the end of the class
# Let's insert it before line: IconData _categoryIcon(String category) {
# Or just before the last closing brace.
# Let's find the closing brace by searching for _categoryIcon
OLD_METHOD_REF = """  IconData _categoryIcon(String category) {"""
NEW_METHODS = """  void _showProductBreakdownDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFFF0F4FF),
          appBar: AppBar(
            title: const Text('تفاصيل حساب كل منتج', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
          ),
          body: ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: _productBreakdowns.length,
            itemBuilder: (context, index) {
              final pb = _productBreakdowns[index];
              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 24.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Drawing thumbnail
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8.0),
                              child: CustomPaint(
                                painter: WindowPainter(model: pb.model),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // 2. Product basic info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pb.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A237E)),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'المقاس: ${pb.width.toStringAsFixed(0)} مم × ${pb.height.toStringAsFixed(0)} مم',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'الكمية: ${pb.qty} حبة',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'السلسلة: ${pb.model.activeSeries?.name ?? pb.model.activeSlidingSeries?.name ?? "غير محدد"}',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // 3. Materials List
                      const Text(
                        'العناصر والمواد المحسوبة لهذا المنتج:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      Table(
                        border: TableBorder.symmetric(inside: BorderSide(color: Colors.grey.shade300, width: 0.5)),
                        columnWidths: const {
                          0: FlexColumnWidth(3),
                          1: FlexColumnWidth(1),
                          2: FlexColumnWidth(1),
                          3: FlexColumnWidth(1.2),
                        },
                        children: [
                          TableRow(
                            decoration: BoxDecoration(color: Colors.grey.shade200),
                            children: const [
                              Padding(padding: EdgeInsets.all(6.0), child: Text('اسم العنصر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Padding(padding: EdgeInsets.all(6.0), child: Text('الكمية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Padding(padding: EdgeInsets.all(6.0), child: Text('الوحدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Padding(padding: EdgeInsets.all(6.0), child: Text('التكلفة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            ],
                          ),
                          ...pb.bomItems.map((bom) {
                            final double qty = (bom.exactQuantity ?? bom.quantity);
                            final double cost = qty * bom.unitPrice;
                            return TableRow(
                              children: [
                                Padding(padding: const EdgeInsets.all(6.0), child: Text(bom.name, style: const TextStyle(fontSize: 12))),
                                Padding(padding: const EdgeInsets.all(6.0), child: Text(qty.toStringAsFixed(2), style: const TextStyle(fontSize: 12))),
                                Padding(padding: const EdgeInsets.all(6.0), child: Text(bom.unit, style: const TextStyle(fontSize: 12))),
                                Padding(padding: const EdgeInsets.all(6.0), child: Text('${cost.toStringAsFixed(0)} د.ج', style: const TextStyle(fontSize: 11))),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {"""

assert OLD_METHOD_REF in code, "OLD_METHOD_REF not found"
code = code.replace(OLD_METHOD_REF, NEW_METHODS, 1)

with open(path_goods, 'w', encoding='utf-8') as f:
    f.write(code)
print("order_required_goods_screen.dart updated successfully with breakdown.")
