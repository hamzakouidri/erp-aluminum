import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../widgets/lazy_window_image.dart';

class GlassOrderReceptionScreen extends StatefulWidget {
  final SqlDatabase db;
  final int commandeId;
  final String clientName;

  const GlassOrderReceptionScreen({
    super.key,
    required this.db,
    required this.commandeId,
    required this.clientName,
  });

  @override
  State<GlassOrderReceptionScreen> createState() => _GlassOrderReceptionScreenState();
}

class _GlassOrderReceptionScreenState extends State<GlassOrderReceptionScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _glassItems = [];

  final Map<int, int> _receivedQtyMap = {};
  final Set<int> _editingUnlockedSet = {};

  @override
  void initState() {
    super.initState();
    _loadOrderGlassDetails();
  }

  Future<void> _loadOrderGlassDetails() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final database = await widget.db.db;
      if (database == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final items = await database.query(
        'Commandes_details',
        where: 'id_commandes = ?',
        whereArgs: [widget.commandeId],
        orderBy: 'id ASC',
      );

      _receivedQtyMap.clear();
      for (var item in items) {
        final id = item['id'] as int;
        final totalQty = (item['nbr'] ?? item['quantity'] ?? 1) as int;
        final savedReceived = (item['glass_received_qty'] ?? 0) as int;
        _receivedQtyMap[id] = savedReceived > 0 ? savedReceived : totalQty;
      }

      if (mounted) {
        setState(() {
          _glassItems = List<Map<String, dynamic>>.from(items);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading glass details: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _tr(String ar, String fr, String en, AppLanguage lang) {
    if (lang == AppLanguage.french) return fr;
    if (lang == AppLanguage.english) return en;
    return ar;
  }

  /// 📐 حساب قياسات الزجاج الحقيقية بناءً على نوع النظام (Gamme) أو البيانات المؤكدة
  _RealGlassDimensions _calculateGlassDimensions(Map<String, dynamic> item) {
    final winH = ((item['hauteur'] ?? item['height'] ?? 0) as num).toDouble();
    final winW = ((item['largeur'] ?? item['width'] ?? 0) as num).toDouble();
    final game = (item['game'] ?? '').toString().toLowerCase().trim();
    final windowType = (item['window_type'] ?? '').toString().toLowerCase();

    // 1. فحص وجود قياسات معدلة/مؤكدة مسبقاً في confirmed_mesures_json
    final confirmedJson = item['confirmed_mesures_json']?.toString();
    if (confirmedJson != null && confirmedJson.isNotEmpty && confirmedJson != '{}') {
      try {
        final map = jsonDecode(confirmedJson) as Map<String, dynamic>;
        final gh = (map['glass_height'] as num?)?.toDouble();
        final gw = (map['glass_width'] as num?)?.toDouble();
        if (gh != null && gw != null && gh > 0 && gw > 0) {
          return _RealGlassDimensions(height: gh, width: gw, isCustom: true);
        }
      } catch (_) {}
    }

    // 2. فحص وجود أبعاد الزجاج داخل partitions_json
    final partitionsJson = item['partitions_json']?.toString();
    if (partitionsJson != null && partitionsJson.isNotEmpty && partitionsJson != '[]') {
      try {
        final parsed = jsonDecode(partitionsJson);
        if (parsed is Map<String, dynamic>) {
          final gh = (parsed['glassHeight'] ?? parsed['cellGh'] ?? parsed['glass_height'] as num?)?.toDouble();
          final gw = (parsed['glassWidth'] ?? parsed['cellGw'] ?? parsed['glass_width'] as num?)?.toDouble();
          if (gh != null && gw != null && gh > 0 && gw > 0) {
            return _RealGlassDimensions(height: gh, width: gw, isCustom: false);
          }
        }
      } catch (_) {}
    }

    // 3. الحساب التلقائي حسب خوارزمية النظام (Gamme Deduction Rules)
    double glassH = winH;
    double glassW = winW;

    if (game.contains('c60') || game.contains('coulissant') || windowType.contains('سحاب') || windowType.contains('coulissant')) {
      // نظام سحاب C60 (ظلفة مزدوجة)
      glassH = winH > 152 ? winH - 152 : winH;
      glassW = winW > 86 ? (winW / 2) - 86 : winW;
    } else if (game.contains('eclips') || game.contains('tango') || game.contains('ouvrant') || game.contains('frappe') || windowType.contains('فتح')) {
      // نظام مفصلي (Ouvrant / Frappe)
      glassH = winH > 164 ? winH - 164 : winH;
      glassW = winW > 164 ? winW - 164 : winW;
    } else if (game.contains('fixe') || windowType.contains('ثابت')) {
      // زجاج ثابت (Fixe)
      glassH = winH > 80 ? winH - 80 : winH;
      glassW = winW > 80 ? winW - 80 : winW;
    } else {
      // الخصم الافتراضي العام للألمنيوم
      glassH = winH > 150 ? winH - 150 : winH;
      glassW = winW > 120 ? winW - 120 : winW;
    }

    return _RealGlassDimensions(
      height: double.parse(glassH.toStringAsFixed(1)),
      width: double.parse(glassW.toStringAsFixed(1)),
      isCustom: false,
    );
  }

  /// 🔍 تحليل وتنسيق نوع واسم الزجاج مباشرة بدون الكلمات الزائدة (couleur, nom)
  _GlassInfo _parseGlassInfo(Map<String, dynamic> item, AppLanguage lang) {
    String rawGlass = (item['glass'] ?? '').toString().trim();

    // تنظيف أي كلمات زائدة مثل couleur, nom, اللون
    rawGlass = rawGlass
        .replaceAll(RegExp(r'\b(couleur|color|nom|name|اللون|اسم)\s*[:=]\s*', caseSensitive: false), '')
        .trim();

    final partitionsJson = item['partitions_json']?.toString() ?? '[]';
    final imageBase64 = item['drawing_image_base64']?.toString() ?? '';
    final drawingPath = item['drawing_image_path']?.toString() ?? '';

    // فحص غاز الأرجون
    final bool hasArgon = rawGlass.toLowerCase().contains('argon') ||
        rawGlass.contains('أرجون') ||
        rawGlass.contains('ارغون');

    // كشف الزجاج المزدوج: يحتوي على "+" أو كلمة double
    final isDouble = rawGlass.contains('+') ||
        rawGlass.toLowerCase().contains('double') ||
        rawGlass.contains('مزدوج') ||
        rawGlass.contains('إزدواجي');

    // كشف الديكور / البانو
    final isDecor = rawGlass.toLowerCase().contains('decor') ||
        rawGlass.contains('ديكور') ||
        rawGlass.toLowerCase().contains('panneau') ||
        rawGlass.contains('بانو') ||
        rawGlass.toLowerCase().contains('sablé') ||
        rawGlass.contains('مشجر');

    bool hasPartitions = false;
    try {
      final parsed = jsonDecode(partitionsJson.isEmpty ? '[]' : partitionsJson);
      hasPartitions = parsed is List && parsed.isNotEmpty;
    } catch (_) {}

    // تفكيك أجزاء الزجاج المزدوج: خارجي + انتركل + داخلي
    String outerFace = '';
    String innerFace = '';
    String intercall = '';
    String formattedCleanSpec = '';

    if (isDouble) {
      final parts = rawGlass.split('+');
      if (parts.length >= 3) {
        outerFace = parts[0].trim();
        intercall = parts[1].trim();
        innerFace = parts[2].replaceAll(RegExp(r'\b(argon|أرجون|ارغون)\b', caseSensitive: false), '').trim();
      } else {
        outerFace = rawGlass;
      }

      final extText = outerFace.isNotEmpty ? outerFace : _tr('خارجي', 'Extérieur', 'Outer', lang);
      final intText = intercall.isNotEmpty ? intercall : '12';
      final intrText = innerFace.isNotEmpty ? innerFace : _tr('داخلي', 'Intérieur', 'Inner', lang);

      formattedCleanSpec = '$extText + $intText + $intrText';
      if (hasArgon) {
        formattedCleanSpec += ' (${_tr("مع غاز أرجون", "Avec Gaz Argon", "With Argon Gas", lang)})';
      }
    } else {
      formattedCleanSpec = rawGlass.isNotEmpty ? rawGlass : _tr('زجاج مفرد', 'Vitrage Simple', 'Single Glass', lang);
    }

    String typeBadgeLabel;
    if (isDouble) {
      typeBadgeLabel = _tr('زجاج مزدوج', 'Vitrage Double', 'Double Glass', lang);
    } else if (isDecor || hasPartitions) {
      typeBadgeLabel = _tr('زجاج بديكور', 'Vitrage Décoré', 'Decorative Glass', lang);
    } else {
      typeBadgeLabel = _tr('زجاج مفرد', 'Vitrage Simple', 'Single Glass', lang);
    }

    return _GlassInfo(
      rawLabel: rawGlass,
      cleanSpec: formattedCleanSpec,
      typeBadgeLabel: typeBadgeLabel,
      isDouble: isDouble,
      isDecor: isDecor || hasPartitions,
      hasPartitions: hasPartitions,
      hasArgon: hasArgon,
      outerFace: outerFace,
      innerFace: innerFace,
      intercall: intercall,
      partitionsJson: partitionsJson,
      imageBase64: imageBase64,
      drawingPath: drawingPath,
    );
  }

  /// ✏️ حوار تعديل قياسات الزجاج الحقيقية ونوعه مباشرةً
  Future<void> _showEditGlassDialog(Map<String, dynamic> item, _GlassInfo glassInfo, _RealGlassDimensions glassDim) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final hCtrl = TextEditingController(text: glassDim.height.toStringAsFixed(1));
    final wCtrl = TextEditingController(text: glassDim.width.toStringAsFixed(1));
    final outerCtrl = TextEditingController(text: glassInfo.isDouble ? glassInfo.outerFace : glassInfo.rawLabel);
    final intercallCtrl = TextEditingController(text: glassInfo.isDouble ? glassInfo.intercall : '12');
    final innerCtrl = TextEditingController(text: glassInfo.isDouble ? glassInfo.innerFace : '');
    bool isDoubleVal = glassInfo.isDouble;
    bool hasArgonVal = glassInfo.hasArgon;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            title: Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: Colors.teal, size: 26),
                const SizedBox(width: 8),
                Text(
                  _tr('تعديل قياس ونوع الزجاج', 'Modifier Vitrage & Mesures', 'Edit Glass & Dimensions', lang),
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr('قياسات الزجاج الحقيقية (مم):', 'Dimensions réelles du verre (mm):', 'Real Glass Dimensions (mm):', lang),
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: hCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: _tr('الارتفاع (مم)', 'Hauteur (mm)', 'Height (mm)', lang),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: wCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: _tr('العرض (مم)', 'Largeur (mm)', 'Width (mm)', lang),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 6),

                  Row(
                    children: [
                      Text(
                        _tr('نوع الزجاج:', 'Type de verre:', 'Glass Type:', lang),
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const Spacer(),
                      ChoiceChip(
                        label: Text(_tr('مفرد', 'Simple', 'Single', lang), style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                        selected: !isDoubleVal,
                        onSelected: (val) => setDlgState(() => isDoubleVal = !val),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: Text(_tr('مزدوج', 'Double', 'Double', lang), style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                        selected: isDoubleVal,
                        onSelected: (val) => setDlgState(() => isDoubleVal = val),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  if (isDoubleVal) ...[
                    TextField(
                      controller: outerCtrl,
                      decoration: InputDecoration(
                        labelText: _tr('الوجه الخارجي (مثال: ستوبسول 5 مم)', 'Face Extérieure', 'Outer Face', lang),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: intercallCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _tr('الانتركل (مم)', 'Espaceur (mm)', 'Intercall (mm)', lang),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: innerCtrl,
                            decoration: InputDecoration(
                              labelText: _tr('الوجه الداخلي (مثال: كلير 5 مم)', 'Face Intérieure', 'Inner Face', lang),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: Text(_tr('مع غاز أرجون', 'Avec Gaz Argon', 'With Argon Gas', lang), style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                      value: hasArgonVal,
                      onChanged: (val) => setDlgState(() => hasArgonVal = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ] else ...[
                    TextField(
                      controller: outerCtrl,
                      decoration: InputDecoration(
                        labelText: _tr('اسم ونوع الزجاج (مثال: كلير 5 مم)', 'Nom & Type du verre', 'Glass Name & Type', lang),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_tr('إلغاء', 'Annuler', 'Cancel', lang), style: const TextStyle(fontFamily: 'Cairo')),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newH = double.tryParse(hCtrl.text) ?? glassDim.height;
                  final newW = double.tryParse(wCtrl.text) ?? glassDim.width;
                  String newGlassText = '';

                  if (isDoubleVal) {
                    final ext = outerCtrl.text.trim().isNotEmpty ? outerCtrl.text.trim() : '5';
                    final inter = intercallCtrl.text.trim().isNotEmpty ? intercallCtrl.text.trim() : '12';
                    final intr = innerCtrl.text.trim().isNotEmpty ? innerCtrl.text.trim() : '5';
                    newGlassText = '$ext+$inter+$intr';
                    if (hasArgonVal) newGlassText += ' أرجون';
                  } else {
                    newGlassText = outerCtrl.text.trim();
                  }

                  final dbInst = await widget.db.db;
                  if (dbInst != null) {
                    final confirmedMap = <String, dynamic>{
                      'glass_height': newH,
                      'glass_width': newW,
                      'custom_spec': newGlassText,
                    };
                    await dbInst.update(
                      'Commandes_details',
                      {
                        'glass': newGlassText,
                        'confirmed_mesures_json': jsonEncode(confirmedMap),
                      },
                      where: 'id = ?',
                      whereArgs: [item['id']],
                    );
                  }

                  if (mounted) {
                    Navigator.pop(ctx);
                    await _loadOrderGlassDetails();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(_tr('حفظ التعديلات', 'Enregistrer', 'Save Changes', lang), style: const TextStyle(fontFamily: 'Cairo')),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 🚀 تأكيد استلام الزجاج مع فصل الكميات المتبقية في بطاقة جديدة
  Future<void> _confirmGlassReception() async {
    if (!mounted) return;
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;

    setState(() => _isLoading = true);

    try {
      final database = await widget.db.db;
      if (database == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      await database.transaction((txn) async {
        for (var item in _glassItems) {
          final id = item['id'] as int;
          final totalQty = (item['nbr'] ?? item['quantity'] ?? 1) as int;
          final currentReceived = _receivedQtyMap[id] ?? totalQty;
          final isAlreadyReceived = (item['is_glass_received'] ?? 0) == 1;

          if (isAlreadyReceived && !_editingUnlockedSet.contains(id)) continue;

          if (currentReceived <= 0) {
            await txn.update(
              'Commandes_details',
              {'glass_received_qty': 0, 'is_glass_received': 0},
              where: 'id = ?',
              whereArgs: [id],
            );
          } else if (currentReceived < totalQty) {
            // استلام جزئي: تحديث البطاقة الحالية بالكمية المستلمة وتحويلها لمستلمة
            await txn.update(
              'Commandes_details',
              {
                'nbr': currentReceived,
                'quantity': currentReceived,
                'glass_received_qty': currentReceived,
                'is_glass_received': 1,
              },
              where: 'id = ?',
              whereArgs: [id],
            );

            // إنشاء بطاقة جديدة تحتها بالكمية المتبقية (غير مستلمة بعد)
            final remainingQty = totalQty - currentReceived;
            final newItem = Map<String, dynamic>.from(item);
            newItem['id'] = widget.db.createDistributedId();
            newItem['nbr'] = remainingQty;
            newItem['quantity'] = remainingQty;
            newItem['glass_received_qty'] = 0;
            newItem['is_glass_received'] = 0;
            await txn.insert('Commandes_details', newItem);
          } else {
            // استلام كامل للبطاقة
            await txn.update(
              'Commandes_details',
              {
                'nbr': totalQty,
                'quantity': totalQty,
                'glass_received_qty': totalQty,
                'is_glass_received': 1,
              },
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        }

        final updatedItems = await txn.query(
          'Commandes_details',
          where: 'id_commandes = ?',
          whereArgs: [widget.commandeId],
        );
        bool allReceived = updatedItems.isNotEmpty &&
            updatedItems.every((it) => (it['is_glass_received'] ?? 0) == 1);

        if (allReceived) {
          await txn.update(
            'Commandes',
            {'status': 'Reserve'},
            where: 'id = ?',
            whereArgs: [widget.commandeId],
          );
        }
      });

      _editingUnlockedSet.clear();
      await _loadOrderGlassDetails();
      if (!mounted) return;

      final database2 = await widget.db.db;
      if (database2 == null) return;
      final finalItems = await database2.query(
        'Commandes_details',
        where: 'id_commandes = ?',
        whereArgs: [widget.commandeId],
      );
      bool isFullyReserveNow = finalItems.isNotEmpty &&
          finalItems.every((it) => (it['is_glass_received'] ?? 0) == 1);

      if (!mounted) return;

      if (isFullyReserveNow) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _tr('اكتمال استلام الزجاج', 'Réception Vitrage Complète', 'Glass Reception Complete', lang),
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: Text(
              _tr(
                'تم استلام كافة قياسات الزجاج بنجاح!\nتم تحويل الطلبية إلى: تحت التحفظ 🚀',
                'Toutes les mesures de vitrage reçues!\nCommande passée en état: Réserve 🚀',
                'All glass received!\nOrder moved to: Reserve 🚀',
                lang,
              ),
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context, true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(_tr('موافق', 'OK', 'OK', lang), style: const TextStyle(fontFamily: 'Cairo')),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr('تم حفظ استلام الزجاج ✅', 'Réception enregistrée ✅', 'Glass reception saved ✅', lang)),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Error confirming glass: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_tr("تدقيق واستلام الزجاج", "Vérification Vitrage", "Glass Reception", lang)} — #${widget.commandeId}',
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _glassItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.view_in_ar_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        _tr('لا توجد عناصر لهذه الطلبية', 'Aucun élément pour cette commande', 'No items found', lang),
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // ── شريط معلومات الطلبية والزبون ──────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: isDark ? const Color(0xFF1E293B) : Colors.teal.shade50,
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline_rounded, color: Colors.teal),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_tr("الزبون", "Client", "Customer", lang)}: ${widget.clientName.isNotEmpty ? widget.clientName : "—"}',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.teal.shade900,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              '${_glassItems.length} ${_tr("بطاقات زجاج", "cartes vitrage", "glass cards", lang)}',
                              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11, color: Colors.teal),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── قائمة عناصر الزجاج (المستلمة والمتبقية) ──────────────
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(14),
                        itemCount: _glassItems.length,
                        itemBuilder: (context, index) {
                          final item = _glassItems[index];
                          final id = item['id'] as int;
                          final totalQty = (item['nbr'] ?? item['quantity'] ?? 1) as int;
                          final isReceived = (item['is_glass_received'] ?? 0) == 1;
                          final isUnlockedForEdit = _editingUnlockedSet.contains(id);
                          final isFaded = isReceived && !isUnlockedForEdit;
                          final currentReceived = _receivedQtyMap[id] ?? totalQty;

                          final winH = item['hauteur'] ?? item['height'] ?? 0;
                          final winW = item['largeur'] ?? item['width'] ?? 0;
                          final glassDim = _calculateGlassDimensions(item);
                          final glassInfo = _parseGlassInfo(item, lang);

                          return Opacity(
                            opacity: isFaded ? 0.55 : 1.0,
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: isReceived
                                      ? const Color(0xFF10B981).withValues(alpha: 0.6)
                                      : glassInfo.isDouble
                                          ? Colors.purple.withValues(alpha: 0.45)
                                          : glassInfo.isDecor
                                              ? Colors.orange.withValues(alpha: 0.45)
                                              : (isDark ? Colors.white24 : Colors.teal.withValues(alpha: 0.3)),
                                  width: isReceived ? 1.6 : 1.2,
                                ),
                              ),
                              color: isDark ? const Color(0xFF1E293B) : Colors.white,
                              child: Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // ── رأس البطاقة ─────────────────────
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // أيقونة حالة الاستلام والنوع
                                        Container(
                                          padding: const EdgeInsets.all(9),
                                          decoration: BoxDecoration(
                                            color: isReceived
                                                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                                : glassInfo.isDouble
                                                    ? Colors.purple.withValues(alpha: 0.12)
                                                    : glassInfo.isDecor
                                                        ? Colors.orange.withValues(alpha: 0.12)
                                                        : Colors.teal.withValues(alpha: 0.12),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            isReceived
                                                ? Icons.check_circle_rounded
                                                : glassInfo.isDouble
                                                    ? Icons.layers_rounded
                                                    : glassInfo.isDecor
                                                        ? Icons.auto_awesome_rounded
                                                        : Icons.crop_square_rounded,
                                            color: isReceived
                                                ? const Color(0xFF10B981)
                                                : glassInfo.isDouble
                                                    ? Colors.purple
                                                    : glassInfo.isDecor
                                                        ? Colors.orange
                                                        : Colors.teal,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    (item['window_type'] ?? _tr('نافذة', 'Fenêtre', 'Window', lang)).toString(),
                                                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                                  ),
                                                  if (isReceived) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        _tr('تم الاستلام ✅', 'Reçu ✅', 'Received ✅', lang),
                                                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                                      ),
                                                    ),
                                                  ] else if (totalQty < (item['original_qty'] ?? totalQty)) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.orange.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        _tr('المتبقي للتأكيد ⏳', 'Reste à recevoir ⏳', 'Remaining balance ⏳', lang),
                                                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 4),

                                              // 🟢 قياس الزجاج الحقيقي المحسوب
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.teal.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.straighten_rounded, size: 13, color: Colors.teal),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      '${_tr("قياس الزجاج الحقيقي", "Taille Verre", "Glass Size", lang)}: ${glassDim.height.toStringAsFixed(1)} × ${glassDim.width.toStringAsFixed(1)} مم',
                                                      style: const TextStyle(
                                                        fontFamily: 'Cairo',
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12,
                                                        color: Colors.teal,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),

                                              const SizedBox(height: 3),
                                              Text(
                                                '${_tr("قياس النافذة", "Cadre Fenêtre", "Window Frame", lang)}: $winH × $winW مم',
                                                style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // زر التعديل المباشر للقياسات ونوع الزجاج
                                        IconButton(
                                          onPressed: () => _showEditGlassDialog(item, glassInfo, glassDim),
                                          icon: const Icon(Icons.tune_rounded, size: 20),
                                          color: Colors.teal,
                                          tooltip: _tr('تعديل القياس والنوع', 'Modifier taille & type', 'Edit size & spec', lang),
                                        ),

                                        if (isReceived && !isUnlockedForEdit)
                                          ElevatedButton.icon(
                                            onPressed: () => setState(() => _editingUnlockedSet.add(id)),
                                            icon: const Icon(Icons.edit, size: 14),
                                            label: Text(_tr('تعديل الاستلام', 'Modifier', 'Edit', lang), style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.amber.shade700,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            ),
                                          ),
                                      ],
                                    ),

                                    const SizedBox(height: 10),

                                    // ── عرض نوع واسم الزجاج مباشرة بدون الكلمات الزائدة ─────────────────
                                    _buildCleanGlassDisplay(glassInfo, isDark, lang),

                                    // ── رسم التقسيمات للديكور ────────────
                                    if (glassInfo.isDecor && glassInfo.hasPartitions) ...[
                                      const SizedBox(height: 10),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          height: 130,
                                          color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
                                          padding: const EdgeInsets.all(6),
                                          child: LazyWindowImage(
                                            db: widget.db,
                                            detailId: id,
                                            initialImagePath: glassInfo.drawingPath,
                                            partitionsJson: glassInfo.partitionsJson,
                                            drawingImageBase64: glassInfo.imageBase64.isNotEmpty ? glassInfo.imageBase64 : null,
                                            height: 120,
                                            width: double.infinity,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ],

                                    const Divider(height: 18),

                                    // ── اختيار الكمية واستلامها ─────────────────────
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          isReceived
                                              ? '${_tr("الكمية المستلمة", "Qté reçue", "Received Qty", lang)}: $totalQty'
                                              : '${_tr("الكمية المتبقية", "Qté restante", "Remaining Qty", lang)}: $totalQty',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isReceived ? const Color(0xFF10B981) : Colors.orange.shade800,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              '${_tr("تأكيد الاستلام", "Confirmer", "Confirm", lang)}:',
                                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(width: 6),
                                            IconButton(
                                              onPressed: isFaded || currentReceived <= 0
                                                  ? null
                                                  : () => setState(() => _receivedQtyMap[id] = currentReceived - 1),
                                              icon: const Icon(Icons.remove_circle_outline, size: 22),
                                              color: Colors.redAccent,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                              decoration: BoxDecoration(
                                                color: isDark ? Colors.black26 : Colors.grey.shade200,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '$currentReceived',
                                                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              onPressed: isFaded || currentReceived >= totalQty
                                                  ? null
                                                  : () => setState(() => _receivedQtyMap[id] = currentReceived + 1),
                                              icon: const Icon(Icons.add_circle_outline, size: 22),
                                              color: Colors.teal,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // ── زر التأكيد السفلي ────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, -3),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _confirmGlassReception,
                            icon: const Icon(Icons.task_alt_rounded, size: 22),
                            label: Text(
                              _tr('تأكيد وحفظ استلام الزجاج ✅', 'Enregistrer la Réception ✅', 'Save Glass Reception ✅', lang),
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  /// 🎨 عرض اسم ونوع الزجاج المباشر بدون الكلمات الزائدة (couleur, nom)
  Widget _buildCleanGlassDisplay(_GlassInfo info, bool isDark, AppLanguage lang) {
    if (info.isDouble) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.purple.withValues(alpha: isDark ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.layers_rounded, size: 16, color: Colors.purple),
                const SizedBox(width: 6),
                Text(
                  info.typeBadgeLabel,
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12, color: Colors.purple),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    info.cleanSpec,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (info.outerFace.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  _glassChip(_tr('الوجه الخارجي', 'Face ext.', 'Outer face', lang), info.outerFace, Colors.indigo, Icons.sunny),
                  const SizedBox(width: 6),
                  _glassChip(_tr('الانتركل', 'Intercall', 'Intercall', lang), '${info.intercall} مم', Colors.blueGrey, Icons.compress_rounded),
                  const SizedBox(width: 6),
                  _glassChip(_tr('الوجه الداخلي', 'Face int.', 'Inner face', lang), info.innerFace, Colors.teal, Icons.light_mode),
                ],
              ),
            ],
          ],
        ),
      );
    } else if (info.isDecor) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: isDark ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, size: 16, color: Colors.orange),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                info.cleanSpec,
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange),
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: isDark ? 0.12 : 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.crop_square_rounded, size: 16, color: Colors.teal),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                info.cleanSpec,
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _glassChip(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 9, color: color), textAlign: TextAlign.center),
            Text(value, style: TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ── نموذج أبعاد الزجاج الحقيقية ──────────────────────────────────────────────
class _RealGlassDimensions {
  final double height;
  final double width;
  final bool isCustom;

  const _RealGlassDimensions({
    required this.height,
    required this.width,
    required this.isCustom,
  });
}

// ── نموذج بيانات وتسمية الزجاج ──────────────────────────────────────────────
class _GlassInfo {
  final String rawLabel;
  final String cleanSpec;
  final String typeBadgeLabel;
  final bool isDouble;
  final bool isDecor;
  final bool hasPartitions;
  final bool hasArgon;
  final String outerFace;
  final String innerFace;
  final String intercall;
  final String partitionsJson;
  final String imageBase64;
  final String drawingPath;

  const _GlassInfo({
    required this.rawLabel,
    required this.cleanSpec,
    required this.typeBadgeLabel,
    required this.isDouble,
    required this.isDecor,
    required this.hasPartitions,
    required this.hasArgon,
    required this.outerFace,
    required this.innerFace,
    required this.intercall,
    required this.partitionsJson,
    required this.imageBase64,
    required this.drawingPath,
  });
}
