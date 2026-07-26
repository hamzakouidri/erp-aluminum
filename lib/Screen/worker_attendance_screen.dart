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

class _WorkerAttendanceScreenState extends State<WorkerAttendanceScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _records = [];
  final _dateFormat = DateFormat('yyyy-MM-dd');
  final _timeFormat = DateFormat('HH:mm');

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
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final uid = widget.worker['uid']?.toString() ?? widget.worker['id']?.toString() ?? '';
    final data = await widget.db.readWorkerAttendance(uid);
    if (mounted) {
      setState(() {
        _records = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _checkIn(AppLanguage lang) async {
    final today = _dateFormat.format(DateTime.now());
    final uid = widget.worker['uid']?.toString() ?? widget.worker['id']?.toString() ?? '';
    // هل يوجد تسجيل دخول اليوم بالفعل؟
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
    );
    _loadData();
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
    _loadData();
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

  Future<void> _manualEntry(AppLanguage lang, {Map<String, dynamic>? existing}) async {
    final dateCtrl = TextEditingController(
        text: existing != null ? existing['attendance_date'] : _dateFormat.format(DateTime.now()));
    final inCtrl = TextEditingController(text: existing?['check_in'] ?? '');
    final outCtrl = TextEditingController(text: existing?['check_out'] ?? '');
    final noteCtrl = TextEditingController(text: existing?['note'] ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _tr('إدخال يدوي للحضور', 'Saisie manuelle présence', 'Manual Attendance Entry', lang),
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
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.tryParse(dateCtrl.text) ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) dateCtrl.text = _dateFormat.format(picked);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: inCtrl,
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        labelText: _tr('وقت الدخول', 'Entrée', 'Check In', lang),
                        border: const OutlineInputBorder(),
                        hintText: 'HH:mm',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: outCtrl,
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        labelText: _tr('وقت الخروج', 'Sortie', 'Check Out', lang),
                        border: const OutlineInputBorder(),
                        hintText: 'HH:mm',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: noteCtrl,
                decoration: InputDecoration(
                  labelText: _tr('ملاحظة', 'Note', 'Note', lang),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () async {
              final uid = widget.worker['uid']?.toString() ?? widget.worker['id']?.toString() ?? '';
              await widget.db.upsertWorkerAttendance(
                workerUid: uid,
                date: dateCtrl.text,
                checkIn: inCtrl.text.isNotEmpty ? inCtrl.text : null,
                checkOut: outCtrl.text.isNotEmpty ? outCtrl.text : null,
                note: noteCtrl.text,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _loadData();
            },
            child: Text(_tr('حفظ', 'Enregistrer', 'Save', lang),
                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo')),
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

    return Directionality(
      textDirection: lang == AppLanguage.arabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey.shade100,
        appBar: AppBar(
          title: Text(
            '${_tr('حضور العامل', 'Présence Ouvrier', 'Worker Attendance', lang)}: ${widget.worker['name']}',
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
          ),
          backgroundColor: isDark ? const Color(0xFF1A237E) : Colors.indigo.shade700,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: _tr('إدخال يدوي', 'Saisie manuelle', 'Manual Entry', lang),
              onPressed: () => _manualEntry(lang),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ── بطاقة اليوم ──────────────────────────────────────────
                  Container(
                    color: isDark ? const Color(0xFF1A237E) : Colors.indigo.shade700,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    child: Column(
                      children: [
                        Text(
                          _tr('اليوم', "Aujourd'hui", 'Today', lang),
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

                  // ── سجل الحضور ───────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.history_rounded, size: 18, color: Colors.indigo),
                        const SizedBox(width: 6),
                        Text(
                          _tr('سجل الحضور (${_records.length} يوم)', 'Historique (${_records.length} jours)',
                              'History (${_records.length} days)', lang),
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.indigo.shade800),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _records.isEmpty
                        ? Center(
                            child: Text(
                              _tr('لا توجد سجلات حضور بعد', 'Aucun enregistrement de présence', 'No attendance records yet', lang),
                              style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _records.length,
                            itemBuilder: (ctx, i) {
                              final r = _records[i];
                              final isToday = r['attendance_date'] == today;
                              final duration = _calcDuration(r['check_in'], r['check_out']);
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                color: isToday
                                    ? (isDark ? Colors.indigo.shade900 : Colors.indigo.shade50)
                                    : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
                                elevation: isToday ? 4 : 1,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        r['check_in'] != null && r['check_out'] != null
                                            ? Colors.green
                                            : r['check_in'] != null
                                                ? Colors.orange
                                                : Colors.grey,
                                    child: Icon(
                                      r['check_in'] != null && r['check_out'] != null
                                          ? Icons.check_circle
                                          : r['check_in'] != null
                                              ? Icons.access_time
                                              : Icons.cancel_outlined,
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
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.login_rounded, size: 13, color: Colors.green),
                                          const SizedBox(width: 4),
                                          Text(r['check_in'] ?? '--:--',
                                              style: const TextStyle(fontSize: 12, fontFamily: 'Cairo')),
                                          const SizedBox(width: 12),
                                          const Icon(Icons.logout_rounded, size: 13, color: Colors.red),
                                          const SizedBox(width: 4),
                                          Text(r['check_out'] ?? '--:--',
                                              style: const TextStyle(fontSize: 12, fontFamily: 'Cairo')),
                                          const SizedBox(width: 12),
                                          const Icon(Icons.schedule, size: 13, color: Colors.amber),
                                          const SizedBox(width: 4),
                                          Text(duration,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontFamily: 'Cairo',
                                                  color: Colors.amber.shade800,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      if ((r['note'] ?? '').isNotEmpty)
                                        Text('📝 ${r['note']}',
                                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    ],
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
              style: TextStyle(
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
