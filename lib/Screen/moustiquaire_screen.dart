import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/sql_database.dart';

enum MoustiquaireType {
  enroulable, // ملفوفة / سحاب زبرك
  plissee, // مطوية / أكورديون
  coulissante, // منزلقة / جرار
  fixe, // ثابتة
}

/// Price keys (in `ShutterSqmPrices`: colour 0 for every colour, or a colour's own price) of each mosquito-net type,
/// edited in the price management page.
const moustiquaireTypePriceKeys = [
  ('Moustiquaire_enroulable', 'Enroulable (ملفوفة / سحاب زبرك)'),
  ('Moustiquaire_plissee', 'Plissée (مطوية / أكورديون)'),
  ('Moustiquaire_coulissante', 'Coulissante (منزلقة / جرار)'),
  ('Moustiquaire_fixe', 'Fixe (إطار ثابت)'),
];

/// Price key of the mosquito net added to a drawn window, also the fallback
/// of a type without its own price.
const moustiquaireAddonPriceKey = 'Moustiquaire_Sqm';

String moustiquaireTypePriceKey(MoustiquaireType type) =>
    'Moustiquaire_${type.name}';

enum InputUnit {
  mm, // مليمتر
  cm, // سنتيمتر
}

class MoustiquaireItem {
  final String id;
  String name;
  MoustiquaireType type;
  double widthMm;
  double heightMm;
  int quantity;
  String frameColor;
  String meshColor;
  double pricePerSqm;

  MoustiquaireItem({
    required this.id,
    required this.name,
    required this.type,
    required this.widthMm,
    required this.heightMm,
    required this.quantity,
    this.frameColor = 'أبيض',
    this.meshColor = 'رمادي',
    this.pricePerSqm = 6000.0,
  });

  double get areaSqm => (widthMm / 1000.0) * (heightMm / 1000.0);
  double get totalAreaSqm => areaSqm * quantity;
  double get estimatedPrice => totalAreaSqm * pricePerSqm;
}

class MoustiquaireScreen extends StatefulWidget {
  final Map<String, dynamic>? initialPayload;
  const MoustiquaireScreen({super.key, this.initialPayload});

  @override
  State<MoustiquaireScreen> createState() => _MoustiquaireScreenState();
}

class _MoustiquaireScreenState extends State<MoustiquaireScreen> {
  final _formKey = GlobalKey<FormState>();

  final _widthController = TextEditingController(text: '1000');
  final _heightController = TextEditingController(text: '1200');
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController(text: '6000');
  final _nameController = TextEditingController();

  MoustiquaireType _selectedType = MoustiquaireType.enroulable;
  InputUnit _selectedUnit = InputUnit.mm;
  String _selectedFrameColor = 'أبيض';
  String _selectedMeshColor = 'رمادي';

  final List<String> _frameColors = [
    'أبيض',
    'بني',
    'رمادي',
    'أسود',
    'بيج',
    'شامبانيا',
    'ديزرت اوك',
  ];

  final List<String> _meshColors = ['رمادي', 'أسود'];

  /// Catalogue colour ids by name: a frame colour found in the catalogue is
  /// priced with its own mosquito-net price (price management).
  final Map<String, int> _catalogColorIds = {};

  final List<MoustiquaireItem> _items = [];

  /// Catalogue price per m² of each type (0 when not set).
  final Map<MoustiquaireType, double> _typePrices = {};
  double _addonPrice = 0;

  /// The user typed a price for this order: catalogue prices no longer
  /// replace it when the type changes.
  bool _priceEditedByUser = false;

  double _catalogPriceFor(MoustiquaireType type) {
    final own = _typePrices[type] ?? 0;
    return own > 0 ? own : _addonPrice;
  }

  void _applyCatalogPrice() {
    if (_priceEditedByUser) return;
    final price = _catalogPriceFor(_selectedType);
    if (price > 0) _priceController.text = _formatPrice(price);
  }

  String _formatPrice(double price) => price == price.roundToDouble()
      ? price.toStringAsFixed(0)
      : price.toStringAsFixed(2);

  Future<void> _loadCatalogPrices() async {
    try {
      final db = SqlDatabase();
      if (_catalogColorIds.isEmpty) {
        final database = await db.db;
        final rows = database == null
            ? const <Map<String, Object?>>[]
            : await database.query('Colors', columns: const ['id', 'name']);
        for (final row in rows) {
          final name = row['name']?.toString().trim() ?? '';
          final id = (row['id'] as num?)?.toInt();
          if (name.isNotEmpty && id != null) _catalogColorIds[name] = id;
        }
        if (mounted && _catalogColorIds.isNotEmpty) {
          setState(() {
            for (final name in _catalogColorIds.keys) {
              if (!_frameColors.contains(name)) _frameColors.add(name);
            }
          });
        }
      }
      final colorId = _catalogColorIds[_selectedFrameColor];
      final addon = await db.getShutterSqmPriceForColor(
        moustiquaireAddonPriceKey,
        colorId,
      );
      final prices = <MoustiquaireType, double>{};
      for (final type in MoustiquaireType.values) {
        prices[type] = await db.getShutterSqmPriceForColor(
          moustiquaireTypePriceKey(type),
          colorId,
        );
      }
      if (!mounted) return;
      setState(() {
        _addonPrice = addon;
        _typePrices
          ..clear()
          ..addAll(prices);
        _applyCatalogPrice();
      });
    } catch (_) {
      // Without the catalogue the price stays editable by hand.
    }
  }

  @override
  void initState() {
    super.initState();
    // A reopened order keeps the prices it was saved with.
    final hasSavedItems =
        widget.initialPayload?['items'] is List &&
        (widget.initialPayload!['items'] as List).isNotEmpty;
    _priceEditedByUser = hasSavedItems;
    _loadCatalogPrices();
    final payload = widget.initialPayload;
    final rawItems = payload?['items'];
    if (rawItems is! List) return;
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final type = MoustiquaireType.values.firstWhere(
        (value) => value.name == item['type']?.toString(),
        orElse: () => MoustiquaireType.enroulable,
      );
      final width = (item['widthMm'] as num?)?.toDouble() ?? 0;
      final height = (item['heightMm'] as num?)?.toDouble() ?? 0;
      if (width <= 0 || height <= 0) continue;
      final area =
          (item['areaSqm'] as num?)?.toDouble() ??
          ((width / 1000) * (height / 1000));
      final estimatedPrice = (item['estimatedPrice'] as num?)?.toDouble() ?? 0;
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
      final pricePerSqm =
          (item['pricePerSqm'] as num?)?.toDouble() ??
          (area > 0 && quantity > 0
              ? estimatedPrice / (area * quantity)
              : 6000);
      _items.add(
        MoustiquaireItem(
          id:
              item['id']?.toString() ??
              '${DateTime.now().microsecondsSinceEpoch}_${_items.length}',
          name: item['name']?.toString() ?? 'ناموسية',
          type: type,
          widthMm: width,
          heightMm: height,
          quantity: quantity,
          frameColor: item['frameColor']?.toString() ?? 'أبيض',
          meshColor: item['meshColor']?.toString() ?? 'رمادي',
          pricePerSqm: pricePerSqm,
        ),
      );
    }
    if (_items.isNotEmpty) {
      final first = _items.first;
      if (!_frameColors.contains(first.frameColor)) {
        _frameColors.add(first.frameColor);
      }
      if (!_meshColors.contains(first.meshColor)) {
        _meshColors.add(first.meshColor);
      }
      _selectedType = first.type;
      _selectedFrameColor = first.frameColor;
      _selectedMeshColor = first.meshColor;
      _priceController.text = first.pricePerSqm.toString();
    }
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String _getTypeLabel(MoustiquaireType type, AppLanguage lang) {
    switch (type) {
      case MoustiquaireType.enroulable:
        return Localization.translate('Enroulable (ملفوفة / سحاب زبرك)', lang);
      case MoustiquaireType.plissee:
        return Localization.translate('Plissée (مطوية / أكورديون)', lang);
      case MoustiquaireType.coulissante:
        return Localization.translate('Coulissante (منزلقة / جرار)', lang);
      case MoustiquaireType.fixe:
        return Localization.translate('Fixe (إطار ثابت)', lang);
    }
  }

  void _addItem() {
    if (!_formKey.currentState!.validate()) return;

    final double rawW = double.tryParse(_widthController.text) ?? 0.0;
    final double rawH = double.tryParse(_heightController.text) ?? 0.0;
    final int qty = int.tryParse(_quantityController.text) ?? 1;
    final double price = double.tryParse(_priceController.text) ?? 0.0;

    final double wMm = _selectedUnit == InputUnit.cm ? rawW * 10.0 : rawW;
    final double hMm = _selectedUnit == InputUnit.cm ? rawH * 10.0 : rawH;

    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final String typeName = _getTypeLabel(_selectedType, lang);
    final String customName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'ناموسية $typeName';

    final newItem = MoustiquaireItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: customName,
      type: _selectedType,
      widthMm: wMm,
      heightMm: hMm,
      quantity: qty,
      frameColor: _selectedFrameColor,
      meshColor: _selectedMeshColor,
      pricePerSqm: price,
    );

    setState(() {
      _items.add(newItem);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Localization.translate('تمت إضافة الناموسية إلى القائمة بنجاح', lang),
        ),
        backgroundColor: Colors.teal,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _finishAndReturn() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(
              'يرجى إضافة ناموسية واحدة على الأقل أولاً',
              lang,
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    double grandTotalArea = 0.0;
    double grandTotalPrice = 0.0;
    int grandTotalQty = 0;

    for (var item in _items) {
      grandTotalArea += item.totalAreaSqm;
      grandTotalPrice += item.estimatedPrice;
      grandTotalQty += item.quantity;
    }

    final firstItem = _items.first;
    final payload = {
      'type': 'moustiquaire',
      'subType': _getTypeLabel(firstItem.type, lang),
      'itemsCount': _items.length,
      'totalQuantity': grandTotalQty,
      'grandTotalAreaSqm': grandTotalArea,
      'grandTotalPrice': grandTotalPrice,
      'widthMm': firstItem.widthMm,
      'heightMm': firstItem.heightMm,
      'frameColor': firstItem.frameColor,
      'meshColor': firstItem.meshColor,
      'items': _items
          .map(
            (i) => {
              'id': i.id,
              'name': i.name,
              'type': i.type.name,
              'widthMm': i.widthMm,
              'heightMm': i.heightMm,
              'quantity': i.quantity,
              'areaSqm': i.areaSqm,
              'totalAreaSqm': i.totalAreaSqm,
              'frameColor': i.frameColor,
              'meshColor': i.meshColor,
              'pricePerSqm': i.pricePerSqm,
              'estimatedPrice': i.estimatedPrice,
            },
          )
          .toList(),
    };

    Navigator.pop(context, payload);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    double grandTotalArea = 0.0;
    double grandTotalPrice = 0.0;
    int grandTotalQty = 0;
    for (var item in _items) {
      grandTotalArea += item.totalAreaSqm;
      grandTotalPrice += item.estimatedPrice;
      grandTotalQty += item.quantity;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate('نظام الموستيكير (Moustiquaire)', lang),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // بطاقة تعليمية / إرشادات
            Card(
              color: Colors.teal.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.grid_4x4_rounded,
                      color: Colors.teal,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Localization.translate(
                              'نظام ناموسيات الحشرات (Moustiquaire)',
                              lang,
                            ),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            Localization.translate(
                              'اختر نوع الناموسية (ملفوفة، مطوية أكورديون، منزلقة، ثابتة) وأدخل الأبعاد لتلقائياً إضافتها إلى الطلبية.',
                              lang,
                            ),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Colors.teal.shade900,
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

            // نموذج إضافة ناموسية
            Form(
              key: _formKey,
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune_rounded, color: Colors.teal),
                          const SizedBox(width: 8),
                          Text(
                            Localization.translate(
                              'نوع الناموسية (Subtype)',
                              lang,
                            ),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: MoustiquaireType.values.map((t) {
                          final isSel = _selectedType == t;
                          return ChoiceChip(
                            avatar: isSel
                                ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : null,
                            label: Text(
                              _getTypeLabel(t, lang),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                color: isSel ? Colors.white : null,
                              ),
                            ),
                            selected: isSel,
                            selectedColor: Colors.teal.shade700,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedType = t;
                                  _applyCatalogPrice();
                                });
                              }
                            },
                          );
                        }).toList(),
                      ),
                      const Divider(height: 24),

                      // وحدة الإدخال (مم / سم)
                      Row(
                        children: [
                          Text(
                            Localization.translate('وحدة القياس:', lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SegmentedButton<InputUnit>(
                            segments: [
                              ButtonSegment(
                                value: InputUnit.mm,
                                label: Text(
                                  Localization.translate('مم (mm)', lang),
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                              ),
                              ButtonSegment(
                                value: InputUnit.cm,
                                label: Text(
                                  Localization.translate('سم (cm)', lang),
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                              ),
                            ],
                            selected: {_selectedUnit},
                            onSelectionChanged: (val) {
                              setState(() {
                                _selectedUnit = val.first;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // الأبعاد: العرض والطول والعدد
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _widthController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    '${Localization.translate('العرض', lang)} (${Localization.translate(_selectedUnit == InputUnit.mm ? 'مم' : 'سم', lang)})',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (val) => val == null || val.isEmpty
                                  ? Localization.translate('مطلوب', lang)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _heightController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText:
                                    '${Localization.translate('الارتفاع', lang)} (${Localization.translate(_selectedUnit == InputUnit.mm ? 'مم' : 'سم', lang)})',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (val) => val == null || val.isEmpty
                                  ? Localization.translate('مطلوب', lang)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 80,
                            child: TextFormField(
                              controller: _quantityController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: Localization.translate(
                                  'العدد',
                                  lang,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (val) => val == null || val.isEmpty
                                  ? Localization.translate('مطلوب', lang)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // ألوان الإطار والشبكة
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  Localization.translate(
                                    'لون إطار الألمنيوم',
                                    lang,
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<String>(
                                  value: _selectedFrameColor,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  items: _frameColors
                                      .map(
                                        (c) => DropdownMenuItem(
                                          value: c,
                                          child: Text(
                                            Localization.colorName(c, lang),
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) {
                                    if (val == null) return;
                                    setState(() => _selectedFrameColor = val);
                                    // The price follows the frame colour.
                                    _loadCatalogPrices();
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  Localization.translate(
                                    'لون شبكة الناموس',
                                    lang,
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<String>(
                                  value: _selectedMeshColor,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  items: _meshColors
                                      .map(
                                        (c) => DropdownMenuItem(
                                          value: c,
                                          child: Text(
                                            Localization.colorName(c, lang),
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null)
                                      setState(() => _selectedMeshColor = val);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // السعر المتر المربع
                      TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => _priceEditedByUser = true,
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'سعر المتر المربع (د.ج / m²)',
                            lang,
                          ),
                          helperText: _catalogPriceFor(_selectedType) > 0
                              ? '${Localization.translate('سعر إدارة الأسعار', lang)}: '
                                    '${_formatPrice(_catalogPriceFor(_selectedType))}'
                              : Localization.translate(
                                  'لا يوجد سعر لهذا النوع في إدارة الأسعار',
                                  lang,
                                ),
                          suffixIcon: _catalogPriceFor(_selectedType) > 0
                              ? IconButton(
                                  tooltip: Localization.translate(
                                    'استعمال سعر إدارة الأسعار',
                                    lang,
                                  ),
                                  icon: const Icon(Icons.restore_rounded),
                                  onPressed: () => setState(() {
                                    _priceEditedByUser = false;
                                    _applyCatalogPrice();
                                  }),
                                )
                              : null,
                          prefixIcon: const Icon(
                            Icons.attach_money_rounded,
                            color: Colors.teal,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // زر الإضافة
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          label: Text(
                            Localization.translate(
                              'إضافة هذه الناموسية إلى القائمة',
                              lang,
                            ),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _addItem,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // قائمة العناصر المضافة
            Text(
              '${Localization.translate('قائمة الناموسيات المضافة', lang)} (${_items.length})',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),

            _items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        Localization.translate(
                          'لم تقم بإضافة أي ناموسيات بعد. قم بتعيين الأبعاد وانقر على زر الإضافة.',
                          lang,
                        ),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _items.length,
                    itemBuilder: (ctx, idx) {
                      final item = _items[idx];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.teal.shade50,
                            child: const Icon(
                              Icons.grid_4x4_rounded,
                              color: Colors.teal,
                            ),
                          ),
                          title: Text(
                            '${item.name} (${item.quantity}×) - ${item.widthMm.toInt()}×${item.heightMm.toInt()} مم',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            '${Localization.translate('النوع:', lang)} ${_getTypeLabel(item.type, lang)} | ${Localization.translate('إطار:', lang)} ${Localization.colorName(item.frameColor, lang)} | ${Localization.translate('المساحة:', lang)} ${item.totalAreaSqm.toStringAsFixed(2)} m²',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${item.estimatedPrice.toStringAsFixed(0)} د.ج',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _items.removeAt(idx);
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

            const SizedBox(height: 20),

            // بطاقة الإجمالي وزر الحفظ النهائي
            if (_items.isNotEmpty) ...[
              Card(
                color: isDark ? Colors.grey.shade900 : Colors.teal.shade900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            Localization.translate('إجمالي عدد القطع:', lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '$grandTotalQty قطعة',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            Localization.translate(
                              'إجمالي المساحة الكلية:',
                              lang,
                            ),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${grandTotalArea.toStringAsFixed(2)} m²',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white24, height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            Localization.translate(
                              'إجمالي السعر التقديري:',
                              lang,
                            ),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${grandTotalPrice.toStringAsFixed(0)} د.ج',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.lightGreenAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle_rounded),
                          label: Text(
                            Localization.translate(
                              'تأكيد وإضافة الموستيكير إلى الطلبية',
                              lang,
                            ),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.tealAccent.shade400,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _finishAndReturn,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
