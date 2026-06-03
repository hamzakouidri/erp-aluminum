import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../services/cloud_sync_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;

    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate('settings', lang)),
        centerTitle: true,
        backgroundColor: Colors.blue,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Language Setting
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.language, color: Colors.blue),
              title: Text(Localization.translate('language', lang)),
              trailing: DropdownButton<AppLanguage>(
                value: lang,
                underline: const SizedBox(),
                items: AppLanguage.values.map((l) {
                  return DropdownMenuItem(
                    value: l,
                    child: Text(Localization.translate(l.name, lang)),
                  );
                }).toList(),
                onChanged: (AppLanguage? newLang) {
                  if (newLang != null) {
                    settings.setLanguage(newLang);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Theme Setting
          Card(
            elevation: 2,
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode, color: Colors.blue),
              title: Text(Localization.translate('theme', lang)),
              subtitle: Text(
                settings.isDarkMode
                    ? Localization.translate('dark_mode', lang)
                    : Localization.translate('light_mode', lang),
              ),
              value: settings.isDarkMode,
              onChanged: (bool isDark) {
                settings.setTheme(isDark ? ThemeMode.dark : ThemeMode.light);
              },
            ),
          ),
          const SizedBox(height: 10),

          // Font Size Setting
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const Icon(Icons.format_size, color: Colors.blue),
                    title: Text(Localization.translate('font_size', lang)),
                  ),
                  Slider(
                    value: settings.fontSizeScale,
                    min: 0.8,
                    max: 1.5,
                    divisions: 7,
                    label: settings.fontSizeScale.toStringAsFixed(1),
                    onChanged: (double val) {
                      settings.setFontSizeScale(val);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Cloud Sync Backup/Restore
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ListTile(
                    leading: Icon(Icons.cloud_sync, color: Colors.blue),
                    title: Text(
                      'النسخ الاحتياطي (Cloud Sync)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'لحفظ بياناتك واسترجاعها عند تغيير الهاتف أو مسح التطبيق.',
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text('رفع للسحابة'),
                        onPressed: () async {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                          try {
                            await CloudSyncService().backupToCloud();
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم الرفع إلى السحابة بنجاح!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('حدث خطأ: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.cloud_download),
                        label: const Text('استعادة البيانات'),
                        onPressed: () async {
                          bool? confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('استعادة البيانات'),
                              content: const Text(
                                'سيتم مسح البيانات الحالية بالكامل واستبدالها بالنسخة السحابية المحفوظة. هل أنت متأكد؟',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('إلغاء'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text(
                                    'استعادة',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                            try {
                              await CloudSyncService().restoreFromCloud();
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'تمت الاستعادة بنجاح! يرجى إعادة تشغيل التطبيق.',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } catch (e) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('حدث خطأ: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Global Catalog Sync
          if (settings.isManager)
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ListTile(
                      leading: Icon(Icons.library_books, color: Colors.purple),
                      title: Text(
                        'كتالوج البروفيلات العالمي',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'تحديث بيانات البروفيلات والإكسسوارات من الكتالوج المركزي. (لن يؤثر على بيانات الطلبيات والزبائن والمشتريات الخاصة بك)',
                      ),
                    ),
                    Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.download),
                        label: const Text('تحديث الكتالوج الآن'),
                        onPressed: () async {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                          try {
                            await CloudSyncService().downloadGlobalCatalog();
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'تم تحديث البروفيلات والإكسسوارات بنجاح!',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('حدث خطأ: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),

          // Cost Calculation Method Setting
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.calculate, color: Colors.blue),
              title: Text(
                Localization.translate('cost_calculation_method', lang),
              ),
              trailing: DropdownButton<CostMethod>(
                value: settings.costMethod,
                underline: const SizedBox(),
                items: CostMethod.values.map((method) {
                  String label = '';
                  if (method == CostMethod.linearMeter) {
                    label = Localization.translate('linear_meter', lang);
                  } else if (method == CostMethod.squareMeter) {
                    label = Localization.translate('square_meter', lang);
                  } else if (method == CostMethod.percentage) {
                    label = Localization.translate('percentage', lang);
                  }
                  return DropdownMenuItem(value: method, child: Text(label));
                }).toList(),
                onChanged: (CostMethod? newMethod) {
                  if (newMethod != null) {
                    settings.setCostMethod(newMethod);
                  }
                },
              ),
            ),
          ),

          if (settings.costMethod == CostMethod.percentage)
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.percent, color: Colors.blue),
                    const SizedBox(width: 15),
                    const Expanded(
                      child: Text(
                        'نسبة الفائدة (Pourcentage)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(
                          text: settings.profitMargin.toString(),
                        ),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          suffixText: '%',
                        ),
                        onSubmitted: (value) {
                          double? margin = double.tryParse(value);
                          if (margin != null) {
                            settings.setProfitMargin(margin);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 10),

          // Gemini API Key Setting
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.smart_toy, color: Colors.purple),
                    title: Text(
                      'مفتاح الذكاء الاصطناعي (Gemini API Key)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('مطلوب لعمل المساعد الصوتي الذكي'),
                  ),
                  TextFormField(
                    initialValue: settings.geminiApiKey,
                    decoration: InputDecoration(
                      hintText: 'ألصق المفتاح هنا...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (val) {
                      settings.setGeminiApiKey(val);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
