import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';

enum GlassWorkType {
  vitrine,
  showerCabin,
  glassDoor,
  facade,
  railing,
  tabletop,
  other,
}

enum GlassWorkFinish { clear, frosted, smoked, laminated, decorative }

enum GlassStickerType { none, motif, full }

/// The first glass-drawing vocabulary is intentionally independent from the
/// aluminium/PVC series model.  It can therefore evolve without changing the
/// existing window calculations.
enum GlassPanelShape { straight, l, u }

enum GlassOperation { sliding, hinged }

class GlassHoleDefinition {
  GlassHoleDefinition({
    required this.id,
    this.diameterMm = 10,
    this.fromTopMm = 0,
    this.fromBottomMm = 0,
    this.fromLeftMm = 0,
    this.fromRightMm = 0,
  });

  final String id;
  double diameterMm;
  double fromTopMm;
  double fromBottomMm;
  double fromLeftMm;
  double fromRightMm;

  Map<String, dynamic> toMap() => {
    'id': id,
    'diameterMm': diameterMm,
    'fromTopMm': fromTopMm,
    'fromBottomMm': fromBottomMm,
    'fromLeftMm': fromLeftMm,
    'fromRightMm': fromRightMm,
  };

  factory GlassHoleDefinition.fromMap(Map<String, dynamic> map) {
    double read(String key, [double fallback = 0]) =>
        (map[key] as num?)?.toDouble() ?? fallback;

    return GlassHoleDefinition(
      id:
          map['id']?.toString() ??
          'hole_${DateTime.now().microsecondsSinceEpoch}',
      diameterMm: read('diameterMm', 10),
      fromTopMm: read('fromTopMm'),
      fromBottomMm: read('fromBottomMm'),
      fromLeftMm: read('fromLeftMm'),
      fromRightMm: read('fromRightMm'),
    );
  }
}

class GlassKitDefinition {
  GlassKitDefinition({
    required this.id,
    required this.name,
    List<GlassHoleDefinition>? holes,
  }) : holes = holes ?? <GlassHoleDefinition>[];

  final String id;
  String name;
  final List<GlassHoleDefinition> holes;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'holes': holes.map((hole) => hole.toMap()).toList(),
  };

  factory GlassKitDefinition.fromMap(Map<String, dynamic> map) {
    final rawHoles = map['holes'];
    return GlassKitDefinition(
      id:
          map['id']?.toString() ??
          'kit_${DateTime.now().microsecondsSinceEpoch}',
      name: map['name']?.toString() ?? '',
      holes: rawHoles is List
          ? rawHoles
                .whereType<Map>()
                .map(
                  (hole) => GlassHoleDefinition.fromMap(
                    Map<String, dynamic>.from(hole),
                  ),
                )
                .toList()
          : <GlassHoleDefinition>[],
    );
  }
}

class GlassWorkMeasurement {
  GlassWorkMeasurement({
    required this.id,
    required this.widthMm,
    required this.heightMm,
    required this.quantity,
    required this.pricePerSqm,
  });

  final String id;
  final double widthMm;
  final double heightMm;
  final int quantity;
  final double pricePerSqm;

  double get areaSqm => (widthMm / 1000) * (heightMm / 1000);
  double get unitPrice => areaSqm * pricePerSqm;
  double get totalPrice => unitPrice * quantity;

  Map<String, dynamic> toMap() => {
    'id': id,
    'widthMm': widthMm,
    'heightMm': heightMm,
    'quantity': quantity,
    'areaSqm': areaSqm,
    'pricePerSqm': pricePerSqm,
    'unitPrice': unitPrice,
    'totalPrice': totalPrice,
  };
}

class TemperedGlassWorkScreen extends StatefulWidget {
  const TemperedGlassWorkScreen({super.key, this.initialPayload});

  final Map<String, dynamic>? initialPayload;

  @override
  State<TemperedGlassWorkScreen> createState() =>
      _TemperedGlassWorkScreenState();
}

class _TemperedGlassWorkScreenState extends State<TemperedGlassWorkScreen> {
  final _formKey = GlobalKey<FormState>();
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  final _imagePicker = ImagePicker();

  GlassWorkType _workType = GlassWorkType.vitrine;
  GlassWorkFinish _glassFinish = GlassWorkFinish.clear;
  GlassStickerType _stickerType = GlassStickerType.none;
  GlassPanelShape _panelShape = GlassPanelShape.straight;
  GlassOperation _operation = GlassOperation.sliding;
  int _doorCount = 1;
  String? _selectedKitId;
  final List<GlassKitDefinition> _slidingKits = [];
  double _thicknessMm = 10;
  String? _imagePath;
  final List<GlassWorkMeasurement> _measurements = [];

  @override
  void initState() {
    super.initState();
    _restoreInitialPayload();
  }

  void _restoreInitialPayload() {
    final payload = widget.initialPayload;
    if (payload == null) {
      _ensureDefaultSlidingKits();
      return;
    }

    _workType = GlassWorkType.values.firstWhere(
      (value) => value.name == payload['workType']?.toString(),
      orElse: () => GlassWorkType.vitrine,
    );
    _glassFinish = GlassWorkFinish.values.firstWhere(
      (value) => value.name == payload['glassFinish']?.toString(),
      orElse: () => GlassWorkFinish.clear,
    );
    _stickerType = GlassStickerType.values.firstWhere(
      (value) => value.name == payload['stickerType']?.toString(),
      orElse: () => GlassStickerType.none,
    );
    _panelShape = GlassPanelShape.values.firstWhere(
      (value) => value.name == payload['panelShape']?.toString(),
      orElse: () => GlassPanelShape.straight,
    );
    _operation = GlassOperation.values.firstWhere(
      (value) => value.name == payload['operation']?.toString(),
      orElse: () => GlassOperation.sliding,
    );
    _doorCount = (((payload['doorCount'] as num?)?.toInt() ?? 1).clamp(1, 2))
        .toInt();
    _selectedKitId = payload['selectedKitId']?.toString();
    final rawKits = payload['kits'];
    if (rawKits is List) {
      _slidingKits.addAll(
        rawKits
            .whereType<Map>()
            .map(
              (kit) => GlassKitDefinition.fromMap(
                Map<String, dynamic>.from(kit),
              ),
            )
            .where((kit) => kit.id.isNotEmpty),
      );
    }
    _ensureDefaultSlidingKits();
    _thicknessMm = (payload['thicknessMm'] as num?)?.toDouble() ?? 10;
    _imagePath = payload['imagePath']?.toString();
    _notesController.text = payload['notes']?.toString() ?? '';

    final rawItems = payload['items'];
    if (rawItems is! List) return;
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final width = (item['widthMm'] as num?)?.toDouble() ?? 0;
      final height = (item['heightMm'] as num?)?.toDouble() ?? 0;
      if (width <= 0 || height <= 0) continue;
      _measurements.add(
        GlassWorkMeasurement(
          id:
              item['id']?.toString() ??
              '${DateTime.now().microsecondsSinceEpoch}_${_measurements.length}',
          widthMm: width,
          heightMm: height,
          quantity: (item['quantity'] as num?)?.toInt() ?? 1,
          pricePerSqm: (item['pricePerSqm'] as num?)?.toDouble() ?? 0,
        ),
      );
    }

    if (_measurements.isNotEmpty) {
      _priceController.text = _measurements.first.pricePerSqm.toString();
    }
  }

  void _ensureDefaultSlidingKits() {
    if (_slidingKits.isEmpty) {
      _slidingKits.addAll([
        GlassKitDefinition(id: 'sliding_kit_1', name: 'Kit 1'),
        GlassKitDefinition(id: 'sliding_kit_2', name: 'Kit 2'),
        GlassKitDefinition(id: 'sliding_kit_3', name: 'Kit 3'),
      ]);
    }
    _selectedKitId ??= _slidingKits.first.id;
    if (!_slidingKits.any((kit) => kit.id == _selectedKitId)) {
      _selectedKitId = _slidingKits.first.id;
    }
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _tr(String ar, String fr, String en) {
    final language = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final dictionaryValue = Localization.translate(ar, language);
    if (language == AppLanguage.arabic || dictionaryValue != ar) {
      return dictionaryValue;
    }
    switch (language) {
      case AppLanguage.french:
        return fr;
      case AppLanguage.english:
        return en;
      case AppLanguage.arabic:
        return ar;
    }
  }

  String _shapeLabel(GlassPanelShape shape) {
    switch (shape) {
      case GlassPanelShape.straight:
        return _tr('مستقيم (I)', 'Droit (I)', 'Straight (I)');
      case GlassPanelShape.l:
        return _tr('زاوية (L)', 'Angle (L)', 'L shape');
      case GlassPanelShape.u:
        return _tr('حرف U', 'En U', 'U shape');
    }
  }

  String _operationLabel(GlassOperation operation) {
    switch (operation) {
      case GlassOperation.sliding:
        return _tr('منزلق', 'Coulissant', 'Sliding');
      case GlassOperation.hinged:
        return _tr('فتح عادي', 'Ouverture battante', 'Hinged opening');
    }
  }

  GlassKitDefinition? get _selectedKit {
    for (final kit in _slidingKits) {
      if (kit.id == _selectedKitId) return kit;
    }
    return _slidingKits.isEmpty ? null : _slidingKits.first;
  }

  Widget _buildKitEditor(BuildContext context) {
    final kit = _selectedKit;
    if (kit == null) return const SizedBox.shrink();

    TextFormField numberField({
      required String label,
      required double value,
      required ValueChanged<double> onChanged,
    }) {
      return TextFormField(
        initialValue: value == 0 ? '' : value.toStringAsFixed(0),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'mm',
          border: const OutlineInputBorder(),
        ),
        onChanged: (text) {
          final parsed = double.tryParse(text.trim());
          if (parsed != null && parsed >= 0) onChanged(parsed);
        },
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _tr('خصائص الكيت والثقوب', 'Propriétés du kit et perçages', 'Kit and hole properties'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey(kit.id),
              initialValue: kit.name,
              decoration: InputDecoration(
                labelText: _tr('اسم الكيت', 'Nom du kit', 'Kit name'),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => kit.name = value.trim().isEmpty ? kit.name : value,
            ),
            const SizedBox(height: 10),
            if (kit.holes.isEmpty)
              Text(
                _tr(
                  'لم تتم إضافة ثقوب لهذا الكيت بعد.',
                  'Aucun perçage n’est encore ajouté à ce kit.',
                  'No holes have been added to this kit yet.',
                ),
                style: TextStyle(color: Colors.grey.shade700),
              ),
            for (var index = 0; index < kit.holes.length; index++)
              Card(
                key: ValueKey(kit.holes[index].id),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_tr('الثقب', 'Perçage', 'Hole')} ${index + 1}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            tooltip: _tr('حذف الثقب', 'Supprimer le perçage', 'Delete hole'),
                            onPressed: () => setState(() => kit.holes.removeAt(index)),
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                          ),
                        ],
                      ),
                      numberField(
                        label: _tr('قطر الثقب', 'Diamètre du perçage', 'Hole diameter'),
                        value: kit.holes[index].diameterMm,
                        onChanged: (value) => kit.holes[index].diameterMm = value,
                      ),
                      const SizedBox(height: 8),
                      numberField(
                        label: _tr('من أعلى الزجاج', 'Depuis le haut du verre', 'From glass top'),
                        value: kit.holes[index].fromTopMm,
                        onChanged: (value) => kit.holes[index].fromTopMm = value,
                      ),
                      const SizedBox(height: 8),
                      numberField(
                        label: _tr('من أسفل الزجاج', 'Depuis le bas du verre', 'From glass bottom'),
                        value: kit.holes[index].fromBottomMm,
                        onChanged: (value) => kit.holes[index].fromBottomMm = value,
                      ),
                      const SizedBox(height: 8),
                      numberField(
                        label: _tr('من اليمين', 'Depuis la droite', 'From right'),
                        value: kit.holes[index].fromRightMm,
                        onChanged: (value) => kit.holes[index].fromRightMm = value,
                      ),
                      const SizedBox(height: 8),
                      numberField(
                        label: _tr('من اليسار', 'Depuis la gauche', 'From left'),
                        value: kit.holes[index].fromLeftMm,
                        onChanged: (value) => kit.holes[index].fromLeftMm = value,
                      ),
                    ],
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  kit.holes.add(
                    GlassHoleDefinition(
                      id: 'hole_${DateTime.now().microsecondsSinceEpoch}',
                    ),
                  );
                });
              },
              icon: const Icon(Icons.add_circle_outline),
              label: Text(_tr('إضافة ثقب للكيت', 'Ajouter un perçage au kit', 'Add hole to kit')),
            ),
          ],
        ),
      ),
    );
  }

  String _workTypeLabel(GlassWorkType type) {
    switch (type) {
      case GlassWorkType.vitrine:
        return _tr('فيترين / واجهة محل', 'Vitrine', 'Storefront');
      case GlassWorkType.showerCabin:
        return _tr('كابين دوش', 'Cabine de douche', 'Shower cabin');
      case GlassWorkType.glassDoor:
        return _tr('باب زجاجي', 'Porte en verre', 'Glass door');
      case GlassWorkType.facade:
        return _tr('واجهة زجاجية', 'Façade vitrée', 'Glass facade');
      case GlassWorkType.railing:
        return _tr('درابزين زجاجي', 'Garde-corps', 'Glass railing');
      case GlassWorkType.tabletop:
        return _tr('طاولة أو رف زجاجي', 'Table / étagère', 'Table / shelf');
      case GlassWorkType.other:
        return _tr('عمل زجاجي آخر', 'Autre travail', 'Other glass work');
    }
  }

  String _finishLabel(GlassWorkFinish finish) {
    switch (finish) {
      case GlassWorkFinish.clear:
        return _tr('شفاف', 'Clair', 'Clear');
      case GlassWorkFinish.frosted:
        return _tr('سابلي / مصنفر', 'Sablé', 'Frosted');
      case GlassWorkFinish.smoked:
        return _tr('فيمي / مدخن', 'Fumé', 'Smoked');
      case GlassWorkFinish.laminated:
        return _tr('فيتي / مورق', 'Feuilleté', 'Laminated');
      case GlassWorkFinish.decorative:
        return _tr('ديكور', 'Décor', 'Decorative');
    }
  }

  String _stickerLabel(GlassStickerType type) {
    switch (type) {
      case GlassStickerType.none:
        return _tr('بدون ستيكر', 'Sans sticker', 'No sticker');
      case GlassStickerType.motif:
        return _tr('ستيكر موشي / نقش جزئي', 'Sticker motif', 'Pattern sticker');
      case GlassStickerType.full:
        return _tr('ستيكر كامل', 'Sticker complet', 'Full sticker');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await _imagePicker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2200,
      maxHeight: 2200,
    );
    if (image == null || !mounted) return;
    setState(() => _imagePath = image.path);
  }

  Future<void> _chooseImageSource() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                _tr(
                  'اختيار صورة من الهاتف',
                  'Choisir depuis la galerie',
                  'Choose from gallery',
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(
                _tr('التقاط صورة', 'Prendre une photo', 'Take a photo'),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  String? _positiveNumberValidator(String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    if (number == null || number <= 0) {
      return _tr('أدخل رقماً أكبر من صفر', 'Valeur invalide', 'Invalid value');
    }
    return null;
  }

  void _addMeasurement() {
    if (!_formKey.currentState!.validate()) return;
    final width = double.parse(_widthController.text.trim());
    final height = double.parse(_heightController.text.trim());
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 1;
    final price = double.tryParse(_priceController.text.trim()) ?? 0;

    setState(() {
      _measurements.add(
        GlassWorkMeasurement(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          widthMm: width,
          heightMm: height,
          quantity: quantity < 1 ? 1 : quantity,
          pricePerSqm: price < 0 ? 0 : price,
        ),
      );
      _widthController.clear();
      _heightController.clear();
      _quantityController.text = '1';
    });
  }

  void _finish() {
    if (_measurements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'أضف قياساً واحداً على الأقل',
              'Ajoutez au moins une mesure',
              'Add at least one measurement',
            ),
          ),
        ),
      );
      return;
    }

    final totalArea = _measurements.fold<double>(
      0,
      (sum, item) => sum + (item.areaSqm * item.quantity),
    );
    final totalPrice = _measurements.fold<double>(
      0,
      (sum, item) => sum + item.totalPrice,
    );
    final totalQuantity = _measurements.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    Navigator.pop(context, <String, dynamic>{
      'type': 'tempered_glass_work',
      'workType': _workType.name,
      'workTypeLabel': _workTypeLabel(_workType),
      'glassFinish': _glassFinish.name,
      'glassFinishLabel': _finishLabel(_glassFinish),
      'panelShape': _panelShape.name,
      'panelShapeLabel': _shapeLabel(_panelShape),
      'operation': _operation.name,
      'operationLabel': _operationLabel(_operation),
      'doorCount': _doorCount,
      'selectedKitId': _selectedKitId,
      'selectedKitLabel': _selectedKit?.name,
      'kits': _slidingKits.map((kit) => kit.toMap()).toList(),
      'thicknessMm': _thicknessMm,
      'stickerType': _stickerType.name,
      'stickerLabel': _stickerLabel(_stickerType),
      'imagePath': _imagePath,
      'notes': _notesController.text.trim(),
      'itemsCount': _measurements.length,
      'totalQuantity': totalQuantity,
      'grandTotalAreaSqm': totalArea,
      'grandTotalPrice': totalPrice,
      'items': _measurements.map((item) => item.toMap()).toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalArea = _measurements.fold<double>(
      0,
      (sum, item) => sum + (item.areaSqm * item.quantity),
    );
    final totalPrice = _measurements.fold<double>(
      0,
      (sum, item) => sum + item.totalPrice,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr(
            'أعمال الزجاج المقسّى',
            'Travaux en verre trempé',
            'Tempered glass work',
          ),
        ),
        backgroundColor: Colors.cyan.shade800,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: isDark ? Colors.cyan.shade900 : Colors.cyan.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _tr(
                    'اختر نوع العمل والزجاج والصورة مرة واحدة، ثم أضف كل القياسات. عند التأكيد سيُضاف كل قياس كسطر مستقل في الطلبية مع نفس الصورة.',
                    'Choisissez le travail, le verre et l’image une fois, puis ajoutez les mesures. Chaque mesure sera une ligne indépendante avec la même image.',
                    'Choose the work, glass and image once, then add measurements. Each measurement becomes a separate order line with the same image.',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _tr(
                        'تهيئة رسم الألواح الزجاجية',
                        'Préparation du dessin des panneaux vitrés',
                        'Glass panel drawing setup',
                      ),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _tr(
                        'الرسم مستقل عن سلاسل الألمنيوم ويعرض اللوح كزجاج، وليس كإطار.',
                        'Le dessin est indépendant des gammes aluminium et affiche un panneau vitré, pas un cadre.',
                        'The drawing is independent from aluminium series and displays a glass panel, not a frame.',
                      ),
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 230,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.blueGrey.shade900 : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.cyan.shade700 : Colors.blue.shade200,
                        ),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: CustomPaint(
                        painter: _GlassPanelPainter(
                          shape: _panelShape,
                          operation: _operation,
                          doorCount: _doorCount,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<GlassPanelShape>(
                            initialValue: _panelShape,
                            decoration: InputDecoration(
                              labelText: _tr('شكل الرسم', 'Forme du dessin', 'Drawing shape'),
                              border: const OutlineInputBorder(),
                            ),
                            items: GlassPanelShape.values
                                .map(
                                  (shape) => DropdownMenuItem(
                                    value: shape,
                                    child: Text(_shapeLabel(shape)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) setState(() => _panelShape = value);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<GlassOperation>(
                            initialValue: _operation,
                            decoration: InputDecoration(
                              labelText: _tr('نظام التشغيل', 'Mode d’ouverture', 'Opening system'),
                              border: const OutlineInputBorder(),
                            ),
                            items: GlassOperation.values
                                .map(
                                  (operation) => DropdownMenuItem(
                                    value: operation,
                                    child: Text(_operationLabel(operation)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) setState(() => _operation = value);
                            },
                          ),
                        ),
                      ],
                    ),
                    if (_workType == GlassWorkType.vitrine) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: _doorCount,
                        decoration: InputDecoration(
                          labelText: _tr('عدد أبواب الواجهة', 'Nombre de portes de la vitrine', 'Storefront door count'),
                          border: const OutlineInputBorder(),
                        ),
                        items: const [1, 2]
                            .map(
                              (count) => DropdownMenuItem(
                                value: count,
                                child: Text('$count'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _doorCount = value);
                        },
                      ),
                    ],
                    if (_operation == GlassOperation.sliding) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedKitId,
                        decoration: InputDecoration(
                          labelText: _tr('كيت النظام المنزلق', 'Kit du système coulissant', 'Sliding system kit'),
                          border: const OutlineInputBorder(),
                        ),
                        items: _slidingKits
                            .map(
                              (kit) => DropdownMenuItem(
                                value: kit.id,
                                child: Text(kit.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => _selectedKitId = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildKitEditor(context),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          final id =
                              'sliding_kit_${DateTime.now().microsecondsSinceEpoch}';
                          setState(() {
                            _slidingKits.add(
                              GlassKitDefinition(
                                id: id,
                                name: 'Kit ${_slidingKits.length + 1}',
                              ),
                            );
                            _selectedKitId = id;
                          });
                        },
                        icon: const Icon(Icons.library_add_outlined),
                        label: Text(
                          _tr('إضافة كيت جديد', 'Ajouter un nouveau kit', 'Add new kit'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    DropdownButtonFormField<GlassWorkType>(
                      initialValue: _workType,
                      decoration: InputDecoration(
                        labelText: _tr(
                          'نوع العمل الزجاجي',
                          'Type de travail',
                          'Work type',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      items: GlassWorkType.values
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(_workTypeLabel(type)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _workType = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<double>(
                            initialValue: _thicknessMm,
                            decoration: InputDecoration(
                              labelText: _tr(
                                'سماكة الزجاج',
                                'Épaisseur',
                                'Thickness',
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            items: const [6.0, 8.0, 10.0, 12.0]
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('${value.toInt()} mm'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _thicknessMm = value);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<GlassWorkFinish>(
                            initialValue: _glassFinish,
                            decoration: InputDecoration(
                              labelText: _tr(
                                'نوع الزجاج',
                                'Type de verre',
                                'Glass finish',
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            items: GlassWorkFinish.values
                                .map(
                                  (finish) => DropdownMenuItem(
                                    value: finish,
                                    child: Text(_finishLabel(finish)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _glassFinish = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<GlassStickerType>(
                      initialValue: _stickerType,
                      decoration: InputDecoration(
                        labelText: _tr(
                          'نوع الستيكر',
                          'Type de sticker',
                          'Sticker type',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      items: GlassStickerType.values
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(_stickerLabel(type)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _stickerType = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: _tr('ملاحظات العمل', 'Notes', 'Work notes'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _tr(
                        'الصورة المشتركة لكل القياسات',
                        'Image commune à toutes les mesures',
                        'Shared image for all measurements',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 190,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black26 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child:
                          _imagePath != null &&
                              _imagePath!.isNotEmpty &&
                              File(_imagePath!).existsSync()
                          ? Image.file(File(_imagePath!), fit: BoxFit.contain)
                          : const Center(
                              child: Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 64,
                                color: Colors.grey,
                              ),
                            ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _chooseImageSource,
                      icon: const Icon(Icons.photo_camera_back_outlined),
                      label: Text(
                        _tr(
                          'اختيار أو تصوير العمل',
                          'Choisir ou prendre une photo',
                          'Choose or take a photo',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Form(
              key: _formKey,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _tr(
                          'إضافة قياس',
                          'Ajouter une mesure',
                          'Add measurement',
                        ),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _widthController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: _positiveNumberValidator,
                              decoration: InputDecoration(
                                labelText: _tr(
                                  'العرض (mm)',
                                  'Largeur (mm)',
                                  'Width (mm)',
                                ),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _heightController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: _positiveNumberValidator,
                              decoration: InputDecoration(
                                labelText: _tr(
                                  'الطول (mm)',
                                  'Hauteur (mm)',
                                  'Height (mm)',
                                ),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _quantityController,
                              keyboardType: TextInputType.number,
                              validator: _positiveNumberValidator,
                              decoration: InputDecoration(
                                labelText: _tr(
                                  'الكمية',
                                  'Quantité',
                                  'Quantity',
                                ),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _priceController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: _tr(
                                  'سعر المتر المربع',
                                  'Prix / m²',
                                  'Price / m²',
                                ),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _addMeasurement,
                        icon: const Icon(Icons.add),
                        label: Text(
                          _tr(
                            'إضافة هذا القياس',
                            'Ajouter cette mesure',
                            'Add this measurement',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_measurements.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      for (var index = 0; index < _measurements.length; index++)
                        ListTile(
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text(
                            '${_measurements[index].widthMm.toStringAsFixed(0)} × '
                            '${_measurements[index].heightMm.toStringAsFixed(0)} mm',
                          ),
                          subtitle: Text(
                            '${_tr("الكمية", "Qté", "Qty")}: '
                            '${_measurements[index].quantity} — '
                            '${_measurements[index].areaSqm.toStringAsFixed(2)} m²',
                          ),
                          trailing: IconButton(
                            onPressed: () {
                              setState(() => _measurements.removeAt(index));
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (_measurements.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                color: isDark ? Colors.cyan.shade900 : Colors.cyan.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${_tr("إجمالي المساحة", "Surface totale", "Total area")}: '
                        '${totalArea.toStringAsFixed(2)} m²',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_tr("الإجمالي", "Total", "Total")}: '
                        '${totalPrice.toStringAsFixed(0)} دج',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyan.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _finish,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(
                          _tr(
                            'تأكيد وإضافة القياسات مستقلة إلى الطلبية',
                            'Confirmer et ajouter les mesures séparément',
                            'Confirm and add separate order lines',
                          ),
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

class _GlassPanelPainter extends CustomPainter {
  const _GlassPanelPainter({
    required this.shape,
    required this.operation,
    required this.doorCount,
  });

  final GlassPanelShape shape;
  final GlassOperation operation;
  final int doorCount;

  @override
  void paint(Canvas canvas, Size size) {
    final borderColor = Colors.cyan.shade800;
    final fillPaint = Paint()
      ..color = const Color(0xFFB9E5F8).withValues(alpha: 0.78)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = borderColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final reflectionPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.62)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final maxWidth = size.width * 0.78;
    final maxHeight = size.height * 0.78;
    final left = (size.width - maxWidth) / 2;
    final top = (size.height - maxHeight) / 2;
    final panelCount = switch (shape) {
      GlassPanelShape.straight => 1,
      GlassPanelShape.l => 2,
      GlassPanelShape.u => 3,
    };
    final panelWidth = maxWidth / panelCount;
    final panelHeight = maxHeight;

    final panels = <Rect>[];
    switch (shape) {
      case GlassPanelShape.straight:
        panels.add(Rect.fromLTWH(left, top, maxWidth, maxHeight));
      case GlassPanelShape.l:
        panels.add(Rect.fromLTWH(left, top, panelWidth, panelHeight));
        panels.add(
          Rect.fromLTWH(left + panelWidth, top + panelHeight / 2, panelWidth, panelHeight / 2),
        );
      case GlassPanelShape.u:
        panels.add(Rect.fromLTWH(left, top, panelWidth, panelHeight));
        panels.add(
          Rect.fromLTWH(left + panelWidth, top + panelHeight / 2, panelWidth, panelHeight / 2),
        );
        panels.add(
          Rect.fromLTWH(left + panelWidth * 2, top, panelWidth, panelHeight),
        );
    }

    for (final panel in panels) {
      canvas.drawRect(panel, fillPaint);
      canvas.drawRect(panel, borderPaint);
      canvas.drawLine(
        Offset(panel.left + panel.width * 0.22, panel.top + panel.height * 0.2),
        Offset(panel.left + panel.width * 0.38, panel.top + panel.height * 0.44),
        reflectionPaint,
      );
    }

    if (shape == GlassPanelShape.straight && doorCount == 2) {
      final dividerX = left + maxWidth / 2;
      canvas.drawLine(Offset(dividerX, top), Offset(dividerX, top + maxHeight), borderPaint);
    }

    final center = Offset(size.width / 2, size.height / 2);
    final motionPaint = Paint()
      ..color = Colors.indigo.shade700
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    if (operation == GlassOperation.sliding) {
      final y = size.height - 18;
      canvas.drawLine(Offset(center.dx - 28, y), Offset(center.dx + 28, y), motionPaint);
      canvas.drawLine(Offset(center.dx - 28, y), Offset(center.dx - 20, y - 6), motionPaint);
      canvas.drawLine(Offset(center.dx - 28, y), Offset(center.dx - 20, y + 6), motionPaint);
      canvas.drawLine(Offset(center.dx + 28, y), Offset(center.dx + 20, y - 6), motionPaint);
      canvas.drawLine(Offset(center.dx + 28, y), Offset(center.dx + 20, y + 6), motionPaint);
    } else {
      final arcRect = Rect.fromCenter(center: center, width: 44, height: 44);
      canvas.drawArc(arcRect, -1.1, 1.5, false, motionPaint);
      canvas.drawLine(
        Offset(center.dx + 17, center.dy - 17),
        Offset(center.dx + 25, center.dy - 15),
        motionPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlassPanelPainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.operation != operation ||
      oldDelegate.doorCount != doorCount;
}
