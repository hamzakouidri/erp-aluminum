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
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'package:database_data/Commande/Systeme/show_system_francais.dart';
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
import 'package:database_data/utils/real_color_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

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
        product.activeFrameSeries?.name ??
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
  bool _isBulkSelectionMode = false;
  String _editOrderStatus = 'Pending';
  bool _editOrderStatusLoaded = false;
  double _editAdvancePayment = 0.0;

  String _normalizedOrderStatus(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll(RegExp(r'\s+'), ' ');

  double _readMoney(dynamic value) {
    if (value is num) return value.toDouble();
    final normalized = value?.toString().trim().replaceAll(',', '.') ?? '';
    return double.tryParse(normalized) ?? 0.0;
  }

  bool _isPendingOrderStatus(String value) {
    final status = _normalizedOrderStatus(value);
    return status == 'pending' ||
        status == 'draft' ||
        status == 'new' ||
        status == 'en attente' ||
        status == 'en_attente' ||
        status == 'في الانتظار';
  }

  void _moveProductToPosition(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex < 0 || oldIndex >= addedProducts.length) return;
    newIndex = newIndex.clamp(0, addedProducts.length - 1).toInt();
    if (oldIndex == newIndex) return;

    setState(() {
      final product = addedProducts.removeAt(oldIndex);
      addedProducts.insert(newIndex, product);
    });
  }

  bool get _showEditPaymentSummary =>
      widget.editCommandeId != null &&
      _editOrderStatusLoaded &&
      !_isPendingOrderStatus(_editOrderStatus);

  bool get _bulkChangesAllowed {
    if (widget.editCommandeId == null) return true;
    if (!_editOrderStatusLoaded) return false;
    final status = _normalizedOrderStatus(_editOrderStatus);
    return status == 'pending' ||
        status == 'draft' ||
        status == 'new' ||
        status == 'en attente' ||
        status == 'en_attente' ||
        status == 'في الانتظار' ||
        status == 'confirmed' ||
        status == 'confirme' ||
        status == 'مؤكد' ||
        status == 'مؤكدة';
  }

  void _showBulkChangesBlockedMessage() {
    final status = _editOrderStatus.trim().isEmpty
        ? 'غير معروفة'
        : _editOrderStatus.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.orange.shade800,
        content: Text(
          'لا يمكن تغيير السلسلة أو اللون أو الزجاج الآن. حالة الطلبية: '
          '$status. هذه التغييرات متاحة فقط في الانتظار أو المؤكدة، '
          'وبعد بدء التصنيع يجب إرجاع الطلبية يدويًا أولاً.',
        ),
      ),
    );
  }

  bool _isBulkEditableProduct(WindowModel product) {
    return !product.isReplaced &&
        !product.isGlassWork &&
        !product.isMoustiquaire &&
        !product.isCaissonTunnel;
  }

  void _enterBulkSelectionMode() {
    if (_isBulkSelectionMode) return;
    setState(() {
      _isBulkSelectionMode = true;
      _bulkSelectedProducts.clear();
    });
  }

  void _exitBulkSelectionMode() {
    setState(() {
      _isBulkSelectionMode = false;
      _bulkSelectedProducts.clear();
    });
  }

  void _toggleBulkProduct(WindowModel product) {
    if (!_isBulkEditableProduct(product)) return;
    setState(() {
      if (_bulkSelectedProducts.contains(product)) {
        _bulkSelectedProducts.remove(product);
      } else {
        _bulkSelectedProducts.add(product);
      }
    });
  }

  void _toggleAllBulkProducts() {
    final products = _bulkEditableProducts();
    setState(() {
      if (_bulkSelectedProducts.length == products.length) {
        _bulkSelectedProducts.clear();
      } else {
        _bulkSelectedProducts
          ..clear()
          ..addAll(products);
      }
    });
  }

  WindowModel? _highlightedProduct;
  final Map<WindowModel, GlobalKey> _cardKeys = {};
  // Existing detail IDs must stay attached to their drawing while an order is
  // edited. Recreating rows with new IDs makes cloud sync reintroduce an old
  // copy of the same window (often with its former colour).
  final Map<WindowModel, int> _persistedDetailIds = {};
  final ScrollController _scrollController = ScrollController();
  Timer? _reorderAutoScrollTimer;
  bool _reorderDragActive = false;
  double? _lastReorderPointerY;

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

  void _startReorderDrag(int index) {
    _reorderDragActive = true;
    _lastReorderPointerY = null;
    _reorderAutoScrollTimer?.cancel();
    _reorderAutoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _autoScrollWhileReordering(),
    );
  }

  void _finishReorderDrag(int index) {
    _reorderDragActive = false;
    _lastReorderPointerY = null;
    _reorderAutoScrollTimer?.cancel();
    _reorderAutoScrollTimer = null;
  }

  void _handleReorderPointerMove(PointerMoveEvent event) {
    if (_reorderDragActive) {
      _lastReorderPointerY = event.position.dy;
    }
  }

  void _autoScrollWhileReordering() {
    if (!mounted ||
        !_reorderDragActive ||
        _lastReorderPointerY == null ||
        !_scrollController.hasClients) {
      return;
    }

    final screenHeight = MediaQuery.sizeOf(context).height;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    const edgeDistance = 88.0;
    final topEdge = topInset + edgeDistance;
    final bottomEdge =
        screenHeight - MediaQuery.paddingOf(context).bottom - edgeDistance;
    final pointerY = _lastReorderPointerY!;

    double delta = 0;
    if (pointerY < topEdge) {
      final factor = ((topEdge - pointerY) / edgeDistance)
          .clamp(0.0, 1.0)
          .toDouble();
      delta = -18.0 * factor;
    } else if (pointerY > bottomEdge) {
      final factor = ((pointerY - bottomEdge) / edgeDistance)
          .clamp(0.0, 1.0)
          .toDouble();
      delta = 18.0 * factor;
    }

    if (delta == 0) return;
    final position = _scrollController.position;
    final nextOffset = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (nextOffset != position.pixels) {
      _scrollController.jumpTo(nextOffset.toDouble());
    }
  }

  // حفظ آخر خصائص مستخدمة داخل نفس الطلبية
  Map<String, dynamic>? _lastUsedSettings;

  /// تحديث حفظ الخصائص من نموذج نافذة
  void _saveLastSettings(WindowModel m) {
    final glassSpec = WindowZone.globalDefaultGlass.toMap();
    final modelMap = m.toMap();
    const defaultKeys = {
      'hasBottomFrame',
      'hasFramePlintheBottom',
      'isInternalView',
      'showInternalHardware',
      'hasShutter',
      'shutterIntercalaireRatio',
      'shutterMechanism',
      'motorHasInterrupteur',
      'motorHasTelecommande',
      'shutterLame',
      'shutterGlissiere',
      'shutterPosition',
      'shutterDriveSide',
      'customShutterBoxHeight',
      'selectedShutterLameId',
      'selectedShutterKitId',
      'selectedShutterMotorId',
      'useSystemOB',
      'useDemiOB',
      'useVerrouCentral',
      'hasSideCovers',
      'sideCoverUseSecondWidth',
      'hasInternalSlidingSideCover',
      'useCustomSideCoverLayout',
      'sideCoverSegments',
      'hiddenSideCoverSegments',
      'isFrame140',
      'removedShutterSides',
      'frameColor',
      'selectedDbColor',
      'selectedColorName',
      'selectedColorHex',
      'selectedAccessoryColor',
      'primaryMullionAxis',
      'mullionProfiles',
      'groovedMullionCavityOnPositiveSide',
      'mullionSectionOverrides',
      'componentOverrides',
      'frameOverride',
      'sashOverride',
      'sideCoverOverride',
      'internalSlidingSideCoverOverride',
      'slidingFrameOverride',
      'slidingSashOverride',
    };
    final drawingDefaults = <String, dynamic>{
      for (final key in defaultKeys)
        if (modelMap.containsKey(key)) key: modelMap[key],
      'glassSpec': glassSpec,
    };
    _lastUsedSettings = {
      'activeSeries': m.activeSeries,
      'activeSlidingSeries': m.activeSlidingSeries,
      'loadedSeriesId': m.activeFrameSeries?.id ?? m.loadedSeriesId,
      'loadedSlidingSeriesId':
          m.activeSlidingSeries?.id ?? m.loadedSlidingSeriesId,
      'loadedSeriesName': m.activeFrameSeries?.name ??
          m.loadedSeriesName ??
          m.manualNameOverride,
      'loadedSlidingSeriesName':
          m.activeSlidingSeries?.name ?? m.loadedSlidingSeriesName,
      'selectedDbColor': m.selectedDbColor != null
          ? Map<String, dynamic>.from(m.selectedDbColor!)
          : null,
      'selectedAccessoryColor': m.selectedAccessoryColor != null
          ? Map<String, dynamic>.from(m.selectedAccessoryColor!)
          : null,
      'glassSpec': glassSpec,
      'drawingDefaults': drawingDefaults,
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
      final shapeLabel = payload['panelShapeLabel']?.toString() ?? 'مستقيم (I)';
      final operationLabel = payload['operationLabel']?.toString() ?? 'منزلق';
      final kitLabel = payload['selectedKitLabel']?.toString() ?? '';
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
      model.manualNameOverride = 'Verre Trempé - $workLabel - $shapeLabel';
      model.description =
          '$operationLabel${kitLabel.isEmpty ? '' : ' | $kitLabel'} | $shapeLabel | '
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

    _editOrderStatusLoaded = widget.editCommandeId == null;

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
      final drawingProducts = addedProducts
          .where(
            (product) =>
                !product.isCustomProduct &&
                !product.isGlassWork &&
                !product.isMoustiquaire &&
                !product.isCaissonTunnel,
          )
          .toList();
      if (drawingProducts.isNotEmpty) {
        _saveLastSettings(drawingProducts.last);
      }
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
    _reorderAutoScrollTimer?.cancel();
    clientController.dispose();
    quoteDateController.dispose();
    validDateController.dispose();
    controller.dispose();
    remiseController.dispose();
    taxController.dispose();
    projectController.dispose();
    _scrollController.dispose();
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
        _editOrderStatus = cmd['status']?.toString().trim().isNotEmpty == true
            ? cmd['status'].toString()
            : 'Pending';
        _editOrderStatusLoaded = true;
        _editAdvancePayment = _readMoney(cmd['advance_payment']);
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
        if (game.isNotEmpty &&
            (model.manualNameOverride?.trim().isEmpty ?? true)) {
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
        if (desc.isNotEmpty && (model.description?.trim().isEmpty ?? true)) {
          model.description = desc;
        }
        model.persistedDrawingImagePath = row['drawing_image_path']?.toString();
        model.persistedDrawingImageBase64 = row['drawing_image_base64']
            ?.toString();
        final detailId = readInt(row['id']);
        if (!mounted) return;
        setState(() {
          if (detailId != null) {
            _persistedDetailIds[model] = detailId;
          }
          addedProducts.add(model);
          _editProductsLoaded = addedProducts.length;
        });
        if (!model.isCustomProduct &&
            !model.isGlassWork &&
            !model.isMoustiquaire &&
            !model.isCaissonTunnel) {
          // Editing an existing order must use its last drawing as the
          // starting defaults when the user adds another drawing.
          _saveLastSettings(model);
        }
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
        SnackBar(content: Text(t('الرجاء إضافة منتجات أولاً لحساب تكلفتها'))),
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
    if (mounted) setState(() => _isSaving = true);

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

    if (!mounted) return;
    if (!await _ensureOrderClient()) {
      if (mounted) setState(() => _isSaving = false);
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
      if (mounted) setState(() => _isSaving = false);
      return;
    }

    final clientId = selectedClient!['id'];

    bool dialogShown = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    dialogShown = true;

    await Future.delayed(const Duration(milliseconds: 100));

    final syncService = CloudSyncService();
    try {
      // Final safety net for users who save/reserve the order without ever
      // opening the quantity-and-cost table.
      await _ensureAutomaticProductPrices(addedProducts, onlyMissing: true);
      await syncService.beginLocalWrite().timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              debugPrint('beginLocalWrite timeout reached; continuing save');
            },
          );
      if (!mounted) return;
      double rawTotal = addedProducts
          .where((p) => !p.isReplaced)
          .fold(
            0.0,
            (sum, p) =>
                sum + ((p.manualPriceOverride ?? p.totalCost) * p.quantity),
          );
      // Each product price is already the final unit selling price produced
      // by the pricing screen (including percentage/linear/square-meter
      // rules). Applying the percentage again at order level doubles it.
      final total = rawTotal;

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

      final imagePaths = <String>[];
      final imageMaxSide = (Platform.isAndroid || Platform.isIOS) ? 420 : 600;
      for (var index = 0; index < addedProducts.length; index++) {
        final p = addedProducts[index];
        final previous = index < existingDetails.length
            ? existingDetails[index]
            : null;
        final selectedGlassImagePath =
            p.glassWorkPayload?['imagePath']?.toString() ?? '';
        final mustKeepSyncedGlassImage =
            p.isGlassWork &&
            selectedGlassImagePath.isNotEmpty &&
            !File(selectedGlassImagePath).existsSync() &&
            (previous?['drawing_image_base64']?.toString().isNotEmpty ?? false);
        if (mustKeepSyncedGlassImage) {
          imagePaths.add('');
          continue;
        }
        try {
          imagePaths.add(
            await saveWindowImageToDisk(
              p,
              maxSide: imageMaxSide,
            ).timeout(const Duration(seconds: 3), onTimeout: () => ''),
          );
        } catch (error) {
          debugPrint('Skipping order preview image: $error');
          imagePaths.add('');
        }
        await Future.delayed(Duration.zero);
      }

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
        final selectedColor = p.selectedDbColor;
        final selectedColorName =
            (selectedColor?['name'] ?? selectedColor?['color_name'])
                ?.toString()
                .trim();
        final persistedModel = p.toMap();
        if (selectedColorName != null && selectedColorName.isNotEmpty) {
          persistedModel['selectedDbColor'] = <String, dynamic>{
            ...Map<String, dynamic>.from(selectedColor ?? const {}),
            'name': selectedColorName,
          };
          persistedModel['selectedColorName'] = selectedColorName;
        }
        preparedDetails.add({
          if (persistedDetailId != null) 'id': persistedDetailId,
          'sort_order': index,
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
          'color': selectedColorName != null && selectedColorName.isNotEmpty
              ? selectedColorName
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
              return jsonEncode(persistedModel);
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
        // Editing an existing order must never move it back to Pending. This
        // preserves the production workflow state on every later save.
        status: widget.editCommandeId == null ? 'Pending' : _editOrderStatus,
        description: controller.text,
        remise: remise,
        tva: tax,
        total: total,
        netPayable: total - remise + ((total * tax) / 100),
        createdAt: _parseQuoteDateForDb(quoteDateController.text),
        projectId: (selectedProject?['id'] as num?)?.toInt(),
        details: preparedDetails,
      );

      if (widget.editCommandeId != null && mounted) {
        final fresh = await widget.db.readCommandeWithClientById(
          widget.editCommandeId!,
        );
        if (fresh != null && mounted) {
          setState(() {
            _editOrderStatus = fresh['status']?.toString() ?? _editOrderStatus;
            _editOrderStatusLoaded = true;
            _editAdvancePayment = _readMoney(fresh['advance_payment']);
          });
        }
      }

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
          content: Text('${t('فشل حفظ الطلبية')}: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      syncService.endLocalWrite();
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _handleSavePressed() {
    if (_isSaving) return;
    if (_isLoadingEditProducts) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _editProductsTotal > 0
                ? 'انتظر اكتمال تحميل عناصر الطلبية: $_editProductsLoaded / $_editProductsTotal'
                : 'انتظر اكتمال تحميل عناصر الطلبية.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    unawaited(_saveCommande());
  }

  List<WindowModel> _bulkEditableProducts() {
    return addedProducts.where(_isBulkEditableProduct).toList();
  }

  Future<List<WindowModel>?> _selectBulkProducts({
    required String title,
  }) async {
    if (widget.editCommandeId != null) {
      final fresh = await widget.db.readCommandeWithClientById(
        widget.editCommandeId!,
      );
      if (fresh != null && mounted) {
        setState(() {
          _editOrderStatus = fresh['status']?.toString() ?? _editOrderStatus;
          _editOrderStatusLoaded = true;
          _editAdvancePayment = _readMoney(fresh['advance_payment']);
        });
      }
    }
    if (!_bulkChangesAllowed) {
      _showBulkChangesBlockedMessage();
      return null;
    }
    final products = _bulkEditableProducts();
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('لا توجد عناصر قابلة لهذا التخصيص.'))),
      );
      return null;
    }
    // Selection is intentionally performed on the cards themselves. The
    // first press on a bulk action only opens selection mode; pressing the
    // same action again applies it to the checked cards.
    if (!_isBulkSelectionMode) {
      _enterBulkSelectionMode();
      return null;
    }

    _bulkSelectedProducts.removeWhere((product) => !products.contains(product));
    if (_bulkSelectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${t('حدد عنصرًا واحدًا على الأقل لتطبيق')} $title.'),
        ),
      );
      return null;
    }
    return _bulkSelectedProducts.toList(growable: false);
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
            content: Text('${t('تعذر تطبيق التخصيص:')} $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _isApplyingBulkChange = false);
    }
  }

  Future<bool?> _askBulkPricePolicy() async {
    var recalculate = true;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(t('سعر العناصر بعد التغيير')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t(
                  'اختر هل تريد الحفاظ على السعر الحالي أم إعادة حسابه حسب التغيير الجديد.',
                ),
              ),
              RadioListTile<bool>(
                value: true,
                groupValue: recalculate,
                onChanged: (value) =>
                    setDialogState(() => recalculate = value ?? true),
                title: Text(t('إعادة حساب السعر')),
                subtitle: Text(t('يأخذ اللون أو السلسلة الجديدة بالحسبان.')),
              ),
              RadioListTile<bool>(
                value: false,
                groupValue: recalculate,
                onChanged: (value) =>
                    setDialogState(() => recalculate = value ?? false),
                title: Text(t('الحفاظ على السعر الحالي')),
                subtitle: Text(t('يبقى السعر كما هو قبل التغيير.')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, recalculate),
              child: Text(t('متابعة')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _prepareBulkCatalog(Iterable<WindowModel> products) async {
    for (final product in products) {
      final savedSlidingSelection =
          product.loadedSlidingSeriesId != null ||
          (product.loadedSlidingSeriesName?.trim().isNotEmpty ?? false);
      final slidingRuntimeMissing =
          (product.systemMode == 'mixed' || product.systemMode == 'sliding') &&
          product.activeSlidingSeries == null &&
          (savedSlidingSelection || product.systemMode == 'sliding');
      final needsCatalog =
          product.availableSystems.isEmpty ||
          product.allGlassCache.isEmpty ||
          product.availableColors.isEmpty ||
          slidingRuntimeMissing ||
          (product.isShutterOnly && product.availableAccessoryColors.isEmpty);
      if (!needsCatalog) continue;
      try {
        await product.loadCatalogData(product.systemMode ?? 'mixed');
      } catch (error, stackTrace) {
        // One incomplete legacy row must not prevent the colour dialog from
        // opening for the remaining selected products.
        debugPrint('Bulk colour catalog load failed: $error\n$stackTrace');
      }
    }
  }

  int? _bulkColorId(Map<String, dynamic> color) {
    final rawId = color['id'];
    return rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '');
  }

  List<Map<String, dynamic>> _bulkColorPalette(WindowModel product) {
    final source = product.isShutterOnly
        ? (product.availableAccessoryColors.isNotEmpty
              ? product.availableAccessoryColors
              : product.availableColors)
        : product.availableColors;
    final result = <Map<String, dynamic>>[];
    final seen = <int>{};
    for (final color in source) {
      final id = _bulkColorId(color);
      if (id != null && seen.add(id)) {
        result.add(Map<String, dynamic>.from(color));
      }
    }
    return result;
  }

  double _readMapPrice(Map<String, dynamic>? value) {
    if (value == null) return 0.0;
    final raw =
        value['calculated_price'] ??
        value['price_dzd'] ??
        value['price_per_meter'] ??
        value['price_per_sqm'] ??
        value['price'];
    return raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }

  Future<double> _readSeriesLinearMeterPrice(WindowModel product) async {
    final database = await widget.db.db;
    if (database == null) return 0.0;
    final series =
        product.activeFrameSeries ??
        (product.usesSlidingPrimaryProfiles
            ? product.activeSlidingSeries
            : product.activeSeries);
    if (series == null) return 0.0;
    final rawColorId = product.selectedDbColor?['id'];
    final colorId = rawColorId is num
        ? rawColorId.toInt()
        : int.tryParse(rawColorId?.toString() ?? '');
    var price = colorId == null
        ? 0.0
        : await widget.db.getSeriesColorPrice(series.id, colorId);
    if (price <= 0) {
      final rows = await database.query(
        'Series',
        columns: const ['price_per_meter'],
        where: 'id = ?',
        whereArgs: [series.id],
        limit: 1,
      );
      if (rows.isNotEmpty) price = _readMapPrice(rows.first);
    }
    if (price <= 0) {
      final rows = await database.query(
        'SeriesColorPrices',
        columns: const ['price'],
        where: 'series_id = ? AND price > 0',
        whereArgs: [series.id],
        limit: 1,
      );
      if (rows.isNotEmpty) price = _readMapPrice(rows.first);
    }
    return price;
  }

  Future<double> _readShutterSquareMeterPrice(WindowModel product) async {
    final database = await widget.db.db;
    if (database == null) return 0.0;
    final override = product.componentOverrides['الشرائح (Lames)'];
    final bladeName = override?['name']?.toString() ?? product.shutterLame;
    final subtype = override?['shutter_subtype']?.toString() ?? 'normal';
    final rawColorId = product.selectedDbColor?['id'];
    final colorId = rawColorId is num
        ? rawColorId.toInt()
        : int.tryParse(rawColorId?.toString() ?? '');
    final prices = await database.query('ShutterSqmPrices');
    var price = WindowModel.resolveShutterSqmPrice(
      bladeName: bladeName,
      bladeSubtype: subtype,
      colorId: colorId,
      prices: prices,
    );
    if (price <= 0 && bladeName.trim().isNotEmpty) {
      final rows = await database.query(
        'ShutterSqmPrices',
        columns: const ['price_per_sqm'],
        where: 'LOWER(TRIM(blade_type)) = ? AND price_per_sqm > 0',
        whereArgs: [bladeName.trim().toLowerCase()],
        limit: 1,
      );
      if (rows.isNotEmpty) price = _readMapPrice(rows.first);
    }
    return price;
  }

  Map<String, bool> _bulkPricingVariants(WindowModel product) {
    final isMotor = product.shutterMechanism == 'محرك';
    final isCrank =
        product.shutterMechanism.contains('مان') ||
        product.shutterMechanism.contains('منا');
    return {
      'Verrou Central': product.useVerrouCentral,
      'System OB': product.useSystemOB,
      'Demi System OB': product.effectiveUseDemiOB,
      'كيت فولي موتور (Kit Volet Moteur)': isMotor,
      'كيت فولي مانيفر (Kit Volet Manivelle)': isCrank,
      'كيت مانيفر (Kit Manivelle)': isCrank,
      'كيت فولي (Kit Volet)': !isMotor && !isCrank,
      'طانديم (Tandem)': product.isCaissonTunnel,
      'أغطية الشفرات (Bouchons Lames)': product.componentOverrides.containsKey(
        'أغطية الشفرات (Bouchons Lames)',
      ),
    };
  }

  /// Rebuilds the complete selling price after a bulk change. A price delta
  /// is unsafe here because changing series can also change mullions, kits,
  /// parcloses, glass and the selected pricing basis at the same time.
  Future<void> _recalculateProductSellingPrice(WindowModel product) async {
    final pricingRules = await SqlDatabase().getProfileCalculationRules();
    final excludedProfiles = pricingRules
        .where(
          (rule) =>
              rule['exclude_from_pricing'] == 1 ||
              rule['exclude_from_pricing'] == true,
        )
        .map((rule) => rule['section_id'])
        .toSet();
    final engine = BomEngineV2(database: widget.db);
    var bom = ComponentCalculator.generateBom(
      product,
      _bulkPricingVariants(product),
    );
    // Resolve the same catalogue selections and prices used by the material
    // table. Pricing an un-stabilized raw BOM is what previously left newly
    // drawn products at zero until that table was opened.
    await engine.stabilizeSelections(window: product, items: bom);
    bom = ComponentCalculator.generateBom(
      product,
      _bulkPricingVariants(product),
    );
    await engine.stabilizeSelections(window: product, items: bom);
    bom = await engine.filterItemsByAvailableCandidates(
      window: product,
      items: bom,
    );
    bom = bom
        .where(
          (item) =>
              item.isActive &&
              item.requiredQuantity > 0 &&
              !(item.category == 'profile' &&
                  excludedProfiles.contains(item.catalogItemId)),
        )
        .toList();
    if (bom.isEmpty) {
      product.manualPriceOverride = null;
      product.totalCost = 0;
      return;
    }

    var profileCost = 0.0;
    var glassCost = 0.0;
    var shutterCost = 0.0;
    var jointCost = 0.0;
    var otherProfileCost = 0.0;
    var mainProfileMeters = 0.0;
    var accessorySellingCost = 0.0;

    for (final item in bom) {
      final itemTotal = item.total;
      if (item.category == 'profile') {
        profileCost += itemTotal;
        final name = item.originalName.toLowerCase();
        final isMain =
            name.contains('إطار') ||
            name.contains('frame') ||
            name.contains('cadre') ||
            name.contains('ظلفة') ||
            name.contains('sash') ||
            name.contains('ouvrant') ||
            name.contains('تقسيم') ||
            name.contains('mullion') ||
            name.contains('باتمو') ||
            name.contains('batmo');
        final isRenfort = name.contains('حديد') || name.contains('renfort');
        if (isMain && !isRenfort) {
          if (item.pieces != null && item.pieces!.isNotEmpty) {
            mainProfileMeters += item.pieces!.fold(0.0, (sum, p) => sum + p);
          } else if (item.length != null) {
            mainProfileMeters += item.length! / 1000 * item.quantity;
          }
        } else {
          otherProfileCost += itemTotal;
        }
      } else if (item.category == 'glass' || item.category == 'panneau') {
        glassCost += itemTotal;
      } else if (item.category == 'shutter') {
        shutterCost += itemTotal;
      } else if (item.category == 'joint') {
        jointCost += itemTotal;
      } else if (item.category == 'accessory' || item.category == 'other') {
        final override = product.componentOverrides[item.originalName];
        if (override is Map &&
            (override['is_selling_calculated'] == 1 ||
                override['is_selling_calculated'] == true)) {
          accessorySellingCost += itemTotal;
        }
      }
    }

    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();
    final pricePerSqm = prefs.getDouble('app_price_per_sqm') ?? 0.0;
    final marginFactor = 1 + settings.profitMargin / 100;
    final areaSqm = product.width / 1000 * product.height / 1000;
    final quantity = product.quantity <= 0 ? 1 : product.quantity;
    final linearMeterPrice = await _readSeriesLinearMeterPrice(product);
    final shutterSqmPrice = await _readShutterSquareMeterPrice(product);
    var shutterSelling = shutterSqmPrice > 0
        ? shutterSqmPrice * areaSqm * quantity
        : shutterCost;

    double profileSelling;
    double glassSelling = glassCost;
    double accessorySelling = accessorySellingCost;
    double jointSelling = jointCost;
    switch (settings.costMethod) {
      case CostMethod.percentage:
        profileSelling = profileCost * marginFactor;
        shutterSelling = shutterCost * marginFactor;
        accessorySelling *= marginFactor;
        jointSelling *= marginFactor;
        break;
      case CostMethod.squareMeter:
        final windowPrice = pricePerSqm * areaSqm * quantity;
        profileSelling = (windowPrice - glassCost).clamp(0.0, double.infinity);
        break;
      case CostMethod.linearMeter:
        profileSelling =
            mainProfileMeters * linearMeterPrice + otherProfileCost;
        break;
    }

    final totalSelling =
        profileSelling +
        glassSelling +
        shutterSelling +
        accessorySelling +
        jointSelling;
    final rawTotal = bom.fold<double>(0.0, (sum, item) => sum + item.total);
    final unitPrice = (totalSelling > 0 ? totalSelling : rawTotal) / quantity;
    if (unitPrice.isFinite && unitPrice >= 0) {
      // Bulk changes intentionally replace the old calculated/manual price:
      // keeping the old override would make the invoice display stale data.
      product.manualPriceOverride = null;
      product.totalCost = unitPrice;
    }
  }

  Future<void> _ensureAutomaticProductPrices(
    Iterable<WindowModel> products, {
    bool onlyMissing = false,
  }) async {
    final automaticProducts = products.where(
      (product) =>
          !product.isCustomProduct &&
          !product.isGlassWork &&
          !product.isMoustiquaire &&
          product.manualPriceOverride == null &&
          (!onlyMissing || product.totalCost <= 0),
    );
    final pending = automaticProducts.toList(growable: false);
    if (pending.isEmpty) return;
    await _prepareBulkCatalog(pending);
    for (final product in pending) {
      await _recalculateProductSellingPrice(product);
    }
  }

  // 🟢 تغيير لون العناصر المحددة من الطلبية
  Future<void> _showApplyBulkColorDialog() async {
    final selected = await _selectBulkProducts(
      title: t('تغيير لون عناصر الطلبية'),
    );
    if (selected == null || selected.isEmpty) return;

    final recalculatePrices = await _askBulkPricePolicy();
    if (recalculatePrices == null || !mounted) return;

    final prepared = await _runBulkOperation<bool>(() async {
      await _prepareBulkCatalog(selected);
      return true;
    });
    if (prepared != true || !mounted) return;

    List<Map<String, dynamic>> allColors = const [];
    try {
      allColors = await widget.db.readColors();
    } catch (error, stackTrace) {
      // The palettes loaded with the selected products are still enough to
      // render the picker if the global colour query is temporarily delayed.
      debugPrint('Bulk colour list load failed: $error\n$stackTrace');
    }
    // A bulk colour change may contain products from different series.  The
    // picker must show every colour supported by at least one selected series
    // (union), rather than only colours shared by all selected series
    // (intersection).  Each product is still checked before applying the
    // choice below, so an incompatible colour is never assigned to it.
    final allowedColorIds = <int>{};
    for (final product in selected) {
      final ids = _bulkColorPalette(
        product,
      ).map(_bulkColorId).whereType<int>().toSet();
      allowedColorIds.addAll(ids);
    }
    final colorsById = <int, Map<String, dynamic>>{};
    for (final color in allColors) {
      final id = _bulkColorId(color);
      if (id != null && allowedColorIds.contains(id)) {
        colorsById[id] = Map<String, dynamic>.from(color);
      }
    }
    // Keep the loaded series/accessory palette as a fallback and as the
    // source of truth for colours that are present locally but not yet in a
    // freshly-read global list.
    for (final product in selected) {
      for (final color in _bulkColorPalette(product)) {
        final id = _bulkColorId(color);
        if (id != null && allowedColorIds.contains(id)) {
          colorsById.putIfAbsent(id, () => Map<String, dynamic>.from(color));
        }
      }
    }
    final colors = colorsById.values.toList();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('اختيار لون العناصر المحددة')),
        content: SizedBox(
          width: double.maxFinite,
          child: colors.isEmpty
              ? Text(t('لا توجد ألوان متاحة للسلاسل المختارة.'))
              : ListView(
                  shrinkWrap: true,
                  children: colors.map((dbColor) {
                    final name = dbColor['name']?.toString() ?? '';
                    return ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: realGradientColors(dbColor),
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          image: realColorTextureImage(dbColor),
                          border: Border.all(color: Colors.black26),
                        ),
                      ),
                      title: Text(name),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final changed = await _runBulkOperation<int>(() async {
                          var count = 0;
                          for (final product in selected) {
                            final allowed = _bulkColorPalette(product).any(
                              (color) =>
                                  _bulkColorId(color) == _bulkColorId(dbColor),
                            );
                            if (!allowed) continue;
                            final previousTotalCost = product.totalCost;
                            final previousManualPrice =
                                product.manualPriceOverride;
                            if (product.isShutterOnly) {
                              product.selectedShutterColor = Map<String, dynamic>.from(dbColor);
                              await product.updateShutterDefaultsIfNeeded();
                            } else {
                              final previousShutterColor = product.effectiveShutterColor;
                              if (product.hasShutter && previousShutterColor != null) {
                                product.selectedShutterColor = Map<String, dynamic>.from(previousShutterColor);
                              }
                              product.selectedDbColor = dbColor;
                              await product
                                  .refreshSectionPricesForSelectedColor(
                                    notify: false,
                                  );
                            }
                            if (recalculatePrices) {
                              await _recalculateProductSellingPrice(product);
                            } else {
                              product.totalCost = previousTotalCost;
                              product.manualPriceOverride = previousManualPrice;
                            }
                            count++;
                          }
                          if (mounted) setState(() {});
                          return count;
                        });
                        if (mounted && changed != null) {
                          _exitBulkSelectionMode();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.green.shade700,
                              content: Text(
                                '${t('تم تغيير اللون لـ')} $changed ${t('عنصر')} ${t('بنجاح')}.',
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
            child: Text(t('إلغاء')),
          ),
        ],
      ),
    );
  }

  Future<void> _showBulkSeriesDialog() async {
    final selected = await _selectBulkProducts(title: t('تغيير سلسلة العناصر'));
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
        SnackBar(content: Text(t('لا توجد سلاسل متاحة لهذه العناصر.'))),
      );
      return;
    }
    final chosen = await showDialog<AluminumSeries>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('اختر السلسلة الجديدة')),
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
            child: Text(t('إلغاء')),
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;

    final recalculatePrices = await _askBulkPricePolicy();
    if (recalculatePrices == null || !mounted) return;

    final changed = await _runBulkOperation<int>(() async {
      var count = 0;
      for (final product in selected) {
        final localSeries = product.availableSystems
            .expand((system) => system.series)
            .where((series) => series.id == chosen.id)
            .cast<AluminumSeries?>()
            .firstWhere((series) => series != null, orElse: () => null);
        if (localSeries == null) continue;
        final previousTotalCost = product.totalCost;
        final previousManualPrice = product.manualPriceOverride;
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
        if (recalculatePrices) {
          await _recalculateProductSellingPrice(product);
        } else {
          product.totalCost = previousTotalCost;
          product.manualPriceOverride = previousManualPrice;
        }
        count++;
      }
      if (mounted) setState(() {});
      return count;
    });
    if (mounted && changed != null) {
      _exitBulkSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text(
            '${t('تم تغيير السلسلة لـ')} $changed ${t('عنصر')} ${t('بنجاح')}.',
          ),
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
              title: Text(t('تغيير زجاج العناصر المحددة')),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      enumDropdown(
                        label: t('نوع الزجاج'),
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
                        decoration: InputDecoration(
                          labelText: t('سمك الزجاج الخارجي (مم)'),
                        ),
                      ),
                      if (structure == GlassStructure.double) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: innerThickness,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: t('سمك الزجاج الداخلي (مم)'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: intercall,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: t('سمك الأنتركال (مم)'),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t('مع غاز')),
                          value: hasGas,
                          onChanged: (value) =>
                              setDialogState(() => hasGas = value),
                        ),
                      ],
                      enumDropdown(
                        label: t('معالجة الوجه الخارجي'),
                        value: processingOuter,
                        values: GlassProcessing.values,
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => processingOuter = value);
                          }
                        },
                      ),
                      enumDropdown(
                        label: t('نوع الوجه الخارجي'),
                        value: finishOuter,
                        values: GlassFinish.values,
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => finishOuter = value);
                          }
                        },
                      ),
                      enumDropdown(
                        label: t('لون الوجه الخارجي'),
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
                          label: t('معالجة الوجه الداخلي'),
                          value: processingInner,
                          values: GlassProcessing.values,
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => processingInner = value);
                            }
                          },
                        ),
                        enumDropdown(
                          label: t('نوع الوجه الداخلي'),
                          value: finishInner,
                          values: GlassFinish.values,
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => finishInner = value);
                            }
                          },
                        ),
                        enumDropdown(
                          label: t('لون الوجه الداخلي'),
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
                  child: Text(t('إلغاء')),
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
                  child: Text(t('تطبيق')),
                ),
              ],
            );
          },
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Bulk glass dialog failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${t('تعذر فتح إعدادات الزجاج')}: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    } finally {
      outerThickness.dispose();
      innerThickness.dispose();
      intercall.dispose();
    }
  }

  Future<void> _showBulkGlassDialog() async {
    try {
      final selected = await _selectBulkProducts(
        title: t('تغيير زجاج العناصر'),
      );
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
      if (source.zones.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('لا توجد مناطق زجاجية في العناصر المحددة.')),
          ),
        );
        return;
      }
      final base =
          source.getUniformGlassSpecification() ?? source.zones.first.glass;
      final spec = await _showBulkGlassSpecDialog(base);
      if (spec == null || !mounted) return;

      final changed = await _runBulkOperation<int>(() async {
        var count = 0;
        for (final product in selected) {
          if (product.zones.isEmpty) continue;
          await product.applyGlassSpecificationToAllZones(spec);
          await _recalculateProductSellingPrice(product);
          count++;
        }
        if (mounted) setState(() {});
        return count;
      });
      if (mounted && changed != null) {
        _exitBulkSelectionMode();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(
              '${t('تم تغيير الزجاج لـ')} $changed ${t('عنصر')} ${t('بنجاح')}.',
            ),
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Bulk glass change failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${t('تعذر تغيير الزجاج')}: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

  Widget _buildPaymentSummaryRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // ==============================================================================

  Widget _buildBulkActionsPanel({required bool isDark}) {
    final products = _bulkEditableProducts();
    if (products.isEmpty) return const SizedBox.shrink();
    final allSelected =
        products.isNotEmpty && products.every(_bulkSelectedProducts.contains);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElegantAnimatedButton(
          gradientColors: const [Colors.deepPurple, Colors.purpleAccent],
          onPressed: _isApplyingBulkChange ? null : _showApplyBulkColorDialog,
          icon: const Icon(Icons.palette_outlined, color: Colors.white),
          label: const Text(
            'تغيير لون العناصر',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          height: 50,
        ),
        const SizedBox(height: 8),
        ElegantAnimatedButton(
          gradientColors: const [Colors.indigo, Colors.blueAccent],
          onPressed: _isApplyingBulkChange ? null : _showBulkSeriesDialog,
          icon: const Icon(Icons.layers_outlined, color: Colors.white),
          label: const Text(
            'تغيير السلسلة',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          height: 50,
        ),
        const SizedBox(height: 8),
        ElegantAnimatedButton(
          gradientColors: const [Colors.teal, Colors.green],
          onPressed: _isApplyingBulkChange ? null : _showBulkGlassDialog,
          icon: const Icon(Icons.window_outlined, color: Colors.white),
          label: const Text(
            'تغيير الزجاج',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          height: 50,
        ),
        if (_isBulkSelectionMode) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? Colors.blueGrey : Colors.blue.shade200,
              ),
            ),
            child: Column(
              children: [
                CheckboxListTile(
                  value: allSelected,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    '${t('تحديد الكل')} (${products.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${t('تم تحديد')} ${_bulkSelectedProducts.length}',
                  ),
                  onChanged: (_) => _toggleAllBulkProducts(),
                ),
                TextButton.icon(
                  onPressed: _exitBulkSelectionMode,
                  icon: const Icon(Icons.close),
                  label: Text(t('إلغاء التحديد')),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final double rawTotal = addedProducts
        .where((p) => !p.isReplaced)
        .fold(
          0.0,
          (sum, p) =>
              sum + ((p.manualPriceOverride ?? p.totalCost) * p.quantity),
        );
    final finalTotal = rawTotal;
    final double remise = double.tryParse(remiseController.text) ?? 0.0;
    final double taxVal = double.tryParse(taxController.text) ?? 0.0;
    final double calculatedTax = (finalTotal * taxVal) / 100;
    final double totalWithRemiseTax = finalTotal - remise + calculatedTax;
    final bool showPaymentSummary = _showEditPaymentSummary;
    final double remainingPayment = showPaymentSummary
        ? (totalWithRemiseTax - _editAdvancePayment)
              .clamp(0.0, double.infinity)
              .toDouble()
        : 0.0;
    final int totalQuantity = addedProducts
        .where((p) => !p.isReplaced)
        .fold(0, (sum, p) => sum + p.quantity);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canChangeOrderDates = Provider.of<AppSettingsProvider>(
      context,
    ).canChangeOrderDates();

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
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 22,
            icon: const Icon(Icons.add_box_outlined, color: Colors.indigo),
            onPressed: _isLoadingEditProducts ? null : _showAddNormalProduct,
            tooltip: Localization.translate(
              'Add Product',
              Provider.of<AppSettingsProvider>(context).language,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 22,
            icon: const Icon(Icons.playlist_add, color: Colors.deepOrange),
            onPressed: _isLoadingEditProducts
                ? null
                : () => _showAddSpecialProductDialog(),
            tooltip: Localization.translate(
              'Add Product Special',
              Provider.of<AppSettingsProvider>(context).language,
            ),
          ),
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
            onPressed: _handleSavePressed,
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
              suffix: canChangeOrderDates ? null : Icons.lock_outline,
              onTap: canChangeOrderDates
                  ? () => pickDate(quoteDateController)
                  : null,
            ),

            const SizedBox(height: 15),

            _buildField(
              label: "Valid till Date *",
              controller: validDateController,
              icon: Icons.calendar_today,
              suffix: canChangeOrderDates ? null : Icons.lock_outline,
              onTap: canChangeOrderDates
                  ? () => pickDate(validDateController)
                  : null,
            ),
            const SizedBox(height: 15),

            if (_isLoadingEditProducts) ...[
              _buildEditItemsLoadingCard(),
              const SizedBox(height: 15),
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
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerMove: _handleReorderPointerMove,
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: addedProducts.length,
                  onReorder: _moveProductToPosition,
                  onReorderStart: _startReorderDrag,
                  onReorderEnd: _finishReorderDrag,
                  proxyDecorator: (child, index, animation) {
                    return AnimatedBuilder(
                      animation: animation,
                      builder: (context, child) {
                        final elevation = Tween<double>(
                          begin: 4,
                          end: 14,
                        ).evaluate(animation);
                        return Material(
                          color: Colors.transparent,
                          elevation: elevation,
                          borderRadius: BorderRadius.circular(15),
                          child: child,
                        );
                      },
                      child: child,
                    );
                  },
                  itemBuilder: (context, index) {
                    final product = addedProducts[index];
                    return KeyedSubtree(
                      key: ObjectKey(product),
                      child: ReorderableDelayedDragStartListener(
                        index: index,
                        child: Stack(
                          children: [
                            _buildProductCard(product),
                            PositionedDirectional(
                              top: 10,
                              end: 10,
                              child: IgnorePointer(
                                child: Icon(
                                  Icons.drag_indicator_rounded,
                                  color: Colors.blue.shade600,
                                  size: 24,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
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
                          await _prepareBulkCatalog(addedProducts);
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
              if (addedProducts.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildBulkActionsPanel(isDark: isDark),
              ],
              const SizedBox(height: 15),
              ...addedProducts.map((p) => _buildProductCard(p)),
              if (addedProducts.isNotEmpty) const SizedBox(height: 15),
            ],

            LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 600;
                final normalButton = ElegantAnimatedButton(
                  gradientColors: const [
                    Colors.indigoAccent,
                    Colors.blueAccent,
                  ],
                  onPressed: _showAddNormalProduct,
                  icon: isMobile
                      ? null
                      : const Icon(Icons.add, color: Colors.white, size: 20),
                  label: Text(
                    Localization.translate(
                      'Add Product',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  height: 46,
                );
                final specialButton = ElegantAnimatedButton(
                  gradientColors: const [
                    Colors.orangeAccent,
                    Colors.deepOrangeAccent,
                  ],
                  onPressed: () => _showAddSpecialProductDialog(),
                  icon: isMobile
                      ? null
                      : const Icon(Icons.add, color: Colors.white, size: 20),
                  label: Text(
                    Localization.translate(
                      'Add Product Special',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  height: 46,
                );

                if (isMobile) {
                  return Column(
                    children: [
                      normalButton,
                      const SizedBox(height: 8),
                      specialButton,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: normalButton),
                    const SizedBox(width: 8),
                    Expanded(child: specialButton),
                  ],
                );
              },
            ),
            const SizedBox(height: 15),

            TextField(
              controller: controller, // متحكم الملاحظات
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
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
              // Let the field grow with the note instead of cutting it after
              // four lines. The surrounding page is already scrollable, so a
              // long note remains reachable without an inner fixed-height box.
              minLines: 4,
              maxLines: null,
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
                  if (showPaymentSummary) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.teal.shade900.withValues(alpha: 0.18)
                            : Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? Colors.teal.shade700
                              : Colors.teal.shade100,
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildPaymentSummaryRow(
                            icon: Icons.payments_outlined,
                            label: Localization.translate(
                              'Amount paid',
                              Provider.of<AppSettingsProvider>(
                                context,
                              ).language,
                            ),
                            value:
                                '${_editAdvancePayment.toStringAsFixed(2)} DZD',
                            color: Colors.green,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 10),
                          _buildPaymentSummaryRow(
                            icon: Icons.account_balance_wallet_outlined,
                            label: Localization.translate(
                              'Remaining:',
                              Provider.of<AppSettingsProvider>(
                                context,
                              ).language,
                            ),
                            value: '${remainingPayment.toStringAsFixed(2)} DZD',
                            color: Colors.red,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 30),
            ElegantAnimatedButton(
              gradientColors: const [Colors.green, Colors.teal],
              onPressed: _handleSavePressed,
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

  bool _clientDialogOpen = false;

  Future<bool> _ensureOrderClient() async {
    if (selectedClient?['id'] != null) return true;
    if (!mounted || _clientDialogOpen) return false;
    _clientDialogOpen = true;
    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => ClientDropdownDialog(db: widget.db),
      );
      if (!mounted || result?['id'] == null) return false;
      setState(() {
        selectedClient = result;
        clientController.text =
            "${result!['firstname'] ?? ''} ${result['lastname'] ?? ''}".trim();
        selectedProject = null;
        projectController.clear();
      });
      return true;
    } finally {
      _clientDialogOpen = false;
    }
  }

  Future<void> _showAddNormalProduct() async {
    if (!await _ensureOrderClient() || !mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChooseSysteme(initialSettings: _lastUsedSettings),
      ),
    );
    if (!mounted) return;

    if (result is WindowModel) {
      // Calculate the selling price before publishing the card. Previously
      // this happened only after opening the quantity/cost table, so saving
      // the order directly could persist a zero-priced item.
      await _ensureAutomaticProductPrices([result]);
      if (!mounted) return;
      _saveLastSettings(result);
      setState(() {
        addedProducts.add(result);
        _highlightedProduct = result;
      });
      _scrollToHighlightedProduct();
    } else if (result is List<WindowModel> && result.isNotEmpty) {
      await _ensureAutomaticProductPrices(result);
      if (!mounted) return;
      _saveLastSettings(result.last);
      setState(() {
        addedProducts.addAll(result);
        _highlightedProduct = result.last;
      });
      _scrollToHighlightedProduct();
    }
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
    final isBulkSelectable = _isBulkEditableProduct(p);
    final isBulkSelected = _bulkSelectedProducts.contains(p);

    final bool isCaisson =
        p.isCaissonTunnel ||
        (p.manualNameOverride?.contains('Caisson Tunnel') == true) ||
        (p.manualNameOverride?.contains('Caisson Tunnel') == true);

    // A tunnel box can be either a standalone calculated item or part of a
    // complete window designed in WindowView. Only the standalone item should
    // open the dedicated Caisson Tunnel calculator when edited. The fallback
    // checks keep older saved drawings working before isDesignDrawing existed.
    final bool isDesignedWindow =
        p.isDesignDrawing ||
        p.zones.isNotEmpty ||
        p.showWall ||
        p.componentOverrides['الصندوق (Caisson)']?['measurement']
                ?.toString()
                .toLowerCase() ==
            'tunnel';
    final bool isStandaloneCaisson =
        !isDesignedWindow &&
        (p.isCaissonTunnel ||
            p.manualNameOverride?.contains('Caisson Tunnel') == true);

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
          color: isBulkSelected
              ? Colors.deepPurple
              : (isHighlighted ? Colors.blue.shade400 : Colors.transparent),
          width: isBulkSelected ? 3 : (isHighlighted ? 2.5 : 0),
        ),
      ),
      color: isDark
          ? ((p.isReplaced && !isCaisson)
                ? Colors.grey.shade900
                : const Color(0xFF1E1E1E))
          : ((p.isReplaced && !isCaisson)
                ? const Color(0xFFF5F5F5)
                : Colors.white),
      child: InkWell(
        onTap: _isBulkSelectionMode && isBulkSelectable
            ? () => _toggleBulkProduct(p)
            : null,
        borderRadius: BorderRadius.circular(15),
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
                        if (_isBulkSelectionMode && isBulkSelectable)
                          Checkbox(
                            value: isBulkSelected,
                            onChanged: (_) => _toggleBulkProduct(p),
                          ),
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
                                            (firstMap['lengthMm'] as num? ??
                                                    0.0)
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
                                tooltip: t(
                                  'جدول المقاسات (Edit Table Details)',
                                ),
                                onPressed: () async {
                                  await _prepareBulkCatalog([p]);
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
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                onPressed: () async {
                                  if (isStandaloneCaisson) {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            CaissonTunnelScreen(
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
                                          p.manualNameOverride =
                                              'Caisson Tunnel';
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
                                              initialPayload:
                                                  p.glassWorkPayload,
                                            ),
                                      ),
                                    );
                                    if (result is Map<String, dynamic> &&
                                        mounted) {
                                      final models =
                                          _modelsFromGlassWorkPayload(result);
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
                                        builder: (context) =>
                                            MoustiquaireScreen(
                                              initialPayload:
                                                  p.moustiquairePayload,
                                            ),
                                      ),
                                    );
                                    if (result is Map<String, dynamic> &&
                                        mounted) {
                                      final models =
                                          _modelsFromMoustiquairePayload(
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

                                  // Every drawing, including a shutter, is
                                  // edited in the design page. The shutter
                                  // options remain available in its bottom
                                  // panel; the old standalone shutter page is
                                  // no longer part of the edit flow.
                                  await _prepareBulkCatalog([p]);
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => WindowView(
                                        model: p,
                                        systemMode: 'mixed',
                                      ),
                                    ),
                                  );
                                  await _ensureAutomaticProductPrices([p]);
                                  if (!mounted) return;
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
                                icon: const Icon(
                                  Icons.copy,
                                  color: Colors.green,
                                ),
                                tooltip: t('تكرار (Duplicate)'),
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
                              child: isMoustiquaire
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

                // 4. Open the design page for both windows and shutters.
                // The shutter controls are provided by its bottom panel.
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => WindowView(
                      model: cloned,
                      // Editing an existing drawing must expose the full
                      // design tools, whatever its original mode.
                      systemMode: 'mixed',
                    ),
                  ),
                );
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
            child: Text(t('حفظ')),
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
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  // 🟢 التخلص من متحكم البحث لتفريغ الذاكرة
  @override
  void dispose() {
    search.dispose();
    _searchFocusNode.dispose();
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
                    focusNode: _searchFocusNode,
                    autofocus: true,
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
