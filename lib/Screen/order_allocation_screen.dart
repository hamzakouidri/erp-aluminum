import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../widgets/lazy_window_image.dart';
import '../services/cloud_sync_service.dart';

class OrderAllocationScreen extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final SqlDatabase db;

  const OrderAllocationScreen({
    super.key,
    required this.orderData,
    required this.db,
  });

  @override
  State<OrderAllocationScreen> createState() => _OrderAllocationScreenState();
}

class _OrderAllocationScreenState extends State<OrderAllocationScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _detailsList = [];
  List<Map<String, dynamic>> _workers = [];
  Map<int, List<Map<String, dynamic>>> _allocations = {}; // detailId -> list of allocations

  String _tr(String ar, String fr, String en, AppLanguage lang) {
    if (lang == AppLanguage.french) return fr;
    if (lang == AppLanguage.english) return en;
    return ar;
  }

  /// تحويل الرقم إلى الصيغة الدولية E.164 (بدون +)
  /// يدعم: الجزائر (0 → 213), المغرب (0 → 212), تونس (0 → 216),
  ///       فرنسا (0 → 33), مصر (0 → 20), السعودية (05→ 966)
  String _toInternational(String raw) {
    // إزالة كل شيء ما عدا الأرقام
    String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return '';

    // إذا بدأ بـ 00 (بديل +) أزل الـ 00
    if (digits.startsWith('00')) {
      return digits.substring(2);
    }

    // إذا بدأ بـ + (كان موجوداً قبل إزالة غير الأرقام) — لن يحدث هنا
    // إذا كان فعلاً رقم دولي بالفعل (أطول من 10 أرقام ولا يبدأ بـ 0)
    if (!digits.startsWith('0') && digits.length >= 11) {
      return digits; // رقم دولي بالفعل
    }

    // كشف كود الدولة من أول رقمين/ثلاثة
    // الجزائر: 05x, 06x, 07x → 213
    if (digits.startsWith('05') || digits.startsWith('06') || digits.startsWith('07')) {
      if (digits.length == 10) return '213${digits.substring(1)}';
    }
    // المغرب: 06x, 07x → 212
    // (نفس البادئة، نُفضّل الجزائر — يمكن تغيير الأولوية)
    
    // تونس: 2x, 5x, 9x بعد الصفر → 216
    if (digits.startsWith('0') && digits.length == 8) {
      return '216$digits'; // تونس بدون إزالة الصفر
    }

    // فرنسا: 06, 07 → 33
    if ((digits.startsWith('06') || digits.startsWith('07')) && digits.length == 10) {
      return '33${digits.substring(1)}';
    }

    // الحالة الافتراضية: أزل الصفر الأول وأضف 213 (الجزائر)
    if (digits.startsWith('0') && digits.length >= 9) {
      return '213${digits.substring(1)}';
    }

    // إذا لم يبدأ بصفر وطوله معقول → أضف 213
    if (digits.length >= 8) {
      return '213$digits';
    }

    return digits;
  }

  Future<void> _launchWhatsApp({String? phone, required String text}) async {
    // intlPhone = أرقام فقط بالصيغة الدولية مثل 213555123456
    String intlPhone = '';
    if (phone != null && phone.trim().isNotEmpty) {
      intlPhone = _toInternational(phone.trim());
    }

    final encodedText = Uri.encodeComponent(text);

    // whatsapp:// يحتاج + قبل الرقم الدولي
    // wa.me يحتاج الرقم بدون +
    final whatsappAppUrl = Uri.parse(intlPhone.isNotEmpty
        ? 'whatsapp://send?phone=%2B$intlPhone&text=$encodedText'
        : 'whatsapp://send?text=$encodedText');

    final whatsappWebUrl = Uri.parse(intlPhone.isNotEmpty
        ? 'https://wa.me/$intlPhone?text=$encodedText'
        : 'https://wa.me/?text=$encodedText');

    try {
      final launched = await launchUrl(whatsappAppUrl, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(whatsappWebUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(whatsappWebUrl, mode: LaunchMode.externalApplication);
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                Provider.of<AppSettingsProvider>(context, listen: false).language == AppLanguage.arabic
                    ? 'تعذر فتح تطبيق WhatsApp'
                    : 'Impossible d\'ouvrir WhatsApp',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }



  String _formatItemForSharing(Map<String, dynamic> item, AppLanguage lang, {String? workerName}) {
    final windowType = item['window_type']?.toString() ?? 'Window';
    final largeur = item['largeur'] as int;
    final hauteur = item['hauteur'] as int;
    final qty = item['quantity'] as int;
    final color = item['color']?.toString() ?? '';
    final glass = item['glass']?.toString() ?? '';
    final game = item['game']?.toString() ?? '';
    final volet = item['volet']?.toString() ?? '';
    final description = item['description']?.toString() ?? '';
    final accessories = item['accessories']?.toString() ?? '';

    final buffer = StringBuffer();
    buffer.writeln('📄 *وصل تسليم جزئي بدون سعر / Bon de Livraison Partiel (Sans Prix)* 📄');
    buffer.writeln('-----------------------------------');
    buffer.writeln('*الطلبية / Commande:* #${widget.orderData['id']}');
    buffer.writeln('*الزبون / Client:* ${widget.orderData['firstname']} ${widget.orderData['lastname']}');
    if (workerName != null) {
      buffer.writeln('*العامل المسؤول / Ouvrier:* $workerName');
    }
    buffer.writeln('-----------------------------------');
    buffer.writeln('*المنتج / Produit:* ${Localization.translate(windowType, lang)}');
    buffer.writeln('*الأبعاد / Dimensions:* $largeur x $hauteur مم (mm)');
    buffer.writeln('*الكمية / Quantité:* $qty');
    
    if (game.isNotEmpty) buffer.writeln('*نوع البروفيل / Gamme:* ${Localization.translate(game, lang)}');
    if (color.isNotEmpty) buffer.writeln('*اللون / Couleur:* ${Localization.translate(color, lang)}');
    if (glass.isNotEmpty) buffer.writeln('*الزجاج / Vitrage:* ${Localization.translate(glass, lang)}');
    if (volet.isNotEmpty && volet != 'No') {
      buffer.writeln('*الستار / Volet:* ${Localization.translate(volet, lang)}');
    }

    try {
      final jsonRaw = item['partitions_json'];
      if (jsonRaw != null) {
        Map<String, dynamic> map = {};
        if (jsonRaw is Map<String, dynamic>) {
          map = jsonRaw;
        } else {
          final str = jsonRaw.toString().trim();
          if (str.length >= 5) {
            map = jsonDecode(str) as Map<String, dynamic>;
          }
        }
        if (map.containsKey('poignee')) {
          buffer.writeln('*نوع المقبض / Poignée:* ${map['poignee']}');
        }
        if (map.containsKey('couvre_joint')) {
          buffer.writeln('*الكوفريج / Couvre Joint:* ${map['couvre_joint']}');
        }
      }
    } catch (_) {}

    if (accessories.isNotEmpty) {
      buffer.writeln('-----------------------------------');
      buffer.writeln('*الملحقات / Accessoires:*');
      buffer.writeln(accessories);
    }
    
    if (description.isNotEmpty) {
      buffer.writeln('-----------------------------------');
      buffer.writeln('*التفاصيل / Détails:*');
      // Strip any price tags to make it a true "sans prix" delivery note
      final cleanDesc = description.replaceAll(RegExp(r'\d+(\.\d+)?\s*دج'), '');
      buffer.writeln(cleanDesc);
    }
    
    buffer.writeln('-----------------------------------');
    return buffer.toString();
  }




  void _shareAllAllocations() async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final buffer = StringBuffer();
    buffer.writeln('📋 *جدول توزيع عناصر الطلبية #${widget.orderData['id']}* 📋');
    buffer.writeln('*العميل / Client:* ${widget.orderData['firstname']} ${widget.orderData['lastname']}');
    buffer.writeln('-----------------------------------');
    
    for (var item in _detailsList) {
      final detailId = item['id'] as int;
      final itemUnitIndex = item['unit_index'];
      final rawList = _allocations[detailId] ?? [];
      final list = rawList.where((a) {
        if (itemUnitIndex != null) {
          return a['unit_index'] == itemUnitIndex;
        }
        return true;
      }).toList();
      
      buffer.writeln('*عنصر / Produit:* ${Localization.translate(item['window_type'] ?? 'Window', lang)} (${item['largeur']}x${item['hauteur']})');
      buffer.writeln('*الكمية الإجمالية / Qté Totale:* ${item['quantity']}');
      
      if (list.isEmpty) {
        buffer.writeln('*التوزيع / Affectation:* ${lang == AppLanguage.arabic ? "غير معين" : "Non affecté"}');
      } else {
        for (var a in list) {
          final workerName = _workers.firstWhere(
            (w) => w['uid'].toString() == a['worker_uid'],
            orElse: () => {'name': 'مجهول'},
          )['name'];
          buffer.writeln('  - $workerName: ${a['quantity']} ${lang == AppLanguage.arabic ? "قطع" : "pcs"}');
        }
      }
      buffer.writeln('-----------------------------------');
    }
    
    _launchWhatsApp(text: buffer.toString());
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final orderId = widget.orderData['id'] as int;
      final rawDetails = await widget.db.readCommandeDetails(orderId);
      final rawWorkers = await widget.db.readEmployees();

      final List<Map<String, dynamic>> expandedDetails = [];
      final Map<int, List<Map<String, dynamic>>> allocs = {};

      for (var row in rawDetails) {
        final detailId = row['id'] as int;
        final list = await widget.db.readWorkerAllocations(detailId);
        allocs[detailId] = list;

        final instancesRaw = row['instances_json'];
        final jsonRaw = row['confirmed_mesures_json'];
        final qty = (row['quantity'] ?? row['nbr'] ?? 1) as int;

        List<dynamic> parsedInstances = [];
        if (instancesRaw != null && instancesRaw.toString().trim().isNotEmpty) {
          try {
            parsedInstances = jsonDecode(instancesRaw.toString()) as List<dynamic>;
          } catch (_) {}
        }

        if (parsedInstances.isNotEmpty) {
          // فحص هل جميع النوافذ بنفس القياسات أم اختلفت
          bool isUnifiedMeasurement = true;
          int? firstW;
          int? firstH;

          for (var inst in parsedInstances) {
            final w = (inst['width'] ?? inst['largeur'] ?? row['largeur'] as num?)?.toInt();
            final h = (inst['height'] ?? inst['hauteur'] ?? row['hauteur'] as num?)?.toInt();
            if (firstW == null) {
              firstW = w;
              firstH = h;
            } else if (w != firstW || h != firstH) {
              isUnifiedMeasurement = false;
              break;
            }
          }

          if (isUnifiedMeasurement) {
            // 🟢 النوافذ بنفس القياسات تماماً: تعطيها مجمعة بالكمية دون تقسيم
            final itemCopy = Map<String, dynamic>.from(row);
            if (firstW != null && firstW > 0) itemCopy['largeur'] = firstW;
            if (firstH != null && firstH > 0) itemCopy['hauteur'] = firstH;
            itemCopy['quantity'] = qty;
            itemCopy['orig_quantity'] = qty;
            itemCopy['is_unified_measurement'] = true;
            expandedDetails.add(itemCopy);
          } else {
            // 🟡 القياسات تغيرت واختلفت داخل صفحة تأكيد القياسات: عرض كل مجموعة قياسات مؤكدة أو كل نافذة على حدة
            int indexCounter = 1;
            for (var inst in parsedInstances) {
              final w = inst['width'] ?? inst['largeur'] ?? row['largeur'];
              final h = inst['height'] ?? inst['hauteur'] ?? row['hauteur'];
              final q = (inst['qty'] ?? 1) as int;
              final pos = inst['position']?.toString() ?? '';

              if (q > 1 && pos.isEmpty) {
                final itemCopy = Map<String, dynamic>.from(row);
                itemCopy['largeur'] = w;
                itemCopy['hauteur'] = h;
                itemCopy['position'] = pos;
                itemCopy['quantity'] = q;
                itemCopy['orig_quantity'] = qty;
                itemCopy['is_confirmed_measurement'] = true;
                expandedDetails.add(itemCopy);
                indexCounter += q;
              } else {
                for (int k = 0; k < q; k++) {
                  final itemCopy = Map<String, dynamic>.from(row);
                  itemCopy['largeur'] = w;
                  itemCopy['hauteur'] = h;
                  itemCopy['position'] = pos;
                  itemCopy['quantity'] = 1;
                  itemCopy['orig_quantity'] = qty;
                  itemCopy['unit_index'] = indexCounter;
                  itemCopy['is_confirmed_measurement'] = true;
                  expandedDetails.add(itemCopy);
                  indexCounter++;
                }
              }
            }
          }
          continue;
        }

        if (jsonRaw != null && jsonRaw.toString().trim().isNotEmpty && qty > 1) {
          try {
            final List parsed = jsonDecode(jsonRaw.toString());
            if (parsed.isNotEmpty) {
              bool isUnified = true;
              final firstW = parsed.first['largeur'] ?? row['largeur'];
              final firstH = parsed.first['hauteur'] ?? row['hauteur'];
              for (var p in parsed) {
                if ((p['largeur'] ?? row['largeur']) != firstW || (p['hauteur'] ?? row['hauteur']) != firstH) {
                  isUnified = false;
                  break;
                }
              }

              if (isUnified) {
                final itemCopy = Map<String, dynamic>.from(row);
                itemCopy['largeur'] = firstW;
                itemCopy['hauteur'] = firstH;
                itemCopy['quantity'] = qty;
                itemCopy['orig_quantity'] = qty;
                itemCopy['is_unified_measurement'] = true;
                expandedDetails.add(itemCopy);
              } else {
                for (int i = 0; i < qty; i++) {
                  final itemCopy = Map<String, dynamic>.from(row);
                  if (i < parsed.length) {
                    itemCopy['hauteur'] = parsed[i]['hauteur'] ?? row['hauteur'];
                    itemCopy['largeur'] = parsed[i]['largeur'] ?? row['largeur'];
                    itemCopy['position'] = parsed[i]['position'] ?? '';
                    itemCopy['unit_index'] = i + 1;
                  }
                  itemCopy['quantity'] = 1;
                  itemCopy['orig_quantity'] = qty;
                  itemCopy['is_confirmed_measurement'] = true;
                  expandedDetails.add(itemCopy);
                }
              }
              continue;
            }
          } catch (_) {}
        }
        expandedDetails.add(Map<String, dynamic>.from(row));
      }

      setState(() {
        _detailsList = expandedDetails;
        _workers = List<Map<String, dynamic>>.from(rawWorkers);
        _allocations = allocs;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading allocation data: $e');
      setState(() => _isLoading = false);
    }
  }

  /// تحديث بيانات الإسنادات فقط بدون إعادة بناء كامل للصفحة (لا يعود للأعلى)
  Future<void> _refreshAllocationsOnly() async {
    try {
      final orderId = widget.orderData['id'] as int;
      final rawDetails = await widget.db.readCommandeDetails(orderId);
      final Map<int, List<Map<String, dynamic>>> allocs = {};
      for (var row in rawDetails) {
        final detailId = row['id'] as int;
        final list = await widget.db.readWorkerAllocations(detailId);
        allocs[detailId] = list;
      }
      if (mounted) {
        setState(() {
          _allocations = allocs;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing allocations: $e');
    }
  }

  void _showConfirmMeasurementsDialog(Map<String, dynamic> item) {
    final qty = (item['orig_quantity'] ?? item['quantity'] ?? 1) as int;
    final origH = (item['hauteur'] ?? 0) as int;
    final origW = (item['largeur'] ?? 0) as int;
    final detailId = item['id'] as int;

    List<Map<String, dynamic>> initialMeasures = [];
    try {
      final jsonRaw = item['confirmed_mesures_json'];
      if (jsonRaw != null && jsonRaw.toString().trim().isNotEmpty) {
        final List parsed = jsonDecode(jsonRaw.toString());
        initialMeasures = parsed.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}

    final List<TextEditingController> heightCtrls = [];
    final List<TextEditingController> widthCtrls = [];

    for (int i = 0; i < qty; i++) {
      int h = origH;
      int w = origW;
      if (i < initialMeasures.length) {
        h = (initialMeasures[i]['hauteur'] ?? origH) as int;
        w = (initialMeasures[i]['largeur'] ?? origW) as int;
      }
      heightCtrls.add(TextEditingController(text: h.toString()));
      widthCtrls.add(TextEditingController(text: w.toString()));
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.straighten_rounded, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'تأكيد قياسات الموقع ($qty نوافذ/عناصر)',
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(qty, (index) {
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1E293B)
                        : Colors.blue.shade50,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'النافذة رقم #${index + 1}',
                            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: heightCtrls[index],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'الارتفاع (مم)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: widthCtrls[index],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'العرض (مم)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final List<Map<String, dynamic>> resultList = [];
                for (int i = 0; i < qty; i++) {
                  final h = int.tryParse(heightCtrls[i].text.trim()) ?? origH;
                  final w = int.tryParse(widthCtrls[i].text.trim()) ?? origW;
                  resultList.add({'index': i + 1, 'hauteur': h, 'largeur': w});
                }
                final jsonString = jsonEncode(resultList);
                final db = await widget.db.db;
                if (db != null) {
                  await db.update(
                    'Commandes_details',
                    {'confirmed_mesures_json': jsonString},
                    where: 'id = ?',
                    whereArgs: [detailId],
                  );
                }
                if (mounted) {
                  Navigator.pop(context);
                  _loadData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم حفظ قياسات الموقع المؤكدة وفصل النوافذ للإسناد ✅', style: TextStyle(fontFamily: 'Cairo')),
                      backgroundColor: Colors.teal,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('حفظ القياسات', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addWorkerAllocation(
    int detailId,
    String workerUid,
    int quantity,
    double price, {
    int? unitIndex,
    String? unitPosition,
  }) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;

    // إظهار مؤشر تقدم فوري
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  lang == AppLanguage.arabic ? 'جاري إسناد العمل…' : 'Affectation en cours…',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await widget.db.insertWorkerAllocation(
        detailId,
        workerUid,
        quantity,
        price,
        unitIndex: unitIndex,
        unitPosition: unitPosition,
      );
      CloudSyncService().notifyChange(); // ⚡ رفع في الخلفية
      await _refreshAllocationsOnly();  // لا يعود للأعلى
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // أغلق التقدم
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lang == AppLanguage.arabic ? 'تم إسناد العمل بنجاح ✅' : 'Affectation réussie ✅',
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _removeWorkerAllocation(int allocationId) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;

    // إظهار مؤشر تقدم فوري
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  lang == AppLanguage.arabic ? 'جاري إلغاء الإسناد…' : 'Annulation en cours…',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await widget.db.deleteWorkerAllocation(allocationId);
      await _refreshAllocationsOnly(); // لا يعود للأعلى
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // أغلق التقدم
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lang == AppLanguage.arabic ? 'تم إلغاء الإسناد ✅' : 'Affectation annulée ✅',
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _editWorkerAllocation(int allocationId, String workerUid, int quantity, double price) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;

    // إظهار مؤشر تقدم فوري
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  lang == AppLanguage.arabic ? 'جاري تعديل الإسناد…' : 'Modification en cours…',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await widget.db.updateWorkerAllocationDetails(allocationId, workerUid, quantity, price);
      CloudSyncService().notifyChange(); // ⚡ رفع في الخلفية
      await _refreshAllocationsOnly();  // لا يعود للأعلى
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // أغلق التقدم
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lang == AppLanguage.arabic ? 'تم تعديل الإسناد بنجاح ✅' : 'Modification réussie ✅',
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showEditAssignDialog(Map<String, dynamic> alloc, Map<String, dynamic> item) {
    final isManufactured = alloc['is_manufactured'] == 1;
    final detailId = item['id'] as int;
    final itemUnitIndex = item['unit_index'];
    final qty = item['quantity'] as int;
    final rawAllocs = _allocations[detailId] ?? [];
    final allocs = rawAllocs.where((a) {
      final aUnitIndex = a['unit_index'];
      if (itemUnitIndex != null) {
        return aUnitIndex == itemUnitIndex;
      } else {
        return true;
      }
    }).toList();
    final int allocatedQty = allocs.fold(0, (sum, a) => sum + (a['quantity'] as int));
    final int remainingQty = qty - allocatedQty;
    final int currentAllocQty = alloc['quantity'] as int;
    final int maxAllowedQty = remainingQty + currentAllocQty;

    String? selectedWorkerUid = alloc['worker_uid']?.toString();
    final qtyCtrl = TextEditingController(text: currentAllocQty.toString());
    final priceCtrl = TextEditingController(
      text: alloc['worker_price'] != null && alloc['worker_price'] != 0.0 ? alloc['worker_price'].toString() : '',
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            isManufactured ? 'تعديل سعر التصنيع (مقفول للعامل)' : 'تعديل إسناد العمل',
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isManufactured) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withOpacity(0.4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.lock_rounded, color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '⚠️ تم تصنيع هذه النافذة بالفعل! تَم قفل تعيين العامل والكمية، يمكنك فقط تعديل سعر/أجرة التصنيع.',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  DropdownButtonFormField<String>(
                    value: selectedWorkerUid,
                    decoration: InputDecoration(
                      labelText: isManufactured ? 'العامل الصانع (مقفول)' : 'اختر العامل',
                      border: const OutlineInputBorder(),
                    ),
                    items: _workers.map((w) {
                      return DropdownMenuItem<String>(
                        value: w['uid'].toString(),
                        child: Text(
                          w['name'] ?? '',
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      );
                    }).toList(),
                    onChanged: isManufactured ? null : (val) => setStateDialog(() => selectedWorkerUid = val),
                    validator: (val) => val == null ? 'يرجى اختيار عامل' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: qtyCtrl,
                    enabled: !isManufactured,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: isManufactured ? 'الكمية المصنوعة (مقفول)' : 'الكمية المسندة (الأقصى $maxAllowedQty)',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'يرجى إدخال الكمية';
                      final q = int.tryParse(val.trim());
                      if (q == null || q <= 0) return 'الرجاء إدخال رقم صحيح أكبر من 0';
                      if (q > maxAllowedQty) return 'لا يمكن تجاوز الكمية القصوى المتاحة ($maxAllowedQty)';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'سعر تصنيع القطعة الواحدة للعامل (د.ج) - إجباري',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'يرجى إدخال سعر/أجرة التصنيع لا محالة';
                      final p = double.tryParse(val.trim());
                      if (p == null || p <= 0) return 'الرجاء إدخال مبلغ صحيح أكبر من 0';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate() && selectedWorkerUid != null) {
                  final q = int.parse(qtyCtrl.text.trim());
                  final p = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                  Navigator.pop(context);
                  _editWorkerAllocation(alloc['id'] as int, selectedWorkerUid!, q, p);
                }
              },
              child: const Text('حفظ التعديل', style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }

  void _showAssignDialog(Map<String, dynamic> item, int remainingQty) {
    String? selectedWorkerUid = _workers.isNotEmpty ? _workers.first['uid'].toString() : null;
    final qtyCtrl = TextEditingController(text: remainingQty.toString());
    final priceCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text(
            'إسناد عمل جديد لعامل',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedWorkerUid,
                    decoration: const InputDecoration(
                      labelText: 'اختر العامل',
                      border: OutlineInputBorder(),
                    ),
                    items: _workers.map((w) {
                      return DropdownMenuItem<String>(
                        value: w['uid'].toString(),
                        child: Text(
                          w['name'] ?? '',
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) => setStateDialog(() => selectedWorkerUid = val),
                    validator: (val) => val == null ? 'يرجى اختيار عامل' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'الكمية المسندة (الأقصى $remainingQty)',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'يرجى إدخال الكمية';
                      final q = int.tryParse(val.trim());
                      if (q == null || q <= 0) return 'الرجاء إدخال رقم صحيح أكبر من 0';
                      if (q > remainingQty) return 'لا يمكن تجاوز الكمية المتبقية ($remainingQty)';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'سعر تصنيع القطعة الواحدة للعامل (د.ج) - إجباري',
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'يرجى إدخال سعر/أجرة التصنيع لا محالة';
                      final p = double.tryParse(val.trim());
                      if (p == null || p <= 0) return 'الرجاء إدخال مبلغ صحيح أكبر من 0';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate() && selectedWorkerUid != null) {
                  final q = int.parse(qtyCtrl.text.trim());
                  final p = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                  Navigator.pop(context);
                  _addWorkerAllocation(
                    item['id'] as int,
                    selectedWorkerUid!,
                    q,
                    p,
                    unitIndex: item['unit_index'] as int?,
                    unitPosition: item['position']?.toString(),
                  );
                }
              },
              child: const Text('إسناد', style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          lang == AppLanguage.arabic
              ? 'توزيع عناصر الطلبية على العمال'
              : lang == AppLanguage.french
                  ? 'Distribuer la commande aux ouvriers'
                  : 'Distribute order to workers',
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blue,
        actions: [
          if (!_isLoading && _detailsList.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.share_rounded, color: Colors.white),
              tooltip: lang == AppLanguage.arabic ? 'مشاركة كل التوزيع' : 'Partager tout le tableau',
              onPressed: _shareAllAllocations,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _detailsList.isEmpty
              ? Center(
                  child: Text(
                    lang == AppLanguage.arabic
                        ? 'لا توجد عناصر في هذه الطلبية'
                        : lang == AppLanguage.french
                            ? 'Aucun élément dans cette commande'
                            : 'No items in this order',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 16),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Order info header
                      Card(
                        elevation: 1,
                        color: Theme.of(context).cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Theme.of(context).brightness == Brightness.dark ? Theme.of(context).appBarTheme.backgroundColor : Colors.blueAccent,
                                foregroundColor: Theme.of(context).cardColor,
                                child: Icon(Icons.assignment_rounded),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${lang == AppLanguage.arabic ? "الطلبية" : "Commande"} #${widget.orderData['id']}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${lang == AppLanguage.arabic ? "الزبون" : "Client"}: ${widget.orderData['firstname']} ${widget.orderData['lastname']}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _detailsList.length,
                          itemBuilder: (context, index) {
                            final item = _detailsList[index];
                            final detailId = item['id'] as int;
                            final windowType = item['window_type']?.toString() ?? 'Window';
                            final largeur = item['largeur'] as int;
                            final hauteur = item['hauteur'] as int;
                            final qty = item['quantity'] as int;
                            final color = item['color']?.toString() ?? '';
                            final glass = item['glass']?.toString() ?? '';
                            final position = item['position']?.toString() ?? '';
                            final unitIndex = item['unit_index'];

                            final isConfirmed = unitIndex != null || position.isNotEmpty;
                            final dimText = isConfirmed
                                ? '📐 ${lang == AppLanguage.arabic ? "القياس المؤكد" : "Mesure Validée"}: $largeur x $hauteur ${position.isNotEmpty ? "($position)" : ""} | ${lang == AppLanguage.arabic ? "الكمية" : "Qté"}: $qty'
                                : '${lang == AppLanguage.arabic ? "الأبعاد" : "Dimensions"}: $largeur x $hauteur | ${lang == AppLanguage.arabic ? "الكمية" : "Qté"}: $qty';

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              elevation: 2,
                              color: Theme.of(context).cardColor,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            windowType.toLowerCase().contains('porte') || windowType.toLowerCase().contains('door')
                                                ? Icons.door_front_door_rounded
                                                : Icons.window_rounded,
                                            color: Colors.blue.shade700,
                                            size: 26,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      Localization.translate(windowType, lang),
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16,
                                                        fontFamily: 'Cairo',
                                                      ),
                                                    ),
                                                  ),
                                                  if (unitIndex != null)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.teal.shade700,
                                                        borderRadius: BorderRadius.circular(10),
                                                      ),
                                                      child: Text(
                                                        '${lang == AppLanguage.arabic ? "قطعة" : "Pièce"} #$unitIndex',
                                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                dimText,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: isConfirmed ? FontWeight.bold : FontWeight.normal,
                                                  color: isConfirmed ? Colors.teal.shade800 : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                                  fontFamily: 'Cairo',
                                                ),
                                              ),
                                              if (color.isNotEmpty || glass.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${Localization.translate(color, lang)} | ${Localization.translate(glass, lang)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                                    fontFamily: 'Cairo',
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12.0),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          color: Theme.of(context).brightness == Brightness.dark
                                              ? const Color(0xFF0F172A)
                                              : Colors.grey.shade100,
                                          padding: const EdgeInsets.all(8),
                                          child: LazyWindowImage(
                                            db: widget.db,
                                            detailId: item['id'] as int,
                                            initialImagePath: item['drawing_image_path']?.toString() ?? '',
                                            partitionsJson: item['partitions_json'],
                                            drawingImageBase64: item['drawing_image_base64']?.toString(),
                                            height: 140,
                                            width: double.infinity,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 12.0),
                                      child: Divider(height: 1),
                                    ),
                                    // ── قائمة التوزيعات الحالية لهذا العنصر ──
                                    Builder(
                                      builder: (context) {
                                        final itemUnitIndex = item['unit_index'];
                                        final rawAllocs = _allocations[detailId] ?? [];
                                        final allocs = rawAllocs.where((a) {
                                          if (itemUnitIndex != null) {
                                            return a['unit_index'] == itemUnitIndex;
                                          }
                                          return true;
                                        }).toList();
                                        final int allocatedQty = allocs.fold(0, (sum, a) => sum + (a['quantity'] as int));
                                        final int remainingQty = qty - allocatedQty;

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (allocs.isNotEmpty) ...[
                                              Text(
                                                lang == AppLanguage.arabic ? 'العمال المعينون:' : 'Ouvriers affectés :',
                                                style: const TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              ...allocs.map((alloc) {
                                                final workerName = _workers.firstWhere(
                                                  (w) => w['uid'].toString() == alloc['worker_uid'],
                                                  orElse: () => {'name': 'مجهول'},
                                                )['name']?.toString() ?? 'مجهول';
                                                final workerPhone = _workers.firstWhere(
                                                  (w) => w['uid'].toString() == alloc['worker_uid'],
                                                  orElse: () => {},
                                                )['phone']?.toString();
                                                final workerPrice = (alloc['worker_price'] as num?)?.toDouble() ?? 0.0;
                                                final totalWorkerPrice = workerPrice * (alloc['quantity'] as int);
                                                final isManufactured = alloc['is_manufactured'] == 1;

                                                return Container(
                                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[850] : Colors.grey[100],
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.person, size: 16, color: Colors.blueGrey),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              '$workerName : ${alloc['quantity']} ${lang == AppLanguage.arabic ? "قطع" : "pcs"}',
                                                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                                                            ),
                                                            const SizedBox(height: 2),
                                                            Text(
                                                              '💵 ${_tr("أجرة التصنيع:", "Prix fab.:", "Mfg price:", lang)} ${workerPrice.toStringAsFixed(0)} د.ج / ${_tr("قطعة", "pc", "pc", lang)} (${_tr("الإجمالي:", "Total:", "Total:", lang)} ${totalWorkerPrice.toStringAsFixed(0)} د.ج)',
                                                              style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.teal.shade700, fontWeight: FontWeight.bold),
                                                            ),
                                                            const SizedBox(height: 4),
                                                            Wrap(
                                                              spacing: 6,
                                                              runSpacing: 4,
                                                              children: [
                                                                Container(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                  decoration: BoxDecoration(
                                                                    color: isManufactured ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
                                                                    borderRadius: BorderRadius.circular(6),
                                                                  ),
                                                                  child: Text(
                                                                    isManufactured ? 'تم الصنع ✅' : 'لم يصنع بعد ⏳',
                                                                    style: TextStyle(
                                                                      color: isManufactured ? Colors.green : Colors.orange,
                                                                      fontSize: 10,
                                                                      fontWeight: FontWeight.bold,
                                                                      fontFamily: 'Cairo',
                                                                    ),
                                                                  ),
                                                                ),
                                                                Container(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                  decoration: BoxDecoration(
                                                                    color: alloc['is_glass_installed'] == 1 ? Colors.blue.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
                                                                    borderRadius: BorderRadius.circular(6),
                                                                  ),
                                                                  child: Text(
                                                                    alloc['is_glass_installed'] == 1 ? 'تم تركيب الزجاج 💎' : 'لم يركب الزجاج ⏳',
                                                                    style: TextStyle(
                                                                      color: alloc['is_glass_installed'] == 1 ? Colors.blue : Colors.orange,
                                                                      fontSize: 10,
                                                                      fontWeight: FontWeight.bold,
                                                                      fontFamily: 'Cairo',
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.share, size: 18, color: Colors.green),
                                                        tooltip: 'مشاركة العمل للعامل (WhatsApp)',
                                                        onPressed: () async {
                                                          final text = _formatItemForSharing(
                                                            {...item, 'quantity': alloc['quantity']},
                                                            lang,
                                                            workerName: workerName,
                                                          );
                                                          await _launchWhatsApp(
                                                            phone: workerPhone,
                                                            text: text,
                                                          );
                                                        },
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.orange),
                                                        tooltip: lang == AppLanguage.arabic ? 'تعديل التعيين' : 'Modifier l\'affectation',
                                                        onPressed: () => _showEditAssignDialog(alloc, item),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                                        tooltip: 'إلغاء التعيين',
                                                        onPressed: () => _removeWorkerAllocation(alloc['id'] as int),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ],
                                            const SizedBox(height: 8),
                                            if (remainingQty > 0) ...[
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  OutlinedButton.icon(
                                                    onPressed: () => _showConfirmMeasurementsDialog(item),
                                                    icon: const Icon(Icons.straighten, size: 15, color: Colors.blue),
                                                    label: Text(
                                                      lang == AppLanguage.arabic ? 'قياسات الموقع 📐' : 'Mesures 📐',
                                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.blue),
                                                    ),
                                                    style: OutlinedButton.styleFrom(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      side: const BorderSide(color: Colors.blue),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  ElevatedButton.icon(
                                                    onPressed: () => _showAssignDialog(item, remainingQty),
                                                    icon: const Icon(Icons.add, size: 16),
                                                    label: Text(
                                                      lang == AppLanguage.arabic ? 'إسناد لعامل' : 'Affecter à un ouvrier',
                                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                                                    ),
                                                    style: ElevatedButton.styleFrom(
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ] else ...[
                                              Text(
                                                lang == AppLanguage.arabic ? 'تم توزيع كامل الكمية لهذا العنصر ✅' : 'Quantité totale affectée ✅',
                                                style: const TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 13,
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),

                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
