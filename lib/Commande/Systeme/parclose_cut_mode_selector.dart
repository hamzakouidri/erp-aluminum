import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
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
    final rule = model.parcloseCutRule;
    final mode = model.parcloseCutMode;
    final hint = Localization.translate('parclose_cut_hint_$mode', lang);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          Localization.translate('parclose_cut_title', lang),
          style: TextStyle(
            fontSize: dense ? 12 : 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        // A parclose taking one cut only leaves nothing to choose.
        if (rule.isFixed)
          Text(
            '${Localization.translate('parclose_cut_$mode', lang)} · '
            '${Localization.translate('parclose_cut_fixed_by_profile', lang)}',
            style: TextStyle(
              fontSize: dense ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final value in rule.allowedModes)
                ChoiceChip(
                  label: Text(
                    Localization.translate('parclose_cut_$value', lang),
                    style: TextStyle(fontSize: dense ? 11 : 12),
                  ),
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
        if (model.parcloseCutAt90)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: dense,
            value: model.parcloseCornerCaps,
            onChanged: model.setParcloseCornerCaps,
            title: Text(
              Localization.translate('parclose_corner_caps_title', lang),
              style: TextStyle(fontSize: dense ? 12 : 13),
            ),
            subtitle: Text(
              Localization.translate('parclose_corner_caps_hint', lang),
              style: TextStyle(fontSize: dense ? 10 : 11),
            ),
          ),
      ],
    );
  }
}

/// The parclose cut rule of a catalogue profile: the cuts it takes and the
/// cut a new drawing starts with. See [ParcloseCutRule].
class ParcloseCutRuleFields extends StatelessWidget {
  final ParcloseCutRule rule;
  final ValueChanged<ParcloseCutRule> onChanged;

  const ParcloseCutRuleFields({
    super.key,
    required this.rule,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    String tr(String key) => Localization.translate(key, lang);

    DropdownMenuItem<String> item(String value, String key) =>
        DropdownMenuItem(value: value, child: Text(tr(key)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: rule.support,
          decoration: InputDecoration(
            labelText: tr('parclose_cut_support_label'),
          ),
          items: [
            for (final support in const ['both', '45', '90'])
              item(support, 'parclose_cut_support_$support'),
          ],
          onChanged: (support) {
            if (support == null) return;
            onChanged(
              ParcloseCutRule(
                support: support,
                defaultMode: switch (support) {
                  '45' => '45',
                  '90' when rule.defaultMode == '45' => '90_length',
                  _ => rule.defaultMode,
                },
              ),
            );
          },
        ),
        if (!rule.isFixed || rule.support == '90') ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // The key rebuilds the field when the support changes its
            // possible values.
            key: ValueKey('parclose_default_${rule.support}'),
            initialValue: rule.initialMode,
            decoration: InputDecoration(
              labelText: tr(
                rule.support == '90'
                    ? 'parclose_cut_priority_label'
                    : 'parclose_cut_default_label',
              ),
            ),
            items: [
              for (final mode in ParcloseCutRule.modes)
                if (rule.support != '90' || mode != '45')
                  item(mode, 'parclose_cut_$mode'),
            ],
            onChanged: (mode) {
              if (mode == null) return;
              onChanged(
                ParcloseCutRule(support: rule.support, defaultMode: mode),
              );
            },
          ),
        ],
      ],
    );
  }
}
