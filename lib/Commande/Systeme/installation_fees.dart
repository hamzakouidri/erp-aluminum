import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show DatabaseExecutor;

import 'calculate_component.dart';
import 'model.dart';

/// Installation (labour) prices, kept apart from the price of the parts.
///
/// They are workshop selling prices stored in `ShutterSqmPrices` with
/// `color_id = 0`, so they already travel with the workshop sync and the
/// workshop's own price markers. A fee is tied explicitly to one catalogue
/// row (accessory id, shutter component id or kit id), never guessed from a
/// part of its name.
class InstallationFees {
  /// Workshop switch: when off no installation fee is added to any price.
  static const String enabledPreference = 'app_installation_fees_enabled';

  /// Whether a quote shows the installation included in each window price.
  static const String showOnDevisPreference = 'app_installation_show_on_devis';

  static const String keyPrefix = 'Install_';

  /// Installation of a shutter (once per shutter unit).
  static const String shutterKey = 'Install_shutter';

  /// Fees that existed before this page. Their keys are kept as they are so
  /// the prices already typed by the workshops stay valid.
  static const String motorKey = 'Moteur_Install';
  static const String crankKey = 'Manivelle';
  static const String obKey = 'OB_Install';
  static const String demiObKey = 'DemiOB_Install';
  static const String verrouKey = 'Verrou_Install';
  static const List<String> legacyKeys = [
    motorKey,
    crankKey,
    obKey,
    demiObKey,
    verrouKey,
  ];

  static String accessoryKey(int accessoryId) => 'Install_acc_$accessoryId';
  static String shutterComponentKey(int componentId) =>
      'Install_shc_$componentId';
  static String kitKey(int kitId) => 'Install_kit_$kitId';

  /// Whether a `ShutterSqmPrices.blade_type` is an installation price.
  static bool isInstallationKey(String? bladeType) {
    final value = bladeType ?? '';
    return value.startsWith(keyPrefix) || legacyKeys.contains(value);
  }

  final bool enabled;

  /// Price per key, from the `color_id = 0` rows.
  final Map<String, double> prices;

  /// Active kits by their exact name, as carried by [BomItem.kitGroupName].
  final Map<String, int> kitIdsByName;

  const InstallationFees({
    this.enabled = true,
    this.prices = const {},
    this.kitIdsByName = const {},
  });

  static const InstallationFees none = InstallationFees(enabled: false);

  double priceOf(String key) => prices[key] ?? 0.0;

  static Future<InstallationFees> load(
    DatabaseExecutor db, {
    SharedPreferences? preferences,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final enabled = prefs.getBool(enabledPreference) ?? true;
    final rows = await db.query(
      'ShutterSqmPrices',
      columns: ['blade_type', 'price_per_sqm'],
      where:
          "color_id = 0 AND (blade_type LIKE ? ESCAPE '!' OR blade_type IN "
          "(${List.filled(legacyKeys.length, '?').join(', ')}))",
      // `_` is a LIKE wildcard: escape it so only "Install_..." matches.
      whereArgs: ['Install!_%', ...legacyKeys],
    );
    final prices = <String, double>{
      for (final row in rows)
        row['blade_type'].toString():
            (row['price_per_sqm'] as num?)?.toDouble() ?? 0.0,
    };
    final kitIdsByName = <String, int>{};
    try {
      final kits = await db.query(
        'KitBundles',
        columns: ['id', 'name'],
        where: 'is_active = 1',
      );
      for (final kit in kits) {
        final id = (kit['id'] as num?)?.toInt();
        final name = kit['name']?.toString().trim() ?? '';
        if (id != null && name.isNotEmpty) kitIdsByName[name] = id;
      }
    } catch (_) {
      // Older databases without kits simply have no kit fees.
    }
    return InstallationFees(
      enabled: enabled,
      prices: prices,
      kitIdsByName: kitIdsByName,
    );
  }

  /// One line per charged installation of [model], for its whole quantity.
  List<InstallationFeeLine> linesFor(WindowModel model, List<BomItem> items) {
    if (!enabled) return const [];
    final active = items.where((item) => item.isActive).toList();
    final windows = model.quantity <= 0 ? 1 : model.quantity;
    final lines = <InstallationFeeLine>[];

    void add(String key, String label, double quantity) {
      final price = priceOf(key);
      if (price <= 0 || quantity <= 0) return;
      lines.add(
        InstallationFeeLine(
          key: key,
          label: label,
          unitPrice: price,
          quantity: quantity,
        ),
      );
    }

    final hasShutter = active.any((item) => item.category == 'shutter');
    if (hasShutter) {
      add(shutterKey, 'تركيب الستار', windows.toDouble());
      final mechanism = ComponentCalculator.shutterMechanismScope(
        model.shutterMechanism,
      );
      if (mechanism == 'motor') {
        add(motorKey, 'تركيب المحرك', windows.toDouble());
      } else if (mechanism == 'crank') {
        add(crankKey, 'تركيب المانيفال', windows.toDouble());
      }
    }

    bool hasLegacyKit(String exactName) => active.any(
      (item) =>
          item.category == 'accessory' &&
          (item.originalName == exactName ||
              item.originalName.startsWith('${exactName}_')),
    );
    if (hasLegacyKit('System OB')) {
      add(obKey, 'تركيب System OB', windows.toDouble());
    }
    if (hasLegacyKit('Demi System OB')) {
      add(demiObKey, 'تركيب Demi System OB', windows.toDouble());
    }
    if (hasLegacyKit('Verrou Central')) {
      add(verrouKey, 'تركيب Verrou Central', windows.toDouble());
    }

    // A kit is installed once per window, or as many times as its own BOM
    // row says when the kit is priced as one row.
    final kitNames = <String>{};
    final kitRowQuantities = <String, double>{};
    for (final item in active) {
      final name = item.kitGroupName?.trim() ?? '';
      if (name.isEmpty || !kitIdsByName.containsKey(name)) continue;
      kitNames.add(name);
      if (item.inventoryItemType == 'KitBundle') {
        kitRowQuantities[name] = (kitRowQuantities[name] ?? 0) + item.quantity;
      }
    }
    for (final name in kitNames) {
      add(
        kitKey(kitIdsByName[name]!),
        name,
        kitRowQuantities[name] ?? windows.toDouble(),
      );
    }

    for (final item in active) {
      final id = item.catalogItemId;
      if (id == null) continue;
      final String key;
      if (item.inventoryItemType == 'Accessory' &&
          (item.category == 'accessory' || item.category == 'other')) {
        key = accessoryKey(id);
      } else if (item.inventoryItemType == 'ShutterComponent') {
        key = shutterComponentKey(id);
      } else {
        continue;
      }
      add(key, item.name, item.quantity);
    }
    return lines;
  }
}

class InstallationFeeLine {
  final String key;

  /// Name of the installed part, as shown in the material table.
  final String label;
  final double unitPrice;
  final double quantity;

  const InstallationFeeLine({
    required this.key,
    required this.label,
    required this.unitPrice,
    required this.quantity,
  });

  double get total => unitPrice * quantity;
}
