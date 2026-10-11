import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:database_data/widgets/app_material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import '../sql_database.dart';
import '../services/cloud_sync_service.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../Screen/client_ledger_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../Commande/partial_proforma_screen.dart';
import '../Commande/devis_builder.dart';
import '../Commande/devis_preview_screen.dart';
import '../widgets/desktop_context_menu.dart';
import '../Commande/order_workspace_screen.dart';

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
  StreamSubscription? _syncSub;
  int _deliveryFilterIndex = 0;

  @override
  void initState() {
    super.initState();
    _refreshClientData();
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        _refreshClientData();
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
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

  int _displayOrderNum(Map<String, dynamic> o) {
    for (final key in const ['order_code', 'display_number']) {
      final v = o[key];
      final n = v is num ? v.toInt() : int.tryParse(v?.toString().trim() ?? '');
      if (n != null && n > 0) return n;
    }
    final rawId = o['id'] ?? o['order_id'] ?? o['id_commandes'];
    final idNum = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString().trim() ?? '');
    if (idNum != null && idNum > 0 && idNum < 100000) return idNum;
    return idNum != null ? ((idNum % 1000).abs() + 1) : 1;
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
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
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

  Widget _buildPhoneNumbersRow(List<String> phones, AppLanguage lang) {
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
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
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
                              const Icon(
                                Icons.call,
                                size: 15,
                                color: Colors.green,
                              ),
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
    String clientName, [
    int? orderCode,
  ]) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final amountCtrl = TextEditingController();
    final displayOrderNum = (orderCode != null && orderCode > 0)
        ? orderCode
        : orderId;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '${Localization.translate("Add payment to order", lang)} #$displayOrderNum',
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
                    'دفعة لطلبية رقم $displayOrderNum من الزبون: $clientName',
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
      where: 'client_id = ? AND (is_deleted IS NULL OR is_deleted = 0)',
      whereArgs: [widget.clientId],
      orderBy: 'id DESC',
    );
    final treasury = await myDb.query(
      'Treasury',
      where: "entity_type = 'Client' AND entity_id = ?",
      whereArgs: [widget.clientId],
    );
    List<Map<String, dynamic>> deliveries = [];
    try {
      deliveries = await myDb.rawQuery(
        '''
        SELECT d.*, c.order_code, c.order_code AS display_number, COALESCE(p.name, '') AS project_name, c.status as order_status
        FROM Commandes_deliveries d
        LEFT JOIN Commandes c ON CAST(d.id_commandes AS TEXT) = CAST(c.id AS TEXT)
        LEFT JOIN Projects p ON c.project_id = p.id
        WHERE (c.is_deleted IS NULL OR c.is_deleted = 0)
          AND (CAST(d.client_id AS TEXT) = ? OR CAST(c.client_id AS TEXT) = ? OR d.id_commandes IN (SELECT id FROM Commandes WHERE client_id = ? AND (is_deleted IS NULL OR is_deleted = 0)))
        ORDER BY d.id DESC
      ''',
        [
          widget.clientId.toString(),
          widget.clientId.toString(),
          widget.clientId,
        ],
      );
      deliveries = deliveries.map((d) => Map<String, dynamic>.from(d)).toList();
    } catch (e) {
      debugPrint('Error loading deliveries in show_client: $e');
    }

    // Auto-detect deliveries for delivered orders if not explicitly present in Commandes_deliveries
    final existingOrderIds = deliveries
        .map((d) => (d['id_commandes'] as num?)?.toInt())
        .whereType<int>()
        .toSet();
    for (final order in orders) {
      final oId = (order['id'] as num?)?.toInt() ?? 0;
      final status = (order['status'] ?? '').toString();
      final isDeliveredStatus =
          status == 'Partial Distribution' ||
          status == 'Full Distribution' ||
          status == 'Livré' ||
          status == 'Distributed';
      if (isDeliveredStatus && !existingOrderIds.contains(oId)) {
        try {
          final details = await myDb.query(
            'Commandes_details',
            where: 'id_commandes = ?',
            whereArgs: [oId],
          );
          final items = details
              .map(
                (cd) => {
                  'id': cd['id'],
                  'name': cd['window_type']?.toString().isNotEmpty == true
                      ? cd['window_type']
                      : 'نافذة',
                  'quantity': cd['quantity'] ?? 1,
                  'price': cd['price'] ?? 0.0,
                  'width': cd['largeur'] ?? 0,
                  'height': cd['hauteur'] ?? 0,
                  'color': cd['color'] ?? '',
                  'glass': cd['glass'] ?? '',
                  'description': cd['description'] ?? '',
                  'drawing_image_path': cd['drawing_image_path'] ?? '',
                },
              )
              .toList();

          final dateStr = (order['created_at'] ?? '').toString();
          final totalAmount = (order['total'] as num?)?.toDouble() ?? 0.0;

          deliveries.add({
            'id': -oId,
            'id_commandes': oId,
            'client_id': widget.clientId,
            'delivery_date': dateStr,
            'items_json': jsonEncode(items),
            'total_amount': totalAmount,
            'is_loaded': 1,
            'is_partial': status == 'Partial Distribution' ? 1 : 0,
            'order_code': order['order_code'] ?? oId,
            'display_number': order['order_code'] ?? oId,
            'project_name': '',
            'order_status': status,
          });
        } catch (_) {}
      }
    }

    List<Map<String, dynamic>> clientItems = [];
    try {
      clientItems = await myDb.rawQuery(
        '''
        SELECT 
          cd.id as detail_id,
          cd.id_commandes,
          cd.largeur,
          cd.hauteur,
          cd.window_type,
          cd.color,
          cd.glass,
          cd.quantity,
          cd.price,
          cd.drawing_image_path,
          cd.delivered_qty,
          c.order_code,
          c.order_code AS display_number,
          COALESCE(p.name, '') AS project_name,
          c.created_at AS order_date,
          c.status as order_status,
          wa.id as allocation_id,
          wa.unit_index,
          COALESCE(wa.is_transferred_to_dist, wa.is_distributed, 0) as is_transferred_to_dist,
          COALESCE(wa.transferred_at, wa.distributed_at) as transferred_at,
          COALESCE(wa.is_manufactured, 0) as is_manufactured,
          COALESCE(wa.is_glass_installed, 0) as is_glass_installed,
          COALESCE(wa.is_distributed, 0) as is_distributed
        FROM Commandes_details cd
        JOIN Commandes c ON cd.id_commandes = c.id
        LEFT JOIN Projects p ON c.project_id = p.id
        LEFT JOIN WorkerAllocations wa ON wa.commande_detail_id = cd.id
        WHERE c.client_id = ? AND (c.is_deleted IS NULL OR c.is_deleted = 0)
        ORDER BY c.id DESC, cd.id ASC, wa.unit_index ASC
      ''',
        [widget.clientId],
      );
    } catch (e) {
      debugPrint('Error loading clientItems in show_client: $e');
    }

    return [cData, orders, treasury, deliveries, clientItems];
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
            icon: const Icon(Icons.refresh),
            tooltip: Localization.translate('تحديث', lang),
            onPressed: () async {
              await CloudSyncService().syncPendingNow();
              _refreshClientData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: Localization.translate('كشف حساب الزبون (Chrono)', lang),
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
          final deliveries =
              (rawData.length > 3 ? rawData[3] : [])
                  as List<Map<String, dynamic>>;
          final clientItems =
              (rawData.length > 4 ? rawData[4] : [])
                  as List<Map<String, dynamic>>;

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
                        _buildPhoneNumbersRow([
                          if (hasPhone1) phone1,
                          if (hasPhone2) phone2,
                        ], lang),
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

                if (client['latitude'] != null &&
                    client['longitude'] != null) ...[
                  const Divider(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Localization.translate(
                                'موقع الزبون (GPS):',
                                lang,
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '${(client['latitude'] as num).toDouble().toStringAsFixed(6)}, ${(client['longitude'] as num).toDouble().toStringAsFixed(6)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.map_rounded, size: 16),
                        label: Text(
                          Localization.translate('خرائط Google', lang),
                        ),
                        onPressed: () async {
                          final lat = (client['latitude'] as num).toDouble();
                          final lng = (client['longitude'] as num).toDouble();
                          final uri = Uri.parse(
                            'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
                          );
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                      ),
                    ],
                  ),
                ],

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

                            return GestureDetector(
                              onSecondaryTapDown: (details) =>
                                  _showOrderContextMenu(
                                    context,
                                    order,
                                    details.globalPosition,
                                    lang,
                                    orderRemaining: orderRemaining,
                                    isPaid: isPaid,
                                  ),
                              child: Container(
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
                                                '${Localization.translate("Order", lang)} #${_displayOrderNum(order)}',
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
                                                        : Colors
                                                              .orange
                                                              .shade200,
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
                                                        : Colors
                                                              .orange
                                                              .shade700,
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
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        if (!isPaid)
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Theme.of(
                                                        context,
                                                      ).brightness ==
                                                      Brightness.dark
                                                  ? Theme.of(context)
                                                        .appBarTheme
                                                        .backgroundColor
                                                  : Colors.blue,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              textStyle: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
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
                                                (order['order_code'] as num?)
                                                        ?.toInt() ??
                                                    (order['display_number']
                                                            as num?)
                                                        ?.toInt(),
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
                                        const SizedBox(height: 6),
                                        Builder(
                                          builder: (context) {
                                            final status =
                                                (order['status'] ?? '')
                                                    .toString();
                                            final isFullyDelivered =
                                                status == 'Full Distribution' ||
                                                status == 'Livré' ||
                                                status == 'Distributed';
                                            final isPartialDelivered =
                                                status ==
                                                'Partial Distribution';

                                            Map<String, dynamic>?
                                            matchingDelivery;
                                            for (final d in deliveries) {
                                              if ((d['id_commandes'] as num?)
                                                      ?.toInt() ==
                                                  (order['id'] as num?)
                                                      ?.toInt()) {
                                                matchingDelivery = d;
                                                break;
                                              }
                                            }
                                            final isDeliveredInRecord =
                                                matchingDelivery != null &&
                                                (matchingDelivery['is_loaded']
                                                            as num?)
                                                        ?.toInt() ==
                                                    1;
                                            final isOrderDoneDelivered =
                                                isFullyDelivered ||
                                                (isDeliveredInRecord &&
                                                    !isPartialDelivered);

                                            if (isOrderDoneDelivered) {
                                              return OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      Colors.green.shade700,
                                                  backgroundColor: Colors.green
                                                      .withOpacity(0.08),
                                                  side: BorderSide(
                                                    color:
                                                        Colors.green.shade400,
                                                    width: 1.0,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 5,
                                                      ),
                                                  textStyle: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons.check_circle_outline,
                                                  size: 14,
                                                  color: Colors.green,
                                                ),
                                                label: Text(
                                                  lang == AppLanguage.french
                                                      ? 'Livré (Voir BL)'
                                                      : 'تم التسليم (عرض BL)',
                                                ),
                                                onPressed: () {
                                                  if (matchingDelivery !=
                                                      null) {
                                                    _previewDeliveryDoc(
                                                      context,
                                                      matchingDelivery,
                                                      orders,
                                                      lang,
                                                      isBonDeCharge: false,
                                                    );
                                                  } else {
                                                    _openOrderDeliveryPreview(
                                                      order,
                                                      lang,
                                                    );
                                                  }
                                                },
                                              );
                                            } else if (isPartialDelivered) {
                                              return OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      Colors.orange.shade800,
                                                  backgroundColor: Colors.orange
                                                      .withOpacity(0.08),
                                                  side: BorderSide(
                                                    color:
                                                        Colors.orange.shade400,
                                                    width: 1.0,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 5,
                                                      ),
                                                  textStyle: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons.local_shipping_outlined,
                                                  size: 14,
                                                  color: Colors.orange,
                                                ),
                                                label: Text(
                                                  lang == AppLanguage.french
                                                      ? 'Livré partiel (BL)'
                                                      : 'تسليم جزئي (BL)',
                                                ),
                                                onPressed: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          PartialProformaScreen(
                                                            order: order,
                                                            documentTitleKey:
                                                                'doc_bon_livraison_partiel',
                                                          ),
                                                    ),
                                                  ).then(
                                                    (_) => _refreshClientData(),
                                                  );
                                                },
                                              );
                                            }

                                            return OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    Colors.teal.shade700,
                                                side: BorderSide(
                                                  color: Colors.teal.shade400,
                                                  width: 1.0,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 5,
                                                    ),
                                                textStyle: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.local_shipping_outlined,
                                                size: 14,
                                              ),
                                              label: Text(
                                                lang == AppLanguage.french
                                                    ? 'Livrer (BL)'
                                                    : Localization.translate(
                                                        'تسليم سلع',
                                                        lang,
                                                      ),
                                              ),
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        PartialProformaScreen(
                                                          order: order,
                                                          documentTitleKey:
                                                              'doc_bon_livraison_partiel',
                                                        ),
                                                  ),
                                                ).then(
                                                  (_) => _refreshClientData(),
                                                );
                                              },
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ); // GestureDetector
                          },
                        ),
                ),

                const SizedBox(height: 16),

                // ─── Deliveries Section (بونات التوصيل والتسليم) ───────────
                _buildDeliveriesSection(deliveries, orders, lang),

                const SizedBox(height: 16),

                // ─── Window Delivery Tracking Section (متابعة تسليم النوافذ والعناصر) ───
                _buildClientItemsDeliverySection(clientItems, orders, lang),

                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeliveriesSection(
    List<Map<String, dynamic>> deliveries,
    List<Map<String, dynamic>> orders,
    AppLanguage lang,
  ) {
    String tr(String ar, String fr) {
      if (lang == AppLanguage.french) return fr;
      return Localization.translate(ar, lang);
    }

    return _SectionCard(
      title: tr('وصلات التسليم والشحن', 'Bons de Livraison & Expéditions'),
      icon: Icons.local_shipping_outlined,
      child: deliveries.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  tr(
                    'لا توجد تسليمات مسجلة بعد',
                    'Aucune livraison enregistrée',
                  ),
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: deliveries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final d = deliveries[index];
                final deliveryId = d['id'];
                final dateStr = (d['delivery_date'] ?? '').toString();
                final orderCode = _displayOrderNum(d);
                final projectName = (d['project_name'] ?? '').toString();
                final totalAmount =
                    (d['total_amount'] as num?)?.toDouble() ?? 0.0;
                final isLoaded = (d['is_loaded'] as num?)?.toInt() == 1;
                final orderStatus = (d['order_status'] ?? '').toString();
                final bool isPartial =
                    (d['is_partial'] as num?)?.toInt() == 1 ||
                    orderStatus == 'Partial Distribution';

                List<Map<String, dynamic>> items = [];
                try {
                  final raw = jsonDecode(d['items_json']?.toString() ?? '[]');
                  if (raw is List) {
                    items = raw
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                  }
                } catch (_) {}

                final totalUnits = items.fold<int>(
                  0,
                  (sum, it) => sum + ((it['quantity'] as num?)?.toInt() ?? 1),
                );

                return GestureDetector(
                  onSecondaryTapDown: (details) async {
                    final selected = await showDesktopContextMenu<String>(
                      context: context,
                      globalPosition: details.globalPosition,
                      items: [
                        PopupMenuItem(
                          value: 'BL',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.print,
                                color: Colors.blue,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                tr('وصل تسليم (BL)', 'Bon de livraison'),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'CHARGE',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.local_shipping,
                                color: Colors.teal,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                tr('وصل شحن (Bon de charge)', 'Bon de charge'),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                    if (selected == 'BL') {
                      _previewDeliveryDoc(
                        context,
                        d,
                        orders,
                        lang,
                        isBonDeCharge: false,
                      );
                    } else if (selected == 'CHARGE') {
                      _previewDeliveryDoc(
                        context,
                        d,
                        orders,
                        lang,
                        isBonDeCharge: true,
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isLoaded
                                ? Colors.green.shade50
                                : Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isLoaded
                                  ? Colors.green.shade200
                                  : Colors.teal.shade200,
                            ),
                          ),
                          child: Icon(
                            isLoaded
                                ? Icons.check_circle_outline
                                : Icons.local_shipping,
                            color: isLoaded
                                ? Colors.green.shade700
                                : Colors.teal,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    'BL #$deliveryId',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isPartial
                                          ? Colors.orange.shade50
                                          : Colors.teal.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isPartial
                                            ? Colors.orange.shade300
                                            : Colors.teal.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      isPartial
                                          ? tr('وصل تسليم جزئي', 'BL Partiel')
                                          : tr('وصل تسليم كلي', 'BL Total'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isPartial
                                            ? Colors.orange.shade900
                                            : Colors.teal.shade900,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isLoaded
                                          ? Colors.green.shade50
                                          : Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isLoaded
                                            ? Colors.green.shade200
                                            : Colors.blue.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      isLoaded
                                          ? tr('مؤكد (Validé)', 'Validé')
                                          : tr(
                                              'في انتظار التأكيد',
                                              'En attente',
                                            ),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isLoaded
                                            ? Colors.green.shade700
                                            : Colors.blue.shade700,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${tr('الطلبية', 'Commande')} #$orderCode${projectName.isNotEmpty ? ' ($projectName)' : ''} · $dateStr',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (items.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    items
                                        .map(
                                          (it) =>
                                              '${it['name'] ?? it['type_name'] ?? 'نافذة'} (×${it['quantity'] ?? 1})',
                                        )
                                        .join('، '),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.blueGrey.shade800,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  Text(
                                    '${tr('الكمية', 'Quantité')}: $totalUnits ${tr('عنصر', 'unités')}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (totalAmount > 0)
                                    Text(
                                      '${tr('القيمة', 'Montant')}: ${totalAmount.toStringAsFixed(2)} دج',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.teal.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          tooltip: tr('خيارات الوصل', 'Options du bon'),
                          icon: const Icon(Icons.more_vert, size: 20),
                          onSelected: (val) {
                            if (val == 'BL') {
                              _previewDeliveryDoc(
                                context,
                                d,
                                orders,
                                lang,
                                isBonDeCharge: false,
                              );
                            } else if (val == 'CHARGE') {
                              _previewDeliveryDoc(
                                context,
                                d,
                                orders,
                                lang,
                                isBonDeCharge: true,
                              );
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'BL',
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.print,
                                    color: Colors.blue,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    tr('وصل تسليم (BL)', 'Bon de livraison'),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'CHARGE',
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.local_shipping,
                                    color: Colors.teal,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    tr(
                                      'وصل شحن (Bon de charge)',
                                      'Bon de charge',
                                    ),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ); // GestureDetector
              },
            ),
    );
  }

  Future<void> _previewDeliveryDoc(
    BuildContext context,
    Map<String, dynamic> delivery,
    List<Map<String, dynamic>> orders,
    AppLanguage lang, {
    required bool isBonDeCharge,
  }) async {
    final orderId = (delivery['id_commandes'] as num?)?.toInt() ?? 0;
    final order = orders.firstWhere(
      (o) => (o['id'] as num?)?.toInt() == orderId,
      orElse: () => <String, dynamic>{},
    );
    if (order.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate('الطلبية غير موجودة', lang)),
        ),
      );
      return;
    }

    List<Map<String, dynamic>> items = [];
    try {
      final raw = jsonDecode(delivery['items_json']?.toString() ?? '[]');
      if (raw is List) {
        items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}

    final workshop = await DevisBuilder.loadWorkshopInfo().timeout(
      const Duration(seconds: 10),
      onTimeout: () => DevisWorkshopInfo.empty,
    );

    final orderStatus = (order['status'] ?? delivery['order_status'] ?? '')
        .toString();
    final bool isPartial =
        (delivery['is_partial'] as num?)?.toInt() == 1 ||
        orderStatus == 'Partial Distribution';

    final devis = await DevisBuilder.build(
      order: order,
      items: items,
      workshop: workshop,
      isPartial: isPartial,
      documentTitleKey: isBonDeCharge
          ? 'BON_CHARGE'
          : (isPartial ? 'doc_bon_livraison_partiel' : 'doc_bon_livraison'),
    );

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DevisPreviewScreen(
          data: devis,
          deliveryId: delivery['id'] as int?,
          initialIsLoaded: (delivery['is_loaded'] as num?)?.toInt() == 1,
        ),
      ),
    ).then((_) => _refreshClientData());
  }

  Future<void> _showOrderContextMenu(
    BuildContext context,
    Map<String, dynamic> order,
    Offset position,
    AppLanguage lang, {
    required double orderRemaining,
    required bool isPaid,
  }) async {
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final selected = await showDesktopContextMenu<String>(
      context: context,
      globalPosition: position,
      items: [
        if (settings.canEditOrders())
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                const Icon(Icons.edit, size: 18, color: Colors.blue),
                const SizedBox(width: 8),
                Text(Localization.translate('Edit Order', lang)),
              ],
            ),
          ),
        if (!isPaid)
          PopupMenuItem(
            value: 'payment',
            child: Row(
              children: [
                const Icon(Icons.payments, size: 18, color: Colors.green),
                const SizedBox(width: 8),
                Text(Localization.translate('Add payment', lang)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'delivery',
          child: Row(
            children: [
              const Icon(Icons.local_shipping, size: 18, color: Colors.teal),
              const SizedBox(width: 8),
              Text(
                lang == AppLanguage.french
                    ? 'Livraison (BL)'
                    : Localization.translate('تسليم سلع', lang),
              ),
            ],
          ),
        ),
      ],
    );

    if (!mounted || selected == null) return;
    switch (selected) {
      case 'edit':
        openOrderInWorkspaceTab(
          context,
          db: db,
          editCommandeId: (order['id'] as num?)?.toInt(),
          onSaved: _refreshClientData,
        );
      case 'payment':
        final clientData = _cachedData != null && _cachedData!.isNotEmpty
            ? _cachedData![0] as Map<String, dynamic>
            : <String, dynamic>{};
        final clientName =
            '${clientData['firstname'] ?? ''} ${clientData['lastname'] ?? ''}'
                .trim();
        _showAddPaymentDialog(
          context,
          order['id'] as int,
          orderRemaining,
          clientName,
          (order['order_code'] as num?)?.toInt() ??
              (order['display_number'] as num?)?.toInt(),
        );
      case 'delivery':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PartialProformaScreen(
              order: order,
              documentTitleKey: 'doc_bon_livraison_partiel',
            ),
          ),
        ).then((_) => _refreshClientData());
    }
  }

  Future<void> _openOrderDeliveryPreview(
    Map<String, dynamic> order,
    AppLanguage lang,
  ) async {
    final orderId = (order['id'] as num?)?.toInt() ?? 0;
    if (orderId <= 0) return;

    List<Map<String, dynamic>> rawItems = [];
    try {
      rawItems = await db.readCommandeDetails(orderId);
    } catch (_) {}

    final workshop = await DevisBuilder.loadWorkshopInfo().timeout(
      const Duration(seconds: 10),
      onTimeout: () => DevisWorkshopInfo.empty,
    );

    final status = (order['status'] ?? '').toString();
    final bool isPartial = status == 'Partial Distribution';

    final devis = await DevisBuilder.build(
      order: order,
      items: rawItems,
      workshop: workshop,
      isPartial: isPartial,
      documentTitleKey: isPartial
          ? 'doc_bon_livraison_partiel'
          : 'doc_bon_livraison',
    );

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DevisPreviewScreen(data: devis, initialIsLoaded: true),
      ),
    ).then((_) => _refreshClientData());
  }

  String _formatDateTime(String? date) {
    if (date == null || date.isEmpty) return '—';
    try {
      final dt = DateTime.parse(date);
      return DateFormat('yyyy/MM/dd HH:mm').format(dt);
    } catch (_) {
      return date;
    }
  }

  Future<void> _quickDeliverWindowUnit(
    Map<String, dynamic> unit,
    AppLanguage lang,
  ) async {
    final isFr = lang == AppLanguage.french;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.outbox, color: Colors.green),
            const SizedBox(width: 8),
            Text(
              isFr
                  ? 'Valider la sortie de la fenêtre'
                  : 'تأكيد خروج وتسليم النافذة',
            ),
          ],
        ),
        content: Text(
          isFr
              ? 'Confirmez-vous que le client a bien pris cette fenêtre (${unit['window_type']} #${unit['unit_number']}) ? Le statut de la commande sera mis à jour.'
              : 'هل تؤكد استلام وأخذ الزبون لهذه النافذة (${unit['window_type']} رقم ${unit['unit_number']}) فعلياً من الورشة؟ سيتم تحديث حالة الطلبية وتسجيل التسليم.',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isFr ? 'Annuler' : 'إلغاء'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check, size: 18),
            label: Text(
              isFr ? 'Confirmer' : 'تأكيد التسليم',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final allocId = (unit['allocation_id'] as num?)?.toInt();
      final orderId = (unit['order_id'] as num?)?.toInt() ?? 0;
      final detailId = (unit['detail_id'] as num?)?.toInt() ?? 0;

      if (allocId != null && allocId > 0) {
        await db.updateWorkerAllocationTransfer(allocId, 1);
      } else {
        await db.markItemsAllocationsTransferred(orderId, [
          {'id': detailId},
        ]);
        await db.recordAllocationDeliveryNote(orderId, {
          'id': detailId,
          'window_type': unit['window_type'],
          'largeur': unit['largeur'],
          'hauteur': unit['hauteur'],
          'quantity': 1,
        });
        await db.syncOrderAndAllocationsStatus(orderId);
      }

      CloudSyncService().notifyChange();
      _refreshClientData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFr
                  ? 'Fenêtre marquée comme livrée au client !'
                  : 'تم تأكيد خروج النافذة وتسليمها للزبون!',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء تأكيد تسليم النافذة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildClientItemsDeliverySection(
    List<Map<String, dynamic>> clientItems,
    List<Map<String, dynamic>> orders,
    AppLanguage lang,
  ) {
    String tr(String ar, String fr) {
      if (lang == AppLanguage.french) return fr;
      return Localization.translate(ar, lang);
    }

    if (clientItems.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Map<String, dynamic>> units = [];
    final Map<int, List<Map<String, dynamic>>> detailGroups = {};
    for (final row in clientItems) {
      final detailId = (row['detail_id'] as num?)?.toInt() ?? 0;
      detailGroups.putIfAbsent(detailId, () => []).add(row);
    }

    for (final entry in detailGroups.entries) {
      final rows = entry.value;
      final first = rows.first;
      final int qty = (first['quantity'] as num?)?.toInt() ?? 1;
      final bool hasAllocations = rows.any((r) => r['allocation_id'] != null);

      if (hasAllocations) {
        int uIdx = 1;
        for (final r in rows) {
          if (r['allocation_id'] == null) continue;
          final int allocUnitIndex = (r['unit_index'] as num?)?.toInt() ?? uIdx;
          final bool isTransferred =
              (r['is_transferred_to_dist'] as num?)?.toInt() == 1;
          final bool isFullDist =
              r['order_status'] == 'Full Distribution' ||
              r['order_status'] == 'Livré';
          final bool isDelivered = isTransferred || isFullDist;

          units.add({
            'detail_id': first['detail_id'],
            'order_id': first['id_commandes'],
            'order_code': _displayOrderNum(first),
            'project_name': (first['project_name'] ?? '').toString(),
            'order_date': (first['order_date'] ?? '').toString(),
            'order_status': (first['order_status'] ?? '').toString(),
            'window_type': (first['window_type'] ?? 'نافذة').toString(),
            'largeur': first['largeur'] ?? 0,
            'hauteur': first['hauteur'] ?? 0,
            'unit_number': allocUnitIndex,
            'total_units': qty,
            'is_delivered': isDelivered,
            'delivered_at': r['transferred_at']?.toString(),
            'allocation_id': r['allocation_id'],
            'image_path': first['drawing_image_path']?.toString(),
          });
          uIdx++;
        }
      } else {
        final int deliveredQty = (first['delivered_qty'] as num?)?.toInt() ?? 0;
        final bool isFullDist =
            first['order_status'] == 'Full Distribution' ||
            first['order_status'] == 'Livré';
        for (int i = 1; i <= qty; i++) {
          final bool isDelivered = isFullDist || (i <= deliveredQty);
          units.add({
            'detail_id': first['detail_id'],
            'order_id': first['id_commandes'],
            'order_code': _displayOrderNum(first),
            'project_name': (first['project_name'] ?? '').toString(),
            'order_date': (first['order_date'] ?? '').toString(),
            'order_status': (first['order_status'] ?? '').toString(),
            'window_type': (first['window_type'] ?? 'نافذة').toString(),
            'largeur': first['largeur'] ?? 0,
            'hauteur': first['hauteur'] ?? 0,
            'unit_number': i,
            'total_units': qty,
            'is_delivered': isDelivered,
            'delivered_at': isDelivered
                ? (first['order_date']?.toString())
                : null,
            'allocation_id': null,
            'image_path': first['drawing_image_path']?.toString(),
          });
        }
      }
    }

    final totalCount = units.length;
    final deliveredCount = units.where((u) => u['is_delivered'] == true).length;
    final missingCount = totalCount - deliveredCount;

    List<Map<String, dynamic>> filteredUnits = units;
    if (_deliveryFilterIndex == 1) {
      filteredUnits = units.where((u) => u['is_delivered'] == false).toList();
    } else if (_deliveryFilterIndex == 2) {
      filteredUnits = units.where((u) => u['is_delivered'] == true).toList();
    }

    return _SectionCard(
      title: tr(
        'متابعة تسليم النوافذ والعناصر',
        'Suivi de livraison des fenêtres',
      ),
      icon: Icons.window_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  title: tr('إجمالي النوافذ', 'Total fenêtres'),
                  count: totalCount,
                  color: Colors.blueGrey,
                  icon: Icons.grid_view_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  title: tr('أخذها الزبون', 'Livrées / Prises'),
                  count: deliveredCount,
                  color: Colors.green,
                  icon: Icons.check_circle_outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  title: tr('ينقصه / في الورشة', 'Restantes (Manque)'),
                  count: missingCount,
                  color: missingCount > 0 ? Colors.orange : Colors.grey,
                  icon: Icons.pending_actions_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: missingCount > 0
                  ? const Color(0xFFFFF3E0)
                  : const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: missingCount > 0
                    ? const Color(0xFFFFB74D)
                    : const Color(0xFF81C784),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  missingCount > 0
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: missingCount > 0
                      ? Colors.orange.shade900
                      : Colors.green.shade800,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    missingCount > 0
                        ? tr(
                            'تنبيه للورشة: ينقص الزبون استلام $missingCount نافذة/عنصر لإكمال طلبياته.',
                            'Attention atelier: Il manque $missingCount fenêtre(s) à livrer au client pour compléter ses commandes.',
                          )
                        : tr(
                            'تم تسليم جميع النوافذ والعناصر للزبون بالكامل ($totalCount نافذة).',
                            'Toutes les fenêtres et éléments ont été livrés au client avec succès ($totalCount fenêtres).',
                          ),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: missingCount > 0
                          ? Colors.orange.shade900
                          : Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(tr('الكل ($totalCount)', 'Toutes ($totalCount)')),
                  selected: _deliveryFilterIndex == 0,
                  onSelected: (_) => setState(() => _deliveryFilterIndex = 0),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(
                    tr(
                      'ينقصه / لم يأخذ ($missingCount)',
                      'En attente ($missingCount)',
                    ),
                    style: TextStyle(
                      color: _deliveryFilterIndex == 1
                          ? Colors.white
                          : Colors.orange.shade900,
                    ),
                  ),
                  selectedColor: Colors.orange.shade700,
                  selected: _deliveryFilterIndex == 1,
                  onSelected: (_) => setState(() => _deliveryFilterIndex = 1),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(
                    tr(
                      'أخذها الزبون ($deliveredCount)',
                      'Livrées ($deliveredCount)',
                    ),
                    style: TextStyle(
                      color: _deliveryFilterIndex == 2
                          ? Colors.white
                          : Colors.green.shade900,
                    ),
                  ),
                  selectedColor: Colors.green.shade700,
                  selected: _deliveryFilterIndex == 2,
                  onSelected: (_) => setState(() => _deliveryFilterIndex = 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (filteredUnits.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  tr('لا توجد عناصر مطابقة', 'Aucun élément correspondant'),
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredUnits.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final u = filteredUnits[idx];
                final bool isDelivered = u['is_delivered'] == true;
                final String? imgPath = u['image_path'];
                final hasImage =
                    imgPath != null &&
                    imgPath.isNotEmpty &&
                    File(imgPath).existsSync();

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDelivered
                              ? Colors.green.shade50
                              : Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDelivered
                                ? Colors.green.shade200
                                : Colors.amber.shade200,
                          ),
                        ),
                        child: hasImage
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: Image.file(
                                  File(imgPath),
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Icon(
                                isDelivered
                                    ? Icons.check_circle
                                    : Icons.crop_square,
                                color: isDelivered
                                    ? Colors.green.shade700
                                    : Colors.amber.shade800,
                                size: 24,
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${tr('نافذة', 'Fenêtre')} #${u['unit_number']} · ${u['window_type']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDelivered
                                        ? Colors.green.shade50
                                        : Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isDelivered
                                          ? Colors.green.shade300
                                          : Colors.orange.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    isDelivered
                                        ? tr('✅ أخذ النافذة', 'Livrée')
                                        : tr(
                                            '⏳ لم يأخذ بعد (ينقصه)',
                                            'Non livrée',
                                          ),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDelivered
                                          ? Colors.green.shade800
                                          : Colors.orange.shade900,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${tr('القياس', 'Dimensions')}: ${u['largeur']} × ${u['hauteur']} مم · ${tr('طلب', 'Cmd')} #${u['order_code']}${u['project_name'].isNotEmpty ? ' (${u['project_name']})' : ''}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            if (isDelivered &&
                                u['delivered_at'] != null &&
                                u['delivered_at'].toString().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${tr('تاريخ ووقت الخروج: ', 'Sortie le: ')}${_formatDateTime(u['delivered_at'])}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!isDelivered) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.outbox, color: Colors.teal),
                          tooltip: tr(
                            'تأكيد خروج النافذة وتسليمها',
                            'Valider la sortie de cette fenêtre',
                          ),
                          onPressed: () => _quickDeliverWindowUnit(u, lang),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blueGrey.shade800,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Cairo',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
              fontFamily: 'Cairo',
            ),
          ),
        ],
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
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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
