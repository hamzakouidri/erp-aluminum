import '../../sql_database.dart';

/// The workshop's own shutter calculation values, edited on the tunnel box
/// page of the products menu (table ShutterCalcRules, synced with the
/// workshop configuration).
class ShutterCalcRules {
  ShutterCalcRules._();

  /// Axe = shutter width − this, with a Standard console.
  static const tunnelAxeStandard = 'tunnel_axe_deduction_standard';

  /// Axe = shutter width − this, with a Special console.
  static const tunnelAxeSpecial = 'tunnel_axe_deduction_special';

  /// Blade and final blade length = shutter width − this.
  static const tunnelBladeDeduction = 'tunnel_blade_deduction';

  /// Blades = (shutter height + this) ÷ blade height + the extra blades. The
  /// height is measured under the tunnel box, so the tunnel is not deducted.
  static const tunnelBladeHeightAdd = 'tunnel_blade_height_add';
  static const tunnelExtraBlades = 'tunnel_extra_blades';

  /// Rail (coulisse) = shutter height + this. The brush joint always takes
  /// twice the rails' length.
  static const tunnelRailAdd = 'tunnel_rail_add';

  /// The console (1 Standard, 2 Special) a tunnel box of each height takes
  /// by default; the drawing can still change it.
  static String tunnelConsoleForHeight(int heightMm) =>
      'tunnel_console_$heightMm';
  static const tunnelHeights = [250, 300, 400];

  static const Map<String, double> defaults = {
    tunnelAxeStandard: 75,
    tunnelAxeSpecial: 75,
    tunnelBladeDeduction: 65,
    tunnelBladeHeightAdd: 100,
    tunnelExtraBlades: 2,
    tunnelRailAdd: 20,
  };

  static final Map<String, double> _values = {};

  static double value(String key) => _values[key] ?? defaults[key] ?? 0;

  /// The axe deduction of a tunnel box with [consoleGroup] (1 Standard,
  /// 2 Special).
  static double tunnelAxeDeduction(int consoleGroup) =>
      value(consoleGroup == 2 ? tunnelAxeSpecial : tunnelAxeStandard);

  /// The default console of a tunnel box [heightMm] high.
  static int defaultTunnelConsole(double heightMm) =>
      value(tunnelConsoleForHeight(heightMm.round())) == 2 ? 2 : 1;

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
