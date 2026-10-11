import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:intl/intl.dart' hide TextDirection;
import '../Commande/order_workspace_screen.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../widgets/order_profitability_dialog.dart';
import '../widgets/resizable_columns_table.dart';

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
  List<Map<String, dynamic>> _materialStoreSales = [];
  List<Map<String, dynamic>> _workshopPurchases = [];
  List<Map<String, dynamic>> _storePurchases = [];
  final NumberFormat _currencyFormatter = NumberFormat('#,##0.00');

  // Active filter tab:
  // 'all' | 'confirmed' | 'partial_manufacturing' | 'full_manufacturing'
  // | 'partial_distribution' | 'full_distribution' | 'installed' | 'reserve' | 'finished' | 'partial'
  String _selectedTab = 'all';
  double _dividerRatio = 0.35; // نسبة عرض اليسار (المخططات) من الإجمالي
  String _mobileViewMode = 'orders'; // 'orders' | 'chart'

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
        WHERE (co.is_deleted IS NULL OR co.is_deleted = 0)
        ORDER BY co.created_at DESC
      ''');

      // 2. Fetch all delivery notes with client name info (Strictly exclude Pending orders!)
      final deliveriesRaw = await myDb.rawQuery('''
        SELECT cd.*, co.status as order_status, co.total as order_total, co.net_payable as order_net_payable, c.firstname, c.lastname FROM Commandes_deliveries cd
        JOIN Commandes co ON cd.id_commandes = co.id
        JOIN Client c ON cd.client_id = c.id
        WHERE (co.is_deleted IS NULL OR co.is_deleted = 0)
          AND LOWER(TRIM(co.status)) NOT IN ('pending', 'en attente', 'en_attente', 'في الانتظار', 'في حالة انتظار', 'nouveau', 'new', 'جديد', 'جديدة', 'draft')
        ORDER BY cd.delivery_date DESC
      ''');
      final materialStoreSales = await widget.db.readMaterialSales();
      final workshopPurchases = await widget.db.readAchats(isWorkshop: true);
      final storePurchases = await widget.db.readAchats(isWorkshop: false);

      setState(() {
        _allOrders = List<Map<String, dynamic>>.from(ordersRaw);
        _allDeliveries = List<Map<String, dynamic>>.from(deliveriesRaw);
        _materialStoreSales = materialStoreSales;
        _workshopPurchases = workshopPurchases;
        _storePurchases = storePurchases;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final lang = Provider.of<AppSettingsProvider>(
          context,
          listen: false,
        ).language;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_tr('خطأ أثناء تحميل المبيعات', 'Erreur lors du chargement des ventes', 'Error loading sales', lang)}: $e',
            ),
            backgroundColor: Colors.red,
          ),
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
      return _activeStatuses.contains(s) &&
          s != 'pending' &&
          s != 'في حالة انتظار';
    }).toList();

    if (_selectedTab == 'all') {
      return active;
    } else if (_selectedTab == 'confirmed') {
      return active
          .where(
            (o) =>
                (o['status'] ?? '').toString().toLowerCase().trim() ==
                'confirmed',
          )
          .toList();
    } else if (_selectedTab == 'partial_manufacturing') {
      return active
          .where(
            (o) =>
                (o['status'] ?? '').toString().toLowerCase().trim() ==
                'partial manufacturing',
          )
          .toList();
    } else if (_selectedTab == 'full_manufacturing') {
      return active
          .where(
            (o) =>
                (o['status'] ?? '').toString().toLowerCase().trim() ==
                'full manufacturing',
          )
          .toList();
    } else if (_selectedTab == 'partial_distribution') {
      return active
          .where(
            (o) =>
                (o['status'] ?? '').toString().toLowerCase().trim() ==
                'partial distribution',
          )
          .toList();
    } else if (_selectedTab == 'full_distribution') {
      return active
          .where(
            (o) =>
                (o['status'] ?? '').toString().toLowerCase().trim() ==
                'full distribution',
          )
          .toList();
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
        return s == 'finished' ||
            s == 'completed' ||
            s == 'archived' ||
            s == 'done' ||
            s == 'أرشيف' ||
            s == 'منتهية';
      }).toList();
    }
    return active;
  }

  // Group deliveries by order ID for partial sales calculations
  Map<int, List<Map<String, dynamic>>> get _groupedDeliveries {
    final Map<int, List<Map<String, dynamic>>> grouped = {};
    for (final del in _allDeliveries) {
      final orderStatus = (del['order_status'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
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
      return _allDeliveries.fold(
        0.0,
        (sum, del) => sum + ((del['total_amount'] as num?)?.toDouble() ?? 0.0),
      );
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
        return _tr(
          'المنتهية / المؤرشفة',
          'Terminée / Archivée',
          'Finished / Archived',
          lang,
        );
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
        return _tr(
          'إجمالي كل المبيعات المؤكدة',
          'Total ventes confirmées',
          'Total Confirmed Sales',
          lang,
        );
      case 'confirmed':
        return _tr(
          'إجمالي الطلبيات المؤكدة',
          'Total commandes confirmées',
          'Total Confirmed Orders',
          lang,
        );
      case 'partial_manufacturing':
        return _tr(
          'إجمالي التصنيع الجزئي',
          'Total Fab. Partielle',
          'Total Partial Mfg',
          lang,
        );
      case 'full_manufacturing':
        return _tr(
          'إجمالي التصنيع الكلي',
          'Total Fab. Totale',
          'Total Full Mfg',
          lang,
        );
      case 'partial_distribution':
        return _tr(
          'إجمالي التوزيع الجزئي',
          'Total Dist. Partielle',
          'Total Partial Dist',
          lang,
        );
      case 'full_distribution':
        return _tr(
          'إجمالي التوزيع الكلي',
          'Total Dist. Totale',
          'Total Full Dist',
          lang,
        );
      case 'installed':
        return _tr(
          'إجمالي الطلبيات المركبة',
          'Total installées',
          'Total Installed',
          lang,
        );
      case 'reserve':
        return _tr(
          'إجمالي المحجوزة / حجز',
          'Total réservées',
          'Total Reserved',
          lang,
        );
      case 'finished':
        return _tr(
          'إجمالي الطلبيات المنتهية',
          'Total terminées',
          'Total Finished',
          lang,
        );
      case 'partial':
        return _tr(
          'إجمالي المبيعات الجزئية المسلمة',
          'Total livraisons partielles',
          'Total Partial Deliveries',
          lang,
        );
      default:
        return _tr('إجمالي المبيعات', 'Total des ventes', 'Total Sales', lang);
    }
  }

  DateTime? _parseOrderDate(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  bool _isConfirmedOrder(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString().trim().toLowerCase();
    return status == 'confirmed' ||
        status == 'confirmée' ||
        status == 'confirmé' ||
        status == 'مؤكد' ||
        status == 'مؤكدة';
  }

  List<_SalesChartPoint> get _workshopChartPoints {
    final grouped = <DateTime, _SalesChartPoint>{};
    for (final order in _allOrders) {
      final status = (order['status'] ?? '').toString().trim().toLowerCase();
      if (!_activeStatuses.contains(status)) continue;
      final date = _parseOrderDate(order['created_at']);
      if (date == null) continue;

      final month = DateTime(date.year, date.month);
      final netPayable = (order['net_payable'] as num?)?.toDouble() ?? 0.0;
      final rawTotal = (order['total'] as num?)?.toDouble() ?? 0.0;
      final total = netPayable > 0 ? netPayable : rawTotal;
      if (total <= 0) continue;

      final point = grouped[month] ?? _SalesChartPoint(month: month);
      point.total += total;
      grouped[month] = point;
    }

    for (final purchase in _workshopPurchases) {
      final date = _parseOrderDate(purchase['created_at']);
      if (date == null) continue;
      final month = DateTime(date.year, date.month);
      final point = grouped[month] ?? _SalesChartPoint(month: month);
      point.confirmed += (purchase['total'] as num?)?.toDouble() ?? 0.0;
      grouped[month] = point;
    }

    final points = grouped.values.toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    // Keep the graph readable when the database contains a long history.
    return points.length > 12 ? points.sublist(points.length - 12) : points;
  }

  List<_SalesChartPoint> get _storeChartPoints {
    final grouped = <DateTime, _SalesChartPoint>{};
    for (final sale in _materialStoreSales) {
      if ((sale['is_internal'] as num?)?.toInt() == 1) continue;
      final date = _parseOrderDate(sale['sale_date'] ?? sale['created_at']);
      if (date == null) continue;
      final month = DateTime(date.year, date.month);
      final point = grouped[month] ?? _SalesChartPoint(month: month);
      point.total += (sale['net_total'] as num?)?.toDouble() ?? 0.0;
      grouped[month] = point;
    }
    for (final purchase in _storePurchases) {
      final date = _parseOrderDate(purchase['created_at']);
      if (date == null) continue;
      final month = DateTime(date.year, date.month);
      final point = grouped[month] ?? _SalesChartPoint(month: month);
      point.confirmed += (purchase['total'] as num?)?.toDouble() ?? 0.0;
      grouped[month] = point;
    }
    final points = grouped.values.toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    return points.length > 12 ? points.sublist(points.length - 12) : points;
  }

  List<_StoreSalesMonthRow> get _storeSalesByMonth {
    final grouped = <DateTime, _StoreSalesMonthRow>{};
    for (final sale in _materialStoreSales) {
      if ((sale['is_internal'] as num?)?.toInt() == 1) continue;
      final rawDate = (sale['sale_date'] ?? sale['created_at'] ?? '')
          .toString();
      final date = DateTime.tryParse(rawDate);
      if (date == null) continue;
      final month = DateTime(date.year, date.month);
      final row = grouped[month] ?? _StoreSalesMonthRow(month: month);
      row.documents++;
      row.total += (sale['net_total'] as num?)?.toDouble() ?? 0.0;
      row.paid += (sale['paid_amount'] as num?)?.toDouble() ?? 0.0;
      row.remaining += (sale['remaining_amount'] as num?)?.toDouble() ?? 0.0;
      grouped[month] = row;
    }
    for (final purchase in _storePurchases) {
      final date = _parseOrderDate(purchase['created_at']);
      if (date == null) continue;
      final month = DateTime(date.year, date.month);
      final row = grouped[month] ?? _StoreSalesMonthRow(month: month);
      row.purchaseDocuments++;
      row.purchaseTotal += (purchase['total'] as num?)?.toDouble() ?? 0.0;
      row.purchasePaid +=
          (purchase['paid_amount'] as num?)?.toDouble() ?? 0.0;
      row.purchaseRemaining +=
          (purchase['remaining_amount'] as num?)?.toDouble() ?? 0.0;
      grouped[month] = row;
    }
    final rows = grouped.values.toList()
      ..sort((a, b) => b.month.compareTo(a.month));
    return rows.length > 6 ? rows.sublist(0, 6) : rows;
  }

  List<_RecentBusinessActivity> get _recentActivities {
    final activities = <_RecentBusinessActivity>[];
    void addActivity({
      required String kind,
      required String document,
      required String party,
      required dynamic date,
      required dynamic user,
      required IconData icon,
      required Color color,
    }) {
      final parsed = _parseOrderDate(date);
      if (parsed == null) return;
      activities.add(
        _RecentBusinessActivity(
          kind: kind,
          document: document,
          party: party,
          date: parsed,
          user: (user ?? '').toString().trim(),
          icon: icon,
          color: color,
        ),
      );
    }

    for (final order in _allOrders) {
      addActivity(
        kind: 'order',
        document: (order['order_code'] ?? '#${order['id']}').toString(),
        party: '${order['firstname'] ?? ''} ${order['lastname'] ?? ''}'.trim(),
        date: order['created_at'],
        user: order['created_by'] ?? order['updated_by'],
        icon: Icons.add_shopping_cart_rounded,
        color: const Color(0xFF2563EB),
      );
      final created = _parseOrderDate(order['created_at']);
      final updated = _parseOrderDate(order['updated_at']);
      if (created != null &&
          updated != null &&
          updated.difference(created).abs() > const Duration(seconds: 5)) {
        addActivity(
          kind: 'order_updated',
          document: (order['order_code'] ?? '#${order['id']}').toString(),
          party: '${order['firstname'] ?? ''} ${order['lastname'] ?? ''}'.trim(),
          date: updated,
          user: order['updated_by'],
          icon: Icons.edit_note_rounded,
          color: const Color(0xFF7C3AED),
        );
      }
    }
    for (final delivery in _allDeliveries) {
      addActivity(
        kind: 'delivery',
        document: (delivery['delivery_code'] ?? delivery['id'] ?? '—').toString(),
        party: '${delivery['firstname'] ?? ''} ${delivery['lastname'] ?? ''}'.trim(),
        date: delivery['delivery_date'] ?? delivery['created_at'],
        user: delivery['created_by'] ?? delivery['updated_by'],
        icon: Icons.local_shipping_rounded,
        color: const Color(0xFF0891B2),
      );
    }
    for (final sale in _materialStoreSales) {
      addActivity(
        kind: 'sale',
        document: (sale['sale_code'] ?? '#${sale['id']}').toString(),
        party: (sale['client_name'] ?? '').toString(),
        date: sale['created_at'],
        user: sale['created_by'],
        icon: Icons.point_of_sale_rounded,
        color: const Color(0xFF16A34A),
      );
    }
    for (final purchase in [..._workshopPurchases, ..._storePurchases]) {
      addActivity(
        kind: 'purchase',
        document: (purchase['invoice_number'] ?? '#${purchase['id']}').toString(),
        party: (purchase['supplier_name'] ?? '').toString(),
        date: purchase['created_at'],
        user: purchase['created_by'],
        icon: Icons.shopping_bag_rounded,
        color: const Color(0xFFF59E0B),
      );
    }
    activities.sort((a, b) => b.date.compareTo(a.date));
    return activities.take(12).toList(growable: false);
  }

  String _activityLabel(String kind, AppLanguage lang) {
    switch (kind) {
      case 'order':
        return _tr('إضافة طلبية', 'Ajout commande', 'Order added', lang);
      case 'order_updated':
        return _tr('تعديل طلبية', 'Modification commande', 'Order updated', lang);
      case 'delivery':
        return _tr('إضافة وصل تسليم', 'Ajout bon de livraison', 'Delivery note added', lang);
      case 'purchase':
        return _tr('إضافة شراء', 'Ajout achat', 'Purchase added', lang);
      case 'sale':
        return _tr('إضافة بيع', 'Ajout vente', 'Sale added', lang);
      default:
        return kind;
    }
  }

  Widget _buildStoreSalesDataTable(AppLanguage lang) {
    final activities = _recentActivities;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final header = isDark ? Colors.grey.shade900 : Colors.blueGrey.shade800;
    Widget cell(String text, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: color,
        ),
      ),
    );

    return Container(
      height: 178,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: header,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront_rounded,
                  color: Colors.white,
                  size: 17,
                ),
                const SizedBox(width: 7),
                Text(
                  _tr(
                    'آخر النشاطات',
                    'Activités récentes',
                    'Recent activity',
                    lang,
                  ),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (activities.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _tr(
                    'لا توجد نشاطات حديثة',
                    'Aucune activité récente',
                    'No recent activity',
                    lang,
                  ),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                ),
              ),
            )
          else
            Expanded(
              child: ResizableColumnsTable(
                persistenceKey: 'recent_business_activity_v1',
                headerMinHeight: 34,
                rowMinHeight: 34,
                cellPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                columns: [
                  ResizableTableColumn(id: 'activity', label: cell(_tr('النشاط', 'Activité', 'Activity', lang), bold: true), initialWidth: 155),
                  ResizableTableColumn(id: 'document', label: cell(_tr('الوثيقة', 'Document', 'Document', lang), bold: true), initialWidth: 145),
                  ResizableTableColumn(id: 'party', label: cell(_tr('العميل / المورد', 'Client / fournisseur', 'Client / supplier', lang), bold: true), initialWidth: 190),
                  ResizableTableColumn(id: 'user', label: cell(_tr('بواسطة', 'Par', 'By', lang), bold: true), initialWidth: 145),
                  ResizableTableColumn(id: 'date', label: cell(_tr('التاريخ', 'Date', 'Date', lang), bold: true), initialWidth: 155),
                ],
                rows: [
                  for (final activity in activities)
                    ResizableTableRow(
                      reorderId: '${activity.kind}_${activity.document}_${activity.date.toIso8601String()}',
                      cells: [
                        Row(children: [Icon(activity.icon, size: 16, color: activity.color), const SizedBox(width: 6), Expanded(child: cell(_activityLabel(activity.kind, lang), bold: true, color: activity.color))]),
                        cell(activity.document, bold: true),
                        cell(activity.party.isEmpty ? '—' : activity.party),
                        cell(activity.user.isEmpty ? '—' : activity.user),
                        cell(DateFormat('dd/MM/yyyy HH:mm').format(activity.date.toLocal())),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWorkshopChartWithStoreData(AppLanguage lang) {
    return Column(
      children: [
        Expanded(child: _buildSalesChart(lang, workshop: true)),
        const SizedBox(height: 10),
        Expanded(child: _buildSalesChart(lang, workshop: false)),
        const SizedBox(height: 10),
        _buildStoreSalesDataTable(lang),
      ],
    );
  }

  Widget _buildSalesChart(AppLanguage lang, {required bool workshop}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final points = workshop ? _workshopChartPoints : _storeChartPoints;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.blueGrey.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── العنوان + أزرار نوع الرسم ──
          Row(
            children: [
              Expanded(
                child: Text(
                  _tr(
                    workshop
                        ? 'مبيعات ومشتريات الورشة'
                        : 'مبيعات ومشتريات المحل',
                    workshop
                        ? 'Ventes et achats de l’atelier'
                        : 'Ventes et achats du magasin',
                    workshop
                        ? 'Workshop sales and purchases'
                        : 'Store sales and purchases',
                    lang,
                  ),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.blueGrey.shade900,
                  ),
                ),
              ),
              Icon(
                workshop ? Icons.bar_chart_rounded : Icons.show_chart_rounded,
                color: workshop ? const Color(0xFF2563EB) : const Color(0xFF0891B2),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ── وسيلة إيضاح ──
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _chartLegend(
                _tr('المبيعات', 'Ventes', 'Sales', lang),
                const Color(0xFF2563EB),
              ),
              _chartLegend(
                _tr('المشتريات', 'Achats', 'Purchases', lang),
                const Color(0xFFF59E0B),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // ── الرسم البياني ──
          Expanded(
            child: points.isEmpty
                ? Center(
                    child: Text(
                      _tr(
                        'لا توجد بيانات للرسم البياني.',
                        'Aucune donnée à afficher.',
                        'No data to display.',
                        lang,
                      ),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.blueGrey,
                      ),
                    ),
                  )
                : CustomPaint(
                    painter: _SalesChartPainter(
                      points: points,
                      isDark: isDark,
                      chartType: workshop ? 'bar' : 'line',
                      showPaid: false,
                    ),
                    child: const SizedBox.expand(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chartLegend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
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

  Widget _buildTabButton(
    String id,
    String label,
    IconData icon,
    Color activeColor,
  ) {
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
        ? (isSelected
              ? Colors.blue.withOpacity(0.08)
              : Theme.of(context).cardColor)
        : (isSelected ? activeColor.withOpacity(0.08) : Colors.white);

    return GestureDetector(
      onTap: () => setState(() => _selectedTab = id),
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
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
            _tr(
              'صفحة المبيعات والطلبيات',
              'Ventes & Commandes',
              'Sales & Orders',
              lang,
            ),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
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
                          _buildTabButton(
                            'all',
                            _tr('الكل', 'Tous', 'All', lang),
                            Icons.list_alt_rounded,
                            Colors.indigo,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            'confirmed',
                            _tr('المؤكدة', 'Confirmée', 'Confirmed', lang),
                            Icons.check_circle_outline,
                            Colors.blue,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            'partial_manufacturing',
                            _tr(
                              'التصنيع الجزئي',
                              'Fab. Partielle',
                              'Partial Mfg',
                              lang,
                            ),
                            Icons.precision_manufacturing_rounded,
                            Colors.amber,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            'full_manufacturing',
                            _tr(
                              'التصنيع الكلي',
                              'Fab. Totale',
                              'Full Mfg',
                              lang,
                            ),
                            Icons.build,
                            Colors.green,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            'partial_distribution',
                            _tr(
                              'التوزيع الجزئي',
                              'Dist. Partielle',
                              'Partial Dist',
                              lang,
                            ),
                            Icons.delivery_dining_outlined,
                            Colors.deepOrange,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            'full_distribution',
                            _tr(
                              'التوزيع الكلي',
                              'Dist. Totale',
                              'Full Dist',
                              lang,
                            ),
                            Icons.local_shipping_rounded,
                            Colors.teal,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            'installed',
                            _tr('المركبة', 'Installée', 'Installed', lang),
                            Icons.home_repair_service_rounded,
                            Colors.purple,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            'reserve',
                            _tr('المحجوزة / حجز', 'Réservée', 'Reserved', lang),
                            Icons.bookmark,
                            Colors.brown,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            'finished',
                            _tr(
                              'المنتهية / المؤرشفة',
                              'Terminée',
                              'Finished',
                              lang,
                            ),
                            Icons.task_alt_rounded,
                            Colors.blueGrey,
                          ),
                          const SizedBox(width: 6),
                          _buildTabButton(
                            'partial',
                            _tr(
                              'المبيعات الجزئية',
                              'Ventes Partielles',
                              'Partial Sales',
                              lang,
                            ),
                            Icons.receipt_long_rounded,
                            Colors.cyan,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // لوحة المبيعات: مخططات + طلبات (متجاوبة للهاتف والكمبيوتر)
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final totalW = constraints.maxWidth;
                          final isDark =
                              Theme.of(context).brightness == Brightness.dark;

                          if (totalW < 700) {
                            // ── نمط الهاتف: مبدل تبويبات أنيق بين الطلبيات والرسم البياني ──
                            final ordersCount = _selectedTab == 'partial'
                                ? _groupedDeliveries.keys.length
                                : _filteredOrders.length;
                            return Column(
                              children: [
                                Container(
                                  height: 38,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF1E293B)
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white12
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => setState(
                                            () => _mobileViewMode = 'orders',
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: _mobileViewMode == 'orders'
                                                  ? const Color(0xFF2563EB)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            alignment: Alignment.center,
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.list_alt_rounded,
                                                  size: 16,
                                                  color:
                                                      _mobileViewMode ==
                                                          'orders'
                                                      ? Colors.white
                                                      : (isDark
                                                            ? Colors.white70
                                                            : Colors.black87),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '${_tr('الطلبيات', 'Commandes', 'Orders', lang)} ($ordersCount)',
                                                  style: TextStyle(
                                                    fontFamily: 'Cairo',
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color:
                                                        _mobileViewMode ==
                                                            'orders'
                                                        ? Colors.white
                                                        : (isDark
                                                              ? Colors.white70
                                                              : Colors.black87),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: InkWell(
                                          onTap: () => setState(
                                            () => _mobileViewMode = 'chart',
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: _mobileViewMode == 'chart'
                                                  ? const Color(0xFF2563EB)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            alignment: Alignment.center,
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.bar_chart_rounded,
                                                  size: 16,
                                                  color:
                                                      _mobileViewMode == 'chart'
                                                      ? Colors.white
                                                      : (isDark
                                                            ? Colors.white70
                                                            : Colors.black87),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  _tr(
                                                    'الرسم البياني',
                                                    'Graphique',
                                                    'Chart',
                                                    lang,
                                                  ),
                                                  style: TextStyle(
                                                    fontFamily: 'Cairo',
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color:
                                                        _mobileViewMode ==
                                                            'chart'
                                                        ? Colors.white
                                                        : (isDark
                                                              ? Colors.white70
                                                              : Colors.black87),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: _mobileViewMode == 'chart'
                                      ? SingleChildScrollView(
                                          child: SizedBox(
                                            height: 650,
                                            child:
                                                _buildWorkshopChartWithStoreData(
                                                  lang,
                                                ),
                                          ),
                                        )
                                      : (_selectedTab == 'partial'
                                            ? _buildPartialDeliveriesList(lang)
                                            : _buildOrdersList(lang)),
                                ),
                              ],
                            );
                          }

                          // ── نمط الشاشات الكبيرة والكمبيوتر ──
                          final minW = 200.0;
                          final maxLeft = (totalW - minW).clamp(minW, totalW);
                          final leftW = (_dividerRatio * totalW).clamp(
                            minW,
                            maxLeft,
                          );
                          final rightW = (totalW - leftW - 6.0).clamp(
                            0.0,
                            totalW,
                          );

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── اليسار: المخططات ──
                              SizedBox(
                                width: leftW,
                                child: _buildWorkshopChartWithStoreData(lang),
                              ),

                              // ── الفاصل القابل للسحب ──
                              GestureDetector(
                                onHorizontalDragUpdate: (details) {
                                  setState(() {
                                    final newLeft = leftW + details.delta.dx;
                                    final minRatio = minW / totalW;
                                    final maxRatio = (totalW - minW) / totalW;
                                    if (minRatio < maxRatio) {
                                      _dividerRatio = (newLeft / totalW).clamp(
                                        minRatio,
                                        maxRatio,
                                      );
                                    }
                                  });
                                },
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.resizeColumn,
                                  child: Container(
                                    width: 6,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade100,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 2,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: Colors.blueGrey.shade400,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // ── اليمين: الطلبات ──
                              SizedBox(
                                width: rightW,
                                child: _selectedTab == 'partial'
                                    ? _buildPartialDeliveriesList(lang)
                                    : _buildOrdersList(lang),
                              ),
                            ],
                          );
                        },
                      ),
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
          _tr(
            'لا توجد طلبيات مطابقة لهذا التصنيف.',
            'Aucune commande trouvée.',
            'No matching orders found.',
            lang,
          ),
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
        final displayNumber =
            (order['display_number'] as num?)?.toInt() ??
            (order['order_code'] as num?)?.toInt() ??
            (order['id'] as num?)?.toInt() ??
            0;

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: Colors.blue.withOpacity(0.15),
              child: const Icon(Icons.receipt, color: Colors.blue),
            ),
            title: Text(
              '${_tr('طلب', 'Commande', 'Order', lang)} #$displayNumber - $clientName',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
            subtitle: Text(
              '${_tr('التاريخ', 'Date', 'Date', lang)}: $date  ·  ${_tr('الحالة', 'Statut', 'Status', lang)}: ${_translateStatus(order['status']?.toString(), lang)}',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.analytics_rounded,
                    color: Color(0xFF10B981),
                    size: 22,
                  ),
                  tooltip: _tr(
                    'تحليل الربحية والتكلفة',
                    'Rentabilité & Coût',
                    'Profitability & Cost',
                    lang,
                  ),
                  onPressed: () {
                    OrderProfitabilityDialog.show(
                      context,
                      orderData: order,
                      db: widget.db,
                    );
                  },
                ),
                Text(
                  '${_currencyFormatter.format(total)} دج',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            onTap: () {
              openOrderInWorkspaceTab(
                context,
                db: widget.db,
                editCommandeId: order['id'] as int,
                onSaved: _loadSalesData,
              );
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
          _tr(
            'لا توجد فواتير تسليم جزئية مسجلة حالياً.',
            'Aucune livraison partielle.',
            'No partial deliveries found.',
            lang,
          ),
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

        final parentOrder = _allOrders.firstWhere(
          (o) => o['id'] == orderId,
          orElse: () => {},
        );
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

        final sumDeliveries = deliveries.fold(
          0.0,
          (sum, d) => sum + ((d['total_amount'] as num?)?.toDouble() ?? 0.0),
        );
        final isCompleted = sumDeliveries >= orderTotal && orderTotal > 0;

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 14,
                ),
              ),
              subtitle: Builder(
                builder: (tileCtx) {
                  final isDark =
                      Theme.of(tileCtx).brightness == Brightness.dark;
                  final badgeBg = isCompleted
                      ? (isDark
                            ? Colors.green.withOpacity(0.15)
                            : Colors.green.shade50)
                      : (isDark
                            ? Colors.orange.withOpacity(0.15)
                            : Colors.orange.shade50);
                  final badgeText = isCompleted
                      ? (isDark ? Colors.green.shade300 : Colors.green.shade800)
                      : (isDark
                            ? Colors.orange.shade300
                            : Colors.orange.shade800);
                  final badgeBorder = isCompleted
                      ? Colors.green
                      : Colors.orange;

                  return Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        '${_tr('قيمة الطلب', 'Montant', 'Amount', lang)}: ${_currencyFormatter.format(orderTotal)} دج  ·  ${_tr('مجموع المسلّم', 'Livré', 'Delivered', lang)}: ${_currencyFormatter.format(sumDeliveries)} دج',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Cairo',
                          color: Theme.of(tileCtx).textTheme.bodySmall?.color,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: badgeBorder),
                        ),
                        child: Text(
                          isCompleted
                              ? _tr(
                                  'مكتملة بالكامل',
                                  'Livrée totalement',
                                  'Fully Delivered',
                                  lang,
                                )
                              : _tr(
                                  'غير جاهزة كلياً (جزئية)',
                                  'Livraison partielle',
                                  'Partial Delivery',
                                  lang,
                                ),
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
                    final isDark =
                        Theme.of(tileCtx).brightness == Brightness.dark;
                    return Container(
                      color: isDark
                          ? Colors.grey.shade900
                          : Colors.grey.shade50,
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 16,
                      ),
                      child: Column(
                        children: deliveries.map((d) {
                          final delDate =
                              d['delivery_date']?.toString().split('T')[0] ??
                              '';
                          final delAmount =
                              (d['total_amount'] as num?)?.toDouble() ?? 0.0;

                          List<dynamic> items = [];
                          try {
                            final rawItems = d['items_json'];
                            if (rawItems != null) {
                              if (rawItems is List) {
                                items = rawItems;
                              } else {
                                items =
                                    jsonDecode(rawItems.toString())
                                        as List<dynamic>;
                              }
                            }
                          } catch (_) {}

                          final itemsSummary = items
                              .map(
                                (i) =>
                                    '${i['game'] ?? 'Window'} (${i['qty'] ?? 1}x)',
                              )
                              .join(', ');

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 6,
                                  color: Colors.teal,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        '${_tr('تاريخ التسليم', 'Date livraison', 'Delivery date', lang)}: $delDate',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          fontFamily: 'Cairo',
                                          color: Theme.of(
                                            tileCtx,
                                          ).textTheme.bodyLarge?.color,
                                        ),
                                      ),
                                      if (itemsSummary.isNotEmpty)
                                        Text(
                                          '${_tr('القطع', 'Pièces', 'Items', lang)}: $itemsSummary',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.grey.shade600,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${_currencyFormatter.format(delAmount)} دج',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal,
                                    fontSize: 13,
                                  ),
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

class _StoreSalesMonthRow {
  final DateTime month;
  int documents = 0;
  double total = 0;
  double paid = 0;
  double remaining = 0;
  int purchaseDocuments = 0;
  double purchaseTotal = 0;
  double purchasePaid = 0;
  double purchaseRemaining = 0;

  _StoreSalesMonthRow({required this.month});
}

class _RecentBusinessActivity {
  final String kind;
  final String document;
  final String party;
  final DateTime date;
  final String user;
  final IconData icon;
  final Color color;

  const _RecentBusinessActivity({
    required this.kind,
    required this.document,
    required this.party,
    required this.date,
    required this.user,
    required this.icon,
    required this.color,
  });
}

class _SalesChartPoint {
  final DateTime month;
  double total = 0;
  double confirmed = 0;
  double paid = 0;

  _SalesChartPoint({required this.month});
}

class _SalesChartPainter extends CustomPainter {
  final List<_SalesChartPoint> points;
  final bool isDark;
  final String chartType; // 'bar' | 'line'
  final bool showPaid;

  const _SalesChartPainter({
    required this.points,
    required this.isDark,
    required this.chartType,
    this.showPaid = false,
  });

  static const _totalColor = Color(0xFF2563EB);
  static const _confirmedColor = Color(0xFFF59E0B);
  static const _paidColor = Color(0xFF16A34A);

  String _compactValue(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}K';
    return value.toStringAsFixed(0);
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
  }

  /// رسم شبكة المحاور والتسميات المشتركة
  void _drawGrid(
    Canvas canvas,
    Size size,
    double maxValue,
    double left,
    double right,
    double top,
    double bottom,
    Color labelColor,
  ) {
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final gridPaint = Paint()
      ..color = isDark ? Colors.white12 : Colors.blueGrey.shade100
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = isDark ? Colors.white24 : Colors.blueGrey.shade300
      ..strokeWidth = 1.2;

    for (var i = 0; i <= 4; i++) {
      final ratio = i / 4;
      final y = top + chartHeight - (chartHeight * ratio);
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
      _drawText(
        canvas,
        _compactValue(maxValue * ratio),
        Offset(0, y - 7),
        TextStyle(fontSize: 9, color: labelColor),
      );
    }
    canvas.drawLine(
      Offset(left, top),
      Offset(left, top + chartHeight),
      axisPaint,
    );
    canvas.drawLine(
      Offset(left, top + chartHeight),
      Offset(size.width - right, top + chartHeight),
      axisPaint,
    );

    // تسميات الشهور
    final slotWidth = chartWidth / points.length;
    for (var i = 0; i < points.length; i++) {
      final centerX = left + slotWidth * (i + 0.5);
      final label = DateFormat('MM/yy').format(points[i].month);
      final lp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontSize: 9, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      lp.paint(canvas, Offset(centerX - lp.width / 2, top + chartHeight + 7));
    }
  }

  void _drawLine(Canvas canvas, List<Offset> pts, Color color) {
    if (pts.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (pts.length > 1) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) path.lineTo(p.dx, p.dy);
      canvas.drawPath(path, paint);
    }
    for (final p in pts) {
      canvas.drawCircle(p, 3.5, Paint()..color = color);
      canvas.drawCircle(p, 2.0, Paint()..color = Colors.white);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    const left = 45.0;
    const right = 12.0;
    const top = 10.0;
    const bottom = 28.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final maxValue = points.fold<double>(0, (maximum, point) {
      final pointMaximum = [
        point.total,
        point.confirmed,
        if (showPaid) point.paid,
      ].reduce((a, b) => a > b ? a : b);
      return pointMaximum > maximum ? pointMaximum : maximum;
    });
    if (maxValue <= 0) return;

    final labelColor = isDark ? Colors.white54 : Colors.blueGrey.shade500;
    _drawGrid(canvas, size, maxValue, left, right, top, bottom, labelColor);

    final slotWidth = chartWidth / points.length;

    if (chartType == 'bar') {
      // ── أعمدة بيانية ──
      final barWidth = (slotWidth * 0.28).clamp(7.0, 28.0).toDouble();

      for (var i = 0; i < points.length; i++) {
        final pt = points[i];
        final cx = left + slotWidth * (i + 0.5);
        final baseline = top + chartHeight;
        final tH = chartHeight * pt.total / maxValue;
        final cH = chartHeight * pt.confirmed / maxValue;

        canvas.drawRect(
          Rect.fromLTWH(cx - barWidth - 2, baseline - tH, barWidth, tH),
          Paint()..color = _totalColor,
        );
        canvas.drawRect(
          Rect.fromLTWH(cx + 2, baseline - cH, barWidth, cH),
          Paint()..color = _confirmedColor,
        );
      }
    } else {
      // ── منحنى بياني ──
      final totalPts = <Offset>[];
      final confirmedPts = <Offset>[];
      final paidPts = <Offset>[];
      final baseline = top + chartHeight;

      for (var i = 0; i < points.length; i++) {
        final pt = points[i];
        final cx = left + slotWidth * (i + 0.5);
        totalPts.add(Offset(cx, baseline - chartHeight * pt.total / maxValue));
        confirmedPts.add(
          Offset(cx, baseline - chartHeight * pt.confirmed / maxValue),
        );
        if (showPaid) {
          paidPts.add(Offset(cx, baseline - chartHeight * pt.paid / maxValue));
        }
      }

      // رسم ظل خفيف تحت خط الإجمالي
      if (totalPts.length > 1) {
        final fillPath = Path()..moveTo(totalPts.first.dx, baseline);
        for (final p in totalPts) fillPath.lineTo(p.dx, p.dy);
        fillPath.lineTo(totalPts.last.dx, baseline);
        fillPath.close();
        canvas.drawPath(
          fillPath,
          Paint()..color = _totalColor.withOpacity(0.07),
        );
      }

      _drawLine(canvas, totalPts, _totalColor);
      _drawLine(canvas, confirmedPts, _confirmedColor);
      if (showPaid) _drawLine(canvas, paidPts, _paidColor);
    }
  }

  @override
  bool shouldRepaint(covariant _SalesChartPainter old) =>
      old.isDark != isDark ||
      old.points != points ||
      old.chartType != chartType ||
      old.showPaid != showPaid;
}
