import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'glass_order_reception_screen.dart';
import 'achat_screen.dart';

class ExternalOperationsHubScreen extends StatefulWidget {
  final SqlDatabase db;

  const ExternalOperationsHubScreen({super.key, required this.db});

  @override
  State<ExternalOperationsHubScreen> createState() =>
      _ExternalOperationsHubScreenState();
}

class _ExternalOperationsHubScreenState
    extends State<ExternalOperationsHubScreen> {
  int _selectedTabIndex = 0; // 0: الزجاج, 1: الشراء والنواقص, 2: التركيبات, 3: التحفظات
  bool _isLoading = true;

  List<Map<String, dynamic>> _allOrders = [];
  Map<int, List<Map<String, dynamic>>> _orderDetailsMap = {};
  Map<int, List<Map<String, dynamic>>> _orderAllocationsMap = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // خريطة لتأكيدات طلبات الزجاج
  final Map<int, String> _glassStatusMap = {}; // orderId -> status

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── ترجمة النصوص إلى اللغات الثلاث ─────────────────────────────────────
  String _tr(String ar, String fr, String en, AppLanguage lang) {
    switch (lang) {
      case AppLanguage.french:
        return fr;
      case AppLanguage.english:
        return en;
      default:
        return ar;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final orders = await widget.db.readCommandesWithClients();
      final Map<int, List<Map<String, dynamic>>> detailsMap = {};
      final Map<int, List<Map<String, dynamic>>> allocsMap = {};

      for (var o in orders) {
        final oId = o['id'] as int;
        final details = await widget.db.readCommandeDetails(oId);
        detailsMap[oId] = details;

        List<Map<String, dynamic>> allAllocs = [];
        for (var d in details) {
          final dId = d['id'] as int;
          final allocs = await widget.db.readWorkerAllocations(dId);
          allAllocs.addAll(allocs);
        }
        allocsMap[oId] = allAllocs;
      }

      if (mounted) {
        setState(() {
          _allOrders = orders;
          _orderDetailsMap = detailsMap;
          _orderAllocationsMap = allocsMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading external operations data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          _tr('المهمات والأعمال الخارجية', 'Tâches & Opérations Externe', 'External Tasks & Operations', lang),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 1. قائمة علوية زالقة هوريزونتال (Horizontal Scrollable Menu Bar) ───────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _tabChip(
                    index: 0,
                    icon: Icons.square_outlined,
                    label: _tr('طلبات الزجاج', 'Commandes de Vitrage', 'Glass Orders', lang),
                    color: Colors.teal,
                    lang: lang,
                  ),
                  const SizedBox(width: 8),
                  _tabChip(
                    index: 1,
                    icon: Icons.shopping_cart_outlined,
                    label: _tr('شراء السلع والنواقص', 'Achats & Manquants', 'Goods Purchasing', lang),
                    color: Colors.indigo,
                    lang: lang,
                  ),
                  const SizedBox(width: 8),
                  _tabChip(
                    index: 2,
                    icon: Icons.construction_rounded,
                    label: _tr('التركيبات الميدانية', 'Poses & Installations', 'Site Installations', lang),
                    color: Colors.blue,
                    lang: lang,
                  ),
                  const SizedBox(width: 8),
                  _tabChip(
                    index: 3,
                    icon: Icons.report_problem_outlined,
                    label: _tr('إدارة التحفظات (Réserve)', 'Gestion des Réserves', 'Reserve Management', lang),
                    color: Colors.orange,
                    lang: lang,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // ── حقل البحث والسيرش السريع ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() => _searchQuery = val.toLowerCase().trim());
              },
              decoration: InputDecoration(
                hintText: _tr('بحث باسم الزبون أو رقم الطلبية...', 'Rechercher par client ou N°...', 'Search by client or order #...', lang),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                ),
              ),
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
            ),
          ),

          // ── 2. محتوى التبويب المختار ────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildTabContent(lang, isDark),
          ),
        ],
      ),
    );
  }

  // ── زر التبويب الأفقي ───────────────────────────────────────────────────
  Widget _tabChip({
    required int index,
    required IconData icon,
    required String label,
    required Color color,
    required AppLanguage lang,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedTabIndex == index;
    final bg = isSelected
        ? color.withValues(alpha: isDark ? 0.25 : 0.15)
        : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9));
    final fg = isSelected ? color : (isDark ? Colors.grey[400]! : Colors.grey[700]!);

    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : (isDark ? Colors.grey[800]! : Colors.grey[300]!),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── عرض المحتوى حسب التبويب ──────────────────────────────────────────────
  Widget _buildTabContent(AppLanguage lang, bool isDark) {
    switch (_selectedTabIndex) {
      case 0:
        return _buildGlassTab(lang, isDark);
      case 1:
        return _buildPurchasingTab(lang, isDark);
      case 2:
        return _buildInstallationsTab(lang, isDark);
      case 3:
        return _buildReservesTab(lang, isDark);
      default:
        return Container();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: طلبات الزجاج (Glass Orders Requisitions)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildGlassTab(AppLanguage lang, bool isDark) {
    final filteredOrders = _allOrders.where((o) {
      final status = o['status']?.toString() ?? '';
      final isRelevant = status != 'Draft' && status != 'Pending' && status != 'في الانتظار' && status != 'ملغاة';
      if (!isRelevant) return false;
      if (_searchQuery.isNotEmpty) {
        final clientName = '${o['firstname'] ?? ''} ${o['lastname'] ?? ''} ${o['id']}'.toLowerCase();
        return clientName.contains(_searchQuery);
      }
      return true;
    }).toList();

    if (filteredOrders.isEmpty) {
      return _emptyState(_tr('لا توجد طلبات زجاج حالية', 'Aucune commande de vitrage', 'No glass orders found', lang));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: filteredOrders.length,
      itemBuilder: (context, index) {
        final o = filteredOrders[index];
        final oId = o['id'] as int;
        final details = _orderDetailsMap[oId] ?? [];
        final clientName = '${o['firstname'] ?? ''} ${o['lastname'] ?? ''}'.trim();
        final currentGlassStatus = _glassStatusMap[oId] ?? 'pending';

        // تجميع أنواع ومساحات الزجاج
        final Map<String, double> glassSurfaceMap = {};
        for (var d in details) {
          final glassType = d['glass']?.toString().trim() ?? '';
          if (glassType.isNotEmpty) {
            final w = (d['largeur'] as num?)?.toDouble() ?? 0.0;
            final h = (d['hauteur'] as num?)?.toDouble() ?? 0.0;
            final qty = (d['quantity'] as num?)?.toInt() ?? 1;
            final surfaceM2 = (w / 1000.0) * (h / 1000.0) * qty;
            glassSurfaceMap[glassType] = (glassSurfaceMap[glassType] ?? 0.0) + surfaceM2;
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_tr("طلب زجاج للطلبية", "Comm. Vitrage N°", "Glass Req. #", lang)} #$oId',
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal),
                    ),
                    Text(
                      clientName.isNotEmpty ? clientName : _tr('عميل غير مسمى', 'Client non spécifié', 'Unnamed Client', lang),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.grey[300] : Colors.grey[800]),
                    ),
                  ],
                ),
                const Divider(height: 16),
                if (glassSurfaceMap.isEmpty)
                  Text(_tr('لا توجد تفاصيل زجاج محددة في النوافظ', 'Aucune spécification de vitrage', 'No glass specs listed', lang),
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey))
                else
                  ...glassSurfaceMap.entries.map((entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            const Icon(Icons.square_outlined, size: 14, color: Colors.teal),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${entry.value.toStringAsFixed(2)} م²',
                                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal),
                              ),
                            ),
                          ],
                        ),
                      )),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_tr('حالة الطلب:', 'Statut :', 'Status :', lang), style: const TextStyle(fontSize: 12, fontFamily: 'Cairo')),
                    Wrap(
                      spacing: 6,
                      children: [
                        _statusChoiceButton(oId, 'pending', _tr('قيد الطلب ⏳', 'En attente ⏳', 'Pending ⏳', lang), Colors.orange),
                        _statusChoiceButton(oId, 'ordered', _tr('تم الطلب 🚚', 'Commandé 🚚', 'Ordered 🚚', lang), Colors.blue),
                        _statusChoiceButton(oId, 'received', _tr('تم الاستلام 💎', 'Reçu 💎', 'Received 💎', lang), Colors.green),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final refreshNeeded = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GlassOrderReceptionScreen(
                            db: widget.db,
                            commandeId: oId,
                            clientName: clientName,
                          ),
                        ),
                      );
                      if (refreshNeeded == true) {
                        _loadData();
                      }
                    },
                    icon: const Icon(Icons.fact_check_outlined, size: 16),
                    label: Text(
                      _tr('تدقيق واستلام القياسات 📏', 'Vérifier & Recevoir les Mesures 📏', 'Check & Receive Measurements 📏', lang),
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusChoiceButton(int orderId, String value, String label, Color color) {
    final current = _glassStatusMap[orderId] ?? 'pending';
    final isSelected = current == value;

    return InkWell(
      onTap: () {
        setState(() => _glassStatusMap[orderId] = value);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: isSelected ? 1.5 : 0.8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : color,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: شراء السلع والنواقص (Goods Purchasing & Procurement)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPurchasingTab(AppLanguage lang, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shopping_cart_outlined, color: Colors.indigo, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tr('متابعة نواقص وسلع الورشة والموقع', 'Suivi des Manquants & Achats', 'Procurement & Missing Goods Tracking', lang),
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _tr('حساب ومتابعة كميات الألمنيوم والاكسسوارات المطلوب شراؤها', 'Calculer les besoins en profilés et accessoires à acheter', 'Calculate required profiles & accessories to purchase', lang),
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text(
            _tr('الطلبيات النشطة التي تتطلب متابعة التزويد:', 'Commandes nécessitant approvisionnement :', 'Active orders requiring supply:', lang),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),

          ..._allOrders.where((o) => o['status'] != 'Done' && o['status'] != 'ملغاة').map((o) {
            final oId = o['id'] as int;
            final clientName = '${o['firstname'] ?? ''} ${o['lastname'] ?? ''}'.trim();
            final details = _orderDetailsMap[oId] ?? [];

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined, color: Colors.indigo),
                title: Text('${_tr("طلبية", "Commande", "Order", lang)} #$oId - ${clientName.isNotEmpty ? clientName : "Client"}',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('${details.length} ${_tr("عنصر/نافذة", "éléments/fenêtres", "items/windows", lang)}', style: const TextStyle(fontSize: 11)),
                trailing: ElevatedButton.icon(
                  onPressed: () {
                    // فتح شاشة تفاصيل النواقص للطلبية
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (ctx) => _MissingItemsSheet(
                        db: widget.db,
                        orderId: oId,
                        clientName: clientName,
                        details: details,
                        lang: lang,
                        isDark: isDark,
                        onPurchaseCreated: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => AchatScreen(db: widget.db)),
                          );
                        },
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_shopping_cart, size: 14),
                  label: Text(_tr('توفير السلع', 'Approvisionner', 'Supply', lang), style: const TextStyle(fontSize: 11, fontFamily: 'Cairo')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 3: التركيبات الميدانية (Site Installations - Window by Window)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildInstallationsTab(AppLanguage lang, bool isDark) {
    final installationOrders = _allOrders.where((o) {
      final status = o['status']?.toString() ?? '';
      final isRelevant = status == 'Partial Distribution' ||
          status == 'Full Distribution' ||
          status == 'Installation' ||
          status == 'توزيع جزئي' ||
          status == 'توزيع كلي' ||
          status == 'تركيب';
      if (!isRelevant) return false;
      if (_searchQuery.isNotEmpty) {
        final clientName = '${o['firstname'] ?? ''} ${o['lastname'] ?? ''} ${o['id']}'.toLowerCase();
        return clientName.contains(_searchQuery);
      }
      return true;
    }).toList();

    if (installationOrders.isEmpty) {
      return _emptyState(_tr('لا توجد نوافذ جاهزة للتركيب الميداني حالياً', 'Aucune fenêtre prête à la pose', 'No windows pending site installation', lang));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: installationOrders.length,
      itemBuilder: (context, index) {
        final o = installationOrders[index];
        final oId = o['id'] as int;
        final details = _orderDetailsMap[oId] ?? [];
        final allocs = _orderAllocationsMap[oId] ?? [];
        final clientName = '${o['firstname'] ?? ''} ${o['lastname'] ?? ''}'.trim();

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          child: ExpansionTile(
            title: Row(
              children: [
                const Icon(Icons.construction, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_tr("تركيب طلبية", "Pose Commande", "Site Installation", lang)} #$oId - ${clientName.isNotEmpty ? clientName : "Client"}',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${_tr("الحالة:", "Statut :", "Status :", lang)} ${o['status']} (${details.length} ${_tr("عنصر", "éléments", "items", lang)})',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
            children: [
              const Divider(height: 1),
              ...allocs.map((t) {
                final allocId = t['id'] as int;
                final isInstalled = t['is_installed'] == 1;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        isInstalled ? Icons.check_circle : Icons.build_circle_outlined,
                        color: isInstalled ? Colors.green : Colors.blue,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${Localization.translate(t['window_type']?.toString() ?? 'Window', lang)} (${t['largeur']} × ${t['hauteur']} مم)',
                              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isInstalled
                                  ? _tr('تم التركيب والمصادقة الميدانية ✅', 'Posé & Validé sur site ✅', 'Installed on site ✅', lang)
                                  : _tr('جاهز للتركيب بالموقع 🏗️', 'Prêt pour la pose 🏗️', 'Ready for site installation 🏗️', lang),
                              style: TextStyle(fontSize: 11, color: isInstalled ? Colors.green : Colors.orange),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final newVal = isInstalled ? 0 : 1;
                          setState(() {
                            t['is_installed'] = newVal;
                          });
                          await widget.db.syncOrderAndAllocationsStatus(oId);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(newVal == 1
                                  ? _tr('تم تسجيل تركيب النافذة بالموقع ✅', 'Pose de fenêtre enregistrée sur site ✅', 'Site window installation recorded ✅', lang)
                                  : _tr('تم إلغاء حالة التركيب', 'Statut de pose annulé', 'Installation status reset', lang)),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isInstalled ? Colors.green.shade600 : Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                        child: Text(
                          isInstalled ? _tr('تم التركيب ✅', 'Posé ✅', 'Installed ✅', lang) : _tr('زر تركيب', 'Poser', 'Install', lang),
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 4: إدارة وتصفية التحفظات (Reserve Clearance - Réserve)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildReservesTab(AppLanguage lang, bool isDark) {
    final reserveOrders = _allOrders.where((o) => o['status'] == 'Reserve' || o['status'] == 'تحت التحفظ' || o['status'] == 'Réserve').toList();

    if (reserveOrders.isEmpty) {
      return _emptyState(_tr('لا توجد طلبات في حالة تحفظ حالياً (Réserve)', 'Aucune réserve en cours', 'No current reserve orders', lang));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: reserveOrders.length,
      itemBuilder: (context, index) {
        final o = reserveOrders[index];
        final oId = o['id'] as int;
        final clientName = '${o['firstname'] ?? ''} ${o['lastname'] ?? ''}'.trim();
        final details = _orderDetailsMap[oId] ?? [];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.report_problem, color: Colors.orange, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          '${_tr("تحفظ طلبية", "Réserve Commande", "Reserve Order", lang)} #$oId',
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange),
                        ),
                      ],
                    ),
                    Text(
                      clientName.isNotEmpty ? clientName : _tr('عميل غير مسمى', 'Client non spécifié', 'Unnamed Client', lang),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Text(
                  _tr('ملاحظات عدم الاقتناع أو تعديلات الموقع المطلوب تسويتها:', 'Remarques ou réserves à lever :', 'Reserve notes to resolve:', lang),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                ),
                const SizedBox(height: 8),

                ...details.map((d) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.build_circle_outlined, size: 14, color: Colors.orange),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${Localization.translate(d['window_type']?.toString() ?? 'Window', lang)} (${d['largeur']} × ${d['hauteur']} مم)',
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    )),

                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await widget.db.updateCommandeStatus(oId, 'Done');
                      await _loadData();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_tr('تمت تصفية جميع التحفظات ونقل الطلبية إلى منتهية (Done) ✅', 'Toutes les réserves levées. Commande terminée (Done) ✅', 'All reserves cleared. Order completed (Done) ✅', lang)),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      _tr('إلغاء التحفظ وإنهاء الطلبية ✅', 'Lever la réserve & Terminer ✅', 'Clear Reserve & Complete ✅', lang),
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── حالة القائمة الخالية ──────────────────────────────────────────────
  Widget _emptyState(String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: isDark ? Colors.grey[600] : Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// شاشة النواقص السفلية — تعرض سلع الطلبية وتتيح فتح موديول المشتريات
// ══════════════════════════════════════════════════════════════════════════════
class _MissingItemsSheet extends StatelessWidget {
  final SqlDatabase db;
  final int orderId;
  final String clientName;
  final List<Map<String, dynamic>> details;
  final AppLanguage lang;
  final bool isDark;
  final VoidCallback onPurchaseCreated;

  const _MissingItemsSheet({
    required this.db,
    required this.orderId,
    required this.clientName,
    required this.details,
    required this.lang,
    required this.isDark,
    required this.onPurchaseCreated,
  });

  String _tr(String ar, String fr, String en) {
    if (lang == AppLanguage.french) return fr;
    if (lang == AppLanguage.english) return en;
    return ar;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            // ── مقبض السحب ──────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── العنوان ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.shopping_cart_outlined, color: Colors.indigo),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_tr("نواقص الطلبية", "Manquants commande", "Order missing items")} #$orderId',
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        if (clientName.isNotEmpty)
                          Text(
                            clientName,
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade500),
                          ),
                      ],
                    ),
                  ),
                  // ── زر إنشاء طلب شراء ───────────────────────────────
                  ElevatedButton.icon(
                    onPressed: onPurchaseCreated,
                    icon: const Icon(Icons.add_shopping_cart, size: 16),
                    label: Text(
                      _tr('فتح المشتريات', 'Ouvrir Achats', 'Open Purchases'),
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // ── قائمة السلع ─────────────────────────────────────────────
            details.isEmpty
                ? Expanded(
                    child: Center(
                      child: Text(
                        _tr('لا توجد سلع مسجلة لهذه الطلبية', 'Aucun article enregistré', 'No items recorded'),
                        style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                      ),
                    ),
                  )
                : Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(14),
                      itemCount: details.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = details[index];
                        final height = item['hauteur'] ?? item['height'] ?? 0;
                        final width = item['largeur'] ?? item['width'] ?? 0;
                        final qty = item['nbr'] ?? item['quantity'] ?? 1;
                        final glass = (item['glass'] ?? '').toString();
                        final color = (item['color'] ?? '').toString();
                        final windowType = (item['window_type'] ?? '').toString();
                        final game = (item['game'] ?? '').toString();

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.indigo.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            children: [
                              // رقم العنصر
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // تفاصيل
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // النوع / اللعبة
                                    Text(
                                      windowType.isNotEmpty ? windowType : game.isNotEmpty ? game : _tr('نافذة', 'Fenêtre', 'Window'),
                                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(height: 3),
                                    // القياسات
                                    Text(
                                      '$height × $width مم',
                                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade600),
                                    ),
                                    if (glass.isNotEmpty || color.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        [
                                          if (glass.isNotEmpty) _tr('زجاج', 'Vitrage', 'Glass') + ': $glass',
                                          if (color.isNotEmpty) _tr('لون', 'Couleur', 'Color') + ': $color',
                                        ].join(' — '),
                                        style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // الكمية
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'x$qty',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.indigo,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ],
        );
      },
    );
  }
}
