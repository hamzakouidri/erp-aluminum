import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../services/cloud_sync_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'workshop_profile_screen.dart';
import 'selected_systems_screen.dart';
import 'package:flutter/services.dart';
import '../sql_database.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _getCostMethodLabel(CostMethod method, AppLanguage lang) {
    if (method == CostMethod.linearMeter) {
      return Localization.translate('linear_meter', lang);
    } else if (method == CostMethod.squareMeter) {
      return Localization.translate('square_meter', lang);
    } else if (method == CostMethod.percentage) {
      return Localization.translate('percentage', lang);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate('settings', lang)),
        centerTitle: true,
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Workshop Profile Settings
          if (settings.isManager) ...[
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.storefront_rounded, color: Colors.blue),
                title: Text(
                  Localization.translate('معلومات الورشة', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const WorkshopProfileScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Display Settings
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.display_settings, color: Colors.blue),
              title: Text(
                Localization.translate('إعدادات الشاشة والمظهر', lang),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DisplaySettingsScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // Selected Systems Management Settings
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.dashboard_customize_rounded, color: Colors.teal),
              title: Text(
                Localization.translate('تحديد الأنظمة المستعملة بالورشة', lang),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
              subtitle: Text(
                Localization.translate('تفعيل وتخصيص أنظمة السلاسل والألمنيوم النشطة.', lang),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SelectedSystemsScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // Cloud Sync Backup/Restore
          if (settings.isManager) ...[
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: Icon(Icons.cloud_sync, color: Colors.blue),
                      title: Text(
                        Localization.translate('النسخ الاحتياطي (Cloud Sync)', lang),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      subtitle: Text(
                        Localization.translate('لحفظ بياناتك واسترجاعها عند تغيير الهاتف أو مسح التطبيق.', lang),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Wrap(
                          spacing: 16.0,
                          runSpacing: 12.0,
                          alignment: WrapAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? Colors.black : Colors.blue,
                                foregroundColor: Colors.white,
                                side: isDark ? const BorderSide(color: Colors.white, width: 1.5) : BorderSide.none,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                shape: isDark ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)) : null,
                              ),
                              icon: const Icon(Icons.cloud_upload),
                              label: Text(
                                Localization.translate('رفع للسحابة', lang),
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                              ),
                              onPressed: () async {
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (dialogContext) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                                try {
                                  await CloudSyncService().backupToCloud();
                                  if (!context.mounted) return;
                                  Navigator.of(context, rootNavigator: true).pop(); // pop dialog safely
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        Localization.translate('تم الرفع إلى السحابة بنجاح!', lang),
                                        style: TextStyle(fontFamily: 'Cairo'),
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                } catch (e) {
                                  if (!context.mounted) return;
                                  Navigator.of(context, rootNavigator: true).pop(); // pop dialog safely
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'حدث خطأ: $e',
                                        style: const TextStyle(fontFamily: 'Cairo'),
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? Colors.black : Colors.orange,
                                foregroundColor: Colors.white,
                                side: isDark ? const BorderSide(color: Colors.white, width: 1.5) : BorderSide.none,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                shape: isDark ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)) : null,
                              ),
                              icon: const Icon(Icons.cloud_download),
                              label: Text(
                                Localization.translate('استعادة البيانات', lang),
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                              ),
                              onPressed: () async {
                                bool? confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                      Localization.translate('استعادة البيانات', lang),
                                      style: TextStyle(fontFamily: 'Cairo'),
                                    ),
                                    content: Text(
                                      Localization.translate('سيتم مسح البيانات الحالية بالكامل واستبدالها بالنسخة السحابية المحفوظة. هل أنت متأكد؟', lang),
                                      style: TextStyle(fontFamily: 'Cairo'),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: Text(
                                          Localization.translate('إلغاء', lang),
                                          style: TextStyle(fontFamily: 'Cairo'),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: Text(
                                          Localization.translate('استعادة', lang),
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontFamily: 'Cairo',
                                          ),
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
                                    await CloudSyncService().init();
                                    await CloudSyncService().restoreFromCloud();
                                    if (!context.mounted) return;
                                    Navigator.of(context, rootNavigator: true).pop(); // pop dialog safely
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          Localization.translate('تمت الاستعادة بنجاح! يرجى إعادة تشغيل التطبيق.', lang),
                                          style: TextStyle(fontFamily: 'Cairo'),
                                        ),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    Navigator.of(context, rootNavigator: true).pop(); // pop dialog safely
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'حدث خطأ: $e',
                                          style: const TextStyle(fontFamily: 'Cairo'),
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Local Backup/Restore
          if (settings.isManager) ...[
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.storage, color: Colors.green),
                      title: Text(
                        Localization.translate('النسخ الاحتياطي المحلي (Local Backup)', lang),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      subtitle: Text(
                        Localization.translate('حفظ نسخة احتياطية مباشرة على جهازك كملف خارجي أو استيرادها.', lang),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Wrap(
                          spacing: 16.0,
                          runSpacing: 12.0,
                          alignment: WrapAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? Colors.black : Colors.teal,
                                foregroundColor: Colors.white,
                                side: isDark ? const BorderSide(color: Colors.white, width: 1.5) : BorderSide.none,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                shape: isDark ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)) : null,
                              ),
                              icon: const Icon(Icons.folder_shared),
                              label: Text(
                                Localization.translate('تصدير ملف .db', lang),
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                              ),
                              onPressed: () async {
                                await SqlDatabase().exportDatabaseFile(context);
                              },
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? Colors.black : Colors.blueGrey,
                                foregroundColor: Colors.white,
                                side: isDark ? const BorderSide(color: Colors.white, width: 1.5) : BorderSide.none,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                shape: isDark ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)) : null,
                              ),
                              icon: const Icon(Icons.file_open),
                              label: Text(
                                Localization.translate('استيراد ملف .db', lang),
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                              ),
                              onPressed: () async {
                                bool? confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                      Localization.translate('استيراد قاعدة البيانات', lang),
                                      style: const TextStyle(fontFamily: 'Cairo'),
                                    ),
                                    content: Text(
                                      Localization.translate('سيتم استبدال قاعدة البيانات الحالية بالكامل بالملف المختار. هل أنت متأكد؟', lang),
                                      style: const TextStyle(fontFamily: 'Cairo'),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: Text(
                                          Localization.translate('إلغاء', lang),
                                          style: const TextStyle(fontFamily: 'Cairo'),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: Text(
                                          Localization.translate('استيراد', lang),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  if (!context.mounted) return;
                                    await SqlDatabase().importDatabaseFile(context);
                                }
                              },
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? Colors.black : Colors.green,
                                foregroundColor: Colors.white,
                                side: isDark ? const BorderSide(color: Colors.white, width: 1.5) : BorderSide.none,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                shape: isDark ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)) : null,
                              ),
                              icon: const Icon(Icons.download),
                              label: Text(
                                Localization.translate('تصدير نسخة JSON', lang),
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                              ),
                              onPressed: () async {
                                await SqlDatabase().exportJsonBackup(context);
                              },
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? Colors.black : Colors.amber[800],
                                foregroundColor: Colors.white,
                                side: isDark ? const BorderSide(color: Colors.white, width: 1.5) : BorderSide.none,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                shape: isDark ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)) : null,
                              ),
                              icon: const Icon(Icons.upload),
                              label: Text(
                                Localization.translate('استيراد نسخة JSON', lang),
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                              ),
                              onPressed: () async {
                                bool? confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                      Localization.translate('استيراد نسخة JSON', lang),
                                      style: const TextStyle(fontFamily: 'Cairo'),
                                    ),
                                    content: Text(
                                      Localization.translate('سيتم دمج وتحديث البيانات الحالية بالبيانات المكتوبة بملف JSON. هل أنت متأكد؟', lang),
                                      style: const TextStyle(fontFamily: 'Cairo'),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: Text(
                                          Localization.translate('إلغاء', lang),
                                          style: const TextStyle(fontFamily: 'Cairo'),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: Text(
                                          Localization.translate('استيراد', lang),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  if (!context.mounted) return;
                                  await SqlDatabase().importJsonBackup(context);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Global Catalog Sync
          if (settings.isManager)
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: Icon(Icons.library_books, color: Colors.purple),
                      title: Text(
                        Localization.translate('كتالوج البروفيلات العالمي', lang),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      subtitle: Text(
                        Localization.translate('تحديث بيانات البروفيلات والإكسسوارات من الكتالوج المركزي. (لن يؤثر على بيانات الطلبيات والزبائن والمشتريات الخاصة بك)', lang),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? Colors.black : Colors.purple,
                          foregroundColor: Colors.white,
                          side: isDark ? const BorderSide(color: Colors.white, width: 1.5) : BorderSide.none,
                          shape: isDark ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)) : null,
                        ),
                        icon: const Icon(Icons.download),
                        label: Text(
                          Localization.translate('تحديث الكتالوج الآن', lang),
                          style: TextStyle(fontFamily: 'Cairo'),
                        ),
                        onPressed: () async {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                          try {
                            await CloudSyncService().init();
                            await CloudSyncService().downloadGlobalCatalog();
                            if (!context.mounted) return;
                            Navigator.of(
                              context,
                              rootNavigator: true,
                            ).pop(); // Close the dialog safely
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  Localization.translate('تم تحديث البروفيلات والإكسسوارات بنجاح!', lang),
                                  style: TextStyle(fontFamily: 'Cairo'),
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            Navigator.of(
                              context,
                              rootNavigator: true,
                            ).pop(); // Close the dialog safely
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'حدث خطأ: $e',
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
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
          if (FirebaseAuth.instance.currentUser?.email ==
              'kouidrihamza45@gmail.com')
            Card(
              color: Theme.of(context).cardColor,
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: Icon(Icons.upload_file, color: Colors.purple),
                      title: Text(
                        Localization.translate('تصدير / رفع الكتالوج (للمدير فقط)', lang),
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        Localization.translate('استخدم هذا الزر لرفع الكتالوج الموجود بجهازك حالياً ليصبح هو الكتالوج المركزي في السحابة.', lang),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[850]
                              : Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.cloud_upload, color: Colors.white),
                        label: Text(
                          Localization.translate('رفع الكتالوج الآن', lang),
                          style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (dialogContext) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                          try {
                            await CloudSyncService().backupGlobalCatalog();
                            if (!context.mounted) return;
                            Navigator.of(
                              context,
                              rootNavigator: true,
                            ).pop(); // pop dialog
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  Localization.translate('تم رفع الكتالوج المركزي بنجاح!', lang),
                                  style: TextStyle(fontFamily: 'Cairo'),
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            Navigator.of(
                              context,
                              rootNavigator: true,
                            ).pop(); // pop dialog
                            showDialog(
                              context: context,
                              builder: (dialogCtx) => AlertDialog(
                                title: Text(
                                  'خطأ Firebase',
                                  style: TextStyle(fontFamily: 'Cairo'),
                                ),
                                content: Text(
                                  e.toString(),
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialogCtx),
                                    child: Text(
                                      'حسنا',
                                      style: TextStyle(fontFamily: 'Cairo'),
                                    ),
                                  ),
                                ],
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

          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.calculate, color: Colors.blue),
              title: Text(
                Localization.translate('cost_calculation_method', lang),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
              subtitle: Text(
                _getCostMethodLabel(settings.costMethod, lang),
                style: const TextStyle(color: Colors.blue, fontFamily: 'Cairo'),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: Text(
                        Localization.translate('cost_calculation_method', lang),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: CostMethod.values.map((method) {
                          return RadioListTile<CostMethod>(
                            title: Text(
                              _getCostMethodLabel(method, lang),
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            value: method,
                            groupValue: settings.costMethod,
                            onChanged: (CostMethod? value) {
                              if (value != null) {
                                settings.setCostMethod(value);
                                Navigator.pop(context);
                              }
                            },
                          );
                        }).toList(),
                      ),
                    );
                  },
                );
              },
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
                    Expanded(
                      child: Text(
                        Localization.translate('نسبة الفائدة (Pourcentage)', lang),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
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
          if (settings.isManager)
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
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.smart_toy, color: Colors.purple),
                    title: Text(
                      Localization.translate('مفتاح الذكاء الاصطناعي (Gemini API Key)', lang),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    subtitle: Text(
                      Localization.translate('مطلوب لعمل المساعد الصوتي الذكي', lang),
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
                  TextFormField(
                    initialValue: settings.geminiApiKey,
                    decoration: InputDecoration(
                      hintText: Localization.translate('ألصق المفتاح هنا...', lang),
                      hintStyle: const TextStyle(fontFamily: 'Cairo'),
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
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.red),
              title: Text(
                Localization.translate('إغلاق التطبيق', lang),
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
              onTap: () {
                SystemNavigator.pop();
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class DisplaySettingsScreen extends StatelessWidget {
  const DisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate('إعدادات الشاشة والمظهر', lang),
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.blue,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // View Mode Setting
          Card(
            elevation: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    Localization.translate('طريقة العرض (View Mode)', lang),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                RadioListTile<AppViewMode>(
                  title: Text(
                    Localization.translate('عادي (كلاسيكي)', lang),
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                  value: AppViewMode.classic,
                  groupValue: settings.viewMode,
                  onChanged: (AppViewMode? mode) {
                    if (mode != null) settings.setViewMode(mode);
                  },
                ),
                RadioListTile<AppViewMode>(
                  title: Text(
                    Localization.translate('تبويبات (متصفح)', lang),
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                  value: AppViewMode.tabs,
                  groupValue: settings.viewMode,
                  onChanged: (AppViewMode? mode) {
                    if (mode != null) settings.setViewMode(mode);
                  },
                ),
                RadioListTile<AppViewMode>(
                  title: Text(
                    Localization.translate('نوافذ مصغرة', lang),
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                  subtitle: Text(
                    Localization.translate('فتح الصفحات كنوافذ يمكن تحريكها وتصغيرها', lang),
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                  value: AppViewMode.windows,
                  groupValue: settings.viewMode,
                  onChanged: (AppViewMode? mode) {
                    if (mode != null) settings.setViewMode(mode);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Language Setting
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.language, color: Colors.blue),
              title: Text(
                Localization.translate('language', lang),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              trailing: DropdownButton<AppLanguage>(
                value: lang,
                underline: const SizedBox(),
                items: AppLanguage.values.map((l) {
                  return DropdownMenuItem(
                    value: l,
                    child: Text(
                      Localization.translate(l.name, lang),
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
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
              title: Text(
                Localization.translate('theme', lang),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              subtitle: Text(
                settings.isDarkMode
                    ? Localization.translate('dark_mode', lang)
                    : Localization.translate('light_mode', lang),
                style: const TextStyle(fontFamily: 'Cairo'),
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
                    title: Text(
                      Localization.translate('font_size', lang),
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
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
        ],
      ),
    );
  }
}
