import 'dart:io';
import 'order_measurements_details_screen.dart';
import 'order_status_order.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:database_data/sql_database.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/widgets/app_material.dart';
import 'package:database_data/Commande/order_workspace_screen.dart';
import 'package:database_data/Screen/trash_screen.dart';
import 'package:database_data/Screen/app_workspace_shell.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import '../settings/shortcut_bindings.dart';
import 'package:flutter/services.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/document_status_localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:database_data/Commande/pdf_fiche_coupe_api.dart';
import 'package:database_data/Commande/order_date_utils.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/Commande/devis_preview_screen.dart';
import 'package:database_data/Commande/capture_image.dart';
import 'package:database_data/Commande/order_picture_pdf_service.dart';
import 'package:database_data/services/glass_fabrication_pdf_service.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/order_required_goods_screen.dart';
import 'package:database_data/Commande/order_measurements_confirm_screen.dart';
import 'package:database_data/Commande/partial_proforma_screen.dart';
import 'package:database_data/Screen/order_allocation_screen.dart';
import '../Screen/cutting_optimization_screen.dart';
import '../Screen/sheet_optimization_screen.dart';
import '../Screen/map_picker_screen.dart';
import 'package:latlong2/latlong.dart';
import 'package:database_data/widgets/resizable_columns_table.dart';
import 'package:database_data/widgets/desktop_context_menu.dart';
import 'package:database_data/widgets/numeric_filter_search_field.dart';
import 'package:database_data/widgets/table_date_range_filter.dart';
import 'package:database_data/widgets/desktop_scroll_behavior.dart';
import 'package:printing/printing.dart';
import '../services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'order_export_service.dart';
import 'order_import_dialog.dart';
import 'order_pinning.dart';

class Commande extends StatefulWidget {
  /// Opens the normal new-order form after the orders page has appeared.
  /// The dashboard uses this so its add action behaves like the page action.
  final bool openAddOrderOnStart;
  final int? initialOrderId;
  final bool openOrdersOnly;

  const Commande({
    super.key,
    this.openAddOrderOnStart = false,
    this.initialOrderId,
    this.openOrdersOnly = false,
  });

  @override
  State<Commande> createState() => _CommandeState();
}

class _CommandeState extends State<Commande> {
  bool _initialOrderOpened = false;
  int? _notificationHighlightedOrderId;
  static const String _orderSortColumnPreferenceKey =
      'orders_sort_column_device';
  static const String _orderSortAscendingPreferenceKey =
      'orders_sort_ascending_device';
  static const Set<String> _persistableOrderSortColumns = {
    'id',
    'client_project',
    'date',
    'updated_at',
    'updated_by',
    'total',
    'advance',
    'remaining',
    'status',
    'stock_reserved',
    'creator',
  };
  final SqlDatabase db = SqlDatabase();
  final ScrollController _mobileOrdersScrollController = ScrollController();
  final ScrollController _desktopOrdersScrollController = ScrollController();
  late Future<List<Map<String, dynamic>>> _data;
  List<Map<String, dynamic>>? _cachedCommandes;
  String _searchQuery = '';
  bool _showMobileSearch = false;
  final TextEditingController _mobileSearchController = TextEditingController();
  final FocusNode _mobileSearchFocusNode = FocusNode();
  BuildContext? _loadingDialogContext;
  StreamSubscription? _dbUpdateSubscription;
  Timer? _syncRefreshDebounce;
  bool _permissionRedirectScheduled = false;
  String _workshopNameForIdentity = '';
  bool _isImportPicking = false;
  static const String _legacySeenVersion = '__legacy_seen__';
  Map<int, String> _seenOrderVersions = {};

  String get _seenOrdersPreferenceKey {
    String? supabaseUid;
    try {
      supabaseUid = Supabase.instance.client.auth.currentUser?.id.trim();
    } catch (_) {}
    final firebaseUid = AppAuthService().currentUser?.uid.trim();
    final uid = supabaseUid?.isNotEmpty == true ? supabaseUid : firebaseUid;
    return 'seen_order_versions_v1_${uid == null || uid.isEmpty ? 'local' : uid}';
  }

  static const String _localSeenOrdersPreferenceKey =
      'seen_order_versions_v1_local';

  String _orderVersion(Map<String, dynamic> order) {
    final updated = order['updated_at']?.toString().trim() ?? '';
    final raw = updated.isNotEmpty
        ? updated
        : order['created_at']?.toString().trim() ?? '';
    final parsed = DateTime.tryParse(raw);
    return parsed?.toUtc().toIso8601String() ?? raw;
  }

  bool _isOrderUnseen(Map<String, dynamic> order) {
    final orderId = _readId(order['id']) ?? 0;
    if (orderId <= 0) return false;
    // The author of the latest change has already seen it; it is unread
    // only for the other accounts of the workshop.
    if (SqlDatabase.isOwnLatestOrderEdit(order)) return false;
    final seenVersion = _seenOrderVersions[orderId];
    if (seenVersion == null) return true;
    if (seenVersion == _legacySeenVersion) return false;
    return seenVersion != _orderVersion(order);
  }

  Future<void> _loadSeenOrderVersions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = <int, String>{};
      // Read state is per user. Never merge the device-wide fallback into an
      // authenticated account, otherwise one worker can make another
      // worker's orders appear read (or unread) on a shared phone.
      var hasSupabaseUser = false;
      try {
        hasSupabaseUser =
            Supabase.instance.client.auth.currentUser?.id.trim().isNotEmpty ==
            true;
      } catch (_) {}
      final hasAuthenticatedUser =
          hasSupabaseUser ||
          AppAuthService().currentUser?.uid.trim().isNotEmpty == true;
      final keys = <String>{
        hasAuthenticatedUser
            ? _seenOrdersPreferenceKey
            : _localSeenOrdersPreferenceKey,
      };
      for (final key in keys) {
        final stored = prefs.getString(key);
        if (stored != null && stored.isNotEmpty) {
          final decoded = jsonDecode(stored);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              final id = int.tryParse(entry.key.toString());
              if (id != null) seen[id] = entry.value.toString();
            }
          }
        }
      }

      // Preserve read state created by older app versions. Its version is
      // upgraded to the current updated_at as soon as orders are loaded.
      final legacyIds = prefs.getStringList('seen_order_ids') ?? const [];
      for (final value in legacyIds) {
        final id = int.tryParse(value);
        if (id != null) seen.putIfAbsent(id, () => _legacySeenVersion);
      }
      if (mounted) {
        setState(() => _seenOrderVersions = seen);
      }
    } catch (_) {}
  }

  Future<void> _persistSeenOrderVersions() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = _seenOrderVersions.entries.toList();
    final retained = entries.length <= 2000
        ? entries
        : entries.sublist(entries.length - 2000);
    final encoded = jsonEncode({
      for (final entry in retained) '${entry.key}': entry.value,
    });
    var hasSupabaseUser = false;
    try {
      hasSupabaseUser =
          Supabase.instance.client.auth.currentUser?.id.trim().isNotEmpty ==
          true;
    } catch (_) {}
    final hasAuthenticatedUser =
        hasSupabaseUser ||
        AppAuthService().currentUser?.uid.trim().isNotEmpty == true;
    await prefs.setString(
      hasAuthenticatedUser
          ? _seenOrdersPreferenceKey
          : _localSeenOrdersPreferenceKey,
      encoded,
    );
  }

  Future<void> _markOrderSeen(Map<String, dynamic> order) async {
    final orderId = _readId(order['id']) ?? 0;
    if (orderId <= 0) return;
    final version = _orderVersion(order);
    if (_seenOrderVersions[orderId] == version) return;
    try {
      _seenOrderVersions[orderId] = version;
      await _persistSeenOrderVersions();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _upgradeLegacySeenVersions(
    List<Map<String, dynamic>> orders,
  ) async {
    var changed = false;
    for (final order in orders) {
      final id = _readId(order['id']) ?? 0;
      if (_seenOrderVersions[id] == _legacySeenVersion) {
        _seenOrderVersions[id] = _orderVersion(order);
        changed = true;
      }
    }
    if (changed) await _persistSeenOrderVersions();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    if (settings.isManager || settings.canViewOrders()) {
      _permissionRedirectScheduled = false;
      return;
    }

    // didChangeDependencies can run more than once while a route is closing.
    // Capture the navigator while this context is active; do not look it up
    // from the deactivated page context in the post-frame callback.
    if (_permissionRedirectScheduled) return;
    _permissionRedirectScheduled = true;
    final navigator = Navigator.maybeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _permissionRedirectScheduled = false;
      if (!mounted || navigator == null || !navigator.mounted) return;
      if (navigator.canPop()) {
        navigator.pop();
      }
    });
  }

  String formatDate(Map<String, dynamic> order) {
    return formatOrderDate(order['created_at'], fallback: order['updated_at']);
  }

  String _translateStatus(String status, AppLanguage lang) {
    final s = status.trim();
    final sLow = s.toLowerCase();
    if (sLow == 'تصنيع كامل' ||
        sLow == 'تصنيع كلي' ||
        sLow == 'full manufacturing' ||
        sLow == 'fabrication totale' ||
        sLow == 'fabrication complète') {
      return Localization.translate('Full Manufacturing', lang);
    }
    if (sLow == 'تصنيع جزئي' ||
        sLow == 'partial manufacturing' ||
        sLow == 'fabrication partielle') {
      return Localization.translate('Partial Manufacturing', lang);
    }
    if (sLow == 'توزيع كامل' ||
        sLow == 'توزيع كلي' ||
        sLow == 'full distribution' ||
        sLow == 'livraison totale') {
      return Localization.translate('Full Distribution', lang);
    }
    if (sLow == 'توزيع جزئي' ||
        sLow == 'partial distribution' ||
        sLow == 'livraison partielle') {
      return Localization.translate('Partial Distribution', lang);
    }
    if (sLow == 'تحت التحفظ' ||
        sLow == 'reserve' ||
        sLow == 'sous réserve' ||
        sLow == 'réserve') {
      return Localization.translate('تحت التحفظ', lang);
    }
    return localizeDocumentStatus(s, lang);
  }

  String _t(String key) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return Localization.translate(key, lang);
  }

  bool _hasPassedFullManufacturing(String status) {
    final s = status.trim().toLowerCase();
    return s == 'full manufacturing' ||
        s.contains('تصنيع كامل') ||
        s.contains('تصنيع كلي') ||
        s.contains('التصنيع الكلي') ||
        s.contains('التصنيع الكامل') ||
        s.contains('fabrication totale') ||
        s.contains('fabrication complète') ||
        s == 'partial distribution' ||
        s.contains('توزيع جزئي') ||
        s == 'full distribution' ||
        s.contains('توزيع كلي') ||
        s.contains('توزيع كامل') ||
        s.contains('التوزيع الكلي') ||
        s.contains('livraison totale') ||
        s.contains('livré') ||
        s.contains('livre') ||
        s.contains('installation') ||
        s.contains('تركيب') ||
        s.contains('التركيب') ||
        s.contains('completed') ||
        s.contains('done') ||
        s.contains('منتهية') ||
        s.contains('مكتمل') ||
        s.contains('مكتملة') ||
        s.contains('cancelled') ||
        s.contains('ملغاة');
  }

  Color _getStatusColor(String status) {
    final s = status.trim().toLowerCase();
    if (s == 'nouveau' || s == 'new' || s == 'جديدة' || s == 'جديد') {
      return const Color(0xFF546E7A);
    }
    if (s.contains('confirm') || s.contains('مؤكد')) {
      return const Color(0xFF2E7D32);
    }
    if (s.contains('قياسات') || s == 'in progress' || s.contains('cours')) {
      return const Color(0xFF1565C0);
    }
    if (s.contains('attente') || s.contains('انتظار') || s == 'pending') {
      return const Color(0xFFE65100);
    }
    if (s == 'partial manufacturing' ||
        s.contains('تصنيع جزئي') ||
        s.contains('fabrication partielle')) {
      return const Color(0xFF0288D1);
    }
    if (s == 'full manufacturing' ||
        s.contains('تصنيع كامل') ||
        s.contains('تصنيع كلي') ||
        s.contains('fabrication')) {
      return const Color(0xFF00796B);
    }
    if (s == 'partial distribution' ||
        s.contains('توزيع جزئي') ||
        s.contains('livraison partielle')) {
      return const Color(0xFFF57C00);
    }
    if (s == 'full distribution' ||
        s.contains('توزيع كامل') ||
        s.contains('توزيع كلي') ||
        s.contains('livraison totale')) {
      return const Color(0xFF388E3C);
    }
    if (s.contains('تركيب') || s.contains('installation')) {
      return const Color(0xFF6A1B9A);
    }
    if (s.contains('تحفظ') || s.contains('reserve') || s.contains('réserve')) {
      return const Color(0xFFD84315);
    }
    if (s.contains('منتهي') ||
        s.contains('مكتمل') ||
        s.contains('done') ||
        s.contains('livr')) {
      return const Color(0xFF00695C);
    }
    return const Color(0xFF546E7A);
  }

  int _getOrderStatusWeight(String status) {
    return orderStatusWeight(status);
  }

  int _displayOrderNumber(Map<String, dynamic> order) {
    for (final key in const ['display_number', 'order_code']) {
      final value = order[key];
      final number = value is num
          ? value.toInt()
          : int.tryParse(value?.toString().trim() ?? '');
      if (number != null && number > 0) return number;
    }
    final id = order['id'];
    return id is num ? id.toInt() : int.tryParse(id?.toString() ?? '') ?? 0;
  }

  String _displayOrderLabel(Map<String, dynamic> order) =>
      '#${_displayOrderNumber(order)}';

  String _documentTabTitle({
    required String docType,
    required Map<String, dynamic> orderData,
    required AppLanguage lang,
  }) {
    final num = _displayOrderNumber(orderData);
    if (lang == AppLanguage.french) {
      switch (docType) {
        case 'devis':
          return 'Devis pour commande #$num';
        case 'proforma':
          return 'Facture Proforma pour commande #$num';
        case 'facture':
          return 'Facture pour commande #$num';
        case 'bon_route':
          return 'Bon de Route pour commande #$num';
        case 'bon_livraison':
          return 'Bon de livraison pour commande #$num';
        case 'bon_charge':
          return 'Bon de charge pour commande #$num';
        default:
          return 'Document pour commande #$num';
      }
    } else if (lang == AppLanguage.english) {
      switch (docType) {
        case 'devis':
          return 'Quote for order #$num';
        case 'proforma':
          return 'Proforma for order #$num';
        case 'facture':
          return 'Invoice for order #$num';
        case 'bon_route':
          return 'Route Note for order #$num';
        case 'bon_livraison':
          return 'Delivery Note for order #$num';
        case 'bon_charge':
          return 'Discharge Note for order #$num';
        default:
          return 'Document for order #$num';
      }
    } else {
      switch (docType) {
        case 'devis':
          return 'عرض سعر للطلبية رقم $num';
        case 'proforma':
          return 'فاتورة أولية للطلبية رقم $num';
        case 'facture':
          return 'فاتورة للطلبية رقم $num';
        case 'bon_route':
          return 'بون دو روت للطلبية رقم $num';
        case 'bon_livraison':
          return 'وصل تسليم للطلبية رقم $num';
        case 'bon_charge':
          return 'وصل شحن للطلبية رقم $num';
        default:
          return 'مستند للطلبية رقم $num';
      }
    }
  }

  double _readMoney(dynamic value) {
    if (value is num) return value.toDouble();
    final normalized = value?.toString().trim().replaceAll(',', '.') ?? '';
    return double.tryParse(normalized) ?? 0.0;
  }

  int? _readId(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '');
  }

  String _orderClientName(Map<String, dynamic> order) {
    final direct =
        order['client_name']?.toString().trim() ??
        order['client_display']?.toString().trim() ??
        '';
    if (direct.isNotEmpty) return direct;
    final first = order['firstname']?.toString().trim() ?? '';
    final last = order['lastname']?.toString().trim() ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Client' : full;
  }

  void _showAddOrderPaymentDialog(
    Map<String, dynamic> orderData,
    AppLanguage lang,
  ) {
    final orderId = _readId(orderData['id']);
    final clientId = _readId(orderData['client_id']);
    if (orderId == null || clientId == null) return;

    final total = _readMoney(orderData['net_payable'] ?? orderData['total']);
    final paid = _readMoney(orderData['advance_payment']);
    final remaining = (total - paid).clamp(0.0, double.infinity).toDouble();
    final clientName = _orderClientName(orderData);
    final amountCtrl = TextEditingController();
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    var isSavingPayment = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            '${Localization.translate('Add payment to order', lang)} ${_displayOrderLabel(orderData)}',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          content: TextField(
            controller: amountCtrl,
            autofocus: true,
            enabled: !isSavingPayment,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: Localization.translate('Amount paid', lang),
              hintText:
                  '${Localization.translate('Remaining:', lang)} ${remaining.toStringAsFixed(2)} د.ج',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSavingPayment
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('Cancel', lang)),
            ),
            ElevatedButton(
              onPressed: isSavingPayment
                  ? null
                  : () async {
                      final amount = _readMoney(amountCtrl.text);
                      if (amount <= 0) return;

                      final navigator = Navigator.of(dialogContext);
                      setDialogState(() => isSavingPayment = true);
                      try {
                        await db.insertTreasury(
                          'Encaissement',
                          amount,
                          'دفعة لطلبية رقم ${_displayOrderNumber(orderData)} من الزبون: $clientName',
                          referenceId: orderId,
                          entityType: 'Client',
                          entityId: clientId,
                          recordedBy: settings.userDisplayName,
                        );
                        if (navigator.mounted && navigator.canPop()) {
                          navigator.pop();
                        }
                        if (mounted) _fetchCommandes();
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() => isSavingPayment = false);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${Localization.translate('فشل حفظ الدفعة', lang)}: $error',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: isSavingPayment
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(Localization.translate('Save payment', lang)),
            ),
          ],
        ),
      ),
    ).whenComplete(amountCtrl.dispose);
  }

  TextSpan highlightText(String text, String query) {
    if (query.isEmpty) {
      return TextSpan(text: text);
    }

    List<String> queryWords = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (queryWords.isEmpty) return TextSpan(text: text);

    String pattern = queryWords.map((w) => RegExp.escape(w)).join('|');
    RegExp regExp = RegExp('($pattern)', caseSensitive: false);

    List<TextSpan> spans = [];
    int start = 0;
    for (var match in regExp.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
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
      spans.add(TextSpan(text: text.substring(start)));
    }

    return TextSpan(children: spans);
  }

  static String _normalizeSearch(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[إأآا]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .trim();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadOrderSortPreference());
    _loadWorkshopNameForIdentity();
    _data = _loadInitialCommandes();
    _dbUpdateSubscription = CloudSyncService().dbUpdateStream.listen((_) {
      _scheduleCloudRefresh();
    });
    if (widget.openAddOrderOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openNewOrderForm();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadInitialCommandes() async {
    // Restore the account-scoped read state before the first list is painted,
    // so previously read orders do not briefly appear as new after login.
    await _loadSeenOrderVersions();
    final list = await db.readCommandesWithClients();
    await _upgradeLegacySeenVersions(list);
    if (mounted) {
      setState(() => _cachedCommandes = list);
      final initialOrderId = widget.initialOrderId;
      if (!_initialOrderOpened && initialOrderId != null) {
        final matches = list.where(
          (order) => order['id'].toString() == initialOrderId.toString(),
        );
        if (matches.isNotEmpty) {
          _initialOrderOpened = true;
          _notificationHighlightedOrderId = initialOrderId;
        }
      }
    }
    return list;
  }

  Future<void> _openNewOrderForm() async {
    await openOrderInWorkspaceTab(context, db: db, onSaved: _fetchCommandes);
  }

  /// يفتح أي شاشة كـ tab مستقل في الـ Workspace (مثل طلبية التعديل تماماً).
  /// إذا كان الـ Workspace غير متاح (classic mode) يُستخدم Navigator.push عادياً.
  void _openInWorkspaceTab({
    required String entryId,
    required String title,
    required IconData icon,
    required Widget content,
  }) {
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final usesWorkspace = isWindows || settings.viewMode != AppViewMode.classic;
    if (usesWorkspace) {
      final workspace = Provider.of<WorkspaceController>(
        context,
        listen: false,
      );
      workspace.open(
        entryId: entryId,
        title: title,
        icon: icon,
        content: content,
      );
    } else {
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(MaterialPageRoute(builder: (_) => content));
    }
  }

  void _fetchCommandes() {
    final future = db.readCommandesWithClients();
    _data = future.then((list) {
      if (mounted) {
        setState(() {
          _cachedCommandes = list;
        });
        final initialOrderId = widget.initialOrderId;
        if (!_initialOrderOpened && initialOrderId != null) {
          final matches = list.where(
            (order) => order['id'].toString() == initialOrderId.toString(),
          );
          if (matches.isNotEmpty) {
            _initialOrderOpened = true;
            _notificationHighlightedOrderId = initialOrderId;
          }
        }
      }
      return list;
    });
  }

  /// SQLite result lists can be read-only. Replacing the active list keeps
  /// the user on the same page and preserves the current scroll position.
  void _removeCommandeFromView(Object? commandeId) {
    final current = _cachedCommandes ?? const <Map<String, dynamic>>[];
    final remaining = current
        .where((commande) => commande['id'].toString() != commandeId.toString())
        .map((commande) => Map<String, dynamic>.from(commande))
        .toList(growable: false);

    setState(() {
      _cachedCommandes = remaining;
      _data = Future<List<Map<String, dynamic>>>.value(remaining);
    });
  }

  void _scheduleCloudRefresh() {
    _syncRefreshDebounce?.cancel();
    _syncRefreshDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _fetchCommandes();
    });
  }

  final Map<String, TextEditingController> _orderColumnControllers = {
    'id': TextEditingController(),
    'client_project': TextEditingController(),
    'date': TextEditingController(),
    'updated_at': TextEditingController(),
    'updated_by': TextEditingController(),
    'total': TextEditingController(),
    'advance': TextEditingController(),
    'remaining': TextEditingController(),
    'status': TextEditingController(),
    'stock_reserved': TextEditingController(),
    'creator': TextEditingController(),
  };
  final Map<String, NumericFilterState> _orderNumericFilters = {};
  TableDateRange _orderDateRange = const TableDateRange();

  String? _orderSortColumn;
  bool _orderSortAscending = true;

  Future<void> _loadOrderSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedColumn = prefs.getString(_orderSortColumnPreferenceKey);
    final savedAscending =
        prefs.getBool(_orderSortAscendingPreferenceKey) ?? true;
    if (!mounted) return;
    setState(() {
      _orderSortColumn = _persistableOrderSortColumns.contains(savedColumn)
          ? savedColumn
          : null;
      _orderSortAscending = savedAscending;
    });
  }

  Future<void> _saveOrderSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final column = _orderSortColumn;
    if (column == null) {
      await prefs.remove(_orderSortColumnPreferenceKey);
    } else {
      await prefs.setString(_orderSortColumnPreferenceKey, column);
    }
    await prefs.setBool(_orderSortAscendingPreferenceKey, _orderSortAscending);
  }

  @override
  void dispose() {
    _syncRefreshDebounce?.cancel();
    _dbUpdateSubscription?.cancel();
    _mobileOrdersScrollController.dispose();
    _desktopOrdersScrollController.dispose();
    _mobileSearchController.dispose();
    _mobileSearchFocusNode.dispose();
    for (final controller in _orderColumnControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _clearAllOrderColumnFilters() {
    setState(() {
      for (final controller in _orderColumnControllers.values) {
        controller.clear();
      }
      _orderSortColumn = null;
      _orderSortAscending = true;
    });
    unawaited(_saveOrderSortPreference());
  }

  bool get _hasActiveOrderColumnFilters {
    return _orderSortColumn != null ||
        _orderDateRange.isActive ||
        _orderNumericFilters.values.any((f) => f.isActive) ||
        _orderColumnControllers.values.any((c) => c.text.trim().isNotEmpty);
  }

  String _orderSortText(String key, AppLanguage lang) {
    const labels = <String, List<String>>{
      'title': ['ترتيب الطلبيات', 'Trier les commandes', 'Sort orders'],
      'date': ['تاريخ الطلبية', 'Date de commande', 'Order date'],
      'client_project': ['اسم الزبون', 'Nom du client', 'Client name'],
      'updated_at': ['تاريخ التعديل', 'Date de modification', 'Modified date'],
      'status': ['الحالة', 'Statut', 'Status'],
      'updated_by': ['اسم المعدّل', 'Modifié par', 'Modified by'],
      'creator': ['اسم المُدخل', 'Créé par', 'Created by'],
      'ascending': ['تصاعدي', 'Croissant', 'Ascending'],
      'descending': ['تنازلي', 'Décroissant', 'Descending'],
      'clear': ['إلغاء الترتيب', 'Annuler le tri', 'Clear sorting'],
    };
    final languageIndex = switch (lang) {
      AppLanguage.arabic => 0,
      AppLanguage.french => 1,
      _ => 2,
    };
    return labels[key]?[languageIndex] ?? key;
  }

  Widget _buildOrderSortButton(AppLanguage lang) {
    final activeSort = _orderSortColumn;
    final tooltip = activeSort == null
        ? _orderSortText('title', lang)
        : '${_orderSortText('title', lang)}: '
              '${_orderSortText(activeSort, lang)} · '
              '${_orderSortText(_orderSortAscending ? 'ascending' : 'descending', lang)}';

    return PopupMenuButton<String>(
      tooltip: tooltip,
      onSelected: (value) {
        setState(() {
          if (value == 'direction:ascending') {
            _orderSortAscending = true;
            return;
          }
          if (value == 'direction:descending') {
            _orderSortAscending = false;
            return;
          }
          if (value == 'clear') {
            _orderSortColumn = null;
            _orderSortAscending = true;
            return;
          }

          final selectedColumn = value.substring('column:'.length);
          if (_orderSortColumn != selectedColumn) {
            _orderSortColumn = selectedColumn;
            _orderSortAscending =
                selectedColumn != 'date' && selectedColumn != 'updated_at';
          }
        });
        unawaited(_saveOrderSortPreference());
      },
      itemBuilder: (context) {
        const columns = <String>[
          'date',
          'client_project',
          'updated_at',
          'status',
          'updated_by',
          'creator',
        ];
        return <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            enabled: false,
            height: 36,
            child: Text(
              _orderSortText('title', lang),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ...columns.map(
            (column) => PopupMenuItem<String>(
              value: 'column:$column',
              child: Row(
                children: [
                  Icon(
                    _orderSortColumn == column
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: _orderSortColumn == column
                        ? const Color(0xFF2563EB)
                        : Colors.grey,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _orderSortText(column, lang),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ],
              ),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'direction:ascending',
            enabled: activeSort != null,
            child: Row(
              children: [
                Icon(
                  Icons.arrow_upward_rounded,
                  size: 18,
                  color: activeSort != null && _orderSortAscending
                      ? const Color(0xFF2563EB)
                      : Colors.grey,
                ),
                const SizedBox(width: 10),
                Text(
                  _orderSortText('ascending', lang),
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'direction:descending',
            enabled: activeSort != null,
            child: Row(
              children: [
                Icon(
                  Icons.arrow_downward_rounded,
                  size: 18,
                  color: activeSort != null && !_orderSortAscending
                      ? const Color(0xFF2563EB)
                      : Colors.grey,
                ),
                const SizedBox(width: 10),
                Text(
                  _orderSortText('descending', lang),
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
          if (activeSort != null) ...[
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'clear',
              child: Row(
                children: [
                  const Icon(Icons.sort_by_alpha_rounded, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    _orderSortText('clear', lang),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ],
              ),
            ),
          ],
        ];
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: activeSort == null
              ? Theme.of(context).colorScheme.surface
              : const Color(0xFF2563EB).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: activeSort == null
                ? Theme.of(context).dividerColor
                : const Color(0xFF2563EB),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.sort_rounded,
              color: activeSort == null ? Colors.grey : const Color(0xFF2563EB),
            ),
            if (activeSort != null)
              Positioned(
                right: 4,
                bottom: 4,
                child: Icon(
                  _orderSortAscending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 12,
                  color: const Color(0xFF2563EB),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _applyOrderFiltersAndSort(
    List<Map<String, dynamic>> rawData,
    AppLanguage lang,
  ) {
    List<Map<String, dynamic>> filtered = rawData.where((d) {
      if (widget.openOrdersOnly &&
          !isOpenOrderStatus((d['status'] ?? '').toString())) {
        return false;
      }
      final query = _searchQuery.trim();
      if (query.isNotEmpty) {
        final first = (d['firstname'] ?? '').toString();
        final last = (d['lastname'] ?? '').toString();
        final phone = (d['phone'] ?? '').toString();
        final id = (d['id'] ?? '').toString();
        final seq = (d['sequence_number'] ?? '').toString();
        final project = (d['project_name'] ?? '').toString();
        final location = (d['window_location'] ?? '').toString();
        final full = '$first $last $phone $id $seq $project $location';

        final normalizedFull = _normalizeSearch(full);
        final normalizedQuery = _normalizeSearch(query);
        final terms = normalizedQuery
            .split(RegExp(r'\s+'))
            .where((term) => term.isNotEmpty);
        if (!terms.every((term) => normalizedFull.contains(term))) {
          return false;
        }
      }

      // Date Range Filter
      if (_orderDateRange.isActive) {
        final dStr = (d['created_at'] ?? d['date'] ?? '').toString();
        final dt = DateTime.tryParse(dStr);
        if (!_orderDateRange.isWithinRange(dt)) return false;
      }

      // Numeric Filters (id, total, advance, remaining)
      if (_orderNumericFilters['id']?.isActive == true) {
        final idNum = (d['id'] as num?)?.toDouble() ?? 0.0;
        if (!_orderNumericFilters['id']!.matches(idNum)) return false;
      }

      final netPayable =
          (d['net_payable'] as num?)?.toDouble() ??
          (d['total'] as num?)?.toDouble() ??
          0.0;
      final advance = (d['advance_payment'] as num?)?.toDouble() ?? 0.0;
      final remaining = netPayable - advance;

      if (_orderNumericFilters['total']?.isActive == true) {
        if (!_orderNumericFilters['total']!.matches(netPayable)) return false;
      }
      if (_orderNumericFilters['advance']?.isActive == true) {
        if (!_orderNumericFilters['advance']!.matches(advance)) return false;
      }
      if (_orderNumericFilters['remaining']?.isActive == true) {
        if (!_orderNumericFilters['remaining']!.matches(remaining))
          return false;
      }

      // Text column filters
      for (final entry in _orderColumnControllers.entries) {
        final colKey = entry.key;
        final filterVal = entry.value.text.toLowerCase().trim();
        if (filterVal.isEmpty) continue;

        switch (colKey) {
          case 'id':
            if (_orderNumericFilters['id']?.isActive != true) {
              final idStr = (d['id'] ?? '').toString().toLowerCase();
              if (!idStr.contains(filterVal)) return false;
            }
            break;
          case 'client_project':
            final clientFirst = (d['firstname'] ?? '').toString().toLowerCase();
            final clientLast = (d['lastname'] ?? '').toString().toLowerCase();
            final clientName = '$clientFirst $clientLast'.trim();
            final projectName = (d['project_name'] ?? '')
                .toString()
                .toLowerCase();
            final cpStr = '$clientName $projectName'.trim();
            if (!cpStr.contains(filterVal)) return false;
            break;
          case 'date':
            final dt = formatDate(d).toLowerCase();
            if (!dt.contains(filterVal)) return false;
            break;
          case 'updated_at':
            final dt = formatOrderDate(
              d['updated_at'],
              fallback: d['created_at'],
            ).toLowerCase();
            if (!dt.contains(filterVal)) return false;
            break;
          case 'updated_by':
            final editor = _formatEditorDisplay(
              d['updated_by']?.toString(),
            ).toLowerCase();
            if (!editor.contains(filterVal)) return false;
            break;
          case 'total':
            if (_orderNumericFilters['total']?.isActive != true) {
              final tStr = netPayable.toStringAsFixed(0);
              if (!tStr.contains(filterVal)) return false;
            }
            break;
          case 'advance':
            if (_orderNumericFilters['advance']?.isActive != true) {
              final aStr = advance.toStringAsFixed(0);
              if (!aStr.contains(filterVal)) return false;
            }
            break;
          case 'remaining':
            if (_orderNumericFilters['remaining']?.isActive != true) {
              final rStr = remaining.toStringAsFixed(0);
              if (!rStr.contains(filterVal)) return false;
            }
            break;
          case 'status':
            final rawStatus = (d['status'] ?? 'Pending').toString();
            final weight = _getOrderStatusWeight(rawStatus);
            final statusStr = _translateStatus(rawStatus, lang).toLowerCase();
            final lower = filterVal.toLowerCase();
            if (lower == 'filter_confirmed_above') {
              if (weight < 20 || weight >= 999) return false;
            } else if (lower == 'filter_mfg_above') {
              if (weight < 50 || weight >= 999) return false;
            } else if (lower == 'filter_dist_above') {
              if (weight < 70 || weight >= 999) return false;
            } else if (lower.startsWith('filter_status_group:')) {
              final selectedGroup = lower.substring(
                'filter_status_group:'.length,
              );
              if (orderStatusGroupKey(rawStatus) != selectedGroup) {
                return false;
              }
            } else if (!statusStr.contains(lower) &&
                !rawStatus.toLowerCase().contains(lower)) {
              return false;
            }
            break;
          case 'stock_reserved':
            final rawStatus = (d['status'] ?? '').toString();
            final passedMfg = _hasPassedFullManufacturing(rawStatus);
            final lower = filterVal.toLowerCase();
            if (passedMfg) {
              if (lower == '-' || lower == '—') {
                break;
              }
              return false;
            }
            final isReserved = (d['is_stock_reserved'] as num?)?.toInt() == 1;
            final reservedAr = isReserved ? 'تم الحجز' : 'لم يُحجز بعد';
            final reservedFr = isReserved ? 'réservé' : 'non réservé';
            if (!reservedAr.toLowerCase().contains(lower) &&
                !reservedFr.toLowerCase().contains(lower) &&
                !(isReserved ? 'محجوز' : 'غير محجوز').contains(lower)) {
              return false;
            }
            break;
          case 'creator':
            final rawPlatform = d['creation_platform']?.toString();
            final creatorStr = _formatCreatorDisplay(rawPlatform).toLowerCase();
            if (!creatorStr.contains(filterVal) &&
                !(rawPlatform ?? '').toLowerCase().contains(filterVal)) {
              return false;
            }
            break;
        }
      }
      return true;
    }).toList();

    if (_orderSortColumn == null) {
      filtered.sort(compareOrdersByLifecycle);
    } else {
      filtered.sort((a, b) {
        int comp = 0;
        switch (_orderSortColumn) {
          case 'id':
            final aId = (a['id'] as num?)?.toInt() ?? 0;
            final bId = (b['id'] as num?)?.toInt() ?? 0;
            comp = aId.compareTo(bId);
            break;
          case 'client_project':
            final aName =
                '${a['firstname'] ?? ''} ${a['lastname'] ?? ''} ${a['project_name'] ?? ''}';
            final bName =
                '${b['firstname'] ?? ''} ${b['lastname'] ?? ''} ${b['project_name'] ?? ''}';
            comp = aName.compareTo(bName);
            break;
          case 'date':
            final aDate = (a['created_at'] ?? a['date'] ?? '').toString();
            final bDate = (b['created_at'] ?? b['date'] ?? '').toString();
            comp = aDate.compareTo(bDate);
            break;
          case 'updated_at':
            final aDate = (a['updated_at'] ?? a['created_at'] ?? '').toString();
            final bDate = (b['updated_at'] ?? b['created_at'] ?? '').toString();
            comp = aDate.compareTo(bDate);
            break;
          case 'updated_by':
            final aEditor = _formatEditorDisplay(a['updated_by']?.toString());
            final bEditor = _formatEditorDisplay(b['updated_by']?.toString());
            comp = aEditor.compareTo(bEditor);
            break;
          case 'total':
            final aTot =
                (a['net_payable'] as num?)?.toDouble() ??
                (a['total'] as num?)?.toDouble() ??
                0.0;
            final bTot =
                (b['net_payable'] as num?)?.toDouble() ??
                (b['total'] as num?)?.toDouble() ??
                0.0;
            comp = aTot.compareTo(bTot);
            break;
          case 'advance':
            final aAdv = (a['advance_payment'] as num?)?.toDouble() ?? 0.0;
            final bAdv = (b['advance_payment'] as num?)?.toDouble() ?? 0.0;
            comp = aAdv.compareTo(bAdv);
            break;
          case 'remaining':
            final aRem =
                ((a['net_payable'] as num?)?.toDouble() ??
                    (a['total'] as num?)?.toDouble() ??
                    0.0) -
                ((a['advance_payment'] as num?)?.toDouble() ?? 0.0);
            final bRem =
                ((b['net_payable'] as num?)?.toDouble() ??
                    (b['total'] as num?)?.toDouble() ??
                    0.0) -
                ((b['advance_payment'] as num?)?.toDouble() ?? 0.0);
            comp = aRem.compareTo(bRem);
            break;
          case 'status':
            final aSt = (a['status'] ?? '').toString();
            final bSt = (b['status'] ?? '').toString();
            final wA = _getOrderStatusWeight(aSt);
            final wB = _getOrderStatusWeight(bSt);
            comp = wA.compareTo(wB);
            if (comp == 0) {
              comp = aSt.compareTo(bSt);
            }
            break;
          case 'stock_reserved':
            final aRes = (a['is_stock_reserved'] as num?)?.toInt() ?? 0;
            final bRes = (b['is_stock_reserved'] as num?)?.toInt() ?? 0;
            comp = aRes.compareTo(bRes);
            break;
          case 'creator':
            final aCr = _formatCreatorDisplay(
              a['creation_platform']?.toString(),
            );
            final bCr = _formatCreatorDisplay(
              b['creation_platform']?.toString(),
            );
            comp = aCr.compareTo(bCr);
            break;
        }
        return _orderSortAscending ? comp : -comp;
      });
    }

    // Search and column filters have already been applied. Pinning only
    // partitions the visible result. Pinned orders keep their own pin-time
    // order, while the selected sort remains authoritative for regular rows.
    return putPinnedOrdersFirst(filtered);
  }

  Future<void> _toggleOrderPin(Map<String, dynamic> order) async {
    final orderId = (order['id'] as num?)?.toInt();
    if (orderId == null) return;
    final pinned = !isOrderPinned(order);
    final updated = await db.setOrderPinned(orderId: orderId, pinned: pinned);
    if (!mounted) return;
    if (!updated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('تعذر تحديث تثبيت الطلبية.')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    _fetchCommandes();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          pinned
              ? _t('تم تثبيت الطلبية في الأعلى.')
              : _t('تم إلغاء تثبيت الطلبية.'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDesktop =
        MediaQuery.of(context).size.width >= 900 || Platform.isWindows;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(Localization.translate("Commande", lang)),
        centerTitle: !isDesktop,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
        actions: [
          if (!isDesktop)
            IconButton(
              icon: Icon(
                _showMobileSearch ? Icons.close_rounded : Icons.search_rounded,
                color: Colors.white,
              ),
              tooltip: Localization.translate(
                _showMobileSearch ? 'إغلاق البحث' : 'Search',
                lang,
              ),
              onPressed: () {
                setState(() {
                  _showMobileSearch = !_showMobileSearch;
                  if (!_showMobileSearch) {
                    _mobileSearchController.clear();
                    _searchQuery = '';
                    _mobileSearchFocusNode.unfocus();
                  }
                });
                if (_showMobileSearch) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _mobileSearchFocusNode.requestFocus();
                  });
                }
              },
            ),
          IconButton(
            icon: _isImportPicking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.file_upload_outlined, color: Colors.white),
            tooltip: Localization.translate('import_order', lang),
            onPressed: _isImportPicking ? null : _importOrder,
          ),
          if (settings.canAccessTrash())
            IconButton(
              icon: const Icon(Icons.auto_delete_rounded, color: Colors.white),
              tooltip: Localization.translate('orders_trash', lang),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        TrashScreen(db: db, onOrderRestored: _fetchCommandes),
                  ),
                ).then((_) {
                  if (mounted) _fetchCommandes();
                });
              },
            ),
          if (isDesktop && settings.canCreateOrders())
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: () {
                  openOrderInWorkspaceTab(
                    context,
                    db: db,
                    onSaved: _fetchCommandes,
                  );
                },
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: Text(
                  lang == AppLanguage.arabic
                      ? 'إضافة طلبية جديدة'
                      : (lang == AppLanguage.french
                            ? 'Nouvelle commande'
                            : 'Add New Order'),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2563EB),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final bodyColumn = Column(
            children: [
              if (!isDesktop && _showMobileSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: TextField(
                    controller: _mobileSearchController,
                    focusNode: _mobileSearchFocusNode,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _mobileSearchFocusNode.unfocus(),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                      if (_mobileOrdersScrollController.hasClients) {
                        _mobileOrdersScrollController.jumpTo(0);
                      }
                      if (_desktopOrdersScrollController.hasClients) {
                        _desktopOrdersScrollController.jumpTo(0);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: Localization.translate('Search', lang),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: Localization.translate(
                                'مسح البحث',
                                lang,
                              ),
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _mobileSearchController.clear();
                                setState(() => _searchQuery = '');
                                if (_mobileOrdersScrollController.hasClients) {
                                  _mobileOrdersScrollController.jumpTo(0);
                                }
                                if (_desktopOrdersScrollController.hasClients) {
                                  _desktopOrdersScrollController.jumpTo(0);
                                }
                                _mobileSearchFocusNode.requestFocus();
                              },
                            ),
                      isDense: true,
                      filled: true,
                      fillColor: Theme.of(context).cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Container(
                  margin: isDesktop
                      ? const EdgeInsets.all(10)
                      : const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _data,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        _cachedCommandes = snapshot.data;
                      }

                      if (snapshot.connectionState == ConnectionState.waiting &&
                          _cachedCommandes == null) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError &&
                          _cachedCommandes == null) {
                        // 🟢 التصميم التفاعلي لحالة الخطأ (بدون أكواد SQL مرعبة)
                        return Center(
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(25),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.warning_amber_rounded,
                                      size: 70,
                                      color: Colors.red.shade400,
                                    ),
                                  ),
                                  const SizedBox(height: 25),
                                  Text(
                                    'عذراً، حدث خطأ غير متوقع!',
                                    style: TextStyle(
                                      color: Colors.red.shade800,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 15),
                                  Container(
                                    padding: const EdgeInsets.all(15),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(15),
                                      border: Border.all(
                                        color: Colors.red.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      // 🟢 الرسالة المفهومة للمستخدم بدلاً من snapshot.error
                                      'تعذر تحميل البيانات حالياً. يرجى التأكد من استقرار النظام أو تحديث الصفحة للمحاولة مرة أخرى.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontSize: 15,
                                        height: 1.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ExpansionTile(
                                    title: const Text('تفاصيل الخطأ / Détails'),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: SelectableText(
                                          snapshot.error.toString(),
                                          textDirection: TextDirection.ltr,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 30),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.red.shade600,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 30,
                                        vertical: 12,
                                      ),
                                      elevation: 0,
                                      side: BorderSide(
                                        color: Colors.red.shade200,
                                        width: 1.5,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                    ),
                                    onPressed: () {
                                      _fetchCommandes();
                                    },
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 22,
                                    ),
                                    label: const Text(
                                      'تحديث الصفحة',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      final rawData = snapshot.hasData
                          ? snapshot.data!
                          : (_cachedCommandes ?? <Map<String, dynamic>>[]);

                      // 🟢 التصميم التفاعلي لحالة عدم وجود طلبات
                      if (rawData.isEmpty) {
                        return Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(30),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.receipt_long_outlined,
                                    size: 80,
                                    color: Colors.blue.shade400,
                                  ),
                                ),
                                const SizedBox(height: 25),
                                Text(
                                  Localization.translate(
                                    "No Data",
                                    Provider.of<AppSettingsProvider>(
                                      context,
                                    ).language,
                                  ),
                                  style: TextStyle(
                                    color: Colors.blueGrey.shade800,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _t(
                                    'لا توجد أي طلبيات مسجلة حالياً.\nابدأ الآن بإنشاء أول فاتورة أو ورقة تقطيع للعميل.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 15,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 35),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade600,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 30,
                                      vertical: 15,
                                    ),
                                    elevation: 4,
                                    shadowColor: Colors.blue.withValues(
                                      alpha: 0.4,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                  ),
                                  onPressed: () {
                                    openOrderInWorkspaceTab(
                                      context,
                                      db: db,
                                      onSaved: _fetchCommandes,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    size: 24,
                                  ),
                                  label: Text(
                                    _t('إنشاء طلبية جديدة'),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      final data = _applyOrderFiltersAndSort(rawData, lang);

                      if (MediaQuery.of(context).size.width >= 900 ||
                          Platform.isWindows) {
                        return _buildDesktopOrdersTableView(
                          context,
                          rawData,
                          lang,
                        );
                      }

                      if (data.isEmpty) {
                        return Center(
                          child: Text(
                            Localization.translate('No matching results', lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        controller: _mobileOrdersScrollController,
                        primary: false,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          10,
                          8,
                          10,
                          _showMobileSearch ? 16 : 80,
                        ),
                        itemCount: data.length,
                        itemBuilder: (context, index) {
                          final pinned = isOrderPinned(data[index]);
                          final clientFirst = data[index]['firstname'] ?? '';
                          final clientLast = data[index]['lastname'] ?? '';

                          final clientPhone = data[index]['phone'];
                          final bool hasPhone =
                              clientPhone != null &&
                              clientPhone.toString().trim().isNotEmpty &&
                              clientPhone.toString() != 'null';

                          final clientName = '$clientFirst $clientLast'.trim();
                          final clientDisplay = clientName.isEmpty
                              ? 'زبون غير معروف'
                              : clientName;

                          final netPayable =
                              (data[index]['net_payable'] as num?)
                                  ?.toDouble() ??
                              0.0;
                          final rawTotal =
                              (data[index]['total'] as num?)?.toDouble() ?? 0.0;
                          final total = netPayable > 0.0
                              ? netPayable
                              : rawTotal;
                          final status = data[index]['status'] ?? 'New';

                          final isUnseen = _isOrderUnseen(data[index]);

                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: isUnseen
                                  ? const BorderSide(
                                      color: Color(0xFF10B981),
                                      width: 1.6,
                                    )
                                  : BorderSide.none,
                            ),
                            elevation: isUnseen ? 3 : 2,
                            color: isUnseen
                                ? (Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? const Color(
                                          0xFF064E3B,
                                        ).withValues(alpha: 0.35)
                                      : const Color(0xFFF0FDF4))
                                : null,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(15),
                              onTap: settings.canViewOrderDetails()
                                  ? () {
                                      _markOrderSeen(data[index]);
                                      _showOrderOptions(context, data[index]);
                                    }
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: Colors.blue.shade100,
                                      child: Icon(
                                        pinned
                                            ? Icons.push_pin_rounded
                                            : Icons.receipt_long,
                                        color: pinned
                                            ? Colors.orange.shade800
                                            : Colors.blue,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          RichText(
                                            text: TextSpan(
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: Theme.of(
                                                  context,
                                                ).textTheme.bodyLarge?.color,
                                              ),
                                              children: [
                                                highlightText(
                                                  clientDisplay,
                                                  _searchQuery,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            formatDate(data[index]),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(
                                                context,
                                              ).textTheme.bodySmall?.color,
                                            ),
                                          ),
                                          if (hasPhone) ...[
                                            const SizedBox(height: 2),
                                            RichText(
                                              text: TextSpan(
                                                style: TextStyle(
                                                  color: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall?.color,
                                                  fontSize: 13,
                                                ),
                                                children: [
                                                  highlightText(
                                                    clientPhone.toString(),
                                                    _searchQuery,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          if (data[index]['project_name'] !=
                                                  null &&
                                              data[index]['project_name']
                                                  .toString()
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.blue.shade50,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.folder,
                                                          size: 12,
                                                          color: Colors
                                                              .blue
                                                              .shade700,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Flexible(
                                                          child: Text(
                                                            data[index]['project_name']
                                                                .toString(),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            maxLines: 1,
                                                            style: TextStyle(
                                                              color: Colors
                                                                  .blue
                                                                  .shade800,
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                '${total.toStringAsFixed(2)} دج',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: _getStatusColor(
                                                    status,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  _translateStatus(
                                                    status,
                                                    Provider.of<
                                                          AppSettingsProvider
                                                        >(
                                                          context,
                                                          listen: false,
                                                        )
                                                        .language,
                                                  ),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              Builder(
                                                builder: (ctx) {
                                                  final currentStatus =
                                                      (data[index]['status'] ??
                                                              '')
                                                          .toString();
                                                  if (_hasPassedFullManufacturing(
                                                    currentStatus,
                                                  )) {
                                                    return const SizedBox.shrink();
                                                  }
                                                  final isStockReserved =
                                                      (data[index]['is_stock_reserved']
                                                              as num?)
                                                          ?.toInt() ==
                                                      1;
                                                  final lang =
                                                      Provider.of<
                                                            AppSettingsProvider
                                                          >(ctx, listen: false)
                                                          .language;
                                                  return Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 7,
                                                          vertical: 2.5,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: isStockReserved
                                                          ? Colors.green
                                                                .withValues(
                                                                  alpha: 0.15,
                                                                )
                                                          : Colors.grey
                                                                .withValues(
                                                                  alpha: 0.12,
                                                                ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      border: Border.all(
                                                        color: isStockReserved
                                                            ? Colors
                                                                  .green
                                                                  .shade600
                                                            : Colors
                                                                  .grey
                                                                  .shade400,
                                                        width: 0.8,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          isStockReserved
                                                              ? Icons
                                                                    .check_circle
                                                              : Icons
                                                                    .inventory_2_outlined,
                                                          size: 11,
                                                          color: isStockReserved
                                                              ? Colors
                                                                    .green
                                                                    .shade800
                                                              : Colors
                                                                    .grey
                                                                    .shade600,
                                                        ),
                                                        const SizedBox(
                                                          width: 3,
                                                        ),
                                                        Text(
                                                          isStockReserved
                                                              ? Localization.translate(
                                                                  'تم الحجز',
                                                                  lang,
                                                                )
                                                              : Localization.translate(
                                                                  'لم يُحجز بعد',
                                                                  lang,
                                                                ),
                                                          style: TextStyle(
                                                            color:
                                                                isStockReserved
                                                                ? Colors
                                                                      .green
                                                                      .shade900
                                                                : Colors
                                                                      .grey
                                                                      .shade700,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
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
                                    ),
                                    const SizedBox(width: 6),
                                    const Padding(
                                      padding: EdgeInsets.only(top: 4),
                                      child: Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          );

          if (isDesktop) {
            return DesktopScrollFallback(
              controller: _desktopOrdersScrollController,
              child: bodyColumn,
            );
          }
          return bodyColumn;
        },
      ),

      floatingActionButton:
          (!isDesktop &&
              settings.canCreateOrders() &&
              MediaQuery.of(context).viewInsets.bottom == 0)
          ? FloatingActionButton(
              onPressed: () {
                openOrderInWorkspaceTab(
                  context,
                  db: db,
                  onSaved: _fetchCommandes,
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _showOrderOptions(
    BuildContext context,
    Map<String, dynamic> orderData,
  ) async {
    final orderId = (orderData['id'] as num?)?.toInt() ?? 0;
    // The list row can legitimately be one repaint behind a live detail
    // update. Documents must always use the newest order header as well as
    // the freshly read Commandes_details rows, otherwise edit and pricing can
    // show two different versions of the same order.
    if (orderId > 0) {
      final freshOrder = await db.readCommandeWithClientById(orderId);
      if (freshOrder != null) {
        orderData = {...orderData, ...freshOrder};
      }
    }
    final isFullyManufactured = await db.isOrderFullyManufactured(orderId);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        final settings = Provider.of<AppSettingsProvider>(
          context,
          listen: false,
        );
        final lang = settings.language;
        final currentStatus = orderData['status']?.toString() ?? 'Pending';
        final statusRaw = (orderData['status']?.toString() ?? '')
            .trim()
            .toLowerCase();
        final isPending =
            statusRaw == 'nouveau' ||
            statusRaw == 'جديد' ||
            statusRaw == 'جديدة' ||
            statusRaw == 'en attente' ||
            statusRaw == 'في الانتظار' ||
            statusRaw == 'pending' ||
            statusRaw == 'draft' ||
            statusRaw == 'new' ||
            statusRaw == 'en_attente';
        final isConfirmedOrBeyond = !isPending;
        final isManufacturingOrBeyond =
            isConfirmedOrBeyond &&
            statusRaw != 'confirmed' &&
            statusRaw != 'مؤكدة' &&
            statusRaw != 'مؤكد';

        final isDistributedOrBeyond =
            isFullyManufactured ||
            statusRaw.contains('full manufacturing') ||
            statusRaw.contains('تصنيع كلي') ||
            statusRaw.contains('distribution') ||
            statusRaw.contains('توزيع') ||
            statusRaw.contains('installation') ||
            statusRaw.contains('تركيب') ||
            statusRaw.contains('reserve') ||
            statusRaw.contains('تحفظ') ||
            statusRaw.contains('done') ||
            statusRaw.contains('انتهاء') ||
            statusRaw.contains('منتهية');

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 15),

                ListTile(
                  leading: Icon(
                    isOrderPinned(orderData)
                        ? Icons.push_pin_outlined
                        : Icons.push_pin_rounded,
                    color: Colors.orange.shade700,
                  ),
                  title: Text(
                    isOrderPinned(orderData)
                        ? (lang == AppLanguage.french
                              ? 'Désépingler la commande'
                              : 'إلغاء تثبيت الطلبية')
                        : (lang == AppLanguage.french
                              ? 'Épingler la commande en haut'
                              : 'تثبيت الطلبية في الأعلى'),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _toggleOrderPin(orderData);
                  },
                ),
                const Divider(),

                // Beautiful Header showing Order details & Status
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${lang == AppLanguage.french ? "Commande" : "طلب"} ${_displayOrderLabel(orderData)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                fontFamily: 'Cairo',
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              orderData['client_name']?.toString() ??
                                  orderData['client_display']?.toString() ??
                                  "Client",
                              style: TextStyle(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                                fontSize: 13,
                                fontFamily: 'Cairo',
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.list_alt_outlined),
                        label: Text(
                          lang == AppLanguage.arabic
                              ? 'التفاصيل'
                              : lang == AppLanguage.french
                              ? 'Détails'
                              : 'Details',
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OrderMeasurementsDetailsScreen(
                                orderData: orderData,
                                db: db,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(currentStatus),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _translateStatus(currentStatus, lang),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                const SizedBox(height: 10),

                // 1. الوثائق والمستندات الرسمية للطلبية
                // 1. الوثائق والمستندات الرسمية للطلبية
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: Text(Localization.translate('doc_devis_menu', lang)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _showHeavyLoadingDialog(context, lang);
                    try {
                      final rawItems = await db
                          .readCommandeDetails(orderData['id'])
                          .timeout(const Duration(seconds: 10));
                      final List<Map<String, dynamic>> items = rawItems
                          .map((item) => Map<String, dynamic>.from(item))
                          .toList();

                      await _restoreDocumentImagesFromStoredBytes(items);

                      final workshop = await DevisBuilder.loadWorkshopInfo()
                          .timeout(const Duration(seconds: 6));
                      final devis = await DevisBuilder.build(
                        order: orderData,
                        items: items,
                        workshop: workshop,
                        documentTitleKey: 'doc_devis',
                      ).timeout(const Duration(seconds: 10));
                      _dismissHeavyLoadingDialog();
                      final orderId = orderData['id']?.toString() ?? '';
                      _openInWorkspaceTab(
                        entryId: 'devis_$orderId',
                        title: _documentTabTitle(
                          docType: 'devis',
                          orderData: orderData,
                          lang: lang,
                        ),
                        icon: Icons.description_outlined,
                        content: DevisPreviewScreen(data: devis),
                      );
                    } catch (e) {
                      _dismissHeavyLoadingDialog();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${_t('خطأ أثناء توليد الفاتورة')}: $e',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),

                if (settings.canViewOrderDocuments())
                  ListTile(
                    leading: const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.deepPurple,
                    ),
                    title: Text(Localization.translate('Picture', lang)),
                    subtitle: Text(
                      Localization.translate(
                        'صور النوافذ مع التفاصيل والمقاسات',
                        lang,
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _exportOrderPicturePdf(context, orderData, lang);
                    },
                  ),

                ListTile(
                  leading: const Icon(
                    Icons.grid_view_rounded,
                    color: Color(0xFF00695C),
                  ),
                  title: Text(
                    Localization.translate('ورقة تصنيع الزجاج (PDF)', lang),
                  ),
                  subtitle: Text(
                    Localization.translate(
                      'جميع تصاميم ومقاسات وثقوب الزجاج المقسى للطلبية',
                      lang,
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportOrderGlassFabricationPdf(context, orderData, lang);
                  },
                ),

                if (isConfirmedOrBeyond &&
                    (settings.canEditPayments() ||
                        settings.canAccessTreasury()))
                  ListTile(
                    leading: const Icon(
                      Icons.payments_outlined,
                      color: Colors.green,
                    ),
                    title: Text(Localization.translate('Add payment', lang)),
                    subtitle: Text(
                      '${Localization.translate('Remaining:', lang)} ${(_readMoney(orderData['net_payable'] ?? orderData['total']) - _readMoney(orderData['advance_payment'])).clamp(0.0, double.infinity).toStringAsFixed(2)} د.ج',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showAddOrderPaymentDialog(orderData, lang);
                    },
                  ),

                // 1.3. Facture Officielle / Proforma
                if (settings.canViewOrderDocuments())
                  ListTile(
                    leading: const Icon(
                      Icons.description,
                      color: Colors.indigo,
                    ),
                    title: Text(
                      Localization.translate('فاتورة رسمية / أولية', lang),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _showHeavyLoadingDialog(context, lang);
                      try {
                        final rawItems = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final List<Map<String, dynamic>> items = rawItems
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList();
                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final devis = await DevisBuilder.build(
                          order: orderData,
                          items: items,
                          workshop: workshop,
                          isProForma: true,
                        );
                        _dismissHeavyLoadingDialog();
                        final orderId = orderData['id']?.toString() ?? '';
                        _openInWorkspaceTab(
                          entryId: 'proforma_$orderId',
                          title: _documentTabTitle(
                            docType: 'proforma',
                            orderData: orderData,
                            lang: lang,
                          ),
                          icon: Icons.receipt_long_outlined,
                          content: DevisPreviewScreen(data: devis),
                        );
                      } catch (e) {
                        _dismissHeavyLoadingDialog();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${_t('خطأ أثناء توليد الفاتورة')}: $e',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // Facture de Vente
                if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.receipt_rounded,
                      color: Colors.green,
                    ),
                    title: Text(
                      lang == AppLanguage.french
                          ? 'Facture de Vente'
                          : 'فاتورة بيع / Facture de Vente',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _showHeavyLoadingDialog(context, lang);
                      try {
                        final rawItems = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final List<Map<String, dynamic>> items = rawItems
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList();
                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final devis = await DevisBuilder.build(
                          order: orderData,
                          items: items,
                          workshop: workshop,
                          isProForma: false,
                          documentTitleKey: 'FACTURE_VENTE',
                        );
                        _dismissHeavyLoadingDialog();
                        final orderId = orderData['id']?.toString() ?? '';
                        _openInWorkspaceTab(
                          entryId: 'facture_$orderId',
                          title: _documentTabTitle(
                            docType: 'facture',
                            orderData: orderData,
                            lang: lang,
                          ),
                          icon: Icons.receipt_rounded,
                          content: DevisPreviewScreen(data: devis),
                        );
                      } catch (e) {
                        _dismissHeavyLoadingDialog();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${_t('خطأ أثناء توليد الفاتورة')}: $e',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // Bon de Route
                if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.directions_car_outlined,
                      color: Colors.blueAccent,
                    ),
                    title: Text(
                      lang == AppLanguage.french
                          ? 'Bon de Route'
                          : 'بون دو روت / Bon de Route',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _showHeavyLoadingDialog(context, lang);
                      try {
                        final rawItems = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final List<Map<String, dynamic>> items = rawItems
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList();
                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final devis = await DevisBuilder.build(
                          order: orderData,
                          items: items,
                          workshop: workshop,
                          isProForma: false,
                          documentTitleKey: 'BON_ROUTE',
                        );
                        _dismissHeavyLoadingDialog();
                        final orderId = orderData['id']?.toString() ?? '';
                        _openInWorkspaceTab(
                          entryId: 'bon_route_$orderId',
                          title: _documentTabTitle(
                            docType: 'bon_route',
                            orderData: orderData,
                            lang: lang,
                          ),
                          icon: Icons.directions_car_outlined,
                          content: DevisPreviewScreen(data: devis),
                        );
                      } catch (e) {
                        _dismissHeavyLoadingDialog();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${_t('خطأ أثناء توليد المستند')}: $e',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // Bon de livraison
                if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                  ListTile(
                    leading: const Icon(Icons.assignment, color: Colors.blue),
                    title: Text(
                      Localization.translate('doc_bon_livraison_menu', lang),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _showHeavyLoadingDialog(context, lang);
                      try {
                        final rawItems = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final List<Map<String, dynamic>> items = rawItems
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList();

                        for (var item in items) {
                          final path =
                              item['drawing_image_path']?.toString() ?? '';
                          if (path.isEmpty ||
                              !File(path).existsSync() ||
                              storedOrderDetailColorDiffersFromModel(
                                item,
                                savedWindowModelMap(item['partitions_json']),
                              )) {
                            final jsonRaw = item['partitions_json'];
                            if (jsonRaw != null) {
                              try {
                                Map<String, dynamic> modelMap = {};
                                if (jsonRaw is Map<String, dynamic>) {
                                  modelMap = jsonRaw;
                                } else if (jsonRaw is Map) {
                                  modelMap = Map<String, dynamic>.from(jsonRaw);
                                } else {
                                  final str = jsonRaw.toString().trim();
                                  if (str.length >= 5) {
                                    modelMap =
                                        jsonDecode(str) as Map<String, dynamic>;
                                  }
                                }
                                if (modelMap.isNotEmpty) {
                                  final model = WindowModel(db: db);
                                  await applyWindowModelAndLoadCatalog(
                                    model,
                                    modelMap,
                                  );
                                  applyStoredOrderDetailColorToWindowModel(
                                    model,
                                    item,
                                  );
                                  final newPath = await saveWindowImageToDisk(
                                    model,
                                  );
                                  if (newPath.isNotEmpty) {
                                    await db.updateCommandeDetailImagePath(
                                      item['id'] as int,
                                      newPath,
                                    );
                                    item['drawing_image_path'] = newPath;
                                  }
                                }
                              } catch (err) {
                                debugPrint(
                                  'Error generating missing image: $err',
                                );
                              }
                            }
                          }
                        }

                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final devis = await DevisBuilder.build(
                          order: orderData,
                          items: items,
                          workshop: workshop,
                          hidePrices: false,
                          documentTitleKey: 'doc_bon_livraison',
                        );
                        _dismissHeavyLoadingDialog();
                        final orderId = orderData['id']?.toString() ?? '';
                        _openInWorkspaceTab(
                          entryId: 'bon_livraison_$orderId',
                          title: _documentTabTitle(
                            docType: 'bon_livraison',
                            orderData: orderData,
                            lang: lang,
                          ),
                          icon: Icons.local_shipping_outlined,
                          content: DevisPreviewScreen(data: devis),
                        );
                      } catch (e) {
                        _dismissHeavyLoadingDialog();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${_t('خطأ أثناء توليد الفاتورة')}: $e',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // Bon de livraison sans prix
                if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.print_disabled,
                      color: Colors.blueGrey,
                    ),
                    title: Text(
                      Localization.translate(
                        'doc_bon_livraison_sans_prix_menu',
                        lang,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _showHeavyLoadingDialog(context, lang);
                      try {
                        final rawItems = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final List<Map<String, dynamic>> items = rawItems
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList();

                        for (var item in items) {
                          final path =
                              item['drawing_image_path']?.toString() ?? '';
                          if (path.isEmpty ||
                              !File(path).existsSync() ||
                              storedOrderDetailColorDiffersFromModel(
                                item,
                                savedWindowModelMap(item['partitions_json']),
                              )) {
                            final jsonRaw = item['partitions_json'];
                            if (jsonRaw != null) {
                              try {
                                Map<String, dynamic> modelMap = {};
                                if (jsonRaw is Map<String, dynamic>) {
                                  modelMap = jsonRaw;
                                } else if (jsonRaw is Map) {
                                  modelMap = Map<String, dynamic>.from(jsonRaw);
                                } else {
                                  final str = jsonRaw.toString().trim();
                                  if (str.length >= 5) {
                                    modelMap =
                                        jsonDecode(str) as Map<String, dynamic>;
                                  }
                                }
                                if (modelMap.isNotEmpty) {
                                  final model = WindowModel(db: db);
                                  await applyWindowModelAndLoadCatalog(
                                    model,
                                    modelMap,
                                  );
                                  applyStoredOrderDetailColorToWindowModel(
                                    model,
                                    item,
                                  );
                                  final newPath = await saveWindowImageToDisk(
                                    model,
                                  );
                                  if (newPath.isNotEmpty) {
                                    await db.updateCommandeDetailImagePath(
                                      item['id'] as int,
                                      newPath,
                                    );
                                    item['drawing_image_path'] = newPath;
                                  }
                                }
                              } catch (err) {
                                debugPrint(
                                  'Error generating missing image: $err',
                                );
                              }
                            }
                          }
                        }

                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final devis = await DevisBuilder.build(
                          order: orderData,
                          items: items,
                          workshop: workshop,
                          hidePrices: true,
                          documentTitleKey: 'doc_bon_livraison_sans_prix',
                        );
                        _dismissHeavyLoadingDialog();
                        final orderId = orderData['id']?.toString() ?? '';
                        _openInWorkspaceTab(
                          entryId: 'bon_livraison_sans_prix_$orderId',
                          title: _documentTabTitle(
                            docType: 'bon_livraison',
                            orderData: orderData,
                            lang: lang,
                          ),
                          icon: Icons.print_disabled,
                          content: DevisPreviewScreen(data: devis),
                        );
                      } catch (e) {
                        _dismissHeavyLoadingDialog();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${_t('خطأ أثناء توليد الفاتورة')}: $e',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // Bon de livraison partiel
                if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.picture_as_pdf_outlined,
                      color: Colors.blue,
                    ),
                    title: Text(
                      Localization.translate(
                        'doc_bon_livraison_partiel_menu',
                        lang,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PartialProformaScreen(
                            order: orderData,
                            documentTitleKey: 'doc_bon_livraison_partiel',
                          ),
                        ),
                      );
                    },
                  ),

                // Bon de livraison partiel sans prix
                if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.print_disabled_outlined,
                      color: Colors.blueGrey,
                    ),
                    title: Text(
                      Localization.translate(
                        'doc_bon_livraison_partiel_sans_prix_menu',
                        lang,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PartialProformaScreen(
                            order: orderData,
                            hidePrices: true,
                            documentTitleKey:
                                'doc_bon_livraison_partiel_sans_prix',
                          ),
                        ),
                      );
                    },
                  ),

                // Bon de charge
                if (settings.canViewOrderDocuments() && isManufacturingOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.local_shipping,
                      color: Colors.teal,
                    ),
                    title: Text(
                      Localization.translate('doc_bon_charge_menu', lang),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);

                      final choice = await showDialog<String>(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: Row(
                            children: [
                              const Icon(
                                Icons.local_shipping,
                                color: Colors.teal,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                lang == AppLanguage.french
                                    ? 'Type de Bon d\'expédition'
                                    : 'نوع فاتورة الشحن',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(color: Colors.grey.shade300),
                                ),
                                leading: const Icon(
                                  Icons.inventory_2,
                                  color: Colors.blue,
                                ),
                                title: Text(
                                  lang == AppLanguage.french
                                      ? 'Expédition complète (Toutes les fenêtres)'
                                      : lang == AppLanguage.english
                                      ? 'Full Shipping (All windows)'
                                      : 'فاتورة شحن كلية (جميع النوافذ)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                ),
                                onTap: () => Navigator.pop(dialogCtx, 'FULL'),
                              ),
                              const SizedBox(height: 10),
                              ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(color: Colors.grey.shade300),
                                ),
                                leading: const Icon(
                                  Icons.local_shipping_outlined,
                                  color: Colors.orange,
                                ),
                                title: Text(
                                  lang == AppLanguage.french
                                      ? 'Expédition partielle (Par bon de livraison)'
                                      : lang == AppLanguage.english
                                      ? 'Partial Shipping (By delivery note)'
                                      : 'فاتورة شحن جزئية (حسب وصل الشحن الجزئي)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                ),
                                onTap: () =>
                                    Navigator.pop(dialogCtx, 'PARTIAL'),
                              ),
                            ],
                          ),
                        ),
                      );

                      if (choice == null) return;

                      if (choice == 'PARTIAL') {
                        final orderId = orderData['id'] as int;
                        final deliveries = await db.readCommandeDeliveries(
                          orderId,
                        );

                        if (deliveries.isEmpty) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                lang == AppLanguage.french
                                    ? 'Aucun bon d\'expédition partiel trouvé. Redirection...'
                                    : 'لا توجد وصولات شحن جزئية مسبقة! سيتم التوجيه لتحديد العناصر المراد شحنها.',
                                style: const TextStyle(fontFamily: 'Cairo'),
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PartialProformaScreen(
                                order: orderData,
                                hidePrices: true,
                                documentTitleKey: 'doc_bon_livraison_partiel',
                                autoOpenBonDeChargeOnSave: true,
                              ),
                            ),
                          );
                          return;
                        }

                        if (!mounted) return;
                        final selectedResult = await showModalBottomSheet<dynamic>(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                          ),
                          builder: (bottomSheetCtx) {
                            return Container(
                              padding: const EdgeInsets.all(16),
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.of(context).size.height * 0.7,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    lang == AppLanguage.french
                                        ? 'Sélectionner un Bon de livraison partiel'
                                        : 'اختر وصل تسليم جزئي للتحميل',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: deliveries.length,
                                      separatorBuilder: (_, _) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final del = deliveries[index];
                                        final isLoaded =
                                            (del['is_loaded'] == 1);
                                        List items = [];
                                        try {
                                          items = jsonDecode(del['items_json']);
                                        } catch (_) {}
                                        final itemCount = items.length;
                                        return ListTile(
                                          leading: Icon(
                                            isLoaded
                                                ? Icons.check_circle
                                                : Icons.local_shipping,
                                            color: isLoaded
                                                ? Colors.green
                                                : Colors.orange,
                                          ),
                                          title: Text(
                                            'وصل بتاريخ: ${del['delivery_date']}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                          subtitle: Text(
                                            'عدد القطع: $itemCount نافذة',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                          trailing: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isLoaded
                                                  ? Colors.green.shade100
                                                  : Colors.orange.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isLoaded
                                                  ? (lang == AppLanguage.french
                                                        ? 'Chargé'
                                                        : 'تم التحميل')
                                                  : (lang == AppLanguage.french
                                                        ? 'En attente'
                                                        : 'معلق'),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: isLoaded
                                                    ? Colors.green.shade900
                                                    : Colors.orange.shade900,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                          ),
                                          onTap: () {
                                            Navigator.pop(bottomSheetCtx, del);
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(bottomSheetCtx, {
                                        'action': 'NEW',
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.add,
                                      color: Colors.white,
                                    ),
                                    label: Text(
                                      lang == AppLanguage.french
                                          ? '+ Nouveau bon de livraison partiel'
                                          : '+ إنشاء توصيل جزئي جديد',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );

                        if (selectedResult == null) return;

                        if (selectedResult is Map &&
                            selectedResult['action'] == 'NEW') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PartialProformaScreen(
                                order: orderData,
                                hidePrices: true,
                                documentTitleKey: 'doc_bon_livraison_partiel',
                                autoOpenBonDeChargeOnSave: true,
                              ),
                            ),
                          );
                          return;
                        }

                        if (selectedResult is Map<String, dynamic>) {
                          await _showHeavyLoadingDialog(context, lang);
                          try {
                            final itemsJsonStr =
                                selectedResult['items_json']?.toString() ??
                                '[]';
                            final List<dynamic> rawDecoded = jsonDecode(
                              itemsJsonStr,
                            );
                            final List<Map<String, dynamic>> items = rawDecoded
                                .map((it) => Map<String, dynamic>.from(it))
                                .toList();

                            for (var item in items) {
                              final path =
                                  item['drawing_image_path']?.toString() ?? '';
                              if (path.isEmpty ||
                                  !File(path).existsSync() ||
                                  storedOrderDetailColorDiffersFromModel(
                                    item,
                                    savedWindowModelMap(
                                      item['partitions_json'],
                                    ),
                                  )) {
                                final jsonRaw = item['partitions_json'];
                                if (jsonRaw != null) {
                                  try {
                                    Map<String, dynamic> modelMap = {};
                                    if (jsonRaw is Map<String, dynamic>) {
                                      modelMap = jsonRaw;
                                    } else if (jsonRaw is Map) {
                                      modelMap = Map<String, dynamic>.from(
                                        jsonRaw,
                                      );
                                    } else {
                                      final str = jsonRaw.toString().trim();
                                      if (str.length >= 5) {
                                        modelMap =
                                            jsonDecode(str)
                                                as Map<String, dynamic>;
                                      }
                                    }
                                    if (modelMap.isNotEmpty) {
                                      final model = WindowModel(db: db);
                                      await applyWindowModelAndLoadCatalog(
                                        model,
                                        modelMap,
                                      );
                                      applyStoredOrderDetailColorToWindowModel(
                                        model,
                                        item,
                                      );
                                      final newPath =
                                          await saveWindowImageToDisk(model);
                                      if (newPath.isNotEmpty) {
                                        await db.updateCommandeDetailImagePath(
                                          item['id'] as int,
                                          newPath,
                                        );
                                        item['drawing_image_path'] = newPath;
                                      }
                                    }
                                  } catch (err) {
                                    debugPrint(
                                      'Error generating missing image: $err',
                                    );
                                  }
                                }
                              }
                            }

                            final workshop =
                                await DevisBuilder.loadWorkshopInfo();
                            final devis = await DevisBuilder.build(
                              order: orderData,
                              items: items,
                              workshop: workshop,
                              hidePrices: true,
                              documentTitleKey: 'BON_CHARGE',
                            );
                            _dismissHeavyLoadingDialog();
                            final orderId = orderData['id']?.toString() ?? '';
                            final delId =
                                selectedResult['id']?.toString() ?? '';
                            _openInWorkspaceTab(
                              entryId: 'delivery_${orderId}_$delId',
                              title: _documentTabTitle(
                                docType: 'bon_charge',
                                orderData: orderData,
                                lang: lang,
                              ),
                              icon: Icons.local_shipping_outlined,
                              content: DevisPreviewScreen(
                                data: devis,
                                deliveryId: selectedResult['id'] as int?,
                                initialIsLoaded:
                                    (selectedResult['is_loaded'] == 1),
                              ),
                            );
                          } catch (e) {
                            _dismissHeavyLoadingDialog();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${_t('خطأ أثناء توليد الفاتورة')}: $e',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                          return;
                        }
                      }

                      // Full loading flow (FULL)
                      await _showHeavyLoadingDialog(context, lang);
                      try {
                        final rawItems = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final List<Map<String, dynamic>> items = rawItems
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList();

                        for (var item in items) {
                          final path =
                              item['drawing_image_path']?.toString() ?? '';
                          if (path.isEmpty ||
                              !File(path).existsSync() ||
                              storedOrderDetailColorDiffersFromModel(
                                item,
                                savedWindowModelMap(item['partitions_json']),
                              )) {
                            final jsonRaw = item['partitions_json'];
                            if (jsonRaw != null) {
                              try {
                                Map<String, dynamic> modelMap = {};
                                if (jsonRaw is Map<String, dynamic>) {
                                  modelMap = jsonRaw;
                                } else if (jsonRaw is Map) {
                                  modelMap = Map<String, dynamic>.from(jsonRaw);
                                } else {
                                  final str = jsonRaw.toString().trim();
                                  if (str.length >= 5) {
                                    modelMap =
                                        jsonDecode(str) as Map<String, dynamic>;
                                  }
                                }
                                if (modelMap.isNotEmpty) {
                                  final model = WindowModel(db: db);
                                  await applyWindowModelAndLoadCatalog(
                                    model,
                                    modelMap,
                                  );
                                  applyStoredOrderDetailColorToWindowModel(
                                    model,
                                    item,
                                  );
                                  final newPath = await saveWindowImageToDisk(
                                    model,
                                  );
                                  if (newPath.isNotEmpty) {
                                    await db.updateCommandeDetailImagePath(
                                      item['id'] as int,
                                      newPath,
                                    );
                                    item['drawing_image_path'] = newPath;
                                  }
                                }
                              } catch (err) {
                                debugPrint(
                                  'Error generating missing image: $err',
                                );
                              }
                            }
                          }
                        }

                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final devis = await DevisBuilder.build(
                          order: orderData,
                          items: items,
                          workshop: workshop,
                          hidePrices: true,
                          documentTitleKey: 'BON_CHARGE',
                        );
                        _dismissHeavyLoadingDialog();
                        if (!mounted) return;
                        final orderId = orderData['id']?.toString() ?? '';
                        _openInWorkspaceTab(
                          entryId: 'bon_charge_$orderId',
                          title: _documentTabTitle(
                            docType: 'bon_charge',
                            orderData: orderData,
                            lang: lang,
                          ),
                          icon: Icons.local_shipping_outlined,
                          content: DevisPreviewScreen(data: devis),
                        );
                      } catch (e) {
                        _dismissHeavyLoadingDialog();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${_t('خطأ أثناء توليد الفاتورة')}: $e',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),
                if (isConfirmedOrBeyond) const Divider(),

                // 2. Fiche de Coupe
                ListTile(
                  leading: const Icon(
                    Icons.architecture_rounded,
                    color: Colors.indigo,
                  ),
                  title: Text(
                    Localization.translate(
                      'تحسين القص (Optimisation de Coupe)',
                      lang,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CuttingOptimizationScreen(
                          db: db,
                          initialOrderId: orderId,
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.dashboard_customize_rounded,
                    color: Colors.teal,
                  ),
                  title: Text(
                    lang == AppLanguage.french
                        ? 'Débit des Panneaux & Feuilles (2D)'
                        : 'تقطيع الألواح والصفائح (2D)',
                  ),
                  subtitle: Text(
                    lang == AppLanguage.french
                        ? 'Panneau sandwich, Résine, Alucobond, Plexiglas'
                        : 'بانو ساندويتش، ريزين، أليكوبوند، بيكسي جلاس',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SheetOptimizationScreen(
                          orderId: orderId,
                          orderName: _displayOrderLabel(orderData),
                        ),
                      ),
                    );
                  },
                ),
                if (settings.canViewFicheDeCoupe())
                  ListTile(
                    leading: const Icon(Icons.cut, color: Colors.orange),
                    title: Text(
                      Localization.translate(
                        'ورقة التقطيع (Fiche de Coupe)',
                        lang,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              Localization.translate(
                                'جاري تجهيز جدول التقطيع...',
                                lang,
                              ),
                            ),
                          ),
                        );
                      }
                      try {
                        final items = await db.readCommandeDetails(
                          orderData['id'],
                        );
                        final workshop = await DevisBuilder.loadWorkshopInfo();
                        final pdfBytes =
                            await PdfFicheCoupeApi.generateFicheCoupe(
                              order: orderData,
                              items: items,
                              workshopName: workshop.name,
                              db: db,
                              language: lang,
                            );
                        if (!mounted) return;
                        final orderId2 = orderData['id']?.toString() ?? '';
                        final num = _displayOrderNumber(orderData);
                        _openInWorkspaceTab(
                          entryId: 'fiche_coupe_$orderId2',
                          title: lang == AppLanguage.french
                              ? 'Fiche de coupe pour commande #$num — ${_orderClientName(orderData)}'
                              : (lang == AppLanguage.english
                                    ? 'Cutting sheet for order #$num — ${_orderClientName(orderData)}'
                                    : 'ورقة التقطيع للطلبية رقم $num — ${_orderClientName(orderData)}'),
                          icon: Icons.cut_outlined,
                          content: PdfPreview(
                            build: (_) async => pdfBytes,
                            canChangeOrientation: false,
                            canChangePageFormat: false,
                            canDebug: false,
                            pdfFileName: 'Fiche_Coupe_$num.pdf',
                          ),
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${Localization.translate('خطأ أثناء توليد الفاتورة:', lang)} $e',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // 3. Fiche de Consommation & المواد والسلع المطلوبة
                if (settings.canViewOrderMaterials()) ...[
                  ListTile(
                    leading: const Icon(
                      Icons.inventory_2,
                      color: Colors.indigo,
                    ),
                    title: Text(
                      Localization.translate('كمية السلع المطلوبة', lang),
                    ),
                    subtitle: Text(
                      Localization.translate(
                        'محسوبة من نفس جدول الكمية والتكلفة',
                        lang,
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      final ordId = orderData['id']?.toString() ?? '';
                      _openInWorkspaceTab(
                        entryId: 'required_goods_$ordId',
                        title:
                            '${Localization.translate('كمية السلع المطلوبة', lang)} #$ordId',
                        icon: Icons.inventory_2_outlined,
                        content: OrderRequiredGoodsScreen(
                          orderData: orderData,
                          db: db,
                        ),
                      );
                    },
                  ),
                ],

                // 3.8 تأكيد القياسات والملصقات
                if (settings.canConfirmMeasurements())
                  ListTile(
                    leading: const Icon(
                      Icons.line_weight_rounded,
                      color: Colors.indigoAccent,
                    ),
                    title: Text(
                      Localization.translate(
                        'تأكيد القياسات والملصقات (Stickers)',
                        lang,
                      ),
                    ),
                    subtitle: Text(
                      Localization.translate(
                        'تعديل القياسات الفعلية للموقع وطباعة الباركود لكل قطعة',
                        lang,
                      ),
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      final ordId = orderData['id']?.toString() ?? '';
                      _openInWorkspaceTab(
                        entryId: 'measurements_$ordId',
                        title:
                            '${Localization.translate('تأكيد القياسات', lang)} #$ordId',
                        icon: Icons.line_weight_rounded,
                        content: OrderMeasurementsConfirmScreen(
                          orderData: orderData,
                          db: db,
                        ),
                      );
                    },
                  ),

                // 3.8.1 طباعة ملصقات الباركود للعمال مسبقاً (مباشرة للورشة)
                ListTile(
                  leading: const Icon(
                    Icons.qr_code_2_rounded,
                    color: Colors.teal,
                  ),
                  title: Text(
                    lang == AppLanguage.french
                        ? 'Imprimer les étiquettes code-barres (Atelier)'
                        : 'طباعة ملصقات الباركود مسبقاً (عمال الورشة)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    lang == AppLanguage.french
                        ? 'Générer les étiquettes pour les ouvriers avant la découpe'
                        : 'طباعة ملصقات الباركود ولصقها على القطع قبل بداية القص والتجميع',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    final ordId = orderData['id']?.toString() ?? '';
                    _openInWorkspaceTab(
                      entryId: 'stickers_' + ordId,
                      title: ' #' + ordId,
                      icon: Icons.qr_code_2_rounded,
                      content: OrderMeasurementsConfirmScreen(
                        orderData: orderData,
                        db: db,
                      ),
                    );
                  },
                ),

                // 3.8.2 تثبيت موقع العميل على الخريطة وفتح خطة التوزيع
                ListTile(
                  leading: const Icon(
                    Icons.location_on_rounded,
                    color: Colors.redAccent,
                  ),
                  title: Text(
                    lang == AppLanguage.french
                        ? 'Localisation du client sur la carte (GPS)'
                        : 'تثبيت موقع العميل على الخريطة وتوزيع الطلبية',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    lang == AppLanguage.french
                        ? 'Pointer la position exacte du client et lancer l\'itinéraire'
                        : 'فتح الخريطة داخل التطبيق لتثبيت مكان العميل وتأكيد الموقع أو فتح Google Maps',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final clientName = _orderClientName(orderData);
                    final clientId = int.tryParse(
                      orderData['client_id']?.toString() ?? '',
                    );
                    double? initialLat = double.tryParse(
                      orderData['latitude']?.toString() ?? '',
                    );
                    double? initialLng = double.tryParse(
                      orderData['longitude']?.toString() ?? '',
                    );

                    final point = await Navigator.push<LatLng>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapPickerScreen(
                          initialLatitude: initialLat,
                          initialLongitude: initialLng,
                          clientName: clientName.isNotEmpty ? clientName : null,
                          title: lang == AppLanguage.french
                              ? 'Position client : ' + clientName
                              : 'تثبيت موقع الزبون : ' + clientName,
                        ),
                      ),
                    );

                    if (point != null && mounted) {
                      if (clientId != null && clientId > 0) {
                        await db.updateClientCoordinates(
                          clientId,
                          point.latitude,
                          point.longitude,
                        );
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              lang == AppLanguage.french
                                  ? 'Position du client enregistrée avec succès !'
                                  : 'تم حفظ وتثبيت موقع العميل بنجاح!',
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                        setState(() {
                          _data = db.readCommandesWithClients();
                        });
                      }
                    }
                  },
                ),

                // 3.9 توزيع المهام وإسناد العمل للعمال
                if (settings.canAllocateTasks() && !isDistributedOrBeyond)
                  ListTile(
                    leading: const Icon(
                      Icons.engineering_rounded,
                      color: Colors.purple,
                    ),
                    title: Text(
                      lang == AppLanguage.french
                          ? 'Affectation des tâches aux ouvriers'
                          : 'توزيع المهام على العمال (إسناد الورشة)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      lang == AppLanguage.french
                          ? 'Répartir la fabrication des éléments sur l\'équipe'
                          : 'توزيع النوافذ وتحديد أجر تصنيع كل عنصر للعمال',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      final ordId = orderData['id']?.toString() ?? '';
                      _openInWorkspaceTab(
                        entryId: 'allocation_$ordId',
                        title:
                            '${Localization.translate('توزيع المهام', lang)} #$ordId',
                        icon: Icons.engineering_rounded,
                        content: OrderAllocationScreen(
                          orderData: orderData,
                          db: db,
                        ),
                      );
                    },
                  ),

                const Divider(),

                // 4. Move to Next Stage (نقل إلى المرحلة التالية)
                if (settings.canPassNextStage())
                  ListTile(
                    leading: const Icon(
                      Icons.forward_rounded,
                      color: Colors.green,
                    ),
                    title: Text(
                      lang == AppLanguage.french
                          ? 'Passer à l\'étape suivante'
                          : 'نقل إلى المرحلة التالية',
                    ),
                    subtitle: Text(
                      lang == AppLanguage.french
                          ? 'Passer la commande de "${_translateStatus(currentStatus, lang)}" à l\'étape suivante'
                          : 'نقل الطلبية من حالة "${_translateStatus(currentStatus, lang)}" إلى المرحلة التي تليها',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      const stagesSequence = [
                        'Nouveau',
                        'Confirmed',
                        'Pending',
                        'In Progress',
                        'Partial Manufacturing',
                        'Full Manufacturing',
                        'Partial Distribution',
                        'Full Distribution',
                        'Installation',
                        'Reserve',
                        'Done',
                      ];

                      final sLow = currentStatus.trim().toLowerCase();
                      String normalizedStatus = currentStatus;
                      if (sLow == 'nouveau' ||
                          sLow == 'new' ||
                          sLow == 'draft' ||
                          sLow == 'جديد' ||
                          sLow == 'جديدة') {
                        normalizedStatus = 'Nouveau';
                      } else if (sLow.contains('confirm') ||
                          sLow.contains('مؤكد')) {
                        normalizedStatus = 'Confirmed';
                      } else if (sLow.contains('قياسات') ||
                          sLow == 'in progress' ||
                          sLow.contains('cours')) {
                        normalizedStatus = 'In Progress';
                      } else if (sLow.contains('attente') ||
                          sLow.contains('انتظار') ||
                          sLow == 'pending') {
                        normalizedStatus = 'Pending';
                      }

                      int currentIndex = stagesSequence.indexOf(
                        normalizedStatus,
                      );
                      if (currentIndex == -1) {
                        if (normalizedStatus.toLowerCase().contains(
                              'attente',
                            ) ||
                            normalizedStatus.toLowerCase().contains('انتظار')) {
                          currentIndex = 2;
                        } else if (normalizedStatus.toLowerCase().contains(
                          'confirm',
                        )) {
                          currentIndex = 1;
                        } else {
                          currentIndex = 0;
                        }
                      }

                      if (currentIndex < stagesSequence.length - 1) {
                        final nextStatus = stagesSequence[currentIndex + 1];

                        if (normalizedStatus == 'In Progress') {
                          if (!mounted) return;
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => PopScope(
                              canPop: false,
                              child: AlertDialog(
                                content: Row(
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        lang == AppLanguage.french
                                            ? 'Vérification des mesures…'
                                            : 'جاري التحقق من القياسات…',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                          await WidgetsBinding.instance.endOfFrame;
                          var allConfirmed = false;
                          Object? measurementCheckError;
                          try {
                            allConfirmed = await _areAllMeasurementsConfirmed(
                              orderData['id'],
                            ).timeout(const Duration(seconds: 15));
                          } catch (error) {
                            measurementCheckError = error;
                          } finally {
                            if (mounted) {
                              Navigator.of(context, rootNavigator: true).pop();
                            }
                          }
                          if (measurementCheckError != null) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    lang == AppLanguage.french
                                        ? 'Impossible de vérifier les mesures de cette commande.'
                                        : 'تعذر التحقق من قياسات هذه الطلبية. راجع بيانات القياسات ثم حاول مجددًا.',
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                            return;
                          }
                          if (!allConfirmed) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    lang == AppLanguage.french
                                        ? 'Impossible de passer à la fabrication sans valider les mesures !'
                                        : 'لا يمكن الانتقال للتصنيع إن لم تقم بتأكيد القياسات!',
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      OrderMeasurementsConfirmScreen(
                                        orderData: orderData,
                                        db: db,
                                      ),
                                ),
                              );
                            }
                            return;
                          }
                        }

                        if (nextStatus == 'Partial Manufacturing' ||
                            nextStatus == 'Full Manufacturing') {
                          final inventoryIssued = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OrderRequiredGoodsScreen(
                                orderData: orderData,
                                db: db,
                                issueAtManufacturingStart: true,
                              ),
                            ),
                          );
                          if (inventoryIssued != true || !mounted) return;
                        }

                        if (!mounted) return;
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => PopScope(
                            canPop: false,
                            child: AlertDialog(
                              content: Row(
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      lang == AppLanguage.french
                                          ? 'Mise à jour de la commande…'
                                          : 'جاري تحديث حالة الطلبية…',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        await WidgetsBinding.instance.endOfFrame;
                        Object? statusUpdateError;
                        try {
                          await db
                              .updateCommandeStatus(orderData['id'], nextStatus)
                              .timeout(const Duration(seconds: 30));
                        } catch (error) {
                          statusUpdateError = error;
                        } finally {
                          if (mounted) {
                            Navigator.of(context, rootNavigator: true).pop();
                          }
                        }

                        if (statusUpdateError != null) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  lang == AppLanguage.french
                                      ? 'Échec du passage à l’étape suivante. Veuillez réessayer.'
                                      : 'تعذر نقل الطلبية إلى المرحلة التالية. يرجى المحاولة مجددًا.',
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                          return;
                        }
                        if (!mounted) return;
                        setState(() {
                          _data = db.readCommandesWithClients();
                        });

                        if (nextStatus == 'In Progress') {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  lang == AppLanguage.french
                                      ? 'Commande passée à: Confirmation des mesures'
                                      : 'تم نقل الطلبية إلى مرحلة تأكيد القياسات. يرجى تأكيد المقاسات.',
                                ),
                                backgroundColor: Colors.indigo,
                              ),
                            );
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderMeasurementsConfirmScreen(
                                  orderData: orderData,
                                  db: db,
                                ),
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  lang == AppLanguage.french
                                      ? 'Commande passée à l\'étape: ${_translateStatus(nextStatus, lang)}'
                                      : 'تم نقل الطلبية بنجاح إلى مرحلة: ${_translateStatus(nextStatus, lang)}',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                lang == AppLanguage.french
                                    ? 'La commande est déjà dans la dernière étape (Done)!'
                                    : 'الطلبية وصلت بالفعل للمرحلة الأخيرة!',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      }
                    },
                  ),

                // 5. Change Status (تغيير الحالة المخصص يدوياً)
                if (settings.canChangeOrderStatus())
                  ListTile(
                    leading: const Icon(Icons.swap_horiz, color: Colors.blue),
                    title: Text(
                      Localization.translate('تغيير الحالة المخصص', lang),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showChangeStatusDialog(orderData);
                    },
                  ),

                // 6. Modification
                if (settings.canEditOrders())
                  ListTile(
                    leading: const Icon(Icons.edit, color: Colors.blue),
                    title: Text(Localization.translate("Edit Order", lang)),
                    onTap: () {
                      Navigator.pop(ctx);
                      openOrderInWorkspaceTab(
                        context,
                        db: db,
                        editCommandeId: (orderData['id'] as num?)?.toInt(),
                        onSaved: _fetchCommandes,
                      );
                    },
                  ),

                // NEW: 6.5 Duplicate
                if (settings.canDuplicateOrders())
                  ListTile(
                    leading: const Icon(Icons.copy, color: Colors.blueGrey),
                    title: Text(
                      Localization.translate('تكرار الطلبية (Duplicate)', lang),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        await _duplicateOrder(orderData);
                        setState(() {
                          _data = db.readCommandesWithClients();
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                Localization.translate(
                                  'تم تكرار الطلبية بنجاح!',
                                  lang,
                                ),
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${Localization.translate('حدث خطأ أثناء التكرار:', lang)} $e',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),

                const Divider(),

                // 7. Supprimer
                Consumer<AppSettingsProvider>(
                  builder: (ctx2, settings, _) {
                    if (!settings.canDeleteOrders()) {
                      return const SizedBox.shrink();
                    }
                    return ListTile(
                      leading: const Icon(
                        Icons.delete,
                        color: Colors.redAccent,
                      ),
                      title: Text(
                        Localization.translate('مسح الطلبية (Supprimer)', lang),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showDeleteConfirmDialog(orderData['id']);
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportOrderPicturePdf(
    BuildContext context,
    Map<String, dynamic> orderData,
    AppLanguage lang,
  ) async {
    if (!mounted || !context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _OrderPicturePdfPreviewPage(
          db: db,
          orderData: Map<String, dynamic>.from(orderData),
          lang: lang,
        ),
      ),
    );
  }

  Future<void> _exportOrderGlassFabricationPdf(
    BuildContext context,
    Map<String, dynamic> orderData,
    AppLanguage lang,
  ) async {
    final orderId = (orderData['id'] as num?)?.toInt() ?? 0;
    final details = await db.readCommandeDetails(orderId);
    final payloads = <Map<String, dynamic>>[];
    for (final d in details) {
      final partitionsJson = d['partitions_json'];
      if (partitionsJson != null) {
        try {
          final decoded = partitionsJson is Map
              ? Map<String, dynamic>.from(partitionsJson)
              : Map<String, dynamic>.from(
                  jsonDecode(partitionsJson.toString()),
                );
          if (decoded['isGlassWork'] == true ||
              decoded['glassWorkPayload'] != null ||
              (d['window_type']?.toString().contains('Verre Trempé') == true) ||
              (d['window_type']?.toString().contains('فير ترومبي') == true)) {
            final p = decoded['glassWorkPayload'] != null
                ? Map<String, dynamic>.from(decoded['glassWorkPayload'])
                : decoded;
            p['itemTitle'] = d['window_type']?.toString() ?? 'Verre trempé';
            payloads.add(p);
          }
        } catch (_) {}
      }
    }
    if (!mounted || !context.mounted) return;
    if (payloads.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(
              'لا توجد عناصر زجاج مقسى في هذه الطلبية',
              lang,
            ),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final clientName =
        '${orderData['firstname'] ?? ''} ${orderData['lastname'] ?? ''}'.trim();
    final clientPhone = orderData['phone']?.toString() ?? '';
    final orderNumber = orderData['id']?.toString() ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GlassFabricationPreviewScreen(
          payloads: payloads,
          clientName: clientName,
          clientPhone: clientPhone,
          orderNumber: orderNumber,
        ),
      ),
    );
  }

  void _openOrderDetails(Map<String, dynamic> orderData) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OrderMeasurementsDetailsScreen(orderData: orderData, db: db),
      ),
    );
  }

  Future<void> _openOrderDevis(
    Map<String, dynamic> orderData,
    AppLanguage lang,
  ) async {
    await _showHeavyLoadingDialog(context, lang);
    try {
      final rawItems = await db
          .readCommandeDetails(orderData['id'])
          .timeout(const Duration(seconds: 10));
      final List<Map<String, dynamic>> itemsList = rawItems
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      await _restoreDocumentImagesFromStoredBytes(itemsList);
      final workshop = await DevisBuilder.loadWorkshopInfo().timeout(
        const Duration(seconds: 6),
      );
      final devis = await DevisBuilder.build(
        order: orderData,
        items: itemsList,
        workshop: workshop,
        documentTitleKey: 'doc_devis',
      ).timeout(const Duration(seconds: 10));
      _dismissHeavyLoadingDialog();
      if (!mounted) return;
      final oId = orderData['id']?.toString() ?? '';
      _openInWorkspaceTab(
        entryId: 'devis_$oId',
        title: _documentTabTitle(
          docType: 'devis',
          orderData: orderData,
          lang: lang,
        ),
        icon: Icons.description_outlined,
        content: DevisPreviewScreen(data: devis),
      );
    } catch (e) {
      _dismissHeavyLoadingDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_t('خطأ أثناء توليد الفاتورة')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showOrderContextMenu(
    BuildContext context,
    Map<String, dynamic> order,
    Offset position,
    AppLanguage lang,
  ) async {
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final orderId = (order['id'] as num?)?.toInt() ?? 0;
    Map<String, dynamic> orderData = Map<String, dynamic>.from(order);
    if (orderId > 0) {
      final freshOrder = await db.readCommandeWithClientById(orderId);
      if (freshOrder != null) {
        orderData = {...orderData, ...freshOrder};
      }
    }
    final isFullyManufactured = await db.isOrderFullyManufactured(orderId);
    if (!mounted) return;

    final currentStatus = orderData['status']?.toString() ?? 'Pending';
    final statusRaw = (orderData['status']?.toString() ?? '')
        .trim()
        .toLowerCase();
    final isPending =
        statusRaw == 'nouveau' ||
        statusRaw == 'جديد' ||
        statusRaw == 'جديدة' ||
        statusRaw == 'en attente' ||
        statusRaw == 'في الانتظار' ||
        statusRaw == 'pending' ||
        statusRaw == 'draft' ||
        statusRaw == 'new' ||
        statusRaw == 'en_attente';
    final isConfirmedOrBeyond = !isPending;
    final isManufacturingOrBeyond =
        isConfirmedOrBeyond &&
        statusRaw != 'confirmed' &&
        statusRaw != 'مؤكدة' &&
        statusRaw != 'مؤكد';
    final isDistributedOrBeyond =
        isFullyManufactured ||
        statusRaw.contains('full manufacturing') ||
        statusRaw.contains('تصنيع كلي') ||
        statusRaw.contains('distribution') ||
        statusRaw.contains('توزيع') ||
        statusRaw.contains('installation') ||
        statusRaw.contains('تركيب') ||
        statusRaw.contains('reserve') ||
        statusRaw.contains('تحفظ') ||
        statusRaw.contains('done') ||
        statusRaw.contains('انتهاء') ||
        statusRaw.contains('منتهية');

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shortcuts = ShortcutBindings.instance;
    String? _getShortcutBadgeText(String commandId) {
      final binding = shortcuts.bindings[commandId];
      if (binding == null || binding.isEmpty || binding == 'none') return null;
      final lbl = ShortcutBindings.label(binding);
      return lbl == '—' ? null : lbl;
    }

    PopupMenuItem<String> _menuItem(
      String value,
      IconData icon,
      Color color,
      String title, {
      Color? textColor,
      String? shortcut,
    }) {
      return PopupMenuItem<String>(
        value: value,
        height: 38,
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (shortcut != null && shortcut.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2D3748)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF4A5568)
                        : const Color(0xFFCBD5E1),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      offset: const Offset(0, 1),
                      blurRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  shortcut,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final items = <PopupMenuEntry<String>>[
      _menuItem(
        isOrderPinned(orderData) ? 'unpin' : 'pin',
        isOrderPinned(orderData)
            ? Icons.push_pin_outlined
            : Icons.push_pin_rounded,
        Colors.orange.shade700,
        isOrderPinned(orderData)
            ? (lang == AppLanguage.french
                  ? 'Désépingler la commande'
                  : 'إلغاء تثبيت الطلبية')
            : (lang == AppLanguage.french
                  ? 'Épingler la commande en haut'
                  : 'تثبيت الطلبية في الأعلى'),
      ),
      const PopupMenuDivider(height: 8),
      // تفاصيل الطلبية
      _menuItem(
        'details',
        Icons.list_alt_outlined,
        Colors.blueGrey,
        lang == AppLanguage.arabic
            ? 'تفاصيل الطلبية والقياسات'
            : (lang == AppLanguage.french
                  ? 'Détails de la commande'
                  : 'Order Details'),
        shortcut: _getShortcutBadgeText('details_order'),
      ),
      const PopupMenuDivider(height: 8),

      // 1. تسعيرة (Devis)
      _menuItem(
        'devis',
        Icons.picture_as_pdf,
        Colors.red,
        Localization.translate('doc_devis_menu', lang),
        shortcut: _getShortcutBadgeText('devis_order'),
      ),

      // 1.1 صور النوافذ (Picture)
      if (settings.canViewOrderDocuments())
        _menuItem(
          'picture',
          Icons.photo_library_outlined,
          Colors.deepPurple,
          Localization.translate('Picture', lang),
        ),

      // 1.2 إضافة دفعة (Paiement)
      if (isConfirmedOrBeyond &&
          (settings.canEditPayments() || settings.canAccessTreasury()))
        _menuItem(
          'payment',
          Icons.payments_outlined,
          Colors.green,
          Localization.translate('Add payment', lang),
        ),

      // 1.3 فاتورة رسمية / أولية (Proforma)
      if (settings.canViewOrderDocuments())
        _menuItem(
          'proforma',
          Icons.description,
          Colors.indigo,
          Localization.translate('فاتورة رسمية / أولية', lang),
        ),

      // 1.4 فاتورة بيع (Facture de Vente)
      if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
        _menuItem(
          'facture',
          Icons.receipt_rounded,
          Colors.green,
          lang == AppLanguage.french
              ? 'Facture de Vente'
              : 'فاتورة بيع / Facture de Vente',
        ),

      // 1.5 بون دو روت (Bon de Route)
      if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
        _menuItem(
          'bon_route',
          Icons.directions_car_outlined,
          Colors.blueAccent,
          lang == AppLanguage.french
              ? 'Bon de Route'
              : 'بون دو روت / Bon de Route',
        ),

      // 1.6 وصل التسليم (Bon de livraison)
      if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
        _menuItem(
          'bon_livraison',
          Icons.assignment,
          Colors.blue,
          Localization.translate('doc_bon_livraison_menu', lang),
        ),

      // 1.7 وصل التسليم بدون أسعار
      if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
        _menuItem(
          'bon_livraison_sans_prix',
          Icons.print_disabled,
          Colors.blueGrey,
          Localization.translate('doc_bon_livraison_sans_prix_menu', lang),
        ),

      // 1.8 وصل التسليم الجزئي
      if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
        _menuItem(
          'bon_livraison_partiel',
          Icons.picture_as_pdf_outlined,
          Colors.blue,
          Localization.translate('doc_bon_livraison_partiel_menu', lang),
        ),

      // 1.9 وصل التسليم الجزئي بدون أسعار
      if (settings.canViewOrderDocuments() && isConfirmedOrBeyond)
        _menuItem(
          'bon_livraison_partiel_sans_prix',
          Icons.print_disabled_outlined,
          Colors.blueGrey,
          Localization.translate(
            'doc_bon_livraison_partiel_sans_prix_menu',
            lang,
          ),
        ),

      // 1.10 وصل الشحن (Bon de charge)
      if (settings.canViewOrderDocuments() && isManufacturingOrBeyond)
        _menuItem(
          'bon_charge',
          Icons.local_shipping,
          Colors.teal,
          Localization.translate('doc_bon_charge_menu', lang),
        ),

      const PopupMenuDivider(height: 8),

      // 2. تحسين القص (Optimisation de Coupe)
      _menuItem(
        'optimisation',
        Icons.architecture_rounded,
        Colors.indigo,
        Localization.translate('تحسين القص (Optimisation de Coupe)', lang),
      ),

      // 2.05 تقطيع الألواح والصفائح (2D)
      _menuItem(
        'sheet_optimisation',
        Icons.dashboard_customize_rounded,
        Colors.teal,
        lang == AppLanguage.french
            ? 'Débit des Panneaux (2D)'
            : 'تقطيع الألواح والصفائح (2D)',
      ),

      // 2.1 ورقة التقطيع (Fiche de Coupe)
      if (settings.canViewFicheDeCoupe())
        _menuItem(
          'fiche_coupe',
          Icons.cut,
          Colors.orange,
          Localization.translate('ورقة التقطيع (Fiche de Coupe)', lang),
        ),

      // 3. كمية السلع والمواد المطلوبة (Fiche de Consommation)
      if (settings.canViewOrderMaterials())
        _menuItem(
          'required_goods',
          Icons.inventory_2,
          Colors.indigo,
          Localization.translate('كمية السلع المطلوبة', lang),
        ),

      // 3.8 تأكيد القياسات والملصقات (Stickers)
      if (settings.canConfirmMeasurements())
        _menuItem(
          'measurements',
          Icons.line_weight_rounded,
          Colors.indigoAccent,
          Localization.translate('تأكيد القياسات والملصقات (Stickers)', lang),
        ),

      // 3.9 توزيع المهام على العمال (إسناد الورشة)
      if (settings.canAllocateTasks() && !isDistributedOrBeyond)
        _menuItem(
          'allocate',
          Icons.engineering_rounded,
          Colors.purple,
          Localization.translate(
            'توزيع المهام على العمال (إسناد الورشة)',
            lang,
          ),
        ),
      const PopupMenuDivider(height: 8),
      // 4. نقل إلى المرحلة التالية (Passer à l'étape suivante)
      if (settings.canPassNextStage())
        _menuItem(
          'next_stage',
          Icons.forward_rounded,
          Colors.green,
          lang == AppLanguage.french
              ? 'Passer à l\'étape suivante'
              : 'نقل إلى المرحلة التالية',
        ),

      // 5. تغيير الحالة المخصص يدوياً
      if (settings.canChangeOrderStatus())
        _menuItem(
          'status',
          Icons.swap_horiz,
          Colors.blue,
          Localization.translate('تغيير الحالة المخصص', lang),
        ),

      // 6. تعديل الطلبية (Modification)
      if (settings.canEditOrders())
        _menuItem(
          'edit',
          Icons.edit,
          Colors.blue,
          Localization.translate('Edit Order', lang),
          shortcut: _getShortcutBadgeText('edit_order'),
        ),

      // 6.5 تكرار الطلبية (Duplicate)
      if (settings.canDuplicateOrders())
        _menuItem(
          'duplicate',
          Icons.copy,
          Colors.blueGrey,
          Localization.translate('تكرار الطلبية (Duplicate)', lang),
        ),

      // تصدير الطلبية (Export)
      _menuItem(
        'export',
        Icons.ios_share,
        Colors.blueAccent,
        Localization.translate('export_order', lang),
      ),

      // 7. مسح الطلبية (Supprimer)
      if (settings.canDeleteOrders()) ...[
        const PopupMenuDivider(height: 8),
        _menuItem(
          'delete',
          Icons.delete,
          Colors.redAccent,
          Localization.translate('مسح الطلبية (Supprimer)', lang),
          textColor: Colors.red,
          shortcut: _getShortcutBadgeText('delete_order'),
        ),
      ],
    ];

    final selected = await showDesktopContextMenu<String>(
      context: context,
      globalPosition: position,
      items: items,
    );

    if (!mounted || selected == null) return;
    switch (selected) {
      case 'pin':
      case 'unpin':
        await _toggleOrderPin(orderData);
      case 'details':
        _openOrderDetails(orderData);
      case 'devis':
        await _openOrderDevis(orderData, lang);
      case 'picture':
        _exportOrderPicturePdf(context, orderData, lang);
      case 'payment':
        _showAddOrderPaymentDialog(orderData, lang);
      case 'proforma':
        await _showHeavyLoadingDialog(context, lang);
        try {
          final rawItems = await db.readCommandeDetails(orderData['id']);
          final List<Map<String, dynamic>> itemsList = rawItems
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          final workshop = await DevisBuilder.loadWorkshopInfo();
          final devis = await DevisBuilder.build(
            order: orderData,
            items: itemsList,
            workshop: workshop,
            isProForma: true,
          );
          _dismissHeavyLoadingDialog();
          if (!mounted) return;
          final oId = orderData['id']?.toString() ?? '';
          _openInWorkspaceTab(
            entryId: 'proforma_$oId',
            title: _documentTabTitle(
              docType: 'proforma',
              orderData: orderData,
              lang: lang,
            ),
            icon: Icons.description,
            content: DevisPreviewScreen(data: devis),
          );
        } catch (e) {
          _dismissHeavyLoadingDialog();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${_t('خطأ أثناء توليد الفاتورة')}: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      case 'facture':
        await _showHeavyLoadingDialog(context, lang);
        try {
          final rawItems = await db.readCommandeDetails(orderData['id']);
          final List<Map<String, dynamic>> itemsList = rawItems
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          final workshop = await DevisBuilder.loadWorkshopInfo();
          final devis = await DevisBuilder.build(
            order: orderData,
            items: itemsList,
            workshop: workshop,
            isProForma: false,
            documentTitleKey: 'FACTURE_VENTE',
          );
          _dismissHeavyLoadingDialog();
          if (!mounted) return;
          final oId = orderData['id']?.toString() ?? '';
          _openInWorkspaceTab(
            entryId: 'facture_$oId',
            title: _documentTabTitle(
              docType: 'facture',
              orderData: orderData,
              lang: lang,
            ),
            icon: Icons.receipt_rounded,
            content: DevisPreviewScreen(data: devis),
          );
        } catch (e) {
          _dismissHeavyLoadingDialog();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${_t('خطأ أثناء توليد الفاتورة')}: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      case 'bon_route':
        await _showHeavyLoadingDialog(context, lang);
        try {
          final rawItems = await db.readCommandeDetails(orderData['id']);
          final List<Map<String, dynamic>> itemsList = rawItems
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          final workshop = await DevisBuilder.loadWorkshopInfo();
          final devis = await DevisBuilder.build(
            order: orderData,
            items: itemsList,
            workshop: workshop,
            isProForma: false,
            documentTitleKey: 'BON_ROUTE',
          );
          _dismissHeavyLoadingDialog();
          if (!mounted) return;
          final oId = orderData['id']?.toString() ?? '';
          _openInWorkspaceTab(
            entryId: 'bon_route_$oId',
            title: _documentTabTitle(
              docType: 'bon_route',
              orderData: orderData,
              lang: lang,
            ),
            icon: Icons.directions_car_outlined,
            content: DevisPreviewScreen(data: devis),
          );
        } catch (e) {
          _dismissHeavyLoadingDialog();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${_t('خطأ أثناء توليد المستند')}: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      case 'bon_livraison':
        await _showHeavyLoadingDialog(context, lang);
        try {
          final rawItems = await db.readCommandeDetails(orderData['id']);
          final List<Map<String, dynamic>> itemsList = rawItems
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          for (var item in itemsList) {
            final path = item['drawing_image_path']?.toString() ?? '';
            if (path.isEmpty ||
                !File(path).existsSync() ||
                storedOrderDetailColorDiffersFromModel(
                  item,
                  savedWindowModelMap(item['partitions_json']),
                )) {
              final jsonRaw = item['partitions_json'];
              if (jsonRaw != null) {
                try {
                  Map<String, dynamic> modelMap = {};
                  if (jsonRaw is Map<String, dynamic>) {
                    modelMap = jsonRaw;
                  } else if (jsonRaw is Map) {
                    modelMap = Map<String, dynamic>.from(jsonRaw);
                  } else {
                    final str = jsonRaw.toString().trim();
                    if (str.length >= 5) {
                      modelMap = jsonDecode(str) as Map<String, dynamic>;
                    }
                  }
                  if (modelMap.isNotEmpty) {
                    final model = WindowModel(db: db);
                    await applyWindowModelAndLoadCatalog(model, modelMap);
                    applyStoredOrderDetailColorToWindowModel(model, item);
                    final newPath = await saveWindowImageToDisk(model);
                    if (newPath.isNotEmpty) {
                      await db.updateCommandeDetailImagePath(
                        item['id'] as int,
                        newPath,
                      );
                      item['drawing_image_path'] = newPath;
                    }
                  }
                } catch (err) {
                  debugPrint('Error generating missing image: $err');
                }
              }
            }
          }
          final workshop = await DevisBuilder.loadWorkshopInfo();
          final devis = await DevisBuilder.build(
            order: orderData,
            items: itemsList,
            workshop: workshop,
            hidePrices: false,
            documentTitleKey: 'doc_bon_livraison',
          );
          _dismissHeavyLoadingDialog();
          if (!mounted) return;
          final oId = orderData['id']?.toString() ?? '';
          _openInWorkspaceTab(
            entryId: 'bon_livraison_$oId',
            title: _documentTabTitle(
              docType: 'bon_livraison',
              orderData: orderData,
              lang: lang,
            ),
            icon: Icons.local_shipping_outlined,
            content: DevisPreviewScreen(data: devis),
          );
        } catch (e) {
          _dismissHeavyLoadingDialog();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${_t('خطأ أثناء توليد الفاتورة')}: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      case 'bon_livraison_sans_prix':
        await _showHeavyLoadingDialog(context, lang);
        try {
          final rawItems = await db.readCommandeDetails(orderData['id']);
          final List<Map<String, dynamic>> itemsList = rawItems
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          for (var item in itemsList) {
            final path = item['drawing_image_path']?.toString() ?? '';
            if (path.isEmpty ||
                !File(path).existsSync() ||
                storedOrderDetailColorDiffersFromModel(
                  item,
                  savedWindowModelMap(item['partitions_json']),
                )) {
              final jsonRaw = item['partitions_json'];
              if (jsonRaw != null) {
                try {
                  Map<String, dynamic> modelMap = {};
                  if (jsonRaw is Map<String, dynamic>) {
                    modelMap = jsonRaw;
                  } else if (jsonRaw is Map) {
                    modelMap = Map<String, dynamic>.from(jsonRaw);
                  } else {
                    final str = jsonRaw.toString().trim();
                    if (str.length >= 5) {
                      modelMap = jsonDecode(str) as Map<String, dynamic>;
                    }
                  }
                  if (modelMap.isNotEmpty) {
                    final model = WindowModel(db: db);
                    await applyWindowModelAndLoadCatalog(model, modelMap);
                    applyStoredOrderDetailColorToWindowModel(model, item);
                    final newPath = await saveWindowImageToDisk(model);
                    if (newPath.isNotEmpty) {
                      await db.updateCommandeDetailImagePath(
                        item['id'] as int,
                        newPath,
                      );
                      item['drawing_image_path'] = newPath;
                    }
                  }
                } catch (err) {
                  debugPrint('Error generating missing image: $err');
                }
              }
            }
          }
          final workshop = await DevisBuilder.loadWorkshopInfo();
          final devis = await DevisBuilder.build(
            order: orderData,
            items: itemsList,
            workshop: workshop,
            hidePrices: true,
            documentTitleKey: 'doc_bon_livraison_sans_prix',
          );
          _dismissHeavyLoadingDialog();
          if (!mounted) return;
          final oId = orderData['id']?.toString() ?? '';
          _openInWorkspaceTab(
            entryId: 'bon_livraison_sans_prix_$oId',
            title: _documentTabTitle(
              docType: 'bon_livraison',
              orderData: orderData,
              lang: lang,
            ),
            icon: Icons.print_disabled,
            content: DevisPreviewScreen(data: devis),
          );
        } catch (e) {
          _dismissHeavyLoadingDialog();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${_t('خطأ أثناء توليد الفاتورة')}: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      case 'bon_livraison_partiel':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PartialProformaScreen(
              order: orderData,
              documentTitleKey: 'doc_bon_livraison_partiel',
            ),
          ),
        );
      case 'bon_livraison_partiel_sans_prix':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PartialProformaScreen(
              order: orderData,
              hidePrices: true,
              documentTitleKey: 'doc_bon_livraison_partiel_sans_prix',
            ),
          ),
        );
      case 'bon_charge':
        final choice = await showDialog<String>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(Icons.local_shipping, color: Colors.teal),
                const SizedBox(width: 8),
                Text(
                  lang == AppLanguage.french
                      ? 'Type de Bon d\'expédition'
                      : 'نوع فاتورة الشحن',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  leading: const Icon(Icons.inventory_2, color: Colors.blue),
                  title: Text(
                    lang == AppLanguage.french
                        ? 'Expédition complète (Toutes les fenêtres)'
                        : lang == AppLanguage.english
                        ? 'Full Shipping (All windows)'
                        : 'فاتورة شحن كلية (جميع النوافذ)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 13,
                    ),
                  ),
                  onTap: () => Navigator.pop(dialogCtx, 'FULL'),
                ),
                const SizedBox(height: 10),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  leading: const Icon(
                    Icons.local_shipping_outlined,
                    color: Colors.orange,
                  ),
                  title: Text(
                    lang == AppLanguage.french
                        ? 'Expédition partielle (Par bon de livraison)'
                        : lang == AppLanguage.english
                        ? 'Partial Shipping (By delivery note)'
                        : 'فاتورة شحن جزئية (حسب وصل الشحن الجزئي)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 13,
                    ),
                  ),
                  onTap: () => Navigator.pop(dialogCtx, 'PARTIAL'),
                ),
              ],
            ),
          ),
        );
        if (choice == null || !mounted) return;
        if (choice == 'PARTIAL') {
          final oId = orderData['id'] as int;
          final deliveries = await db.readCommandeDeliveries(oId);
          if (deliveries.isEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  lang == AppLanguage.french
                      ? 'Aucun bon d\'expédition partiel trouvé. Redirection...'
                      : 'لا توجد وصولات شحن جزئية مسبقة! سيتم التوجيه لتحديد العناصر المراد شحنها.',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
                backgroundColor: Colors.orange,
              ),
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PartialProformaScreen(
                  order: orderData,
                  hidePrices: true,
                  documentTitleKey: 'doc_bon_livraison_partiel',
                  autoOpenBonDeChargeOnSave: true,
                ),
              ),
            );
            return;
          }
          if (!mounted) return;
          final selectedResult = await showModalBottomSheet<dynamic>(
            context: context,
            isScrollControlled: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            builder: (bottomSheetCtx) {
              return Container(
                padding: const EdgeInsets.all(16),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      lang == AppLanguage.french
                          ? 'Sélectionner un Bon de livraison partiel'
                          : 'اختر وصل تسليم جزئي للتحميل',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: deliveries.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final del = deliveries[index];
                          final isLoaded = (del['is_loaded'] == 1);
                          List itemsList = [];
                          try {
                            itemsList = jsonDecode(del['items_json']);
                          } catch (_) {}
                          final itemCount = itemsList.length;
                          return ListTile(
                            leading: Icon(
                              isLoaded
                                  ? Icons.check_circle
                                  : Icons.local_shipping,
                              color: isLoaded ? Colors.green : Colors.orange,
                            ),
                            title: Text(
                              'وصل بتاريخ: ${del['delivery_date']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            subtitle: Text(
                              'عدد القطع: $itemCount نافذة',
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isLoaded
                                    ? Colors.green.shade100
                                    : Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isLoaded
                                    ? (lang == AppLanguage.french
                                          ? 'Chargé'
                                          : 'تم التحميل')
                                    : (lang == AppLanguage.french
                                          ? 'En attente'
                                          : 'معلق'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isLoaded
                                      ? Colors.green.shade900
                                      : Colors.orange.shade900,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            onTap: () => Navigator.pop(bottomSheetCtx, del),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () =>
                          Navigator.pop(bottomSheetCtx, {'action': 'NEW'}),
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: Text(
                        lang == AppLanguage.french
                            ? '+ Nouveau bon de livraison partiel'
                            : '+ إنشاء توصيل جزئي جديد',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
          if (selectedResult == null) return;
          if (selectedResult is Map && selectedResult['action'] == 'NEW') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PartialProformaScreen(
                  order: orderData,
                  hidePrices: true,
                  documentTitleKey: 'doc_bon_livraison_partiel',
                  autoOpenBonDeChargeOnSave: true,
                ),
              ),
            );
            return;
          }
          if (selectedResult is Map<String, dynamic>) {
            await _showHeavyLoadingDialog(context, lang);
            try {
              final itemsJsonStr =
                  selectedResult['items_json']?.toString() ?? '[]';
              final List<dynamic> rawDecoded = jsonDecode(itemsJsonStr);
              final List<Map<String, dynamic>> itemsList = rawDecoded
                  .map((it) => Map<String, dynamic>.from(it))
                  .toList();
              final workshop = await DevisBuilder.loadWorkshopInfo();
              final devis = await DevisBuilder.build(
                order: orderData,
                items: itemsList,
                workshop: workshop,
                hidePrices: true,
                documentTitleKey: 'BON_CHARGE',
              );
              _dismissHeavyLoadingDialog();
              final oId = orderData['id']?.toString() ?? '';
              final delId = selectedResult['id']?.toString() ?? '';
              _openInWorkspaceTab(
                entryId: 'delivery_${oId}_$delId',
                title: _documentTabTitle(
                  docType: 'bon_charge',
                  orderData: orderData,
                  lang: lang,
                ),
                icon: Icons.local_shipping_outlined,
                content: DevisPreviewScreen(
                  data: devis,
                  deliveryId: selectedResult['id'] as int?,
                  initialIsLoaded: (selectedResult['is_loaded'] == 1),
                ),
              );
            } catch (e) {
              _dismissHeavyLoadingDialog();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${_t('خطأ أثناء توليد الفاتورة')}: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }
          return;
        }
        // FULL shipping
        await _showHeavyLoadingDialog(context, lang);
        try {
          final rawItems = await db.readCommandeDetails(orderData['id']);
          final List<Map<String, dynamic>> itemsList = rawItems
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          final workshop = await DevisBuilder.loadWorkshopInfo();
          final devis = await DevisBuilder.build(
            order: orderData,
            items: itemsList,
            workshop: workshop,
            hidePrices: true,
            documentTitleKey: 'BON_CHARGE',
          );
          _dismissHeavyLoadingDialog();
          if (!mounted) return;
          final oId = orderData['id']?.toString() ?? '';
          _openInWorkspaceTab(
            entryId: 'bon_charge_$oId',
            title: _documentTabTitle(
              docType: 'bon_charge',
              orderData: orderData,
              lang: lang,
            ),
            icon: Icons.local_shipping_outlined,
            content: DevisPreviewScreen(data: devis),
          );
        } catch (e) {
          _dismissHeavyLoadingDialog();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${_t('خطأ أثناء توليد الفاتورة')}: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      case 'optimisation':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CuttingOptimizationScreen(db: db, initialOrderId: orderId),
          ),
        );
      case 'sheet_optimisation':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SheetOptimizationScreen(
              orderId: orderId,
              orderName: _displayOrderLabel(orderData),
            ),
          ),
        );
      case 'fiche_coupe':
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                Localization.translate('جاري تجهيز جدول التقطيع...', lang),
              ),
            ),
          );
        }
        try {
          final itemsList = await db.readCommandeDetails(orderData['id']);
          final workshop = await DevisBuilder.loadWorkshopInfo();
          final pdfBytes = await PdfFicheCoupeApi.generateFicheCoupe(
            order: orderData,
            items: itemsList,
            workshopName: workshop.name,
            db: db,
            language: lang,
          );
          if (!mounted) return;
          final oId = orderData['id']?.toString() ?? '';
          final numStr = _displayOrderNumber(orderData);
          _openInWorkspaceTab(
            entryId: 'fiche_coupe_$oId',
            title: lang == AppLanguage.french
                ? 'Fiche de coupe pour commande #$numStr — ${_orderClientName(orderData)}'
                : (lang == AppLanguage.english
                      ? 'Cutting sheet for order #$numStr — ${_orderClientName(orderData)}'
                      : 'ورقة التقطيع للطلبية رقم $numStr — ${_orderClientName(orderData)}'),
            icon: Icons.cut_outlined,
            content: PdfPreview(
              build: (_) async => pdfBytes,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              pdfFileName: 'Fiche_Coupe_$numStr.pdf',
            ),
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${Localization.translate('خطأ أثناء توليد الفاتورة:', lang)} $e',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      case 'required_goods':
        final ordId = orderData['id']?.toString() ?? '';
        _openInWorkspaceTab(
          entryId: 'required_goods_$ordId',
          title:
              '${Localization.translate('كمية السلع المطلوبة', lang)} #$ordId',
          icon: Icons.inventory_2_outlined,
          content: OrderRequiredGoodsScreen(orderData: orderData, db: db),
        );
      case 'measurements':
        final ordId = orderData['id']?.toString() ?? '';
        _openInWorkspaceTab(
          entryId: 'measurements_$ordId',
          title: '${Localization.translate('تأكيد القياسات', lang)} #$ordId',
          icon: Icons.line_weight_rounded,
          content: OrderMeasurementsConfirmScreen(orderData: orderData, db: db),
        );
      case 'allocate':
        final ordId = orderData['id']?.toString() ?? '';
        _openInWorkspaceTab(
          entryId: 'allocation_$ordId',
          title: '${Localization.translate('توزيع المهام', lang)} #$ordId',
          icon: Icons.engineering_rounded,
          content: OrderAllocationScreen(orderData: orderData, db: db),
        );
      case 'next_stage':
        const stagesSequence = [
          'Nouveau',
          'Confirmed',
          'Pending',
          'In Progress',
          'Partial Manufacturing',
          'Full Manufacturing',
          'Partial Distribution',
          'Full Distribution',
          'Installation',
          'Reserve',
          'Done',
        ];
        final sLow = currentStatus.trim().toLowerCase();
        String normalizedStatus = currentStatus;
        if (sLow == 'nouveau' ||
            sLow == 'new' ||
            sLow == 'draft' ||
            sLow == 'جديد' ||
            sLow == 'جديدة') {
          normalizedStatus = 'Nouveau';
        } else if (sLow.contains('confirm') || sLow.contains('مؤكد')) {
          normalizedStatus = 'Confirmed';
        } else if (sLow.contains('قياسات') ||
            sLow == 'in progress' ||
            sLow.contains('cours')) {
          normalizedStatus = 'In Progress';
        } else if (sLow.contains('attente') ||
            sLow.contains('انتظار') ||
            sLow == 'pending') {
          normalizedStatus = 'Pending';
        }
        int currentIndex = stagesSequence.indexOf(normalizedStatus);
        if (currentIndex == -1) {
          if (normalizedStatus.toLowerCase().contains('attente') ||
              normalizedStatus.toLowerCase().contains('انتظار')) {
            currentIndex = 2;
          } else if (normalizedStatus.toLowerCase().contains('confirm')) {
            currentIndex = 1;
          } else {
            currentIndex = 0;
          }
        }
        if (currentIndex < stagesSequence.length - 1) {
          final nextStatus = stagesSequence[currentIndex + 1];
          if (normalizedStatus == 'In Progress') {
            if (!mounted) return;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => PopScope(
                canPop: false,
                child: AlertDialog(
                  content: Row(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          lang == AppLanguage.french
                              ? 'Vérification des mesures…'
                              : 'جاري التحقق من القياسات…',
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            await WidgetsBinding.instance.endOfFrame;
            var allConfirmed = false;
            Object? measurementCheckError;
            try {
              allConfirmed = await _areAllMeasurementsConfirmed(
                orderData['id'],
              ).timeout(const Duration(seconds: 15));
            } catch (error) {
              measurementCheckError = error;
            } finally {
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pop();
              }
            }
            if (measurementCheckError != null) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      lang == AppLanguage.french
                          ? 'Impossible de vérifier les mesures de cette commande.'
                          : 'تعذر التحقق من قياسات هذه الطلبية. راجع بيانات القياسات ثم حاول مجددًا.',
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
              return;
            }
            if (!allConfirmed) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      lang == AppLanguage.french
                          ? 'Impossible de passer à la fabrication sans valider les mesures !'
                          : 'لا يمكن الانتقال للتصنيع إن لم تقم بتأكيد القياسات!',
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrderMeasurementsConfirmScreen(
                      orderData: orderData,
                      db: db,
                    ),
                  ),
                );
              }
              return;
            }
          }
          if (nextStatus == 'Partial Manufacturing' ||
              nextStatus == 'Full Manufacturing') {
            final inventoryIssued = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => OrderRequiredGoodsScreen(
                  orderData: orderData,
                  db: db,
                  issueAtManufacturingStart: true,
                ),
              ),
            );
            if (inventoryIssued != true || !mounted) return;
          }
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => PopScope(
              canPop: false,
              child: AlertDialog(
                content: Row(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        lang == AppLanguage.french
                            ? 'Mise à jour de la commande…'
                            : 'جاري تحديث حالة الطلبية…',
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await WidgetsBinding.instance.endOfFrame;
          Object? statusUpdateError;
          try {
            await db
                .updateCommandeStatus(orderData['id'], nextStatus)
                .timeout(const Duration(seconds: 30));
          } catch (error) {
            statusUpdateError = error;
          } finally {
            if (mounted) {
              Navigator.of(context, rootNavigator: true).pop();
            }
          }
          if (statusUpdateError != null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    lang == AppLanguage.french
                        ? 'Échec du passage à l’étape suivante. Veuillez réessayer.'
                        : 'تعذر نقل الطلبية إلى المرحلة التالية. يرجى المحاولة مجددًا.',
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
            return;
          }
          if (!mounted) return;
          setState(() {
            _data = db.readCommandesWithClients();
          });
          if (nextStatus == 'In Progress') {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    lang == AppLanguage.french
                        ? 'Commande passée à: Confirmation des mesures'
                        : 'تم نقل الطلبية إلى مرحلة تأكيد القياسات. يرجى تأكيد المقاسات.',
                  ),
                  backgroundColor: Colors.indigo,
                ),
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderMeasurementsConfirmScreen(
                    orderData: orderData,
                    db: db,
                  ),
                ),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    lang == AppLanguage.french
                        ? 'Commande passée à l\'étape: ${_translateStatus(nextStatus, lang)}'
                        : 'تم نقل الطلبية بنجاح إلى مرحلة: ${_translateStatus(nextStatus, lang)}',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  lang == AppLanguage.french
                      ? 'La commande est déjà dans la dernière étape (Done)!'
                      : 'الطلبية وصلت بالفعل للمرحلة الأخيرة!',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      case 'status':
        _showChangeStatusDialog(orderData);
      case 'edit':
        openOrderInWorkspaceTab(
          context,
          db: db,
          editCommandeId: (orderData['id'] as num?)?.toInt(),
          onSaved: _fetchCommandes,
        );
      case 'duplicate':
        await _duplicateOrder(orderData);
        if (mounted) _fetchCommandes();
      case 'export':
        await OrderExportService.shareOrder(
          context,
          db,
          (orderData['id'] as num?)?.toInt() ?? 0,
          lang,
        );
      case 'delete':
        _showDeleteConfirmDialog(orderData['id']);
    }
  }

  Future<void> _importOrder() async {
    if (_isImportPicking) return;
    setState(() => _isImportPicking = true);
    final lang = context.read<AppSettingsProvider>().language;
    try {
      final payload = await OrderExportService.pickOrderFile();
      if (payload == null || !mounted) return;
      final result = await showDialog<dynamic>(
        context: context,
        builder: (_) => OrderImportDialog(
          payload: payload,
          db: db,
          onImported: _fetchCommandes,
        ),
      );
      if (result != null && mounted) {
        _fetchCommandes();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Localization.translate('invalid_order_file', lang)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImportPicking = false);
      }
    }
  }

  Future<void> _loadWorkshopNameForIdentity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('workshop_name')?.trim() ?? '';
      if (mounted && name != _workshopNameForIdentity) {
        setState(() => _workshopNameForIdentity = name);
      }
    } catch (_) {}
  }

  Future<void> _duplicateOrder(Map<String, dynamic> orderData) async {
    final oldId = (orderData['id'] as num?)?.toInt();
    final clientId = (orderData['client_id'] as num?)?.toInt();
    if (oldId == null || clientId == null) {
      throw StateError('بيانات الطلبية أو العميل غير صالحة.');
    }

    final description = orderData['description']?.toString() ?? '';
    final remise = (orderData['remise'] as num?)?.toDouble() ?? 0.0;
    final tva = (orderData['tva'] as num?)?.toDouble() ?? 0.0;
    final total = (orderData['total'] as num?)?.toDouble() ?? 0.0;
    final items = await db.readCommandeDetails(oldId);
    if (items.isEmpty) {
      throw StateError(
        'لا يمكن نسخ هذه الطلبية لأنها لا تحتوي على سطور تفاصيل محفوظة.',
      );
    }

    final copiedDetails = items
        .map(
          (item) => <String, dynamic>{
            'largeur': (item['largeur'] as num?)?.toInt() ?? 0,
            'hauteur': (item['hauteur'] as num?)?.toInt() ?? 0,
            'game': item['game']?.toString() ?? '',
            'quantity': (item['quantity'] as num?)?.toInt() ?? 1,
            'glass': item['glass']?.toString() ?? '',
            'color': item['color']?.toString() ?? '',
            'volet': item['volet']?.toString() ?? '',
            'accessories': item['accessories']?.toString() ?? '',
            'description': item['description']?.toString() ?? '',
            'price': (item['price'] as num?)?.toDouble() ?? 0.0,
            'window_type': item['window_type']?.toString() ?? '',
            'partitions_json': item['partitions_json']?.toString() ?? '{}',
            'drawing_image_path': item['drawing_image_path']?.toString() ?? '',
            if (item['drawing_image_base64'] != null)
              'drawing_image_base64': item['drawing_image_base64'],
          },
        )
        .toList(growable: false);

    await db.saveCommandeWithDetails(
      clientId: clientId,
      status: 'Nouveau',
      description: description,
      remise: remise,
      tva: tva,
      total: total,
      netPayable: total - remise + ((total * tva) / 100),
      createdAt: DateTime.now().toUtc().toIso8601String(),
      details: copiedDetails,
    );
  }

  void _showDeleteConfirmDialog(int id) async {
    // 1. التحقق أولاً من أن عناصر الفاتورة لم تُستخدم في المخزون
    final isUsed = await db.isCommandeUsedInInventory(id);
    if (!mounted) return;

    if (isUsed) {
      // ✋ ممنوع الحذف: العناصر تُستخدم
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.block, color: Colors.red),
              const SizedBox(width: 8),
              Text(_t('لا يمكن الحذف')),
            ],
          ),
          content: Text(
            _t(
              'هذه الطلبية لا يمكن حذفها لأن بعض عناصرها قد تم استخدامها أو خصمها من المخزون.\n\nيمكنك تغيير حالتها بدلاً من حذفها.',
            ),
            textAlign: TextAlign.start,
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('موافق')),
            ),
          ],
        ),
      );
      return;
    }

    // 2. التحقق من الصلاحية (المدير فقط)
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    if (!settings.canDeleteOrders()) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.lock, color: Colors.orange),
              const SizedBox(width: 8),
              Text(_t('غير مصرح')),
            ],
          ),
          content: Text(
            _t(
              'ليس لديك صلاحية حذف الطلبيات.\nتواصل مع المدير للحصول على هذه الصلاحية.',
            ),
            textAlign: TextAlign.start,
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('موافق')),
            ),
          ],
        ),
      );
      return;
    }

    // 3. تأكيد النقل إلى سلة المهملات
    bool? confirm = await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text(_t('move_to_trash')),
          ],
        ),
        content: Text(_t('confirm_move_to_trash')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_t('إلغاء')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_t('move_to_trash')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final deletedRows = await db.deleteCommande(id);
        if (!mounted) return;

        if (deletedRows == 0) {
          // The record may already have been removed by another device.
          // Remove only this stale row, without reloading the page.
          _removeCommandeFromView(id);
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(_t('الطلبية لم تعد موجودة في قاعدة البيانات.')),
                backgroundColor: Colors.orange,
              ),
            );
          return;
        }

        _removeCommandeFromView(id);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                _t('order_moved_to_trash'),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.blueGrey[900],
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 8),
              persist: false,
              dismissDirection: DismissDirection.horizontal,
              showCloseIcon: true,
              closeIconColor: Colors.white,
              action: SnackBarAction(
                label: _t('undo'),
                textColor: Colors.amberAccent,
                onPressed: () async {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  await db.restoreCommande(id);
                  if (mounted) _fetchCommandes();
                },
              ),
            ),
          );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('${_t('تعذر حذف الطلبية:')} $error'),
              backgroundColor: Colors.red,
            ),
          );
      }
    }
  }

  Future<bool> _areAllMeasurementsConfirmed(int orderId) async {
    final details = await db.readCommandeDetails(orderId);
    if (details.isEmpty) return true;
    for (final detail in details) {
      final jsonStr = detail['instances_json']?.toString() ?? '';
      if (jsonStr.isEmpty) {
        return false;
      }
      try {
        final List decoded = jsonDecode(jsonStr);
        int sum = 0;
        for (final inst in decoded) {
          sum += (inst['qty'] as int? ?? 0);
        }
        if (sum != (detail['quantity'] as int)) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  Future<void> _restoreDocumentImagesFromStoredBytes(
    List<Map<String, dynamic>> items,
  ) async {
    final missingImages = items
        .where((item) {
          final path = item['drawing_image_path']?.toString() ?? '';
          return path.isEmpty || !File(path).existsSync();
        })
        .toList(growable: false);
    if (missingImages.isEmpty) return;

    // A path uploaded by another phone is not valid on this device. Prefer
    // synced image bytes when available, then rebuild from partitions_json if
    // the cloud snapshot intentionally contains no image bytes.
    Directory? cacheDirectory;
    try {
      cacheDirectory = await getTemporaryDirectory().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      // A temporary directory is only needed for a synced byte copy.  We can
      // still rebuild the drawing from partitions_json below.
      cacheDirectory = null;
    }

    final writes = missingImages.map((item) async {
      item['drawing_image_path'] = '';
      final raw = item['drawing_image_base64']?.toString().trim() ?? '';
      if (raw.isNotEmpty && cacheDirectory != null) {
        try {
          final separator = raw.indexOf(',');
          final encoded = raw.startsWith('data:image') && separator >= 0
              ? raw.substring(separator + 1)
              : raw;
          final bytes = base64Decode(encoded);
          if (bytes.isNotEmpty) {
            final detailId =
                (item['id'] as num?)?.toInt() ?? encoded.hashCode.abs();
            final file = File(
              '${cacheDirectory!.path}${Platform.pathSeparator}'
              'devis_item_$detailId.img',
            );
            if (!await file.exists() || await file.length() != bytes.length) {
              await file
                  .writeAsBytes(bytes, flush: false)
                  .timeout(const Duration(seconds: 4));
            }
            item['drawing_image_path'] = file.path;
            return;
          }
        } catch (error) {
          debugPrint('Unable to restore Devis image bytes: $error');
        }
      }

      // Image paths are device-local and images are intentionally excluded
      // from the cloud snapshot. Rebuild the missing image from the durable
      // window model so a second device can display it immediately.
      final modelMap = savedWindowModelMap(item['partitions_json']);
      if (modelMap.isEmpty) return;
      try {
        final model = WindowModel(db: db);
        await applyWindowModelAndLoadCatalog(model, modelMap);
        applyStoredOrderDetailColorToWindowModel(model, item);
        final generatedPath = await saveWindowImageToDisk(model, maxSide: 1800);
        if (generatedPath.isEmpty) return;
        item['drawing_image_path'] = generatedPath;
        final detailId = (item['id'] as num?)?.toInt();
        if (detailId != null) {
          await db.updateCommandeDetailImagePath(detailId, generatedPath);
        }
      } catch (error) {
        debugPrint('Unable to rebuild missing Devis image: $error');
      }
    });

    try {
      await Future.wait(writes).timeout(const Duration(seconds: 10));
    } catch (error) {
      // A single problematic image must never prevent the Devis from opening.
      debugPrint('Devis image restoration timed out: $error');
    }
  }

  void _showChangeStatusDialog(Map<String, dynamic> orderData) {
    final String currentStatus = orderData['status'] ?? 'Pending';
    final statuses = [
      'Nouveau',
      'Confirmed',
      'Pending',
      'In Progress',
      'Partial Manufacturing',
      'Full Manufacturing',
      'Partial Distribution',
      'Full Distribution',
      'Installation',
      'Reserve',
      'Done',
    ];

    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.swap_horiz, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Localization.translate('تغيير حالة الطلبية', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Cairo',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: statuses.map((stageKey) {
                  final bool isCurrent =
                      (stageKey.toLowerCase() == currentStatus.toLowerCase()) ||
                      (stageKey == 'Nouveau' &&
                          (currentStatus == 'New' ||
                              currentStatus == 'Draft' ||
                              currentStatus == 'جديدة' ||
                              currentStatus == 'جديد')) ||
                      (stageKey == 'Pending' &&
                          (currentStatus == 'en_attente' ||
                              currentStatus == 'في الانتظار'));
                  final color = _getStatusColor(stageKey);
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? color.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCurrent ? color : Colors.grey.shade300,
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        radius: 12,
                        backgroundColor: color,
                        child: isCurrent
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      title: Text(
                        _translateStatus(stageKey, lang),
                        style: TextStyle(
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isCurrent
                              ? color
                              : (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white70
                                    : Colors.black87),
                          fontFamily: 'Cairo',
                          fontSize: 14,
                        ),
                      ),
                      trailing: isCurrent
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                lang == AppLanguage.french
                                    ? 'Actuel'
                                    : 'الحالية',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: Colors.grey,
                            ),
                      onTap: () async {
                        final progressIndex = statuses.indexOf('In Progress');
                        final targetIndex = statuses.indexOf(stageKey);

                        if (targetIndex > progressIndex) {
                          final allConfirmed =
                              await _areAllMeasurementsConfirmed(
                                orderData['id'],
                              );
                          if (!allConfirmed) {
                            Navigator.pop(dialogContext);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    lang == AppLanguage.french
                                        ? 'Impossible de passer à la fabrication sans valider les mesures !'
                                        : 'لا يمكن الانتقال للتصنيع إن لم تقم بتأكيد القياسات!',
                                  ),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      OrderMeasurementsConfirmScreen(
                                        orderData: orderData,
                                        db: db,
                                      ),
                                ),
                              );
                            }
                            return;
                          }
                        }

                        if (stageKey == 'Partial Manufacturing' ||
                            stageKey == 'Full Manufacturing') {
                          Navigator.pop(dialogContext);
                          final inventoryIssued = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OrderRequiredGoodsScreen(
                                orderData: orderData,
                                db: db,
                                issueAtManufacturingStart: true,
                              ),
                            ),
                          );
                          if (inventoryIssued != true || !mounted) return;
                        } else {
                          Navigator.pop(dialogContext);
                        }
                        await db.updateCommandeStatus(
                          orderData['id'],
                          stageKey,
                        );
                        setState(() {
                          _data = db.readCommandesWithClients();
                        });

                        if (stageKey == 'In Progress') {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  lang == AppLanguage.french
                                      ? 'Commande passée à: Confirmation des mesures'
                                      : 'تم نقل الطلبية إلى مرحلة تأكيد القياسات. يرجى تأكيد المقاسات.',
                                ),
                                backgroundColor: Colors.indigo,
                              ),
                            );
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderMeasurementsConfirmScreen(
                                  orderData: orderData,
                                  db: db,
                                ),
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  lang == AppLanguage.french
                                      ? 'Statut changé à: ${_translateStatus(stageKey, lang)}'
                                      : 'تم تغيير حالة الطلبية إلى: ${_translateStatus(stageKey, lang)}',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                Localization.translate('إلغاء', lang),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showHeavyLoadingDialog(
    BuildContext context,
    AppLanguage lang,
  ) async {
    final ready = Completer<void>();
    BuildContext? shownDialogContext;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogCtx) {
        shownDialogContext = dialogCtx;
        _loadingDialogContext = dialogCtx;
        if (!ready.isCompleted) ready.complete();
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Text(
                  lang == AppLanguage.french
                      ? 'Génération du document...'
                      : 'جاري تحضير المستند...',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
        );
      },
    );
    unawaited(
      dialogFuture.whenComplete(() {
        if (identical(_loadingDialogContext, shownDialogContext)) {
          _loadingDialogContext = null;
        }
        if (!ready.isCompleted) ready.complete();
      }),
    );
    await ready.future;
  }

  String _formatCreatorDisplay(String? rawPlatform) {
    String raw = (rawPlatform ?? '').trim();
    // Older rows stored the email prefix followed by the device name. Keep
    // the person name, but never display the technical platform suffix.
    raw = raw
        .replaceFirst(
          RegExp(
            r'\s+\((?:web|phone|computer|هاتف|كمبيوتر|ÙˆÙŠØ¨|ÙƒÙ…Ø¨ÙŠÙˆØªØ±|Ù‡Ø§ØªÙ)\)$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    if (raw.isNotEmpty &&
        raw != 'unknown' &&
        raw != 'تطبيق' &&
        raw != 'phone' &&
        raw != 'computer' &&
        raw != 'web' &&
        raw != 'هاتف' &&
        raw != 'كمبيوتر' &&
        raw != 'المدير / عامل الورشة') {
      return raw;
    }
    final user = AppAuthService().currentUser;
    final displayName = user?.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;
    final email = user?.email?.trim() ?? '';
    if (email.isNotEmpty) {
      return email.contains('@') ? email.split('@').first.trim() : email;
    }
    return '—';
  }

  String _formatEditorDisplay(String? rawEditor) {
    final raw = (rawEditor ?? '').trim();
    final isGeneric =
        raw.isEmpty ||
        raw == 'unknown' ||
        raw == 'المدير / عامل الورشة' ||
        raw == 'مدير الورشة' ||
        raw == 'عامل ورشة' ||
        raw == 'عامل';
    final isWorkshopName =
        raw.isNotEmpty &&
        _workshopNameForIdentity.isNotEmpty &&
        raw == _workshopNameForIdentity;
    if (!isGeneric && !isWorkshopName) return raw;

    final user = AppAuthService().currentUser;
    final displayName = user?.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;
    final email = user?.email?.trim() ?? '';
    if (email.isNotEmpty) {
      return email.contains('@') ? email.split('@').first.trim() : email;
    }
    return '—';
  }

  Widget _buildOrderSortableHeaderCell({
    int flex = 1,
    required String label,
    required String colKey,
    required Color mutedColor,
  }) {
    final isSorted = _orderSortColumn == colKey;
    return InkWell(
      onTap: () {
        setState(() {
          if (_orderSortColumn == colKey) {
            if (_orderSortAscending) {
              _orderSortAscending = false;
            } else {
              _orderSortColumn = null;
              _orderSortAscending = true;
            }
          } else {
            _orderSortColumn = colKey;
            _orderSortAscending = true;
          }
        });
        unawaited(_saveOrderSortPreference());
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSorted ? const Color(0xFF2563EB) : mutedColor,
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: isSorted ? FontWeight.w900 : FontWeight.bold,
                ),
              ),
            ),
            if (isSorted) ...[
              const SizedBox(width: 2),
              Icon(
                _orderSortAscending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 13,
                color: const Color(0xFF2563EB),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOrderFilterInputCell({
    required int flex,
    required TextEditingController controller,
    required String hintText,
    required BuildContext context,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          height: 42,
          child: TextField(
            controller: controller,
            onChanged: (_) => setState(() {}),
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'Cairo',
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
                fontFamily: 'Cairo',
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF2563EB),
                  width: 1.5,
                ),
              ),
              suffixIcon: controller.text.isNotEmpty
                  ? InkWell(
                      onTap: () {
                        controller.clear();
                        setState(() {});
                      },
                      child: const Icon(
                        Icons.close,
                        size: 17,
                        color: Colors.red,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopOrdersTableView(
    BuildContext context,
    List<Map<String, dynamic>> rawData,
    AppLanguage lang,
  ) {
    final cardColor = Theme.of(context).cardColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contentColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;
    final mutedColor =
        Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.blue.shade100;

    final data = _applyOrderFiltersAndSort(rawData, lang);
    final statusFilterOptions = _buildOrderStatusFilterOptions(rawData, lang);

    final columns = [
      ResizableTableColumn(
        id: 'id',
        label: _buildOrderSortableHeaderCell(
          label: '#',
          colKey: 'id',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: '#...',
          isNumeric: true,
          lang: lang,
          initialNumericState:
              _orderNumericFilters['id'] ?? const NumericFilterState(),
          onNumericFilterChanged: (f) =>
              setState(() => _orderNumericFilters['id'] = f),
        ),
        initialWidth: 75,
        minWidth: 55,
        maxWidth: 130,
      ),
      ResizableTableColumn(
        id: 'client_project',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('الزبون والمشروع', lang),
          colKey: 'client_project',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('زبون / مشروع...', lang),
          controller: _orderColumnControllers['client_project'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 220,
        minWidth: 140,
        maxWidth: 380,
      ),
      ResizableTableColumn(
        id: 'date',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('تاريخ الإنشاء', lang),
          colKey: 'date',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('سنة-شهر...', lang),
          controller: _orderColumnControllers['date'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 125,
        minWidth: 95,
        maxWidth: 200,
      ),
      ResizableTableColumn(
        id: 'updated_at',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('تاريخ التعديل', lang),
          colKey: 'updated_at',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('سنة-شهر...', lang),
          controller: _orderColumnControllers['updated_at'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 125,
        minWidth: 95,
        maxWidth: 200,
      ),
      ResizableTableColumn(
        id: 'updated_by',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('معدّل من طرف', lang),
          colKey: 'updated_by',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('اسم المعدّل...', lang),
          controller: _orderColumnControllers['updated_by'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 140,
        minWidth: 100,
        maxWidth: 260,
      ),
      ResizableTableColumn(
        id: 'total',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('المجموع الكلي (د.ج)', lang),
          colKey: 'total',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('المجموع...', lang),
          isNumeric: true,
          lang: lang,
          initialNumericState:
              _orderNumericFilters['total'] ?? const NumericFilterState(),
          onNumericFilterChanged: (f) =>
              setState(() => _orderNumericFilters['total'] = f),
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 220,
      ),
      ResizableTableColumn(
        id: 'advance',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('المدفوع', lang),
          colKey: 'advance',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('المدفوع...', lang),
          isNumeric: true,
          lang: lang,
          initialNumericState:
              _orderNumericFilters['advance'] ?? const NumericFilterState(),
          onNumericFilterChanged: (f) =>
              setState(() => _orderNumericFilters['advance'] = f),
        ),
        initialWidth: 120,
        minWidth: 90,
        maxWidth: 200,
      ),
      ResizableTableColumn(
        id: 'remaining',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('المتبقي', lang),
          colKey: 'remaining',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('المتبقي...', lang),
          isNumeric: true,
          lang: lang,
          initialNumericState:
              _orderNumericFilters['remaining'] ?? const NumericFilterState(),
          onNumericFilterChanged: (f) =>
              setState(() => _orderNumericFilters['remaining'] = f),
        ),
        initialWidth: 120,
        minWidth: 90,
        maxWidth: 200,
      ),
      ResizableTableColumn(
        id: 'status',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('حالة الورشة', lang),
          colKey: 'status',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('حالة الورشة...', lang),
          controller: _orderColumnControllers['status'],
          lang: lang,
          options: statusFilterOptions,
          optionsTooltip: Localization.translate('اختيار حالة الطلبية', lang),
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 220,
      ),
      ResizableTableColumn(
        id: 'stock_reserved',
        label: _buildOrderSortableHeaderCell(
          label: lang == AppLanguage.french
              ? 'Statut stock'
              : Localization.translate('حالة السلع', lang),
          colKey: 'stock_reserved',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: lang == AppLanguage.french
              ? 'Réservation...'
              : Localization.translate('حالة السلع...', lang),
          controller: _orderColumnControllers['stock_reserved'],
          lang: lang,
          options: [
            TableFilterOption(
              value: '',
              label: Localization.translate('الكل', lang),
              icon: Icons.clear_all_rounded,
              color: Colors.grey,
            ),
            TableFilterOption(
              value: lang == AppLanguage.french ? 'réservé' : 'محجوز',
              label: lang == AppLanguage.french
                  ? 'Réservé'
                  : Localization.translate('تم الحجز', lang),
              icon: Icons.check_circle,
              color: Colors.green,
            ),
            TableFilterOption(
              value: lang == AppLanguage.french ? 'non réservé' : 'غير محجوز',
              label: lang == AppLanguage.french
                  ? 'Non réservé'
                  : Localization.translate('لم يُحجز بعد', lang),
              icon: Icons.inventory_2_outlined,
              color: Colors.grey,
            ),
          ],
          optionsTooltip: Localization.translate('تصفية حسب حجز السلع', lang),
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 220,
      ),
      ResizableTableColumn(
        id: 'creator',
        label: _buildOrderSortableHeaderCell(
          label: Localization.translate('المُدخل', lang),
          colKey: 'creator',
          mutedColor: mutedColor,
        ),
        filter: CompactTableFilterField(
          hintText: Localization.translate('المُدخل...', lang),
          controller: _orderColumnControllers['creator'],
          lang: lang,
          onTextChanged: (_) => setState(() {}),
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 240,
      ),
      ResizableTableColumn(
        id: 'actions',
        label: Center(
          child: Text(
            Localization.translate('إجراءات', lang),
            style: TextStyle(
              color: mutedColor,
              fontFamily: 'Cairo',
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        filter: _hasActiveOrderColumnFilters
            ? Center(
                child: InkWell(
                  onTap: _clearAllOrderColumnFilters,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.clear_all,
                          size: 13,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          Localization.translate('مسح', lang),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        initialWidth: 95,
        minWidth: 75,
        maxWidth: 150,
      ),
    ];

    final rows = data.map((order) {
      final clientFirst = order['firstname'] ?? '';
      final clientLast = order['lastname'] ?? '';
      final clientName = '$clientFirst $clientLast'.trim();
      final projectName = (order['project_name'] ?? '').toString().trim();
      final clientProject = projectName.isNotEmpty
          ? '$clientName ($projectName)'
          : (clientName.isEmpty ? 'زبون عام' : clientName);

      final netPayable =
          (order['net_payable'] as num?)?.toDouble() ??
          (order['total'] as num?)?.toDouble() ??
          0.0;
      final advance = (order['advance_payment'] as num?)?.toDouble() ?? 0.0;
      final remaining = netPayable - advance;
      final status = (order['status'] ?? 'Pending').toString();
      final statusColor = _getStatusColor(status);
      final creator = _formatCreatorDisplay(
        order['creation_platform']?.toString(),
      );
      final updatedBy = _formatEditorDisplay(order['updated_by']?.toString());
      final pinned = isOrderPinned(order);

      KeyEventResult handleOrderKey(KeyEvent event) {
        final focusContext = FocusManager.instance.primaryFocus?.context;
        if (focusContext != null &&
            (ModalRoute.of(focusContext) is PopupRoute ||
                focusContext.widget is EditableText ||
                focusContext.findAncestorWidgetOfExactType<EditableText>() !=
                    null)) {
          return KeyEventResult.ignored;
        }
        final shortcuts = ShortcutBindings.instance;
        final settings = context.read<AppSettingsProvider>();
        final id = (order['id'] as num?)?.toInt();
        if (id == null) return KeyEventResult.ignored;
        if (shortcuts.matches('edit_order', event) &&
            settings.canEditOrders()) {
          openOrderInWorkspaceTab(
            context,
            db: db,
            editCommandeId: id,
            onSaved: _fetchCommandes,
          );
          return KeyEventResult.handled;
        }
        if ((shortcuts.matches('delete_order', event) ||
                event.logicalKey == LogicalKeyboardKey.delete) &&
            settings.canDeleteOrders()) {
          _showDeleteConfirmDialog(id);
          return KeyEventResult.handled;
        }
        if (shortcuts.matches('devis_order', event)) {
          _openOrderDevis(order, lang);
          return KeyEventResult.handled;
        }
        if (shortcuts.matches('details_order', event)) {
          _openOrderDetails(order);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      final orderId = (order['id'] as num?)?.toInt() ?? 0;
      final isUnseen = _isOrderUnseen(order);
      final isHighlighted =
          _notificationHighlightedOrderId?.toString() == order['id'].toString();

      final rowBgColor = isHighlighted
          ? (Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF594B16)
                : const Color(0xFFFFF1A8))
          : (isUnseen
                ? (Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF064E3B).withValues(alpha: 0.45)
                      : const Color(0xFFECFDF5))
                : null);

      return ResizableTableRow(
        reorderId: order['id'].toString(),
        color: rowBgColor,
        onTap: () {
          _markOrderSeen(order);
          if (_notificationHighlightedOrderId?.toString() ==
              order['id'].toString()) {
            setState(() => _notificationHighlightedOrderId = null);
          }
          _openOrderDetails(order);
        },
        onKeyEvent: handleOrderKey,
        onDoubleTap: context.read<AppSettingsProvider>().canEditOrders()
            ? () => openOrderInWorkspaceTab(
                context,
                db: db,
                editCommandeId: (order['id'] as num?)?.toInt(),
                onSaved: _fetchCommandes,
              )
            : null,
        onSecondaryTapDown: (position) =>
            _showOrderContextMenu(context, order, position, lang),
        cells: [
          // ID
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pinned) ...[
                Icon(
                  Icons.push_pin_rounded,
                  size: 14,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                _displayOrderLabel(order),
                style: const TextStyle(
                  color: Color(0xFF2563EB),
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          // Client & Project
          Text(
            clientProject,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: contentColor,
            ),
          ),
          // Date
          Text(
            formatDate(order),
            style: TextStyle(
              color: mutedColor,
              fontFamily: 'Cairo',
              fontSize: 11.5,
            ),
          ),
          // Last edit timestamp and editor
          Text(
            formatOrderDate(order['updated_at'], fallback: order['created_at']),
            style: TextStyle(
              color: mutedColor,
              fontFamily: 'Cairo',
              fontSize: 11.5,
            ),
          ),
          Text(
            updatedBy.isEmpty ? '—' : updatedBy,
            style: TextStyle(
              color: mutedColor,
              fontFamily: 'Cairo',
              fontSize: 11.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          // Total
          Text(
            '${netPayable.toStringAsFixed(0)} د.ج',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: contentColor,
            ),
          ),
          // Advance
          Text(
            '${advance.toStringAsFixed(0)} د.ج',
            style: const TextStyle(
              color: Color(0xFF10B981),
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Remaining
          Text(
            '${remaining.toStringAsFixed(0)} د.ج',
            style: TextStyle(
              color: remaining > 0
                  ? const Color(0xFFEF4444)
                  : const Color(0xFF10B981),
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Status (حالة الورشة)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _translateStatus(status, lang),
              style: TextStyle(
                color: statusColor,
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // Stock Reservation Status (حالة السلع: réservé / non réservé)
          Builder(
            builder: (ctx) {
              final status = (order['status'] ?? '').toString();
              if (_hasPassedFullManufacturing(status)) {
                return const Center(
                  child: Text(
                    '—',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                );
              }
              final isStockReserved =
                  (order['is_stock_reserved'] as num?)?.toInt() == 1;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isStockReserved
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isStockReserved
                        ? Colors.green.shade600
                        : Colors.grey.shade400,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isStockReserved
                          ? Icons.check_circle
                          : Icons.inventory_2_outlined,
                      size: 13,
                      color: isStockReserved
                          ? Colors.green.shade800
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isStockReserved
                          ? (lang == AppLanguage.french
                                ? 'Réservé'
                                : Localization.translate('تم الحجز', lang))
                          : (lang == AppLanguage.french
                                ? 'Non réservé'
                                : Localization.translate('لم يُحجز بعد', lang)),
                      style: TextStyle(
                        color: isStockReserved
                            ? Colors.green.shade900
                            : Colors.grey.shade700,
                        fontFamily: 'Cairo',
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // Creator
          Text(
            creator,
            style: TextStyle(
              color: mutedColor,
              fontFamily: 'Cairo',
              fontSize: 11.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          // Actions
          Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              return handleOrderKey(event);
            },
            child: Center(
              child: IconButton(
                icon: const Icon(Icons.more_horiz_rounded, size: 18),
                onPressed: () => _showOrderOptions(context, order),
                tooltip: Localization.translate('خيارات الطلبية', lang),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      );
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Date Range Filter Bar for Desktop ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TableDateRangeFilterBar(
                  initialRange: _orderDateRange,
                  lang: lang,
                  compact: true,
                  onRangeChanged: (range) {
                    setState(() => _orderDateRange = range);
                  },
                ),
              ),
              const SizedBox(width: 8),
              _buildOrderSortButton(lang),
            ],
          ),
          const SizedBox(height: 8),

          // ── Desktop Resizable Table with zero vertical overflow ──
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ResizableColumnsTable(
                  persistenceKey: 'orders',
                  emptyPlaceholder: Center(
                    child: Text(
                      Localization.translate('No matching results', lang),
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade600,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  revealRowId: _notificationHighlightedOrderId?.toString(),
                  footerCells: {
                    'total': Text(
                      data
                          .fold<double>(
                            0,
                            (sum, row) =>
                                sum +
                                ((row['net_payable'] as num?)?.toDouble() ??
                                    (row['total'] as num?)?.toDouble() ??
                                    0),
                          )
                          .toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    'advance': Text(
                      data
                          .fold<double>(
                            0,
                            (sum, row) =>
                                sum +
                                ((row['advance_payment'] as num?)?.toDouble() ??
                                    0),
                          )
                          .toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    'remaining': Text(
                      data
                          .fold<double>(
                            0,
                            (sum, row) =>
                                sum +
                                ((row['net_payable'] as num?)?.toDouble() ??
                                    (row['total'] as num?)?.toDouble() ??
                                    0) -
                                ((row['advance_payment'] as num?)?.toDouble() ??
                                    0),
                          )
                          .toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  },
                  columns: columns,
                  rows: rows,
                  headerColor: const Color(0xFF2563EB).withValues(alpha: 0.08),
                  filterRowColor: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF8FAFC),
                  borderColor: borderColor,
                  rowColor: cardColor,
                  verticalController: _desktopOrdersScrollController,
                  headerMinHeight: 38,
                  filterRowMinHeight: 34,
                  rowMinHeight: 46,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TableFilterOption> _buildOrderStatusFilterOptions(
    List<Map<String, dynamic>> rawData,
    AppLanguage lang,
  ) {
    final statusesByGroup = <String, String>{};
    for (final status in canonicalOrderStatuses) {
      statusesByGroup[orderStatusGroupKey(status)] = status;
    }
    for (final order in rawData) {
      final status = (order['status'] ?? 'Pending').toString();
      statusesByGroup.putIfAbsent(orderStatusGroupKey(status), () => status);
    }

    final sortedStatuses = statusesByGroup.entries.toList()
      ..sort((a, b) {
        final wA = _getOrderStatusWeight(a.value);
        final wB = _getOrderStatusWeight(b.value);
        final comp = wA.compareTo(wB);
        if (comp != 0) return comp;
        final translatedA = _translateStatus(
          orderStatusCanonicalLabel(a.value),
          lang,
        );
        final translatedB = _translateStatus(
          orderStatusCanonicalLabel(b.value),
          lang,
        );
        return translatedA.compareTo(translatedB);
      });

    return [
      TableFilterOption(
        value: '',
        label: Localization.translate('كل الحالات', lang),
        icon: Icons.clear_all_rounded,
        color: Colors.grey,
      ),
      TableFilterOption(
        value: 'filter_confirmed_above',
        label: Localization.translate('المؤكدة فما فوق', lang),
        icon: Icons.verified_outlined,
        color: const Color(0xFF2E7D32),
      ),
      TableFilterOption(
        value: 'filter_mfg_above',
        label: Localization.translate('قيد التصنيع وما بعدها', lang),
        icon: Icons.precision_manufacturing_outlined,
        color: const Color(0xFF0288D1),
      ),
      TableFilterOption(
        value: 'filter_dist_above',
        label: Localization.translate('التوزيع وما بعده', lang),
        icon: Icons.local_shipping_outlined,
        color: const Color(0xFFF57C00),
      ),
      for (final status in sortedStatuses)
        TableFilterOption(
          value: 'filter_status_group:${status.key}',
          label: _translateStatus(
            orderStatusCanonicalLabel(status.value),
            lang,
          ),
          icon: Icons.circle,
          color: _getStatusColor(status.value),
        ),
    ];
  }

  void _dismissHeavyLoadingDialog() {
    final dialogContext = _loadingDialogContext;
    _loadingDialogContext = null;
    if (dialogContext == null || !dialogContext.mounted) return;
    Navigator.of(dialogContext).pop();
  }
}

class _OrderPicturePdfPayload {
  const _OrderPicturePdfPayload({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

class _OrderPicturePreviewPayload {
  const _OrderPicturePreviewPayload({
    required this.orderData,
    required this.filename,
    required this.items,
  });

  final Map<String, dynamic> orderData;
  final String filename;
  final List<_OrderPicturePreviewItem> items;
}

class _OrderPicturePreviewItem {
  const _OrderPicturePreviewItem({
    required this.title,
    required this.details,
    required this.quantity,
    required this.width,
    required this.height,
    required this.color,
    required this.imageBytes,
  });

  final String title;
  final List<String> details;
  final int quantity;
  final int width;
  final int height;
  final String color;
  final Uint8List? imageBytes;
}

class _OrderPicturePdfPreviewPage extends StatefulWidget {
  const _OrderPicturePdfPreviewPage({
    required this.db,
    required this.orderData,
    required this.lang,
  });

  final SqlDatabase db;
  final Map<String, dynamic> orderData;
  final AppLanguage lang;

  @override
  State<_OrderPicturePdfPreviewPage> createState() =>
      _OrderPicturePdfPreviewPageState();
}

class _OrderPicturePdfPreviewPageState
    extends State<_OrderPicturePdfPreviewPage> {
  late Future<_OrderPicturePreviewPayload> _future;
  _OrderPicturePdfPayload? _pdfPayload;
  bool _isPdfBusy = false;

  @override
  void initState() {
    super.initState();
    _future = _buildPayload();
  }

  Future<_OrderPicturePreviewPayload> _buildPayload() async {
    var orderData = Map<String, dynamic>.from(widget.orderData);
    final freshOrderId = (orderData['id'] as num?)?.toInt() ?? 0;
    if (freshOrderId > 0) {
      final freshOrder = await widget.db.readCommandeWithClientById(
        freshOrderId,
      );
      if (freshOrder != null) {
        orderData = {...orderData, ...freshOrder};
      }
    }

    final rawItems = freshOrderId > 0
        ? await widget.db.readCommandeDetails(freshOrderId)
        : const <Map<String, dynamic>>[];
    final items = <_OrderPicturePreviewItem>[];
    for (final raw in rawItems) {
      final item = Map<String, dynamic>.from(raw);
      final line = DevisBuilder.buildLineItemFromDetail(
        item,
        overrideLang: widget.lang,
        forceGeneratedDetails: false,
      );
      final imageBytes = await _readPreviewImageBytes(
        item,
      ).timeout(const Duration(seconds: 8), onTimeout: () => null);
      items.add(
        _OrderPicturePreviewItem(
          title: line.title,
          details: line.details,
          quantity: line.quantity,
          width: line.width,
          height: line.height,
          color: line.color,
          imageBytes: imageBytes,
        ),
      );
      await Future.delayed(Duration.zero);
    }

    return _OrderPicturePreviewPayload(
      orderData: orderData,
      filename: OrderPicturePdfService.fileNameFor(orderData, widget.lang),
      items: items,
    );
  }

  void _retry() {
    setState(() {
      _pdfPayload = null;
      _future = _buildPayload();
    });
  }

  Future<_OrderPicturePdfPayload> _ensurePdfPayload(
    _OrderPicturePreviewPayload preview,
  ) async {
    final existing = _pdfPayload;
    if (existing != null) return existing;
    final bytes = await OrderPicturePdfService.buildPdfBytes(
      db: widget.db,
      order: preview.orderData,
      lang: widget.lang,
    ).timeout(const Duration(seconds: 90));
    final payload = _OrderPicturePdfPayload(
      bytes: bytes,
      filename: preview.filename,
    );
    if (mounted) {
      setState(() => _pdfPayload = payload);
    }
    return payload;
  }

  Future<void> _runPdfAction(
    _OrderPicturePreviewPayload preview,
    Future<void> Function(_OrderPicturePdfPayload payload) action,
  ) async {
    if (_isPdfBusy) return;
    setState(() => _isPdfBusy = true);
    try {
      final payload = await _ensurePdfPayload(preview);
      await action(payload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${Localization.translate('فشل توليد ملف PDF', widget.lang)}: $error',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPdfBusy = false);
    }
  }

  Future<void> _save(_OrderPicturePdfPayload payload) async {
    final savedPath = await OrderPicturePdfService.savePdf(
      bytes: payload.bytes,
      filename: payload.filename,
    );
    if (!mounted || savedPath == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Localization.translate('تم حفظ ملف الصور بنجاح', widget.lang),
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _share(_OrderPicturePdfPayload payload) async {
    await OrderPicturePdfService.sharePdf(
      bytes: payload.bytes,
      filename: payload.filename,
    );
  }

  Future<void> _print(_OrderPicturePdfPayload payload) async {
    await OrderPicturePdfService.printPdf(
      bytes: payload.bytes,
      filename: payload.filename,
    );
  }

  Future<Uint8List?> _readPreviewImageBytes(Map<String, dynamic> item) async {
    final modelMap = savedWindowModelMap(item['partitions_json']);

    // An old image can carry a different colour than the durable detail row.
    // Repair that image before returning it; otherwise the preview keeps
    // showing (for example) antique while the order says white.
    final path = item['drawing_image_path']?.toString().trim() ?? '';
    if (path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists() &&
            !storedOrderDetailColorDiffersFromModel(item, modelMap)) {
          return file.readAsBytes();
        }
      } catch (_) {}
    }

    final raw = item['drawing_image_base64']?.toString().trim() ?? '';
    if (raw.isNotEmpty &&
        !storedOrderDetailColorDiffersFromModel(item, modelMap)) {
      try {
        final separator = raw.indexOf(',');
        final encoded = raw.startsWith('data:image') && separator >= 0
            ? raw.substring(separator + 1)
            : raw;
        return base64Decode(encoded);
      } catch (_) {}
    }

    if (modelMap.isNotEmpty) {
      try {
        final model = WindowModel(db: widget.db);
        await applyWindowModelAndLoadCatalog(model, modelMap);
        applyStoredOrderDetailColorToWindowModel(model, item);
        final image = await captureWindowImage(
          model,
          maxSide: 3200,
          showDrawingDimensions: true,
        );
        final repairedPath = await saveWindowImageToDisk(model, maxSide: 1800);
        if (repairedPath.isNotEmpty) {
          final detailId = (item['id'] as num?)?.toInt();
          if (detailId != null) {
            await widget.db.updateCommandeDetailImagePath(
              detailId,
              repairedPath,
            );
          }
          item['drawing_image_path'] = repairedPath;
        }
        return image;
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_OrderPicturePreviewPayload>(
      future: _future,
      builder: (context, snapshot) {
        final payload = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(Localization.translate('Picture', widget.lang)),
            actions: [
              if (payload != null) ...[
                IconButton(
                  tooltip: Localization.translate(
                    'حفظ Picture PDF',
                    widget.lang,
                  ),
                  icon: _isPdfBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_alt),
                  onPressed: _isPdfBusy
                      ? null
                      : () => _runPdfAction(payload, _save),
                ),
                IconButton(
                  tooltip: Localization.translate(
                    'مشاركة Picture PDF',
                    widget.lang,
                  ),
                  icon: const Icon(Icons.share),
                  onPressed: _isPdfBusy
                      ? null
                      : () => _runPdfAction(payload, _share),
                ),
                IconButton(
                  tooltip: Localization.translate(
                    'طباعة Picture PDF',
                    widget.lang,
                  ),
                  icon: const Icon(Icons.print),
                  onPressed: _isPdfBusy
                      ? null
                      : () => _runPdfAction(payload, _print),
                ),
              ],
            ],
          ),
          body: _buildBody(snapshot, payload),
        );
      },
    );
  }

  Widget _buildBody(
    AsyncSnapshot<_OrderPicturePreviewPayload> snapshot,
    _OrderPicturePreviewPayload? payload,
  ) {
    if (snapshot.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 42),
              const SizedBox(height: 12),
              Text(
                '${Localization.translate('خطأ أثناء توليد ملف الصور: ', widget.lang)}${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: Text(
                  Localization.translate('إعادة المحاولة', widget.lang),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (payload == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              Localization.translate('جار تجهيز الصور', widget.lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ],
        ),
      );
    }

    if (payload.items.isEmpty) {
      return Center(
        child: Text(
          Localization.translate('لا توجد صور لهذه الطلبية', widget.lang),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: payload.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final item = payload.items[index];
        return _buildPreviewCard(item, index + 1);
      },
    );
  }

  Widget _buildPreviewCard(_OrderPicturePreviewItem item, int index) {
    final details = item.details
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final meta = <String>[
      if (item.width > 0 || item.height > 0)
        '${Localization.translate('الأبعاد', widget.lang)}: ${item.width} x ${item.height} mm',
      '${Localization.translate('الكمية', widget.lang)}: ${item.quantity}',
      if (item.color.trim().isNotEmpty)
        '${Localization.translate('اللون', widget.lang)}: ${item.color}',
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$index. ${item.title}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                meta.join('   |   '),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.grey.shade700,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.74,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: item.imageBytes == null
                    ? Center(
                        child: Text(
                          Localization.translate(
                            'لا توجد صورة محفوظة لهذا العنصر',
                            widget.lang,
                          ),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      )
                    : InteractiveViewer(
                        minScale: 0.7,
                        maxScale: 5,
                        child: Center(
                          child: Image.memory(
                            item.imageBytes!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...details.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    line,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
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
