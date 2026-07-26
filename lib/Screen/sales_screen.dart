import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:intl/intl.dart' hide TextDirection;
import '../Commande/add_commande.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

class SalesScreen extends StatefulWidget {
  final SqlDatabase db;

  const SalesScreen({super.key, required this.db});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allOrders = [];
  List<Map<String, dynamic>> _allDeliveries = [];
  final NumberFormat _currencyFormatter = NumberFormat('#,##0.00');

  // Active filter tab:
  // 'all' | 'confirmed' | 'partial_manufacturing' | 'full_manufacturing'
  // | 'partial_distribution' | 'full_distribution' | 'installed' | 'reserve' | 'finished' | 'partial'
  String _selectedTab = 'all';

  @override
  void initState() {
    super.initState();
    _loadSalesData();
  }

  String _tr(String ar, String fr, String en, AppLanguage lang) {
    switch (lang) {
      case AppLanguage.french:
        return fr;
      case AppLanguage.english:
        return en;
      case AppLanguage.arabic:
        return ar;
    }
  }

  Future<void> _loadSalesData() async {
    setState(() => _isLoading = true);
    try {
      final myDb = await widget.db.db;

      // 1. Fetch all orders with client name info (Exclude Pending from sales metrics)
      final ordersRaw = await myDb!.rawQuery('''
        SELECT co.*, c.firstname, c.lastname FROM Commandes co
        JOIN Client c ON co.client_id = c.id
        ORDER BY co.created_at DESC
      ''');

      // 2. Fetch all delivery notes with client name info (Strictly exclude Pending orders!)
      final deliveriesRaw = await myDb.rawQuery('''
        SELECT cd.*, co.status as order_status, co.total as order_total, co.net_payable as order_net_payable, c.firstname, c.lastname FROM Commandes_deliveries cd
        JOIN Commandes co ON cd.id_commandes = co.id
        JOIN Client c ON cd.client_id = c.id
        WHERE LOWER(TRIM(co.status)) NOT IN ('pending', 'في حالة انتظار')
        ORDER BY cd.delivery_date DESC
      ''');

      setState(() {
        _allOrders = List<Map<String, dynamic>>.from(ordersRaw);
        _allDeliveries = List<Map<String, dynamic>>.from(deliveriesRaw);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء تحميل المبيعات: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Active status set that excludes 'pending' / 'في حالة انتظار'
  static const _activeStatuses = {
    'confirmed',
    'in progress',
    'done',
    'installation',
    'installed',
    'delivered',
    'partial manufacturing',
    'full manufacturing',
    'partial distribution',
    'full distribution',
    'reserve',
    'reserved',
    'finished',
    'completed',
    'archived',
    'أرشيف',
    'منتهية',
  };

  // Get list of orders for the selected status tab
  List<Map<String, dynamic>> get _filteredOrders {
    final active = _allOrders.where((o) {
      final s = (o['status'] ?? '').toString().toLowerCase().trim();
      return _activeStatuses.contains(s) && s != 'pending' && s != 'في حالة انتظار';
    }).toList();

    if (_selectedTab == 'all') {
      return active;
    } else if (_selectedTab == 'confirmed') {
      return active.where((o) => (o['status'] ?? '').toString().toLowerCase().trim() == 'confirmed').toList();
    } else if (_selectedTab == 'partial_manufacturing') {
      return active.where((o) => (o['status'] ?? '').toString().toLowerCase().trim() == 'partial manufacturing').toList();
    } else if (_selectedTab == 'full_manufacturing') {
      return active.where((o) => (o['status'] ?? '').toString().toLowerCase().trim() == 'full manufacturing').toList();
    } else if (_selectedTab == 'partial_distribution') {
      return active.where((o) => (o['status'] ?? '').toString().toLowerCase().trim() == 'partial distribution').toList();
    } else if (_selectedTab == 'full_distribution') {
      return active.where((o) => (o['status'] ?? '').toString().toLowerCase().trim() == 'full distribution').toList();
    } else if (_selectedTab == 'installed') {
      return active.where((o) {
        final s = (o['status'] ?? '').toString().toLowerCase().trim();
        return s == 'installation' || s == 'installed';
      }).toList();
    } else if (_selectedTab == 'reserve') {
      return active.where((o) {
        final s = (o['status'] ?? '').toString().toLowerCase().trim();
        return s == 'reserve' || s == 'reserved';
      }).toList();
    } else if (_selectedTab == 'finished') {
      return active.where((o) {
        final s = (o['status'] ?? '').toString().toLowerCase().trim();
        return s == 'finished' || s == 'completed' || s == 'archived' || s == 'done' || s == 'أرشيف' || s == 'منتهية';
      }).toList();
    }
    return active;
  }

  // Group deliveries by order ID for partial sales calculations
  Map<int, List<Map<String, dynamic>>> get _groupedDeliveries {
    final Map<int, List<Map<String, dynamic>>> grouped = {};
    for (final del in _allDeliveries) {
      final orderStatus = (del['order_status'] ?? '').toString().toLowerCase().trim();
      if (orderStatus == 'pending' || orderStatus == 'في حالة انتظار') continue;

      final orderId = del['id_commandes'] as int;
      grouped.putIfAbsent(orderId, () => []).add(del);
    }
    return grouped;
  }

  // Compute stats based on the active tab
  double get _totalSalesAmount {
    if (_selectedTab == 'partial') {
      // Sum of all partial deliveries for active orders
      return _allDeliveries.fold(0.0, (sum, del) => sum + ((del['total_amount'] as num?)?.toDouble() ?? 0.0));
    } else {
      // Sum of filtered active orders
      return _filteredOrders.fold(0.0, (sum, o) {
        final netPayable = (o['net_payable'] as num?)?.toDouble() ?? 0.0;
        final rawTotal = (o['total'] as num?)?.toDouble() ?? 0.0;
        return sum + (netPayable > 0 ? netPayable : rawTotal);
      });
    }
  }

  String _translateStatus(String? status, AppLanguage lang) {
    if (status == null || status.isEmpty) return '';
    final lower = status.trim().toLowerCase();
    switch (lower) {
      case 'confirmed':
        return _tr('المؤكدة', 'Confirmée', 'Confirmed', lang);
      case 'partial manufacturing':
        return _tr('التصنيع الجزئي', 'Fab. Partielle', 'Partial Mfg', lang);
      case 'full manufacturing':
        return _tr('التصنيع الكلي', 'Fab. Totale', 'Full Mfg', lang);
      case 'partial distribution':
        return _tr('التوزيع الجزئي', 'Dist. Partielle', 'Partial Dist', lang);
      case 'full distribution':
        return _tr('التوزيع الكلي', 'Dist. Totale', 'Full Dist', lang);
      case 'installation':
      case 'installed':
        return _tr('المركبة', 'Installée', 'Installed', lang);
      case 'reserve':
      case 'reserved':
        return _tr('المحجوزة', 'Réservée', 'Reserved', lang);
      case 'finished':
      case 'completed':
      case 'archived':
      case 'done':
      case 'أرشيف':
      case 'منتهية':
        return _tr('المنتهية / المؤرشفة', 'Terminée / Archivée', 'Finished / Archived', lang);
      case 'pending':
      case 'في حالة انتظار':
        return _tr('قيد الانتظار', 'En Attente', 'Pending', lang);
      default:
        return Localization.translate(status, lang);
    }
  }

  String _statCardTitle(AppLanguage lang) {
    switch (_selectedTab) {
      case 'all':
        return _tr('إجمالي كل المبيعات المؤكدة', 'Total ventes confirmées', 'Total Confirmed Sales', lang);
      case 'confirmed':
        return _tr('إجمالي الطلبيات المؤكدة', 'Total commandes confirmées', 'Total Confirmed Orders', lang);
      case 'partial_manufacturing':
        return _tr('إجمالي التصنيع الجزئي', 'Total Fab. Partielle', 'Total Partial Mfg', lang);
      case 'full_manufacturing':
        return _tr('إجمالي التصنيع الكلي', 'Total Fab. Totale', 'Total Full Mfg', lang);
      case 'partial_distribution':
        return _tr('إجمالي التوزيع الجزئي', 'Total Dist. Partielle', 'Total Partial Dist', lang);
      case 'full_distribution':
        return _tr('إجمالي التوزيع الكلي', 'Total Dist. Totale', 'Total Full Dist', lang);
      case 'installed':
        return _tr('إجمالي الطلبيات المركبة', 'Total installées', 'Total Installed', lang);
      case 'reserve':
        return _tr('إجمالي المحجوزة / حجز', 'Total réservées', 'Total Reserved', lang);
      case 'finished':
        return _tr('إجمالي الطلبيات المنتهية', 'Total terminées', 'Total Finished', lang);
      case 'partial':
        return _tr('إجمالي المبيعات الجزئية المسلمة', 'Total livraisons partielles', 'Total Partial Deliveries', lang);
      default:
        return _tr('إجمالي المبيعات', 'Total des ventes', 'Total Sales', lang);
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.15), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.grey,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.teal.shade300 : color,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String id, String label, IconData icon, Color activeColor) {
    final isSelected = _selectedTab == id;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color borderColor = isSelected
        ? (isDark ? Colors.blue : activeColor)
        : (isDark ? Colors.grey.shade800 : Colors.grey.shade300);
    final Color textColor = isSelected
        ? (isDark ? Colors.blue : activeColor)
        : (isDark ? Colors.white70 : Colors.black87);
    final Color iconColor = isSelected
        ? (isDark ? Colors.blue : activeColor)
        : (isDark ? Colors.white54 : Colors.grey);
    final Color bgColor = isDark
        ? (isSelected ? Colors.blue.withOpacity(0.08) : Theme.of(context).cardColor)
        : (isSelected ? activeColor.withOpacity(0.08) : Colors.white);

    return GestureDetector(
      onTap: () => setState(() => _selectedTab = id),
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 10,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isRtl = lang == AppLanguage.arabic;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            _tr('صفحة المبيعات والطلبيات', 'Ventes & Commandes', 'Sales & Orders', lang),
            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.blueGrey.shade900,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadSalesData,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Dynamic total sales banner
                    _buildStatCard(
                      _statCardTitle(lang),
                      '${_currencyFormatter.format(_totalSalesAmount)} دج',
                      Icons.account_balance_wallet_rounded,
                      Colors.teal.shade700,
                    ),
                    const SizedBox(height: 14),

                    // Status filter tabs row — 10 status buttons starting from Confirmed
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildTabButton('all',                  _tr('الكل', 'Tous', 'All', lang),                                Icons.list_alt_rounded,            Colors.indigo),
                          const SizedBox(width: 6),
                          _buildTabButton('confirmed',            _tr('المؤكدة', 'Confirmée', 'Confirmed', lang),                 Icons.check_circle_outline,        Colors.blue),
                          const SizedBox(width: 6),
                          _buildTabButton('partial_manufacturing', _tr('التصنيع الجزئي', 'Fab. Partielle', 'Partial Mfg', lang),    Icons.precision_manufacturing_rounded, Colors.amber),
                          const SizedBox(width: 6),
                          _buildTabButton('full_manufacturing',    _tr('التصنيع الكلي', 'Fab. Totale', 'Full Mfg', lang),         Icons.build,                       Colors.green),
                          const SizedBox(width: 6),
                          _buildTabButton('partial_distribution',  _tr('التوزيع الجزئي', 'Dist. Partielle', 'Partial Dist', lang),  Icons.delivery_dining_outlined,    Colors.deepOrange),
                          const SizedBox(width: 6),
                          _buildTabButton('full_distribution',     _tr('التوزيع الكلي', 'Dist. Totale', 'Full Dist', lang),       Icons.local_shipping_rounded,      Colors.teal),
                          const SizedBox(width: 6),
                          _buildTabButton('installed',            _tr('المركبة', 'Installée', 'Installed', lang),                 Icons.home_repair_service_rounded, Colors.purple),
                          const SizedBox(width: 6),
                          _buildTabButton('reserve',              _tr('المحجوزة / حجز', 'Réservée', 'Reserved', lang),            Icons.bookmark,                    Colors.brown),
                          const SizedBox(width: 6),
                          _buildTabButton('finished',             _tr('المنتهية / المؤرشفة', 'Terminée', 'Finished', lang),       Icons.task_alt_rounded,            Colors.blueGrey),
                          const SizedBox(width: 6),
                          _buildTabButton('partial',              _tr('المبيعات الجزئية', 'Ventes Partielles', 'Partial Sales', lang), Icons.receipt_long_rounded,       Colors.cyan),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Orders / Partial Deliveries list
                    Expanded(
                      child: _selectedTab == 'partial'
                          ? _buildPartialDeliveriesList(lang)
                          : _buildOrdersList(lang),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildOrdersList(AppLanguage lang) {
    final list = _filteredOrders;
    if (list.isEmpty) {
      return Center(
        child: Text(
          _tr('لا توجد طلبيات مطابقة لهذا التصنيف.', 'Aucune commande trouvée.', 'No matching orders found.', lang),
          style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Cairo'),
        ),
      );
    }

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, idx) {
        final order = list[idx];
        final clientName = '${order['firstname']} ${order['lastname']}'.trim();
        final netPayable = (order['net_payable'] as num?)?.toDouble() ?? 0.0;
        final rawTotal = (order['total'] as num?)?.toDouble() ?? 0.0;
        final total = netPayable > 0 ? netPayable : rawTotal;
        final date = order['created_at']?.toString().split('T')[0] ?? '';

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: Colors.blue.withOpacity(0.15),
              child: const Icon(Icons.receipt, color: Colors.blue),
            ),
            title: Text(
              '${_tr('طلب', 'Commande', 'Order', lang)} #${order['id']} - $clientName',
              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
            ),
            subtitle: Text(
              '${_tr('التاريخ', 'Date', 'Date', lang)}: $date  ·  ${_tr('الحالة', 'Statut', 'Status', lang)}: ${_translateStatus(order['status']?.toString(), lang)}',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color),
            ),
            trailing: Text(
              '${_currencyFormatter.format(total)} دج',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CommandePage(
                    db: widget.db,
                    editCommandeId: order['id'] as int,
                  ),
                ),
              ).then((_) => _loadSalesData());
            },
          ),
        );
      },
    );
  }

  Widget _buildPartialDeliveriesList(AppLanguage lang) {
    final grouped = _groupedDeliveries;
    if (grouped.isEmpty) {
      return Center(
        child: Text(
          _tr('لا توجد فواتير تسليم جزئية مسجلة حالياً.', 'Aucune livraison partielle.', 'No partial deliveries found.', lang),
          style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Cairo'),
        ),
      );
    }

    final parentIds = grouped.keys.toList();

    return ListView.builder(
      itemCount: parentIds.length,
      itemBuilder: (context, idx) {
        final orderId = parentIds[idx];
        final deliveries = grouped[orderId]!;

        final parentOrder = _allOrders.firstWhere((o) => o['id'] == orderId, orElse: () => {});
        final clientName = parentOrder.isNotEmpty
            ? '${parentOrder['firstname']} ${parentOrder['lastname']}'.trim()
            : _tr('زبون غير معروف', 'Client inconnu', 'Unknown client', lang);

        final netPayable = parentOrder.isNotEmpty
            ? ((parentOrder['net_payable'] as num?)?.toDouble() ?? 0.0)
            : 0.0;
        final rawTotal = parentOrder.isNotEmpty
            ? ((parentOrder['total'] as num?)?.toDouble() ?? 0.0)
            : 0.0;
        final orderTotal = netPayable > 0 ? netPayable : rawTotal;

        final sumDeliveries = deliveries.fold(0.0, (sum, d) => sum + ((d['total_amount'] as num?)?.toDouble() ?? 0.0));
        final isCompleted = sumDeliveries >= orderTotal && orderTotal > 0;

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 3,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: Colors.teal.withOpacity(0.15),
                child: const Icon(Icons.delivery_dining, color: Colors.teal),
              ),
              title: Text(
                '${_tr('طلب', 'Commande', 'Order', lang)} #$orderId - $clientName',
                style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14),
              ),
              subtitle: Builder(
                builder: (tileCtx) {
                  final isDark = Theme.of(tileCtx).brightness == Brightness.dark;
                  final badgeBg = isCompleted
                      ? (isDark ? Colors.green.withOpacity(0.15) : Colors.green.shade50)
                      : (isDark ? Colors.orange.withOpacity(0.15) : Colors.orange.shade50);
                  final badgeText = isCompleted
                      ? (isDark ? Colors.green.shade300 : Colors.green.shade800)
                      : (isDark ? Colors.orange.shade300 : Colors.orange.shade800);
                  final badgeBorder = isCompleted ? Colors.green : Colors.orange;

                  return Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        '${_tr('قيمة الطلب', 'Montant', 'Amount', lang)}: ${_currencyFormatter.format(orderTotal)} دج  ·  ${_tr('مجموع المسلّم', 'Livré', 'Delivered', lang)}: ${_currencyFormatter.format(sumDeliveries)} دج',
                        style: TextStyle(fontSize: 11, fontFamily: 'Cairo', color: Theme.of(tileCtx).textTheme.bodySmall?.color),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: badgeBorder),
                        ),
                        child: Text(
                          isCompleted
                              ? _tr('مكتملة بالكامل', 'Livrée totalement', 'Fully Delivered', lang)
                              : _tr('غير جاهزة كلياً (جزئية)', 'Livraison partielle', 'Partial Delivery', lang),
                          style: TextStyle(
                            fontSize: 9,
                            color: badgeText,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              children: [
                const Divider(height: 1),
                Builder(
                  builder: (tileCtx) {
                    final isDark = Theme.of(tileCtx).brightness == Brightness.dark;
                    return Container(
                      color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      child: Column(
                        children: deliveries.map((d) {
                          final delDate = d['delivery_date']?.toString().split('T')[0] ?? '';
                          final delAmount = (d['total_amount'] as num?)?.toDouble() ?? 0.0;

                          List<dynamic> items = [];
                          try {
                            final rawItems = d['items_json'];
                            if (rawItems != null) {
                              if (rawItems is List) {
                                items = rawItems;
                              } else {
                                items = jsonDecode(rawItems.toString()) as List<dynamic>;
                              }
                            }
                          } catch (_) {}

                          final itemsSummary = items.map((i) => '${i['game'] ?? 'Window'} (${i['qty'] ?? 1}x)').join(', ');

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.circle, size: 6, color: Colors.teal),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_tr('تاريخ التسليم', 'Date livraison', 'Delivery date', lang)}: $delDate',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          fontFamily: 'Cairo',
                                          color: Theme.of(tileCtx).textTheme.bodyLarge?.color,
                                        ),
                                      ),
                                      if (itemsSummary.isNotEmpty)
                                        Text(
                                          '${_tr('القطع', 'Pièces', 'Items', lang)}: $itemsSummary',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark ? Colors.white70 : Colors.grey.shade600,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${_currencyFormatter.format(delAmount)} دج',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
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
}
