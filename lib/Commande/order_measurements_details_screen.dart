import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../sql_database.dart';
import 'item_measurements_dialog.dart';
import 'order_measurements_confirm_screen.dart';

class OrderMeasurementsDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final SqlDatabase db;

  const OrderMeasurementsDetailsScreen({
    super.key,
    required this.orderData,
    required this.db,
  });

  @override
  State<OrderMeasurementsDetailsScreen> createState() =>
      _OrderMeasurementsDetailsScreenState();
}

class _OrderMeasurementsDetailsScreenState
    extends State<OrderMeasurementsDetailsScreen> {
  late Future<List<Map<String, dynamic>>> _details;

  @override
  void initState() {
    super.initState();
    _details = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await widget.db.readCommandeDetails(
      widget.orderData['id'] as int,
    );
    return Future.wait(
      rows.map(
        (row) async => <String, dynamic>{
          ...row,
          'measurement_allocations': await widget.db.readWorkerAllocations(
            row['id'] as int,
          ),
        },
      ),
    );
  }

  String tr(AppLanguage lang, String ar, String fr, String en) =>
      lang == AppLanguage.arabic
      ? ar
      : lang == AppLanguage.french
      ? fr
      : en;

  Future<void> _showMeasurements(
    Map<String, dynamic> detail,
    AppSettingsProvider settings,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => ItemMeasurementsDialog(
        detail: detail,
        language: settings.language,
        canConfirm: settings.canConfirmMeasurements(),
        isSaved: true,
      ),
    );
    if (confirm != true || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderMeasurementsConfirmScreen(
          orderData: widget.orderData,
          db: widget.db,
          initialDetailId: detail['id'] as int?,
        ),
      ),
    );
    if (mounted) setState(() => _details = _load());
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();
    final lang = settings.language;
    return Directionality(
      textDirection: lang == AppLanguage.arabic
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: tr(lang, 'تحديث', 'Actualiser', 'Refresh'),
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() => _details = _load()),
            ),
          ],
          title: Text(
            tr(
              lang,
              'تفاصيل قياسات الطلبية',
              'Détails des mesures',
              'Order measurement details',
            ),
          ),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _details,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done)
              return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError)
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr(
                        lang,
                        'تعذر تحميل القياسات',
                        'Impossible de charger les mesures',
                        'Could not load measurements',
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _details = _load()),
                      child: Text(
                        tr(lang, 'إعادة المحاولة', 'Réessayer', 'Retry'),
                      ),
                    ),
                  ],
                ),
              );
            final details = snapshot.data ?? [];
            if (details.isEmpty)
              return Center(
                child: Text(
                  tr(
                    lang,
                    'لا توجد عناصر في هذه الطلبية',
                    'Aucun élément dans cette commande',
                    'No items in this order',
                  ),
                ),
              );
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: details.length,
              itemBuilder: (context, index) {
                final detail = details[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${index + 1}. ${detail['game'] ?? ''}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: tr(
                                lang,
                                'عرض القياسات',
                                'Voir les mesures',
                                'View measurements',
                              ),
                              icon: const Icon(
                                Icons.straighten,
                                color: Colors.teal,
                              ),
                              onPressed: () =>
                                  _showMeasurements(detail, settings),
                            ),
                          ],
                        ),
                        const Divider(),
                        ItemMeasurementsDialog(
                          detail: detail,
                          language: lang,
                          canConfirm: false,
                          isSaved: true,
                          embedded: true,
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
    );
  }
}
