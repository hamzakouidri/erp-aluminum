import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../Commande/add_commande.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../Commande/commande.dart'; // To navigate to order details if needed

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
  
  // Active filter tab: 'all' | 'confirmed' | 'manufactured' | 'installed' | 'partial'
  String _selectedTab = 'all';

  @override
  void initState() {
    super.initState();
    _loadSalesData();
  }

  Future<void> _loadSalesData() async {
    setState(() => _isLoading = true);
    try {
      final myDb = await widget.db.db;
      
      // Fetch all orders with client name info
      final ordersRaw = await myDb!.rawQuery('''
        SELECT co.*, c.firstname, c.lastname FROM Commandes co
        JOIN Client c ON co.client_id = c.id
        ORDER BY co.created_at DESC
      ''');
      
      // Fetch all delivery notes with client name info
      final deliveriesRaw = await myDb.rawQuery('''
        SELECT cd.*, co.status as order_status, co.total as order_total, co.net_payable as order_net_payable, c.firstname, c.lastname FROM Commandes_deliveries cd
        JOIN Commandes co ON cd.id_commandes = co.id
        JOIN Client c ON cd.client_id = c.id
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

  // الحالات التي تُعدّ «مؤكدة أو أكثر» (تستبعد غير المؤكدة)
  static const _activeStatuses = {
    'confirmed',
    'in progress',
    'done',
    'installation',
    'delivered',
    'partial manufacturing',
    'full manufacturing',
    'partial distribution',
    'full distribution'
  };

  // Get list of orders for the selected status tab
  List<Map<String, dynamic>> get _filteredOrders {
    if (_selectedTab == 'all') {
      // الكل: كل الطلبيات المؤكدة أو المصنعة أو المركبة أو المنتهية
      return _allOrders.where((o) {
        final s = (o['status'] ?? '').toString().toLowerCase().trim();
        return _activeStatuses.contains(s);
      }).toList();
    } else if (_selectedTab == 'confirmed') {
      return _allOrders.where((o) => (o['status'] ?? '').toString().toLowerCase() == 'confirmed').toList();
    } else if (_selectedTab == 'manufactured') {
      return _allOrders.where((o) {
        final s = (o['status'] ?? '').toString().toLowerCase();
        return s == 'in progress' || s == 'done' || s == 'full manufacturing' || s == 'partial manufacturing';
      }).toList();
    } else if (_selectedTab == 'installed') {
      return _allOrders.where((o) {
        final s = (o['status'] ?? '').toString().toLowerCase();
        return s == 'installation' || s == 'done';
      }).toList();
    } else if (_selectedTab == 'partial_manufacturing') {
      return _allOrders.where((o) => (o['status'] ?? '').toString().toLowerCase().trim() == 'partial manufacturing').toList();
    } else if (_selectedTab == 'full_manufacturing') {
      return _allOrders.where((o) => (o['status'] ?? '').toString().toLowerCase().trim() == 'full manufacturing').toList();
    } else if (_selectedTab == 'partial_distribution') {
      return _allOrders.where((o) => (o['status'] ?? '').toString().toLowerCase().trim() == 'partial distribution').toList();
    } else if (_selectedTab == 'full_distribution') {
      return _allOrders.where((o) => (o['status'] ?? '').toString().toLowerCase().trim() == 'full distribution').toList();
    }
    return [];
  }

  // Group deliveries by order ID for partial sales calculations
  Map<int, List<Map<String, dynamic>>> get _groupedDeliveries {
    final Map<int, List<Map<String, dynamic>>> grouped = {};
    for (final del in _allDeliveries) {
      final orderId = del['id_commandes'] as int;
      grouped.putIfAbsent(orderId, () => []).add(del);
    }
    return grouped;
  }

  // Compute stats based on the active tab
  double get _totalSalesAmount {
    if (_selectedTab == 'partial') {
      // Sum of all partial deliveries
      return _allDeliveries.fold(0.0, (sum, del) => sum + ((del['total_amount'] as num?)?.toDouble() ?? 0.0));
    } else {
      // Sum of filtered orders
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
        return Localization.translate('Confirmed', lang);
      case 'in progress':
        return Localization.translate('In Progress', lang);
      case 'done':
        return Localization.translate('Done', lang);
      case 'installation':
        return Localization.translate('Installation', lang);
      case 'delivered':
        return Localization.translate('Delivered', lang);
      case 'pending':
        return Localization.translate('Pending', lang);
      case 'partial manufacturing':
        return Localization.translate('Partial Manufacturing', lang);
      case 'full manufacturing':
        return Localization.translate('Full Manufacturing', lang);
      case 'partial distribution':
        return Localization.translate('Partial Distribution', lang);
      case 'full distribution':
        return Localization.translate('Full Distribution', lang);
      default:
        return Localization.translate(status, lang);
    }
  }

  String _statCardTitle(AppLanguage lang) {
    switch (_selectedTab) {
      case 'all':                  return Localization.translate('إجمالي كل المبيعات المؤكدة', lang);
      case 'confirmed':            return Localization.translate('إجمالي الطلبيات المؤكدة', lang);
      case 'manufactured':         return Localization.translate('إجمالي الطلبيات المصنعة', lang);
      case 'installed':            return Localization.translate('إجمالي الطلبيات المركبة', lang);
      case 'partial':              return Localization.translate('إجمالي المبيعات الجزئية المسلمة', lang);
      case 'partial_manufacturing': return Localization.translate('Partial Manufacturing', lang);
      case 'full_manufacturing':    return Localization.translate('Full Manufacturing', lang);
      case 'partial_distribution':  return Localization.translate('Partial Distribution', lang);
      case 'full_distribution':     return Localization.translate('Full Distribution', lang);
      default:                     return Localization.translate('إجمالي المبيعات', lang);
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
                    fontFamily: 'Cairo'
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
                      fontFamily: 'Cairo'
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
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
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
            Localization.translate('vente', lang),
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
                    // Dynamic premium total sales banner
                    _buildStatCard(
                      _statCardTitle(lang),
                      '${_totalSalesAmount.toStringAsFixed(2)} دج',
                      Icons.account_balance_wallet_rounded,
                      Colors.teal.shade700,
                    ),
                    const SizedBox(height: 16),

                    // Filter tabs row – scrollable for all status buttons
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildTabButton('all',                  Localization.translate('الكل', lang),                     Icons.list_alt_rounded,            Colors.indigo),
                          const SizedBox(width: 8),
                          _buildTabButton('confirmed',            Localization.translate('المؤكدة', lang),                  Icons.check_circle_outline,        Colors.blue),
                          const SizedBox(width: 8),
                          _buildTabButton('partial_manufacturing', Localization.translate('Partial Manufacturing', lang),     Icons.precision_manufacturing_rounded, Colors.amber),
                          const SizedBox(width: 8),
                          _buildTabButton('full_manufacturing',    Localization.translate('Full Manufacturing', lang),        Icons.build,                       Colors.green),
                          const SizedBox(width: 8),
                          _buildTabButton('partial_distribution',  Localization.translate('Partial Distribution', lang),     Icons.delivery_dining_outlined,    Colors.deepOrange),
                          const SizedBox(width: 8),
                          _buildTabButton('full_distribution',     Localization.translate('Full Distribution', lang),        Icons.local_shipping_rounded,      Colors.teal),
                          const SizedBox(width: 8),
                          _buildTabButton('installed',            Localization.translate('المركبة', lang),                  Icons.home_repair_service_rounded,  Colors.purple),
                          const SizedBox(width: 8),
                          _buildTabButton('partial',              Localization.translate('المبيعات الجزئية', lang),         Icons.receipt_long_rounded,        Colors.cyan),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Content list view
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

  // Build standard list for confirmed, manufactured, and installed tabs
  Widget _buildOrdersList(AppLanguage lang) {
    final list = _filteredOrders;
    if (list.isEmpty) {
      return Center(
        child: Text(
          Localization.translate('لا توجد طلبيات مطابقة لهذا التصنيف.', lang),
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
              '${Localization.translate('طلب', lang)} #${order['id']} - $clientName',
              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
            ),
            subtitle: Text(
              '${Localization.translate('التاريخ', lang)}: $date  ·  ${Localization.translate('الحالة', lang)}: ${_translateStatus(order['status']?.toString(), lang)}',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color),
            ),
            trailing: Text(
              '${total.toStringAsFixed(2)} دج',
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

  // Build partial deliveries view grouped under parent orders
  Widget _buildPartialDeliveriesList(AppLanguage lang) {
    final grouped = _groupedDeliveries;
    if (grouped.isEmpty) {
      return Center(
        child: Text(
          Localization.translate('لا توجد فواتير تسليم جزئية مسجلة حالياً.', lang),
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
        
        // Find parent order info
        final parentOrder = _allOrders.firstWhere((o) => o['id'] == orderId, orElse: () => {});
        final clientName = parentOrder.isNotEmpty
            ? '${parentOrder['firstname']} ${parentOrder['lastname']}'.trim()
            : Localization.translate('زبون غير معروف', lang);
        
        final netPayable = parentOrder.isNotEmpty
            ? ((parentOrder['net_payable'] as num?)?.toDouble() ?? 0.0)
            : 0.0;
        final rawTotal = parentOrder.isNotEmpty
            ? ((parentOrder['total'] as num?)?.toDouble() ?? 0.0)
            : 0.0;
        final orderTotal = netPayable > 0 ? netPayable : rawTotal;

        // Sum of deliveries
        final sumDeliveries = deliveries.fold(0.0, (sum, d) => sum + ((d['total_amount'] as num?)?.toDouble() ?? 0.0));
        final isCompleted = sumDeliveries >= orderTotal;

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
                '${Localization.translate('طلب', lang)} #$orderId - $clientName',
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
                        '${Localization.translate('قيمة الطلب', lang)}: ${orderTotal.toStringAsFixed(2)} دج  ·  ${Localization.translate('مجموع المسلّم', lang)}: ${sumDeliveries.toStringAsFixed(2)} دج',
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
                          isCompleted ? Localization.translate('مكتملة بالكامل', lang) : Localization.translate('غير جاهزة كلياً (جزئية)', lang),
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
                }
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
                          
                          // Safely parse delivered items list
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
                                        '${Localization.translate('تاريخ التسليم', lang)}: $delDate',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold, 
                                          fontSize: 12, 
                                          fontFamily: 'Cairo',
                                          color: Theme.of(tileCtx).textTheme.bodyLarge?.color
                                        ),
                                      ),
                                      if (itemsSummary.isNotEmpty)
                                        Text(
                                          '${Localization.translate('القطع', lang)}: $itemsSummary',
                                          style: TextStyle(
                                            fontSize: 11, 
                                            color: isDark ? Colors.white70 : Colors.grey.shade600, 
                                            fontFamily: 'Cairo'
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${delAmount.toStringAsFixed(2)} دج',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
