import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../settings/localization.dart';
import 'receipt_pdf_service.dart';

class TreasuryScreen extends StatefulWidget {
  final SqlDatabase db;

  const TreasuryScreen({super.key, required this.db});

  @override
  State<TreasuryScreen> createState() => _TreasuryScreenState();
}

class _TreasuryScreenState extends State<TreasuryScreen> {
  List<Map<String, dynamic>> _allTransactions = [];
  List<Map<String, dynamic>> _filteredTransactions = [];
  bool _isLoading = false;
  double _totalBalance = 0.0;
  String _searchQuery = '';
  List<String> _caisseNames = [];
  String _selectedCaisse = 'الكل';
  String _selectedTypeFilter = 'all'; // 'all', 'income', 'expense'
  String _selectedCategoryFilter = 'all'; // 'all', 'general_expenses'
  double _filteredTotalIncome = 0.0;
  double _filteredTotalExpense = 0.0;
  bool _showSearch = false;
  bool _showFilters = false;

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _suppliers = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadEntities();
  }

  Future<void> _loadEntities() async {
    final clients = await widget.db.readClient();
    final workers = await widget.db.readEmployees();
    final suppliers = await widget.db.readSuppliers();
    if (mounted) {
      setState(() {
        _clients = clients;
        _workers = workers;
        _suppliers = suppliers;
      });
    }
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      await widget.db.migrateLegacyTreasuryRecords();
      
      final data = await widget.db.readTreasury();
      final caisses = await widget.db.readCaisses();
      final caisseNames = caisses.map((c) => c['name'].toString()).toList();
      if (caisseNames.isEmpty) {
        caisseNames.add('الصندوق الرئيسي');
      }

      double balance = 0.0;
      for (var row in data) {
        final cName = row['caisse_name']?.toString() ?? 'الصندوق الرئيسي';
        if (_selectedCaisse != 'الكل' && cName != _selectedCaisse) {
          continue;
        }
        final type = row['transaction_type']?.toString() ?? '';
        if (type == 'Encaissement' || type == 'income') {
          balance += (row['amount'] as num?)?.toDouble() ?? 0.0;
        } else if (type == 'Décaissement' || type == 'expense') {
          balance -= (row['amount'] as num?)?.toDouble() ?? 0.0;
        } else {
          if (type.contains('Achat') || type.contains('Purchase')) {
            balance -= (row['amount'] as num?)?.toDouble() ?? 0.0;
          } else {
            balance += (row['amount'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }

      if (mounted) {
        setState(() {
          _allTransactions = data;
          _caisseNames = caisseNames;
          _totalBalance = balance;
          _applyFilter();
        });
      }
    } catch (e) {
      debugPrint('Error loading treasury: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilter() {
    List<Map<String, dynamic>> filtered = _allTransactions;

    // 1. Caisse filter
    if (_selectedCaisse != 'الكل') {
      filtered = filtered.where((t) {
        final cName = t['caisse_name']?.toString() ?? 'الصندوق الرئيسي';
        return cName == _selectedCaisse;
      }).toList();
    }

    // 2. Type Filter (income / expense)
    if (_selectedTypeFilter != 'all') {
      filtered = filtered.where((t) {
        final tType = t['transaction_type']?.toString() ?? '';
        final isInc = tType == 'Encaissement' ||
            tType == 'income' ||
            (!tType.contains('Achat') &&
                !tType.contains('Purchase') &&
                !tType.contains('Décaissement') &&
                !tType.contains('expense'));
        if (_selectedTypeFilter == 'income') {
          return isInc;
        } else {
          return !isInc;
        }
      }).toList();
    }

    // 3. Category Filter (general expenses/faux frais/additional costs)
    if (_selectedCategoryFilter == 'general_expenses') {
      filtered = filtered.where((t) {
        final entityType = t['entity_type']?.toString();
        final desc = (t['description'] ?? '').toString().toLowerCase();
        
        final isGeneral = entityType == 'General' ||
            desc.contains('dépens') ||
            desc.contains('مصاريف') ||
            desc.contains('مازوت') ||
            desc.contains('سيارة') ||
            desc.contains('تصليح') ||
            desc.contains('répar') ||
            desc.contains('carburant');
            
        return isGeneral;
      }).toList();
    }

    // 4. Search filter
    if (_searchQuery.isNotEmpty) {
      final search = _searchQuery.trim().toLowerCase();
      filtered = filtered.where((t) {
        final desc = (t['description'] ?? '').toString().toLowerCase();
        final amount = (t['amount'] ?? '').toString().toLowerCase();
        final phone = (t['phone'] ?? '').toString().toLowerCase();
        final recorded = (t['recorded_by'] ?? '').toString().toLowerCase();
        final date = (t['created_at'] ?? '').toString().toLowerCase();
        final tType = (t['transaction_type'] ?? '').toString().toLowerCase();
        final pMethod = (t['payment_method'] ?? '').toString().toLowerCase();
        final cName = (t['caisse_name'] ?? '').toString().toLowerCase();

        return desc.contains(search) ||
            amount.contains(search) ||
            phone.contains(search) ||
            recorded.contains(search) ||
            date.contains(search) ||
            tType.contains(search) ||
            pMethod.contains(search) ||
            cName.contains(search);
      }).toList();
    }

    // Calculate sum of filtered records
    double inc = 0.0;
    double exp = 0.0;
    for (var row in filtered) {
      final tType = row['transaction_type']?.toString() ?? '';
      final isInc = tType == 'Encaissement' ||
          tType == 'income' ||
          (!tType.contains('Achat') &&
              !tType.contains('Purchase') &&
              !tType.contains('Décaissement') &&
              !tType.contains('expense'));
      final amt = (row['amount'] as num?)?.toDouble() ?? 0.0;
      if (isInc) {
        inc += amt;
      } else {
        exp += amt;
      }
    }

    setState(() {
      _filteredTransactions = filtered;
      _filteredTotalIncome = inc;
      _filteredTotalExpense = exp;
    });
  }

  Widget _highlightText(String text, String query, TextStyle defaultStyle) {
    if (query.isEmpty) {
      return Text(text, style: defaultStyle);
    }

    final String textLower = text.toLowerCase();
    final String queryLower = query.toLowerCase();

    final List<TextSpan> spans = [];
    int start = 0;
    int indexOfMatch;

    while ((indexOfMatch = textLower.indexOf(queryLower, start)) != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(
          text: text.substring(start, indexOfMatch),
          style: defaultStyle,
        ));
      }

      spans.add(TextSpan(
        text: text.substring(indexOfMatch, indexOfMatch + query.length),
        style: defaultStyle.copyWith(
          backgroundColor: Colors.yellow.shade200,
          color: Colors.black87,
          fontWeight: FontWeight.bold,
        ),
      ));

      start = indexOfMatch + query.length;
    }

    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: defaultStyle,
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
  }

  Future<void> _deleteTransaction(Map<String, dynamic> item) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          Localization.translate('تأكيد الحذف', lang),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        content: Text(
          Localization.translate('هل أنت متأكد من حذف هذه المعاملة؟', lang),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(Localization.translate('إلغاء', lang), style: const TextStyle(fontFamily: 'Cairo')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              Localization.translate('حذف', lang),
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final id = item['id'] as int;
      await widget.db.deleteTreasury(id);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localization.translate('تم حذف المعاملة بنجاح', lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        );
      }
    }
  }

  void _showEditTransactionDialog(Map<String, dynamic> item) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final id = item['id'] as int;
    final amountCtrl = TextEditingController(text: item['amount']?.toString() ?? '');
    final descCtrl = TextEditingController(text: item['description'] ?? '');
    String selectedCaisse = item['caisse_name']?.toString() ?? 'الصندوق الرئيسي';
    String selectedPaymentMethod = item['payment_method']?.toString() ?? 'نقداً / Espèce';
    
    DateTime selectedDate;
    try {
      selectedDate = DateTime.parse(item['created_at']);
    } catch (_) {
      selectedDate = DateTime.now();
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate('تعديل المعاملة', lang),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: Localization.translate('المبلغ (د.ج)', lang),
                    prefixIcon: const Icon(Icons.attach_money),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (date != null && mounted) {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(selectedDate),
                      );
                      if (time != null) {
                        setStateDialog(() {
                          selectedDate = DateTime(date.year, date.month,
                              date.day, time.hour, time.minute);
                        });
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18, color: Colors.teal),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('dd/MM/yyyy  HH:mm').format(selectedDate),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _caisseNames.contains(selectedCaisse) ? selectedCaisse : (_caisseNames.isNotEmpty ? _caisseNames.first : null),
                  decoration: InputDecoration(
                    labelText: Localization.translate('اختر الصندوق', lang),
                    border: const OutlineInputBorder(),
                  ),
                  items: _caisseNames
                      .map((name) => DropdownMenuItem<String>(
                            value: name,
                            child: Text(
                              Localization.translate(name, lang),
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setStateDialog(() => selectedCaisse = val!);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: selectedPaymentMethod,
                  decoration: InputDecoration(
                    labelText: Localization.translate('طريقة الدفع', lang),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    'نقداً / Espèce',
                    'شيك / Chèque',
                    'شيك مصدق / Chèque de banque',
                    'تحويل بنكي / Virement',
                    'بطاقة بنكية / CIB',
                    'CCP / حساب جاري',
                    'بريدي موب / BaridiMob',
                  ]
                      .map((method) => DropdownMenuItem<String>(
                            value: method,
                            child: Text(
                              method,
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setStateDialog(() => selectedPaymentMethod = val!);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: Localization.translate('البيان / السبب', lang),
                    prefixIcon: const Icon(Icons.notes),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('إلغاء', lang), style: const TextStyle(fontFamily: 'Cairo')),
            ),
            TextButton(
              onPressed: () async {
                final double? newAmt = double.tryParse(amountCtrl.text);
                if (newAmt == null || newAmt <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(Localization.translate('يرجى إدخال مبلغ صحيح', lang))),
                  );
                  return;
                }

                Navigator.pop(context);
                await widget.db.updateTreasury(
                  id,
                  newAmount: newAmt,
                  newDescription: descCtrl.text,
                  newCaisse: selectedCaisse,
                  newPaymentMethod: selectedPaymentMethod,
                  newCreatedAt: selectedDate.toIso8601String(),
                );
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(Localization.translate('تم تعديل المعاملة بنجاح', lang))),
                );
              },
              child: Text(
                Localization.translate('حفظ', lang),
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReceiptOptions(BuildContext context, Map<String, dynamic> item) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.print, color: Colors.teal),
                title: Text(
                  Localization.translate('طباعة الوصل', lang) + ' / Imprimer',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ReceiptPdfService.printReceipt(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.orange),
                title: Text(
                  Localization.translate('مشاركة', lang) + ' / Partager',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ReceiptPdfService.shareReceipt(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download, color: Colors.blue),
                title: Text(
                  Localization.translate('حفظ الوصل', lang) + ' / Enregistrer',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ReceiptPdfService.saveReceipt(item, context);
                },
              ),
              if (Provider.of<AppSettingsProvider>(context, listen: false).canEditPayments())
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blueGrey),
                  title: Text(
                    Localization.translate('تعديل المعاملة', lang) + ' / Modifier',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditTransactionDialog(item);
                  },
                ),
              if (Provider.of<AppSettingsProvider>(context, listen: false).canDeletePayments())
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: Text(
                    Localization.translate('حذف المعاملة', lang) + ' / Supprimer',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteTransaction(item);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showManageCaissesDialog() {
    final nameCtrl = TextEditingController();
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(
                Localization.translate('إدارة الصناديق والحسابات', lang),
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              labelText: Localization.translate('اسم صندوق جديد', lang),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final name = nameCtrl.text.trim();
                            if (name.isNotEmpty) {
                              await widget.db.insertCaisse(name);
                              nameCtrl.clear();
                              setStateDialog(() {});
                              _loadData();
                            }
                          },
                          child: Text(Localization.translate('إضافة', lang)),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Text(
                      Localization.translate('الصناديق الحالية (اضغط للتعديل أو الحذف):', lang),
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: widget.db.readCaisses(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final list = snapshot.data!;
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: list.length,
                            itemBuilder: (context, idx) {
                              final item = list[idx];
                              final id = item['id'] as int;
                              final name = item['name'].toString();
                              return Card(
                                child: ListTile(
                                  title: Text(
                                    Localization.translate(name, lang),
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.blue),
                                        onPressed: () async {
                                          final editCtrl = TextEditingController(text: name);
                                          final newName = await showDialog<String>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: Text(Localization.translate('تعديل اسم الصندوق', lang)),
                                              content: TextField(
                                                controller: editCtrl,
                                                decoration: InputDecoration(
                                                  labelText: Localization.translate('الاسم الجديد', lang),
                                                  border: const OutlineInputBorder(),
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx),
                                                  child: Text(Localization.translate('إلغاء', lang)),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.pop(ctx, editCtrl.text.trim()),
                                                  child: Text(Localization.translate('حفظ', lang)),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (newName != null && newName.isNotEmpty && newName != name) {
                                            await widget.db.updateCaisseName(id, newName, name);
                                            setStateDialog(() {});
                                            _loadData();
                                          }
                                        },
                                      ),
                                      if (list.length > 1)
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: Text(Localization.translate('تأكيد الحذف', lang)),
                                                content: Text(
                                                  '${Localization.translate('هل أنت متأكد من حذف الصندوق', lang)} "${Localization.translate(name, lang)}"؟ ${Localization.translate('سيتم نقل معاملاته تلقائياً للصندوق الآخر.', lang)}',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx, false),
                                                    child: Text(Localization.translate('إلغاء', lang)),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx, true),
                                                    child: Text(
                                                      Localization.translate('حذف', lang),
                                                      style: const TextStyle(color: Colors.red),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await widget.db.deleteCaisse(id, name);
                                              setStateDialog(() {});
                                              _loadData();
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
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
                  child: Text(Localization.translate('إغلاق', lang)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddTransactionDialog() {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    String type = 'Encaissement';
    String entityType = 'Client';
    int? selectedEntityId;
    double oldBalance = 0.0;
    double newBalance = 0.0;
    bool loadingBalance = false;
    DateTime selectedDate = DateTime.now();
    String selectedCaisse = _caisseNames.isNotEmpty ? _caisseNames.first : 'الصندوق الرئيسي';
    String selectedPaymentMethod = 'نقداً / Espèce';

    Future<void> loadBalance(StateSetter setStateDialog, String eType, int eId) async {
      setStateDialog(() => loadingBalance = true);
      double bal = 0.0;
      if (eType == 'Client') {
        bal = await widget.db.getClientBalance(eId);
      } else if (eType == 'Supplier') {
        bal = await widget.db.getSupplierBalance(eId);
      } else if (eType == 'Worker') {
        bal = await widget.db.getWorkerBalance(eId);
      }
      setStateDialog(() {
        oldBalance = bal;
        final amount = double.tryParse(amountCtrl.text) ?? 0.0;
        newBalance = type == 'Encaissement'
            ? oldBalance - amount
            : oldBalance + amount;
        loadingBalance = false;
      });
    }

    void recalcNewBalance(StateSetter setStateDialog) {
      final amount = double.tryParse(amountCtrl.text) ?? 0.0;
      setStateDialog(() {
        newBalance = type == 'Encaissement'
            ? oldBalance - amount
            : oldBalance + amount;
      });
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate('إضافة معاملة للصندوق', lang),
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: InputDecoration(
                    labelText: Localization.translate('نوع المعاملة', lang),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'Encaissement',
                      child: Text(
                        Localization.translate('قبض / Encaissement', lang),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Décaissement',
                      child: Text(
                        Localization.translate('دفع / Décaissement', lang),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    setStateDialog(() {
                      type = val!;
                      if (type == 'Encaissement') {
                        entityType = 'Client';
                      } else {
                        entityType = 'Supplier';
                      }
                      selectedEntityId = null;
                      phoneCtrl.clear();
                      oldBalance = 0.0;
                      newBalance = 0.0;
                    });
                  },
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  value: entityType,
                  decoration: InputDecoration(
                    labelText: Localization.translate('نوع الجهة', lang),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    if (type == 'Encaissement') ...[
                      DropdownMenuItem(
                        value: 'Client',
                        child: Text(
                          Localization.translate('زبون', lang),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Supplier',
                        child: Text(
                          Localization.translate('مورد (استرجاع)', lang),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ),
                    ] else ...[
                      DropdownMenuItem(
                        value: 'Supplier',
                        child: Text(
                          Localization.translate('مورد', lang),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Worker',
                        child: Text(
                          Localization.translate('عامل', lang),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'General',
                        child: Text(
                          Localization.translate('مصاريف عامة', lang),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ),
                    ],
                  ],
                  onChanged: (val) {
                    setStateDialog(() {
                      entityType = val!;
                      selectedEntityId = null;
                      phoneCtrl.clear();
                      oldBalance = 0.0;
                      newBalance = 0.0;
                    });
                  },
                ),
                const SizedBox(height: 10),

                if (entityType == 'Client')
                  DropdownButtonFormField<int>(
                    value: selectedEntityId,
                    hint: Text(Localization.translate('اختر الزبون', lang),
                        style: const TextStyle(fontFamily: 'Cairo')),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: _clients
                        .map((c) => DropdownMenuItem<int>(
                              value: c['id'] as int,
                              child: Text(
                                '${c['firstname']} ${c['lastname']}',
                                style: const TextStyle(fontFamily: 'Cairo'),
                              ),
                            ))
                        .toList(),
                    onChanged: (val) {
                      setStateDialog(() => selectedEntityId = val);
                      if (val != null) {
                        final client = _clients.firstWhere((c) => c['id'] == val);
                        phoneCtrl.text = client['phone1'] ?? '';
                        loadBalance(setStateDialog, 'Client', val);
                      }
                    },
                  )
                else if (entityType == 'Supplier')
                  DropdownButtonFormField<int>(
                    value: selectedEntityId,
                    hint: Text(Localization.translate('اختر المورد', lang),
                        style: const TextStyle(fontFamily: 'Cairo')),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: _suppliers
                        .map((s) => DropdownMenuItem<int>(
                              value: s['id'] as int,
                              child: Text(
                                s['name']?.toString() ?? '-',
                                style: const TextStyle(fontFamily: 'Cairo'),
                              ),
                            ))
                        .toList(),
                    onChanged: (val) {
                      setStateDialog(() => selectedEntityId = val);
                      if (val != null) {
                        final supplier = _suppliers.firstWhere((s) => s['id'] == val);
                        phoneCtrl.text = supplier['phone'] ?? '';
                        loadBalance(setStateDialog, 'Supplier', val);
                      }
                    },
                  )
                else if (entityType == 'Worker')
                  DropdownButtonFormField<int>(
                    value: selectedEntityId,
                    hint: Text(Localization.translate('اختر العامل', lang),
                        style: const TextStyle(fontFamily: 'Cairo')),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: _workers
                        .map((w) => DropdownMenuItem<int>(
                              value: w['id'] as int,
                              child: Text(
                                w['name']?.toString() ?? '-',
                                style: const TextStyle(fontFamily: 'Cairo'),
                              ),
                            ))
                        .toList(),
                    onChanged: (val) {
                      setStateDialog(() => selectedEntityId = val);
                      if (val != null) {
                        loadBalance(setStateDialog, 'Worker', val);
                      }
                    },
                  ),

                const SizedBox(height: 10),

                if (entityType != 'General')
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: Localization.translate('رقم الهاتف', lang),
                      prefixIcon: const Icon(Icons.phone),
                      border: const OutlineInputBorder(),
                    ),
                  ),

                const SizedBox(height: 10),

                if (entityType != 'General' && selectedEntityId != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey.shade900
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: loadingBalance
                        ? const Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                Localization.translate('الرصيد القديم:', lang),
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                              Text(
                                '${NumberFormat('#,##0.00').format(oldBalance.abs())} د.ج'
                                '  (${oldBalance >= 0 ? Localization.translate("مدين", lang) : Localization.translate("دائن", lang)})',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  color: oldBalance > 0
                                      ? Colors.orange.shade800
                                      : Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                  ),

                const SizedBox(height: 10),

                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: Localization.translate('المبلغ (د.ج)', lang),
                    prefixIcon: const Icon(Icons.attach_money),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => recalcNewBalance(setStateDialog),
                ),

                const SizedBox(height: 10),

                if (entityType != 'General' && selectedEntityId != null && amountCtrl.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: newBalance <= 0
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: newBalance <= 0
                            ? Colors.green.shade300
                            : Colors.orange.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          Localization.translate('الرصيد الجديد:', lang),
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        Text(
                          '${NumberFormat('#,##0.00').format(newBalance.abs())} د.ج'
                          '  (${newBalance >= 0 ? Localization.translate("مدين", lang) : Localization.translate("دائن", lang)})',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            color: newBalance > 0
                                ? Colors.orange.shade800
                                : Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _caisseNames.contains(selectedCaisse) ? selectedCaisse : (_caisseNames.isNotEmpty ? _caisseNames.first : null),
                  decoration: InputDecoration(
                    labelText: Localization.translate('اختر الصندوق', lang),
                    border: const OutlineInputBorder(),
                  ),
                  items: _caisseNames
                      .map((name) => DropdownMenuItem<String>(
                            value: name,
                            child: Text(
                              Localization.translate(name, lang),
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setStateDialog(() => selectedCaisse = val!);
                  },
                ),

                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: selectedPaymentMethod,
                  decoration: InputDecoration(
                    labelText: Localization.translate('طريقة الدفع', lang),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    'نقداً / Espèce',
                    'شيك / Chèque',
                    'شيك مصدق / Chèque de banque',
                    'تحويل بنكي / Virement',
                    'بطاقة بنكية / CIB',
                    'CCP / حساب جاري',
                    'بريدي موب / BaridiMob',
                  ]
                      .map((method) => DropdownMenuItem<String>(
                            value: method,
                            child: Text(
                              method,
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (val) {
                    setStateDialog(() => selectedPaymentMethod = val!);
                  },
                ),

                const SizedBox(height: 10),

                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (date != null && mounted) {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(selectedDate),
                      );
                      if (time != null) {
                        setStateDialog(() {
                          selectedDate = DateTime(date.year, date.month,
                              date.day, time.hour, time.minute);
                        });
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18, color: Colors.teal),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('dd/MM/yyyy  HH:mm').format(selectedDate),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: Localization.translate('البيان / السبب', lang),
                    prefixIcon: const Icon(Icons.notes),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('إلغاء', lang), style: const TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save, color: Colors.white),
              onPressed: () async {
                final amountText = amountCtrl.text.trim();
                if (amountText.isEmpty) return;
                final amount = double.tryParse(amountText) ?? 0.0;
                if (amount <= 0) return;

                final settings = Provider.of<AppSettingsProvider>(context, listen: false);
                final String userName = settings.userDisplayName;

                String finalDesc = descCtrl.text.trim();
                if (entityType == 'Client' && selectedEntityId != null) {
                  final client = _clients.firstWhere((c) => c['id'] == selectedEntityId);
                  finalDesc = 'من الزبون: ${client['firstname']} ${client['lastname']}'
                      '${finalDesc.isNotEmpty ? ' - $finalDesc' : ''}';
                } else if (entityType == 'Supplier' && selectedEntityId != null) {
                  final supplier = _suppliers.firstWhere((s) => s['id'] == selectedEntityId);
                  finalDesc = '${type == 'Encaissement' ? 'استرجاع من المورد' : 'للمورد'}: ${supplier['name']}'
                      '${finalDesc.isNotEmpty ? ' - $finalDesc' : ''}';
                } else if (entityType == 'Worker' && selectedEntityId != null) {
                  final worker = _workers.firstWhere((w) => w['id'] == selectedEntityId);
                  finalDesc = 'إلى العامل: ${worker['name']}'
                      '${finalDesc.isNotEmpty ? ' - $finalDesc' : ''}';
                }

                final calcNewBalance = entityType == 'General'
                    ? 0.0
                    : (type == 'Encaissement'
                        ? oldBalance - amount
                        : oldBalance + amount);

                await widget.db.insertTreasury(
                  type,
                  amount,
                  finalDesc,
                  entityType: entityType,
                  entityId: selectedEntityId,
                  phone: phoneCtrl.text.trim(),
                  oldBalance: entityType == 'General' ? 0.0 : oldBalance,
                  newBalance: calcNewBalance,
                  recordedBy: userName,
                  caisseName: selectedCaisse,
                  paymentMethod: selectedPaymentMethod,
                  createdAt: selectedDate.toIso8601String(),
                );

                if (mounted) {
                  Navigator.pop(context);
                  _loadData();
                }
              },
              label: Text(Localization.translate('حفظ', lang), style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<AppSettingsProvider>(context);
    final lang = settingsProvider.language;
    final currency = Localization.translate('د.ج', lang);
    final formatter = NumberFormat('#,##0.00');

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate('الخزينة (Caisse)', lang),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.teal,
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.search_off : Icons.search),
            tooltip: Localization.translate('بحث', lang),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
              });
            },
          ),
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_alt_off : Icons.filter_alt),
            tooltip: Localization.translate('فلترة', lang),
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 1. شريط الصندوق المثبت في الأعلى
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade900 : Colors.teal.shade50,
                    border: Border(bottom: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.teal.shade100, width: 1)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedCaisse,
                            isExpanded: true,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              color: isDark ? Colors.tealAccent : Colors.teal,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            items: [
                              DropdownMenuItem<String>(
                                value: 'الكل',
                                child: Text(Localization.translate('الكل (جميع الصناديق)', lang), style: const TextStyle(fontFamily: 'Cairo')),
                              ),
                              ..._caisseNames.map((name) => DropdownMenuItem<String>(
                                    value: name,
                                    child: Text(Localization.translate(name, lang), style: const TextStyle(fontFamily: 'Cairo')),
                                  )),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _selectedCaisse = val!;
                                _loadData();
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.tealAccent.shade700 : Colors.teal,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${formatter.format(_totalBalance)} $currency',
                          style: TextStyle(
                            color: isDark ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (settingsProvider.canManageCaisses())
                        IconButton(
                          icon: Icon(Icons.settings, size: 20, color: isDark ? Colors.tealAccent : Colors.teal),
                          tooltip: Localization.translate('إدارة الصناديق', lang),
                          onPressed: _showManageCaissesDialog,
                        ),
                    ],
                  ),
                ),

                // 🟢 حقل البحث التفاعلي (يظهر ويختفي بناءً على الأيقونة في الأب بار)
                if (_showSearch)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: Localization.translate('بحث بالاسم أو البيان', lang),
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                          _applyFilter();
                        });
                      },
                    ),
                  ),

                // 🟢 خيارات الفلترة المتقدمة (تظهر وتختفي بناءً على الأيقونة في الأب بار)
                if (_showFilters)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 175,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _selectedTypeFilter,
                              decoration: InputDecoration(
                                labelText: Localization.translate('نوع المعاملة', lang),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text(
                                    Localization.translate('الكل', lang),
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'income',
                                  child: Text(
                                    Localization.translate('مقبوضات', lang),
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'expense',
                                  child: Text(
                                    Localization.translate('مدفوعات', lang),
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedTypeFilter = val!;
                                  _applyFilter();
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 175,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _selectedCategoryFilter,
                              decoration: InputDecoration(
                                labelText: Localization.translate('التصنيف', lang),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text(
                                    Localization.translate('كلها', lang),
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'general_expenses',
                                  child: Text(
                                    Localization.translate('تكاليف إضافية / مصاريف عامة', lang),
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedCategoryFilter = val!;
                                  _applyFilter();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 🟢 كرت المجموع المصفى التلقائي (يظهر فقط عند التصفية أو البحث النشط)
                if (_selectedTypeFilter != 'all' || _selectedCategoryFilter != 'all' || _searchQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.teal.withValues(alpha: 0.15) : Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.teal.shade800 : Colors.teal.shade100,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            Localization.translate('إجمالي المصفى:', lang),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.tealAccent : Colors.teal.shade900,
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (_filteredTotalIncome > 0)
                                Text(
                                  '${Localization.translate('المقبوضات:', lang)} +${formatter.format(_filteredTotalIncome)} $currency',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              if (_filteredTotalExpense > 0)
                                Text(
                                  '${Localization.translate('المدفوعات:', lang)} -${formatter.format(_filteredTotalExpense)} $currency',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              Text(
                                '${Localization.translate('الصافي:', lang)} ${formatter.format(_filteredTotalIncome - _filteredTotalExpense)} $currency',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: (_filteredTotalIncome - _filteredTotalExpense) >= 0
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                // 2. القائمة الرئيسية القابلة للتمرير بالكامل
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredTransactions.length + 1, // +1 for big balance card
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isDark
                                  ? [Colors.teal.shade900, Colors.grey.shade900]
                                  : [Colors.teal, Colors.green],
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                Localization.translate('رصيد الصندوق', lang),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${formatter.format(_totalBalance)} $currency',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final item = _filteredTransactions[index - 1];
                      final tType = item['transaction_type']?.toString() ?? '';
                      final isIncome = tType == 'Encaissement' ||
                          tType == 'income' ||
                          (!tType.contains('Achat') &&
                              !tType.contains('Purchase') &&
                              !tType.contains('Décaissement') &&
                              !tType.contains('expense'));

                      String dateStr = item['created_at'] ?? '';
                      if (dateStr.length > 16) {
                        dateStr = dateStr.substring(0, 16).replaceFirst('T', ' ');
                      }

                      final oldBal = (item['old_balance'] as num?)?.toDouble();
                      final newBal = (item['new_balance'] as num?)?.toDouble();
                      final phone = item['phone']?.toString() ?? '';

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Row 1: Icon and Title
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: isIncome
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : Colors.red.withValues(alpha: 0.15),
                                    child: Icon(
                                      isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                                      color: isIncome ? Colors.green : Colors.red,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _highlightText(
                                      _buildTransactionTitle(item, lang),
                                      _searchQuery,
                                      TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Row 2: Paid Amount in its own row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    Localization.translate('المبلغ:', lang) + ' / Montant:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white60 : Colors.grey,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  Text(
                                    '${isIncome ? "+" : "-"}${formatter.format((item['amount'] as num?)?.toDouble() ?? 0)} $currency',
                                    style: TextStyle(
                                      color: isIncome ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              if (phone.isNotEmpty) ...[
                                Row(
                                  children: [
                                    const Text('📞 ', style: TextStyle(fontSize: 11)),
                                    Expanded(
                                      child: _highlightText(
                                        phone,
                                        _searchQuery,
                                        const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                              ],

                              if (oldBal != null && newBal != null && item['entity_type'] != 'General') ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    '${Localization.translate("الرصيد", lang)}: ${formatter.format(oldBal.abs())} → ${formatter.format(newBal.abs())} $currency',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                              ],

                              // Row 3: Metadata
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    '${Localization.translate('بواسطة', lang)}: ${item['recorded_by'] ?? ''} | $dateStr',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.inbox, size: 10, color: Colors.teal),
                                        const SizedBox(width: 3),
                                        Text(
                                          t(item['caisse_name']?.toString() ?? 'الصندوق الرئيسي'),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isDark ? Colors.tealAccent : Colors.teal,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.payment, size: 10, color: Colors.blue),
                                        const SizedBox(width: 3),
                                        Text(
                                          t(item['payment_method']?.toString() ?? 'نقداً / Espèce'),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isDark ? Colors.blueAccent : Colors.blue,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 16),

                              // Row 4: Action Print options button in its own row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: isDark ? Colors.tealAccent : Colors.teal,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        side: BorderSide(color: isDark ? Colors.tealAccent : Colors.teal),
                                      ),
                                    ),
                                    icon: const Icon(Icons.print, size: 14),
                                    label: Text(
                                      Localization.translate('خيارات الوصل', lang),
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: () => _showReceiptOptions(context, item),
                                  ),
                                ],
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTransactionDialog,
        backgroundColor: isDark ? Colors.black : Colors.teal,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: isDark ? const BorderSide(color: Colors.white, width: 1.5) : BorderSide.none,
        ),
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          Localization.translate('معاملة جديدة', lang),
          style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
        ),
      ),
    );
  }

  String _buildTransactionTitle(Map<String, dynamic> item, AppLanguage lang) {
    final desc = item['description']?.toString() ?? '';
    if (desc.startsWith('دفعة لطلبية رقم ')) {
      final orderId = desc.replaceFirst('دفعة لطلبية رقم ', '');
      return '${Localization.translate('دفعة لطلبية', lang)} ${Localization.translate('رقم', lang)} $orderId';
    }
    if (desc.startsWith('من الزبون: ')) {
      return '${Localization.translate('من الزبون', lang)}: ${desc.replaceFirst('من الزبون: ', '')}';
    }
    if (desc.startsWith('للمورد: ')) {
      return '${Localization.translate('للمورد', lang)}: ${desc.replaceFirst('للمورد: ', '')}';
    }
    if (desc.startsWith('استرجاع من المورد: ')) {
      return '${Localization.translate('استرجاع من المورد', lang)}: ${desc.replaceFirst('استرجاع من المورد: ', '')}';
    }
    if (desc.startsWith('إلى العامل: ')) {
      return '${Localization.translate('إلى العامل', lang)}: ${desc.replaceFirst('إلى العامل: ', '')}';
    }
    if (desc.startsWith('دفع للمورد الفاتورة')) {
      return desc.replaceFirst('دفع للمورد الفاتورة', Localization.translate('دفع للمورد الفاتورة', lang));
    }
    if (desc.startsWith('دفع للمورد الفاتوره')) {
      return desc.replaceFirst('دفع للمورد الفاتوره', Localization.translate('دفع للمورد الفاتورة', lang));
    }
    if (desc.startsWith('دفع للمورد: ')) {
      final content = desc.replaceFirst('دفع للمورد: ', '');
      if (content.contains(' - الفاتورة: ')) {
        final parts = content.split(' - الفاتورة: ');
        final supplier = parts[0];
        final inv = parts[1];
        return '${Localization.translate('دفع للمورد:', lang)} $supplier - ${Localization.translate('رقم الفاتورة', lang)}: $inv';
      }
      return '${Localization.translate('دفع للمورد:', lang)} $content';
    }
    if (desc.startsWith('دفع للمورد:')) {
      return desc.replaceFirst('دفع للمورد:', '${Localization.translate('دفع للمورد:', lang)}');
    }
    if (desc.startsWith('دفع للمورد فاتورة رقم')) {
      return desc.replaceFirst('دفع للمورد فاتورة رقم', Localization.translate('دفع للمورد فاتورة رقم', lang));
    }
    return desc.isEmpty ? Localization.translate('بدون بيان', lang) : desc;
  }

  String t(String key) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    return Localization.translate(key, lang);
  }
}
