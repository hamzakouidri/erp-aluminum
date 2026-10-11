import 'package:database_data/widgets/app_material.dart';
import '../sql_database.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'dart:convert';
import 'package:intl/intl.dart';

import 'dart:async';
import '../services/cloud_sync_service.dart';
import 'worker_transactions_detail_screen.dart';
import 'worker_attendance_screen.dart';

class WorkerFinancesScreen extends StatefulWidget {
  final SqlDatabase db;

  /// وضع العرض فقط — يخفي أزرار التعديل والإضافة
  final bool readOnly;

  const WorkerFinancesScreen({
    super.key,
    required this.db,
    this.readOnly = false,
  });

  @override
  State<WorkerFinancesScreen> createState() => _WorkerFinancesScreenState();
}

class _WorkerFinancesScreenState extends State<WorkerFinancesScreen> {
  List<Map<String, dynamic>> _workers = [];
  bool _isLoading = false;
  StreamSubscription? _syncSub;
  DateTime? _startDate;
  DateTime? _endDate;

  String _t(String key) => Localization.translate(
    key,
    Provider.of<AppSettingsProvider>(context, listen: false).language,
  );

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

  Future<void> _showDateFilterDialog() async {
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final lang = settings.language;
    final startCtrl = TextEditingController(
      text: _startDate != null
          ? DateFormat('yyyy-MM-dd').format(_startDate!)
          : '',
    );
    final endCtrl = TextEditingController(
      text: _endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : '',
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.date_range, color: Colors.orange),
            const SizedBox(width: 8),
            Text(
              _tr(
                'تحديد فترة البحث والفلترة بالتاريخ',
                'Filtrer par date',
                'Filter by Date Range',
                lang,
              ),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: startCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: _tr(
                    'تاريخ البداية (من)',
                    'Date de début (Du)',
                    'Start Date (From)',
                    lang,
                  ),
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: _startDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    startCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: endCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: _tr(
                    'تاريخ النهاية (إلى)',
                    'Date de fin (Au)',
                    'End Date (To)',
                    lang,
                  ),
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: _endDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    endCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          if (_startDate != null || _endDate != null)
            TextButton(
              onPressed: () {
                setState(() {
                  _startDate = null;
                  _endDate = null;
                });
                Navigator.pop(ctx);
              },
              child: Text(
                _tr('إلغاء الفلتر 🧹', 'Réinitialiser', 'Reset Filter', lang),
                style: const TextStyle(color: Colors.red, fontFamily: 'Cairo'),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_tr('إلغاء', 'Annuler', 'Cancel', lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _startDate = startCtrl.text.isNotEmpty
                    ? DateTime.tryParse(startCtrl.text)
                    : null;
                _endDate = endCtrl.text.isNotEmpty
                    ? DateTime.tryParse(endCtrl.text)
                    : null;
              });
              Navigator.pop(ctx);
            },
            child: Text(
              _tr('تطبيق الفلتر', 'Appliquer', 'Apply Filter', lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        _loadData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && _workers.isEmpty) {
      setState(() => _isLoading = true);
    }
    final data = await widget.db.readEmployees();
    if (mounted) {
      setState(() {
        _workers = data;
        _isLoading = false;
      });
    }
  }

  void _showAddWorkerDialog() {
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final lang = settings.language;
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final jobRoleCtrl = TextEditingController();
    final salaryCtrl = TextEditingController();
    String salaryType = 'manual';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            _tr(
              'إضافة عامل جديد',
              'Ajouter un nouvel ouvrier',
              'Add New Worker',
              lang,
            ),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: _tr(
                      'اسم العامل (إجباري)',
                      'Nom de l\'ouvrier (Obligatoire)',
                      'Worker Name (Required)',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  decoration: InputDecoration(
                    labelText: _tr(
                      'رقم الهاتف (اختياري)',
                      'Numéro de téléphone (Optionnel)',
                      'Phone Number (Optional)',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                    labelText: _tr(
                      'البريد الإلكتروني (اختياري)',
                      'Email (Optionnel)',
                      'Email (Optional)',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressCtrl,
                  decoration: InputDecoration(
                    labelText: _tr(
                      'العنوان (اختياري)',
                      'Adresse (Optionnelle)',
                      'Address (Optional)',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: jobRoleCtrl,
                  decoration: InputDecoration(
                    labelText: _tr(
                      'المنصب أو الاختصاص (اختياري)',
                      'Poste ou Spécialité (Optionnel)',
                      'Position or Speciality (Optional)',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: salaryType,
                  items: [
                    DropdownMenuItem(
                      value: 'manual',
                      child: Text(
                        _tr(
                          'صاحب متفرق / كراء (بدون راتب ثابت)',
                          'Indépendant / À la قطعة (Sans salaire fixe)',
                          'Independent / Piecework (Without Fixed Salary)',
                          lang,
                        ),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'fixed',
                      child: Text(
                        _tr(
                          'راتب شهري ثابت',
                          'Salaire mensuel fixe',
                          'Fixed Monthly Salary',
                          lang,
                        ),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (val) => setStateDialog(() => salaryType = val!),
                  decoration: InputDecoration(
                    labelText: _tr(
                      'طريقة الدفع / الأجر',
                      'Mode de paiement',
                      'Payment Method',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (salaryType == 'fixed') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: salaryCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'الراتب الشهري (د.ج)',
                        'Salaire mensuel (DA)',
                        'Monthly Salary (DA)',
                        lang,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_tr('إلغاء', 'Annuler', 'Cancel', lang)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty) {
                  final uid =
                      'local_worker_${DateTime.now().millisecondsSinceEpoch}';
                  final baseSalary = double.tryParse(salaryCtrl.text) ?? 0.0;

                  await widget.db.insertEmployee(
                    uid,
                    emailCtrl.text,
                    nameCtrl.text,
                    jsonEncode({}),
                    salaryType: salaryType,
                    baseSalary: baseSalary,
                    phone: phoneCtrl.text,
                    address: addressCtrl.text,
                    jobRole: jobRoleCtrl.text,
                  );
                  Navigator.pop(context);
                  _loadData();
                }
              },
              child: Text(_tr('حفظ', 'Enregistrer', 'Save', lang)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditWorkerDialog(Map<String, dynamic> worker) {
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final lang = settings.language;
    final nameCtrl = TextEditingController(text: worker['name'] ?? '');
    final phoneCtrl = TextEditingController(text: worker['phone'] ?? '');
    final emailCtrl = TextEditingController(text: worker['email'] ?? '');
    final addressCtrl = TextEditingController(text: worker['address'] ?? '');
    final jobRoleCtrl = TextEditingController(text: worker['job_role'] ?? '');
    final salaryCtrl = TextEditingController(
      text: (worker['base_salary'] ?? 0.0).toString(),
    );
    String salaryType = worker['salary_type'] ?? 'manual';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            _tr(
              'تعديل بيانات العامل',
              'Modifier les données de l\'ouvrier',
              'Edit Worker Info',
              lang,
            ),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: _tr(
                      'اسم العامل (إجباري)',
                      'Nom de l\'ouvrier (Obligatoire)',
                      'Worker Name (Required)',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  decoration: InputDecoration(
                    labelText: _tr(
                      'رقم الهاتف (اختياري)',
                      'Numéro de téléphone (Optionnel)',
                      'Phone Number (Optional)',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                    labelText: _tr(
                      'البريد الإلكتروني (اختياري)',
                      'Email (Optionnel)',
                      'Email (Optional)',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressCtrl,
                  decoration: InputDecoration(
                    labelText: _tr(
                      'العنوان (اختياري)',
                      'Adresse (Optionnelle)',
                      'Address (Optional)',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: jobRoleCtrl,
                  decoration: InputDecoration(
                    labelText: _tr(
                      'المنصب أو الاختصاص (اختياري)',
                      'Poste ou Spécialité (Optionnel)',
                      'Position or Speciality (Optional)',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: salaryType,
                  items: [
                    DropdownMenuItem(
                      value: 'manual',
                      child: Text(
                        _tr(
                          'صاحب متفرق / كراء (بدون راتب ثابت)',
                          'Indépendant / À la قطعة (Sans salaire fixe)',
                          'Independent / Piecework (Without Fixed Salary)',
                          lang,
                        ),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'fixed',
                      child: Text(
                        _tr(
                          'راتب شهري ثابت',
                          'Salaire mensuel fixe',
                          'Fixed Monthly Salary',
                          lang,
                        ),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (val) => setStateDialog(() => salaryType = val!),
                  decoration: InputDecoration(
                    labelText: _tr(
                      'طريقة الدفع / الأجر',
                      'Mode de paiement',
                      'Payment Method',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (salaryType == 'fixed') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: salaryCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _tr(
                        'الراتب الشهري (د.ج)',
                        'Salaire mensuel (DA)',
                        'Monthly Salary (DA)',
                        lang,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_tr('إلغاء', 'Annuler', 'Cancel', lang)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty) {
                  final baseSalary = double.tryParse(salaryCtrl.text) ?? 0.0;

                  await widget.db.updateEmployeeFullInfo(
                    worker['uid'],
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    address: addressCtrl.text.trim(),
                    jobRole: jobRoleCtrl.text.trim(),
                    salaryType: salaryType,
                    baseSalary: baseSalary,
                  );
                  Navigator.pop(context);
                  _loadData();
                }
              },
              child: Text(_tr('حفظ', 'Enregistrer', 'Save', lang)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTransactionDialog(Map<String, dynamic> worker) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String type = 'advance'; // advance (سلفة) or salary (راتب)
    String paymentSource = 'الصندوق الرئيسي';
    List<String> caisseNames = [
      'الصندوق الرئيسي',
      'الصندوق المفرد',
      'الحساب البنكي / البنك',
      'يدوي (بدون اقتطاع صندوق)',
    ];

    try {
      final caissesData = await widget.db.readCaisses();
      final names = caissesData
          .map((c) => c['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      if (names.isNotEmpty) {
        caisseNames = [
          ...names,
          'الحساب البنكي / البنك',
          'يدوي (بدون اقتطاع صندوق)',
        ];
      }
    } catch (_) {}

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            '${_t('تسجيل مال للعامل')}: ${worker['name']}',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  items: [
                    DropdownMenuItem(
                      value: 'advance',
                      child: Text(
                        _t('سلفة (Advance)'),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'salary',
                      child: Text(
                        _t('أجرة (Salary)'),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                  ],
                  onChanged: (val) => setStateDialog(() => type = val!),
                  decoration: InputDecoration(
                    labelText: _t('نوع العملية'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                // ── اختيار الصندوق (Caisse) ────────────────────────────
                DropdownButtonFormField<String>(
                  value: paymentSource,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _t('مصدر الدفع / الصندوق'),
                    border: OutlineInputBorder(),
                  ),
                  items: caisseNames
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setStateDialog(() => paymentSource = v!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _t('المبلغ (دج)'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: _t('ملاحظة'),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () async {
                if (amountCtrl.text.isNotEmpty) {
                  final rawText = amountCtrl.text
                      .replaceAll('،', '')
                      .replaceAll(',', '')
                      .replaceAll(' ', '')
                      .replaceAll('\u00a0', '');
                  final amount = double.tryParse(rawText) ?? 0.0;
                  final settings = Provider.of<AppSettingsProvider>(
                    context,
                    listen: false,
                  );
                  final workerName = worker['name']?.toString() ?? '';
                  final empId = worker['id'] as int? ?? 0;

                  // 1. Record in worker's account
                  await widget.db.insertWorkerTransaction(
                    worker['uid'],
                    amount,
                    type,
                    noteCtrl.text.isNotEmpty
                        ? noteCtrl.text
                        : (type == 'advance' ? 'سلفة مالية' : 'دفعة أجر'),
                    recordedBy: settings.userDisplayName,
                    caisseName: paymentSource,
                  );

                  // 2. If source is a real caisse, record Décaissement in Treasury
                  if (!paymentSource.contains('يدوي')) {
                    await widget.db.insertTreasury(
                      'Décaissement',
                      amount,
                      'إلى العامل: $workerName - ${type == 'advance' ? 'سلفة' : 'دفعة أجر'} (${noteCtrl.text.isNotEmpty ? noteCtrl.text : 'بدون ملاحظات'})',
                      entityType: 'Worker',
                      entityId: empId,
                      caisseName: paymentSource,
                      recordedBy: settings.userDisplayName,
                    );
                  }

                  Navigator.pop(context);
                  if (mounted) {
                    _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _t('تم تسجيل العملية بنجاح وخصمها من الصندوق'),
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
              child: Text(_t('حفظ')),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteTransaction(
    Map<String, dynamic> worker,
    Map<String, dynamic> trans,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _t('تأكيد حذف العملية'),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        content: Text(
          '${_t('هل أنت متأكد من حذف هذه العملية بقيمة')} ${trans['amount']} د.ج؟ ${_t('سيتم إلغاء الحركة واسترجاع المبلغ إلى الصندوق تلقائياً.')} ',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('إلغاء')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await widget.db.deleteWorkerTransaction(
                trans['id'] as int,
                worker['id'] as int,
                trans['amount'] as double,
              );
              Navigator.pop(context); // Close confirm
              Navigator.pop(context); // Close history list
              _loadData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _t('تم حذف العملية بنجاح وإعادة المبلغ للصندوق'),
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text(_t('حذف'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditTransactionDialog(
    Map<String, dynamic> worker,
    Map<String, dynamic> trans,
  ) {
    final amountCtrl = TextEditingController(text: trans['amount'].toString());
    final noteCtrl = TextEditingController(text: trans['note'] ?? '');
    String type = trans['typeRaw'] ?? 'advance';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            '${_t('تعديل عملية')}: ${worker['name']}',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  items: [
                    DropdownMenuItem(
                      value: 'advance',
                      child: Text(
                        _t('سلفة (Advance)'),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'salary',
                      child: Text(
                        _t('أجرة (Salary)'),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                  ],
                  onChanged: (val) => setStateDialog(() => type = val!),
                  decoration: InputDecoration(
                    labelText: _t('نوع العملية'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _t('المبلغ (سيُعدل بالصندوق)'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: _t('ملاحظة'),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () async {
                if (amountCtrl.text.isNotEmpty) {
                  final rawText = amountCtrl.text
                      .replaceAll('،', '')
                      .replaceAll(',', '')
                      .replaceAll(' ', '')
                      .replaceAll('\u00a0', '');
                  final newAmount = double.tryParse(rawText) ?? 0.0;

                  await widget.db.updateWorkerTransaction(
                    trans['id'] as int,
                    worker['uid'],
                    worker['id'] as int,
                    trans['amount'] as double,
                    newAmount,
                    trans['typeRaw'] as String,
                    type,
                    trans['note'] as String,
                    noteCtrl.text,
                    worker['name'],
                  );

                  Navigator.pop(context); // Close edit dialog
                  Navigator.pop(context); // Close history dialog
                  _loadData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _t('تم تعديل العملية بنجاح وتحديث الصندوق'),
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              },
              child: Text(_t('حفظ')),
            ),
          ],
        ),
      ),
    );
  }

  void _viewWorkerHistory(Map<String, dynamic> worker) async {
    final wTrans = await widget.db.readWorkerTransactions(worker['uid']);

    final List<Map<String, dynamic>> combined = [];
    for (var t in wTrans) {
      final createdAt = t['created_at']?.toString() ?? '';
      DateTime date = DateTime.now();
      try {
        date = DateTime.parse(createdAt);
      } catch (_) {}
      combined.add({
        'id': t['id'],
        'date': date,
        'amount': (t['amount'] as num?)?.toDouble() ?? 0.0,
        'type': t['transaction_type'] == 'advance' ? 'سلفة' : 'أجرة',
        'typeRaw': t['transaction_type'] ?? 'advance',
        'note': t['note'] ?? '',
      });
    }

    combined.sort((a, b) => b['date'].compareTo(a['date']));

    double totalReceived = 0.0;
    for (var t in combined) {
      totalReceived += t['amount'];
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'سجل العامل: ${worker['name']}',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'إجمالي ما استلمه: $totalReceived د.ج',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              if (worker['salary_type'] == 'fixed') ...[
                const SizedBox(height: 5),
                Text(
                  'الراتب الشهري الثابت: ${worker['base_salary']} د.ج',
                  style: const TextStyle(fontSize: 14, color: Colors.teal),
                ),
              ],
              const Divider(),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: combined.length,
                  itemBuilder: (context, index) {
                    final t = combined[index];
                    return ListTile(
                      title: Text(
                        '${t['amount']} د.ج - ${t['type']}',
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                      subtitle: Text(
                        '${t['note']} \n${t['date'].toString().split(' ')[0]}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _showEditTransactionDialog(worker, t);
                          } else if (value == 'delete') {
                            _confirmDeleteTransaction(worker, t);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.edit,
                                  color: Colors.orange,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  _t('تعديل'),
                                  style: TextStyle(fontFamily: 'Cairo'),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  _t('حذف'),
                                  style: TextStyle(fontFamily: 'Cairo'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _t('إغلاق'),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr(
            'إدارة شؤون وأجور العمال',
            'Gestion des ouvriers et salaires',
            'Worker Management & Wages',
            lang,
          ),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isDark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.orange,
        actions: [
          IconButton(
            icon: Icon(
              (_startDate != null || _endDate != null)
                  ? Icons.date_range
                  : Icons.date_range_outlined,
              color: (_startDate != null || _endDate != null)
                  ? Colors.amber
                  : Colors.white,
            ),
            tooltip: _tr(
              'فلترة بالتاريخ (تاريخ البداية وتاريخ النهاية)',
              'Filtrer par date',
              'Date Filter',
              lang,
            ),
            onPressed: _showDateFilterDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _workers.length,
              itemBuilder: (context, index) {
                final worker = _workers[index];
                return Card(
                  margin: const EdgeInsets.all(10),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.orange,
                      child: Icon(Icons.engineering, color: Colors.white),
                    ),
                    title: Text(
                      worker['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    subtitle: Text(
                      worker['salary_type'] == 'fixed'
                          ? 'راتب ثابت: ${worker['base_salary']} د.ج'
                          : 'سحب متفرق',
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                        fontFamily: 'Cairo',
                      ),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorkerTransactionsDetailScreen(
                            worker: worker,
                            db: widget.db,
                            initialStartDate: _startDate,
                            initialEndDate: _endDate,
                          ),
                        ),
                      ).then((_) => _loadData());
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (worker['salary_type'] == 'fixed')
                          IconButton(
                            icon: const Icon(
                              Icons.co_present_rounded,
                              color: Colors.teal,
                            ),
                            tooltip: _tr(
                              'سجل حضور ودخول وخروج العامل',
                              'Présence ouvrier',
                              'Worker Attendance',
                              lang,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => WorkerAttendanceScreen(
                                    worker: worker,
                                    db: widget.db,
                                  ),
                                ),
                              );
                            },
                          ),
                        if (!widget.readOnly)
                          IconButton(
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: Colors.orange,
                            ),
                            tooltip: _tr(
                              'تعديل بيانات العامل',
                              'Modifier ouvrier',
                              'Edit Worker',
                              lang,
                            ),
                            onPressed: () => _showEditWorkerDialog(worker),
                          ),
                        IconButton(
                          icon: const Icon(
                            Icons.account_balance_wallet_outlined,
                            color: Colors.blue,
                          ),
                          tooltip: _tr(
                            'كشف وسجل السلفات والمعاملات',
                            'Relevé des avances',
                            'View Advances Statement',
                            lang,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WorkerTransactionsDetailScreen(
                                  worker: worker,
                                  db: widget.db,
                                  initialStartDate: _startDate,
                                  initialEndDate: _endDate,
                                ),
                              ),
                            ).then((_) => _loadData());
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddWorkerDialog,
              backgroundColor: isDark ? Colors.orange[800] : Colors.orange,
              icon: const Icon(Icons.person_add),
              label: Text(
                _t('إضافة عامل'),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
    );
  }
}
