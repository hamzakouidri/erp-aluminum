import 'package:flutter/material.dart';
import '../settings/app_settings.dart';

int _number(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
bool _done(dynamic value) => value == true || _number(value) == 1;

/// Counts only the allocations explicitly belonging to this measurement.
/// Unindexed allocations can only be attributed when there is a single group.
({
  int manufactured,
  int glass,
  int distributed,
  int installed,
  int reserved,
  int completed,
  bool unknown,
})
measurementProgress({
  required List<Map<String, dynamic>> allocations,
  required int quantity,
  Set<int>? unitIndices,
  bool singleGroup = false,
}) {
  var manufactured = 0;
  var glass = 0;
  var distributed = 0;
  var installed = 0;
  var reserved = 0;
  var completed = 0;
  var unknown = false;
  for (final allocation in allocations) {
    final index = _number(allocation['unit_index']);
    if (unitIndices != null) {
      if (index <= 0 && !singleGroup) {
        unknown = true;
        continue;
      }
      if (index > 0 && !unitIndices.contains(index)) continue;
    }
    final count = _number(allocation['quantity']);
    if (count <= 0) continue;
    if (_done(allocation['is_manufactured'])) manufactured += count;
    if (_done(allocation['is_glass_installed'])) glass += count;
    if (_done(allocation['is_distributed']) ||
        _done(allocation['is_transferred_to_dist']))
      distributed += count;
    if (_done(allocation['is_installed'])) installed += count;
    if (_done(allocation['has_reserve']) && !_done(allocation['is_completed']))
      reserved += count;
    if (_done(allocation['is_completed'])) completed += count;
  }
  return (
    manufactured: manufactured.clamp(0, quantity),
    glass: glass.clamp(0, quantity),
    distributed: distributed.clamp(0, quantity),
    installed: installed.clamp(0, quantity),
    reserved: reserved.clamp(0, quantity),
    completed: completed.clamp(0, quantity),
    unknown: unknown,
  );
}

class MeasurementProgress extends StatelessWidget {
  final List<Map<String, dynamic>> allocations;
  final int quantity;
  final AppLanguage language;
  final Set<int>? unitIndices;
  final bool singleGroup;

  const MeasurementProgress({
    super.key,
    required this.allocations,
    required this.quantity,
    required this.language,
    this.unitIndices,
    this.singleGroup = false,
  });

  String tr(String ar, String fr, String en) => language == AppLanguage.arabic
      ? ar
      : language == AppLanguage.french
      ? fr
      : en;

  @override
  Widget build(BuildContext context) {
    final progress = measurementProgress(
      allocations: allocations,
      quantity: quantity,
      unitIndices: unitIndices,
      singleGroup: singleGroup,
    );
    Widget status(
      IconData icon,
      int count,
      String done,
      String pending,
      String partial, {
      String? title,
      bool reserve = false,
    }) {
      final complete = quantity > 0 && count == quantity;
      final label = complete
          ? done
          : progress.unknown
          ? tr(
              'غير محدد لهذا القياس',
              'Non précisé pour cette mesure',
              'Not specified for this measurement',
            )
          : count == 0
          ? pending
          : partial;
      return Chip(
        avatar: Icon(
          icon,
          size: 18,
          color: reserve
              ? (count > 0
                    ? Colors.red.shade700
                    : progress.unknown
                    ? Colors.orange.shade800
                    : Colors.green)
              : complete
              ? Colors.green
              : Colors.orange.shade800,
        ),
        label: Text(
          '${title ?? (icon == Icons.handyman_outlined ? tr('التصنيع', 'Fabrication', 'Manufacturing') : tr('الزجاج', 'Vitrage', 'Glass'))}: $label ($count / $quantity)',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            status(
              Icons.handyman_outlined,
              progress.manufactured,
              tr('مصنّعة', 'Fabriqué', 'Manufactured'),
              tr('غير مصنّعة', 'Non fabriqué', 'Not manufactured'),
              tr(
                'مصنّعة جزئياً',
                'Fabrication partielle',
                'Partially manufactured',
              ),
            ),
            status(
              Icons.window_outlined,
              progress.glass,
              tr('الزجاج مركّب', 'Vitrage posé', 'Glass installed'),
              tr('الزجاج غير مركّب', 'Vitrage non posé', 'Glass not installed'),
              tr(
                'الزجاج مركّب جزئياً',
                'Vitrage partiellement posé',
                'Glass partially installed',
              ),
            ),
            status(
              Icons.local_shipping_outlined,
              progress.distributed,
              tr('موزّعة', 'Distribué', 'Distributed'),
              tr('غير موزّعة', 'Non distribué', 'Not distributed'),
              tr(
                'موزّعة جزئياً',
                'Distribution partielle',
                'Partially distributed',
              ),
              title: tr('التوزيع', 'Distribution', 'Distribution'),
            ),
            status(
              Icons.home_repair_service_outlined,
              progress.installed,
              tr('مركّبة', 'Installé', 'Installed'),
              tr('غير مركّبة', 'Non installé', 'Not installed'),
              tr(
                'مركّبة جزئياً',
                'Installation partielle',
                'Partially installed',
              ),
              title: tr('التركيب', 'Installation', 'Installation'),
            ),
            status(
              Icons.report_problem_outlined,
              progress.reserved,
              tr('فيها تحفّظ', 'Avec réserves', 'Has reservations'),
              tr('لا توجد تحفّظات', 'Aucune réserve', 'No reservations'),
              tr(
                'تحفّظ على بعض القطع',
                'Réserves sur certaines pièces',
                'Some pieces have reservations',
              ),
              title: tr('التحفّظات', 'Réserves', 'Reservations'),
              reserve: true,
            ),
            status(
              Icons.task_alt,
              progress.completed,
              tr('منتهية', 'Terminé', 'Completed'),
              tr('غير منتهية', 'Non terminé', 'Not completed'),
              tr(
                'منتهية جزئياً',
                'Partiellement terminé',
                'Partially completed',
              ),
              title: tr('الانتهاء', 'Achèvement', 'Completion'),
            ),
          ],
        ),
        if (progress.unknown)
          Text(
            tr(
              'يوجد إسناد جماعي غير مرتبط بقياس محدد؛ راجع ملخص العنصر.',
              'Une affectation groupée ne précise pas la mesure ; voir le récapitulatif.',
              'A grouped allocation does not identify the measurement; see the item summary.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}
