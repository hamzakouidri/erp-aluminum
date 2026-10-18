import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/Commande/Systeme/model.dart';

/// Aluminium opening parclose cutting choice, shared by the drawing panel and
/// the quantity/cost table. See [WindowModel.parcloseCutMode].
class ParcloseCutModeSelector extends StatelessWidget {
  final WindowModel model;
  final bool dense;

  const ParcloseCutModeSelector({
    super.key,
    required this.model,
    this.dense = false,
  });

  /// Aluminium windows with an opening parclose only.
  static bool isAvailableFor(WindowModel model) =>
      !model.isPVC && model.canUseOpeningOnlyOptions;

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    String t(String ar, String fr) => lang == AppLanguage.arabic ? ar : fr;

    final options = <(String, String)>[
      ('45', t('قطع 45°', 'Coupe 45°')),
      ('90_length', t('90° الأولوية للطول', '90° priorité hauteur')),
      ('90_width', t('90° الأولوية للعرض', '90° priorité largeur')),
    ];
    final mode = model.parcloseCutMode;
    final String hint = switch (mode) {
      '90_length' => t(
        'القطع الطولية = الفراغ الداخلي، والعرضية = الفراغ الداخلي − 2 × ركوب الزجاج للباركلوز',
        'Montants = clair intérieur, traverses = clair − 2 × déduction vitrage de la parclose',
      ),
      '90_width' => t(
        'القطع العرضية = الفراغ الداخلي، والطولية = الفراغ الداخلي − 2 × ركوب الزجاج للباركلوز',
        'Traverses = clair intérieur, montants = clair − 2 × déduction vitrage de la parclose',
      ),
      _ => t(
        'كل القطع بمقاس الفراغ الداخلي (مثل PVC)',
        'Toutes les coupes au clair intérieur (comme le PVC)',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          t('قطع الباركلوز (Parclose)', 'Coupe parclose'),
          style: TextStyle(
            fontSize: dense ? 12 : 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (value, label) in options)
              ChoiceChip(
                label: Text(label, style: TextStyle(fontSize: dense ? 11 : 12)),
                selected: mode == value,
                visualDensity: dense ? VisualDensity.compact : null,
                onSelected: (_) => model.setParcloseCutMode(value),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: TextStyle(fontSize: dense ? 10 : 11, color: Colors.grey),
        ),
      ],
    );
  }
}
