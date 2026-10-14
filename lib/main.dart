import 'dart:async' show unawaited;
import 'Screen/app_workspace_shell.dart';
import 'settings/shortcut_bindings.dart';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show GestureBinding;
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey;
import 'package:firebase_core/firebase_core.dart' as firebase_core;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/app_theme.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/services/supabase_workshop_sync_service.dart';
import 'package:database_data/services/supabase_config.dart';
import 'package:database_data/widgets/auth_session_view.dart';
import 'package:database_data/widgets/desktop_scroll_behavior.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:flutter/foundation.dart' show kIsWeb, PlatformDispatcher;
import 'package:database_data/Commande/Systeme/cutting_settings.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/services/auth_service.dart';
import 'package:database_data/services/order_notification_service.dart';
import 'package:database_data/services/worker_push_notification_service.dart';
import 'package:database_data/Commande/commande.dart';
import 'package:database_data/Screen/treasury_screen.dart';
import 'package:database_data/sql_database.dart';

import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Register before runApp so Android/iOS can enter the background isolate
  // when the application process is suspended or was launched by a push.
  if (kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

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

      if (SupabaseConfig.isConfigured) {
        try {
          await supabase.Supabase.initialize(
            url: SupabaseConfig.url,
            publishableKey: SupabaseConfig.publishableKey,
          ).timeout(const Duration(seconds: 5));
        } catch (supabaseError) {
          debugPrint(
            'Supabase initialization offline/timeout warning: $supabaseError',
          );
          // التطبيق يواصل العمل بدون اتصال بالاعتماد الكامل على قاعدة بيانات SQLite المحلية
        }
      }

      // تهيئة Firebase بأمان لمنع استثناء: No Firebase App '[DEFAULT]' has been created
      try {
        if (firebase_core.Firebase.apps.isEmpty) {
          await firebase_core.Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          ).timeout(const Duration(seconds: 5));
        }
      } catch (firebaseError) {
        debugPrint('Firebase initialization warning: $firebaseError');
      }
      // Initialize notification service (non-blocking — errors are swallowed).
      unawaited(
        OrderNotificationService()
            .initialize()
            .then((_) async {
              final uuid = await OrderNotificationService.readWorkshopUuid();
              if (uuid.isNotEmpty) {
                await OrderNotificationService().subscribeToWorkshop(uuid);
              }
            })
            .catchError((e) {
              debugPrint('OrderNotificationService init warning: $e');
            }),
      );
      unawaited(
        WorkerPushNotificationService.instance.initialize().catchError((e) {
          debugPrint('Worker push notification init warning: $e');
        }),
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
              backgroundColor: Color(0xFF0F2027),
              skipTaskbar: false,
              titleBarStyle: TitleBarStyle.hidden,
              windowButtonVisibility: false,
            )
          : const WindowOptions(backgroundColor: Color(0xFF0F2027));
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.show();
        await windowManager.maximize();
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
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _ready = true;
                              _startupError = null;
                            });
                          },
                          icon: const Icon(Icons.offline_pin_outlined),
                          label: const Text(
                            'المتابعة في وضع عدم الاتصال (أوفلاين)',
                          ),
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

class _DialogButtonCandidate {
  final VoidCallback onPressed;
  final String text;
  final bool isPrimaryType;

  const _DialogButtonCandidate({
    required this.onPressed,
    required this.text,
    required this.isPrimaryType,
  });
}

class _AppDialogObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routeStack = [];

  Route<dynamic>? get topRoute =>
      _routeStack.isNotEmpty ? _routeStack.last : null;

  bool get isDialogOpen {
    final top = topRoute;
    if (top == null) return false;
    return top is PopupRoute;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routeStack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routeStack.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routeStack.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      final index = _routeStack.indexOf(oldRoute);
      if (index != -1 && newRoute != null) {
        _routeStack[index] = newRoute;
      } else {
        _routeStack.remove(oldRoute);
        if (newRoute != null) _routeStack.add(newRoute);
      }
    }
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
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final _AppDialogObserver _dialogObserver = _AppDialogObserver();

  /// الوقت الذي دخل فيه التطبيق إلى الخلفية.
  /// يُستخدم لحساب مدة الغياب قبل السماح بالمزامنة عند الرجوع.
  DateTime? _backgroundedAt;

  /// الحد الأدنى من الوقت في الخلفية قبل إعادة المزامنة عند الرجوع.
  /// 3 دقائق: كافية لتغطية انقطاع الشبكة الحقيقي دون إزعاج المستخدم
  /// عند تبديل التطبيقات للثوانٍ.
  static const Duration _resumeSyncCooldown = Duration(minutes: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && Platform.isWindows) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(
        DesktopScrollCoordinator.handleGlobalPointerEvent,
      );
    }
    WorkerPushNotificationService.instance.setNotificationTapHandler((data) {
      final eventType = data['type']?.toString() ?? '';
      final rawTreasuryId = data['treasury_id'];
      final treasuryId = rawTreasuryId is num
          ? rawTreasuryId.toInt()
          : int.tryParse(rawTreasuryId?.toString() ?? '');
      final rawOrderId = data['order_id'];
      final orderId = rawOrderId is num
          ? rawOrderId.toInt()
          : int.tryParse(rawOrderId?.toString() ?? '');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navigator = _navigatorKey.currentState;
        if (navigator == null || AppAuthService().currentUser == null) return;
        if ((eventType == 'payments' || eventType == 'cashbox') &&
            treasuryId != null &&
            treasuryId > 0) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => TreasuryScreen(
                db: SqlDatabase(),
                initialTransactionId: treasuryId,
              ),
            ),
          );
          return;
        }
        if (orderId == null || orderId <= 0) return;
        navigator.push(
          MaterialPageRoute(builder: (_) => Commande(initialOrderId: orderId)),
        );
      });
    });

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
    if (!kIsWeb && Platform.isWindows) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(
        DesktopScrollCoordinator.handleGlobalPointerEvent,
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Global Dialog Enter Key Handler:
  /// Confirms any open dialog (delete, confirm, save, add, OK, etc.) upon pressing Enter.
  bool _handleDialogEnterKey(KeyDownEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return false;
    }

    // 1. Check if the top route in our navigator is a dialog / popup route:
    final topRoute = _dialogObserver.topRoute;
    if (topRoute != null && topRoute is PopupRoute) {
      if (_confirmDialogRoute(topRoute)) return true;
    }

    // 2. Fallback check: maybe focused widget's ModalRoute is a dialog / popup route:
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext != null) {
      final route = ModalRoute.of(focusedContext);
      if (route != null && route is PopupRoute) {
        if (_confirmDialogRoute(route)) return true;
      }
      // If a button is explicitly focused, activate it even outside popup:
      if (focusedContext.widget is! EditableText &&
          focusedContext.findAncestorWidgetOfExactType<EditableText>() ==
              null) {
        const intent = ActivateIntent();
        final action = Actions.maybeFind<ActivateIntent>(focusedContext);
        if (action != null && action.isEnabled(intent)) {
          Actions.of(
            focusedContext,
          ).invokeAction(action, intent, focusedContext);
          return true;
        }
      }
    }

    return false;
  }

  bool _confirmDialogRoute(Route<dynamic> route) {
    final dialogContext = route is ModalRoute ? route.subtreeContext : null;
    if (dialogContext == null) return false;

    // Check if an explicit widget/button inside the dialog is currently focused:
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext != null) {
      if (focusedContext.widget is EditableText) {
        final editable = focusedContext.widget as EditableText;
        if ((editable.maxLines ?? 1) > 1) {
          // Multiline text input: allow Enter to type a newline
          return false;
        }
        // Single-line text input: pressing Enter confirms the dialog
      } else {
        const intent = ActivateIntent();
        final action = Actions.maybeFind<ActivateIntent>(focusedContext);
        if (action != null && action.isEnabled(intent)) {
          Actions.of(
            focusedContext,
          ).invokeAction(action, intent, focusedContext);
          return true;
        }
      }
    }

    // Collect all interactive buttons within the dialog subtree:
    final candidates = <_DialogButtonCandidate>[];

    void visit(Element element) {
      final widget = element.widget;
      if (widget is ButtonStyleButton && widget.onPressed != null) {
        final text = _extractTextFromElement(element);
        candidates.add(
          _DialogButtonCandidate(
            onPressed: widget.onPressed!,
            text: text,
            isPrimaryType: widget is ElevatedButton || widget is FilledButton,
          ),
        );
      } else if (widget is MaterialButton && widget.onPressed != null) {
        final text = _extractTextFromElement(element);
        candidates.add(
          _DialogButtonCandidate(
            onPressed: widget.onPressed!,
            text: text,
            isPrimaryType: true,
          ),
        );
      } else if (widget is InkWell && widget.onTap != null) {
        final text = _extractTextFromElement(element);
        if (text.isNotEmpty) {
          candidates.add(
            _DialogButtonCandidate(
              onPressed: widget.onTap!,
              text: text,
              isPrimaryType: false,
            ),
          );
        }
      }
      element.visitChildren(visit);
    }

    dialogContext.visitChildElements(visit);

    if (candidates.isEmpty) return false;

    // Pick the best confirmation button
    _DialogButtonCandidate? best;
    int bestScore = -100;

    for (int i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      final score = _scoreDialogButton(
        c.text,
        c.isPrimaryType,
        index: i,
        total: candidates.length,
      );
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }

    if (best != null && bestScore > 0) {
      best.onPressed();
      return true;
    }

    // Fallback: trigger the last non-cancel button
    final nonCancel = candidates.lastWhere(
      (c) => !_isCancelButtonText(c.text),
      orElse: () => candidates.last,
    );
    nonCancel.onPressed();
    return true;
  }

  bool _isCancelButtonText(String text) {
    final lower = text.trim().toLowerCase();
    const cancelKeywords = [
      'إلغاء',
      'الغاء',
      'تراجع',
      'لا',
      'cancel',
      'annuler',
      'non',
      'close',
      'fermer',
      'خروج',
      'إغلاق',
      'اغلاق',
    ];
    return cancelKeywords.any(
      (k) => lower == k || lower.startsWith('$k ') || lower.endsWith(' $k'),
    );
  }

  int _scoreDialogButton(
    String text,
    bool isPrimaryType, {
    required int index,
    required int total,
  }) {
    if (_isCancelButtonText(text)) {
      return -100;
    }

    final lower = text.trim().toLowerCase();
    int score = 10;

    const confirmKeywords = [
      'تأكيد',
      'تاكيد',
      'مسح',
      'حذف',
      'حفظ',
      'نعم',
      'موافق',
      'إضافة',
      'اضافة',
      'تعديل',
      'تطبيق',
      'تم',
      'قبول',
      'متابعة',
      'استمرار',
      'إنشاء',
      'انشاء',
      'confirm',
      'delete',
      'supprimer',
      'effacer',
      'save',
      'yes',
      'oui',
      'ok',
      'valider',
      'enregistrer',
      'ajouter',
      'modifier',
      'appliquer',
      'creer',
      'submit',
      'continuer',
    ];

    for (final kw in confirmKeywords) {
      if (lower.contains(kw)) {
        score += 50;
        break;
      }
    }

    if (isPrimaryType) score += 20;

    // In standard dialogs actions: [cancel, confirm], confirmation is usually the later button
    score += (index * 5);

    return score;
  }

  String _extractTextFromElement(Element root) {
    final buffer = StringBuffer();
    void findText(Element el) {
      if (el.widget is Text) {
        final t = el.widget as Text;
        if (t.data != null) buffer.write(' ${t.data}');
        if (t.textSpan != null) buffer.write(' ${t.textSpan!.toPlainText()}');
      }
      el.visitChildren(findText);
    }

    findText(root);
    return buffer.toString().trim().toLowerCase();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // حساب مدة الغياب في الخلفية.
      // إذا لم يكن في الخلفية مدةً كافية، نتجاهل الـ sync لأن
      // المستمعين في الوقت الحقيقي (Realtime) ما زالوا نشطين.
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      final timeInBackground = backgroundedAt == null
          ? null
          : DateTime.now().difference(backgroundedAt);

      // A Windows focus change emits inactive -> resumed without ever
      // entering paused. In that case [backgroundedAt] is null and there is
      // nothing to resume. Treating null as "sync now" made every click on
      // the taskbar start a full cloud refresh and temporarily starve pointer
      // handling until another page rebuild occurred.
      final shouldSync =
          timeInBackground != null && timeInBackground >= _resumeSyncCooldown;

      if (!shouldSync) {
        debugPrint(
          'App resumed after ${timeInBackground?.inSeconds ?? 0}s — '
          'skipping resume sync (cooldown: ${_resumeSyncCooldown.inSeconds}s). '
          'Realtime listeners are still active.',
        );
        return;
      }

      debugPrint(
        'App resumed after ${timeInBackground.inSeconds}s — '
        'triggering resume sync.',
      );

      // أعد تشغيل الـ background sync timer الذي تم إيقافه عند الدخول للخلفية.
      SupabaseWorkshopSyncService().resumeBackgroundSync();

      // Re-check the server after a device returns from the background. This
      // covers operating systems that suspend Firestore listeners.
      CloudSyncService().refreshFromCloudIfChanged();
      unawaited(
        SupabaseWorkshopSyncService()
            .ensureStarted(timeout: const Duration(seconds: 20))
            .then((ready) async {
              if (ready) {
                await SupabaseWorkshopSyncService().downloadWorkshopData();
              }
            })
            .catchError((error) {
              debugPrint('Workshop sync resume failed: $error');
            }),
      );
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // سجّل الوقت الذي دخل فيه التطبيق إلى الخلفية.
      // inactive يحدث بشكل عابر (نافذة تنبيه، مكالمة...) لذا نتجاهله
      // ونبدأ العد فقط عند paused/detached الحقيقي.
      _backgroundedAt = DateTime.now();
      // أوقف الـ background sync timer حتى لا يبقي العملية مستيقظة.
      SupabaseWorkshopSyncService().pauseBackgroundSync();
      debugPrint(
        'App went to background at $_backgroundedAt. '
        'Resume sync will fire after ${_resumeSyncCooldown.inMinutes} minutes.',
      );
    } else if (state == AppLifecycleState.inactive) {
      // inactive عابر — لا نفعل شيئاً للمزامنة، لكن نقوم بتنظيف مسار الماوس
      // القديم حتى لا يعلق السكرول عند استعادة تركيز النافذة في ويندوز.
      if (!kIsWeb && Platform.isWindows) {
        DesktopScrollCoordinator.resetStaleState();
      }
      debugPrint('App inactive (transient) — no sync change.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final uiFontFamily = settings.language == AppLanguage.arabic
        ? 'Cairo'
        : 'Arial';

    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [_dialogObserver],
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: Localization.translate('ورشتي', settings.language),
      themeMode: settings.themeMode,
      scrollBehavior: const DesktopScrollBehavior(),
      shortcuts: <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            const ActivateIntent(),
      },
      theme: AppTheme.lightTheme(
        settings.fontSizeScale,
        fontFamily: uiFontFamily,
      ),
      darkTheme: AppTheme.darkTheme(
        settings.fontSizeScale,
        fontFamily: uiFontFamily,
      ),
      builder: (context, child) {
        final commandShortcuts = ShortcutBindings.instance;
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
            if (kIsWeb || !Platform.isWindows) return KeyEventResult.ignored;
            if (commandShortcuts.handle(context, event))
              return KeyEventResult.handled;
            final keyboard = HardwareKeyboard.instance;
            final focus = FocusManager.instance.primaryFocus;
            final focusContext = focus?.context;
            if (event is KeyDownEvent &&
                keyboard.isControlPressed &&
                !keyboard.isAltPressed &&
                event.logicalKey == LogicalKeyboardKey.tab &&
                (focusContext == null ||
                    ModalRoute.of(focusContext) is! PopupRoute)) {
              final workspace = context.read<WorkspaceController>();
              final count = workspace.entries.length;
              if (count > 1)
                workspace.activate(
                  (workspace.activeIndex +
                          (keyboard.isShiftPressed ? -1 : 1) +
                          count) %
                      count,
                );
              return KeyEventResult.handled;
            }
            if (event is KeyDownEvent && _handleDialogEnterKey(event)) {
              return KeyEventResult.handled;
            }

            // Keyboard scrolling (Arrow keys, PageUp/Down, Home/End) first
            final handledScroll = DesktopScrollCoordinator.handleKeyEvent(
              event,
            );
            if (handledScroll) {
              return KeyEventResult.handled;
            }

            // Fallback focus traversal for arrow keys only when not consumed by scrolling:
            if (event is KeyDownEvent &&
                focusContext != null &&
                !keyboard.isControlPressed &&
                !keyboard.isAltPressed &&
                !keyboard.isMetaPressed &&
                !keyboard.isShiftPressed &&
                focusContext.widget is! EditableText &&
                focusContext.findAncestorWidgetOfExactType<EditableText>() ==
                    null) {
              final direction = <LogicalKeyboardKey, TraversalDirection>{
                LogicalKeyboardKey.arrowDown: TraversalDirection.down,
                LogicalKeyboardKey.arrowUp: TraversalDirection.up,
                LogicalKeyboardKey.arrowLeft: TraversalDirection.left,
                LogicalKeyboardKey.arrowRight: TraversalDirection.right,
              }[event.logicalKey];
              if (direction != null && focus!.focusInDirection(direction)) {
                return KeyEventResult.handled;
              }
            }

            return KeyEventResult.ignored;
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

      home: AuthSessionView(
        navigatorKey: _navigatorKey,
        authStateChanges: AppAuthService().authStateChanges,
        initialUser: AppAuthService().currentUser,
      ),
    );
  }
}
