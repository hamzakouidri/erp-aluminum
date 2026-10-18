import 'dart:io';
import 'package:database_data/widgets/app_material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:database_data/sql_database.dart';
import 'ai_invoice_service.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class AiScannerScreen extends StatefulWidget {
  final SqlDatabase db;

  const AiScannerScreen({super.key, required this.db});

  @override
  State<AiScannerScreen> createState() => _AiScannerScreenState();
}

class _AiScannerScreenState extends State<AiScannerScreen>
    with SingleTickerProviderStateMixin {
  File? _imageFile;
  bool _isScanning = false;

  // فحص حالة الخطوة الحالية
  int _currentStep =
      0; // 0: التقاط الفاتورة، 1: الفحص بالـ AI، 2: المطابقة التفاعلية والمراجعة

  ExtractedInvoice? _extractedInvoice;
  List<Map<String, dynamic>> _catalogSections = [];
  List<Map<String, dynamic>> _catalogSeries = [];
  List<Map<String, dynamic>> _catalogColors = [];

  // خريطة مطابقة السلعة بقاعدة البيانات: {مؤشر السلعة: معرف القسم المطابق أو "new" أو "ignore"}
  final Map<int, dynamic> _itemMappings = {};

  // لحفظ بيانات المقاطع الجديدة التي سيتم إنشاؤها: {مؤشر السلعة: خريطة خصائص المقطع الجديد}
  final Map<int, Map<String, dynamic>> _newSectionsData = {};

  final ImagePicker _picker = ImagePicker();

  // ── Palette ───────────────────────────────────────────────────────────────
  static const _blue = Color(0xFF2563EB);
  static const _cyan = Color(0xFF0EA5E9);
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFEF4444);
  static const _orange = Color(0xFFF59E0B);

  Color get _text => Theme.of(context).brightness == Brightness.dark
      ? Colors.white70
      : const Color(0xFF1E293B);

  Color get _textDim => Theme.of(context).brightness == Brightness.dark
      ? Colors.white54
      : const Color(0xFF64748B);

  Color get _bg => Theme.of(context).scaffoldBackgroundColor;

  Color get _cardBg => Theme.of(context).cardColor;

  Color get _divider => Theme.of(context).brightness == Brightness.dark
      ? Colors.grey.shade800
      : const Color(0xFFE2E8F0);

  // شريط المسح الضوئي
  late AnimationController _scanController;
  late Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_scanController);

    _loadCatalogAndApiKey();
  }

  Future<void> _loadCatalogAndApiKey() async {
    try {
      final dbClient = await widget.db.db;
      final sections = await dbClient!.query('Sections');
      final series = await dbClient.query('Series');
      final colors = await dbClient.query('Colors');

      setState(() {
        _catalogSections = sections;
        _catalogSeries = series;
        _catalogColors = colors;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  // التقاط صورة من الكاميرا
  Future<void> _captureImage() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (photo != null) {
      setState(() {
        _imageFile = File(photo.path);
        _currentStep = 1;
      });
      _startAiAnalysis();
    }
  }

  // اختيار صورة من الاستوديو
  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
        _currentStep = 1;
      });
      _startAiAnalysis();
    }
  }

  // تشغيل تحليل الذكاء الاصطناعي
  Future<void> _startAiAnalysis() async {
    if (_imageFile == null) return;
    setState(() {
      _isScanning = true;
    });

    try {
      final bytes = await _imageFile!.readAsBytes();
      final invoice = await AiInvoiceService.analyzeInvoice(
        bytes,
        mimeType: _mimeTypeForPath(_imageFile!.path),
        catalogHints: _catalogSections.map((section) {
          return {
            'code': (section['code'] ?? '').toString(),
            'name': (section['name'] ?? '').toString(),
            'color': '',
          };
        }).toList(),
      );

      setState(() {
        _extractedInvoice = invoice;
        _isScanning = false;
        _currentStep = 2;
      });

      _performAutomaticMatching();
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ أثناء معالجة الفاتورة بالـ AI: $e',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: _red,
          ),
        );
      }
    }
  }

  String _mimeTypeForPath(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.heif':
        return 'image/heif';
      default:
        return 'image/jpeg';
    }
  }

  // مطابقة السلع المستخرجة تلقائياً مع الكتالوج المتوفر بقاعدة البيانات
  void _performAutomaticMatching() {
    if (_extractedInvoice == null) return;

    for (int i = 0; i < _extractedInvoice!.items.length; i++) {
      final item = _extractedInvoice!.items[i];
      Map<String, dynamic>? best;
      var bestScore = 0.0;
      for (final section in _catalogSections) {
        final score = _catalogMatchScore(item, section);
        if (score > bestScore) {
          bestScore = score;
          best = section;
        }
      }

      // High precision matches are accepted automatically. We deliberately
      // keep weaker guesses visible for human review instead of losing lines.
      if (best != null && bestScore >= 0.72) {
        _itemMappings[i] = best['id'] as int;
      } else {
        _itemMappings[i] = null;
      }
    }
    setState(() {});
  }

  String _normaliseMatchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
        .trim();
  }

  String _compactCode(String value) => _normaliseMatchText(value)
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('o', '0');

  Set<String> _tokens(String value) => _normaliseMatchText(value)
      .split(' ')
      .where((token) => token.length > 1)
      .toSet();

  double _catalogMatchScore(
    ExtractedInvoiceItem item,
    Map<String, dynamic> section,
  ) {
    final itemCode = _compactCode(item.itemCode);
    final sectionCode = _compactCode((section['code'] ?? '').toString());
    if (itemCode.isNotEmpty && sectionCode.isNotEmpty) {
      if (itemCode == sectionCode) return 1.0;
      if (itemCode.contains(sectionCode) || sectionCode.contains(itemCode)) {
        return 0.88;
      }
    }

    final sourceTokens = _tokens(
      '${item.itemName} ${item.rawDescription} ${item.itemCode}',
    );
    final targetTokens = _tokens(
      '${section['name'] ?? ''} ${section['code'] ?? ''} ${section['type'] ?? ''}',
    );
    if (sourceTokens.isEmpty || targetTokens.isEmpty) return 0.0;
    final intersection = sourceTokens.intersection(targetTokens).length;
    final union = sourceTokens.union(targetTokens).length;
    final jaccard = intersection / union;
    final overlap = intersection /
        (sourceTokens.length < targetTokens.length
            ? sourceTokens.length
            : targetTokens.length);
    // Supplier descriptions usually contain extra words (colour, bar length,
    // packaging). The overlap coefficient still recognises the catalogue name
    // when all its meaningful tokens occur inside that longer description.
    var score = jaccard > overlap * 0.82 ? jaccard : overlap * 0.82;
    if (itemCode.isNotEmpty && sectionCode.isNotEmpty &&
        (itemCode.startsWith(sectionCode) || sectionCode.startsWith(itemCode))) {
      score += 0.35;
    }
    return score.clamp(0.0, 1.0).toDouble();
  }

  int? _colorIdFor(String rawColor) {
    final normalized = _normaliseMatchText(rawColor);
    if (normalized.isEmpty || normalized.contains('غير مذكور')) return null;
    final aliases = normalized.contains('fbm') ||
            normalized.contains('bois') ||
            normalized.contains('خشب')
        ? <String>{'fbm', 'bois', 'خشبي', 'خشب'}
        : _tokens(normalized);
    for (final color in _catalogColors) {
      final colorText = _normaliseMatchText(
        '${color['name'] ?? ''} ${color['code'] ?? ''}',
      );
      if (aliases.any(colorText.contains)) return color['id'] as int?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: Text(
            Localization.translate(
              'فحص الفواتير بالذكاء الاصطناعي',
              Provider.of<AppSettingsProvider>(context).language,
            ),
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          foregroundColor: _text,
          elevation: 0,
        ),
        body: _buildStepContent(),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildCaptureStage();
      case 1:
        return _buildScanningStage();
      case 2:
        return _buildVerificationStage();
      default:
        return _buildCaptureStage();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. مرحلة التقاط صورة الفاتورة (Capture Stage)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildCaptureStage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // إدخال API Key تم إلغاؤه من هنا (متوفر فقط بالإعدادات للمدراء)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.amber.shade900.withOpacity(0.2)
                  : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _orange.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: _orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      Localization.translate(
                        'الذكاء الاصطناعي متاح مجاناً للمعاينة',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  Localization.translate(
                    'سيقوم التطبيق بمحاكاة قراءة فاتورة ألمنيوم حقيقية وعرض الفحص التفاعلي والربط مباشرة لتختبر عمل الميزة بكل سهولة.',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: isDark
                        ? Colors.amber.shade200
                        : Colors.amber.shade900,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // صندوق التقاط الفاتورة
          GestureDetector(
            onTap: _showCaptureSheet,
            child: Container(
              width: double.infinity,
              height: 240,
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _blue.withOpacity(0.3),
                  width: 2,
                  style: BorderStyle.solid,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.document_scanner_rounded,
                    size: 64,
                    color: _blue,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    Localization.translate(
                      'تصوير أو رفع فاتورة الشراء',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _text,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Localization.translate(
                      'اضغط هنا للتصوير بالكاميرا أو اختيار الفاتورة',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: _textDim,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  void _showCaptureSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Localization.translate(
                  'استيراد الفاتورة بالذكاء الاصطناعي',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _blue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.camera_alt_rounded, color: _blue),
                ),
                title: Text(
                  Localization.translate(
                    'التصوير بالكاميرا فوراً',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _captureImage();
                },
              ),
              Divider(),
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _cyan.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.photo_library_rounded, color: _cyan),
                ),
                title: Text(
                  Localization.translate(
                    'اختيار صورة من المعرض',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2. مرحلة المسح الضوئي والانتظار (Scanning Stage)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildScanningStage() {
    return Stack(
      children: [
        // معاينة الصورة في الخلفية
        if (_imageFile != null)
          Positioned.fill(
            child: Opacity(
              opacity: 0.25,
              child: Image.file(_imageFile!, fit: BoxFit.cover),
            ),
          ),
        // أنيميشن المسح
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // حلقة المسح النبضية
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _blue.withValues(alpha: 0.1),
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      color: _blue,
                    ),
                  ),
                  Icon(Icons.auto_awesome_rounded, size: 42, color: _blue),
                ],
              ),
              SizedBox(height: 32),
              Text(
                Localization.translate(
                  'جاري تحليل الفاتورة بالذكاء الاصطناعي...',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _text,
                ),
              ),
              SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'يقوم الذكاء الاصطناعي باستخراج أسماء الموردين، قيم الفواتير، والأكواد التجارية للسلع لمطابقتها تلقائياً.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: _textDim,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        // خط المسح الليزري
        AnimatedBuilder(
          animation: _scanAnimation,
          builder: (context, child) {
            final screenHeight = MediaQuery.of(context).size.height;
            final topPosition = _scanAnimation.value * screenHeight;
            return Positioned(
              top: topPosition,
              left: 0,
              right: 0,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      _blue.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _blue.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3. مرحلة المراجعة الذكية ومطابقة السلع (Verification Stage)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildVerificationStage() {
    if (_extractedInvoice == null) return SizedBox();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── ملخص الفاتورة المستخرجة ──
                _buildExtractedInvoiceHeader(),
                SizedBox(height: 24),

                // ── عنوان السلع ──
                Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: _blue, size: 20),
                    SizedBox(width: 8),
                    Text(
                      Localization.translate(
                        'مطابقة وفحص السلع المستوردة',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _text,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  'التحقق من مطابقة المقاطع الواردة مع كتالوج الألمنيوم المحلي في قاعدة البيانات:',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: _textDim,
                  ),
                ),
                SizedBox(height: 12),

                // ── قائمة السلع والمطابقة ──
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _extractedInvoice!.items.length,
                  itemBuilder: (context, index) {
                    final item = _extractedInvoice!.items[index];
                    return _buildMatchItemCard(item, index);
                  },
                ),
              ],
            ),
          ),
        ),
        // ── أزرار الحفظ والإنهاء ──
        _buildBottomActionBar(),
      ],
    );
  }

  Widget _buildExtractedInvoiceHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.business_rounded, color: _blue, size: 20),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _extractedInvoice!.supplierName,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: _text,
                      ),
                    ),
                    Text(
                      'فاتورة رقم: ${_extractedInvoice!.invoiceNumber}',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: _textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Divider(height: 1, color: _divider),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Localization.translate(
                      'إجمالي الفاتورة المستخرج',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: _textDim,
                    ),
                  ),
                  Text(
                    '${_extractedInvoice!.total.toStringAsFixed(2)} دج',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: _blue,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Localization.translate(
                      'تاريخ الفاتورة',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: _textDim,
                    ),
                  ),
                  Text(
                    _extractedInvoice!.date,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _text,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // كارت مخصص لكل سلعة ومطابقتها
  Widget _buildMatchItemCard(ExtractedInvoiceItem item, int index) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final mapping = _itemMappings[index];

    final isMatched =
        mapping != null && mapping != 'ignore' && mapping != 'new';
    final isNew = mapping == 'new';
    final isIgnored = mapping == 'ignore';
    final isUnresolved = mapping == null;

    Color stateColor = _orange;
    String stateText = Localization.translate('غير مطابقة', lang);
    IconData stateIcon = Icons.warning_amber_rounded;

    if (isMatched) {
      stateColor = _green;
      stateText = Localization.translate('مطابقة تلقائية', lang);
      stateIcon = Icons.check_circle_rounded;
    } else if (isNew) {
      stateColor = _blue;
      stateText = Localization.translate('موافقة لإنشاء جديد', lang);
      stateIcon = Icons.add_circle_rounded;
    } else if (isIgnored) {
      stateColor = _textDim;
      stateText = Localization.translate('تم تجاهل السلعة', lang);
      stateIcon = Icons.block_rounded;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMatched ? _divider : stateColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.itemName,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${Localization.translate('الكود المستخرج:', lang)} ${item.itemCode.isEmpty ? Localization.translate('لا يوجد', lang) : item.itemCode} | '
                      '${Localization.translate('الكمية:', lang)} ${item.quantity} | '
                      '${Localization.translate('السعر:', lang)} ${item.price} ${Localization.translate('دج', lang)}',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: _textDim,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'اللون: ${item.color.isEmpty ? 'غير مذكور' : item.color}'
                      '${item.unit.isEmpty ? '' : ' | الوحدة: ${item.unit}'}'
                      '${item.confidence <= 0 ? '' : ' | دقة القراءة: ${(item.confidence * 100).round()}%'}',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: item.confidence > 0 && item.confidence < 0.65
                            ? _orange
                            : _textDim,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.rawDescription.isNotEmpty &&
                        item.rawDescription != item.itemName)
                      Text(
                        'النص المقروء: ${item.rawDescription}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          color: _textDim,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(stateIcon, color: stateColor, size: 12),
                    SizedBox(width: 4),
                    Text(
                      stateText,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        color: stateColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Divider(height: 1, color: _divider),
          SizedBox(height: 12),
          // عرض المقطع المرتبط
          if (isMatched) ...[_buildMatchedSectionDetails(mapping)],
          if (isNew) ...[_buildNewSectionDetails(index)],
          if (isUnresolved) ...[_buildUnresolvedActions(item, index)],
          if (!isUnresolved) ...[
            // زر للتراجع وإعادة الموازنة
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _itemMappings[index] = null;
                      _newSectionsData.remove(index);
                    });
                  },
                  child: Text(
                    Localization.translate(
                      'تعديل المطابقة',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: _blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // تفاصيل المقطع الذي تم مطابقته بنجاح
  Widget _buildMatchedSectionDetails(int sectionId) {
    final sec = _catalogSections.firstWhere(
      (element) => element['id'] == sectionId,
    );
    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, color: _green, size: 18),
          SizedBox(width: 8),
          Text(
            'مرتبط بالمقطع: ${sec['code']} - ${sec['name']} (${sec['type']})',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: _green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // تفاصيل المقطع الجديد الذي سيتم إنشاؤه
  Widget _buildNewSectionDetails(int itemIndex) {
    final data = _newSectionsData[itemIndex]!;
    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.add_circle_outline_rounded, color: _blue, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'سيتم إنشاؤه كمقطع جديد بكود: ${data['code']} واسم: ${data['name']}',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: _blue,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // خيارات القرار للسلعة غير المطابقة
  Widget _buildUnresolvedActions(ExtractedInvoiceItem item, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الذكاء الاصطناعي لم يجد مقطعاً مطابقاً تماماً في الكتالوج الحالي. ماذا تريد أن تفعل؟',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            color: _text,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () => _showLinkToExistingDialog(item, index),
                icon: Icon(Icons.link_rounded, size: 16),
                label: Text(
                  Localization.translate(
                    'ربط بمقطع موجود',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () => _showCreateAsNewDialog(item, index),
                icon: Icon(Icons.add_rounded, size: 16),
                label: Text(
                  Localization.translate(
                    'إنشاء مقطع جديد',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: _textDim),
              onPressed: () {
                setState(() {
                  _itemMappings[index] = 'ignore';
                });
              },
              icon: Icon(Icons.block_rounded, size: 14),
              label: Text(
                Localization.translate(
                  'تجاهل هذه السلعة',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // نافذة اختيار مقطع موجود مسبقاً لربط السلعة به
  void _showLinkToExistingDialog(ExtractedInvoiceItem item, int itemIndex) {
    final rankedSections = List<Map<String, dynamic>>.from(_catalogSections)
      ..sort(
        (a, b) => _catalogMatchScore(
          item,
          b,
        ).compareTo(_catalogMatchScore(item, a)),
      );
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            Localization.translate(
              'ربط السلعة بمقطع موجود',
              Provider.of<AppSettingsProvider>(context).language,
            ),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: rankedSections.isEmpty
                ? Center(
                    child: Text(
                      Localization.translate(
                        'لا توجد مقاطع بالكتالوج حالياً.',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                  )
                : ListView.builder(
                    itemCount: rankedSections.length,
                    itemBuilder: (context, index) {
                      final sec = rankedSections[index];
                      return ListTile(
                        title: Text(
                          '${sec['code']} - ${sec['name']}',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          'النوع: ${sec['type']}',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
                        ),
                        trailing: Icon(Icons.chevron_left_rounded, size: 18),
                        onTap: () {
                          setState(() {
                            _itemMappings[itemIndex] = sec['id'] as int;
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
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
                style: TextStyle(fontFamily: 'Cairo', color: _textDim),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // نافذة إدخال مقطع جديد بالكامل وتخزينه في الكتالوج
  void _showCreateAsNewDialog(ExtractedInvoiceItem item, int itemIndex) {
    if (_catalogSeries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الرجاء التأكد من وجود "سلسلة" واحدة على الأقل في الكتالوج لكي تنشئ مقطعاً بداخلها.',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: _red,
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final codeCtrl = TextEditingController(
      text: item.itemCode.isEmpty ? "NEW-CODE" : item.itemCode,
    );
    final nameCtrl = TextEditingController(text: item.itemName);
    final thicknessCtrl = TextEditingController(text: '45.0');
    final glassDedCtrl = TextEditingController(text: '28.0');
    final weightCtrl = TextEditingController(text: '1.2');

    int selectedSeriesId = _catalogSeries.first['id'] as int;
    String selectedType = 'frame';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                Localization.translate(
                  'إضافة مقطع جديد للكتالوج المعتمد',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: selectedSeriesId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'السلسلة المرتبطة *',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                          labelStyle: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        items: _catalogSeries
                            .map(
                              (s) => DropdownMenuItem<int>(
                                value: s['id'] as int,
                                child: Text(
                                  s['name'] ?? '',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setDialogState(() => selectedSeriesId = val!),
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: codeCtrl,
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'الكود التجاري (Code) *',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                          labelStyle: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'يرجى إدخال كود المقطع'
                            : null,
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'اسم المقطع (Name) *',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                          labelStyle: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'يرجى إدخال اسم المقطع'
                            : null,
                      ),
                      SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedType,
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'نوع المقطع الهندسي *',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                          labelStyle: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                          ),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'frame',
                            child: Text(
                              Localization.translate(
                                'حلق خارجي (Frame)',
                                Provider.of<AppSettingsProvider>(
                                  context,
                                ).language,
                              ),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'sash',
                            child: Text(
                              Localization.translate(
                                'ضلفة (Sash)',
                                Provider.of<AppSettingsProvider>(
                                  context,
                                ).language,
                              ),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'mullion',
                            child: Text(
                              Localization.translate(
                                'تيار / تقسيم (Mullion)',
                                Provider.of<AppSettingsProvider>(
                                  context,
                                ).language,
                              ),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'parclose',
                            child: Text(
                              Localization.translate(
                                'باغيت زجاج (Parclose)',
                                Provider.of<AppSettingsProvider>(
                                  context,
                                ).language,
                              ),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) =>
                            setDialogState(() => selectedType = val!),
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: thicknessCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'سماكة المقطع / Thickness (mm)',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                          labelStyle: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                          ),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: glassDedCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'خصم الزجاج / Glass Deduction (mm)',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                          labelStyle: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                          ),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 12),
                      TextFormField(
                        controller: weightCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'الوزن التقريبي للمتر (Kg/m)',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                          labelStyle: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                          ),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
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
                    style: TextStyle(fontFamily: 'Cairo', color: _textDim),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _green),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      setState(() {
                        _itemMappings[itemIndex] = 'new';
                        _newSectionsData[itemIndex] = {
                          'series_id': selectedSeriesId,
                          'code': codeCtrl.text.trim(),
                          'name': nameCtrl.text.trim(),
                          'type': selectedType,
                          'thickness':
                              double.tryParse(thicknessCtrl.text) ?? 45.0,
                          'glass_deduction':
                              double.tryParse(glassDedCtrl.text) ?? 28.0,
                          'weight_per_meter':
                              double.tryParse(weightCtrl.text) ?? 1.2,
                        };
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: Text(
                    Localization.translate(
                      'اعتماد وحفظ',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                    style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // شريط الحفظ السفلي المشتمل على المطابقة الكاملة
  Widget _buildBottomActionBar() {
    bool hasUnresolved = _itemMappings.values.any((element) => element == null);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: _cardBg,
        border: Border(top: BorderSide(color: _divider)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasUnresolved ? _textDim : _blue,
                  disabledBackgroundColor: _textDim.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: hasUnresolved ? null : _saveInvoiceAndItems,
                icon: Icon(Icons.cloud_upload_rounded, color: Colors.white),
                label: Text(
                  hasUnresolved
                      ? 'يرجى مطابقة كافة السلع أولاً'
                      : 'حفظ الفاتورة والسلع بقاعدة البيانات',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // حفظ الفاتورة بالكامل، وتحديث الكتالوج بالمواد الجديدة المعتمدة، وتخزين مسار الصورة
  Future<void> _saveInvoiceAndItems() async {
    if (_extractedInvoice == null) return;

    try {
      // 1. حفظ صورة الفاتورة محلياً بشكل دائم
      String? savedImagePath;
      if (_imageFile != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName =
            'invoice_${DateTime.now().millisecondsSinceEpoch}${p.extension(_imageFile!.path)}';
        final savedFile = await _imageFile!.copy(p.join(appDir.path, fileName));
        savedImagePath = savedFile.path;
      }

      // 2. إدخال المقاطع الجديدة التي وافق عليها المستخدم في الكتالوج بقاعدة البيانات
      for (int i = 0; i < _extractedInvoice!.items.length; i++) {
        final mapping = _itemMappings[i];
        if (mapping == 'new') {
          final data = _newSectionsData[i]!;
          final newSectionId = await widget.db.insertSection(
            seriesId: data['series_id'] as int,
            code: data['code'] as String,
            name: data['name'] as String,
            type: data['type'] as String,
            thickness: data['thickness'] as double,
            glassDeduction: data['glass_deduction'] as double,
            weightPerMeter: data['weight_per_meter'] as double,
          );
          // ربط السلعة بالمعرف الجديد مباشرة
          _itemMappings[i] = newSectionId;
        }
      }

      // 3. حفظ الفاتورة الرئيسية (Achat)
      final achatId = await widget.db.insertAchat(
        _extractedInvoice!.invoiceNumber,
        _extractedInvoice!.supplierName,
        _extractedInvoice!.total,
        imagePath: savedImagePath,
      );

      // 4. حفظ سلع الفاتورة المستوردة
      for (int i = 0; i < _extractedInvoice!.items.length; i++) {
        final item = _extractedInvoice!.items[i];
        final mapping = _itemMappings[i];

        if (mapping != 'ignore' && mapping != null) {
          await widget.db.insertAchatItem(
            achatId: achatId,
            itemCode: item.itemCode,
            itemName: item.itemName,
            itemType: 'Sections',
            // AI Scanner specifically handles aluminum sections for now
            itemId: mapping as int,
            colorId: _colorIdFor(item.color),
            quantity: item.quantity,
            price: item.price,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم استيراد وحفظ فاتورة المشتريات ومطابقة السلع بنجاح تام',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(
          context,
          true,
        ); // يرجع لشاشة المشتريات الرئيسية ويعطيه إشعار تحديث
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ أثناء حفظ الفاتورة: $e',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: _red,
          ),
        );
      }
    }
  }
}
