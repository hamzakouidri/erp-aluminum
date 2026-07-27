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
import 'dart:async';
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter/foundation.dart' show kIsWeb, PlatformDispatcher;
import 'package:database_data/Commande/texture_cache.dart';

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
      databaseFactory = databaseFactoryFfiWebNoWebWorker;
    }
  } catch (e) {
    debugPrint('SQLite Web init error: $e');
  }

  // Initialize window_manager
  try {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
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
  } catch (e) {
    debugPrint('Window Manager init error: $e');
  }

  // Initialize texture cache for wood drawing textures
  try {
    await TextureCache.init();
  } catch (e) {
    debugPrint('TextureCache init warning: $e');
  }

  String? firebaseError;
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
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<CloudSyncFeedback>? _syncFeedbackSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncFeedbackSubscription = CloudSyncService().syncFeedbackStream.listen(
      _showCloudSyncFeedback,
    );

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
    _syncFeedbackSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _showCloudSyncFeedback(CloudSyncFeedback feedback) {
    // Cloud sync now runs quietly in the background. Only real failures stay
    // visible so the user is not interrupted by routine upload/download
    // progress and success messages.
    if (feedback.type != CloudSyncFeedbackType.uploadFailed &&
        feedback.type != CloudSyncFeedbackType.downloadFailed) {
      return;
    }

    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    final isFailure =
        feedback.type == CloudSyncFeedbackType.uploadFailed ||
        feedback.type == CloudSyncFeedbackType.downloadFailed;
    final isSuccess =
        feedback.type == CloudSyncFeedbackType.uploadSucceeded ||
        feedback.type == CloudSyncFeedbackType.downloadSucceeded;
    final color = isFailure
        ? Colors.red
        : isSuccess
        ? Colors.green
        : feedback.type == CloudSyncFeedbackType.uploadStarted ||
              feedback.type == CloudSyncFeedbackType.downloadStarted
        ? Colors.blue
        : Colors.orange;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: Duration(
          seconds: isFailure
              ? 15
              : feedback.type == CloudSyncFeedbackType.uploadStarted ||
                    feedback.type == CloudSyncFeedbackType.downloadStarted
              ? 5
              : 7,
        ),
        backgroundColor: color,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(feedback.message, style: const TextStyle(fontFamily: 'Cairo')),
            if (feedback.details.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                feedback.details,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
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

    return MaterialApp(
      scaffoldMessengerKey: _scaffoldMessengerKey,
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
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(settings.fontSizeScale)),
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
