import 'dart:async';
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
  String _searchType = 'none'; // 'none', 'client', 'worker', 'date'
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
    _refreshTasks(); // ✅ نسحب أحدث البيانات من السحابة عند الدخول للشاشة
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        if (!_isLocalChangePending) {
          _loadTasks(); // ✅ عند التحديث التلقائي، نقرأ من المحلي فقط لتجنب الدوران اللانهائي
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

  // ✅ دالة التحديث الكامل (السحابة + المحلي)
  Future<void> _refreshTasks() async {
    setState(() => _isLoading = true);
    String restoreError = '';
    try {
      final settings = Provider.of<AppSettingsProvider>(context, listen: false);
      if (!settings.isManager) {
        try {
          final svc = CloudSyncService();
          await svc.init(); // ✅ ضروري لتهيئة workshopId قبل الاستعادة
          await svc.restoreFromCloud();
          // ✅ ربط الإسنادات بـ UID الصحيح للعامل بعد الاستعادة
          await widget.db.relinkCurrentWorkerAllocations();
        } catch (e) {
          debugPrint('Worker cloud restore failed: $e');
          restoreError = '❌ خطأ مزامنة السحابة: $e\n';
          // حتى لو فشلت السحابة، نحاول ربط الإسنادات بالبيانات المحلية
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
      await _loadTasks();
      if (restoreError.isNotEmpty) {
        setState(() {
          _debugInfo = restoreError + _debugInfo;
        });
      }
    }
  }

  // ✅ دالة القراءة المحلية فقط لتفادي التكرار اللانهائي
  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final settings = Provider.of<AppSettingsProvider>(context, listen: false);
        final List<Map<String, dynamic>> rawTasks;
        if (settings.isManager) {
          rawTasks = await widget.db.readAbsoluteAllWorkerAllocations();
        } else {
          rawTasks = await widget.db.readAllWorkerAllocations(user.uid, user.email ?? '');

          // 🔍 تشخيص: اعرض معلومات مفيدة
          try {
            final db = await widget.db.db;
            if (db != null) {
              final allAllocs = await db.rawQuery('SELECT worker_uid, COUNT(*) as cnt FROM WorkerAllocations GROUP BY worker_uid');
              final allEmps = await db.rawQuery('SELECT uid, email, name FROM Employees');
              final info = StringBuffer();
              info.writeln('🔑 UID الحالي: ${user.uid}');
              info.writeln('📧 البريد: ${user.email ?? "—"}');
              info.writeln('👤 الاسم: ${user.displayName ?? "—"}');
              info.writeln('🏢 كود الورشة: ${CloudSyncService().workshopId}');
              info.writeln('☁️ حالة الاسترجاع: ${CloudSyncService().lastRestoreSummary}');
              info.writeln('📋 الإسنادات في القاعدة (${allAllocs.length}):');
              for (final a in allAllocs) {
                final uid = a['worker_uid']?.toString() ?? '';
                final match = uid == user.uid ? ' ✅ مطابق' : '';
                info.writeln('  uid=$uid (${a['cnt']} مهمة)$match');
              }
              info.writeln('👷 العمال في القاعدة (${allEmps.length}):');
              for (final e in allEmps) {
                info.writeln('  uid=${e['uid']} email=${e['email']} name=${e['name']}');
              }
              info.writeln('📊 مهام محمّلة: ${rawTasks.length}');
              setState(() { _debugInfo = info.toString(); });
              debugPrint(_debugInfo);
            }
          } catch (e) {
            debugPrint('Debug info error: $e');
          }
        }
        final tasks = rawTasks.map((t) => Map<String, dynamic>.from(t)).toList();
        setState(() {
          _allTasks = tasks;
          _applyFilters();
        });
      }
    } catch (e) {
      debugPrint('Error loading worker tasks: $e');
    } finally {
      setState(() => _isLoading = false);
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

    // Second, filter by search query if searchType is active
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase().trim();
      if (_searchType == 'client') {
        tasks = tasks.where((t) {
          final cName = '${t['firstname'] ?? ''} ${t['lastname'] ?? ''}'.toLowerCase();
          return cName.contains(query);
        }).toList();
      } else if (_searchType == 'worker') {
        tasks = tasks.where((t) {
          final wName = (t['worker_name'] ?? '').toString().toLowerCase();
          return wName.contains(query);
        }).toList();
      } else if (_searchType == 'date') {
        tasks = tasks.where((t) {
          final dateStr = _formatDateTime(t['assigned_at']).toLowerCase();
          return dateStr.contains(query);
        }).toList();
      }
    }

    _visibleTasks = tasks;
  }

  Future<void> _toggleManufactured(int allocationId, int currentMfg) async {
    _isLocalChangePending = true;
    final newVal = currentMfg == 1 ? 0 : 1;
    await widget.db.updateWorkerAllocationManufacturing(allocationId, newVal);
    
    // إذا تم إلغاء الصنع، يتم إلغاء تركيب الزجاج تلقائياً
    if (newVal == 0) {
      await widget.db.updateWorkerAllocationGlass(allocationId, 0);
    }

    // Update local state lists in place
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newVal == 1 ? 'تم تسجيل صنع النافذة بنجاح 🛠️' : 'تم إلغاء حالة الصنع',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: newVal == 1 ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 1),
        ),
      );
    }

    await Future.delayed(const Duration(milliseconds: 350));
    _isLocalChangePending = false;
  }

  Future<void> _toggleGlassInstalled(int allocationId, int currentGlass) async {
    _isLocalChangePending = true;
    final newVal = currentGlass == 1 ? 0 : 1;
    await widget.db.updateWorkerAllocationGlass(allocationId, newVal);
    
    // Update local state lists in place
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newVal == 1 ? 'تم تسجيل تركيب الزجاج بنجاح 🪟' : 'تم إلغاء حالة تركيب الزجاج',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: newVal == 1 ? Colors.teal : Colors.orange,
          duration: const Duration(seconds: 1),
        ),
      );
    }

    await Future.delayed(const Duration(milliseconds: 350));
    _isLocalChangePending = false;
  }

  Future<void> _transferToDistribution(int allocationId) async {
    _isLocalChangePending = true;
    await widget.db.updateWorkerAllocationTransfer(allocationId, 1);

    setState(() {
      _allTasks.removeWhere((t) => (t['id'] as num?)?.toInt() == allocationId);
      _visibleTasks.removeWhere((t) => (t['id'] as num?)?.toInt() == allocationId);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم تحويل النافذة إلى التوزيع والأرشيف بنجاح 🚚',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.indigo,
          duration: Duration(seconds: 2),
        ),
      );
    }

    await Future.delayed(const Duration(milliseconds: 350));
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

          // ── فلترة متقدمة (اسم العامل / اسم الزبون / التاريخ) ─────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: Row(
              children: [
                // اختيار نوع الفلترة
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _searchType,
                      dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'none',
                          child: Text(lang == AppLanguage.arabic ? 'بدون بحث' : 'Pas de recherche'),
                        ),
                        DropdownMenuItem(
                          value: 'client',
                          child: Text(lang == AppLanguage.arabic ? 'اسم الزبون' : 'Nom Client'),
                        ),
                        if (settings.isManager) // اسم العامل يظهر للمدير فقط
                          DropdownMenuItem(
                            value: 'worker',
                            child: Text(lang == AppLanguage.arabic ? 'اسم العامل' : 'Nom Ouvrier'),
                          ),
                        DropdownMenuItem(
                          value: 'date',
                          child: Text(lang == AppLanguage.arabic ? 'التاريخ' : 'Date'),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _searchType = val ?? 'none';
                          _searchController.clear();
                          _searchQuery = '';
                          _applyFilters();
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // حقل الإدخال
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    enabled: _searchType != 'none',
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _applyFilters();
                      });
                    },
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                    decoration: InputDecoration(
                      hintText: _searchType == 'none'
                          ? (lang == AppLanguage.arabic ? 'اختر نوع الفلترة أولاً' : 'Sélectionnez un type')
                          : _searchType == 'client'
                              ? (lang == AppLanguage.arabic ? 'أدخل اسم الزبون...' : 'Nom client...')
                              : _searchType == 'worker'
                                  ? (lang == AppLanguage.arabic ? 'أدخل اسم العامل...' : 'Nom ouvrier...')
                                  : (lang == AppLanguage.arabic ? 'أدخل التاريخ (يوم/شهر/سنة)...' : 'Date (jj/mm/aaaa)...'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: _searchType == 'none'
                          ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC))
                          : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: _searchType == 'none'
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_searchType == 'date')
                                  IconButton(
                                    icon: const Icon(Icons.calendar_today, size: 18),
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2030),
                                        locale: const Locale('ar'),
                                      );
                                      if (picked != null) {
                                        final formatted = '${picked.day}/${picked.month}/${picked.year}';
                                        setState(() {
                                          _searchController.text = formatted;
                                          _searchQuery = formatted;
                                          _applyFilters();
                                        });
                                      }
                                    },
                                  ),
                                if (_searchController.text.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      setState(() {
                                        _searchController.clear();
                                        _searchQuery = '';
                                        _applyFilters();
                                      });
                                    },
                                  ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
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
    final largeur = (t['largeur'] as num?)?.toInt() ?? 0;
    final hauteur = (t['hauteur'] as num?)?.toInt() ?? 0;
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
            Text(
              '${Localization.translate(windowType, lang)} ($largeur × $hauteur مم)',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),

            // المواصفات (اللون، الزجاج، الملحقات)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
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

            // ── أزرار العمليات (تم الصنع - تم تركيب الزجاج) ──────────────────────────
            Row(
              children: [
                // 1️⃣ زر "تم الصنع" (تصنيع النافذة) — حصري للعامل فقط
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: settings.isManager
                        ? null // 🚫 المدير لا يمكنه الضغط على الزر (عرض الحالة فقط)
                        : () {
                            final allocId = (t['id'] as num?)?.toInt() ?? 0;
                            if (allocId > 0) {
                              _toggleManufactured(
                                allocId,
                                (t['is_manufactured'] as num?)?.toInt() ?? 0,
                              );
                            }
                          },
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
                      disabledBackgroundColor: isManufactured ? Colors.green.shade700 : Colors.grey.shade400,
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 2️⃣ زر "تم تركيب الزجاج" (تركيب الزجاج) — حصري للعامل فقط
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: settings.isManager
                        ? null // 🚫 المدير لا يمكنه الضغط على الزر (عرض الحالة فقط)
                        : () {
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
                          },
                    icon: Icon(
                      isGlassInstalled ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      size: 20,
                      color: !isManufactured && !settings.isManager ? Colors.grey : null,
                    ),
                    label: Text(
                      isGlassInstalled
                          ? (lang == AppLanguage.arabic ? 'تم تركيب الزجاج ✅' : 'Vitré ✅')
                          : (lang == AppLanguage.arabic ? 'تم تركيب الزجاج' : 'Poser Vitrage'),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: !isManufactured && !settings.isManager ? Colors.grey : null,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isGlassInstalled
                          ? Colors.teal.shade600
                          : (!isManufactured && !settings.isManager
                              ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
                      foregroundColor: isGlassInstalled ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      disabledBackgroundColor: isGlassInstalled ? Colors.teal.shade700 : Colors.grey.shade400,
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),

            if (!settings.isManager) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (!isManufactured || !isGlassInstalled) {
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
                      return;
                    }
                    final allocId = (t['id'] as num?)?.toInt() ?? 0;
                    if (allocId > 0) {
                      _transferToDistribution(allocId);
                    }
                  },
                  icon: const Icon(Icons.local_shipping_rounded, size: 18),
                  label: Text(
                    lang == AppLanguage.arabic ? 'تحويل للتوزيع والأرشيف 🚚' : 'Transférer pour Distribution 🚚',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (isManufactured && isGlassInstalled)
                        ? Colors.indigo.shade600
                        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                    foregroundColor: (isManufactured && isGlassInstalled)
                        ? Colors.white
                        : Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
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
