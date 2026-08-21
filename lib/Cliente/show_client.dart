import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import '../sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../Screen/client_ledger_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class ShowClient extends StatefulWidget {
  final int clientId;

  const ShowClient({super.key, required this.clientId});

  @override
  State<ShowClient> createState() => _ShowClientState();
}

class _ShowClientState extends State<ShowClient> {
  final SqlDatabase db = SqlDatabase();
  late Future<List<dynamic>> _dataFuture;
  List<dynamic>? _cachedData;

  @override
  void initState() {
    super.initState();
    _refreshClientData();
  }

  void _refreshClientData() {
    final future = _loadData();
    _dataFuture = future.then((data) {
      if (mounted) {
        setState(() {
          _cachedData = data;
        });
      }
      return data;
    });
  }

  String _formatDate(String? date) {
    if (date == null || date.isEmpty) return '—';
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(date));
    } catch (_) {
      return date;
    }
  }

  bool get _canCallFromThisDevice =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _callPhoneNumber(String phone, AppLanguage lang) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty || !_canCallFromThisDevice) return;
    final uri = Uri(scheme: 'tel', path: cleanPhone);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localization.translate('تعذر فتح تطبيق الاتصال', lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate('تعذر فتح تطبيق الاتصال', lang),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
    }
  }

  Widget _buildPhoneNumbersRow(
    List<String> phones,
    AppLanguage lang,
  ) {
    if (!_canCallFromThisDevice) {
      return _InfoRow(
        icon: Icons.phone,
        iconColor: Colors.green,
        label: Localization.translate('Phone Numbers:', lang),
        value: phones.join('  ·  '),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.phone, color: Colors.green, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Localization.translate('Phone Numbers:', lang),
                style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: phones
                    .map(
                      (phone) => InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _callPhoneNumber(phone, lang),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.call, size: 15, color: Colors.green),
                              const SizedBox(width: 6),
                              Text(
                                phone,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _creationPlatformLabel(String source, AppLanguage lang) {
    switch (source.trim().toLowerCase()) {
      case 'computer':
        switch (lang) {
          case AppLanguage.french:
            return 'Ajouté depuis l’ordinateur';
          case AppLanguage.english:
            return 'Added from computer';
          default:
            return 'أُضيف من الكمبيوتر';
        }
      case 'phone':
        switch (lang) {
          case AppLanguage.french:
            return 'Ajouté depuis le téléphone';
          case AppLanguage.english:
            return 'Added from phone';
          default:
            return 'أُضيف من الهاتف';
        }
      case 'web':
        switch (lang) {
          case AppLanguage.french:
            return 'Ajouté depuis le web';
          case AppLanguage.english:
            return 'Added from web';
          default:
            return 'أُضيف من الويب';
        }
      default:
        switch (lang) {
          case AppLanguage.french:
            return 'Source d’ajout inconnue';
          case AppLanguage.english:
            return 'Creation source unknown';
          default:
            return 'مصدر الإضافة غير معروف';
        }
    }
  }

  IconData _creationPlatformIcon(String source) {
    switch (source.trim().toLowerCase()) {
      case 'computer':
        return Icons.desktop_windows_outlined;
      case 'phone':
        return Icons.phone_android_outlined;
      case 'web':
        return Icons.language_outlined;
      default:
        return Icons.help_outline;
    }
  }

  void _showAddPaymentDialog(
    BuildContext context,
    int orderId,
    double remaining,
    String clientName,
  ) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '${Localization.translate("Add payment to order", lang)} #$orderId',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: TextField(
          controller: amountCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: Localization.translate("Amount paid", lang),
            hintText:
                '${Localization.translate("Remaining:", lang)} ${remaining.toStringAsFixed(2)} د.ج',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.payments_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Localization.translate('Cancel', lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).appBarTheme.backgroundColor
                  : Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text) ?? 0.0;
              if (amount > 0) {
                if (ctx.mounted) {
                  final settings = Provider.of<AppSettingsProvider>(
                    ctx,
                    listen: false,
                  );
                  await db.insertTreasury(
                    'Encaissement',
                    amount,
                    'دفعة لطلبية رقم $orderId من الزبون: $clientName',
                    referenceId: orderId,
                    entityType: 'Client',
                    entityId: widget.clientId,
                    recordedBy: settings.userDisplayName,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) _refreshClientData();
              }
            },
            child: Text(Localization.translate('Save payment', lang)),
          ),
        ],
      ),
    );
  }

  Future<List<dynamic>> _loadData() async {
    await db.migrateLegacyTreasuryRecords();
    final myDb = await db.db;
    final cData = await myDb!.query(
      'Client',
      where: 'id = ?',
      whereArgs: [widget.clientId],
    );
    final orders = await myDb.query(
      'Commandes',
      where: 'client_id = ?',
      whereArgs: [widget.clientId],
      orderBy: 'id DESC',
    );
    final treasury = await myDb.query(
      'Treasury',
      where: "entity_type = 'Client' AND entity_id = ?",
      whereArgs: [widget.clientId],
    );
    return [cData, orders, treasury];
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          Localization.translate("Client Details", lang),
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'كشف حساب الزبون (Chrono)',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ClientLedgerScreen(clientId: widget.clientId),
                ),
              ).then((_) => _refreshClientData());
            },
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _dataFuture,
        builder: (context, asyncSnapshot) {
          if (asyncSnapshot.hasData) {
            _cachedData = asyncSnapshot.data;
          }

          if (asyncSnapshot.connectionState == ConnectionState.waiting &&
              _cachedData == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (asyncSnapshot.hasError && _cachedData == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 64,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      Localization.translate('Error loading data', lang),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () => setState(() {}),
                      icon: const Icon(Icons.refresh),
                      label: Text(Localization.translate('Refresh', lang)),
                    ),
                  ],
                ),
              ),
            );
          }

          final rawData = asyncSnapshot.hasData
              ? asyncSnapshot.data!
              : (_cachedData ?? []);
          if (rawData.isEmpty) {
            return Center(child: Text(Localization.translate('No Data', lang)));
          }

          final clientData = rawData[0] as List<Map<String, dynamic>>;
          if (clientData.isEmpty) {
            return Center(
              child: Text(Localization.translate('Client not found', lang)),
            );
          }

          final client = clientData[0];
          final orders = rawData[1] as List<Map<String, dynamic>>;
          final treasury = rawData[2] as List<Map<String, dynamic>>;

          double totalOrders = 0.0;
          for (var order in orders) {
            final net = (order['net_payable'] as num?)?.toDouble() ?? 0.0;
            final raw = (order['total'] as num?)?.toDouble() ?? 0.0;
            totalOrders += net > 0 ? net : raw;
          }

          double totalPayments = 0.0;
          for (var t in treasury) {
            final type = t['transaction_type']?.toString() ?? 'Encaissement';
            final amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
            if (type == 'Encaissement') {
              totalPayments += amount;
            } else if (type == 'Décaissement') {
              totalPayments -= amount;
            }
          }
          final remaining = totalOrders - totalPayments;

          final firstName = client['firstname'] ?? '';
          final lastName = client['lastname'] ?? '';
          final phone1 = client['phone1']?.toString() ?? '';
          final phone2 = client['phone2']?.toString() ?? '';
          final email = client['email']?.toString() ?? '';
          final address = client['address']?.toString() ?? '';
          final createdAt = client['created_at']?.toString() ?? '';
          final creationPlatform =
              client['creation_platform']?.toString() ?? 'unknown';

          final bool hasPhone1 =
              phone1.isNotEmpty && phone1 != '0' && phone1 != 'null';
          final bool hasPhone2 =
              phone2.isNotEmpty && phone2 != '0' && phone2 != 'null';
          final bool hasEmail = email.isNotEmpty && email != 'null';
          final bool hasAddress = address.isNotEmpty && address != 'null';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ─── Client Header Card ───────────────────────────────
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Theme.of(context).dividerColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).appBarTheme.backgroundColor
                            : Colors.blue.shade100,
                        child: Text(
                          (firstName.isNotEmpty
                                  ? firstName[0]
                                  : (lastName.isNotEmpty ? lastName[0] : '?'))
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.blue.shade300
                                : Colors.blue.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$lastName $firstName'.trim(),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (createdAt.isNotEmpty)
                              Text(
                                _formatDate(createdAt),
                                style: TextStyle(fontSize: 13),
                              ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  _creationPlatformIcon(creationPlatform),
                                  size: 15,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    _creationPlatformLabel(
                                      creationPlatform,
                                      lang,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ─── Contact Info Card ────────────────────────────────
                _SectionCard(
                  title: Localization.translate('Client Information', lang),
                  icon: Icons.info_outline,
                  child: Column(
                    children: [
                      if (hasPhone1 || hasPhone2)
                        _buildPhoneNumbersRow(
                          [
                            if (hasPhone1) phone1,
                            if (hasPhone2) phone2,
                          ],
                          lang,
                        ),
                      if (hasEmail) ...[
                        const Divider(height: 16),
                        _InfoRow(
                          icon: Icons.email_outlined,
                          iconColor: Colors.orange,
                          label: Localization.translate('Email', lang),
                          value: email,
                        ),
                      ],
                      if (hasAddress) ...[
                        const Divider(height: 16),
                        _InfoRow(
                          icon: Icons.place_outlined,
                          iconColor: Colors.red,
                          label: Localization.translate('Address:', lang),
                          value: address,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ─── Financial Summary ────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: Localization.translate('Total Orders', lang),
                        value: '${totalOrders.toStringAsFixed(2)} دج',
                        color: Colors.blue,
                        icon: Icons.receipt_long_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        label: Localization.translate('Total Payments', lang),
                        value: '${totalPayments.toStringAsFixed(2)} دج',
                        color: Colors.green,
                        icon: Icons.payments_outlined,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                _StatCard(
                  label: Localization.translate('Rest of the order', lang),
                  value: '${remaining.toStringAsFixed(2)} دج',
                  color: remaining > 0 ? Colors.red : Colors.green,
                  icon: remaining > 0
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  fullWidth: true,
                ),

                const SizedBox(height: 10),

                if (settings.canViewClientLedger()) ...[
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    color: Theme.of(context).cardColor,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ClientLedgerScreen(clientId: widget.clientId),
                          ),
                        ).then((_) => setState(() {}));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Theme.of(
                                        context,
                                      ).primaryColor.withValues(alpha: 0.15)
                                    : Colors.blue.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.history_edu_rounded,
                                color: Colors.blue.shade700,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    Localization.translate(
                                      'عرض كشف الحساب التفصيلي (Chrono)',
                                      lang,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    Localization.translate(
                                      'سجل الطلبيات والمدفوعات مرتبة زمنياً',
                                      lang,
                                    ),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodySmall?.color,
                                      fontSize: 11,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              color: Colors.blue.shade300,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ─── Orders List ──────────────────────────────────────
                _SectionCard(
                  title: Localization.translate('Customer Orders', lang),
                  icon: Icons.list_alt_outlined,
                  child: orders.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              Localization.translate('No Data', lang),
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: orders.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final order = orders[index];
                            final netPay =
                                (order['net_payable'] as num?)?.toDouble() ??
                                0.0;
                            final rawTotal =
                                (order['total'] as num?)?.toDouble() ?? 0.0;
                            final orderTotal = netPay > 0 ? netPay : rawTotal;
                            final orderAdvance =
                                (order['advance_payment'] as num?)
                                    ?.toDouble() ??
                                0.0;
                            final orderRemaining = orderTotal - orderAdvance;
                            final isPaid = orderAdvance >= orderTotal;
                            final orderDate = _formatDate(
                              order['created_at']?.toString(),
                            );

                            return Container(
                              padding: EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: isPaid
                                        ? Colors.green.shade50
                                        : Colors.orange.shade50,
                                    child: Icon(
                                      isPaid
                                          ? Icons.check_circle
                                          : Icons.hourglass_bottom,
                                      size: 20,
                                      color: isPaid
                                          ? Colors.green
                                          : Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              '${Localization.translate("Order", lang)} #${order["id"]}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isPaid
                                                    ? Colors.green.shade50
                                                    : Colors.orange.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: isPaid
                                                      ? Colors.green.shade200
                                                      : Colors.orange.shade200,
                                                ),
                                              ),
                                              child: Text(
                                                isPaid
                                                    ? Localization.translate(
                                                        'Paid',
                                                        lang,
                                                      )
                                                    : Localization.translate(
                                                        'Unpaid',
                                                        lang,
                                                      ),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isPaid
                                                      ? Colors.green.shade700
                                                      : Colors.orange.shade700,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          orderDate,
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            Text(
                                              '${Localization.translate("Total:", lang)} ${orderTotal.toStringAsFixed(2)} دج',
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              '${Localization.translate("Amount paid", lang)} ${orderAdvance.toStringAsFixed(2)} دج',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.green.shade700,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (!isPaid)
                                              Text(
                                                '· ${Localization.translate("Remaining:", lang)} ${orderRemaining.toStringAsFixed(2)} دج',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.red.shade600,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (!isPaid)
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Theme.of(
                                                context,
                                              ).appBarTheme.backgroundColor
                                            : Colors.blue,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: () {
                                        final clientName =
                                            '${client['firstname'] ?? ''} ${client['lastname'] ?? ''}'
                                                .trim();
                                        _showAddPaymentDialog(
                                          context,
                                          order['id'] as int,
                                          orderRemaining,
                                          clientName,
                                        );
                                      },
                                      child: Text(
                                        Localization.translate(
                                          'Add payment',
                                          lang,
                                        ),
                                      ),
                                    )
                                  else
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green.shade400,
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Reusable widgets ───────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
              children: [
                TextSpan(
                  text: '$label  ',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool fullWidth;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(width: 5, color: color)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
