import 'dart:async';
import 'dart:io';

import 'package:database_data/widgets/app_material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_svg/flutter_svg.dart';

import '../sql_database.dart';

import '../services/cloud_sync_service.dart';
import '../services/supabase_workshop_sync_service.dart';

import 'package:database_data/settings/localization.dart';

import 'package:database_data/settings/app_settings.dart';

import 'package:provider/provider.dart';

import '../widgets/section_image.dart';

class AccessoriesScreen extends StatefulWidget {
  final SqlDatabase db;

  const AccessoriesScreen({super.key, required this.db});

  @override
  State<AccessoriesScreen> createState() => _AccessoriesScreenState();
}

class _AccessoriesScreenState extends State<AccessoriesScreen> {
  String _t(String key) => Localization.translate(
    key,
    Provider.of<AppSettingsProvider>(context, listen: false).language,
  );

  String _withoutQualityLabel(String value) {
    return value
        .replaceAll(
          RegExp(
            r'\s*\(\s*(?:جودة\s+(?:رفيعة|قياسية|تجارية)|qualité\s+(?:haute|standard|commerciale)|(?:premium|standard|commercial)\s+quality)\s*\)',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  String? _accessoryImagePath(Map<String, dynamic> item) {
    // 1. الأولوية المطلقة: المسار المربوط والمقيد صراحة بهذا الإكسسوار بعينه
    final savedPath = item['image_path']?.toString().trim() ?? '';
    if (savedPath.isNotEmpty) return savedPath;

    // 2. المطابقة الدقيقة فقط بالرمز التجاري المحدد (Exact Code Match) بدون تخمين بالاسم
    final code = (item['code'] ?? '').toString().trim().toUpperCase();
    if (code.isNotEmpty) {
      if (code == '40127') return 'assets/sections/40127.svg';
      if (code == 'N245') return 'assets/sections/N245.svg';
      if (code == 'N52034') return 'assets/sections/N52034.svg';
    }

    // إذا لم تكن هناك صورة مقيدة صراحة ولا كود دقيق، لا نخمن بالكلمات تجنباً للخطأ
    return null;
  }

  Future<String?> _saveAccessoryImageLocally(XFile pickedFile, String accessoryName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final accDir = Directory(p.join(appDir.path, 'accessories_images'));
      if (!await accDir.exists()) {
        await accDir.create(recursive: true);
      }
      final ext = p.extension(pickedFile.path).isNotEmpty
          ? p.extension(pickedFile.path)
          : '.png';
      final safeName = accessoryName
          .replaceAll(RegExp(r'[^\w\s\.-]'), '_')
          .replaceAll(' ', '_');
      final fileName = 'acc_${DateTime.now().millisecondsSinceEpoch}_$safeName$ext';
      final savedFile = File(p.join(accDir.path, fileName));
      await File(pickedFile.path).copy(savedFile.path);
      return savedFile.path;
    } catch (e) {
      debugPrint('Error saving accessory image locally: $e');
      return pickedFile.path;
    }
  }

  Future<void> _pickAndAssignImageForAccessory(Map<String, dynamic> item) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (pickedFile == null) return;

      final accId = _databaseId(item['id']);
      if (accId == null) return;

      final savedPath = await _saveAccessoryImageLocally(
        pickedFile,
        item['name']?.toString() ?? 'accessory',
      );
      if (savedPath == null) return;

      await widget.db.updateAccessory(accId, {
        'image_path': savedPath,
      });

      await _loadItems();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('تم تحديث صورة الإكسسوار بنجاح.')),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_t('حدث خطأ أثناء تعيين الصورة')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _items = [];

  List<Map<String, dynamic>> _series = [];

  String _searchQuery = '';

  final TextEditingController _searchCtrl = TextEditingController();

  StreamSubscription? _dbSubscription;

  String mapArabicCategoryToFrench(String cat) {
    switch (cat.trim()) {
      case 'البراغي':
      case 'Visse':
        return 'Visse';

      case 'قفل':
      case 'Serrure':
        return 'Serrure';

      case 'قاش':
      case 'Gâche':
        return 'Gâche';

      case 'الطاسو':
      case 'Tasso':
        return 'Tasso';

      case 'إيكار':
      case 'Ekar':
        return 'Ekar';

      case 'مقبض':
      case 'Poignée Fenêtre':
        return 'Poignée Fenêtre';

      case 'Poignée':
        return 'Poignée';

      case 'Poignée TPR':
        return 'Poignée TPR';

      case 'Espagnolette TPR':
        return 'Espagnolette TPR';

      case 'Kit':
      case 'Kits':
        return 'Kit';

      case 'Poignée Porte à Clé':
        return 'Poignée Porte à Clé';

      case 'Poignée Porte Condamnation':
        return 'Poignée Porte Condamnation';

      case 'Canon Condamnation':
        return 'Canon Condamnation';

      case 'فيرو':
      case 'Verrou':
        return 'Verrou';

      case 'مفاصل':
      case 'Paumelles':
        return 'Paumelles';

      case 'إسبانيوليت':
      case 'Espagnolette':
        return 'Espagnolette';

      case 'كانو':
      case 'Canon':
        return 'Canon';

      case 'سيستم أو بي':
      case 'System OB':
        return 'System OB';

      case 'ديمي سيستم أو بي':
      case 'Demi System OB':
        return 'Demi System OB';

      case 'فيرو سنترال':
      case 'Verrou Central':
        return 'Verrou Central';

      case 'Gache simple ouvrant':
      case 'Gâche simple':
        return 'Gâche simple';

      case 'إسبانيوليت كوليسون':
      case 'Esp coll':
      case 'Espagnolette Coulissante':
        return 'Espagnolette Coulissante';

      case 'كوليسون أوفرون':
      case 'Coulissant Ouvrant':
        return 'Coulissant Ouvrant';

      case 'رولات':
      case 'Roullette':
      case 'Roulette':
        return 'Roulette';

      case 'كاش بورت':
      case 'Gache Port':
      case 'Gâche Porte':
        return 'Gâche Porte';

      case 'كاش كوليسون':
      case 'Gache Colissante':
      case 'Gâche Coulissante':
        return 'Gâche Coulissante';

      case 'كريمون':
      case 'Crémon':
      case 'Crémone':
        return 'Crémone';

      case 'اكليبس':
      case 'Clips':
      case 'Eclipse':
        return 'Eclipse';

      case 'بوشون بارك لوز':
      case 'Bouchon Parclose':
        return 'Bouchon Parclose';

      case 'بوشون الكانيفو':
      case 'غطاء الكانيفو':
      case 'Bouchon Caniveau':
      case 'Cache Caniveau':
        return 'Bouchon Caniveau';

      case 'Clam':
      case 'clam':
        return 'Clam';

      case 'Serrure Condamnation':
      case 'serrure condamnation':
        return 'Serrure Condamnation';

      case 'Intramatique':
      case 'intramatique':
        return 'Intramatique';

      case 'أوكتو':
      case 'octo':
        return 'octo';

      case 'لوجتو':
      case 'Logteau':
        return 'Logteau';

      case 'أخرى':
      case 'Autre':
        return 'Autre';

      default:
        return cat;
    }
  }

  /// All category comparisons use the catalogue's canonical French value.
  /// Older databases can still contain Arabic or legacy spellings, so the
  /// value must be normalized before deciding which accessory controls show.
  bool _isScrewCategory(String category) =>
      mapArabicCategoryToFrench(category) == 'Visse';

  bool _isGacheCategory(String category) {
    final normalized = mapArabicCategoryToFrench(category);
    return normalized == 'Gâche' ||
        normalized == 'Gâche simple' ||
        normalized == 'Gâche Porte' ||
        normalized == 'Gâche Coulissante';
  }

  bool _databaseFlag(dynamic value) =>
      value == true || value == 1 || value?.toString().trim() == '1';

  int? _databaseId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  @override
  void initState() {
    super.initState();

    _loadItems();

    _dbSubscription = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        _loadItems();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();

    _dbSubscription?.cancel();

    super.dispose();
  }

  Future<void> _loadItems() async {
    final items = await widget.db.readAccessories();

    final dbInstance = await widget.db.db;

    final series = await dbInstance!.rawQuery('''

      SELECT s.*, p.name as profile_name, p.type as material_type 

      FROM Series s 

      LEFT JOIN Profile p ON s.profile_id = p.id

    ''');

    if (!mounted) return;

    setState(() {
      _items = items;

      _series = series;
    });
  }

  void _showAddDialog() {
    bool isSaving = false;
    final nameCtrl = TextEditingController();

    final screwCountCtrl = TextEditingController(text: '0');

    bool isAluminiumSelected = true;

    bool isPvcSelected = false;

    final selectedSeriesIds = <int>{};

    String scope = 'Global';

    bool isMoteurScrew = false;

    bool isCaissonScrew = false;

    bool isBatmoScrew = false;

    bool isBouchonBatmoScrew = false;

    bool isRenfortScrew = false;

    bool isManivelleScrew = false;

    bool isGacheSimple = false;

    bool isGacheDouble = false;

    bool isGachePorte = false;

    bool isLockClef = false;

    bool isLockCondamnation = false;

    bool isAssemblyScrew = false;

    bool isAccessoryScrew = false;

    bool isInstallationScrew = false;

    bool isKitScrew = false;

    String accessoryCategory = 'Poignée Fenêtre';

    final List<String> categories = [
      'Ekar',

      'Poignée Fenêtre',

      'Poignée',

      'Poignée TPR',

      'Poignée Porte à Clé',

      'Poignée Porte Condamnation',

      'Verrou',

      'Paumelles',

      'Espagnolette',

      'Espagnolette TPR',

      'Gâche',

      'Serrure',

      'Serrure Condamnation',

      'Canon',

      'Canon Condamnation',

      'Tasso',
      'Visse',

      'System OB',

      'Demi System OB',

      'Verrou Central',

      'Gâche simple',

      'Espagnolette Coulissante',

      'Coulissant Ouvrant',

      'Roulette',

      'Gâche Porte',

      'Gâche Coulissante',

      'Crémone',

      'Eclipse',

      'Bouchon Parclose',

      'Bouchon Caniveau',

      'Clam',

      'Intramatique',

      'Kit',

      'octo',

      'Logteau',

      'Autre',
    ];

    String quality = 'جودة قياسية';

    String screwUsage = 'التجميع';

    String? selectedImagePath;

    final List<String> qualities = ['جودة رفيعة', 'جودة قياسية', 'جودة تجارية'];

    showDialog(
      context: context,
      barrierDismissible: false,

      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => PopScope(
          canPop: !isSaving,
          child: AlertDialog(
            title: Text(
              Localization.translate(
                'إضافة أكسسوار جديد',

                Provider.of<AppSettingsProvider>(context).language,
              ),

              style: const TextStyle(fontWeight: FontWeight.bold),
            ),

            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,

                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),

              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,

                  children: [
                    TextField(
                      controller: nameCtrl,

                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'اسم الأكسسوار (مثال: مقبض إيطالي)',

                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    DropdownButtonFormField<String>(
                      isExpanded: true,

                      initialValue: accessoryCategory,

                      items: categories.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,

                          child: Text(
                            Localization.translate(
                              value,
                              Provider.of<AppSettingsProvider>(
                                context,
                              ).language,
                            ),
                          ),
                        );
                      }).toList(),

                      onChanged: (newValue) {
                        setStateDialog(() {
                          accessoryCategory = newValue!;
                        });
                      },

                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'تصنيف الإكسسوار (النوع)',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    if (!_isScrewCategory(accessoryCategory)) ...[
                      TextField(
                        controller: screwCountCtrl,

                        keyboardType: TextInputType.number,

                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'عدد البراغي المستخدمة',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),
                    ],

                    DropdownButtonFormField<String>(
                      isExpanded: true,

                      initialValue: quality,

                      items: qualities.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,

                          child: Text(
                            Localization.translate(
                              value,
                              Provider.of<AppSettingsProvider>(
                                context,
                              ).language,
                            ),
                          ),
                        );
                      }).toList(),

                      onChanged: (newValue) {
                        setStateDialog(() {
                          quality = newValue!;
                        });
                      },

                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'الجودة (النوعية)',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                    ),

                    if (_isScrewCategory(accessoryCategory)) ...[
                      const SizedBox(height: 10),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            _t('استخدام البراغي:'),

                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),

                          CheckboxListTile(
                            title: Text(_t('براغي المحرك')),

                            value: isMoteurScrew,

                            onChanged: (v) => setStateDialog(
                              () => isMoteurScrew = v ?? false,
                            ),
                          ),

                          CheckboxListTile(
                            title: Text(_t('براغي الصندوق')),

                            value: isCaissonScrew,

                            onChanged: (v) => setStateDialog(
                              () => isCaissonScrew = v ?? false,
                            ),
                          ),

                          CheckboxListTile(
                            title: Text(_t('براغي الباتمو')),

                            value: isBatmoScrew,

                            onChanged: (v) =>
                                setStateDialog(() => isBatmoScrew = v ?? false),
                          ),

                          CheckboxListTile(
                            title: Text(_t('براغي بوشون باتمو')),

                            value: isBouchonBatmoScrew,

                            onChanged: (v) => setStateDialog(
                              () => isBouchonBatmoScrew = v ?? false,
                            ),
                          ),

                          CheckboxListTile(
                            title: Text(_t('براغي حديد الدعم (Renfort)')),

                            value: isRenfortScrew,

                            onChanged: (v) => setStateDialog(
                              () => isRenfortScrew = v ?? false,
                            ),
                          ),

                          CheckboxListTile(
                            title: Text(_t('براغي المانيفال')),

                            value: isManivelleScrew,

                            onChanged: (v) => setStateDialog(
                              () => isManivelleScrew = v ?? false,
                            ),
                          ),

                          CheckboxListTile(
                            title: Text(_t('براغي التجميع')),

                            value: isAssemblyScrew,

                            onChanged: (v) => setStateDialog(
                              () => isAssemblyScrew = v ?? false,
                            ),
                          ),

                          CheckboxListTile(
                            title: Text(_t('براغي الإكسسوارات')),

                            value: isAccessoryScrew,

                            onChanged: (v) => setStateDialog(
                              () => isAccessoryScrew = v ?? false,
                            ),
                          ),

                          CheckboxListTile(
                            title: Text(_t('براغي التركيب')),

                            value: isInstallationScrew,

                            onChanged: (v) => setStateDialog(
                              () => isInstallationScrew = v ?? false,
                            ),
                          ),

                          CheckboxListTile(
                            title: Text(_t('براغي الكيت')),

                            value: isKitScrew,

                            onChanged: (v) =>
                                setStateDialog(() => isKitScrew = v ?? false),
                          ),
                        ],
                      ),
                    ],

                    // Gache type checkboxes (only shown when category is Gache)
                    Builder(
                      builder: (context) {
                        final isGacheCategory = _isGacheCategory(
                          accessoryCategory,
                        );

                        if (!isGacheCategory) return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            const SizedBox(height: 8),

                            Text(
                              _t('نوع اللاش:'),

                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),

                            CheckboxListTile(
                              title: Text(_t('Gache Simple Ouvrant')),

                              value: isGacheSimple,

                              onChanged: (v) => setStateDialog(
                                () => isGacheSimple = v ?? false,
                              ),
                            ),

                            CheckboxListTile(
                              title: Text(_t('Gache Double Ouvrant')),

                              value: isGacheDouble,

                              onChanged: (v) => setStateDialog(
                                () => isGacheDouble = v ?? false,
                              ),
                            ),

                            CheckboxListTile(
                              title: Text(_t('Gache Porte')),

                              value: isGachePorte,

                              onChanged: (v) => setStateDialog(
                                () => isGachePorte = v ?? false,
                              ),
                            ),

                            const SizedBox(height: 8),

                            Text(
                              _t('نوع القفل:'),

                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),

                            CheckboxListTile(
                              title: Text(_t('قفل بمفتاح (Clef)')),

                              value: isLockClef,

                              onChanged: (v) =>
                                  setStateDialog(() => isLockClef = v ?? false),
                            ),

                            CheckboxListTile(
                              title: Text(_t('قفل Condamnation')),

                              value: isLockCondamnation,

                              onChanged: (v) => setStateDialog(
                                () => isLockCondamnation = v ?? false,
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 10),

                    const SizedBox(height: 10),

                    const Align(
                      alignment: Alignment.centerLeft,

                      child: Text(
                        'نوع المادة (Material Type):',

                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),

                    Row(
                      children: [
                        Checkbox(
                          value: isAluminiumSelected,

                          onChanged: (val) {
                            setStateDialog(() {
                              isAluminiumSelected = val ?? false;

                              if (!isAluminiumSelected && !isPvcSelected) {
                                isPvcSelected = true;
                              }
                            });
                          },
                        ),

                        const Text('Alu'),

                        const SizedBox(width: 8),

                        Checkbox(
                          value: isPvcSelected,

                          onChanged: (val) {
                            setStateDialog(() {
                              isPvcSelected = val ?? false;

                              if (!isAluminiumSelected && !isPvcSelected) {
                                isAluminiumSelected = true;
                              }
                            });
                          },
                        ),

                        const Text('PVC'),
                      ],
                    ),

                    const SizedBox(height: 10),

                    DropdownButtonFormField<String>(
                      initialValue: scope,

                      items: ['Global', 'Unique'].map((String value) {
                        String translatedValue = value == 'Global'
                            ? Localization.translate(
                                "Global",

                                Provider.of<AppSettingsProvider>(
                                  context,
                                ).language,
                              )
                            : Localization.translate(
                                "Unique (Per Series)",

                                Provider.of<AppSettingsProvider>(
                                  context,
                                ).language,
                              );

                        return DropdownMenuItem<String>(
                          value: value,

                          child: Text(translatedValue),
                        );
                      }).toList(),

                      onChanged: (newValue) {
                        setStateDialog(() {
                          scope = newValue!;
                        });
                      },

                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'Scope',

                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                    ),

                    if (scope == 'Unique')
                      Builder(
                        builder: (context) {
                          final filteredSeries = _series.where((s) {
                            final mat = s['material_type']?.toString() ?? '';

                            if (isAluminiumSelected && mat == 'Aluminium')
                              return true;

                            if (isPvcSelected && mat == 'PVC') return true;

                            // fallback: if material_type missing show all

                            if (mat.isEmpty) return true;

                            return false;
                          }).toList();

                          return Padding(
                            padding: const EdgeInsets.only(top: 10),

                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [
                                Text(
                                  Localization.translate(
                                    'اختر السلاسل المسموح لها:',

                                    Provider.of<AppSettingsProvider>(
                                      context,
                                    ).language,
                                  ),

                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(height: 5),

                                Column(
                                  children: filteredSeries.map((s) {
                                    final sId =
                                        int.tryParse(s['id'].toString()) ?? -1;

                                    if (sId == -1)
                                      return const SizedBox.shrink();

                                    return CheckboxListTile(
                                      title: Text(
                                        "${s['profile_name'] ?? ''} - ${s['name']}",
                                      ),

                                      value: selectedSeriesIds.contains(sId),

                                      onChanged: (bool? checked) {
                                        setStateDialog(() {
                                          if (checked == true) {
                                            selectedSeriesIds.add(sId);
                                          } else {
                                            selectedSeriesIds.remove(sId);
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final pickedFile = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                        );
                        if (pickedFile != null) {
                          setStateDialog(() {
                            selectedImagePath = pickedFile.path;
                          });
                        }
                      },
                      icon: const Icon(Icons.add_photo_alternate_rounded),
                      label: Text(
                        selectedImagePath == null
                            ? _t('إضافة صورة للإكسسوار (اختياري)')
                            : _t('تغيير صورة الإكسسوار'),
                      ),
                    ),
                    if (selectedImagePath != null) ...[
                      const SizedBox(height: 10),
                      Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Container(
                            height: 110,
                            width: 110,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200, width: 2),
                              color: Colors.grey.shade50,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: selectedImagePath!.toLowerCase().endsWith('.svg')
                                ? SvgPicture.file(
                                    File(selectedImagePath!),
                                    fit: BoxFit.contain,
                                  )
                                : Image.file(
                                    File(selectedImagePath!),
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          IconButton(
                            icon: const CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.red,
                              child: Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                            onPressed: () {
                              setStateDialog(() {
                                selectedImagePath = null;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),

                child: Text(
                  Localization.translate(
                    'إلغاء',

                    Provider.of<AppSettingsProvider>(context).language,
                  ),

                  style: const TextStyle(color: Colors.grey),
                ),
              ),

              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),

                onPressed: isSaving
                    ? null
                    : () async {
                        if (isSaving) return;
                        if (scope == 'Unique' && selectedSeriesIds.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _t(
                                  'الرجاء اختيار سلسلة واحدة على الأقل عند اختيار نطاق خاص بالسلسلة!',
                                ),
                              ),

                              backgroundColor: Colors.red,
                            ),
                          );

                          return;
                        }

                        final trimmedName = nameCtrl.text.trim();
                        if (trimmedName.isNotEmpty) {
                          setStateDialog(() => isSaving = true);
                          String finalName = "$trimmedName ($quality)";

                          String finalType = _isScrewCategory(accessoryCategory)
                              ? "$accessoryCategory|$quality|$screwUsage"
                              : "$accessoryCategory|$quality";

                          try {
                            String finalMaterialType = 'Aluminium';

                            if (isAluminiumSelected && isPvcSelected) {
                              finalMaterialType = 'Both';
                            } else if (isPvcSelected) {
                              finalMaterialType = 'PVC';
                            }

                            final seriesIdsStr =
                                (scope == 'Unique' &&
                                    selectedSeriesIds.isNotEmpty)
                                ? ',${selectedSeriesIds.join(',')},'
                                : null;

                            final seriesIdVal =
                                (scope == 'Unique' &&
                                    selectedSeriesIds.isNotEmpty)
                                ? selectedSeriesIds.first
                                : null;

                            await widget.db.insertAccessory({
                              'name': finalName,

                              'material_type': finalMaterialType,

                              'scope': scope,

                              'series_id': seriesIdVal,

                              'series_ids': seriesIdsStr,

                              'type': finalType,

                              'price': 0.0,

                              'screw_count': _isScrewCategory(accessoryCategory)
                                  ? 0
                                  : (int.tryParse(screwCountCtrl.text) ?? 0),

                              'is_moteur_screw':
                                  _isScrewCategory(accessoryCategory) &&
                                      isMoteurScrew
                                  ? 1
                                  : 0,

                              'is_caisson_screw':
                                  _isScrewCategory(accessoryCategory) &&
                                      isCaissonScrew
                                  ? 1
                                  : 0,

                              'is_batmo_screw':
                                  _isScrewCategory(accessoryCategory) &&
                                      isBatmoScrew
                                  ? 1
                                  : 0,

                              'is_bouchon_batmo_screw':
                                  _isScrewCategory(accessoryCategory) &&
                                      isBouchonBatmoScrew
                                  ? 1
                                  : 0,

                              'is_renfort_screw':
                                  _isScrewCategory(accessoryCategory) &&
                                      isRenfortScrew
                                  ? 1
                                  : 0,

                              'is_manivelle_screw':
                                  _isScrewCategory(accessoryCategory) &&
                                      isManivelleScrew
                                  ? 1
                                  : 0,

                              'is_gache_simple':
                                  (_isGacheCategory(accessoryCategory) &&
                                      (accessoryCategory == 'Gâche simple' ||
                                          isGacheSimple))
                                  ? 1
                                  : 0,

                              'is_gache_double':
                                  _isGacheCategory(accessoryCategory) &&
                                      isGacheDouble
                                  ? 1
                                  : 0,

                              'is_gache_porte':
                                  _isGacheCategory(accessoryCategory) &&
                                      isGachePorte
                                  ? 1
                                  : 0,

                              'is_lock_clef':
                                  _isGacheCategory(accessoryCategory) &&
                                      isLockClef
                                  ? 1
                                  : 0,

                              'is_lock_condamnation':
                                  _isGacheCategory(accessoryCategory) &&
                                      isLockCondamnation
                                  ? 1
                                  : 0,

                              'is_assembly_screw':
                                  _isScrewCategory(accessoryCategory) &&
                                      isAssemblyScrew
                                  ? 1
                                  : 0,

                              'is_accessory_screw':
                                  _isScrewCategory(accessoryCategory) &&
                                      isAccessoryScrew
                                  ? 1
                                  : 0,

                              'is_installation_screw':
                                  _isScrewCategory(accessoryCategory) &&
                                      isInstallationScrew
                                  ? 1
                                  : 0,

                              'is_kit_screw':
                                  _isScrewCategory(accessoryCategory) &&
                                      isKitScrew
                                  ? 1
                                  : 0,
                              if (selectedImagePath != null &&
                                  selectedImagePath!.isNotEmpty)
                                'image_path': await _saveAccessoryImageLocally(
                                  XFile(selectedImagePath!),
                                  finalName,
                                ),
                            });

                            // The catalogue notification refreshes the list once.
                            if (context.mounted) Navigator.pop(context);
                          } catch (e) {
                            if (context.mounted) {
                              setStateDialog(() => isSaving = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${_t('حدث خطأ في قاعدة البيانات')}: $e',
                                  ),
                                ),
                              );
                            }
                          }
                        }
                      },

                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        Localization.translate(
                          'حفظ',

                          Provider.of<AppSettingsProvider>(context).language,
                        ),

                        style: const TextStyle(color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item) {
    final nameCtrl = TextEditingController(
      text: item['name'].toString().split(' (')[0],
    );

    final screwCountCtrl = TextEditingController(
      text: (item['screw_count'] ?? 0).toString(),
    );

    String materialType = item['material_type']?.toString() ?? 'Aluminium';

    bool isAluminiumSelected =
        materialType == 'Aluminium' || materialType == 'Both';

    bool isPvcSelected = materialType == 'PVC' || materialType == 'Both';

    final idsStr = item['series_ids']?.toString() ?? '';

    final selectedSeriesIds = idsStr
        .split(',')
        .map((s) => int.tryParse(s))
        .where((id) => id != null)
        .cast<int>()
        .toSet();

    if (item['series_id'] != null) {
      final parsedId = int.tryParse(item['series_id'].toString());

      if (parsedId != null) {
        selectedSeriesIds.add(parsedId);
      }
    }

    String scope = item['scope']?.toString() ?? 'Global';

    if (scope != 'Global' && scope != 'Unique') {
      scope = 'Global';
    }

    bool isMoteurScrew = _databaseFlag(item['is_moteur_screw']);

    bool isCaissonScrew = _databaseFlag(item['is_caisson_screw']);

    bool isBatmoScrew = _databaseFlag(item['is_batmo_screw']);

    bool isBouchonBatmoScrew = _databaseFlag(item['is_bouchon_batmo_screw']);

    bool isRenfortScrew = _databaseFlag(item['is_renfort_screw']);

    bool isManivelleScrew = _databaseFlag(item['is_manivelle_screw']);

    bool isGacheSimple = _databaseFlag(item['is_gache_simple']);

    bool isGacheDouble = _databaseFlag(item['is_gache_double']);

    bool isGachePorte = _databaseFlag(item['is_gache_porte']);

    bool isLockClef = _databaseFlag(item['is_lock_clef']);

    bool isLockCondamnation = _databaseFlag(item['is_lock_condamnation']);

    bool isAssemblyScrew = _databaseFlag(item['is_assembly_screw']);

    bool isAccessoryScrew = _databaseFlag(item['is_accessory_screw']);

    bool isInstallationScrew = _databaseFlag(item['is_installation_screw']);

    bool isKitScrew = _databaseFlag(item['is_kit_screw']);

    // Decode Type and Quality

    String accessoryCategory = 'Autre';

    String quality = 'جودة قياسية';

    String screwUsage = 'التجميع';

    final List<String> screwUsages = [
      'التجميع',

      'تجميع الصندوق',

      'إكسسوارات',

      'حديد الدعم',

      'التثبيت',

      'كيت الستار',

      'الباتمو',
    ];

    String dbType = item['type']?.toString() ?? '';

    final List<String> categories = [
      'Ekar',

      'Poignée Fenêtre',

      'Poignée',

      'Poignée TPR',

      'Poignée Porte à Clé',

      'Poignée Porte Condamnation',

      'Verrou',

      'Paumelles',

      'Espagnolette',

      'Espagnolette TPR',

      'Gâche',

      'Serrure',

      'Serrure Condamnation',

      'Canon',

      'Canon Condamnation',

      'Tasso',

      'Visse',

      'System OB',

      'Demi System OB',

      'Verrou Central',

      'Gâche simple',

      'Espagnolette Coulissante',

      'Coulissant Ouvrant',

      'Roulette',

      'Gâche Porte',

      'Gâche Coulissante',

      'Crémone',

      'Eclipse',

      'Bouchon Parclose',

      'Bouchon Caniveau',

      'Clam',

      'Intramatique',

      'Kit',

      'octo',

      'Logteau',

      'Autre',
    ];

    String? selectedImagePath = item['image_path']?.toString().trim();
    if (selectedImagePath != null && selectedImagePath.isEmpty) {
      selectedImagePath = null;
    }

    final List<String> qualities = ['جودة رفيعة', 'جودة قياسية', 'جودة تجارية'];

    if (dbType.contains('|')) {
      var parts = dbType.split('|');

      if (parts.isNotEmpty) {
        final cat = mapArabicCategoryToFrench(parts[0].trim());

        if (cat.isNotEmpty) {
          if (!categories.contains(cat)) {
            categories.insert(
              categories.length - 1,
              cat,
            ); // insert before 'Autre'
          }

          accessoryCategory = cat;
        }
      }

      if (parts.length > 1) {
        final qual = parts[1].trim();

        if (qual.isNotEmpty) {
          if (!qualities.contains(qual)) {
            qualities.add(qual);
          }

          quality = qual;
        }
      }

      if (parts.length > 2) {
        final usage = parts[2].trim();

        if (usage.isNotEmpty) {
          if (!screwUsages.contains(usage)) {
            screwUsages.add(usage);
          }

          screwUsage = usage;
        }
      }
    } else {
      final dbTypeTrimmed = mapArabicCategoryToFrench(dbType.trim());

      if (dbTypeTrimmed.isNotEmpty) {
        if (!categories.contains(dbTypeTrimmed)) {
          categories.insert(categories.length - 1, dbTypeTrimmed);
        }

        accessoryCategory = dbTypeTrimmed;
      }
    }

    showDialog(
      context: context,

      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate(
              'تعديل',

              Provider.of<AppSettingsProvider>(context).language,
            ),

            style: const TextStyle(fontWeight: FontWeight.bold),
          ),

          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,

              children: [
                TextField(
                  controller: nameCtrl,

                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'اسم الأكسسوار',

                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  isExpanded: true,

                  initialValue: accessoryCategory,

                  items: categories.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,

                      child: Text(
                        Localization.translate(
                          value,
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                    );
                  }).toList(),

                  onChanged: (newValue) {
                    setStateDialog(() {
                      accessoryCategory = newValue!;
                    });
                  },

                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'تصنيف الإكسسوار (النوع)',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                if (!_isScrewCategory(accessoryCategory)) ...[
                  TextField(
                    controller: screwCountCtrl,

                    keyboardType: TextInputType.number,

                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'عدد البراغي المستخدمة',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                ],

                DropdownButtonFormField<String>(
                  isExpanded: true,

                  initialValue: quality,

                  items: qualities.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,

                      child: Text(
                        Localization.translate(
                          value,
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                    );
                  }).toList(),

                  onChanged: (newValue) {
                    setStateDialog(() {
                      quality = newValue!;
                    });
                  },

                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'الجودة (النوعية)',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),

                if (_isScrewCategory(accessoryCategory)) ...[
                  const SizedBox(height: 10),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        _t('استخدام البراغي:'),

                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),

                      CheckboxListTile(
                        title: Text(_t('براغي المحرك')),

                        value: isMoteurScrew,

                        onChanged: (v) =>
                            setStateDialog(() => isMoteurScrew = v ?? false),
                      ),

                      CheckboxListTile(
                        title: Text(_t('براغي الصندوق')),

                        value: isCaissonScrew,

                        onChanged: (v) =>
                            setStateDialog(() => isCaissonScrew = v ?? false),
                      ),

                      CheckboxListTile(
                        title: Text(_t('براغي الباتمو')),

                        value: isBatmoScrew,

                        onChanged: (v) =>
                            setStateDialog(() => isBatmoScrew = v ?? false),
                      ),

                      CheckboxListTile(
                        title: Text(_t('براغي بوشون باتمو')),

                        value: isBouchonBatmoScrew,

                        onChanged: (v) => setStateDialog(
                          () => isBouchonBatmoScrew = v ?? false,
                        ),
                      ),

                      CheckboxListTile(
                        title: Text(_t('براغي حديد الدعم (Renfort)')),

                        value: isRenfortScrew,

                        onChanged: (v) =>
                            setStateDialog(() => isRenfortScrew = v ?? false),
                      ),

                      CheckboxListTile(
                        title: Text(_t('براغي المانيفال')),

                        value: isManivelleScrew,

                        onChanged: (v) =>
                            setStateDialog(() => isManivelleScrew = v ?? false),
                      ),

                      CheckboxListTile(
                        title: Text(_t('براغي التجميع')),

                        value: isAssemblyScrew,

                        onChanged: (v) =>
                            setStateDialog(() => isAssemblyScrew = v ?? false),
                      ),

                      CheckboxListTile(
                        title: Text(_t('براغي الإكسسوارات')),

                        value: isAccessoryScrew,

                        onChanged: (v) =>
                            setStateDialog(() => isAccessoryScrew = v ?? false),
                      ),

                      CheckboxListTile(
                        title: Text(_t('براغي التركيب')),

                        value: isInstallationScrew,

                        onChanged: (v) => setStateDialog(
                          () => isInstallationScrew = v ?? false,
                        ),
                      ),

                      CheckboxListTile(
                        title: Text(_t('براغي الكيت')),

                        value: isKitScrew,

                        onChanged: (v) =>
                            setStateDialog(() => isKitScrew = v ?? false),
                      ),
                    ],
                  ),
                ],

                // Gache type checkboxes (only shown when category is Gache)
                Builder(
                  builder: (context) {
                    final isGacheCategory = _isGacheCategory(accessoryCategory);

                    if (!isGacheCategory) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        const SizedBox(height: 8),

                        Text(
                          _t('نوع اللاش:'),

                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),

                        CheckboxListTile(
                          title: Text(_t('Gache Simple Ouvrant')),

                          value: isGacheSimple,

                          onChanged: (v) =>
                              setStateDialog(() => isGacheSimple = v ?? false),
                        ),

                        CheckboxListTile(
                          title: Text(_t('Gache Double Ouvrant')),

                          value: isGacheDouble,

                          onChanged: (v) =>
                              setStateDialog(() => isGacheDouble = v ?? false),
                        ),

                        CheckboxListTile(
                          title: Text(_t('Gache Porte')),

                          value: isGachePorte,

                          onChanged: (v) =>
                              setStateDialog(() => isGachePorte = v ?? false),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          _t('نوع القفل:'),

                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),

                        CheckboxListTile(
                          title: Text(_t('قفل بمفتاح (Clef)')),

                          value: isLockClef,

                          onChanged: (v) =>
                              setStateDialog(() => isLockClef = v ?? false),
                        ),

                        CheckboxListTile(
                          title: Text(_t('قفل Condamnation')),

                          value: isLockCondamnation,

                          onChanged: (v) => setStateDialog(
                            () => isLockCondamnation = v ?? false,
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 10),

                const SizedBox(height: 10),

                const Align(
                  alignment: Alignment.centerLeft,

                  child: Text(
                    'نوع المادة (Material Type):',

                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                Row(
                  children: [
                    Checkbox(
                      value: isAluminiumSelected,

                      onChanged: (val) {
                        setStateDialog(() {
                          isAluminiumSelected = val ?? false;

                          if (!isAluminiumSelected && !isPvcSelected) {
                            isPvcSelected = true;
                          }
                        });
                      },
                    ),

                    const Text('Alu'),

                    const SizedBox(width: 8),

                    Checkbox(
                      value: isPvcSelected,

                      onChanged: (val) {
                        setStateDialog(() {
                          isPvcSelected = val ?? false;

                          if (!isAluminiumSelected && !isPvcSelected) {
                            isAluminiumSelected = true;
                          }
                        });
                      },
                    ),

                    const Text('PVC'),
                  ],
                ),

                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  initialValue: scope,

                  items: ['Global', 'Unique'].map((String value) {
                    String translatedValue = value == 'Global'
                        ? Localization.translate(
                            "Global",

                            Provider.of<AppSettingsProvider>(context).language,
                          )
                        : Localization.translate(
                            "Unique (Per Series)",

                            Provider.of<AppSettingsProvider>(context).language,
                          );

                    return DropdownMenuItem<String>(
                      value: value,

                      child: Text(translatedValue),
                    );
                  }).toList(),

                  onChanged: (newValue) {
                    setStateDialog(() {
                      scope = newValue!;
                    });
                  },

                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'Scope',

                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),

                if (scope == 'Unique')
                  Builder(
                    builder: (context) {
                      final filteredSeries = _series.where((s) {
                        final mat = s['material_type']?.toString() ?? '';

                        if (isAluminiumSelected && mat == 'Aluminium')
                          return true;

                        if (isPvcSelected && mat == 'PVC') return true;

                        // fallback: if material_type missing show all

                        if (mat.isEmpty) return true;

                        return false;
                      }).toList();

                      return Padding(
                        padding: const EdgeInsets.only(top: 10),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              Localization.translate(
                                'اختر السلاسل المسموح لها:',

                                Provider.of<AppSettingsProvider>(
                                  context,
                                ).language,
                              ),

                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 5),

                            Column(
                              children: filteredSeries.map((s) {
                                final sId =
                                    int.tryParse(s['id'].toString()) ?? -1;

                                if (sId == -1) return const SizedBox.shrink();

                                return CheckboxListTile(
                                  title: Text(
                                    "${s['profile_name'] ?? ''} - ${s['name']}",
                                  ),

                                  value: selectedSeriesIds.contains(sId),

                                  onChanged: (bool? checked) {
                                    setStateDialog(() {
                                      if (checked == true) {
                                        selectedSeriesIds.add(sId);
                                      } else {
                                        selectedSeriesIds.remove(sId);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final pickedFile = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 85,
                    );
                    if (pickedFile != null) {
                      setStateDialog(() {
                        selectedImagePath = pickedFile.path;
                      });
                    }
                  },
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: Text(
                    selectedImagePath == null || selectedImagePath!.isEmpty
                        ? _t('إضافة صورة للإكسسوار (اختياري)')
                        : _t('تغيير صورة الإكسسوار'),
                  ),
                ),
                if (selectedImagePath != null && selectedImagePath!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Container(
                        height: 110,
                        width: 110,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200, width: 2),
                          color: Colors.grey.shade50,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Builder(
                          builder: (context) {
                            final path = selectedImagePath!;
                            if (path.toLowerCase().endsWith('.svg')) {
                              if (path.startsWith('assets/')) {
                                return SvgPicture.asset(path, fit: BoxFit.contain);
                              }
                              return SvgPicture.file(File(path), fit: BoxFit.contain);
                            }
                            if (path.startsWith('assets/')) {
                              return Image.asset(path, fit: BoxFit.cover);
                            }
                            return Image.file(File(path), fit: BoxFit.cover);
                          },
                        ),
                      ),
                      IconButton(
                        icon: const CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.red,
                          child: Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                        onPressed: () {
                          setStateDialog(() {
                            selectedImagePath = '';
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),

              child: Text(
                Localization.translate(
                  'إلغاء',

                  Provider.of<AppSettingsProvider>(context).language,
                ),

                style: const TextStyle(color: Colors.grey),
              ),
            ),

            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),

              onPressed: () async {
                if (scope == 'Unique' && selectedSeriesIds.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _t(
                          'الرجاء اختيار سلسلة واحدة على الأقل عند اختيار نطاق خاص بالسلسلة!',
                        ),
                      ),

                      backgroundColor: Colors.red,
                    ),
                  );

                  return;
                }

                final accessoryId = _databaseId(item['id']);
                if (accessoryId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _t('تعذر حفظ الإكسسوار: المعرّف غير صالح.'),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final trimmedName = nameCtrl.text.trim();
                if (trimmedName.isNotEmpty) {
                  String finalName = "$trimmedName ($quality)";

                  String finalType = _isScrewCategory(accessoryCategory)
                      ? "$accessoryCategory|$quality|$screwUsage"
                      : "$accessoryCategory|$quality";

                  try {
                    String finalMaterialType = 'Aluminium';

                    if (isAluminiumSelected && isPvcSelected) {
                      finalMaterialType = 'Both';
                    } else if (isPvcSelected) {
                      finalMaterialType = 'PVC';
                    }

                    final seriesIdsStr =
                        (scope == 'Unique' && selectedSeriesIds.isNotEmpty)
                        ? ',${selectedSeriesIds.join(',')},'
                        : null;

                    final seriesIdVal =
                        (scope == 'Unique' && selectedSeriesIds.isNotEmpty)
                        ? selectedSeriesIds.first
                        : null;

                    final updatedRows = await widget.db.updateAccessory(
                      accessoryId,
                      {
                        'name': finalName,

                        'material_type': finalMaterialType,

                        'scope': scope,

                        'series_id': seriesIdVal,

                        'series_ids': seriesIdsStr,

                        'type': finalType,

                        'screw_count': _isScrewCategory(accessoryCategory)
                            ? 0
                            : (int.tryParse(screwCountCtrl.text) ?? 0),

                        'is_moteur_screw':
                            _isScrewCategory(accessoryCategory) && isMoteurScrew
                            ? 1
                            : 0,

                        'is_caisson_screw':
                            _isScrewCategory(accessoryCategory) &&
                                isCaissonScrew
                            ? 1
                            : 0,

                        'is_batmo_screw':
                            _isScrewCategory(accessoryCategory) && isBatmoScrew
                            ? 1
                            : 0,

                        'is_bouchon_batmo_screw':
                            _isScrewCategory(accessoryCategory) &&
                                isBouchonBatmoScrew
                            ? 1
                            : 0,

                        'is_renfort_screw':
                            _isScrewCategory(accessoryCategory) &&
                                isRenfortScrew
                            ? 1
                            : 0,

                        'is_manivelle_screw':
                            _isScrewCategory(accessoryCategory) &&
                                isManivelleScrew
                            ? 1
                            : 0,

                        'is_gache_simple':
                            (_isGacheCategory(accessoryCategory) &&
                                (accessoryCategory == 'Gâche simple' ||
                                    isGacheSimple))
                            ? 1
                            : 0,

                        'is_gache_double':
                            _isGacheCategory(accessoryCategory) && isGacheDouble
                            ? 1
                            : 0,

                        'is_gache_porte':
                            _isGacheCategory(accessoryCategory) && isGachePorte
                            ? 1
                            : 0,

                        'is_lock_clef':
                            _isGacheCategory(accessoryCategory) && isLockClef
                            ? 1
                            : 0,

                        'is_lock_condamnation':
                            _isGacheCategory(accessoryCategory) &&
                                isLockCondamnation
                            ? 1
                            : 0,

                        'is_assembly_screw':
                            _isScrewCategory(accessoryCategory) &&
                                isAssemblyScrew
                            ? 1
                            : 0,

                        'is_accessory_screw':
                            _isScrewCategory(accessoryCategory) &&
                                isAccessoryScrew
                            ? 1
                            : 0,

                        'is_installation_screw':
                            _isScrewCategory(accessoryCategory) &&
                                isInstallationScrew
                            ? 1
                            : 0,

                        'is_kit_screw':
                            _isScrewCategory(accessoryCategory) && isKitScrew
                            ? 1
                            : 0,
                        if (selectedImagePath != null && selectedImagePath!.isNotEmpty)
                          'image_path': selectedImagePath!.startsWith('assets/')
                              ? selectedImagePath
                              : await _saveAccessoryImageLocally(
                                  XFile(selectedImagePath!),
                                  finalName,
                                )
                        else if (selectedImagePath != null && selectedImagePath!.isEmpty)
                          'image_path': '',
                      },
                    );

                    if (updatedRows == 0) {
                      throw StateError(
                        'لم يتم العثور على الإكسسوار عند الحفظ.',
                      );
                    }

                    await _loadItems();

                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${_t('حدث خطأ في قاعدة البيانات')}: $e',
                          ),
                        ),
                      );
                    }
                  }
                }
              },

              child: Text(
                Localization.translate(
                  'حفظ',

                  Provider.of<AppSettingsProvider>(context).language,
                ),

                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,

      builder: (dialogContext) => AlertDialog(
        title: Text(
          _t('تأكيد الحذف'),

          style: const TextStyle(
            fontWeight: FontWeight.bold,

            color: Colors.red,
          ),
        ),

        content: Text(
          _t(
            'سيتم أرشفة هذا العنصر (إخفاؤه) ولن يتم حذفه نهائياً حفاظاً على سلامة بيانات المخزون والفواتير السابقة المرتبطة به.',
          ),

          style: const TextStyle(fontSize: 14),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),

            child: Text(_t('إلغاء')),
          ),

          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),

            onPressed: () async {
              await widget.db.deleteAccessory(item['id']);

              _loadItems();

              if (context.mounted) Navigator.pop(dialogContext);
            },

            child: Text(
              _t('موافق، قم بالأرشفة'),

              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  double? _parseRuleNumber(String text) {
    var value = text.trim().replaceAll(',', '.').replaceAll('٫', '.');
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      value = value.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    final number = double.tryParse(value);
    return number != null && number.isFinite && number >= 0 ? number : null;
  }

  void _showAccessoryRulesDialog(Map<String, dynamic> item, {bool readOnly = false}) {
    final gacheItems = _items.where((candidate) {
      final text = '${candidate['name'] ?? ''} ${candidate['type'] ?? ''}'
          .toLowerCase();
      return text.contains('gache') ||
          text.contains('gâche') ||
          text.contains('قاش') ||
          text.contains('كاش');
    }).toList();
    final screwItems = _items.where((candidate) {
      final text = '${candidate['name'] ?? ''} ${candidate['type'] ?? ''}'
          .toLowerCase();
      return text.contains('vis') ||
          text.contains('screw') ||
          text.contains('برغ') ||
          text.contains('براغ');
    }).toList();
    int? asId(dynamic value) =>
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    double asDouble(dynamic value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0.0;

    int? gacheId = asId(item['gache_accessory_id']);
    int? screwId = asId(item['screw_accessory_id']);
    final gacheCountCtrl = TextEditingController(
      text: (item['gache_count'] ?? 0).toString(),
    );
    final deductionCtrl = TextEditingController(
      text: asDouble(item['triangle_deduction_mm']).toString(),
    );
    final triangleQtyCtrl = TextEditingController(
      text: (item['triangle_quantity'] ?? 1).toString(),
    );
    final trianglePositionCtrl = TextEditingController(
      text: asDouble(item['triangle_position_mm']).toString(),
    );
    var trianglePositionMode =
        item['triangle_position_mode']?.toString().trim().toLowerCase() ??
        'center';
    var triangleLinkMode =
        item['triangle_link_mode']?.toString().trim().toLowerCase() ?? 'none';
    if (!const ['none', 'optional', 'required'].contains(triangleLinkMode)) {
      triangleLinkMode = 'none';
    }
    final accessoryRuleText = '${item['name'] ?? ''} ${item['type'] ?? ''}'
        .toLowerCase();
    final isCremoneRule =
        accessoryRuleText.contains('كريمون') ||
        accessoryRuleText.contains('cremone') ||
        accessoryRuleText.contains('crémone');
    var isDefault = _databaseFlag(item['is_default']);
    var saving = false;
    String? deductionError;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_t('قواعد الإكسسوار')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    item['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_t('الاختيار الافتراضي')),
                    subtitle: Text(_t('يُختار تلقائياً عند توفر هذا النوع')),
                    value: isDefault,
                    onChanged: readOnly
                        ? null
                        : (value) => setDialogState(() => isDefault = value),
                  ),
                  const Divider(),
                  Text(
                    _t('القاش المرتبط بالقفل'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int?>(
                    initialValue:
                        gacheItems.any((row) => asId(row['id']) == gacheId)
                        ? gacheId
                        : null,
                    decoration: InputDecoration(
                      labelText: _t('اختر القاش'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(_t('بدون ربط')),
                      ),
                      ...gacheItems.map(
                        (row) => DropdownMenuItem<int?>(
                          value: asId(row['id']),
                          child: Text(row['name']?.toString() ?? ''),
                        ),
                      ),
                    ],
                    onChanged: readOnly
                        ? null
                        : (value) => setDialogState(() => gacheId = value),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    enabled: !readOnly,
                    controller: gacheCountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _t('عدد القاش لهذا الأكسسوار'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _t('براغي التجميع'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int?>(
                    initialValue:
                        screwItems.any((row) => asId(row['id']) == screwId)
                        ? screwId
                        : null,
                    decoration: InputDecoration(
                      labelText: _t('نوع البرغي'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(_t('بدون ربط')),
                      ),
                      ...screwItems.map(
                        (row) => DropdownMenuItem<int?>(
                          value: asId(row['id']),
                          child: Text(row['name']?.toString() ?? ''),
                        ),
                      ),
                    ],
                    onChanged: readOnly
                        ? null
                        : (value) => setDialogState(() => screwId = value),
                  ),
                  const SizedBox(height: 6),
                  Text(_t('عدد البراغي يؤخذ من حقل عدد البراغي في الأكسسوار')),
                  const SizedBox(height: 14),
                  Text(
                    _t('إعدادات التراينغل'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  if (isCremoneRule)
                    Text(
                      _t(
                        'الكريمون يولّد قطعتين تراينغل تلقائيًا، وموضع المقبض يؤخذ من الرسم.',
                      ),
                    )
                  else ...[
                    DropdownButtonFormField<String>(
                      initialValue: triangleLinkMode,
                      decoration: InputDecoration(
                        labelText: _t('ربط هذا الأكسيسوار بالتراينغل'),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'none',
                          child: Text(_t('بدون تراينغل')),
                        ),
                        DropdownMenuItem(
                          value: 'optional',
                          child: Text(_t('اختياري')),
                        ),
                        DropdownMenuItem(
                          value: 'required',
                          child: Text(_t('حتمي')),
                        ),
                      ],
                      onChanged: readOnly
                          ? null
                          : (value) => setDialogState(
                              () => triangleLinkMode = value ?? 'none',
                            ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      enabled: !readOnly,
                      controller: triangleQtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _t('عدد التراينغل لهذا الأكسيسوار'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: trianglePositionMode == 'offset'
                          ? 'offset'
                          : 'center',
                      decoration: InputDecoration(
                        labelText: _t('موضع التقسيم'),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'center',
                          child: Text(_t('منتصف الضلفة')),
                        ),
                        DropdownMenuItem(
                          value: 'offset',
                          child: Text(_t('مسافة من الأسفل')),
                        ),
                      ],
                      onChanged: readOnly
                          ? null
                          : (value) => setDialogState(
                              () => trianglePositionMode = value ?? 'center',
                            ),
                    ),
                    if (trianglePositionMode == 'offset') ...[
                      const SizedBox(height: 8),
                      TextField(
                        enabled: !readOnly,
                        controller: trianglePositionCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _t('المسافة من أسفل الضلفة (مم)'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    enabled: !readOnly,
                    controller: deductionCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _t('الخصم من طول الظلفة (مم)'),
                      errorText: deductionError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: Text(readOnly ? _t('إغلاق') : _t('إلغاء')),
            ),
            if (!readOnly)
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final id = asId(item['id']);
                      if (id == null) return;
                      final rawDeduction = deductionCtrl.text.trim();
                      final deduction = rawDeduction.isEmpty
                          ? 0.0
                          : _parseRuleNumber(rawDeduction);
                      if (deduction == null) {
                        setDialogState(() => deductionError = _t('أدخل رقمًا صالحًا أكبر من أو يساوي صفرًا'));
                        return;
                      }
                      setDialogState(() {
                        deductionError = null;
                        saving = true;
                      });
                      try {
                        await widget.db.updateAccessory(id, {
                          'gache_accessory_id': gacheId,
                          'gache_count': int.tryParse(gacheCountCtrl.text) ?? 0,
                          'screw_accessory_id': screwId,
                          'triangle_deduction_mm': deduction < 0 ? 0.0 : deduction,
                          'triangle_position_mode': trianglePositionMode,
                          'triangle_position_mm': _parseRuleNumber(trianglePositionCtrl.text) ?? 0.0,
                          'triangle_link_mode': triangleLinkMode,
                          'triangle_quantity': (int.tryParse(triangleQtyCtrl.text) ?? 1).clamp(
                            1,
                            20,
                          ),
                        });
                        await widget.db.setAccessoryDefault(id, isDefault);
                        unawaited(() async {
                          try {
                            final sync = SupabaseWorkshopSyncService();
                            if (sync.isReady || await sync.ensureStarted()) {
                              final config = await widget.db.exportWorkshopCatalogConfiguration();
                              if (config.isNotEmpty) {
                                await sync.saveWorkshopCatalogConfiguration(config);
                              }
                            }
                          } catch (e) {
                            debugPrint('Error uploading workshop catalog configuration: $e');
                          }
                        }());
                        await _loadItems();
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_t('تم حفظ قواعد الأكسسوار بنجاح')),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          deductionError = '${_t('خطأ أثناء الحفظ')}: $e';
                        });
                      }
                    },
              child: Text(_t('حفظ')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isUserAdmin = isAdmin;

    final lang = Provider.of<AppSettingsProvider>(context).language;

    final typeOrder = [
      'Ekar',

      'Poignée Fenêtre',

      'Poignée',

      'Poignée TPR',

      'Poignée Porte à Clé',

      'Poignée Porte Condamnation',

      'Verrou',

      'Paumelles',

      'Espagnolette',

      'Espagnolette TPR',

      'Gâche',

      'Serrure',

      'Serrure Condamnation',

      'Canon',

      'Canon Condamnation',

      'Tasso',

      'Visse',

      'System OB',

      'Demi System OB',

      'Verrou Central',

      'Gâche simple',

      'Espagnolette Coulissante',

      'Coulissant Ouvrant',

      'Roulette',

      'Gâche Porte',

      'Gâche Coulissante',

      'Crémone',

      'Eclipse',

      'Bouchon Parclose',

      'Bouchon Caniveau',

      'Clam',

      'Intramatique',

      'Kit',

      'Autre',
    ];

    String getCategory(Map<String, dynamic> item) {
      final String dbType = item['type']?.toString() ?? '';

      String rawCat = 'Autre';

      if (dbType.contains('|')) {
        rawCat = dbType.split('|')[0].trim();
      } else if (dbType.isNotEmpty) {
        rawCat = dbType.trim();
      }

      return mapArabicCategoryToFrench(rawCat);
    }

    // ---- فلترة البحث ----

    final String q = _searchQuery.toLowerCase().trim();

    final List<Map<String, dynamic>> filteredItems = q.isEmpty
        ? _items
        : _items.where((item) {
            final name = (item['name'] ?? '').toString().toLowerCase();

            final type = (item['type'] ?? '').toString().toLowerCase();

            return name.contains(q) || type.contains(q);
          }).toList();

    Map<String, List<Map<String, dynamic>>> grouped = {};

    for (var cat in typeOrder) {
      grouped[cat] = [];
    }

    for (var item in filteredItems) {
      final cat = getCategory(item);

      if (grouped.containsKey(cat)) {
        grouped[cat]!.add(item);
      } else {
        grouped['Autre']!.add(item);
      }
    }

    final categoryColors = {
      'Visse': Colors.blue.shade800,

      'Serrure': Colors.indigo.shade800,

      'Serrure Condamnation': Colors.indigo.shade600,

      'Gâche': Colors.pink.shade800,

      'Tasso': Colors.teal.shade800,

      'Ekar': Colors.teal.shade600,

      'Poignée Fenêtre': Colors.deepOrange.shade800,

      'Poignée': Colors.deepOrange.shade700,

      'Poignée TPR': Colors.orange.shade800,

      'Poignée Porte à Clé': Colors.red.shade900,

      'Poignée Porte Condamnation': Colors.red.shade700,

      'Canon Condamnation': Colors.cyan.shade900,

      'Verrou': Colors.purple.shade800,

      'Paumelles': Colors.amber.shade900,

      'Espagnolette': Colors.green.shade800,

      'Espagnolette TPR': Colors.teal.shade800,

      'Canon': Colors.cyan.shade800,

      'System OB': Colors.red.shade800,

      'Demi System OB': Colors.pink.shade700,

      'Verrou Central': Colors.blueGrey.shade800,

      'Gâche simple': Colors.orange.shade900,

      'Espagnolette Coulissante': Colors.green.shade900,

      'Coulissant Ouvrant': Colors.deepPurple.shade900,

      'Roulette': Colors.brown.shade800,

      'Gâche Porte': Colors.purple.shade900,

      'Gâche Coulissante': Colors.teal.shade900,

      'Crémone': Colors.indigo.shade900,

      'Eclipse': Colors.cyan.shade900,

      'Bouchon Parclose': Colors.grey.shade600,

      'Bouchon Caniveau': Colors.blueGrey.shade500,

      'Clam': Colors.indigo.shade600,

      'Intramatique': Colors.purple.shade600,

      'Kit': Colors.blueGrey.shade700,

      'Autre': Colors.grey.shade700,
    };

    final categoryIcons = {
      'Visse': Icons.build,

      'Serrure': Icons.lock,

      'Serrure Condamnation': Icons.enhanced_encryption,

      'Gâche': Icons.crop_free,

      'Tasso': Icons.check_box_outline_blank,

      'Ekar': Icons.change_history,

      'Poignée Fenêtre': Icons.touch_app,

      'Poignée': Icons.touch_app,

      'Poignée TPR': Icons.touch_app_outlined,

      'Poignée Porte à Clé': Icons.door_front_door,

      'Poignée Porte Condamnation': Icons.door_back_door,

      'Canon Condamnation': Icons.lock_clock,

      'Verrou': Icons.lock_open,

      'Paumelles': Icons.settings_ethernet,

      'Espagnolette': Icons.vpn_key,

      'Espagnolette TPR': Icons.key,

      'Canon': Icons.lock_outline,

      'System OB': Icons.flip,

      'Demi System OB': Icons.flip_camera_android,

      'Verrou Central': Icons.lock_person,

      'Gâche simple': Icons.border_outer,

      'Espagnolette Coulissante': Icons.vpn_key_outlined,

      'Coulissant Ouvrant': Icons.arrow_forward_ios,

      'Roulette': Icons.circle,

      'Gâche Porte': Icons.border_all,

      'Gâche Coulissante': Icons.border_vertical,

      'Crémone': Icons.view_sidebar,

      'Eclipse': Icons.brightness_3,

      'Bouchon Parclose': Icons.lens,

      'Bouchon Caniveau': Icons.vertical_align_bottom,

      'Clam': Icons.settings_input_component,

      'Intramatique': Icons.rotate_left,

      'Kit': Icons.inventory,

      'Autre': Icons.widgets,
    };

    final sections = <WidgetBuilder>[];

    for (var cat in typeOrder) {
      final items = grouped[cat] ?? [];

      if (items.isEmpty) continue;

      final sectionColor = categoryColors[cat] ?? Colors.blue;

      final sectionIcon = categoryIcons[cat] ?? Icons.widgets;

      sections.add(
        (context) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),

          child: Row(
            children: [
              Icon(sectionIcon, color: sectionColor, size: 22),

              const SizedBox(width: 8),

              Flexible(
                child: Text(
                  Localization.translate(cat, lang),

                  overflow: TextOverflow.ellipsis,

                  style: TextStyle(
                    fontSize: 17,

                    fontWeight: FontWeight.bold,

                    color: sectionColor,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Divider(
                  color: sectionColor.withValues(alpha: 0.4),

                  thickness: 1.5,
                ),
              ),

              const SizedBox(width: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),

                decoration: BoxDecoration(
                  color: sectionColor.withValues(alpha: 0.12),

                  borderRadius: BorderRadius.circular(12),
                ),

                child: Text(
                  '${items.length}',

                  style: TextStyle(
                    color: sectionColor,

                    fontWeight: FontWeight.bold,

                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      for (var item in items) {
        String subtitle = "${item['material_type']} - ";

        subtitle += item['scope'] == 'Global'
            ? Localization.translate(
                "Global",

                Provider.of<AppSettingsProvider>(context).language,
              )
            : Localization.translate(
                "Unique (Per Series)",

                Provider.of<AppSettingsProvider>(context).language,
              );

        sections.add(
          (context) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

            child: ListTile(
              leading: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  GestureDetector(
                    onTap: isUserAdmin
                        ? () => _pickAndAssignImageForAccessory(item)
                        : null,
                    child: SectionImageWidget(
                      imagePath: _accessoryImagePath(item),
                      code: item['code']?.toString(),
                      name: item['name']?.toString(),
                      size: 54,
                      fallbackIcon: sectionIcon,
                    ),
                  ),
                  if (isUserAdmin)
                    GestureDetector(
                      onTap: () => _pickAndAssignImageForAccessory(item),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),

              title: Text(
                _withoutQualityLabel(item['name'].toString()),

                style: TextStyle(
                  fontWeight: FontWeight.bold,

                  color: sectionColor,
                ),
              ),

              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(subtitle),

                  if (item['type'] != null &&
                      item['type'].toString().contains('|'))
                    Builder(
                      builder: (context) {
                        final lang = Provider.of<AppSettingsProvider>(
                          context,
                        ).language;

                        final parts = item['type'].toString().split('|');

                        final typeStr = parts[0].trim();

                        if (typeStr == 'البراغي')
                          return const SizedBox.shrink();

                        String label =
                            Localization.translate('النوع:', lang) +
                            ' ' +
                            Localization.translate(typeStr, lang);

                        return Text(
                          label,

                          style: TextStyle(
                            color: Colors.grey.shade700,

                            fontSize: 13,
                          ),
                        );
                      },
                    ),

                  if (item['screw_count'] != null &&
                      (item['screw_count'] is int
                          ? item['screw_count'] > 0
                          : int.tryParse(item['screw_count'].toString()) !=
                                    null &&
                                int.parse(item['screw_count'].toString()) > 0))
                    Builder(
                      builder: (context) {
                        final lang = Provider.of<AppSettingsProvider>(
                          context,
                        ).language;

                        return Padding(
                          padding: const EdgeInsets.only(top: 2.0),

                          child: Text(
                            Localization.translate(
                                  'عدد البراغي للإكسسوار:',
                                  lang,
                                ) +
                                ' ${item['screw_count']}',

                            style: TextStyle(
                              color: Colors.blue.shade700,

                              fontSize: 13,

                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),

                  Builder(
                    builder: (context) {
                      final lang = Provider.of<AppSettingsProvider>(
                        context,
                      ).language;

                      List<String> usages = [];

                      if (item['is_assembly_screw'] == 1) usages.add('التجميع');

                      if (item['is_caisson_screw'] == 1)
                        usages.add('تجميع الصندوق');

                      if (item['is_accessory_screw'] == 1)
                        usages.add('إكسسوارات');

                      if (item['is_renfort_screw'] == 1)
                        usages.add('حديد الدعم');

                      if (item['is_installation_screw'] == 1)
                        usages.add('التثبيت');

                      if (item['is_kit_screw'] == 1) usages.add('كيت الستار');

                      if (item['is_batmo_screw'] == 1) usages.add('الباتمو');

                      if (item['is_bouchon_batmo_screw'] == 1)
                        usages.add('بوشون باتمو');

                      if (item['is_moteur_screw'] == 1) usages.add('المحرك');

                      if (item['is_manivelle_screw'] == 1)
                        usages.add('المانيفيل');

                      if (usages.isNotEmpty) {
                        final translatedUsages = usages
                            .map((u) => Localization.translate(u, lang))
                            .join(', ');

                        return Padding(
                          padding: const EdgeInsets.only(top: 2.0),

                          child: Text(
                            Localization.translate('الاستخدامات:', lang) +
                                ' ' +
                                translatedUsages,

                            style: TextStyle(
                              color: Colors.orange.shade800,

                              fontSize: 13,

                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),

              trailing: Row(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        IconButton(
                          tooltip: _t('قواعد الإكسسوار'),

                          icon: const Icon(
                            Icons.rule,

                            color: Colors.deepPurple,

                            size: 20,
                          ),

                          onPressed: () => _showAccessoryRulesDialog(
                            item,
                            readOnly: !isUserAdmin,
                          ),
                        ),

                        if (isUserAdmin) ...[
                        IconButton(
                          icon: const Icon(
                            Icons.edit,

                            color: Colors.blue,

                            size: 20,
                          ),

                          onPressed: () => _showEditDialog(item),
                        ),

                        IconButton(
                          icon: const Icon(
                            Icons.delete,

                            color: Colors.red,

                            size: 20,
                          ),

                          onPressed: () async {
                            _showDeleteDialog(item);
                          },
                        ),
                        ],
                      ],
                    ),
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate(
            'الإكسسوارات',

            Provider.of<AppSettingsProvider>(context).language,
          ),
        ),
      ),

      body: Column(
        children: [
          // ---- حقل البحث ----
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),

            child: TextField(
              controller: _searchCtrl,

              onChanged: (val) => setState(() => _searchQuery = val),

              decoration: InputDecoration(
                hintText: Localization.translate(
                  'البحث بالاسم أو النوع...',
                  Provider.of<AppSettingsProvider>(
                    context,
                    listen: false,
                  ).language,
                ),

                prefixIcon: const Icon(Icons.search, color: Colors.blueGrey),

                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),

                        onPressed: () {
                          _searchCtrl.clear();

                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,

                filled: true,

                fillColor: Colors.grey.shade100,

                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),

                  borderSide: BorderSide.none,
                ),

                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),

                  borderSide: BorderSide(color: Colors.blueGrey.shade100),
                ),

                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),

                  borderSide: BorderSide(
                    color: Colors.blue.shade300,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // ---- القائمة ----
          Expanded(
            child: filteredItems.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty
                          ? 'لا توجد بيانات'
                          : 'لا توجد نتائج للبحث عن "$_searchQuery"',

                      style: const TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                  )
                : ListView.builder(
                    itemCount: sections.length,
                    itemBuilder: (context, index) => sections[index](context),
                  ),
          ),
        ],
      ),

      floatingActionButton: !isUserAdmin
          ? null
          : FloatingActionButton(
              onPressed: _showAddDialog,

              child: const Icon(Icons.add),
            ),
    );
  }
}
