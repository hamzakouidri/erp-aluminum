import 'dart:async';
import 'dart:convert';
import 'package:database_data/widgets/app_material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../services/cloud_sync_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';

class TrashScreen extends StatefulWidget {
  final SqlDatabase? db;
  final VoidCallback? onOrderRestored;
  final int initialIndex;

  const TrashScreen({
    super.key,
    this.db,
    this.onOrderRestored,
    this.initialIndex = 0,
  });

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen>
    with SingleTickerProviderStateMixin {
  late final SqlDatabase _db;
  late final TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _trashOrders = [];
  List<Map<String, dynamic>> _trashAchats = [];
  List<Map<String, dynamic>> _trashMaterialSales = [];
  List<Map<String, dynamic>> _auditLogs = [];
  static const int _auditPageSize = 50;
  static const int _auditTabIndex = 3;
  final ScrollController _auditScrollController = ScrollController();
  int _auditTotal = 0;
  bool _auditLoaded = false;
  bool _auditLoading = false;
  bool _auditLoadingMore = false;
  bool _auditHasMore = false;
  String _auditLoadedQuery = '';

  // Bumped on every first-page load so late responses of an older search
  // are dropped instead of overwriting the newer list.
  int _auditRequestToken = 0;
  Timer? _auditSearchDebounce;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<String>? _syncSubscription;
  Timer? _syncDebounceTimer;

  @override
  void initState() {
    super.initState();
    _db = widget.db ?? SqlDatabase();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 3),
    );
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
      if (!_tabController.indexIsChanging) _ensureAuditLoaded();
    });
    _auditScrollController.addListener(_onAuditScroll);
    _loadTrashData();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAuditLoaded());
    _syncSubscription = CloudSyncService().dbUpdateStream.listen((event) {
      if (mounted) {
        _syncDebounceTimer?.cancel();
        _syncDebounceTimer = Timer(const Duration(milliseconds: 500), () {
          if (mounted) {
            _loadTrashOrders();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _syncDebounceTimer?.cancel();
    _auditSearchDebounce?.cancel();
    _auditScrollController.dispose();
    _tabController.dispose();
    _searchController.dispose();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadTrashData({bool isUserInitiated = true}) async {
    if (isUserInitiated &&
        (_trashOrders.isEmpty &&
            _trashAchats.isEmpty &&
            _trashMaterialSales.isEmpty)) {
      setState(() => _isLoading = true);
    }
    try {
      final orders = await _db.readTrashCommandesWithClients();
      final achats = await _db.readTrashAchats();
      final materialSales = await _db.readTrashMaterialSales();
      if (mounted) {
        setState(() {
          _trashOrders = orders;
          _trashAchats = achats;
          _trashMaterialSales = materialSales;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
    // The audit log is paged separately and only for authorised users;
    // a sync event refreshes the rows already on screen, not the whole table.
    if (!mounted || !_canViewAudit) return;
    if (_auditLoaded) {
      await _loadAuditFirstPage(keepLoadedCount: !isUserInitiated);
    } else {
      final total = await _db.countAuditLogs();
      if (mounted) setState(() => _auditTotal = total);
    }
  }

  bool get _canViewAudit =>
      context.read<AppSettingsProvider>().canViewDocumentHistory();

  void _ensureAuditLoaded() {
    if (!mounted ||
        _tabController.index != _auditTabIndex ||
        !_canViewAudit ||
        _auditLoading) {
      return;
    }
    if (!_auditLoaded || _auditLoadedQuery != _searchQuery.trim()) {
      _loadAuditFirstPage();
    }
  }

  Future<void> _loadAuditFirstPage({bool keepLoadedCount = false}) async {
    final query = _searchQuery.trim();
    final token = ++_auditRequestToken;
    final limit = keepLoadedCount && _auditLogs.length > _auditPageSize
        ? _auditLogs.length
        : _auditPageSize;
    if (!keepLoadedCount) setState(() => _auditLoading = true);
    final rows = await _db.readAuditLogsPage(limit: limit, query: query);
    final total = await _db.countAuditLogs(query: query);
    if (!mounted || token != _auditRequestToken) return;
    setState(() {
      _auditLogs = rows;
      _auditTotal = total;
      _auditHasMore = rows.length >= limit;
      _auditLoadedQuery = query;
      _auditLoaded = true;
      _auditLoading = false;
      _auditLoadingMore = false;
    });
    if (!keepLoadedCount && _auditScrollController.hasClients) {
      _auditScrollController.jumpTo(0);
    }
    // A search typed while this page was loading still needs its own page.
    if (_auditLoadedQuery != _searchQuery.trim()) _ensureAuditLoaded();
  }

  Future<void> _loadMoreAudit() async {
    if (_auditLoading ||
        _auditLoadingMore ||
        !_auditHasMore ||
        _auditLogs.isEmpty) {
      return;
    }
    final token = _auditRequestToken;
    final last = _auditLogs.last;
    setState(() => _auditLoadingMore = true);
    final rows = await _db.readAuditLogsPage(
      limit: _auditPageSize,
      query: _auditLoadedQuery,
      beforeTimestamp: last['timestamp']?.toString() ?? '',
      beforeId: (last['id'] as num?)?.toInt() ?? 0,
    );
    if (!mounted || token != _auditRequestToken) return;
    setState(() {
      _auditLogs = [..._auditLogs, ...rows];
      _auditHasMore = rows.length >= _auditPageSize;
      _auditLoadingMore = false;
    });
  }

  void _onAuditScroll() {
    final position = _auditScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) _loadMoreAudit();
  }

  void _onSearchChanged(String val) {
    setState(() => _searchQuery = val);
    _auditSearchDebounce?.cancel();
    if (_tabController.index != _auditTabIndex) return;
    _auditSearchDebounce = Timer(
      const Duration(milliseconds: 350),
      _ensureAuditLoaded,
    );
  }

  Future<void> _loadTrashOrders() => _loadTrashData(isUserInitiated: false);

  List<Map<String, dynamic>> get _filteredAchats {
    if (_searchQuery.trim().isEmpty) return _trashAchats;
    final q = _searchQuery.trim().toLowerCase();
    return _trashAchats.where((achat) {
      final num = (achat['invoice_number'] ?? '').toString().toLowerCase();
      final sup =
          (achat['supplier_name'] ?? achat['supplier_name_joined'] ?? '')
              .toString()
              .toLowerCase();
      return num.contains(q) || sup.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredMaterialSales {
    if (_searchQuery.trim().isEmpty) return _trashMaterialSales;
    final q = _searchQuery.trim().toLowerCase();
    return _trashMaterialSales.where((sale) {
      return (sale['sale_code'] ?? '').toString().toLowerCase().contains(q) ||
          (sale['client_name'] ?? '').toString().toLowerCase().contains(q) ||
          (sale['client_phone'] ?? '').toString().toLowerCase().contains(q) ||
          (sale['doc_type'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _restoreMaterialSale(
    int saleId,
    AppLanguage lang,
    AppSettingsProvider settings,
  ) async {
    if (!settings.canRestoreDeletedDocuments()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(
              'ليس لديك صلاحية استعادة الوثائق المحذوفة',
              lang,
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Localization.translate('استعادة وثيقة المبيعات', lang)),
        content: Text(
          Localization.translate(
            'ستُستعاد الوثيقة كمسودة للمراجعة، ولن يُخصم المخزون إلا عند تأكيدها من جديد.',
            lang,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Localization.translate('cancel', lang)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.restore_from_trash_rounded),
            label: Text(Localization.translate('استعادة', lang)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.restoreMaterialSale(saleId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Localization.translate('تمت استعادة الوثيقة كمسودة', lang),
        ),
        backgroundColor: Colors.teal,
      ),
    );
    await _loadTrashData();
  }

  Future<void> _restoreAchat(int achatId, AppLanguage lang) async {
    if (!context.read<AppSettingsProvider>().canRestoreDeletedDocuments()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate('ليس لديك صلاحية الاسترجاع', lang),
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.restore_from_trash_rounded, color: Colors.teal),
            const SizedBox(width: 8),
            Text(Localization.translate('استعادة الفاتورة', lang)),
          ],
        ),
        content: Text(
          Localization.translate('هل ترغب في استعادة فاتورة الشراء هذه؟', lang),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Localization.translate('cancel', lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(Localization.translate('استعادة الفاتورة', lang)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _db.restoreAchat(achatId);
      widget.onOrderRestored?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localization.translate('تمت استعادة الفاتورة بنجاح', lang),
            ),
            backgroundColor: Colors.teal,
          ),
        );
        _loadTrashData();
      }
    }
  }

  Future<void> _permanentlyDeleteAchat(int achatId, AppLanguage lang) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text(_t('delete_permanently', lang)),
          ],
        ),
        content: Text(
          Localization.translate(
            'هل أنت متأكد من الحذف النهائي لفاتورة الشراء؟ لا يمكن التراجع عن هذا الإجراء.',
            lang,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Localization.translate('cancel', lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('delete_permanently', lang)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _db.deleteAchat(achatId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                Localization.translate('تم حذف الفاتورة نهائياً', lang),
              ),
              backgroundColor: Colors.red,
            ),
          );
          _loadTrashData();
        }
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                Localization.translate(
                  err.toString().replaceFirst(
                    RegExp(r'^(Bad state|Exception): '),
                    '',
                  ),
                  lang,
                ),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  List<Map<String, dynamic>> get _filteredOrders {
    if (_searchQuery.trim().isEmpty) return _trashOrders;
    final q = _searchQuery.trim().toLowerCase();
    return _trashOrders.where((order) {
      final code = (order['order_code'] ?? order['id'] ?? '').toString();
      final firstName = (order['firstname'] ?? '').toString().toLowerCase();
      final lastName = (order['lastname'] ?? '').toString().toLowerCase();
      final clientName = '$firstName $lastName'.trim();
      final phone = (order['phone'] ?? '').toString();
      final project = (order['project_name'] ?? '').toString().toLowerCase();
      return code.contains(q) ||
          clientName.contains(q) ||
          phone.contains(q) ||
          project.contains(q);
    }).toList();
  }

  String _t(String key, AppLanguage lang) {
    return Localization.translate(key, lang);
  }

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return '';
    try {
      final dt = DateTime.parse(dateVal.toString()).toLocal();
      return DateFormat('yyyy-MM-dd HH:mm').format(dt);
    } catch (_) {
      return dateVal.toString();
    }
  }

  Future<void> _showAuditDetails(int logId, AppLanguage lang) async {
    final raw = await _db.readAuditLogDetails(logId);
    // Snapshots can hold a whole order with all its lines: format them off
    // the UI thread and render the lines lazily instead of one huge Text.
    final lines = raw.trim().isEmpty
        ? const <String>[]
        : await compute(_formatAuditDetailsLines, raw);
    if (!mounted) return;
    final controller = ScrollController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Localization.translate('audit_details_title', lang)),
        content: SizedBox(
          width: 760,
          height: MediaQuery.sizeOf(ctx).height * 0.6,
          child: lines.isEmpty
              ? Center(
                  child: Text(
                    Localization.translate('audit_details_empty', lang),
                  ),
                )
              : Directionality(
                  textDirection: TextDirection.ltr,
                  child: Scrollbar(
                    controller: controller,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: controller,
                      itemCount: lines.length,
                      itemBuilder: (_, i) => Text(
                        lines[i],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Localization.translate('audit_close', lang)),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _restoreOrder(int orderId, AppLanguage lang) async {
    if (!context.read<AppSettingsProvider>().canRestoreDeletedDocuments()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate('ليس لديك صلاحية الاسترجاع', lang),
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.restore_from_trash_rounded, color: Colors.teal),
            const SizedBox(width: 8),
            Text(_t('restore_order', lang)),
          ],
        ),
        content: Text(_t('confirm_restore', lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Localization.translate('cancel', lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('restore_order', lang)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _db.restoreCommande(orderId);
      widget.onOrderRestored?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('order_restored_successfully', lang)),
            backgroundColor: Colors.teal,
          ),
        );
        _loadTrashOrders();
      }
    }
  }

  Future<void> _permanentlyDeleteOrder(int orderId, AppLanguage lang) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text(_t('delete_permanently', lang)),
          ],
        ),
        content: Text(_t('confirm_permanent_delete', lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Localization.translate('cancel', lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('delete_permanently', lang)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _db.deleteCommandePermanently(orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('order_deleted_permanently', lang)),
            backgroundColor: Colors.red,
          ),
        );
        _loadTrashOrders();
      }
    }
  }

  /// Empties only the bin of the tab shown: orders, purchases or store
  /// sales.
  Future<void> _emptyTrash(AppLanguage lang) async {
    final tab = _tabController.index;
    if (tab == 2) {
      await _emptyMaterialSalesTrash(lang);
      return;
    }
    if (tab != 0 && tab != 1) return;
    final isAchats = tab == 1;
    if (isAchats ? _trashAchats.isEmpty : _trashOrders.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text(_t('empty_trash', lang)),
          ],
        ),
        content: Text(
          isAchats
              ? Localization.translate(
                  'هل أنت متأكد من تفريغ سلة فواتير الشراء نهائياً؟',
                  lang,
                )
              : _t('confirm_empty_trash', lang),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Localization.translate('cancel', lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('empty_trash', lang)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (isAchats) {
          await _db.emptyAchatTrash();
        } else {
          await _db.emptyTrash();
        }
      } catch (error) {
        debugPrint('Empty trash failed: $error');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isAchats
                  ? Localization.translate('تم تفريغ سلة فواتير الشراء', lang)
                  : _t('trash_emptied_successfully', lang),
            ),
            backgroundColor: Colors.red,
          ),
        );
        _loadTrashData();
      }
    }
  }

  Future<void> _emptyMaterialSalesTrash(AppLanguage lang) async {
    if (_trashMaterialSales.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Text(_t('empty_trash', lang)),
          ],
        ),
        content: Text(
          Localization.translate('trash_confirm_empty_material_sales', lang),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Localization.translate('cancel', lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('empty_trash', lang)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    var removed = 0;
    try {
      removed = await _db.emptyMaterialSalesTrash();
    } catch (error) {
      debugPrint('Empty store-sales trash failed: $error');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Localization.translate(
            'trash_material_sales_emptied',
            lang,
          ).replaceAll('{count}', '$removed'),
        ),
        backgroundColor: Colors.red,
      ),
    );
    _loadTrashData();
  }

  void _showOrderSummaryDialog(
    Map<String, dynamic> order,
    AppLanguage lang,
  ) async {
    final orderId = (order['id'] as num?)?.toInt() ?? 0;
    final items = await _db.readCommandeDetails(orderId);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.blue),
            const SizedBox(width: 8),
            Text(
              '${_t('Commande', lang)} #${order['order_code'] ?? order['id']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    Localization.translate('Aucun élément trouvé', lang),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.blue.withAlpha(30),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                      title: Text(
                        '${item['game'] ?? ''} - ${item['largeur']} × ${item['hauteur']} mm',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${Localization.translate('Quantité', lang)}: ${item['quantity']} | ${Localization.translate('Prix', lang)}: ${item['price'] ?? 0}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Localization.translate('Fermer', lang)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.restore_from_trash_rounded, size: 18),
            label: Text(_t('restore_order', lang)),
            onPressed: () {
              Navigator.pop(ctx);
              _restoreOrder(orderId, lang);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredOrders = _filteredOrders;
    final filteredAchats = _filteredAchats;
    final filteredMaterialSales = _filteredMaterialSales;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t('trash', lang),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark
            ? Theme.of(context).appBarTheme.backgroundColor
            : const Color(0xFFC0392B),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: [
            Tab(
              icon: const Icon(Icons.shopping_cart_outlined, size: 18),
              text:
                  '${Localization.translate('commandes', lang)} (${_trashOrders.length})',
            ),
            Tab(
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              text:
                  '${Localization.translate('achats', lang)} (${_trashAchats.length})',
            ),
            Tab(
              icon: const Icon(Icons.point_of_sale_rounded, size: 18),
              text:
                  '${Localization.translate('مبيعات المحل', lang)} (${_trashMaterialSales.length})',
            ),
            Tab(
              icon: const Icon(Icons.history_edu_rounded, size: 18),
              text: settings.canViewDocumentHistory()
                  ? '${_t('audit_tab_title', lang)} ($_auditTotal)'
                  : _t('audit_tab_title', lang),
            ),
          ],
        ),
        actions: [
          if ((_tabController.index == 0 && _trashOrders.isNotEmpty) ||
              (_tabController.index == 1 && _trashAchats.isNotEmpty) ||
              (_tabController.index == 2 && _trashMaterialSales.isNotEmpty))
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.delete_sweep_rounded, size: 20),
              label: Text(
                _t('empty_trash', lang),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => _emptyTrash(lang),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: Localization.translate('Actualiser', lang),
            onPressed: _loadTrashData,
          ),
        ],
      ),
      body: Column(
        children: [
          // 🔍 Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: Localization.translate('Rechercher', lang),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOrdersTab(context, filteredOrders, lang, isDark),
                _buildAchatsTab(context, filteredAchats, lang, isDark),
                _buildMaterialSalesTab(
                  context,
                  filteredMaterialSales,
                  lang,
                  isDark,
                  settings,
                ),
                _buildAuditLogsTab(context, lang, isDark, settings),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialSalesTab(
    BuildContext context,
    List<Map<String, dynamic>> filtered,
    AppLanguage lang,
    bool isDark,
    AppSettingsProvider settings,
  ) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          Localization.translate('لا توجد وثائق مبيعات محذوفة', lang),
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final sale = filtered[index];
        final id = (sale['id'] as num?)?.toInt() ?? 0;
        final total = (sale['net_total'] as num?)?.toDouble() ?? 0;
        return Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.point_of_sale_rounded),
            ),
            title: Text(
              '${sale['sale_code'] ?? '#$id'} — ${sale['client_name'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${NumberFormat('#,##0.00').format(total)} DZD\n'
              '${Localization.translate('حُذفت في', lang)}: ${_formatDate(sale['deleted_at'])}'
              '${(sale['deleted_by'] ?? '').toString().isEmpty ? '' : ' — ${sale['deleted_by']}'}',
            ),
            isThreeLine: true,
            trailing: settings.canRestoreDeletedDocuments()
                ? IconButton(
                    tooltip: Localization.translate('استعادة', lang),
                    icon: const Icon(
                      Icons.restore_from_trash_rounded,
                      color: Colors.teal,
                    ),
                    onPressed: () => _restoreMaterialSale(id, lang, settings),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildAchatsTab(
    BuildContext context,
    List<Map<String, dynamic>> filtered,
    AppLanguage lang,
    bool isDark,
  ) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 72,
              color: Colors.grey.withAlpha(120),
            ),
            const SizedBox(height: 16),
            Text(
              Localization.translate('سلة فواتير الشراء فارغة', lang),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              Localization.translate('لا توجد فواتير شراء محذوفة', lang),
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final achat = filtered[index];
        final achatId = (achat['id'] as num?)?.toInt() ?? 0;
        final invoiceNum = achat['invoice_number']?.toString() ?? '';
        final supplierName =
            achat['supplier_name']?.toString() ??
            achat['supplier_name_joined']?.toString() ??
            'مورد غير محدد';
        final total = (achat['total'] as num?)?.toDouble() ?? 0.0;
        final deletedAt = achat['deleted_at'];

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: Colors.red,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${Localization.translate('invoice_number', lang)}: $invoiceNum',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${Localization.translate('supplier', lang)}: $supplierName',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${NumberFormat('#,##0.00').format(total)} DZD',
                        style: const TextStyle(
                          color: Colors.blueGrey,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (deletedAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${_t('deleted_date', lang)}: ${_formatDate(deletedAt)}',
                          style: TextStyle(
                            color: Colors.red.shade400,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (achat['deleted_by'] != null &&
                          achat['deleted_by'].toString().trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${lang == AppLanguage.arabic ? "حُذفت بواسطة" : "Supprimé par"}: ${achat['deleted_by']}',
                          style: const TextStyle(
                            color: Colors.deepOrangeAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: Localization.translate('استعادة الفاتورة', lang),
                  icon: const Icon(
                    Icons.restore_from_trash_rounded,
                    color: Colors.teal,
                  ),
                  onPressed: () => _restoreAchat(achatId, lang),
                ),
                IconButton(
                  tooltip: _t('delete_permanently', lang),
                  icon: const Icon(
                    Icons.delete_forever_rounded,
                    color: Colors.red,
                  ),
                  onPressed: () => _permanentlyDeleteAchat(achatId, lang),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrdersTab(
    BuildContext context,
    List<Map<String, dynamic>> filtered,
    AppLanguage lang,
    bool isDark,
  ) {
    return Column(
      children: [
        if (_trashOrders.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withAlpha(35),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withAlpha(90)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lang == AppLanguage.arabic
                        ? 'الطلبيات في سلة المهملات لا تؤثر على حسابات الزبائن أو المخزن ويمكن استرجاعها في أي وقت.'
                        : (lang == AppLanguage.french
                              ? 'Les commandes dans la corbeille n\'affectent pas les soldes clients et peuvent être restaurées à tout moment.'
                              : 'Orders in trash do not affect client balances and can be restored at any time.'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.amber[200] : Colors.brown[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 72,
                        color: Colors.grey.withAlpha(120),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _t('trash_empty_message', lang),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t('no_deleted_orders', lang),
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final order = filtered[index];
                    final orderId = (order['id'] as num?)?.toInt() ?? 0;
                    final displayCode =
                        order['display_number'] ??
                        order['order_code'] ??
                        orderId;
                    final firstName = order['firstname'] ?? '';
                    final lastName = order['lastname'] ?? '';
                    final clientName = '$firstName $lastName'.trim();
                    final phone = order['phone'] ?? '';
                    final total = (order['total'] as num?)?.toDouble() ?? 0.0;
                    final netPayable =
                        (order['net_payable'] as num?)?.toDouble() ?? 0.0;
                    final displayAmount = netPayable > 0 ? netPayable : total;
                    final deletedAt = order['deleted_at'];
                    final createdAt = order['created_at'];

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 1.5,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withAlpha(25),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '#$displayCode',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    clientName.isNotEmpty
                                        ? clientName
                                        : _t('client_unspecified', lang),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${NumberFormat('#,##0.00').format(displayAmount)} DZD',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.amber[300]
                                        : Colors.blue[800],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            if (phone.isNotEmpty ||
                                (order['project_name'] ?? '')
                                    .toString()
                                    .isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  if (phone.isNotEmpty) ...[
                                    const Icon(
                                      Icons.phone_outlined,
                                      size: 14,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      phone,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  if ((order['project_name'] ?? '')
                                      .toString()
                                      .isNotEmpty) ...[
                                    const Icon(
                                      Icons.folder_outlined,
                                      size: 14,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      order['project_name'].toString(),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (createdAt != null) ...[
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.calendar_today_outlined,
                                        size: 13,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${Localization.translate('Date', lang)}: ${_formatDate(createdAt)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (deletedAt != null) ...[
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.delete_outline,
                                        size: 13,
                                        color: Colors.redAccent,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${_t('deleted_date', lang)}: ${_formatDate(deletedAt)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (order['deleted_by'] != null &&
                                    order['deleted_by']
                                        .toString()
                                        .trim()
                                        .isNotEmpty) ...[
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.person_outline_rounded,
                                        size: 13,
                                        color: Colors.deepOrangeAccent,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${lang == AppLanguage.arabic ? "حُذفت بواسطة" : "Supprimé par"}: ${order['deleted_by']}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.deepOrangeAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            const Divider(height: 16),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isCompact = constraints.maxWidth < 480;

                                final viewDetailsBtn = OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    Localization.translate(
                                      'afficher_les_elements',
                                      lang,
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onPressed: () =>
                                      _showOrderSummaryDialog(order, lang),
                                );

                                final restoreBtn = ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.restore_from_trash_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    _t('restore_order', lang),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onPressed: () => _restoreOrder(orderId, lang),
                                );

                                final deleteBtn = ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red[700],
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.delete_forever_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    _t('delete_permanently', lang),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onPressed: () =>
                                      _permanentlyDeleteOrder(orderId, lang),
                                );

                                if (isCompact) {
                                  return Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: restoreBtn),
                                          const SizedBox(width: 8),
                                          Expanded(child: deleteBtn),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: viewDetailsBtn,
                                      ),
                                    ],
                                  );
                                }

                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    viewDetailsBtn,
                                    const SizedBox(width: 8),
                                    restoreBtn,
                                    const SizedBox(width: 8),
                                    deleteBtn,
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAuditLogsTab(
    BuildContext context,
    AppLanguage lang,
    bool isDark,
    AppSettingsProvider settings,
  ) {
    // Only the workshop manager (or co-manager with full rights) and workers
    // explicitly granted `view_document_history` may read the log.
    if (!settings.canViewDocumentHistory()) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 64,
                color: Colors.grey.withAlpha(140),
              ),
              const SizedBox(height: 12),
              Text(
                _t('audit_no_permission', lang),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _t('audit_no_permission_hint', lang),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    if (!_auditLoaded && !_auditLoading) {
      // Permissions can arrive after the first frame (settings load async).
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAuditLoaded());
    }
    if (_auditLoading || !_auditLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_auditLogs.isEmpty) {
      final isSearching = _auditLoadedQuery.isNotEmpty;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearching
                  ? Icons.search_off_rounded
                  : Icons.history_edu_rounded,
              size: 72,
              color: Colors.grey.withAlpha(120),
            ),
            const SizedBox(height: 16),
            Text(
              _t(isSearching ? 'audit_no_results' : 'audit_empty_title', lang),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            if (!isSearching) ...[
              const SizedBox(height: 8),
              Text(
                _t('audit_empty_subtitle', lang),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ],
        ),
      );
    }

    final showFooter = _auditHasMore || _auditLoadingMore;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _t('audit_showing_count', lang)
                  .replaceAll('{shown}', '${_auditLogs.length}')
                  .replaceAll('{total}', '$_auditTotal'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _auditScrollController,
            child: ListView.builder(
              controller: _auditScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _auditLogs.length + (showFooter ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _auditLogs.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: _auditLoadingMore
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : TextButton.icon(
                              icon: const Icon(Icons.expand_more_rounded),
                              label: Text(_t('audit_load_more', lang)),
                              onPressed: _loadMoreAudit,
                            ),
                    ),
                  );
                }
                return _buildAuditLogCard(_auditLogs[index], lang, isDark);
              },
            ),
          ),
        ),
      ],
    );
  }

  (Color, IconData, String) _auditActionStyle(String actionType) {
    final type = actionType.toUpperCase();
    if (type.contains('DELETE')) {
      return (
        Colors.redAccent,
        Icons.delete_outline_rounded,
        'audit_action_delete',
      );
    }
    if (type.contains('RESTORE')) {
      return (
        Colors.teal,
        Icons.restore_from_trash_rounded,
        'audit_action_restore',
      );
    }
    if (type.contains('RETURN')) {
      return (
        Colors.deepPurple,
        Icons.assignment_return_rounded,
        'audit_action_return',
      );
    }
    if (type.contains('CONFIRM')) {
      return (
        Colors.green.shade700,
        Icons.verified_rounded,
        'audit_action_confirm',
      );
    }
    if (type.contains('UPDATE')) {
      return (
        Colors.amber.shade800,
        Icons.edit_note_rounded,
        'audit_action_update',
      );
    }
    if (type.contains('CREATE')) {
      return (
        Colors.blue.shade700,
        Icons.add_circle_outline_rounded,
        'audit_action_create',
      );
    }
    if (type.contains('STATUS')) {
      return (
        Colors.cyan.shade700,
        Icons.swap_horiz_rounded,
        'audit_action_status',
      );
    }
    if (type.contains('CLOSE')) {
      return (
        Colors.indigo,
        Icons.lock_clock_rounded,
        'audit_action_daily_close',
      );
    }
    return (Colors.blue, Icons.info_outline_rounded, 'audit_action_other');
  }

  String _auditEntityKey(String entityType) {
    switch (entityType.toLowerCase()) {
      case 'order':
        return 'audit_entity_order';
      case 'purchase':
        return 'audit_entity_purchase';
      case 'materialsale':
        return 'audit_entity_material_sale';
      case 'client':
        return 'audit_entity_client';
      case 'payment':
        return 'audit_entity_payment';
      case 'store':
        return 'audit_entity_store';
      case 'workshop':
        return 'audit_entity_workshop';
      default:
        return 'audit_entity_other';
    }
  }

  static final RegExp _arabicLetters = RegExp(r'[؀-ۿ]');
  static final RegExp _documentNumber = RegExp(r'#\s*(\S+)');

  /// Titles are stored in Arabic by the database layer ("طلبية #12 للزبون …").
  /// In French/English, rebuild them from the entity type and number.
  String _auditDisplayTitle(Map<String, dynamic> log, AppLanguage lang) {
    final rawTitle = (log['entity_title'] ?? '').toString().trim();
    final entityType = (log['entity_type'] ?? '').toString();
    final entityId = (log['entity_id'] ?? '').toString().trim();
    final entityLabel = _t(_auditEntityKey(entityType), lang);
    if (rawTitle.isEmpty) {
      return entityId.isEmpty ? entityLabel : '$entityLabel #$entityId';
    }
    // Codes such as a sale code or a closing date carry no type label.
    if (!_arabicLetters.hasMatch(rawTitle)) return '$entityLabel — $rawTitle';
    if (lang == AppLanguage.arabic) return rawTitle;
    final number =
        _documentNumber.firstMatch(rawTitle)?.group(1) ??
        rawTitle.split(RegExp(r'\s+')).last;
    return '$entityLabel #$number';
  }

  Widget _buildAuditLogCard(
    Map<String, dynamic> log,
    AppLanguage lang,
    bool isDark,
  ) {
    final logId = (log['id'] as num?)?.toInt() ?? 0;
    final (badgeColor, actionIcon, actionKey) = _auditActionStyle(
      (log['action_type'] ?? '').toString(),
    );
    final title = _auditDisplayTitle(log, lang);
    final rawUser = (log['user_name'] ?? '').toString().trim();
    final userName = rawUser.isEmpty ? _t('audit_unknown_user', lang) : rawUser;
    final preview = (log['details_preview'] ?? '').toString().trim();
    final hasDetails = ((log['has_details'] as num?)?.toInt() ?? 0) == 1;
    final timestamp = log['timestamp'];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: badgeColor.withAlpha(28),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(actionIcon, color: badgeColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _t(actionKey, lang),
                          style: TextStyle(
                            color: badgeColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.person_rounded,
                            size: 14,
                            color: Colors.blueGrey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            userName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                      if (timestamp != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 13,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDate(timestamp),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (hasDetails && logId != 0)
              IconButton(
                tooltip: _t('audit_view_details', lang),
                icon: const Icon(Icons.compare_arrows_rounded),
                onPressed: () => _showAuditDetails(logId, lang),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pretty-prints an audit payload (runs in a background isolate).
List<String> _formatAuditDetailsLines(String raw) {
  try {
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(jsonDecode(raw)).split('\n');
  } catch (_) {
    return raw.split('\n');
  }
}
