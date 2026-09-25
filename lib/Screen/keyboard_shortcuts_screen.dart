import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../settings/shortcut_bindings.dart';

class KeyboardShortcutsScreen extends StatefulWidget {
  const KeyboardShortcutsScreen({super.key});
  @override
  State<KeyboardShortcutsScreen> createState() => _KeyboardShortcutsScreenState();
}

class _KeyboardShortcutsScreenState extends State<KeyboardShortcutsScreen> {
  String? selected;
  bool ready = false;
  String tr(String key) => Localization.translate(key, context.watch<AppSettingsProvider>().language);
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) async {
      await ShortcutBindings.instance.reload();
      if (!mounted) return;
      setState(() {
        selected = prefs.getString('shortcut_drawing_mode');
        ready = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('اختصارات لوحة المفاتيح'))),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text(tr('اختصار تبديل وضع الرسم والتحريك داخل صفحة الرسم. لا يعمل أثناء الكتابة أو فتح نافذة حوار.')),
      const SizedBox(height: 20),
      DropdownButtonFormField<String>(
        value: selected,
        decoration: InputDecoration(labelText: tr('تبديل وضع الرسم')),
        hint: Text(tr('غير مفعّل')),
        items: [for (var code = 65; code <= 90; code++)
          DropdownMenuItem(value: String.fromCharCode(code),
            child: Text(String.fromCharCode(code)))],
        onChanged: !ready ? null : (value) async {
          final prefs = await SharedPreferences.getInstance();
          if (value != null) await prefs.setString('shortcut_drawing_mode', value);
          if (mounted) setState(() => selected = value);
        },
      ),
      TextButton(onPressed: !ready ? null : () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('shortcut_drawing_mode');
        if (mounted) setState(() => selected = null);
      }, child: Text(tr('إلغاء الاختصار'))),
      const Divider(),
      Text(tr('اختصارات التنقل: Ctrl + Alt + الحرف')),
      for (final command in ShortcutBindings.commands.entries)
        ListTile(
          title: Text(tr(command.value)),
          subtitle: Text('Ctrl + Alt + ${ShortcutBindings.instance.bindings[command.key] ?? "—"}'),
          trailing: DropdownButton<String>(
            value: ShortcutBindings.instance.bindings[command.key] ?? '',
            items: [DropdownMenuItem(value: '', child: Text(tr('غير مفعّل'))),
              for (var code = 65; code <= 90; code++)
                if (!ShortcutBindings.instance.bindings.entries.any((e) =>
                    e.key != command.key && e.value == String.fromCharCode(code)))
                  DropdownMenuItem(value: String.fromCharCode(code), child: Text(String.fromCharCode(code)))],
            onChanged: !ready ? null : (value) async {
              final prefs = await SharedPreferences.getInstance();
              if (value == null || value.isEmpty) {
                await prefs.remove('shortcut_${command.key}');
              } else {
                await prefs.setString('shortcut_${command.key}', value);
              }
              await ShortcutBindings.instance.reload();
              if (mounted) setState(() {});
            },
          ),
        ),
    ]),
  );
}
