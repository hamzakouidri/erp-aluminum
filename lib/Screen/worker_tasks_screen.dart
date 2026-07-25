import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../Commande/add_commande.dart';
import '../services/cloud_sync_service.dart';
import '../widgets/lazy_window_image.dart';
import 'worker_archive_screen.dart';

class WorkerTasksScreen extends StatefulWidget {
  final SqlDatabase db;
  const WorkerTasksScreen({super.key, required this.db});

  @override
  State<WorkerTasksScreen> createState() => _WorkerTasksScreenState();
}

class _WorkerTasksScreenState extends State<WorkerTasksScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _allTasks = [];
  List<Map<String, dynamic>> _visibleTasks = [];
  String _selectedFilter = 'all'; // 'all', 'pending', 'manufactured', 'glass'
  StreamSubscription? _syncSub;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _debugInfo = ''; // 🔍 تشخيص مؤقت
  bool _isLocalChangePending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.isManager && !settings.canViewMyTasks()) {
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
    _loadTasks(); // ⚡ 1. القراءة المحلية السريعة فوراً (تنهي التحميل بأقل من 50 مالي ثانية)
    _refreshTasks(silent: true); // ⚡ 2. المزامنة والاستعادة السحابية في الخلفية دون حظر الواجهة
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        if (!_isLocalChangePending) {
          _loadTasks(silent: true); // ✅ تحديث صامت بدون إخفاء شاشة المهام
        }
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ✅ دالة التحديث الكامل (السحابة + المحلي) بالتحديث الصامت خلف الكواليس
  Future<void> _refreshTasks({bool silent = true}) async {
    String restoreError = '';
    try {
      final settings = Provider.of<AppSettingsProvider>(context, listen: false);
      if (!settings.isManager) {
        try {
          final svc = CloudSyncService();
          await svc.init(); // ✅ تهيئة workshopId
          await svc.restoreFromCloud();
          await widget.db.relinkCurrentWorkerAllocations();
        } catch (e) {
          debugPrint('Worker cloud restore failed: $e');
          restoreError = '❌ خطأ مزامنة السحابة: $e\n';
          await widget.db.relinkCurrentWorkerAllocations();
        }
      } else {
        try {
          await widget.db.syncWorkerAllocationsStatusFromCloud();
        } catch (e) {
          debugPrint('Manager status sync failed: $e');
        }
      }
    } finally {
      if (mounted) {
        await _loadTasks(silent: true);
        if (restoreError.isNotEmpty) {
          setState(() {
            _debugInfo = restoreError + _debugInfo;
          });
        }
      }
    }
  }

  // ✅ دالة القراءة المحلية مع التحديث اللحظي الصامت في الخلفية
  Future<void> _loadTasks({bool silent = false}) async {
    if (_allTasks.isEmpty && !silent) {
      setState(() => _isLoading = true);
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final settings = Provider.of<AppSettingsProvider>(context, listen: false);
        final List<Map<String, dynamic>> rawTasks;
        if (settings.canViewAllWorkerTasks()) {
          rawTasks = await widget.db.readAbsoluteAllWorkerAllocations();
        } else {
          rawTasks = await widget.db.readAllWorkerAllocations(user.uid, user.email ?? '');
        }

        final tasks = rawTasks.map((t) => Map<String, dynamic>.from(t)).toList();
        setState(() {
          _allTasks = tasks;
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading worker tasks: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
    List<Map<String, dynamic>> tasks = _allTasks;

    // First, filter by status
    if (_selectedFilter == 'pending') {
      tasks = tasks.where((t) => t['is_manufactured'] != 1).toList();
    } else if (_selectedFilter == 'manufactured') {
      tasks = tasks.where((t) => t['is_manufactured'] == 1 && t['is_glass_installed'] != 1).toList();
    } else if (_selectedFilter == 'glass') {
      tasks = tasks.where((t) => t['is_glass_installed'] == 1).toList();
    }

    // Second, universal radical search across ALL fields simultaneously
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      tasks = tasks.where((t) {
        final cName = '${t['firstname'] ?? ''} ${t['lastname'] ?? ''}'.toLowerCase();
        final wName = (t['worker_name'] ?? '').toString().toLowerCase();
        final dateStr = _formatDateTime(t['assigned_at']).toLowerCase();
        final orderId = (t['id_commandes'] ?? '').toString().toLowerCase();
        final allocId = (t['id'] ?? '').toString().toLowerCase();
        final windowType = (t['window_type'] ?? '').toString().toLowerCase();
        final color = (t['color'] ?? '').toString().toLowerCase();
        final glass = (t['glass'] ?? '').toString().toLowerCase();
        final pos = (t['unit_position'] ?? '').toString().toLowerCase();

        return cName.contains(query) ||
               wName.contains(query) ||
               dateStr.contains(query) ||
               orderId.contains(query) ||
               allocId.contains(query) ||
               windowType.contains(query) ||
               color.contains(query) ||
               glass.contains(query) ||
               pos.contains(query);
      }).toList();
    }

    _visibleTasks = tasks;
  }

  Future<void> _toggleManufactured(int allocationId, int currentMfg) async {
    _isLocalChangePending = true;
    final newVal = currentMfg == 1 ? 0 : 1;

    // ⚡ 1. التحديث الفوري للواجهة بدون أي تأخير (Zero latency)
    setState(() {
      for (var list in [_allTasks, _visibleTasks]) {
        for (var i = 0; i < list.length; i++) {
          if (list[i]['id'] == allocationId) {
            final mutable = Map<String, dynamic>.from(list[i]);
            mutable['is_manufactured'] = newVal;
            mutable['manufactured_at'] = newVal == 1 ? DateTime.now().toIso8601String() : null;
            if (newVal == 0) {
              mutable['is_glass_installed'] = 0;
              mutable['glass_installed_at'] = null;
            }
            list[i] = mutable;
          }
        }
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newVal == 1 ? 'تم تسجيل صنع النافذة بنجاح 🛠️' : 'تم إلغاء حالة الصنع',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: newVal == 1 ? Colors.green : Colors.orange,
          duration: const Duration(milliseconds: 800),
        ),
      );
    }

    // ⚡ 2. حفظ البيانات في السحابة والقاعدة المحلية في الخلفية
    try {
      await widget.db.updateWorkerAllocationManufacturing(allocationId, newVal);
      if (newVal == 0) {
        await widget.db.updateWorkerAllocationGlass(allocationId, 0);
      }
    } catch (e) {
      debugPrint('Error toggling manufactured status: $e');
    }

    // الحفاظ على الحماية لمدة ثانيتين لمنع تضارب أحداث البث السحابية
    await Future.delayed(const Duration(seconds: 2));
    _isLocalChangePending = false;
  }

  Future<void> _toggleGlassInstalled(int allocationId, int currentGlass) async {
    _isLocalChangePending = true;
    final newVal = currentGlass == 1 ? 0 : 1;

    // ⚡ 1. التحديث الفوري للواجهة
    setState(() {
      for (var list in [_allTasks, _visibleTasks]) {
        for (var i = 0; i < list.length; i++) {
          if (list[i]['id'] == allocationId) {
            final mutable = Map<String, dynamic>.from(list[i]);
            mutable['is_glass_installed'] = newVal;
            mutable['glass_installed_at'] = newVal == 1 ? DateTime.now().toIso8601String() : null;
            list[i] = mutable;
          }
        }
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newVal == 1 ? 'تم تسجيل تركيب الزجاج بنجاح 🪟' : 'تم إلغاء حالة تركيب الزجاج',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: newVal == 1 ? Colors.teal : Colors.orange,
          duration: const Duration(milliseconds: 800),
        ),
      );
    }

    // ⚡ 2. تحديث في الخلفية
    try {
      await widget.db.updateWorkerAllocationGlass(allocationId, newVal);
    } catch (e) {
      debugPrint('Error toggling glass status: $e');
    }

    await Future.delayed(const Duration(seconds: 2));
    _isLocalChangePending = false;
  }

  Future<void> _transferToDistribution(int allocationId) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;

    // ⚡ 1. إظهار مؤشر تقدم فوري
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
                  lang == AppLanguage.arabic
                      ? 'جاري تحويل النافذة للتوزيع والأرشيف…'
                      : 'Transfert vers la distribution…',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    _isLocalChangePending = true;

    // ⚡ 2. تحديث الحسابات والدبابيس والقواعد السحابية في الخلفية
    try {
      await widget.db.updateWorkerAllocationTransfer(allocationId, 1);
    } catch (e) {
      debugPrint('Error transferring to distribution: $e');
    }

    // ⚡ 3. إزالة النافذة فوراً من قائمة الشاشة
    setState(() {
      _allTasks.removeWhere((t) => (t['id'] as num?)?.toInt() == allocationId);
      _visibleTasks.removeWhere((t) => (t['id'] as num?)?.toInt() == allocationId);
    });

    if (mounted) Navigator.of(context, rootNavigator: true).pop(); // إغلاق مؤشر التقدم

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lang == AppLanguage.arabic
                ? 'تم تحويل النافذة إلى التوزيع والأرشيف بنجاح 🚚'
                : 'Transféré vers la distribution avec succès 🚚',
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.indigo,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    await Future.delayed(const Duration(seconds: 2));
    _isLocalChangePending = false;
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _confirmResetTasksData(BuildContext context, AppLanguage lang) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          lang == AppLanguage.arabic ? 'تأكيد مسح وتصفير المهام' : 'Reset Tasks Confirmation',
          style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
        ),
        content: Text(
          lang == AppLanguage.arabic 
            ? 'هل أنت تأكد من مسح وتصفير جميع الإسنادات والمهام المصنعة بالتطوير؟'
            : 'Voulez-vous réinitialiser toutes les tâches et affectations ?',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(lang == AppLanguage.arabic ? 'إلغاء' : 'Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              lang == AppLanguage.arabic ? 'مسح كلي 🧹' : 'Effacer tout 🧹',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (mounted) {
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
                      lang == AppLanguage.arabic
                          ? 'جاري تصفير ومسح جميع المهام…'
                          : 'Réinitialisation des tâches…',
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      await widget.db.clearAllWorkerAllocationsFromCloudAndLocal();
      await _loadTasks();

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lang == AppLanguage.arabic ? 'تم مسح وتصفير كافة الإسنادات والمهام بنجاح محلياً ومنا السحابة 🧹' : 'Toutes les tâches ont été réinitialisées 🧹'),
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
        title: Text(
          lang == AppLanguage.arabic ? 'مهامي وتصنيعاتي' : 'Mes Tâches de Fabrication',
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            tooltip: lang == AppLanguage.arabic ? 'تصفير كافة المهام والإسنادات (للتطوير)' : 'Réinitialiser toutes les tâches (Dev)',
            onPressed: () => _confirmResetTasksData(context, lang),
          ),
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: lang == AppLanguage.arabic ? 'الأرشيف' : 'Archives',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => WorkerArchiveScreen(db: widget.db),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshTasks,
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
                  lang == AppLanguage.arabic ? '🧪 تصفير المهام (للتطوير)' : '🧪 Réinitialiser (Dev)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red.shade900,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  onPressed: () => _confirmResetTasksData(context, lang),
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: Text(
                    lang == AppLanguage.arabic ? 'تصفير كافة المهام 🧹' : 'Effacer Tout 🧹',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          // ── فلترة المهام ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterButton('all', lang == AppLanguage.arabic ? 'الكل' : 'Tout', Icons.list),
                  const SizedBox(width: 8),
                  _filterButton('pending', lang == AppLanguage.arabic ? 'قيد التصنيع' : 'En fabrication', Icons.hourglass_empty_rounded),
                  const SizedBox(width: 8),
                  _filterButton('manufactured', lang == AppLanguage.arabic ? 'تم الصنع (بدون زجاج)' : 'Prêt (Sans vitrage)', Icons.build_circle_outlined),
                  const SizedBox(width: 8),
                  _filterButton('glass', lang == AppLanguage.arabic ? 'منتهي بالزجاج' : 'Terminé avec vitrage', Icons.check_circle_outline_rounded),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // ── بحث شامل وباشر (اسم الزبون / العامل / التاريخ / رقم الطلبية / النافذة) ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                  _applyFilters();
                });
              },
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
              decoration: InputDecoration(
                hintText: lang == AppLanguage.arabic
                    ? 'بحث شامل (اسم الزبون، العامل، رقم الطلبية، النافذة، اللون...)'
                    : 'Recherche globale (Client, Ouvrier, Commande, Fenêtre...)',
                hintStyle: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF3B82F6)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                            _applyFilters();
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const Divider(height: 1),

          // ── قائمة المهام ──────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _visibleTasks.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                lang == AppLanguage.arabic ? 'لا توجد مهام مطابقة للفلتر المختار' : 'Aucune tâche correspondante',
                                style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey, fontSize: 14),
                              ),
                              // 🔍 معلومات التشخيص (تُزال لاحقاً)
                              if (_debugInfo.isNotEmpty && !settings.isManager) ...[
                                const SizedBox(height: 16),
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    border: Border.all(color: Colors.orange),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('🔍 معلومات تشخيص:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      const SizedBox(height: 4),
                                      Text(_debugInfo, style: const TextStyle(fontSize: 10, fontFamily: 'Courier')),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )

                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _visibleTasks.length,
                        itemBuilder: (context, idx) {
                          final t = _visibleTasks[idx];
                          return _buildTaskCard(t, lang, isDark, settings);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterButton(String filter, String label, IconData icon) {
    final isSelected = _selectedFilter == filter;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color fg;
    if (isSelected) {
      bg = const Color(0xFF3B82F6);
      fg = Colors.white;
    } else {
      bg = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
      fg = isDark ? Colors.white70 : Colors.black87;
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = filter;
          _applyFilters();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.blue : (isDark ? Colors.grey[800]! : Colors.grey[300]!),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: fg),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> t, AppLanguage lang, bool isDark, AppSettingsProvider settings) {
    final windowType = t['window_type']?.toString() ?? 'Window';
    final qty = (t['quantity'] as num?)?.toInt() ?? (t['detail_quantity'] as num?)?.toInt() ?? 1;
    final price = (t['worker_price'] as num?)?.toDouble() ?? 0.0;
    final total = qty * price;
    final assignedAt = _formatDateTime(t['assigned_at']);
    
    final color = t['color']?.toString() ?? '';
    final glass = t['glass']?.toString() ?? '';
    final clientName = '${t['firstname'] ?? ''} ${t['lastname'] ?? ''}'.trim();

    final isManufactured = t['is_manufactured'] == 1;
    final isGlassInstalled = t['is_glass_installed'] == 1;

    final commandeId = (t['id_commandes'] as num?)?.toInt() ?? 0;

    int finalW = (t['unit_width'] as num?)?.toInt() ?? 0;
    int finalH = (t['unit_height'] as num?)?.toInt() ?? 0;
    if (finalW == 0) finalW = (t['largeur'] as num?)?.toInt() ?? 0;
    if (finalH == 0) finalH = (t['hauteur'] as num?)?.toInt() ?? 0;

    String unitPos = t['unit_position']?.toString() ?? '';
    final unitIndex = t['unit_index'];

    if ((t['unit_width'] == null || t['unit_height'] == null) && t['confirmed_mesures_json'] != null && t['confirmed_mesures_json'].toString().trim().isNotEmpty) {
      try {
        final List parsed = jsonDecode(t['confirmed_mesures_json'].toString());
        final uIdx = (unitIndex as num?)?.toInt() ?? 1;
        final arrayIdx = uIdx - 1;
        if (arrayIdx >= 0 && arrayIdx < parsed.length) {
          final unitMap = parsed[arrayIdx];
          final cw = (unitMap['largeur'] as num?)?.toInt() ?? (unitMap['width'] as num?)?.toInt();
          final ch = (unitMap['hauteur'] as num?)?.toInt() ?? (unitMap['height'] as num?)?.toInt();
          final pos = unitMap['position']?.toString() ?? '';
          if (cw != null && cw > 0 && finalW == 0) finalW = cw;
          if (ch != null && ch > 0 && finalH == 0) finalH = ch;
          if (pos.isNotEmpty && unitPos.isEmpty) unitPos = pos;
        }
      } catch (_) {}
    }

    final isConfirmedMesure = unitIndex != null || unitPos.isNotEmpty || (finalW != (t['largeur'] as num?)?.toInt() || finalH != (t['hauteur'] as num?)?.toInt());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── رأس البطاقة (رقم الطلبية واسم الزبون) ───────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () {
                    if (settings.canViewOrderDetails() && commandeId > 0) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CommandePage(
                            editCommandeId: commandeId,
                            db: widget.db,
                          ),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.assignment_outlined, size: 14, color: Color(0xFF3B82F6)),
                        const SizedBox(width: 4),
                        Text(
                          '${lang == AppLanguage.arabic ? "طلبية" : "Order"} #${t['id_commandes']}',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF3B82F6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  assignedAt,
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // اسم العامل (يظهر للمدير فقط)
            if (settings.isManager) ...[
              Row(
                children: [
                  const Icon(Icons.engineering_outlined, size: 16, color: Colors.blueAccent),
                  const SizedBox(width: 6),
                  Text(
                    '${lang == AppLanguage.arabic ? "العامل المعيّن" : "Ouvrier affecté"}: ${t['worker_name'] ?? (lang == AppLanguage.arabic ? "غير محدد" : "Non affecté")}',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // اسم الزبون
            if (clientName.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 16, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  Text(
                    '${lang == AppLanguage.arabic ? "الزبون" : "Client"}: $clientName',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Divider(height: 16),
            ],

            // ── تفاصيل العنصر ─────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${Localization.translate(windowType, lang)} ($finalW × $finalH مم)',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (unitIndex != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade700,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${lang == AppLanguage.arabic ? "قطعة" : "Pièce"} #$unitIndex ${unitPos.isNotEmpty ? "($unitPos)" : ""}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // المواصفات (اللون، الزجاج، الملحقات)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (isConfirmedMesure)
                  _specBadge('📐 ${lang == AppLanguage.arabic ? "قياس مؤكد" : "Mesure Validée"}: $finalW×$finalH', Icons.straighten_rounded, Colors.teal),
                if (color.isNotEmpty)
                  _specBadge(lang == AppLanguage.arabic ? 'اللون: $color' : 'Couleur: $color', Icons.color_lens_outlined, Colors.purple),
                if (glass.isNotEmpty)
                  _specBadge(lang == AppLanguage.arabic ? 'الزجاج: $glass' : 'Vitrage: $glass', Icons.square_outlined, Colors.teal),
                _specBadge('${lang == AppLanguage.arabic ? "الكمية" : "Qté"}: $qty قطع', Icons.layers_outlined, Colors.blueGrey),
              ],
            ),

            if (t['accessories']?.toString().isNotEmpty == true || t['description']?.toString().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                '${lang == AppLanguage.arabic ? "ملاحظات:" : "Notes:"} ${[t['accessories'], t['description']].where((s) => s != null && s.toString().isNotEmpty).join(" | ")}',
                style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600], fontStyle: FontStyle.italic),
              ),
            ],

            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
                  padding: const EdgeInsets.all(8),
                  child: LazyWindowImage(
                    db: widget.db,
                    detailId: (t['commande_detail_id'] as num?)?.toInt() ?? (t['id'] as num?)?.toInt() ?? 0,
                    initialImagePath: t['drawing_image_path']?.toString() ?? '',
                    partitionsJson: t['partitions_json'],
                    drawingImageBase64: t['drawing_image_base64']?.toString(),
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            const Divider(height: 20),

            // ── الأجر المالي المقابل ──────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  lang == AppLanguage.arabic ? 'أجر التصنيع المترتب:' : 'Salaire dû :',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                ),
                Text(
                  '$total د.ج',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.green,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── فحص صلاحية التحكم بهذه المهمة ────────────────────────────
            Builder(
              builder: (ctx) {
                final currentUser = FirebaseAuth.instance.currentUser;
                final currentUid = (currentUser?.uid ?? '').trim().toLowerCase();
                final currentEmail = (currentUser?.email ?? '').trim().toLowerCase();

                final taskWorkerUid = (t['worker_uid'] ?? '').toString().trim().toLowerCase();
                final taskWorkerEmail = (t['worker_email'] ?? '').toString().trim().toLowerCase();

                bool isMyTask = false;
                if (settings.isManager) {
                  isMyTask = true; // ✅ المدير ونائب المدير لديهما كامل الصلاحية للتحكم وتفعيل كل المهام
                } else if (currentUid.isNotEmpty && taskWorkerUid == currentUid) {
                  isMyTask = true;
                } else if (currentEmail.isNotEmpty && (taskWorkerUid == currentEmail || taskWorkerEmail == currentEmail)) {
                  isMyTask = true;
                } else if (!settings.canViewAllWorkerTasks()) {
                  isMyTask = true;
                }

                return Column(
                  children: [
                    // ── أزرار العمليات (تم الصنع - تم تركيب الزجاج) ──────────────────────────
                    Row(
                      children: [
                        // 1️⃣ زر "تم الصنع" (تصنيع النافذة)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isMyTask
                                ? () {
                                    final allocId = (t['id'] as num?)?.toInt() ?? 0;
                                    if (allocId > 0) {
                                      _toggleManufactured(
                                        allocId,
                                        (t['is_manufactured'] as num?)?.toInt() ?? 0,
                                      );
                                    }
                                  }
                                : null, // 🚫 معطّل إذا كانت المهمة مسندة لعامل آخر
                            icon: Icon(
                              isManufactured ? Icons.check_circle_rounded : Icons.build_circle_outlined,
                              size: 18,
                            ),
                            label: Text(
                              isManufactured
                                  ? (lang == AppLanguage.arabic ? 'تم الصنع ✅' : 'Fabriqué ✅')
                                  : (lang == AppLanguage.arabic ? 'تم الصنع' : 'Fabriquer'),
                              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isManufactured
                                  ? Colors.green.shade600
                                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                              foregroundColor: isManufactured ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                              disabledBackgroundColor: isManufactured ? Colors.green.shade700 : (isDark ? const Color(0xFF1E293B) : Colors.grey.shade300),
                              disabledForegroundColor: isManufactured ? Colors.white70 : Colors.grey.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // 2️⃣ زر "تم تركيب الزجاج" (تركيب الزجاج)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isMyTask
                                ? () {
                                    if (!isManufactured) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            lang == AppLanguage.arabic
                                                ? '⚠️ لا يمكن تركيب الزجاج! يجب إتمام "تم الصنع" أولاً.'
                                                : '⚠️ Pose du vitrage impossible ! Marquez "Fabriqué" d\'abord.',
                                            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                          ),
                                          backgroundColor: Colors.amber.shade900,
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                      return;
                                    }
                                    final allocId = (t['id'] as num?)?.toInt() ?? 0;
                                    if (allocId > 0) {
                                      _toggleGlassInstalled(
                                        allocId,
                                        (t['is_glass_installed'] as num?)?.toInt() ?? 0,
                                      );
                                    }
                                  }
                                : null, // 🚫 معطّل إذا كانت المهمة مسندة لعامل آخر
                            icon: Icon(
                              isGlassInstalled ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              size: 20,
                              color: (!isManufactured && isMyTask) ? Colors.grey : null,
                            ),
                            label: Text(
                              isGlassInstalled
                                  ? (lang == AppLanguage.arabic ? 'تم تركيب الزجاج ✅' : 'Vitré ✅')
                                  : (lang == AppLanguage.arabic ? 'تم تركيب الزجاج' : 'Poser Vitrage'),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: (!isManufactured && isMyTask) ? Colors.grey : null,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isGlassInstalled
                                  ? Colors.teal.shade600
                                  : (!isManufactured
                                      ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))
                                      : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
                              foregroundColor: isGlassInstalled ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                              disabledBackgroundColor: isGlassInstalled ? Colors.teal.shade700 : (isDark ? const Color(0xFF1E293B) : Colors.grey.shade300),
                              disabledForegroundColor: isGlassInstalled ? Colors.white70 : Colors.grey.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // 3️⃣ زر "تحويل للتوزيع والأرشيف"
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (isMyTask && isManufactured && isGlassInstalled)
                            ? () {
                                final allocId = (t['id'] as num?)?.toInt() ?? 0;
                                if (allocId > 0) {
                                  _transferToDistribution(allocId);
                                }
                              }
                            : (isMyTask && (!isManufactured || !isGlassInstalled))
                                ? () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          lang == AppLanguage.arabic
                                              ? '⚠️ يجب إتمام "تم الصنع" و "تركيب الزجاج" أولاً قبل التحويل للتوزيع!'
                                              : '⚠️ Terminez la fabrication et la pose du vitrage d\'abord !',
                                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                        ),
                                        backgroundColor: Colors.amber.shade900,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                : null, // 🚫 معطّل إذا كانت المهمة مسندة لعامل آخر
                        icon: const Icon(Icons.local_shipping_rounded, size: 18),
                        label: Text(
                          lang == AppLanguage.arabic ? 'تحويل للتوزيع والأرشيف 🚚' : 'Transférer pour Distribution 🚚',
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (isManufactured && isGlassInstalled && isMyTask)
                              ? Colors.indigo.shade600
                              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                          foregroundColor: (isManufactured && isGlassInstalled && isMyTask)
                              ? Colors.white
                              : Colors.grey,
                          disabledBackgroundColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade600,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),

                    // 🔒 تنبيه قفل العرض فقط إذا كانت مسندة لعامل آخر
                    if (!isMyTask) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade900.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade700, width: 0.8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline_rounded, size: 14, color: Colors.amber.shade800),
                            const SizedBox(width: 6),
                            Text(
                              lang == AppLanguage.arabic
                                  ? 'مسندة لعامل آخر (للعرض فقط — لا يمكن تعديلها)'
                                  : 'Affectée à un autre ouvrier (Lecture seule)',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _specBadge(String label, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'Cairo',
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
