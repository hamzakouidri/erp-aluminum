import 'package:flutter/material.dart';

// تأكد من مطابقة مسار الموديل الخاص بك
import 'package:database_data/Commande/Systeme/model.dart';

// ============================================================================
// 🟢 1. واجهة المستخدم (UI) باستخدام اسم الكلاس SystemRoling
// ============================================================================
class SystemRoling extends StatefulWidget {
  final WindowModel model;

  const SystemRoling({super.key, required this.model});

  @override
  State<SystemRoling> createState() => _SystemRolingState();
}

class _SystemRolingState extends State<SystemRoling> {
  final TransformationController _transformationController =
      TransformationController();

  // متغيرات التحكم في آلية الستار (محلية داخل الصفحة)
  String _shutterDriveType = 'strap'; // 'motor', 'strap', 'crank'
  String _shutterDriveSide = 'right'; // 'left', 'right'

  @override
  void initState() {
    super.initState();
    // إجبار ظهور الستار برمجياً في هذه الصفحة المخصصة
    widget.model.hasShutter = true;

    // ضبط الكاميرا الافتراضية للـ InteractiveViewer
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _transformationController.value = Matrix4.identity()
        ..scale(0.30)
        ..translate(500.0, 300.0);
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Color _getFrameColorDisplay(FrameColor c) {
    switch (c) {
      case FrameColor.white:
        return Colors.white;
      case FrameColor.brown:
        return const Color(0xFF5D4037);
      case FrameColor.gray:
        return Colors.grey;
      case FrameColor.black:
        return Colors.black87;
      case FrameColor.beige:
        return const Color(0xFFDDC8A0);
    }
  }

  void _showResizeDialog(BuildContext context, {required bool focusWidth}) {
    final widthCtrl = TextEditingController(
      text: widget.model.width.toInt().toString(),
    );
    final heightCtrl = TextEditingController(
      text: widget.model.height.toInt().toString(),
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            'تعديل قياسات الستار',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: widthCtrl,
                  autofocus: focusWidth,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'عرض الستار الإجمالي (mm)',
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: heightCtrl,
                  autofocus: !focusWidth,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'ارتفاع الستار الإجمالي (mm)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () {
                final w = double.tryParse(widthCtrl.text) ?? widget.model.width;
                final h =
                    double.tryParse(heightCtrl.text) ?? widget.model.height;
                if (w >= 100 && h >= 100) widget.model.resizeWindow(w, h);
                Navigator.pop(context);
              },
              child: const Text('تطبيق', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // 🟢 دالة حساب المواد والتكلفة المحدثة (إضافة Lame Finale و Kit)
  void _showCalculationDialog() {
    final double w = widget.model.width;
    final double h = widget.model.height;

    // 1. حسابات التقطيع (Débit)
    double boxSize = 155.0;
    if (h > 1600 && h <= 2400) {
      boxSize = 185.0;
    } else if (h > 2400)
      boxSize = 205.0;

    final double coulisseLength = h;
    final double axeLength = w - 80;

    // شفرات الستار (Lames)
    final double lameLength = w - 60;
    final double lameHeight = 43.0; // يمكن تغييرها لاحقاً لـ 55
    final int lamesCount = ((h - boxSize) / lameHeight).ceil();
    final double totalLamesMeter = (lamesCount * lameLength) / 1000;

    // 🟢 الشفرة النهائية (Lame Finale)
    final double lameFinaleLength = lameLength; // نفس طول الشفرات

    // 2. الأسعار (الأسعار الافتراضية للبرمجة - تستبدل من قاعدة البيانات لاحقاً)
    final double priceBoxPerMeter = 1200.0;
    final double priceCoulissePerMeter = 600.0;
    final double priceLamePerMeter = 450.0;
    final double priceAxePerMeter = 500.0;

    // 🟢 أسعار المكونات الجديدة
    final double priceLameFinalePerMeter =
        650.0; // الشفرة النهائية تكون أغلى قليلاً عادة
    final double priceKit =
        1800.0; // سعر طقم الإكسسوارات (Flasque, embouts, attaches...)

    double drivePrice = 0.0;
    String driveName = '';
    if (_shutterDriveType == 'motor') {
      drivePrice = 8500.0;
      driveName = 'محرك كهربائي';
    } else if (_shutterDriveType == 'strap') {
      drivePrice = 1200.0;
      driveName = 'حزام (Enrouleur + Sangle)';
    } else if (_shutterDriveType == 'crank') {
      drivePrice = 3500.0;
      driveName = 'مانيفر (Manivelle + Treuil)';
    }

    // 3. الحساب الإجمالي
    final double costBox = (w / 1000) * priceBoxPerMeter;
    final double costCoulisses =
        (2 * coulisseLength / 1000) * priceCoulissePerMeter;
    final double costLames = totalLamesMeter * priceLamePerMeter;
    final double costAxe = (axeLength / 1000) * priceAxePerMeter;
    final double costLameFinale =
        (lameFinaleLength / 1000) *
        priceLameFinalePerMeter; // 🟢 تكلفة الشفرة النهائية

    // 🟢 التكلفة الإجمالية المحدثة
    final double totalCost =
        costBox +
        costCoulisses +
        costLames +
        costAxe +
        costLameFinale +
        drivePrice +
        priceKit;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'تفاصيل التقطيع والتكلفة',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const Divider(thickness: 1.5),
              const SizedBox(height: 10),

              // قسم التقطيع
              const Text(
                '✂️ التقطيع (Débit):',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              _buildCalcRow('الصندوق (Coffre)', '1 قطعة', '${w.toInt()} mm'),
              _buildCalcRow(
                'السكك (Coulisses)',
                '2 قطع',
                '${coulisseLength.toInt()} mm',
              ),
              _buildCalcRow(
                'الأنبوب الداخلي (Axe)',
                '1 قطعة',
                '${axeLength.toInt()} mm',
              ),
              _buildCalcRow(
                'الشفرات العادية (Lames)',
                '$lamesCount قطع',
                '${lameLength.toInt()} mm',
              ),
              _buildCalcRow(
                'الشفره النهائية (Lame Finale)',
                '1 قطعة',
                '${lameFinaleLength.toInt()} mm',
              ),
              // 🟢 إضافة للتقطيع
              _buildCalcRow(
                'نظام التحكم',
                _shutterDriveSide == 'right' ? 'يمين' : 'يسار',
                driveName,
              ),
              _buildCalcRow('طقم الملحقات (Kit)', '1 طقم', 'جاهز'),

              // 🟢 إضافة للتقطيع
              const SizedBox(height: 20),

              // قسم التكلفة
              const Text(
                '💰 المواد والتكلفة (Devis):',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              _buildCostRow('هيكل الصندوق', costBox),
              _buildCostRow('السكك', costCoulisses),
              _buildCostRow('شفرات الألمنيوم العادية', costLames),
              _buildCostRow('الشفره النهائية', costLameFinale),
              // 🟢 إضافة للتكلفة
              _buildCostRow('الأنبوب', costAxe),
              _buildCostRow('التحكم ($driveName)', drivePrice),
              _buildCostRow('طقم الملحقات (Kit)', priceKit),

              // 🟢 إضافة للتكلفة
              const Divider(thickness: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'التكلفة الإجمالية:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  Text(
                    '${totalCost.toStringAsFixed(2)} دج',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'حفظ في قاعدة البيانات',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCalcRow(String title, String qty, String dim) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(title, style: const TextStyle(color: Colors.black87)),
          ),
          Expanded(
            flex: 1,
            child: Text(
              qty,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              dim,
              style: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostRow(String title, double cost) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.black54)),
          Text(
            '${cost.toStringAsFixed(2)} دج',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text(
              'تصميم الستار (Volet)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            elevation: 0.5,
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.withValues(alpha: 0.1),
                    foregroundColor: Colors.blue,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.aspect_ratio_rounded, size: 18),
                  label: Text(
                    '${widget.model.width.toInt()} × ${widget.model.height.toInt()} mm',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  onPressed: () => _showResizeDialog(context, focusWidth: true),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // 🟢 شريط التحكم العلوي
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // الألوان
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'لون الستار',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: FrameColor.values.map((color) {
                                  final isSelected =
                                      widget.model.frameColor == color;
                                  return GestureDetector(
                                    onTap: () =>
                                        widget.model.frameColor = color,
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      width: isSelected ? 26 : 22,
                                      height: isSelected ? 26 : 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _getFrameColorDisplay(color),
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.blue
                                              : Colors.grey.shade400,
                                          width: isSelected ? 2.5 : 1.0,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // زر الوجه الداخلي/الخارجي
                        GestureDetector(
                          onTap: () => widget.model.toggleViewMode(),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: widget.model.isInternalView
                                  ? Colors.blue.withValues(alpha: 0.1)
                                  : Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: widget.model.isInternalView
                                    ? Colors.blue
                                    : Colors.orange,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  widget.model.isInternalView
                                      ? Icons.visibility
                                      : Icons.flip_camera_android,
                                  size: 20,
                                  color: widget.model.isInternalView
                                      ? Colors.blue.shade700
                                      : Colors.orange.shade700,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.model.isInternalView
                                      ? 'وجه داخلي'
                                      : 'وجه خارجي',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: widget.model.isInternalView
                                        ? Colors.blue.shade700
                                        : Colors.orange.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),

                    // الأزرار تم فصلها لتفادي الأوفر فلو
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // نوع التحكم
                        Row(
                          children: [
                            Text(
                              'نوع التحكم:',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'strap',
                                      label: Text(
                                        'خيط',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      icon: Icon(Icons.line_weight, size: 16),
                                    ),
                                    ButtonSegment(
                                      value: 'crank',
                                      label: Text(
                                        'مانيفر',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      icon: Icon(
                                        Icons.settings_overscan,
                                        size: 16,
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: 'motor',
                                      label: Text(
                                        'محرك',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      icon: Icon(Icons.power, size: 16),
                                    ),
                                  ],
                                  selected: {_shutterDriveType},
                                  onSelectionChanged:
                                      (Set<String> newSelection) {
                                        setState(
                                          () => _shutterDriveType =
                                              newSelection.first,
                                        );
                                      },
                                  style: ButtonStyle(
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // الجهة
                        Row(
                          children: [
                            Text(
                              'الجهة:',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'right',
                                  label: Text(
                                    'يمين',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                ButtonSegment(
                                  value: 'left',
                                  label: Text(
                                    'يسار',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                              selected: {_shutterDriveSide},
                              onSelectionChanged: (Set<String> newSelection) {
                                setState(
                                  () => _shutterDriveSide = newSelection.first,
                                );
                              },
                              style: ButtonStyle(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // المنزلق لرفع وإنزال الستار
                    Row(
                      children: [
                        Text(
                          'تحريك الستار:',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: widget.model.shutterPosition,
                            min: 0.0,
                            max: 1.0,
                            activeColor: Colors.blue,
                            inactiveColor: Colors.grey.shade300,
                            onChanged: (value) =>
                                widget.model.setShutterPosition(value),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 🟢 مساحة اللوحة التفاعلية للرسم
              Expanded(
                child: Container(
                  color: const Color(0xFFF5F5F5),
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    boundaryMargin: const EdgeInsets.all(5000),
                    minScale: 0.05,
                    maxScale: 5.0,
                    constrained: false,
                    child: Center(
                      child: CustomPaint(
                        size: Size(
                          widget.model.width,
                          widget.model.height + 250,
                        ),
                        painter: WindowPainter(
                          model: widget.model,
                          driveType: _shutterDriveType,
                          driveSide: _shutterDriveSide,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 🟢 الشريط السفلي المضاف لحساب التكلفة
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(
                    Icons.calculate_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  label: const Text(
                    'حساب التقطيع والتكلفة',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _showCalculationDialog,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// 🟢 2. كود الرسام (WindowPainter) مخصص للستار فقط مع تأثيرات 3D للصندوق
// ============================================================================
class WindowPainter extends CustomPainter {
  final WindowModel model;
  final String driveType;
  final String driveSide;

  WindowPainter({
    required this.model,
    required this.driveType,
    required this.driveSide,
  }) : super(repaint: model);

  List<Color> get _fc {
    if (model.selectedDbColor != null) {
      final hexCode = (model.selectedDbColor!['hex_code'] as String)
          .toUpperCase();
      if (hexCode == '#FFFFFF') return FrameColor.white.gradientColors;
      if (hexCode == '#795548' || hexCode == '#5D4037') {
        return FrameColor.brown.gradientColors;
      }
      if (hexCode == '#9E9E9E' || hexCode == '#B0BEC5' || hexCode == '#E0E0E0') {
        return FrameColor.gray.gradientColors;
      }
      if (hexCode == '#000000' || hexCode == '#212121') {
        return FrameColor.black.gradientColors;
      }
      if (hexCode == '#F5F5DC' || hexCode == '#DDC8A0') {
        return FrameColor.beige.gradientColors;
      }
    }
    return model.frameColor.gradientColors;
  }

  Color get _fb {
    if (model.selectedDbColor != null) {
      final hexCode = model.selectedDbColor!['hex_code'] as String;
      Color c = Colors.grey;
      try {
        c = Color(int.parse(hexCode.replaceFirst('#', '0xFF')));
      } catch (_) {}
      final hsl = HSLColor.fromColor(c);
      return hsl.withLightness((hsl.lightness - 0.2).clamp(0.0, 1.0)).toColor();
    }
    return model.frameColor.borderColor;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = model.width > 0 ? model.width : size.width;
    final h = model.height > 0 ? model.height : size.height;

    double boxSize = 155.0;
    if (h > 1600 && h <= 2400) {
      boxSize = 185.0;
    } else if (h > 2400) {
      boxSize = 205.0;
    }

    // رسم السكك الجانبية (الأخاديد) في الخلف
    const coulisseWidth = 25.0;
    final trackPaint = Paint()
      ..color = _fc[1]
      ..style = PaintingStyle.fill;
    final trackBorder = Paint()
      ..color = _fb
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRect(Rect.fromLTWH(0, boxSize, coulisseWidth, h), trackPaint);
    canvas.drawRect(Rect.fromLTWH(0, boxSize, coulisseWidth, h), trackBorder);
    canvas.drawRect(
      Rect.fromLTWH(w - coulisseWidth, boxSize, coulisseWidth, h),
      trackPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(w - coulisseWidth, boxSize, coulisseWidth, h),
      trackBorder,
    );

    // رسم شفرات الستار
    final visibleSlatsHeight = h * model.shutterPosition;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        coulisseWidth,
        boxSize,
        w - coulisseWidth,
        boxSize + visibleSlatsHeight,
      ),
    );

    for (double y = boxSize; y < boxSize + visibleSlatsHeight; y += 20.0) {
      canvas.drawRect(
        Rect.fromLTRB(coulisseWidth, y, w - coulisseWidth, y + 20.0),
        Paint()
          ..color = _fc[0].withValues(alpha: 0.95)
          ..style = PaintingStyle.fill,
      );
      canvas.drawLine(
        Offset(coulisseWidth, y + 20.0),
        Offset(w - coulisseWidth, y + 20.0),
        Paint()
          ..color = _fb.withValues(alpha: 0.4)
          ..strokeWidth = 1,
      );
    }

    // إضافة ظل غائر للشفرات في الوجه الداخلي
    if (model.isInternalView && visibleSlatsHeight > 0) {
      canvas.drawRect(
        Rect.fromLTWH(coulisseWidth, boxSize, w - (coulisseWidth * 2), 25),
        Paint()
          ..shader =
              LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.6),
                  Colors.transparent,
                ],
              ).createShader(
                Rect.fromLTWH(
                  coulisseWidth,
                  boxSize,
                  w - (coulisseWidth * 2),
                  25,
                ),
              ),
      );
    }
    canvas.restore();

    // رسم صندوق الستار العلوي
    final boxRect = Rect.fromLTWH(0, 0, w, boxSize);

    if (model.isInternalView) {
      canvas.drawRect(
        Rect.fromLTWH(0, boxSize, w, 10),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent],
          ).createShader(Rect.fromLTWH(0, boxSize, w, 10)),
      );
    }

    canvas.drawRect(
      boxRect,
      Paint()
        ..color = _fc[1]
        ..style = PaintingStyle.fill,
    );

    if (model.isInternalView) {
      canvas.drawRect(
        Rect.fromLTWH(0, boxSize - 18, w, 18),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill,
      );
      canvas.drawLine(
        Offset(0, boxSize - 18),
        Offset(w, boxSize - 18),
        Paint()
          ..color = _fb
          ..strokeWidth = 1.2,
      );
    }

    canvas.drawRect(
      boxRect,
      Paint()
        ..color = _fb
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    if (model.isInternalView) {
      _drawDriveMechanism(canvas, w, h, boxSize, coulisseWidth);
    }
  }

  void _drawDriveMechanism(
    Canvas canvas,
    double w,
    double h,
    double boxSize,
    double coulisseWidth,
  ) {
    bool isRight = driveSide == 'right';
    double sign = isRight ? 1.0 : -1.0;

    Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    if (driveType == 'motor') {
      double sideX = isRight ? w : 0.0;
      double startY = boxSize / 2;
      double wireLength = h * 0.65;
      double step = wireLength / 3;

      Paint motorPaint = Paint()
        ..color = const Color(0xFF212121)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round;

      Path wirePath = Path();
      wirePath.moveTo(sideX, startY);

      wirePath.quadraticBezierTo(
        sideX + (sign * 45),
        startY + (step * 0.5),
        sideX + (sign * 20),
        startY + step,
      );
      wirePath.quadraticBezierTo(
        sideX - (sign * 5),
        startY + (step * 1.5),
        sideX + (sign * 30),
        startY + (step * 2.0),
      );
      wirePath.quadraticBezierTo(
        sideX + (sign * 55),
        startY + (step * 2.5),
        sideX + (sign * 15),
        startY + wireLength,
      );

      canvas.drawPath(wirePath, motorPaint);

      double endX = sideX + (sign * 15);
      double endY = startY + wireLength;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(endX, endY + 8),
            width: 14,
            height: 20,
          ),
          const Radius.circular(4),
        ),
        Paint()
          ..color = const Color(0xFF212121)
          ..style = PaintingStyle.fill,
      );

      Paint pinPaint = Paint()
        ..color = Colors.grey.shade400
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(endX - 3, endY + 18),
        Offset(endX - 3, endY + 28),
        pinPaint,
      );
      canvas.drawLine(
        Offset(endX + 3, endY + 18),
        Offset(endX + 3, endY + 28),
        pinPaint,
      );
    } else {
      double frontX = isRight ? w - 25.0 : 25.0;

      if (driveType == 'strap') {
        paint.color = Colors.grey.shade400;
        paint.strokeWidth = 14.0;
        double strapLength = h * 0.4;

        canvas.drawLine(
          Offset(frontX, boxSize - 9),
          Offset(frontX, boxSize + strapLength),
          paint,
        );

        final boxCenter = Offset(frontX, boxSize + strapLength + 25);
        canvas.drawRect(
          Rect.fromCenter(center: boxCenter, width: 22, height: 50),
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill,
        );
        canvas.drawRect(
          Rect.fromCenter(center: boxCenter, width: 22, height: 50),
          Paint()
            ..color = Colors.grey.shade600
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        canvas.drawLine(
          Offset(frontX - 5, boxCenter.dy - 15),
          Offset(frontX + 5, boxCenter.dy - 15),
          Paint()
            ..color = Colors.black87
            ..strokeWidth = 3,
        );
      } else if (driveType == 'crank') {
        paint.color = Colors.grey.shade300;
        paint.strokeWidth = 10.0;
        paint.strokeJoin = StrokeJoin.round;
        double rodLength = h * 0.5;

        canvas.drawCircle(
          Offset(frontX, boxSize - 5),
          9,
          Paint()
            ..color = Colors.grey.shade600
            ..style = PaintingStyle.fill,
        );
        canvas.drawLine(
          Offset(frontX, boxSize - 5),
          Offset(frontX, boxSize + rodLength),
          paint,
        );

        double zigzagWidth = isRight ? -60.0 : 60.0;

        Path crankPath = Path();
        crankPath.moveTo(frontX, boxSize + rodLength);
        crankPath.lineTo(frontX + zigzagWidth, boxSize + rodLength + 15);
        crankPath.lineTo(frontX + zigzagWidth, boxSize + rodLength + 105);
        crankPath.lineTo(frontX, boxSize + rodLength + 120);
        canvas.drawPath(crankPath, paint);

        canvas.drawLine(
          Offset(frontX, boxSize + rodLength + 120),
          Offset(frontX, boxSize + rodLength + 180),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 14
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant WindowPainter oldDelegate) => true;
}
