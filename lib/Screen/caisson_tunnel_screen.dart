import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/widgets/draggable_fab.dart';
import 'package:database_data/Screen/caisson_tunnel_result_screen.dart';

enum KitType {
  kit11, // Adds +11 cm (+110 mm) to Caisson length
  kit16, // Adds +16 cm (+160 mm) to Caisson length
}

enum InputUnit {
  mm, // Millimeter (ملم) - Standard
  cm, // Centimeter (سم)
}

class CaissonItem {
  final String id;
  double lengthMm; // Internal length stored in mm
  int quantity;
  int sizeCm; // 25, 30, or 40 cm

  CaissonItem({
    required this.id,
    required this.lengthMm,
    required this.quantity,
    required this.sizeCm,
  });

  double getAdditionMm(KitType kit) {
    return kit == KitType.kit11 ? 110.0 : 160.0;
  }

  double getCaissonCutLengthMm(KitType kit) {
    return lengthMm + getAdditionMm(kit);
  }

  double getTotalCaissonLengthMm(KitType kit) {
    return getCaissonCutLengthMm(kit) * quantity;
  }

  double getTotalBottomCoverLengthMm() {
    return lengthMm * quantity;
  }
}

class CaissonSizeCalculation {
  final int sizeCm;
  final double caissonLengthMm;
  final double bottomCoverLengthMm;
  final int totalPairs;
  final int caissonBars;
  final int bottomCoverBars;

  CaissonSizeCalculation({
    required this.sizeCm,
    required this.caissonLengthMm,
    required this.bottomCoverLengthMm,
    required this.totalPairs,
    required this.caissonBars,
    required this.bottomCoverBars,
  });
}

class CaissonTunnelScreen extends StatefulWidget {
  const CaissonTunnelScreen({super.key});

  @override
  State<CaissonTunnelScreen> createState() => _CaissonTunnelScreenState();
}

class _CaissonTunnelScreenState extends State<CaissonTunnelScreen> {
  final List<CaissonItem> _items = [];
  KitType _selectedKit = KitType.kit11;
  InputUnit _inputUnit = InputUnit.mm;
  bool _isCalculated = false;

  static const Color _primaryBlue = Color(0xFF1565C0);
  static const Color _accentOrange = Color(0xFFFF9800);

  String get _appBarTitle {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    if (lang == AppLanguage.french || lang == AppLanguage.english) {
      return 'Caisson Tunnel';
    }
    return 'صندوق النفق';
  }

  void _openAddDialog({CaissonItem? editItem}) {
    final double initialVal = editItem != null
        ? (_inputUnit == InputUnit.mm ? editItem.lengthMm : editItem.lengthMm / 10.0)
        : 0;

    final lengthController = TextEditingController(
      text: editItem != null ? (initialVal == initialVal.toInt() ? initialVal.toInt().toString() : initialVal.toStringAsFixed(1)) : '',
    );
    final quantityController = TextEditingController(
      text: editItem != null ? editItem.quantity.toString() : '1',
    );
    int selectedSizeCm = editItem != null ? editItem.sizeCm : 30;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            final unitText = _inputUnit == InputUnit.mm ? 'ملم' : 'سم';

            void submitItem({required bool closeDialog}) {
              final lengthVal = double.tryParse(lengthController.text.trim());
              final qtyVal = int.tryParse(quantityController.text.trim()) ?? 1;

              if (lengthVal == null || lengthVal <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('يرجى إدخال قياس (طول) صحيح بـ $unitText',
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 2),
                  ),
                );
                return;
              }

              // Convert input to internal mm
              final lengthInMm = _inputUnit == InputUnit.mm ? lengthVal : lengthVal * 10.0;

              setState(() {
                if (editItem != null) {
                  editItem.lengthMm = lengthInMm;
                  editItem.quantity = qtyVal > 0 ? qtyVal : 1;
                  editItem.sizeCm = selectedSizeCm;
                } else {
                  _items.add(
                    CaissonItem(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      lengthMm: lengthInMm,
                      quantity: qtyVal > 0 ? qtyVal : 1,
                      sizeCm: selectedSizeCm,
                    ),
                  );
                }
                _isCalculated = false;
              });

              if (closeDialog || editItem != null) {
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      editItem != null ? 'تم تعديل الكيسون بنجاح' : 'تم إضافة الكيسون بنجاح',
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 1),
                  ),
                );
              } else {
                // Keep dialog open for rapid continuous entry
                setDialogState(() {
                  lengthController.clear();
                  quantityController.text = '1';
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تمت الإضافة، يمكنك إدخال قياس آخر مباشرة',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                    backgroundColor: Colors.green,
                    duration: Duration(milliseconds: 1200),
                  ),
                );
              }
            }

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.square_rounded, color: _primaryBlue, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    editItem != null ? 'تعديل الكيسون' : 'إضافة كيسون جديد',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    // Length Field
                    TextField(
                      controller: lengthController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofocus: editItem == null,
                      decoration: InputDecoration(
                        labelText: 'القياس / الطول ($unitText)',
                        hintText: _inputUnit == InputUnit.mm ? 'مثال: 1500' : 'مثال: 150',
                        suffixText: unitText,
                        prefixIcon: const Icon(Icons.straighten, color: _primaryBlue),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 14),

                    // Quantity Field
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: quantityController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'الكمية',
                              prefixIcon: const Icon(Icons.format_list_numbered, color: _primaryBlue),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () {
                            final q = int.tryParse(quantityController.text) ?? 1;
                            if (q > 1) {
                              setDialogState(() {
                                quantityController.text = (q - 1).toString();
                              });
                            }
                          },
                          icon: const Icon(Icons.remove_circle, color: Colors.red, size: 32),
                        ),
                        IconButton(
                          onPressed: () {
                            final q = int.tryParse(quantityController.text) ?? 1;
                            setDialogState(() {
                              quantityController.text = (q + 1).toString();
                            });
                          },
                          icon: const Icon(Icons.add_circle, color: Colors.green, size: 32),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Caisson Size Checkboxes (25 cm, 30 cm, 40 cm)
                    Text(
                      'حجم الكيسون (الأغطية الجانبية):',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.grey.shade300 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [25, 30, 40].map((size) {
                        final isSelected = selectedSizeCm == size;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                selectedSizeCm = size;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? _primaryBlue : (isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? _primaryBlue : Colors.grey.shade400,
                                  width: isSelected ? 2.0 : 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                    size: 18,
                                    color: isSelected ? Colors.white : Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$size سم',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              actions: [
                Row(
                  children: [
                    // Button 1: Cancel
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: const Text('إلغاء',
                          style: TextStyle(fontFamily: 'Cairo', color: Colors.grey, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),

                    if (editItem == null) ...[
                      // Button 2: Add (Keep Open)
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => submitItem(closeDialog: false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentOrange,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('إضافة',
                            style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],

                    // Button 3: Add & Finish / Close
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => submitItem(closeDialog: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryBlue,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          editItem != null ? 'تعديل' : 'إضافة وإنهاء',
                          style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteItem(int index) {
    setState(() {
      _items.removeAt(index);
      _isCalculated = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Addition in mm and cm
    final additionMm = _selectedKit == KitType.kit11 ? 110.0 : 160.0;
    final additionCm = additionMm / 10.0;
    const double barLengthMm = 6000.0;

    // Group items and calculate totals per caisson size (25 cm, 30 cm, 40 cm)
    final Map<int, CaissonSizeCalculation> sizeCalculations = {};

    for (final size in [25, 30, 40]) {
      final itemsForSize = _items.where((i) => i.sizeCm == size).toList();
      if (itemsForSize.isEmpty) continue;

      double sizeCaissonMm = 0;
      double sizeBottomCoverMm = 0;
      int sizePairs = 0;

      for (final item in itemsForSize) {
        sizeCaissonMm += item.getTotalCaissonLengthMm(_selectedKit);
        sizeBottomCoverMm += item.getTotalBottomCoverLengthMm();
        sizePairs += item.quantity;
      }

      final cBars = (sizeCaissonMm / barLengthMm).ceil();
      final bBars = (sizeBottomCoverMm / barLengthMm).ceil();

      sizeCalculations[size] = CaissonSizeCalculation(
        sizeCm: size,
        caissonLengthMm: sizeCaissonMm,
        bottomCoverLengthMm: sizeBottomCoverMm,
        totalPairs: sizePairs,
        caissonBars: cBars,
        bottomCoverBars: bBars,
      );
    }

    // Grand totals across all sizes
    int grandTotalCaissonBars = 0;
    int grandTotalBottomCoverBars = 0;
    int grandTotalPairs = 0;

    sizeCalculations.forEach((_, calc) {
      grandTotalCaissonBars += calc.caissonBars;
      grandTotalBottomCoverBars += calc.bottomCoverBars;
      grandTotalPairs += calc.totalPairs;
    });

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF3F5F8),
      appBar: AppBar(
        title: Text(
          _appBarTitle,
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 1.0,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Kit Selector Header & Unit Selector
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.extension_rounded, color: _primaryBlue, size: 20),
                            const SizedBox(width: 6),
                            Text(
                              'نوع الأغطية (Kit):',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        SegmentedButton<KitType>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: KitType.kit11,
                              label: Text('Kit 11 (+11cm)', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            ButtonSegment(
                              value: KitType.kit16,
                              label: Text('Kit 16 (+16cm)', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                          selected: {_selectedKit},
                          onSelectionChanged: (newSelection) {
                            setState(() {
                              _selectedKit = newSelection.first;
                              _isCalculated = false;
                            });
                          },
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return _primaryBlue;
                              }
                              return isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade200;
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return Colors.white;
                              }
                              return isDark ? Colors.white70 : Colors.black87;
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.square_foot, color: _accentOrange, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'وحدة الإدخال:',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.grey.shade300 : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        SegmentedButton<InputUnit>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: InputUnit.mm,
                              label: Text('ملم (mm)', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                            ButtonSegment(
                              value: InputUnit.cm,
                              label: Text('سم (cm)', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                          selected: {_inputUnit},
                          onSelectionChanged: (newSelection) {
                            setState(() {
                              _inputUnit = newSelection.first;
                            });
                          },
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return _accentOrange;
                              }
                              return isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade200;
                            }),
                            foregroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return Colors.white;
                              }
                              return isDark ? Colors.white70 : Colors.black87;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Items List Area
              Expanded(
                child: _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 70, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'القائمة فارغة كلياً',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'انقر على زر + الإضافة لإدخال قياسات الكيسون',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final cutLengthMm = item.getCaissonCutLengthMm(_selectedKit);

                          final displayLen = _inputUnit == InputUnit.mm ? item.lengthMm : item.lengthMm / 10.0;
                          final displayCutLen = _inputUnit == InputUnit.mm ? cutLengthMm : cutLengthMm / 10.0;
                          final unitStr = _inputUnit == InputUnit.mm ? 'ملم' : 'سم';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 1.5,
                            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: _primaryBlue.withValues(alpha: 0.1),
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.bold,
                                            color: _primaryBlue,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            Text(
                                              'القياس: ${displayLen.toStringAsFixed(0)} $unitStr',
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: isDark ? Colors.white : Colors.black87,
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.shade100,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'مع الزيادة (+$additionCm سم): ${displayCutLen.toStringAsFixed(0)} $unitStr',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.amber.shade900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => _openAddDialog(editItem: item),
                                        child: const Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Icon(Icons.edit, color: Colors.blue, size: 20),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () => _deleteItem(index),
                                        child: const Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Icon(Icons.delete, color: Colors.red, size: 20),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Padding(
                                    padding: const EdgeInsets.only(right: 42),
                                    child: Text(
                                      'الكمية: ${item.quantity}  |  حجم الكيسون: ${item.sizeCm} سم  (زوج x ${item.quantity})',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        color: isDark ? Colors.grey.shade400 : Colors.black54,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Calculation Action Button & Results Card
              if (_items.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              setState(() {
                                _isCalculated = true;
                              });

                              final payload = {
                                'systemType': 'caisson_tunnel',
                                'kitType': _selectedKit == KitType.kit11 ? 'Kit 11 (+11cm)' : 'Kit 16 (+16cm)',
                                'inputUnit': _inputUnit == InputUnit.mm ? 'mm' : 'cm',
                                'itemsCount': _items.length,
                                'grandTotalCaissonBars': grandTotalCaissonBars,
                                'grandTotalBottomCoverBars': grandTotalBottomCoverBars,
                                'grandTotalPairs': grandTotalPairs,
                                'items': _items.map((i) => {
                                  'lengthMm': i.lengthMm,
                                  'quantity': i.quantity,
                                  'sizeCm': i.sizeCm,
                                  'cutLengthMm': i.getCaissonCutLengthMm(_selectedKit),
                                }).toList(),
                                'sizeCalculations': sizeCalculations.map((size, calc) => MapEntry(size.toString(), {
                                  'sizeCm': calc.sizeCm,
                                  'caissonBars': calc.caissonBars,
                                  'bottomCoverBars': calc.bottomCoverBars,
                                  'totalPairs': calc.totalPairs,
                                  'caissonMeters': calc.caissonLengthMm / 1000.0,
                                  'bottomCoverMeters': calc.bottomCoverLengthMm / 1000.0,
                                })),
                              };

                              final result = await Navigator.push<Map<String, dynamic>>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CaissonTunnelResultScreen(caissonData: payload),
                                ),
                              );

                              if (result != null && mounted) {
                                Navigator.of(context).pop(result);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryBlue,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.calculate, color: Colors.white),
                            label: const Text(
                              'حساب البارات والأغطية الجانبية',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),

                        if (_isCalculated) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF262626) : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _primaryBlue.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'المجموع الإجمالي العام:',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: isDark ? Colors.white : _primaryBlue,
                                      ),
                                    ),
                                    Text(
                                      'الكيت: ${_selectedKit == KitType.kit11 ? "Kit 11 (+11cm)" : "Kit 16 (+16cm)"}',
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),

                                // Grand Caisson Bars Total
                                _buildResultRow(
                                  icon: Icons.view_day_rounded,
                                  title: 'إجمالي بارات الكيسون (6 أمتار):',
                                  value: '$grandTotalCaissonBars بارة',
                                  subtext: 'مجموع البارات الإجمالية لكافة أحجام الكيسون المستعملة',
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 8),

                                // Grand Bottom Cover Bars Total
                                _buildResultRow(
                                  icon: Icons.horizontal_rule_rounded,
                                  title: 'إجمالي بارات أغطية الكيسون (6 أمتار):',
                                  value: '$grandTotalBottomCoverBars بارة',
                                  subtext: 'مجموع أغطية الكيسون السفلية لكافة الأحجام',
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 8),

                                // Grand Side Covers Pairs Total
                                _buildResultRow(
                                  icon: Icons.square_rounded,
                                  title: 'إجمالي الأغطية الجانبية (بالزوج / Paire):',
                                  value: '$grandTotalPairs زوج',
                                  subtext: 'مجموع أزواج الأغطية الجانبية لكافة الأحجام',
                                  isDark: isDark,
                                ),

                                const Divider(height: 20, thickness: 1.2),

                                // Detailed Breakdown per Caisson Size (25cm, 30cm, 40cm)
                                Text(
                                  'تفاصيل الحساب مقسمة حسب حجم الكيسون:',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isDark ? Colors.orangeAccent : _accentOrange,
                                  ),
                                ),
                                const SizedBox(height: 10),

                                ...sizeCalculations.values.map((calc) {
                                  final cMeters = calc.caissonLengthMm / 1000.0;
                                  final bMeters = calc.bottomCoverLengthMm / 1000.0;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade400),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.widgets_outlined, size: 16, color: _primaryBlue),
                                            const SizedBox(width: 6),
                                            Text(
                                              'كيسون حجم ${calc.sizeCm} سم:',
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: isDark ? Colors.white : Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          ' • بارات الكيسون (6م): ${calc.caissonBars} بارة (الطول: ${cMeters.toStringAsFixed(2)} م)',
                                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: isDark ? Colors.grey.shade300 : Colors.black87),
                                        ),
                                        Text(
                                          ' • بارات الغطاء السفلي (6م): ${calc.bottomCoverBars} بارة (الطول: ${bMeters.toStringAsFixed(2)} م)',
                                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: isDark ? Colors.grey.shade300 : Colors.black87),
                                        ),
                                        Text(
                                          ' • أغطية جانبية ${calc.sizeCm}سم: ${calc.totalPairs} زوج (Paire)',
                                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: _accentOrange),
                                        ),
                                      ],
                                    ),
                                  );
                                }),

                                const SizedBox(height: 12),

                                // Button: Add to Order
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      final orderPayload = {
                                        'systemType': 'caisson_tunnel',
                                        'kitType': _selectedKit == KitType.kit11 ? 'Kit 11 (+11cm)' : 'Kit 16 (+16cm)',
                                        'inputUnit': _inputUnit == InputUnit.mm ? 'mm' : 'cm',
                                        'itemsCount': _items.length,
                                        'grandTotalCaissonBars': grandTotalCaissonBars,
                                        'grandTotalBottomCoverBars': grandTotalBottomCoverBars,
                                        'grandTotalPairs': grandTotalPairs,
                                        'items': _items.map((i) => {
                                          'lengthMm': i.lengthMm,
                                          'quantity': i.quantity,
                                          'sizeCm': i.sizeCm,
                                          'cutLengthMm': i.getCaissonCutLengthMm(_selectedKit),
                                        }).toList(),
                                        'sizeCalculations': sizeCalculations.map((size, calc) => MapEntry(size.toString(), {
                                          'sizeCm': calc.sizeCm,
                                          'caissonBars': calc.caissonBars,
                                          'bottomCoverBars': calc.bottomCoverBars,
                                          'totalPairs': calc.totalPairs,
                                          'caissonMeters': calc.caissonLengthMm / 1000.0,
                                          'bottomCoverMeters': calc.bottomCoverLengthMm / 1000.0,
                                        })),
                                      };
                                      Navigator.of(context).pop(orderPayload);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('تمت إضافة كيسون النفق إلى الطلب بنجاح', style: TextStyle(fontFamily: 'Cairo')),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade700,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
                                    label: const Text(
                                      'إضافة كيسون النفق إلى الطلب',
                                      style: TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Draggable Floating Action Button
          DraggableFloatingActionButton(
            onPressed: () => _openAddDialog(),
            backgroundColor: _accentOrange,
            icon: Icons.add,
            label: 'إضافة كيسون',
            initialOffset: const Offset(16, 220),
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow({
    required IconData icon,
    required String title,
    required String value,
    required String subtext,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: _primaryBlue),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isDark ? Colors.orangeAccent : _accentOrange,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: 24, top: 2),
          child: Text(
            subtext,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              color: Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}
