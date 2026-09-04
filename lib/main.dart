import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:database_data/Screen/subscription_checker.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/services/supabase_config.dart';
import 'package:database_data/login_screen.dart';
import 'package:database_data/widgets/desktop_window_frame.dart';
import 'package:database_data/widgets/desktop_scroll_behavior.dart';
import 'package:database_data/Screen/app_workspace_shell.dart';
import 'package:database_data/firebase_options.dart';
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter/foundation.dart' show kIsWeb, PlatformDispatcher;
import 'package:database_data/Commande/texture_cache.dart';
import 'package:database_data/Commande/Systeme/cutting_settings.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/services/auth_service.dart';

import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🛡️ حماية شاملة لمنع الانهيار والإغلاق المفاجئ للتطبيق (Crash Prevention)
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Caught Flutter Error: ${details.exception}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Caught Platform Error: $error');
    return true; // تم التعامل مع الخطأ دون إغلاق التطبيق
  };

  // Initialize SQLite for Windows/Linux
  try {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  } catch (e) {
    debugPrint('SQLite FFI init error: $e');
  }

  // Initialize SQLite for Web
  try {
    if (kIsWeb) {
      sqfliteFfiInit();
      databaseFactory = createDatabaseFactoryFfiWeb(
        noWebWorker: true,
        options: SqfliteFfiWebOptions(
          sqlite3WasmUri: Uri.parse('assets/web/sqlite3.wasm'),
        ),
        tag: 'erp_web',
      );
    }
  } catch (e) {
    debugPrint('SQLite Web init error: $e');
  }

  // Initialize window_manager
  try {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.ensureInitialized();
      final WindowOptions windowOptions = Platform.isWindows
          ? const WindowOptions(
              size: Size(1280, 800),
              minimumSize: Size(900, 600),
              center: true,
              backgroundColor: Colors.transparent,
              skipTaskbar: false,
              titleBarStyle: TitleBarStyle.hidden,
              windowButtonVisibility: false,
            )
          : const WindowOptions(
              backgroundColor: Colors.transparent,
              skipTaskbar: false,
            );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
      // Safety guarantee: Ensure window is shown immediately on launch
      await windowManager.show();
      await windowManager.focus();
    }
  } catch (e) {
    debugPrint('Window Manager init error: $e');
  }

  // Initialize texture cache for wood drawing textures
  try {
    await TextureCache.init();
  } catch (e) {
    debugPrint('TextureCache init warning: $e');
  }

  // Load the last saved kerf before any synchronous BOM is generated.
  try {
    final prefs = await SharedPreferences.getInstance();
    CuttingSettings.setSawKerfMm(
      prefs.getDouble('saw_kerf_mm') ?? CuttingSettings.defaultSawKerfMm,
    );
  } catch (e) {
    debugPrint('Cutting settings cache warning: $e');
  }

  String? firebaseError;
  String? supabaseError;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    final errStr = e.toString();
    if (errStr.contains('already-exists') ||
        errStr.contains('already exists')) {
      debugPrint(
        "Firebase was already initialized on the native side. Ignoring error.",
      );
    } else {
      debugPrint("Firebase Initialization Error: $e");
      firebaseError = e.toString();
    }
  }

  try {
    if (SupabaseConfig.isConfigured) {
      await supabase.Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
    }
  } catch (e) {
    debugPrint("Supabase Initialization Error: $e");
    supabaseError = e.toString();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppSettingsProvider()),
        ChangeNotifierProvider(create: (_) => WorkspaceController()),
      ],
      child: MyApp(firebaseError: firebaseError, supabaseError: supabaseError),
    ),
  );
}

class MyApp extends StatefulWidget {
  final String? firebaseError;
  final String? supabaseError;

  const MyApp({super.key, this.firebaseError, this.supabaseError});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // [إضافة هامة]: تهيئة خدمة المزامنة السحابية وبدء الاستماع بمجرد فتح التطبيق مع حماية ضد الانهيار
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (widget.firebaseError != null) return;
        final syncService = CloudSyncService();
        await syncService.init().timeout(const Duration(seconds: 10));
        syncService.startListeningForUpdates(() {
          debugPrint('CloudSyncService: Realtime update received!');
        });
      } catch (e) {
        debugPrint('CloudSyncService post frame init error: $e');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check the server after a device returns from the background. This
      // covers operating systems that suspend Firestore listeners.
      CloudSyncService().refreshFromCloudIfChanged();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      // [تم الإصلاح]: تم إيقاف عملية الرفع الثقيلة هنا لأنها ستُقتل بواسطة النظام.
      // الاعتماد الآن كلياً على الرفع التلقائي (notifyChange) الذي يعمل أثناء تشغيل التطبيق.
      debugPrint(
        "App went to background. Sync is handled silently during active use.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final uiFontFamily = settings.language == AppLanguage.arabic
        ? 'Cairo'
        : 'Arial';

    return MaterialApp(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: Localization.translate('ورشتي', settings.language),
      themeMode: settings.themeMode,
      scrollBehavior: const DesktopScrollBehavior(),
      theme: AppTheme.lightTheme(
        settings.fontSizeScale,
        fontFamily: uiFontFamily,
      ),
      darkTheme: AppTheme.darkTheme(
        settings.fontSizeScale,
        fontFamily: uiFontFamily,
      ),
      builder: (context, child) {
        Widget content = child!;
        if (kIsWeb) {
          content = Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: child,
            ),
          );
        }
        return Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            final handled = DesktopScrollCoordinator.handleKeyEvent(event);
            return handled ? KeyEventResult.handled : KeyEventResult.ignored;
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerHover: DesktopScrollCoordinator.rememberPointerPosition,
            onPointerMove: DesktopScrollCoordinator.rememberPointerPosition,
            onPointerSignal: DesktopScrollCoordinator.handlePointerSignal,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(settings.fontSizeScale)),
              child: content,
            ),
          ),
        );
      },
      home: widget.firebaseError != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    '${Localization.translate('Firebase connection error', settings.language)}:\n${widget.firebaseError}\n\n${Localization.translate('Check your platform setup, for example add Windows support if you run on desktop', settings.language)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 16 * settings.fontSizeScale,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ),
            )
          : StreamBuilder<AppAuthUser?>(
              stream: AppAuthService().authStateChanges,
              initialData: AppAuthService().currentUser,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  const authenticatedContent = SubscriptionChecker();
                  if (!kIsWeb && Platform.isWindows) {
                    return DesktopWindowFrame(
                      topBar: const WorkspaceTabStrip(),
                      child: authenticatedContent,
                    );
                  }
                  return authenticatedContent;
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                return const LoginScreen();
              },
            ),
    );
  }
}
