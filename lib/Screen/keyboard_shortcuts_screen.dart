import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KeyboardShortcutsScreen extends StatefulWidget {
  const KeyboardShortcutsScreen({super.key});
  @override
  State<KeyboardShortcutsScreen> createState() => _KeyboardShortcutsScreenState();
}

class _KeyboardShortcutsScreenState extends State<KeyboardShortcutsScreen> {
  String? selected;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        selected = prefs.getString('shortcut_drawing_mode');
        ready = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('اختصارات لوحة المفاتيح')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('اختصار تبديل وضع الرسم والتحريك داخل صفحة الرسم. لا يعمل أثناء الكتابة أو فتح نافذة حوار.'),
      const SizedBox(height: 20),
      DropdownButtonFormField<String>(
        value: selected,
        decoration: const InputDecoration(labelText: 'تبديل وضع الرسم'),
        hint: const Text('غير مفعّل'),
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
      }, child: const Text('إلغاء الاختصار')),
    ]),
  );
}
