import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/worker_push_notification_service.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _loading = true;
  bool _manager = false;
  Map<String, bool> _values = {};

  static const _workerTypes = <String, String>{
    'worker_assignment': 'إسناد مهمة جديدة',
  };
  static const _managerTypes = <String, String>{
    'cashbox': 'حركة صندوق الورشة',
    'payments': 'المقبوضات والمدفوعات',
    'invoices': 'الفواتير',
    'deliveries': 'التسليمات ووصول السلع',
    'inventory': 'دخول المواد إلى الورشة',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? 'worker';
    _manager = const {'owner', 'manager', 'co_manager', 'admin'}.contains(role);
    final types = _manager ? _managerTypes.keys : _workerTypes.keys;
    final values = await WorkerPushNotificationService.instance.loadPreferences(
      types,
    );
    if (mounted)
      setState(() {
        _values = values;
        _loading = false;
      });
  }

  Future<void> _change(String type, bool value) async {
    setState(() => _values[type] = value);
    try {
      await WorkerPushNotificationService.instance.savePreference(type, value);
    } catch (_) {
      if (mounted) setState(() => _values[type] = !value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isArabic = lang == AppLanguage.arabic;
    final entries = _manager ? _managerTypes : _workerTypes;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate('إعدادات الإشعارات', lang),
          style: TextStyle(
            fontFamily: isArabic ? 'Cairo' : null,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: entries.entries
                  .map(
                    (entry) => Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SwitchListTile(
                        secondary: Icon(
                          Icons.notifications_active_outlined,
                          color: Theme.of(context).primaryColor,
                        ),
                        title: Text(
                          Localization.translate(entry.value, lang),
                          style: TextStyle(
                            fontFamily: isArabic ? 'Cairo' : null,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        value: _values[entry.key] ?? true,
                        onChanged: (value) => _change(entry.key, value),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}
