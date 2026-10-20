/// One right-click menu at a time in the whole application.
///
/// A menu that first reads the database used to open once per click while
/// it was being prepared: three quick right clicks stacked three menus, and
/// each needed its own click to close. Every right-click menu goes through
/// [run]: while one is being prepared or is open, further requests are
/// ignored.
class ContextMenuGate {
  ContextMenuGate._();

  static bool _busy = false;

  /// Whether a menu is being prepared or is open.
  static bool get isBusy => _busy;

  /// Prepares and shows a menu with [open], unless another one is already
  /// being prepared or shown; returns null when ignored.
  static Future<T?> run<T>(Future<T?> Function() open) async {
    if (_busy) return null;
    _busy = true;
    try {
      return await open();
    } finally {
      _busy = false;
    }
  }
}
