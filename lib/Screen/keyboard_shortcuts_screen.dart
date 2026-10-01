import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_workshop_sync_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../settings/shortcut_bindings.dart';

class KeyboardShortcutsScreen extends StatefulWidget {
  const KeyboardShortcutsScreen({super.key});
  @override
  State<KeyboardShortcutsScreen> createState() =>
      _KeyboardShortcutsScreenState();
}

class _KeyboardShortcutsScreenState extends State<KeyboardShortcutsScreen> {
  final FocusNode _captureFocus = FocusNode();
  String? _capturing;
  bool _ready = false;

  String tr(String key) =>
      Localization.translate(key, context.read<AppSettingsProvider>().language);

  @override
  void initState() {
    super.initState();
    ShortcutBindings.instance.reload().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _captureFocus.dispose();
    super.dispose();
  }

  Future<void> _save(String command, String? binding) async {
    if (mounted) setState(() => _capturing = null);
    final prefs = await SharedPreferences.getInstance();
    if (binding == null) {
      await prefs.remove('shortcut_$command');
    } else {
      await prefs.setString('shortcut_$command', binding);
    }
    if (command == 'drawing_mode') await prefs.remove('shortcut_drawing_mode');
    await ShortcutBindings.instance.reload();
    final code = (prefs.getString('workshop_code') ?? '').trim();
    if (code.isNotEmpty) {
      await prefs.setString(
        'pending_workshop_shortcuts_$code',
        jsonEncode(ShortcutBindings.instance.bindings),
      );
      try {
        await SupabaseWorkshopSyncService().uploadPendingShortcutBindings();
      } catch (_) {
        // Workshop sync retries the pending map.
      }
    }
    if (mounted) setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final command = _capturing;
    if (command == null) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _capturing = null);
      return KeyEventResult.handled;
    }
    final binding = ShortcutBindings.capture(event);
    if (binding == null) return KeyEventResult.handled;
    final duplicate = ShortcutBindings.instance.bindings.entries.any(
      (entry) =>
          entry.key != command &&
          ShortcutBindings.sameShortcut(entry.value, binding),
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('هذا الاختصار مستخدم لأمر آخر.'))),
      );
      return KeyEventResult.handled;
    }
    _save(command, binding);
    return KeyEventResult.handled;
  }

  Future<void> _showAddShortcutDialog() async {
    var query = '';
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final available = ShortcutBindings.commands.entries.where((entry) {
            if (ShortcutBindings.defaultCommands.contains(entry.key) ||
                ShortcutBindings.instance.bindings.containsKey(entry.key)) {
              return false;
            }
            final needle = query.trim().toLowerCase();
            if (needle.isEmpty) return true;
            final category =
                ShortcutBindings.commandCategories[entry.key] ?? '';
            return tr(entry.value).toLowerCase().contains(needle) ||
                tr(category).toLowerCase().contains(needle);
          }).toList();

          return AlertDialog(
            title: Text(tr('إضافة اختصار جديد')),
            content: SizedBox(
              width: 520,
              height: 520,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: tr('ابحث عن صفحة أو خاصية...'),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: available.isEmpty
                        ? Center(
                            child: Text(tr('لا توجد خصائص أخرى لإضافتها.')),
                          )
                        : ListView.separated(
                            itemCount: available.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final entry = available[index];
                              final category =
                                  ShortcutBindings.commandCategories[entry
                                      .key] ??
                                  '';
                              return ListTile(
                                leading: const Icon(Icons.add_circle_outline),
                                title: Text(tr(entry.value)),
                                subtitle: category.isEmpty
                                    ? null
                                    : Text(tr(category)),
                                onTap: () =>
                                    Navigator.pop(dialogContext, entry.key),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr('إلغاء')),
              ),
            ],
          );
        },
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _capturing = selected);
    _captureFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _captureFocus,
    onKeyEvent: _onKey,
    child: Scaffold(
      appBar: AppBar(title: Text(tr('اختصارات لوحة المفاتيح'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr('تُحفظ الاختصارات لجميع أعضاء الورشة.')),
          const SizedBox(height: 8),
          Text(
            tr(
              'اختر أمرًا ثم اضغط المفاتيح المطلوبة. لا تعمل الاختصارات أثناء الكتابة أو فتح نافذة حوار.',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('لتعديل أو حذف طلبية، حدد زر خياراتها بلوحة المفاتيح أولًا.'),
          ),
          const Divider(),
          for (final command in ShortcutBindings.commands.entries.where(
            (entry) =>
                ShortcutBindings.defaultCommands.contains(entry.key) ||
                entry.key == _capturing ||
                ShortcutBindings.instance.bindings.containsKey(entry.key),
          ))
            ListTile(
              title: Text(tr(command.value)),
              subtitle: Text(
                _capturing == command.key
                    ? tr('اضغط المفاتيح الآن (Esc للإلغاء)')
                    : ShortcutBindings.label(
                        ShortcutBindings.instance.bindings[command.key],
                      ),
              ),
              onTap: !_ready
                  ? null
                  : () {
                      setState(() => _capturing = command.key);
                      _captureFocus.requestFocus();
                    },
              trailing: IconButton(
                tooltip: tr('إلغاء الاختصار'),
                icon: const Icon(Icons.close),
                onPressed:
                    !_ready ||
                        !ShortcutBindings.instance.bindings.containsKey(
                          command.key,
                        )
                    ? null
                    : () => _save(command.key, null),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: !_ready ? null : _showAddShortcutDialog,
            icon: const Icon(Icons.add),
            label: Text(tr('إضافة اختصار جديد')),
          ),
        ],
      ),
    ),
  );
}
