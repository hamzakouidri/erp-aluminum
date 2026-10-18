import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/Systeme/cutting_settings.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

class CuttingSettingsScreen extends StatefulWidget {
  const CuttingSettingsScreen({super.key});

  @override
  State<CuttingSettingsScreen> createState() => _CuttingSettingsScreenState();
}

class _CuttingSettingsScreenState extends State<CuttingSettingsScreen> {
  final SqlDatabase _db = SqlDatabase();
  final _sawKerfController = TextEditingController();
  final _minimumReusableLengthController = TextEditingController();
  final Map<String, TextEditingController> _remnantControllers = {
    for (final spec in _remnantThresholdSpecs)
      spec.key: TextEditingController(),
  };

  static const _remnantThresholdSpecs = <({String key, String label})>[
    (key: 'frame', label: 'الإطار بدون غطاء جانبي'),
    (key: 'frame_side_cover', label: 'الإطار بغطاء جانبي'),
    (key: 'mullion', label: 'التقسيم / الفاصل'),
    (key: 'sash', label: 'الدلفة / الكانة'),
  ];

  bool _isLoading = true;
  bool _isSaving = false;

  String _t(String key) {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    return Localization.translate(key, lang);
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  String _formatNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  double? _positiveNumber(String raw) {
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    return value != null && value > 0 ? value : null;
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedSawKerf =
          await _db.readSawKerfMm() ?? prefs.getDouble('saw_kerf_mm') ?? 4.0;
      CuttingSettings.setSawKerfMm(storedSawKerf);
      _sawKerfController.text = _formatNumber(storedSawKerf);

      final globalMinimum = await _db.readMinimumReusableLengthMm();
      _minimumReusableLengthController.text = globalMinimum == null
          ? ''
          : _formatNumber(globalMinimum);
      final remnantMinimums = await _db.readMinimumReusableLengthsMm();
      for (final spec in _remnantThresholdSpecs) {
        final value = remnantMinimums[spec.key];
        _remnantControllers[spec.key]!.text = value == null
            ? ''
            : _formatNumber(value);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_t('تعذر تحميل إعدادات القص')}: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    final sawKerfMm = _positiveNumber(_sawKerfController.text);
    final globalMinimum = _positiveNumber(
      _minimumReusableLengthController.text,
    );
    if (sawKerfMm == null || globalMinimum == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t('أدخل فاقد المنشار والحد العام للفضلة بقيم أكبر من صفر.'),
          ),
        ),
      );
      return;
    }

    final remnantMinimums = <String, double>{};
    for (final spec in _remnantThresholdSpecs) {
      final raw = _remnantControllers[spec.key]!.text.trim();
      if (raw.isEmpty) continue;
      final value = _positiveNumber(raw);
      if (value == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_t('قيمة')} ${_t(spec.label)} ${_t('يجب أن تكون أكبر من صفر.')}',
            ),
          ),
        );
        return;
      }
      remnantMinimums[spec.key] = value;
    }

    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('saw_kerf_mm', sawKerfMm);
      await _db.saveSawKerfMm(sawKerfMm);
      await _db.saveMinimumReusableLengthMm(globalMinimum);
      for (final entry in remnantMinimums.entries) {
        await _db.saveMinimumReusableLengthMm(
          entry.value,
          itemKey: entry.key,
        );
      }
      CuttingSettings.setSawKerfMm(sawKerfMm);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('تم حفظ إعدادات القص والفضلات بنجاح')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_t('خطأ في حفظ إعدادات القص')}: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _sawKerfController.dispose();
    _minimumReusableLengthController.dispose();
    for (final controller in _remnantControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sectionColor = isDark ? Colors.blue.shade300 : Colors.blue.shade800;
    final lang = Provider.of<AppSettingsProvider>(context).language;

    if (_isLoading) {
      // Keep the form visible immediately while the local database is read.
      // This avoids making the settings card look like it needs a long press.
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate('القص والفضلات', lang)),
        actions: [
          IconButton(
            onPressed: _isLoading || _isSaving ? null : _saveSettings,
            icon: const Icon(Icons.save),
            tooltip: Localization.translate('حفظ الإعدادات', lang),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              Localization.translate('القص والفضلات', lang),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: sectionColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              Localization.translate(
                'تُستخدم هذه القيم في حساب عدد القضبان. أدخل القيم بالمليمتر؛ مثال: 5 مم = نصف سنتيمتر. الحد الخاص بنوع البروفيل يتقدم على الحد العام.',
                lang,
              ),
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sawKerfController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: Localization.translate(
                  'فاقد شفرة المنشار لكل قص (مم)',
                  lang,
                ),
                hintText: Localization.translate('مثال: 4 أو 5', lang),
                prefixIcon: Icon(Icons.content_cut),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _minimumReusableLengthController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: Localization.translate(
                  'الحد العام للفضلة القابلة للاستعمال (مم)',
                  lang,
                ),
                hintText: Localization.translate('مثال: 300', lang),
                prefixIcon: Icon(Icons.straighten),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            ..._remnantThresholdSpecs.map(
              (spec) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _remnantControllers[spec.key],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        '${Localization.translate(spec.label, lang)} — ${Localization.translate('أقل فضلة (مم)', lang)}',
                    hintText: Localization.translate(
                      'اتركه فارغًا لاستعمال الحد العام',
                      lang,
                    ),
                    prefixIcon: const Icon(Icons.view_stream_outlined),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isLoading || _isSaving ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(Localization.translate('حفظ إعدادات القص', lang)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 46),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
