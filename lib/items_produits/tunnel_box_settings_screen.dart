import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../widgets/tunnel_calc_rules_card.dart';

/// The workshop's tunnel box (caisson tunnel) settings: its shutter
/// calculations and the default console of each tunnel height.
class TunnelBoxSettingsScreen extends StatelessWidget {
  const TunnelBoxSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppSettingsProvider>().language;
    String t(String key) => Localization.translate(key, lang);
    return Scaffold(
      appBar: AppBar(title: Text(t('صندوق النفق (Caisson Tunnel)'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: Colors.amber.shade50,
            child: ListTile(
              leading: Icon(
                Icons.warning_amber_rounded,
                color: Colors.amber.shade900,
              ),
              title: Text(t(TunnelCalcRulesCard.nonStandardWarning)),
            ),
          ),
          const TunnelCalcRulesCard(),
        ],
      ),
    );
  }
}
