import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:database_data/Screen/subscription_checker.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/login_screen.dart';
import 'package:database_data/widgets/voice_assistant_overlay.dart';
import 'package:database_data/Screen/app_workspace_shell.dart';
import 'package:database_data/firebase_options.dart';

import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:database_data/Commande/texture_cache.dart';

import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite for Windows/Linux
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize SQLite for Web
  if (kIsWeb) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiWebNoWebWorker;
  }

  // Initialize window_manager
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Initialize texture cache for wood drawing textures
  await TextureCache.init();

  String? firebaseError;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    final errStr = e.toString();
    if (errStr.contains('already-exists') || errStr.contains('already exists')) {
      debugPrint("Firebase was already initialized on the native side. Ignoring error.");
    } else {
      debugPrint("Firebase Initialization Error: $e");
      firebaseError = e.toString();
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppSettingsProvider()),
        ChangeNotifierProvider(create: (_) => WorkspaceController()),
      ],
      child: MyApp(firebaseError: firebaseError),
    ),
  );
}

class MyApp extends StatefulWidget {
  final String? firebaseError;

  const MyApp({super.key, this.firebaseError});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // [إضافة هامة]: تهيئة خدمة المزامنة السحابية وبدء الاستماع بمجرد فتح التطبيق
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.firebaseError != null)
        return; // Prevent crash if Firebase failed
      final syncService = CloudSyncService();
      await syncService.init();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
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

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: Localization.translate('ورشتي', settings.language),
      themeMode: settings.themeMode,
      theme: AppTheme.lightTheme(settings.fontSizeScale).copyWith(
        textTheme: AppTheme.lightTheme(
          settings.fontSizeScale,
        ).textTheme.apply(fontFamily: 'Cairo'),
      ),
      darkTheme: AppTheme.darkTheme(settings.fontSizeScale).copyWith(
        textTheme: AppTheme.darkTheme(
          settings.fontSizeScale,
        ).textTheme.apply(fontFamily: 'Cairo'),
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
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(settings.fontSizeScale),
          ),
          child: VoiceAssistantOverlay(child: content),
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
          : StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              initialData: FirebaseAuth.instance.currentUser,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return const SubscriptionChecker();
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
