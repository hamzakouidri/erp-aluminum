// Force compile sync trigger
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../sql_database.dart';
import '../services/cloud_sync_service.dart';
import 'choose_systems.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:database_data/Screen/show_dialog.dart';
import 'package:flutter/services.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/show_system_francais.dart';
import 'package:database_data/Commande/Systeme/volet.dart' show SystemRoling;
import 'package:database_data/Commande/window_painter.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/order_date_utils.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'order_table_edit_screen.dart';
import 'package:database_data/Commande/capture_image.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/Screen/caisson_tunnel_screen.dart';
import 'package:database_data/Screen/moustiquaire_screen.dart';
import 'package:database_data/Screen/tempered_glass_work_screen.dart';

class CommandePage extends StatefulWidget {
  final SqlDatabase db;
  final int? editCommandeId;
  final int? projectId;
  final List<WindowModel>? initialProducts;

  /// When shown inside the order workspace, the tab strip owns closing and
  /// navigation so the form itself must not pop the whole workspace route.
  final bool embeddedInWorkspace;
  final VoidCallback? onSavedInWorkspace;

  const CommandePage({
    super.key,
    required this.db,
    this.editCommandeId,
    this.projectId,
    this.initialProducts,
    this.embeddedInWorkspace = false,
    this.onSavedInWorkspace,
  });

  @override
  State<CommandePage> createState() => _CommandePageState();
}

class _CommandePageState extends State<CommandePage> {
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

  DevisLineItem _invoiceLineForProduct(WindowModel product) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final modelMap = Map<String, dynamic>.from(product.toMap());
    final seriesName =
        product.activeSeries?.name ??
        product.loadedSeriesName ??
        product.activeSlidingSeries?.name ??
        product.loadedSlidingSeriesName ??
        '';
    final colorName =
        product.selectedDbColor?['name']?.toString() ?? product.frameColor.name;

    modelMap['description'] = product.description ?? '';
    modelMap['quantity'] = product.quantity;

    return DevisBuilder.buildLineItemFromDetail(
      {
        'id': 0,
        'window_type': product.manualNameOverride ?? '',
        'game': seriesName,
        'color': colorName,
        'glass':
            product.zones.isNotEmpty &&
                product.zones.first.glass.structure == GlassStructure.double
            ? 'Double'
            : 'Simple',
        'largeur': product.width,
        'hauteur': product.height,
        'quantity': product.quantity,
        'price': product.manualPriceOverride ?? product.totalCost,
        'description': product.description ?? '',
        'partitions_json': jsonEncode(modelMap),
        'drawing_image_path': '',
      },
      overrideLang: lang,
      forceGeneratedDetails: false,
    );
  }

  Widget _detailRichText(String text, {required TextStyle style}) {
    final labelStyle = style.copyWith(fontWeight: FontWeight.w700);
    return RichText(
      textDirection: _containsArabic(text)
          ? ui.TextDirection.rtl
          : ui.TextDirection.ltr,
      text: TextSpan(children: _detailTextSpans(text, style, labelStyle)),
    );
  }

  List<TextSpan> _detailTextSpans(
    String text,
    TextStyle normalStyle,
    TextStyle labelStyle,
  ) {
    final spans = <TextSpan>[];
    final parts = text.split('|');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        spans.add(TextSpan(text: ' | ', style: normalStyle));
      }
      final part = parts[i];
      final colonIndex = part.indexOf(':');
      if (colonIndex > 0) {
        spans.add(
          TextSpan(text: part.substring(0, colonIndex + 1), style: labelStyle),
        );
        spans.add(
          TextSpan(text: part.substring(colonIndex + 1), style: normalStyle),
        );
      } else {
        spans.add(TextSpan(text: part, style: normalStyle));
      }
    }
    return spans;
  }

  bool _containsArabic(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }

  Map<String, dynamic>? selectedClient;

  TextEditingController clientController = TextEditingController();
  TextEditingController quoteDateController = TextEditingController();
  TextEditingController validDateController = TextEditingController();
  TextEditingController controller = TextEditingController(); // للملاحظات
  TextEditingController remiseController = TextEditingController();
  TextEditingController taxController = TextEditingController();

  List<WindowModel> addedProducts = [];
  bool _isSaving = false;
  bool _isReordering = false;
  bool _isLoadingEditProducts = false;
  int _editProductsLoaded = 0;
  int _editProductsTotal = 0;
  bool _isApplyingBulkChange = false;
  final Set<WindowModel> _bulkSelectedProducts = <WindowModel>{};

  WindowModel? _highlightedProduct;
  final Map<WindowModel, GlobalKey> _cardKeys = {};
  // Existing detail IDs must stay attached to their drawing while an order is
  // edited. Recreating rows with new IDs makes cloud sync reintroduce an old
  // copy of the same window (often with its former colour).
  final Map<WindowModel, int> _persistedDetailIds = {};
  final ScrollController _scrollController = ScrollController();

  void _scrollToHighlightedProduct() {
    if (_highlightedProduct == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _cardKeys[_highlightedProduct];
      if (key != null && key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  // حفظ آخر خصائص مستخدمة داخل نفس الطلبية
  Map<String, dynamic>? _lastUsedSettings;

  /// تحديث حفظ الخصائص من نموذج نافذة
  void _saveLastSettings(WindowModel m) {
    final glassSpec = m.zones.isNotEmpty ? m.zones.first.glass.toMap() : null;
    _lastUsedSettings = {
      'activeSeries': m.activeSeries,
      'activeSlidingSeries': m.activeSlidingSeries,
      'loadedSeriesId': m.activeSeries?.id ?? m.loadedSeriesId,
      'loadedSlidingSeriesId':
          m.activeSlidingSeries?.id ?? m.loadedSlidingSeriesId,
      'loadedSeriesName':
          m.activeSeries?.name ?? m.loadedSeriesName ?? m.manualNameOverride,
      'loadedSlidingSeriesName':
          m.activeSlidingSeries?.name ?? m.loadedSlidingSeriesName,
      'selectedDbColor': m.selectedDbColor != null
          ? Map<String, dynamic>.from(m.selectedDbColor!)
          : null,
      'selectedAccessoryColor': m.selectedAccessoryColor != null
          ? Map<String, dynamic>.from(m.selectedAccessoryColor!)
          : null,
      'glassSpec': glassSpec,
      'hasShutter': m.hasShutter,
      'shutterLame': m.shutterLame,
      'shutterGlissiere': m.shutterGlissiere,
      'shutterMechanism': m.shutterMechanism,
    };
  }

  List<WindowModel> _modelsFromMoustiquairePayload(
    Map<String, dynamic> payload,
  ) {
    final rawItems = payload['items'];
    if (rawItems is! List) return const [];
    final models = <WindowModel>[];
    final payloadId =
        payload['payloadId']?.toString() ??
        'payload_${DateTime.now().millisecondsSinceEpoch}';
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final width = (item['widthMm'] as num?)?.toDouble() ?? 0;
      final height = (item['heightMm'] as num?)?.toDouble() ?? 0;
      if (width <= 0 || height <= 0) continue;
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
      final area =
          (item['areaSqm'] as num?)?.toDouble() ??
          ((width / 1000) * (height / 1000));
      final totalArea =
          (item['totalAreaSqm'] as num?)?.toDouble() ?? area * quantity;
      final totalPrice = (item['estimatedPrice'] as num?)?.toDouble() ?? 0;
      final subtype =
          item['type']?.toString() ?? payload['subType']?.toString() ?? '';
      final frameColor =
          item['frameColor']?.toString() ??
          payload['frameColor']?.toString() ??
          '';
      final meshColor =
          item['meshColor']?.toString() ??
          payload['meshColor']?.toString() ??
          '';
      final singlePayload = <String, dynamic>{
        ...payload,
        'payloadId': payloadId,
        'subType': subtype,
        'itemsCount': 1,
        'totalQuantity': quantity,
        'grandTotalAreaSqm': totalArea,
        'grandTotalPrice': totalPrice,
        'widthMm': width,
        'heightMm': height,
        'frameColor': frameColor,
        'meshColor': meshColor,
        'items': [item],
      };
      final model = WindowModel(
        width: width,
        height: height,
        profileThickness: 60,
        db: widget.db,
      );
      model.isMoustiquaire = true;
      model.isReplaced = false;
      model.manualNameOverride = 'Moustiquaire ($subtype)';
      model.description =
          'النوع: $subtype | القياس: ${width.toStringAsFixed(0)} × '
          '${height.toStringAsFixed(0)} mm | الإطار: $frameColor | '
          'الشبكة: $meshColor';
      model.quantity = quantity < 1 ? 1 : quantity;
      model.moustiquairePayload = singlePayload;
      model.manualPriceOverride = model.quantity > 0
          ? totalPrice / model.quantity
          : totalPrice;
      models.add(model);
    }
    return models;
  }

  List<WindowModel> _modelsFromGlassWorkPayload(Map<String, dynamic> payload) {
    final rawItems = payload['items'];
    if (rawItems is! List) return const [];
    final models = <WindowModel>[];
    final payloadId =
        payload['payloadId']?.toString() ??
        'payload_${DateTime.now().millisecondsSinceEpoch}';
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final width = (item['widthMm'] as num?)?.toDouble() ?? 0;
      final height = (item['heightMm'] as num?)?.toDouble() ?? 0;
      if (width <= 0 || height <= 0) continue;
      final quantity = (item['quantity'] as num?)?.toInt() ?? 1;
      final area =
          (item['areaSqm'] as num?)?.toDouble() ??
          ((width / 1000) * (height / 1000));
      final unitPrice =
          (item['unitPrice'] as num?)?.toDouble() ??
          area * ((item['pricePerSqm'] as num?)?.toDouble() ?? 0);
      final totalPrice =
          (item['totalPrice'] as num?)?.toDouble() ?? unitPrice * quantity;
      final workLabel = payload['workTypeLabel']?.toString() ?? 'عمل زجاجي';
      final finishLabel = payload['glassFinishLabel']?.toString() ?? 'شفاف';
      final stickerLabel = payload['stickerLabel']?.toString() ?? 'بدون ستيكر';
      final thickness = (payload['thicknessMm'] as num?)?.toDouble() ?? 10;
      final notes = payload['notes']?.toString() ?? '';
      final singlePayload = <String, dynamic>{
        ...payload,
        'payloadId': payloadId,
        'itemsCount': 1,
        'totalQuantity': quantity,
        'grandTotalAreaSqm': area * quantity,
        'grandTotalPrice': totalPrice,
        'items': [item],
      };
      final model = WindowModel(
        width: width,
        height: height,
        profileThickness: 60,
        db: widget.db,
      );
      model.isGlassWork = true;
      model.isReplaced = false;
      model.manualNameOverride = 'Verre Trempé - $workLabel';
      model.description =
          '$finishLabel ${thickness.toStringAsFixed(0)} mm | $stickerLabel | '
          '${width.toStringAsFixed(0)} × ${height.toStringAsFixed(0)} mm'
          '${notes.isEmpty ? '' : ' | $notes'}';
      model.quantity = quantity < 1 ? 1 : quantity;
      model.glassWorkPayload = singlePayload;
      model.manualPriceOverride = unitPrice;
      models.add(model);
    }
    return models;
  }

  void _replaceProductWithIndependentModels(
    WindowModel current,
    List<WindowModel> models,
  ) {
    if (models.isEmpty) return;
    final currentIndex = addedProducts.indexOf(current);
    if (currentIndex < 0) {
      addedProducts.addAll(models);
      _highlightedProduct = models.last;
      return;
    }

    // Identify if adjacent models share the same payload group to replace them as a batch
    int replaceCount = 1;
    final currentPayloadId =
        current.glassWorkPayload?['payloadId'] ??
        current.moustiquairePayload?['payloadId'] ??
        current.caissonPayload?['payloadId'];

    if (currentPayloadId != null) {
      for (int i = currentIndex + 1; i < addedProducts.length; i++) {
        final p = addedProducts[i];
        final pPayloadId =
            p.glassWorkPayload?['payloadId'] ??
            p.moustiquairePayload?['payloadId'] ??
            p.caissonPayload?['payloadId'];
        if (pPayloadId == currentPayloadId) {
          replaceCount++;
        } else {
          break;
        }
      }
    }

    addedProducts.replaceRange(
      currentIndex,
      currentIndex + replaceCount,
      models,
    );
    _highlightedProduct = models.last;
  }

  Map<String, dynamic>? selectedProject;
  TextEditingController projectController = TextEditingController();

  String get today => DateFormat('yyyy/MM/dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();

    quoteDateController.text = today;
    validDateController.text = DateFormat(
      'yyyy/MM/dd',
    ).format(DateTime.now().add(const Duration(days: 14)));

    if (widget.editCommandeId != null) {
      _loadEditData();
    } else if (widget.projectId != null) {
      _loadInitialProject(widget.projectId!);
    } else if (widget.initialProducts != null &&
        widget.initialProducts!.isNotEmpty) {
      addedProducts.addAll(widget.initialProducts!);
    }
  }

  Future<void> _loadInitialProject(int projId) async {
    final proj = await widget.db.readProjectById(projId);
    if (proj != null) {
      setState(() {
        selectedProject = proj;
        projectController.text = proj['name'];
        selectedClient = {
          'id': proj['client_id'],
          'firstname': proj['firstname'],
          'lastname': proj['lastname'],
        };
        clientController.text = '${proj['firstname']} ${proj['lastname']}'
            .trim();
      });
    }
  }

  // 🟢 التخلص من المتحكمات لتفريغ الذاكرة
  @override
  void dispose() {
    clientController.dispose();
    quoteDateController.dispose();
    validDateController.dispose();
    controller.dispose();
    remiseController.dispose();
    taxController.dispose();
    projectController.dispose();
    super.dispose();
  }

  String _formatStoredDate(dynamic date) {
    final formatted = formatOrderDate(date, emptyLabel: '');
    if (formatted.isEmpty) return today;
    try {
      return DateFormat(
        'yyyy/MM/dd',
      ).format(DateFormat('yyyy-MM-dd').parse(formatted));
    } catch (_) {
      return today;
    }
  }

  String _parseQuoteDateForDb(String text) {
    final trimmed = text.trim();
    final now = DateTime.now();
    if (trimmed.isEmpty) return now.toIso8601String();
    try {
      if (trimmed.contains('/')) {
        final parts = trimmed.split('/');
        if (parts.length == 3) {
          return DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
            now.hour,
            now.minute,
            now.second,
          ).toIso8601String();
        }
      }
      final parsed = DateTime.parse(trimmed);
      return DateTime(
        parsed.year,
        parsed.month,
        parsed.day,
        now.hour,
        now.minute,
        now.second,
      ).toIso8601String();
    } catch (_) {
      return now.toIso8601String();
    }
  }

  Future<void> _loadEditData() async {
    final cmd = await widget.db.readCommandeWithClientById(
      widget.editCommandeId!,
    );
    if (cmd != null) {
      // Start the local detail query before optional project metadata.  The
      // project is secondary to the editable rows and should never delay
      // their first paint.
      final detailsFuture = widget.db.readCommandeDetails(
        widget.editCommandeId!,
      );
      final firstName = cmd['firstname']?.toString() ?? '';
      final lastName = cmd['lastname']?.toString() ?? '';
      setState(() {
        selectedClient = {
          'id': cmd['client_id'],
          'firstname': firstName,
          'lastname': lastName,
        };
        clientController.text = '$firstName $lastName'.trim();
        quoteDateController.text = _formatStoredDate(cmd['created_at']);
        remiseController.text = (cmd['remise'] ?? '').toString();
        taxController.text = (cmd['tva'] ?? '').toString();
        controller.text = cmd['description']?.toString() ?? '';
      });

      if (cmd['project_id'] != null) {
        final proj = await widget.db.readProjectById(cmd['project_id']);
        if (proj != null) {
          setState(() {
            selectedProject = proj;
            projectController.text = proj['name'];
          });
        }
      }

      final details = await detailsFuture;
      if (!mounted) return;
      setState(() {
        addedProducts.clear();
        _persistedDetailIds.clear();
        _isLoadingEditProducts = details.isNotEmpty;
        _editProductsTotal = details.length;
        _editProductsLoaded = 0;
      });

      double? readDouble(dynamic value) {
        if (value is num) return value.toDouble();
        return double.tryParse(value?.toString().trim() ?? '');
      }

      int? readInt(dynamic value) {
        if (value is num) return value.toInt();
        return int.tryParse(value?.toString().trim() ?? '');
      }

      for (final row in details) {
        final model = WindowModel(db: widget.db);
        final savedWidth = readDouble(row['largeur']);
        final savedHeight = readDouble(row['hauteur']);
        final jsonRaw = row['partitions_json'];
        if (jsonRaw != null) {
          Map<String, dynamic> map = {};
          if (jsonRaw is Map<String, dynamic>) {
            map = jsonRaw;
          } else if (jsonRaw is Map) {
            map = Map<String, dynamic>.from(jsonRaw);
          } else {
            final str = jsonRaw.toString().trim();
            if (str.length > 5) {
              try {
                final decoded = jsonDecode(str);
                if (decoded is Map) {
                  map = Map<String, dynamic>.from(decoded);
                }
              } catch (e) {
                debugPrint('Error parsing partitions JSON: $e');
              }
            }
          }
          if (map.isNotEmpty) {
            try {
              // Restore the saved drawing synchronously.  Loading the full
              // catalogue here used to run dozens of database queries for
              // every row before the first card could be painted, which was
              // especially noticeable on phones.  WindowView loads the
              // catalogue lazily when the user opens this specific drawing.
              applyWindowModelFromMap(model, map);
            } catch (e, st) {
              debugPrint(
                'Error restoring commande detail ${row['id']}: $e\n$st',
              );
            }
          }
        }
        // The detail column is the durable visual fallback.  It must win over
        // stale JSON from an earlier save, otherwise a former wood colour can
        // overwrite the colour the user most recently saved for the order.
        final rowColor = row['color']?.toString().trim() ?? '';
        final savedColorName =
            model.selectedDbColor?['name']?.toString().trim() ??
            model.selectedDbColor?['color_name']?.toString().trim() ??
            '';
        if (rowColor.isNotEmpty &&
            !model.isGlassWork &&
            savedColorName.toLowerCase() != rowColor.toLowerCase()) {
          // Keep the durable row value visible while the catalogue is still
          // cold.  It is only a lightweight display fallback; the catalogue
          // validates it later when the drawing is opened.
          model.selectedDbColor = {'name': rowColor};
        }

        // These columns are a durable fallback if an old JSON model is
        // incomplete or references a catalog entry that no longer exists.
        if (savedWidth != null) model.width = savedWidth;
        if (savedHeight != null) model.height = savedHeight;

        final game = row['game']?.toString().trim() ?? '';
        if (game.isNotEmpty) {
          model.manualNameOverride = game;
        }
        final savedPrice = readDouble(row['price']);
        final jsonPrice = model.manualPriceOverride;
        if (savedPrice != null &&
            (savedPrice != 0 || jsonPrice == null || jsonPrice == 0)) {
          model.manualPriceOverride = savedPrice;
        }
        model.quantity = readInt(row['quantity']) ?? model.quantity;
        final desc = row['description']?.toString().trim() ?? '';
        if (desc.isNotEmpty) {
          model.description = desc;
        }
        final detailId = readInt(row['id']);
        if (!mounted) return;
        setState(() {
          if (detailId != null) {
            _persistedDetailIds[model] = detailId;
          }
          addedProducts.add(model);
          _editProductsLoaded = addedProducts.length;
        });
        // Give Flutter a paint opportunity after each local row.  This makes
        // the first items visible immediately instead of waiting for the full
        // order to finish decoding.
        await Future.delayed(Duration.zero);
      }
      if (!mounted) return;
      setState(() {
        _isLoadingEditProducts = false;
      });

      final storedTotal = readDouble(cmd['total']) ?? 0.0;
      if (details.isEmpty && storedTotal > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'هذه الطلبية القديمة تحتوي على مجموع محفوظ دون سطور تفاصيل. '
                'استرجع نسخة سحابية أقدم أو أعد إضافة عناصرها قبل الحفظ.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 8),
            ),
          );
        });
      }
    }
  }

  Widget _buildEditItemsLoadingCard() {
    final total = _editProductsTotal;
    final loaded = _editProductsLoaded.clamp(0, total);
    final progress = total <= 0 ? null : loaded / total;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  total > 0
                      ? 'جاري تحميل عناصر الطلبية: $loaded / $total'
                      : 'جاري تحميل عناصر الطلبية...',
                  style: TextStyle(
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 6),
          Text(
            'يمكنك رؤية العناصر التي اكتملت فوراً، وسيتم تفعيل الحفظ والتعديل السريع عند اكتمال التحميل.',
            style: TextStyle(
              color: Colors.blueGrey.shade700,
              fontSize: 12,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> pickDate(TextEditingController controller) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );

    if (date != null) {
      controller.text = DateFormat('yyyy/MM/dd').format(date);
    }
  }

  // ==============================================================================
  // 🟢 دالة حساب المواد والتكلفة الإجمالية وجلب الأسعار من قاعدة البيانات
  // ==============================================================================
  Future<void> _calculateGlobalMaterialsAndCost() async {
    if (addedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("الرجاء إضافة منتجات أولاً لحساب تكلفتها"),
        ),
      );
      return;
    }

    // إظهار مؤشر تحميل أثناء الجلب من قاعدة البيانات
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    await Future.delayed(const Duration(milliseconds: 100));

    // 1. تعريف مجمعات المواد (Accumulators) للطلبية بأكملها
    double totalAluminumMeters = 0.0;
    double totalGlassSqm = 0.0;
    int totalHandles = 0;
    int totalHinges = 0;
    int totalRoulettes = 0;
    double totalShutterLamesMeters = 0.0;
    int totalShutters = 0;
    Map<int, int> totalEspagnolettes = {};

    // 2. جلب الأسعار من قاعدة البيانات (DB)
    double priceAlumPerMeter = 0.0;
    double priceGlassPerSqm = 0.0;
    double priceHandle = 0.0;
    double priceHinge = 0.0;
    double priceRoulette = 0.0;
    double priceEspagnolette = 0.0;
    double priceShutterKit = 0.0; // محرك أو حزام مع الملحقات
    double priceLamesPerMeter = 0.0;

    // 3. تحليل هندسي لكل منتج لحساب استهلاكه من المواد وتكلفته
    for (var p in addedProducts) {
      double pWidthM = p.width / 1000;
      double pHeightM = p.height / 1000;

      double pAlumMeters =
          (pWidthM * 2) + (pHeightM * 2); // الحلق الخارجي (Dormant)
      double pGlassSqm = 0.0;
      int pHandles = 0;
      int pHinges = 0;
      int pRoulettes = 0;
      double pLamesMeters = 0.0;

      int cremoneLengthCm = 0;
      if (p.hasShutter) {
        cremoneLengthCm = (pHeightM * 100).round() - 35;
      } else {
        cremoneLengthCm = (pHeightM * 100).round() - 20;
      }

      if (cremoneLengthCm > 180) cremoneLengthCm = 180;
      if (cremoneLengthCm < 0) cremoneLengthCm = 0;

      int hingesPerSash = 0;
      if (cremoneLengthCm <= 80) {
        hingesPerSash = 2;
      } else if (cremoneLengthCm <= 100) {
        hingesPerSash = 3;
      } else {
        hingesPerSash = 4;
      }

      int pEspagnolettesCount = 0;

      // حساب المكونات الداخلية (Ouvrants, Vitrage) بناءً على نوع المناطق
      for (var zone in p.zones) {
        double zWidthM = zone.boundary.width / 1000;
        double zHeightM = zone.boundary.height / 1000;
        double area = zWidthM * zHeightM;

        if (zone.content == ZoneContent.singleSash) {
          pAlumMeters += (zWidthM * 2) + (zHeightM * 2);
          pGlassSqm += area;
          pHandles += 1;
          pHinges += hingesPerSash;
          pEspagnolettesCount += 1;
        } else if (zone.content == ZoneContent.doubleSash) {
          pAlumMeters += (zWidthM * 4) + (zHeightM * 4);
          pAlumMeters +=
              zHeightM +
              1.0; // Batmo (Height) + Cache Batmo (1 piece = 1 meter equivalent)
          pGlassSqm += area;
          pHandles += 1;
          pHinges += hingesPerSash * 2;
          pEspagnolettesCount += 1;
        } else if (zone.content == ZoneContent.slidingSash) {
          pAlumMeters +=
              (zWidthM * zone.slidingSashesCount) +
              (zHeightM * zone.slidingSashesCount);
          pGlassSqm += area;
          pRoulettes += zone.slidingSashesCount * 2;
          pHandles += 2;
        } else if (zone.content == ZoneContent.fixedGlass) {
          pGlassSqm += area;
        }
      }

      // حساب مواد الستار إن وجد
      double pShutterCost = 0.0;
      if (p.hasShutter) {
        double lameHeight = 0.043; // 43mm
        int lamesCount = (pHeightM / lameHeight).ceil();
        pLamesMeters = lamesCount * pWidthM;
        if (!p.isReplaced) {
          totalShutters += 1;
        }
        pShutterCost =
            (pLamesMeters * priceLamesPerMeter) +
            priceShutterKit +
            (pWidthM * 1200); // 1200 للصندوق
      }

      // حساب التكلفة الفردية للمنتج (Cost calculation per window)
      double pCost = 0.0;
      pCost += pAlumMeters * priceAlumPerMeter;
      pCost += pGlassSqm * priceGlassPerSqm;
      pCost +=
          (pHandles * priceHandle) +
          (pHinges * priceHinge) +
          (pRoulettes * priceRoulette) +
          (pEspagnolettesCount * priceEspagnolette);
      pCost += pShutterCost;

      // 🟢 تحديث تكلفة المنتج داخل الموديل لكي تظهر في الفاتورة مباشرة
      p.totalCost = pCost;

      if (p.isReplaced) {
        continue;
      }

      // تجميع الإجماليات لإظهار التقرير
      totalAluminumMeters += pAlumMeters;
      totalGlassSqm += pGlassSqm;
      totalHandles += pHandles;
      totalHinges += pHinges;
      totalRoulettes += pRoulettes;
      totalShutterLamesMeters += pLamesMeters;
      if (pEspagnolettesCount > 0 && cremoneLengthCm > 0) {
        totalEspagnolettes[cremoneLengthCm] =
            (totalEspagnolettes[cremoneLengthCm] ?? 0) + pEspagnolettesCount;
      }
    }

    // إغلاق مؤشر التحميل
    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    // تحديث الواجهة (ليظهر السعر الجديد في ملخص الفاتورة السفلي)
    setState(() {});

    // 4. عرض تقرير المواد (Débit & Devis) في نافذة سفلية
    if (mounted) {
      _showReportBottomSheet(
        totalAluminumMeters: totalAluminumMeters,
        totalGlassSqm: totalGlassSqm,
        totalHandles: totalHandles,
        totalHinges: totalHinges,
        totalRoulettes: totalRoulettes,
        totalShutterLamesMeters: totalShutterLamesMeters,
        totalShutters: totalShutters,
        totalEspagnolettes: totalEspagnolettes,
        grandTotal: addedProducts
            .where((p) => !p.isReplaced)
            .fold(
              0.0,
              (sum, p) =>
                  sum + ((p.manualPriceOverride ?? p.totalCost) * p.quantity),
            ),
      );
    }
  }

  Future<void> _saveCommande() async {
    if (_isSaving) return;

    // 🟢 Auto-resolve client if typed in text field but selectedClient map is null
    if (selectedClient == null && clientController.text.trim().isNotEmpty) {
      final inputName = clientController.text.trim();
      try {
        final clients = await widget.db.readClient();
        final match = clients.firstWhere(
          (c) =>
              '${c['firstname']} ${c['lastname']}'.trim().toLowerCase() ==
                  inputName.toLowerCase() ||
              '${c['lastname']} ${c['firstname']}'.trim().toLowerCase() ==
                  inputName.toLowerCase() ||
              (c['firstname']?.toString().toLowerCase() ==
                  inputName.toLowerCase()),
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) {
          selectedClient = match;
        } else {
          final parts = inputName.split(' ');
          final fname = parts.first;
          final lname = parts.length > 1 ? parts.sublist(1).join(' ') : '';
          final newId = await widget.db.insertClient(
            fname,
            lname,
            '',
            '',
            '',
            '',
          );
          selectedClient = {'id': newId, 'firstname': fname, 'lastname': lname};
        }
      } catch (e) {
        debugPrint('Error auto-resolving client: $e');
      }
    }

    if (selectedClient == null || selectedClient!['id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(
              "Please select a client",
              Provider.of<AppSettingsProvider>(context, listen: false).language,
            ),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (addedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(
              "Please add products",
              Provider.of<AppSettingsProvider>(context, listen: false).language,
            ),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final clientId = selectedClient!['id'];

    setState(() => _isSaving = true);
    bool dialogShown = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    dialogShown = true;

    await Future.delayed(const Duration(milliseconds: 100));

    final syncService = CloudSyncService();
    await syncService.beginLocalWrite();
    try {
      if (!mounted) return;
      final settings = Provider.of<AppSettingsProvider>(context, listen: false);
      double rawTotal = addedProducts
          .where((p) => !p.isReplaced)
          .fold(
            0.0,
            (sum, p) =>
                sum + ((p.manualPriceOverride ?? p.totalCost) * p.quantity),
          );
      double total = rawTotal;
      if (settings.costMethod == CostMethod.percentage) {
        total = rawTotal * (1 + settings.profitMargin / 100);
      }

      double remise = double.tryParse(remiseController.text) ?? 0.0;
      double tax = double.tryParse(taxController.text) ?? 0.0;

      final existingDetails = widget.editCommandeId == null
          ? <Map<String, dynamic>>[]
          : await widget.db.readCommandeDetails(widget.editCommandeId!);
      final existingDetailsById = <int, Map<String, dynamic>>{};
      for (final detail in existingDetails) {
        final rawId = detail['id'];
        final detailId = rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId?.toString() ?? '');
        if (detailId != null) existingDetailsById[detailId] = detail;
      }

      final imagePaths = await Future.wait(
        addedProducts.asMap().entries.map((entry) async {
          final index = entry.key;
          final p = entry.value;
          final previous = index < existingDetails.length
              ? existingDetails[index]
              : null;
          final selectedGlassImagePath =
              p.glassWorkPayload?['imagePath']?.toString() ?? '';
          final mustKeepSyncedGlassImage =
              p.isGlassWork &&
              selectedGlassImagePath.isNotEmpty &&
              !File(selectedGlassImagePath).existsSync() &&
              (previous?['drawing_image_base64']?.toString().isNotEmpty ??
                  false);
          if (mustKeepSyncedGlassImage) return '';
          return saveWindowImageToDisk(p, maxSide: 600);
        }),
      );

      final preparedDetails = <Map<String, dynamic>>[];
      for (var index = 0; index < addedProducts.length; index++) {
        final p = addedProducts[index];
        final persistedDetailId = _persistedDetailIds[p];
        final previous = persistedDetailId == null
            ? (index < existingDetails.length ? existingDetails[index] : null)
            : existingDetailsById[persistedDetailId];
        final newImagePath = imagePaths[index];
        final drawingPath = newImagePath.isNotEmpty
            ? newImagePath
            : previous?['drawing_image_path']?.toString() ?? '';
        preparedDetails.add({
          if (persistedDetailId != null) 'id': persistedDetailId,
          'largeur': p.width.toInt(),
          'hauteur': p.height.toInt(),
          'game': p.isShutterOnly
              ? 'Volet roulant'
              : (p.manualNameOverride ?? ''),
          'quantity': p.quantity,
          'glass': p.isGlassWork
              ? '${p.glassWorkPayload?['glassFinishLabel'] ?? 'Verre'} '
                    '${((p.glassWorkPayload?['thicknessMm'] as num?)?.toDouble() ?? 10).toStringAsFixed(0)} mm'
              : (p.zones.isNotEmpty &&
                        p.zones.first.glass.structure == GlassStructure.double
                    ? 'Double'
                    : 'Single'),
          'color': p.selectedDbColor != null
              ? (p.selectedDbColor!['name']?.toString() ??
                    p.selectedDbColor!['color_name']?.toString() ??
                    '')
              : (p.isGlassWork
                    ? (p.glassWorkPayload?['stickerLabel']?.toString() ?? '')
                    : p.frameColor.toString().split('.').last),
          'volet': p.hasShutter ? 'Yes' : 'No',
          'accessories': '',
          'description': p.description ?? '',
          'price': p.manualPriceOverride ?? p.totalCost,
          'window_type': p.isGlassWork
              ? (p.glassWorkPayload?['workTypeLabel']?.toString() ??
                    'Verre Trempé')
              : (p.zones.any((z) => z.content == ZoneContent.doubleSash)
                    ? 'Double Sash'
                    : 'Single Sash'),
          'partitions_json': () {
            try {
              return jsonEncode(p.toMap());
            } catch (e) {
              debugPrint('Error encoding p.toMap(): $e');
              return '{}';
            }
          }(),
          'drawing_image_path': drawingPath,
          if (newImagePath.isEmpty && previous?['drawing_image_base64'] != null)
            'drawing_image_base64': previous!['drawing_image_base64'],
        });
      }

      await widget.db.saveCommandeWithDetails(
        idCommande: widget.editCommandeId,
        clientId: (clientId as num).toInt(),
        status: 'Pending',
        description: controller.text,
        remise: remise,
        tva: tax,
        total: total,
        netPayable: total - remise + ((total * tax) / 100),
        createdAt: _parseQuoteDateForDb(quoteDateController.text),
        projectId: (selectedProject?['id'] as num?)?.toInt(),
        details: preparedDetails,
      );

      if (!mounted) return;
      if (dialogShown) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop(); // close loading dialog
        dialogShown = false;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(
              "Saved successfully!",
              Provider.of<AppSettingsProvider>(context, listen: false).language,
            ),
          ),
        ),
      );
      if (widget.embeddedInWorkspace) {
        widget.onSavedInWorkspace?.call();
      } else {
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      debugPrint('Error saving commande: $e\n$st');
      if (!mounted) return;
      if (dialogShown) {
        try {
          Navigator.of(
            context,
            rootNavigator: true,
          ).pop(); // close loading dialog
        } catch (_) {}
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ الطلبية: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      syncService.endLocalWrite();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  List<WindowModel> _bulkEditableProducts() {
    return addedProducts.where((product) {
      return !product.isReplaced &&
          !product.isGlassWork &&
          !product.isMoustiquaire &&
          !product.isCaissonTunnel &&
          !product.isShutterOnly;
    }).toList();
  }

  Future<List<WindowModel>?> _selectBulkProducts({
    required String title,
  }) async {
    final products = _bulkEditableProducts();
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد عناصر قابلة لهذا التخصيص.')),
      );
      return null;
    }

    final selected = <WindowModel>{
      ..._bulkSelectedProducts.where(products.contains),
    };
    if (selected.isEmpty) selected.addAll(products);

    final result = await showDialog<List<WindowModel>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final allSelected = selected.length == products.length;
            return AlertDialog(
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: Column(
                  children: [
                    CheckboxListTile(
                      value: allSelected,
                      tristate: false,
                      title: const Text('تحديد الكل'),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            selected.addAll(products);
                          } else {
                            selected.clear();
                          }
                        });
                      },
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final product = products[index];
                          final title = product.manualNameOverride?.trim();
                          return CheckboxListTile(
                            value: selected.contains(product),
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              title == null || title.isEmpty
                                  ? 'عنصر ${index + 1}'
                                  : title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${product.width.toInt()} × ${product.height.toInt()} mm',
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  selected.add(product);
                                } else {
                                  selected.remove(product);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, selected.toList()),
                  child: Text('متابعة (${selected.length})'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      _bulkSelectedProducts
        ..clear()
        ..addAll(result);
    }
    return result;
  }

  Future<T?> _runBulkOperation<T>(Future<T> Function() operation) async {
    if (_isApplyingBulkChange) return null;
    if (mounted) setState(() => _isApplyingBulkChange = true);
    try {
      return await operation();
    } catch (error, stackTrace) {
      debugPrint('Bulk order customization failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تطبيق التخصيص: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _isApplyingBulkChange = false);
    }
  }

  Future<void> _prepareBulkCatalog(Iterable<WindowModel> products) async {
    for (final product in products) {
      if (product.availableSystems.isEmpty || product.allGlassCache.isEmpty) {
        await product.loadCatalogData(product.systemMode ?? 'mixed');
      }
    }
  }

  double _readMapPrice(Map<String, dynamic>? value) {
    if (value == null) return 0.0;
    final raw =
        value['calculated_price'] ?? value['price_dzd'] ?? value['price'];
    return raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }

  double _productProfileUnitPrice(WindowModel product) {
    final sash = product.usesSlidingPrimaryProfiles
        ? product.slidingSashOverride
        : product.sashOverride;
    return _readMapPrice(product.activeFrameOverride) + _readMapPrice(sash);
  }

  double _productGlassCost(WindowModel product) {
    if (product.allGlassCache.isEmpty) return 0.0;
    var total = 0.0;
    for (final zone in product.zones) {
      if (zone.content == ZoneContent.empty) continue;
      final area = zone.boundary.width / 1000 * zone.boundary.height / 1000;
      total += area * product.calculateTotalGlassPricePerSqmForZone(zone);
    }
    return total;
  }

  void _applyPriceDelta(
    WindowModel product, {
    required double oldGlassCost,
    required double oldProfilePrice,
  }) {
    final oldUnitPrice = product.manualPriceOverride ?? product.totalCost;
    final perimeterMeters = (2 * product.width + 2 * product.height) / 1000.0;
    final newGlassCost = _productGlassCost(product);
    final newProfilePrice = _productProfileUnitPrice(product);
    final delta =
        (newGlassCost - oldGlassCost) +
        ((newProfilePrice - oldProfilePrice) * perimeterMeters);
    var updated = oldUnitPrice + delta;
    if (oldUnitPrice <= 0 && updated <= 0) {
      updated = newGlassCost + newProfilePrice * perimeterMeters;
    }
    if (updated <= 0) return;
    if (product.manualPriceOverride != null) {
      product.manualPriceOverride = updated;
    } else {
      product.totalCost = updated;
    }
  }

  // 🟢 تغيير لون العناصر المحددة من الطلبية
  Future<void> _showApplyBulkColorDialog() async {
    final selected = await _selectBulkProducts(
      title: 'تغيير لون عناصر الطلبية',
    );
    if (selected == null || selected.isEmpty) return;

    final prepared = await _runBulkOperation<bool>(() async {
      await _prepareBulkCatalog(selected);
      return true;
    });
    if (prepared != true || !mounted) return;

    final allColors = await widget.db.readColors();
    Set<int>? allowedColorIds;
    for (final product in selected) {
      final ids = product.availableColors
          .map((color) {
            final rawId = color['id'];
            return rawId is num
                ? rawId.toInt()
                : int.tryParse(rawId?.toString() ?? '');
          })
          .whereType<int>()
          .toSet();
      allowedColorIds = allowedColorIds == null
          ? ids
          : allowedColorIds.intersection(ids);
    }
    final colors = allColors.where((color) {
      final rawId = color['id'];
      final id = rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '');
      return id != null && (allowedColorIds?.contains(id) ?? false);
    }).toList();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختيار لون العناصر المحددة'),
        content: SizedBox(
          width: double.maxFinite,
          child: colors.isEmpty
              ? const Text('لا يوجد لون مشترك صالح لهذه العناصر.')
              : ListView(
                  shrinkWrap: true,
                  children: colors.map((dbColor) {
                    final name = dbColor['name']?.toString() ?? '';
                    final hex = dbColor['hex_code']?.toString() ?? '#9E9E9E';
                    Color parsedColor = Colors.grey;
                    try {
                      parsedColor = Color(
                        int.parse(hex.replaceAll('#', '0xFF')),
                      );
                    } catch (_) {}
                    return ListTile(
                      leading: CircleAvatar(backgroundColor: parsedColor),
                      title: Text(name),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final changed = await _runBulkOperation<int>(() async {
                          var count = 0;
                          for (final product in selected) {
                            final oldGlass = _productGlassCost(product);
                            final oldProfile = _productProfileUnitPrice(
                              product,
                            );
                            final allowed = product.availableColors.any(
                              (color) =>
                                  color['id']?.toString() ==
                                  dbColor['id']?.toString(),
                            );
                            if (!allowed) continue;
                            product.selectedDbColor = dbColor;
                            await product.refreshSectionPricesForSelectedColor(
                              notify: false,
                            );
                            _applyPriceDelta(
                              product,
                              oldGlassCost: oldGlass,
                              oldProfilePrice: oldProfile,
                            );
                            count++;
                          }
                          if (mounted) setState(() {});
                          return count;
                        });
                        if (mounted && changed != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.green.shade700,
                              content: Text(
                                'تم تغيير اللون لـ $changed عنصر بنجاح.',
                              ),
                            ),
                          );
                        }
                      },
                    );
                  }).toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBulkSeriesDialog() async {
    final selected = await _selectBulkProducts(title: 'تغيير سلسلة العناصر');
    if (selected == null || selected.isEmpty) return;
    final prepared = await _runBulkOperation<bool>(() async {
      await _prepareBulkCatalog(selected);
      return true;
    });
    if (prepared != true || !mounted) return;

    final source = selected.first;
    final candidates = <AluminumSeries>[];
    for (final system in source.availableSystems) {
      for (final series in system.series) {
        if (!candidates.any((item) => item.id == series.id)) {
          candidates.add(series);
        }
      }
    }
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد سلاسل متاحة لهذه العناصر.')),
      );
      return;
    }
    final chosen = await showDialog<AluminumSeries>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختر السلسلة الجديدة'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: ListView(
            children: candidates.map((series) {
              final system = source.availableSystems.firstWhere(
                (item) =>
                    item.series.any((candidate) => candidate.id == series.id),
                orElse: () => AluminumProfileSystem(id: 0, name: '', type: ''),
              );
              final sliding = isSlidingSeriesForDrawing(series);
              return ListTile(
                leading: Icon(
                  sliding ? Icons.swap_horiz : Icons.open_in_new,
                  color: sliding ? Colors.green : Colors.blue,
                ),
                title: Text(series.name),
                subtitle: Text(
                  '${system.name}${sliding ? ' - منزلق' : ' - فتح'}',
                ),
                onTap: () => Navigator.pop(ctx, series),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;

    final changed = await _runBulkOperation<int>(() async {
      var count = 0;
      for (final product in selected) {
        final localSeries = product.availableSystems
            .expand((system) => system.series)
            .where((series) => series.id == chosen.id)
            .cast<AluminumSeries?>()
            .firstWhere((series) => series != null, orElse: () => null);
        if (localSeries == null) continue;
        final oldGlass = _productGlassCost(product);
        final oldProfile = _productProfileUnitPrice(product);
        if (isSlidingSeriesForDrawing(localSeries)) {
          if (product.systemMode == 'sliding') {
            await product.setActiveSeries(localSeries);
          } else {
            await product.setActiveSlidingSeries(localSeries);
          }
          product.loadedSlidingSeriesId = localSeries.id;
          product.loadedSlidingSeriesName = localSeries.name;
        } else {
          await product.setActiveSeries(localSeries);
          product.loadedSeriesId = localSeries.id;
          product.loadedSeriesName = localSeries.name;
        }
        _applyPriceDelta(
          product,
          oldGlassCost: oldGlass,
          oldProfilePrice: oldProfile,
        );
        count++;
      }
      if (mounted) setState(() {});
      return count;
    });
    if (mounted && changed != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text('تم تغيير السلسلة لـ $changed عنصر بنجاح.'),
        ),
      );
    }
  }

  Future<GlassSpecification?> _showBulkGlassSpecDialog(
    GlassSpecification base,
  ) async {
    final outerThickness = TextEditingController(
      text: (base.thicknessOuter ?? 4).toStringAsFixed(0),
    );
    final innerThickness = TextEditingController(
      text: (base.thicknessInner ?? 4).toStringAsFixed(0),
    );
    final intercall = TextEditingController(
      text: base.intercallThickness.toString(),
    );
    var structure = base.structure;
    var finishOuter = base.finishOuter;
    var finishInner = base.finishInner;
    var colorOuter = base.colorOuter;
    var colorInner = base.colorInner;
    var processingOuter = base.processingOuter;
    var processingInner = base.processingInner;
    var hasGas = base.hasGas;

    try {
      return await showDialog<GlassSpecification>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) {
            Widget enumDropdown<T>({
              required String label,
              required T value,
              required List<T> values,
              required ValueChanged<T?> onChanged,
            }) {
              return DropdownButtonFormField<T>(
                value: value,
                decoration: InputDecoration(labelText: label),
                items: values
                    .map(
                      (item) => DropdownMenuItem<T>(
                        value: item,
                        child: Text(item.toString().split('.').last),
                      ),
                    )
                    .toList(),
                onChanged: onChanged,
              );
            }

            return AlertDialog(
              title: const Text('تغيير زجاج العناصر المحددة'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      enumDropdown(
                        label: 'نوع الزجاج',
                        value: structure,
                        values: GlassStructure.values,
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => structure = value);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: outerThickness,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'سمك الزجاج الخارجي (مم)',
                        ),
                      ),
                      if (structure == GlassStructure.double) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: innerThickness,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'سمك الزجاج الداخلي (مم)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: intercall,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'سمك الأنتركال (مم)',
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('مع غاز'),
                          value: hasGas,
                          onChanged: (value) =>
                              setDialogState(() => hasGas = value),
                        ),
                      ],
                      enumDropdown(
                        label: 'معالجة الوجه الخارجي',
                        value: processingOuter,
                        values: GlassProcessing.values,
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => processingOuter = value);
                          }
                        },
                      ),
                      enumDropdown(
                        label: 'نوع الوجه الخارجي',
                        value: finishOuter,
                        values: GlassFinish.values,
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => finishOuter = value);
                          }
                        },
                      ),
                      enumDropdown(
                        label: 'لون الوجه الخارجي',
                        value: colorOuter,
                        values: GlassColor.values,
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => colorOuter = value);
                          }
                        },
                      ),
                      if (structure == GlassStructure.double) ...[
                        enumDropdown(
                          label: 'معالجة الوجه الداخلي',
                          value: processingInner,
                          values: GlassProcessing.values,
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => processingInner = value);
                            }
                          },
                        ),
                        enumDropdown(
                          label: 'نوع الوجه الداخلي',
                          value: finishInner,
                          values: GlassFinish.values,
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => finishInner = value);
                            }
                          },
                        ),
                        enumDropdown(
                          label: 'لون الوجه الداخلي',
                          value: colorInner,
                          values: GlassColor.values,
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => colorInner = value);
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () {
                    final outer =
                        double.tryParse(
                          outerThickness.text.replaceAll(',', '.'),
                        ) ??
                        4.0;
                    final inner =
                        double.tryParse(
                          innerThickness.text.replaceAll(',', '.'),
                        ) ??
                        4.0;
                    Navigator.pop(
                      ctx,
                      GlassSpecification(
                        structure: structure,
                        finishOuter: finishOuter,
                        finishInner: structure == GlassStructure.double
                            ? finishInner
                            : finishOuter,
                        colorOuter: colorOuter,
                        colorInner: structure == GlassStructure.double
                            ? colorInner
                            : colorOuter,
                        processingOuter: processingOuter,
                        processingInner: structure == GlassStructure.double
                            ? processingInner
                            : GlassProcessing.none,
                        temperedOuter:
                            processingOuter == GlassProcessing.tempered,
                        temperedInner:
                            processingInner == GlassProcessing.tempered,
                        hasGas: structure == GlassStructure.double && hasGas,
                        intercallThickness:
                            int.tryParse(intercall.text) ??
                            base.intercallThickness,
                        thicknessOuter: outer,
                        thicknessInner: structure == GlassStructure.double
                            ? inner
                            : null,
                        panneauSubtype: base.panneauSubtype,
                        panneauColor: base.panneauColor,
                        panneauProductId: base.panneauProductId,
                      ),
                    );
                  },
                  child: const Text('تطبيق'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      outerThickness.dispose();
      innerThickness.dispose();
      intercall.dispose();
    }
  }

  Future<void> _showBulkGlassDialog() async {
    final selected = await _selectBulkProducts(title: 'تغيير زجاج العناصر');
    if (selected == null || selected.isEmpty) return;
    final prepared = await _runBulkOperation<bool>(() async {
      await _prepareBulkCatalog(selected);
      return true;
    });
    if (prepared != true || !mounted) return;

    final source = selected.firstWhere(
      (product) => product.zones.isNotEmpty,
      orElse: () => selected.first,
    );
    if (source.zones.isEmpty) return;
    final base =
        source.getUniformGlassSpecification() ?? source.zones.first.glass;
    final spec = await _showBulkGlassSpecDialog(base);
    if (spec == null || !mounted) return;

    final changed = await _runBulkOperation<int>(() async {
      var count = 0;
      for (final product in selected) {
        if (product.zones.isEmpty) continue;
        final oldGlass = _productGlassCost(product);
        final oldProfile = _productProfileUnitPrice(product);
        await product.applyGlassSpecificationToAllZones(spec);
        _applyPriceDelta(
          product,
          oldGlassCost: oldGlass,
          oldProfilePrice: oldProfile,
        );
        count++;
      }
      if (mounted) setState(() {});
      return count;
    });
    if (mounted && changed != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text('تم تغيير الزجاج لـ $changed عنصر بنجاح.'),
        ),
      );
    }
  }

  // 🟢 حل مشكلة الأوفر فلو العمودي في النافذة المنبثقة
  void _showReportBottomSheet({
    required double totalAluminumMeters,
    required double totalGlassSqm,
    required int totalHandles,
    required int totalHinges,
    required int totalRoulettes,
    required double totalShutterLamesMeters,
    required int totalShutters,
    required Map<int, int> totalEspagnolettes,
    required double grandTotal,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20.0,
              right: 20.0,
              top: 20.0,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20.0,
            ),
            child: SingleChildScrollView(
              // 🟢 يمنع خروج النص من الشاشة
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تقرير المواد المستهلكة والتكلفة',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const Divider(thickness: 1.5),
                  const SizedBox(height: 10),

                  _buildReportRow(
                    t('إجمالي الألمنيوم (Profilés):'),
                    '${totalAluminumMeters.toStringAsFixed(1)} متر طولي',
                  ),
                  _buildReportRow(
                    t('إجمالي الزجاج (Vitrage):'),
                    '${totalGlassSqm.toStringAsFixed(2)} متر مربع',
                  ),
                  _buildReportRow('مقابض (Poignées):', '$totalHandles قطع'),
                  _buildReportRow('مفصلات (Paumelles):', '$totalHinges قطع'),
                  if (totalEspagnolettes.isNotEmpty)
                    ...totalEspagnolettes.entries.map(
                      (entry) => _buildReportRow(
                        'اسبانيولات (Crémones) ${entry.key} سم:',
                        '${entry.value} قطع',
                      ),
                    ),
                  if (totalRoulettes > 0)
                    _buildReportRow(
                      'عجلات الانزلاق (Roulettes):',
                      '$totalRoulettes قطع',
                    ),
                  if (totalShutters > 0) ...[
                    const Divider(),
                    Text(
                      t('الستائر (Volets):'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                    _buildReportRow(
                      'شفرات الستائر (Lames):',
                      '${totalShutterLamesMeters.toStringAsFixed(1)} متر طولي',
                    ),
                    _buildReportRow(t('صناديق/محركات:'), '$totalShutters أطقم'),
                  ],

                  const Divider(thickness: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        t('التكلفة المحسوبة:'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${grandTotal.toStringAsFixed(2)} دج',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'حسناً، تم اعتماد الحساب',
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildReportRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, color: Colors.black87),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
        ],
      ),
    );
  }

  // ==============================================================================

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final double rawTotal = addedProducts
        .where((p) => !p.isReplaced)
        .fold(
          0.0,
          (sum, p) =>
              sum + ((p.manualPriceOverride ?? p.totalCost) * p.quantity),
        );
    double finalTotal = rawTotal;
    if (settings.costMethod == CostMethod.percentage) {
      finalTotal = rawTotal * (1 + settings.profitMargin / 100);
    }
    final double remise = double.tryParse(remiseController.text) ?? 0.0;
    final double taxVal = double.tryParse(taxController.text) ?? 0.0;
    final double calculatedTax = (finalTotal * taxVal) / 100;
    final double totalWithRemiseTax = finalTotal - remise + calculatedTax;
    final int totalQuantity = addedProducts
        .where((p) => !p.isReplaced)
        .fold(0, (sum, p) => sum + p.quantity);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embeddedInWorkspace,
        title: Text(
          Localization.translate(
            "New Quotation",
            Provider.of<AppSettingsProvider>(context).language,
          ),
        ),
        backgroundColor: isDark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        actions: [
          if (addedProducts.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.palette, color: Colors.purpleAccent),
              onPressed: _isApplyingBulkChange
                  ? null
                  : _showApplyBulkColorDialog,
              tooltip: 'تغيير لون عناصر الطلبية',
            ),
            IconButton(
              icon: const Icon(Icons.layers, color: Colors.blueAccent),
              onPressed: _isApplyingBulkChange ? null : _showBulkSeriesDialog,
              tooltip: 'تغيير سلسلة عناصر الطلبية',
            ),
            IconButton(
              icon: const Icon(Icons.window, color: Colors.teal),
              onPressed: _isApplyingBulkChange ? null : _showBulkGlassDialog,
              tooltip: 'تغيير زجاج عناصر الطلبية',
            ),
          ],
          if (addedProducts.length > 1)
            IconButton(
              icon: Icon(
                _isReordering ? Icons.grid_view : Icons.sort,
                color: _isReordering
                    ? Colors.blue
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
              onPressed: () {
                setState(() {
                  _isReordering = !_isReordering;
                });
              },
              tooltip: Localization.translate(
                "ترتيب العناصر",
                Provider.of<AppSettingsProvider>(context).language,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.check, size: 28, color: Colors.teal),
            onPressed: (_isSaving || _isLoadingEditProducts)
                ? null
                : _saveCommande,
            tooltip: Localization.translate(
              "Save",
              Provider.of<AppSettingsProvider>(context).language,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildField(
              label:
                  "${Localization.translate('Customer', Provider.of<AppSettingsProvider>(context).language)} *",
              controller: clientController,
              icon: Icons.person,
              suffix: (widget.projectId != null || selectedProject != null)
                  ? null
                  : Icons.search,
              onTap: (widget.projectId != null || selectedProject != null)
                  ? null
                  : () async {
                      final result = await showDialog(
                        context: context,
                        builder: (context) =>
                            ClientDropdownDialog(db: widget.db),
                      );

                      if (result != null && result is Map<String, dynamic>) {
                        setState(() {
                          selectedClient = result;
                          clientController.text =
                              "${result['firstname']} ${result['lastname']}";
                          // Clear project if customer changes
                          selectedProject = null;
                          projectController.text = '';
                        });
                      }
                    },
            ),

            const SizedBox(height: 15),

            _buildField(
              label: Localization.translate(
                'المشروع (اختياري)',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              controller: projectController,
              icon: Icons.folder_shared_rounded,
              suffix: (widget.projectId != null) ? null : Icons.search,
              onTap: (widget.projectId != null)
                  ? null
                  : () async {
                      if (selectedClient == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              Localization.translate(
                                'يرجى اختيار الزبون أولاً لعرض مشاريعه',
                                Provider.of<AppSettingsProvider>(
                                  context,
                                ).language,
                              ),
                            ),
                          ),
                        );
                        return;
                      }
                      final result = await showDialog(
                        context: context,
                        builder: (context) => ProjectDropdownDialog(
                          db: widget.db,
                          clientId: selectedClient!['id'] as int,
                        ),
                      );

                      if (result != null && result is Map<String, dynamic>) {
                        setState(() {
                          selectedProject = result;
                          projectController.text = result['name'];
                        });
                      } else if (result == 'clear') {
                        setState(() {
                          selectedProject = null;
                          projectController.text = '';
                        });
                      }
                    },
            ),

            const SizedBox(height: 15),

            _buildField(
              label: "Quote date *",
              controller: quoteDateController,
              icon: Icons.calendar_today,
              onTap: () => pickDate(quoteDateController),
            ),

            const SizedBox(height: 15),

            _buildField(
              label: "Valid till Date *",
              controller: validDateController,
              icon: Icons.calendar_today,
              onTap: () => pickDate(validDateController),
            ),
            const SizedBox(height: 15),

            if (_isLoadingEditProducts) ...[
              _buildEditItemsLoadingCard(),
              const SizedBox(height: 15),
            ],

            if (addedProducts.isNotEmpty && !_isReordering) ...[
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isApplyingBulkChange
                        ? null
                        : _showApplyBulkColorDialog,
                    icon: const Icon(Icons.palette_outlined, size: 20),
                    label: const Text('تغيير اللون'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isApplyingBulkChange
                        ? null
                        : _showBulkSeriesDialog,
                    icon: const Icon(Icons.layers_outlined, size: 20),
                    label: const Text('تغيير السلسلة'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isApplyingBulkChange
                        ? null
                        : _showBulkGlassDialog,
                    icon: const Icon(Icons.window_outlined, size: 20),
                    label: const Text('تغيير الزجاج'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            if (_isReordering) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      Localization.translate(
                        'ترتيب العناصر',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _isReordering = false),
                      icon: const Icon(Icons.check),
                      label: Text(
                        Localization.translate(
                          'تم',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ...List.generate(addedProducts.length, (index) {
                final p = addedProducts[index];
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(
                      p.manualNameOverride?.trim().isNotEmpty == true
                          ? p.manualNameOverride!.trim()
                          : (p.isShutterOnly
                                ? 'Volet roulant'
                                : (p.isDoor
                                      ? (p.zones.any(
                                              (z) =>
                                                  z.content ==
                                                  ZoneContent.doubleSash,
                                            )
                                            ? t('باب بضلفتين')
                                            : t('باب بضلفة واحدة'))
                                      : (p.zones.any(
                                              (z) =>
                                                  z.content ==
                                                  ZoneContent.doubleSash,
                                            )
                                            ? t('نافذة بضلفتين')
                                            : t('نافذة بضلفة واحدة')))),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      '${p.width.toInt()}x${p.height.toInt()} mm - ${p.quantity} Pcs',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_upward,
                            color: Colors.blue,
                          ),
                          onPressed: index > 0
                              ? () {
                                  setState(() {
                                    final temp = addedProducts[index];
                                    addedProducts[index] =
                                        addedProducts[index - 1];
                                    addedProducts[index - 1] = temp;
                                  });
                                }
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_downward,
                            color: Colors.blue,
                          ),
                          onPressed: index < addedProducts.length - 1
                              ? () {
                                  setState(() {
                                    final temp = addedProducts[index];
                                    addedProducts[index] =
                                        addedProducts[index + 1];
                                    addedProducts[index + 1] = temp;
                                  });
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 15),
            ] else ...[
              if (addedProducts.isNotEmpty)
                ElegantAnimatedButton(
                  gradientColors: const [Colors.teal, Colors.cyan],
                  icon: const Icon(Icons.table_view, color: Colors.white),
                  label: Text(
                    Localization.translate(
                      "تعديل جدول الفاتورة (سريع)",
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  onPressed: _isLoadingEditProducts
                      ? null
                      : () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  OrderTableEditScreen(products: addedProducts),
                            ),
                          );
                          if (result == true) {
                            if (mounted) setState(() {});
                          }
                        },
                ),
              const SizedBox(height: 15),
              ...addedProducts.map((p) => _buildProductCard(p)),
              if (addedProducts.isNotEmpty) const SizedBox(height: 15),
            ],

            ElegantAnimatedButton(
              gradientColors: const [Colors.indigoAccent, Colors.blueAccent],
              onPressed: () async {
                if (selectedClient == null || selectedClient!.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        Localization.translate(
                          "Please select a client",
                          Provider.of<AppSettingsProvider>(
                            context,
                            listen: false,
                          ).language,
                        ),
                      ),
                    ),
                  );
                } else {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ChooseSysteme(initialSettings: _lastUsedSettings),
                    ),
                  );
                  if (result is WindowModel) {
                    _saveLastSettings(result);
                    setState(() {
                      addedProducts.add(result);
                      _highlightedProduct = result;
                    });
                    _scrollToHighlightedProduct();
                  } else if (result is List<WindowModel> && result.isNotEmpty) {
                    _saveLastSettings(result.last);
                    setState(() {
                      addedProducts.addAll(result);
                      _highlightedProduct = result.last;
                    });
                    _scrollToHighlightedProduct();
                  }
                }
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                Localization.translate(
                  'Add Product',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              height: 60,
            ),
            const SizedBox(height: 15),
            ElegantAnimatedButton(
              gradientColors: const [
                Colors.orangeAccent,
                Colors.deepOrangeAccent,
              ],
              onPressed: () => _showAddSpecialProductDialog(),
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                Localization.translate(
                  'Add Product Special',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              height: 55,
            ),
            const SizedBox(height: 15),

            TextField(
              controller: controller, // متحكم الملاحظات
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: Localization.translate(
                  'Notes',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                hintStyle: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: isDark
                      ? BorderSide(color: Colors.grey.shade800)
                      : const BorderSide(),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: isDark
                      ? BorderSide(color: Colors.grey.shade800)
                      : const BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(
                    color: Colors.blueAccent,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 15),

            if (Provider.of<AppSettingsProvider>(
              context,
            ).canChangePrices()) ...[
              _buildField(
                label: Localization.translate(
                  'Remise',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                controller: remiseController,
                icon: Icons.discount,
                readOnly: false,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                onChanged: (val) => setState(() {}),
              ),
              const SizedBox(height: 15),
              _buildField(
                label: Localization.translate(
                  'Tax Tva',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                controller: taxController,
                icon: Icons.percent,
                readOnly: false,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                onChanged: (val) => setState(() {}),
              ),
              const SizedBox(height: 15),
            ],

            // 🟢 حل مشكلة الأوفر فلو الأفقي في المربع السفلي (استخدام Expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.all(0),
              decoration: BoxDecoration(
                border: Border.all(
                  width: 1,
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                ),
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                    spreadRadius: 1,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(Icons.description, color: Colors.blueAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          Localization.translate(
                            'Description',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          Localization.translate(
                            'Totale Sans Tva :',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        "${finalTotal.toStringAsFixed(2)} DZD",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          t('مجموع الكميات :'),
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        "$totalQuantity",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          Localization.translate(
                            'Tax (Tva) :',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        "${calculatedTax.toStringAsFixed(2)} DZD",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.grey, thickness: 1.0, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          Localization.translate(
                            'Totale Avec Tva :',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        '${totalWithRemiseTax.toStringAsFixed(2)} DZD',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            ElegantAnimatedButton(
              gradientColors: const [Colors.green, Colors.teal],
              onPressed: (_isSaving || _isLoadingEditProducts)
                  ? null
                  : _saveCommande,
              icon: const Icon(Icons.save, color: Colors.white),
              label: Text(
                Localization.translate(
                  "Save",
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              height: 60,
            ),
            const SizedBox(height: 250),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    IconData? suffix,
    VoidCallback? onTap,
    bool readOnly = true,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        onTap: onTap,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: isDark ? Colors.white70 : Colors.blueGrey,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(icon, color: Colors.blueAccent),
          suffixIcon: suffix != null
              ? Icon(suffix, color: Colors.blueAccent)
              : null,
          filled: true,
          fillColor: Colors.transparent,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
          ),
        ),
      ),
    );
  }

  void _showAddSpecialProductDialog([WindowModel? existingProduct]) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final nameController = TextEditingController(
      text: existingProduct?.manualNameOverride ?? '',
    );
    final purchaseController = TextEditingController(
      text: existingProduct?.totalCost.toString() ?? '0',
    );
    final sellController = TextEditingController(
      text: existingProduct?.manualPriceOverride?.toString() ?? '',
    );
    final descController = TextEditingController(
      text: existingProduct?.description ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          existingProduct == null
              ? Localization.translate('إضافة منتج خاص', lang)
              : Localization.translate('تعديل المنتج الخاص', lang),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: Localization.translate('اسم المنتج', lang) + ' *',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: purchaseController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Localization.translate(
                    'سعر الشراء (اختياري)',
                    lang,
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sellController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Localization.translate('سعر البيع', lang) + ' *',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: Localization.translate('الوصف', lang),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(Localization.translate('إلغاء', lang)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      Localization.translate('يرجى إدخال اسم المنتج', lang),
                    ),
                  ),
                );
                return;
              }
              final sellPrice = double.tryParse(sellController.text.trim());
              if (sellPrice == null || sellPrice <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      Localization.translate('يرجى إدخال سعر بيع صحيح', lang),
                    ),
                  ),
                );
                return;
              }
              final purchasePrice =
                  double.tryParse(purchaseController.text.trim()) ?? 0.0;

              if (existingProduct == null) {
                final newProduct = WindowModel(db: widget.db);
                newProduct.isCustomProduct = true;
                newProduct.manualNameOverride = name;
                newProduct.totalCost = purchasePrice;
                newProduct.manualPriceOverride = sellPrice;
                newProduct.description = descController.text.trim();
                newProduct.width = 0.0;
                newProduct.height = 0.0;
                setState(() {
                  addedProducts.add(newProduct);
                  _highlightedProduct = newProduct;
                });
                _scrollToHighlightedProduct();
              } else {
                setState(() {
                  existingProduct.manualNameOverride = name;
                  existingProduct.totalCost = purchasePrice;
                  existingProduct.manualPriceOverride = sellPrice;
                  existingProduct.description = descController.text.trim();
                  _highlightedProduct = existingProduct;
                });
                _scrollToHighlightedProduct();
              }

              Navigator.pop(context);
            },
            child: Text(Localization.translate('حفظ', lang)),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(WindowModel p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (p.isCustomProduct) {
      final valStr = ((p.manualPriceOverride ?? 0.0) * p.quantity)
          .toStringAsFixed(2);
      final totalLabel = '${t('المجموع:')} $valStr ${t('دج')}';
      final desc = p.description ?? '';

      final cardKey = _cardKeys.putIfAbsent(p, () => GlobalKey());
      bool isHighlighted = _highlightedProduct == p;

      return Card(
        key: cardKey,
        elevation: isHighlighted ? 8 : 4,
        shadowColor: isHighlighted ? Colors.blue.withOpacity(0.5) : null,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(
            color: isHighlighted ? Colors.blue.shade400 : Colors.transparent,
            width: isHighlighted ? 2.5 : 0,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      p.manualNameOverride ?? t('منتج خاص'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showAddSpecialProductDialog(p),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(t('حذف المنتج')),
                              content: Text(
                                t('هل أنت متأكد أنك تريد حذف هذا المنتج؟'),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: Text(t('إلغاء')),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      addedProducts.remove(p);
                                    });
                                    Navigator.pop(ctx);
                                  },
                                  child: Text(t('Delete')),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        t('الكمية: '),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      QuantityInput(
                        initialValue: p.quantity,
                        onChanged: (val) {
                          setState(() {
                            p.quantity = val;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    totalLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${t('الوصف')}: $desc',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }

    final cardKey = _cardKeys.putIfAbsent(p, () => GlobalKey());
    bool isHighlighted = _highlightedProduct == p;

    final bool isCaisson =
        p.isCaissonTunnel ||
        (p.manualNameOverride?.contains('Caisson Tunnel') == true) ||
        (p.manualNameOverride?.contains('Caisson Tunnel') == true);

    final bool isMoustiquaire =
        p.isMoustiquaire ||
        (p.manualNameOverride?.contains('Moustiquaire') == true) ||
        (p.manualNameOverride?.contains('موستيكير') == true) ||
        (p.manualNameOverride?.contains('ناموسية') == true);
    final bool isGlassWork =
        p.isGlassWork ||
        (p.manualNameOverride?.contains('Verre Trempé') == true) ||
        (p.manualNameOverride?.contains('عمل زجاجي') == true);

    if (isCaisson) {
      p.isCaissonTunnel = true;
      p.isReplaced = false;
    }

    if (isMoustiquaire) {
      p.isMoustiquaire = true;
      p.isReplaced = false;
    }
    if (isGlassWork) {
      p.isGlassWork = true;
      p.isReplaced = false;
    }

    final invoiceLine = _invoiceLineForProduct(p);
    final invoiceDetails = invoiceLine.details;

    return Card(
      key: cardKey,
      elevation: isHighlighted ? 8 : 4,
      shadowColor: isHighlighted ? Colors.blue.withOpacity(0.5) : null,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: isHighlighted ? Colors.blue.shade400 : Colors.transparent,
          width: isHighlighted ? 2.5 : 0,
        ),
      ),
      color: isDark
          ? ((p.isReplaced && !isCaisson)
                ? Colors.grey.shade900
                : const Color(0xFF1E1E1E))
          : ((p.isReplaced && !isCaisson)
                ? const Color(0xFFF5F5F5)
                : Colors.white),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomPaint(
              foregroundPainter: (p.isReplaced && !isCaisson)
                  ? CardCrossPainter()
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          isCaisson
                              ? (() {
                                  String dimSummary = '';
                                  if (p.caissonPayload != null &&
                                      p.caissonPayload!['items'] != null) {
                                    final itemsList =
                                        (p.caissonPayload!['items'] as List);
                                    if (itemsList.isNotEmpty) {
                                      final firstMap = itemsList.first as Map;
                                      final double lengthMm =
                                          (firstMap['lengthMm'] as num? ?? 0.0)
                                              .toDouble();
                                      final int sizeCm =
                                          (firstMap['sizeCm'] as num? ?? 25)
                                              .toInt();
                                      final String lenStr = (lengthMm / 10.0)
                                          .toStringAsFixed(0);
                                      dimSummary =
                                          ' ($lenStr سم - صندوق $sizeCm سم)';
                                    }
                                  }
                                  return '${invoiceLine.title}$dimSummary';
                                })()
                              : invoiceLine.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: (p.isReplaced && !isCaisson)
                                ? Colors.grey
                                : Colors.blueAccent,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          if (!p.isReplaced) ...[
                            IconButton(
                              icon: const Icon(
                                Icons.upgrade,
                                color: Colors.deepOrange,
                              ),
                              tooltip: t('تعديل (Amélioration)'),
                              onPressed: () {
                                _showUpgradeDialog(p);
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.table_chart,
                                color: Colors.purple,
                              ),
                              tooltip: 'جدول المقاسات (Edit Table Details)',
                              onPressed: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        OrderTableEditScreen(products: [p]),
                                  ),
                                );
                                if (result == true) {
                                  if (mounted) {
                                    setState(() {
                                      _highlightedProduct = p;
                                    });
                                    _scrollToHighlightedProduct();
                                  }
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () async {
                                if (p.isCaissonTunnel ||
                                    (p.manualNameOverride?.contains(
                                          'Caisson Tunnel',
                                        ) ==
                                        true)) {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CaissonTunnelScreen(
                                        initialPayload: p.caissonPayload,
                                      ),
                                    ),
                                  );
                                  if (result != null &&
                                      result is Map<String, dynamic> &&
                                      mounted) {
                                    final int cBars =
                                        (result['grandTotalCaissonBars']
                                            as int? ??
                                        0);
                                    final int bBars =
                                        (result['grandTotalBottomCoverBars']
                                            as int? ??
                                        0);
                                    final int pairs =
                                        (result['grandTotalPairs'] as int? ??
                                        0);

                                    // Compute suggested price from DB prices
                                    double suggestedPrice = 0.0;
                                    try {
                                      final ctPrices = await widget.db
                                          .getCaissonTunnelPrices();
                                      if (ctPrices.isNotEmpty) {
                                        // Use first color entry (or match by color if set)
                                        final priceRow = ctPrices.first;
                                        final profileBar =
                                            (priceRow['profile_price_per_bar']
                                                        as num? ??
                                                    0)
                                                .toDouble();
                                        final bottomBar =
                                            (priceRow['bottom_cover_price_per_bar']
                                                        as num? ??
                                                    0)
                                                .toDouble();
                                        suggestedPrice =
                                            (cBars * profileBar) +
                                            (bBars * bottomBar);
                                      }
                                    } catch (_) {}

                                    if (mounted) {
                                      setState(() {
                                        p.isCaissonTunnel = true;
                                        p.isReplaced = false;
                                        p.manualNameOverride = 'Caisson Tunnel';
                                        p.description =
                                            'Kit: ${result['kitType']} | Barres caisson: $cBars (6m) | Fond: $bBars (6m) | Paires: $pairs';
                                        p.caissonPayload = result;
                                        if (suggestedPrice > 0 &&
                                            p.manualPriceOverride == null) {
                                          p.manualPriceOverride =
                                              suggestedPrice;
                                        }
                                        _highlightedProduct = p;
                                      });
                                      _saveLastSettings(p);
                                      _scrollToHighlightedProduct();
                                    }
                                  }
                                  return;
                                }

                                if (p.isGlassWork ||
                                    (p.manualNameOverride?.contains(
                                          'Verre Trempé',
                                        ) ==
                                        true)) {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          TemperedGlassWorkScreen(
                                            initialPayload: p.glassWorkPayload,
                                          ),
                                    ),
                                  );
                                  if (result is Map<String, dynamic> &&
                                      mounted) {
                                    final models = _modelsFromGlassWorkPayload(
                                      result,
                                    );
                                    setState(() {
                                      _replaceProductWithIndependentModels(
                                        p,
                                        models,
                                      );
                                    });
                                    if (models.isNotEmpty) {
                                      _saveLastSettings(models.last);
                                    }
                                    _scrollToHighlightedProduct();
                                  }
                                  return;
                                }

                                if (p.isMoustiquaire ||
                                    (p.manualNameOverride?.contains(
                                          'Moustiquaire',
                                        ) ==
                                        true) ||
                                    (p.manualNameOverride?.contains(
                                          'موستيكير',
                                        ) ==
                                        true)) {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => MoustiquaireScreen(
                                        initialPayload: p.moustiquairePayload,
                                      ),
                                    ),
                                  );
                                  if (result is Map<String, dynamic> &&
                                      mounted) {
                                    final models =
                                        _modelsFromMoustiquairePayload(result);
                                    setState(() {
                                      _replaceProductWithIndependentModels(
                                        p,
                                        models,
                                      );
                                    });
                                    if (models.isNotEmpty) {
                                      _saveLastSettings(models.last);
                                    }
                                    _scrollToHighlightedProduct();
                                  }
                                  return;
                                }

                                // العودة إلى الرسم لتعديل النافذة أو الستار
                                if (p.isShutterOnly) {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          SystemRoling(model: p),
                                    ),
                                  );
                                } else {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => WindowView(
                                        model: p,
                                        systemMode: 'mixed',
                                      ),
                                    ),
                                  );
                                }
                                _saveLastSettings(p);
                                // بمجرد العودة (حتى لو لم يضغط إضافة للطلبية، فالمودل يعدل مباشرة في الذاكرة)
                                // نعمل setState لتحديث الصورة والتكلفة ونحدد الإضاءة والتحريك
                                setState(() {
                                  _highlightedProduct = p;
                                });
                                _scrollToHighlightedProduct();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, color: Colors.green),
                              tooltip: 'تكرار (Duplicate)',
                              onPressed: () {
                                final cloned = WindowModel(db: p.db);
                                final map = p.toMap();
                                applyWindowModelFromMap(cloned, map);
                                cloned.availableSystems = List.from(
                                  p.availableSystems,
                                );
                                cloned.activeSeries = p.activeSeries;
                                cloned.availableColors = List.from(
                                  p.availableColors,
                                );
                                cloned.quantity =
                                    1; // Default to 1 for the new clone
                                setState(() {
                                  addedProducts.add(cloned);
                                  _highlightedProduct = cloned;
                                });
                                _saveLastSettings(cloned);
                                _scrollToHighlightedProduct();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      t('تم استنساخ النافذة بنجاح'),
                                    ),
                                    backgroundColor: Colors.green,
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                          ],
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(t('حذف النافذة')),
                                  content: Text(
                                    t(
                                      'هل أنت متأكد أنك تريد حذف هذه النافذة من الطلبية؟',
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: Text(t('إلغاء')),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          addedProducts.remove(p);
                                        });
                                        Navigator.pop(ctx);
                                      },
                                      child: Text(t('Delete')),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...invoiceDetails.map(
                              (detail) => Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: _detailRichText(
                                  detail,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: p.isReplaced
                                        ? Colors.grey
                                        : (isDark
                                              ? Colors.white70
                                              : Colors.black87),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (p.isReplaced)
                              Text(
                                '${t('الكمية:')} ${p.quantity}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              )
                            else
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    t('الكمية: '),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  QuantityInput(
                                    initialValue: p.quantity,
                                    onChanged: (val) {
                                      setState(() {
                                        p.quantity = val;
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            const SizedBox(height: 4),
                            Text(
                              '${t('المجموع:')} ${((p.manualPriceOverride ?? p.totalCost) * p.quantity).toStringAsFixed(2)} ${t('دج')}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: p.isReplaced
                                    ? Colors.grey
                                    : Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        children: [
                          Text(
                            isGlassWork
                                ? t('صورة العمل الزجاجي')
                                : (isMoustiquaire
                                      ? t('صورة الموستيكير')
                                      : t('شكل النافذة')),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Container(
                            height: 130,
                            width: 130,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: isCaisson
                                ? Image.asset(
                                    'Icon/caisson_tunnel.jpg',
                                    fit: BoxFit.contain,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Image.asset(
                                              'assets/Icon/caisson_tunnel.jpg',
                                              fit: BoxFit.contain,
                                            ),
                                  )
                                : isMoustiquaire
                                ? Image.asset(
                                    'Icon/media.webp',
                                    fit: BoxFit.contain,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Image.asset(
                                              'assets/Icon/media.webp',
                                              fit: BoxFit.contain,
                                            ),
                                  )
                                : isGlassWork
                                ? Builder(
                                    builder: (context) {
                                      final path = p
                                          .glassWorkPayload?['imagePath']
                                          ?.toString();
                                      if (path != null &&
                                          path.isNotEmpty &&
                                          File(path).existsSync()) {
                                        return Image.file(
                                          File(path),
                                          fit: BoxFit.contain,
                                        );
                                      }
                                      return Image.asset(
                                        'Icon/verre.png',
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                const Icon(
                                                  Icons.window_rounded,
                                                  color: Colors.cyan,
                                                  size: 56,
                                                ),
                                      );
                                    },
                                  )
                                : IgnorePointer(
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: Opacity(
                                        opacity: p.isReplaced ? 0.5 : 1.0,
                                        child: CustomPaint(
                                          size: Size(
                                            p.width.toDouble(),
                                            p.height.toDouble(),
                                          ),
                                          painter: WindowPainter(model: p),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: p.isReplaced
                        ? MainAxisAlignment.spaceBetween
                        : MainAxisAlignment.end,
                    children: [
                      if (p.isReplaced)
                        Text(
                          t('(عنصر مستبدل - غير محسوب في المجموع)'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      Text(
                        '${t('السعر:')} ${(p.manualPriceOverride ?? p.totalCost).toStringAsFixed(2)} ${t('دج')}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: p.isReplaced ? Colors.grey : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (p.isReplaced && p.replacementReason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  border: Border.all(color: Colors.amber.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.amber.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'سبب التعديل: ${p.replacementReason}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_note, color: Colors.amber),
                      tooltip: t('تعديل السبب'),
                      onPressed: () {
                        _showEditReasonDialog(p);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showUpgradeDialog(WindowModel p) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        final bool isDark = Provider.of<AppSettingsProvider>(
          context,
          listen: false,
        ).isDarkMode;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
          title: Text(
            'تعديل الطلبية (Amélioration)',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'عند القيام بهذا التعديل، سيتم الاحتفاظ بهذا العنصر الحالي مع إظهاره مشطوباً في الفاتورة (دون احتسابه في السعر الكلي) وإضافة نسخة جديدة منه وتعديلها.',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  maxLength: 1000,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: isDark
                            ? const Color(0xFF374151)
                            : Colors.black26,
                      ),
                    ),
                    labelText: t('سبب التعديل / الإلغاء'),
                    labelStyle: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    hintText:
                        'اكتب هنا سبب إلغاء هذا العنصر وتفعيل التعديل الجديد...',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white30 : Colors.black38,
                    ),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                t('إلغاء'),
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final reason = controller.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t('الرجاء إدخال سبب التعديل'))),
                  );
                  return;
                }
                Navigator.pop(ctx);

                // 1. Mark the current one as replaced
                p.isReplaced = true;
                p.replacementReason = reason;

                // 2. Clone the window model
                final cloned = WindowModel(db: p.db);
                final map = p.toMap();
                applyWindowModelFromMap(cloned, map);
                cloned.availableSystems = List.from(p.availableSystems);
                cloned.activeSeries = p.activeSeries;
                cloned.availableColors = List.from(p.availableColors);
                cloned.quantity = p.quantity;
                cloned.isReplaced = false;
                cloned.replacementReason = '';

                // 3. Insert the clone right after the original item in the list
                final idx = addedProducts.indexOf(p);
                if (idx != -1) {
                  setState(() {
                    addedProducts.insert(idx + 1, cloned);
                    _highlightedProduct = cloned;
                  });
                } else {
                  setState(() {
                    addedProducts.add(cloned);
                    _highlightedProduct = cloned;
                  });
                }

                // 4. Directly open the window view to edit the clone
                if (cloned.isShutterOnly) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SystemRoling(model: cloned),
                    ),
                  );
                } else {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WindowView(
                        model: cloned,
                        // Editing an existing window must always expose both
                        // French and sliding tools, whatever its original mode.
                        systemMode: 'mixed',
                      ),
                    ),
                  );
                }
                _saveLastSettings(cloned);

                // 5. Trigger calculation and refresh UI
                setState(() {
                  _highlightedProduct = cloned;
                });
                _scrollToHighlightedProduct();
                await _calculateGlobalMaterialsAndCost();
              },
              child: Text(
                t('تعديل (Amélioration)'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showEditReasonDialog(WindowModel p) {
    final controller = TextEditingController(text: p.replacementReason);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          t('تعديل سبب التعديل'),
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 1000,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            labelText: t('سبب التعديل / الإلغاء'),
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('إلغاء')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t('الرجاء إدخال سبب التعديل'))),
                );
                return;
              }
              setState(() {
                p.replacementReason = reason;
              });
              Navigator.pop(ctx);
            },
            child: Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class ClientDropdownDialog extends StatefulWidget {
  final SqlDatabase db;

  const ClientDropdownDialog({super.key, required this.db});

  @override
  State<ClientDropdownDialog> createState() => _ClientDropdownDialogState();
}

class _ClientDropdownDialogState extends State<ClientDropdownDialog> {
  List<Map<String, dynamic>> clients = [];
  List<Map<String, dynamic>> filtered = [];

  TextEditingController search = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadData();
  }

  // 🟢 التخلص من متحكم البحث لتفريغ الذاكرة
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void loadData() async {
    final data = await widget.db.readClient();

    setState(() {
      clients = data;
      filtered = data;
    });
  }

  String normalizeArabic(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[ً-ٟـ]'), '');
  }

  bool matchClient(Map<String, dynamic> c, String query) {
    if (query.trim().isEmpty) return true;

    List<String> qTerms = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();

    final first = normalizeArabic(c['firstname'] ?? '');
    final last = normalizeArabic(c['lastname'] ?? '');
    final phone1 = normalizeArabic(c['phone1'] ?? '');
    final phone2 = normalizeArabic(c['phone2'] ?? '');

    final full = "$first $last $phone1 $phone2";

    return qTerms.every((term) {
      final t = normalizeArabic(term);
      return full.contains(t);
    });
  }

  TextSpan highlightText(String text, String query) {
    final bool isDark = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).isDarkMode;
    final Color textColor = isDark ? Colors.white : Colors.black87;

    if (query.trim().isEmpty) {
      return TextSpan(
        text: text,
        style: TextStyle(color: textColor),
      );
    }

    List<String> queryWords = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (queryWords.isEmpty) {
      return TextSpan(
        text: text,
        style: TextStyle(color: textColor),
      );
    }

    String pattern = queryWords.map((w) => RegExp.escape(w)).join('|');
    RegExp regExp = RegExp('($pattern)', caseSensitive: false);

    List<TextSpan> spans = [];
    int start = 0;
    for (var match in regExp.allMatches(text)) {
      if (match.start > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, match.start),
            style: TextStyle(color: textColor),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(
            color: Colors.blue,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.yellow.withValues(alpha: 0.3),
          ),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(start),
          style: TextStyle(color: textColor),
        ),
      );
    }

    return TextSpan(children: spans);
  }

  void searchClient(String value) {
    setState(() {
      if (value.isEmpty) {
        filtered = clients;
      } else {
        filtered = clients.where((c) {
          return matchClient(c, value);
        }).toList();
      }
    });
  }

  void _showAddClientDialog() {
    String initialFirst = search.text;
    String initialLast = '';

    if (search.text.contains(' ')) {
      var parts = search.text.split(RegExp(r'\s+'));
      initialFirst = parts.first;
      initialLast = parts.sublist(1).join(' ');
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return DynamicDialog(
          title: "Add Client",
          content: '',
          button: "Add",
          fields: [
            FormFieldConfig(
              label: "First Name",
              type: FieldType.text,
              initialValue: initialFirst,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Please enter a first name";
                }
                return null;
              },
            ),
            FormFieldConfig(
              label: "Last Name",
              type: FieldType.text,
              initialValue: initialLast,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Please enter a last name";
                }
                return null;
              },
            ),
            FormFieldConfig(
              label: "Phone Number 1",
              type: FieldType.text,
              keyboardType: TextInputType.number,
              maxLenght: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Please enter a phone number";
                }
                return null;
              },
            ),
            FormFieldConfig(
              label: "Phone Number 2",
              type: FieldType.text,
              keyboardType: TextInputType.number,
              maxLenght: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            FormFieldConfig(label: "Email", type: FieldType.text),
            FormFieldConfig(label: "Address", type: FieldType.text),
          ],
          onSubmit: (values) async {
            try {
              await widget.db.insertClient(
                values[0],
                values[1],
                values[2],
                values[3],
                values[4],
                values[5],
              );
            } catch (e) {
              debugPrint("Error inserting client: $e");
            }

            if (!mounted) return;

            final data = await widget.db.readClient();
            setState(() {
              clients = data;
            });
            searchClient(search.text);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  Localization.translate(
                    "Client added",
                    Provider.of<AppSettingsProvider>(
                      context,
                      listen: false,
                    ).language,
                  ),
                ),
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.green,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(30)),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Provider.of<AppSettingsProvider>(context).isDarkMode;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              Localization.translate(
                "Select Client",
                Provider.of<AppSettingsProvider>(context).language,
              ),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: search,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      hintText: "Search...",
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF1F2937)
                          : Colors.transparent,
                      border: const OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: isDark
                              ? const Color(0xFF374151)
                              : Colors.black26,
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue, width: 2),
                      ),
                    ),
                    onChanged: searchClient,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.person_add, color: Colors.white),
                    onPressed: _showAddClientDialog,
                    tooltip: Localization.translate(
                      'Add Client',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            SizedBox(
              height: 250,
              child: filtered.isEmpty && search.text.isNotEmpty
                  ? Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                        ),
                        onPressed: _showAddClientDialog,
                        icon: const Icon(Icons.person_add, color: Colors.white),
                        label: Text(
                          '${Localization.translate('إضافة', Provider.of<AppSettingsProvider>(context).language)} "${search.text}"',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final c = filtered[index];

                        return ListTile(
                          title: RichText(
                            text: highlightText(
                              "${c['firstname']} ${c['lastname']}",
                              search.text,
                            ),
                          ),
                          trailing: RichText(
                            text: highlightText("${c['phone1']}", search.text),
                          ),
                          onTap: () {
                            Navigator.pop(context, c);
                          },
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

class QuantityInput extends StatefulWidget {
  final int initialValue;
  final ValueChanged<int> onChanged;

  const QuantityInput({
    Key? key,
    required this.initialValue,
    required this.onChanged,
  }) : super(key: key);

  @override
  _QuantityInputState createState() => _QuantityInputState();
}

class _QuantityInputState extends State<QuantityInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue.toString());
  }

  @override
  void didUpdateWidget(covariant QuantityInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue.toString() != _controller.text) {
      _controller.text = widget.initialValue.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _increment() {
    int current = int.tryParse(_controller.text) ?? 1;
    current++;
    _controller.text = current.toString();
    widget.onChanged(current);
  }

  void _decrement() {
    int current = int.tryParse(_controller.text) ?? 1;
    if (current > 1) {
      current--;
      _controller.text = current.toString();
      widget.onChanged(current);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
          onPressed: _decrement,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          height: 35,
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: 4,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (val) {
              int? parsed = int.tryParse(val);
              if (parsed != null && parsed > 0) {
                widget.onChanged(parsed);
              }
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Colors.green),
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
          onPressed: _increment,
        ),
      ],
    );
  }
}

class ElegantAnimatedButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;
  final List<Color> gradientColors;
  final double height;

  const ElegantAnimatedButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    required this.gradientColors,
    this.height = 55,
  });

  @override
  State<ElegantAnimatedButton> createState() => _ElegantAnimatedButtonState();
}

class _ElegantAnimatedButtonState extends State<ElegantAnimatedButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onPressed != null;
    return GestureDetector(
      onTapDown: isEnabled ? (_) => setState(() => _scale = 0.95) : null,
      onTapUp: isEnabled ? (_) => setState(() => _scale = 1.0) : null,
      onTapCancel: isEnabled ? () => setState(() => _scale = 1.0) : null,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          width: double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isEnabled
                  ? widget.gradientColors
                  : [Colors.grey.shade400, Colors.grey.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: widget.gradientColors.first.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: widget.onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  widget.icon!,
                  const SizedBox(width: 8),
                ],
                widget.label,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CardCrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.4)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ProjectDropdownDialog extends StatefulWidget {
  final SqlDatabase db;
  final int clientId;

  const ProjectDropdownDialog({
    super.key,
    required this.db,
    required this.clientId,
  });

  @override
  State<ProjectDropdownDialog> createState() => _ProjectDropdownDialogState();
}

class _ProjectDropdownDialogState extends State<ProjectDropdownDialog> {
  List<Map<String, dynamic>> projects = [];
  List<Map<String, dynamic>> filtered = [];
  TextEditingController search = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void loadData() async {
    final data = await widget.db.readProjectsForClient(widget.clientId);
    setState(() {
      projects = data;
      filtered = data;
    });
  }

  void searchProject(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        filtered = projects;
      } else {
        filtered = projects.where((p) {
          final name = (p['name'] ?? '').toString().toLowerCase();
          final desc = (p['description'] ?? '').toString().toLowerCase();
          final q = query.trim().toLowerCase();
          return name.contains(q) || desc.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              Localization.translate("اختيار المشروع", lang),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: search,
              decoration: InputDecoration(
                hintText: Localization.translate("البحث...", lang),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: searchProject,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 250,
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        Localization.translate(
                          "لا توجد مشاريع لهذا الزبون",
                          lang,
                        ),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return ListTile(
                            leading: const Icon(Icons.clear, color: Colors.red),
                            title: Text(
                              Localization.translate(
                                "بدون مشروع / إلغاء الربط",
                                lang,
                              ),
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onTap: () => Navigator.pop(context, 'clear'),
                          );
                        }
                        final p = filtered[index - 1];
                        return ListTile(
                          leading: const Icon(Icons.folder, color: Colors.blue),
                          title: Text(p['name']),
                          subtitle:
                              p['description'] != null &&
                                  p['description'].toString().isNotEmpty
                              ? Text(p['description'])
                              : null,
                          onTap: () => Navigator.pop(context, p),
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
