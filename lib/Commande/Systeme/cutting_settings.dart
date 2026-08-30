/// Runtime cache for cutting settings.
///
/// The persisted source is InventorySettings. This cache keeps synchronous BOM
/// generation from falling back to a hard-coded saw loss after the app starts.
class CuttingSettings {
  CuttingSettings._();

  static const double defaultSawKerfMm = 4.0;
  static double _sawKerfMm = defaultSawKerfMm;

  static double get sawKerfMm => _sawKerfMm;
  static double get sawKerfMeters => _sawKerfMm / 1000.0;

  static void setSawKerfMm(double value) {
    if (value > 0) _sawKerfMm = value;
  }
}
