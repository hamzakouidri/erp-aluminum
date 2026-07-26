import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';

class WorkerAttendanceScreen extends StatefulWidget {
  final Map<String, dynamic> worker;
  final SqlDatabase db;

  const WorkerAttendanceScreen({
    super.key,
    required this.worker,
    required this.db,
  });

  @override
  State<WorkerAttendanceScreen> createState() => _WorkerAttendanceScreenState();
}

class _WorkerAttendanceScreenState extends State<WorkerAttendanceScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<Map<String, dynamic>> _records = [];
  final _dateFormat = DateFormat('yyyy-MM-dd');
  final _timeFormat = DateFormat('HH:mm');
  DateTime _selectedMonth = DateTime.now();
  late TabController _tabController;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    final uid = widget.worker['uid']?.toString() ?? widget.worker['id']?.toString() ?? '';
    final data = await widget.db.readWorkerAttendance(uid);
    if (mounted) {
      setState(() {
        _records = data;
        _isLoading = false;
      });
    }
  }

  int _getDaysInMonth(DateTime month) {
    final nextMonth = DateTime(month.year, month.month + 1, 1);
    return nextMonth.subtract(const Duration(days: 1)).day;
  }

  Future<void> _toggleDayStatus(int day, AppLanguage lang) async {
    final uid = widget.worker['uid']?.toString() ?? widget.worker['id']?.toString() ?? '';
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime(_selectedMonth.year, _selectedMonth.month, day));
    final existingIndex = _records.indexWhere((r) => r['attendance_date'] == dateStr);
    final existing = existingIndex != -1 ? _records[existingIndex] : null;

    Map<String, dynamic>? updatedRecord;

    if (existing == null || (existing['check_in'] == null && (existing['note'] ?? '').contains('غائب'))) {
      // 🟢 تحويل فوري إلى (حاضر ✅)
      updatedRecord = {
        'worker_uid': uid,
        'attendance_date': dateStr,
        'check_in': '08:00',
        'check_out': '17:00',
        'note': 'حاضر ✅',
      };
    } else if (existing['check_in'] != null || (existing['note'] ?? '').contains('حاضر')) {
      // 🔴 تحويل فوري إلى (غائب ❌)
      updatedRecord = {
        'worker_uid': uid,
        'attendance_date': dateStr,
        'check_in': null,
        'check_out': null,
        'note': 'غائب ❌',
      };
    } else {
      // ⚪ مسح / فارغ
      updatedRecord = null;
    }

    // ⚡ تحديث واجهة المستخدم فوراً وبدون أي ترميش (Optimistic UI Update)
    setState(() {
      if (updatedRecord == null) {
        if (existingIndex != -1) _records.removeAt(existingIndex);
      } else {
        if (existingIndex != -1) {
          _records[existingIndex] = updatedRecord;
        } else {
          _records.add(updatedRecord);
        }
      }
    });

    // 💾 حفظ في قاعدة البيانات في الخلفية
    if (updatedRecord == null) {
      await widget.db.upsertWorkerAttendance(
        workerUid: uid,
        date: dateStr,
        checkIn: null,
        checkOut: null,
        note: null,
      );
    } else {
      await widget.db.upsertWorkerAttendance(
        workerUid: uid,
        date: dateStr,
        checkIn: updatedRecord['check_in'],
        checkOut: updatedRecord['check_out'],
        note: updatedRecord['note'],
      );
    }

    // 🔄 مزامنة صامتة في الكواليس
    _loadData(silent: true);
  }

  Future<void> _checkIn(AppLanguage lang) async {
    final today = _dateFormat.format(DateTime.now());
    final uid = widget.worker['uid']?.toString() ?? widget.worker['id']?.toString() ?? '';
    final existing = _records.where((r) => r['attendance_date'] == today).toList();
    if (existing.isNotEmpty && existing.first['check_in'] != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr('تم تسجيل الدخول اليوم بالفعل — الساعة ${existing.first['check_in']}',
                  'Pointage du matin déjà enregistré — ${existing.first['check_in']}',
                  'Already checked in today at ${existing.first['check_in']}',
                  lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    final now = _timeFormat.format(DateTime.now());
    await widget.db.upsertWorkerAttendance(
      workerUid: uid,
      date: today,
      checkIn: now,
      note: 'حاضر ✅',
    );
    _loadData(silent: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr('✅ تم تسجيل الدخول الساعة $now', '✅ Pointage entrée: $now', '✅ Checked in at $now', lang),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _checkOut(AppLanguage lang) async {
    final today = _dateFormat.format(DateTime.now());
    final existing = _records.where((r) => r['attendance_date'] == today).toList();
    if (existing.isEmpty || existing.first['check_in'] == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr('⚠️ لم يتم تسجيل الدخول بعد اليوم!',
                  '⚠️ Aucun pointage d\'entrée aujourd\'hui!',
                  '⚠️ No check-in recorded today!',
                  lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (existing.first['check_out'] != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr('تم تسجيل الخروج اليوم بالفعل — الساعة ${existing.first['check_out']}',
                  'Pointage de sortie déjà enregistré — ${existing.first['check_out']}',
                  'Already checked out today at ${existing.first['check_out']}',
                  lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    final now = _timeFormat.format(DateTime.now());
    final uid = widget.worker['uid']?.toString() ?? widget.worker['id']?.toString() ?? '';
    await widget.db.upsertWorkerAttendance(
      workerUid: uid,
      date: today,
      checkOut: now,
    );
    _loadData(silent: true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr('✅ تم تسجيل الخروج الساعة $now', '✅ Pointage sortie: $now', '✅ Checked out at $now', lang),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.indigo,
        ),
      );
    }
  }

  Future<void> _manualEntry(AppLanguage lang, {Map<String, dynamic>? existing, String? initialDate}) async {
    final dateCtrl = TextEditingController(
        text: existing != null ? existing['attendance_date'] : (initialDate ?? _dateFormat.format(DateTime.now())));
    final inCtrl = TextEditingController(text: existing?['check_in'] ?? '');
    final outCtrl = TextEditingController(text: existing?['check_out'] ?? '');
    final noteCtrl = TextEditingController(text: existing?['note'] ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _tr('تفاصيل وتعديل حضور اليوم', 'Détails de présence', 'Attendance Details', lang),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: dateCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: _tr('التاريخ', 'Date', 'Date', lang),
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: inCtrl,
                      decoration: InputDecoration(
                        labelText: _tr('وقت الدخول (مثال 08:00)', 'Entrée', 'Check In', lang),
                        border: const OutlineInputBorder(),
                        hintText: '08:00',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: outCtrl,
                      decoration: InputDecoration(
                        labelText: _tr('وقت الخروج (مثال 17:00)', 'Sortie', 'Check Out', lang),
                        border: const OutlineInputBorder(),
                        hintText: '17:00',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: noteCtrl,
                decoration: InputDecoration(
                  labelText: _tr('ملاحظات / سبب الغياب', 'Note / Motif', 'Note / Reason', lang),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_tr('إلغاء', 'Annuler', 'Cancel', lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () async {
              final uid = widget.worker['uid']?.toString() ?? widget.worker['id']?.toString() ?? '';
              await widget.db.upsertWorkerAttendance(
                workerUid: uid,
                date: dateCtrl.text,
                checkIn: inCtrl.text.isNotEmpty ? inCtrl.text : null,
                checkOut: outCtrl.text.isNotEmpty ? outCtrl.text : null,
                note: noteCtrl.text.isNotEmpty ? noteCtrl.text : null,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _loadData(silent: true);
            },
            child: Text(_tr('حفظ', 'Enregistrer', 'Save', lang), style: const TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  String _calcDuration(String? checkIn, String? checkOut) {
    if (checkIn == null || checkOut == null) return '--';
    try {
      final base = DateTime(2000);
      final inParts = checkIn.split(':');
      final outParts = checkOut.split(':');
      final inTime = base.add(Duration(hours: int.parse(inParts[0]), minutes: int.parse(inParts[1])));
      final outTime = base.add(Duration(hours: int.parse(outParts[0]), minutes: int.parse(outParts[1])));
      final diff = outTime.difference(inTime);
      if (diff.isNegative) return '--';
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    } catch (_) {
      return '--';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = settings.isDarkMode;
    final today = _dateFormat.format(DateTime.now());
    final todayRecord = _records.where((r) => r['attendance_date'] == today).firstOrNull;

    final daysInMonth = _getDaysInMonth(_selectedMonth);
    final monthPrefix = DateFormat('yyyy-MM').format(_selectedMonth);
    final monthRecords = _records.where((r) => (r['attendance_date'] ?? '').startsWith(monthPrefix)).toList();

    int presentDays = 0;
    int absentDays = 0;
    for (var r in monthRecords) {
      if (r['check_in'] != null || (r['note'] ?? '').contains('حاضر')) {
        presentDays++;
      } else if ((r['note'] ?? '').contains('غائب')) {
        absentDays++;
      }
    }

    final double baseSalary = (widget.worker['base_salary'] as num?)?.toDouble() ?? 0.0;
    final double dailyRate = baseSalary > 0 ? baseSalary / 26.0 : 0.0;
    final double earnedSalary = dailyRate * presentDays;

    return Directionality(
      textDirection: lang == AppLanguage.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey.shade100,
        appBar: AppBar(
          title: Text(
            '${_tr('جدول حضور وغياب العامل', 'Calendrier de présence', 'Attendance Calendar', lang)}: ${widget.worker['name']}',
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
          ),
          backgroundColor: isDark ? const Color(0xFF1A237E) : Colors.indigo.shade700,
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.amber,
            labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontFamily: 'Cairo'),
            tabs: [
              Tab(text: _tr('🗓️ تقويم الشهر', '🗓️ Calendrier Mensuel', '🗓️ Monthly Grid', lang)),
              Tab(text: _tr('⏱️ السجل والتوقيت', '⏱️ Pointage Horaire', '⏱️ Time Log', lang)),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  // ── TAB 1: تقويم الشهر التفاعلي لتحديد الأيام ───────────────
                  Column(
                    children: [
                      // ── أزرار اختيار الشهر والإحصائيات ──────────────────
                      Container(
                        color: isDark ? const Color(0xFF1A237E) : Colors.indigo.shade700,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                                    });
                                  },
                                ),
                                Text(
                                  DateFormat('MMMM yyyy').format(_selectedMonth),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildMetricChip(
                                  label: _tr('أيام الحضور', 'Présent', 'Present', lang),
                                  value: '$presentDays ${_tr("يوم", "j", "d", lang)}',
                                  color: Colors.green,
                                ),
                                _buildMetricChip(
                                  label: _tr('أيام الغياب', 'Absent', 'Absent', lang),
                                  value: '$absentDays ${_tr("يوم", "j", "d", lang)}',
                                  color: Colors.red.shade400,
                                ),
                                _buildMetricChip(
                                  label: _tr('الراتب المستحق', 'Salaire Dû', 'Earned Wage', lang),
                                  value: '${earnedSalary.toStringAsFixed(0)} د.ج',
                                  color: Colors.amber,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _tr('💡 اضغط على أي يوم للتغيير: (🟢 حاضر 👈 🔴 غائب 👈 ⚪ إعادة تعيين)',
                                  '💡 Appuyez pour changer: (🟢 Présent 👈 🔴 Absent 👈 ⚪ Réinitialiser)',
                                  '💡 Tap day to toggle: (🟢 Present 👈 🔴 Absent 👈 ⚪ Reset)',
                                  lang),
                              style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Cairo'),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                      // ── شبكة أيام الشهر (Interactive Calendar Grid) ──────────
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: daysInMonth,
                          itemBuilder: (ctx, idx) {
                            final dayNum = idx + 1;
                            final dateStr = DateFormat('yyyy-MM-dd')
                                .format(DateTime(_selectedMonth.year, _selectedMonth.month, dayNum));
                            final record = _records.where((r) => r['attendance_date'] == dateStr).firstOrNull;

                            final bool isPresent = record != null &&
                                (record['check_in'] != null || (record['note'] ?? '').contains('حاضر'));
                            final bool isAbsent = record != null && !isPresent && (record['note'] ?? '').contains('غائب');
                            final bool isToday = dateStr == today;

                            Color cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
                            Color borderColor = Colors.grey.shade300;
                            IconData icon = Icons.circle_outlined;
                            Color iconColor = Colors.grey;

                            if (isPresent) {
                              cardColor = isDark ? Colors.green.shade900.withOpacity(0.4) : Colors.green.shade50;
                              borderColor = Colors.green;
                              icon = Icons.check_circle;
                              iconColor = Colors.green;
                            } else if (isAbsent) {
                              cardColor = isDark ? Colors.red.shade900.withOpacity(0.4) : Colors.red.shade50;
                              borderColor = Colors.red;
                              icon = Icons.cancel;
                              iconColor = Colors.red;
                            }

                            if (isToday) {
                              borderColor = Colors.amber.shade800;
                            }

                            return GestureDetector(
                              onTap: () => _toggleDayStatus(dayNum, lang),
                              onLongPress: () => _manualEntry(lang, existing: record, initialDate: dateStr),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: borderColor, width: isToday ? 2.5 : 1),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 3,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '$dayNum',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: isToday ? Colors.amber.shade900 : null,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Icon(icon, size: 18, color: iconColor),
                                    const SizedBox(height: 2),
                                    Text(
                                      isPresent
                                          ? _tr('حاضر', 'Présent', 'Present', lang)
                                          : (isAbsent
                                              ? _tr('غائب', 'Absent', 'Absent', lang)
                                              : _tr('فارغ', 'Neutre', 'Empty', lang)),
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontFamily: 'Cairo',
                                        color: iconColor,
                                        fontWeight: FontWeight.bold,
                                      ),
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

                  // ── TAB 2: توقيت اليوم وسجل الساعات التفصيلي ─────────────────
                  Column(
                    children: [
                      Container(
                        color: isDark ? const Color(0xFF1A237E) : Colors.indigo.shade700,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        child: Column(
                          children: [
                            Text(
                              _tr('تسجيل الساعات لليوم الحالي', "Pointage d'aujourd'hui", 'Today Check-In/Out', lang),
                              style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildTodayCard(
                                  label: _tr('دخول', 'Entrée', 'In', lang),
                                  value: todayRecord?['check_in'] ?? '--:--',
                                  icon: Icons.login_rounded,
                                  color: Colors.green,
                                ),
                                _buildTodayCard(
                                  label: _tr('خروج', 'Sortie', 'Out', lang),
                                  value: todayRecord?['check_out'] ?? '--:--',
                                  icon: Icons.logout_rounded,
                                  color: Colors.red.shade300,
                                ),
                                _buildTodayCard(
                                  label: _tr('المدة', 'Durée', 'Duration', lang),
                                  value: _calcDuration(todayRecord?['check_in'], todayRecord?['check_out']),
                                  icon: Icons.access_time,
                                  color: Colors.amber.shade300,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _checkIn(lang),
                                    icon: const Icon(Icons.login_rounded, size: 18),
                                    label: Text(_tr('تسجيل الدخول', 'Pointer entrée', 'Check In', lang),
                                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _checkOut(lang),
                                    icon: const Icon(Icons.logout_rounded, size: 18),
                                    label: Text(_tr('تسجيل الخروج', 'Pointer sortie', 'Check Out', lang),
                                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.shade600,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _records.isEmpty
                            ? Center(
                                child: Text(
                                  _tr('لا توجد سجلات حضور بعد', 'Aucun enregistrement', 'No attendance records yet', lang),
                                  style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _records.length,
                                itemBuilder: (ctx, i) {
                                  final r = _records[i];
                                  final isToday = r['attendance_date'] == today;
                                  final duration = _calcDuration(r['check_in'], r['check_out']);
                                  final isPresent = r['check_in'] != null || (r['note'] ?? '').contains('حاضر');
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    color: isToday
                                        ? (isDark ? Colors.indigo.shade900 : Colors.indigo.shade50)
                                        : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
                                    elevation: isToday ? 4 : 1,
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: isPresent ? Colors.green : Colors.red,
                                        child: Icon(
                                          isPresent ? Icons.check_circle : Icons.cancel,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                      title: Text(
                                        r['attendance_date'] ?? '',
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.bold,
                                            color: isToday ? Colors.indigo : null),
                                      ),
                                      subtitle: Text(
                                        '${r['check_in'] != null ? "🟢 دخول: ${r['check_in']}" : ""} ${r['check_out'] != null ? "| 🔴 خروج: ${r['check_out']}" : ""} ${r['note'] != null ? "\n📝 ${r['note']}" : ""}',
                                        style: const TextStyle(fontSize: 11, fontFamily: 'Cairo'),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.teal),
                                        onPressed: () => _manualEntry(lang, existing: r),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildMetricChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _buildTodayCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Cairo')),
        ],
      ),
    );
  }
}
