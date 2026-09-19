import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:provider/provider.dart';
import 'package:database_data/Screen/subscription_checker.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/app_theme.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/services/supabase_config.dart';
import 'package:database_data/login_screen.dart';
import 'package:database_data/widgets/desktop_window_frame.dart';
import 'package:database_data/widgets/desktop_scroll_behavior.dart';
import 'package:database_data/Screen/app_workspace_shell.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter/foundation.dart' show kIsWeb, PlatformDispatcher;
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

  // Paint the first Flutter frame immediately. Platform services, Supabase,
  // preferences, synchronization, and image decoding are intentionally moved
  // behind this lightweight bootstrap screen.
  runApp(const AppBootstrap());
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  Object? _startupError;
  bool _ready = false;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startServices());
  }

  Future<void> _startServices() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _startupError = null;
    });

    try {
      _configureDatabaseFactory();

      if (!SupabaseConfig.isConfigured) {
        throw StateError('إعدادات Supabase غير مكتملة.');
      }
      await supabase.Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );

      // This is a small local read. It is needed before calculations can run,
      // but no database restore or network synchronization blocks this step.
      try {
        final prefs = await SharedPreferences.getInstance();
        CuttingSettings.setSawKerfMm(
          prefs.getDouble('saw_kerf_mm') ?? CuttingSettings.defaultSawKerfMm,
        );
      } catch (error) {
        debugPrint('Cutting settings cache warning: $error');
      }

      if (!mounted) return;
      setState(() {
        _ready = true;
        _starting = false;
      });

      // Desktop window decoration is cosmetic and must never hold up startup.
      unawaited(_initializeDesktopWindow());
    } catch (error, stack) {
      debugPrint('Application bootstrap failed: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _startupError = error;
        _starting = false;
      });
    }
  }

  void _configureDatabaseFactory() {
    if (kIsWeb) {
      sqfliteFfiInit();
      databaseFactory = createDatabaseFactoryFfiWeb(
        noWebWorker: true,
        options: SqfliteFfiWebOptions(
          sqlite3WasmUri: Uri.parse('assets/web/sqlite3.wasm'),
        ),
        tag: 'erp_web',
      );
    } else if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  Future<void> _initializeDesktopWindow() async {
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return;
    }
    try {
      await windowManager.ensureInitialized();
      final options = Platform.isWindows
          ? const WindowOptions(
              size: Size(1280, 800),
              minimumSize: Size(900, 600),
              center: true,
              backgroundColor: Colors.transparent,
              skipTaskbar: false,
              titleBarStyle: TitleBarStyle.hidden,
              windowButtonVisibility: false,
            )
          : const WindowOptions(backgroundColor: Colors.transparent);
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (error) {
      debugPrint('Window Manager init warning: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppSettingsProvider()),
          ChangeNotifierProvider(create: (_) => WorkspaceController()),
        ],
        child: const MyApp(),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _startupError == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.home_repair_service, size: 64),
                        SizedBox(height: 20),
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('جاري تجهيز التطبيق…'),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off, size: 56),
                        const SizedBox(height: 16),
                        const Text(
                          'تعذر الاتصال بـ Supabase.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _startupError.toString(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _starting ? null : _startServices,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

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

  /// Desktop dialogs already expose focusable Material buttons, but a root
  /// keyboard listener can otherwise leave Enter unhandled after Tab/arrow
  /// navigation. Invoke the focused dialog button directly so Yes/No always
  /// performs the action currently highlighted by the keyboard.
  bool _activateFocusedDialogButton(KeyDownEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return false;
    }
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) return false;
    final inDialog =
        focusedContext.findAncestorWidgetOfExactType<AlertDialog>() != null ||
        focusedContext.findAncestorWidgetOfExactType<SimpleDialog>() != null;
    if (!inDialog ||
        focusedContext.findAncestorWidgetOfExactType<ButtonStyleButton>() ==
            null) {
      return false;
    }
    return Actions.maybeInvoke(focusedContext, const ActivateIntent()) != null;
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
            if (event is KeyDownEvent && _activateFocusedDialogButton(event)) {
              return KeyEventResult.handled;
            }
            final handled = DesktopScrollCoordinator.handleKeyEvent(event);
            return handled ? KeyEventResult.handled : KeyEventResult.ignored;
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerHover: DesktopScrollCoordinator.rememberPointerPosition,
            onPointerMove: DesktopScrollCoordinator.rememberPointerPosition,
            // Every page, dialog and nested list now participates in the
            // desktop fallback. Flutter still handles the nearest scrollable
            // first; this only continues to a parent when that child reached
            // its beginning/end.
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
      home: StreamBuilder<AppAuthUser?>(
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
          final loginContent = const LoginScreen();
          if (!kIsWeb && Platform.isWindows) {
            return DesktopWindowFrame(child: loginContent);
          }
          return loginContent;
        },
      ),
    );
  }
}
