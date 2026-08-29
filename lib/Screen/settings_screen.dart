import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../services/cloud_sync_service.dart';
import '../services/supabase_catalog_sync_service.dart';
import '../services/supabase_workshop_sync_service.dart';
import 'workshop_profile_screen.dart';
import 'selected_systems_screen.dart';
import 'package:flutter/services.dart';
import '../sql_database.dart';

class _SupabaseCredentials {
  const _SupabaseCredentials({
    required this.email,
    required this.password,
    required this.createAccount,
  });

  final String email;
  final String password;
  final bool createAccount;
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<bool> _ensureSupabaseCatalogLogin(BuildContext context) async {
    final service = SupabaseCatalogSyncService();
    if (service.isSignedIn) return true;

    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    try {
      final credentials = await showDialog<_SupabaseCredentials>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'تسجيل دخول Supabase',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'البريد'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'كلمة المرور'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    _SupabaseCredentials(
                      email: emailController.text,
                      password: passwordController.text,
                      createAccount: true,
                    ),
                  );
                },
                child: const Text('إنشاء حساب'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                    _SupabaseCredentials(
                      email: emailController.text,
                      password: passwordController.text,
                      createAccount: false,
                    ),
                  );
                },
                child: const Text('دخول'),
              ),
            ],
          );
        },
      );

      if (credentials == null) return false;
      if (credentials.createAccount) {
        await service.signUpWithPassword(
          email: credentials.email,
          password: credentials.password,
        );
      } else {
        await service.signInWithPassword(
          email: credentials.email,
          password: credentials.password,
        );
      }
      return true;
    } finally {
      emailController.dispose();
      passwordController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final isAllowed = settings.isManager || settings.canAccessSettings();
    final lang = settings.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showLegacyFirebaseCloudSync = bool.fromEnvironment(
      'SHOW_LEGACY_FIREBASE_SYNC',
    );

    if (!isAllowed) {
      return Scaffold(
        appBar: AppBar(
          title: Text(Localization.translate('settings', lang)),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              Localization.translate(
                'عذراً، ليس لديك صلاحية للوصول إلى هذه الشاشة.',
                lang,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 16),
            ),
          ),
        ),
      );
    }

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
                leading: const Icon(
                  Icons.storefront_rounded,
                  color: Colors.blue,
                ),
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
              leading: const Icon(
                Icons.dashboard_customize_rounded,
                color: Colors.teal,
              ),
              title: Text(
                Localization.translate('تحديد الأنظمة المستعملة بالورشة', lang),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
              subtitle: Text(
                Localization.translate(
                  'تفعيل وتخصيص أنظمة السلاسل والألمنيوم النشطة.',
                  lang,
                ),
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
          if (showLegacyFirebaseCloudSync &&
              (settings.isManager || settings.canBackupToCloud())) ...[
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
                        Localization.translate(
                          'النسخ الاحتياطي (Cloud Sync)',
                          lang,
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      subtitle: Text(
                        Localization.translate(
                          'لحفظ بياناتك واسترجاعها عند تغيير الهاتف أو مسح التطبيق.',
                          lang,
                        ),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Wrap(
                          spacing: 16.0,
                          runSpacing: 12.0,
                          alignment: WrapAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark
                                    ? Colors.black
                                    : Colors.blue,
                                foregroundColor: Colors.white,
                                side: isDark
                                    ? const BorderSide(
                                        color: Colors.white,
                                        width: 1.5,
                                      )
                                    : BorderSide.none,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                shape: isDark
                                    ? RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      )
                                    : null,
                              ),
                              icon: const Icon(Icons.cloud_upload),
                              label: Text(
                                Localization.translate('رفع للسحابة', lang),
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                              ),
                              onPressed: () async {
                                showDialog(
                                  context: context,
                                  useRootNavigator: true,
                                  barrierDismissible: false,
                                  builder: (dialogContext) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                                bool success = false;
                                String errorMsg = '';
                                try {
                                  final cloudSync = CloudSyncService();
                                  cloudSync.lastBackupUploadSummary = '';
                                  cloudSync.lastCatalogUploadSummary = '';
                                  await cloudSync.backupToCloud();
                                  if (settings.userRole == 'admin' || isAdmin) {
                                    await cloudSync.backupGlobalCatalog();
                                  }
                                  success = true;
                                } catch (e) {
                                  errorMsg = e.toString().replaceAll(
                                    'Exception: ',
                                    '',
                                  );
                                } finally {
                                  if (context.mounted) {
                                    Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).pop();
                                    if (success) {
                                      final backupSummary = CloudSyncService()
                                          .lastBackupUploadSummary;
                                      final catalogSummary = CloudSyncService()
                                          .lastCatalogUploadSummary;
                                      final summary =
                                          [backupSummary, catalogSummary]
                                              .where(
                                                (value) => value.isNotEmpty,
                                              )
                                              .join(' — ');
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            summary.isEmpty
                                                ? Localization.translate(
                                                    'تم الرفع إلى السحابة بنجاح!',
                                                    lang,
                                                  )
                                                : 'تم الرفع إلى السحابة بنجاح. $summary',
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'حدث خطأ: $errorMsg',
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark
                                    ? Colors.black
                                    : Colors.orange,
                                foregroundColor: Colors.white,
                                side: isDark
                                    ? const BorderSide(
                                        color: Colors.white,
                                        width: 1.5,
                                      )
                                    : BorderSide.none,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                shape: isDark
                                    ? RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      )
                                    : null,
                              ),
                              icon: const Icon(Icons.cloud_download),
                              label: Text(
                                Localization.translate(
                                  'استعادة البيانات',
                                  lang,
                                ),
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                              ),
                              onPressed: () async {
                                bool? confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                      Localization.translate(
                                        'استعادة البيانات',
                                        lang,
                                      ),
                                      style: TextStyle(fontFamily: 'Cairo'),
                                    ),
                                    content: Text(
                                      Localization.translate(
                                        'سيتم مسح البيانات الحالية بالكامل واستبدالها بالنسخة السحابية المحفوظة. هل أنت متأكد؟',
                                        lang,
                                      ),
                                      style: TextStyle(fontFamily: 'Cairo'),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: Text(
                                          Localization.translate('إلغاء', lang),
                                          style: TextStyle(fontFamily: 'Cairo'),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text(
                                          Localization.translate(
                                            'استعادة',
                                            lang,
                                          ),
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
                                    useRootNavigator: true,
                                    barrierDismissible: false,
                                    builder: (_) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                  bool success = false;
                                  String errorMsg = '';
                                  try {
                                    await CloudSyncService().init();
                                    await CloudSyncService().restoreFromCloud();
                                    success = true;
                                  } catch (e) {
                                    errorMsg = e.toString().replaceAll(
                                      'Exception: ',
                                      '',
                                    );
                                  } finally {
                                    if (context.mounted) {
                                      Navigator.of(
                                        context,
                                        rootNavigator: true,
                                      ).pop();
                                      if (success) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              Localization.translate(
                                                'تمت الاستعادة بنجاح! يرجى إعادة تشغيل التطبيق.',
                                                lang,
                                              ),
                                              style: const TextStyle(
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      } else {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'حدث خطأ أثناء الاستعادة: $errorMsg',
                                              style: const TextStyle(
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
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

          if (settings.isManager || settings.canBackupToCloud()) ...[
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.sync_alt_rounded,
                        color: Colors.deepPurple,
                      ),
                      title: Text(
                        Localization.translate('مزامنة Supabase السريعة', lang),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      subtitle: Text(
                        Localization.translate(
                          'ارفع بيانات الورشة كاملة أول مرة، وبعدها يتم رفع وتنزيل التغييرات فقط بشكل خفيف.',
                          lang,
                        ),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark
                                    ? Colors.black
                                    : Colors.deepPurple,
                                foregroundColor: Colors.white,
                                side: isDark
                                    ? const BorderSide(
                                        color: Colors.white,
                                        width: 1.5,
                                      )
                                    : BorderSide.none,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                              icon: const Icon(Icons.cloud_upload_rounded),
                              label: const Text(
                                'رفع بيانات الورشة كاملة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                              ),
                              onPressed: () async {
                                try {
                                  final ready =
                                      await _ensureSupabaseCatalogLogin(
                                        context,
                                      );
                                  if (!ready || !context.mounted) return;
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'تعذر تسجيل دخول Supabase: ${e.toString().replaceAll('Exception: ', '')}',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }

                                showDialog(
                                  context: context,
                                  useRootNavigator: true,
                                  barrierDismissible: false,
                                  builder: (_) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                                bool success = false;
                                String errorMsg = '';
                                try {
                                  await SupabaseWorkshopSyncService()
                                      .uploadFullWorkshopData();
                                  SupabaseWorkshopSyncService().start();
                                  success = true;
                                } catch (e) {
                                  errorMsg = e.toString().replaceAll(
                                    'Exception: ',
                                    '',
                                  );
                                } finally {
                                  if (context.mounted) {
                                    Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          success
                                              ? SupabaseWorkshopSyncService()
                                                    .lastUploadSummary
                                              : 'فشل رفع بيانات الورشة: $errorMsg',
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                        backgroundColor: success
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark
                                    ? Colors.black
                                    : Colors.indigo,
                                foregroundColor: Colors.white,
                                side: isDark
                                    ? const BorderSide(
                                        color: Colors.white,
                                        width: 1.5,
                                      )
                                    : BorderSide.none,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                              icon: const Icon(Icons.cloud_download_rounded),
                              label: const Text(
                                'تنزيل بيانات الورشة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                              ),
                              onPressed: () async {
                                try {
                                  final ready =
                                      await _ensureSupabaseCatalogLogin(
                                        context,
                                      );
                                  if (!ready || !context.mounted) return;
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'تعذر تسجيل دخول Supabase: ${e.toString().replaceAll('Exception: ', '')}',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }

                                showDialog(
                                  context: context,
                                  useRootNavigator: true,
                                  barrierDismissible: false,
                                  builder: (_) => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                                bool success = false;
                                String errorMsg = '';
                                try {
                                  await SupabaseWorkshopSyncService()
                                      .downloadWorkshopData(full: true);
                                  SupabaseWorkshopSyncService().start();
                                  success = true;
                                } catch (e) {
                                  errorMsg = e.toString().replaceAll(
                                    'Exception: ',
                                    '',
                                  );
                                } finally {
                                  if (context.mounted) {
                                    Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          success
                                              ? SupabaseWorkshopSyncService()
                                                    .lastDownloadSummary
                                              : 'فشل تنزيل بيانات الورشة: $errorMsg',
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                        backgroundColor: success
                                            ? Colors.green
                                            : Colors.red,
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
          if (settings.isManager ||
              settings.canBackupToCloud() ||
              settings.canAccessLocalJsonBackup()) ...[
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
                        Localization.translate(
                          'النسخ الاحتياطي المحلي (Local Backup)',
                          lang,
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      subtitle: Text(
                        Localization.translate(
                          'حفظ نسخة احتياطية مباشرة على جهازك كملف خارجي أو استيرادها.',
                          lang,
                        ),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Wrap(
                          spacing: 16.0,
                          runSpacing: 12.0,
                          alignment: WrapAlignment.center,
                          children: [
                            if (settings.isManager ||
                                settings.canBackupToCloud()) ...[
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDark
                                      ? Colors.black
                                      : Colors.teal,
                                  foregroundColor: Colors.white,
                                  side: isDark
                                      ? const BorderSide(
                                          color: Colors.white,
                                          width: 1.5,
                                        )
                                      : BorderSide.none,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  shape: isDark
                                      ? RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        )
                                      : null,
                                ),
                                icon: const Icon(Icons.folder_shared),
                                label: Text(
                                  Localization.translate('تصدير ملف .db', lang),
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                ),
                                onPressed: () async {
                                  await SqlDatabase().exportDatabaseFile(
                                    context,
                                  );
                                },
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDark
                                      ? Colors.black
                                      : Colors.blueGrey,
                                  foregroundColor: Colors.white,
                                  side: isDark
                                      ? const BorderSide(
                                          color: Colors.white,
                                          width: 1.5,
                                        )
                                      : BorderSide.none,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  shape: isDark
                                      ? RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        )
                                      : null,
                                ),
                                icon: const Icon(Icons.file_open),
                                label: Text(
                                  Localization.translate(
                                    'استيراد ملف .db',
                                    lang,
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                ),
                                onPressed: () async {
                                  bool? confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(
                                        Localization.translate(
                                          'استيراد قاعدة البيانات',
                                          lang,
                                        ),
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      content: Text(
                                        Localization.translate(
                                          'سيتم استبدال قاعدة البيانات الحالية بالكامل بالملف المختار. هل أنت متأكد؟',
                                          lang,
                                        ),
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: Text(
                                            Localization.translate(
                                              'إلغاء',
                                              lang,
                                            ),
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: Text(
                                            Localization.translate(
                                              'استيراد',
                                              lang,
                                            ),
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
                                    await SqlDatabase().importDatabaseFile(
                                      context,
                                    );
                                  }
                                },
                              ),
                            ],
                            if (settings.canAccessLocalJsonBackup()) ...[
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDark
                                      ? Colors.black
                                      : Colors.green,
                                  foregroundColor: Colors.white,
                                  side: isDark
                                      ? const BorderSide(
                                          color: Colors.white,
                                          width: 1.5,
                                        )
                                      : BorderSide.none,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  shape: isDark
                                      ? RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        )
                                      : null,
                                ),
                                icon: const Icon(Icons.download),
                                label: Text(
                                  Localization.translate(
                                    'تصدير نسخة JSON',
                                    lang,
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                ),
                                onPressed: () async {
                                  await SqlDatabase().exportJsonBackup(context);
                                },
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDark
                                      ? Colors.black
                                      : Colors.amber[800],
                                  foregroundColor: Colors.white,
                                  side: isDark
                                      ? const BorderSide(
                                          color: Colors.white,
                                          width: 1.5,
                                        )
                                      : BorderSide.none,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  shape: isDark
                                      ? RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        )
                                      : null,
                                ),
                                icon: const Icon(Icons.upload),
                                label: Text(
                                  Localization.translate(
                                    'استيراد نسخة JSON',
                                    lang,
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                ),
                                onPressed: () async {
                                  bool? confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(
                                        Localization.translate(
                                          'استيراد نسخة JSON',
                                          lang,
                                        ),
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      content: Text(
                                        Localization.translate(
                                          'سيتم دمج وتحديث البيانات الحالية بالبيانات المكتوبة بملف JSON. هل أنت متأكد؟',
                                          lang,
                                        ),
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: Text(
                                            Localization.translate(
                                              'إلغاء',
                                              lang,
                                            ),
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: Text(
                                            Localization.translate(
                                              'استيراد',
                                              lang,
                                            ),
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
                                    await SqlDatabase().importJsonBackup(
                                      context,
                                    );
                                  }
                                },
                              ),
                            ],
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
          if (settings.isManager || settings.canSyncGlobalCatalog())
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
                        Localization.translate(
                          'كتالوج البروفيلات العالمي',
                          lang,
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      subtitle: Text(
                        Localization.translate(
                          'تحديث بيانات البروفيلات والإكسسوارات من الكتالوج المركزي. (لن يؤثر على بيانات الطلبيات والزبائن والمشتريات الخاصة بك)',
                          lang,
                        ),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? Colors.black
                              : Colors.purple,
                          foregroundColor: Colors.white,
                          side: isDark
                              ? const BorderSide(
                                  color: Colors.white,
                                  width: 1.5,
                                )
                              : BorderSide.none,
                          shape: isDark
                              ? RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                )
                              : null,
                        ),
                        icon: const Icon(Icons.download),
                        label: Text(
                          Localization.translate('تحديث الكتالوج الآن', lang),
                          style: TextStyle(fontFamily: 'Cairo'),
                        ),
                        onPressed: () async {
                          try {
                            final ready = await _ensureSupabaseCatalogLogin(
                              context,
                            );
                            if (!ready || !context.mounted) return;
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تعذر تسجيل دخول Supabase: $e',
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          showDialog(
                            context: context,
                            useRootNavigator: true,
                            barrierDismissible: false,
                            builder: (_) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                          bool success = false;
                          String errorMsg = '';
                          try {
                            await CloudSyncService().init();
                            await CloudSyncService().downloadGlobalCatalog();
                            success = true;
                          } catch (e) {
                            errorMsg = e.toString();
                          } finally {
                            if (context.mounted) {
                              Navigator.of(context, rootNavigator: true).pop();
                              if (success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      Localization.translate(
                                        'تم تحديث البروفيلات والإكسسوارات بنجاح!',
                                        lang,
                                      ),
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'حدث خطأ: $errorMsg',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          if (settings.userRole == 'admin' || isAdmin)
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
                        Localization.translate(
                          'تصدير / رفع الكتالوج (لمدير التطبيق فقط)',
                          lang,
                        ),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        Localization.translate(
                          'استخدم هذا الزر لرفع الكتالوج الموجود بجهازك حالياً ليصبح هو الكتالوج المركزي في السحابة.',
                          lang,
                        ),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[850]
                              : Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(
                          Icons.cloud_upload,
                          color: Colors.white,
                        ),
                        label: Text(
                          Localization.translate('رفع الكتالوج الآن', lang),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () async {
                          bool ready = false;
                          try {
                            ready = await _ensureSupabaseCatalogLogin(context);
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'تعذر تسجيل دخول Supabase: ${e.toString().replaceAll('Exception: ', '')}',
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                            return;
                          }
                          if (!ready || !context.mounted) return;

                          showDialog(
                            context: context,
                            useRootNavigator: true,
                            barrierDismissible: false,
                            builder: (dialogContext) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                          bool success = false;
                          String errorMsg = '';
                          try {
                            await SupabaseCatalogSyncService()
                                .uploadGlobalCatalog();
                            success = true;
                          } catch (e) {
                            errorMsg = e.toString();
                          } finally {
                            if (context.mounted) {
                              Navigator.of(context, rootNavigator: true).pop();
                              if (success) {
                                final catalogSummary =
                                    SupabaseCatalogSyncService()
                                        .lastCatalogUploadSummary;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      catalogSummary.isEmpty
                                          ? Localization.translate(
                                              'تم رفع الكتالوج المركزي بنجاح!',
                                              lang,
                                            )
                                          : 'تم رفع الكتالوج بنجاح. $catalogSummary',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'حدث خطأ: $errorMsg',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          }
                        },
                      ),
                    ),
                  ],
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
                    Expanded(
                      child: Text(
                        Localization.translate(
                          'نسبة الفائدة (Pourcentage)',
                          lang,
                        ),
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
                        Localization.translate(
                          'مفتاح الذكاء الاصطناعي (Gemini API Key)',
                          lang,
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      subtitle: Text(
                        Localization.translate(
                          'مطلوب لعمل المساعد الصوتي الذكي',
                          lang,
                        ),
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                    TextFormField(
                      initialValue: settings.geminiApiKey,
                      decoration: InputDecoration(
                        hintText: Localization.translate(
                          'ألصق المفتاح هنا...',
                          lang,
                        ),
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
                    Localization.translate(
                      'فتح الصفحات كنوافذ يمكن تحريكها وتصغيرها',
                      lang,
                    ),
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
