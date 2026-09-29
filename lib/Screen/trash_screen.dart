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

  const TrashScreen({super.key, this.db, this.onOrderRestored});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  late final SqlDatabase _db;
  bool _isLoading = true;
  List<Map<String, dynamic>> _trashOrders = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<String>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _db = widget.db ?? SqlDatabase();
    _loadTrashOrders();
    _syncSubscription = CloudSyncService().dbUpdateStream.listen((event) {
      if (mounted) {
        _loadTrashOrders();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadTrashOrders() async {
    setState(() => _isLoading = true);
    try {
      final orders = await _db.readTrashCommandesWithClients();
      if (mounted) {
        setState(() {
          _trashOrders = orders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
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
    if (_trashOrders.isEmpty) return;

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
        content: Text(_t('confirm_empty_trash', lang)),
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
      setState(() => _isLoading = true);
      final count = await _db.emptyTrash();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_t('trash_emptied_successfully', lang)} ($count)',
            ),
            backgroundColor: Colors.red[700],
          ),
        );
        _loadTrashOrders();
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
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredOrders;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _t('orders_trash', lang),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark
            ? Theme.of(context).appBarTheme.backgroundColor
            : const Color(0xFFC0392B),
        actions: [
          if (_trashOrders.isNotEmpty)
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
            onPressed: _loadTrashOrders,
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

          // ℹ️ Info Banner
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

          // 📋 Orders List
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
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: Colors.red.withAlpha(40),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top row: Code + Amount
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withAlpha(30),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '#$displayCode',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${displayAmount.toStringAsFixed(2)} DZD',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.teal,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Client name and phone
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.person_outline,
                                        size: 18,
                                        color: Colors.blueGrey,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          clientName.isEmpty
                                              ? Localization.translate(
                                                  'الزبون غير محدد',
                                                  lang,
                                                )
                                              : clientName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      if (phone.toString().isNotEmpty) ...[
                                        const Icon(
                                          Icons.phone_outlined,
                                          size: 16,
                                          color: Colors.grey,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          phone.toString(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),

                                  // Project if present
                                  if (order['project_name'] != null &&
                                      order['project_name'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.folder_outlined,
                                          size: 16,
                                          color: Colors.blueGrey,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          order['project_name'].toString(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.blueGrey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],

                                  const SizedBox(height: 8),
                                  const Divider(height: 1),
                                  const SizedBox(height: 8),

                                  // Dates info
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (createdAt != null)
                                        Text(
                                          '${Localization.translate('Date', lang)}: ${_formatDate(createdAt)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      if (deletedAt != null)
                                        Text(
                                          '${_t('deleted_date', lang)}: ${_formatDate(deletedAt)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.red[300],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                    ],
                                  ),

                                  const SizedBox(height: 10),

                                  // Action Buttons
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      // Details Button
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                        icon: const Icon(Icons.list_alt, size: 16),
                                        label: Text(
                                          Localization.translate(
                                            'Détails',
                                            lang,
                                          ),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        onPressed: () =>
                                            _showOrderSummaryDialog(order, lang),
                                      ),
                                      const SizedBox(width: 8),

                                      // Restore Button
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.teal,
                                          foregroundColor: Colors.white,
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
                                          Icons.restore_from_trash_rounded,
                                          size: 16,
                                        ),
                                        label: Text(
                                          _t('restore_order', lang),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        onPressed: () =>
                                            _restoreOrder(orderId, lang),
                                      ),
                                      const SizedBox(width: 8),

                                      // Delete Permanently Button
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red[700],
                                          foregroundColor: Colors.white,
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
                                          Icons.delete_forever_rounded,
                                          size: 16,
                                        ),
                                        label: Text(
                                          _t('delete_permanently', lang),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        onPressed: () =>
                                            _permanentlyDeleteOrder(orderId, lang),
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
    );
  }
}
