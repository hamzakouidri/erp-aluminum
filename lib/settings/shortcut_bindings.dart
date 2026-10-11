import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Screen/app_workspace_shell.dart';
import '../Screen/treasury_screen.dart';
import '../Screen/inventory_screen.dart';
import '../Screen/achat_screen.dart';
import '../Screen/client_chrono_search_screen.dart';
import '../Screen/distribution_tracking_screen.dart';
import '../Screen/external_operations_hub_screen.dart';
import '../Screen/global_consumption_report_screen.dart';
import '../Screen/measurements_screen.dart';
import '../Screen/price_management_screen.dart';
import '../Screen/projects_screen.dart';
import '../Screen/reports_hub_screen.dart';
import '../Screen/sales_screen.dart';
import '../Screen/selected_systems_screen.dart';
import '../Screen/settings_screen.dart';
import '../Screen/suppliers_screen.dart';
import '../Screen/worker_archive_screen.dart';
import '../Screen/worker_tasks_screen.dart';
import '../Screen/workers_management_screen.dart';
import '../Cliente/client.dart';
import '../Commande/commande.dart';
import '../Commande/order_workspace_screen.dart';
import '../Commande/Systeme/show_system_francais.dart';
import '../items_produits/products_menu_screen.dart';
import '../sql_database.dart';
import 'app_settings.dart';
import 'localization.dart';

class ShortcutBindings {
  static final instance = ShortcutBindings._();
  ShortcutBindings._() {
    reload();
  }

  static String makeBinding(
    LogicalKeyboardKey key, {
    bool ctrl = false,
    bool alt = false,
    bool shift = false,
    bool meta = false,
  }) {
    return jsonEncode({
      'key': key.keyId,
      'label': key.keyLabel.toUpperCase(),
      'ctrl': ctrl,
      'alt': alt,
      'shift': shift,
      'meta': meta,
    });
  }

  static final Map<String, String> defaultBindings = {
    // Global Navigation (Ctrl + key)
    'orders': makeBinding(LogicalKeyboardKey.keyO, ctrl: true),
    'inventory': makeBinding(LogicalKeyboardKey.keyK, ctrl: true),
    'treasury': makeBinding(LogicalKeyboardKey.keyT, ctrl: true),
    'new_order': makeBinding(LogicalKeyboardKey.keyN, ctrl: true),
    'customers': makeBinding(LogicalKeyboardKey.keyC, ctrl: true),
    'sales': makeBinding(LogicalKeyboardKey.keyS, ctrl: true),
    'purchases': makeBinding(LogicalKeyboardKey.keyP, ctrl: true),
    // Order row actions (single letter)
    'edit_order': makeBinding(LogicalKeyboardKey.keyE),
    'delete_order': makeBinding(LogicalKeyboardKey.keyD),
    'devis_order': makeBinding(LogicalKeyboardKey.keyV),
    'details_order': makeBinding(LogicalKeyboardKey.keyI),
    // Drawing
    'drawing_mode': makeBinding(LogicalKeyboardKey.keyD, ctrl: true, shift: true),
  };

  static const commands = {
    'drawing_mode': 'تبديل وضع الرسم',
    'orders': 'الطلبات',
    'treasury': 'الصندوق والخزينة',
    'inventory': 'المخزون',
    'new_order': 'إضافة طلبية جديدة',
    'edit_order': 'تعديل الطلبية المحددة',
    'delete_order': 'حذف الطلبية المحددة',
    'devis_order': 'تسعيرة الطلبية المحددة',
    'details_order': 'تفاصيل الطلبية المحددة',
    'sales': 'المبيعات',
    'purchases': 'المشتريات',
    'suppliers': 'الموردون',
    'products': 'المنتجات',
    'customers': 'الزبائن',
    'customer_ledger': 'كشف حساب الزبائن',
    'measurements': 'رفع القياسات',
    'distribution': 'التوزيع والتتبع',
    'reports': 'مركز التقارير',
    'projects': 'كل المشاريع',
    'worker_tasks': 'مهامي وتصنيعاتي',
    'worker_archive': 'أرشيف المهام والتوزيع',
    'external_operations': 'المهام الخارجية',
    'workers': 'صلاحيات المستخدمين',
    'prices': 'إدارة الأسعار',
    'selected_systems': 'الأنظمة المستعملة',
    'settings': 'إعدادات التطبيق',
    'shortage_report': 'تقرير النواقص',
  };

  static const defaultCommands = {
    'drawing_mode',
    'orders',
    'treasury',
    'inventory',
    'new_order',
    'edit_order',
    'delete_order',
    'devis_order',
    'details_order',
    'customers',
    'sales',
    'purchases',
  };

  static const commandCategories = {
    'drawing_mode': 'الرسم والطلبات',
    'orders': 'الرسم والطلبات',
    'new_order': 'الرسم والطلبات',
    'edit_order': 'الرسم والطلبات',
    'delete_order': 'الرسم والطلبات',
    'devis_order': 'الرسم والطلبات',
    'details_order': 'الرسم والطلبات',
    'sales': 'الرسم والطلبات',
    'measurements': 'الرسم والطلبات',
    'distribution': 'الرسم والطلبات',
    'treasury': 'الحسابات والسندات',
    'purchases': 'الحسابات والسندات',
    'suppliers': 'الحسابات والسندات',
    'customers': 'الزبائن والمشاريع',
    'customer_ledger': 'الزبائن والمشاريع',
    'projects': 'الزبائن والمشاريع',
    'inventory': 'المخزون والمنتجات',
    'products': 'المخزون والمنتجات',
    'shortage_report': 'المخزون والمنتجات',
    'reports': 'التقارير والمهام',
    'worker_tasks': 'التقارير والمهام',
    'worker_archive': 'التقارير والمهام',
    'external_operations': 'التقارير والمهام',
    'workers': 'الإدارة والإعدادات',
    'prices': 'الإدارة والإعدادات',
    'selected_systems': 'الإدارة والإعدادات',
    'settings': 'الإدارة والإعدادات',
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
      'label': event.logicalKey.keyLabel.toUpperCase(),
      'ctrl': keyboard.isControlPressed,
      'alt': keyboard.isAltPressed,
      'shift': keyboard.isShiftPressed,
      'meta': keyboard.isMetaPressed,
    });
  }

  static bool sameShortcut(String first, String second) {
    if (first == 'none' || second == 'none') return false;
    if (first.startsWith('legacy_drawing:') && second.startsWith('{')) {
      final value = jsonDecode(second);
      return value is Map &&
          value['label']?.toString().toUpperCase() == first.substring(15) &&
          value['ctrl'] == false &&
          value['alt'] == false &&
          value['shift'] == false &&
          value['meta'] == false;
    }
    if (second.startsWith('legacy_drawing:') && first.startsWith('{')) {
      return sameShortcut(second, first);
    }
    try {
      final a = jsonDecode(first);
      final b = jsonDecode(second);
      if (a is Map && b is Map) {
        final sameModifiers =
            (a['ctrl'] == true) == (b['ctrl'] == true) &&
            (a['alt'] == true) == (b['alt'] == true) &&
            (a['shift'] == true) == (b['shift'] == true) &&
            (a['meta'] == true) == (b['meta'] == true);
        if (!sameModifiers) return false;
        if (a['key'] != null && b['key'] != null && a['key'] == b['key']) {
          return true;
        }
        final aLabel = a['label']?.toString().toUpperCase();
        final bLabel = b['label']?.toString().toUpperCase();
        if (aLabel != null && bLabel != null && aLabel == bLabel) {
          return true;
        }
        return false;
      }
    } catch (_) {}
    return first == second;
  }

  static bool _matchesBinding(String binding, KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (binding == 'none' || binding.isEmpty) return false;
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
        final matchesModifiers =
            (saved['ctrl'] == true) == keyboard.isControlPressed &&
            (saved['alt'] == true) == keyboard.isAltPressed &&
            (saved['shift'] == true) == keyboard.isShiftPressed &&
            (saved['meta'] == true) == keyboard.isMetaPressed;
        if (!matchesModifiers) return false;
        if (saved['key'] == event.logicalKey.keyId) return true;
        final label = saved['label']?.toString().toUpperCase();
        if (label != null &&
            label.isNotEmpty &&
            label == event.logicalKey.keyLabel.toUpperCase()) {
          return true;
        }
        return false;
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
    if (binding == null || binding.isEmpty || binding == 'none') return '—';
    if (binding.startsWith('legacy_drawing:')) return binding.substring(15);
    try {
      final saved = jsonDecode(binding);
      if (saved is Map) {
        final parts = [
          if (saved['ctrl'] == true) 'Ctrl',
          if (saved['alt'] == true) 'Alt',
          if (saved['shift'] == true) 'Shift',
          if (saved['meta'] == true) 'Meta',
          saved['label']?.toString().isNotEmpty == true
              ? saved['label'].toString().toUpperCase()
              : '?',
        ];
        return parts.join(' + ');
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
      if (key == 'none') {
        continue;
      }
      if (key != null && key.isNotEmpty) {
        bindings[id] = key;
      } else if (defaultBindings.containsKey(id)) {
        bindings[id] = defaultBindings[id]!;
      }
    }
    final drawing = prefs.getString('shortcut_drawing_mode');
    if (!bindings.containsKey('drawing_mode') &&
        drawing != null &&
        drawing.isNotEmpty &&
        drawing != 'none') {
      bindings['drawing_mode'] = 'legacy_drawing:$drawing';
    }
  }

  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    for (final id in commands.keys) {
      await prefs.remove('shortcut_$id');
    }
    await prefs.remove('shortcut_drawing_mode');
    await reload();
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

    // Do not trigger global home/navigation shortcuts while active in WindowView (Drawing Screen)
    final route = ModalRoute.of(focus);
    final routeName = route?.settings.name ?? '';
    final isDrawingRoute = routeName.contains('WindowView') ||
        focus.findAncestorWidgetOfExactType<WindowView>() != null;
    if (isDrawingRoute) {
      return false;
    }

    final settings = context.read<AppSettingsProvider>();
    const contextualRowCommands = {
      'drawing_mode',
      'edit_order',
      'delete_order',
      'devis_order',
      'details_order',
    };
    for (final entry in bindings.entries) {
      if (contextualRowCommands.contains(entry.key) ||
          !_matchesBinding(entry.value, event)) {
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
            screen = TreasuryScreen(
              db: SqlDatabase(),
              storeOnly:
                  settings.workingSection == WorkingSection.materialsStore,
            );
          break;
        case 'inventory':
          if (settings.canAccessInventory())
            screen = InventoryScreen(db: SqlDatabase());
          break;
        case 'sales':
          if (settings.canViewSales()) screen = SalesScreen(db: SqlDatabase());
          break;
        case 'purchases':
          if (settings.canRegisterPurchases())
            screen = AchatScreen(
              db: SqlDatabase(),
              isWorkshop:
                  settings.workingSection != WorkingSection.materialsStore,
            );
          break;
        case 'suppliers':
          if (settings.canViewSuppliers())
            screen = SuppliersScreen(db: SqlDatabase());
          break;
        case 'products':
          if (settings.canViewMyAccreditations())
            screen = ProductsMenuScreen(db: SqlDatabase());
          break;
        case 'customers':
          if (settings.canViewClients()) {
            screen = Customers(
              storeOnly:
                  settings.workingSection == WorkingSection.materialsStore,
            );
          }
          break;
        case 'customer_ledger':
          if (settings.workingSection != WorkingSection.materialsStore &&
              settings.canViewClientLedger())
            screen = const ClientChronoSearchScreen();
          break;
        case 'measurements':
          if (settings.canAccessMeasurements())
            screen = MeasurementsScreen(db: SqlDatabase());
          break;
        case 'distribution':
          if (settings.canAccessDistributionTracking())
            screen = const DistributionTrackingScreen();
          break;
        case 'reports':
          if (settings.canViewStatistics())
            screen = ReportsHubScreen(db: SqlDatabase());
          break;
        case 'projects':
          if (settings.canViewProjects())
            screen = ProjectsScreen(db: SqlDatabase());
          break;
        case 'worker_tasks':
          if (settings.canViewMyTasks())
            screen = WorkerTasksScreen(db: SqlDatabase());
          break;
        case 'worker_archive':
          if (settings.canViewMyTasks())
            screen = WorkerArchiveScreen(db: SqlDatabase());
          break;
        case 'external_operations':
          if (settings.canAccessExternalOperations())
            screen = ExternalOperationsHubScreen(db: SqlDatabase());
          break;
        case 'workers':
          if (settings.canManageWorkers())
            screen = WorkersManagementScreen(db: SqlDatabase());
          break;
        case 'prices':
          if (settings.canChangePrices()) screen = PriceManagementScreen();
          break;
        case 'selected_systems':
          if (settings.canSelectSystems())
            screen = const SelectedSystemsScreen();
          break;
        case 'settings':
          if (settings.canAccessSettings()) screen = const SettingsScreen();
          break;
        case 'shortage_report':
          if (settings.canViewGlobalConsumption())
            screen = GlobalConsumptionReportScreen(db: SqlDatabase());
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
