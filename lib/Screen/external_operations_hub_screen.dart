import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import 'glass_order_reception_screen.dart';
import 'achat_screen.dart';
import '../widgets/lazy_window_image.dart';

import 'dart:async';
import '../services/cloud_sync_service.dart';

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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // خريطة لتأكيدات طلبات الزجاج
  final Map<int, String> _glassStatusMap = {}; // orderId -> status
  StreamSubscription? _syncSub;
  bool _isLocalChangePending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.isManager && !settings.canAccessExternalOperations()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted && !_isLocalChangePending) {
        _loadDataQuietly();
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
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

  String _formatDateStr(dynamic str) {
    if (str == null || str.toString().trim().isEmpty) return '-';
    try {
      final dt = DateTime.parse(str.toString());
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return str.toString();
    }
  }

  List<Map<String, dynamic>> _fieldInstallationAllocations = [];
  List<Map<String, dynamic>> _reserveAllocations = [];

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final orders = await widget.db.readCommandesWithClients();
      final fieldAllocs = await widget.db.readFieldInstallationAllocations();
      final reserveAllocs = await widget.db.readReserveAllocations();
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
          _fieldInstallationAllocations = fieldAllocs;
          _reserveAllocations = reserveAllocs;
          _orderDetailsMap = detailsMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading external operations data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDataQuietly() async {
    try {
      final orders = await widget.db.readCommandesWithClients();
      final fieldAllocs = await widget.db.readFieldInstallationAllocations();
      final reserveAllocs = await widget.db.readReserveAllocations();
      if (mounted) {
        setState(() {
          _allOrders = orders;
          _fieldInstallationAllocations = fieldAllocs;
          _reserveAllocations = reserveAllocs;
        });
      }
    } catch (e) {
      debugPrint('Error loading data quietly: $e');
    }
  }

  String _formatDate(String? isoStr) {
    if (isoStr == null || isoStr.trim().isEmpty) return '';
    try {
      final dt = DateTime.parse(isoStr).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoStr;
    }
  }

  String _workerAssignmentKey(Map<String, dynamic> worker) {
    final uid = (worker['uid'] ?? '').toString().trim();
    if (uid.isNotEmpty) return uid;
    final id = (worker['id'] ?? '').toString().trim();
    if (id.isNotEmpty) return id;
    return (worker['email'] ?? '').toString().trim();
  }

  bool _isInstallationAssignedToCurrentUser(Map<String, dynamic> allocation) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final uid = user.uid.trim().toLowerCase();
    final email = (user.email ?? '').trim().toLowerCase();
    final installUid = (allocation['installation_worker_uid'] ??
            allocation['worker_uid'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    if (installUid.isEmpty) return false;
    return (uid.isNotEmpty && installUid == uid) ||
        (email.isNotEmpty && installUid == email);
  }

  void _showInstallationWorkerOnlyNotice(AppLanguage lang) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            '⚠️ التحكم في التركيب مخصص لعامل التركيب المسند له هذا العنصر',
            '⚠️ Seul le poseur affecté peut modifier cette installation',
            '⚠️ Only the assigned installer can update this installation',
            lang,
          ),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 50, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _showInstallationWorkerDialog(
    Map<String, dynamic> allocation,
    AppLanguage lang,
  ) async {
    final allocId = (allocation['id'] as num?)?.toInt() ?? 0;
    if (allocId <= 0) return;

    final workers = await widget.db.readEmployees();
    if (!mounted) return;
    if (workers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'لا يوجد عمال مسجلون لاختيار عامل التركيب',
              'Aucun ouvrier enregistré pour la pose',
              'No workers available for installation',
              lang,
            ),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        final currentKey = (allocation['installation_worker_uid'] ??
                allocation['worker_uid'] ??
                '')
            .toString()
            .trim();
        return AlertDialog(
          title: Text(
            _tr(
              'تعديل إسناد التركيب',
              'Modifier l\'ouvrier de pose',
              'Edit installation worker',
              lang,
            ),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView.separated(
              itemCount: workers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final worker = workers[index];
                final key = _workerAssignmentKey(worker);
                final name = (worker['name'] ?? key).toString();
                final role = (worker['job_role'] ?? '').toString().trim();
                final isSelected = key.isNotEmpty && key == currentKey;
                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isSelected ? Colors.teal : null,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: role.isEmpty
                      ? null
                      : Text(role, style: const TextStyle(fontFamily: 'Cairo')),
                  onTap: key.isEmpty ? null : () => Navigator.pop(ctx, worker),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                _tr('إلغاء', 'Annuler', 'Cancel', lang),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          ],
        );
      },
    );

    if (selected == null) return;
    final workerKey = _workerAssignmentKey(selected);
    if (workerKey.isEmpty) return;
    final workerName = (selected['name'] ?? workerKey).toString();

    _isLocalChangePending = true;
    final nowIso = DateTime.now().toIso8601String();
    setState(() {
      for (final list in [_fieldInstallationAllocations, _reserveAllocations]) {
        for (var i = 0; i < list.length; i++) {
          if ((list[i]['id'] as num?)?.toInt() == allocId) {
            final updated = Map<String, dynamic>.from(list[i]);
            updated['installation_worker_uid'] = workerKey;
            updated['installation_worker_name'] = workerName;
            updated['installation_assigned_at'] = nowIso;
            list[i] = updated;
          }
        }
      }
    });

    try {
      await widget.db.updateWorkerAllocationInstallationWorker(
        allocId,
        workerKey,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'تم تغيير عامل التركيب بنجاح',
                'Ouvrier de pose modifié avec succès',
                'Installation worker updated successfully',
                lang,
              ),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating installation worker: $e');
    } finally {
      await Future.delayed(const Duration(milliseconds: 800));
      _isLocalChangePending = false;
    }
  }

  Future<void> _confirmResetInstallationData(BuildContext context, AppLanguage lang) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('تأكيد المسح الكلي للعمليات الخارجية', 'Confirmation de réinitialisation', 'Confirm Reset', lang), style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        content: Text(_tr('هل أنت تأكد من تصفير ومسح جميع بيانات طلبات الزجاج، الشراء والنواقص، والتركيبات والتحفظات الميدانية بالتطوير؟', 'Voulez-vous réinitialiser toutes les données d\'opérations externes ?', 'Do you want to reset all external operations data?', lang), style: const TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_tr('إلغاء', 'Annuler', 'Cancel', lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr('مسح كلي 🧹', 'Effacer tout 🧹', 'Clear All 🧹', lang), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.db.clearAllInstallationDataFromCloudAndLocal();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr('تم مسح وتصفير كافة بيانات العمليات الخارجية (الزجاج، الشراء والنواقص، التركيبات، والتحفظات) بنجاح 🧹', 'Données d\'opérations externes réinitialisées 🧹', 'External operations data cleared 🧹', lang)),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        backgroundColor: isDark ? const Color(0xFF0F172A) : Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        title: Text(
          _tr('المهمات والأعمال الخارجية', 'Tâches & Opérations Externe', 'External Tasks & Operations', lang),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            tooltip: _tr('تصفير العمليات الخارجية والزجاج والمشتريات (للتطوير)', 'Vider les données d\'opérations (Dev)', 'Clear Operations Data (Dev)', lang),
            onPressed: () => _confirmResetInstallationData(context, lang),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await widget.db.syncWorkerAllocationsStatusFromCloud();
              await _loadData();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── شريط تصفير البيانات البارز للتطوير ─────────────────────────
          Container(
            color: Colors.red.shade900,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _tr('🧪 تصفير العمليات والزجاج والمشتريات (للتطوير)', '🧪 Réinitialiser Opérations (Dev)', '🧪 Reset Operations (Dev)', lang),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red.shade900,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  onPressed: () => _confirmResetInstallationData(context, lang),
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: Text(
                    _tr('تصفير الكل 🧹', 'Effacer tout 🧹', 'Clear All 🧹', lang),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
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
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final canEditInstallationWorker = settings.isManager;
    final filtered = _fieldInstallationAllocations.where((t) {
      if (_searchQuery.isEmpty) return true;
      final clientName = '${t['firstname'] ?? ''} ${t['lastname'] ?? ''}'.toLowerCase();
      final workerName = (t['worker_name'] ?? '').toString().toLowerCase();
      final installationWorkerName =
          (t['installation_worker_name'] ?? '').toString().toLowerCase();
      final wType = (t['window_type'] ?? '').toString().toLowerCase();
      final oId = (t['id_commandes'] ?? '').toString();
      return clientName.contains(_searchQuery) ||
          workerName.contains(_searchQuery) ||
          installationWorkerName.contains(_searchQuery) ||
          wType.contains(_searchQuery) ||
          oId.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return _emptyState(_tr('لا توجد نوافذ محولة للتركيبات الميدانية حالياً', 'Aucune fenêtre en pose sur site', 'No windows pending site installation', lang));
    }

    // تجميع العناصر مرتبة حسب الزبون
    final Map<int, List<Map<String, dynamic>>> clientGroupedMap = {};
    for (var item in filtered) {
      final clientId = (item['client_id'] as num?)?.toInt() ?? 0;
      clientGroupedMap.putIfAbsent(clientId, () => []).add(item);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: clientGroupedMap.keys.length,
      itemBuilder: (context, index) {
        final clientId = clientGroupedMap.keys.elementAt(index);
        final clientItems = clientGroupedMap[clientId]!;
        final firstItem = clientItems.first;
        final clientName = '${firstItem['firstname'] ?? ''} ${firstItem['lastname'] ?? ''}'.trim();
        final displayClientName = clientName.isNotEmpty ? clientName : _tr('زبون غير محدد', 'Client Inconnu', 'Unknown Client', lang);

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1️⃣ رأس بطاقة الزبون
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_rounded, color: Colors.blue, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_tr("الزبون:", "Client :", "Client:", lang)} $displayClientName',
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${clientItems.length} ${_tr("عناصر", "éléments", "items", lang)}',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),

                // 2️⃣ قائمة عناصر الزبون مرتبة
                ...clientItems.map((t) {
                  final allocId = (t['id'] as num?)?.toInt() ?? 0;
                  final orderId = (t['id_commandes'] as num?)?.toInt() ?? 0;
                  final windowType = t['window_type']?.toString() ?? 'Window';
                  final largeur = (t['largeur'] as num?)?.toInt() ?? 0;
                  final hauteur = (t['hauteur'] as num?)?.toInt() ?? 0;
                  final qty = (t['quantity'] as num?)?.toInt() ?? (t['detail_quantity'] as num?)?.toInt() ?? 1;
                  final workerName = (t['worker_name'] ?? '').toString().trim();
                  final installationWorkerName =
                      (t['installation_worker_name'] ?? workerName)
                          .toString()
                          .trim();

                  final isDistributed = t['is_distributed'] == 1;
                  final isInstalled = t['is_installed'] == 1;
                  final isCompleted = t['is_completed'] == 1;
                  final canControlInstallation =
                      !settings.isManager && _isInstallationAssignedToCurrentUser(t);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 75,
                              height: 75,
                              child: LazyWindowImage(
                                db: widget.db,
                                detailId: (t['commande_detail_id'] as num?)?.toInt() ?? 0,
                                initialImagePath: t['drawing_image_path'] ?? '',
                                drawingImageBase64: t['drawing_image_base64'],
                                partitionsJson: t['partitions_json'],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_tr("طلبية", "Commande", "Order", lang)} #$orderId | $windowType',
                                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_tr("الأبعاد:", "Dims:", "Dims:", lang)} ${largeur}cm × ${hauteur}cm | ${_tr("الكمية:", "Qté:", "Qty:", lang)} $qty',
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                                  ),
                                  if (workerName.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      '👷 ${_tr("العامل الصانع:", "Ouvrier:", "Worker:", lang)} $workerName',
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.blue),
                                    ),
                                  ],
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '🛠️ ${_tr("عامل التركيب:", "Poseur:", "Installer:", lang)} ${installationWorkerName.isNotEmpty ? installationWorkerName : _tr("غير محدد", "Non défini", "Not set", lang)}',
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 11,
                                            color: Colors.teal,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (canEditInstallationWorker)
                                        Tooltip(
                                          message: _tr(
                                            'تعديل عامل التركيب',
                                            'Modifier le poseur',
                                            'Edit installer',
                                            lang,
                                          ),
                                          child: IconButton(
                                            visualDensity: VisualDensity.compact,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 32,
                                            ),
                                            padding: EdgeInsets.zero,
                                            icon: const Icon(
                                              Icons.edit_location_alt_rounded,
                                              color: Colors.teal,
                                              size: 19,
                                            ),
                                            onPressed: () =>
                                                _showInstallationWorkerDialog(
                                              t,
                                              lang,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  
                                  // 🕒 إظهار تواريخ الإسناد والتوزيع والتركيب الميدانية
                                  Builder(builder: (ctx) {
                                    final assignedAtStr = _formatDate(t['assigned_at']?.toString());
                                    final distributedAtStr = _formatDate(t['distributed_at']?.toString());
                                    final installedAtStr = _formatDate(t['installed_at']?.toString());

                                    if (assignedAtStr.isEmpty && distributedAtStr.isEmpty && installedAtStr.isEmpty) {
                                      return const SizedBox.shrink();
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          if (assignedAtStr.isNotEmpty)
                                            Text('📅 ${_tr("إسناد:", "Assigné:", "Assigned:", lang)} $assignedAtStr', style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.grey)),
                                          if (distributedAtStr.isNotEmpty)
                                            Text('🚚 ${_tr("توزيع:", "Distribué:", "Distributed:", lang)} $distributedAtStr', style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.indigo, fontWeight: FontWeight.bold)),
                                          if (installedAtStr.isNotEmpty)
                                            Text('🛠️ ${_tr("تركيب:", "Installé:", "Installed:", lang)} $installedAtStr', style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // 3️⃣ الأزرار (تم التوزيع - تم التركيب - تم الانتهاء - تحفظ)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            // 1. زر تم التوزيع
                            ElevatedButton.icon(
                              onPressed: () async {
                                if (!canControlInstallation) {
                                  _showInstallationWorkerOnlyNotice(lang);
                                  return;
                                }
                                _isLocalChangePending = true;
                                final newVal = isDistributed ? 0 : 1;
                                final nowIso = DateTime.now().toIso8601String();
                                setState(() {
                                  t['is_distributed'] = newVal;
                                  t['distributed_at'] = newVal == 1 ? nowIso : null;
                                });
                                await widget.db.updateWorkerAllocationDistribution(allocId, newVal);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(newVal == 1 ? 'تم تسجيل خروج وتوزيع النافذة للميدان 🚚✅' : 'تم إلغاء حالة التوزيع', style: const TextStyle(fontFamily: 'Cairo')),
                                      duration: const Duration(seconds: 1),
                                      behavior: SnackBarBehavior.floating,
                                      margin: const EdgeInsets.only(bottom: 50, left: 16, right: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                }
                                await Future.delayed(const Duration(milliseconds: 1500));
                                _isLocalChangePending = false;
                              },
                              icon: Icon(
                                isDistributed ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                size: 16,
                              ),
                              label: Text(
                                isDistributed
                                    ? _tr('تم التوزيع ✅', 'Distribué ✅', 'Distributed ✅', lang)
                                    : _tr('تم التوزيع 🚚', 'Distribué 🚚', 'Distributed 🚚', lang),
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDistributed ? Colors.indigo : Colors.grey.shade400,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                            ),

                            // 2. زر تم التركيب (يتطلب تم التوزيع أولاً)
                            ElevatedButton.icon(
                              onPressed: () async {
                                if (!canControlInstallation) {
                                  _showInstallationWorkerOnlyNotice(lang);
                                  return;
                                }

                                if (!isDistributed) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _tr(
                                          '⚠️ يجب تسجيل وتأكيد [تم التوزيع 🚚] أولاً قبل التركيب بالموقع!',
                                          '⚠️ Veuillez d\'abord valider la distribution [Distribué 🚚] !',
                                          '⚠️ Please validate distribution [Distributed 🚚] first!',
                                          lang,
                                        ),
                                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                      ),
                                      backgroundColor: Colors.orange.shade800,
                                      behavior: SnackBarBehavior.floating,
                                      margin: const EdgeInsets.only(bottom: 50, left: 16, right: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                  return;
                                }

                                _isLocalChangePending = true;
                                final newVal = isInstalled ? 0 : 1;
                                final nowIso = DateTime.now().toIso8601String();
                                setState(() {
                                  t['is_installed'] = newVal;
                                  t['installed_at'] = newVal == 1 ? nowIso : null;
                                });
                                await widget.db.updateWorkerAllocationInstallation(allocId, newVal);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(newVal == 1 ? 'تم تسجيل تركيب النافذة بالموقع 🛠️✅' : 'تم إلغاء حالة التركيب', style: const TextStyle(fontFamily: 'Cairo')),
                                      duration: const Duration(seconds: 1),
                                      behavior: SnackBarBehavior.floating,
                                      margin: const EdgeInsets.only(bottom: 50, left: 16, right: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                }
                                await Future.delayed(const Duration(milliseconds: 1500));
                                _isLocalChangePending = false;
                              },
                              icon: Icon(
                                isInstalled ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                size: 16,
                              ),
                              label: Text(
                                isInstalled
                                    ? _tr('تم التركيب ✅', 'Installé ✅', 'Installed ✅', lang)
                                    : _tr('تم التركيب 🛠️', 'Installé 🛠️', 'Installed 🛠️', lang),
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isInstalled ? Colors.teal : Colors.grey.shade400,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                            ),

                            // 3. زر تم الانتهاء (يتطلب تم التركيب أولاً ورصد خلو العناصر من أي تحفظ)
                            ElevatedButton.icon(
                              onPressed: () async {
                                if (!canControlInstallation) {
                                  _showInstallationWorkerOnlyNotice(lang);
                                  return;
                                }

                                if (!isInstalled) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _tr(
                                          '⚠️ يجب تسجيل وتأكيد [تم التركيب 🛠️] بالموقع أولاً قبل الانتهاء كلياً والأرشفة!',
                                          '⚠️ Veuillez d\'abord valider l\'installation [Installé 🛠️] avant de terminer !',
                                          '⚠️ Please validate installation [Installed 🛠️] first before completion!',
                                          lang,
                                        ),
                                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                      ),
                                      backgroundColor: Colors.orange.shade800,
                                      behavior: SnackBarBehavior.floating,
                                      margin: const EdgeInsets.only(bottom: 50, left: 16, right: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                  return;
                                }

                                final hasReserve = t['has_reserve'] == 1;
                                if (hasReserve) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _tr(
                                          '🛑 لا يمكن إنهاء هذا العنصر لوجود تحفظات ونقائص مسجلة! يجب رفع وإلغاء التحفظ أولاً من صفحة إدارة التحفظات (Réserve).',
                                          '🛑 Impossible de terminer : des réserves sont actives. Veuillez lever les réserves d\'abord.',
                                          '🛑 Cannot complete: active reserves exist. Please clear reserves first.',
                                          lang,
                                        ),
                                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                      ),
                                      backgroundColor: Colors.red.shade800,
                                      behavior: SnackBarBehavior.floating,
                                      margin: const EdgeInsets.only(bottom: 50, left: 16, right: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      duration: const Duration(seconds: 4),
                                    ),
                                  );
                                  return;
                                }

                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(_tr('إتمام العمل والتحويل للأرشيف', 'Terminer et archiver', 'Complete and archive', lang), style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                    content: Text(
                                      _tr('هل تم الانتهاء كلياً من تركيب هذا العنصر والتخلص من تحفظاته ونقله نهائياً للأرشيف؟', 'Voulez-vous vraiment terminer et archiver cet élément ?', 'Are you sure you want to complete and archive this item?', lang),
                                      style: const TextStyle(fontFamily: 'Cairo'),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: Text(_tr('إلغاء', 'Annuler', 'Cancel', lang), style: const TextStyle(fontFamily: 'Cairo')),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: Text(_tr('تأكيد الانتهاء', 'Confirmer', 'Confirm', lang), style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  _isLocalChangePending = true;
                                  setState(() {
                                    t['is_completed'] = 1;
                                  });
                                  await widget.db.updateWorkerAllocationCompletion(allocId, 1);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text('تم الانتهاء بنجاح وتحويل النافذة للأرشيف 📦✅', style: TextStyle(fontFamily: 'Cairo')),
                                        backgroundColor: Colors.green,
                                        behavior: SnackBarBehavior.floating,
                                        margin: const EdgeInsets.only(bottom: 50, left: 16, right: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                    );
                                  }
                                  await Future.delayed(const Duration(milliseconds: 1500));
                                  _isLocalChangePending = false;
                                }
                              },
                              icon: Icon(
                                isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                size: 16,
                                color: isCompleted ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
                              ),
                              label: Text(
                                isCompleted
                                    ? _tr('تم الانتهاء ✅', 'Terminé ✅', 'Completed ✅', lang)
                                    : _tr('تم الانتهاء', 'Terminé', 'Completed', lang),
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isCompleted ? Colors.white : (isDark ? Colors.white : Colors.black87),
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isCompleted ? Colors.green.shade600 : (isDark ? const Color(0xFF334155) : Colors.white),
                                foregroundColor: isCompleted ? Colors.white : (isDark ? Colors.white : Colors.black87),
                                side: isCompleted ? BorderSide.none : BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              ),
                            ),

                            // 4. زر تحفظ (Réserve) - يتطلب تم التوزيع أولاً
                            ElevatedButton.icon(
                              onPressed: () async {
                                if (!canControlInstallation) {
                                  _showInstallationWorkerOnlyNotice(lang);
                                  return;
                                }

                                if (!isDistributed) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _tr(
                                          '⚠️ لا يمكن تسجيل تحفظ إلا بعد توزيع ونقل النافذة للميدان [تم التوزيع 🚚]!',
                                          '⚠️ Les réserves sont possibles uniquement après distribution [Distribué 🚚] !',
                                          '⚠️ Reserves can only be logged after distribution [Distributed 🚚]!',
                                          lang,
                                        ),
                                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                      ),
                                      backgroundColor: Colors.orange.shade800,
                                      behavior: SnackBarBehavior.floating,
                                      margin: const EdgeInsets.only(bottom: 50, left: 16, right: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                  return;
                                }
                                final hasReserve = t['has_reserve'] == 1;
                                final currentNotes = t['reserve_notes']?.toString() ?? '';
                                final notesCtrl = TextEditingController(text: currentNotes);

                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                      hasReserve
                                          ? _tr('تعديل أو إلغاء التحفظ (Réserve)', 'Modifier ou annuler réserve', 'Edit or cancel reserve', lang)
                                          : _tr('تسجيل نقائص النافذة / تحفظ ⚠️', 'Saisir les réserves ⚠️', 'Log window reserve ⚠️', lang),
                                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_tr('ما هي النقائص والتفاصيل الميدانية لهاته النافذة؟', 'Quels sont les détails des réserves ?', 'What are the details of the reserves?', lang), style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: notesCtrl,
                                          maxLines: 3,
                                          decoration: InputDecoration(
                                            hintText: _tr('أدخل النقائص: مثال: ناقص مقبض، زجاج مكسور...', 'Saisir les réserves...', 'Enter reserve details...', lang),
                                            border: const OutlineInputBorder(),
                                          ),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      if (hasReserve)
                                        TextButton(
                                          onPressed: () async {
                                            Navigator.pop(ctx, false);
                                            _isLocalChangePending = true;
                                            setState(() {
                                              t['has_reserve'] = 0;
                                              t['reserve_notes'] = null;
                                            });
                                            await widget.db.updateWorkerAllocationReserve(allocId, 0, null);
                                            await Future.delayed(const Duration(milliseconds: 1500));
                                            _isLocalChangePending = false;
                                          },
                                          child: Text(_tr('إلغاء التحفظ', 'Annuler réserve', 'Cancel reserve', lang), style: const TextStyle(fontFamily: 'Cairo', color: Colors.red)),
                                        ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, null),
                                        child: Text(_tr('إغلاق', 'Fermer', 'Close', lang), style: const TextStyle(fontFamily: 'Cairo')),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: Text(_tr('حفظ التحفظ', 'Enregistrer', 'Save reserve', lang), style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  final txt = notesCtrl.text.trim();
                                  if (txt.isNotEmpty) {
                                    _isLocalChangePending = true;
                                    setState(() {
                                      t['has_reserve'] = 1;
                                      t['reserve_notes'] = txt;
                                    });
                                    await widget.db.updateWorkerAllocationReserve(allocId, 1, txt);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: const Text('تم تسجيل النقائص والتحفظ بنجاح ونقله لصفحة إدارة التحفظات ⚠️✅', style: TextStyle(fontFamily: 'Cairo')),
                                          backgroundColor: Colors.orange,
                                          behavior: SnackBarBehavior.floating,
                                          margin: const EdgeInsets.only(bottom: 50, left: 16, right: 16),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      );
                                    }
                                    await Future.delayed(const Duration(milliseconds: 1500));
                                    _isLocalChangePending = false;
                                  }
                                }
                              },
                              icon: Icon(
                                t['has_reserve'] == 1 ? Icons.warning_rounded : Icons.warning_amber_rounded,
                                size: 16,
                              ),
                              label: Text(
                                t['has_reserve'] == 1
                                    ? _tr('تحفظ مسجّل ⚠️', 'Réserve Inscrite ⚠️', 'Reserve Logged ⚠️', lang)
                                    : _tr('تحفظ ⚠️', 'Réserve ⚠️', 'Reserve ⚠️', lang),
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: t['has_reserve'] == 1 ? Colors.orange.shade800 : Colors.grey.shade400,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 4: إدارة وتصفية التحفظات (Reserve Clearance - Réserve)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildReservesTab(AppLanguage lang, bool isDark) {
    final filtered = _reserveAllocations.where((t) {
      if (_searchQuery.isEmpty) return true;
      final clientName = '${t['firstname'] ?? ''} ${t['lastname'] ?? ''}'.toLowerCase();
      final workerName = (t['worker_name'] ?? '').toString().toLowerCase();
      final wType = (t['window_type'] ?? '').toString().toLowerCase();
      final notes = (t['reserve_notes'] ?? '').toString().toLowerCase();
      return clientName.contains(_searchQuery) || workerName.contains(_searchQuery) || wType.contains(_searchQuery) || notes.contains(_searchQuery);
    }).toList();

    if (filtered.isEmpty) {
      return _emptyState(_tr('لا توجد نوافذ بها تحفظات مسجلة حالياً (Réserve)', 'Aucune réserve en cours', 'No active window reserves', lang));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final t = filtered[index];
        final allocId = (t['id'] as num?)?.toInt() ?? 0;
        final orderId = (t['id_commandes'] as num?)?.toInt() ?? 0;
        final clientName = '${t['firstname'] ?? ''} ${t['lastname'] ?? ''}'.trim();
        final windowType = t['window_type']?.toString() ?? 'Window';
        final largeur = (t['largeur'] as num?)?.toInt() ?? 0;
        final hauteur = (t['hauteur'] as num?)?.toInt() ?? 0;
        final qty = (t['quantity'] as num?)?.toInt() ?? (t['detail_quantity'] as num?)?.toInt() ?? 1;
        final workerName = (t['worker_name'] ?? '').toString().trim();
        final notes = t['reserve_notes']?.toString() ?? '';
        final reserveAt = _formatDateStr(t['reserve_at']);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${_tr("تحفظ نافذة طلبية", "Réserve Commande", "Window Reserve", lang)} #$orderId',
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange),
                      ),
                    ),
                    Text(
                      clientName.isNotEmpty ? clientName : _tr('زبون غير محدد', 'Client Inconnu', 'Unknown Client', lang),
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Divider(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 75,
                      height: 75,
                      child: LazyWindowImage(
                        db: widget.db,
                        detailId: (t['commande_detail_id'] as num?)?.toInt() ?? 0,
                        initialImagePath: t['drawing_image_path'] ?? '',
                        drawingImageBase64: t['drawing_image_base64'],
                        partitionsJson: t['partitions_json'],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            windowType,
                            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_tr("الأبعاد:", "Dims:", "Dims:", lang)} ${largeur}cm × ${hauteur}cm | ${_tr("الكمية:", "Qté:", "Qty:", lang)} $qty',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                          ),
                          if (workerName.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '👷 ${_tr("العامل الصانع:", "Ouvrier:", "Worker:", lang)} $workerName',
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.blue),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // صندوق النقائص والتفاصيل
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.report_problem_rounded, size: 16, color: Colors.orange),
                          const SizedBox(width: 6),
                          Text(
                            '${_tr("تفاصيل النقائص والتحفظات الميدانية:", "Détails des réserves :", "Reserve details:", lang)} ($reserveAt)',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notes.isNotEmpty ? notes : _tr('لم تسجل تفاصيل', 'Pas de détails', 'No details', lang),
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final isManager = Provider.of<AppSettingsProvider>(context, listen: false).isManager;
                      if (isManager) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _tr('⚠️ أزرار رفع وإلغاء التحفظ مخصصة للعامل فقط! حساب المدير للعرض والمتابعة فقط 👁️', '⚠️ Seul l\'ouvrier peut lever les réserves ! Compte gérant en lecture seule 👁️', '⚠️ Only worker can clear reserves! Manager account is read-only 👁️', lang),
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            backgroundColor: Colors.orange,
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.only(bottom: 50, left: 16, right: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                        return;
                      }
                      _isLocalChangePending = true;
                      setState(() {
                        _reserveAllocations.removeWhere((item) => (item['id'] as num?)?.toInt() == allocId);
                      });
                      await widget.db.updateWorkerAllocationReserve(allocId, 0, null);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_tr('تم رفع وإلغاء التحفظ بنجاح 🔄✅', 'Réserve levée avec succès 🔄✅', 'Reserve cleared successfully 🔄✅', lang), style: const TextStyle(fontFamily: 'Cairo')),
                            backgroundColor: Colors.green,
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.only(bottom: 50, left: 16, right: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      }
                      await Future.delayed(const Duration(milliseconds: 1500));
                      _isLocalChangePending = false;
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      _tr('إلغاء التحفظ (Réserve Levée) ✅', 'Lever la réserve ✅', 'Clear Reserve ✅', lang),
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
