import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:database_data/settings/app_settings.dart';

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
    if (payload == null) return;

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
    switch (language) {
      case AppLanguage.french:
        return fr;
      case AppLanguage.english:
        return en;
      case AppLanguage.arabic:
        return ar;
    }
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
                              if (value != null)
                                setState(() => _glassFinish = value);
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
