import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';

import '../Commande/Systeme/shutter_calc_rules.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';

/// The workshop's tunnel shutter calculations: axe per console, blade
/// length and count, rail length. The brush joint always takes twice the
/// rails' length.
class TunnelCalcRulesCard extends StatefulWidget {
  const TunnelCalcRulesCard({super.key});

  /// Shown where the tunnel box is set: a box fitted off standard changes
  /// the axe length only.
  static const nonStandardWarning =
      'تنبيه: إذا رُكّب صندوق النفق خارج المعايير القانونية، قد يتغير حساب المحور فقط. راجع خصم المحور في إعدادات صندوق النفق.';

  @override
  State<TunnelCalcRulesCard> createState() => _TunnelCalcRulesCardState();
}

class _TunnelCalcRulesCardState extends State<TunnelCalcRulesCard> {
  static const _fields = <(String, String)>[
    (ShutterCalcRules.tunnelAxeStandard, 'خصم المحور مع كونسول ستاندار (مم)'),
    (ShutterCalcRules.tunnelAxeSpecial, 'خصم المحور مع كونسول سبيسيال (مم)'),
    (ShutterCalcRules.tunnelBladeDeduction, 'خصم طول الشفرة (مم)'),
    (
      ShutterCalcRules.tunnelBladeHeightAdd,
      'إضافة إلى الارتفاع لعدد الشفرات (مم)',
    ),
    (ShutterCalcRules.tunnelExtraBlades, 'شفرات إضافية'),
    (ShutterCalcRules.tunnelRailAdd, 'إضافة إلى طول السكة (مم)'),
  ];

  late final Map<String, TextEditingController> _controllers = {
    for (final (key, _) in _fields)
      key: TextEditingController(text: _format(ShutterCalcRules.value(key))),
  };
  // The default console of each tunnel height (1 Standard, 2 Special).
  final Map<int, int> _consoles = {
    for (final height in ShutterCalcRules.tunnelHeights)
      height: ShutterCalcRules.defaultTunnelConsole(height.toDouble()),
  };
  bool _saving = false;

  static String _format(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';

  @override
  void initState() {
    super.initState();
    // Values saved on another device may have arrived since startup.
    ShutterCalcRules.load(SqlDatabase()).then((_) {
      if (!mounted) return;
      setState(() {
        for (final (key, _) in _fields) {
          _controllers[key]!.text = _format(ShutterCalcRules.value(key));
        }
        for (final height in ShutterCalcRules.tunnelHeights) {
          _consoles[height] = ShutterCalcRules.defaultTunnelConsole(
            height.toDouble(),
          );
        }
      });
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save(AppLanguage lang) async {
    final values = <String, double>{};
    for (final (key, _) in _fields) {
      final parsed = double.tryParse(
        _controllers[key]!.text.trim().replaceAll(',', '.'),
      );
      if (parsed != null) values[key] = parsed;
    }
    for (final entry in _consoles.entries) {
      values[ShutterCalcRules.tunnelConsoleForHeight(entry.key)] = entry.value
          .toDouble();
    }
    setState(() => _saving = true);
    await ShutterCalcRules.save(SqlDatabase(), values);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Localization.translate('تم حفظ حسابات ستار النفق', lang)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppSettingsProvider>().language;
    String t(String key) => Localization.translate(key, lang);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('حسابات ستار النفق'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              t(
                'المحور = العرض − خصم الكونسول. الشفرة والشفرة النهائية = العرض − خصم الشفرة. عدد الشفرات = (الارتفاع + الإضافة) ÷ ارتفاع الشفرة + الشفرات الإضافية، والارتفاع يُقاس تحت النفق. السكة = الارتفاع + الإضافة، وجوان الفرشاة = طول السكك مرتين.',
              ),
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (key, label) in _fields)
                  SizedBox(
                    width: 250,
                    child: TextField(
                      controller: _controllers[key],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: t(label),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              t('الكونسول الافتراضي لكل ارتفاع نفق'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final height in ShutterCalcRules.tunnelHeights)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(width: 90, child: Text('${height ~/ 10} cm')),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final group in const [1, 2])
                            ChoiceChip(
                              label: Text(
                                t(
                                  group == 1
                                      ? 'كونسول ستاندار'
                                      : 'كونسول سبيسيال',
                                ),
                              ),
                              selected: _consoles[height] == group,
                              onSelected: (_) =>
                                  setState(() => _consoles[height] = group),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: _saving ? null : () => _save(lang),
                icon: const Icon(Icons.save_rounded),
                label: Text(t('حفظ')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
