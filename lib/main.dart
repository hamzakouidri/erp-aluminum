import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:database_data/Screen/subscription_checker.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/login_screen.dart';
import 'package:database_data/widgets/voice_assistant_overlay.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? firebaseError;
  try {
    // 2. حدث التهيئة لتقرأ الإعدادات الخاصة بمشروعك الجديد
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase Initialization Error: $e");
    firebaseError = e.toString();
  }

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppSettingsProvider())],
      child: MyApp(firebaseError: firebaseError),
    ),
  );
}

// باقي كود الـ MyApp الخاص بك لا يحتاج أي تغيير...

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached || state == AppLifecycleState.inactive) {
      // User is exiting or closing the app, force a sync to Firebase
      try {
        if (FirebaseAuth.instance.currentUser != null) {
          CloudSyncService().backupToCloud();
        }
      } catch (e) {
        debugPrint("Error syncing on exit: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'نظام تصميم النوافذ ERP',
      themeMode: settings.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          primary: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        fontFamily: 'Cairo',
        textTheme: TextTheme(
          bodyMedium: TextStyle(fontSize: 14 * settings.fontSizeScale),
          bodyLarge: TextStyle(fontSize: 16 * settings.fontSizeScale),
          titleLarge: TextStyle(fontSize: 22 * settings.fontSizeScale),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          primary: const Color(0xFF2563EB),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Cairo',
        textTheme: TextTheme(
          bodyMedium: TextStyle(fontSize: 14 * settings.fontSizeScale),
          bodyLarge: TextStyle(fontSize: 16 * settings.fontSizeScale),
          titleLarge: TextStyle(fontSize: 22 * settings.fontSizeScale),
        ),
      ),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(settings.fontSizeScale)),
          child: VoiceAssistantOverlay(child: child!),
        );
      },
      home: widget.firebaseError != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    'حدث خطأ في الاتصال بقاعدة البيانات (Firebase):\n${widget.firebaseError}\n\nتأكد من أنك قمت بإعداد المنصة الصحيحة (مثل إضافة دعم Windows إذا كنت تشغّل التطبيق على الكمبيوتر).',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 16),
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ),
            )
          : StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasData) {
                  return const SubscriptionChecker();
                }
                return const LoginScreen();
              },
            ),
    );
  }
}
