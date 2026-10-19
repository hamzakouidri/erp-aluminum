import '../../sql_database.dart';

/// The workshop's own shutter calculation values. Each has a default that
/// keeps the former fixed calculation; the workshop edits them on the
/// tunnel box tab of the price page (table ShutterCalcRules, synced with
/// the workshop configuration).
class ShutterCalcRules {
  ShutterCalcRules._();

  /// Axe = shutter width − this, with a Standard console.
  static const tunnelAxeStandard = 'tunnel_axe_deduction_standard';

  /// Axe = shutter width − this, with a Special console.
  static const tunnelAxeSpecial = 'tunnel_axe_deduction_special';

  /// Blade and final blade length = shutter width − this.
  static const tunnelBladeDeduction = 'tunnel_blade_deduction';

  /// Blades = (shutter height − tunnel height + this) ÷ blade height + the
  /// extra blades.
  static const tunnelBladeHeightAdd = 'tunnel_blade_height_add';
  static const tunnelExtraBlades = 'tunnel_extra_blades';

  /// Rail (coulisse) = shutter height + this. The brush joint always takes
  /// twice the rails' length.
  static const tunnelRailAdd = 'tunnel_rail_add';

  static const Map<String, double> defaults = {
    tunnelAxeStandard: 75,
    tunnelAxeSpecial: 75,
    tunnelBladeDeduction: 65,
    tunnelBladeHeightAdd: 0,
    tunnelExtraBlades: 2,
    tunnelRailAdd: 20,
  };

  static final Map<String, double> _values = {};

  static double value(String key) => _values[key] ?? defaults[key] ?? 0;

  /// The axe deduction of a tunnel box with [consoleGroup] (1 Standard,
  /// 2 Special).
  static double tunnelAxeDeduction(int consoleGroup) =>
      value(consoleGroup == 2 ? tunnelAxeSpecial : tunnelAxeStandard);

  /// Replaces the values in memory (tests, and after a load or a save).
  static void apply(Map<String, double> values) {
    _values
      ..clear()
      ..addAll(values);
  }

  static Future<void> load(SqlDatabase db) async {
    try {
      apply(await db.readShutterCalcRules());
    } catch (_) {
      // The defaults stay in place without a database.
    }
  }

  static Future<void> save(SqlDatabase db, Map<String, double> values) async {
    await db.saveShutterCalcRules(values);
    apply({..._values, ...values});
  }
}
