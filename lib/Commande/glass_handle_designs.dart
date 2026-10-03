import 'dart:io';
import 'package:flutter/material.dart';

/// Definition of a standard glass handle design / model.
/// Allows workshop owners to create handles under any custom commercial name
/// while linking them to a clean physical drawing design and reference photo.
class GlassHandleDesignDefinition {
  final String code;
  final String labelAr;
  final String labelFr;
  final String assetPath;
  final String shape; // 'round' or 'square'
  final String type; // 'handle', 'towel_rail', 'knob'
  final int defaultHolesCount;
  final double defaultEntraxe;
  final double defaultHoleDiameter;
  final String descriptionAr;

  const GlassHandleDesignDefinition({
    required this.code,
    required this.labelAr,
    required this.labelFr,
    required this.assetPath,
    required this.shape,
    required this.type,
    required this.defaultHolesCount,
    required this.defaultEntraxe,
    this.defaultHoleDiameter = 12.0,
    this.descriptionAr = '',
  });

  bool get isSquare => shape == 'square';
  bool get isTowelRail => type == 'towel_rail';
  bool get isKnob => type == 'knob';
}

/// Catalog of available glass handle motifs & drawings.
class GlassHandleDesignCatalog {
  static const List<GlassHandleDesignDefinition> designs = [
    GlassHandleDesignDefinition(
      code: 'vro_ronde',
      labelAr: 'مقبض V-RO أنبوبي دائري',
      labelFr: 'Poignée tubulaire ronde (V-RO)',
      assetPath: 'assets/images/poignee_ro_ronde.png',
      shape: 'round',
      type: 'handle',
      defaultHolesCount: 2,
      defaultEntraxe: 200.0,
      defaultHoleDiameter: 12.0,
      descriptionAr: 'أنبوب ستانلس أسطواني دائري مع قواعد تثبيت دائرية مصقولة',
    ),
    GlassHandleDesignDefinition(
      code: 'vro_carree',
      labelAr: 'مقبض V-RO أنبوبي مربع',
      labelFr: 'Poignée tubulaire carrée (V-RO)',
      assetPath: 'assets/images/poignee_ro_carree.png',
      shape: 'square',
      type: 'handle',
      defaultHolesCount: 2,
      defaultEntraxe: 200.0,
      defaultHoleDiameter: 10.0,
      descriptionAr: 'أنبوب ستانلس بمقطع مربع أنيق مع قواعد تثبيت مربعة مشطوفة',
    ),
    GlassHandleDesignDefinition(
      code: 'porte_serviettes_rond',
      labelAr: 'حامل مناشف V-RO دائري',
      labelFr: 'Porte-serviettes rond (V-RO)',
      assetPath: 'assets/images/porte_serviettes_ro_rond.png',
      shape: 'round',
      type: 'towel_rail',
      defaultHolesCount: 2,
      defaultEntraxe: 400.0,
      defaultHoleDiameter: 12.0,
      descriptionAr: 'قضيب أفقي دائري لحمل المناشف مع ركائز تثبيت دائرية',
    ),
    GlassHandleDesignDefinition(
      code: 'porte_serviettes_carre',
      labelAr: 'حامل مناشف V-RO مربع',
      labelFr: 'Porte-serviettes carré (V-RO)',
      assetPath: 'assets/images/porte_serviettes_ro_carre.png',
      shape: 'square',
      type: 'towel_rail',
      defaultHolesCount: 2,
      defaultEntraxe: 400.0,
      defaultHoleDiameter: 10.0,
      descriptionAr: 'قضيب أفقي بمقطع مربع عصري مع ركائز تثبيت مربعة متناسقة',
    ),
    GlassHandleDesignDefinition(
      code: 'bouton_rond',
      labelAr: 'مقبض زر دائري مفرد (Bouton)',
      labelFr: 'Bouton rond inox simple',
      assetPath: 'assets/images/poignee_ro_ronde.png',
      shape: 'round',
      type: 'knob',
      defaultHolesCount: 1,
      defaultEntraxe: 0.0,
      defaultHoleDiameter: 10.0,
      descriptionAr: 'مقبض زر دائري ثقب واحد Ø10-12 مم مريح وسهل الاستخدام',
    ),
    GlassHandleDesignDefinition(
      code: 'bouton_carre',
      labelAr: 'مقبض زر مربع مفرد (Bouton carré)',
      labelFr: 'Bouton carré inox simple',
      assetPath: 'assets/images/poignee_ro_carree.png',
      shape: 'square',
      type: 'knob',
      defaultHolesCount: 1,
      defaultEntraxe: 0.0,
      defaultHoleDiameter: 10.0,
      descriptionAr: 'مقبض زر مربع بحواف مشطوفة عصرية ثقب واحد',
    ),
  ];

  static GlassHandleDesignDefinition? findByCode(String? code) {
    if (code == null || code.trim().isEmpty) return null;
    final normalized = code.trim().toLowerCase();
    for (final d in designs) {
      if (d.code.toLowerCase() == normalized) return d;
    }
    return null;
  }

  static GlassHandleDesignDefinition? findByImagePath(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final normalized = path.trim().toLowerCase();
    for (final d in designs) {
      if (d.assetPath.toLowerCase() == normalized ||
          normalized.endsWith(d.assetPath.toLowerCase())) {
        return d;
      }
    }
    return null;
  }

  /// Automatically resolves the correct design definition for a given handle item map,
  /// checking handle_design_code, image_path, or analyzing the item name.
  static GlassHandleDesignDefinition resolveForItem(Map<String, dynamic>? item) {
    if (item == null) return designs[0];

    // 1. Direct design code
    final code = item['handle_design_code']?.toString();
    final byCode = findByCode(code);
    if (byCode != null) return byCode;

    // 2. Direct image path
    final imagePath = item['image_path']?.toString();
    final byImage = findByImagePath(imagePath);
    if (byImage != null) return byImage;

    // 3. Name & properties semantic resolution
    final name = (item['name'] ?? '').toString().toLowerCase();
    final notes = (item['notes'] ?? '').toString().toLowerCase();
    final entraxe = (item['entraxe'] as num?)?.toDouble() ?? 0.0;
    final holesCount = (item['holes_count'] as num?)?.toInt() ?? 0;

    final isTowel = name.contains('serviette') ||
        name.contains('منشف') ||
        notes.contains('serviette') ||
        notes.contains('منشف');
    final isSquare = name.contains('carr') ||
        name.contains('مربع') ||
        name.contains('square') ||
        notes.contains('carr') ||
        notes.contains('مربع');
    final isKnob = holesCount == 1 ||
        entraxe == 0 ||
        name.contains('bouton') ||
        name.contains('زر') ||
        name.contains('مفرد');

    if (isKnob) {
      return isSquare ? designs[5] : designs[4];
    }
    if (isTowel) {
      return isSquare ? designs[3] : designs[2];
    }
    return isSquare ? designs[1] : designs[0];
  }
}

/// Visual preview widget for a handle design thumbnail.
class GlassHandleThumbnailView extends StatelessWidget {
  final String? imagePath;
  final String? designCode;
  final double size;
  final BorderRadius? borderRadius;
  final BoxFit fit;

  const GlassHandleThumbnailView({
    super.key,
    this.imagePath,
    this.designCode,
    this.size = 52,
    this.borderRadius,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? BorderRadius.circular(10);
    String resolvedPath = imagePath?.trim() ?? '';
    if (resolvedPath.isEmpty && designCode != null) {
      final d = GlassHandleDesignCatalog.findByCode(designCode);
      if (d != null) resolvedPath = d.assetPath;
    }

    Widget content;
    if (resolvedPath.isNotEmpty) {
      if (resolvedPath.startsWith('assets/')) {
        content = Image.asset(
          resolvedPath,
          fit: fit,
          errorBuilder: (_, __, ___) => _fallbackIcon(),
        );
      } else if (File(resolvedPath).existsSync()) {
        content = Image.file(
          File(resolvedPath),
          fit: fit,
          errorBuilder: (_, __, ___) => _fallbackIcon(),
        );
      } else {
        content = _fallbackIcon();
      }
    } else {
      content = _fallbackIcon();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: effectiveRadius,
        border: Border.all(color: Colors.teal.shade100, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: effectiveRadius,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: content,
        ),
      ),
    );
  }

  Widget _fallbackIcon() {
    return Icon(
      Icons.door_sliding_outlined,
      size: size * 0.5,
      color: Colors.teal.shade800,
    );
  }
}

/// Dialog allowing the user to visually choose a handle design / photo
/// when creating or editing a tempered glass handle item.
class GlassHandleDesignPickerModal extends StatefulWidget {
  final String? currentCode;
  final String? currentImagePath;

  const GlassHandleDesignPickerModal({
    super.key,
    this.currentCode,
    this.currentImagePath,
  });

  static Future<GlassHandleDesignDefinition?> show(
    BuildContext context, {
    String? currentCode,
    String? currentImagePath,
  }) {
    return showModalBottomSheet<GlassHandleDesignDefinition>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GlassHandleDesignPickerModal(
        currentCode: currentCode,
        currentImagePath: currentImagePath,
      ),
    );
  }

  @override
  State<GlassHandleDesignPickerModal> createState() =>
      _GlassHandleDesignPickerModalState();
}

class _GlassHandleDesignPickerModalState
    extends State<GlassHandleDesignPickerModal> {
  String? _selectedCode;

  @override
  void initState() {
    super.initState();
    if (widget.currentCode != null && widget.currentCode!.isNotEmpty) {
      _selectedCode = widget.currentCode;
    } else if (widget.currentImagePath != null &&
        widget.currentImagePath!.isNotEmpty) {
      _selectedCode =
          GlassHandleDesignCatalog.findByImagePath(widget.currentImagePath)?.code;
    }
    _selectedCode ??= GlassHandleDesignCatalog.designs.first.code;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final designs = GlassHandleDesignCatalog.designs;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.palette_outlined,
                    color: Colors.teal.shade700,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'اختر تصميم وصورة المقبض (Modèle de dessin)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'سيتم ربط هذا المقبض بالصورة المختارة ليتم رسمه بنفس تصميمه الهندسي على شاشة الزجاج المقسى.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.95,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: designs.length,
                itemBuilder: (context, idx) {
                  final d = designs[idx];
                  final isSelected = _selectedCode == d.code;

                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      setState(() => _selectedCode = d.code);
                      Navigator.pop(context, d);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.teal.shade50
                            : theme.cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? Colors.teal.shade700
                              : Colors.grey.shade300,
                          width: isSelected ? 2.2 : 1.0,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Colors.teal.withValues(alpha: 0.18),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Image.asset(
                                    d.assetPath,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => Icon(
                                      Icons.door_sliding_outlined,
                                      size: 40,
                                      color: Colors.teal.shade700,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.shade700,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            d.labelAr,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isSelected ? Colors.teal.shade900 : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: d.isSquare
                                      ? Colors.indigo.shade50
                                      : Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  d.isSquare ? 'مربع' : 'دائري',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: d.isSquare
                                        ? Colors.indigo.shade800
                                        : Colors.amber.shade900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                d.defaultEntraxe > 0
                                    ? '${d.defaultEntraxe.toInt()} مم'
                                    : 'ثقب مفرد',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
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
