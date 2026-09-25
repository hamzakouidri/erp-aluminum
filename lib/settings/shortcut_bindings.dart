import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Screen/app_workspace_shell.dart';
import '../Screen/treasury_screen.dart';
import '../Screen/inventory_screen.dart';
import '../Commande/commande.dart';
import '../Commande/order_workspace_screen.dart';
import '../sql_database.dart';
import 'app_settings.dart';
import 'localization.dart';

class ShortcutBindings {
  static final instance = ShortcutBindings._();
  ShortcutBindings._() { reload(); }
  static const commands = {
    'orders': 'الطلبات', 'treasury': 'الصندوق والخزينة',
    'inventory': 'المخزون',
    'new_order': 'إضافة طلبية جديدة',
    'edit_order': 'تعديل الطلبية المحددة',
    'delete_order': 'حذف الطلبية المحددة',
  };
  final Map<String, String> bindings = {};
  bool matches(String command, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    return event is KeyDownEvent && keyboard.isControlPressed &&
        keyboard.isAltPressed && !keyboard.isShiftPressed &&
        !keyboard.isMetaPressed &&
        bindings[command] == event.logicalKey.keyLabel.toUpperCase();
  }
  Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    bindings.clear();
    for (final id in commands.keys) {
      final key = prefs.getString('shortcut_$id');
      if (key != null) bindings[id] = key;
    }
  }
  bool handle(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed || !keyboard.isAltPressed ||
        keyboard.isMetaPressed || keyboard.isShiftPressed) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null || ModalRoute.of(focus) is PopupRoute ||
        focus.widget is EditableText ||
        focus.findAncestorWidgetOfExactType<EditableText>() != null) return false;
    final key = event.logicalKey.keyLabel.toUpperCase();
    final settings = context.read<AppSettingsProvider>();
    for (final entry in bindings.entries) {
      if (entry.value != key) continue;
      Widget? screen;
      if (entry.key == 'new_order') {
        if (!settings.canCreateOrders()) return false;
        openOrderInWorkspaceTab(context, db: SqlDatabase());
        return true;
      }
      switch (entry.key) {
        case 'orders':
          if (settings.canViewOrders()) screen = Commande();
          break;
        case 'treasury':
          if (settings.canAccessTreasury()) screen = TreasuryScreen(db: SqlDatabase());
          break;
        case 'inventory':
          if (settings.canAccessInventory()) screen = InventoryScreen(db: SqlDatabase());
          break;
      }
      if (screen == null) return false;
      openAdaptiveScreen(context, title: Localization.translate(commands[entry.key]!, settings.language),
        icon: Icons.keyboard, screen: screen);
      return true;
    }
    return false;
  }
}
