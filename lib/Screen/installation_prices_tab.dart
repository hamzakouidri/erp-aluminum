import 'package:database_data/Commande/Systeme/installation_fees.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sql_database.dart';
import 'price_management_screen.dart' show PriceEditRow;

/// Price page of the installation (labour) fees, apart from the price of
/// the parts: each fee belongs to one accessory, shutter component or kit,
/// or is one of the general fees (shutter, motor, crank, OB...).
class InstallationPricesTab extends StatefulWidget {
  final List<Map<String, dynamic>> accessories;
  final List<Map<String, dynamic>> shutterComponents;
  final List<Map<String, dynamic>> kits;

  /// `ShutterSqmPrices` rows by blade type, then colour id.
  final Map<String, Map<int, double>> prices;
  final bool canChangePrices;
  final VoidCallback onPriceSaved;

  const InstallationPricesTab({
    super.key,
    required this.accessories,
    required this.shutterComponents,
    required this.kits,
    required this.prices,
    required this.canChangePrices,
    required this.onPriceSaved,
  });

  @override
  State<InstallationPricesTab> createState() => _InstallationPricesTabState();
}

class _InstallationPricesTabState extends State<InstallationPricesTab> {
  final SqlDatabase _db = SqlDatabase();
  bool _enabled = true;
  bool _showOnDevis = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _enabled = prefs.getBool(InstallationFees.enabledPreference) ?? true;
      _showOnDevis =
          prefs.getBool(InstallationFees.showOnDevisPreference) ?? true;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  double _price(String key) => widget.prices[key]?[0] ?? 0.0;

  Future<void> _save(String key, double price) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    await _db.setInstallationPrice(key, price);
    widget.onPriceSaved();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
      ),
    );
  }

  bool _matches(Map<String, dynamic> row) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      row['name'],
      row['code'],
      row['type'],
      row['component_type'],
      row['description'],
    ].any((value) => (value ?? '').toString().toLowerCase().contains(query));
  }

  Widget _row({
    required String key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return PriceEditRow(
      key: ValueKey('install-$key'),
      title: title,
      subtitle: subtitle,
      titleIcon: Icon(icon, size: 18, color: color),
      currentPrice: _price(key),
      canChangePrices: widget.canChangePrices && _enabled,
      onSave: (price) => _save(key, price),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> rows,
    required AppLanguage lang,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                ),
                Text(
                  '${rows.length}',
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                Localization.translate('لا توجد نتائج مطابقة للبحث.', lang),
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++) ...[
              rows[i],
              if (i < rows.length - 1)
                Divider(height: 1, indent: 16, endIndent: 16),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    String tr(String key) => Localization.translate(key, lang);
    final perWindow = tr('لكل نافذة');
    final perUnit = tr('لكل وحدة');

    final general = <Widget>[
      _row(
        key: InstallationFees.shutterKey,
        title: tr('تركيب الستار'),
        subtitle: perWindow,
        icon: Icons.curtains_closed,
        color: Colors.deepPurple,
      ),
      _row(
        key: InstallationFees.motorKey,
        title: tr('تركيب المحرك'),
        subtitle: perWindow,
        icon: Icons.settings_input_component_outlined,
        color: Colors.deepOrange,
      ),
      _row(
        key: InstallationFees.crankKey,
        title: tr('تركيب المانيفال'),
        subtitle: perWindow,
        icon: Icons.rotate_right,
        color: Colors.green,
      ),
      _row(
        key: InstallationFees.obKey,
        title: tr('تركيب System OB'),
        subtitle: perWindow,
        icon: Icons.build_circle_outlined,
        color: Colors.blueGrey,
      ),
      _row(
        key: InstallationFees.demiObKey,
        title: tr('تركيب Demi System OB'),
        subtitle: perWindow,
        icon: Icons.build_circle_outlined,
        color: Colors.blueGrey,
      ),
      _row(
        key: InstallationFees.verrouKey,
        title: tr('تركيب Verrou Central'),
        subtitle: perWindow,
        icon: Icons.build_circle_outlined,
        color: Colors.blueGrey,
      ),
    ];

    List<Widget> rowsFor(
      List<Map<String, dynamic>> source,
      String Function(int id) keyOf,
      String subtitle,
      IconData icon,
      Color color,
    ) {
      final rows = <Widget>[];
      for (final row in source.where(_matches)) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null) continue;
        final name = (row['name'] ?? '').toString();
        final code = (row['code'] ?? '').toString().trim();
        rows.add(
          _row(
            key: keyOf(id),
            title: code.isEmpty ? name : '$name ($code)',
            subtitle: subtitle,
            icon: icon,
            color: color,
          ),
        );
      }
      return rows;
    }

    return ListView(
      key: const PageStorageKey<String>('price-installation-list'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.handyman_outlined),
                title: Text(tr('احتساب أجور التركيب في السعر')),
                subtitle: Text(
                  tr(
                    'أجور التركيب منفصلة عن سعر القطع ولا يدخل عليها هامش الربح.',
                  ),
                ),
                value: _enabled,
                onChanged: widget.canChangePrices
                    ? (value) {
                        setState(() => _enabled = value);
                        _saveSetting(InstallationFees.enabledPreference, value);
                      }
                    : null,
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.request_quote_outlined),
                title: Text(tr('إظهار أجور التركيب في الديفي')),
                subtitle: Text(
                  tr('يظهر تحت كل نافذة سطر «منها أجور التركيب».'),
                ),
                value: _showOnDevis,
                onChanged: widget.canChangePrices && _enabled
                    ? (value) {
                        setState(() => _showOnDevis = value);
                        _saveSetting(
                          InstallationFees.showOnDevisPreference,
                          value,
                        );
                      }
                    : null,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: TextField(
            decoration: InputDecoration(
              hintText: tr('بحث في أجور التركيب...'),
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        _section(
          title: tr('أجور التركيب العامة'),
          icon: Icons.handyman_outlined,
          color: Colors.teal,
          rows: general,
          lang: lang,
        ),
        _section(
          title: tr('تركيب الكيتات'),
          icon: Icons.inventory_2_outlined,
          color: Colors.deepPurple,
          rows: rowsFor(
            widget.kits,
            InstallationFees.kitKey,
            tr('لكل كيت'),
            Icons.inventory_2_outlined,
            Colors.deepPurple,
          ),
          lang: lang,
        ),
        _section(
          title: tr('تركيب مكوّنات الستار'),
          icon: Icons.window_rounded,
          color: Colors.indigo,
          rows: rowsFor(
            widget.shutterComponents,
            InstallationFees.shutterComponentKey,
            perUnit,
            Icons.window_rounded,
            Colors.indigo,
          ),
          lang: lang,
        ),
        _section(
          title: tr('تركيب الإكسسوارات'),
          icon: Icons.construction_rounded,
          color: Colors.brown,
          rows: rowsFor(
            widget.accessories,
            InstallationFees.accessoryKey,
            perUnit,
            Icons.construction_rounded,
            Colors.brown,
          ),
          lang: lang,
        ),
      ],
    );
  }
}
