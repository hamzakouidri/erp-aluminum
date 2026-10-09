import 'package:flutter/material.dart';

import '../sql_database.dart';

/// نافذة مراجعة وتأكيد الفضلات للعامل عند الضغط على "تم الصنع"
/// تتيح:
/// 1. التعديل المباشر على طول الفضلة
/// 2. تأكيد الفضلة لتصبح متاحة في المخزون
/// 3. تحويل الفضلة إلى هالك (Scrap)
/// 4. زر [إضافة] لإضافة فضلة ناتجة بدون سحب بارة
/// 5. زر [خطأ في القص] لسحب بارة إضافية بسبب تلف قطاع وتحديد الفضلة الناتجة عنها
class WorkerRemnantsReviewDialog extends StatefulWidget {
  final int orderId;
  final String orderCode;
  final String windowType;
  final SqlDatabase db;

  const WorkerRemnantsReviewDialog({
    super.key,
    required this.orderId,
    required this.orderCode,
    required this.windowType,
    required this.db,
  });

  @override
  State<WorkerRemnantsReviewDialog> createState() => _WorkerRemnantsReviewDialogState();
}

class _WorkerRemnantsReviewDialogState extends State<WorkerRemnantsReviewDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _remnants = [];
  final Map<int, TextEditingController> _lengthControllers = {};
  final Map<int, TextEditingController> _rackControllers = {};
  final Set<int> _confirmedIds = {};
  final Set<int> _scrappedIds = {};

  List<Map<String, dynamic>> _orderSections = [];
  List<Map<String, dynamic>> _locations = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (var c in _lengthControllers.values) {
      c.dispose();
    }
    for (var c in _rackControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final rems = await widget.db.readMaterialRemnantsForOrder(widget.orderId);
      final locs = await widget.db.readLocations();

      // جلب المقاطع المستخدمة في هذه الطلبية حصراً
      final myDb = await widget.db.db;
      List<Map<String, dynamic>> sections = [];
      if (myDb != null) {
        sections = await myDb.rawQuery('''
          SELECT DISTINCT s.id, s.name, s.code, s.series_id, cd.color AS color_name
          FROM Commandes_details cd
          JOIN Sections s ON s.series_id IS NOT NULL
          WHERE cd.id_commandes = ?
          LIMIT 30
        ''', [widget.orderId]);
      }

      for (var r in rems) {
        final id = (r['id'] as num).toInt();
        final len = ((r['length_mm'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0);
        _lengthControllers[id] = TextEditingController(text: len);
        _rackControllers[id] = TextEditingController(text: r['rack_code']?.toString() ?? '');
      }

      if (mounted) {
        setState(() {
          _remnants = rems.map((e) => Map<String, dynamic>.from(e)).toList();
          _locations = locs;
          _orderSections = sections;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading remnants for review: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmItem(Map<String, dynamic> item) async {
    final id = (item['id'] as num).toInt();
    final lenCtrl = _lengthControllers[id];
    final rackCtrl = _rackControllers[id];
    final len = double.tryParse(lenCtrl?.text.trim() ?? '') ?? ((item['length_mm'] as num?)?.toDouble() ?? 0.0);

    if (len <= 0) return;

    await widget.db.confirmMaterialRemnant(
      remnantId: id,
      actualLengthMm: len,
      rackCode: rackCtrl?.text.trim(),
    );

    setState(() {
      _confirmedIds.add(id);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تأكيد دخول الفضلة إلى المخزون بنجاح ✅'),
          backgroundColor: Colors.green,
          duration: Duration(milliseconds: 900),
        ),
      );
    }
  }

  Future<void> _scrapItem(Map<String, dynamic> item) async {
    final id = (item['id'] as num).toInt();
    await widget.db.scrapMaterialRemnant(
      remnantId: id,
      reason: 'تم تحويلها لهالك من قبل العامل',
    );

    setState(() {
      _scrappedIds.add(id);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحويل الفضلة إلى هالك (Scrap) 🗑️'),
          backgroundColor: Colors.redAccent,
          duration: Duration(milliseconds: 900),
        ),
      );
    }
  }

  // نافذة الإضافة المباشرة لفضلة إضافية بدون سحب بارة
  Future<void> _showAddExtraRemnantDialog() async {
    final lenCtrl = TextEditingController(text: '800');
    final rackCtrl = TextEditingController();
    Map<String, dynamic>? selectedSec = _orderSections.isNotEmpty ? _orderSections.first : null;
    int? selectedLoc = _locations.isNotEmpty ? (_locations.first['id'] as num).toInt() : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.add_circle_outline, color: Colors.blue),
              SizedBox(width: 8),
              Text('إضافة فضلة إضافية ناتجة', style: TextStyle(fontFamily: 'Cairo', fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'إضافة فضلة ناتجة من نفس البارات المستخدمة بدون سحب بارة جديدة.',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                if (_orderSections.isNotEmpty)
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: selectedSec,
                    decoration: const InputDecoration(labelText: 'المقطع المستعمل', border: OutlineInputBorder()),
                    items: _orderSections.map((s) => DropdownMenuItem(
                      value: s,
                      child: Text('${s['name']} (${s['code'] ?? ''})', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    )).toList(),
                    onChanged: (val) => setDlgState(() => selectedSec = val),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: lenCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'طول الفضلة (مم)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: rackCtrl,
                  decoration: const InputDecoration(labelText: 'مكان الرف / الخانة (Rack)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () async {
                final len = double.tryParse(lenCtrl.text.trim()) ?? 0.0;
                if (len <= 50 || selectedSec == null || selectedLoc == null) return;
                await widget.db.insertMaterialRemnant({
                  'item_id': selectedSec!['id'],
                  'item_type': 'Section',
                  'series_id': selectedSec!['series_id'],
                  'length_mm': len,
                  'location_id': selectedLoc,
                  'rack_code': rackCtrl.text.trim(),
                  'source_order_id': widget.orderId,
                  'status': 'available',
                  'note': 'فضلة إضافية أثناء القص',
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
              },
              child: const Text('إدخال للمخزون', style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }

  // نافذة خطأ في القص: اختيار المقطع التالف وسحب بارة جديدة
  Future<void> _showCuttingErrorDialog() async {
    final newRemnantLenCtrl = TextEditingController(text: '1500');
    final rackCtrl = TextEditingController();
    final noteCtrl = TextEditingController(text: 'خطأ قياس أثناء القص');
    Map<String, dynamic>? selectedSec = _orderSections.isNotEmpty ? _orderSections.first : null;
    int? selectedLoc = _locations.isNotEmpty ? (_locations.first['id'] as num).toInt() : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              const Text('تسجيل خطأ في القص وسحب بارة', style: TextStyle(fontFamily: 'Cairo', fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Text(
                    '⚠️ سيتم سحب بارة إضافية كاملة من المخزون لتعويض القطاع التالف، وتسجيل الفضلة المتبقية منها.',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.brown),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('أين وقع الخطأ وما هو المقطع التالف؟', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                if (_orderSections.isNotEmpty)
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: selectedSec,
                    decoration: const InputDecoration(labelText: 'اختر المقطع التالف', border: OutlineInputBorder()),
                    items: _orderSections.map((s) => DropdownMenuItem(
                      value: s,
                      child: Text('${s['name']} (${s['code'] ?? ''})', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    )).toList(),
                    onChanged: (val) => setDlgState(() => selectedSec = val),
                  )
                else
                  const Text('لا توجد مقاطع مرتبطة مباشرة بالطلبية.', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.red)),
                const SizedBox(height: 12),
                TextField(
                  controller: newRemnantLenCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'طول الفضلة الناتجة عن البارة الجديدة (مم)',
                    hintText: 'مثلاً: 2500',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: rackCtrl,
                  decoration: const InputDecoration(labelText: 'مكان رف الفضلة الجديدة (Rack)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'سبب الخطأ أو الملاحظة', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white),
              onPressed: () async {
                if (selectedSec == null || selectedLoc == null) return;
                final len = double.tryParse(newRemnantLenCtrl.text.trim()) ?? 0.0;
                await widget.db.registerCuttingErrorExtraBar(
                  orderId: widget.orderId,
                  sectionId: (selectedSec!['id'] as num).toInt(),
                  locationId: selectedLoc!,
                  seriesId: (selectedSec!['series_id'] as num?)?.toInt(),
                  newRemnantLengthMm: len,
                  rackCode: rackCtrl.text.trim(),
                  note: noteCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم تسجيل سحب بارة إضافية وحفظ فضلتها بنجاح ⚠️'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.check),
              label: const Text('سحب وتأكيد الفضلة', style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 650,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.inventory_2_outlined, color: Colors.green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مراجعة وتأكيد الفضلات — طلبية #${widget.orderCode}',
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'عنصر: ${widget.windowType} • عدّل الأطوال أو أكّدها لدخول المخزون',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 24),

            // Top Toolbar: زر إضافة فضلة + زر خطأ في القص
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showAddExtraRemnantDialog,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('➕ إضافة فضلة', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                      side: BorderSide(color: Colors.blue.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showCuttingErrorDialog,
                    icon: const Icon(Icons.warning_amber_rounded, size: 18),
                    label: const Text('⚠️ خطأ في القص (سحب بارة)', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Remnants List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _remnants.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              const Text(
                                'لا توجد فضلات متوقعة مسجلة لهذه الطلبية',
                                style: TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _showAddExtraRemnantDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('إضافة فضلة يدوياً الآن', style: TextStyle(fontFamily: 'Cairo')),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _remnants.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final r = _remnants[index];
                            final id = (r['id'] as num).toInt();
                            final isConfirmed = _confirmedIds.contains(id) || r['status'] == 'available';
                            final isScrapped = _scrappedIds.contains(id) || r['status'] == 'scrapped';

                            final itemName = r['item_name'] ?? r['item_code'] ?? 'قطاع';
                            final seriesName = r['series_name'] ?? '';
                            final colorName = r['color_name'] ?? '';

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isConfirmed
                                    ? Colors.green.shade50.withValues(alpha: isDark ? 0.2 : 0.6)
                                    : (isScrapped
                                        ? Colors.red.shade50.withValues(alpha: isDark ? 0.2 : 0.6)
                                        : (isDark ? const Color(0xFF1E293B) : Colors.grey.shade50)),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isConfirmed
                                      ? Colors.green.shade300
                                      : (isScrapped ? Colors.red.shade300 : Colors.grey.shade300),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$itemName $seriesName',
                                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (colorName.isNotEmpty)
                                          Text(
                                            'اللون: $colorName',
                                            style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey.shade600),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // حقل الطول (قابل للتعديل المباشر)
                                  SizedBox(
                                    width: 100,
                                    child: TextField(
                                      controller: _lengthControllers[id],
                                      keyboardType: TextInputType.number,
                                      enabled: !isConfirmed && !isScrapped,
                                      decoration: InputDecoration(
                                        labelText: 'المقاس (مم)',
                                        labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),

                                  // حقل الرف
                                  SizedBox(
                                    width: 80,
                                    child: TextField(
                                      controller: _rackControllers[id],
                                      enabled: !isConfirmed && !isScrapped,
                                      decoration: InputDecoration(
                                        labelText: 'الرف',
                                        labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // أزرار التأكيد والهالك
                                  if (isConfirmed)
                                    const Chip(
                                      avatar: Icon(Icons.check, size: 16, color: Colors.green),
                                      label: Text('في المخزون', style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.green)),
                                      backgroundColor: Colors.transparent,
                                    )
                                  else if (isScrapped)
                                    const Chip(
                                      avatar: Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                      label: Text('هالك', style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.red)),
                                      backgroundColor: Colors.transparent,
                                    )
                                  else ...[
                                    IconButton(
                                      icon: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                                      tooltip: 'تأكيد وإدخال للمخزون',
                                      onPressed: () => _confirmItem(r),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 26),
                                      tooltip: 'تحويل لهالك (Scrap)',
                                      onPressed: () => _scrapItem(r),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 12),

            // Footer
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق والمتابعة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
