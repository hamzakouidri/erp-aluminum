import 'package:flutter/material.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/show_system_francais.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:database_data/Commande/capture_image.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/Systeme/sliding_montant_counts.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';

class OrderTableEditScreen extends StatefulWidget {
  final List<WindowModel> products;

  const OrderTableEditScreen({Key? key, required this.products})
    : super(key: key);

  @override
  State<OrderTableEditScreen> createState() => _OrderTableEditScreenState();
}

class _OrderTableEditScreenState extends State<OrderTableEditScreen> {
  Future<void> _editActualDrawing(int index) async {
    final original = widget.products[index];
    final draft = WindowModel(db: original.db);
    applyWindowModelFromMap(draft, original.toMap());
    draft.copyCatalogRuntimeFrom(original, preserveCurrentSelections: true);
    final result = await Navigator.push<WindowModel>(
      context,
      MaterialPageRoute(
        builder: (_) => WindowView(
          model: draft,
          // Same rule as the order page: editing an existing drawing exposes
          // the full design tools. Its saved mode ('sliding') hid the
          // opening sashes, fixed glass and splits.
          systemMode: 'mixed',
        ),
      ),
    );
    if (!mounted || result == null) return;
    widget.products[index] = result;
    _widthControllers[index]?.text = result.width.toStringAsFixed(0);
    _heightControllers[index]?.text = result.height.toStringAsFixed(0);
    _quantityControllers[index]?.text = result.quantity.toString();
    _priceControllers[index]?.text =
        (result.manualPriceOverride ?? result.totalCost).toStringAsFixed(2);
    _descControllers[index]?.text = _buildInvoiceLineForProduct(
      result,
      description: '',
      forceGeneratedDetails: true,
    ).details.join('\n');
    await _loadProductPreviewImage(index, result);
    if (mounted) setState(() {});
  }

  String t(String key) {
    try {
      final lang = Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).language;
      return Localization.translate(key, lang);
    } catch (_) {
      return key;
    }
  }

  final Map<int, TextEditingController> _nameControllers = {};
  final Map<int, TextEditingController> _widthControllers = {};
  final Map<int, TextEditingController> _heightControllers = {};
  final Map<int, TextEditingController> _quantityControllers = {};
  final Map<int, TextEditingController> _priceControllers = {};
  final Map<int, TextEditingController> _descControllers = {};
  final Map<int, Uint8List?> _images = {};
  Timer? _debounce;

  // ─── Multi-select state ───
  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};

  void _enterSelectionMode(int index) {
    setState(() {
      _isSelectionMode = true;
      _selectedIndices.add(index);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIndices.clear();
    });
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  // Global controllers for Bulk Edit (Keys & Values)
  final _globalGamKeyController = TextEditingController();
  final _globalGamController = TextEditingController();

  final _globalTitleController = TextEditingController();

  final _globalColorKeyController = TextEditingController();
  final _globalColorController = TextEditingController();

  final _globalAccessoryColorKeyController = TextEditingController();
  final _globalAccessoryColorController = TextEditingController();

  final _globalShutterColorKeyController = TextEditingController();
  final _globalShutterColorController = TextEditingController();

  final _globalGlassKeyController = TextEditingController();
  final _globalGlassController = TextEditingController();

  final _globalCoverKeyController = TextEditingController();
  final _globalCoverController = TextEditingController();

  final _globalBaseKeyController = TextEditingController();
  final _globalBaseController = TextEditingController();

  final _globalClosureKeyController = TextEditingController();
  final _globalClosureController = TextEditingController();

  final _globalShutterKeyController = TextEditingController();
  final _globalShutterController = TextEditingController();

  final _globalWidthKeyController = TextEditingController();
  final _globalWidthController = TextEditingController();

  final _globalHeightKeyController = TextEditingController();
  final _globalHeightController = TextEditingController();

  final _globalHandleHKeyController = TextEditingController();
  final _globalHandleHController = TextEditingController();

  final _globalLameController = TextEditingController();
  final _globalCoulisseController = TextEditingController();

  void _onFieldChanged(int index) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    setState(() {}); // يُحدِّث حساب السعر فوراً

    // Keep typing fluid, while refreshing the dependent description and
    // preview shortly after the user pauses. Totals themselves are rebuilt
    // immediately by the setState above.
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final p = widget.products[index];
      final double newW = double.tryParse(_widthControllers[index]!.text) ?? 0;
      final double newH = double.tryParse(_heightControllers[index]!.text) ?? 0;

      // Update the description text box dynamically!
      final currentDesc = _descControllers[index]!.text;
      final newDesc = _buildInvoiceLineForProduct(
        p,
        width: newW,
        height: newH,
        description: currentDesc,
        forceGeneratedDetails: true,
      ).details.join('\n');
      if (currentDesc != newDesc) {
        // Keep cursor position
        final selection = _descControllers[index]!.selection;
        _descControllers[index]!.text = newDesc;
        // Attempt to restore selection if it's within bounds
        if (selection.isValid && selection.end <= newDesc.length) {
          _descControllers[index]!.selection = selection;
        } else {
          _descControllers[index]!.selection = TextSelection.collapsed(
            offset: newDesc.length,
          );
        }
      }

      // ─── معاينة الصورة بنموذج مؤقت (لا نُعدّل النموذج الأصلي هنا) ───
      // نبني نسخة مؤقتة بالأبعاد الجديدة لالتقاط الصورة فقط
      final tempModel = WindowModel(db: p.db);
      applyWindowModelFromMap(tempModel, p.toMap());
      // Copy the complete catalog runtime, including role ownership and the
      // separate sliding series. Copying only the two active series made the
      // preview fall back to opening profiles and lose its colours.
      tempModel.copyCatalogRuntimeFrom(p, preserveCurrentSelections: true);
      tempModel.persistedDrawingImagePath = p.persistedDrawingImagePath;
      tempModel.persistedDrawingImageBase64 = p.persistedDrawingImageBase64;

      // نطبّق إعادة التحجيم على النموذج المؤقت فقط
      if ((newW - p.width).abs() > 0.5 || (newH - p.height).abs() > 0.5) {
        tempModel.rescaleZones(p.width, p.height, newW, newH);
      }

      _loadProductPreviewImage(index, tempModel);
    });
  }

  DevisLineItem _buildInvoiceLineForProduct(
    WindowModel product, {
    double? width,
    double? height,
    int? quantity,
    double? price,
    String? description,
    bool forceGeneratedDetails = false,
  }) {
    return DevisBuilder.buildLineItemFromDetail(
      _detailMapFromProduct(
        product,
        width: width,
        height: height,
        quantity: quantity,
        price: price,
        description: description,
      ),
      overrideLang: lang,
      forceGeneratedDetails: forceGeneratedDetails,
    );
  }

  Map<String, dynamic> _detailMapFromProduct(
    WindowModel product, {
    double? width,
    double? height,
    int? quantity,
    double? price,
    String? description,
  }) {
    final map = Map<String, dynamic>.from(product.toMap());
    final effectiveWidth = width ?? product.width;
    final effectiveHeight = height ?? product.height;
    final effectiveQuantity = quantity ?? product.quantity;
    final effectivePrice =
        price ?? product.manualPriceOverride ?? product.totalCost;
    final effectiveDescription = description ?? product.description ?? '';

    map['width'] = effectiveWidth;
    map['height'] = effectiveHeight;
    map['quantity'] = effectiveQuantity;
    map['description'] = effectiveDescription;

    final bool hasSliding = product.zones.any(
      (z) => z.content == ZoneContent.slidingSash,
    );
    final bool hasOpening = product.zones.any(
      (z) =>
          z.content == ZoneContent.singleSash ||
          z.content == ZoneContent.doubleSash,
    );
    final String seriesName;
    if (product.isGlassWork) {
      seriesName = 'فير ترومبي';
    } else if (hasSliding && !hasOpening) {
      seriesName = product.activeSlidingSeries?.name ??
          product.loadedSlidingSeriesName ??
          product.activeFrameSeries?.name ??
          '';
    } else if (hasOpening && !hasSliding) {
      seriesName = product.activeSeries?.name ??
          product.loadedSeriesName ??
          product.activeFrameSeries?.name ??
          '';
    } else {
      seriesName = product.activeFrameSeries?.name ??
          product.loadedSeriesName ??
          product.activeSlidingSeries?.name ??
          product.loadedSlidingSeriesName ??
          '';
    }
    final colorName =
        product.selectedDbColor?['name']?.toString() ?? product.frameColor.name;

    return {
      'id': 0,
      'window_type': product.manualNameOverride ?? '',
      'game': seriesName,
      'color': colorName,
      'glass':
          product.zones.isNotEmpty &&
              product.zones.first.glass.structure == GlassStructure.double
          ? 'Double'
          : 'Simple',
      'largeur': effectiveWidth,
      'hauteur': effectiveHeight,
      'quantity': effectiveQuantity,
      'price': effectivePrice,
      'description': effectiveDescription,
      'partitions_json': jsonEncode(map),
      'drawing_image_path': '',
    };
  }

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < widget.products.length; i++) {
      final p = widget.products[i];
      final invoiceLine = _buildInvoiceLineForProduct(
        p,
        // Reopen the exact text previously saved in the PDF table. Forcing
        // generated details here made a text-only edit appear to disappear
        // the next time the invoice was edited.
        forceGeneratedDetails: false,
      );

      // Name
      _nameControllers[i] = TextEditingController(text: invoiceLine.title);

      // Dimensions
      _widthControllers[i] = TextEditingController(
        text: p.width.toInt().toString(),
      );
      _heightControllers[i] = TextEditingController(
        text: p.height.toInt().toString(),
      );

      // Quantity
      _quantityControllers[i] = TextEditingController(
        text: p.quantity.toString(),
      );

      // Price
      _priceControllers[i] = TextEditingController(
        text: (p.manualPriceOverride ?? p.totalCost).toStringAsFixed(2),
      );

      // Description (Details)
      String initialDesc = invoiceLine.details.join('\n');
      _descControllers[i] = TextEditingController(text: initialDesc);

      _loadProductPreviewImage(i, p);
    }

    _extractGlobalValues();
  }

  Future<void> _loadProductPreviewImage(int index, WindowModel product) async {
    Uint8List? imageBytes;
    try {
      imageBytes = await captureWindowImage(product, maxSide: 400);
    } catch (error) {
      debugPrint('Error capturing window image in pricing table: $error');
    }

    imageBytes ??= await _readPersistedPreviewImage(product);
    if (!mounted) return;
    setState(() => _images[index] = imageBytes);
  }

  Future<Uint8List?> _readPersistedPreviewImage(WindowModel product) async {
    final path = product.persistedDrawingImagePath?.trim() ?? '';
    if (path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) return file.readAsBytes();
      } catch (_) {}
    }

    final raw = product.persistedDrawingImageBase64?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final separator = raw.indexOf(',');
      final encoded = raw.startsWith('data:image') && separator >= 0
          ? raw.substring(separator + 1)
          : raw;
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  void _extractGlobalValues() {
    final gamKeys = <String>[];
    final gams = <String>[];
    final titles = <String>[];

    final colorKeys = <String>[];
    final colors = <String>[];

    final accessoryColorKeys = <String>[];
    final accessoryColors = <String>[];

    final shutterColorKeys = <String>[];
    final shutterColors = <String>[];

    final glassKeys = <String>[];
    final glasses = <String>[];

    final coverKeys = <String>[];
    final covers = <String>[];

    final baseKeys = <String>[];
    final bases = <String>[];

    final closureKeys = <String>[];
    final closures = <String>[];

    final shutterKeys = <String>[];
    final shutters = <String>[];

    final lames = <String>[];
    final coulisses = <String>[];

    for (int i = 0; i < widget.products.length; i++) {
      final p = widget.products[i];
      if (p.isReplaced) continue; // Skip replaced/crossed-out elements!
      final title = _nameControllers[i]?.text.trim() ?? '';
      if (title.isNotEmpty) titles.add(title);
      final desc = _descControllers[i]?.text ?? _generateDefaultDetails(p);
      final lines = desc.split('\n');

      final glassBlock = _extractBlock(lines, _isGlassDetailLine);
      if (glassBlock.isNotEmpty) {
        glassKeys.add(_defaultKeyForCategory('glass'));
        glasses.add(glassBlock);
      }

      for (var line in lines) {
        final l = line.trim();
        if (_isGlassDetailLine(l)) continue;
        _collectCategoryValue(l, 'gam', gamKeys, gams);
        _collectCategoryValue(l, 'profileColor', colorKeys, colors);
        _collectCategoryValue(
          l,
          'accessoryColor',
          accessoryColorKeys,
          accessoryColors,
        );
        _collectCategoryValue(
          l,
          'shutterColor',
          shutterColorKeys,
          shutterColors,
        );
        _collectCategoryValue(l, 'cover', coverKeys, covers);
        _collectCategoryValue(l, 'base', baseKeys, bases);
        _collectCategoryValue(l, 'closure', closureKeys, closures);
        _collectCategoryValue(l, 'shutter', shutterKeys, shutters);

        if (_isCategoryLine('lame', l, '')) {
          lames.add(
            _extractValueFromLine(l).isEmpty ? l : _extractValueFromLine(l),
          );
        } else if (_isCategoryLine('coulisse', l, '')) {
          coulisses.add(
            _extractValueFromLine(l).isEmpty ? l : _extractValueFromLine(l),
          );
        }
      }
    }

    void setKeyCtrl(
      TextEditingController ctrl,
      String category,
      List<String> extracted,
    ) {
      final def = _defaultKeyForCategory(category);
      if (extracted.isNotEmpty) {
        final most = _mostCommon(extracted);
        final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(most);
        if (lang != AppLanguage.arabic && hasArabic) {
          ctrl.text = def;
        } else {
          ctrl.text = most;
        }
      } else {
        ctrl.text = def;
      }
    }

    if (titles.isNotEmpty) _globalTitleController.text = _mostCommon(titles);

    setKeyCtrl(_globalGamKeyController, 'gam', gamKeys);
    if (gams.isNotEmpty) _globalGamController.text = _mostCommon(gams);

    setKeyCtrl(_globalColorKeyController, 'profileColor', colorKeys);
    if (colors.isNotEmpty) _globalColorController.text = _mostCommon(colors);

    setKeyCtrl(
      _globalAccessoryColorKeyController,
      'accessoryColor',
      accessoryColorKeys,
    );
    if (accessoryColors.isNotEmpty) {
      _globalAccessoryColorController.text = _mostCommon(accessoryColors);
    }

    setKeyCtrl(
      _globalShutterColorKeyController,
      'shutterColor',
      shutterColorKeys,
    );
    if (shutterColors.isNotEmpty) {
      _globalShutterColorController.text = _mostCommon(shutterColors);
    }

    setKeyCtrl(_globalGlassKeyController, 'glass', glassKeys);
    if (glasses.isNotEmpty) _globalGlassController.text = _mostCommon(glasses);

    setKeyCtrl(_globalCoverKeyController, 'cover', coverKeys);
    if (covers.isNotEmpty) _globalCoverController.text = _mostCommon(covers);

    setKeyCtrl(_globalBaseKeyController, 'base', baseKeys);
    if (bases.isNotEmpty) _globalBaseController.text = _mostCommon(bases);

    setKeyCtrl(_globalClosureKeyController, 'closure', closureKeys);
    if (closures.isNotEmpty) {
      _globalClosureController.text = _mostCommon(closures);
    }

    setKeyCtrl(_globalShutterKeyController, 'shutter', shutterKeys);
    if (shutters.isNotEmpty) {
      _globalShutterController.text = _mostCommon(shutters);
    }

    if (lames.isNotEmpty) _globalLameController.text = _mostCommon(lames);
    if (coulisses.isNotEmpty) {
      _globalCoulisseController.text = _mostCommon(coulisses);
    }
  }

  void _collectCategoryValue(
    String line,
    String category,
    List<String> keys,
    List<String> values,
  ) {
    if (!_isCategoryLine(category, line, '')) return;
    final idx = line.indexOf(':');
    if (idx != -1) {
      keys.add(line.substring(0, idx + 1));
      values.add(line.substring(idx + 1).trim());
    } else {
      keys.add(_defaultKeyForCategory(category));
      values.add(line.trim());
    }
  }

  String _extractBlock(List<String> lines, bool Function(String) match) {
    return lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && match(line))
        .join('\n');
  }

  String _mostCommon(List<String> list) {
    if (list.isEmpty) return '';
    final counts = <String, int>{};
    for (var item in list) {
      counts[item] = (counts[item] ?? 0) + 1;
    }
    String best = list.first;
    int maxCount = 0;
    counts.forEach((k, v) {
      if (v > maxCount) {
        maxCount = v;
        best = k;
      }
    });
    return best;
  }

  void _applyGlobalChange(String category, String newKey, String newValue) {
    // Only apply to selected items when in selection mode
    final targetIndices = (_isSelectionMode && _selectedIndices.isNotEmpty)
        ? _selectedIndices.toList()
        : List.generate(widget.products.length, (i) => i);

    for (final i in targetIndices) {
      final p = widget.products[i];
      if (p.isReplaced) continue; // Skip replaced/crossed-out elements!

      if (category == 'title') {
        if (newValue.trim().isNotEmpty) {
          _nameControllers[i]?.text = newValue.trim();
        }
        continue;
      }

      final desc = _descControllers[i]!.text;
      final lines = desc.split('\n');
      final newLines = <String>[];
      var found = false;
      var insertedBlock = false;
      final replacementLines = _replacementLinesForCategory(
        category,
        newKey,
        newValue,
      );

      for (var line in lines) {
        final l = line.trim();
        final match = _isCategoryLine(category, l, newKey);

        if (match) {
          found = true;
          if (!insertedBlock && replacementLines.isNotEmpty) {
            newLines.addAll(replacementLines);
            insertedBlock = true;
          }
        } else {
          newLines.add(line);
        }
      }

      if (!found && replacementLines.isNotEmpty) {
        newLines.addAll(replacementLines);
      }

      _descControllers[i]!.text = newLines.join('\n');
    }
  }

  void _applyAllGlobalChanges() {
    setState(() {
      _applyGlobalChange('title', '', _globalTitleController.text.trim());
      _applyGlobalChange(
        'gam',
        _globalGamKeyController.text.trim(),
        _globalGamController.text.trim(),
      );
      _applyGlobalChange(
        'profileColor',
        _globalColorKeyController.text.trim(),
        _globalColorController.text.trim(),
      );
      _applyGlobalChange(
        'accessoryColor',
        _globalAccessoryColorKeyController.text.trim(),
        _globalAccessoryColorController.text.trim(),
      );
      _applyGlobalChange(
        'shutterColor',
        _globalShutterColorKeyController.text.trim(),
        _globalShutterColorController.text.trim(),
      );
      _applyGlobalChange(
        'glass',
        _globalGlassKeyController.text.trim(),
        _globalGlassController.text.trim(),
      );
      _applyGlobalChange(
        'cover',
        _globalCoverKeyController.text.trim(),
        _globalCoverController.text.trim(),
      );
      _applyGlobalChange(
        'base',
        _globalBaseKeyController.text.trim(),
        _globalBaseController.text.trim(),
      );
      _applyGlobalChange(
        'closure',
        _globalClosureKeyController.text.trim(),
        _globalClosureController.text.trim(),
      );
      _applyGlobalChange(
        'shutter',
        _globalShutterKeyController.text.trim(),
        _globalShutterController.text.trim(),
      );
      _applyGlobalChange('lame', '', _globalLameController.text.trim());
      _applyGlobalChange('coulisse', '', _globalCoulisseController.text.trim());
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('تم تطبيق الخصائص الموحدة على جميع العناصر بنجاح')),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _generateDefaultDetails(WindowModel p) {
    return _buildInvoiceLineForProduct(
      p,
      forceGeneratedDetails: true,
    ).details.join('\n');

    final curLang = lang;
    List<String> details = [];

    // 1. System Type
    if (p.isShutterOnly) {
      if (curLang == AppLanguage.french) {
        details.add('Volet roulant');
      } else if (curLang == AppLanguage.english) {
        details.add('Rolling shutter');
      } else {
        details.add('ستار رولان (Volet roulant)');
      }
    } else if (p.zones.any((z) => z.content == ZoneContent.slidingSash)) {
      int sCount = p.zones.isNotEmpty ? p.zones.first.slidingSashesCount : 2;
      if (curLang == AppLanguage.french) {
        details.add('Système Coulissant - $sCount vantaux');
      } else if (curLang == AppLanguage.english) {
        details.add('Sliding System - $sCount sashes');
      } else {
        details.add('نظام منزلق (Coulissant) - $sCount ضلفات');
      }
    } else {
      if (curLang == AppLanguage.french) {
        details.add('Système Battant');
      } else if (curLang == AppLanguage.english) {
        details.add('Casement System');
      } else {
        details.add('نظام مفصلي (Battant)');
      }
    }

    // 2. Series Name (Gam)
    String gamName = p.isShutterOnly
        ? (curLang == AppLanguage.french
            ? 'Volet'
            : (curLang == AppLanguage.english ? 'Shutter' : 'ستار'))
        : (p.activeSeries?.name ?? p.loadedSeriesName ?? '');
    if (gamName.isNotEmpty) {
      if (curLang == AppLanguage.french) {
        details.add('Gamme: $gamName');
      } else if (curLang == AppLanguage.english) {
        details.add('Series: $gamName');
      } else {
        details.add('القطاع: $gamName');
      }
    }

    // 3. Colors (Profile Color & Accessory Color & Shutter Color)
    final String profColor = p.selectedDbColor?['name'] != null
        ? Localization.colorName(p.selectedDbColor!['name'], curLang)
        : _colorLabelLocal(p.frameColor.toString().split('.').last, curLang);
    final String accColor = p.selectedAccessoryColor?['name'] != null
        ? Localization.colorName(p.selectedAccessoryColor!['name'], curLang)
        : profColor;

    if (curLang == AppLanguage.french) {
      details.add('Couleur Profil: $profColor');
      details.add('Couleur Accessoire: $accColor');
      if (p.isShutterOnly || p.hasShutter) {
        details.add('Couleur Volet: $profColor');
      }
    } else if (curLang == AppLanguage.english) {
      details.add('Profile Color: $profColor');
      details.add('Accessory Color: $accColor');
      if (p.isShutterOnly || p.hasShutter) {
        details.add('Shutter Color: $profColor');
      }
    } else {
      details.add('لون المقطع: $profColor');
      details.add('لون الإكسسوار: $accColor');
      if (p.isShutterOnly || p.hasShutter) {
        details.add('لون الستار: $profColor');
      }
    }

    // Width and Height are now always appended by devis_builder.dart directly to the invoice,
    // so we don't need them in the description text field.

    // 5. Handle Height
    if (p.zones.isNotEmpty) {
      final z = p.zones.first;
      if (z.content == ZoneContent.singleSash ||
          z.content == ZoneContent.doubleSash ||
          z.content == ZoneContent.slidingSash) {
        final bool isOcto = z.useOctoHandle == true;
        final bool isLeftOrRight =
            z.openDirection == OpenDirection.left ||
            z.openDirection == OpenDirection.right;

        if (!isOcto && isLeftOrRight) {
          final ratio = z.handlePositionRatio ?? 0.5;
          final handleY = z.boundary.top + z.boundary.height * (1.0 - ratio);
          final handleH = (p.height - handleY).toInt();
          if (curLang == AppLanguage.french) {
            details.add('Hauteur Poignée: ${handleH} mm');
          } else if (curLang == AppLanguage.english) {
            details.add('Handle Height: ${handleH} mm');
          } else {
            details.add('ارتفاع المقبض: ${handleH} مم');
          }
        }
      }
    }

    // 6. Glass — window only, never for standalone volet
    if (!p.isShutterOnly) {
      final isDouble =
          p.zones.isNotEmpty &&
          p.zones.first.glass.structure == GlassStructure.double;
      if (curLang == AppLanguage.french) {
        details.add(isDouble ? 'Vitrage: Double' : 'Vitrage: Simple');
      } else if (curLang == AppLanguage.english) {
        details.add(isDouble ? 'Glass: Double' : 'Glass: Single');
      } else {
        details.add(
          isDouble
              ? 'الزجاج: مزدوج (Double Vitrage)'
              : 'الزجاج: مفرد (Simple Vitrage)',
        );
      }
    }

    // 7. Couvre-joint (Side Covers) — window only, never for standalone volet
    if (!p.isShutterOnly && p.hasSideCovers) {
      final isMultiFrame = p.getFrameRects().length > 1;
      final removed = p.removedShutterSides.map((s) => s.toLowerCase()).toSet();
      final hasL = !removed.contains('left');
      final hasR = !removed.contains('right');
      final hasT = !removed.contains('top');
      final hasB = !removed.contains('bottom') && p.hasBottomFrame;

      if (isMultiFrame) {
        if (curLang == AppLanguage.french) {
          details.add('Couvre-joint: périmètre extérieur de tous les cadres');
        } else if (curLang == AppLanguage.english) {
          details.add('Cover joint: outer perimeter of all frames');
        } else {
          details.add('كوفرو جوان: المحيط الخارجي لجميع الإطارات');
        }
      } else if (curLang == AppLanguage.french) {
        final sides = <String>[];
        if (hasL) sides.add('Gauche');
        if (hasR) sides.add('Droite');
        if (hasT) sides.add('Haut');
        if (hasB) sides.add('Bas');
        if (sides.isNotEmpty) details.add('Couvre-joint: ${sides.join(', ')}');
      } else if (curLang == AppLanguage.english) {
        final sides = <String>[];
        if (hasL) sides.add('Left');
        if (hasR) sides.add('Right');
        if (hasT) sides.add('Top');
        if (hasB) sides.add('Bottom');
        if (sides.isNotEmpty) details.add('Cover joint: ${sides.join(', ')}');
      } else {
        final sides = <String>[];
        if (hasL) sides.add('يسار');
        if (hasR) sides.add('يمين');
        if (hasT) sides.add('أعلى');
        if (hasB) sides.add('أسفل');
        if (sides.isNotEmpty) details.add('كوفرو جوان: ${sides.join('، ')}');
      }
    }

    // 8. Fermeture — window only, not for standalone volet
    if (!p.isShutterOnly) {
      final pMap = p.toMap();
      final isPVC =
          p.isPVC ||
          p.isSlidingPVC ||
          (p.activeSeries?.name?.toLowerCase().contains('pvc') ?? false) ||
          (pMap['slidingSeriesName']?.toString().toLowerCase().contains(
                'pvc',
              ) ??
              false);
      bool useEntrematique = false;
      bool hasKeyLock = false;
      bool hasSliding = false;
      int lateralReinforcedCount = 0;
      int lateralNormalCount = 0;
      int centralReinforcedCount = 0;
      int centralNormalCount = 0;

      // Use toMap() zones (same data as devis_builder uses)
      final zonesList = pMap['zones'] as List? ?? [];
      for (final z in zonesList) {
        if (z == null || z is! Map) continue;
        final content = z['content']?.toString() ?? '';
        final lType = z['lockType']?.toString() ?? '';
        if (lType == 'clef' || lType == 'condamnation') hasKeyLock = true;
        if (content.contains('slidingSash')) {
          hasSliding = true;
          if (z['useClassicHandle'] != true) useEntrematique = true;
          final reinforcedMap = z['slidingMontantReinforced'] as Map?;
          final sashes = (z['slidingSashesCount'] as num?)?.toInt() ?? 2;
          final counts = slidingMontantCounts(
            sashes: sashes,
            tracks: (z['slidingTrackCount'] as num?)?.toInt() ?? sashes,
            faceToFace: z['slidingFaceToFace'] == true,
          );
          final lateralCount = counts.lateral;
          final currentCentralCount = counts.central;
          for (var i = 0; i < lateralCount; i++) {
            final isReinforced =
                reinforcedMap != null &&
                (reinforcedMap['lateral_$i'] == true ||
                    (i == 0 && reinforcedMap['lateral_left'] == true) ||
                    (i == (lateralCount == 4 ? 1 : lateralCount - 1) &&
                        reinforcedMap['lateral_right'] == true));
            if (isReinforced) {
              lateralReinforcedCount++;
            } else {
              lateralNormalCount++;
            }
          }
          for (var i = 0; i < currentCentralCount; i++) {
            final isReinforced =
                reinforcedMap != null &&
                (reinforcedMap['central_$i'] == true ||
                    (i.isEven && reinforcedMap['central_left'] == true) ||
                    (i.isOdd && reinforcedMap['central_right'] == true));
            if (isReinforced) {
              centralReinforcedCount++;
            } else {
              centralNormalCount++;
            }
          }
        }
      }
      if (isPVC) useEntrematique = false;

      bool useOcto = false;
      bool hasClef = false;
      bool hasCondamnation = false;
      for (final z in zonesList) {
        if (z == null || z is! Map) continue;
        final lType = z['lockType']?.toString() ?? '';
        final useOctoHandle =
            z['useOctoHandle'] == true ||
            z['useOctoHandle']?.toString() == 'true';
        if (useOctoHandle) useOcto = true;
        if (lType == 'clef') hasClef = true;
        if (lType == 'condamnation') hasCondamnation = true;
      }

      String fermetureVal = 'poignée espagnole';
      if (hasClef) {
        fermetureVal = 'béquille à clé';
      } else if (hasCondamnation) {
        fermetureVal = 'béquille condamnation';
      } else if (useOcto) {
        fermetureVal = 'poignée octo';
      } else if (useEntrematique) {
        fermetureVal = 'entrematique';
      }

      if (curLang == AppLanguage.french) {
        details.add('Fermeture: $fermetureVal');
      } else if (curLang == AppLanguage.english) {
        details.add('Closure: $fermetureVal');
      } else {
        details.add('الإغلاق (Fermeture): $fermetureVal');
      }

      final bool hasThreePiece =
          !isPVC &&
          ((p.activeSlidingSeries?.hasThreePieceSash ?? false) ||
              (p.activeSeries?.hasThreePieceSash ?? false) ||
              pMap['hasThreePieceSash'] == true ||
              pMap['has_three_piece_sash'] == 1 ||
              '${p.activeSlidingSeries?.name ?? pMap['slidingSeriesName'] ?? ''}'
                  .toLowerCase()
                  .contains('tpr'));

      // Montant renforcé / simple - only for 3-piece sash series
      if (hasSliding && !isPVC && hasThreePiece) {
        final totalLateral = lateralReinforcedCount + lateralNormalCount;
        if (totalLateral > 0) {
          if (lateralReinforcedCount > 0 && lateralNormalCount > 0) {
            details.add(switch (curLang) {
              AppLanguage.french =>
                'Montant latéral: $lateralReinforcedCount renforcé(s), $lateralNormalCount simple(s)',
              AppLanguage.english =>
                'Lateral montant: $lateralReinforcedCount reinforced, $lateralNormalCount standard',
              AppLanguage.arabic =>
                'القائم الجانبي: $lateralReinforcedCount مدعم، $lateralNormalCount غير مدعم',
            });
          } else if (lateralReinforcedCount > 0) {
            details.add(switch (curLang) {
              AppLanguage.french =>
                'Montant latéral: $lateralReinforcedCount renforcé(s)',
              AppLanguage.english =>
                'Lateral montant: $lateralReinforcedCount reinforced',
              AppLanguage.arabic =>
                'القائم الجانبي: $lateralReinforcedCount مدعم',
            });
          } else {
            details.add(switch (curLang) {
              AppLanguage.french =>
                'Montant latéral: $lateralNormalCount simple(s)',
              AppLanguage.english =>
                'Lateral montant: $lateralNormalCount standard',
              AppLanguage.arabic =>
                'القائم الجانبي: $lateralNormalCount غير مدعم',
            });
          }
        }

        final totalCentral = centralReinforcedCount + centralNormalCount;
        if (totalCentral > 0) {
          if (centralReinforcedCount > 0 && centralNormalCount > 0) {
            details.add(switch (curLang) {
              AppLanguage.french =>
                'Montant central: $centralReinforcedCount renforcé(s), $centralNormalCount simple(s)',
              AppLanguage.english =>
                'Central montant: $centralReinforcedCount reinforced, $centralNormalCount standard',
              AppLanguage.arabic =>
                'القائم الوسطي: $centralReinforcedCount مدعم، $centralNormalCount غير مدعم',
            });
          } else if (centralReinforcedCount > 0) {
            details.add(switch (curLang) {
              AppLanguage.french =>
                'Montant central: $centralReinforcedCount renforcé(s)',
              AppLanguage.english =>
                'Central montant: $centralReinforcedCount reinforced',
              AppLanguage.arabic =>
                'القائم الوسطي: $centralReinforcedCount مدعم',
            });
          } else {
            details.add(switch (curLang) {
              AppLanguage.french =>
                'Montant central: $centralNormalCount simple(s)',
              AppLanguage.english =>
                'Central montant: $centralNormalCount standard',
              AppLanguage.arabic =>
                'القائم الوسطي: $centralNormalCount غير مدعم',
            });
          }
        }
      }
    }

    // 8b. Shutter (Sitar) — present on volet or window with shutter
    if (p.hasShutter) {
      String mech = p.shutterMechanism.toLowerCase();
      String mechLabel = '';
      if (mech.contains('sangle') || mech.contains('حزام')) {
        mechLabel = 'manuel (sangle)';
      } else if (mech.contains('moteur') || mech.contains('محرك')) {
        mechLabel = 'électrique';
      } else if (mech.contains('manivelle') || mech.contains('منايفال')) {
        mechLabel = 'manuel (manivelle)';
      } else {
        mechLabel = mech;
      }

      if (curLang == AppLanguage.french) {
        details.add('Volet: $mechLabel');
      } else if (curLang == AppLanguage.english) {
        details.add('Shutter: $mechLabel');
      } else {
        details.add('ستار: $mechLabel');
      }

      // Shutter Lame — full name as stored in model
      final String lameFullName = p.shutterLame;
      if (lameFullName.isNotEmpty) {
        if (curLang == AppLanguage.french) {
          details.add('Lame: $lameFullName');
        } else if (curLang == AppLanguage.english) {
          details.add('Lame: $lameFullName');
        } else {
          details.add('الشفرة: $lameFullName');
        }
      }

      // Shutter Glissiere
      final String glis = p.shutterGlissiere;
      if (glis.isNotEmpty) {
        if (curLang == AppLanguage.french) {
          details.add(
            glis
                .replaceAll('Glissiere', 'Coulisse')
                .replaceAll('Glissière', 'Coulisse'),
          );
        } else if (curLang == AppLanguage.english) {
          details.add(
            glis
                .replaceAll('Glissiere', 'Slide')
                .replaceAll('Glissière', 'Slide'),
          );
        } else {
          details.add(
            glis
                .replaceAll('Glissiere', 'كوليس')
                .replaceAll('Glissière', 'كوليس'),
          );
        }
      }
    }

    return details.join('\n');
  }

  static String _colorLabelLocal(String color, AppLanguage curLang) {
    final lower = color.toLowerCase();
    if (curLang == AppLanguage.french) {
      if (lower == 'white' || lower == 'blanc' || lower == 'أبيض')
        return 'Blanc';
      if (lower == 'gray' ||
          lower == 'grey' ||
          lower == 'gris' ||
          lower == 'رمادي')
        return 'Gris';
      if (lower == 'faux bois marron clair' || lower == 'خشبي بني فاتح' || lower == 'light brown wood grain')
        return 'Faux bois marron clair';
      if (lower == 'faux bois marron' || lower == 'marron faux bois' || lower == 'خشبي بني' || lower == 'بني خشبي')
        return 'Faux Bois Marron';
      if (lower == 'brown' || lower == 'faux bois' || lower == 'بني')
        return 'Faux Bois';
      if (lower == 'black' || lower == 'noir' || lower == 'أسود') return 'Noir';
      if (lower == 'beige' || lower == 'بيج') return 'Beige';
      return color;
    } else if (curLang == AppLanguage.english) {
      if (lower == 'white' || lower == 'blanc' || lower == 'أبيض')
        return 'White';
      if (lower == 'gray' ||
          lower == 'grey' ||
          lower == 'gris' ||
          lower == 'رمادي')
        return 'Grey';
      if (lower == 'faux bois marron clair' || lower == 'خشبي بني فاتح' || lower == 'light brown wood grain')
        return 'Light brown wood grain';
      if (lower == 'faux bois marron' || lower == 'marron faux bois' || lower == 'خشبي بني' || lower == 'بني خشبي')
        return 'Brown Wood (Faux Bois Marron)';
      if (lower == 'brown' || lower == 'faux bois' || lower == 'بني')
        return 'Wood Faux';
      if (lower == 'black' || lower == 'noir' || lower == 'أسود')
        return 'Black';
      if (lower == 'beige' || lower == 'بيج') return 'Beige';
      return color;
    } else {
      if (lower == 'white' || lower == 'blanc' || lower == 'أبيض')
        return 'أبيض';
      if (lower == 'gray' ||
          lower == 'grey' ||
          lower == 'gris' ||
          lower == 'رمادي')
        return 'رمادي';
      if (lower == 'faux bois marron clair' || lower == 'خشبي بني فاتح' || lower == 'light brown wood grain')
        return 'خشبي بني فاتح';
      if (lower == 'faux bois marron' || lower == 'marron faux bois' || lower == 'خشبي بني' || lower == 'بني خشبي')
        return 'خشبي بني (Faux Bois Marron)';
      if (lower == 'brown' || lower == 'faux bois' || lower == 'بني')
        return 'بني';
      if (lower == 'black' || lower == 'noir' || lower == 'أسود') return 'أسود';
      if (lower == 'beige' || lower == 'بيج') return 'بيج';
      return color;
    }
  }

  @override
  void dispose() {
    _globalGamKeyController.dispose();
    _globalGamController.dispose();
    _globalTitleController.dispose();
    _globalColorKeyController.dispose();
    _globalColorController.dispose();
    _globalAccessoryColorKeyController.dispose();
    _globalAccessoryColorController.dispose();
    _globalShutterColorKeyController.dispose();
    _globalShutterColorController.dispose();
    _globalGlassKeyController.dispose();
    _globalGlassController.dispose();
    _globalCoverKeyController.dispose();
    _globalCoverController.dispose();
    _globalBaseKeyController.dispose();
    _globalBaseController.dispose();
    _globalClosureKeyController.dispose();
    _globalClosureController.dispose();
    _globalShutterKeyController.dispose();
    _globalShutterController.dispose();
    _globalWidthKeyController.dispose();
    _globalWidthController.dispose();
    _globalHeightKeyController.dispose();
    _globalHeightController.dispose();
    _globalHandleHKeyController.dispose();
    _globalHandleHController.dispose();
    _globalLameController.dispose();
    _globalCoulisseController.dispose();

    for (var c in _nameControllers.values) {
      c.dispose();
    }
    for (var c in _widthControllers.values) {
      c.dispose();
    }
    for (var c in _heightControllers.values) {
      c.dispose();
    }
    for (var c in _quantityControllers.values) {
      c.dispose();
    }
    for (var c in _priceControllers.values) {
      c.dispose();
    }
    for (var c in _descControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _saveAll() {
    for (int i = 0; i < widget.products.length; i++) {
      final p = widget.products[i];
      final nameCtrl = _nameControllers[i];
      if (nameCtrl != null) {
        p.manualNameOverride = nameCtrl.text.trim();
      }

      // ─── تطبيق إعادة التحجيم مرة واحدة من الأبعاد الأصلية ───
      final widthCtrl = _widthControllers[i];
      final heightCtrl = _heightControllers[i];
      final double newW = widthCtrl != null
          ? (double.tryParse(widthCtrl.text) ?? 0)
          : p.width;
      final double newH = heightCtrl != null
          ? (double.tryParse(heightCtrl.text) ?? 0)
          : p.height;
      if ((newW - p.width).abs() > 0.5 || (newH - p.height).abs() > 0.5) {
        // rescaleZones تُحدِّث p.width و p.height داخلياً
        p.rescaleZones(p.width, p.height, newW, newH);
      }

      final qtyCtrl = _quantityControllers[i];
      if (qtyCtrl != null) {
        p.quantity = int.tryParse(qtyCtrl.text) ?? p.quantity;
      }

      final priceCtrl = _priceControllers[i];
      if (priceCtrl != null) {
        final parsedPrice = double.tryParse(priceCtrl.text);
        p.manualPriceOverride = parsedPrice;
        if (parsedPrice != null) {
          p.totalCost = parsedPrice;
        }
      }

      // Update dimensions in description automatically before saving
      final descCtrl = _descControllers[i];
      final currentDesc = descCtrl != null
          ? descCtrl.text.trim()
          : (p.description ?? '');
      p.description = currentDesc.isEmpty
          ? _buildInvoiceLineForProduct(
              p,
              width: newW,
              height: newH,
              quantity: p.quantity,
              price: p.manualPriceOverride ?? p.totalCost,
              description: currentDesc,
              forceGeneratedDetails: true,
            ).details.join('\n')
          : currentDesc;
      // This edited table is the exact source of the Devis row.
      p.invoiceTableEdited = true;
    }
    Navigator.pop(context, true);
  }

  String _updateDimensionsInDescription(
    String desc,
    double width,
    double height,
    WindowModel p,
  ) {
    List<String> lines = desc.split('\n');

    final cleanLines = <String>[];
    for (var line in lines) {
      final l = line.trim();
      final isWidthLine =
          l.startsWith(t('Largeur: ')) ||
          l.startsWith('العرض') ||
          l.startsWith('Width:') ||
          l.startsWith('Largeur:');
      final isHeightLine =
          l.startsWith(t('Hauteur: ')) ||
          l.startsWith('الارتفاع') ||
          l.startsWith('الطول') ||
          l.startsWith('Height:') ||
          l.startsWith('Hauteur:');
      if (!isWidthLine && !isHeightLine) {
        cleanLines.add(line);
      }
    }

    String widthStr = width > 0 ? '${t('Largeur: ')}${width.toInt()} mm' : '';
    String heightStr = height > 0
        ? '${t('Hauteur: ')}${height.toInt()} mm'
        : '';

    if (heightStr.isNotEmpty) {
      cleanLines.insert(0, heightStr);
    }
    if (widthStr.isNotEmpty) {
      cleanLines.insert(0, widthStr);
    }

    return cleanLines.join('\n').trim();
  }

  String _extractValueFromLine(String line) {
    final idx = line.indexOf(':');
    if (idx != -1) {
      return line.substring(idx + 1).trim();
    }
    return '';
  }

  List<String> _replacementLinesForCategory(
    String category,
    String newKey,
    String newValue,
  ) {
    final value = newValue.trim();
    if (value.isEmpty) return const [];

    if (category == 'glass' && (value.contains('\n') || value.contains(':'))) {
      return value
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
    }

    final key = newKey.trim().isEmpty
        ? _defaultKeyForCategory(category)
        : newKey.trim();
    return ['$key $value'.trim()];
  }

  String _defaultKeyForCategory(String category) {
    switch (category) {
      case 'gam':
        return lang == AppLanguage.english
            ? 'Series:'
            : lang == AppLanguage.french
            ? 'Gamme:'
            : 'السلسلة:';
      case 'profileColor':
        return lang == AppLanguage.english
            ? 'Profile color:'
            : lang == AppLanguage.french
            ? 'Couleur profil:'
            : 'لون البروفيل:';
      case 'accessoryColor':
        return lang == AppLanguage.english
            ? 'Accessory color:'
            : lang == AppLanguage.french
            ? 'Couleur accessoire:'
            : 'لون الإكسسوار:';
      case 'shutterColor':
        return lang == AppLanguage.english
            ? 'Shutter color:'
            : lang == AppLanguage.french
            ? 'Couleur volet:'
            : 'لون الستار:';
      case 'glass':
        return lang == AppLanguage.english
            ? 'Glass:'
            : lang == AppLanguage.french
            ? 'Vitrage:'
            : 'الزجاج:';
      case 'cover':
        return lang == AppLanguage.english
            ? 'Cover joint:'
            : lang == AppLanguage.french
            ? 'Couvre-joint:'
            : 'القطعة الجانبية:';
      case 'base':
        return lang == AppLanguage.english
            ? 'Base frame:'
            : lang == AppLanguage.french
            ? 'Cadre de base:'
            : 'الإطار السفلي:';
      case 'closure':
        return lang == AppLanguage.english
            ? 'Closure:'
            : lang == AppLanguage.french
            ? 'Fermeture:'
            : 'نوعية الغلق:';
      case 'shutter':
        return lang == AppLanguage.english
            ? 'Shutter mechanism:'
            : lang == AppLanguage.french
            ? 'Mécanisme volet:'
            : 'ميكانيزم الستار:';
      case 'lame':
        return lang == AppLanguage.english
            ? 'Shutter blade:'
            : lang == AppLanguage.french
            ? 'Lame volet:'
            : 'لام الستار:';
      case 'coulisse':
        return lang == AppLanguage.english
            ? 'Coulisse:'
            : lang == AppLanguage.french
            ? 'Coulisse:'
            : 'كوليس:';
      default:
        return '';
    }
  }

  bool _isCategoryLine(String category, String line, String currentKey) {
    final normalized = line.trim().toLowerCase();
    final key = currentKey.trim().toLowerCase();
    if (key.isNotEmpty && normalized.startsWith(key)) return true;
    if (category == 'glass') return _isGlassDetailLine(line);

    return _categoryPrefixes(category).any((prefix) {
      final p = prefix.toLowerCase();
      return normalized.startsWith(p);
    });
  }

  bool _isGlassDetailLine(String line) {
    final lower = line.trim().toLowerCase();
    return lower.startsWith('remplacement:') ||
        lower.startsWith('vitrage:') ||
        lower.startsWith('glass:') ||
        lower.startsWith('الزجاج:') ||
        lower.startsWith('intérieur:') ||
        lower.startsWith('interieur:') ||
        lower.startsWith('extérieur:') ||
        lower.startsWith('exterieur:') ||
        lower.startsWith('interior:') ||
        lower.startsWith('exterior:') ||
        lower.startsWith('الوجه الداخلي:') ||
        lower.startsWith('الوجه الخارجي:') ||
        lower.startsWith('- ') ||
        lower.startsWith('• ');
  }

  List<String> _categoryPrefixes(String category) {
    switch (category) {
      case 'gam':
        return const [
          'Gamme:',
          'Series:',
          'Série:',
          'Série ',
          'القطاع:',
          'السلسلة:',
        ];
      case 'profileColor':
        return const [
          'Couleur profil:',
          'Couleur Profil:',
          'Profile color:',
          'Profile Color:',
          'لون البروفيل:',
          'لون المقطع:',
          'اللون:',
          'Couleur:',
          'Color:',
        ];
      case 'accessoryColor':
        return const [
          'Couleur accessoire:',
          'Couleur Accessoire:',
          'Accessory color:',
          'Accessory Color:',
          'لون الإكسسوار:',
        ];
      case 'shutterColor':
        return const [
          'Couleur volet:',
          'Couleur Volet:',
          'Shutter color:',
          'Shutter Color:',
          'لون الستار:',
        ];
      case 'cover':
        return const [
          'Couvre-joint:',
          'Cover joint:',
          'Cache latéral:',
          'Cache lateral:',
          'Side cover:',
          'غطاء جانبي:',
          'القطعة الجانبية:',
          'كوفرو جوان:',
        ];
      case 'base':
        return const [
          'Cadre de base:',
          'De base:',
          'Base frame:',
          'الإطار السفلي:',
        ];
      case 'closure':
        return const ['Fermeture:', 'Closure:', 'الإغلاق', 'نوعية الغلق:'];
      case 'shutter':
        return const [
          'Mécanisme volet:',
          'Mecanisme volet:',
          'Shutter mechanism:',
          'Volet:',
          'Shutter:',
          'ستار:',
          'الستار:',
          'ميكانيزم الستار:',
        ];
      case 'lame':
        return const [
          'Lame volet:',
          'Shutter blade:',
          'Lame:',
          'Slats:',
          'الشفرة:',
          'اللام:',
          'لام الستار:',
          'الشرائح:',
        ];
      case 'coulisse':
        return const ['Coulisse:', 'Glissiere:', 'Glissière:', 'كوليس:'];
      default:
        return const [];
    }
  }

  AppLanguage get lang {
    try {
      return Provider.of<AppSettingsProvider>(context, listen: false).language;
    } catch (_) {
      return AppLanguage.arabic;
    }
  }

  Widget _buildGlobalEditCard() {
    return Card(
      elevation: 4,
      color: Colors.blue.shade50,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.blue.shade200, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  t('تعديل الخصائص الموحدة لجميع العناصر (Bulk Edit)'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'اضبط اسم الخاصية وقيمتها واضغط ⚡ للتطبيق على الكل، أو استخدم الزر السفلي للكل:',
              ),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            _buildGlobalRow(
              TextEditingController(),
              _globalTitleController,
              '',
              t('البيان / اسم الموديل'),
              'title',
              isStandalone: true,
            ),
            _buildGlobalRow(
              _globalGamKeyController,
              _globalGamController,
              t('اسم السلسلة'),
              t('قيمة السلسلة'),
              'gam',
            ),
            _buildGlobalRow(
              _globalColorKeyController,
              _globalColorController,
              t('اسم لون البروفيل'),
              t('قيمة لون البروفيل'),
              'profileColor',
            ),
            _buildGlobalRow(
              _globalAccessoryColorKeyController,
              _globalAccessoryColorController,
              t('اسم لون الأكسيسوار'),
              t('قيمة لون الأكسيسوار'),
              'accessoryColor',
            ),
            _buildGlobalRow(
              _globalShutterColorKeyController,
              _globalShutterColorController,
              t('اسم لون الستار'),
              t('قيمة لون الستار'),
              'shutterColor',
            ),
            _buildGlobalRow(
              _globalGlassKeyController,
              _globalGlassController,
              t('اسم الزجاج'),
              t('تفاصيل الزجاج / Vitrage'),
              'glass',
              valueMaxLines: 4,
            ),
            _buildGlobalRow(
              _globalCoverKeyController,
              _globalCoverController,
              t('اسم القطعة الجانبية'),
              t('قيمة القطعة الجانبية'),
              'cover',
            ),
            _buildGlobalRow(
              _globalBaseKeyController,
              _globalBaseController,
              t('اسم الإطار السفلي'),
              t('قيمة الإطار السفلي'),
              'base',
            ),
            _buildGlobalRow(
              _globalClosureKeyController,
              _globalClosureController,
              t('اسم الغلق'),
              t('قيمة الغلق'),
              'closure',
            ),
            _buildGlobalRow(
              _globalShutterKeyController,
              _globalShutterController,
              t('اسم ميكانيزم الستار'),
              t('قيمة الميكانيزم'),
              'shutter',
            ),
            _buildGlobalRow(
              TextEditingController(),
              _globalLameController,
              '',
              t('قيمة اللام (Lame volet)'),
              'lame',
              isStandalone: true,
            ),
            _buildGlobalRow(
              TextEditingController(),
              _globalCoulisseController,
              '',
              t('قيمة الكوليس (Coulisse)'),
              'coulisse',
              isStandalone: true,
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _applyAllGlobalChanges,
              icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
              label: Text(
                t('تطبيق تعديلات الوصف فقط — لا يغيّر السعر'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalRow(
    TextEditingController keyController,
    TextEditingController valueController,
    String keyLabel,
    String valueLabel,
    String category, {
    bool isStandalone = false,
    int valueMaxLines = 1,
  }) {
    final bool isDark = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).isDarkMode;
    final Color inputFillColor = isDark
        ? const Color(0xFF1E293B)
        : Colors.white;
    final Color borderColor = isDark
        ? const Color(0xFF475569)
        : Colors.grey.shade300;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (!isStandalone) ...[
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: keyController,
                decoration: InputDecoration(
                  labelText: keyLabel,
                  labelStyle: TextStyle(color: isDark ? Colors.white60 : null),
                  isDense: true,
                  filled: true,
                  fillColor: inputFillColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: borderColor),
                  ),
                ),
                style: TextStyle(fontSize: 12, color: textColor),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 5,
            child: TextFormField(
              controller: valueController,
              minLines: 1,
              maxLines: valueMaxLines,
              decoration: InputDecoration(
                labelText: valueLabel,
                labelStyle: TextStyle(color: isDark ? Colors.white60 : null),
                isDense: true,
                filled: true,
                fillColor: inputFillColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderColor),
                ),
              ),
              style: TextStyle(fontSize: 12, color: textColor),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: isDark
                  ? Colors.blue.shade900.withValues(alpha: 0.5)
                  : Colors.blue.shade100,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              setState(() {
                _applyGlobalChange(
                  category,
                  isStandalone ? '' : keyController.text.trim(),
                  valueController.text.trim(),
                );
              });
              final msg = (_isSelectionMode && _selectedIndices.isNotEmpty)
                  ? '${t('تم تطبيق التعديل على العناصر المحددة')} (${_selectedIndices.length})'
                  : t('تم تطبيق التعديل بنجاح على جميع العناصر');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(msg), backgroundColor: Colors.green),
              );
            },
            icon: Icon(
              Icons.flash_on_rounded,
              color: isDark ? Colors.blue.shade300 : Colors.blue,
            ),
            tooltip: t('تطبيق على الكل'),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalField(TextEditingController controller, String label) {
    final bool isDark = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).isDarkMode;
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.white60 : null),
        isDense: true,
        filled: true,
        fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF475569) : Colors.grey.shade300,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF475569) : Colors.grey.shade300,
          ),
        ),
      ),
      style: TextStyle(
        fontSize: 13,
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Provider.of<AppSettingsProvider>(context).isDarkMode;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF070E1D) : Colors.grey.shade100,
      appBar: AppBar(
        title: _isSelectionMode
            ? Text(
                '${_selectedIndices.length} ${t('محدد')}',
                style: const TextStyle(color: Colors.white),
              )
            : Text(
                t('تعديل جدول الفاتورة'),
                style: const TextStyle(color: Colors.white),
              ),
        backgroundColor: _isSelectionMode
            ? (isDark ? Colors.deepPurple.shade900 : Colors.deepPurple)
            : (isDark ? const Color(0xFF111827) : Colors.blue),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: t('إلغاء التحديد'),
                onPressed: _exitSelectionMode,
              )
            : null,
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all, color: Colors.white),
              tooltip: t('تحديد الكل'),
              onPressed: () {
                setState(() {
                  for (int i = 0; i < widget.products.length; i++) {
                    _selectedIndices.add(i);
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.deselect, color: Colors.white),
              tooltip: t('إلغاء تحديد الكل'),
              onPressed: () {
                setState(() => _selectedIndices.clear());
              },
            ),
          ],
          IconButton(
            icon: const Icon(Icons.check, color: Colors.white),
            onPressed: _saveAll,
            tooltip: t('حفظ التعديلات'),
          ),
        ],
      ),
      body: widget.products.isEmpty
          ? Center(
              child: Text(
                t('لا توجد منتجات لتعديلها'),
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: widget.products.length > 1
                  ? widget.products.length + 1
                  : widget.products.length,
              itemBuilder: (context, index) {
                if (widget.products.length > 1 && index == 0) {
                  return _buildGlobalEditCard();
                }
                final itemIndex = widget.products.length > 1
                    ? index - 1
                    : index;
                final p = widget.products[itemIndex];
                final isSelected = _selectedIndices.contains(itemIndex);
                return GestureDetector(
                  onLongPress: () => _enterSelectionMode(itemIndex),
                  onTap: _isSelectionMode
                      ? () => _toggleSelection(itemIndex)
                      : null,
                  child: Stack(
                    children: [
                      Card(
                        elevation: _isSelectionMode && isSelected ? 6 : 3,
                        color: _isSelectionMode && isSelected
                            ? (isDark
                                  ? const Color(0xFF2E1B4E)
                                  : Colors.deepPurple.shade50)
                            : p.isReplaced
                            ? (isDark
                                  ? const Color(0xFF2C1E1E)
                                  : Colors.red.shade50)
                            : (isDark ? const Color(0xFF111827) : Colors.white),
                        margin: const EdgeInsets.only(bottom: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: _isSelectionMode && isSelected
                              ? BorderSide(
                                  color: isDark
                                      ? Colors.deepPurple.shade300
                                      : Colors.deepPurple.shade400,
                                  width: 2.5,
                                )
                              : p.isReplaced
                              ? BorderSide(
                                  color: isDark
                                      ? Colors.red.shade700
                                      : Colors.red.shade300,
                                  width: 2,
                                )
                              : (isDark
                                    ? const BorderSide(
                                        color: Color(0xFF334155),
                                        width: 1,
                                      )
                                    : BorderSide.none),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (p.isReplaced)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  margin: const EdgeInsets.only(bottom: 15),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF5A1E1E)
                                        : Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    t('(عنصر مستبدل - غير محسوب في المجموع)'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.redAccent
                                          : Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              TextButton.icon(
                                icon: const Icon(Icons.design_services),
                                label: Text(
                                  t(
                                    'تعديل الرسم والخيارات — اعتماد السعر من جدول الكمية والتكلفة',
                                  ),
                                ),
                                onPressed: () => _editActualDrawing(itemIndex),
                              ),
                              if (_images[itemIndex] != null)
                                Center(
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 15),
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF1F2937)
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0xFF374151)
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: Image.memory(
                                        _images[itemIndex]!,
                                        height: 120,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isDark
                                        ? Colors.blue.shade900.withValues(
                                            alpha: 0.5,
                                          )
                                        : Colors.blue.shade100,
                                    child: Text(
                                      '${itemIndex + 1}',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.blue.shade300
                                            : Colors.blue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _nameControllers[itemIndex],
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: t(
                                          'البيان (الاسم / الموديل)',
                                        ),
                                        labelStyle: TextStyle(
                                          color: isDark ? Colors.white60 : null,
                                        ),
                                        border: const OutlineInputBorder(),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: isDark
                                                ? const Color(0xFF374151)
                                                : Colors.black26,
                                          ),
                                        ),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 15),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _widthControllers[itemIndex],
                                      keyboardType: TextInputType.number,
                                      onChanged: (val) =>
                                          _onFieldChanged(itemIndex),
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: t('العرض (mm)'),
                                        labelStyle: TextStyle(
                                          color: isDark ? Colors.white60 : null,
                                        ),
                                        border: const OutlineInputBorder(),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: isDark
                                                ? const Color(0xFF374151)
                                                : Colors.black26,
                                          ),
                                        ),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _heightControllers[itemIndex],
                                      keyboardType: TextInputType.number,
                                      onChanged: (val) =>
                                          _onFieldChanged(itemIndex),
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: t('الارتفاع (mm)'),
                                        labelStyle: TextStyle(
                                          color: isDark ? Colors.white60 : null,
                                        ),
                                        border: const OutlineInputBorder(),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: isDark
                                                ? const Color(0xFF374151)
                                                : Colors.black26,
                                          ),
                                        ),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller:
                                          _quantityControllers[itemIndex],
                                      keyboardType: TextInputType.number,
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: t('الكمية'),
                                        labelStyle: TextStyle(
                                          color: isDark ? Colors.white60 : null,
                                        ),
                                        border: const OutlineInputBorder(),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: isDark
                                                ? const Color(0xFF374151)
                                                : Colors.black26,
                                          ),
                                        ),
                                        isDense: true,
                                      ),
                                      onChanged: (val) {
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 15),
                              TextFormField(
                                controller: _descControllers[itemIndex],
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  labelText: t(
                                    'التفاصيل المطبوعة في الـ PDF (يمكنك مسح وتعديل أي شيء)',
                                  ),
                                  labelStyle: TextStyle(
                                    color: isDark ? Colors.white60 : null,
                                  ),
                                  border: const OutlineInputBorder(),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? const Color(0xFF374151)
                                          : Colors.black26,
                                    ),
                                  ),
                                  isDense: true,
                                  filled: true,
                                  fillColor: isDark
                                      ? const Color(0xFF2D2A1E)
                                      : Colors.yellow.shade50,
                                ),
                              ),
                              const SizedBox(height: 15),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _priceControllers[itemIndex],
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.greenAccent
                                            : Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: t('سعر الوحدة (دج)'),
                                        labelStyle: TextStyle(
                                          color: isDark ? Colors.white60 : null,
                                        ),
                                        border: const OutlineInputBorder(),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: isDark
                                                ? const Color(0xFF374151)
                                                : Colors.black26,
                                          ),
                                        ),
                                        isDense: true,
                                        prefixIcon: Icon(
                                          Icons.attach_money,
                                          color: isDark
                                              ? Colors.greenAccent
                                              : Colors.green,
                                        ),
                                      ),
                                      onChanged: (val) {
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 15),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          t('السعر الإجمالي'),
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white60
                                                : Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          '${((double.tryParse(_priceControllers[itemIndex]!.text) ?? 0.0) * (int.tryParse(_quantityControllers[itemIndex]!.text) ?? 0)).toStringAsFixed(2)} ${t('دج')}',
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.lightBlueAccent
                                                : Colors.blue,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ), // Column
                        ), // Padding (Card child)
                      ), // Card
                      // ─── Checkbox overlay in selection mode ───
                      if (_isSelectionMode)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: IgnorePointer(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? Colors.deepPurple
                                    : Colors.white.withValues(alpha: 0.85),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.deepPurple
                                      : Colors.grey.shade400,
                                  width: 2,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 16,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ); // GestureDetector
              },
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          border: isDark
              ? const Border(
                  top: BorderSide(color: Color(0xFF334155), width: 1),
                )
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.grey.shade300,
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            minimumSize: const Size(double.infinity, 55),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          onPressed: _saveAll,
          icon: const Icon(Icons.save, color: Colors.white),
          label: Text(
            t('حفظ جميع التعديلات'),
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
