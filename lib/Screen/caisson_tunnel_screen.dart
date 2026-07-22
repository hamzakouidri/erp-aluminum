import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';

enum KitType {
  kit11, // Adds +11 cm to Caisson length
  kit16, // Adds +16 cm to Caisson length
}

class CaissonItem {
  final String id;
  double lengthCm;
  int quantity;
  int sizeCm; // 25, 30, or 40

  CaissonItem({
    required this.id,
    required this.lengthCm,
    required this.quantity,
    required this.sizeCm,
  });

  double getAdditionCm(KitType kit) {
    return kit == KitType.kit11 ? 11.0 : 16.0;
  }

  double getCaissonCutLengthCm(KitType kit) {
    return lengthCm + getAdditionCm(kit);
  }

  double getTotalCaissonLengthCm(KitType kit) {
    return getCaissonCutLengthCm(kit) * quantity;
  }

  double getTotalBottomCoverLengthCm() {
    return lengthCm * quantity;
  }
}

class CaissonTunnelScreen extends StatefulWidget {
  const CaissonTunnelScreen({super.key});

  @override
  State<CaissonTunnelScreen> createState() => _CaissonTunnelScreenState();
}

class _CaissonTunnelScreenState extends State<CaissonTunnelScreen> {
  final List<CaissonItem> _items = [];
  KitType _selectedKit = KitType.kit11;
  bool _isCalculated = false;

  static const Color _primaryBlue = Color(0xFF1565C0);
  static const Color _accentOrange = Color(0xFFFF9800);

  String t(String key) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    try {
      return Localization.translate(key, lang);
    } catch (_) {
      return key;
    }
  }

  void _openAddDialog({CaissonItem? editItem}) {
    final lengthController = TextEditingController(
      text: editItem != null ? editItem.lengthCm.toStringAsFixed(0) : '',
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

            void submitItem({required bool closeDialog}) {
              final lengthVal = double.tryParse(lengthController.text.trim());
              final qtyVal = int.tryParse(quantityController.text.trim()) ?? 1;

              if (lengthVal == null || lengthVal <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى إدخال قياس (طول) صحيح بالكيسون',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }

              setState(() {
                if (editItem != null) {
                  editItem.lengthCm = lengthVal;
                  editItem.quantity = qtyVal > 0 ? qtyVal : 1;
                  editItem.sizeCm = selectedSizeCm;
                } else {
                  _items.add(
                    CaissonItem(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      lengthCm: lengthVal,
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
                        labelText: 'القياس / الطول (سم أو مم)',
                        hintText: 'مثال: 150',
                        suffixText: 'سم',
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
                      'حجم الكيسون (حجم الغطاء الجانبي):',
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

    final additionCm = _selectedKit == KitType.kit11 ? 11.0 : 16.0;

    // Totals calculations
    double totalCaissonCm = 0;
    double totalBottomCoverCm = 0;
    int pairs25 = 0;
    int pairs30 = 0;
    int pairs40 = 0;

    for (final item in _items) {
      totalCaissonCm += item.getTotalCaissonLengthCm(_selectedKit);
      totalBottomCoverCm += item.getTotalBottomCoverLengthCm();
      if (item.sizeCm == 25) pairs25 += item.quantity;
      if (item.sizeCm == 30) pairs30 += item.quantity;
      if (item.sizeCm == 40) pairs40 += item.quantity;
    }

    final totalPairs = pairs25 + pairs30 + pairs40;

    // Standard bar length = 600 cm (6 meters)
    const barLengthCm = 600.0;
    final caissonBars = _items.isEmpty ? 0 : (totalCaissonCm / barLengthCm).ceil();
    final bottomCoverBars = _items.isEmpty ? 0 : (totalBottomCoverCm / barLengthCm).ceil();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF3F5F8),
      appBar: AppBar(
        title: const Text('كيسون تونيل (Caisson Tunnel)',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : _primaryBlue,
        foregroundColor: Colors.white,
        elevation: 1.0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddDialog(),
        backgroundColor: _accentOrange,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('إضافة كيسون',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          // Kit Selector Header
          Container(
            padding: const EdgeInsets.all(12),
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: Row(
              children: [
                const Icon(Icons.extension_rounded, color: _primaryBlue),
                const SizedBox(width: 8),
                Text(
                  'نوع الأغطية الجانبية (Kit):',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                SegmentedButton<KitType>(
                  segments: const [
                    ButtonSegment(
                      value: KitType.kit11,
                      label: Text('Kit 11 (+11cm)', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    ButtonSegment(
                      value: KitType.kit16,
                      label: Text('Kit 16 (+16cm)', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  selected: {_selectedKit},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _selectedKit = newSelection.first;
                    });
                  },
                  style: ButtonStyle(
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
                          'انقر على زر + الأسفل لإضافة مقاسات الكيسون',
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
                      final cutLengthCm = item.getCaissonCutLengthCm(_selectedKit);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 1.5,
                        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: _primaryBlue.withValues(alpha: 0.1),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    color: _primaryBlue,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'القياس: ${item.lengthCm.toStringAsFixed(0)} سم',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade100,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'مع الزيادة: ${cutLengthCm.toStringAsFixed(0)} سم',
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'الكمية: ${item.quantity}  |  حجم الأغطية: ${item.sizeCm} سم  (زوج x ${item.quantity})',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        color: isDark ? Colors.grey.shade400 : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                                onPressed: () => _openAddDialog(editItem: item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                onPressed: () => _deleteItem(index),
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
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _isCalculated = true;
                        });
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
                                'النتائج الإجمالية المطلوبة:',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: isDark ? Colors.white : _primaryBlue,
                                ),
                              ),
                              Text(
                                'نوع الكيت: ${_selectedKit == KitType.kit11 ? "Kit 11 (+11cm)" : "Kit 16 (+16cm)"}',
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                              ),
                            ],
                          ),
                          const Divider(height: 16),

                          // Caisson Bars Total
                          _buildResultRow(
                            icon: Icons.view_day_rounded,
                            title: 'بارات الكيسون (6 أمتار):',
                            value: '$caissonBars بارة',
                            subtext: 'مجموع الطول: ${(totalCaissonCm / 100).toStringAsFixed(2)} متر (مع زيادة $additionCm سم لكل قطعة)',
                            isDark: isDark,
                          ),
                          const SizedBox(height: 8),

                          // Bottom Cover Bars Total
                          _buildResultRow(
                            icon: Icons.horizontal_rule_rounded,
                            title: 'بارات غطاء الكيسون السفلي (6 أمتار):',
                            value: '$bottomCoverBars بارة',
                            subtext: 'مجموع الطول: ${(totalBottomCoverCm / 100).toStringAsFixed(2)} متر (بدون زيادات الأغطية)',
                            isDark: isDark,
                          ),
                          const SizedBox(height: 8),

                          // Side Covers Pairs Breakdown
                          _buildResultRow(
                            icon: Icons.square_rounded,
                            title: 'الأغطية الجانبية (بالزوج / Paire):',
                            value: '$totalPairs زوج',
                            subtext: 'التفصيل: ${pairs25 > 0 ? "25سم ($pairs25 زوج)  " : ""}${pairs30 > 0 ? "30سم ($pairs30 زوج)  " : ""}${pairs40 > 0 ? "40سم ($pairs40 زوج)" : ""}',
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
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
