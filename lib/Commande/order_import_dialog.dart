import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';
import 'order_export_service.dart';

class OrderImportDialog extends StatefulWidget {
  final Map<String, dynamic> payload;
  final SqlDatabase db;
  final VoidCallback? onImported;

  const OrderImportDialog({
    super.key,
    required this.payload,
    required this.db,
    this.onImported,
  });

  @override
  State<OrderImportDialog> createState() => _OrderImportDialogState();
}

class _OrderImportDialogState extends State<OrderImportDialog> {
  bool _isLoading = true;
  bool _isImporting = false;
  int? _selectedClientId; // null = use matching or create new

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  Future<void> _loadClients() async {
    try {
      final clientData = Map<String, dynamic>.from(widget.payload['client'] ?? {});
      final matching = await OrderExportService.findMatchingClient(widget.db, clientData);

      if (mounted) {
        setState(() {
          if (matching != null && matching['id'] != null) {
            _selectedClientId = (matching['id'] as num).toInt();
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _t(String key, AppLanguage lang) {
    return Localization.translate(key, lang);
  }

  Future<void> _doImport(AppLanguage lang) async {
    setState(() => _isImporting = true);
    try {
      final newOrderId = await OrderExportService.importOrder(
        widget.db,
        widget.payload,
        selectedClientId: _selectedClientId,
      );

      if (!mounted) return;
      Navigator.pop(context, newOrderId);

      widget.onImported?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('order_imported_successfully', lang)),
          backgroundColor: Colors.green[700],
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_t('Erreur', lang)}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final clientData = Map<String, dynamic>.from(widget.payload['client'] ?? {});
    final orderData = Map<String, dynamic>.from(widget.payload['order'] ?? {});
    final items = List<dynamic>.from(widget.payload['items'] ?? []);
    final sourceWorkshop = widget.payload['source_workshop']?.toString().trim() ?? '';

    final firstName = clientData['firstname']?.toString() ?? '';
    final lastName = clientData['lastname']?.toString() ?? '';
    final clientName = '$firstName $lastName'.trim();
    final phone1 = clientData['phone1']?.toString() ?? '';
    final address = clientData['address']?.toString() ?? '';

    final total = (orderData['total'] as num?)?.toDouble() ?? 0.0;
    final netPayable = (orderData['net_payable'] as num?)?.toDouble() ?? total;
    final remise = (orderData['remise'] as num?)?.toDouble() ?? 0.0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(20),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withAlpha(30),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.file_download_outlined,
                          color: Colors.blue,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _t('import_order_preview', lang),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (sourceWorkshop.isNotEmpty)
                              Text(
                                '${_t('source_workshop', lang)}: $sourceWorkshop',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  // Content Body
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 👤 Client Section Card
                          Card(
                            elevation: 0,
                            color: isDark
                                ? Colors.grey[850]
                                : const Color(0xFFF1F5F9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.person_rounded,
                                        size: 18,
                                        color: Colors.blue,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _t('select_or_create_client', lang),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    clientName.isEmpty
                                        ? _t('الزبون غير محدد', lang)
                                        : clientName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (phone1.isNotEmpty)
                                    Text(
                                      '${Localization.translate('Téléphone', lang)}: $phone1',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  if (address.isNotEmpty)
                                    Text(
                                      '${Localization.translate('Adresse', lang)}: $address',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  if (_selectedClientId != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withAlpha(30),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.check_circle_outline,
                                            size: 14,
                                            color: Colors.green,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _t('client_match_found', lang),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.green,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withAlpha(30),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.person_add_alt,
                                            size: 14,
                                            color: Colors.blue,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _t(
                                              'new_client_will_be_created',
                                              lang,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.blue,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 💰 Financial Overview Card
                          Card(
                            elevation: 0,
                            color: isDark
                                ? Colors.grey[850]
                                : const Color(0xFFF1F5F9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  Column(
                                    children: [
                                      Text(
                                        _t('order_items_count', lang),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${items.length}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (remise > 0)
                                    Column(
                                      children: [
                                        Text(
                                          _t('Remise', lang),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${remise.toStringAsFixed(2)} DZD',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  Column(
                                    children: [
                                      Text(
                                        Localization.translate(
                                          'Net à payer',
                                          lang,
                                        ),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${netPayable.toStringAsFixed(2)} DZD',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 🪟 Items List
                          Text(
                            Localization.translate('Détails', lang),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final it = Map<String, dynamic>.from(
                                items[i] as Map,
                              );
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.blue.withAlpha(30),
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  '${it['game'] ?? ''} - ${it['largeur']} × ${it['hauteur']} mm',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  '${Localization.translate('Quantité', lang)}: ${it['quantity']} | ${Localization.translate('Prix', lang)}: ${it['price'] ?? 0} DZD',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  // Bottom Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isImporting
                            ? null
                            : () => Navigator.pop(context),
                        child: Text(Localization.translate('cancel', lang)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: _isImporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.file_download_done_rounded,
                                size: 18,
                              ),
                        label: Text(
                          _t('confirm_import', lang),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: _isImporting ? null : () => _doImport(lang),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
