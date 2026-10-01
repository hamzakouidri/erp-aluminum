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
      await prefs.setString('shortcut_$command', 'none');
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

  Future<void> _resetDefaults() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('استعادة الاختصارات الافتراضية')),
        content: Text(tr('هل تريد حقاً استعادة جميع الاختصارات الافتراضية؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('استعادة')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await ShortcutBindings.instance.resetToDefaults();
    final prefs = await SharedPreferences.getInstance();
    final code = (prefs.getString('workshop_code') ?? '').trim();
    if (code.isNotEmpty) {
      await prefs.setString(
        'pending_workshop_shortcuts_$code',
        jsonEncode(ShortcutBindings.instance.bindings),
      );
      try {
        await SupabaseWorkshopSyncService().uploadPendingShortcutBindings();
      } catch (_) {}
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

  Widget _buildKeyCapBadge(String? binding, {bool isCapturing = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (isCapturing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.primary, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              tr('اضغط المفاتيح الآن (Esc للإلغاء)'),
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      );
    }

    final lbl = ShortcutBindings.label(binding);
    final isUnset = lbl == '—';

    if (isUnset) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark ? Colors.white24 : Colors.black12,
            width: 1,
          ),
        ),
        child: Text(
          '—',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      );
    }

    final parts = lbl.split(' + ');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < parts.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                '+',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ),
          Container(
            constraints: const BoxConstraints(minWidth: 26),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isDark ? const Color(0xFF4A5568) : const Color(0xFFCBD5E1),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  offset: const Offset(0, 1),
                  blurRadius: 1,
                ),
              ],
            ),
            child: Text(
              parts[i],
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final visibleCommands = ShortcutBindings.commands.entries.where(
      (entry) =>
          ShortcutBindings.defaultCommands.contains(entry.key) ||
          entry.key == _capturing ||
          ShortcutBindings.instance.bindings.containsKey(entry.key),
    ).toList();

    final Map<String, List<MapEntry<String, String>>> grouped = {};
    for (final cmd in visibleCommands) {
      final category = ShortcutBindings.commandCategories[cmd.key] ?? 'عام';
      grouped.putIfAbsent(category, () => []).add(cmd);
    }

    return Focus(
      focusNode: _captureFocus,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('اختصارات لوحة المفاتيح')),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: Text(tr('استعادة الاختصارات الافتراضية')),
              onPressed: !_ready ? null : _resetDefaults,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.blue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.blue.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        tr('تُحفظ الاختصارات لجميع أعضاء الورشة.'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr('اختر أمرًا ثم اضغط المفاتيح المطلوبة. لا تعمل الاختصارات أثناء الكتابة أو فتح نافذة حوار.'),
                    style: TextStyle(fontSize: 12.5, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('لتعديل أو حذف طلبية، حدد زر خياراتها بلوحة المفاتيح أولًا.'),
                    style: TextStyle(fontSize: 12.5, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            for (final group in grouped.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6, right: 4, left: 4),
                child: Text(
                  tr(group.key),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < group.value.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        title: Text(
                          tr(group.value[i].value),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildKeyCapBadge(
                              ShortcutBindings.instance.bindings[group.value[i].key],
                              isCapturing: _capturing == group.value[i].key,
                            ),
                            const SizedBox(width: 8),
                            if (ShortcutBindings.instance.bindings.containsKey(group.value[i].key))
                              IconButton(
                                tooltip: tr('إلغاء الاختصار'),
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: !_ready
                                    ? null
                                    : () => _save(group.value[i].key, null),
                              )
                            else
                              const SizedBox(width: 40),
                          ],
                        ),
                        onTap: !_ready
                            ? null
                            : () {
                                setState(() => _capturing = group.value[i].key);
                                _captureFocus.requestFocus();
                              },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

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
}
