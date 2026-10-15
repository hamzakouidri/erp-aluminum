// ignore_for_file: deprecated_member_use

import 'dart:async';
// unused import removed
import 'dart:convert';

import 'package:database_data/widgets/app_material.dart';
import '../sql_database.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import 'package:intl/intl.dart';
import '../settings/localization.dart';
import '../services/cloud_sync_service.dart';
import 'receipt_pdf_service.dart';
import '../widgets/resizable_columns_table.dart';
import '../widgets/numeric_filter_search_field.dart';
import '../widgets/table_date_range_filter.dart';
import '../widgets/desktop_scroll_behavior.dart';

class TreasuryScreen extends StatefulWidget {
  static Future<void> showQuickTransactionDialog(
    BuildContext context, {
    SqlDatabase? db,
    String initialType = 'Encaissement',
    List<String>? caisseNames,
    List<Map<String, dynamic>>? clients,
    List<Map<String, dynamic>>? suppliers,
    List<Map<String, dynamic>>? workers,
    VoidCallback? onSaved,
  }) async {
    final effectiveDb = db ?? SqlDatabase();
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    final effectiveClients = clients ?? await effectiveDb.readClient();
    final effectiveSuppliers = suppliers ?? await effectiveDb.readSuppliers();
    final effectiveWorkers = workers ?? await effectiveDb.readEmployees();

    List<String> effectiveCaisseNames =
        caisseNames != null && caisseNames.isNotEmpty
        ? List<String>.from(caisseNames)
        : [];
    if (effectiveCaisseNames.isEmpty) {
      try {
        final caisses = await effectiveDb.readCaisses();
        effectiveCaisseNames = caisses
            .map((c) => (c['name'] ?? '').toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } catch (_) {}
    }
    if (effectiveCaisseNames.isEmpty) {
      effectiveCaisseNames = ['الصندوق الرئيسي'];
    }

    if (!context.mounted) return;

    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    String type = initialType;
    String entityType = initialType == 'Encaissement' ? 'Client' : 'Supplier';
    int? selectedEntityId;
    double oldBalance = 0.0;
    double newBalance = 0.0;
    bool loadingBalance = false;
    DateTime selectedDate = DateTime.now();
    String selectedCaisse = effectiveCaisseNames.first;
    String selectedPaymentMethod = 'نقداً / Espèce';

    Future<void> loadBalance(
      StateSetter setStateDialog,
      String eType,
      int eId,
    ) async {
      setStateDialog(() => loadingBalance = true);
      double bal = 0.0;
      if (eType == 'Client') {
        bal = await effectiveDb.getClientBalance(eId);
      } else if (eType == 'Supplier') {
        bal = await effectiveDb.getSupplierBalance(eId);
      } else if (eType == 'Worker') {
        bal = await effectiveDb.getWorkerBalance(eId);
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

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final dialogTitle = type == 'Encaissement'
              ? (lang == AppLanguage.french
                    ? 'Nouvel Encaissement (Caisse)'
                    : (lang == AppLanguage.english
                          ? 'New Income (Treasury)'
                          : 'قبض جديد / Encaissement'))
              : (lang == AppLanguage.french
                    ? 'Nouveau Décaissement (Caisse)'
                    : (lang == AppLanguage.english
                          ? 'New Expense (Treasury)'
                          : 'دفع جديد / Décaissement'));

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  type == 'Encaissement'
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: type == 'Encaissement' ? Colors.green : Colors.orange,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dialogTitle,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 500,
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: type,
                      decoration: InputDecoration(
                        labelText: Localization.translate('نوع المعاملة', lang),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'Encaissement',
                          child: Text(
                            Localization.translate('قبض / Encaissement', lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Décaissement',
                          child: Text(
                            Localization.translate('دفع / Décaissement', lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
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
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: entityType,
                      decoration: InputDecoration(
                        labelText: Localization.translate('نوع الجهة', lang),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items: [
                        if (type == 'Encaissement') ...[
                          DropdownMenuItem(
                            value: 'Client',
                            child: Text(
                              Localization.translate('زبون', lang),
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'Supplier',
                            child: Text(
                              Localization.translate('مورد (استرجاع)', lang),
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ] else ...[
                          DropdownMenuItem(
                            value: 'Supplier',
                            child: Text(
                              Localization.translate('مورد', lang),
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'Worker',
                            child: Text(
                              Localization.translate('عامل', lang),
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'General',
                            child: Text(
                              Localization.translate('مصاريف عامة', lang),
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
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
                    const SizedBox(height: 12),
                    if (entityType == 'Client') ...[
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: selectedEntityId,
                        hint: Text(
                          Localization.translate('اختر الزبون', lang),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                          ),
                        ),
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'اختر الزبون',
                            lang,
                          ),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: effectiveClients
                            .map(
                              (c) => DropdownMenuItem<int>(
                                value: c['id'] as int,
                                child: Text(
                                  '${c['firstname']} ${c['lastname']}',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          setStateDialog(() => selectedEntityId = val);
                          if (val != null) {
                            final client = effectiveClients.firstWhere(
                              (c) => c['id'] == val,
                            );
                            phoneCtrl.text = client['phone1'] ?? '';
                            loadBalance(setStateDialog, 'Client', val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                    ] else if (entityType == 'Supplier') ...[
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: selectedEntityId,
                        hint: Text(
                          Localization.translate('اختر المورد', lang),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                          ),
                        ),
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'اختر المورد',
                            lang,
                          ),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: effectiveSuppliers
                            .map(
                              (s) => DropdownMenuItem<int>(
                                value: s['id'] as int,
                                child: Text(
                                  s['name']?.toString() ?? '-',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          setStateDialog(() => selectedEntityId = val);
                          if (val != null) {
                            final supplier = effectiveSuppliers.firstWhere(
                              (s) => s['id'] == val,
                            );
                            phoneCtrl.text = supplier['phone'] ?? '';
                            loadBalance(setStateDialog, 'Supplier', val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                    ] else if (entityType == 'Worker') ...[
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: selectedEntityId,
                        hint: Text(
                          Localization.translate('اختر العامل', lang),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                          ),
                        ),
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'اختر العامل',
                            lang,
                          ),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: effectiveWorkers
                            .map(
                              (w) => DropdownMenuItem<int>(
                                value: w['id'] as int,
                                child: Text(
                                  w['name']?.toString() ?? '-',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          setStateDialog(() => selectedEntityId = val);
                          if (val != null) {
                            loadBalance(setStateDialog, 'Worker', val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (entityType != 'General') ...[
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: Localization.translate('رقم الهاتف', lang),
                          prefixIcon: const Icon(Icons.phone),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (loadingBalance)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (entityType != 'General' &&
                        selectedEntityId != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: oldBalance <= 0
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: oldBalance <= 0
                                ? Colors.green.shade300
                                : Colors.orange.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              Localization.translate('الرصيد السابق:', lang),
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                '${NumberFormat('#,##0.00').format(oldBalance.abs())} د.ج'
                                '  (${oldBalance >= 0 ? Localization.translate("مدين", lang) : Localization.translate("دائن", lang)})',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: oldBalance > 0
                                      ? Colors.orange.shade800
                                      : Colors.green.shade700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: Localization.translate('المبلغ (د.ج)', lang),
                        prefixIcon: const Icon(Icons.attach_money),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (_) => recalcNewBalance(setStateDialog),
                    ),
                    const SizedBox(height: 12),
                    if (entityType != 'General' &&
                        selectedEntityId != null &&
                        amountCtrl.text.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
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
                                fontSize: 13,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                '${NumberFormat('#,##0.00').format(newBalance.abs())} د.ج'
                                '  (${newBalance >= 0 ? Localization.translate("مدين", lang) : Localization.translate("دائن", lang)})',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: newBalance > 0
                                      ? Colors.orange.shade800
                                      : Colors.green.shade700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: effectiveCaisseNames.contains(selectedCaisse)
                          ? selectedCaisse
                          : effectiveCaisseNames.first,
                      decoration: InputDecoration(
                        labelText: Localization.translate('الصندوق', lang),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items: effectiveCaisseNames
                          .map(
                            (caisse) => DropdownMenuItem<String>(
                              value: caisse,
                              child: Text(
                                caisse,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setStateDialog(() => selectedCaisse = val!);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: selectedPaymentMethod,
                      decoration: InputDecoration(
                        labelText: Localization.translate('طريقة الدفع', lang),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items:
                          [
                                'نقداً / Espèce',
                                'شيك / Chèque',
                                'تحويل بنكي / Virement',
                                'بريدي موب / BaridiMob',
                                'أخرى / Autre',
                              ]
                              .map(
                                (method) => DropdownMenuItem<String>(
                                  value: method,
                                  child: Text(
                                    method,
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (val) {
                        setStateDialog(() => selectedPaymentMethod = val!);
                      },
                    ),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (ctx) {
                        final canChangeDate = Provider.of<AppSettingsProvider>(
                          context,
                          listen: false,
                        ).canChangePaymentDates();
                        return InkWell(
                          onTap: canChangeDate
                              ? () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: selectedDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (date != null && context.mounted) {
                                    final time = await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay.fromDateTime(
                                        selectedDate,
                                      ),
                                    );
                                    if (time != null) {
                                      setStateDialog(() {
                                        selectedDate = DateTime(
                                          date.year,
                                          date.month,
                                          date.day,
                                          time.hour,
                                          time.minute,
                                        );
                                      });
                                    }
                                  }
                                }
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 18,
                                  color: canChangeDate
                                      ? Colors.teal
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat(
                                    'dd/MM/yyyy  HH:mm',
                                  ).format(selectedDate),
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    color: canChangeDate ? null : Colors.grey,
                                  ),
                                ),
                                if (!canChangeDate) ...[
                                  const Spacer(),
                                  const Icon(
                                    Icons.lock,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'البيان / السبب',
                          lang,
                        ),
                        prefixIcon: const Icon(Icons.notes),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  Localization.translate('إلغاء', lang),
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save, color: Colors.white),
                onPressed: () async {
                  final amountText = amountCtrl.text.trim();
                  if (amountText.isEmpty) return;
                  final amount = double.tryParse(amountText) ?? 0.0;
                  if (amount <= 0) return;

                  final settings = Provider.of<AppSettingsProvider>(
                    context,
                    listen: false,
                  );
                  final String userName = settings.userDisplayName;

                  String finalDesc = descCtrl.text.trim();
                  if (entityType == 'Client' && selectedEntityId != null) {
                    final client = effectiveClients.firstWhere(
                      (c) => c['id'] == selectedEntityId,
                    );
                    finalDesc =
                        'من الزبون: ${client['firstname']} ${client['lastname']}'
                        '${finalDesc.isNotEmpty ? ' - $finalDesc' : ''}';
                  } else if (entityType == 'Supplier' &&
                      selectedEntityId != null) {
                    final supplier = effectiveSuppliers.firstWhere(
                      (s) => s['id'] == selectedEntityId,
                    );
                    finalDesc =
                        '${type == 'Encaissement' ? 'استرجاع من المورد' : 'للمورد'}: ${supplier['name']}'
                        '${finalDesc.isNotEmpty ? ' - $finalDesc' : ''}';
                  } else if (entityType == 'Worker' &&
                      selectedEntityId != null) {
                    final worker = effectiveWorkers.firstWhere(
                      (w) => w['id'] == selectedEntityId,
                    );
                    finalDesc =
                        'إلى العامل: ${worker['name']}'
                        '${finalDesc.isNotEmpty ? ' - $finalDesc' : ''}';
                  }

                  final calcNewBalance = entityType == 'General'
                      ? 0.0
                      : (type == 'Encaissement'
                            ? oldBalance - amount
                            : oldBalance + amount);

                  await effectiveDb.insertTreasury(
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

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          type == 'Encaissement'
                              ? (lang == AppLanguage.french
                                    ? 'Encaissement enregistré avec succès'
                                    : (lang == AppLanguage.english
                                          ? 'Income recorded successfully'
                                          : 'تم تسجيل القبض بنجاح'))
                              : (lang == AppLanguage.french
                                    ? 'Décaissement enregistré avec succès'
                                    : (lang == AppLanguage.english
                                          ? 'Expense recorded successfully'
                                          : 'تم تسجيل الدفع بنجاح')),
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                        backgroundColor: type == 'Encaissement'
                            ? Colors.green
                            : Colors.orange.shade800,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    onSaved?.call();
                  }
                },
                label: Text(
                  Localization.translate('حفظ', lang),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: type == 'Encaissement'
                      ? Colors.green
                      : Colors.teal,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  final SqlDatabase db;

  /// وضع العرض فقط — يخفي أزرار الإضافة والحذف
  final bool readOnly;
  final int? initialTransactionId;

  /// When true, workshop cashboxes and their movements are never loaded.
  final bool storeOnly;

  const TreasuryScreen({
    super.key,
    required this.db,
    this.readOnly = false,
    this.initialTransactionId,
    this.storeOnly = false,
  });

  static const Map<int, int> _unicodeToWin1252 = <int, int>{
    0x20AC: 0x80,
    0x201A: 0x82,
    0x0192: 0x83,
    0x201E: 0x84,
    0x2026: 0x85,
    0x2020: 0x86,
    0x2021: 0x87,
    0x02C6: 0x88,
    0x2030: 0x89,
    0x0160: 0x8A,
    0x2039: 0x8B,
    0x0152: 0x8C,
    0x017D: 0x8E,
    0x2018: 0x91,
    0x2019: 0x92,
    0x201C: 0x93,
    0x201D: 0x94,
    0x2022: 0x95,
    0x2013: 0x96,
    0x2014: 0x97,
    0x02DC: 0x98,
    0x2122: 0x99,
    0x0161: 0x9A,
    0x203A: 0x9B,
    0x0153: 0x9C,
    0x017E: 0x9E,
    0x0178: 0x9F,
  };

  bool _isIncomeTransaction(Map<String, dynamic> item) {
    final entityType =
        item['entity_type']?.toString().toLowerCase().trim() ?? '';
    if (entityType == 'worker') return false;

    final type =
        item['transaction_type']?.toString().toLowerCase().trim() ?? '';
    if (type == 'encaissement' || type == 'income') return true;
    if (type.contains('achat') ||
        type.contains('purchase') ||
        type.contains('décaissement') ||
        type.contains('dã©caissement') ||
        type.contains('decaissement') ||
        type.contains('expense')) {
      return false;
    }
    return true;
  }

  String _transactionRelation(Map<String, dynamic> item, AppLanguage lang) {
    final entityType = item['entity_type']?.toString().toLowerCase() ?? '';
    final description = item['description']?.toString().toLowerCase() ?? '';
    final isIncome = _isIncomeTransaction(item);

    if (entityType == 'client') {
      return Localization.translate('دفعة مرتبطة بطلبية زبون', lang);
    }
    if (entityType == 'supplier') {
      return Localization.translate(
        isIncome ? 'إرجاع من المورد' : 'دفع للمورد / فاتورة شراء',
        lang,
      );
    }
    if (entityType == 'worker') {
      final isSettlement =
          description.contains('تسوية') ||
          description.contains('weekly') ||
          description.contains('hebdomadaire');
      return Localization.translate(
        isSettlement ? 'تسوية أسبوعية للعامل' : 'دفع للعامل',
        lang,
      );
    }
    if (entityType == 'general') {
      return Localization.translate('مصروف عام غير مرتبط بفاتورة', lang);
    }
    if (item['reference_id'] != null) {
      return Localization.translate('عملية مرتبطة بمرجع', lang);
    }
    return Localization.translate('عملية مستقلة', lang);
  }

  String _transactionDate(Map<String, dynamic> item) {
    final raw = item['created_at']?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? raw : DateFormat('dd/MM/yyyy HH:mm').format(parsed);
  }

  String _readableText(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty ||
        (!text.contains('Ø') &&
            !text.contains('Ã') &&
            !text.contains('Â') &&
            !text.contains('Ù'))) {
      return text;
    }
    try {
      final bytes = <int>[];
      for (final rune in text.runes) {
        if (rune <= 0xFF) {
          bytes.add(rune);
        } else if (_unicodeToWin1252.containsKey(rune)) {
          bytes.add(_unicodeToWin1252[rune]!);
        } else {
          return text;
        }
      }
      final repaired = utf8.decode(bytes, allowMalformed: false);
      return repaired.contains('�') ? text : repaired;
    } catch (_) {
      return text;
    }
  }

  DataCell _desktopTableCell(
    String value, {
    required double width,
    required Color color,
    bool bold = false,
  }) {
    return DataCell(
      SizedBox(
        width: width,
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            color: color,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Future<void> _showTreasuryRowContextMenu(
    BuildContext context,
    Offset position,
    Map<String, dynamic> item,
    AppLanguage lang, {
    required bool readOnly,
    required bool canEditPayments,
    required bool canDeletePayments,
    required ValueChanged<Map<String, dynamic>> onEdit,
    required ValueChanged<Map<String, dynamic>> onDelete,
    required ValueChanged<Map<String, dynamic>> onOpen,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlay.globalToLocal(position);
    final x = local.dx.clamp(8.0, overlay.size.width - 8.0).toDouble();
    final y = local.dy.clamp(8.0, overlay.size.height - 8.0).toDouble();
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        x,
        y,
        overlay.size.width - x,
        overlay.size.height - y,
      ),
      items: [
        _treasuryContextMenuItem('open', Icons.open_in_new_rounded,
            Localization.translate('فتح', lang)),
        if (!readOnly && canEditPayments)
          _treasuryContextMenuItem('edit', Icons.edit_outlined,
              Localization.translate('تعديل المعاملة', lang)),
        _treasuryContextMenuItem('print', Icons.print_outlined,
            Localization.translate('طباعة الوصل', lang)),
        _treasuryContextMenuItem('share', Icons.share_outlined,
            Localization.translate('مشاركة', lang)),
        _treasuryContextMenuItem('save', Icons.download_outlined,
            Localization.translate('حفظ الوصل', lang)),
        if (!readOnly && canDeletePayments)
          _treasuryContextMenuItem('delete', Icons.delete_outline,
              Localization.translate('حذف المعاملة', lang),
              color: Colors.red),
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'open':
        onOpen(item);
        return;
      case 'edit':
        onEdit(item);
        return;
      case 'print':
        await ReceiptPdfService.printReceiptWithFeedback(item, context);
        return;
      case 'share':
        await ReceiptPdfService.shareReceiptWithFeedback(item, context);
        return;
      case 'save':
        await ReceiptPdfService.saveReceiptWithFeedback(item, context);
        return;
      case 'delete':
        onDelete(item);
        return;
    }
  }

  PopupMenuItem<String> _treasuryContextMenuItem(
    String value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 19, color: color),
        title: Text(label, style: TextStyle(fontFamily: 'Cairo', color: color)),
      ),
    );
  }

  Widget _buildDesktopTreasuryTable(
    BuildContext context,
    AppLanguage lang,
    NumberFormat formatter,
    String currency,
    bool isDark,
    List<Map<String, dynamic>> transactions,
    double filteredTotalIncome,
    double filteredTotalExpense,
    bool readOnly,
    bool canEditPayments,
    bool canDeletePayments,
    ScrollController horizontalScrollController,
    ValueChanged<Map<String, dynamic>> onEdit,
    ValueChanged<Map<String, dynamic>> onDelete,
    ValueChanged<Map<String, dynamic>> onReceipt, {
    required int? highlightedTransactionId,
    required ValueChanged<Map<String, dynamic>> onHighlightedTap,
    required TableDateRange dateRange,
    required ValueChanged<TableDateRange> onDateRangeChanged,
    required NumericFilterState numericFilter,
    required ValueChanged<NumericFilterState> onNumericFilterChanged,
    required Map<String, TextEditingController> columnControllers,
    required Map<String, NumericFilterState> columnNumericFilters,
    required String Function(Map<String, dynamic>) payerNameForTransaction,
    required VoidCallback onFiltersUpdated,
    required VoidCallback onClearAllFilters,
    required ScrollController verticalScrollController,
  }) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.white70 : Colors.black54;
    final headerColor = isDark ? Colors.teal.shade900 : Colors.teal.shade50;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.teal.shade100;

    final hasActiveColumnFilters =
        dateRange.isActive ||
        numericFilter.isActive ||
        columnNumericFilters.values.any((f) => f.isActive) ||
        columnControllers.values.any((c) => c.text.trim().isNotEmpty);

    final columns = [
      ResizableTableColumn(
        id: 'date',
        label: Text(
          Localization.translate('التاريخ', lang),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        filter: CompactTableFilterField(
          key: const ValueKey('compact_filter_date'),
          height: 34,
          hintText: Localization.translate('تاريخ...', lang),
          controller: columnControllers['date'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 220,
      ),
      ResizableTableColumn(
        id: 'entered_by',
        label: Text(
          Localization.translate('أدخلها', lang),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        filter: CompactTableFilterField(
          key: const ValueKey('compact_filter_entered_by'),
          height: 34,
          hintText: Localization.translate('المُدخل...', lang),
          controller: columnControllers['entered_by'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 125,
        minWidth: 85,
        maxWidth: 220,
      ),
      ResizableTableColumn(
        id: 'payer_name',
        label: Text(
          Localization.translate('اسم الدافع', lang),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        filter: CompactTableFilterField(
          key: const ValueKey('compact_filter_payer_name'),
          height: 34,
          hintText: Localization.translate('اسم الدافع...', lang),
          controller: columnControllers['payer_name'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 150,
        minWidth: 100,
        maxWidth: 280,
      ),
      ResizableTableColumn(
        id: 'type',
        label: Text(
          Localization.translate('نوع العملية', lang),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        filter: CompactTableFilterField(
          key: const ValueKey('compact_filter_type'),
          height: 34,
          hintText: Localization.translate('النوع...', lang),
          controller: columnControllers['type'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 115,
        minWidth: 85,
        maxWidth: 190,
      ),
      ResizableTableColumn(
        id: 'relation',
        label: Text(
          Localization.translate('الارتباط', lang),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        filter: CompactTableFilterField(
          key: const ValueKey('compact_filter_relation'),
          height: 34,
          hintText: Localization.translate('الارتباط...', lang),
          controller: columnControllers['relation'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 190,
        minWidth: 120,
        maxWidth: 360,
      ),
      ResizableTableColumn(
        id: 'method',
        label: Text(
          Localization.translate('طريقة الدفع', lang),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        filter: CompactTableFilterField(
          key: const ValueKey('compact_filter_method'),
          height: 34,
          hintText: Localization.translate('طريقة الدفع...', lang),
          controller: columnControllers['method'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 145,
        minWidth: 100,
        maxWidth: 250,
      ),
      ResizableTableColumn(
        id: 'desc',
        label: Text(
          Localization.translate('البيان', lang),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        filter: CompactTableFilterField(
          key: const ValueKey('compact_filter_desc'),
          height: 34,
          hintText: Localization.translate('البيان...', lang),
          controller: columnControllers['desc'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 260,
        minWidth: 140,
        maxWidth: 600,
      ),
      ResizableTableColumn(
        id: 'income',
        label: Text(
          Localization.translate('الدفع', lang),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
        filter: CompactTableFilterField(
          key: const ValueKey('compact_filter_income'),
          height: 34,
          hintText: Localization.translate('الدفع...', lang),
          controller: columnControllers['income'],
          isNumeric: true,
          lang: lang,
          initialNumericState:
              columnNumericFilters['income'] ?? const NumericFilterState(),
          onNumericFilterChanged: (f) {
            columnNumericFilters['income'] = f;
            onFiltersUpdated();
          },
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 240,
      ),
      ResizableTableColumn(
        id: 'expense',
        label: Text(
          Localization.translate('السحب', lang),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        filter: CompactTableFilterField(
          key: const ValueKey('compact_filter_expense'),
          height: 34,
          hintText: Localization.translate('السحب...', lang),
          controller: columnControllers['expense'],
          isNumeric: true,
          lang: lang,
          initialNumericState:
              columnNumericFilters['expense'] ?? const NumericFilterState(),
          onNumericFilterChanged: (f) {
            columnNumericFilters['expense'] = f;
            onFiltersUpdated();
          },
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 240,
      ),
      ResizableTableColumn(
        id: 'caisse',
        label: Text(
          Localization.translate('الصندوق', lang),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        filter: CompactTableFilterField(
          key: const ValueKey('compact_filter_caisse'),
          height: 34,
          hintText: Localization.translate('الصندوق...', lang),
          controller: columnControllers['caisse'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 135,
        minWidth: 90,
        maxWidth: 230,
      ),
      ResizableTableColumn(
        id: 'receipt',
        label: Text(
          Localization.translate('الإيصال', lang),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        initialWidth: 85,
        minWidth: 65,
        maxWidth: 130,
      ),
      ResizableTableColumn(
        id: 'actions',
        label: Text(
          Localization.translate('الإجراءات', lang),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        filter: hasActiveColumnFilters
            ? Center(
                child: InkWell(
                  onTap: onClearAllFilters,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.clear_all,
                          size: 13,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          Localization.translate('مسح', lang),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        initialWidth: 105,
        minWidth: 85,
        maxWidth: 160,
      ),
    ];

    final rows = transactions.map((item) {
      final isIncome = _isIncomeTransaction(item);
      final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
      final type = item['transaction_type']?.toString() ?? '';
      final recordedBy = item['recorded_by']?.toString().trim() ?? '';
      final payerName = payerNameForTransaction(item);
      final method = _readableText(item['payment_method']).trim();
      final cashbox = _readableText(item['caisse_name']).trim();
      final description = _readableText(item['description']).trim();

      return ResizableTableRow(
        reorderId: item['id'].toString(),
        color: highlightedTransactionId?.toString() == item['id'].toString()
            ? (isDark ? const Color(0xFF594B16) : const Color(0xFFFFF1A8))
            : null,
        onTap: () {
          if (highlightedTransactionId?.toString() == item['id'].toString()) {
            onHighlightedTap(item);
          }
          if (!readOnly && canEditPayments) {
            onEdit(item);
          } else {
            onReceipt(item);
          }
        },
        onSecondaryTapDown: (position) => _showTreasuryRowContextMenu(
          context,
          position,
          item,
          lang,
          readOnly: readOnly,
          canEditPayments: canEditPayments,
          canDeletePayments: canDeletePayments,
          onEdit: onEdit,
          onDelete: onDelete,
          onOpen: onReceipt,
        ),
        cells: [
          // Date
          Text(
            _transactionDate(item),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: mutedColor,
            ),
          ),
          // Entered by
          Text(
            recordedBy.isEmpty || recordedBy == 'system'
                ? Localization.translate('النظام', lang)
                : recordedBy,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              color: textColor,
            ),
          ),
          // Client who paid, or supplier/worker involved in the movement.
          Text(
            payerName.isEmpty
                ? Localization.translate('غير محدد', lang)
                : payerName,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              color: textColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          // Type
          Text(
            type.isEmpty
                ? (isIncome
                      ? Localization.translate('دفع', lang)
                      : Localization.translate('سحب', lang))
                : Localization.translate(type, lang),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
          // Relation
          Text(
            _transactionRelation(item, lang),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              color: textColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          // Method
          Text(
            method.isEmpty
                ? Localization.translate('نقداً / Espèce', lang)
                : Localization.translate(method, lang),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: textColor,
            ),
          ),
          // Description
          Text(
            description.isEmpty
                ? Localization.translate('بدون بيان', lang)
                : description,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: textColor,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          // Income
          Text(
            isIncome ? '${formatter.format(amount)} $currency' : '—',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isIncome ? Colors.green.shade700 : mutedColor,
            ),
          ),
          // Expense
          Text(
            isIncome ? '—' : '${formatter.format(amount)} $currency',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isIncome ? mutedColor : Colors.red.shade700,
            ),
          ),
          // Caisse
          Text(
            cashbox.isEmpty
                ? Localization.translate('الصندوق الرئيسي', lang)
                : Localization.translate(cashbox, lang),
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: textColor,
            ),
          ),
          // Receipt
          IconButton(
            tooltip: Localization.translate('خيارات الوصل', lang),
            icon: const Icon(Icons.receipt_long_outlined, size: 19),
            color: isDark ? Colors.tealAccent : Colors.teal,
            onPressed: () => onReceipt(item),
          ),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!readOnly && canEditPayments)
                IconButton(
                  tooltip: Localization.translate('تعديل المعاملة', lang),
                  icon: const Icon(Icons.edit_outlined, size: 19),
                  color: Colors.blue,
                  onPressed: () => onEdit(item),
                ),
              if (!readOnly && canDeletePayments)
                IconButton(
                  tooltip: Localization.translate('حذف المعاملة', lang),
                  icon: const Icon(Icons.delete_outline, size: 19),
                  color: Colors.red,
                  onPressed: () => onDelete(item),
                ),
            ],
          ),
        ],
      );
    }).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header Summary Bar ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.table_chart_rounded,
                      size: 20,
                      color: Colors.teal,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      Localization.translate('سجل عمليات الصندوق', lang),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: isDark
                            ? Colors.tealAccent
                            : Colors.teal.shade900,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${Localization.translate('الدفع', lang)}: ${formatter.format(filteredTotalIncome)} $currency   •   '
                  '${Localization.translate('السحب', lang)}: ${formatter.format(filteredTotalExpense)} $currency   •   '
                  '${Localization.translate('الرصيد', lang)}: ${formatter.format(filteredTotalIncome - filteredTotalExpense)} $currency',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),

          // ── Desktop Filters Bar (Date Range + Numeric Operator Search) ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 8,
              children: [
                // Date Range Filter Bar
                TableDateRangeFilterBar(
                  initialRange: dateRange,
                  lang: lang,
                  compact: true,
                  onRangeChanged: onDateRangeChanged,
                ),

                // Numeric Amount Search with Comparison Operators
                NumericFilterSearchField(
                  hintText: Localization.translate(
                    'بحث بالمبلغ (=, >, <, ≥, ≤, ≠)...',
                    lang,
                  ),
                  lang: lang,
                  initialState: numericFilter,
                  width: 300,
                  onFilterChanged: onNumericFilterChanged,
                ),
              ],
            ),
          ),

          // ── Resizable Desktop Table with zero vertical overflow ──
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: borderColor)),
              child: ResizableColumnsTable(
                persistenceKey: 'treasury',
                revealRowId: highlightedTransactionId?.toString(),
                headerMinHeight: 48,
                filterRowMinHeight: 42,
                rowMinHeight: 50,
                cellPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                emptyPlaceholder: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 32.0,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 52,
                          color: mutedColor,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          Localization.translate(
                            'لا توجد عمليات مطابقة لشروط الفلترة والبحث',
                            lang,
                          ),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: mutedColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          switch (lang) {
                            AppLanguage.french =>
                              'Modifiez directement les critères dans les champs visibles ci-dessus.',
                            AppLanguage.english =>
                              'Edit the criteria directly in the visible fields above.',
                            _ =>
                              'يمكنك تعديل كلمات البحث مباشرة في الحقول الظاهرة أعلاه',
                          },
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: mutedColor.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                footerCells: {
                  'income': Text(
                    transactions
                        .where(_isIncomeTransaction)
                        .fold<double>(
                          0,
                          (sum, row) =>
                              sum + ((row['amount'] as num?)?.toDouble() ?? 0),
                        )
                        .toStringAsFixed(2),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  'expense': Text(
                    transactions
                        .where((row) => !_isIncomeTransaction(row))
                        .fold<double>(
                          0,
                          (sum, row) =>
                              sum + ((row['amount'] as num?)?.toDouble() ?? 0),
                        )
                        .toStringAsFixed(2),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                },
                columns: columns,
                rows: rows,
                headerColor: headerColor,
                filterRowColor: isDark
                    ? const Color(0xFF1A1A26)
                    : const Color(0xFFF1F5F9),
                borderColor: borderColor,
                rowColor: isDark ? const Color(0xFF171721) : Colors.white,
                horizontalController: horizontalScrollController,
                verticalController: verticalScrollController,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  State<TreasuryScreen> createState() => _TreasuryScreenState();
}

class _TreasuryScreenState extends State<TreasuryScreen> {
  int? _highlightedTransactionId;
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
  TableDateRange _dateRange = const TableDateRange();
  NumericFilterState _numericFilter = const NumericFilterState();
  final Map<String, TextEditingController> _treasuryColumnControllers = {
    'date': TextEditingController(),
    'entered_by': TextEditingController(),
    'payer_name': TextEditingController(),
    'type': TextEditingController(),
    'relation': TextEditingController(),
    'method': TextEditingController(),
    'desc': TextEditingController(),
    'income': TextEditingController(),
    'expense': TextEditingController(),
    'caisse': TextEditingController(),
  };
  final Map<String, NumericFilterState> _treasuryNumericFilters = {};
  bool _showSearch = false;
  bool _showFilters = false;
  final ScrollController _desktopTableScrollController = ScrollController();
  final ScrollController _desktopTreasuryScrollController = ScrollController();
  final ScrollController _mobileTreasuryScrollController = ScrollController();

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _suppliers = [];
  StreamSubscription? _syncSub;

  bool _isStoreCaisseName(dynamic value) {
    final name = (value ?? '').toString().trim().toLowerCase();
    return name == 'صندوق المحل' ||
        name == 'caisse magasin' ||
        name.contains('المحل') ||
        name.contains('magasin') ||
        name.contains('store');
  }

  @override
  void initState() {
    super.initState();
    _highlightedTransactionId = widget.initialTransactionId;
    _loadData();
    _loadEntities();
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        _loadData(silent: true);
        _loadEntities();
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _desktopTableScrollController.dispose();
    _desktopTreasuryScrollController.dispose();
    _mobileTreasuryScrollController.dispose();
    for (final controller in _treasuryColumnControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEntities() async {
    final clients = widget.storeOnly
        ? await widget.db.readMaterialClients()
        : await widget.db.readClient();
    final workers = widget.storeOnly
        ? <Map<String, dynamic>>[]
        : await widget.db.readEmployees();
    final suppliers = await widget.db.readSuppliers();
    if (mounted) {
      setState(() {
        _clients = clients;
        _workers = workers;
        _suppliers = suppliers;
      });
    }
  }

  /// Resolve the client, supplier or worker attached to a treasury movement.
  /// The movement stores the entity type/id, while the display name remains
  /// in the corresponding local table.
  String _transactionPayerName(Map<String, dynamic> item) {
    final storedName = item['payer_name'] ?? item['entity_name'];
    if (storedName != null && storedName.toString().trim().isNotEmpty) {
      return widget._readableText(storedName).trim();
    }

    final rawId = item['entity_id'];
    final entityId = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '');
    if (entityId == null || entityId <= 0) return '';

    final entityType = item['entity_type']?.toString().toLowerCase().trim();
    final List<Map<String, dynamic>> source;
    if (entityType == 'client') {
      source = _clients;
    } else if (entityType == 'supplier') {
      source = _suppliers;
    } else if (entityType == 'worker' || entityType == 'employee') {
      source = _workers;
    } else {
      return '';
    }

    for (final row in source) {
      final rowId = row['id'] is num
          ? (row['id'] as num).toInt()
          : int.tryParse(row['id']?.toString() ?? '');
      if (rowId != entityId) continue;

      final directName = row['name']?.toString().trim() ?? '';
      if (directName.isNotEmpty) return widget._readableText(directName);
      final first = (row['firstname'] ?? row['first_name'] ?? '')
          .toString()
          .trim();
      final last = (row['lastname'] ?? row['last_name'] ?? '')
          .toString()
          .trim();
      return widget._readableText('$first $last'.trim());
    }
    return '';
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      await widget.db.migrateLegacyTreasuryRecords();

      final rawData = await widget.db.readTreasury();
      final data = rawData
          .map(
            (row) => <String, dynamic>{
              ...row,
              'caisse_name': widget._readableText(row['caisse_name']),
              'payment_method': widget._readableText(row['payment_method']),
              'description': widget._readableText(row['description']),
              'recorded_by': widget._readableText(row['recorded_by']),
            },
          )
          .where(
            (row) =>
                !widget.storeOnly || _isStoreCaisseName(row['caisse_name']),
          )
          .toList();
      final caisses = await widget.db.readCaisses();
      final caisseNames = caisses
          .map((c) => widget._readableText(c['name']))
          .where((name) => !widget.storeOnly || _isStoreCaisseName(name))
          .toList();
      if (caisseNames.isEmpty) {
        caisseNames.add(widget.storeOnly ? 'صندوق المحل' : 'الصندوق الرئيسي');
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
        } else if (type == 'Décaissement' ||
            type == 'DÃ©caissement' ||
            type == 'expense') {
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
      if (!silent && mounted) {
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
        final isInc = widget._isIncomeTransaction(t);
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

        final isGeneral =
            entityType == 'General' ||
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

    // Date Range filter
    if (_dateRange.isActive) {
      filtered = filtered.where((t) {
        final dStr = t['created_at']?.toString() ?? '';
        final d = DateTime.tryParse(dStr);
        return _dateRange.isWithinRange(d);
      }).toList();
    }

    // Numeric Operator Filter on Amount
    if (_numericFilter.isActive) {
      filtered = filtered.where((t) {
        final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
        return _numericFilter.matches(amt);
      }).toList();
    }

    // Per-column numeric filters (Income, Expense)
    if (_treasuryNumericFilters['income']?.isActive == true) {
      filtered = filtered.where((t) {
        final isInc = widget._isIncomeTransaction(t);
        final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
        return isInc
            ? _treasuryNumericFilters['income']!.matches(amt)
            : _treasuryNumericFilters['income']!.matches(0);
      }).toList();
    }
    if (_treasuryNumericFilters['expense']?.isActive == true) {
      filtered = filtered.where((t) {
        final isInc = widget._isIncomeTransaction(t);
        final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
        return !isInc
            ? _treasuryNumericFilters['expense']!.matches(amt)
            : _treasuryNumericFilters['expense']!.matches(0);
      }).toList();
    }

    // Per-column text filters
    for (final entry in _treasuryColumnControllers.entries) {
      final val = entry.value.text.trim().toLowerCase();
      if (val.isEmpty) continue;
      switch (entry.key) {
        case 'date':
          filtered = filtered
              .where(
                (t) => widget._transactionDate(t).toLowerCase().contains(val),
              )
              .toList();
          break;
        case 'entered_by':
          filtered = filtered
              .where(
                (t) => (t['recorded_by'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(val),
              )
              .toList();
          break;
        case 'payer_name':
          filtered = filtered
              .where(
                (t) => _transactionPayerName(t).toLowerCase().contains(val),
              )
              .toList();
          break;
        case 'type':
          filtered = filtered
              .where(
                (t) => (t['transaction_type'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(val),
              )
              .toList();
          break;
        case 'relation':
          filtered = filtered
              .where(
                (t) => widget
                    ._transactionRelation(t, AppLanguage.arabic)
                    .toLowerCase()
                    .contains(val),
              )
              .toList();
          break;
        case 'method':
          filtered = filtered
              .where(
                (t) => (t['payment_method'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(val),
              )
              .toList();
          break;
        case 'desc':
          filtered = filtered
              .where(
                (t) => (t['description'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(val),
              )
              .toList();
          break;
        case 'caisse':
          filtered = filtered
              .where(
                (t) => (t['caisse_name'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(val),
              )
              .toList();
          break;
      }
    }

    // 4. Search filter
    if (_searchQuery.isNotEmpty) {
      final search = _searchQuery.trim().toLowerCase();
      filtered = filtered.where((t) {
        final desc = (t['description'] ?? '').toString().toLowerCase();
        final amount = (t['amount'] ?? '').toString().toLowerCase();
        final phone = (t['phone'] ?? '').toString().toLowerCase();
        final recorded = (t['recorded_by'] ?? '').toString().toLowerCase();
        final payerName = _transactionPayerName(t).toLowerCase();
        final date = (t['created_at'] ?? '').toString().toLowerCase();
        final tType = (t['transaction_type'] ?? '').toString().toLowerCase();
        final pMethod = (t['payment_method'] ?? '').toString().toLowerCase();
        final cName = (t['caisse_name'] ?? '').toString().toLowerCase();

        return desc.contains(search) ||
            amount.contains(search) ||
            phone.contains(search) ||
            recorded.contains(search) ||
            payerName.contains(search) ||
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
      final isInc = widget._isIncomeTransaction(row);
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
        spans.add(
          TextSpan(
            text: text.substring(start, indexOfMatch),
            style: defaultStyle,
          ),
        );
      }

      spans.add(
        TextSpan(
          text: text.substring(indexOfMatch, indexOfMatch + query.length),
          style: defaultStyle.copyWith(
            backgroundColor: Colors.yellow.shade200,
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      start = indexOfMatch + query.length;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: defaultStyle));
    }

    return RichText(
      text: TextSpan(children: spans),
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
  }

  Future<void> _deleteTransaction(Map<String, dynamic> item) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          Localization.translate('تأكيد الحذف', lang),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          Localization.translate('هل أنت متأكد من حذف هذه المعاملة؟', lang),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              Localization.translate('إلغاء', lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              Localization.translate('حذف', lang),
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final id = (item['id'] as num?)?.toInt() ??
          int.tryParse(item['id']?.toString() ?? '');
      if (id == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر تحديد رقم المعاملة القديمة.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      try {
        final deleted = await widget.db.deleteTreasury(id);
        if (deleted <= 0) {
          throw StateError('لم تعد المعاملة موجودة في قاعدة البيانات المحلية.');
        }
        await _loadData();
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
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تعذر حذف المعاملة: $error',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showEditTransactionDialog(Map<String, dynamic> item) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final id = item['id'] as int;
    final amountCtrl = TextEditingController(
      text: item['amount']?.toString() ?? '',
    );
    final descCtrl = TextEditingController(text: item['description'] ?? '');
    String selectedCaisse =
        item['caisse_name']?.toString() ?? 'الصندوق الرئيسي';
    String selectedPaymentMethod =
        item['payment_method']?.toString() ?? 'نقداً / Espèce';

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
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: Localization.translate('المبلغ (د.ج)', lang),
                    prefixIcon: const Icon(Icons.attach_money),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Builder(
                  builder: (ctx) {
                    final canChangeDate = Provider.of<AppSettingsProvider>(
                      context,
                      listen: false,
                    ).canChangePaymentDates();
                    return InkWell(
                      onTap: canChangeDate
                          ? () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (date != null && context.mounted) {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(
                                    selectedDate,
                                  ),
                                );
                                if (time != null) {
                                  setStateDialog(() {
                                    selectedDate = DateTime(
                                      date.year,
                                      date.month,
                                      date.day,
                                      time.hour,
                                      time.minute,
                                    );
                                  });
                                }
                              }
                            }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 18,
                              color: canChangeDate ? Colors.teal : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat(
                                'dd/MM/yyyy  HH:mm',
                              ).format(selectedDate),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                color: canChangeDate ? null : Colors.grey,
                              ),
                            ),
                            if (!canChangeDate) ...[
                              const Spacer(),
                              const Icon(
                                Icons.lock,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _caisseNames.contains(selectedCaisse)
                      ? selectedCaisse
                      : (_caisseNames.isNotEmpty ? _caisseNames.first : null),
                  decoration: InputDecoration(
                    labelText: Localization.translate('اختر الصندوق', lang),
                    border: const OutlineInputBorder(),
                  ),
                  items: _caisseNames
                      .map(
                        (name) => DropdownMenuItem<String>(
                          value: name,
                          child: Text(
                            Localization.translate(name, lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
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
                  items:
                      [
                            'نقداً / Espèce',
                            'شيك / Chèque',
                            'شيك مصدق / Chèque de banque',
                            'تحويل بنكي / Virement',
                            'بطاقة بنكية / CIB',
                            'CCP / حساب جاري',
                            'بريدي موب / BaridiMob',
                          ]
                          .map(
                            (method) => DropdownMenuItem<String>(
                              value: method,
                              child: Text(
                                method,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
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
              child: Text(
                Localization.translate('إلغاء', lang),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
            TextButton(
              onPressed: () async {
                final double? newAmt = double.tryParse(amountCtrl.text);
                if (newAmt == null || newAmt <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        Localization.translate('يرجى إدخال مبلغ صحيح', lang),
                      ),
                    ),
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
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        Localization.translate('تم تعديل المعاملة بنجاح', lang),
                      ),
                    ),
                  );
                }
              },
              child: Text(
                Localization.translate('حفظ', lang),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReceiptOptions(BuildContext context, Map<String, dynamic> item) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
                  Localization.translate('طباعة الوصل', lang),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptPdfService.printReceiptWithFeedback(
                    item,
                    context,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.orange),
                title: Text(
                  Localization.translate('مشاركة', lang),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptPdfService.shareReceiptWithFeedback(
                    item,
                    context,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.download, color: Colors.blue),
                title: Text(
                  Localization.translate('حفظ الوصل', lang),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptPdfService.saveReceiptWithFeedback(
                    item,
                    context,
                  );
                },
              ),
              if (Provider.of<AppSettingsProvider>(
                context,
                listen: false,
              ).canEditPayments())
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blueGrey),
                  title: Text(
                    Localization.translate('تعديل المعاملة', lang),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditTransactionDialog(item);
                  },
                ),
              if (!widget.readOnly &&
                  Provider.of<AppSettingsProvider>(
                    context,
                    listen: false,
                  ).canDeletePayments())
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: Text(
                    Localization.translate('حذف المعاملة', lang),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
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
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final canManageCaisses = settings.canManageCaisses();
    final canAddCaisse = settings.canAddCaisses();
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(
                Localization.translate('إدارة الصناديق والحسابات', lang),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canAddCaisse) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: nameCtrl,
                              decoration: InputDecoration(
                                labelText: Localization.translate(
                                  'اسم صندوق جديد',
                                  lang,
                                ),
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
                    ],
                    Text(
                      Localization.translate(
                        'الصناديق الحالية (اضغط للتعديل أو الحذف):',
                        lang,
                      ),
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: widget.db.readCaisses(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final list = widget.storeOnly
                              ? snapshot.data!
                                    .where(
                                      (caisse) =>
                                          _isStoreCaisseName(caisse['name']),
                                    )
                                    .toList(growable: false)
                              : snapshot.data!;
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: list.length,
                            itemBuilder: (context, idx) {
                              final item = list[idx];
                              final id = item['id'] as int;
                              final rawName = item['name'].toString();
                              final name = widget._readableText(rawName);
                              return Card(
                                child: ListTile(
                                  title: Text(
                                    Localization.translate(name, lang),
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (canManageCaisses)
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blue,
                                          ),
                                          onPressed: () async {
                                            final editCtrl =
                                                TextEditingController(
                                                  text: name,
                                                );
                                            final newName = await showDialog<String>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: Text(
                                                  Localization.translate(
                                                    'تعديل اسم الصندوق',
                                                    lang,
                                                  ),
                                                ),
                                                content: TextField(
                                                  controller: editCtrl,
                                                  decoration: InputDecoration(
                                                    labelText:
                                                        Localization.translate(
                                                          'الاسم الجديد',
                                                          lang,
                                                        ),
                                                    border:
                                                        const OutlineInputBorder(),
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(ctx),
                                                    child: Text(
                                                      Localization.translate(
                                                        'إلغاء',
                                                        lang,
                                                      ),
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          editCtrl.text.trim(),
                                                        ),
                                                    child: Text(
                                                      Localization.translate(
                                                        'حفظ',
                                                        lang,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (newName != null &&
                                                newName.isNotEmpty &&
                                                newName != name) {
                                              await widget.db.updateCaisseName(
                                                id,
                                                newName,
                                                rawName,
                                              );
                                              setStateDialog(() {});
                                              _loadData();
                                            }
                                          },
                                        ),
                                      if (canManageCaisses &&
                                          list.length > 1 &&
                                          !widget.readOnly)
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: Text(
                                                  Localization.translate(
                                                    'تأكيد الحذف',
                                                    lang,
                                                  ),
                                                ),
                                                content: Text(
                                                  '${Localization.translate('هل أنت متأكد من حذف الصندوق', lang)} "${Localization.translate(name, lang)}"؟ ${Localization.translate('سيتم نقل معاملاته تلقائياً للصندوق الآخر.', lang)}',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          false,
                                                        ),
                                                    child: Text(
                                                      Localization.translate(
                                                        'إلغاء',
                                                        lang,
                                                      ),
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          true,
                                                        ),
                                                    child: Text(
                                                      Localization.translate(
                                                        'حذف',
                                                        lang,
                                                      ),
                                                      style: const TextStyle(
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await widget.db.deleteCaisse(
                                                id,
                                                rawName,
                                              );
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

  void _showAddTransactionDialog({String initialType = 'Encaissement'}) {
    TreasuryScreen.showQuickTransactionDialog(
      context,
      db: widget.db,
      initialType: initialType,
      caisseNames: _caisseNames,
      clients: _clients,
      suppliers: _suppliers,
      workers: _workers,
      onSaved: () {
        if (mounted) _loadData();
      },
    );
  }

  Future<void> _showDailyClosingDialog() async {
    final settings = context.read<AppSettingsProvider>();
    final lang = settings.language;
    if (!settings.canCloseBusinessDay()) return;
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final scope = widget.storeOnly ? 'store' : 'workshop';
    final totals = await widget.db.calculateBusinessDayReconciliation(
      businessDate: date,
      scope: scope,
    );
    if (!mounted) return;
    final countedController = TextEditingController(
      text: (totals['expected'] ?? 0).toStringAsFixed(2),
    );
    final notesController = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Localization.translate('التسوية اليومية', lang)),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${Localization.translate('التاريخ', lang)}: $date'),
              const SizedBox(height: 10),
              Text('${Localization.translate('إجمالي المبيعات', lang)}: '
                  '${(totals['sales'] ?? 0).toStringAsFixed(2)} DZD'),
              Text('${Localization.translate('المقبوضات', lang)}: '
                  '${(totals['income'] ?? 0).toStringAsFixed(2)} DZD'),
              Text('${Localization.translate('المصروفات', lang)}: '
                  '${(totals['expense'] ?? 0).toStringAsFixed(2)} DZD'),
              Text(
                '${Localization.translate('الرصيد المتوقع', lang)}: '
                '${(totals['expected'] ?? 0).toStringAsFixed(2)} DZD',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: countedController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: Localization.translate('النقد المحسوب فعلياً', lang),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: Localization.translate('ملاحظات', lang),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Localization.translate('cancel', lang)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.lock_clock_rounded),
            label: Text(Localization.translate('إغلاق اليوم', lang)),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final counted = double.tryParse(countedController.text.replaceAll(',', '.'));
    if (counted == null) return;
    await widget.db.closeBusinessDay(
      businessDate: date,
      scope: scope,
      countedCash: counted,
      notes: notesController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Localization.translate('تم حفظ التسوية اليومية في السجل', lang)),
        backgroundColor: Colors.teal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<AppSettingsProvider>(context);
    final lang = settingsProvider.language;
    final currency = Localization.translate('د.ج', lang);
    final formatter = NumberFormat('#,##0.00');
    final treasuryVerticalController = MediaQuery.sizeOf(context).width >= 900
        ? _desktopTreasuryScrollController
        : _mobileTreasuryScrollController;

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate('الخزينة (Caisse)', lang),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isDark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.teal,
        actions: [
          if (!widget.readOnly && settingsProvider.canCloseBusinessDay())
            IconButton(
              icon: const Icon(Icons.lock_clock_rounded),
              tooltip: Localization.translate('التسوية اليومية', lang),
              onPressed: _showDailyClosingDialog,
            ),
          PopupMenuButton<String>(
            initialValue: _selectedCaisse,
            tooltip: Localization.translate('اختيار الصندوق', lang),
            onSelected: (value) {
              setState(() => _selectedCaisse = value);
              _loadData();
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'الكل',
                child: Text(
                  Localization.translate('الكل (جميع الصناديق)', lang),
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
              ),
              ..._caisseNames.map(
                (name) => PopupMenuItem<String>(
                  value: name,
                  child: Text(
                    Localization.translate(name, lang),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 19),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 125),
                    child: Text(
                      Localization.translate(
                        _selectedCaisse == 'الكل'
                            ? 'كل الصناديق'
                            : _selectedCaisse,
                        lang,
                      ),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
          if (!widget.readOnly)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              tooltip: Localization.translate('معاملة جديدة', lang),
              onPressed: _showAddTransactionDialog,
            ),
          if (settingsProvider.canManageCaisses() ||
              settingsProvider.canAddCaisses())
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: Localization.translate('إدارة الصناديق', lang),
              onPressed: _showManageCaissesDialog,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: Localization.translate('تحديث', lang),
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    Localization.translate('جاري التحديث...', lang),
                  ),
                  duration: const Duration(milliseconds: 900),
                ),
              );
              await CloudSyncService().syncPendingNow();
              await _loadData();
              await _loadEntities();
            },
          ),
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
          : DesktopScrollFallback(
              controller: treasuryVerticalController,
              child: LayoutBuilder(
                builder: (context, viewport) => Column(
                  children: [
                    // 🟢 حقل البحث التفاعلي (يظهر ويختفي بناءً على الأيقونة في الأب بار)
                    if (_showSearch)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 8.0,
                        ),
                        child: TextField(
                          decoration: InputDecoration(
                            labelText: Localization.translate(
                              'بحث بالاسم أو البيان',
                              lang,
                            ),
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12.0,
                            vertical: 4.0,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 175,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: _selectedTypeFilter,
                                  decoration: InputDecoration(
                                    labelText: Localization.translate(
                                      'نوع المعاملة',
                                      lang,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Text(
                                        Localization.translate('الكل', lang),
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'income',
                                      child: Text(
                                        Localization.translate('مقبوضات', lang),
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'expense',
                                      child: Text(
                                        Localization.translate('مدفوعات', lang),
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                        ),
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
                                    labelText: Localization.translate(
                                      'التصنيف',
                                      lang,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Text(
                                        Localization.translate('كلها', lang),
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'general_expenses',
                                      child: Text(
                                        Localization.translate(
                                          'تكاليف إضافية / مصاريف عامة',
                                          lang,
                                        ),
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 13,
                                        ),
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
                    if (_selectedTypeFilter != 'all' ||
                        _selectedCategoryFilter != 'all' ||
                        _searchQuery.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 4.0,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.teal.withValues(alpha: 0.15)
                                : Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.teal.shade800
                                  : Colors.teal.shade100,
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
                                  color: isDark
                                      ? Colors.tealAccent
                                      : Colors.teal.shade900,
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
                                      color:
                                          (_filteredTotalIncome -
                                                  _filteredTotalExpense) >=
                                              0
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
                      child: viewport.maxWidth >= 900
                          ? widget._buildDesktopTreasuryTable(
                              context,
                              lang,
                              formatter,
                              currency,
                              isDark,
                              _filteredTransactions,
                              _filteredTotalIncome,
                              _filteredTotalExpense,
                              widget.readOnly,
                              settingsProvider.canEditPayments(),
                              settingsProvider.canDeletePayments(),
                              _desktopTableScrollController,
                              _showEditTransactionDialog,
                              _deleteTransaction,
                              (item) => _showReceiptOptions(context, item),
                              highlightedTransactionId:
                                  _highlightedTransactionId,
                              onHighlightedTap: (_) {
                                setState(
                                  () => _highlightedTransactionId = null,
                                );
                              },
                              dateRange: _dateRange,
                              onDateRangeChanged: (range) {
                                setState(() {
                                  _dateRange = range;
                                  _applyFilter();
                                });
                              },
                              numericFilter: _numericFilter,
                              onNumericFilterChanged: (filter) {
                                setState(() {
                                  _numericFilter = filter;
                                  _applyFilter();
                                });
                              },
                              columnControllers: _treasuryColumnControllers,
                              columnNumericFilters: _treasuryNumericFilters,
                              payerNameForTransaction: _transactionPayerName,
                              onFiltersUpdated: () =>
                                  setState(() => _applyFilter()),
                              onClearAllFilters: () {
                                setState(() {
                                  for (final c
                                      in _treasuryColumnControllers.values) {
                                    c.clear();
                                  }
                                  _treasuryNumericFilters.clear();
                                  _dateRange = const TableDateRange();
                                  _numericFilter = const NumericFilterState();
                                  _applyFilter();
                                });
                              },
                              verticalScrollController:
                                  _desktopTreasuryScrollController,
                            )
                          : ListView.builder(
                              controller: _mobileTreasuryScrollController,
                              primary: false,
                              itemCount: _filteredTransactions.length + 1,
                              // +1 for big balance card
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isDark
                                            ? [
                                                Colors.teal.shade900,
                                                Colors.grey.shade900,
                                              ]
                                            : [Colors.teal, Colors.green],
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          Localization.translate(
                                            'رصيد الصندوق',
                                            lang,
                                          ),
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
                                final tType =
                                    item['transaction_type']?.toString() ?? '';
                                final isIncome =
                                    tType == 'Encaissement' ||
                                    tType == 'income' ||
                                    (!tType.contains('Achat') &&
                                        !tType.contains('Purchase') &&
                                        !tType.contains('Décaissement') &&
                                        !tType.contains('expense'));

                                String dateStr = item['created_at'] ?? '';
                                if (dateStr.length > 16) {
                                  dateStr = dateStr
                                      .substring(0, 16)
                                      .replaceFirst('T', ' ');
                                }

                                final oldBal = (item['old_balance'] as num?)
                                    ?.toDouble();
                                final newBal = (item['new_balance'] as num?)
                                    ?.toDouble();
                                final phone = item['phone']?.toString() ?? '';
                                final payerName = _transactionPayerName(item);

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Row 1: Icon and Title
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 16,
                                              backgroundColor: isIncome
                                                  ? Colors.green.withValues(
                                                      alpha: 0.15,
                                                    )
                                                  : Colors.red.withValues(
                                                      alpha: 0.15,
                                                    ),
                                              child: Icon(
                                                isIncome
                                                    ? Icons.arrow_downward
                                                    : Icons.arrow_upward,
                                                color: isIncome
                                                    ? Colors.green
                                                    : Colors.red,
                                                size: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: _highlightText(
                                                _buildTransactionTitle(
                                                  item,
                                                  lang,
                                                ),
                                                _searchQuery,
                                                TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'Cairo',
                                                  fontSize: 13,
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black87,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),

                                        // Row 2: Paid Amount in its own row
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '${Localization.translate('المبلغ:', lang)} / Montant:',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDark
                                                    ? Colors.white60
                                                    : Colors.grey,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                            Text(
                                              '${isIncome ? "+" : "-"}${formatter.format((item['amount'] as num?)?.toDouble() ?? 0)} $currency',
                                              style: TextStyle(
                                                color: isIncome
                                                    ? Colors.green
                                                    : Colors.red,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),

                                        if (payerName.isNotEmpty) ...[
                                          Row(
                                            children: [
                                              Text(
                                                '${Localization.translate('اسم الدافع', lang)}: ',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isDark
                                                      ? Colors.white60
                                                      : Colors.grey,
                                                  fontFamily: 'Cairo',
                                                ),
                                              ),
                                              Expanded(
                                                child: _highlightText(
                                                  payerName,
                                                  _searchQuery,
                                                  TextStyle(
                                                    fontSize: 11,
                                                    color: isDark
                                                        ? Colors.white70
                                                        : Colors.black87,
                                                    fontFamily: 'Cairo',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                        ],

                                        if (phone.isNotEmpty) ...[
                                          Row(
                                            children: [
                                              const Text(
                                                '📞 ',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              Expanded(
                                                child: _highlightText(
                                                  phone,
                                                  _searchQuery,
                                                  const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.blueGrey,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                        ],

                                        if (oldBal != null &&
                                            newBal != null &&
                                            item['entity_type'] !=
                                                'General') ...[
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 2,
                                            ),
                                            child: Text(
                                              '${Localization.translate("الرصيد", lang)}: ${formatter.format(oldBal.abs())} → ${formatter.format(newBal.abs())} $currency',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark
                                                    ? Colors.white60
                                                    : Colors.grey.shade600,
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
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              '${Localization.translate('بواسطة', lang)}: ${item['recorded_by'] ?? ''} | $dateStr',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark
                                                    ? Colors.white60
                                                    : Colors.black54,
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.teal.withValues(
                                                  alpha: 0.08,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.inbox,
                                                    size: 10,
                                                    color: Colors.teal,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    t(
                                                      item['caisse_name']
                                                              ?.toString() ??
                                                          'الصندوق الرئيسي',
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: isDark
                                                          ? Colors.tealAccent
                                                          : Colors.teal,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontFamily: 'Cairo',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withValues(
                                                  alpha: 0.08,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.payment,
                                                    size: 10,
                                                    color: Colors.blue,
                                                  ),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    t(
                                                      item['payment_method']
                                                              ?.toString() ??
                                                          'نقداً / Espèce',
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: isDark
                                                          ? Colors.blueAccent
                                                          : Colors.blue,
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
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            TextButton.icon(
                                              style: TextButton.styleFrom(
                                                foregroundColor: isDark
                                                    ? Colors.tealAccent
                                                    : Colors.teal,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 4,
                                                    ),
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  side: BorderSide(
                                                    color: isDark
                                                        ? Colors.tealAccent
                                                        : Colors.teal,
                                                  ),
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.print,
                                                size: 14,
                                              ),
                                              label: Text(
                                                Localization.translate(
                                                  'خيارات الوصل',
                                                  lang,
                                                ),
                                                style: const TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              onPressed: () =>
                                                  _showReceiptOptions(
                                                    context,
                                                    item,
                                                  ),
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
      return desc.replaceFirst(
        'دفع للمورد الفاتورة',
        Localization.translate('دفع للمورد الفاتورة', lang),
      );
    }
    if (desc.startsWith('دفع للمورد الفاتوره')) {
      return desc.replaceFirst(
        'دفع للمورد الفاتوره',
        Localization.translate('دفع للمورد الفاتورة', lang),
      );
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
      return desc.replaceFirst(
        'دفع للمورد:',
        Localization.translate('دفع للمورد:', lang),
      );
    }
    if (desc.startsWith('دفع للمورد فاتورة رقم')) {
      return desc.replaceFirst(
        'دفع للمورد فاتورة رقم',
        Localization.translate('دفع للمورد فاتورة رقم', lang),
      );
    }
    return desc.isEmpty ? Localization.translate('بدون بيان', lang) : desc;
  }

  String t(String key) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return Localization.translate(key, lang);
  }
}
