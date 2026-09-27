import 'dart:convert';

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
  ShortcutBindings._() {
    reload();
  }

  static const commands = {
    'drawing_mode': 'تبديل وضع الرسم',
    'orders': 'الطلبات',
    'treasury': 'الصندوق والخزينة',
    'inventory': 'المخزون',
    'new_order': 'إضافة طلبية جديدة',
    'edit_order': 'تعديل الطلبية المحددة',
    'delete_order': 'حذف الطلبية المحددة',
  };
  final Map<String, String> bindings = {};

  static final _modifierKeys = {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  static String? capture(KeyEvent event) {
    if (event is! KeyDownEvent || _modifierKeys.contains(event.logicalKey)) {
      return null;
    }
    final keyboard = HardwareKeyboard.instance;
    return jsonEncode({
      'key': event.logicalKey.keyId,
      'label': event.logicalKey.keyLabel,
      'ctrl': keyboard.isControlPressed,
      'alt': keyboard.isAltPressed,
      'shift': keyboard.isShiftPressed,
      'meta': keyboard.isMetaPressed,
    });
  }

  static bool sameShortcut(String first, String second) {
    if (first.startsWith('legacy_drawing:') && second.startsWith('{')) {
      final value = jsonDecode(second);
      return value is Map &&
          value['label']?.toString().toUpperCase() == first.substring(15) &&
          value['ctrl'] == false && value['alt'] == false &&
          value['shift'] == false && value['meta'] == false;
    }
    if (second.startsWith('legacy_drawing:') && first.startsWith('{')) {
      return sameShortcut(second, first);
    }
    try {
      final a = jsonDecode(first);
      final b = jsonDecode(second);
      if (a is Map && b is Map) {
        return a['key'] == b['key'] &&
            a['ctrl'] == b['ctrl'] &&
            a['alt'] == b['alt'] &&
            a['shift'] == b['shift'] &&
            a['meta'] == b['meta'];
      }
    } catch (_) {}
    return first == second;
  }

  static bool _matchesBinding(String binding, KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    if (binding.startsWith('legacy_drawing:')) {
      return !keyboard.isControlPressed &&
          !keyboard.isAltPressed &&
          !keyboard.isShiftPressed &&
          !keyboard.isMetaPressed &&
          event.logicalKey.keyLabel.toUpperCase() == binding.substring(15);
    }
    try {
      final saved = jsonDecode(binding);
      if (saved is Map) {
        return saved['key'] == event.logicalKey.keyId &&
            saved['ctrl'] == keyboard.isControlPressed &&
            saved['alt'] == keyboard.isAltPressed &&
            saved['shift'] == keyboard.isShiftPressed &&
            saved['meta'] == keyboard.isMetaPressed;
      }
    } catch (_) {}
    // Old navigation shortcuts stored a letter and implied Ctrl+Alt.
    return keyboard.isControlPressed &&
        keyboard.isAltPressed &&
        !keyboard.isShiftPressed &&
        !keyboard.isMetaPressed &&
        binding == event.logicalKey.keyLabel.toUpperCase();
  }

  static String label(String? binding) {
    if (binding == null || binding.isEmpty) return '—';
    if (binding.startsWith('legacy_drawing:')) return binding.substring(15);
    try {
      final saved = jsonDecode(binding);
      if (saved is Map) {
        return [
          if (saved['ctrl'] == true) 'Ctrl',
          if (saved['alt'] == true) 'Alt',
          if (saved['shift'] == true) 'Shift',
          if (saved['meta'] == true) 'Meta',
          saved['label']?.toString().isNotEmpty == true
              ? saved['label'].toString()
              : '?',
        ].join(' + ');
      }
    } catch (_) {}
    return 'Ctrl + Alt + $binding';
  }

  bool matches(String command, KeyEvent event) {
    final binding = bindings[command];
    return binding != null && _matchesBinding(binding, event);
  }

  Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    bindings.clear();
    for (final id in commands.keys) {
      final key = prefs.getString('shortcut_$id');
      if (key != null && key.isNotEmpty) bindings[id] = key;
    }
    final drawing = prefs.getString('shortcut_drawing_mode');
    if (!bindings.containsKey('drawing_mode') && drawing != null) {
      bindings['drawing_mode'] = 'legacy_drawing:$drawing';
    }
  }

  bool handle(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus == null ||
        ModalRoute.of(focus) is PopupRoute ||
        focus.widget is EditableText ||
        focus.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    final settings = context.read<AppSettingsProvider>();
    for (final entry in bindings.entries) {
      if (entry.key == 'drawing_mode' || !_matchesBinding(entry.value, event)) {
        continue;
      }
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
          if (settings.canAccessTreasury())
            screen = TreasuryScreen(db: SqlDatabase());
          break;
        case 'inventory':
          if (settings.canAccessInventory())
            screen = InventoryScreen(db: SqlDatabase());
          break;
      }
      if (screen == null) return false;
      openAdaptiveScreen(
        context,
        title: Localization.translate(commands[entry.key]!, settings.language),
        icon: Icons.keyboard,
        screen: screen,
      );
      return true;
    }
    return false;
  }
}
