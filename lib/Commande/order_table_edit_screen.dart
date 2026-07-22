import 'package:flutter/material.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:database_data/Commande/capture_image.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
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

  String t(String key) {
    try {
      final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
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

  final _globalColorKeyController = TextEditingController();
  final _globalColorController = TextEditingController();

  final _globalGlassKeyController = TextEditingController();
  final _globalGlassController = TextEditingController();

  final _globalCoverKeyController = TextEditingController();
  final _globalCoverController = TextEditingController();

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

    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final p = widget.products[index];
      final double newW =
          double.tryParse(_widthControllers[index]!.text) ?? 0;
      final double newH =
          double.tryParse(_heightControllers[index]!.text) ?? 0;

      // Update the description text box dynamically!
      final currentDesc = _descControllers[index]!.text;
      final newDesc = _updateDimensionsInDescription(currentDesc, newW, newH, p);
      if (currentDesc != newDesc) {
        // Keep cursor position
        final selection = _descControllers[index]!.selection;
        _descControllers[index]!.text = newDesc;
        // Attempt to restore selection if it's within bounds
        if (selection.isValid && selection.end <= newDesc.length) {
          _descControllers[index]!.selection = selection;
        } else {
          _descControllers[index]!.selection = TextSelection.collapsed(offset: newDesc.length);
        }
      }

      // ─── معاينة الصورة بنموذج مؤقت (لا نُعدّل النموذج الأصلي هنا) ───
      // نبني نسخة مؤقتة بالأبعاد الجديدة لالتقاط الصورة فقط
      final tempModel = WindowModel(db: p.db);
      applyWindowModelFromMap(tempModel, p.toMap());
      tempModel.availableSystems = List.from(p.availableSystems);
      tempModel.activeSeries = p.activeSeries;
      tempModel.activeSlidingSeries = p.activeSlidingSeries;
      tempModel.availableColors = List.from(p.availableColors);

      // نطبّق إعادة التحجيم على النموذج المؤقت فقط
      if ((newW - p.width).abs() > 0.5 || (newH - p.height).abs() > 0.5) {
        tempModel.rescaleZones(p.width, p.height, newW, newH);
      }

      captureWindowImage(tempModel, maxSide: 400).then((img) {
        if (mounted) {
          setState(() {
            _images[index] = img;
          });
        }
      }).catchError((e) {
        debugPrint('Error capturing window image in _onFieldChanged: $e');
      });
    });
  }

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < widget.products.length; i++) {
      final p = widget.products[i];

      // Name
      final isSliding = p.zones.any((z) => z.content == ZoneContent.slidingSash);
      String defaultName = '';
      if (p.isShutterOnly) {
        defaultName = 'Volet roulant';
      } else {
        if (lang == AppLanguage.french) {
          defaultName = isSliding ? 'Fenêtre coulissante' : 'Fenêtre ouvrante';
        } else if (lang == AppLanguage.english) {
          defaultName = isSliding ? 'Sliding window' : 'Casement window';
        } else {
          defaultName = isSliding ? 'نافذة منزلقة' : 'نافذة مفصلية';
        }
      }

      if (p.activeSeries != null ||
          (p.loadedSeriesName != null && p.loadedSeriesName!.isNotEmpty)) {
        final series = p.activeSeries?.name ?? p.loadedSeriesName;
        defaultName = '$series - $defaultName'; // Reversed title! Series first!
      }
      _nameControllers[i] = TextEditingController(
        text: p.manualNameOverride ?? defaultName,
      );

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
      String initialDesc = p.description ?? _generateDefaultDetails(p);
      _descControllers[i] = TextEditingController(text: initialDesc);

      captureWindowImage(p, maxSide: 400).then((img) {
        if (mounted) setState(() => _images[i] = img);
      }).catchError((e) {
        debugPrint('Error capturing window image in initState: $e');
      });
    }

    _extractGlobalValues();
  }

  void _extractGlobalValues() {
    final gamKeys = <String>[];
    final gams = <String>[];

    final colorKeys = <String>[];
    final colors = <String>[];

    final glassKeys = <String>[];
    final glasses = <String>[];

    final coverKeys = <String>[];
    final covers = <String>[];

    final shutterKeys = <String>[];
    final shutters = <String>[];

    final widthKeys = <String>[];
    final widths = <String>[];

    final heightKeys = <String>[];
    final heights = <String>[];

    final handleHKeys = <String>[];
    final handleHs = <String>[];

    final lames = <String>[];
    final coulisses = <String>[];

    for (int i = 0; i < widget.products.length; i++) {
      final p = widget.products[i];
      if (p.isReplaced) continue; // Skip replaced/crossed-out elements!
      final desc = _descControllers[i]?.text ?? _generateDefaultDetails(p);
      final lines = desc.split('\n');
      for (var line in lines) {
        final l = line.trim();
        if (l.startsWith('القطاع:') || l.startsWith('Gamme:') || l.startsWith('Série ') || l.startsWith('Série:')) {
          final idx = l.indexOf(':');
          if (idx != -1) {
            gamKeys.add(l.substring(0, idx + 1));
            gams.add(l.substring(idx + 1).trim());
          } else {
            gams.add(l);
          }
        } else if (l.startsWith('اللون:') || l.startsWith('Couleur:') || l.startsWith('Color:')) {
          final idx = l.indexOf(':');
          if (idx != -1) {
            colorKeys.add(l.substring(0, idx + 1));
            colors.add(l.substring(idx + 1).trim());
          } else {
            colors.add(l);
          }
        } else if (l.startsWith('الزجاج:') || l.startsWith('Vitrage:') || l.startsWith('Glass:')) {
          final idx = l.indexOf(':');
          if (idx != -1) {
            glassKeys.add(l.substring(0, idx + 1));
            glasses.add(l.substring(idx + 1).trim());
          } else {
            glasses.add(l);
          }
        } else if (l.startsWith('غطاء جانبي:') || l.startsWith('Couvre-joint:') || l.startsWith('Cover joint:') || l.startsWith('Cache latéral:') || l.startsWith('Side cover:') || l.startsWith('Cache lateral:')) {
          final idx = l.indexOf(':');
          if (idx != -1) {
            coverKeys.add(l.substring(0, idx + 1));
            covers.add(l.substring(idx + 1).trim());
          } else {
            covers.add(l);
          }
        } else if (l.startsWith('ستار:') || l.startsWith('Volet:') || l.startsWith('Shutter:')) {
          final idx = l.indexOf(':');
          if (idx != -1) {
            shutterKeys.add(l.substring(0, idx + 1));
            shutters.add(l.substring(idx + 1).trim());
          } else {
            shutters.add(l);
          }
        } else if (l.startsWith('العرض:') || l.startsWith('Largeur:') || l.startsWith('Width:')) {
          final idx = l.indexOf(':');
          if (idx != -1) {
            widthKeys.add(l.substring(0, idx + 1));
            widths.add(l.substring(idx + 1).replaceAll('mm', '').trim());
          } else {
            widths.add(l.replaceAll('mm', '').trim());
          }
        } else if (l.startsWith('الارتفاع:') || l.startsWith('Hauteur:') || l.startsWith('Height:')) {
          final idx = l.indexOf(':');
          if (idx != -1) {
            heightKeys.add(l.substring(0, idx + 1));
            heights.add(l.substring(idx + 1).replaceAll('mm', '').trim());
          } else {
            heights.add(l.replaceAll('mm', '').trim());
          }
        } else if (l.startsWith('ارتفاع المقبض:') || l.startsWith('Hauteur Poignée:') || l.startsWith('Handle Height:')) {
          final idx = l.indexOf(':');
          if (idx != -1) {
            handleHKeys.add(l.substring(0, idx + 1));
            handleHs.add(l.substring(idx + 1).replaceAll('mm', '').trim());
          } else {
            handleHs.add(l.replaceAll('mm', '').trim());
          }
        } else if (l.contains('شفرات') || l.contains('Slats') || l.contains('Lames')) {
          lames.add(l);
        } else if (l.contains('كوليس') || l.contains('Coulisse') || l.contains('Glissiere') || l.contains('Glissière')) {
          coulisses.add(l);
        }
      }
    }

    if (gamKeys.isNotEmpty) _globalGamKeyController.text = _mostCommon(gamKeys);
    if (gams.isNotEmpty) _globalGamController.text = _mostCommon(gams);

    if (colorKeys.isNotEmpty) _globalColorKeyController.text = _mostCommon(colorKeys);
    if (colors.isNotEmpty) _globalColorController.text = _mostCommon(colors);

    if (glassKeys.isNotEmpty) _globalGlassKeyController.text = _mostCommon(glassKeys);
    if (glasses.isNotEmpty) _globalGlassController.text = _mostCommon(glasses);

    if (coverKeys.isNotEmpty) _globalCoverKeyController.text = _mostCommon(coverKeys);
    if (covers.isNotEmpty) _globalCoverController.text = _mostCommon(covers);

    if (shutterKeys.isNotEmpty) _globalShutterKeyController.text = _mostCommon(shutterKeys);
    if (shutters.isNotEmpty) _globalShutterController.text = _mostCommon(shutters);

    if (widthKeys.isNotEmpty) _globalWidthKeyController.text = _mostCommon(widthKeys);
    if (widths.isNotEmpty) _globalWidthController.text = _mostCommon(widths);

    if (heightKeys.isNotEmpty) _globalHeightKeyController.text = _mostCommon(heightKeys);
    if (heights.isNotEmpty) _globalHeightController.text = _mostCommon(heights);

    if (handleHKeys.isNotEmpty) _globalHandleHKeyController.text = _mostCommon(handleHKeys);
    if (handleHs.isNotEmpty) _globalHandleHController.text = _mostCommon(handleHs);

    if (lames.isNotEmpty) _globalLameController.text = _mostCommon(lames);
    if (coulisses.isNotEmpty) _globalCoulisseController.text = _mostCommon(coulisses);
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
    final currentGamKey = _globalGamKeyController.text.trim();
    final currentColorKey = _globalColorKeyController.text.trim();
    final currentGlassKey = _globalGlassKeyController.text.trim();
    final currentCoverKey = _globalCoverKeyController.text.trim();
    final currentShutterKey = _globalShutterKeyController.text.trim();

    final currentWidthKey = _globalWidthKeyController.text.trim();
    final currentHeightKey = _globalHeightKeyController.text.trim();
    final currentHandleHKey = _globalHandleHKeyController.text.trim();

    // Only apply to selected items when in selection mode
    final targetIndices = (_isSelectionMode && _selectedIndices.isNotEmpty)
        ? _selectedIndices.toList()
        : List.generate(widget.products.length, (i) => i);

    for (final i in targetIndices) {
      final p = widget.products[i];
      if (p.isReplaced) continue; // Skip replaced/crossed-out elements!

      // ─── Apply modifications immediately to model values/controllers ONLY if newValue is not empty ───
      if (newValue.isNotEmpty) {
        if (category == 'width') {
          final val = double.tryParse(newValue);
          if (val != null) {
            _widthControllers[i]?.text = val.toInt().toString();
            p.rescaleZones(p.width, p.height, val, p.height);
          }
        } else if (category == 'height') {
          final val = double.tryParse(newValue);
          if (val != null) {
            _heightControllers[i]?.text = val.toInt().toString();
            p.rescaleZones(p.width, p.height, p.width, val);
          }
        } else if (category == 'handleH') {
          final val = double.tryParse(newValue);
          if (val != null && p.zones.isNotEmpty) {
            final z = p.zones.first;
            final hVal = double.tryParse(_heightControllers[i]?.text ?? '') ?? p.height;
            if (hVal > 0) {
              double ratio = 1.0 - (val / hVal);
              if (ratio < 0.0) ratio = 0.0;
              if (ratio > 1.0) ratio = 1.0;
              z.handlePositionRatio = ratio;
            }
          }
        }
      }

      final desc = _descControllers[i]!.text;
      final lines = desc.split('\n');
      final newLines = <String>[];
      bool found = false;

      for (var line in lines) {
        final l = line.trim();
        bool match = false;
        if (category == 'gam') {
          match = (currentGamKey.isNotEmpty && l.startsWith(currentGamKey)) ||
                  l.startsWith('القطاع:') || l.startsWith('Gamme:') || l.startsWith('Série ') || l.startsWith('Série:');
        } else if (category == 'color') {
          match = (currentColorKey.isNotEmpty && l.startsWith(currentColorKey)) ||
                  l.startsWith('اللون:') || l.startsWith('Couleur:') || l.startsWith('Color:');
        } else if (category == 'glass') {
          match = (currentGlassKey.isNotEmpty && l.startsWith(currentGlassKey)) ||
                  l.startsWith('الزجاج:') || l.startsWith('Vitrage:') || l.startsWith('Glass:');
        } else if (category == 'cover') {
          match = (currentCoverKey.isNotEmpty && l.startsWith(currentCoverKey)) ||
                  l.startsWith('غطاء جانبي:') || l.startsWith('Couvre-joint:') || l.startsWith('Cover joint:') || l.startsWith('Cache latéral:') || l.startsWith('Side cover:') || l.startsWith('Cache lateral:');
        } else if (category == 'shutter') {
          match = (currentShutterKey.isNotEmpty && l.startsWith(currentShutterKey)) ||
                  l.startsWith('ستار:') || l.startsWith('Volet:') || l.startsWith('Shutter:');
        } else if (category == 'width') {
          match = (currentWidthKey.isNotEmpty && l.startsWith(currentWidthKey)) ||
                  l.startsWith('العرض:') || l.startsWith('Largeur:') || l.startsWith('Width:');
        } else if (category == 'height') {
          match = (currentHeightKey.isNotEmpty && l.startsWith(currentHeightKey)) ||
                  l.startsWith('الارتفاع:') || l.startsWith('Hauteur:') || l.startsWith('Height:');
        } else if (category == 'handleH') {
          match = (currentHandleHKey.isNotEmpty && l.startsWith(currentHandleHKey)) ||
                  l.startsWith('ارتفاع المقبض:') || l.startsWith('Hauteur Poignée:') || l.startsWith('Handle Height:');
        } else if (category == 'lame') {
          match = l.contains('شفرات') || l.contains('Slats') || l.contains('Lames');
        } else if (category == 'coulisse') {
          match = l.contains('كوليس') || l.contains('Coulisse') || l.contains('Glissiere') || l.contains('Glissière');
        }

        if (match) {
          if (category == 'lame' || category == 'coulisse') {
            if (newValue.isNotEmpty) {
              newLines.add(newValue);
            } else {
              newLines.add(line); // Keep unchanged if newValue is empty
            }
          } else {
            if (newKey.isNotEmpty || newValue.isNotEmpty) {
              final defaultKey = category == 'gam'
                  ? 'القطاع:'
                  : category == 'color'
                      ? 'اللون:'
                      : category == 'glass'
                          ? 'الزجاج:'
                          : category == 'cover'
                              ? 'غطاء جانبي:'
                              : category == 'width'
                                  ? 'العرض:'
                                  : category == 'height'
                                      ? 'الارتفاع:'
                                      : category == 'handleH'
                                          ? 'ارتفاع المقبض:'
                                          : 'ستار:';
              final finalKey = newKey.isEmpty ? defaultKey : newKey;
              final finalValue = newValue.isEmpty ? _extractValueFromLine(l) : newValue;
              final suffix = (category == 'width' || category == 'height' || category == 'handleH') && !finalValue.endsWith('mm') && finalValue.isNotEmpty
                  ? '$finalValue mm'
                  : finalValue;
              newLines.add('$finalKey $suffix'.trim());
            } else {
              newLines.add(line);
            }
          }
          found = true;
        } else {
          newLines.add(line);
        }
      }

      if (!found && newValue.isNotEmpty) {
        final defaultKey = category == 'gam'
            ? 'القطاع:'
            : category == 'color'
                ? 'اللون:'
                : category == 'glass'
                    ? 'الزجاج:'
                    : category == 'cover'
                        ? 'غطاء جانبي:'
                        : category == 'width'
                            ? 'العرض:'
                            : category == 'height'
                                ? 'الارتفاع:'
                                : category == 'handleH'
                                    ? 'ارتفاع المقبض:'
                                    : 'ستار:';
        if (category == 'lame') {
          newLines.add(newValue);
        } else if (category == 'coulisse') {
          newLines.add(newValue);
        } else {
          final suffix = (category == 'width' || category == 'height' || category == 'handleH') && !newValue.endsWith('mm')
              ? '$newValue mm'
              : newValue;
          newLines.add('${newKey.isEmpty ? defaultKey : newKey} $suffix'.trim());
        }
      }

      _descControllers[i]!.text = newLines.join('\n');
    }
  }

  void _applyAllGlobalChanges() {
    setState(() {
      _applyGlobalChange('gam', _globalGamKeyController.text.trim(), _globalGamController.text.trim());
      _applyGlobalChange('color', _globalColorKeyController.text.trim(), _globalColorController.text.trim());
      _applyGlobalChange('glass', _globalGlassKeyController.text.trim(), _globalGlassController.text.trim());
      _applyGlobalChange('cover', _globalCoverKeyController.text.trim(), _globalCoverController.text.trim());
      _applyGlobalChange('shutter', _globalShutterKeyController.text.trim(), _globalShutterController.text.trim());
      _applyGlobalChange('width', _globalWidthKeyController.text.trim(), _globalWidthController.text.trim());
      _applyGlobalChange('height', _globalHeightKeyController.text.trim(), _globalHeightController.text.trim());
      _applyGlobalChange('handleH', _globalHandleHKeyController.text.trim(), _globalHandleHController.text.trim());
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
    String gamName = p.activeSeries?.name ?? p.loadedSeriesName ?? '';
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
    final String profColor = p.selectedDbColor?['name']?.toString() ?? _colorLabelLocal(p.frameColor.toString().split('.').last, curLang);
    final String accColor = p.selectedAccessoryColor?['name']?.toString() ?? profColor;

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
        final bool isLeftOrRight = z.openDirection == OpenDirection.left || z.openDirection == OpenDirection.right;

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
      final isDouble = p.zones.isNotEmpty && p.zones.first.glass.structure == GlassStructure.double;
      if (curLang == AppLanguage.french) {
        details.add(isDouble ? 'Vitrage: Double' : 'Vitrage: Simple');
      } else if (curLang == AppLanguage.english) {
        details.add(isDouble ? 'Glass: Double' : 'Glass: Single');
      } else {
        details.add(isDouble ? 'الزجاج: مزدوج (Double Vitrage)' : 'الزجاج: مفرد (Simple Vitrage)');
      }
    }

    // 7. Couvre-joint (Side Covers) — window only, never for standalone volet
    if (!p.isShutterOnly && p.hasSideCovers) {
      final removed = p.removedShutterSides.map((s) => s.toLowerCase()).toSet();
      final hasL = !removed.contains('left');
      final hasR = !removed.contains('right');
      final hasT = !removed.contains('top');
      final hasB = !removed.contains('bottom') && p.hasBottomFrame;

      if (curLang == AppLanguage.french) {
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
      final isPVC = (p.activeSeries?.name?.toLowerCase().contains('pvc') ?? false);
      bool useEntrematique = false;
      bool hasKeyLock = false;
      bool hasSliding = false;
      bool hasCentralReinforced = false;
      bool hasCentralSimple = false;
      bool hasLateralReinforced = false;

      // Use toMap() zones (same data as devis_builder uses)
      final pMap = p.toMap();
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
          if (reinforcedMap != null) {
            if (reinforcedMap['lateral_0'] == true || reinforcedMap['lateral_1'] == true) {
              hasLateralReinforced = true;
            }
            bool centralFound = false;
            bool centralReinforced = false;
            reinforcedMap.forEach((k, v) {
              if (k.toString().startsWith('central_')) {
                centralFound = true;
                if (v == true) centralReinforced = true;
              }
            });
            if (centralFound) {
              if (centralReinforced) hasCentralReinforced = true;
              else hasCentralSimple = true;
            }
          } else {
            hasCentralSimple = true;
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
        final useOctoHandle = z['useOctoHandle'] == true || z['useOctoHandle']?.toString() == 'true';
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

      // Montant renforcé
      if (hasSliding) {
        if (curLang == AppLanguage.french) {
          details.add('Montant latéral: ${hasLateralReinforced ? "renforcé" : "simple"}');
          details.add('Montant central: ${hasCentralReinforced ? "renforcé" : "simple"}');
        } else if (curLang == AppLanguage.english) {
          details.add('Lateral montant: ${hasLateralReinforced ? "reinforced" : "simple"}');
          details.add('Central montant: ${hasCentralReinforced ? "reinforced" : "simple"}');
        } else {
          details.add('مقطع جانبي (Montant latéral): ${hasLateralReinforced ? "مدعم" : "عادي"}');
          details.add('مقطع وسطي (Montant central): ${hasCentralReinforced ? "مدعم" : "عادي"}');
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
          details.add(glis.replaceAll('Glissiere', 'Coulisse').replaceAll('Glissière', 'Coulisse'));
        } else if (curLang == AppLanguage.english) {
          details.add(glis.replaceAll('Glissiere', 'Slide').replaceAll('Glissière', 'Slide'));
        } else {
          details.add(glis.replaceAll('Glissiere', 'كوليس').replaceAll('Glissière', 'كوليس'));
        }
      }
    }

    return details.join('\n');
  }

  static String _colorLabelLocal(String color, AppLanguage curLang) {
    final lower = color.toLowerCase();
    if (curLang == AppLanguage.french) {
      if (lower == 'white' || lower == 'blanc' || lower == 'أبيض') return 'Blanc';
      if (lower == 'gray' || lower == 'grey' || lower == 'gris' || lower == 'رمادي') return 'Gris';
      if (lower == 'brown' || lower == 'faux bois' || lower == 'بني') return 'Faux Bois';
      if (lower == 'black' || lower == 'noir' || lower == 'أسود') return 'Noir';
      if (lower == 'beige' || lower == 'بيج') return 'Beige';
      return color;
    } else if (curLang == AppLanguage.english) {
      if (lower == 'white' || lower == 'blanc' || lower == 'أبيض') return 'White';
      if (lower == 'gray' || lower == 'grey' || lower == 'gris' || lower == 'رمادي') return 'Grey';
      if (lower == 'brown' || lower == 'faux bois' || lower == 'بني') return 'Wood Faux';
      if (lower == 'black' || lower == 'noir' || lower == 'أسود') return 'Black';
      if (lower == 'beige' || lower == 'بيج') return 'Beige';
      return color;
    } else {
      if (lower == 'white' || lower == 'blanc' || lower == 'أبيض') return 'أبيض';
      if (lower == 'gray' || lower == 'grey' || lower == 'gris' || lower == 'رمادي') return 'رمادي';
      if (lower == 'brown' || lower == 'faux bois' || lower == 'بني') return 'بني';
      if (lower == 'black' || lower == 'noir' || lower == 'أسود') return 'أسود';
      if (lower == 'beige' || lower == 'بيج') return 'بيج';
      return color;
    }
  }

  @override
  void dispose() {
    _globalGamKeyController.dispose();
    _globalGamController.dispose();
    _globalColorKeyController.dispose();
    _globalColorController.dispose();
    _globalGlassKeyController.dispose();
    _globalGlassController.dispose();
    _globalCoverKeyController.dispose();
    _globalCoverController.dispose();
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
      p.manualNameOverride = _nameControllers[i]!.text.trim();

      // ─── تطبيق إعادة التحجيم مرة واحدة من الأبعاد الأصلية ───
      final double newW =
          double.tryParse(_widthControllers[i]!.text) ?? 0;
      final double newH =
          double.tryParse(_heightControllers[i]!.text) ?? 0;
      if ((newW - p.width).abs() > 0.5 || (newH - p.height).abs() > 0.5) {
        // rescaleZones تُحدِّث p.width و p.height داخلياً
        p.rescaleZones(p.width, p.height, newW, newH);
      }

      p.quantity = int.tryParse(_quantityControllers[i]!.text) ?? p.quantity;
      final parsedPrice = double.tryParse(_priceControllers[i]!.text);
      p.manualPriceOverride = parsedPrice;
      if (parsedPrice != null) {
        p.totalCost = parsedPrice;
      }
      
      // Update dimensions in description automatically before saving
      final currentDesc = _descControllers[i]!.text.trim();
      p.description = _updateDimensionsInDescription(currentDesc, newW, newH, p);
    }
    Navigator.pop(context, true);
  }

  String _updateDimensionsInDescription(String desc, double width, double height, WindowModel p) {
    List<String> lines = desc.split('\n');
    
    final cleanLines = <String>[];
    for (var line in lines) {
      final l = line.trim();
      final isWidthLine = l.startsWith(t('Largeur: ')) || l.startsWith('العرض') || l.startsWith('Width:') || l.startsWith('Largeur:');
      final isHeightLine = l.startsWith(t('Hauteur: ')) || l.startsWith('الارتفاع') || l.startsWith('الطول') || l.startsWith('Height:') || l.startsWith('Hauteur:');
      if (!isWidthLine && !isHeightLine) {
        cleanLines.add(line);
      }
    }

    String widthStr = width > 0 ? '${t('Largeur: ')}${width.toInt()} mm' : '';
    String heightStr = height > 0 ? '${t('Hauteur: ')}${height.toInt()} mm' : '';

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
              t('اضبط اسم الخاصية وقيمتها واضغط ⚡ للتطبيق على الكل، أو استخدم الزر السفلي للكل:'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            _buildGlobalRow(_globalGamKeyController, _globalGamController, t('اسم القطاع'), t('قيمة القطاع'), 'gam'),
            _buildGlobalRow(_globalColorKeyController, _globalColorController, t('اسم اللون'), t('قيمة اللون'), 'color'),
            _buildGlobalRow(_globalGlassKeyController, _globalGlassController, t('اسم الزجاج'), t('قيمة الزجاج'), 'glass'),
            _buildGlobalRow(_globalCoverKeyController, _globalCoverController, t('اسم الغطاء الجانبي'), t('قيمة الغطاء'), 'cover'),
            _buildGlobalRow(_globalShutterKeyController, _globalShutterController, t('اسم الستار'), t('قيمة الستار'), 'shutter'),
            _buildGlobalRow(_globalWidthKeyController, _globalWidthController, t('اسم العرض'), t('قيمة العرض'), 'width'),
            _buildGlobalRow(_globalHeightKeyController, _globalHeightController, t('اسم الارتفاع'), t('قيمة الارتفاع'), 'height'),
            _buildGlobalRow(_globalHandleHKeyController, _globalHandleHController, t('اسم ارتفاع المقبض'), t('قيمة ارتفاع المقبض'), 'handleH'),
            _buildGlobalRow(TextEditingController(), _globalLameController, '', t('قيمة الشفرات (Lames)'), 'lame', isStandalone: true),
            _buildGlobalRow(TextEditingController(), _globalCoulisseController, '', t('قيمة المجرى (Coulisse)'), 'coulisse', isStandalone: true),
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
                t('تطبيق جميع الخصائص معاً'),
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
    String category,
    {bool isStandalone = false}
  ) {
    final bool isDark = Provider.of<AppSettingsProvider>(context, listen: false).isDarkMode;
    final Color inputFillColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color borderColor = isDark ? const Color(0xFF475569) : Colors.grey.shade300;
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
              backgroundColor: isDark ? Colors.blue.shade900.withValues(alpha: 0.5) : Colors.blue.shade100,
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
                  ? t('تم تطبيق التعديل على العناصر المحددة (${_selectedIndices.length})')
                  : t('تم تطبيق التعديل بنجاح على جميع العناصر');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(msg),
                  backgroundColor: Colors.green,
                ),
              );
            },
            icon: Icon(Icons.flash_on_rounded, color: isDark ? Colors.blue.shade300 : Colors.blue),
            tooltip: t('تطبيق على الكل'),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalField(TextEditingController controller, String label) {
    final bool isDark = Provider.of<AppSettingsProvider>(context, listen: false).isDarkMode;
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
          borderSide: BorderSide(color: isDark ? const Color(0xFF475569) : Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: isDark ? const Color(0xFF475569) : Colors.grey.shade300),
        ),
      ),
      style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Provider.of<AppSettingsProvider>(context).isDarkMode;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF070E1D) : Colors.grey.shade100,
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('${_selectedIndices.length} ${t('محدد')}', style: const TextStyle(color: Colors.white))
            : Text(t('تعديل جدول الفاتورة'), style: const TextStyle(color: Colors.white)),
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
            tooltip: 'حفظ التعديلات',
          ),
        ],
      ),
      body: widget.products.isEmpty
          ? Center(child: Text(t('لا توجد منتجات لتعديلها'), style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)))
          : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: widget.products.length > 1 ? widget.products.length + 1 : widget.products.length,
              itemBuilder: (context, index) {
                if (widget.products.length > 1 && index == 0) {
                  return _buildGlobalEditCard();
                }
                final itemIndex = widget.products.length > 1 ? index - 1 : index;
                final p = widget.products[itemIndex];
                final isSelected = _selectedIndices.contains(itemIndex);
                return GestureDetector(
                  onLongPress: () => _enterSelectionMode(itemIndex),
                  onTap: _isSelectionMode ? () => _toggleSelection(itemIndex) : null,
                  child: Stack(
                    children: [
                      Card(
                        elevation: _isSelectionMode && isSelected ? 6 : 3,
                        color: _isSelectionMode && isSelected
                            ? (isDark ? const Color(0xFF2E1B4E) : Colors.deepPurple.shade50)
                            : p.isReplaced
                                ? (isDark ? const Color(0xFF2C1E1E) : Colors.red.shade50)
                                : (isDark ? const Color(0xFF111827) : Colors.white),
                        margin: const EdgeInsets.only(bottom: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: _isSelectionMode && isSelected
                              ? BorderSide(color: isDark ? Colors.deepPurple.shade300 : Colors.deepPurple.shade400, width: 2.5)
                              : p.isReplaced
                                  ? BorderSide(color: isDark ? Colors.red.shade700 : Colors.red.shade300, width: 2)
                                  : (isDark ? const BorderSide(color: Color(0xFF334155), width: 1) : BorderSide.none),
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
                              color: isDark ? const Color(0xFF5A1E1E) : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              t('(عنصر مستبدل - غير محسوب في المجموع)'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark ? Colors.redAccent : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        if (_images[itemIndex] != null)
                          Center(
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 15),
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDark ? const Color(0xFF374151) : Colors.grey.shade300),
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
                              backgroundColor: isDark ? Colors.blue.shade900.withValues(alpha: 0.5) : Colors.blue.shade100,
                              child: Text(
                                '${itemIndex + 1}',
                                style: TextStyle(
                                  color: isDark ? Colors.blue.shade300 : Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _nameControllers[itemIndex],
                                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                decoration: InputDecoration(
                                  labelText: t('البيان (الاسم / الموديل)'),
                                  labelStyle: TextStyle(color: isDark ? Colors.white60 : null),
                                  border: const OutlineInputBorder(),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: isDark ? const Color(0xFF374151) : Colors.black26),
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
                                onChanged: (val) => _onFieldChanged(itemIndex),
                                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                decoration: InputDecoration(
                                  labelText: t('العرض (mm)'),
                                  labelStyle: TextStyle(color: isDark ? Colors.white60 : null),
                                  border: const OutlineInputBorder(),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: isDark ? const Color(0xFF374151) : Colors.black26),
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
                                onChanged: (val) => _onFieldChanged(itemIndex),
                                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                decoration: InputDecoration(
                                  labelText: t('الارتفاع (mm)'),
                                  labelStyle: TextStyle(color: isDark ? Colors.white60 : null),
                                  border: const OutlineInputBorder(),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: isDark ? const Color(0xFF374151) : Colors.black26),
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _quantityControllers[itemIndex],
                                keyboardType: TextInputType.number,
                                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                decoration: InputDecoration(
                                  labelText: t('الكمية'),
                                  labelStyle: TextStyle(color: isDark ? Colors.white60 : null),
                                  border: const OutlineInputBorder(),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: isDark ? const Color(0xFF374151) : Colors.black26),
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
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                          decoration: InputDecoration(
                            labelText:
                                t('التفاصيل المطبوعة في الـ PDF (يمكنك مسح وتعديل أي شيء)'),
                            labelStyle: TextStyle(color: isDark ? Colors.white60 : null),
                            border: const OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: isDark ? const Color(0xFF374151) : Colors.black26),
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: isDark ? const Color(0xFF2D2A1E) : Colors.yellow.shade50,
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
                                  color: isDark ? Colors.greenAccent : Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: InputDecoration(
                                  labelText: t('سعر الوحدة (دج)'),
                                  labelStyle: TextStyle(color: isDark ? Colors.white60 : null),
                                  border: const OutlineInputBorder(),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: isDark ? const Color(0xFF374151) : Colors.black26),
                                  ),
                                  isDense: true,
                                  prefixIcon: Icon(
                                    Icons.attach_money,
                                    color: isDark ? Colors.greenAccent : Colors.green,
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
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    t('السعر الإجمالي'),
                                    style: TextStyle(
                                      color: isDark ? Colors.white60 : Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${((double.tryParse(_priceControllers[itemIndex]!.text) ?? 0.0) * (int.tryParse(_quantityControllers[itemIndex]!.text) ?? 1)).toStringAsFixed(2)} دج',
                                    style: TextStyle(
                                      color: isDark ? Colors.lightBlueAccent : Colors.blue,
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
                    ),       // Column
                  ),         // Padding (Card child)
                ),           // Card
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
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 16)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            );                // GestureDetector
              },
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : Colors.white,
          border: isDark ? const Border(top: BorderSide(color: Color(0xFF334155), width: 1)) : null,
          boxShadow: isDark ? null : [
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
