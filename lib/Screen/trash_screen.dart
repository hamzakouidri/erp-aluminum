import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/cloud_sync_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';

class TrashScreen extends StatefulWidget {
  final SqlDatabase? db;
  final VoidCallback? onOrderRestored;
  final int initialIndex;

  const TrashScreen({super.key, this.db, this.onOrderRestored, this.initialIndex = 0});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> with SingleTickerProviderStateMixin {
  late final SqlDatabase _db;
  late final TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _trashOrders = [];
  List<Map<String, dynamic>> _trashAchats = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<String>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _db = widget.db ?? SqlDatabase();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 1),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadTrashData();
    _syncSubscription = CloudSyncService().dbUpdateStream.listen((event) {
      if (mounted) {
        _loadTrashOrders();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadTrashData() async {
    setState(() => _isLoading = true);
    try {
      final orders = await _db.readTrashCommandesWithClients();
      final achats = await _db.readTrashAchats();
      if (mounted) {
        setState(() {
          _trashOrders = orders;
          _trashAchats = achats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadTrashOrders() => _loadTrashData();

  List<Map<String, dynamic>> get _filteredAchats {
    if (_searchQuery.trim().isEmpty) return _trashAchats;
    final q = _searchQuery.trim().toLowerCase();
    return _trashAchats.where((achat) {
      final num = (achat['invoice_number'] ?? '').toString().toLowerCase();
      final sup = (achat['supplier_name'] ?? achat['supplier_name_joined'] ?? '').toString().toLowerCase();
      return num.contains(q) || sup.contains(q);
    }).toList();
  }

  Future<void> _restoreAchat(int achatId, AppLanguage lang) async {
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
        content: Text(Localization.translate('هل ترغب في استعادة فاتورة الشراء هذه؟', lang)),
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
            content: Text(Localization.translate('تمت استعادة الفاتورة بنجاح', lang)),
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
        content: Text(Localization.translate('هل أنت متأكد من الحذف النهائي لفاتورة الشراء؟ لا يمكن التراجع عن هذا الإجراء.', lang)),
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
              content: Text(Localization.translate('تم حذف الفاتورة نهائياً', lang)),
              backgroundColor: Colors.red,
            ),
          );
          _loadTrashData();
        }
      } catch (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(''),
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

  Future<void> _restoreOrder(int orderId, AppLanguage lang) async {
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

  Future<void> _emptyTrash(AppLanguage lang) async {
    final isAchats = _tabController.index == 1;
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
              ? Localization.translate('هل أنت متأكد من تفريغ سلة فواتير الشراء نهائياً؟', lang)
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
      if (isAchats) {
        await _db.emptyAchatTrash();
      } else {
        await _db.emptyTrash();
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

  void _showOrderSummaryDialog(Map<String, dynamic> order, AppLanguage lang) async {
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
                          style: const TextStyle(fontSize: 12, color: Colors.blue),
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
  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredOrders = _filteredOrders;
    final filteredAchats = _filteredAchats;

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
              text: '${Localization.translate('commandes', lang)} (${_trashOrders.length})',
            ),
            Tab(
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              text: '${Localization.translate('achats', lang)} (${_trashAchats.length})',
            ),
          ],
        ),
        actions: [
          if ((_tabController.index == 0 && _trashOrders.isNotEmpty) ||
              (_tabController.index == 1 && _trashAchats.isNotEmpty))
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
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: Localization.translate('Rechercher', lang),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              ],
            ),
          ),
        ],
      ),
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
              style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
              ),
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
        final supplierName = achat['supplier_name']?.toString() ??
            achat['supplier_name_joined']?.toString() ??
            'مورد غير محدد';
        final total = (achat['total'] as num?)?.toDouble() ?? 0.0;
        final deletedAt = achat['deleted_at'];

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${Localization.translate('supplier', lang)}: $supplierName',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
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
                          style: TextStyle(color: Colors.red.shade400, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: Localization.translate('استعادة الفاتورة', lang),
                  icon: const Icon(Icons.restore_from_trash_rounded, color: Colors.teal),
                  onPressed: () => _restoreAchat(achatId, lang),
                ),
                IconButton(
                  tooltip: _t('delete_permanently', lang),
                  icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
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
                            order['display_number'] ?? order['order_code'] ?? orderId;
                        final firstName = order['firstname'] ?? '';
                        final lastName = order['lastname'] ?? '';
                        final clientName = '$firstName $lastName'.trim();
                        final phone = order['phone'] ?? '';
                        final total = (order['total'] as num?)?.toDouble() ?? 0.0;
                        final netPayable =
                            (order['net_payable'] as num?)?.toDouble() ?? 0.0;
                        final displayAmount =
                            netPayable > 0 ? netPayable : total;
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
                                if (phone.isNotEmpty || (order['project_name'] ?? '').toString().isNotEmpty) ...[
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
                                      if ((order['project_name'] ?? '').toString().isNotEmpty) ...[
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
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                                      onPressed: () =>
                                          _restoreOrder(orderId, lang),
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
                                          borderRadius:
                                              BorderRadius.circular(8),
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
}
