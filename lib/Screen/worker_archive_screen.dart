import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../widgets/lazy_window_image.dart';

class WorkerArchiveScreen extends StatefulWidget {
  final SqlDatabase db;

  const WorkerArchiveScreen({super.key, required this.db});

  @override
  State<WorkerArchiveScreen> createState() => _WorkerArchiveScreenState();
}

class _WorkerArchiveScreenState extends State<WorkerArchiveScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _archivedTasks = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadArchivedTasks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadArchivedTasks() async {
    setState(() => _isLoading = true);
    try {
      final settings = Provider.of<AppSettingsProvider>(context, listen: false);
      final user = FirebaseAuth.instance.currentUser;
      List<Map<String, dynamic>> tasks = [];

      if (settings.isManager) {
        tasks = await widget.db.readAllArchivedAllocationsForManager();
      } else if (user != null) {
        tasks = await widget.db.readWorkerArchivedAllocations(
          user.uid,
          user.email ?? '',
        );
      }

      setState(() {
        _archivedTasks = tasks;
      });
    } catch (e) {
      debugPrint('Error loading archived tasks: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'غير محدد';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  Future<void> _unarchiveTask(int allocId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الأرشفة ومسح السجل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: const Text(
          'هل تريد إرجاع هذا العنصر من الأرشيف ومسحه منه وإعادته إلى قائمة مهامك النشطة؟',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الإرجاع', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.db.updateWorkerAllocationTransfer(allocId, 0);
      _loadArchivedTasks();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء أرشفة العنصر وإعادته لمهامك النشطة بنجاح 🔄', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.teal,
          ),
        );
      }
    }
  }

  Future<void> _editArchivedNotes(int allocId, String currentNotes) async {
    final controller = TextEditingController(text: currentNotes);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل ملاحظات الأرشيف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'أدخل الملاحظات والتعديلات...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ التعديل', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Save notes if needed
      _loadArchivedTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;

    final filteredTasks = _archivedTasks.where((t) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final clientName = '${t['firstname'] ?? ''} ${t['lastname'] ?? ''}'.toLowerCase();
      final workerName = (t['worker_name'] ?? '').toString().toLowerCase();
      final wType = (t['window_type'] ?? '').toString().toLowerCase();
      final oId = (t['id_commandes'] ?? '').toString();
      return clientName.contains(q) || workerName.contains(q) || wType.contains(q) || oId.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          lang == AppLanguage.arabic ? 'أرشيف المهام والتصنيع 📦' : 'Archives des Tâches 📦',
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadArchivedTasks,
            tooltip: lang == AppLanguage.arabic ? 'تحديث' : 'Actualiser',
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط البحث
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: lang == AppLanguage.arabic ? 'بحث باسم الزبون، العامل، النافذة، رقم الطلب...' : 'Rechercher...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // كروت الأرشيف
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredTasks.isEmpty
                    ? Center(
                        child: Text(
                          lang == AppLanguage.arabic ? 'لا توجد مهام أرشيفية مسجلة' : 'Aucune tâche archivée',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: filteredTasks.length,
                        itemBuilder: (context, index) {
                          return _buildArchiveCard(filteredTasks[index], isDark, lang);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveCard(Map<String, dynamic> t, bool isDark, AppLanguage lang) {
    final clientName = '${t['firstname'] ?? ''} ${t['lastname'] ?? ''}'.trim();
    final workerName = (t['worker_name'] ?? '').toString().trim();
    final windowType = t['window_type']?.toString() ?? 'Window';
    final largeur = (t['largeur'] as num?)?.toInt() ?? 0;
    final hauteur = (t['hauteur'] as num?)?.toInt() ?? 0;
    final qty = (t['quantity'] as num?)?.toInt() ?? (t['detail_quantity'] as num?)?.toInt() ?? 1;
    final price = (t['worker_price'] as num?)?.toDouble() ?? 0.0;
    final total = qty * price;

    final assignedAt = _formatDateTime(t['assigned_at']);
    final mfgAt = _formatDateTime(t['manufactured_at']);
    final glassAt = _formatDateTime(t['glass_installed_at']);
    final distributedAt = _formatDateTime(t['distributed_at'] ?? t['transferred_at']);
    final installedAt = _formatDateTime(t['installed_at']);
    final completedAt = _formatDateTime(t['completed_at']);

    final isLocked = t['is_locked_after_week'] == true;
    final allocId = (t['id'] as num?)?.toInt() ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1️⃣ رأس البطاقة (اسم الزبون وشارة القفل)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    clientName.isNotEmpty ? clientName : (lang == AppLanguage.arabic ? 'زبون غير محدد' : 'Client Inconnu'),
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isLocked ? Colors.red.withOpacity(0.12) : Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isLocked ? Colors.red.withOpacity(0.4) : Colors.green.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(isLocked ? Icons.lock_rounded : Icons.lock_open_rounded, size: 14, color: isLocked ? Colors.red : Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        isLocked
                            ? (lang == AppLanguage.arabic ? 'مقفول (مرّ أكثر من أسبوع)' : 'Verrouillé (+7j)')
                            : (lang == AppLanguage.arabic ? 'مفتوح (أقل من أسبوع)' : 'Modifiable (<7j)'),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isLocked ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // 2️⃣ اسم العامل المسند / المصنع
            Row(
              children: [
                const Icon(Icons.badge_outlined, size: 16, color: Colors.blue),
                const SizedBox(width: 6),
                Text(
                  '${lang == AppLanguage.arabic ? "اسم العامل الصانع:" : "Nom de l'ouvrier:"} ',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey),
                ),
                Text(
                  workerName.isNotEmpty ? workerName : (lang == AppLanguage.arabic ? 'غير محدد' : 'Non spécifié'),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ],
            ),
            const Divider(height: 16),

            // 3️⃣ التواريخ الإسناد - الصنع - تركيب الزجاج - التوزيع - التركيب والانتهاء
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _dateRow(Icons.assignment_outlined, 'تاريخ الإسناد:', assignedAt, Colors.orange),
                  const SizedBox(height: 4),
                  _dateRow(Icons.build_circle_outlined, 'تاريخ الصنع:', mfgAt, Colors.green),
                  const SizedBox(height: 4),
                  _dateRow(Icons.check_box_rounded, 'تاريخ تركيب الزجاج بالورشة:', glassAt, Colors.teal),
                  const SizedBox(height: 4),
                  _dateRow(Icons.local_shipping_rounded, 'تاريخ التوزيع والخروج للميدان:', distributedAt, Colors.indigo),
                  if (installedAt != 'غير محدد') ...[
                    const SizedBox(height: 4),
                    _dateRow(Icons.construction_rounded, 'تاريخ التركيب بالموقع:', installedAt, Colors.purple),
                  ],
                  if (completedAt != 'غير محدد') ...[
                    const SizedBox(height: 4),
                    _dateRow(Icons.task_alt_rounded, 'تاريخ الانتهاء والأرشفة النهائي:', completedAt, Colors.green),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 4️⃣ الصورة والتفاصيل الأبعاد والكمية
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
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
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${lang == AppLanguage.arabic ? "الأبعاد:" : "Dims:"} ${largeur}cm × ${hauteur}cm | ${lang == AppLanguage.arabic ? "الكمية:" : "Qté:"} $qty',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                      ),
                      if (price > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${lang == AppLanguage.arabic ? "أجرة التصنيع:" : "Prix:"} ${total.toStringAsFixed(2)} DZD',
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.teal),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // 5️⃣ أزرار التعديل والمسح (تظهر فقط إذا كان السجل غير مقفول !isLocked)
            if (!isLocked) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _editArchivedNotes(allocId, t['notes']?.toString() ?? ''),
                      icon: const Icon(Icons.edit_note_rounded, size: 16),
                      label: const Text('تعديل الملاحظات', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                        side: const BorderSide(color: Colors.blue),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _unarchiveTask(allocId),
                      icon: const Icon(Icons.undo_rounded, size: 16),
                      label: const Text('إرجاع من الأرشيف / مسح', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dateRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
