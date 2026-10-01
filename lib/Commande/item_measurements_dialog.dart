import 'dart:convert';
import 'measurement_progress.dart';
import 'package:flutter/material.dart';
import '../settings/app_settings.dart';
import 'order_measurements_confirm_screen.dart';

class ItemMeasurementsDialog extends StatelessWidget {
  final Map<String, dynamic> detail;
  final AppLanguage language;
  final bool canConfirm;
  final bool isSaved;
  final bool embedded;

  const ItemMeasurementsDialog({
    super.key,
    required this.detail,
    required this.language,
    required this.canConfirm,
    required this.isSaved,
    this.embedded = false,
  });

  String tr(String ar, String fr, String en) => language == AppLanguage.arabic
      ? ar
      : language == AppLanguage.french
      ? fr
      : en;

  List<dynamic> readRows(dynamic value) {
    try {
      final decoded = value is String ? jsonDecode(value) : value;
      return decoded is List ? decoded : [];
    } catch (_) {
      return [];
    }
  }

  Widget _measurementAndStatus(Widget measurement, Widget? status) {
    if (status == null) return measurement;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [measurement, const SizedBox(height: 8), status],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: measurement),
            const SizedBox(width: 32),
            Expanded(flex: 3, child: status),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final quantity = measurementQuantityValue(detail['quantity'], fallback: 1);
    final confirmed = readRows(detail['confirmed_mesures_json'])
        .where(
          (row) =>
              row is Map &&
              measurementQuantityValue(row['width'] ?? row['largeur']) > 0 &&
              measurementQuantityValue(row['height'] ?? row['hauteur']) > 0,
        )
        .toList();
    final complete = quantity > 0 && confirmed.length == quantity;
    String position = '';
    try {
      final raw = detail['partitions_json'];
      final model = raw is String ? jsonDecode(raw) : raw;
      if (model is Map) position = model['position']?.toString() ?? '';
    } catch (_) {}
    final rows = normalizeMeasurementInstances(
      originalQuantity: quantity,
      originalWidth: measurementQuantityValue(detail['largeur']),
      originalHeight: measurementQuantityValue(detail['hauteur']),
      defaultPosition: position,
      savedInstances: confirmed.isEmpty
          ? readRows(detail['instances_json'])
          : [],
      confirmedInstances: confirmed,
    );
    if (confirmed.isNotEmpty && confirmed.length < quantity) {
      rows.add({
        'width': measurementQuantityValue(detail['largeur']),
        'height': measurementQuantityValue(detail['hauteur']),
        'qty': quantity - confirmed.length,
        'position': position,
        'pending': true,
      });
    }
    final rawAllocations = detail['measurement_allocations'];
    final allocations = rawAllocations is List
        ? rawAllocations
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : <Map<String, dynamic>>[];
    Set<int> indicesFor(Map<String, dynamic> row) {
      final indices = <int>{};
      for (var index = 0; index < confirmed.length; index++) {
        final unit = confirmed[index] as Map;
        if (measurementQuantityValue(unit['width'] ?? unit['largeur']) ==
                row['width'] &&
            measurementQuantityValue(unit['height'] ?? unit['hauteur']) ==
                row['height'] &&
            (unit['position'] ?? position).toString() == row['position']) {
          indices.add(index + 1);
        }
      }
      return indices;
    }

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          complete
              ? tr(
                  'القياسات مؤكدة',
                  'Mesures confirmées',
                  'Measurements confirmed',
                )
              : tr(
                  'المؤكد: ${confirmed.length} من $quantity',
                  'Confirmées : ${confirmed.length} sur $quantity',
                  'Confirmed: ${confirmed.length} of $quantity',
                ),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: complete ? Colors.green : Colors.orange,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            const Divider(
              height: 20,
              thickness: 0.8,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _measurementAndStatus(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${rows[i]['width']} × ${rows[i]['height']} ${tr('مم', 'mm', 'mm')}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            tr(
                              'الكمية: ${rows[i]['qty']}',
                              'Quantité : ${rows[i]['qty']}',
                              'Quantity: ${rows[i]['qty']}',
                            ),
                            if (rows[i]['position'].toString().isNotEmpty)
                              tr(
                                'الموقع: ${rows[i]['position']}',
                                'Emplacement : ${rows[i]['position']}',
                                'Location: ${rows[i]['position']}',
                              ),
                            if (confirmed.isEmpty ||
                                rows[i]['pending'] == true)
                              tr(
                                'غير مؤكدة — قياسات أولية',
                                'Non confirmées — mesures initiales',
                                'Unconfirmed — initial measurements',
                              ),
                          ].join('\n'),
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              rawAllocations is List && rows.length > 1
                  ? MeasurementProgress(
                      allocations: allocations,
                      quantity: measurementQuantityValue(rows[i]['qty']),
                      language: language,
                      unitIndices: indicesFor(rows[i]),
                    )
                  : null,
            ),
          ),
        ],
        if (rawAllocations is List) ...[
          const SizedBox(height: 12),
          const Divider(thickness: 1.2),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('حالة العنصر', 'État de l’élément', 'Item status'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                MeasurementProgress(
                  allocations: allocations,
                  quantity: quantity,
                  language: language,
                ),
              ],
            ),
          ),
        ],
        if (!isSaved)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr(
                'احفظ الطلبية أولاً لتأكيد القياسات.',
                'Enregistrez la commande avant de confirmer les mesures.',
                'Save the order before confirming measurements.',
              ),
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
      ],
    );

    final content = SizedBox(
      width: embedded ? double.infinity : 1000,
      child: embedded
          ? body
          : SingleChildScrollView(child: body),
    );
    if (embedded) return content;
    return Directionality(
      textDirection: language == AppLanguage.arabic
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: AlertDialog(
        title: Text(
          tr('عرض القياسات', 'Voir les mesures', 'View measurements'),
        ),
        content: content,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('إغلاق', 'Fermer', 'Close')),
          ),
          if (!complete && canConfirm)
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(
                tr(
                  'تأكيد القياسات',
                  'Confirmer les mesures',
                  'Confirm measurements',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
